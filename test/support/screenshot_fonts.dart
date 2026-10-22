import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Real-font loading for screenshot tests (the default test font renders
/// glyphs as boxes). Same approach as the marketing golden: a system sans
/// for text and the SDK's Material Icons for icons, so captures read like the
/// running app. Call [loadScreenshotFonts] inside `tester.runAsync`.
const _fontFamily = 'AtlasScreenshot';

Future<void> _loadReadableMarketingFont() async {
  const candidates = <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
  ];

  File? fontFile;
  for (final path in candidates) {
    final candidate = File(path);
    if (candidate.existsSync()) {
      fontFile = candidate;
      break;
    }
  }

  if (fontFile == null) {
    throw StateError('No readable CI font found for Atlas screenshot capture.');
  }

  final bytes = fontFile.readAsBytesSync();
  for (final family in const [_fontFamily]) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

String _flutterRootFromExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    directory = directory.parent;
  }
  return directory.path;
}

Future<void> _loadMaterialIcons() async {
  final candidates = <String>[];
  final environmentRoot = Platform.environment['FLUTTER_ROOT'];
  if (environmentRoot != null && environmentRoot.isNotEmpty) {
    candidates.add(
      '$environmentRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
  candidates.add(
    '${_flutterRootFromExecutable()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );

  File? iconFile;
  for (final path in candidates) {
    final candidate = File(path);
    if (candidate.existsSync()) {
      iconFile = candidate;
      break;
    }
  }

  if (iconFile == null) {
    throw StateError('Material Icons font was not found in the Flutter SDK.');
  }

  final bytes = iconFile.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> loadScreenshotFonts() async {
  await Future.wait([
    _loadReadableMarketingFont(),
    _loadMaterialIcons(),
  ]);
}

ThemeData screenshotTheme() {
  final base = MercantisTheme.light();
  final textTheme = base.textTheme.apply(fontFamily: _fontFamily);
  final primaryTextTheme =
      base.primaryTextTheme.apply(fontFamily: _fontFamily);
  final colorScheme = base.colorScheme;

  // Button themes carry their own family-less text styles; give them the
  // screenshot family too.
  const buttonText = WidgetStatePropertyAll(
      TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600));
  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(textStyle: buttonText)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(textStyle: buttonText)),
    textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(textStyle: buttonText)),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

