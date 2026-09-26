import assert from 'node:assert/strict';
import test from 'node:test';
import { LoroDoc } from 'loro-crdt';
import { applyNewSessionChoices, projectNewSessionRunConfig } from './run-config.mjs';
import { newSessionOptions, startSession } from './session-start.mjs';

const capability = {
  cliType: 'builtin', agentType: 'codex', models: [],
  configOptions: [
    { id: 'model', name: 'Model', category: 'model', type: 'select', currentValue: 'gpt-5.5',
      options: [{ value: 'gpt-5.5', name: 'gpt-5.5' }, { value: 'gpt-5.4-mini', name: 'gpt-5.4-mini' }] },
    { id: 'reasoning_effort', name: 'Reasoning', type: 'select', currentValue: 'medium',
      options: [{ value: 'low', name: 'Low' }, { value: 'medium', name: 'Medium' }, { value: 'high', name: 'High' }] },
  ],
  modelReasoningEfforts: { 'gpt-5.4-mini': ['low'] },
};

function fixture() {
  const rows = new Map([
    ['session-template', {
      userId: 'user', machineId: 'mac', cliType: 'builtin', agentType: 'codex', agentConfigId: 'cfg',
      status: { type: 'idle' }, acpSessionId: 'acp-1', lastHandledUserMsgId: 'old',
      project: { kind: 'local', localProjectId: 'proj', useWorktree: true, branch: 'feature' },
    }],
    ['session-claude-elsewhere', {
      userId: 'user', machineId: 'mac', cliType: 'builtin', agentType: 'claude', agentConfigId: 'claude',
      status: { type: 'idle' }, lastMessageAt: 5,
      project: { kind: 'local', localProjectId: 'other' },
    }],
    ['machine-mac', { name: 'spike@mac' }],
  ]);
  const docs = new Map();
  const history = (id, inputConfig) => {
    const doc = new LoroDoc();
    doc.getList('history').push({ id, role: 'user', items: [], inputConfig });
    doc.commit();
    return doc;
  };
  docs.set('session-template', history('old', {
    modeId: 'bypass', modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high' },
    agentRoleId: 'role',
  }));
  docs.set('session-claude-elsewhere', history('c1', { modeId: 'acceptEdits', modelId: 'opus' }));
  const flock = new Map([
    ['acpCapability/cfg', capability],
    ['agentConfig/cfg', { name: 'Codex', machineId: 'mac', cliType: 'builtin', agentType: 'codex' }],
    ['acpCapability/claude', { cliType: 'builtin', agentType: 'claude', models: [], configOptions: [
      { id: 'model', category: 'model', type: 'select', currentValue: 'sonnet',
        options: [{ value: 'sonnet', name: 'Sonnet' }, { value: 'opus', name: 'Opus' }] },
    ] }],
    ['agentConfig/claude', { name: 'Claude Code', machineId: 'mac', cliType: 'builtin', agentType: 'claude' }],
    ['agentConfig/foreign', { name: 'Other machine', machineId: 'pc', cliType: 'builtin', agentType: 'codex' }],
  ]);
  const calls = [];
  const repo = {
    listDoc: async () => [...rows].map(([docId, meta]) => ({ docId, meta })),
    getDocMeta: async id => rows.has(id) ? { meta: rows.get(id) } : undefined,
    openPersistedDoc: async id => {
      if (!docs.has(id)) docs.set(id, new LoroDoc());
      return { doc: docs.get(id) };
    },
    openFlockDoc: async () => ({ flock: {
      get: key => flock.get(key.join('/')),
      scan: ({ prefix }) => [...flock]
        .filter(([key]) => key.startsWith(`${prefix.join('/')}/`))
        .map(([key, value]) => ({ key: key.split('/'), value })),
    } }),
    sync: async options => { calls.push(options); return { ok: true, outcome: 'synced' }; },
    upsertDocMeta: async (id, patch) => { rows.set(id, { ...rows.get(id), ...patch }); },
  };
  return { repo, rows, docs, calls };
}

const start = (repo, overrides = {}) => startSession(repo, 'ws', {
  templateSessionID: 'template', sessionID: 'new', turnID: 'turn-1', userID: 'user',
  text: 'Build the thing', timestamp: '2026-09-25T00:00:00.000Z', selections: [], ...overrides,
});

