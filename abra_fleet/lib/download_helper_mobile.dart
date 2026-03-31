import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

// Mobile-specific implementation
Future<void> downloadFilePlatform(Uint8List bytes, String filename) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes);
  
  // Optional: Open the file automatically
  OpenFile.open(file.path);
}
