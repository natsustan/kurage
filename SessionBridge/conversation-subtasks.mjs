// Native agent tasks are history items, never child Session metadata. Codex
// publishes one `subagent_task` per subagent lifecycle activity (start /
// interact / complete / interrupt), each keyed by its own activity id, so the
// panel groups them into the subagent they belong to and keeps the activities
// as that subagent's steps.
const SUBAGENT_TASK_STATUSES = ['pending', 'in_progress', 'completed', 'failed'];

const visibleText = value => typeof value === 'string' && value.trim() ? value : undefined;

// Activity titles are rendered as "<verb> subagent <actor>" (see Lody's
// CodexToolCallMapper). The actor is the only subagent identity the persisted
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
// cannot say whether the subagent is still alive. Only a complete/interrupt
// activity ends it; a start or interaction means it is running.
const activityStatus = description => {
  const title = description.toLowerCase();
  if (title.startsWith('complete')) return 'completed';
  return title.startsWith('interrupt') ? 'failed' : 'in_progress';
};

export function projectSubtasks(history) {
  const groups = new Map();
  const groupIDByStepID = new Map();
  const count = value => Number.isSafeInteger(value) && value >= 0 ? value : undefined;

  const forget = stepID => {
    const groupID = groupIDByStepID.get(stepID);
    if (groupID === undefined) return;
    groupIDByStepID.delete(stepID);
    const group = groups.get(groupID);
    if (!group) return;
    group.steps = group.steps.filter(step => step.id !== stepID);
    if (group.steps.length === 0) groups.delete(groupID);
  };

  for (const entry of history) {
    if (entry?.role !== 'assistant' || !Array.isArray(entry.items)) continue;
    for (const item of entry.items) {
      if (item?.type !== 'subagent_task' || !visibleText(item.taskId)) continue;
      if (item.skipTranscript) { forget(item.taskId); continue; }
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
      group.status = actor && description ? activityStatus(description) : step.status;
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
