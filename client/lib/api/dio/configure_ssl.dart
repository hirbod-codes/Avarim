import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

void trustExtraRoot(Dio dio) {
  List<int> rootPemBytes = kDebugMode
      ? File(p.join(Directory.current.absolute.path, '..', 'backend', "localhost+2.pem")).readAsBytesSync()
      : File(p.join(Directory.current.absolute.path, 'lib', 'api', 'dio', "fullchain.pem")).readAsBytesSync();

  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final context = SecurityContext(withTrustedRoots: true)..setTrustedCertificatesBytes(rootPemBytes);
    return HttpClient(context: context);
  };
}
