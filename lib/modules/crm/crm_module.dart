import 'package:mercantis_core/mercantis_core.dart';

abstract final class CrmModule {
  static const _module = 'CRM';

  static List<DocType> docTypes() => [
        _lead(),
        _opportunity(),
        _contact(),
        _customer(),
      ];

  static DocType _lead() => DocType(
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

  static DocType _opportunity() => DocType(
        id: 'Opportunity',
        name: 'Opportunity',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'opportunity_name', label: 'Opportunity Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, options: 'Customer'),
          FieldDefinition(key: 'contact', label: 'Contact', type: FieldType.link, options: 'Contact'),
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

  static DocType _contact() => DocType(
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

  static DocType _customer() => DocType(
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
          FieldDefinition(key: 'territory', label: 'Territory', type: FieldType.data),
          FieldDefinition(key: 'tax_id', label: 'Tax ID', type: FieldType.data),
          FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.link, options: 'Currency'),
          FieldDefinition(key: 'website', label: 'Website', type: FieldType.data),
        ],
      );
}
