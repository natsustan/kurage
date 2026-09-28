// Native agent tasks are history items, never child Session metadata.
export function projectSubtasks(history) {
  const tasks = new Map();
  const text = value => typeof value === 'string' && value.trim() ? value : undefined;
  const count = value => Number.isSafeInteger(value) && value >= 0 ? value : undefined;
  for (const entry of history) {
    if (entry?.role !== 'assistant' || !Array.isArray(entry.items)) continue;
    for (const item of entry.items) {
      if (item?.type !== 'subagent_task' || !text(item.taskId)) continue;
      if (item.skipTranscript) { tasks.delete(item.taskId); continue; }
      if (!['pending', 'in_progress', 'completed', 'failed'].includes(item.status)) continue;
      tasks.set(item.taskId, {
        id: item.taskId,
        title: text(item.description) ?? 'Agent task',
        agentName: text(item.actor) ?? text(item.subagentType) ?? text(item.workflowName) ?? 'Agent',
        status: item.status,
        summary: text(item.summary), error: text(item.error),
        lastToolName: text(item.lastToolName), modelID: text(item.modelId),
        totalTokens: count(item.usage?.totalTokens), toolUses: count(item.usage?.toolUses),
      });
    }
  }
  return [...tasks.values()];
}
