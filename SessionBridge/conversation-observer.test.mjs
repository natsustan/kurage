import test from 'node:test';
import assert from 'node:assert/strict';
import { LoroDoc } from 'loro-crdt';
import { conversationPatch, observeConversation, readSyncedConversation, syncedConversationVersion } from './conversation-observer.mjs';

function harness({ waitFor, meta = { status: { type: 'running' } }, flock, rootSessionID } = {}) {
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
  const start = () => observeConversation({ repo, workspaceID: 'ws', sessionID: 'abc', rootSessionID, signal: controller.signal,
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
    metadataChanged: (docId = 'session-abc', patch = {}) =>
      metaListener?.({ kind: 'doc-metadata', docId, patch, by: 'sync' }),
    releases: () => releases };
}

test('a late steer metadata ACK patches unchanged history and preserves turn identity', async () => {
  const meta = { status: { type: 'running' } };
  const h = harness({ meta });
  h.doc.getList('history').push({ id: 'guide', role: 'user', status: 'pending_apply',
    items: [{ type: 'text', text: 'Guide' }] });
  h.doc.commit();
  await h.start();
  await h.flush();
  assert.equal(h.updates.at(-1).changed[0].isDeliveryConfirmed, undefined);
  meta.steerTurnStatuses = { guide: 'processing' };
  h.metadataChanged('session-abc', { steerTurnStatuses: meta.steerTurnStatuses });
  await h.flush();
  assert.deepEqual(h.updates.at(-1).order, ['guide']);
  assert.equal(h.updates.at(-1).changed[0].id, 'guide');
  assert.equal(h.updates.at(-1).changed[0].isDeliveryConfirmed, true);
  h.controller.abort();
});

test('a missing-history negative ACK patches unchanged history and removes positive confirmation', async () => {
  const meta = { status: { type: 'running' }, lastHandledUserMsgId: 'guide' };
  const h = harness({ meta });
  h.doc.getList('history').push({ id: 'guide', role: 'user', status: 'pending',
    items: [{ type: 'text', text: 'Guide' }] });
  h.doc.commit();
  await h.start();
  await h.flush();
  assert.equal(h.updates.at(-1).changed[0].isDeliveryConfirmed, true);
  meta.lastMissingHistoryUserMsgId = 'guide';
  h.metadataChanged('session-abc', { lastMissingHistoryUserMsgId: 'guide' });
  await h.flush();
  assert.deepEqual(h.updates.at(-1).order, ['guide']);
  assert.equal(h.updates.at(-1).changed[0].isDeliveryRejected, true);
  assert.equal(h.updates.at(-1).changed[0].isDeliveryConfirmed, undefined);
  h.controller.abort();
});

for (const state of ['missing', 'deleted', 'archived', 'closed']) {
  test(`a remembered ${state} tab publishes its root before opening the transcript`, async () => {
    const h = harness({ rootSessionID: 'root' });
    h.repo.getDocMeta = async () => state === 'missing' ? undefined : {
      deleted: state === 'deleted', meta: { parentSessionId: 'root',
        childSessionPlacement: 'tab', isArchived: state === 'archived', isTabClosed: state === 'closed' },
    };
    h.repo.listDoc = async () => [{ docId: 'session-root', meta: { title: 'Main' } },
      ...(state === 'closed' ? [{ docId: 'session-abc', meta: { parentSessionId: 'root',
        childSessionPlacement: 'tab', isTabClosed: true } }] : [])];
    h.repo.openPersistedDoc = async () => assert.fail('Unavailable tab must not open a transcript');
    assert.equal(await h.start(), false);
    assert.deepEqual(h.updates[0].sessionTabs.map(tab => tab.id), state === 'closed' ? ['root', 'abc'] : ['root']);
    assert.equal(h.updates[0].error, undefined);
    assert.equal(h.rooms.length, 0);
  });
}

test('removing an observed tab publishes the root and releases both live rooms', async () => {
  const meta = { parentSessionId: 'root', childSessionPlacement: 'tab' };
  const h = harness({ rootSessionID: 'root', meta });
  const root = { docId: 'session-root', meta: { title: 'Main' } };
  h.repo.listDoc = async () => [root, { docId: 'session-abc', meta }];
  await h.start();
  h.repo.getDocMeta = async () => undefined;
  h.repo.listDoc = async () => [root];
  h.metadataChanged();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['root']);
  assert.equal(h.updates.at(-1).error, undefined);
  assert.equal(h.releases(), 2);
});

