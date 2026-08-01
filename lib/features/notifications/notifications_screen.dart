import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/numeric_styled_text.dart';

import '../../core/services/notification_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/widgets/gradient_header.dart';
import '../../shared/widgets/app_toast.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // FCM is a trigger — always fetch fresh data from API on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUnread = state.notifications.any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Notifications',
            trailing: hasUnread && !state.isLoading
                ? GestureDetector(
                    onTap: _onMarkAllRead,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100.r),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all_rounded,
                              size: 14.sp, color: Colors.white),
                          SizedBox(width: 4.w),
                          Text(
                            'Mark All Read',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: state.isLoading
                ? _buildShimmerList()
                : state.error != null
                    ? _buildError(state.error!, isDark)
                    : state.notifications.isEmpty
                        ? _buildEmpty(isDark)
                        : _buildList(state, isDark),
          ),
        ],
      ),
    );
  }

  // ── Mark all read ──────────────────────────────────────────────────────────

  void _onMarkAllRead() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          'Mark All as Read',
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
        ),
        content: Text(
          'Are you sure you want to mark all notifications as read?',
          style: GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            color: Colors.black54,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.playfairDisplay(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(notificationProvider.notifier).markAllAsRead();
            },
            child: Text('Confirm',
                style: GoogleFonts.playfairDisplay(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Widget _buildList(NotificationState state, bool isDark) {
    return RefreshIndicator(
      color: AppTheme.primaryGreen,
      onRefresh: () => ref.read(notificationProvider.notifier).load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        itemCount: state.notifications.length,
        separatorBuilder: (_, __) => SizedBox(height: 10.h),
        itemBuilder: (context, index) {
          final notif = state.notifications[index];
          return _buildDismissibleCard(notif, isDark);
        },
      ),
    );
  }

  // ── Dismissible card (swipe to delete) ──────────────────────────────────────

  Widget _buildDismissibleCard(AppNotification notif, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: Dismissible(
        key: ValueKey(notif.id),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {DismissDirection.endToStart: 0.35},
        movementDuration: const Duration(milliseconds: 200),
        confirmDismiss: (_) async {
          HapticFeedback.mediumImpact();
          final success = await ref
              .read(notificationProvider.notifier)
              .deleteNotification(notif.id);
          if (success && mounted) {
            AppToast.show(context, 'Notification removed',
                type: ToastType.info);
          }
          return success;
        },
        background: Container(
          color: const Color(0xFFDC2626),
          alignment: Alignment.centerRight,
          padding: EdgeInsets.only(right: 28.w),
          child: Icon(
            Icons.delete_rounded,
            color: Colors.white,
            size: 24.sp,
          ),
        ),
        child: _buildCard(notif, isDark),
      ),
    );
  }

  // ── Card ────────────────────────────────────────────────────────────────────

  Widget _buildCard(AppNotification notif, bool isDark) {
    final isUnread = !notif.isRead;

    return GestureDetector(
      onTap: () {
        if (isUnread) {
          ref.read(notificationProvider.notifier).markAsRead(notif.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: isUnread
              ? (isDark
                  ? AppTheme.primaryGreen.withOpacity(0.08)
                  : const Color(0xFFF0FDF4))
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isUnread
                ? AppTheme.primaryGreen.withOpacity(0.25)
                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(14.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _typeColor(notif.type).withOpacity(0.12),
                ),
                child: Icon(
                  _typeIcon(notif.type),
                  color: _typeColor(notif.type),
                  size: 20.sp,
                ),
              ),
              SizedBox(width: 12.w),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 13.sp,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8.w,
                            height: 8.w,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    NumericStyledText(
                      notif.message,
                      fontSize: 12.sp,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 11.sp,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          notif.createdAt,
                          style: GoogleFonts.lora(
                            fontSize: 10.sp,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shimmer loading ────────────────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: 6,
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder: (_, __) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Circle shimmer
          Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120.w,
                  height: 14.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  width: double.infinity,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(height: 4.h),
                Container(
                  width: 180.w,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  width: 80.w,
                  height: 10.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty / Error ─────────────────────────────────────────────────────────

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(24.r),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryGreen.withOpacity(0.08),
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: 48.sp, color: AppTheme.primaryGreen),
          ),
          SizedBox(height: 20.h),
          Text(
            'No Notifications Yet',
            style: AppTextStyles.titleMedium(isDark),
          ),
          SizedBox(height: 8.h),
          Text(
            'You\'re all caught up! Alerts and\nupdates will appear here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              color: isDark ? Colors.white38 : Colors.black45,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48.sp, color: Colors.redAccent),
          SizedBox(height: 16.h),
          Text(
            'Failed to load notifications',
            style: GoogleFonts.playfairDisplay(
                fontSize: 15.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8.h),
          TextButton(
            onPressed: () =>
                ref.read(notificationProvider.notifier).load(),
            child: Text('Retry',
                style: GoogleFonts.playfairDisplay(color: AppTheme.primaryGreen)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'market':
        return Icons.show_chart_rounded;
      case 'transaction':
        return Icons.receipt_long_rounded;
      case 'kyc':
        return Icons.verified_user_rounded;
      case 'withdrawal':
        return Icons.account_balance_wallet_rounded;
      case 'offer':
        return Icons.local_offer_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'market':
        return const Color(0xFF0284C7);
      case 'transaction':
        return AppTheme.primaryGreen;
      case 'kyc':
        return const Color(0xFF7C3AED);
      case 'withdrawal':
        return const Color(0xFFD97706);
      case 'offer':
        return const Color(0xFFDB2777);
      default:
        return AppTheme.primaryGreen;
    }
  }
}
