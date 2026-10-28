import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseSite } from '../src/site-data.ts';

// Exercise the real Python-to-Astro boundary, including every retained preview state.
const result = spawnSync('python3', ['-c', `
import json
from Tools.InstallerKit.installer_site_data import prepare_site
from Tools.Tests.Fixtures.installer_update_fixtures import site_scenarios, REPO, FEED_URL
print(json.dumps([prepare_site(catalog, REPO, FEED_URL, registered_apps={}).data
                 for catalog in site_scenarios().values()]))
`], { cwd: fileURLToPath(new URL('../../../../', import.meta.url)), encoding: 'utf8' });
assert.equal(result.error, undefined);
assert.equal(result.status, 0, result.stderr);
const prepared: unknown = JSON.parse(result.stdout);
assert.ok(Array.isArray(prepared));
const sites = prepared.map((value: unknown) => parseSite(value));
const populated = sites.find(site => site.apps.some(app => app.channels.some(channel => channel.state === 'active')))!;

void test('Python presentation scenarios cover all channel states and legacy release details', () => {
  assert.ok(sites.length > 1);
  const channels = sites.flatMap(site => site.apps.flatMap(app => app.channels));
  assert.deepEqual([...new Set(channels.map(channel => channel.state))].sort(), ['active', 'failed', 'preparing', 'retired', 'unpublished']);
  assert.ok(channels.some(channel => channel.state === 'active' && channel.release.buildDetails === undefined));
  assert.ok(channels.some(channel => channel.state === 'active' && channel.buildStatus !== undefined));
  assert.ok(channels.some(channel => channel.state === 'active' && channel.release.commits.some(commit => commit.subject.includes('<script>'))));
});

void test('empty publication data is valid', () => {
  assert.deepEqual(parseSite({ ...populated, apps: [] }), { ...populated, apps: [] });
});

void test('malformed primitives and nested values fail with field paths', () => {
  for (const value of [null, [], 'site', false]) assert.throws(() => parseSite(value), /site must be an object/);
  const app = populated.apps[0];
  for (const [field, value] of Object.entries({ siteURL: 1, basePath: null, repository: false, apps: {} })) {
    assert.throws(() => parseSite({ ...populated, [field]: value }), new RegExp('site.' + field));
  }
  for (const [field, value] of Object.entries({ id: 1, name: false, bundleIdentifier: null, presentation: [], channels: {} })) {
    assert.throws(() => parseSite({ ...populated, apps: [{ ...app, [field]: value }] }), new RegExp('apps\\[0\\].' + field));
  }
  for (const field of ['subtitle', 'icon', 'darkIcon']) {
    assert.throws(() => parseSite({ ...populated, apps: [{ ...app, presentation: { ...app.presentation, [field]: 42 } }] }), /presentation/);
  }
});

void test('active releases and progress states require their complete presentation shape', () => {
  const app = populated.apps[0];
  const active = app.channels.find(channel => channel.state === 'active')!;
  const parseChannel = (channel: unknown) => parseSite({ ...populated, apps: [{ ...app, channels: [channel] }] });
  for (const channel of [{ name: 'main', state: 'unknown' }, { ...active, installURL: null },
    { name: 'main', state: 'failed' }, { name: 'main', state: 'preparing', runURL: false },
    { ...active, buildStatus: { state: 'active', runURL: 'url' } }]) assert.throws(() => parseChannel(channel));
  for (const [field, value] of Object.entries({ id: { run: true, attempt: 1 }, sha: 1, publishedAt: null,
    bundleVersion: 1, baseSHA: 1, historyChanged: 'false', commits: [{ sha: 'sha', subject: 1 }], buildDetails: null })) {
    assert.throws(() => parseChannel({ ...active, release: { ...active.release, [field]: value } }), new RegExp('release.' + field));
  }
  for (const run of [0, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => parseChannel({ ...active, release: { ...active.release, id: { run, attempt: 1 } } }), /id.run/);
  }
  for (const field of ['version', 'minimumOSVersion', 'sizeBytes']) {
    assert.throws(() => parseChannel({ ...active, release: { ...active.release, buildDetails: {
      version: '1', minimumOSVersion: '27', sizeBytes: 1, [field]: false,
    } } }), /buildDetails/);
  }
});
