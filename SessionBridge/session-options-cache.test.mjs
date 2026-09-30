import assert from 'node:assert/strict';
import test from 'node:test';
import { createSessionOptionsCache } from './session-options-cache.mjs';

const metadata = (lastMessageAt = 1) => ({ meta: { lastMessageAt, status: { type: 'idle' },
  machineId: 'mac', agentConfigId: 'agent', latestUserMsgId: 'turn', lastHandledUserMsgId: 'turn' } });
const flock = rows => ({ scan: ({ prefix }) => rows.filter(row => prefix.every((part, index) => row.key[index] === part)) });

test('machine snapshots copy only option and project rows and preserve deletion commands', () => {
  const cache = createSessionOptionsCache();
  const project = { name: 'Project' };
  cache.rememberMachine('ws:mf:mac', flock([
    { key: ['localProject', 'project'], value: project },
    { key: ['cmd', 'deleteLocalProject', 'project'], value: {} },
    { key: ['unrelated'], value: 'unused' },
  ]));
  project.name = 'Mutated';
  const snapshot = cache.reader().machine('ws:mf:mac');
  assert.equal(snapshot.get(['localProject', 'project']).name, 'Project');
  assert.equal(snapshot.scan({ prefix: ['cmd', 'deleteLocalProject'] }).length, 1);
  assert.equal(snapshot.get(['unrelated']), undefined);
});

test('baseline markers reject pending dispatches and changes during a read', () => {
  const cache = createSessionOptionsCache();
  const reader = cache.reader();
  reader.rememberBaseline('session', metadata(), metadata(2), { modelId: 'old' });
  assert.equal(reader.baseline('session', metadata()), undefined);
  reader.rememberBaseline('session', metadata(), metadata(), { modelId: 'old' });
  const pending = metadata();
  pending.meta.latestUserMsgId = 'new';
  assert.equal(reader.baseline('session', pending), undefined);
  const returned = reader.baseline('session', metadata());
  returned.modelId = 'mutated';
  assert.equal(reader.baseline('session', metadata()).modelId, 'old');
});

test('bounded configuration caches evict old entries and clear all workspace data', () => {
  const cache = createSessionOptionsCache();
  const reader = cache.reader();
  for (let index = 0; index < 80; index++) {
    cache.rememberMachine(`machine-${index}`, flock([]));
    reader.rememberBaseline(`session-${index}`, metadata(), metadata(), { modelId: `${index}` });
  }
  assert.equal(reader.machine('machine-0'), undefined);
  assert.equal(reader.baseline('session-0', metadata()), undefined);
  assert.ok(reader.machine('machine-79'));
  assert.equal(reader.baseline('session-79', metadata()).modelId, '79');
  cache.clear();
  assert.equal(reader.machine('machine-79'), undefined);
  assert.equal(reader.baseline('session-79', metadata()), undefined);
});
