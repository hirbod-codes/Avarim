import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/l10n/app_localizations.dart';

/// Maps backend `error_code` values to user-facing text.
///
/// This is the one place that needs updating whenever the backend adds a
/// new error_code — everything else (interceptor, UI) is generic and
/// doesn't change. Codes not listed here fall back to a generic message
/// rather than showing the raw code to the user.
Map<String, String Function(AppLocalizations? l10n)> errorCodeMessages = {
  'INVALID_CREDENTIALS': (l10n) => l10n?.error_code_invalid_credentials ?? 'Incorrect email or password.',
  'EMAIL_ALREADY_REGISTERED': (l10n) => l10n?.error_code_email_already_registered ?? 'An account with this email already exists.',
  'OTP_FAILED': (l10n) => l10n?.error_code_otp_failed ?? 'Unfortunately, we failed to send the verification code.',
  'INVALID_OTP': (l10n) => l10n?.error_code_invalid_otp ?? 'That code is incorrect or expired.',
  'INVALID_CODE': (l10n) => l10n?.error_code_invalid_code ?? 'That code is incorrect or expired.',
  'OTP_EXPIRED': (l10n) => l10n?.error_code_otp_expired ?? 'That code has expired. Request a new one.',
  'OTP_RATE_LIMITED': (l10n) => l10n?.error_code_otp_rate_limited ?? 'Too many attempts. Please wait before trying again.',
  'ACCOUNT_NOT_FOUND': (l10n) => l10n?.error_code_account_not_found ?? 'No account found with that email or phone number.',
  'QUOTA_EXCEEDED': (l10n) => l10n?.error_code_quota_exceeded ?? "You've reached your plan's limit for this.",
  'FEATURE_NOT_AVAILABLE': (l10n) => l10n?.error_code_feature_not_available ?? 'This feature requires an upgraded plan.',
  'UNAUTHORIZED': (l10n) => l10n?.error_code_unauthorized ?? 'Your session has expired. Please log in again.',
  'UNSUPPORTED_PAYMENT_METHOD': (l10n) => l10n?.error_code_unsupported_payment_method ?? 'This payment method is not supported.',
  'INTERNAL': (l10n) => l10n?.error_code_internal ?? 'Something went wrong. Please try again.',
  'INTERNAL_ERROR': (l10n) => l10n?.error_code_internal_error ?? 'Something went wrong. Please try again.',
  'PLAN_STATE_INVALID': (l10n) => l10n?.error_code_plan_state_invalid ?? 'The current plan state is invalid.',
  'OTP_COOLDOWN': (l10n) => l10n?.error_code_otp_cooldown ?? 'Please wait before requesting another verification code.',
  'PHONE_REGISTRATION_DISABLED': (l10n) => l10n?.error_code_phone_registration_disabled ?? 'Phone number registration is currently unavailable.',
  'CREATE_FAILED': (l10n) => l10n?.error_code_create_failed ?? 'Failed to create the requested item.',
  'FETCH_FAILED': (l10n) => l10n?.error_code_fetch_failed ?? 'Failed to load the requested data.',
  'EMAIL_REGISTRATION_DISABLED': (l10n) => l10n?.error_code_email_registration_disabled ?? 'Email registration is currently unavailable.',
  'SMTP_COOLDOWN': (l10n) => l10n?.error_code_smtp_cooldown ?? 'Please wait before requesting another email.',
  'INVALID_INPUT': (l10n) => l10n?.error_code_invalid_input ?? 'Some of the provided information is invalid.',
  'EMAIL_NOT_FOUND': (l10n) => l10n?.error_code_email_not_found ?? 'No account was found with this email.',
  'UPDATE_FAILED': (l10n) => l10n?.error_code_update_failed ?? 'Failed to update the requested item.',
  'NO_REFRESH_TOKEN': (l10n) => l10n?.error_code_no_refresh_token ?? 'Your session has expired. Please log in again.',
  'REFRESH_INVALID': (l10n) => l10n?.error_code_refresh_invalid ?? 'Your session has expired. Please log in again.',
  'INVALID_PLAN': (l10n) => l10n?.error_code_invalid_plan ?? 'The selected plan is invalid.',
  'USER_HAS_NO_ACTIVE_PLAN': (l10n) => l10n?.error_code_user_has_no_active_plan ?? 'You do not have an active plan.',
  'PLAN_ALREADY_ACTIVE': (l10n) => l10n?.error_code_plan_already_active ?? 'This plan is already active.',
  'MUST_USE_SAME_PAYMENT_METHOD_AS_PRECIOUS_PLAN': (l10n) =>
      l10n?.error_code_must_use_same_payment_method_as_previous_plan ?? 'You must use the same payment method as your previous plan.',
  'USER_HAS_ACTIVE_PLAN': (l10n) => l10n?.error_code_user_has_active_plan ?? 'You already have an active plan.',
  'UPLOAD_FAILED': (l10n) => l10n?.error_code_upload_failed ?? 'Failed to upload the file.',
  'USER_NOT_FOUND': (l10n) => l10n?.error_code_user_not_found ?? 'User not found.',
  'AVATAR_NOT_FOUND': (l10n) => l10n?.error_code_avatar_not_found ?? 'Avatar not found.',
  'UNAUTHENTICATED': (l10n) => l10n?.error_code_unauthenticated ?? 'Authentication is required. Please log in again.',
  'INVALID_PARENT_TREENODE': (l10n) => l10n?.error_code_invalid_parent_treenode ?? 'The selected parent is invalid.',
  'SUBSCRIPTION_STATE_INVALID': (l10n) => l10n?.error_code_subscription_state_invalid ?? 'The current subscription state is invalid.',
  'INVALID_TREENODE_ID': (l10n) => l10n?.error_code_invalid_treenode_id ?? 'The selected item is invalid.',
  'LEAF_NOT_FOUND': (l10n) => l10n?.error_code_leaf_not_found ?? 'The requested item was not found.',
  'INVALID_PLAN_TITLE': (l10n) => l10n?.error_code_invalid_plan_title ?? 'The plan title is invalid.',
  'SUBSCRIPTION_NOT_FOUND': (l10n) => l10n?.error_code_subscription_not_found ?? 'Subscription not found.',
  'ACTIVE_PLAN_EXPIRED': (l10n) => l10n?.error_code_active_plan_expired ?? 'Your active plan has expired.',
  'ACTIVE_PLAN_CURRENCY_MISMATCH': (l10n) => l10n?.error_code_active_plan_currency_mismatch ?? 'The currency does not match your active plan.',
  'NO_SUBSCRIPTION': (l10n) => l10n?.error_code_no_subscription ?? 'You do not have a subscription.',
  'UUID_NOT_FOUND': (l10n) => l10n?.error_code_uuid_not_found ?? 'The requested item was not found.',
  'INVALID_SUBSCRIPTION_DUE': (l10n) => l10n?.error_code_invalid_subscription_due ?? 'The subscription due date is invalid.',
  'INVALID_PARAMETERS': (l10n) => l10n?.error_code_invalid_parameters ?? 'Some of the provided parameters are invalid.',
  'PLAN_NOT_FOUND': (l10n) => l10n?.error_code_plan_not_found ?? 'Plan not found',
  'PLAN_PAYMENT_METHOD': (l10n) => l10n?.error_code_plan_payment_method ?? 'This payment method is not available for this plan',
  'NO_UPGRADE_OPTIONS': (l10n) => l10n?.error_code_no_upgrade_options ?? 'Each plan renewal must add 3 days to due date or at least one GB to storage',
  'TITLE_NOT_UNIQUE': (l10n) => 'An audio with this title already exists.',
};

String messageForErrorCode(String code) {
  final m = errorCodeMessages[code];
  if (m != null) {
    return m(rootContext == null ? null : AppLocalizations.of(rootContext!));
  } else {
    return 'Something went wrong. Please try again.';
  }
}
