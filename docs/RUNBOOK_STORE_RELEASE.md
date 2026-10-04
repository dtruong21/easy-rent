# Runbook — Release stores Baillan (à dérouler sur le Mac de release, autre compte OK)

> Écrit le 2026-07-07, mis à jour le 2026-10-04 (Flutter, Crashlytics, compte
> démo à email vérifié). À dérouler sur le **Mac de release**, potentiellement
> avec **d'autres comptes** que celui de la session courante.
> Autonome : tout le contexte nécessaire est ici ou dans les docs liées.
> Audit et statuts : [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) ·
> Formulaires : [`STORE_FORMS.md`](STORE_FORMS.md) ·
> Setup machine général : [`HANDOFF.md`](HANDOFF.md).

## 0. Qui fait quoi avec quel compte (à lire d'abord)

Trois « comptes » distincts — ne pas les confondre :

| Compte | Sert à | État |
|---|---|---|
| **Compte Google Firebase** (accès projet `easy-rent-54cd4`) | Console Firebase, CLI `firebase` | ✅ Configuré sur le Mac de release en juillet (à revérifier avec `firebase projects:list`). **Rien à refaire** : apps enregistrées, SHA debug + release déclarées. Si vous utilisez un AUTRE compte Google ici, il faut d'abord lui donner accès IAM au projet |
| **Compte développeur Google Play** (25 $ une fois) | Play Console : publier l'app | ⏳ À créer/choisir — décision **perso vs organisation** (§2) |
| **Apple ID développeur** (Apple Developer Program, 99 $/an) | App Store Connect + signing Xcode | ⏳ À créer/choisir (§2) |

Le compte Play et l'Apple ID sont **indépendants** du compte Google Firebase :
utiliser un autre compte pour les stores ne change rien au backend.

**Si vous travaillez depuis une autre session macOS** (autre utilisateur du
Mac) : la clé d'upload Android est dans le home du compte propriétaire —
`~/keystores/baillan/` de ce compte (`upload-keystore.jks` +
`key.properties`, chmod 600). La copier dans un emplacement accessible et
adapter `storeFile=` dans `key.properties`.

## 1. ⚠️ Avant tout : sauvegarder la clé d'upload (2 min)

Copier dans le gestionnaire de mots de passe :
`~/keystores/baillan/upload-keystore.jks` **et**
`~/keystores/baillan/key.properties` (contient le mot de
passe). Machine morte sans backup = clé perdue (resettable via support Play,
mais long).

## 2. Comptes + DSA trader (décisions puis paperasse)

1. **Play Console** — décision structurante :
   - Compte **organisation** (recommandé) : exige un **D-U-N-S** (gratuit,
     délai quelques jours — le demander tôt) et une structure (le statut
     micro-entrepreneur/SIREN suffit) → **exempte du test fermé 12 testeurs
     × 14 jours** et évite d'afficher une adresse personnelle (DSA).
   - Compte **personnel** : plus rapide, mais test fermé obligatoire
     (~3-4 semaines de calendrier) + coordonnées perso publiées (DSA).
2. **Apple Developer Program** : souscrire avec l'Apple ID choisi (99 $/an).
   La vérification peut prendre 24-48 h.
3. **DSA trader** (les deux consoles, bloquant UE) : déclarer le statut
   trader — adresse (boîte postale acceptée par Apple avec justificatif),
   email et téléphone **dédiés** (ils seront publics sur les fiches),
   vérifications 2FA email + téléphone + justificatifs.
   Détail : [`STORE_COMPLIANCE.md`](STORE_COMPLIANCE.md) §3.

## 3. Signing iOS (après le compte Apple, ~30 min)

Sur le Mac de release (Xcode à jour — 26.6 utilisé en juillet) :

1. Xcode → Settings → Accounts → **ajouter l'Apple ID développeur**.
2. Ouvrir `ios/Runner.xcworkspace` → target Runner → *Signing &
   Capabilities* : Team = la nouvelle team, « Automatically manage
   signing » (bundle ID `com.daki.baillan` déjà posé).
