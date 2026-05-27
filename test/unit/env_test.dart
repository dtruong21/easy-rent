import 'package:easyrent/core/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('isConfigured returns false when supabaseUrl and supabaseAnonKey are empty', () {
      // In the test environment no --dart-define-from-file is passed, so both
      // constants default to ''. isConfigured must therefore be false.
      expect(Env.supabaseUrl, isEmpty);
      expect(Env.supabaseAnonKey, isEmpty);
      expect(Env.isConfigured, isFalse);
    });

    test('supabaseSchema defaults to "public" when not overridden', () {
      expect(Env.supabaseSchema, equals('public'));
    });

    test('isProd is true when supabaseSchema is "public" (default)', () {
      expect(Env.isProd, isTrue);
    });

    test('isDev is false when supabaseSchema is "public" (default)', () {
      expect(Env.isDev, isFalse);
    });

    test('storageEnvPrefix is "prod" when supabaseSchema is "public" (default)', () {
      expect(Env.storageEnvPrefix, equals('prod'));
    });
  });
}
