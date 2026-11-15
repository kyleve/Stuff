# UI guidance: accessibility

## Build for accessibility and localization

- Exercise standard and accessibility Dynamic Type while constructing the
  layout. Restack crowded rows, grow meaningful accents and tap targets, and
  keep complete labels and values readable.
- Give custom full-screen modal surfaces the `.isModal` accessibility trait and
  post `.screenChanged` when crossing the modal boundary.
- Group an illustrative card into one meaningful accessibility summary.
  For a row with one action, expose one element with its evidence and action.
  Preserve separate controls when actions differ.
  Inspect spoken output and focus order, not only annotation rectangles.
- Never rely on color alone when Broadway reports Differentiate Without Color.
- Resolve user-facing copy through the owning module's generated
  `LocalizedStringResource` symbols. Keep DEBUG UI localized unless its module
  explicitly documents developer-only literal strings.
- Format numbers, dates, and measurements with `FormatStyle` or the module's
  shared formatter rather than interpolation or ad-hoc strings.
