/// Which credential the user is authenticating with.
enum AuthMethod { email, phone }

/// Which action the current form is performing.
/// Only meaningful for [AuthMethod.email] — phone auth is passwordless
/// and unifies login/signup into a single OTP flow (the backend decides
/// whether the number belongs to a new or existing account).
enum AuthMode { login, signUp }

/// Tokens returned by the backend on a successful login/signup/verification.
/// Storing these (secure storage, in-memory, etc.) is the caller's
/// responsibility — this widget set only produces them.
class AuthTokens {
  final String accessToken;
  final String? refreshToken;

  const AuthTokens({required this.accessToken, this.refreshToken});
}

/// Thrown by [AuthApi] methods for known, user-facing failures
/// (bad credentials, invalid/expired code, email already registered, etc).
/// Anything else (network failure, 500s) should propagate as its natural
/// exception type so the UI can fall back to a generic error message.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
