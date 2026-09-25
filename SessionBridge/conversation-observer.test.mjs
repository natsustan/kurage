import test from 'node:test';
import assert from 'node:assert/strict';
import { LoroDoc } from 'loro-crdt';
import { conversationPatch, observeConversation } from './conversation-observer.mjs';

function harness({ waitFor, meta = { status: { type: 'running' } }, flock } = {}) {
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
    getDocMeta: async () => ({ meta }),
    openPersistedDoc: async () => ({ doc, joinRoom: createRoom }),
    openFlockDoc: async id => flock.open(id),
    joinMetaRoom: createRoom,
    watch(listener) { metaListener = listener; return { unsubscribe() { metaListener = undefined; } }; },
  };
  const updates = [];
  const controller = new AbortController();
  const start = () => observeConversation({ repo, workspaceID: 'ws', sessionID: 'abc', signal: controller.signal,
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

test('run config follows capabilities that arrive after the transcript', async () => {
  const rows = new Map();
  let flockListener;
  let openedID;
  let flockReleased = false;
  const flock = {
    open: async id => {
      openedID = id;
      return {
        flock: {
          get: key => rows.get(JSON.stringify(key)),
          subscribe: listener => { flockListener = listener; return () => { flockListener = undefined; }; },
        },
        joinRoom: async () => ({ unsubscribe() { flockReleased = true; } }),
      };
    },
  };
  const h = harness({ flock, meta: {
    status: { type: 'idle' }, cliType: 'builtin', agentType: 'codex',
    machineId: 'm1', agentConfigId: 'cfg',
  } });
  h.doc.getList('history').push({ id: 'u1', role: 'user', items: [],
    inputConfig: { modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high' } } });
  h.doc.commit();
  await h.start();
  assert.equal(openedID, 'ws:mf:m1');
  assert.deepEqual(h.updates[0].runConfig, {
    model: { value: 'gpt-5.5', label: 'gpt-5.5' }, reasoning: { value: 'high', label: 'High' },
    editable: null,
  });

  rows.set(JSON.stringify(['acpCapability', 'cfg']), {
    cliType: 'builtin', agentType: 'codex', models: [], configOptions: [
      { id: 'reasoning_effort', name: 'Reasoning', type: 'select', currentValue: 'medium',
        options: [{ value: 'medium', name: 'Medium' }, { value: 'high', name: 'High' }] },
    ],
  });
  flockListener();
  await h.flush();
  assert.equal(h.updates.at(-1).runConfig.editable.kind, 'reasoning');
  h.controller.abort();
  assert.equal(flockListener, undefined);
  assert.equal(flockReleased, true);
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

test('patch transmits an image added to an unchanged text turn', () => {
  const before = { id: 'a', author: 'agent', text: 'See', parts: [{ type: 'text', text: 'See' }] };
  const after = {
    ...before,
    parts: [...before.parts, { type: 'image', imageID: 'shot', mimeType: 'image/png' }],
  };
  const previous = { sessionID: 'abc', turns: [before], permission: null };
  const next = { sessionID: 'abc', turns: [after], permission: null };
  assert.deepEqual(conversationPatch(previous, next).changed, [after]);
  assert.deepEqual(conversationPatch(next, next).changed, []);
});
