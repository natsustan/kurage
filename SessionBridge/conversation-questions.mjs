// Protocol reference: Lody shared/acp/ask-user-question.ts and history-writer.ts.
import { isSessionTab } from './session-tabs.mjs';
import { canonical } from './conversation-send.mjs';

const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function parseQuestionMeta(meta) {
  let source, raw;
  if (meta?.lody?.elicitation?.version === 1) {
    source = 'lody'; raw = meta.lody.elicitation;
  } else if (record(meta?.claudeCode)) {
    source = 'claude'; raw = meta.claudeCode.askUserQuestion;
  } else {
    source = 'codex'; raw = meta?.codex?.requestUserInput;
  }
  if (!record(raw) || !Array.isArray(raw.questions) || !raw.questions.length) return null;
  const questions = [];
  for (const q of raw.questions) {
    if (!record(q) || typeof q.question !== 'string' || typeof q.header !== 'string' ||
        (source === 'codex' && typeof q.id !== 'string')) return null;
    const options = q.options ?? (source === 'codex' ? [] : null);
    if (!Array.isArray(options) || options.some(o => !record(o) || typeof o.label !== 'string')) return null;
    if (source === 'lody' && q.note !== undefined && (!record(q.note) ||
        typeof q.note.fieldId !== 'string' || !q.note.fieldId.trim() ||
        ['title', 'description'].some(k => q.note[k] !== undefined && typeof q.note[k] !== 'string') ||
        (q.note.isSecret !== undefined && typeof q.note.isSecret !== 'boolean'))) return null;
    questions.push({
      ...(source !== 'claude' && typeof q.id === 'string' ? { id: q.id } : {}),
      question: q.question, header: q.header,
      options: options.map(o => ({ label: o.label,
        ...(typeof o.description === 'string' ? { description: o.description } : {}),
        ...(typeof o.preview === 'string' ? { preview: o.preview } : {}),
      })),
      multiSelect: source !== 'codex' && q.multiSelect === true,
      allowCustomAnswer: source === 'claude' ? raw.allowCustomAnswer === true
        : source === 'codex' ? q.isOther === true || q.is_other === true || q.allowCustomAnswer === true
          : typeof q.allowCustomAnswer === 'boolean' ? q.allowCustomAnswer
            : raw.questions.some(question => question?.allowCustomAnswer === true),
      isSecret: source !== 'claude' && (q.isSecret === true || q.is_secret === true),
      ...(source === 'lody' && q.note ? { note: q.note } : {}),
    });
  }
  if (questions.some(q => q.note)) {
    const used = new Set(questions.map(q => q.id));
    if (used.size !== questions.length || questions.some(q => !q.id?.trim())) return null;
    for (const q of questions) if (q.note) {
      if (used.has(q.note.fieldId)) return null;
      used.add(q.note.fieldId);
    }
  }
  const keyed = questions.map((question, index) => {
    for (const field of ['id', 'question', 'header']) {
      const value = question[field];
      if (typeof value === 'string' && value.trim() &&
          questions.filter(other => other[field] === value).length === 1) {
        return { ...question, id: value };
      }
    }
    return { ...question, id: String(index) };
  });
  // Never expose ambiguous answer dictionaries to the native UI.
  if (new Set(keyed.map(q => q.id)).size !== keyed.length) return null;
  const deadline = source === 'lody' && Number.isFinite(raw.autoResolveAtEpochSeconds)
    ? raw.autoResolveAtEpochSeconds * 1000 : raw.autoResolveAt;
  return { source, questions: keyed,
    ...(source !== 'claude' && Number.isFinite(deadline) ? { autoResolveAt: deadline } : {}),
  };
}

function requestOptions(permission) {
  const options = Array.isArray(permission.options) ? permission.options.filter(o => typeof o?.optionId === 'string') : [];
  const answer = options.find(o => o.optionId === 'answer') ?? options.find(o => typeof o.kind === 'string' && o.kind.startsWith('allow')) ?? options[0];
  const skip = options.find(o => o.optionId !== answer?.optionId && /^(deny|reject)/.test(o.kind))
    ?? options.find(o => o.optionId !== answer?.optionId);
  return { answerOptionID: answer?.optionId, skipOptionID: skip?.optionId };
}

export function projectQuestions(history) {
  const result = [];
  for (const turn of history) {
    if (turn?.role !== 'assistant' || typeof turn.id !== 'string' || turn.finished === true || turn.endedAt != null) continue;
    for (const item of Array.isArray(turn.items) ? turn.items : []) {
      const permission = item?.type === 'tool_call' ? item.permissionRequest : null;
      if (!permission || permission.outcome || typeof permission.requestId !== 'string') continue;
      const meta = parseQuestionMeta(permission._meta);
      if (!meta) continue;
      result.push({ id: JSON.stringify([turn.id, permission.requestId]), turnID: turn.id,
        requestID: permission.requestId, ...meta, ...requestOptions(permission) });
    }
  }
  return result;
}

