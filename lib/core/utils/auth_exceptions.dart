/// Base class for all authentication errors. Carries a user-friendly message
/// that can be shown directly in the UI.
class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Raised when registration fails because the email is already in use.
class EmailAlreadyExistsException extends AuthException {
  const EmailAlreadyExistsException()
      : super(
          'An account with this email address already exists. '
          'Please sign in instead.',
        );
}

/// Raised at sign-in when no account exists for the provided email.
class UserNotFoundException extends AuthException {
  const UserNotFoundException()
      : super(
          'No account found with this email address. '
          'Please register first.',
        );
}

/// Raised at sign-in when the password is incorrect.
class WrongPasswordException extends AuthException {
  const WrongPasswordException()
      : super(
          'Incorrect password. Please try again or reset your password.',
        );
}

/// Raised when a registration password is too short/weak.
class WeakPasswordException extends AuthException {
  const WeakPasswordException()
      : super(
          'Your password is too weak. '
          'Please use at least 6 characters.',
        );
}

/// Fallback exception for any unhandled authentication failure.
class GenericAuthException extends AuthException {
  const GenericAuthException()
      : super(
          'Something went wrong. Please try again later.',
        );
}