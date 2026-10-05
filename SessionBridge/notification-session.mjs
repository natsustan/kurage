// Resolve only from the synchronized, authenticated workspace's metadata.
// No document body is opened, no stream is created, and no permission is answered.
export async function notificationSessionDestination(repo, sessionID, signal) {
  signal?.throwIfAborted();
  const rows = await repo.listDoc();
  signal?.throwIfAborted();
  const visible = row => row && row.docId?.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted &&
    row.exists !== false && row.e !== false && row.meta && !row.meta.isArchived;
  const current = rows.find(row => row.docId === `session-${sessionID}` && visible(row));
  if (!current || current.meta.childSessionPlacement === 'side-panel') return null;
  const rootSessionID = current.meta.parentSessionId ?? sessionID;
  const root = rows.find(row => row.docId === `session-${rootSessionID}` && visible(row));
  if (!root || root.meta.parentSessionId) return null;
  return { rootSessionID, sessionID, isTabClosed: current.meta.isTabClosed === true };
}
