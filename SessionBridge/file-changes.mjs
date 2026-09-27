// SessionHistory.fileDiff is a per-turn summary, not the current Git worktree.
// Completed ACP diff blocks are optional historical text evidence. Never infer
// modifications from tool names, locations, shell output, or failed calls.
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const sumCounts = (left, right) => left === null || right === null ? null : count(left + right);
const validPath = value => typeof value === 'string' && value.trim() && !value.includes('\0');
// Match Lody's display-path normalization; never guess a root from suffixes.
const normalizedPath = value => value.replace(/\\/g, '/').replace(/^\.\/+/, '');

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
      // A turn may contain multiple checkpoints for the same path. Lody sums
      // their deltas; a later zero-count record must not erase an earlier edit.
      files.set(path, { path,
        additions: existing ? sumCounts(existing.additions, count(diff.add)) : count(diff.add),
        deletions: existing ? sumCounts(existing.deletions, count(diff.del)) : count(diff.del),
        edits: [],
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
    if (files.size) groups.push({ id: turn.id, turnNumber: Math.max(1, turnNumber), files: [...files.values()] });
  }
  return groups;
}
