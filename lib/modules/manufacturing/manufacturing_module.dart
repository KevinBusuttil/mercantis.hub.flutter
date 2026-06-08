import 'package:mercantis_core/mercantis_core.dart';

/// Manufacturing module (ported from the Swift Hub `Manufacturing`). Stock-only
/// (no GL): a Work Order, on completion, posts a Manufacturing Stock Entry that
/// consumes raw materials from the source warehouse and produces the finished
/// good into the target warehouse — handled by the existing Stock Entry
/// derivation (`Manufacturing` → `Production`). BOM cost rolls up on save;
/// submitting a Production Plan auto-creates one Work Order per planned item.
abstract final class ManufacturingModule {
  static const _module = 'Manufacturing';
  static const _uom = 'Nos\nKg\nGrams\nLitre\nMetre\nBox\nPair\nSet';

  static List<DocType> docTypes() => [
        _workstation(),
        _operation(),
        _bom(),
        _bomItem(),
        _bomOperation(),
        _workOrder(),
        _workOrderItem(),
        _jobCard(),
        _productionPlan(),
        _productionPlanItem(),
      ];

  // ---- masters ------------------------------------------------------------

  static DocType _workstation() => const DocType(
        id: 'Workstation',
        name: 'Workstation',
        module: _module,
        namingRule: 'WS-.####',
        fields: [
          FieldDefinition(key: 'workstation_name', label: 'Workstation Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'hour_rate', label: 'Hour Rate', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'location', label: 'Location', type: FieldType.data),
          FieldDefinition(key: 'is_active', label: 'Active', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  static DocType _operation() => const DocType(
        id: 'Operation',
        name: 'Operation',
        module: _module,
        namingRule: 'OP-.####',
        fields: [
          FieldDefinition(key: 'operation_name', label: 'Operation Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.longText),
          FieldDefinition(key: 'default_workstation', label: 'Default Workstation', type: FieldType.link, linkDocType: 'Workstation', options: 'Workstation'),
          FieldDefinition(key: 'default_time_minutes', label: 'Default Time (min)', type: FieldType.float, defaultValue: '0'),
        ],
      );

  // ---- BOM ----------------------------------------------------------------

  static DocType _bom() => const DocType(
        id: 'BOM',
        name: 'BOM',
        module: _module,
        isSubmittable: true,
        namingRule: 'BOM-.YYYY.-.####',
        workflowId: 'wf-bom',
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'uom', label: 'UOM', type: FieldType.select, options: _uom, defaultValue: 'Nos'),
          FieldDefinition(key: 'is_default', label: 'Default for Item', type: FieldType.check),
          FieldDefinition(key: 'is_active', label: 'Active', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'BOM Item', options: 'BOM Item'),
          FieldDefinition(key: 'operations', label: 'Operations', type: FieldType.table, tableDocType: 'BOM Operation', options: 'BOM Operation'),
          FieldDefinition(key: 'raw_material_cost', label: 'Raw-Material Cost', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'operating_cost', label: 'Operating Cost', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'total_cost', label: 'Total Cost', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText, allowOnSubmit: true),
        ],
      );

  static DocType _bomItem() => const DocType(
        id: 'BOM Item',
        name: 'BOM Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'uom', label: 'UOM', type: FieldType.select, options: _uom, defaultValue: 'Nos'),
          FieldDefinition(key: 'scrap_pct', label: 'Scrap %', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'qty * rate'),
        ],
      );

  static DocType _bomOperation() => const DocType(
        id: 'BOM Operation',
        name: 'BOM Operation',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'operation', label: 'Operation', type: FieldType.link, linkDocType: 'Operation', options: 'Operation', required: true),
          FieldDefinition(key: 'workstation', label: 'Workstation', type: FieldType.link, linkDocType: 'Workstation', options: 'Workstation'),
          FieldDefinition(key: 'time_minutes', label: 'Time (min)', type: FieldType.float, required: true, defaultValue: '0'),
          FieldDefinition(key: 'hour_rate', label: 'Hour Rate', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'cost', label: 'Cost', type: FieldType.currency, readOnly: true, formulaExpression: '(time_minutes / 60) * hour_rate'),
        ],
      );

  // ---- Work Order ---------------------------------------------------------

