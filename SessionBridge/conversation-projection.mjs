import { projectQuestions } from './conversation-questions.mjs';
import { projectSubtasks } from './conversation-subtasks.mjs';
import { projectFileChanges } from './file-changes.mjs';
import { projectAssistantBlocks } from './conversation-work.mjs';
import { deliveryOutcome } from './conversation-delivery.mjs';

// Project ordinary chat text, session images, and file metadata. Tool calls are
// summarized as explicit activity parts; chat failures have their own error
// parts. Thoughts and other item types need
// their own UI, and rendering them as prose would misrepresent them.
const IMAGE_MIME_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

function visibleText(value) {
  return typeof value === 'string' && value.trim().length > 0 ? value : undefined;
}

function isImageReference(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function optionalFileName(value) {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 200 || trimmed.includes('\0')) return undefined;
  return trimmed;
}

function optionalDimension(value) {
  return Number.isInteger(value) && value > 0 && value <= 32768 ? value : undefined;
}

function projectImage(item) {
  if (!isImageReference(item?.imageId) ||
      (item.mimeType != null && !IMAGE_MIME_TYPES.has(item.mimeType))) return undefined;
  if (item.sizeBytes != null &&
      (!Number.isInteger(item.sizeBytes) || item.sizeBytes <= 0 || item.sizeBytes > MAX_IMAGE_BYTES)) {
    return undefined;
  }
  const image = { type: 'image', imageID: item.imageId };
  if (item.mimeType) image.mimeType = item.mimeType;
  const fileName = optionalFileName(item.fileName);
  if (fileName) image.fileName = fileName;
  if (isImageReference(item.storageSessionId)) image.storageSessionID = item.storageSessionId;
  const width = optionalDimension(item.width);
  const height = optionalDimension(item.height);
  if (width) image.width = width;
  if (height) image.height = height;
  return image;
}

function projectItemParts(item) {
  if (item?.type === 'file' && isImageReference(item.fileId) && Number.isInteger(item.sizeBytes) && item.sizeBytes > 0) {
    const fileName = typeof item.fileName === 'string'
      ? item.fileName.replaceAll('\0', '').trim().slice(0, 200) : '';
    return [{ type: 'file', fileID: item.fileId, fileName: fileName || 'File', sizeBytes: item.sizeBytes }];
  }
  if (item?.type === 'text') {
    const text = visibleText(item.text);
    return text ? [{ type: 'text', text }] : [];
  }
  if (item?.type === 'image') {
    const image = projectImage(item);
    return image ? [image] : [];
  }
  if (item?.type === 'image_group' && Array.isArray(item.images)) {
    return item.images.map(projectImage).filter(Boolean);
  }
  return [];
}

// Lody persists agent failures as chat_failed system notices, not chat text.
// Preserve the raw message for inspection/copying; never expose arbitrary meta.
function projectErrorParts(item, index) {
  if (item?.type !== 'system_notice' || item.name !== 'chat_failed') return [];
  const error = { type: 'error', id: `notice-${index}` };
  for (const field of ['reason', 'code', 'message']) {
    const value = visibleText(item.meta?.[field]);
    if (value) error[field] = value;
  }
  return [error];
}

function projectAssistantItemParts(item, index) {
  const errors = projectErrorParts(item, index);
  return errors.length ? errors : projectItemParts(item);
}

export function projectConversation(sessionID, history, meta = {}) {
  const turns = [];
  const questions = projectQuestions(history);
  const fileChanges = projectFileChanges(history);
  const changedTurnIDs = new Set(fileChanges.map(group => group.id));
  const latestTurnNumber = Math.max(1, history.filter(entry => entry?.role === 'user').length);
  for (const entry of history) {
    if (!['user', 'assistant', 'system'].includes(entry?.role)) continue;
    if (typeof entry.id !== 'string') continue;
    const { parts, work } = entry.role === 'assistant'
      ? projectAssistantBlocks(entry, projectAssistantItemParts)
      : { parts: (Array.isArray(entry.items) ? entry.items : [])
        .flatMap(entry.role === 'system' ? projectErrorParts : projectItemParts) };
    const live = entry === history.at(-1) && entry.role === 'assistant' &&
      entry.finished !== true && entry.endedAt == null;
    const startedAtMs = typeof entry.timestamp === 'string' ? Date.parse(entry.timestamp) : NaN;
    const timing = live ? {
      ...(Number.isFinite(startedAtMs) ? { startedAtMs } : {}),
      permissionWaitMs: Number.isFinite(entry.permissionWaitMs) && entry.permissionWaitMs > 0
        ? entry.permissionWaitMs : 0,
    } : undefined;
    if (parts.length === 0 && !changedTurnIDs.has(entry.id) && !timing) continue;
    const text = parts
      .filter((part) => part.type === 'text')
      .map((part) => part.text)
      .join('\n\n');
    turns.push({
      id: entry.id,
      author: entry.role === 'user' ? 'user' : 'agent',
      text,
      parts,
      ...(deliveryOutcome(entry, meta) === 'sent' ? { isDeliveryConfirmed: true } : {}),
      ...(deliveryOutcome(entry, meta) === 'rejected' ? { isDeliveryRejected: true } : {}),
      ...(work ? { work } : {}),
      ...(timing ? { timing } : {}),
    });
  }
  return { sessionID, turns, latestTurnNumber, subtasks: projectSubtasks(history), permission: null, ...(questions.length ? { questions } : {}), ...(fileChanges.length ? { fileChanges } : {}) };
}
