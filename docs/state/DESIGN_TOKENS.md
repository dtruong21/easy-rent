# Design Tokens — Baillan.

> **Source de vérité** : [`config/theme_tokens.json`](../../config/theme_tokens.json).
> Les constantes de [`app_theme.dart`](../../lib/core/theme/app_theme.dart) et les
> variables CSS de la vitrine en sont deux miroirs générés
> (`dart run tool/gen_theme_tokens.dart`, garde-fou `scripts/check-theme-tokens.sh`).
> Les **alias sémantiques** (`acquitte`, `echu`, `consigne`, `archive`) restent
> écrits à la main dans `app_theme.dart` : ce sont des indirections métier, pas
> des couleurs.
> **Dernière mise à jour** : 2026-09-05 (source canonique partagée avec la vitrine).

Ce fichier **mappe chaque jeton de couleur à un usage métier précis**. Sans cette table, les états se contaminent au fil des features et la posture de marque se dilue.

Règle d'or : **un dev qui code un état métier doit utiliser l'alias sémantique** (`AppTheme.acquitte`), pas le jeton technique (`AppTheme.sealGreen`), et JAMAIS une couleur en dur (`Colors.green`, `Color(0xFF2E5339)`).

---

## 1 — Palette de base (FEAT-020)

| Jeton | Hex | Rôle | Ne pas utiliser pour |
|---|---|---|---|
| `paper` | `#F7F4ED` | Surface principale (scaffold background) | — |
| `paperDeep` | `#EFE9DA` | Surface containers (cards, paperasse) | — |
| `cream` | `#FCFAF5` | Surface low / inputs / panneau soulevé | Texte sur paper (trop proche) |
| `ink` | `#1B1A17` | Texte primaire, dark mode ground | — |
| `inkSurface` | `#2A2823` | Dark mode containers | — |
| `inkMuted` | `#6B665D` | Texte secondaire (captions, hints) | Disabled (utiliser `stone`) |
| `rule` | `#E8E2D3` | Divider, bordure de card normale | **Jamais pour porter du texte** (1.18:1) |
| `olive` | `#3F4A2A` | Primary (boutons, focus ring, accents) | États (utiliser `acquitte` etc.) |
| `oliveMid` | `#5E6A45` | Tertiary | — |
| `oliveSoft` | `#B5B89D` | Primary container, dark mode primary | Texte sur paper (insuffisant) |
| `oxblood` | `#9A3B2F` | **Erreur uniquement** (quittance annulée, retard >30j) | Charges débitrices normales (utiliser `amountNegative`) |

## 2 — Jetons d'extension (brand polish, 30 juin 2026)

8 jetons ajoutés pour combler les trous sémantiques.

| Jeton | Hex | Contraste sur paper | Usage |
|---|---|---|---|
| `sealGreen` | `#2E5339` | 7.92:1 (AAA) | États terminés positifs |
| `ochre` | `#7E5612` | 5.92:1 (AA) | Échéance imminente, brouillon |
| `indigoInk` | `#2A3656` | 10.86:1 (AAA) | Info neutre, mention légale |
| `kraft` | `#E4D9BD` | n/a (surface) | Zone "documents archivés" |
| `stone` | `#A8A39A` | 2.28:1 (intentionnel) | Disabled, placeholder |
| `oliveDeep` | `#34401F` | 10.07:1 (AAA) | Hover/pressed du primary |
| `ruleStrong` | `#C9C1AB` | n/a (border) | Card sélectionnée, focus outline |
| `amountNegative` | `#6E3A1F` | >8.5:1 (AAA) | Montants débiteurs (charges) |

## 3 — Alias sémantiques métier

Ces alias **portent la voix éditoriale Baillan jusqu'au code**. Préférer ces noms quand l'usage est explicitement métier.

