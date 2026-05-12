import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/linked_session_provider.dart';

class DisconnectConfirmScreen extends StatefulWidget {
  const DisconnectConfirmScreen({super.key});

  @override
  State<DisconnectConfirmScreen> createState() => _DisconnectConfirmScreenState();
}

class _DisconnectConfirmScreenState extends State<DisconnectConfirmScreen> {
  bool _isLoading = false;

  Future<void> _handleDisconnect() async {
    setState(() => _isLoading = true);
    
    final provider = context.read<LinkedSessionProvider>();
    await provider.disconnect(context);

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected successfully. Your own workspace has been restored.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(); // Go back to LinkedDevicesScreen which will reflect the state
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Termination Protocol'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: cs.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.link_off_rounded, size: 48, color: cs.error),
                ),
                const SizedBox(height: 32),
                Text(
                  'Disconnect Instance?',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'This action will terminate your connection to the administrative node. Your local workspace will be fully restored.',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                if (_isLoading)
                  const CircularProgressIndicator()
                else ...[
                  _buildPremiumActionButton(
                    onPressed: _handleDisconnect,
                    label: 'Terminate Connection',
                    cs: cs,
                    isDestructive: true,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel Operation', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumActionButton({
    required VoidCallback onPressed,
    required String label,
    required ColorScheme cs,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? cs.error : cs.primary;
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}
