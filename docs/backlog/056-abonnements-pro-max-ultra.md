# FEAT-056 — Abonnements payants : Pro, Max, Ultra

> Statut : **📋 Cadré (2026-07-31, deux fois révisé le même jour après arbitrages propriétaire)** — spec produit/commerciale, aucun développement lancé. Périmètre visé : **staging uniquement**, compatible avec la réouverture commerciale prévue vers le **2026-08-25** (`SUBSCRIPTIONS_ENABLED` reste `false` en prod jusque-là). Aucune action Stripe réelle n'a été effectuée pour produire ce document.
>
> **Arbitrages tranchés le 2026-07-31** (repris dans tout le document ci-dessous) : (1) seul **Pro** est achetable au lancement, Max/Ultra s'affichent en « bientôt disponible » ; (2) grille tarifaire Variante A retenue ; (3) réallocation de features — Max = annonces (FEAT-051) + rappels (FEAT-031), Ultra = export comptable (FEAT-032) + multi-utilisateurs (FEAT-034) ; (4) conflit avec FEAT-051 tranché en faveur de Max (note ajoutée dans son fichier) ; (5) SLA support non publiés tant que la capacité opérationnelle n'est pas validée ; **(6) NOUVEAU — les quotas de volume (biens/locataires/baux/documents/scénarios) sont désormais différenciés entre Pro, Max et Ultra** (grille resserrée retenue, détail §2), avec grandfathering illimité à vie pour les comptes legacy `paid` (détail §6).

## 0. Résumé exécutif

Aujourd'hui il existe un seul palier payant (« Baillan Pro », `subscriptionTier = 'paid'`), pas encore commercialisé en prod. Ce document découpe l'offre payante en **trois paliers — Pro, Max, Ultra** — chacun adressant un profil de bailleur différent, différenciés à la fois par les **features** et, depuis cette révision, par des **plafonds de volume** (biens, locataires, baux, documents, scénarios).

**Reformulation importante** : Baillan reste **forfaitaire** (jamais de facturation qui grimpe par bien ajouté à l'intérieur d'un palier) mais n'est plus **illimité dès Pro**. Cette nuance corrige la faiblesse relevée sur la version précédente de ce document : sans plafonds différenciés, Max et Ultra ne se distinguaient de Pro que par des features non construites — un pari sur l'avenir, pas une valeur immédiate. Avec des plafonds différenciés, **Max a une raison d'être dès aujourd'hui**, même avant que ses features distinctives (FEAT-031, FEAT-051) soient livrées. Seul **Ultra reste illimité** sur toute la ligne, ce qui en fait la vraie promesse « sans limite » de la grille — reprise du positionnement structure patrimoniale.

**Séquencement de vente inchangé** : seul Pro est réellement achetable à la réouverture du ~25/08. Max et Ultra s'affichent sur `/pro` en « bientôt disponible » avec capture d'intérêt par palier — mais peuvent désormais afficher des **plafonds de volume réels et déjà vrais** (pas des promesses), ce qui rend leur carte « bientôt disponible » plus crédible.

---

## 1. Positionnement — un palier = un profil de bailleur

