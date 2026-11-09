// midi2tvc.js - a midi2tvc.py JavaScript-portja (böngészőben és node-ban).
// A kimenete bájtra azonos a Python változatéval (test/web_parity.js
// ellenőrzi), ezért a függvények és a sorrendek a Python kódot követik.
// A .cas összeállításához a players.js (tools/export_players.py) kell.
(function (root) {
  'use strict';

  const TVC_CLOCK = 195312.5;
  const FRAME_RATE = 49.76;
  const DRUM_CHANNEL = 9;
  const CPU_CLOCK = 3125000.0;
  const POLY_LOOP_CYCLES = 271;
  const POLY_TICK_OVERHEAD = 1100;
  const POLY_VOICES = 3;

  // Python round(): a .5 a páros felé
  function pyRound(x) {
    const r = Math.round(x);
    if (Math.abs(x % 1) === 0.5) return 2 * Math.round(x / 2);
    return r;
  }
  const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
  // tömbök lexikografikus összehasonlítása (Python tuple)
  function cmpTuple(a, b) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return a.length - b.length;
  }
  // Python max(seq, key=...): az első legnagyobb
  function maxBy(seq, key) {
    let best = seq[0], bk = key(seq[0]);
    for (let i = 1; i < seq.length; i++) {
      const k = key(seq[i]);
      if (cmpTuple(k, bk) > 0) { best = seq[i]; bk = k; }
    }
    return best;
  }
  function minBy(seq, key) {
    let best = seq[0], bk = key(seq[0]);
    for (let i = 1; i < seq.length; i++) {
      const k = key(seq[i]);
      if (cmpTuple(k, bk) < 0) { best = seq[i]; bk = k; }
    }
    return best;
  }

  // ---- MIDI olvasás ---------------------------------------------------------
  function readVlq(data, pos) {
    let value = 0;
    for (;;) {
      const b = data[pos++];
      if (b === undefined) throw new Error('váratlan fájlvég');
      value = (value * 128) + (b & 0x7F);
      if (!(b & 0x80)) return [value, pos];
    }
  }
  const u32 = (d, p) => ((d[p] << 24) >>> 0) + (d[p + 1] << 16) + (d[p + 2] << 8) + d[p + 3];
  const u16 = (d, p) => (d[p] << 8) | d[p + 1];

  // -> {division, events: [[tick, order, kind, ch, a, b]], tracks: [{name, channels}]}
  function parseMidi(data) {
    if (String.fromCharCode(data[0], data[1], data[2], data[3]) !== 'MThd')
      throw new Error('nem Standard MIDI fájl (hiányzik az MThd)');
    const hlen = u32(data, 4), ntrks = u16(data, 10), division = u16(data, 12);
    if (division & 0x8000) throw new Error('SMPTE időalapú MIDI nem támogatott');
    let pos = 8 + hlen;
    const events = [], tracks = [];
    let order = 0;
    const isTrk = (p) => data[p] === 0x4D && data[p + 1] === 0x54 && data[p + 2] === 0x72 && data[p + 3] === 0x6B;
    for (let ti = 0; ti < ntrks; ti++) {
      while (pos + 8 <= data.length && !isTrk(pos)) pos += 8 + u32(data, pos + 4);
      if (pos + 8 > data.length) break;
      const tlen = u32(data, pos + 4);
      let p = pos + 8;
      const end = Math.min(p + tlen, data.length);
      pos = p + tlen;
      let tick = 0, status = 0;
      const info = { name: '', channels: {} };
      tracks.push(info);
      while (p < end) {
        let delta;
        [delta, p] = readVlq(data, p);
        tick += delta;
        const b = data[p];
        if (b & 0x80) { status = b; p++; }
        else if (status === 0) throw new Error('futó státusz előzmény nélkül');
        if (status === 0xFF) {
          const mtype = data[p];
          let mlen;
          [mlen, p] = readVlq(data, p + 1);
          if (mtype === 0x51 && mlen === 3) {
            events.push([tick, order, 'tempo', 0, (data[p] << 16) | (data[p + 1] << 8) | data[p + 2], 0]);
          } else if (mtype === 0x03 && !info.name) {
            info.name = latin1(data.subarray(p, p + mlen));
          } else if (mtype === 0x2F) {
            p += mlen;
            break;
          }
          p += mlen;
          status = 0;
          order++;
          continue;
        }
        if (status === 0xF0 || status === 0xF7) {
          let slen;
          [slen, p] = readVlq(data, p);
          p += slen;
          status = 0;
          continue;
        }
        const hi = status & 0xF0, ch = status & 0x0F;
        if (hi === 0xC0 || hi === 0xD0) { p++; continue; }
        const a = data[p], v = data[p + 1];
        p += 2;
        if (hi === 0x90 && v > 0) {
          events.push([tick, order, 'on', ch, a, v]);
          const c = info.channels[ch] || (info.channels[ch] = { notes: 0, lo: 127, hi: 0 });
          c.notes++; c.lo = Math.min(c.lo, a); c.hi = Math.max(c.hi, a);
        } else if (hi === 0x80 || hi === 0x90) {
          events.push([tick, order, 'off', ch, a, 0]);
        } else if (hi === 0xB0) {
          events.push([tick, order, 'cc', ch, a, v]);
        }
        order++;
      }
    }
    events.sort((x, y) => (x[0] - y[0]) || (x[1] - y[1]));
    return { division, events, tracks };
  }
  function latin1(u8) {
    let s = '';
    for (const c of u8) s += String.fromCharCode(c);
    return s;
  }

  function tickToSeconds(division, events) {
    const map = [[0, 0.0, 500000]];
    for (const [tick, , kind, , tempo] of events) {
      if (kind !== 'tempo') continue;
      const [t0, s0, tp] = map[map.length - 1];
      const s = s0 + (tick - t0) * tp / (division * 1e6);
      if (tick === t0) map[map.length - 1] = [t0, s0, tempo];
      else map.push([tick, s, tempo]);
    }
    return function (tick) {
      let lo = 0, hi = map.length - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (map[mid][0] <= tick) lo = mid; else hi = mid - 1;
      }
      const [t0, s0, tp] = map[lo];
      return s0 + (tick - t0) * tp / (division * 1e6);
    };
  }

  // -> [[start, end, note, vel, ch]]
  function collectNotes(division, events, channels, transpose, speed) {
    const conv = tickToSeconds(division, events);
    const open = new Map(), held = new Map();
    const sustain = new Array(16).fill(false);
    const volume = new Array(16).fill(100), expression = new Array(16).fill(127);
    const notes = [];
    const K = (ch, n) => ch * 256 + n;
    const finish = (ch, note, start, vel, end) =>
      notes.push([start, end, note, vel * volume[ch] * expression[ch] / (127 * 127), ch]);
    for (const [tick, , kind, ch, a, b] of events) {
      const t = conv(tick) / speed;
      if (kind === 'tempo') continue;
      if (channels && !channels.has(ch)) continue;
      if (kind === 'cc') {
        if (a === 7) volume[ch] = b;
        else if (a === 11) expression[ch] = b;
        else if (a === 64) {
          const down = b >= 64;
          if (sustain[ch] && !down) {
            for (const [k, lst] of [...held]) {
              if ((k >> 8) === ch) {
                for (const [st, v] of lst) finish(ch, k & 255, st, v, t);
                held.delete(k);
              }
            }
          }
          sustain[ch] = down;
        } else if (a === 120 || a === 123) {
          for (const [k, lst] of [...open, ...held]) {
            if ((k >> 8) === ch) for (const [st, v] of lst) finish(ch, k & 255, st, v, t);
          }
          for (const d of [open, held]) for (const k of [...d.keys()]) if ((k >> 8) === ch) d.delete(k);
        }
        continue;
      }
      const note = a + transpose;
      if (note < 0 || note > 127) continue;
      const key = K(ch, note);
      if (kind === 'on') {
        if (held.has(key)) {
          for (const [st, v] of held.get(key)) finish(ch, note, st, v, t);
          held.delete(key);
        }
        if (!open.has(key)) open.set(key, []);
        open.get(key).push([t, b]);
      } else {
        const lst = open.get(key);
        if (!lst || !lst.length) continue;
        const [st, v] = lst.shift();
        if (!lst.length) open.delete(key);
        if (sustain[ch]) {
          if (!held.has(key)) held.set(key, []);
          held.get(key).push([st, v]);
        } else finish(ch, note, st, v, t);
      }
    }
    const end = events.length ? conv(events[events.length - 1][0]) / speed : 0.0;
    for (const d of [open, held])
      for (const [k, lst] of d) for (const [st, v] of lst) finish(k >> 8, k & 255, st, v, end);
    notes.sort(cmpTuple);
    return notes;
  }

  // ---- TVC adatok ---------------------------------------------------------------
  const pitchValue = (f) => 4096.0 - TVC_CLOCK / f;
  const noteFreq = (n, tuning) => tuning * Math.pow(2.0, (n - 69) / 12.0);
  function pitchTable(tuning) {
    const t = [];
    for (let n = 0; n < 128; n++) {
      let f = noteFreq(n, tuning);
      while (pitchValue(f) < 0) f *= 2;
      t.push(clamp(pyRound(pitchValue(f)), 0, 4094));
    }
    return t;
  }

  const DRUM_KIT = [
    ['lábdob', [[160, 15, 6, 1], [110, 14, 0, 0], [80, 12, 0, 0], [60, 9, 0, 0]]],
    ['pergő', [[220, 9, 13, 6], [190, 5, 10, 5], [null, 0, 7, 4]]],
    ['zárt cin', [[null, 0, 8, 1]]],
    ['nyitott cin', [[null, 0, 9, 3], [null, 0, 7, 3], [null, 0, 5, 3], [null, 0, 3, 2]]],
    ['crash', [[null, 0, 12, 7], [null, 0, 10, 6], [null, 0, 8, 5], [null, 0, 6, 4], [null, 0, 4, 3], [null, 0, 3, 2]]],
    ['mély tam', [[190, 14, 4, 1], [140, 12, 0, 0], [110, 10, 0, 0], [95, 7, 0, 0]]],
    ['közép tam', [[260, 14, 4, 1], [200, 12, 0, 0], [160, 10, 0, 0], [140, 7, 0, 0]]],
    ['magas tam', [[350, 14, 4, 1], [270, 12, 0, 0], [220, 10, 0, 0], [190, 7, 0, 0]]],
    ['taps', [[null, 0, 12, 2], [null, 0, 11, 3], [null, 0, 6, 3]]],
    ['kolomp', [[800, 12, 5, 1], [800, 7, 0, 0]]],
    ['ride', [[null, 0, 6, 2], [null, 0, 4, 2], [null, 0, 3, 2]]],
    ['perem', [[1200, 10, 8, 1]]],
  ];
  const [KICK, SNARE, HAT, OPENHAT, CRASH, LOTOM, MIDTOM, HITOM, CLAP, COWBELL, RIDE, RIM] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  const GM_DRUMS = { 35: KICK, 36: KICK, 37: RIM, 38: SNARE, 40: SNARE, 39: CLAP, 42: HAT, 44: HAT, 46: OPENHAT, 54: OPENHAT,
    49: CRASH, 52: CRASH, 55: CRASH, 57: CRASH, 51: RIDE, 53: RIDE, 59: RIDE,
    41: LOTOM, 43: LOTOM, 45: MIDTOM, 47: MIDTOM, 48: HITOM, 50: HITOM, 56: COWBELL };
  const DRUM_PRIORITY = [KICK, SNARE, CLAP, CRASH, LOTOM, MIDTOM, HITOM, OPENHAT, RIDE, COWBELL, RIM, HAT];

  function buildKit(kitOffset) {
    const steps = DRUM_KIT.map(([, kit]) => {
      const b = [];
      for (const [hz, tvol, nvol, nlen] of kit) {
        let lo = 0, hi = 0xFF;
        if (hz !== null) {
          const p = clamp(pyRound(pitchValue(hz)), 0, 4094);
          lo = p & 0xFF; hi = p >> 8;
        }
        b.push(tvol, lo, hi, (nvol << 4) | Math.min(8, nlen));
      }
      b.push(0xFF);
      return b;
    });
    const out = [steps.length];
    let pos = kitOffset + 1 + 2 * steps.length;
    for (const st of steps) { out.push(pos & 0xFF, pos >> 8); pos += st.length; }
    for (const st of steps) out.push(...st);
    return out;
  }

  function drumHits(notes, rate, curve) {
    const hits = new Map();
    for (const [s, , n, v] of notes) {
      if (!(n in GM_DRUMS) && !(n >= 27 && n <= 87)) continue;
      const k = (n in GM_DRUMS) ? GM_DRUMS[n] : HAT;
      const t = pyRound(s * rate);
      const att = clamp(pyRound((1.0 - Math.pow(clamp(v / 127.0, 0.0, 1.0), curve)) * 8), 0, 15);
      const old = hits.get(t);
      if (old === undefined || DRUM_PRIORITY.indexOf(k) < DRUM_PRIORITY.indexOf(old[0]) ||
          (k === old[0] && att < old[1])) hits.set(t, [k, att]);
    }
    return hits;
  }

  const POLY_KIT = {
    [KICK]: ['slide', 50, 45, 15, 1, 5],
    [LOTOM]: ['slide', 55, 90, 13, 1, 6],
    [MIDTOM]: ['slide', 59, 120, 13, 1, 6],
    [HITOM]: ['slide', 63, 160, 13, 1, 6],
    [COWBELL]: ['slide', 79, 780, 10, 1, 4],
    [SNARE]: ['noise', 12, 1, 8],
    [CLAP]: ['noise', 11, 1, 6],
    [HAT]: ['noise', 6, 1, 2],
    [OPENHAT]: ['noise', 7, 2, 10],
    [CRASH]: ['noise', 10, 3, 30],
    [RIDE]: ['noise', 5, 2, 8],
    [RIM]: ['noise', 8, 1, 2],
  };

  function polyRates() {
    const frame = CPU_CLOCK / FRAME_RATE;
    const samples = (frame - POLY_TICK_OVERHEAD) / POLY_LOOP_CYCLES;
    return [samples * FRAME_RATE, FRAME_RATE];
  }
  function polyFreqTable(tuning, sr) {
    const out = [];
    for (let n = 0; n < 128; n++) out.push(clamp(pyRound(noteFreq(n, tuning) * 65536 / sr), 1, 32767));
    return out;
  }
  function polyMixTable(knee, ceiling = 15) {
    const out = [];
    for (let s = 0; s < 64; s++) {
      const v = s <= knee ? s : knee + (ceiling - knee) * (1 - Math.exp(-(s - knee) / 12.0));
      out.push(clamp(pyRound(v), 0, ceiling));
    }
    return out;
  }

  function velocityToVolume(vel, curve, vmin, vmax) {
    const x = Math.pow(clamp(vel / 127.0, 0.0, 1.0), curve);
    return clamp(pyRound(vmin + x * (vmax - vmin)), vmin, vmax);
  }
  function buildTicks(notes, rate) {
    return notes.map(([s, e, n, v, ch], i) => {
      const st = pyRound(s * rate);
      return [st, Math.max(st + 1, pyRound(e * rate)), n, v, ch, i];
    });
  }
  function choose(active, mode, prio, maxNotes, keepBass) {
    if (!active.length) return [];
    if (mode === 'mono') {
      let best;
      if (prio === 'high') best = maxBy(active, (a) => [a[0], a[2]]);
      else if (prio === 'low') best = minBy(active, (a) => [a[0], -a[2]]);
      else best = maxBy(active, (a) => [a[2], a[0]]);
      return [[best[0], best[1], best[3]]];
    }
    const uniq = new Map();
    for (const [n, v, st, idx] of active) {
      if (!uniq.has(n) || st > uniq.get(n)[2]) uniq.set(n, [n, v, st, idx]);
    }
    const ordered = [...uniq.values()].sort((a, b) => b[0] - a[0]);
    let pick = ordered.slice(0, maxNotes);
    if (keepBass && ordered.length > maxNotes) pick = ordered.slice(0, maxNotes - 1).concat([ordered[ordered.length - 1]]);
    pick.sort((a, b) => a[0] - b[0]);
    return pick.map(([n, v, , idx]) => [n, v, idx]);
  }
  function encodeWait(out, n, longCode) {
    while (n > 0) {
      if (n <= 63) { out.push(0xBF + n); return; }
      const k = Math.min(n, 65535);
      out.push(longCode, k & 0xFF, k >> 8);
      n -= k;
    }
  }
  function maxOf(arr) {
    let m = -Infinity;
    for (const x of arr) if (x > m) m = x;
    return m;
  }
  function groupStarts(ticks) {
    const starts = new Map();
    for (const t of ticks) {
      if (!starts.has(t[0])) starts.set(t[0], []);
      starts.get(t[0]).push(t);
    }
    return starts;
  }
  function expire(active, t) {
    for (const [k, a] of [...active]) if (a[1] <= t) active.delete(k);
  }

  function convert(notes, o, drums) {
    const ticks = buildTicks(notes, o.rate);
    const total = maxOf(ticks.map((t) => t[1]).concat([...drums.keys()].map((t) => t + 6)));
    const starts = groupStarts(ticks);
    const active = new Map();
    const out = [];
    let prev = null, curVol = null, pending = 0;
    const stats = { chords: 0, notes: 0, rests: 0, drums: drums.size };
    for (let t = 0; t <= total; t++) {
      expire(active, t);
      for (const [st, en, n, v, , idx] of starts.get(t) || []) active.set(idx, [st, en, n, v]);
      const sel = choose([...active].map(([i, a]) => [a[2], a[3], a[0], i]), o.mode, o.prio, o.maxNotes, o.arpBass);
      const notesKey = sel.map((s) => s[0]).join(',');
      const idxSet = new Set(sel.map((s) => s[2]));
      const same = prev && prev.notesKey === notesKey && prev.idxSet.size === idxSet.size &&
        [...idxSet].every((i) => prev.idxSet.has(i));
      if (!same) {
        const newAttack = prev === null || sel.some((s) => !prev.idxSet.has(s[2]));
        if ((prev ? notesKey !== prev.notesKey : true) || newAttack) {
          encodeWait(out, pending, 0xA0);
          pending = 0;
          if (!sel.length) { out.push(0x80); stats.rests++; }
          else {
            const vol = velocityToVolume(Math.max(...sel.map((s) => s[1])), o.curve, o.minVolume, o.maxVolume);
            if (vol !== curVol) { out.push(0x90 | vol); curVol = vol; }
            if (sel.length === 1) { out.push(sel[0][0]); stats.notes++; }
            else { out.push(0x80 | sel.length, ...sel.map((s) => s[0])); stats.chords++; }
          }
        }
        prev = { notesKey, idxSet };
      }
      if (drums.has(t)) {
        encodeWait(out, pending, 0xA0);
        pending = 0;
        const [k, att] = drums.get(t);
        out.push(0xA1 + k, att);
      }
      pending++;
    }
    encodeWait(out, pending, 0xA0);
    out.push(0x80);
    if (o.loop) out.push(0xC0 + 0x0F);
    out.push(0xFF);
    return { body: out, total, stats };
  }

  function convertPoly(notes, drums, o, sr, tickRate, ftab) {
    const ticks = buildTicks(notes, tickRate);
    const total = maxOf(ticks.map((t) => t[1]).concat([...drums.keys()].map((t) => t + 8), [1]));
    const starts = groupStarts(ticks);
    const vmax = o.polyVolume;
    const vmin = Math.max(1, Math.min(vmax, pyRound(o.minVolume * vmax / 15.0)));
    const out = [];
    let pending = 0;
    const stats = { notes: 0, drums: drums.size, voices_max: 0, chords: 0, rests: 0 };
    const emit = (...b) => { encodeWait(out, pending, 0xBF); pending = 0; out.push(...b); };
    const active = new Map();
    const cur = new Array(POLY_VOICES).fill(null);
    const reserved = new Array(POLY_VOICES).fill(0);
    let noiseOffAt = null;
    for (let t = 0; t <= total; t++) {
      expire(active, t);
      for (const [st, en, n, v, , idx] of starts.get(t) || []) active.set(idx, [st, en, n, v]);
      for (let v = 0; v < POLY_VOICES; v++) {
        if (reserved[v] && reserved[v] <= t) { reserved[v] = 0; emit(0xB0 + v); cur[v] = null; }
      }
      if (noiseOffAt !== null && noiseOffAt <= t) { emit(0xB4, 0x00); noiseOffAt = null; }
      const uniq = new Map();
      for (const [idx, [st, , n, v]] of active) {
        if (!uniq.has(n) || st > uniq.get(n)[0]) uniq.set(n, [st, idx, v]);
      }
      const ordered = [...uniq.keys()].sort((a, b) => b - a);
      const prio = ordered.length > 1
        ? [ordered[0], ordered[ordered.length - 1], ...ordered.slice(1, -1)] : ordered;
      if (drums.has(t)) {
        const [k, att] = drums.get(t);
        const kit = POLY_KIT[k];
        if (kit && kit[0] === 'noise') {
          const [, vol0, dec, dur] = kit;
          emit(0xB4, (Math.max(1, vol0 - att) << 4) | dec);
          noiseOffAt = t + dur;
        } else if (kit) {
          const [, note, endHz, vol0, dec, dur] = kit;
          const keep = new Set(prio.slice(0, 2));
          const range = [...Array(POLY_VOICES).keys()];
          let cand = range.filter((v) => !reserved[v] && cur[v] === null);
          cand = cand.concat(range.filter((v) => !reserved[v] && cur[v] !== null && !keep.has(cur[v][1])));
          if (prio.length) {
            const last = prio[prio.length - 1];
            cand = cand.concat(range.filter((v) => !reserved[v] && cur[v] !== null && cur[v][1] === last));
          }
          if (cand.length) {
            const v = cand[0];
            const f0 = ftab[note], f1 = pyRound(endHz * 65536 / sr);
            const slide = pyRound((f1 - f0) / dur) & 0xFFFF;
            emit(0xB8 + v, note, (Math.max(1, vol0 - att) << 4) | dec, slide & 0xFF, slide >> 8);
            reserved[v] = t + dur;
            cur[v] = null;
          }
        }
      }
      const free = [...Array(POLY_VOICES).keys()].filter((v) => !reserved[v]);
      const want = prio.slice(0, free.length);
      const wantIdx = new Map(want.map((n) => [uniq.get(n)[1], n]));
      stats.voices_max = Math.max(stats.voices_max, want.length);
      const newCur = new Map();
      for (const v of free) if (cur[v] !== null && wantIdx.has(cur[v][0])) newCur.set(v, cur[v]);
      const placed = new Set([...newCur.values()].map((c) => c[0]));
      const empty = free.filter((v) => !newCur.has(v));
      for (const [idx, n] of wantIdx) {
        if (placed.has(idx)) continue;
        const v = empty.shift();
        const vol = velocityToVolume(active.get(idx)[3], o.curve, vmin, vmax);
        emit(0x80 + 16 * v + vol, n);
        stats.notes++;
        newCur.set(v, [idx, n]);
      }
      for (const v of free) {
        if (!newCur.has(v) && cur[v] !== null) emit(0xB0 + v);
        cur[v] = newCur.has(v) ? newCur.get(v) : null;
      }
      pending++;
    }
    encodeWait(out, pending, 0xBF);
    out.push(0xB0, 0xB1, 0xB2, 0xB4, 0x00);
    if (o.loop) out.push(0xC0 + 0x0F);
    out.push(0xFF);
    return { body: out, total, stats };
  }

  const DEFAULTS = {
    mode: 'arp', prio: 'high', maxNotes: 3, arpBass: false, arpSpeed: 1, polyVolume: 9, polyKnee: 10,
    channels: null, drums: 'synth', transpose: 0, tuning: 440.0, speed: 1.0, rate: FRAME_RATE,
    decay: 0, decayFloor: 6, curve: 0.7, minVolume: 6, maxVolume: 15, loop: false, background: false,
  };

  // midi: Uint8Array vagy parseMidi() eredménye; opts: mint a parancssor.
  // -> {song: Uint8Array (song.bin), mode, total, rate, stats, notes, warnings}
  function convertMidi(midi, opts) {
    const o = Object.assign({}, DEFAULTS, opts || {});
    const parsed = midi instanceof Uint8Array ? parseMidi(midi) : midi;
    const { division, events } = parsed;
    const channels = new Set(o.channels ? o.channels.map((c) => c - 1) : [...Array(16).keys()]);
    const useDrums = o.drums === 'synth' && channels.has(DRUM_CHANNEL);
    if (o.drums !== 'pitched') channels.delete(DRUM_CHANNEL);
    if (!(o.arpSpeed >= 1 && o.arpSpeed <= 255)) throw new Error('arpeggio sebesség: 1..255');
    if (!(o.decay >= 0 && o.decay <= 255)) throw new Error('lecsengés: 0..255');
    if (!(1 <= o.minVolume && o.minVolume <= o.maxVolume && o.maxVolume <= 15))
      throw new Error('1 <= min. hangerő <= max. hangerő <= 15');
    const notes = collectNotes(division, events, channels, o.transpose, o.speed);
    let drums = new Map();
    if (useDrums) drums = drumHits(collectNotes(division, events, new Set([DRUM_CHANNEL]), 0, o.speed), o.rate, o.curve);
    if (!notes.length && !drums.size) throw new Error('a kiválasztott csatornákon nincs hang');
    const floor = clamp(o.decayFloor, 0, 15);
    let song, total, stats, rate, sr = null;
    if (o.mode === 'poly') {
      let tickRate;
      [sr, tickRate] = polyRates();
      const pd = new Map();
      for (const [t, hit] of drums) {
        const tt = pyRound(t / o.rate * tickRate);
        const old = pd.get(tt);
        if (old === undefined || DRUM_PRIORITY.indexOf(hit[0]) < DRUM_PRIORITY.indexOf(old[0])) pd.set(tt, hit);
      }
      const ftab = polyFreqTable(o.tuning, sr);
      const r = convertPoly(notes, pd, o, sr, tickRate, ftab);
      const data = [o.loop ? 1 : 0, o.decay, floor, 0, 0, 0, 0, 0, ...polyMixTable(o.polyKnee)];
      for (const f of ftab) data.push(f & 0xFF, f >> 8);
      song = Uint8Array.from(data.concat(r.body));
      ({ total, stats } = r);
      rate = tickRate;
    } else {
      const r = convert(notes, o, drums);
      const kitOffset = drums.size ? 8 + 256 + r.body.length : 0;
      const data = [(o.loop ? 1 : 0) | (o.background ? 2 : 0), o.arpSpeed, o.decay, floor, 0, 0, kitOffset & 0xFF, kitOffset >> 8];
      for (const p of pitchTable(o.tuning)) data.push(p & 0xFF, p >> 8);
      let all = data.concat(r.body);
      if (drums.size) all = all.concat(buildKit(kitOffset));
      song = Uint8Array.from(all);
      ({ total, stats } = r);
      rate = o.rate;
    }
    const warnings = [];
    if (o.mode === 'poly' && o.background)
      warnings.push('a háttér-mód csak az egycsatornás lejátszóval működik (a poly a teljes CPU-t használja)');
    const used = [...new Set(notes.map((n) => n[2]))].sort((a, b) => a - b);
    if (used.length && o.mode !== 'poly' && noteFreq(used[0], o.tuning) < TVC_CLOCK / 4096)
      warnings.push('a 47,7 Hz alatti hangok egy oktávval feljebb szólnak');
    return { song, mode: o.mode, total, rate, sampleRate: sr, stats, notes, used, warnings, options: o };
  }

  // ---- .cas összeállítása ---------------------------------------------------------
  // players: a players.js objektuma ({mono: {code, title_offset}, poly: {...}})
  function titleBytes(title) {
    const out = new Uint8Array(32).fill(32);
    let i = 0;
    for (const ch of String(title)) {
      if (i >= 32) break;
      const c = ch.charCodeAt(0);
      out[i++] = (c >= 32 && c < 127 && ch !== '"') ? c : 0x5F;
    }
    return out;
  }
  function buildCas(player, song, title) {
    const code = Uint8Array.from(player.code);
    const suffix = Uint8Array.from(player.suffix || []);
    code.set(titleBytes(title), player.title_offset);
    if (player.song_len_offset !== null && player.song_len_offset !== undefined) {
      code[player.song_len_offset] = song.length & 0xFF;
      code[player.song_len_offset + 1] = song.length >> 8;
    }
    const progLen = code.length + song.length + suffix.length;
    const total = 16 + progLen;
    const blocks = Math.ceil(total / 128);
    const cas = new Uint8Array(128 + total);
    cas[0] = 0x11;
    cas[2] = blocks & 0xFF; cas[3] = blocks >> 8;
    const last = total - (blocks - 1) * 128;
    cas[4] = last & 0xFF; cas[5] = last >> 8;
    cas[129] = 0x01;                        // programfájl
    cas[130] = progLen & 0xFF; cas[131] = progLen >> 8;
    cas[132] = 0xFF;                        // autorun
    cas.set(code, 144);
    cas.set(song, 144 + code.length);
    cas.set(suffix, 144 + code.length + song.length);
    return cas;
  }

  // ---- forráscsomag -----------------------------------------------------------
  // a beállításokkal egyenértékű build.sh / midi2tvc.py kapcsolók
  const CLI = [
    ['mode', '--mode'], ['prio', '--prio'], ['maxNotes', '--max-notes'], ['arpBass', '--arp-bass'],
    ['arpSpeed', '--arp-speed'], ['polyVolume', '--poly-volume'], ['polyKnee', '--poly-knee'],
    ['channels', '--channels'], ['drums', '--drums'], ['transpose', '--transpose'], ['tuning', '--tuning'],
    ['speed', '--speed'], ['decay', '--decay'], ['decayFloor', '--decay-floor'], ['curve', '--curve'],
    ['minVolume', '--min-volume'], ['maxVolume', '--max-volume'], ['loop', '--loop'],
    ['background', '--background'],
  ];
  function cliArgs(opts) {
    const o = Object.assign({}, DEFAULTS, opts || {});
    const out = [];
    for (const [k, flag] of CLI) {
      const v = o[k];
      if (k === 'channels') { if (v && v.length) out.push(flag, v.join(',')); continue; }
      if (typeof v === 'boolean') { if (v) out.push(flag); continue; }
      if (v !== DEFAULTS[k]) out.push(flag, String(v));
    }
    return out;
  }
  const shQuote = (s) => /^[A-Za-z0-9_.,\/:=+-]+$/.test(s) ? s : "'" + String(s).replace(/'/g, "'\\''") + "'";
  const enc = (s) => new TextEncoder().encode(s);

  // -> [[útvonal, Uint8Array]]: a lejátszó forrása, a dal adatai, a MIDI, a
  // kész .cas, build.sh és README.txt; a build.sh-val bájtra ugyanez a .cas
  // fordul újra (sjasmplus)
  function sourcePackage(p) {
    const { players, result, midiBytes, midiName, title, casBytes, name } = p;
    const asm = result.mode === 'poly' ? 'player_poly.asm' : 'player.asm';
    const args = cliArgs(result.options);
    const tb = titleBytes(title);
    const cmd = ['./build.sh', midiName].concat(args, ['--title', String.fromCharCode(...tb).trimEnd()]).map(shQuote).join(' ');
    const build = '#!/bin/sh\n' +
      '# a ' + name + '.cas újrafordítása a forrásból (kell: sjasmplus)\n' +
      'set -e\ncd "$(dirname "$0")"\nmkdir -p build\n' +
      'sjasmplus --nologo --msg=war --raw=build/' + name + '.cas --sym=build/' + name + '.sym ' + asm + '\n' +
      'if cmp -s build/' + name + '.cas ' + name + '.cas; then echo "kész: build/' + name + '.cas (azonos a csomagban lévővel)"; ' +
      'else echo "kész: build/' + name + '.cas (ELTÉR a csomagban lévőtől)"; fi\n';
    const pad = (t) => t + ' '.repeat(Math.max(1, 20 - t.length));
    const mode = { poly: 'többszólamú (player_poly.asm)', arp: 'egycsatornás, arpeggio (player.asm)', mono: 'egycsatornás, egyszólamú (player.asm)' }[result.mode];
    const readme = [
      name + ' - TVC MIDI-lejátszó forráscsomag',
      '',
      'Forrás:    ' + midiName,
      'Lejátszó:  ' + mode,
      'Hossz:     ' + (result.total / result.rate).toFixed(1) + ' s, ' + result.song.length + ' bájt dal, ' + casBytes.length + ' bájt .cas',
      '',
      'Fájlok',
      '  ' + pad(name + '.cas') + 'a kész program (TVC: LOAD, magától indul)',
      '  ' + pad(midiName) + 'az eredeti MIDI',
      '  ' + pad(asm) + 'a lejátszó assembly forrása (sjasmplus)',
      '  cas.inc             a .cas fejléc és a BASIC indító sorok',
      '  build/song.bin      a dal adatai (formátum: a ' + asm + ' eleje)',
      '  build/title.bin     a cím (32 bájt, a BASIC PRINT sorban)',
      '  build.sh            újrafordítás: ./build.sh -> build/' + name + '.cas',
      '',
      'A dal adatai a tvc-midi-player repó midi2tvc.py konverterével, ugyanezekkel',
      'a beállításokkal így készíthetők el a MIDI-ből (a repó gyökeréből):',
      '',
      '  ' + cmd,
      '',
    ].join('\n');
    return [
      [name + '/' + name + '.cas', casBytes],
      [name + '/' + midiName, midiBytes],
      [name + '/' + asm, enc(players.sources[asm])],
      [name + '/cas.inc', enc(players.sources['cas.inc'])],
      [name + '/build/song.bin', result.song],
      [name + '/build/title.bin', tb],
      [name + '/build.sh', enc(build)],
      [name + '/README.txt', enc(readme)],
    ];
  }

  // tömörítetlen (stored) ZIP; files: [[útvonal, Uint8Array], ...]
  function crc32(u8) {
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < u8.length; i++) {
      let c = (crc ^ u8[i]) & 0xFF;
      for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1;
      crc = (crc >>> 8) ^ c;
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }
  function zipFiles(files, unixExec) {
    const parts = [], central = [];
    let off = 0;
    const date = ((2026 - 1980) << 9) | (1 << 5) | 1;      // rögzített dátum: azonos csomag
    for (const [path, data] of files) {
      const nm = enc(path), crc = crc32(data), n = data.length;
      const lh = new DataView(new ArrayBuffer(30));
      lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
      lh.setUint16(12, date, true);
      lh.setUint32(14, crc, true); lh.setUint32(18, n, true); lh.setUint32(22, n, true); lh.setUint16(26, nm.length, true);
      const ch = new DataView(new ArrayBuffer(46));
      ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, (3 << 8) | 20, true); ch.setUint16(6, 20, true);
      ch.setUint16(8, 0x0800, true); ch.setUint16(14, date, true);
      ch.setUint32(16, crc, true); ch.setUint32(20, n, true); ch.setUint32(24, n, true); ch.setUint16(28, nm.length, true);
      const mode = (unixExec && unixExec.test(path)) ? 0o100755 : 0o100644;
      ch.setUint32(38, (mode << 16) >>> 0, true);
      ch.setUint32(42, off, true);
      parts.push(new Uint8Array(lh.buffer), nm, data);
      central.push(new Uint8Array(ch.buffer), nm);
      off += 30 + nm.length + n;
    }
    let cdLen = 0;
    for (const c of central) cdLen += c.length;
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
    end.setUint32(12, cdLen, true); end.setUint32(16, off, true);
    const all = parts.concat(central, [new Uint8Array(end.buffer)]);
    let n = 0;
    for (const a of all) n += a.length;
    const out = new Uint8Array(n);
    let p2 = 0;
    for (const a of all) { out.set(a, p2); p2 += a.length; }
    return out;
  }

  const api = {
    TVC_CLOCK, FRAME_RATE, CPU_CLOCK, POLY_LOOP_CYCLES, POLY_VOICES, DRUM_CHANNEL, DRUM_KIT, POLY_KIT, DEFAULTS,
    pyRound, parseMidi, collectNotes, pitchTable, polyFreqTable, polyMixTable, polyRates, noteFreq,
    convertMidi, buildCas, titleBytes, cliArgs, sourcePackage, zipFiles,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Midi2Tvc = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
