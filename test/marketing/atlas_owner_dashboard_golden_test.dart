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

  final bytes = fontFile.readAsBytesSync();
  final loader = FontLoader(_marketingFontFamily)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
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

Future<void> _loadMarketingFonts() async {
  await Future.wait([
    _loadReadableMarketingFont(),
    _loadMaterialIcons(),
  ]);
}

ThemeData _marketingTheme() {
  final base = MercantisTheme.light();
  final textTheme = base.textTheme.apply(fontFamily: _marketingFontFamily);
  final primaryTextTheme =
      base.primaryTextTheme.apply(fontFamily: _marketingFontFamily);
  final colorScheme = base.colorScheme;

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
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
  AtlasNavDestination(
    icon: Icons.assessment_outlined,
    selectedIcon: Icons.assessment,
    label: 'Reports',
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
              minExtendedWidth: 198,
              accentColor: MercantisBrandColors.accentFinance,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
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
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aster Trading Ltd',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Owner overview · 14 September 2026',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                      SizedBox(width: 10),
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
                      SizedBox(width: 10),
                      Expanded(
                        child: KpiCard(
                          title: 'Overdue',
                          value: '€6,930',
                          subtitle: '8 customer invoices',
                          icon: Icons.schedule_outlined,
                          accentColor: MercantisBrandColors.accentFinance,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: KpiCard(
                          title: 'Bills due',
                          value: '€4,120',
                          subtitle: 'Next 7 days',
                          icon: Icons.receipt_long_outlined,
                          accentColor: MercantisBrandColors.accentPurchase,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: KpiCard(
                          title: 'VAT estimate',
                          value: '€4,280',
                          subtitle: 'Current quarter',
                          icon: Icons.account_balance_wallet_outlined,
                          accentColor: MercantisBrandColors.accentFinance,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 320,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(
                          flex: 7,
                          child: ListCard(
                            title: 'Recent invoices',
                            subtitle: 'Latest customer activity',
                            icon: Icons.receipt_long_outlined,
                            accentColor: MercantisBrandColors.accentSales,
                            rows: [
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
                        const SizedBox(width: 12),
                        const Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: KpiCard(
                                        title: 'Open sales orders',
                                        value: '14',
                                        subtitle: '€31,640 committed',
                                        icon: Icons.shopping_cart_outlined,
                                        accentColor:
                                            MercantisBrandColors.accentSales,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: KpiCard(
                                        title: 'Receivables',
                                        value: '€26,410',
                                        subtitle: '18 open invoices',
                                        icon: Icons.south_west,
                                        accentColor:
                                            MercantisBrandColors.accentFinance,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: KpiCard(
                                        title: 'Payables',
                                        value: '€15,780',
                                        subtitle: '11 supplier bills',
                                        icon: Icons.north_east,
                                        accentColor:
                                            MercantisBrandColors.accentPurchase,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: KpiCard(
                                        title: 'Stock value',
                                        value: '€62,480',
                                        subtitle: 'Across 2 warehouses',
                                        icon: Icons.inventory_2_outlined,
                                        accentColor:
                                            MercantisBrandColors.accentInventory,
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
                  const SizedBox(height: 14),
                  const Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListCard(
                            title: 'Recent sales orders',
                            subtitle: 'Orders moving through fulfilment',
                            icon: Icons.shopping_cart_outlined,
                            accentColor: MercantisBrandColors.accentSales,
                            rows: [
                              ListCardRow(
                                title: 'SO-2026-0092 · Coastline Catering',
                                subtitle: 'Delivery 16 Sep · Confirmed',
                                trailing: Text('€4,860.00'),
                              ),
                              ListCardRow(
                                title: 'SO-2026-0091 · Portside Interiors',
                                subtitle: 'Delivery 18 Sep · Draft',
                                trailing: Text('€8,120.00'),
                              ),
                              ListCardRow(
                                title: 'SO-2026-0090 · Greenline Retail',
                                subtitle: 'Delivery 15 Sep · To deliver',
                                trailing: Text('€2,745.60'),
                              ),
                              ListCardRow(
                                title: 'SO-2026-0089 · Meridian Services',
                                subtitle: 'Delivery 21 Sep · Confirmed',
                                trailing: Text('€6,380.00'),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ListCard(
                            title: 'Recent stock movements',
                            subtitle: 'Live inventory activity',
                            icon: Icons.swap_horiz,
                            accentColor: MercantisBrandColors.accentInventory,
                            rows: [
                              ListCardRow(
                                title: 'SKU-1044 · Main Warehouse',
                                subtitle: 'Receipt · 14 Sep 2026',
                                trailing: Text('+48 pcs'),
                              ),
                              ListCardRow(
                                title: 'SKU-2031 · Main Warehouse',
                                subtitle: 'Delivery · 14 Sep 2026',
                                trailing: Text('−12 pcs'),
                              ),
                              ListCardRow(
                                title: 'SKU-1008 · Transit Warehouse',
                                subtitle: 'Transfer · 13 Sep 2026',
                                trailing: Text('+20 pcs'),
                              ),
                              ListCardRow(
                                title: 'SKU-3050 · Main Warehouse',
                                subtitle: 'Adjustment · 13 Sep 2026',
                                trailing: Text('−2 pcs'),
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
      () => _loadMarketingFonts().timeout(const Duration(seconds: 15)),
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
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('goldens/atlas_owner_dashboard_1440x900.png'),
    );
  });
}
