import test from 'node:test';
import assert from 'node:assert/strict';
import { LoroDoc } from 'loro-crdt';
import { conversationPatch, observeConversation } from './conversation-observer.mjs';

function harness({ waitFor } = {}) {
  const doc = new LoroDoc();
  const timers = new Map();
  let nextTimer = 0;
  let metaListener;
  let releases = 0;
  const rooms = [];
  const createRoom = async () => {
    const room = {
      status: 'joined',
      waitFor: waitFor ?? (async () => ({ status: 'complete' })),
      unsubscribe() { releases++; },
      onStatusChange(listener) { room.changeStatus = status => { room.status = status; listener(status); }; return () => {}; },
    };
    rooms.push(room);
    return room;
  };
  const repo = {
    getDocMeta: async () => ({ meta: { status: { type: 'running' } } }),
    openPersistedDoc: async () => ({ doc, joinRoom: createRoom }),
    joinMetaRoom: createRoom,
    watch(listener) { metaListener = listener; return { unsubscribe() { metaListener = undefined; } }; },
  };
  const updates = [];
  const controller = new AbortController();
  const start = () => observeConversation({ repo, sessionID: 'abc', signal: controller.signal,
    emit: async update => { updates.push(update); },
    schedule: callback => { const id = ++nextTimer; timers.set(id, callback); return id; },
    unschedule: id => timers.delete(id),
  });
  const flush = async () => {
    await Promise.resolve();
    for (const [id, callback] of [...timers]) { timers.delete(id); callback(); }
    // publish crosses getDocMeta and emit boundaries.
    await Promise.resolve();
    await Promise.resolve();
  };
  return { doc, updates, controller, start, flush, rooms, repo,
    metadataChanged: () => metaListener?.(), releases: () => releases };
}

test('initial history, same-turn growth, deletion and reconnect status remain coherent', async () => {
  const h = harness();
  const history = h.doc.getList('history');
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'text', text: 'Hello' }] });
  h.doc.commit();
  await h.start();
  assert.equal(h.updates[0].changed[0].text, 'Hello');
  history.delete(0, 1);
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'text', text: 'Hello world' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).changed[0].text, 'Hello world');
  h.rooms[0].changeStatus('reconnecting');
  await h.flush();
  assert.equal(h.updates.at(-1).syncState, 'connecting');
  assert.deepEqual(h.updates.at(-1).changed, []);
  h.rooms[0].changeStatus('joined');
  history.delete(0, 1);
  h.doc.commit();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).order, []);
  assert.equal(h.updates.at(-1).syncState, 'live');
  h.controller.abort();
  assert.equal(h.releases(), 2);
  const count = h.updates.length;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.length, count);
});

test('cancelling while initial sync is pending releases both rooms without stale snapshot', async () => {
  let complete;
  const waiting = new Promise(resolve => { complete = resolve; });
  let started;
  const signal = new Promise(resolve => { started = resolve; });
  const h = harness({ waitFor: () => { started(); return waiting; } });
  const setup = h.start();
  await signal;
  h.controller.abort();
  complete({ status: 'aborted' });
  await setup;
  assert.equal(h.releases(), 2);
  assert.deepEqual(h.updates, []);
});

test('patch keeps turn identity and explicitly transmits ordering and removals', () => {
  const a = { id: 'a', text: 'one', author: 'agent' };
  const b = { id: 'b', text: 'two', author: 'user' };
  const previous = { sessionID: 'abc', turns: [a, b], permission: null };
  const next = { ...previous, turns: [b, { ...a, text: 'one more' }] };
  assert.deepEqual(conversationPatch(previous, next), {
    sessionID: 'abc', order: ['b', 'a'], changed: [{ ...a, text: 'one more' }], permission: null,
  });
});
