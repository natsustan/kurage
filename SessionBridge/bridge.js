import { sessionProjects } from './session-projects.mjs';
import { projectGitSource, readProjectGit, switchProjectBranch } from './project-git.mjs';
import { respondQuestion } from './conversation-questions.mjs';
import { updateSessionMetadata } from './session-metadata.mjs';
import { LoroRepo } from 'loro-repo';
import { StreamsTransportAdapter } from 'loro-repo/transport/streams';
import { decompress as decompressZstd } from '@loro-dev/streams-crdt/zstd';
import { projectConversation } from './conversation-projection.mjs';
import { projectSessionActivity } from './session-activity.mjs';
import { runningSessionTabParents } from './session-tabs.mjs';

import { createNativeFetch } from './native-fetch.mjs';
import { observeConversation, readSyncedConversation, syncedConversationVersion } from './conversation-observer.mjs';
import { sendText } from './conversation-send.mjs';
import { mentionSkills } from './mention-skills.mjs';
import { requestMachine } from './machine-rpc.mjs';
import { turnDiffSource, loadTurnDiff } from './turn-diff.mjs';
import { cancelSession } from './conversation-cancel.mjs';
import { newSessionOptions, startSession } from './session-start.mjs';
import { createSessionOptionsCache } from './session-options-cache.mjs';
import { activityTime, archiveSession, deleteArchivedSession, readLocalProjectState, restoreArchivedSession, selectArchivedSessions } from './session-archive.mjs';

const nativeFetch = createNativeFetch(
  message => window.webkit.messageHandlers.streamFetch.postMessage(message),
  globalThis.fetch.bind(globalThis),
);
globalThis.fetch = nativeFetch.fetch;
window.kurageFetchEvent = nativeFetch.receive;

const snapshotCodec = {
  compress: async (bytes) => bytes,
  decompress: async (bytes) =>
    bytes.length >= 4 && bytes[0] === 0x28 && bytes[1] === 0xb5 &&
      bytes[2] === 0x2f && bytes[3] === 0xfd
      ? await decompressZstd(bytes) : bytes,
};

let cachedWorkspace;
let workspaceOperation = Promise.resolve();
const sessionRefreshes = new Map();
// Like native pending sends, steer targets live only for this account's bridge.
const steerTargets = new Map();
const workspaceTransports = new WeakMap();

// Only a replica that authors a new session may create its document stream.
async function createWorkspaceRepo(workspaceID, gatewayBaseURL,
  { createStreams = false, operationID, signal } = {}) {
  const repo = await LoroRepo.create({ metaDebounceCommitMs: 0 });
  try {
    const transport = new StreamsTransportAdapter({
      bucketId: 'lody',
      metaStreamId: `${workspaceID}:meta`,
      docStreamId: (docID) => docID.startsWith('session-')
        ? `${workspaceID}:s:${docID.slice('session-'.length)}` : docID,
      flockDocStreamId: (flockDocID) => flockDocID,
      auth: async context => {
        const access = await window.webkit.messageHandlers.streamFetch.postMessage({
          command: 'auth', workspaceID, operationID, refresh: context?.reason === 'unauthorized',
        });
        signal?.throwIfAborted();
        if (signal) nativeFetch.bindSignal(access.token, signal);
        return access.token;
      },
      baseUrl: gatewayBaseURL,
      createStreamIfMissing: createStreams,
      persistence: { mode: 'ephemeral' },
      snapshotCodec,
    });
    await repo.addTransport('cloud', transport);
    workspaceTransports.set(repo, transport);
    return repo;
  } catch (error) {
    await repo.destroy();
    throw error;
  }
}

window.kurageCancel = (operationID) => {
  sessionRefreshes.get(operationID)?.abort();
};

