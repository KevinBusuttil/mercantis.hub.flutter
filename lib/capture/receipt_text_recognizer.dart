import 'dart:io' show File, Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device text recognition for a receipt image (ADR-049). Abstracted so the
/// mobile ML Kit engine and the desktop/test fallback are interchangeable.
/// Extraction-only — it reads text, nothing else; it never posts or submits.
abstract class ReceiptTextRecognizer {
  /// Whether this device can recognise text. Desktop and the test host return
  /// false, and the capture flow falls back to manual entry.
  bool get isAvailable;

  /// Recognise the text in the image at [imagePath]. Returns null when
  /// recognition is unavailable or nothing legible was found.
  Future<String?> recognise(String imagePath);
}

/// Google ML Kit text recognition — free, offline, on-device. Android/iOS only;
/// other platforms report [isAvailable] false and never touch the plugin.
class MlKitReceiptTextRecognizer implements ReceiptTextRecognizer {
  @override
  bool get isAvailable => Platform.isAndroid || Platform.isIOS;

  @override
  Future<String?> recognise(String imagePath) async {
    if (!isAvailable) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(File(imagePath)));
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      // A recognition failure is never fatal — the document just goes to manual
      // review rather than crashing the capture.
      return null;
    } finally {
      await recognizer.close();
    }
  }
}

/// Fallback for platforms without on-device OCR (desktop, tests). Always defers
/// to manual entry.
class UnavailableTextRecognizer implements ReceiptTextRecognizer {
  const UnavailableTextRecognizer();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> recognise(String imagePath) async => null;
}

/// Selects the recogniser for the current platform.
final receiptTextRecognizerProvider = Provider<ReceiptTextRecognizer>((ref) {
  if (Platform.isAndroid || Platform.isIOS) {
    return MlKitReceiptTextRecognizer();
  }
  return const UnavailableTextRecognizer();
});
