import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// S13 (Phase 5): EN 16931 e-invoicing, first slice. Builds a UBL 2.1
/// Invoice XML from a SUBMITTED Sales Invoice — the semantic model the
/// EU mandate requires (PEPPOL BIS Billing 3.0 customization). What this
/// deliberately is NOT: a PEPPOL Access Point. Transmission over the
/// network is an integration (an AP provider), never a build — this
/// slice produces the document those providers accept.
abstract final class UblInvoiceBuilder {
  static const customizationId =
      'urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0';
  static const profileId = 'urn:fdc:peppol.eu:2017:poacc:billing:01:1.0';

  /// UOM → UN/ECE Recommendation 20 unit codes (C62 = "one").
  static const _unitCodes = {
    'Nos': 'C62',
    'Unit': 'C62',
    'Pcs': 'C62',
    'Hour': 'HUR',
    'Hours': 'HUR',
    'Kg': 'KGM',
    'Litre': 'LTR',
    'Meter': 'MTR',
    'Box': 'XBX',
    'Pair': 'PR',
    'Set': 'SET',
  };

  static const _countryCodes = {
    'malta': 'MT',
    'italy': 'IT',
    'germany': 'DE',
    'france': 'FR',
    'spain': 'ES',
    'netherlands': 'NL',
    'belgium': 'BE',
    'austria': 'AT',
    'ireland': 'IE',
    'portugal': 'PT',
    'greece': 'GR',
    'cyprus': 'CY',
    'united kingdom': 'GB',
    'uk': 'GB',
  };

  /// ISO 3166-1 alpha-2 from a free-text country, or from a VAT id's
  /// two-letter prefix as a fallback.
  static String? countryCode(String? country, {String? vatId}) {
    final raw = country?.trim() ?? '';
    if (raw.length == 2 && raw == raw.toUpperCase()) return raw;
    final mapped = _countryCodes[raw.toLowerCase()];
    if (mapped != null) return mapped;
    final vat = vatId?.trim() ?? '';
    if (vat.length >= 2) {
      final prefix = vat.substring(0, 2).toUpperCase();
      if (RegExp(r'^[A-Z]{2}$').hasMatch(prefix)) return prefix;
    }
    return null;
  }

  static String _esc(Object? value) => '$value'
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _money(num v) => v.toStringAsFixed(2);

