import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FrameScope } from '../src/scripts/frame-scope.ts';

test('cancel invalidates queued and already-dequeued callbacks without suppressing the next render', () => {
    const callbacks = new Map<number, FrameRequestCallback>();
    const cancelled: number[] = [];
    let next = 0;
    const scope = new FrameScope({
        requestAnimationFrame(callback) { callbacks.set(++next, callback); return next; },
        cancelAnimationFrame(id) { cancelled.push(id); },
    });
    const calls: string[] = [];
    scope.request(() => calls.push('stale'));
    scope.cancel();
    scope.request(() => calls.push('current'));
    for (const callback of callbacks.values()) callback(1);
    assert.deepEqual(calls, ['current']);
    assert.deepEqual(cancelled, [1]);
});
