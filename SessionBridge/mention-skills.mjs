import { StreamsClient } from '@loro-dev/streams-client';
import skillDirs from './skill-dirs.json' with { type: 'json' };

// Lody's machine control requests travel through short-lived JSON Streams.
// Keep the response stream private to this request, including when a refresh
// is cancelled, so replies cannot leak into another workspace or account.
export async function control(repoAccess, workspaceID, machineID, request, signal) {
  const responseID = `${workspaceID}:rpc:res:${crypto.randomUUID()}`;
  const requestID = crypto.randomUUID();
  const stream = id => new StreamsClient({
    url: `${repoAccess.baseURL.replace(/\/+$/, '')}/ds/lody/${encodeURIComponent(id)}`,
    auth: repoAccess.auth,
    fetch: (input, init) => globalThis.fetch(input, {
      ...init, signal: init?.signal ? AbortSignal.any([init.signal, signal]) : signal,
    }),
  });
  const response = stream(responseID);
  const created = await response.create({ contentType: 'application/json', ttlSeconds: 86400 });
  if (!created.ok) throw new Error('Could not open a machine response stream');
  signal.throwIfAborted();

  const reply = (async () => {
    // This stream was just created for this call. Read from the beginning so a
    // fast machine reply cannot beat the first SSE connection.
    for await (const event of response.live({ offset: '-1', mode: 'sse', signal })) {
      if (event.type === 'error') throw new Error('Machine response stream failed');
      if (event.type !== 'data') continue;
      const messages = event.payload.json();
      for (const message of Array.isArray(messages) ? messages : [messages]) {
        if (message?.id !== requestID) continue;
        if (message.error) throw new Error(message.error.message ?? 'Skill request failed');
        return message.result;
      }
    }
    throw new Error('Machine response stream closed');
  })();

  const now = Date.now();
  const envelope = {
    jsonrpc: '2.0', id: requestID, method: 'local-project/control', rpcVersion: '1',
    machineId: machineID, workspaceId: workspaceID, replyTo: responseID,
    sentAt: now, expiresAt: now + 120000, params: { request },
  };
  try {
    const appended = await stream(`${workspaceID}:rpc:req:${machineID}`).append({
      part: { contentType: 'application/json', body: JSON.stringify(envelope) },
    });
    if (!appended.ok) throw new Error('Could not request machine skills');
    return await reply;
  } catch (error) {
    // The live read is stopped by the caller's abort signal. Consume its
    // rejection if appending failed before we began awaiting it.
    void reply.catch(() => {});
    throw error;
  }
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
