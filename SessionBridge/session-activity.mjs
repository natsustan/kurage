export function projectSessionActivity(status) {
  return ['running', 'initializing', 'requestPermission'].includes(status?.type)
    ? 'running' : 'idle';
}
