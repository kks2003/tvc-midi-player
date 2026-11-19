// tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
// Copyright (C) 2026 kks2003 és a közreműködők
//
// Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
// Foundation által kiadott GNU General Public License 2. vagy (választás
// szerint) bármely későbbi változata szerint. A programot a hasznosság
// reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
//
// Burkológörbe-szerkesztő a midiplay envelope.txt formátumához (Varga István
// midiplay programja, GPL 2): a fájl hangszer-blokkokra bontva szerkeszthető,
// a görbe rajzon látszik, és a TVC többszólamú lejátszójának szimulációjával
// meghallgatható. A szöveg <-> modell átalakítás: parseEnvText / envText.
(function (root) {
  'use strict';

  // ---- szöveg -> modell ---------------------------------------------------------
  // modell: [{progs: [{n, flags, layer}], segs: [{mark, len, l, r, pitch, dist}]}]
  // l, r: {mult: bool, v}; mark: '' | 'L' | 'R' | 'S'
  function parseEnvText(text) {
    let buf = '', comment = false;
    for (const c of text) {
      if (comment && c !== '\r' && c !== '\n' && c !== '\0') continue;
      comment = false;
      if (c.codePointAt(0) <= 32) continue;
      if (c === '#') { comment = true; continue; }
      buf += c;
    }
    let pos = 0;
    const fail = (m) => { throw new Error(m + ' (a ' + (pos + 1) + '. jelnél)'); };
    const peek = () => buf[pos] || '';
    const num = () => {
      const m = /^[+-]?\d+/.exec(buf.slice(pos));
      if (!m) fail('számot vártam');
      pos += m[0].length;
      return parseInt(m[0], 10);
    };
    const want = (ch) => { if (buf[pos] !== ch) fail('„' + ch + '” jelet vártam'); pos++; };
    const vol = () => {
      const mult = peek() === '*';
      if (mult) pos++;
      return { mult, v: num() };
    };
    const blocks = [];
    while (pos < buf.length) {
      const progs = [];
      for (;;) {
        const p = { n: num(), flags: '', layer: null };
        while (/[pdPD]/.test(peek())) p.flags += buf[pos++].toUpperCase();
        if (peek() === ':') { pos++; const c = num(); want(','); p.layer = [c, num()]; }
        progs.push(p);
        if (peek() === '{') { pos++; break; }
        want(',');
      }
      const segs = [];
      while (peek() !== '}') {
        if (!peek()) fail('hiányzik a „}”');
        let mark = '';
        if (/[lrsLRS]/.test(peek())) mark = buf[pos++].toUpperCase();
        const len = num(); want(',');
        const l = vol(); want(',');
        const r = vol(); want(',');
        const pitch = num(); want(',');
        const dist = num(); want(';');
        segs.push({ mark, len, l, r, pitch, dist });
      }
      pos++;
      blocks.push({ progs, segs });
    }
    return blocks;
  }

  // ---- modell -> szöveg ---------------------------------------------------------
  const volText = (x) => (x.mult ? '*' : '') + x.v;
  function envText(blocks, names) {
    const lines = ['# Hangszer-burkológörbék (midiplay envelope.txt formátum)',
      '# sor: [L|R|S] hossz (1/50 s), bal, jobb hangerő (0..63, *n = szorzás n/128-cal), hangmagasság, torzítás;',
      '# L = ismétlés eleje, R = ismétlés vége / elengedés, S = egy képkockán kitart;',
      '# a program száma után D: az elengedés után végigfut, P: hangmagasság szerinti panoráma', ''];
    for (const b of blocks) {
      const head = b.progs.map((p) => p.n + p.flags + (p.layer ? ':' + p.layer.join(',') : '')).join(', ');
      const label = b.progs.map((p) => names(p.n)).join(', ');
      lines.push(head + ' {' + (label ? '   # ' + label : ''));
      for (const s of b.segs) {
        lines.push((s.mark || ' ') + ' ' + String(s.len).padStart(3) + ', ' + volText(s.l).padStart(4) + ', ' +
          volText(s.r).padStart(4) + ', ' + s.pitch + ', ' + s.dist + ';');
      }
      lines.push('}', '');
    }
    return lines.join('\n');
  }

  // ---- a szerkesztő ---------------------------------------------------------------
  // opts: {M, PV, gmName(n), sources: () => [[érték, felirat, szöveg]], apply(name, text), status(t, bad)}
  function EnvEditor(opts) {
    const { M, PV } = opts;
    const $ = (id) => document.getElementById(id);
    const dlg = $('envDlg');
    const KEY = 'tvcmidi.envEditor';
    let blocks = [], sel = 0, ctx = null, src = null, fileName = 'szerkesztett';

    const names = (n) => (n < 0 ? 'Dob ' + (-n) : opts.gmName(n));
    const save = () => { try { localStorage.setItem(KEY, JSON.stringify({ text: envText(blocks, names), fileName })); } catch (e) { /* nincs tároló */ } };
    const msg = (t, bad) => { const el = $('eeMsg'); el.textContent = t || ''; el.classList.toggle('bad', !!bad); };

    function load(text, name) {
      blocks = parseEnvText(text);
      if (name) fileName = name;
      sel = 0;
      renderList();
      renderBlock();
      save();
    }
    // a szerkesztett szöveg érvényes-e (a konverter fordítójával)
    function compiled() {
      const text = envText(blocks, names);
      try { return [M.compileEnvelopes(text), text, null]; } catch (e) { return [null, text, e.message]; }
    }

    function renderList() {
      const ul = $('eeList');
      ul.textContent = '';
      blocks.forEach((b, i) => {
        const li = document.createElement('li');
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = i === sel ? 'on' : '';
        const nums = b.progs.map((p) => p.n).join(', ');
        btn.textContent = nums + ' · ' + b.progs.map((p) => names(p.n)).join(', ');
        btn.title = btn.textContent;
        btn.addEventListener('click', () => { sel = i; renderList(); renderBlock(); });
        li.appendChild(btn);
        ul.appendChild(li);
      });
      $('eeCount').textContent = blocks.length + ' hangszer';
    }

    function renderBlock() {
      const b = blocks[sel];
      $('eeBlock').hidden = !b;
      if (!b) { drawGraph(); return; }
      $('eeProgs').value = b.progs.map((p) => p.n + p.flags.replace(/D/g, '') + (p.layer ? ':' + p.layer.join(',') : '')).join(', ');
      $('eeDecay').checked = b.progs.some((p) => p.flags.includes('D'));
      $('eeNames').textContent = b.progs.map((p) => names(p.n)).join(', ');
      const tb = $('eeSegs');
      tb.textContent = '';
      b.segs.forEach((s, i) => {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td><select aria-label="Jel"><option value="">–</option><option>L</option><option>R</option><option>S</option></select></td>' +
          '<td><input type="number" min="0" max="255" aria-label="Hossz"></td><td><input type="text" aria-label="Bal hangerő"></td>' +
          '<td><input type="text" aria-label="Jobb hangerő"></td><td><input type="number" min="-2048" max="2047" aria-label="Hangmagasság"></td>' +
          '<td><input type="number" min="0" max="255" step="16" aria-label="Torzítás"></td>' +
          '<td class="rowbtns"><button type="button" title="Fel">↑</button><button type="button" title="Le">↓</button><button type="button" title="Törlés">✕</button></td>';
        const [mk, ln, l, r, pt, ds] = tr.querySelectorAll('select, input');
        mk.value = s.mark; ln.value = s.len; l.value = volText(s.l); r.value = volText(s.r); pt.value = s.pitch; ds.value = s.dist;
        const parseVol = (t) => { const m = /^\s*(\*)?\s*(\d+)\s*$/.exec(t); return m ? { mult: !!m[1], v: +m[2] } : null; };
        const upd = () => {
          const lv = parseVol(l.value), rv = parseVol(r.value);
          l.classList.toggle('bad', !lv); r.classList.toggle('bad', !rv);
          if (!lv || !rv) return;
          Object.assign(s, { mark: mk.value, len: +ln.value || 0, l: lv, r: rv, pitch: +pt.value || 0, dist: +ds.value || 0 });
          changed();
        };
        for (const el of [mk, ln, l, r, pt, ds]) el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', upd);
        const [up, down, del] = tr.querySelectorAll('.rowbtns button');
        up.disabled = i === 0;
        down.disabled = i === b.segs.length - 1;
        up.addEventListener('click', () => { b.segs.splice(i - 1, 0, b.segs.splice(i, 1)[0]); renderBlock(); changed(); });
        down.addEventListener('click', () => { b.segs.splice(i + 1, 0, b.segs.splice(i, 1)[0]); renderBlock(); changed(); });
        del.addEventListener('click', () => { b.segs.splice(i, 1); renderBlock(); changed(); });
        tb.appendChild(tr);
      });
      drawGraph();
    }

    function changed() {
      save();
      const [env, , err] = compiled();
      msg(err ? 'Hibás görbe: ' + err + '.' : '', !!err);
      $('eeApply').disabled = !!err;
      $('eeSave').disabled = !!err;
      drawGraph(env);
    }

    // a programszámok mezője: "0, 24P, 25:1,0" (a D a jelölőnégyzetből)
    function readProgs() {
      const b = blocks[sel];
      const re = /\s*([+-]?\d+)\s*([pP]?)\s*(?::\s*([+-]?\d+)\s*,\s*([+-]?\d+))?\s*(,|$)/y;
      const v = $('eeProgs').value, progs = [];
      let ok = true;
      re.lastIndex = 0;
      while (re.lastIndex < v.length) {
        const m = re.exec(v);
        if (!m || +m[1] < -127 || +m[1] > 127) { ok = false; break; }
        progs.push({ n: +m[1], flags: (m[2] ? 'P' : '') + ($('eeDecay').checked ? 'D' : ''), layer: m[3] !== undefined ? [+m[3], +m[4]] : null });
        if (!m[5]) break;
      }
      if (!ok || !progs.length || new Set(progs.map((p) => p.n < 0)).size > 1) { $('eeProgs').classList.add('bad'); return; }
      $('eeProgs').classList.remove('bad');
      b.progs = progs;
      $('eeNames').textContent = progs.map((p) => names(p.n)).join(', ');
      renderList();
      changed();
    }

    // ---- rajz: a görbe képkockánként, a lenyomás vége és a lecsengés ----------------
    function drawGraph(env) {
      const cv = $('eeGraph'), g = cv.getContext('2d');
      const dpr = window.devicePixelRatio || 1, W = cv.clientWidth, H = cv.clientHeight;
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      const css = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
      const b = blocks[sel];
      if (env === undefined) env = compiled()[0];
      const held = +$('eeHeld').value;
      $('eeHeldVal').textContent = held + ' képkocka (' + (held / 50).toFixed(2).replace('.', ',') + ' s)';
      if (!b || !env) return;
      const pg = b.progs[0].n;
      const e = env.get(pg);
      if (!e) {
        g.fillStyle = css('--muted'); g.font = '12px ' + css('--font-mono');
        g.fillText(pg < 0 ? 'dob: a TVC-n a saját dobkészlet szól' : '', 8, 18);
        return;
      }
      const lev = M.envelopeLevels(e, held);
      const frames = e[0].slice(0, -1);
      const n = Math.max(lev.length, held, 10) + 4;
      const pad = 22, x = (i) => pad + i * (W - pad - 6) / n, y = (v) => H - 16 - v * (H - 26) / 63;
      g.font = '10.5px ' + css('--font-mono');
      g.fillStyle = css('--line');
      for (const v of [0, 16, 32, 48, 63]) { g.fillRect(pad, Math.round(y(v)), W - pad - 6, 1); }
      g.fillStyle = css('--muted');
      for (const v of [0, 32, 63]) g.fillText(String(v), 2, y(v) + 4);
      const step = [1, 5, 10, 25, 50, 100, 250].find((s) => s * (W - pad) / n >= 40) || 500;
      for (let i = 0; i <= n; i += step) g.fillText((i / 50).toFixed(i % 50 ? 1 : 0) + ' s', x(i) + 2, H - 3);
      // a fájl képkockái (bal / jobb hangerő), L/R/S jelek
      const line = (arr, col, w) => {
        g.strokeStyle = col; g.lineWidth = w; g.beginPath();
        arr.forEach((v, i) => { const px = x(i), py = y(v); if (i) g.lineTo(px, py); else g.moveTo(px, py); g.lineTo(x(i + 1), py); });
        g.stroke();
      };
      line(frames.map((f) => f[0] & 0x3F), css('--v1'), 1);
      line(frames.map((f) => f[1]), css('--v2'), 1);
      frames.forEach((f, i) => {
        if (!(f[0] & 0xC0)) return;
        const m = { 0x40: 'L', 0x80: 'R', 0xC0: 'S' }[f[0] & 0xC0];
        g.fillStyle = css('--accent'); g.fillRect(Math.round(x(i)), 4, 1, H - 20);
        g.fillText(m, x(i) + 3, 13);
      });
      // a megszólaló hangerő: ezt a TVC kapja (a bal és jobb nagyobbika)
      g.globalAlpha = 0.25; g.fillStyle = css('--v0');
      lev.forEach((v, i) => g.fillRect(x(i), y(v), x(i + 1) - x(i) + 0.5, y(0) - y(v)));
      g.globalAlpha = 1;
      line(lev, css('--v0'), 2);
      // a billentyű elengedése
      g.fillStyle = css('--warn'); g.fillRect(Math.round(x(held)), 4, 2, H - 20);
      g.fillText('elengedés', x(held) + 4, 26);
    }

    // ---- meghallgatás: egy hang a TVC többszólamú lejátszójának szimulációjával -----
    function stopSound() { if (src) { try { src.stop(); } catch (e) { /* már leállt */ } src = null; } $('eePlay').textContent = '▶ Meghallgatás'; }
    function playSound() {
      if (src) { stopSound(); return; }
      const [env, text, err] = compiled();
      const b = blocks[sel];
      if (err || !b || b.progs[0].n < 0) return;
      const held = +$('eeHeld').value, note = +$('eeNote').value, vel = +$('eeVel').value;
      const t1 = Math.max(1, Math.round(held / 50 * 960));        // 120 BPM, 480 tick/negyed
      const parsed = { division: 480, events: [[0, 0, 'prog', 0, b.progs[0].n, 0], [0, 1, 'on', 0, note, vel], [t1, 2, 'off', 0, note, 0]] };
      try {
        const o = opts.options();
        const r = M.convertMidi(parsed, Object.assign({}, o, { mode: 'poly', channels: [1], drums: 'off', from: null, to: null,
          trim: false, loop: false, envelopes: { name: 'szerkesztett.txt', text } }));
        const sim = PV.simulate(r.song, 'poly', 44100);
        ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
        if (ctx.state === 'suspended') ctx.resume();
        const data = PV.toAudio(sim.levels);
        const buf = ctx.createBuffer(1, data.length, Math.round(sim.rate));
        buf.copyToChannel(data, 0);
        opts.stopMain();
        src = ctx.createBufferSource();
        src.buffer = buf;
        src.connect(ctx.destination);
        src.onended = () => { src = null; $('eePlay').textContent = '▶ Meghallgatás'; };
        src.start();
        $('eePlay').textContent = '■ Leállítás';
      } catch (e) { msg('Nem szólaltatható meg: ' + e.message + '.', true); }
      void env;
    }

    // ---- gombok -----------------------------------------------------------------------
    function fillSources() {
      const s = $('eeSrc');
      s.textContent = '';
      for (const [v, label] of opts.sources()) { const o = document.createElement('option'); o.value = v; o.textContent = label; s.appendChild(o); }
    }
    $('eeSrcLoad').addEventListener('click', () => {
      const v = $('eeSrc').value;
      if (blocks.length && !confirm('A szerkesztett görbék helyére betöltsem ezt a készletet?')) return;
      if (v === '') { blocks = [{ progs: [{ n: 0, flags: '', layer: null }], segs: [{ mark: '', len: 0, l: { mult: false, v: 62 }, r: { mult: false, v: 62 }, pitch: 0, dist: 0 }] }]; sel = 0; fileName = 'szerkesztett'; renderList(); renderBlock(); changed(); return; }
      const it = opts.sources().find((x) => x[0] === v);
      try { load(it[2], v === 'file' ? undefined : v + '-szerkesztett'); msg('Betöltve: ' + it[1] + '.'); } catch (e) { msg('Nem olvasható: ' + e.message + '.', true); }
    });
    $('eeOpen').addEventListener('click', () => $('eeFile').click());
    $('eeFile').addEventListener('change', (ev) => {
      const f = ev.target.files[0];
      ev.target.value = '';
      if (!f) return;
      f.text().then((text) => {
        try { M.compileEnvelopes(text); load(text, f.name.replace(/\.[^.]*$/, '')); msg('Betöltve: ' + f.name + '.'); }
        catch (e) { msg('A fájl hibás: ' + e.message + '.', true); }
      });
    });
    $('eeSave').addEventListener('click', () => {
      const [, text, err] = compiled();
      if (err) return;
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }));
      a.download = (M.asciiName(fileName) || 'envelope') + '.txt';
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      msg('Mentve: ' + a.download + '.');
    });
    $('eeApply').addEventListener('click', () => {
      const [, text, err] = compiled();
      if (err) return;
      opts.apply((M.asciiName(fileName) || 'szerkesztett') + '.txt', text);
      msg('A konverter mostantól ezekkel a görbékkel dolgozik.');
    });
    $('eeAdd').addEventListener('click', () => {
      const used = new Set(blocks.flatMap((b) => b.progs.map((p) => p.n)));
      let n = 0; while (used.has(n) && n < 127) n++;
      blocks.push({ progs: [{ n, flags: '', layer: null }], segs: [{ mark: '', len: 0, l: { mult: false, v: 62 }, r: { mult: false, v: 62 }, pitch: 0, dist: 0 },
        { mark: '', len: 25, l: { mult: false, v: 20 }, r: { mult: false, v: 20 }, pitch: 0, dist: 0 }] });
      sel = blocks.length - 1; renderList(); renderBlock(); changed();
    });
    $('eeDup').addEventListener('click', () => {
      if (!blocks[sel]) return;
      const c = JSON.parse(JSON.stringify(blocks[sel]));
      const used = new Set(blocks.flatMap((b) => b.progs.map((p) => p.n)));
      let n = c.progs[0].n; while (used.has(n) && n < 127) n++;
      c.progs = [{ n, flags: c.progs[0].flags, layer: null }];
      blocks.splice(sel + 1, 0, c); sel++; renderList(); renderBlock(); changed();
    });
    $('eeDel').addEventListener('click', () => {
      if (!blocks[sel] || !confirm('Törlöm ezt a hangszert?')) return;
      blocks.splice(sel, 1); sel = Math.min(sel, blocks.length - 1); renderList(); renderBlock(); changed();
    });
    $('eeSegAdd').addEventListener('click', () => {
      const b = blocks[sel]; if (!b) return;
      const last = b.segs[b.segs.length - 1];
      b.segs.push({ mark: '', len: 10, l: last ? { ...last.l } : { mult: false, v: 0 }, r: last ? { ...last.r } : { mult: false, v: 0 }, pitch: last ? last.pitch : 0, dist: last ? last.dist : 0 });
      renderBlock(); changed();
    });
    $('eeProgs').addEventListener('change', readProgs);
    $('eeDecay').addEventListener('change', readProgs);
    for (const id of ['eeHeld', 'eeNote', 'eeVel']) $(id).addEventListener('input', () => drawGraph());
    $('eePlay').addEventListener('click', playSound);
    $('eeClose').addEventListener('click', () => { stopSound(); dlg.close(); });
    dlg.addEventListener('close', stopSound);
    window.addEventListener('resize', () => { if (dlg.open) drawGraph(); });

    return {
      open() {
        fillSources();
        if (!blocks.length) {
          let st = null;
          try { st = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { /* nincs tároló */ }
          try {
            if (st && st.text) load(st.text, st.fileName);
            else { const s = opts.sources().find((x) => x[0] === 'midiplay'); load(s[2], 'midiplay-szerkesztett'); }
          } catch (e) { msg('A mentett szerkesztés nem olvasható: ' + e.message + '.', true); }
        }
        dlg.showModal();
        renderList();
        renderBlock();
        changed();
      },
    };
  }

  const api = { parseEnvText, envText, EnvEditor };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.TvcEnvEditor = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