test('deleting a tab during its history pull still falls back without a sync error', async () => {
  const h = harness({ rootSessionID: 'root', meta: { parentSessionId: 'root', lastMessageAt: 100 } });
  h.repo.listDoc = async () => [{ docId: 'session-root', meta: {} }];
  h.repo.sync = async () => {
    h.repo.getDocMeta = async () => ({ deleted: true, meta: { parentSessionId: 'root' } });
    return { ok: true };
  };
  await h.start();
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['root']);
  assert.equal(h.updates.at(-1).error, undefined);
  assert.equal(h.releases(), 2);
});

test('a stale remembered tab refreshes membership if its document cannot open', async () => {
  const h = harness({ rootSessionID: 'root', meta: { parentSessionId: 'root' } });
  h.repo.openPersistedDoc = async () => { throw new Error('Document missing'); };
  h.repo.sync = async options => {
    assert.equal(options.scope, 'meta');
    h.repo.getDocMeta = async () => undefined;
    return { ok: true };
  };
  h.repo.listDoc = async () => [{ docId: 'session-root', meta: {} }];
  assert.equal(await h.start(), false);
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['root']);
});

test('cached history acknowledges a stable synced marker without another content change', async () => {
  const h = harness({ meta: { status: { type: 'idle' }, lastMessageAt: 200 } });
  const history = h.doc.getList('history');
  history.push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Old' }] });
  h.doc.commit();
  await h.start();
  assert.deepEqual(h.updates[0].order, ['old']);
  assert.equal(h.updates[0].lastMessageAt, 200);
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  history.push({ id: 'new', role: 'assistant', items: [{ type: 'text', text: 'New' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  h.controller.abort();
});

test('warm conversation evidence rejects an advanced marker, changed body or another workspace', async () => {
  const meta = { lastMessageAt: 200 };
  const h = harness({ meta });
  await h.start();
  assert.notEqual(syncedConversationVersion(h.repo, 'ws', 'abc', h.doc, { meta }), undefined);
  assert.equal(syncedConversationVersion(h.repo, 'other', 'abc', h.doc, { meta }), undefined);
  assert.equal(syncedConversationVersion(h.repo, 'ws', 'abc', h.doc, { meta: { lastMessageAt: 300 } }), undefined);
  assert.equal(syncedConversationVersion(h.repo, 'ws', 'abc', h.doc, { meta: {} }), undefined);
  h.doc.getMap('acpRuntimeConfig').set('modelId', 'new-model');
  h.doc.commit();
  assert.equal(syncedConversationVersion(h.repo, 'ws', 'abc', h.doc, { meta }), undefined);
  h.controller.abort();
});

test('stream updates reuse a successful pull without requiring repeated visible changes', async () => {
  const meta = { lastMessageAt: 200 };
  const h = harness({ meta });
  let pulls = 0;
  h.repo.sync = async () => { pulls++; return { ok: true }; };
  const history = h.doc.getList('history');
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'text', text: 'Partial' }] });
  h.doc.commit();
  await h.start();
  assert.equal(pulls, 1);
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  for (let index = 0; index < 3; index++) {
    h.metadataChanged();
    h.doc.getMap('acpRuntimeConfig').set('modelId', `model-${index}`);
    h.doc.commit();
    await h.flush();
  }
  assert.equal(pulls, 1);
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  history.delete(0, 1);
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'text', text: 'Completed' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(pulls, 1);
  assert.equal(h.updates.at(-1).changed[0].text, 'Completed');
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  meta.lastMessageAt = 300;
  h.metadataChanged();
  await h.flush();
  assert.equal(pulls, 2);
  assert.equal(h.updates.at(-1).lastMessageAt, 300);
  h.controller.abort();
});

test('completion metadata arriving after the final body can acknowledge the synced turn', async () => {
  const meta = { status: { type: 'running' }, latestUserMsgId: 'u1', lastMessageAt: 100 };
  const h = harness({ meta });
  await h.start();
  const history = h.doc.getList('history');
  history.push({ id: 'u1', role: 'user', items: [{ type: 'text', text: 'Question' }] });
  history.push({ id: 'a1', userTurnId: 'u1', role: 'assistant', finished: true,
    items: [{ type: 'text', text: 'Final answer' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 100);

  meta.lastMessageAt = 200;
  meta.status = { type: 'idle' };
  h.metadataChanged();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).changed, []);
  assert.equal(h.updates.at(-1).lastMessageAt, 200);

  // A later dispatch must complete its own pull before publishing a marker.
  const pull = Promise.withResolvers();
  h.repo.sync = async () => pull.promise;
  meta.latestUserMsgId = 'u2';
  meta.lastMessageAt = 300;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
  pull.resolve({ ok: true });
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 300);
  h.controller.abort();
});

