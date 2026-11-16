import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:permission_handler/permission_handler.dart';
// Conditional imports for web
import 'tours_travels_webview_web.dart' if (dart.library.io) 'tours_travels_webview_stub.dart';

// UI Constants
const Color kPrimaryColor = Color(0xFF0D47A1);

class ToursTravelsWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const ToursTravelsWebViewScreen({
    Key? key,
    required this.url,
    required this.title,
  }) : super(key: key);

  @override
  State<ToursTravelsWebViewScreen> createState() => _ToursTravelsWebViewScreenState();
}

class _ToursTravelsWebViewScreenState extends State<ToursTravelsWebViewScreen> {
  late final WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  late String _iframeId;

  @override
  void initState() {
    super.initState();
    _iframeId = 'tours-travels-iframe-${widget.url.hashCode}';
    if (kIsWeb) {
      _initializeWebIframe();
    } else {
      _requestPermissions();
    }
  }

  // ✅ Appends a throwaway timestamp param so the browser/WebView can never
  // serve a cached copy of the PHP page on refresh -- without this, "Refresh"
  // re-requests the exact same URL and a cached response (or, on web, the
  // iframe just never reloading at all -- see _refresh()) can silently hide
  // any server-side change until the app is fully restarted.
  String _cacheBustedUrl() {
    final separator = widget.url.contains('?') ? '&' : '?';
    return '${widget.url}${separator}_cb=${DateTime.now().millisecondsSinceEpoch}';
  }

  // ✅ Shared by both the AppBar refresh button and the error screen's "Try
  // Again" button. On web, the iframe's src is fixed at creation time by
  // registerViewFactory -- re-registering the SAME viewId throws, and the
  // previous code just toggled the loading spinner without touching the
  // iframe at all, so edits to the PHP page never showed up no matter how
  // many times you clicked Refresh. Generating a brand-new viewId each time
  // forces Flutter to create a fresh iframe pointed at the cache-busted URL.
  void _refresh() {
    debugPrint('🌍 Refreshing page...');
    if (kIsWeb) {
      final freshUrl = _cacheBustedUrl();
      final newIframeId = 'tours-travels-iframe-${DateTime.now().microsecondsSinceEpoch}';
      registerWebView(newIframeId, freshUrl);
      setState(() {
        _iframeId = newIframeId;
        _isLoading = true;
        _errorMessage = null;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      _controller?.loadRequest(Uri.parse(_cacheBustedUrl()));
    }
  }

  /// Request camera and location permissions before initializing WebView
  Future<void> _requestPermissions() async {
    debugPrint('🔐 ========================================');
    debugPrint('🔐 REQUESTING CAMERA & LOCATION PERMISSIONS');
    debugPrint('🔐 ========================================');
    
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    debugPrint('🔐 Camera permission: $cameraStatus');
    
    // Request location permissions
    final locationStatus = await Permission.location.request();
    debugPrint('🔐 Location permission: $locationStatus');
    
    // Request microphone permission (for WebView media)
    final microphoneStatus = await Permission.microphone.request();
    debugPrint('🔐 Microphone permission: $microphoneStatus');
    
    debugPrint('🔐 ========================================');
    debugPrint('🔐 PERMISSIONS REQUESTED - INITIALIZING WEBVIEW');
    debugPrint('🔐 ========================================');
    
    _initializeWebView();
  }

  void _initializeWebIframe() {
    debugPrint('🌍 ========================================');
    debugPrint('🌍 INITIALIZING WEB IFRAME');
    debugPrint('🌍 Title: ${widget.title}');
    debugPrint('🌍 URL: ${widget.url}');
    debugPrint('🌍 ========================================');

    // Register iframe for web using conditional import
    registerWebView(_iframeId, widget.url);

    // Simulate loading complete after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _initializeWebView() {
    debugPrint('🌍 ========================================');
    debugPrint('🌍 INITIALIZING WEBVIEW (Mobile)');
    debugPrint('🌍 Title: ${widget.title}');
    debugPrint('🌍 URL: ${widget.url}');
    debugPrint('🌍 ========================================');

    // Create platform-specific parameters
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    // ✅ Grant camera/microphone access when the page calls getUserMedia() (e.g. attendance
    // photo capture). Without this, Android's WebView denies all media requests even though
    // the app itself already has the OS-level CAMERA permission.
    final WebViewController controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (WebViewPermissionRequest request) {
        debugPrint('🔐 WebView permission requested: ${request.types}');
        request.grant();
      },
    );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('🌍 Loading progress: $progress%');
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
            debugPrint('🌍 Page started loading: $url');
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            debugPrint('🌍 ✅ Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _errorMessage = error.description;
            });
            debugPrint('🌍 ❌ Error loading page: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🌍 Navigation request: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // ✅ ANDROID-SPECIFIC: Enable geolocation and camera permissions
    if (controller.platform is AndroidWebViewController) {
      debugPrint('🤖 Configuring Android WebView permissions...');
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController).setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          debugPrint('📍 Geolocation permission requested by WebView');
          debugPrint('📍 Origin: ${request.origin}');
          
          // Grant geolocation permission
          return GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
      );

      // Camera/microphone media requests are granted via the cross-platform
      // onPermissionRequest callback passed to WebViewController.fromPlatformCreationParams above.
      debugPrint('🔐 Android WebView configured - media permissions granted via onPermissionRequest');
    }

    // ✅ iOS-SPECIFIC: Configure WKWebView for media permissions
    if (controller.platform is WebKitWebViewController) {
      debugPrint('🍎 Configuring iOS WKWebView permissions...');
      // iOS handles permissions through Info.plist and system prompts
      // No additional configuration needed here
    }

    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            debugPrint('🌍 ========================================');
            debugPrint('🌍 BACK BUTTON CLICKED');
            debugPrint('🌍 Navigating back to Admin Dashboard');
            debugPrint('🌍 ========================================');
            Navigator.pop(context);
          },
          tooltip: 'Back to Dashboard',
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Content based on platform
          if (kIsWeb)
            // Web: Use HtmlElementView with iframe
            HtmlElementView(viewType: _iframeId)
          else
            // Mobile: Use WebView
            if (_controller != null) WebViewWidget(controller: _controller!),
          
          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Error message
          if (_errorMessage != null && !_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load page',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
