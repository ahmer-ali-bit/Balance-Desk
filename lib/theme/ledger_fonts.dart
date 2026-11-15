import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// Uses built-in macOS typefaces on that platform; other platforms retain the
/// existing bundled Ledger Pro fonts.
class LedgerFonts {
  LedgerFonts._();

  static bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  static String get sans => _isMacOS ? 'Helvetica Neue' : 'Lato';
  static String get mono => _isMacOS ? 'Menlo' : 'IBM Plex Mono';
}
