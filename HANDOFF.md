# HANDOFF — Portage macOS FIFA Street via ReXGlue (2026-10-14 soir)

Reprise : lis ceci, puis `bd ready` (projet `fifa_street_pc_port`). Objectif : **booter
`/Users/ismael/Downloads/FIFAStreetXbox.iso`** (déjà extrait) nativement sur M1 Pro.

## Session nuit 2026-10-14 → 15 — résumé (à lire en premier)

Acquis de la session, dans l'ordre :

1. **Menu Match Setup qui apparaissait puis disparaissait : RÉSOLU.**
   Cause : transferts de propriété EDRAM des draws sans clipping.
   Solution : `--execute_unclipped_draw_vs_on_cpu` (défaut `false` dans notre SDK,
   `true` dans la config ReStreet). Reste à figer le défaut dans un patch.

2. **Vidéo verte de l'intro : RÉSOLUE.** Patch
   `patches/rexglue-v0.10.0-vector-pack-fix.patch` (alias `destination==source`
   des `vpkuwus`/`vpkuhus`, 20 hunks, commit `884edd1`). Correspond à l'upstream
   `rexglue-sdk#449` (issue #364, vidéo verte VP6, fermée).

3. Autres patchs ajoutés (commits `e1711ba`, `c51c8e0`, `2928608`) :
   - `present-interval-cap` : `guest_present_interval_cap=1`, le jeu demandait un
     interval 2 dans menus/replays/cutscenes (moitié du framerate). Gain modéré seul.
   - `vulkan-texture-pipeline-fixes` : exponent bias lu au **mot 3** au lieu du mot 4
     (upstream `#456`, textures sombres/noires/vertes) ; pipelines ombre/profondeur
     en asynchrone (`#368`).
   - `waitmultiple-backoff` : polling `WaitMultiple` 1→16 ms (`#368`).
   - `vmsum3fp128-mask` : **ANNULÉ le 15/10 — le patch `0xEF`→`0x7F` était FAUX.**
     `0xEF` était déjà correct : pour `simde_mm_dp_ps`, le nibble **haut** sélectionne
     les sources et le nibble **bas** les destinations, donc `0xEF` = dot3 des lanes
     1,2,3 (= guest x,y,z, stockage inversé) diffusé sur les 4 lanes. Le `0x7F`
     sommait les lanes 0..2 (= guest w,z,y) et mettait host lane 3 à 0 — or host
     lane 3 = guest element 0, celui que le jeu relit (`stvx128` + `lfs`) → joueurs
     **aplatis/invisibles**. Vérifié empiriquement (`simde_mm_dp_ps` compilé arm64 :
     `0xEF` → 14 partout = dot3, `0x7F` → 113 = mauvaises lanes) et contre la
     référence Xenia (`InstrEmit_vmsum3fp128` = `DotProduct3` + `Splat`).
     Patch supprimé de `patches/` et de `sdk-build-patched.sh` ;
     `sdk-src/src/codegen/builders/vector.cpp` est revenu à `0xEF`.
     → checkpoint `dist/checkpoints/vmsum-v1-BROKEN/` : **ne pas utiliser**.
   - `vulkan-presenter-pipeline-fix` : le presenter recréait son pipeline à chaque
     frame (upstream `#507`) → warnings primitive restart effondrés, un peu plus
     fluide ; + `primitiveRestartEnable` pour Metal (`#487`).

4. **Variante `dist/render-tests/vulkan-fixes-v1/`** (aucun codegen, GPU plugin +
   runtime seulement) : present cap, exponent bias mot 3, depth-only async,
   waitmultiple backoff, presenter #507/#487.

Résultats utilisateur sur cette variante :
- `--no-vsync` : menu avant-match rapide, joueurs apparaissent vite, utilisable,
  un peu de latence, **foule noire**.
- `--no-async_shader_compilation` : plus fluide que `--no-vsync`, menu sans lag,
  **textures joueurs toujours incomplètes** (même dans le menu), touches un peu
  lentes.
- `--readback_resolve=full` : très lent du chargement au match, **foule rose**,
  textures joueurs inchangées. `--readback_resolve=some` **pas encore testé**.
- Warnings `Metal does not support disabling primitive restart` : fortement réduits.

Reste ouvert : textures joueurs partielles, foule (noir/bleu/rose selon le mode),
latence des touches, terrain/sol.

Prochaines actions, dans l'ordre :
1. **Revenir à un binaire sain sans rien recompiler** : lancer
   `dist/render-tests/vulkan-fixes-v1/launch.sh --execute_unclipped_draw_vs_on_cpu`
   (même contenu que `vmsum-v1` **sans** le masque cassé). Le prochain
   `zsh scripts/sdk-build-patched.sh && zsh scripts/build-macos.sh` régénère le
   codegen avec le `0xEF` d'origine (patch retiré) : c'est la base propre suivante.
2. **Tester deux choses sans rebuild** sur `vulkan-fixes-v1` :
   - `--readback_resolve=some` (jamais testé ; le mode existe mais sans les réglages
     adaptatifs `sync_addrs`/`sync_below`) ;
   - `--render_target_path_vulkan=fsi` (piste upstream `#508`, un seul paramètre).
3. **Porter le readback adaptatif `readback_some_*`** de ReStreet
   (`readback_some_sync_addrs=1282B000`, `readback_some_sync_below=0`) : solution
   validée pour le sol correct sans le stall du full. Absent de notre SDK
   (aucune cvar `readback_some_*` dans `sdk-src`).
4. Si le terrain reste noir après 2/3 : format/tiling des textures.

Outils : Xenia-edge (`/Applications/Xenia-edge.app`) est un oracle fonctionnel sur
le même ISO ; l'API GitHub via `curl` et `web_search` fonctionnent ; les CLI
`codex`/`zcode`/`muse`/`agy` sont bloqués par le sandbox (EPERM sur leurs dossiers
d'état) → les lancer depuis le terminal utilisateur.

## État courant — boot et match confirmés par l'utilisateur

### Arrêt demandé par l'utilisateur — dernier résultat

Le test `--no-async_shader_compilation` **ne corrige pas le défaut** : le menu
apparaît puis disparaît toujours, confirmé par l'utilisateur. Ne pas considérer
la désactivation de l'asynchrone comme solution. L'utilisateur demande un commit
puis l'arrêt du travail. Aucun nouveau build ou test à lancer dans cette session.

État à conserver : démarrage et match possibles, trois vérificateurs codegen
réussis, checkpoint de démarrage intact ; vidéo verte, artefacts personnages et
menu transitoire encore non résolus. FSI, correctifs Vulkan textures 3D→2D et
désactivation async n'ont pas amélioré ces symptômes. La trace identifie des
écarts de dessins mais aucune cause prouvée ; piste ID 0xBEBEBEBE à investiguer.
L'essai readback full n'a pas de résultat utilisateur confirmé à ce stade.

Reprise : lire cet état et Beads 8l9, examiner les analyses du test de trace,
puis choisir un diagnostic ciblé avant tout nouveau build. Les variantes et
captures locales sous `dist/` sont ignorées par Git, pas incluses dans le commit.

### Historique de l'analyse asynchrone (test négatif, voir ci-dessus)

### Trace utilisateur analysée : prochaine comparaison sans compilation asynchrone

Capture `dist/render-tests/menu-trace-v1/logs/20261014-212140-789085/` : 2033 images,
53,337 s, sommes des groupes vérifiées. 299522 demandes, 259452 dessins backend,
39626 copies, zéro échec du helper draw_fail. Sur 16 images, 444 demandes ne sont
ni dessins enregistrés ni copies ; pics 129 et 75 vers 25 s, pendant une création
de pipelines. Ce n'est pas la preuve d'une erreur : le backend peut ignorer un
dessin sans effet ou un pipeline asynchrone encore placeholder.

Précision utilisateur : après A sur la deuxième équipe, le menu apparaît, puis
écran noir, puis les joueurs apparaissent sans le menu. Le SDK active
`async_shader_compilation=true` par défaut ; le payload Windows utilise false.
**Prochain essai isolé, sans build :**
```sh
zsh dist/render-tests/menu-trace-v1/launch.sh --no-async_shader_compilation
```
Ce test n'a pas encore de résultat. La comparaison GPU→CPU/readback reste une
autre hypothèse, à ne pas mélanger avec cet essai. Analyse détaillée dans
`analysis.md` et mesures dans `analysis.json` du dossier de capture.

Piste secondaire : requête `l-1094795586.dds`, ID `0xBEBEBEBE`, identique au
remplissage des piles 0xBE de `xthread.cpp:308`. Compatible avec une donnée non
initialisée mais cause non prouvée ; requête déjà présente dans baseline003/005.
Ne pas créer un faux fichier pour satisfaire ce chemin.

### Historique de préparation de la trace

### Dernière action : trace par image prête, collecte validée

L'utilisateur a précisé que le menu **apparaît puis disparaît** et autorisé la
préparation d'une trace. Patch optionnel local
`patches/rexglue-v0.10.0-menu-frame-trace.patch` (un fichier GPU) ; activé par
`vulkan_menu_trace`, désactivé par défaut. Il enregistre les demandes/dessins
Vulkan, copies, shaders, descripteurs de textures, registres et scissor par image.
Ce n'est pas un dump de pixels ni de l'ordre complet des commandes.

Variante isolée créée : `dist/render-tests/menu-trace-v1/`. GPU seul compilé ;
autres binaires vérifiés contre le checkpoint, qui reste intact. Test de collecte
effectué : 258 images, 1 204 groupes, CSV valide, totaux de dessins par image
vérifiés ; arrêt SIGINT contrôlé après 12 s. Logs
`logs/20261014-211941-392372/`. Le menu n'a PAS été reproduit dans ce test court.

**Prochaine action utilisateur, sans build :**
```sh
zsh dist/render-tests/menu-trace-v1/launch.sh
```
Aller à la sélection des équipes puis laisser le menu apparaître et disparaître,
ensuite fermer le jeu. Ne pas ajouter d'autres réglages pour ce test. Lire
`gpu-frames.csv` et les logs du nouveau dossier horodaté. Procédure et limites :
`docs/menu-render-diagnostics.md`. Le sous-agent tracking a actualisé Beads 8l9.

Les index BIG4 racine ont aussi été vérifiés sans extraction : `rna.ini` et
`data/rendering_patch.cdb` sont dans `data7.big` malgré les ouvertures loose
échouées. Les autres ressources peuvent être dans des archives imbriquées ;
leur absence n'est pas démontrée par ces warnings seuls.

### Résultat de la variante textures 3D→2D

Dernier résultat de `vulkan-3d-textures-v1` : **aucun changement visuel**, confirmé
par l'utilisateur. Test `logs/20261014-210556-556070` analysé ; détails dans son
`analysis.md`. Sortie volontaire à 21:07:45, pas de fatal, quatre erreurs de chemins
identiques au baseline. Les 26 666 avertissements comptés correspondent à 13 333
occurrences dans chacun des deux flux console/runtime. Les 18 avertissements
QueueUserCallback apparaissent ensemble juste avant la fermeture.

Prochain test isolé sans build :
```sh
zsh dist/render-tests/vulkan-3d-textures-v1/launch.sh --readback_resolve=full
```
Comparer le rendu (menu, personnages, intro) ; ne pas mélanger FSI/MSAA.
Ce mode peut coûter des performances. Il teste la cohérence GPU→CPU ; aucun
résultat n'est encore disponible. Le suivi Beads/RTK est délégué à `tracking`.

### Dernier lot : variante Vulkan textures 3D→2D prête à tester

Après sélection des équipes, l'utilisateur décrit Match Setup incomplet
(joueurs et barre inférieure seuls), artefacts personnages et vidéo verte
toujours présents. Captures supplémentaires conservées dans
`dist/logs/render-baseline-2026-10-14/`. FSI n'apporte pas d'amélioration.

Deux correctifs ciblés Windows sont isolés dans
`patches/rexglue-v0.10.0-vulkan-3d-textures.patch`, appliqués sur `sdk-src/` et
compilés via la seule cible `rexgpu-xenos:Release` : dimensions 2D/3D dans le
traducteur SPIR-V, puis rechargement/barrières de la vue 3D→2D réutilisée.
Aucun codegen guest ni recompilation du jeu. Le plugin installé dans `dist/sdk/`
n'a pas été remplacé dans ce lot ; `sdk-build-patched.sh` connaît le nouveau
patch pour les reconstructions ultérieures.

`scripts/prepare-render-test.py` a créé
`dist/render-tests/vulkan-3d-textures-v1/` : seul le plugin GPU diffère du
checkpoint (autres fichiers vérifiés par SHA-256), cache shaders isolé.
**Prochain test sans build :**
```sh
zsh dist/render-tests/vulkan-3d-textures-v1/launch.sh
```
Comparer la vidéo, les textures personnages et le contenu de Match Setup ;
aucun résultat visuel encore disponible. Les binaires du checkpoint restent intacts.

Le lancement journalisé capture désormais aussi `runtime.log`, affiché en direct
avec `[runtime]`, en plus de la console MoltenVK. Le warning primitive restart
reste séparé/compté. Tests synthétiques de suivi des deux flux, rotation, erreurs
visibles et propagation du code de sortie réussis. Ancien runtime log 20:59 :
quelques erreurs ResolvePath (cache, dvdini, nom nu de DLL), sans fatal ; leur
présence seule n'établit pas la cause des défauts graphiques.

### Historique du test FSI et du filtrage des logs

Dernier retour : le test `--render_target_path_vulkan=fsi` ne corrige pas les
artefacts verts. Ne pas présenter FSI comme solution validée.

Pour rendre les prochaines observations lisibles sans perdre de diagnostics :
`zsh scripts/play-logged.sh` lance le checkpoint sauvegardé via
`scripts/run-logged.py`. Un dossier horodaté sous `dist/logs/play/` conserve
`console.raw.log` (stdout/stderr complets), `console.filtered.log` (première
occurrence du warning primitive restart puis compteur toutes les cinq secondes),
`primitive-restart.log` (toutes ses occurrences) et `summary.txt` (total).
Les autres lignes sont affichées telles quelles. Le code de sortie est conservé.
Test synthétique réussi : 3 warnings conservés, un seul affiché, autre erreur
stderr visible et code de sortie 7 propagé. Aucune recompilation nécessaire.

Le build 20:47 démarre et atteint la configuration de match puis un match.
Captures conservées : `dist/logs/render-baseline-2026-10-14/` (intro corrompue,
configuration de match, match en cours) avec observations. Menu décrit comme
fluide ; jeu « un peu fluide », sans mesure FPS. J3 `bve` est clos sur ces preuves.
Nouveau jalon graphique `8l9` en cours ; J4 clavier/configuration reste distinct.

Défauts observés : intro verte et blocs/stries, motifs anormaux sur les joueurs,
warning répété « Metal does not support disabling primitive restart ». La source
MoltenVK `MVKPipeline.mm` émet ce warning sans forcer l'échec de la pipeline ;
aucun lien causal démontré entre ce warning et les défauts visuels.

Le checkpoint conserve ses binaires ; seul son statut de validation a été mis à
jour (`user_reported_gameplay`, rendu encore incorrect). Prochain test sans build,
changer une seule option sur le même binaire :
```sh
zsh dist/checkpoints/2026-10-14-codegen-validated/launch.sh --render_target_path_vulkan=fsi
```
Comparer intro et joueurs. Ne pas mélanger plusieurs options ou patches dans ce
test. Ensuite examiner les correctifs graphiques de la référence selon résultat.

### État compilé et sauvegardé à 20:47

Le pipeline a maintenant réussi depuis le terminal utilisateur : codegen 516,7 s,
trois vérificateurs PASS, configuration sur `dist/sdk/` et build 295/295 exit 0.
La compilation du lot codegen est validée ; le boot de cette DLL reste à tester.

Checkpoint local créé et vérifié :
`dist/checkpoints/2026-10-14-codegen-validated/`. Il contient le runtime complet
(modules sous les deux noms, renderer, runtime, Vulkan/MoltenVK), le SDK, les
sorties générées et les sources/patches/scripts. `checkpoint.json` enregistre
le commit, l'état Git, les résultats de contrôle et les SHA-256 du runtime.
Les données du jeu restent dans `dist/GameData/`, sans duplication.

**Prochain test sans build :**
```sh
zsh dist/checkpoints/2026-10-14-codegen-validated/launch.sh
```
Ce test utilise les bibliothèques sauvegardées ; il reste ouvert jusqu'à fermeture
du jeu et écrit ses logs dans le dossier `runtime/logs/` du checkpoint.
Les futurs snapshots se créent avec `python3 scripts/freeze-build.py <nom-unique>`.
Ils utilisent des clones APFS si disponibles, n'écrasent aucun snapshot existant
et ne suppriment ni `generated/` ni les caches de compilation.

### Préparation et validation du SDK à 20:34

Le lot de contrôle de flux de la référence Windows est maintenant isolé dans
`patches/rexglue-v0.10.0-shared-control-flow.patch` et appliqué sur `sdk-src/`.
Cinq fichiers, 49 insertions / 10 suppressions ; aucun changement graphique ni
inlining GPR/LR. Le SDK téléchargé `ReXGlue/` n'a pas été modifié.

Le générateur corrigé a été compilé en Release et stagé dans `dist/sdk/bin/`
(UUID `30FA9E40-BA7A-3D92-88CD-44CF48432827`, identique à la sortie source).
L'installation complète a fini par échouer sur le registre utilisateur CMake,
après copie des fichiers ; ce registre n'est pas utilisé par notre projet.

Les trois vérificateurs Windows sont restaurés sous `scripts/`. Le pipeline
`scripts/build-macos.sh` utilise exclusivement `dist/sdk/`, invalide le cache
codegen si le binaire du générateur change, et refuse de compiler le jeu tant
que ces vérifications échouent. `sdk-build-patched.sh` applique les trois patches
avec détection explicite d'incompatibilité et construit uniquement Release.

Validation : compilation du générateur OK, syntaxe shell et patches OK ; sur les
anciennes sorties, contrôles branches directes et CTR en échec attendu, contrôle
allocation OK. La génération corrigée reste bloquée par le sandbox :
`Unable to reserve the 4gb guest address space`.

**Prochaine action depuis le terminal macOS utilisateur :**
```sh
zsh scripts/build-macos.sh && zsh scripts/boot-test.sh 45
```
Si la vérification échoue, analyser ses erreurs AVANT de compiler ou relancer le
jeu. Le dernier boot (20:26) utilisait encore la DLL 20:12 et échouait sur
0x833B5A04 → 0x833B59C0. J3 reste en cours. Les overrides ponctuels déjà ajoutés
sont conservés. Les correctifs de rendu de `main` sont un lot ultérieur.

Détails et provenance : `patches/README.md`. Logs :
`dist/logs/sdk-control-flow-build.log`, `dist/logs/sdk-control-flow-install.log`,
`dist/logs/control-flow-pipeline.log`.

## Historique du débogage (les actions ci-dessous sont remplacées par l'état courant)

### Audit de la référence Windows — priorité avant le prochain build

Le dépôt `windows-version/` contient les sources et recettes, pas le C++ guest
pré-généré ni les exécutables Windows (`docs/BUILDING.md` le précise).
Sa base SDK est exactement c94f5eb, comme notre SDK séparé, mais son patch
`windows-version/patches/rexglue-local-changes.patch` corrige aussi le codegen :
- `phase_discover.cpp` : création d'entrées pour les branches vers des tails partagés ;
- `function_graph.cpp` : priorité aux labels locaux déjà découverts ;
- `builders/context.cpp`, `control_flow.cpp` : classification depuis la fonction
  propriétaire, et traitement des cases de switch ;
- `builders/helpers.h` : exécution effective des branches CTR externes.
Ces changements ne sont PAS dans `sdk-src/` actuellement. Les maps TOML Windows
seules ne reproduisent donc pas sa traduction. Le vérificateur Windows
`Installer/recomp-template/config/verify_direct_branches.py` exige zéro saut
irrésolu. Avant de poursuivre des corrections TOML individuelles : isoler les
correctifs de contrôle de flux (exclure l'optimisation gprlr et les changements
renderer), les porter comme patch minimal documenté sur `sdk-src/` uniquement,
puis régénérer et vérifier tous les sauts. Aucun patch SDK ajouté par cet audit.

### Dernier test utilisateur : 20:15 — splash affiché

- La correction 0x8264C330 a été régénérée et compilée par l'utilisateur ;
  le démarrage affiche désormais le splash (retour utilisateur), avec des
  événements GPU PRESENT dans le log. J3 n'est pas encore validé.
- Nouveau FATAL : `Unresolved call from 0x833B5A04 to 0x833B59C0`.
  Même découpage incorrect : `sub_833B59B8` contient un switch dont les cases
  partagent les retours true/false à 0x833B59C0 et 0x833B5A3C.
- Correction TOML ajoutée : routine `[0x833B59B8, 0x833B5A44)`, suppression
  de ses sept frontières internes. L'entrée padding 0x833B5A44 reste séparée.
  Syntaxe TOML, absence de frontières internes et diff vérifiés ; nouvelle
  génération/compilation et test utilisateur nécessaires.
- Inventaire statique du C++ généré actuel : `dist/logs/unresolved-generated.tsv`
  (510 calls, 163 branches, uniquement fifadllzf). Ce sont des sites d'arrêt
  potentiels, pas 673 pannes démontrées au démarrage. Ne pas corriger en masse
  sans examiner le contrôle de flux.
- Prochaine action : `cmake --build build --parallel 8`, puis
  `zsh scripts/boot-test.sh 45` depuis le terminal macOS de l'utilisateur.

**Cette mise à jour remplace l'état de reprise et la première action ci-dessous.**

- Beads confirme que le relink a réussi à 19:57 ; `cmp build/librexruntime.dylib
  dist/sdk/lib/librexruntime.dylib` confirme les runtimes identiques. Le test avec
  `--writable_code_segments` atteint Metal/Vulkan sans la tempête 0x823F2E90.
- Blocage observé : `Unresolved call from 0x8264C444 to 0x8264C4E4`.
  Le C++ généré montre que `sub_8264C330` est une boucle avec switch : les
  17 overrides 0x8264C424–0x8264C4DC isolent ses cases en fonctions. Leurs
  branches vers le store commun 0x8264C4E4 sont irrésolues ; la branche de
  boucle 0x8264C4FC → 0x8264C358 est également irrésolue.
- Correction projet dans `config/fifadllzf_overrides.toml` : retirer ces 17
  frontières internes et imposer la routine entière `[0x8264C330, 0x8264C528)`.
  TOML et absence de frontières internes vérifiés. **Codegen/build/boot après
  cette correction restent à valider.** Aucun changement au SDK.
- La session restreinte ne peut pas effectuer cette validation : codegen échoue
  `Unable to reserve the 4gb guest address space` ; le binaire existant échoue
  `SDL_InitSubSystem(SDL_INIT_VIDEO) failed: The video driver did not add any displays`.
  Logs : `dist/logs/startup-relink.log`, `dist/logs/startup-probe.log`.
  Le log du boot 19:57 est préservé dans `dist/logs/startup-before/`.

Prochaine action depuis un terminal macOS avec accès à la session graphique :
`cmake --build build --parallel 8`, puis `zsh scripts/boot-test.sh 45`.
Vérifier que les deux erreurs 0x8264C4E4 et 0x8264C358 ont disparu, puis
identifier le prochain blocage. J3 reste en cours.

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
