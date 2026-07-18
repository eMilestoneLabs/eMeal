import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/shared/widgets/app_analytics_card.dart';

/// A horizontal scrollable row of [AppAnalyticsCard] widgets showing
/// headline KPIs for the admin dashboard.
///
/// Displays: Total Members · Present Today · Absent Today · Rate %
class StatsSummaryRow extends StatelessWidget {
  const StatsSummaryRow({
    super.key,
    required this.totalMembers,
    required this.presentToday,
    required this.absentToday,
    required this.attendanceRate,
  });

  final int totalMembers;
  final int presentToday;
  final int absentToday;
  final double attendanceRate;

  @override
  Widget build(BuildContext context) {
    final ratePercent = (attendanceRate * 100).toStringAsFixed(0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AppAnalyticsCard(
            label: 'Total Members',
            value: '$totalMembers',
            icon: Icons.people_rounded,
            iconColor: AppColors.primary,
            compact: true,
            vibrant: true,
          ),
          const SizedBox(width: 10),
          AppAnalyticsCard(
            label: 'Present Today',
            value: '$presentToday',
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.present,
            compact: true,
            vibrant: true,
          ),
          const SizedBox(width: 10),
          AppAnalyticsCard(
            label: 'Absent Today',
            value: '$absentToday',
            icon: Icons.cancel_rounded,
            iconColor: AppColors.absent,
            compact: true,
            vibrant: true,
          ),
          const SizedBox(width: 10),
          AppAnalyticsCard(
            label: 'Attendance Rate',
            value: '$ratePercent%',
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.vacation,
            compact: true,
            vibrant: true,
            deltaPositive: attendanceRate >= 0.75,
          ),
        ],
      ),
    );
  }
}
