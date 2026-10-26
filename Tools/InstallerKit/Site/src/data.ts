import { readFileSync } from 'node:fs';

import { parseSite, type App, type Channel, type ActiveChannel } from './site-data.ts';
export type { Release, ActiveChannel, BuildStatus, ProgressChannel, Channel, App, Site } from './site-data.ts';

const path = process.env.INSTALLER_SITE_DATA;
if (!path) throw new Error('Build through installer_update_site.py, or use npm run dev for fixture data.');
export const site = parseSite(JSON.parse(readFileSync(path, 'utf8')));

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
