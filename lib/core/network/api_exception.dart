/// Thrown by [ApiClient] for any failure — network, timeout, non-2xx status,
/// or a `{ ok:false, msg }` business-logic failure from the backend.
///
/// [message] is always safe to show directly to the user (English or Arabic
/// depending on what the caller passes to [ApiException.userFacing]).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;
  /// True when this came from a `{ ok:false }` response with no `msg` field
  /// — i.e. the server didn't explain itself. Callers use this to swap in a
  /// clearer, context-specific message instead of the generic fallback.
  final bool isGenericFailure;

  const ApiException(this.message, {this.statusCode, this.cause, this.isGenericFailure = false});

  /// No internet / DNS / socket-level failure.
  factory ApiException.network() => const ApiException(
        'Can\'t reach the WASFA server. Check your internet connection and try again.',
      );

  /// Request took too long.
  factory ApiException.timeout() => const ApiException(
        'That took too long to respond. Please try again.',
      );

  /// Server responded but with an error status code.
  factory ApiException.server(int statusCode, {String? serverMessage}) => ApiException(
        serverMessage?.trim().isNotEmpty == true
            ? serverMessage!
            : (statusCode >= 500
                ? 'Something went wrong on our end. Please try again in a moment.'
                : 'We couldn\'t process that request.'),
        statusCode: statusCode,
      );

  /// `{ ok:false, msg }` style business failure (e.g. wallet balance too low).
  /// [isGenericFailure] is true when the server gave no `msg` at all — see
  /// [withFallbackMessage] for how callers turn that into something clearer.
  factory ApiException.business(String msg, {bool isGenericFailure = false}) =>
      ApiException(msg, isGenericFailure: isGenericFailure);

  /// Response body wasn't valid/expected JSON.
  factory ApiException.parse() => const ApiException(
        'We had trouble reading the server\'s response. Please try again.',
      );

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Turns any caught error into a message safe to show in a toast/banner.
/// Use this at every catch site instead of `e.toString()`.
String describeError(Object error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Runs [action]; if it fails with a generic `{ ok:false }` (no `msg` from
/// the server — see [ApiException.isGenericFailure]), rethrows with
/// [fallback] instead, so the person sees something specific to what they
/// were doing ("Couldn't save this address") rather than a bare "Request
/// failed." Any other error (network, timeout, a real server `msg`) passes
/// through unchanged.
Future<T> withFallbackMessage<T>(Future<T> Function() action, String fallback) async {
  try {
    return await action();
  } on ApiException catch (e) {
    if (e.isGenericFailure) {
      throw ApiException(fallback, statusCode: e.statusCode, cause: e.cause);
    }
    rethrow;
  }
}
