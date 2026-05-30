import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_colors.dart';
import 'consent_notice_screen.dart';

/// Login Screen — Authentication gate.
///
/// Username/email + password fields, show/hide toggle, error message.
/// Admin → AdminHomeScreen, Driver → HomeScreen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      // Set the current user's ID on TripProvider for trip attribution
      final userId = authProvider.currentUser?['id'] as int? ?? 0;
      context.read<TripProvider>().setCurrentUserId(userId);
      final route = authProvider.isAdmin ? '/admin' : '/home';
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
          Localizations.of<AppLocalizations>(context, AppLocalizations)
              ?.invalidCredentials ??
            'Invalid username or password';
      });
    }
  }

  Future<void> _setLanguage(String code) async {
    try {
      await context.read<LanguageProvider>().setLanguage(code);
    } catch (_) {
      // Ignore when LanguageProvider is not available (e.g., isolated widget tests)
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n =
      Localizations.of<AppLocalizations>(context, AppLocalizations);
    final currentLanguageCode =
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ─── Logo ────────────────────────────────────────────
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_bus_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // ─── Title ───────────────────────────────────────────
                Text(
                  'Traxio',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n?.appName ?? 'Vehicle Motion Data Collection & Driver Benchmarking',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),

                // ─── Login Form ──────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Username / Email
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Username or Email',
                          prefixIcon: const Icon(Icons.person_outline),
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkCard
                              : AppColors.lightCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
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
                            return 'Username or Email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          labelText: l10n?.password ?? 'Password',
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
                          fillColor: isDark
                              ? AppColors.darkCard
                              : AppColors.lightCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.dividerDark
                                  : AppColors.dividerLight,
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
                          if (value == null || value.isEmpty) {
                            return l10n?.password ?? 'Password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ─── Error Message ─────────────────────────────
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LanguageButton(
                            label: l10n?.english ?? 'English',
                            selected: currentLanguageCode == 'en',
                            onTap: () => _setLanguage('en'),
                          ),
                          const SizedBox(width: 8),
                          _LanguageButton(
                            label: 'മലയാളം',
                            selected: currentLanguageCode == 'ml',
                            onTap: () => _setLanguage('ml'),
                          ),
                          const SizedBox(width: 8),
                          _LanguageButton(
                            label: 'हिन्दी',
                            selected: currentLanguageCode == 'hi',
                            onTap: () => _setLanguage('hi'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ─── Login Button ──────────────────────────────
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
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
                                  l10n?.login ?? 'Login',
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

                // ─── Developer Quick Login (Demo Mode Only) ─────────
                if (AppConstants.demoMode)
                  _DeveloperQuickLoginButtons(
                    isLoading: _isLoading,
                    onQuickLogin: (username, password) {
                      _usernameController.text = username;
                      _passwordController.text = password;
                      _handleLogin();
                    },
                  ),

                const SizedBox(height: 20),

                // ─── Create Account Link ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n?.dontHaveAccount ?? "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final username = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const ConsentNoticeScreen(),
                          ),
                        );

                          if (username != null && mounted) {
                          _usernameController.text = username;
                        }
                      },
                      child: Text(
                        l10n?.signUp ?? 'Sign Up',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // ─── Footer ──────────────────────────────────────────
                Text(
                  'NIT Calicut × Traxio',
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
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Developer Quick Login Buttons — only shown when demoMode = true.
// Three small outlined buttons styled as dev-tools, not production UI.
// ═══════════════════════════════════════════════════════════════════════

class _DeveloperQuickLoginButtons extends StatelessWidget {
  final bool isLoading;
  final void Function(String username, String password) onQuickLogin;

  const _DeveloperQuickLoginButtons({
    required this.isLoading,
    required this.onQuickLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Divider(color: Colors.grey[300], thickness: 0.5),
          const SizedBox(height: 6),
          Text(
            'DEV QUICK LOGIN',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _devButton('Login as Admin', 'admin', 'admin123'),
              _devButton('Login as Driver', 'driver', 'driver123'),
              _devButton('Login as Test Driver', 'testdriver', 'test123'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _devButton(String label, String username, String password) {
    return OutlinedButton(
      onPressed: isLoading ? null : () => onQuickLogin(username, password),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey[600],
        side: BorderSide(color: Colors.grey[400]!),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(label),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.primary : Colors.grey,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
