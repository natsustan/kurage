function synced(report) {
  return report.outcome === 'synced';
}

export async function cancelSession(repo, sessionID) {
  const docID = `session-${sessionID}`;
  const row = (await repo.listDoc()).find(entry => entry.docId === docID && !entry.deleted);
  if (!row || row.meta.isArchived || row.meta.parentSessionId) {
    throw new Error('Session is unavailable in this workspace');
  }
  const handle = await repo.openPersistedDoc(docID);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    throw new Error('Session history sync failed');
  }
  const history = handle.doc.getList('history').toJSON();
  const latestAssistant = history.findLast(entry => entry?.role === 'assistant');
  if (!latestAssistant || latestAssistant.finished === true ||
      typeof latestAssistant.endedAt === 'number' ||
      typeof latestAssistant.id !== 'string' || !latestAssistant.id) return 'unavailable';

  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    throw new Error('Session metadata sync failed');
  }
  const current = await repo.getDocMeta(docID);
  if (!current || current.deleted || current.meta.isArchived ||
      !['running', 'initializing', 'requestPermission'].includes(current.meta.status?.type)) {
    return 'unavailable';
  }
  if (current.meta.lastCanceledTurn !== latestAssistant.id) {
    await repo.upsertDocMeta(docID, { lastCanceledTurn: latestAssistant.id });
  }
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    throw new Error('Session cancellation sync failed');
  }
  const confirmed = await repo.getDocMeta(docID);
  return confirmed?.meta.lastCanceledTurn === latestAssistant.id ? 'requested' : 'unconfirmed';
}
