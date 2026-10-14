#!/bin/bash
# Package-macOS.sh - Stage ReStreet.app and an optional DMG from an existing
# macOS build (see BuildFifaStreet-macOS.sh). No rebuild, no game data.
#
# Usage:
#   Installer/Package-macOS.sh [--build <dir>] [--output <dir>]
#     [--dmg] [--version <ver>] [--force]
#
# Defaults:
#   --build   dist/mac-build/FifaStreetRex/out/build/mac-arm64-release
#   --output  dist/mac-dist
#   --version 1.2.0
#
# Result:
#   <output>/ReStreet.app          (double-clickable; runs windowed via the
#                                   bundled ReStreet launcher script)
#   <output>/ReStreet-macOS-arm64.dmg   (only with --dmg; needs hdiutil)
#
# Notes:
# - The bundle preserves the build tree's relative layout (dylibs beside the
#   executable, vulkan/ subtree): @executable_path rpaths and the MoltenVK
#   ICD lookup (vulkan_moltenvk.cpp) keep working unchanged.
# - Binaries are ad-hoc signed (codesign -s -) so Gatekeeper lets a local
#   build run. Distributing outside the Mac App Store / without a Developer
#   ID still requires the recipient to clear the quarantine flag once:
#   xattr -dr com.apple.quarantine ReStreet.app
# - GameData is NOT included: wire it with Installer/Install-macOS.sh.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/dist/mac-build/FifaStreetRex/out/build/mac-arm64-release"
OUT="$REPO/dist/mac-dist"
VERSION="1.2.0"
DMG=0; FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --build) BUILD="${2:?--build needs a directory}"; shift 2 ;;
    --output) OUT="${2:?--output needs a directory}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --dmg) DMG=1; shift ;;
    --force) FORCE=1; shift ;;
    --help|-h) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

[ -x "$BUILD/fifastreet" ] || { echo "fifastreet binary not found in $BUILD (run BuildFifaStreet-macOS.sh first)" >&2; exit 1; }
for dylib in librexruntime.dylib librexgpu-xenos.dylib libfifastreet_fifadllzf_xex.dylib libfifastreet_FootballCompEngzf_xex.dylib; do
  [ -f "$BUILD/$dylib" ] || { echo "missing $dylib in $BUILD" >&2; exit 1; }
done
[ -f "$BUILD/vulkan/share/vulkan/icd.d/MoltenVK_icd.json" ] || { echo "missing MoltenVK ICD in $BUILD/vulkan" >&2; exit 1; }

APP="$OUT/ReStreet.app"
if [ -e "$APP" ]; then
  [ "$FORCE" -eq 1 ] || { echo "$APP exists (re-run with --force)" >&2; exit 1; }
  rm -rf "$APP"
fi

MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
mkdir -p "$MACOS" "$RES"

# --- Info.plist ---------------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ReStreet</string>
  <key>CFBundleDisplayName</key><string>ReStreet - FIFA Street 2012</string>
  <key>CFBundleIdentifier</key><string>com.restreet.fifastreet</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ReStreet</string>
  <key>LSMinimumSystemVersion</key><string>13.3</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>ReStreet community port. Requires your own FIFA Street (2012) Xbox 360 copy.</string>
</dict>
</plist>
EOF

# --- Binaries -----------------------------------------------------------------
cp -p "$BUILD/fifastreet" "$MACOS/fifastreet"
cp -p "$BUILD"/*.dylib "$MACOS/" 2>/dev/null
cp -Rp "$BUILD/vulkan" "$MACOS/vulkan"
cp -p "$REPO/Installer/ReStreet-macOS.sh" "$MACOS/ReStreet"
chmod +x "$MACOS/ReStreet" "$MACOS/fifastreet"

# --- macOS default config (seed; the launcher overrides everything via CLI) ---
# Mirrors the validated windowed setup: fsi path, fast readback with
# memexport, no occlusion queries, async shaders, 720p windowed.
cat > "$RES/fifastreet.toml" <<'EOF'
# ReStreet macOS defaults (packaged seed). The ReStreet launcher passes
# explicit --cvar overrides at every launch, which outrank this file.
render_target_path_vulkan = "fsi"
vulkan_device = -1
execute_unclipped_draw_vs_on_cpu = true
execute_unclipped_draw_vs_on_cpu_with_scissor = false
depth_float24_convert_in_pixel_shader = true
guest_vblank_unlocked = false
readback_resolve = "fast"
readback_memexport = true
readback_memexport_fast = true
clear_memory_page_state = false
occlusion_query_enable = false
async_shader_compilation = true
video_mode_width = 1280
video_mode_height = 720
video_mode_refresh_rate = 60
fullscreen = false
vsync = false
native_2x_msaa = false
swap_post_effect = "none"
bind_debug_overlay = "Home"
vulkan_log_sync_timing = false
vulkan_log_render_targets = false
vulkan_log_resolve_contents = false
EOF
# The game resolves its config beside the executable: seed it there too.
cp -p "$RES/fifastreet.toml" "$MACOS/fifastreet.toml"

cat > "$RES/README-macOS.txt" <<EOF
ReStreet ${VERSION} for macOS (Apple Silicon) - experimental.

1. Run Installer/Install-macOS.sh to provide your own game copy
   (ISO or extracted GameData) and wire it to this app.
2. Double-click ReStreet.app to play (windowed, 720p, Balanced profile).
   For other profiles use Contents/MacOS/ReStreet --help.
3. The game needs your own FIFA Street (2012) Xbox 360 copy; no game
   files are included. Offline only, no online play.

Known macOS issues: fullscreen presents black (stay windowed), and a
startup race is contained automatically. See docs/STATUS.md.
EOF

# --- Verify -------------------------------------------------------------------
echo "--- verify ---"
otool -L "$MACOS/fifastreet" | head -8
[ -f "$MACOS/vulkan/share/vulkan/icd.d/MoltenVK_icd.json" ] && echo "ICD: OK"
[ -f "$MACOS/librexruntime.dylib" ] && echo "runtime: OK"
[ -f "$MACOS/libfifastreet_fifadllzf_xex.dylib" ] && echo "guest modules: OK"

# --- Ad-hoc sign (binaries only; the toml stays editable) ---------------------
if command -v codesign >/dev/null 2>&1; then
  find "$MACOS" -name "*.dylib" -exec codesign --force --sign - {} \; >/dev/null 2>&1
  codesign --force --sign - "$MACOS/fifastreet" >/dev/null 2>&1
  echo "ad-hoc signature applied"
else
  echo "codesign not found - skipping signatures"
fi

# --- DMG (optional) -------------------------------------------------------------
if [ "$DMG" -eq 1 ]; then
  command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil not found - cannot build DMG" >&2; exit 1; }
  STAGE="$OUT/dmg-staging"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -Rp "$APP" "$STAGE/"
  cp -p "$RES/README-macOS.txt" "$STAGE/README.txt"
  DMG_PATH="$OUT/ReStreet-macOS-arm64.dmg"
  rm -f "$DMG_PATH"
  hdiutil create -volname "ReStreet $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null \
    || { echo "DMG creation failed" >&2; exit 1; }
  rm -rf "$STAGE"
  echo "DMG: $DMG_PATH"
fi

echo "=== packaged: $APP ==="
