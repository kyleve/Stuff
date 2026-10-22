interface ScrollPosition { left: number; top: number }
export interface InspectorPosition {
    screenID: string;
    frame: ScrollPosition;
    device: ScrollPosition;
}

export function captureInspectorPosition(dialog: HTMLElement | null): InspectorPosition | null {
    const frame = dialog?.querySelector<HTMLElement>('.inspector-image');
    const device = dialog?.querySelector<HTMLElement>('.inspector-device');
    if (!dialog?.dataset.screenId || !frame || !device) return null;
    return {
        screenID: dialog.dataset.screenId,
        frame: { left: frame.scrollLeft, top: frame.scrollTop },
        device: { left: device.scrollLeft, top: device.scrollTop },
    };
}

/** Restore only this screen, after the replacement image establishes its scroll bounds. */
export function restoreInspectorPosition(dialog: HTMLElement, position: InspectorPosition | null): void {
    if (!position || position.screenID !== dialog.dataset.screenId) return;
    const restore = () => {
        if (!dialog.isConnected) return;
        dialog.querySelector('.inspector-image')?.scrollTo(position.frame);
        dialog.querySelector('.inspector-device')?.scrollTo(position.device);
    };
    const image = dialog.querySelector('img');
    if (image && !image.complete) image.addEventListener('load', restore, { once: true });
    else restore();
}
