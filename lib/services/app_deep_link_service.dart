import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class AppDeepLinkService extends ChangeNotifier {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<String>? _linkSubscription;
  bool _isInitialized = false;
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    try {
      final initialLink = await _appLinks.getInitialLinkString();
      _storeIncomingLink(initialLink);
    } catch (_) {
      // Ignore startup link errors so app launch is not blocked.
    }

    _linkSubscription = _appLinks.stringLinkStream.listen(
      _storeIncomingLink,
      onError: (_) {
        // Ignore transient deep-link listener errors.
      },
    );
  }

  bool isInviteLink(String? rawLink) {
    return false;
  }

  void _storeIncomingLink(String? rawLink) {
    // Deep linking logic for local operations can be added here.
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
