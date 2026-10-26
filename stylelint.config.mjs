/** Correctness rules without a repository-wide cosmetic rewrite. */
export default {
    ignoreFiles: ['**/node_modules/**', '**/.build/**', '**/dist/**', '**/.astro/**'],
    rules: {
        'at-rule-no-unknown': true,
        'block-no-empty': true,
        'color-no-invalid-hex': true,
        'declaration-block-no-duplicate-properties': [true, { ignore: ['consecutive-duplicates-with-different-values'] }],
        'declaration-block-no-shorthand-property-overrides': true,
        'font-family-no-duplicate-names': true,
        'keyframe-declaration-no-important': true,
        'no-duplicate-selectors': true,
        'property-no-unknown': true,
        'selector-pseudo-class-no-unknown': true,
        'selector-pseudo-element-no-unknown': true,
        'unit-no-unknown': true,
    },
};
