// HISH_TYPESCRIPT=/path/to/typescript node --test test/web-preview.test.cjs
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { strict: assert } = require('node:assert');
const { test } = require('node:test');
const ts = require(process.env.HISH_TYPESCRIPT || 'typescript');
const file = join(__dirname, '../feature/hish_main/src/main/ets/lib/webPreviewUrl.ets');
const compiled = ts.transpileModule(readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const loaded = { exports: {} };
new Function('exports', 'module', compiled)(loaded.exports, loaded);
const normalize = loaded.exports.normalizeWebPreviewUrl;

for (const [input, expected] of [
  ['127.0.0.1:8000', 'http://127.0.0.1:8000'],
  [' localhost:3080/path?q=1#part ', 'http://localhost:3080/path?q=1#part'],
  ['https://example.org/app', 'https://example.org/app'],
  ['HTTP://127.0.0.1:65535', 'http://127.0.0.1:65535'],
  ['[::1]:8000', 'http://[::1]:8000'],
  ['example.org', 'http://example.org']
]) {
  test(`accepts ${input}`, () => assert.equal(normalize(input), expected));
}
for (const input of ['', 'file:///data/a', 'javascript:alert(1)', 'data:text/html,a',
  'intent://a', 'ftp://localhost', 'http://user:password@localhost', 'http://localhost:0',
  'http://localhost:65536', 'http://localhost:-1', 'http://localhost:abc',
  'http://', 'http://a b', 'http://localhost\\path', 'http://localhost\n/path']) {
  test(`rejects ${JSON.stringify(input)}`, () => assert.equal(normalize(input), undefined));
}

test('phone and tablet routes expose the new shared page', () => {
  for (const product of ['phone', 'tablet']) {
    const routes = JSON.parse(readFileSync(join(__dirname,
      `../product/${product}/src/main/resources/base/profile/main_pages.json`), 'utf8'));
    assert.ok(routes.src.includes('pages/WebPreviewPage'));
  }
});
