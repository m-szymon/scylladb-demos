// Draws the custom elements the slides use (icons, connectors) and drives screen navigation.
(function () {
  const ICONS = {
    Warning:   '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
    Lightbulb: '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M15.1 14a5 5 0 1 0-6.2 0c.7.6 1.1 1.3 1.1 2v2h4v-2c0-.7.4-1.4 1.1-2z"/>',
    Clock:     '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    Check:     '<path d="M20 6 9 17l-5-5"/>',
    Search:    '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    Database:  '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5"/><path d="M3 12a9 3 0 0 0 18 0"/>',
    Settings:  '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h0a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v0a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  };

  function drawIcons() {
    document.querySelectorAll('x-icon').forEach(el => {
      const body = ICONS[el.getAttribute('name')] || ICONS.Check;
      el.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
    });
  }

  let markerSeq = 0;
  function drawConnectors() {
    document.querySelectorAll('x-connector').forEach(el => {
      const host = el.parentElement;
      if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
      const [x1, y1, x2, y2] = ['x1', 'y1', 'x2', 'y2'].map(a => parseFloat(el.getAttribute(a)));
      const color = el.style.color || '#687797';
      const width = parseFloat(el.style.borderWidth) || 2;
      const dash = el.style.borderStyle === 'dashed' ? `${width * 4} ${width * 3}` : el.style.borderStyle === 'dotted' ? `${width} ${width * 2}` : '';
      const head = el.getAttribute('head') || 'end';
      const id = `arrow${markerSeq++}`;
      const ns = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(ns, 'svg');
      svg.setAttribute('class', 'connector');
      const m = (mid, path) => `<marker id="${mid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="4" markerHeight="4" orient="${path}" markerUnits="strokeWidth"><path d="M0,0 L10,5 L0,10 z" fill="${color}"/></marker>`;
      svg.innerHTML = `<defs>${m(id, 'auto')}${m(id + 's', 'auto-start-reverse')}</defs>` +
        `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${color}" stroke-width="${width}" ${dash ? `stroke-dasharray="${dash}"` : ''} ` +
        `${head === 'end' || head === 'both' ? `marker-end="url(#${id})"` : ''} ${head === 'both' ? `marker-start="url(#${id}s)"` : ''}/>`;
      host.appendChild(svg);
    });
  }

  // ---- screen navigation ----
  function setupScreen() {
    if (matchMedia('print').matches) return;
    const slides = Array.from(document.querySelectorAll('.deck > section'));
    const deck = document.querySelector('.deck');
    const hud = document.getElementById('hud');
    const notes = document.getElementById('notes');
    let i = Math.max(0, Math.min(slides.length - 1, (parseInt(location.hash.slice(1), 10) || 1) - 1));

    function fit() {
      const s = Math.min(innerWidth / 1920, innerHeight / 1080);
      deck.style.transform = `scale(${s})`;
    }
    function show() {
      slides.forEach((s, k) => s.classList.toggle('current', k === i));
      location.hash = String(i + 1);
      hud.textContent = `${i + 1} / ${slides.length}   ←/→ navigate · n notes · p print`;
      const aside = slides[i].querySelector('aside');
      notes.textContent = aside ? aside.textContent : '(no notes)';
    }
    addEventListener('resize', fit);
    addEventListener('keydown', e => {
      if (['ArrowRight', 'PageDown', ' '].includes(e.key)) { i = Math.min(slides.length - 1, i + 1); show(); }
      else if (['ArrowLeft', 'PageUp'].includes(e.key)) { i = Math.max(0, i - 1); show(); }
      else if (e.key === 'Home') { i = 0; show(); }
      else if (e.key === 'End') { i = slides.length - 1; show(); }
      else if (e.key === 'n') { document.body.classList.toggle('notes'); }
      else if (e.key === 'p') { print(); }
    });
    addEventListener('click', e => { if (!notes.contains(e.target)) { i = Math.min(slides.length - 1, i + 1); show(); } });
    fit(); show();
  }

  drawIcons();
  drawConnectors();
  setupScreen();
})();
