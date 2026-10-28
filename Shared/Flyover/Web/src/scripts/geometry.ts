import type { Rect, Size } from "./manifest.ts";

/** Fit operations may go below the manual zoom floor to keep large catalogs visible. */
export function fittedZoom(frame: Size, viewport: Size, maximum: number): number {
    const padding = Math.min(Math.max(viewport.width * 0.055, 32), 80);
    return Math.min(maximum,
        Math.max(viewport.width - padding * 2, 1) / Math.max(frame.width, 1),
        Math.max(viewport.height - padding * 2, 1) / Math.max(frame.height, 1));
}

export function initialZoom(width: number, viewportWidth: number): number {
    return Math.min(1, Math.max(viewportWidth - 32, 1) / width);
}

export function manualZoom(next: number, previous: number, minimum: number, maximum: number): number {
    return Math.max(Math.min(minimum, previous), Math.min(maximum, next));
}

export function rectIntersects(frame: Rect, visibleRect: { left: number; top: number; right: number; bottom: number }) {
    return frame.x < visibleRect.right && frame.x + frame.width > visibleRect.left
        && frame.y < visibleRect.bottom && frame.y + frame.height > visibleRect.top;
}

export function squaredDistance(x1: number, y1: number, x2: number, y2: number) {
    const x = x1 - x2;
    const y = y1 - y2;
    return x * x + y * y;
}

export function touchMidpoint(touches: TouchList) {
    return {
        x: (touches[0].clientX + touches[1].clientX) / 2,
        y: (touches[0].clientY + touches[1].clientY) / 2,
    };
}

export function touchDistance(touches: TouchList) {
    return Math.hypot(
        touches[0].clientX - touches[1].clientX,
        touches[0].clientY - touches[1].clientY,
    );
}
