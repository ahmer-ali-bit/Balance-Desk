import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../models/workspace.dart';
import '../providers/customer_provider.dart';
import '../providers/ledger_year_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/app_pin_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/company_profile_service.dart';
import '../services/manual_update_service.dart';
import '../utils/platform_helper.dart';
import '../widgets/app_pin_dialogs.dart';
import '../widgets/mobile_premium.dart';
import '../widgets/platform_shell_layouts.dart';
import '../widgets/scale_down_width.dart';
import 'customer_list_screen.dart';
import 'snapshot_entries_screen.dart';
import 'summary_screen.dart';
import 'backup_restore_screen.dart';
import '../features/linked_devices/screens/linked_devices_screen.dart';
import '../features/linked_devices/providers/linked_session_provider.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  static const String _notesSettingKey = 'sidebar.notes';

  final AppPinService _appPinService = AppPinService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final CompanyProfileService _companyProfileService = CompanyProfileService();
  final ManualUpdateService _manualUpdateService = ManualUpdateService.instance;
  int _selectedIndex = 0;
  int _reloadRevision = 0;
  bool _isPinEnabled = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  String _biometricLabel = 'Fingerprint';
  CompanyProfile _companyProfile = const CompanyProfile(
    name: '',
    logoPath: null,
  );
  bool _didPromptCompanyProfile = false;
  String _sidebarNotes = '';

  static const List<_ShellDestination> _destinations = <_ShellDestination>[
    _ShellDestination(
      label: 'Customers',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt,
      child: CustomerListScreen(),
    ),
    _ShellDestination(
      label: 'Summary',
      icon: Icons.assessment_outlined,
      selectedIcon: Icons.assessment,
      child: SummaryScreen(),
    ),
    _ShellDestination(
      label: 'Daily Logs',
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      child: SnapshotEntriesScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
    _loadBiometricStatus();
    _loadCompanyProfile();
    _loadSidebarNotes();
    _setupWorkspaceProvider();
  }

  void _setupWorkspaceProvider() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final workspaceProvider = context.read<WorkspaceProvider>();
      workspaceProvider.onWorkspaceSwitch = _performWorkspaceSwitch;
    });
  }

  Future<void> _performWorkspaceSwitch(String workspaceId) async {
    // Capture providers before async gap
    final yearProvider = context.read<LedgerYearProvider>();
    final customerProvider = context.read<CustomerProvider>();

    // Close and reopen database for new workspace
    await AppDatabase.instance.switchDatabase();

    if (!mounted) return;

    // Reload all providers with new database data
    await yearProvider.loadYears();

    customerProvider.updateSearchQuery('');
    await customerProvider.loadCustomers();

    // Reload sidebar data
    await _loadPinStatus();
    await _loadBiometricStatus();
    await _loadCompanyProfile();
    await _loadSidebarNotes();

    if (!mounted) return;
    setState(() {
      _selectedIndex = 0;
      _reloadRevision++;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
          Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[...previousChildren, ?currentChild],
          ),
      child: _buildActivePage(),
    );

    if (PlatformHelper.isDesktop) {
      return ScaleDownWidth(
        designWidth: 1100,
        child: DesktopDrawerLayout(
          title: _destinations[_selectedIndex].label,
          drawerChild: _buildSidebarContent(
            dark: true,
            subtitle: 'Accounting command center',
            closeDrawerOnAction: true,
            showDestinations: false,
          ),
          content: _buildDesktopMain(content),
        ),
      );
    }

    if (PlatformHelper.isAndroid) {
      return _buildMobileScaffold(
        content: content,
        drawerChild: _buildSidebarContent(
          dark: true,
          subtitle: 'Mobile workspace',
          closeDrawerOnAction: true,
          showDestinations: false,
        ),
      );
    }

    return _buildMobileScaffold(
      content: content,
      drawerChild: _buildSidebarContent(
        dark: true,
        subtitle: 'Mobile workspace',
        closeDrawerOnAction: true,
        showDestinations: false,
      ),
    );
  }

  Widget _buildMobileScaffold({
    required Widget content,
    required Widget drawerChild,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final destination = _destinations[_selectedIndex];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colorScheme.surface,
      extendBody: true,
      drawerScrimColor: Colors.black.withValues(alpha: 0.58),
      drawer: Drawer(
        width: math.min(MediaQuery.sizeOf(context).width * 0.88, 356),
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
        ),
        child: SafeArea(top: false, child: drawerChild),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(78),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: _MobileTopBar(destination: destination),
          ),
        ),
      ),
      body: _buildMobileMain(content),
      bottomNavigationBar: _MobileBottomNav(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        onSelected: _selectIndex,
      ),
    );
  }

  Widget _buildMobileMain(Widget content) {
    return DecoratedBox(
      key: const ValueKey<String>('mobile-content'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Theme.of(context).colorScheme.surfaceContainerLowest,
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[Expanded(child: content)],
      ),
    );
  }

  Widget _buildDesktopMain(Widget content) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ShellNavigationHeader(
            selectedIndex: _selectedIndex,
            destinations: _destinations,
            onSelected: _selectIndex,
          ),
          const SizedBox(height: 14),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildSidebarContent({
    required bool dark,
    required String subtitle,
    required bool closeDrawerOnAction,
    bool showDestinations = true,
  }) {
    return _SidebarContent(
      selectedIndex: _selectedIndex,
      destinations: _destinations,
      subtitle: subtitle,
      onSelected: (int index) {
        _closeDrawerIfNeeded(closeDrawerOnAction);
        _selectIndex(index);
      },
      onYearSelected: (int year) {
        _closeDrawerIfNeeded(closeDrawerOnAction);
        _openLedgerYear(year);
      },
      onAddYearRequested: () {
        _closeDrawerIfNeeded(closeDrawerOnAction);
        _showAddYearDialog();
      },
      onDeleteYearRequested: () {
        _closeDrawerIfNeeded(closeDrawerOnAction);
        _confirmDeleteYear();
      },
      onBackupRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openBackupRestoreScreen,
      ),

      onPinRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openPinSettings,
      ),
      onCompanyProfileRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openCompanyProfileEditor,
      ),
      onNotesRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openNotesEditor,
      ),
      onLinkedDevicesRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openLinkedDevices,
      ),
      onCheckUpdateRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openManualUpdateDialog,
      ),
      onWorkspaceSwitched: () {
        _closeDrawerIfNeeded(closeDrawerOnAction);
      },
      pinButtonLabel: _isPinEnabled ? 'Manage App PIN' : 'Set App PIN',
      companyName: _companyProfile.name.trim().isEmpty
          ? 'Balance Desk'
          : _companyProfile.name.trim(),
      companyLogoPath: _companyProfile.logoPath,
      hasNotes: _sidebarNotes.trim().isNotEmpty,
      showDestinations: showDestinations,
      dark: dark,
    );
  }

  void _closeDrawerIfNeeded(bool closeDrawerOnAction) {
    if (!closeDrawerOnAction) {
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _runDrawerAction({
    required bool closeDrawerOnAction,
    required Future<void> Function() action,
  }) async {
    _closeDrawerIfNeeded(closeDrawerOnAction);
    await action();
  }

  Future<void> _loadPinStatus() async {
    final hasPin = await _appPinService.hasPin();
    if (!mounted) {
      return;
    }

    setState(() {
      _isPinEnabled = hasPin;
    });
  }

  Future<void> _loadBiometricStatus() async {
    final available = await _biometricService.isBiometricAvailable();
    final enabled = await _biometricService.isBiometricEnabled();
    final label = available
        ? await _biometricService.getBiometricLabel()
        : 'Fingerprint';
    if (!mounted) {
      return;
    }

    setState(() {
      _isBiometricAvailable = available;
      _isBiometricEnabled = enabled;
      _biometricLabel = label;
    });
  }

  Future<void> _loadSidebarNotes() async {
    try {
      final notes =
          await AppDatabase.instance.getAppSetting(_notesSettingKey) ?? '';
      if (!mounted) {
        return;
      }
      setState(() {
        _sidebarNotes = notes;
      });
    } catch (error) {
      debugPrint('AppShellScreen._loadSidebarNotes failed: $error');
    }
  }

  Future<void> _loadCompanyProfile() async {
    try {
      final profile = await _companyProfileService.loadProfile();
      if (!mounted) {
        return;
      }

      setState(() {
        _companyProfile = profile;
      });

      if (profile.isEmpty && !_didPromptCompanyProfile) {
        final hasSkipped = await _companyProfileService
            .hasSkippedInitialPrompt();
        if (!mounted) {
          return;
        }
        if (!hasSkipped) {
          _didPromptCompanyProfile = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _openCompanyProfileEditor(isInitial: true);
            }
          });
        }
      }
    } catch (error) {
      debugPrint('AppShellScreen._loadCompanyProfile failed: $error');
    }
  }

  Future<void> _openNotesEditor() async {
    final notes = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TextInputDialog(
        title: 'Add Notes',
        label: 'Notes',
        initialValue: _sidebarNotes,
        isMultiline: true,
        actionLabel: 'Save',
        hint: 'Write any note you want to keep in the sidebar.',
      ),
    );

    if (!mounted || notes == null) {
      return;
    }

    await AppDatabase.instance.setAppSetting(
      key: _notesSettingKey,
      value: notes,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _sidebarNotes = notes;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notes.isEmpty ? 'Notes cleared successfully.' : 'Notes saved.',
        ),
      ),
    );
  }

  Future<void> _openManualUpdateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _ManualUpdateDialog(service: _manualUpdateService);
      },
    );
  }

  Future<void> _openPinSettings() async {
    if (!_isPinEnabled) {
      await _setPin();
      return;
    }

    final action = await showDialog<_PinAction>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _PinSettingsDialog(
          isBiometricAvailable: _isBiometricAvailable,
          isBiometricEnabled: _isBiometricEnabled,
          biometricLabel: _biometricLabel,
          onBiometricToggled: (bool enabled) async {
            await _biometricService.setBiometricEnabled(enabled);
            await _loadBiometricStatus();
          },
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == _PinAction.change) {
      await _changePin();
      return;
    }

    await _disablePin();
  }

  Future<void> _openLinkedDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const LinkedDevicesScreen()),
    );
  }

  Future<void> _setPin() async {
    final result = await showDialog<AppPinSetupResult>(
      context: context,
      builder: (BuildContext context) {
        return const AppPinSetupDialog(
          title: 'Set App PIN',
          submitLabel: 'Save PIN',
          description:
              'Add a 4 to 6 digit PIN if you want the app to ask for it on startup.',
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    await _appPinService.savePin(result.newPin);
    await _loadPinStatus();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App PIN enabled.')));
  }

  Future<void> _changePin() async {
    final result = await showDialog<AppPinSetupResult>(
      context: context,
      builder: (BuildContext context) {
        return const AppPinSetupDialog(
          title: 'Change App PIN',
          submitLabel: 'Update PIN',
          requireCurrentPin: true,
          description:
              'Enter the current PIN, then choose a new 4 to 6 digit PIN.',
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final isChanged = await _appPinService.changePin(
      currentPin: result.currentPin ?? '',
      newPin: result.newPin,
    );
    if (!mounted) {
      return;
    }

    if (!isChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current PIN is incorrect.')),
      );
      return;
    }

    await _loadPinStatus();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App PIN updated.')));
  }

  Future<void> _disablePin() async {
    final currentPin = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return const AppPinVerifyDialog(
          title: 'Turn Off App PIN',
          submitLabel: 'Turn Off',
          description: 'Enter the current PIN to disable startup protection.',
        );
      },
    );

    if (!mounted || currentPin == null) {
      return;
    }

    final isDisabled = await _appPinService.disablePin(currentPin);
    if (!mounted) {
      return;
    }

    if (!isDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current PIN is incorrect.')),
      );
      return;
    }

    // Also disable biometric when PIN is turned off.
    await _biometricService.setBiometricEnabled(false);

    await _loadPinStatus();
    await _loadBiometricStatus();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App PIN turned off.')));
  }

  Widget _buildActivePage() {
    final activeYear = context.watch<LedgerYearProvider>().activeYear;
    final workspaceId = context.watch<WorkspaceProvider>().activeWorkspaceId;

    return KeyedSubtree(
      key: ValueKey<String>(
        '$_selectedIndex-$_reloadRevision-$activeYear-$workspaceId',
      ),
      child: PlatformHelper.isDesktop
          ? _PageSurface(child: _destinations[_selectedIndex].child)
          : _destinations[_selectedIndex].child,
    );
  }

  void _selectIndex(int index) {
    if (_selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _openLedgerYear(int year) async {
    final yearProvider = context.read<LedgerYearProvider>();
    if (yearProvider.activeYear == year) {
      return;
    }

    final isOpened = await yearProvider.selectYear(year);
    if (!mounted) {
      return;
    }

    if (!isOpened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(yearProvider.errorMessage ?? 'Unable to open year.'),
        ),
      );
      return;
    }

    await _reloadActiveYearData();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Year $year opened.')));
  }

  Future<void> _showAddYearDialog() async {
    final year = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => const _AddYearDialog(),
    );

    if (!mounted || year == null) {
      return;
    }

    final yearProvider = context.read<LedgerYearProvider>();
    final isAdded = await yearProvider.addAndSelectYear(year);
    if (!mounted) {
      return;
    }

    if (!isAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(yearProvider.errorMessage ?? 'Unable to add year.'),
        ),
      );
      return;
    }

    await _reloadActiveYearData();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Year $year opened.')));
  }

  Future<void> _confirmDeleteYear() async {
    final yearProvider = context.read<LedgerYearProvider>();
    final yearToDelete = yearProvider.activeYear;

    if (yearProvider.years.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only active year.')),
      );
      return;
    }

    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete Ledger Year'),
              content: Text(
                'Delete year $yearToDelete? This will remove all customers, entries, and snapshots for that year.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete || !mounted) {
      return;
    }

    final isDeleted = await yearProvider.deleteYear(yearToDelete);
    if (!mounted) {
      return;
    }

    if (isDeleted) {
      await _reloadActiveYearData();
      if (!mounted) {
        return;
      }
    }

    final message = isDeleted
        ? 'Year $yearToDelete deleted.'
        : (yearProvider.errorMessage ?? 'Unable to delete year.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBackupRestoreScreen() async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
    );
  }

  Future<void> _openCompanyProfileEditor({bool isInitial = false}) async {
    final nameController = TextEditingController(text: _companyProfile.name);
    String? pickedLogoPath = _companyProfile.logoPath;
    bool removeLogo = false;

    final didSkip = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            Widget logoPreview() {
              if (removeLogo) return const SizedBox.shrink();
              final path = pickedLogoPath;
              if (path == null || path.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              final file = File(path);
              if (!file.existsSync()) return const SizedBox.shrink();
              return CircleAvatar(radius: 28, backgroundImage: FileImage(file));
            }

            return AlertDialog(
              title: Text(
                isInitial ? 'Set Company Profile' : 'Company Profile',
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Company name and logo are optional. You can update them anytime.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Company name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        logoPreview(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final result = await FilePicker.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: [
                                        'jpg',
                                        'jpeg',
                                        'png',
                                        'gif',
                                        'bmp',
                                        'webp',
                                      ],
                                      allowMultiple: false,
                                    );
                                    if (result == null ||
                                        result.files.isEmpty ||
                                        result.files.first.path == null) {
                                      return;
                                    }
                                    setState(() {
                                      pickedLogoPath = result.files.first.path;
                                      removeLogo = false;
                                    });
                                  } catch (e) {
                                    debugPrint('FilePicker error: $e');
                                  }
                                },
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Choose Logo'),
                              ),
                              if (pickedLogoPath != null &&
                                  pickedLogoPath!.trim().isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      removeLogo = true;
                                      pickedLogoPath = null;
                                    });
                                  },
                                  child: const Text('Remove Logo'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(isInitial),
                  child: Text(isInitial ? 'Skip' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    String? logoPath;

                    if (removeLogo) {
                      await _companyProfileService.clearLogo();
                      logoPath = '';
                    } else if (pickedLogoPath != null &&
                        pickedLogoPath!.trim().isNotEmpty) {
                      if (pickedLogoPath != _companyProfile.logoPath) {
                        logoPath = await _companyProfileService
                            .copyLogoToAppDir(pickedLogoPath!);
                      } else {
                        logoPath = _companyProfile.logoPath;
                      }
                    } else {
                      logoPath = _companyProfile.logoPath;
                    }

                    await _companyProfileService.saveProfile(
                      name: name,
                      logoPath: logoPath,
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop(false);
                    if (!mounted) return;
                    await _loadCompanyProfile();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (didSkip == true && mounted) {
      await _companyProfileService.markInitialPromptSkipped();
    }
  }

  Future<void> _reloadActiveYearData() async {
    final customerProvider = context.read<CustomerProvider>();
    customerProvider.updateSearchQuery('');
    await customerProvider.loadCustomers();

    if (!mounted) {
      return;
    }

    setState(() {
      _reloadRevision++;
    });
  }
}

class _ShellNavigationHeader extends StatelessWidget {
  const _ShellNavigationHeader({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ScaleDownWidth(
        designWidth: 960,
        child: Row(
          children: <Widget>[
            for (
              var index = 0;
              index < destinations.length;
              index++
            ) ...<Widget>[
              Expanded(
                child: _ShellNavigationPill(
                  label: destinations[index].label,
                  icon: index == selectedIndex
                      ? destinations[index].selectedIcon
                      : destinations[index].icon,
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
              if (index != destinations.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarContent extends StatefulWidget {
  const _SidebarContent({
    required this.selectedIndex,
    required this.destinations,
    required this.subtitle,
    required this.onSelected,
    required this.onYearSelected,
    required this.onAddYearRequested,
    required this.onDeleteYearRequested,
    required this.onBackupRequested,
    required this.onPinRequested,
    required this.onCompanyProfileRequested,
    required this.onNotesRequested,
    required this.onLinkedDevicesRequested,
    required this.onCheckUpdateRequested,
    required this.onWorkspaceSwitched,
    required this.pinButtonLabel,
    required this.companyName,
    required this.companyLogoPath,
    required this.hasNotes,
    this.showDestinations = true,
    this.dark = false,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final String subtitle;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onYearSelected;
  final VoidCallback onAddYearRequested;
  final VoidCallback onDeleteYearRequested;
  final Future<void> Function() onBackupRequested;
  final Future<void> Function() onPinRequested;
  final Future<void> Function() onCompanyProfileRequested;
  final Future<void> Function() onNotesRequested;
  final Future<void> Function() onLinkedDevicesRequested;
  final Future<void> Function() onCheckUpdateRequested;
  final VoidCallback onWorkspaceSwitched;
  final String pinButtonLabel;
  final String companyName;
  final String? companyLogoPath;
  final bool hasNotes;
  final bool showDestinations;
  final bool dark;

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canEdit = context.watch<LinkedSessionProvider>().canEdit;

    if (!PlatformHelper.isDesktop) {
      return _buildMobileDrawer(context, canEdit: canEdit);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with Gradient
        Container(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorScheme.primaryContainer, colorScheme.surface],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  // const SyncStatusIndicator(), // Temporarily hidden
                ],
              ),
              const SizedBox(height: 20),
              Text(
                widget.companyName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                  letterSpacing: -1.0,
                ),
              ),
              Text(
                'Professional Accounting Command',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Year Switcher
        Consumer<LedgerYearProvider>(
          builder: (BuildContext context, LedgerYearProvider provider, _) {
            return _buildYearSwitcher(
              context: context,
              provider: provider,
              onDeleteRequested: canEdit ? widget.onDeleteYearRequested : () {},
            );
          },
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        // Workspace Switcher
        _WorkspaceSwitcher(onWorkspaceSwitched: widget.onWorkspaceSwitched),
        Divider(height: 1, color: colorScheme.outlineVariant),
        // Menu items
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DrawerSectionLabel('Settings'),
                  _DrawerListTile(
                    icon: Icons.business_outlined,
                    label: 'Company Profile',
                    onTap: canEdit ? widget.onCompanyProfileRequested : null,
                  ),
                  _DrawerListTile(
                    icon: Icons.devices_other_outlined,
                    label: 'Linked Devices',
                    onTap: widget.onLinkedDevicesRequested,
                  ),
                  _DrawerListTile(
                    icon: Icons.edit_note_outlined,
                    label: 'Notes',
                    trailing: widget.hasNotes ? '●' : null,
                    onTap: canEdit ? widget.onNotesRequested : null,
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                    indent: 16,
                    endIndent: 16,
                  ),
                  _DrawerSectionLabel('Data'),
                  _DrawerListTile(
                    icon: Icons.backup_rounded,
                    label: 'Backup & Restore',
                    onTap: canEdit ? widget.onBackupRequested : null,
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                    indent: 16,
                    endIndent: 16,
                  ),
                  _DrawerSectionLabel('Security'),
                  _DrawerListTile(
                    icon: Icons.lock_outline_rounded,
                    label: widget.pinButtonLabel,
                    onTap: canEdit ? widget.onPinRequested : null,
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                    indent: 16,
                    endIndent: 16,
                  ),
                  _DrawerSectionLabel('App'),
                  _DrawerListTile(
                    icon: Icons.system_update_alt_outlined,
                    label: 'Check for Update',
                    onTap: widget.onCheckUpdateRequested,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Balance Desk',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Developer: Ahmer Abid',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileDrawer(BuildContext context, {required bool canEdit}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 54, 18, 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(kMobilePremiumRadius),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child:
                      widget.companyLogoPath == null ||
                          widget.companyLogoPath!.trim().isEmpty
                      ? Icon(
                          Icons.account_balance_wallet_rounded,
                          color: colorScheme.primary,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(
                            kMobilePremiumRadius,
                          ),
                          child: Image.file(
                            File(widget.companyLogoPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.account_balance_wallet_rounded,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildYearSwitcher(
                      context: context,
                      provider: context.watch<LedgerYearProvider>(),
                      onDeleteRequested: canEdit
                          ? widget.onDeleteYearRequested
                          : () {},
                    ),
                    const SizedBox(height: 10),
                    _WorkspaceSwitcher(
                      onWorkspaceSwitched: widget.onWorkspaceSwitched,
                    ),
                    const SizedBox(height: 14),
                    MobileSectionHeader(title: 'Workspace Tools'),
                    const SizedBox(height: 8),
                    _MobileDrawerAction(
                      icon: Icons.business_outlined,
                      label: 'Company Profile',
                      onTap: canEdit ? widget.onCompanyProfileRequested : null,
                    ),
                    _MobileDrawerAction(
                      icon: Icons.devices_other_outlined,
                      label: 'Linked Devices',
                      onTap: widget.onLinkedDevicesRequested,
                    ),
                    _MobileDrawerAction(
                      icon: Icons.edit_note_outlined,
                      label: 'Notes',
                      trailing: widget.hasNotes
                          ? MobileStatusPill(
                              icon: Icons.check_rounded,
                              label: 'Saved',
                              color: colorScheme.secondary,
                            )
                          : null,
                      onTap: canEdit ? widget.onNotesRequested : null,
                    ),
                    const SizedBox(height: 12),
                    MobileSectionHeader(title: 'Data & Security'),
                    const SizedBox(height: 8),
                    _MobileDrawerAction(
                      icon: Icons.backup_rounded,
                      label: 'Backup & Restore',
                      onTap: canEdit ? widget.onBackupRequested : null,
                    ),
                    _MobileDrawerAction(
                      icon: Icons.lock_outline_rounded,
                      label: widget.pinButtonLabel,
                      onTap: canEdit ? widget.onPinRequested : null,
                    ),
                    _MobileDrawerAction(
                      icon: Icons.system_update_alt_outlined,
                      label: 'Check for Update',
                      onTap: widget.onCheckUpdateRequested,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Text(
              'Balance Desk',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearSwitcher({
    required BuildContext context,
    required LedgerYearProvider provider,
    required VoidCallback onDeleteRequested,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final years = provider.years.isEmpty
        ? <int>[provider.activeYear]
        : provider.years;
    final canEdit = context.read<LinkedSessionProvider>().canEdit;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'LEDGER YEAR',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<int>(
                  enabled: !provider.isLoading,
                  onSelected: widget.onYearSelected,
                  itemBuilder: (BuildContext context) {
                    return years
                        .map<PopupMenuEntry<int>>(
                          (int year) => PopupMenuItem<int>(
                            value: year,
                            child: Text('$year'),
                          ),
                        )
                        .toList(growable: false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${provider.activeYear}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (provider.isLoading)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        else
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add year',
                onPressed: (provider.isLoading || !canEdit)
                    ? null
                    : widget.onAddYearRequested,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete year',
                onPressed:
                    (provider.isLoading ||
                        provider.years.length <= 1 ||
                        !canEdit)
                    ? null
                    : onDeleteRequested,
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          if (provider.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                provider.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DrawerListTile extends StatelessWidget {
  const _DrawerListTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: onTap != null
            ? colorScheme.onSurface
            : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: onTap != null
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing != null
          ? Text(
              trailing!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colorScheme.primary),
            )
          : null,
      onTap: onTap,
      enabled: onTap != null,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

enum _PinAction { change, disable }

/// Dialog that shows PIN management options along with a biometric toggle.
class _PinSettingsDialog extends StatefulWidget {
  const _PinSettingsDialog({
    required this.isBiometricAvailable,
    required this.isBiometricEnabled,
    required this.biometricLabel,
    required this.onBiometricToggled,
  });

  final bool isBiometricAvailable;
  final bool isBiometricEnabled;
  final String biometricLabel;
  final Future<void> Function(bool enabled) onBiometricToggled;

  @override
  State<_PinSettingsDialog> createState() => _PinSettingsDialogState();
}

class _PinSettingsDialogState extends State<_PinSettingsDialog> {
  late bool _biometricOn;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _biometricOn = widget.isBiometricEnabled;
  }

  Future<void> _onBiometricChanged(bool value) async {
    setState(() => _toggling = true);
    await widget.onBiometricToggled(value);
    if (!mounted) return;
    setState(() {
      _biometricOn = value;
      _toggling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('App PIN'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You can change the current PIN or remove it completely.',
            ),
            if (widget.isBiometricAvailable) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: colorScheme.outlineVariant),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${widget.biometricLabel} Unlock'),
                subtitle: Text(
                  _biometricOn
                      ? 'App can be unlocked with ${widget.biometricLabel.toLowerCase()}'
                      : 'Use ${widget.biometricLabel.toLowerCase()} to unlock app',
                ),
                secondary: Icon(
                  widget.biometricLabel.contains('Face')
                      ? Icons.face_rounded
                      : Icons.fingerprint_rounded,
                  color: _biometricOn ? colorScheme.primary : null,
                ),
                value: _biometricOn,
                onChanged: _toggling ? null : _onBiometricChanged,
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_PinAction.disable),
          child: const Text('Turn Off PIN'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_PinAction.change),
          child: const Text('Change PIN'),
        ),
      ],
    );
  }
}

class _AddYearDialog extends StatefulWidget {
  const _AddYearDialog();

  @override
  State<_AddYearDialog> createState() => _AddYearDialogState();
}

class _AddYearDialogState extends State<_AddYearDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _yearController = TextEditingController();

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(int.parse(_yearController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Year'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _yearController,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Year'),
            validator: (String? value) {
              final year = int.tryParse(value?.trim() ?? '');
              if (year == null) {
                return 'Enter a year like 2024';
              }
              if (year < 1900 || year > 9999) {
                return 'Enter a valid year';
              }
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open Year')),
      ],
    );
  }
}

class _PageSurface extends StatelessWidget {
  const _PageSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!PlatformHelper.isDesktop) {
          return child;
        }

        final compact =
            constraints.maxWidth < 720 || constraints.maxHeight < 560;
        final colorScheme = Theme.of(context).colorScheme;
        final borderRadius = BorderRadius.circular(compact ? 22 : 28);

        return Padding(
          padding: EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: borderRadius,
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: compact ? 16 : 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(borderRadius: borderRadius, child: child),
          ),
        );
      },
    );
  }
}

class _ShellNavigationPill extends StatelessWidget {
  const _ShellNavigationPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 32,
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.primary.withValues(alpha: 0.86),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.primary.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.isSelected
        ? const Color(0xFF22C55E).withValues(alpha: 0.16)
        : _isHovered
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.transparent,
          splashColor: const Color(0xFF22C55E).withValues(alpha: 0.18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  width: 3,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? const Color(0xFF22C55E)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: widget.isSelected
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: widget.isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
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

class _SidebarActionItem extends StatefulWidget {
  const _SidebarActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_SidebarActionItem> createState() => _SidebarActionItemState();
}

class _SidebarActionItemState extends State<_SidebarActionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isEnabled = widget.onTap != null;
    const baseOpacity = 0.05;
    const hoverOpacity = 0.08;

    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.transparent,
          splashColor: isEnabled
              ? const Color(0xFF22C55E).withValues(alpha: 0.14)
              : Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: isEnabled
                    ? (_isHovered ? hoverOpacity : baseOpacity)
                    : 0.02,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Opacity(
              opacity: isEnabled ? 1.0 : 0.4,
              child: Row(
                children: <Widget>[
                  Icon(widget.icon, size: 18, color: const Color(0xFFE5E7EB)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualUpdateDialog extends StatefulWidget {
  const _ManualUpdateDialog({required this.service});

  final ManualUpdateService service;

  @override
  State<_ManualUpdateDialog> createState() => _ManualUpdateDialogState();
}

class _ManualUpdateDialogState extends State<_ManualUpdateDialog> {
  bool _isLoading = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('About & Updates'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<AppVersionInfo>(
          future: widget.service.getAppVersionInfo(),
          builder: (BuildContext context, AsyncSnapshot<AppVersionInfo> snap) {
            final versionLabel = snap.data?.label ?? 'Loading...';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Current version: $versionLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Use a local update file to install the latest version.',
                ),
                if ((_statusMessage ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _handleCheckForUpdate,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Check for Update'),
        ),
      ],
    );
  }

  Future<void> _handleCheckForUpdate() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    final result = await widget.service.pickUpdateFile();
    if (!mounted) {
      return;
    }

    if (!result.isSuccess || result.file == null) {
      setState(() {
        _isLoading = false;
        _statusMessage = result.message;
      });
      return;
    }

    if (result.versionStatus == ManualUpdateVersionStatus.notNewer &&
        result.currentVersion != null &&
        result.file!.parsedVersion != null) {
      final shouldContinue = await _confirmOlderVersion(
        currentVersion: result.currentVersion!,
        selectedVersion: result.file!.parsedVersion!,
      );
      if (!shouldContinue) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Update cancelled.';
        });
        return;
      }
    }

    final openResult = await widget.service.openInstaller(result.file!);
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _statusMessage = openResult.message;
    });

    if (!PlatformHelper.isAndroid) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Manual Update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Close the app and run the installer:'),
                const SizedBox(height: 8),
                SelectableText(result.file!.path),
              ],
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<bool> _confirmOlderVersion({
    required String currentVersion,
    required String selectedVersion,
  }) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Version Warning'),
          content: Text(
            'Selected version ($selectedVersion) is not newer than the '
            'current version ($currentVersion). Do you want to continue?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    return decision ?? false;
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({required this.destination});

  final _ShellDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MobilePremiumPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: <Widget>[
          Builder(
            builder: (BuildContext context) {
              return IconButton(
                tooltip: 'Open menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  foregroundColor: colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kMobilePremiumRadius),
                  ),
                ),
                icon: const Icon(Icons.menu_rounded),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Balance Desk',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(kMobilePremiumRadius),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(destination.selectedIcon, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _MobileDrawerAction extends StatelessWidget {
  const _MobileDrawerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MobilePremiumPanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Opacity(
          opacity: enabled ? 1 : 0.42,
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 19,
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: MobilePremiumPanel(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < destinations.length; i++) ...<Widget>[
                Expanded(
                  child: _MobileBottomNavItem(
                    label: destinations[i].label,
                    icon: selectedIndex == i
                        ? destinations[i].selectedIcon
                        : destinations[i].icon,
                    selected: selectedIndex == i,
                    colorScheme: colorScheme,
                    onTap: () => onSelected(i),
                  ),
                ),
                if (i < destinations.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNavItem extends StatelessWidget {
  const _MobileBottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kMobilePremiumRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kMobilePremiumRadius),
          border: selected
              ? Border.all(color: colorScheme.primary.withValues(alpha: 0.22))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 22,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
}

class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({required this.onWorkspaceSwitched});

  final VoidCallback onWorkspaceSwitched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<WorkspaceProvider>(
      builder: (BuildContext context, WorkspaceProvider provider, _) {
        final workspaces = provider.workspaces;
        final active = provider.activeWorkspace;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'WORKSPACE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Add Workspace',
                        onPressed: () =>
                            _showAddWorkspaceDialog(context, provider),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          foregroundColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              // Active workspace chip
              PopupMenuButton<String>(
                enabled: !provider.isSwitching,
                onSelected: (String workspaceId) async {
                  if (workspaceId == active.id) return;
                  final switched = await provider.switchWorkspace(workspaceId);
                  if (switched) {
                    onWorkspaceSwitched();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Switched to ${provider.activeWorkspace.name}',
                          ),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (BuildContext context) {
                  return workspaces
                      .map<PopupMenuEntry<String>>((Workspace w) {
                        final isActive = w.id == active.id;
                        return PopupMenuItem<String>(
                          value: w.id,
                          child: Row(
                            children: [
                              Icon(
                                isActive
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                size: 18,
                                color: isActive
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  w.name,
                                  style: TextStyle(
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (!isActive && w.id != 'default')
                                PopupMenuButton<_WorkspaceMenuAction>(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.more_vert,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  onSelected: (_WorkspaceMenuAction action) {
                                    Navigator.of(context).pop();
                                    switch (action) {
                                      case _WorkspaceMenuAction.rename:
                                        _showRenameDialog(context, provider, w);
                                        break;
                                      case _WorkspaceMenuAction.delete:
                                        _showDeleteDialog(context, provider, w);
                                        break;
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: _WorkspaceMenuAction.rename,
                                      child: Text('Rename'),
                                    ),
                                    const PopupMenuItem(
                                      value: _WorkspaceMenuAction.delete,
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              if (w.id == 'default' && !isActive)
                                const SizedBox(width: 40),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.workspaces_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          active.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (provider.isSwitching)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      else
                        Icon(
                          Icons.unfold_more_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddWorkspaceDialog(
    BuildContext context,
    WorkspaceProvider provider,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _TextInputDialog(
        title: 'Add Workspace',
        label: 'Workspace name',
        hint: 'e.g. Shop 2, Warehouse',
        actionLabel: 'Add',
      ),
    );

    if (name == null || name.isEmpty || !context.mounted) return;

    final workspace = await provider.addWorkspace(name);
    // Auto-switch to the new workspace
    final switched = await provider.switchWorkspace(workspace.id);
    if (switched && context.mounted) {
      onWorkspaceSwitched();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace "$name" created & activated.')),
      );
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WorkspaceProvider provider,
    Workspace workspace,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TextInputDialog(
        title: 'Rename Workspace',
        label: 'New name',
        initialValue: workspace.name,
        actionLabel: 'Rename',
      ),
    );

    if (newName == null || newName.isEmpty || !context.mounted) return;

    await provider.renameWorkspace(workspace.id, newName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace renamed to "$newName".')),
      );
    }
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WorkspaceProvider provider,
    Workspace workspace,
  ) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete Workspace'),
              content: Text(
                'Delete "${workspace.name}"? All data in this workspace will be lost. This cannot be undone.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete || !context.mounted) return;

    final deleted = await provider.deleteWorkspace(workspace.id);
    if (deleted && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${workspace.name}" deleted.')));
    }
  }
}

enum _WorkspaceMenuAction { rename, delete }

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
    this.initialValue = '',
    this.isMultiline = false,
    this.hint,
  });

  final String title;
  final String label;
  final String actionLabel;
  final String initialValue;
  final bool isMultiline;
  final String? hint;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty || widget.initialValue.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.isMultiline ? 420 : 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: widget.isMultiline ? 12 : 1,
          minLines: widget.isMultiline ? 6 : 1,
          textInputAction: widget.isMultiline
              ? TextInputAction.newline
              : TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.isMultiline)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Clear'),
          ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
