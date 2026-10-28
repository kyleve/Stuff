import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import astro from 'eslint-plugin-astro';

const projects = ['Shared/Flyover/Web', 'Tools/InstallerKit/Site'];
export default [
    { ignores: ['**/node_modules/**', '**/.astro/**', '**/.build/**', '**/dist/**', '**/test-results/**'] },
    ...projects.flatMap(project => [
        ...tseslint.configs.recommendedTypeChecked.map(config => ({
            ...config,
            files: [`${project}/**/*.ts`],
        })),
        {
            files: [`${project}/**/*.ts`],
            languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } },
        },
    ]),
    ...astro.configs.recommended,
    {
        files: ['**/*.mjs'],
        ...js.configs.recommended,
        languageOptions: { globals: { process: 'readonly', Buffer: 'readonly', console: 'readonly', URL: 'readonly' } },
    },
];
