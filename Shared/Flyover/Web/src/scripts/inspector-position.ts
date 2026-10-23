interface ScrollPosition { left: number; top: number }
interface InspectorPosition {
    screenID: string;
    frame: ScrollPosition;
    device: ScrollPosition;
}

function captureInspectorPosition(dialog: HTMLElement | null): InspectorPosition | null {
    const frame = dialog?.querySelector<HTMLElement>('.inspector-image');
    const device = dialog?.querySelector<HTMLElement>('.inspector-device');
    if (!dialog?.dataset.screenId || !frame || !device) return null;
    return {
        screenID: dialog.dataset.screenId,
        frame: { left: frame.scrollLeft, top: frame.scrollTop },
        device: { left: device.scrollLeft, top: device.scrollTop },
    };
}

/** Owns one inspector's pending position until its replacement image establishes scroll bounds. */
export class InspectorPositionController {
    private pendingPosition: InspectorPosition | null = null;
    private loadEvents: AbortController | null = null;

    capture(dialog: HTMLElement | null): void {
        this.loadEvents?.abort();
        this.loadEvents = null;
        // An unloaded replacement is still at zero; retain the last measured position instead.
        if (!dialog || this.pendingPosition?.screenID !== dialog.dataset.screenId) {
            this.pendingPosition = captureInspectorPosition(dialog);
        }
    }

    restore(dialog: HTMLElement): void {
        this.loadEvents?.abort();
        const position = this.pendingPosition;
        if (!position || position.screenID !== dialog.dataset.screenId) {
            this.reset();
            return;
        }
        const events = new AbortController();
        this.loadEvents = events;
        const restore = () => {
            if (events.signal.aborted || !dialog.isConnected) return;
            dialog.querySelector('.inspector-image')?.scrollTo(position.frame);
            dialog.querySelector('.inspector-device')?.scrollTo(position.device);
            this.reset();
        };
        const image = dialog.querySelector('img');
        if (image?.complete && image.naturalWidth > 0) restore();
        else image?.addEventListener('load', restore, { once: true, signal: events.signal });
    }

    reset(): void {
        this.loadEvents?.abort();
        this.loadEvents = null;
        this.pendingPosition = null;
    }
}
