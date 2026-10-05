/* reader-view — the Style panel, outline, reading dial, reading position and
   highlights for pages produced by reader-render. Settings persist in
   localStorage (one origin for every file:// page in Chrome and Safari, so a
   change made on one rendered reply applies to the next). Defaults can also be
   seeded per machine from ~/.config/reader/settings.json, which reader-render
   embeds as window.READER_DEFAULTS. */
(function () {
  'use strict';

  var DEFAULTS = {
    fontSize: 25, lineHeight: 1.6, letterSpacing: 0, maxWidth: 1200, textAlign: 'left',
    outline: true, showVideo: true, showPhoto: true, bionic: false,
    fontFamily: 'monospace', followSystem: false, theme: 'default',
    rememberPosition: true, showDial: true,
    highlightEnabled: true, showHighlights: true, showMarks: true
  };
  var LIMITS = { fontSize: [12, 48, 1], lineHeight: [1, 2.5, 0.1], letterSpacing: [-2, 6, 0.5], maxWidth: [560, 2200, 40] };
  var FONTS = {
    monospace: 'ui-monospace, "SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", monospace',
    'sans-serif': '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif',
    serif: 'Georgia, "Iowan Old Style", "Times New Roman", Times, serif',
    system: 'system-ui, -apple-system, sans-serif'
  };
  var KEY = 'reader.settings';
  var WPM = 230;

  var root = document.documentElement, body = document.body;
  var content = document.getElementById('content');
  var head = document.getElementById('head');
  var meta = document.getElementById('meta');
  var panel = document.getElementById('panel');
  var tools = document.getElementById('tools');
  var marks = document.getElementById('marks');
  var pop = document.getElementById('hl-pop');
  var outlineList = document.getElementById('outline-list');
  var docKey = body.getAttribute('data-doc') || 'nodoc';
  var POS_KEY = 'reader.pos.' + docKey, HL_KEY = 'reader.hl.' + docKey;

  function store(k) { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } }
  function put(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private window etc. */ } }
  function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
  function round(v) { return Math.round(v * 100) / 100; }

  function loadSettings() {
    var s = {}, k;
    for (k in DEFAULTS) s[k] = DEFAULTS[k];
    var seed = window.READER_DEFAULTS, saved = store(KEY);
    [seed, saved].forEach(function (src) {
      if (!src || typeof src !== 'object') return;
      for (k in src) if (k in DEFAULTS && typeof src[k] === typeof DEFAULTS[k]) s[k] = src[k];
    });
    return s;
  }
  var S = loadSettings();

  /* ---- title, meta line, original snapshot ---- */
  var first = content.firstElementChild;
  if (first && first.tagName === 'H1') { first.classList.add('doc-title'); head.insertBefore(first, head.firstChild); }
  content.querySelectorAll('table').forEach(function (t) {
    var w = el('div', 'table-wrap'); t.parentNode.insertBefore(w, t); w.appendChild(t);
  });
  var ORIGINAL = content.innerHTML;
  var words = (content.innerText || content.textContent).trim().split(/\s+/).filter(Boolean).length;
  var minutes = Math.max(1, Math.ceil(words / WPM));
  var ICON = {
    src: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/></svg>',
    clock: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    doc: '<svg viewBox="0 0 24 24"><path d="M6 3h9l5 5v13H6z"/><path d="M14 3v6h6"/></svg>',
    cal: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
    full: '<svg viewBox="0 0 24 24"><path d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5"/></svg>'
  };
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  meta.innerHTML =
    '<span>' + ICON.src + esc(body.getAttribute('data-source') || 'Terminal output') + '</span>' +
    '<span>' + ICON.clock + minutes + ' Minute' + (minutes === 1 ? '' : 's') + ' Read</span>' +
    '<span>' + ICON.doc + words + ' Words</span>' +
    '<span>' + ICON.cal + esc(body.getAttribute('data-rendered') || '') + '</span>';

  /* ---- theme / layout ---- */
  var darkMedia = window.matchMedia('(prefers-color-scheme: dark)');
  function resolveTheme() {
    if (!S.followSystem) return S.theme;
    if (darkMedia.matches) return 'dark';
    return S.theme === 'dark' ? 'default' : S.theme;
  }
  function layoutRails() {
    var gutter = Math.max(0, (window.innerWidth - Math.min(S.maxWidth, window.innerWidth)) / 2);
    root.style.setProperty('--gutter', gutter + 'px');
    root.classList.toggle('narrow', gutter < 200);
  }
  var SYNC = {};
  function apply() {
    root.style.setProperty('--font-size', S.fontSize + 'px');
    root.style.setProperty('--line-height', String(S.lineHeight));
    root.style.setProperty('--letter-spacing', S.letterSpacing + 'px');
    root.style.setProperty('--max-width', S.maxWidth + 'px');
    root.style.setProperty('--text-align', S.textAlign);
    root.style.setProperty('--font-family', FONTS[S.fontFamily] || S.fontFamily);
    root.setAttribute('data-theme', resolveTheme());
    root.classList.toggle('no-outline', !S.outline);
    root.classList.toggle('no-photo', !S.showPhoto);
    root.classList.toggle('no-video', !S.showVideo);
    root.classList.toggle('no-dial', !S.showDial);
    root.classList.toggle('no-hl', !S.showHighlights);
    root.classList.toggle('no-marks', !S.showMarks);
    layoutRails();
    for (var k in SYNC) SYNC[k]();
    onScroll();
    drawMarks();
  }
  function set(key, val) {
    S[key] = val; put(KEY, S);
    if (key === 'bionic') rebuild();
    apply();
  }
  darkMedia.addEventListener('change', apply);

  /* ---- bionic reading + highlights are both rebuilt from the snapshot ---- */
  var HL = store(HL_KEY) || [];
  function bionify(rootEl) {
    var w = document.createTreeWalker(rootEl, NodeFilter.SHOW_TEXT, { acceptNode: function (n) {
      var p = n.parentElement;
      if (!p || p.closest('pre, code, kbd, samp, svg, script, style')) return NodeFilter.FILTER_REJECT;
      return /\S/.test(n.data) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
    } });
    var nodes = []; while (w.nextNode()) nodes.push(w.currentNode);
    var re = /[\p{L}\p{N}]+/gu;
    nodes.forEach(function (n) {
      var t = n.data, frag = document.createDocumentFragment(), last = 0, m;
      re.lastIndex = 0;
      while ((m = re.exec(t))) {
        if (m.index > last) frag.appendChild(document.createTextNode(t.slice(last, m.index)));
        var word = m[0], k = word.length <= 3 ? 1 : Math.ceil(word.length * 0.45);
        var b = el('b', 'bi'); b.textContent = word.slice(0, k);
        frag.appendChild(b); frag.appendChild(document.createTextNode(word.slice(k)));
        last = m.index + word.length;
      }
      if (last < t.length) frag.appendChild(document.createTextNode(t.slice(last)));
      n.parentNode.replaceChild(frag, n);
    });
  }
  function applyHighlights() {
    if (!HL.length) return;
    var hs = HL.slice().sort(function (a, b) { return a.s - b.s; });
    var w = document.createTreeWalker(content, NodeFilter.SHOW_TEXT), nodes = [], pos = 0;
    while (w.nextNode()) { nodes.push({ n: w.currentNode, start: pos }); pos += w.currentNode.data.length; }
    nodes.forEach(function (rec) {
      var a = rec.start, t = rec.n.data, len = t.length, b = a + len;
      var over = hs.filter(function (h) { return h.s < b && h.e > a; });
      if (!over.length) return;
      var frag = document.createDocumentFragment(), cur = 0;
      over.forEach(function (h) {
        var ls = Math.max(0, h.s - a), le = Math.min(len, h.e - a);
        if (ls > cur) frag.appendChild(document.createTextNode(t.slice(cur, ls)));
        var m = el('mark', 'hl'); m.setAttribute('data-id', h.id); m.textContent = t.slice(ls, le);
        frag.appendChild(m); cur = le;
      });
      if (cur < len) frag.appendChild(document.createTextNode(t.slice(cur)));
      rec.n.parentNode.replaceChild(frag, rec.n);
    });
  }
  function rebuild() {
    content.innerHTML = ORIGINAL;
    if (S.bionic) bionify(content);
    applyHighlights();
    buildOutline();
    drawMarks();
  }
  function drawMarks() {
    marks.innerHTML = '';
    if (!S.showMarks || !S.showHighlights) return;
    var H = root.scrollHeight, seen = {};
    content.querySelectorAll('mark.hl').forEach(function (m) {
      var id = m.getAttribute('data-id'); if (seen[id]) return; seen[id] = true;
      var y = m.getBoundingClientRect().top + window.scrollY;
      var i = el('i'); i.style.top = (y / H * 100) + '%'; marks.appendChild(i);
    });
  }
  function textOffset(node, offset) {
    var r = document.createRange(); r.setStart(content, 0); r.setEnd(node, offset);
    return r.toString().length;
  }
  function addHighlight(s, e) {
    var keep = [], id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    HL.forEach(function (h) { if (h.e < s || h.s > e) keep.push(h); else { s = Math.min(s, h.s); e = Math.max(e, h.e); } });
    keep.push({ id: id, s: s, e: e, text: content.textContent.slice(s, e).slice(0, 120) });
    HL = keep; put(HL_KEY, HL); rebuild();
  }
  function removeHighlight(id) {
    HL = HL.filter(function (h) { return h.id !== id; }); put(HL_KEY, HL); rebuild();
  }
  function showPop(rect, label, action) {
    pop.innerHTML = ''; var b = el('button'); b.type = 'button'; b.textContent = label;
    b.addEventListener('mousedown', function (ev) { ev.preventDefault(); });
    b.addEventListener('click', function () { hidePop(); action(); });
    pop.appendChild(b);
    pop.style.left = (rect.left + window.scrollX + rect.width / 2) + 'px';
    pop.style.top = (rect.top + window.scrollY - 40) + 'px';
    pop.classList.add('show');
  }
  function hidePop() { pop.classList.remove('show'); }
  content.addEventListener('mouseup', function () {
    setTimeout(function () {
      var sel = window.getSelection();
      if (!S.highlightEnabled || !sel || sel.isCollapsed || sel.rangeCount === 0) { hidePop(); return; }
      var r = sel.getRangeAt(0);
      if (!content.contains(r.startContainer) || !content.contains(r.endContainer)) { hidePop(); return; }
      var s = textOffset(r.startContainer, r.startOffset), e = textOffset(r.endContainer, r.endOffset);
      if (e <= s) { hidePop(); return; }
      showPop(r.getBoundingClientRect(), 'Highlight', function () { addHighlight(s, e); sel.removeAllRanges(); });
    }, 0);
  });
  content.addEventListener('click', function (ev) {
    var m = ev.target.closest && ev.target.closest('mark.hl');
    if (!m || !S.highlightEnabled || !S.showHighlights) return;
    var sel = window.getSelection(); if (sel && !sel.isCollapsed) return;
    var id = m.getAttribute('data-id');
    showPop(m.getBoundingClientRect(), 'Remove highlight', function () { removeHighlight(id); });
  });
  document.addEventListener('mousedown', function (ev) { if (!pop.contains(ev.target)) hidePop(); });

  /* ---- outline ---- */
  var headings = [];
  function buildOutline() {
    outlineList.innerHTML = ''; headings = [];
    var hs = content.querySelectorAll('h1, h2, h3'), i = 0;
    hs.forEach(function (h) {
      if (!h.id) h.id = 'h-' + (++i);
      var li = el('li', 'l' + h.tagName[1]), a = el('a');
      a.href = '#' + h.id; a.textContent = h.textContent; li.appendChild(a); outlineList.appendChild(li);
      headings.push({ h: h, a: a });
    });
  }
  function updateActive() {
    var cur = null, limit = window.innerHeight * 0.3;
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].h.getBoundingClientRect().top <= limit) cur = headings[i]; else break;
    }
    headings.forEach(function (x) { x.a.classList.toggle('active', x === cur); });
  }

  /* ---- right rail: style button, fullscreen, reading dial ---- */
  var C = 2 * Math.PI * 17;
  tools.innerHTML =
    '<button type="button" id="btn-style" title="Style (s)" aria-label="Style settings">Aa</button>' +
    '<button type="button" id="btn-full" title="Fullscreen (f)" aria-label="Fullscreen">' + ICON.full + '</button>' +
    '<div class="sep"></div>' +
    '<div id="dial" title="Reading progress">' +
      '<svg viewBox="0 0 40 40"><circle class="track" cx="20" cy="20" r="17"/>' +
      '<circle class="bar" cx="20" cy="20" r="17" stroke-dasharray="' + C + '" stroke-dashoffset="' + C + '"/></svg>' +
      '<div class="txt"><b id="dial-num">' + minutes + '</b><span>min</span></div></div>';
  var bar = tools.querySelector('.bar'), dialNum = document.getElementById('dial-num'), dial = document.getElementById('dial');
  var btnStyle = document.getElementById('btn-style');
  function togglePanel(force) {
    var open = typeof force === 'boolean' ? force : !panel.classList.contains('open');
    panel.classList.toggle('open', open); btnStyle.classList.toggle('on', open);
  }
  btnStyle.addEventListener('click', function () { togglePanel(); });
  document.getElementById('btn-full').addEventListener('click', function () {
    if (document.fullscreenElement) document.exitFullscreen(); else root.requestFullscreen && root.requestFullscreen();
  });
  dial.addEventListener('click', function () { window.scrollTo({ top: 0, behavior: 'smooth' }); });

  /* ---- scroll: dial progress, reading position, active heading ---- */
  var ticking = false, restored = false;
  function onScroll() {
    var max = root.scrollHeight - window.innerHeight;
    var p = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 1;
    bar.style.strokeDashoffset = C * (1 - p);
    dialNum.textContent = Math.max(0, Math.ceil(minutes * (1 - p)));
    dial.title = Math.round(p * 100) + '% read';
    if (S.rememberPosition && restored) put(POS_KEY, Math.round(window.scrollY));
    updateActive();
  }
  window.addEventListener('scroll', function () {
    if (ticking) return; ticking = true;
    requestAnimationFrame(function () { ticking = false; onScroll(); });
  });
  window.addEventListener('resize', function () { layoutRails(); onScroll(); drawMarks(); });

  /* ---- the Style panel ---- */
  var ALIGNS = [
    ['left', '<svg viewBox="0 0 24 24"><path d="M3 6h18M3 10h12M3 14h18M3 18h12"/></svg>'],
    ['center', '<svg viewBox="0 0 24 24"><path d="M3 6h18M6 10h12M3 14h18M6 18h12"/></svg>'],
    ['right', '<svg viewBox="0 0 24 24"><path d="M3 6h18M9 10h12M3 14h18M9 18h12"/></svg>'],
    ['justify', '<svg viewBox="0 0 24 24"><path d="M3 6h18M3 10h18M3 14h18M3 18h18"/></svg>']
  ];
  var ROWS = [
    { type: 'step', key: 'fontSize', label: 'Font Size', fmt: function (v) { return v + 'px'; } },
    { type: 'step', key: 'lineHeight', label: 'Line Height', fmt: function (v) { return v.toFixed(1); } },
    { type: 'step', key: 'letterSpacing', label: 'Letter Spacing', fmt: function (v) { return v ? v + 'px' : '0'; } },
    { type: 'step', key: 'maxWidth', label: 'Max Width', fmt: function (v) { return v + 'px'; } },
    { type: 'align', key: 'textAlign', label: 'Text Align' },
    { type: 'toggle', key: 'outline', label: 'Outline' },
    { type: 'toggle', key: 'showVideo', label: 'Show Video' },
    { type: 'toggle', key: 'showPhoto', label: 'Show Photo' },
    { type: 'toggle', key: 'bionic', label: 'Bionic Reading' },
    { type: 'select', key: 'fontFamily', label: 'Font Family', options: [['monospace', 'monospace'], ['sans-serif', 'sans-serif'], ['serif', 'serif'], ['system', 'system']] },
    { type: 'toggle', key: 'followSystem', label: 'Follow System Theme' },
    { type: 'select', key: 'theme', label: 'Theme', options: [['default', 'Default'], ['dark', 'Dark'], ['sepia', 'Sepia']] },
    { type: 'section', label: 'Reading settings' },
    { type: 'toggle', key: 'rememberPosition', label: 'Remember reading position' },
    { type: 'toggle', key: 'showDial', label: 'Show reading time dial' },
    { type: 'section', label: 'Highlight settings' },
    { type: 'toggle', key: 'highlightEnabled', label: 'Enable Highlighting' },
    { type: 'toggle', key: 'showHighlights', label: 'Show highlights on page' },
    { type: 'toggle', key: 'showMarks', label: 'Show highlight page marks' }
  ];
  function buildPanel() {
    panel.innerHTML = '<div class="ph"><span>Style</span><button type="button" aria-label="Close">×</button></div><div class="pb"></div><div class="pf"></div>';
    panel.querySelector('.ph button').addEventListener('click', function () { togglePanel(false); });
    var pb = panel.querySelector('.pb');
    ROWS.forEach(function (r) {
      if (r.type === 'section') { var d = el('div', 'sec'); d.textContent = r.label; pb.appendChild(d); return; }
      var row = el('div', 'row'), lab = el('label'); lab.textContent = r.label; row.appendChild(lab);
      var ctl;
      if (r.type === 'step') {
        ctl = el('div', 'step');
        var minus = el('button'), out = el('output'), plus = el('button');
        minus.type = plus.type = 'button'; minus.textContent = '−'; plus.textContent = '+';
        ctl.appendChild(minus); ctl.appendChild(out); ctl.appendChild(plus);
        var lo = LIMITS[r.key][0], hi = LIMITS[r.key][1], st = LIMITS[r.key][2];
        minus.addEventListener('click', function () { set(r.key, round(Math.max(lo, S[r.key] - st))); });
        plus.addEventListener('click', function () { set(r.key, round(Math.min(hi, S[r.key] + st))); });
        SYNC[r.key] = function () { out.textContent = r.fmt(S[r.key]); minus.disabled = S[r.key] <= lo; plus.disabled = S[r.key] >= hi; };
      } else if (r.type === 'toggle') {
        ctl = el('button', 'sw'); ctl.type = 'button'; ctl.setAttribute('role', 'switch');
        ctl.addEventListener('click', function () { set(r.key, !S[r.key]); });
        SYNC[r.key] = function () { ctl.classList.toggle('on', !!S[r.key]); ctl.setAttribute('aria-checked', String(!!S[r.key])); };
      } else if (r.type === 'align') {
        ctl = el('div', 'aligns'); var btns = {};
        ALIGNS.forEach(function (pair) {
          var b = el('button'); b.type = 'button'; b.innerHTML = pair[1]; b.title = pair[0];
          b.addEventListener('click', function () { set(r.key, pair[0]); }); btns[pair[0]] = b; ctl.appendChild(b);
        });
        SYNC[r.key] = function () { for (var v in btns) btns[v].classList.toggle('on', S[r.key] === v); };
      } else if (r.type === 'select') {
        ctl = el('select');
        r.options.forEach(function (o) { var opt = el('option'); opt.value = o[0]; opt.textContent = o[1]; ctl.appendChild(opt); });
        ctl.addEventListener('change', function () { set(r.key, ctl.value); });
        SYNC[r.key] = function () {
          var have = Array.prototype.some.call(ctl.options, function (o) { return o.value === S[r.key]; });
          if (!have) { var opt = el('option'); opt.value = S[r.key]; opt.textContent = 'custom'; ctl.appendChild(opt); }
          ctl.value = S[r.key];
        };
      }
      row.appendChild(ctl); pb.appendChild(row);
    });
    var pf = panel.querySelector('.pf');
    var reset = el('button'), copy = el('button'), ta = el('textarea'), hint = el('p', 'hint');
    reset.type = copy.type = 'button'; reset.textContent = 'Reset to defaults'; copy.textContent = 'Show settings JSON';
    ta.readOnly = true;
    hint.innerHTML = 'Settings are saved in this browser. To make them the defaults on every machine, save the JSON as <code>~/.config/reader/settings.json</code>.';
    reset.addEventListener('click', function () {
      for (var k in DEFAULTS) S[k] = DEFAULTS[k];
      var seed = window.READER_DEFAULTS; if (seed) for (k in seed) if (k in DEFAULTS) S[k] = seed[k];
      put(KEY, S); rebuild(); apply(); ta.value = JSON.stringify(S, null, 2);
    });
    copy.addEventListener('click', function () {
      ta.value = JSON.stringify(S, null, 2); ta.classList.toggle('show');
      if (ta.classList.contains('show')) { ta.select(); if (navigator.clipboard) navigator.clipboard.writeText(ta.value).catch(function () {}); }
    });
    pf.appendChild(reset); pf.appendChild(copy); pf.appendChild(ta); pf.appendChild(hint);
  }

  /* ---- keyboard ---- */
  document.addEventListener('keydown', function (ev) {
    if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
    var tag = (ev.target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') { if (ev.key === 'Escape') togglePanel(false); return; }
    if (ev.key === 'Escape') { togglePanel(false); hidePop(); }
    else if (ev.key === 's') togglePanel();
    else if (ev.key === 'f') document.getElementById('btn-full').click();
  });

  /* ---- go ---- */
  buildPanel();
  rebuild();
  apply();
  var savedY = S.rememberPosition ? store(POS_KEY) : null;
  if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
  // The script runs at the end of <body>, so layout is complete here; no rAF
  // (which never fires in a background tab).
  if (typeof savedY === 'number' && savedY > 0) window.scrollTo(0, savedY);
  restored = true; onScroll();
})();
