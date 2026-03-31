// ============================================================================
// ABRA TRAVELS — PREMIUM WELCOME SCREEN
// ============================================================================
// File: lib/features/auth/presentation/screens/welcome_screen.dart
// Features:
//   ✅ Premium hero with logo, animated background, glassmorphism cards
//   ✅ 5-step animated progress stepper tour (fleet-themed)
//   ✅ Skip / Get Started → LoginScreen
//   ✅ Fully responsive — desktop two-column, mobile single-column
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'login_screen.dart';

// ── Brand colors ──────────────────────────────────────────────────────────────
const Color _blueDark   = Color(0xFF0B1F4B);
const Color _blueMid    = Color(0xFF1E3A8A);
const Color _blueLight  = Color(0xFF3B82F6);
const Color _blueAccent = Color(0xFF60A5FA);
const Color _goldAccent = Color(0xFFFBBF24);

// ── Tour step model ───────────────────────────────────────────────────────────
class _TourStep {
  final IconData icon;
  final IconData secondaryIcon;
  final String stepLabel;
  final String title;
  final String subtitle;
  final String description;
  final List<String> highlights;
  final Color accentColor;

  const _TourStep({
    required this.icon,
    required this.secondaryIcon,
    required this.stepLabel,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.highlights,
    required this.accentColor,
  });
}

const List<_TourStep> _steps = [
  _TourStep(
    icon: Icons.directions_bus_rounded,
    secondaryIcon: Icons.add_road_rounded,
    stepLabel: 'STEP 01',
    title: 'Fleet Command',
    subtitle: 'Every vehicle. One dashboard.',
    description:
        'Monitor your entire fleet in real time from a single command centre. '
        'Track vehicle health, assign trips, manage maintenance schedules, '
        'and get instant alerts — before issues become breakdowns.',
    highlights: [
      'Real-time vehicle status & location',
      'Maintenance & service scheduling',
      'Fuel consumption tracking',
    ],
    accentColor: Color(0xFF60A5FA),
  ),
  _TourStep(
    icon: Icons.my_location_rounded,
    secondaryIcon: Icons.route_rounded,
    stepLabel: 'STEP 02',
    title: 'Live Trip Tracking',
    subtitle: 'Know exactly where every trip stands.',
    description:
        'Follow every journey from departure to destination with live GPS tracking. '
        'Passengers and operations teams get real-time updates, '
        'estimated arrivals, and instant deviation alerts.',
    highlights: [
      'Live GPS tracking per vehicle',
      'ETA updates & route deviation alerts',
      'Trip history & replay',
    ],
    accentColor: Color(0xFF34D399),
  ),
  _TourStep(
    icon: Icons.event_seat_rounded,
    secondaryIcon: Icons.confirmation_number_rounded,
    stepLabel: 'STEP 03',
    title: 'Smart Bookings',
    subtitle: 'Bookings that run themselves.',
    description:
        'Create, manage, and automate trip bookings with zero friction. '
        'Assign vehicles and drivers instantly, handle recurring routes, '
        'and give passengers a seamless booking experience end to end.',
    highlights: [
      'Quick & recurring trip scheduling',
      'Auto vehicle & driver assignment',
      'Passenger notifications & e-tickets',
    ],
    accentColor: Color(0xFFFBBF24),
  ),
  _TourStep(
    icon: Icons.badge_rounded,
    secondaryIcon: Icons.star_rounded,
    stepLabel: 'STEP 04',
    title: 'Driver Management',
    subtitle: 'Your drivers. Fully empowered.',
    description:
        'Maintain complete driver profiles, track performance scores, '
        'manage licence renewals and compliance documents, '
        'and recognise your best drivers with built-in rating systems.',
    highlights: [
      'Driver profiles & document management',
      'Performance scoring & ratings',
      'Licence & compliance alerts',
    ],
    accentColor: Color(0xFFF472B6),
  ),
  _TourStep(
    icon: Icons.bar_chart_rounded,
    secondaryIcon: Icons.insights_rounded,
    stepLabel: 'STEP 05',
    title: 'Reports & Insights',
    subtitle: 'Data that drives better decisions.',
    description:
        'Unlock powerful operational reports — trip summaries, fleet utilisation, '
        'fuel efficiency, driver performance, and revenue analytics. '
        'Export, schedule, and share reports with your management team.',
    highlights: [
      'Fleet utilisation & efficiency reports',
      'Revenue & cost analytics',
      'Scheduled report delivery',
    ],
    accentColor: Color(0xFFA78BFA),
  ),
];

