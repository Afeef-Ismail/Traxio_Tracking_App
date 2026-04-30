import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import 'signup_screen.dart';

/// Consent Notice Screen — Privacy and data collection notice before signup.
///
/// Explains what data is collected, why, and where it's stored.
/// Must be accepted before proceeding to signup form.
class ConsentNoticeScreen extends StatefulWidget {
  const ConsentNoticeScreen({super.key});

  @override
  State<ConsentNoticeScreen> createState() => _ConsentNoticeScreenState();
}

class _ConsentNoticeScreenState extends State<ConsentNoticeScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n?.privacyAndConsent ?? 'Privacy & Consent',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Title ───────────────────────────────────────
                    Text(
                      l10n?.dataCollectionNotice ?? 'Data Collection Notice',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── What We Collect ────────────────────────────
                    _SectionTitle(
                      title: l10n?.whatWeCollect ?? 'What We Collect',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _BulletPoint(
                      text: l10n?.collectGPS ?? 'GPS location data',
                      isDark: isDark,
                    ),
                    _BulletPoint(
                      text: l10n?.collectMotion ?? 'Vehicle motion sensor data (acceleration, rotation)',
                      isDark: isDark,
                    ),
                    _BulletPoint(
                      text: l10n?.collectBehavior ?? 'Driving behavior patterns',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // ─── Why We Collect ─────────────────────────────
                    _SectionTitle(
                      title: l10n?.whyWeCollect ?? 'Why We Collect This Data',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _BulletPoint(
                      text: l10n?.researchPurpose ??
                          'Research at NIT Calicut to identify safer driving patterns',
                      isDark: isDark,
                    ),
                    _BulletPoint(
                      text: l10n?.improveRoadSafety ?? 'Improve road safety in Kerala',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // ─── How We Store ───────────────────────────────
                    _SectionTitle(
                      title: l10n?.howWeStore ?? 'How Your Data Is Stored',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _BulletPoint(
                      text: l10n?.dataStoredDevice ??
                          'All data is stored on your device only',
                      isDark: isDark,
                    ),
                    _BulletPoint(
                      text: l10n?.noAutomaticShare ??
                          'Data is never automatically shared or uploaded',
                      isDark: isDark,
                    ),
                    _BulletPoint(
                      text: l10n?.youDecideShare ??
                          'You decide when and what to share by exporting and sending',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // ─── Additional Info ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCard
                            : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                        ),
                      ),
                      child: Text(
                        l10n?.consentDisclaimer ??
                            'By clicking "I understand and agree", you confirm that you have read and understand this notice and agree to the collection of this data for research purposes.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textOnDarkSecondary
                              : AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ─── Action Buttons ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final username = await navigator.push<String>(
                          MaterialPageRoute(
                            builder: (_) => const SignupScreen(),
                          ),
                        );
                        if (username != null && mounted) {
                          navigator.pop(username);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        l10n?.iUnderstandAndAgree ??
                            'I Understand and Agree',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // Go back to login
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n?.cancel ?? 'Cancel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({
    required this.title,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  final bool isDark;

  const _BulletPoint({
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8, right: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
