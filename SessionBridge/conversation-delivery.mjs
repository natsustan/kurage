// Missing-history recovery is a permanent negative ACK for this exact ID.
// History visibility, auto-read, and a producer pointer are not acceptance.
export function deliveryOutcome(entry, meta = {}) {
  if (entry?.role !== 'user') return undefined;
  if (meta.lastMissingHistoryUserMsgId === entry.id) return 'rejected';
  const steerStatus = meta.steerTurnStatuses?.[entry.id];
  if (entry.status === 'delivery_unknown' || steerStatus === 'delivery_unknown') return 'unconfirmed';
  if (meta.lastHandledUserMsgId === entry.id ||
      ['processing', 'handled', 'canceled', 'failed', 'completed', 'cancelled'].includes(entry.status) ||
      ['pending', 'processing', 'handled', 'failed', 'canceled'].includes(steerStatus)) return 'sent';
  return undefined;
}
