// tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
// Copyright (C) 2026 kks2003 és a közreműködők
//
// Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
// Foundation által kiadott GNU General Public License 2. vagy (választás
// szerint) bármely későbbi változata szerint. A programot a hasznosság
// reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
//
// Kottaszerkesztő (zongoratekercs): a betöltött MIDI hangjai csatornánként
// színezve; a hangok kijelölhetők, mozgathatók, a hosszuk húzható, újak
// rajzolhatók; egy hang kihagyható (nem kerül át a TVC-re), és látszik, melyiket
// játssza le ténylegesen a TVC (3 szólam). Csatornánként hangszer és átültetés,
// új dal üresből. A szerkesztett dal Standard MIDI-ként megy vissza a konverterbe
// (midi2tvc.js songFromParsed / writeMidi), így a forráscsomag és a parancssori
// konverter is ugyanazt kapja.
(function (root) {
  'use strict';

  const NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const noteName = (n) => NAMES[n % 12] + (Math.floor(n / 12) - 1);
  const BLACK = [false, true, false, true, false, false, true, false, true, false, true, false];
  const KEYW = 46, RULER = 20;                  // a billentyűzet szélessége, a vonalzó magassága
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

  // opts: {M, PV, chColor(ch), gmName(n), options(), fullResult(), current() -> {parsed, name},
  //        apply(bytes, name), stopMain()}
  function NoteEditor(opts) {
    const { M, PV } = opts;
    const $ = (id) => document.getElementById(id);
    const dlg = $('ndDlg'), cv = $('ndRoll');
    let song = null, name = 'dal', dirty = false;
    let sel = new Set();                          // a kijelölt hangok (objektumok)
    let undoStack = [], redoStack = [], cleanAt = 0;   // cleanAt: a visszavonási verem mélysége a konverterbe adott állapotnál
    const view = { t0: 0, ppt: 0.25, top: 84, kh: 9 };
    let hidden = new Set();                       // a nem látszó csatornák
    let target = 0;                               // az új hangok csatornája
    let played = null;                            // Map(hang -> true / false): a TVC lejátssza-e
    let drag = null, hover = null;
    let playTick = 0, audio = null;               // meghallgatás

    const msg = (t, bad) => { const el = $('ndMsg'); el.textContent = t || ''; el.classList.toggle('bad', !!bad); };
    const gridTicks = () => { const g = +$('ndGrid').value; return g ? Math.max(1, Math.round(song.division * 4 / g)) : 1; };
    const snap = (t) => { const g = gridTicks(); return Math.round(t / g) * g; };
    const tempoConv = () => M.tickToSeconds(song.division, song.ctrl.filter((e) => e[1] === 'tempo').map((e) => [e[0], 0, 'tempo', 0, e[3], 0]));
    const endTick = () => song.notes.reduce((m, nt) => Math.max(m, nt.t + nt.d), 0);

    // ---- visszavonás -------------------------------------------------------------
    const snapshot = () => JSON.stringify({ notes: song.notes, ctrl: song.ctrl, names: song.names, division: song.division });
    function mark() {
      if (undoStack.length < cleanAt) cleanAt = -1;   // a konverterbe adott állapot már nem érhető el
      undoStack.push(snapshot());
      if (undoStack.length > 60) undoStack.shift();
      redoStack = [];
      dirty = true;
      played = null;                              // a TVC-s jelölés újra kell (Használat után)
    }
    function restore(s) {
      const o = JSON.parse(s);
      song.notes = o.notes; song.ctrl = o.ctrl; song.names = o.names; song.division = o.division;
      sel.clear();
      dirty = undoStack.length !== cleanAt;
      if (dirty) played = null; else computePlayed();
      renderChannels(); draw(); info();
    }
    function restoreQuiet(s) {                    // a csippentéssel megszakított húzás nyoma nélkül
      const o = JSON.parse(s);
      song.notes = o.notes; song.ctrl = o.ctrl; song.names = o.names;
      sel.clear();
      dirty = undoStack.length !== cleanAt;
      if (!dirty) computePlayed();
    }
    function undo() { if (!undoStack.length) return; redoStack.push(snapshot()); restore(undoStack.pop()); }
    function redo() { if (!redoStack.length) return; undoStack.push(snapshot()); restore(redoStack.pop()); }

    // ---- a dal ---------------------------------------------------------------------
    function load(s, nm) {
      song = s; name = nm || 'dal';
      sel.clear(); undoStack = []; redoStack = []; cleanAt = 0; dirty = false; hidden = new Set();
      const chs = channels();
      target = chs.find((c) => c !== 9) ?? 0;
      fit();
      computePlayed();
      renderChannels(); draw(); info();
    }
    function newSong() {
      const bpm = clamp(+$('ndBpm').value || 120, 20, 300);
      load({ division: 96, notes: [], ctrl: [[0, 'tempo', 0, Math.round(60e6 / bpm), 0], [0, 'prog', 0, 0, 0]], names: {} }, 'uj-dal');
      dirty = true; cleanAt = -1;
      msg('Új, üres dal (' + bpm + ' BPM, 4/4). Rajzolás módban kattintással kerülnek fel a hangok a kiválasztott csatornára.');
    }
    function channels() {
      const s = new Set(song.notes.map((n) => n.ch));
      for (const e of song.ctrl) if (e[1] === 'prog') s.add(e[2]);
      s.add(target);
      return [...s].sort((a, b) => a - b);
    }
    const programOf = (ch) => { const e = song.ctrl.find((x) => x[1] === 'prog' && x[2] === ch); return e ? e[3] : 0; };
    function setProgram(ch, pg) {
      mark();
      const e = song.ctrl.find((x) => x[1] === 'prog' && x[2] === ch);
      if (e) e[3] = pg; else song.ctrl.unshift([0, 'prog', ch, pg, 0]);
    }

    // a TVC melyik hangot játssza le: a fő oldal utolsó (teljes dalos) konverziójából
    function computePlayed() {
      played = null;
      const fr = opts.fullResult();             // {result, sim}: a fő oldal teljes dalos konverziója
      if (!fr || !fr.result || !fr.sim || dirty || !fr.sim.roll || !fr.sim.roll.length) return;
      const r = { options: fr.result.options, rate: fr.result.rate, roll: fr.sim.roll };
      const o = r.options, conv = tempoConv();
      const tr = o.transpose || 0, chSel = new Set(o.channels || []);
      played = new Map();
      for (const nt of song.notes) {
        if (nt.off || nt.ch === 9) continue;
        if (!chSel.has(nt.ch + 1)) { played.set(nt, false); continue; }
        const k = Math.round(conv(nt.t) / (o.speed || 1) * r.rate);
        const want = nt.n + tr;
        let ok = false;
        for (let j = k; j <= k + 1 && !ok; j++) ok = (r.roll[j] || []).some((x) => x.note === want);
        played.set(nt, ok);
      }
    }

    // ---- nézet ---------------------------------------------------------------------
    function size() {
      const r = cv.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
      cv.width = Math.round(r.width * dpr); cv.height = Math.round(r.height * dpr);
      return { w: r.width, h: r.height, dpr };
    }
    function fit() {
      const ns = song.notes.filter((n) => n.ch !== 9);
      const lo = ns.length ? Math.min(...ns.map((n) => n.n)) : 48, hi = ns.length ? Math.max(...ns.map((n) => n.n)) : 72;
      const { w, h } = size();
      view.kh = clamp(Math.floor((h - RULER) / (hi - lo + 5)), 6, 16);
      view.top = Math.min(127, hi + 2);
      view.t0 = 0;
      view.ppt = clamp((w - KEYW) / (song.division * 4 * 8), PPT_MIN, PPT_MAX);   // kb. 8 ütem
    }
    const xOf = (t) => KEYW + (t - view.t0) * view.ppt;
    const yOf = (n) => RULER + (view.top - n) * view.kh;
    const tOf = (x) => view.t0 + (x - KEYW) / view.ppt;
    const nOf = (y) => view.top - Math.floor((y - RULER) / view.kh);
    // nagyítás: vízszintesen px / tick (PPT_MIN..PPT_MAX), függőlegesen px / félhang (KH_MIN..KH_MAX)
    const PPT_MIN = 0.005, PPT_MAX = 12, KH_MIN = 3, KH_MAX = 40;
    function zoomX(f, x) {                        // x: a rögzített pont (px); alapból a közép
      const w = cv.getBoundingClientRect().width;
      if (x === undefined) x = KEYW + (w - KEYW) / 2;
      const t = tOf(x);
      view.ppt = clamp(view.ppt * f, PPT_MIN, PPT_MAX);
      view.t0 = Math.max(0, t - (x - KEYW) / view.ppt);
    }
    function zoomY(f, y) {
      const h = cv.getBoundingClientRect().height;
      if (y === undefined) y = RULER + (h - RULER) / 2;
      const n = view.top - (y - RULER) / view.kh;   // a rögzített hangmagasság (tört)
      view.kh = clamp(view.kh * f, KH_MIN, KH_MAX);
      view.top = clamp(Math.round(n + (y - RULER) / view.kh), 12, 127);
    }
    // a csúszkák: logaritmikus skála
    const toSlider = (v, a, b) => Math.round(1000 * Math.log(v / a) / Math.log(b / a));
    const fromSlider = (s, a, b) => a * Math.pow(b / a, s / 1000);
    function syncZoom() {
      $('ndZoomX').value = toSlider(view.ppt, PPT_MIN, PPT_MAX);
      $('ndZoomY').value = toSlider(view.kh, KH_MIN, KH_MAX);
    }
    function hit(x, y) {
      for (let i = song.notes.length - 1; i >= 0; i--) {
        const nt = song.notes[i];
        if (hidden.has(nt.ch)) continue;
        const x0 = xOf(nt.t), x1 = xOf(nt.t + nt.d), y0 = yOf(nt.n);
        if (x >= x0 && x <= Math.max(x1, x0 + 3) && y >= y0 && y < y0 + view.kh) return { nt, edge: x >= Math.max(x1, x0 + 3) - 5 };
      }
      return null;
    }

    function draw() {
      if (!song) return;
      syncZoom();
      const { w, h, dpr } = size();
      const c = cv.getContext('2d');
      c.setTransform(dpr, 0, 0, dpr, 0, 0);
      const css = (v) => getComputedStyle(document.documentElement).getPropertyValue(v).trim();
      const bg = css('--sunk') || '#f2f2f2', line = css('--line') || '#ccc', ink = css('--ink') || '#111', muted = css('--muted') || '#777';
      c.fillStyle = bg; c.fillRect(0, 0, w, h);
      // sorok: a fekete billentyűk sötétebben
      const nBot = view.top - Math.ceil((h - RULER) / view.kh);
      for (let n = view.top; n >= Math.max(0, nBot); n--) {
        const y = yOf(n);
        if (BLACK[n % 12]) { c.fillStyle = 'rgba(127,127,127,0.10)'; c.fillRect(KEYW, y, w - KEYW, view.kh); }
        if (n % 12 === 0) { c.fillStyle = line; c.fillRect(KEYW, y + view.kh - 1, w - KEYW, 1); }
      }
      // rács: negyedek, ütemek (4/4)
      const beat = song.division, bar = beat * 4, g = gridTicks();
      const tEnd = tOf(w);
      const step = view.ppt * g >= 6 ? g : (view.ppt * beat >= 6 ? beat : bar);
      for (let t = Math.floor(view.t0 / step) * step; t <= tEnd; t += step) {
        if (t < view.t0) continue;
        const x = Math.round(xOf(t)) + 0.5;
        c.fillStyle = t % bar === 0 ? muted : line;
        c.globalAlpha = t % bar === 0 ? 0.6 : (t % beat === 0 ? 0.7 : 0.35);
        c.fillRect(x, RULER, 1, h - RULER);
        c.globalAlpha = 1;
      }
      // hangok
      for (const nt of song.notes) {
        if (hidden.has(nt.ch)) continue;
        const x0 = xOf(nt.t), x1 = xOf(nt.t + nt.d);
        if (x1 < KEYW || x0 > w) continue;
        const y = yOf(nt.n);
        if (y + view.kh < RULER || y > h) continue;
        const col = opts.chColor(nt.ch), wd = Math.max(2, x1 - x0 - 1);
        const p = played ? played.get(nt) : undefined;
        if (nt.off) {
          c.strokeStyle = muted; c.setLineDash([3, 3]); c.strokeRect(x0 + 0.5, y + 0.5, wd, view.kh - 2); c.setLineDash([]);
        } else {
          c.fillStyle = col;
          c.globalAlpha = p === false ? 0.3 : 0.55 + 0.45 * nt.v / 127;
          c.fillRect(x0, y, wd, view.kh - 1);
          c.globalAlpha = 1;
          if (p === false) { c.strokeStyle = col; c.strokeRect(x0 + 0.5, y + 0.5, wd - 1, view.kh - 2); }
        }
        if (!nt.off && nt.pr > 0) { c.fillStyle = ink; c.fillRect(x0, y, Math.min(3, wd), view.kh - 1); }       // mindenképp
        if (!nt.off && nt.pr < 0) { c.fillStyle = bg; c.fillRect(x0, y + Math.floor((view.kh - 1) / 2), wd, 1); } // ha van hely
        if (sel.has(nt)) { c.strokeStyle = ink; c.lineWidth = 2; c.strokeRect(x0 + 1, y + 1, Math.max(1, wd - 2), view.kh - 3); c.lineWidth = 1; }
      }
      // kijelölő téglalap
      if (drag && drag.kind === 'box') {
        c.fillStyle = css('--accent'); c.globalAlpha = 0.15;
        c.fillRect(Math.min(drag.x0, drag.x1), Math.min(drag.y0, drag.y1), Math.abs(drag.x1 - drag.x0), Math.abs(drag.y1 - drag.y0));
        c.globalAlpha = 1;
      }
      // vonalzó: ütemszámok, a lejátszás helye
      c.fillStyle = css('--surface') || '#fff'; c.fillRect(0, 0, w, RULER);
      c.fillStyle = line; c.fillRect(0, RULER - 1, w, 1);
      c.fillStyle = muted; c.font = '11px system-ui, sans-serif'; c.textBaseline = 'middle';
      const barStep = Math.max(1, Math.ceil(40 / (view.ppt * bar)));
      for (let b = Math.floor(view.t0 / bar); b * bar <= tEnd; b++) {
        if (b % barStep || b * bar < view.t0) continue;
        c.fillText(String(b + 1), xOf(b * bar) + 3, RULER / 2);
      }
      const ph = xOf(audio ? audio.tick : playTick);
      if (ph >= KEYW) { c.fillStyle = css('--warn') || '#c00'; c.fillRect(Math.round(ph), 0, 2, h); }
      // billentyűzet
      c.fillStyle = css('--surface') || '#fff'; c.fillRect(0, RULER, KEYW, h - RULER);
      for (let n = view.top; n >= Math.max(0, nBot); n--) {
        const y = yOf(n);
        if (BLACK[n % 12]) { c.fillStyle = ink; c.globalAlpha = 0.75; c.fillRect(0, y, KEYW * 0.6, view.kh); c.globalAlpha = 1; }
        if ((n % 12 === 0 && view.kh >= 6) || view.kh >= 14) {     // nagy sormagasságnál minden hang neve
          c.fillStyle = BLACK[n % 12] ? css('--surface') || '#fff' : muted;
          c.fillText(noteName(n), BLACK[n % 12] ? 3 : KEYW * 0.62, y + view.kh / 2);
        }
      }
      c.fillStyle = line; c.fillRect(KEYW - 1, RULER, 1, h - RULER);
      // a mutatott hang adatai
      const t = hover ? hover.nt : null;
      $('ndHover').textContent = t ? '— ' + noteName(t.n) + ' · ' + (t.ch + 1) + '. csatorna · erősség ' + t.v +
        ' · ' + (t.d / song.division).toFixed(2).replace('.', ',') + ' negyed' + (t.off ? ' · kihagyva' : t.pr > 0 ? ' · ★ mindenképp szóljon' : t.pr < 0 ? ' · csak ha van hely' : '') +
        (played && played.get(t) === false ? ' · a TVC-n nem szól (nincs szabad szólam)' : '') : '';
    }

    function info() {
      if (!song) return;
      const on = song.notes.filter((n) => !n.off).length;
      let t = song.notes.length + ' hang, ebből ' + (song.notes.length - on) + ' kihagyva';
      const hi = song.notes.filter((n) => !n.off && n.pr > 0).length, lo = song.notes.filter((n) => !n.off && n.pr < 0).length;
      if (hi) t += ', ' + hi + ' ★ mindenképp';
      if (lo) t += ', ' + lo + ' csak ha van hely';
      if (played) {
        let p = 0, q = 0;
        for (const v of played.values()) { if (v) p++; else q++; }
        t += ' · a TVC-n ' + p + ' szól, ' + q + ' nem fér el (halványan)';
      } else if (dirty) t += ' · módosítva (a „Használat a konverterben” után látszik, melyiket játssza a TVC)';
      $('ndInfo').textContent = t + (sel.size ? ' · ' + sel.size + ' kijelölve' : '');
      $('ndSelBar').hidden = !sel.size;
      if (sel.size) {
        const vs = [...sel].map((n) => n.v);
        $('ndVel').value = Math.round(vs.reduce((a, b) => a + b, 0) / vs.length);
      }
    }

    // ---- csatornák -------------------------------------------------------------------
    function renderChannels() {
      const ul = $('ndChans');
      ul.textContent = '';
      for (const ch of channels()) {
        const li = document.createElement('li');
        const cnt = song.notes.filter((n) => n.ch === ch).length;
        li.innerHTML = '<label class="vis"><input type="checkbox"><i class="dot"></i><span class="nm"></span></label>' +
          '<input type="radio" name="ndTarget" title="Ide kerülnek az új hangok">' +
          '<select title="Hangszer (MIDI program)"></select><button type="button" title="A csatorna hangjainak kijelölése">Kijelöl</button>' +
          '<span class="tr">Átültetés: <button type="button" data-k="-12" title="Az egész csatorna egy oktávval le">−12</button><button type="button" data-k="-1" title="Egy félhanggal le">−1</button>' +
          '<button type="button" data-k="1" title="Egy félhanggal fel">+1</button><button type="button" data-k="12" title="Egy oktávval fel">+12</button></span>';
        const [vis, radio, pgSel, selBtn] = [li.querySelector('input[type=checkbox]'), li.querySelector('input[type=radio]'), li.querySelector('select'), li.querySelector('button')];
        for (const b of li.querySelectorAll('.tr button')) {
          if (ch === 9) { b.disabled = true; b.title = 'A dobcsatornán a hangmagasság a dobot választja'; continue; }
          b.addEventListener('click', () => {
            const ns = song.notes.filter((n) => n.ch === ch);
            if (!ns.length) return;
            mark();
            for (const nt of ns) nt.n = clamp(nt.n + +b.dataset.k, 0, 127);
            msg((ch + 1) + '. csatorna: ' + (+b.dataset.k > 0 ? '+' : '') + b.dataset.k + ' félhang.');
            draw(); info();
          });
        }
        li.querySelector('.dot').style.background = opts.chColor(ch);
        li.querySelector('.nm').textContent = (ch + 1) + '. ' + (song.names[ch] || (ch === 9 ? 'dob' : '')) + ' (' + cnt + ')';
        vis.checked = !hidden.has(ch);
        vis.addEventListener('change', () => { if (vis.checked) hidden.delete(ch); else hidden.add(ch); draw(); });
        radio.checked = ch === target;
        radio.addEventListener('change', () => { target = ch; });
        if (ch === 9) pgSel.innerHTML = '<option>dobok</option>', pgSel.disabled = true;
        else {
          for (let i = 0; i < 128; i++) { const o = document.createElement('option'); o.value = i; o.textContent = i + ' ' + opts.gmName(i); pgSel.appendChild(o); }
          pgSel.value = programOf(ch);
          pgSel.addEventListener('change', () => { setProgram(ch, +pgSel.value); info(); });
        }
        selBtn.addEventListener('click', () => {
          sel = new Set(song.notes.filter((n) => n.ch === ch));
          draw(); info();
        });
        ul.appendChild(li);
      }
      // új csatorna
      const free = [...Array(16).keys()].filter((c) => !channels().includes(c));
      const add = $('ndAddCh');
      add.innerHTML = '<option value="">+ csatorna…</option>' + free.map((c) => '<option value="' + c + '">' + (c + 1) + (c === 9 ? ' (dob)' : '') + '</option>').join('');
    }

    // ---- műveletek a kijelölésen ----------------------------------------------------
    function transpose(k) {
      if (!sel.size) return;
      mark();
      for (const nt of sel) nt.n = clamp(nt.n + k, 0, 127);
      draw(); info();
    }
    function moveTime(k) {
      if (!sel.size) return;
      mark();
      const min = Math.min(...[...sel].map((n) => n.t));
      const d = Math.max(-min, k);
      for (const nt of sel) nt.t += d;
      draw(); info();
    }
    function setOff(v) {
      if (!sel.size) return;
      mark();
      for (const nt of sel) nt.off = v || undefined;
      draw(); info();
    }
    function setPrio(v) {
      if (!sel.size) return;
      mark();
      for (const nt of sel) { if (v) nt.pr = v; else delete nt.pr; }
      draw(); info();
    }
    function del() {
      if (!sel.size) return;
      mark();
      song.notes = song.notes.filter((n) => !sel.has(n));
      sel.clear();
      renderChannels(); draw(); info();
    }
    function setVel(v) {
      if (!sel.size) return;
      mark();
      for (const nt of sel) nt.v = clamp(v, 1, 127);
      draw(); info();
    }

    // ---- egér -----------------------------------------------------------------------
    const pos = (e) => { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    // két ujj (érintő): csippentés = nagyítás vízszintesen és függőlegesen külön, húzás = görgetés
    const touches = new Map();
    let pinch = null;
    function pinchState() {
      const [a, b] = [...touches.values()];
      return { mx: (a[0] + b[0]) / 2, my: (a[1] + b[1]) / 2, dx: Math.abs(a[0] - b[0]), dy: Math.abs(a[1] - b[1]) };
    }
    cv.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'touch') {
        touches.set(e.pointerId, pos(e));
        if (touches.size === 2) {                   // a második ujj: a megkezdett művelet elmarad
          if (drag && (drag.kind === 'move' || drag.kind === 'len') && undoStack.length) { if (drag.created) song.notes.pop(); restoreQuiet(undoStack.pop()); }
          drag = null;
          pinch = pinchState();
          return;
        }
        if (touches.size > 2) return;
      }
      if (!song || e.button !== 0) return;
      try { cv.setPointerCapture(e.pointerId); } catch (err) { /* (szimulált esemény) */ }
      const [x, y] = pos(e);
      if (y < RULER) {                              // a vonalzó: a meghallgatás kezdete
        playTick = Math.max(0, snap(tOf(Math.max(KEYW, x))));
        if (audio) { stopAudio(); playAudio(); }
        draw();
        return;
      }
      if (x < KEYW) return;
      const h = hit(x, y);
      const drawMode = $('ndModeDraw').checked;
      if (h) {
        if (e.shiftKey) { if (sel.has(h.nt)) sel.delete(h.nt); else sel.add(h.nt); draw(); info(); return; }
        if (!sel.has(h.nt)) { sel = new Set([h.nt]); }
        mark();
        drag = { kind: h.edge ? 'len' : 'move', x0: x, y0: y, t0: tOf(x), n0: nOf(y),
          orig: [...sel].map((nt) => [nt, nt.t, nt.n, nt.d]), moved: false };
      } else if (drawMode) {
        mark();
        const t = Math.max(0, Math.floor(tOf(x) / gridTicks()) * gridTicks());
        const nt = { ch: target, n: clamp(nOf(y), 0, 127), t, d: gridTicks() >= 2 ? gridTicks() : song.division, v: +$('ndVel').value || 100 };
        song.notes.push(nt);
        sel = new Set([nt]);
        drag = { kind: 'len', x0: x, y0: y, t0: tOf(x), n0: nt.n, orig: [[nt, nt.t, nt.n, nt.d]], moved: true, created: true };
        renderChannels();
      } else {
        if (!e.shiftKey) sel.clear();
        drag = { kind: 'box', x0: x, y0: y, x1: x, y1: y, base: new Set(sel) };
      }
      draw(); info();
    });
    cv.addEventListener('pointermove', (e) => {
      if (!song) return;
      if (e.pointerType === 'touch' && touches.has(e.pointerId)) {
        touches.set(e.pointerId, pos(e));
        if (pinch && touches.size === 2) {
          const s = pinchState();
          if (pinch.dx > 30 && s.dx > 0) zoomX(s.dx / pinch.dx, s.mx);
          if (pinch.dy > 30 && s.dy > 0) zoomY(s.dy / pinch.dy, s.my);
          view.t0 = Math.max(0, view.t0 - (s.mx - pinch.mx) / view.ppt);
          view.top = clamp(Math.round(view.top + (s.my - pinch.my) / view.kh), 12, 127);
          pinch = s;
          draw();
          return;
        }
      }
      const [x, y] = pos(e);
      if (!drag) {
        const h = x >= KEYW && y >= RULER ? hit(x, y) : null;
        hover = h;
        cv.style.cursor = h ? (h.edge ? 'ew-resize' : 'move') : ($('ndModeDraw').checked ? 'crosshair' : 'default');
        draw();
        return;
      }
      if (drag.kind === 'box') {
        drag.x1 = x; drag.y1 = y;
        const ta = tOf(Math.min(drag.x0, x)), tb = tOf(Math.max(drag.x0, x));
        const na = nOf(Math.max(drag.y0, y)), nb = nOf(Math.min(drag.y0, y));
        sel = new Set(drag.base);
        for (const nt of song.notes) {
          if (hidden.has(nt.ch)) continue;
          if (nt.t + nt.d >= ta && nt.t <= tb && nt.n >= na && nt.n <= nb) sel.add(nt);
        }
        draw(); info();
        return;
      }
      const dt = tOf(x) - drag.t0, dn = nOf(y) - drag.n0;
      if (!drag.moved && Math.abs(x - drag.x0) < 3 && Math.abs(y - drag.y0) < 3) return;
      drag.moved = true;
      const g = gridTicks();
      if (drag.kind === 'move') {
        const minT = Math.min(...drag.orig.map((o) => o[1]));
        const sdt = Math.max(-minT, Math.round(dt / g) * g);
        for (const [nt, t, n] of drag.orig) { nt.t = t + sdt; nt.n = clamp(n + dn, 0, 127); }
      } else {
        for (const [nt, t, , d] of drag.orig) nt.d = Math.max(1, drag.created ? Math.max(g, snap(tOf(x)) - t) : Math.round((d + dt) / g) * g || g);
      }
      draw();
    });
    const endDrag = (e) => {
      if (e && e.pointerType === 'touch') {
        touches.delete(e.pointerId);
        if (pinch) { if (touches.size < 2) pinch = null; drag = null; return; }
      }
      if (drag && (drag.kind === 'move' || drag.kind === 'len') && !drag.moved) undoStack.pop();   // csak kattintás volt
      drag = null;
      draw(); info();
    };
    cv.addEventListener('pointerup', endDrag);
    cv.addEventListener('pointercancel', endDrag);
    cv.addEventListener('dblclick', (e) => {
      const [x, y] = pos(e);
      if (y < RULER || x < KEYW) return;
      const h = hit(x, y);
      if (h) { sel = new Set([h.nt]); del(); return; }
      if ($('ndModeDraw').checked) return;          // rajzolásnál a kattintás már tett hangot
      mark();
      const t = Math.max(0, Math.floor(tOf(x) / gridTicks()) * gridTicks());
      const nt = { ch: target, n: clamp(nOf(y), 0, 127), t, d: gridTicks() >= 2 ? gridTicks() : song.division, v: +$('ndVel').value || 100 };
      song.notes.push(nt);
      sel = new Set([nt]);
      renderChannels(); draw(); info();
    });
    cv.addEventListener('wheel', (e) => {
      if (!song) return;
      e.preventDefault();
      const [x] = pos(e);
      const [, y] = pos(e);
      if (e.altKey) {                               // függőleges nagyítás az egér körül
        zoomY(e.deltaY < 0 ? 1.15 : 1 / 1.15, y);
      } else if (e.ctrlKey || e.metaKey) {          // vízszintes nagyítás az egér körül
        zoomX(e.deltaY < 0 ? 1.25 : 0.8, x);
      } else if (e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        view.t0 = Math.max(0, view.t0 + (e.deltaX || e.deltaY) / view.ppt);
      } else {
        view.top = clamp(view.top + (e.deltaY < 0 ? 2 : -2), 12, 127);
      }
      draw();
    }, { passive: false });

    // ---- billentyűk ------------------------------------------------------------------
    dlg.addEventListener('keydown', (e) => {
      if (!song || /^(INPUT|SELECT|TEXTAREA)$/.test(e.target.tagName) && e.target.type !== 'radio' && e.target.type !== 'checkbox') return;
      const k = e.key, ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && (k === 'z' || k === 'Z')) { e.preventDefault(); if (e.shiftKey) redo(); else undo(); }
      else if (ctrl && (k === 'y' || k === 'Y')) { e.preventDefault(); redo(); }
      else if (ctrl && (k === 'a' || k === 'A')) { e.preventDefault(); sel = new Set(song.notes.filter((n) => !hidden.has(n.ch))); draw(); info(); }
      else if (k === 'Delete' || k === 'Backspace') { e.preventDefault(); del(); }
      else if (k === 'ArrowUp') { e.preventDefault(); transpose(e.shiftKey ? 12 : 1); }
      else if (k === 'ArrowDown') { e.preventDefault(); transpose(e.shiftKey ? -12 : -1); }
      else if (k === 'ArrowRight') { e.preventDefault(); moveTime(gridTicks()); }
      else if (k === 'ArrowLeft') { e.preventDefault(); moveTime(-gridTicks()); }
      else if (k === 'k' || k === 'K') { e.preventDefault(); setOff(![...sel].every((n) => n.off)); }
      else if (k === 'm' || k === 'M') { e.preventDefault(); setPrio(1); }
      else if (k === 'n' || k === 'N') { e.preventDefault(); setPrio(0); }
      else if (k === 'h' || k === 'H') { e.preventDefault(); setPrio(-1); }
      else if (k === ' ') { e.preventDefault(); if (audio) stopAudio(); else playAudio(); }
    });

    // ---- meghallgatás: a TVC szimulációja a fő oldal beállításaival -----------------------
    function editedParsed() { return M.parseMidi(M.writeMidi(song)); }
    function playAudio() {
      stopAudio();
      opts.stopMain();
      let r;
      const o = Object.assign({}, opts.options(), { from: null, to: null, trim: false });
      // a szerkesztőben új csatornák is szóljanak (ami a fő oldalon ki van kapcsolva, az nem)
      const known = new Set((opts.current() && opts.current().channels) || []);
      const chs = new Set(o.channels);
      for (const ch of channels()) if (!known.has(ch + 1)) chs.add(ch + 1);
      o.channels = [...chs].sort((a, b) => a - b);
      try { r = M.convertMidi(editedParsed(), o); }
      catch (err) { msg('A dal nem alakítható át: ' + err.message, true); return; }
      if (r.tooBig) msg('Figyelem: így a dal nem fér el a TVC-n (a meghallgatás ettől még szól).', true);
      const sim = PV.simulate(r.song, r.mode, 44100);
      let ctx;
      try { ctx = audioCtx || (audioCtx = new (window.AudioContext || window.webkitAudioContext)()); }
      catch (err) { msg('A böngésző nem tud hangot lejátszani.', true); return; }
      if (ctx.state === 'suspended') ctx.resume();
      const data = PV.toAudio(sim.levels);
      const buf = ctx.createBuffer(1, data.length, Math.round(sim.rate));
      buf.copyToChannel(data, 0);
      const src = ctx.createBufferSource();
      src.buffer = buf; src.connect(ctx.destination);
      const conv = tempoConv(), speed = o.speed || 1;
      const off = clamp(conv(playTick) / speed, 0, Math.max(0, buf.duration - 0.05));
      const t0 = ctx.currentTime - off;
      src.start(0, off);
      audio = { src, tick: playTick, raf: 0 };
      src.onended = () => { if (audio && audio.src === src) stopAudio(); };
      // a lejátszás helye tickben (a tempótérkép inverze, bináris kereséssel)
      const end = endTick();
      const toTick = (sec) => { let lo = 0, hi = Math.max(1, end); while (lo < hi) { const m = (lo + hi + 1) >> 1; if (conv(m) / speed <= sec) lo = m; else hi = m - 1; } return lo; };
      const step = () => {
        if (!audio || audio.src !== src) return;
        audio.tick = toTick(ctx.currentTime - t0);
        const { w } = cv.getBoundingClientRect();
        if (xOf(audio.tick) > w - 40) view.t0 = audio.tick - 40 / view.ppt;   // a nézet követi
        draw();
        audio.raf = requestAnimationFrame(step);
      };
      step();
      $('ndPlay').textContent = '■ Leállítás';
    }
    let audioCtx = null;
    function stopAudio() {
      if (!audio) return;
      const a = audio; audio = null;
      cancelAnimationFrame(a.raf);
      try { a.src.onended = null; a.src.stop(); } catch (e) { /* már leállt */ }
      $('ndPlay').textContent = '▶ Meghallgatás';
      draw();
    }

    // ---- gombok --------------------------------------------------------------------------
    $('ndNew').addEventListener('click', () => {
      if (dirty && song && song.notes.length && !confirm('Az eddigi szerkesztés elvész. Új, üres dal?')) return;
      stopAudio();
      newSong();
    });
    $('ndUndo').addEventListener('click', undo);
    $('ndRedo').addEventListener('click', redo);
    $('ndFit').addEventListener('click', () => { fit(); draw(); });
    $('ndZoomXIn').addEventListener('click', () => { zoomX(1.5); draw(); });
    $('ndZoomXOut').addEventListener('click', () => { zoomX(1 / 1.5); draw(); });
    $('ndZoomYIn').addEventListener('click', () => { zoomY(1.3); draw(); });
    $('ndZoomYOut').addEventListener('click', () => { zoomY(1 / 1.3); draw(); });
    $('ndZoomX').addEventListener('input', () => { zoomX(fromSlider(+$('ndZoomX').value, PPT_MIN, PPT_MAX) / view.ppt); draw(); });
    $('ndZoomY').addEventListener('input', () => { zoomY(fromSlider(+$('ndZoomY').value, KH_MIN, KH_MAX) / view.kh); draw(); });
    $('ndGrid').addEventListener('change', draw);
    $('ndPlay').addEventListener('click', () => { if (audio) stopAudio(); else playAudio(); });
    $('ndSave').addEventListener('click', () => {
      const bytes = M.writeMidi(song);
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([bytes], { type: 'audio/midi' }));
      a.download = name.replace(/\.[^.]*$/, '') + '.mid';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      msg('Mentve: ' + a.download + ' (a kihagyott hangok nélkül).');
    });
    $('ndApply').addEventListener('click', () => {
      stopAudio();
      song.src = opts.apply(M.writeMidi(song), name);
      dirty = false;
      cleanAt = undoStack.length;
      computePlayed();
      draw(); info();
      msg('A szerkesztett dal a konverterben van: az előnézet és a .cas már ebből készül.');
    });
    $('ndClose').addEventListener('click', () => {
      if (dirty && !confirm('A módosítások nincsenek a konverterben (Használat a konverterben). Bezárod így?')) return;
      dlg.close();
    });
    dlg.addEventListener('close', stopAudio);
    $('ndUp1').addEventListener('click', () => transpose(1));
    $('ndDown1').addEventListener('click', () => transpose(-1));
    $('ndUp12').addEventListener('click', () => transpose(12));
    $('ndDown12').addEventListener('click', () => transpose(-12));
    $('ndOff').addEventListener('click', () => setOff(true));
    $('ndPrioHi').addEventListener('click', () => setPrio(1));
    $('ndPrioNorm').addEventListener('click', () => setPrio(0));
    $('ndPrioLo').addEventListener('click', () => setPrio(-1));
    $('ndOn').addEventListener('click', () => setOff(false));
    $('ndDel').addEventListener('click', del);
    $('ndVelSet').addEventListener('click', () => setVel(+$('ndVel').value));
    $('ndAddCh').addEventListener('change', () => {
      const v = $('ndAddCh').value;
      if (v === '') return;
      const ch = +v;
      mark();
      if (ch !== 9) song.ctrl.unshift([0, 'prog', ch, 0, 0]);
      target = ch;
      renderChannels(); info();
      if (ch === 9) msg('A 10. csatorna a dob: a hang magassága választja a dobot (pl. 36 lábdob, 38 pergő, 42 cin).');
    });
    window.addEventListener('resize', () => { if (dlg.open) draw(); });

    return {
      open(fresh) {
        const cur = opts.current();
        if (fresh || !cur) newSong();
        else if (!song || !dirty || song.src !== cur.parsed) {
          load(M.songFromParsed(cur.parsed), cur.name);
          song.src = cur.parsed;
        }
        dlg.showModal();
        fit(); computePlayed();
        renderChannels(); draw(); info();
        if (!fresh) msg('Kattintás egy hangon: kijelölés; a kijelölt hang húzható. A kezelés részletei a tekercs alatti „Súgó”-ban.');
        cv.focus();
      },
    };
  }

  const api = { NoteEditor, noteName };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.TvcNoteEditor = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
