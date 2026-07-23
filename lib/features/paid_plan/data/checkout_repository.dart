import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class CheckoutRepository {
  Future<String> createCheckoutSession({required String plan});
}

class FirebaseCheckoutRepository implements CheckoutRepository {
  FirebaseCheckoutRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<String> createCheckoutSession({required String plan}) async {
    final callable = _functions.httpsCallable(
      'createCheckoutSession',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Map<String, dynamic>>({'plan': plan});
    final url = result.data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('createCheckoutSession returned no URL');
    }
    return url;
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => FirebaseCheckoutRepository(
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  ),
);
