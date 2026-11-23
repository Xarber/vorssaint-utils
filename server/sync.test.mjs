// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { once } from 'node:events';
import test from 'node:test';
import { SignJWT, exportJWK, generateKeyPair } from 'jose';
import * as oidc from 'openid-client';
import { createSyncServer } from './sync.mjs';

const clientID = 'fixture-client';
const issuer = 'https://id.xcenter.it';
const origin = 'https://vorssaint.xcenter.it';
const root = '/auth/xcenter';
const cook = response => response.headers.get('set-cookie').split(';')[0];

async function relay(options, context) {
  const server = createSyncServer(options).listen(0, '127.0.0.1');
  await once(server, 'listening');
  context.after(() => server.close());
  const host = 'http://127.0.0.1:' + server.address().port;
  return (path, options = {}) => fetch(host + root + path, { redirect: 'manual', ...options });
}

const post = json => ({
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(json),
});

async function fixture(context, recordFetch) {
  const keys = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(keys.publicKey), kid: 'fixture', alg: 'RS256' };
  let nonce;
  let expectedChallenge;
  const discover = async (issuerURL, id, _metadata, auth) => {
    assert.equal(issuerURL.href, issuer + '/');
    const config = new oidc.Configuration({
      issuer, authorization_endpoint: issuer + '/authorize',
      token_endpoint: issuer + '/token', jwks_uri: issuer + '/jwks',
      userinfo_endpoint: issuer + '/userinfo', id_token_signing_alg_values_supported: ['RS256'],
    }, id, { id_token_signed_response_alg: 'RS256' }, auth);
    config[oidc.customFetch] = async (url, options) => {
      const address = new URL(url);
      switch (address.pathname) {
        case '/token': {
          const fields = new URLSearchParams(options.body);
          const challenge = createHash('sha256').update(fields.get('code_verifier')).digest('base64url');
          assert.equal(challenge, expectedChallenge);
          assert.equal(fields.get('redirect_uri'), origin + root + '/callback');
          const token = await new SignJWT({ nonce })
            .setProtectedHeader({ alg: 'RS256', kid: 'fixture' }).setIssuer(issuer)
            .setAudience(clientID).setSubject('fixture-user').setIssuedAt().setExpirationTime('5m')
            .sign(keys.privateKey);
          return Response.json({ id_token: token, access_token: 'fixture-token', token_type: 'Bearer',
            expires_in: 300, scope: 'openid app_data' });
        }
        case '/jwks': return Response.json({ keys: [jwk] });
        case '/userinfo': return Response.json({ sub: 'fixture-user' });
        default: throw new Error('Unexpected endpoint in fixture');
      }
    };
    return config;
  };
  const request = await relay({ clientID, clientSecret: 'fixture-secret', discover, recordFetch }, context);
  const proof = randomBytes(32).toString('hex');
  const challenge = createHash('sha256').update(proof).digest('hex');
  const start = await request('/start', post({ challenge }));
  assert.equal(start.status, 201);
  const transaction = await start.json();
  const launch = new URL(transaction.url).search;
  const browser = await request('/browser' + launch);
  assert.equal(browser.status, 303);
  const auth = new URL(browser.headers.get('location')).searchParams;
  assert.equal(auth.get('state'), transaction.transaction);
  assert.equal(auth.get('scope'), 'openid app_data');
  assert.equal(auth.get('code_challenge_method'), 'S256');
  nonce = auth.get('nonce');
  expectedChallenge = auth.get('code_challenge');

  return {
    request,
    launch,
    pickup: { transaction: transaction.transaction, proof },
    callback: '/callback?' + new URLSearchParams({ state: transaction.transaction, code: 'fixture-code' }),
    cookie: cook(browser),
  };
}

test('settings sync is disabled without service credentials', async context => {
  const request = await relay({}, context);
  assert.deepEqual(await (await request('/status')).json(), { enabled: false });
  assert.equal((await request('/start', post({ challenge: '0'.repeat(64) }))).status, 503);
});

test('successful browser completion creates one proof-bound session', async context => {
  const { request, pickup, launch, callback, cookie } = await fixture(context);
  assert.equal((await request('/mouse-profiles')).status, 401);
  assert.equal((await request('/pickup', post(pickup))).status, 202);
  assert.equal((await request('/pickup', post({ ...pickup, proof: '0'.repeat(64) }))).status, 404);
  assert.equal((await request('/browser' + launch)).status, 410);
  assert.equal((await request(callback)).status, 400);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 200);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 400);
  const result = await request('/pickup', post(pickup));
  assert.equal(result.status, 200);
  const { session } = await result.json();
  assert.match(session, /^[a-f0-9]{64}$/);
  assert.equal((await request('/pickup', post(pickup))).status, 404);
  const auth = { Authorization: 'Bearer ' + session };
  assert.equal((await request('/mouse-profiles', { method: 'DELETE', headers: auth })).status, 400);
  assert.equal((await request('/signout', { method: 'POST', headers: auth })).status, 204);
  assert.equal((await request('/mouse-profiles', { headers: auth })).status, 401);
});

test('a bound cancellation prevents callback and session pickup', async context => {
  const { request, pickup, callback, cookie } = await fixture(context);
  assert.equal((await request('/cancel', post(pickup))).status, 204);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 400);
  assert.equal((await request('/pickup', post(pickup))).status, 404);
});

