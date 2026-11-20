// tvc-midi-player - MIDI-lejátszó és konverter Videoton TVC-re
// Copyright (C) 2026 kks2003 és a közreműködők
//
// Ez a program szabad szoftver: terjeszthető és módosítható a Free Software
// Foundation által kiadott GNU General Public License 2. vagy (választás
// szerint) bármely későbbi változata szerint. A programot a hasznosság
// reményében adjuk közre, de MINDENFÉLE GARANCIA NÉLKÜL. Részletek: COPYING.
//
// A böngészős sjasmplus (web/sjasmplus: a build.sh-éval azonos v1.24.0,
// WebAssemblyre fordítva; BSD licenc, sjasmplus/LICENSE.md). A sjasmplus egy
// futás után nem indítható újra, ezért minden fordítás új példány a már
// lefordított WebAssembly-modulból (néhány ms).
(function (root) {
  'use strict';

  // factory: a sjasmplus.js SjasmPlus függvénye; wasm: a sjasmplus.wasm bájtjai
  // -> async run(files, main, outs): files = {útvonal: Uint8Array | string},
  //    outs = {raw: 'build/x.cas', sym: 'build/x.sym'} -> {raw: Uint8Array, sym: szöveg, log}
  async function createAssembler(factory, wasm) {
    const mod = await WebAssembly.compile(wasm);
    return async function run(files, main, outs) {
      let log = '';
      const m = await factory({
        print: (t) => { log += t + '\n'; },
        printErr: (t) => { log += t + '\n'; },
        instantiateWasm: (imports, ok) => { WebAssembly.instantiate(mod, imports).then((inst) => ok(inst, mod)); return {}; },
      });
      const FS = m.FS;
      FS.mkdir('/w');
      for (const [p, data] of Object.entries(files)) {
        const parts = p.split('/');
        let dir = '/w';
        for (const d of parts.slice(0, -1)) {
          dir += '/' + d;
          try { FS.mkdir(dir); } catch (e) { /* már van */ }
        }
        FS.writeFile('/w/' + p, data);
      }
      FS.chdir('/w');
      const args = ['--nologo', '--msg=war', '--raw=' + outs.raw].concat(outs.sym ? ['--sym=' + outs.sym] : [], [main]);
      let rc;
      try { rc = m.callMain(args); }
      catch (e) { throw new Error('a fordító leállt: ' + (e.message || e)); }
      const res = { log };
      try { res.raw = FS.readFile('/w/' + outs.raw); } catch (e) { /* nincs kimenet */ }
      if (outs.sym) try { res.sym = FS.readFile('/w/' + outs.sym, { encoding: 'utf8' }); } catch (e) { /* nincs */ }
      if (rc !== 0 || !res.raw) throw new Error('fordítási hiba: ' + log.trim().split('\n').slice(-3).join(' | '));
      return res;
    };
  }

  // a böngészőben: a sjasmplus.js betöltése és a wasm letöltése (egyszer)
  let loading = null;
  function loadAssembler(base) {
    if (!loading) {
      loading = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = base + 'sjasmplus.js';
        s.onload = () => resolve();
        s.onerror = () => reject(new Error('a sjasmplus.js nem tölthető be'));
        document.head.appendChild(s);
      }).then(() => fetch(base + 'sjasmplus.wasm'))
        .then((r) => { if (!r.ok) throw new Error('a sjasmplus.wasm nem tölthető be'); return r.arrayBuffer(); })
        .then((buf) => createAssembler(root.SjasmPlus, buf));
      loading.catch(() => { loading = null; });
    }
    return loading;
  }

  const api = { createAssembler, loadAssembler };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.TvcAssembler = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
