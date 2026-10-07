import { activityTime, canRestoreArchivedSession, readLocalProjectState } from './session-archive.mjs';
import { appendUserTurn, assertSameTurn, sendText, synced } from './conversation-send.mjs';
import {
  applyNewSessionChoices, effectiveRunConfig, latestUserTurn, projectNewSessionRunConfig,
} from './run-config.mjs';

const text = value => typeof value === 'string' && value.length > 0 ? value : undefined;
// Agent roles and chain depth describe how the source session was created.
const INHERITED_CONFIG_KEYS = ['modeId', 'modelId', 'configOptionValues', 'mcpServerIds'];
const TITLE_LENGTH = 50;

// Project only a public icon key, never agent environment or credentials.
export function providerIcon(config) {
  if (config?.cliType === 'custom') return null;
  const brands = { deepseek: ['deepseek.com'], mimo: ['xiaomimimo.com'],
    minimax: ['minimaxi.com', 'minimax.io'], glm: ['bigmodel.cn', 'z.ai'] };
  if (Object.hasOwn(brands, config?.brandId ?? '')) return config.brandId;
  if (config?.cliType === 'builtin') {
    try {
      const host = new URL(config.env?.ANTHROPIC_BASE_URL).hostname.toLowerCase();
      for (const [brand, domains] of Object.entries(brands)) {
        if (domains.some(domain => host === domain || host.endsWith(`.${domain}`))) return brand;
      }
    } catch { /* A missing or custom endpoint has no inferred brand. */ }
  }
  const aliases = { 'claude-p': 'claude', 'amp-acp': 'amp', 'pi-acp': 'pi',
    'github-copilot-cli': 'copilot', 'gemini-cli': 'gemini', 'grok-build': 'grok',
    'reasonix': 'deepseek' };
  const type = aliases[config?.agentType] ?? config?.agentType;
  return ['codex', 'claude', 'gemini', 'deepseek', 'kimi', 'grok', 'minimax', 'glm', 'mimo',
    'pi', 'devin', 'amp', 'cursor', 'opencode', 'copilot'].includes(type) ? type : null;
}

const isRootSession = (row, allowArchived = false) => row.docId?.startsWith('session-') &&
  !row.docId.startsWith('session-comment-') && !row.deleted &&
  (allowArchived || !row.meta?.isArchived) && !row.meta?.parentSessionId;

// Agent configs are scoped to their machine's Flock document.
function readProviders(flock, machineID) {
  const providers = [];
  for (const row of flock.scan({ prefix: ['agentConfig'] })) {
    const id = row.key?.[1];
    const config = row.value;
    if (!text(id) || !text(config?.cliType) || !text(config?.agentType) ||
        (text(config.machineId) && config.machineId !== machineID)) continue;
    providers.push({ id, name: text(config.name) ?? config.agentType, cliType: config.cliType,
      agentType: config.agentType, icon: providerIcon(config) });
  }
  return providers.sort((a, b) => a.name.localeCompare(b.name));
}

// The most recent session with this agent across projects gives
// the first turn's permission mode, model, options and MCP selection.
async function readBaseline(repo, rows, meta, agentConfigID, signal, cache) {
  const candidates = rows
    .filter(row => isRootSession(row) && row.meta.machineId === meta.machineId &&
      row.meta.agentConfigId === agentConfigID)
    .sort((a, b) => activityTime(b.meta) - activityTime(a.meta));
  const source = candidates[0];
  if (!source) return {};
  return readDocumentBaseline(repo, source.docId, signal, cache);
}

async function readDocumentBaseline(repo, docID, signal, cache) {
  const before = cache ? JSON.parse(JSON.stringify(await repo.getDocMeta(docID) ?? null)) : undefined;
  signal?.throwIfAborted();
  const cached = cache?.baseline(docID, before);
  if (cached !== undefined) return cached;
  const handle = await repo.openPersistedDoc(docID);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'], signal }))) {
    throw new Error('Session history sync failed');
  }
  const inherited = effectiveRunConfig(
    latestUserTurn(handle.doc.getList('history').toJSON()),
    handle.doc.getMap('acpRuntimeConfig').toJSON(),
  );
  const baseline = {};
  for (const key of INHERITED_CONFIG_KEYS) {
    if (inherited[key] !== undefined) baseline[key] = inherited[key];
  }
  if (cache) {
    const after = await repo.getDocMeta(docID);
    signal?.throwIfAborted();
    cache.rememberBaseline(docID, before, after, baseline);
  }
  return baseline;
}

