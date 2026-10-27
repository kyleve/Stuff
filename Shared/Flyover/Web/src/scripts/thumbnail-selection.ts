import type { AtlasImage, AtlasThumbnail, Size } from './manifest.ts';

/** Select explicitly so zooming out can release a larger decoded image as well as zooming in. */
export function selectThumbnail(metadata: AtlasImage | undefined, fullPath: string,
    displaySize: Size, pixelRatio: number, fit: 'contain' | 'cover'): AtlasThumbnail {
    const largest = {
        relativePath: metadata?.thumbnailRelativePath || fullPath,
        pixelWidth: metadata?.thumbnailPixelWidth || metadata?.pixelWidth || 0,
        pixelHeight: metadata?.thumbnailPixelHeight || metadata?.pixelHeight || 0,
    };
    if (!metadata?.thumbnailVariants?.length) return largest;
    // Cards contain the thumbnail within their preview box. Use its aspect ratio,
    // not the full-content capture's height, to determine the actual displayed pixels.
    const scale = (fit === 'cover' ? Math.max : Math.min)(displaySize.width / largest.pixelWidth, displaySize.height / largest.pixelHeight)
        * pixelRatio;
    const width = Math.min(largest.pixelWidth, Math.max(1, largest.pixelWidth * scale));
    const height = Math.min(largest.pixelHeight, Math.max(1, largest.pixelHeight * scale));
    return [...metadata.thumbnailVariants, largest]
        .sort((a, b) => a.pixelWidth * a.pixelHeight - b.pixelWidth * b.pixelHeight)
        .find(candidate => candidate.pixelWidth >= width && candidate.pixelHeight >= height) || largest;
}
