# SDK séparé pour FIFA Street macOS

Base : ReXGlue `c94f5ebdcb3c9d1a460ca48e04f9758448f8d518` (v0.10.0).
Appliquer les patches uniquement à `sdk-src/`, installer dans `dist/sdk/`.
Le SDK téléchargé `ReXGlue/` reste immuable.

| Patch, dans l'ordre d'application | Rôle |
|---|---|
| `rexglue-v0.10.0-image-overlap-fix.patch` | Charger les images DLL à leur base préférée sans faux chevauchement avec la réserve de thunks. |
| `rexglue-v0.10.0-writable-code-segments.patch` | Fournir `--writable_code_segments`, nécessaire aux écritures du jeu dans ses images. |
| `rexglue-v0.10.0-shared-control-flow.patch` | Reprendre le contrôle de flux partagé du portage Windows : fonction propriétaire, labels locaux, queues partagées et branches CTR externes. |
| `rexglue-v0.10.0-vulkan-3d-textures.patch` | Corriger les dimensions des fetches 2D de textures 3D et rafraîchir leur copie 3D→2D lorsqu'une vue est réutilisée. |
| `rexglue-v0.10.0-vector-pack-fix.patch` | Corriger les packs vectoriels quand destination et source s'aliassent : `vpkuhus`/`vpkuwus` (charger les deux sources avant écriture, saturation non signée) et `vpkd3d128`/`vupkd3d128` (copier la source avant écriture). |
| `rexglue-v0.10.0-present-interval-cap.patch` | FIFA Street : plafonner à 1 le *present interval* demandé par le callback de swap (`fifadllz`, `sub_8270F040`). Le jeu demande 2 dans les menus/replays/cutscenes, ce qui divise le framerate par deux (A ratés). Cvar `guest_present_interval_cap` (défaut 1, 0 = laisser le jeu décider). |
| `rexglue-v0.10.0-vulkan-texture-pipeline-fixes.patch` | Vulkan : lire l'exponent bias des fetch constants au mot **3** au lieu du mot 4 (le DXBC fait déjà ça ; textures sombres/noires/vertes, issue #456), et compiler les pipelines sans pixel shader (ombre/profondeur) en asynchrone au lieu de bloquer le thread de rendu (PR #368). |
| `rexglue-v0.10.0-waitmultiple-backoff.patch` | `WaitMultiple` POSIX : backoff exponentiel (1→16 ms) du polling, au lieu de re-verrouiller chaque mutex toutes les 1 ms ; réduit le CPU du thread audio (PR #368). |
| `rexglue-v0.10.0-vulkan-presenter-pipeline-fix.patch` | Presenter Vulkan : stocker `swapchain_format` une fois le pipeline créé (sinon il est détruit/recréé **à chaque frame** avec une attente GPU complète → ~115 pipelines/s, des dizaines de milliers de warnings primitive restart et une sérialisation CPU/GPU par frame ; issue #507). Active aussi `primitiveRestartEnable` sur le triangle-strip final, requis par Metal (PR #487). |

> **Retiré le 15/10/2026 : `rexglue-v0.10.0-vmsum3fp128-mask.patch`.**
> Le patch changeait le masque `_mm_dp_ps` de `vmsum3fp128` de `0xEF` à `0x7F` :
> c'était une erreur. Pour `simde_mm_dp_ps`, le nibble **haut** sélectionne les
> sources et le nibble **bas** les destinations ; `0xEF` = dot3 des lanes 1,2,3
> (= guest x,y,z, stockage inversé) diffusé sur les 4 lanes, ce qui est exactement
> la sémantique matérielle (Xenia `InstrEmit_vmsum3fp128` = `DotProduct3` + `Splat`).
> Le `0x7F` sommait les lanes 0..2 (= guest w,z,y) et mettait host lane 3 à 0, or
> host lane 3 = guest element 0, celui que le jeu relit (`stvx128` + `lfs`) :
> **joueurs aplatis / invisibles** dans le checkpoint `vmsum-v1-BROKEN`. Vérifié
> empiriquement en compilant `simde_mm_dp_ps` sur arm64.

Le troisième patch est extrait de
`windows-version/patches/rexglue-local-changes.patch`, également présent sur
`main` (origine `4ee3aee`). Il modifie cinq fichiers de codegen, sans reprendre
l'optimisation d'inlining GPR/LR ni les modifications du renderer.

Le cinquième patch est extrait du même `rexglue-local-changes.patch`
(`src/codegen/builders/vector.cpp`, 20 hunks). Le code généré actuel contient des
cas réels d'alias destination==source : 12 `vupkd3d128`, 4 `vpkuwus`,
6 `vpkuwum` et 2 `vpkuhus` où la destination est aussi une source, ce qui corrompt
les données de packing/unpacking. Le patch applique la version de la référence.

**Validé le 14 octobre 2026** : le rebuild codegen + jeu corrige la **vidéo verte**
de l'intro (retour utilisateur). Les textures de joueurs, de terrain et de foule
restent incomplètes, et la scène de match reste lente à charger/rendre ; le menu
Match Setup et l'intro sont corrects.

**Present interval cap (14 octobre 2026)** : appliqué et compilé en runtime seul
(pas de codegen, cible `rexruntime`). Gain observé seul : menu et gameplay un peu
plus rapides, sans plus — le lot timing complet de la référence (`guest_vblank_unlocked`,
True VSync, timer précis, partage du vblank moniteur) n'est pas porté.
`--readback_resolve=full` corrige la foule et la réactivité des entrées (plus de A
à presser deux fois) mais stalle ; c'est le mode validé par la référence, optimisé
là-bas par le lot adaptatif `readback_some_*` absent de notre SDK. Le terrain reste
incorrect même en full.

## Générer et vérifier avant de compiler le jeu

```sh
zsh scripts/sdk-build-patched.sh
zsh scripts/build-macos.sh
zsh scripts/boot-test.sh 45
```

Le script du jeu utilise le même SDK séparé pour le codegen et CMake. Il force
une régénération si le hash du binaire `dist/sdk/bin/rexglue` change : le cache
amont ne connaît que la version SDK et ne distingue pas nos patches locaux.
Les exécutions suivantes conservent le cache par module.

Avant la compilation du jeu, il lance les trois vérificateurs issus du portage
Windows, restaurés sous `scripts/` : aucun saut direct irrésolu, aucun retour
silencieux sur branche externe, et contrôle des régions CTR et allocation.
Une erreur arrête le pipeline ; ne pas lancer de tests de boot en boucle avec
une ancienne DLL.

## Validation au 14 octobre 2026, 20:34

- Les trois patches sont appliqués et vérifiables en sens inverse sur `sdk-src/`.
- Le générateur corrigé compile en Release. Son UUID est
  `30FA9E40-BA7A-3D92-88CD-44CF48432827`, identique dans la sortie source et
  dans `dist/sdk/bin/rexglue` après staging.
- L'installation a copié les fichiers dans `dist/sdk/`, puis échoué sur
  l'enregistrement facultatif dans `~/.cmake/packages/rexglue` (sandbox).
  Le projet utilise explicitement `CMAKE_PREFIX_PATH`, sans ce registre.
- Les anciennes sorties échouent aux contrôles de branches directes et CTR ;
  le contrôle de la région allocation passe.
- La régénération avec le nouvel outil reste à valider : dans la session
  restreinte, le runtime du codegen échoue à réserver la mémoire partagée
  (`Unable to reserve the 4gb guest address space`).

Logs : `dist/logs/sdk-control-flow-build.log`,
`dist/logs/sdk-control-flow-install.log`, `dist/logs/control-flow-pipeline.log`,
`dist/logs/verify-*-before-codegen.log`.

## Lot graphique restant

Le lot Vulkan 3D→2D est maintenant extrait de la référence, appliqué dans
`sdk-src/` et compilé (deux fichiers GPU). Il est testé séparément dans
`dist/render-tests/vulkan-3d-textures-v1/`, préparé par
`python3 scripts/prepare-render-test.py <nom-unique>`. Cette variante remplace
uniquement le plugin GPU du checkpoint ; tous les autres fichiers du runtime
sont vérifiés par SHA-256. Son cache de shaders est isolé. Le résultat visuel
reste à valider ; le renderer du checkpoint n'est pas remplacé.

Le lanceur de variante utilise `run-logged.py --capture-runtime` : `runtime.log`
est capturé dans le même dossier horodaté que la console et affiché en direct
avec `[runtime]`. La rotation est suivie. Le compteur primitive restart compte
les occurrences dans les deux flux, qui peuvent rapporter le même warning.

L'audit de `main` relève d'autres correctifs à examiner séparément : opérations
vectorielles, readback et resolve. Ils ne sont pas inclus dans ce lot. La référence macOS
documente un rendu fenêtré avec `fsi`, alors que le payload générique utilise
`fbo` et le plein écran ; vérifier la configuration effective lors des tests.

## Conserver une version avant le lot suivant

Après compilation, `python3 scripts/freeze-build.py <nom-unique>` préserve le
runtime, le SDK, les sorties générées et les sources du projet sous
`dist/checkpoints/<nom-unique>/`. Le script relance les trois vérificateurs,
enregistre leurs résultats et les empreintes des binaires, puis fournit un
`launch.sh` utilisant les bibliothèques sauvegardées. Le statut de boot reste
`not_verified` : un contrôle statique ne prouve pas le démarrage.

Le checkpoint `2026-10-14-codegen-validated` correspond au build terminé à 20:47,
avec les trois vérifications réussies. Aucun nouveau build n'est nécessaire
pour tester ce checkpoint. Il s'agit d'une sauvegarde locale ignorée par Git ;
le script et les patches constituent les éléments versionnables du dépôt.
