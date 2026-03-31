import 'dart:typed_data';
import 'dart:html' as html;

// Web-specific implementation
void downloadFile(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

// Legacy function name for backward compatibility
void downloadFilePlatform(Uint8List bytes, String filename) {
  downloadFile(bytes, filename);
}
