# Dialogues et onomatopées de Frouch City

## Dialogues (`narrative/dialogues/mNN_*.yarn`)

Sous-ensemble de Yarn (`YarnLite`, `game/scripts/narrative/yarn_lite.gd`). Un fichier par mission, des nœuds :

```
title: m06_pay
---
Josette: Alors, ça fait dix-sept euros quarante-trois. Vous avez la monnaie ? #line:m06_pay_01
Vous: Attendez, je dois avoir ça au fond du sac… #line:m06_pay_02 #onoma:CLING !
===
```

- **Réplique** : `Locuteur: texte #line:identifiant`. L'identifiant est **obligatoire, unique et stable** (sous-titrage, localisation). Étiquettes facultatives : `#onoma:TEXTE` (onomatopée en bulle au-dessus du locuteur), `#wait:secondes` (durée imposée).
- **Commandes** : `<<jump nœud>>` enchaîne. Pas de choix ni de variables : les dialogues sont dits **par-dessus l'action**, jamais bloquants (jeu en ligne à 16, solo = même code).
- **Quand un nœud se joue** (serveur, `MissionBase`) : `mNN_intro` au démarrage ; `mNN_<étape>` à chaque changement d'étape ; `mNN_done_win`, `mNN_failed_evicted`… selon l'issue ; et des « aboiements » `mNN_<événement>` appelés par la mission (`bark("m06_incident", 8.0)` : au plus une fois par 8 s). Un nœud inexistant est ignoré. Le serveur envoie le nom du nœud aux clients, chacun lit son exemplaire des fichiers.
- **Affichage** : bulle de paroles au-dessus du locuteur (`SpeechBubbles`), réplique en sous-titre en bas de l'écran (toujours), petit marmonnement (`babble`). Locuteurs reconnus : compagnons, PNJ nommés (Mme Hubert, Josette, Dylan, Gendarme, Marguerite), « Vous » = le joueur local ; sinon le joueur local.
- **Passer une scène** : touche X (manette : Retour), vote à la majorité des joueurs humains (`skip: majority_vote` des missions).
- **Règles d'écriture** : humour « Normandie profonde », tendre, jamais méprisant ; 150 caractères au plus par réplique ; aucun nom de personne, d'enseigne ou de marque réels.
- `make city` copie les fichiers dans `game/assets/dialogues/` (un test vérifie qu'ils sont identiques). Un test vérifie le format, les identifiants, les locuteurs et que chaque `say("…")` / `bark("…")` d'une mission désigne un nœud existant.

## Onomatopées en bulles

Chaque son important a son onomatopée (`Sfx.ONOMA`) : POUET POUET ! (klaxon), BOUM ! (choc), CRAAAC ! (verre), MEUUUH !, OUAF OUAF !, DING !, CLING !, BIP !, TSSSSS, FIIIIIT !, PFFFF… (soupir)… Ton `loud` (rouge), `soft` (bleu), `good` (vert), `bad` (violet). Une même onomatopée au plus toutes les 0,35 s. Option « Onomatopées en bulles » dans le menu pause (accessibilité : équivalent visuel des bruitages, avec les sous-titres sonores), ainsi que « Bulles de dialogue ».
