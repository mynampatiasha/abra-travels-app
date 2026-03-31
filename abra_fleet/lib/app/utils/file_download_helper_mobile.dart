// lib/utils/file_download_helper_mobile.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class FileDownloadHelper {
  /// Download and save file to device storage
  static Future<void> downloadFile(Uint8List bytes, String fileName) async {
    try {
      // Request storage permission for Android
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Storage permission denied');
        }
      }

      // Get the appropriate directory
      Directory? directory;
      if (Platform.isAndroid) {
        // Try to get downloads directory, fallback to external storage
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        
        // Automatically open the file
        await OpenFile.open(filePath);
        
        print('File saved to: $filePath');
      }
    } catch (e) {
      print('Error downloading file: $e');
      rethrow;
    }
  }

  /// Share file using native share dialog
  static Future<void> shareFile(Uint8List bytes, String fileName) async {
    try {
      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      
      // Share the file
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: fileName,
      );
    } catch (e) {
      print('Error sharing file: $e');
      rethrow;
    }
  }

  /// Copy text to clipboard
  static Future<void> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      print('Error copying to clipboard: $e');
      rethrow;
    }
  }

  /// Open URL in external browser/app
  static Future<void> openUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch $urlString');
      }
    } catch (e) {
      print('Error opening URL: $e');
      rethrow;
    }
  }

  /// Check if native share is available (always true on mobile)
  static bool canShare() {
    return true;
  }
}