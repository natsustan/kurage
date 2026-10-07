import { projectSessionActivity } from './session-activity.mjs';

const FRESH_MS = 30_000;
const MAX_MACHINES = 16;
const MAX_BASELINES = 64;
const MACHINE_PREFIXES = [['agentConfig'], ['acpCapability'], ['localProject'], ['cmd', 'deleteLocalProject']];
const copy = value => JSON.parse(JSON.stringify(value));

// Only cache configuration, never transcripts or transport handles. The owner
// is one workspace replica; sign-out and workspace replacement release it.
export function createSessionOptionsCache(now = Date.now) {
  const machines = new Map();
  const baselines = new Map();
  const remember = (entries, key, value, limit) => {
    entries.delete(key);
    entries.set(key, { ...value, savedAt: now() });
    while (entries.size > limit) entries.delete(entries.keys().next().value);
  };
  const touch = (entries, key) => {
    const entry = entries.get(key);
    if (entry) { entries.delete(key); entries.set(key, entry); }
    return entry;
  };
  const marker = row => {
    const meta = row?.meta;
    if (!meta || row.deleted || !Number.isFinite(meta.lastMessageAt) ||
        projectSessionActivity(meta.status) !== 'idle' ||
        (meta.latestUserMsgId && meta.latestUserMsgId !== meta.lastHandledUserMsgId)) return undefined;
    return JSON.stringify([meta.machineId, meta.agentConfigId, meta.cliType, meta.agentType,
      meta.lastMessageAt, meta.latestUserMsgId, meta.lastHandledUserMsgId, meta.lastCanceledTurn]);
  };
  const rememberMachine = (id, flock) => {
    const rows = MACHINE_PREFIXES.flatMap(prefix => Array.from(flock.scan({ prefix }), ({ key, value }) => ({ key, value })));
    remember(machines, id, { rows: copy(rows) }, MAX_MACHINES);
  };
  return {
    rememberMachine,
    clear: () => { machines.clear(); baselines.clear(); },
    reader({ refresh = false, isObserved = () => false, allowStale = true } = {}) {
      const reader = {
        needsRefresh: false,
        usedCache: false,
        machine(id) {
          const entry = !refresh && touch(machines, id);
          if (!entry || (!allowStale && now() - entry.savedAt >= FRESH_MS)) return undefined;
          reader.usedCache = true;
          if (now() - entry.savedAt >= FRESH_MS) reader.needsRefresh = true;
          // A read-only projection cannot inherit a live room's auth or cursor.
          return {
            get: key => entry.rows.find(row => JSON.stringify(row.key) === JSON.stringify(key))?.value,
            scan: ({ prefix }) => entry.rows.filter(row => prefix.every((part, index) => row.key?.[index] === part)),
          };
        },
        rememberMachine,
        baseline(id, row) {
          const stamp = marker(row);
          const entry = !refresh && !isObserved(id) && touch(baselines, id);
          if (!entry || stamp === undefined || entry.marker !== stamp ||
              (!allowStale && now() - entry.savedAt >= FRESH_MS)) return undefined;
          reader.usedCache = true;
          if (now() - entry.savedAt >= FRESH_MS) reader.needsRefresh = true;
          return copy(entry.baseline);
        },
        rememberBaseline(id, before, after, baseline) {
          const stamp = marker(before);
          if (stamp !== undefined && stamp === marker(after)) {
            remember(baselines, id, { marker: stamp, baseline: copy(baseline) }, MAX_BASELINES);
          }
        },
      };
      return reader;
    },
  };
}
