import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/image.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class ImageController {
  final Ref ref;

  Dio get _authDio => ref.read(authDioProvider);

  ImageController(this.ref);
  Future<ImageInfo?> get({required String imageId}) async {
    talker.info('ImageController.get is called...');

    final response = await apiCall(() => _authDio.get('/api/image/info?imageId=$imageId'));
    talker.debug({'response.dataOrNull': response.dataOrNull});

    if (response.isFailure || response.dataOrNull == null) {
      talker.info('Null response data!');
      talker.info('ImageController.get call ended');
      return null;
    }

    return ImageInfo.fromJson(response.dataOrNull);
  }
}

final imageControllerProvider = Provider((ref) => ImageController(ref));