window.kurageTurnDiff = async (workspaceID, sessionID, gatewayBaseURL, turnID, path, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try {
    // Resolve metadata under the read lock, then perform the machine read outside
    // it. A slow diff must not block conversation or workspace refreshes.
    const sourceController = new AbortController();
    const cancelSource = () => sourceController.abort();
    controller.signal.addEventListener('abort', cancelSource, { once: true });
    let source;
    try {
      controller.signal.throwIfAborted();
      source = await withWorkspaceReadRepo(workspaceID, gatewayBaseURL,
        repo => turnDiffSource(repo, sessionID, controller.signal), operationID, sourceController);
    } finally { controller.signal.removeEventListener('abort', cancelSource); }
    controller.signal.throwIfAborted();
    const access = { baseURL: gatewayBaseURL, auth: async context => {
      const access = await window.webkit.messageHandlers.streamFetch.postMessage({
        command: 'auth', workspaceID, operationID, refresh: context?.reason === 'unauthorized',
      });
      controller.signal.throwIfAborted();
      nativeFetch.bindSignal(access.token, controller.signal);
      return access.token;
    } };
    return JSON.stringify(await loadTurnDiff(source, access, workspaceID, sessionID, turnID, path,
      controller.signal));
  } finally {
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

window.kurageProjectGit = async (workspaceID, gatewayBaseURL, templateSessionID, projectID, userID, branch, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try {
    const sourceController = new AbortController();
    const cancelSource = () => sourceController.abort();
    controller.signal.addEventListener('abort', cancelSource, { once: true });
    let source;
    try {
      controller.signal.throwIfAborted();
      // Refresh metadata for the busy check; release its lock before machine IO.
      source = await withWorkspaceReadRepo(workspaceID, gatewayBaseURL,
        repo => projectGitSource(repo, workspaceID, templateSessionID, projectID, controller.signal),
        operationID, sourceController, true);
    } finally { controller.signal.removeEventListener('abort', cancelSource); }
    controller.signal.throwIfAborted();
    const access = { baseURL: gatewayBaseURL, auth: async context => {
      const access = await window.webkit.messageHandlers.streamFetch.postMessage({
        command: 'auth', workspaceID, operationID, refresh: context?.reason === 'unauthorized',
      });
      controller.signal.throwIfAborted();
      nativeFetch.bindSignal(access.token, controller.signal);
      return access.token;
    } };
    const result = branch == null
      ? await readProjectGit(source, access, workspaceID, userID, controller.signal)
      : await switchProjectBranch(source, access, workspaceID, userID, branch, controller.signal, requestMachine,
        async () => {
          const recheckController = new AbortController();
          const cancel = () => recheckController.abort();
          controller.signal.addEventListener('abort', cancel, { once: true });
          try {
            controller.signal.throwIfAborted();
            return await withWorkspaceReadRepo(workspaceID, gatewayBaseURL,
              repo => projectGitSource(repo, workspaceID, templateSessionID, projectID, controller.signal),
              operationID, recheckController, true);
          } finally { controller.signal.removeEventListener('abort', cancel); }
        });
    return JSON.stringify(result);
  } finally {
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

function createWorkspaceState(rawRepo, workspaceID, gatewayBaseURL) {
  const state = { workspaceID, gatewayBaseURL, metaReady: false, documents: new Map(), optionsCache: createSessionOptionsCache() };
  const methods = {
    openPersistedDoc: async id => {
      const handle = await rawRepo.openPersistedDoc(id);
      state.documents.set(id, handle);
      return handle;
    },
    unloadDoc: async id => {
      await rawRepo.unloadDoc(id);
      // This repo has no body storage. unloadDoc retains the Streams cursor,
      // so reopening an empty replica would skip all history before that offset.
      // Forget only transport-local state after a successful eviction.
      await workspaceTransports.get(rawRepo).forgetDoc(id);
      state.documents.delete(id);
    },
  };
  state.repo = new Proxy(rawRepo, { get: (target, property) => {
    if (Object.hasOwn(methods, property)) return methods[property];
    const value = Reflect.get(target, property, target);
    return typeof value === 'function' ? value.bind(target) : value;
  } });
  return state;
}

function withWorkspaceRepo(workspaceID, gatewayBaseURL, work, refreshMeta = true, signal) {
  // The session list has already synced metadata. Keep its in-memory repo so
  // opening a conversation needs only the session document sync.
  const operation = workspaceOperation.then(async () => {
    signal?.throwIfAborted();
    let state = cachedWorkspace;
    if (state && (state.workspaceID !== workspaceID || state.gatewayBaseURL !== gatewayBaseURL)) {
      cachedWorkspace = undefined;
      await state.repo.destroy();
      state = undefined;
    }
    signal?.throwIfAborted();
    if (!state) {
      state = createWorkspaceState(await createWorkspaceRepo(workspaceID, gatewayBaseURL), workspaceID, gatewayBaseURL);
      cachedWorkspace = state;
    }
    if (refreshMeta || !state.metaReady) {
      const report = await state.repo.sync({ scope: 'meta', requireTransports: ['cloud'], signal });
      if (!report.ok) throw new Error('Workspace metadata sync failed');
      state.metaReady = true;
    }
    signal?.throwIfAborted();
    return work(state.repo, state.optionsCache);
  });
  workspaceOperation = operation.catch(() => {});
  return operation;
}

function withWorkspaceReadRepo(workspaceID, gatewayBaseURL, work, operationID, controller, refreshMeta = false) {
  const operation = workspaceOperation.then(async () => {
    const signal = controller.signal;
    signal.throwIfAborted();
    const state = cachedWorkspace;
    const shared = !refreshMeta && state?.metaReady && state.workspaceID === workspaceID &&
      state.gatewayBaseURL === gatewayBaseURL ? state : undefined;
    let isolated;
    const coldDocuments = new Set();
    const coldFlockDocuments = new Set();
    const sharedDocuments = new Set();
    const borrowed = new Map();
    let reuseLive = true;
    const isObserved = sessionID => [...observations.values()].some(observation => observation.ready &&
      observation.workspaceID === workspaceID && observation.sessionID === sessionID && !observation.controller.signal.aborted);
    const confirmedVersion = async (id, handle) => syncedConversationVersion(shared.repo, workspaceID,
      id.slice('session-'.length), handle.doc, await shared.repo.getDocMeta(id));
    const getIsolatedRepo = async () => isolated ??= await createWorkspaceRepo(workspaceID, gatewayBaseURL, { operationID, signal });
    // Reuse a live transcript only while its confirmed history matches metadata.
    // Other resources sync separately: cancelling a one-shot Streams sync cannot
    // safely cancel a request also owned by a live room on the shared replica.
    const reader = {
      isObserved: id => shared?.documents.has(id) && isObserved(id.slice('session-'.length)),
      listDoc: async () => (shared?.repo ?? await getIsolatedRepo()).listDoc(),
      getDocMeta: async id => (shared?.repo ?? await getIsolatedRepo()).getDocMeta(id),
      openPersistedDoc: async id => {
        const handle = shared?.documents.get(id);
        if (handle) {
          sharedDocuments.add(id);
          const sessionID = id.slice('session-'.length);
          if (reuseLive && isObserved(sessionID)) {
            const version = await confirmedVersion(id, handle);
            if (version !== undefined) {
              borrowed.set(id, { handle, version });
              return handle;
            }
          }
        }
        coldDocuments.add(id);
        return (await getIsolatedRepo()).openPersistedDoc(id);
      },
      openFlockDoc: async id => {
        // A list pull does not keep machine providers or capabilities live.
        coldFlockDocuments.add(id);
        return (await getIsolatedRepo()).openFlockDoc(id);
      },
      sync: async options => {
        signal.throwIfAborted();
        const docIds = (options.docIds ?? []).filter(id => coldDocuments.has(id));
        const flockDocIds = (options.flockDocIds ?? []).filter(id => coldFlockDocuments.has(id));
        if (options.scope !== 'meta' && !docIds.length && !flockDocIds.length) return { ok: true, outcome: 'synced' };
        return (await getIsolatedRepo()).sync({ ...options, docIds, flockDocIds, signal });
      },
    };
    try {
      if (!shared) {
        const report = await (await getIsolatedRepo()).sync({ scope: 'meta', requireTransports: ['cloud'], signal });
        signal.throwIfAborted();
        if (!report.ok) throw new Error('Workspace metadata sync failed');
      }
      let result = await work(reader, shared?.optionsCache);
      // Recheck after awaits: a live patch may have superseded the borrowed
      // baseline during this read. Retry once entirely on the scoped replica.
      for (const [id, { handle, version }] of borrowed) {
        if (!isObserved(id.slice('session-'.length)) || await confirmedVersion(id, handle) !== version) {
          signal.throwIfAborted();
          reuseLive = false;
          result = await work(reader, shared?.optionsCache);
          break;
        }
      }
      signal.throwIfAborted();
      return result;
    } finally {
      // destroy() alone does not cancel an in-flight one-shot sync in the pinned
      // Streams library; abort its own auth scope before releasing the replica.
      controller.abort();
      await isolated?.destroy();
      for (const docID of sharedDocuments) {
        const observed = [...observations.values()].some(observation => observation.workspaceID === workspaceID &&
          `session-${observation.sessionID}` === docID);
        if (!observed) await shared.repo.unloadDoc(docID);
      }
    }
  });
  workspaceOperation = operation.catch(() => {});
  return operation;
}

window.kurageSessions = async (workspaceID, gatewayBaseURL, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try { return await withWorkspaceRepo(workspaceID, gatewayBaseURL, async (repo, optionsCache) => {
    const rows = await repo.listDoc();
    const visibleSessions = rows.filter((row) => row.docId.startsWith('session-') &&
      !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta.isArchived &&
      !row.meta.parentSessionId);
    const runningTabParents = runningSessionTabParents(rows);
    const machineNames = new Map(rows
      .filter(row => row.docId.startsWith('machine-') && !row.deleted &&
        typeof row.meta?.name === 'string' && row.meta.name.length > 0)
      .map(row => [row.docId.slice('machine-'.length), row.meta.name]));
    const localProjectNames = new Map();
    const machineIDs = new Set(visibleSessions
      .filter((row) => row.meta.project?.kind === 'local')
      .map((row) => row.meta.machineId)
      .filter((id) => typeof id === 'string' && id.length > 0));
    await Promise.all([...machineIDs].map(async (machineID) => {
      try {
        const document = await repo.openFlockDoc(`${workspaceID}:mf:${machineID}`);
        const sync = await repo.sync({
          scope: 'doc',
          flockDocIds: [`${workspaceID}:mf:${machineID}`],
          requireTransports: ['cloud'],
          signal: controller.signal,
        });
        controller.signal.throwIfAborted();
        if (!sync.ok) return;
        optionsCache.rememberMachine(`${workspaceID}:mf:${machineID}`, document.flock);
        for (const row of document.flock.scan({ prefix: ['localProject'] })) {
          if (typeof row.key?.[1] === 'string' && typeof row.value?.name === 'string') {
            localProjectNames.set(`${machineID}:${row.key[1]}`, row.value.name);
          }
        }
      } catch {
        controller.signal.throwIfAborted();
        // Project names are optional; session metadata still gives stable group IDs.
      }
    }));
    controller.signal.throwIfAborted();
    for (const machineID of machineIDs) {
      const legacy = rows.find((row) => row.docId === `machine-${machineID}`)?.meta?.localProjects;
      if (legacy && typeof legacy === 'object') {
        for (const [localID, project] of Object.entries(legacy)) {
          if (typeof project?.name === 'string') {
            const key = `${machineID}:${localID}`;
            if (!localProjectNames.has(key)) localProjectNames.set(key, project.name);
          }
        }
      }
    }
    visibleSessions.sort((a, b) => activityTime(b.meta) - activityTime(a.meta));
    const projected = visibleSessions.map((row) => {
      const project = row.meta.project;
      const repoName = project?.kind === 'github' ? project.repoFullName
        : project?.githubRepoFullName ?? row.meta.repoFullName;
      const localID = project?.kind === 'local' ? project.localProjectId : null;
      const projectID = typeof localID === 'string'
        ? `local:${row.meta.machineId}:${localID}`
        : typeof repoName === 'string' && repoName.length > 0 ? `github:${repoName}` : null;
      const fallbackName = typeof repoName === 'string' ? repoName.split('/').at(-1) : null;
      const projectName = typeof localID === 'string'
        ? localProjectNames.get(`${row.meta.machineId}:${localID}`) ?? fallbackName ?? 'Local Project'
        : fallbackName;
      return {
        id: row.docId.slice('session-'.length),
        title: typeof row.meta.title === 'string' && row.meta.title.length > 0
          ? row.meta.title : 'Untitled session',
        agentName: row.meta.agentType ?? row.meta.cliType ?? 'Agent',
        activity: projectSessionActivity(row.meta.status),
        hasRunningTabs: runningTabParents.has(row.docId.slice('session-'.length)),
        preview: row.meta.repoFullName ?? '',
        projectID,
        projectName,
        isPinned: row.meta.isPinned === true,
        lastActivityAt: activityTime(row.meta),
        lastReadAt: Number.isFinite(row.meta.lastReadAt) ? row.meta.lastReadAt : null,
        machineName: machineNames.get(row.meta.machineId) ?? null,
        lastMessageAt: Number.isFinite(row.meta.lastMessageAt)
          ? row.meta.lastMessageAt : null,
      };
    });
    return JSON.stringify({ sessions: projected });
  }, true, controller.signal); }
  finally { if (operationID) sessionRefreshes.delete(operationID); }
};

window.kurageMentionSessions = async (workspaceID, gatewayBaseURL, currentSessionID, projectID, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try { return await withWorkspaceReadRepo(workspaceID, gatewayBaseURL, async repo => {
    const rows = await repo.listDoc();
    controller.signal.throwIfAborted();
    const currentProjectKey = projectID.startsWith('github:') ? projectID.toLowerCase() : projectID;
    const sessions = rows.filter(row => row.docId.startsWith('session-') &&
      !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta?.isArchived &&
      row.docId !== `session-${currentSessionID}`).map(row => {
      const project = row.meta.project;
      const localID = project?.kind === 'local' ? project.localProjectId : null;
      const repoName = project?.kind === 'github' ? project.repoFullName :
        project?.githubRepoFullName ?? row.meta.repoFullName;
      const key = typeof localID === 'string' ? `local:${row.meta.machineId}:${localID}` :
        typeof repoName === 'string' && repoName.trim().length ? `github:${repoName.trim().toLowerCase()}` : null;
      return {
        id: row.docId.slice('session-'.length), title: row.meta.title || 'Untitled session',
        projectID: key, lastActivityAt: activityTime(row.meta),
      };
    }).filter(row => row.projectID === currentProjectKey)
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt);
    return JSON.stringify({ sessions });
  }, operationID, controller); }
  finally { if (operationID) sessionRefreshes.delete(operationID); }
};

window.kurageMentionSkills = async (workspaceID, gatewayBaseURL, templateSessionID,
  agentConfigID, userID, operationID, projectID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  const timeout = setTimeout(() => controller.abort(), 120000);
  try {
    // The metadata reader releases its own auth scope at completion. The
    // machine scan continues under the parent operation's cancellation scope.
    const sourceController = new AbortController();
    const abortSource = () => sourceController.abort();
    controller.signal.addEventListener('abort', abortSource, { once: true });
    let source;
    try {
      controller.signal.throwIfAborted();
      source = await withWorkspaceReadRepo(workspaceID, gatewayBaseURL, async repo => {
        const row = (await repo.listDoc()).find(row => row.docId === `session-${templateSessionID}` &&
          !row.deleted && !row.meta?.isArchived);
        if (!row) throw new Error('Session is unavailable in this workspace');
        const machineID = row.meta.machineId;
        if (typeof machineID !== 'string' || !machineID) throw new Error('Machine is unavailable');
        let agentType = row.meta.agentType ?? row.meta.cliType;
        if (agentConfigID && agentConfigID !== row.meta.agentConfigId) {
          const flockID = `${workspaceID}:mf:${machineID}`;
          const document = await repo.openFlockDoc(flockID);
          const synced = await repo.sync({ scope: 'doc', flockDocIds: [flockID],
            requireTransports: ['cloud'], signal: controller.signal });
          if (!synced.ok) throw new Error('Agent configuration sync failed');
          const config = Array.from(document.flock.scan({ prefix: ['agentConfig'] }))
            .find(item => item.key?.[1] === agentConfigID)?.value;
          if (!config?.agentType) throw new Error('Agent configuration is unavailable');
          agentType = config.agentType;
        }
        const prefix = `local:${machineID}:`;
        if (projectID && (!projectID.startsWith(prefix) || !projectID.slice(prefix.length))) {
          throw new Error('Skill project belongs to another machine');
        }
        const localProjectID = projectID ? projectID.slice(prefix.length) : row.meta.project?.kind === 'local'
          ? row.meta.project.localProjectId : null;
        return { machineID, localProjectID, agentType };
      }, operationID, sourceController);
    } finally {
      controller.signal.removeEventListener('abort', abortSource);
    }
    controller.signal.throwIfAborted();
    const skills = await mentionSkills({
      workspaceID, ...source, userID, gatewayBaseURL,
      auth: async () => {
        const access = await window.webkit.messageHandlers.streamFetch.postMessage({
          command: 'auth', workspaceID, operationID,
        });
        return access.token;
      },
      signal: controller.signal,
    });
    return JSON.stringify({ skills });
  }
  finally {
    clearTimeout(timeout);
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

window.kurageArchivedSessions = async (workspaceID, gatewayBaseURL, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try { return await withWorkspaceRepo(workspaceID, gatewayBaseURL, async (repo) => {
    const rows = await repo.listDoc();
    const machineIDs = new Set(rows
      .filter(row => row.docId?.startsWith('session-') && !row.docId.startsWith('session-comment-') &&
        !row.deleted && row.meta?.isArchived === true && !row.meta?.parentSessionId &&
        row.meta?.project?.kind === 'local' && typeof row.meta.machineId === 'string')
      .map(row => row.meta.machineId)
      .filter(id => id.length > 0));
    const availability = new Map();
    await Promise.all([...machineIDs].map(async (machineID) => {
      availability.set(
        machineID,
        await readLocalProjectState(repo, workspaceID, machineID, controller.signal),
      );
    }));
    controller.signal.throwIfAborted();
    return JSON.stringify({ sessions: selectArchivedSessions(rows, availability) });
  }, true, controller.signal); }
  finally { if (operationID) sessionRefreshes.delete(operationID); }
};

// Use a short-lived replica for writes so reader subscriptions and workspace
// switching cannot change the document being authored mid-send.
window.kurageSendText = async (workspaceID, sessionID, gatewayBaseURL, turnID, userID, text, timestamp, runConfig, attachments, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  const key = JSON.stringify([workspaceID, sessionID, turnID]);
  if (!steerTargets.has(key)) steerTargets.set(key, {});
  const state = steerTargets.get(key);
  let result;
  try {
    const access = {
      baseURL: gatewayBaseURL,
      auth: async context => {
        const token = await window.webkit.messageHandlers.streamFetch.postMessage({
          command: 'auth', workspaceID, operationID, refresh: context?.reason === 'unauthorized',
        });
        controller.signal.throwIfAborted();
        return token.token;
      },
    };
    const steering = { state, request: (machineID, params) => requestMachine(access, workspaceID, machineID,
      'session/steer', params, controller.signal, 5000) };
    result = await withSyncedWriteRepo(workspaceID, gatewayBaseURL,
      repo => sendText(repo, sessionID, turnID, userID, text, timestamp, runConfig, attachments, steering),
      { operationID, signal: controller.signal }, controller.signal);
    return result;
  } finally {
    controller.abort();
    if (!state.expectedTurnID || result === 'sent' || result === 'superseded') steerTargets.delete(key);
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

async function withSyncedWriteRepo(workspaceID, gatewayBaseURL, work, options, signal) {
  signal?.throwIfAborted();
  const repo = await createWorkspaceRepo(workspaceID, gatewayBaseURL, options);
  try {
    signal?.throwIfAborted();
    const meta = await repo.sync({ scope: 'meta', requireTransports: ['cloud'], signal });
    signal?.throwIfAborted();
    if (meta.outcome !== 'synced') throw new Error('Workspace metadata sync failed');
    return await work(repo);
  } finally {
    await repo.destroy();
  }
}

window.kurageNewSessionOptions = async (workspaceID, templateSessionID, agentConfigID, gatewayBaseURL, operationID, projectID, tab = false, refresh = false) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try {
    return await withWorkspaceReadRepo(workspaceID, gatewayBaseURL, async (repo, cache) => {
      const snapshot = cache?.reader({ refresh, isObserved: repo.isObserved });
      const read = reader => newSessionOptions(repo, workspaceID, templateSessionID, agentConfigID, controller.signal,
        projectID ?? undefined, tab, reader);
      try {
        return JSON.stringify(await read(snapshot));
      } catch (error) {
        controller.signal.throwIfAborted();
        if (!snapshot?.usedCache || refresh) throw error;
        // Cached deletion commands or agent catalogs may already be obsolete.
        // Retry once with fresh resources before declaring them unavailable.
        cache.clear();
        return JSON.stringify(await read(cache.reader({ refresh: true, isObserved: repo.isObserved })));
      }
    },
    operationID, controller);
  } finally {
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

window.kurageStartSession = async (workspaceID, gatewayBaseURL, request) => {
  let result;
  try {
    result = await withSyncedWriteRepo(workspaceID, gatewayBaseURL,
      repo => startSession(repo, workspaceID, request), { createStreams: true });
    return result;
  } finally {
    // A rejected creation must be able to reload options after a provider or
    // project changed. Successful writes invalidate baselines via metadata.
    if (result !== 'sent' && cachedWorkspace?.workspaceID === workspaceID &&
        cachedWorkspace.gatewayBaseURL === gatewayBaseURL) cachedWorkspace.optionsCache.clear();
  }
};

window.kurageCancelSession = (workspaceID, sessionID, gatewayBaseURL) =>
  withSyncedWriteRepo(workspaceID, gatewayBaseURL, repo => cancelSession(repo, sessionID));

window.kurageArchiveSession = (workspaceID, sessionID, gatewayBaseURL) =>
  withSyncedWriteRepo(workspaceID, gatewayBaseURL,
    repo => archiveSession(repo, sessionID).then(JSON.stringify));

window.kurageRestoreArchivedSession = async (workspaceID, sessionID, gatewayBaseURL) => {
  const repo = await createWorkspaceRepo(workspaceID, gatewayBaseURL);
  try {
    return await restoreArchivedSession(repo, workspaceID, sessionID);
  } finally {
    await repo.destroy();
  }
};

window.kurageDeleteArchivedSession = async (workspaceID, sessionID, gatewayBaseURL) => {
  const repo = await createWorkspaceRepo(workspaceID, gatewayBaseURL);
  try {
    return await deleteArchivedSession(repo, sessionID);
  } finally {
    await repo.destroy();
  }
};

window.kurageConversation = async (workspaceID, sessionID, gatewayBaseURL, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try { return await withWorkspaceRepo(workspaceID, gatewayBaseURL, async (repo) => {
    const docID = `session-${sessionID}`;
    const rows = await repo.listDoc();
    if (!rows.some((row) => row.docId === docID && !row.deleted)) {
      throw new Error('Session is missing from this workspace');
    }
    const handle = await repo.openPersistedDoc(docID);
    try {
      const conversation = await readSyncedConversation({
        repo, workspaceID, sessionID, doc: handle.doc, signal: controller.signal,
      });
      return JSON.stringify(conversation);
    } finally {
      // Search reads every transcript. Keep only documents used by a pending
      // or active observation; unloading those would invalidate its handle.
      const observed = [...observations.values()].some(observation =>
        observation.workspaceID === workspaceID && observation.sessionID === sessionID);
      if (!observed) await repo.unloadDoc(docID);
    }
  }, false, controller.signal); }
  finally { if (operationID) sessionRefreshes.delete(operationID); }
};

const observations = new Map();
window.kurageStopConversation = (id) => {
  const observation = observations.get(id);
  observations.delete(id);
  observation?.controller.abort();
};
window.kurageObserveConversation = async (workspaceID, sessionID, gatewayBaseURL, id, rootSessionID) => {
  const controller = new AbortController();
  observations.set(id, { controller, workspaceID, sessionID });
  try {
    await withWorkspaceRepo(workspaceID, gatewayBaseURL, async repo => {
      if (controller.signal.aborted) return;
      const available = await observeConversation({ repo, workspaceID, sessionID, rootSessionID, signal: controller.signal,
        emit: update => window.webkit.messageHandlers.streamFetch.postMessage({
          command: 'conversation', id, update,
        }),
      });
      if (available !== false && !controller.signal.aborted) observations.get(id).ready = true;
    }, false, controller.signal);
    return 'ok';
  } catch (error) {
    window.kurageStopConversation(id);
    throw error;
  }
};

window.kurageUpdateSessionMetadata = async (workspaceID, sessionID, gatewayBaseURL, change, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try {
    return await withSyncedWriteRepo(workspaceID, gatewayBaseURL,
      repo => updateSessionMetadata(repo, sessionID, change, controller.signal),
      { operationID, signal: controller.signal }, controller.signal);
  } finally {
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

window.kurageRespondQuestion = async (workspaceID, sessionID, baseURL, turnID, requestID, answers, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  try {
    return await withSyncedWriteRepo(workspaceID, baseURL,
      repo => respondQuestion(repo, sessionID, turnID, requestID, answers, controller.signal),
      { operationID, signal: controller.signal }, controller.signal);
  } finally {
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};

window.kurageSessionProjects = async (workspaceID, gatewayBaseURL, templateSessionID, action, path, cursor, operationID) => {
  const controller = new AbortController();
  if (operationID) sessionRefreshes.set(operationID, controller);
  const timeout = setTimeout(() => controller.abort(), 120000);
  try {
    const access = {
      baseURL: gatewayBaseURL,
      auth: async () => {
        const token = await window.webkit.messageHandlers.streamFetch.postMessage({
          command: 'auth', workspaceID, operationID,
        });
        return token.token;
      },
    };
    const run = repo => sessionProjects(repo, workspaceID, templateSessionID, action, path, cursor,
      access, controller.signal);
    if (action === 'select') {
      try {
        return await withSyncedWriteRepo(workspaceID, gatewayBaseURL, async repo => JSON.stringify(await run(repo)),
          { operationID, signal: controller.signal }, controller.signal);
      } finally {
        if (cachedWorkspace?.workspaceID === workspaceID) cachedWorkspace.optionsCache.clear();
      }
    }
    // Catalog refreshes independently; browse needs only the cached machine ID.
    return await withWorkspaceReadRepo(workspaceID, gatewayBaseURL, async repo => JSON.stringify(await run(repo)),
      operationID, controller, action === 'catalog');
  } finally {
    clearTimeout(timeout);
    controller.abort();
    if (operationID) sessionRefreshes.delete(operationID);
  }
};
