import { LoroList, LoroMap, LoroText } from 'loro-crdt';
import { applyRunConfigChoice, effectiveRunConfig, latestUserTurn } from './run-config.mjs';
import { isSessionTab } from './session-tabs.mjs';

export function synced(report) {
  return report.outcome === 'synced';
}

// Values a new turn inherits from the turn before it.
export const INHERITED_TURN_CONFIG_KEYS = ['modeId', 'modelId', 'configOptionValues', 'mcpServerIds',
  'agentRoleId', 'agentRoleRevision', 'chainDepth'];

export function appendUserTurn(history, { turnID, userID, text, timestamp, config, status = 'pending' }) {
  const turn = history.insertContainer(history.length, new LoroMap());
  turn.set('id', turnID);
  turn.set('userId', userID);
  turn.set('role', 'user');
  turn.set('timestamp', timestamp);
  turn.set('status', status);
  turn.set('read', false);
  turn.set('fileDiff', []);
  turn.set('finished', true);
  const items = turn.setContainer('items', new LoroList());
  const item = items.insertContainer(0, new LoroMap());
  item.set('type', 'text');
  item.setContainer('text', new LoroText()).update(text);
  for (const block of config.inputBlocks ?? []) {
    if (block.type === 'text') continue;
    const attachment = items.insertContainer(items.length, new LoroMap());
    for (const [key, value] of Object.entries(block)) attachment.set(key, value);
  }
  const inputConfig = turn.setContainer('inputConfig', new LoroMap());
  for (const [key, value] of Object.entries(config)) inputConfig.set(key, value);
}

export const canonical = value => JSON.stringify(value, (_key, item) =>
  item && typeof item === "object" && !Array.isArray(item)
    ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a.localeCompare(b))) : item);

// A retry must name the same user turn it first wrote.
export function assertSameTurn(existing, userID, text, attachments = []) {
  if (existing.role !== 'user' || existing.userId !== userID ||
      existing.items?.[0]?.text !== text ||
      canonical(existing.inputConfig?.inputBlocks?.filter(block => block.type !== 'text') ?? []) !== canonical(attachments)) {
    throw new Error('Message ID belongs to another turn');
  }
}

function competingActivation(meta, entries, turnID) {
  const otherID = meta.latestUserMsgId;
  if (!otherID || otherID === turnID) return null;
  const otherIndex = entries.findIndex(entry => entry?.id === otherID);
  if (otherIndex < 0) return 'unconfirmed';
  if (otherIndex > entries.findIndex(entry => entry?.id === turnID)) return 'superseded';
  if (otherID !== meta.lastHandledUserMsgId &&
      otherID !== meta.lastMissingHistoryUserMsgId &&
      otherID !== meta.settledActivationUserMsgId) return 'unconfirmed';
  return null;
}

const deliveredStatuses = ['processing', 'handled', 'canceled', 'failed', 'completed', 'cancelled'];

// A retry keeps its user turn, configuration, and original steer target.
// Both dispatch routes wait for the body to reach Streams before submission.
// `runConfig` changes one model or reasoning value, and only for a new turn.
export async function sendText(repo, sessionID, turnID, userID, text, timestamp, runConfig, attachments = [], steering) {
  const docID = `session-${sessionID}`;
  const rows = await repo.listDoc();
  const row = rows.find(entry => entry.docId === docID && !entry.deleted);
  if (!row || row.meta.isArchived || (row.meta.parentSessionId && !isSessionTab(row, rows))) {
    throw new Error('Session is unavailable in this workspace');
  }
  const { cliType, agentType, status } = row.meta;
  if (typeof userID !== 'string' || !userID ||
      typeof cliType !== 'string' || !cliType ||
      typeof agentType !== 'string' || !agentType) {
    throw new Error('Session dispatch configuration is unavailable');
  }
  const handle = await repo.openPersistedDoc(docID);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    throw new Error('Session history sync failed');
  }
  const history = handle.doc.getList('history');
  const entries = history.toJSON();
  const existing = entries.find(entry => entry?.id === turnID);
  let steerTarget;
  if (existing) {
    assertSameTurn(existing, userID, text, attachments);
    if (row.meta.lastHandledUserMsgId === turnID ||
        deliveredStatuses.includes(existing.status)) return 'sent';
    if (row.meta.steerTurnStatuses?.[turnID] === 'delivery_unknown' || existing.status === 'delivery_unknown') return 'unconfirmed';
    if (acceptedSteer(row.meta, turnID)) return 'sent';
    if (existing.status === 'pending_apply') {
      // Keep the original target in process memory. CRDT merges can insert
      // another assistant before this user entry, so ordering is not a retry key.
      steerTarget = steering?.state.expectedTurnID;
      if (!steering || !steerTarget) return 'unconfirmed';
    } else {
      const conflict = competingActivation(row.meta, entries, turnID);
      if (conflict) return conflict;
    }
  } else {
    if (status?.type !== 'idle') {
      const assistant = entries.findLast(entry => entry?.role === 'assistant');
      if (!steering || !['running', 'initializing', 'requestPermission'].includes(status?.type) ||
          typeof assistant?.id !== 'string' || !assistant.id ||
          assistant.finished === true || typeof assistant.endedAt === 'number' ||
          typeof row.meta.machineId !== 'string' || !row.meta.machineId) return 'busy';
      steerTarget = assistant.id;
      steering.state.expectedTurnID = steerTarget;
    } else if (row.meta.latestUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.lastHandledUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.lastMissingHistoryUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.settledActivationUserMsgId) {
      return 'busy';
    }
    const lastConfig = effectiveRunConfig(
      latestUserTurn(entries), handle.doc.getMap('acpRuntimeConfig').toJSON(),
    );
    let config = {
      prompt: text, inputBlocks: [{ type: 'text', text }, ...attachments], cliType, agentType,
    };
    for (const key of INHERITED_TURN_CONFIG_KEYS) {
      if (lastConfig[key] !== undefined) config[key] = lastConfig[key];
    }
    config = applyRunConfigChoice(config, runConfig);
    if (typeof row.meta.acpSessionId === 'string' && row.meta.acpSessionId) {
      config.resume = row.meta.acpSessionId;
    }
    appendUserTurn(history, { turnID, userID, text, timestamp, config,
      status: steerTarget ? 'pending_apply' : 'pending' });
    handle.doc.commit();
  }
  // A failure after the local commit is ambiguous; the same turn ID can be
  // retried safely. Never publish the activation before the body is confirmed.
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  // Metadata and history sync independently. Recheck after the body is durable
  // so an activation written while it synced cannot be overwritten blindly.
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const current = await repo.getDocMeta(docID);
  if (!current || current.deleted) return 'unconfirmed';
  const currentMeta = current.meta;
  if (currentMeta.isArchived) return 'unconfirmed';
  if (steerTarget) {
    return await steerTurn(repo, sessionID, history, currentMeta, turnID, steerTarget, steering);
  }
  if (currentMeta.lastHandledUserMsgId === turnID ||
      currentMeta.latestUserMsgId === turnID) return 'sent';
  const conflict = competingActivation(currentMeta, history.toJSON(), turnID);
  if (conflict) return conflict;
  if (currentMeta.status?.type !== 'idle') return 'unconfirmed';

  // The pinned LoroRepo has no conditional metadata write. Confirm the merged
  // pointer after syncing instead of reporting a competing write as sent.
  await repo.upsertDocMeta(docID, { latestUserMsgId: turnID, lastMessageAt: Date.now() });
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const confirmed = await repo.getDocMeta(docID);
  return confirmed?.meta.latestUserMsgId === turnID ||
    confirmed?.meta.lastHandledUserMsgId === turnID ? 'sent' : 'unconfirmed';
}