// ============================================================================
// WELCOME SCREEN
// ============================================================================

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  bool _tourActive = false;
  int _currentStep = 0;

  // Hero animations
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  // Orbiting background
  late final AnimationController _orbitCtrl;

  // Tour animations
  late final AnimationController _stepCtrl;
  late final Animation<double> _stepFade;
  late final Animation<Offset> _stepSlide;
  late final Animation<double> _iconScale;

  // Icon pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Logo bounce
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoFloat;

  @override
  void initState() {
    super.initState();

    _heroCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _orbitCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 18))
      ..repeat();

    _stepCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _stepFade = CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOut);
    _stepSlide = Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOutCubic));
    _iconScale = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.elasticOut));

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _logoFloat = Tween<double>(begin: -6.0, end: 6.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeInOut));

    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _orbitCtrl.dispose();
    _stepCtrl.dispose();
    _pulseCtrl.dispose();
    _logoCtrl.dispose();
    super.dispose();
  }

  void _startTour() {
    setState(() { _tourActive = true; _currentStep = 0; });
    _stepCtrl.forward(from: 0);
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _stepCtrl.reverse().then((_) {
        setState(() => _currentStep++);
        _stepCtrl.forward(from: 0);
      });
    } else {
      _goToLogin();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _stepCtrl.reverse().then((_) {
        setState(() => _currentStep--);
        _stepCtrl.forward(from: 0);
      });
    }
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        return Stack(
          children: [
            // Animated background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _orbitCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _PremiumBgPainter(_orbitCtrl.value),
                ),
              ),
            ),
            // Content
            _tourActive
                ? _buildTourView(isWide)
                : FadeTransition(
                    opacity: _heroFade,
                    child: SlideTransition(
                      position: _heroSlide,
                      child: isWide
                          ? _buildHeroWide()
                          : _buildHeroMobile(),
                    ),
                  ),
          ],
        );
      }),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────────────

  Widget _buildHeroWide() {
    return SafeArea(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1100),
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 32),
          child: Row(
            children: [
              // Left — logo + branding
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogoBlock(large: true),
                    const SizedBox(height: 32),
                    // Overline
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _goldAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: _goldAccent.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: _goldAccent, size: 13),
                          const SizedBox(width: 6),
                          Text(
                            'ENTERPRISE FLEET MANAGEMENT',
                            style: TextStyle(color: _goldAccent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your Journey,\nOur Priority.',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.08,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'From bookings to destinations — ABRA Travels gives you '
                      'complete command over your fleet, drivers, and passenger experience.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        _PrimaryBtn(label: 'Explore Features', icon: Icons.explore_outlined, onTap: _startTour),
                        const SizedBox(width: 14),
                        _GhostBtn(label: 'Sign In', onTap: _goToLogin),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 64),
              // Right — floating logo + stat cards
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFloatingLogo(),
                    const SizedBox(height: 28),
                    _buildStatCards(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroMobile() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Column(
          children: [
            _buildFloatingLogo(size: 110),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _goldAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: _goldAccent.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, color: _goldAccent, size: 12),
                  const SizedBox(width: 6),
                  Text('ENTERPRISE FLEET MANAGEMENT',
                    style: TextStyle(color: _goldAccent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your Journey,\nOur Priority.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.1,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Complete command over your fleet, drivers, and passenger experience.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.65),
            ),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity,
              child: _PrimaryBtn(label: 'Explore Features', icon: Icons.explore_outlined, onTap: _startTour)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: _GhostBtn(label: 'Sign In', onTap: _goToLogin)),
            const SizedBox(height: 36),
            _buildFeaturePills(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoBlock({bool large = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: large ? 52 : 44,
          height: large ? 52 : 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: _blueAccent.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ABRA TRAVELS',
              style: TextStyle(
                color: Colors.white,
                fontSize: large ? 18 : 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              )),
            Text('Fleet Management Platform',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
                letterSpacing: 0.8,
              )),
          ],
        ),
      ],
    );
  }

  Widget _buildFloatingLogo({double size = 160}) {
    return AnimatedBuilder(
      animation: _logoFloat,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _logoFloat.value),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            Container(
              width: size + 60,
              height: size + 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blueAccent.withOpacity(0.07),
              ),
            ),
            Container(
              width: size + 30,
              height: size + 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blueAccent.withOpacity(0.1),
                border: Border.all(color: _blueAccent.withOpacity(0.15), width: 1),
              ),
            ),
            // Main logo circle
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: _blueAccent.withOpacity(0.35), blurRadius: 50, spreadRadius: 5),
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: ClipOval(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.08),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
            ),
            // Small orbit badge
            Positioned(
              right: 8,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _goldAccent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _goldAccent.withOpacity(0.5), blurRadius: 12)],
                ),
                child: const Icon(Icons.verified_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    final stats = [
      (Icons.directions_bus_rounded,  'Vehicles Managed',   '500+',  _blueAccent),
      (Icons.people_rounded,          'Happy Passengers',   '10K+',  const Color(0xFF34D399)),
      (Icons.route_rounded,           'Routes Covered',     '200+',  _goldAccent),
      (Icons.star_rounded,            'Uptime Reliability', '99.9%', const Color(0xFFA78BFA)),
    ];

    return Column(
      children: [
        Row(children: [
          Expanded(child: _StatCard(icon: stats[0].$1, label: stats[0].$2, value: stats[0].$3, color: stats[0].$4)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(icon: stats[1].$1, label: stats[1].$2, value: stats[1].$3, color: stats[1].$4)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _StatCard(icon: stats[2].$1, label: stats[2].$2, value: stats[2].$3, color: stats[2].$4)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(icon: stats[3].$1, label: stats[3].$2, value: stats[3].$3, color: stats[3].$4)),
        ]),
      ],
    );
  }

  Widget _buildFeaturePills() {
    final pills = [
      (Icons.my_location_rounded,     'Live Tracking',    const Color(0xFF34D399)),
      (Icons.event_seat_rounded,      'Smart Booking',    _goldAccent),
      (Icons.badge_rounded,           'Driver Mgmt',      const Color(0xFFF472B6)),
      (Icons.bar_chart_rounded,       'Analytics',        const Color(0xFFA78BFA)),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: pills.map((p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.$3.withOpacity(0.1),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: p.$3.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(p.$1, color: p.$3, size: 14),
            const SizedBox(width: 6),
            Text(p.$2, style: TextStyle(color: p.$3, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      )).toList(),
    );
  }

  // ── TOUR ──────────────────────────────────────────────────────────────────

  Widget _buildTourView(bool isWide) {
    final step = _steps[_currentStep];
    return Stack(
      children: [
        // Skip
        Positioned(
          top: 12, right: 16,
          child: SafeArea(
            child: TextButton.icon(
              onPressed: _goToLogin,
              icon: const Icon(Icons.close, size: 15, color: Colors.white54),
              label: const Text('Skip', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ),
        ),
        Center(
          child: isWide ? _buildTourWide(step) : _buildTourMobile(step),
        ),
      ],
    );
  }

  Widget _buildTourWide(_TourStep step) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 980),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProgressStepper(current: _currentStep, total: _steps.length),
          const SizedBox(height: 44),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: FadeTransition(
                  opacity: _stepFade,
                  child: ScaleTransition(
                    scale: _iconScale,
                    child: _IconPanel(step: step, pulseAnim: _pulseAnim),
                  ),
                ),
              ),
              const SizedBox(width: 52),
              Expanded(
                flex: 6,
                child: FadeTransition(
                  opacity: _stepFade,
                  child: SlideTransition(
                    position: _stepSlide,
                    child: _StepContent(step: step),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          _NavRow(current: _currentStep, total: _steps.length, onPrev: _prevStep, onNext: _nextStep, step: step),
        ],
      ),
    );
  }

  Widget _buildTourMobile(_TourStep step) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
      child: Column(
        children: [
          _ProgressStepper(current: _currentStep, total: _steps.length),
          const SizedBox(height: 32),
          FadeTransition(
            opacity: _stepFade,
            child: ScaleTransition(scale: _iconScale,
              child: _IconPanel(step: step, pulseAnim: _pulseAnim, compact: true)),
          ),
          const SizedBox(height: 28),
          FadeTransition(
            opacity: _stepFade,
            child: SlideTransition(position: _stepSlide,
              child: _StepContent(step: step, centerAlign: true)),
          ),
          const SizedBox(height: 32),
          _NavRow(current: _currentStep, total: _steps.length, onPrev: _prevStep, onNext: _nextStep, step: step),
        ],
      ),
    );
  }
}

