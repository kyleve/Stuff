import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fixture, capturePNG } from './fixture.ts';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'flyover-browser-'));
execFileSync('python3', ['-m', 'Tools.flyover_site', 'build', directory], { cwd: root, stdio: 'inherit' });
writeFileSync(join(directory, 'manifest.json'), JSON.stringify(fixture()));
const captures = new Map(['phone-light', 'phone-dark'].map(id => [id, capturePNG(id === 'phone-dark')]));
const thumbnails = new Map(['phone-light', 'phone-dark'].map(id => [id, capturePNG(id === 'phone-dark', 134, 867)]));
const server = createServer((request, response) => {
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path.startsWith('/atlas/images/')) {
        response.setHeader('Content-Type', 'image/png');
        response.end((path.endsWith('-thumbnail.png') ? thumbnails : captures).get(path.includes('phone-dark') ? 'phone-dark' : 'phone-light'));
        return;
    }
    const file = resolve(directory, decodeURIComponent(path.replace(/^\/atlas\//, '')) || 'index.html');
    if (!path.startsWith('/atlas/') || !file.startsWith(directory + sep)) {
        response.writeHead(404).end();
        return;
    }
    try {
        response.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.json') ? 'application/json' : 'text/html');
        response.end(readFileSync(file));
    } catch (error) {
        if (error.code !== 'ENOENT') console.error(error);
        response.writeHead(404).end();
    }
});
server.listen(4329, '127.0.0.1');
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
process.on('exit', () => rmSync(directory, { recursive: true, force: true }));
