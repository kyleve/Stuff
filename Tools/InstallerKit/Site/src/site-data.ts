export interface Release {
  id: { run: number; attempt: number };
  sha: string;
  publishedAt: string;
  bundleVersion: string;
  buildDetails?: { version: string; minimumOSVersion: string; sizeBytes: number };
  baseSHA: string | null;
  historyChanged: boolean;
  commits: { sha: string; subject: string }[];
}

export interface ActiveChannel {
  name: string;
  state: 'active';
  release: Release;
  installURL: string;
  buildStatus?: BuildStatus;
}

export interface BuildStatus {
  state: 'preparing' | 'failed';
  runURL: string;
}

export type ProgressChannel = { name: string } & BuildStatus;
export type Channel = ActiveChannel | ProgressChannel | { name: string; state: 'retired' | 'unpublished' };

export interface App {
  id: string;
  name: string;
  bundleIdentifier: string;
  presentation: { subtitle: string; icon: string | null; darkIcon: string | null };
  channels: Channel[];
}

export interface Site {
  siteURL: string;
  basePath: string;
  repository: string;
  apps: App[];
}

/** Validate only Astro's private presentation shape. Python owns publication policy. */
export function parseSite(value: unknown): Site {
  const data = object(value, 'site');
  return {
    siteURL: text(data.siteURL, 'site.siteURL'),
    basePath: text(data.basePath, 'site.basePath'),
    repository: text(data.repository, 'site.repository'),
    apps: array(data.apps, 'site.apps', parseApp),
  };
}

function parseApp(value: unknown, path: string): App {
  const data = object(value, path);
  const presentation = object(data.presentation, path + '.presentation');
  return {
    id: text(data.id, path + '.id'),
    name: text(data.name, path + '.name'),
    bundleIdentifier: text(data.bundleIdentifier, path + '.bundleIdentifier'),
    presentation: {
      subtitle: text(presentation.subtitle, path + '.presentation.subtitle'),
      icon: nullableText(presentation.icon, path + '.presentation.icon'),
      darkIcon: nullableText(presentation.darkIcon, path + '.presentation.darkIcon'),
    },
    channels: array(data.channels, path + '.channels', parseChannel),
  };
}

function parseChannel(value: unknown, path: string): Channel {
  const data = object(value, path);
  const name = text(data.name, path + '.name');
  switch (data.state) {
    case 'active':
      return {
        name, state: 'active',
        release: parseRelease(data.release, path + '.release'),
        installURL: text(data.installURL, path + '.installURL'),
        ...(data.buildStatus === undefined ? {} : { buildStatus: parseStatus(data.buildStatus, path + '.buildStatus') }),
      };
    case 'preparing':
    case 'failed':
      return { name, ...parseStatus(data, path) };
    case 'retired':
    case 'unpublished':
      return { name, state: data.state };
    default:
      throw invalid(path + '.state', 'a supported channel state');
  }
}

function parseStatus(value: unknown, path: string): BuildStatus {
  const data = object(value, path);
  if (data.state !== 'preparing' && data.state !== 'failed') throw invalid(path + '.state', 'preparing or failed');
  return { state: data.state, runURL: text(data.runURL, path + '.runURL') };
}

function parseRelease(value: unknown, path: string): Release {
  const data = object(value, path);
  const identity = object(data.id, path + '.id');
  let buildDetails: Release['buildDetails'];
  if (data.buildDetails !== undefined) {
    const details = object(data.buildDetails, path + '.buildDetails');
    buildDetails = {
      version: text(details.version, path + '.buildDetails.version'),
      minimumOSVersion: text(details.minimumOSVersion, path + '.buildDetails.minimumOSVersion'),
      sizeBytes: positiveInteger(details.sizeBytes, path + '.buildDetails.sizeBytes'),
    };
  }
  return {
    id: { run: positiveInteger(identity.run, path + '.id.run'), attempt: positiveInteger(identity.attempt, path + '.id.attempt') },
    sha: text(data.sha, path + '.sha'),
    publishedAt: text(data.publishedAt, path + '.publishedAt'),
    bundleVersion: text(data.bundleVersion, path + '.bundleVersion'),
    baseSHA: nullableText(data.baseSHA, path + '.baseSHA'),
    historyChanged: boolean(data.historyChanged, path + '.historyChanged'),
    commits: array(data.commits, path + '.commits', (value, path) => {
      const commit = object(value, path);
      return { sha: text(commit.sha, path + '.sha'), subject: text(commit.subject, path + '.subject') };
    }),
    ...(buildDetails === undefined ? {} : { buildDetails }),
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function object(value: unknown, path: string): Record<string, unknown> {
  if (!isObject(value)) throw invalid(path, 'an object');
  return value;
}

function text(value: unknown, path: string): string {
  if (typeof value !== 'string') throw invalid(path, 'a string');
  return value;
}

function nullableText(value: unknown, path: string): string | null {
  return value === null ? null : text(value, path);
}

function boolean(value: unknown, path: string): boolean {
  if (typeof value !== 'boolean') throw invalid(path, 'a Boolean');
  return value;
}

function positiveInteger(value: unknown, path: string): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) throw invalid(path, 'a positive safe integer');
  return value;
}

function array<T>(value: unknown, path: string, parse: (value: unknown, path: string) => T): T[] {
  if (!Array.isArray(value)) throw invalid(path, 'an array');
  return value.map((item: unknown, index) => parse(item, path + '[' + index + ']'));
}

function invalid(path: string, expected: string): Error {
  return new Error('Invalid installer presentation data: ' + path + ' must be ' + expected + '.');
}
