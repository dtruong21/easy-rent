import 'package:flutter/material.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';

/// Page `/faq` — questions fréquentes sur Baillan, organisées par thèmes.
///
/// Publique (hors shell, comme `/privacy`) : consultable avant de créer un
/// compte, par les sessions d'essai anonymes, et référençable depuis les
/// fiches stores. Également accessible via Profil → Aide → FAQ et le pied
/// de la landing.
///
/// Contenu statique embarqué (pas de collection Firestore) : la FAQ évolue
/// avec le produit, au rythme des releases — même logique que `/privacy` et
/// `/terms`. RÈGLE DE RÉDACTION : ne décrire que des comportements livrés ;
/// les features à venir (rappels, import…) sont annoncées « à l'étude »,
/// jamais promises.
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppAppBar(title: 'Questions fréquentes', fallbackRoute: '/'),
      body: SafeArea(
        child: Center(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FAQ — Baillan',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les réponses aux questions les plus fréquentes. Vous '
                        'ne trouvez pas la vôtre ? Écrivez-nous via '
                        'Profil → Aide → « Nous contacter ».',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final section in _faqSections) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 28, bottom: 12),
                          child: Text(
                            section.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final entry in section.entries)
                          _FaqTile(entry: entry),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une question/réponse repliée par défaut — la liste reste scannable.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.entry});

  final _FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: Key('faq_tile_${entry.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          entry.question,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(entry.answer, style: theme.textTheme.bodyMedium)],
      ),
    );
  }
}

typedef _FaqEntry = ({String id, String question, String answer});
typedef _FaqSection = ({String title, List<_FaqEntry> entries});

