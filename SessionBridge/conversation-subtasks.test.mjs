import test from 'node:test';
import assert from 'node:assert/strict';
import { projectSubtasks } from './conversation-subtasks.mjs';

const row = (id, parentSessionId, overrides = {}) => ({ docId: `session-${id}`,
  meta: { parentSessionId, title: id, agentType: 'codex', createdAt: '2026-09-27T00:00:00Z', ...overrides } });

test('subtasks belong to exactly their direct parent and exclude removed documents', () => {
  const rows = [row('root'), row('child', 'root'), row('other', 'another-root'),
    row('grandchild', 'child'), row('root', 'root'), row('comment-note', 'root'),
    { ...row('deleted', 'root'), deleted: true }, row('archived', 'root', { isArchived: true })];
  assert.deepEqual(projectSubtasks('root', rows).map(task => task.id), ['archived', 'child']);
  assert.deepEqual(projectSubtasks('child', rows).map(task => task.id), ['grandchild']);
  assert.deepEqual(projectSubtasks('root', []), []);
});

test('subtasks report metadata states without claiming idle means success; order stays stable', () => {
  const rows = [row('b', 'root', { status: { type: 'requestPermission' } }),
    row('a', 'root', { status: { type: 'running' } }),
    row('early', 'root', { createdAt: '2026-09-26', status: { type: 'initializing' } }),
    row('d', 'root', { title: '', agentType: '', cliType: 'custom', status: { type: 'idle' } })];
  const projected = projectSubtasks('root', rows);
  assert.deepEqual(projected.map(task => [task.id, task.status]),
    [['early', 'starting'], ['a', 'running'], ['b', 'waitingForInput'], ['d', 'idle']]);
  assert.equal(projected[3].title, 'Untitled subtask');
  assert.equal(projected[3].agentName, 'custom');
  rows[1].meta.status.type = 'idle';
  assert.deepEqual(projectSubtasks('root', rows).map(task => task.id), projected.map(task => task.id));
});
