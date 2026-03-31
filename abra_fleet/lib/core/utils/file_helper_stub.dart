// Stub for web - File operations not supported
class FileHelper {
  static dynamic createFile(String path) {
    throw UnsupportedError('File operations not supported on web');
  }
  
  static Future<void> writeFile(dynamic file, String content) async {
    throw UnsupportedError('File operations not supported on web');
  }
  
  static Future<String> readFile(dynamic file) async {
    throw UnsupportedError('File operations not supported on web');
  }
}