function acceptedSteer(meta, turnID) {
  return ['pending', 'processing', 'handled', 'failed', 'canceled'].includes(meta.steerTurnStatuses?.[turnID]);
}

async function steerTurn(repo, sessionID, history, meta, turnID, expectedTurnId, steering) {
  const entry = history.toJSON().find(turn => turn?.id === turnID);
  if (meta.lastHandledUserMsgId === turnID || acceptedSteer(meta, turnID) ||
      deliveredStatuses.includes(entry?.status)) return 'sent';
  if (meta.steerTurnStatuses?.[turnID] === 'delivery_unknown' || entry?.status === 'delivery_unknown') {
    return 'unconfirmed';
  }
  if (!entry || !meta.machineId) return 'unconfirmed';
  const params = { sessionId: sessionID, expectedTurnId, userTurnId: turnID,
    userId: entry.userId, timestamp: entry.timestamp, inputConfig: entry.inputConfig };
  let response;
  try {
    response = await steering.request(meta.machineId, params);
    if (response?.recoveryOwned && response.disposition === 'promotion-failed') {
      // Only the daemon can repair its own recovery activation safely.
      response = await steering.request(meta.machineId, params);
    }
  } catch {
    // The RPC may already have reached the provider. Retain this turn for
    // same-ID recovery; never publish an ordinary activation after a timeout.
    return 'unconfirmed';
  }
  if (response?.type !== 'session/steer_response' || response.sessionId !== sessionID ||
      response.userTurnId !== turnID) return 'unconfirmed';
  if (response.applied === true) return 'sent';
  if (response.recoveryOwned) {
    if (!synced(await repo.sync({ scope: 'doc', docIds: [`session-${sessionID}`], requireTransports: ['cloud'] }))) {
      return 'unconfirmed';
    }
    if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
    const confirmed = await repo.getDocMeta(`session-${sessionID}`);
    const recovered = history.toJSON().find(turn => turn?.id === turnID);
    return acceptedSteer(confirmed?.meta ?? {}, turnID) ||
      confirmed?.meta.lastHandledUserMsgId === turnID || deliveredStatuses.includes(recovered?.status)
      ? 'sent' : 'unconfirmed';
  }
  if (['no-active-turn', 'promotion-failed'].includes(response.disposition)) {
    // Legacy machines can prove non-delivery without owning recovery. Reuse
    // this exact turn; the ordinary path still checks competing activations.
    const index = history.toJSON().findIndex(turn => turn?.id === turnID);
    if (history.get(index)?.get('status') !== 'pending_apply') return 'unconfirmed';
    history.get(index).set('status', 'pending');
    (await repo.openPersistedDoc(`session-${sessionID}`)).doc.commit();
    return await sendText(repo, sessionID, turnID, entry.userId, entry.items[0].text,
      entry.timestamp, undefined, entry.inputConfig.inputBlocks.filter(block => block.type !== 'text'));
  }
  return 'unconfirmed';
}
