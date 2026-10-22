import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Removes what a support bundle must never carry: e-mail addresses,
/// credentials and tokens, card/IBAN/phone-like digit runs, money amounts,
/// URL query strings and the user's home folder. Applied when an error is
/// RECORDED, so nothing sensitive is ever written to the log file.
///
/// It is deliberately coarse. A diagnostic loses a little detail; a customer
/// never loses a secret.
class DiagnosticRedactor {
  const DiagnosticRedactor._();

  /// Longest message kept, after redaction.
  static const maxMessageLength = 600;

  static final _rules = <(RegExp, String)>[
    // Authorization headers and bearer tokens.
    (RegExp(r'(bearer|basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        r'$1 [token]'),
    // key=value / "key": "value" secrets.
    (
      RegExp(
          r'''(api[_-]?key|apikey|token|secret|password|passphrase|passcode|pin|authorization|x-api-key)(["']?\s*[:=]\s*["']?)[^\s"',;&]+''',
          caseSensitive: false),
      r'$1$2[redacted]'
    ),
    // Provider-style keys (sk-..., ghp_..., xox...) and JWTs.
    (RegExp(r'\b(sk|pk|rk)-[A-Za-z0-9_-]{8,}'), '[key]'),
    (RegExp(r'\b(ghp|gho|ghs|xox[abpr])[_-][A-Za-z0-9_-]{8,}'), '[key]'),
    (RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'), '[jwt]'),
    // E-mail addresses.
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '[email]'),
    // URL query strings (may carry tokens or names).
    (RegExp(r'(https?://[^\s?#]+)\?[^\s]*'), r'$1?[query]'),
    // IBAN-like account numbers.
    (RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9 ]{11,30}\b'), '[account]'),
    // Card numbers in 4-digit groups, then long digit runs (phones, bank
    // accounts). Dashed runs are left alone so dates and document numbers
    // such as SINV-2026-00001 stay readable.
    (RegExp(r'\b\d{4}([ -])\d{4}\1\d{4}\1\d{1,4}\b'), '[number]'),
    (RegExp(r'\+?\d(?: ?\d){8,}'), '[number]'),
    // Money-shaped amounts, so balances never leave the device.
    // Version numbers such as 6.18.44 are left alone.
    (RegExp(r'(?<![\d.,])\d+(?:,\d{3})*[.,]\d{2}(?![\d.,])'), '[amount]'),
    // The user's home folder in file paths.
    (RegExp(r'(/Users/|/home/|C:\\Users\\)[^/\\\s]+', caseSensitive: false),
        r'$1[user]'),
  ];

  static String redact(String input) {
    var out = input;
    for (final (pattern, replacement) in _rules) {
      out = out.replaceAllMapped(pattern, (m) {
        return replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) {
          final i = int.parse(g.group(1)!);
          return i <= m.groupCount ? (m.group(i) ?? '') : '';
        });
      });
    }
    if (out.length > maxMessageLength) {
      out = '${out.substring(0, maxMessageLength)}…';
    }
    return out;
  }

  /// Keeps only the code location of each frame (package/file:line), at most
  /// [maxFrames] of them. Frames never carry data, but trimming keeps the
  /// bundle readable.
  static String? redactStack(StackTrace? stack, {int maxFrames = 12}) {
    if (stack == null) return null;
    final lines = stack
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(maxFrames)
        .map(redact)
        .toList();
    return lines.isEmpty ? null : lines.join('\n');
  }
}

/// One recorded problem.
@immutable
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.at,
    required this.source,
    required this.message,
    this.stack,
  });

  final DateTime at;

  /// Where it was caught: `flutter`, `platform`, `posting`, `backup`, `boot`…
  final String source;
  final String message;
  final String? stack;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'source': source,
        'message': message,
        if (stack != null) 'stack': stack,
      };

  static DiagnosticEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return DiagnosticEvent(
      at: at,
      source: '${json['source'] ?? 'unknown'}',
      message: '${json['message'] ?? ''}',
      stack: json['stack'] as String?,
    );
  }
}

/// A small, privacy-filtered record of recent application errors, kept on
/// this device so a support case can be diagnosed without developer tools
/// (plan M1.6).
///
/// - Errors are redacted ([DiagnosticRedactor]) before they are stored.
/// - At most [capacity] events are kept, newest last.
/// - Once [attach]ed to the data folder the log survives restarts in
///   `diagnostics/errors.jsonl`. Before that (early boot) it is memory-only.
/// - Nothing here ever leaves the device on its own: the user exports it from
///   Settings › Help & diagnostics.
class DiagnosticLog {
  DiagnosticLog({this.capacity = 50});

  /// The app-wide log.
  static final instance = DiagnosticLog();

  static const folderName = 'diagnostics';
  static const fileName = 'errors.jsonl';

  final int capacity;
  final List<DiagnosticEvent> _events = [];
  File? _file;
  bool _installed = false;

  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  /// Routes uncaught framework and platform errors here, keeping Flutter's
  /// own reporting (console in debug) intact.
  void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record('flutter', details.exception, details.stack);
      if (previousFlutter != null) {
        previousFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousPlatform = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      record('platform', error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  /// Persist to `<dataDirectory>/diagnostics/errors.jsonl`, merging what is
  /// already there (earlier sessions) with what was recorded during boot.
  Future<void> attach(String dataDirectory) async {
    try {
      final dir = Directory(p.join(dataDirectory, folderName));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, fileName));
      final earlier = <DiagnosticEvent>[];
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            final e = DiagnosticEvent.fromJson(jsonDecode(line));
            if (e != null) earlier.add(e);
          } catch (_) {
            // A torn last line from a crash: skip it.
          }
        }
      }
      _events
        ..insertAll(0, earlier)
        ..sort((a, b) => a.at.compareTo(b.at));
      _trim();
      _file = file;
      await _rewrite();
    } catch (_) {
      // Diagnostics must never stop the app from starting.
    }
  }

  /// Record [error] (redacted). Safe to call from anywhere, never throws.
  void record(String source, Object error, [StackTrace? stack]) {
    try {
      final event = DiagnosticEvent(
        at: DateTime.now(),
        source: source,
        message: DiagnosticRedactor.redact('$error'),
        stack: DiagnosticRedactor.redactStack(stack),
      );
      _events.add(event);
      final trimmed = _trim();
      final file = _file;
      if (file == null) return;
      if (trimmed) {
        unawaited(_rewrite());
      } else {
        file.writeAsStringSync('${jsonEncode(event.toJson())}\n',
            mode: FileMode.append, flush: true);
      }
    } catch (_) {
      // Never let error reporting raise an error.
    }
  }

  /// Forget every recorded event, on disk too.
  Future<void> clear() async {
    _events.clear();
    await _rewrite();
  }

  bool _trim() {
    if (_events.length <= capacity) return false;
    _events.removeRange(0, _events.length - capacity);
    return true;
  }

  Future<void> _rewrite() async {
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          _events.map((e) => '${jsonEncode(e.toJson())}\n').join(),
          flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }
}
