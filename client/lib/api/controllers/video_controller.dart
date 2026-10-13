import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/video.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class VideoController {
  final Ref ref;

  Dio get _authDio => ref.read(authDioProvider);

  VideoController(this.ref);

  Future<Video?> get({required String videoId}) async {
    talker.info('VideoController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/video/info?videoId=$videoId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('VideoController.get call ended');
      return null;
    }

    talker.info('VideoController.get call ended');
    return Video.fromJson(response.dataOrNull);
  }

  Future<String?> getSignedToken({required String videoId}) async {
    talker.info('VideoController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/video/singed_token?videoId=$videoId'));
    talker.info({'response.dataOrNull': response.dataOrNull});
    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('VideoController.get call ended');
      return null;
    }

    talker.info('VideoController.get call ended');
    return response.dataOrNull;
  }
}

final videoControllerProvider = Provider((ref) => VideoController(ref));
