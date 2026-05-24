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
          FieldDefinition(fieldKey: 'first_name', label: 'First Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'last_name', label: 'Last Name', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'email', label: 'Email', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'phone', label: 'Phone', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'company_name', label: 'Company', fieldType: FieldType.data),
          FieldDefinition(
            fieldKey: 'lead_source',
            label: 'Lead Source',
            fieldType: FieldType.select,
            options: 'Cold Call\nEmail\nExisting Customer\nReferral\nWebsite\nSocial Media\nOther',
          ),
          FieldDefinition(
            fieldKey: 'status',
            label: 'Status',
            fieldType: FieldType.select,
            options: 'Open\nWorking\nNurturing\nQualified\nUnqualified\nConverted',
            defaultValue: 'Open',
          ),
          FieldDefinition(fieldKey: 'notes', label: 'Notes', fieldType: FieldType.textEditor),
        ],
      );

  static DocType _opportunity() => DocType(
        id: 'Opportunity',
        name: 'Opportunity',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(fieldKey: 'opportunity_name', label: 'Opportunity Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'customer', label: 'Customer', fieldType: FieldType.link, options: 'Customer'),
          FieldDefinition(fieldKey: 'contact', label: 'Contact', fieldType: FieldType.link, options: 'Contact'),
          FieldDefinition(
            fieldKey: 'opportunity_type',
            label: 'Opportunity Type',
            fieldType: FieldType.select,
            options: 'Sales\nSupport\nMaintenance',
          ),
          FieldDefinition(
            fieldKey: 'status',
            label: 'Status',
            fieldType: FieldType.select,
            options: 'Open\nQuotation\nNurturing\nConverted\nLost\nClosed',
            defaultValue: 'Open',
          ),
          FieldDefinition(fieldKey: 'expected_closing', label: 'Expected Closing', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'opportunity_amount', label: 'Opportunity Amount', fieldType: FieldType.currency),
          FieldDefinition(fieldKey: 'probability', label: 'Probability (%)', fieldType: FieldType.percent),
          FieldDefinition(fieldKey: 'notes', label: 'Notes', fieldType: FieldType.textEditor),
        ],
      );

  static DocType _contact() => DocType(
        id: 'Contact',
        name: 'Contact',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(fieldKey: 'first_name', label: 'First Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'last_name', label: 'Last Name', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'email', label: 'Email', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'mobile', label: 'Mobile', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'company_name', label: 'Company', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'designation', label: 'Designation', fieldType: FieldType.data),
          FieldDefinition(
            fieldKey: 'gender',
            label: 'Gender',
            fieldType: FieldType.select,
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
          FieldDefinition(fieldKey: 'customer_name', label: 'Customer Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(
            fieldKey: 'customer_type',
            label: 'Customer Type',
            fieldType: FieldType.select,
            options: 'Company\nIndividual',
            defaultValue: 'Company',
          ),
          FieldDefinition(fieldKey: 'customer_group', label: 'Customer Group', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'territory', label: 'Territory', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'tax_id', label: 'Tax ID', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'default_currency', label: 'Default Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'website', label: 'Website', fieldType: FieldType.data),
        ],
      );
}
