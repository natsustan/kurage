// Mirrors Lody's selector resolution (`acp-selector-options.ts`,
// `acp-run-config.ts`) for the two values Kurage exposes per session.

const THOUGHT_LEVEL_CATEGORY = 'thought_level';
const REASONING_EFFORT_CONFIG_ID = 'reasoning_effort';
// Display-only fallback when no capability names the reasoning option.
const KNOWN_REASONING_CONFIG_IDS = [REASONING_EFFORT_CONFIG_ID, 'effort'];

const text = value => typeof value === 'string' && value.length > 0 ? value : undefined;
const record = value => value && typeof value === 'object' && !Array.isArray(value) ? value : undefined;
const stripRecommended = label => label.replace(/\s*\(recommended\)/gi, '');

function selectOptions(capability) {
  const options = Array.isArray(capability.configOptions) ? capability.configOptions : [];
  if (options.length > 0) {
    return options.filter(option => text(option?.id) && option.type === 'select' &&
      Array.isArray(option.options));
  }
  const models = Array.isArray(capability.models)
    ? capability.models.filter(model => text(model?.modelId)) : [];
  if (models.length === 0) return [];
  return [{
    id: 'model', category: 'model', type: 'select', currentValue: models[0].modelId,
    options: models.map(model => ({ value: model.modelId, name: text(model.name) ?? model.modelId })),
  }];
}

function choices(option) {
  return option.options
    .filter(choice => text(choice?.value))
    .map(choice => ({ value: choice.value, label: stripRecommended(text(choice.name) ?? choice.value) }));
}

function effortLabel(value) {
  return value === 'xhigh' ? 'X-High' : value.charAt(0).toUpperCase() + value.slice(1);
}

export function latestUserTurn(entries) {
  return entries.findLast(entry => entry?.role === 'user' && record(entry.inputConfig));
}

function matchingRuntime(turn, runtimeConfig) {
  return text(turn?.id) && runtimeConfig?.basedOnUserTurnId === turn.id
    ? runtimeConfig : undefined;
}

// Use the same baseline for the picker and new turns. A reported option table
// is a complete snapshot: omitted keys must not come back from the old input.
export function effectiveRunConfig(turn, runtimeConfig) {
  const input = record(turn?.inputConfig) ?? {};
  const runtime = matchingRuntime(turn, runtimeConfig);
  return {
    ...input,
    ...(text(runtime?.modelId) ? { modelId: runtime.modelId } : {}),
    ...(text(runtime?.modeId) ? { modeId: runtime.modeId } : {}),
    ...(record(runtime?.configOptionValues) ? { configOptionValues: runtime.configOptionValues } : {}),
  };
}

function capabilityOptions({ cliType, agentType, capability }) {
  const usable = record(capability) && capability.cliType === cliType &&
    capability.agentType === agentType ? capability : undefined;
  const options = usable ? selectOptions(usable) : [];
  return {
    usable,
    // Registry and custom agents carry the model as a config option value.
    probed: cliType === 'registry' || cliType === 'custom',
    modelOption: options.find(option => option.category === 'model'),
    reasoningOption: options.find(option =>
      option.id === REASONING_EFFORT_CONFIG_ID || option.category === THOUGHT_LEVEL_CATEGORY),
  };
}

// An explicitly empty per-model list means the model has no reasoning choice.
function reasoningChoicesFor(usable, reasoningOption, modelValue) {
  const efforts = modelValue && Array.isArray(usable?.modelReasoningEfforts?.[modelValue])
    ? usable.modelReasoningEfforts[modelValue].filter(text) : undefined;
  if (efforts === undefined) return reasoningOption ? choices(reasoningOption) : [];
  return efforts.map(value => ({
    value,
    label: (reasoningOption ? choices(reasoningOption) : [])
      .find(choice => choice.value === value)?.label ?? effortLabel(value),
  }));
}

