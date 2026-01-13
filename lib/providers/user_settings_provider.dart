import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provider for managing user settings stored locally.
/// Works whether user is signed in or not.
class UserSettingsProvider extends ChangeNotifier {
  static const _keyDisplayName = 'user_display_name';
  static const _keyIconSeed = 'user_icon_seed';
  static const _keyCountryCode = 'user_country_code';

  SharedPreferences? _prefs;
  String _displayName = 'Anonymous';
  String _iconSeed = '';
  String _countryCode = 'JP';
  bool _isLoading = true;

  String get displayName => _displayName;
  String get iconSeed => _iconSeed;
  String get countryCode => _countryCode;
  bool get isLoading => _isLoading;

  /// Initialize provider by loading saved settings
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    _prefs = await SharedPreferences.getInstance();
    
    _displayName = _prefs?.getString(_keyDisplayName) ?? 'Anonymous';
    _iconSeed = _prefs?.getString(_keyIconSeed) ?? const Uuid().v4();
    _countryCode = _prefs?.getString(_keyCountryCode) ?? 'JP';

    // Save default icon seed if not set
    if (_prefs?.getString(_keyIconSeed) == null) {
      await _prefs?.setString(_keyIconSeed, _iconSeed);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Update display name
  Future<void> setDisplayName(String name) async {
    _displayName = name.trim().isEmpty ? 'Anonymous' : name.trim();
    await _prefs?.setString(_keyDisplayName, _displayName);
    notifyListeners();
  }

  /// Update icon seed (regenerates jdenticon)
  Future<void> setIconSeed(String seed) async {
    _iconSeed = seed;
    await _prefs?.setString(_keyIconSeed, _iconSeed);
    notifyListeners();
  }

  /// Regenerate icon with new random seed
  Future<void> regenerateIcon() async {
    _iconSeed = const Uuid().v4();
    await _prefs?.setString(_keyIconSeed, _iconSeed);
    notifyListeners();
  }

  /// Update country code
  Future<void> setCountryCode(String code) async {
    _countryCode = code;
    await _prefs?.setString(_keyCountryCode, _countryCode);
    notifyListeners();
  }
}
