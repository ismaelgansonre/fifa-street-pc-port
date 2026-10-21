// texview : visionneuse de .retex (vrais octets guest du jeu).
// Usage : texview <dossier-retex> [--export-bmp <dossier-sortie>]
// Touches : gauche/droite = texture, haut/bas = niveau mip,
//           +/- = zoom, R = vue brute (octets lineaires en niveaux de gris),
//           Q ou Echap = quitter. Le titre de la fenetre decrit la texture.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include <SDL3/SDL.h>

#include "decode.h"
#include "retex.h"

namespace fs = std::filesystem;

static void WriteBMP(const char* path, const uint8_t* rgba, int w, int h) {
  int row_stride = (w * 3 + 3) & ~3;
  std::vector<uint8_t> img(size_t(row_stride) * h, 0);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      img[size_t(y) * row_stride + x * 3 + 0] = rgba[size_t(y * w + x) * 4 + 2];
      img[size_t(y) * row_stride + x * 3 + 1] = rgba[size_t(y * w + x) * 4 + 1];
      img[size_t(y) * row_stride + x * 3 + 2] = rgba[size_t(y * w + x) * 4 + 0];
    }
  uint8_t hdr[54] = {};
  hdr[0] = 'B';
  hdr[1] = 'M';
  *reinterpret_cast<uint32_t*>(hdr + 2) = uint32_t(54 + img.size());
  *reinterpret_cast<uint32_t*>(hdr + 10) = 54;
  *reinterpret_cast<uint32_t*>(hdr + 14) = 40;
  *reinterpret_cast<int32_t*>(hdr + 18) = w;
  *reinterpret_cast<int32_t*>(hdr + 22) = h;
  *reinterpret_cast<uint16_t*>(hdr + 26) = 1;
  *reinterpret_cast<uint16_t*>(hdr + 28) = 24;
  FILE* f = std::fopen(path, "wb");
  if (!f) return;
  std::fwrite(hdr, 1, 54, f);
  for (int y = h - 1; y >= 0; --y) std::fwrite(&img[size_t(y) * row_stride], 1, row_stride, f);
  std::fclose(f);
}

static const char* FormatName(uint32_t f) {
  switch (f) {
    case 6:
      return "8888";
    case 18:
      return "DXT1";
    case 19:
      return "DXT3";
    case 20:
      return "DXT5";
    default:
      return "?";
  }
}

