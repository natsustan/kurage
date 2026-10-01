import test from 'node:test';
import assert from 'node:assert/strict';
import { projectSessionTabs, runningSessionTabParents } from './session-tabs.mjs';
const row = (id, meta = {}) => ({ docId: `session-${id}`, meta });

test('tabs contain the root and direct children in stable creation order, including closed tabs', () => {
  const rows = [row('unrelated'), row('b', { parentSessionId: 'root', createdAt: '2', isTabClosed: true }),
    row('a', { parentSessionId: 'root', createdAt: '1', lastMessageAt: 5 }), row('root'),
    row('side', { parentSessionId: 'root', childSessionPlacement: 'side-panel' }),
    row('opened', { openedBySessionId: 'root' }), row('nested', { parentSessionId: 'a' }),
    row('archived', { parentSessionId: 'root', isArchived: true }),
    { ...row('deleted', { parentSessionId: 'root' }), deleted: true },
    row('comment-root', { parentSessionId: 'root' })];
  assert.deepEqual(projectSessionTabs(rows, 'root').map(tab => tab.id), ['root', 'a', 'b']);
  assert.deepEqual(projectSessionTabs(rows, 'a'), projectSessionTabs(rows, 'root'));
  assert.equal(projectSessionTabs(rows, 'root')[2].isTabClosed, true);
  assert.deepEqual(projectSessionTabs(rows, 'missing'), []);
  rows.find(row => row.docId === 'session-root').meta.isArchived = true;
  assert.deepEqual(projectSessionTabs(rows, 'a'), []);
});

test('root list activity includes working closed tabs and excludes unrelated or removed children', () => {
  const rows = [row('root'), row('other'),
    row('tab', { parentSessionId: 'root', status: { type: 'running' } }),
    row('closed', { parentSessionId: 'root', isTabClosed: true, status: { type: 'initializing' } }),
    row('side', { parentSessionId: 'other', childSessionPlacement: 'side-panel', status: { type: 'running' } }),
    row('nested', { parentSessionId: 'tab', status: { type: 'running' } }),
    row('archived', { parentSessionId: 'other', isArchived: true, status: { type: 'running' } }),
    { ...row('deleted', { parentSessionId: 'other', status: { type: 'running' } }), deleted: true },
    row('comment-other', { parentSessionId: 'other', status: { type: 'running' } })];
  assert.deepEqual([...runningSessionTabParents(rows)], ['root']);
  assert.equal(projectSessionTabs(rows, 'root')[0].activity, 'idle');
  rows[2].meta.status = { type: 'idle' };
  assert.deepEqual([...runningSessionTabParents(rows)], ['root']);
  rows[3].meta.status = { type: 'requestPermission' };
  assert.deepEqual([...runningSessionTabParents(rows)], ['root']);
  rows[3].meta.status = { type: 'idle' };
  assert.deepEqual([...runningSessionTabParents(rows)], []);
});
