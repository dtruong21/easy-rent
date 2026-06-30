import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/tenant_repository.dart';
import '../domain/tenant.dart';
import '../domain/tenant_form_state.dart';
import 'tenant_detail_provider.dart';
import 'tenants_list_provider.dart';

final _log = Logger('TenantFormController');

/// Contrôle le formulaire de création / édition d'un locataire.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [tenantsListProvider] et, en mode édition,
/// [tenantDetailProvider(id)] pour que la liste et la fiche soient à jour.
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// du formulaire.
class TenantFormController extends StateNotifier<TenantFormState> {
  TenantFormController(this._ref) : super(const TenantFormState.idle());

  final Ref _ref;

  /// Soumet le formulaire.
  ///
  /// [initial] : null pour une création, locataire existant pour une édition.
  Future<void> submit({
    Tenant? initial,
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async {
    state = const TenantFormState.submitting();

    try {
      final repo = _ref.read(tenantRepositoryProvider);
      final Tenant result;

      if (initial == null) {
        // Mode création
        result = await repo.create(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          birthDate: birthDate,
          birthPlace: birthPlace?.trim().isEmpty == true
              ? null
              : birthPlace?.trim(),
          nationality: nationality?.trim().isEmpty == true
              ? null
              : nationality?.trim(),
          profession: profession?.trim().isEmpty == true
              ? null
              : profession?.trim(),
          employer: employer?.trim().isEmpty == true ? null : employer?.trim(),
          monthlyIncomeCents: monthlyIncomeCents,
          previousAddress: previousAddress?.trim().isEmpty == true
              ? null
              : previousAddress?.trim(),
          guarantorName: guarantorName?.trim().isEmpty == true
              ? null
              : guarantorName?.trim(),
          guarantorEmail: guarantorEmail?.trim().isEmpty == true
              ? null
              : guarantorEmail?.trim(),
          guarantorPhone: guarantorPhone?.trim().isEmpty == true
              ? null
              : guarantorPhone?.trim(),
        );
        _log.info('tenant created id=${result.id}');
      } else {
        // Mode édition — on n'envoie QUE les champs métier
        final updated = initial.copyWith(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
          birthDate: birthDate,
          birthPlace: birthPlace?.trim().isEmpty == true
              ? null
              : birthPlace?.trim(),
          nationality: nationality?.trim().isEmpty == true
              ? null
              : nationality?.trim(),
          profession: profession?.trim().isEmpty == true
              ? null
              : profession?.trim(),
          employer: employer?.trim().isEmpty == true ? null : employer?.trim(),
          monthlyIncomeCents: monthlyIncomeCents,
          previousAddress: previousAddress?.trim().isEmpty == true
              ? null
              : previousAddress?.trim(),
          guarantorName: guarantorName?.trim().isEmpty == true
              ? null
              : guarantorName?.trim(),
          guarantorEmail: guarantorEmail?.trim().isEmpty == true
              ? null
              : guarantorEmail?.trim(),
          guarantorPhone: guarantorPhone?.trim().isEmpty == true
              ? null
              : guarantorPhone?.trim(),
        );
        result = await repo.update(updated);
        _log.info('tenant updated id=${result.id}');
        // Invalider la fiche pour forcer un rechargement.
        _ref.invalidate(tenantDetailProvider(result.id));
      }

      // Invalider la liste pour afficher le nouveau/modifié locataire.
      _ref.invalidate(tenantsListProvider);

      state = TenantFormState.success(tenant: result);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseFunctionsException submit (code=${e.code})', e, st);
      state = TenantFormState.error(message: _mapFunctionsError(e));
    } on FirebaseException catch (e, st) {
      _log.warning('FirebaseException submit (code=${e.code})', e, st);
      state = const TenantFormState.error(
        message: 'Erreur de sauvegarde. Vérifiez votre connexion et réessayez.',
      );
    } on TenantNotFoundException catch (notFound, st) {
      _log.warning('TenantNotFoundException lors de submit', notFound, st);
      state = const TenantFormState.error(
        message: 'Locataire introuvable. Il a peut-être été archivé.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = const TenantFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const TenantFormState.idle();

  String _mapFunctionsError(FirebaseFunctionsException e) {
    final code = e.code;
    final msg = e.message ?? '';
    if (msg.contains('tenant_has_active_leases')) {
      return 'Ce locataire a des baux actifs — résiliez-les avant d\'archiver.';
    }
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return 'Action non autorisée.';
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return 'Service temporairement indisponible. Réessayez.';
    }
    return 'Erreur lors de la sauvegarde. Veuillez réessayer.';
  }
}

/// Provider autoDispose du contrôleur de formulaire locataire.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final tenantFormControllerProvider =
    StateNotifierProvider.autoDispose<TenantFormController, TenantFormState>(
      (ref) => TenantFormController(ref),
    );
