import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import { LoroDoc } from 'loro-crdt';
import { StreamsClient } from '@loro-dev/streams-client';
import { createNativeFetch } from './native-fetch.mjs';
import { readSyncedConversation, syncedConversationVersion } from './conversation-observer.mjs';
import { selectMentionSkills } from './mention-skills.mjs';
import { createSessionOptionsCache } from './session-options-cache.mjs';
import { newSessionOptions } from './session-start.mjs';
import { runningSessionTabParents } from './session-tabs.mjs';
import { projectSessionActivity } from './session-activity.mjs';
import { turnDiffSource } from './turn-diff.mjs';
import { projectGitSource } from './project-git.mjs';
import { notificationSessionDestination } from './notification-session.mjs';
import {
  activityTime,
  deleteArchivedSession,
  readLocalProjectState,
  restoreArchivedSession,
  selectArchivedSessions,
} from './session-archive.mjs';

const source = (await readFile(new URL('./bridge.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '');

function makeBridge(sync = async () => ({ ok: true }), rows = [], cancel = async () => 'requested', archive = async () => ({ status: 'archived', sessionIDs: ['chat'] }), extras = {}) {
  const repos = [];
  const transports = [];
  class Repo {
    constructor() { this.destroyed = false; this.loaded = new Set(); }
    static async create() {
      const repo = new Repo();
      repos.push(repo);
      return repo;
    }
    async addTransport(_id, transport) { this.transport = transport.options; transports.push(transport.options); }
    async sync(options) { return sync(options, this); }
    async listDoc() { return rows; }
    async openFlockDoc(docID) {
      if (extras.openFlockDoc) return extras.openFlockDoc(docID, this);
      return {
        syncOnce: () => sync({ scope: 'doc', flockDocIds: [docID] }),
        flock: { scan: () => [] },
      };
    }
    async openPersistedDoc(id) {
      this.loaded.add(id);
      if (extras.openPersistedDoc) return extras.openPersistedDoc(id, this);
      return { doc: { getList: () => ({ toJSON: () => [] }), getMap: () => ({ toJSON: () => ({ modelId: this.model }) }) } };
    }
    async unloadDoc(id) { this.loaded.delete(id); await extras.unloadDoc?.(id, this); }
    async getDocMeta(id) { return extras.getDocMeta ? extras.getDocMeta(id, this) : rows.find(row => row.docId === id); }
    async destroy() { this.destroyed = true; this.loaded.clear(); await extras.destroy?.(this); }
  }
  class Transport {
    constructor(options) { this.options = options; }
    async forgetDoc(id) { await extras.forgetDoc?.(id, this); }
  }
  const window = { webkit: { messageHandlers: { streamFetch: { postMessage: extras.postMessage } } } };
  const context = vm.createContext({
    window,
    LoroRepo: Repo,
    StreamsTransportAdapter: Transport,
    decompressZstd: async (bytes) => bytes,
    createNativeFetch: extras.createNativeFetch ?? (() => ({ fetch: async () => {}, receive: async () => {} })),
    createSessionOptionsCache: () => createSessionOptionsCache(extras.now),
    projectConversation: () => ({}),
    projectSessionActivity,
    runningSessionTabParents,
    observeConversation: extras.observeConversation ?? (async () => {}),
    readSyncedConversation,
    syncedConversationVersion: extras.syncedConversationVersion ?? syncedConversationVersion,
    cancelSession: cancel,
    newSessionOptions: extras.newSessionOptions ?? newSessionOptions,
    startSession: extras.startSession,
    sessionProjects: extras.sessionProjects,
    archiveSession: archive,
    updateSessionMetadata: extras.updateSessionMetadata,
    respondQuestion: extras.respondQuestion,
    activityTime,
    selectArchivedSessions,
    readLocalProjectState: extras.readLocalProjectState ?? readLocalProjectState,
    restoreArchivedSession: extras.restoreArchivedSession ?? restoreArchivedSession,
    deleteArchivedSession: extras.deleteArchivedSession ?? deleteArchivedSession,
    mentionSkills: extras.mentionSkills,
    sendText: extras.sendText,
    requestMachine: extras.requestMachine,
    turnDiffSource,
    loadTurnDiff: extras.loadTurnDiff,
    projectGitSource: extras.projectGitSource ?? projectGitSource,
    notificationSessionDestination,
    readProjectGit: extras.readProjectGit,
    fetch: async () => {},
    AbortController,
    setTimeout,
    clearTimeout,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

test('notification destination uses freshly synced workspace metadata only and releases its replica', async () => {
  const pulls = [];
  const rows = [{ docId: 'session-root', meta: {} },
    { docId: 'session-tab', meta: { parentSessionId: 'root', isTabClosed: true } }];
  const { window, repos } = makeBridge(async (options, repo) => {
    pulls.push({ scope: options.scope, workspace: repo.transport.metaStreamId });
    return { ok: true };
  }, rows, undefined, undefined, {
    openPersistedDoc: () => { throw new Error('Notification routing must not open history'); },
  });
  await window.kurageSessions('workspace', 'https://streams.test');
  pulls.length = 0;
  const result = JSON.parse(await window.kurageNotificationDestination('workspace', 'tab', 'https://streams.test', 'push-read'));
  assert.deepEqual(result, { destination: { rootSessionID: 'root', sessionID: 'tab', isTabClosed: true } });
  assert.deepEqual(pulls, [{ scope: 'meta', workspace: 'workspace:meta' }]);
  assert.equal(repos[0].destroyed, false);
  assert.equal(repos[1].destroyed, true);
  await window.kurageNotificationDestination('other', 'root', 'https://streams.test', 'other-push');
  assert.deepEqual(pulls[1], { scope: 'meta', workspace: 'other:meta' });
  assert.equal(repos[2].destroyed, true);
});

test('cancelled notification lookup cannot publish late metadata', async () => {
  let started, finish;
  const ready = new Promise(resolve => { started = resolve; });
  const delayed = new Promise(resolve => { finish = resolve; });
  const { window, repos } = makeBridge(async () => { started(); return delayed; },
    [{ docId: 'session-root', meta: {} }]);
  const request = window.kurageNotificationDestination('workspace', 'root', 'https://streams.test', 'cancelled-push');
  await ready;
  window.kurageCancel('cancelled-push');
  finish({ ok: true });
  await assert.rejects(request, { name: 'AbortError' });
  assert.equal(repos[0].destroyed, true);
});

test('turn diff releases the metadata read lock and keeps RPC cancellation alive', async () => {
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  let rpcSignal;
  const bridge = makeBridge(undefined, [{ docId: 'session-chat', meta: { machineId: 'machine' } }],
    undefined, undefined, { loadTurnDiff: async (source, access, workspace, session, turn, path, signal) => {
      assert.equal(source.machineID, 'machine');
      assert.equal(source.ownerSessionID, 'chat');
      assert.equal(workspace, 'workspace');
      assert.equal(turn, 'turn');
      assert.equal(path, 'file.swift');
      assert.equal(signal.aborted, false);
      rpcSignal = signal;
      started();
      return await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    } });
  const request = bridge.window.kurageTurnDiff('workspace', 'chat', 'https://streams.test', 'turn', 'file.swift', 'diff-request');
  void request.catch(() => {});
  await ready;
  await bridge.window.kurageSessions('workspace', 'https://streams.test', 'list-request');
  assert.equal(rpcSignal.aborted, false);
  bridge.window.kurageCancel('diff-request');
  await assert.rejects(request, { name: 'AbortError' });
  assert.equal(rpcSignal.aborted, true);
});

test('project Git releases metadata lock, scopes token refresh and cancels only its own machine read', async () => {
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  let rpcSignal;
  let bound;
  const bridge = makeBridge(undefined, [], undefined, undefined, {
    projectGitSource: async (_repo, workspace, template, project) => {
      assert.equal(workspace, 'workspace'); assert.equal(template, 'template'); assert.equal(project, 'local:mac:p');
      return { machineID: 'mac', localProjectID: 'p' };
    },
    createNativeFetch: () => ({ fetch: async () => {}, receive() {}, bindSignal: (token, signal) => { bound = { token, signal }; } }),
    postMessage: async message => {
      assert.equal(message.workspaceID, 'workspace'); assert.equal(message.operationID, 'git-read');
      assert.equal(message.refresh, true);
      return { token: 'scoped-token' };
    },
    readProjectGit: async (source, access, workspace, user, signal) => {
      assert.equal(source.machineID, 'mac'); assert.equal(user, 'user');
      assert.equal(await access.auth({ reason: 'unauthorized' }), 'scoped-token');
      assert.equal(bound.signal, signal);
      rpcSignal = signal; started();
      return await new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
  });
  const pending = bridge.window.kurageProjectGit('workspace', 'https://streams.test', 'template', 'local:mac:p', 'user', 'git-read');
  void pending.catch(() => {});
  await ready;
  await bridge.window.kurageSessions('workspace', 'https://streams.test', 'list');
  assert.equal(rpcSignal.aborted, false);
  bridge.window.kurageCancel('git-read');
  await assert.rejects(pending, { name: 'AbortError' });
});

const gitProjectRows = [{ docId: 'session-template', meta: {
  machineId: 'mac', project: { kind: 'local', localProjectId: 'p' },
} }];
const gitProjectFlock = (pending = false) => ({ flock: { scan: ({ prefix }) => {
  if (prefix[0] === 'localProject') return [{ key: ['localProject', 'p'], value: { name: 'Project' } }];
  if (prefix[0] === 'cmd' && pending) return [{ key: ['cmd', 'deleteLocalProject', 'p'] }];
  return [];
} } });

test('project Git reuses list metadata and a fresh catalog while every read gets the current branch', async () => {
  const pulls = [];
  let reads = 0;
  const { window, repos } = makeBridge(async options => {
    pulls.push(options);
    return { ok: true };
  }, gitProjectRows, undefined, undefined, {
    openFlockDoc: () => gitProjectFlock(),
    readProjectGit: async () => ({ state: { git: true, currentBranch: `branch-${++reads}` } }),
  });
  await window.kurageSessions('workspace', 'https://streams.test');
  pulls.length = 0;
  for (let read = 1; read <= 2; read++) {
    const result = JSON.parse(await window.kurageProjectGit('workspace', 'https://streams.test',
      'template', 'local:mac:p', 'user', `git-${read}`));
    assert.equal(result.state.currentBranch, `branch-${read}`);
  }
  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  assert.deepEqual(pulls, []);
});

test('project Git refreshes an expired catalog once and checks newly pending project deletions', async () => {
  let now = 0;
  let pending = false;
  let reads = 0;
  const pulls = [];
  const { window, repos } = makeBridge(async options => {
    pulls.push(options);
    return { ok: true };
  }, gitProjectRows, undefined, undefined, {
    now: () => now,
    openFlockDoc: () => gitProjectFlock(pending),
    readProjectGit: async () => { reads++; return { state: { git: true } }; },
  });
  await window.kurageSessions('workspace', 'https://streams.test');
  pulls.length = 0;
  now = 30_000;
  await window.kurageProjectGit('workspace', 'https://streams.test', 'template', 'local:mac:p', 'user');
  await window.kurageProjectGit('workspace', 'https://streams.test', 'template', 'local:mac:p', 'user');
  assert.equal(pulls.length, 1);
  assert.equal(pulls[0].scope, 'doc');
  assert.deepEqual([...pulls[0].flockDocIds], ['workspace:mf:mac']);
  assert.equal(repos.length, 2);
  assert.equal(repos[1].destroyed, true);
  assert.equal(reads, 2);
  now += 30_000;
  pending = true;
  await assert.rejects(window.kurageProjectGit('workspace', 'https://streams.test',
    'template', 'local:mac:p', 'user'), /Project is unavailable/);
  assert.equal(reads, 2);
});

test('project Git never borrows metadata or the project catalog from a different workspace or gateway', async () => {
  const pulls = [];
  const { window, repos } = makeBridge(async (options, repo) => {
    pulls.push({ scope: options.scope, metaStreamID: repo.transport.metaStreamId, baseURL: repo.transport.baseUrl });
    return { ok: true };
  }, gitProjectRows, undefined, undefined, {
    openFlockDoc: () => gitProjectFlock(),
    readProjectGit: async () => ({ state: { git: true } }),
  });
  await window.kurageSessions('workspace', 'https://streams.test');
  pulls.length = 0;
  await window.kurageProjectGit('other', 'https://streams.test', 'template', 'local:mac:p', 'user');
  await window.kurageProjectGit('workspace', 'https://other.test', 'template', 'local:mac:p', 'user');
  assert.deepEqual(pulls, [
    { scope: 'meta', metaStreamID: 'other:meta', baseURL: 'https://streams.test' },
    { scope: 'doc', metaStreamID: 'other:meta', baseURL: 'https://streams.test' },
    { scope: 'meta', metaStreamID: 'workspace:meta', baseURL: 'https://other.test' },
    { scope: 'doc', metaStreamID: 'workspace:meta', baseURL: 'https://other.test' },
  ]);
  assert.equal(repos.length, 3);
  assert.ok(repos.slice(1).every(repo => repo.destroyed));
  assert.equal(repos[0].destroyed, false);
});

test('cancelling an expired project catalog read discards it and preserves the shared workspace', async () => {
  let now = 0;
  let started;
  let finish;
  let reads = 0;
  const ready = new Promise(resolve => { started = resolve; });
  const delayed = new Promise(resolve => { finish = resolve; });
  const pulls = [];
  const { window, repos } = makeBridge(async options => {
    pulls.push(options);
    if (now > 0 && options.scope === 'doc') {
      started();
      return delayed;
    }
    return { ok: true };
  }, gitProjectRows, undefined, undefined, {
    now: () => now,
    openFlockDoc: () => gitProjectFlock(),
    readProjectGit: async () => { reads++; return { state: { git: true } }; },
  });
  await window.kurageSessions('workspace', 'https://streams.test');
  now = 30_000;
  const read = window.kurageProjectGit('workspace', 'https://streams.test',
    'template', 'local:mac:p', 'user', 'cancelled-git');
  await ready;
  window.kurageCancel('cancelled-git');
  finish({ ok: true });
  await assert.rejects(read, { name: 'AbortError' });
  assert.equal(reads, 0);
  assert.equal(repos[0].destroyed, false);
  assert.equal(repos[1].destroyed, true);
  pulls.length = 0;
  await window.kurageProjectGit('workspace', 'https://streams.test', 'template', 'local:mac:p', 'user');
  assert.equal(pulls.length, 1);
  assert.equal(pulls[0].scope, 'doc');
  assert.equal(reads, 1);
});

test('isolated transcript reads restore history with a fresh replica and cursor', async () => {
  const remote = new LoroDoc();
  remote.getList('history').push({ id: 'turn', role: 'user', items: [{ type: 'text', text: 'Hello' }] });
  remote.commit();
  const snapshot = remote.export({ mode: 'snapshot' });
  const documents = new Map();
  const cursors = new Map();
  const { window, repos } = makeBridge(async (options, repo) => {
    if (options.docIds?.includes('session-chat') && !cursors.has(repo)) {
      documents.get(repo).import(snapshot);
      cursors.set(repo, 'end-of-history');
    }
    return { ok: true };
  }, [{ docId: 'session-chat', meta: {} }], undefined, undefined, {
    openPersistedDoc: (_id, repo) => {
      if (!documents.has(repo)) documents.set(repo, new LoroDoc());
      return { doc: documents.get(repo) };
    },
    destroy: repo => {
      documents.delete(repo);
      cursors.delete(repo);
    },
  });
  for (let attempt = 0; attempt < 3; attempt++) {
    const conversation = JSON.parse(await window.kurageConversation('workspace', 'chat',
      'https://gateway.lody.ai', `read-${attempt}`));
    assert.deepEqual(conversation.turns.map(turn => turn.text), ['Hello']);
    assert.equal(documents.size, 0);
    assert.equal(cursors.size, 0);
    assert.equal(repos.length, attempt + 1);
    assert.ok(repos.every(repo => repo.destroyed));
  }
});

test('one-shot reads preserve the replica and cursor of an active observation', async () => {
  let forgets = 0;
  const { window, repos } = makeBridge(undefined, [{ docId: 'session-chat', meta: {} }], undefined, undefined, {
    observeConversation: async ({ repo }) => { await repo.openPersistedDoc('session-chat'); },
    forgetDoc: () => { forgets++; },
  });
  await window.kurageObserveConversation('workspace', 'chat', 'https://gateway.lody.ai', 'observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read');
  assert.equal(repos[0].loaded.has('session-chat'), true);
  assert.equal(forgets, 0);
  window.kurageStopConversation('observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'after-stop');
  assert.equal(repos[0].loaded.has('session-chat'), false);
  assert.equal(forgets, 1);
});

test('mention sessions stay in the current project and include child sessions', async () => {
  const rows = [
    { docId: 'session-current', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Current', lastMessageAt: 8 } },
    { docId: 'session-child', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, parentSessionId: 'current', title: 'Review', lastMessageAt: 9 } },
    { docId: 'session-root', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Other', lastMessageAt: 7 } },
    { docId: 'session-archived', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Archived', isArchived: true } },
    { docId: 'session-other-project', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'other' }, title: 'Elsewhere' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true }), rows);
  const result = JSON.parse(await window.kurageMentionSessions('workspace', 'https://gateway.lody.ai',
    'current', 'local:machine:project', 'request'));
  assert.deepEqual(result.sessions.map(session => session.id), ['child', 'root']);
});

test('mention reads reuse synced workspace metadata without another network sync', async () => {
  let metaSyncs = 0;
  const rows = [{ docId: 'session-template', meta: {
    machineId: 'machine', agentType: 'codex',
    project: { kind: 'local', localProjectId: 'project' },
  } }];
  const { window, repos } = makeBridge(async options => {
    if (options.scope === 'meta') metaSyncs++;
    return { ok: true };
  }, rows, undefined, undefined, { mentionSkills: async () => [] });
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  await window.kurageMentionSessions('workspace', 'https://gateway.lody.ai', 'template', 'local:machine:project', 'sessions');
  await window.kurageMentionSkills('workspace', 'https://gateway.lody.ai', 'template', null, 'user', 'skills');
  assert.equal(metaSyncs, 1);
  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  await window.kurageMentionSessions('other-workspace', 'https://gateway.lody.ai', 'template', 'local:machine:project', 'other');
  assert.equal(metaSyncs, 2);
  assert.equal(repos[1].destroyed, true);
});

test('cancelling a skill source read does not start the machine scan', async () => {
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  let scanned = false;
  const { window, repos } = makeBridge(async options => {
    entered();
    await new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true }));
  }, [], undefined, undefined, { mentionSkills: async () => { scanned = true; return []; } });
  const request = window.kurageMentionSkills('workspace', 'https://gateway.lody.ai', 'template', null, 'user', 'cancel-source');
  await started;
  window.kurageCancel('cancel-source');
  await assert.rejects(request, { name: 'AbortError' });
  assert.equal(scanned, false);
  assert.equal(repos[0].destroyed, true);
});

test('skill request uses the template machine, project, agent, workspace and user', async () => {
  let request;
  const rows = [{ docId: 'session-template', meta: {
    machineId: 'machine', agentConfigId: 'config', agentType: 'codex',
    project: { kind: 'local', localProjectId: 'project' },
  } }];
  const { window } = makeBridge(async () => ({ ok: true }), rows, undefined, undefined, {
    mentionSkills: async args => { request = args; return [{ token: 'review', name: 'Review', description: '', path: 'review/SKILL.md' }]; },
  });
  const result = JSON.parse(await window.kurageMentionSkills('workspace', 'https://gateway.lody.ai',
    'template', null, 'user', 'request'));
  assert.equal(result.skills[0].token, 'review');
  assert.equal(request.workspaceID, 'workspace');
  assert.equal(request.machineID, 'machine');
  assert.equal(request.localProjectID, 'project');
  assert.equal(request.agentType, 'codex');
  assert.equal(request.userID, 'user');
});

test('mention skills use legacy CLI fallback while preserving explicit agent selection', async () => {
  const groups = [
    { scope: 'project', dir: '.agents/skills', skills: [
      { name: 'codex-skill', relativePath: '.agents/skills/codex-skill/SKILL.md' },
    ] },
    { scope: 'project', dir: '.claude/skills', skills: [
      { name: 'claude-skill', relativePath: '.claude/skills/claude-skill/SKILL.md' },
    ] },
  ];
  for (const [agent, expected] of [
    [{ cliType: 'codex' }, ['codex-skill']],
    [{ cliType: 'claude' }, ['claude-skill']],
    [{ cliType: 'codex', agentType: 'claude' }, ['claude-skill']],
    [{ cliType: 'codex', agentType: 'custom-agent' }, []],
    [{ cliType: 'builtin' }, []],
    [{}, []],
  ]) {
    const rows = [{ docId: 'session-template', meta: { machineId: 'machine', ...agent } }];
    const { window } = makeBridge(undefined, rows, undefined, undefined, {
      mentionSkills: async ({ agentType }) => selectMentionSkills([{ groups }], agentType),
    });
    const result = JSON.parse(await window.kurageMentionSkills('workspace', 'https://gateway.lody.ai',
      'template', null, 'user', 'request'));
    assert.deepEqual(result.skills.map(skill => skill.token), expected, JSON.stringify(agent));
  }
});

test('session cancellation uses the requested workspace and releases its writer', async () => {
  let request;
  const { window, repos, transports } = makeBridge(
    async () => ({ outcome: 'synced', ok: true }), [],
    async (repo, sessionID) => { request = { repo, sessionID }; return 'requested'; },
  );
  assert.equal(await window.kurageCancelSession('workspace', 'chat', 'https://gateway.lody.ai'), 'requested');
  assert.equal(request.sessionID, 'chat');
  assert.equal(request.repo, repos[0]);
  assert.equal(transports[0].metaStreamId, 'workspace:meta');
  assert.equal(repos[0].destroyed, true);
});

test('archiving uses a short-lived writer for the requested session', async () => {
  let request;
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced', ok: true }), [], async () => 'requested',
    async (repo, sessionID) => {
      request = { repo, sessionID };
      return { status: 'archived', sessionIDs: ['chat', 'opened'] };
    });
  assert.deepEqual(
    JSON.parse(await window.kurageArchiveSession('workspace', 'chat', 'https://gateway.lody.ai')),
    { status: 'archived', sessionIDs: ['chat', 'opened'] },
  );
  assert.equal(request.sessionID, 'chat');
  assert.equal(request.repo, repos[0]);
  assert.equal(repos[0].destroyed, true);
});

test('archived sessions stay out of the active list and keep newest-first order', async () => {
  const rows = [
    { docId: 'session-older', meta: { isArchived: true, title: 'Older', lastMessageAt: 1 } },
    { docId: 'session-newer', meta: { isArchived: true, title: 'Newer', lastMessageAt: 5 } },
    { docId: 'session-tab', meta: { isArchived: true, parentSessionId: 'newer', title: 'Tab', lastMessageAt: 9 } },
    { docId: 'session-live', meta: { title: 'Live', lastMessageAt: 3 } },
    { docId: 'session-comment-newer', meta: { isArchived: true, title: 'Comment' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true, outcome: 'synced' }), rows);
  const active = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active'));
  const archived = JSON.parse(await window.kurageArchivedSessions('workspace', 'https://gateway.lody.ai', 'archived'));
  assert.deepEqual(active.sessions.map(session => session.id), ['live']);
  assert.deepEqual(archived.sessions.map(session => session.id), ['newer', 'older']);
  assert.equal(archived.sessions[0].canRestore, true);
});

test('restore and delete use a short-lived writer', async () => {
  let restored;
  let deleted;
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced', ok: true }), [], async () => 'requested', async () => 'archived', {
    restoreArchivedSession: async (repo, workspaceID, sessionID) => {
      restored = { repo, workspaceID, sessionID };
      return 'restored';
    },
    deleteArchivedSession: async (repo, sessionID) => {
      deleted = { repo, sessionID };
      return 'deleted';
    },
  });
  assert.equal(await window.kurageRestoreArchivedSession('workspace', 'chat', 'https://gateway.lody.ai'), 'restored');
  assert.equal(await window.kurageDeleteArchivedSession('workspace', 'chat', 'https://gateway.lody.ai'), 'deleted');
  assert.equal(restored.workspaceID, 'workspace');
  assert.equal(restored.sessionID, 'chat');
  assert.equal(deleted.sessionID, 'chat');
  assert.equal(restored.repo, repos[0]);
  assert.equal(deleted.repo, repos[1]);
  assert.equal(repos[0].destroyed, true);
  assert.equal(repos[1].destroyed, true);
});

test('refresh reuses the workspace repo', async () => {
  const { window, repos, transports } = makeBridge();
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'first');
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'second');

  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  assert.equal(typeof transports[0].auth, 'function');

  await window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'third');
  assert.equal(repos.length, 2);
  assert.equal(repos[0].destroyed, true);
});

