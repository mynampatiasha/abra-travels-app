// File: lib/features/auth/data/repositories/mock_auth_repository_impl.dart
// Mock implementation of AuthRepository for testing and development.
// This provides in-memory storage and simulated authentication operations.

import 'dart:async';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';

class MockAuthRepositoryImpl implements AuthRepository {
  // In-memory storage for users and passwords
  final Map<String, UserEntity> _users = {};
  final Map<String, String> _passwords = {};
  // In-memory store for phone numbers to user mapping
  final Map<String, UserEntity> _phoneToUser = {};

  UserEntity _currentUser = UserEntity.empty;
  final StreamController<UserEntity> _userController = StreamController<UserEntity>.broadcast();
  
  // Predefined admin credentials
  static const String adminEmail = 'admin@abrafleet.com';
  static const String adminPassword = 'admin123';

  MockAuthRepositoryImpl() {
    _initializePredefinedUsers();
  }

  @override
  Stream<UserEntity> get user => _userController.stream;

  @override
  UserEntity get currentUser => _currentUser;

  @override
  Future<void> refreshCurrentUser() async {
    // Mock implementation - no actual refresh needed for mock data
    print('[MockAuth] refreshCurrentUser called.');
    return;
  }

  @override
  Future<UserEntity> getCurrentUserWithRole() async {
    // For mock implementation, return current user directly
    return _currentUser;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? name,
    required String role,
    String? phoneNumber,
  }) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay

    if (_users.containsKey(email)) {
      throw Exception('Email already in use.');
    }

    final user = UserEntity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: email,
      name: name,
      role: role.toLowerCase().trim(),
      phoneNumber: phoneNumber,
    );

    _users[email] = user;
    _passwords[email] = password;

    // Map phone number to user if provided
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      _phoneToUser[phoneNumber] = user;
    }

    print('[MockAuth] User registered: $email with role: ${user.role}');
  }

  // --- FIX 1: Corrected return type from Future<void> to Future<String?> ---
  @override
  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay

    if (!_users.containsKey(email)) {
      throw Exception('User not found.');
    }

    if (_passwords[email] != password) {
      throw Exception('Invalid password.');
    }

    _currentUser = _users[email]!;
    _userController.add(_currentUser);
    print('[MockAuth] User signed in: $email');
    
    // Return a mock token on successful login
    return 'mock-firebase-id-token-for-$email';
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
    
    _currentUser = UserEntity.empty;
    _userController.add(_currentUser);
    print('[MockAuth] User signed out');
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate network delay

    if (!_users.containsKey(email)) {
      throw Exception('Email not registered.');
    }

    print('[MockAuth] Password reset email sent to: $email (Mock)');
  }
  
  // --- FIX 2: Added missing getAuthToken method ---
  @override
  Future<String?> getAuthToken() async {
    print('[MockAuth] getAuthToken called.');
    await Future.delayed(const Duration(milliseconds: 50));
    // If a user is logged in, return a token, otherwise null.
    if (_currentUser != UserEntity.empty) {
      return 'mock-firebase-id-token-for-${_currentUser.email}';
    }
    return null;
  }
  
  // --- FIX 3: Added missing updateUserProfile method ---
  @override
  Future<bool> updateUserProfile({
    required String userId,
    String? name,
    String? phoneNumber,
  }) async {
    print('[MockAuth] updateUserProfile called for user $userId');
    await Future.delayed(const Duration(seconds: 1));

    // Find the user by their ID
    UserEntity? userToUpdate;
    String? userEmailKey;

    _users.forEach((email, user) {
      if (user.id == userId) {
        userToUpdate = user;
        userEmailKey = email;
      }
    });

    if (userToUpdate != null && userEmailKey != null) {
      // Create a new user entity with updated details
      final updatedUser = userToUpdate!.copyWith(
        name: name ?? userToUpdate!.name,
        phoneNumber: phoneNumber ?? userToUpdate!.phoneNumber,
      );
      // Update the user in our in-memory map
      _users[userEmailKey!] = updatedUser;
      
      // If the updated user is the current user, update the current user instance
      if (_currentUser.id == userId) {
          _currentUser = updatedUser;
          _userController.add(_currentUser);
      }
      return true; // Indicate success
    }

    return false; // Indicate failure (user not found)
  }

  // --- FIX 4: Added missing getUserProfile method ---
  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    print('[MockAuth] getUserProfile called for user $userId');
    await Future.delayed(const Duration(milliseconds: 300));
    
    UserEntity? foundUser;
    _users.forEach((email, user) {
      if (user.id == userId) {
        foundUser = user;
      }
    });

    if (foundUser != null) {
      // Convert UserEntity to a Map, simulating a Firestore document
      return {
        'email': foundUser!.email,
        'name': foundUser!.name,
        'role': foundUser!.role,
        'phoneNumber': foundUser!.phoneNumber,
      };
    }

    return null; // User not found
  }

  // Helper method to update password for testing
  Future<void> updatePasswordByEmail({
    required String email,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay

    if (!_users.containsKey(email)) {
      throw Exception('Email not registered.');
    }

    _passwords[email] = newPassword;
    print('[MockAuth] Password updated for: $email');
  }

  // Initialize predefined admin user
  void _initializePredefinedUsers() {
    final adminUser = UserEntity(
      id: 'admin_001',
      email: adminEmail,
      name: 'System Administrator',
      role: 'admin',
      phoneNumber: '+1234567890',
    );

    _users[adminEmail] = adminUser;
    _passwords[adminEmail] = adminPassword;
    _phoneToUser['+1234567890'] = adminUser;

    print('[MockAuth] Predefined admin user initialized: $adminEmail');
  }

  @override
  void dispose() {
    _userController.close();
  }
}