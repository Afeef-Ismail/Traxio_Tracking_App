import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../database/db_helper.dart';
import '../theme/app_colors.dart';

/// Signup Screen — Self-registration for new drivers.
///
/// Collects: Full name, username, password, confirm password, age checkbox,
/// vehicle type (optional), vehicle number (optional).
/// On success: Creates user in DB, shows success message, navigates to login.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _vehicleNumberController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _ageConfirmed = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedVehicleType = '';

  final List<String> _vehicleTypes = [
    'Bus',
    'Minibus',
    'Car',
    'Auto',
    'Bike',
    'Other'
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_ageConfirmed) {
      setState(() {
        _errorMessage = Localizations.of<AppLocalizations>(context, AppLocalizations)
            ?.ageConfirmationRequired ??
            'You must confirm that you are 18 years or older';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final db = DbHelper();

    // Check if username already exists
    final existingUser = await db.getUserByUsername(_usernameController.text.trim());
    if (existingUser != null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = Localizations.of<AppLocalizations>(context, AppLocalizations)
              ?.usernameAlreadyExists ??
              'Username already exists. Please choose a different one.';
        });
      }
      return;
    }

    // Create user
    final passwordHash = DbHelper.hashPassword(_passwordController.text);
    try {
      await db.createUser(
        _usernameController.text.trim(),
        passwordHash,
        'driver',
        vehicleType: _selectedVehicleType,
        vehicleNumber: _vehicleNumberController.text.trim(),
      );

      if (mounted) {
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.of<AppLocalizations>(context, AppLocalizations)
                  ?.accountCreatedSuccessfully ??
                  'Account created successfully. Please sign in.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate back to login with username pre-filled
        Navigator.of(context).pop(_usernameController.text.trim());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = Localizations.of<AppLocalizations>(context, AppLocalizations)
              ?.signupFailed ??
              'Signup failed. Please try again.';
        });
      }
    }
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.usernameRequired ??
          'Username is required';
    }
    if (value.length < 4) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.usernameMinLength ??
          'Username must be at least 4 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value)) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.usernameAlphanumeric ??
          'Username must contain only alphanumeric characters (no spaces)';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.passwordRequired ??
          'Password is required';
    }
    if (value.length < 6) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.passwordMinLength ??
          'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.confirmPasswordRequired ??
          'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return Localizations.of<AppLocalizations>(context, AppLocalizations)
          ?.passwordsMustMatch ??
          'Passwords do not match';
    }
    return null;
  }

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
          l10n?.createAccount ?? 'Create Account',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── Full Name ───────────────────────────────────────
                Text(
                  l10n?.fullName ?? 'Full Name',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l10n?.enterFullName ?? 'Enter your full name',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n?.fullNameRequired ?? 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ─── Username ────────────────────────────────────────
                Text(
                  l10n?.username ?? 'Username',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l10n?.enterUsername ?? 'Enter username (4+ characters)',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: _validateUsername,
                ),
                const SizedBox(height: 20),

                // ─── Password ────────────────────────────────────────
                Text(
                  l10n?.password ?? 'Password',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l10n?.enterPassword ?? 'Enter password (6+ characters)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 20),

                // ─── Confirm Password ─────────────────────────────────
                Text(
                  l10n?.confirmPassword ?? 'Confirm Password',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: l10n?.confirmPasswordHint ?? 'Re-enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: _validateConfirmPassword,
                ),
                const SizedBox(height: 20),

                // ─── Vehicle Type ────────────────────────────────────
                Text(
                  l10n?.vehicleType ?? 'Vehicle Type (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedVehicleType.isEmpty ? null : _selectedVehicleType,
                  decoration: InputDecoration(
                    hintText: l10n?.selectVehicleType ?? 'Select vehicle type',
                    prefixIcon: const Icon(Icons.directions_bus_rounded),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                  ),
                  items: _vehicleTypes
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleType = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 20),

                // ─── Vehicle Number ──────────────────────────────────
                Text(
                  l10n?.vehicleNumber ?? 'Vehicle Number (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _vehicleNumberController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: l10n?.enterVehicleNumber ?? 'Optional: Vehicle registration number',
                    prefixIcon: const Icon(Icons.tag_outlined),
                    filled: true,
                    fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ─── Age Confirmation Checkbox ──────────────────────
                Row(
                  children: [
                    Checkbox(
                      value: _ageConfirmed,
                      onChanged: (value) {
                        setState(() {
                          _ageConfirmed = value ?? false;
                        });
                      },
                      activeColor: AppColors.primary,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _ageConfirmed = !_ageConfirmed;
                          });
                        },
                        child: Text(
                          l10n?.ageConfirmation ??
                              'I confirm that I am 18 years of age or older',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.textOnDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ─── Error Message ───────────────────────────────────
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.alert,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.alert,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ─── Submit Button ───────────────────────────────────
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            l10n?.createAccount ?? 'Create Account',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
