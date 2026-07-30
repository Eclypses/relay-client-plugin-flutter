import 'dart:typed_data';

const Map<String, String> testHeaders = {
  'content-type': 'application/json',
  'x-request-id': 'req-123',
};

const Map<dynamic, dynamic> successfulMapResponse = {
  'success': true,
  'data': [123, 34, 111, 107, 34, 58, 116, 114, 117, 101, 125],
  'headers': testHeaders,
  'statusCode': 200,
};

const Map<dynamic, dynamic> failedMapResponse = {
  'success': false,
  'error': 'Something went wrong',
  'headers': testHeaders,
  'statusCode': 500,
};

final Uint8List utf8JsonBytes = Uint8List.fromList(
  [123, 34, 111, 107, 34, 58, 116, 114, 117, 101, 125],
);

const Map<String, dynamic> testArgs = {
  'url': 'https://relay.example.com',
  'route': '/v1/data',
  'method': 'POST',
  'headers': {'authorization': 'Bearer token'},
  'headersToEncrypt': ['authorization'],
  'body': '{"hello":"world"}',
};