| Palier | En une phrase |
|---|---|
| **Gratuit** | Le bailleur qui débute ou gère un bien unique : découvre l'outil, gestion manuelle complète mais volumes plafonnés (2 biens). |
| **Pro** | Le bailleur multi-biens qui a dépassé le cadre du gratuit et gère un petit portefeuille (jusqu'à 5 biens) à prix fixe, jamais facturé par bien. |
| **Max** | Le bailleur qui pilote sa **gestion locative active au quotidien** sur un portefeuille plus large (jusqu'à 15 biens) : relancer les impayés sans y penser, reloger vite un bien vacant. |
| **Ultra** | Le bailleur en **structure patrimoniale** (SCI, indivision), **sans limite de volume** : gère à plusieurs avec un comptable, export comptable et collaborateurs invités. |

Lecture : Pro répond à « j'ai dépassé les 2 biens du gratuit, mais je reste un particulier avec un portefeuille raisonnable » (quantité bornée, prix fixe). Max répond à « je passe trop de temps sur les tâches répétitives de gestion — relances, relocation — sur un portefeuille qui a grossi » (opérationnel quotidien, plafond plus haut). Ultra répond à « je ne gère plus seul, il faut partager l'accès, sortir des comptes propres, et le volume n'est plus le sujet » (structure/gouvernance à plusieurs, aucun plafond). Ce n'est pas un empilement arbitraire de « toujours plus » — chaque saut résout une douleur différente, et les plafonds de volume renforcent ce récit au lieu de le contredire : le seuil Max (15 biens) correspond, en gros, au point où un patrimoine individuel commence à justifier une structure (SCI) pour des raisons fiscales/successorales — exactement le moment où Ultra prend le relais.

> **Supersède** la formulation de `docs/backlog/044-monetization-freemium.md` (« un SEUL plan à PRIX FIXE… biens illimités… le prix NE monte PAS avec le patrimoine »). Ce qui reste vrai : le prix ne grimpe jamais par bien ajouté *à l'intérieur* d'un palier (forfaitaire). Ce qui change : « illimité » n'est plus vrai dès Pro — seul Ultra l'est désormais. Fichier non modifié par ce document, note laissée ici pour éviter toute contradiction de lecture.

---

## 2. Matrice de différenciation complète

| Capacité | Gratuit | Pro | Max | Ultra |
|---|---|---|---|---|
| Biens actifs | 2 | **5** | **15** | Illimité¹ |
| Locataires actifs | 3 | **8** | **20** | Illimité¹ |
| Baux actifs | 2 | **5** | **15** | Illimité¹ |
| Documents actifs (nombre) | 10 | **50** | **150** | Illimité¹ |
| Taille max. par document uploadé | 10 Mio | 10 Mio | 25 Mio | 50 Mio |
| Scénarios simulateur sauvegardés | 3 | **15** | **30** | Illimité¹ |
| Comparaison de scénarios d'investissement (FEAT-055) | ❌ | ✅ | ✅ | ✅ |
| Régularisation annuelle des charges | ❌ | ✅ | ✅ | ✅ |
| Quittances PDF conformes (loi du 6/07/1989) | ✅ | ✅ | ✅ | ✅ |
| Envoi de quittance par email | ✅ | ✅ | ✅ | ✅ |
| Dashboard récap (loyers du mois, retards) | ✅ | ✅ | ✅ | ✅ |
| Export RGPD / suppression de compte | ✅ | ✅ | ✅ | ✅ |
| Rappels automatiques de paiement (FEAT-031)² | ❌ | ❌ | ✅ | ✅ |
| Annonces réutilisables & diffusion multi-portails (FEAT-051)² | ❌ | ❌ | ✅ (frais de diffusion en sus, par campagne) | ✅ |
| Export comptable annuel CSV (FEAT-032)² | ❌ | ❌ | ❌ | ✅ |
| Collaborateurs invités (comptable, co-associé, mandataire) (FEAT-034)² | ❌ | ❌ | ❌ | ✅ jusqu'à 3 |
| Accès anticipé aux nouveautés (bêta) | ❌ | ❌ | ✅ | ✅ |
| Support | Standard | Standard | Prioritaire³ | Dédié³ |
| Résiliation en ligne en 3 clics (art. L215-1-1 C. conso.) | — | ✅ | ✅ (dès ouverture du palier) | ✅ (dès ouverture du palier) |
| **Achetable à la réouverture (~25/08)** | — (déjà accessible) | **✅ oui** | 🔜 **bientôt** (capture d'intérêt) | 🔜 **bientôt** (capture d'intérêt) |

¹ « Illimité » reste soumis à un plafond technique anti-abus déjà en place indépendamment du palier (200 biens par requête liste, cf. `property_repository.dart` — cible produit réelle : 1-20 biens), pas un argument commercial affiché, juste un garde-fou existant. Seul le palier **Ultra** en bénéficie désormais (Pro et Max ont des plafonds commerciaux explicites, très en-dessous de ce seuil technique).
² Feature **non construite à ce jour** — le palier existe et peut être affiché dès aujourd'hui (verrouillage + argumentaire + capture d'intérêt), la vente réelle n'ouvre qu'à la livraison de la/des feature(s) distinctive(s) du palier (voir §6). **Différence clé avec la version précédente de ce document** : même sans ces features, Max se distingue déjà concrètement de Pro par ses plafonds de volume (3× sur biens/baux, 2,5× sur locataires, 3× sur documents et scénarios) — la différenciation ne repose plus sur un seul chantier non livré.
³ « Prioritaire »/« Dédié » sont volontairement **qualitatifs, sans chiffre publié** — une cible de délai (24h ouvrées / 12h ouvrées) existe en interne mais n'est pas validée côté capacité support ; ne pas l'afficher publiquement tant que ce n'est pas confirmé (voir note en fin de §5).

**Les comptes legacy migrés depuis l'ancien palier unique `paid` gardent l'illimité à vie sur les 5 lignes en gras ci-dessus** (grandfathering, détail §6) — les plafonds Pro/Max ne s'appliquent qu'aux nouveaux abonnés post-migration.

### Deux grilles de quotas envisagées

**Grille resserrée (recommandée)**

| Capacité | Gratuit | Pro | Max | Ultra | Justification du plafond |
|---|---|---|---|---|---|
| Biens actifs | 2 | 5 | 15 | Illimité | Le gratuit couvre déjà le mono/bi-bien, cœur du marché des bailleurs particuliers. Pro (5) laisse une marge confortable au-delà du profil « 1 à 3 biens » sans jamais ressembler à un piège à upsell. Max (15) borne le « petit multi-bien actif » — au voisinage du seuil où un patrimoine individuel commence, en pratique, à justifier une structure (SCI) pour des raisons fiscales/successorales. Ultra prend le relais sans limite, cohérent avec le profil structure. |
| Locataires actifs | 3 | 8 | 20 | Illimité | Ratio ≈1,5-1,6× le nombre de biens (marge colocation), calqué sur le ratio déjà retenu en gratuit (3 pour 2 biens). |
| Baux actifs | 2 | 5 | 15 | Illimité | Ratio 1:1 avec les biens (un bail actif type par bien), identique au ratio gratuit (2 pour 2 biens). |
| Documents actifs | 10 | 50 | 150 | Illimité | ≈10 documents/bien (diagnostics, assurance, état des lieux, quittances archivées) — double le ratio serré du gratuit (5/bien), cohérent avec un usage payant plus complet. |
| Scénarios simulateur | 3 | 15 | 30 | Illimité | Non indexé sur le nombre de biens (usage prospectif, pas le patrimoine détenu) ; doublé à chaque palier pour rester généreux sur une fonctionnalité déjà gatée Pro+ (comparaison de scénarios, FEAT-055). |

**Grille généreuse (alternative, écartée)**

| Capacité | Gratuit | Pro | Max | Ultra |
|---|---|---|---|---|
| Biens actifs | 2 | 10 | 25 | Illimité |
| Locataires actifs | 3 | 15 | 35 | Illimité |
| Baux actifs | 2 | 10 | 25 | Illimité |
| Documents actifs | 10 | 100 | 250 | Illimité |
| Scénarios simulateur | 3 | 20 | 40 | Illimité |

**Recommandation : grille resserrée.** Trois raisons : (1) le marché visé — explicitement « du mono-bien au petit multi-bien / SCI familiale » — est concentré sur des petits volumes ; un Pro à 10 biens et un Max à 25 biens ne seraient quasiment jamais atteints organiquement par la cible réelle, ce qui viderait Max de sa raison d'être commerciale (c'est précisément le défaut relevé sur ce document) ; (2) l'écart concurrentiel reste massif même sur la grille resserrée (voir calcul ci-dessous) — resserrer les plafonds ne sacrifie donc pas l'argument prix ; (3) un Pro à 5 biens correspond déjà à un multiple confortable du profil déclaratif dominant (bailleurs à 1-3 biens), donc sans risque de « piège à upsell » pour l'écrasante majorité du marché individuel.