test('synced cached history does not depend on optional completion or dispatch fields', async () => {
  for (const [answer, latestUserMsgId, expected] of [
    [{ userTurnId: 'u1', finished: true }, 'u1', 200],
    [{ userTurnId: 'u1', endedAt: 150 }, 'u1', 200],
    [{ userTurnId: 'u1', finished: false }, 'u1', 200],
    [{ userTurnId: 'other', finished: true }, 'u1', 200],
    [{ finished: true }, 'u1', 200],
    [{ userTurnId: 'u1', finished: true }, 'u2', 200],
    [{ userTurnId: 'u1', finished: true }, undefined, 200],
  ]) {
    const h = harness({ meta: { lastMessageAt: 200, latestUserMsgId } });
    const history = h.doc.getList('history');
    history.push({ id: 'u1', role: 'user', items: [{ type: 'text', text: 'Question' }] });
    history.push({ id: 'a1', role: 'assistant', items: [{ type: 'text', text: 'Answer' }], ...answer });
    h.doc.commit();
    await h.start();
    assert.equal(h.updates.at(-1).lastMessageAt, expected);
    h.controller.abort();
  }
});

test('completed answers cannot bypass a failed history pull', async () => {
  const h = harness({ meta: { lastMessageAt: 200, latestUserMsgId: 'u1' } });
  const history = h.doc.getList('history');
  history.push({ id: 'u1', role: 'user', items: [{ type: 'text', text: 'Question' }] });
  history.push({ id: 'a1', userTurnId: 'u1', role: 'assistant', finished: true,
    items: [{ type: 'text', text: 'Answer' }] });
  h.doc.commit();
  h.repo.sync = async () => ({ ok: false });
  await h.start();
  assert.deepEqual(h.updates, [{ error: 'Conversation sync failed' }]);
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

test('synced receipts survive non-visible updates and same-turn growth', async () => {
  const h = harness({ meta: { lastMessageAt: 200 } });
  const history = h.doc.getList('history');
  history.push({ id: 'old', role: 'assistant', items: [{ type: 'text', text: 'Partial' }] });
  h.doc.commit();
  await h.start();
  h.doc.getMap('acpRuntimeConfig').set('modelId', 'model');
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
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
  let pulls = 0;
  h.repo.sync = async () => { pulls++; return { ok: true }; };
  for (const [workspaceID, timestamp, expected] of [['ws', 100, 100], ['ws', 200, 200], ['other', 100, 100]]) {
    meta.lastMessageAt = timestamp;
    const controller = new AbortController();
    const updates = [];
    await observeConversation({ repo: h.repo, workspaceID, sessionID: 'abc', signal: controller.signal,
      emit: async update => updates.push(update) });
    assert.equal(updates[0].lastMessageAt, expected);
    controller.abort();
  }
  assert.equal(pulls, 2);
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
    sessionID: 'abc', latestTurnNumber: undefined, order: ['b', 'a'], changed: [{ ...a, text: 'one more' }], permission: null, questions: [],
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

test('patch transmits folded work that changes without visible parts changing', () => {
  const before = { id: 'a', author: 'agent', text: 'Done', parts: [{ type: 'text', text: 'Done' }],
    work: { parts: [{ type: 'text', text: 'Working' }] } };
  const after = { ...before, work: { ...before.work, durationMs: 1_000 } };
  const withoutWork = { ...before, work: undefined };
  const turns = turn => ({ sessionID: 'abc', turns: [turn], permission: null });
  assert.deepEqual(conversationPatch(turns(before), turns(after)).changed, [after]);
  assert.deepEqual(conversationPatch(turns(after), turns(withoutWork)).changed, [withoutWork]);
  assert.deepEqual(conversationPatch(turns(after), turns(after)).changed, []);
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

test('task history updates stay independent from session tabs', async () => {
  const h = harness();
  h.repo.listDoc = async () => [{ docId: 'session-abc', meta: {} },
    { docId: 'session-child', meta: { parentSessionId: 'abc', title: 'A separate tab' } }];
  await h.start();
  assert.deepEqual(h.updates[0].subtasks, []);
  const history = h.doc.getList('history');
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'subagent_task', taskId: 'worker', status: 'in_progress' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).subtasks[0].status, 'in_progress');
  history.delete(0, 1);
  history.push({ id: 'a', role: 'assistant', items: [{ type: 'subagent_task', taskId: 'worker', status: 'completed', summary: 'Done' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).subtasks[0].summary, 'Done');
  history.push({ id: 'text', role: 'assistant', items: [{ type: 'text', text: 'Parent output' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(h.updates.at(-1).replacesSubtasks, undefined);

  history.delete(0, 1);
  h.doc.commit();
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

test('metadata-only activity is readable after a stable pull and later history still arrives', async () => {
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
  assert.equal(h.updates.at(-1).lastMessageAt, 200);
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
    let pulls = 0;
    repo.sync = async () => { pulls++; return { ok: true }; };
    const controller = new AbortController();
    const updates = [];
    await observeConversation({ repo, workspaceID: scenario === 'workspace' ? 'other' : 'ws',
      sessionID: scenario === 'session' ? 'other' : 'abc', signal: controller.signal,
      emit: async update => updates.push(update) });
    assert.equal(updates[0].lastMessageAt, scenario === 'newer-marker' ? 200 : 100, scenario);
    assert.equal(pulls, scenario === 'matching' ? 0 : 1, scenario);
    controller.abort();
  }
});

for (const scenario of ['unchanged', 'failed', 'cancelled']) {
  test(`search ${scenario} sync never writes a read receipt`, async () => {
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
    assert.deepEqual(h.updates, []);
    let pulls = 0;
    h.repo.sync = async () => { pulls++; return { ok: true }; };
    await h.start();
    assert.equal(h.updates[0].lastMessageAt, 100);
    assert.equal(pulls, scenario === 'unchanged' ? 0 : 1);
    h.controller.abort();
  });
}

for (const preload of [false, true]) {
  test(`marker advancing during ${preload ? 'search' : 'observation'} sync waits for a stable timestamp`, async () => {
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

test('patches publish timing changes and removal without text changes', () => {
  const before = { sessionID: 'chat', turns: [{ id: 'a', author: 'agent', text: '', timing: { startedAtMs: 1000, permissionWaitMs: 0 } }] };
  const after = { ...before, turns: [{ ...before.turns[0], timing: { startedAtMs: 1000, permissionWaitMs: 5000 } }] };
  assert.equal(conversationPatch(before, after).changed.length, 1);
  assert.equal(conversationPatch(after, { ...after, turns: [{ id: 'a', author: 'agent', text: '' }] }).changed.length, 1);
});


test('metadata changes update the tab group while history changes do not rescan it', async () => {
  const h = harness();
  const rows = [{ docId: 'session-abc', meta: { title: 'Main' } }];
  let scans = 0;
  h.repo.listDoc = async () => { scans++; return rows; };
  await h.start();
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['abc']);
  h.doc.getList('history').push({ id: 'u', role: 'user', items: [{ type: 'text', text: 'Hello' }] });
  h.doc.commit();
  await h.flush();
  assert.equal(scans, 1);
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['abc']);
  rows.push({ docId: 'session-tab', meta: { parentSessionId: 'abc', status: { type: 'running' } } });
  h.metadataChanged();
  await h.flush();
  assert.deepEqual(h.updates.at(-1).sessionTabs.map(tab => tab.id), ['abc', 'tab']);
  assert.equal(h.updates.at(-1).sessionTabs[1].activity, 'running');
  rows[1].meta.isTabClosed = true;
  h.metadataChanged();
  await h.flush();
  assert.equal(h.updates.at(-1).sessionTabs[1].isTabClosed, true);
  // Status churn on the observed session's own row stays visible; churn on an
  // unrelated session in the same workspace must not republish this one.
  const published = h.updates.length;
  h.metadataChanged('session-other', { status: { type: 'running' } });
  await h.flush();
  assert.equal(h.updates.length, published);
  // A tab this session has not seen yet can still announce itself.
  h.metadataChanged('session-appearing', { parentSessionId: 'abc' });
  await h.flush();
  assert.equal(h.updates.length, published + 1);
  h.controller.abort();
});
