import 'package:mercantis_core/mercantis_core.dart';

/// The Hub's workflow state machines, ported field-for-field from the Swift
/// `HubWorkflows`. Each submittable DocType binds to one of these via its
/// `workflowId`. Transitions are gated to `System Manager` for now (Phase UX-2
/// will introduce finer role templates), and the two invoice "Mark as Paid"
/// transitions carry the `outstanding_amount <= 0` guard.
///
/// Definitions whose DocType has not been ported yet (Supplier Quotation, POS
/// Invoice, BOM, Work Order) are included for parity and stored inertly until
/// their modules land in Phase 6.
abstract final class HubWorkflows {
  static const _systemManager = ['System Manager'];

  static List<WorkflowDefinition> all() => [
        _quotation(),
        _salesOrder(),
        _salesInvoice(),
        _supplierQuotation(),
        _purchaseOrder(),
        _purchaseInvoice(),
        _purchaseReceipt(),
        _salesDelivery(),
        _posInvoice(),
        _stockEntry(),
        _journalEntry(),
        _paymentEntry(),
        _bom(),
        _workOrder(),
        _productionPlan(),
      ];

  // ---- helpers ------------------------------------------------------------

  static WorkflowState _state(String name, {bool isDefault = false, bool allowEdit = false}) =>
      WorkflowState(name: name, isDefault: isDefault, allowEdit: allowEdit);

  static WorkflowTransition _t(
    String workflowId,
    String from,
    String to,
    String action, {
    String? condition,
  }) =>
      WorkflowTransition(
        id: '$workflowId:$from->$to',
        fromState: from,
        toState: to,
        action: action,
        allowedRoles: _systemManager,
        conditionExpression: condition,
      );

  // ---- definitions --------------------------------------------------------

