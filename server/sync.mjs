// SPDX-License-Identifier: GPL-3.0-or-later
import { createServer } from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import * as oidc from 'openid-client';
import { exchangeBackup, maximumRequest } from './backup.mjs';

const issuer = new URL('https://id.xcenter.it');
const origin = 'https://vorssaint.xcenter.it';
const base = '/auth/xcenter';
const redirect = origin + base + '/callback';
const transactionLifetime = 5 * 60_000;
const hex = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const clientIdentifier = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const random = () => randomBytes(32).toString('hex');
const cookieOptions = `Path=${base}; HttpOnly; Secure; SameSite=Lax`;
const expiredCookie = `vorssaint_login=; ${cookieOptions}; Max-Age=0`;

function answer(res, status, body) {
  if (body !== undefined) res.setHeader('Content-Type', 'application/json');
  res.writeHead(status).end(body === undefined ? undefined : JSON.stringify(body));
}

async function readJSON(req, limit) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw new RangeError();
  const buffers = [];
  let count = 0;
  for await (const bytes of req) {
    count += bytes.length;
    if (count > limit) throw new RangeError();
    buffers.push(bytes);
  }
  return JSON.parse(Buffer.concat(buffers));
}

class ExpiringEntries {
  #values = new Map();
  constructor(limit) { this.limit = limit; }
  get(key) {
    const entry = this.#values.get(key);
    if (!entry || entry.expires <= Date.now()) return undefined;
    return entry.value;
  }
  set(key, value, ttl) {
    for (const [id, entry] of this.#values) {
      if (entry.expires <= Date.now()) this.#values.delete(id);
    }
    if (this.#values.size >= this.limit) throw new Error('Capacity reached');
    this.#values.set(key, { value, expires: Date.now() + ttl });
  }
  delete(key) { this.#values.delete(key); }
}

function proves(transaction, proof) {
  return transaction && hex(proof) && timingSafeEqual(
    createHash('sha256').update(proof).digest(), Buffer.from(transaction.challenge, 'hex'));
}

function browserResult(res, success) {
  const title = success ? 'Return to Vorssaint' : 'Sign-in could not be completed';
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.writeHead(success ? 200 : 400).end(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><main><h1>${title}</h1><p>Close this tab and return to Vorssaint.</p></main></html>`);
}

export function createSyncServer({ clientID, clientSecret, discover = oidc.discovery, recordFetch = fetch } = {}) {
  const enabled = clientIdentifier(clientID) && !!clientSecret;
  const transactions = new ExpiringEntries(256);
  const launches = new ExpiringEntries(256);
  const sessions = new ExpiringEntries(2048);
  let configuration;

  async function config() {
    configuration ??= discover(issuer, clientID, undefined, oidc.ClientSecretBasic(clientSecret))
      .then(value => {
        const metadata = value.serverMetadata();
        for (const endpoint of [metadata.authorization_endpoint, metadata.token_endpoint,
          metadata.jwks_uri, metadata.userinfo_endpoint]) {
          if (!endpoint || new URL(endpoint).origin !== issuer.origin) throw new Error('Invalid issuer metadata');
        }
        oidc.enableNonRepudiationChecks(value);
        return value;
      }).catch(error => { configuration = undefined; throw error; });
    return configuration;
  }

  return createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
    res.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const url = new URL(req.url, origin);
      if (url.origin !== origin) return answer(res, 400);
      const path = url.pathname;
      const method = req.method;
      if (method === 'GET' && path === base + '/status') return answer(res, 200, { enabled });
      if (!path.startsWith(base + '/')) return answer(res, 404);
      if (!enabled) return answer(res, 503);
      if (method === 'POST' && req.headers.origin) return answer(res, 403);

      if (method === 'POST' && path === base + '/start') {
        const { challenge } = await readJSON(req, 1024);
        if (!hex(challenge)) return answer(res, 400);
        const state = random(), nonce = random(), launch = random();
        const verifier = oidc.randomPKCECodeVerifier();
        const authorization = oidc.buildAuthorizationUrl(await config(), {
          redirect_uri: redirect, response_type: 'code', scope: 'openid app_data',
          prompt: 'consent', state, nonce, code_challenge_method: 'S256',
          code_challenge: await oidc.calculatePKCECodeChallenge(verifier),
        });
        transactions.set(state, { challenge, nonce, verifier }, transactionLifetime);
        launches.set(launch, { state, authorization }, transactionLifetime);
        return answer(res, 201, { transaction: state, url: origin + base + '/browser?launch=' + launch });
      }

      if (method === 'GET' && path === base + '/browser') {
        const handle = url.searchParams.get('launch');
        const pending = hex(handle) && launches.get(handle);
        if (!pending || !transactions.get(pending.state)) return answer(res, 410);
        launches.delete(handle);
        res.setHeader('Set-Cookie', `vorssaint_login=${pending.state}; ${cookieOptions}; Max-Age=300`);
        return res.writeHead(303, { Location: pending.authorization.href }).end();
      }

      if (method === 'GET' && path === base + '/callback') {
        const state = url.searchParams.get('state');
        const cookie = /(?:^|; )vorssaint_login=([a-f0-9]{64})(?:;|$)/.exec(req.headers.cookie ?? '')?.[1];
        const pending = hex(state) && state === cookie && transactions.get(state);
        res.setHeader('Set-Cookie', expiredCookie);
        if (!pending || pending.consumed) return browserResult(res, false);
        pending.consumed = true;
        try {
          const configuration = await config();
          const tokens = await oidc.authorizationCodeGrant(configuration, new URL(redirect + url.search), {
            pkceCodeVerifier: pending.verifier, expectedState: state, expectedNonce: pending.nonce,
            idTokenExpected: true,
          });
          const subject = tokens.claims()?.sub;
          const grants = new Set(tokens.scope?.split(' '));
          if (!subject || !grants.has('app_data')) throw new Error('Storage permission needed');
          await oidc.fetchUserInfo(configuration, tokens.access_token, subject);
          if (transactions.get(state) !== pending) return browserResult(res, false);
          const lifetime = Math.min((tokens.expires_in ?? 300) * 1000, 1_800_000);
          pending.session = { accessToken: tokens.access_token, expires: Date.now() + lifetime };
          return browserResult(res, true);
        } catch {
          pending.denied = true;
          return browserResult(res, false);
        }
      }

      if (method === 'POST' && (path === base + '/pickup' || path === base + '/cancel')) {
        const { transaction, proof } = await readJSON(req, 1024);
        const pending = hex(transaction) && transactions.get(transaction);
        if (!proves(pending, proof)) return answer(res, 404);
        if (path.endsWith('/cancel')) {
          transactions.delete(transaction);
          return answer(res, 204);
        }
        if (pending.denied) return answer(res, 403);
        if (!pending.session) return answer(res, 202);
        const lifetime = pending.session.expires - Date.now();
        if (lifetime <= 0) return answer(res, 410);
        const session = random();
        sessions.set(session, pending.session, lifetime);
        transactions.delete(transaction);
        return answer(res, 200, { session, expiresIn: Math.floor(lifetime / 1000) });
      }

      const key = /^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization ?? '')?.[1];
      if (method === 'POST' && path === base + '/signout') {
        if (key) sessions.delete(key);
        return answer(res, 204);
      }

      if (path === base + '/backup' && ['GET', 'HEAD', 'PUT', 'DELETE'].includes(method)) {
        const session = key && sessions.get(key);
        if (!session) return answer(res, 401);
        if (req.headers.origin) return answer(res, 403);
        const input = method === 'PUT' ? await readJSON(req, maximumRequest) : undefined;
        const result = await exchangeBackup({ method, revision: req.headers['if-match'], input,
          recordFetch, clientID, accessToken: session.accessToken, issuer });
        if (result.revision) res.setHeader('ETag', result.revision);
        return answer(res, result.status, result.body);
      }

      if (path === base + '/mouse-profiles' && ['GET', 'PUT', 'DELETE'].includes(method)) {
        const session = key && sessions.get(key);
        if (!session) return answer(res, 401);
        const headers = { Authorization: 'Bearer ' + session.accessToken };
        if (method !== 'GET') {
          const revision = req.headers['if-match'];
          if (typeof revision !== 'string' || !/^"[0-9]{1,64}"$/.test(revision)) return answer(res, 400);
          headers['If-Match'] = revision;
        }
        let body;
        let uploaded;
        if (method === 'PUT') {
          const { data } = await readJSON(req, 60_000);
          if (!validSnapshot(data)) return answer(res, 400);
          uploaded = data;
          body = JSON.stringify({ data, public: false });
          headers['Content-Type'] = 'application/json';
        }
        const record = await recordFetch(new URL(`/v1/apps/${clientID}/data/preferences/mouse-profiles`, issuer), {
          method, headers, body, redirect: 'error', signal: AbortSignal.timeout(15_000),
        });
        if (!record.ok) return answer(res, record.status);
        if (method === 'DELETE') return answer(res, 204);
        const payload = await record.json();
        const revision = record.headers.get('etag') ?? (Number.isSafeInteger(payload.revision) ? `"${payload.revision}"` : '');
        const data = method === 'PUT' ? uploaded : payload.data;
        if (!/^"[0-9]{1,64}"$/.test(revision) || payload.public !== false || payload.shared === true || !validSnapshot(data)) {
          return answer(res, 502);
        }
        res.setHeader('ETag', revision);
        return answer(res, record.status, { data, public: false });
      }
      return answer(res, 404);
    } catch (error) {
      if (error instanceof SyntaxError || error instanceof RangeError) return answer(res, 400);
      return answer(res, 503);
    }
  });
}

function validSnapshot(data) {
  if (!data || data.version !== 1 || !data.mouseProfiles || Array.isArray(data.mouseProfiles)
    || typeof data.mouseProfiles !== 'object' || Object.keys(data).some(key => key !== 'version' && key !== 'mouseProfiles')) return false;
  const values = Object.entries(data.mouseProfiles);
  return values.length <= 256 && values.every(([id, value]) =>
    id.includes('.') && /^[A-Za-z0-9.-]{1,120}$/.test(id)
    && typeof value === 'string' && /^[a-z0-9,]{1,64}$/.test(value));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  createSyncServer({
    clientID: process.env.VORSSAINT_XCENTER_CLIENT_ID,
    clientSecret: process.env.VORSSAINT_XCENTER_CLIENT_SECRET,
  }).listen(Number(process.env.PORT ?? 8789), process.env.BIND_ADDRESS ?? '127.0.0.1');
}
