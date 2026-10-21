// Format .retex : dump brut guest + descripteur, produit par le patch
// rexglue-v0.10.0-texture-dump.patch (--vulkan_dump_textures=<dir>).
// Tous les entiers sont little-endian. Apres l'en-tete : base_size octets
// (niveau 0), puis mips_size octets (niveaux 1..., offsets dans
// TextureGuestLayout::mip_offsets_bytes).
#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

struct RetexHeader {
  char magic[8];  // "RETEX01\0"
  uint32_t width, height, depth_or_array;
  uint32_t dimension;  // xenos::DataDimension (1 = 2D)
  uint32_t format;     // xenos::TextureFormat (6, 18, 19, 20 supportes)
  uint32_t tiled, packed_mips;
  uint32_t pitch;  // base_pitch_texels_div_32 de la fetch constant
  uint32_t mip_max_level, has_base, endianness;
  uint32_t base_size_bytes, mips_size_bytes;
};

struct RetexFile {
  RetexHeader header;
  std::vector<uint8_t> base_bytes;
  std::vector<uint8_t> mips_bytes;
  std::string path;
};

inline bool ReadRetex(const std::string& path, RetexFile& out) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return false;
  RetexHeader h;
  if (std::fread(&h, 1, sizeof(h), f) != sizeof(h)) {
    std::fclose(f);
    return false;
  }
  if (std::memcmp(h.magic, "RETEX01", 7) != 0) {
    std::fclose(f);
    return false;
  }
  if (h.base_size_bytes > (64u << 20) || h.mips_size_bytes > (64u << 20)) {
    std::fclose(f);
    return false;
  }
  out.header = h;
  out.base_bytes.resize(h.base_size_bytes);
  out.mips_bytes.resize(h.mips_size_bytes);
  bool ok = true;
  if (h.base_size_bytes &&
      std::fread(out.base_bytes.data(), 1, h.base_size_bytes, f) != h.base_size_bytes)
    ok = false;
  if (h.mips_size_bytes &&
      std::fread(out.mips_bytes.data(), 1, h.mips_size_bytes, f) != h.mips_size_bytes)
    ok = false;
  std::fclose(f);
  if (!ok) return false;
  out.path = path;
  return true;
}
