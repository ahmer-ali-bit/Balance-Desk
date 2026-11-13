import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../models/workspace.dart';
import '../providers/customer_provider.dart';
import '../providers/ledger_provider_cache.dart';
import '../providers/ledger_year_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/app_pin_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/company_profile_service.dart';
import '../services/manual_update_service.dart';
import '../utils/platform_helper.dart';
import '../widgets/app_pin_dialogs.dart';
import '../widgets/app_shell_chrome.dart';
import 'customer_list_screen.dart';
import 'snapshot_entries_screen.dart';
import 'summary_screen.dart';
import 'backup_restore_screen.dart';

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
      description: 'Accounts, balances and statements',
    ),
    _ShellDestination(
      label: 'Summary',
      icon: Icons.assessment_outlined,
      selectedIcon: Icons.assessment,
      child: SummaryScreen(),
      description: 'Your ledger year at a glance',
    ),
    _ShellDestination(
      label: 'Daily Logs',
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      child: SnapshotEntriesScreen(),
      description: 'Daily snapshot history',
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

    // Clear cached ledger providers so they re-query against the new database
    LedgerProviderCache.instance.disposeAll();

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

    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout =
        PlatformHelper.isDesktop && width >= ShellMetrics.desktopBreakpoint;

    if (useDesktopLayout) {
      return _buildDesktopScaffold(content);
    }

    return _buildMobileScaffold(content);
  }

  Widget _buildDesktopScaffold(Widget content) {
    final destination = _destinations[_selectedIndex];
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildDesktopTopBar(),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: ShellMetrics.sidebarWidth,
                    child: _buildSidebar(closeDrawerOnAction: false),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildDesktopHeader(destination),
                        const SizedBox(height: 14),
                        Expanded(child: ShellContentSheet(child: content)),
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

  Widget _buildDesktopTopBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeYear = context.watch<LedgerYearProvider>().activeYear;
    final workspaceName = context
        .watch<WorkspaceProvider>()
        .activeWorkspace
        .name;
    final logo = _buildCompanyLogo();

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (logo != null) ...[logo, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'FY $activeYear  •  $workspaceName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShellChip(
            icon: Icons.calendar_month_outlined,
            label: 'FY $activeYear',
          ),
          const SizedBox(width: 10),
          ShellChip(
            icon: Icons.workspaces_outlined,
            label: workspaceName,
            color: colorScheme.tertiary,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(_ShellDestination destination) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Balance Desk'.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.primary.withValues(alpha: 0.9),
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileScaffold(Widget content) {
    final destination = _destinations[_selectedIndex];
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to quit?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Quit', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: colorScheme.surface,
        drawerScrimColor: Colors.black.withValues(alpha: 0.55),
        drawer: Drawer(
          width: math.min(MediaQuery.sizeOf(context).width * 0.88, 340),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: _buildSidebar(closeDrawerOnAction: true),
            ),
          ),
        ),
        appBar: AppBar(
          toolbarHeight: 64,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 56,
          leading: Builder(
            builder: (BuildContext headerContext) {
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  tooltip: 'Open menu',
                  onPressed: () => Scaffold.of(headerContext).openDrawer(),
                  icon: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: const Icon(Icons.menu_rounded, size: 20),
                  ),
                ),
              );
            },
          ),
          titleSpacing: 4,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildCompanyLogo() ??
                    Icon(destination.selectedIcon,
                        color: colorScheme.primary, size: 20),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Container(
            color: colorScheme.surface,
            child: content,
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectIndex,
          destinations: <NavigationDestination>[
            for (final _ShellDestination d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }

  String get _companyName {
    final name = _companyProfile.name.trim();
    return name.isEmpty ? 'Balance Desk' : name;
  }

  List<ShellNavEntry> get _shellNavEntries {
    return <ShellNavEntry>[
      for (final _ShellDestination destination in _destinations)
        ShellNavEntry(
          label: destination.label,
          icon: destination.icon,
          selectedIcon: destination.selectedIcon,
          description: destination.description,
        ),
    ];
  }

  /// Company logo image, or null when no readable logo is configured.
  Widget? _buildCompanyLogo() {
    final path = _companyProfile.logoPath;
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }

    return Image.file(file, fit: BoxFit.cover);
  }

  Widget _buildSidebar({required bool closeDrawerOnAction}) {
    return AppShellSidebar(
      companyName: _companyName,
      subtitle: PlatformHelper.isDesktop
          ? 'Accounting command center'
          : 'Mobile workspace',
      logo: _buildCompanyLogo(),
      yearControl: _buildYearControl(closeDrawerOnAction: closeDrawerOnAction),
      workspaceControl: _WorkspaceSwitcher(
        onWorkspaceSwitched: () {
          _closeDrawerIfNeeded(closeDrawerOnAction);
        },
      ),
      navEntries: _shellNavEntries,
      selectedIndex: _selectedIndex,
      onSelectIndex: (int index) {
        _closeDrawerIfNeeded(closeDrawerOnAction);
        _selectIndex(index);
      },
      tools: <ShellToolEntry>[
        ShellToolEntry(
          icon: Icons.business_outlined,
          label: 'Company Profile',
          onTap: () => _runDrawerAction(
            closeDrawerOnAction: closeDrawerOnAction,
            action: _openCompanyProfileEditor,
          ),
        ),
        ShellToolEntry(
          icon: Icons.edit_note_outlined,
          label: 'Notes',
          badge: _sidebarNotes.trim().isNotEmpty,
          onTap: () => _runDrawerAction(
            closeDrawerOnAction: closeDrawerOnAction,
            action: _openNotesEditor,
          ),
        ),
        ShellToolEntry(
          icon: Icons.backup_rounded,
          label: 'Backup & Restore',
          onTap: () => _runDrawerAction(
            closeDrawerOnAction: closeDrawerOnAction,
            action: _openBackupRestoreScreen,
          ),
        ),
        ShellToolEntry(
          icon: Icons.lock_outline_rounded,
          label: _isPinEnabled ? 'Manage App PIN' : 'Set App PIN',
          onTap: () => _runDrawerAction(
            closeDrawerOnAction: closeDrawerOnAction,
            action: _openPinSettings,
          ),
        ),
        ShellToolEntry(
          icon: Icons.system_update_alt_outlined,
          label: 'Check for Update',
          onTap: () => _runDrawerAction(
            closeDrawerOnAction: closeDrawerOnAction,
            action: _openManualUpdateDialog,
          ),
        ),
      ],
      showNavEntries: true,
    );
  }

  Widget _buildYearControl({required bool closeDrawerOnAction}) {
    return Consumer<LedgerYearProvider>(
      builder: (BuildContext context, LedgerYearProvider provider, Widget? _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final years = provider.years.isEmpty
            ? <int>[provider.activeYear]
            : provider.years;
        final canEdit = _canEdit(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: PopupMenuButton<int>(
                    enabled: !provider.isLoading,
                    tooltip: 'Switch ledger year',
                    onSelected: (int year) {
                      _closeDrawerIfNeeded(closeDrawerOnAction);
                      _openLedgerYear(year);
                    },
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
                    child: ShellSelectField(
                      icon: Icons.calendar_month_outlined,
                      value: '${provider.activeYear}',
                      isBusy: provider.isLoading,
                    ),
                  ),
                ),
                if (canEdit) ...<Widget>[
                  const SizedBox(width: 6),
                  ShellIconAction(
                    icon: Icons.add_rounded,
                    tooltip: 'Add year',
                    onPressed: provider.isLoading
                        ? null
                        : () {
                            _closeDrawerIfNeeded(closeDrawerOnAction);
                            _showAddYearDialog();
                          },
                  ),
                  const SizedBox(width: 6),
                  ShellIconAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete year',
                    destructive: true,
                    onPressed: provider.isLoading || provider.years.length <= 1
                        ? null
                        : () {
                            _closeDrawerIfNeeded(closeDrawerOnAction);
                            _confirmDeleteYear();
                          },
                  ),
                ],
              ],
            ),
            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  provider.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _canEdit(BuildContext context) {
    return true;
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
      child: _destinations[_selectedIndex].child,
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
    required this.description,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
  final String description;
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

        return Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
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
                child: ShellSelectField(
                  icon: Icons.workspaces_outlined,
                  value: active.name,
                  isBusy: provider.isSwitching,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ShellIconAction(
              icon: Icons.add_rounded,
              tooltip: 'Add Workspace',
              onPressed: () => _showAddWorkspaceDialog(context, provider),
            ),
          ],
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