test('private records use the app-scoped token and match revisions', async context => {
  const data = { version: 1, mouseProfiles: { 'com.example.editor': 'inherited,reversed' } };
  const calls = [];
  const recordFetch = async (url, options) => {
    assert.equal(url.href, issuer + '/v1/apps/fixture-client/data/preferences/mouse-profiles');
    assert.equal(options.headers.Authorization, 'Bearer fixture-token');
    calls.push(options.method);
    if (options.method === 'GET') return Response.json({ data, public: false, revision: 1 });
    assert.equal(options.headers['If-Match'], '"1"');
    if (options.method === 'DELETE') return Response.json({ ok: true });
    assert.deepEqual(JSON.parse(options.body), { data, public: false });
    return Response.json({ revision: 2, public: false });
  };
  const { request, pickup, callback, cookie } = await fixture(context, recordFetch);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 200);
  const { session } = await (await request('/pickup', post(pickup))).json();
  const headers = { Authorization: 'Bearer ' + session };
  const get = await request('/mouse-profiles', { headers });
  assert.equal(get.headers.get('etag'), '"1"');
  assert.deepEqual(await get.json(), { data, public: false });
  const mutationHeaders = { ...headers, 'If-Match': '"1"', 'Content-Type': 'application/json' };
  const invalid = await request('/mouse-profiles', { method: 'PUT', headers: mutationHeaders,
    body: JSON.stringify({ data: { ...data, privatePath: '/Users/test' } }) });
  assert.equal(invalid.status, 400);
  const put = await request('/mouse-profiles', { method: 'PUT', headers: mutationHeaders, body: JSON.stringify({ data }) });
  assert.equal(put.headers.get('etag'), '"2"');
  assert.deepEqual(await put.json(), { data, public: false });
  assert.equal((await request('/mouse-profiles', { method: 'DELETE', headers: mutationHeaders })).status, 204);
  assert.deepEqual(calls, ['GET', 'PUT', 'DELETE']);
});

test('Advanced backups span private records and restore atomically', async context => {
  const records = new Map();
  let failedPiece = false;
  const recordFetch = async (url, { method, headers, body }) => {
    assert.equal(headers.Authorization, 'Bearer fixture-token');
    assert.equal(url.origin, issuer);
    const id = url.pathname.split('/').at(-1);
    const record = records.get(id);
    if (method === 'GET') return Response.json(record ?? {}, { status: record ? 200 : 404 });
    assert.equal(headers['If-Match'], '"' + (record?.revision ?? 0) + '"');
    if (method === 'DELETE') {
      records.delete(id);
      return Response.json({ ok: true });
    }
    const payload = JSON.parse(body);
    assert.equal(payload.public, false);
    assert.ok(Buffer.byteLength(JSON.stringify(payload.data)) < 60_000);
    if (failedPiece && id.startsWith('backup-') && id.endsWith('-1')) return Response.json({}, { status: 503 });
    const revision = (record?.revision ?? 0) + 1;
    records.set(id, { ...payload, revision });
    return Response.json({ revision, public: false });
  };
  const { request, pickup, callback, cookie } = await fixture(context, recordFetch);
  assert.equal((await request('/backup')).status, 401);
  assert.equal((await request(callback, { headers: { Cookie: cookie } })).status, 200);
  const { session } = await (await request('/pickup', post(pickup))).json();
  const headers = { Authorization: 'Bearer ' + session };
  const archive = Buffer.concat([Buffer.from('bplist00'), Buffer.alloc(90_000, 31)]).toString('base64');
  const updated = Buffer.concat([Buffer.from('bplist00'), Buffer.alloc(90_000, 32)]).toString('base64');
  const send = (value, revision) => request('/backup', { method: 'PUT',
    headers: { ...headers, 'Content-Type': 'application/json', 'If-Match': revision },
    body: JSON.stringify({ archive: value }) });
  assert.equal((await request('/backup', { headers })).status, 404);
  assert.equal((await send('not a backup', '"0"')).status, 400);
  assert.equal((await send(archive, '"0"')).headers.get('etag'), '"1"');
  assert.equal(records.size, 4);
  assert.equal((await request('/backup', { method: 'HEAD', headers })).headers.get('etag'), '"1"');
  assert.deepEqual(await (await request('/backup', { headers })).json(), { archive });
  assert.equal((await send(updated, '"0"')).status, 409);
  failedPiece = true;
  assert.equal((await send(updated, '"1"')).status, 503);
  assert.equal(records.size, 4);
  assert.deepEqual(await (await request('/backup', { headers })).json(), { archive });
  failedPiece = false;
  assert.equal((await send(updated, '"1"')).headers.get('etag'), '"2"');
  assert.deepEqual(await (await request('/backup', { headers })).json(), { archive: updated });
  assert.equal(records.size, 4);
  assert.equal((await request('/backup', { method: 'DELETE',
    headers: { ...headers, 'If-Match': '"2"' } })).status, 204);
  assert.equal((await request('/backup', { headers })).status, 404);
  assert.equal(records.size, 1);
  assert.equal((await send(archive, '"0"')).headers.get('etag'), '"4"');
});
