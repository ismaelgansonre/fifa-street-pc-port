# Trace de la disparition du menu

Le menu de configuration de match apparaît puis disparaît. Les essais FSI et
Vulkan textures 3D→2D n'ont pas changé ce comportement selon l'utilisateur.

## Capturer sans recompiler le jeu

```sh
zsh dist/render-tests/menu-trace-v1/launch.sh
```

Aller à la sélection des équipes puis à la configuration de match. Laisser le
menu apparaître et disparaître, puis fermer le jeu. Pour cette capture, ne pas
changer simultanément les options FSI, readback ou MSAA.

Chaque lancement crée un dossier horodaté sous
`dist/render-tests/menu-trace-v1/logs/`, avec :

- `gpu-frames.csv` : résumés des commandes du backend Vulkan par image ;
- `runtime.log` : journal du jeu, affiché aussi avec le préfixe `[runtime]` ;
- `console.raw.log` et `console.filtered.log` : console brute et vue lisible ;
- `primitive-restart.log` et `summary.txt` : warning répétitif séparé et compté.

## Ce que mesure le CSV

Une ligne `frame` compte les appels IssueDraw, les commandes de dessin
enregistrées dans le tampon Vulkan différé, les IssueCopy et les échecs qui
passent par le helper `draw_fail`. Un IssueDraw peut lui-même demander une
copie, ou être ignoré légitimement : les compteurs ne prouvent pas une panne.

Les lignes `draw` regroupent les dessins d'une image par shaders vertex/pixel,
descripteurs de textures utilisés, registres color/depth/surface, zone scissor
et primitive. `textures` contient `slot:adresse/format/dimension` pour chaque
texture utilisée ; `fetch_hash` est une empreinte de ses descripteurs.

Les totaux `draws` des groupes doivent égaler `submitted` pour chaque image.
Le temps `elapsed_ms` part de la première commande tracée. Le CSV est vidé sur
disque à chaque présentation ; il ne dépend pas des destructeurs, contournés
par la sortie `_Exit` du jeu. La capture s'arrête après 12 000 résumés d'images.

## Interpréter avant de corriger

Comparer les groupes autour de l'instant où le menu disparaît. Une disparition
des groupes associés au menu oriente vers la logique guest ou un dessin ignoré.
Des groupes persistants avec des descripteurs, shaders ou zones modifiés donnent
une cible pour examiner les textures et les paramètres GPU.

La trace ne conserve ni pixels, ni ordre complet des dessins, ni géométrie, ni
constantes shader, ni toutes les opérations de synchronisation. Elle ne prouve
donc pas à elle seule la cause et peut nécessiter une capture GPU plus ciblée.
La collecte ajoute du travail CPU ; ne pas mesurer les performances avec elle.

## Reproduction technique

`patches/rexglue-v0.10.0-menu-frame-trace.patch` est un ajout local à un fichier
GPU (`command_processor.cpp`). Il est désactivé par défaut et activé seulement
par `--vulkan_menu_trace=<chemin-csv>`. Il ne modifie aucun paramètre de rendu.
La variante contient aussi le lot textures 3D→2D précédent. Ses autres binaires
ont été vérifiés contre le checkpoint de démarrage ; aucune génération PPC ni
compilation du jeu n'a été nécessaire.

Le court test de démarrage a produit 258 résumés et 1 204 groupes (172 380 octets),
CSV valide et totaux vérifiés. Il s'est terminé par SIGINT contrôlé après
12 secondes. Logs : `dist/render-tests/menu-trace-v1/logs/20261014-211941-392372/`.
Ce test valide la collecte, pas la transition de menu encore à reproduire.
