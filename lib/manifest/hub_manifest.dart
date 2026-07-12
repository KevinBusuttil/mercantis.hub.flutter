import 'package:mercantis_core/mercantis_core.dart';
import '../modules/crm/crm_module.dart';
import '../modules/selling/selling_module.dart';
import '../modules/buying/buying_module.dart';
import '../modules/capture/capture_module.dart';
import '../modules/stock/stock_module.dart';
import '../modules/accounting/accounting_module.dart';
import '../modules/accounting/compliance_module.dart';
import '../modules/banking/banking_module.dart';
import '../modules/deliveries/deliveries_module.dart';
import '../modules/fulfilment/fulfilment_module.dart';
import '../modules/manufacturing/manufacturing_module.dart';
import '../modules/pos/pos_module.dart';
import '../modules/setup/setup_module.dart';
import '../modules/projects/projects_module.dart';
import '../modules/channels/channels_module.dart';
import '../modules/assets/assets_module.dart';
import '../modules/booking/booking_module.dart';
import '../modules/equipment/equipment_module.dart';
import '../modules/membership/membership_module.dart';
import '../modules/property/property_module.dart';
import '../modules/rental/rental_module.dart';
import '../modules/field_service/field_service_module.dart';
import '../modules/hospitality/hospitality_module.dart';
import '../modules/scheduling/scheduling_module.dart';
import '../setup_library/setup_library_module.dart';
import '../modules/tax/tax_module.dart';
import '../workflows/hub_workflows.dart';
import 'hub_dashboards.dart';
import 'hub_reports.dart';

abstract final class HubManifest {
  static AppManifest build() {
    final allDocTypes = [
      ...SetupModule.docTypes(),
      ...TaxModule.docTypes(),
      ...CrmModule.docTypes(),
      ...SellingModule.docTypes(),
      ...BuyingModule.docTypes(),
      ...StockModule.docTypes(),
      ...AccountingModule.docTypes(),
      ...ComplianceModule.docTypes(),
      ...BankingModule.docTypes(),
      ...FulfilmentModule.docTypes(),
      ...PosModule.docTypes(),
      ...ManufacturingModule.docTypes(),
      ...DeliveriesModule.docTypes(),
      ...CaptureModule.docTypes(),
      ...ProjectsModule.docTypes(),
      ...ChannelsModule.docTypes(),
      ...SchedulingModule.docTypes(),
      ...FieldServiceModule.docTypes(),
      ...HospitalityModule.docTypes(),
      ...BookingModule.docTypes(),
      ...AssetsModule.docTypes(),
      ...EquipmentModule.docTypes(),
      ...RentalModule.docTypes(),
      ...PropertyModule.docTypes(),
      ...MembershipModule.docTypes(),
      ...SetupLibraryModule.docTypes(),
    ];

    return AppManifest(
      id: 'app.mercantis.hub',
      name: 'Neuradix Atlas',
      version: '1.0.0',
      docTypes: allDocTypes,
      workflows: HubWorkflows.all(),
      schedulerEvents: const [],
      documentEventSubscriptions: const [],
      reports: HubReports.all(),
      dashboards: HubDashboards.all(),
    );
  }
}