test('cancelling a queued refresh leaves the current workspace intact', async () => {
  let beginSync;
  const started = new Promise((resolve) => { beginSync = resolve; });
  let finishSync;
  const pendingSync = new Promise((resolve) => { finishSync = resolve; });
  let syncCount = 0;
  const { window, repos } = makeBridge(async () => {
    syncCount += 1;
    if (syncCount === 1) {
      beginSync();
      return pendingSync;
    }
    return { ok: true };
  });

  const first = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'first');
  await started;
  const cancelled = window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'cancelled');
  window.kurageCancel('cancelled');
  finishSync({ ok: true });

  await first;
  await assert.rejects(cancelled, { name: 'AbortError' });
  assert.equal(syncCount, 1);
  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
});

test('cancelling an active refresh aborts its sync', async () => {
  let beginSync;
  const started = new Promise((resolve) => { beginSync = resolve; });
  const { window } = makeBridge(({ signal }) => new Promise((_resolve, reject) => {
    beginSync();
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  }));

  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active');
  await started;
  window.kurageCancel('active');

  await assert.rejects(refresh, { name: 'AbortError' });
});

const localSession = {
  docId: 'session-local',
  meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' } },
};

test('stopping observation during metadata setup releases the next refresh', async () => {
  let beginSync;
  const started = new Promise(resolve => { beginSync = resolve; });
  let finishSync;
  let aborted = false;
  let syncCount = 0;
  const { window } = makeBridge(({ signal }) => {
    if (++syncCount > 1) return { ok: true };
    return new Promise((resolve, reject) => {
      finishSync = () => resolve({ ok: true });
      signal?.addEventListener('abort', () => {
        aborted = true;
        reject(signal.reason);
      }, { once: true });
      beginSync();
    });
  });
  const observation = window.kurageObserveConversation('workspace', 'session', 'https://gateway.lody.ai', 'observe');
  const outcome = observation.then(() => null, error => error);
  await started;
  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh');
  try {
    window.kurageStopConversation('observe');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(aborted, true);
    assert.equal((await outcome)?.name, 'AbortError');
    assert.equal(syncCount, 2);
    assert.deepEqual(JSON.parse(await refresh), { sessions: [] });
  } finally {
    finishSync();
    await Promise.allSettled([observation, refresh]);
  }
});

