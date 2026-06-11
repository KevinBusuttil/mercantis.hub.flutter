import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/capture/receipt_text_recognizer.dart';

/// ADR-049: the OCR abstraction. On the Linux test host there's no on-device
/// recogniser, so the provider must hand back the graceful fallback rather than
/// touch ML Kit — proving the capture flow degrades to manual entry off-device.
void main() {
  test('provider yields an unavailable recogniser off-device', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final recognizer = container.read(receiptTextRecognizerProvider);
    expect(recognizer.isAvailable, isFalse);
  });

  test('unavailable recogniser returns null instead of throwing', () async {
    const recognizer = UnavailableTextRecognizer();
    expect(await recognizer.recognise('/nonexistent/receipt.jpg'), isNull);
  });
}
