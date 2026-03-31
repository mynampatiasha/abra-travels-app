// lib/features/auth/data/repositories/firebase_auth_repository_impl.dart

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/core/services/user_verification_service.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/utils/role_mapper.dart';

class FirebaseAuthRepositoryImpl implements AuthRepository {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final ApiService _apiService;

  // 🔥 CACHE VARIABLES - Prevent redundant API calls
  UserEntity? _cachedUser;
  DateTime? _lastFetch;
  String? _lastUid;

  // Predefined admin credentials
  static const String adminEmail = 'admin@abrafleet.com';
  static const String adminPassword = 'admin123';

  FirebaseAuthRepositoryImpl({
    firebase_auth.FirebaseAuth? firebaseAuth,
    ApiService? apiService,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _apiService = apiService ?? ApiService() {
    // ⚠️ DISABLED: Firebase initialization disabled - using JWT authentication
    // Only initialize admin user in debug mode
    // if (kDebugMode) {
    //   _initializeAdminUserIfNeeded();
    // }
  }

  // Initialize admin user only if it doesn't exist (prevents repeated attempts)
  Future<void> _initializeAdminUserIfNeeded() async {
    try {
      // Check if admin user already exists before attempting creation
      final existingUsers = await _firebaseAuth.fetchSignInMethodsForEmail(adminEmail);
      if (existingUsers.isNotEmpty) {
        print('[FirebaseAuth] Admin user already exists, skipping initialization');
        return;
      }
      
      print('[FirebaseAuth] Admin user not found, creating...');
      await _initializeAdminUser();
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('[FirebaseAuth] FirebaseAuthException checking admin user: ${e.code} - ${e.message}');
      // Silently ignore - admin user will be created on first login if needed
    } catch (e) {
      print('[FirebaseAuth] Error checking admin user existence: $e');
      // Silently ignore - admin user will be created on first login if needed
    }
  }

  // Initialize admin user in Firebase if it doesn't exist
  Future<void> _initializeAdminUser() async {
    print('[FirebaseAuth] Starting admin user initialization...');
    
    try {
      // Ensure we're signed out first
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser != null) {
        print('[FirebaseAuth] Signing out current user before admin creation');
        await _firebaseAuth.signOut();
      }

      print('[FirebaseAuth] Attempting to create admin user: $adminEmail');
      
      // Try to create admin user in Firebase Auth
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: adminEmail,
        password: adminPassword,
      );

      final user = userCredential.user;
      if (user != null) {
        print('[FirebaseAuth] Admin user created with UID: ${user.uid}');
        
        // Create admin user in MongoDB via backend API with admin role
        try {
          await _apiService.loginToBackend(
            firebaseUid: user.uid,
            email: adminEmail,
            name: 'System Administrator',
            role: 'admin',
          );
          print('[FirebaseAuth] Admin user created in MongoDB with admin role');
        } catch (apiError) {
          print('[FirebaseAuth] Warning: Could not create admin in MongoDB: $apiError');
        }
        
        print('[FirebaseAuth] Admin user setup completed successfully');
        
        // Sign out after creation
        await _firebaseAuth.signOut();
        print('[FirebaseAuth] Signed out after admin user creation');
      } else {
        print('[FirebaseAuth] ERROR: User creation returned null');
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        print('[FirebaseAuth] Admin user already exists in Firebase - this is expected');
      } else if (e.code == 'weak-password') {
        print('[FirebaseAuth] ERROR: Admin password is too weak');
      } else if (e.code == 'invalid-email') {
        print('[FirebaseAuth] ERROR: Admin email format is invalid');
      } else {
        print('[FirebaseAuth] FirebaseAuthException: ${e.code} - ${e.message}');
      }
    } catch (e) {
      print('[FirebaseAuth] ERROR initializing admin user: $e');
      print('[FirebaseAuth] Error type: ${e.runtimeType}');
    }
  }

