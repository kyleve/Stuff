/** Budgets constrain only speculative offscreen loading, never a visible screen. */
export interface ImageCandidate {
    screen: { id: string };
    imagePixels: number;
    isVisible: boolean;
}

export function selectResidentImages(candidates: ImageCandidate[], imageLimit: number, pixelLimit: number): Set<string> {
    const result = new Set<string>();
    let pixels = 0;
    for (const candidate of candidates) {
        if (!candidate.isVisible) continue;
        result.add(candidate.screen.id);
        pixels += candidate.imagePixels;
    }
    for (const candidate of candidates) {
        if (candidate.isVisible) continue;
        if (result.size >= imageLimit) break;
        if (result.size > 0 && pixels + candidate.imagePixels > pixelLimit) continue;
        result.add(candidate.screen.id);
        pixels += candidate.imagePixels;
    }
    return result;
}
