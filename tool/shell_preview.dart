// Throwaway visual harness for iterating on the shell chrome.
// Run with: flutter run -d chrome -t tool/shell_preview.dart
import 'package:flutter/material.dart';

import 'package:shop/theme/balance_desk_theme.dart';
import 'package:shop/widgets/app_shell_chrome.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BalanceDeskTheme.desktopTheme(),
      home: const _PreviewPage(),
    ),
  );
}

const List<ShellNavEntry> _entries = <ShellNavEntry>[
  ShellNavEntry(
    label: 'Customers',
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt,
    description: 'Accounts and balances',
  ),
  ShellNavEntry(
    label: 'Summary',
    icon: Icons.assessment_outlined,
    selectedIcon: Icons.assessment,
    description: 'Year at a glance',
  ),
  ShellNavEntry(
    label: 'Daily Logs',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    description: 'Snapshot history',
  ),
];

class _PreviewPage extends StatefulWidget {
  const _PreviewPage();

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  int _index = 0;

  Widget _sidebar({bool compact = false}) {
    return AppShellSidebar(
      companyName: 'Ahmer Traders',
      subtitle: 'Accounting command center',
      logo: null,
      yearControl: Row(
        children: <Widget>[
          const Expanded(
            child: ShellSelectField(
              icon: Icons.calendar_month_outlined,
              value: '2026',
            ),
          ),
          const SizedBox(width: 6),
          ShellIconAction(
            icon: Icons.add_rounded,
            tooltip: 'Add year',
            onPressed: () {},
          ),
          const SizedBox(width: 6),
          ShellIconAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete year',
            destructive: true,
            onPressed: () {},
          ),
        ],
      ),
      workspaceControl: Row(
        children: <Widget>[
          const Expanded(
            child: ShellSelectField(
              icon: Icons.workspaces_outlined,
              value: 'Main Shop',
            ),
          ),
          const SizedBox(width: 6),
          ShellIconAction(
            icon: Icons.add_rounded,
            tooltip: 'Add Workspace',
            onPressed: () {},
          ),
        ],
      ),
      navEntries: _entries,
      selectedIndex: _index,
      onSelectIndex: (int i) => setState(() => _index = i),
      tools: <ShellToolEntry>[
        ShellToolEntry(
          icon: Icons.business_outlined,
          label: 'Company Profile',
          onTap: () {},
        ),
        ShellToolEntry(
          icon: Icons.edit_note_outlined,
          label: 'Notes',
          onTap: () {},
          badge: true,
        ),
        ShellToolEntry(
          icon: Icons.backup_rounded,
          label: 'Backup & Restore',
          onTap: () {},
        ),
        ShellToolEntry(
          icon: Icons.lock_outline_rounded,
          label: 'Set App PIN',
          onTap: () {},
        ),
        ShellToolEntry(
          icon: Icons.system_update_alt_outlined,
          label: 'Check for Update',
          onTap: () {},
        ),
      ],
      showNavEntries: true,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppShellBackdrop(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final narrow = constraints.maxWidth < 1000;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 28,
                runSpacing: 28,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: <Widget>[
                  _frame(
                    label: 'Desktop 1440 x 900',
                    width: narrow ? constraints.maxWidth - 40 : 1080,
                    height: 800,
                    child: _desktop(),
                  ),
                  _frame(
                    label: 'Mobile 390 x 844',
                    width: 390,
                    height: 700,
                    child: _mobile(),
                  ),
                  _frame(
                    label: 'Sidebar rail',
                    width: 120,
                    height: 520,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _sidebar(compact: true),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _frame({
    required String label,
    required double width,
    required double height,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  Widget _desktop() {
    final entry = _entries[_index];
    return Row(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
          child: SizedBox(width: ShellMetrics.sidebarWidth, child: _sidebar()),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 16),
            child: Column(
              children: <Widget>[
                ShellPageHeader(
                  eyebrow: 'Balance Desk',
                  title: entry.label,
                  subtitle: entry.description,
                  trailing: const ShellChip(
                    icon: Icons.calendar_month_outlined,
                    label: 'FY 2026',
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(child: ShellContentSheet(child: _fakePage())),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobile() {
    final entry = _entries[_index];
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: ShellMobileHeader(
            onMenu: () {},
            companyName: 'Ahmer Traders',
            title: entry.label,
            icon: entry.selectedIcon,
          ),
        ),
        Expanded(child: ShellContentSheet(radius: 20, child: _fakePage())),
        const SizedBox(height: 8),
        ShellMobileDock(
          entries: _entries,
          selectedIndex: _index,
          onSelected: (int i) => setState(() => _index = i),
        ),
      ],
    );
  }

  Widget _fakePage() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'Search customers',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, int i) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.16,
                      ),
                      child: Text(
                        'A${i + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Customer ${i + 1}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'PKR 12,500',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
