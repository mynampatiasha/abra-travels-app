// Stub implementation for non-web platforms
import 'dart:typed_data';

void downloadFile(Uint8List bytes, String filename) {
  throw UnsupportedError('Download is only supported on web platform');
}
