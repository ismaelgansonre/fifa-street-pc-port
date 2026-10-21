// Test du decodeur sur .retex SYNTHETIQUES (pas de jeu requis).
// Les positions attendues sont calculees A LA MAIN (pas via le SDK) :
//  - 8888 tuile, pitch 64 : bloc (32,0) -> offset 0x1000 (formule documentee).
//  - DXT1 tuile, pitch 32 blocs : bloc (8,0) -> offset 0x40.
//  - DXT5 : alpha a0=255,a1=0 -> a2=(6*255)/7=218 ; indices 0 -> 255.
// Ecrit les .retex dans /tmp/texharness/retex-test/ puis les decode.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "decode.h"
#include "retex.h"

static int failures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::printf("FAIL %d: %s\n", __LINE__, #cond);                    \
      ++failures;                                                       \
    } else {                                                            \
      std::printf("ok: %s\n", #cond);                                   \
    }                                                                   \
  } while (0)

static void WriteRetex(const std::string& path, uint32_t w, uint32_t h, uint32_t format,
                       bool tiled, uint32_t pitch, const std::vector<uint8_t>& base) {
  RetexHeader hdr = {};
  std::memcpy(hdr.magic, "RETEX01", 8);
  hdr.width = w;
  hdr.height = h;
  hdr.depth_or_array = 1;
  hdr.dimension = 1;  // k2DOrStacked
  hdr.format = format;
  hdr.tiled = tiled ? 1 : 0;
  hdr.packed_mips = 0;
  hdr.pitch = pitch;
  hdr.mip_max_level = 0;
  hdr.has_base = 1;
  hdr.base_size_bytes = uint32_t(base.size());
  FILE* f = std::fopen(path.c_str(), "wb");
  std::fwrite(&hdr, 1, sizeof(hdr), f);
  std::fwrite(base.data(), 1, base.size(), f);
  std::fclose(f);
}

