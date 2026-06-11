import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../capture/capture_providers.dart';
import '../ledger/ledger_values.dart';
import '../modules/capture/capture_module.dart';

/// Review & confirm a capture, then create a DRAFT Purchase Invoice (ADR-049).
/// The one screen between a photo and a draft the user can post later. Nothing
/// here submits anything.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  const CaptureReviewScreen({super.key, required this.captureId});

  final String captureId;

  @override
  ConsumerState<CaptureReviewScreen> createState() =>
      _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  final _merchant = TextEditingController();
  final _date = TextEditingController();
  final _invoiceNo = TextEditingController();
  final _net = TextEditingController();
  final _vat = TextEditingController();
  final _grand = TextEditingController();

  Document? _capture;
  List<({String id, String name})> _suppliers = const [];
  String? _supplierId;
  String _intendedRole = CaptureModule.roleAnyone;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_merchant, _date, _invoiceNo, _net, _vat, _grand]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final capture = await ref.read(captureProvider(widget.captureId).future);
    final suppliers = await ref.read(suppliersForPickerProvider.future);
    if (!mounted) return;
    if (capture == null) {
      setState(() {
        _loading = false;
        _error = 'This capture no longer exists.';
      });
      return;
    }
    final p = capture.payload;
    _merchant.text = asNonEmpty(p['merchant_name']) ?? '';
    _date.text = asNonEmpty(p['document_date']) ?? '';
    _invoiceNo.text = asNonEmpty(p['invoice_no']) ?? '';
    _net.text = _fmt(p['net_total']);
    _vat.text = _fmt(p['vat_total']);
    _grand.text = _fmt(p['grand_total']);
    setState(() {
      _capture = capture;
      _suppliers = suppliers;
      _supplierId = asNonEmpty(p['supplier']);
      _intendedRole =
          asNonEmpty(p['intended_role']) ?? CaptureModule.roleAnyone;
      _loading = false;
    });
  }

  static String _fmt(Object? v) =>
      v == null ? '' : asNum(v).toStringAsFixed(2);

  static num? _parse(String s) =>
      s.trim().isEmpty ? null : num.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _createDraft() async {
    final capture = _capture;
    if (capture == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Fold the (possibly edited) fields back onto the capture before routing.
    final p = capture.payload;
    p['merchant_name'] = _merchant.text.trim();
    p['document_date'] = _date.text.trim();
    p['invoice_no'] = _invoiceNo.text.trim();
    p['net_total'] = _parse(_net.text);
    p['vat_total'] = _parse(_vat.text);
    p['grand_total'] = _parse(_grand.text);
    p['intended_role'] = _intendedRole;
    try {
      final service = await ref.read(captureServiceProvider.future);
      final invoice =
          await service.createDraftInvoice(capture, supplierId: _supplierId);
      ref.invalidate(capturesProvider);
      ref.invalidate(captureProvider(widget.captureId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft purchase invoice created.')),
      );
      context.go('/form/Purchase Invoice/${invoice.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create the draft: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _capture == null
              ? Center(child: Text(_error!))
              : _form(context),
    );
  }

  Widget _form(BuildContext context) {
    final image = ref.watch(captureImageProvider(widget.captureId));
    final alreadyDrafted =
        asNonEmpty(_capture?.payload['linked_voucher']) != null;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            image.maybeWhen(
              data: (bytes) => bytes == null
                  ? const SizedBox.shrink()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(bytes,
                          height: 220, width: double.infinity, fit: BoxFit.cover),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _merchant,
              decoration: const InputDecoration(
                  labelText: 'Merchant', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _suppliers.any((s) => s.id == _supplierId)
                  ? _supplierId
                  : null,
              decoration: const InputDecoration(
                  labelText: 'Supplier (optional)',
                  border: OutlineInputBorder(),
                  helperText: 'Leave blank to use a placeholder you can change later'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Unspecified')),
                for (final s in _suppliers)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _date,
                    readOnly: true,
                    decoration: const InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18)),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _invoiceNo,
                    decoration: const InputDecoration(
                        labelText: 'Invoice / Receipt no',
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _amountField(_net, 'Net')),
                const SizedBox(width: 12),
                Expanded(child: _amountField(_vat, 'VAT')),
                const SizedBox(width: 12),
                Expanded(child: _amountField(_grand, 'Total')),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _intendedRole,
              decoration: const InputDecoration(
                  labelText: 'Show in queue for', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: CaptureModule.roleAnyone, child: Text('Anyone')),
                DropdownMenuItem(value: 'Bookkeeping', child: Text('Bookkeeping')),
                DropdownMenuItem(value: 'Management', child: Text('Management')),
                DropdownMenuItem(value: 'Field', child: Text('Field')),
              ],
              onChanged: (v) =>
                  setState(() => _intendedRole = v ?? CaptureModule.roleAnyone),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            if (alreadyDrafted)
              FilledButton.tonalIcon(
                onPressed: () => context.go(
                    '/form/Purchase Invoice/${_capture!.payload['linked_voucher']}'),
                icon: const Icon(Icons.open_in_new),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                label: const Text('Open created invoice'),
              )
            else
              FilledButton.icon(
                onPressed: _saving ? null : _createDraft,
                icon: const Icon(Icons.note_add_outlined),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                label: const Text('Create draft purchase invoice'),
              ),
            const SizedBox(height: 8),
            Text(
              'A draft is created for you to review and post later. Nothing is submitted automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        if (_saving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _amountField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration:
            InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() =>
        _date.text = picked.toIso8601String().split('T').first);
  }
}
