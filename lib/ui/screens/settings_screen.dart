import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';

/// Settings Screen — minimal configuration options.
///
/// Includes:
///   - Slope threshold input
///   - Sensor calibration button
///   - Export trip data (CSV)
///   - Dark mode toggle
class SettingsScreen extends StatefulWidget {
  /// Callback to toggle dark mode in the app root.
  final ValueChanged<bool>? onDarkModeChanged;

  const SettingsScreen({super.key, this.onDarkModeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _slopeThreshold = 0.02;
  bool _darkMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _slopeThreshold = prefs.getDouble('slope_threshold') ?? 0.02;
      _darkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('slope_threshold', _slopeThreshold);
    await prefs.setBool('dark_mode', _darkMode);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsSaved),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = context.watch<LanguageProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Slope Threshold ─────────────────────────────────────
            _SettingSection(
              title: 'Terrain Classification',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slope Threshold',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textOnDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Segments with slope above this value are classified as Uphill/Downhill',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _slopeThreshold,
                          min: 0.005,
                          max: 0.10,
                          divisions: 19,
                          activeColor: AppColors.primary,
                          label: _slopeThreshold.toStringAsFixed(3),
                          onChanged: (v) {
                            setState(() => _slopeThreshold = v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          _slopeThreshold.toStringAsFixed(3),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textOnDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Sensor Calibration ──────────────────────────────────
            _SettingSection(
              title: 'Sensor',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calibrate sensors while the phone is stationary on a flat surface.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Calibrate Sensors',
                    icon: Icons.tune_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Place phone on flat surface and start a trip. '
                            'Calibration happens automatically during the first 2 seconds.',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Export Data ─────────────────────────────────────────
            _SettingSection(
              title: 'Data',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export all trip data as CSV files for analysis.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Export Trip Data (CSV)',
                    icon: Icons.file_download_outlined,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CSV export coming soon'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Appearance ──────────────────────────────────────────
            _SettingSection(
              title: l10n.appearance,
              isDark: isDark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.darkMode,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Reduce glare for night driving',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textOnDarkSecondary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _darkMode,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() => _darkMode = v);
                      widget.onDarkModeChanged?.call(v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _SettingSection(
              title: l10n.language,
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _languageOption(
                    context,
                    code: 'en',
                    label: l10n.english,
                    selected: languageProvider.locale.languageCode == 'en',
                  ),
                  _languageOption(
                    context,
                    code: 'ml',
                    label: 'മലയാളം',
                    selected: languageProvider.locale.languageCode == 'ml',
                  ),
                  _languageOption(
                    context,
                    code: 'hi',
                    label: 'हिन्दी',
                    selected: languageProvider.locale.languageCode == 'hi',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Save Button ─────────────────────────────────────────
            PrimaryButton(
              label: l10n.saveSettings,
              icon: Icons.save_rounded,
              loading: _saving,
              onPressed: _saveSettings,
            ),
            const SizedBox(height: 16),

            // ─── Logout ──────────────────────────────────────────────
            _SettingSection(
              title: l10n.account,
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign out of the current session.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        context.read<AuthProvider>().logout();
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/login', (_) => false);
                      },
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text(l10n.logout),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.alert,
                        side: BorderSide(
                          color: AppColors.alert.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── App Info ────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Text(
                    'KSRTC Benchmarking v1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kozhikode – Sulthan Bathery Route',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(
    BuildContext context, {
    required String code,
    required String label,
    required bool selected,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: () => context.read<LanguageProvider>().setLanguage(code),
    );
  }
}

class _SettingSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;

  const _SettingSection({
    required this.title,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
