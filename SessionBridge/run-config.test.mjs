import assert from 'node:assert/strict';
import test from 'node:test';
import { applyRunConfigChoice, latestUserTurn, projectRunConfig } from './run-config.mjs';

const codexCapability = {
  cliType: 'builtin', agentType: 'codex',
  models: [],
  configOptions: [
    { id: 'model', name: 'Model', category: 'model', type: 'select', currentValue: 'gpt-5.5',
      options: [{ value: 'gpt-5.5', name: 'gpt-5.5 (recommended)' }, { value: 'gpt-5.4-mini', name: 'gpt-5.4-mini' }] },
    { id: 'reasoning_effort', name: 'Reasoning', type: 'select', currentValue: 'medium',
      options: [{ value: 'low', name: 'Low' }, { value: 'medium', name: 'Medium' }, { value: 'high', name: 'High' }] },
  ],
  modelReasoningEfforts: { 'gpt-5.4-mini': ['low', 'medium'] },
};

test('an agent with a reasoning option exposes only reasoning for the current model', () => {
  const turn = { id: 'u1', role: 'user',
    inputConfig: { modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high' } } };
  const projected = projectRunConfig({ cliType: 'builtin', agentType: 'codex',
    capability: codexCapability, turn, runtimeConfig: {} });
  assert.deepEqual(projected.model, { value: 'gpt-5.5', label: 'gpt-5.5' });
  assert.deepEqual(projected.reasoning, { value: 'high', label: 'High' });
  assert.equal(projected.editable.kind, 'reasoning');
  assert.equal(projected.editable.configOptionID, 'reasoning_effort');
  assert.deepEqual(projected.editable.options.map(option => option.value), ['low', 'medium', 'high']);

  const mini = projectRunConfig({ cliType: 'builtin', agentType: 'codex', capability: codexCapability,
    turn: { id: 'u1', inputConfig: { modelId: 'gpt-5.4-mini' } }, runtimeConfig: {} });
  assert.deepEqual(mini.editable.options.map(option => option.value), ['low', 'medium']);
  assert.equal(mini.reasoning.value, 'medium');
});

test('runtime config overrides only the turn it answered', () => {
  const turn = { id: 'u2', inputConfig: { modelId: 'gpt-5.5' } };
  const runtime = { basedOnUserTurnId: 'u2', configOptionValues: { reasoning_effort: 'low' } };
  const current = projectRunConfig({ cliType: 'builtin', agentType: 'codex',
    capability: codexCapability, turn, runtimeConfig: runtime });
  assert.equal(current.reasoning.value, 'low');
  const stale = projectRunConfig({ cliType: 'builtin', agentType: 'codex',
    capability: codexCapability, turn, runtimeConfig: { ...runtime, basedOnUserTurnId: 'u1' } });
  assert.equal(stale.reasoning.value, 'medium');
});

test('an agent without reasoning exposes its model as the probed config option', () => {
  const capability = { cliType: 'registry', agentType: 'gemini', models: [], configOptions: [
    { id: 'model', name: 'Model', category: 'model', type: 'select', currentValue: 'pro',
      options: [{ value: 'pro', name: 'Pro' }, { value: 'flash', name: 'Flash' }] },
  ] };
  const projected = projectRunConfig({ cliType: 'registry', agentType: 'gemini', capability,
    turn: { id: 'u1', inputConfig: { configOptionValues: { model: 'flash' } } }, runtimeConfig: {} });
  assert.deepEqual(projected.model, { value: 'flash', label: 'Flash' });
  assert.equal(projected.reasoning, null);
  assert.deepEqual(projected.editable, {
    kind: 'model', configOptionID: 'model',
    options: [{ value: 'pro', label: 'Pro' }, { value: 'flash', label: 'Flash' }],
  });
});

test('missing or mismatched capabilities keep the current values read-only', () => {
  const turn = { id: 'u1', inputConfig: { modelId: 'opus', configOptionValues: { effort: 'high' } } };
  for (const capability of [undefined, { ...codexCapability, agentType: 'claude' }]) {
    const projected = projectRunConfig({ cliType: 'builtin', agentType: 'codex', capability,
      turn, runtimeConfig: {} });
    assert.deepEqual(projected, {
      model: { value: 'opus', label: 'opus' }, reasoning: { value: 'high', label: 'High' }, editable: null,
    });
  }
  assert.equal(projectRunConfig({ cliType: 'builtin', agentType: 'codex', turn: undefined }), null);
});

test('the latest user turn with input config is the baseline', () => {
  const entries = [
    { id: 'u1', role: 'user', inputConfig: { modelId: 'a' } },
    { id: 'a1', role: 'assistant' },
    { id: 'u2', role: 'user' },
  ];
  assert.equal(latestUserTurn(entries).id, 'u1');
});

test('a choice changes only its own field', () => {
  const base = { modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high', fast: 'on' } };
  assert.deepEqual(applyRunConfigChoice(base, { configOptionID: 'reasoning_effort', value: 'low' }),
    { modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'low', fast: 'on' } });
  assert.deepEqual(applyRunConfigChoice(base, { configOptionID: null, value: 'gpt-5.4-mini' }),
    { ...base, modelId: 'gpt-5.4-mini' });
  assert.equal(applyRunConfigChoice(base, null), base);
  assert.throws(() => applyRunConfigChoice(base, { value: '' }), /Invalid/);
});


test('runtime option tables replace the old table, including an empty snapshot', () => {
  const turn = { id: 'u1', inputConfig: {
    modelId: 'old-model', configOptionValues: { reasoning_effort: 'high' },
  } };
  const projected = projectRunConfig({ cliType: 'builtin', agentType: 'codex',
    capability: codexCapability, turn,
    runtimeConfig: { basedOnUserTurnId: 'u1', modelId: 'actual-model', configOptionValues: {} },
  });
  assert.equal(projected.model.value, 'actual-model');
  assert.equal(projected.reasoning, null);
});

test('an explicit empty model reasoning list stays read-only', () => {
  const capability = { ...codexCapability, modelReasoningEfforts: { 'gpt-5.5': [] } };
  const projected = projectRunConfig({ cliType: 'builtin', agentType: 'codex', capability,
    turn: { id: 'u1', inputConfig: { modelId: 'gpt-5.5' } } });
  assert.equal(projected.model.value, 'gpt-5.5');
  assert.equal(projected.editable, null);
});

test('an empty global reasoning list does not enable model switching', () => {
  const capability = { ...codexCapability, configOptions: codexCapability.configOptions.map(option =>
    option.id === 'reasoning_effort' ? { ...option, options: [] } : option) };
  const projected = projectRunConfig({ cliType: 'builtin', agentType: 'codex', capability,
    turn: { id: 'u1', inputConfig: { modelId: 'gpt-5.5' } } });
  assert.equal(projected.editable, null);
});
