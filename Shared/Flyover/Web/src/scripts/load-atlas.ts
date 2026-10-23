/** Load the local data before starting the viewer. Never interpret catalog text as HTML. */
import { readManifest, type AtlasManifest } from './manifest.ts';

export async function openAtlas(root: HTMLElement, start: (manifest: AtlasManifest) => void): Promise<void> {
    try {
        if (location.protocol === 'file:') {
            throw new Error('Run ./flyover preview or upload this directory to a static web host.');
        }
        const response = await fetch(new URL('./manifest.json', document.baseURI), { cache: 'no-store' });
        if (!response.ok) throw new Error(`Could not load manifest.json (HTTP ${response.status}).`);
        const manifest = readManifest(await response.json());
        start(manifest);
    } catch (error) {
        const main = document.createElement('main');
        main.className = 'error selectable-text';
        main.setAttribute('role', 'alert');
        const title = document.createElement('h1');
        title.textContent = 'Flyover cannot open this atlas';
        const message = document.createElement('p');
        message.textContent = error instanceof Error ? error.message : String(error);
        main.append(title, message);
        root.replaceChildren(main);
    } finally {
        root.removeAttribute('aria-busy');
    }
}
