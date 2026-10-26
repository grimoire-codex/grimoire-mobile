import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_mobile/core/settings.dart';
import 'package:grimoire_mobile/core/storage.dart';
import 'package:grimoire_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('signed out, the app opens on the server step of sign-in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tmp = Directory.systemTemp.createTempSync('grimoire-app');
    addTearDown(() => tmp.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          storageDirsProvider.overrideWithValue(StorageDirs(data: tmp, cache: tmp)),
        ],
        child: const GrimoireApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect to your own Grimoire server.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // No tabs until signed in.
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your Grimoire address.'), findsOneWidget);
  });
}
