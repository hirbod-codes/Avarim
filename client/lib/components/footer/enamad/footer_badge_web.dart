// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const _viewType = 'memoize-enamad-badge';
bool _registered = false;

// PLACEHOLDERS — replace with whatever you were actually given.
// const _linkUrl = 'https://REPLACE_WITH_LINK_URL';
// const _imageUrl = 'https://REPLACE_WITH_IMAGE_URL';
// const _altText = 'REPLACE_WITH_ALT_TEXT';

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
        ..href = 'https://trustseal.enamad.ir/?id=7649114&Code=73PTlAXHjPhgtZVV7hxJPlvoz0D1AWKq'
        ..target = '_blank'
        ..rel = 'noopener noreferrer'
        ..style.display = 'inline-block';

      final img = html.ImageElement()
        ..referrerPolicy = 'origin'
        ..src = 'https://trustseal.enamad.ir/logo.aspx?id=7649114&Code=73PTlAXHjPhgtZVV7hxJPlvoz0D1AWKq'
        ..attributes['code'] = '73PTlAXHjPhgtZVV7hxJPlvoz0D1AWKq'
        ..style.cursor = 'pointer'
        ..style.height = '64px'
        ..style.width = 'auto';

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