test('a new session offers both the model and its reasoning from the template baseline', async () => {
  const { repo } = fixture();
  const options = await newSessionOptions(repo, 'ws', 'template');
  assert.equal(options.machineName, 'spike@mac');
  assert.equal(options.agentConfigID, 'cfg');
  assert.deepEqual(options.providers, [
    { value: 'claude', label: 'Claude Code' }, { value: 'cfg', label: 'Codex' },
  ]);
  assert.equal(options.runConfig.model.value, 'gpt-5.5');
  assert.equal(options.runConfig.model.configOptionID, null);
  assert.deepEqual(options.runConfig.model.options.map(option => option.reasoning.map(r => r.value)),
    [['low', 'medium', 'high'], ['low']]);
  assert.equal(options.runConfig.reasoning.value, 'high');
});

test('the first turn is durable before metadata publishes and dispatches it', async () => {
  const { repo, rows, docs, calls } = fixture();
  assert.equal(await start(repo, { selections: [
    { configOptionID: null, value: 'gpt-5.4-mini' },
    { configOptionID: 'reasoning_effort', value: 'low' },
  ] }), 'sent');
  const turn = docs.get('session-new').getList('history').toJSON()[0];
  assert.equal(turn.id, 'turn-1');
  assert.equal(turn.items[0].text, 'Build the thing');
  assert.equal(turn.inputConfig.resume, undefined);
  assert.equal(turn.inputConfig.agentRoleId, undefined);
  assert.equal(turn.inputConfig.modeId, 'bypass');
  assert.equal(turn.inputConfig.modelId, 'gpt-5.4-mini');
  assert.deepEqual(turn.inputConfig.configOptionValues, { reasoning_effort: 'low' });

  const meta = rows.get('session-new');
  assert.equal(meta.latestUserMsgId, 'turn-1');
  assert.equal(meta.machineId, 'mac');
  assert.equal(meta.agentConfigId, 'cfg');
  assert.deepEqual(meta.project, { kind: 'local', localProjectId: 'proj' });
  assert.equal(meta.isWorktree, undefined);
  assert.equal(meta.acpSessionId, undefined);
  assert.equal(meta.title, 'Build the thing');
  assert.deepEqual(meta.status, { type: 'idle' });
  const newDocSyncs = calls.filter(call => call.docIds?.includes('session-new')).length;
  assert.equal(newDocSyncs, 2);
  assert.equal(calls.at(-1).scope, 'meta');
});

test('a retry after an unconfirmed metadata write keeps one session and one turn', async () => {
  const { repo, rows, docs } = fixture();
  let failMeta = true;
  const sync = repo.sync;
  repo.sync = async options => options.scope === 'meta' && failMeta
    ? { ok: false, outcome: 'failed' } : sync(options);
  assert.equal(await start(repo), 'unconfirmed');
  failMeta = false;
  assert.equal(await start(repo), 'sent');
  assert.equal(await start(repo), 'sent');
  assert.equal(docs.get('session-new').getList('history').length, 1);
  assert.equal(rows.get('session-new').latestUserMsgId, 'turn-1');
  await assert.rejects(start(repo, { text: 'Other text' }), /another turn/);
});

test('an unsynced first turn never publishes the session', async () => {
  const { repo, rows } = fixture();
  let count = 0;
  const sync = repo.sync;
  repo.sync = async options => options.docIds?.includes('session-new') && ++count === 2
    ? { ok: false, outcome: 'failed' } : sync(options);
  assert.equal(await start(repo), 'unconfirmed');
  assert.equal(rows.has('session-new'), false);
});

test('only offered choices and local root templates can start a session', async () => {
  const { repo, rows } = fixture();
  assert.equal(await start(repo, { selections: [
    { configOptionID: null, value: 'gpt-5.4-mini' },
    { configOptionID: 'reasoning_effort', value: 'high' },
  ] }), 'rejected');
  rows.get('session-template').isArchived = true;
  assert.equal(await start(repo), 'rejected');
  rows.get('session-template').isArchived = false;
  rows.get('session-template').project = { kind: 'github', repoFullName: 'a/b', branch: 'main' };
  assert.equal(await start(repo), 'rejected');
  assert.equal(rows.has('session-new'), false);
});

test('another provider on the machine starts from its own most recent session', async () => {
  const { repo, rows, docs } = fixture();
  const options = await newSessionOptions(repo, 'ws', 'template', 'claude');
  assert.equal(options.agentConfigID, 'claude');
  assert.equal(options.runConfig.model.value, 'opus');
  assert.equal(options.runConfig.reasoning, null);

  assert.equal(await start(repo, { agentConfigID: 'claude', selections: [
    { configOptionID: null, value: 'sonnet' },
  ] }), 'sent');
  const meta = rows.get('session-new');
  assert.equal(meta.agentConfigId, 'claude');
  assert.equal(meta.agentType, 'claude');
  assert.deepEqual(meta.project, { kind: 'local', localProjectId: 'proj' });
  const turn = docs.get('session-new').getList('history').toJSON()[0];
  assert.equal(turn.inputConfig.agentType, 'claude');
  assert.equal(turn.inputConfig.modeId, 'acceptEdits');
  assert.equal(turn.inputConfig.modelId, 'sonnet');
  assert.equal(turn.inputConfig.configOptionValues, undefined);

  await assert.rejects(newSessionOptions(repo, 'ws', 'template', 'foreign'), /Provider is unavailable/);
});

