/** Fixed UTC formatting keeps production and offline snapshots independent of host locale. */
export function publishedDate(date: string, includeYear: boolean): string {
  const value = new Date(date);
  const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.getUTCMonth()];
  return month + ' ' + value.getUTCDate() + (includeYear ? ', ' + value.getUTCFullYear() : '');
}

export function downloadSize(size: number): string {
  if (size >= 1_000_000_000) return (size / 1_000_000_000).toFixed(1) + ' GB';
  if (size >= 1_000_000) return (size / 1_000_000).toFixed(1) + ' MB';
  return Math.max(1, Math.round(size / 1_000)).toLocaleString('en-US') + ' KB';
}
