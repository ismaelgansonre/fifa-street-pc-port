# HANDOFF — Portage macOS FIFA Street via ReXGlue (2026-10-14 soir)

Reprise : lis ceci, puis `bd ready` (projet `fifa_street_pc_port`). Objectif : **booter
`/Users/ismael/Downloads/FIFAStreetXbox.iso`** (déjà extrait) nativement sur M1 Pro.

## État exact à la reprise (CRITIQUE)

Le projet est construit et relie contre le **SDK patché** (`dist/sdk/`, 2 patches, build 19:34).
**MAIS** : le relink final après l'ajout du 2ᵉ patch a été **annulé** — `build/` est encore lié
contre le runtime 19:28 (overlap seul). Le flag `--writable_code_segments` n'est donc **pas encore
testé**.

### Première action (~5 min)
```bash
cmake --build build --parallel 8        # relink + restage du runtime patché (~1-2 min)
zsh scripts/boot-test.sh 45             # boot fenêtré + screenshot (le flag est déjà dans le script)
```
Puis juger : capture `dist/logs/boot-title.png` + `tail build/logs/fifastreet_001.log`.

## La chaîne de débogage (chaque étape prouvée par log)

1. ~~FATAL function-not-in-table~~ → le jeu charge ses DLL par **chemins machine**
   `\Device\Harddisk0\Partition1\...` ; le registre généré ne connaît que les noms nus.
   **Fix (commit 9f56983)** : alias de registre device-path dans `src/fifastreet_app.h::OnPostSetup`.
2. ~~Dirty Disc Error~~ → le dispatcher stock v0.10.0 compte une **zone de thunks imaginaire**
   après chaque image dans son test de chevauchement ; celle de default.xex recouvre la base
   préférée de fifadllzf (0x82300000). **Fix (commit b27eef3)** :
   `patches/rexglue-v0.10.0-image-overlap-fix.patch` (comparaison d'images pures, même sémantique
   que le fork Windows de référence) — SDK source construit dans `dist/sdk/` via
   `scripts/sdk-build-patched.sh`, le SDK téléchargé `ReXGlue/` reste **intact** (règle utilisateur).
3. **En cours** : tempête `write of guest 0x823F2E90` (dans l'image fifadllzf, pages code/rodata
   protégées ; le jeu écrit dedans — boucle ~3/s, pas de fenêtre). `--writable_executable_memory`
   (stock) ne couvre PAS ce cas. **Fix en attente de test** : cherry-pick upstream `5e2dae1`
   → `patches/rexglue-v0.10.0-writable-code-segments.patch` (cvar `--writable_code_segments`,
   sections CODE/READONLY_DATA inscriptibles). SDK rebuilt 19:34, **relink + test à faire**.
   Si la tempête persiste : `sample` le process pendant la tempête pour identifier la fonction
   guest fautive, et vérifier quelle section contient 0x823F2E90 (headers XEX de fifadllzf).

## Règles utilisateur (FERMES)

- **SDK `ReXGlue/` immuable** — tout contournement projet d'abord ; un fix SDK = patch documenté
  minimal sur build séparé (`sdk-src/` + `patches/`), jamais modifier le dossier téléchargé.
- **Repartir de zéro** : les notes d'octobre (`memory/2026-10-13|14.md`) sont des ARCHIVES.
  Référence = `windows-version/` (clone du portage Windows d'origine, avec son
  `patches/rexglue-local-changes.patch` de 8 934 lignes).
- **Scripts dans le repo** (`scripts/`), jamais /tmp. Logs dans `dist/logs/`.

## Carte du dépôt

| Chemin | Rôle |
|---|---|
| `ReXGlue/` | SDK officiel prébuildé v0.10.0 (c94f5eb) — INTACT, immuable |
| `sdk-src/` | source officielle c94f5eb + les 2 patches appliqués (build: `scripts/sdk-build-patched.sh`) |
| `dist/sdk/` | SDK patché installé (CMAKE_PREFIX_PATH du projet) |
| `dist/GameData/` | ISO extraite (106 fichiers, 4,3 Go) |
| `windows-version/` | référence (portage Windows d'origine) |
| `docs/rexglue-wiki/` | wiki officiel cloné + INDEX.md (écarts v0.3.x/v0.10.0 annotés) |
| `scripts/` | `build-macos.sh` (codegen→build), `boot-test.sh` (boot+capture), `sdk-build-patched.sh`, `winid.swift` |
| `patches/` | les 2 patches SDK documentés |
| `config/` | overrides TOML obligatoires (frontières de fonctions, 57 k lignes pour fifadllzf) |
| `generated/`, `build/` | sorties codegen + build (gitignorés, reconstruisables) |

## Pièges connus

- **NE PAS créer** `GameData/fifadllzf.xex.dllp` (symlink) : le jeu sonde ce nom comme « patch XEX »
  et un fichier présent → Disc Read Error.
- Le codegen v0.10.0 **strip le préfixe `game:\`** du manifest → registre en noms nus.
- `rexglue_setup_target(fifastreet GPU_PLUGINS xenos)` obligatoire sinon pas de renderer.
- TU register géants : bloc `MACOS-PORT-O1-MEGA-TU` dans le CMakeLists (à `-O0`, les barrières
  du fork sont inutiles ; `-fno-global-isel` sinon Localizer quadratique).
- Codegen complet ≈ 10 min mono-cœur (analyse) ; build -j8 ≈ 6 min ; SDK from source ≈ 5 min
  (sous-modules déjà initialisés dans sdk-src).
- Le cache CMake garde `rexglue_DIR` — pour repointer le SDK : `cmake -B build -Urexglue_DIR
  -DCMAKE_PREFIX_PATH=$PWD/dist/sdk ...`.
- Beads : mode **embedded** (`.beads/config.yaml` : `dolt: shared-server: false`) — le serveur
  Dolt partagé casse sinon.

## Jalons Beads (projet `fifa_street_pc_port`)

- ✓ J0 `u2o` audit SDK · ✓ J0b `3gg` wiki + optimisations · ✓ J1 `p34` extraction ISO · ✓ J2 `k2a` build pipeline
- ◐ **J3 `bve`** : premier boot écran-titre — **EN COURS, reprendre ici** (relink + test flag)
- ○ J4 `ayu` : config jouable (toml seed type référence Windows `Installer/payload/Game/fifastreet.toml`
  + `--mnk_mode` clavier) · ○ J5 `mo1` : hygiène repo + commits

## Derniers commits (new-sdk-usage)

`bfb636c gg` (nettoyage utilisateur) → `1fbe2a8` (résidus gitignore) → `0874a90` (projet SDK complet)
→ `748dffc` (windows-version/) → `9f56983` (alias device-path) → `b27eef3` (patch overlap)
→ patch writable_code_segments + scripts (voir `git log --oneline -8`).

Machine : M1 Pro (6P+2E, 16 Go, GPU 14 cœurs Metal 4), macOS 27, Xcode 27, clang 21, cmake 4.4.3,
ninja 1.13.2, ccache 4.14.1.
