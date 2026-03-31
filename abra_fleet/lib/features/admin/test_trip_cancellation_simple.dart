// Simple test widget to verify rendering works
import 'package:flutter/material.dart';

class TestTripCancellationSimple extends StatelessWidget {
  const TestTripCancellationSimple({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('🧪 TestTripCancellationSimple building...');
    
    return Container(
      color: Colors.lightBlue.shade50,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 100,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'TEST SCREEN WORKING!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'If you see this, the screen index is correct',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                debugPrint('🧪 Test button clicked!');
              },
              child: const Text('Test Button'),
            ),
          ],
        ),
      ),
    );
  }
}
