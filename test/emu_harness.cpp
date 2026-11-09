// Ep128web (ep128emu) natív tesztmeghajtó a TVC MIDI-lejátszóhoz.
//   emu_harness <rom-csomag> <név> <másodperc> <out.wav> <portlog.txt> [stop-mp]
// A /files/<név>.cas fájlnak léteznie kell (a FILE: eszköz könyvtára).
// Bootolja a TVC 64k+ / BASIC 2.2 ROM-ot, beírja: load "<név>" (autorun),
// majd rögzíti a hangkimenetet és a 04h/05h/06h portok írását
// (képkocka, PC, port, érték). stop-mp: ennyi másodperc után ESC-et nyom.
// Környezeti változók: SCREEN=kép.ppm (képernyőkép a végén), DUMP=cím,hossz
// (memória hexában), ALLPORTS=1 (minden port írása a naplóba).
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <sys/stat.h>
extern "C" {
const char *ep_last_error();
int ep_init(int);
int ep_set_machine_type(int);
int ep_reset_memory(int);
int ep_load_rom(int, const char *, int);
int ep_reset(int);
int ep_run(int);
int ep_pc();
int ep_read_memory(int);
void ep_set_key(int, int);
int ep_unpack_rom_package(const char *, const char *);
const float *ep_audio_buffer();
int ep_audio_frames();
void ep_audio_clear();
void ep_dbg_iolog_enable(int);
const uint32_t *ep_frame_buffer();
void ep_dbg_measure_start(int, int, int, int, int);
void ep_dbg_measure_stop();
int ep_dbg_measure_count();
int ep_dbg_measure_kept();
const double *ep_dbg_measure_samples();
int ep_frame_width();
int ep_frame_height();
const char *ep_dbg_iolog(int);
void ep_set_tvc_card256(int, int);
int ep_tvc_card_put_file(const char *, const char *);
void ep_write_memory(int, int);
}
static std::vector<int16_t> audio;
static bool recording = false;
static long frame = 0;
static FILE *plog = 0;
static void readIOLog()
{
  const char *log = ep_dbg_iolog(4096);
  unsigned pc, port, val; int w;
  for (const char *p = log; *p; ) {
    if (std::sscanf(p, "%x %x %x %d", &pc, &port, &val, &w) == 4 && w &&
        (port == 4 || port == 5 || port == 6 || std::getenv("ALLPORTS")))
      std::fprintf(plog, "%ld %04X %02X %02X\n", frame, pc, port, val);
    const char *nl = std::strchr(p, '\n');
    if (!nl) break;
    p = nl + 1;
  }
  ep_dbg_iolog_enable(1);     // a napló törlése
}
// egy képkocka (20 ms); felvétel közben 2 ms-onként olvassuk a portnaplót,
// hogy a 4096 bejegyzéses gyűrűpuffer ne csorduljon túl (pl. betöltéskor)
static void step()
{
  for (int i = 0; i < 10; i++) {
    ep_run(2000);
    if (recording)
      readIOLog();
  }
  frame++;
  if (recording) {
    const float *b = ep_audio_buffer();
    int n = ep_audio_frames();
    for (int i = 0; i < n; i++) {
      float v = b[i * 2] * 32767.0f;
      audio.push_back(int16_t(v > 32767 ? 32767 : (v < -32768 ? -32768 : v)));
    }
  }
  ep_audio_clear();
}
static void runMs(int ms) { for (int i = 0; i < ms / 20; i++) step(); }
static void key(int k) { ep_set_key(k, 1); runMs(100); ep_set_key(k, 0); runMs(100); }
// billentyűkódok: Ep128web test/native_boot.cpp (TVC, magyar kiosztás)
static void typeText(const char *t)
{
  static const int lcodes[26] = {0x0E,0x02,0x03,0x0B,0x15,0x0C,0x0A,0x08,0x48,0x30,0x32,0x34,0x40,
                                 0x00,0x4A,0x4C,0x11,0x13,0x0D,0x14,0x10,0x04,0x16,0x05,0x06,0x12};  // y/z: QWERTZ
  static const int digits[10] = {0x4B,0x19,0x1E,0x1D,0x1B,0x1C,0x1A,0x18,0x28,0x2A};
  for (; *t; t++) {
    if (*t == '"') {
      ep_set_key(0x07, 1); runMs(60); ep_set_key(0x1E, 1); runMs(80); ep_set_key(0x1E, 0); runMs(40);
      ep_set_key(0x07, 0); runMs(60);
    } else if (*t >= 'a' && *t <= 'z') key(lcodes[*t - 'a']);
    else if (*t >= '0' && *t <= '9') key(digits[*t - '0']);
    else if (*t == ' ') key(0x46);
    else if (*t == ',') key(0x42);
    else if (*t == '\n') key(0x3E);
  }
}
static void writeWav(const char *fn, int rate)
{
  FILE *f = std::fopen(fn, "wb");
  if (!f) return;
  uint32_t n = uint32_t(audio.size()) * 2;
  auto u32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
  auto u16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
  std::fwrite("RIFF", 1, 4, f); u32(36 + n); std::fwrite("WAVEfmt ", 1, 8, f);
  u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16);
  std::fwrite("data", 1, 4, f); u32(n);
  std::fwrite(audio.data(), 2, audio.size(), f);
  std::fclose(f);
}
int main(int argc, char **argv)
{
  if (argc < 6) { std::fprintf(stderr, "usage: %s pkg name seconds out.wav portlog [stop]\n", argv[0]); return 2; }
  mkdir("/tmp/tvcroms", 0755);
  // CARD=slot: TVC256k++ kártya a megadott slotban (a SID-lejátszó tesztjéhez)
  int cardSlot = std::getenv("CARD") ? std::atoi(std::getenv("CARD")) : -1;
  if (cardSlot >= 0) ep_set_tvc_card256(1, cardSlot);
  if (ep_init(48000) != 0 || ep_set_machine_type(1) != 0) { std::fprintf(stderr, "init %s\n", ep_last_error()); return 1; }
  if (ep_unpack_rom_package(argv[1], "/tmp/tvcroms") < 10) { std::fprintf(stderr, "unpack %s\n", ep_last_error()); return 1; }
  ep_reset_memory(128);
  const struct { int seg; const char *f; } roms[] = {{0, "tvc22_sys.rom"}, {2, "tvc22_ext.rom"}, {4, "tvcfileio.rom"}};
  for (auto &r : roms) {
    std::string p = std::string("/tmp/tvcroms/") + r.f;
    if (ep_load_rom(r.seg, p.c_str(), 0) != 0) { std::fprintf(stderr, "rom %s: %s\n", r.f, ep_last_error()); return 1; }
  }
  ep_reset(1);
  runMs(4000);
  key(0x3E); runMs(3000);                  // a bekapcsolási kép után Enter; az első leütés elveszhet, ezért " load"
  // CARD_FILE=név,útvonal[;név,útvonal...]: fájlok a kártya PSRAM-meghajtójára, a LOAD a kártyáról tölt
  if (const char *cf = std::getenv("CARD_FILE")) {
    std::string all(cf);
    for (size_t p = 0; p < all.size(); ) {
      size_t q = all.find(';', p);
      std::string a = all.substr(p, q == std::string::npos ? std::string::npos : q - p);
      size_t c = a.find(',');
      if (ep_tvc_card_put_file(a.substr(0, c).c_str(), a.substr(c + 1).c_str()) != 0) { std::fprintf(stderr, "card file: %s\n", ep_last_error()); return 1; }
      if (q == std::string::npos) break;
      p = q + 1;
    }
    ep_write_memory(0x0B05, 0x80 | cardSlot); ep_write_memory(0x0B0D, 0x80 | cardSlot);
  }
  std::printf("isr0=");                     // az IT-belépő a betöltés előtt
  for (int a = 0x38; a < 0x40; a++) std::printf("%02x ", ep_read_memory(a));
  std::printf("\n");
  plog = std::fopen(argv[5], "w");
  std::string cmd = std::string(" load \"") + argv[2] + "\"\n";
  // MEASURE=start,stop (hex): ciklusmérés a két cím között a felvétel alatt
  int mStart = -1, mStop = -1;
  if (const char *m = std::getenv("MEASURE")) {
    std::sscanf(m, "%x,%x", (unsigned *) &mStart, (unsigned *) &mStop);
    ep_dbg_measure_start(mStart, -1, mStop, -1, 0);
  }
  ep_dbg_iolog_enable(1);
  recording = true;            // már a gépeléskor: az autorun rögtön indul
  typeText(cmd.c_str());
  int secs = std::atoi(argv[3]);
  int stopAt = argc > 6 ? std::atoi(argv[6]) : -1;
  // TYPE_AT="mp:szöveg;mp:szöveg": gépelés a felvétel közben (a szövegben
  // a \n Enter); az idő a gépelés kezdetétől számít
  std::vector<std::pair<double, std::string>> typeAt;
  if (const char *t = std::getenv("TYPE_AT")) {
    std::string all(t);
    size_t p = 0;
    while (p < all.size()) {
      size_t q = all.find(';', p);
      std::string item = all.substr(p, q == std::string::npos ? std::string::npos : q - p);
      size_t c = item.find(':');
      if (c != std::string::npos) {
        std::string txt = item.substr(c + 1), out;
        for (size_t i = 0; i < txt.size(); i++) {
          if (txt[i] == '\\' && i + 1 < txt.size() && txt[i + 1] == 'n') { out += '\n'; i++; }
          else out += txt[i];
        }
        typeAt.push_back({std::atof(item.substr(0, c).c_str()), out});
      }
      if (q == std::string::npos) break;
      p = q + 1;
    }
  }
  long frame0 = frame;
  size_t nextType = 0;
  while (frame - frame0 < long(secs) * 50) {
    double now = (frame - frame0) / 50.0;
    if (nextType < typeAt.size() && now >= typeAt[nextType].first) {
      typeText(typeAt[nextType].second.c_str());
      nextType++;
      continue;
    }
    if (stopAt >= 0 && now >= stopAt) {
      ep_set_key(0x38, 1); runMs(200); ep_set_key(0x38, 0);
      stopAt = -1;
      continue;
    }
    step();
  }
  recording = false;
  if (mStart >= 0) {
    int n = ep_dbg_measure_kept();
    const double *sm = ep_dbg_measure_samples();
    double sum = 0, mn = 1e18, mx = 0;
    for (int i = 0; i < n; i++) { double c = sm[i * 2 + 1]; sum += c; mn = c < mn ? c : mn; mx = c > mx ? c : mx; }
    std::printf("measure %04x-%04x: count=%d avg=%.0f min=%.0f max=%.0f sum=%.0f\n", mStart, mStop,
                ep_dbg_measure_count(), n ? sum / n : 0, n ? mn : 0, mx, sum);
    ep_dbg_measure_stop();
  }
  writeWav(argv[4], 48000);
  std::fclose(plog);
  std::printf("pc=%04x isr=", ep_pc());
  for (int a = 0x38; a < 0x40; a++) std::printf("%02x ", ep_read_memory(a));
  std::printf("time=%d\n", ep_read_memory(0x0B1D) | (ep_read_memory(0x0B1E) << 8));
  if (const char *scr = std::getenv("SCREEN")) {      // képernyőkép (PPM)
    int w = ep_frame_width(), h = ep_frame_height();
    const uint32_t *fb = ep_frame_buffer();
    if (FILE *f = std::fopen(scr, "wb")) {
      std::fprintf(f, "P6\n%d %d\n255\n", w, h);
      for (int i = 0; i < w * h; i++) {
        uint32_t px = fb[i];
        std::fputc(px & 255, f); std::fputc((px >> 8) & 255, f); std::fputc((px >> 16) & 255, f);
      }
      std::fclose(f);
    }
  }
  if (const char *d = std::getenv("DUMP")) {          // DUMP=cím,hossz (hex)
    unsigned a = 0, n = 0;
    std::sscanf(d, "%x,%x", &a, &n);
    std::printf("dump %04x:", a);
    for (unsigned i = 0; i < n; i++) std::printf(" %02x", ep_read_memory(int(a + i)));
    std::printf("\n");
  }
  std::printf("basic=");
  for (int a = 0x19EF; a < 0x19EF + 56; a++) std::printf("%02x", ep_read_memory(a));
  std::printf("\n");
  return 0;
}
