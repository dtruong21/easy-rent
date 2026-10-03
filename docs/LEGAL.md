# Contraintes légales — EasyRent

## Quittance de loyer (loi du 6 juillet 1989, art. 21)

Champs obligatoires sur le PDF :
- Nom et adresse du **bailleur** (propriétaire)
- Nom du **locataire**
- **Adresse du logement** loué
- **Période** concernée (mois/année)
- **Montant du loyer** hors charges
- **Montant des charges** (provisions ou récupérables)
- **Montant total payé**
- **Date d'émission**
- Titre clair : "Quittance de loyer"

## Distinction quittance vs reçu

- **Quittance** = paiement intégral du terme → libère le locataire de sa dette pour cette période
- **Reçu** = paiement partiel → mention obligatoire "ne libère pas le locataire du solde"

Ne jamais émettre une quittance si le paiement n'est pas complet.

## RGPD

Obligations à respecter :
- **Consentement explicite** lors du signup (case à cocher non pré-cochée)
- **Politique de confidentialité** accessible (URL dans le footer)
- **Droit d'accès** : possibilité d'exporter ses données (`GET /export`)
- **Droit à l'effacement** : suppression du compte in-app (FEAT-045 —
  écran Profil → « Supprimer mon compte » + page publique `/delete-account`)
  - Exception : les **quittances émises** sont conservées 5 ans par la
    plateforme (preuve de l'émission, art. 2224 C. civ. / obligation
    fiscale), sous forme archivée inaccessible, puis purgées à l'échéance
    (`retentionUntil`)
  - **Tout le reste est hard-delete immédiat** (biens, locataires, baux,
    paiements, documents — y compris `legalHold` —, dépenses, simulations,
    décomptes de charges, états des lieux, profil, fichiers Storage, compte
    Auth ; décomptes et états des lieux ajoutés le 2026-09-30, constat
    OWASP-05). Position assumée : les devoirs
    de conservation des baux (5 ans) et pièces comptables (10 ans)
    incombent au **bailleur** pour ses propres documents — le flux de
    suppression l'avertit explicitement de les télécharger avant ; la
    plateforme ne conserve en son nom que la trace des quittances émises
  - La rétention des quittances est annoncée dans le flux de suppression
    ET dans la politique de confidentialité (v1.3, §5) — exigence des
    politiques Google Play / App Store
- **Nom du responsable de traitement** dans les emails sortants
- **Lien de désabonnement** dans les emails non-transactionnels

## Résiliation d'abonnement en ligne (art. L215-1-1 C. conso.)

L'abonnement **Baillan Pro** est souscrit en ligne (Stripe Checkout). L'art.
**L215-1-1** du Code de la consommation (dispositif « résiliation en trois
clics », décret 2023-182, applicable depuis le **1ᵉʳ juin 2023**) impose alors
d'offrir une résiliation **au moins aussi simple** que la souscription :
en ligne, gratuite, accessible en permanence, avec un **récapitulatif présenté
avant la confirmation**.

Conformité Baillan (FEAT-044f) :
- **Parcours en 3 clics** : (1) ouvrir `/profile`, (2) « Résilier mon
  abonnement », (3) « Confirmer la résiliation ». Aucun tiers, aucune friction,
  aucun contact commercial imposé.
- **Récapitulatif avant confirmation** : la boîte de dialogue énonce la date de
  fin d'accès (`proExpiresAt`, format DD/MM/YYYY), le passage automatique en
  formule gratuite, et l'absence de remboursement au prorata (choix produit =
  résiliation en **fin de période payée**, l'accès Pro est conservé jusqu'au
  terme déjà réglé).
- **Gratuité + permanence** : bouton in-app disponible tant que l'abonnement
  court.
- **Réactivation** possible tant que la période n'est pas terminée (symétrie de
  l'action, évite une re-souscription payante après une résiliation par erreur).

> Périmètre : web uniquement pour l'instant. Un abonnement souscrit via l'App
> Store / Google Play (mobile, non encore livré) se résilie obligatoirement via
> l'UI système de l'éditeur — l'app y **renvoie** l'utilisateur plutôt que de
> proposer un bouton in-app, conformément aux règles Apple/Google.

## Conservation des données

- Quittances et baux : **5 ans minimum** (obligation fiscale et prescription
  civile) — devoir du **bailleur** pour ses documents ; côté plateforme,
  tant que le compte est actif rien n'est purgé (`legalHold` sur les
  documents à valeur légale), et après suppression du compte seules les
  **quittances** sont archivées 5 ans (cf. « Droit à l'effacement »)
- Documents comptables liés : **10 ans** (code de commerce) — devoir du
  bailleur ; à télécharger avant toute suppression de compte
- Données personnelles hors documents légaux : effaçables à la demande

## Mentions email

Tous les emails sortants doivent contenir :
- Nom de l'application (EasyRent) et coordonnées du propriétaire émetteur
- Lien vers la politique de confidentialité
- Lien de désabonnement (sauf transactionnels obligatoires comme l'envoi de quittance)

## Format dates et montants

- Dates : **DD/MM/YYYY** (locale fr_FR)
- Montants : **`1 234,56 €`** (espace insécable, virgule décimale, € à droite)
- Mois en français dans les quittances : "Loyer de janvier 2026"
