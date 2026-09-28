import { projectSubtasks } from './conversation-subtasks.mjs';
import { projectConversation } from './conversation-projection.mjs';
import { projectSessionActivity } from './session-activity.mjs';
import { latestUserTurn, projectRunConfig } from './run-config.mjs';

// Evidence survives document unloads, but never outlives its workspace repo.
// Keep only one compact version per session, never the search transcripts.
const syncedReceipts = new WeakMap();
const receiptKey = (workspaceID, sessionID) => JSON.stringify([workspaceID, sessionID]);
const documentVersion = doc => Array.from(doc.version().encode()).join(',');

function confirmedMarker(repo, workspaceID, sessionID, version) {
  const receipt = syncedReceipts.get(repo)?.get(receiptKey(workspaceID, sessionID));
  return receipt?.version === version ? receipt.timestamp : null;
}

function rememberMarker(repo, workspaceID, sessionID, version, timestamp) {
  let receipts = syncedReceipts.get(repo);
  if (!receipts) syncedReceipts.set(repo, receipts = new Map());
  const key = receiptKey(workspaceID, sessionID);
  receipts.set(key, { version, timestamp });
}

const messageTimestamp = metadata => Number.isFinite(metadata?.meta?.lastMessageAt)
  ? metadata.meta.lastMessageAt : null;

// Metadata and history travel independently. Do not consume the comparison
// baseline until a document pull is bracketed by the same activity marker.
async function syncStableHistory(repo, docID, metadata, signal) {
  for (let attempt = 0; attempt < 5; attempt++) {
    signal.throwIfAborted();
    const timestamp = messageTimestamp(metadata);
    const report = await repo.sync({ scope: 'doc', docIds: [docID], requireTransports: ['cloud'], signal });
    signal.throwIfAborted();
    if (!report.ok) throw new Error('Session history sync failed');
    metadata = await repo.getDocMeta(docID);
    signal.throwIfAborted();
    if (metadata?.deleted) throw new Error('Session was removed');
    if (messageTimestamp(metadata) === timestamp) return metadata;
  }
  // Let the existing retry/reconnect path handle sustained activity rather
  // than publishing an unverified marker or spinning without a bound.
  throw new Error('Session activity changed during history sync');
}

// Search preloads establish sync evidence without authoring a read receipt.
export async function readSyncedConversation({ repo, workspaceID, sessionID, doc, signal }) {
  signal.throwIfAborted();
  const baseline = projectConversation(sessionID, doc.getList('history').toJSON());
  const metadata = await repo.getDocMeta(`session-${sessionID}`);
  signal.throwIfAborted();
  const syncedMetadata = await syncStableHistory(repo, `session-${sessionID}`, metadata, signal);
  const timestamp = messageTimestamp(syncedMetadata);
  const next = projectConversation(sessionID, doc.getList('history').toJSON());
  if (Number.isFinite(timestamp) && hasVisibleConversationChange(baseline, next)) {
    rememberMarker(repo, workspaceID, sessionID, documentVersion(doc), timestamp);
  }
  return next;
}

export function conversationPatch(previous, next) {
  const old = new Map(previous?.turns.map(turn => [turn.id, turn]) ?? []);
  return {
    sessionID: next.sessionID,
    order: next.turns.map(turn => turn.id),
    changed: next.turns.filter(turn => {
      const before = old.get(turn.id);
      return !before || before.text !== turn.text || before.author !== turn.author ||
        JSON.stringify(before.parts ?? []) !== JSON.stringify(turn.parts ?? []);
    }),
    permission: next.permission,
    latestTurnNumber: next.latestTurnNumber,
    ...(!previous || (previous.subtasks !== next.subtasks &&
      JSON.stringify(previous.subtasks ?? []) !== JSON.stringify(next.subtasks ?? []))
      ? { replacesSubtasks: true, subtasks: next.subtasks ?? [] } : {}),
    ...(!previous || (previous.fileChanges !== next.fileChanges &&
      JSON.stringify(previous.fileChanges ?? null) !== JSON.stringify(next.fileChanges ?? null))
      ? { replacesFileChanges: true, fileChanges: next.fileChanges ?? null } : {}),
  };
}

function hasVisibleConversationChange(previous, next) {
  if (!previous) return next.turns.length > 0;
  const patch = conversationPatch(previous, next);
  return patch.changed.length > 0 || patch.replacesFileChanges === true ||
    patch.order.length !== previous.turns.length ||
    patch.order.some((id, index) => id !== previous.turns[index].id);
}

async function watchCapabilities({ repo, workspaceID, meta, own, isStopped, changed }) {
  const { machineId, agentConfigId } = meta;
  if (typeof workspaceID !== 'string' || typeof machineId !== 'string' || !machineId ||
      typeof agentConfigId !== 'string' || !agentConfigId) return undefined;
  try {
    const handle = await repo.openFlockDoc(`${workspaceID}:mf:${machineId}`);
    if (isStopped()) return undefined;
    own(handle.flock.subscribe(changed));
    // Capabilities only affect the run-config picker; they never gate the transcript.
    handle.joinRoom().then(room => own(() => room.unsubscribe()), () => {});
    return () => handle.flock.get(['acpCapability', agentConfigId]);
  } catch {
    return undefined;
  }
}

