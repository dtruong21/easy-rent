import 'package:freezed_annotation/freezed_annotation.dart';

part 'paid_plan_interest.freezed.dart';

/// Marque d'intérêt d'un landlord FREE pour le futur Plan Pro.
///
/// Persisté sur `paid_plan_interest/{uid}` (docId = UID landlord). Écrit
/// depuis [ComingSoonPaidPlanSection] (pied de `/simulator`) et la modal
/// [ScenarioLimitReachedModal] (mode `free`) quand l'utilisateur clique
/// « M'avertir du lancement ». Aucun plan payant n'est encore commercialisé
/// au moment de BAILLAN-M1 — ce document sert uniquement à mesurer la
/// demande et informer les premiers utilisateurs au lancement.
@freezed
class PaidPlanInterest with _$PaidPlanInterest {
  const factory PaidPlanInterest({
    /// Fonctionnalités du Plan Pro qui ont motivé le clic (ex.
    /// `['comparateur', 'sensibilite_taux', 'fiscal_lmnp', 'export_pdf']`).
    /// Permet de prioriser la roadmap Plan Pro selon la demande réelle.
    @Default(<String>[]) List<String> features,

    /// Email de contact optionnel si différent de celui du compte (ex. un
    /// email professionnel pour le lancement commercial).
    String? email,

    /// Horodatage de la dernière expression d'intérêt (mis à jour à chaque
    /// clic répété, pour avoir une notion de fraîcheur du signal).
    DateTime? notifyAt,
  }) = _PaidPlanInterest;
}
