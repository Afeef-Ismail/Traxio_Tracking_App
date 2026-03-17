import 'package:flutter/material.dart';
import '../../config/constants.dart';
import '../../database/db_helper.dart';
import '../theme/app_colors.dart';

String? _validateBusNumber(String value) {
  if (value.isEmpty) return null;
  final normalized = value.replaceAll(' ', '-').toUpperCase();
  final pattern = RegExp(r'^KL-\d{2}-[A-Z0-9-]+$');
  if (!pattern.hasMatch(normalized)) {
    return 'Expected format: KL-DD-XXXX (e.g. KL-11-A-1234)';
  }
  return null;
}

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
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddDriverDialog(),
    );
    if (result == true && mounted) {
      _loadDrivers();
    }
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

  Future<void> _showEditBusNumberDialog(Map<String, dynamic> driver) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EditBusNumberDialog(
        driverId: driver['id'] as int,
        username: driver['username'] as String,
        currentBusNumber: driver['bus_number'] as String? ?? '',
      ),
    );
    if (result == true && mounted) {
      _loadDrivers();
    }
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

class _AddDriverDialog extends StatefulWidget {
  const _AddDriverDialog();

  @override
  State<_AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends State<_AddDriverDialog> {
  final DbHelper _db = DbHelper();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _busNumberController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;
  String? _busWarning;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _busNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password required');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final existing = await _db.getUserByUsername(username);
      if (!mounted) return;
      if (existing != null) {
        setState(() {
          _error = 'Username already exists';
          _isLoading = false;
        });
        return;
      }

      final hash = DbHelper.hashPassword(password);
      await _db.createUser(
        username,
        hash,
        'driver',
        busNumber: _busNumberController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Driver'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _busNumberController,
              textCapitalization: TextCapitalization.characters,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'Bus Number (optional)',
                hintText: 'e.g. KL-11-A-1234',
                prefixIcon: const Icon(Icons.directions_bus_outlined, size: 20),
                helperText: _busWarning,
                helperStyle: const TextStyle(color: Colors.orange, fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (v) {
                final warn = _validateBusNumber(v);
                if (warn != _busWarning) {
                  setState(() => _busWarning = warn);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _EditBusNumberDialog extends StatefulWidget {
  final int driverId;
  final String username;
  final String currentBusNumber;

  const _EditBusNumberDialog({
    required this.driverId,
    required this.username,
    required this.currentBusNumber,
  });

  @override
  State<_EditBusNumberDialog> createState() => _EditBusNumberDialogState();
}

class _EditBusNumberDialogState extends State<_EditBusNumberDialog> {
  final DbHelper _db = DbHelper();
  late final TextEditingController _controller;
  bool _isLoading = false;
  String? _busWarning;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentBusNumber);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _db.updateBusNumber(widget.driverId, _controller.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Bus Number — ${widget.username}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Bus Number',
              hintText: 'e.g. KL-11-A-1234',
              errorText: _error,
              prefixIcon: const Icon(Icons.directions_bus_outlined, size: 20),
              helperText: _busWarning,
              helperStyle: const TextStyle(color: Colors.orange, fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) {
              final warn = _validateBusNumber(v);
              if (warn != _busWarning) {
                setState(() => _busWarning = warn);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
