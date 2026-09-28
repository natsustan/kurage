import test from 'node:test';
import assert from 'node:assert/strict';
import { LoroDoc } from 'loro-crdt';
import { conversationPatch, observeConversation, readSyncedConversation } from './conversation-observer.mjs';

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
    listDoc: async () => [],
    sync: async () => ({ ok: true }),
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
    // Drain metadata reads and delivery without relying on a fixed await count.
    await new Promise(setImmediate);
  };
  return { doc, updates, controller, start, flush, rooms, repo,
    metadataChanged: () => metaListener?.(), releases: () => releases };
}

test('initial cached history cannot acknowledge a newer marker until content arrives', async () => {
  const h = harness({ meta: { status: { type: 'idle' }, lastMessageAt: 200 } });
  const history = h.doc.getList('history');
  history.push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Old' }] });
  h.doc.commit();
  await h.start();
  assert.deepEqual(h.updates[0].order, ['old']);
  assert.equal(h.updates[0].lastMessageAt, null);
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, null);
  history.push({ id: 'new', role: 'assistant', items: [{ type: 'text', text: 'New' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  h.controller.abort();
});

test('initial room restoration counts as content arriving after the local baseline', async () => {
  const h = harness({ meta: { lastMessageAt: 200 }, waitFor: async () => {
    if (h.doc.getList('history').length === 0) {
      h.doc.getList('history').push({ id: 'new', role: 'assistant', items: [{ type: 'text', text: 'New' }] });
      h.doc.commit();
    }
    return { status: 'complete' };
  } });
  await h.start();
  assert.equal(h.updates[0].lastMessageAt, 200);
  h.controller.abort();
});

test('initial receipt waits through non-visible updates and accepts same-turn growth', async () => {
  const h = harness({ meta: { lastMessageAt: 200 } });
  const history = h.doc.getList('history');
  history.push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Partial' }] });
  h.doc.commit();
  await h.start();
  h.doc.getMap('acpRuntimeConfig').set('modelId', 'model');
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, null);
  history.delete(0, 1);
  history.push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Partial completed' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  assert.deepEqual(h.updates.at(-1).order, ['old']);
  h.controller.abort();
});

test('reopening delivered history reuses only its confirmed marker and workspace', async () => {
  const meta = { lastMessageAt: 100 };
  const h = harness({ meta });
  h.repo.sync = async () => {
    h.doc.getList('history').push({ id: 'first', role: 'assistant', items: [{ type: 'text', text: 'First' }] });
    h.doc.commit();
    return { ok: true };
  };
  await h.start();
  assert.equal(h.updates[0].lastMessageAt, 100);
  h.controller.abort();
  h.repo.sync = async () => ({ ok: true });
  for (const [workspaceID, timestamp, expected] of [['ws', 100, 100], ['ws', 200, null], ['other', 100, null]]) {
    meta.lastMessageAt = timestamp;
    const controller = new AbortController();
    const updates = [];
    await observeConversation({ repo: h.repo, workspaceID, sessionID: 'abc', signal: controller.signal,
      emit: async update => updates.push(update) });
    assert.equal(updates[0].lastMessageAt, expected);
    controller.abort();
  }
});

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

test('context window usage follows metadata updates and clears when unavailable', async () => {
  const meta = { status: { type: 'idle' }, contextWindowUsage: { size: 258_000, used: 217_000 } };
  const h = harness({ meta });
  await h.start();
  assert.deepEqual(h.updates[0].contextWindowUsage, { size: 258_000, used: 217_000 });

  meta.contextWindowUsage = { size: 258_000, used: 218_000 };
  h.metadataChanged();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).contextWindowUsage, { size: 258_000, used: 218_000 });

  delete meta.contextWindowUsage;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).contextWindowUsage, null);

  meta.contextWindowUsage = { size: 258_000, used: 12.5 };
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).contextWindowUsage, null);
  h.controller.abort();
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
    sessionID: 'abc', latestTurnNumber: undefined, order: ['b', 'a'], changed: [{ ...a, text: 'one more' }], permission: null,
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


