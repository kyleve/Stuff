/** Keep native arrow-key scrolling and focus when the inspector changes scale. */
export function updateCaptureScroller(
    frame: HTMLElement, device: HTMLElement, title: string, extent: string, scale: string,
): void {
    const fullContent = extent === 'fullContent' || extent === 'fullContent2D';
    const scroller = scale === 'actual' ? frame : (fullContent ? device : null);
    const previous = [frame, device].find(node => node === document.activeElement);
    for (const node of [frame, device]) {
        if (node === scroller) {
            node.tabIndex = 0;
            node.dataset.captureScroller = '';
            node.setAttribute('role', 'region');
            node.setAttribute('aria-label', title + ' scrollable capture');
            node.dataset.focusKey = 'inspector-capture';
        } else {
            for (const attribute of ['tabindex', 'data-capture-scroller', 'data-focus-key', 'role', 'aria-label']) {
                node.removeAttribute(attribute);
            }
        }
    }
    if (previous && scroller && previous !== scroller) scroller.focus();
}
