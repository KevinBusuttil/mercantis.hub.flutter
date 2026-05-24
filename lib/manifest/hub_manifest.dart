import 'package:mercantis_core/mercantis_core.dart';
import '../modules/crm/crm_module.dart';
import '../modules/selling/selling_module.dart';
import '../modules/buying/buying_module.dart';
import '../modules/stock/stock_module.dart';
import '../modules/accounting/accounting_module.dart';
import '../modules/setup/setup_module.dart';

abstract final class HubManifest {
  static AppManifest build() {
    final allDocTypes = [
      ...SetupModule.docTypes(),
      ...CrmModule.docTypes(),
      ...SellingModule.docTypes(),
      ...BuyingModule.docTypes(),
      ...StockModule.docTypes(),
      ...AccountingModule.docTypes(),
    ];

    return AppManifest(
      id: 'app.mercantis.hub',
      name: 'Mercantis Hub',
      version: '1.0.0',
      description: 'Full ERP application: CRM, Selling, Buying, Stock, Accounting.',
      docTypes: allDocTypes,
      workflows: [],
      schedulerEvents: [],
      documentSubscriptions: [],
      reports: [],
      dashboards: [],
    );
  }
}
