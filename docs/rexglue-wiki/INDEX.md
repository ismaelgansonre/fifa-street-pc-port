# Wiki officiel ReXGlue SDK — Index & Synthèse

Source : clone de https://github.com/rexglue/rexglue-sdk.wiki (commit `ebc5cc8`, 2026-06-04).
Pages copiées telles quelles (noms originaux conservés) dans `docs/rexglue-wiki/`.

> **Écart de version** : le wiki décrit un SDK « v0.3.x » (statut sur `Home.md`), mais le CLI
> installé est **ReXGlue v0.10.0**. Tout ce qui est marqué **[bin v0.10.0]** ci-dessous a été
> vérifié directement contre le binaire `ReXGlue/bin/rexglue` (help, strings, run réel sur
> `dist/GameData/default.xex`) et fait autorité sur le wiki en cas de conflit.

## Pages du wiki

| Fichier | Résumé |
|--|--------|
| `Home.md` | Présentation du projet : recompilation statique X360 → C++, relation à Xenia (runtime dérivé, JIT supprimé), avertissement « pas un turnkey ». |
| `Getting-Started.md` | Prérequis (CMake 3.25+, Ninja, Clang 20+), install du SDK, `rexglue init`, codegen via la cible CMake `<app>_codegen`, itération sur les appels non résolus avec `--force`. |
| `Contributing.md` | Guidelines contribution : style Google C++, build cmake --preset, workflow git (rebase, LF). |
| `rexglue-CLI-Commands.md` | Référence des sous-commandes `init` / `codegen` / `migrate` / `recompile-tests` + flags globaux (log, `--force`, `--enable_exception_handlers`). |
| `rexglue-CLI-Configuration-File.md` | Référence du TOML de codegen : champs requis, options de localisation des registres (`skip_lr`, `cr_as_local`, …), `[analysis]` (max_jump_extension, data_region_threshold, large_function_threshold), `[functions]`, `[[switch_tables]]`, `[[invalid_instructions]]`, `[[midasm_hook]]`, `[rexcrt]`. |
| `Codegen-Pipeline-Overview.md` | Les 7 stades d'analyse (Register, Scan, Discover, GapFill, Discover, Merge, Validate) puis la recompilation PPC→C++ ; mécanismes de découverte (signatures, vtables, blocs, EH, config) ; MMIO, jump tables, CSR flush ; table des autorités de fonctions. |
| `Generated-Code-Structure.md` | Layout de sortie : `{project}_init.h/.cpp`, `{project}_recomp.N.cpp` **découpés pour la compilation parallèle**, macros `DEFINE_REX_FUNC` (alias faible), appels non résolus, intégration `sources.cmake`. |
| `Function-Overrides.md` | Macros `REX_HOOK`, `REX_HOOK_RAW`, stubs, `REX_EXPORT`, `REX_IMPORT` + `CallFrame` pour appeler le code recompilé depuis l'hôte. |
| `Mid-ASM-Hooks.md` | Hooks `[[midasm_hook]]` à une adresse d'instruction précise, signatures void/bool, options de contrôle de flux (return/jump conditionnels). |
| `Runtime-Architecture-Overview.md` | Hiérarchie des sous-systèmes du `Runtime`, séquence d'init en 14 étapes, `FunctionDispatcher` (table guest→host), `ExportResolver`. |
| `ReXApp.md` | Classe de base applicative : cycle de vie, 20+ hooks virtuels (`OnPreSetup`, `OnPostLoadXexImage`, …), `PathConfig`, structure du projet généré par `init`, overlays ImGui (F3/F4/backtick). |
| `Kernel-State-&-Objects.md` | Modèle objet noyau (threads, events, modules), 3 processus, chargement « data-only » des XEX (le code est déjà natif), DPC. |
| `Memory.md` | Espace guest 4 Go mappé à adresse fixe, tableaux des heaps, translation guest↔host, granularité 64 Ko Windows vs 4 Ko Linux, table de fonctions à `IMAGE_BASE+IMAGE_SIZE`, allocateur ReXCRT (o1heap). |
| `Virtual-File-System.md` | Devices VFS, montages par défaut (`game:`, `d:`, `update:`, NullDevice pour `\Cache*`), résolution de chemins, I/O fichiers. |
| `CVar-System.md` | Système de config : macros `REXCVAR_DEFINE_*`, précedence CLI > TOML > env (`REX_<NAME>`), lifecycle, callbacks, overlays Settings/Console. |
| `Logging.md` | Logging spdlog par catégories (`rex::log::*`), macros `REXLOG_*`/`REXCPU_*`, `LogConfig`, niveaux, sinks par catégorie. |
| `SDK-Install-Modes.md` | 3 modes d'install (binaire via `find_package(rexglue)` + registre `~/.cmake/packages/rexglue/` sur macOS/Linux, submodule, FetchContent), pinning `REXSDK`/`REXSDK_VERSION`. |
| `_Sidebar.md` / `_Footer.md` | Navigation du wiki (aucun contenu technique). |

