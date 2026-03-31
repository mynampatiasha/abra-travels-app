// lib/core/exceptions/auth_exception.dart
// Custom authentication exception to replace FirebaseAuthException

class AuthException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  AuthException({
    required this.code,
    required this.message,
    this.details,
  });

  // Common error codes
  static const String userNotFoundCode = 'user-not-found';
  static const String wrongPasswordCode = 'wrong-password';
  static const String emailAlreadyInUseCode = 'email-already-in-use';
  static const String invalidEmailCode = 'invalid-email';
  static const String weakPasswordCode = 'weak-password';
  static const String tooManyRequestsCode = 'too-many-requests';
  static const String userDisabledCode = 'user-disabled';
  static const String operationNotAllowedCode = 'operation-not-allowed';
  static const String networkErrorCode = 'network-error';
  static const String unauthorizedCode = 'unauthorized';
  static const String tokenExpiredCode = 'token-expired';
  static const String invalidTokenCode = 'invalid-token';
  static const String serverErrorCode = 'server-error';

  // Factory constructors for common errors
  factory AuthException.userNotFound() {
    return AuthException(
      code: userNotFoundCode,
      message: 'No account found with this email address.',
    );
  }

  factory AuthException.wrongPassword() {
    return AuthException(
      code: wrongPasswordCode,
      message: 'Incorrect password. Please try again.',
    );
  }

  factory AuthException.emailAlreadyInUse() {
    return AuthException(
      code: emailAlreadyInUseCode,
      message: 'An account already exists with this email address.',
    );
  }

  factory AuthException.invalidEmail() {
    return AuthException(
      code: invalidEmailCode,
      message: 'Invalid email address format.',
    );
  }

  factory AuthException.weakPassword() {
    return AuthException(
      code: weakPasswordCode,
      message: 'Password is too weak. Use at least 6 characters.',
    );
  }

  factory AuthException.tooManyRequests() {
    return AuthException(
      code: tooManyRequestsCode,
      message: 'Too many requests. Please try again later.',
    );
  }

  factory AuthException.networkError() {
    return AuthException(
      code: networkErrorCode,
      message: 'Network error. Please check your connection.',
    );
  }

  factory AuthException.unauthorized() {
    return AuthException(
      code: unauthorizedCode,
      message: 'Unauthorized. Please login again.',
    );
  }

  factory AuthException.tokenExpired() {
    return AuthException(
      code: tokenExpiredCode,
      message: 'Session expired. Please login again.',
    );
  }

  factory AuthException.serverError() {
    return AuthException(
      code: serverErrorCode,
      message: 'Server error. Please try again later.',
    );
  }

  // Parse backend error response
  factory AuthException.fromBackendError(dynamic error) {
    if (error is Map<String, dynamic>) {
      final code = error['code']?.toString() ?? 'unknown-error';
      final message = error['message']?.toString() ?? 'An error occurred';
      return AuthException(code: code, message: message, details: error);
    }
    
    return AuthException(
      code: 'unknown-error',
      message: error.toString(),
    );
  }

  @override
  String toString() => 'AuthException($code): $message';

  // Get user-friendly error message
  String getUserMessage() {
    switch (code) {
      case userNotFoundCode:
        return 'No account found with this email address.';
      case wrongPasswordCode:
        return 'Incorrect password. Please try again.';
      case emailAlreadyInUseCode:
        return 'An account already exists with this email address.';
      case invalidEmailCode:
        return 'Invalid email address format.';
      case weakPasswordCode:
        return 'Password is too weak. Use at least 6 characters.';
      case tooManyRequestsCode:
        return 'Too many requests. Please try again later.';
      case userDisabledCode:
        return 'This account has been disabled.';
      case networkErrorCode:
        return 'Network error. Please check your connection.';
      case unauthorizedCode:
        return 'Unauthorized. Please login again.';
      case tokenExpiredCode:
        return 'Session expired. Please login again.';
      case serverErrorCode:
        return 'Server error. Please try again later.';
      default:
        return message;
    }
  }
}
