# [FEAT-029] Charges copropriété exceptionnelles + régularisation annuelle des charges

## User story

En tant que **bailleur utilisateur de Baillan**, je veux **enregistrer une charge de copropriété exceptionnelle et faire la régularisation annuelle des charges récupérables** afin de **respecter mon obligation légale de décompte annuel (bail nu) et facturer au locataire les charges réelles qui dépassent les provisions mensuelles encaissées**.

## Context & motivation

Aujourd'hui, `leases.chargesAmountCents` porte une provision mensuelle unique versée par le locataire avec le loyer, et `payments` enregistre un couple `rentAmountCents` + `chargesAmountCents` par période — mais rien ne permet de distinguer un paiement de loyer « normal » d'un paiement lié à une régularisation ou à une charge exceptionnelle. Il n'existe aucune notion de « décompte » comparant provisions encaissées vs dépenses réelles du syndic.

Deux besoins distincts remontent du verbatim utilisateur :

1. **Charge copro exceptionnelle / supplémentaire** : un appel de fonds ponctuel du syndic (ravalement, ascenseur, sinistre) que le bailleur doit parfois répercuter au locataire (si la charge est de nature récupérable au sens du décret n°87-713) ou absorber lui-même (si non récupérable — impacte alors `properties.condoFeesNonRecoverableCents`, déjà existant, utilisé pour la rentabilité).
2. **Régularisation annuelle des charges** (bail nu uniquement, art. 23 loi du 6 juillet 1989) : au moins une fois par an, le bailleur doit comparer le total des provisions encaissées sur la période aux dépenses réelles justifiées par le syndic, et calculer un solde — à réclamer au locataire (complément) ou à lui rembourser (trop-perçu). Cette régularisation doit pouvoir être communiquée au locataire (justification écrite légalement requise, un mois avant exigibilité si le bail le prévoit).

Ce chantier était déjà identifié dans `docs/ROADMAP.md` (P1 : « Gestion des charges récupérables / non-récupérables », « Régularisation annuelle des charges ») mais jamais spécifié ni construit.

**Portée de ce document** : cadrage produit uniquement. Aucune ligne de code, migration, règle Firestore ou Cloud Function n'a été touchée pour produire cette spec.

## Analyse d'options — impact modèle de données

### Rappel de l'état actuel (vérifié dans le code, pas seulement `SCHEMA.md`)

| Entité | Champ pertinent | Rôle actuel |
|---|---|---|
| `leases` | `chargesAmountCents` | Provision mensuelle récupérable, votée avec le loyer |
| `leases` | `leaseType` | Enum `unfurnished / furnished / mobility / student` — **existe déjà**, exploitable pour distinguer nu (régularisation obligatoire) vs meublé (forfait, pas de régularisation légale) |
| `payments` | `rentAmountCents` + `chargesAmountCents` | Montants d'une période, **déjà séparés** — bonne nouvelle : la brique de saisie « loyer / charges » existe |
| `payments` | *(aucun champ type)* | Impossible de dire si un paiement est un loyer normal, un rattrapage de régularisation, ou une charge exceptionnelle |
| `payments` | Immuabilité | `PaymentRepository.archive()` lève `UnsupportedError` — les paiements ne sont **jamais** modifiés/supprimés après création (cohérent loi 1989). Toute solution doit respecter cette immuabilité, pas la contourner. |
| `properties` | `condoFeesNonRecoverableCents` | Coût annuel non récupérable, **côté rentabilité bailleur** — sans lien avec un décompte locataire |
| `receipts` | — | Immuable, un receipt = un paiement. Pas de notion de type de document non plus |

### Option A — Ajouter un champ `type` sur `payments`

Ajouter `paymentType: 'rent' | 'charge_regularization' | 'exceptional_charge'` (defaut `'rent'`) au document `payments`, sans nouvelle collection.

