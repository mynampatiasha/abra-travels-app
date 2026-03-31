// IO implementation for mobile/desktop
import 'dart:io';

class FileHelper {
  static File createFile(String path) {
    return File(path);
  }
  
  static Future<void> writeFile(File file, String content) async {
    await file.writeAsString(content);
  }
  
  static Future<String> readFile(File file) async {
    return await file.readAsString();
  }
}