test('cancelling machine sync releases the queued workspace refresh', async () => {
  let beginSync;
  const started = new Promise(resolve => { beginSync = resolve; });
  let finishSync;
  let aborted = false;
  const { window, repos } = makeBridge(options => {
    if (options.scope !== 'doc' || options.flockDocIds[0] !== 'workspace:mf:machine') {
      return { ok: true };
    }
    return new Promise((resolve, reject) => {
      finishSync = () => resolve({ ok: true });
      options.signal?.addEventListener('abort', () => {
        aborted = true;
        reject(options.signal.reason);
      }, { once: true });
      beginSync();
    });
  }, [localSession]);

  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active');
  const outcome = refresh.then(() => null, error => error);
  await started;
  const replacement = window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'next');
  try {
    window.kurageCancel('active');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(aborted, true);
    assert.equal((await outcome)?.name, 'AbortError');
    assert.equal(repos.length, 2);
    assert.equal(repos[0].destroyed, true);
    assert.equal(JSON.parse(await replacement).sessions[0].id, 'local');
  } finally {
    finishSync();
    await Promise.allSettled([refresh, replacement]);
  }
});

test('optional machine sync failure still returns sessions with a fallback project name', async () => {
  const { window } = makeBridge(({ scope }) => {
    if (scope === 'doc') throw new Error('Machine unavailable');
    return { ok: true };
  }, [localSession]);

  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].projectName, 'Local Project');
});