// The setup promise finishes after joining. The signal owns the lasting leases.
export async function observeConversation({ repo, workspaceID, sessionID, signal, emit, schedule = setTimeout, unschedule = clearTimeout }) {
  const cleanup = [];
  let timer;
  let previous;
  let publishing = false;
  let dirty = false;
  let stopped = signal.aborted;
  let ready = false;
  let historyChanged = true;
  let subtasksChanged = true;
  let subtasks = [];
  let syncedMessageAt = null;
  let receiptConversation;
  const rooms = [];
  const stop = () => {
    stopped = true;
    unschedule(timer);
    for (const dispose of cleanup.splice(0).reverse()) dispose();
    signal.removeEventListener('abort', stop);
  };
  signal.addEventListener('abort', stop, { once: true });
  const own = dispose => { if (stopped) dispose(); else cleanup.push(dispose); };
  try {
    const docID = `session-${sessionID}`;
    const metadata = await repo.getDocMeta(docID);
    if (stopped) return;
    if (!metadata || metadata.deleted) throw new Error('Session is missing from this workspace');
    const handle = await repo.openPersistedDoc(docID);
    if (stopped) return;
    receiptConversation = projectConversation(sessionID, handle.doc.getList('history').toJSON());
    syncedMessageAt = confirmedMarker(repo, workspaceID, sessionID, documentVersion(handle.doc));
    let latestTurn;
    let capability;
    const publish = async () => {
      timer = undefined;
      if (stopped) return;
      if (publishing) { dirty = true; return; }
      publishing = true;
      dirty = false;
      try {
        let meta = await repo.getDocMeta(docID);
        if (stopped) return;
        if (!meta || meta.deleted) throw new Error('Session was removed');
        let lastMessageAt = messageTimestamp(meta);
        if (lastMessageAt !== null && lastMessageAt !== syncedMessageAt) {
          meta = await syncStableHistory(repo, docID, meta, signal);
          if (stopped) return;
          if (!meta || meta.deleted) throw new Error('Session was removed');
          lastMessageAt = messageTimestamp(meta);
          historyChanged = true;
        }
        let next = previous;
        if (historyChanged || !previous) {
          const entries = handle.doc.getList('history').toJSON();
          next = projectConversation(sessionID, entries);
          latestTurn = latestUserTurn(entries);
        }
        const projectedVersion = documentVersion(handle.doc);
        historyChanged = false;
        if (subtasksChanged) {
          subtasksChanged = false;
          subtasks = projectSubtasks(sessionID, await repo.listDoc());
          if (stopped) return;
        }
        next = { ...next, subtasks };
        const update = conversationPatch(previous, next);
        // A synced marker alone does not show that its new content reached the UI.
        if (lastMessageAt === null) {
          syncedMessageAt = null;
          receiptConversation = next;
        } else if (lastMessageAt !== syncedMessageAt &&
                   hasVisibleConversationChange(receiptConversation, next)) {
          syncedMessageAt = lastMessageAt;
          receiptConversation = next;
        }
        update.activity = projectSessionActivity(meta.meta.status);
        update.lastMessageAt = lastMessageAt === syncedMessageAt ? syncedMessageAt : null;
        const usage = meta.meta.contextWindowUsage;
        update.contextWindowUsage = usage && Number.isSafeInteger(usage.size) && usage.size > 0 &&
          Number.isSafeInteger(usage.used) && usage.used >= 0
          ? { size: usage.size, used: usage.used } : null;
        update.runConfig = projectRunConfig({
          cliType: meta.meta.cliType, agentType: meta.meta.agentType,
          capability: capability?.(), turn: latestTurn,
          runtimeConfig: handle.doc.getMap('acpRuntimeConfig').toJSON(),
        });
        update.syncState = rooms.length === 2 && rooms.every(room => room.status === 'joined') ? 'live' : 'connecting';
        await emit(update);
        if (stopped) return;
        if (update.lastMessageAt !== null) {
          rememberMarker(repo, workspaceID, sessionID, projectedVersion, update.lastMessageAt);
        }
        previous = next;
      } catch {
        if (!stopped) {
          try { await emit({ error: 'Conversation sync failed' }); } finally { stop(); }
        }
      } finally {
        publishing = false;
        if (dirty && !stopped) queue();
      }
    };
    const queue = () => {
      if (ready && !stopped && timer === undefined) timer = schedule(() => { void publish(); }, 80);
    };
    own(handle.doc.subscribe(() => { historyChanged = true; queue(); }));
    capability = await watchCapabilities({
      repo, workspaceID, meta: metadata.meta, own, isStopped: () => stopped, changed: queue,
    });
    if (stopped) return;
    const watch = repo.watch(() => { subtasksChanged = true; queue(); }, {
      kinds: ['doc-metadata', 'doc-existence-changed'],
    });
    own(() => watch.unsubscribe());
    for (const join of [() => handle.joinRoom(), () => repo.joinMetaRoom()]) {
      const room = await join();
      own(() => room.unsubscribe());
      if (stopped) return;
      rooms.push(room);
      own(room.onStatusChange(queue));
    }
    for (const room of rooms) {
      const result = await room.waitFor({ phase: 'restored', timeoutMs: 30_000, signal });
      if (stopped) return;
      if (result.status !== 'complete') throw new Error('Initial conversation sync failed');
    }
    ready = true;
    await publish();
  } catch (error) { stop(); throw error; }
}
