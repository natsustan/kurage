import { projectConversation } from './conversation-projection.mjs';
import { projectSessionActivity } from './session-activity.mjs';
import { latestUserTurn, projectRunConfig } from './run-config.mjs';

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
  };
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
    let latestTurn;
    let capability;
    const publish = async () => {
      timer = undefined;
      if (stopped) return;
      if (publishing) { dirty = true; return; }
      publishing = true;
      dirty = false;
      try {
        const meta = await repo.getDocMeta(docID);
        if (stopped) return;
        if (!meta || meta.deleted) throw new Error('Session was removed');
        let next = previous;
        if (historyChanged || !previous) {
          const entries = handle.doc.getList('history').toJSON();
          next = projectConversation(sessionID, entries);
          latestTurn = latestUserTurn(entries);
        }
        historyChanged = false;
        const update = conversationPatch(previous, next);
        update.activity = projectSessionActivity(meta.meta.status);
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
    const watch = repo.watch(queue, {
      docIds: [docID], kinds: ['doc-metadata', 'doc-existence-changed'],
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
