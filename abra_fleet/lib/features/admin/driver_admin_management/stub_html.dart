// Stub file for dart:html on non-web platforms
// This file provides empty implementations to satisfy imports on mobile/desktop

class Blob {
  Blob(List<dynamic> parts, String mimeType);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  AnchorElement({String? href});
  void setAttribute(String name, String value) {}
  void click() {}
}