- **Pour** : minimal, pas de nouvelle collection/rules/index. Réutilise le flux d'enregistrement de paiement existant (formulaire, callable `createPayment`, génération de quittance). Le montant `rentAmountCents` deviendrait `0` pour une ligne de type régularisation, avec le solde logé dans `chargesAmountCents` — ou un signe négatif si trop-perçu (**à trancher**, cf Décisions).
- **Contre** : un `payment` sert aussi à générer une **quittance** (loi 1989) — une quittance de régularisation n'a pas le même contenu légal qu'une quittance de loyer (elle doit référencer le décompte, la période concernée par la régularisation qui peut différer de la période du paiement, le détail provisions vs réel). Fusionner « paiement » et « décompte » dans une même collection risque de complexifier `generateReceipt` (déjà une CF avec logique conditionnelle) et de casser l'hypothèse actuelle « 1 payment = 1 quittance simple ».
- **Ne capture pas** le décompte lui-même (rien pour stocker : provisions encaissées sur la période, dépenses réelles par nature de charge, justificatif syndic). Un `type` seul répond au marquage, pas au calcul.

### Option B — Nouvelle entité `charge_statements` (décompte de charges) + paiements liés

Nouvelle collection `charge_statements/{id}` : un décompte = une période de référence (ex. 01/01/2025–31/12/2025), le total des provisions encaissées sur cette période (calculable depuis `payments` ou saisi), le total des dépenses réelles (saisi manuellement depuis le décompte syndic), le solde (positif = à réclamer, négatif = à rembourser), un statut (`draft / finalized / settled`), et un lien optionnel vers le `payment` qui règle le solde une fois le locataire remboursé/débité.