test('a registry agent without reasoning edits the model through its config option', () => {
  const projection = projectNewSessionRunConfig({
    cliType: 'registry', agentType: 'gemini',
    capability: { cliType: 'registry', agentType: 'gemini', models: [], configOptions: [
      { id: 'model', category: 'model', type: 'select', currentValue: 'pro',
        options: [{ value: 'pro', name: 'Pro' }, { value: 'flash', name: 'Flash' }] },
    ] },
    baseline: { configOptionValues: { model: 'flash' } },
  });
  assert.equal(projection.model.value, 'flash');
  assert.equal(projection.model.configOptionID, 'model');
  assert.equal(projection.reasoning, null);
  assert.deepEqual(
    applyNewSessionChoices({}, projection, [{ configOptionID: 'model', value: 'pro' }]),
    { configOptionValues: { model: 'pro' } },
  );
  assert.equal(projectNewSessionRunConfig({ cliType: 'registry', agentType: 'gemini' }), null);
});


test('a model-only change removes unsupported inherited reasoning and preserves other options', async () => {
  const { repo, docs } = fixture();
  assert.equal(await start(repo, { selections: [{ configOptionID: null, value: 'gpt-5.4-mini' }] }), 'sent');
  const config = docs.get('session-new').getList('history').toJSON()[0].inputConfig;
  assert.equal(config.modelId, 'gpt-5.4-mini');
  assert.equal(config.configOptionValues.reasoning_effort, undefined);
  const projection = projectNewSessionRunConfig({ cliType: 'builtin', agentType: 'codex', capability,
    baseline: { modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high', other: 'keep' } } });
  const baseline = { configOptionValues: { reasoning_effort: 'high', other: 'keep' } };
  const changed = applyNewSessionChoices(baseline, projection, [{ configOptionID: null, value: 'gpt-5.4-mini' }]);
  assert.deepEqual(changed.configOptionValues, { other: 'keep' });
  assert.equal(baseline.configOptionValues.reasoning_effort, 'high');
  assert.equal(applyNewSessionChoices(baseline, projection, []).configOptionValues.reasoning_effort, 'high');
});

test('a rejected configuration has no authored turn and accepts corrected selections', async () => {
  const { repo, rows, docs } = fixture();
  assert.equal(await start(repo, { selections: [{ configOptionID: null, value: 'removed-model' }] }), 'rejected');
  assert.equal(rows.has('session-new'), false);
  assert.equal(docs.get('session-new').getList('history').length, 0);
  assert.equal(await start(repo, { selections: [{ configOptionID: null, value: 'gpt-5.5' }] }), 'sent');
  assert.equal(docs.get('session-new').getList('history').length, 1);
});

test('an authored first turn cannot be released as a rejected configuration on retry', async () => {
  const { repo, rows } = fixture();
  const sync = repo.sync;
  let newDocSyncs = 0;
  repo.sync = async options => options.docIds?.includes('session-new') && ++newDocSyncs === 2
    ? { outcome: 'failed', ok: false } : sync(options);
  assert.equal(await start(repo), 'unconfirmed');
  rows.get('session-template').isArchived = true;
  await assert.rejects(start(repo), /unavailable/);
  assert.equal(rows.has('session-new'), false);
});

for (const stage of ['machine', 'history']) {
  test(`option cancellation reaches the ${stage} sync without falling back`, async () => {
    const { repo } = fixture();
    const controller = new AbortController();
    const sync = repo.sync;
    let entered;
    const ready = new Promise(resolve => { entered = resolve; });
    repo.sync = async options => {
      const target = stage === 'machine' ? options.flockDocIds : options.docIds;
      if (!target) return sync(options);
      assert.equal(options.signal, controller.signal);
      entered();
      await new Promise((resolve, reject) => {
        options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
      });
    };
    const pending = newSessionOptions(repo, 'ws', 'template', undefined, controller.signal);
    await ready;
    controller.abort();
    await assert.rejects(pending, { name: 'AbortError' });
  });
}
