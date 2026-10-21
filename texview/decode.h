// Decodage .retex -> RGBA (sans SDL). Reutilise les fonctions de layout du SDK
// (GetGuestTextureLayout, GetTiledOffset2D, GetPackedMipOffset) : c'est le
// MEME calcul d'adressage que le runtime, nourri avec les VRAIS octets guest.
//
// Formats : k_8_8_8_8 (6), k_DXT1 (18), k_DXT2_3 (19), k_DXT4_5 (20).
// Note 8888 : ordre des canaux a confirmer visuellement (voir README).
// Mip tail packe : position des blocs via GetPackedMipOffset (modele "une tuile
// 32x32", experimental pour les petites textures tilees).
#pragma once
#include <cstdint>
#include <string>
#include <vector>

struct DecodedImage {
  uint32_t w = 0, h = 0;
  std::vector<uint8_t> rgba;  // w*h*4
};

struct DecodedTexture {
  std::string name;
  uint32_t format = 0;
  bool tiled = false, packed_mips = false;
  std::vector<DecodedImage> levels;  // [0] = base, [k] = mip k
};

// Remplit levels avec base + mips decodes. Retourne false si non supporte.
bool DecodeRetex(const std::string& path, DecodedTexture& out, std::string& error);
