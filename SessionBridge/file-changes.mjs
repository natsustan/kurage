// SessionHistory.fileDiff is a per-turn summary, not the current Git worktree.
// Completed ACP diff blocks are optional historical text evidence. Never infer
// modifications from tool names, locations, shell output, or failed calls.
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const sumCounts = (left, right) => left === null || right === null ? null : count(left + right);
const validPath = value => typeof value === 'string' && value.trim() && !value.includes('\0');
// Match Lody's display-path normalization; never guess a root from suffixes.
const normalizedPath = value => value.replace(/\\/g, '/').replace(/^\.\/+/, '');
const validOpID = value => value === undefined ||
  (typeof value === 'string' && value.length <= 128 && /^\d+:\d+$/.test(value));

export function projectFileChanges(history) {
  const groups = [];
  let textBudget = 512 * 1024;
  let turnNumber = 0;
  for (const turn of history) {
    if (turn?.role === 'user') turnNumber += 1;
    if (turn?.role !== 'assistant' || typeof turn.id !== 'string') continue;
    const files = new Map();
    for (const diff of Array.isArray(turn.fileDiff) ? turn.fileDiff : []) {
      if (!validPath(diff?.filePath)) continue;
      const path = normalizedPath(diff.filePath);
      if (!path) continue;
      const existing = files.get(path);
      const checkpoint = diff.cc?.v === 1 && typeof diff.cc.fileId === 'string' &&
        diff.cc.fileId.length > 0 && diff.cc.fileId.length <= 512 && validOpID(diff.cc.opId) && validOpID(diff.cc.baseOpId)
        ? JSON.stringify([turn.finished === true, Number.isFinite(turn.endedAt) ? turn.endedAt : null,
            diff.cc.fileId, diff.cc.opId, diff.cc.baseOpId, diff.cc.base === 'missing', diff.cc.deleted === true]) : '';
      // A turn may contain multiple checkpoints for the same path. Lody sums
      // their deltas; a later zero-count record must not erase an earlier edit.
      files.set(path, { path,
        additions: existing ? sumCounts(existing.additions, count(diff.add)) : count(diff.add),
        deletions: existing ? sumCounts(existing.deletions, count(diff.del)) : count(diff.del),
        edits: [],
        ...(checkpoint || existing?.previewRevision ? { previewRevision:
          `${existing?.previewRevision ?? ''}${checkpoint.length}:${checkpoint}` } : {}),
      });
    }
    for (const tool of Array.isArray(turn.items) ? turn.items : []) {
      if (tool?.type !== 'tool_call' || tool.status !== 'completed' || !Array.isArray(tool.content)) continue;
      for (const [index, diff] of tool.content.entries()) {
        if (diff?.type !== 'diff' || !validPath(diff.path) || typeof diff.newText !== 'string' ||
            (diff.oldText != null && typeof diff.oldText !== 'string')) continue;
        const path = normalizedPath(diff.path);
        if (!path) continue;
        const file = files.get(path) ?? { path, additions: null, deletions: null, edits: [] };
        const oldText = diff.oldText ?? '';
        const size = oldText.length + diff.newText.length;
        if (size <= 128 * 1024 && size <= textBudget && file.edits.length < 8) {
          file.edits.push({ id: `${tool.toolCallId ?? 'tool'}:${index}:${file.edits.length}`,
            oldText, newText: diff.newText });
          textBudget -= size;
        } else {
          file.previewLimited = true;
        }
        files.set(path, file);
      }
    }
    if (typeof turn.finished === 'boolean' || turn.endedAt != null) {
      for (const file of files.values()) file.previewFinished = turn.finished === true || turn.endedAt != null;
    }
    if (files.size) groups.push({ id: turn.id, turnNumber: Math.max(1, turnNumber), files: [...files.values()] });
  }
  return groups;
}
