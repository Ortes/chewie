import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

final _handlers = <void Function(), JSFunction>{};

/// Whether the document exposes the Fullscreen API.
///
/// iPhone Safari ships no `Element.requestFullscreen`: only the video element
/// has `webkitEnterFullscreen`. Calling the missing member throws, so callers
/// have to feature-detect rather than assume a browser means the API is there.
bool get browserFullscreenSupported {
  final web.Element? element = web.document.documentElement;
  if (element == null) {
    return false;
  }
  return (element as JSObject).has('requestFullscreen');
}

void requestBrowserFullscreen() {
  if (!browserFullscreenSupported) {
    return;
  }
  web.document.documentElement?.requestFullscreen();
}

void exitBrowserFullscreen() {
  if (!browserFullscreenSupported) {
    return;
  }
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  }
}

bool get browserInFullscreen =>
    browserFullscreenSupported && web.document.fullscreenElement != null;

void addBrowserFullscreenChangeListener(void Function() callback) {
  final jsHandler = ((JSAny? _) => callback()).toJS;
  _handlers[callback] = jsHandler;
  web.document.addEventListener('fullscreenchange', jsHandler);
}

void removeBrowserFullscreenChangeListener(void Function() callback) {
  final jsHandler = _handlers.remove(callback);
  if (jsHandler != null) {
    web.document.removeEventListener('fullscreenchange', jsHandler);
  }
}
