// Project only ordinary chat text. Tool results, thoughts, files, and future
// item types need dedicated UI; rendering them as prose would misrepresent them.
export function projectConversation(sessionID, history) {
  const turns = [];
  for (const entry of history) {
    if (entry?.role !== 'user' && entry?.role !== 'assistant') continue;
    if (typeof entry.id !== 'string' || !Array.isArray(entry.items)) continue;
    const text = entry.items
      .filter((item) => item?.type === 'text' && typeof item.text === 'string')
      .map((item) => item.text)
      .filter((part) => part.trim().length > 0)
      .join('\n\n');
    if (!text) continue;
    turns.push({ id: entry.id, author: entry.role === 'user' ? 'user' : 'agent', text });
  }
  return { sessionID, turns, permission: null };
}
