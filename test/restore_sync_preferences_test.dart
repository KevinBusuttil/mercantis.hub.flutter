import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Folder sync is turned off before a restore commits, so a crash after the
/// restored books are installed cannot sync them into the previous shared
/// folder; a restore that does not go ahead gives the settings back.
void main() {
  test('suspend clears folder sync; resume puts it back', () async {
    SharedPreferences.setMockInitialValues({
      'hub.company_folder': '/shared/books',
      'hub.auto_sync': true,
      'hub.theme': 'dark',
    });
    final saved = await HubBackup.suspendFolderSync();
    final prefs = await SharedPreferences.getInstance();
    for (final k in clearedOnRestorePreferenceKeys) {
      expect(prefs.containsKey(k), isFalse, reason: k);
    }
    expect(prefs.getString('hub.theme'), 'dark');

    await HubBackup.resumeFolderSync(saved);
    expect(prefs.getString('hub.company_folder'), '/shared/books');
    expect(prefs.getBool('hub.auto_sync'), isTrue);
  });

  test("restored settings are the backup's: one it lacked is removed",
      () async {
    SharedPreferences.setMockInitialValues({
      'core.theme_mode': 'light',
      'capture.ai.settings': '{"enabled":true}',
    });
    final staged = StagedRestore(
      header: BackupHeader(
        formatVersion: BackupHeader.currentFormat,
        createdAt: DateTime(2026, 10, 1),
        producer: 'test',
        kdf: BackupKdfParams.generate(memoryKiB: 1024, iterations: 1),
        noncePrefix: List<int>.filled(BackupCipher.noncePrefixLength, 0),
      ),
      manifest: const {},
      stagingDirectory: '/nonexistent',
      databasePath: '/nonexistent/db',
      attachmentsDirectory: '/nonexistent/a',
      configFiles: {
        'preferences.json': utf8.encode(jsonEncode({'core.theme_mode': 'dark'})),
      },
      schemaVersion: 1,
      tableCounts: const {},
    );
    await HubBackup.applyRestoredPreferences(staged);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('core.theme_mode'), 'dark');
    expect(prefs.containsKey('capture.ai.settings'), isFalse);
  });
}
