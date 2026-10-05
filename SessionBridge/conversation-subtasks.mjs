import { projectAssistantBlocks } from './conversation-work.mjs';

// Normalized runs persist their own output in parent history. Legacy Codex
// tasks publish one row per lifecycle activity (start / interact / interrupt),
// so those rows are grouped by actor and kept as the subagent's steps.
const SUBAGENT_TASK_STATUSES = ['pending', 'in_progress', 'completed', 'failed'];

const visibleText = value => typeof value === 'string' && value.trim() ? value : undefined;

// Activity titles are rendered as "<verb> subagent <actor>" (see Lody's
// CodexToolCallMapper). The actor is the only identity a legacy activity
// payload carries, so a title naming its own actor is what separates a
// lifecycle activity from a task whose description is a prompt.
const activityActor = item => {
  const actor = visibleText(item.actor);
  const description = visibleText(item.description)?.toLowerCase();
  if (!actor || !description) return undefined;
  return description.includes('subagent') && description.endsWith(` ${actor.toLowerCase()}`)
    ? actor : undefined;
};

// An activity item completes as soon as its call returns, so its own status
// cannot say whether the subagent is still alive. Codex names its activities
// "Start subagent X", "Interact with subagent X", and "Interrupt subagent X" —
// it has no completion activity, so a subagent that finishes on its own emits
// nothing further. An interrupt ends it as failed; otherwise the turn ending is
// what ends it.
const interrupted = description => description.toLowerCase().startsWith('interrupt');
const turnEnded = entry => entry.finished === true || entry.endedAt != null;
const activityStatus = (description, entry) =>
  interrupted(description) ? 'failed' : turnEnded(entry) ? 'completed' : 'in_progress';

const RUN_STATES = new Set(['pending', 'running', 'completed', 'failed', 'cancelled', 'unknown']);
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : undefined;
const milliseconds = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
  value * 1000 <= 8.64e15 ? value * 1000 : undefined;

// Only the explicit text/tool/plan contract is projected. Thought text and raw
// tool input/output remain private, just as in the main transcript.
function projectRun(item) {
  const { run } = item;
  if (!run || !visibleText(run.sessionId) || !RUN_STATES.has(run.snapshot?.state) ||
      !Array.isArray(run.items)) return undefined;
  const snapshot = run.snapshot;
  const progress = run.progress;
  // The ACP root is part of a run's identity. Names are display data, not IDs.
  const id = `run:${JSON.stringify([run.sessionId, item.taskId])}`;
  const status = snapshot.state === 'running' ? 'in_progress' : snapshot.state;
  const live = status === 'pending' || status === 'in_progress';
  const startedAtMs = milliseconds(snapshot.startedAtEpochSeconds) ?? milliseconds(item.startedAtEpochSeconds);
  const endedAtMs = milliseconds(snapshot.endedAtEpochSeconds) ?? milliseconds(item.endedAtEpochSeconds);
  const entry = { items: run.items, finished: !live && status !== 'unknown',
    ...(startedAtMs !== undefined ? { timestamp: new Date(startedAtMs).toISOString() } : {}),
    ...(endedAtMs !== undefined ? { endedAt: endedAtMs } : {}) };
  const { parts, work } = projectAssistantBlocks(entry, value => {
    const text = value?.type === 'text' ? visibleText(value.text) : undefined;
    return text ? [{ type: 'text', text }] : [];
  });
  if (work && work.durationMs === undefined && typeof progress?.durationMs === 'number' &&
      Number.isFinite(progress.durationMs) && progress.durationMs >= 0) {
    work.durationMs = progress.durationMs;
  }
  const turns = [];
  const description = visibleText(snapshot.description) ?? visibleText(item.description);
  // This provider-generated label names the run; it is not a user prompt.
  const placeholder = [snapshot.name, item.actor].some(name => visibleText(name) &&
    description?.trim() === `Delegated task for ${name.trim()}`);
  if (description && !placeholder) turns.push({ id: `${id}:brief`, author: 'user', text: description, parts: [] });
  if (parts.length || work || live) {
    turns.push({ id: `${id}:output`, author: 'agent',
      text: parts.filter(part => part.type === 'text').map(part => part.text).join('\n\n'), parts,
      ...(work ? { work } : {}),
      ...(live ? { timing: { ...(startedAtMs !== undefined ? { startedAtMs } : {}), permissionWaitMs: 0 } } : {}) });
  }
  const summary = visibleText(snapshot.summary) ?? visibleText(item.summary);
  // Status-only providers still have a readable result, without repeating a
  // summary already present in their streamed answer.
  const lastText = run.items.findLast(value => value?.type === 'text' && visibleText(value.text))?.text;
  if (summary && summary.trim() !== lastText?.trim()) {
    turns.push({ id: `${id}:result`, author: 'agent', text: summary, parts: [] });
  }
  const plan = run.items.findLast(value => value?.type === 'plan' && Array.isArray(value.entries))?.entries
    .filter(value => visibleText(value?.content) && ['pending', 'in_progress', 'completed'].includes(value.status))
    .map(value => ({ content: value.content, status: value.status })) ?? [];
  const totalTokens = count(progress?.totalTokens) ?? count(item.usage?.totalTokens);
  const toolUses = count(progress?.toolCallCount) ?? count(item.usage?.toolUses);
  return {
    id, title: visibleText(snapshot.name) ?? visibleText(item.actor) ?? description ?? 'Agent',
    agentName: visibleText(snapshot.name) ?? visibleText(item.actor) ?? 'Agent', status,
    run: { turns, streamsOutput: Array.isArray(snapshot.support?.stream) &&
      snapshot.support.stream.some(type => ['text', 'tool', 'plan'].includes(type)),
      outputIncomplete: snapshot.outputIncomplete === true, plan },
    ...(summary ? { summary } : {}),
    ...(visibleText(snapshot.reason?.message) ?? visibleText(item.error)
      ? { error: visibleText(snapshot.reason?.message) ?? visibleText(item.error) } : {}),
    ...(visibleText(snapshot.modelId) ?? visibleText(item.modelId)
      ? { modelID: visibleText(snapshot.modelId) ?? visibleText(item.modelId) } : {}),
    ...(visibleText(progress?.summary) ? { progressSummary: progress.summary } : {}),
    ...(visibleText(progress?.lastToolName) ?? visibleText(item.lastToolName)
      ? { lastToolName: visibleText(progress?.lastToolName) ?? visibleText(item.lastToolName) } : {}),
    ...(totalTokens !== undefined ? { totalTokens } : {}),
    ...(toolUses !== undefined ? { toolUses } : {}),
  };
}

