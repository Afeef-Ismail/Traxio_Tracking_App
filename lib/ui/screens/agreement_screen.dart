import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  bool _accepted = false;

  Future<void> _acceptAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('data_agreement_accepted', true);
    await prefs.setString('data_agreement_date', DateTime.now().toIso8601String());

    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      onboardingComplete ? '/login' : '/onboarding',
      (_) => false,
    );
  }

  Future<void> _decline() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notice'),
        content: const Text(
          'You must accept the agreement to use this application for data collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Collection & Research Use Agreement',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'KSRTC Driver Benchmarking System — NIT Calicut',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Section 1 — Purpose of Data Collection', isDark),
                    _sectionBody(
                      'This application collects vehicle motion and GPS data during your trips for academic research at the Centre of Excellence in Artificial Intelligence (CoE-AI), National Institute of Technology Calicut (NITC), in collaboration with the Kerala State Road Transport Corporation (KSRTC). The research aims to identify safe and fuel-efficient driving patterns on Kerala roads.',
                      isDark,
                    ),
                    _sectionTitle('Section 2 — What Data is Collected', isDark),
                    _bullet('GPS location (latitude, longitude, altitude, speed) at 10 readings per second', isDark),
                    _bullet('Vehicle motion data (acceleration, turning rate, vertical movement) from phone sensors', isDark),
                    _bullet('Derived driving behaviour features computed from the above', isDark),
                    _bullet('Trip timestamps, segment distances, and terrain information', isDark),
                    _bullet('No personal communications, contacts, photos, or identity documents are accessed', isDark),
                    const SizedBox(height: 8),
                    _sectionTitle('Section 3 — How Your Data is Used', isDark),
                    _sectionBody(
                      'Collected data is stored only on your device. Data is transferred to researchers only when you explicitly export and share it using the Export CSV function. Researchers at NIT Calicut will use this data to develop driver benchmarking models for road safety research. Data will not be sold to any third party or used for commercial purposes.',
                      isDark,
                    ),
                    _sectionTitle('Section 4 — Your Rights', isDark),
                    _bullet('You may stop data collection at any time by tapping Stop', isDark),
                    _bullet('You may request deletion of your recorded trips by contacting your supervisor', isDark),
                    _bullet('Participation is voluntary', isDark),
                    _bullet('You must be 18 years of age or older to use this application', isDark),
                    const SizedBox(height: 8),
                    _sectionTitle('Section 5 — Data Security', isDark),
                    _sectionBody(
                      'All data stored on your device is encrypted using AES-256 encryption. Your account password is stored as a secure hash and is never transmitted in plain text.',
                      isDark,
                    ),
                    _sectionTitle('Section 6 — Contact', isDark),
                    _sectionBody(
                      'For questions about this research or your data, contact: Centre of Excellence in Artificial Intelligence, NIT Calicut, Kozhikode, Kerala — 673601',
                      isDark,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _accepted,
                        onChanged: (v) => setState(() => _accepted = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _accepted = !_accepted),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I have read and understood this agreement. I am 18 years of age or older and I voluntarily agree to participate in this research.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _accepted ? _acceptAndContinue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Accept & Continue'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _decline,
                      child: const Text('Decline'),
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

  Widget _sectionTitle(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _sectionBody(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _bullet(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
