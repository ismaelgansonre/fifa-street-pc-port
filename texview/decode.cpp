#include "decode.h"

#include <algorithm>
#include <cstring>

#include <rex/graphics/pipeline/texture/util.h>

#include "retex.h"

namespace tu = rex::graphics::texture_util;
namespace xenos = rex::graphics::xenos;

namespace {

void DecodeDXTColor(uint16_t c0, uint16_t c1, bool always_four, uint8_t pal[4][4]) {
  auto expand = [](uint16_t c, uint8_t out[4]) {
    out[0] = uint8_t(((c >> 11) * 255 + 15) / 31);
    out[1] = uint8_t((((c >> 5) & 63) * 255 + 31) / 63);
    out[2] = uint8_t(((c & 31) * 255 + 15) / 31);
    out[3] = 255;
  };
  expand(c0, pal[0]);
  expand(c1, pal[1]);
  if (c0 > c1 || always_four) {
    for (int i = 0; i < 4; ++i) {
      pal[2][i] = uint8_t((2 * pal[0][i] + pal[1][i]) / 3);
      pal[3][i] = uint8_t((pal[0][i] + 2 * pal[1][i]) / 3);
    }
  } else {
    for (int i = 0; i < 4; ++i) {
      pal[2][i] = uint8_t((pal[0][i] + pal[1][i]) / 2);
      pal[3][i] = (i == 3) ? 0 : pal[3][i];
    }
    pal[3][0] = pal[3][1] = pal[3][2] = 0;
    pal[3][3] = 0;
  }
}

// Decode un bloc (bytes_per_block = 8 ou 16) vers 16 texels RGBA.
void DecodeBlock(const uint8_t* block, uint32_t format, uint8_t out[16 * 4]) {
  if (format == 6) {  // k_8_8_8_8 : un texel = 4 octets
    std::memcpy(out, block, 4);
    return;
  }
  uint8_t alpha[16];
  const uint8_t* color_block = block;
  if (format == 19) {  // k_DXT2_3 : alpha explicite 4 bits
    for (int i = 0; i < 16; i += 2) {
      alpha[i] = uint8_t((block[i / 2] & 0xF) * 17);
      alpha[i + 1] = uint8_t(((block[i / 2] >> 4) & 0xF) * 17);
    }
    color_block = block + 8;
  } else if (format == 20) {  // k_DXT4_5 : alpha interpolee
    uint8_t a0 = block[0], a1 = block[1];
    uint8_t atab[8];
    atab[0] = a0;
    atab[1] = a1;
    if (a0 > a1) {
      for (int i = 2; i < 8; ++i) atab[i] = uint8_t(((8 - i) * a0 + (i - 1) * a1) / 7);
    } else {
      for (int i = 2; i < 6; ++i) atab[i] = uint8_t(((6 - i) * a0 + (i - 1) * a1) / 5);
      atab[6] = 0;
      atab[7] = 255;
    }
    uint64_t abits = 0;
    for (int i = 0; i < 6; ++i) abits |= uint64_t(block[2 + i]) << (8 * i);
    for (int i = 0; i < 16; ++i) alpha[i] = atab[(abits >> (3 * i)) & 7];
    color_block = block + 8;
  } else {
    for (int i = 0; i < 16; ++i) alpha[i] = 255;
  }
  uint16_t c0 = color_block[0] | (color_block[1] << 8);
  uint16_t c1 = color_block[2] | (color_block[3] << 8);
  uint8_t pal[4][4];
  DecodeDXTColor(c0, c1, format != 18, pal);
  uint32_t idx = color_block[4] | (color_block[5] << 8) | (color_block[6] << 16) |
                 (color_block[7] << 24);
  for (int i = 0; i < 16; ++i) {
    int sel = (idx >> (2 * i)) & 3;
    out[i * 4 + 0] = pal[sel][0];
    out[i * 4 + 1] = pal[sel][1];
    out[i * 4 + 2] = pal[sel][2];
    out[i * 4 + 3] = (format == 18 && c0 <= c1 && sel == 3) ? 0 : alpha[i];
  }
}

}  // namespace

