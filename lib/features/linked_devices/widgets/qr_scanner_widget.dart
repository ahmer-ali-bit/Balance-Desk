import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR Scanner widget — uses mobile_scanner on Android/iOS.
/// On desktop/web, shows a manual token input fallback.
class QrScannerWidget extends StatelessWidget {
  const QrScannerWidget({
    super.key,
    required this.onScanned,
    required this.onClose,
  });

  final void Function(String value) onScanned;
  final VoidCallback onClose;

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (_isMobile) {
      return _MobileScanner(onScanned: onScanned, onClose: onClose);
    }
    return _DesktopFallback(onScanned: onScanned, onClose: onClose);
  }
}

/// Mobile scanner using the camera.
class _MobileScanner extends StatefulWidget {
  const _MobileScanner({required this.onScanned, required this.onClose});
  final void Function(String) onScanned;
  final VoidCallback onClose;

  @override
  State<_MobileScanner> createState() => _MobileScannerState();
}

class _MobileScannerState extends State<_MobileScanner> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_isScanned) return;
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final rawValue = barcode.rawValue;
              if (rawValue != null) {
                _isScanned = true;
                widget.onScanned(rawValue);
                break;
              }
            }
          },
        ),
        // Overlay / Close button
        Positioned(
          top: 10,
          right: 10,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
            onPressed: widget.onClose,
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
          ),
        ),
        // Scanner border overlay
        Center(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop/Fallback: manual token paste input
class _DesktopFallback extends StatefulWidget {
  const _DesktopFallback({required this.onScanned, required this.onClose});
  final void Function(String) onScanned;
  final VoidCallback onClose;

  @override
  State<_DesktopFallback> createState() => _DesktopFallbackState();
}

class _DesktopFallbackState extends State<_DesktopFallback> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: cs.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enter Token Manually',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16,
                      color: cs.onSurface),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            style: const TextStyle(fontFamily: 'RobotoMono', fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Paste QR token or invite link here',
              prefixIcon: Icon(Icons.vpn_key_rounded, color: cs.primary),
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                final val = _controller.text.trim();
                if (val.isNotEmpty) widget.onScanned(val);
              },
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Submit Token',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