  @override
  Stream<UserEntity> get user {
    return _firebaseAuth.authStateChanges()
      .distinct((prev, next) => prev?.uid == next?.uid) // 🔥 Only emit if UID actually changes
      .asyncMap((firebaseUser) async {
        final timestamp = DateTime.now().toIso8601String();
        print('[$timestamp] Auth state changed - Firebase User: ${firebaseUser?.email}');
        
        if (firebaseUser == null) {
          print('[$timestamp] No Firebase user, returning empty UserEntity');
          _cachedUser = null;
          _lastFetch = null;
          _lastUid = null;
          return UserEntity.empty;
        }
        
        // 🔥 Return cached user if fetched within last 2 MINUTES for same UID
        if (_cachedUser != null && 
            _lastFetch != null && 
            _lastUid == firebaseUser.uid &&
            DateTime.now().difference(_lastFetch!) < const Duration(minutes: 2)) {
          print('[$timestamp] ✅ Using cached user data (cached ${DateTime.now().difference(_lastFetch!).inSeconds}s ago)');
          return _cachedUser!;
        }
        
        // 🔥 If we just logged in and have cached data, use it immediately
        if (_cachedUser != null && _lastUid == firebaseUser.uid) {
          final cacheAge = _lastFetch != null 
              ? DateTime.now().difference(_lastFetch!).inSeconds 
              : 999;
          
          if (cacheAge < 10) {
            print('[$timestamp] ✅ Using fresh login cache (${cacheAge}s old)');
            return _cachedUser!;
          }
        }
        
        print('[$timestamp] Cache miss or expired, fetching from MongoDB...');
        
        // 🔥 Check MongoDB FIRST using UserVerificationService
        try {
          print('[$timestamp] Checking MongoDB for user: ${firebaseUser.email}');
          
          // 🔥 Extended timeout to 15 seconds
          final mongoUserData = await UserVerificationService
            .verifyUserByEmail(firebaseUser.email!)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                print('[$timestamp] ⚠️ MongoDB verification timed out after 15s');
                return null;
              },
            );
          
          if (mongoUserData != null) {
            print('[$timestamp] ✅ Found user in MongoDB');
            
            final rawRole = mongoUserData['role']?.toString();
            final normalizedRole = RoleMapper.normalizeRole(rawRole);
            
            print('[$timestamp] MongoDB Role: "$rawRole" → Normalized: "$normalizedRole"');
            
            final userEntity = UserEntity(
              id: mongoUserData['_id']?.toString() ?? firebaseUser.uid,
              firebaseUid: mongoUserData['firebaseUid']?.toString() ?? firebaseUser.uid,
              email: mongoUserData['email']?.toString() ?? firebaseUser.email,
              name: mongoUserData['name']?.toString() ?? firebaseUser.displayName,
              role: normalizedRole, // ✅ Role from MongoDB
              phoneNumber: mongoUserData['phone']?.toString(),
              photoUrl: mongoUserData['photoUrl']?.toString(),
            );
            
            // 🔥 Cache the result with extended duration
            _cachedUser = userEntity;
            _lastFetch = DateTime.now();
            _lastUid = firebaseUser.uid;
            
            return userEntity;
          }
          
          print('[$timestamp] User not found in MongoDB, checking Firestore...');
          
        } catch (mongoError) {
          print('[$timestamp] ❌ MongoDB check failed: $mongoError');
          
          // 🔥 If we have ANY cached data for this user, use it
          if (_cachedUser != null && _lastUid == firebaseUser.uid) {
            print('[$timestamp] ⚠️ Using stale cache due to MongoDB error');
            return _cachedUser!;
          }
        }
        
        // Fallback to Firestore if MongoDB fails - REMOVED
        // MongoDB is the source of truth, no Firestore fallback needed
        
        // Special handling for admin email
        if (firebaseUser.email == adminEmail) {
          print('[$timestamp] Using super_admin role for admin email');
          final adminEntity = UserEntity(
            id: firebaseUser.uid,
            firebaseUid: firebaseUser.uid,
            email: firebaseUser.email,
            name: firebaseUser.displayName ?? 'System Administrator',
            role: 'super_admin',
          );
          
          _cachedUser = adminEntity;
          _lastFetch = DateTime.now();
          _lastUid = firebaseUser.uid;
          
          return adminEntity;
        }
        
        // 🔥 Final fallback - but DON'T cache this to allow retry
        print('[$timestamp] ⚠️ No data found, defaulting to customer role (NOT CACHED)');
        return UserEntity(
          id: firebaseUser.uid,
          firebaseUid: firebaseUser.uid,
          email: firebaseUser.email,
          name: firebaseUser.displayName,
          role: 'customer',
        );
      });
  }

  @override
  Future<void> refreshCurrentUser() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      print('🔄 Refreshing current user data...');
      
      // 🔥 Clear cache to force fresh fetch
      _cachedUser = null;
      _lastFetch = null;
      _lastUid = null;
      
      // Reload Firebase user first
      await firebaseUser.reload();
      
      // Force trigger auth state change to update UI
      await _refreshAuthState();
      
      print('✅ Current user data refreshed successfully');
    }
  }

  // Force refresh auth state to trigger immediate UI updates
  Future<void> _refreshAuthState() async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser != null) {
        // Reload the current user to trigger auth state change
        await currentUser.reload();
        // Small delay to ensure backend changes are propagated
        await Future.delayed(const Duration(milliseconds: 100));
        print('[FirebaseAuth] Auth state refreshed for immediate UI update');
      }
    } catch (e) {
      print('[FirebaseAuth] Error refreshing auth state: $e');
    }
  }

  @override
  UserEntity get currentUser {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return UserEntity.empty;
    
    return UserEntity(
      id: firebaseUser.uid,
      firebaseUid: firebaseUser.uid,
      email: firebaseUser.email,
      name: firebaseUser.displayName,
    );
  }

  @override
  Future<UserEntity> getCurrentUserWithRole() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return UserEntity.empty;

    try {
      // Fetch user data from backend API (MongoDB)
      final response = await _apiService.getProfile();
      
      if (response['success'] == true && response['user'] != null) {
        final userData = response['user'];
        
        // 🔥 Normalize role here too
        String? rawRole = userData['role']?.toString();
        String normalizedRole = RoleMapper.normalizeRole(rawRole);
        
        return UserEntity(
          id: userData['id']?.toString() ?? userData['_id']?.toString() ?? firebaseUser.uid,
          firebaseUid: userData['firebaseUid']?.toString() ?? firebaseUser.uid,
          email: userData['email']?.toString() ?? firebaseUser.email,
          name: userData['name']?.toString() ?? firebaseUser.displayName,
          role: normalizedRole, // 🔥 Use normalized role
          phoneNumber: userData['phone']?.toString(),
          photoUrl: userData['photoUrl']?.toString(),
        );
      } else {
        print('Backend returned no user data');
        return UserEntity(
          id: firebaseUser.uid,
          firebaseUid: firebaseUser.uid,
          email: firebaseUser.email,
          name: firebaseUser.displayName,
          role: 'customer',
        );
      }
    } catch (e) {
      print('Error fetching user data from backend: $e');
      // Return basic user info if backend fetch fails
      return UserEntity(
        id: firebaseUser.uid,
        firebaseUid: firebaseUser.uid,
        email: firebaseUser.email,
        name: firebaseUser.displayName,
        role: 'customer',
      );
    }
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? name,
    required String role,
    String? phoneNumber,
  }) async {
    try {
      print('Creating Firebase Auth user for: $email');
      
      // Create user in Firebase Auth
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Failed to create user in Firebase Auth');
      }

      print('Firebase Auth user created with UID: ${user.uid}');

      // Update display name if provided
      if (name != null && name.isNotEmpty) {
        await user.updateDisplayName(name);
        print('Display name updated: $name');
      }

      // Create user in MongoDB via backend API with correct role
      await _apiService.loginToBackend(
        firebaseUid: user.uid,
        email: email,
        name: name ?? email.split('@')[0],
        role: role,
      );
      
      print('User created in MongoDB with role: ${role.toLowerCase()}');

    } catch (e) {
      print('Error during sign up: $e');
      rethrow;
    }
  }

  @override
  @override
