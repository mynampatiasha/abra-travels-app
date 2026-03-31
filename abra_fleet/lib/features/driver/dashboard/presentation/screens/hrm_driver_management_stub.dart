// Stub implementation for non-web platforms (Android/iOS)
import 'package:flutter/widgets.dart';

/// Stub: Does nothing on mobile platforms
void registerWebViewFactory(String viewId, String url) {
  // No-op on mobile
}

/// Stub: Returns empty container on mobile platforms
Widget buildHtmlElementView(String viewType) {
  return const SizedBox.shrink();
}

/// Stub: Does nothing on mobile platforms
void openUrlInNewTab(String url) {
  // No-op on mobile
}
