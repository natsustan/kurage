import test from 'node:test';
import assert from 'node:assert/strict';
import { sessionProjects } from './session-projects.mjs';

const fixture = () => {
  const rows = [
    { docId: 'session-template', meta: { machineId: 'mac', project: { kind: 'local', localProjectId: 'a' } } },
    { docId: 'session-b', meta: { machineId: 'mac', project: { kind: 'local', localProjectId: 'b' }, lastMessageAt: 5 } },
    { docId: 'session-child', meta: { machineId: 'mac', parentSessionId: 'b', project: { kind: 'local', localProjectId: 'b' }, lastMessageAt: 10 } },
  ];
  const entries = new Map(['a', 'b', 'fresh', 'deleting'].map(id => [id, { id, name: id, rootPath: `/${id}` }]));
  const repo = {
    listDoc: async () => rows,
    openFlockDoc: async () => ({ flock: { scan: ({ prefix }) => prefix[0] === 'localProject'
      ? [...entries].map(([id, value]) => ({ key: ['localProject', id], value }))
      : [{ key: ['cmd', 'deleteLocalProject', 'deleting'] }],
      get: key => entries.get(key[1]), put: (key, value) => entries.set(key[1], value), txn: work => work(),
    } }),
    sync: async () => ({ ok: true }), getDocMeta: async () => undefined,
  };
  return { repo, rows, entries };
};
const call = (repo, action, rpc, path, cursor, signal = new AbortController().signal) =>
  sessionProjects(repo, 'ws', 'template', action, path, cursor, {}, signal, rpc);

test('catalog includes unused projects, removes deleting projects and chooses recent roots', async () => {
  const { repo } = fixture();
  const { projects } = await call(repo, 'catalog');
  assert.deepEqual(projects.map(p => p.id), ['local:mac:a', 'local:mac:b', 'local:mac:fresh']);
  assert.equal(projects[1].templateSessionID, 'b');
  assert.equal(projects[2].templateSessionID, 'template');
});

test('folder browsing carries machine/workspace, path and pagination through RPC', async () => {
  const { repo } = fixture();
  const directory = { path: '/projects', parentPath: '/', entries: [], truncated: true, nextCursor: 'next' };
  const result = await call(repo, 'browse', async (access, workspace, machine, request) => {
    assert.equal(workspace, 'ws'); assert.equal(machine, 'mac');
    assert.deepEqual(request, { type: 'local-project/browse-dir', machineId: 'mac', workspaceId: 'ws', absolutePath: '/projects', cursor: 'page2', limit: 100 });
    return { ok: true, type: request.type, result: directory };
  }, '/projects', 'page2');
  assert.deepEqual(result.directory, directory);
});

test('folder selection registers only in the requested workspace and returns the canonical path', async () => {
  const { repo, entries } = fixture();
  entries.delete('fresh');
  const result = await call(repo, 'select', async (access, workspace, machine, request) => {
    assert.deepEqual(request, { type: 'local-project/prepare-add', machineId: 'mac', workspaceId: 'ws', rootPath: '/link' });
    return { ok: true, type: request.type, result: { localProjectId: 'fresh', name: 'Fresh', rootPath: '/real', alreadyRegistered: false } };
  }, '/link');
  assert.equal(result.project.id, 'local:mac:fresh');
  assert.equal(result.project.rootPath, '/real');
});

test('denied, malformed and cancelled directory requests never publish a selection', async () => {
  const { repo } = fixture();
  await assert.rejects(call(repo, 'browse', async () => ({ ok: false, message: 'Forbidden' })));
  await assert.rejects(call(repo, 'select', async () => ({ ok: true, type: 'local-project/add', result: { workspaceIds: ['other'] } }), '/x'));
  const controller = new AbortController();
  await assert.rejects(call(repo, 'browse', async () => { controller.abort(); return { ok: true }; }, null, null, controller.signal));
});

test('directory registration preserves an existing custom name and rejects a pending deletion', async () => {
  const { repo, entries } = fixture();
  entries.set('fresh', { id: 'fresh', name: 'Custom name', rootPath: '/real', createdAtMs: 1 });
  const rpc = async () => ({ ok: true, type: 'local-project/prepare-add',
    result: { localProjectId: 'fresh', name: 'basename', rootPath: '/real', alreadyRegistered: false } });
  assert.equal((await call(repo, 'select', rpc, '/real')).project.name, 'Custom name');
  assert.equal(entries.get('fresh').createdAtMs, 1);
  await assert.rejects(call(repo, 'select', async () => ({ ok: true, type: 'local-project/prepare-add',
    result: { localProjectId: 'deleting', name: 'Deleted', rootPath: '/deleted', alreadyRegistered: true } }), '/deleted'), /being deleted/);
});

test('unconfirmed registration can be retried without replacing an existing row', async () => {
  const { repo, entries } = fixture();
  entries.delete('fresh');
  let count = 0;
  repo.sync = async () => ({ ok: ++count !== 2 });
  const rpc = async () => ({ ok: true, type: 'local-project/prepare-add',
    result: { localProjectId: 'fresh', name: 'Fresh', rootPath: '/real', alreadyRegistered: false } });
  await assert.rejects(call(repo, 'select', rpc, '/real'), /unconfirmed/);
  const before = entries.get('fresh');
  assert.equal((await call(repo, 'select', rpc, '/real')).project.id, 'local:mac:fresh');
  assert.equal(entries.get('fresh'), before);
});
