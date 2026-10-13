import 'models/auth_models.dart';

/// Boundary between the auth UI and your actual backend.
/// Implement this against your existing HTTP client and Memoize's
/// auth endpoints. Throw [AuthException] with a user-facing message for
/// known failures (wrong password, expired/invalid code, duplicate email,
/// etc); let unexpected errors (network, 5xx) propagate as-is so the UI
/// can fall back to a generic "something went wrong" message.
///
/// Every verification-style flow in this app (email signup, email
/// password reset, phone auth) follows the same shape: send a 6-digit
/// code, verify it in a second call. Nothing here uses email links.
abstract class AuthApi {
  // ---- Email + password ----

  Future<AuthTokens> loginWithEmail({required String email, required String password});

  /// Step 1 of email sign-up: creates the account in an unverified state
  /// and sends a 6-digit code to [email]. No tokens yet — the account
  /// isn't usable until [verifyEmailSignUp] succeeds.
  Future<void> signUpWithEmail({required String email, required String password});

  /// Step 2 of email sign-up: verifies the code and marks the account
  /// verified, returning tokens.
  Future<AuthTokens> verifyEmailSignUp({required String email, required String code});

  /// Step 1 of email password reset: sends a 6-digit code to an existing
  /// account's email.
  Future<void> requestEmailPasswordReset({required String email});

  /// Step 2: verifies the code and sets a new password.
  Future<void> completeEmailPasswordReset({required String email, required String code, required String newPassword});

  // ---- Phone (passwordless) ----
  // Login and signup are the same flow: send a code, verify it, get
  // tokens back. The backend decides whether the number is new
  // (creates an account) or existing (logs in) — the client doesn't
  // need to know or care which happened.

  /// Sends an OTP to [phone]. Works for both new and existing numbers.
  Future<void> sendPhoneOtp({required String phone});

  /// Verifies the code. On success the backend has either logged the
  /// user in or created + logged in a new account for this number.
  Future<AuthTokens> verifyPhoneOtp({required String phone, required String code});
}