**Donnée de marché mobilisée** : le produit n'est pas encore commercialisé, donc aucune donnée d'usage propriétaire n'existe. Le calibrage s'appuie sur (a) la cible produit déjà actée dans le code existant (`property_repository.dart` : commentaire « cible utilisateur : 1-20 biens »), (b) le repère qualitatif largement partagé par les acteurs français de la gestion locative — la structure du marché des bailleurs particuliers est fortement concentrée sur le mono- et micro-bien, les patrimoines à deux chiffres relevant en général de foncières familiales/SCI plutôt que du bailleur particulier isolé — et (c) le positionnement marché déjà écrit dans le brief produit (« du mono-bien au petit multi-bien / SCI familiale »). **À valider avec de vraies données d'usage dès que le produit aura des abonnés réels** — ces plafonds sont une hypothèse de lancement, pas une science exacte.

### Coût par bien au plafond (argument concurrentiel)

| Palier | Prix mensuel | Plafond biens (resserrée) | Coût par bien/mois au plafond | vs concurrents (9,75-12,99 €/bien/mois) |
|---|---|---|---|---|
| Pro | 7,99 € | 5 | 1,60 € | **6,1× à 8,1× moins cher** |
| Max | 14,99 € | 15 | 1,00 € | **9,75× à 13× moins cher** |
| Ultra | 24,99 € | Illimité | décroît en continu (ex. 0,50 €/bien à 50 biens, 0,25 €/bien à 100 biens) | toujours moins cher, l'écart croît avec le patrimoine |

Même au palier le plus contraint (Pro, le plus bas plafond), Baillan reste 6 à 8 fois moins cher par bien que BailFacile/Gérer Seul (9,75-12,99 €/mois **par bien**), et l'écart s'élargit à chaque palier supérieur. Avec la grille généreuse écartée, l'écart aurait été encore plus grand (12 à 22× moins cher) mais au prix d'un Max quasiment inatteignable par la cible réelle — ce qui aurait reproduit le problème que cette révision corrige.

