import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const _captureKey = Key('atlas-marketing-capture');
const _marketingFontFamily = 'AtlasMarketing';

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
    throw StateError('No readable CI font found for Atlas marketing capture.');
  }

  // Keep filesystem access synchronous, then load the font outside the widget
  // test's fake-async zone via tester.runAsync() below.
  final bytes = fontFile.readAsBytesSync();
  final loader = FontLoader(_marketingFontFamily)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

ThemeData _marketingTheme() {
  final base = MercantisTheme.light();
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _marketingFontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _marketingFontFamily),
  );
}

const _destinations = <AtlasNavDestination>[
  AtlasNavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  AtlasNavDestination(
    icon: Icons.sell_outlined,
    selectedIcon: Icons.sell,
    label: 'Selling',
  ),
  AtlasNavDestination(
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag,
    label: 'Buying',
  ),
  AtlasNavDestination(
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    label: 'Stock',
  ),
  AtlasNavDestination(
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance,
    label: 'Finance',
  ),
];

class _AtlasMarketingSurface extends StatelessWidget {
  const _AtlasMarketingSurface();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(right: BorderSide(color: cs.outlineVariant)),
            ),
            child: AtlasNavigationRail(
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
              extended: true,
              minExtendedWidth: 210,
              accentColor: MercantisBrandColors.accentFinance,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        'A',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'ATLAS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 24, 30, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good morning, Aster Trading Ltd',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Your business today · 14 September 2026',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                        label: const Text('New transaction'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Row(
                    children: [
                      Expanded(
                        child: KpiCard(
                          title: 'Cash position',
                          value: '€84,320',
                          subtitle: 'Across bank and cash',
                          icon: Icons.account_balance_outlined,
                          accentColor: MercantisBrandColors.accentFinance,
                          trend: KpiTrend.up,
                          trendLabel: '+8.2%',
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          title: 'Sales this month',
                          value: '€47,850',
                          subtitle: 'September 2026',
                          icon: Icons.trending_up,
                          accentColor: MercantisBrandColors.accentSales,
                          trend: KpiTrend.up,
                          trendLabel: '+11.4%',
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          title: 'Receivables',
                          value: '€26,410',
                          subtitle: '€6,930 overdue',
                          icon: Icons.south_west,
                          accentColor: MercantisBrandColors.accentFinance,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          title: 'Payables',
                          value: '€15,780',
                          subtitle: '€4,120 due this week',
                          icon: Icons.north_east,
                          accentColor: MercantisBrandColors.accentPurchase,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: ListCard(
                            title: 'Recent invoices',
                            subtitle: 'Latest customer activity',
                            icon: Icons.receipt_long_outlined,
                            accentColor: MercantisBrandColors.accentSales,
                            onSeeAll: () {},
                            rows: const [
                              ListCardRow(
                                title: 'INV-2026-0148 · Harbour Office Supplies',
                                subtitle: 'Paid · 14 Sep 2026',
                                trailing: Text('€3,482.50'),
                              ),
                              ListCardRow(
                                title: 'INV-2026-0147 · Valletta Design Studio',
                                subtitle: 'Due 28 Sep 2026',
                                trailing: Text('€1,965.00'),
                              ),
                              ListCardRow(
                                title: 'INV-2026-0146 · Northshore Services',
                                subtitle: 'Due 24 Sep 2026',
                                trailing: Text('€7,240.80'),
                              ),
                              ListCardRow(
                                title: 'INV-2026-0145 · Aster Retail',
                                subtitle: 'Paid · 12 Sep 2026',
                                trailing: Text('€895.40'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              const Expanded(
                                child: KpiCard(
                                  title: 'Open sales orders',
                                  value: '14',
                                  subtitle: '€31,640 committed',
                                  icon: Icons.shopping_cart_outlined,
                                  accentColor: MercantisBrandColors.accentSales,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Expanded(
                                child: KpiCard(
                                  title: 'VAT estimate',
                                  value: '€4,280',
                                  subtitle: 'Current filing period',
                                  icon: Icons.account_balance_wallet_outlined,
                                  accentColor: MercantisBrandColors.accentFinance,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Material(
                                  color: cs.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: cs.outlineVariant),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.fact_check_outlined,
                                              color: MercantisBrandColors.accentApprovals,
                                            ),
                                            const SizedBox(width: 9),
                                            Text(
                                              'Pending approvals',
                                              style: theme.textTheme.titleMedium,
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        Text(
                                          '3',
                                          style: theme.textTheme.displaySmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Purchases and payment requests waiting for review',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('marketing owner dashboard is deterministic', (tester) async {
    await tester.runAsync(
      () => _loadReadableMarketingFont().timeout(const Duration(seconds: 15)),
    );

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _marketingTheme(),
        debugShowCheckedModeBanner: false,
        home: const RepaintBoundary(
          key: _captureKey,
          child: Scaffold(body: _AtlasMarketingSurface()),
        ),
      ),
    );
    // This surface is intentionally static. A fixed pump makes the golden
    // deterministic without waiting for unrelated framework animations.
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('goldens/atlas_owner_dashboard_1440x900.png'),
    );
  });
}
