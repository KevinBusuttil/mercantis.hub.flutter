import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:mercantis_hub_app/ledger/bin_identity.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../support/books_harness.dart';

/// The Solo data-layer benchmark workload, shared by the host baseline
/// (test/perf/host_benchmark_test.dart, sqflite_common_ffi) and the device
/// run (integration_test/device_benchmark_test.dart, the platform sqflite).
///
/// Fixture (deterministic, synthetic, no customer data): [customers]
/// customers, [itemCount] stock items, 2 warehouses, 100 stock purchases of
/// 4 lines, 50 invoices of 5 stock lines, 10 receipt attachments of 2 MB,
/// then an encrypted backup and a restore of the whole book.
///
/// Returns metric → milliseconds (or a p50/p95/max map for repeated
/// samples), plus sizes and counts.
Future<Map<String, Object>> runSoloWorkload({
  required String rootDir,
  required DatabaseFactory factory,
  int customers = 10000,
  int itemCount = 5000,
}) async {
  final results = <String, Object>{};

  Future<T> time<T>(String key, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    final out = await body();
    sw.stop();
    results[key] = sw.elapsedMicroseconds / 1000.0;
    return out;
  }

  Future<Map<String, double>> sample(
      String key, int n, Future<void> Function(int i) body) async {
    final ms = <double>[];
    for (var i = 0; i < n; i++) {
      final sw = Stopwatch()..start();
      await body(i);
      ms.add(sw.elapsedMicroseconds / 1000.0);
    }
    ms.sort();
    double pct(double q) => ms[((ms.length - 1) * q).round()];
    final stats = {'p50_ms': pct(0.5), 'p95_ms': pct(0.95), 'max_ms': ms.last};
    results[key] = stats;
    return stats;
  }

  final dataDir = p.join(rootDir, 'device');
  Directory(dataDir).createSync();
  final dbPath = p.join(dataDir, 'mercantis.db');
  final rssStart = ProcessInfo.currentRss;

  // ---- Database initialisation ------------------------------------------
  var h = await time(
      'db_init_fresh_install_ms',
      () => BooksHarness.open(dbPath,
          factory: factory)); // migrate + install + seed + ledger
  await h.close();
  h = await time(
      'db_init_existing_ms', () => BooksHarness.open(dbPath, factory: factory));

  // ---- Masters ------------------------------------------------------------
  await h.save(Document(
      id: 'SUPP-1',
      docType: 'Supplier',
      payload: {'supplier_name': 'Perf Supplies', 'supplier_type': 'Company'}));
  for (final w in ['MAIN', 'SHOP']) {
    await h.save(
        Document(id: w, docType: 'Warehouse', payload: {'warehouse_name': w}));
  }

  Future<void> addCustomers(int from, int to) async {
    for (var i = from; i < to; i++) {
      await h.save(Document(
          id: 'C${i.toString().padLeft(5, '0')}',
          docType: 'Customer',
          payload: {
            'customer_name': 'Customer ${i.toString().padLeft(5, '0')} Ltd',
            'customer_type': 'Company',
          }));
    }
  }

  await time('create_1000_customers_ms', () => addCustomers(0, 1000));
  await time('list_1000_customers_ms',
      () => h.engine.list('Customer', userRoles: systemRoles));
  await time('list_1000_customers_first_page_ms',
      () => h.engine.list('Customer', limit: 50, userRoles: systemRoles));
  await time('create_next_${customers - 1000}_customers_ms',
      () => addCustomers(1000, customers));
  final all = await time('list_${customers}_customers_ms',
      () => h.engine.list('Customer', userRoles: systemRoles));
  _check(all.length == customers, 'customer count');
  await time('list_${customers}_customers_first_page_ms',
      () => h.engine.list('Customer', limit: 50, userRoles: systemRoles));
  await sample(
      'search_${customers}_customers_by_name',
      20,
      (i) => h.engine.list('Customer',
          predicates: [
            ListFilter.like('customer_name', '%${(i * 37) % customers}%')
          ],
          limit: 50,
          userRoles: systemRoles));

  await time('create_${itemCount}_items_ms', () async {
    for (var i = 0; i < itemCount; i++) {
      await h.save(Document(
          id: 'SKU${i.toString().padLeft(5, '0')}',
          docType: 'Item',
          payload: {
            'item_code': 'SKU${i.toString().padLeft(5, '0')}',
            'item_name': 'Widget ${i % 97} size ${i % 13} colour ${i % 7}',
            'item_type': 'Stock',
            'stock_uom': 'Nos',
            'valuation_method': 'Moving Average',
            'standard_rate': 10 + i % 50,
          }));
    }
  });
  await sample(
      'search_${itemCount}_item_catalogue',
      20,
      (i) => h.engine.list('Item',
          predicates: [ListFilter.like('item_name', '%size ${i % 13}%')],
          limit: 50,
          userRoles: systemRoles));

  // ---- Purchases put stock on hand (200 items × 2 warehouses) -----------
  await time('post_100_stock_purchases_ms', () async {
    for (var b = 0; b < 100; b++) {
      final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
        'supplier': 'SUPP-1',
        'posting_date': isoToday(),
        'update_stock': 1,
        'set_warehouse': b.isEven ? 'MAIN' : 'SHOP',
      });
      pi.children['items'] = [
        for (var l = 0; l < 4; l++)
          itemLine(
              'Purchase Invoice',
              {
                'item': 'SKU${((b ~/ 2) * 4 + l).toString().padLeft(5, '0')}',
                'qty': 100,
                'rate': 5,
              },
              l),
      ];
      await h.saveAndSubmit(pi);
    }
  });

  // ---- Creating an invoice (5 stock lines, posts GL/stock/AR) ------------
  await sample('create_and_post_invoice_5_lines', 50, (i) async {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'C${(i * 191 % customers).toString().padLeft(5, '0')}',
      'posting_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'MAIN',
    });
    si.children['items'] = [
      for (var l = 0; l < 5; l++)
        itemLine(
            'Sales Invoice',
            {
              'item':
                  'SKU${((i % 50) * 4 % 200 + l % 4).toString().padLeft(5, '0')}',
              'qty': 1,
              'rate': 12,
            },
            l),
    ];
    await h.saveAndSubmit(si);
  });

  // ---- Stock availability --------------------------------------------------
  await sample(
      'stock_availability_single_item',
      50,
      (i) => h.engine.fetch(
          'Bin', binId('SKU${(i % 200).toString().padLeft(5, '0')}', 'MAIN')));
  await time('stock_availability_all_bins_ms',
      () => h.engine.list('Bin', userRoles: systemRoles));

  // ---- Reports ---------------------------------------------------------------
  final reports = HubAggregatingReports(h.engine.list, fetch: h.engine.fetch);
  await time('report_trial_balance_ms',
      () => reports.trialBalance(userRoles: systemRoles));
  await time('report_profit_and_loss_ms',
      () => reports.profitAndLoss(userRoles: systemRoles));
  await time('report_balance_sheet_ms',
      () => reports.balanceSheet(userRoles: systemRoles));
  await time(
      'report_ar_ageing_ms', () => reports.arAging(userRoles: systemRoles));
  await time('report_stock_valuation_ms',
      () => reports.stockValuation(userRoles: systemRoles));
  await time('report_stock_gl_reconciliation_ms',
      () => reports.stockGlReconciliation(userRoles: systemRoles));

  // ---- Long offline session: everything is still queued for sync -----------
  final queued = await h.db.db.rawQuery(
      "SELECT COUNT(*) AS n FROM sync_queue WHERE status = 'pending'");
  results['offline_changes_queued'] = queued.first['n'] as int;
  await time('offline_queue_count_ms', () async {
    await h.db.db
        .rawQuery("SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'");
  });
  _check(await h.trialBalanceDifference() == 0, 'trial balance');

  // ---- Attachment / receipt processing ---------------------------------------
  final attachments = AttachmentManager(
      h.db.db, AttachmentStore(p.join(dataDir, 'attachments')));
  final receipt = List<int>.generate(2 * 1024 * 1024, (i) => (i * 31) % 251);
  await sample('attach_2mb_receipt', 10, (i) async {
    await attachments.attach(
        documentId: 'C00001',
        docType: 'Customer',
        fileName: 'receipt-$i.jpg',
        mimeType: 'image/jpeg',
        data: receipt,
        userId: 'owner');
  });

  // ---- Large local database ----------------------------------------------------
  final docCount =
      await h.db.db.rawQuery('SELECT COUNT(*) AS n FROM documents');
  results['documents_total'] = docCount.first['n'] as int;
  results['db_file_mb'] = double.parse(
      (File(dbPath).lengthSync() / (1024 * 1024)).toStringAsFixed(2));
  await time(
      'integrity_quick_check_ms', () => h.db.db.rawQuery('PRAGMA quick_check'));

  // ---- Backup / restore of the large book (production KDF) --------------
  final backup = HubBackup(dataDirectory: dataDir, factory: factory);
  final out = p.join(rootDir, 'perf.atlasbackup');
  await time(
      'backup_large_book_ms',
      () => backup.createBackup(
          database: h.db.db,
          passphrase: 'correct horse battery staple',
          outputPath: out));
  results['backup_file_mb'] =
      double.parse((File(out).lengthSync() / (1024 * 1024)).toStringAsFixed(2));
  await h.close();

  final restoreDir = p.join(rootDir, 'restored');
  Directory(restoreDir).createSync();
  final restore = HubBackup(dataDirectory: restoreDir, factory: factory);
  final staged = await time('restore_stage_and_verify_ms',
      () => restore.stage(out, 'correct horse battery staple'));
  await time('restore_commit_ms', () => restore.commit(staged));

  h = await time(
      'reopen_restored_book_ms',
      () => BooksHarness.open(p.join(restoreDir, 'mercantis.db'),
          factory: factory));
  await h.close();

  results['rss_growth_mb'] = double.parse(
      ((ProcessInfo.currentRss - rssStart) / (1024 * 1024)).toStringAsFixed(1));
  results['rss_end_mb'] =
      double.parse((ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1));

  return results;
}

void _check(bool ok, String what) {
  if (!ok) throw StateError('Benchmark invariant failed: $what');
}
