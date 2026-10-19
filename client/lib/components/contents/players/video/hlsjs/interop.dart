@JS()
library hls_interop;

import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Minimal JS interop bindings for hls.js.
/// Docs: https://github.com/video-dev/hls.js/blob/master/docs/API.md
@JS('Hls')
extension type Hls._(JSObject _) implements JSObject {
  external factory Hls();

  external static bool isSupported();

  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement media);
  external void on(String event, JSFunction listener);
  external void startLoad();
  external void recoverMediaError();
  external void destroy();
}

/// Shape of the `data` object hls.js passes to the 'hlsError' event.
@JS()
extension type HlsErrorData._(JSObject _) implements JSObject {
  external bool get fatal;
  external String? get type;
  external String? get details;
}

abstract class HlsEvent {
  static const error = 'hlsError';
}

abstract class HlsErrorType {
  static const network = 'networkError';
  static const media = 'mediaError';
}