// A new session reuses the machine and local project of a recent root session
// in the same project and starts in that project's directory. Its agent defaults
// to that session's and may be any agent configured on the same machine.
async function readTemplate(repo, workspaceID, templateSessionID, agentConfigID, signal,
  { allowArchived = false, projectID, tab = false, includeBaseline = true, cache } = {}) {
  signal?.throwIfAborted();
  const rows = await repo.listDoc();
  const templateDocID = `session-${templateSessionID}`;
  const row = rows.find(entry => entry.docId === templateDocID);
  const meta = row?.meta;
  const project = meta?.project;
  if (!row || !isRootSession(row, allowArchived) ||
      (!tab && (project?.kind !== 'local' || !text(project.localProjectId))) || !text(meta.machineId) ||
      !text(meta.cliType) || !text(meta.agentType)) {
    throw new Error('Project is unavailable for a new session');
  }

  // A tab inherits its parent project; it may run another agent from the machine.
  if (tab && projectID) throw new Error('Tab inherits its parent project');
  let targetMeta = meta;
  if (projectID !== undefined) {
    const prefix = `local:${meta.machineId}:`;
    if (!projectID.startsWith(prefix) || !projectID.slice(prefix.length)) {
      throw new Error('Target project belongs to another machine');
    }
    targetMeta = { ...meta, project: project.localProjectId === projectID.slice(prefix.length)
      ? project : { kind: 'local', localProjectId: projectID.slice(prefix.length) } };
  }
  const flockDocID = `${workspaceID}:mf:${meta.machineId}`;
  let flock = cache?.machine(flockDocID);
  try {
    if (!flock) {
      const machine = await repo.openFlockDoc(flockDocID);
      const report = await repo.sync({ scope: 'doc', flockDocIds: [flockDocID], requireTransports: ['cloud'], signal });
      signal?.throwIfAborted();
      if (report.ok) {
        flock = machine.flock;
        cache?.rememberMachine(flockDocID, flock);
      }
    }
  } catch {
    signal?.throwIfAborted();
    // Without the machine document only the template's agent is offered, at its inherited values.
  }
  signal?.throwIfAborted();
  // Reuse the known machine snapshot and the restore rules, including legacy projects.
  if (flock) {
    const state = await readLocalProjectState(repo, workspaceID, meta.machineId, signal, flock);
    if (!canRestoreArchivedSession(targetMeta, state)) throw new Error('Project is unavailable for a new session');
  }
  if (projectID && !flock) throw new Error('Target project could not be verified');
  let providers = flock ? readProviders(flock, meta.machineId) : [];
  // The inherited agent remains selectable even while viewing another provider.
  if (!providers.some(provider => provider.id === meta.agentConfigId)) {
    providers = [{ id: meta.agentConfigId, name: meta.agentType,
      cliType: meta.cliType, agentType: meta.agentType, icon: providerIcon(meta) }, ...providers];
  }
  const chosenID = text(agentConfigID) ?? meta.agentConfigId;
  const agent = providers.find(provider => provider.id === chosenID);
  if (!agent) throw new Error('Provider is unavailable for a new session');
  // A tab on the parent's agent keeps the parent's exact run configuration;
  // a tab on another agent starts from that agent's most recent use, like a
  // new session does.
  const inheritsAgent = !text(agentConfigID) || agentConfigID === meta.agentConfigId;
  // A confirmed retry only needs the meta/agent halves; the baseline doc sync
  // serves the first turn's inherited configuration and can be skipped.
  const baseline = !includeBaseline ? {}
    : !tab
    ? (text(agent.id)
        ? await readBaseline(repo, rows, meta, agent.id, signal, cache)
        : await readDocumentBaseline(repo, templateDocID, signal, cache))
    : (inheritsAgent
        ? await readDocumentBaseline(repo, templateDocID, signal, cache)
        : await readBaseline(repo, rows, meta, agent.id, signal, cache));
  signal?.throwIfAborted();
  const machineName = text(rows.find(entry => entry.docId === `machine-${meta.machineId}`)?.meta?.name);
  return {
    meta: targetMeta,
    agent,
    baseline,
    machineName: machineName ?? meta.machineId,
    providers: providers.map(provider => ({ value: provider.id ?? '', label: provider.name, icon: provider.icon })),
    runConfig: projectNewSessionRunConfig({
      cliType: agent.cliType, agentType: agent.agentType,
      capability: flock && text(agent.id) ? flock.get(['acpCapability', agent.id]) : undefined,
      baseline,
    }),
  };
}

export async function newSessionOptions(repo, workspaceID, templateSessionID, agentConfigID, signal, projectID, tab = false, cache) {
  const template = await readTemplate(repo, workspaceID, templateSessionID, agentConfigID, signal, { projectID, tab, cache });
  return {
    machineName: template.machineName,
    agentConfigID: template.agent.id ?? '',
    providers: template.providers,
    runConfig: template.runConfig,
    ...(cache?.needsRefresh ? { needsRefresh: true } : {}),
  };
}

