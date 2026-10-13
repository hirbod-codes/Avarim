import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/api_call_extensions.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/subscription/models/subscription.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plain service object, not a Notifier — it holds no state of its own.
/// Loading/error bookkeeping for whichever action is in flight is
/// handled the same way it is on the auth page: by wrapping each call
/// in authActionControllerProvider.run() at the call site.
class AccountController extends Notifier {
  late final Dio _authDio;

  @override
  void build() {
    _authDio = ref.read(authDioProvider);
  }

  Future<Subscription?> getUserSubscription() async {
    final response = await apiCall<Subscription>(() => _authDio.get('/api/subscription'), fromJson: (data) => Subscription.fromJson(data));
    return response.dataOrNull;
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await apiCall(
      () => _authDio
          .post('/api/auth/email/change-password', data: {'currentPassword': currentPassword, 'newPassword': newPassword})
          .notifyOnSuccess(rootContext == null ? 'Password updated.' : (AppLocalizations.of(rootContext!)?.password_updated ?? 'Password updated.')),
    );
  }

  Future<void> requestEmailChange({required String newEmail}) async {
    await apiCall(
      () => _authDio
          .post('/api/auth/email/change', data: {'newEmail': newEmail})
          .notifyOnSuccess(
            rootContext == null
                ? 'Verification code sent to your new email.'
                : (AppLocalizations.of(rootContext!)?.code_sent_to_email ?? 'Verification code sent to your new email.'),
          ),
    );
  }

  Future<void> verifyEmailChange({required String newEmail, required String code}) async {
    await apiCall(
      () => _authDio
          .post('/api/auth/email/change/verify', data: {'newEmail': newEmail, 'code': code})
          .notifyOnSuccess(rootContext == null ? 'Email updated.' : (AppLocalizations.of(rootContext!)?.email_updated ?? 'Email updated.')),
    );
  }

  Future<void> requestPhoneChange({required String newPhone}) async {
    await apiCall(
      () => _authDio
          .post('/api/auth/otp/change/request', data: {'phoneNumber': newPhone})
          .notifyOnSuccess(
            rootContext == null ? 'Code sent to your new number.' : (AppLocalizations.of(rootContext!)?.code_sent_to_phone ?? 'Code sent to your new number.'),
          ),
    );
  }

  Future<void> verifyPhoneChange({required String newPhone, required String code}) async {
    await apiCall(
      () => _authDio
          .post('/api/auth/otp/change/verify', data: {'phoneNumber': newPhone, 'code': code})
          .notifyOnSuccess(
            rootContext == null ? 'Phone number updated.' : (AppLocalizations.of(rootContext!)?.phone_number_updated ?? 'Phone number updated.'),
          ),
    );
  }
}

final accountControllerProvider = NotifierProvider<AccountController, void>(AccountController.new);