Future<String?> signInWithEmailAndPassword({
  required String email,
  required String password,
}) async {
  try {
    print('🔐 ========================================');
    print('🔐 STARTING SIGN IN PROCESS');
    print('🔐 ========================================');
    print('🔐 Email: $email');
    
    // ✅ STEP 0: Clear token cache from previous session
    print('🧹 Clearing cached token from previous session...');
    _apiService.clearTokenCache(); // ← ADD THIS LINE
    print('✅ Token cache cleared');
    
    // ✅ STEP 1: Sign in to Firebase
    print('🔐 Step 1: Authenticating with Firebase...');
    final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    print('✅ Firebase authentication successful');
    
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw Exception('Sign in successful but user object is null.');
    }
    
    print('✅ Firebase User UID: ${firebaseUser.uid}');
    
    // ✅ STEP 2: Get Firebase ID token
    print('🔐 Step 2: Retrieving Firebase ID token...');
    final String? idToken = await firebaseUser.getIdToken(true);
    if (idToken == null) {
      throw Exception('Failed to retrieve Firebase ID token after login.');
    }
    
    print('✅ Firebase ID token retrieved successfully');
    
    // ✅ STEP 3: FORCE BACKEND VERIFICATION BEFORE PROCEEDING
    print('🔐 Step 3: Verifying user in MongoDB backend...');
    
    try {
      // 🔥 CRITICAL FIX: Clear any old cached data FIRST
      print('🔥 Clearing old cache before fetching new data...');
      _cachedUser = null;
      _lastFetch = null;
      _lastUid = null;
      
      // Add a small delay to ensure token is fully propagated
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Try to get user profile from backend
      final response = await _apiService.getProfile().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Backend verification timed out, will retry on auth stream');
          return {'success': false, 'message': 'Timeout'};
        },
      );
      
      if (response['success'] == true && response['user'] != null) {
        final userData = response['user'];
        final role = userData['role']?.toString() ?? 'customer';
        
        print('✅ MongoDB verification successful');
        print('✅ User role from backend: $role');
        print('✅ User name: ${userData['name']}');
        
        // ✅ NOW cache the CORRECT, FRESH data
        _cachedUser = UserEntity(
          id: userData['id']?.toString() ?? firebaseUser.uid,
          firebaseUid: userData['firebaseUid']?.toString() ?? firebaseUser.uid,
          email: userData['email']?.toString() ?? firebaseUser.email,
          name: userData['name']?.toString() ?? firebaseUser.displayName,
          role: RoleMapper.normalizeRole(role),
          phoneNumber: userData['phone']?.toString(),
          photoUrl: userData['photoUrl']?.toString(),
        );
        _lastFetch = DateTime.now();
        _lastUid = firebaseUser.uid;
        
        print('✅ User data pre-cached for immediate use');
        print('✅ Cached role: ${_cachedUser!.role}');
        print('✅ This role will be used for navigation');
      } else {
        print('⚠️ MongoDB returned no user data or failed');
        print('⚠️ Response: ${response.toString()}');
        print('⚠️ Will retry on auth stream');
      }
    } catch (e) {
      print('⚠️ MongoDB verification error: $e');
      print('⚠️ Will retry on auth stream');
      // Don't throw error - let auth stream handle it
    }
    
    // ✅ STEP 4: Small delay to ensure everything is ready
    print('🔐 Step 4: Finalizing authentication...');
    await Future.delayed(const Duration(milliseconds: 500));
    
    print('🔐 ========================================');
    print('✅ SIGN IN PROCESS COMPLETED SUCCESSFULLY');
    print('🔐 ========================================');
    
    return idToken;
    
  } catch (e) {
    print('🔐 ========================================');
    print('❌ SIGN IN FAILED');
    print('🔐 ========================================');
    print('❌ Error: $e');
    rethrow;
  }
}
  
  @override
  Future<String?> getAuthToken() async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        print('[FirebaseAuth] No current user found to get token.');
        return null;
      }
      
      // Check if user is still authenticated
      await firebaseUser.reload();
      
      // Force refresh the token to ensure it's valid and not expired
      final String? idToken = await firebaseUser.getIdToken(true);
      if (idToken != null && idToken.isNotEmpty) {
        print('[FirebaseAuth] ✅ Successfully retrieved fresh auth token');
        return idToken;
      } else {
        print('[FirebaseAuth] ⚠️ Token is null or empty after refresh');
        return null;
      }
      
    } on firebase_auth.FirebaseAuthException catch (e) {
      print('[FirebaseAuth] FirebaseAuthException getting token: ${e.code} - ${e.message}');
      if (e.code == 'user-token-expired' || e.code == 'user-disabled') {
        // User needs to re-authenticate
        await signOut();
      }
      return null;
    } catch (e) {
      print('[FirebaseAuth] Error getting auth token: $e');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // 🔥 Clear cache on sign out
      _cachedUser = null;
      _lastFetch = null;
      _lastUid = null;
      
      await _firebaseAuth.signOut();
      print('User signed out successfully');
    } catch (e) {
      print('Error during sign out: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      print('Password reset email sent to: $email');
    } catch (e) {
      print('Error sending password reset email: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Clear cache on dispose
    _cachedUser = null;
    _lastFetch = null;
    _lastUid = null;
  }

  @override
  Future<bool> updateUserProfile({
    required String userId,
    String? name,
    String? phoneNumber,
  }) async {
    try {
      print('[FirebaseAuth] Updating profile for user: $userId');
      
      // Update profile in MongoDB via backend API
      final response = await _apiService.updateProfile(
        name: name,
        phone: phoneNumber,
      );
      
      if (response['success'] == true) {
        print('[FirebaseAuth] Profile updated successfully');
        
        // 🔥 Clear cache to force refresh
        _cachedUser = null;
        _lastFetch = null;
        _lastUid = null;
        
        // Force refresh the auth state to trigger UI updates
        await _refreshAuthState();
        
        return true;
      } else {
        print('[FirebaseAuth] Profile update failed: ${response['message']}');
        return false;
      }
    } catch (e) {
      print('[FirebaseAuth] Error updating user profile: $e');
      return false;
    }
  }
  
  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      print('[FirebaseAuth] Fetching profile for user: $userId');
      
      final response = await _apiService.getProfile();
      
      if (response['success'] == true && response['user'] != null) {
        return response['user'];
      } else {
        print('[FirebaseAuth] User profile not found');
        return null;
      }
    } catch (e) {
      print('[FirebaseAuth] Error fetching user profile: $e');
      return null;
    }
  }
}