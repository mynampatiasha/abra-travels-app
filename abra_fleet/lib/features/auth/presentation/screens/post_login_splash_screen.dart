// ============================================================================
// ABRA TRAVELS — POST-LOGIN SPLASH SCREEN
// ============================================================================
// File: lib/features/auth/presentation/screens/post_login_splash_screen.dart
//
// Flow:
//   Login succeeds → push PostLoginSplashScreen → auto-navigates to HomeScreen
//
// Usage:
//   Navigator.pushReplacement(
//     context,
//     MaterialPageRoute(builder: (_) => PostLoginSplashScreen(userName: 'Ravi')),
//   );
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Replace this import with your actual home/dashboard screen ───────────────
// import 'package:abra_fleet/features/home/presentation/screens/home_screen.dart';

// ── Brand colors ──────────────────────────────────────────────────────────────
const Color _blueDark   = Color(0xFF0B1F4B);
const Color _blueMid    = Color(0xFF1E3A8A);
const Color _blueLight  = Color(0xFF3B82F6);
const Color _blueAccent = Color(0xFF60A5FA);
const Color _goldAccent = Color(0xFFFBBF24);

class PostLoginSplashScreen extends StatefulWidget {
  /// Pass the logged-in user's first name for the greeting
  final String userName;

  /// The widget to navigate to after splash completes
  final Widget destination;

  const PostLoginSplashScreen({
    Key? key,
    required this.userName,
    required this.destination,
  }) : super(key: key);

  @override
  State<PostLoginSplashScreen> createState() => _PostLoginSplashScreenState();
}

class _PostLoginSplashScreenState extends State<PostLoginSplashScreen>
    with TickerProviderStateMixin {

  // Ripple rings
  late final AnimationController _rippleCtrl;
  late final List<Animation<double>> _rippleScales;
  late final List<Animation<double>> _rippleOpacities;

  // Logo pop-in
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  // Text reveal
  late final AnimationController _textCtrl;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  // Gold checkmark
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  // Exit fade
  late final AnimationController _exitCtrl;
  late final Animation<double> _exitFade;

  // Orbiting background
  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();

    // ── Orbiting background ──
    _orbitCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();

    // ── Ripple — 4 expanding rings staggered ──
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

    _rippleScales = List.generate(4, (i) =>
      Tween<double>(begin: 0.3, end: 3.5).animate(
        CurvedAnimation(
          parent: _rippleCtrl,
          curve: Interval(i * 0.15, 0.8 + i * 0.05, curve: Curves.easeOut),
        ),
      ),
    );

    _rippleOpacities = List.generate(4, (i) =>
      Tween<double>(begin: 0.35, end: 0.0).animate(
        CurvedAnimation(
          parent: _rippleCtrl,
          curve: Interval(i * 0.15, 0.85 + i * 0.05, curve: Curves.easeOut),
        ),
      ),
    );

    // ── Logo ──
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);

    // ── Text ──
    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));

    // ── Checkmark ──
    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut));

    // ── Exit ──
    _exitCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Ripple starts immediately
    _rippleCtrl.forward();

    // 2. Logo pops in after short delay
    await Future.delayed(const Duration(milliseconds: 300));
    _logoCtrl.forward();

    // 3. Welcome text slides in
    await Future.delayed(const Duration(milliseconds: 500));
    _textCtrl.forward();

    // 4. Checkmark appears
    await Future.delayed(const Duration(milliseconds: 300));
    _checkCtrl.forward();

    // 5. Hold for a moment
    await Future.delayed(const Duration(milliseconds: 1400));

    // 6. Fade out and navigate
    _exitCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 700));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.destination,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _rippleCtrl.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _checkCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_exitCtrl, _orbitCtrl]),
        builder: (_, __) {
          return FadeTransition(
            opacity: _exitFade,
            child: Stack(
              children: [
                // Background
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SplashBgPainter(_orbitCtrl.value),
                  ),
                ),

                // Ripple rings
                Center(
                  child: AnimatedBuilder(
                    animation: _rippleCtrl,
                    builder: (_, __) => SizedBox(
                      width: 300,
                      height: 300,
                      child: Stack(
                        alignment: Alignment.center,
                        children: List.generate(4, (i) => Transform.scale(
                          scale: _rippleScales[i].value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _blueAccent.withOpacity(_rippleOpacities[i].value),
                                width: 1.5,
                              ),
                            ),
                          ),
                        )),
                      ),
                    ),
                  ),
                ),

                // Main content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo with checkmark
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glow behind logo
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _blueAccent.withOpacity(0.4),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          // Logo
                          ScaleTransition(
                            scale: _logoScale,
                            child: FadeTransition(
                              opacity: _logoFade,
                              child: Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 30,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Gold checkmark badge
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: ScaleTransition(
                              scale: _checkScale,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _goldAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _goldAccent.withOpacity(0.6),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // Welcome text
                      FadeTransition(
                        opacity: _textFade,
                        child: SlideTransition(
                          position: _textSlide,
                          child: Column(
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.6),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.userName,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Brand tagline pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions_bus_rounded, color: _blueAccent, size: 14),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ABRA TRAVELS  ·  Your Journey, Our Priority',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              // Loading dots
                              _LoadingDots(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Loading dots ──────────────────────────────────────────────────────────────

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) =>
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
        ..repeat(reverse: true));

    // Stagger the dots
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }

    _anims = _ctrls.map((c) =>
      Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))
    ).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) =>
        AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _blueAccent.withOpacity(_anims[i].value),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _SplashBgPainter extends CustomPainter {
  final double progress;
  _SplashBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0B1F4B), Color(0xFF0D2660), Color(0xFF1A3A8A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    final cx = size.width / 2;
    final cy = size.height / 2;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.35;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70)
        ..color = const Color(0xFF3B82F6).withOpacity(0.1);
      canvas.drawCircle(Offset(x, y), 100, glow);
    }

    // Subtle grid
    final grid = Paint()..color = Colors.white.withOpacity(0.025)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(_SplashBgPainter old) => old.progress != progress;
}