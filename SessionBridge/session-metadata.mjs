// Match Lody updateSessionTitle / setSessionPinned; preserve unrelated metadata.
export async function updateSessionMetadata(repo, sessionID, change, signal) {
  signal?.throwIfAborted();
  const docID = `session-${sessionID}`;
  const row = await repo.getDocMeta(docID);
  signal?.throwIfAborted();
  if (!row || row.deleted || row.exists === false || row.e === false || !row.meta || row.meta.isArchived) return 'missing';
  let patch;
  if (typeof change.isTabClosed === 'boolean') {
    if (!row.meta.parentSessionId || row.meta.childSessionPlacement === 'side-panel') return 'invalid';
    patch = { isTabClosed: change.isTabClosed };
  } else if (Number.isFinite(change.lastReadAt)) {
    patch = { lastReadAt: Math.max(change.lastReadAt, Number.isFinite(row.meta.lastReadAt) ? row.meta.lastReadAt : change.lastReadAt) };
  } else if (typeof change.isPinned === 'boolean') {
    patch = { isPinned: change.isPinned };
  } else if (typeof change.title === 'string' && change.title.trim() && change.title.trim().length <= 200) {
    patch = { title: change.title.trim(), titleSource: 'user' };
  } else {
    return 'invalid';
  }
  await repo.upsertDocMeta(docID, patch);
  signal?.throwIfAborted();
  const report = await repo.sync({ scope: 'meta', requireTransports: ['cloud'], signal });
  signal?.throwIfAborted();
  if (report?.outcome !== 'synced' && report?.ok !== true) return 'unconfirmed';
  const confirmed = await repo.getDocMeta(docID);
  signal?.throwIfAborted();
  if (!confirmed || confirmed.deleted || confirmed.exists === false || confirmed.e === false || confirmed.meta?.isArchived) return 'unconfirmed';
  return Object.entries(patch).every(([key, value]) => (key === 'lastReadAt' ? Number.isFinite(confirmed.meta?.[key]) && confirmed.meta[key] >= value : confirmed.meta?.[key] === value))
    ? 'updated' : 'unconfirmed';
}
