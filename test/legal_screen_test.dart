import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/content/screens/legal_screen.dart';
import 'package:startgold/routes/app_router.dart';

/// Profile → Legal lists every policy document, and each row opens its own
/// route (stubbed here, so no CMS fetch happens).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const rows = {
    'Terms & Conditions': AppRouter.terms,
    'Privacy Policy': AppRouter.privacy,
    'Refund Policy': AppRouter.refundPolicy,
    'AutoGold Terms & Conditions': AppRouter.autoGoldTerms,
    'Grievances': AppRouter.grievances,
  };

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: const LegalScreen(),
          routes: {
            for (final route in rows.values)
              route: (_) => Scaffold(body: Text('page:$route')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the five documents in order', (tester) async {
    await pump(tester);

    final tops = [
      for (final title in rows.keys) tester.getTopLeft(find.text(title)).dy,
    ];
    expect(tops, [...tops]..sort());
  });

  for (final entry in rows.entries) {
    testWidgets('${entry.key} opens ${entry.value}', (tester) async {
      await pump(tester);

      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();

      expect(find.text('page:${entry.value}'), findsOneWidget);
    });
  }
}