  /// Builds the XML. [taxRateByCode] maps Tax Code ids to their percent
  /// rates, [itemTaxCodeByItem] carries each line item's master-level
  /// tax code and [partyTaxCode] the customer's — together they mirror
  /// the tax interceptor's line → item → document → party fallback
  /// chain, so a line's ClassifiedTaxCategory matches what actually
  /// posted (Codex P1, PR #169). The VAT breakdown and totals prefer the
  /// invoice's PERSISTED `taxes` rows and totals over recomputation for
  /// the same reason — including prices_include_tax invoices, whose
  /// contained tax was already extracted at posting time.
  /// Throws a StateError listing EVERY missing mandatory element at
  /// once, so the user fixes the record in one pass.
  static String build({
    required Document invoice,
    required Document seller,
    required Document buyer,
    Map<String, num> taxRateByCode = const {},
    Map<String, String> itemTaxCodeByItem = const {},
    String? partyTaxCode,
  }) {
    final problems = <String>[];
    if (invoice.docStatus != 1) {
      problems.add('the invoice must be submitted (drafts are not '
          'fiscal documents)');
    }
    final sellerName = asNonEmpty(seller.payload['company_name']);
    if (sellerName == null) problems.add('seller company name (BT-27)');
    final sellerVat = asNonEmpty(seller.payload['tax_id']);
    if (sellerVat == null) {
      problems.add('seller VAT identifier (BT-31) — set Tax ID on the '
          'Company');
    }
    final sellerCountry = countryCode(
        asNonEmpty(seller.payload['country']), vatId: sellerVat);
    if (sellerCountry == null) {
      problems.add('seller country (BT-40) — set Country on the Company');
    }
    final buyerName = asNonEmpty(buyer.payload['customer_name']);
    if (buyerName == null) problems.add('buyer name (BT-44)');
    final buyerVat = asNonEmpty(buyer.payload['tax_id']);
    final buyerCountry = countryCode(asNonEmpty(buyer.payload['country']),
            vatId: buyerVat) ??
        sellerCountry; // domestic default when the customer has none
    final rows = invoice.children['items'] ?? const <ChildRow>[];
    if (rows.isEmpty) problems.add('at least one invoice line (BG-25)');
    if (problems.isNotEmpty) {
      throw StateError(
          'E-invoice blocked — missing: ${problems.join('; ')}.');
    }

    final currency =
        asNonEmpty(invoice.payload['currency']) ?? 'EUR';
    final issueDate = '${invoice.payload['posting_date']}';
    final dueDate = asNonEmpty(invoice.payload['due_date']);
    final number =
        asNonEmpty(invoice.payload['official_number']) ?? invoice.id;
    final isCreditNote = isTrue(invoice.payload['is_return']);
    final docTaxCode = asNonEmpty(invoice.payload['tax_code']);
    final inclusive = isTrue(invoice.payload['prices_include_tax']);

    // The interceptor's fallback chain, mirrored exactly.
    num rateFor(ChildRow row) {
      final code = asNonEmpty(row.payload['tax_code']) ??
          itemTaxCodeByItem['${row.payload['item']}'] ??
          docTaxCode ??
          partyTaxCode;
      return code == null ? 0 : (taxRateByCode[code] ?? 0);
    }

    // A line's NET extension: inclusive documents entered gross, and
    // the posting extracted the contained tax — do the same here.
    num lineNet(ChildRow row) {
      final entered =
          asNum(row.payload['qty']) * asNum(row.payload['rate']);
      if (!inclusive) return round2(entered);
      final rate = rateFor(row);
      return round2(entered * 100 / (100 + rate));
    }

    // VAT breakdown (BG-23): the PERSISTED taxes rows are the truth the
    // document posted with — recomputation is only the fallback for
    // records that predate the tax interceptor.
    final taxRows = [
      for (final t in invoice.children['taxes'] ?? const <ChildRow>[])
        if ('${t.payload['tax_type']}' != 'Withholding') t,
    ];
    num netTotal = 0;
    for (final row in rows) {
      netTotal += lineNet(row);
    }
    netTotal = round2(netTotal);
    final persistedNet = asNum(invoice.payload['total']);
    if (persistedNet != 0) netTotal = persistedNet;

    num taxTotal = 0;
    final subtotals = StringBuffer();
    void subtotal(num taxable, num tax, num rate) {
      taxTotal = round2(taxTotal + tax);
      subtotals.write('''
    <cac:TaxSubtotal>
      <cbc:TaxableAmount currencyID="$currency">${_money(taxable)}</cbc:TaxableAmount>
      <cbc:TaxAmount currencyID="$currency">${_money(tax)}</cbc:TaxAmount>
      <cac:TaxCategory>
        <cbc:ID>${rate > 0 ? 'S' : 'Z'}</cbc:ID>
        <cbc:Percent>${_money(rate)}</cbc:Percent>
        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
      </cac:TaxCategory>
    </cac:TaxSubtotal>
''');
    }

    if (taxRows.isNotEmpty) {
      num coveredTaxable = 0;
      for (final t in taxRows) {
        final taxable = asNum(t.payload['taxable_amount']);
        subtotal(taxable, asNum(t.payload['tax_amount']),
            asNum(t.payload['rate']));
        coveredTaxable = round2(coveredTaxable + taxable);
      }
      // Lines no tax row covers are the zero-rated remainder.
      final zeroRated = round2(netTotal - coveredTaxable);
      if (zeroRated > 0.005) subtotal(zeroRated, 0, 0);
    } else {
      final taxableByRate = <num, num>{};
      for (final row in rows) {
        final rate = rateFor(row);
        taxableByRate[rate] = (taxableByRate[rate] ?? 0) + lineNet(row);
      }
      for (final rate in taxableByRate.keys.toList()
        ..sort((a, b) => b.compareTo(a))) {
        final taxable = round2(taxableByRate[rate]!);
        subtotal(taxable, round2(taxable * rate / 100), rate);
      }
    }

    final persistedGrand = asNum(invoice.payload['grand_total']);
    final grandTotal =
        persistedGrand != 0 ? persistedGrand : round2(netTotal + taxTotal);

    final lines = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final qty = asNum(row.payload['qty']);
      final amount = lineNet(row);
      final rate = qty == 0 ? 0 : round2(amount / qty);
      final unit = _unitCodes['${row.payload['uom']}'] ?? 'C62';
      final vatRate = rateFor(row);
      final name = asNonEmpty(row.payload['description']) ??
          '${row.payload['item']}';
      lines.write('''
  <cac:InvoiceLine>
    <cbc:ID>${i + 1}</cbc:ID>
    <cbc:InvoicedQuantity unitCode="$unit">$qty</cbc:InvoicedQuantity>
    <cbc:LineExtensionAmount currencyID="$currency">${_money(amount)}</cbc:LineExtensionAmount>
    <cac:Item>
      <cbc:Name>${_esc(name)}</cbc:Name>
      <cac:ClassifiedTaxCategory>
        <cbc:ID>${vatRate > 0 ? 'S' : 'Z'}</cbc:ID>
        <cbc:Percent>${_money(vatRate)}</cbc:Percent>
        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
      </cac:ClassifiedTaxCategory>
    </cac:Item>
    <cac:Price>
      <cbc:PriceAmount currencyID="$currency">${_money(rate)}</cbc:PriceAmount>
    </cac:Price>
  </cac:InvoiceLine>
''');
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
  xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:CustomizationID>$customizationId</cbc:CustomizationID>
  <cbc:ProfileID>$profileId</cbc:ProfileID>
  <cbc:ID>${_esc(number)}</cbc:ID>
  <cbc:IssueDate>$issueDate</cbc:IssueDate>
${dueDate != null ? '  <cbc:DueDate>$dueDate</cbc:DueDate>\n' : ''}  <cbc:InvoiceTypeCode>${isCreditNote ? 381 : 380}</cbc:InvoiceTypeCode>
  <cbc:DocumentCurrencyCode>$currency</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty>
    <cac:Party>
      <cac:PartyName><cbc:Name>${_esc(sellerName)}</cbc:Name></cac:PartyName>
      <cac:PostalAddress>
        <cac:Country><cbc:IdentificationCode>$sellerCountry</cbc:IdentificationCode></cac:Country>
      </cac:PostalAddress>
      <cac:PartyTaxScheme>
        <cbc:CompanyID>${_esc(sellerVat)}</cbc:CompanyID>
        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
      </cac:PartyTaxScheme>
      <cac:PartyLegalEntity><cbc:RegistrationName>${_esc(sellerName)}</cbc:RegistrationName></cac:PartyLegalEntity>
    </cac:Party>
  </cac:AccountingSupplierParty>
  <cac:AccountingCustomerParty>
    <cac:Party>
      <cac:PartyName><cbc:Name>${_esc(buyerName)}</cbc:Name></cac:PartyName>
      <cac:PostalAddress>
        <cac:Country><cbc:IdentificationCode>$buyerCountry</cbc:IdentificationCode></cac:Country>
      </cac:PostalAddress>
${buyerVat != null ? '''      <cac:PartyTaxScheme>
        <cbc:CompanyID>${_esc(buyerVat)}</cbc:CompanyID>
        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
      </cac:PartyTaxScheme>
''' : ''}      <cac:PartyLegalEntity><cbc:RegistrationName>${_esc(buyerName)}</cbc:RegistrationName></cac:PartyLegalEntity>
    </cac:Party>
  </cac:AccountingCustomerParty>
  <cac:TaxTotal>
    <cbc:TaxAmount currencyID="$currency">${_money(taxTotal)}</cbc:TaxAmount>
$subtotals  </cac:TaxTotal>
  <cac:LegalMonetaryTotal>
    <cbc:LineExtensionAmount currencyID="$currency">${_money(netTotal)}</cbc:LineExtensionAmount>
    <cbc:TaxExclusiveAmount currencyID="$currency">${_money(netTotal)}</cbc:TaxExclusiveAmount>
    <cbc:TaxInclusiveAmount currencyID="$currency">${_money(grandTotal)}</cbc:TaxInclusiveAmount>
    <cbc:PayableAmount currencyID="$currency">${_money(grandTotal)}</cbc:PayableAmount>
  </cac:LegalMonetaryTotal>
$lines</Invoice>
''';
  }
}

/// Resolves everything the pure builder needs from the book: the
/// hydrated invoice, the seller Company (the invoice's, else the first),
/// the buyer Customer, and the rates of every tax code the lines touch.
class UblExportService {
  UblExportService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  Future<String> buildFor(String invoiceId) async {
    final invoice = await _engine.fetch('Sales Invoice', invoiceId);
    if (invoice == null) {
      throw StateError('Sales Invoice $invoiceId not found.');
    }

    Document? seller;
    final companyId = invoice.company;
    if (companyId != null && companyId.isNotEmpty) {
      seller = await _engine.fetch('Company', companyId);
    }
    if (seller == null) {
      final companies =
          await _engine.list('Company', userRoles: _roles);
      if (companies.isEmpty) {
        throw StateError(
            'No Company on file — the e-invoice needs a seller.');
      }
      seller = companies.first;
    }

    final buyer = await _engine.fetch(
        'Customer', '${invoice.payload['customer']}');
    if (buyer == null) {
      throw StateError(
          'Customer ${invoice.payload['customer']} not found.');
    }

    // The full fallback chain's inputs: line codes, each line item's
    // master code, the document code, and the customer's default.
    final itemTaxCodeByItem = <String, String>{};
    for (final row in invoice.children['items'] ?? const <ChildRow>[]) {
      final itemId = asNonEmpty(row.payload['item']);
      if (itemId == null || itemTaxCodeByItem.containsKey(itemId)) {
        continue;
      }
      final item = await _engine.fetch('Item', itemId);
      final code = asNonEmpty(item?.payload['tax_code']);
      if (code != null) itemTaxCodeByItem[itemId] = code;
    }
    final partyTaxCode = asNonEmpty(buyer.payload['tax_code']);

    final codes = <String>{
      if (asNonEmpty(invoice.payload['tax_code']) != null)
        '${invoice.payload['tax_code']}',
      for (final row in invoice.children['items'] ?? const <ChildRow>[])
        if (asNonEmpty(row.payload['tax_code']) != null)
          '${row.payload['tax_code']}',
      ...itemTaxCodeByItem.values,
      if (partyTaxCode != null) partyTaxCode,
    };
    final rates = <String, num>{};
    for (final code in codes) {
      final taxCode = await _engine.fetch('Tax Code', code);
      if (taxCode != null) rates[code] = asNum(taxCode.payload['rate']);
    }

    return UblInvoiceBuilder.build(
      invoice: invoice,
      seller: seller,
      buyer: buyer,
      taxRateByCode: rates,
      itemTaxCodeByItem: itemTaxCodeByItem,
      partyTaxCode: partyTaxCode,
    );
  }
}
