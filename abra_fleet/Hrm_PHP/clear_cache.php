<?php
// ============================================================
// PHP CACHE CLEAR UTILITY
// Upload this to: https://www.abra-travels.com/clear_cache.php
// Then visit the URL to clear all PHP caches
// ============================================================

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>🧹 PHP Cache Clear Utility</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
        }
        .success {
            background: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
            border-left: 4px solid #28a745;
        }
        .error {
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
            border-left: 4px solid #dc3545;
        }
        .info {
            background: #d1ecf1;
            color: #0c5460;
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
            border-left: 4px solid #17a2b8;
        }
        .button {
            background: #4CAF50;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            text-decoration: none;
            display: inline-block;
            margin: 10px 5px;
        }
        .button:hover {
            background: #45a049;
        }
        .button-secondary {
            background: #2196F3;
        }
        .button-secondary:hover {
            background: #0b7dda;
        }
        code {
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
        hr {
            border: none;
            border-top: 2px solid #eee;
            margin: 30px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧹 PHP Cache Clear Utility</h1>
        
        <?php
        $cleared = false;
        $errors = [];
        
        // Clear OPcache
        if (function_exists('opcache_reset')) {
            if (opcache_reset()) {
                echo '<div class="success">✅ <strong>OPcache cleared successfully!</strong><br>All compiled PHP files have been removed from memory.</div>';
                $cleared = true;
            } else {
                $errors[] = 'opcache_reset() failed to execute';
            }
        } else {
            $errors[] = 'opcache_reset() function not available';
        }
        
        // Invalidate specific files
        if (function_exists('opcache_invalidate')) {
            $files_to_clear = [
                __FILE__,
                __DIR__ . '/abra_travels_contact_sales.php',
                __DIR__ . '/contact_sales_list_page.php',
            ];
            
            $invalidated = 0;
            foreach ($files_to_clear as $file) {
                if (file_exists($file)) {
                    if (opcache_invalidate($file, true)) {
                        $invalidated++;
                    }
                }
            }
            
            if ($invalidated > 0) {
                echo '<div class="success">✅ <strong>File cache invalidated!</strong><br>Cleared ' . $invalidated . ' specific PHP files from cache.</div>';
                $cleared = true;
            }
        } else {
            $errors[] = 'opcache_invalidate() function not available';
        }
        
        // Clear stat cache
        clearstatcache(true);
        echo '<div class="success">✅ <strong>Stat cache cleared!</strong><br>File system cache has been refreshed.</div>';
        $cleared = true;
        
        // Show errors if any
        if (!empty($errors)) {
            echo '<div class="error">';
            echo '<strong>⚠️ Some operations failed:</strong><br>';
            foreach ($errors as $error) {
                echo '• ' . htmlspecialchars($error) . '<br>';
            }
            echo '</div>';
        }
        
        // Show info about OPcache status
        if (function_exists('opcache_get_status')) {
            $status = opcache_get_status(false);
            if ($status) {
                echo '<div class="info">';
                echo '<strong>📊 OPcache Status:</strong><br>';
                echo '• Enabled: ' . ($status['opcache_enabled'] ? 'Yes' : 'No') . '<br>';
                echo '• Cache Full: ' . ($status['cache_full'] ? 'Yes' : 'No') . '<br>';
                echo '• Restart Pending: ' . ($status['restart_pending'] ? 'Yes' : 'No') . '<br>';
                if (isset($status['opcache_statistics'])) {
                    echo '• Cached Scripts: ' . $status['opcache_statistics']['num_cached_scripts'] . '<br>';
                    echo '• Hits: ' . number_format($status['opcache_statistics']['hits']) . '<br>';
                    echo '• Misses: ' . number_format($status['opcache_statistics']['misses']) . '<br>';
                }
                echo '</div>';
            }
        }
        ?>
        
        <hr>
        
        <h2>🧪 Next Steps:</h2>
        
        <?php if ($cleared): ?>
            <div class="success">
                <strong>✅ Cache has been cleared!</strong><br><br>
                Now test your contact form:
                <ol>
                    <li>Login to admin panel as <code>admin@abrafleet.com</code></li>
                    <li>Go to Tours & Travels → Contact Sales</li>
                    <li>Create a test ticket</li>
                    <li>Check MongoDB database</li>
                </ol>
                
                <strong>Expected Result:</strong><br>
                <code>"creator_email": "admin@abrafleet.com"</code><br>
                <code>"name": "Admin"</code><br>
                <code>"created_by": {"$oid": "..."}</code>
            </div>
        <?php else: ?>
            <div class="error">
                <strong>❌ Cache clearing failed!</strong><br><br>
                OPcache functions are not available on this server.<br>
                You need to contact your hosting provider to clear the cache.
            </div>
        <?php endif; ?>
        
        <hr>
        
        <h2>🔄 Actions:</h2>
        <a href="?" class="button">🔄 Clear Cache Again</a>
        <a href="abra_travels_contact_sales.php" class="button button-secondary">📋 Go to Contact Sales</a>
        
        <hr>
        
        <h2>📝 Server Information:</h2>
        <div class="info">
            <strong>PHP Version:</strong> <?php echo phpversion(); ?><br>
            <strong>Server Time:</strong> <?php echo date('Y-m-d H:i:s'); ?><br>
            <strong>Server Software:</strong> <?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?><br>
            <strong>Document Root:</strong> <?php echo $_SERVER['DOCUMENT_ROOT'] ?? 'Unknown'; ?><br>
            <strong>Script Path:</strong> <?php echo __FILE__; ?><br>
        </div>
        
        <hr>
        
        <h2>⚠️ Important Notes:</h2>
        <div class="info">
            <ul>
                <li>This script clears PHP OPcache which stores compiled PHP code</li>
                <li>After clearing, the server will recompile PHP files on next request</li>
                <li>This may cause a slight performance impact for the first request</li>
                <li>You can delete this file after fixing the issue</li>
                <li>If cache clearing doesn't work, contact your hosting provider</li>
            </ul>
        </div>
        
        <hr>
        
        <p style="text-align: center; color: #666; font-size: 12px;">
            Abra Fleet Management System • Cache Clear Utility v1.0
        </p>
    </div>
</body>
</html>