int main() {
  // 1) 8888 tuile 64x64 : damier + texel rouge place A LA MAIN a 0x1000.
  {
    const uint32_t W = 64, H = 64;
    // Upper bound pour 64x64 4bpb : origine tuile (32,32) + 0x1000.
    // off(32,32) calcule main : macro=(1+1*2)<<9=0xC00, retour 0x6000 -> +0x1000.
    std::vector<uint8_t> tiled(0x7000, 0);
    for (uint32_t y = 0; y < H; ++y)
      for (uint32_t x = 0; x < W; ++x) {
        // Placement via formule directe (copie independante, pas le SDK) :
        // on ne remplit que la diagonale pour rester lisible, le reste = 0.
        (void)x;
        (void)y;
      }
    // Diagonale blanche via adressage manuel simplifie : on utilise les
    // offsets main connus : (0,0)->0, (32,0)->0x1000, (0,32)->0x2000.
    auto put = [&](uint32_t off, uint8_t r, uint8_t g, uint8_t b) {
      tiled[off] = 255;  // guest BE : mot 0xAARRGGBB stocke [AA,RR,GG,BB]
      tiled[off + 1] = r;
      tiled[off + 2] = g;
      tiled[off + 3] = b;
    };
    put(0x0000, 255, 0, 0);    // (0,0) rouge
    put(0x1000, 0, 255, 0);    // (32,0) vert
    put(0x2000, 0, 0, 255);    // (0,32) bleu
    WriteRetex("/tmp/texharness/retex-test/tiled8888.retex", W, H, 6, true, 2, tiled);
    DecodedTexture tex;
    std::string err;
    CHECK(DecodeRetex("/tmp/texharness/retex-test/tiled8888.retex", tex, err));
    if (tex.levels.empty()) {
      std::printf("decode impossible : %s\n", err.c_str());
      return 1;
    }
    CHECK(tex.levels.size() == 1 && tex.levels[0].w == 64 && tex.levels[0].h == 64);
    auto px = [&](uint32_t x, uint32_t y) -> const uint8_t* {
      return &tex.levels[0].rgba[(y * 64 + x) * 4];
    };
    // Encodage guest [AA,RR,GG,BB] + mapping decodeur -> couleurs exactes.
    CHECK(px(0, 0)[0] == 255 && px(0, 0)[1] == 0 && px(0, 0)[2] == 0 && px(0, 0)[3] == 255);
    CHECK(px(32, 0)[0] == 0 && px(32, 0)[1] == 255 && px(32, 0)[2] == 0);
    CHECK(px(0, 32)[0] == 0 && px(0, 32)[1] == 0 && px(0, 32)[2] == 255);
    CHECK(px(1, 1)[0] == 0 && px(1, 1)[1] == 0 && px(1, 1)[2] == 0);
    std::printf("  8888 (0,0)=(%u,%u,%u) (32,0)=(%u,%u,%u) (0,32)=(%u,%u,%u)\n", px(0, 0)[0],
            px(0, 0)[1], px(0, 0)[2], px(32, 0)[0], px(32, 0)[1], px(32, 0)[2],
            px(0, 32)[0], px(0, 32)[1], px(0, 32)[2]);
  }

  // 2) DXT1 tuile 64x64 : bloc rouge place A LA MAIN a 0x40 (= bloc (8,0)).
  {
    std::vector<uint8_t> tiled(0x8000, 0);
    // Bloc DXT1 tout rouge : c0=0xF800, c1=0x001F, indices 0.
    uint8_t red[8] = {0x00, 0xF8, 0x1F, 0x00, 0, 0, 0, 0};
    std::memcpy(&tiled[0x40], red, 8);
    WriteRetex("/tmp/texharness/retex-test/tileddxt1.retex", 64, 64, 18, true, 2, tiled);
    DecodedTexture tex;
    std::string err;
    CHECK(DecodeRetex("/tmp/texharness/retex-test/tileddxt1.retex", tex, err));
    CHECK(tex.levels.size() == 1);
    const uint8_t* p = &tex.levels[0].rgba[(0 * 64 + 33) * 4];
    CHECK(p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255);
    const uint8_t* q = &tex.levels[0].rgba[0];
    CHECK(q[0] == 0 && q[3] == 255);  // bloc (0,0) noir (zeros -> c0=0 <= c1=0 ?)
    std::printf("  DXT1 bloc(8,0)=(%u,%u,%u,%u)\n", p[0], p[1], p[2], p[3]);
  }

  // 3) DXT5 lineaire 8x4 : alpha a0=255,a1=0, indices alpha 0 -> 255.
  {
    // Bloc 0 : couleur rouge, alpha pleine. Bloc 1 : alpha indice 1 -> a=0.
    uint8_t b0[16] = {255, 0, 0, 0, 0, 0, 0, 0, 0x00, 0xF8, 0x1F, 0x00, 0, 0, 0, 0};
    // 16 indices alpha a 1 (3 bits "001" x16, LSB first) = 49 92 24 x2.
    uint8_t b1[16] = {255, 0, 0x49, 0x92, 0x24, 0x49, 0x92, 0x24, 0x00, 0xF8, 0x1F, 0x00,
                      0, 0, 0, 0};
    std::vector<uint8_t> lin(32, 0);
    std::memcpy(&lin[0], b0, 16);
    std::memcpy(&lin[16], b1, 16);
    WriteRetex("/tmp/texharness/retex-test/lineardxt5.retex", 8, 4, 20, false, 1, lin);
    DecodedTexture tex;
    std::string err;
    CHECK(DecodeRetex("/tmp/texharness/retex-test/lineardxt5.retex", tex, err));
    CHECK(tex.levels.size() == 1 && tex.levels[0].w == 8 && tex.levels[0].h == 4);
    const uint8_t* p = &tex.levels[0].rgba[0];
    CHECK(p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255);
    // Bloc 1 : indices alpha = 001 001... -> a1 = 0 -> transparent.
    const uint8_t* r = &tex.levels[0].rgba[(0 * 8 + 4) * 4];
    CHECK(r[3] == 0);
    std::printf("  DXT5 bloc0=(%u,%u,%u,%u) bloc1.alpha=%u\n", p[0], p[1], p[2], p[3], r[3]);
  }

  // 4) DXT3 lineaire : alpha explicite 0xF -> 255.
  {
    uint8_t b[16] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xF8,
                     0x1F, 0x00, 0, 0, 0, 0};
    std::vector<uint8_t> lin(b, b + 16);
    WriteRetex("/tmp/texharness/retex-test/lineardxt3.retex", 4, 4, 19, false, 1, lin);
    DecodedTexture tex;
    std::string err;
    CHECK(DecodeRetex("/tmp/texharness/retex-test/lineardxt3.retex", tex, err));
    const uint8_t* p = &tex.levels[0].rgba[0];
    CHECK(p[0] == 255 && p[3] == 255);
    std::printf("  DXT3 (%u,%u,%u,%u)\n", p[0], p[1], p[2], p[3]);
  }

  if (!failures) std::printf("PASS decode: 4 cas synthetiques\n");
  return failures != 0;
}
