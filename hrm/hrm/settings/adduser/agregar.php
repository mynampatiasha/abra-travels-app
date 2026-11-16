<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/user_error.log');

session_start();
require_once('../../database.php');
require_once('../../config.php');

// Log everything
function logMsg($msg) {
    error_log(date('Y-m-d H:i:s') . " - $msg\n", 3, __DIR__ . '/user_error.log');
}

logMsg("=== User creation started ===");

try {
    // Check database connection
    if (!isset($dbConn)) {
        throw new Exception("Database connection not available");
    }
    
    if (!mysqli_ping($dbConn)) {
        throw new Exception("Database connection failed");
    }
    
    logMsg("Database connected");
    
    // Get POST data
    $name_parson = isset($_POST['name_parson']) ? trim($_POST['name_parson']) : '';
    $name        = isset($_POST['name']) ? trim($_POST['name']) : '';
    $email       = isset($_POST['email']) ? trim($_POST['email']) : '';
    $phone       = isset($_POST['phone']) ? trim($_POST['phone']) : '';
    $password    = isset($_POST['pwd']) ? $_POST['pwd'] : '';
    $type        = isset($_POST['type']) ? intval($_POST['type']) : 0;
    
    logMsg("Data received: name=$name, email=$email");
    
    // Validation
    if (empty($name_parson)) {
        throw new Exception("Person name is required");
    }
    if (empty($name)) {
        throw new Exception("Username is required");
    }
    if (empty($email)) {
        throw new Exception("Email is required");
    }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        throw new Exception("Invalid email format");
    }
    if (empty($password)) {
        throw new Exception("Password is required");
    }
    
    logMsg("Validation passed");
    
    // Sanitize
    $name_parson = mysqli_real_escape_string($dbConn, $name_parson);
    $name        = mysqli_real_escape_string($dbConn, $name);
    $email       = mysqli_real_escape_string($dbConn, $email);
    $phone       = mysqli_real_escape_string($dbConn, $phone);
    
    // Hash password
    if (defined('PASS_SALT')) {
        $pwdmd5 = md5(PASS_SALT . $password);
    } else {
        $pwdmd5 = md5($password);
    }
    
    logMsg("Data sanitized and password hashed");
    
    // ✅ FIXED: Check for duplicates PROPERLY
    $check_sql = "SELECT email, name FROM manager_user WHERE email='$email' OR name='$name'";
    $result = mysqli_query($dbConn, $check_sql);
    
    if (!$result) {
        throw new Exception("Database query failed: " . mysqli_error($dbConn));
    }
    
    if ($row = mysqli_fetch_array($result)) {
        // ✅ FIXED: Duplicate found - show error and EXIT
        logMsg("Duplicate found: email=$email or name=$name");
        echo "<script type=\"text/javascript\">
            alert(\"The email $email or username $name is already registered. Please use different credentials.\");
            window.location = \"../../add-new-users.php\";
        </script>";
        exit; // ✅ CRITICAL: Stop here!
    }
    
    logMsg("No duplicates found, proceeding with insert");
    
    // ✅ FIXED: Insert user (only if no duplicate)
    $insert_sql = "INSERT INTO manager_user (name_parson, name, email, phone, pwd, estado, type, date) 
                   VALUES ('$name_parson', '$name', '$email', '$phone', '$pwdmd5', 1, $type, CURDATE())";
    
    logMsg("SQL: $insert_sql");
    
    if (!mysqli_query($dbConn, $insert_sql)) {
        throw new Exception("Insert failed: " . mysqli_error($dbConn));
    }
    
    $user_id = mysqli_insert_id($dbConn);
    logMsg("User created successfully. ID: $user_id");
    
    // ✅ Success
    echo "<script type=\"text/javascript\">
        alert(\"Thank you for your registration. User created successfully!\");
        window.location = \"../../add-new-users.php\";
    </script>";
    exit;
    
} catch (Exception $e) {
    logMsg("ERROR: " . $e->getMessage());
    
    // Show error to user
    echo "<script type=\"text/javascript\">
        alert(\"Error: " . addslashes($e->getMessage()) . "\");
        window.location = \"../../add-new-users.php\";
    </script>";
    exit;
}
?>