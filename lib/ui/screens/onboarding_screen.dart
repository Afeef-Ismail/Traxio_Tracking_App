import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// Onboarding Screen — First-launch 3-screen introduction.
///
/// Screen 1: App purpose
/// Screen 2: How it works
/// Screen 3: Privacy
/// Skip/Get Started buttons navigate to login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // ─── Page View ───────────────────────────────────────────
            PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                _OnboardingPage1(isDark: isDark, l10n: l10n),
                _OnboardingPage2(isDark: isDark, l10n: l10n),
                _OnboardingPage3(isDark: isDark, l10n: l10n),
              ],
            ),

            // ─── Skip / Get Started Buttons ──────────────────────────
            Positioned(
              top: 16,
              right: 16,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: Text(
                  l10n?.skip ?? 'Skip',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // ─── Navigation & Dots ──────────────────────────────────
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            width: _currentPage == index ? 32 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? AppColors.primary
                                  : (isDark
                                      ? AppColors.dividerDark
                                      : AppColors.dividerLight),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Navigation Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _currentPage > 0
                                  ? () {
                                      _pageController.previousPage(
                                        duration:
                                            const Duration(milliseconds: 400),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: BorderSide(
                                  color: _currentPage > 0
                                      ? AppColors.primary
                                      : AppColors.primary.withOpacity(0.3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                l10n?.previous ?? 'Previous',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _currentPage < 2
                                  ? () {
                                      _pageController.nextPage(
                                        duration:
                                            const Duration(milliseconds: 400),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  : _completeOnboarding,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _currentPage < 2
                                    ? (l10n?.next ?? 'Next')
                                    : (l10n?.getStarted ?? 'Get Started'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
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
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage1 extends StatelessWidget {
  final bool isDark;
  final AppLocalizations? l10n;

  const _OnboardingPage1({
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Icon(
            Icons.directions_bus_rounded,
            size: 60,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n?.onboardingTitle1 ??
                'Help Make Kerala Roads Safer',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n?.onboardingDesc1 ??
                'This app records how vehicles are driven to help researchers identify safer driving patterns.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingPage2 extends StatelessWidget {
  final bool isDark;
  final AppLocalizations? l10n;

  const _OnboardingPage2({
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Icon(
            Icons.sensors_rounded,
            size: 60,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n?.onboardingTitle2 ?? 'How It Works',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepText(
                num: '1',
                text: l10n?.onboardingStep1 ?? 'Mount your phone on the dashboard',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _StepText(
                num: '2',
                text: l10n?.onboardingStep2 ?? 'Calibrate the sensors (takes 10 seconds)',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _StepText(
                num: '3',
                text: l10n?.onboardingStep3 ?? 'Tap Start and drive normally',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _StepText(
                num: '4',
                text: l10n?.onboardingStep4 ??
                    'The app automatically records data every 100 metres',
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepText extends StatelessWidget {
  final String num;
  final String text;
  final bool isDark;

  const _StepText({
    required this.num,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.textOnDark
                    : AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingPage3 extends StatelessWidget {
  final bool isDark;
  final AppLocalizations? l10n;

  const _OnboardingPage3({
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Icon(
            Icons.privacy_tip_rounded,
            size: 60,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n?.onboardingTitle3 ?? 'Your Data, Your Choice',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _PrivacyBullet(
                icon: Icons.storage_rounded,
                text: l10n?.onboardingPrivacy1 ??
                    'All data stays on your phone only',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _PrivacyBullet(
                icon: Icons.cloud_off_rounded,
                text: l10n?.onboardingPrivacy2 ??
                    'Never automatically uploaded or shared',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _PrivacyBullet(
                icon: Icons.share_rounded,
                text: l10n?.onboardingPrivacy3 ??
                    'You choose when and what to share',
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;

  const _PrivacyBullet({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 32,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.textOnDark
                    : AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
