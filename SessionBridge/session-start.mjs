import { appendUserTurn, assertSameTurn, sendText, synced } from './conversation-send.mjs';
import {
  applyNewSessionChoices, effectiveRunConfig, latestUserTurn, projectNewSessionRunConfig,
} from './run-config.mjs';

const text = value => typeof value === 'string' && value.length > 0 ? value : undefined;
// Agent roles and chain depth describe how the source session was created.
const INHERITED_CONFIG_KEYS = ['modeId', 'modelId', 'configOptionValues', 'mcpServerIds'];
const TITLE_LENGTH = 50;

const isRootSession = row => row.docId?.startsWith('session-') && !row.docId.startsWith('session-comment-') &&
  !row.deleted && !row.meta?.isArchived && !row.meta?.parentSessionId;
const activityAt = meta => Number.isFinite(meta?.lastMessageAt)
  ? meta.lastMessageAt : Date.parse(meta?.createdAt ?? '') || 0;

// Agent configs are scoped to their machine's Flock document.
function readProviders(flock, machineID) {
  const providers = [];
  for (const row of flock.scan({ prefix: ['agentConfig'] })) {
    const id = row.key?.[1];
    const config = row.value;
    if (!text(id) || !text(config?.cliType) || !text(config?.agentType) ||
        (text(config.machineId) && config.machineId !== machineID)) continue;
    providers.push({ id, name: text(config.name) ?? config.agentType, cliType: config.cliType, agentType: config.agentType });
  }
  return providers.sort((a, b) => a.name.localeCompare(b.name));
}

// The most recent session with this agent, preferring the same project, gives
// the first turn's permission mode, model, options and MCP selection.
async function readBaseline(repo, rows, meta, agentConfigID) {
  const candidates = rows
    .filter(row => isRootSession(row) && row.meta.machineId === meta.machineId &&
      row.meta.agentConfigId === agentConfigID)
    .sort((a, b) => {
      const sameProject = row => row.meta.project?.localProjectId === meta.project.localProjectId ? 1 : 0;
      return sameProject(b) - sameProject(a) || activityAt(b.meta) - activityAt(a.meta);
    });
  const source = candidates[0];
  if (!source) return {};
  const handle = await repo.openPersistedDoc(source.docId);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [source.docId], requireTransports: ['cloud'] }))) {
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
  return baseline;
}

// A new session reuses the machine and local project of a recent root session
// in the same project and starts in that project's directory. Its agent defaults
// to that session's and may be any agent configured on the same machine.
async function readTemplate(repo, workspaceID, templateSessionID, agentConfigID) {
  const rows = await repo.listDoc();
  const templateDocID = `session-${templateSessionID}`;
  const row = rows.find(entry => entry.docId === templateDocID);
  const meta = row?.meta;
  const project = meta?.project;
  if (!row || !isRootSession(row) || project?.kind !== 'local' ||
      !text(project.localProjectId) || !text(meta.machineId) ||
      !text(meta.cliType) || !text(meta.agentType)) {
    throw new Error('Project is unavailable for a new session');
  }

  let flock;
  const flockDocID = `${workspaceID}:mf:${meta.machineId}`;
  try {
    const machine = await repo.openFlockDoc(flockDocID);
    const report = await repo.sync({ scope: 'doc', flockDocIds: [flockDocID], requireTransports: ['cloud'] });
    if (report.ok) flock = machine.flock;
  } catch {
    // Without the machine document only the template's agent is offered, at its inherited values.
  }
  let providers = flock ? readProviders(flock, meta.machineId) : [];
  const chosenID = text(agentConfigID) ?? meta.agentConfigId;
  let agent = providers.find(provider => provider.id === chosenID);
  if (!agent) {
    if (text(agentConfigID) && agentConfigID !== meta.agentConfigId) {
      throw new Error('Provider is unavailable for a new session');
    }
    agent = { id: meta.agentConfigId, name: meta.agentType, cliType: meta.cliType, agentType: meta.agentType };
    providers = [agent, ...providers];
  }
  const baseline = text(agent.id)
    ? await readBaseline(repo, rows, meta, agent.id) : {};
  const machineName = text(rows.find(entry => entry.docId === `machine-${meta.machineId}`)?.meta?.name);
  return {
    meta,
    agent,
    baseline,
    machineName: machineName ?? meta.machineId,
    providers: providers.map(provider => ({ value: provider.id ?? '', label: provider.name })),
    runConfig: projectNewSessionRunConfig({
      cliType: agent.cliType, agentType: agent.agentType,
      capability: flock && text(agent.id) ? flock.get(['acpCapability', agent.id]) : undefined,
      baseline,
    }),
  };
}

export async function newSessionOptions(repo, workspaceID, templateSessionID, agentConfigID) {
  const template = await readTemplate(repo, workspaceID, templateSessionID, agentConfigID);
  return {
    machineName: template.machineName,
    agentConfigID: template.agent.id ?? '',
    providers: template.providers,
    runConfig: template.runConfig,
  };
}

// The first turn is durable before the session metadata that publishes it, so
// the machine never sees a session without its message. Metadata carries the
// dispatch pointer in the same write. Retries reuse both IDs.
export async function startSession(repo, workspaceID, {
  templateSessionID, agentConfigID, sessionID, turnID, userID, text: prompt, timestamp, selections,
}) {
  if (!text(userID) || !text(sessionID) || !text(turnID)) {
    throw new Error('Session dispatch configuration is unavailable');
  }
  if (!text(prompt?.trim())) throw new Error('Message is empty');
  const docID = `session-${sessionID}`;
  const published = (await repo.listDoc()).find(entry => entry.docId === docID);
  if (published?.deleted) throw new Error('Session was removed');
  if (published) {
    if (published.meta?.userId !== userID) throw new Error('Session ID belongs to another session');
    return sendText(repo, sessionID, turnID, userID, prompt, timestamp);
  }

  const template = await readTemplate(repo, workspaceID, templateSessionID, agentConfigID);
  const { meta: source, agent } = template;
  const handle = await repo.openPersistedDoc(docID);
  if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
    return 'unconfirmed';
  }
  const history = handle.doc.getList('history');
  const entries = history.toJSON();
  const existing = entries.find(entry => entry?.id === turnID);
  if (existing) {
    assertSameTurn(existing, userID, prompt);
  } else {
    if (entries.length > 0) throw new Error('Session ID belongs to another session');
    const config = applyNewSessionChoices({
      prompt, inputBlocks: [{ type: 'text', text: prompt }],
      cliType: agent.cliType, agentType: agent.agentType, ...template.baseline,
    }, template.runConfig, selections);
    appendUserTurn(history, { turnID, userID, text: prompt, timestamp, config });
    handle.doc.commit();
    if (!synced(await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'] }))) {
      return 'unconfirmed';
    }
  }

  const project = { kind: 'local', localProjectId: source.project.localProjectId };
  if (text(source.project.githubRepoFullName)) {
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
    title: prompt.trim().slice(0, TITLE_LENGTH),
    titleSource: 'draft',
    project,
    latestUserMsgId: turnID,
    lastMessageAt: Date.now(),
  };
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