test('file-only history updates replace summaries and removal clears them while subscribed', async () => {
  const h = harness();
  const history = h.doc.getList('history');
  const turn = { id: 'a', role: 'assistant', items: [], fileDiff: [{ filePath: 'a.swift', add: 1, del: 0 }] };
  history.push(turn);
  h.doc.commit();
  await h.start();
  assert.equal(h.updates[0].fileChanges[0].files[0].additions, 1);
  assert.deepEqual(h.updates[0].order, ['a']);
  history.delete(0, 1);
  history.push({ ...turn, fileDiff: [{ filePath: 'a.swift', add: 4, del: 2 }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).fileChanges[0].files[0].additions, 4);
  history.delete(0, 1);
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).fileChanges, null);
  h.controller.abort();
});

test('subtask metadata changes appear without parent history edits and stop after cancellation', async () => {
  const h = harness();
  let rows = [];
  let reads = 0;
  h.repo.listDoc = async () => { reads++; return rows; };
  let watched;
  const watch = h.repo.watch;
  h.repo.watch = (listener, filter) => { watched = filter; return watch(listener); };
  await h.start();
  assert.equal(watched.docIds, undefined, 'new children must not be filtered out by the parent ID');
  assert.deepEqual(h.updates[0].subtasks, []);
  rows = [{ docId: 'session-child', meta: { parentSessionId: 'abc', title: 'Review', status: { type: 'running' } } }];
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).replacesSubtasks, true);
  assert.equal(h.updates.at(-1).subtasks[0].status, 'running');
  const beforeText = reads;
  h.doc.getList('history').push({ id: 'a', role: 'assistant', items: [{ type: 'text', text: 'Output' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(reads, beforeText, 'streaming text must not rescan workspace metadata');
  assert.equal(h.updates.at(-1).replacesSubtasks, undefined);
  rows[0].meta.status.type = 'idle';
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).subtasks[0].status, 'idle');
  rows = [];
  h.metadataChanged();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).subtasks, []);
  h.controller.abort();
  const count = h.updates.length;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.length, count);
  assert.equal(h.releases(), 2);
});

test('message timestamps follow cloud history on initial and metadata-only updates', async () => {
  const meta = { status: { type: 'idle' }, lastMessageAt: 100 };
  const h = harness({ meta });
  const history = h.doc.getList('history');
  const synced = [];
  h.repo.sync = async options => {
    synced.push(options);
    if (meta.lastMessageAt === 100) {
      history.push({ id: 'first', role: 'assistant', items: [{ type: 'text', text: 'First' }] });
    } else {
      history.push({ id: 'second', role: 'assistant', items: [{ type: 'text', text: 'Second' }] });
    }
    h.doc.commit();
    return { ok: true };
  };
  await h.start();
  assert.equal(h.updates[0].lastMessageAt, 100);
  assert.deepEqual(h.updates[0].order, ['first']);
  meta.lastMessageAt = 200;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  assert.deepEqual(h.updates.at(-1).order, ['first', 'second']);
  assert.deepEqual(synced.map(({ scope, docIds }) => [scope, docIds]), [
    ['doc', ['session-abc']], ['doc', ['session-abc']],
  ]);
  h.controller.abort();
});

test('a metadata update cannot publish its read timestamp before history sync completes', async () => {
  const meta = { status: { type: 'idle' }, lastMessageAt: 100 };
  const h = harness({ meta });
  const history = h.doc.getList('history');
  h.repo.sync = async () => {
    history.push({ id: 'first', role: 'assistant', items: [{ type: 'text', text: 'First' }] });
    h.doc.commit();
    return { ok: true };
  };
  await h.start();
  h.repo.sync = async () => ({ ok: true });
  const syncing = Promise.withResolvers();
  h.repo.sync = async () => {
    await syncing.promise;
    history.push({ id: 'second', role: 'assistant', items: [{ type: 'text', text: 'Second' }] });
    h.doc.commit();
    return { ok: true };
  };
  meta.lastMessageAt = 200;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 100);
  syncing.resolve();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  assert.deepEqual(h.updates.at(-1).order, ['first', 'second']);
  h.controller.abort();
});

