// File: lib/features/auth/presentation/screens/splash_screen.dart
// Splash screen that listens to authentication state and navigates to MainAppShell or WelcomeScreen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'welcome_screen.dart';
import 'package:abra_fleet/app/presentation/screens/main_app_shell.dart'; // Import MainAppShell

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<UserEntity>? _userSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToAuthChanges();
    });
  }

  void _listenToAuthChanges() {
    if (!mounted) return;
    
    final authRepository = Provider.of<AuthRepository>(context, listen: false);
    _userSubscription?.cancel();

    _userSubscription = authRepository.user.listen((user) {
      if (!mounted) return;
      
      Future.delayed(const Duration(milliseconds: 1500), () { // Keep a slight delay for splash visibility
        if (!mounted) return;

        if (user.isAuthenticated && user.role != null && user.role!.isNotEmpty) {
          print('[SplashScreen] User Authenticated. Role: ${user.role}. Navigating to MainAppShell.');
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainAppShell()), // Navigate to MainAppShell
            );
          }
        } else {
          if (user.isAuthenticated && (user.role == null || user.role!.isEmpty)) {
            print('[SplashScreen] User Authenticated but role is missing/empty. Navigating to Welcome Screen.');
          } else {
            print('[SplashScreen] User Unauthenticated. Navigating to Welcome Screen.');
          }
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            );
          }
        }
      });
    }, onError: (error) {
      print('[SplashScreen] Error in auth stream: $error. Navigating to Welcome Screen.');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Abra Travels Manager',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
