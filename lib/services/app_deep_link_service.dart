import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// One invite link waiting to be redeemed.
class PendingInviteLink {
  const PendingInviteLink({
    required this.workspaceId,
    required this.token,
    required this.rawLink,
  });

  final String workspaceId;
  final String token;
  final String rawLink;
}

/// Receives `balancedesk://link-device?w=<workspaceId>&t=<token>` deep links.
///
/// The scheme is registered on Android (intent filter), iOS/macOS
/// (`CFBundleURLSchemes`) and Windows (registry entry written by the Inno
/// Setup installer), so the same invite link works everywhere and the same
/// string is what gets encoded into the QR code.
///
/// Links that arrive before the UI is ready are buffered in [pendingInvite],
/// so a cold start from an invite link is not lost.
class AppDeepLinkService extends ChangeNotifier {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  static const String scheme = 'balancedesk';
  static const String linkHost = 'link-device';
  static const String workspaceParam = 'w';
  static const String tokenParam = 't';

  final AppLinks _appLinks = AppLinks();
  final StreamController<PendingInviteLink> _inviteController =
      StreamController<PendingInviteLink>.broadcast();

  StreamSubscription<String>? _linkSubscription;
  bool _isInitialized = false;
  PendingInviteLink? _pendingInvite;
  String? _lastRawLink;

  /// Emits every invite link that arrives while the app is running.
  Stream<PendingInviteLink> get inviteLinks => _inviteController.stream;

  /// Invite link captured at launch (or before a listener attached).
  PendingInviteLink? get pendingInvite => _pendingInvite;

  bool get hasPendingInvite => _pendingInvite != null;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    try {
      final String? initialLink = await _appLinks.getInitialLinkString();
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

  /// True when [rawLink] is a well-formed Balance Desk invite link.
  bool isInviteLink(String? rawLink) => parseInviteLink(rawLink) != null;

  /// Parses an invite link, returning null when it is not one.
  ///
  /// Accepts the custom scheme (`balancedesk://link-device?w=…&t=…`) and, for
  /// convenience, any `https://` link carrying the same `w`/`t` pair so a
  /// future Universal/App Link deployment keeps working unchanged.
  static PendingInviteLink? parseInviteLink(String? rawLink) {
    if (rawLink == null || rawLink.trim().isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(rawLink.trim());
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    final bool isCustomScheme =
        uri.scheme.toLowerCase() == scheme && uri.host == linkHost;
    final bool isHttpsWithParams =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.queryParameters.containsKey(workspaceParam) &&
            uri.queryParameters.containsKey(tokenParam);

    if (!isCustomScheme && !isHttpsWithParams) {
      return null;
    }

    final String workspaceId = uri.queryParameters[workspaceParam] ?? '';
    final String token = uri.queryParameters[tokenParam] ?? '';

    if (workspaceId.isEmpty || token.length < 32) {
      return null;
    }

    return PendingInviteLink(
      workspaceId: workspaceId,
      token: token,
      rawLink: rawLink.trim(),
    );
  }

  /// Called by the UI once it has consumed the buffered link.
  void clearPendingInvite() {
    _pendingInvite = null;
    notifyListeners();
  }

  void _storeIncomingLink(String? rawLink) {
    if (rawLink == null || rawLink == _lastRawLink) {
      return;
    }
    _lastRawLink = rawLink;

    final PendingInviteLink? invite = parseInviteLink(rawLink);
    if (invite == null) {
      return;
    }

    _pendingInvite = invite;
    _inviteController.add(invite);
    notifyListeners();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _inviteController.close();
    super.dispose();
  }
}
