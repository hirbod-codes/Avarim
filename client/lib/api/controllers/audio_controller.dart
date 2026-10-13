import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/dio/dio_providers.dart';
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

  Future<Audio?> getByTitle({required String title}) async {
    talker.info('AudioController.getByTitle is called...');

    final response = await apiCall(() => _authDio.get('/api/audio/info?title=$title'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('AudioController.getByTitle call ended');
      return null;
    }

    return Audio.fromJson(response.dataOrNull);
  }
}

final audioControllerProvider = Provider((ref) => AudioController(ref));