## Manifest multi-modules (exe + DLLs guest) — **[bin v0.10.0]**, non documenté dans le wiki

Le wiki v0.3.x décrit un TOML mono-fichier (`project_name`/`file_path`/…). **v0.10.0 refuse ce
format** : « *no [project] section. Pre-manifest single-file configs are no longer converted
automatically* ». Le format est un *manifest* :

```toml
[project]
name = "fifastreet"                 # [project].name requis (identifiant valide)
sdk_version = "0.10.0"
game_root = "…"                     # racine des assets guest

[entrypoint]
file_path = "…/default.xex"         # l'exe principal
out_directory_path = "generated/default"
includes = []

[[modules]]                         # une entrée par DLL guest (ex. fifadllzf, FootballCompEng)
guest_path = "modules/fifadllzf.xex"   # chemin GUEST (pour XexLoadImage) ; "game:\" est retiré, slashes /
file_path = "…/fifadllzf.xex"
out_directory_path = "generated/fifadllzf"  # OBLIGATOIREMENT unique par binaire (sinon erreur)
includes = []
```

- Ajout assisté : `rexglue init --scan-dll` (scanne `--game-root` pour des `.dll` et crée les
  `[[modules]]`), ou `rexglue init module --xex-path … --guest-path …`.
  **Piège CLI11 [bin v0.10.0]** : pour `init module`, les flags requis du parent (`--project-name`,
  `--xex-path`) doivent aussi être passés *avant* le mot-clé `module`.
- Chaque module génère une **shared library** (`dll_targets.cmake`, `rexglue_configure_module_target`),
  colocalisée à côté de l'exe hôte ; chargée au runtime via `module_registry.cpp` /
  `IModuleRegistrar` (cf. `probe_register.cpp` → `<projet>_RegisterFunctions(registrar)`).
- Régénérer un seul module : `rexglue codegen <manifest> --target <nom>` (répétable ; l'entrypoint
  est toujours inclus).
- Chevauchement d'adpaces d'adresses entre modules → erreur « overlaps » : les DLL guest doivent
  charger à des bases distinctes (comme sur console).

## Optimisations (synthèse actionnable pour M1 Pro 8 cœurs / 16 Go)

### A. Vitesse de génération (codegen)

Le pipeline d'analyse est **mono-thread** [bin v0.10.0] : les 7 stades tournent séquentiellement,
il n'y a **aucune option de parallélisation du codegen** (pas de CVar `threads`). Les leviers :

1. **`max_file_size_bytes`** — LE levier build. Défaut **1 048 576 (1 Mio)** [bin v0.10.0, mesuré :
   `codegen.partition.json → max_file_bytes: 1048576`]. Contrôle le découpage des
   `{project}_recomp.N.cpp` « split for parallel compilation » (`Generated-Code-Structure.md`).
   - Valeur **choisie une fois puis persistée** dans `codegen.partition.json` ; la changer
     re-partitionne tout (« *Byte budget changed (…), repartitioning from scratch* ») → recompile
     intégrale. **Choisissez la valeur UNE fois et ne la touchez plus.**
   - Calibration mesurée [bin v0.10.0] : `default.xex` (1,8 Mo, 4 967 fonctions) → 19,7 Mo de C++
     → 20 fichiers ~1 Mio, codegen en 0,7 s. Le module de 27,8 Mo (~75 000 fonctions) extrapolé ≈
     300 Mo de C++ ≈ 300 fichiers à 1 Mio → **parallélisme largement suffisant pour 8 cœurs au
     défaut**. Descendre à `524288` (512 Kio) ne se justifie que si la RAM sature (TUs ~1 Mio à
     -O2 + PCH ≈ 1-2 Go RSS chacune). Ne pas monter au-dessus de 1 Mio (moins de parallélisme,
     pic mémoire plus haut). Une fonction plus grosse que le budget déborde seule dans son fichier
     (« Function 0x… exceeds max_file_size_bytes »).
   - Remplace le CVar `functions_per_file` cité par `Generated-Code-Structure.md` (wiki v0.3.x,
     absent du binaire v0.10.0).
2. **`progress_log_frequency`** — log de progression toutes les N fonctions. Cosmétique (zéro
   impact perf) ; utile pour suivre les longues runs du module de 27,8 Mo (ex. `--progress_log_frequency 1000`).
