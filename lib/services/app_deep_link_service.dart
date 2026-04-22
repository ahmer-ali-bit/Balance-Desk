import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class AppDeepLinkService extends ChangeNotifier {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<String>? _linkSubscription;
  bool _isInitialized = false;
  String? _pendingInviteLink;
  String? _lastDeliveredInviteLink;

  String? get pendingInviteLink => _pendingInviteLink;

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

  String? takePendingInviteLink() {
    final inviteLink = _pendingInviteLink;
    if (inviteLink == null) {
      return null;
    }

    _lastDeliveredInviteLink = inviteLink;
    _pendingInviteLink = null;
    return inviteLink;
  }

  bool isInviteLink(String? rawLink) {
    final uri = Uri.tryParse((rawLink ?? '').trim());
    if (uri == null) {
      return false;
    }

    return uri.scheme.toLowerCase() == 'balancedesk' &&
        uri.host.toLowerCase() == 'link-device' &&
        (uri.queryParameters['workspace'] ?? '').trim().isNotEmpty &&
        (uri.queryParameters['invite'] ?? '').trim().isNotEmpty &&
        (uri.queryParameters['token'] ?? '').trim().isNotEmpty;
  }

  void _storeIncomingLink(String? rawLink) {
    final normalizedLink = rawLink?.trim();
    if ((normalizedLink ?? '').isEmpty) {
      return;
    }
    if (!isInviteLink(normalizedLink)) {
      return;
    }
    if (_pendingInviteLink == normalizedLink ||
        _lastDeliveredInviteLink == normalizedLink) {
      return;
    }

    _pendingInviteLink = normalizedLink;
    notifyListeners();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
