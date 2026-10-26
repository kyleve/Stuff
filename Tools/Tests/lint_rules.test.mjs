import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const probes = [
    { name: 'Python undefined names', command: 'mise', args: ['exec', '--', 'ruff', 'check', '--stdin-filename', 'Tools/probe.py', '-'],
        source: 'print(missing_name)\n', rule: 'F821' },
    { name: 'typed promise handling', command: 'node_modules/.bin/eslint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/scripts/manifest.ts'],
        source: 'export function probe() { Promise.resolve(1); }', rule: '@typescript-eslint/no-floating-promises' },
    { name: 'CSS invalid colors', command: 'node_modules/.bin/stylelint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/styles/base.css'],
        source: 'a { color: #zzzzzz; }', rule: 'color-no-invalid-hex' },
];

for (const probe of probes) {
    void test(probe.name, () => {
        const result = spawnSync(probe.command, probe.args, { input: probe.source, encoding: 'utf8' });
        assert.equal(result.error, undefined);
        assert.notEqual(result.status, 0);
        assert.ok((result.stdout + result.stderr).includes(probe.rule), result.stdout + result.stderr);
    });
}