3. **`max_discovery_iterations` / `max_vtable_iterations` / `max_resolve_iterations`** — plafonds
   de sécurité des boucles à point fixe (Discover tourne « until no new function entry points are
   found », `Codegen-Pipeline-Overview.md`). Ne pas toucher par défaut : les baisser peut tronquer
   la découverte (fonctions manquantes → `UnresolvedCall`), les monter ne sert que si le log montre
   une non-convergence (« *Analyze: N iterations, resolved=…, sealed=X/Y* » avec X<Y). Défauts non
   exposés par `--help` [bin v0.10.0].
4. Analyses à sauter/limiter (`rexglue-CLI-Configuration-File.md`, § Analysis Tuning) :
   `data_region_threshold` (déf. 16), `max_jump_extension` (déf. 65536),
   `large_function_threshold` (déf. 1 Mio, warnings seulement) + `backward_scan_limit`,
   `max_jump_table_entries`, `max_blocks_per_function` [bin v0.10.0]. Tous orientés correction ;
   les laisser par défaut. Éviter seulement `--enable_exception_handlers` tant que le jeu n'en a
   pas besoin (génère des wrappers SEH en plus).
5. **Incremental intégré** [bin v0.10.0] : passer par la cible CMake `<app>_codegen` (méthode
   `Getting-Started.md`) plutôt qu'un codegen manuel — le DEPFILE `codegen.d` (manifest + XEX) et
   les stamps (`codegen.stamp` = empreinte + liste d'outputs, `codegen.build.stamp`) font que ninja
   ne relance codegen que si un input change, et codegen ne réécrit que les partitions modifiées
   (« Codegen summary: N written, M unchanged »). `--ignore-stamp` force la régénération.
6. Options de localisation des registres (`cr_as_local`, `non_volatile_as_local`, …,
   `rexglue-CLI-Configuration-File.md`) : améliorent la **perf runtime** du code généré (variables
   locales optimisables en registres machine, appels `__savegprlr_*` élidés —
   `Codegen-Pipeline-Overview.md`) mais changent tout le code généré → recompilation complète à
   chaque bascule. À figer tôt dans le projet.

### B. Vitesse de build (compilation)

Contexte machine : 8 cœurs (6P+2E, pas d'hyperthreading), 16 Go RAM, clang 21, ninja 1.13.2,
ccache 4.14.1 présent (`/opt/homebrew/bin/ccache`).

1. **`ninja -j8`** (ou `cmake --build … -j 8`). 8 jobs = 1/cœur est l'optimum sur M1 Pro sans SMT ;
   `-j9` n'apporte rien. Si swap pendant les gros builds (surveiller `memory pressure`), redescendre
   à `-j6` (cœurs P seulement) plutôt que réduire les flags.
2. **ccache** : brancher dans le CMakeLists du projet généré :
   ```cmake
   set(CMAKE_C_COMPILER_LAUNCHER ccache)
   set(CMAKE_CXX_COMPILER_LAUNCHER ccache)
   ```
   à placer avant `project()`. Comme codegen ne réécrit que les partitions changées
   (`Generated-Code-Structure.md` + stamps [bin v0.10.0]), ccache dope les rebuilds après
   régénération partielle et les changements de branche. Pour des hits avec les PCH :
   `export CCACHE_SLOPPINESS=pch_defines,time_macros` (et idéalement `CCACHE_COMPILERCHECK=content`
   car clang 21 peut être mis à jour). L'inconvénient : cache disque significatif (~Go).
3. **PCH** : déjà câblés par le SDK — `rexglue.cmake` généré applique
   `target_precompile_headers(<target>_recomp PRIVATE "<projet>_pch.h")` sur la lib objet
   `<target>_recomp` [bin v0.10.0] ; le PCH contient tout `<rex/ppc.h>` etc. **Le garder.**
   Exception critique : les **TU register géantes** (`<projet>_register.cpp` = UNE fonction avec
   ~75 000 `registrar->SetFunction(...)` séquentiels, **sans barrière asm en v0.10.0** [bin v0.10.0,
   vérifié]) — même pathologie que celle rencontrée au 2026-10-13 (SelectionDAG/GlobalISel
   quadratique). Les compiler avec **`-O0 -g0`** + **pas de PCH optimisé** (propriété CMake
   `SKIP_PRECOMPILE_HEADERS` sur le fichier, un PCH construit à -O0 reste OK) et **`-fno-global-isel`**
   sur ces TU seulement. Elles ne se recompilent ensuite jamais (ninja ne les retouche que si le
   registre change).
   ```cmake
   set_source_files_properties(generated/<mod>/<mod>_register.cpp PROPERTIES
       SKIP_PRECOMPILE_HEADERS ON
       COMPILE_OPTIONS "-O0;-g0;-fno-global-isel")
   ```
4. **Debug info du code généré** : la variable SDK `REXGLUE_RECOMP_DEBUG_INFO`
   (`line-tables-only` par défaut | `full` | `none`) pilote `-gline-tables-only`/`-g0` sur les
   sources recompilées [bin v0.10.0, rexglue.cmake]. Rester en `line-tables-only` pour itérer
   (moins de RAM/disco par TU) ; `none` pour les builds de perf.
5. **Unity builds : NON.** Le découpage `recomp.N.cpp` existe précisément pour paralléliser
   (`Generated-Code-Structure.md`) ; fusionner recrée des TUs géantes et perd le -j8.
6. **LTO : NON pour itérer.** ~300 Mo de code généré → liens monolithiques très longs et gourmands
   en RAM. Au pire ThinLTO sur le SDK seul pour un build de release final, jamais sur le code
   recompilé pendant le développement.
7. **`-mcpu=apple-m1`** : les presets générés ne mettent que `-march=armv8-a` sur mac-arm64
   [bin v0.10.0, CMakePresets.json] ; `-mcpu=apple-m1` (ou `native`) sur les sources **hôte**
   (src/) est un plus légitime via `add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-mcpu=apple-m1>)`.
   Ne pas l'appliquer aux TU register (couvert par leur -O0).
8. Basculer `CMAKE_BUILD_TYPE` Debug→Release change tout le graph de recompilation → ccache misses
   ; garder un build dir par preset (déjà le cas : `out/build/<preset>`).

### C. macOS arm64 / MoltenVK

- **Staging Vulkan automatique** [bin v0.10.0, `rexglue_helpers.cmake`] : quand `REXGLUE_USE_VULKAN`
  est actif, le SDK copie POST_BUILD `libvulkan.1.dylib` + `libMoltenVK.dylib` dans
  `<exe>/vulkan/lib/` et l'ICD `MoltenVK_icd.json` dans `<exe>/vulkan/share/vulkan/icd.d/`. Conserver
  cette arborescence exacte dans tout packaging (cf. bundle ReStreet.app du 2026-10-14) — le loader
  attend l'ICD à ce chemin relatif.
- **Rpath** : `rexglue_configure_target` pose `INSTALL_RPATH "@executable_path"` sur macOS (analogue
  de `$ORIGIN`) et copie `librexruntime`/`TracyClient` à côté de l'exe — le SDK rend l'app
  auto-contenue [bin v0.10.0].
- **Wiki `Memory.md`** : granularité d'allocation — la compensation `host_address_offset=0x1000`
  du heap physique 4K (`0xE0000000`) y est décrite « Windows only », mais le PCH généré v0.10.0
  applique `REX_PHYS_HOST_OFFSET` aussi pour `REX_PLATFORM_MAC && REX_ARCH_ARM64` [bin v0.10.0,
  `<projet>_pch.h`] — le wiki est en retard.
- **Wiki `Memory.md` / `SDK-Install-Modes.md`** : l'espace guest 4 Go est mappé à adresse fixe
  (typ. `0x100000000` côté hôte ; le codegen tool-mode v0.10.0 mappe à `0x700000000`) ; le registre
  CMake du SDK vit sous `~/.cmake/packages/rexglue/` sur macOS.
- **Symboles faibles Darwin** : sur Apple, `DEFINE_REX_FUNC` n'est PAS un alias (rejeté par ld64)
  mais un thunk faible `[[clang::musttail]]` vers `__imp__##name` → `&name != &__imp__name`
  [bin v0.10.0, `<projet>_pch.h`]. À savoir quand on branche des hooks `REX_HOOK`.
- Le wiki lui-même ne documente rien d'autre sur macOS/MoltenVK (pas de page GPU/Vulkan au
  2026-06-04) ; les faits ci-dessus viennent du SDK installé.
- Chargement des DLL guest sur POSIX : connu depuis le 2026-10-13 — le registre généré passe un nom
  sans extension et `dlopen` ne complète pas comme Windows ; le SDK v0.10.0 embarque le retry
  `.dylib`/préfixe `lib` à côté de l'exécutable.

### Priorités de lecture

1. `Getting-Started.md` puis `rexglue-CLI-Commands.md` — prise en main et flux build/codegen.
2. `rexglue-CLI-Configuration-File.md` — toutes les options TOML (analysis, overrides, rexcrt).
3. `Codegen-Pipeline-Overview.md` — comprendre Discover/Merge/Validate pour diagnostiquer les
   fonctions manquantes.
4. `Generated-Code-Structure.md` — layout de sortie et découpage parallèle.
5. `Function-Overrides.md` + `Mid-ASM-Hooks.md` — patcher le jeu sans régénérer.