// ============================================================================
// BACKGROUND PAINTER — orbiting rings + grid
// ============================================================================

class _PremiumBgPainter extends CustomPainter {
  final double progress;
  _PremiumBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Base gradient
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0B1F4B), Color(0xFF0D2660), Color(0xFF1A3A8A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    // Subtle grid
    final grid = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Orbiting glow circles
    final cx = size.width * 0.75;
    final cy = size.height * 0.25;
    final r = size.width * 0.22;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50)
        ..color = [
          const Color(0xFF3B82F6).withOpacity(0.18),
          const Color(0xFF60A5FA).withOpacity(0.12),
          const Color(0xFF1E3A8A).withOpacity(0.22),
        ][i];
      canvas.drawCircle(Offset(x, y), 80, glow);
    }

    // Bottom left blob
    final blob = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80)
      ..color = const Color(0xFF1E3A8A).withOpacity(0.4);
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.9), 120, blob);

    // Top accent line
    final line = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, _blueAccent.withOpacity(0.6), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_PremiumBgPainter old) => old.progress != progress;
}

// ============================================================================
// SHARED COMPONENTS
// ============================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
        ],
      ),
    );
  }
}

class _ProgressStepper extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressStepper({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(total * 2 - 1, (i) {
            if (i.isOdd) {
              final idx = i ~/ 2;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 28, height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: idx < current ? _blueAccent : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }
            final idx = i ~/ 2;
            final isActive = idx == current;
            final isDone = idx < current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: isActive ? 38 : 28,
              height: isActive ? 38 : 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isActive || isDone
                    ? const LinearGradient(colors: [_blueAccent, _blueLight], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: isActive || isDone ? null : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: isActive ? _blueAccent : isDone ? _blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: isActive ? [BoxShadow(color: _blueAccent.withOpacity(0.55), blurRadius: 14, spreadRadius: 1)] : null,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : Text('${idx + 1}',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                          fontSize: isActive ? 13 : 11,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Text('${current + 1} of $total',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, letterSpacing: 0.5)),
      ],
    );
  }
}

class _IconPanel extends StatelessWidget {
  final _TourStep step;
  final Animation<double> pulseAnim;
  final bool compact;
  const _IconPanel({required this.step, required this.pulseAnim, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = compact ? 100.0 : 140.0;
    final ic = compact ? 44.0 : 62.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: pulseAnim,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: s + 44, height: s + 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: step.accentColor.withOpacity(0.06))),
              Container(width: s + 22, height: s + 22,
                decoration: BoxDecoration(shape: BoxShape.circle, color: step.accentColor.withOpacity(0.1))),
              Container(
                width: s, height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [step.accentColor.withOpacity(0.22), _blueMid.withOpacity(0.6)]),
                  border: Border.all(color: step.accentColor.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(step.icon, color: step.accentColor, size: ic),
              ),
              Positioned(
                bottom: compact ? 8 : 14,
                right: compact ? 8 : 14,
                child: Container(
                  width: compact ? 28 : 36,
                  height: compact ? 28 : 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _blueDark,
                    border: Border.all(color: step.accentColor.withOpacity(0.5), width: 1.5),
                  ),
                  child: Icon(step.secondaryIcon, color: step.accentColor, size: compact ? 14 : 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: step.accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: step.accentColor.withOpacity(0.3)),
          ),
          child: Text(step.stepLabel,
            style: TextStyle(color: step.accentColor, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ),
      ],
    );
  }
}

