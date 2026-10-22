import 'package:flutter_test/flutter_test.dart';
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
}
