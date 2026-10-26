import { readFileSync } from 'node:fs';

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

const path = process.env.INSTALLER_SITE_DATA;
if (!path) throw new Error('Build through installer_update_site.py, or use npm run dev for fixture data.');
// Python owns runtime validation. This private shape is not the public catalog schema.
export const site = JSON.parse(readFileSync(path, 'utf8')) as Site;

export function appURL(app: App): string {
  return site.basePath + 'apps/' + app.id + '/';
}

export function channelURL(app: App, channel: Channel): string {
  return appURL(app) + channel.name + '/';
}

export function channelLabel(channel: Channel): string {
  return channel.name === 'main' ? 'Main' : 'PR #' + channel.name.slice(3);
}

export function mainChannel(app: App): ActiveChannel | undefined {
  return app.channels.find((channel): channel is ActiveChannel => channel.name === 'main' && channel.state === 'active');
}
