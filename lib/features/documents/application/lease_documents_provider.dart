import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/documents_repository.dart';
import '../domain/document.dart';

final _log = Logger('LeaseDocumentsNotifier');

/// Notifier qui charge et expose la liste des documents actifs d'un bail.
///
/// Paramétré par [leaseId] — un cache distinct par bail (invalidation chirurgicale).
/// Tri : `uploaded_at DESC` (géré par le repository).
class LeaseDocumentsNotifier
    extends FamilyAsyncNotifier<List<Document>, String> {
  @override
  Future<List<Document>> build(String arg) async {
    _log.info('fetch documents for lease=$arg');
    return ref.read(documentsRepositoryProvider).listForLease(arg);
  }

  /// Recharge la liste depuis Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(documentsRepositoryProvider).listForLease(arg),
    );
  }
}

/// Provider de la liste des documents, paramétré par leaseId.
final leaseDocumentsProvider =
    AsyncNotifierProviderFamily<LeaseDocumentsNotifier, List<Document>, String>(
      LeaseDocumentsNotifier.new,
    );
