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
    fontFamily: 'monospace', codeStyle: 'subtle', wrapCode: false, followSystem: false, theme: 'default',
    rememberPosition: true, showDial: true,
    highlightEnabled: true, showHighlights: true, showMarks: true,
    rsvpWpm: 320, rsvpWords: 1, rsvpFontSize: 64, rsvpFont: 'serif', rsvpTheme: 'dark',
    rsvpFocusMarks: true, rsvpFocusLetter: true, rsvpPauseLong: true, rsvpPauseNumbers: true,
    rsvpPausePunct: true, rsvpPauseParagraph: true, rsvpShowCode: true
  };
  var LIMITS = { fontSize: [12, 48, 1], lineHeight: [1, 2.5, 0.1], letterSpacing: [-2, 6, 0.5], maxWidth: [560, 2200, 40],
    rsvpWpm: [100, 1200, 10], rsvpWords: [1, 3, 1], rsvpFontSize: [24, 120, 4] };
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
  // every code block gets a wrap/unwrap button in its corner. The label is CSS
  // ::after text, so the button adds no text to the content (highlight offsets
  // and the speed reader's word count stay the same).
  content.querySelectorAll('pre').forEach(function (pre, i) {
    var w = el('div', 'code-block'); w.setAttribute('data-i', i);
    pre.parentNode.insertBefore(w, pre); w.appendChild(pre);
    var b = el('button', 'wrap-btn'); b.type = 'button'; b.setAttribute('aria-label', 'Toggle line wrapping'); b.title = 'Wrap long lines';
    w.appendChild(b);
  });
  var ORIGINAL = content.innerHTML;
  var wrapOverride = {}; // code block index -> true (wrap) / false (no wrap), set by its button
  function applyWrapOverrides() {
    content.querySelectorAll('.code-block').forEach(function (w) {
      var o = wrapOverride[w.getAttribute('data-i')];
      w.classList.toggle('wrap', o === true); w.classList.toggle('nowrap', o === false);
    });
  }
  content.addEventListener('click', function (ev) {
    var b = ev.target.closest && ev.target.closest('.wrap-btn'); if (!b) return;
    var w = b.parentNode, i = w.getAttribute('data-i');
    var wrapped = w.classList.contains('wrap') || (S.wrapCode && !w.classList.contains('nowrap'));
    wrapOverride[i] = !wrapped; applyWrapOverrides();
  });
  var words = (content.innerText || content.textContent).trim().split(/\s+/).filter(Boolean).length;
  var minutes = Math.max(1, Math.ceil(words / WPM));
  var ICON = {
    src: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/></svg>',
    clock: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    doc: '<svg viewBox="0 0 24 24"><path d="M6 3h9l5 5v13H6z"/><path d="M14 3v6h6"/></svg>',
    cal: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
    full: '<svg viewBox="0 0 24 24"><path d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5"/></svg>',
    bolt: '<svg viewBox="0 0 24 24"><path d="M13 2L4 14h7l-1 8 9-12h-7z"/></svg>',
    play: '<svg viewBox="0 0 24 24"><path d="M7 4l13 8-13 8z" fill="currentColor" stroke="none"/></svg>',
    pause: '<svg viewBox="0 0 24 24"><path d="M7 4h4v16H7zM13 4h4v16h-4z" fill="currentColor" stroke="none"/></svg>',
    back: '<svg viewBox="0 0 24 24"><path d="M4 12a8 8 0 1 0 3-6.2"/><path d="M4 4v5h5"/></svg>',
    fwd: '<svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-3-6.2"/><path d="M20 4v5h-5"/></svg>'
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
    root.setAttribute('data-code', S.codeStyle);
    root.classList.toggle('wrap-code', !!S.wrapCode);
    root.style.setProperty('--rsvp-size', S.rsvpFontSize + 'px');
    root.style.setProperty('--rsvp-font', S.rsvpFont === 'page' ? 'var(--font-family)' : (FONTS[S.rsvpFont] || FONTS.serif));
    root.setAttribute('data-rsvp-theme', S.rsvpTheme);
    root.classList.toggle('no-focus-marks', !S.rsvpFocusMarks);
    root.classList.toggle('no-focus-letter', !S.rsvpFocusLetter);
    if (rsvp.open) rsvp.refresh();
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
    if (key === 'wrapCode') { wrapOverride = {}; applyWrapOverrides(); }
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
    applyWrapOverrides();
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
    '<button type="button" id="btn-rsvp" title="Speed read (r)" aria-label="Speed read">' + ICON.bolt + '</button>' +
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
  document.getElementById('btn-rsvp').addEventListener('click', function () { rsvp.start(); });

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

  /* ---- speed reading (RSVP overlay, after SwiftRead) ---- */
  var rsvp = (function () {
    var box = el('div'); box.id = 'rsvp'; box.setAttribute('aria-label', 'Speed reader');
    box.innerHTML =
      '<div class="prog"></div>' +
      '<div class="top"><span class="count"></span><span class="wpm"></span>' +
        '<button type="button" class="close" aria-label="Close (Esc)">×</button></div>' +
      '<div class="stage"><div class="word"><span class="pre"></span><span class="orp"></span><span class="post"></span></div>' +
        '<div class="slide"><div class="slide-body"></div>' +
          '<button type="button" class="cont">Continue <kbd>space</kbd></button></div>' +
        '<div class="done">End of document <button type="button" class="again">Read again</button></div></div>' +
      '<div class="bar">' +
        '<button type="button" class="slower" title="Slower (↓)">−10</button>' +
        '<button type="button" class="back" title="Previous sentence (←)">' + ICON.back + '</button>' +
        '<button type="button" class="play" title="Play / pause (space)">' + ICON.play + '</button>' +
        '<button type="button" class="fwd" title="Next sentence (→)">' + ICON.fwd + '</button>' +
        '<button type="button" class="faster" title="Faster (↑)">+10</button>' +
      '</div>';
    body.appendChild(box);
    var q = function (sel) { return box.querySelector(sel); };
    var wordPre = q('.pre'), wordOrp = q('.orp'), wordPost = q('.post'), wordBox = q('.word');
    var slide = q('.slide'), slideBody = q('.slide-body'), done = q('.done');
    var prog = q('.prog'), count = q('.count'), wpmEl = q('.wpm'), playBtn = q('.play');

    var chunks = [], idx = 0, playing = false, timer = null, totalWords = 0;
    var SENT = /[.!?…]["'”’)\]]*$/, CLAUSE = /[,;:—–]["'”’)\]]*$/;

    function tokens() {
      // walk the content's block elements; code blocks and tables become slides
      var BLOCKS = 'p, h1, h2, h3, h4, h5, h6, li, pre, .table-wrap, dt, dd';
      var out = [], blocks = content.querySelectorAll(BLOCKS);
      blocks.forEach(function (b) {
        if (b.closest('pre, .table-wrap') && !(b.tagName === 'PRE' || b.classList.contains('table-wrap'))) return;
        if (b.tagName === 'PRE' || b.classList.contains('table-wrap')) {
          if (S.rsvpShowCode) out.push({ slide: b, block: b });
          return;
        }
        var head = /^H[1-6]$/.test(b.tagName), words = [];
        // only this block's own text: a tight nested list sits inside its parent <li>
        // and a loose <li> wraps <p>s, and those blocks are walked on their own
        var w = document.createTreeWalker(b, NodeFilter.SHOW_TEXT, { acceptNode: function (n) {
          var p = n.parentElement;
          if (!p || p.closest('svg')) return NodeFilter.FILTER_REJECT;
          return p.closest(BLOCKS) === b ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT; } });
        var n;
        while ((n = w.nextNode())) {
          var code = n.parentElement.closest('code');
          if (code) {
            if (words.length && words[words.length - 1].codeEl === code) { words[words.length - 1].w += n.data; continue; }
            words.push({ w: n.data, code: true, codeEl: code, block: b }); continue;
          }
          n.data.split(/\s+/).forEach(function (t) { if (t) words.push({ w: t, block: b }); });
        }
        if (!words.length) return;
        words.forEach(function (t) { if (t.code) t.w = t.w.replace(/\s+/g, ' ').trim(); });
        words[words.length - 1].end = head ? 'head' : 'para';
        out.push.apply(out, words);
      });
      return out;
    }
    function build() {
      var toks = tokens(); chunks = []; totalWords = 0;
      var cur = null;
      toks.forEach(function (t) {
        if (t.slide) { if (cur) chunks.push(cur); cur = null; chunks.push({ slide: t.slide, block: t.block, words: 0 }); return; }
        totalWords++;
        var boundary = !cur || cur.words >= S.rsvpWords || t.code || cur.code || cur.end;
        if (boundary) { if (cur) chunks.push(cur); cur = { text: t.w, words: 1, block: t.block, code: !!t.code, end: t.end, sent: SENT.test(t.w), clause: CLAUSE.test(t.w) }; }
        else { cur.text += ' ' + t.w; cur.words++; cur.end = t.end; cur.sent = SENT.test(t.w); cur.clause = CLAUSE.test(t.w); }
        if (cur.sent || cur.clause) { chunks.push(cur); cur = null; }
      });
      if (cur) chunks.push(cur);
      chunks.forEach(function (c, i) { c.i = i; });
    }
    function duration(c) {
      if (c.slide) return 0;
      var base = 60000 / S.rsvpWpm, m = c.words, L = c.text.length;
      if (c.code) m += Math.min(L, 48) / 16;
      else if (S.rsvpPauseLong && L >= 9) m *= 1.3;
      if (S.rsvpPauseNumbers && /\d/.test(c.text)) m *= 1.4;
      if (S.rsvpPausePunct) { if (c.sent) m *= 2; else if (c.clause) m *= 1.5; }
      if (S.rsvpPauseParagraph && c.end) m *= (c.end === 'head' ? 2.5 : 2);
      return Math.max(80, base * m);
    }
    function orpIndex(s) { var L = s.length; return L <= 1 ? 0 : L <= 5 ? 1 : L <= 9 ? 2 : L <= 13 ? 3 : 4; }
    function show() {
      var c = chunks[idx];
      if (!c) { finish(); return; }
      slide.classList.remove('show'); done.classList.remove('show'); wordBox.classList.remove('hide');
      if (c.slide) {
        slideBody.innerHTML = ''; slideBody.appendChild(c.slide.cloneNode(true));
        wordBox.classList.add('hide'); slide.classList.add('show'); pause();
      } else {
        var t = c.text, k = c.words > 1 ? orpIndex(t.split(' ')[0]) : orpIndex(t);
        wordPre.textContent = t.slice(0, k); wordOrp.textContent = t.charAt(k); wordPost.textContent = t.slice(k + 1);
        wordBox.classList.toggle('is-code', !!c.code);
      }
      var left = 0; for (var i = idx; i < chunks.length; i++) left += chunks[i].words;
      var secs = Math.round(left / S.rsvpWpm * 60), mm = Math.floor(secs / 60), ss = secs % 60;
      count.textContent = (idx + 1) + ' / ' + chunks.length + ' · ' + mm + ':' + (ss < 10 ? '0' : '') + ss + ' left';
      prog.style.width = (chunks.length ? (idx + 1) / chunks.length * 100 : 0) + '%';
      wpmEl.textContent = S.rsvpWpm + ' wpm' + (S.rsvpWords > 1 ? ' · ' + S.rsvpWords + ' words' : '');
    }
    function tick() {
      if (!playing) return;
      show();
      var c = chunks[idx];
      if (!c || c.slide) return;
      timer = setTimeout(function () { idx++; if (idx >= chunks.length) { finish(); return; } tick(); }, duration(c));
    }
    function play() {
      if (idx >= chunks.length) idx = 0;
      playing = true; playBtn.innerHTML = ICON.pause; playBtn.classList.add('on');
      clearTimeout(timer); timer = setTimeout(tick, 250);
    }
    function pause() { playing = false; clearTimeout(timer); playBtn.innerHTML = ICON.play; playBtn.classList.remove('on'); }
    function finish() { pause(); idx = chunks.length; wordBox.classList.add('hide'); slide.classList.remove('show'); done.classList.add('show'); prog.style.width = '100%'; }
    function sentenceStart(i) { while (i > 0 && !(chunks[i - 1].sent || chunks[i - 1].end || chunks[i - 1].slide)) i--; return i; }
    function back() { var s0 = sentenceStart(Math.min(idx, chunks.length - 1)); idx = s0 < idx ? s0 : sentenceStart(Math.max(0, s0 - 1)); restart(); }
    function forward() { var i = idx; while (i < chunks.length - 1 && !(chunks[i].sent || chunks[i].end || chunks[i].slide)) i++; idx = Math.min(chunks.length - 1, i + 1); restart(); }
    function restart() { clearTimeout(timer); if (playing) { timer = setTimeout(tick, 150); } else show(); }
    function speed(d) { set('rsvpWpm', Math.min(LIMITS.rsvpWpm[1], Math.max(LIMITS.rsvpWpm[0], S.rsvpWpm + d))); show(); }
    function cont() { if (idx < chunks.length && chunks[idx].slide) idx++; play(); }
    function startIndex() {
      var top = 60;
      for (var i = 0; i < chunks.length; i++) if (chunks[i].block.getBoundingClientRect().bottom > top) return i;
      return 0;
    }
    var api = { open: false };
    api.start = function () {
      build();
      if (!chunks.length) return;
      idx = startIndex(); api.open = true; box.classList.add('open'); body.classList.add('rsvp-open');
      togglePanel(false); hidePop(); show(); play();
    };
    api.stop = function () {
      pause(); api.open = false; box.classList.remove('open'); body.classList.remove('rsvp-open');
      var c = chunks[Math.min(idx, chunks.length - 1)];
      if (c && c.block) {
        // one instant jump: a smooth scrollIntoView would be cancelled by a follow-up scrollBy
        window.scrollTo({ top: c.block.getBoundingClientRect().top + window.scrollY - 80, behavior: 'instant' });
        c.block.classList.add('rsvp-left'); setTimeout(function () { c.block.classList.remove('rsvp-left'); }, 1800);
      }
      onScroll();
    };
    api.refresh = function () {
      if (!api.open) return;
      var block = chunks[Math.min(idx, chunks.length - 1)] && chunks[Math.min(idx, chunks.length - 1)].block;
      var was = chunks.length; build();
      if (was !== chunks.length && block) { for (var i = 0; i < chunks.length; i++) if (chunks[i].block === block) { idx = i; break; } }
      idx = Math.min(idx, chunks.length - 1); restart();
    };
    api.key = function (ev) {
      switch (ev.key) {
        case 'Escape': api.stop(); return true;
        case ' ': if (chunks[idx] && chunks[idx].slide) cont(); else if (playing) pause(); else play(); return true;
        case 'ArrowLeft': back(); return true;
        case 'ArrowRight': forward(); return true;
        case 'ArrowUp': case '+': case '=': speed(10); return true;
        case 'ArrowDown': case '-': case '_': speed(-10); return true;
        case 'r': api.stop(); return true;
      }
      return false;
    };
    q('.close').addEventListener('click', api.stop);
    q('.again').addEventListener('click', function () { idx = 0; play(); });
    q('.cont').addEventListener('click', cont);
    playBtn.addEventListener('click', function () { if (chunks[idx] && chunks[idx].slide) cont(); else if (playing) pause(); else play(); });
    q('.back').addEventListener('click', back); q('.fwd').addEventListener('click', forward);
    q('.slower').addEventListener('click', function () { speed(-10); }); q('.faster').addEventListener('click', function () { speed(10); });
    q('.stage').addEventListener('click', function (ev) { if (ev.target.closest('button') || ev.target.closest('.slide')) return; if (playing) pause(); else if (!(chunks[idx] && chunks[idx].slide)) play(); });
    return api;
  })();

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
    { type: 'select', key: 'codeStyle', label: 'Inline Code', options: [['subtle', 'Subtle grey'], ['tinted', 'Tinted red'], ['bordered', 'Bordered grey'], ['outlined', 'Outlined red'], ['accent', 'Accent blue'], ['inverted', 'Inverted pill']] },
    { type: 'toggle', key: 'wrapCode', label: 'Wrap code blocks' },
    { type: 'toggle', key: 'followSystem', label: 'Follow System Theme' },
    { type: 'select', key: 'theme', label: 'Theme', options: [['default', 'Default'], ['dark', 'Dark'], ['sepia', 'Sepia']] },
    { type: 'section', label: 'Reading settings' },
    { type: 'toggle', key: 'rememberPosition', label: 'Remember reading position' },
    { type: 'toggle', key: 'showDial', label: 'Show reading time dial' },
    { type: 'section', label: 'Highlight settings' },
    { type: 'toggle', key: 'highlightEnabled', label: 'Enable Highlighting' },
    { type: 'toggle', key: 'showHighlights', label: 'Show highlights on page' },
    { type: 'toggle', key: 'showMarks', label: 'Show highlight page marks' },
    { type: 'section', label: 'Speed reading' },
    { type: 'step', key: 'rsvpWpm', label: 'Speed', fmt: function (v) { return v + ' wpm'; } },
    { type: 'step', key: 'rsvpWords', label: 'Words at a time', fmt: function (v) { return String(v); } },
    { type: 'step', key: 'rsvpFontSize', label: 'Font size', fmt: function (v) { return v + 'px'; } },
    { type: 'select', key: 'rsvpFont', label: 'Font', options: [['serif', 'serif'], ['sans-serif', 'sans-serif'], ['monospace', 'monospace'], ['page', 'same as page']] },
    { type: 'select', key: 'rsvpTheme', label: 'Theme', options: [['dark', 'Dark'], ['light', 'Light'], ['page', 'Same as page']] },
    { type: 'toggle', key: 'rsvpFocusMarks', label: 'Focus marks' },
    { type: 'toggle', key: 'rsvpFocusLetter', label: 'Focus letter' },
    { type: 'toggle', key: 'rsvpPauseLong', label: 'Pause on long words' },
    { type: 'toggle', key: 'rsvpPauseNumbers', label: 'Pause on numbers' },
    { type: 'toggle', key: 'rsvpPausePunct', label: 'Pause on punctuation' },
    { type: 'toggle', key: 'rsvpPauseParagraph', label: 'Pause on paragraphs' },
    { type: 'toggle', key: 'rsvpShowCode', label: 'Pause and show code blocks' }
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
    if (rsvp.open && rsvp.key(ev)) { ev.preventDefault(); return; }
    if (ev.key === 'Escape') { togglePanel(false); hidePop(); }
    else if (ev.key === 's') togglePanel();
    else if (ev.key === 'f') document.getElementById('btn-full').click();
    else if (ev.key === 'r') rsvp.start();
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