**Ce qui est livrable SANS construire de nouvelle feature métier** : la différenciation de volume elle-même est de la **configuration**, pas du développement — elle étend un pattern déjà en place (`propertyLimit`, `activeTenantLimit`, `activeLeaseLimit`, `documentLimit`, `scenarioLimit`, aujourd'hui un switch binaire free/paid, à étendre à 4 branches free/pro/max/ultra=null). Le palier **Pro entier** (quotas + régularisation + comparaison de scénarios) et la **majorité de Max** (quotas plus larges, quota de taille de fichier, support prioritaire — politique, pas code) sont donc vendables sans attendre de nouveau chantier métier. Seuls 4 éléments dépendent encore d'un chantier séparé non livré : **rappels (FEAT-031) et annonces & diffusion (FEAT-051) pour Max** ; **export comptable (FEAT-032) et multi-utilisateurs (FEAT-034) pour Ultra**. Avec les quotas différenciés, Max n'a plus besoin d'attendre ces deux features pour avoir une valeur perceptible — elles restent en revanche la condition d'ouverture commerciale du palier (§6, décision inchangée par cette révision).

---

## 3. Le « pourquoi je paie plus »

### Gratuit → Pro
- **Argument déclencheur** : « Vous gérez plus de 2 biens, plus de 3 locataires ou plus de 2 baux actifs — passez à 5 biens, sans facturation par bien. »
- **Point d'upsell concret** : bouton « Ajouter un bien » désactivé sur `/properties` au 3ᵉ bien (message `leasesErrorLimitReached` existant, à généraliser aux 3 quotas) ; bannière verrouillée « Régulariser les charges » sur la fiche bail ; bouton « Comparer » verrouillé sur `/simulator` (déjà géré FEAT-055).

### Pro → Max
- **Argument déclencheur** : « Votre portefeuille a dépassé 5 biens — passez à 15. Et arrêtez de relancer vos locataires en retard à la main, ou de ressaisir vos annonces partout pour reloger vite. »
- **Points d'upsell concrets** :
  - **Nouveau (volumétrique)** : bouton « Ajouter un bien » désactivé sur `/properties` au 6ᵉ bien pour un compte Pro (même mécanique que free→Pro, un cran plus haut) → bannière « Passez à Max pour aller jusqu'à 15 biens ». Même mécanique sur `/tenants` (9ᵉ locataire) et à la création de bail (6ᵉ bail actif).
  - Bloc « Loyers en retard » du dashboard → bannière « Activez les relances automatiques avec Max » (FEAT-031 ; en attendant sa livraison, capture d'intérêt via `paid_plan_interest` taguée Max, même mécanisme que le paywall Pro « bientôt disponible » actuel).
  - Fiche bien vacant (pas de bail actif) → bannière « Créez une annonce et diffusez-la avec Max » (FEAT-051).
  - Upload d'un document scanné volumineux (bail + annexes photographiées) qui dépasse 10 Mio, ou compte Pro qui atteint 50 documents actifs → message qui propose Max (25 Mio, 150 documents) au lieu d'un simple refus.

### Max → Ultra
- **Argument déclencheur** : « Votre portefeuille dépasse 15 biens, ou vous gérez en structure (SCI, indivision) avec un comptable ou des co-associés — Ultra lève le plafond et ouvre l'accès partagé. »
- **Points d'upsell concrets** :
  - **Nouveau (volumétrique)** : bouton « Ajouter un bien » désactivé sur `/properties` au 16ᵉ bien pour un compte Max → bannière « Ultra : plus aucun plafond, pensé pour les structures patrimoniales ».
  - `/profile` → nouvelle entrée « Inviter un collaborateur » verrouillée avec argumentaire Ultra (aujourd'hui : 1 compte = 1 bailleur, aucun partage possible ; FEAT-034).
  - Saisonnalité fiscale (avril-mai, déclaration des revenus fonciers) → bannière dashboard « Exportez vos revenus locatifs en un clic avec Ultra » (FEAT-032).
  - Upload d'un document qui dépasse 25 Mio (compte déjà Max) → message d'erreur qui propose Ultra (50 Mio).

---

## 4. Proposition de prix (TTC, marché FR)

**Variante retenue : A (prudente).** L'annuel offre environ **2 mois gratuits** par rapport au mensuel ×12, pour inciter à l'engagement annuel sans jamais imposer d'engagement contractuel (résiliable à tout moment, art. L215-1-1).

| Palier | Mensuel TTC | Annuel TTC | Économie vs mensuel ×12 |
|---|---|---|---|
| Pro | 7,99 € | 79 € | ≈ 17,6 % (~2 mois offerts) |
| Max | 14,99 € | 149 € | ≈ 17,2 % (~2 mois offerts) |
| Ultra | 24,99 € | 249 € | ≈ 17,0 % (~2 mois offerts) |

Pro **reste au prix déjà hypothétisé et affiché** aujourd'hui sur `/pro` et dans `docs/backlog/051-annonces-diffusion-pro.md` (7,99 €/79 €) — aucune ancre déjà communiquée n'est cassée. La grille de prix elle-même n'est **pas modifiée** par cette révision (seuls les plafonds de volume changent) : Max ≈ 1,9× Pro, Ultra ≈ 1,67× Max (≈3,1× Pro).

**Statut des prix Max/Ultra** : tant que ces paliers ne sont pas ouverts à la vente (§6), leurs prix affichés sur `/pro` sont **indicatifs** — à marquer explicitement comme tels dans le copy (voir §5), pas comme un tarif ferme et engageant.

> *Historique de décision* : une Variante B « ambitieuse » (9,99/19,99/39,99 € mensuel, 89/179/349 € annuel, ~25 % d'économie annuelle) a été étudiée puis écartée pour ne pas modifier le prix Pro déjà communiqué au moment où deux nouveaux paliers sont introduits.

Justification concurrentielle détaillée par le calcul du coût par bien au plafond de chaque palier : voir §2 (« Coût par bien au plafond »). Résumé : même sur le palier le plus contraint (Pro), Baillan reste 6 à 8 fois moins cher par bien que BailFacile/Gérer Seul (9,75-12,99 €/mois par bien).

Question encore ouverte (voir §8) : offre de lancement remisée quand Max/Ultra ouvrent réellement à la vente (sur le modèle de l'offre Fondateur envisagée pour Pro, 59 €/79 €).

---

## 5. Copy de la page `/pro`

> Convention : Pro affiche un vrai bouton de paiement (Stripe Checkout) une fois `Env.subscriptionsEnabled == true`. Max et Ultra affichent un badge **« Bientôt disponible »**, un prix marqué **indicatif**, et un bouton de capture d'intérêt — jamais de chemin de paiement — tant que leur palier n'est pas ouvert (§6). Les plafonds de volume affichés sur les cartes Max/Ultra sont en revanche **déjà réels**, pas indicatifs (seuls le prix et les features FEAT-031/032/034/051 le sont). Les libellés « Support prioritaire »/« Support dédié » sont volontairement sans chiffre d'heures (SLA interne non validé, cf. note en fin de section).

### FR

**Titre de page** : Baillan Pro, Max & Ultra
**Titre principal** : Trouvez le palier qui correspond à votre patrimoine
**Sous-titre** : Pro est disponible dès maintenant. Max et Ultra arrivent bientôt — inscrivez-vous pour être prévenu dès l'ouverture. Sans engagement, résiliable en 3 clics.
**Toggle** : Mensuel / Annuel — badge « Économisez ~2 mois »

**Carte Gratuit**
- Titre : Gratuit
- Accroche : Pour découvrir Baillan sur votre premier bien
- Bullets :
  - Jusqu'à 2 biens, 3 locataires, 2 baux actifs
  - 10 documents stockés
  - Quittances PDF conformes à la loi du 6 juillet 1989
  - Paiements, dépenses, dashboard
- CTA : Commencer gratuitement

**Carte Pro**
- Titre : Pro
- Accroche : Pour le bailleur multi-biens, à prix fixe — jamais facturé par bien
- Bullets :
  - Jusqu'à 5 biens, 8 locataires, 5 baux actifs
  - 50 documents stockés
  - 15 scénarios simulateur sauvegardés
  - Régularisation annuelle des charges
  - Comparaison de scénarios d'investissement
  - Support standard
- CTA : Passer Pro

**Carte Max**
- Titre : Max
- Badge : Bientôt disponible
- Accroche : Pour la gestion locative active, au quotidien
- Prix affiché : à partir de 14,99 €/mois *(indicatif)*
- Bullets :
  - Jusqu'à 15 biens, 20 locataires, 15 baux actifs
  - 150 documents stockés (jusqu'à 25 Mio par fichier)
  - 30 scénarios simulateur sauvegardés
  - Relances de paiement automatiques
  - Annonces réutilisables et diffusion multi-portails
  - Support prioritaire
- CTA : Me prévenir à l'ouverture

**Carte Ultra**
- Titre : Ultra
- Badge : Bientôt disponible
- Accroche : Pour la structure patrimoniale (SCI, indivision) gérée à plusieurs, sans limite de volume
- Prix affiché : à partir de 24,99 €/mois *(indicatif)*
- Bullets :
  - Biens, locataires, baux, documents et scénarios illimités
  - Export comptable annuel en un clic
  - Jusqu'à 3 collaborateurs invités (comptable, co-associé, mandataire)
  - Documents jusqu'à 50 Mio
  - Support dédié
- CTA : Me prévenir à l'ouverture

**Pied de page** : Prix TTC. Pro : résiliable à tout moment en 3 clics, sans engagement. Max et Ultra : prix indicatifs, sous réserve d'ouverture (les plafonds affichés, eux, sont d'ores et déjà définitifs).

### EN

**Page title**: Baillan Pro, Max & Ultra
**Headline**: Find the plan that matches your portfolio
**Subheadline**: Pro is available right now. Max and Ultra are coming soon — sign up to be notified at launch. No commitment, cancel anytime in 3 clicks.
**Toggle**: Monthly / Annual — badge "Save ~2 months"

**Free card**
- Title: Free
- Tagline: Discover Baillan on your first property
- Bullets:
  - Up to 2 properties, 3 tenants, 2 active leases
  - 10 stored documents
  - Rent receipts compliant with French law (6 July 1989)
  - Payments, expenses, dashboard
- CTA: Start for free

**Pro card**
- Title: Pro
- Tagline: For the multi-property landlord, flat-rate — never billed per property
- Bullets:
  - Up to 5 properties, 8 tenants, 5 active leases
  - 50 stored documents
  - 15 saved simulator scenarios
  - Annual charges reconciliation
  - Investment scenario comparison
  - Standard support
- CTA: Upgrade to Pro

**Max card**
- Title: Max
- Badge: Coming soon
- Tagline: For hands-on, day-to-day rental management
- Price shown: from €14.99/month *(indicative)*
- Bullets:
  - Up to 15 properties, 20 tenants, 15 active leases
  - 150 stored documents (up to 25 MiB per file)
  - 30 saved simulator scenarios
  - Automatic payment reminders
  - Reusable listings & multi-portal syndication
  - Priority support
- CTA: Notify me at launch

**Ultra card**
- Title: Ultra
- Badge: Coming soon
- Tagline: For shared ownership structures (SCI, joint ownership), no volume limits
- Price shown: from €24.99/month *(indicative)*
- Bullets:
  - Unlimited properties, tenants, leases, documents and scenarios
  - One-click annual accounting export
  - Up to 3 invited collaborators (accountant, co-owner, managing agent)
  - Documents up to 50 MiB
  - Dedicated support
- CTA: Notify me at launch

**Footer**: Prices include VAT. Pro: cancel anytime in 3 clicks, no commitment. Max and Ultra: indicative pricing, subject to launch (the displayed caps, however, are already final).

> **Note interne (non publiée)** : cibles de délai support envisagées — Pro/Gratuit standard 48-72h, Max prioritaire ~24h ouvrées, Ultra dédié ~12h ouvrées. Non validées côté capacité opérationnelle support à la date de ce document ; ne pas publier de chiffre avant validation (cf. §8).

---

## 6. Migration des abonnés actuels & séquencement de lancement

**Constat** : `SUBSCRIPTIONS_ENABLED = false` en production jusqu'au ~25/08/2026 — aucun abonné payant réel n'existe aujourd'hui en prod.

**Décision de séquencement (inchangée par cette révision)** : à la réouverture, **seul Pro est réellement achetable** (checkout Stripe actif). **Max et Ultra restent en « bientôt disponible »** avec capture d'intérêt via `paid_plan_interest`, taguée par palier (ex. `features: ['tier-max']` / `['tier-ultra']`). Chaque palier haut s'ouvre à la vente **indépendamment**, dès que ses features distinctives assignées sont livrées :
- **Max** ouvre quand FEAT-031 (rappels) et FEAT-051 (annonces & diffusion) sont livrées.
- **Ultra** ouvre quand FEAT-032 (export comptable) et FEAT-034 (multi-utilisateurs) sont livrées.

*Hypothèse retenue, à confirmer au moment du build* : un palier n'ouvre à la vente qu'une fois **l'ensemble** de ses features distinctives assignées livrées (pas dès la première des deux). Si le propriétaire préfère ouvrir dès la première feature prête, ajuster l'ordre de FEAT-056g/h en conséquence — décision mineure, non bloquante pour ce cadrage.

**Motif légal** : ne jamais afficher un bouton de paiement menant vers une fonctionnalité indisponible — risque de pratique commerciale trompeuse (art. L121-2 C. conso.). Le badge « bientôt disponible » + capture d'intérêt (sans aucun chemin de paiement atteignable) est la garde-fou déjà éprouvé sur Pro et repris à l'identique par palier.

### Grandfathering — le point sensible de cette révision

**Pour tout compte déjà sur l'ancien palier unique `paid`** :
- Bascule automatique vers **Pro**, au même prix déjà payé (7,99 €/mois ou 79 €/an selon le cycle en cours), sans nouvelle action ni nouveau consentement de paiement requis.
- **Option retenue : les comptes legacy gardent l'illimité à vie sur les 5 axes de volume** (biens, locataires, baux, documents, scénarios) — un flag dédié (ex. `legacyUnlimited: true`) fait exception aux nouveaux plafonds Pro (5/8/5/50/15) pour ces comptes précis, indéfiniment. Ils restent en tout autre point des comptes Pro standards (mêmes features, même prix, même parcours de résiliation).
- **Option écartée** : reformuler la promesse (« Pro est désormais plafonné, y compris pour vous ») — rejetée car le coût de l'honorer est aujourd'hui quasi nul (`SUBSCRIPTIONS_ENABLED=false`, probablement zéro abonné réel en production à ce jour) alors que le coût de confiance de revenir sur une promesse déjà documentée publiquement (FEAT-044 : « le prix NE monte PAS avec le patrimoine », « biens illimités » ; copy actuel de `/pro`) serait disproportionné si ne serait-ce qu'un seul testeur/bêta avait déjà payé. Techniquement, honorer la promesse ne coûte qu'un flag booléen bypassant les nouveaux plafonds — pas une nouvelle collection, pas un nouveau parcours.
- Communication : email + bandeau in-app annonçant l'arrivée de Max/Ultra comme **upsells optionnels à venir**, jamais comme une dégradation de l'offre actuelle.
- **Garantie de prix** recommandée : prix Pro verrouillé au moins 12 mois pour les comptes grandfathered, même si la grille Pro évolue ensuite pour les nouveaux abonnés.

---

## 7. User stories

### FEAT-056a — Modèle de données 3 paliers payants + migration des abonnés existants

En tant que **product owner**, je veux que le système de paliers distingue Pro/Max/Ultra, avec un statut d'ouverture à la vente indépendant par palier et une exception d'illimité pour les comptes legacy, afin de pouvoir vendre Pro dès maintenant, ouvrir Max/Ultra plus tard, et honorer la promesse faite aux abonnés existants.

**Acceptance criteria** :
- **Given** un compte avec l'ancien palier unique payant **When** la migration s'exécute **Then** le compte devient Pro, au prix qu'il payait déjà, avec le flag `legacyUnlimited` posé, sans interruption d'accès.
- **Given** un nouvel abonné **When** il souscrit à Pro **Then** son palier est déterminé côté serveur par l'événement de paiement, jamais par le client, et il ne porte pas le flag `legacyUnlimited`.
- **Given** le palier Max ou Ultra **non encore ouvert** à la vente **When** `createCheckoutSession` est invoquée avec un `plan` correspondant à ce palier — même en contournant l'UI **Then** l'appel échoue explicitement : aucune session Stripe n'est créée, aucun price ID n'est exposé pour ce palier. *(Garantie testable, pas une intention.)*

**Out of scope** : le détail technique du nouveau schéma d'énumération et du flag d'ouverture par palier (délégué à l'architecte) ; l'application des plafonds de volume eux-mêmes (traitée en 056b) ; l'ouverture effective de Max/Ultra à la vente (traitée en 056g/056h).

**Dependencies** : Collections Firestore `landlords` (`subscriptionTier`). Fonctions `revenueCatWebhook`, `reconcileEntitlements`, `createCheckoutSession`.

**Legal / compliance** : aucune dégradation d'accès sans consentement (RGPD, confiance) ; le grandfathering doit être documenté dans les CGV/CGU ; garde-fou anti-pratique commerciale trompeuse (art. L121-2 C. conso.) sur les paliers non ouverts.

**Priority** : P0 (bloquant pour la réouverture commerciale du 25/08).
**Estimated effort** : M.

---

### FEAT-056b — Quotas de volume différenciés par palier payant (Pro/Max plafonnés, Ultra illimité)

En tant que **product owner**, je veux que les plafonds de biens/locataires/baux/documents/scénarios soient différents pour Pro, Max et Ultra afin que chaque palier payant ait une valeur perceptible dès aujourd'hui, sans dépendre de la livraison de FEAT-031/032/034/051.

**Acceptance criteria** :
- **Given** un compte Pro à son plafond (5 biens / 8 locataires / 5 baux / 50 documents / 15 scénarios) **When** il tente de dépasser l'un de ces plafonds **Then** la création est refusée côté serveur, avec un message qui oriente vers Max.
- **Given** un compte Max à son plafond (15 biens / 20 locataires / 15 baux / 150 documents / 30 scénarios) **When** il tente de le dépasser **Then** la création est refusée côté serveur, avec un message qui oriente vers Ultra.
- **Given** un compte Ultra **When** il crée des biens/locataires/baux/documents/scénarios **Then** aucun plafond commercial ne s'applique (seul le garde-fou technique anti-abus à 200 éléments, déjà en place, reste actif).
- **Given** un compte portant le flag `legacyUnlimited` (grandfathered, 056a) **When** il crée des biens/locataires/baux/documents/scénarios, même au-delà des nouveaux plafonds Pro **Then** aucun plafond commercial ne s'applique, quel que soit le nombre déjà détenu à la migration.
- **Given** le palier Gratuit **When** ces changements sont livrés **Then** ses plafonds (2/3/2/10/3) restent strictement inchangés.

**Out of scope** : le quota de taille par fichier (traité en 056e, axe indépendant) ; l'affichage des plafonds sur `/pro` (traité en 056c).

**Dependencies** : 056a (enum de palier + flag `legacyUnlimited`). Cloud Functions `createProperty`, `createTenant`, `createLease`, `createDocument`, callable de création de scénario simulateur (source de vérité serveur, cf. pattern déjà en place pour `propertyLimit`/`activeTenantLimit`/`activeLeaseLimit`/`documentLimit`/`scenarioLimit`).

**Priority** : P0 — c'est désormais le levier principal qui rend Pro payant et distingue Max, indépendamment des chantiers FEAT-031/032/034/051.
**Estimated effort** : S (extension d'un pattern déjà en place — switch-case binaire free/paid étendu à 4 branches — pas une nouvelle mécanique).

---

### FEAT-056c — Refonte de la page `/pro` en 3 (+1) cartes, avec Max/Ultra en « bientôt disponible »

En tant que **visiteur ou bailleur**, je veux voir les 4 paliers avec leurs accroches, plafonds et bullets, savoir clairement lequel est achetable aujourd'hui, et être prévenu quand Max/Ultra ouvrent, afin de ne jamais tomber sur une promesse de paiement non tenue.

**Acceptance criteria** :
- **Given** la page `/pro` **When** elle se charge **Then** les 4 cartes (Gratuit, Pro, Max, Ultra) s'affichent avec accroche, plafonds de volume réels, bullets et CTA, en FR et en EN selon la langue active.
- **Given** `Env.subscriptionsEnabled == true` (post 25/08) **When** un visiteur consulte `/pro` **Then** la carte Pro affiche un vrai CTA de checkout, tandis que Max et Ultra affichent le badge « Bientôt disponible », un prix marqué indicatif (mais des plafonds de volume déjà définitifs), et un CTA « Me prévenir à l'ouverture ».
- **Given** le toggle mensuel/annuel **When** l'utilisateur bascule sur annuel **Then** les 3 prix payants et le badge d'économie se mettent à jour simultanément, y compris les prix indicatifs de Max/Ultra.
- **Given** un compte déjà sur un palier payant **When** il consulte `/pro` **Then** sa carte actuelle est marquée comme active et son CTA est désactivé.
- **Given** un visiteur clique « Me prévenir à l'ouverture » sur la carte Max **When** il confirme **Then** son intérêt est enregistré dans `paid_plan_interest` avec un tag spécifique à Max (distinct du tag Ultra).
- **Given** Max ou Ultra non ouvert **When** n'importe quel utilisateur tente d'atteindre un flux de paiement pour ce palier, par quelque moyen que ce soit (UI, URL directe, outils dev) **Then** aucun chemin de paiement n'est atteignable — aucune session Stripe ne peut être initiée pour ce palier. *(Garantie testable, pas une intention — complète le contrôle serveur de 056a côté UI.)*
- **Given** un palier Max ou Ultra qui s'ouvre plus tard **When** son flag d'ouverture est activé **Then** sa carte bascule automatiquement du mode « bientôt disponible » vers un vrai CTA de checkout, sans autre changement de code.

**Out of scope** : logique de checkout Stripe pour Max/Ultra eux-mêmes ; refonte visuelle globale hors page `/pro`.

**Dependencies** : 056a, 056b (valeurs de plafonds à afficher). `paid_plan_interest`, `landlordTierProvider`, ARB `lib/l10n/`.

**Legal / compliance** : art. L121-2 C. conso. — pas de bouton de paiement menant à une fonctionnalité indisponible.

**Priority** : P0.
**Estimated effort** : M.

---

### FEAT-056d — Changement de palier en libre-service (upgrade / downgrade / résiliation)

En tant qu'**abonné Pro** (et, plus tard, Max ou Ultra), je veux changer de palier ou résilier depuis `/profile` afin de garder le contrôle de mon abonnement sans contact commercial.

**Acceptance criteria** :
- **Given** un abonné Pro **When** il souhaite résilier **Then** le parcours en 3 clics existant (FEAT-044f) reste inchangé et conforme (art. L215-1-1).
- **Given** Max et Ultra ouverts à la vente (post FEAT-056g/h) **When** un abonné Pro choisit de passer à Max ou Ultra **Then** le changement est immédiat (nouveaux plafonds et nouvelles capacités disponibles tout de suite).
- **Given** Max et Ultra ouverts à la vente **When** un abonné Max ou Ultra choisit de redescendre à un palier inférieur ou de résilier, **et** qu'il détient plus de biens/locataires/baux/documents que le plafond du palier de repli **When** il consulte le récapitulatif **Then** ce dernier signale explicitement les éléments qui passeront en lecture seule (jamais supprimés) à la bascule, en plus de la date de fin d'accès et de l'absence de remboursement au prorata (même politique que FEAT-044f : effet en fin de période payée).

**Out of scope** : gestion des remboursements/avoirs ; palier IAP mobile (hors périmètre web actuel, cf. FEAT-044e) ; tant que Max/Ultra ne sont pas ouverts (§6), seule la résiliation Pro→Gratuit est exerçable.

**Dependencies** : 056a, 056b (règle de lecture seule au downgrade sous plafond, cohérente avec le garde-fou déjà retenu FEAT-044 : « biens excédentaires en lecture seule, jamais supprimés/inaccessibles »). Callable de résiliation existant (FEAT-044f).

**Legal / compliance** : art. L215-1-1 C. conso. — résiliation au moins aussi simple que la souscription, récapitulatif avant confirmation obligatoire.

**Priority** : P1 (la résiliation Pro existe déjà via FEAT-044f ; l'upgrade/downgrade Max/Ultra n'a d'utilité qu'à leur ouverture).
**Estimated effort** : S.

---

### FEAT-056e — Quota de taille de fichier document différencié par palier

En tant que **bailleur Max ou Ultra**, je veux uploader des documents plus volumineux (scans multi-pages, photos) afin de ne pas être bloqué par la limite gratuite/Pro de 10 Mio.

**Acceptance criteria** :
- **Given** un compte Gratuit ou Pro **When** il uploade un document **Then** la limite reste 10 Mio (inchangé).
- **Given** un compte Max **When** il uploade un document ≤ 25 Mio **Then** l'upload réussit.
- **Given** un compte Ultra **When** il uploade un document ≤ 50 Mio **Then** l'upload réussit.
- **Given** un document dépassant la limite de son palier **When** l'upload est tenté **Then** le message d'erreur mentionne le palier supérieur qui débloquerait la taille demandée.

**Out of scope** : quota de stockage agrégé (Go totaux) ; quota de **nombre** de documents (traité en 056b, axe indépendant).

**Dependencies** : Collection `documents`, Storage rules, Cloud Function `createDocument`.

**Priority** : P1.
**Estimated effort** : S.

---

### FEAT-056f — Points d'upsell contextuels Max/Ultra

En tant que **bailleur Pro**, je veux voir où et pourquoi passer à Max ou Ultra directement dans les écrans où j'en ressens le besoin — y compris quand je viens d'atteindre un plafond de volume — afin de comprendre la valeur sans avoir à chercher la page `/pro`.

**Acceptance criteria** :
- **Given** un compte Pro à son plafond de biens (5), locataires (8) ou baux (5) **When** il tente d'en créer un de plus sur `/properties`, `/tenants` ou à la création de bail **Then** l'action est bloquée avec une bannière qui affiche le plafond Max correspondant (15/20/15) et un lien vers `/pro`.
- **Given** un compte Max à son plafond (15/20/15) **When** il tente de le dépasser **Then** la bannière propose Ultra (illimité) au lieu de Max.
- **Given** un bailleur avec au moins un loyer en retard **When** il consulte le dashboard **Then** une bannière propose l'automatisation des relances (Max), avec lien vers `/pro`.
- **Given** un bien sans bail actif (vacant) **When** un bailleur Pro consulte sa fiche **Then** une bannière propose la création d'une annonce (Max), avec lien vers `/pro`.
- **Given** un document dont l'upload échoue pour cause de taille ou de plafond de nombre **When** l'erreur s'affiche **Then** un lien « Passez à Max/Ultra » accompagne le message.
- **Given** `/profile` **When** un bailleur Max le consulte **Then** une entrée « Inviter un collaborateur » verrouillée présente l'argumentaire Ultra.
- **Given** la période de déclaration fiscale (avril-mai) **When** un bailleur Max consulte le dashboard **Then** une bannière propose l'export comptable en un clic (Ultra).
- **Given** n'importe lequel de ces liens **When** il pointe vers un palier non encore ouvert **Then** il atterrit sur la carte « bientôt disponible » correspondante de `/pro` (056c), jamais sur un chemin de paiement.

**Out of scope** : implémentation des features sous-jacentes (rappels, annonces, export, multi-utilisateurs).

**Dependencies** : 056a, 056b, 056c. Dashboard, `/properties`, `/tenants`, fiche bien, `/profile`.

**Priority** : P1.
**Estimated effort** : M.

---

### FEAT-056g — Rattachement de FEAT-051 (annonces) et FEAT-031 (rappels) au palier Max, et ouverture commerciale de Max

En tant que **product owner**, je veux que les annonces & diffusion et les rappels automatiques, une fois construits, soient réservés au palier Max (et supérieur), et que Max s'ouvre à la vente à ce moment-là, afin que ces chantiers déjà planifiés/discovery servent aussi la monétisation.

**Acceptance criteria** :
- **Given** FEAT-031 livré **When** un compte Gratuit ou Pro atteint le déclencheur de relance **Then** aucun email automatique n'est envoyé pour son compte, un upsell Max s'affiche à la place.
- **Given** FEAT-031 livré **When** un compte Max ou Ultra atteint le déclencheur **Then** la relance s'envoie automatiquement.
- **Given** FEAT-051 livré **When** un compte Gratuit ou Pro tente de créer une annonce **Then** l'action est verrouillée avec upsell Max.
- **Given** FEAT-031 ET FEAT-051 livrées **When** le palier Max est marqué ouvert **Then** sa carte `/pro` bascule en checkout réel (056c) et son upgrade/downgrade devient exerçable (056d).

**Out of scope** : le contenu métier de FEAT-031/051 eux-mêmes (`docs/backlog/031-rappels-paiement.md`, `docs/backlog/051-annonces-diffusion-pro.md` — repositionné Pro→Max, note en en-tête).

**Dependencies** : **Bloquée tant que FEAT-031 et FEAT-051 ne sont pas livrées.** Dépend de 056a et 056c.

**Priority** : P1 (conditionnée à FEAT-031 — planifiée mais non chiffrée — et FEAT-051 — discovery uniquement).
**Estimated effort** : S.

---

### FEAT-056h — Rattachement de FEAT-032 (export comptable) et FEAT-034 (multi-utilisateurs) au palier Ultra, et ouverture commerciale d'Ultra

En tant que **product owner**, je veux que l'export comptable et l'accès multi-utilisateurs, une fois construits, soient exclusifs au palier Ultra, et qu'Ultra s'ouvre à la vente à ce moment-là.

**Acceptance criteria** :
- **Given** FEAT-032 livré **When** un compte Gratuit, Pro ou Max tente l'export comptable **Then** l'action est verrouillée avec upsell Ultra.
- **Given** FEAT-034 livré **When** un compte Max tente d'inviter un collaborateur **Then** l'action est verrouillée avec upsell Ultra.
- **Given** FEAT-034 livré **When** un compte Ultra invite un collaborateur **Then** il peut en inviter jusqu'à 3.
- **Given** FEAT-032 ET FEAT-034 livrées **When** le palier Ultra est marqué ouvert **Then** sa carte `/pro` bascule en checkout réel (056c) et son upgrade/downgrade devient exerçable (056d).

**Out of scope** : le contenu métier de FEAT-032/034 eux-mêmes.

**Dependencies** : **Bloquée tant que FEAT-032 et FEAT-034 ne sont pas livrées.** Dépend de 056a et 056c.

**Priority** : P2 (conditionnée à FEAT-032 — format encore à trancher — et FEAT-034 — idée RICE rang 7, non spec'd).
**Estimated effort** : S.

---

## 8. Risques & questions ouvertes (arbitrage propriétaire)

1. **Noms de paliers** : « Max » et « Ultra » sont-ils validés côté marque (pas de recherche de conflit de marque effectuée dans ce document) ?
2. **Offre de lancement Max/Ultra** : faut-il une remise limitée dans le temps pour amorcer l'adoption de chaque palier haut au moment de son ouverture (cf. §4), sur le modèle de l'offre Fondateur déjà envisagée pour Pro ?
3. **Plafond « illimité » d'Ultra** : le plafond technique de 200 biens (garde-fou existant, non commercial) suffit-il comme fair-use pour Ultra, ou faut-il un plafond explicite et communiqué en cas d'usage réellement massif (petit professionnel) ?
4. **Plafonds de volume Pro/Max non validés par de la donnée réelle** : la grille resserrée (§2) est calibrée sur des repères qualitatifs faute d'abonnés existants — à recalibrer dès que des données d'usage réelles sont disponibles (probable premier ajustement post-lancement, pas un blocage).

---

## 9. Entrée suggérée pour `docs/state/FEATURES.md`

*(à ajouter par l'utilisateur ou `state-keeper` — non modifié ici)*

| FEAT-ID | Nom court | Statut | Domaine | Réf commit/PR |
|---|---|---|---|---|
| FEAT-056 | Abonnements Pro/Max/Ultra (paliers + quotas différenciés, Pro seul achetable au lancement) | 📋 planned | account | docs/backlog/056-abonnements-pro-max-ultra.md |
