import { requestMachine } from './machine-rpc.mjs';
import skillDirs from './skill-dirs.json' with { type: 'json' };

// Local-project controls share the workspace-scoped machine RPC transport.
export function control(repoAccess, workspaceID, machineID, request, signal) {
  return requestMachine(repoAccess, workspaceID, machineID, 'local-project/control', { request }, signal);
}

export function selectMentionSkills(results, agentType) {
  if (!Object.hasOwn(skillDirs.agents, agentType)) return [];
  const mapping = skillDirs.agents[agentType];
  const allowed = new Set([
    ...mapping.projectDirs, ...mapping.globalDirs, ...mapping.systemDirs,
  ]);
  const seen = new Set();
  const skills = [];
  for (const group of results.flatMap(result => result.groups ?? [])) {
    if (![...allowed].some(dir => group.dir === dir || group.dir.startsWith(`${dir}/`))) continue;
    for (const skill of group.skills ?? []) {
      const name = skill.name?.trim() ?? '';
      const basename = skill.relativePath?.replace(/\/SKILL\.md$/i, '').split('/').at(-1) ?? '';
      const token = name && !/\s/.test(name) ? name : basename.replace(/\s+/g, '-');
      if (!token || seen.has(token)) continue;
      seen.add(token);
      skills.push({
        token, name: name || token, description: skill.description ?? '',
        path: group.scope === 'project' ? skill.relativePath : skill.absolutePath ?? skill.relativePath,
      });
    }
  }
  return skills.sort((a, b) => a.token.localeCompare(b.token));
}

export async function mentionSkills({ workspaceID, machineID, localProjectID, userID, agentType,
  gatewayBaseURL, auth, signal, requestControl = control }) {
  const access = { baseURL: gatewayBaseURL, auth };
  const base = { machineId: machineID, workspaceId: workspaceID, requestedByUserId: userID };
  const requests = [
    { ...base, type: 'local-project/list-global-skills' },
  ];
  if (localProjectID) requests.unshift({
    ...base, type: 'local-project/list-skills', localProjectId: localProjectID,
    skillDirs: skillDirs.projectDirs,
  });
  const responses = await Promise.all(requests.map(request =>
    requestControl(access, workspaceID, machineID, request, signal)));
  signal.throwIfAborted();
  for (const response of responses) {
    if (response?.ok !== true || response.type !== 'local-project/list-skills' &&
        response.type !== 'local-project/list-global-skills') {
      throw new Error(response?.message ?? 'Skill scan failed');
    }
  }
  return selectMentionSkills(responses.map(response => response.result), agentType);
}
