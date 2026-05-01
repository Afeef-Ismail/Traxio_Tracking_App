import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import 'data_collection_screen.dart';
import 'data_collected_screen.dart';
import 'driver_profile_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'trip_history_screen.dart';

class MainShellScreen extends StatefulWidget {
  final ValueChanged<bool>? onDarkModeChanged;

  const MainShellScreen({super.key, this.onDarkModeChanged});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  bool _initialIndexLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialIndexLoaded) return;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _currentIndex = args?['initialTab'] as int? ?? 0;
    _initialIndexLoaded = true;
  }

  void _selectIndex(int index) {
    Navigator.of(context).pop();
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void _showHelpSheet() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkCard
          : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.help,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _FaqTile(
                  question: l10n.faqWhatRecordedQ,
                  answer: l10n.faqWhatRecordedA,
                ),
                _FaqTile(
                  question: l10n.faqInternetQ,
                  answer: l10n.faqInternetA,
                ),
                _FaqTile(
                  question: l10n.faqShareDataQ,
                  answer: l10n.faqShareDataA,
                ),
                _FaqTile(
                  question: l10n.faqStorageQ,
                  answer: l10n.faqStorageA,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _logout() {
    Navigator.of(context).pop();
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;
    final displayName = currentUser?['username'] as String? ?? 'Driver';
    final vehicleType = currentUser?['vehicle_type'] as String? ?? '';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Traxio'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicleType.isEmpty ? 'Unknown vehicle type' : vehicleType,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _DrawerItem(
                      icon: Icons.sensors,
                      label: l10n.dataCollection,
                      selected: _currentIndex == 0,
                      onTap: () => _selectIndex(0),
                    ),
                    _DrawerItem(
                      icon: Icons.folder_open,
                      label: 'Data Collected',
                      selected: _currentIndex == 1,
                      onTap: () => _selectIndex(1),
                    ),
                    _DrawerItem(
                      icon: Icons.analytics,
                      label: l10n.benchmark,
                      selected: _currentIndex == 2,
                      onTap: () => _selectIndex(2),
                    ),
                    _DrawerItem(
                      icon: Icons.person,
                      label: l10n.driverProfile,
                      selected: _currentIndex == 3,
                      onTap: () => _selectIndex(3),
                    ),
                    _DrawerItem(
                      icon: Icons.history,
                      label: l10n.tripHistory,
                      selected: _currentIndex == 4,
                      onTap: () => _selectIndex(4),
                    ),
                    _DrawerItem(
                      icon: Icons.settings,
                      label: l10n.settings,
                      selected: _currentIndex == 5,
                      onTap: () => _selectIndex(5),
                    ),
                    _DrawerItem(
                      icon: Icons.help_outline,
                      label: l10n.help,
                      selected: false,
                      onTap: () {
                        Navigator.of(context).pop();
                        _showHelpSheet();
                      },
                    ),
                    const Divider(height: 24),
                    _DrawerItem(
                      icon: Icons.logout,
                      label: l10n.logout,
                      selected: false,
                      iconColor: Colors.red,
                      textColor: Colors.red,
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const DataCollectionScreen(),
          const DataCollectedScreen(embedded: true),
          const HomeScreen(),
          const DriverProfileScreen(embedded: true),
          const TripHistoryScreen(embedded: true),
          SettingsScreen(
            onDarkModeChanged: widget.onDarkModeChanged,
            embedded: true,
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color? iconColor;
  final Color? textColor;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent;
    final effectiveIconColor = iconColor ?? (selected ? AppColors.primary : AppColors.textSecondary);
    final effectiveTextColor = textColor ?? (selected ? AppColors.primary : AppColors.textPrimary);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: effectiveIconColor),
        title: Text(
          label,
          style: TextStyle(
            color: effectiveTextColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        question,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