int main(int argc, char** argv) {
  if (argc < 2) {
    std::printf("usage: texview <dossier-retex> [--export-bmp <dossier>]\n");
    return 1;
  }
  std::string export_dir;
  for (int i = 2; i + 1 < argc; ++i)
    if (!std::strcmp(argv[i], "--export-bmp")) export_dir = argv[i + 1];

  std::vector<std::string> files;
  for (const auto& entry : fs::directory_iterator(argv[1])) {
    if (entry.path().extension() == ".retex") files.push_back(entry.path().string());
  }
  if (files.empty()) {
    std::printf("aucun .retex dans %s\n", argv[1]);
    return 1;
  }
  std::vector<DecodedTexture> textures;
  for (const auto& path : files) {
    DecodedTexture tex;
    std::string error;
    if (DecodeRetex(path, tex, error)) {
      textures.push_back(std::move(tex));
    } else {
      std::printf("ignore %s : %s\n", fs::path(path).filename().string().c_str(),
                  error.c_str());
    }
  }
  if (textures.empty()) {
    std::printf("rien de decodable\n");
    return 1;
  }
  std::sort(textures.begin(), textures.end(), [](const DecodedTexture& a,
                                                 const DecodedTexture& b) {
    size_t sa = a.levels.empty() ? 0 : size_t(a.levels[0].w) * a.levels[0].h;
    size_t sb = b.levels.empty() ? 0 : size_t(b.levels[0].w) * b.levels[0].h;
    return sa > sb;
  });
  std::printf("%zu textures decodables\n", textures.size());

  if (!export_dir.empty()) {
    std::error_code ec;
    fs::create_directories(export_dir, ec);
    for (size_t i = 0; i < textures.size(); ++i) {
      const auto& tex = textures[i];
      for (size_t l = 0; l < tex.levels.size(); ++l) {
        char name[256];
        std::snprintf(name, sizeof(name), "%03zu_mip%zu_%s.bmp", i, l,
                      tex.name.c_str());
        // Evite les '/' residuels du nom (il n'y en a pas, par construction).
        WriteBMP((fs::path(export_dir) / name).string().c_str(), tex.levels[l].rgba.data(),
                 int(tex.levels[l].w), int(tex.levels[l].h));
      }
    }
    std::printf("export BMP termine dans %s\n", export_dir.c_str());
    return 0;
  }

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    std::printf("SDL_Init: %s\n", SDL_GetError());
    return 1;
  }
  SDL_Window* window = SDL_CreateWindow("texview", 1280, 800, SDL_WINDOW_RESIZABLE);
  SDL_Renderer* renderer = SDL_CreateRenderer(window, nullptr);
  if (!window || !renderer) {
    std::printf("SDL: %s\n", SDL_GetError());
    return 1;
  }

  size_t index = 0, level = 0, zoom = 0;
  int zooms[] = {1, 2, 4, 8};
  bool raw = false;
  bool quit = false;
  SDL_Texture* gpu = nullptr;
  std::vector<uint8_t> raw_gray;
  auto refresh = [&]() {
    if (gpu) SDL_DestroyTexture(gpu);
    gpu = nullptr;
    const auto& tex = textures[index];
    level = std::min(level, tex.levels.size() - 1);
    const auto& img = tex.levels[level];
    const uint8_t* pixels = img.rgba.data();
    raw_gray.clear();
    if (raw) {
      // Vue brute : octets du niveau en niveaux de gris (diagnostic packing).
      RetexFile rf;
      if (ReadRetex(std::string(argv[1]) + "/" + tex.name, rf)) {
        const auto& src = (level == 0 || rf.mips_bytes.empty()) ? rf.base_bytes : rf.mips_bytes;
        size_t n = std::min(src.size(), size_t(img.w) * img.h);
        raw_gray.assign(size_t(img.w) * img.h * 4, 0);
        for (size_t i = 0; i < n; ++i) {
          raw_gray[i * 4 + 0] = raw_gray[i * 4 + 1] = raw_gray[i * 4 + 2] = src[i];
          raw_gray[i * 4 + 3] = 255;
        }
        pixels = raw_gray.data();
      }
    }
    gpu = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STATIC,
                            int(img.w), int(img.h));
    SDL_UpdateTexture(gpu, nullptr, pixels, int(img.w) * 4);
    SDL_SetTextureScaleMode(gpu, SDL_SCALEMODE_LINEAR);
    char title[256];
    std::snprintf(title, sizeof(title), "%zu/%zu %s %ux%u %s%s mip %zu/%zu x%d%s", index + 1,
                  textures.size(), tex.name.c_str(), img.w, img.h, FormatName(tex.format),
                  tex.tiled ? " tiled" : " linear", level + 1, tex.levels.size(),
                  zooms[zoom], raw ? " RAW" : "");
    SDL_SetWindowTitle(window, title);
  };
  refresh();

  while (!quit) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) quit = true;
      if (event.type == SDL_EVENT_KEY_DOWN) {
        switch (event.key.key) {
          case SDLK_ESCAPE:
          case SDLK_Q:
            quit = true;
            break;
          case SDLK_RIGHT:
            index = (index + 1) % textures.size();
            level = 0;
            refresh();
            break;
          case SDLK_LEFT:
            index = (index + textures.size() - 1) % textures.size();
            level = 0;
            refresh();
            break;
          case SDLK_DOWN:
            level = (level + 1) % textures[index].levels.size();
            refresh();
            break;
          case SDLK_UP:
            level = (level + textures[index].levels.size() - 1) % textures[index].levels.size();
            refresh();
            break;
          case SDLK_PLUS:
          case SDLK_EQUALS:
            zoom = std::min<size_t>(zoom + 1, 3);
            refresh();
            break;
          case SDLK_MINUS:
            zoom = zoom > 0 ? zoom - 1 : 0;
            refresh();
            break;
          case SDLK_R:
            raw = !raw;
            refresh();
            break;
          default:
            break;
        }
      }
    }
    SDL_SetRenderDrawColor(renderer, 18, 18, 22, 255);
    SDL_RenderClear(renderer);
    const auto& img = textures[index].levels[level];
    int ww, wh;
    SDL_GetWindowSize(window, &ww, &wh);
    float scale =
        std::min(float(ww) / img.w, float(wh) / img.h) * float(zooms[zoom]) / 4.0f;
    scale = std::max(scale, 0.05f);
    SDL_FRect dst{(ww - img.w * scale) / 2, (wh - img.h * scale) / 2, img.w * scale,
                 img.h * scale};
    SDL_RenderTexture(renderer, gpu, nullptr, &dst);
    SDL_RenderPresent(renderer);
    SDL_Delay(16);
  }
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();
  return 0;
}
