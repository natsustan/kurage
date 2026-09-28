import test from 'node:test';
import assert from 'node:assert/strict';
import { projectSubtasks } from './conversation-subtasks.mjs';
const task = overrides => ({ type: 'subagent_task', taskId: 'a', status: 'pending', ...overrides });
const assistant = (...items) => ({ role: 'assistant', items });
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
