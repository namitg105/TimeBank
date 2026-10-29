// Smoke tests for the TimeBank app shell.
//
// These deliberately avoid the network. Every page fetches from the
// Spring Boot API on first build, so a test that mounted the whole app
// would fail whenever Oracle happened to be down -- which tells you
// nothing about the widgets. The theme and the shell can be checked on
// their own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timebank/core/theme/app_colors.dart';
import 'package:timebank/core/theme/app_theme.dart';
import 'package:timebank/shared/widgets/app_widgets.dart';

void main() {
  group('theme', () {
    test('canvas is near-black, not pure black', () {
      // A fraction of blue stops a large dark area reading as a dead
      // pixel field, and gives the greys above it something to sit on.
      expect(AppColors.canvas.r, lessThan(0.05));
      expect(AppColors.canvas.b, greaterThan(AppColors.canvas.r));
    });

    test('status colours are distinct per booking state', () {
      expect(AppColors.forStatus('COMPLETED'), AppColors.positive);
      expect(AppColors.forStatus('DISPUTED'), AppColors.negative);
      expect(AppColors.forStatus('CONFIRMED'), AppColors.info);
    });

    test('amount colour follows the sign', () {
      expect(AppColors.forAmount(1.5), AppColors.positive);
      expect(AppColors.forAmount(-1.5), AppColors.negative);
      expect(AppColors.forAmount(0), AppColors.textMuted);
    });

    test('dark theme uses the canvas as its scaffold background', () {
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.canvas);
    });
  });

  group('shared widgets', () {
    testWidgets('StatusChip always shows the word, not just a colour',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StatusChip('COMPLETED')),
      ));
      expect(find.text('COMPLETED'), findsOneWidget);
    });

    testWidgets('EmptyState tells the user what to do next',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No sessions yet',
            hint: 'Book the first one with the + button above.',
          ),
        ),
      ));
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(find.textContaining('Book the first one'), findsOneWidget);
    });

    testWidgets('ErrorView offers a retry when one is given',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorView(
            message: 'Cannot reach the server.',
            onRetry: () => retried = true,
          ),
        ),
      ));
      expect(find.text('Cannot reach the server.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });
}