export function projectRunConfig({ cliType, agentType, capability, turn, runtimeConfig }) {
  const { usable, probed, modelOption, reasoningOption } =
    capabilityOptions({ cliType, agentType, capability });
  const input = effectiveRunConfig(turn, runtimeConfig);
  const runtime = matchingRuntime(turn, runtimeConfig);
  const values = record(input.configOptionValues) ?? {};

  const modelValue = (probed && modelOption ? text(values[modelOption.id]) : undefined) ??
    text(runtime?.modelId) ?? text(input.modelId) ?? text(modelOption?.currentValue);
  const modelChoices = modelOption ? choices(modelOption) : [];
  const reasoningChoices = reasoningChoicesFor(usable, reasoningOption, modelValue);
  const reasoningID = reasoningOption?.id ??
    KNOWN_REASONING_CONFIG_IDS.find(id => text(values[id]));
  const reasoningValue = reasoningID
    ? text(values[reasoningID]) ?? (record(runtime?.configOptionValues)
      ? undefined : text(reasoningOption?.currentValue)) : undefined;

  const model = modelValue ? {
    value: modelValue,
    label: modelChoices.find(choice => choice.value === modelValue)?.label ?? modelValue,
  } : null;
  const reasoning = reasoningValue ? {
    value: reasoningValue,
    label: reasoningChoices.find(choice => choice.value === reasoningValue)?.label ??
      effortLabel(reasoningValue),
  } : null;
  // Switching models mid-conversation can discard the provider's prompt
  // cache. Offer the model only when the agent has no separate reasoning knob.
  let editable = null;
  if (reasoningOption && reasoningChoices.length > 0) {
    editable = { kind: 'reasoning', configOptionID: reasoningOption.id, options: reasoningChoices };
  } else if (!reasoningOption && modelOption && modelChoices.length > 0) {
    editable = { kind: 'model', configOptionID: probed ? modelOption.id : null, options: modelChoices };
  }
  if (!model && !reasoning && !editable) return null;
  return { model, reasoning, editable };
}

const pick = (options, ...candidates) =>
  candidates.map(text).find(value => value && options.some(option => option.value === value)) ??
    options[0]?.value;

// A new session has no provider context to preserve, so both the model and
// its reasoning are editable. `baseline` is the config the first turn inherits.
export function projectNewSessionRunConfig({ cliType, agentType, capability, baseline }) {
  const { usable, probed, modelOption, reasoningOption } =
    capabilityOptions({ cliType, agentType, capability });
  const values = record(baseline?.configOptionValues) ?? {};
  const modelChoices = modelOption ? choices(modelOption) : [];
  const model = modelChoices.length > 0 ? {
    configOptionID: probed ? modelOption.id : null,
    value: pick(modelChoices, probed ? values[modelOption.id] : baseline?.modelId,
      modelOption.currentValue),
    options: modelChoices.map(choice => ({
      ...choice, reasoning: reasoningChoicesFor(usable, reasoningOption, choice.value),
    })),
  } : null;
  const reasoning = reasoningOption ? {
    configOptionID: reasoningOption.id,
    value: text(values[reasoningOption.id]) ?? text(reasoningOption.currentValue) ?? null,
    // Used when there is no model list to carry per-model choices.
    options: reasoningChoicesFor(usable, reasoningOption, model?.value),
  } : null;
  if (!model && !reasoning?.options.length) return null;
  return { model, reasoning };
}

// Only values the projection offers may reach a new session's first turn.
// Selections come model first, so reasoning is checked against the chosen model.
export function applyNewSessionChoices(config, projection, selections) {
  const model = projection?.model;
  const reasoning = projection?.reasoning;
  let modelValue = model?.value;
  let result = config;
  for (const choice of selections ?? []) {
    const id = choice?.configOptionID ?? null;
    const offers = options => options.some(option => option.value === choice?.value);
    if (model && id === model.configOptionID && offers(model.options)) {
      modelValue = choice.value;
    } else {
      const options = model
        ? model.options.find(option => option.value === modelValue)?.reasoning ?? []
        : reasoning?.options ?? [];
      if (!reasoning || id !== reasoning.configOptionID || !offers(options)) {
        throw new Error('Invalid run configuration');
      }
    }
    result = applyRunConfigChoice(result, choice);
  }
  return result;
}

export function applyRunConfigChoice(config, choice) {
  if (choice == null) return config;
  if (!text(choice.value) ||
      (choice.configOptionID != null && !text(choice.configOptionID))) {
    throw new Error('Invalid run configuration');
  }
  if (choice.configOptionID) {
    return {
      ...config,
      configOptionValues: {
        ...(record(config.configOptionValues) ?? {}), [choice.configOptionID]: choice.value,
      },
    };
  }
  return { ...config, modelId: choice.value };
}
