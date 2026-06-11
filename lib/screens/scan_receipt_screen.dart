import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/capture_providers.dart';
import '../capture/receipt_text_recognizer.dart';

/// Mobile-first intake for Document Capture (ADR-049): take a photo or pick a
/// file, then hand off to the review screen. Deliberately two big buttons — no
/// configuration, nothing to learn.
class ScanReceiptScreen extends ConsumerStatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  ConsumerState<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends ConsumerState<ScanReceiptScreen> {
  bool _busy = false;
  String? _error;

  bool get _cameraSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (e) {
      setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
      return;
    }
    if (file == null) return; // cancelled

    setState(() => _busy = true);
    try {
      final service = await ref.read(captureServiceProvider.future);
      final capture = await service.captureFromImage(
        imagePath: file.path,
        sourceType: source == ImageSource.camera ? 'Camera' : 'Upload',
      );
      ref.invalidate(capturesProvider);
      if (!mounted) return;
      context.go('/w/home/capture-review?id=${capture.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not process that image. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recognizer = ref.watch(receiptTextRecognizerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: _busy
          ? const _Busy()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Icon(Icons.receipt_long_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Capture a receipt or bill',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      recognizer.isAvailable
                          ? "We'll read the amount, date and merchant for you to confirm."
                          : "We'll create a draft for you to fill in. (Automatic reading is available on phone and tablet.)",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    if (_cameraSupported)
                      FilledButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        label: const Text('Take a photo'),
                      ),
                    if (_cameraSupported) const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.attach_file),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      label: const Text('Choose a file'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Reading your receipt…'),
        ],
      ),
    );
  }
}
