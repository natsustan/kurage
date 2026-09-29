import test from 'node:test';
import assert from 'node:assert/strict';
import { projectSubtasks } from './conversation-subtasks.mjs';
const task = overrides => ({ type: 'subagent_task', taskId: 'a', status: 'pending', ...overrides });
const assistant = (...items) => ({ role: 'assistant', items, finished: true });
const runningAssistant = (...items) => ({ role: 'assistant', items });
test('tasks come only from assistant history, never child tab metadata', () => {
  assert.deepEqual(projectSubtasks([{ docId: 'session-child', meta: { parentSessionId: 'root' } },
    { role: 'user', items: [task()] }, assistant(task({ skipTranscript: true }))]), []);
});
test('tasks retain first-seen order and latest persisted state, including results and usage', () => {
  const result = projectSubtasks([assistant(task(), task({ taskId: 'b', status: 'in_progress' })),
    assistant(task({ status: 'completed', summary: 'Done', usage: { totalTokens: 10, toolUses: 2 } }))]);
  assert.deepEqual(result.map(t => t.id), ['a', 'b']);
  assert.equal(result[0].status, 'completed');
  assert.equal(result[0].summary, 'Done');
  assert.equal(result[0].totalTokens, 10);
  assert.equal(result[0].toolUses, 2);
  assert.deepEqual(result[0].steps.map(s => s.id), ['a']);
  assert.deepEqual(projectSubtasks([]), []);
});
test('failed tasks preserve errors; malformed values and hidden replacements are excluded', () => {
  const result = projectSubtasks([assistant(task({ status: 'failed', error: 'Stopped', usage: { totalTokens: -1 } }),
    task({ taskId: 'b', status: 'unknown' }), task({ taskId: '' }))]);
  assert.equal(result.length, 1);
  assert.equal(result[0].error, 'Stopped');
  assert.equal(result[0].totalTokens, undefined);
  assert.deepEqual(projectSubtasks([assistant(task()), assistant(task({ skipTranscript: true }))]), []);
});
test('lifecycle activities collapse into the subagent they name, keeping their order as steps', () => {
  const result = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'in_progress' }),
    task({ taskId: 'act-2', actor: 'review_reuse', description: 'Interact with subagent review_reuse',
           status: 'completed', summary: 'Checked helpers' }),
    task({ taskId: 'act-3', actor: 'review_reuse', description: 'Interact with subagent review_reuse',
           status: 'completed' }))]);
  assert.equal(result.length, 1);
  assert.deepEqual(result[0], {
    id: 'review_reuse', title: 'review_reuse', agentName: 'review_reuse', status: 'completed',
    summary: 'Checked helpers',
    steps: [
      { id: 'act-1', title: 'Start subagent review_reuse', status: 'in_progress' },
      { id: 'act-2', title: 'Interact with subagent review_reuse', status: 'completed',
        summary: 'Checked helpers' },
      { id: 'act-3', title: 'Interact with subagent review_reuse', status: 'completed' },
    ],
  });
});
test('an activity group runs until its turn ends or an interrupt activity fails it', () => {
  // Codex has no completion activity: a subagent that finishes on its own emits
  // nothing, so the turn ending is what ends the group.
  const running = projectSubtasks([runningAssistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'completed' }),
    task({ taskId: 'act-2', actor: 'review_reuse', description: 'Interact with subagent review_reuse',
           status: 'completed' }))]);
  assert.equal(running[0].status, 'in_progress');
  assert.deepEqual(running[0].steps.map(s => s.status), ['completed', 'completed']);
  const ended = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'completed' }))]);
  assert.equal(ended[0].status, 'completed');
  const interrupted = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Interrupt subagent review_reuse',
           status: 'completed' }))]);
  assert.equal(interrupted[0].status, 'failed');
  // A later live activity on the same subagent starts it running again.
  const resumed = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'completed' })),
    runningAssistant(
    task({ taskId: 'act-2', actor: 'review_reuse', description: 'Interact with subagent review_reuse',
           status: 'in_progress' }))]);
  assert.equal(resumed[0].status, 'in_progress');
});
test('subagents stay separate per actor and keep prompts as their own task title', () => {
  const result = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'in_progress' }),
    task({ taskId: 'act-2', actor: 'review_tests', description: 'Start subagent review_tests',
           status: 'in_progress' }),
    task({ taskId: 'prompt-1', actor: 'general-purpose', description: 'Review the diff',
           status: 'completed' }))]);
  assert.deepEqual(result.map(t => t.id), ['review_reuse', 'review_tests', 'prompt-1']);
  assert.deepEqual(result.map(t => t.title), ['review_reuse', 'review_tests', 'Review the diff']);
  assert.deepEqual(result.map(t => t.steps.length), [1, 1, 1]);
});
test('hidden replacements drop their step and an emptied subagent', () => {
  const result = projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'in_progress' }),
    task({ taskId: 'act-2', actor: 'review_reuse', description: 'Interact with subagent review_reuse',
           status: 'completed' }),
    task({ taskId: 'act-1', skipTranscript: true }))]);
  assert.deepEqual(result.map(t => t.id), ['review_reuse']);
  assert.deepEqual(result[0].steps.map(s => s.id), ['act-2']);
  assert.deepEqual(projectSubtasks([assistant(
    task({ taskId: 'act-1', actor: 'review_reuse', description: 'Start subagent review_reuse',
           status: 'in_progress' }),
    task({ taskId: 'act-1', skipTranscript: true }))]), []);
});
