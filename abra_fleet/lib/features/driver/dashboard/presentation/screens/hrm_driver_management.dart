import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ── Web-only imports (conditional) ──────────────────────────────────────────
// These imports are only included when building for web platform
import 'hrm_driver_management_web.dart' if (dart.library.io) 'hrm_driver_management_stub.dart';

// ── TMS Screens (Flutter-native) ───────────────────────────────────────────
import 'package:abra_fleet/features/TMS/raise_ticket.dart';
import 'package:abra_fleet/features/TMS/my_tickets.dart';

// ── HRM Feedback Screen (Flutter-native) ──────────────────────────────────
import 'package:abra_fleet/features/admin/hrm/hrm_feedback.dart';

// ── Colours that match the whole app ──────────────────────────────────────
const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryLight = Color(0xFF1565C0);
const Color _kAccent = Color(0xFF0288D1);
const Color _kSurface = Color(0xFFF4F7FF);
const Color _kCard = Colors.white;

// ── HRM WebView URLs ───────────────────────────────────────────────────────
const _kHrmUrls = {
  'attendance': 'https://www.abra-travels.com/hrm/hr-attendance-list.php',
  'leave': 'https://www.abra-travels.com/hrm/hr-leave-requests.php',
  'feedback': 'https://www.abra-travels.com/hrm/hr-feedback.php',
  'notice': 'https://abra-travels.com/hrm/hr-notices.php',
  'kpi': 'https://www.abra-travels.com/hrm/hr-kpi-evaluation.php',
};

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class HrmDriverManagementScreen extends StatefulWidget {
  final VoidCallback? onNavigateToNotifications;

  const HrmDriverManagementScreen({
    super.key,
    this.onNavigateToNotifications,
  });

  @override
  State<HrmDriverManagementScreen> createState() =>
      _HrmDriverManagementScreenState();
}

