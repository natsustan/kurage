// Project ordinary chat text and session images. Tool results, thoughts, files,
// and other item types need their own UI; rendering them as prose would
// misrepresent them.
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
  if (!isImageReference(item?.imageId) || !IMAGE_MIME_TYPES.has(item.mimeType)) return undefined;
  if (item.sizeBytes != null &&
      (!Number.isInteger(item.sizeBytes) || item.sizeBytes <= 0 || item.sizeBytes > MAX_IMAGE_BYTES)) {
    return undefined;
  }
  const image = { type: 'image', imageID: item.imageId, mimeType: item.mimeType };
  const fileName = optionalFileName(item.fileName);
  if (fileName) image.fileName = fileName;
  if (isImageReference(item.storageSessionId)) image.storageSessionID = item.storageSessionId;
  const width = optionalDimension(item.width);
  const height = optionalDimension(item.height);
  if (width) image.width = width;
  if (height) image.height = height;
  return image;
}

function projectParts(items) {
  const parts = [];
  for (const item of items) {
    if (item?.type === 'text') {
      const text = visibleText(item.text);
      if (text) parts.push({ type: 'text', text });
      continue;
    }
    if (item?.type === 'image') {
      const image = projectImage(item);
      if (image) parts.push(image);
      continue;
    }
    if (item?.type === 'image_group' && Array.isArray(item.images)) {
      for (const image of item.images) {
        const projected = projectImage(image);
        if (projected) parts.push(projected);
      }
    }
  }
  return parts;
}

export function projectConversation(sessionID, history) {
  const turns = [];
  for (const entry of history) {
    if (entry?.role !== 'user' && entry?.role !== 'assistant') continue;
    if (typeof entry.id !== 'string' || !Array.isArray(entry.items)) continue;
    const parts = projectParts(entry.items);
    if (parts.length === 0) continue;
    const text = parts
      .filter((part) => part.type === 'text')
      .map((part) => part.text)
      .join('\n\n');
    turns.push({
      id: entry.id,
      author: entry.role === 'user' ? 'user' : 'agent',
      text,
      parts,
    });
  }
  return { sessionID, turns, permission: null };
}
