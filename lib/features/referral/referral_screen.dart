import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/numeric_styled_text.dart';

import '../main/main_screen.dart';
import '../../routes/app_router.dart';
import 'referral_service.dart';

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  @override
  void initState() {
    super.initState();
    // Force fresh API call every time this screen opens
    Future.microtask(() {
      ref.invalidate(referralDataProvider);
    });
  }

  // ── Native system share sheet — opens all platforms ─────────────────────
  Future<void> _shareReferral(String code, String rewardAmount) async {
    final reward =
        rewardAmount.startsWith('₹') ? rewardAmount : '₹$rewardAmount';
    final text =
        '🌟 Join me on StartGold and earn $reward in free Pure Gold!\n\n'
        'Use my referral code: $code\n\n'
        'Download now 👇\nhttps://startgold.com/download';
    await Share.share(text, subject: 'Invite to StartGold');
  }

  @override
  Widget build(BuildContext context) {
    final referralAsync = ref.watch(referralDataProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Gradient Header (extends to cover hero section too) ────────────
          _buildHeroHeader(context, ref, referralAsync),

          // ── White scrollable body ─────────────────────────────────────────
          Expanded(
            child: referralAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  _buildBody(context, ref, ReferralData.empty, [], ''),
              data: (data) => _buildBody(
                context,
                ref,
                data,
                data.bulletPoints,
                data.rewardAmount,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Full green hero header ─────────────────────────────────────────────────
  Widget _buildHeroHeader(
      BuildContext context, WidgetRef ref, AsyncValue<ReferralData> asyncData) {
    final rewardText = asyncData.when(
      data: (d) {
        if (d.rewardAmount.isEmpty) return '';
        // API returns just the number (e.g. "250"), prepend ₹ if not already present
        final amt = d.rewardAmount;
        return amt.startsWith('₹') ? amt : '₹$amt';
      },
      loading: () => '',
      error: (_, __) => '',
    );

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.87, -0.5),
          end: Alignment(0.87, 0.5),
          colors: [Color(0xFF003716), Color(0xFF167525)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28.r),
          bottomRight: Radius.circular(28.r),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // nav row
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20.sp),
                  onPressed: () {
                    final routeName = ModalRoute.of(context)?.settings.name;
                    if (routeName == AppRouter.referral) {
                      Navigator.pop(context);
                    } else {
                      ref.read(selectedTabProvider.notifier).state = 0;
                    }
                  },
                ),
                Text(
                  'Refer & Earn',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            SizedBox(height: 16.h),

            // Hero content — Stack so image sits bottom-right
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 16.w, 28.h),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Left: text content
                  Padding(
                    padding: EdgeInsets.only(right: 100.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Title only (bullets moved to body) ──
                        asyncData.whenData((d) => d).value?.title.isNotEmpty ==
                                true
                            ? Text(
                                asyncData.value!.title,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.5,
                                ),
                              )
                            : RichText(
                                text: TextSpan(
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                  children: [
                                    const TextSpan(
                                        text: 'Invite a friend and earn '),
                                    TextSpan(
                                      text: rewardText,
                                      style: GoogleFonts.lora(
                                        color: const Color(0xFFFDE047),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 20.sp,
                                      ),
                                    ),
                                    const TextSpan(text: ' worth of Gold.'),
                                  ],
                                ),
                              ),
                      ],
                    ),
                  ),

                  // Right: referral image (SVG)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Image.asset(
                      'assets/home/referal.png',
                      width: 110.w,
                      height: 110.w,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10.w,
          height: 10.w,
          margin: EdgeInsets.only(top: 3.h, right: 10.w),
          decoration: const BoxDecoration(
            color: Color(0xFFFDE047),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
              height: 1.43, // 20px / 14px
            ),
          ),
        ),
      ],
    );
  }

  // ── Premium body ─────────────────────────────────────────────────────
  Widget _buildBody(BuildContext context, WidgetRef ref, ReferralData data,
      [List<String> bulletPoints = const [], String rewardText = '']) {
    final code = data.referralCode.isNotEmpty ? data.referralCode : '';
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.w, 28.h, 20.w, 48.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.totalReferrals > 0 || data.totalEarned > 0) ...[
            GestureDetector(
              onTap: data.totalReferrals > 0
                  ? () => Navigator.pushNamed(context, AppRouter.refereeList)
                  : null,
              child: _buildStatsRow(data),
            ),
            SizedBox(height: 20.h),
          ],
          _buildPremiumCodeCard(context, code, data.rewardAmount),
          SizedBox(height: 20.h),
          _buildBulletSection(bulletPoints, rewardText),
          SizedBox(height: 24.h),
          _buildHowItWorks(),
        ],
      ),
    );
  }

  // ── Bullet points card ──────────────────────────────────────────────
  Widget _buildBulletSection(List<String> bullets, String rewardText) {
    final effectiveBullets = bullets.isNotEmpty
        ? bullets
        : [
            'Share the link with friends, family, and relatives.',
            'Both you and your friend get ${rewardText.isNotEmpty ? (rewardText.startsWith('\u20b9') ? rewardText : '\u20b9$rewardText') : 'a reward'} worth of gold.',
            'Reward is credited after your friend\'s first purchase.',
          ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why Refer?',
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1B882C),
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12.h),
          ...effectiveBullets.asMap().entries.map((entry) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: entry.key < effectiveBullets.length - 1 ? 12.h : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7.r,
                    height: 7.r,
                    margin: EdgeInsets.only(top: 5.h, right: 10.w),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1B882C), Color(0xFF49B44B)],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: NumericStyledText(
                      entry.value,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Premium code card ──────────────────────────────────────────────────────
  Widget _buildPremiumCodeCard(
      BuildContext context, String code, String rewardAmount) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB8860B), Color(0xFFDAA520), Color(0xFFF5C842)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDAA520).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(2.r), // gold border thickness
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 22.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Label
            Text(
              'YOUR REFERRAL CODE',
              style: GoogleFonts.playfairDisplay(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB8860B),
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 14.h),
            // Big code
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF8E8),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: const Color(0xFFDAA520).withOpacity(0.25),
                ),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: GoogleFonts.lora(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1B3A2D),
                  letterSpacing: 6,
                ),
              ),
            ),
            SizedBox(height: 18.h),
            // Two buttons
            Row(
              children: [
                // Copy Code
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      // Auto-clear clipboard after 60s — prevents clipboard sniffing
                      Future.delayed(const Duration(seconds: 60), () {
                        Clipboard.setData(const ClipboardData(text: ''));
                      });
                      AppToast.show(context, 'Referral code copied!',
                          type: ToastType.success);
                    },
                    icon: Icon(Icons.copy_rounded,
                        size: 16.sp, color: const Color(0xFF1B882C)),
                    label: Text(
                      'Copy Code',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1B882C),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      side: BorderSide(
                          color: const Color(0xFF1B882C).withOpacity(0.4),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50.r)),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                // Share
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment(-0.87, -0.5),
                        end: Alignment(0.87, 0.5),
                        colors: [Color(0xFF003716), Color(0xFF167525)],
                      ),
                      borderRadius: BorderRadius.circular(50.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1B882C).withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _shareReferral(code, rewardAmount),
                      icon: Icon(Icons.share_rounded,
                          size: 16.sp, color: Colors.white),
                      label: Text(
                        'Share',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50.r)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── How It Works section ───────────────────────────────────────────────────
  Widget _buildHowItWorks() {
    final steps = [
      {'icon': Icons.share_rounded, 'label': 'Share\nYour Code'},
      {'icon': Icons.person_add_rounded, 'label': 'Friend\nSigns Up'},
      {'icon': Icons.monetization_on_rounded, 'label': 'Both\nEarn Gold'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How It Works',
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              // Connector arrow between steps
              if (i.isOdd) {
                return Expanded(
                  child: Center(
                    child: Icon(Icons.arrow_forward_rounded,
                        color: const Color(0xFF1B882C).withOpacity(0.4),
                        size: 18.sp),
                  ),
                );
              }
              final step = steps[i ~/ 2];
              return Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Container(
                      width: 52.w,
                      height: 52.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B882C).withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1B882C).withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        step['icon'] as IconData,
                        color: const Color(0xFF1B882C),
                        size: 22.sp,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      step['label'] as String,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── Stats banner ───────────────────────────────────────────────────────────
  Widget _buildStatsRow(ReferralData data) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF003716), Color(0xFF1B882C), Color(0xFF49B44B)],
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B882C).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── Decorative background circles ──
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 110.w,
              height: 110.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -30,
            child: Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          // ── Content ──
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 20.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: label + big number + sub-label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Friends Referred',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.75),
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '${data.totalReferrals}',
                        style: GoogleFonts.lora(
                          fontSize: 42.sp,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        children: [
                          Icon(Icons.trending_up_rounded,
                              size: 13.sp, color: const Color(0xFFFDE047)),
                          SizedBox(width: 4.w),
                          Text(
                            'Keep referring & earn more gold!',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        children: [
                          Text(
                            'View list',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFDE047),
                            ),
                          ),
                          SizedBox(width: 3.w),
                          Icon(Icons.arrow_forward_rounded,
                              size: 12.sp, color: const Color(0xFFFDE047)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right: icon badge
                Container(
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2), width: 1.5),
                  ),
                  child: Icon(Icons.group_rounded,
                      color: Colors.white, size: 30.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
