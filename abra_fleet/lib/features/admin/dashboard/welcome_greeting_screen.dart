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
    setState(() {
      _userName = prefs.getString('user_name') ?? 'User';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/abra_logo.png', // Fallback to icon if this doesn't exist
                width: 80,
                height: 80,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.directions_car,
                  size: 80,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Welcome Back, $_userName!',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Please select an option from the sidebar to begin.',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF718096),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