| Alias | Pointe vers | Vocabulaire produit | Cas d'usage |
|---|---|---|---|
| `acquitte` | `sealGreen` | "Acquitté" | Quittance émise et payée ; bail signé ; document validé ; locataire à jour |
| `echu` | `ochre` | "Échu" | Échéance dans <7j ; quittance non encore émise mais due ; brouillon non signé |
| `consigne` | `indigoInk` | "Consigné" | Mention loi 1989 mise en avant ; RGPD ; document archivé neutre |
| `archive` | `kraft` | "Bailliage tenu" | Surface des sections historique, anciennes quittances, archives baux |

## 4 — Table d'usage légal / métier précise

À consulter avant d'introduire une nouvelle couleur dans un widget. Si l'intention ne figure pas dans cette table, **demander avant de coder**.

| Intention métier | Token | Notes |
|---|---|---|
| Quittance émise + payée | `acquitte` | État final positif. Pas de bouton "Action" sur cet état. |
| Quittance émise non payée | (aucun token spécifique) | Utiliser `inkMuted` pour le texte secondaire ; passer en `echu` si <7j de l'échéance |
| Échéance dans <7j | `echu` | Avertissement modéré, jamais alarmiste |
| Retard de paiement <30j | `echu` | Toujours échu, pas encore critique |
| Retard de paiement >30j | `oxblood` | Critique — action attendue du bailleur |
| Quittance annulée | `oxblood` | État définitif d'erreur métier |
| Bail signé électroniquement | `acquitte` | Document opposable |
| Brouillon de quittance | `echu` | Pas signé = pas valide |
| Mention "Loi du 6 juillet 1989" | `consigne` | Mise en avant légale obligatoire sur PDF |
| Notification système neutre (export prêt, sync OK) | `consigne` | Pas un succès, pas une alerte |
| Confirmation d'action utilisateur (snackbar "Quittance envoyée") | `acquitte` | Feedback positif d'action |
| Erreur réseau / erreur backend | `oxblood` | Erreur technique (différent de l'erreur métier) |
| Section "Historique des quittances" | `archive` | Surface, pas un texte |
| Section "Documents conservés" | `archive` | Surface |
| Champ formulaire désactivé | `stone` | Pas la même couleur qu'un caption |
| Bouton primary en hover | `oliveDeep` | Pas un opacity overlay |
| Bouton primary en pressed | `oliveDeep` + déplacement 1px | Métaphore "plume qui appuie" |
| Card focus / sélection (sans être primary) | bordure 1px `ruleStrong` | Pas d'olive — gardé pour le primary |
| Charge mensuelle (sortie comptable) | `amountNegative` | Pas oxblood — c'est une opération normale |
| Encaissement (entrée comptable) | `acquitte` ou `ink` | Selon le contexte (état vs ligne neutre) |

## 5 — Anti-patterns

À ne pas faire — repérables en code review :

```dart
// ❌ Couleur en dur
Container(color: const Color(0xFF15803D))

// ❌ Material générique
Icon(Icons.check, color: Colors.green)

// ❌ Token primary réutilisé comme état
Container(color: AppTheme.olive)  // pour signaler "payé"

// ❌ inkMuted utilisé comme disabled
TextField(enabled: false, style: TextStyle(color: AppTheme.inkMuted))

// ✅ Alias sémantique
Container(color: AppTheme.acquitte)
TextField(enabled: false, style: TextStyle(color: AppTheme.stone))
```

## 6 — TODO follow-ups

Pas inclus dans cette PR (scope volontairement réduit) :

- [ ] Migrer `lib/core/ui/theme/app_colors.dart` (StatusPillTone) vers ces alias — aujourd'hui les pills utilisent encore une palette Tailwind héritée d'EasyRent.
- [ ] Câbler `oliveDeep` comme hover/pressed du `FilledButtonTheme` dans `AppTheme._build()`.
- [ ] Câbler `ruleStrong` dans le focus ring des `Card` et `OutlinedButton`.
- [ ] Self-host IBM Plex Sans (woff2) pour fixer le body en non-système (cf. dossier brand polish §III).
- [ ] Générer les vraies icônes PNG (16/32/192/512/1024) depuis un SVG main propre — aujourd'hui le favicon est un SVG inline data-URI.
