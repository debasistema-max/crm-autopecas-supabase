const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const read = file => fs.readFileSync(file, 'utf8');

function harness() {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {
      dataset: {}, listeners: {}, hidden: false, complete: true, naturalWidth: 800,
      src: 'https://example.invalid/photo.png', currentSrc: '', alt: 'Foto do produto 001',
      open: false, disabled: false, value: '100', textContent: '', scrollLeft: 0, scrollTop: 0,
      style: { values: {}, setProperty(key, value) { this.values[key] = value; } },
      addEventListener(event, callback) { (this.listeners[event] ||= []).push(callback); },
      emit(event, target = this) { (this.listeners[event] || []).forEach(fn => fn({ target, currentTarget: this })); },
      getAttribute(name) { return this[name]; }, removeAttribute(name) { this[name] = ''; },
      showModal() { this.open = true; this.showCount = (this.showCount || 0) + 1; },
      close() { this.open = false; this.emit('close'); }
    });
    return nodes.get(id);
  };
  node('imageDialog').open = true;
  const context = vm.createContext({ document: { getElementById: node } });
  vm.runInContext(read('public/b2b/js/photo_viewer.js'), context);
  context.bindB2BPhotoViewer();
  return { node, context };
}

test('B2B photo opens the already loaded source and preserves the product sheet', () => {
  const { node, context } = harness();
  node('imageDialogImage').currentSrc = 'https://example.invalid/loaded-photo.png';
  node('productPhotoExpand').emit('click');
  assert.equal(node('productPhotoDialog').open, true);
  assert.equal(node('productPhotoImage').src, node('imageDialogImage').currentSrc);
  assert.equal(node('productPhotoTitle').textContent, 'Foto do produto 001');
  assert.equal(node('imageDialog').open, true);
  context.bindB2BPhotoViewer();
  assert.equal(node('productPhotoExpand').listeners.click.length, 1);
  node('productPhotoClose').emit('click');
  assert.equal(node('productPhotoDialog').open, false);
  assert.equal(node('imageDialog').open, true);
  assert.equal(node('productPhotoImage').src, '');
});

test('missing, loading or failed photos cannot open the viewer', () => {
  for (const state of [{ hidden: true }, { complete: false }, { naturalWidth: 0 }, { src: '' }]) {
    const { node } = harness();
    Object.assign(node('imageDialogImage'), state);
    node('imageDialogImage').emit('load');
    assert.equal(node('productPhotoExpand').disabled, true);
    node('productPhotoExpand').emit('click');
    assert.equal(node('productPhotoDialog').open, false);
  }
  const { node } = harness();
  node('imageDialogImage').emit('error');
  assert.equal(node('productPhotoExpand').disabled, true);
});

test('zoom is bounded, reopening resets position and image failures show a message', () => {
  const { node } = harness();
  node('productPhotoExpand').emit('click');
  node('productPhotoZoom').value = '250';
  node('productPhotoZoom').emit('input');
  assert.equal(node('productPhotoViewport').style.values['--photo-scale'], '2.5');
  node('productPhotoZoom').value = '999';
  node('productPhotoZoom').emit('input');
  assert.equal(node('productPhotoZoomValue').textContent, '300%');
  node('productPhotoImage').emit('error');
  assert.equal(node('productPhotoError').hidden, false);
  node('productPhotoDialog').close();
  node('productPhotoViewport').scrollLeft = 200;
  node('productPhotoExpand').emit('click');
  assert.equal(node('productPhotoZoomValue').textContent, '100%');
  assert.equal(node('productPhotoViewport').scrollLeft, 0);
  assert.equal(node('productPhotoError').hidden, true);
  node('imageDialog').close();
  assert.equal(node('productPhotoDialog').open, false);
});

test('B2B viewer is keyboard-accessible, scrollable on mobile and cache-versioned', () => {
  const html = read('public/b2b/index.html');
  assert.match(html, /<button id="productPhotoExpand"[^>]*aria-label=/);
  assert.match(html, /<dialog id="productPhotoDialog"[^>]*aria-labelledby="productPhotoTitle"/);
  assert.match(html, /id="productPhotoZoom"[^>]*type="range"/);
  assert.match(html, /photo_viewer\.js\?v=20261027-photo-zoom-1/);
  assert.match(html, /catalog\.css\?v=20261027-photo-zoom-1/);
  const css = read('public/b2b/css/catalog.css');
  assert.match(css, /\.product-photo-dialog > \.product-photo-viewport[\s\S]*?overflow: auto/);
  assert.match(css, /max-height: calc\(100dvh - 24px\)/);
  const app = read('public/b2b/js/app.js');
  assert.match(app, /function bindPortal\(\) \{\s*bindB2BPhotoViewer\(\)/);
  assert.match(app, /getElementById\('productPhotoExpand'\)\.disabled = true/);
});
