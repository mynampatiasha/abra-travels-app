// lib/features/auth/domain/repositories/auth_repository.dart

import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';

abstract class AuthRepository {
  /// Stream of [UserEntity] which will emit the current user when
  /// the authentication state changes.
  ///
  /// Emits [UserEntity.empty] if the user is not authenticated.
  Stream<UserEntity> get user;

  /// Returns the current cached user.
  /// Defaults to [UserEntity.empty] if there is no current user.
  UserEntity get currentUser;

  /// Returns the current user's data with their role from Firestore.
  Future<UserEntity> getCurrentUserWithRole();

  /// Creates a new user with the provided [email] and [password].
  Future<void> signUp({
    required String email,
    required String password,
    String? name,
    required String role,
    String? phoneNumber,
  });

  /// Signs in with the provided [email] and [password].
  ///
  /// Returns the Firebase ID token on success.
  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  
  /// Returns the current user's Firebase ID token.
  ///
  /// Refreshes the token if it's expired.
  Future<String?> getAuthToken();

  /// Signs out the current user.
  Future<void> signOut();

  /// Sends a password reset link to the provided [email].
  Future<void> sendPasswordResetEmail({required String email});
  
  /// Forces a refresh of the current user's data from Firestore.
  Future<void> refreshCurrentUser();

  /// Updates the user's profile information in Firestore.
  Future<bool> updateUserProfile({
    required String userId,
    String? name,
    String? phoneNumber,
  });
  
  /// Fetches the user's full profile data from Firestore.
  Future<Map<String, dynamic>?> getUserProfile(String userId);

  /// Disposes of any resources used by the repository.
  void dispose();
}