/// Base class for call-related failures.
class CallException implements Exception {
  final String message;

  const CallException(this.message);

  @override
  String toString() => message;
}

/// Raised when required permissions (camera/microphone) are denied.
class PermissionDeniedException extends CallException {
  const PermissionDeniedException()
      : super(
          'Camera and microphone permissions are required to make calls. '
          'Please enable them in Settings.',
        );
}