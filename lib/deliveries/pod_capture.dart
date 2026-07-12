import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// What the driver captured at the door (S3): any combination of a drawn
/// signature (normalised-strokes JSON), a photo (local path), and a note.
class PodCapture {
  const PodCapture({this.signature, this.photoPath, this.note});

  final String? signature;
  final String? photoPath;
  final String? note;

  bool get isEmpty =>
      (signature == null || signature!.isEmpty) &&
      (photoPath == null || photoPath!.isEmpty) &&
      (note == null || note!.isEmpty);
}

/// Writes a stop's status (and proof) onto the Delivery Route and saves it —
/// the save triggers DeliveryRouteService, which appends the status event
/// and mirrors the status onto the Delivery Note. Pure engine logic, so the
/// whole driver flow is testable without a widget tree.
Future<void> markStopStatus(
  DocumentEngine engine, {
  required String routeId,
  required int sequence,
  required String status,
  PodCapture? pod,
  Set<String> roles = _systemRoles,
}) async {
  final route = await engine.fetch('Delivery Route', routeId);
  if (route == null) throw StateError('Delivery Route $routeId not found.');
  final stops = route.children['stops'] ?? const [];
  ChildRow? stop;
  for (var i = 0; i < stops.length; i++) {
    final seq = asNum(stops[i].payload['sequence']) == 0
        ? i + 1
        : asNum(stops[i].payload['sequence']).toInt();
    if (seq == sequence) {
      stop = stops[i];
      break;
    }
  }
  if (stop == null) {
    throw StateError('Route $routeId has no stop #$sequence.');
  }

  stop.payload['status'] = status;
  if (pod != null && !pod.isEmpty) {
    if (pod.signature != null && pod.signature!.isNotEmpty) {
      stop.payload['pod_signature'] = pod.signature;
    }
    if (pod.photoPath != null && pod.photoPath!.isNotEmpty) {
      stop.payload['pod_image'] = pod.photoPath;
    }
    if (pod.note != null && pod.note!.isNotEmpty) {
      stop.payload['pod_note'] = pod.note;
    }
    stop.payload['pod_time'] = DateTime.now().toIso8601String();
  }

  // The last stop resolving finishes the run: no separate "end route" chore.
  const terminal = {'Delivered', 'Failed', 'Rescheduled'};
  final allDone = stops.every(
      (s) => terminal.contains('${s.payload['status']}'));
  if (allDone) route.payload['status'] = 'Completed';

  await engine.save(route, roles);
}

/// The driver's proof-of-delivery sheet: sign, snap, note — then confirm.
/// Returns null when dismissed without confirming.
Future<PodCapture?> showPodCaptureSheet(
  BuildContext context, {
  required String customer,
}) {
  String? signature;
  String? photoPath;
  final noteCtrl = TextEditingController();

  return showModalBottomSheet<PodCapture>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: MercantisSpacing.lg,
          right: MercantisSpacing.lg,
          top: MercantisSpacing.lg,
          bottom:
              MediaQuery.of(c).viewInsets.bottom + MercantisSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Proof of delivery — $customer',
                style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: MercantisSpacing.md),
            SignatureField(
              label: 'Receiver signature',
              required: false,
              value: signature,
              readOnly: false,
              onChanged: (v) =>
                  setSheetState(() => signature = v as String?),
            ),
            const SizedBox(height: MercantisSpacing.sm),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final shot = await ImagePicker()
                          .pickImage(source: ImageSource.camera);
                      if (shot != null) {
                        setSheetState(() => photoPath = shot.path);
                      }
                    } catch (_) {
                      // No camera on this device — fall back to the gallery.
                      final picked = await ImagePicker()
                          .pickImage(source: ImageSource.gallery);
                      if (picked != null) {
                        setSheetState(() => photoPath = picked.path);
                      }
                    }
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(photoPath == null ? 'Add photo' : 'Retake'),
                ),
                if (photoPath != null)
                  const Padding(
                    padding: EdgeInsets.only(left: MercantisSpacing.sm),
                    child: Icon(Icons.check_circle_outline),
                  ),
              ],
            ),
            const SizedBox(height: MercantisSpacing.sm),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (left with neighbour, gate code…)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MercantisSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: MercantisSpacing.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    c,
                    PodCapture(
                      signature: signature,
                      photoPath: photoPath,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    ),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Delivered'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
