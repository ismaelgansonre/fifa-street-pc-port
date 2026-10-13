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

Known issues on macOS (not present on Windows):

- **Startup is a coin flip (~50% of launches).** A guest thread reads a manager object before its constructor has run and spins on null-pointer reads (`Unhandled guest access violation: read of guest 0x4`, thousands per second, ~100 MB of log). The rest of the game, including rendering and audio, keeps running, but that launch should be closed and retried. Root cause identified by sampling: `sub_82050728` dereferences the first field of an object passed by a virtual call from the module-init path (`sub_82105838`) before initialization.
- **Fullscreen presents black.** Use `fullscreen = false` in `fifastreet.toml` (windowed) — windowed rendering is verified. `render_target_path_vulkan = "fsi"` is set in the tested configuration; the default host-render-targets path was not verified separately.

## Development method

SamuelitoDaVila directed and tested the project with AI assistance from ChatGPT, OpenAI Codex and Anthropic's Claude (Claude Code). The statements above separate what was actually tested from what still needs broader coverage.
