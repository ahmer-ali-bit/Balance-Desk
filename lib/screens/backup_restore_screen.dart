import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/csv_backup_service.dart';
import '../widgets/mobile_premium.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _service = CsvBackupService();
  List<FileInfo> _backups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final files = await _listBackupFiles();
    if (mounted) {
      setState(() {
        _backups = files;
        _isLoading = false;
      });
    }
  }

  Future<List<FileInfo>> _listBackupFiles() async {
    try {
      final dir = await _getBackupDir();
      if (!await dir.exists()) return [];
      final entities = dir.listSync();
      final files = <FileInfo>[];
      for (final e in entities) {
        if (e is! File) continue;
        if (p.extension(e.path).toLowerCase() != '.json') continue;
        final stat = e.statSync();
        files.add(
          FileInfo(
            path: e.path,
            name: p.basename(e.path),
            size: stat.size,
            modified: stat.modified,
          ),
        );
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      return files;
    } catch (_) {
      return [];
    }
  }

  Future<Directory> _getBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'shop_ledger', 'backups'));
  }

  Future<void> _createBackup() async {
    try {
      final path = await _service.createBackupFile();
      if (!mounted) return;
      if (path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved\n$path')));
      _refresh();
    } on CsvBackupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _saveBackupToFolder() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final fileName = _buildBackupFileName();
      final directoryPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select folder to save backup',
      );
      if (directoryPath == null || !mounted) return;
      final filePath = p.join(directoryPath, fileName);
      await _service.backupToFile(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved\n$filePath')));
      _refresh();
    } on CsvBackupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _buildBackupFileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'balance_desk_backup_$stamp.json';
  }

  Future<void> _pickAndRestore() async {
    try {
      final path = await _service.restoreBackupFile();
      if (!mounted || path == null || path.isEmpty) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup restored.')));
      _refresh();
    } on CsvBackupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _confirmRestore(String filePath, String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text('This will replace all current data with\n$fileName'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.restoreFromFile(filePath);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Backup restored.')));
        _refresh();
      }
    } on CsvBackupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (Platform.isAndroid || Platform.isIOS) {
      return _buildPremiumMobileBackupScreen(theme, cs);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Platform.isAndroid || Platform.isIOS) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        theme,
                        cs,
                        icon: Icons.backup_rounded,
                        label: 'Quick Backup',
                        onTap: _createBackup,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionCard(
                        theme,
                        cs,
                        icon: Icons.folder_open_rounded,
                        label: 'Save to…',
                        onTap: _saveBackupToFolder,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionCard(
                        theme,
                        cs,
                        icon: Icons.restore_page_rounded,
                        label: 'Pick & Restore',
                        onTap: _pickAndRestore,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        theme,
                        cs,
                        icon: Icons.backup_rounded,
                        label: 'Create Backup',
                        onTap: _createBackup,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionCard(
                        theme,
                        cs,
                        icon: Icons.restore_page_rounded,
                        label: 'Pick & Restore',
                        onTap: _pickAndRestore,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 14, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'RECENT BACKUPS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_backups.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.folder_off_rounded,
                          color: cs.primary.withValues(alpha: 0.4),
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No backups found',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Quick Backup" above',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._backups.map((f) => _buildFileCard(theme, cs, f)),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumMobileBackupScreen(ThemeData theme, ColorScheme cs) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: MobilePremiumPage(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                MobilePremiumHeader(
                  icon: Icons.backup_rounded,
                  title: 'Backups',
                  subtitle: '${_backups.length} saved restore points',
                  trailing: IconButton(
                    tooltip: 'Refresh backups',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  children: <Widget>[
                    MobileMetricGrid(
                      children: <Widget>[
                        MobileMetricTile(
                          label: 'Local',
                          value: '${_backups.length}',
                          icon: Icons.folder_rounded,
                          color: cs.primary,
                        ),
                        MobileMetricTile(
                          label: 'Format',
                          value: 'JSON',
                          icon: Icons.data_object_rounded,
                          color: cs.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MobilePremiumPanel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _createBackup,
                              icon: const Icon(Icons.backup_rounded),
                              label: const Text('Create Backup'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickAndRestore,
                              icon: const Icon(Icons.restore_page_rounded),
                              label: const Text('Pick & Restore'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MobileSectionHeader(
                  title: 'Recent Backups',
                  count: '${_backups.length}',
                ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const MobilePremiumPanel(
                    child: SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_backups.isEmpty)
                  MobilePremiumPanel(
                    child: Column(
                      children: <Widget>[
                        Icon(
                          Icons.folder_off_rounded,
                          color: cs.onSurfaceVariant,
                          size: 42,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No backups found',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: <Widget>[
                      for (var index = 0; index < _backups.length; index++) ...[
                        if (index != 0) const SizedBox(height: 10),
                        _buildPremiumMobileBackupFile(
                          theme,
                          cs,
                          _backups[index],
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumMobileBackupFile(
    ThemeData theme,
    ColorScheme cs,
    FileInfo file,
  ) {
    return MobilePremiumPanel(
      onTap: () => _confirmRestore(file.path, file.name),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(kMobilePremiumRadius),
            ),
            child: Icon(Icons.description_rounded, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    file.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontFamily: 'RobotoMono',
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(file.modified)} - ${_formatSize(file.size)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore backup',
            onPressed: () => _confirmRestore(file.path, file.name),
            icon: const Icon(Icons.restore_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    ThemeData theme,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.primary, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(ThemeData theme, ColorScheme cs, FileInfo f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _confirmRestore(f.path, f.name),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          f.name,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'RobotoMono',
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(f.modified)}  ·  ${_formatSize(f.size)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.restore_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () => _confirmRestore(f.path, f.name),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modified;
  const FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });
}
