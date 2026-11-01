import 'dart:io';
import 'package:avarim/main.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void trustExtraRoot(Dio dio, Ref ref) {
  List<int> rootPemBytes = ref.watch(rootPemBytesProvider);

  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final context = SecurityContext(withTrustedRoots: true)..setTrustedCertificatesBytes(rootPemBytes);
    return HttpClient(context: context);
  };
}