export function questionOutcome(permission, answers) {
  const meta = parseQuestionMeta(permission._meta);
  if (!meta) throw new Error('Question unavailable');
  const options = requestOptions(permission);
  const optionId = answers === null ? options.skipOptionID : options.answerOptionID;
  if (!optionId) throw new Error('Question action unavailable');
  if (answers === null) return { outcome: 'selected', optionId };
  if (!record(answers)) throw new Error('Invalid answers');
  const validated = Object.create(null);
  for (const q of meta.questions) {
    const value = answers[q.id];
    const values = Array.isArray(value) ? value : [value];
    if (!values.length || values.some(v => typeof v !== 'string' || !v.trim()) ||
        (!q.multiSelect && Array.isArray(value)) ||
        (!q.allowCustomAnswer && values.some(v => !q.options.some(o => o.label === v)))) {
      throw new Error('Invalid answer');
    }
    validated[q.id] = value;
    if (q.note && answers[q.note.fieldId] !== undefined) {
      if (typeof answers[q.note.fieldId] !== 'string') throw new Error('Invalid note');
      if (answers[q.note.fieldId].trim()) validated[q.note.fieldId] = answers[q.note.fieldId];
    }
  }
  const payload = meta.source === 'codex'
    ? { codex: { requestUserInput: { answers: Object.fromEntries(Object.entries(validated).map(([key, value]) => [key, { answers: Array.isArray(value) ? value : [value] }])) } } }
    : meta.source === 'lody' ? { lody: { elicitation: { version: 1, answers: validated } } }
      : { claudeCode: { askUserQuestion: { answers: validated } } };
  return { outcome: 'selected', optionId, _meta: payload };
}

const container = value => typeof value?.kind === 'function';
const field = (value, key) => container(value) ? value.get(key) : value?.[key];
// Preserve container identity wherever possible, including legacy inline JSON.
function setPath(value, path, replacement) {
  if (!path.length) return replacement;
  const [key, ...rest] = path;
  const child = field(value, key);
  const updated = setPath(child, rest, replacement);
  if (container(value)) {
    if (!container(child)) {
      if (value.kind() === 'Map') value.set(key, updated);
      else { value.delete(key, 1); value.insert(key, updated); }
    }
    return value;
  }
  const copy = Array.isArray(value) ? [...value] : { ...value };
  copy[key] = updated;
  return copy;
}

export async function respondQuestion(repo, sessionID, turnID, requestID, answers, signal) {
  const docID = `session-${sessionID}`;
  const sync = async scope => {
    signal?.throwIfAborted();
    const result = await repo.sync({ scope, ...(scope === 'doc' ? { docIds: [docID] } : {}), requireTransports: ['cloud'], signal });
    signal?.throwIfAborted();
    if (result.outcome !== 'synced') throw new Error('Question sync unconfirmed');
  };
  await sync('meta');
  const rows = await repo.listDoc();
  const row = await repo.getDocMeta(docID);
  if (!row || row.deleted || row.meta?.isArchived ||
      (row.meta?.parentSessionId && !isSessionTab(row, rows))) return 'unavailable';
  const { doc } = await repo.openPersistedDoc(docID);
  await sync('doc');
  await sync('meta');
  const current = await repo.getDocMeta(docID);
  signal?.throwIfAborted();
  if (!current || current.deleted || current.meta?.isArchived ||
      (current.meta?.parentSessionId && !isSessionTab(current, rows))) return 'unavailable';
  const history = doc.getList('history');
  const locate = () => {
    const entries = history.toJSON();
    const index = entries.findIndex(t => t.id === turnID && t.role === 'assistant');
    const turn = entries[index];
    const itemIndex = turn?.items?.findIndex(item => item.type === 'tool_call' && item.permissionRequest?.requestId === requestID) ?? -1;
    return { index, itemIndex, turn, permission: turn?.items?.[itemIndex]?.permissionRequest };
  };
  const target = locate();
  if (!target.permission) return 'unavailable';
  const outcome = questionOutcome(target.permission, answers);
  if (target.permission.outcome) return canonical(target.permission.outcome) === canonical(outcome) ? 'answered' : 'resolved';
  const meta = parseQuestionMeta(target.permission._meta);
  if (!['running', 'requestPermission'].includes(current.meta?.status?.type) || target.turn.finished === true ||
      target.turn.endedAt != null || (meta.autoResolveAt !== undefined && Date.now() >= meta.autoResolveAt)) return 'unavailable';
  signal?.throwIfAborted();
  setPath(history, [target.index, 'items', target.itemIndex, 'permissionRequest', 'outcome'], outcome);
  doc.commit();
  await sync('doc');
  return canonical(locate().permission?.outcome) === canonical(outcome) ? 'answered' : 'resolved';
}