test('session list includes the machine name and pin from workspace metadata', async () => {
  const rows = [
    { ...localSession, meta: { ...localSession.meta, isPinned: true, lastMessageAt: 200, lastReadAt: 100 } },
    { docId: 'machine-machine', meta: { name: 'spike@mac' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true }), rows);

  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].machineName, 'spike@mac');
  assert.equal(result.sessions[0].isPinned, true);
  assert.equal(result.sessions[0].lastMessageAt, 200);
  assert.equal(result.sessions[0].lastReadAt, 100);
});

test('cancelling a transcript read releases the queued conversation observation', async () => {
  const started = Promise.withResolvers();
  let aborted = false;
  const { window } = makeBridge(options => {
    if (options.scope !== 'doc') return { ok: true };
    assert.deepEqual(Array.from(options.docIds), ['session-chat']);
    started.resolve();
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => {
        aborted = true;
        reject(options.signal.reason);
      }, { once: true });
    });
  }, [{ docId: 'session-chat', meta: {} }]);
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  await started.promise;
  const observation = window.kurageObserveConversation('workspace', 'chat', 'https://gateway.lody.ai', 'observe');
  window.kurageCancel('search');
  await outcome;
  await observation;
  assert.equal(aborted, true);
});

test('cancelling a queued transcript read skips document sync', async () => {
  const started = Promise.withResolvers();
  const finish = Promise.withResolvers();
  let syncs = 0;
  const { window } = makeBridge(() => {
    syncs += 1;
    started.resolve();
    return finish.promise;
  }, [{ docId: 'session-chat', meta: {} }]);
  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh');
  await started.promise;
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  window.kurageCancel('search');
  finish.resolve({ ok: true });
  await refresh;
  await outcome;
  assert.equal(syncs, 1);
});


test('one-shot reads release all loaded transcripts on success and sync failure', async () => {
  let fail = false;
  const { window, repos } = makeBridge(async () => {
    if (fail) throw new Error('offline');
    return { ok: true };
  }, ['a', 'b', 'c'].map(id => ({ docId: `session-${id}`, meta: {} })));
  for (const id of ['a', 'b', 'c']) {
    await window.kurageConversation('workspace', id, 'https://gateway.lody.ai', id);
    assert.equal(repos[0].loaded.size, 0);
  }
  fail = true;
  await assert.rejects(window.kurageConversation('workspace', 'a', 'https://gateway.lody.ai', 'failure'), /offline/);
  assert.equal(repos[0].loaded.size, 0);
});

test('a one-shot read does not unload an observed conversation', async () => {
  const { window, repos } = makeBridge(async () => ({ ok: true }),
    [{ docId: 'session-chat', meta: {} }], undefined, undefined, {
      observeConversation: async ({ repo }) => { await repo.openPersistedDoc('session-chat'); },
    });
  await window.kurageObserveConversation('workspace', 'chat', 'https://gateway.lody.ai', 'observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read');
  assert.equal(repos[0].loaded.has('session-chat'), true);
  window.kurageStopConversation('observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read-again');
  assert.equal(repos[0].loaded.size, 0);
});


