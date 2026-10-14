# Validation and known limitations

Last updated: **11 October 2026**, for **ReStreet v1.2** (offline only). This page separates what was tested from what was not.

## What was tested for v1.2

All of this was tested by the developer on one Windows 11 PC with an AMD Radeon RX 9070 XT and a Ryzen 5 7600, at 100% display scale.

| Check | Result |
|---|---|
| Direct3D 12 at 60 Hz: menus, cutscenes, goals, replays and match setup at 60 FPS | Passed |
| Vulkan: goal replays sharp (no blur) | Passed |
| Vulkan: menus at 60 FPS, main menu not stretched | Passed |
| Update over v1.1 offline (installer `--update-test` on a copy) | Passed |
| Update over v1.1 with the online patch: files replaced, online patch removed, settings kept | Passed |

**Not yet tested on v1.2:** a clean installation from the ISO, NVIDIA and Intel graphics, the update over an installation with the v1.0 online patch, a full play session from an updated installation.

Known on v1.2: with VSync on above 60 Hz, some scenes run at half the refresh rate (for example 50 FPS at 100 Hz). Vulkan runs at 30 FPS outside menus on the test PC; Direct3D 12 is recommended.

The game module was rebuilt for v1.2 (the game's own 40 FPS limiter for replays and cutscenes now follows the refresh rate chosen in the launcher). World Tour and Practice were validated on earlier releases and not repeated.

## Graphics backends

The package contains two validated backend folders, `Game/Backends/D3D12` and `Game/Backends/Vulkan`. The launcher copies the selected backend's `rexruntime.dll` and `rexgpu-xenos.dll` beside `fifastreet.exe` before launch. Direct3D 12 is the default.

### SHA-256 of the backend files in v1.2

| Backend | `rexruntime.dll` | `rexgpu-xenos.dll` |
|---|---|---|
| Direct3D 12 | `D572DF8FBCDB2B8972BBD0A4DA729260088873FF74FD40CB06D95E9568843CD3` | `E9E407D0EE59A8D6FBEE5AD5A98F49727314826687693C00A8FD68D8A9E0FB9F` |
| Vulkan | `870653C3AF20506413F5891A6C21C3E28491994B8691EA371B0D918BDCCBC7BF` | `C956E3B7701032851D46B17D5994A414B1C14C3C835B2EE6052C9F4421598085` |

The installer checks its payload against the hashes in its own manifest before installing.

## Performance options

- **Profiles:** Balanced (the launcher defaults), Quality (2x internal resolution, FXAA Extreme, MSAA), Performance (native resolution, no post-processing, Fast readback, occlusion queries off) and Custom. They only set options the launcher already has.
- **Readback Resolve:** Some is the default in the Balanced and Quality profiles since v1.1: it was reworked to avoid the graphical garbage it used to cause, and it was tested on one GPU only. Full (compatible) is the old default. The Performance profile uses Fast, which gives more FPS under heavy GPU load but has not been validated on other hardware.
- **Shader cache:** a small set of pre-built shaders ships in `Game/shader-seed` and is copied into the player's cache on the first run. It never replaces files the player already has.

## Resolution model

Output resolution and internal rendering scale are independent. Internal resolution is a whole-number multiple of the game's 1280x720 base: 1x is 1280x720, 2x is 2560x1440, 3x is 3840x2160 and 4x is 5120x2880. Higher settings are available for testing and are not a performance guarantee.

## Not tested

- Any GPU other than the AMD Radeon RX 9070 XT (an RX 6700 was used on earlier releases). NVIDIA and Intel graphics have not been tested.
- Weak or old PCs. The system requirements in the README are estimates.
- The Performance profile on a PC where the GPU is the limit.
- Other ISO regions or revisions: the installer accepts only builds that match the three verified module hashes.
- Long World Tour careers, all venues, all controller types and long play sessions.
- Windows 10.

## Known limitations

- No universal hardware, driver or frame-rate guarantee. 3x/4x internal rendering and 4K output are not guaranteed 60 FPS modes.
- No online play in v1.2.
- The window title of the game itself still reads "FIFA Street PC"; the launcher and installer use the ReStreet name.
- The exit prompt only opens with the START + B (START + Circle) shortcut, not from the main menu.
- The installer expands its details panel by 180 px, which does not fit on screens 768 px high or less.
- Free-space requirements depend on extraction and temporary files.

## macOS (Apple Silicon) port status

First native boot achieved on **13 October 2026** on an M1 Pro (macOS 27, arm64, built from source with the SDK's Vulkan backend on MoltenVK). Build instructions are in [BUILDING.md](BUILDING.md).

Tested and working on that date:

- The game builds and boots to the title screen: logos, textures, fonts and the menu load render correctly in a window, with audio. The same state was previously seen under Wine/CrossOver.
- All three recompiled outputs link, including the two guest modules; modules load and their guest code executes.

Packaging (14 October 2026, branch `wiki-side`): `Installer/Package-macOS.sh`
stages a working `ReStreet.app` (binary + guest dylibs + MoltenVK subtree,
ad-hoc signed) with the launcher as `CFBundleExecutable`. Smoke-tested from
the bundle on the same M1 Pro: process alive 28 s, MoltenVK 1.4.1 on Apple
M1 Pro, swapchain created, GameData resolved via `Contents/GameData`. The
Windows launcher/installer remain Windows-only by design (WinForms).

Known issues on macOS (not present on Windows):

- **Startup race (~20-50% of launches, macOS only).** A guest worker thread created before the game's static constructors have run dereferences the task object's dispatch-table pointer (`sub_82050728` reading `[obj+0]`, object `0x8217DD40`) while it is still null and faults in a loop — `read of guest 0x4`, measured up to 229,087 hits in one second while the rest of the game keeps running. Root cause: `ExCreateThread` resumes the created thread immediately (`xthread.cpp`) and Apple Silicon schedules it on another core before the creator writes the pointer; Windows always wins the race. Contained on two levels since 2026-10-13: the runtime logs the first hit per thread then one line per second with a hit counter, and parks the faulting thread (global lock released) so initialization lands and the thread self-heals. A console-faithful fix (queue guest-created threads until the creator's first yield) remains possible if the park ever proves insufficient.
- **Fullscreen presents black.** Use `fullscreen = false` in `fifastreet.toml` (windowed) — windowed rendering is verified. `render_target_path_vulkan = "fsi"` is set in the tested configuration; the default host-render-targets path was not verified separately.
- **Retina 2x swapchain (code fix built 2026-10-13, VALIDATED 2026-10-14).** A 1280x720 window got a 2560x1440 swapchain (contents scale 2.0). `SDL_VIDEO_HIGHDPI_DISABLED=1` is a no-op (SDL2 var, we run SDL3); the 2x comes from the `SDL_WINDOW_HIGH_PIXEL_DENSITY` flag in upstream `window_sdl.cpp`, so the fix is a code patch (`patches/rexglue-macos-addendum.patch` item 8: flag off on macOS) + rebuild. Play-run log confirms `Created 3 swapchain images with size (1280, 720) and contents scale 1.0`. Closed.
- **Shader-cache stall ~20 s when `~/.local/share` is not writable (fixed 2026-10-14, launcher-side).** The run logs `Failed to open ... for writing, persistent shader storage will be disabled` (measured 20:41:53 → 20:42:16, 22.6 s recompiling every boot). The launcher now sets `XDG_CACHE_HOME` into the support dir; success criterion is the absence of that log line, readable without playing.
- **Audio ahead of video.** The audio thread starts at host speed while video is still in the shader stall; with `vsync=off` + immediate presentation nothing re-syncs the guest. Suspected fix: `--vsync on` (FIFO presentation). To validate in one run.
- **Half-screen stripes + magenta crowd: `fast` AND `some` both fail on MoltenVK (14 Oct 2026 screenshots).** Left half vertically striped (partial/pitch-mismatched resolve), spectators magenta (unresolved fetches). Mechanism verified in code (`ReXGlue/src/graphics/command_processor.cpp:236` — the shared `readback_resolve` string overrides the Vulkan legacy bool, so `--readback some` was a genuine `some` run, not a no-op). Next: `full` in one run. If `full` clears it, it becomes the macOS default (perf cost accepted); if not, the split is a present/scissor-side issue, not readback — diagnose with `vulkan_log_resolve_contents` fingerprints.
- **SDK re-cloned pristine (14 Oct 2026).** The `ReXGlue/` tree carried ~93 modified/new files (hand edits on top of the two patches). Rule going forward: SDK is never hand-edited — pristine clone at `c94f5eb` + the two versioned patches only. Old tree kept aside as `ReXGlue-AVANT-reclone-sale/` (delete once the clean build is validated); textual backup of its diff in `/tmp/rexglue-backup.diff`. MoltenVK comes from the SDK submodule `thirdparty/moltenvk` (`db445ff2`), restored by the same re-clone. Rebuild from clean in progress.
- **CPU ~250% (2.5 cores) on M1 Pro.** Expected, not a leak: recompiled PPC thread + CPU-side geometry expansion (`geometryShader is not supported` on MoltenVK → fallback) + audio/readback thread.

## Development method

SamuelitoDaVila directed and tested the project with AI assistance from ChatGPT, OpenAI Codex and Anthropic's Claude (Claude Code). The statements above separate what was actually tested from what still needs broader coverage.
