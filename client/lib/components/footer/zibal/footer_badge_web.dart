// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const _viewType = 'memoize-zibal-badge';
bool _registered = false;

/// Embeds the badge as real DOM elements, built directly rather than
/// via setInnerHtml + a NodeValidator.
///
/// Why: dart:html's sanitizer treats href/src as URI attributes and
/// checks them against a UriPolicy separately from the element/attribute
/// allowlist. The default policy only allows same-origin relative URLs
/// — an external badge link and image get silently stripped, which is
/// exactly the "attributes vanish" bug. Since this is static content
/// you wrote yourself (not untrusted/dynamic HTML), there's nothing to
/// sanitize in the first place — constructing the elements directly
/// avoids the sanitizer entirely instead of fighting its default policy.
Widget buildFooterBadgeWidget() {
  if (!_registered) {
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final anchor = html.AnchorElement()
        ..referrerPolicy = 'origin'
        ..href = 'https://gateway.zibal.ir/trustMe/memoize.ir'
        ..target = '_blank'
        ..rel = 'noopener'
        ..style.display = 'inline-block';

      final img = html.ImageElement()
        ..referrerPolicy = 'origin'
        ..src = 'https://zibal.ir/trust/assets/1.png'
        ..style.cursor = 'pointer'
        ..style.height = '100px'
        ..style.width = 'auto'
      // ..style.height = 'auto'
      // ..style.maxWidth = '110px'
      ;

      anchor.append(img);

      return html.DivElement()
        ..style.display = 'inline-block'
        ..append(anchor);
    });
  }

  return const SizedBox(
    height: 32,
    width: 140, // adjust to the badge's actual dimensions
    child: HtmlElementView(viewType: _viewType),
  );
}
