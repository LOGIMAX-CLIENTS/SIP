import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../routes/app_router.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/menu_tile.dart';

/// Profile → Legal: every policy document in one place. Each row opens the
/// server-fetched [ContentScreen] for that document.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Column(
          children: [
            const GradientHeader(title: 'Legal'),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(24.w),
                children: [
                  MenuTile(
                    title: 'Terms & Conditions',
                    iconPath: 'assets/sidemenu/tc.svg',
                    onTap: () => Navigator.pushNamed(context, AppRouter.terms),
                  ),
                  MenuTile(
                    title: 'Privacy Policy',
                    iconPath: 'assets/sidemenu/privacy.svg',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRouter.privacy),
                  ),
                  MenuTile(
                    title: 'Refund Policy',
                    iconPath: 'assets/sidemenu/refund.svg',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRouter.refundPolicy),
                  ),
                  MenuTile(
                    title: 'AutoGold Terms & Conditions',
                    iconPath: 'assets/sidemenu/autosaving.svg',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRouter.autoGoldTerms),
                  ),
                  MenuTile(
                    title: 'Grievances',
                    iconPath: 'assets/sidemenu/enquiry.svg',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRouter.grievances),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