bool DecodeRetex(const std::string& path, DecodedTexture& out, std::string& error) {
  RetexFile file;
  if (!ReadRetex(path, file)) {
    error = "illisible ou magic invalide";
    return false;
  }
  const RetexHeader& h = file.header;
  if (h.dimension != uint32_t(xenos::DataDimension::k2DOrStacked)) {
    error = "dimension non-2D non supportee";
    return false;
  }
  if (h.format != 6 && h.format != 18 && h.format != 19 && h.format != 20) {
    error = "format non supporte";
    return false;
  }
  const uint32_t block_w = (h.format == 6) ? 1 : 4;
  const uint32_t block_h = (h.format == 6) ? 1 : 4;
  const uint32_t bpb = (h.format == 6) ? 4 : (h.format == 18 ? 8 : 16);
  uint32_t bpb_log2 = 0;
  for (uint32_t v = bpb; v > 1; v >>= 1) ++bpb_log2;

  tu::TextureGuestLayout layout = tu::GetGuestTextureLayout(
      xenos::DataDimension::k2DOrStacked, h.pitch, h.width, h.height, 1, h.tiled != 0,
      xenos::TextureFormat(h.format), h.packed_mips != 0, h.has_base != 0, h.mip_max_level);

  auto level_addr = [&](const tu::TextureGuestLayout::Level& lvl, const uint8_t* region,
                        uint32_t bx, uint32_t by) -> const uint8_t* {
    if (!h.tiled) return region + by * lvl.row_pitch_bytes + bx * bpb;
    uint32_t pitch_blocks = lvl.row_pitch_bytes / bpb;
    return region + tu::GetTiledOffset2D(int32_t(bx), int32_t(by), pitch_blocks, bpb_log2);
  };

  // Niveaux stockes : 0 (base) puis 1..min(max, packed).
  uint32_t packed = layout.packed_level;
  uint32_t last = std::min(h.mip_max_level, packed == UINT32_MAX ? h.mip_max_level : packed);
  for (uint32_t level = 0;; ++level) {
    bool is_base = (level == 0);
    if (!is_base && level > last) break;
    if (is_base && !h.has_base) {
      if (last == 0) break;
      continue;
    }
    uint32_t lw = std::max(h.width >> level, 1u);
    uint32_t lh = std::max(h.height >> level, 1u);
    uint32_t bw = (lw + block_w - 1) / block_w;
    uint32_t bh = (lh + block_h - 1) / block_h;
    const tu::TextureGuestLayout::Level& lvl = is_base ? layout.base : layout.mips[level];
    const uint8_t* region =
        is_base ? file.base_bytes.data() : file.mips_bytes.data() + layout.mip_offsets_bytes[level];
    DecodedImage img;
    img.w = bw * block_w;
    img.h = bh * block_h;
    img.rgba.assign(img.w * img.h * 4, 0);
    if (level == packed) {
      // Mip tail : chaque bloc lu a sa position packee (modele tuile 32x32).
      uint32_t ox = 0, oy = 0, oz = 0;
      tu::GetPackedMipOffset(h.width, h.height, 1, xenos::TextureFormat(h.format), level, ox,
                             oy, oz);
      for (uint32_t by = 0; by < bh; ++by)
        for (uint32_t bx = 0; bx < bw; ++bx) {
          const uint8_t* src;
          if (!h.tiled) {
            src = region + (oy + by) * lvl.row_pitch_bytes + (ox + bx) * bpb;
          } else {
            src = region + tu::GetTiledOffset2D(int32_t(ox + bx), int32_t(oy + by), 32,
                                                bpb_log2);
          }
          uint8_t blk[16 * 4];
          DecodeBlock(src, h.format, blk);
          for (uint32_t y = 0; y < block_h; ++y)
            for (uint32_t x = 0; x < block_w; ++x)
              std::memcpy(&img.rgba[((by * block_h + y) * img.w + (bx * block_w + x)) * 4],
                          &blk[(y * block_w + x) * 4], 4);
        }
    } else {
      for (uint32_t by = 0; by < bh; ++by)
        for (uint32_t bx = 0; bx < bw; ++bx) {
          uint8_t blk[16 * 4];
          DecodeBlock(level_addr(lvl, region, bx, by), h.format, blk);
          for (uint32_t y = 0; y < block_h; ++y)
            for (uint32_t x = 0; x < block_w; ++x)
              std::memcpy(&img.rgba[((by * block_h + y) * img.w + (bx * block_w + x)) * 4],
                          &blk[(y * block_w + x) * 4], 4);
        }
    }
    if (h.format == 6) {
      // Guest big-endian : le mot 0xAARRGGBB est stocke dans l'ordre
      // [AA,RR,GG,BB], donc RGBA = (byte1, byte2, byte3, byte0), sans swap.
      // Verifie par le test (rouge/vert/bleu aux positions calculees main).
      for (size_t i = 0; i < img.rgba.size(); i += 4) {
        uint8_t a = img.rgba[i], r = img.rgba[i + 1], g = img.rgba[i + 2], b = img.rgba[i + 3];
        img.rgba[i] = r;
        img.rgba[i + 1] = g;
        img.rgba[i + 2] = b;
        img.rgba[i + 3] = a;
      }
    }
    out.levels.push_back(std::move(img));
    if (level == last) break;
  }

  out.name = path.substr(path.find_last_of("/\\") + 1);
  out.format = h.format;
  out.tiled = h.tiled != 0;
  out.packed_mips = h.packed_mips != 0;
  if (out.levels.empty()) {
    error = "aucun niveau";
    return false;
  }
  return true;
}
