import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';

/// A premium glassmorphism greeting card for the admin dashboard header.
///
/// Shows time-aware salutation, admin name, organisation name, and
/// the current date — rendered on a gradient-backed [AppGlassCard].
class AdminGreetingCard extends StatelessWidget {
  const AdminGreetingCard({
    super.key,
    required this.adminName,
    required this.orgName,
    this.groupCount = 0,
    this.roleLabel,
  });

  final String adminName;
  final String orgName;

  /// Number of groups in the organisation. Rendered next to [orgName] as
  /// "· 5 groups". This count used to be written INTO the org name slot as a
  /// substitute ("5 Groups" instead of the organisation), so the header could
  /// show one or the other but never both. It is now its own element, so the
  /// footer reads "🏢 Acme Mess · 5 groups". 0 hides it.
  final int groupCount;

  /// #8: per-group functional role label for the selected group
  /// (e.g. "Hostel Admin"). null -> shows the generic "Admin" badge.
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final today = DateFormat('EEE, d MMM').format(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.tertiary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: AppGlassCard(
        borderRadius: 20,
        glassEnabled: true,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        borderColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting + admin badge row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting 👋',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminName,
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        roleLabel ?? 'Admin',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.2),
            ),

            const SizedBox(height: 12),

            // Org + date footer
            Row(
              children: [
                const Icon(Icons.business_rounded,
                    size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // Organisation AND group count — "Midnapore Namaste Mess · 5
                    // groups". Previously the count REPLACED the org name here,
                    // so only one could ever show; both are preserved now.
                    groupCount > 0
                        ? '$orgName · $groupCount '
                            '${groupCount == 1 ? 'group' : 'groups'}'
                        : orgName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.calendar_today_rounded,
                    size: 13, color: Colors.white60),
                const SizedBox(width: 5),
                Text(
                  today,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
