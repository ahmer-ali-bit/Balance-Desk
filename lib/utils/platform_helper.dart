import 'dart:io';

class PlatformHelper {
  const PlatformHelper._();

  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool get supportsQrScanner => isMobile;

  static String get platformLabel {
    if (isAndroid) {
      return 'Android';
    }
    if (isIOS) {
      return 'iPhone';
    }
    if (isWindows) {
      return 'Windows';
    }
    if (isMacOS) {
      return 'macOS';
    }
    if (isLinux) {
      return 'Linux';
    }
    return 'Unknown';
  }
}
