// Platform-agnostic download helper
import 'dart:typed_data';

// Conditional export based on platform
export 'download_helper_mobile.dart' if (dart.library.html) 'download_helper_web.dart';
