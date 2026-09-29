import test from 'node:test';
import assert from 'node:assert/strict';
import { LoroDoc, LoroMap, LoroList } from 'loro-crdt';
import { parseQuestionMeta, projectQuestions, questionOutcome, respondQuestion } from './conversation-questions.mjs';
import { conversationPatch } from './conversation-observer.mjs';
import { projectConversation } from './conversation-projection.mjs';
const json = value => JSON.parse(JSON.stringify(value));
const question = { id: 'q', question: 'Which session?', header: 'Session', options: [], allowCustomAnswer: true };
const permission = (source = 'lody') => ({ requestId: 'request', options: [
  { optionId: 'answer', kind: 'allow_once' }, { optionId: 'skip', kind: 'reject_once' },
], _meta: source === 'lody' ? { lody: { elicitation: { version: 1, questions: [question] } } }
  : source === 'codex' ? { codex: { requestUserInput: { questions: [question] } } }
    : { claudeCode: { askUserQuestion: { questions: [question], allowCustomAnswer: true } } } });
const turn = () => ({ id: 'turn', role: 'assistant', items: [{ type: 'tool_call', toolCallId: 'tool', permissionRequest: permission() }], untouched: 'keep' });
function populate(container, value) {
  for (const [key, child] of Object.entries(value)) {
    const k = Array.isArray(value) ? Number(key) : key;
    if (child && typeof child === 'object') {
      const nested = Array.isArray(child) ? new LoroList() : new LoroMap();
      populate(Array.isArray(value) ? container.insertContainer(k, nested) : container.setContainer(k, nested), child);
    } else if (Array.isArray(value)) container.insert(k, child);
    else container.set(k, child);
  }
}
function fixture(nested = false) {
  const doc = new LoroDoc(), history = doc.getList('history');
  if (nested) populate(history, [turn()]); else history.push(turn());
  doc.commit();
  const meta = { status: { type: 'requestPermission' } };
  const repo = {
    getDocMeta: async id => id === 'session-chat' ? { meta } : null,
    openPersistedDoc: async () => ({ doc }),
    sync: async () => ({ outcome: 'synced' }),
  };
  return { doc, history, repo, meta };
}
const send = (repo, answers = { q: 'session-a' }, signal) => respondQuestion(repo, 'chat', 'turn', 'request', answers, signal);

