import { projectSessionActivity } from './session-activity.mjs';

// A tab is a child of the root that is not a side panel and is not nested under
// another child. Rows that carry a missing parent stay permissive: an archived
// or deleted root must not turn a visible tab into an unusable one.
export function isSessionTab(row, rows) {
  const parentID = row?.meta?.parentSessionId;
  if (!parentID || row.meta.childSessionPlacement === 'side-panel') return false;
  const parent = rows.find(entry => entry.docId === `session-${parentID}`);
  return !parent || !parent.meta?.parentSessionId;
}

export function projectSessionTabs(rows, sessionID) {
  const sessions = rows.filter(row => row.docId?.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta?.isArchived);
  const current = sessions.find(row => row.docId === `session-${sessionID}`);
  if (!current) return [];
  const rootID = current.meta.parentSessionId || sessionID;
  const root = sessions.find(row => row.docId === `session-${rootID}` && !row.meta.parentSessionId);
  if (!root) return [];
  return [root, ...sessions.filter(row => row.meta.parentSessionId === rootID &&
    row.meta.childSessionPlacement !== 'side-panel').sort((a, b) =>
    (a.meta.createdAt ?? '').localeCompare(b.meta.createdAt ?? '') || a.docId.localeCompare(b.docId))]
    .map(row => ({
      id: row.docId.slice('session-'.length), title: row.meta.title || 'Untitled session',
      agentName: row.meta.agentType ?? row.meta.cliType ?? 'Agent',
      activity: projectSessionActivity(row.meta.status), preview: '',
      parentSessionID: row.meta.parentSessionId ?? null,
      isTabClosed: row.meta.isTabClosed === true,
      lastMessageAt: Number.isFinite(row.meta.lastMessageAt) ? row.meta.lastMessageAt : null,
      lastReadAt: Number.isFinite(row.meta.lastReadAt) ? row.meta.lastReadAt : null,
    }));
}

// Closed tabs can still be working. Only live direct tabs contribute to the
// root row; side panels, nested children and removed documents do not.
export function runningSessionTabParents(rows) {
  const sessions = rows.filter(row => row.docId?.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta?.isArchived);
  const rootIDs = new Set(sessions.filter(row => !row.meta?.parentSessionId)
    .map(row => row.docId.slice('session-'.length)));
  return new Set(sessions.filter(row => rootIDs.has(row.meta?.parentSessionId) &&
    row.meta.childSessionPlacement !== 'side-panel' &&
    projectSessionActivity(row.meta.status) === 'running').map(row => row.meta.parentSessionId));
}
