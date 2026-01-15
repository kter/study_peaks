import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserSettingsProvider', () {
    group('Initial State', () {
      test('has default displayName of Anonymous', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        
        // Before init
        expect(provider.displayName, 'Anonymous');
      });

      test('has default countryCode of JP', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        
        expect(provider.countryCode, 'JP');
      });

      test('isLoading is true before init completes', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        
        expect(provider.isLoading, true);
      });

      test('isInitialized is false before init', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        
        expect(provider.isInitialized, false);
      });
    });

    group('Uninitialized Access', () {
      test('setDisplayName throws StateError before init', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();

        expect(
          () => provider.setDisplayName('Test'),
          throwsA(isA<StateError>()),
        );
      });

      test('setCountryCode throws StateError before init', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();

        expect(
          () => provider.setCountryCode('US'),
          throwsA(isA<StateError>()),
        );
      });

      test('setIconSeed throws StateError before init', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();

        expect(
          () => provider.setIconSeed('seed'),
          throwsA(isA<StateError>()),
        );
      });

      test('regenerateIcon throws StateError before init', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();

        expect(
          () => provider.regenerateIcon(),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('init', () {
      test('loads saved displayName from preferences', () async {
        await setupMockSharedPreferences({
          'user_display_name': 'Saved User',
        });
        final provider = UserSettingsProvider();
        await provider.init();

        expect(provider.displayName, 'Saved User');
        expect(provider.isLoading, false);
      });

      test('loads saved countryCode from preferences', () async {
        await setupMockSharedPreferences({
          'user_country_code': 'US',
        });
        final provider = UserSettingsProvider();
        await provider.init();

        expect(provider.countryCode, 'US');
      });

      test('loads saved iconSeed from preferences', () async {
        await setupMockSharedPreferences({
          'user_icon_seed': 'custom-seed-123',
        });
        final provider = UserSettingsProvider();
        await provider.init();

        expect(provider.iconSeed, 'custom-seed-123');
      });

      test('generates new iconSeed if not saved', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        expect(provider.iconSeed, isNotEmpty);
        expect(provider.iconSeed.length, greaterThan(0));
      });
    });

    group('setDisplayName', () {
      test('updates displayName', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setDisplayName('New Name');

        expect(provider.displayName, 'New Name');
      });

      test('falls back to Anonymous for empty string', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setDisplayName('');

        expect(provider.displayName, 'Anonymous');
      });

      test('trims whitespace from name', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setDisplayName('  Trimmed Name  ');

        expect(provider.displayName, 'Trimmed Name');
      });

      test('falls back to Anonymous for whitespace-only string', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setDisplayName('   ');

        expect(provider.displayName, 'Anonymous');
      });

      test('notifies listeners on change', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        bool notified = false;
        provider.addListener(() => notified = true);

        await provider.setDisplayName('New Name');

        expect(notified, true);
      });
    });

    group('setCountryCode', () {
      test('updates countryCode', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setCountryCode('FR');

        expect(provider.countryCode, 'FR');
      });

      test('notifies listeners on change', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        bool notified = false;
        provider.addListener(() => notified = true);

        await provider.setCountryCode('DE');

        expect(notified, true);
      });
    });

    group('setIconSeed', () {
      test('updates iconSeed', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        await provider.setIconSeed('new-seed-456');

        expect(provider.iconSeed, 'new-seed-456');
      });
    });

    group('regenerateIcon', () {
      test('generates new random iconSeed', () async {
        await setupMockSharedPreferences({
          'user_icon_seed': 'original-seed',
        });
        final provider = UserSettingsProvider();
        await provider.init();

        final originalSeed = provider.iconSeed;
        expect(originalSeed, 'original-seed');

        await provider.regenerateIcon();

        expect(provider.iconSeed, isNot(originalSeed));
        expect(provider.iconSeed, isNotEmpty);
      });

      test('notifies listeners on regeneration', () async {
        await setupMockSharedPreferences();
        final provider = UserSettingsProvider();
        await provider.init();

        bool notified = false;
        provider.addListener(() => notified = true);

        await provider.regenerateIcon();

        expect(notified, true);
      });
    });

    group('Persistence', () {
      test('displayName persists across provider instances', () async {
        await setupMockSharedPreferences();
        
        // First instance sets the name
        final provider1 = UserSettingsProvider();
        await provider1.init();
        await provider1.setDisplayName('Persistent User');
        expect(provider1.displayName, 'Persistent User');

        // Second instance should load the same name
        final provider2 = UserSettingsProvider();
        await provider2.init();
        expect(provider2.displayName, 'Persistent User');
      });

      test('countryCode persists across provider instances', () async {
        await setupMockSharedPreferences();
        
        final provider1 = UserSettingsProvider();
        await provider1.init();
        await provider1.setCountryCode('UK');

        final provider2 = UserSettingsProvider();
        await provider2.init();
        expect(provider2.countryCode, 'UK');
      });
    });
  });
}