test('a synced marker stays unread until the visible conversation catches up', async () => {
  const meta = { status: { type: 'idle' }, lastMessageAt: 100 };
  const h = harness({ meta });
  const history = h.doc.getList('history');
  h.repo.sync = async () => {
    history.push({ id: 'first', role: 'assistant', items: [{ type: 'text', text: 'First' }] });
    h.doc.commit();
    return { ok: true };
  };
  await h.start();
  h.repo.sync = async () => ({ ok: true });
  meta.lastMessageAt = 200;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, null);
  assert.deepEqual(h.updates.at(-1).order, ['first']);
  history.push({ id: 'second', role: 'assistant', items: [{ type: 'text', text: 'Second' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  assert.deepEqual(h.updates.at(-1).order, ['first', 'second']);
  h.controller.abort();
});

test('history that arrives before metadata still advances the read timestamp', async () => {
  const meta = { status: { type: 'idle' }, lastMessageAt: 100 };
  const h = harness({ meta });
  const history = h.doc.getList('history');
  h.repo.sync = async () => {
    history.push({ id: 'first', role: 'assistant', items: [{ type: 'text', text: 'First' }] });
    h.doc.commit();
    return { ok: true };
  };
  await h.start();
  h.repo.sync = async () => ({ ok: true });
  history.push({ id: 'second', role: 'assistant', items: [{ type: 'text', text: 'Second' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 100);
  meta.lastMessageAt = 200;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  assert.deepEqual(h.updates.at(-1).changed, []);
  h.controller.abort();
});

test('failed history sync never publishes a newer read timestamp', async () => {
  const h = harness({ meta: { status: { type: 'idle' }, lastMessageAt: 100 } });
  h.repo.sync = async () => ({ ok: false });
  await h.start();
  assert.deepEqual(h.updates, [{ error: 'Conversation sync failed' }]);
});

test('cancelling a pending receipt sync releases observation without publishing', async () => {
  const h = harness({ meta: { status: { type: 'idle' }, lastMessageAt: 100 } });
  const syncing = Promise.withResolvers();
  const started = Promise.withResolvers();
  h.repo.sync = async ({ signal }) => {
    assert.equal(signal, h.controller.signal);
    started.resolve();
    return syncing.promise;
  };
  const observing = h.start();
  await started.promise;
  h.controller.abort();
  syncing.resolve({ ok: true });
  await observing;
  assert.deepEqual(h.updates, []);
  assert.equal(h.releases(), 2);
});


test('search sync evidence survives unloading and is scoped to repo, workspace, session and version', async () => {
  const h = harness({ meta: { lastMessageAt: 100 } });
  h.repo.sync = async () => {
    h.doc.getList('history').push({ id: 'new', role: 'assistant', items: [{ type: 'text', text: 'Latest' }] });
    h.doc.commit();
    return { ok: true };
  };
  const preloaded = await readSyncedConversation({ repo: h.repo, workspaceID: 'ws', sessionID: 'abc',
    doc: h.doc, signal: h.controller.signal });
  assert.deepEqual(preloaded.turns.map(turn => turn.id), ['new']);
  assert.equal(preloaded.lastMessageAt, undefined);
  assert.deepEqual(h.updates, []);
  const snapshot = h.doc.export({ mode: 'snapshot' });
  h.repo.sync = async () => ({ ok: true });
  for (const scenario of ['matching', 'workspace', 'session', 'repo', 'version', 'newer-marker']) {
    const doc = new LoroDoc();
    doc.import(snapshot);
    if (scenario === 'version') {
      doc.getList('history').push({ id: 'other', role: 'assistant', items: [{ type: 'text', text: 'Other' }] });
      doc.commit();
    }
    const open = h.repo.openPersistedDoc;
    h.repo.openPersistedDoc = async () => ({ ...(await open()), doc });
    const repo = scenario === 'repo' ? { ...h.repo } : h.repo;
    if (scenario === 'newer-marker') repo.getDocMeta = async () => ({ meta: { lastMessageAt: 200 } });
    const controller = new AbortController();
    const updates = [];
    await observeConversation({ repo, workspaceID: scenario === 'workspace' ? 'other' : 'ws',
      sessionID: scenario === 'session' ? 'other' : 'abc', signal: controller.signal,
      emit: async update => updates.push(update) });
    assert.equal(updates[0].lastMessageAt, scenario === 'matching' ? 100 : null, scenario);
    controller.abort();
  }
});

for (const scenario of ['unchanged', 'failed', 'cancelled']) {
  test(`search ${scenario} sync cannot establish receipt evidence`, async () => {
    const h = harness({ meta: { lastMessageAt: 100 } });
    h.doc.getList('history').push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Old' }] });
    h.doc.commit();
    const controller = new AbortController();
    h.repo.sync = async () => {
      if (scenario !== 'unchanged') {
        h.doc.getList('history').push({ id: 'new', role: 'assistant', items: [{ type: 'text', text: 'New' }] });
        h.doc.commit();
      }
      if (scenario === 'cancelled') controller.abort();
      return { ok: scenario !== 'failed' };
    };
    const read = readSyncedConversation({ repo: h.repo, workspaceID: 'ws', sessionID: 'abc',
      doc: h.doc, signal: controller.signal });
    if (scenario === 'unchanged') await read;
    else await assert.rejects(read);
    h.repo.sync = async () => ({ ok: true });
    await h.start();
    assert.equal(h.updates[0].lastMessageAt, null);
    h.controller.abort();
  });
}

for (const preload of [false, true]) {
  test(`marker advancing during ${preload ? 'search' : 'observation'} sync retains the original baseline`, async () => {
    const meta = { lastMessageAt: 200 };
    const h = harness({ meta });
    let pulls = 0;
    h.repo.sync = async () => {
      if (++pulls === 1) {
        meta.lastMessageAt = 300;
        h.doc.getList('history').push({ id: 'latest', role: 'assistant', items: [{ type: 'text', text: 'Latest' }] });
        h.doc.commit();
        h.metadataChanged();
      }
      return { ok: true };
    };
    if (preload) await readSyncedConversation({ repo: h.repo, workspaceID: 'ws', sessionID: 'abc',
      doc: h.doc, signal: h.controller.signal });
    await h.start();
    assert.equal(pulls, 2);
    assert.equal(h.updates[0].lastMessageAt, 300);
    await h.flush();
    assert.equal(h.updates.at(-1).lastMessageAt, 300);
    h.controller.abort();
  });
}

test('a newer marker requires another successful pull and remains cancellable', async () => {
  for (const cancel of [false, true]) {
    const meta = { lastMessageAt: 200 };
    const h = harness({ meta });
    let pulls = 0;
    h.repo.sync = async () => {
      if (++pulls === 1) {
        meta.lastMessageAt = 300;
        h.doc.getList('history').push({ id: 'latest', role: 'assistant', items: [{ type: 'text', text: 'Latest' }] });
        h.doc.commit();
        return { ok: true };
      }
      if (cancel) h.controller.abort();
      return { ok: false };
    };
    await h.start();
    assert.equal(pulls, 2);
    assert.deepEqual(h.updates, cancel ? [] : [{ error: 'Conversation sync failed' }]);
    h.controller.abort();
  }
});

test('continuously advancing metadata bounds the number of sync attempts', async () => {
  const meta = { lastMessageAt: 200 };
  const h = harness({ meta });
  let pulls = 0;
  h.repo.sync = async () => { pulls++; meta.lastMessageAt++; return { ok: true }; };
  await h.start();
  assert.equal(pulls, 5);
  assert.deepEqual(h.updates, [{ error: 'Conversation sync failed' }]);
  h.controller.abort();
});
