import 'dart:developer' as developer;

class RelayException implements Exception {
  RelayException({
    required this.message,
    this.statusCode,
    this.rawMessage,
    this.reason,
  });

  final String message;
  final int? statusCode;
  final String? rawMessage;

  /// The relay's registry reason, such as `body_too_large` or `pool_exhausted`, when the
  /// relay itself refused the request. Null when something else answered: a 413 from a
  /// proxy in front of the relay has a status and no reason, which is how the two differ.
  final String? reason;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (statusCode=$statusCode)';
    final why = reason == null ? '' : ' [$reason]';
    return '$runtimeType: $message$code$why';
  }
}

class PairReplacedRetryableException extends RelayException {
  PairReplacedRetryableException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
    super.reason,
  });
}

class PairReplaceFailedException extends RelayException {
  PairReplaceFailedException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
    super.reason,
  });
}

class FullRepairCompletedRetryableException extends RelayException {
  FullRepairCompletedRetryableException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
    super.reason,
  });
}

class FullRepairFailedException extends RelayException {
  FullRepairFailedException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
    super.reason,
  });
}

/// No longer thrown: it stood for statuses 566 to 569 of the previous protocol, which a
/// frame version 2 relay never sends. Kept so code that catches it still compiles.
class RelayProtocolErrorException extends RelayException {
  RelayProtocolErrorException({
    required super.message,
    required super.statusCode,
    super.rawMessage,
    super.reason,
  });
}

/// The recovery a relay refusal calls for, from the frame version 2 registry. Only the
/// entries that change what the caller should do are listed; everything else surfaces.
enum _RelayRecovery { replacePair, fullRepair, surface }

_RelayRecovery _recoveryFor(int code, String? reason) {
  switch ((code, reason)) {
    case (470 || 471 || 472 || 473 || 474, _):
    case (477, 'eof_before_end'):
    case (486, 'pair_busy'):
    case (503, 'state_store_write_failed'):
      return _RelayRecovery.replacePair;
    case (475, 'unknown_key'):
      return _RelayRecovery.surface;
    case (475, _):
      return _RelayRecovery.fullRepair;
    default:
      return _RelayRecovery.surface;
  }
}

/// Turns a relay refusal into the typed exception that says whether to retry.
///
/// The native library has already applied the recovery by the time this runs; the request
/// that met the refusal is never resent. [outcome] is that recovery's result when the
/// platform reports it (iOS does); otherwise the registry entry for [statusCode] and
/// [reason] decides. Keyed on the frame version 2 codes, 470 to 490: the 559 to 569 range
/// this used to read belongs to the previous protocol and a current relay never sends it.
RelayException mapRelayProtocolException({
  required int statusCode,
  required String message,
  String? rawMessage,
  String? reason,
  String? outcome,
}) {
  // Boundary log: one line per relay protocol failure, then the typed exception
  // is returned for the caller to throw. Status + message only — never payloads.
  developer.log(
    'Relay protocol failure (status $statusCode${reason == null ? '' : ' $reason'}): $message',
    name: 'MteRelay',
    level: 1000, // SEVERE
  );

  final recovery = switch (outcome) {
    'pairReplaced' || 'pairReplaceFailed' => _RelayRecovery.replacePair,
    'fullRepairSuccess' || 'fullRepairFailed' => _RelayRecovery.fullRepair,
    _ => _recoveryFor(statusCode, reason),
  };
  final failed = outcome == 'pairReplaceFailed' || outcome == 'fullRepairFailed';

  switch (recovery) {
    case _RelayRecovery.replacePair when failed:
      return PairReplaceFailedException(
        message: message, statusCode: statusCode, rawMessage: rawMessage, reason: reason);
    case _RelayRecovery.replacePair:
      return PairReplacedRetryableException(
        message: message, statusCode: statusCode, rawMessage: rawMessage, reason: reason);
    case _RelayRecovery.fullRepair when failed:
      return FullRepairFailedException(
        message: message, statusCode: statusCode, rawMessage: rawMessage, reason: reason);
    case _RelayRecovery.fullRepair:
      return FullRepairCompletedRetryableException(
        message: message, statusCode: statusCode, rawMessage: rawMessage, reason: reason);
    case _RelayRecovery.surface:
      return RelayException(
        message: message, statusCode: statusCode, rawMessage: rawMessage, reason: reason);
  }
}
