import 'package:mercantis_core/mercantis_core.dart';

import '../common/countries.dart';

abstract final class CrmModule {
  static const _module = 'CRM';

  static List<DocType> docTypes() => [
        _lead(),
        _opportunity(),
        _contact(),
        _customer(),
        _address(),
        _dynamicLink(),
      ];

  /// Postal address, linkable to any party via the [_dynamicLink] child table.
  static DocType _address() => const DocType(
        id: 'Address',
        name: 'Address',
        module: _module,
        fields: [
          FieldDefinition(key: 'address_title', label: 'Title', type: FieldType.data, required: true),
          FieldDefinition(key: 'address_type', label: 'Address Type', type: FieldType.select, options: 'Billing\nShipping\nOffice\nPersonal\nOther', defaultValue: 'Billing'),
          FieldDefinition(key: 'address_line1', label: 'Address Line 1', type: FieldType.data, required: true),
          FieldDefinition(key: 'address_line2', label: 'Address Line 2', type: FieldType.data),
          FieldDefinition(key: 'city', label: 'City', type: FieldType.data, required: true),
          FieldDefinition(key: 'state', label: 'State / Province', type: FieldType.data),
          FieldDefinition(key: 'country', label: 'Country', type: FieldType.select, options: kCountryOptions, required: true),
          FieldDefinition(key: 'pincode', label: 'Postcode', type: FieldType.data),
          FieldDefinition(key: 'phone', label: 'Phone', type: FieldType.data),
          FieldDefinition(key: 'fax', label: 'Fax', type: FieldType.data),
          FieldDefinition(key: 'links', label: 'Linked To', type: FieldType.table, tableDocType: 'Dynamic Link', options: 'Dynamic Link'),
        ],
      );

  /// Polymorphic link row (e.g. an Address linked to a Customer/Supplier).
  static DocType _dynamicLink() => const DocType(
        id: 'Dynamic Link',
        name: 'Dynamic Link',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'link_doctype', label: 'Link DocType', type: FieldType.select, options: 'Customer\nSupplier\nContact\nLead', required: true),
          FieldDefinition(key: 'link_name', label: 'Link Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'is_primary', label: 'Primary', type: FieldType.check),
        ],
      );

  static DocType _lead() => const DocType(
        id: 'Lead',
        name: 'Lead',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'first_name', label: 'First Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'last_name', label: 'Last Name', type: FieldType.data),
          FieldDefinition(key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(key: 'phone', label: 'Phone', type: FieldType.data),
          FieldDefinition(key: 'company_name', label: 'Company', type: FieldType.data),
          FieldDefinition(
            key: 'lead_source',
            label: 'Lead Source',
            type: FieldType.select,
            options: 'Cold Call\nEmail\nExisting Customer\nReferral\nWebsite\nSocial Media\nOther',
          ),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nWorking\nNurturing\nQualified\nUnqualified\nConverted',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  static DocType _opportunity() => const DocType(
        id: 'Opportunity',
        name: 'Opportunity',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'opportunity_name', label: 'Opportunity Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'contact', label: 'Contact', type: FieldType.link, linkDocType: 'Contact', options: 'Contact'),
          FieldDefinition(
            key: 'opportunity_type',
            label: 'Opportunity Type',
            type: FieldType.select,
            options: 'Sales\nSupport\nMaintenance',
          ),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nQuotation\nNurturing\nConverted\nLost\nClosed',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'expected_closing', label: 'Expected Closing', type: FieldType.date),
          FieldDefinition(key: 'opportunity_amount', label: 'Opportunity Amount', type: FieldType.currency),
          FieldDefinition(key: 'probability', label: 'Probability (%)', type: FieldType.percent),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  static DocType _contact() => const DocType(
        id: 'Contact',
        name: 'Contact',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'first_name', label: 'First Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'last_name', label: 'Last Name', type: FieldType.data),
          FieldDefinition(key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(key: 'mobile', label: 'Mobile', type: FieldType.data),
          FieldDefinition(key: 'company_name', label: 'Company', type: FieldType.data),
          FieldDefinition(key: 'designation', label: 'Designation', type: FieldType.data),
          FieldDefinition(
            key: 'gender',
            label: 'Gender',
            type: FieldType.select,
            options: 'Male\nFemale\nNon-Binary\nOther',
          ),
        ],
      );

  static DocType _customer() => const DocType(
        id: 'Customer',
        name: 'Customer',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'customer_name', label: 'Customer Name', type: FieldType.data, required: true),
          FieldDefinition(
            key: 'customer_type',
            label: 'Customer Type',
            type: FieldType.select,
            options: 'Company\nIndividual',
            defaultValue: 'Company',
          ),
          FieldDefinition(key: 'customer_group', label: 'Customer Group', type: FieldType.data),
          // The buyer identity online channels dedupe on (Phase 5) — also
          // where statements and reminders get sent.
          FieldDefinition(key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(key: 'territory', label: 'Territory', type: FieldType.data),
          FieldDefinition(key: 'tax_id', label: 'Tax ID', type: FieldType.data),
          FieldDefinition(key: 'country', label: 'Country', type: FieldType.select, options: kCountryOptions),
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          // S8 pricing: this customer's negotiated rates. Second in the
          // resolution order, after a document's explicit price list.
          FieldDefinition(key: 'default_price_list', label: 'Default Price List', type: FieldType.link, linkDocType: 'Price List', options: 'Price List'),
          FieldDefinition(key: 'website', label: 'Website', type: FieldType.data),
        ],
      );
}
