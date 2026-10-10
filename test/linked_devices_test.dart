import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/sync_op.dart';
import 'package:shop/services/app_deep_link_service.dart';

void main() {
  group('AppDeepLinkService.parseInviteLink', () {
    const String workspace = 'ws-abc123def456abc12345';
    const String token =
        '0123456789abcdef0123456789abcdef'; // 32 hex chars = 128 bits

    test('accepts the canonical custom-scheme invite link', () {
      final PendingInviteLink? invite = AppDeepLinkService.parseInviteLink(
        'balancedesk://link-device?w=$workspace&t=$token',
      );

      expect(invite, isNotNull);
      expect(invite!.workspaceId, workspace);
      expect(invite.token, token);
    });

    test('accepts an https link carrying the same w/t pair', () {
      final PendingInviteLink? invite = AppDeepLinkService.parseInviteLink(
        'https://balancedesk.app/invite?w=$workspace&t=$token',
      );

      expect(invite, isNotNull);
      expect(invite!.token, token);
    });

    test('trims surrounding whitespace', () {
      expect(
        AppDeepLinkService.parseInviteLink(
          '  balancedesk://link-device?w=$workspace&t=$token\n',
        ),
        isNotNull,
      );
    });

    test('rejects a short token (rules require >= 32 chars)', () {
      expect(
        AppDeepLinkService.parseInviteLink(
          'balancedesk://link-device?w=$workspace&t=tooshort',
        ),
        isNull,
      );
    });

    test('rejects a missing workspace id', () {
      expect(
        AppDeepLinkService.parseInviteLink(
          'balancedesk://link-device?t=$token',
        ),
        isNull,
      );
    });

    test('rejects the wrong host on the custom scheme', () {
      expect(
        AppDeepLinkService.parseInviteLink(
          'balancedesk://something-else?w=$workspace&t=$token',
        ),
        isNull,
      );
    });

    test('rejects unrelated links and null', () {
      expect(AppDeepLinkService.parseInviteLink(null), isNull);
      expect(AppDeepLinkService.parseInviteLink(''), isNull);
      expect(
        AppDeepLinkService.parseInviteLink('https://example.com/nothing'),
        isNull,
      );
      expect(
        AppDeepLinkService.parseInviteLink('not a url at all'),
        isNull,
      );
    });
  });

  group('SyncOp.newOpId', () {
    test('is long enough for the Firestore rules (>= 26 chars)', () {
      final String opId = SyncOp.newOpId(
        deviceId: 'a1b2c3d4e5f6',
        counter: 0,
        at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(opId.length, greaterThanOrEqualTo(26));
    });

    test('sorts chronologically, which is how the journal is replayed', () {
      String idAt(int millis, int counter) => SyncOp.newOpId(
            deviceId: 'a1b2c3d4e5f6',
            counter: counter,
            at: DateTime.fromMillisecondsSinceEpoch(millis),
          );

      final List<String> ids = <String>[
        idAt(1700000000000, 0),
        idAt(1700000000001, 0),
        idAt(1700000000999, 0),
      ];

      final List<String> sorted = List<String>.from(ids)..sort();
      expect(sorted.first, idAt(1700000000000, 0));
      expect(sorted.last, idAt(1700000000999, 0));
    });

    test('stays unique for repeated ops inside the same millisecond', () {
      final DateTime now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final Set<String> ids = <String>{
        for (int i = 0; i < 50; i++)
          SyncOp.newOpId(deviceId: 'a1b2c3d4e5f6', counter: i, at: now),
      };

      expect(ids.length, 50);
    });

    test('embeds the origin device id used for the LWW tiebreak', () {
      final String opId = SyncOp.newOpId(
        deviceId: 'a1b2c3d4e5f6',
        counter: 7,
        at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(opId.split('-')[1], 'a1b2c3d4e5f6');
    });
  });

  group('SyncOp document shape', () {
    test('carries every field the Firestore rules validate', () {
      final Map<String, Object?> doc = const SyncOp(
        opId: '00000189-a1b2c3d4e5f6-000000',
        originDeviceId: 'a1b2c3d4e5f6',
        table: 'customers',
        rowId: '12',
        action: SyncOp.actionUpsert,
        updatedAt: 1700000000000,
        payload: <String, Object?>{'name': 'Ali'},
      ).toDocument();

      for (final String key in <String>[
        'opId',
        'originDeviceId',
        'table',
        'rowId',
        'action',
        'updatedAt',
        'payload',
        'createdAt',
      ]) {
        expect(doc.containsKey(key), isTrue, reason: 'missing $key');
      }
      expect(doc['updatedAt'], isA<int>());
      expect(doc['payload'], isA<Map<String, Object?>>());
    });
  });
}