class _StepContent extends StatelessWidget {
  final _TourStep step;
  final bool centerAlign;
  const _StepContent({required this.step, this.centerAlign = false});

  @override
  Widget build(BuildContext context) {
    final align = centerAlign ? TextAlign.center : TextAlign.left;
    final cross = centerAlign ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: [
        Text(step.title, textAlign: align,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text(step.subtitle, textAlign: align,
          style: TextStyle(color: step.accentColor, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 18),
        Text(step.description, textAlign: align,
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.7)),
        const SizedBox(height: 22),
        ...step.highlights.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisSize: centerAlign ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, color: step.accentColor.withOpacity(0.15)),
                child: Icon(Icons.check_rounded, color: step.accentColor, size: 12),
              ),
              const SizedBox(width: 10),
              Text(h, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        )),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final int current, total;
  final VoidCallback onPrev, onNext;
  final _TourStep step;
  const _NavRow({required this.current, required this.total, required this.onPrev, required this.onNext, required this.step});

  @override
  Widget build(BuildContext context) {
    final isLast = current == total - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (current > 0) ...[
          OutlinedButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.arrow_back_rounded, size: 15),
            label: const Text('Previous'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
          ),
          const SizedBox(width: 14),
        ],
        ElevatedButton.icon(
          onPressed: onNext,
          icon: Icon(isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded, size: 15),
          label: Text(isLast ? 'Get Started' : 'Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: step.accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
        ),
      ],
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.25)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}