// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerWebView(String viewId, String url) {
  // Register the view factory for web
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'camera; microphone; geolocation; fullscreen'
        ..setAttribute('allowfullscreen', 'true');

      return iframe;
    },
  );
}
