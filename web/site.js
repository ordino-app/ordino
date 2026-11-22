// ordino site: two small jobs the kit does not do.
// 1. The hero desktop: the scattered windows snap into Master + Stack once after load (the HUD shows the
//    shortcut), and again when the pointer or the focus enters the frame. Under reduced motion they stand arranged.
// 2. The download links: the static href points at 0.2.0-beta.1; the update feed (same origin) upgrades the
//    href and the version label to the newest release. Without script or feed the static link stays.
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const desk = document.querySelector('[data-desk]');
if (desk) {
  let busy = false;
  const play = (delay) => {
    if (busy) return; busy = true;
    if (reduced) { desk.classList.remove('is-scattered'); busy = false; return; }
    desk.classList.add('is-scattered');
    setTimeout(() => {
      desk.classList.add('is-hud');
      requestAnimationFrame(() => desk.classList.remove('is-scattered'));
      setTimeout(() => { desk.classList.remove('is-hud'); busy = false; }, 1500);
    }, delay);
  };
  play(1200);
  const frame = desk.closest('.hero__window');
  let last = performance.now();
  frame?.addEventListener('pointerenter', () => { if (performance.now() - last > 2600) { last = performance.now(); play(250); } });
}

const FEED = 'https://xsugra.github.io/ordino-updates/appcast.xml';
const SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
(async () => {
  try {
    const res = await fetch(FEED, { cache: 'no-cache' });
    if (!res.ok) return;
    const xml = new DOMParser().parseFromString(await res.text(), 'application/xml');
    const item = xml.querySelector('item');
    const enc = item?.querySelector('enclosure');
    const url = enc?.getAttribute('url');
    if (!url || !/^https:\/\//.test(url)) return;
    const version = item.getElementsByTagNameNS(SPARKLE, 'shortVersionString')[0]?.textContent?.trim()
      || enc.getAttributeNS(SPARKLE, 'shortVersionString') || '';
    const bytes = Number(enc.getAttribute('length')) || 0;
    document.querySelectorAll('a[data-download]').forEach(a => { a.href = url; });
    const label = document.querySelector('[data-dl-label]');
    if (label && version) label.textContent = `Version ${version}` + (bytes ? ` · ${(bytes / 1e6).toFixed(1)} MB` : '');
  } catch { /* offline or blocked: the static link stays */ }
})();