test('cancelling an unobserved search read unloads its document', async () => {
  const started = Promise.withResolvers();
  const { window, repos } = makeBridge(options => {
    if (options.scope !== 'doc') return { ok: true };
    started.resolve();
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
    });
  }, [{ docId: 'session-chat', meta: {} }]);
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  await started.promise;
  window.kurageCancel('search');
  await outcome;
  assert.equal(repos[0].loaded.size, 0);
});


test('cold new-session options cancel their sync and destroy the temporary reader', async () => {
  let entered;
  const ready = new Promise(resolve => { entered = resolve; });
  let observedSignal;
  const { window, repos } = makeBridge(async ({ signal }) => {
    observedSignal = signal;
    entered();
    await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
  });
  const pending = window.kurageNewSessionOptions('ws', 'template', null, 'https://gateway.lody.ai', 'options-1');
  await ready;
  window.kurageCancel('options-1');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(observedSignal.aborted, true);
  assert.equal(repos[0].destroyed, true);
});

test('new-session options reuse the synced reader without resyncing metadata', async () => {
  const scopes = [];
  const { window, repos } = makeBridge(options => {
    scopes.push(options.scope);
    return { ok: true, outcome: 'synced' };
  }, undefined, undefined, undefined, {
    newSessionOptions: async () => ({ agentConfigID: 'codex', providers: [], runConfig: {} }),
  });
  await window.kurageSessions('ws', 'https://gateway.lody.ai', 'sessions');
  const first = JSON.parse(await window.kurageNewSessionOptions('ws', 'template', null, 'https://gateway.lody.ai', 'options-1'));
  assert.equal(first.agentConfigID, 'codex');
  const second = JSON.parse(await window.kurageNewSessionOptions('ws', 'template', null, 'https://gateway.lody.ai', 'options-2'));
  assert.equal(second.agentConfigID, 'codex');
  assert.equal(repos.length, 1);
  assert.equal(scopes.filter(scope => scope === 'meta').length, 1);
});


test('metadata edits use the requested workspace and release their replica on success or failure', async () => {
  for (const fails of [false, true]) {
    let request;
    const { window, repos, transports } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
      updateSessionMetadata: async (repo, sessionID, change) => {
        request = { repo, sessionID, change };
        if (fails) throw new Error('write failed');
        return 'updated';
      },
    });
    const operation = window.kurageUpdateSessionMetadata('workspace-other', 'chat', 'https://gateway.lody.ai', { isPinned: true });
    if (fails) await assert.rejects(operation, /write failed/);
    else assert.equal(await operation, 'updated');
    assert.equal(request.sessionID, 'chat');
    assert.equal(request.repo, repos[0]);
    assert.equal(request.change.isPinned, true);
    assert.equal(repos[0].destroyed, true);
    assert.equal(transports[0].metaStreamId, 'workspace-other:meta');
  }
});

for (const phase of ['initial sync', 'write sync']) {
  test(`metadata cancellation during ${phase} aborts and releases its replica`, async () => {
    const started = Promise.withResolvers();
    let observedSignal;
    let writes = 0;
    const waitForCancellation = async signal => {
      observedSignal = signal;
      started.resolve();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    };
    const { window, repos } = makeBridge(async ({ signal }) => {
      if (phase === 'initial sync') await waitForCancellation(signal);
      return { outcome: 'synced' };
    }, [], undefined, undefined, {
      updateSessionMetadata: async (repo, sessionID, change, signal) => {
        writes++;
        await waitForCancellation(signal);
      },
    });
    const pending = window.kurageUpdateSessionMetadata('ws', 'chat', 'https://gateway.lody.ai', { isPinned: true }, 'edit');
    await started.promise;
    window.kurageCancel('edit');
    await assert.rejects(pending, { name: 'AbortError' });
    assert.equal(observedSignal.aborted, true);
    assert.equal(writes, phase === 'initial sync' ? 0 : 1);
    assert.equal(repos[0].destroyed, true);
  });
}

test('metadata cancellation prevents writes even when initial sync completes successfully after abort', async () => {
  const started = Promise.withResolvers();
  const sync = Promise.withResolvers();
  const { window, repos } = makeBridge(() => {
    started.resolve();
    return sync.promise;
  }, [], undefined, undefined, {
    updateSessionMetadata: async () => assert.fail('unexpected metadata write'),
  });
  const pending = window.kurageUpdateSessionMetadata('ws', 'chat', 'https://gateway.lody.ai', { title: 'New' }, 'edit');
  await started.promise;
  window.kurageCancel('edit');
  sync.resolve({ outcome: 'synced' });
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(repos[0].destroyed, true);
});


test('session list preserves the creation-time sorting fallback without inventing a message marker', async () => {
  const { window } = makeBridge(async () => ({ ok: true }), [
    { ...localSession, meta: { ...localSession.meta, lastMessageAt: undefined, createdAt: '2026-01-01T00:00:00Z' } },
  ]);
  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].lastMessageAt, null);
  assert.equal(result.sessions[0].lastActivityAt, Date.parse('2026-01-01T00:00:00Z'));
});


test('question writes scope requests and cancellation to an ephemeral existing-stream replica', async () => {
  let entered, signal, args;
  const started = new Promise(resolve => { entered = resolve; });
  const { window, repos, transports } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    respondQuestion: async (...values) => {
      args = values;
      signal = values.at(-1);
      entered();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
  });
  const pending = window.kurageRespondQuestion('workspace-a', 'chat', 'https://example.test', 'turn', 'request', { q: 'Answer' }, 'operation');
  await started;
  assert.equal(transports[0].metaStreamId, 'workspace-a:meta');
  assert.equal(transports[0].createStreamIfMissing, false);
  assert.deepEqual(args.slice(1, 5), ['chat', 'turn', 'request', { q: 'Answer' }]);
  window.kurageCancel('operation');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(signal.aborted, true);
  assert.equal(repos[0].destroyed, true);
});


test('new-folder skill mentions use the selected project on the template machine', async () => {
  let request;
  const rows = [{ docId: 'session-template', meta: {
    machineId: 'machine', agentType: 'codex', project: { kind: 'local', localProjectId: 'old' },
  } }];
  const { window } = makeBridge(undefined, rows, undefined, undefined, {
    mentionSkills: async args => { request = args; return []; },
  });
  await window.kurageMentionSkills('workspace', 'https://gateway.lody.ai',
    'template', null, 'user', 'request', 'local:machine:fresh');
  assert.equal(request.localProjectID, 'fresh');
  await assert.rejects(window.kurageMentionSkills('workspace', 'https://gateway.lody.ai',
    'template', null, 'user', 'request2', 'local:other:fresh'), /another machine/);
});

test('tab configuration forwards its mode and scope without a project override or writable streams', async () => {
  const { window, repos, transports } = makeBridge(async () => ({ ok: true, outcome: 'synced' }), [], undefined, undefined, {
    newSessionOptions: async (_repo, workspace, parent, agent, signal, project, tab) => {
      assert.equal(workspace, 'workspace-tab');
      assert.equal(parent, 'parent');
      assert.equal(agent, null);
      assert.equal(project, undefined);
      assert.equal(tab, true);
      assert.equal(signal.aborted, false);
      return { agentConfigID: 'codex', providers: [], runConfig: {} };
    },
  });
  const result = await window.kurageNewSessionOptions('workspace-tab', 'parent', null,
    'https://gateway.lody.ai', 'tab-config', null, true);
  assert.equal(JSON.parse(result).agentConfigID, 'codex');
  assert.equal(transports[0].createStreamIfMissing, false);
  assert.equal(repos[0].destroyed, true);
});