class _HrmDriverManagementScreenState
    extends State<HrmDriverManagementScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  String? _userEmail;
  bool _loading = true;

  // Track which feature is currently open (null = menu screen)
  String? _currentFeature;
  String? _currentFeatureTitle;

  // Track registered iframe view IDs — avoids duplicate-factory errors
  final Set<String> _registeredViewIds = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _loadUserEmail();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        setState(() => _userEmail = map['email'] as String?);
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  /// Appends ?user_email=… the same way the admin shell does
  String _buildUrl(String base) {
    if (_userEmail == null || _userEmail!.isEmpty) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}user_email=${Uri.encodeComponent(_userEmail!)}';
  }

  // ── Navigation helpers ───────────────────────────────────────────────────

  void _openFlutter(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _openFeature(String title, String urlKey,
      {bool isFlutterScreen = false}) {
    setState(() {
      _currentFeature = urlKey;
      _currentFeatureTitle = title;
    });
  }

  void _goBackToMenu() {
    setState(() {
      _currentFeature = null;
      _currentFeatureTitle = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _currentFeature == null
              ? _buildMenuScreen()
              : _buildFeatureScreen(),
    );
  }

  // ── Menu Screen ──────────────────────────────────────────────────────────

  Widget _buildMenuScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.confirmation_number_rounded,
            label: 'Ticket Management System',
            delay: 0,
            controller: _animCtrl,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HrmCard(
                  icon: Icons.add_circle_outline_rounded,
                  iconBg: const Color(0xFFE3F2FD),
                  iconColor: _kPrimary,
                  label: 'Raise a Ticket',
                  subtitle: 'Submit new issue',
                  delay: 0.05,
                  controller: _animCtrl,
                  onTap: () => _openFlutter(const RaiseTicketScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HrmCard(
                  icon: Icons.list_alt_rounded,
                  iconBg: const Color(0xFFE8F5E9),
                  iconColor: const Color(0xFF2E7D32),
                  label: 'My Tickets',
                  subtitle: 'Track your issues',
                  delay: 0.10,
                  controller: _animCtrl,
                  onTap: () => _openFlutter(const MyTicketsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            icon: Icons.people_alt_rounded,
            label: 'HRM Portal',
            delay: 0.15,
            controller: _animCtrl,
          ),
          const SizedBox(height: 12),
          _buildHrmGrid(),
        ],
      ),
    );
  }

  // ── Feature Screen ───────────────────────────────────────────────────────
  // Renders the selected HRM page inline — the parent Scaffold's AppBar
  // (with back arrow) and the DriverMainShell bottom nav bar stay intact.

  Widget _buildFeatureScreen() {
    if (_currentFeature == 'feedback') {
      return const HRMFeedbackScreen();
    }

    final raw = _kHrmUrls[_currentFeature]!;
    final url = _buildUrl(raw);

    if (kIsWeb) {
      return _buildInlineIframe(url);
    } else {
      return _buildInlineWebView(url);
    }
  }

  // ── Inline iframe — WEB ──────────────────────────────────────────────────
  // Uses platform-specific implementation via conditional imports

  Widget _buildInlineIframe(String url) {
    final viewId = 'hrm-iframe-${_currentFeature ?? 'view'}';

    if (!_registeredViewIds.contains(viewId)) {
      _registeredViewIds.add(viewId);
      registerWebViewFactory(viewId, url);
    }

    return buildHtmlElementView(viewId);
  }

  // ── Inline WebView — MOBILE ──────────────────────────────────────────────

  Widget _buildInlineWebView(String url) {
    return _InlineWebView(url: url);
  }

  // ── AppBar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: _kPrimary,
      automaticallyImplyLeading: false,
      toolbarHeight: 70,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kPrimary, _kAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                if (_currentFeature != null)
                  GestureDetector(
                    onTap: _goBackToMenu,
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentFeature == null
                            ? 'HRM & Support'
                            : _currentFeatureTitle ?? 'HRM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        _currentFeature == null
                            ? 'Manage your HR activities'
                            : 'Tap back to return to menu',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onNavigateToNotifications != null)
                  GestureDetector(
                    onTap: widget.onNavigateToNotifications,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HRM Cards Grid ───────────────────────────────────────────────────────

  Widget _buildHrmGrid() {
    final items = [
      _HrmCardData(
        icon: Icons.calendar_today_rounded,
        iconBg: const Color(0xFFFFF3E0),
        iconColor: const Color(0xFFE65100),
        label: 'Attendance',
        subtitle: 'View your records',
        urlKey: 'attendance',
        delay: 0.20,
      ),
      _HrmCardData(
        icon: Icons.beach_access_rounded,
        iconBg: const Color(0xFFFCE4EC),
        iconColor: const Color(0xFFC62828),
        label: 'Leave Requests',
        subtitle: 'Apply & track leaves',
        urlKey: 'leave',
        delay: 0.25,
      ),
      _HrmCardData(
        icon: Icons.trending_up_rounded,
        iconBg: const Color(0xFFF3E5F5),
        iconColor: const Color(0xFF6A1B9A),
        label: 'KPI Evaluation',
        subtitle: 'Your performance',
        urlKey: 'kpi',
        delay: 0.30,
      ),
      _HrmCardData(
        icon: Icons.rate_review_rounded,
        iconBg: const Color(0xFFEDE7F6),
        iconColor: const Color(0xFF4527A0),
        label: 'Feedback',
        subtitle: 'Share your thoughts',
        urlKey: 'feedback',
        delay: 0.35,
        isFlutterScreen: true,
      ),
      _HrmCardData(
        icon: Icons.campaign_rounded,
        iconBg: const Color(0xFFE0F7FA),
        iconColor: const Color(0xFF00695C),
        label: 'Notice Board',
        subtitle: 'Company updates',
        urlKey: 'notice',
        delay: 0.40,
      ),
    ];

    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: _HrmCard(
                  icon: left.icon,
                  iconBg: left.iconBg,
                  iconColor: left.iconColor,
                  label: left.label,
                  subtitle: left.subtitle,
                  delay: left.delay,
                  controller: _animCtrl,
                  onTap: () {
                    if (left.isFlutterScreen && left.urlKey == 'feedback') {
                      _openFeature(left.label, left.urlKey,
                          isFlutterScreen: true);
                    } else {
                      _openFeature(left.label, left.urlKey);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: right != null
                    ? _HrmCard(
                        icon: right.icon,
                        iconBg: right.iconBg,
                        iconColor: right.iconColor,
                        label: right.label,
                        subtitle: right.subtitle,
                        delay: right.delay,
                        controller: _animCtrl,
                        onTap: () {
                          if (right.isFlutterScreen &&
                              right.urlKey == 'feedback') {
                            _openFeature(right.label, right.urlKey,
                                isFlutterScreen: true);
                          } else {
                            _openFeature(right.label, right.urlKey);
                          }
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════
class _HrmCardData {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String subtitle;
  final String urlKey;
  final double delay;
  final bool isFlutterScreen;

  const _HrmCardData({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.urlKey,
    required this.delay,
    this.isFlutterScreen = false,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  REUSABLE CARD WIDGET
// ══════════════════════════════════════════════════════════════════════════════
class _HrmCard extends StatefulWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String subtitle;
  final double delay;
  final AnimationController controller;
  final VoidCallback onTap;

  const _HrmCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.delay,
    required this.controller,
    required this.onTap,
  });

  @override
  State<_HrmCard> createState() => _HrmCardState();
}

class _HrmCardState extends State<_HrmCard> {
  bool _pressed = false;

  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final start = widget.delay.clamp(0.0, 0.99);
    final end = (start + 0.35).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: widget.controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
            .animate(curved);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTapDown: (_) {
            if (mounted) setState(() => _pressed = true);
          },
          onTapUp: (_) {
            if (mounted) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          },
          onTapCancel: () {
            if (mounted) setState(() => _pressed = false);
          },
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _kPrimary.withOpacity(0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(widget.icon, color: widget.iconColor, size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: widget.iconBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.arrow_forward_ios_rounded,
                            size: 11, color: widget.iconColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTION HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final double delay;
  final AnimationController controller;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.delay,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final start = delay.clamp(0.0, 0.99);
    final end = (start + 0.3).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(anim),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPrimary, _kAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kPrimary.withOpacity(0.25),
                    Colors.transparent,
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

// ══════════════════════════════════════════════════════════════════════════════
//  INLINE WEBVIEW — MOBILE ONLY
//  Renders the URL inside the same Scaffold body.
//  The parent AppBar and DriverMainShell bottom nav bar stay fully intact.
// ══════════════════════════════════════════════════════════════════════════════
class _InlineWebView extends StatefulWidget {
  final String url;
  const _InlineWebView({required this.url});

  @override
  State<_InlineWebView> createState() => _InlineWebViewState();
}

class _InlineWebViewState extends State<_InlineWebView> {
  WebViewController? _wvCtrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _wvCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (_wvCtrl == null) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    return Stack(
      children: [
        WebViewWidget(controller: _wvCtrl!),
        if (_isLoading)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _kPrimary),
                  SizedBox(height: 16),
                  Text(
                    'Loading…',
                    style: TextStyle(
                      color: _kPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  LEGACY FULL-SCREEN WEBVIEW
//  Kept for backward compatibility with any code that still calls this via
//  Navigator.push. The HRM inline flow above does NOT use this class.
// ══════════════════════════════════════════════════════════════════════════════
class _DriverWebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const _DriverWebViewScreen({
    required this.title,
    required this.url,
  });

  @override
  State<_DriverWebViewScreen> createState() => _DriverWebViewScreenState();
}

class _DriverWebViewScreenState extends State<_DriverWebViewScreen> {
  WebViewController? _wvCtrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _openInNewTab();
    } else {
      _initWebView();
    }
  }

  void _openInNewTab() {
    try {
      openUrlInNewTab(widget.url);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      debugPrint('Error opening URL in new tab: $e');
      setState(() => _isLoading = false);
    }
  }

  void _initWebView() {
    _wvCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kPrimary, _kAccent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.open_in_new, size: 64, color: _kPrimary),
              const SizedBox(height: 24),
              Text(
                'Opening ${widget.title}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'The page will open in a new tab',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile — full WebView with its own AppBar
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _wvCtrl?.reload(),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kPrimary, _kAccent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
      body: _wvCtrl == null
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Stack(
              children: [
                WebViewWidget(controller: _wvCtrl!),
                if (_isLoading)
                  Container(
                    color: Colors.white,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: _kPrimary),
                          SizedBox(height: 16),
                          Text(
                            'Loading…',
                            style: TextStyle(
                              color: _kPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}