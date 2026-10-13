// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addNew => 'Add new';

  @override
  String get appTitle => 'Memoize';

  @override
  String get changeEmail => 'Change email';

  @override
  String get changePassword => 'Change password';

  @override
  String get changePhoneNumber => 'Change phone number';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get email => 'Email';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get getStarted => 'Get started';

  @override
  String get language => 'Language';

  @override
  String get loadMore => 'Load More';

  @override
  String get logInOrSignUp => 'Log in or sign up';

  @override
  String get signUp => 'Sign up';

  @override
  String get login => 'Log in';

  @override
  String get logout => 'Log out';

  @override
  String get logout_success => 'You\'ve Logged out successfully';

  @override
  String get password => 'Password';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phone => 'Phone';

  @override
  String get sendCode => 'Send code';

  @override
  String get resendCode => 'Resend code';

  @override
  String resendCodeIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get verify => 'Verify';

  @override
  String get username => 'Username';

  @override
  String get email_password => 'Email & password';

  @override
  String get update_password => 'Update password';

  @override
  String get account => 'Account';

  @override
  String get plan => 'Plan';

  @override
  String get avatar => 'Avatar';

  @override
  String get update => 'Update';

  @override
  String get email_required => 'Email is required';

  @override
  String get enter_valid_email => 'Enter a valid email';

  @override
  String get account_load_failed => 'Couldn\'t load your account info.';

  @override
  String get verify_your_new_number => 'Verify your new number';

  @override
  String get enter_code_new_password => 'Enter code & new password';

  @override
  String get new_password => 'New password';

  @override
  String get at_least_eight_characters => 'At least 8 characters';

  @override
  String get passwords_not_match => 'Passwords do not match';

  @override
  String get reset_password => 'Reset password';

  @override
  String get password_required => 'Password is required';

  @override
  String get signup_heading => 'Don\'t have an account? Sign up';

  @override
  String get login_heading => 'Already have an account? Log in';

  @override
  String get unauthenticated => 'Unauthenticated.';

  @override
  String get video_fetch_failed => 'Failed to fetch video data.';

  @override
  String get video_not_found => 'Video not found.';

  @override
  String get image_fetch_failed => 'Failed to fetch image data.';

  @override
  String get image_not_found => 'Image not found.';

  @override
  String get audio_fetch_failed => 'Failed to fetch audio data.';

  @override
  String get audio_not_found => 'Audio not found.';

  @override
  String get choose_new_account => 'Choose new account';

  @override
  String get tts_failed_to_play_pronunciation => 'Failed to play pronunciation';

  @override
  String get tts_hear_pronunciation => 'Hear pronunciation';

  @override
  String get text_editor_placeholder => 'Start writing your notes...';

  @override
  String get option => 'Option';

  @override
  String get choose => 'Choose';

  @override
  String get auth_page_checking_sign_in_methods_failed => 'Couldn\'t check available sign-in methods.';

  @override
  String get auth_page_sign_in_unavailable => 'Sign-in is temporarily unavailable. Please try again shortly.';

  @override
  String get forgot_password_email_sheet_heading => 'Enter your email and we\'ll send you a 6-digit code.';

  @override
  String get phone_otp_form_heading => 'We\'ll text you a code — no password needed. New number? We\'ll set up your account automatically.';

  @override
  String get change_phone_sheet => 'Change phone number';

  @override
  String get change_phone_sheet_code_sent_confirm => 'We\'ll text a code to your new number to confirm it.';

  @override
  String get change_phone_sheet_new_phone_number => 'New phone number';

  @override
  String get change_phone_sheet_phone_number_required => 'Phone number is required';

  @override
  String get change_password_sheet => 'Change password';

  @override
  String get change_password_sheet_current_password => 'Current password';

  @override
  String get change_password_sheet_new_password => 'New password';

  @override
  String get change_password_sheet_confirm_new_password => 'Confirm new password';

  @override
  String get change_email_sheet => 'Change email';

  @override
  String get change_email_sheet_code_sent_confirm => 'We\'ll send a code to your new address to confirm it.';

  @override
  String get change_email_sheet_new_email => 'New email';

  @override
  String get change => 'Change';

  @override
  String get cancel => 'Cancel';

  @override
  String get move => 'Move';

  @override
  String get $continue => 'Continue';

  @override
  String get moveHere => 'Move here';

  @override
  String get gallery => 'Gallery';

  @override
  String get camera => 'Camera';

  @override
  String get upload => 'Upload';

  @override
  String get uncaughtError => 'Something went wrong.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get contentTypes => 'Content types';

  @override
  String get storage => 'storage';

  @override
  String get text => 'Text';

  @override
  String get texts => 'Texts';

  @override
  String get richText => 'Rich text';

  @override
  String get images => 'Images';

  @override
  String get image => 'Image';

  @override
  String get audio => 'Audio';

  @override
  String get audios => 'Audios';

  @override
  String get video => 'Video';

  @override
  String get videos => 'Videos';

  @override
  String get message_choose_language => 'Choose your language and calendar to get started. You can change these later in Settings.';

  @override
  String get system_failed => 'system failed to set new language, try again.';

  @override
  String get errors_page_not_found => 'We couldn\'t find that page.';

  @override
  String errors_page_path_not_found(String path) {
    return 'We couldn\'t find \"$path\".';
  }

  @override
  String get choose_your_language => 'Choose your language';

  @override
  String get required => 'Required';

  @override
  String get go_home => 'Go home';

  @override
  String get verify_your_email => 'Verify your email';

  @override
  String get verify_your_new_email => 'Verify your new email';

  @override
  String get welcome_to_memoize => 'Welcome to Memoize';

  @override
  String get login_success => 'You\'re logged in!';

  @override
  String get code_sent_to_phone => 'Code sent to your phone.';

  @override
  String get email_updated => 'Email updated.';

  @override
  String get phone_number_updated => 'Phone number updated.';

  @override
  String get password_updated => 'Password updated successfully.';

  @override
  String get account_created => 'You\'re all set! Account created.';

  @override
  String get code_sent_to_email => 'Verification code sent to your email.';

  @override
  String get request_timeout => 'The request timed out. Check your connection and try again.';

  @override
  String get request_connection_error => 'Could not reach the server. Check your connection.';

  @override
  String get request_cancelled => 'Request cancelled.';

  @override
  String get error_code_invalid_credentials => 'Incorrect email or password.';

  @override
  String get error_code_email_already_registered => 'An account with this email already exists.';

  @override
  String get error_code_otp_failed => 'unfortunately, we failed to send verification code.';

  @override
  String get error_code_invalid_otp => 'That code is incorrect or expired.';

  @override
  String get error_code_invalid_code => 'That code is incorrect or expired.';

  @override
  String get error_code_otp_expired => 'That code has expired. Request a new one.';

  @override
  String get error_code_otp_rate_limited => 'Too many attempts. Please wait before trying again.';

  @override
  String get error_code_account_not_found => 'No account found with that email or phone number.';

  @override
  String get error_code_quota_exceeded => 'You\'ve reached your plan\'s limit for this.';

  @override
  String get error_code_feature_not_available => 'This feature requires an upgraded plan.';

  @override
  String get error_code_unauthorized => 'Your session has expired. Please log in again.';

  @override
  String get timeZone => 'Time zone';

  @override
  String get calendar => 'Calendar';

  @override
  String get card => 'Card';

  @override
  String get cards => 'Cards';

  @override
  String get categories => 'Categories';

  @override
  String get category => 'Category';

  @override
  String get cancelMove => 'Cancel move';

  @override
  String get title_about_us => 'About Us';

  @override
  String get title_contact_us => 'Contact Us';

  @override
  String get title_pricing => 'Pricing';

  @override
  String get no => 'No';

  @override
  String get yes => 'Yes';

  @override
  String get flip => 'Flip';

  @override
  String get title => 'Title';

  @override
  String get add_content => 'Add content';

  @override
  String get file_manager_content_delete_dialog_heading => 'Are you sure?\nthis action is irreversible!';

  @override
  String get landing_page_get_started_free => 'Get started free';

  @override
  String get landing_page_see_pricing => 'See pricing';

  @override
  String get landing_page_how_it_works => 'How it works';

  @override
  String get landing_page_memorize_anything => 'MEMORIZE ANYTHING';

  @override
  String get landing_page_hero_title => 'Turn your own material into flashcards you actually remember';

  @override
  String get landing_page_hero_secondary =>
      'Upload text, images, audio, or video — organize it however makes sense to you — and review it whenever you have a few minutes.';

  @override
  String get landing_page_upload_your_content => 'Upload your content';

  @override
  String get landing_page_upload_your_content_description => 'Text, images, audio, or video — right onto either side of a card.';

  @override
  String get landing_page_organize_id_your_way => 'Organize it your way';

  @override
  String get landing_page_organize_id_your_way_description => 'Nest categories as deep as you need — by subject, by chapter, by whatever makes sense to you.';

  @override
  String get landing_page_come_back_review => 'Come back and review';

  @override
  String get landing_page_come_back_review_description => 'Work through your cards whenever you have a few spare minutes.';

  @override
  String get landing_page_content_type => 'Any kind of content, on either side of a card';

  @override
  String get landing_page_content_type_description =>
      'A vocabulary word with its pronunciation. A diagram next to your own explanation. It\'s your material — Memoize doesn\'t limit how you represent it.';

  @override
  String get landing_page_use_case_first_title => 'Learning a new language';

  @override
  String get landing_page_use_case_first_description =>
      'Pair a word with an audio clip of its pronunciation and a picture instead of just a translation — build cards the way you actually think about the word.';

  @override
  String get landing_page_use_case_second_title => 'Studying for an exam';

  @override
  String get landing_page_use_case_second_description =>
      'Turn lecture slides, diagrams, and your own notes into cards organized by subject and chapter, nested exactly the way your course is structured.';

  @override
  String get landing_page_final_cta => 'Ready to remember more?';

  @override
  String get pricing_page_could_not_load => 'Couldn\'t load pricing right now.';

  @override
  String get pricing_page_no_plan_available => 'No plans are available right now.';

  @override
  String get pricing_page_choose_plan => 'Choose your plan';

  @override
  String get pricing_page_choose_plan_description => 'Pick the plan that fits how you use Memoize.';

  @override
  String get pricing_page_levels_of_nesting => 'levels of nesting';

  @override
  String get pricing_page_cards_per_category => 'cards per category';

  @override
  String get pricing_page_contents_per_card_side => 'contents per card side';

  @override
  String get pricing_page_get_started => 'Get started';

  @override
  String get avatar_upload_success => 'Avatar image successfully uploaded';

  @override
  String get upload_video => 'Upload video';

  @override
  String get video_not_selected => 'No video selected';

  @override
  String get upload_image => 'Upload image';

  @override
  String get image_not_selected => 'No image selected';

  @override
  String get upload_audio => 'Upload audio';

  @override
  String get audio_not_selected => 'No audio selected';

  @override
  String get choose_audio => 'Choose audio';

  @override
  String get home => 'Home';

  @override
  String otp_sheet_heading(String destination) {
    return 'Enter the 6-digit code sent to $destination';
  }

  @override
  String get no_image_selected => 'No image selected';

  @override
  String get folder_add_success => 'Successfully added new folder.';

  @override
  String get folder_add_failed => 'Failure while trying to add new folder.';

  @override
  String get folder_move_success => 'Successfully moved the folder.';

  @override
  String get folder_move_failed => 'Failure while trying to move the folder.';

  @override
  String get folders_not_found => 'Folders not found!';

  @override
  String get folder_not_found => 'No folder found!';

  @override
  String get folder_set_success => 'Successfully updated folder.';

  @override
  String get folder_set_failed => 'Failure while trying to update folder.';

  @override
  String get folder_remove_success => 'Successfully removed folder.';

  @override
  String get folder_remove_failed => 'Failure while trying to remove folder.';

  @override
  String get file_add_success => 'Successfully added new file.';

  @override
  String get file_add_failed => 'Failure while trying to add new file.';

  @override
  String get files_not_found => 'Files not found!';

  @override
  String get file_not_found => 'No file found!';

  @override
  String get file_set_success => 'Successfully updated file.';

  @override
  String get file_set_failed => 'Failure while trying to update file.';

  @override
  String get file_remove_success => 'Successfully removed file.';

  @override
  String get file_remove_failed => 'Failure while trying to remove file.';

  @override
  String get file_move_success => 'Successfully moved the file.';

  @override
  String get file_move_failed => 'Failure while trying to move the file.';

  @override
  String get content_set_success => 'Successfully updated content.';

  @override
  String get content_set_failed => 'Failure while trying to update content.';

  @override
  String get content_add_success => 'Successfully added content.';

  @override
  String get content_add_failed => 'Failure while trying to add content.';

  @override
  String get content_remove_success => 'Successfully removed content.';

  @override
  String get content_remove_failed => 'Failure while trying to remove content.';

  @override
  String get content_value_set_success => 'Successfully updated content.';

  @override
  String get content_value_set_failed => 'Failure while trying to update content.';

  @override
  String get content_value_add_success => 'Successfully added content.';

  @override
  String get content_value_add_failed => 'Failure while trying to add content.';

  @override
  String get content_value_remove_success => 'Successfully removed content.';

  @override
  String get content_value_remove_failed => 'Failure while trying to remove content.';

  @override
  String get content_move_failed => 'Failure while trying to move content.';

  @override
  String get content_not_found => 'No content found!';

  @override
  String get app_page_file_pagination_failed => 'Failure while trying to load cards';

  @override
  String get app_page_folder_pagination_failed => 'Failure while trying to load categories';

  @override
  String get retry => 'Retry';

  @override
  String get payment_result_checking => 'Checking payment...';

  @override
  String get checking_plan => 'Checking your plan...';

  @override
  String get plan_check_failed => 'Failed to check your plan.';

  @override
  String get payment_result_continue => 'Continue';

  @override
  String get payment_result_success_title => 'Payment Successful';

  @override
  String get payment_result_error_title => 'Payment Failed';

  @override
  String get payment_result_success_message => 'Your payment was completed successfully.';

  @override
  String get payment_result_error_message => 'Your payment could not be completed.';

  @override
  String get checkout_title => 'Checkout';

  @override
  String get checkout_payment_method => 'Payment method';

  @override
  String get checkout_duration_month => 'Month';

  @override
  String get checkout_duration_year => 'Year';

  @override
  String get checkout_total => 'Total';

  @override
  String get checkout_pay => 'Pay';

  @override
  String get checkout_cancel => 'Cancel';

  @override
  String get checkout_retry => 'Retry';

  @override
  String get checkout_no_methods => 'No payment methods available.';

  @override
  String get checkout_load_methods_failed => 'Failed to load payment methods.';

  @override
  String get checkout_select_method => 'Select a payment method.';

  @override
  String get checkout_pay_failed => 'Payment failed.';

  @override
  String get limit_reached => 'You\'ve reached a limit on your current plan. Upgrade to keep going.';

  @override
  String get upgrade_required => 'Upgrade required';

  @override
  String get notNow => 'Not now';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get sentence => 'sentence';

  @override
  String get remove => 'Remove';

  @override
  String get avatar_delete_success => 'successfully removed user \'s avatar';

  @override
  String get remove_subscription => 'Remove subscription';

  @override
  String get subscription_delete_success => 'Subscription removed successfully.';

  @override
  String get storage_usage => 'Storage usage';

  @override
  String get add_storage => 'Add storage';

  @override
  String get continue_to_payment => 'Continue to payment';

  @override
  String get renewal => 'Renewal';

  @override
  String get please_fill_inputs_correctly => 'Please fill in the inputs correctly';

  @override
  String get checkout_additional_storage => 'Additional Storage';

  @override
  String get checkout_storage_invalid => 'Invalid storage value';

  @override
  String get checkout_days_suffix => 'days';

  @override
  String get checkout_duration_days => 'Plan duration in days';

  @override
  String get checkout_duration_invalid => 'Invalid days value';

  @override
  String get error_code_unsupported_payment_method => 'This payment method is not supported.';

  @override
  String get error_code_internal => 'Something went wrong. Please try again.';

  @override
  String get error_code_internal_error => 'Something went wrong. Please try again.';

  @override
  String get error_code_plan_state_invalid => 'The current plan state is invalid.';

  @override
  String get error_code_otp_cooldown => 'Please wait before requesting another verification code.';

  @override
  String get error_code_phone_registration_disabled => 'Phone number registration is currently unavailable.';

  @override
  String get error_code_create_failed => 'Failed to create the requested item.';

  @override
  String get error_code_fetch_failed => 'Failed to load the requested data.';

  @override
  String get error_code_email_registration_disabled => 'Email registration is currently unavailable.';

  @override
  String get error_code_smtp_cooldown => 'Please wait before requesting another email.';

  @override
  String get error_code_invalid_input => 'Some of the provided information is invalid.';

  @override
  String get error_code_email_not_found => 'No account was found with this email.';

  @override
  String get error_code_update_failed => 'Failed to update the requested item.';

  @override
  String get error_code_no_refresh_token => 'Your session has expired. Please log in again.';

  @override
  String get error_code_refresh_invalid => 'Your session has expired. Please log in again.';

  @override
  String get error_code_invalid_plan => 'The selected plan is invalid.';

  @override
  String get error_code_user_has_no_active_plan => 'You do not have an active plan.';

  @override
  String get error_code_plan_already_active => 'This plan is already active.';

  @override
  String get error_code_must_use_same_payment_method_as_previous_plan => 'You must use the same payment method as your previous plan.';

  @override
  String get error_code_user_has_active_plan => 'You already have an active plan.';

  @override
  String get error_code_upload_failed => 'Failed to upload the file.';

  @override
  String get error_code_user_not_found => 'User not found.';

  @override
  String get error_code_avatar_not_found => 'Avatar not found.';

  @override
  String get error_code_unauthenticated => 'Authentication is required. Please log in again.';

  @override
  String get error_code_invalid_parent_treenode => 'The selected parent is invalid.';

  @override
  String get error_code_subscription_state_invalid => 'The current subscription state is invalid.';

  @override
  String get error_code_invalid_treenode_id => 'The selected item is invalid.';

  @override
  String get error_code_leaf_not_found => 'The requested item was not found.';

  @override
  String get error_code_invalid_plan_title => 'The plan title is invalid.';

  @override
  String get error_code_subscription_not_found => 'Subscription not found.';

  @override
  String get error_code_active_plan_expired => 'Your active plan has expired.';

  @override
  String get error_code_active_plan_currency_mismatch => 'The currency does not match your active plan.';

  @override
  String get error_code_no_subscription => 'You do not have a subscription.';

  @override
  String get error_code_uuid_not_found => 'The requested item was not found.';

  @override
  String get error_code_invalid_subscription_due => 'The subscription due date is invalid.';

  @override
  String get error_code_invalid_parameters => 'Some of the provided parameters are invalid.';

  @override
  String get calculate_price => 'Calculate Price';

  @override
  String get error_code_plan_not_found => 'Plan not found';

  @override
  String get error_code_plan_payment_method => 'This payment method is not available for this plan';

  @override
  String get error_code_no_upgrade_options => 'Each plan renewal must add at least 3 days to the due date or 1 GB to storage';

  @override
  String get checkout_upgrade_requirement_title => 'At least one of the following must be satisfied:';

  @override
  String get checkout_upgrade_duration_requirement => 'Plan duration must be changed by more than 3 days.';

  @override
  String get checkout_upgrade_storage_requirement => 'Storage must be changed by more than 10 GB.';

  @override
  String get checkout_free_purchase_message => 'This purchase is free for you. The remaining balance will be saved for future purchases.';
}
