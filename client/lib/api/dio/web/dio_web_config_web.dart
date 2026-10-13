import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureDioForWeb(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
