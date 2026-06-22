import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Page de politique de confidentialité — conforme RGPD.
///
/// Accessible sans login (route `/privacy` publique).
/// Référencée depuis [LoginPage] et [ProfilePage].
///
/// Dernière mise à jour : juin 2026
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Politique de confidentialité'),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
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
          'Version 1.0 — Dernière mise à jour : juin 2026',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),

        // 1. Responsable du traitement
        const _Section(
          title: '1. Responsable du traitement',
          body:
              'EasyRent est un outil B2B de gestion locative. Chaque bailleur '
              'utilisant EasyRent est responsable du traitement des données '
              'personnelles de ses locataires en qualité de responsable de '
              'traitement au sens du RGPD (art. 4§7).\n\n'
              'Pour toute question relative à vos données personnelles, '
              'contactez le bailleur titulaire du compte EasyRent dont vous '
              'dépendez. Ses coordonnées vous ont été fournies à la signature '
              'du bail.',
        ),

        // 2. Données collectées
        const _Section(
          title: '2. Données collectées',
          body:
              'Les catégories de données suivantes sont traitées via EasyRent :\n\n'
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
              '(nom du fichier, taille, date d\'upload).',
        ),

        // 3. Base légale
        const _Section(
          title: '3. Base légale (RGPD art. 6.1.b)',
          body:
              'Les traitements effectués via EasyRent sont fondés sur l\'exécution '
              'du contrat de bail (art. 6.1.b du RGPD) : les données des locataires '
              'sont nécessaires à la gestion du contrat de location, au calcul des '
              'loyers et charges, et à la délivrance des quittances.\n\n'
              'L\'authentification du bailleur est fondée sur son intérêt légitime '
              'à accéder à son espace de gestion locative (art. 6.1.f).',
        ),

        // 4. Sous-traitants
        const _Section(
          title: '4. Sous-traitants et transferts',
          body:
              'Les données sont traitées par les sous-traitants suivants, tous '
              'disposant d\'une politique DPA conforme au RGPD :\n\n'
              '• Supabase (Supabase Inc., États-Unis) — hébergement de la base de '
              'données, authentification, stockage des fichiers. Les instances de '
              'données sont hébergées dans la région EU (Francfort). DPA disponible '
              'sur supabase.com/legal/dpa.\n\n'
              '• Firebase Hosting (Google LLC, États-Unis) — hébergement statique de '
              'l\'application web. Firebase Hosting ne stocke aucune donnée personnelle '
              '(l\'application communique directement avec Supabase pour les données). '
              'DPA disponible sur firebase.google.com/terms/data-processing-terms.\n\n'
              'Le partage des quittances utilise l\'API native du navigateur '
              '(Web Share API). Aucune donnée du locataire ne transite par un '
              'service tiers lors de cette opération.\n\n'
              'Aucun autre transfert hors UE non mentionné ci-dessus n\'est effectué.',
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
              '• Fichiers stockés : conservés dans un bucket privé Supabase Storage. '
              'L\'accès se fait uniquement via des URL signées valables 5 minutes.\n\n'
              '• Autres données (paiements, profil locataire) : conservées tant que '
              'le compte bailleur est actif, puis supprimées sur demande dans les '
              'délais légaux.\n\n'
              '• Compte bailleur : conservé jusqu\'à la demande de suppression ou '
              'l\'inactivité prolongée (>2 ans), sous réserve des obligations légales.',
        ),

        // 6. Sécurité
        const _Section(
          title: '6. Sécurité',
          body:
              'Les mesures de sécurité suivantes sont mises en place :\n\n'
              '• Contrôle d\'accès Row Level Security (RLS) Postgres : chaque bailleur '
              'ne peut lire et modifier que ses propres données.\n\n'
              '• Authentification sans mot de passe : magic link PKCE envoyé par email.\n\n'
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
              'EasyRent n\'utilise aucun cookie tiers de tracking ou d\'analyse '
              'comportementale.\n\n'
              'Seuls les cookies fonctionnels suivants sont utilisés :\n\n'
              '• Session d\'authentification Supabase (stockée en localStorage) — '
              'nécessaire au maintien de la connexion.\n\n'
              '• Préférences d\'interface (thème, dismiss du prompt d\'installation) — '
              'stockées en localStorage, non transmises à des tiers.\n\n'
              'Aucun outil d\'analytics tiers (Google Analytics, Mixpanel, etc.) '
              'n\'est actuellement intégré.',
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
              '• Art. 17 — Droit à l\'effacement ("droit à l\'oubli") : demander '
              'la suppression, sous réserve des obligations légales de conservation.\n\n'
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
          'EasyRent — Gestion locative simplifiée',
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
