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
- **Droit à l'effacement** : suppression du compte
  - Exception : conserver les quittances 5 ans (obligation fiscale)
  - Donc soft-delete des entités à valeur légale, hard-delete du reste
- **Nom du responsable de traitement** dans les emails sortants
- **Lien de désabonnement** dans les emails non-transactionnels

## Conservation des données

- Quittances et baux : **5 ans minimum** (obligation fiscale et prescription civile)
- Documents comptables liés : **10 ans** (code de commerce)
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
