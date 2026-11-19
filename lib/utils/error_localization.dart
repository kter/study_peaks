import '../l10n/app_localizations.dart';
import '../services/network_exception.dart';

String localizeErrorKey(
  AppLocalizations l10n,
  String key, {
  String? fallback,
}) =>
    key == NetworkErrorKey.networkError ? l10n.networkError : fallback ?? key;