- **Pour** : modélise correctement le concept légal (un décompte de régularisation n'est PAS un paiement — c'est un document de calcul et de justification qui peut exister avant même qu'un paiement ne le solde). Permet en V2 un détail par nature de charge (chauffage collectif, entretien espaces verts, ascenseur...) sans reprendre le modèle plus tard. Sépare proprement le concept « paiement immuable loi 1989 » du concept « décompte réglementaire distinct ».
- **Contre** : nouvelle collection = nouvelles `firestore.rules` + nouveaux indexes composites + probablement une nouvelle Cloud Function (calcul du solde ne doit pas être falsifiable côté client, cross-entity avec `leases`/`payments`) → **risque direct avec la contrainte connue** : `firestore.rules` a des modifications locales non commitées sur la branche courante et `functions/` a un `deploy` actuellement cassé (mémoire projet : provisioning landlord 100% client depuis la suppression de `handleNewUser`). Ajouter une collection + CF ici n'est donc pas un simple ticket d'implémentation : c'est un ticket qui dépend d'abord de la remise en état de `functions/`.

### Recommandation

**Option B pour le concept, avec un scope V1 réduit qui limite le risque d'infrastructure.** Le concept légal (comparaison provisions vs réel, solde, justification) est fondamentalement différent d'un paiement, et le forcer dans `payments.type` produirait une dette de modélisation qu'on paierait cher dès qu'on voudrait le détail par nature de charge (V2) ou l'historique des décomptes indépendamment des paiements qui les soldent.

Cependant, compte tenu du risque `functions/`/`rules`, **le scope V1 proposé plus bas limite volontairement l'implémentation pour ne pas bloquer sur une CF complexe** — voir déroulé V1/V2.

Pour la **charge exceptionnelle simple** (besoin 1 du verbatim, hors régularisation annuelle) : si le bailleur veut juste noter « le syndic a appelé 300 € pour l'ascenseur, refacturés au locataire ce mois-ci », c'est un besoin plus proche de l'Option A (un paiement additionnel, hors loyer standard, sur la période courante) que de l'Option B. **Les deux besoins du verbatim ne demandent donc pas la même brique technique** — voir découpage V1/V2.

## Régime meublé vs nu — décision de scope

- **Bail nu** (`leaseType == unfurnished`, et par extension `student`/`mobility` à vérifier légalement — **cf Décisions**) : provisions + régularisation annuelle **obligatoire** (art. 23 loi du 6 juillet 1989).
- **Bail meublé avec forfait de charges** : pas de régularisation légale — le forfait est libératoire. `leaseType == furnished` peut néanmoins avoir des charges au réel selon le contrat signé (rare, mais possible) — l'app ne peut pas le déduire uniquement de l'enum.
- **Décision de scope proposée** : **V1 limité au bail nu (`unfurnished`)**. Le bouton/action de régularisation n'apparaît que sur les baux nus. Pour les autres types, un message explicite indique que la régularisation ne s'applique pas (forfait) — évite une fausse impression de conformité pour un cas où la loi ne l'exige pas telle quelle.

## Découpage V1 / V2

### V1 — Saisie manuelle + document de régularisation, scope bail nu uniquement

1. **Charge copro exceptionnelle** : réutiliser le flux de paiement existant en ajoutant un **motif/libellé optionnel** au paiement (ex. champ `notes` déjà existant sur `payments` — **déjà suffisant sans migration** si on accepte de ne pas le distinguer structurellement en V1) OU ajouter un champ `paymentType` minimal (`rent` par défaut / `exceptional_charge`) si on veut pouvoir le filtrer/afficher distinctement dans l'historique et sur le dashboard. **Décision à trancher avec l'utilisateur** (cf Décisions) — impacte l'effort.
2. **Régularisation annuelle** : un formulaire de saisie manuelle du décompte (période de référence, total provisions encaissées **pré-rempli par somme des `payments.chargesAmountCents` sur la période** — lecture seule, calcul client, pas de nouvelle CF nécessaire pour cette lecture agrégée simple —, total dépenses réelles **saisi manuellement** par le bailleur depuis le décompte syndic papier/PDF, solde calculé automatiquement) aboutissant à un **document PDF « avis de régularisation des charges »** téléchargeable/partageable (même mécanisme Web Share que la quittance), mais **sans persister de nouvelle collection Firestore en V1** — le document est généré à la volée à partir des données saisies et **archivé comme un `document` classique** (collection `documents/{id}` déjà existante, catégorie à étendre, ex. `category: 'charge_statement'`) plutôt que comme une nouvelle collection métier.
3. Le solde calculé (à réclamer / à rembourser) est **affiché à l'utilisateur mais l'encaissement/remboursement réel reste un paiement classique** que le bailleur enregistre séparément via le flux `createPayment` existant (avec le motif/libellé de V1.1) — **pas d'automatisation du rapprochement en V1**.

Ce V1 volontairement minimal évite : nouvelle collection métier, nouveaux indexes composites, nouvelle Cloud Function cross-entity. Il réutilise `documents` (déjà CF `createDocument`, déjà `legalHold`) et éventuellement un enrichissement mineur de `payments` (à trancher). **Reste néanmoins un risque à vérifier** : étendre `documents.category` à une nouvelle valeur peut nécessiter de toucher `firestore.rules` (validation de l'enum côté rules) — **à vérifier techniquement par l'architecte avant de considérer ce point acquis** (cf Risques).

### V2 (hors scope de ce ticket)

- Décompte détaillé par nature de charge (chauffage collectif, entretien, ascenseur, eau...) avec ventilation ligne à ligne — nécessiterait la collection `charge_statements` (Option B) pour être robuste.
- Rapprochement automatique entre le décompte et le(s) paiement(s) qui le soldent (aujourd'hui : deux actions manuelles indépendantes en V1).
- Alerte/rappel automatique « régularisation annuelle à faire » sur le dashboard (dépend de `leases.startDate`/anniversaire de bail).
- Historique consultable des régularisations passées avec statut (calculée / envoyée / soldée) — en V1 le document généré est un artefact ponctuel, pas un objet suivi dans le temps avec statut.
- Gestion différenciée des baux meublés à charges réelles (hors forfait) — nécessite un champ contractuel supplémentaire non modélisé aujourd'hui.
- Import du décompte syndic (OCR/PDF) — item roadmap P2 « OCR de baux scannés » à étendre.

## Acceptance criteria (Gherkin) — V1

```gherkin
Fonctionnalité : Charge copropriété exceptionnelle

Scénario : bailleur enregistre une charge exceptionnelle refacturée au locataire
  Given je suis sur un bail nu actif avec un locataire
  When j'enregistre un nouveau paiement avec un motif "Régularisation ascenseur T2 2026"
  And un montant de charges de 150,00 €
  Then le paiement apparaît dans l'historique du bail avec son motif visible
  And le motif figure sur la quittance ou le reçu généré pour ce paiement

Fonctionnalité : Régularisation annuelle des charges (bail nu)

Scénario : bailleur lance une régularisation sur un bail nu
  Given un bail avec leaseType = "unfurnished"
  And des paiements enregistrés sur la période 01/01/2025 au 31/12/2025 totalisant 1 200,00 € de charges provisionnées
  When le bailleur ouvre l'action "Régularisation annuelle des charges" depuis le bail
  Then le total des provisions encaissées sur la période est pré-rempli automatiquement à 1 200,00 €
  And le bailleur peut saisir le montant réel des dépenses justifié par le syndic
  And le solde (dépenses réelles − provisions encaissées) est calculé et affiché immédiatement
  And un libellé clair indique si le solde est "à réclamer au locataire" (positif) ou "à rembourser au locataire" (négatif)

Scénario : régularisation indisponible sur un bail meublé au forfait
  Given un bail avec leaseType = "furnished"
  When le bailleur consulte le détail du bail
  Then l'action "Régularisation annuelle des charges" n'est pas proposée
  And un message explique que le forfait de charges ne donne pas lieu à régularisation légale

Scénario : génération du document de régularisation
  Given une régularisation a été calculée avec un solde de 85,00 € à réclamer au locataire
  When le bailleur valide la régularisation
  Then un document PDF "Avis de régularisation des charges" est généré
  And ce document mentionne : identité bailleur, identité locataire, adresse du logement,
    période de référence, total des provisions encaissées, total des dépenses réelles, solde et son sens
  And ce document est archivé dans les documents du bail et peut être partagé (Web Share, comme les quittances)

Scénario : bailleur encaisse le solde de régularisation
  Given une régularisation calculée avec un solde de 85,00 € à réclamer
  When le bailleur enregistre un nouveau paiement pour ce montant avec le motif "Régularisation charges 2025"
  Then ce paiement suit le flux d'enregistrement de paiement standard
  And aucun rapprochement automatique n'est effectué entre le document de régularisation et ce paiement (V1 = actions manuelles indépendantes)
```

## Out of scope

- Décompte détaillé par nature de charge (V2).
- Rapprochement automatique décompte ↔ paiement de règlement (V2).
- Rappel/alerte automatique de régularisation annuelle à faire (V2, dépend du dashboard).
- Historique avec statut des régularisations passées (V2).
- Baux meublés à charges réelles hors forfait (non modélisé, V2+).
- Import/OCR du décompte syndic (P2 roadmap existant).
- Toute modification de `firestore.rules` ou `functions/` au-delà de ce qui est strictement nécessaire et validé explicitement — **pas d'extension silencieuse de scope technique**.

## Dependencies

- **Collections Firestore concernées** : `payments` (lecture agrégée pour pré-remplir les provisions ; éventuel champ `notes`/`paymentType` — à trancher), `documents` (nouvelle valeur de `category` pour l'avis de régularisation), `leases` (lecture `leaseType` pour le gate meublé/nu).
- **Features bloquantes** : aucune — s'appuie sur FEAT-005 (baux), FEAT-006 (paiements), FEAT-009 (documents) déjà livrées.
- **Risque infrastructure à lever avant chiffrage définitif** : `firestore.rules` a des modifications locales non commitées sur la branche courante (`git status` : `M firestore.rules`) et le déploiement de `functions/` est décrit comme cassé (mémoire projet, provisioning `handleNewUser` supprimé). **Toute évolution de `documents.category` (validation d'enum côté rules) ou tout champ additionnel sur `payments` validé côté Cloud Function `createPayment` dépend d'abord de la remise en état de cette zone.** Ce ticket ne doit pas être chiffré/planifié en implémentation tant que l'architecte n'a pas confirmé si ces changements sont possibles sans toucher aux zones à risque, ou si un chantier de stabilisation `functions/`/`rules` est un prérequis.

## Legal / compliance notes

- **Art. 23 loi du 6 juillet 1989 + décret n°87-713** : régularisation annuelle obligatoire en location nue, sur la base des dépenses réellement engagées par le bailleur, avec justification (mode de calcul, nature des charges). Le document V1 doit rester consultable/exportable comme justificatif.
- **Distinction récupérable / non récupérable** : seules les charges de nature récupérable (décret 87-713, liste limitative) peuvent être incluses dans la régularisation transmise au locataire. `properties.condoFeesNonRecoverableCents` reste hors périmètre du décompte locataire — ne pas mélanger les deux dans le calcul du solde (risque de sur-facturation illégale au locataire).
- **Conservation des données** : le document de régularisation, comme les quittances, doit suivre la règle de rétention 5 ans (`docs/LEGAL.md`) — cohérent avec un stockage dans `documents` si `legalHold` est correctement positionné pour cette nouvelle catégorie.
- **Meublé au forfait** : rappeler explicitement dans l'UI que le forfait est libératoire pour éviter qu'un bailleur ne réclame une régularisation illégale sur ce type de bail.
- **Format montants/dates** : `1 234,56 €` et `DD/MM/YYYY`, cohérent avec les quittances existantes.

## Décisions à trancher par l'utilisateur

1. **Charge exceptionnelle — champ structuré ou simple motif texte ?**
   Option "notes" (déjà existant, zéro migration, zéro risque `functions/`) vs option "paymentType" enum (permet filtrage/affichage distinct dans l'historique et le dashboard, mais touche `createPayment` côté CF et donc la zone à risque). **Recommandation par défaut si aucune préférence : démarrer par "notes"**, gratuit et sans risque, à faire évoluer vers un `paymentType` plus tard si le besoin de filtrage se confirme à l'usage.
2. **Portée `leaseType`** : le gate "régularisation activée" doit-il couvrir uniquement `unfurnished`, ou aussi `student`/`mobility` (baux qui peuvent légalement comporter des provisions de charges selon leurs modalités propres) ? Proposition par défaut : `unfurnished` uniquement en V1, extension possible en V2 après vérification légale des deux autres régimes.
3. **Sens du signe du solde** : convention d'affichage/stockage pour un trop-perçu (remboursement au locataire) — nombre négatif avec libellé explicite, ou deux champs séparés (`amountDueByTenantCents` / `amountDueToTenantCents`, un seul non-nul) ? Impacte le futur schéma si on migre vers l'Option B en V2.
4. **Emplacement de l'action dans l'UI** : bouton dédié sur `LeaseDetailPage` ("Régularisation annuelle"), ou sous-item dans le flux de paiement existant ? Impacte l'architecte pour le découpage des écrans.
5. **Confirmation du risque `functions/`/`rules`** : l'utilisateur souhaite-t-il traiter la remise en état de cette zone comme un prérequis explicite avant tout chiffrage d'implémentation de FEAT-029, même pour le scope V1 réduit proposé ici ?

## Priority

P1 (post-MVP) — déjà identifié dans `docs/ROADMAP.md`, ne fait pas partie des 10 features P0 du MVP.

## Estimated effort

**Cadrage uniquement livré ici (pas de code).** Pour le V1 tel que scopé ci-dessus, une fois les décisions tranchées et le risque `functions/`/`rules` levé par l'architecte :

- Charge exceptionnelle (option "notes") : **S** (< 1 jour — UI seule, zéro migration).
- Charge exceptionnelle (option "paymentType" enum) : **M** (touche `createPayment`, zone à risque).
- Régularisation annuelle V1 complète (formulaire + calcul + PDF + archivage `documents`) : **L** (> 3 jours) — à re-découper par l'architecte en sous-tickets si nécessaire (ex. formulaire+calcul / génération PDF / archivage) pour rester sous la règle "story < 3 jours".
