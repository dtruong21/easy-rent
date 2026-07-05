import 'package:easyrent/core/router/transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('appPage — smoke tests', () {
    // -------------------------------------------------------------------------
    // Cas 1 : overrideIsWeb: true → CustomTransitionPage (fade ou standard)
    // -------------------------------------------------------------------------
    test(
      'overrideIsWeb: true ET transition standard → CustomTransitionPage',
      () {
        final page = appPage<void>(
          key: const ValueKey('test'),
          child: const SizedBox(),
          transition: AppTransition.standard,
          overrideIsWeb: true,
        );

        expect(page, isA<CustomTransitionPage<void>>());
      },
    );

    test('overrideIsWeb: true ET transition fade → CustomTransitionPage', () {
      final page = appPage<void>(
        key: const ValueKey('test'),
        child: const SizedBox(),
        transition: AppTransition.fade,
        overrideIsWeb: true,
      );

      expect(page, isA<CustomTransitionPage<void>>());
    });

    test('overrideIsWeb: true ET transition none → NoTransitionPage', () {
      final page = appPage<void>(
        key: const ValueKey('test'),
        child: const SizedBox(),
        transition: AppTransition.none,
        overrideIsWeb: true,
      );

      expect(page, isA<NoTransitionPage<void>>());
    });

    // -------------------------------------------------------------------------
    // Cas 2 : overrideIsWeb: false → MaterialPage quelle que soit la transition
    // -------------------------------------------------------------------------
    test('overrideIsWeb: false → MaterialPage (transition standard)', () {
      final page = appPage<void>(
        key: const ValueKey('test'),
        child: const SizedBox(),
        transition: AppTransition.standard,
        overrideIsWeb: false,
      );

      expect(page, isA<MaterialPage<void>>());
    });

    test('overrideIsWeb: false → MaterialPage (transition fade)', () {
      final page = appPage<void>(
        key: const ValueKey('test'),
        child: const SizedBox(),
        transition: AppTransition.fade,
        overrideIsWeb: false,
      );

      expect(page, isA<MaterialPage<void>>());
    });

    test('overrideIsWeb: false → MaterialPage (transition none)', () {
      final page = appPage<void>(
        key: const ValueKey('test'),
        child: const SizedBox(),
        transition: AppTransition.none,
        overrideIsWeb: false,
      );

      expect(page, isA<MaterialPage<void>>());
    });

    // -------------------------------------------------------------------------
    // Clé transmise correctement
    // -------------------------------------------------------------------------
    test('la key est transmise à la page produite', () {
      const key = ValueKey('ma-route');

      final page = appPage<void>(
        key: key,
        child: const SizedBox(),
        overrideIsWeb: false,
      );

      expect(page.key, equals(key));
    });
  });
}
