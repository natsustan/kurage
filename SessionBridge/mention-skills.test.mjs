import assert from 'node:assert/strict';
import test from 'node:test';
import { mentionSkills, selectMentionSkills } from './mention-skills.mjs';

test('skill candidates use the selected provider directories and project path precedence', () => {
  const project = { groups: [{ scope: 'project', dir: '.agents/skills', skills: [
    { name: 'review', relativePath: '.agents/skills/review/SKILL.md', description: 'Review changes' },
  ] }] };
  const global = { groups: [
    { scope: 'global', dir: '~/.agents/skills', skills: [
      { name: 'review', relativePath: 'review/SKILL.md', absolutePath: '/home/me/.agents/skills/review/SKILL.md' },
      { name: 'global-only', relativePath: 'global-only/SKILL.md', absolutePath: '/home/me/.agents/skills/global-only/SKILL.md' },
    ] },
    { scope: 'global', dir: '~/.claude/skills', skills: [
      { name: 'claude-only', relativePath: 'claude-only/SKILL.md' },
    ] },
  ] };
  assert.deepEqual(selectMentionSkills([project, global], 'codex').map(({ token, path }) => [token, path]), [
    ['global-only', '/home/me/.agents/skills/global-only/SKILL.md'],
    ['review', '.agents/skills/review/SKILL.md'],
  ]);
});

test('local skill discovery sends workspace-bound project and global requests', async () => {
  const calls = [];
  const skills = await mentionSkills({
    workspaceID: 'workspace-1', machineID: 'machine-1', localProjectID: 'project-1',
    userID: 'user-1', agentType: 'codex', gatewayBaseURL: 'https://gateway.example',
    auth: async () => 'unused', signal: new AbortController().signal,
    requestControl: async (_access, workspaceID, machineID, request) => {
      calls.push({ workspaceID, machineID, request });
      return { ok: true, type: request.type, result: { groups: [] } };
    },
  });
  assert.deepEqual(skills, []);
  assert.deepEqual(calls.map(({ request }) => request.type), [
    'local-project/list-skills', 'local-project/list-global-skills',
  ]);
  assert(calls.every(({ workspaceID, machineID, request }) =>
    workspaceID === 'workspace-1' && machineID === 'machine-1' &&
    request.workspaceId === 'workspace-1' && request.machineId === 'machine-1' &&
    request.requestedByUserId === 'user-1'));
  assert(calls[0].request.skillDirs.includes('.agents/skills'));
});
