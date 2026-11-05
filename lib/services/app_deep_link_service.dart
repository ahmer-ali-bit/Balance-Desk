import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class AppDeepLinkService extends ChangeNotifier {
  AppDeepLinkService._();

  static final AppDeepLinkService instance = AppDeepLinkService._();

  /// Workspace invites are shared as `balancedesk://join?token=<code>`.
  static const String _inviteScheme = 'balancedesk';
  static const String _inviteHost = 'join';
  static const String _tokenParameter = 'token';

  final AppLinks _appLinks = AppLinks();

  StreamSubscription<String>? _linkSubscription;
  bool _isInitialized = false;
  String? _pendingInviteToken;

  /// Invite code from the most recent invite link, kept until it is consumed.
  ///
  /// Stored rather than acted on directly because a link can arrive before any
  /// screen is mounted, for example when the link is what launched the app.
  String? get pendingInviteToken => _pendingInviteToken;

  bool get hasPendingInvite => _pendingInviteToken != null;

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

  bool isInviteLink(String? rawLink) => _extractInviteToken(rawLink) != null;

  /// Returns the pending invite code and clears it, so the join screen opens
  /// once per link instead of on every rebuild.
  String? takePendingInviteToken() {
    final String? token = _pendingInviteToken;
    if (token == null) {
      return null;
    }
    _pendingInviteToken = null;
    return token;
  }

  void clearPendingInvite() {
    if (_pendingInviteToken == null) {
      return;
    }
    _pendingInviteToken = null;
    notifyListeners();
  }

  void _storeIncomingLink(String? rawLink) {
    final String? token = _extractInviteToken(rawLink);
    if (token == null) {
      return;
    }

    _pendingInviteToken = token;
    notifyListeners();
  }

  static String? _extractInviteToken(String? rawLink) {
    final String trimmed = rawLink?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != _inviteScheme) {
      return null;
    }

    // `balancedesk://join?token=x` puts `join` in the host, while the
    // schemeless-authority form `balancedesk:join?token=x` puts it in the path.
    final String target = (uri.host.isEmpty ? uri.path : uri.host)
        .replaceAll('/', '')
        .toLowerCase();
    if (target != _inviteHost) {
      return null;
    }

    final String token = uri.queryParameters[_tokenParameter]?.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
