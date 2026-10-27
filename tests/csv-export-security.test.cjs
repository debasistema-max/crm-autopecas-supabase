const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function fixture() {
  const downloads = [];
  const blobs = [];
  const revoked = [];
  const context = vm.createContext({ Blob,
    URL: {
      createObjectURL(blob) { blobs.push(blob); return 'blob:fictional-export'; },
      revokeObjectURL(url) { revoked.push(url); }
    },
    document: { createElement(tag) {
      assert.equal(tag, 'a');
      return { click() { downloads.push({ filename: this.download, href: this.href }); } };
    } }
  });
  vm.runInContext(fs.readFileSync('public/js/utils/format.js', 'utf8'), context);
  return { context, downloads, blobs, revoked };
}

test('formula prefixes are neutralized inside a fully quoted CSV cell', () => {
  const { context: c } = fixture();
  for (const prefix of ['=', '+', '-', '@', '\uff1d', '\uff0b', '\uff0d', '\uff20']) {
    const input = prefix + '1+1';
    assert.equal(c.csvValue(input), '"\t' + input + '"');
    assert.equal(c.csvCell(input), c.csvValue(input));
  }
});

test('whitespace, invisible/control prefixes and multiline starts cannot hide formulas', () => {
  const { context: c } = fixture();
  for (const prefix of [' ', '\t', '\r', '\n', '\r\n', '\u0000', '\u001f', '\u007f',
    '\u0085', '\u00a0', '\ufeff', '\u200b', '\u202e', '\u2060', ' \t\u200b', "'", " ' "]) {
    const input = prefix + '=1+1';
    assert.equal(c.csvValue(input), '"\t' + input + '"');
  }
  for (const input of ['\tLAB', '\rLAB', '\nLAB']) {
    assert.equal(c.csvValue(input), '"\t' + input + '"');
  }
});

test('finite numeric amounts retain their numeric text, while string negatives are untrusted', () => {
  const { context: c } = fixture();
  for (const number of [-123.45, -1, 0, 1, 123.45]) assert.equal(c.csvValue(number), `"${number}"`);
  assert.equal(c.csvValue('-123.45'), '"\t-123.45"');
  assert.equal(c.csvValue('-Infinity'), '"\t-Infinity"');
});

test('ordinary text, nulls, codes, unicode, quotes and delimiters are preserved', () => {
  const { context: c } = fixture();
  for (const [input, expected] of [
    [null, '""'], [undefined, '""'], ['', '""'], [false, '"false"'],
    ['0000123', '"0000123"'], ['LAB OEM', '"LAB OEM"'], ['Pe\u00e7a', '"Pe\u00e7a"'],
    ['LAB;"OEM"\nsegunda linha', '"LAB;""OEM""\nsegunda linha"'],
    ['LAB;=1+1', '"LAB;=1+1"'], ['LAB";=1+1', '"LAB"";=1+1"']
  ]) assert.equal(c.csvValue(input), expected);
  assert.equal(c.csvValue('=1+1";=2+2'), '"\t=1+1"";=2+2"');
});

test('object exports protect dynamic headers as well as values, preserving BOM and download behavior', async () => {
  const { context: c, blobs, downloads, revoked } = fixture();
  const rows = [{ '=CABECALHO': '=1+1', valor: -2, descricao: 'LAB;"OEM"' }];
  c.downloadCsv('ficcional.csv', rows);
  const content = Buffer.from(await blobs[0].arrayBuffer()).toString('utf8');
  assert.equal(content, '\ufeff"\t=CABECALHO";"valor";"descricao"\r\n"\t=1+1";"-2";"LAB;""OEM"""');
  assert.deepEqual(rows, [{ '=CABECALHO': '=1+1', valor: -2, descricao: 'LAB;"OEM"' }]);
  assert.deepEqual(downloads, [{ filename: 'ficcional.csv', href: 'blob:fictional-export' }]);
  assert.deepEqual(revoked, ['blob:fictional-export']);
});

test('array exports protect every cell and empty exports still work', async () => {
  const { context: c, blobs } = fixture();
  c.downloadCsv('ficcional.csv', [['Nome', 'Valor'], [' @LAB', 12.5], ['=1+1', 0]]);
  assert.equal(Buffer.from(await blobs[0].arrayBuffer()).toString('utf8'),
    '\ufeff"Nome";"Valor"\n"\t @LAB";"12.5"\n"\t=1+1";"0"');
  c.downloadCsv('vazio.csv', []);
  assert.equal(Buffer.from(await blobs[1].arrayBuffer()).toString('utf8'), '\ufeff');
});

test('batch exports use the same shared CSV protection, including hidden prefixes', () => {
  const { context: c } = fixture();
  vm.runInContext(fs.readFileSync('public/js/import_batches.js', 'utf8'), c);
  for (const value of ['=1+1', ' \t=1+1', 'LAB;"OEM"', -12.5, null]) {
    assert.equal(c.importBatchCsvCell(value), c.csvValue(value));
  }
});

test('published entry points request the updated shared formatter', () => {
  for (const file of ['public/app.html', 'public/index.html']) {
    assert.match(fs.readFileSync(file, 'utf8'), /js\/utils\/format\.js\?v=20261027-csv-security-1/);
  }
});
