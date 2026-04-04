import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/calibration_service.dart';
import '../theme/app_colors.dart';

/// Guided sensor calibration screen.
///
/// Step 1 — Mount phone in driving position and keep still.
///          A stability ring fills up as the phone stays still.
/// Step 2 — Auto-records calibration samples (5-second countdown).
/// Step 3 — Shows calibration result in plain language.
class CalibrationScreen extends StatefulWidget {
  final bool showContinueButton;

  const CalibrationScreen({
    super.key,
    this.showContinueButton = false,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with TickerProviderStateMixin {
  final CalibrationService _calibrationService = CalibrationService();

  StreamSubscription<CalibrationProgress>? _calibrationSub;
  CalibrationPhase _phase = CalibrationPhase.waitingForStillness;
  double _stabilityProgress = 0.0;
  double _recordingProgress = 0.0;
  int _countdown = 5;
  bool _failed = false;

  late AnimationController _ringController;
  late Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _ringAnimation =
        Tween<double>(begin: 0.0, end: 0.0).animate(_ringController);
    _startCalibration();
  }

  @override
  void dispose() {
    _calibrationSub?.cancel();
    _calibrationService.stopCalibration();
    _ringController.dispose();
    super.dispose();
  }

  void _startCalibration() {
    setState(() {
      _phase = CalibrationPhase.waitingForStillness;
      _stabilityProgress = 0.0;
      _recordingProgress = 0.0;
      _countdown = 5;
      _failed = false;
    });

    _calibrationSub?.cancel();
    final stream = _calibrationService.startCalibration();
    _calibrationSub = stream.listen(
      _onProgress,
      onError: (_) {
        if (mounted) {
          setState(() => _failed = true);
        }
      },
    );
  }

  void _onProgress(CalibrationProgress progress) {
    if (!mounted) return;
    setState(() {
      _phase = progress.phase;
      _stabilityProgress = progress.stabilityProgress;
      _recordingProgress = progress.recordingProgress;
      _countdown = progress.countdown;
    });

    // Animate the ring
    _ringAnimation = Tween<double>(
      begin: _ringAnimation.value,
      end: progress.phase == CalibrationPhase.recording
          ? progress.recordingProgress
          : progress.stabilityProgress,
    ).animate(CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOut,
    ));
    _ringController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Sensor Calibration'),
        backgroundColor:
            isDark ? AppColors.darkCard : AppColors.lightCard,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              _buildStepContent(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(bool isDark) {
    if (_failed) return _buildFailedState(isDark);

    switch (_phase) {
      case CalibrationPhase.waitingForStillness:
        return _buildStillnessStep(isDark);
      case CalibrationPhase.recording:
        return _buildRecordingStep(isDark);
      case CalibrationPhase.complete:
        return _buildCompleteStep(isDark);
    }
  }

  Widget _buildStillnessStep(bool isDark) {
    return Column(
      children: [
        _buildStepIndicator(isDark, step: 1),
        const SizedBox(height: 32),
        Icon(
          Icons.smartphone_rounded,
          size: 64,
          color: AppColors.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Mount your phone in the position\nyou will use during driving.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Keep the phone completely still.\nThe circle below will fill up when stable.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 48),
        _buildStabilityRing(isDark),
        const SizedBox(height: 24),
        if (_stabilityProgress > 0)
          Text(
            '${(_stabilityProgress * 100).toInt()}% stable',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingStep(bool isDark) {
    final secondsLeft = max(0, (_countdown ~/ 10) + 1);
    return Column(
      children: [
        _buildStepIndicator(isDark, step: 2),
        const SizedBox(height: 32),
        Icon(
          Icons.fiber_manual_record_rounded,
          size: 64,
          color: AppColors.alert,
        ),
        const SizedBox(height: 24),
        Text(
          'Recording calibration data...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Keep the phone still for a few more seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 48),
        _buildStabilityRing(isDark, isRecording: true),
        const SizedBox(height: 24),
        Text(
          '$secondsLeft',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteStep(bool isDark) {
    final pitchDeg = _calibrationService.pitchDegrees;
    final rollDeg = _calibrationService.rollDegrees;

    return Column(
      children: [
        _buildStepIndicator(isDark, step: 3),
        const SizedBox(height: 32),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 48,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Calibration Complete!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your phone position has been saved.\nThe app will now measure only your driving motions.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        // Tilt info card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
          ),
          child: Column(
            children: [
              Text(
                'Phone tilt detected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTiltInfo(
                    label: 'Forward',
                    degrees: pitchDeg,
                    isDark: isDark,
                  ),
                  _buildTiltInfo(
                    label: 'Sideways',
                    degrees: rollDeg,
                    isDark: isDark,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _startCalibration,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Recalibrate'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (widget.showContinueButton) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Trip'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFailedState(bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.warning_rounded, size: 64, color: AppColors.warning),
        const SizedBox(height: 24),
        Text(
          'Calibration Failed',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Please keep the phone completely still and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _startCalibration,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStabilityRing(bool isDark, {bool isRecording = false}) {
    return AnimatedBuilder(
      animation: _ringAnimation,
      builder: (context, child) {
        final value = isRecording ? _recordingProgress : _stabilityProgress;
        final color = isRecording ? AppColors.alert : AppColors.primary;

        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 12,
                backgroundColor:
                    isDark ? AppColors.dividerDark : AppColors.dividerLight,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Icon(
                isRecording
                    ? Icons.fiber_manual_record_rounded
                    : Icons.smartphone_rounded,
                size: 48,
                color: color.withOpacity(0.8),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepIndicator(bool isDark, {required int step}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 2, 3].map((s) {
        final isActive = s == step;
        final isDone = s < step ||
            (step == 3 && _phase == CalibrationPhase.complete);
        return Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone || isActive
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.dividerDark
                        : AppColors.dividerLight),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : Text(
                        '$s',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : (isDark
                                  ? AppColors.textOnDarkSecondary
                                  : AppColors.textMuted),
                        ),
                      ),
              ),
            ),
            if (s < 3)
              Container(
                width: 32,
                height: 2,
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTiltInfo({
    required String label,
    required double degrees,
    required bool isDark,
  }) {
    final absAngle = degrees.abs().toStringAsFixed(1);
    final direction = label == 'Forward'
        ? (degrees > 0 ? 'tilted back' : 'tilted forward')
        : (degrees > 0 ? 'tilted right' : 'tilted left');

    return Column(
      children: [
        Text(
          '$absAngle°',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          direction,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
