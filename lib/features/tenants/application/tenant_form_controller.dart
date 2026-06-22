import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    } on PostgrestException catch (e, st) {
      _log.warning('PostgrestException lors de submit', e, st);
      state = TenantFormState.error(message: mapPostgrestError(e));
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
}

/// Provider autoDispose du contrôleur de formulaire locataire.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final tenantFormControllerProvider =
    StateNotifierProvider.autoDispose<TenantFormController, TenantFormState>(
      (ref) => TenantFormController(ref),
    );
