// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

// ============================================================================
// WEB VIEW REGISTRATION  (web build only)
// ============================================================================
// Most HR/CRM pages render fine in a cross-origin <iframe>: the login rides on
// the ?user_email= parameter that each page's JS keeps on every link/form, plus
// a SameSite=None cookie for POST->redirect, so it no longer depends on the
// (iframe-blocked) PHP session cookie.
//
// The ONE exception is Attendance: it captures a photo, and Chrome blocks
// getUserMedia() in any cross-origin iframe. Those pages must open TOP-LEVEL
// in a new tab. Everything else stays embedded in the app.
//
// Native Android/iOS use a real first-party WebView (this file is web-only).
// ============================================================================

// URL fragments whose pages need the camera -> must open top-level, not iframe.
// NOTE: 'hr-attendance-list' was removed so Attendance now loads inside the
// app iframe (which already sets allow="camera *"). If the camera is blocked
// in the browser, restore it here to fall back to the new-tab behaviour.
const _cameraPages = <String>[];

bool _needsTopLevel(String url) => _cameraPages.any((p) => url.contains(p));

void registerWebView(String viewId, String url) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) {
      if (!_needsTopLevel(url)) {
        // Embedded: render the page inside the app.
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'camera *; microphone *; geolocation *; fullscreen *'
          ..setAttribute('allowfullscreen', 'true')
          ..setAttribute('allowusermedia', 'true');
        return iframe;
      }

      // Camera page: open the real page top-level so getUserMedia() works.
      html.window.open(url, '_blank');

      final div = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'flex'
        ..style.flexDirection = 'column'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.background = '#f0f4f8'
        ..style.fontFamily = 'Poppins, sans-serif';

      div.innerHtml = '''
        <div style="text-align:center; padding:40px; max-width:420px;">
          <div style="font-size:56px; margin-bottom:16px;">📷</div>
          <h2 style="color:#1e3a8a; font-weight:700; margin-bottom:10px;">Attendance opened in a new tab</h2>
          <p style="color:#475569; font-size:14px; line-height:1.5; margin-bottom:22px;">
            The camera only works on a full page, so Attendance opens as its own tab.
            If it did not open, use the button below.
          </p>
          <button onclick="window.open('$url', '_blank')"
            style="background:linear-gradient(135deg,#1e3a8a,#1e40af); color:white;
                   border:none; padding:13px 26px; border-radius:10px;
                   font-size:14px; font-weight:700; cursor:pointer;">
            Open Attendance
          </button>
        </div>
      ''';

      return div;
    },
  );
}
