import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/config/app_config.dart';
import 'package:study_peaks/services/api_service.dart';

void main() {
  const devUrl = 'https://study-peaks-api-dev-opjqzrfbbq-an.a.run.app/v1';
  const prdUrl = 'https://study-peaks-api-prd-ozokydui6a-an.a.run.app/v1';

  group('AppConfig', () {
    test('dev flavor uses the dev API', () {
      expect(AppConfig.apiBaseUrlForFlavor('dev'), devUrl);
    });

    test('prd flavor uses the production API', () {
      expect(AppConfig.apiBaseUrlForFlavor('prd'), prdUrl);
    });

    test('missing flavor uses the production API', () {
      expect(AppConfig.apiBaseUrlForFlavor(null), prdUrl);
    });

    test('unknown and empty flavors use the production API', () {
      expect(AppConfig.apiBaseUrlForFlavor('staging'), prdUrl);
      expect(AppConfig.apiBaseUrlForFlavor(''), prdUrl);
    });

    test('apiBaseUrl resolves the Flutter app flavor', () {
      expect(AppConfig.apiBaseUrl, appFlavor == 'dev' ? devUrl : prdUrl);
    });
  });

  group('ApiService', () {
    test('defaults to the configured API URL', () {
      final service = ApiService();
      addTearDown(service.dispose);

      expect(service.baseUrl, AppConfig.apiBaseUrl);
    });

    test('preserves an explicitly supplied API URL', () {
      final service = ApiService(baseUrl: 'http://localhost:8080/v1');
      addTearDown(service.dispose);

      expect(service.baseUrl, 'http://localhost:8080/v1');
    });
  });
}
