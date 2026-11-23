// SPDX-License-Identifier: GPL-3.0-or-later
import { createHash, randomUUID } from 'node:crypto';

const chunkSize = 48_000;
export const maximumArchive = 6 * 1024 * 1024;
export const maximumRequest = 4 * Math.ceil(maximumArchive / 3) + 1024;
const maxChunks = Math.ceil(maximumRequest / chunkSize);
const archiveID = 'advanced-backup';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const revisionHeader = revision => '"' + revision + '"';
const chunkID = (generation, index) => 'backup-' + generation + '-' + index;

function validManifest(value) {
  return value?.version === 1 && /^[a-f0-9-]{36}$/.test(value.generation)
    && Number.isInteger(value.count) && value.count >= 1 && value.count <= maxChunks
    && /^[a-f0-9]{64}$/.test(value.digest);
}

function archiveBytes(value) {
  if (typeof value !== 'string' || value.length > maximumRequest) return undefined;
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length > maximumArchive || bytes.toString('base64') !== value
      || bytes.subarray(0, 8).toString() !== 'bplist00') return undefined;
  return bytes;
}

async function inBatches(count, work) {
  const results = [];
  for (let offset = 0; offset < count; offset += 8) {
    const batch = Array.from({ length: Math.min(8, count - offset) }, (_, i) => work(offset + i));
    results.push(...await Promise.allSettled(batch));
  }
  return results;
}

export async function exchangeBackup({ method, revision, input, recordFetch, clientID, accessToken, issuer }) {
  if (['PUT', 'DELETE'].includes(method) && (typeof revision !== 'string' || !/^"[0-9]{1,64}"$/.test(revision))) {
    return { status: 400 };
  }
  const encoded = input?.archive;
  const bytes = method === 'PUT' ? archiveBytes(encoded) : undefined;
  if (method === 'PUT' && !bytes) return { status: 400 };

  async function record(id, verb, ifMatch, data) {
    const headers = { Authorization: 'Bearer ' + accessToken };
    if (ifMatch) headers['If-Match'] = ifMatch;
    if (data !== undefined) headers['Content-Type'] = 'application/json';
    return recordFetch(new URL(`/v1/apps/${clientID}/data/preferences/${id}`, issuer), {
      method: verb, headers, body: data === undefined ? undefined : JSON.stringify({ data, public: false }),
      redirect: 'error', signal: AbortSignal.timeout(15_000),
    });
  }

  async function cleanup(manifest) {
    await inBatches(manifest.count, i => record(chunkID(manifest.generation, i), 'DELETE', '"1"'));
  }

  const prior = await record(archiveID, 'GET');
  if (!prior.ok && prior.status !== 404) return { status: prior.status };
  let old;
  let currentRevision = '"0"';
  if (prior.ok) {
    const document = await prior.json();
    if (document.public !== false || document.shared === true
        || !Number.isSafeInteger(document.revision) || document.revision < 1) return { status: 502 };
    if (validManifest(document.data)) old = document.data;
    else if (document.data?.version !== 1 || document.data.deleted !== true) return { status: 502 };
    currentRevision = revisionHeader(document.revision);
  }

  if (method === 'HEAD') return old ? { status: 200, revision: currentRevision } : { status: 404 };

  if (method === 'GET') {
    if (!old) return { status: 404 };
    const parts = await inBatches(old.count, async i => {
      const result = await record(chunkID(old.generation, i), 'GET');
      if (!result.ok) return undefined;
      const item = await result.json();
      const piece = item.data?.part;
      if (item.public !== false || item.shared === true || typeof piece !== 'string'
          || piece.length === 0 || piece.length > chunkSize) return undefined;
      return piece;
    });
    if (parts.some(part => part.status !== 'fulfilled' || !part.value)) return { status: 409 };
    const archive = parts.map(part => part.value).join('');
    const decoded = archiveBytes(archive);
    if (!decoded || digest(decoded) !== old.digest) return { status: 502 };
    return { status: 200, body: { archive }, revision: currentRevision };
  }

  if (revision !== (old ? currentRevision : '"0"')) return { status: 409 };
  if (method === 'DELETE') {
    if (!old) return { status: 404 };
    const deletion = await record(archiveID, 'PUT', currentRevision, { version: 1, deleted: true });
    if (!deletion.ok) return { status: deletion.status };
    await cleanup(old);
    return { status: 204 };
  }

  const manifest = {
    version: 1, generation: randomUUID(), count: Math.ceil(encoded.length / chunkSize), digest: digest(bytes),
  };
  const writes = await inBatches(manifest.count, i => record(chunkID(manifest.generation, i), 'PUT', '"0"', {
    part: encoded.slice(i * chunkSize, (i + 1) * chunkSize),
  }));
  if (writes.some(write => write.status !== 'fulfilled' || !write.value.ok)) {
    await cleanup(manifest);
    const failure = writes.find(write => write.status === 'fulfilled' && !write.value.ok);
    return { status: failure?.value.status === 409 ? 507 : failure?.value.status ?? 502 };
  }
  // A timeout around the single commit request is ambiguous. Retain the
  // chunks in that case, since the issuer may already have published them.
  const committed = await record(archiveID, 'PUT', currentRevision, manifest);
  if (!committed.ok) {
    await cleanup(manifest);
    return { status: committed.status };
  }
  const document = await committed.json();
  if (!Number.isSafeInteger(document.revision) || document.revision < 1) return { status: 502 };
  if (old) await cleanup(old);
  return { status: 200, body: { archive: encoded }, revision: revisionHeader(document.revision) };
}
