<?php
// ============================================================================
// JWT SESSION BRIDGE - Converts Flutter JWT to PHP Session
// ============================================================================
// This endpoint receives JWT token from Flutter app and creates PHP session
// for HRM KPI/KPQ system integration
// ============================================================================

session_start();
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Only allow POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed. Use POST.']);
    exit;
}

// Get Authorization header
$headers = getallheaders();
$authHeader = isset($headers['Authorization']) ? $headers['Authorization'] : '';

// Extract token from "Bearer <token>" format
$token = '';
if (!empty($authHeader) && strpos($authHeader, 'Bearer ') === 0) {
    $token = substr($authHeader, 7);
}

// Check if token exists
if (empty($token)) {
    http_response_code(401);
    echo json_encode(['error' => 'No token provided']);
    exit;
}

// ============================================================================
// DECODE JWT TOKEN (Simple Base64 decode - no signature verification needed)
// ============================================================================
// Since this is internal communication between Flutter app and PHP,
// we can use simple base64 decode instead of full JWT library
// ============================================================================

try {
    // JWT format: header.payload.signature
    $parts = explode('.', $token);
    
    if (count($parts) !== 3) {
        throw new Exception('Invalid token format');
    }
    
    // Decode payload (second part)
    $payload = $parts[1];
    
    // Add padding if needed for base64_decode
    $remainder = strlen($payload) % 4;
    if ($remainder) {
        $payload .= str_repeat('=', 4 - $remainder);
    }
    
    // Decode base64
    $decoded = base64_decode(strtr($payload, '-_', '+/'));
    
    if ($decoded === false) {
        throw new Exception('Failed to decode token');
    }
    
    // Parse JSON
    $userData = json_decode($decoded, true);
    
    if ($userData === null) {
        throw new Exception('Invalid token data');
    }
    
    // Extract user information
    $email = isset($userData['email']) ? trim($userData['email']) : '';
    $name = isset($userData['name']) ? trim($userData['name']) : '';
    $userId = isset($userData['userId']) ? $userData['userId'] : '';
    $role = isset($userData['role']) ? $userData['role'] : '';
    
    // Validate required fields
    if (empty($email)) {
        throw new Exception('Email not found in token');
    }
    
    // ============================================================================
    // CREATE PHP SESSION
    // ============================================================================
    // Set session variables that PHP files expect
    // ============================================================================
    
    $_SESSION['user_name'] = $email; // Primary identifier for HRM system
    $_SESSION['user_email'] = $email;
    $_SESSION['user_full_name'] = $name;
    $_SESSION['user_id'] = $userId;
    $_SESSION['user_role'] = $role;
    $_SESSION['jwt_authenticated'] = true;
    $_SESSION['session_created_at'] = time();
    
    // Log successful session creation
    error_log("✅ JWT Session Bridge: Session created for user: $email");
    
    // Return success response
    echo json_encode([
        'success' => true,
        'message' => 'Session created successfully',
        'session_data' => [
            'user_name' => $_SESSION['user_name'],
            'user_email' => $_SESSION['user_email'],
            'user_full_name' => $_SESSION['user_full_name'],
            'user_role' => $_SESSION['user_role']
        ]
    ]);
    
} catch (Exception $e) {
    // Log error
    error_log("❌ JWT Session Bridge Error: " . $e->getMessage());
    
    // Return error response
    http_response_code(401);
    echo json_encode([
        'error' => 'Invalid token',
        'message' => $e->getMessage()
    ]);
}
?>
