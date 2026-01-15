import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provider for managing user settings stored locally.
/// Works whether user is signed in or not.
/// 
/// IMPORTANT: [init] must be called before any setter methods.
/// Getters return default values before initialization for UI loading states.
class UserSettingsProvider extends ChangeNotifier {
  static const _keyDisplayName = 'user_display_name';
  static const _keyIconSeed = 'user_icon_seed';
  static const _keyCountryCode = 'user_country_code';

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  String _displayName = 'Anonymous';
  String _iconSeed = '';
  String _countryCode = 'JP';
  bool _isLoading = true;

  String get displayName => _displayName;
  String get iconSeed => _iconSeed;
  String get countryCode => _countryCode;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  /// Throws [StateError] if [init] has not been called.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'UserSettingsProvider.init() must be called before modifying settings',
      );
    }
  }

  /// Initialize provider by loading saved settings.
  /// Must be called before any setter methods.
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    _prefs = await SharedPreferences.getInstance();
    
    _displayName = _prefs!.getString(_keyDisplayName) ?? 'Anonymous';
    _iconSeed = _prefs!.getString(_keyIconSeed) ?? const Uuid().v4();
    _countryCode = _prefs!.getString(_keyCountryCode) ?? 'JP';

    // Save default icon seed if not set
    if (_prefs!.getString(_keyIconSeed) == null) {
      await _prefs!.setString(_keyIconSeed, _iconSeed);
    }

    _isInitialized = true;
    _isLoading = false;
    notifyListeners();
  }

  /// Update display name.
  /// Throws [StateError] if [init] has not been called.
  Future<void> setDisplayName(String name) async {
    _ensureInitialized();
    _displayName = name.trim().isEmpty ? 'Anonymous' : name.trim();
    await _prefs!.setString(_keyDisplayName, _displayName);
    notifyListeners();
  }

  /// Update icon seed (regenerates jdenticon).
  /// Throws [StateError] if [init] has not been called.
  Future<void> setIconSeed(String seed) async {
    _ensureInitialized();
    _iconSeed = seed;
    await _prefs!.setString(_keyIconSeed, _iconSeed);
    notifyListeners();
  }

  /// Regenerate icon with new random seed.
  /// Throws [StateError] if [init] has not been called.
  Future<void> regenerateIcon() async {
    _ensureInitialized();
    _iconSeed = const Uuid().v4();
    await _prefs!.setString(_keyIconSeed, _iconSeed);
    notifyListeners();
  }

  /// Update country code.
  /// Throws [StateError] if [init] has not been called.
  Future<void> setCountryCode(String code) async {
    _ensureInitialized();
    _countryCode = code;
    await _prefs!.setString(_keyCountryCode, _countryCode);
    notifyListeners();
  }
}
