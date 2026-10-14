// fifastreet - ReXGlue Recompiled Project
//
// Customize your app by overriding virtual hooks from rex::ReXApp.
// Windows reference: windows-version/Installer/recomp-template/src/fifastreet_app.h

#pragma once

#include <rex/rex_app.h>
#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/system/kernel_state.h>

class FifastreetApp : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<FifastreetApp>(new FifastreetApp(ctx, "fifastreet",
        PPCImageConfig));
  }

  void OnPreSetup(rex::RuntimeConfig& config) override {
    if (config.gpu_plugin.empty()) {
      config.gpu_plugin = "xenos";
    }
  }

  void OnConfigurePaths(rex::PathConfig& paths) override {
    if (paths.game_data_root.empty()) {
      const auto executable_folder = rex::filesystem::GetExecutableFolder();
      for (const auto& candidate : {executable_folder, executable_folder / "GameData",
                                   executable_folder.parent_path() / "GameData",
                                   executable_folder.parent_path()}) {
        std::error_code error;
        if (std::filesystem::is_regular_file(candidate / "default.xex", error)) {
          paths.game_data_root = candidate;
          break;
        }
      }
    }
  }

  void OnCreateDialogs(rex::ui::ImGuiDrawer*) override {
    window()->SetTitle("FIFA Street (macOS)");
  }

  void OnPostSetup() override {
    // FIFA Street builds raw disc device paths at runtime and loads its
    // DLLs through XexLoadImage("\Device\Harddisk0\Partition1\<name>").
    // The generated registry only carries the bare manifest name, and
    // NormalizeGuestPath cannot fold a device path back onto it, so the
    // recompiled-module lookup misses and DllMain jumps into unwired code.
    // Register device-path aliases pointing at the same shared libraries.
    auto* kernel_state = runtime()->kernel_state();
    kernel_state->RegisterRecompiledModule(
        "fifadllzf.xex.dll",
        "\\Device\\Harddisk0\\Partition1\\fifadllzf.xex.dll",
        "fifastreet_fifadllzf_xex");
    kernel_state->RegisterRecompiledModule(
        "footballcompengzf.xex.dll",
        "\\Device\\Harddisk0\\Partition1\\FootballCompEngzf.xex.dll",
        "fifastreet_FootballCompEngzf_xex");

    // FIFA Street uses texture fetch descriptors with the invalid-texture
    // tag. Their address and format fields are still valid and must be
    // decoded (from the Windows reference port).
    rex::cvar::SetFlagByName("gpu_allow_invalid_fetch_constants", "true");
  }
};
