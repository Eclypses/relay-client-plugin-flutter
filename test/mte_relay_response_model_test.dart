import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay_client_plugin/mte_relay_response_model.dart';

import 'fixtures/test_data.dart';

void main() {
  group('Result', () {
    test('should parse success map correctly', () {
      final result = Result<dynamic>.fromMap(successfulMapResponse);

      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.statusCode, 200);
      expect(result.headers, testHeaders);
      expect(result.data, isA<List<int>>());
    });

    test('should parse error map correctly', () {
      final result = Result<dynamic>.fromMap(failedMapResponse);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Something went wrong');
      expect(result.statusCode, 500);
      expect(result.headers, testHeaders);
      expect(result.data, isNull);
    });

    test('should convert to map with expected shape', () {
      final result = Result.success('ok', headers: testHeaders, statusCode: 201);

      expect(result.toMap(), {
        'success': true,
        'data': 'ok',
        'error': null,
        'headers': testHeaders,
        'statusCode': 201,
      });
    });

    test('should decode bodyAsString when data is byte list', () {
      final result = Result.success(utf8JsonBytes.toList());

      expect(result.bodyAsString, '{"ok":true}');
    });

    test('should return empty bodyAsString for non-byte-list data', () {
      final result = Result.success('not-bytes');

      expect(result.bodyAsString, isEmpty);
    });

    test('should parse JSON body to object', () {
      final result = Result.success(utf8JsonBytes.toList());

      expect(result.bodyAsJsonObject, {'ok': true});
    });

    test('should return null for invalid JSON', () {
      final result = Result.success('hello'.codeUnits);

      expect(result.bodyAsJsonObject, isNull);
    });

    test('should return null for empty JSON body', () {
      final result = Result.success(<int>[]);

      expect(result.bodyAsJsonObject, isNull);
    });

    test('should coerce map header keys and values to strings', () {
      final response = {
        'success': true,
        'data': 'x',
        'headers': {1: true},
        'statusCode': 200,
      };

      final result = Result<dynamic>.fromMap(response);

      expect(result.headers, {'1': 'true'});
    });

    test('should return null headers when headers is not a map', () {
      final response = {
        'success': true,
        'data': 'x',
        'headers': 'invalid',
        'statusCode': 200,
      };

      final result = Result<dynamic>.fromMap(response);

      expect(result.headers, isNull);
    });
  });
}