export function projectSubtasks(history) {
  const groups = new Map();
  const groupIDByStepID = new Map();

  const forget = stepID => {
    const groupID = groupIDByStepID.get(stepID);
    if (groupID === undefined) return;
    groupIDByStepID.delete(stepID);
    const group = groups.get(groupID);
    if (!group) return;
    if (group.run) { groups.delete(groupID); return; }
    group.steps = group.steps.filter(step => step.id !== stepID);
    if (group.steps.length === 0) groups.delete(groupID);
  };

  for (const entry of history) {
    if (entry?.role !== 'assistant' || !Array.isArray(entry.items)) continue;
    for (const item of entry.items) {
      if (item?.type !== 'subagent_task' || !visibleText(item.taskId)) continue;
      const stepID = visibleText(item.run?.sessionId)
        ? JSON.stringify([item.run.sessionId, item.taskId]) : item.taskId;
      if (item.skipTranscript) { forget(stepID); continue; }
      if (item.run) {
        const run = projectRun(item);
        if (run) {
          groups.set(run.id, run);
          groupIDByStepID.set(stepID, run.id);
        }
        continue;
      }
      if (!SUBAGENT_TASK_STATUSES.includes(item.status)) continue;
      const actor = activityActor(item);
      const name = visibleText(item.actor) ?? visibleText(item.subagentType) ?? visibleText(item.workflowName) ?? 'Agent';
      const description = visibleText(item.description);
      const step = { id: item.taskId, title: description ?? name, status: item.status };
      const summary = visibleText(item.summary);
      const error = visibleText(item.error);
      if (summary) step.summary = summary;
      if (error) step.error = error;
      const groupID = actor ?? item.taskId;
      let group = groups.get(groupID);
      if (!group) {
        group = { id: groupID, title: name, agentName: name, status: item.status, steps: [] };
        groups.set(groupID, group);
      }
      const known = group.steps.findIndex(candidate => candidate.id === step.id);
      if (known === -1) group.steps.push(step); else group.steps[known] = step;
      groupIDByStepID.set(step.id, groupID);
      // A later step wins per field, but a step that carries no value leaves the
      // subagent's earlier detail (its prompt, result, usage) in place.
      if (!actor && description) group.title = description;
      group.status = actor && description ? activityStatus(description, entry) : step.status;
      if (summary) group.summary = summary;
      if (error) group.error = error;
      const lastToolName = visibleText(item.lastToolName);
      const modelID = visibleText(item.modelId);
      const totalTokens = count(item.usage?.totalTokens);
      const toolUses = count(item.usage?.toolUses);
      if (lastToolName) group.lastToolName = lastToolName;
      if (modelID) group.modelID = modelID;
      if (totalTokens !== undefined) group.totalTokens = totalTokens;
      if (toolUses !== undefined) group.toolUses = toolUses;
    }
  }
  return [...groups.values()];
}