/// Source unique du contenu FAQ — l'ordre est l'ordre d'affichage.
/// Les `id` sont stables (clés de widgets/tests) : ne pas les renuméroter.
const List<_FaqSection> _faqSections = [
  (
    title: 'Découvrir Baillan',
    entries: [
      (
        id: 'quoi',
        question: 'Qu\'est-ce que Baillan ?',
        answer:
            'Baillan est le registre locatif des bailleurs particuliers : '
            'vos biens, locataires et baux au même endroit, le suivi des '
            'paiements et des retards, des quittances de loyer conformes, '
            'le registre de vos dépenses, la régularisation annuelle des '
            'charges et un simulateur d\'investissement. Le tout pensé pour '
            'rester simple — en cas de doute, sortez le registre.',
      ),
      (
        id: 'gratuit',
        question: 'Baillan est-il gratuit ?',
        answer:
            'Oui, Baillan a un palier gratuit sans limite de durée : '
            'jusqu\'à 2 biens, 3 locataires, 2 baux actifs, 10 documents '
            'et 3 scénarios de simulation — de quoi tenir un petit '
            'portefeuille locatif complet. Les quittances de loyer PDF '
            'restent gratuites quel que soit le palier — c\'est un '
            'instrument légal, pas un produit d\'appel. Baillan Pro lève '
            'les plafonds et débloque quelques fonctions avancées ; vous '
            'n\'êtes jamais facturé sans action explicite de votre part.',
      ),
      // Tiles Pro désactivés tant que le checkout n'est pas déployé en prod
      // (FEAT-044e — le back-end est livré, la route `/pro` existe côté client
      // depuis 75fcbd3 sur develop). À réactiver au moment de la release.
      // (
      //   id: 'pro-inclus',
      //   question: 'Que débloque Baillan Pro ?',
      //   answer:
      //       'Biens, locataires, baux, documents et scénarios de '
      //       'simulation illimités, la régularisation annuelle des charges '
      //       '(pour les baux en provisions) et l\'accès au support '
      //       'prioritaire. Les quittances de loyer, elles, restent '
      //       'gratuites pour tous les comptes.',
      // ),
      // (
      //   id: 'pro-prix',
      //   question: 'Combien coûte Baillan Pro et comment l\'essayer ?',
      //   answer:
      //       '7,99 € par mois ou 79 € par an (deux mois offerts en '
      //       'annuel). Un essai gratuit de 7 jours vous laisse tester les '
      //       'fonctions Pro sans engagement, résiliable à tout moment '
      //       'depuis votre compte. Le paiement est traité par Stripe : '
      //       'vos coordonnées bancaires ne transitent pas par Baillan.',
      // ),
      (
        id: 'essai-sans-compte',
        question: 'Puis-je essayer Baillan sans créer de compte ?',
        answer:
            'Oui. « Continuer sans compte » ouvre le simulateur '
            'd\'investissement sans aucune inscription : rendement, '
            'cash-flow et coût du crédit, avec un scénario sauvegardé. '
            'Cet essai dure 14 jours glissants ; si vous créez un compte '
            'pendant l\'essai, votre scénario y est automatiquement '
            'rattaché. Le registre complet (biens, baux, quittances) '
            'nécessite un compte.',
      ),
      (
        id: 'appareils',
        question: 'Sur quels appareils Baillan fonctionne-t-il ?',
        answer:
            'Baillan est une application web : elle fonctionne dans le '
            'navigateur, sur ordinateur, tablette et téléphone, et peut '
            's\'installer comme une application (PWA). Des applications '
            'iOS et Android sont en préparation — même compte, mêmes '
            'données sur tous vos appareils.',
      ),
      (
        id: 'reprise-donnees',
        question:
            'J\'ai déjà des locataires en place, dois-je tout ressaisir ?',
        answer:
            'La saisie se fait aujourd\'hui dans l\'application : créez vos '
            'biens, vos locataires puis vos baux — quelques minutes par '
            'bien. L\'import de données depuis un fichier est à l\'étude.',
      ),
    ],
  ),
  (
    title: 'Loyers, paiements et quittances',
    entries: [
      (
        id: 'generer-quittance',
        question: 'Comment générer une quittance de loyer ?',
        answer:
            'Enregistrez le paiement sur le bail concerné (montant, date, '
            'mode de règlement, motif éventuel) : la quittance '
            'correspondante est générée et numérotée. Vous la retrouvez '
            'dans la fiche du bail, prête à être partagée en PDF.',
      ),
      (
        id: 'quittance-conforme',
        question: 'Les quittances sont-elles conformes à la loi ?',
        answer:
            'Oui. Chaque quittance porte les mentions requises par '
            'l\'article 21 de la loi n° 89-462 du 6 juillet 1989 : identité '
            'et adresse du bailleur, nom du locataire, adresse du logement, '
            'période concernée, détail loyer et charges, montant total et '
            'date d\'émission. Les quittances sont numérotées et archivées '
            'dans l\'application.',
      ),
      (
        id: 'corriger-quittance',
        question: 'Puis-je corriger une quittance déjà émise ?',
        answer:
            'Une quittance émise ne se modifie pas (elle a valeur de '
            'preuve) : vous l\'annulez, et une quittance rectifiée est '
            'émise en remplacement. L\'historique des deux reste tracé '
            'dans l\'application.',
      ),
      (
        id: 'retards',
        question: 'Comment Baillan détecte-t-il les retards de paiement ?',
        answer:
            'Pour chaque bail actif, Baillan compare les paiements '
            'enregistrés aux échéances attendues (jour de paiement du '
            'bail, avec un délai de grâce de 5 jours). Les baux en retard '
            'sont signalés sur l\'accueil et dans la liste des baux, avec '
            'un filtre dédié.',
      ),
      (
        id: 'rappels',
        question: 'Baillan envoie-t-il des rappels automatiques au locataire ?',
        answer:
            'Pas encore : aujourd\'hui les retards sont signalés dans '
            'l\'application, et vous relancez votre locataire par le canal '
            'de votre choix. Des rappels automatiques par email sont à '
            'l\'étude.',
      ),
    ],
  ),
  (
    title: 'Charges et dépenses',
    entries: [
      (
        id: 'provisions-forfait',
        question: 'Provisions sur charges ou forfait : que gère Baillan ?',
        answer:
            'Les deux. En provisions, le locataire verse une avance '
            'mensuelle régularisée chaque année ; au forfait, le montant '
            'est libératoire et ne se régularise pas. Baillan applique '
            'les règles légales selon le type de bail : un bail nu est '
            'obligatoirement en provisions, un bail mobilité au forfait, '
            'un meublé peut choisir.',
      ),
      (
        id: 'regularisation',
        question: 'Comment fonctionne la régularisation annuelle des charges ?',
        answer:
            'Pour un bail en provisions, Baillan rapproche les provisions '
            'encaissées sur la période des dépenses récupérables '
            'enregistrées, calcule le solde (trop-perçu à rembourser ou '
            'complément à demander) et génère un avis de régularisation en '
            'PDF à transmettre au locataire. Cette fonctionnalité est '
            'réservée au palier Baillan Pro — au forfait, la '
            'régularisation n\'a de toute façon pas d\'application '
            'légale.',
      ),
      (
        id: 'depenses',
        question: 'Quelles dépenses puis-je suivre ?',
        answer:
            'Le registre des dépenses se tient par bien : charges de '
            'copropriété, taxe foncière, assurance PNO, frais de gestion, '
            'travaux, entretien et réparations, divers. Chaque dépense est '
            'classée récupérable ou non récupérable — la catégorie est '
            'pré-remplie selon sa nature, conformément au décret 87-713 — '
            'et peut porter un justificatif (PDF ou photo). Les dépenses '
            'récupérables alimentent la régularisation des charges.',
      ),
    ],
  ),
  (
    title: 'Données, sécurité et RGPD',
    entries: [
      (
        id: 'stockage-donnees',
        question: 'Où sont stockées mes données et celles de mes locataires ?',
        answer:
            'En Union européenne, sur l\'infrastructure Google Firebase : '
            'base de données en multi-région eur3 (Belgique, Pays-Bas, '
            'Finlande) et fichiers à Francfort (europe-west3). Chaque '
            'compte n\'accède qu\'à ses propres données — les règles '
            'd\'accès sont vérifiées côté serveur —, les échanges sont '
            'chiffrés (HTTPS) et aucun outil de tracking publicitaire '
            'n\'est intégré. Détails dans la Politique de confidentialité.',
      ),
      (
        id: 'rgpd-locataires',
        question: 'Qui est responsable des données de mes locataires (RGPD) ?',
        answer:
            'En tant que bailleur, vous êtes responsable du traitement des '
            'données de vos locataires ; Baillan vous fournit l\'outil '
            '(Google Firebase agit en sous-traitant). Pensez à informer '
            'vos locataires de l\'utilisation d\'un outil de gestion — '
            'leurs droits d\'accès, de rectification et d\'effacement '
            's\'exercent auprès de vous.',
      ),
      (
        id: 'acces-locataires',
        question: 'Mes locataires ont-ils accès à Baillan ?',
        answer:
            'Non. Baillan est aujourd\'hui un outil réservé au bailleur : '
            'vos locataires n\'ont ni compte ni accès à vos données. Vous '
            'leur transmettez les documents (quittances, avis de '
            'régularisation) en PDF, par le canal de votre choix.',
      ),
      (
        id: 'suppression-compte',
        question: 'Comment supprimer mon compte et mes données ?',
        answer:
            'Depuis l\'application : Profil → « Supprimer mon compte » '
            '(confirmation d\'identité requise), ou depuis la page '
            'publique /delete-account. La suppression est immédiate et '
            'définitive : biens, locataires, baux, paiements, documents, '
            'dépenses et simulations sont effacés — téléchargez avant ce '
            'que vous souhaitez conserver. Seules les quittances émises '
            'sont conservées 5 ans (obligation légale de preuve), sous '
            'forme archivée inaccessible, puis supprimées.',
      ),
    ],
  ),
  (
    title: 'Compte et support',
    entries: [
      (
        id: 'mot-de-passe',
        question: 'J\'ai oublié mon mot de passe, que faire ?',
        answer:
            'Sur l\'écran de connexion, cliquez « Mot de passe oublié ? » : '
            'un email de réinitialisation vous est envoyé. Si vous vous '
            'êtes inscrit avec Google ou Apple, connectez-vous simplement '
            'via le bouton correspondant — il n\'y a pas de mot de passe '
            'Baillan à retenir. Une fois connecté, le mot de passe se '
            'change dans Profil → « Changer le mot de passe ».',
      ),
      (
        id: 'changer-email',
        question: 'Puis-je changer l\'adresse email de mon compte ?',
        answer:
            'Pas encore : l\'adresse email est l\'identifiant du compte et '
            'ne se modifie pas depuis l\'application pour l\'instant. '
            'Écrivez-nous via « Nous contacter » si c\'est bloquant.',
      ),
      (
        id: 'contact-support',
        question: 'Comment contacter le support ?',
        answer:
            'Une fois connecté : Profil → Aide → « Nous contacter ». '
            'Décrivez votre demande, nous vous répondons par email à '
            'l\'adresse de votre compte.',
      ),
    ],
  ),
];
