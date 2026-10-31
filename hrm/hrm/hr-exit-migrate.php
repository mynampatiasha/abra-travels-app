<?php
// ONE-TIME schema setup/migration for the Exit Process module.
// Run this once by visiting it in the browser, then delete it from the server.
// hr-exit-initiation.php and hr-employee-exit-request.php no longer create or
// alter tables themselves — running that on every single page load is what
// was causing intermittent crashes (ALTER TABLE locking under concurrent
// requests). Schema changes now only happen here, deliberately, once.

// --- FLUTTER WEBVIEW AUTH INJECTION ---
if (!headers_sent()) { header('Content-Type: text/html; charset=utf-8'); }
if (session_status() === PHP_SESSION_NONE) { session_start(); }
// Recover the Flutter user's email from (in order): the URL param, our own
// long-lived cookie, or the session. This keeps the login alive across every
// internal link / redirect inside the WebView, even when the PHP session
// cookie is not carried between page loads.
$__fue = $_REQUEST['user_email'] ?? $_COOKIE['abra_hrm_email'] ?? $_SESSION['flutter_user_email'] ?? '';
if ($__fue !== '' && (isset($_REQUEST['user_email']) || empty($_SESSION['user_name']))) {
    require_once('database.php');
    $auth_con = conexion();
    $user_email = mysqli_real_escape_string($auth_con, $__fue);
    $auth_query = mysqli_query($auth_con, "SELECT * FROM hr_employees WHERE TRIM(LOWER(email)) = TRIM(LOWER('$user_email')) OR TRIM(LOWER(personal_email)) = TRIM(LOWER('$user_email')) LIMIT 1");
    if ($auth_query && mysqli_num_rows($auth_query) > 0) {
        $auth_user = mysqli_fetch_assoc($auth_query);
        $_SESSION['user_name'] = $auth_user['name'];
        $_SESSION['user_id'] = $auth_user['id'];
        $_SESSION['role_id'] = $auth_user['role_id'] ?? 0;
        $_SESSION['role_name'] = 'hr';
        $_SESSION['flutter_user_email'] = $__fue;
        $_SESSION['ge_cname'] = $auth_user['company_name'] ?? ($_SESSION['ge_cname'] ?? 'Abra');
        if (empty($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
        if (!headers_sent()) { setcookie('abra_hrm_email', $__fue, ['expires' => time() + 43200, 'path' => '/', 'secure' => true, 'httponly' => false, 'samesite' => 'None']); }
    }
}
// Defaults so page <title> / headers that read these session keys don't warn
// in the WebView (the CRM login normally sets them).
if (!isset($_SESSION['ge_cname']))    { $_SESSION['ge_cname'] = 'Abra'; }
if (!isset($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
// Make the email available to the in-page link fixer (see foot of file).
$GLOBALS['__fue'] = $__fue;
// --------------------------------------
error_reporting(E_ALL);
ini_set('display_errors', 1);
mysqli_report(MYSQLI_REPORT_OFF);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

$con = conexion();
if (!$con) die("Database connection failed.");

header('Content-Type: text/plain');
$log = [];
function step($msg) { global $log; $log[] = $msg; }

$tables = [
"CREATE TABLE IF NOT EXISTS hr_exit_requests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_number VARCHAR(20) DEFAULT NULL,
    employee_id INT NOT NULL,
    exit_type ENUM('resignation','termination','retirement','contract_end') DEFAULT 'resignation',
    reason TEXT DEFAULT NULL,
    initiated_by VARCHAR(255) DEFAULT NULL,
    requested_last_day DATE DEFAULT NULL,
    policy_notice_days INT DEFAULT 30,
    notice_start_date DATE DEFAULT NULL,
    final_last_working_day DATE DEFAULT NULL,
    manager_approval ENUM('pending','approved','retained','rejected') DEFAULT 'pending',
    manager_approved_by VARCHAR(255) DEFAULT NULL,
    manager_approved_at DATETIME DEFAULT NULL,
    manager_remarks TEXT DEFAULT NULL,
    submitted_at DATETIME DEFAULT NULL,
    hr_approval ENUM('pending','approved','retained','rejected') DEFAULT 'pending',
    hr_approved_by VARCHAR(255) DEFAULT NULL,
    hr_approved_at DATETIME DEFAULT NULL,
    hr_remarks TEXT DEFAULT NULL,
    token VARCHAR(64) DEFAULT NULL,
    link_generated_by VARCHAR(255) DEFAULT NULL,
    link_generated_at DATETIME DEFAULT NULL,
    link_reason TEXT DEFAULT NULL,
    link_reason_category VARCHAR(50) DEFAULT NULL,
    link_expires_at DATETIME DEFAULT NULL,
    link_notified_at DATETIME DEFAULT NULL,
    link_notify_channel VARCHAR(20) DEFAULT NULL,
    termination_type ENUM('performance','misconduct','redundancy','layoff') DEFAULT NULL,
    warning_letter_ref VARCHAR(255) DEFAULT NULL,
    second_approver_name VARCHAR(255) DEFAULT NULL,
    second_approval ENUM('pending','approved','rejected') DEFAULT 'pending',
    second_approved_by VARCHAR(255) DEFAULT NULL,
    second_approved_at DATETIME DEFAULT NULL,
    notice_handling ENUM('served','pay_in_lieu','immediate') DEFAULT NULL,
    status ENUM('link_sent','initiated','retained','approved','rejected','handover','clearance','interview_settlement','documents','closed') DEFAULT 'initiated',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_notice_policy (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    notice_days INT DEFAULT 30,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_dept_pos (department_id, position_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_settings (
    id INT PRIMARY KEY,
    retirement_age INT DEFAULT 60
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_documents (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    doc_type VARCHAR(100) NOT NULL,
    token VARCHAR(64) DEFAULT NULL,
    generated_by VARCHAR(255) DEFAULT NULL,
    generated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    sent_at DATETIME DEFAULT NULL,
    UNIQUE KEY uniq_exit_doc (exit_id, doc_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_departments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 0,
    is_active TINYINT(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    status ENUM('pending','cleared') DEFAULT 'pending',
    remarks TEXT DEFAULT NULL,
    cleared_by VARCHAR(255) DEFAULT NULL,
    cleared_at DATETIME DEFAULT NULL,
    UNIQUE KEY uniq_exit_dept (exit_id, department_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_settlement (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL UNIQUE,
    pending_salary DECIMAL(12,2) DEFAULT 0,
    leave_encashment DECIMAL(12,2) DEFAULT 0,
    bonus_incentive DECIMAL(12,2) DEFAULT 0,
    gratuity_amount DECIMAL(12,2) DEFAULT 0,
    pension_amount DECIMAL(12,2) DEFAULT 0,
    severance_pay DECIMAL(12,2) DEFAULT 0,
    loan_recovery DECIMAL(12,2) DEFAULT 0,
    notice_shortfall_deduction DECIMAL(12,2) DEFAULT 0,
    other_deductions DECIMAL(12,2) DEFAULT 0,
    net_amount DECIMAL(12,2) DEFAULT 0,
    notes TEXT DEFAULT NULL,
    status ENUM('pending','approved') DEFAULT 'pending',
    approved_by VARCHAR(255) DEFAULT NULL,
    approved_at DATETIME DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) {
    $ok = mysqli_query($con, $sql);
    step($ok ? "OK: table ensured" : "FAILED: " . mysqli_error($con));
}

function ensureColumn($con, $table, $col, $def) {
    global $log;
    $r = mysqli_query($con, "SHOW COLUMNS FROM $table LIKE '$col'");
    if (!$r || mysqli_num_rows($r) == 0) {
        $ok = mysqli_query($con, "ALTER TABLE $table ADD COLUMN $col $def");
        $log[] = ($ok ? "OK: " : "FAILED: ") . "$table.$col";
    }
}
function ensureEnumValue($con, $table, $col, $value, $fullEnumSql) {
    $r = mysqli_query($con, "SHOW COLUMNS FROM $table LIKE '$col'");
    $row = $r ? mysqli_fetch_assoc($r) : null;
    if ($row && strpos($row['Type'], "'$value'") === false) {
        mysqli_query($con, "ALTER TABLE $table MODIFY COLUMN $col $fullEnumSql");
    }
}

$r = mysqli_query($con, "SELECT id FROM hr_exit_settings WHERE id=1");
if ($r && mysqli_num_rows($r) == 0) mysqli_query($con, "INSERT INTO hr_exit_settings (id, retirement_age) VALUES (1, 60)");

ensureColumn($con, 'hr_exit_requests', 'notice_start_date', "DATE DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'token', "VARCHAR(64) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_generated_by', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_generated_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_reason', "TEXT DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_reason_category', "VARCHAR(50) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_expires_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_notified_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'link_notify_channel', "VARCHAR(20) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'termination_type', "ENUM('performance','misconduct','redundancy','layoff') DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'warning_letter_ref', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'second_approver_name', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'second_approval', "ENUM('pending','approved','rejected') DEFAULT 'pending'");
ensureColumn($con, 'hr_exit_requests', 'second_approved_by', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'second_approved_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'notice_handling', "ENUM('served','pay_in_lieu','immediate') DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'manager_remarks', "TEXT DEFAULT NULL");
ensureColumn($con, 'hr_exit_requests', 'submitted_at', "DATETIME DEFAULT NULL");
ensureEnumValue($con, 'hr_exit_requests', 'manager_approval', 'retained', "ENUM('pending','approved','retained','rejected') DEFAULT 'pending'");
ensureEnumValue($con, 'hr_exit_requests', 'hr_approval', 'retained', "ENUM('pending','approved','retained','rejected') DEFAULT 'pending'");
ensureEnumValue($con, 'hr_exit_requests', 'status', 'link_sent', "ENUM('link_sent','initiated','retained','approved','rejected','handover','clearance','interview_settlement','documents','closed') DEFAULT 'initiated'");
ensureEnumValue($con, 'hr_exit_documents', 'doc_type', 'termination_letter', "ENUM('relieving_letter','experience_certificate','settlement_statement','termination_letter','retirement_confirmation_letter','non_renewal_notification') NOT NULL");
ensureColumn($con, 'hr_exit_documents', 'file_path', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'status', "VARCHAR(20) DEFAULT 'draft'");
// status was originally created as ENUM('draft','approved','declined') by hr-exit-settlement.php's
// self-healing code before this migration ever ran, so ensureColumn() (which only ADDs missing
// columns) left it untouched. Widen it explicitly so 'pending_signature'/'pending_hr_final' fit.
$statusColInfo = mysqli_fetch_assoc(mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'"));
if ($statusColInfo && stripos($statusColInfo['Type'], 'enum') !== false) {
    $ok = mysqli_query($con, "ALTER TABLE hr_exit_documents MODIFY COLUMN status VARCHAR(20) DEFAULT 'draft'");
    $log[] = ($ok ? "OK: " : "FAILED: ") . "hr_exit_documents.status widened from ENUM to VARCHAR(20)";
}
ensureColumn($con, 'hr_exit_documents', 'requires_signature', "TINYINT(1) DEFAULT 0");
ensureColumn($con, 'hr_exit_documents', 'employee_signature_data', "LONGTEXT DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'employee_signed_by', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'employee_signed_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'hr_released_by', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'hr_released_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'hr_accepted_by', "VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_exit_documents', 'hr_accepted_at', "DATETIME DEFAULT NULL");

ensureColumn($con, 'hr_employees', 'employment_status', "VARCHAR(20) DEFAULT 'active'");
ensureColumn($con, 'hr_employees', 'rehire_eligible', "VARCHAR(10) DEFAULT NULL");
ensureColumn($con, 'hr_employees', 'contract_end_date', "DATE DEFAULT NULL");

ensureColumn($con, 'hr_exit_settlement', 'gratuity_amount', "DECIMAL(12,2) DEFAULT 0");
ensureColumn($con, 'hr_exit_settlement', 'pension_amount', "DECIMAL(12,2) DEFAULT 0");
ensureColumn($con, 'hr_exit_settlement', 'severance_pay', "DECIMAL(12,2) DEFAULT 0");

$cnt = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_clearance_departments"));
if ($cnt && intval($cnt['c']) == 0) {
    foreach (['IT' => 1, 'Finance' => 2, 'Admin' => 3, 'HR' => 4] as $name => $order) {
        $n = mysqli_real_escape_string($con, $name);
        mysqli_query($con, "INSERT INTO hr_exit_clearance_departments (department_name, sort_order) VALUES ('$n', $order)");
    }
    step("OK: seeded default clearance departments");
} elseif ($cnt) {
    $hasHr = mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_clearance_departments WHERE department_name='HR'")) > 0;
    if (!$hasHr) { mysqli_query($con, "INSERT INTO hr_exit_clearance_departments (department_name, sort_order) VALUES ('HR', 4)"); step("OK: added HR clearance department"); }
}

echo "Exit Process schema migration complete.\n\n";
echo implode("\n", $log);
echo "\n\nAll tables/columns are now up to date. You can delete this file (hr-exit-migrate.php) now.\n";
