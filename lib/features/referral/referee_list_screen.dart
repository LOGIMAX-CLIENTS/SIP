import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/numeric_styled_text.dart';
import 'package:shimmer/shimmer.dart';

import '../../shared/widgets/gradient_header.dart';
import '../../shared/theme/app_text_styles.dart';
import 'referee_list_service.dart';

class RefereeListScreen extends ConsumerStatefulWidget {
  const RefereeListScreen({super.key});

  @override
  ConsumerState<RefereeListScreen> createState() => _RefereeListScreenState();
}

class _RefereeListScreenState extends ConsumerState<RefereeListScreen> {
  @override
  void initState() {
    super.initState();
    // Force fresh API call every time this page is opened
    Future.microtask(() => ref.invalidate(refereeListProvider));
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(refereeListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Friends Referred'),
          Expanded(
            child: asyncData.when(
              loading: () => _buildSkeleton(),
              error: (e, _) => _buildError(context, ref),
              data: (data) => data.results.isEmpty
                  ? _buildEmpty()
                  : _buildList(data),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer skeleton ──────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      itemCount: 5,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.black.withValues(alpha: 0.05),
        highlightColor: Colors.black.withValues(alpha: 0.10),
        child: Container(
          height: 90.h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.r),
          ),
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48.sp, color: Colors.black26),
          SizedBox(height: 12.h),
          Text(
            'Failed to load referral list.',
            style: GoogleFonts.playfairDisplay(fontSize: 14.sp, color: Colors.black45),
          ),
          SizedBox(height: 16.h),
          TextButton.icon(
            onPressed: () => ref.invalidate(refereeListProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                color: const Color(0xFF1B882C).withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.group_off_rounded,
                  size: 38.sp, color: const Color(0xFF1B882C)),
            ),
            SizedBox(height: 20.h),
            Text(
              'No Referrals Yet',
              style: AppTextStyles.titleMedium(false),
            ),
            SizedBox(height: 8.h),
            Text(
              'Share your referral code with friends and track their status here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                color: Colors.black45,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────
  Widget _buildList(RefereeListData data) {
    return Column(
      children: [
        // ── Summary chip ────────────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 4.h),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF003716), Color(0xFF167525)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(50.r),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B882C).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_rounded,
                  color: Colors.white, size: 16.sp),
              SizedBox(width: 8.w),
              NumericStyledText(
                '${data.count} Friend${data.count == 1 ? '' : 's'} Referred',
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ],
          ),
        ),

        // ── Cards ────────────────────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 40.h),
            itemCount: data.results.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, i) =>
                _RefereeCard(item: data.results[i], index: i),
          ),
        ),
      ],
    );
  }
}

// ── Single referee card ───────────────────────────────────────────────────────

class _RefereeCard extends StatelessWidget {
  final RefereeItem item;
  final int index;

  const _RefereeCard({required this.item, required this.index});

  // Derive chip colour from status
  _StatusStyle _style(String status) {
    switch (status.toLowerCase()) {
      case 'disbursed':
        return const _StatusStyle(
          bg: Color(0xFFDCFCE7),
          fg: Color(0xFF15803D),
          icon: Icons.check_circle_rounded,
        );
      case 'hold':
        return const _StatusStyle(
          bg: Color(0xFFFFF3CD),
          fg: Color(0xFF92400E),
          icon: Icons.hourglass_top_rounded,
        );
      case 'pending':
        return const _StatusStyle(
          bg: Color(0xFFE0F2FE),
          fg: Color(0xFF0369A1),
          icon: Icons.schedule_rounded,
        );
      case 'no reward':
        return const _StatusStyle(
          bg: Color(0xFFF1F5F9),
          fg: Color(0xFF64748B),
          icon: Icons.remove_circle_outline_rounded,
        );
      default:
        return const _StatusStyle(
          bg: Color(0xFFF1F5F9),
          fg: Color(0xFF64748B),
          icon: Icons.info_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewardStyle = _style(item.rewardStatus);
    final isGold = item.reward.toLowerCase() == 'gold';
    final hasReward = item.reward != '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────────
            Container(
              width: 46.w,
              height: 46.w,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF003716), Color(0xFF167525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  item.referee.isNotEmpty
                      ? item.referee[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(width: 14.w),

            // ── Main content ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username + date row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.referee,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        _formatDate(item.referralDate),
                        style: GoogleFonts.lora(
                          fontSize: 11.sp,
                          color: Colors.black38,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),

                  // Status chips row
                  Row(
                    children: [
                      // Join status chip
                      _chip(item.status, _style(item.status)),
                      SizedBox(width: 6.w),
                      // Reward status chip
                      _chip(item.rewardStatus, rewardStyle),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),

            // ── Reward badge ─────────────────────────────────────────────
            if (hasReward)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      gradient: isGold
                          ? const LinearGradient(
                              colors: [Color(0xFFF5A702), Color(0xFFF9D522)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [
                                Colors.grey.shade400,
                                Colors.grey.shade300,
                              ],
                            ),
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                          color: (isGold
                                  ? const Color(0xFFF5A702)
                                  : Colors.grey.shade400)
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      item.reward,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w800,
                        color: isGold
                            ? const Color(0xFF5C3300)
                            : const Color(0xFF3D3D3D),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    item.quantity == '—' ? '—' : '${item.quantity} gm',
                    style: GoogleFonts.lora(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _StatusStyle style) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(50.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 10.sp, color: style.fg),
          SizedBox(width: 3.w),
          Text(
            label,
            style: GoogleFonts.playfairDisplay(
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: style.fg,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final parts = raw.split('-');
      if (parts.length != 3) return raw;
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final m = int.tryParse(parts[1]) ?? 0;
      return '${parts[2]} ${months[m]} ${parts[0]}';
    } catch (_) {
      return raw;
    }
  }
}

class _StatusStyle {
  final Color bg;
  final Color fg;
  final IconData icon;
  const _StatusStyle({required this.bg, required this.fg, required this.icon});
}
