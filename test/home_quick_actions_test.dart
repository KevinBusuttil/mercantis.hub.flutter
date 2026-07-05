import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/workspaces/home_workspace.dart';

/// The Notification inbox (ADR-048) and Recents views are surfaced from the Home
/// workspace's quick actions, routing to the routes wired in hub_navigation.
void main() {
  test('home workspace surfaces Notifications and Recents quick actions', () {
    final byRoute = {
      for (final qa in homeWorkspace.quickActions)
        if (qa.routeName != null) qa.routeName: qa,
    };
    expect(byRoute['/w/home/notifications']?.label, 'Notifications');
    expect(byRoute['/w/home/recents']?.label, 'Recents');
  });
}
