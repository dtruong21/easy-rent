import 'package:flutter/material.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';

/// Page de politique de confidentialité — conforme RGPD.
///
/// Accessible sans login (route `/privacy` publique).
/// Référencée depuis [LoginPage] et [ProfilePage].
///
/// Dernière mise à jour : octobre 2026 (v1.4 — avis in-app et date de la
/// dernière sollicitation de notation stockée sur l'appareil, FEAT-060 ;
/// v1.3 — précisions sur les données de tiers (locataires) et le devoir
/// d'information du bailleur, + rapport d'incident Crashlytics mobile en
/// opt-in ; v1.2 — suppression de compte in-app et rétention des quittances,
/// FEAT-045 ; v1.1 — collecte demandes de support, FEAT-025)
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Politique de confidentialité',
        fallbackRoute: '/',
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: _PrivacyContent(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu
// ---------------------------------------------------------------------------

class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Politique de confidentialité',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Version 1.4 — Dernière mise à jour : octobre 2026',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),

        // 1. Responsable du traitement
        const _Section(
          title: '1. Responsable du traitement',
          body:
              'Baillan. est un outil B2B de gestion locative. Chaque bailleur '
              'utilisant Baillan. est responsable du traitement des données '
              'personnelles de ses locataires en qualité de responsable de '
              'traitement au sens du RGPD (art. 4§7).\n\n'
              'Pour toute question relative à vos données personnelles, '
              'contactez le bailleur titulaire du compte Baillan. dont vous '
              'dépendez. Ses coordonnées vous ont été fournies à la signature '
              'du bail.\n\n'
              'Données de tiers (locataires) : les données des locataires sont '
              'saisies par le bailleur, seul responsable de leur traitement. '
              'À ce titre, le bailleur s\'engage à informer ses locataires de '
              'la collecte et du traitement de leurs données via Baillan. '
              '(finalités, base légale, durée de conservation et droits — '
              'RGPD art. 13 et 14), notamment lors de la signature du bail. '
              'Baillan. et ses sous-traitants techniques (Google / Firebase, '
              'cf. §4) agissent uniquement sur instruction du bailleur et ne '
              'réutilisent jamais les données des locataires à d\'autres fins.',
        ),

        // 2. Données collectées
        const _Section(
          title: '2. Données collectées',
          body:
              'Les catégories de données suivantes sont traitées via Baillan. :\n\n'
              '• Compte bailleur : adresse email (authentification), nom complet, '
              'téléphone, adresse postale.\n\n'
              '• Locataires : prénom, nom, adresse email, numéro de téléphone.\n\n'
              '• Baux : montant du loyer et des charges, dates de début et de fin, '
              'statut du contrat, bien immobilier et locataire associés.\n\n'
              '• Paiements : montant, date de paiement, mode de règlement (virement, '
              'chèque, espèces, prélèvement), notes éventuelles.\n\n'
              '• Quittances de loyer : documents PDF générés (contenant nom, '
              'adresse, montants, période — mentions obligatoires loi n° 89-462 '
              'du 6 juillet 1989, art. 21).\n\n'
              '• Documents : fichiers uploadés par le bailleur (baux signés, états '
              'des lieux, attestations d\'assurance, etc.) et leurs métadonnées '
              '(nom du fichier, taille, date d\'upload).\n\n'
              '• Demandes de support : sujet et message que vous nous adressez '
              'via le formulaire « Nous contacter », associés à votre adresse '
              'email, un identifiant technique de compte, la version de '
              'l\'application et l\'environnement — utilisés uniquement pour '
              'traiter votre demande.\n\n'
              '• Avis : note de 1 à 5, commentaire facultatif, plateforme '
              '(web, iOS ou Android), version de l\'application, adresse '
              'email et identifiant technique de compte, recueillis via le '
              'formulaire « Donner mon avis » — utilisés pour améliorer le '
              'service.\n\n'
              '• Rapport d\'incident (applications mobiles iOS/Android '
              'uniquement) : en cas de plantage, et UNIQUEMENT si vous avez '
              'activé cette option — désactivée par défaut, dans Profil → '
              'Confidentialité — des données de diagnostic sont collectées : '
              'type d\'appareil, version du système et de l\'application, état '
              'de l\'application et pile d\'appel du plantage. Ces données ne '
              'contiennent pas le contenu de vos biens, baux ou locataires. Le '
              'site web n\'est pas concerné.',
        ),

        // 3. Base légale
        const _Section(
          title: '3. Base légale (RGPD art. 6.1.b)',
          body:
              'Les traitements effectués via Baillan. sont fondés sur l\'exécution '
              'du contrat de bail (art. 6.1.b du RGPD) : les données des locataires '
              'sont nécessaires à la gestion du contrat de location, au calcul des '
              'loyers et charges, et à la délivrance des quittances.\n\n'
              'L\'authentification du bailleur est fondée sur son intérêt légitime '
              'à accéder à son espace de gestion locative (art. 6.1.f).\n\n'
              'Le traitement des demandes de support (formulaire « Nous '
              'contacter ») est fondé sur l\'intérêt légitime à répondre aux '
              'utilisateurs du service (art. 6.1.f).\n\n'
              'Le traitement des avis (formulaire « Donner mon avis ») est '
              'fondé sur l\'intérêt légitime à améliorer le service '
              '(art. 6.1.f).',
        ),

        // 4. Sous-traitants
        const _Section(
          title: '4. Sous-traitants et transferts',
          body:
              'Les données sont traitées par les sous-traitants suivants, tous '
              'disposant d\'une politique DPA conforme au RGPD :\n\n'
              '• Google LLC / Google Ireland Ltd via Firebase (Cloud Firestore, '
              'Firebase Authentication, Cloud Functions, Cloud Storage, '
              'Firebase Hosting, et — sur les applications mobiles avec votre '
              'opt-in — Firebase Crashlytics) — hébergement de la base de '
              'données, authentification, exécution serveur, stockage de '
              'fichiers, hébergement web et, le cas échéant, rapport '
              'd\'incident. Les données sont localisées dans la région '
              'multi-region eur3 (Belgique + Pays-Bas + Finlande) pour '
              'Firestore et europe-west3 (Francfort) pour Cloud Storage. DPA '
              'disponible sur firebase.google.com/terms/data-processing-terms.\n\n'
              'Le partage des quittances utilise l\'API native du navigateur '
              '(Web Share API). Aucune donnée du locataire ne transite par un '
              'service tiers lors de cette opération.\n\n'
              'Transferts hors UE : les données peuvent transiter par '
              'l\'infrastructure Google aux États-Unis dans le cadre des '
              'opérations techniques de Google (clauses contractuelles types '
              'CCT 2021 + DPF). Aucun autre transfert n\'est effectué.',
        ),

        // 5. Durée de conservation
        const _Section(
          title: '5. Durée de conservation',
          body:
              'Les données sont conservées selon les règles suivantes :\n\n'
              '• Quittances de loyer, baux signés et états des lieux : 5 ans à compter '
              'de la fin du bail (loi n° 89-462 du 6 juillet 1989, art. 7g ; '
              'art. 2224 Code civil). Un mécanisme de verrouillage légal (legal_hold) '
              'empêche la suppression prématurée de ces documents.\n\n'
              '• Fichiers stockés : conservés dans un bucket privé Firebase '
              'Cloud Storage. L\'accès se fait uniquement via des URL signées '
              'valables 5 minutes générées par une Cloud Function après '
              'vérification d\'identité.\n\n'
              '• Autres données (paiements, profil locataire) : conservées tant que '
              'le compte bailleur est actif, puis supprimées sur demande dans les '
              'délais légaux.\n\n'
              '• Compte bailleur : conservé jusqu\'à la demande de suppression ou '
              'l\'inactivité prolongée (>2 ans), sous réserve des obligations légales.\n\n'
              '• Session anonyme (mode démo, avant création de compte) : les données '
              'liées à une session anonyme (scénarios de simulation d\'investissement, '
              'préférences éphémères) sont conservées 14 jours glissants à compter '
              'de la dernière activité, puis supprimées automatiquement par un '
              'traitement quotidien (Cloud Function planifiée). Aucune donnée '
              'nominative n\'est collectée pendant cette phase — seul un identifiant '
              'technique Firebase Anonymous UID permet de rattacher les scénarios '
              'à la session en cours. La création d\'un compte pendant la période '
              'de démo préserve les scénarios enregistrés et fait basculer le '
              'compte en régime standard de conservation.\n\n'
              '• Demandes de support : conservées le temps du traitement de la '
              'demande, puis au plus 12 mois après le dernier échange (suivi '
              'qualité), avant suppression.\n\n'
              '• Avis : mêmes règles de conservation que les demandes de '
              'support (ci-dessus) ; ils sont supprimés avec le compte.\n\n'
              '• Suppression de compte : la suppression (accessible dans '
              'l\'application via Profil → « Supprimer mon compte », ou via la '
              'page publique /delete-account) efface immédiatement et '
              'définitivement l\'ensemble des données du compte — biens, '
              'locataires, baux, paiements, documents et fichiers stockés, '
              'dépenses, simulations, demandes de support et avis, profil et '
              'compte de connexion (y compris la révocation du jeton « Se connecter '
              'avec Apple »). Seules les quittances de loyer émises sont '
              'conservées 5 ans à titre de preuve (loi n° 89-462 du 6 juillet '
              '1989 ; art. 2224 du Code civil), sous forme archivée '
              'inaccessible, puis supprimées à l\'échéance.',
        ),

        // 6. Sécurité
        const _Section(
          title: '6. Sécurité',
          body:
              'Les mesures de sécurité suivantes sont mises en place :\n\n'
              '• Contrôle d\'accès Firestore Security Rules + Storage Rules : '
              'chaque bailleur ne peut lire et modifier que ses propres données '
              '(`request.auth.uid == landlordId`). Les mutations sensibles '
              '(receipts, cross-entity) passent exclusivement par des Callable '
              'Cloud Functions auditées.\n\n'
              '• Authentification Firebase Authentication par email et mot de '
              'passe. Les credentials sont stockés côté Google selon les '
              'standards Identity Platform (scrypt). Aucun mot de passe en '
              'clair n\'est jamais journalisé ou stocké côté client. '
              'Communication HTTPS exclusivement.\n\n'
              '• Communications HTTPS exclusivement (HSTS activé, 1 an).\n\n'
              '• Fichiers stockés dans un bucket privé, accessibles uniquement via '
              'URL signées à durée de vie limitée (5 minutes).\n\n'
              '• Headers de sécurité HTTP : CSP stricte, X-Frame-Options DENY, '
              'X-Content-Type-Options nosniff, Permissions-Policy restrictive.',
        ),

        // 7. Cookies
        const _Section(
          title: '7. Cookies et traceurs',
          body:
              'Baillan. n\'utilise aucun cookie tiers de tracking ou d\'analyse '
              'comportementale.\n\n'
              'Seuls les cookies fonctionnels suivants sont utilisés :\n\n'
              '• Session d\'authentification Firebase (stockée dans '
              'IndexedDB / cookies first-party) — nécessaire au maintien '
              'de la connexion.\n\n'
              '• Préférences d\'interface (thème, dismiss du prompt d\'installation) — '
              'stockées en localStorage, non transmises à des tiers.\n\n'
              '• Date de la dernière sollicitation d\'avis '
              '(`review_solicited_at`) — stockée uniquement sur votre appareil '
              '(localStorage sur le web, préférences de l\'application sur '
              'mobile), non transmise, afin de ne pas vous solliciter plus '
              'd\'une fois tous les 120 jours.\n\n'
              'Aucun outil d\'analytics comportemental ou publicitaire (Google '
              'Analytics, Mixpanel, etc.) n\'est intégré. Le seul outil tiers de '
              'diagnostic est Firebase Crashlytics, limité aux applications '
              'mobiles iOS/Android et activé uniquement après opt-in explicite '
              '(cf. §2) — le site web n\'en fait pas usage.',
        ),

        // 8. Droits
        const _Section(
          title: '8. Vos droits (RGPD art. 15–21)',
          body:
              'Conformément au RGPD, vous disposez des droits suivants :\n\n'
              '• Art. 15 — Droit d\'accès : obtenir confirmation du traitement '
              'et une copie de vos données.\n\n'
              '• Art. 16 — Droit de rectification : faire corriger des données '
              'inexactes ou incomplètes.\n\n'
              '• Art. 17 — Droit à l\'effacement ("droit à l\'oubli") : le '
              'bailleur peut supprimer son compte et l\'ensemble de ses données '
              'directement dans l\'application (Profil → « Supprimer mon '
              'compte ») ou depuis la page publique /delete-account, sous '
              'réserve des obligations légales de conservation (quittances, '
              'cf. §5).\n\n'
              '• Art. 18 — Droit à la limitation : demander la suspension temporaire '
              'du traitement.\n\n'
              '• Art. 20 — Droit à la portabilité : recevoir vos données dans un '
              'format structuré (CSV, JSON).\n\n'
              '• Art. 21 — Droit d\'opposition : s\'opposer à un traitement fondé '
              'sur l\'intérêt légitime.\n\n'
              'Pour exercer ces droits, contactez le bailleur titulaire de votre '
              'dossier (les coordonnées vous ont été fournies à la signature du '
              'bail). Vous pouvez également introduire une réclamation auprès de '
              'la CNIL (www.cnil.fr).',
        ),

        // 9. Mise à jour
        const _Section(
          title: '9. Mise à jour de cette politique',
          body:
              'Cette politique peut être mise à jour à tout moment. La date de '
              'dernière modification est indiquée en haut de cette page. '
              'En cas de modification substantielle, les utilisateurs seront '
              'informés par email ou via l\'application.',
        ),

        const SizedBox(height: 32),
        Text(
          'Baillan. — Gestion locative simplifiée',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section réutilisable
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
