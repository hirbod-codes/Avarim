import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class AudioController {
  final Ref ref;

  Dio get _authDio => ref.read(authDioProvider);

  AudioController(this.ref);

  Future<Audio?> get({required String audioId}) async {
    talker.info('AudioController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/audio/info?audioId=$audioId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('AudioController.get call ended');
      return null;
    }

    return Audio.fromJson(response.dataOrNull);
  }

  Future<String?> getSignedToken({required String audioId}) async {
    talker.info('AudioController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/audio/singed_token?audioId=$audioId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('AudioController.get call ended');
      return null;
    }

    return response.dataOrNull;
  }

  /// DELETE /api/audio/:audioId (admin only): deletes the audio itself, so it disappears from every album,
  /// artist and playlist. A failure is toasted by the global interceptor; true = success.
  Future<bool> delete({required String audioId}) async {
    final res = await apiCall<dynamic>(() => _authDio.delete<dynamic>('/api/audio/$audioId'));
    return res.isSuccess;
  }
}

final audioControllerProvider = Provider((ref) => AudioController(ref));
