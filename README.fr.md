# ESO Addons for Mac — Alternative à Minion pour macOS

[English](README.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Español](README.es.md)

[![Build and tests](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml/badge.svg)](https://github.com/TheMoldex/minion-alternative-eso-macos/actions/workflows/build.yml)

Gestionnaire natif d’extensions **The Elder Scrolls Online pour macOS et Apple Silicon**, écrit avec SwiftUI. Une alternative indépendante à Minion : catalogue ESOUI, mises à jour automatiques, installation des bibliothèques requises, captures d’écran et sauvegardes des réglages. Interface en anglais, russe, français et espagnol.

**[Télécharger pour Mac](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest/download/ESO-Addons-for-Mac.zip)** · [Versions et sommes de contrôle](https://github.com/TheMoldex/minion-alternative-eso-macos/releases) · [Signaler un problème](https://github.com/TheMoldex/minion-alternative-eso-macos/issues)

## Installation

Configuration requise : **macOS 14 ou version ultérieure et Mac avec puce Apple Silicon**. Cette version ne prend pas en charge les Mac Intel.

1. Ouvre la [dernière version](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest) et télécharge **`ESO-Addons-for-Mac.zip`**. Les archives « Source code » de GitHub contiennent le code source, pas l’application prête à l’emploi.
2. Décompresse le ZIP, puis déplace **`ESO Addons for Mac.app`** dans **Applications** et ouvre-la.
3. Autorise l’accès au dossier **Documents** lorsque macOS le demande : les extensions ESO s’y trouvent normalement.
4. Vérifie le dossier détecté. Sinon, ouvre la roue dentée → **Général → Choisir un dossier…** et sélectionne `live` ou `AddOns`. Le chemin habituel est `~/Documents/Elder Scrolls Online/live/AddOns`. Pour le serveur de test, sélectionne `pts`.
5. Vérifie que tes extensions apparaissent dans **Installées**. Après une installation ou une mise à jour, exécute **`/reloadui`** dans ESO.

L’application est signée localement, sans certificat Apple Developer ID ni notarisation. Si macOS bloque le premier lancement et propose **Ouvrir quand même**, cette option se trouve dans Réglages Système → Confidentialité et sécurité. Consulte les [instructions d’Apple](https://support.apple.com/fr-fr/102445). Aucun compte développeur Apple ni certificat personnel n’est nécessaire pour utiliser l’application.

## Tu utilisais Minion sur macOS ?

Sélectionne le même dossier AddOns. Les extensions déjà installées sont détectées et les enregistrements Minion correspondants peuvent identifier leur source ESOUI. Il n’est pas nécessaire de tout réinstaller ni de déplacer SavedVariables. La configuration Minion est lue sans être modifiée. Ferme Minion avant d’installer ou de mettre à jour des extensions ici. Cette application est indépendante ; ce n’est ni une version officielle de Minion ni un fork.

## Installer, mettre à jour et supprimer

- **Installées** affiche les extensions existantes et les badges **Extension / Bibliothèque**. L’état distingue une mise à jour disponible, une version à jour, une version locale plus récente et une version impossible à vérifier. Un état inconnu ne confirme pas que l’extension est à jour.
- **Rechercher des extensions** permet de chercher par nom, auteur ou dossier dans le catalogue ESOUI. Sélectionne une extension, clique sur **Installer**, vérifie la liste des extensions et bibliothèques proposées, puis confirme.
- Les bibliothèques obligatoires et leurs versions minimales sont résolues automatiquement. Les dépendances facultatives ne sont pas installées automatiquement. Si une bibliothèque requise ne peut pas être identifiée, l’opération s’arrête et l’indique.
- **Mises à jour → Tout mettre à jour** présente les mises à jour reconnues avant de modifier les fichiers. Une version locale plus récente n’est pas automatiquement remplacée par une version plus ancienne.
- La fiche affiche la description, les nouveautés et les captures fournies par ESOUI. Clique sur une miniature pour l’agrandir ; les flèches du clavier permettent de parcourir les images. Les textes des auteurs ne sont pas traduits.
- Un clic droit sur une ligne ouvre les actions : installer, mettre à jour, réinstaller, ignorer les mises à jour, réinitialiser les réglages, ouvrir ESOUI ou le dossier, et supprimer.
- La suppression affiche les dossiers concernés. Ils vont dans la **Corbeille macOS**, sans créer de sauvegarde automatique de suppression. **Remettre** dans la Corbeille permet de les récupérer. SavedVariables reste en place. Les bibliothèques sont conservées par défaut ; le nettoyage facultatif ne supprime que les dépendances inutilisées. Les bibliothèques encore utilisées par d’autres extensions sont protégées.
- Après toute modification d’extension, exécute **`/reloadui`** dans le jeu.

Utilise les filtres de catégorie, type et version ESO, puis le tri par nom, téléchargements ou dernière mise à jour. Le bouton de réinitialisation efface aussi la recherche. Les filtres limitent la liste affichée ; **Tout mettre à jour** examine toujours les mises à jour reconnues, sauf celles qui sont ignorées.

Le catalogue est mis en cache pendant une heure ; les actualisations manuelles sont limitées à une par minute. Si la source d’une extension reste ambiguë, sélectionne-la et choisis sa source ESOUI. Les mises à jour groupées ne touchent pas aux dossiers sans source identifiée.

## Réglages et mises à jour automatiques

Ouvre la roue dentée en bas de la barre latérale ou utilise **⌘,**. **Général** contient les dossiers ESO, la langue et les options de sauvegarde. Les réglages des mises à jour contiennent la planification, les exclusions, les téléchargements simultanés et la vérification de la version de l’application. Choisis **Français** pour changer la langue ; ce choix est conservé.

Les deux séparateurs verticaux permettent de redimensionner la barre latérale et la fiche. Leur largeur est conservée après redémarrage. Les dossiers `live` et `pts` peuvent être enregistrés séparément. Retirer un dossier de la liste ne supprime aucun fichier. Chaque dossier possède ses propres sources, exclusions, sauvegardes de mise à jour et historique.

Les mises à jour automatiques sont activées par défaut et vérifiées toutes les heures tant que l’application fonctionne. Elles concernent uniquement les extensions reconnues du dossier sélectionné. Elles attendent lorsque ESO ou Minion est lancé, lorsqu’une opération ou une confirmation est ouverte, pendant l’affichage des réglages, ou si la récupération est bloquée. Une pause est réessayée après cinq minutes ; une autre erreur après quinze minutes.

L’action **Ignorer les mises à jour** exclut une extension de **Tout mettre à jour** et des mises à jour automatiques. Son bouton individuel reste disponible. Les exclusions se gèrent dans les réglages des mises à jour. Si une extension exige une bibliothèque ignorée plus récente, l’opération s’arrête au lieu de la mettre à jour silencieusement.

Tu peux choisir de 1 à 4 téléchargements simultanés ; la valeur par défaut est 3. Les fichiers sont téléchargés et vérifiés avant installation. Si un téléchargement ou la vérification d’une archive échoue, ce paquet est ignoré. Les autres extensions sont mises à jour si leurs bibliothèques requises sont disponibles. Le résultat indique les paquets ignorés et la raison.

Fermer la fenêtre laisse l’application dans la barre des menus lorsque les mises à jour automatiques sont activées. Utilise le menu de l’application pour la quitter complètement. Il n’y a ni service système ni lancement automatique après redémarrage du Mac. La mise en veille suspend les vérifications. Ne lance pas de mises à jour manuelles dans Minion et cette application en même temps.

## Sauvegardes, transfert et restauration

Les deux types de sauvegardes ont des usages différents :

- **Sauvegardes de mise à jour** : copies des dossiers remplacés lors d’une installation, mise à jour ou restauration. Elles ne contiennent pas les réglages du jeu ni SavedVariables. La conservation se règle sur toutes les copies ou les 5, 10 ou 20 dernières ; toutes sont conservées par défaut. Les copies nécessaires à une récupération inachevée ne sont pas supprimées.
- **Réglages et transfert** : copies manuelles de SavedVariables, `UserSettings.txt`, `AddOnSettings.txt`, de l’inventaire des extensions et des associations ESOUI. L’option d’inclure les fichiers des extensions permet un transfert sans téléchargement. Sans ces fichiers, l’inventaire seul ne réinstalle pas les extensions. Ces copies restent jusqu’à leur suppression explicite.

Pour une copie manuelle ou un transfert :

1. Ferme **ESO et Minion**.
2. Dans les réglages généraux, choisis un dossier de sauvegarde situé hors de `live` ou `pts`.
3. Ouvre **Sauvegardes → Réglages et transfert**. Tu peux donner un nom facultatif à la copie et inclure les fichiers des extensions.
4. Clique sur **Créer une sauvegarde manuelle**.
5. Pour transférer vers un autre Mac, copie le dossier complet `ESO-Backup-…`, sélectionne le dossier ESO de destination, ouvre cette copie depuis l’application et vérifie la liste avant de restaurer.

Seuls les fichiers et dossiers listés sont remplacés. Les autres éléments restent en place. Le transfert ne réécrit pas les identifiants de compte ou de personnage dans les réglages des extensions. Les fichiers sont vérifiés avec SHA-256. Depuis 0.5.5, les copies automatiques pour restauration contiennent également ces empreintes. Les anciennes copies automatiques sans empreintes restent consultables et supprimables, mais leur bouton de restauration est désactivé. Les copies manuelles portables restent compatibles.

Sélectionne plusieurs copies avec **⌘** ou **⇧**, puis utilise Supprimer ou le menu contextuel pour les placer dans la Corbeille. Les copies manuelles peuvent aussi être renommées. Les réglages de conservation des mises à jour ne suppriment pas les copies manuelles.

**Réinitialiser les réglages…** est une action séparée. Elle présente les fichiers SavedVariables de l’extension sélectionnée et les place dans la Corbeille après confirmation. Les réglages partagés sont protégés. Ferme ESO avant cette opération pour éviter qu’il réécrive ses anciens réglages à la fermeture.

## Sécurité des fichiers et diagnostic

Les installations, mises à jour et suppressions ordinaires conservent les réglages du jeu et SavedVariables. Seules une réinitialisation explicite des réglages ou une restauration manuelle les modifient. Les tables de prix TTC existantes sont conservées lors d’une mise à jour de Tamriel Trade Centre ; la synchronisation TTC nécessite le [client TTC séparé](https://github.com/TheMoldex/ttc-client-macos).

Les archives sont téléchargées en HTTPS depuis les hôtes ESOUI/MMOUI autorisés et contrôlées avec leur somme MD5 et les CRC du ZIP. Cela détecte des corruptions, sans constituer une signature de l’auteur. Les chemins dangereux, liens et tailles de décompression excessives sont refusés.

Les dossiers en lecture seule appartenant à ton compte peuvent recevoir le droit d’écriture du propriétaire avant leur remplacement. Les fichiers verrouillés dans le Finder sont refusés avant le début de la modification. Une restauration de bibliothèque ne peut pas casser une dépendance auparavant satisfaite d’une extension conservée. Une récupération inachevée attend la fermeture d’ESO et de Minion.

Si un fichier est illisible ou une récupération échoue, la liste des extensions reste consultable et les modifications sont bloquées. Le message indique le chemin concerné. Corrige les droits ou les données signalées, puis relance la vérification. Consulte l’historique des opérations et son filtre d’erreurs : les 500 dernières entrées sont conservées pour le dossier sélectionné. Avant de partager des journaux, retire les noms de compte, chemins privés et contenus de SavedVariables.

Les données de l’application se trouvent dans `~/Library/Application Support/ESOAddonsMac/` et les préférences dans `local.denstash.ESOAddonsMac`. Un fichier caché `.eso-addons.lock` évite deux opérations concurrentes de cette application sur le même dossier. La configuration Minion n’est jamais modifiée.

## Mettre à jour l’application

La version est vérifiée sur GitHub à chaque lancement, puis toutes les heures. Une nouvelle version stable avec le ZIP de l’application déclenche une proposition ; les brouillons et préversions sont ignorés. Après avoir choisi de reporter, une bannière reste disponible. La vérification manuelle se trouve dans les réglages des mises à jour et dans les menus.

Pour installer une nouvelle version, télécharge le ZIP du [dernière version publiée](https://github.com/TheMoldex/minion-alternative-eso-macos/releases/latest), quitte l’application, puis remplace-la dans Applications. L’installation de la mise à jour est manuelle. Aucun identifiant ESO ni fichier du jeu n’est envoyé à GitHub.

Les anciennes versions locales jusqu’à 0.5.5 utilisent l’ancien dépôt : installe **0.5.6** manuellement une fois pour passer aux versions publiques de `TheMoldex/minion-alternative-eso-macos`.

## Compiler et vérifier

Les Xcode Command Line Tools sont nécessaires. Aucune dépendance Swift externe ni Java n’est requise.

```sh
./build.sh /tmp/ESOAddons.app
```

La compilation lance les vérifications locales. Pour tester aussi de vrais téléchargements ESOUI, installations, sauvegardes, restaurations et récupérations dans des dossiers temporaires :

```sh
ESO_LIVE_TESTS=1 ./build.sh /tmp/ESOAddons.app
```

La signature est locale par défaut. Un certificat de signature de code existant peut être indiqué avec `ESO_SIGNING_IDENTITY` ; le script n’en crée ni n’en importe. Changer de compilation peut provoquer une nouvelle demande d’accès à Documents. Un redémarrage de la même compilation ne remplace pas sa signature. Les vérifications GitHub Actions sont visibles dans le badge en haut de cette page. Tous les ZIP du catalogue ESOUI et une installation sur un autre Mac n’ont pas été testés.

Application indépendante et non officielle, sans affiliation avec ESOUI, MMOUI, Minion, ZeniMax ou Bethesda. Les extensions appartiennent à leurs auteurs et sont téléchargées depuis ESOUI à la demande. Pour de l’aide, ouvre un [ticket GitHub](https://github.com/TheMoldex/minion-alternative-eso-macos/issues) avec la version de l’application, la version de macOS et les étapes pour reproduire le problème.
