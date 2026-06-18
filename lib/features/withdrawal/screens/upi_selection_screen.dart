import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/widgets/animations.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../providers/withdrawal_provider.dart';
import '../models/withdrawal_method.dart';
import '../services/withdrawal_service.dart';
import '../../../core/providers/user_provider.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../shared/widgets/gradient_header.dart';

class UpiSelectionScreen extends ConsumerStatefulWidget {
  const UpiSelectionScreen({super.key});

  @override
  ConsumerState<UpiSelectionScreen> createState() => _UpiSelectionScreenState();
}

class _UpiSelectionScreenState extends ConsumerState<UpiSelectionScreen> {
  // Brand colours
  static const _gradientDark = Color(0xFF003716);
  static const _gradientLight = Color(0xFF167525);
  static const _accentGreen = Color(0xFF1B882C);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSelect());
  }

  void _autoSelect() {
    final list = ref.read(accountDetailsProvider).valueOrNull;
    if (list != null && list.isNotEmpty) {
      final alreadySelected = ref.read(withdrawalProvider).selectedMethod;
      if (alreadySelected == null) {
        ref.read(withdrawalProvider.notifier).selectMethod(list.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accountsAsync = ref.watch(accountDetailsProvider);

    ref.listen<AsyncValue<List<WithdrawalMethod>>>(accountDetailsProvider,
        (_, next) {
      next.whenData((list) {
        final current = ref.read(withdrawalProvider).selectedMethod;
        if (list.isEmpty) {
          ref.read(withdrawalProvider.notifier).selectMethod(null);
        } else if (current != null && !list.any((m) => m.id == current.id)) {
          ref.read(withdrawalProvider.notifier).selectMethod(list.first);
        } else if (current == null) {
          ref.read(withdrawalProvider.notifier).selectMethod(list.first);
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Select UPI ID',
            onBack: () => Navigator.pop(context),
          ),

          // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: accountsAsync.when(
              data: (methods) => _buildBody(context, methods, isDark),
              loading: () => const Center(
                  child: CircularProgressIndicator(color: _accentGreen)),
              error: (_, __) => _buildErrorState(isDark),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildFooter(context, ref, isDark, accountsAsync),
    );
  }

  // â”€â”€ BODY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBody(
      BuildContext context, List<WithdrawalMethod> methods, bool isDark) {
    return RefreshIndicator(
      color: _accentGreen,
      onRefresh: () async => ref.refresh(accountDetailsProvider),
      child: ListView(
        padding: EdgeInsets.all(20.w),
        children: [
          SizedBox(height: 4.h),

          // â”€â”€ Account cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (methods.isNotEmpty) ...[
            ...methods.asMap().entries.map((entry) {
              final index = entry.key;
              final method = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: FadeInAnimation(
                  delay: Duration(milliseconds: 60 * index),
                  child: _buildAccountCard(method, isDark, isFirst: index == 0),
                ),
              );
            }).toList(),
            SizedBox(height: 8.h),
          ],

          // â”€â”€ Empty state (show add button in body when no accounts) â”€â”€â”€â”€â”€â”€â”€â”€
          if (methods.isEmpty) _buildEmptyState(context, isDark),

          // â”€â”€ Add a UPI ID row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (methods.isNotEmpty) _buildAddRow(context, isDark),
        ],
      ),
    );
  }

  // â”€â”€ ACCOUNT CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAccountCard(WithdrawalMethod method, bool isDark,
      {bool isFirst = false}) {
    final selectedMethod = ref.watch(withdrawalProvider).selectedMethod;
    final isSelected = selectedMethod?.id == method.id;

    return GestureDetector(
      onTap: () => ref.read(withdrawalProvider.notifier).selectMethod(method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected
                ? _accentGreen
                : (isDark ? Colors.white12 : const Color(0x330E5723)),
            width: isSelected ? 1.5 : 0.5,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          children: [
            // â”€â”€ Radio dot indicator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22.w,
              height: 22.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _accentGreen : Colors.transparent,
                border: Border.all(
                  color: _accentGreen,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check_rounded, color: Colors.white, size: 13.sp)
                  : null,
            ),
            SizedBox(width: 14.w),

            // â”€â”€ Text â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.title.isNotEmpty ? method.title : method.identifier,
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  NumericStyledText(
                    method.identifier,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),
            ),

            // â”€â”€ Suggested badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (isFirst)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: _accentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  'suggested',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: _accentGreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ ADD ROW â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAddRow(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => _showAddOptions(context, ref, isDark),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Small rounded-square + badge
              Container(
                width: 28.w,
                height: 28.w,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accentGreen, _gradientDark],
                  ),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 18.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                'Add Account',
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                  color: _accentGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ EMPTY STATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(top: 60.h),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showAddOptions(context, ref, isDark),
            child: Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                color: _accentGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/withdraw/add.svg',
                  width: 28.w,
                  height: 28.w,
                  colorFilter:
                      const ColorFilter.mode(_accentGreen, BlendMode.srcIn),
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Add Account',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Add a UPI ID or bank account\nto proceed with withdrawal',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 12.sp,
              color: isDark ? Colors.white38 : Colors.black38,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ ERROR STATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 48.sp),
          SizedBox(height: 16.h),
          Text(
            'Failed to load accounts.\nPull to refresh.',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
                color: isDark ? Colors.white54 : Colors.black54),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: () => ref.refresh(accountDetailsProvider),
            style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // â”€â”€ FOOTER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildFooter(BuildContext context, WidgetRef ref, bool isDark,
      AsyncValue<List<WithdrawalMethod>> accountsAsync) {
    final selected = ref.watch(withdrawalProvider).selectedMethod;
    final methods = accountsAsync.valueOrNull ?? [];
    final isEnabled = selected != null && methods.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomButton(
              text: 'Withdrawal', svgIconPath: 'assets/buttons/tick.svg',
              onPressed: isEnabled
                  ? () => Navigator.pushNamed(context, '/withdrawal-confirmation')
                  : null,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isEnabled
                    ? const [_accentGreen, _gradientDark]
                    : [
                        _accentGreen.withOpacity(0.4),
                        _gradientDark.withOpacity(0.4),
                      ],
              ),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: _accentGreen.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ ADD ACCOUNT SHEET â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showAddOptions(BuildContext context, WidgetRef ref, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 24.h),
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF0F172A)])
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFDEF9DF), Color(0xFFFFFFFF)],
                    stops: [-0.3775, 1.0],
                  ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Add Account',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black),
              ),
              SizedBox(height: 4.h),
              Text(
                'Select your preferred payout method for a quick and secure transfer.',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white54 : Colors.black54,
                    height: 1.5),
              ),
              SizedBox(height: 20.h),
              _buildOptionTile(
                context,
                'UPI Handle',
                'Receive your money instantly using your UPI ID for a quick and easy transfer.',
                'assets/withdraw/upi.svg',
                () {
                  Navigator.pop(context);
                  _showUpiForm(context, ref, isDark);
                },
                isDark,
              ),
              // TODO: Bank Account feature â€” to be enabled later
              // SizedBox(height: 12.h),
              // _buildOptionTile(
              //   context,
              //   'Bank Account',
              //   'Get your funds securely transferred directly to your registered bank account.',
              //   'assets/withdraw/bank.svg',
              //   () {
              //     Navigator.pop(context);
              //     _showBankForm(context, ref, isDark);
              //   },
              //   isDark,
              // ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, String title, String desc,
      String svgAsset, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.07)),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                color: _accentGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Center(
                child: SvgPicture.asset(
                  svgAsset,
                  width: 20.w,
                  height: 20.w,
                  colorFilter:
                      const ColorFilter.mode(_accentGreen, BlendMode.srcIn),
                ),
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : Colors.black87)),
                  SizedBox(height: 3.h),
                  Text(desc,
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 11.sp,
                          color: isDark ? Colors.white38 : Colors.black45,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ UPI FORM SHEET â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showUpiForm(BuildContext context, WidgetRef ref, bool isDark) {
    final ctrl = TextEditingController();
    bool isVerifying = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          top: false,
          child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF0F172A)])
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFDEF9DF), Color(0xFFFFFFFF)],
                      stops: [-0.3775, 1.0],
                    ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4.r)),
                  ),
                ),
                SizedBox(height: 20.h),
                // Close + title row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Add UPI Handle',
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black)),
                    GestureDetector(
                      onTap: isVerifying ? null : () => Navigator.pop(sheetCtx),
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 18.sp, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  'Receive your money instantly using your UPI\nID for a quick and easy transfer.',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 12.sp,
                      color: isDark ? Colors.white54 : Colors.black54,
                      height: 1.5),
                ),
                SizedBox(height: 24.h),
                Text('Enter UPI ID',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : Colors.black87)),
                SizedBox(height: 8.h),
                TextField(
                  controller: ctrl,
                  enabled: !isVerifying,
                  onChanged: (_) => setModalState(() {}),
                  contextMenuBuilder: SecureClipboard.none,
                  style: GoogleFonts.playfairDisplay(
                      color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'example@abc',
                    hintStyle: TextStyle(
                        fontSize: 16.sp,
                        color: isDark ? Colors.white30 : Colors.black26),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide:
                            const BorderSide(color: _accentGreen, width: 1.5)),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
                  ),
                ),
                SizedBox(height: 28.h),
                _buildGradientButton(
                  'Verify & Add',
                  ctrl.text.trim().isNotEmpty && !isVerifying,
                  (ctrl.text.trim().isNotEmpty && !isVerifying)
                      ? () => _processAddUpi(
                          sheetCtx, ref, ctrl.text.trim(), setModalState,
                          (v) => isVerifying = v)
                      : null,
                  isLoading: isVerifying,
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  // â”€â”€ BANK FORM SHEET â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showBankForm(BuildContext context, WidgetRef ref, bool isDark) {
    final nameCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final accCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    bool isVerifying = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF0F172A)])
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFDEF9DF), Color(0xFFFFFFFF)],
                      stops: [-0.3775, 1.0],
                    ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(4.r)),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Text('Add Bank Account',
                          style: GoogleFonts.playfairDisplay(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black)),
                      GestureDetector(
                        onTap: () { if (!isVerifying) Navigator.pop(sheetCtx); },
                        child: Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 18.sp, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  _buildField('Account Holder Name', 'Enter full name',
                      nameCtrl, isDark,
                      forceUpperCase: true,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 12.h),
                  _buildField('Bank Name', 'e.g. State Bank of India',
                      bankNameCtrl, isDark,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 12.h),
                  _buildField(
                      'Account Number', 'Enter account number', accCtrl, isDark,
                      kbd: TextInputType.number,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 12.h),
                  _buildField('IFSC Code', 'e.g. SBIN0001234', ifscCtrl, isDark,
                      forceUpperCase: true,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 28.h),
                  _buildGradientButton(
                    'Verify & Add',
                    nameCtrl.text.trim().isNotEmpty &&
                        bankNameCtrl.text.trim().isNotEmpty &&
                        accCtrl.text.trim().isNotEmpty &&
                        ifscCtrl.text.trim().isNotEmpty &&
                        !isVerifying,
                    (nameCtrl.text.trim().isNotEmpty &&
                            bankNameCtrl.text.trim().isNotEmpty &&
                            accCtrl.text.trim().isNotEmpty &&
                            ifscCtrl.text.trim().isNotEmpty &&
                            !isVerifying)
                        ? () => _processAddBank(
                            sheetCtx,
                            ref,
                            nameCtrl.text.trim(),
                            bankNameCtrl.text.trim(),
                            accCtrl.text.trim(),
                            ifscCtrl.text.trim(),
                            setModalState,
                            (v) => isVerifying = v)
                        : null,
                    isLoading: isVerifying,
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Shared gradient button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildGradientButton(
      String label, bool isEnabled, VoidCallback? onPressed,
      {bool isLoading = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: double.infinity,
      height: 54.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isEnabled
              ? const [_accentGreen, _gradientDark]
              : isLoading
                  ? [_accentGreen.withOpacity(0.7), _gradientDark.withOpacity(0.7)]
                  : [
                      _accentGreen.withOpacity(0.4),
                      _gradientDark.withOpacity(0.4),
                    ],
        ),
        borderRadius: BorderRadius.circular(100.r),
        boxShadow: (isEnabled && !isLoading)
            ? [
                BoxShadow(
                  color: _accentGreen.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white60,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100.r)),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isLoading
              ? Row(
                  key: const ValueKey('verifying'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18.h,
                      height: 18.h,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      'Verifying...',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  key: const ValueKey('label'),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  // â”€â”€ Field helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildField(
      String label, String hint, TextEditingController ctrl, bool isDark,
      {TextInputType kbd = TextInputType.text,
      bool forceUpperCase = false,
      ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87)),
        SizedBox(height: 8.h),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          keyboardType: kbd,
          contextMenuBuilder: SecureClipboard.none,
          textCapitalization: forceUpperCase
              ? TextCapitalization.characters
              : TextCapitalization.none,
          inputFormatters: forceUpperCase
              ? [
                  TextInputFormatter.withFunction((oldValue, newValue) =>
                      newValue.copyWith(text: newValue.text.toUpperCase()))
                ]
              : null,
          style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontSize: 16.sp,
                color: isDark ? Colors.white30 : Colors.black26),
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFF3F4F6),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: const BorderSide(color: _accentGreen, width: 1.5)),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
          ),
        ),
      ],
    );
  }

  // â”€â”€ Process UPI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _processAddUpi(
      BuildContext sheetCtx, WidgetRef ref, String upi,
      StateSetter setModalState, void Function(bool) setVerifying) async {
    if (!upi.contains('@')) {
      if (mounted) {
        AppToast.show(sheetCtx, 'Please enter a valid UPI ID (e.g. name@bank)',
            type: ToastType.error);
      }
      return;
    }
    final user = ref.read(userProvider);
    if (user == null) return;

    setModalState(() => setVerifying(true));
    try {
      final result = await ref.read(withdrawalServiceProvider).verifyAndAddUpi(
            customerId: user.id,
            mobile: user.mobile,
            upiId: upi,
          );
      if (!sheetCtx.mounted) return;
      if (result['success'] == true) {
        Navigator.pop(sheetCtx); // close sheet
        ref.invalidate(accountDetailsProvider);
        // Show server success message to user
        if (mounted) {
          AppToast.show(
            context,
            result['message'] ?? 'UPI verified successfully',
            type: ToastType.success,
          );
        }
      } else {
        setModalState(() => setVerifying(false));
        AppToast.show(sheetCtx, result['message'] ?? 'Verification failed',
            type: ToastType.error);
      }
    } catch (e) {
      if (sheetCtx.mounted) {
        setModalState(() => setVerifying(false));
        AppToast.show(sheetCtx, 'Could not verify UPI. Please try again.',
            type: ToastType.error);
      }
    }
  }

  // â”€â”€ Process Bank â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _processAddBank(BuildContext sheetCtx, WidgetRef ref,
      String name, String bankName, String acc, String ifsc,
      StateSetter setModalState, void Function(bool) setVerifying) async {
    final user = ref.read(userProvider);
    if (user == null) return;

    setModalState(() => setVerifying(true));
    try {
      final result = await ref.read(withdrawalServiceProvider).verifyAndAddBank(
            customerId: user.id,
            mobile: user.mobile,
            holderName: name,
            bankName: bankName,
            accNo: acc,
            ifsc: ifsc,
          );
      if (!sheetCtx.mounted) return;
      if (result['success'] == true) {
        Navigator.pop(sheetCtx);
        ref.invalidate(accountDetailsProvider);
        if (mounted) {
          AppToast.show(
            context,
            result['message'] ?? 'Bank account verified successfully',
            type: ToastType.success,
          );
        }
      } else {
        setModalState(() => setVerifying(false));
        AppToast.show(sheetCtx, result['message'] ?? 'Verification failed',
            type: ToastType.error);
      }
    } catch (e) {
      if (sheetCtx.mounted) {
        setModalState(() => setVerifying(false));
        AppToast.show(
            sheetCtx, 'Could not verify bank details. Please try again.',
            type: ToastType.error);
      }
    }
  }
}
