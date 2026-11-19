import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/core/backend_service.dart';

void main() {
  group('BackendService', () {
    test('initial state is stopped', () {
      expect(BackendService.instance.currentState, BackendState.stopped);
    });

    test('baseUrl and healthUrl are correct', () {
      expect(BackendService.instance.baseUrl, 'http://127.0.0.1:8000');
      expect(BackendService.instance.healthUrl, 'http://127.0.0.1:8000/health');
    });
  });
}
