import { element } from './dom.ts';

/** Recover a failed full-resolution request without changing the selected state. */
export function captureRecovery(image: HTMLImageElement, screenTitle: string): HTMLElement {
    const panel = element('section', 'capture-error');
    panel.hidden = true;
    const status = element('p', '', `Could not load the capture for ${screenTitle}.`);
    status.setAttribute('role', 'status');
    const retry = element('button', 'primary-button', 'Retry capture');
    retry.type = 'button';
    const reload = element('button', 'secondary-button', 'Reload atlas');
    reload.type = 'button';
    const help = element('p', '', 'If the atlas changed after you opened it, reload the atlas.');
    let attempt = 0;
    let restoreFocus = false;
    const source = image.src;
    image.addEventListener('error', () => {
        image.dataset.loadError = 'true';
        panel.hidden = false;
        retry.disabled = false;
        status.textContent = `Could not load the capture for ${screenTitle}.`;
    });
    image.addEventListener('load', () => {
        delete image.dataset.loadError;
        if (panel.contains(document.activeElement) || (restoreFocus && document.activeElement === document.body)) {
            const target = image.closest<HTMLElement>('[data-capture-scroller]')
                ?? image.closest('dialog')?.querySelector<HTMLElement>('.close-inspector');
            target?.focus();
        }
        panel.hidden = true;
        retry.disabled = false;
        restoreFocus = false;
    });
    retry.addEventListener('click', () => {
        restoreFocus = panel.contains(document.activeElement);
        retry.disabled = true;
        status.textContent = 'Loading capture…';
        const url = new URL(source);
        url.searchParams.set('retry', String(++attempt));
        image.src = url.href;
    });
    reload.addEventListener('click', () => window.location.reload());
    panel.append(status, help, retry, reload);
    return panel;
}