test('options reuse a confirmed live transcript while refreshing machine configuration independently', async () => {
  const syncs = [];
  const { window, repos } = makeBridge((options, repo) => {
    syncs.push({ repo, options });
    return { ok: true };
  }, [localSession], undefined, undefined, {
    syncedConversationVersion: () => 'confirmed',
    observeConversation: async ({ repo }) => {
      await repo.openPersistedDoc('session-local');
      await repo.sync({ scope: 'doc', docIds: ['session-local'] });
    },
    newSessionOptions: async repo => {
      await repo.openFlockDoc('workspace:mf:machine');
      await repo.sync({ scope: 'doc', flockDocIds: ['workspace:mf:machine'] });
      await repo.openPersistedDoc('session-local');
      await repo.sync({ scope: 'doc', docIds: ['session-local'] });
      return {};
    },
  });
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  await window.kurageObserveConversation('workspace', 'local', 'https://gateway.lody.ai', 'observe');
  const before = syncs.length;
  await window.kurageNewSessionOptions('workspace', 'local', null, 'https://gateway.lody.ai', 'options');
  assert.equal(repos.length, 2);
  assert.deepEqual(syncs.slice(before).map(read => Array.from(read.options.flockDocIds)), [['workspace:mf:machine']]);
  assert.equal(repos[1].destroyed, true);
  assert.equal(repos[0].loaded.has('session-local'), true);
  window.kurageStopConversation('observe');
  const stopped = syncs.length;
  await window.kurageNewSessionOptions('workspace', 'local', null, 'https://gateway.lody.ai', 'again');
  assert.equal(repos[0].loaded.size, 0);
  assert.deepEqual(syncs.slice(stopped).flatMap(read => Array.from(read.options.docIds)), ['session-local']);
});

function optionsBridge(sync, extras = {}) {
  const rows = [{ docId: 'session-template', meta: {
    machineId: 'machine', agentConfigId: 'codex', cliType: 'builtin', agentType: 'codex',
    lastMessageAt: 8, status: { type: 'idle' },
    project: { kind: 'local', localProjectId: 'project' },
  } }];
  const doc = new LoroDoc();
  doc.getList('history').push({ id: 'turn', role: 'user', inputConfig: { modelId: 'model' } });
  doc.commit();
  const entries = [
    { key: ['localProject', 'project'], value: { name: 'Project' } },
    { key: ['agentConfig', 'codex'], value: { name: 'Codex', cliType: 'builtin', agentType: 'codex' } },
    { key: ['acpCapability', 'codex'], value: { cliType: 'builtin', agentType: 'codex',
      models: [{ modelId: 'model' }] } },
  ];
  const bridge = makeBridge(sync, rows, undefined, undefined, {
    openPersistedDoc: () => ({ doc }),
    openFlockDoc: () => ({ flock: {
      scan: ({ prefix }) => entries.filter(row => prefix.every((part, index) => row.key[index] === part)),
      get: key => entries.find(row => JSON.stringify(row.key) === JSON.stringify(key))?.value,
    } }),
    ...extras,
  });
  return { ...bridge, entries };
}

test('new-session options reuse the list machine snapshot and compact defaults across page opens', async () => {
  const reads = [];
  const { window, repos } = optionsBridge(async options => { reads.push(options); return { ok: true, outcome: 'synced' }; });
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  reads.length = 0;
  const first = await window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'first');
  assert.deepEqual(reads.map(read => Array.from(read.docIds)), [['session-template']]);
  assert.equal(repos[1].destroyed, true);
  reads.length = 0;
  assert.equal(await window.kurageNewSessionOptions('workspace', 'template', null,
    'https://gateway.lody.ai', 'second'), first);
  assert.equal(reads.length, 0);
  assert.equal(repos.length, 2);
  assert.equal(repos[0].loaded.size, 0);
});

test('a cached unavailable project refreshes once before rejecting restored server state', async () => {
  const reads = [];
  const { window, entries } = optionsBridge(async options => {
    reads.push(options);
    return { ok: true, outcome: 'synced' };
  });
  const project = entries.shift();
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  entries.unshift(project);
  reads.length = 0;
  const options = JSON.parse(await window.kurageNewSessionOptions('workspace', 'template', null,
    'https://gateway.lody.ai', 'restored'));
  assert.equal(options.runConfig.model.value, 'model');
  assert.equal(reads.length, 2);
  reads.length = 0;
  await window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'again');
  assert.equal(reads.length, 0);
});

test('stale options return immediately and an explicit refresh has its own cancellable replica', async () => {
  let time = 0;
  let block = false;
  const started = Promise.withResolvers();
  const reads = [];
  const { window, repos } = optionsBridge(async options => {
    reads.push(options);
    if (block && options.flockDocIds?.length) {
      started.resolve();
      await new Promise((_resolve, reject) => options.signal.addEventListener('abort',
        () => reject(options.signal.reason), { once: true }));
    }
    return { ok: true, outcome: 'synced' };
  }, { now: () => time });
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  await window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'first');
  time = 30_000;
  reads.length = 0;
  const cached = JSON.parse(await window.kurageNewSessionOptions('workspace', 'template', null,
    'https://gateway.lody.ai', 'stale'));
  assert.equal(cached.needsRefresh, true);
  assert.equal(reads.length, 0);
  block = true;
  const refresh = window.kurageNewSessionOptions('workspace', 'template', null,
    'https://gateway.lody.ai', 'refresh', null, false, true);
  const rejected = assert.rejects(refresh, { name: 'AbortError' });
  await started.promise;
  window.kurageCancel('refresh');
  await rejected;
  assert.equal(repos[2].destroyed, true);
  assert.equal(repos[0].destroyed, false);
  reads.length = 0;
  assert.equal(JSON.parse(await window.kurageNewSessionOptions('workspace', 'template', null,
    'https://gateway.lody.ai', 'after-cancel')).runConfig.model.value, 'model');
  assert.equal(reads.length, 0);
});

test('new-session configuration never crosses a workspace or gateway replacement', async () => {
  const reads = [];
  const { window, repos } = optionsBridge(async options => { reads.push(options); return { ok: true, outcome: 'synced' }; });
  for (const [workspace, gateway] of [['workspace', 'https://gateway.lody.ai'],
    ['other', 'https://gateway.lody.ai'], ['other', 'https://other.lody.ai']]) {
    await window.kurageSessions(workspace, gateway, 'list');
    reads.length = 0;
    await window.kurageNewSessionOptions(workspace, 'template', null, gateway, 'options');
    assert.deepEqual(reads.map(read => Array.from(read.docIds)), [['session-template']]);
  }
  assert.equal(repos.filter(repo => !repo.destroyed).length, 1);
});

for (const result of ['sent', 'rejected']) {
  test(`a ${result} creation ${result === 'sent' ? 'preserves' : 'invalidates'} the display configuration cache`, async () => {
    const reads = [];
    const { window } = optionsBridge(async options => {
      reads.push(options);
      return { ok: true, outcome: 'synced' };
    }, { startSession: async () => result });
    await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
    await window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'first');
    assert.equal(await window.kurageStartSession('workspace', 'https://gateway.lody.ai', {}), result);
    reads.length = 0;
    await window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'again');
    assert.equal(reads.length, result === 'sent' ? 0 : 2);
  });
}

