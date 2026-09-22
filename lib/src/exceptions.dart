/// Thrown when controls are not available on the current platform: any
/// platform other than iOS, or iOS older than 18.
class ControlCenterUnsupportedException implements Exception {
  /// Creates the exception with a human readable [message].
  const ControlCenterUnsupportedException(this.message);

  /// Why controls are unavailable.
  final String message;

  @override
  String toString() => 'ControlCenterUnsupportedException: $message';
}

/// Thrown when the native side rejects a call, for example because
/// [code] is `not_configured` (call `configure` first) or
/// `app_group_unavailable` (the App Group entitlement is missing).
class FlutterControlCenterException implements Exception {
  /// Creates the exception from a native error [code] and [message].
  const FlutterControlCenterException(this.code, this.message);

  /// Machine readable error code: `invalid_argument`, `not_configured`,
  /// `app_group_unavailable` or `native_error`.
  final String code;

  /// Human readable description of the failure.
  final String message;

  @override
  String toString() => 'FlutterControlCenterException($code): $message';
}
