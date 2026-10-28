/** Shared standard rules for both static websites. */
export default {
    extends: ['stylelint-config-standard'],
    ignoreFiles: ['**/node_modules/**', '**/.build/**', '**/dist/**', '**/.astro/**'],
    rules: {
        // Preserve the existing Safari compatibility declarations. All other prefixes remain checked.
        'property-no-vendor-prefix': [true, { ignoreProperties: [
            '-webkit-user-select', '-webkit-backdrop-filter', '-webkit-text-size-adjust',
        ] }],
    },
};
