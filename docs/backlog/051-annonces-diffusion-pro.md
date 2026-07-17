# FEAT-051 — Baillan Pro : annonces réutilisables & diffusion multi-portails

> Statut : **📋 Discovery cadrée** (2026-07-16) · Priorité : P1 Growth / monétisation · Aucun développement lancé.

## Problème et promesse

Lorsqu'un bien devient vacant, le bailleur ressaisit ses informations, photos et conditions sur plusieurs sites. Cela prend du temps, crée des erreurs et oblige à repartir de zéro lors de la relocation suivante.

**Promesse :** « Créez l'annonce une fois, réutilisez-la à chaque relocation et diffusez-la là où votre compte ou les partenaires Baillan le permettent. »

## Cible et accès

- Cible primaire : bailleurs particuliers autonomes possédant 1 à 5 logements.
- Fonctionnalité **exclusivement Plan Pro** : un compte gratuit peut découvrir la valeur et l'offre, mais ne peut ni créer, ni sauvegarder, ni publier une annonce de location.
- Les fonctions de gestion existantes et les documents déjà déposés restent accessibles quel que soit le palier.

## Décisions produit retenues

- Une annonce appartient à un seul bien ; une seule annonce peut être active par bien.
- L'annonce est un instantané éditorial : modifier le bien ne modifie jamais silencieusement une annonce diffusée.
- Adresse privée par défaut : ville ou quartier ; une adresse plus précise requiert un choix explicite du bailleur.
- Le matching signifie contrôle de complétude et de cohérence, jamais score ou sélection de candidats.
- Un bail actif bloque une diffusion standard ; la relocation anticipée est hors V1.
- Les frais d'un portail ou d'un multidiffuseur sont un **add-on par campagne/canal**, affiché et validé avant activation. Ils ne sont pas inclus dans l'abonnement Pro.

## Offre et hypothèses tarifaires

| Offre | Hypothèse | Accès annonces |
|---|---|---|
| Gratuit | Limites existantes : 2 biens, 3 locataires, 2 baux actifs | Aucun accès aux annonces, modèles, photos dédiées ou diffusion |
| Pro | 7,99 € TTC/mois ou 79 € TTC/an | Annonces, images, modèles de relocation, page Baillan, partage et canaux sans coût partenaire |
| Fondateur | 59 € TTC la première année, places limitées ; renouvellement à 79 €/an | Même contenu Pro |

Ces prix sont des **hypothèses de lancement** à tester avant commercialisation. Aucun paiement ne doit être proposé avant les prérequis légaux et de facturation du Plan Pro.

## Périmètre produit V1

1. Depuis un bien vacant, création d'une annonce préremplie ; écran de matching : informations reprises, à vérifier et manquantes.
2. Brouillon enregistré à tout moment ; les informations manquantes bloquent la diffusion, jamais le brouillon.
3. Édition : titre, description, photos, loyer HC, charges, loyer CC, disponibilité, dépôt, caractéristiques, DPE/GES lorsque requis et niveau d'adresse publique.
   Les mentions réglementaires applicables à l'annonce (notamment énergie et Géorisques) doivent être vérifiées avant toute diffusion publique.
4. Les photos sont conservées dans l'espace de fichiers Baillan ; Firestore ne contient que les métadonnées. L'expérience compresse les images et permet leur suppression.
5. Un modèle est une annonce réutilisable. « Réutiliser pour relouer » crée une nouvelle version, avec vérification explicite du prix, de la disponibilité et des photos ; l'original et son historique restent conservés.
6. Page publique Baillan, lien de partage, texte et visuel prêts à publier.
7. Hub de diffusion par canal : `à connecter`, `prêt`, `publié`, `en attente`, `refusé`, `à mettre à jour`, `retiré`.
8. Catalogue honnête : Leboncoin, SeLoger, PAP, Bien'ici, Logic-Immo, Figaro Immobilier, Facebook Marketplace, Instagram, Facebook Page et X. Chaque canal indique s'il est direct, partenaire/multidiffuseur ou manuel assisté.

## Hors périmètre V1

- Scraping, automatisation navigateur ou partage d'identifiants portail.
- Promesse de publication sur Facebook Marketplace.
- Connecteur Leboncoin, SeLoger ou Bien'ici sans contrat ou partenariat effectif.
- Candidatures, dossiers locataires, messagerie ou sélection de candidats.
- Mise à jour automatique d'une annonce active après modification du bien.
- Stockage illimité ou frais portail inclus dans le Pro.

## Critères d'acceptation produit

- Un compte gratuit ne peut pas créer ni conserver une annonce de location ; il comprend clairement la valeur du Plan Pro.
- Un Pro crée un brouillon prérempli depuis un bien vacant et identifie clairement les données à compléter.
- Une annonce publiée n'est jamais écrasée par une modification de la fiche bien.
- Réutiliser un modèle crée une nouvelle annonce et impose la vérification du prix, de la disponibilité et des photos.
- Les informations obligatoires bloquent la diffusion, pas l'enregistrement du brouillon.
- Chaque canal n'affiche que les actions réellement disponibles et conserve son statut propre.
- Avant une diffusion payante, le coût et le canal sont confirmés explicitement ; aucun débit implicite.
- Le bailleur peut arrêter une annonce, supprimer ses photos et visualiser les canaux qui restent publiés.

## Découpage recommandé après validation

| Incrément | Objectif | Condition de lancement |
|---|---|---|
| 051A | Annonce canonique Pro, modèles de relocation, photos et contrôles de préparation | Plan Pro commercialisable ou bêta Pro contrôlée |
| 051B | Page publique Baillan, partage, exports et hub de canaux | Validation de l'usage avec des bailleurs |
| 051C | Connecteurs sociaux réellement autorisés | API et autorisations confirmées |
| 051D | Multidiffuseur ou portail pilote | Contrat, prix, retrait et retours d'erreur définis |

## Validation discovery avant développement

- 12 entretiens avec des bailleurs 1–5 biens, dont au moins 6 ayant reloué au cours des 18 derniers mois.
- Prototype : bien → annonce préremplie → modèle → diffusion. Objectif : 80 % terminent sans aide et 70 % comprennent que les frais portails sont séparés.
- Test des prix 59 €, 79 € et 99 €/an sur trafic comparable ; conserver 79 € si la conversion ne chute pas significativement face à 59 €.
- Qualifier au moins un multidiffuseur ou portail : accès, conditions particulier/pro, coût fixe/variable, retrait, synchronisation et traitement des échecs.

## Métriques de succès

- Activation : Pro créant un brouillon dans les 7 jours.
- Complétion : brouillon → prêt à diffuser ; temps médian de création.
- Réemploi : part des annonces créées depuis un modèle.
- Diffusion : canaux moyens par annonce et taux de succès/rejet par canal.
- Business : conversion gratuit → Pro depuis le paywall annonces, rétention Pro à 90 jours, marge brute Pro et marge par campagne.
- Garde-fous : coût de stockage/sortie par annonce, exposition d'adresse signalée, taux de retrait réussi.