for (const state of ['stopped', 'advanced', 'changed-during-read']) {
  test(`options refresh the baseline when its live evidence is ${state}`, async () => {
    let remoteModel = 'old';
    let proof = 'old';
    let attempts = 0;
    const syncs = [];
    const { window, repos } = makeBridge((options, repo) => {
      syncs.push({ options, repo });
      if (options.docIds?.length) repo.model = remoteModel;
      return { ok: true };
    }, [localSession], undefined, undefined, {
      syncedConversationVersion: () => proof,
      observeConversation: async ({ repo }) => {
        await repo.openPersistedDoc('session-local');
        await repo.sync({ scope: 'doc', docIds: ['session-local'] });
      },
      newSessionOptions: async repo => {
        attempts++;
        const { doc } = await repo.openPersistedDoc('session-local');
        await repo.sync({ scope: 'doc', docIds: ['session-local'] });
        const model = doc.getMap('acpRuntimeConfig').toJSON().modelId;
        if (state === 'changed-during-read' && attempts === 1) {
          remoteModel = 'new';
          proof = 'new';
        }
        return { model };
      },
    });
    await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
    await window.kurageObserveConversation('workspace', 'local', 'https://gateway.lody.ai', 'observe');
    const before = syncs.length;
    if (state === 'stopped') { window.kurageStopConversation('observe'); remoteModel = 'new'; }
    if (state === 'advanced') { proof = undefined; remoteModel = 'new'; }
    const result = JSON.parse(await window.kurageNewSessionOptions('workspace', 'local', null, 'https://gateway.lody.ai', 'options'));
    assert.equal(result.model, 'new');
    assert.equal(attempts, state === 'changed-during-read' ? 2 : 1);
    assert.equal(syncs.slice(before).length, 1);
    assert.equal(syncs.at(-1).repo, repos[1]);
    assert.equal(repos[1].destroyed, true);
    window.kurageStopConversation('observe');
  });
}

test('project catalogs refresh on an isolated reader while browsing reuses cached metadata', async () => {
  const syncs = [];
  const { window, repos } = makeBridge((options, repo) => {
    syncs.push({ options, repo });
    return { ok: true };
  }, [localSession], undefined, undefined, {
    sessionProjects: async repo => { await repo.listDoc(); return {}; },
  });
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
  const before = syncs.length;
  await window.kurageSessionProjects('workspace', 'https://gateway.lody.ai', 'local', 'catalog', null, null, 'catalog');
  assert.equal(repos.length, 2);
  assert.equal(repos[1].destroyed, true);
  assert.deepEqual(syncs.slice(before).map(read => read.options.scope), ['meta']);
  await window.kurageSessionProjects('workspace', 'https://gateway.lody.ai', 'local', 'browse', null, null, 'browse');
  assert.equal(repos.length, 2);
  assert.equal(syncs.length, before + 1);
});

for (const action of ['browse', 'select']) {
  test(`project ${action} sends the scoped native token through Streams authentication`, async () => {
    const commands = [];
    const operationID = `project-${action}`;
    const token = `${operationID}-token`;
    let native;
    const { window } = makeBridge(async () => ({ ok: true, outcome: 'synced' }), [localSession], undefined, undefined, {
      createNativeFetch: (send, fallback) => native = createNativeFetch(send, fallback),
      postMessage: async command => {
        commands.push(command);
        if (command.command === 'auth') return { token };
        if (command.command === 'start') {
          await native.receive({ id: command.id, type: 'headers', status: 201,
            headers: { 'content-type': 'application/json', 'stream-next-offset': '0' } });
          await native.receive({ id: command.id, type: 'end' });
        }
      },
      sessionProjects: async (_repo, _workspace, _template, _action, _path, _cursor, access, signal) => {
        signal.throwIfAborted();
        const client = new StreamsClient({ url: `${access.baseURL}/ds/lody/response`,
          auth: access.auth, fetch: native.fetch });
        assert.equal((await client.create({ contentType: 'application/json' })).ok, true);
        return {};
      },
    });
    await window.kurageSessionProjects('workspace', 'https://gateway.lody.ai', 'local', action,
      '/projects', null, operationID);
    const auth = commands.find(command => command.command === 'auth');
    assert.equal(auth.workspaceID, 'workspace');
    assert.equal(auth.operationID, operationID);
    const request = commands.find(command => command.command === 'start');
    assert.equal(request.headers.authorization, `Bearer ${token}`);
  });
}

for (const outcome of ['success', 'failure', 'cancel']) {
  test(`a cold baseline stays out of the shared cache on ${outcome}`, async () => {
    const started = Promise.withResolvers();
    const syncs = [];
    const { window, repos } = makeBridge(async (options, repo) => {
      syncs.push({ repo, options });
      if (options.docIds?.length) {
        if (outcome === 'failure') throw new Error('offline');
        if (outcome === 'cancel') {
          started.resolve();
          await new Promise((_resolve, reject) => options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true }));
        }
      }
      return { ok: true };
    }, [localSession], undefined, undefined, {
      newSessionOptions: async repo => {
        await repo.openFlockDoc('workspace:mf:machine');
        await repo.sync({ scope: 'doc', flockDocIds: ['workspace:mf:machine'] });
        await repo.openPersistedDoc('session-baseline');
        await repo.sync({ scope: 'doc', docIds: ['session-baseline'] });
        return {};
      },
    });
    await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
    const before = syncs.length;
    const pending = window.kurageNewSessionOptions('workspace', 'local', null, 'https://gateway.lody.ai', 'options');
    const result = outcome === 'success' ? pending : assert.rejects(pending,
      outcome === 'cancel' ? { name: 'AbortError' } : /offline/);
    if (outcome === 'cancel') { await started.promise; window.kurageCancel('options'); }
    await result;
    assert.equal(repos[0].destroyed, false);
    assert.equal(repos[0].loaded.size, 0);
    assert.equal(repos[1].destroyed, true);
    const reads = syncs.slice(before);
    assert.deepEqual(reads.map(read => Array.from(read.options.docIds)), [[], ['session-baseline']]);
    assert.ok(reads.every(read => read.repo === repos[1]));
  });
}

for (const operation of ['options', 'conversation']) for (const cancel of [false, true]) {
  test(`${operation} ${cancel ? 'cancellation' : 'completion'} leaves a concurrent live SSE reader intact`, async () => {
    const entered = Promise.withResolvers();
    const finish = Promise.withResolvers();
    const commands = [];
    let native;
    const read = async signal => {
      const token = await transports[1].auth({ reason: 'unauthorized' });
      await native.fetch('https://gateway.lody.ai/one-shot', { headers: { authorization: `Bearer ${token}` } });
      entered.resolve();
      await finish.promise;
      signal.throwIfAborted();
      return { ok: true };
    };
    const { window, repos, transports } = makeBridge(async options => {
      if (operation === 'conversation' && options.scope === 'doc') return read(options.signal);
      return { ok: true };
    }, [{ docId: 'session-chat', meta: {} }], undefined, undefined, {
      createNativeFetch: (send, fallback) => native = createNativeFetch(send, fallback),
      postMessage: async command => {
        commands.push(command);
        if (command.command === 'auth') return { token: command.operationID ? 'read-token' : 'live-token' };
        if (command.command === 'start') {
          await native.receive({ id: command.id, type: 'headers', status: 200,
            headers: { 'content-type': 'text/event-stream' } });
        }
      },
      newSessionOptions: async (repo, _workspace, _template, _agent, signal) => {
        await repo.openPersistedDoc('session-baseline');
        // Exercise native work whose lifetime belongs to the one-shot reader.
        await read(signal);
        return {};
      },
    });
    await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'list');
    const pending = operation === 'options'
      ? window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'read')
      : window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read');
    const result = cancel ? assert.rejects(pending, { name: 'AbortError' }) : pending;
    await entered.promise;
    const owner = new AbortController();
    const client = new StreamsClient({ url: 'https://gateway.lody.ai/live', auth: transports[0].auth, fetch: native.fetch });
    const opened = await client.openSseSession({ offset: 'now', signal: owner.signal });
    assert.equal(opened.ok, true);
    const events = opened.result.events[Symbol.asyncIterator]();
    const event = events.next();
    if (cancel) window.kurageCancel('read');
    finish.resolve();
    await result;
    const live = commands.find(command => command.command === 'start' && command.url.startsWith('https://gateway.lody.ai/live'));
    const oneShot = commands.find(command => command.command === 'start' && command.url === 'https://gateway.lody.ai/one-shot');
    assert.equal(commands.some(command => command.command === 'cancel' && command.id === live.id), false);
    assert.equal(commands.some(command => command.command === 'cancel' && command.id === oneShot.id), true);
    assert.equal(commands.find(command => command.command === 'auth' && !command.operationID).operationID, undefined);
    assert.equal(commands.find(command => command.command === 'auth' && command.operationID).operationID, 'read');
    assert.equal(commands.find(command => command.command === 'auth' && command.operationID).refresh, true);
    await native.receive({ id: live.id, type: 'chunk', body: Buffer.from('event: control\ndata: {"streamNextOffset":"1","upToDate":true}\n\n').toString('base64') });
    assert.equal((await event).done, false);
    assert.equal(repos[0].destroyed, false);
    assert.equal(repos[1].destroyed, true);
    owner.abort();
    await events.return();
  });
}

