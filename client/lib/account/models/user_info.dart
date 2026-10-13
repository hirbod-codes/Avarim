import 'package:avarim/auth/models/auth_models.dart';
import 'package:avarim/localization/calendars/calendar_system.dart';

/// Mirrors /api/auth/info's response shape. Deliberately has no
/// `password` field — even though the backend's validation schema
/// includes one (shared with write/insert validation), an info
/// endpoint should never actually send a password or hash back to the
/// client.
///
/// locale/calendarType/timeZone are NOT in the schema you gave me —
/// added here as optional fields on the assumption the backend will
/// store per-account localization preferences that should follow the
/// user across devices. If that assumption is wrong, these just stay
/// null forever and nothing breaks; if it's right, the backend needs
/// matching fields added to planSchema^H^H^H^H the user document schema.
class UserInfo {
  final String? id;
  final String role;
  final AuthMethod authMethod;
  final String? username;
  final String? phoneNumber;
  final String? email;
  final String? avatarKey;
  final bool temporaryAvatar;
  final String? locale;
  final CalendarType? calendarType;
  final String? timeZone;

  const UserInfo({
    this.id,
    required this.role,
    required this.authMethod,
    this.username,
    this.phoneNumber,
    this.email,
    this.avatarKey,
    required this.temporaryAvatar,
    this.locale,
    this.calendarType,
    this.timeZone,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    id: json['_id'] as String?,
    role: json['role'] as String,
    authMethod: json['authMethod'] == 'phone' ? AuthMethod.phone : AuthMethod.email,
    username: json['username'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    email: json['email'] as String?,
    avatarKey: json['avatarKey'] as String?,
    temporaryAvatar: json['temporaryAvatar'] as bool,
    locale: json['locale'] as String?,
    calendarType: _parseCalendarType(json['calendarType'] as String?),
    timeZone: json['timeZone'] as String?,
  );

  static CalendarType? _parseCalendarType(String? value) {
    if (value == null) return null;
    for (final t in CalendarType.values) {
      if (t.name == value) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'role': role,
    'authMethod': authMethod.name,
    'username': username,
    'phoneNumber': phoneNumber,
    'email': email,
    'avatarKey': avatarKey,
    'temporaryAvatar': temporaryAvatar,
    'locale': locale,
    'calendarType': calendarType?.name,
    'timeZone': timeZone,
  };
}
