// File: lib/app/presentation/screens/main_app_shell.dart
// This widget acts as a wrapper after login, directing to the correct role-based UI.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';

import 'package:abra_fleet/features/notifications/presentation/providers/notification_provider.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:abra_fleet/features/admin/shell/admin_main_shell.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/driver_main_parent_screen.dart';
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/customer_main_parent_screen.dart';

// ── Brand colors (matches welcome/login screens) ──────────────────────────────
const Color _blueDark   = Color(0xFF0B1F4B);
const Color _blueMid    = Color(0xFF1E3A8A);
const Color _blueLight  = Color(0xFF3B82F6);
const Color _blueAccent = Color(0xFF60A5FA);

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});
  static const String routeName = '/main_shell';

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<NotificationProvider>(context, listen: false)
          .fetchUnreadNotificationCount();
    });
  }

  Widget _buildNotificationBadge(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notificationProvider, child) {
        final unreadCount = notificationProvider.unreadCount;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const NotificationsScreen()),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8)),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLogoutButton(
      BuildContext context, AuthRepository authRepository) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Logout',
      onPressed: () async {
        await authRepository.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const WelcomeScreen()),
            (Route<dynamic> route) => false,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authRepository =
        Provider.of<AuthRepository>(context, listen: false);

    return StreamBuilder<UserEntity>(
      stream: authRepository.user,
      builder: (context, snapshot) {

        // ── BRANDED loading state (replaces plain white scaffold) ──────────
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _BrandedLoadingScreen();
        }

        if (snapshot.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            authRepository.signOut();
          });
          return const _BrandedLoadingScreen();
        }

        final currentUser = snapshot.data;

        if (currentUser == null ||
            currentUser == UserEntity.empty ||
            !currentUser.isAuthenticated) {
          return const WelcomeScreen();
        }

        if (currentUser.role == null || currentUser.role!.trim().isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Account Setup Required'),
              actions: [_buildLogoutButton(context, authRepository)],
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text('No role assigned to your account'),
                  const SizedBox(height: 8),
                  const Text('Please contact support for assistance'),
                  const SizedBox(height: 8),
                  Text('User: ${currentUser.email}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => authRepository.signOut(),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          );
        }

        final userRole = currentUser.role!.toLowerCase().trim();
        print('🔄 [MainAppShell] Routing user with role: "$userRole"');

        switch (userRole) {
          case 'admin':
          case 'super_admin':
          case 'superadmin':
          case 'employee':
          case 'org_admin':
          case 'hr_manager':
          case 'fleet_manager':
          case 'finance':
          case 'operations':
            print('✅ [MainAppShell] Routing to AdminMainShell');
            return AdminMainShell(authRepository: authRepository);

          case 'driver':
            print('✅ [MainAppShell] Routing to DriverMainShell');
            return const DriverMainShell();

          case 'customer':
            print('✅ [MainAppShell] Routing to CustomerMainScreen');
            return const CustomerMainScreen();

          default:
            return Scaffold(
              appBar: AppBar(
                title: const Text('Account Setup Required'),
                actions: [_buildLogoutButton(context, authRepository)],
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(
                      'Unknown Role: "$userRole"',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        'Please contact support to assign a proper role'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => authRepository.signOut(),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

// ============================================================================
// BRANDED LOADING SCREEN — shown while StreamBuilder awaits user data
// Matches the navy theme of welcome/login screens
// ============================================================================

class _BrandedLoadingScreen extends StatefulWidget {
  const _BrandedLoadingScreen();

  @override
  State<_BrandedLoadingScreen> createState() =>
      _BrandedLoadingScreenState();
}

class _BrandedLoadingScreenState extends State<_BrandedLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbitCtrl;
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();

    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..repeat();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoCtrl.forward();

    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _logoCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Navy background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) =>
                  CustomPaint(painter: _LoadingBgPainter(_orbitCtrl.value)),
            ),
          ),

          // Centred content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                ScaleTransition(
                  scale: _logoScale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
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
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Image.asset('assets/logo.png',
                                fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Brand name
                const Text(
                  'ABRA TRAVELS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fleet Management Platform',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 40),

                // Animated loading dots
                AnimatedBuilder(
                  animation: _dotCtrl,
                  builder: (_, __) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final delay = i / 3;
                        final progress = (_dotCtrl.value - delay).clamp(0.0, 1.0);
                        final opacity = math.sin(progress * math.pi).clamp(0.2, 1.0);
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _blueAccent.withOpacity(opacity),
                          ),
                        );
                      }),
                    );
                  },
                ),

                const SizedBox(height: 16),

                Text(
                  'Setting up your workspace...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBgPainter extends CustomPainter {
  final double progress;
  _LoadingBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF0B1F4B),
          Color(0xFF0D2660),
          Color(0xFF1A3A8A),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    // Grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Orbiting glow
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.28;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
        ..color = _blueAccent.withOpacity(0.1);
      canvas.drawCircle(
          Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
          80, glow);
    }
  }

  @override
  bool shouldRepaint(_LoadingBgPainter old) => old.progress != progress;
}