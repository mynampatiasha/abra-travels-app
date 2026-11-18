import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomeGreetingScreen extends StatefulWidget {
  const WelcomeGreetingScreen({super.key});

  @override
  State<WelcomeGreetingScreen> createState() => _WelcomeGreetingScreenState();
}

class _WelcomeGreetingScreenState extends State<WelcomeGreetingScreen> {
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // Treat an empty stored name the same as a missing one.
      final stored = (prefs.getString('user_name') ?? '').trim();
      _userName = stored.isEmpty ? 'User' : stored;
    });
  }

  String get _timeGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 768;

    final double logoSize = isMobile ? 64 : 88;
    final double titleSize = isMobile ? 22 : 30;
    final double subtitleSize = isMobile ? 14 : 16;
    final double cardPadding = isMobile ? 24 : 40;

    return Scaffold(
      body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE3F2FD), Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(cardPadding),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D47A1).withOpacity(0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: EdgeInsets.all(isMobile ? 16 : 22),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFE3F2FD),
                                  Color(0xFFBBDEFB),
                                ],
                              ),
                            ),
                            child: Image.asset(
                              'assets/images/abra_logo.png',
                              width: logoSize,
                              height: logoSize,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                Icons.directions_car,
                                size: logoSize,
                                color: const Color(0xFF0D47A1),
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 20 : 28),
                          Text(
                            _timeGreeting,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: subtitleSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color: const Color(0xFF0D47A1),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Welcome Back, $_userName!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2D3748),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: 56,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D47A1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isMobile
                                ? 'Tap the menu icon at the top left to begin.'
                                : 'Please select an option from the sidebar to begin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: subtitleSize,
                              height: 1.4,
                              color: const Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}
