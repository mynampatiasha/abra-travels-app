// Web-specific implementation for HRM Driver Management
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window, IFrameElement;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

/// Registers a web view factory for the given viewId and URL
void registerWebViewFactory(String viewId, String url) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int id) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'fullscreen';
      return iframe;
    },
  );
}

/// Builds an HtmlElementView for the given viewType
Widget buildHtmlElementView(String viewType) {
  return HtmlElementView(viewType: viewType);
}

/// Opens a URL in a new browser tab
void openUrlInNewTab(String url) {
  html.window.open(url, '_blank');
}
