import 'package:flutter/material.dart';
import '../../config/constants.dart';
import '../../database/db_helper.dart';
import '../theme/app_colors.dart';

/// Driver Management Screen — admin CRUD for driver accounts.
///
/// List all drivers, add new driver, delete driver.
/// Cannot delete admin accounts.
class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  final DbHelper _db = DbHelper();
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    final drivers = await _db.getAllDrivers();
    if (mounted) {
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
    }
  }

  Future<void> _showAddDriverDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final busNumberController = TextEditingController();
    String? errorText;
    String? busWarning;
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Driver'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon:
                            const Icon(Icons.person_outline, size: 20),
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon:
                            const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() => obscure = !obscure);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: busNumberController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Bus Number (optional)',
                        hintText: 'e.g. KL-11-A-1234',
                        prefixIcon:
                            const Icon(Icons.directions_bus_outlined, size: 20),
                        helperText: busWarning,
                        helperStyle: const TextStyle(
                            color: Colors.orange, fontSize: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) {
                        final warn = _validateBusNumber(v);
                        if (warn != busWarning) {
                          setDialogState(() => busWarning = warn);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final username = usernameController.text.trim();
                    final password = passwordController.text;

                    if (username.isEmpty || password.isEmpty) {
                      setDialogState(() {
                        errorText = 'Username and password required';
                      });
                      return;
                    }

                    if (password.length < 4) {
                      setDialogState(() {
                        errorText = 'Password must be at least 4 characters';
                      });
                      return;
                    }

                    // Check if username already exists
                    final existing = await _db.getUserByUsername(username);
                    if (!ctx.mounted) return;
                    if (existing != null) {
                      setDialogState(() {
                        errorText = 'Username already exists';
                      });
                      return;
                    }

                    final hash = DbHelper.hashPassword(password);
                    await _db.createUser(username, hash, 'driver',
                        busNumber: busNumberController.text.trim());
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!mounted) return;
                    _loadDrivers();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    busNumberController.dispose();
  }

  Future<void> _confirmDeleteDriver(Map<String, dynamic> driver) async {
    final username = driver['username'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Driver?'),
        content: Text(
          'Are you sure you want to delete driver "$username"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteUser(driver['id'] as int);
      if (!mounted) return;
      _loadDrivers();
    }
  }

  /// Demo-only: quickly add a test driver without dialog.
  Future<void> _quickAddTestDriver() async {
    final existing = await _db.getUserByUsername('testdriver');
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('testdriver already exists')),
        );
      }
      return;
    }
    final hash = DbHelper.hashPassword('test123');
    await _db.createUser('testdriver', hash, 'driver');
    _loadDrivers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added testdriver / test123')),
      );
    }
  }

  /// Soft-validate Kerala bus number format.
  /// Returns a warning message or null if looks valid.
  static String? _validateBusNumber(String value) {
    if (value.isEmpty) return null;
    // Accept KL-DD-XXXX, KL DD XXXX, or similar Kerala plates
    final normalized = value.replaceAll(' ', '-').toUpperCase();
    final pattern = RegExp(r'^KL-\d{2}-[A-Z0-9-]+$');
    if (!pattern.hasMatch(normalized)) {
      return 'Expected format: KL-DD-XXXX (e.g. KL-11-A-1234)';
    }
    return null;
  }

  Future<void> _showEditBusNumberDialog(Map<String, dynamic> driver) async {
    final controller = TextEditingController(
      text: driver['bus_number'] as String? ?? '',
    );
    String? busWarning;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Edit Bus Number — ${driver['username']}'),
              content: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Bus Number',
                  hintText: 'e.g. KL-11-A-1234',
                  prefixIcon:
                      const Icon(Icons.directions_bus_outlined, size: 20),
                  helperText: busWarning,
                  helperStyle:
                      const TextStyle(color: Colors.orange, fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (v) {
                  final warn = _validateBusNumber(v);
                  if (warn != busWarning) {
                    setDialogState(() => busWarning = warn);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _db.updateBusNumber(
                      driver['id'] as int,
                      controller.text.trim(),
                    );
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!mounted) return;
                    _loadDrivers();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (AppConstants.demoMode)
            TextButton(
              onPressed: _quickAddTestDriver,
              child: const Text('+ testdriver',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDriverDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Driver'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _drivers.isEmpty
                ? _buildEmptyState(isDark)
                : _buildDriverList(isDark),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No drivers registered',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Driver" to create a new account',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _drivers.length,
      itemBuilder: (context, index) {
        final driver = _drivers[index];
        final username = driver['username'] as String;
        final busNumber = driver['bus_number'] as String? ?? '';
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          driver['created_at'] as int,
        );
        final dateStr =
            '${createdAt.day}/${createdAt.month}/${createdAt.year}';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.12),
              child: Text(
                username[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            title: Text(
              username,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textOnDark
                    : AppColors.textPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busNumber.isNotEmpty)
                  Text(
                    'Bus: $busNumber',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                Text(
                  'Added $dateStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                  tooltip: 'Edit Bus Number',
                  onPressed: () => _showEditBusNumberDialog(driver),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.alert.withOpacity(0.7),
                  ),
                  onPressed: () => _confirmDeleteDriver(driver),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
