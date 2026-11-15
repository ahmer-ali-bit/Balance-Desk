import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pro/services/linked_device_credentials.dart';

void main() {
  group('LinkedWorkspaceConfig return workspace', () {
    test('preserves the previous workspace through JSON and cursor updates', () {
      const config = LinkedWorkspaceConfig(
        localWorkspaceId: 'linked_cloud-id',
        cloudWorkspaceId: 'cloud-id',
        deviceId: 'device-id',
        role: 'linked',
        permission: 'read_only',
        cursor: 4,
        allowExport: true,
        returnWorkspaceId: 'my-local-workspace',
      );

      final restored = LinkedWorkspaceConfig.fromJson(
        Map<String, dynamic>.from(config.toJson()),
      );
      final advanced = restored.copyWith(cursor: 9);

      expect(restored.returnWorkspaceId, 'my-local-workspace');
      expect(advanced.returnWorkspaceId, 'my-local-workspace');
      expect(advanced.cursor, 9);
      expect(restored.canExport, isTrue);
      expect(advanced.allowExport, isTrue);
    });

    test('accepts configs created before return workspace was stored', () {
      final legacy = LinkedWorkspaceConfig.fromJson(<String, dynamic>{
        'localWorkspaceId': 'linked_cloud-id',
        'cloudWorkspaceId': 'cloud-id',
        'deviceId': 'device-id',
        'role': 'linked',
        'permission': 'edit',
        'cursor': 0,
      });

      expect(legacy.returnWorkspaceId, isNull);
      expect(legacy.allowExport, isFalse);
      expect(legacy.canExport, isTrue);

      final legacyReadOnly = LinkedWorkspaceConfig.fromJson(<String, dynamic>{
        'localWorkspaceId': 'linked_cloud-id',
        'cloudWorkspaceId': 'cloud-id',
        'deviceId': 'device-id',
        'role': 'linked',
        'permission': 'read_only',
        'cursor': 0,
      });
      expect(legacyReadOnly.canExport, isFalse);
    });
  });
}
