import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../providers/customer_provider.dart';
import '../providers/ledger_year_provider.dart';
import '../services/app_deep_link_service.dart';
import '../services/app_pin_service.dart';
import '../services/company_profile_service.dart';
import '../services/csv_backup_service.dart';
import '../services/linked_devices_controller.dart';
import '../services/manual_update_service.dart';
import '../utils/platform_helper.dart';
import '../widgets/app_pin_dialogs.dart';
import '../widgets/platform_shell_layouts.dart';
import '../widgets/scale_down_width.dart';
import 'customer_list_screen.dart';
import 'linked_devices_screen.dart';
import 'snapshot_entries_screen.dart';
import 'summary_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  static const String _notesSettingKey = 'sidebar.notes';

  final AppPinService _appPinService = AppPinService();
  final CompanyProfileService _companyProfileService = CompanyProfileService();
  final CsvBackupService _csvBackupService = CsvBackupService();
  final LinkedDevicesController _linkedDevices =
      LinkedDevicesController.instance;
  final ManualUpdateService _manualUpdateService = ManualUpdateService.instance;
  final AppDeepLinkService _deepLinkService = AppDeepLinkService.instance;
  int _selectedIndex = 0;
  int _reloadRevision = 0;
  bool _isPinEnabled = false;
  CompanyProfile _companyProfile = const CompanyProfile(
    name: '',
    logoPath: null,
  );
  bool _didPromptCompanyProfile = false;
  int _lastSeenLinkedDataVersion = 0;
  bool _isHandlingDeepLink = false;
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
    _linkedDevices.addListener(_handleLinkedDevicesChanged);
    _deepLinkService.addListener(_onPendingDeepLinkChanged);
    _loadPinStatus();
    _loadCompanyProfile();
    _loadSidebarNotes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingDeepLink();
    });
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _deepLinkService.removeListener(_onPendingDeepLinkChanged);
    super.dispose();
  }

  void _handleLinkedDevicesChanged() {
    if (_lastSeenLinkedDataVersion == _linkedDevices.dataVersion) {
      return;
    }

    _lastSeenLinkedDataVersion = _linkedDevices.dataVersion;
    _loadCompanyProfile();
    _loadSidebarNotes();
    if (mounted) {
      setState(() {
        _reloadRevision++;
      });
    }
  }

  void _onPendingDeepLinkChanged() {
    _handlePendingDeepLink();
  }

  Future<void> _handlePendingDeepLink() async {
    if (_isHandlingDeepLink || !mounted) {
      return;
    }

    final inviteLink = _deepLinkService.takePendingInviteLink();
    if ((inviteLink ?? '').isEmpty) {
      return;
    }

    _isHandlingDeepLink = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LinkedDevicesScreen(
            initialInviteLink: inviteLink,
            controller: _linkedDevices,
          ),
        ),
      );
    } finally {
      _isHandlingDeepLink = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handlePendingDeepLink();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
          Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              ?currentChild,
            ],
          ),
      child: _buildActivePage(),
    );

    if (PlatformHelper.isDesktop) {
      return DesktopDrawerLayout(
        title: _destinations[_selectedIndex].label,
        drawerChild: _buildSidebarContent(
          dark: true,
          subtitle: 'Accounting command center',
          closeDrawerOnAction: true,
          showDestinations: false,
        ),
        content: _buildDesktopMain(content),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final destination = _destinations[_selectedIndex];

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      drawer: Drawer(child: SafeArea(child: drawerChild)),
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Balance Desk',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _WorkspaceStatusPill(
              label: _linkedDevices.workspaceBadgeLabel,
              compact: true,
            ),
          ),
        ],
      ),
      body: SafeArea(bottom: false, child: _buildMobileMain(content)),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectIndex,
              destinations: <NavigationDestination>[
                for (final item in _destinations)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            ),
          ),
        ),
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

  Widget _buildMobileMain(Widget content) {
    return Column(
      key: const ValueKey<String>('mobile-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_companyProfile.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _CompanyHeaderCard(
              name: _companyProfile.name,
              logoPath: _companyProfile.logoPath,
            ),
          ),
        if (!_companyProfile.isEmpty) const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 86),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarContent({
    required bool dark,
    required String subtitle,
    required bool closeDrawerOnAction,
    bool showDestinations = true,
  }) {
    final linkedDevices =
        context.watch<LinkedDevicesController?>() ?? _linkedDevices;

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
        action: _createManualBackup,
      ),
      onPinRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openPinSettings,
      ),
      onRestoreBackupRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _restoreBackup,
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
        action: _openLinkedDevicesScreen,
      ),
      onCheckUpdateRequested: () => _runDrawerAction(
        closeDrawerOnAction: closeDrawerOnAction,
        action: _openManualUpdateDialog,
      ),
      pinButtonLabel: _isPinEnabled ? 'Manage App PIN' : 'Set App PIN',
      companyName: _companyProfile.name.trim().isEmpty
          ? 'Balance Desk'
          : _companyProfile.name.trim(),
      companyLogoPath: _companyProfile.logoPath,
      workspaceSubtitle: linkedDevices.workspaceSubtitle,
      workspaceBadge: linkedDevices.workspaceBadgeLabel,
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

  void _showLinkedReadOnlyMessage() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_linkedDevices.readOnlyMessage)));
  }

  Future<void> _openLinkedDevicesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkedDevicesScreen(controller: _linkedDevices),
      ),
    );
  }

  Future<void> _openNotesEditor() async {
    if (!_linkedDevices.canEditWorkspace) {
      _showLinkedReadOnlyMessage();
      return;
    }

    final controller = TextEditingController(text: _sidebarNotes);
    final notes = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Notes'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 12,
              minLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Write any note you want to keep in the sidebar.',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || notes == null) {
      return;
    }

    await AppDatabase.instance.setAppSetting(
      key: _notesSettingKey,
      value: notes,
    );
    await _linkedDevices.syncAfterLocalChange(reason: 'sidebar_notes');

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
        return AlertDialog(
          title: const Text('App PIN'),
          content: const Text(
            'You can change the current PIN or remove it completely.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PinAction.disable),
              child: const Text('Turn Off PIN'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PinAction.change),
              child: const Text('Change PIN'),
            ),
          ],
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

    await _loadPinStatus();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App PIN turned off.')));
  }

  Widget _buildActivePage() {
    final activeYear = context.watch<LedgerYearProvider>().activeYear;

    return KeyedSubtree(
      key: ValueKey<String>('$_selectedIndex-$_reloadRevision-$activeYear'),
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
    if (!_linkedDevices.canEditWorkspace) {
      _showLinkedReadOnlyMessage();
      return;
    }

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
    if (!_linkedDevices.canEditWorkspace) {
      _showLinkedReadOnlyMessage();
      return;
    }

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

  Future<void> _createManualBackup() async {
    try {
      final path = await _csvBackupService.createBackupFile();
      if (!mounted) {
        return;
      }
      if (path == null) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved.\n$path')));
    } on CsvBackupException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to create backup right now.')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    if (!_linkedDevices.canEditWorkspace) {
      _showLinkedReadOnlyMessage();
      return;
    }

    try {
      final filePath = await _csvBackupService.restoreBackupFile();
      if (!mounted || filePath == null || filePath.isEmpty) {
        return;
      }
      await _linkedDevices.syncAfterLocalChange(
        reason: 'manual_backup_restore',
      );
      await _reloadActiveYearData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } on CsvBackupException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to restore backup right now.')),
      );
    }
  }

  Future<void> _openCompanyProfileEditor({bool isInitial = false}) async {
    if (!isInitial && !_linkedDevices.canEditWorkspace) {
      _showLinkedReadOnlyMessage();
      return;
    }

    final nameController = TextEditingController(text: _companyProfile.name);
    String? pickedLogoPath = _companyProfile.logoPath;
    bool removeLogo = false;

    final didSkip = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            Widget logoPreview() {
              if (removeLogo) {
                return const SizedBox.shrink();
              }
              final path = pickedLogoPath;
              if (path == null || path.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              final file = File(path);
              if (!file.existsSync()) {
                return const SizedBox.shrink();
              }
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
                                  final result = await FilePicker.platform
                                      .pickFiles(type: FileType.image);
                                  if (result == null ||
                                      result.files.isEmpty ||
                                      result.files.first.path == null) {
                                    return;
                                  }
                                  setState(() {
                                    pickedLogoPath = result.files.first.path;
                                    removeLogo = false;
                                  });
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
                    await _linkedDevices.syncAfterLocalChange(
                      reason: 'company_profile_update',
                    );

                    if (!dialogContext.mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(false);
                    if (!mounted) {
                      return;
                    }
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

    if (isInitial && (didSkip ?? false)) {
      await _companyProfileService.markInitialPromptSkipped();
    }

    nameController.dispose();
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
    required this.onRestoreBackupRequested,
    required this.onCompanyProfileRequested,
    required this.onNotesRequested,
    required this.onLinkedDevicesRequested,
    required this.onCheckUpdateRequested,
    required this.pinButtonLabel,
    required this.companyName,
    required this.companyLogoPath,
    required this.workspaceSubtitle,
    required this.workspaceBadge,
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
  final Future<void> Function() onRestoreBackupRequested;
  final Future<void> Function() onCompanyProfileRequested;
  final Future<void> Function() onNotesRequested;
  final Future<void> Function() onLinkedDevicesRequested;
  final Future<void> Function() onCheckUpdateRequested;
  final String pinButtonLabel;
  final String companyName;
  final String? companyLogoPath;
  final String workspaceSubtitle;
  final String workspaceBadge;
  final bool hasNotes;
  final bool showDestinations;
  final bool dark;

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  final ScrollController _scrollController = ScrollController();

  static const Color _sidebarTop = Color(0xFF081A13);
  static const Color _sidebarBottom = Color(0xFF103526);
  static const Color _sidebarAccent = Color(0xFF22C55E);
  static const Color _sidebarText = Color(0xFFF3F7F4);
  static const Color _sidebarMutedText = Color(0xFFB8C8BF);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sidebarTop = widget.dark ? _sidebarTop : const Color(0xFF0E241A);
    final sidebarBottom = widget.dark
        ? _sidebarBottom
        : const Color(0xFF174432);
    final dividerAlpha = widget.dark ? 0.08 : 0.10;
    final shadowAlpha = widget.dark ? 0.16 : 0.12;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[sidebarTop, sidebarBottom],
        ),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: dividerAlpha),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: 28,
            offset: const Offset(10, 0),
          ),
        ],
      ),
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(
          thumbColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.18),
          ),
          trackColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SidebarBrandHeader(subtitle: widget.subtitle),
                const SizedBox(height: 26),
                _DrawerProfileCard(
                  title: widget.companyName,
                  subtitle: widget.workspaceSubtitle,
                  badge: widget.workspaceBadge,
                  logoPath: widget.companyLogoPath,
                ),
                const SizedBox(height: 18),
                Consumer<LedgerYearProvider>(
                  builder:
                      (BuildContext context, LedgerYearProvider provider, _) {
                        return _buildYearSwitcher(
                          context: context,
                          provider: provider,
                          onDeleteRequested: widget.onDeleteYearRequested,
                        );
                      },
                ),
                if (widget.showDestinations) ...<Widget>[
                  const SizedBox(height: 26),
                  const _SettingsSectionLabel(title: 'Main Navigation'),
                  const SizedBox(height: 12),
                  ...List<Widget>.generate(widget.destinations.length, (
                    int index,
                  ) {
                    final destination = widget.destinations[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SidebarNavItem(
                        icon: index == widget.selectedIndex
                            ? destination.selectedIcon
                            : destination.icon,
                        label: destination.label,
                        isSelected: index == widget.selectedIndex,
                        onTap: () => widget.onSelected(index),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 26),
                const _SettingsSectionLabel(title: 'Settings'),
                const SizedBox(height: 12),
                _SidebarActionItem(
                  icon: Icons.business_outlined,
                  label: 'Company Profile',
                  onTap: () {
                    widget.onCompanyProfileRequested();
                  },
                ),
                const SizedBox(height: 8),
                _SidebarActionItem(
                  icon: Icons.edit_note_outlined,
                  label: 'Add Notes',
                  trailingText: widget.hasNotes ? 'Saved' : null,
                  onTap: () {
                    widget.onNotesRequested();
                  },
                ),
                const SizedBox(height: 8),
                _SidebarActionItem(
                  icon: Icons.devices_outlined,
                  label: 'Linked Devices',
                  trailingText: widget.workspaceBadge,
                  onTap: () {
                    widget.onLinkedDevicesRequested();
                  },
                ),
                const SizedBox(height: 8),
                _SidebarActionItem(
                  icon: Icons.system_update_alt_outlined,
                  label: 'Check for Update',
                  onTap: () {
                    widget.onCheckUpdateRequested();
                  },
                ),
                const SizedBox(height: 8),
                _SidebarActionItem(
                  icon: Icons.backup_outlined,
                  label: 'Backup',
                  onTap: () {
                    widget.onBackupRequested();
                  },
                ),
                const SizedBox(height: 8),
                _SidebarActionItem(
                  icon: Icons.restore_page_outlined,
                  label: 'Restore Backup',
                  onTap: () {
                    widget.onRestoreBackupRequested();
                  },
                ),
                const SizedBox(height: 26),
                const _SettingsSectionLabel(title: 'Security'),
                const SizedBox(height: 12),
                _SidebarActionItem(
                  icon: Icons.lock_outline_rounded,
                  label: widget.pinButtonLabel,
                  subtle: true,
                  onTap: () {
                    widget.onPinRequested();
                  },
                ),
                const SizedBox(height: 28),
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                const SizedBox(height: 16),
                const _SidebarFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildYearSwitcher({
    required BuildContext context,
    required LedgerYearProvider provider,
    required VoidCallback onDeleteRequested,
  }) {
    final theme = Theme.of(context);
    final years = provider.years.isEmpty
        ? <int>[provider.activeYear]
        : provider.years;
    final totalYears = years.length;
    final helperText = totalYears == 1 ? '1 active year' : '$totalYears years';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _sidebarAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 18,
                  color: _sidebarAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ledger Year',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: _sidebarText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      helperText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _sidebarMutedText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${provider.activeYear}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _sidebarText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.event_note_rounded,
                            size: 16,
                            color: _sidebarAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${provider.activeYear}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _sidebarText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: provider.isLoading
                              ? SizedBox(
                                  key: const ValueKey<String>('loading'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: _sidebarAccent,
                                  ),
                                )
                              : Icon(
                                  key: const ValueKey<String>('menu'),
                                  Icons.unfold_more_rounded,
                                  color: _sidebarMutedText,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add year',
                onPressed: provider.isLoading
                    ? null
                    : widget.onAddYearRequested,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: _sidebarAccent.withValues(alpha: 0.14),
                  foregroundColor: _sidebarAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Delete year',
                onPressed: provider.isLoading || provider.years.length <= 1
                    ? null
                    : onDeleteRequested,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  foregroundColor: const Color(0xFFFCA5A5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (provider.errorMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              provider.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFFCA5A5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PinAction { change, disable }

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

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: const Color(0xFF87A193),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyHeaderCard extends StatelessWidget {
  const _CompanyHeaderCard({required this.name, required this.logoPath});

  final String name;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = name.trim().isEmpty ? 'Balance Desk' : name.trim();
    final logoFile = logoPath == null || logoPath!.trim().isEmpty
        ? null
        : File(logoPath!);
    const cardPadding = 10.0;
    const avatarRadius = 20.0;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    const badgePadding = EdgeInsets.symmetric(horizontal: 10, vertical: 4);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              backgroundImage: logoFile != null && logoFile.existsSync()
                  ? FileImage(logoFile)
                  : null,
              child: logoFile != null && logoFile.existsSync()
                  ? null
                  : Icon(Icons.business_outlined, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accounting Workspace',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: badgePadding,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceStatusPill extends StatelessWidget {
  const _WorkspaceStatusPill({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
          ),
        ],
      ),
    );
  }
}

class _DrawerProfileCard extends StatelessWidget {
  const _DrawerProfileCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    this.logoPath,
  });

  final String title;
  final String subtitle;
  final String badge;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final logoFile = logoPath == null || logoPath!.trim().isEmpty
        ? null
        : File(logoPath!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(
                  0xFF22C55E,
                ).withValues(alpha: 0.14),
                backgroundImage: logoFile != null && logoFile.existsSync()
                    ? FileImage(logoFile)
                    : null,
                child: logoFile != null && logoFile.existsSync()
                    ? null
                    : const Icon(
                        Icons.apartment_rounded,
                        color: Color(0xFF22C55E),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Workspace',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF87A193),
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFDCFCE7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFB8C8BF),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrandHeader extends StatelessWidget {
  const _SidebarBrandHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF22C55E), Color(0xFF14532D)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_graph_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'BalanceDesk',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB8C8BF),
                ),
              ),
            ],
          ),
        ),
      ],
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
    this.trailingText,
    this.subtle = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;
  final bool subtle;

  @override
  State<_SidebarActionItem> createState() => _SidebarActionItemState();
}

class _SidebarActionItemState extends State<_SidebarActionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseOpacity = widget.subtle ? 0.03 : 0.05;
    final hoverOpacity = widget.subtle ? 0.06 : 0.08;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.transparent,
          splashColor: const Color(0xFF22C55E).withValues(alpha: 0.14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: _isHovered ? hoverOpacity : baseOpacity,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.subtle
                      ? const Color(0xFFB8C8BF)
                      : const Color(0xFFE5E7EB),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: widget.subtle
                          ? const Color(0xFFD1D5DB)
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if ((widget.trailingText ?? '').trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.trailingText!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFB8C8BF),
                        fontWeight: FontWeight.w700,
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

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'BalanceDesk v1.0.0+1',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFFB8C8BF),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Developer: Ahmer Abid',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF87A193),
          ),
        ),
      ],
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
