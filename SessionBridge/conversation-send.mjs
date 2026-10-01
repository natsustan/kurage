import { LoroList, LoroMap, LoroText } from 'loro-crdt';
import { applyRunConfigChoice, effectiveRunConfig, latestUserTurn } from './run-config.mjs';
import { isSessionTab } from './session-tabs.mjs';
import { deliveryOutcome } from './conversation-delivery.mjs';

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

function competingActivation(meta, entries, turnID, followUp = false) {
  const otherID = meta.latestUserMsgId;
  if (!otherID || otherID === turnID) return null;
  const otherIndex = entries.findIndex(entry => entry?.id === otherID);
  if (otherIndex < 0) return 'unconfirmed';
  if (otherIndex > entries.findIndex(entry => entry?.id === turnID)) return 'superseded';
  if (followUp && (meta.processingUserMsgId === otherID || entries[otherIndex]?.status === 'processing')) return null;
  if (otherID !== meta.lastHandledUserMsgId &&
      otherID !== meta.lastMissingHistoryUserMsgId &&
      otherID !== meta.settledActivationUserMsgId) return 'unconfirmed';
  return null;
}

// A retry keeps its user turn, configuration, and original steer target.
// Steer offers its payload while history uploads; ordinary activation follows
// durable history. An ephemeral writer stays alive until its upload settles.
// `runConfig` changes one model or reasoning value, and only for a new turn.
export async function sendText(repo, sessionID, turnID, userID, text, timestamp, runConfig, attachments = [], steering) {
  const docID = `session-${sessionID}`;
  const rows = await repo.listDoc();
  const row = rows.find(entry => entry.docId === docID && !entry.deleted);
  if (!row || row.meta.isArchived || (row.meta.parentSessionId && !isSessionTab(row, rows))) {
    throw new Error('Session is unavailable in this workspace');
  }
  const { cliType, agentType } = row.meta;
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
  const refreshed = await repo.getDocMeta(docID);
  if (!refreshed || refreshed.deleted || refreshed.meta.isArchived) return 'unconfirmed';
  row.meta = refreshed.meta;
  if (row.meta.lastMissingHistoryUserMsgId === turnID) return 'rejected';
  // Replay the same CRDT operations, not a second insertion with the same
  // domain ID, when a cancelled/failed upload never reached another replica.
  if (steering?.state.authoredUpdate) handle.doc.import(steering.state.authoredUpdate);
  const entries = history.toJSON();
  const existing = entries.find(entry => entry?.id === turnID);
  let steerTarget;
  if (existing) {
    assertSameTurn(existing, userID, text, attachments);
    const outcome = deliveryOutcome(existing, row.meta);
    if (outcome && !steering?.state.authoredUpdate) return outcome;
    if (outcome === 'rejected' || outcome === 'unconfirmed') return outcome;
    if (outcome === 'sent') {
      if (!await uploadHistory(repo, docID, steering.signal)) return 'unconfirmed';
      delete steering.state.authoredUpdate;
      return 'sent';
    }
    if (existing.status === 'pending_apply') {
      // Keep the original target in process memory. CRDT merges can insert
      // another assistant before this user entry, so ordering is not a retry key.
      steerTarget = steering?.state.expectedTurnID;
      if (!steering || !steerTarget) return 'unconfirmed';
    } else {
      const conflict = competingActivation(row.meta, entries, turnID, steering?.state.followUp);
      if (conflict) return conflict;
    }
  } else {
    if (row.meta.status?.type !== 'idle') {
      const assistant = entries.findLast(entry => entry?.role === 'assistant');
      if (!steering || !['running', 'initializing', 'requestPermission'].includes(row.meta.status?.type) ||
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
    const before = handle.doc.version();
    appendUserTurn(history, { turnID, userID, text, timestamp, config,
      status: steerTarget ? 'pending_apply' : 'pending' });
    handle.doc.commit();
    if (steerTarget) steering.state.authoredUpdate = handle.doc.export({ mode: 'update', from: before });
  }
  if (steerTarget) {
    const upload = uploadHistory(repo, docID, steering.signal);
    return await steerTurn(repo, sessionID, handle.doc, row.meta, turnID, steerTarget, steering, upload);
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
  if (currentMeta.lastMissingHistoryUserMsgId === turnID) return 'rejected';
  const outcome = deliveryOutcome(history.toJSON().find(turn => turn?.id === turnID), currentMeta);
  if (outcome) return outcome;
  if (currentMeta.lastHandledUserMsgId === turnID ||
      currentMeta.latestUserMsgId === turnID) return 'sent';
  const conflict = competingActivation(currentMeta, history.toJSON(), turnID, steering?.state.followUp);
  if (conflict) return conflict;
  if (currentMeta.status?.type !== 'idle' && !steering?.state.followUp) return 'unconfirmed';

  // The pinned LoroRepo has no conditional metadata write. Confirm the merged
  // pointer after syncing instead of reporting a competing write as sent.
  await repo.upsertDocMeta(docID, { latestUserMsgId: turnID, lastMessageAt: Date.now() });
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const confirmed = await repo.getDocMeta(docID);
  if (confirmed?.meta.lastMissingHistoryUserMsgId === turnID) return 'rejected';
  return confirmed?.meta.latestUserMsgId === turnID ||
    confirmed?.meta.lastHandledUserMsgId === turnID ? 'sent' : 'unconfirmed';
}

async function uploadHistory(repo, docID, signal) {
  try {
    return synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'], signal }));
  } catch { return false; }
}

async function steerTurn(repo, sessionID, doc, meta, turnID, expectedTurnId, steering, upload) {
  const history = doc.getList('history');
  const entry = history.toJSON().find(turn => turn?.id === turnID);
  const params = { sessionId: sessionID, expectedTurnId, userTurnId: turnID,
    userId: entry.userId, timestamp: entry.timestamp, inputConfig: entry.inputConfig };
  let response;
  try {
    steering.signal?.throwIfAborted();
    response = steering.state.applied
      ? { type: 'session/steer_response', sessionId: sessionID, userTurnId: turnID, applied: true }
      : steering.state.deliveryUnknown ? undefined : await steering.request(meta.machineId, params);
    if (response?.type === 'session/steer_response' && response.sessionId === sessionID &&
        response.userTurnId === turnID && response.recoveryOwned && response.disposition === 'promotion-failed') {
      // Only the daemon can repair its own recovery activation safely.
      response = await steering.request(meta.machineId, params);
    }
  } catch {
    // The RPC may already have reached the provider. Retain this turn for
    // same-ID recovery; never publish an ordinary activation after a timeout.
    response = undefined;
  }
  const matched = response?.type === 'session/steer_response' && response.sessionId === sessionID &&
    response.userTurnId === turnID;
  if (matched && response.disposition === 'delivery-unknown') steering.state.deliveryUnknown = true;
  if (matched && response.applied === true) {
    steering.state.applied = true;
    const index = history.toJSON().findIndex(turn => turn?.id === turnID);
    if (!steering.signal?.aborted && history.get(index)?.get('status') === 'pending_apply') {
      history.get(index).set('status', 'processing');
      history.get(index).set('read', true);
      history.get(index).get('inputConfig').set('_lodyDeliveryKind', 'steer');
      doc.commit();
    }
  }
  // Do not destroy this replica while its original insertion is uploading.
  const uploaded = await upload;
  steering.signal?.throwIfAborted();
  if (!uploaded) return 'unconfirmed';
  delete steering.state.authoredUpdate;
  if (!await uploadHistory(repo, `session-${sessionID}`, steering.signal)) return 'unconfirmed';
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'], signal: steering.signal }))) return 'unconfirmed';
  steering.signal?.throwIfAborted();
  const confirmed = await repo.getDocMeta(`session-${sessionID}`);
  if (!confirmed || confirmed.deleted || confirmed.meta.isArchived) return 'unconfirmed';
  const outcome = deliveryOutcome(history.toJSON().find(turn => turn?.id === turnID), confirmed.meta);
  if (outcome) return outcome;
  if (!matched || response.recoveryOwned) return 'unconfirmed';
  if (['no-active-turn', 'promotion-failed'].includes(response.disposition)) {
    // Legacy machines can prove non-delivery without owning recovery. Reuse
    // this exact turn; the ordinary path still checks competing activations.
    const index = history.toJSON().findIndex(turn => turn?.id === turnID);
    const status = history.get(index)?.get('status');
    if (status === 'pending_apply') {
      history.get(index).set('status', 'pending');
      doc.commit();
    } else if (!['pending', 'seen'].includes(status)) return 'unconfirmed';
    steering.state.followUp = true;
    return await sendText(repo, sessionID, turnID, entry.userId, entry.items[0].text,
      entry.timestamp, undefined, entry.inputConfig.inputBlocks.filter(block => block.type !== 'text'), steering);
  }
  return 'unconfirmed';
}
