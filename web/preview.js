// preview.js - a két TVC lejátszó szimulációja a böngészőben (előnézet).
// A song.bin-t ugyanúgy értelmezi, mint a player.asm / player_poly.asm:
//   poly: mintára pontosan (fázisakkumulátorok, LFSR, keverőtábla,
//         képkockánkénti tick), a lejátszó effektív mintafrekvenciáján
//   mono/arp: tickenként a lejátszó állapotgépe, a hang a hardveres
//         négyszög (f = 195312,5 / (4096 - PITCH)) és a dobok zajlöketei
// Eredmény: {levels: Float32Array (0..15), rate, roll: [[{v, note, vol}]]}
(function (root) {
  'use strict';
  const M = root.Midi2Tvc || (typeof require !== 'undefined' ? require('./midi2tvc.js') : null);
  const FRAME = M.FRAME_RATE;
  const MAX_SECONDS = 15 * 60;

  function lfsrStep(s) {                      // 16 bites Galois, B400h
    const out = s & 1;
    s >>= 1;
    if (out) s ^= 0xB400;
    return s;
  }

  // ---- többszólamú lejátszó ---------------------------------------------------
  function simulatePoly(song) {
    const [sr] = M.polyRates();
    const flags = song[0], decay = song[1], floor = song[2];
    const loopOff = song[4] | (song[5] << 8);
    const mix = song.subarray(8, 72);
    const F = (n) => song[72 + 2 * n] | (song[73 + 2 * n] << 8);
    const EV = 328;
    let ptr = EV, wait = 0, done = false;
    const loopPtr = EV + loopOff;
    const vs = [0, 1, 2].map(() => ({ f: 0, slide: 0, vol: 0, dec: 0, cnt: 0, floor: 0, note: -1, drum: false }));
    let noiseVol = 0, noiseDec = 0, noiseCnt = 0;
    let loops = 0;

    function events() {
      if (wait) { wait--; if (wait) return; }
      for (let guard = 0; guard < 100000; guard++) {
        const a = song[ptr++];
        if (a === undefined) { done = true; return; }
        if (a >= 0xC0) {
          if (a === 0xFF) {
            if (flags & 1) { if (++loops > 1) { done = true; return; } ptr = loopPtr; continue; }
            ptr--; done = true; return;
          }
          wait = a - 0xBF; return;
        }
        if (a < 0x80) continue;
        if (a < 0xB0) {
          const v = vs[(a >> 4) & 3], n = song[ptr++];
          v.vol = a & 15; v.f = F(n); v.slide = 0; v.dec = decay; v.cnt = decay; v.floor = floor;
          v.note = n; v.drum = false;
        } else if (a < 0xB3) vs[a - 0xB0].vol = 0;
        else if (a === 0xB4) {
          const b = song[ptr++];
          noiseDec = b & 15; noiseCnt = noiseDec; noiseVol = b >> 4;
        } else if (a >= 0xB8 && a < 0xBB) {
          const v = vs[a - 0xB8], n = song[ptr++], b = song[ptr++];
          v.f = F(n); v.dec = b & 15; v.cnt = v.dec; v.vol = b >> 4; v.floor = 0;
          v.slide = song[ptr] | (song[ptr + 1] << 8); ptr += 2;
          v.note = n; v.drum = true;
        } else if (a === 0xBF) {
          wait = song[ptr] | (song[ptr + 1] << 8); ptr += 2; return;
        }
      }
    }
    function voices() {
      for (const v of vs) {
        v.f = (v.f + v.slide) & 0xFFFF;
        if (v.dec) {
          if (--v.cnt === 0) { v.cnt = v.dec; if (v.vol > v.floor) v.vol--; }
        }
      }
      if (noiseDec) {
        if (--noiseCnt === 0) { noiseCnt = noiseDec; if (noiseVol) noiseVol--; }
      }
    }
    const perFrame = sr / FRAME;
    const maxFrames = Math.ceil(MAX_SECONDS * FRAME);
    const chunks = [], roll = [];
    let acc = [0, 0, 0], lfsr = 0xACE1, frac = 0, frame = 0;
    // a hurok előtt egy tick (mint a player_poly.asm-ben)
    events(); voices();
    while (!done && frame < maxFrames) {
      frac += perFrame;
      const n = Math.floor(frac);
      frac -= n;
      const buf = new Uint8Array(n);
      const f0 = vs[0].f, f1 = vs[1].f, f2 = vs[2].f;
      const v0 = vs[0].vol, v1 = vs[1].vol, v2 = vs[2].vol, nv = noiseVol;
      for (let i = 0; i < n; i++) {
        acc[0] = (acc[0] + f0) & 0xFFFF;
        acc[1] = (acc[1] + f1) & 0xFFFF;
        acc[2] = (acc[2] + f2) & 0xFFFF;
        lfsr = lfsrStep(lfsr);
        const s = ((acc[0] & 0x8000) ? v0 : 0) + ((acc[1] & 0x8000) ? v1 : 0) +
          ((acc[2] & 0x8000) ? v2 : 0) + ((lfsr & 0xFF) & nv);
        buf[i] = mix[s];
      }
      chunks.push(buf);
      roll.push(vs.map((v, i) => ({ v: i, note: v.note, vol: v.vol, drum: v.drum }))
        .filter((x) => x.vol > 0 && x.note >= 0).concat(nv ? [{ v: 3, note: -1, vol: nv, drum: true }] : []));
      events(); voices();
      frame++;
    }
    return { levels: join(chunks), rate: sr, roll, frames: frame };
  }

  // ---- egycsatornás lejátszó (player.asm) ---------------------------------------
  function simulateMono(song, outRate) {
    const flags = song[0], arpSpeed = song[1] || 1, decay = song[2], floor = song[3];
    const loopOff = song[4] | (song[5] << 8), kitOff = song[6] | (song[7] << 8);
    const P = (n) => song[8 + 2 * n] | (song[9 + 2 * n] << 8);
    const EV = 264;
    let ptr = EV, wait = 0, done = false, loops = 0;
    const loopPtr = EV + loopOff;
    let arpN = 0, arpI = 0, arpCnt = 0, envCnt = 0, curVol = 0, noteVol = 12;
    const arpNotes = [0, 0, 0, 0];
    let shPitch = 0;
    let drumOn = false, drumPtr = 0, drumAtt = 0;
    const hw = { pitch: 0, osc: false, vol: 0 };
    let burst = 0, burstVol = 0;               // zajlöket: hossz (s), hangerő

    const setNote = (n) => { shPitch = P(n); if (!drumOn) { hw.pitch = shPitch; hw.osc = true; } };
    const setVol = (v) => { if (!drumOn) hw.vol = v; };
    const soundOff = () => { arpN = 0; drumOn = false; curVol = 0; hw.vol = 0; hw.osc = false; };
    const atten = (a) => Math.max(0, a - drumAtt);
    function drumStart(k, att) {
      if (!kitOff || k >= song[kitOff]) return;
      drumPtr = song[kitOff + 1 + 2 * k] | (song[kitOff + 2 + 2 * k] << 8);
      drumAtt = att; drumOn = true;
    }
    function parse() {
      for (let guard = 0; guard < 100000; guard++) {
        const a = song[ptr++];
        if (a === undefined) { done = true; return; }
        if (a < 0x80) { arpNotes[0] = a; startNotes(1); continue; }
        if (a === 0x80) { arpN = 0; curVol = 0; setVol(0); continue; }
        if (a < 0x90) {
          const n = a & 7;
          for (let i = 0; i < n; i++) arpNotes[i] = song[ptr++];
          startNotes(n); continue;
        }
        if (a < 0xA0) { noteVol = a & 15; continue; }
        if (a === 0xA0) { wait = song[ptr] | (song[ptr + 1] << 8); ptr += 2; return; }
        if (a < 0xC0) { const att = song[ptr++]; drumStart(a - 0xA1, att); continue; }
        if (a === 0xFF) {
          if (flags & 1) { if (++loops > 1) { done = true; return; } ptr = loopPtr; continue; }
          ptr--; soundOff(); done = true; return;
        }
        wait = a - 0xBF; return;
      }
    }
    function startNotes(n) {
      arpN = n; arpI = 0; arpCnt = arpSpeed; envCnt = decay;
      setNote(arpNotes[0]);
      curVol = noteVol; setVol(curVol);
    }
    function effects() {
      if (arpN >= 2 && --arpCnt === 0) {
        arpCnt = arpSpeed;
        arpI = (arpI + 1) % arpN;
        setNote(arpNotes[arpI]);
      }
      if (!decay || !arpN) return;
      if (--envCnt) return;
      envCnt = decay;
      if (curVol > floor) { curVol--; setVol(curVol); }
    }
    function tick() {
      if (wait) { wait--; if (wait) { effects(); return; } }
      parse();
    }
    function drumStep() {
      burst = 0;
      if (!drumOn) return;
      const tv = song[drumPtr];
      if (tv === 0xFF || tv === undefined) {
        drumOn = false; hw.pitch = shPitch; hw.osc = true; hw.vol = curVol; return;
      }
      const lo = song[drumPtr + 1], hi = song[drumPtr + 2], nz = song[drumPtr + 3];
      drumPtr += 4;
      const vol = atten(tv);
      if (hi !== 0xFF) { hw.pitch = lo | (hi << 8); hw.osc = true; hw.vol = vol; }
      else hw.vol = 0;
      const len = nz & 15, nv = atten(nz >> 4);
      if (len && nv) { burst = len * 48 * 79 / M.CPU_CLOCK; burstVol = nv; }
    }

    const perFrame = outRate / FRAME;
    const maxFrames = Math.ceil(MAX_SECONDS * FRAME);
    const chunks = [], roll = [];
    let phase = 0, frac = 0, frame = 0, lfsr = 0xACE1;
    while (!done && frame < maxFrames) {
      tick();
      drumStep();
      frac += perFrame;
      const n = Math.floor(frac);
      frac -= n;
      const buf = new Uint8Array(n);
      const freq = M.TVC_CLOCK / (4096 - hw.pitch);
      const nb = Math.round(burst * outRate);
      for (let i = 0; i < n; i++) {
        if (i < nb) { lfsr = lfsrStep(lfsr); buf[i] = (lfsr & 1) ? burstVol : 0; continue; }
        if (hw.osc) {
          phase += freq / outRate;
          phase -= Math.floor(phase);
          buf[i] = phase < 0.5 ? hw.vol : 0;
        } else buf[i] = hw.vol;
      }
      chunks.push(buf);
      const r = [];
      if (drumOn) r.push({ v: 3, note: -1, vol: hw.vol || burstVol, drum: true });
      else if (arpN && curVol) r.push({ v: 0, note: arpNotes[arpI], vol: curVol, drum: false });
      roll.push(r);
      frame++;
    }
    return { levels: join(chunks), rate: outRate, roll, frames: frame };
  }

  function join(chunks) {
    let n = 0;
    for (const c of chunks) n += c.length;
    const out = new Uint8Array(n);
    let p = 0;
    for (const c of chunks) { out.set(c, p); p += c.length; }
    return out;
  }

  // 0..15 szintek -> hang (-1..1), egyenáram nélkül (a TVC kimenete is
  // kondenzátoron át megy a tévére)
  function toAudio(levels, gain = 0.55) {
    const out = new Float32Array(levels.length);
    let xp = 0, yp = 0;
    for (let i = 0; i < levels.length; i++) {
      const x = levels[i] / 15;
      const y = x - xp + 0.995 * yp;
      xp = x; yp = y;
      out[i] = y * gain;
    }
    return out;
  }

  function simulate(song, mode, outRate) {
    return mode === 'poly' ? simulatePoly(song) : simulateMono(song, outRate || 44100);
  }

  const api = { simulate, toAudio };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.TvcPreview = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
