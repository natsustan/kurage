import { LoroList, LoroMap, LoroText } from 'loro-crdt';

function synced(report) {
  return report.outcome === 'synced';
}

// A retry keeps its turn ID. If the body reached Streams before the reply was
// lost, only the dispatch pointer needs another attempt.
export async function sendText(repo, sessionID, turnID, userID, text, timestamp) {
  const docID = `session-${sessionID}`;
  const row = (await repo.listDoc()).find(entry => entry.docId === docID && !entry.deleted);
  if (!row || row.meta.isArchived || row.meta.parentSessionId) {
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
  if (existing) {
    if (existing.role !== 'user' || existing.userId !== userID ||
        existing.items?.[0]?.text !== text) {
      throw new Error('Message ID belongs to another turn');
    }
    if (row.meta.lastHandledUserMsgId === turnID ||
        ['completed', 'cancelled', 'failed'].includes(existing.status)) return 'sent';
    const newerActivation = row.meta.latestUserMsgId;
    if (newerActivation && newerActivation !== turnID) {
      const activationIndex = entries.findIndex(entry => entry?.id === newerActivation);
      if (activationIndex < 0) return 'unconfirmed';
      if (activationIndex > entries.indexOf(existing)) return 'superseded';
    }
  } else {
    // Direct dispatch is for an idle session. Steering a running turn and
    // replying to a permission request have different Lody protocols.
    if (status?.type !== 'idle' ||
        (row.meta.latestUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.lastHandledUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.lastMissingHistoryUserMsgId &&
         row.meta.latestUserMsgId !== row.meta.settledActivationUserMsgId)) {
      return 'busy';
    }
    const lastConfig = [...entries].reverse()
      .find(entry => entry?.role === 'user' && entry.inputConfig)?.inputConfig ?? {};
    const config = {
      prompt: text, inputBlocks: [{ type: 'text', text }], cliType, agentType,
    };
    for (const key of ['modeId', 'modelId', 'configOptionValues', 'mcpServerIds',
      'agentRoleId', 'agentRoleRevision', 'chainDepth']) {
      if (lastConfig[key] !== undefined) config[key] = lastConfig[key];
    }
    if (typeof row.meta.acpSessionId === 'string' && row.meta.acpSessionId) {
      config.resume = row.meta.acpSessionId;
    }
    const turn = history.insertContainer(history.length, new LoroMap());
    turn.set('id', turnID);
    turn.set('userId', userID);
    turn.set('role', 'user');
    turn.set('timestamp', timestamp);
    turn.set('status', 'pending');
    turn.set('read', false);
    turn.set('fileDiff', []);
    turn.set('finished', true);
    const items = turn.setContainer('items', new LoroList());
    const item = items.insertContainer(0, new LoroMap());
    item.set('type', 'text');
    item.setContainer('text', new LoroText()).update(text);
    const inputConfig = turn.setContainer('inputConfig', new LoroMap());
    for (const [key, value] of Object.entries(config)) inputConfig.set(key, value);
    handle.doc.commit();
  }
  // A failure after the local commit is ambiguous; the same turn ID can be
  // retried safely. Never publish the activation before the body is confirmed.
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  await repo.upsertDocMeta(docID, { latestUserMsgId: turnID, lastMessageAt: Date.now() });
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  return 'sent';
}
