// Run: HISH_TYPESCRIPT=/path/to/typescript node --test test/port-mappings.test.cjs
// Executes the production pure ArkTS validator, transpiled by TypeScript.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { createRequire } = require('node:module');
const { strict: assert } = require('node:assert');
const { test } = require('node:test');
const ts = require(process.env.HISH_TYPESCRIPT || 'typescript');
const file = join(__dirname, '../feature/hish_main/src/main/ets/lib/validatePortMappings.ets');
const compiled = ts.transpileModule(readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const loaded = { exports: {} };
new Function('require', 'exports', 'module', compiled)(createRequire(file), loaded.exports, loaded);
const validate = loaded.exports.validatePortMappings;

test('empty list and inclusive TCP port boundaries are valid', () => {
  assert.equal(validate([]), undefined);
  assert.equal(validate([{ guest: 1, host: 65535 }, { guest: 65535, host: 1 }]), undefined);
});
for (const side of ['guest', 'host']) {
  test(`${side}: missing port reports the correct row`, () => {
    const mapping = { guest: 3080, host: 8000 };
    delete mapping[side];
    assert.deepEqual(validate([{ guest: 22, host: 2222 }, mapping]), { kind: 'incomplete', index: 1 });
  });
  for (const port of [-1, 0, 65536, 100000, 1.5, NaN, Infinity]) {
    test(`${side}: rejects ${port}`, () => {
      assert.deepEqual(validate([{ guest: 3080, host: 8000, [side]: port }]), { kind: 'range', index: 0 });
    });
  }
  test(`${side}: duplicate ports retain the existing validation policy`, () => {
    const first = { guest: 3080, host: 8000 };
    const second = { guest: 3081, host: 8001, [side]: first[side] };
    assert.deepEqual(validate([first, second]), { kind: 'duplicate', index: 1 });
  });
}
