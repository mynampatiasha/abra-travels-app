import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/testing/connection_test_screen.dart';
import 'core/services/backend_connection_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
    print("✅ Environment variables loaded");
  } catch (e) {
    print("⚠️ Warning: Could not load .env file: $e");
    // Set default environment variables for web
    dotenv.env['API_BASE_URL'] = 'http://localhost:3001';
    dotenv.env['WEBSOCKET_URL'] = 'ws://localhost:3001';
    print("✅ Using default environment configuration");
  }
  
  try {
    // Initialize Backend Connection Manager
    final connectionManager = BackendConnectionManager();
    await connectionManager.initialize();
    print("✅ Backend Connection Manager initialized");
  } catch (e) {
    print("❌ Backend Connection Manager failed: $e");
  }
  
  runApp(const ConnectionTestApp());
}

class ConnectionTestApp extends StatelessWidget {
  const ConnectionTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backend Connection Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ConnectionTestScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
