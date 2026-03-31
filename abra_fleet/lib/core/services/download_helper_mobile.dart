// Mobile-specific download helper
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

Future<void> downloadFile(Uint8List bytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final filePath = '${directory.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
  print('✅ File saved to: $filePath');
  
  // Open file
  final result = await OpenFile.open(filePath);
  print('📂 File opened: ${result.message}');
}
