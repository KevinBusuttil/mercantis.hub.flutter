import 'package:mercantis_core/mercantis_core.dart';

/// Plain words for a storage failure (R7), or null when [e] is not one.
String? friendlyStorageError(Object e) => storageErrorText(e);
