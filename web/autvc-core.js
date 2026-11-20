/*
 * auTVC web – önkicsomagoló TVC CAS fájlok készítése
 * --------------------------------------------------
 * Az eredeti auTVC 2.0 (Márta Krisztián / Murphy, 2025) parancssoros
 * program böngészős megvalósítása. A tömörített adatfolyam aPLib
 * formátumú (ugyanaz, amit az apultra tömörítő állít elő), így az
 * eredeti programban használt Z80 kitömörítő rutinok változtatás nélkül
 * kicsomagolják.
 *
 * A teljes mag egyetlen gyárfüggvényben van, hogy Web Workerben
 * (Blob URL-ből, file:// alatt is) és Node.js alatt (tesztek) is
 * futtatható legyen.
 *
 * A tvc-midi-player az auTVC web változatból vette át (tömörítés a
 * konverterben: build.sh --compress, a webes felületen a Tömörítés).
 */
function autvcCoreFactory() {
  'use strict';

  // ---------------------------------------------------------------
  //  Z80 kitömörítő rutinok (aPLib), a $0100 címre fordítva.
  //  Az auTVC 2.0 által generált fájlokból kiemelve.
  // ---------------------------------------------------------------
  function hex(s) {
    const a = new Uint8Array(s.length / 2);
    for (let i = 0; i < a.length; i++) a[i] = parseInt(s.substr(i * 2, 2), 16);
    return a;
  }
  // sebességoptimalizált (alapértelmezett) változat, 239 bájt
  const DEPACK_FAST = hex(
    'eda0377e23173807eda08730fb28f4873031282a87cceb01da86014ecb19c8230600dd69' +
    'dd60e5626b3808ed42eda0eda01842b7ed42eda0eda0eda018377e231738d1cdcc010d0d' +
    '28780d414e23dd69dd60c5cdcc01e3087cfe7d300bfe053008b72006cb7d200203037b95' +
    '6f7a9c6708eda0edb0e187308f283487303e283787cceb01309501e00087cceb01cb1187' +
    'cceb01cb1187cceb01cb1187cceb01cb11eb2805e5ed424ee17123ebc30a017e2317d208' +
    '0118c47e231738c4cdcc010d18880ccdcf01dde5e308189e01010087280ecb11cb1087d0' +
    '20f57e2317d018ef7e2317cb11cb1087d018e47e2317c9');
  // méretoptimalizált (-us / -small) változat, 147 bájt
  const DEPACK_SMALL = hex(
    '3e80eda006ff87cc8f0130f687cc8f01302c01e00087cc8f01301587cc8f01cb1138f8eb' +
    '2805e5ed424ee17123eb18d44ecb19c823e560690e01cb11182a087808cd7d0108814f08' +
    '0d282a0d414e23c5cd7d01e3087cfe7d300bfe053008b72006cb7d2002030308e5dde1d5' +
    'ebed52d1edb0e11891cd7d01dde5e318ee01010087cc8f01cb11cb1087cc8f01d018f17e' +
    '2317c9');

  const BASIC_START = 0x19ef;     // a BASIC program kezdőcíme (TEXT)
  const STACK_LAST = 0x16ab;      // a BASIC stack utolsó bájtja
  const DEPACK_ADDR = 0x0100;     // ide másolódik a kitömörítő
  const STACK_NEED = 16;          // a kitömörítő stack igénye (bájt)
  // memórialapozás (02h port): b7-b6: 3. lap (01=SYS, 10=U3),
  // b5: 2. lap (0=VID, 1=U2), b4-b3: 0. lap (10=U0)
  const MEMCFG = { UUUU: 0xb0, UUVU: 0x90, UUUS: 0x70, UUVS: 0x50 };

  // ---------------------------------------------------------------
  //  aPLib tömörítő (optimális elemzés, ismételt offszet kezeléssel)
  // ---------------------------------------------------------------
  function bitLen(v) { return 32 - Math.clz32(v); }
  function gammaBits(v) { return 2 * (bitLen(v) - 1); }   // v >= 2
  function lenAdj(o) { return o < 128 ? 2 : (o >= 32000 ? 2 : (o >= 1280 ? 1 : 0)); }
  function minLen(o) { return 2 + lenAdj(o); }

  // tokenek típusai
  const T_LIT = 0, T_NIB = 1, T_SHORT = 2, T_MATCH = 3, T_REP = 4;

  /**
   * data: Uint8Array (max. 65536 bájt)
   * opts.depth: a hash lánc keresési mélysége (alap 1024)
   * opts.arrivals: pozíciónként megtartott állapotok száma (alap 8)
   * opts.progress: function(fraction)
   */
  function compress(data, opts) {
    opts = opts || {};
    const n = data.length;
    if (n === 0) throw new Error('Üres bemenet.');
    if (n > 65536) throw new Error('A bemenet nagyobb, mint 64 kB.');
    const DEPTH = opts.depth || 1024;
    const K = opts.arrivals || 8;
    const ENUM = 48;        // ennyi hosszig minden hosszt kipróbál
    const LONG = 192;       // ennél hosszabb egyezés után gyorsított keresés
    const REPCAP = 255;     // ismételt offszet max. vizsgált hossza

    // állapotok: pozíciónként K hely
    const SZ = (n + 1) * K;
    const aCost = new Float64Array(SZ).fill(Infinity);
    const aRep = new Int32Array(SZ);
    const aLwm = new Uint8Array(SZ);
    const aFrom = new Int32Array(SZ).fill(-1);  // forrás állapot indexe
    const aType = new Uint8Array(SZ);
    const aLen = new Int32Array(SZ);
    const aOff = new Int32Array(SZ);
    const aCnt = new Uint8Array(n + 1);

    function arrive(pos, cost, rep, lwm, from, type, len, off) {
      const base = pos * K;
      let cnt = aCnt[pos];
      // azonos állapot (rep, lwm) már létezik?
      for (let s = 0; s < cnt; s++) {
        const ix = base + s;
        if (aRep[ix] === rep && aLwm[ix] === lwm) {
          if (cost >= aCost[ix]) return;
          // törlés, majd újra beszúrás rendezetten
          for (let t = s; t < cnt - 1; t++) copySlot(base + t + 1, base + t);
          cnt--;
          break;
        }
      }
      if (cnt === K && cost >= aCost[base + K - 1]) { aCnt[pos] = cnt; return; }
      let p = cnt < K ? cnt : K - 1;
      while (p > 0 && aCost[base + p - 1] > cost) { copySlot(base + p - 1, base + p); p--; }
      const ix = base + p;
      aCost[ix] = cost; aRep[ix] = rep; aLwm[ix] = lwm; aFrom[ix] = from;
      aType[ix] = type; aLen[ix] = len; aOff[ix] = off;
      aCnt[pos] = cnt < K ? cnt + 1 : K;
    }
    function copySlot(src, dst) {
      aCost[dst] = aCost[src]; aRep[dst] = aRep[src]; aLwm[dst] = aLwm[src];
      aFrom[dst] = aFrom[src]; aType[dst] = aType[src]; aLen[dst] = aLen[src];
      aOff[dst] = aOff[src];
    }

    // egyezéskereső: hash lánc 2 bájtos kulccsal
    const head = new Int32Array(65536).fill(-1);
    const prev = new Int32Array(n).fill(-1);
    function insert(i) {
      if (i + 1 >= n) return;
      const key = (data[i] << 8) | data[i + 1];
      prev[i] = head[key];
      head[key] = i;
    }
    const mOff = new Int32Array(64), mLen = new Int32Array(64);
    let skipOff = 0, skipEnd = -1;   // hosszú egyezés belsejében

    function findMatches(i) {
      let cnt = 0;
      const maxL = n - i;
      if (maxL < 2) return 0;
      if (i < skipEnd) {
        mOff[0] = skipOff; mLen[0] = skipEnd + LONG - i;
        return 1;
      }
      const key = (data[i] << 8) | data[i + 1];
      let j = head[key], depth = DEPTH, best = 1;
      while (j >= 0 && depth-- > 0) {
        const o = i - j;
        if (o > 65535) break;
        if (best < maxL && data[j + best] === data[i + best]) {
          let l = 2;
          while (l < maxL && data[j + l] === data[i + l]) l++;
          if (l > best && l >= minLen(o) - (o < 128 ? 2 : 0)) {
            best = l;
            mOff[cnt] = o; mLen[cnt] = l; cnt++;
            if (l === maxL || cnt === 64) break;
          }
        }
        j = prev[j];
      }
      if (best >= LONG + 2 && cnt > 0) {
        skipOff = mOff[cnt - 1];
        skipEnd = i + best - LONG;
      }
      return cnt;
    }
    function matchLenAt(i, o) {
      if (o > i) return 0;
      const maxL = Math.min(n - i, REPCAP);
      let l = 0;
      while (l < maxL && data[i + l - o] === data[i + l]) l++;
      return l;
    }

    // kezdő állapot: az első bájt mindig nyers literál
    arrive(1, 8, 0, 0, -1, T_LIT, 1, 0);
    insert(0);
    const progressStep = Math.max(1, n >> 6);

    for (let i = 1; i < n; i++) {
      if (opts.progress && (i % progressStep) === 0) opts.progress(i / n);
      const base = i * K, cnt = aCnt[i];
      if (cnt === 0) { insert(i); continue; }
      const c = data[i];
      // 4 bites rövid offszet (111) – egy bájt másolása vagy 0 írása
      let nib = -1;
      if (c === 0) nib = 0;
      else for (let o = 1; o <= 15 && o <= i; o++) if (data[i - o] === c) { nib = o; break; }

      let best0 = -1, best1 = -1;   // legjobb állapot lwm=0 ill. lwm=1 esetén
      for (let s = 0; s < cnt; s++) {
        const ix = base + s, cost = aCost[ix], rep = aRep[ix], lwm = aLwm[ix];
        if (lwm === 0) { if (best0 < 0) best0 = ix; } else if (best1 < 0) best1 = ix;
        // literál
        if (nib >= 0) arrive(i + 1, cost + 7, rep, 0, ix, T_NIB, 1, nib);
        else arrive(i + 1, cost + 9, rep, 0, ix, T_LIT, 1, 0);
        // ismételt offszet (csak literál után)
        if (lwm === 0 && rep > 0) {
          const M = matchLenAt(i, rep);
          if (M >= 2) {
            const top = Math.min(M, ENUM);
            for (let L = 2; L <= top; L++) arrive(i + L, cost + 4 + gammaBits(L), rep, 1, ix, T_REP, L, rep);
            if (M > top) arrive(i + M, cost + 4 + gammaBits(M), rep, 1, ix, T_REP, M, rep);
          }
        }
      }

      const mc = findMatches(i);
      if (mc > 0) {
        const bestAny = base;     // a legolcsóbb állapot
        const costAny = aCost[bestAny];
        let prevL = 1;
        for (let k = 0; k < mc; k++) {
          const o = mOff[k], M = mLen[k];
          // rövid egyezés (110): offszet 1..127, hossz 2..3
          if (o < 128) {
            for (let L = Math.max(2, prevL + 1); L <= 3 && L <= M; L++)
              arrive(i + L, costAny + 11, o, 1, bestAny, T_SHORT, L, o);
          }
          const lo = Math.max(prevL + 1, minLen(o));
          const adj = lenAdj(o), hi = o >> 8;
          for (let w = 0; w < 2; w++) {
            const src = w === 0 ? best0 : best1;
            if (src < 0) continue;
            const oc = aCost[src] + 2 + gammaBits(hi + (w === 0 ? 3 : 2)) + 8;
            const top = Math.min(M, ENUM);
            for (let L = lo; L <= top; L++) arrive(i + L, oc + gammaBits(L - adj), o, 1, src, T_MATCH, L, o);
            if (M > top && M >= lo) arrive(i + M, oc + gammaBits(M - adj), o, 1, src, T_MATCH, M, o);
          }
          if (M > prevL) prevL = M;
        }
      }
      insert(i);
    }

    // visszakövetés
    let ix = n * K;
    if (aCnt[n] === 0) throw new Error('Belső hiba: nincs érvényes elemzés.');
    const toks = [];
    while (ix >= 0) {
      toks.push(ix);
      ix = aFrom[ix];
    }
    toks.reverse();

    // kódolás
    const out = [];
    let tagPos = -1, bitsLeft = 0;
    function bit(b) {
      if (bitsLeft === 0) { tagPos = out.length; out.push(0); bitsLeft = 8; }
      bitsLeft--;
      if (b) out[tagPos] |= 1 << bitsLeft;
    }
    function gamma(v) {
      const nb = bitLen(v);
      for (let b = nb - 2; b >= 0; b--) { bit((v >> b) & 1); bit(b > 0 ? 1 : 0); }
    }
    out.push(data[0]);
    let lwm = 0, pos = 1;
    for (let t = 1; t < toks.length; t++) {
      const k = toks[t], type = aType[k], L = aLen[k], o = aOff[k];
      switch (type) {
        case T_LIT: bit(0); out.push(data[pos]); lwm = 0; break;
        case T_NIB: bit(1); bit(1); bit(1); for (let b = 3; b >= 0; b--) bit((o >> b) & 1); lwm = 0; break;
        case T_SHORT: bit(1); bit(1); bit(0); out.push((o << 1) | (L - 2)); lwm = 1; break;
        case T_REP: bit(1); bit(0); gamma(2); gamma(L); lwm = 1; break;
        case T_MATCH:
          bit(1); bit(0); gamma((o >> 8) + (lwm ? 2 : 3)); out.push(o & 0xff);
          gamma(L - lenAdj(o)); lwm = 1; break;
      }
      pos += L;
    }
    if (pos !== n) throw new Error('Belső hiba: hibás elemzés.');
    bit(1); bit(1); bit(0); out.push(0);     // vége jel
    return Uint8Array.from(out);
  }

  // ---------------------------------------------------------------
  //  aPLib kitömörítő (ellenőrzéshez és a helyben kitömörítés
  //  biztonsági távolságának kiszámításához)
  // ---------------------------------------------------------------
  function decompress(src) {
    const out = [];
    let sp = 0, tag = 0, bits = 0, r0 = 0, lwm = 0, maxLag = -Infinity;
    function rd() { if (sp >= src.length) throw new Error('Sérült adatfolyam.'); return src[sp++]; }
    function bit() {
      if (bits === 0) { tag = rd(); bits = 8; }
      bits--;
      return (tag >> bits) & 1;
    }
    function gamma() { let v = 1; do { v = (v << 1) | bit(); } while (bit()); return v; }
    function put(b) { const lag = out.length - sp; if (lag > maxLag) maxLag = lag; out.push(b); }
    function copy(o, l) {
      if (o > out.length || o <= 0) throw new Error('Sérült adatfolyam (offszet).');
      for (let k = 0; k < l; k++) put(out[out.length - o]);
    }
    put(rd());
    for (;;) {
      if (bit()) {
        if (bit()) {
          if (bit()) {
            let o = 0;
            for (let k = 0; k < 4; k++) o = (o << 1) | bit();
            if (o) copy(o, 1); else put(0);
            lwm = 0;
          } else {
            const b = rd();
            const o = b >> 1, l = 2 + (b & 1);
            if (!o) break;
            copy(o, l); r0 = o; lwm = 1;
          }
        } else {
          let g = gamma();
          if (lwm === 0 && g === 2) {
            copy(r0, gamma());
          } else {
            g -= lwm === 0 ? 3 : 2;
            const o = (g << 8) | rd();
            let l = gamma();
            if (o >= 32000) l++;
            if (o >= 1280) l++;
            if (o < 128) l += 2;
            copy(o, l); r0 = o;
          }
          lwm = 1;
        }
      } else {
        put(rd()); lwm = 0;
      }
      if (out.length > 65536) throw new Error('Sérült adatfolyam (túl hosszú).');
    }
    // maxLag: max(j - r_j), ahol j a kiírt bájt sorszáma, r_j az addig
    // beolvasott bájtok száma. Helyben kitömörítéshez a tömörített adat
    // első bájtjának címe >= célcím + maxLag + 1 kell legyen.
    return { data: Uint8Array.from(out), maxLag: maxLag, consumed: sp };
  }

  // ---------------------------------------------------------------
  //  Segédfüggvények
  // ---------------------------------------------------------------
  function hex4(v) { return '$' + (v >>> 0).toString(16).padStart(4, '0'); }

  /** CAS fájl beolvasása: 128 bájtos UPM fej + 16 bájtos programfej + adat */
  function parseCas(bytes) {
    if (bytes.length < 0x90) throw new Error('Túl rövid CAS fájl.');
    const info = {};
    info.upmType = bytes[0];
    info.type = bytes[0x81];
    info.size = bytes[0x82] | (bytes[0x83] << 8);
    info.autorun = bytes[0x84];
    const avail = bytes.length - 0x90;
    const warnings = [];
    if (bytes[0] !== 0x11) warnings.push('A fájl nem szabványos CAS fejléccel kezdődik (első bájt: $' + bytes[0].toString(16) + ').');
    if (info.type !== 0x01) warnings.push('A CAS programfej típusa nem "program" (1), hanem ' + info.type + '.');
    let size = info.size;
    if (size === 0 || size > avail) {
      if (size > avail) warnings.push('A fejlécben megadott méret (' + size + ') nagyobb, mint a fájlban lévő adat (' + avail + '), a tényleges méretet használom.');
      size = avail;
    }
    return { data: bytes.slice(0x90, 0x90 + size), info: info, warnings: warnings };
  }

  /** CAS fájl összeállítása programadatból */
  function makeCas(prog, autorun) {
    const n = prog.length + 16;
    const out = new Uint8Array(128 + n);
    out[0] = 0x11; out[1] = 0x00;
    const blocks = Math.floor(n / 128) + 1;
    out[2] = blocks & 0xff; out[3] = blocks >> 8;
    out[4] = n % 128;
    out[0x80] = 0x00; out[0x81] = 0x01;
    out[0x82] = prog.length & 0xff; out[0x83] = prog.length >> 8;
    out[0x84] = autorun ? 0xff : 0x00;
    out.set(prog, 0x90);
    return out;
  }

  /**
   * Megjegyzés szöveg TVC kódokra alakítása. A kis- és nagybetűk úgy
   * maradnak, ahogy beírták; a magyar ékezetes betűk a TVC karakterkészlet
   * kódjaira kerülnek (Á É Í Ó Ö Ő Ú Ü Ű = $80..$88, kisbetűk = $90..$98).
   * Más ékezetes betűkről az ékezet lekerül, a nem ábrázolható karakterek
   * kimaradnak.
   */
  const TVC_HU = 'ÁÉÍÓÖŐÚÜŰ', TVC_HU_LOWER = 'áéíóöőúüű';
  const HU_ALIAS = { 'Ô': 'Ő', 'Õ': 'Ő', 'Û': 'Ű', 'ô': 'ő', 'õ': 'ő', 'û': 'ű' };
  function noteBytes(text) {
    const res = [];
    for (let ch of String(text)) {
      ch = HU_ALIAS[ch] || ch;
      let k = TVC_HU.indexOf(ch);
      if (k >= 0) { res.push(0x80 + k); continue; }
      k = TVC_HU_LOWER.indexOf(ch);
      if (k >= 0) { res.push(0x90 + k); continue; }
      let c = ch;
      try { c = c.normalize('NFD').replace(/[\u0300-\u036f]/g, ''); } catch (e) { /* régi böngésző */ }
      for (const cc of c) {
        const code = cc.charCodeAt(0);
        if (code >= 32 && code <= 126) res.push(code);
      }
    }
    return res;
  }

  function ascii(s) { return Array.from(s, ch => ch.charCodeAt(0)); }
  function w16(v) { return [v & 0xff, (v >> 8) & 0xff]; }

  // ---------------------------------------------------------------
  //  Fő függvény: önkicsomagoló fájl készítése
  // ---------------------------------------------------------------
  /**
   * opt: {
   *   input: Uint8Array        – a bemeneti fájl tartalma
   *   inputName: string
   *   headerless: bool         – -bi: fejléc nélküli bináris bemenet
   *   loadAddr: number         – -la (alap $19ef)
   *   jumpAddr: number|null    – -jp; null = BASIC RUN
   *   output: 'cas'|'bin'|'raw'|'demo'   – -oc / -oh / -or / -od
   *   autorun: bool, lineNumber: number|null, note: string
   *   small: bool              – -us
   *   mem: 'UUUS'|'UUUU'|'UUVU'|'UUVS'
   *   di: bool, sp: number|null
   *   mopt: bool, most: number (opcionális, alapból 1 = pontos)
   *   depth, arrivals          – tömörítési paraméterek
   *   progress: function(f)
   * }
   */
  function build(opt) {
    const log = [], warnings = [];
    let src, inputWarnings = [];
    if (opt.headerless) src = opt.input;
    else {
      const p = parseCas(opt.input);
      src = p.data; inputWarnings = p.warnings;
    }
    warnings.push(...inputWarnings);
    const N = src.length;
    if (N === 0) throw new Error('A bemeneti program üres.');
    const la = opt.loadAddr == null ? BASIC_START : opt.loadAddr;
    const jp = opt.jumpAddr == null ? null : opt.jumpAddr;
    const mem = opt.mem || 'UUUS';
    const memVal = MEMCFG[mem];
    if (memVal == null) throw new Error('Ismeretlen memóriakonfiguráció: ' + mem);
    const sp = opt.sp == null ? null : opt.sp;
    const output = opt.output || 'cas';
    const depack = opt.small ? DEPACK_SMALL : DEPACK_FAST;

    // --- paraméterek ellenőrzése (az eredeti program szabályai szerint)
    if (la !== BASIC_START && jp === null && output !== 'raw')
      throw new Error('Ha a betöltési cím nem a BASIC kezdőcím (' + hex4(BASIC_START) + '), meg kell adni az ugrási címet (-jp).');
    if (output === 'cas' || output === 'bin') {
      if (la <= STACK_LAST && sp === null)
        throw new Error('Ha a betöltési cím kisebb vagy egyenlő, mint a stack utolsó bájtja (' + hex4(STACK_LAST) + '), meg kell adni a stack címét (-sp).');
      if (sp !== null && sp >= la)
        throw new Error('A stack pointer címének kisebbnek kell lennie a betöltési címnél.');
      if (jp === null && (mem === 'UUUU' || mem === 'UUVU'))
        throw new Error('Ellentmondó paraméterek! BASIC módban (nincs -jp) a rendszer ROM-nak bekapcsolva kell maradnia (UUUS vagy UUVS).');
    }
    const E = la + N;                 // a kitömörített program vége (kizárólagos)
    if (E > 0x10000)
      throw new Error('A kitömörített program (' + hex4(la) + ' + ' + N + ' bájt) nem fér el a memóriában ($ffff felett végződne).');

    // --- tömörítés
    const packed = compress(src, { depth: opt.depth, arrivals: opt.arrivals, progress: opt.progress });
    const C = packed.length;
    const chk = decompress(packed);
    if (chk.data.length !== N || chk.data.some((v, i) => v !== src[i]))
      throw new Error('Belső hiba: a tömörített adat ellenőrzése sikertelen.');
    if (C >= N) warnings.push('A tömörített méret (' + C + ') nem kisebb, mint a bemenet mérete (' + N + '). Lehet, hogy a bemenet már tömörített.');

    const result = { warnings, log, packedSize: C, inputSize: N };
    const pct = x => (x * 100 / N).toFixed(2) + '%';
    log.push('Forrás: ' + (opt.inputName || 'bemenet') + ' – méret: ' + N + ' (' + hex4(N) + ')');

    if (output === 'raw') {
      result.bytes = packed;
      log.push('Nyers tömörített adat: ' + C + ' (' + hex4(C) + ') – ' + pct(C));
      return result;
    }
    if (output === 'demo') {
      // [kitömörítési cím, hossz, ugrási cím]. Az eredeti program az első mezőbe
      // még 0-t ír (a forrásban TODO: ide a kitömörítési cím kerül), itt már a cím szerepel.
      const jd = jp === null ? la : jp;
      const out = new Uint8Array(6 + C);
      out.set([...w16(la), ...w16(C), ...w16(jd)], 0);
      out.set(packed, 6);
      result.bytes = out;
      log.push('Demo fájl: ' + out.length + ' (' + hex4(out.length) + ') – ' + pct(out.length));
      return result;
    }

    // --- BASIC indítósor: <hossz> <sorszám> PRINT USR(cím) [:! megjegyzés] <sorvég>
    const ln = opt.lineNumber == null ? new Date().getFullYear() : opt.lineNumber;
    if (!(ln >= 0 && ln <= 65535)) throw new Error('Érvénytelen sorszám: ' + ln);
    const note = opt.note ? noteBytes(opt.note) : [];
    function basicLine(usr) {
      const body = [0xdd, ...ascii('USR'), 0x96, ...ascii(String(usr)), 0x95];
      if (note.length) body.push(0xfd, 0xfe, ...note);
      body.push(0xff);
      const line = [0, ...w16(ln), ...body];
      line[0] = line.length;
      return line;
    }
    let line = basicLine(0), stubAddr = 0;
    for (let k = 0; k < 4; k++) {          // a cím számjegyeinek száma befolyásolja a hosszt
      stubAddr = BASIC_START + line.length + 3;
      line = basicLine(stubAddr);
    }
    if (line.length > 255) throw new Error('A megjegyzés túl hosszú (a BASIC sor max. 255 bájt lehet).');
    const pre = [...line, 0x00, 0x00, 0x00];    // program vége + kitöltés

    // --- záró rész (a $0100-ra másolt kitömörítő után)
    function tail(S) {
      const t = [0xed, 0xb8,                  // LDDR – tömörített adat a helyére
        0x21, ...w16(S),                      // LD HL,tömörített adat eleje
        0x11, ...w16(la),                     // LD DE,célcím
        0xdd, 0xe5, 0xcd, ...w16(DEPACK_ADDR), 0xdd, 0xe1,   // PUSH IX / CALL depack / POP IX
        0x3e, memVal, 0xd3, 0x02];            // LD A,lapozás / OUT (02),A
      if (memVal !== MEMCFG.UUUS) t.push(0x32, 0x03, 0x00);  // LD (0003),A – P_SAVE
      t.push(opt.di ? 0xf3 : 0xfb);           // DI / EI
      if (jp !== null) t.push(0xc3, ...w16(jp));
      else t.push(0x3a, 0xb6, 0xcf, 0xfe, 0x32, 0xca, 0xed, 0xd6, 0xc3, 0x1b, 0xde);
      // LD A,(CFB6) / CP '2' / JP Z,D6ED (BASIC 2.x RUN) / JP DE1B (BASIC 1.x RUN)
      return t;
    }
    const tailLen = tail(0).length;
    const relocLen = depack.length + tailLen;
    const relocEnd = DEPACK_ADDR + relocLen;     // kizárólagos
    if (la < relocEnd)
      throw new Error('A betöltési cím (' + hex4(la) + ') ütközik a kitömörítő rutinnal (' + hex4(DEPACK_ADDR) + '–' + hex4(relocEnd - 1) + '). ' +
        (opt.small ? '' : 'A rövid kitömörítővel (-us) kisebb a terület. ') + 'Legkisebb lehetséges cím: ' + hex4(relocEnd) + '.');
    // a kitömörítés közben a stack kb. 16 bájtot használ: [sp-16, sp)
    if (sp !== null && (sp < STACK_NEED || (sp - STACK_NEED < relocEnd && sp > DEPACK_ADDR)))
      throw new Error('A stack (' + hex4(sp) + ') ütközik a kitömörítő rutinnal (' + hex4(DEPACK_ADDR) + '–' + hex4(relocEnd - 1) +
        '). A stack legalább ' + STACK_NEED + ' bájtot használ lefelé; adj meg ' + hex4(relocEnd + STACK_NEED) + ' vagy nagyobb (de a betöltési címnél kisebb) címet, vagy ' + hex4(DEPACK_ADDR) + ' alattit.');

    const headLen = 1 + (sp !== null ? 4 : 0) + 4 + 3 + 3 + 3 + 2 + 3 + 3 + 3 + 3;
    const stubLen = headLen + relocLen;
    const progLen = pre.length + stubLen + C;
    const loadLast = BASIC_START + progLen - 1;    // a betöltött fájl utolsó bájtja
    if (loadLast > 0xffff) throw new Error('A tömörített fájl túl nagy.');

    // --- a tömörített adat végső helye (P = utolsó bájt címe)
    // helyben kitömörítés feltétele: első bájt címe >= la + maxLag + 1
    const Pmin = la + chk.maxLag + 1 + C - 1;
    let P, off = 0;
    if (opt.mopt) {
      const base = Math.max(loadLast, E);
      // pontos érték; opcionálisan (opt.most) lépésköz többszörösére kerekítve
      const step = Math.max(1, opt.most | 0 || 1);
      off = Math.max(0, Pmin - base);
      off = Math.ceil(off / step) * step;
      P = base + off;
      if (P > 0xffff)
        throw new Error('Memória túlcsordulás: a felhasznált memória vége (' + hex4(P) + ') nagyobb, mint $ffff.');
    } else {
      P = 0xffff;
      if (P < Pmin)
        throw new Error('A program nem tömöríthető ki helyben: a tömörített adat a memória végén is ütközne a kitömörített programmal (' +
          (Pmin - P) + ' bájttal kevés a hely).');
      if (P < loadLast) throw new Error('A betöltött fájl túl nagy.');
    }
    const S = P - C + 1;
    const dataStart = loadLast - C + 1;

    // --- összerakás
    const head = [0xf3];                                       // DI
    if (sp !== null) head.push(0x21, ...w16(sp), 0xf9);        // LD HL,sp / LD SP,HL
    head.push(0x3e, MEMCFG.UUUU, 0xd3, 0x02);                  // teljes RAM a kitömörítéshez
    const relocSrc = stubAddr + headLen;
    head.push(0x21, ...w16(relocSrc), 0x11, ...w16(DEPACK_ADDR), 0x01, ...w16(relocLen), 0xed, 0xb0);
    head.push(0x21, ...w16(loadLast), 0x11, ...w16(P), 0x01, ...w16(C));
    head.push(0xc3, ...w16(DEPACK_ADDR + depack.length));      // JP a záró részre
    if (head.length !== headLen) throw new Error('Belső hiba (fej hossza).');
    const prog = new Uint8Array(progLen);
    let q = 0;
    prog.set(pre, q); q += pre.length;
    prog.set(head, q); q += head.length;
    prog.set(depack, q); q += depack.length;
    prog.set(tail(S), q); q += tailLen;
    prog.set(packed, q); q += C;
    if (q !== progLen || BASIC_START + pre.length !== stubAddr) throw new Error('Belső hiba (összeállítás).');

    result.prog = prog;
    result.bytes = output === 'cas' ? makeCas(prog, !!opt.autorun) : prog;
    result.layout = { la, E, jp, stubAddr, loadLast, P, S, off, dataStart, relocEnd, maxLag: chk.maxLag };
    log.push('Tömörített program (CAS fejléc nélkül): ' + prog.length + ' (' + hex4(prog.length) + ') – ' + pct(prog.length));
    log.push('  ebből tömörített adat: ' + C + ' bájt, kitömörítő + indító: ' + (progLen - C) + ' bájt');
    if (jp !== null) log.push('Indítási cím: ' + hex4(jp)); else log.push('Indítás: BASIC RUN');
    log.push('Betöltött terület: ' + hex4(BASIC_START) + ' – ' + hex4(loadLast));
    log.push('Kitömörített program: ' + hex4(la) + ' – ' + hex4(E - 1));
    log.push('Kitömörítés közben használt memória: ' + hex4(la) + ' – ' + hex4(P));
    if (opt.mopt) log.push('Memória vég offszet: ' + hex4(off));
    return result;
  }

  function defaultName(name, output) {
    const base = String(name || 'program').replace(/\.[^.\/\\]*$/, '');
    return base + '-cr.' + (output === 'cas' ? 'cas' : output === 'demo' ? 'dbin' : 'bin');
  }

  return { noteBytes, compress, decompress, parseCas, makeCas, build, defaultName, DEPACK_FAST, DEPACK_SMALL, MEMCFG, BASIC_START };
}

if (typeof module !== 'undefined' && module.exports) module.exports = autvcCoreFactory();