  static DocType _workOrder() => const DocType(
        id: 'Work Order',
        name: 'Work Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'WO-.YYYY.-.####',
        workflowId: 'wf-work-order',
        fields: [
          FieldDefinition(key: 'item', label: 'Item to Produce', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'bom', label: 'BOM', type: FieldType.link, linkDocType: 'BOM', options: 'BOM', required: true),
          FieldDefinition(key: 'qty_to_produce', label: 'Qty to Produce', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'source_warehouse', label: 'Source Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse', required: true),
          FieldDefinition(key: 'target_warehouse', label: 'Target Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse', required: true),
          FieldDefinition(key: 'planned_start', label: 'Planned Start', type: FieldType.date),
          FieldDefinition(key: 'planned_end', label: 'Planned End', type: FieldType.date),
          FieldDefinition(key: 'required_items', label: 'Required Items', type: FieldType.table, tableDocType: 'Work Order Item', options: 'Work Order Item'),
          FieldDefinition(key: 'produced_qty', label: 'Produced Qty', type: FieldType.float, defaultValue: '0', allowOnSubmit: true),
          FieldDefinition(key: 'against_sales_order', label: 'Against Sales Order', type: FieldType.link, linkDocType: 'Sales Order', options: 'Sales Order'),
          FieldDefinition(key: 'against_production_plan', label: 'Against Production Plan', type: FieldType.link, linkDocType: 'Production Plan', options: 'Production Plan'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText, allowOnSubmit: true),
        ],
      );

  static DocType _workOrderItem() => const DocType(
        id: 'Work Order Item',
        name: 'Work Order Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'required_qty', label: 'Required Qty', type: FieldType.float, required: true, defaultValue: '0'),
          FieldDefinition(key: 'transferred_qty', label: 'Transferred Qty', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'consumed_qty', label: 'Consumed Qty', type: FieldType.float, defaultValue: '0'),
        ],
      );

  // ---- Job Card (status/time tracking only — does not post) ---------------

  static DocType _jobCard() => const DocType(
        id: 'Job Card',
        name: 'Job Card',
        module: _module,
        fields: [
          FieldDefinition(key: 'work_order', label: 'Work Order', type: FieldType.link, linkDocType: 'Work Order', options: 'Work Order', required: true),
          FieldDefinition(key: 'operation', label: 'Operation', type: FieldType.link, linkDocType: 'Operation', options: 'Operation', required: true),
          FieldDefinition(key: 'workstation', label: 'Workstation', type: FieldType.link, linkDocType: 'Workstation', options: 'Workstation'),
          FieldDefinition(key: 'status', label: 'Status', type: FieldType.select, options: 'Open\nIn Progress\nDone', defaultValue: 'Open'),
          FieldDefinition(key: 'planned_time_minutes', label: 'Planned Time (min)', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'actual_time_minutes', label: 'Actual Time (min)', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'completed_qty', label: 'Completed Qty', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'started_at', label: 'Started', type: FieldType.date),
          FieldDefinition(key: 'finished_at', label: 'Finished', type: FieldType.date),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  // ---- Production Plan -----------------------------------------------------

  static DocType _productionPlan() => const DocType(
        id: 'Production Plan',
        name: 'Production Plan',
        module: _module,
        isSubmittable: true,
        namingRule: 'PP-.YYYY.-.####',
        workflowId: 'wf-production-plan',
        fields: [
          FieldDefinition(key: 'plan_name', label: 'Plan Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'planning_date', label: 'Planning Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'default_source_warehouse', label: 'Default Source Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'default_target_warehouse', label: 'Default Target Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'items_to_manufacture', label: 'Items to Manufacture', type: FieldType.table, tableDocType: 'Production Plan Item', options: 'Production Plan Item'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText, allowOnSubmit: true),
        ],
      );

  static DocType _productionPlanItem() => const DocType(
        id: 'Production Plan Item',
        name: 'Production Plan Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'planned_qty', label: 'Planned Qty', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'bom', label: 'BOM', type: FieldType.link, linkDocType: 'BOM', options: 'BOM'),
          FieldDefinition(key: 'against_sales_order', label: 'Against Sales Order', type: FieldType.link, linkDocType: 'Sales Order', options: 'Sales Order'),
        ],
      );
}