3. **+ Capability « Sign in with Apple »** → **committer** le
   `Runner.entitlements` généré (bloquant pour l'auth Apple sur device).
4. App Store Connect → créer l'app sur le bundle ID `com.daki.baillan`.
5. Build (Flutter **3.44.6**, version épinglée en CI — `flutter --version` doit
   concorder) : `flutter build ipa`
   → upload via Xcode Organizer ou Transporter.
6. Firebase : **rien à faire** côté iOS (pas de SHA ; provider Apple actif).

## 4. Compte démo + formulaires consoles (~1 h)

1. Créer le **compte démo review** et le peupler :
   recette exacte dans [`STORE_FORMS.md`](STORE_FORMS.md) §3.
2. Dérouler les formulaires **en copiant les réponses préparées** :
   - Play Console → Contenu de l'app : [`STORE_FORMS.md`](STORE_FORMS.md) §1
     (privacy policy, ads, App access + texte anglais, IARC, audience 18+,
     financial features = aucune, Data safety complet).
   - App Store Connect : [`STORE_FORMS.md`](STORE_FORMS.md) §2
     (privacy labels, questionnaire d'âge, App Review Information).
3. Prérequis : FEAT-045 ✅ livrée (page `https://easy-rent-54cd4.web.app/delete-account`
   active — l'URL est déclarée dans Data safety). Vérifier son état avant.
4. **Rapport de plantage (Crashlytics, mobile, opt-in)** : à déclarer dans
   Data safety (Play) et App Privacy (Apple) — lignes prêtes dans
   [`STORE_FORMS.md`](STORE_FORMS.md) §1.8 et §2.1. Le compte démo doit avoir un
   **email vérifié** (§3 de `STORE_FORMS.md`).

## 5. Android : produire et uploader l'AAB

```bash
cd <repo>                                  # branche develop/main à jour
cp ~/keystores/baillan/key.properties android/    # du compte propriétaire de la clé
flutter --version                          # doit afficher 3.44.6 (épinglé en CI)
flutter pub get && dart run build_runner build --delete-conflicting-outputs
flutter build appbundle --release          # → build/app/outputs/bundle/release/app-release.aab
```

- Sans `android/key.properties`, le build retombe **silencieusement** en
  signature debug (fallback CI voulu) → Play refusera l'AAB. Vérifier :
  `keytool -printcert -jarfile app-release.aab` doit afficher `CN=Baillan`.
- À l'upload : activer **Play App Signing** (notre clé = clé d'upload),
  surveiller l'avertissement **16 KB pages** (vérifié OK au 2026-09-30, cf. `STORE_COMPLIANCE.md` §1.2 ; à reconfirmer sur l'AAB release).
- Compte **perso** : passer par *Closed testing* (12 testeurs × 14 jours)
  puis demande d'accès production. Compte **organisation** : production
  directe possible.

## 6. iOS : TestFlight

Après §3.5 : dans App Store Connect, surveiller les emails
**ITMS-91053 / ITMS-91061** (privacy manifests — le nôtre est en place,
les pods Firebase récents aussi). Tester sur device via TestFlight,
notamment : login Google + Apple, génération + partage de quittance
(share sheet), suppression de compte (FEAT-045).

## 7. Déjà fait — ne pas refaire

- Apps Firebase Android/iOS enregistrées, `firebase_options.dart` 3
  plateformes, SHA **debug + release** déclarées.
- `PrivacyInfo.xcprivacy` (embarqué, vérifié) + `ITSAppUsesNonExemptEncryption=false`.
- Signing Android : keystore + Gradle + AAB signé validé + smoke test
  release sur émulateur.
- Icônes + splash natifs Baillan : ✅ faits (2026-07-07) et validés sur
  émulateur/simulateur — icônes web re-brandées au passage.
