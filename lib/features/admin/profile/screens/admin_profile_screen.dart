import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Admin profile screen.
///
/// Dark-adaptive, premium card layout. Supports local profile image
/// upload (compressed bytes stored in [AuthProvider.avatarBytes]).
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);

    final rawBytes = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      rawBytes,
      quality: 75,
      minWidth: 400,
      minHeight: 400,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (!mounted) return;
    AuthProviderScope.of(context).setAvatarBytes(
      compressed.isEmpty ? rawBytes : compressed,
    );
    setState(() => _uploadingAvatar = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    final avatarBytes = auth.avatarBytes;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Profile', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor:
            isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePaddingH,
          vertical: AppConstants.pagePaddingV,
        ),
        child: Column(
          children: [
            // ── Avatar card ──────────────────────────────────────────────────
            _AvatarCard(
              user: user,
              avatarBytes: avatarBytes,
              isDark: isDark,
              isUploading: _uploadingAvatar,
              onPickImage: _pickProfileImage,
            ),
            const SizedBox(height: AppConstants.space16),

            // ── Info tiles ───────────────────────────────────────────────────
            _InfoTile(
              icon: Icons.manage_accounts_rounded,
              label: 'Role',
              value: user?.role.label ?? 'Admin',
              isDark: isDark,
            ),
            _InfoTile(
              icon: Icons.phone_rounded,
              label: 'Phone',
              value: (user?.phone?.isNotEmpty == true) ? user!.phone! : 'Not set',
              isDark: isDark,
            ),
            _InfoTile(
              icon: Icons.email_rounded,
              label: 'Email',
              value: user?.email ?? '',
              isDark: isDark,
            ),
            _InfoTile(
              icon: Icons.business_rounded,
              label: 'Organization ID',
              value: user?.organizationId ?? '—',
              isDark: isDark,
            ),

            const SizedBox(height: AppConstants.space24),

            // ── Edit profile (coming Phase B6) ───────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Profile editing will be available after backend integration.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Edit Profile',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.space12),

            // ── Settings link ────────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () => context.push(RouteNames.adminSettings),
              icon: Icon(
                Icons.settings_rounded,
                size: 18,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
              label: Text(
                'Settings',
                style: AppTypography.labelLarge.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                side: BorderSide(
                  color: isDark ? AppColors.borderDark : AppColors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.space12),

            // ── Sign out ─────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  await auth.logout();
                  if (mounted) router.go(RouteNames.roleSelect);
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(
                  'Sign Out',
                  style: AppTypography.labelLarge
                      .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.space40),
          ],
        ),
      ),
    );
  }
}

// ── Avatar card ────────────────────────────────────────────────────────────────

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.user,
    required this.avatarBytes,
    required this.isDark,
    required this.isUploading,
    required this.onPickImage,
  });

  final UserModel? user;
  final Uint8List? avatarBytes;
  final bool isDark;
  final bool isUploading;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // Tappable avatar with camera overlay
          GestureDetector(
            onTap: onPickImage,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Avatar circle
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryContainer,
                    border: Border.all(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: isUploading
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : ClipOval(
                          child: avatarBytes != null
                              ? Image.memory(
                                  avatarBytes!,
                                  fit: BoxFit.cover,
                                  width: 88,
                                  height: 88,
                                )
                              : Center(
                                  child: Text(
                                    user?.initials ?? 'A',
                                    style: AppTypography.headlineMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                ),
                // Camera badge
                if (!isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        border: Border.all(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surface,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space16),

          Text(
            user?.name ?? 'Admin',
            style: AppTypography.titleLarge.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: AppTypography.bodyMedium.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.space12),

          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.chipRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  user?.role.displayName ?? 'Admin',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info tile ──────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
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
}