test('cancelling while scoped auth is pending prevents native requests from starting', async () => {
  const auth = Promise.withResolvers();
  const entered = Promise.withResolvers();
  let requests = 0;
  const { window, repos } = makeBridge(async (_options, repo) => {
    await repo.transport.auth();
    requests++;
    return { ok: true };
  }, [], undefined, undefined, {
    createNativeFetch,
    postMessage: async () => { entered.resolve(); return auth.promise; },
  });
  const pending = window.kurageNewSessionOptions('workspace', 'template', null, 'https://gateway.lody.ai', 'options');
  const result = assert.rejects(pending, { name: 'AbortError' });
  await entered.promise;
  window.kurageCancel('options');
  auth.resolve({ token: 'scoped-token' });
  await result;
  assert.equal(requests, 0);
  assert.equal(repos[0].destroyed, true);
});

test('session list refresh rolls up tab activity while preserving the main activity', async () => {
  const rows = [
    { docId: 'session-root', meta: { status: { type: 'idle' } } },
    { docId: 'session-child', meta: { parentSessionId: 'root', status: { type: 'running' } } },
    { docId: 'session-other', meta: { status: { type: 'idle' } } },
  ];
  const { window } = makeBridge(undefined, rows);
  const first = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai'));
  assert.equal(first.sessions.length, 2);
  assert.equal(first.sessions.find(session => session.id === 'root').activity, 'idle');
  assert.equal(first.sessions.find(session => session.id === 'root').hasRunningTabs, true);
  assert.equal(first.sessions.find(session => session.id === 'other').hasRunningTabs, false);
  rows[1].meta.status = { type: 'idle' };
  const next = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai'));
  assert.equal(next.sessions.find(session => session.id === 'root').hasRunningTabs, false);
});

test('native send routes steer RPC with workspace auth and retains its target across replicas', async () => {
  const states = [];
  const requests = [];
  const auth = [];
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    postMessage: async command => { auth.push(command); return { token: 'test-token' }; },
    requestMachine: async (access, workspaceID, machineID, method, params, signal) => {
      assert.equal(await access.auth({ reason: 'unauthorized' }), 'test-token');
      requests.push({ workspaceID, machineID, method, params, signal });
      return { applied: true };
    },
    sendText: async (_repo, sessionID, turnID, userID, text, timestamp, config, attachments, steering) => {
      assert.equal(sessionID, 'chat');
      assert.equal(turnID, 'guide');
      assert.equal(text, 'Guidance');
      assert.equal(attachments.length, 1);
      states.push(steering.state);
      steering.state.expectedTurnID ??= 'original-assistant';
      await steering.request('machine', { sessionId: sessionID, userTurnId: turnID,
        expectedTurnId: steering.state.expectedTurnID });
      return states.length === 1 ? 'unconfirmed' : 'sent';
    },
  });
  const send = (workspaceID, operationID) => window.kurageSendText(workspaceID, 'chat',
    'https://gateway.example', 'guide', 'user', 'Guidance', 'timestamp', null, [{ type: 'image' }], operationID);
  assert.equal(await send('workspace', 'first'), 'unconfirmed');
  assert.equal(await send('workspace', 'retry'), 'sent');
  assert.equal(await send('other-workspace', 'other'), 'sent');
  assert.equal(states[0], states[1]);
  assert.notEqual(states[0], states[2]);
  assert.deepEqual(requests.map(request => request.workspaceID), ['workspace', 'workspace', 'other-workspace']);
  assert(requests.every(request => request.method === 'session/steer' && request.signal.aborted));
  assert.deepEqual(auth.map(command => [command.workspaceID, command.operationID, command.refresh]), [
    ['workspace', 'first', true], ['workspace', 'retry', true], ['other-workspace', 'other', true],
  ]);
  assert(repos.every(repo => repo.destroyed));
});

for (const result of ['sent', 'superseded', 'rejected']) {
  test(`native send releases a steer retry target after ${result}`, async () => {
    const states = [];
    const { window } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
      sendText: async (_repo, _sessionID, _turnID, _userID, _text, _timestamp, _config, _attachments, steering) => {
        states.push(steering.state);
        steering.state.expectedTurnID = 'assistant';
        return result;
      },
    });
    const send = () => window.kurageSendText('workspace', 'chat', 'https://gateway.example',
      'guide', 'user', 'Guidance', 'timestamp', null, []);
    await send();
    await send();
    assert.notEqual(states[0], states[1]);
  });
}

test('native send retains an ambiguous steer target when the writer throws', async () => {
  const states = [];
  const { window } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    sendText: async (_repo, _sessionID, _turnID, _userID, _text, _timestamp, _config, _attachments, steering) => {
      states.push(steering.state);
      steering.state.expectedTurnID ??= 'original-assistant';
      if (states.length === 1) throw new Error('sync interrupted');
      return 'sent';
    },
  });
  const send = () => window.kurageSendText('workspace', 'chat', 'https://gateway.example',
    'guide', 'user', 'Guidance', 'timestamp', null, []);
  await assert.rejects(send(), /sync interrupted/);
  assert.equal(await send(), 'sent');
  assert.equal(states[0], states[1]);
  assert.equal(states[1].expectedTurnID, 'original-assistant');
});

test('native completion retires only its exact workspace, session and turn retry state', async () => {
  const states = [];
  const { window } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    sendText: async (_repo, _sessionID, _turnID, _userID, _text, _timestamp, _config, _attachments, steering) => {
      states.push(steering.state);
      steering.state.expectedTurnID = 'assistant';
      steering.state.authoredUpdate = new Uint8Array([1, 2, 3]);
      return 'unconfirmed';
    },
  });
  const keys = [['workspace', 'chat', 'guide'], ['other-workspace', 'chat', 'guide'],
    ['workspace', 'other-chat', 'guide'], ['workspace', 'chat', 'other-turn']];
  const send = ([workspace, session, turn]) => window.kurageSendText(workspace, session,
    'https://gateway.example', turn, 'user', 'Guidance', 'timestamp', null, []);
  const originals = [];
  for (const key of keys) {
    await send(key);
    originals.push(states.at(-1));
  }
  window.kurageFinishTextSend(...keys[0]);
  for (const [index, key] of keys.entries()) {
    await send(key);
    const current = states.at(-1);
    if (index === 0) assert.notEqual(current, originals[index]);
    else assert.equal(current, originals[index]);
  }
});

test('native completion keeps an active upload alive and its late completion cannot retire a newer retry state', async () => {
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  let finish;
  const uploaded = new Promise(resolve => { finish = resolve; });
  const states = [];
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    sendText: async (_repo, _sessionID, _turnID, _userID, _text, _timestamp, _config, _attachments, steering) => {
      states.push(steering.state);
      steering.state.expectedTurnID = 'assistant';
      if (states.length === 1) {
        started();
        await uploaded;
        assert.equal(steering.signal.aborted, false);
        return 'sent';
      }
      return 'unconfirmed';
    },
  });
  const send = () => window.kurageSendText('workspace', 'chat', 'https://gateway.example',
    'guide', 'user', 'Guidance', 'timestamp', null, []);
  const active = send();
  await ready;
  window.kurageFinishTextSend('workspace', 'chat', 'guide');
  assert.equal(repos[0].destroyed, false);
  assert.equal(await send(), 'unconfirmed');
  assert.notEqual(states[0], states[1]);
  finish();
  assert.equal(await active, 'sent');
  assert.equal(await send(), 'unconfirmed');
  assert.equal(states[1], states[2]);
  assert(repos.every(repo => repo.destroyed));
});
