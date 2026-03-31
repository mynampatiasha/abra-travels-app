// lib/utils/file_download_helper_web.dart
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';

class FileDownloadHelper {
  /// Download file in web browser
  static Future<void> downloadFile(Uint8List bytes, String fileName) async {
    try {
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      final anchor = html.AnchorElement()
        ..href = url
        ..download = fileName
        ..click();
      
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('Error downloading file: $e');
      rethrow;
    }
  }

  /// Share file using Web Share API
  static Future<void> shareFile(Uint8List bytes, String fileName) async {
    try {
      if (html.window.navigator.share != null) {
        final blob = html.Blob([bytes]);
        final file = html.File([blob], fileName);
        
        await html.window.navigator.share({
          'files': [file],
          'title': fileName,
        });
      } else {
        // Fallback to download if share is not available
        await downloadFile(bytes, fileName);
      }
    } catch (e) {
      print('Error sharing file: $e');
      rethrow;
    }
  }

  /// Copy text to clipboard
  static Future<void> copyToClipboard(String text) async {
    try {
      await html.window.navigator.clipboard?.writeText(text);
    } catch (e) {
      print('Error copying to clipboard: $e');
      rethrow;
    }
  }

  /// Open URL in new tab
  static Future<void> openUrl(String urlString) async {
    try {
      html.window.open(urlString, '_blank');
    } catch (e) {
      print('Error opening URL: $e');
      rethrow;
    }
  }

  /// Check if Web Share API is available
  static bool canShare() {
    return html.window.navigator.share != null;
  }
}