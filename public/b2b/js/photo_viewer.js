function bindB2BPhotoViewer() {
  const trigger = document.getElementById('productPhotoExpand');
  if (!trigger || trigger.dataset.bound === 'true') return;
  trigger.dataset.bound = 'true';
  const sourceImage = document.getElementById('imageDialogImage');
  const details = document.getElementById('imageDialog');
  const dialog = document.getElementById('productPhotoDialog');
  const image = document.getElementById('productPhotoImage');
  const viewport = document.getElementById('productPhotoViewport');
  const zoom = document.getElementById('productPhotoZoom');
  const output = document.getElementById('productPhotoZoomValue');
  const error = document.getElementById('productPhotoError');
  const canExpand = () => !sourceImage.hidden && sourceImage.complete && sourceImage.naturalWidth > 0
    && Boolean(sourceImage.currentSrc || sourceImage.getAttribute('src'));
  sourceImage.addEventListener('load', () => { trigger.disabled = !canExpand(); });
  sourceImage.addEventListener('error', () => { trigger.disabled = true; });
  trigger.disabled = !canExpand();
  trigger.addEventListener('click', () => {
    if (!details.open || !canExpand()) return;
    // Enlarge the photo already visible in the detail sheet; no extra catalog lookup.
    image.src = sourceImage.currentSrc || sourceImage.src;
    image.alt = sourceImage.alt;
    image.hidden = false;
    error.hidden = true;
    zoom.value = '100';
    output.textContent = '100%';
    viewport.style.setProperty('--photo-scale', '1');
    document.getElementById('productPhotoTitle').textContent = sourceImage.alt || 'Foto do produto';
    if (!dialog.open) dialog.showModal();
    viewport.scrollLeft = viewport.scrollTop = 0;
  });
  zoom.addEventListener('input', () => {
    const value = Math.max(100, Math.min(300, Number(zoom.value) || 100));
    viewport.style.setProperty('--photo-scale', String(value / 100));
    output.textContent = `${value}%`;
  });
  document.getElementById('productPhotoClose').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    if (event.target === dialog) dialog.close();
  });
  dialog.addEventListener('close', () => {
    image.removeAttribute('src');
    image.alt = '';
  });
  details.addEventListener('close', () => { if (dialog.open) dialog.close(); });
  image.addEventListener('error', () => {
    image.hidden = true;
    error.hidden = false;
  });
}
