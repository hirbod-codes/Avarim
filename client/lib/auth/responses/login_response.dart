import 'package:flutter/foundation.dart';

class LoginResponse {
  final String accessToken;
  final String? refreshToken;

  LoginResponse({required this.accessToken, required this.refreshToken});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];

    if (accessToken == null || (!kIsWeb && refreshToken == null)) {
      throw Exception('Invalid login response');
    }

    return LoginResponse(accessToken: accessToken, refreshToken: refreshToken);
  }
}
