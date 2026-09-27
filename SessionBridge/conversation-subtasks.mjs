// Child tabs share their parent's workspace. Keep them out of the root list,
// but expose their metadata in that parent's conversation, including archived
// tasks so their results remain discoverable. Never open child documents here.
export function projectSubtasks(sessionID, rows) {
  return rows.filter(row => row.docId?.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted &&
    row.docId !== `session-${sessionID}` && row.meta?.parentSessionId === sessionID)
    .sort((a, b) => (Date.parse(a.meta.createdAt ?? '') || 0) -
      (Date.parse(b.meta.createdAt ?? '') || 0) || a.docId.localeCompare(b.docId))
    .map(row => {
      const meta = row.meta;
      const type = meta.status?.type;
      const status = meta.isArchived ? 'archived' :
        type === 'requestPermission' ? 'waitingForInput' :
        type === 'initializing' ? 'starting' : type === 'running' ? 'running' : 'idle';
      return {
        id: row.docId.slice('session-'.length),
        title: typeof meta.title === 'string' && meta.title.trim() ? meta.title : 'Untitled subtask',
        agentName: meta.agentType || meta.cliType || 'Agent',
        status,
      };
    });
}
