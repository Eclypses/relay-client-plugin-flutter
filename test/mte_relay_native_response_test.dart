import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay_client_plugin/mte_relay_native_response.dart';

import 'fixtures/test_data.dart';

void main() {
  group('NativeHttpResponse', () {
    test('should parse success map correctly', () {
      final response = NativeHttpResponse.fromMap({
        'success': true,
        'data': utf8JsonBytes,
        'headers': testHeaders,
        'statusCode': 200,
      });

      expect(response.isSuccess, isTrue);
      expect(response.errorMessage, isNull);
      expect(response.statusCode, 200);
      expect(response.headers, testHeaders);
      expect(response.data, utf8JsonBytes);
    });

    test('should parse error map correctly', () {
      final response = NativeHttpResponse.fromMap(failedMapResponse);

      expect(response.isSuccess, isFalse);
      expect(response.errorMessage, 'Something went wrong');
      expect(response.statusCode, 500);
      expect(response.headers, testHeaders);
      expect(response.data, isNull);
    });

    test('should expose empty safeData when data is null', () {
      final response = NativeHttpResponse.error('error');

      expect(response.safeData, Uint8List(0));
    });

    test('should decode bodyAsString from bytes', () {
      final response = NativeHttpResponse.success(utf8JsonBytes);

      expect(response.bodyAsString, '{"ok":true}');
    });

    test('should decode JSON body object', () {
      final response = NativeHttpResponse.success(utf8JsonBytes);

      expect(response.bodyAsJsonObject, {'ok': true});
    });

    test('should return null for invalid JSON body', () {
      final response = NativeHttpResponse.success(
        Uint8List.fromList('invalid'.codeUnits),
      );

      expect(response.bodyAsJsonObject, isNull);
    });

    test('should return null for empty JSON body', () {
      final response = NativeHttpResponse.success(Uint8List(0));

      expect(response.bodyAsJsonObject, isNull);
    });

    test('should convert to map with expected shape', () {
      final response = NativeHttpResponse.success(
        utf8JsonBytes,
        headers: testHeaders,
        statusCode: 206,
      );

      expect(response.toMap(), {
        'success': true,
        'data': utf8JsonBytes,
        'error': null,
        'headers': testHeaders,
        'statusCode': 206,
      });
    });
  });
}
