/// The country pick-list shared by every `country` field (Company,
/// Customer, Supplier, Address). A curated select rather than free text,
/// because downstream consumers need to RESOLVE the value — the UBL
/// e-invoice maps each name to its ISO 3166-1 alpha-2 code, and the VAT
/// jurisdiction logic keys off it. Every entry here MUST resolve in
/// `UblInvoiceBuilder.countryCode` (a test enforces it); extend both
/// together.
///
/// EU-27 + EEA/UK/CH plus the common non-EU trading partners. Adding a
/// country is additive and safe; renaming one is a data migration.
const kCountryOptions = 'Malta\n'
    'Austria\n'
    'Belgium\n'
    'Bulgaria\n'
    'Croatia\n'
    'Cyprus\n'
    'Czech Republic\n'
    'Denmark\n'
    'Estonia\n'
    'Finland\n'
    'France\n'
    'Germany\n'
    'Greece\n'
    'Hungary\n'
    'Iceland\n'
    'Ireland\n'
    'Italy\n'
    'Latvia\n'
    'Lithuania\n'
    'Luxembourg\n'
    'Netherlands\n'
    'Norway\n'
    'Poland\n'
    'Portugal\n'
    'Romania\n'
    'Slovakia\n'
    'Slovenia\n'
    'Spain\n'
    'Sweden\n'
    'Switzerland\n'
    'United Kingdom\n'
    'United States\n'
    'Canada\n'
    'Australia\n'
    'New Zealand\n'
    'United Arab Emirates\n'
    'Turkey';
