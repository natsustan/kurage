// Mirrors Lody's assistant-turn folding (`assistant-turn-render-blocks.ts`,
// `message-copy.ts`, `session-history-duration.ts`): consecutive tool calls and
// thoughts form an activity group, and a finished turn with a visible answer
// folds its earlier work behind "Worked for …". Thought text is never exposed.
const MAX_ACTIVITY_STEPS = 100;
const MAX_STEP_TITLE = 200;

const STEP_KINDS = {
  execute: 'command', bash: 'command', read: 'read',
  edit: 'edit', write: 'edit', delete: 'edit', move: 'edit',
  search: 'search', fetch: 'fetch',
};

const isToolCall = item => item?.type === 'tool_call';

export function isHiddenAssistantItem(item) {
  return item?.type === 'subagent_task' || item?.type === 'available_commands' ||
    (isToolCall(item) && item.activityKind === 'codex_retry' &&
      item.status !== 'pending' && item.status !== 'in_progress');
}

export function isActivityItem(item) {
  return item?.type === 'thought' ||
    (isToolCall(item) && item.kind !== 'switch_mode' && item.activityKind === undefined);
}

const isThought = item => item?.type === 'thought' || (isToolCall(item) && item.kind === 'think');

const isNeverCollapsed = item =>
  ['image_group', 'image', 'file', 'plan', 'goal', 'proposed_plan', 'system_notice'].includes(item?.type) ||
  (isToolCall(item) && item.kind === 'switch_mode');

// The answer is the final contiguous run of text before the never-collapsed tail.
function finalTextRunStart(items) {
  let index = items.length - 1;
  while (index >= 0 && isNeverCollapsed(items[index])) index -= 1;
  if (items[index]?.type !== 'text') return items.length;
  while (index > 0 && items[index - 1]?.type === 'text') index -= 1;
  return index;
}

export function collapsibleIndexes(items) {
  const textStart = finalTextRunStart(items);
  const indexes = new Set();
  items.forEach((item, index) => {
    if (items.length > 1 && index < items.length - 1 &&
        !(item?.type === 'text' && index >= textStart) && !isNeverCollapsed(item)) {
      indexes.add(index);
    }
  });
  return indexes;
}

function toolPaths(item) {
  const paths = new Set();
  for (const location of Array.isArray(item.locations) ? item.locations : []) {
    if (typeof location?.path === 'string' && location.path) paths.add(location.path);
  }
  for (const block of Array.isArray(item.content) ? item.content : []) {
    if (block?.type === 'diff' && typeof block.path === 'string' && block.path) paths.add(block.path);
  }
  return [...paths];
}

function stepKind(item) {
  const kind = STEP_KINDS[item.kind];
  if (kind) return kind;
  const hasTerminal = Array.isArray(item.content) &&
    item.content.some(block => block?.type === 'terminal_command' || block?.type === 'terminal_output');
  return hasTerminal ? 'command' : 'tool';
}

function stepTitle(item) {
  if (typeof item.title !== 'string') return undefined;
  const title = item.title.replaceAll('\0', '').trim();
  return title ? title.slice(0, MAX_STEP_TITLE) : undefined;
}

// Counts match Lody's `summarizeAssistantActivity`: reads and edits count distinct paths.
export function projectActivity(id, entries) {
  const readPaths = new Set();
  const editPaths = new Set();
  const counts = { commands: 0, reads: 0, edits: 0, searches: 0, fetches: 0, tools: 0 };
  const steps = [];
  const stepIDs = new Set();
  for (const { item, index } of entries) {
    if (isThought(item)) continue;
    const kind = stepKind(item);
    const paths = toolPaths(item);
    if (kind === 'read' || kind === 'edit') {
      const known = kind === 'read' ? readPaths : editPaths;
      if (paths.length === 0) counts[kind === 'read' ? 'reads' : 'edits'] += 1;
      for (const path of paths) known.add(path);
    } else {
      counts[{ command: 'commands', search: 'searches', fetch: 'fetches', tool: 'tools' }[kind]] += 1;
    }
    const title = stepTitle(item);
    const stepID = typeof item.toolCallId === 'string' && item.toolCallId ? item.toolCallId : `#${index}`;
    if (title && steps.length < MAX_ACTIVITY_STEPS && !stepIDs.has(stepID)) {
      stepIDs.add(stepID);
      steps.push({ id: stepID, kind, title });
    }
  }
  counts.reads += readPaths.size;
  counts.edits += editPaths.size;
  if (Object.values(counts).every(count => count === 0)) return undefined;
  return { type: 'activity', id, ...counts, steps };
}

// Effective working time: (endedAt - timestamp) - permissionWaitMs.
export function workDurationMs(entry) {
  const endedAt = entry?.endedAt;
  if (typeof endedAt !== 'number' || !Number.isFinite(endedAt)) return undefined;
  const startedAt = typeof entry.timestamp === 'string' ? Date.parse(entry.timestamp) : NaN;
  if (!Number.isFinite(startedAt) || endedAt < startedAt) return undefined;
  const span = endedAt - startedAt;
  const wait = entry.permissionWaitMs;
  return typeof wait === 'number' && Number.isFinite(wait) && wait > 0 ? Math.max(0, span - wait) : span;
}

/**
 * Groups an assistant entry into ordered blocks. `projectItem` turns one
 * non-activity item into displayable parts. Returns the visible parts and, for
 * a finished turn with a visible answer, the folded work.
 */
export function projectAssistantBlocks(entry, projectItem) {
  const items = (Array.isArray(entry.items) ? entry.items : []).filter(item => !isHiddenAssistantItem(item));
  const finished = entry.finished === true;
  const collapsible = finished ? collapsibleIndexes(items) : new Set();
  const blocks = [];
  let pending = [];
  const flush = () => {
    const first = pending[0];
    if (!first) return;
    const suffix = isToolCall(first.item) && typeof first.item.toolCallId === 'string' ? first.item.toolCallId : '';
    const activity = projectActivity(`${first.index}:${suffix}`, pending);
    if (activity) blocks.push({ parts: [activity], work: true });
    pending = [];
  };
  items.forEach((item, index) => {
    if (isActivityItem(item)) {
      pending.push({ item, index });
      return;
    }
    flush();
    const parts = projectItem(item);
    if (parts.length) blocks.push({ parts, work: collapsible.has(index) });
  });
  flush();

  const all = blocks.flatMap(block => block.parts);
  const visible = blocks.filter(block => !block.work).flatMap(block => block.parts);
  const folded = blocks.filter(block => block.work).flatMap(block => block.parts);
  if (!finished || folded.length === 0 || visible.length === 0) return { parts: all };
  const durationMs = workDurationMs(entry);
  return { parts: visible, work: { ...(durationMs === undefined ? {} : { durationMs }), parts: folded } };
}
