import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de'), Locale('en'), Locale('fa')];

  /// No description provided for @addNew.
  ///
  /// In en, this message translates to:
  /// **'Add new'**
  String get addNew;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Memoize'**
  String get appTitle;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmail;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @changePhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Change phone number'**
  String get changePhoneNumber;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createYourAccount;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get loadMore;

  /// No description provided for @logInOrSignUp.
  ///
  /// In en, this message translates to:
  /// **'Log in or sign up'**
  String get logInOrSignUp;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @logout_success.
  ///
  /// In en, this message translates to:
  /// **'You\'ve Logged out successfully'**
  String get logout_success;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @resendCodeIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String resendCodeIn(int seconds);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email_password.
  ///
  /// In en, this message translates to:
  /// **'Email & password'**
  String get email_password;

  /// No description provided for @update_password.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get update_password;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get plan;

  /// No description provided for @avatar.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get avatar;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @email_required.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get email_required;

  /// No description provided for @enter_valid_email.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enter_valid_email;

  /// No description provided for @account_load_failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your account info.'**
  String get account_load_failed;

  /// No description provided for @verify_your_new_number.
  ///
  /// In en, this message translates to:
  /// **'Verify your new number'**
  String get verify_your_new_number;

  /// No description provided for @enter_code_new_password.
  ///
  /// In en, this message translates to:
  /// **'Enter code & new password'**
  String get enter_code_new_password;

  /// No description provided for @new_password.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get new_password;

  /// No description provided for @at_least_eight_characters.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get at_least_eight_characters;

  /// No description provided for @passwords_not_match.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwords_not_match;

  /// No description provided for @reset_password.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get reset_password;

  /// No description provided for @password_required.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get password_required;

  /// No description provided for @signup_heading.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get signup_heading;

  /// No description provided for @login_heading.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get login_heading;

  /// No description provided for @unauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Unauthenticated.'**
  String get unauthenticated;

  /// No description provided for @video_fetch_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch video data.'**
  String get video_fetch_failed;

  /// No description provided for @video_not_found.
  ///
  /// In en, this message translates to:
  /// **'Video not found.'**
  String get video_not_found;

  /// No description provided for @image_fetch_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch image data.'**
  String get image_fetch_failed;

  /// No description provided for @image_not_found.
  ///
  /// In en, this message translates to:
  /// **'Image not found.'**
  String get image_not_found;

  /// No description provided for @audio_fetch_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch audio data.'**
  String get audio_fetch_failed;

  /// No description provided for @audio_not_found.
  ///
  /// In en, this message translates to:
  /// **'Audio not found.'**
  String get audio_not_found;

  /// No description provided for @choose_new_account.
  ///
  /// In en, this message translates to:
  /// **'Choose new account'**
  String get choose_new_account;

  /// No description provided for @tts_failed_to_play_pronunciation.
  ///
  /// In en, this message translates to:
  /// **'Failed to play pronunciation'**
  String get tts_failed_to_play_pronunciation;

  /// No description provided for @tts_hear_pronunciation.
  ///
  /// In en, this message translates to:
  /// **'Hear pronunciation'**
  String get tts_hear_pronunciation;

  /// No description provided for @text_editor_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Start writing your notes...'**
  String get text_editor_placeholder;

  /// No description provided for @option.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get option;

  /// No description provided for @choose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get choose;

  /// No description provided for @auth_page_checking_sign_in_methods_failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check available sign-in methods.'**
  String get auth_page_checking_sign_in_methods_failed;

  /// No description provided for @auth_page_sign_in_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is temporarily unavailable. Please try again shortly.'**
  String get auth_page_sign_in_unavailable;

  /// No description provided for @forgot_password_email_sheet_heading.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a 6-digit code.'**
  String get forgot_password_email_sheet_heading;

  /// No description provided for @phone_otp_form_heading.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a code — no password needed. New number? We\'ll set up your account automatically.'**
  String get phone_otp_form_heading;

  /// No description provided for @change_phone_sheet.
  ///
  /// In en, this message translates to:
  /// **'Change phone number'**
  String get change_phone_sheet;

  /// No description provided for @change_phone_sheet_code_sent_confirm.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text a code to your new number to confirm it.'**
  String get change_phone_sheet_code_sent_confirm;

  /// No description provided for @change_phone_sheet_new_phone_number.
  ///
  /// In en, this message translates to:
  /// **'New phone number'**
  String get change_phone_sheet_new_phone_number;

  /// No description provided for @change_phone_sheet_phone_number_required.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get change_phone_sheet_phone_number_required;

  /// No description provided for @change_password_sheet.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get change_password_sheet;

  /// No description provided for @change_password_sheet_current_password.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get change_password_sheet_current_password;

  /// No description provided for @change_password_sheet_new_password.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get change_password_sheet_new_password;

  /// No description provided for @change_password_sheet_confirm_new_password.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get change_password_sheet_confirm_new_password;

  /// No description provided for @change_email_sheet.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get change_email_sheet;

  /// No description provided for @change_email_sheet_code_sent_confirm.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a code to your new address to confirm it.'**
  String get change_email_sheet_code_sent_confirm;

  /// No description provided for @change_email_sheet_new_email.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get change_email_sheet_new_email;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @$continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get $continue;

  /// No description provided for @moveHere.
  ///
  /// In en, this message translates to:
  /// **'Move here'**
  String get moveHere;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @uncaughtError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get uncaughtError;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @contentTypes.
  ///
  /// In en, this message translates to:
  /// **'Content types'**
  String get contentTypes;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'storage'**
  String get storage;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @texts.
  ///
  /// In en, this message translates to:
  /// **'Texts'**
  String get texts;

  /// No description provided for @richText.
  ///
  /// In en, this message translates to:
  /// **'Rich text'**
  String get richText;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @audios.
  ///
  /// In en, this message translates to:
  /// **'Audios'**
  String get audios;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @message_choose_language.
  ///
  /// In en, this message translates to:
  /// **'Choose your language and calendar to get started. You can change these later in Settings.'**
  String get message_choose_language;

  /// No description provided for @system_failed.
  ///
  /// In en, this message translates to:
  /// **'system failed to set new language, try again.'**
  String get system_failed;

  /// No description provided for @errors_page_not_found.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that page.'**
  String get errors_page_not_found;

  /// No description provided for @errors_page_path_not_found.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find \"{path}\".'**
  String errors_page_path_not_found(String path);

  /// No description provided for @choose_your_language.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get choose_your_language;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @go_home.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get go_home;

  /// No description provided for @verify_your_email.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verify_your_email;

  /// No description provided for @verify_your_new_email.
  ///
  /// In en, this message translates to:
  /// **'Verify your new email'**
  String get verify_your_new_email;

  /// No description provided for @welcome_to_memoize.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Memoize'**
  String get welcome_to_memoize;

  /// No description provided for @login_success.
  ///
  /// In en, this message translates to:
  /// **'You\'re logged in!'**
  String get login_success;

  /// No description provided for @code_sent_to_phone.
  ///
  /// In en, this message translates to:
  /// **'Code sent to your phone.'**
  String get code_sent_to_phone;

  /// No description provided for @email_updated.
  ///
  /// In en, this message translates to:
  /// **'Email updated.'**
  String get email_updated;

  /// No description provided for @phone_number_updated.
  ///
  /// In en, this message translates to:
  /// **'Phone number updated.'**
  String get phone_number_updated;

  /// No description provided for @password_updated.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully.'**
  String get password_updated;

  /// No description provided for @account_created.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set! Account created.'**
  String get account_created;

  /// No description provided for @code_sent_to_email.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to your email.'**
  String get code_sent_to_email;

  /// No description provided for @request_timeout.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Check your connection and try again.'**
  String get request_timeout;

  /// No description provided for @request_connection_error.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection.'**
  String get request_connection_error;

  /// No description provided for @request_cancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get request_cancelled;

  /// No description provided for @error_code_invalid_credentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get error_code_invalid_credentials;

  /// No description provided for @error_code_email_already_registered.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get error_code_email_already_registered;

  /// No description provided for @error_code_otp_failed.
  ///
  /// In en, this message translates to:
  /// **'unfortunately, we failed to send verification code.'**
  String get error_code_otp_failed;

  /// No description provided for @error_code_invalid_otp.
  ///
  /// In en, this message translates to:
  /// **'That code is incorrect or expired.'**
  String get error_code_invalid_otp;

  /// No description provided for @error_code_invalid_code.
  ///
  /// In en, this message translates to:
  /// **'That code is incorrect or expired.'**
  String get error_code_invalid_code;

  /// No description provided for @error_code_otp_expired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Request a new one.'**
  String get error_code_otp_expired;

  /// No description provided for @error_code_otp_rate_limited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait before trying again.'**
  String get error_code_otp_rate_limited;

  /// No description provided for @error_code_account_not_found.
  ///
  /// In en, this message translates to:
  /// **'No account found with that email or phone number.'**
  String get error_code_account_not_found;

  /// No description provided for @error_code_quota_exceeded.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached your plan\'s limit for this.'**
  String get error_code_quota_exceeded;

  /// No description provided for @error_code_feature_not_available.
  ///
  /// In en, this message translates to:
  /// **'This feature requires an upgraded plan.'**
  String get error_code_feature_not_available;

  /// No description provided for @error_code_unauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get error_code_unauthorized;

  /// No description provided for @timeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get timeZone;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @cards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get cards;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @cancelMove.
  ///
  /// In en, this message translates to:
  /// **'Cancel move'**
  String get cancelMove;

  /// No description provided for @title_about_us.
  ///
  /// In en, this message translates to:
  /// **'About Us'**
  String get title_about_us;

  /// No description provided for @title_contact_us.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get title_contact_us;

  /// No description provided for @title_pricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get title_pricing;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @flip.
  ///
  /// In en, this message translates to:
  /// **'Flip'**
  String get flip;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @add_content.
  ///
  /// In en, this message translates to:
  /// **'Add content'**
  String get add_content;

  /// No description provided for @file_manager_content_delete_dialog_heading.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?\nthis action is irreversible!'**
  String get file_manager_content_delete_dialog_heading;

  /// No description provided for @landing_page_get_started_free.
  ///
  /// In en, this message translates to:
  /// **'Get started free'**
  String get landing_page_get_started_free;

  /// No description provided for @landing_page_see_pricing.
  ///
  /// In en, this message translates to:
  /// **'See pricing'**
  String get landing_page_see_pricing;

  /// No description provided for @landing_page_how_it_works.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get landing_page_how_it_works;

  /// No description provided for @landing_page_memorize_anything.
  ///
  /// In en, this message translates to:
  /// **'MEMORIZE ANYTHING'**
  String get landing_page_memorize_anything;

  /// No description provided for @landing_page_hero_title.
  ///
  /// In en, this message translates to:
  /// **'Turn your own material into flashcards you actually remember'**
  String get landing_page_hero_title;

  /// No description provided for @landing_page_hero_secondary.
  ///
  /// In en, this message translates to:
  /// **'Upload text, images, audio, or video — organize it however makes sense to you — and review it whenever you have a few minutes.'**
  String get landing_page_hero_secondary;

  /// No description provided for @landing_page_upload_your_content.
  ///
  /// In en, this message translates to:
  /// **'Upload your content'**
  String get landing_page_upload_your_content;

  /// No description provided for @landing_page_upload_your_content_description.
  ///
  /// In en, this message translates to:
  /// **'Text, images, audio, or video — right onto either side of a card.'**
  String get landing_page_upload_your_content_description;

  /// No description provided for @landing_page_organize_id_your_way.
  ///
  /// In en, this message translates to:
  /// **'Organize it your way'**
  String get landing_page_organize_id_your_way;

  /// No description provided for @landing_page_organize_id_your_way_description.
  ///
  /// In en, this message translates to:
  /// **'Nest categories as deep as you need — by subject, by chapter, by whatever makes sense to you.'**
  String get landing_page_organize_id_your_way_description;

  /// No description provided for @landing_page_come_back_review.
  ///
  /// In en, this message translates to:
  /// **'Come back and review'**
  String get landing_page_come_back_review;

  /// No description provided for @landing_page_come_back_review_description.
  ///
  /// In en, this message translates to:
  /// **'Work through your cards whenever you have a few spare minutes.'**
  String get landing_page_come_back_review_description;

  /// No description provided for @landing_page_content_type.
  ///
  /// In en, this message translates to:
  /// **'Any kind of content, on either side of a card'**
  String get landing_page_content_type;

  /// No description provided for @landing_page_content_type_description.
  ///
  /// In en, this message translates to:
  /// **'A vocabulary word with its pronunciation. A diagram next to your own explanation. It\'s your material — Memoize doesn\'t limit how you represent it.'**
  String get landing_page_content_type_description;

  /// No description provided for @landing_page_use_case_first_title.
  ///
  /// In en, this message translates to:
  /// **'Learning a new language'**
  String get landing_page_use_case_first_title;

  /// No description provided for @landing_page_use_case_first_description.
  ///
  /// In en, this message translates to:
  /// **'Pair a word with an audio clip of its pronunciation and a picture instead of just a translation — build cards the way you actually think about the word.'**
  String get landing_page_use_case_first_description;

  /// No description provided for @landing_page_use_case_second_title.
  ///
  /// In en, this message translates to:
  /// **'Studying for an exam'**
  String get landing_page_use_case_second_title;

  /// No description provided for @landing_page_use_case_second_description.
  ///
  /// In en, this message translates to:
  /// **'Turn lecture slides, diagrams, and your own notes into cards organized by subject and chapter, nested exactly the way your course is structured.'**
  String get landing_page_use_case_second_description;

  /// No description provided for @landing_page_final_cta.
  ///
  /// In en, this message translates to:
  /// **'Ready to remember more?'**
  String get landing_page_final_cta;

  /// No description provided for @pricing_page_could_not_load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load pricing right now.'**
  String get pricing_page_could_not_load;

  /// No description provided for @pricing_page_no_plan_available.
  ///
  /// In en, this message translates to:
  /// **'No plans are available right now.'**
  String get pricing_page_no_plan_available;

  /// No description provided for @pricing_page_choose_plan.
  ///
  /// In en, this message translates to:
  /// **'Choose your plan'**
  String get pricing_page_choose_plan;

  /// No description provided for @pricing_page_choose_plan_description.
  ///
  /// In en, this message translates to:
  /// **'Pick the plan that fits how you use Memoize.'**
  String get pricing_page_choose_plan_description;

  /// No description provided for @pricing_page_levels_of_nesting.
  ///
  /// In en, this message translates to:
  /// **'levels of nesting'**
  String get pricing_page_levels_of_nesting;

  /// No description provided for @pricing_page_cards_per_category.
  ///
  /// In en, this message translates to:
  /// **'cards per category'**
  String get pricing_page_cards_per_category;

  /// No description provided for @pricing_page_contents_per_card_side.
  ///
  /// In en, this message translates to:
  /// **'contents per card side'**
  String get pricing_page_contents_per_card_side;

  /// No description provided for @pricing_page_get_started.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get pricing_page_get_started;

  /// No description provided for @avatar_upload_success.
  ///
  /// In en, this message translates to:
  /// **'Avatar image successfully uploaded'**
  String get avatar_upload_success;

  /// No description provided for @upload_video.
  ///
  /// In en, this message translates to:
  /// **'Upload video'**
  String get upload_video;

  /// No description provided for @video_not_selected.
  ///
  /// In en, this message translates to:
  /// **'No video selected'**
  String get video_not_selected;

  /// No description provided for @upload_image.
  ///
  /// In en, this message translates to:
  /// **'Upload image'**
  String get upload_image;

  /// No description provided for @image_not_selected.
  ///
  /// In en, this message translates to:
  /// **'No image selected'**
  String get image_not_selected;

  /// No description provided for @upload_audio.
  ///
  /// In en, this message translates to:
  /// **'Upload audio'**
  String get upload_audio;

  /// No description provided for @audio_not_selected.
  ///
  /// In en, this message translates to:
  /// **'No audio selected'**
  String get audio_not_selected;

  /// No description provided for @choose_audio.
  ///
  /// In en, this message translates to:
  /// **'Choose audio'**
  String get choose_audio;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @otp_sheet_heading.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to {destination}'**
  String otp_sheet_heading(String destination);

  /// No description provided for @no_image_selected.
  ///
  /// In en, this message translates to:
  /// **'No image selected'**
  String get no_image_selected;

  /// No description provided for @folder_add_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully added new folder.'**
  String get folder_add_success;

  /// No description provided for @folder_add_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to add new folder.'**
  String get folder_add_failed;

  /// No description provided for @folder_move_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully moved the folder.'**
  String get folder_move_success;

  /// No description provided for @folder_move_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to move the folder.'**
  String get folder_move_failed;

  /// No description provided for @folders_not_found.
  ///
  /// In en, this message translates to:
  /// **'Folders not found!'**
  String get folders_not_found;

  /// No description provided for @folder_not_found.
  ///
  /// In en, this message translates to:
  /// **'No folder found!'**
  String get folder_not_found;

  /// No description provided for @folder_set_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully updated folder.'**
  String get folder_set_success;

  /// No description provided for @folder_set_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to update folder.'**
  String get folder_set_failed;

  /// No description provided for @folder_remove_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully removed folder.'**
  String get folder_remove_success;

  /// No description provided for @folder_remove_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to remove folder.'**
  String get folder_remove_failed;

  /// No description provided for @file_add_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully added new file.'**
  String get file_add_success;

  /// No description provided for @file_add_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to add new file.'**
  String get file_add_failed;

  /// No description provided for @files_not_found.
  ///
  /// In en, this message translates to:
  /// **'Files not found!'**
  String get files_not_found;

  /// No description provided for @file_not_found.
  ///
  /// In en, this message translates to:
  /// **'No file found!'**
  String get file_not_found;

  /// No description provided for @file_set_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully updated file.'**
  String get file_set_success;

  /// No description provided for @file_set_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to update file.'**
  String get file_set_failed;

  /// No description provided for @file_remove_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully removed file.'**
  String get file_remove_success;

  /// No description provided for @file_remove_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to remove file.'**
  String get file_remove_failed;

  /// No description provided for @file_move_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully moved the file.'**
  String get file_move_success;

  /// No description provided for @file_move_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to move the file.'**
  String get file_move_failed;

  /// No description provided for @content_set_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully updated content.'**
  String get content_set_success;

  /// No description provided for @content_set_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to update content.'**
  String get content_set_failed;

  /// No description provided for @content_add_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully added content.'**
  String get content_add_success;

  /// No description provided for @content_add_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to add content.'**
  String get content_add_failed;

  /// No description provided for @content_remove_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully removed content.'**
  String get content_remove_success;

  /// No description provided for @content_remove_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to remove content.'**
  String get content_remove_failed;

  /// No description provided for @content_value_set_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully updated content.'**
  String get content_value_set_success;

  /// No description provided for @content_value_set_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to update content.'**
  String get content_value_set_failed;

  /// No description provided for @content_value_add_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully added content.'**
  String get content_value_add_success;

  /// No description provided for @content_value_add_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to add content.'**
  String get content_value_add_failed;

  /// No description provided for @content_value_remove_success.
  ///
  /// In en, this message translates to:
  /// **'Successfully removed content.'**
  String get content_value_remove_success;

  /// No description provided for @content_value_remove_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to remove content.'**
  String get content_value_remove_failed;

  /// No description provided for @content_move_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to move content.'**
  String get content_move_failed;

  /// No description provided for @content_not_found.
  ///
  /// In en, this message translates to:
  /// **'No content found!'**
  String get content_not_found;

  /// No description provided for @app_page_file_pagination_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to load cards'**
  String get app_page_file_pagination_failed;

  /// No description provided for @app_page_folder_pagination_failed.
  ///
  /// In en, this message translates to:
  /// **'Failure while trying to load categories'**
  String get app_page_folder_pagination_failed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @payment_result_checking.
  ///
  /// In en, this message translates to:
  /// **'Checking payment...'**
  String get payment_result_checking;

  /// No description provided for @checking_plan.
  ///
  /// In en, this message translates to:
  /// **'Checking your plan...'**
  String get checking_plan;

  /// No description provided for @plan_check_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check your plan.'**
  String get plan_check_failed;

  /// No description provided for @payment_result_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get payment_result_continue;

  /// No description provided for @payment_result_success_title.
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get payment_result_success_title;

  /// No description provided for @payment_result_error_title.
  ///
  /// In en, this message translates to:
  /// **'Payment Failed'**
  String get payment_result_error_title;

  /// No description provided for @payment_result_success_message.
  ///
  /// In en, this message translates to:
  /// **'Your payment was completed successfully.'**
  String get payment_result_success_message;

  /// No description provided for @payment_result_error_message.
  ///
  /// In en, this message translates to:
  /// **'Your payment could not be completed.'**
  String get payment_result_error_message;

  /// No description provided for @checkout_title.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout_title;

  /// No description provided for @checkout_payment_method.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get checkout_payment_method;

  /// No description provided for @checkout_duration_month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get checkout_duration_month;

  /// No description provided for @checkout_duration_year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get checkout_duration_year;

  /// No description provided for @checkout_total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get checkout_total;

  /// No description provided for @checkout_pay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get checkout_pay;

  /// No description provided for @checkout_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get checkout_cancel;

  /// No description provided for @checkout_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get checkout_retry;

  /// No description provided for @checkout_no_methods.
  ///
  /// In en, this message translates to:
  /// **'No payment methods available.'**
  String get checkout_no_methods;

  /// No description provided for @checkout_load_methods_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load payment methods.'**
  String get checkout_load_methods_failed;

  /// No description provided for @checkout_select_method.
  ///
  /// In en, this message translates to:
  /// **'Select a payment method.'**
  String get checkout_select_method;

  /// No description provided for @checkout_pay_failed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed.'**
  String get checkout_pay_failed;

  /// No description provided for @limit_reached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached a limit on your current plan. Upgrade to keep going.'**
  String get limit_reached;

  /// No description provided for @upgrade_required.
  ///
  /// In en, this message translates to:
  /// **'Upgrade required'**
  String get upgrade_required;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @sentence.
  ///
  /// In en, this message translates to:
  /// **'sentence'**
  String get sentence;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @avatar_delete_success.
  ///
  /// In en, this message translates to:
  /// **'successfully removed user \'s avatar'**
  String get avatar_delete_success;

  /// No description provided for @remove_subscription.
  ///
  /// In en, this message translates to:
  /// **'Remove subscription'**
  String get remove_subscription;

  /// No description provided for @subscription_delete_success.
  ///
  /// In en, this message translates to:
  /// **'Subscription removed successfully.'**
  String get subscription_delete_success;

  /// No description provided for @storage_usage.
  ///
  /// In en, this message translates to:
  /// **'Storage usage'**
  String get storage_usage;

  /// No description provided for @add_storage.
  ///
  /// In en, this message translates to:
  /// **'Add storage'**
  String get add_storage;

  /// No description provided for @continue_to_payment.
  ///
  /// In en, this message translates to:
  /// **'Continue to payment'**
  String get continue_to_payment;

  /// No description provided for @renewal.
  ///
  /// In en, this message translates to:
  /// **'Renewal'**
  String get renewal;

  /// No description provided for @please_fill_inputs_correctly.
  ///
  /// In en, this message translates to:
  /// **'Please fill in the inputs correctly'**
  String get please_fill_inputs_correctly;

  /// No description provided for @checkout_additional_storage.
  ///
  /// In en, this message translates to:
  /// **'Additional Storage'**
  String get checkout_additional_storage;

  /// No description provided for @checkout_storage_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid storage value'**
  String get checkout_storage_invalid;

  /// No description provided for @checkout_days_suffix.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get checkout_days_suffix;

  /// No description provided for @checkout_duration_days.
  ///
  /// In en, this message translates to:
  /// **'Plan duration in days'**
  String get checkout_duration_days;

  /// No description provided for @checkout_duration_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid days value'**
  String get checkout_duration_invalid;

  /// No description provided for @error_code_unsupported_payment_method.
  ///
  /// In en, this message translates to:
  /// **'This payment method is not supported.'**
  String get error_code_unsupported_payment_method;

  /// No description provided for @error_code_internal.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get error_code_internal;

  /// No description provided for @error_code_internal_error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get error_code_internal_error;

  /// No description provided for @error_code_plan_state_invalid.
  ///
  /// In en, this message translates to:
  /// **'The current plan state is invalid.'**
  String get error_code_plan_state_invalid;

  /// No description provided for @error_code_otp_cooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait before requesting another verification code.'**
  String get error_code_otp_cooldown;

  /// No description provided for @error_code_phone_registration_disabled.
  ///
  /// In en, this message translates to:
  /// **'Phone number registration is currently unavailable.'**
  String get error_code_phone_registration_disabled;

  /// No description provided for @error_code_create_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the requested item.'**
  String get error_code_create_failed;

  /// No description provided for @error_code_fetch_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the requested data.'**
  String get error_code_fetch_failed;

  /// No description provided for @error_code_email_registration_disabled.
  ///
  /// In en, this message translates to:
  /// **'Email registration is currently unavailable.'**
  String get error_code_email_registration_disabled;

  /// No description provided for @error_code_smtp_cooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait before requesting another email.'**
  String get error_code_smtp_cooldown;

  /// No description provided for @error_code_invalid_input.
  ///
  /// In en, this message translates to:
  /// **'Some of the provided information is invalid.'**
  String get error_code_invalid_input;

  /// No description provided for @error_code_email_not_found.
  ///
  /// In en, this message translates to:
  /// **'No account was found with this email.'**
  String get error_code_email_not_found;

  /// No description provided for @error_code_update_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update the requested item.'**
  String get error_code_update_failed;

  /// No description provided for @error_code_no_refresh_token.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get error_code_no_refresh_token;

  /// No description provided for @error_code_refresh_invalid.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please log in again.'**
  String get error_code_refresh_invalid;

  /// No description provided for @error_code_invalid_plan.
  ///
  /// In en, this message translates to:
  /// **'The selected plan is invalid.'**
  String get error_code_invalid_plan;

  /// No description provided for @error_code_user_has_no_active_plan.
  ///
  /// In en, this message translates to:
  /// **'You do not have an active plan.'**
  String get error_code_user_has_no_active_plan;

  /// No description provided for @error_code_plan_already_active.
  ///
  /// In en, this message translates to:
  /// **'This plan is already active.'**
  String get error_code_plan_already_active;

  /// No description provided for @error_code_must_use_same_payment_method_as_previous_plan.
  ///
  /// In en, this message translates to:
  /// **'You must use the same payment method as your previous plan.'**
  String get error_code_must_use_same_payment_method_as_previous_plan;

  /// No description provided for @error_code_user_has_active_plan.
  ///
  /// In en, this message translates to:
  /// **'You already have an active plan.'**
  String get error_code_user_has_active_plan;

  /// No description provided for @error_code_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload the file.'**
  String get error_code_upload_failed;

  /// No description provided for @error_code_user_not_found.
  ///
  /// In en, this message translates to:
  /// **'User not found.'**
  String get error_code_user_not_found;

  /// No description provided for @error_code_avatar_not_found.
  ///
  /// In en, this message translates to:
  /// **'Avatar not found.'**
  String get error_code_avatar_not_found;

  /// No description provided for @error_code_unauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Authentication is required. Please log in again.'**
  String get error_code_unauthenticated;

  /// No description provided for @error_code_invalid_parent_treenode.
  ///
  /// In en, this message translates to:
  /// **'The selected parent is invalid.'**
  String get error_code_invalid_parent_treenode;

  /// No description provided for @error_code_subscription_state_invalid.
  ///
  /// In en, this message translates to:
  /// **'The current subscription state is invalid.'**
  String get error_code_subscription_state_invalid;

  /// No description provided for @error_code_invalid_treenode_id.
  ///
  /// In en, this message translates to:
  /// **'The selected item is invalid.'**
  String get error_code_invalid_treenode_id;

  /// No description provided for @error_code_leaf_not_found.
  ///
  /// In en, this message translates to:
  /// **'The requested item was not found.'**
  String get error_code_leaf_not_found;

  /// No description provided for @error_code_invalid_plan_title.
  ///
  /// In en, this message translates to:
  /// **'The plan title is invalid.'**
  String get error_code_invalid_plan_title;

  /// No description provided for @error_code_subscription_not_found.
  ///
  /// In en, this message translates to:
  /// **'Subscription not found.'**
  String get error_code_subscription_not_found;

  /// No description provided for @error_code_active_plan_expired.
  ///
  /// In en, this message translates to:
  /// **'Your active plan has expired.'**
  String get error_code_active_plan_expired;

  /// No description provided for @error_code_active_plan_currency_mismatch.
  ///
  /// In en, this message translates to:
  /// **'The currency does not match your active plan.'**
  String get error_code_active_plan_currency_mismatch;

  /// No description provided for @error_code_no_subscription.
  ///
  /// In en, this message translates to:
  /// **'You do not have a subscription.'**
  String get error_code_no_subscription;

  /// No description provided for @error_code_uuid_not_found.
  ///
  /// In en, this message translates to:
  /// **'The requested item was not found.'**
  String get error_code_uuid_not_found;

  /// No description provided for @error_code_invalid_subscription_due.
  ///
  /// In en, this message translates to:
  /// **'The subscription due date is invalid.'**
  String get error_code_invalid_subscription_due;

  /// No description provided for @error_code_invalid_parameters.
  ///
  /// In en, this message translates to:
  /// **'Some of the provided parameters are invalid.'**
  String get error_code_invalid_parameters;

  /// No description provided for @calculate_price.
  ///
  /// In en, this message translates to:
  /// **'Calculate Price'**
  String get calculate_price;

  /// No description provided for @error_code_plan_not_found.
  ///
  /// In en, this message translates to:
  /// **'Plan not found'**
  String get error_code_plan_not_found;

  /// No description provided for @error_code_plan_payment_method.
  ///
  /// In en, this message translates to:
  /// **'This payment method is not available for this plan'**
  String get error_code_plan_payment_method;

  /// No description provided for @error_code_no_upgrade_options.
  ///
  /// In en, this message translates to:
  /// **'Each plan renewal must add at least 3 days to the due date or 1 GB to storage'**
  String get error_code_no_upgrade_options;

  /// No description provided for @checkout_upgrade_requirement_title.
  ///
  /// In en, this message translates to:
  /// **'At least one of the following must be satisfied:'**
  String get checkout_upgrade_requirement_title;

  /// No description provided for @checkout_upgrade_duration_requirement.
  ///
  /// In en, this message translates to:
  /// **'Plan duration must be changed by more than 3 days.'**
  String get checkout_upgrade_duration_requirement;

  /// No description provided for @checkout_upgrade_storage_requirement.
  ///
  /// In en, this message translates to:
  /// **'Storage must be changed by more than 10 GB.'**
  String get checkout_upgrade_storage_requirement;

  /// No description provided for @checkout_free_purchase_message.
  ///
  /// In en, this message translates to:
  /// **'This purchase is free for you. The remaining balance will be saved for future purchases.'**
  String get checkout_free_purchase_message;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
