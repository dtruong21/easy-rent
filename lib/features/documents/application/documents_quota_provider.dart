import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/documents_repository.dart';
import '../domain/documents_quota.dart';

final _log = Logger('DocumentsQuotaNotifier');

/// Notifier qui calcule le quota de stockage utilisé par le bailleur courant.
///
/// Invalidé après chaque upload ou suppression de document.
class DocumentsQuotaNotifier extends AsyncNotifier<DocumentsQuota> {
  @override
  Future<DocumentsQuota> build() async {
    _log.info('fetch quota for current landlord');
    return ref.read(documentsRepositoryProvider).quotaForCurrentLandlord();
  }
}

/// Provider du quota de stockage documents pour le bailleur courant.
final documentsQuotaProvider =
    AsyncNotifierProvider<DocumentsQuotaNotifier, DocumentsQuota>(
      DocumentsQuotaNotifier.new,
    );