test('canonical, Codex and Claude use their answer namespaces and stable keys', () => {
  for (const source of ['lody', 'codex', 'claude']) {
    const p = permission(source), key = source === 'claude' ? question.question : 'q';
    assert.equal(parseQuestionMeta(p._meta).questions[0].id, key);
    const outcome = json(questionOutcome(p, { [key]: 'session-a' }));
    assert.equal(outcome.optionId, 'answer');
    if (source === 'lody') assert.deepEqual(outcome._meta.lody.elicitation, { version: 1, answers: { q: 'session-a' } });
    if (source === 'codex') assert.deepEqual(outcome._meta.codex.requestUserInput.answers, { q: { answers: ['session-a'] } });
    if (source === 'claude') assert.deepEqual(outcome._meta.claudeCode.askUserQuestion.answers, { [key]: 'session-a' });
    assert.deepEqual(questionOutcome(p, null), { outcome: 'selected', optionId: 'skip' });
  }
});
test('multi-select, custom answers, notes and secret fields follow metadata', () => {
  const p = permission();
  p._meta.lody.elicitation.questions = [{ ...question, multiSelect: true, allowCustomAnswer: false,
    isSecret: true, options: [{ label: 'A' }, { label: 'B', preview: 'example' }], note: { fieldId: 'note', isSecret: true } }];
  assert.equal(parseQuestionMeta(p._meta).questions[0].isSecret, true);
  assert.deepEqual(json(questionOutcome(p, { q: ['A', 'B'], note: 'extra' })._meta.lody.elicitation.answers), { q: ['A', 'B'], note: 'extra' });
  assert.throws(() => questionOutcome(p, { q: 'custom' }), /Invalid answer/);
  assert.throws(() => questionOutcome(p, { q: [] }), /Invalid answer/);
  p._meta.lody.elicitation.questions[0].note.fieldId = 'q';
  assert.equal(parseQuestionMeta(p._meta), null);
});
test('legacy repeated questions use unique headers, then indexes', () => {
  const p = permission('claude');
  p._meta.claudeCode.askUserQuestion.questions = [{ ...question, header: 'First' }, { ...question, header: 'Second' }];
  assert.deepEqual(parseQuestionMeta(p._meta).questions.map(q => q.id), ['First', 'Second']);
  p._meta.claudeCode.askUserQuestion.questions[1].header = 'First';
  assert.deepEqual(parseQuestionMeta(p._meta).questions.map(q => q.id), ['0', '1']);
});
test('patch clears resolved questions even with unchanged transcript text', () => {
  const history = [turn()], before = projectConversation('chat', history);
  assert.equal(before.questions.length, 1);
  history[0].items[0].permissionRequest.outcome = { outcome: 'selected', optionId: 'skip' };
  const patch = conversationPatch(before, projectConversation('chat', history));
  assert.deepEqual(patch.questions, []);
  assert.deepEqual(patch.changed, []);
  delete history[0].items[0].permissionRequest.outcome;
  history[0].finished = true;
  assert.deepEqual(projectQuestions(history), []);
});
for (const nested of [false, true]) test(`write only outcome, preserving identity and idempotent retries: nested=${nested}`, async () => {
  const { repo, history, doc } = fixture(nested), before = history.toJSON()[0];
  assert.equal(await send(repo), 'answered');
  const after = history.toJSON()[0], { outcome, ...request } = after.items[0].permissionRequest;
  assert.deepEqual(request, before.items[0].permissionRequest);
  assert.equal(after.untouched, 'keep');
  assert.equal(outcome._meta.lody.elicitation.answers.q, 'session-a');
  const version = Array.from(doc.version().encode());
  assert.equal(await send(repo), 'answered');
  assert.deepEqual(Array.from(doc.version().encode()), version);
  assert.equal(await send(repo, { q: 'changed' }), 'resolved');
});
test('another device response is preserved, including skip retries', async () => {
  const { repo, history } = fixture();
  assert.equal(await send(repo, null), 'answered');
  assert.equal(await send(repo), 'resolved');
  assert.equal(await send(repo, null), 'answered');
  assert.deepEqual(history.toJSON()[0].items[0].permissionRequest.outcome, { outcome: 'selected', optionId: 'skip' });
});
test('expired, finished, archived and foreign workspace requests cannot be authored', async () => {
  for (const reason of ['expired', 'finished', 'archived', 'idle', 'missing']) {
    const { repo, history, meta } = fixture(), t = turn();
    if (reason === 'expired') t.items[0].permissionRequest._meta.lody.elicitation.autoResolveAtEpochSeconds = 1;
    if (reason === 'finished') t.finished = true;
    if (reason === 'archived') meta.isArchived = true;
    if (reason === 'idle') meta.status.type = 'idle';
    if (reason === 'missing') repo.getDocMeta = async () => null;
    history.delete(0, 1); history.push(t);
    assert.equal(await send(repo), 'unavailable');
    assert.equal(history.toJSON()[0].items[0].permissionRequest.outcome, undefined);
  }
});
test('cancellation and failed initial sync cannot write; uncertain delivery retries the same outcome', async () => {
  const { repo, history, doc } = fixture(), abort = new AbortController(); abort.abort();
  await assert.rejects(send(repo, undefined, abort.signal), { name: 'AbortError' });
  assert.equal(history.toJSON()[0].items[0].permissionRequest.outcome, undefined);
  repo.sync = async () => ({ outcome: 'failed' });
  await assert.rejects(send(repo), /unconfirmed/);
  assert.equal(history.toJSON()[0].items[0].permissionRequest.outcome, undefined);
  repo.sync = async () => ({ outcome: history.toJSON()[0].items[0].permissionRequest.outcome ? 'failed' : 'synced' });
  await assert.rejects(send(repo), /unconfirmed/);
  const version = Array.from(doc.version().encode());
  repo.sync = async () => ({ outcome: 'synced' });
  assert.equal(await send(repo), 'answered');
  assert.deepEqual(Array.from(doc.version().encode()), version);
});


test('canonical unspecified custom-answer flags inherit the desktop metadata fallback', () => {
  const p = permission();
  p._meta.lody.elicitation.questions = [question, { ...question, id: 'other', allowCustomAnswer: undefined }];
  assert.equal(parseQuestionMeta(p._meta).questions[1].allowCustomAnswer, true);
  p._meta.lody.elicitation.questions[1].allowCustomAnswer = false;
  assert.equal(parseQuestionMeta(p._meta).questions[1].allowCustomAnswer, false);
  assert.deepEqual(projectQuestions([{ id: 'bad', role: 'assistant', items: {} }]), []);
});

test('status changes during history sync reject a now-stale question', async () => {
  const { repo, history, meta } = fixture();
  repo.sync = async ({ scope }) => {
    if (scope === 'doc') meta.status = { type: 'idle' };
    return { outcome: 'synced' };
  };
  assert.equal(await send(repo), 'unavailable');
  assert.equal(history.toJSON()[0].items[0].permissionRequest.outcome, undefined);
});

test('tab questions answer only the tab request', async () => {
  const { repo, meta, history } = fixture();
  meta.parentSessionId = 'root';
  assert.equal(await send(repo), 'answered');
  assert.equal(history.toJSON()[0].items[0].permissionRequest.outcome.optionId, 'answer');
});
