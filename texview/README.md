# texview — visionneuse des vraies textures du jeu

Affiche les textures telles que le runtime les charge, à partir de dumps
d'octets guest. Pas de jeu requis pour lire, mais le jeu requis pour capturer.

## 1. Capturer (terminal utilisateur, jeu + fenêtre requis)

```sh
cd "/Users/ismael/Documents/GIT/fifa-street-pc-port"
zsh scripts/sdk-build-patched.sh   # inclut le patch texture-dump (deja fait)
zsh scripts/build-macos.sh         # relink le jeu (en cours ou a refaire)
zsh scripts/capture-textures.sh    # cree la variante + lance avec dump
```

Aller au Match Setup (ou plus loin), quitter. Chaque texture 2D unique est
écrite une fois dans `dist/texdump` (plafond 1024 fichiers, 64 Mo/texture).

Sans `--vulkan_dump_textures`, le jeu est strictement inchangé (cvar vide =
aucune lecture, aucune écriture).

## 2. Regarder

```sh
./dist/tools/texview dist/texdump
```

Touches : `←`/`→` texture, `↑`/`↓` mip, `+`/`-` zoom, `R` vue brute, `Q` quitter.
Le titre de la fenêtre donne nom, dimensions, format et mip courants.

Variante sans fenêtre (vérification) :
```sh
./dist/tools/texview dist/texdump --export-bmp /tmp/texexport
```

## 3. Reconstruire la visionneuse seule

```sh
zsh texview/build.sh
```

Le script rejoue aussi le test du décodeur sur `.retex` synthétiques
(`/tmp/texharness/retex-test/`), avec positions calculées à la main.

## Limites connues

- Formats décodés : 8888 (6), DXT1 (18), DXT3 (19), DXT5 (20). Le reste est
  ignoré avec un message, pas un crash.
- 8888 : l'ordre des canaux suit la lecture naturelle du mot guest 0xAARRGGBB.
  Si les textures 8888 réelles apparaissent R/B inversées, c'est ce mapping
  qu'il faut ajuster dans `decode.cpp` (marqueur `8888`).
- Mip tail packé : positions via `GetPackedMipOffset` (modèle tuile 32x32,
  expérimental). La vue `R` (octets bruts, exacte pour le mip 0) aide à
  arbitrer les cas douteux.
- Premier upload gagne : une texture réécrite ensuite (streaming, render
  target animée) garde sa première version. Les render targets
  (`scaled_resolve`) sont exclues.
