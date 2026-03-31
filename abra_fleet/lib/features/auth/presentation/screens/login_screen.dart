// ============================================================================
// ABRA TRAVELS — PREMIUM LOGIN SCREEN
// ============================================================================
// File: lib/features/auth/presentation/screens/login_screen.dart
// ✅ No left panel — centred layout on all screen sizes
// ✅ Logo + title centred at top
// ✅ Horizontal 4-step row above card
// ✅ Navy glassmorphism card — pure white text everywhere
// ✅ All font sizes +2px
// ✅ Post-login splash screen injected for all roles
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/data/repositories/jwt_auth_repository_impl.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'registration_screen.dart';
import 'forgot_password_screen.dart';
import 'post_login_splash_screen.dart';
import 'package:abra_fleet/app/presentation/screens/main_app_shell.dart';
import 'package:abra_fleet/features/client/client_main_shell.dart';

// ── Brand colors ──────────────────────────────────────────────────────────────
const Color _blueDark   = Color(0xFF0B1F4B);
const Color _blueMid    = Color(0xFF1E3A8A);
const Color _blueLight  = Color(0xFF3B82F6);
const Color _blueAccent = Color(0xFF60A5FA);
const Color _goldAccent = Color(0xFFFBBF24);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;
  bool _isLoading  = false;

  late final AnimationController _orbitCtrl;
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _entranceFade;
  late final Animation<Offset>   _entranceSlide;
  late final AnimationController _btnCtrl;
  late final Animation<double>   _btnScale;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _entranceFade  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _btnCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _btnScale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _orbitCtrl.dispose();
    _entranceCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  // ── Navigation with splash ─────────────────────────────────────────────────
  void _navigateBasedOnRole(String role, String userName) {
    debugPrint('[LoginScreen] Navigating with role: $role, userName: $userName');
    Widget destination;
    if (role == 'client') {
      destination = ClientMainShell();
    } else if ([
      'super_admin', 'admin', 'employee', 'org_admin',
      'fleet_manager', 'hr_manager', 'operations',
      'finance', 'customer', 'driver'
    ].contains(role)) {
      destination = MainAppShell();
    } else {
      debugPrint('[LoginScreen] Unknown role: $role');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login successful but role unclear ($role). Contact support.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostLoginSplashScreen(
          userName: userName,
          destination: destination,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ── Login logic ────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final authRepository    = Provider.of<AuthRepository>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final token = await authRepository.signInWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      if (token == null) throw Exception('Login failed - no token received');

      await Future.delayed(const Duration(milliseconds: 100));
      final user = await authRepository.getCurrentUserWithRole();
      if (user.isEmpty) throw Exception('Failed to get user information');

      debugPrint('[LoginScreen] Login OK — role: ${user.role}, name: ${user.name}');

      if (mounted) {
        final userName = (user.name?.isNotEmpty == true)
            ? user.name!
            : (user.email?.split('@')[0] ?? 'User');
        _navigateBasedOnRole(user.role ?? 'customer', userName);
      }
    } catch (e) {
      debugPrint('❌ Login error: $e');
      if (mounted) {
        String msg = 'Login failed';
        if (e.toString().contains('Invalid credentials') ||
            e.toString().contains('Email or password is incorrect')) {
          msg = 'Invalid email or password';
        } else if (e.toString().contains('Account inactive')) {
          msg = 'Your account is inactive. Contact administrator.';
        } else if (e.toString().contains('User not found')) {
          msg = 'No account found with this email';
        } else {
          msg = 'Login failed: ${e.toString()}';
        }
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) => CustomPaint(
                painter: _LoginBgPainter(_orbitCtrl.value),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoBadge(),
                          const SizedBox(height: 24),
                          const Text(
                            'Welcome Back.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to your fleet command centre.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                height: 1.5),
                          ),
                          const SizedBox(height: 32),
                          _buildHorizontalSteps(),
                          const SizedBox(height: 32),
                          _buildLoginCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo badge ─────────────────────────────────────────────────────────────
  Widget _buildLogoBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _blueAccent.withOpacity(0.45), blurRadius: 20, spreadRadius: 2)],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ABRA TRAVELS',
                style: TextStyle(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w800, letterSpacing: 2)),
            Text('Fleet Management Platform',
                style: TextStyle(color: Colors.white, fontSize: 10,
                    letterSpacing: 0.8)),
          ],
        ),
      ],
    );
  }

  // ── Horizontal 4-step row ──────────────────────────────────────────────────
  Widget _buildHorizontalSteps() {
    final steps = [
      (Icons.lock_outline_rounded,   '01', 'Secure Login'),
      (Icons.verified_user_rounded,  '02', 'Role Verified'),
      (Icons.check_circle_outline,   '03', 'Access Granted'),
      (Icons.dashboard_rounded,      '04', 'Dashboard Ready'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          );
        }
        final s = steps[i ~/ 2];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_blueAccent, _blueLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: _blueAccent.withOpacity(0.4), blurRadius: 12, spreadRadius: 1),
                ],
              ),
              child: Icon(s.$1, color: Colors.white, size: 17),
            ),
            const SizedBox(height: 6),
            Text(s.$2,
                style: const TextStyle(
                    color: _blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(s.$3,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        );
      }),
    );
  }

  // ── Login card ─────────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sign In',
                style: TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            const Text('Enter your credentials to continue',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 28),

            _buildField(
              controller: _emailCtrl,
              label: 'Email Address',
              hint: 'you@abragroup.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your email';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v))
                  return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildField(
              controller: _passCtrl,
              label: 'Password',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white, size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your password';
                return null;
              },
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen())),
                style: TextButton.styleFrom(
                  foregroundColor: _blueAccent,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot Password?',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),

            ScaleTransition(
              scale: _btnScale,
              child: GestureDetector(
                onTapDown: (_) => _btnCtrl.forward(),
                onTapUp: (_) => _btnCtrl.reverse(),
                onTapCancel: () => _btnCtrl.reverse(),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blueAccent,
                    disabledBackgroundColor: _blueAccent.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Sign In', style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
            ]),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?",
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const RegistrationScreen())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Register Now',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700, color: _goldAccent)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, color: _blueAccent, size: 14),
                  SizedBox(width: 8),
                  Text('Secured with JWT authentication',
                      style: TextStyle(color: Colors.white, fontSize: 11,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Field — pure white text, font +2 ──────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blueAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 12),
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────
class _LoginBgPainter extends CustomPainter {
  final double progress;
  _LoginBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0B1F4B), Color(0xFF0D2660), Color(0xFF1A3A8A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()..color = Colors.white.withOpacity(0.025)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final cx = size.width * 0.5;
    final cy = size.height * 0.4;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.18;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
        ..color = [
          const Color(0xFF3B82F6).withOpacity(0.14),
          const Color(0xFF60A5FA).withOpacity(0.10),
          const Color(0xFF1E3A8A).withOpacity(0.18),
        ][i];
      canvas.drawCircle(
          Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)), 70, glow);
    }

    final line = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, const Color(0xFF60A5FA).withOpacity(0.6), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_LoginBgPainter old) => old.progress != progress;
}