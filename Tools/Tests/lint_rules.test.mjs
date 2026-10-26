import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const probes = [
    { name: 'Python formatting', command: 'mise', args: ['exec', '--', 'ruff', 'format', '--check', '--diff', '--stdin-filename', 'Tools/probe.py', '-'],
        source: 'items=[1,2]\n', rule: '+items = [1, 2]' },
    { name: 'Python assigned lambdas', command: 'mise', args: ['exec', '--', 'ruff', 'check', '--stdin-filename', 'Tools/probe.py', '-'],
        source: 'callback = lambda value: value\n', rule: 'E731' },
    { name: 'Python undefined names', command: 'mise', args: ['exec', '--', 'ruff', 'check', '--stdin-filename', 'Tools/probe.py', '-'],
        source: 'print(missing_name)\n', rule: 'F821' },
    { name: 'typed promise handling', command: 'node_modules/.bin/eslint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/scripts/manifest.ts'],
        source: 'export function probe() { Promise.resolve(1); }', rule: '@typescript-eslint/no-floating-promises' },
    { name: 'CSS invalid colors', command: 'node_modules/.bin/stylelint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/styles/base.css'],
        source: 'a { color: #zzzzzz; }', rule: 'declaration-property-value-no-unknown' },
    { name: 'CSS invalid property values', command: 'node_modules/.bin/stylelint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/styles/base.css'],
        source: 'a { display: potato; }', rule: 'declaration-property-value-no-unknown' },
    { name: 'CSS accidental duplicate values', command: 'node_modules/.bin/stylelint',
        args: ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/styles/base.css'],
        source: 'a {\n  color: red;\n  color: blue;\n}', rule: 'declaration-block-no-duplicate-properties' },
];

for (const probe of probes) {
    void test(probe.name, () => {
        const result = spawnSync(probe.command, probe.args, { input: probe.source, encoding: 'utf8' });
        assert.equal(result.error, undefined);
        assert.notEqual(result.status, 0);
        assert.ok((result.stdout + result.stderr).includes(probe.rule), result.stdout + result.stderr);
    });
}

void test('intentional Safari compatibility properties remain valid', () => {
    const result = spawnSync('node_modules/.bin/stylelint', ['--stdin', '--stdin-filename', 'Shared/Flyover/Web/src/styles/base.css'], {
        input: 'a {\n  -webkit-user-select: none;\n  user-select: none;\n  -webkit-backdrop-filter: blur(5px);\n  backdrop-filter: blur(5px);\n  -webkit-text-size-adjust: 100%;\n  text-size-adjust: 100%;\n}',
        encoding: 'utf8',
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stdout + result.stderr);
});
