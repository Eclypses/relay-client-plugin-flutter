import 'dart:developer' as developer;

class RelayException implements Exception {
  RelayException({
    required this.message,
    this.statusCode,
    this.rawMessage,
  });

  final String message;
  final int? statusCode;
  final String? rawMessage;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (statusCode=$statusCode)';
    return '$runtimeType: $message$code';
  }
}

class PairReplacedRetryableException extends RelayException {
  PairReplacedRetryableException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
  });
}

class PairReplaceFailedException extends RelayException {
  PairReplaceFailedException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
  });
}

class FullRepairCompletedRetryableException extends RelayException {
  FullRepairCompletedRetryableException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
  });
}

class FullRepairFailedException extends RelayException {
  FullRepairFailedException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
  });
}

class RelayProtocolErrorException extends RelayException {
  RelayProtocolErrorException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
  });
}

RelayException mapRelayProtocolException({
  required int statusCode,
  required String message,
  String? rawMessage,
}) {
  // Boundary log: one line per relay protocol failure, then the typed exception
  // is returned for the caller to throw. Status + message only — never payloads.
  // See dev_docs/LOGGING_CONVENTION.md §2.
  developer.log(
    'Relay protocol failure (status $statusCode): $message',
    name: 'MteRelay',
    level: 1000, // SEVERE
  );

  if (statusCode >= 559 && statusCode <= 563) {
    return PairReplacedRetryableException(
      message: message,
      statusCode: statusCode,
      rawMessage: rawMessage,
    );
  }

  if (statusCode == 564) {
    return FullRepairCompletedRetryableException(
      message: message,
      statusCode: statusCode,
      rawMessage: rawMessage,
    );
  }

  if (statusCode == 565) {
    return FullRepairFailedException(
      message: message,
      statusCode: statusCode,
      rawMessage: rawMessage,
    );
  }

  if (statusCode >= 566 && statusCode <= 569) {
    return RelayProtocolErrorException(
      message: message,
      statusCode: statusCode,
      rawMessage: rawMessage,
    );
  }

  return RelayException(
    message: message,
    statusCode: statusCode,
    rawMessage: rawMessage,
  );
}