  static WorkflowDefinition _quotation() => WorkflowDefinition(
        id: 'wf-quotation',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Ordered'),
          _state('Lost'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-quotation', 'Draft', 'Submitted', 'Submit'),
          _t('wf-quotation', 'Submitted', 'Ordered', 'Mark as Ordered'),
          _t('wf-quotation', 'Submitted', 'Lost', 'Mark as Lost'),
          _t('wf-quotation', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _salesOrder() => WorkflowDefinition(
        id: 'wf-sales-order',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Closed'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-sales-order', 'Draft', 'Submitted', 'Submit'),
          _t('wf-sales-order', 'Submitted', 'Closed', 'Close'),
          _t('wf-sales-order', 'Submitted', 'Cancelled', 'Cancel'),
          _t('wf-sales-order', 'Closed', 'Submitted', 'Re-open'),
        ],
      );

  static WorkflowDefinition _salesInvoice() => WorkflowDefinition(
        id: 'wf-sales-invoice',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Paid'),
          _state('Overdue'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-sales-invoice', 'Draft', 'Submitted', 'Submit'),
          _t('wf-sales-invoice', 'Submitted', 'Paid', 'Mark as Paid', condition: 'outstanding_amount <= 0'),
          _t('wf-sales-invoice', 'Submitted', 'Overdue', 'Mark as Overdue'),
          _t('wf-sales-invoice', 'Overdue', 'Paid', 'Mark as Paid', condition: 'outstanding_amount <= 0'),
          _t('wf-sales-invoice', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _supplierQuotation() => WorkflowDefinition(
        id: 'wf-supplier-quotation',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Ordered'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-supplier-quotation', 'Draft', 'Submitted', 'Submit'),
          _t('wf-supplier-quotation', 'Submitted', 'Ordered', 'Mark as Ordered'),
          _t('wf-supplier-quotation', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _purchaseOrder() => WorkflowDefinition(
        id: 'wf-purchase-order',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Closed'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-purchase-order', 'Draft', 'Submitted', 'Submit'),
          _t('wf-purchase-order', 'Submitted', 'Closed', 'Close'),
          _t('wf-purchase-order', 'Submitted', 'Cancelled', 'Cancel'),
          _t('wf-purchase-order', 'Closed', 'Submitted', 'Re-open'),
        ],
      );

  static WorkflowDefinition _purchaseInvoice() => WorkflowDefinition(
        id: 'wf-purchase-invoice',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Paid'),
          _state('Overdue'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-purchase-invoice', 'Draft', 'Submitted', 'Submit'),
          _t('wf-purchase-invoice', 'Submitted', 'Paid', 'Mark as Paid', condition: 'outstanding_amount <= 0'),
          _t('wf-purchase-invoice', 'Submitted', 'Overdue', 'Mark as Overdue'),
          _t('wf-purchase-invoice', 'Overdue', 'Paid', 'Mark as Paid', condition: 'outstanding_amount <= 0'),
          _t('wf-purchase-invoice', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _purchaseReceipt() => WorkflowDefinition(
        id: 'wf-purchase-receipt',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-purchase-receipt', 'Draft', 'Submitted', 'Submit'),
          _t('wf-purchase-receipt', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _salesDelivery() => WorkflowDefinition(
        id: 'wf-sales-delivery',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Scheduled'),
          _state('Loaded'),
          _state('Out for Delivery'),
          _state('Delivered'),
          _state('Failed'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-sales-delivery', 'Draft', 'Scheduled', 'Submit'),
          _t('wf-sales-delivery', 'Scheduled', 'Loaded', 'Mark Loaded'),
          _t('wf-sales-delivery', 'Loaded', 'Out for Delivery', 'Mark Out for Delivery'),
          _t('wf-sales-delivery', 'Out for Delivery', 'Delivered', 'Mark Delivered'),
          _t('wf-sales-delivery', 'Out for Delivery', 'Failed', 'Mark Failed'),
          _t('wf-sales-delivery', 'Failed', 'Scheduled', 'Reschedule'),
          _t('wf-sales-delivery', 'Scheduled', 'Cancelled', 'Cancel'),
          _t('wf-sales-delivery', 'Loaded', 'Cancelled', 'Cancel'),
          _t('wf-sales-delivery', 'Out for Delivery', 'Cancelled', 'Cancel'),
          _t('wf-sales-delivery', 'Delivered', 'Cancelled', 'Cancel'),
          _t('wf-sales-delivery', 'Failed', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _posInvoice() => WorkflowDefinition(
        id: 'wf-pos-invoice',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-pos-invoice', 'Draft', 'Submitted', 'Submit'),
          _t('wf-pos-invoice', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _stockEntry() => WorkflowDefinition(
        id: 'wf-stock-entry',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-stock-entry', 'Draft', 'Submitted', 'Submit'),
          _t('wf-stock-entry', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _journalEntry() => WorkflowDefinition(
        id: 'wf-journal-entry',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-journal-entry', 'Draft', 'Submitted', 'Submit'),
          _t('wf-journal-entry', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _paymentEntry() => WorkflowDefinition(
        id: 'wf-payment-entry',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Reconciled'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-payment-entry', 'Draft', 'Submitted', 'Submit'),
          _t('wf-payment-entry', 'Submitted', 'Reconciled', 'Reconcile'),
          _t('wf-payment-entry', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _bom() => WorkflowDefinition(
        id: 'wf-bom',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Inactive'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-bom', 'Draft', 'Submitted', 'Submit'),
          _t('wf-bom', 'Submitted', 'Inactive', 'Deactivate'),
          _t('wf-bom', 'Inactive', 'Submitted', 'Reactivate'),
          _t('wf-bom', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _workOrder() => WorkflowDefinition(
        id: 'wf-work-order',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('InProgress'),
          _state('Completed'),
          _state('Stopped'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-work-order', 'Draft', 'Submitted', 'Submit'),
          _t('wf-work-order', 'Submitted', 'InProgress', 'Start'),
          _t('wf-work-order', 'InProgress', 'Completed', 'Complete'),
          _t('wf-work-order', 'InProgress', 'Stopped', 'Stop'),
          _t('wf-work-order', 'Stopped', 'InProgress', 'Resume'),
          _t('wf-work-order', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );

  static WorkflowDefinition _productionPlan() => WorkflowDefinition(
        id: 'wf-production-plan',
        states: [
          _state('Draft', isDefault: true, allowEdit: true),
          _state('Submitted'),
          _state('Cancelled'),
        ],
        transitions: [
          _t('wf-production-plan', 'Draft', 'Submitted', 'Submit'),
          _t('wf-production-plan', 'Submitted', 'Cancelled', 'Cancel'),
        ],
      );
}
