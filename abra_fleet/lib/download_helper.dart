import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports for web and mobile
import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart'
    if (dart.library.io) 'download_helper_mobile.dart';

// Main download function that delegates to platform-specific implementation
void downloadFile(Uint8List bytes, String filename) {
  downloadFilePlatform(bytes, filename);
}
