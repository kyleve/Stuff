/** Own frame callbacks for one mounted render, including callbacks already dequeued by the browser. */
export class FrameScope {
    private frames = new Set<number>();
    private generation = 0;

    private clock: Pick<Window, 'requestAnimationFrame' | 'cancelAnimationFrame'>;

    constructor(clock: Pick<Window, 'requestAnimationFrame' | 'cancelAnimationFrame'>) {
        this.clock = clock;
    }

    request(callback: FrameRequestCallback): void {
        const generation = this.generation;
        const id = this.clock.requestAnimationFrame(time => {
            this.frames.delete(id);
            if (generation === this.generation) callback(time);
        });
        this.frames.add(id);
    }

    cancel(): void {
        this.generation++;
        for (const id of this.frames) this.clock.cancelAnimationFrame(id);
        this.frames.clear();
    }
}