// The first turn is durable before the session metadata that publishes it, so
// the machine never sees a session without its message. Metadata carries the
// dispatch pointer in the same write. Retries reuse both IDs.
export async function startSession(repo, workspaceID, {
  templateSessionID, projectID, agentConfigID, sessionID, turnID, userID, text: prompt, timestamp, selections, attachments = [], parentSessionID, title,
}) {
  if (!text(userID) || !text(sessionID) || !text(turnID)) {
    throw new Error('Session dispatch configuration is unavailable');
  }
  if (!text(prompt?.trim()) && !attachments.length) throw new Error('Message is empty');
  const docID = `session-${sessionID}`;
  const published = (await repo.listDoc()).find(entry => entry.docId === docID);
  if (published?.deleted) throw new Error('Session was removed');
  if (published) {
    if ((published.meta?.parentSessionId ?? undefined) !== parentSessionID) throw new Error('Session parent does not match');
    if (projectID && projectID !== `local:${published.meta?.machineId}:${published.meta?.project?.localProjectId}`) throw new Error('Session project does not match');
    if (published.meta?.userId !== userID) throw new Error('Session ID belongs to another session');
    return sendText(repo, sessionID, turnID, userID, prompt, timestamp, undefined, attachments);
  }

  const handle = await repo.openPersistedDoc(docID);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const history = handle.doc.getList('history');
  const entries = history.toJSON();
  const existing = entries.find(entry => entry?.id === turnID);
  if (existing) assertSameTurn(existing, userID, prompt, attachments);
  else if (entries.length > 0) throw new Error('Session ID belongs to another session');

  let template;
  let config;
  try {
    // Archiving the source must not strand a first turn already authored by this request.
    // Only a synced, matching turn may resume from an archived template.
    if (parentSessionID) {
      if (parentSessionID !== templateSessionID || projectID) throw new Error('Invalid tab parent');
      template = await readTemplate(repo, workspaceID, parentSessionID, agentConfigID, undefined,
        { tab: true, includeBaseline: !existing });
    } else {
      template = await readTemplate(repo, workspaceID, templateSessionID, agentConfigID, undefined,
        { allowArchived: Boolean(existing), projectID, includeBaseline: !existing });
    }
    if (!existing) config = applyNewSessionChoices({
      prompt, inputBlocks: [{ type: 'text', text: prompt }, ...attachments],
      cliType: template.agent.cliType, agentType: template.agent.agentType, ...template.baseline,
    }, template.runConfig, selections);
  } catch (error) {
    // A synced empty document proves there is no first turn to preserve.
    // Once authored, any error must retain the original retry IDs/configuration.
    if (!existing) return 'rejected';
    throw error;
  }
  const { meta: source, agent } = template;
  if (!existing) {
    appendUserTurn(history, { turnID, userID, text: prompt, timestamp, config });
    handle.doc.commit();
    if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
      return 'unconfirmed';
    }
  }

  const project = parentSessionID ? { ...(source.project ?? { kind: 'chat' }) }
    : { kind: 'local', localProjectId: source.project.localProjectId };
  if (text(source.project?.githubRepoFullName)) {
    project.githubRepoFullName = source.project.githubRepoFullName;
  }
  const meta = {
    id: sessionID,
    machineId: source.machineId,
    userId: userID,
    status: { type: 'idle' },
    isArchived: false,
    createdAt: timestamp,
    cliType: agent.cliType,
    agentType: agent.agentType,
    title: (text(title) ?? (prompt.trim() || attachments[0]?.fileName || 'New session')).slice(0, TITLE_LENGTH),
    titleSource: text(title) ? 'user' : 'draft',
    project,
    latestUserMsgId: turnID,
    lastMessageAt: Date.now(),
  };
  if (parentSessionID) {
    meta.parentSessionId = parentSessionID;
    if (source.isWorktree !== undefined) meta.isWorktree = source.isWorktree;
    if (source.repoFullName) meta.repoFullName = source.repoFullName;
  }
  if (text(agent.id)) meta.agentConfigId = agent.id;
  if (project.githubRepoFullName) meta.repoFullName = project.githubRepoFullName;
  await repo.upsertDocMeta(docID, meta);
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const confirmed = await repo.getDocMeta(docID);
  return confirmed?.meta.latestUserMsgId === turnID ||
    confirmed?.meta.lastHandledUserMsgId === turnID ? 'sent' : 'unconfirmed';
}
