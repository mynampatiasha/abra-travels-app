<?php
// ============================================================
// DEBUG: Test URL Parameter Reading
// Upload this file to: https://www.abra-travels.com/test_url_param.php
// Then visit: https://www.abra-travels.com/test_url_param.php?user_email=admin@abrafleet.com
// ============================================================

header('Content-Type: text/html; charset=utf-8');

echo '<h1>🧪 URL Parameter Test</h1>';
echo '<hr>';

echo '<h2>📥 Received Parameters:</h2>';
echo '<pre>';
print_r($_GET);
echo '</pre>';

echo '<h2>✅ Test Results:</h2>';

$user_email = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';

if (!empty($user_email)) {
    echo '<p style="color: green; font-weight: bold;">✅ SUCCESS: user_email parameter received!</p>';
    echo '<p>Email: <strong>' . htmlspecialchars($user_email) . '</strong></p>';
} else {
    echo '<p style="color: red; font-weight: bold;">❌ FAILED: user_email parameter NOT received</p>';
    echo '<p>The URL parameter is missing or empty.</p>';
}

echo '<hr>';
echo '<h2>🔧 Server Info:</h2>';
echo '<p>PHP Version: ' . phpversion() . '</p>';
echo '<p>Server Time: ' . date('Y-m-d H:i:s') . '</p>';
echo '<p>Request URI: ' . htmlspecialchars($_SERVER['REQUEST_URI'] ?? 'N/A') . '</p>';

echo '<hr>';
echo '<h2>📝 Instructions:</h2>';
echo '<ol>';
echo '<li>If you see the email above, the server CAN read URL parameters</li>';
echo '<li>If not, check if mod_rewrite or .htaccess is blocking query strings</li>';
echo '<li>After confirming this works, the main PHP file should work too</li>';
echo '</ol>';
?>
