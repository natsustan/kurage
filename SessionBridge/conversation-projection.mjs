import { projectFileChanges } from './file-changes.mjs';
import { projectAssistantBlocks } from './conversation-work.mjs';

// Project ordinary chat text, session images, and file metadata. Tool calls are
// summarized as explicit activity parts; thoughts and other item types need
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

export function projectConversation(sessionID, history) {
  const turns = [];
  const fileChanges = projectFileChanges(history);
  const changedTurnIDs = new Set(fileChanges.map(group => group.id));
  const latestTurnNumber = Math.max(1, history.filter(entry => entry?.role === 'user').length);
  for (const entry of history) {
    if (entry?.role !== 'user' && entry?.role !== 'assistant') continue;
    if (typeof entry.id !== 'string') continue;
    const { parts, work } = entry.role === 'assistant'
      ? projectAssistantBlocks(entry, projectItemParts)
      : { parts: (Array.isArray(entry.items) ? entry.items : []).flatMap(projectItemParts) };
    if (parts.length === 0 && !changedTurnIDs.has(entry.id)) continue;
    const text = parts
      .filter((part) => part.type === 'text')
      .map((part) => part.text)
      .join('\n\n');
    turns.push({
      id: entry.id,
      author: entry.role === 'user' ? 'user' : 'agent',
      text,
      parts,
      ...(work ? { work } : {}),
    });
  }
  return { sessionID, turns, latestTurnNumber, permission: null, ...(fileChanges.length ? { fileChanges } : {}) };
}
