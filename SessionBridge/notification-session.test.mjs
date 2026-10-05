import assert from 'node:assert/strict';
import test from 'node:test';
import { notificationSessionDestination } from './notification-session.mjs';

const row = (id, meta = {}, extra = {}) => ({ docId: `session-${id}`, meta, ...extra });
const repo = rows => ({ listDoc: async () => rows });

test('notification resolves roots and closed direct tabs without opening documents', async () => {
  const metadata = repo([row('root'), row('tab', { parentSessionId: 'root', isTabClosed: true })]);
  assert.deepEqual(await notificationSessionDestination(metadata, 'root'), { rootSessionID: 'root', sessionID: 'root', isTabClosed: false });
  assert.deepEqual(await notificationSessionDestination(metadata, 'tab'), { rootSessionID: 'root', sessionID: 'tab', isTabClosed: true });
});

test('notification rejects unavailable targets, side panels and nested descendants', async () => {
  for (const rows of [[], [row('root', { isArchived: true })], [row('root', {}, { deleted: true })],
    [row('root', {}, { exists: false })], [row('root', {}, { e: false })],
    [row('root'), row('tab', { parentSessionId: 'root', childSessionPlacement: 'side-panel' })],
    [row('tab', { parentSessionId: 'missing' })],
    [row('root', { isArchived: true }), row('tab', { parentSessionId: 'root' })],
    [row('root'), row('parent', { parentSessionId: 'root' }), row('tab', { parentSessionId: 'parent' })]]) {
    const id = rows.some(r => r.docId === 'session-tab') ? 'tab' : 'root';
    assert.equal(await notificationSessionDestination(repo(rows), id), null);
  }
});

test('notification discards metadata returned after cancellation', async () => {
  const controller = new AbortController();
  const metadata = { listDoc: async () => { controller.abort(); return [row('root')]; } };
  await assert.rejects(notificationSessionDestination(metadata, 'root', controller.signal), { name: 'AbortError' });
});
