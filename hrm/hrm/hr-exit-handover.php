<?php
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

$pm1 = __DIR__ . '/PHPMailer/src/Exception.php';
$pm2 = __DIR__ . '/PHPMailer/src/PHPMailer.php';
$pm3 = __DIR__ . '/PHPMailer/src/SMTP.php';
if (file_exists($pm1) && file_exists($pm2) && file_exists($pm3)) {
    require_once($pm1);
    require_once($pm2);
    require_once($pm3);
    $PHPMAILER_AVAILABLE = true;
}

if (!function_exists('sendSmtpMail')) {
function sendSmtpMail($to_list, $subject, $body_text, $from_name = null) {
    global $PHPMAILER_AVAILABLE;
    if (empty($PHPMAILER_AVAILABLE)) {
        $to = implode(',', array_filter((array)$to_list, function($e){ return filter_var(trim($e), FILTER_VALIDATE_EMAIL); }));
        if (!$to) return ['success' => false, 'message' => 'No valid email address found.'];
        $headers = "From: " . ($from_name ?: (defined('SMTP_FROM_NAME_DEFAULT') ? SMTP_FROM_NAME_DEFAULT : 'HR Dept')) . " <" . (defined('SMTP_USER') ? SMTP_USER : 'hr@example.com') . ">\r\nReply-To: " . (defined('SMTP_USER') ? SMTP_USER : 'hr@example.com') . "\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n";
        $sent = @mail($to, $subject, $body_text, $headers);
        return ['success' => $sent, 'message' => $sent ? 'Email sent (fallback mail()).' : 'mail() returned false.'];
    }
    $mail = new \PHPMailer\PHPMailer\PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host       = SMTP_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = SMTP_USER;
        $mail->Password   = SMTP_PASS;
        $mail->SMTPSecure = SMTP_SECURE === 'ssl' ? \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS : \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = SMTP_PORT;
        $mail->CharSet    = 'UTF-8';
        $mail->setFrom(SMTP_USER, $from_name ?: SMTP_FROM_NAME_DEFAULT);
        foreach ((array)$to_list as $to) {
            $to = trim($to);
            if (filter_var($to, FILTER_VALIDATE_EMAIL)) $mail->addAddress($to);
        }
        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body    = nl2br($body_text);
        $mail->AltBody = strip_tags($body_text);
        $mail->send();
        return ['success' => true, 'message' => 'Email sent.'];
    } catch (\Exception $e) {
        return ['success' => false, 'message' => "SMTP Error: {$mail->ErrorInfo}"];
    }
}
}

try {

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

// The exiting employee can view/print their own Asset Handover document via their resignation
// link's token, without being logged in — same no-login bypass pattern used for the token itself
// in hr-employee-exit-request.php. Every other page load still requires a normal session.
$asset_doc_token_ok = false;
if ((isset($_GET['view_asset_doc']) || isset($_GET['view_clearance_doc'])) && isset($_GET['token'])) {
    $va_check_id = intval($_GET['view_asset_doc'] ?? $_GET['view_clearance_doc']);
    $va_check_token = mysqli_real_escape_string($con, $_GET['token']);
    $va_check_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_requests WHERE id=$va_check_id AND token='$va_check_token' LIMIT 1"));
    $asset_doc_token_ok = (bool)$va_check_row;
}

// Position Head reviews/signs off via their own direct link (no login) — same idea as the
// employee's resignation-link token above. Covers both the GET page load (?ph_review=&token=)
// and the two AJAX actions the review page itself calls (approve/reject), which also arrive
// without a session and carry the token in the POST body instead.
$ph_token_ok = false;
$ph_token_instance = null;
if (isset($_GET['ph_review']) && isset($_GET['token'])) {
    $ph_check_id = intval($_GET['ph_review']);
    $ph_check_token = mysqli_real_escape_string($con, $_GET['token']);
    $ph_token_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$ph_check_id AND position_head_token='$ph_check_token' LIMIT 1"));
    $ph_token_ok = (bool)$ph_token_instance;
} elseif (isset($_POST['ajax_action']) && in_array($_POST['ajax_action'], ['approve_clearance_position_head', 'reject_clearance_position_head', 'set_clearance_response', 'save_clearance_item_remarks']) && isset($_POST['ph_token'])) {
    if (isset($_POST['instance_id'])) {
        $ph_check_id = intval($_POST['instance_id']);
    } elseif (isset($_POST['run_item_id'])) {
        $run_it = mysqli_fetch_assoc(mysqli_query($con, "SELECT instance_id FROM hr_exit_clearance_run_items WHERE id=" . intval($_POST['run_item_id']) . " LIMIT 1"));
        $ph_check_id = $run_it ? intval($run_it['instance_id']) : 0;
    } else {
        $ph_check_id = 0;
    }
    $ph_check_token = mysqli_real_escape_string($con, $_POST['ph_token']);
    $ph_token_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$ph_check_id AND position_head_token='$ph_check_token' LIMIT 1"));
    $ph_token_ok = (bool)$ph_token_instance;
}

if (!$asset_doc_token_ok && !$ph_token_ok) { isUser(); }

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// A token-authenticated Position Head has no session — resolve their real name from the
// instance's assigned employee so the existing approve/reject handlers (which use
// $currentUserName for position_head_signed_by / the rejection ticket) work unchanged.
if ($ph_token_ok && $ph_token_instance) {
    $ph_head_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_employees WHERE id=" . intval($ph_token_instance['position_head_employee_id']) . " LIMIT 1"));
    if ($ph_head_row) { $currentUserName = $ph_head_row['name']; }
}

// =========================================================================
// TABLE SETUP
// =========================================================================
$tables = [
// HR-defined master template, one-time per Dept/Position (mirrors hr_oje_training_materials pattern)
"CREATE TABLE IF NOT EXISTS hr_exit_handover_templates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    item_title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// Per-exit handover instance: who is receiving the handover
"CREATE TABLE IF NOT EXISTS hr_exit_handover_instance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    employee_id INT NOT NULL,
    nominated_to_id INT NOT NULL,
    nominated_by VARCHAR(255) DEFAULT NULL,
    assigned_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_exit (exit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// Per-exit checklist items, copied from template at assignment time
"CREATE TABLE IF NOT EXISTS hr_exit_handover_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    item_title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT NULL,
    employee_notes TEXT DEFAULT NULL,
    status ENUM('pending','filled','acknowledged') DEFAULT 'pending',
    filled_at DATETIME DEFAULT NULL,
    acknowledged_by VARCHAR(255) DEFAULT NULL,
    acknowledged_at DATETIME DEFAULT NULL,
    sort_order INT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// ===== ASSET HANDOVER CHECKLIST =====
// HR-managed master template of checklist sections (department/position scoped, 0 = global/applies to all)
"CREATE TABLE IF NOT EXISTS hr_exit_asset_headings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL DEFAULT 0,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    show_condition_field TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// Template items belonging to a heading above
"CREATE TABLE IF NOT EXISTS hr_exit_asset_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    heading_id INT NOT NULL,
    item_text VARCHAR(500) NOT NULL,
    sort_order INT DEFAULT 0,
    is_active TINYINT(1) DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// One asset-handover checklist run per exit
"CREATE TABLE IF NOT EXISTS hr_exit_asset_instance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    employee_id INT NOT NULL,
    signature_data LONGTEXT DEFAULT NULL,
    signed_by VARCHAR(255) DEFAULT NULL,
    signed_at DATETIME DEFAULT NULL,
    status ENUM('in_progress','pending_approval','rejected','completed','not_applicable') DEFAULT 'in_progress',
    rejection_reason TEXT DEFAULT NULL,
    reviewed_by VARCHAR(255) DEFAULT NULL,
    reviewed_at DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_exit (exit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// Per-exit checklist rows, copied from the template at start time (plus any ad-hoc rows added during fill-in)
"CREATE TABLE IF NOT EXISTS hr_exit_asset_run_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    instance_id INT NOT NULL,
    heading_id INT DEFAULT NULL,
    heading_name VARCHAR(255) NOT NULL,
    heading_sort INT DEFAULT 0,
    show_condition_field TINYINT(1) DEFAULT 0,
    item_id INT DEFAULT NULL,
    item_text VARCHAR(500) NOT NULL,
    item_sort INT DEFAULT 0,
    is_checked TINYINT(1) DEFAULT 0,
    condition_text VARCHAR(255) DEFAULT NULL,
    remarks TEXT DEFAULT NULL,
    is_custom TINYINT(1) DEFAULT 0,
    checked_by VARCHAR(255) DEFAULT NULL,
    checked_at DATETIME DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// ===== DEPARTMENT-POSITION CLEARANCE =====
// One template per exact (department, position, position head) combination
"CREATE TABLE IF NOT EXISTS hr_exit_clearance_templates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL,
    position_head_employee_id INT NOT NULL,
    signatory_title VARCHAR(100) DEFAULT 'Position Head',
    declaration_text TEXT DEFAULT NULL,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_combo (department_id, position_id, position_head_employee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_headings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    template_id INT NOT NULL,
    heading_name VARCHAR(255) NOT NULL,
    sort_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_checklist_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    heading_id INT NOT NULL,
    item_text VARCHAR(500) NOT NULL,
    sort_order INT DEFAULT 0,
    is_active TINYINT(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_instance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    employee_id INT NOT NULL,
    template_id INT DEFAULT NULL,
    position_head_employee_id INT DEFAULT NULL,
    status ENUM('in_progress','pending_position_head_review','rejected_by_position_head','pending_employee_signature','pending_hr_approval','completed','not_applicable') DEFAULT 'in_progress',
    employee_signature_data LONGTEXT DEFAULT NULL,
    employee_signed_by VARCHAR(255) DEFAULT NULL,
    employee_signed_at DATETIME DEFAULT NULL,
    position_head_signature_data LONGTEXT DEFAULT NULL,
    position_head_signed_by VARCHAR(255) DEFAULT NULL,
    position_head_signed_at DATETIME DEFAULT NULL,
    position_head_remarks TEXT DEFAULT NULL,
    position_head_rejection_reason TEXT DEFAULT NULL,
    hr_reviewed_by VARCHAR(255) DEFAULT NULL,
    hr_reviewed_at DATETIME DEFAULT NULL,
    hr_rejection_reason TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_exit (exit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_run_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    instance_id INT NOT NULL,
    heading_id INT DEFAULT NULL,
    heading_name VARCHAR(255) NOT NULL,
    heading_sort INT DEFAULT 0,
    item_id INT DEFAULT NULL,
    item_text VARCHAR(500) NOT NULL,
    item_sort INT DEFAULT 0,
    response ENUM('unanswered','yes','no','na') DEFAULT 'unanswered',
    remarks TEXT DEFAULT NULL,
    is_custom TINYINT(1) DEFAULT 0,
    checked_by VARCHAR(255) DEFAULT NULL,
    checked_at DATETIME DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_exit_clearance_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    action_name VARCHAR(255) NOT NULL,
    action_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    KEY idx_exit_id (exit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) mysqli_query($con, $sql);

// =========================================================================
// SCHEMA UPGRADE — hr_exit_asset_instance gained approval-workflow columns
// after this table may have already been created on a prior page load;
// CREATE TABLE IF NOT EXISTS above is a no-op once the table exists, so
// these have to be added explicitly here (idempotent, safe to run every load).
// =========================================================================
$asset_instance_col_checks = [
    ["hr_exit_asset_instance", "rejection_reason", "ALTER TABLE hr_exit_asset_instance ADD COLUMN rejection_reason TEXT DEFAULT NULL AFTER status"],
    ["hr_exit_asset_instance", "reviewed_by",       "ALTER TABLE hr_exit_asset_instance ADD COLUMN reviewed_by VARCHAR(255) DEFAULT NULL AFTER rejection_reason"],
    ["hr_exit_asset_instance", "reviewed_at",       "ALTER TABLE hr_exit_asset_instance ADD COLUMN reviewed_at DATETIME DEFAULT NULL AFTER reviewed_by"],
];
foreach ($asset_instance_col_checks as [$tbl, $col, $alter_sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $alter_sql);
}

// Widen the status ENUM if it's still an older definition missing any of the newer values
$status_col = mysqli_fetch_assoc(mysqli_query($con, "SHOW COLUMNS FROM hr_exit_asset_instance LIKE 'status'"));
if ($status_col && strpos($status_col['Type'], 'not_applicable') === false) {
    mysqli_query($con, "ALTER TABLE hr_exit_asset_instance MODIFY COLUMN status ENUM('in_progress','pending_employee_signature','rejected_by_employee','pending_hr_approval','completed','not_applicable') DEFAULT 'in_progress'");
}

$clr_status_col = mysqli_fetch_assoc(mysqli_query($con, "SHOW COLUMNS FROM hr_exit_clearance_instance LIKE 'status'"));
if ($clr_status_col && strpos($clr_status_col['Type'], 'pending_employee_signature') === false) {
    mysqli_query($con, "ALTER TABLE hr_exit_clearance_instance MODIFY COLUMN status ENUM('in_progress','pending_position_head_review','rejected_by_position_head','pending_employee_signature','pending_hr_approval','completed','not_applicable') DEFAULT 'in_progress'");
}

// Position Head is now optional at template-creation time — lets HR (or a backend seed) create
// a clearance template before deciding who the position head is, and assign that person later
// from the Manage Clearance Template screen. Widen the column if still the old NOT NULL definition.
$phead_col = mysqli_fetch_assoc(mysqli_query($con, "SHOW COLUMNS FROM hr_exit_clearance_templates LIKE 'position_head_employee_id'"));
if ($phead_col && stripos($phead_col['Null'], 'YES') === false) {
    mysqli_query($con, "ALTER TABLE hr_exit_clearance_templates MODIFY COLUMN position_head_employee_id INT DEFAULT NULL");
}

// Lets the Position Head review/sign off via a direct link (no login), same idea as the
// employee's resignation-link token — added here since the instance table already existed live.
$phtoken_col = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_clearance_instance LIKE 'position_head_token'");
if ($phtoken_col && mysqli_num_rows($phtoken_col) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_clearance_instance ADD COLUMN position_head_token VARCHAR(64) DEFAULT NULL AFTER position_head_employee_id");
}

$phnotified_col = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_clearance_instance LIKE 'position_head_notified_at'");
if ($phnotified_col && mysqli_num_rows($phnotified_col) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_clearance_instance ADD COLUMN position_head_notified_at DATETIME DEFAULT NULL AFTER position_head_token");
}

// =========================================================================
// SEED DEFAULT ASSET HANDOVER CHECKLIST (one-time, idempotent, global scope)
// =========================================================================
$asset_seed_headings = [
    ['name' => 'Asset Return Checklist', 'show_condition' => 1, 'items' => [
        'Laptop', 'Laptop Charger', 'Desktop / CPU', 'Monitor', 'Keyboard', 'Mouse',
        'Company Mobile Phone', 'SIM Card', 'ID Card', 'Access Card / RFID Card', 'Office Keys',
        'Vehicle Keys (if issued)', 'Headset / Earphones', 'Uniform / Safety Jacket / PPE',
        'Documents / Files', 'Company Credit/Debit Card (if issued)', 'Any Other Company Asset',
    ]],
    ['name' => 'IT & Access Deactivation Checklist', 'show_condition' => 0, 'items' => [
        'Company Email Disabled', 'CRM/ERP Access Disabled', 'Attendance System Access Disabled',
        'Shared Drive Access Removed', 'Company Applications Logged Out', 'Passwords Changed (where applicable)',
    ]],
];
foreach ($asset_seed_headings as $ash_idx => $ash) {
    $ash_name_e = mysqli_real_escape_string($con, $ash['name']);
    $ash_check = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_asset_headings WHERE department_id=0 AND position_id=0 AND heading_name='$ash_name_e' LIMIT 1"));
    if ($ash_check) {
        $ash_id = intval($ash_check['id']);
    } else {
        mysqli_query($con, "INSERT INTO hr_exit_asset_headings (department_id, position_id, heading_name, show_condition_field, sort_order, created_by) VALUES (0, 0, '$ash_name_e', " . intval($ash['show_condition']) . ", $ash_idx, 'system_seed')");
        $ash_id = mysqli_insert_id($con);
    }
    foreach ($ash['items'] as $asi_idx => $asi_text) {
        $asi_text_e = mysqli_real_escape_string($con, $asi_text);
        $asi_check = mysqli_query($con, "SELECT id FROM hr_exit_asset_items WHERE heading_id=$ash_id AND item_text='$asi_text_e'");
        if ($asi_check && mysqli_num_rows($asi_check) == 0) {
            mysqli_query($con, "INSERT INTO hr_exit_asset_items (heading_id, item_text, sort_order) VALUES ($ash_id, '$asi_text_e', $asi_idx)");
        }
    }
}

function resolveDeptPos($con, $empRow) {
    $deptVal = $empRow['department_id'] ?? ($empRow['department'] ?? null);
    $posVal  = $empRow['position_id']   ?? ($empRow['position']   ?? null);
    $dept_id = 0; $pos_id = 0;
    if ($deptVal !== null && $deptVal !== '') {
        if (is_numeric($deptVal)) { $dept_id = intval($deptVal); }
        else {
            $dn = mysqli_real_escape_string($con, trim($deptVal));
            $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1"));
            if ($r) $dept_id = intval($r['id']);
        }
    }
    if ($posVal !== null && $posVal !== '') {
        if (is_numeric($posVal)) { $pos_id = intval($posVal); }
        else {
            $pn = mysqli_real_escape_string($con, trim($posVal));
            $where = $dept_id > 0 ? "AND department_id=$dept_id" : "";
            $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_positions WHERE title='$pn' $where LIMIT 1"));
            if ($r) $pos_id = intval($r['id']);
        }
    }
    return [$dept_id, $pos_id];
}

// Resolves an exiting employee's company logo/contact/signature for the printable asset doc
function getExitCompanySettings($con, $emp_id) {
    if ($emp_id <= 0) return [];
    $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT company_name FROM hr_employees WHERE id=" . intval($emp_id) . " LIMIT 1"));
    $ename = trim($emp['company_name'] ?? '');
    if (empty($ename)) return [];
    $cname_e = mysqli_real_escape_string($con, $ename);

    // Preferred: resolve via hr_companies -> hr_offer_company_settings.company_id (avoids cross-company mixups)
    $r = null;
    $hc_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$cname_e')) LIMIT 1"));
    if ($hc_row) {
        $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_id=" . intval($hc_row['id']) . " LIMIT 1"));
        if ($r) $r['company_name'] = $hc_row['company_name'];
    }

    // Fallback: match hr_offer_company_settings directly by name (covers rows never linked via company_id)
    if (!$r) {
        $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$cname_e')) LIMIT 1"));
    }

    // Nothing configured anywhere — still show the employee's own company name instead of a blank header
    if (!$r) return ['company_name' => $ename];

    if (empty($r['company_signature']) && !empty($r['signature_path'])) $r['company_signature'] = $r['signature_path'];
    return $r;
}

// Raises one ticket to the employee when HR rejects their Asset Handover submission
// (same tickets table / ticket_number pattern as hr-checklist.php's reject_fillable)
function raiseAssetHandoverRejectedTicket($con, $currentUserName, $empRow, $exitRow, $reason) {
    if (!$empRow || intval($empRow['id']) <= 0) return 0;

    $by_name_e = mysqli_real_escape_string($con, $currentUserName);
    $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE TRIM(LOWER(name))=TRIM(LOWER('$by_name_e')) LIMIT 1"));
    if (!$hr_self) $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$by_name_e%' LIMIT 1"));
    if (!$hr_self) return 0;

    $subject = "Asset Handover Rejected — " . $exitRow['exit_number'];
    $message = "Your Asset Handover checklist submission was reviewed and rejected by {$currentUserName}.\n\nReason: {$reason}\n\nPlease review, update, and re-sign your Asset Handover checklist via your exit tracker link.";
    $subject_e = mysqli_real_escape_string($con, $subject);
    $message_e = mysqli_real_escape_string($con, $message);
    $deadline = date('Y-m-d H:i:s', strtotime('+1440 minutes'));

    $tk_row  = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
    $tk_next = intval($tk_row['max_id'] ?? 0) + 1;
    $ticket_number = 'TICKET' . date('Y') . str_pad($tk_next, 4, '0', STR_PAD_LEFT);

    mysqli_query($con, "INSERT INTO tickets
        (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
        VALUES
        ('$ticket_number', '$by_name_e', '$subject_e', '$message_e', 'open', 'medium', 1440, '$deadline', '', NOW(), NOW(), " . intval($empRow['id']) . ", " . intval($hr_self['id']) . ")");

    return mysqli_affected_rows($con) > 0 ? 1 : 0;
}

// Raises one ticket to the employee when their Department-Position Clearance submission is
// rejected — by either the Position Head or HR — same tickets table pattern as above.
function raiseClearanceRejectedTicket($con, $currentUserName, $empRow, $exitRow, $reason) {
    if (!$empRow || intval($empRow['id']) <= 0) return 0;

    $by_name_e = mysqli_real_escape_string($con, $currentUserName);
    $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE TRIM(LOWER(name))=TRIM(LOWER('$by_name_e')) LIMIT 1"));
    if (!$hr_self) $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$by_name_e%' LIMIT 1"));
    if (!$hr_self) return 0;

    $subject = "Department-Position Clearance Rejected — " . $exitRow['exit_number'];
    $message = "Your Department-Position Clearance submission was reviewed and rejected by {$currentUserName}.\n\nReason: {$reason}\n\nPlease review, update, and re-sign your Department-Position Clearance checklist via your exit tracker link.";
    $subject_e = mysqli_real_escape_string($con, $subject);
    $message_e = mysqli_real_escape_string($con, $message);
    $deadline = date('Y-m-d H:i:s', strtotime('+1440 minutes'));

    $tk_row  = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
    $tk_next = intval($tk_row['max_id'] ?? 0) + 1;
    $ticket_number = 'TICKET' . date('Y') . str_pad($tk_next, 4, '0', STR_PAD_LEFT);

    mysqli_query($con, "INSERT INTO tickets
        (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
        VALUES
        ('$ticket_number', '$by_name_e', '$subject_e', '$message_e', 'open', 'medium', 1440, '$deadline', '', NOW(), NOW(), " . intval($empRow['id']) . ", " . intval($hr_self['id']) . ")");

    return mysqli_affected_rows($con) > 0 ? 1 : 0;
}

// Default clearance checklist content, applied automatically the first time HR creates a
// clearance template whose Position title matches one of these (case-insensitive exact match).
// HR can freely edit/add/remove anything afterward — this is only a starting point.
function clearanceDefaultTemplateFor($positionTitle) {
    $key = trim(mb_strtolower($positionTitle));
    $defaults = [
        'hr and admin' => [
            'signatory_title' => 'HR Executive',
            'declaration_text' => "I confirm that I have returned all company assets, completed the required handover, and have no company property or confidential information in my possession.",
            'headings' => [[
                'name' => 'HR Clearance',
                'items' => [
                    'Resignation accepted',
                    'Notice period completed/approved',
                    'Exit interview completed',
                    'Attendance updated',
                    'Leave balance verified',
                    'Payroll informed for Full & Final Settlement',
                    'Employee ID card returned',
                    'HR files and documents handed over',
                    'Recruitment tracker handed over',
                    'Employee records updated',
                    'Offer letters and onboarding documents handed over',
                    'Pending recruitment closed or transferred'
                ]
            ], [
                'name' => 'Administration Clearance',
                'items' => [
                    'Laptop/Desktop',
                    'Laptop Charger',
                    'Mouse & Keyboard',
                    'Office Mobile Phone',
                    'SIM Card',
                    'ID Card',
                    'Access Card',
                    'Office Keys',
                    'Drawer/Locker Keys',
                    'Company Documents',
                    'Company Seal/Stamp',
                    'Company Cheque Book (if any)',
                    'Office Stationery',
                    'Vendor Files',
                    'Employee Personal Files',
                    'Attendance Register',
                    'Asset Register',
                    'Visitor Register',
                    'Office Keys Handed Over',
                    'Office Clean Desk Checked'
                ]
            ], [
                'name' => 'IT Clearance',
                'items' => [
                    'Official Email Disabled',
                    'CRM/ERP Access Removed',
                    'HRMS Access Removed',
                    'WhatsApp Business Access Removed',
                    'Passwords Handed Over',
                    'Data Backup Completed'
                ]
            ], [
                'name' => 'Reporting Manager Clearance',
                'items' => [
                    'Work Handover Completed',
                    'Pending Tasks Transferred',
                    'Documents Submitted',
                    'Confidential Information Returned'
                ]
            ], [
                'name' => 'Finance Clearance',
                'items' => [
                    'Salary Advance Cleared',
                    'Reimbursements Settled',
                    'Full & Final Settlement Approved',
                    'No Pending Dues'
                ]
            ]]
        ],
        'sales and marketing executive' => [
            'signatory_title' => 'Sales & Marketing Manager',
            'declaration_text' => "I confirm that I have returned all company assets, completed the required handover, and have no company property or confidential information in my possession.",
            'headings' => [[
                'name' => 'Sales & Marketing Department Exit Clearance',
                'items' => [
                    'Customer database handed over',
                    'Active customer list handed over',
                    'Prospective lead list handed over',
                    'CRM updated and handed over',
                    'Pending quotations handed over',
                    'Pending customer follow-ups handed over',
                    'Sales pipeline handed over',
                    'Customer contracts and agreements handed over',
                    'Sales reports submitted',
                    'Marketing campaign details handed over',
                    'Vendor/Business partner details handed over',
                    'Official company documents/files handed over',
                    'Company email and CRM access handed over/disabled',
                    'Company laptop returned (if issued)',
                    'Company mobile phone returned (if issued)',
                    'Company SIM card returned (if issued)',
                    'ID card and access card returned',
                    'Business cards, brochures, and marketing materials returned',
                    'Pending reimbursement bills submitted',
                    'No pending customer commitments or company dues'
                ]
            ]]
        ],
        'software developer' => [
            'signatory_title' => 'IT Executive',
            'declaration_text' => "I confirm that I have returned all company assets, completed the required handover, and have no company property or confidential information in my possession.",
            'headings' => [[
                'name' => 'IT Department Exit Clearance',
                'items' => [
                    'Company laptop/desktop returned',
                    'Laptop charger returned',
                    'Docking station returned (if issued)',
                    'External monitor returned',
                    'Keyboard returned',
                    'Mouse returned',
                    'Headset/Webcam returned',
                    'External hard disk/Pen drive returned',
                    'Mobile phone returned (if issued)',
                    'SIM card returned (if issued)',
                    'Company email account disabled',
                    'HRMS/CRM/ERP login disabled',
                    'Attendance/Biometric access disabled',
                    'Microsoft 365/Google Workspace access removed',
                    'VPN access disabled',
                    'Shared folders and cloud storage access removed',
                    'Official WhatsApp/Teams/Slack access removed',
                    'Software licenses recovered/deactivated',
                    'Source code/project files handed over (if applicable)',
                    'Business data backed up successfully',
                    'Confidential files transferred to reporting manager',
                    'Passwords, credentials and MFA devices handed over (where applicable)',
                    'No company data stored on personal devices',
                    'Company data deleted from personal devices (if company policy requires)',
                    'Email auto-forwarding configured/disabled as per company policy',
                    'Company ID card/access card deactivated',
                    'IT assets checked for physical damage',
                    'Asset details updated in the IT Asset Register',
                    'No pending IT support tickets assigned to the employee',
                    'All IT security and exit formalities completed'
                ]
            ]]
        ],
        'digital marketing' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I hereby confirm that I have handed over all company assets, digital marketing accounts, passwords, login credentials, campaign details, documents, and other responsibilities assigned to me. I declare that I have not retained any company property or confidential company information.",
            'headings' => [[
                'name' => 'Digital Marketing Department Exit Clearance',
                'items' => [
                    'All digital marketing campaigns handed over',
                    'Social media accounts handed over (Facebook, Instagram, LinkedIn, X, YouTube, etc.)',
                    'All social media usernames and passwords handed over',
                    'Login credentials transferred to the authorized person',
                    'Content calendar handed over',
                    'Scheduled posts reviewed and handed over',
                    'Ongoing campaign reports submitted',
                    'Google Ads account and credentials handed over',
                    'Meta Ads/Business Manager account and credentials handed over',
                    'SEO reports and keyword tracker handed over',
                    'Website/CMS access and passwords handed over',
                    'Google Analytics and Search Console access transferred',
                    'Marketing creatives (images, videos, banners, designs) handed over',
                    'Brand guidelines and digital assets handed over',
                    'Email marketing campaigns, templates, and login credentials handed over',
                    'CRM and marketing automation tool access handed over',
                    'Canva/Adobe/design tool access and passwords handed over',
                    'Lead generation reports submitted',
                    'CRM updated with latest marketing leads',
                    'Vendor/Agency contact details handed over',
                    'Company laptop/mobile/SIM card returned (if issued)',
                    'Official email account handed over and access disabled',
                    'All company passwords transferred or changed',
                    'Two-factor authentication (2FA) transferred or removed',
                    'Confidential marketing data and documents returned',
                    'Pending reimbursement bills submitted (if applicable)',
                    'No pending digital marketing activities or company dues'
                ]
            ]]
        ],
        'procurment and marketing' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I hereby confirm that I have handed over all procurement documents, vendor information, purchase records, system access, passwords, company assets, and all other responsibilities assigned to me. I declare that I have not retained any confidential company information or company property.",
            'headings' => [[
                'name' => 'Procurement Department Exit Clearance',
                'items' => [
                    'All pending purchase requisitions (PRs) handed over',
                    'All pending purchase orders (POs) handed over',
                    'Vendor master list handed over',
                    'Vendor contact details handed over',
                    'Vendor quotations handed over',
                    'Rate contracts/price agreements handed over',
                    'Vendor negotiation status handed over',
                    'Pending deliveries and follow-up details handed over',
                    'Pending invoices and payment follow-up details handed over',
                    'Procurement reports and records handed over',
                    'Vendor performance records handed over',
                    'Contracts, agreements, and procurement documents handed over',
                    'ERP/Procurement software updated',
                    'ERP/Procurement system login credentials handed over',
                    'Official email account handed over and access disabled',
                    'Company passwords and login credentials handed over',
                    'Company laptop/mobile phone/SIM card returned (if issued)',
                    'ID card and access card returned',
                    'Procurement files, registers, and documents returned',
                    'Company stamp/seal (if issued) returned',
                    'Pending reimbursement bills submitted (if applicable)',
                    'No pending procurement activities or company dues'
                ]
            ]]
        ],
        'logistic coordinator for ptl' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I hereby confirm that I have handed over all PTL operational activities, shipment details, damaged shipment records, written-off shipment records, customer records, vendor information, documents, system access, passwords, company assets, and all other responsibilities assigned to me. I declare that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Logistics Coordinator (PTL) Department Exit Clearance',
                'items' => [
                    'All active PTL shipments handed over',
                    'Pending shipment details handed over',
                    'Shipment tracking status updated and handed over',
                    'Customer shipment records handed over',
                    'Customer contact details handed over',
                    'Transport vendor database handed over',
                    'Vendor contact details handed over',
                    'Driver contact details handed over',
                    'Vehicle details and allocation records handed over',
                    'Pending vehicle arrangements handed over',
                    'Pending pickup details handed over',
                    'Pending delivery details handed over',
                    'E-Way Bill details handed over (if applicable)',
                    'POD (Proof of Delivery) records handed over',
                    'LR/Lorry Receipt records handed over',
                    'Challans, invoices, and shipment documents handed over',
                    'Customer booking records handed over',
                    'Shipment exception/issues list handed over',
                    'Damaged shipment records handed over',
                    'Written-off shipment records handed over',
                    'Customer complaints and resolutions handed over',
                    'Vendor payment follow-up details handed over',
                    'Customer billing status handed over',
                    'Daily operations report submitted',
                    'Weekly and monthly reports submitted',
                    'FlowX/CRM/TMS updated with latest shipment status',
                    'FlowX/CRM/TMS login credentials handed over (if applicable)',
                    'Official email account handed over and access disabled',
                    'Company mobile phone/SIM card returned (if issued)',
                    'Company laptop/desktop returned (if issued)',
                    'Company ID card and access card returned',
                    'Company files, registers, and operation documents returned',
                    'Official WhatsApp groups and communication handover completed',
                    'All company passwords and login credentials handed over',
                    'Pending reimbursement claims submitted',
                    'Petty cash/advance settled (if applicable)',
                    'No pending customer, vendor, or operational commitments',
                    'No confidential company data retained by the employee'
                ]
            ]]
        ],
        'logistic coordinator for ftl' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I confirm that I have completed the applicable handover and returned all company property, documents, access and responsibilities assigned to me.",
            'headings' => [[
                'name' => 'Logistics Coordinator (FTL) Exit Clearance',
                'items' => [
                    'All active FTL shipments and pending shipments handed over',
                    'Customer shipment records and contact details handed over',
                    'Customer rate contracts and agreed freight rates handed over',
                    'Transport vendor and driver details handed over',
                    'Vehicle allocation/placement records handed over',
                    'Vehicle documents, permits and fitness details handed over, where applicable',
                    'Pending vehicle placements and loading/unloading schedules handed over',
                    'Route plans, trip details and GPS tracking status handed over',
                    'E-Way Bills, LR records and POD records handed over, where applicable',
                    'Challans, invoices and shipment documents handed over',
                    'Damaged shipment records handed over',
                    'Written-off shipment records handed over',
                    'Shortage, excess and transit-loss records handed over',
                    'Vehicle detention and loading/unloading delay records handed over',
                    'Customer complaints and operational exceptions handed over',
                    'Vendor payment follow-ups and customer billing status handed over',
                    'Advance, diesel/trip expense records handed over, where applicable',
                    'Daily dispatch, vehicle placement and periodic reports submitted',
                    'FlowX/CRM/TMS access and passwords handled through the approved process',
                    'Company assets and pending reimbursement claims cleared',
                ],
            ]],
        ],
        'civil engineer executive' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I confirm that I have completed the applicable handover and returned all company property, documents, access and responsibilities assigned to me.",
            'headings' => [[
                'name' => 'Civil Engineer Executive Exit Clearance',
                'items' => [
                    'All assigned project/site responsibilities handed over',
                    'Site progress reports submitted',
                    'Site measurement records handed over',
                    'BOQ, estimation and costing files handed over',
                    'Approved drawings and latest revisions handed over',
                    'Site/project documents and files handed over',
                    'Contractor and subcontractor details handed over',
                    'Vendor/supplier details handed over',
                    'Material requirement and consumption records handed over',
                    'Site inventory and asset records handed over',
                    'Quality inspection records handed over',
                    'Safety inspection and incident records handed over',
                    'Pending work list and snag/rectification status handed over',
                    'Site photographs and project documentation handed over',
                    'Project reports and pending issues submitted',
                    'Company laptop/mobile/ID/access card and other issued items returned',
                    'Project software/system access and passwords handled through the approved process',
                    'Pending reimbursement claims submitted',
                ],
            ]],
        ],
        'admin executive' => [
            'signatory_title' => 'Department Manager',
            'declaration_text' => "I hereby confirm that I have handed over all site administration records, vendor payment details, registers, documents, company assets, passwords, and responsibilities assigned to me. I further confirm that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Site Admin Executive - Department Exit Clearance',
                'items' => [
                    'Site keys handed over',
                    'Site asset register handed over',
                    'Site inventory records handed over',
                    'Material inward and outward registers handed over',
                    'Labour attendance and muster roll records handed over',
                    'Contractor and subcontractor records handed over',
                    'Vendor master list and contact details handed over',
                    'Vendor payment records handed over',
                    'Pending vendor payment details handed over',
                    'Vendor bills and invoices handed over',
                    'Material purchase records handed over',
                    'Site petty cash records handed over',
                    'Site expense records handed over',
                    'Equipment and tool issue registers handed over',
                    'Site visitor register handed over',
                    'Site document files and registers handed over',
                    'Company laptop/mobile phone/SIM card returned (if issued)',
                    'Company ID card and access card returned',
                    'Official email and software access handed over',
                    'All company passwords and login credentials handed over',
                    'Pending reimbursement claims submitted',
                    'No confidential company documents or data retained'
                ]
            ]]
        ],
        'finance executive' => [
            'signatory_title' => 'Finance Manager',
            'declaration_text' => "I hereby confirm that I have handed over all finance records, customer payment details, vendor payment details, invoices, reports, documents, system access, passwords, company assets, and responsibilities assigned to me. I confirm that I have not retained any company financial data or confidential information.",
            'headings' => [[
                'name' => 'Finance Executive Department Exit Clearance',
                'items' => [
                    'Customer master details handed over',
                    'Customer outstanding payment details handed over',
                    'Pending customer payment follow-up details handed over',
                    'Customer ageing report handed over',
                    'Customer invoices raised and records handed over',
                    'Pending customer invoices status handed over',
                    'Customer payment received records updated and handed over',
                    'Customer credit notes/debit notes details handed over',
                    'Vendor master details handed over',
                    'Vendor outstanding payment details handed over',
                    'Pending vendor payment records handed over',
                    'Vendor payment follow-up status handed over',
                    'Vendor invoices and bills records handed over',
                    'Vendor ageing report handed over',
                    'Purchase invoices verification records handed over',
                    'Bank payment details and transaction records handed over',
                    'Bank reconciliation statement updated and handed over',
                    'Cash book and petty cash records handed over',
                    'Employee salary/payroll records handed over',
                    'Employee reimbursement records handed over',
                    'Advance payment records handed over',
                    'Expense records and supporting bills handed over',
                    'GST records and related documents handed over',
                    'TDS records and documents handed over',
                    'Tax-related documents handed over',
                    'Monthly financial reports handed over',
                    'Profit & Loss reports handed over',
                    'Balance sheet supporting documents handed over',
                    'Expense tracker updated and handed over',
                    'Pending payments and receivables list handed over',
                    'Accounting software access handed over',
                    'Finance system login credentials handed over',
                    'All finance-related passwords and access details handed over',
                    'Official email account handed over and access disabled',
                    'Company laptop/desktop returned (if issued)',
                    'Company mobile/SIM card returned (if issued)',
                    'Company ID card/access card returned',
                    'Finance files, registers, and documents returned',
                    'Pending reimbursement claims submitted',
                    'No pending financial activities or commitments',
                    'No confidential financial data retained by the employee'
                ]
            ]]
        ],
        'warehouse site supervisor' => [
            'signatory_title' => 'Manager',
            'declaration_text' => "I hereby confirm that I have handed over all warehouse operations details, inventory records, manpower details, shipment records, documents, system access, passwords, company assets, and responsibilities assigned to me. I confirm that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Warehouse Site Supervisor - Department Exit Clearance',
                'items' => [
                    'Complete warehouse operations handover completed',
                    'Daily warehouse activity reports handed over',
                    'Pending work and operational issues handed over',
                    'Shift-wise activity details handed over',
                    'Manpower attendance records handed over',
                    'Worker/helper details and allocation records handed over',
                    'Shift roster and duty allocation details handed over',
                    'Training records of warehouse employees handed over',
                    'Warehouse safety records handed over',
                    'Safety incident/accident records handed over',
                    'Material inward records handed over',
                    'Material outward/dispatch records handed over',
                    'Stock/inventory records handed over',
                    'Stock discrepancy records handed over',
                    'Damaged material records handed over',
                    'Shortage/excess material records handed over',
                    'Pending inventory issues handed over',
                    'Warehouse equipment and tools records handed over',
                    'Equipment damage/maintenance records handed over',
                    'Barcode/scanner/warehouse device records handed over (if applicable)',
                    'Vehicle loading/unloading records handed over',
                    'Inbound and outbound shipment records handed over',
                    'Pending shipment details handed over',
                    'Shipment exception and issue records handed over',
                    'Customer/client coordination details handed over',
                    'Vendor/service provider details handed over',
                    'Warehouse documents, registers, and files handed over',
                    'Gate entry and exit records handed over',
                    'Housekeeping and maintenance records handed over',
                    'Security coordination details handed over',
                    'Warehouse keys/access cards returned',
                    'Company laptop/desktop returned (if issued)',
                    'Company mobile phone/SIM card returned (if issued)',
                    'Company ID card returned',
                    'Warehouse system/software access handed over or disabled',
                    'All warehouse-related passwords and login credentials handed over',
                    'Pending reimbursement claims submitted',
                    'Petty cash/advance settlement completed (if applicable)',
                    'No pending operational activities or responsibilities',
                    'No company documents, data, or assets retained by the employee'
                ]
            ]]
        ],
        'warehouse manager' => [
            'signatory_title' => 'Manager',
            'declaration_text' => "I hereby confirm that I have handed over all warehouse operations, inventory details, manpower records, vendor/customer details, reports, documents, system access, passwords, company assets, and responsibilities assigned to me. I confirm that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Warehouse Manager - Department Exit Clearance',
                'items' => [
                    'Complete warehouse operations handover completed',
                    'Warehouse process and SOP documents handed over',
                    'Daily, weekly, and monthly warehouse reports handed over',
                    'Pending operational activities and issues handed over',
                    'Warehouse performance reports and KPI details handed over',
                    'Manpower details and workforce allocation records handed over',
                    'Employee attendance, shift roster, and duty allocation records handed over',
                    'Training records and performance details of warehouse staff handed over',
                    'Disciplinary issues and pending employee matters handed over',
                    'Inventory/stock records handed over',
                    'Stock reconciliation reports handed over',
                    'Stock shortage/excess records handed over',
                    'Damaged material records handed over',
                    'Written-off material records handed over',
                    'Inventory discrepancy and investigation records handed over',
                    'Inward material records handed over',
                    'Outward/dispatch records handed over',
                    'Pending shipment records handed over',
                    'Shipment exception and issue records handed over',
                    'Customer/client coordination details handed over',
                    'Vendor/service provider details handed over',
                    'Vendor performance and pending issues handed over',
                    'Warehouse layout and operational details handed over',
                    'Equipment and machinery records handed over',
                    'Equipment maintenance and repair records handed over',
                    'Asset register and warehouse asset details handed over',
                    'Safety documents and compliance records handed over',
                    'Safety incidents and corrective action records handed over',
                    'Security coordination and access control details handed over',
                    'Gate entry/exit records handed over',
                    'Housekeeping and facility maintenance records handed over',
                    'Warehouse keys/access cards returned',
                    'Warehouse documents, registers, and files returned',
                    'System/software access handed over or disabled',
                    'Warehouse system login credentials and passwords handed over',
                    'Official email access handed over and disabled',
                    'Company laptop/desktop returned (if issued)',
                    'Company mobile phone/SIM card returned (if issued)',
                    'Company ID card returned',
                    'Pending reimbursement claims submitted',
                    'Petty cash/advance settlement completed (if applicable)',
                    'No pending customer/vendor/operational commitments',
                    'No company data, documents, or confidential information retained'
                ]
            ]]
        ],
        'logistic executive' => [
            'signatory_title' => 'Manager',
            'declaration_text' => "I hereby confirm that I have handed over all warehouse and logistics activities, shipment details, inventory records, documents, system access, passwords, company assets, and responsibilities assigned to me. I confirm that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Logistics Executive - Warehouse Department Exit Clearance',
                'items' => [
                    'Daily warehouse and logistics activities handed over',
                    'Pending operational tasks handed over',
                    'Inbound shipment details handed over',
                    'Outbound shipment details handed over',
                    'Pending shipment status handed over',
                    'Shipment tracking details updated and handed over',
                    'Customer shipment records handed over',
                    'Customer coordination details handed over',
                    'Transport/vendor details handed over',
                    'Driver details and vehicle allocation records handed over',
                    'Vehicle placement and dispatch records handed over',
                    'Loading and unloading records handed over',
                    'Material inward records handed over',
                    'Material outward records handed over',
                    'Inventory/stock records handed over',
                    'Stock discrepancy records handed over',
                    'Damaged shipment/material records handed over',
                    'Shortage and excess material records handed over',
                    'Shipment exception and issue records handed over',
                    'POD (Proof of Delivery) records handed over',
                    'LR/transport documents handed over',
                    'Challans and shipment documents handed over',
                    'Warehouse registers and operational files handed over',
                    'Daily logistics reports submitted',
                    'Weekly/monthly logistics reports submitted',
                    'Warehouse system/CRM/TMS details updated',
                    'System login credentials and passwords handed over',
                    'Official email access handed over and disabled',
                    'Official communication groups and updates handed over',
                    'Warehouse keys/access card returned (if issued)',
                    'Company laptop/desktop returned (if issued)',
                    'Company mobile phone/SIM card returned (if issued)',
                    'Company ID card returned',
                    'Pending vendor/customer follow-up details handed over',
                    'Pending reimbursement claims submitted',
                    'Petty cash/advance settlement completed (if applicable)',
                    'No pending warehouse/logistics responsibilities',
                    'No company documents, data, or confidential information retained'
                ]
            ]]
        ],
        'telecalling executive' => [
            'signatory_title' => 'Manager',
            'declaration_text' => "I hereby confirm that I have handed over all lead generation records, customer details, follow-up information, CRM data, documents, system access, passwords, company assets, and responsibilities assigned to me. I confirm that I have not retained any company customer data or confidential information.",
            'headings' => [[
                'name' => 'Telecaller - Lead Generation Department Exit Clearance',
                'items' => [
                    'Complete lead generation activities handed over',
                    'Daily calling reports submitted',
                    'Weekly/monthly calling reports submitted',
                    'Lead database handed over',
                    'New leads generated details handed over',
                    'Follow-up lead details handed over',
                    'Interested customer/prospect details handed over',
                    'Not interested customer details updated and handed over',
                    'Pending callback/follow-up list handed over',
                    'Lead status updated in CRM/system',
                    'CRM login details and access handed over (if applicable)',
                    'Customer contact details and communication history handed over',
                    'Sales team follow-up leads transferred',
                    'Appointment/meeting schedules handed over',
                    'Customer queries and pending issues handed over',
                    'Call scripts and communication formats handed over',
                    'Campaign-wise lead details handed over',
                    'Lead source details handed over',
                    'Customer feedback records handed over',
                    'Company mobile/SIM card returned (if issued)',
                    'Company laptop/desktop/headset returned (if issued)',
                    'Company email access handed over and disabled',
                    'All company passwords and login credentials handed over',
                    'Official WhatsApp/business communication access handed over',
                    'Lead-related documents and files returned',
                    'Pending reimbursement claims submitted',
                    'No pending customer follow-ups or lead commitments',
                    'No company customer data or confidential information retained'
                ]
            ]]
        ],
        'delivery agent' => [
            'signatory_title' => 'Manager',
            'declaration_text' => "I hereby confirm that I have completed the handover of all assigned deliveries, customer details, shipment records, company assets, documents, system access, and other responsibilities assigned to me. I confirm that I have not retained any company property or confidential information.",
            'headings' => [[
                'name' => 'Delivery Agent Exit Clearance',
                'items' => [
                    'All assigned deliveries completed or handed over',
                    'Pending delivery details handed over',
                    'Undelivered shipment details handed over',
                    'Customer delivery details and communication handed over',
                    'Delivery status updated in system/application',
                    'Delivery proof (POD) records submitted',
                    'Customer acknowledgement/signature records handed over',
                    'Return shipment details handed over',
                    'Damaged shipment records handed over',
                    'Shortage/missing shipment records handed over',
                    'Delivery exception/issues details handed over',
                    'Cash collection/payment collection details handed over (if applicable)',
                    'Pending cash/payment settlement completed',
                    'Company/customer documents returned',
                    'Delivery bags/equipment/tools returned (if issued)',
                    'Company vehicle/bike returned (if provided)',
                    'Vehicle documents/keys returned (if applicable)',
                    'Fuel card/fuel advance settled (if applicable)',
                    'Company mobile phone/SIM card returned (if issued)',
                    'Delivery application login access handed over/disabled',
                    'All company passwords and login credentials handed over',
                    'Attendance and shift records updated',
                    'Pending salary advance/loan settlement completed',
                    'Pending reimbursement claims submitted',
                    'Company ID card/uniform/access card returned (if issued)',
                    'No pending customer deliveries or company responsibilities',
                    'No company data, documents, or customer information retained'
                ]
            ]]
        ],
        'general helper' => [
            'signatory_title' => 'Supervisor',
            'declaration_text' => "I hereby confirm that I have completed my assigned work responsibilities and returned all company-provided items, materials, and assets issued to me. I confirm that I have no pending company dues or company property with me.",
            'headings' => [[
                'name' => 'General Helper Exit Clearance',
                'items' => [
                    'Assigned work responsibilities completed or properly handed over',
                    'Pending work/task details informed to supervisor',
                    'Work area and assigned location handed over properly',
                    'Company uniform returned (if issued)',
                    'Company ID card returned (if issued)',
                    'Safety equipment returned (if issued)',
                    'Tools/equipment/material handling items returned (if issued)',
                    'Any company-provided items received by employee returned',
                    'Damaged or lost company items reported (if any)',
                    'Attendance records verified',
                    'Leave and absence records updated',
                    'Salary advance/loan settlement completed (if applicable)',
                    'Pending salary-related issues cleared',
                    'Pending reimbursement/expense settlement completed (if applicable)',
                    'Accommodation/room items returned (if company provided)',
                    'Company documents/materials returned (if any)',
                    'No pending company dues from employee',
                    'No company property retained by the employee'
                ]
            ]]
        ]
    ];
    if (isset($defaults[$key])) return $defaults[$key];
    foreach ($defaults as $k => $v) {
        if (strpos($key, $k) !== false || strpos($k, $key) !== false) {
            return $v;
        }
    }
    return null;
}

// =========================================================================
// SEED DEFAULT CLEARANCE TEMPLATES FROM THE BACKEND (one-time, idempotent)
// HR asked for these 3 positions to be pre-created without clicking through the
// Department/Position/Position Head picker each time. Department is resolved
// automatically from the position's own hr_positions record (no guessing).
// Position Head is left unassigned (NULL) — HR assigns the actual person later
// from Manage Clearance Template; Give Access is blocked until they do.
// =========================================================================
foreach ([
    'Logistic Coordinator for PTL', 'Delivery Agent', 'General Helper', 'HR and Admin',
    'Sales and Marketing Executive', 'Software Developer', 'Digital Marketing Executive', 'Procurment and marketing',
    'Logistic Coordinator for FTL', 'Civil Engineer Executive', 'Admin Executive', 'Finance Executive',
    'Warehouse Site Supervisor', 'Warehouse Manager', 'Logistic Executive', 'Telecalling Executive',
] as $csTitle) {
    $csTitle_e = mysqli_real_escape_string($con, $csTitle);
    $csPos = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, department_id FROM hr_positions WHERE title='$csTitle_e' LIMIT 1"));
    if (!$csPos) continue; // position doesn't exist in this system yet — nothing to attach the template to
    $csDeptId = intval($csPos['department_id']);
    $csPosId = intval($csPos['id']);
    if ($csDeptId <= 0) continue;

    $csDefault = clearanceDefaultTemplateFor($csTitle);
    if (!$csDefault) continue;

    // Reuse the template if it already exists (e.g. created manually, or by an earlier buggy
    // run before hr_exit_clearance_checklist_items had its own table) instead of skipping it —
    // otherwise it stays permanently empty. Existing signatory_title/declaration_text/position
    // head are left untouched so we never clobber something HR already set.
    $csExisting = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_clearance_templates WHERE department_id=$csDeptId AND position_id=$csPosId LIMIT 1"));
    if ($csExisting) {
        $csTemplateId = intval($csExisting['id']);
    } else {
        $cs_sig_e = mysqli_real_escape_string($con, $csDefault['signatory_title']);
        $cs_decl_e = mysqli_real_escape_string($con, $csDefault['declaration_text']);
        mysqli_query($con, "INSERT INTO hr_exit_clearance_templates (department_id, position_id, position_head_employee_id, signatory_title, declaration_text, created_by) VALUES ($csDeptId, $csPosId, NULL, '$cs_sig_e', '$cs_decl_e', 'system_seed')");
        $csTemplateId = mysqli_insert_id($con);
    }

    $cs_hsort = 0;
    foreach ($csDefault['headings'] as $csHeading) {
        $cs_hname_e = mysqli_real_escape_string($con, $csHeading['name']);
        $csHeadingRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_clearance_headings WHERE template_id=$csTemplateId AND heading_name='$cs_hname_e' LIMIT 1"));
        if ($csHeadingRow) {
            $cs_heading_id = intval($csHeadingRow['id']);
        } else {
            mysqli_query($con, "INSERT INTO hr_exit_clearance_headings (template_id, heading_name, sort_order) VALUES ($csTemplateId, '$cs_hname_e', $cs_hsort)");
            $cs_heading_id = mysqli_insert_id($con);
        }
        // Only backfill items into this heading if it doesn't already have any — avoids
        // duplicating items on a heading that's already correctly populated.
        $csItemCount = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_clearance_checklist_items WHERE heading_id=$cs_heading_id"));
        if (intval($csItemCount['c']) == 0) {
            $cs_isort = 0;
            foreach ($csHeading['items'] as $csItemText) {
                $cs_item_e = mysqli_real_escape_string($con, $csItemText);
                mysqli_query($con, "INSERT INTO hr_exit_clearance_checklist_items (heading_id, item_text, sort_order) VALUES ($cs_heading_id, '$cs_item_e', $cs_isort)");
                $cs_isort++;
            }
        }
        $cs_hsort++;
    }
}

// =========================================================================
// ASSET HANDOVER — PRINTABLE DOCUMENT (early exit, before any page HTML)
// =========================================================================
if (isset($_GET['view_asset_doc'])) {
    $va_exit_id = intval($_GET['view_asset_doc']);
    $va_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$va_exit_id LIMIT 1"));
    if (!$va_exitRow) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Exit record not found.</h3></div>"); }
    $va_empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($va_exitRow['employee_id']) . " LIMIT 1"));
    $va_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_asset_instance WHERE exit_id=$va_exit_id LIMIT 1"));
    if (!$va_instance) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Asset handover checklist has not been started for this exit yet.</h3></div>"); }
    if ($va_instance['status'] === 'not_applicable') { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Asset Handover was marked as not applicable for this employee — there is no document to show.</h3></div>"); }
    $va_cs = getExitCompanySettings($con, intval($va_empRow['id'] ?? 0));
    $va_items_res = mysqli_query($con, "SELECT * FROM hr_exit_asset_run_items WHERE instance_id=" . intval($va_instance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
    $va_grouped = [];
    while ($vi = mysqli_fetch_assoc($va_items_res)) {
        $vk = $vi['heading_name'];
        if (!isset($va_grouped[$vk])) $va_grouped[$vk] = ['show_condition_field' => $vi['show_condition_field'], 'items' => []];
        $va_grouped[$vk]['items'][] = $vi;
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>Employee Asset Return Checklist — <?php echo htmlspecialchars($va_empRow['name'] ?? ''); ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <style>
    body { font-family: Arial, sans-serif; background: #f0f4f8; padding: 20px; color: #000; }
    .pdf-preview { width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.2); border-radius: 0; box-sizing: border-box; }
    .pdf-content-wrapper { padding: 0 20mm; }
    table { width: 100%; border-collapse: collapse; }
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;margin-top:40px;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:center;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;}
    .letter-header-left{font-size:19px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:0;margin-left:30px;}
    .letter-header-left span{display:flex;align-items:center;gap:10px;}
    .letter-header-left i{width:26px;text-align:center;font-size:26px;}
    .letter-header-right{text-align:right;}
    .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
    .doc-title { font-size:16px; font-weight:800; text-align:center; text-decoration:underline; margin:25px 0; color:#0f2557; }
    .doc-field-row { display:flex; flex-wrap:wrap; gap:0 24px; margin-bottom:18px; }
    .doc-field { width:47%; margin-bottom:14px; }
    .doc-field label { font-weight:700; font-size:12px; display:block; margin-bottom:4px; color:#334155; text-transform:uppercase; letter-spacing:.3px; }
    .doc-field .val { border-bottom:1px solid #94a3b8; padding:6px 4px; font-size:14px; min-height:18px; }
    table.asset-tbl { width:100%; border-collapse:collapse; margin:16px 0 26px; font-size:12.5px; table-layout:fixed; }
    table.asset-tbl col.a-no { width:6%; }
    table.asset-tbl col.a-item { width:30%; }
    table.asset-tbl col.a-ret { width:10%; }
    table.asset-tbl col.a-cond { width:24%; }
    table.asset-tbl col.a-remarks { width:30%; }
    table.asset-tbl th, table.asset-tbl td { box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; text-align:left; vertical-align:middle; overflow-wrap:break-word; word-break:break-word; }
    table.asset-tbl th { background:#0f2557; color:#fff; font-weight:700; font-size:11px; text-transform:uppercase; letter-spacing:0.3px; }
    table.asset-tbl tbody tr:nth-child(even) { background:#f8faff; }
    .section-heading { font-weight:800; color:#0f2557; font-size:14px; margin:20px 0 10px; padding-bottom:6px; border-bottom:2px solid #eef2ff; }
    .checklist-item { font-size:13px; color:#334155; margin-bottom:8px; padding-left:26px; position:relative; }
    .checklist-item .box { position:absolute; left:0; top:1px; width:16px; height:16px; border:2px solid #94a3b8; border-radius:3px; display:inline-block; background:#fff; }
    .checklist-item .box.checked { background:#0f2557; border-color:#0f2557; }
    .checklist-item .box.checked i { color:#fff; font-size:10px; position:absolute; left:2px; top:1px; }
    .checklist-item .remark { color:#64748b; font-style:italic; margin-left:6px; }
    .sig-area { margin-top:40px; display:flex; justify-content:space-between; }
    .sig-box { width:260px; }
    .sig-box img { max-height:110px; max-width:260px; }
    .sig-line { border-top:1px solid #334155; margin-top:8px; padding-top:6px; font-size:12px; font-weight:700; }
    .no-print { text-align:center; margin-bottom:20px; }
    .print-only-spacer, .print-only-spacer-foot { display: none; }
    @media print{
        @page { margin: 0; }
        body { padding: 0 !important; margin: 0 !important; background: #fff !important; }
        .no-print { display: none !important; }
        * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
        .pdf-preview { padding: 0 !important; margin: 0 !important; width: 100% !important; min-height: 0 !important; border: none !important; box-shadow: none !important; max-width: none !important; }
        .letter-wave-top { position: fixed !important; top: 0 !important; left: 0 !important; right: 0 !important; z-index: 10 !important; }
        .letter-header { position: fixed !important; top: 70px !important; left: 0 !important; right: 0 !important; z-index: 10 !important; }
        .letter-wave-bottom { position: fixed !important; bottom: 0 !important; left: 0 !important; right: 0 !important; margin-top: 0 !important; z-index: 10 !important; }
        .print-only-spacer { display: table-header-group !important; }
        .print-only-spacer-foot { display: table-footer-group !important; }
        .pdf-content-wrapper { margin-top: 0 !important; }
        table.asset-tbl tr, .checklist-item, .doc-field-row, .section-heading, .sig-area { page-break-inside: avoid; break-inside: avoid; }
    }
    </style>
    </head>
    <body>
    <div class="no-print">
       <button onclick="window.print()" style="padding:14px 28px; background:#0f2557; color:#fff; border:none; border-radius:10px; font-weight:bold; cursor:pointer;">🖨️ Print / Save as PDF</button>
    </div>
    <div class="pdf-preview">
        <div class="letter-wave-top">
            <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
                <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
            </svg>
        </div>
        <div class="letter-header">
            <div class="letter-header-left">
                <?php if($va_cs['company_phone'] ?? ''): ?><span><i class="fas fa-phone-alt"></i> <?php echo htmlspecialchars($va_cs['company_phone']); ?></span><?php endif; ?>
                <?php if($va_cs['company_email'] ?? ''): ?><span><i class="fas fa-envelope"></i> <?php echo htmlspecialchars($va_cs['company_email']); ?></span><?php endif; ?>
                <?php if($va_cs['company_website'] ?? ''): ?><span><i class="fas fa-globe"></i> <?php echo htmlspecialchars($va_cs['company_website']); ?></span><?php endif; ?>
                <?php if (empty($va_cs['company_phone']) && empty($va_cs['company_email']) && empty($va_cs['company_website']) && !empty($va_cs['company_name'])): ?>
                <span style="font-size:15px;font-weight:800;"><?php echo htmlspecialchars($va_cs['company_name']); ?></span>
                <?php endif; ?>
            </div>
            <div class="letter-header-right">
                <?php if (!empty($va_cs['company_logo'])): ?><img src="<?php echo htmlspecialchars($va_cs['company_logo']); ?>" alt="Logo"><?php endif; ?>
            </div>
        </div>
        <table style="width:100%; border-collapse:collapse; border:none;">
        <thead class="print-only-spacer"><tr><td style="height: 260px; border:none;"></td></tr></thead>
        <tbody><tr><td style="padding: 0; border:none;">
        <div class="pdf-content-wrapper">
            <div class="doc-title">Employee Asset Return Checklist</div>

            <div class="doc-field-row">
                <div class="doc-field"><label>Employee Name</label><div class="val"><?php echo htmlspecialchars($va_empRow['name'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Employee ID</label><div class="val"><?php echo htmlspecialchars($va_empRow['employee_id'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Department</label><div class="val"><?php echo htmlspecialchars($va_empRow['department'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Designation</label><div class="val"><?php echo htmlspecialchars($va_empRow['position'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Last Working Day</label><div class="val"><?php echo $va_exitRow['final_last_working_day'] ? date('d M Y', strtotime($va_exitRow['final_last_working_day'])) : '—'; ?></div></div>
            </div>

            <?php foreach ($va_grouped as $vh_name => $vh_data): ?>
                <div class="section-heading"><?php echo htmlspecialchars($vh_name); ?></div>
                <?php if ($vh_data['show_condition_field']): ?>
                <table class="asset-tbl">
                    <colgroup>
                        <col class="a-no"><col class="a-item"><col class="a-ret"><col class="a-cond"><col class="a-remarks">
                    </colgroup>
                    <thead><tr><th style="width:6%;">Sl. No.</th><th style="width:30%;">Asset</th><th style="width:10%;">Returned</th><th style="width:24%;">Condition</th><th style="width:30%;">Remarks</th></tr></thead>
                    <tbody>
                    <?php foreach ($vh_data['items'] as $vidx => $vit): ?>
                    <tr>
                        <td style="text-align:center;"><?php echo $vidx+1; ?></td>
                        <td><?php echo htmlspecialchars($vit['item_text']); ?></td>
                        <td style="text-align:center;font-weight:800;"><?php echo $vit['is_checked'] ? '&#10003;' : ''; ?></td>
                        <td><?php echo htmlspecialchars($vit['condition_text'] ?? ''); ?></td>
                        <td><?php echo htmlspecialchars($vit['remarks'] ?? ''); ?></td>
                    </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
                <?php else: ?>
                <table class="asset-tbl">
                    <colgroup>
                        <col class="a-no"><col class="a-item"><col class="a-ret"><col class="a-remarks" style="width:24%;">
                    </colgroup>
                    <thead><tr><th style="width:6%;">Sl. No.</th><th style="width:30%;">Asset</th><th style="width:10%;">Returned</th><th>Remarks</th></tr></thead>
                    <tbody>
                    <?php foreach ($vh_data['items'] as $vidx => $vit): ?>
                    <tr>
                        <td style="text-align:center;"><?php echo $vidx+1; ?></td>
                        <td><?php echo htmlspecialchars($vit['item_text']); ?></td>
                        <td style="text-align:center;font-weight:800;"><?php echo $vit['is_checked'] ? '&#10003;' : ''; ?></td>
                        <td><?php echo htmlspecialchars($vit['remarks'] ?? ''); ?></td>
                    </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
                <?php endif; ?>
            <?php endforeach; ?>

            <?php if (empty($va_grouped)): ?>
                <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist items recorded.</p>
            <?php endif; ?>

            <div class="sig-area">
                <div class="sig-box">
                    <?php if (!empty($va_cs['company_signature'])): ?>
                        <img src="<?php echo htmlspecialchars($va_cs['company_signature']); ?>" alt="Company Signature">
                    <?php else: ?>
                        <div style="height:70px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        Management Signature<br>
                        For <?php echo htmlspecialchars($va_cs['company_name'] ?? (isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'the Company')); ?>
                    </div>
                </div>
                <div class="sig-box">
                    <?php if (!empty($va_instance['signature_data'])): ?>
                        <img src="<?php echo htmlspecialchars($va_instance['signature_data']); ?>" alt="Employee Signature">
                    <?php else: ?>
                        <div style="height:70px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        Signature: <?php echo htmlspecialchars($va_empRow['name'] ?? ''); ?><br>
                        Date: <?php echo !empty($va_instance['signed_at']) ? date('d M Y', strtotime($va_instance['signed_at'])) : '_______________________'; ?>
                    </div>
                </div>
            </div>
        </div>
        </td></tr></tbody>
        <tfoot class="print-only-spacer-foot"><tr><td style="height: 100px; border:none;"></td></tr></tfoot>
        </table>
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>
    </div>
    </body>
    </html>
    <?php
    exit;
}

// =========================================================================
// DEPARTMENT-POSITION CLEARANCE — PRINTABLE DOCUMENT
// =========================================================================
if (isset($_GET['view_clearance_doc'])) {
    $vc_exit_id = intval($_GET['view_clearance_doc']);
    $vc_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$vc_exit_id LIMIT 1"));
    if (!$vc_exitRow) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Exit record not found.</h3></div>"); }
    $vc_empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($vc_exitRow['employee_id']) . " LIMIT 1"));
    $vc_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE exit_id=$vc_exit_id LIMIT 1"));
    if (!$vc_instance) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Department-Position Clearance has not been started for this exit yet.</h3></div>"); }
    if ($vc_instance['status'] === 'not_applicable') { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Department-Position Clearance was marked as not applicable for this employee — there is no document to show.</h3></div>"); }
    $vc_template = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE id=" . intval($vc_instance['template_id']) . " LIMIT 1"));
    $vc_headRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_employees WHERE id=" . intval($vc_instance['position_head_employee_id']) . " LIMIT 1"));
    $vc_signatory_title = $vc_template['signatory_title'] ?? 'Position Head';
    $vc_cs = getExitCompanySettings($con, intval($vc_empRow['id'] ?? 0));
    $vc_declaration = str_replace('{{name}}', htmlspecialchars($vc_empRow['name'] ?? ''), $vc_template['declaration_text'] ?? '');
    $vc_items_res = mysqli_query($con, "SELECT * FROM hr_exit_clearance_run_items WHERE instance_id=" . intval($vc_instance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
    $vc_grouped = [];
    while ($vci = mysqli_fetch_assoc($vc_items_res)) {
        $vck = $vci['heading_name'];
        if (!isset($vc_grouped[$vck])) $vc_grouped[$vck] = ['items' => []];
        $vc_grouped[$vck]['items'][] = $vci;
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>Department-Position Clearance — <?php echo htmlspecialchars($vc_empRow['name'] ?? ''); ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <style>
    body { font-family: Arial, sans-serif; background: #f0f4f8; padding: 20px; color: #000; }
    .pdf-preview { width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.2); border-radius: 0; box-sizing: border-box; }
    .pdf-content-wrapper { padding: 0 20mm; }
    table { width: 100%; border-collapse: collapse; }
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;margin-top:40px;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:center;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;margin-bottom:25px;}
    .letter-header-left{font-size:19px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:0;margin-left:30px;}
    .letter-header-left span{display:flex;align-items:center;gap:10px;}
    .letter-header-left i{width:26px;text-align:center;font-size:26px;}
    .letter-header-right{text-align:right;}
    .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
    .doc-title { font-size:16px; font-weight:800; text-align:center; text-decoration:underline; margin:25px 0; color:#0f2557; }
    .doc-field-row { display:flex; flex-wrap:wrap; gap:0 24px; margin-bottom:18px; }
    .doc-field { width:47%; margin-bottom:14px; }
    .doc-field label { font-weight:700; font-size:12px; display:block; margin-bottom:4px; color:#334155; text-transform:uppercase; letter-spacing:.3px; }
    .doc-field .val { border-bottom:1px solid #94a3b8; padding:6px 4px; font-size:14px; min-height:18px; }
    table.clr-tbl { width:100%; border-collapse:collapse; margin:16px 0 26px; font-size:11.5px; table-layout:fixed; }
    table.clr-tbl col.c-no { width:5%; }
    table.clr-tbl col.c-item { width:45%; }
    table.clr-tbl col.c-chk { width:10%; }
    table.clr-tbl col.c-remarks { width:20%; }
    table.clr-tbl th, table.clr-tbl td { box-sizing:border-box; border:1px solid #cbd5e1; padding:7px 8px; text-align:left; vertical-align:middle; overflow-wrap:break-word; word-break:break-word; }
    table.clr-tbl th { background:#0f2557; color:#fff; font-weight:700; font-size:10.5px; text-transform:uppercase; letter-spacing:0.3px; }
    table.clr-tbl tbody tr:nth-child(even) { background:#f8faff; }
    table.clr-tbl td.chk { text-align:center; font-weight:800; vertical-align:middle; padding:0; }
    table.clr-tbl td.chk span.chkmark { display:inline-block; width:100%; text-align:center; }
    .section-heading { font-weight:800; color:#0f2557; font-size:14px; margin:20px 0 10px; padding-bottom:6px; border-bottom:2px solid #eef2ff; }
    .declaration { font-size:13px; line-height:1.8; color:#1a202c; margin:24px 0; white-space:pre-wrap; background:#f8fafc; border:1px solid #e2e8f0; border-radius:8px; padding:14px 16px; }
    .sig-area { margin-top:40px; display:flex; justify-content:space-between; gap:16px; }
    .sig-box { width:31%; }
    .sig-box img { max-height:120px; max-width:200px; }
    .sig-line { border-top:1px solid #334155; margin-top:8px; padding-top:6px; font-size:13.5px; font-weight:700; line-height:1.4; }
    .no-print { text-align:center; margin-bottom:20px; }
    @media print{
        @page { margin: 0; }
        body { padding: 0 !important; margin: 0 !important; background: #fff !important; }
        .no-print { display: none !important; }
        * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
        .pdf-preview { padding: 0 !important; margin: 0 !important; width: 100% !important; min-height: 0 !important; border: none !important; box-shadow: none !important; max-width: none !important; }
        thead { display: table-header-group; }
        tfoot { display: table-footer-group; }
        table.clr-tbl tr, .declaration, .sig-area { page-break-inside: avoid; break-inside: avoid; }
    }
    </style>
    </head>
    <body>
    <div class="no-print">
       <button onclick="window.print()" style="padding:14px 28px; background:#0f2557; color:#fff; border:none; border-radius:10px; font-weight:bold; cursor:pointer;">🖨️ Print / Save as PDF</button>
    </div>
    <div class="pdf-preview">
        <table style="width:100%; border-collapse:collapse; border:none;">
        <thead><tr><td style="padding:0; border:none;">
        <div class="letter-wave-top">
            <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
                <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
            </svg>
        </div>
        <div class="letter-header">
            <div class="letter-header-left">
                <?php if($vc_cs['company_phone'] ?? ''): ?><span><i class="fas fa-phone-alt"></i> <?php echo htmlspecialchars($vc_cs['company_phone']); ?></span><?php endif; ?>
                <?php if($vc_cs['company_email'] ?? ''): ?><span><i class="fas fa-envelope"></i> <?php echo htmlspecialchars($vc_cs['company_email']); ?></span><?php endif; ?>
                <?php if($vc_cs['company_website'] ?? ''): ?><span><i class="fas fa-globe"></i> <?php echo htmlspecialchars($vc_cs['company_website']); ?></span><?php endif; ?>
                <?php if (empty($vc_cs['company_phone']) && empty($vc_cs['company_email']) && empty($vc_cs['company_website']) && !empty($vc_cs['company_name'])): ?>
                <span style="font-size:15px;font-weight:800;"><?php echo htmlspecialchars($vc_cs['company_name']); ?></span>
                <?php endif; ?>
            </div>
            <div class="letter-header-right">
                <?php if (!empty($vc_cs['company_logo'])): ?><img src="<?php echo htmlspecialchars($vc_cs['company_logo']); ?>" alt="Logo"><?php endif; ?>
            </div>
        </div>
        </td></tr></thead>
        <tbody><tr><td style="padding: 0; border:none;">
        <div class="pdf-content-wrapper">
            <div class="doc-title">Department-Position Clearance</div>

            <div class="doc-field-row">
                <div class="doc-field"><label>Employee Name</label><div class="val"><?php echo htmlspecialchars($vc_empRow['name'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Employee ID</label><div class="val"><?php echo htmlspecialchars($vc_empRow['employee_id'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Department</label><div class="val"><?php echo htmlspecialchars($vc_empRow['department'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Designation</label><div class="val"><?php echo htmlspecialchars($vc_empRow['position'] ?? ''); ?></div></div>
                <div class="doc-field"><label>Last Working Day</label><div class="val"><?php echo $vc_exitRow['final_last_working_day'] ? date('d M Y', strtotime($vc_exitRow['final_last_working_day'])) : '—'; ?></div></div>
                <div class="doc-field"><label><?php echo htmlspecialchars($vc_signatory_title); ?></label><div class="val"><?php echo htmlspecialchars($vc_headRow['name'] ?? ''); ?></div></div>
            </div>

            <?php foreach ($vc_grouped as $vch_name => $vch_data): ?>
                <div class="section-heading"><?php echo htmlspecialchars($vch_name); ?></div>
                <table class="clr-tbl">
                    <colgroup>
                        <col class="c-no"><col class="c-item"><col class="c-chk"><col class="c-chk"><col class="c-chk"><col class="c-remarks">
                    </colgroup>
                    <thead><tr><th>S.No.</th><th>Clearance Item</th><th>Yes</th><th>No</th><th>N/A</th><th>Remarks</th></tr></thead>
                    <tbody>
                    <?php foreach ($vch_data['items'] as $vcidx => $vcit): ?>
                    <tr>
                        <td><?php echo $vcidx+1; ?></td>
                        <td><?php echo htmlspecialchars($vcit['item_text']); ?></td>
                        <td class="chk"><?php echo $vcit['response']==='yes' ? '<span class="chkmark">&#10003;</span>' : ''; ?></td>
                        <td class="chk"><?php echo $vcit['response']==='no' ? '<span class="chkmark">&#10003;</span>' : ''; ?></td>
                        <td class="chk"><?php echo $vcit['response']==='na' ? '<span class="chkmark">&#10003;</span>' : ''; ?></td>
                        <td><?php echo htmlspecialchars($vcit['remarks'] ?? ''); ?></td>
                    </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endforeach; ?>

            <?php if (empty($vc_grouped)): ?>
                <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist items recorded.</p>
            <?php endif; ?>

            <?php if (!empty($vc_declaration)): ?>
            <div class="declaration"><?php echo nl2br($vc_declaration); ?></div>
            <?php endif; ?>

            <?php if (!empty($vc_instance['employee_remarks'])): ?>
            <div class="doc-field" style="width:100%; margin-top:20px;">
                <label>Employee Remarks</label>
                <div class="val" style="border:none; padding:10px; background:#f8fafc; border-radius:6px; line-height:1.6;">
                    <?php echo nl2br(htmlspecialchars($vc_instance['employee_remarks'])); ?>
                </div>
            </div>
            <?php endif; ?>

            <?php if (!empty($vc_instance['position_head_remarks'])): ?>
            <div class="doc-field" style="width:100%; margin-top:20px;">
                <label><?php echo htmlspecialchars($vc_signatory_title); ?> Remarks</label>
                <div class="val" style="border:none; padding:10px; background:#f8fafc; border-radius:6px; line-height:1.6;">
                    <?php echo nl2br(htmlspecialchars($vc_instance['position_head_remarks'])); ?>
                </div>
            </div>
            <?php endif; ?>

            <div class="sig-area">
                <div class="sig-box">
                    <?php if (!empty($vc_cs['company_signature'])): ?>
                        <img src="<?php echo htmlspecialchars($vc_cs['company_signature']); ?>" alt="Company Signature">
                    <?php else: ?>
                        <div style="height:70px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        Management Signature<br>
                        For <?php echo htmlspecialchars($vc_cs['company_name'] ?? (isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'the Company')); ?><br>
                        &nbsp;
                    </div>
                </div>
                <div class="sig-box">
                    <?php if (!empty($vc_instance['employee_signature_data'])): ?>
                        <img src="<?php echo htmlspecialchars($vc_instance['employee_signature_data']); ?>" alt="Employee Signature">
                    <?php else: ?>
                        <div style="height:70px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        Employee Signature<br>
                        <?php echo htmlspecialchars($vc_empRow['name'] ?? ''); ?><br>
                        Date: <?php echo !empty($vc_instance['employee_signed_at']) ? date('d M Y', strtotime($vc_instance['employee_signed_at'])) : '_______________________'; ?>
                    </div>
                </div>
                <div class="sig-box">
                    <?php if (!empty($vc_instance['position_head_signature_data'])): ?>
                        <img src="<?php echo htmlspecialchars($vc_instance['position_head_signature_data']); ?>" alt="<?php echo htmlspecialchars($vc_signatory_title); ?> Signature">
                    <?php else: ?>
                        <div style="height:70px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        <?php echo htmlspecialchars($vc_signatory_title); ?><br>
                        <?php echo htmlspecialchars($vc_headRow['name'] ?? ''); ?><br>
                        Date: <?php echo !empty($vc_instance['position_head_signed_at']) ? date('d M Y', strtotime($vc_instance['position_head_signed_at'])) : '_______________________'; ?>
                    </div>
                </div>
            </div>
        </div>
        </td></tr></tbody>
        <tfoot><tr><td style="padding:0; border:none;">
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>
        </td></tr></tfoot>
        </table>
    </div>
    </body>
    </html>
    <?php
    exit;
}

// =========================================================================
// DEPARTMENT-POSITION CLEARANCE — POSITION HEAD REVIEW (token link, no login)
// =========================================================================
if ($ph_token_ok && isset($_GET['ph_review']) && !isset($_POST['ajax_action'])) {
    $phv_instance = $ph_token_instance;
    $phv_empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($phv_instance['employee_id']) . " LIMIT 1"));
    $phv_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=" . intval($phv_instance['exit_id']) . " LIMIT 1"));
    $phv_template = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE id=" . intval($phv_instance['template_id']) . " LIMIT 1"));
    $phv_signatory_title = $phv_template['signatory_title'] ?? 'Position Head';
    $phv_declaration = str_replace('{{name}}', htmlspecialchars($phv_empRow['name'] ?? ''), $phv_template['declaration_text'] ?? '');
    $phv_items_res = mysqli_query($con, "SELECT * FROM hr_exit_clearance_run_items WHERE instance_id=" . intval($phv_instance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
    $phv_grouped = [];
    while ($phvi = mysqli_fetch_assoc($phv_items_res)) {
        $phvk = $phvi['heading_name'];
        if (!isset($phv_grouped[$phvk])) $phv_grouped[$phvk] = ['items' => []];
        $phv_grouped[$phvk]['items'][] = $phvi;
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>Clearance Review — <?php echo htmlspecialchars($phv_empRow['name'] ?? ''); ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <style>
    :root{--navy:#0f2557;--teal:#0f766e;}
    *{box-sizing:border-box;}
    body{font-family:Arial,sans-serif;background:#f0f4f8;padding:20px;color:#1a202c;margin:0;}
    .wrap{max-width:760px;margin:0 auto;background:#fff;border-radius:12px;box-shadow:0 4px 20px rgba(0,0,0,.08);overflow:hidden;}
    .hdr{background:linear-gradient(135deg,var(--navy),var(--teal));color:#fff;padding:20px 26px;}
    .hdr h2{margin:0;font-size:18px;}
    .hdr p{margin:4px 0 0;font-size:12.5px;opacity:.9;}
    .body{padding:22px 26px;}
    .info-row{display:flex;flex-wrap:wrap;gap:16px;margin-bottom:18px;padding:12px 14px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;font-size:12.5px;}
    .section-heading{font-weight:800;color:var(--navy);font-size:13px;margin:16px 0 8px;padding-bottom:5px;border-bottom:2px solid #eef2ff;}
    table.clr-tbl{width:100%;border-collapse:collapse;margin:8px 0 14px;font-size:11.5px;table-layout:fixed;}
    table.clr-tbl col.c-no{width:5%;}
    table.clr-tbl col.c-item{width:45%;}
    table.clr-tbl col.c-chk{width:10%;}
    table.clr-tbl col.c-remarks{width:20%;}
    table.clr-tbl th,table.clr-tbl td{box-sizing:border-box;border:1px solid #cbd5e1;padding:6px 8px;text-align:left;vertical-align:middle;overflow-wrap:break-word;word-break:break-word;}
    table.clr-tbl th{background:var(--navy);color:#fff;font-weight:700;font-size:10px;text-transform:uppercase;}
    table.clr-tbl td.chk{text-align:center;font-weight:800;}
    table.clr-tbl tbody tr:nth-child(even){background:#f8faff;}
    .declaration{font-size:12.5px;line-height:1.7;color:#1a202c;margin:18px 0;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px 14px;}
    .fl{font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;}
    .fc{width:100%;padding:9px 12px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:13px;font-family:inherit;}
    .sig-pad-box{border:2px dashed #a78bfa;border-radius:10px;background:#faf5ff;padding:12px;max-width:500px;}
    .sig-pad-box canvas{width:100%;height:150px;border:1px solid #ddd6fe;border-radius:8px;background:#fff;cursor:crosshair;touch-action:none;display:block;}
    .btn-p{padding:10px 20px;border-radius:8px;font-weight:700;font-size:12.5px;border:none;cursor:pointer;}
    .btn-navy{background:linear-gradient(135deg,var(--navy),var(--teal));color:#fff;}
    .btn-red{background:#dc2626;color:#fff;}
    .btn-outline{background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;}
    .alert{padding:12px 16px;border-radius:8px;font-size:12.5px;margin:16px 0;}
    .alert-warning{background:#fef3c7;color:#92400e;}
    .alert-success{background:#d1fae5;color:#065f46;}
    </style>
    </head>
    <body>
    <div class="wrap">
      <div class="hdr">
        <h2><i class="fas fa-user-shield mr-1"></i> Department-Position Clearance Review</h2>
        <p>Hello <strong><?php echo htmlspecialchars($currentUserName); ?></strong>. You've been asked to review and sign off as <?php echo htmlspecialchars($phv_signatory_title); ?> for <?php echo htmlspecialchars($phv_empRow['name'] ?? ''); ?>'s exit.</p>
      </div>
      <div class="body">
        <div class="info-row">
          <div><strong>Employee:</strong> <?php echo htmlspecialchars($phv_empRow['name'] ?? ''); ?></div>
          <div><strong>Employee ID:</strong> <?php echo htmlspecialchars($phv_empRow['employee_id'] ?? '—'); ?></div>
          <div><strong>Department:</strong> <?php echo htmlspecialchars($phv_empRow['department'] ?? '—'); ?></div>
          <div><strong>Designation:</strong> <?php echo htmlspecialchars($phv_empRow['position'] ?? '—'); ?></div>
          <div><strong>Last Working Day:</strong> <?php echo $phv_exitRow['final_last_working_day'] ? date('d M Y', strtotime($phv_exitRow['final_last_working_day'])) : '—'; ?></div>
        </div>

        <?php if ($phv_instance['status'] === 'pending_employee_signature'): ?>
        <div style="background:#fff; border:1px solid #e2e8f0; border-radius:12px; padding:40px 20px; text-align:center; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1); margin:40px 0;">
            <div style="width:64px; height:64px; background:#d1fae5; border-radius:50%; display:flex; align-items:center; justify-content:center; margin:0 auto 20px;">
                <i class="fas fa-check" style="font-size:32px; color:#059669;"></i>
            </div>
            <h3 style="color:#111827; font-size:20px; margin:0 0 10px; font-weight:800;">Clearance Approved</h3>
            <p style="color:#4b5563; font-size:14px; line-height:1.6; max-width:440px; margin:0 auto;">
                You have successfully approved the clearance. We are currently waiting for the employee (<strong><?php echo htmlspecialchars($phv_empRow['name'] ?? ''); ?></strong>) to provide their digital signature.
            </p>
            <p style="color:#94a3b8; font-size:12px; margin-top:20px;">You can check back later using this same link.</p>
        </div>

        <?php else: ?>

        <?php $phv_readonly = !in_array($phv_instance['status'], ['in_progress', 'pending_position_head_review', 'rejected_by_position_head']); ?>
        <?php foreach ($phv_grouped as $phv_name => $phv_data): ?>
          <div class="section-heading"><?php echo htmlspecialchars($phv_name); ?></div>
          <table class="clr-tbl">
            <colgroup>
              <col class="c-no"><col class="c-item"><col class="c-chk"><col class="c-chk"><col class="c-chk"><col class="c-remarks">
            </colgroup>
            <thead><tr><th>S.No.</th><th>Clearance Item</th><th>Yes</th><th>No</th><th>N/A</th><th>Remarks</th></tr></thead>
            <tbody>
            <?php foreach ($phv_data['items'] as $phvidx => $phvit): ?>
            <tr>
              <td><?php echo $phvidx+1; ?></td>
              <td><?php echo htmlspecialchars($phvit['item_text']); ?></td>
              <td class="chk"><input type="radio" name="phvResp_<?php echo $phvit['id']; ?>" value="yes" <?php echo $phvit['response']==='yes'?'checked':''; ?> <?php echo $phv_readonly?'disabled':''; ?> onchange="phPost({ajax_action:'set_clearance_response', run_item_id:<?php echo $phvit['id']; ?>, response:'yes'})"></td>
              <td class="chk"><input type="radio" name="phvResp_<?php echo $phvit['id']; ?>" value="no" <?php echo $phvit['response']==='no'?'checked':''; ?> <?php echo $phv_readonly?'disabled':''; ?> onchange="phPost({ajax_action:'set_clearance_response', run_item_id:<?php echo $phvit['id']; ?>, response:'no'})"></td>
              <td class="chk"><input type="radio" name="phvResp_<?php echo $phvit['id']; ?>" value="na" <?php echo $phvit['response']==='na'?'checked':''; ?> <?php echo $phv_readonly?'disabled':''; ?> onchange="phPost({ajax_action:'set_clearance_response', run_item_id:<?php echo $phvit['id']; ?>, response:'na'})"></td>
              <td><input type="text" style="width:100%;border:1px solid #ddd;border-radius:4px;padding:4px;font-size:12px;" value="<?php echo htmlspecialchars($phvit['remarks'] ?? ''); ?>" <?php echo $phv_readonly?'readonly':''; ?> onblur="phPost({ajax_action:'save_clearance_item_remarks', run_item_id:<?php echo $phvit['id']; ?>, remarks:this.value})"></td>
            </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        <?php endforeach; ?>

        <?php if (empty($phv_grouped)): ?>
        <p style="text-align:center;color:#94a3b8;padding:16px;">No checklist items recorded.</p>
        <?php endif; ?>

        <?php if (!empty($phv_declaration)): ?>
        <div class="declaration"><?php echo nl2br($phv_declaration); ?></div>
        <?php endif; ?>

        <?php if (!empty($phv_instance['employee_signature_data'])): ?>
        <div style="margin:14px 0;">
          <div class="fl">Employee Signature</div>
          <img src="<?php echo htmlspecialchars($phv_instance['employee_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;">
        </div>
        <?php endif; ?>

        <?php if (in_array($phv_instance['status'], ['in_progress', 'pending_position_head_review'])): ?>
          <div class="fl" style="margin-top:16px;">Your Remarks (optional)</div>
          <textarea id="phRemarks" class="fc" rows="2"></textarea>
          <div class="fl" style="margin-top:14px;">Your Signature</div>
          <div class="sig-pad-box">
            <canvas id="phSigCanvas" width="460" height="150"></canvas>
            <div style="font-size:12px; color:#64748b; margin-top:6px; font-weight: 600;">Signatory: <?php echo htmlspecialchars($currentUserName); ?> (<?php echo htmlspecialchars($phv_signatory_title); ?>)</div>
            <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap;">
              <button type="button" class="btn-p btn-outline" onclick="phClearSig()">Clear</button>
              <button type="button" class="btn-p btn-navy" onclick="phApprove()"><i class="fas fa-check mr-1"></i> Sign &amp; Approve</button>
              <button type="button" class="btn-p btn-red" onclick="phReject()"><i class="fas fa-times mr-1"></i> Reject</button>
            </div>
          </div>
        <?php elseif ($phv_instance['status'] === 'rejected_by_position_head'): ?>
          <div class="alert alert-warning"><i class="fas fa-hourglass-half mr-1"></i> You rejected this — the employee needs to update and re-submit. You'll be able to review again once they do.</div>
        <?php elseif (!empty($phv_instance['position_head_signature_data'])): ?>
          <div style="margin:14px 0;">
            <div class="fl">Your Signature</div>
            <img src="<?php echo htmlspecialchars($phv_instance['position_head_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;">
          </div>
          <div class="alert alert-success"><i class="fas fa-check-circle mr-1"></i> You already signed off on this on <?php echo date('d M Y', strtotime($phv_instance['position_head_signed_at'])); ?>. <?php echo $phv_instance['status'] === 'completed' ? 'HR has given final approval.' : "Awaiting HR's final approval."; ?></div>
        <?php endif; ?>

        <?php endif; ?>
      </div>
    </div>
    <div id="phConfirmOverlay" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:9999;align-items:center;justify-content:center;">
        <div style="background:#fff;border-radius:12px;padding:30px;width:90%;max-width:400px;text-align:center;box-shadow:0 10px 25px rgba(0,0,0,0.2);">
            <div style="width:50px;height:50px;background:#fef3c7;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 16px;">
                <i class="fas fa-question" style="font-size:24px;color:#d97706;"></i>
            </div>
            <h3 style="margin:0 0 10px;color:#111827;font-size:18px;font-weight:800;">Confirm Approval</h3>
            <p style="color:#4b5563;font-size:14px;margin:0 0 24px;line-height:1.5;">Are you sure you want to sign and officially approve this clearance for the employee?</p>
            <div style="display:flex;gap:12px;justify-content:center;">
                <button type="button" class="btn-p btn-outline" style="flex:1;" onclick="document.getElementById('phConfirmOverlay').style.display='none'">Cancel</button>
                <button type="button" class="btn-p btn-navy" style="flex:1;" onclick="phSubmitApproval()">Yes, Approve</button>
            </div>
        </div>
    </div>

    <div id="phRejectOverlay" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:9999;align-items:center;justify-content:center;">
        <div style="background:#fff;border-radius:12px;padding:30px;width:90%;max-width:400px;text-align:center;box-shadow:0 10px 25px rgba(0,0,0,0.2);">
            <div style="width:50px;height:50px;background:#fee2e2;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 16px;">
                <i class="fas fa-times" style="font-size:24px;color:#dc2626;"></i>
            </div>
            <h3 style="margin:0 0 10px;color:#111827;font-size:18px;font-weight:800;">Reject Clearance</h3>
            <p style="color:#4b5563;font-size:14px;margin:0 0 16px;line-height:1.5;">Please provide a reason for rejecting (the employee will see this):</p>
            <textarea id="phRejectReason" class="fc" rows="3" style="margin-bottom:20px;"></textarea>
            <div style="display:flex;gap:12px;justify-content:center;">
                <button type="button" class="btn-p btn-outline" style="flex:1;" onclick="document.getElementById('phRejectOverlay').style.display='none'">Cancel</button>
                <button type="button" class="btn-p btn-red" style="flex:1;" onclick="phSubmitReject()">Yes, Reject</button>
            </div>
        </div>
    </div>

    <script>
    var phInstanceId = <?php echo intval($phv_instance['id']); ?>;
    var phToken = <?php echo json_encode($_GET['token']); ?>;
    var phSigCanvas = document.getElementById('phSigCanvas'), phSigCtx = null, phSigDrawing = false;
    if (phSigCanvas) {
        phSigCanvas.width = phSigCanvas.offsetWidth; phSigCanvas.height = phSigCanvas.offsetHeight;
        phSigCtx = phSigCanvas.getContext('2d'); phSigCtx.lineWidth = 2; phSigCtx.lineCap = 'round'; phSigCtx.strokeStyle = '#1a202c';
        function phSigPos(e){ var r = phSigCanvas.getBoundingClientRect(); var t = e.touches ? e.touches[0] : e; return {x:(t.clientX-r.left)*(phSigCanvas.width/r.width), y:(t.clientY-r.top)*(phSigCanvas.height/r.height)}; }
        phSigCanvas.addEventListener('mousedown', function(e){ phSigDrawing = true; var p = phSigPos(e); phSigCtx.beginPath(); phSigCtx.moveTo(p.x, p.y); });
        phSigCanvas.addEventListener('mousemove', function(e){ if (!phSigDrawing) return; var p = phSigPos(e); phSigCtx.lineTo(p.x, p.y); phSigCtx.stroke(); });
        phSigCanvas.addEventListener('mouseup', function(){ phSigDrawing = false; });
        phSigCanvas.addEventListener('mouseleave', function(){ phSigDrawing = false; });
        phSigCanvas.addEventListener('touchstart', function(e){ e.preventDefault(); phSigDrawing = true; var p = phSigPos(e); phSigCtx.beginPath(); phSigCtx.moveTo(p.x, p.y); }, {passive:false});
        phSigCanvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!phSigDrawing) return; var p = phSigPos(e); phSigCtx.lineTo(p.x, p.y); phSigCtx.stroke(); }, {passive:false});
        phSigCanvas.addEventListener('touchend', function(e){ e.preventDefault(); phSigDrawing = false; }, {passive:false});
    }
    function phClearSig(){ if (phSigCtx) phSigCtx.clearRect(0,0,phSigCanvas.width,phSigCanvas.height); }
    function phIsSigBlank(){ var b = document.createElement('canvas'); b.width = phSigCanvas.width; b.height = phSigCanvas.height; return phSigCanvas.toDataURL() === b.toDataURL(); }
    function phPost(data){
        data.ph_token = phToken;
        return fetch('', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:new URLSearchParams(data).toString() }).then(function(r){ return r.json(); });
    }
    function phApprove(){
        if (phIsSigBlank()) { alert('Please draw your signature first.'); return; }
        document.getElementById('phConfirmOverlay').style.display = 'flex';
    }
    function phSubmitApproval(){
        document.getElementById('phConfirmOverlay').style.display = 'none';
        phPost({ ajax_action:'approve_clearance_position_head', instance_id:phInstanceId, signature_data:phSigCanvas.toDataURL('image/png'), remarks:document.getElementById('phRemarks').value }).then(function(resp){
            if (resp.success) { location.reload(); } else { alert(resp.message || 'Something went wrong.'); }
        });
    }
    function phReject(){
        document.getElementById('phRejectReason').value = '';
        document.getElementById('phRejectOverlay').style.display = 'flex';
    }
    function phSubmitReject(){
        var reason = document.getElementById('phRejectReason').value.trim();
        if (!reason) { alert('Please provide a reason.'); return; }
        document.getElementById('phRejectOverlay').style.display = 'none';
        phPost({ ajax_action:'reject_clearance_position_head', instance_id:phInstanceId, reason:reason }).then(function(resp){
            if (resp.success) { location.reload(); } else { alert(resp.message || 'Something went wrong.'); }
        });
    }
    </script>
    </body>
    </html>
    <?php
    exit;
}

// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    // HR: add a template item for a Dept/Position (one-time setup, reused for every future exit)
    if (isset($_POST['action']) && $_POST['action'] === 'add_template_item') {
        $dept_id = intval($_POST['department_id']);
        $pos_id = intval($_POST['position_id'] ?? 0);
        $title = mysqli_real_escape_string($con, $_POST['item_title']);
        $desc = mysqli_real_escape_string($con, $_POST['description'] ?? '');
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "INSERT INTO hr_exit_handover_templates (department_id, position_id, item_title, description, created_by) VALUES ($dept_id, $pos_id, '$title', '$desc', '$by')");
        $_SESSION['success_message'] = "Handover template item added.";
        header("Location: hr-exit-handover.php?tab=template&department_id=$dept_id&position_id=$pos_id"); exit;
    }

    // HR: assign supervisor/successor and generate the instance checklist from the template
    if (isset($_POST['action']) && $_POST['action'] === 'assign_handover') {
        $exit_id = intval($_POST['exit_id']);
        $nominated_to_id = intval($_POST['nominated_to_id']);
        $by = mysqli_real_escape_string($con, $currentUserName);

        $exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$exit_id LIMIT 1"));
        $empRow = $exitRow ? mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$exitRow['employee_id']} LIMIT 1")) : null;
        if ($exitRow && $empRow) {
            list($dept_id, $pos_id) = resolveDeptPos($con, $empRow);
            mysqli_query($con, "INSERT INTO hr_exit_handover_instance (exit_id, employee_id, nominated_to_id, nominated_by) VALUES ($exit_id, {$exitRow['employee_id']}, $nominated_to_id, '$by') ON DUPLICATE KEY UPDATE nominated_to_id=$nominated_to_id, nominated_by='$by'");

            // Copy template items into the instance (only if not already copied)
            $existingCount = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_handover_items WHERE exit_id=$exit_id"));
            if (intval($existingCount['c']) == 0) {
                $tq = mysqli_query($con, "SELECT * FROM hr_exit_handover_templates WHERE department_id=$dept_id AND (position_id=$pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
                while ($t = mysqli_fetch_assoc($tq)) {
                    $title = mysqli_real_escape_string($con, $t['item_title']);
                    $desc = mysqli_real_escape_string($con, $t['description']);
                    mysqli_query($con, "INSERT INTO hr_exit_handover_items (exit_id, item_title, description, sort_order) VALUES ($exit_id, '$title', '$desc', {$t['sort_order']})");
                }
            }
            mysqli_query($con, "UPDATE hr_exit_requests SET status='handover' WHERE id=$exit_id");
            $_SESSION['success_message'] = "Handover assigned and checklist generated.";
        }
        header("Location: hr-exit-handover.php?exit_id=$exit_id"); exit;
    }

    // Employee (or HR on their behalf): fill in the actual pending items
    if (isset($_POST['action']) && $_POST['action'] === 'fill_item') {
        $item_id = intval($_POST['item_id']);
        $notes = mysqli_real_escape_string($con, $_POST['employee_notes']);
        mysqli_query($con, "UPDATE hr_exit_handover_items SET employee_notes='$notes', status='filled', filled_at=NOW() WHERE id=$item_id");
        header("Location: hr-exit-handover.php?exit_id=" . intval($_POST['exit_id'])); exit;
    }

    // Supervisor/successor: acknowledge receipt of each item
    if (isset($_POST['action']) && $_POST['action'] === 'acknowledge_item') {
        $item_id = intval($_POST['item_id']);
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_handover_items SET status='acknowledged', acknowledged_by='$by', acknowledged_at=NOW() WHERE id=$item_id");
        header("Location: hr-exit-handover.php?exit_id=" . intval($_POST['exit_id'])); exit;
    }

    // --- ASSET TEMPLATE: add section ---
    if (isset($_POST['action']) && $_POST['action'] === 'add_asset_heading') {
        $ah_dept = intval($_POST['department_id'] ?? 0);
        $ah_name = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $ah_cond = isset($_POST['show_condition_field']) ? 1 : 0;
        $by = mysqli_real_escape_string($con, $currentUserName);
        if (!empty($ah_name)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_exit_asset_headings WHERE department_id=$ah_dept"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_exit_asset_headings (department_id, position_id, heading_name, show_condition_field, sort_order, created_by) VALUES ($ah_dept, 0, '$ah_name', $ah_cond, $next_sort, '$by')");
            $_SESSION['success_message'] = "Checklist section added.";
        }
        header("Location: hr-exit-handover.php?tab=assets&asset_mode=manage"); exit;
    }

    // --- ASSET TEMPLATE: edit section ---
    if (isset($_POST['action']) && $_POST['action'] === 'edit_asset_heading') {
        $ah_id = intval($_POST['id']);
        $ah_name = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $ah_cond = isset($_POST['show_condition_field']) ? 1 : 0;
        if ($ah_id > 0 && !empty($ah_name)) {
            mysqli_query($con, "UPDATE hr_exit_asset_headings SET heading_name='$ah_name', show_condition_field=$ah_cond WHERE id=$ah_id");
            $_SESSION['success_message'] = "Checklist section updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- ASSET TEMPLATE: delete section (removes template items only — already-filled instance data is untouched) ---
    if (isset($_POST['action']) && $_POST['action'] === 'delete_asset_heading') {
        $ah_id = intval($_POST['id']);
        mysqli_query($con, "DELETE FROM hr_exit_asset_items WHERE heading_id=$ah_id");
        mysqli_query($con, "DELETE FROM hr_exit_asset_headings WHERE id=$ah_id");
        $_SESSION['success_message'] = "Checklist section deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- ASSET TEMPLATE: add item ---
    if (isset($_POST['action']) && $_POST['action'] === 'add_asset_item') {
        $ai_heading_id = intval($_POST['heading_id']);
        $ai_text = mysqli_real_escape_string($con, trim($_POST['item_text']));
        if ($ai_heading_id > 0 && !empty($ai_text)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_exit_asset_items WHERE heading_id=$ai_heading_id"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_exit_asset_items (heading_id, item_text, sort_order) VALUES ($ai_heading_id, '$ai_text', $next_sort)");
            $_SESSION['success_message'] = "Checklist item added.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- ASSET TEMPLATE: edit item ---
    if (isset($_POST['action']) && $_POST['action'] === 'edit_asset_item') {
        $ai_id = intval($_POST['id']);
        $ai_text = mysqli_real_escape_string($con, trim($_POST['item_text']));
        if ($ai_id > 0 && !empty($ai_text)) {
            mysqli_query($con, "UPDATE hr_exit_asset_items SET item_text='$ai_text' WHERE id=$ai_id");
            $_SESSION['success_message'] = "Checklist item updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- ASSET TEMPLATE: delete item (template only — does NOT touch already-filled instance rows) ---
    if (isset($_POST['action']) && $_POST['action'] === 'delete_asset_item') {
        $ai_id = intval($_POST['id']);
        mysqli_query($con, "DELETE FROM hr_exit_asset_items WHERE id=$ai_id");
        $_SESSION['success_message'] = "Checklist item deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- ASSET INSTANCE: start the checklist for a specific exit (copies template rows) ---
    if (isset($_POST['action']) && $_POST['action'] === 'assign_asset_instance') {
        $aa_exit_id = intval($_POST['exit_id']);
        $aa_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$aa_exit_id LIMIT 1"));
        $aa_empRow = $aa_exitRow ? mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$aa_exitRow['employee_id']} LIMIT 1")) : null;
        if ($aa_exitRow && $aa_empRow) {
            list($aa_dept_id, $aa_pos_id) = resolveDeptPos($con, $aa_empRow);
            mysqli_query($con, "INSERT INTO hr_exit_asset_instance (exit_id, employee_id) VALUES ($aa_exit_id, {$aa_exitRow['employee_id']}) ON DUPLICATE KEY UPDATE exit_id=exit_id");
            $aa_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_asset_instance WHERE exit_id=$aa_exit_id LIMIT 1"));
            $aa_instance_id = intval($aa_instance['id']);

            $aa_existing = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_asset_run_items WHERE instance_id=$aa_instance_id"));
            if (intval($aa_existing['c']) == 0) {
                $aa_hq = mysqli_query($con, "SELECT * FROM hr_exit_asset_headings WHERE (department_id=$aa_dept_id OR department_id=0) AND (position_id=$aa_pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
                while ($aa_h = mysqli_fetch_assoc($aa_hq)) {
                    $aa_hname_e = mysqli_real_escape_string($con, $aa_h['heading_name']);
                    $aa_iq = mysqli_query($con, "SELECT * FROM hr_exit_asset_items WHERE heading_id=" . intval($aa_h['id']) . " ORDER BY sort_order ASC, id ASC");
                    while ($aa_i = mysqli_fetch_assoc($aa_iq)) {
                        $aa_itext_e = mysqli_real_escape_string($con, $aa_i['item_text']);
                        mysqli_query($con, "INSERT INTO hr_exit_asset_run_items (instance_id, heading_id, heading_name, heading_sort, show_condition_field, item_id, item_text, item_sort) VALUES ($aa_instance_id, {$aa_h['id']}, '$aa_hname_e', {$aa_h['sort_order']}, {$aa_h['show_condition_field']}, {$aa_i['id']}, '$aa_itext_e', {$aa_i['sort_order']})");
                    }
                }
            }
            // Advances the exit into the Handover stage (if not already past it) so the employee's
            // tracker link unlocks Phase 2 — independent of the separate "Handover Checklist" tab.
            mysqli_query($con, "UPDATE hr_exit_requests SET status='handover' WHERE id=$aa_exit_id AND status='approved'");
            $_SESSION['success_message'] = "Access given — the employee can now fill this in via their exit link.";
        }
        header("Location: hr-exit-handover.php?tab=assets&exit_id=$aa_exit_id"); exit;
    }

    // --- ASSET INSTANCE: HR declines access — no assets applicable, skips this exit entirely ---
    if (isset($_POST['action']) && $_POST['action'] === 'decline_asset_handover') {
        $da_exit_id = intval($_POST['exit_id']);
        $da_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$da_exit_id LIMIT 1"));
        if ($da_exitRow) {
            mysqli_query($con, "INSERT INTO hr_exit_asset_instance (exit_id, employee_id, status) VALUES ($da_exit_id, {$da_exitRow['employee_id']}, 'not_applicable') ON DUPLICATE KEY UPDATE status='not_applicable'");
            mysqli_query($con, "UPDATE hr_exit_requests SET status='handover' WHERE id=$da_exit_id AND status='approved'");
            $_SESSION['success_message'] = "Asset Handover marked as not applicable for this employee.";
        }
        header("Location: hr-exit-handover.php?tab=assets&exit_id=$da_exit_id"); exit;
    }

    // --- ASSET INSTANCE: HR reverts a Decline — removes the "not applicable" marker so
    // Give Access / Decline can be chosen again. Only allowed while still declined, so this
    // can never be used to wipe out a real in-progress/completed checklist by mistake. ---
    if (isset($_POST['action']) && $_POST['action'] === 'revert_asset_decline') {
        $rv_exit_id = intval($_POST['exit_id']);
        mysqli_query($con, "DELETE FROM hr_exit_asset_instance WHERE exit_id=$rv_exit_id AND status='not_applicable'");
        $_SESSION['success_message'] = "Decline reverted — you can choose Give Access or Decline again.";
        header("Location: hr-exit-handover.php?tab=assets&exit_id=$rv_exit_id"); exit;
    }

    // --- CLEARANCE TEMPLATE: add section ---
    if (isset($_POST['action']) && $_POST['action'] === 'add_clearance_heading') {
        $ch_template_id = intval($_POST['template_id']);
        $ch_name = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        if ($ch_template_id > 0 && !empty($ch_name)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_exit_clearance_headings WHERE template_id=$ch_template_id"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_exit_clearance_headings (template_id, heading_name, sort_order) VALUES ($ch_template_id, '$ch_name', $next_sort)");
            $_SESSION['success_message'] = "Checklist section added.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: edit section ---
    if (isset($_POST['action']) && $_POST['action'] === 'edit_clearance_heading') {
        $ch_id = intval($_POST['id']);
        $ch_name = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        if ($ch_id > 0 && !empty($ch_name)) {
            mysqli_query($con, "UPDATE hr_exit_clearance_headings SET heading_name='$ch_name' WHERE id=$ch_id");
            $_SESSION['success_message'] = "Checklist section updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: delete section ---
    if (isset($_POST['action']) && $_POST['action'] === 'delete_clearance_heading') {
        $ch_id = intval($_POST['id']);
        mysqli_query($con, "DELETE FROM hr_exit_clearance_checklist_items WHERE heading_id=$ch_id");
        mysqli_query($con, "DELETE FROM hr_exit_clearance_headings WHERE id=$ch_id");
        $_SESSION['success_message'] = "Checklist section deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: add item ---
    if (isset($_POST['action']) && $_POST['action'] === 'add_clearance_item') {
        $ci_heading_id = intval($_POST['heading_id']);
        $ci_text = mysqli_real_escape_string($con, trim($_POST['item_text']));
        if ($ci_heading_id > 0 && !empty($ci_text)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_exit_clearance_checklist_items WHERE heading_id=$ci_heading_id"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_exit_clearance_checklist_items (heading_id, item_text, sort_order) VALUES ($ci_heading_id, '$ci_text', $next_sort)");
            $_SESSION['success_message'] = "Checklist item added.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: edit item ---
    if (isset($_POST['action']) && $_POST['action'] === 'edit_clearance_item') {
        $ci_id = intval($_POST['id']);
        $ci_text = mysqli_real_escape_string($con, trim($_POST['item_text']));
        if ($ci_id > 0 && !empty($ci_text)) {
            mysqli_query($con, "UPDATE hr_exit_clearance_checklist_items SET item_text='$ci_text' WHERE id=$ci_id");
            $_SESSION['success_message'] = "Checklist item updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: delete item ---
    if (isset($_POST['action']) && $_POST['action'] === 'delete_clearance_item') {
        $ci_id = intval($_POST['id']);
        mysqli_query($con, "DELETE FROM hr_exit_clearance_checklist_items WHERE id=$ci_id");
        $_SESSION['success_message'] = "Checklist item deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE TEMPLATE: import sections/items from CSV (same format produced by Export) ---
    if (isset($_POST['action']) && $_POST['action'] === 'import_clearance_sections') {
        $ic_template_id = intval($_POST['template_id']);
        $ic_redirect = "?tab=clearance2&clearance_mode=manage&clr_department_id=" . intval($_POST['clr_department_id'] ?? 0) . "&clr_position_id=" . intval($_POST['clr_position_id'] ?? 0);

        if ($ic_template_id > 0 && isset($_FILES['import_file']) && $_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
            $ic_fh = fopen($_FILES['import_file']['tmp_name'], 'r');
            $ic_sections = []; // ordered: heading name => [item texts]
            if ($ic_fh) {
                $ic_row_num = 0;
                while (($ic_row = fgetcsv($ic_fh)) !== false) {
                    $ic_row_num++;
                    if ($ic_row_num === 1 && isset($ic_row[0]) && strtolower(trim($ic_row[0])) === 'section') continue; // header row
                    $ic_sname = isset($ic_row[0]) ? trim($ic_row[0]) : '';
                    $ic_itext = isset($ic_row[1]) ? trim($ic_row[1]) : '';
                    if ($ic_sname === '') continue;
                    if (!isset($ic_sections[$ic_sname])) $ic_sections[$ic_sname] = [];
                    if ($ic_itext !== '') $ic_sections[$ic_sname][] = $ic_itext;
                }
                fclose($ic_fh);
            }

            if (!empty($ic_sections)) {
                $ic_old_hq = mysqli_query($con, "SELECT id FROM hr_exit_clearance_headings WHERE template_id=$ic_template_id");
                if ($ic_old_hq) {
                    while ($ic_old_h = mysqli_fetch_assoc($ic_old_hq)) {
                        mysqli_query($con, "DELETE FROM hr_exit_clearance_checklist_items WHERE heading_id=" . intval($ic_old_h['id']));
                    }
                }
                mysqli_query($con, "DELETE FROM hr_exit_clearance_headings WHERE template_id=$ic_template_id");

                $ic_hsort = 0;
                foreach ($ic_sections as $ic_sname => $ic_items) {
                    $ic_sname_e = mysqli_real_escape_string($con, $ic_sname);
                    mysqli_query($con, "INSERT INTO hr_exit_clearance_headings (template_id, heading_name, sort_order) VALUES ($ic_template_id, '$ic_sname_e', $ic_hsort)");
                    $ic_heading_id = mysqli_insert_id($con);
                    $ic_isort = 0;
                    foreach ($ic_items as $ic_itext) {
                        $ic_itext_e = mysqli_real_escape_string($con, $ic_itext);
                        mysqli_query($con, "INSERT INTO hr_exit_clearance_checklist_items (heading_id, item_text, sort_order) VALUES ($ic_heading_id, '$ic_itext_e', $ic_isort)");
                        $ic_isort++;
                    }
                    $ic_hsort++;
                }
                $_SESSION['success_message'] = "Imported " . count($ic_sections) . " section(s) successfully, replacing the previous sections.";
            } else {
                $_SESSION['error_message'] = "That file had no valid sections to import. Use the Export button to download a file in the expected format.";
            }
        } else {
            $_SESSION['error_message'] = "Please choose a file to import.";
        }
        header("Location: " . $ic_redirect); exit;
    }

    // --- CLEARANCE TEMPLATE: save signatory title + declaration text ---
    if (isset($_POST['action']) && $_POST['action'] === 'update_clearance_template_meta') {
        $ct_id = intval($_POST['template_id']);
        $ct_title = mysqli_real_escape_string($con, trim($_POST['signatory_title']) ?: 'Position Head');
        $ct_decl = mysqli_real_escape_string($con, trim($_POST['declaration_text'] ?? ''));
        $ct_head_id = intval($_POST['position_head_employee_id'] ?? 0);
        $ct_head_sql = $ct_head_id > 0 ? $ct_head_id : 'NULL';
        if ($ct_id > 0) {
            mysqli_query($con, "UPDATE hr_exit_clearance_templates SET signatory_title='$ct_title', declaration_text='$ct_decl', position_head_employee_id=$ct_head_sql WHERE id=$ct_id");
            $_SESSION['success_message'] = "Template details saved.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // --- CLEARANCE INSTANCE: HR gives access — auto-matches the template by the employee's dept+position ---
    if (isset($_POST['action']) && $_POST['action'] === 'assign_clearance_instance') {
        $ac_exit_id = intval($_POST['exit_id']);
        $ac_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$ac_exit_id LIMIT 1"));
        $ac_empRow = $ac_exitRow ? mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$ac_exitRow['employee_id']} LIMIT 1")) : null;
        if ($ac_exitRow && $ac_empRow) {
            list($ac_dept_id, $ac_pos_id) = resolveDeptPos($con, $ac_empRow);
            $ac_template = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE department_id=$ac_dept_id AND position_id=$ac_pos_id ORDER BY id ASC LIMIT 1"));
            if (!$ac_template) {
                $_SESSION['error_message'] = "No clearance template configured for this employee's Department/Position yet. Set one up under Manage Clearance Template first.";
                header("Location: hr-exit-handover.php?tab=clearance2&exit_id=$ac_exit_id"); exit;
            }
            if (empty($ac_template['position_head_employee_id'])) {
                $_SESSION['error_message'] = "This clearance template doesn't have a Position Head assigned yet. Assign one under Manage Clearance Template before giving access.";
                header("Location: hr-exit-handover.php?tab=clearance2&exit_id=$ac_exit_id"); exit;
            }
            $ac_template_id = intval($ac_template['id']);
            $ac_head_id = intval($ac_template['position_head_employee_id']);
            // Generated fresh here, but ON DUPLICATE KEY re-uses whatever token already exists
            // (via COALESCE below) so re-running Give Access never invalidates a link already sent out.
            $ac_new_token = bin2hex(random_bytes(24));
            mysqli_query($con, "INSERT INTO hr_exit_clearance_instance (exit_id, employee_id, template_id, position_head_employee_id, position_head_token) VALUES ($ac_exit_id, {$ac_exitRow['employee_id']}, $ac_template_id, $ac_head_id, '$ac_new_token') ON DUPLICATE KEY UPDATE template_id=$ac_template_id, position_head_employee_id=$ac_head_id, status='in_progress', position_head_token=COALESCE(position_head_token, '$ac_new_token')");
            $ac_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_exit_clearance_instance WHERE exit_id=$ac_exit_id LIMIT 1"));
            $ac_instance_id = intval($ac_instance['id']);

            $ac_existing = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_clearance_run_items WHERE instance_id=$ac_instance_id"));
            if (intval($ac_existing['c']) == 0) {
                $ac_hq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_headings WHERE template_id=$ac_template_id ORDER BY sort_order ASC, id ASC");
                while ($ac_h = mysqli_fetch_assoc($ac_hq)) {
                    $ac_hname_e = mysqli_real_escape_string($con, $ac_h['heading_name']);
                    $ac_iq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_checklist_items WHERE heading_id=" . intval($ac_h['id']) . " ORDER BY sort_order ASC, id ASC");
                    while ($ac_i = mysqli_fetch_assoc($ac_iq)) {
                        $ac_itext_e = mysqli_real_escape_string($con, $ac_i['item_text']);
                        mysqli_query($con, "INSERT INTO hr_exit_clearance_run_items (instance_id, heading_id, heading_name, heading_sort, item_id, item_text, item_sort) VALUES ($ac_instance_id, {$ac_h['id']}, '$ac_hname_e', {$ac_h['sort_order']}, {$ac_i['id']}, '$ac_itext_e', {$ac_i['sort_order']})");
                    }
                }
            }
            mysqli_query($con, "UPDATE hr_exit_requests SET status='handover' WHERE id=$ac_exit_id AND status='approved'");
            $by_e = mysqli_real_escape_string($con, $currentUserName);
            mysqli_query($con, "INSERT INTO hr_exit_clearance_history (exit_id, action_name, action_by) VALUES ($ac_exit_id, 'Link Generated for Position Head', '$by_e')");
            $_SESSION['success_message'] = "Link generated for the Position Head. You can now notify them.";
            header("Location: hr-exit-handover.php?tab=clearance2&exit_id=$ac_exit_id"); exit;
        }
        header("Location: hr-exit-handover.php?tab=clearance2&exit_id=$ac_exit_id"); exit;
    }

    // --- CLEARANCE INSTANCE: Notify Position Head ---
    if (isset($_POST['action']) && $_POST['action'] === 'notify_position_head') {
        $n_exit_id = intval($_POST['exit_id']);
        $n_instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT ci.*, e.email, e.personal_email, e.phone, e.alt_phone FROM hr_exit_clearance_instance ci JOIN hr_employees e ON ci.position_head_employee_id = e.id WHERE ci.exit_id=$n_exit_id LIMIT 1"));
        if ($n_instance && !empty($n_instance['position_head_token'])) {
            $to_email = !empty($n_instance['email']) ? $n_instance['email'] : $n_instance['personal_email'];
            if ($to_email) {
                $subject = trim($_POST['email_subject']);
                $body = trim($_POST['email_body']);
                $result = sendSmtpMail([$to_email], $subject, $body, $currentUserName);
                if ($result['success']) {
                    mysqli_query($con, "UPDATE hr_exit_clearance_instance SET position_head_notified_at=NOW() WHERE exit_id=$n_exit_id");
                    $by_e = mysqli_real_escape_string($con, $currentUserName);
                    mysqli_query($con, "INSERT INTO hr_exit_clearance_history (exit_id, action_name, action_by) VALUES ($n_exit_id, 'Position Head Notified via Email', '$by_e')");
                    $_SESSION['success_message'] = "Position Head notified successfully.";
                } else {
                    $_SESSION['error_message'] = "Failed to send notification: " . $result['message'];
                }
            } else {
                $_SESSION['error_message'] = "Position Head has no email address on file.";
            }
        } else {
            $_SESSION['error_message'] = "Clearance instance or token not found.";
        }
        header("Location: hr-exit-handover.php?tab=clearance2&exit_id=$n_exit_id"); exit;
    }

    // --- CLEARANCE INSTANCE: HR declines — not applicable, skips this exit entirely ---
    if (isset($_POST['action']) && $_POST['action'] === 'decline_clearance') {
        $dc_exit_id = intval($_POST['exit_id']);
        $dc_exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$dc_exit_id LIMIT 1"));
        if ($dc_exitRow) {
            mysqli_query($con, "INSERT INTO hr_exit_clearance_instance (exit_id, employee_id, status) VALUES ($dc_exit_id, {$dc_exitRow['employee_id']}, 'not_applicable') ON DUPLICATE KEY UPDATE status='not_applicable'");
            mysqli_query($con, "UPDATE hr_exit_requests SET status='handover' WHERE id=$dc_exit_id AND status='approved'");
            $_SESSION['success_message'] = "Department-Position Clearance marked as not applicable for this employee.";
        }
        header("Location: hr-exit-handover.php?tab=clearance2"); exit;
    }

    // --- CLEARANCE INSTANCE: HR reverts a Decline ---
    if (isset($_POST['action']) && $_POST['action'] === 'revert_clearance_decline') {
        $rc_exit_id = intval($_POST['exit_id']);
        mysqli_query($con, "DELETE FROM hr_exit_clearance_instance WHERE exit_id=$rc_exit_id AND status='not_applicable'");
        $_SESSION['success_message'] = "Decline reverted — you can choose Give Access or Decline again.";
        header("Location: hr-exit-handover.php?tab=clearance2"); exit;
    }

    // --- CLEARANCE TEMPLATE: HR deletes a configured template (and its sections/items) ---
    if (isset($_POST['action']) && $_POST['action'] === 'delete_clearance_template') {
        $dtpl_id = intval($_POST['template_id']);
        $dtpl_hids = [];
        $dtpl_hq = mysqli_query($con, "SELECT id FROM hr_exit_clearance_headings WHERE template_id=$dtpl_id");
        if ($dtpl_hq) while ($dh = mysqli_fetch_assoc($dtpl_hq)) $dtpl_hids[] = $dh['id'];
        if (!empty($dtpl_hids)) {
            mysqli_query($con, "DELETE FROM hr_exit_clearance_checklist_items WHERE heading_id IN (" . implode(',', $dtpl_hids) . ")");
        }
        mysqli_query($con, "DELETE FROM hr_exit_clearance_headings WHERE template_id=$dtpl_id");
        mysqli_query($con, "DELETE FROM hr_exit_clearance_templates WHERE id=$dtpl_id");
        $_SESSION['success_message'] = "Clearance template deleted. Already-assigned employee checklists are not affected.";
        header("Location: hr-exit-handover.php?tab=clearance2&clearance_mode=manage"); exit;
    }
}

// =========================================================================
// ASSET HANDOVER — AJAX ACTIONS
// =========================================================================
if (isset($_POST['ajax_action'])) {
    header('Content-Type: application/json');

    if ($_POST['ajax_action'] === 'toggle_asset_item') {
        $ri_id = intval($_POST['run_item_id']);
        $checked = intval($_POST['checked']) == 1 ? 1 : 0;
        $by = mysqli_real_escape_string($con, $currentUserName);
        if ($checked) {
            mysqli_query($con, "UPDATE hr_exit_asset_run_items SET is_checked=1, checked_by='$by', checked_at=NOW() WHERE id=$ri_id");
        } else {
            mysqli_query($con, "UPDATE hr_exit_asset_run_items SET is_checked=0, checked_by=NULL, checked_at=NULL WHERE id=$ri_id");
        }
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'save_asset_item_detail') {
        $ri_id = intval($_POST['run_item_id']);
        $cond = mysqli_real_escape_string($con, trim($_POST['condition_text'] ?? ''));
        $rem = mysqli_real_escape_string($con, trim($_POST['remarks'] ?? ''));
        mysqli_query($con, "UPDATE hr_exit_asset_run_items SET condition_text='$cond', remarks='$rem' WHERE id=$ri_id");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'add_asset_custom_row') {
        $inst_id = intval($_POST['instance_id']);
        $head_id = intval($_POST['heading_id']);
        $item_text = mysqli_real_escape_string($con, trim($_POST['item_text'] ?? ''));
        if (empty($item_text) || $inst_id <= 0) { echo json_encode(['success' => false, 'message' => 'Item text required']); exit; }
        $hrow = mysqli_fetch_assoc(mysqli_query($con, "SELECT heading_name, sort_order, show_condition_field FROM hr_exit_asset_headings WHERE id=$head_id"));
        if (!$hrow) { echo json_encode(['success' => false, 'message' => 'Section not found']); exit; }
        $hname_e = mysqli_real_escape_string($con, $hrow['heading_name']);
        $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(item_sort) as m FROM hr_exit_asset_run_items WHERE instance_id=$inst_id AND heading_id=$head_id"));
        $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
        mysqli_query($con, "INSERT INTO hr_exit_asset_run_items (instance_id, heading_id, heading_name, heading_sort, show_condition_field, item_text, item_sort, is_custom) VALUES ($inst_id, $head_id, '$hname_e', {$hrow['sort_order']}, {$hrow['show_condition_field']}, '$item_text', $next_sort)");
        echo json_encode(['success' => true, 'run_item_id' => mysqli_insert_id($con)]); exit;
    }

    if ($_POST['ajax_action'] === 'remove_asset_custom_row') {
        $ri_id = intval($_POST['run_item_id']);
        mysqli_query($con, "DELETE FROM hr_exit_asset_run_items WHERE id=$ri_id AND is_custom=1");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'save_asset_signature') {
        $inst_id = intval($_POST['instance_id']);
        $sig = trim($_POST['signature_data'] ?? '');
        if (empty($sig) || $inst_id <= 0) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $sig_e = mysqli_real_escape_string($con, $sig);
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_asset_instance SET signature_data='$sig_e', signed_by='$by', signed_at=NOW(), status='pending_approval', rejection_reason=NULL WHERE id=$inst_id");
        echo json_encode(['success' => true]); exit;
    }

    // --- ASSET INSTANCE: HR approves the signed checklist — files it in the employee's documents ---
    if ($_POST['ajax_action'] === 'approve_asset_handover') {
        $inst_id = intval($_POST['instance_id']);
        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_asset_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Checklist not found']); exit; }

        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_asset_instance SET status='completed', reviewed_by='$by', reviewed_at=NOW() WHERE id=$inst_id");

        $exit_id = intval($inst['exit_id']);
        mysqli_query($con, "UPDATE hr_exit_requests SET status='clearance' WHERE id=$exit_id AND status='handover'");

        $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT employee_id FROM hr_employees WHERE id=" . intval($inst['employee_id']) . " LIMIT 1"));
        if ($emp && !empty($emp['employee_id'])) {
            $doc_url = 'hr-exit-handover.php?view_asset_doc=' . $exit_id;
            $eid_e   = mysqli_real_escape_string($con, $emp['employee_id']);
            $dt_e    = 'Employee Asset Return Checklist';
            $fn_e    = mysqli_real_escape_string($con, $dt_e . '.pdf');
            $fp_e    = mysqli_real_escape_string($con, $doc_url);
            $exists  = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employee_documents WHERE employee_id='$eid_e' AND document_type='$dt_e' LIMIT 1"));
            if ($exists) {
                mysqli_query($con, "UPDATE hr_employee_documents SET filename='$fn_e', filepath='$fp_e' WHERE id=" . intval($exists['id']));
            } else {
                mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath) VALUES ('$eid_e', '$dt_e', '$fn_e', '$fp_e')");
            }
        }

        echo json_encode(['success' => true]); exit;
    }

    // --- ASSET INSTANCE: HR rejects the signed checklist — reverts signature, raises a ticket to the employee ---
    if ($_POST['ajax_action'] === 'reject_asset_handover') {
        $inst_id = intval($_POST['instance_id']);
        $reason  = trim($_POST['reason'] ?? '');
        if (empty($reason)) { echo json_encode(['success' => false, 'message' => 'Please provide a rejection reason.']); exit; }

        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_asset_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Checklist not found']); exit; }

        $by = mysqli_real_escape_string($con, $currentUserName);
        $reason_e = mysqli_real_escape_string($con, $reason);
        mysqli_query($con, "UPDATE hr_exit_asset_instance SET status='rejected', rejection_reason='$reason_e', reviewed_by='$by', reviewed_at=NOW(), signature_data=NULL WHERE id=$inst_id");

        $empRow_r = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($inst['employee_id']) . " LIMIT 1"));
        $exitRow_r = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=" . intval($inst['exit_id']) . " LIMIT 1"));
        if ($empRow_r && $exitRow_r) {
            raiseAssetHandoverRejectedTicket($con, $currentUserName, $empRow_r, $exitRow_r, $reason);
        }

        echo json_encode(['success' => true]); exit;
    }

    // --- CLEARANCE: HR-side fill-in (mirrors Asset Handover's toggle/remarks — "both can do") ---
    if ($_POST['ajax_action'] === 'set_clearance_response') {
        $ri_id = intval($_POST['run_item_id']);
        $resp = $_POST['response'] ?? '';
        if (!in_array($resp, ['yes','no','na','unanswered'], true)) { echo json_encode(['success' => false, 'message' => 'Invalid response']); exit; }
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_clearance_run_items SET response='$resp', checked_by='$by', checked_at=NOW() WHERE id=$ri_id");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'save_clearance_item_remarks') {
        $ri_id = intval($_POST['run_item_id']);
        $rem = mysqli_real_escape_string($con, trim($_POST['remarks'] ?? ''));
        mysqli_query($con, "UPDATE hr_exit_clearance_run_items SET remarks='$rem' WHERE id=$ri_id");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'save_clearance_employee_signature') {
        $inst_id = intval($_POST['instance_id']);
        $sig = trim($_POST['signature_data'] ?? '');
        if (empty($sig) || $inst_id <= 0) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $sig_e = mysqli_real_escape_string($con, $sig);
        $by = mysqli_real_escape_string($con, $currentUserName);
        // Employee is the second to sign
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET employee_signature_data='$sig_e', employee_signed_by='$by', employee_signed_at=NOW(), status='pending_hr_approval', hr_rejection_reason=NULL WHERE id=$inst_id");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'get_clearance_history') {
        $ex_id = intval($_POST['exit_id']);
        $hq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_history WHERE exit_id=$ex_id ORDER BY created_at DESC");
        $h_html = '';
        if (mysqli_num_rows($hq) > 0) {
            $h_html .= '<ul style="list-style:none;padding:0;margin:0;">';
            while ($h = mysqli_fetch_assoc($hq)) {
                $h_html .= '<li style="margin-bottom:12px;border-left:2px solid #2563eb;padding-left:12px;">';
                $h_html .= '<div style="font-size:11px;color:#94a3b8;font-weight:700;">' . date('d M Y, h:i A', strtotime($h['created_at'])) . '</div>';
                $h_html .= '<div style="font-size:13px;color:var(--navy);font-weight:600;margin-top:2px;">' . htmlspecialchars($h['action_name']) . '</div>';
                $h_html .= '<div style="font-size:11.5px;color:#64748b;margin-top:2px;"><i class="fas fa-user-circle mr-1"></i> By: ' . htmlspecialchars($h['action_by'] ?: 'System') . '</div>';
                $h_html .= '</li>';
            }
            $h_html .= '</ul>';
        } else {
            $h_html = '<p style="color:#64748b;text-align:center;margin:0;">No history recorded yet.</p>';
        }
        echo json_encode(['success' => true, 'html' => $h_html]); exit;
    }

    // --- CLEARANCE: Position Head signs off and approves — moves to Employee for signature ---
    if ($_POST['ajax_action'] === 'approve_clearance_position_head') {
        $inst_id = intval($_POST['instance_id']);
        $sig = trim($_POST['signature_data'] ?? '');
        $remarks = trim($_POST['remarks'] ?? '');
        if (empty($sig)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $sig_e = mysqli_real_escape_string($con, $sig);
        $rem_e = mysqli_real_escape_string($con, $remarks);
        $by = mysqli_real_escape_string($con, $currentUserName);
        // Position Head is the FIRST to sign
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET position_head_signature_data='$sig_e', position_head_signed_by='$by', position_head_signed_at=NOW(), position_head_remarks='$rem_e', status='pending_employee_signature' WHERE id=$inst_id");
        echo json_encode(['success' => true]); exit;
    }

    // --- CLEARANCE: Position Head rejects — reverts the employee's signature, goes back to them ---
    if ($_POST['ajax_action'] === 'reject_clearance_position_head') {
        $inst_id = intval($_POST['instance_id']);
        $reason = trim($_POST['reason'] ?? '');
        if (empty($reason)) { echo json_encode(['success' => false, 'message' => 'Please provide a rejection reason.']); exit; }
        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $reason_e = mysqli_real_escape_string($con, $reason);
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET status='rejected_by_position_head', position_head_rejection_reason='$reason_e', employee_signature_data=NULL, employee_signed_by=NULL, employee_signed_at=NULL WHERE id=$inst_id");

        $empRow_c = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($inst['employee_id']) . " LIMIT 1"));
        $exitRow_c = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=" . intval($inst['exit_id']) . " LIMIT 1"));
        if ($empRow_c && $exitRow_c) {
            raiseClearanceRejectedTicket($con, $currentUserName, $empRow_c, $exitRow_c, $reason);
        }
        echo json_encode(['success' => true]); exit;
    }

    // --- CLEARANCE: HR gives the final approval — files the document into hr_employee_documents ---
    if ($_POST['ajax_action'] === 'approve_clearance_hr') {
        $inst_id = intval($_POST['instance_id']);
        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }

        if (empty($inst['position_head_signature_data']) || empty($inst['employee_signature_data'])) {
            echo json_encode(['success' => false, 'message' => 'Both Position Head and Employee signatures are required before final approval.']); exit;
        }

        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET status='completed', hr_reviewed_by='$by', hr_reviewed_at=NOW() WHERE id=$inst_id");
        $exit_id_e = intval($inst['exit_id']);
        mysqli_query($con, "INSERT INTO hr_exit_clearance_history (exit_id, action_name, action_by) VALUES ($exit_id_e, 'Final HR Approval Granted', '$by')");

        $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT employee_id FROM hr_employees WHERE id=" . intval($inst['employee_id']) . " LIMIT 1"));
        if ($emp && !empty($emp['employee_id'])) {
            $doc_url = 'hr-exit-handover.php?view_clearance_doc=' . intval($inst['exit_id']);
            $eid_e   = mysqli_real_escape_string($con, $emp['employee_id']);
            $dt_e    = 'Department-Position Clearance';
            $fn_e    = mysqli_real_escape_string($con, $dt_e . '.pdf');
            $fp_e    = mysqli_real_escape_string($con, $doc_url);
            $exists  = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employee_documents WHERE employee_id='$eid_e' AND document_type='$dt_e' LIMIT 1"));
            if ($exists) {
                mysqli_query($con, "UPDATE hr_employee_documents SET filename='$fn_e', filepath='$fp_e' WHERE id=" . intval($exists['id']));
            } else {
                mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath) VALUES ('$eid_e', '$dt_e', '$fn_e', '$fp_e')");
            }
        }
        
        // Advance candidate to Interview & Settlement phase
        mysqli_query($con, "UPDATE hr_exit_requests SET status='interview_settlement' WHERE id=$exit_id_e AND status='clearance'");
        
        echo json_encode(['success' => true]); exit;
    }

    // --- CLEARANCE: HR rejects at the final stage — full reset, clears both signatures, re-passes Position Head ---
    if ($_POST['ajax_action'] === 'reject_clearance_hr') {
        $inst_id = intval($_POST['instance_id']);
        $reason = trim($_POST['reason'] ?? '');
        if (empty($reason)) { echo json_encode(['success' => false, 'message' => 'Please provide a rejection reason.']); exit; }
        $inst = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=$inst_id LIMIT 1"));
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $reason_e = mysqli_real_escape_string($con, $reason);
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET status='in_progress', hr_rejection_reason='$reason_e', hr_reviewed_by='$by', hr_reviewed_at=NOW(), employee_signature_data=NULL, employee_signed_by=NULL, employee_signed_at=NULL, position_head_signature_data=NULL, position_head_signed_by=NULL, position_head_signed_at=NULL, position_head_remarks=NULL WHERE id=$inst_id");

        $empRow_c = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($inst['employee_id']) . " LIMIT 1"));
        $exitRow_c = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=" . intval($inst['exit_id']) . " LIMIT 1"));
        if ($empRow_c && $exitRow_c) {
            raiseClearanceRejectedTicket($con, $currentUserName, $empRow_c, $exitRow_c, $reason);
        }
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'notify_ph_email_ajax') {
        $n_exit_id = intval($_POST['exit_id']);
        $to_email = trim($_POST['email_to']);
        if ($to_email) {
            $subject = trim($_POST['email_subject']);
            $body = trim($_POST['email_body']);
            try {
                $result = sendSmtpMail([$to_email], $subject, $body, $currentUserName);
            } catch (Throwable $e) {
                $result = ['success' => false, 'message' => $e->getMessage()];
            }
            if (!empty($result['success'])) {
                mysqli_query($con, "UPDATE hr_exit_clearance_instance SET position_head_notified_at=NOW() WHERE exit_id=$n_exit_id");
                $by_e = mysqli_real_escape_string($con, $currentUserName);
                mysqli_query($con, "INSERT INTO hr_exit_clearance_history (exit_id, action_name, action_by) VALUES ($n_exit_id, 'Position Head Notified via Email', '$by_e')");
                echo json_encode(['status' => 'success']);
            } else {
                echo json_encode(['status' => 'error', 'message' => 'Failed to send: ' . $result['message']]);
            }
        } else {
            echo json_encode(['status' => 'error', 'message' => 'No email address provided.']);
        }
        exit;
    }

    echo json_encode(['success' => false, 'message' => 'Unknown action']); exit;
}

// =========================================================================
// PAGE DATA
// =========================================================================
$activeTab = $_GET['tab'] ?? 'assets';
$exit_id = intval($_GET['exit_id'] ?? 0);

$exitRow = null; $empRow = null; $instance = null; $items = [];
if ($exit_id > 0) {
    $exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$exit_id LIMIT 1"));
    if ($exitRow) {
        $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$exitRow['employee_id']} LIMIT 1"));
        $instance = mysqli_fetch_assoc(mysqli_query($con, "SELECT hi.*, e.name as nominated_name FROM hr_exit_handover_instance hi LEFT JOIN hr_employees e ON e.id=hi.nominated_to_id WHERE hi.exit_id=$exit_id LIMIT 1"));
        $iq = mysqli_query($con, "SELECT * FROM hr_exit_handover_items WHERE exit_id=$exit_id ORDER BY sort_order ASC, id ASC");
        while ($row = mysqli_fetch_assoc($iq)) $items[] = $row;
    }
}
$total_items = count($items);
$ack_items = count(array_filter($items, fn($i) => $i['status'] === 'acknowledged'));
$pct = $total_items > 0 ? round(($ack_items / $total_items) * 100) : 0;

$employees = [];
$eq = mysqli_query($con, "SELECT id, name, department, position FROM hr_employees ORDER BY name ASC");
if ($eq) while ($row = mysqli_fetch_assoc($eq)) $employees[] = $row;

$departments = [];
$dq = mysqli_query($con, "SELECT id, name FROM hr_departments ORDER BY name ASC");
if ($dq) while ($row = mysqli_fetch_assoc($dq)) $departments[] = $row;

$tpl_dept_id = intval($_GET['department_id'] ?? 0);
$tpl_pos_id = intval($_GET['position_id'] ?? 0);
$templateItems = [];
if ($tpl_dept_id > 0) {
    $tq = mysqli_query($con, "SELECT * FROM hr_exit_handover_templates WHERE department_id=$tpl_dept_id AND (position_id=$tpl_pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
    while ($row = mysqli_fetch_assoc($tq)) $templateItems[] = $row;
}

// Pending exits awaiting handover assignment
$pendingExits = [];
$peq = mysqli_query($con, "SELECT r.*, e.name as employee_name FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.status='approved' ORDER BY r.id DESC");
if ($peq) while ($row = mysqli_fetch_assoc($peq)) $pendingExits[] = $row;

// =========================================================================
// ASSET HANDOVER — PAGE DATA
// =========================================================================
$asset_mode = $_GET['asset_mode'] ?? '';
$asset_dept_id = 0; // Asset Handover Checklist applies to all departments — no per-department scoping

// Unlike $pendingExits above (only 'approved'), this list stays visible through the whole
// exit lifecycle so HR can always find an exit again — e.g. to revert a Decline — instead
// of it disappearing once Give Access / Decline moves the exit past 'approved'.
$assetPendingExits = [];
$apeq = mysqli_query($con, "
    SELECT r.*, e.name as employee_name, ai.status as asset_status
    FROM hr_exit_requests r
    LEFT JOIN hr_employees e ON e.id = r.employee_id
    LEFT JOIN hr_exit_asset_instance ai ON ai.exit_id = r.id
    WHERE r.status NOT IN ('link_sent','initiated','retained','rejected')
    ORDER BY r.id DESC
");
if ($apeq) while ($row = mysqli_fetch_assoc($apeq)) $assetPendingExits[] = $row;

$assetHeadings = [];
if ($activeTab === 'assets' && $asset_mode === 'manage') {
    $ahq = mysqli_query($con, "SELECT * FROM hr_exit_asset_headings WHERE department_id=$asset_dept_id ORDER BY sort_order ASC, id ASC");
    while ($ah = mysqli_fetch_assoc($ahq)) {
        $ah['items'] = [];
        $aiq = mysqli_query($con, "SELECT * FROM hr_exit_asset_items WHERE heading_id=" . intval($ah['id']) . " ORDER BY sort_order ASC, id ASC");
        while ($ai = mysqli_fetch_assoc($aiq)) $ah['items'][] = $ai;
        $assetHeadings[] = $ah;
    }
}

$assetInstance = null;
$assetGrouped = [];
if ($activeTab === 'assets' && $asset_mode !== 'manage' && $exit_id > 0 && $exitRow && $empRow) {
    $assetInstance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_asset_instance WHERE exit_id=$exit_id LIMIT 1"));

    if ($assetInstance && $assetInstance['status'] === 'in_progress') {
        // Diff-sync: pick up any template items added after this instance was started (frozen once signed/completed)
        list($sync_dept_id, $sync_pos_id) = resolveDeptPos($con, $empRow);
        $existing_item_ids = [];
        $ex_res = mysqli_query($con, "SELECT item_id FROM hr_exit_asset_run_items WHERE instance_id=" . intval($assetInstance['id']) . " AND item_id IS NOT NULL");
        while ($ex = mysqli_fetch_assoc($ex_res)) $existing_item_ids[intval($ex['item_id'])] = true;

        $sync_hq = mysqli_query($con, "SELECT * FROM hr_exit_asset_headings WHERE (department_id=$sync_dept_id OR department_id=0) AND (position_id=$sync_pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
        while ($sync_h = mysqli_fetch_assoc($sync_hq)) {
            $sync_iq = mysqli_query($con, "SELECT * FROM hr_exit_asset_items WHERE heading_id=" . intval($sync_h['id']) . " ORDER BY sort_order ASC, id ASC");
            while ($sync_i = mysqli_fetch_assoc($sync_iq)) {
                if (isset($existing_item_ids[intval($sync_i['id'])])) continue;
                $sh_name_e = mysqli_real_escape_string($con, $sync_h['heading_name']);
                $si_text_e = mysqli_real_escape_string($con, $sync_i['item_text']);
                mysqli_query($con, "INSERT INTO hr_exit_asset_run_items (instance_id, heading_id, heading_name, heading_sort, show_condition_field, item_id, item_text, item_sort) VALUES (" . intval($assetInstance['id']) . ", {$sync_h['id']}, '$sh_name_e', {$sync_h['sort_order']}, {$sync_h['show_condition_field']}, {$sync_i['id']}, '$si_text_e', {$sync_i['sort_order']})");
            }
        }
    }

    if ($assetInstance) {
        $air = mysqli_query($con, "SELECT * FROM hr_exit_asset_run_items WHERE instance_id=" . intval($assetInstance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
        while ($ai_row = mysqli_fetch_assoc($air)) {
            $gk = $ai_row['heading_name'];
            if (!isset($assetGrouped[$gk])) $assetGrouped[$gk] = ['heading_id' => $ai_row['heading_id'], 'show_condition_field' => $ai_row['show_condition_field'], 'items' => []];
            $assetGrouped[$gk]['items'][] = $ai_row;
        }
    }
}

// =========================================================================
// DEPARTMENT-POSITION CLEARANCE — PAGE DATA
// =========================================================================
$clearance_mode = $_GET['clearance_mode'] ?? '';

// Same persistent-list approach as Asset Handover — visible through the whole exit lifecycle.
$clearancePendingExits = [];
$cpeq = mysqli_query($con, "
    SELECT r.*, e.name as employee_name, ci.status as clearance_status, ci.position_head_notified_at as clr_notified_at, ci.position_head_token as clr_ph_token, ci.id as clr_instance_id,
           ph.email as ph_email, ph.personal_email as ph_pemail, ph.phone as ph_phone, ph.alt_phone as ph_mobile
    FROM hr_exit_requests r
    LEFT JOIN hr_employees e ON e.id = r.employee_id
    LEFT JOIN hr_exit_clearance_instance ci ON ci.exit_id = r.id
    LEFT JOIN hr_employees ph ON ci.position_head_employee_id = ph.id
    WHERE r.status NOT IN ('link_sent','initiated','retained','rejected')
    ORDER BY r.id DESC
");
if ($cpeq) while ($row = mysqli_fetch_assoc($cpeq)) $clearancePendingExits[] = $row;

// Auto-fix: advance any exits where clearance instance is 'completed' but hr_exit_requests.status is still 'clearance'
mysqli_query($con, "UPDATE hr_exit_requests r
    JOIN hr_exit_clearance_instance ci ON ci.exit_id = r.id
    SET r.status='interview_settlement'
    WHERE r.status='clearance' AND ci.status='completed'");

// For each waiting exit, resolve the employee's actual Department/Position and check
// whether a clearance template has been configured for that combo yet (same lookup
// assign_clearance_instance uses — dept_id+pos_id only, ignoring position head).
foreach ($clearancePendingExits as &$cpe) {
    $cpe['clr_dept_id'] = 0; $cpe['clr_pos_id'] = 0; $cpe['clr_template_configured'] = false; $cpe['clr_needs_head'] = false;
    $cpe_emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=" . intval($cpe['employee_id']) . " LIMIT 1"));
    if ($cpe_emp) {
        list($cpe_dept_id, $cpe_pos_id) = resolveDeptPos($con, $cpe_emp);
        $cpe['clr_dept_id'] = $cpe_dept_id;
        $cpe['clr_pos_id'] = $cpe_pos_id;
        if ($cpe_dept_id > 0 && $cpe_pos_id > 0) {
            $cpe_tpl = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, position_head_employee_id FROM hr_exit_clearance_templates WHERE department_id=$cpe_dept_id AND position_id=$cpe_pos_id LIMIT 1"));
            $cpe['clr_template_configured'] = (bool)$cpe_tpl && !empty($cpe_tpl['position_head_employee_id']);
            $cpe['clr_needs_head'] = (bool)$cpe_tpl && empty($cpe_tpl['position_head_employee_id']);
        }
    }
}
unset($cpe);

// Department x Position coverage matrix for the Manage Clearance Template screen — every
// position under every department gets a row (not just ones already configured), mirroring
// hr-OJE.php's coverage summary so HR can see at a glance what's configured vs missing.
$clearanceMatrix = [];
$clearanceMatrixConfigured = 0;
$clearanceMatrixNeedsHead = 0;
$clearanceMatrixMissing = 0;
$cmq = mysqli_query($con, "
    SELECT d.id as dept_id, d.name as dept_name, p.id as pos_id, p.title as pos_title,
           t.id as template_id, t.position_head_employee_id, eh.name as position_head_name,
           (SELECT COUNT(*) FROM hr_exit_clearance_headings h WHERE h.template_id = t.id) as heading_count
    FROM hr_departments d
    JOIN hr_positions p ON p.department_id = d.id
    LEFT JOIN hr_exit_clearance_templates t ON t.department_id = d.id AND t.position_id = p.id
    LEFT JOIN hr_employees eh ON eh.id = t.position_head_employee_id
    ORDER BY d.name ASC, p.title ASC
");
if ($cmq) while ($row = mysqli_fetch_assoc($cmq)) {
    if (!$row['template_id']) $clearanceMatrixMissing++;
    elseif (!$row['position_head_employee_id']) $clearanceMatrixNeedsHead++;
    else $clearanceMatrixConfigured++;
    $clearanceMatrix[] = $row;
}

// Manage Clearance Template: Department -> Position (filtered) -> Position Head pickers
$clr_dept_id = intval($_GET['clr_department_id'] ?? 0);
$clr_pos_id  = intval($_GET['clr_position_id'] ?? 0);
$clr_head_id = intval($_GET['clr_position_head_id'] ?? 0);

$clearancePositions = [];
if ($clr_dept_id > 0) {
    $cpq = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$clr_dept_id ORDER BY title ASC");
    if ($cpq) while ($row = mysqli_fetch_assoc($cpq)) $clearancePositions[] = $row;
}

$clearanceTemplate = null;
$clearanceHeadings = [];
if ($activeTab === 'clearance2' && $clearance_mode === 'manage' && $clr_dept_id > 0 && $clr_pos_id > 0) {
    // Keyed on Department+Position only — Position Head is optional and can be assigned/changed
    // later from the Save Details form below, so it's not required just to view/edit a template.
    $ct_q = mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE department_id=$clr_dept_id AND position_id=$clr_pos_id LIMIT 1");
    $clearanceTemplate = $ct_q ? mysqli_fetch_assoc($ct_q) : null;

    // SELF-HEALING: Disabled because it deletes valid templates while users are building them manually.
    /*
    if ($clearanceTemplate) {
        $hc_q = mysqli_query($con, "SELECT id FROM hr_exit_clearance_headings WHERE template_id=" . $clearanceTemplate['id'] . " LIMIT 1");
        $h_row = $hc_q ? mysqli_fetch_assoc($hc_q) : null;
        $items_count = 0;
        if ($h_row) {
             $ic_q = mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_clearance_checklist_items WHERE heading_id=" . $h_row['id']);
             $ic = $ic_q ? mysqli_fetch_assoc($ic_q) : null;
             if ($ic) $items_count = intval($ic['c']);
        }
        
        if ($items_count == 0) {
            mysqli_query($con, "DELETE FROM hr_exit_clearance_templates WHERE id=" . $clearanceTemplate['id']);
            $clearanceTemplate = null;
        }
    }
    */

    if (!$clearanceTemplate) {
        $by_e = mysqli_real_escape_string($con, $currentUserName);
        $ct_head_sql = $clr_head_id > 0 ? $clr_head_id : 0;
        mysqli_query($con, "INSERT INTO hr_exit_clearance_templates (department_id, position_id, position_head_employee_id, created_by) VALUES ($clr_dept_id, $clr_pos_id, $ct_head_sql, '$by_e')");
        $ct_q2 = mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE department_id=$clr_dept_id AND position_id=$clr_pos_id LIMIT 1");
        $clearanceTemplate = $ct_q2 ? mysqli_fetch_assoc($ct_q2) : null;

        if ($clearanceTemplate) {
            $cdp_q = mysqli_query($con, "SELECT title FROM hr_positions WHERE id=" . intval($clr_pos_id) . " LIMIT 1");
            $cdpTitleRow = $cdp_q ? mysqli_fetch_assoc($cdp_q) : null;
        $cdpDefault = $cdpTitleRow ? clearanceDefaultTemplateFor($cdpTitleRow['title']) : null;
        if ($cdpDefault) {
            $cdp_sig_e = mysqli_real_escape_string($con, $cdpDefault['signatory_title']);
            $cdp_decl_e = mysqli_real_escape_string($con, $cdpDefault['declaration_text']);
            mysqli_query($con, "UPDATE hr_exit_clearance_templates SET signatory_title='$cdp_sig_e', declaration_text='$cdp_decl_e' WHERE id=" . intval($clearanceTemplate['id']));
            $clearanceTemplate['signatory_title'] = $cdpDefault['signatory_title'];
            $clearanceTemplate['declaration_text'] = $cdpDefault['declaration_text'];
            $cdp_hsort = 0;
            foreach ($cdpDefault['headings'] as $cdpHeading) {
                $cdp_hname_e = mysqli_real_escape_string($con, $cdpHeading['name']);
                mysqli_query($con, "INSERT INTO hr_exit_clearance_headings (template_id, heading_name, sort_order) VALUES (" . intval($clearanceTemplate['id']) . ", '$cdp_hname_e', $cdp_hsort)");
                $cdp_heading_id = mysqli_insert_id($con);
                $cdp_isort = 0;
                foreach ($cdpHeading['items'] as $cdpItemText) {
                    $cdp_item_e = mysqli_real_escape_string($con, $cdpItemText);
                    mysqli_query($con, "INSERT INTO hr_exit_clearance_checklist_items (heading_id, item_text, sort_order) VALUES ($cdp_heading_id, '$cdp_item_e', $cdp_isort)");
                    $cdp_isort++;
                }
                $cdp_hsort++;
            }
        }
        } // close if ($clearanceTemplate)
    }
    
    if ($clearanceTemplate) {
        $chq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_headings WHERE template_id=" . intval($clearanceTemplate['id']) . " ORDER BY sort_order ASC, id ASC");
        if ($chq) {
            while ($ch = mysqli_fetch_assoc($chq)) {
                $ch['items'] = [];
                $ciq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_checklist_items WHERE heading_id=" . intval($ch['id']) . " ORDER BY sort_order ASC, id ASC");
                if ($ciq) {
                    while ($ci = mysqli_fetch_assoc($ciq)) $ch['items'][] = $ci;
                }
                $clearanceHeadings[] = $ch;
            }
        }
    }
}

$clearanceInstance = null;
$clearanceGrouped = [];
$clearanceTemplateForInstance = null;
$clearanceHeadName = '';
if ($activeTab === 'clearance2' && $clearance_mode !== 'manage' && $exit_id > 0 && $exitRow && $empRow) {
    $clearanceInstance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_instance WHERE exit_id=$exit_id LIMIT 1"));
    if ($clearanceInstance) {
        if (!empty($clearanceInstance['template_id'])) {
            $clearanceTemplateForInstance = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_clearance_templates WHERE id=" . intval($clearanceInstance['template_id']) . " LIMIT 1"));
        }
        if (!empty($clearanceInstance['position_head_employee_id'])) {
            $chr = mysqli_fetch_assoc(mysqli_query($con, "SELECT name, email, personal_email, phone, alt_phone FROM hr_employees WHERE id=" . intval($clearanceInstance['position_head_employee_id']) . " LIMIT 1"));
            $clearanceHeadName = $chr['name'] ?? '';
            $clearanceInstance['ph_email'] = !empty($chr['email']) ? $chr['email'] : $chr['personal_email'];
            $clearanceInstance['ph_phone'] = !empty($chr['alt_phone']) ? $chr['alt_phone'] : $chr['phone'];
        }
        $cir = mysqli_query($con, "SELECT * FROM hr_exit_clearance_run_items WHERE instance_id=" . intval($clearanceInstance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
        while ($ci_row = mysqli_fetch_assoc($cir)) {
            $cgk = $ci_row['heading_name'];
            if (!isset($clearanceGrouped[$cgk])) $clearanceGrouped[$cgk] = ['items' => []];
            $clearanceGrouped[$cgk]['items'][] = $ci_row;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Handover — Exit Module</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--teal:#0f766e;--green:#10b981;--gray-bg:#f0f4f8;}
*{box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--gray-bg);margin:0;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--teal));padding:20px 30px;border-radius:12px;margin:20px;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-weight:800;font-size:1.3rem;margin:0;}
.hdr p{color:rgba(255,255,255,.7);font-size:12px;margin:4px 0 0;}
.wrap{max-width:1400px;margin:0 auto;padding:0 20px 30px;}
.tab-bar{display:flex;gap:6px;background:#fff;padding:6px;border-radius:12px;border:1px solid #e2e8f0;margin-bottom:18px;}
.tab-bar a{flex:1;text-align:center;padding:10px;border-radius:8px;font-weight:700;font-size:13px;color:#64748b;text-decoration:none;}
.tab-bar a.active{background:linear-gradient(135deg,var(--navy),var(--teal));color:#fff;}
.card-box{background:#fff;border-radius:12px;padding:22px;box-shadow:0 2px 10px rgba(0,0,0,.06);margin-bottom:18px;}
.card-box h5{font-weight:800;color:var(--navy);margin-bottom:14px;font-size:15px;}
.fc{border:2px solid #e2e8f0;border-radius:8px;padding:9px 12px;font-size:13px;font-weight:600;width:100%;}
label.fl{font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;}
.fg{margin-bottom:12px;}
.btn-p{padding:9px 18px;border:none;border-radius:8px;font-weight:700;font-size:12px;cursor:pointer;color:#fff;display:inline-block;}
a.btn-p:hover { opacity: 0.9; color: #fff !important; text-decoration: none !important; }
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--teal));}
.btn-red{background:#dc2626;color:#fff;}
.btn-red:hover{background:#b91c1c;}
.btn-green{background:linear-gradient(135deg,var(--green),#059669);}
.progress-track{height:10px;border-radius:5px;background:#e0e7ff;overflow:hidden;}
.progress-fill{height:100%;background:linear-gradient(90deg,var(--teal),var(--green));}
.item-card{border:1.5px solid #e2e8f0;border-radius:10px;padding:14px 16px;margin-bottom:10px;}
.item-card.filled{border-color:#fde68a;background:#fffbeb;}
.item-card.acknowledged{border-color:#bbf7d0;background:#f0fdf4;}
.badge{padding:4px 10px;border-radius:12px;font-size:11px;font-weight:800;}
.b-pending{background:#f1f5f9;color:#475569;}
.b-filled{background:#fef3c7;color:#92400e;}
.b-acknowledged{background:#d1fae5;color:#065f46;}
.b-rejected{background:#fee2e2;color:#991b1b;}
table{width:100%;border-collapse:collapse;}
th{background:#f0f4f8;color:var(--navy);font-weight:800;font-size:11px;text-transform:uppercase;padding:10px 12px;text-align:left;}
td{padding:10px 12px;border-bottom:1px solid #f1f5f9;font-size:12.5px;}

/* Inline template preview (Manage Asset Handover Checklist) */
.tpl-tab-toggle{display:flex;gap:8px;margin-bottom:16px;}
.tpl-tab-toggle button{padding:8px 20px;border-radius:8px;font-weight:700;font-size:12.5px;border:1.5px solid #e2e8f0;background:#fff;color:#64748b;cursor:pointer;}
.tpl-tab-toggle button.active{background:linear-gradient(135deg,var(--navy),var(--teal));color:#fff;border-color:transparent;}
.preview-doc{width:100%;max-width:800px;margin:0 auto;background:#fff;border:1px solid #e2e8f0;border-radius:10px;box-shadow:0 2px 15px rgba(0,0,0,.08);overflow:hidden;}
.preview-doc .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
.preview-doc .letter-wave-top svg{width:100%;height:60px;display:block;}
.preview-doc .letter-wave-bottom{width:100%;line-height:0;display:block;margin-top:30px;}
.preview-doc .letter-wave-bottom svg{width:100%;height:70px;display:block;}
.preview-doc .letter-header{display:flex;justify-content:space-between;align-items:center;padding:8px 30px 12px;border-bottom:3px solid #3b5998;background:#fff;}
.preview-doc .letter-header-left{font-size:12px;color:#0f2557;font-weight:700;}
.preview-doc .letter-header-left span{display:flex;align-items:center;gap:6px;margin-bottom:2px;}
.preview-doc .letter-header-right img{max-height:70px;max-width:160px;object-fit:contain;display:block;margin-left:auto;}
.preview-doc .pdf-content-wrapper{padding:0 24px 24px;}
.preview-doc .doc-title{font-size:15px;font-weight:800;text-align:center;text-decoration:underline;margin:20px 0;color:#0f2557;}
.preview-doc .doc-field-row{display:flex;flex-wrap:wrap;gap:0 20px;margin-bottom:14px;}
.preview-doc .doc-field{width:47%;margin-bottom:10px;}
.preview-doc .doc-field label{font-weight:700;font-size:11px;display:block;margin-bottom:3px;color:#334155;text-transform:uppercase;letter-spacing:.3px;}
.preview-doc .doc-field .val{border-bottom:1px solid #94a3b8;padding:4px;font-size:13px;min-height:16px;color:#94a3b8;}
.preview-doc table.asset-tbl{width:100%;border-collapse:collapse;margin:12px 0 20px;font-size:11.5px;table-layout:fixed;}
.preview-doc table.asset-tbl col.a-no{width:8%;}
.preview-doc table.asset-tbl col.a-item{width:36%;}
.preview-doc table.asset-tbl col.a-ret{width:14%;}
.preview-doc table.asset-tbl col.a-cond{width:18%;}
.preview-doc table.asset-tbl col.a-remarks{width:24%;}
.preview-doc table.asset-tbl th,.preview-doc table.asset-tbl td{box-sizing:border-box;border:1px solid #cbd5e1;padding:6px 8px;text-align:left;overflow-wrap:break-word;word-break:break-word;}
.preview-doc table.asset-tbl th{background:#0f2557;color:#fff;font-weight:700;font-size:10px;text-transform:uppercase;letter-spacing:.3px;}
.preview-doc table.asset-tbl tbody tr:nth-child(even){background:#f8faff;}
.preview-doc .section-heading{font-weight:800;color:#0f2557;font-size:13px;margin:16px 0 8px;padding-bottom:5px;border-bottom:2px solid #eef2ff;}
.preview-doc table.clr-tbl{width:100%;border-collapse:collapse;margin:12px 0 20px;font-size:11.5px;table-layout:fixed;}
.preview-doc table.clr-tbl col.c-no{width:5%;}
.preview-doc table.clr-tbl col.c-item{width:45%;}
.preview-doc table.clr-tbl col.c-chk{width:10%;}
.preview-doc table.clr-tbl col.c-remarks{width:20%;}
.preview-doc table.clr-tbl th,.preview-doc table.clr-tbl td{box-sizing:border-box;border:1px solid #cbd5e1;padding:6px 8px;text-align:left;vertical-align:middle;overflow-wrap:break-word;word-break:break-word;}
.preview-doc table.clr-tbl th{background:#0f2557;color:#fff;font-weight:700;font-size:10px;text-transform:uppercase;letter-spacing:.3px;}
.preview-doc table.clr-tbl tbody tr:nth-child(even){background:#f8faff;}
.preview-doc table.clr-tbl td.chk{text-align:center;font-weight:800;color:#94a3b8;}
.preview-doc .checklist-item{font-size:12px;color:#334155;margin-bottom:6px;padding-left:24px;position:relative;}
.preview-doc .checklist-item .box{position:absolute;left:0;top:1px;width:14px;height:14px;border:2px solid #94a3b8;border-radius:3px;display:inline-block;background:#fff;}
.preview-doc .sig-area{margin-top:30px;display:flex;justify-content:space-between;}
.preview-doc .sig-box{width:220px;}
.preview-doc .sig-line{border-top:1px solid #334155;margin-top:60px;padding-top:5px;font-size:11px;font-weight:700;}

/* Department x Position coverage matrix (Manage Clearance Template) */
.coverage-header{background:#f1f5f9;padding:15px 20px;border-bottom:1px solid #e2e8f0;display:flex;justify-content:space-between;align-items:center;cursor:pointer;flex-wrap:wrap;gap:10px;border-radius:10px 10px 0 0;}
.coverage-header:hover{background:#e2e8f0;}
.coverage-header h6{margin:0;font-weight:800;color:var(--navy);font-size:14px;}
.coverage-flat-table{width:100%;border-collapse:collapse;}
.coverage-flat-table th{text-align:left;padding:10px 14px;background:#f8fafc;color:#64748b;font-weight:700;font-size:11px;text-transform:uppercase;letter-spacing:.4px;border-bottom:2px solid #e2e8f0;white-space:nowrap;}
.coverage-flat-table td{padding:10px 14px;border-bottom:1px solid #eef2f6;vertical-align:middle;font-size:12.5px;color:#334155;}
.coverage-flat-table tbody tr:hover{background:#f8fafc;}
.rc-count{display:inline-block;padding:4px 11px;border-radius:20px;font-size:11.5px;font-weight:700;text-decoration:none;transition:all .2s ease;}
.rc-count.rc-ok{background:#dcfce7;color:#15803d;}
.rc-count.rc-ok:hover{background:#16a34a;color:#fff;text-decoration:none;}
.rc-count.rc-missing{background:#fee2e2;color:#b91c1c;}
.rc-count.rc-missing:hover{background:#dc2626;color:#fff;text-decoration:none;}
.rc-count.rc-warn{background:#fef3c7;color:#92400e;}
.rc-count.rc-warn:hover{background:#f59e0b;color:#fff;text-decoration:none;}
/* ── Filter bar (matches hr_candidate_tracking.php's action-bar / form-control-ct) ── */
.dt-filters { display: flex; gap: 12px; margin-bottom: 16px; align-items: center; background: #fff; padding: 14px 16px; border-radius: 12px; border: 1px solid #e2e8f0; box-shadow: 0 2px 10px rgba(0,0,0,.05); flex-wrap: wrap; }
.dt-filters label { display: none; }
.dt-filters input, .dt-filters select { padding: 10px 14px; border: 2px solid #e2e8f0; border-radius: 9px; font-size: 13px; font-weight: 500; color: #334155; background: #fff; transition: .2s; width: 170px; }
.dt-filters input[type="date"] { width: 150px; }
.dt-filters input:focus, .dt-filters select:focus { outline: none; border-color: var(--teal); box-shadow: 0 0 0 3px rgba(15,118,110,.12); }
.dt-search-wrap { position: relative; min-width: 220px; flex: 1; }
.dt-search-wrap i { position: absolute; left: 14px; top: 50%; transform: translateY(-50%); color: #94a3b8; font-size: 13px; }
.dt-search-wrap input { width: 100%; padding: 10px 14px 10px 38px; }
.dt-export-btn { background: linear-gradient(135deg,var(--green),#059669); border: none; border-radius: 9px; color: #fff; font-size: 12.5px; font-weight: 700; padding: 10px 18px; cursor: pointer; transition: all 0.2s; display: inline-flex; align-items: center; gap: 6px; box-shadow: 0 3px 10px rgba(16,185,129,.25); }
.dt-export-btn:hover { transform: translateY(-1px); box-shadow: 0 5px 16px rgba(16,185,129,.35); }

/* ── Table card (matches hr_candidate_tracking.php's table-card / ctrack-table) ── */
.table-card { background: #fff; border-radius: 14px; box-shadow: 0 2px 12px rgba(0,0,0,.08); overflow: hidden; }
.table-card-header { padding: 16px 20px; border-bottom: 2px solid #e2e8f0; display: flex; justify-content: space-between; align-items: center; }
.table-card-header h5 { font-weight: 700; color: var(--navy); margin: 0; }
.table-scroll { overflow-x: auto; overflow-y: auto; max-height: 68vh; }
.ctrack-table { width: 100%; border-collapse: collapse; min-width: 700px; }
.ctrack-table thead th { background: linear-gradient(135deg,var(--navy),var(--teal)); color: #fff; font-weight: 700; font-size: 12.5px; text-transform: uppercase; letter-spacing: .4px; padding: 13px 16px; white-space: nowrap; border-right: 1px solid rgba(255,255,255,.15); position: sticky; top: 0; z-index: 10; }
.ctrack-table thead th:last-child { border-right: none; }
.ctrack-table tbody tr { border-bottom: 1px solid #f1f5f9; transition: .15s; }
.ctrack-table tbody tr:hover { background: #f8fafc; }
.ctrack-table tbody td { padding: 13px 16px; font-size: 13.5px; font-weight: 500; color: #334155; vertical-align: middle; }
.ctrack-empty { text-align: center; padding: 40px 20px; color: #94a3b8; }

/* ── Pagination (matches hr_candidate_tracking.php's paging-wrap / paging-btn) ── */
.paging-wrap { padding: 16px 20px; display: flex; align-items: center; justify-content: space-between; border-top: 2px solid #e2e8f0; flex-wrap: wrap; gap: 12px; }
.paging-info { color: #64748b; font-size: 13px; font-weight: 600; }
.paging-btns { display: flex; gap: 6px; }
.paging-btn { padding: 7px 14px; border-radius: 8px; border: 2px solid #e2e8f0; background: #fff; color: var(--navy); font-weight: 700; font-size: 13px; cursor: pointer; transition: .2s; }
.paging-btn:hover, .paging-btn.active { background: var(--navy); color: #fff; border-color: var(--navy); }
.paging-btn:disabled { opacity: .4; cursor: not-allowed; }
</style>
</head>
<body>
<div class="hdr" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:14px;">
  <div><h1><i class="fas fa-people-arrows mr-2"></i>Handover</h1><!-- <p>Step 2 of 5 — nominate a receiver and transfer pending work</p> --></div>
  
</div>
<div class="wrap">

<?php if (isset($_SESSION['success_message'])): ?>
<div class="alert alert-success"><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?></div>
<?php endif; ?>

<?php if (isset($_SESSION['error_message'])): ?>
<div class="alert" style="background:#fee2e2;color:#991b1b;border:1px solid #fecaca;border-radius:8px;padding:10px 14px;font-size:12.5px;font-weight:700;margin-bottom:12px;"><i class="fas fa-triangle-exclamation mr-1"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?></div>
<?php endif; ?>

<div class="tab-bar">
  <a href="?tab=assets" class="<?php echo $activeTab=='assets'?'active':''; ?>"><i class="fas fa-boxes-stacked mr-1"></i>Asset Handover</a>
  <a href="?tab=clearance2" class="<?php echo ($activeTab=='clearance2' && $clearance_mode!=='manage')?'active':''; ?>"><i class="fas fa-user-shield mr-1"></i>Department-Position Clearance</a>
  <a href="?tab=clearance2&clearance_mode=manage" class="<?php echo ($activeTab=='clearance2' && $clearance_mode==='manage')?'active':''; ?>"><i class="fas fa-cog mr-1"></i>Manage Clearance Template</a>
  <!-- <a href="?tab=template" class="<?php echo $activeTab=='template'?'active':''; ?>"><i class="fas fa-cog mr-1"></i>Template Setup (HR)</a> -->
</div>

<?php if ($activeTab === 'template'): ?>
<div class="card-box">
  <h5><i class="fas fa-layer-group mr-2"></i>Master Handover Checklist (one-time per Department/Position)</h5>
  <form method="GET" class="form-inline mb-3">
    <input type="hidden" name="tab" value="template">
    <select name="department_id" class="fc mr-2" style="max-width:240px;" onchange="this.form.submit()">
      <option value="">-- Select Department --</option>
      <?php foreach ($departments as $d): ?>
      <option value="<?php echo $d['id']; ?>" <?php echo $tpl_dept_id==$d['id']?'selected':''; ?>><?php echo htmlspecialchars($d['name']); ?></option>
      <?php endforeach; ?>
    </select>
  </form>

  <?php if ($tpl_dept_id > 0): ?>
  <form method="POST" class="mb-3">
    <input type="hidden" name="action" value="add_template_item">
    <input type="hidden" name="department_id" value="<?php echo $tpl_dept_id; ?>">
    <input type="hidden" name="position_id" value="0">
    <div class="fg"><label class="fl">Checklist Item</label><input type="text" name="item_title" class="fc" required placeholder="e.g. Pending vendor payments"></div>
    <div class="fg"><label class="fl">Description (optional)</label><input type="text" name="description" class="fc" placeholder="What the supervisor should look for"></div>
    <button type="submit" class="btn-p btn-navy"><i class="fas fa-plus mr-1"></i> Add Item</button>
  </form>
  <table><thead><tr><th>#</th><th>Item</th><th>Description</th></tr></thead><tbody>
  <?php foreach ($templateItems as $i => $t): ?>
  <tr><td><?php echo $i+1; ?></td><td><?php echo htmlspecialchars($t['item_title']); ?></td><td><?php echo htmlspecialchars($t['description']); ?></td></tr>
  <?php endforeach; ?>
  <?php if (empty($templateItems)): ?><tr><td colspan="3" style="text-align:center;color:#94a3b8;">No items yet for this department.</td></tr><?php endif; ?>
  </tbody></table>
  <?php endif; ?>
</div>

<?php elseif ($activeTab === 'assets'): ?>

<?php if ($asset_mode === 'manage'): ?>
<div class="card-box">
  <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:14px;">
    <h5 style="margin:0;"><i class="fas fa-boxes-stacked mr-2"></i>Manage Asset Handover Checklist</h5>
    <a href="?tab=assets" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-arrow-left mr-1"></i> Back to Asset Handover</a>
  </div>

  <div class="tpl-tab-toggle">
    <button type="button" id="tplTabBtn_sections" class="active" onclick="showTplTab('sections')"><i class="fas fa-list mr-1"></i> Sections</button>
    <button type="button" id="tplTabBtn_preview" onclick="showTplTab('preview')"><i class="fas fa-eye mr-1"></i> Preview</button>
  </div>

  <div id="tplPanel_sections">
  <p style="font-size:12.5px;color:#64748b;margin-bottom:12px;"><i class="fas fa-globe mr-1"></i> This checklist applies to every department.</p>

  <button class="btn-p btn-navy mb-3" data-toggle="modal" data-target="#addAssetHeadingModal"><i class="fas fa-plus mr-1"></i> Add Section</button>

  <?php if (empty($assetHeadings)): ?>
    <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist sections for this scope yet.</p>
  <?php else: foreach ($assetHeadings as $ah): ?>
    <div class="item-card" style="margin-bottom:16px;">
      <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;">
        <h6 style="margin:0;font-weight:800;color:var(--navy);"><?php echo htmlspecialchars($ah['heading_name']); ?> <?php if ($ah['show_condition_field']): ?><span class="badge b-filled" style="margin-left:6px;">Has Condition column</span><?php endif; ?></h6>
        <div>
          <button type="button" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;" onclick='editAssetHeading(<?php echo json_encode($ah); ?>)'><i class="fas fa-edit"></i></button>
          <button type="button" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;" onclick="openAddAssetItemModal(<?php echo $ah['id']; ?>, '<?php echo htmlspecialchars(addslashes($ah['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
          <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this section and all its items? Already-filled employee checklists are not affected.');">
            <input type="hidden" name="action" value="delete_asset_heading">
            <input type="hidden" name="id" value="<?php echo $ah['id']; ?>">
            <button type="submit" class="btn-p" style="background:#dc2626;padding:5px 12px;font-size:11px;"><i class="fas fa-trash"></i></button>
          </form>
        </div>
      </div>
      <?php if (empty($ah['items'])): ?>
        <p class="text-muted small mb-0 mt-2">No items yet.</p>
      <?php else: ?>
        <table class="mt-2"><thead><tr><th>#</th><th>Item</th><th></th></tr></thead><tbody>
        <?php foreach ($ah['items'] as $aidx => $ai): ?>
        <tr>
          <td><?php echo $aidx+1; ?></td>
          <td><?php echo htmlspecialchars($ai['item_text']); ?></td>
          <td style="text-align:right;white-space:nowrap;">
            <button type="button" class="btn-p btn-navy" style="padding:3px 10px;font-size:11px;" onclick='editAssetItem(<?php echo json_encode($ai); ?>)'><i class="fas fa-edit"></i></button>
            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?');">
              <input type="hidden" name="action" value="delete_asset_item">
              <input type="hidden" name="id" value="<?php echo $ai['id']; ?>">
              <button type="submit" class="btn-p" style="background:#dc2626;padding:3px 10px;font-size:11px;"><i class="fas fa-trash"></i></button>
            </form>
          </td>
        </tr>
        <?php endforeach; ?>
        </tbody></table>
      <?php endif; ?>
    </div>
  <?php endforeach; endif; ?>
  </div>

  <div id="tplPanel_preview" style="display:none;">
    <div class="preview-banner" style="max-width:800px;margin:0 auto 16px;background:#fff7ed;border:1px solid #fcd34d;border-radius:10px;padding:10px 16px;font-size:12.5px;color:#92400e;font-weight:600;text-align:center;">
      <i class="fas fa-info-circle mr-1"></i> Template preview — shows placeholder data. Real employee details, checkmarks, and signatures appear once an employee's checklist is filled in.
    </div>
    <div class="preview-doc">
      <div class="letter-wave-top">
        <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
          <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
        </svg>
      </div>
      <div class="letter-header">
        <div class="letter-header-left"><span><i class="fas fa-building"></i> <?php echo htmlspecialchars(isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Your Company'); ?></span></div>
        <div class="letter-header-right"></div>
      </div>
      <div class="pdf-content-wrapper">
        <div class="doc-title">Employee Asset Return Checklist</div>
        <div class="doc-field-row">
          <div class="doc-field"><label>Employee Name</label><div class="val">Sample Employee</div></div>
          <div class="doc-field"><label>Employee ID</label><div class="val">—</div></div>
          <div class="doc-field"><label>Department</label><div class="val">Sample Department</div></div>
          <div class="doc-field"><label>Designation</label><div class="val">—</div></div>
          <div class="doc-field"><label>Last Working Day</label><div class="val">—</div></div>
        </div>

        <?php if (empty($assetHeadings)): ?>
          <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist sections for this scope yet.</p>
        <?php endif; ?>
        <?php foreach ($assetHeadings as $ph): ?>
          <div class="section-heading"><?php echo htmlspecialchars($ph['heading_name']); ?></div>
          <?php if ($ph['show_condition_field']): ?>
          <table class="asset-tbl">
            <colgroup>
              <col class="a-no"><col class="a-item"><col class="a-ret"><col class="a-cond"><col class="a-remarks">
            </colgroup>
            <thead><tr><th>Sl. No.</th><th>Asset</th><th>Returned</th><th>Condition</th><th>Remarks</th></tr></thead>
            <tbody>
            <?php if (empty($ph['items'])): ?>
              <tr><td colspan="5" style="text-align:center;color:#94a3b8;">No items yet.</td></tr>
            <?php else: foreach ($ph['items'] as $pidx => $pit): ?>
              <tr>
                <td><?php echo $pidx+1; ?></td>
                <td><?php echo htmlspecialchars($pit['item_text']); ?></td>
                <td style="text-align:center;">✗</td>
                <td>&nbsp;</td>
                <td>&nbsp;</td>
              </tr>
            <?php endforeach; endif; ?>
            </tbody>
          </table>
          <?php else: ?>
          <table class="asset-tbl">
            <colgroup>
              <col class="a-no"><col class="a-item"><col class="a-ret"><col class="a-remarks" style="width:24%;">
            </colgroup>
            <thead><tr><th>Sl. No.</th><th>Asset</th><th>Returned</th><th>Remarks</th></tr></thead>
            <tbody>
            <?php if (empty($ph['items'])): ?>
              <tr><td colspan="4" style="text-align:center;color:#94a3b8;">No items yet.</td></tr>
            <?php else: foreach ($ph['items'] as $pidx => $pit): ?>
              <tr>
                <td><?php echo $pidx+1; ?></td>
                <td><?php echo htmlspecialchars($pit['item_text']); ?></td>
                <td style="text-align:center;">✗</td>
                <td>&nbsp;</td>
              </tr>
            <?php endforeach; endif; ?>
            </tbody>
          </table>
          <?php endif; ?>
        <?php endforeach; ?>

        <div class="sig-area">
          <div class="sig-box"><div class="sig-line">Management Signature<br>For <?php echo htmlspecialchars(isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'the Company'); ?></div></div>
          <div class="sig-box"><div class="sig-line">Signature: Sample Employee<br>Date: _______________________</div></div>
        </div>
      </div>
      <div class="letter-wave-bottom">
        <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
          <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
        </svg>
      </div>
    </div>
  </div>
</div>

<?php else: ?>

  <?php if (!$exit_id): ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:10px;">
      <h5 style="margin:0;"><i class="fas fa-boxes-stacked mr-2"></i>Asset Handover</h5>
      <a href="?tab=assets&asset_mode=manage" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-cog mr-1"></i> Manage Asset Handover Checklist</a>
    </div>
    <div class="dt-filters" id="assetFilters">
      <input type="date" id="assetDateFrom" title="From date (LWD)">
      <input type="date" id="assetDateTo" title="To date (LWD)">
      <select id="assetStatus" title="Status">
        <option value="">All Statuses</option>
      </select>
      <div class="dt-search-wrap"><i class="fas fa-search"></i><input type="text" id="assetSearch" placeholder="Search by exit #, employee, status…"></div>
      <button type="button" class="dt-export-btn" onclick="exportAssetCSV('excel')"><i class="fas fa-file-excel"></i> Export Excel</button>
      <button type="button" class="dt-export-btn" onclick="exportAssetCSV('csv')"><i class="fas fa-file-csv"></i> Export CSV</button>
    </div>
    <div class="table-card">
      <div class="table-card-header">
        <h5><i class="fas fa-list mr-2"></i>Exit Records</h5>
        <span id="assetTableCount" style="font-size:13px;color:#64748b;font-weight:600;"></span>
      </div>
      <div class="table-scroll">
    <table class="ctrack-table" id="assetHandoverTable"><thead><tr><th>Exit #</th><th>Employee</th><th>Last Working Day</th><th>Status</th><th>Action</th></tr></thead><tbody id="assetTbody">
    <?php
    $asset_list_badge_map = [
        'completed'        => ['b-acknowledged', 'Approved & Completed'],
        'pending_approval' => ['b-filled', 'Pending HR Approval'],
        'rejected'         => ['b-rejected', 'Rejected'],
        'not_applicable'   => ['b-pending', 'Not Applicable'],
        'in_progress'      => ['b-filled', 'In Progress'],
    ];
    ?>
    <?php foreach ($assetPendingExits as $p):
        if ($p['asset_status'] === null) { $asset_status_class = 'b-pending'; $asset_status_label = 'Not Started'; }
        else { $lb = $asset_list_badge_map[$p['asset_status']] ?? ['b-pending', ucfirst($p['asset_status'])]; $asset_status_class = $lb[0]; $asset_status_label = $lb[1]; }
        $asset_lwd_iso = $p['final_last_working_day'] ? date('Y-m-d', strtotime($p['final_last_working_day'])) : '';
        $asset_search = strtolower($p['exit_number'].' '.$p['employee_name'].' '.$asset_status_label);
    ?>
    <tr class="asset-row" data-status="<?php echo htmlspecialchars($asset_status_label); ?>" data-lwd="<?php echo $asset_lwd_iso; ?>" data-search="<?php echo htmlspecialchars($asset_search); ?>">
      <td><?php echo htmlspecialchars($p['exit_number']); ?></td>
      <td><?php echo htmlspecialchars($p['employee_name']); ?></td>
      <td><?php echo $p['final_last_working_day'] ? date('d M Y', strtotime($p['final_last_working_day'])) : '—'; ?></td>
      <td><span class="badge <?php echo $asset_status_class; ?>"><?php echo htmlspecialchars($asset_status_label); ?></span></td>
      <td style="white-space:nowrap;">
        <?php if ($p['asset_status'] === null): ?>
        <!-- Give Access Overlay -->
        <div id="assetGiveAccessOverlay<?php echo $p['id']; ?>" style="display:none;position:fixed;inset:0;background:rgba(15,37,87,.45);z-index:99999;align-items:center;justify-content:center;padding:20px;white-space:normal;">
          <div style="background:#fff;border-radius:16px;padding:32px;max-width:380px;width:100%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.25);">
            <div style="width:56px;height:56px;border-radius:50%;background:#d1fae5;color:#059669;display:flex;align-items:center;justify-content:center;font-size:26px;margin:0 auto 16px;"><i class="fas fa-unlock"></i></div>
            <h5 style="font-weight:800;color:var(--navy);margin-bottom:8px;">Confirm Access</h5>
            <p style="color:#64748b;font-size:13px;margin-bottom:24px;">Are you sure you want to give Asset Handover access for <strong><?php echo htmlspecialchars($p['employee_name']); ?></strong>?</p>
            <div style="display:flex;gap:10px;justify-content:center;">
              <button type="button" style="padding:10px 24px;border:2px solid #e2e8f0;background:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;flex:1;" onclick="document.getElementById('assetGiveAccessOverlay<?php echo $p['id']; ?>').style.display='none'">Cancel</button>
              <button type="button" class="btn-green" style="padding:10px 24px;border:none;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;flex:1;" onclick="document.getElementById('formGiveAccess<?php echo $p['id']; ?>').submit()">Yes, Give Access</button>
            </div>
          </div>
        </div>

        <!-- Decline Overlay -->
        <div id="assetDeclineOverlay<?php echo $p['id']; ?>" style="display:none;position:fixed;inset:0;background:rgba(15,37,87,.45);z-index:99999;align-items:center;justify-content:center;padding:20px;white-space:normal;">
          <div style="background:#fff;border-radius:16px;padding:32px;max-width:380px;width:100%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.25);">
            <div style="width:56px;height:56px;border-radius:50%;background:#fee2e2;color:#dc2626;display:flex;align-items:center;justify-content:center;font-size:26px;margin:0 auto 16px;"><i class="fas fa-ban"></i></div>
            <h5 style="font-weight:800;color:var(--navy);margin-bottom:8px;">Confirm Decline</h5>
            <p style="color:#64748b;font-size:13px;margin-bottom:24px;">Mark Asset Handover as not applicable for <strong><?php echo htmlspecialchars($p['employee_name']); ?></strong>? No checklist will be generated.</p>
            <div style="display:flex;gap:10px;justify-content:center;">
              <button type="button" style="padding:10px 24px;border:2px solid #e2e8f0;background:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;flex:1;" onclick="document.getElementById('assetDeclineOverlay<?php echo $p['id']; ?>').style.display='none'">Cancel</button>
              <button type="button" style="padding:10px 24px;border:none;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;flex:1;background:#dc2626;" onclick="document.getElementById('formDecline<?php echo $p['id']; ?>').submit()">Yes, Decline</button>
            </div>
          </div>
        </div>

        <form id="formGiveAccess<?php echo $p['id']; ?>" method="POST" style="display:inline;">
          <input type="hidden" name="action" value="assign_asset_instance">
          <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
          <button type="button" onclick="document.getElementById('assetGiveAccessOverlay<?php echo $p['id']; ?>').style.display='flex'" class="btn-p btn-navy" style="padding:6px 12px;font-size:11px;"><i class="fas fa-unlock mr-1"></i> Give Access</button>
        </form>
        <form id="formDecline<?php echo $p['id']; ?>" method="POST" style="display:inline;">
          <input type="hidden" name="action" value="decline_asset_handover">
          <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
          <button type="button" onclick="document.getElementById('assetDeclineOverlay<?php echo $p['id']; ?>').style.display='flex'" class="btn-p" style="background:#dc2626;padding:6px 12px;font-size:11px;"><i class="fas fa-ban mr-1"></i> Decline</button>
        </form>
        <?php elseif ($p['asset_status'] === 'not_applicable'): ?>
        <form method="POST" style="display:inline;" onsubmit="return confirm('Revert the Decline for <?php echo htmlspecialchars(addslashes($p['employee_name'])); ?>? You will be able to choose Give Access or Decline again.');">
          <input type="hidden" name="action" value="revert_asset_decline">
          <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
          <button type="submit" class="btn-p btn-navy" style="padding:6px 12px;font-size:11px;"><i class="fas fa-rotate-left mr-1"></i> Revert Decline</button>
        </form>
        <?php endif; ?>
        <a href="?tab=assets&exit_id=<?php echo $p['id']; ?>" class="btn-p" style="background:#64748b;padding:6px 12px;font-size:11px;text-decoration:none;"><i class="fas fa-cog mr-1"></i> Manage</a>
        <a href="hr-exit-handover.php?view_asset_doc=<?php echo $p['id']; ?>" target="_blank" class="btn-p btn-navy" style="padding:6px 12px;font-size:11px;text-decoration:none;margin-left:4px;"><i class="fas fa-file-pdf mr-1"></i> View PDF</a>
      </td>
    </tr>
    <?php endforeach; ?>
    <?php if (empty($assetPendingExits)): ?><tr><td colspan="5" class="ctrack-empty">No exits to show.</td></tr><?php endif; ?>
    <tr id="assetNoResultsRow" style="display:none;"><td colspan="5" class="ctrack-empty">No matching records found.</td></tr>
    </tbody></table>
      </div>
      <div class="paging-wrap">
        <div class="paging-info" id="assetPagingInfo"></div>
        <div class="paging-btns" id="assetPagingBtns"></div>
      </div>
    </div>
  </div>

  <?php elseif (!$assetInstance): ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:10px;margin-bottom:8px;">
      <h5 style="margin:0;"><i class="fas fa-boxes-stacked mr-2"></i>Asset Handover — <?php echo htmlspecialchars($exitRow['exit_number']); ?> (<?php echo htmlspecialchars($empRow['name'] ?? ''); ?>)</h5>
      <a href="?tab=assets&asset_mode=manage" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-cog mr-1"></i> Manage Asset Handover Checklist</a>
    </div>
    <p style="color:#64748b;font-size:13px;">Give access to generate the asset return checklist and let the employee fill it in via their exit link — or decline if no assets need to be returned.</p>
    <div style="display:flex;gap:10px;">
      <!-- Single View Give Access Overlay -->
      <div id="assetSingleGiveAccessOverlay" style="display:none;position:fixed;inset:0;background:rgba(15,37,87,.45);z-index:99999;align-items:center;justify-content:center;padding:20px;white-space:normal;">
        <div style="background:#fff;border-radius:16px;padding:32px;max-width:380px;width:100%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.25);">
          <div style="width:56px;height:56px;border-radius:50%;background:#d1fae5;color:#059669;display:flex;align-items:center;justify-content:center;font-size:26px;margin:0 auto 16px;"><i class="fas fa-unlock"></i></div>
          <h5 style="font-weight:800;color:var(--navy);margin-bottom:8px;">Confirm Access</h5>
          <p style="color:#64748b;font-size:13px;margin-bottom:24px;">Are you sure you want to give Asset Handover access for this employee?</p>
          <div style="display:flex;gap:10px;justify-content:center;">
            <button type="button" style="padding:10px 24px;border:2px solid #e2e8f0;background:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;flex:1;" onclick="document.getElementById('assetSingleGiveAccessOverlay').style.display='none'">Cancel</button>
            <button type="button" class="btn-green" style="padding:10px 24px;border:none;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;flex:1;" onclick="document.getElementById('formSingleGiveAccess').submit()">Yes, Give Access</button>
          </div>
        </div>
      </div>

      <!-- Single View Decline Overlay -->
      <div id="assetSingleDeclineOverlay" style="display:none;position:fixed;inset:0;background:rgba(15,37,87,.45);z-index:99999;align-items:center;justify-content:center;padding:20px;white-space:normal;">
        <div style="background:#fff;border-radius:16px;padding:32px;max-width:380px;width:100%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.25);">
          <div style="width:56px;height:56px;border-radius:50%;background:#fee2e2;color:#dc2626;display:flex;align-items:center;justify-content:center;font-size:26px;margin:0 auto 16px;"><i class="fas fa-ban"></i></div>
          <h5 style="font-weight:800;color:var(--navy);margin-bottom:8px;">Confirm Decline</h5>
          <p style="color:#64748b;font-size:13px;margin-bottom:24px;">Mark Asset Handover as not applicable for this employee? No checklist will be generated.</p>
          <div style="display:flex;gap:10px;justify-content:center;">
            <button type="button" style="padding:10px 24px;border:2px solid #e2e8f0;background:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;flex:1;" onclick="document.getElementById('assetSingleDeclineOverlay').style.display='none'">Cancel</button>
            <button type="button" style="padding:10px 24px;border:none;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;flex:1;background:#dc2626;" onclick="document.getElementById('formSingleDecline').submit()">Yes, Decline</button>
          </div>
        </div>
      </div>

      <form id="formSingleGiveAccess" method="POST">
        <input type="hidden" name="action" value="assign_asset_instance">
        <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
        <button type="button" onclick="document.getElementById('assetSingleGiveAccessOverlay').style.display='flex'" class="btn-p btn-navy"><i class="fas fa-unlock mr-1"></i> Give Access</button>
      </form>
      <form id="formSingleDecline" method="POST">
        <input type="hidden" name="action" value="decline_asset_handover">
        <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
        <button type="button" onclick="document.getElementById('assetSingleDeclineOverlay').style.display='flex'" class="btn-p" style="background:#dc2626;"><i class="fas fa-ban mr-1"></i> Decline Access</button>
      </form>
    </div>
  </div>

  <?php else: ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:10px;">
      <h5 style="margin:0;"><i class="fas fa-boxes-stacked mr-2"></i><?php echo htmlspecialchars($exitRow['exit_number']); ?> — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
      <div>
        <?php
        $asset_badge_map = [
            'completed'        => ['b-acknowledged', 'Approved & Completed'],
            'pending_approval' => ['b-filled', 'Pending HR Approval'],
            'rejected'         => ['b-rejected', 'Rejected'],
            'not_applicable'   => ['b-pending', 'Not Applicable'],
        ];
        $asset_badge = $asset_badge_map[$assetInstance['status']] ?? ['b-pending', 'In Progress'];
        ?>
        <span class="badge <?php echo $asset_badge[0]; ?>"><?php echo $asset_badge[1]; ?></span>
        <?php if ($assetInstance['status'] !== 'not_applicable'): ?>
        <a href="hr-exit-handover.php?view_asset_doc=<?php echo $exit_id; ?>" target="_blank" class="btn-p btn-navy" style="text-decoration:none;margin-left:8px;"><i class="fas fa-print mr-1"></i> Preview / Print</a>
        <?php endif; ?>
        <a href="?tab=assets&asset_mode=manage" class="btn-p" style="background:#64748b;text-decoration:none;margin-left:8px;"><i class="fas fa-cog mr-1"></i> Manage Checklist</a>
      </div>
    </div>

    <?php if ($assetInstance['status'] === 'not_applicable'): ?>
    <p style="color:#64748b;font-size:13px;">Asset Handover was marked as not applicable for this employee — no checklist was generated.</p>
    <form method="POST" onsubmit="return confirm('Revert this Decline? You will be able to choose Give Access or Decline again.');">
      <input type="hidden" name="action" value="revert_asset_decline">
      <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
      <button type="submit" class="btn-p btn-navy"><i class="fas fa-rotate-left mr-1"></i> Revert Decline</button>
    </form>
    <?php else: ?>

    <div style="display:flex;flex-wrap:wrap;gap:16px;margin:16px 0;padding:14px 16px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;font-size:12.5px;">
      <div><strong>Employee ID:</strong> <?php echo htmlspecialchars($empRow['employee_id'] ?? '—'); ?></div>
      <div><strong>Department:</strong> <?php echo htmlspecialchars($empRow['department'] ?? '—'); ?></div>
      <div><strong>Designation:</strong> <?php echo htmlspecialchars($empRow['position'] ?? '—'); ?></div>
      <div><strong>Last Working Day:</strong> <?php echo $exitRow['final_last_working_day'] ? date('d M Y', strtotime($exitRow['final_last_working_day'])) : '—'; ?></div>
    </div>

    <?php if ($assetInstance['status'] === 'rejected'): ?>
    <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 16px;font-size:12.5px;color:#991b1b;margin-bottom:16px;">
      <strong>Rejected by <?php echo htmlspecialchars($assetInstance['reviewed_by']); ?></strong> on <?php echo date('d M Y, h:i A', strtotime($assetInstance['reviewed_at'])); ?><br>
      Reason: <?php echo htmlspecialchars($assetInstance['rejection_reason']); ?><br>
      Please review, update if needed, and re-sign below.
    </div>
    <?php endif; ?>

    <?php $asset_readonly = in_array($assetInstance['status'], ['pending_approval','completed']); ?>

    <?php foreach ($assetGrouped as $g_name => $g_data): ?>
    <h6 style="font-weight:800;color:var(--navy);margin:18px 0 10px;"><?php echo htmlspecialchars($g_name); ?></h6>
    <div id="assetSection_<?php echo $g_data['heading_id']; ?>">
      <?php if ($g_data['show_condition_field']): ?>
      <div style="overflow-x:auto;">
        <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
          <thead><tr><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Sl. No.</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Asset</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%;">Returned</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:16%;">Condition</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:24%;">Remarks</th><?php if (!$asset_readonly): ?><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Act</th><?php endif; ?></tr></thead>
          <tbody>
          <?php $vidx=0; foreach ($g_data['items'] as $it): $vidx++; ?>
          <tr id="assetRow_<?php echo $it['id']; ?>" style="background:<?php echo $vidx%2==0?'#f8faff':'#fff'; ?>;">
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;"><?php echo $vidx; ?></td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;"><strong><?php echo htmlspecialchars($it['item_text']); ?></strong><?php if ($it['is_custom']): ?><span class="badge" style="background:#ede9fe;color:#5b21b6;margin-left:6px;font-size:10px;">Custom</span><?php endif; ?></td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
              <input type="checkbox" <?php echo $it['is_checked']?'checked':''; ?> <?php echo $asset_readonly?'disabled':''; ?> onchange="toggleAssetItem(<?php echo $it['id']; ?>, this.checked)" style="width:18px;height:18px;cursor:pointer;margin-top:2px;">
            </td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px;">
              <input type="text" class="fc" placeholder="Condition" value="<?php echo htmlspecialchars($it['condition_text'] ?? ''); ?>" style="padding:4px 8px;font-size:12px;width:100%;" <?php echo $asset_readonly?'readonly':''; ?> onblur="saveAssetDetail(<?php echo $it['id']; ?>)" id="cond_<?php echo $it['id']; ?>">
            </td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px;">
              <input type="text" class="fc" placeholder="Remarks" value="<?php echo htmlspecialchars($it['remarks'] ?? ''); ?>" style="padding:4px 8px;font-size:12px;width:100%;" <?php echo $asset_readonly?'readonly':''; ?> onblur="saveAssetDetail(<?php echo $it['id']; ?>)" id="rem_<?php echo $it['id']; ?>">
            </td>
            <?php if (!$asset_readonly): ?>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
              <?php if ($it['is_custom']): ?>
              <button type="button" class="btn-p" style="background:#dc2626;padding:4px 8px;font-size:10px;" onclick="removeAssetCustomRow(<?php echo $it['id']; ?>)"><i class="fas fa-times"></i></button>
              <?php endif; ?>
            </td>
            <?php endif; ?>
          </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      <?php else: ?>
      <div style="overflow-x:auto;">
        <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
          <thead><tr><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Sl. No.</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Asset</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%;">Returned</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:24%;">Remarks</th><?php if (!$asset_readonly): ?><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Act</th><?php endif; ?></tr></thead>
          <tbody>
          <?php $vidx=0; foreach ($g_data['items'] as $it): $vidx++; ?>
          <tr id="assetRow_<?php echo $it['id']; ?>" style="background:<?php echo $vidx%2==0?'#f8faff':'#fff'; ?>;">
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;"><?php echo $vidx; ?></td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;"><strong><?php echo htmlspecialchars($it['item_text']); ?></strong><?php if ($it['is_custom']): ?><span class="badge" style="background:#ede9fe;color:#5b21b6;margin-left:6px;font-size:10px;">Custom</span><?php endif; ?></td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
              <input type="checkbox" <?php echo $it['is_checked']?'checked':''; ?> <?php echo $asset_readonly?'disabled':''; ?> onchange="toggleAssetItem(<?php echo $it['id']; ?>, this.checked)" style="width:18px;height:18px;cursor:pointer;margin-top:2px;">
            </td>
            <td style="border:1px solid #cbd5e1; padding:8px 10px;">
              <input type="text" class="fc" placeholder="Remarks" value="<?php echo htmlspecialchars($it['remarks'] ?? ''); ?>" style="padding:4px 8px;font-size:12px;width:100%;" <?php echo $asset_readonly?'readonly':''; ?> onblur="saveAssetDetail(<?php echo $it['id']; ?>)" id="rem_<?php echo $it['id']; ?>">
            </td>
            <?php if (!$asset_readonly): ?>
            <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
              <?php if ($it['is_custom']): ?>
              <button type="button" class="btn-p" style="background:#dc2626;padding:4px 8px;font-size:10px;" onclick="removeAssetCustomRow(<?php echo $it['id']; ?>)"><i class="fas fa-times"></i></button>
              <?php endif; ?>
            </td>
            <?php endif; ?>
          </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      <?php endif; ?>
    </div>
    <?php if (!$asset_readonly): ?>
    <div style="display:flex;gap:8px;align-items:center;margin:8px 0 4px;">
      <input type="text" class="fc" id="newRowText_<?php echo $g_data['heading_id']; ?>" placeholder="Add another item to this section..." style="max-width:320px;">
      <button type="button" class="btn-p btn-navy" style="padding:6px 14px;font-size:11px;" onclick="addAssetCustomRow(<?php echo $assetInstance['id']; ?>, <?php echo $g_data['heading_id']; ?>)"><i class="fas fa-plus mr-1"></i> Add Row</button>
    </div>
    <?php endif; ?>
    <?php endforeach; ?>

    <?php if (empty($assetGrouped)): ?>
    <div style="text-align:center;color:#94a3b8;padding:20px;">No checklist items configured — set them up under "Manage Asset Handover Checklist".</div>
    <?php endif; ?>

    <hr style="margin:24px 0;">

    <?php if ($assetInstance['status'] === 'completed'): ?>
      <div class="alert alert-success"><i class="fas fa-check-circle mr-1"></i> Signed by <?php echo htmlspecialchars($assetInstance['signed_by']); ?> on <?php echo date('d M Y, h:i A', strtotime($assetInstance['signed_at'])); ?>. Approved by <?php echo htmlspecialchars($assetInstance['reviewed_by']); ?> on <?php echo date('d M Y, h:i A', strtotime($assetInstance['reviewed_at'])); ?>.</div>
      <?php if (!empty($assetInstance['signature_data'])): ?>
      <img src="<?php echo htmlspecialchars($assetInstance['signature_data']); ?>" style="max-height:100px;border:1px solid #e2e8f0;border-radius:8px;">
      <?php endif; ?>
    <?php elseif ($assetInstance['status'] === 'pending_approval'): ?>
      <div class="alert alert-warning"><i class="fas fa-hourglass-half mr-1"></i> Signed by <?php echo htmlspecialchars($assetInstance['signed_by']); ?> on <?php echo date('d M Y, h:i A', strtotime($assetInstance['signed_at'])); ?>. Awaiting HR approval.</div>
      <?php if (!empty($assetInstance['signature_data'])): ?>
      <img src="<?php echo htmlspecialchars($assetInstance['signature_data']); ?>" style="max-height:100px;border:1px solid #e2e8f0;border-radius:8px;display:block;margin-bottom:12px;">
      <?php endif; ?>
      <button type="button" class="btn-p btn-green" onclick="approveAssetHandover(<?php echo $assetInstance['id']; ?>)"><i class="fas fa-check mr-1"></i> Approve</button>
      <button type="button" class="btn-p" style="background:#dc2626;" onclick="openRejectAssetModal(<?php echo $assetInstance['id']; ?>)"><i class="fas fa-times mr-1"></i> Reject</button>
    <?php else: ?>
      <h6 style="font-weight:800;color:var(--navy);">Employee Signature</h6>
      <p style="font-size:12px;color:#64748b;">Draw your signature below to finalize this checklist.</p>
      <div style="border:2px dashed #a78bfa;border-radius:10px;background:#faf5ff;padding:12px;max-width:500px;">
        <canvas id="assetSigCanvas" width="460" height="150" style="width:100%;height:150px;border:1px solid #ddd6fe;border-radius:8px;background:#fff;cursor:crosshair;touch-action:none;display:block;"></canvas>
        <div style="margin-top:8px;display:flex;gap:8px;">
          <button type="button" class="btn-p" style="background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;" onclick="clearAssetSig()">Clear</button>
          <button type="button" class="btn-p btn-navy" onclick="finalizeAssetSignature(<?php echo $assetInstance['id']; ?>)">Finalize & Sign</button>
        </div>
      </div>
    <?php endif; ?>
    <?php endif; ?>
  </div>
  <?php endif; ?>

<?php endif; ?>
<?php elseif ($activeTab === 'clearance2'): ?>

<?php if ($clearance_mode === 'manage'): ?>
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
    <h5 style="margin:0;"><i class="fas fa-user-shield mr-2"></i>Manage Clearance Template</h5>
    <?php if ($clr_dept_id > 0 && $clr_pos_id > 0): ?>
    <a href="?tab=clearance2&clearance_mode=manage" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-arrow-left mr-1"></i> Back to All Templates</a>
    <?php else: ?>
    <a href="?tab=department_clearance" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-arrow-left mr-1"></i> Back to Department-Position Clearance</a>
    <?php endif; ?>
  </div>

  <?php if (!($clr_dept_id > 0 && $clr_pos_id > 0)): ?>
  <div style="border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;margin-bottom:18px;">
    <div class="coverage-header" onclick="toggleClrCoverage()">
      <h6><i class="fas fa-th-list mr-2"></i>Department &times; Position Coverage (Click to Expand/Collapse)</h6>
      <div style="display:flex;align-items:center;gap:10px;">
        <span class="badge" style="background:#dcfce7;color:#15803d;">Configured — <?php echo $clearanceMatrixConfigured; ?></span>
        <?php if ($clearanceMatrixNeedsHead > 0): ?>
        <span class="badge" style="background:#fef3c7;color:#92400e;">Needs Position Head — <?php echo $clearanceMatrixNeedsHead; ?></span>
        <?php endif; ?>
        <?php if ($clearanceMatrixMissing > 0): ?>
        <span class="badge" style="background:#fee2e2;color:#991b1b;">Not Configured — <?php echo $clearanceMatrixMissing; ?></span>
        <?php elseif ($clearanceMatrixNeedsHead == 0): ?>
        <span class="badge" style="background:#dcfce7;color:#15803d;">All positions covered</span>
        <?php endif; ?>
        <i id="clrCoverageIcon" class="fas fa-chevron-down" style="color:#64748b;"></i>
      </div>
    </div>
    <div id="clrCoverageContent" style="display:none;overflow-x:auto;">
      <table class="coverage-flat-table"><thead><tr><th>Department</th><th>Position</th><th>Status</th><th>Position Head</th><th>Sections</th><th></th></tr></thead><tbody>
      <?php if (empty($clearanceMatrix)): ?>
        <tr><td colspan="6" style="text-align:center;color:#94a3b8;padding:20px;">No positions found. Add positions under HR Setup first.</td></tr>
      <?php else: foreach ($clearanceMatrix as $cm): ?>
      <tr>
        <td><strong><?php echo htmlspecialchars($cm['dept_name']); ?></strong></td>
        <td><?php echo htmlspecialchars($cm['pos_title']); ?></td>
        <td>
          <?php if (!$cm['template_id']): ?>
          <a href="?tab=clearance2&clearance_mode=manage&clr_department_id=<?php echo $cm['dept_id']; ?>&clr_position_id=<?php echo $cm['pos_id']; ?>" class="rc-count rc-missing"><i class="fas fa-xmark mr-1"></i>Not Configured</a>
          <?php elseif (!$cm['position_head_employee_id']): ?>
          <a href="?tab=clearance2&clearance_mode=manage&clr_department_id=<?php echo $cm['dept_id']; ?>&clr_position_id=<?php echo $cm['pos_id']; ?>" class="rc-count rc-warn"><i class="fas fa-user-slash mr-1"></i>Needs Position Head</a>
          <?php else: ?>
          <a href="?tab=clearance2&clearance_mode=manage&clr_department_id=<?php echo $cm['dept_id']; ?>&clr_position_id=<?php echo $cm['pos_id']; ?>" class="rc-count rc-ok"><i class="fas fa-check mr-1"></i>Configured</a>
          <?php endif; ?>
        </td>
        <td><?php echo htmlspecialchars($cm['position_head_name'] ?: '—'); ?></td>
        <td><?php echo $cm['template_id'] ? intval($cm['heading_count']) : '—'; ?></td>
        <td style="text-align:right;white-space:nowrap;">
          <?php if ($cm['template_id']): ?>
          <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this clearance template and all its sections/items? Already-assigned employee checklists are not affected.');">
            <input type="hidden" name="action" value="delete_clearance_template">
            <input type="hidden" name="template_id" value="<?php echo $cm['template_id']; ?>">
            <button type="submit" class="btn-p" style="background:#dc2626;padding:4px 10px;font-size:11px;"><i class="fas fa-trash"></i></button>
          </form>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; endif; ?>
      </tbody></table>
    </div>
  </div>
  <script>
  function toggleClrCoverage(){
    var c=document.getElementById('clrCoverageContent'), i=document.getElementById('clrCoverageIcon');
    var hidden = c.style.display === 'none';
    c.style.display = hidden ? 'block' : 'none';
    i.className = hidden ? 'fas fa-chevron-up' : 'fas fa-chevron-down';
  }
  </script>

  <div class="card-box" style="margin-bottom:24px;background:transparent;box-shadow:none;padding:0;border:none;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;flex-wrap:wrap;gap:10px;">
      <h5 style="margin:0;color:var(--navy);font-weight:800;"><i class="fas fa-layer-group mr-2"></i>All Configured Clearance Templates</h5>
      <div style="display:flex;align-items:center;gap:10px;">
        <div style="position:relative;">
          <i class="fas fa-search" style="position:absolute;left:10px;top:50%;transform:translateY(-50%);color:#94a3b8;font-size:13px;"></i>
          <input type="text" id="templateSearch" onkeyup="filterTemplates()" class="fc" placeholder="Search department or position..." style="max-width:250px;padding-left:30px;font-size:13px;">
        </div>
        <button type="button" class="btn-add" data-toggle="modal" data-target="#newConfigModal" style="background:#2563eb;color:#fff;border:none;padding:8px 16px;border-radius:6px;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-plus mr-1"></i> New Configuration</button>
      </div>
    </div>
    <div id="templatesGrid" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(320px, 1fr));gap:20px;">
      <?php
      $hasConfigured = false;
      foreach ($clearanceMatrix as $cm): 
        if (!$cm['template_id']) continue; // skip unconfigured
        $hasConfigured = true;
      ?>
      <div class="template-card" data-search="<?php echo htmlspecialchars(strtolower($cm['dept_name'] . ' ' . $cm['pos_title'])); ?>" style="background:#fff;border:1px solid #e2e8f0;border-radius:12px;box-shadow:0 4px 6px rgba(0,0,0,0.02);display:flex;flex-direction:column;overflow:hidden;">
        <div style="padding:16px;flex:1;">
          <div style="font-size:10px;font-weight:800;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;"><i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($cm['dept_name'] ?? ''); ?></div>
          <div style="font-size:14px;font-weight:800;color:var(--navy);margin-bottom:12px;"><i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($cm['pos_title'] ?? ''); ?></div>
          
          <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
            <span class="badge" style="background:#dcfce7;color:#15803d;"><i class="fas fa-check-circle mr-1"></i><?php echo intval($cm['heading_count']); ?> Headings</span>
            <?php if (!$cm['position_head_employee_id']): ?>
            <span class="badge" style="background:#fef3c7;color:#92400e;"><i class="fas fa-user-slash mr-1"></i>Needs Head</span>
            <?php else: ?>
            <span class="badge" style="background:#f1f5f9;color:#475569;"><i class="fas fa-user-tie mr-1"></i><?php echo htmlspecialchars($cm['position_head_name'] ?? 'Unknown Employee'); ?></span>
            <?php endif; ?>
          </div>
        </div>
        <div style="background:#f8fafc;padding:12px 16px;border-top:1px solid #f1f5f9;display:flex;gap:8px;">
          <a href="?tab=clearance2&clearance_mode=manage&clr_department_id=<?php echo $cm['dept_id']; ?>&clr_position_id=<?php echo $cm['pos_id']; ?>" class="btn-p btn-navy" style="flex:1;text-align:center;text-decoration:none;"><i class="fas fa-cog mr-1"></i> Manage</a>
          <a href="?tab=clearance2&clearance_mode=manage&clr_department_id=<?php echo $cm['dept_id']; ?>&clr_position_id=<?php echo $cm['pos_id']; ?>&auto_preview=1" class="btn-p" style="background:#64748b;flex:1;text-align:center;text-decoration:none;"><i class="fas fa-eye mr-1"></i> Preview</a>
          <form method="POST" style="display:inline-flex;margin:0;" onsubmit="return confirm('Delete this clearance template and all its sections/items? Already-assigned employee checklists are not affected.');">
            <input type="hidden" name="action" value="delete_clearance_template">
            <input type="hidden" name="template_id" value="<?php echo $cm['template_id']; ?>">
            <button type="submit" class="btn-p btn-red" style="padding: 0 14px; display:flex; justify-content:center; align-items:center; height:100%;" title="Delete Template"><i class="fas fa-trash"></i></button>
          </form>
        </div>
      </div>
      <?php endforeach; ?>
      <?php if (!$hasConfigured): ?>
      <div style="grid-column:1/-1;text-align:center;color:#94a3b8;padding:40px;background:#fff;border:2px dashed #cbd5e1;border-radius:12px;"><i class="fas fa-clipboard-list fa-2x mb-2"></i><br>No clearance templates configured yet. Select a department and position below to create one.</div>
      <?php endif; ?>
    </div>
  </div>
  <?php endif; // end hide overview ?>

  <script>
  function filterTemplates() {
    var input = document.getElementById('templateSearch');
    if(!input) return;
    var filter = input.value.toLowerCase();
    var cards = document.querySelectorAll('.template-card');
    cards.forEach(function(card) {
      var searchData = card.getAttribute('data-search');
      if (searchData && searchData.indexOf(filter) > -1) {
        card.style.display = '';
      } else {
        card.style.display = 'none';
      }
    });
  }
  </script>

  <?php if (!($clr_dept_id > 0 && $clr_pos_id > 0)): ?>
  <?php else: ?>
    <!-- Currently Managing: Show header for the selected template -->
    <?php
        $m_dept = array_reduce($departments, function($c, $d) use ($clr_dept_id){ return $d['id']==$clr_dept_id ? $d['name'] : $c; }, '');
        $m_pos = '';
        foreach ($clearancePositions as $p) { if ($p['id']==$clr_pos_id) { $m_pos = $p['title']; break; } }
    ?>
    <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:16px;margin-bottom:20px;display:flex;align-items:center;gap:16px;">
        <div>
            <div style="font-size:11px;font-weight:800;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;"><i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($m_dept); ?></div>
            <div style="font-size:18px;font-weight:800;color:var(--navy);"><i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($m_pos); ?></div>
        </div>
    </div>
  <?php endif; ?>

  <?php if ($clr_dept_id > 0 && $clr_pos_id > 0 && $clearanceTemplate): ?>

  <?php if (empty($clearanceTemplate['position_head_employee_id'])): ?>
  <div class="alert" style="background:#fee2e2;color:#991b1b;border:1px solid #fecaca;border-radius:8px;padding:10px 14px;font-size:12.5px;font-weight:700;margin-bottom:12px;"><i class="fas fa-triangle-exclamation mr-1"></i> No Position Head assigned yet — Give Access will be blocked for this Department/Position until you assign one below.</div>
  <?php endif; ?>

  <form method="POST" style="margin-bottom:16px;padding:14px 16px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;">
    <input type="hidden" name="action" value="update_clearance_template_meta">
    <input type="hidden" name="template_id" value="<?php echo $clearanceTemplate['id']; ?>">
    <div class="fg"><label class="fl">Position Head (reviews and signs off after the employee)</label>
      <select name="position_head_employee_id" class="fc">
        <option value="0">-- Not Assigned --</option>
        <?php foreach ($employees as $e): ?>
        <option value="<?php echo $e['id']; ?>" <?php echo $clearanceTemplate['position_head_employee_id']==$e['id']?'selected':''; ?>><?php echo htmlspecialchars($e['name']); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fg"><label class="fl">Signatory Title (shown on the document, e.g. "Department Manager")</label><input type="text" name="signatory_title" class="fc" value="<?php echo htmlspecialchars($clearanceTemplate['signatory_title'] ?: 'Position Head'); ?>"></div>
    <div class="fg"><label class="fl">Employee Declaration (shown above the employee's signature — use <code>{{name}}</code> for their name)</label><textarea name="declaration_text" class="fc" rows="4" placeholder="I, {{name}}, hereby confirm that I have handed over all responsibilities, records, and company property assigned to me for this role..."><?php echo htmlspecialchars($clearanceTemplate['declaration_text'] ?? ''); ?></textarea></div>
    <button type="submit" class="btn-p btn-navy" style="padding:7px 16px;font-size:12px;">Save Details</button>
  </form>

  <div class="tpl-tab-toggle">
    <button type="button" id="clrTabBtn_sections" class="active" onclick="showClrTplTab('sections')"><i class="fas fa-list mr-1"></i> Sections</button>
    <button type="button" id="clrTabBtn_preview" onclick="showClrTplTab('preview')"><i class="fas fa-eye mr-1"></i> Preview</button>
  </div>

  <div id="clrTplPanel_sections">
    <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px;">
      <button class="btn-p btn-navy mb-3" data-toggle="modal" data-target="#addClrHeadingModal"><i class="fas fa-plus mr-1"></i> Add Section</button>
      <button type="button" class="btn-p mb-3" style="background:#0f766e;" onclick="exportClrTemplateCSV()"><i class="fas fa-file-export mr-1"></i> Export</button>
      <button type="button" class="btn-p mb-3" style="background:#64748b;" data-toggle="modal" data-target="#clrImportModal"><i class="fas fa-file-import mr-1"></i> Import</button>
    </div>

    <form id="clrImportForm" method="POST" enctype="multipart/form-data" style="display:none;">
      <input type="hidden" name="action" value="import_clearance_sections">
      <input type="hidden" name="template_id" value="<?php echo $clearanceTemplate['id']; ?>">
      <input type="hidden" name="clr_department_id" value="<?php echo $clr_dept_id; ?>">
      <input type="hidden" name="clr_position_id" value="<?php echo $clr_pos_id; ?>">
      <input type="file" id="clrImportFileInput" name="import_file" accept=".csv" onchange="if(this.files.length){ if(confirm('Importing will replace all current sections and items for this template with the contents of the file. Continue?')) document.getElementById('clrImportForm').submit(); else this.value=''; }">
    </form>

    <!-- Import Checklist Modal: download the expected format first, then pick a file -->
    <div class="modal fade" id="clrImportModal" tabindex="-1" role="dialog" aria-hidden="true">
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-header"><h5 class="modal-title"><i class="fas fa-file-import mr-1"></i> Import Checklist Sections</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
          <div class="modal-body">
            <p style="color:#64748b;font-size:13px;margin-bottom:18px;">Import replaces every section and item in this checklist with the contents of the CSV you upload. Download the template first to see the expected two-column format (<code>Section</code>, <code>Item</code>) — for a new checklist it comes with a sample row, or the current sections if you already have some — fill it in, then import it back.</p>
            <div style="display:flex;flex-direction:column;gap:10px;">
              <button type="button" class="btn-p" style="background:#0f766e;" onclick="downloadClrImportTemplate()"><i class="fas fa-file-download mr-1"></i> Download Template</button>
              <button type="button" class="btn-p" style="background:#64748b;" onclick="document.getElementById('clrImportFileInput').click()"><i class="fas fa-file-import mr-1"></i> Choose File &amp; Import</button>
            </div>
          </div>
          <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button></div>
        </div>
      </div>
    </div>

    <?php if (empty($clearanceHeadings)): ?>
      <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist sections yet for this Department / Position / Position Head.</p>
    <?php else: foreach ($clearanceHeadings as $ch): ?>
      <div class="item-card" style="margin-bottom:16px;">
        <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;">
          <h6 style="margin:0;font-weight:800;color:var(--navy);"><?php echo htmlspecialchars($ch['heading_name']); ?></h6>
          <div>
            <button type="button" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;" onclick='editClrHeading(<?php echo json_encode($ch); ?>)'><i class="fas fa-edit"></i></button>
            <button type="button" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;" onclick="openAddClrItemModal(<?php echo $ch['id']; ?>, '<?php echo htmlspecialchars(addslashes($ch['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this section and all its items?');">
              <input type="hidden" name="action" value="delete_clearance_heading">
              <input type="hidden" name="id" value="<?php echo $ch['id']; ?>">
              <button type="submit" class="btn-p" style="background:#dc2626;padding:5px 12px;font-size:11px;"><i class="fas fa-trash"></i></button>
            </form>
          </div>
        </div>
        <?php if (empty($ch['items'])): ?>
          <p class="text-muted small mb-0 mt-2">No items yet.</p>
        <?php else: ?>
          <table class="mt-2"><thead><tr><th>#</th><th>Item</th><th></th></tr></thead><tbody>
          <?php foreach ($ch['items'] as $cidx => $ci): ?>
          <tr>
            <td><?php echo $cidx+1; ?></td>
            <td><?php echo htmlspecialchars($ci['item_text']); ?></td>
            <td style="text-align:right;white-space:nowrap;">
              <button type="button" class="btn-p btn-navy" style="padding:3px 10px;font-size:11px;" onclick='editClrItem(<?php echo json_encode($ci); ?>)'><i class="fas fa-edit"></i></button>
              <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?');">
                <input type="hidden" name="action" value="delete_clearance_item">
                <input type="hidden" name="id" value="<?php echo $ci['id']; ?>">
                <button type="submit" class="btn-p" style="background:#dc2626;padding:3px 10px;font-size:11px;"><i class="fas fa-trash"></i></button>
              </form>
            </td>
          </tr>
          <?php endforeach; ?>
          </tbody></table>
        <?php endif; ?>
      </div>
    <?php endforeach; endif; ?>
  </div>

  <div id="clrTplPanel_preview" style="display:none;">
    <div style="margin-bottom:20px;text-align:right;">
      <button type="button" onclick="window.print()" style="padding:10px 20px;background:#0f2557;color:white;border:none;border-radius:8px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:8px;" class="no-print"><i class="fas fa-print"></i> Print / Download PDF</button>
    </div>
    <div class="preview-doc">
      <div class="letter-wave-top">
        <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
          <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
        </svg>
      </div>
      <div class="letter-header">
        <div class="letter-header-left"><span><i class="fas fa-building"></i> <?php echo htmlspecialchars(isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Your Company'); ?></span></div>
        <div class="letter-header-right"></div>
      </div>
      <div class="pdf-content-wrapper">
        <div class="doc-title">Department-Position Clearance</div>
        <div class="doc-field-row">
          <div class="doc-field"><label>Employee Name</label><div class="val">Sample Employee</div></div>
          <div class="doc-field"><label>Employee ID</label><div class="val">—</div></div>
          <div class="doc-field"><label>Department</label><div class="val"><?php echo htmlspecialchars(array_reduce($departments, function($c,$d) use ($clr_dept_id){ return $d['id']==$clr_dept_id ? $d['name'] : $c; }, '—')); ?></div></div>
          <div class="doc-field"><label>Designation</label><div class="val"><?php echo htmlspecialchars(array_reduce($clearancePositions, function($c,$p) use ($clr_pos_id){ return $p['id']==$clr_pos_id ? $p['title'] : $c; }, '—')); ?></div></div>
          <div class="doc-field"><label>Last Working Day</label><div class="val">—</div></div>
          <div class="doc-field"><label><?php echo htmlspecialchars($clearanceTemplate['signatory_title'] ?: 'Position Head'); ?></label><div class="val"><?php echo htmlspecialchars(array_reduce($employees, function($c,$e) use ($clearanceTemplate){ return $e['id']==$clearanceTemplate['position_head_employee_id'] ? $e['name'] : $c; }, '—')); ?></div></div>
        </div>

        <?php if (empty($clearanceHeadings)): ?>
          <p style="text-align:center;color:#94a3b8;padding:20px;">No checklist sections yet.</p>
        <?php endif; ?>
        <?php foreach ($clearanceHeadings as $ph): ?>
          <div class="section-heading"><?php echo htmlspecialchars($ph['heading_name']); ?></div>
          <?php if (empty($ph['items'])): ?>
            <p style="text-align:center;color:#94a3b8;padding:10px;">No items yet.</p>
          <?php else: ?>
          <table class="clr-tbl">
            <colgroup>
              <col class="c-no"><col class="c-item"><col class="c-chk"><col class="c-chk"><col class="c-chk"><col class="c-remarks">
            </colgroup>
            <thead><tr><th>S.No.</th><th>Clearance Item</th><th>Yes</th><th>No</th><th>N/A</th><th>Remarks</th></tr></thead>
            <tbody>
            <?php foreach ($ph['items'] as $pidx => $pit): ?>
            <tr>
              <td><?php echo $pidx+1; ?></td>
              <td><?php echo htmlspecialchars($pit['item_text']); ?></td>
              <td class="chk">&#9744;</td>
              <td class="chk">&#9744;</td>
              <td class="chk">&#9744;</td>
              <td></td>
            </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
          <?php endif; ?>
        <?php endforeach; ?>

        <?php if (!empty($clearanceTemplate['declaration_text'])): ?>
        <div style="font-size:12px;line-height:1.7;color:#1a202c;margin:18px 0;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px 14px;"><?php echo nl2br(htmlspecialchars(str_replace('{{name}}', 'Sample Employee', $clearanceTemplate['declaration_text']))); ?></div>
        <?php endif; ?>

        <div class="sig-area">
          <div class="sig-box"><div class="sig-line">Management Signature<br>For <?php echo htmlspecialchars(isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'the Company'); ?></div></div>
          <div class="sig-box"><div class="sig-line">Signature: Sample Employee<br>Date: _______________________</div></div>
          <div class="sig-box"><div class="sig-line"><?php echo htmlspecialchars($clearanceTemplate['signatory_title'] ?: 'Position Head'); ?>: <?php echo htmlspecialchars(array_reduce($employees, function($c,$e) use ($clearanceTemplate){ return $e['id']==$clearanceTemplate['position_head_employee_id'] ? $e['name'] : $c; }, '—')); ?><br>Date: _______________________</div></div>
        </div>
      </div>
      <div class="letter-wave-bottom">
        <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
          <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
        </svg>
      </div>
    </div>
  </div>

  <?php else: ?>
    <p style="text-align:center;color:#94a3b8;padding:30px;">Select a Department, Position, and Position Head above to manage that clearance template.</p>
  <?php endif; ?>
</div>

<?php else: ?>

  <?php if (!$exit_id): ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:10px;">
      <h5 style="margin:0;"><i class="fas fa-user-shield mr-2"></i>Department-Position Clearance</h5>
    </div>
    <div class="dt-filters" id="clearanceFilters">
      <input type="date" id="clearanceDateFrom" title="From date (LWD)">
      <input type="date" id="clearanceDateTo" title="To date (LWD)">
      <select id="clearanceDepartment" title="Department">
        <option value="">All — Department</option>
      </select>
      <select id="clearancePosition" title="Position">
        <option value="">All — Position</option>
      </select>
      <select id="clearanceStatus" title="Status">
        <option value="">All Statuses</option>
      </select>
      <div class="dt-search-wrap"><i class="fas fa-search"></i><input type="text" id="clearanceSearch" placeholder="Search by exit #, employee, status…"></div>
      <button type="button" class="dt-export-btn" onclick="exportClearanceCSV('excel')"><i class="fas fa-file-excel"></i> Export Excel</button>
      <button type="button" class="dt-export-btn" onclick="exportClearanceCSV('csv')"><i class="fas fa-file-csv"></i> Export CSV</button>
    </div>
    <div class="table-card">
      <div class="table-card-header">
        <h5><i class="fas fa-list mr-2"></i>Exit Records</h5>
        <span id="clearanceTableCount" style="font-size:13px;color:#64748b;font-weight:600;"></span>
      </div>
      <div class="table-scroll">
    <table class="ctrack-table" id="clearanceTable"><thead><tr><th>Exit #</th><th>Employee</th><th>Dept & Position</th><th>Last Working Day</th><th>Status</th><th>Action</th></tr></thead><tbody id="clearanceTbody">
    <?php
    $clr_badge_map = [
        'completed'                      => ['b-acknowledged', 'Approved & Completed'],
        'pending_position_head_review'   => ['b-filled', 'Pending Position Head Review'],
        'rejected_by_position_head'      => ['b-rejected', 'Rejected by Position Head'],
        'pending_hr_approval'            => ['b-filled', 'Pending HR Approval'],
        'not_applicable'                 => ['b-pending', 'Not Applicable'],
        'in_progress'                    => ['b-filled', 'In Progress'],
    ];
    ?>
    <?php foreach ($clearancePendingExits as $p):
        $dpStr = '—'; $dn = ''; $pn = '';
        if (!empty($p['clr_dept_id']) || !empty($p['clr_pos_id'])) {
            $dn = 'Unknown Dept'; $pn = 'Unknown Pos';
            if (!empty($p['clr_dept_id'])) {
                $dq = mysqli_query($con, "SELECT name FROM hr_departments WHERE id=" . intval($p['clr_dept_id']) . " LIMIT 1");
                if ($dq && $dr = mysqli_fetch_assoc($dq)) $dn = $dr['name'];
            }
            if (!empty($p['clr_pos_id'])) {
                $pq = mysqli_query($con, "SELECT title FROM hr_positions WHERE id=" . intval($p['clr_pos_id']) . " LIMIT 1");
                if ($pq && $pr = mysqli_fetch_assoc($pq)) $pn = $pr['title'];
            }
            $dpStr = "<div style='font-size:11px;font-weight:700;color:var(--navy);'>" . htmlspecialchars($dn) . "</div><div style='font-size:11px;color:#64748b;'>" . htmlspecialchars($pn) . "</div>";
        }
        if ($p['clearance_status'] === null) {
            if ($p['clr_needs_head']) { $clr_status_class = 'b-filled'; $clr_status_label = 'Needs Position Head'; }
            elseif (!$p['clr_template_configured']) { $clr_status_class = 'b-rejected'; $clr_status_label = 'Not Configured'; }
            else { $clr_status_class = 'b-pending'; $clr_status_label = 'Not Started'; }
        } else {
            $lb = $clr_badge_map[$p['clearance_status']] ?? ['b-pending', ucfirst($p['clearance_status'])];
            $clr_status_class = $lb[0]; $clr_status_label = $lb[1];
        }
        $clr_lwd_iso = $p['final_last_working_day'] ? date('Y-m-d', strtotime($p['final_last_working_day'])) : '';
        $clr_search = strtolower($p['exit_number'].' '.$p['employee_name'].' '.$dn.' '.$pn.' '.$clr_status_label);
    ?>
    <tr class="clearance-row" data-status="<?php echo htmlspecialchars($clr_status_label); ?>" data-dept="<?php echo htmlspecialchars($dn); ?>" data-pos="<?php echo htmlspecialchars($pn); ?>" data-lwd="<?php echo $clr_lwd_iso; ?>" data-search="<?php echo htmlspecialchars($clr_search); ?>">
      <td><?php echo htmlspecialchars($p['exit_number']); ?></td>
      <td><?php echo htmlspecialchars($p['employee_name']); ?></td>
      <td><?php echo $dpStr; ?></td>
      <td><?php echo $p['final_last_working_day'] ? date('d M Y', strtotime($p['final_last_working_day'])) : '—'; ?></td>
      <td><span class="badge <?php echo $clr_status_class; ?>"><?php echo htmlspecialchars($clr_status_label); ?></span></td>
      <td style="white-space:nowrap;">
        <?php if ($p['clearance_status'] === null): ?>
          <?php if (!$p['clr_template_configured']): ?>
          <a href="?tab=clearance2&clearance_mode=manage<?php echo $p['clr_dept_id'] ? '&clr_department_id='.$p['clr_dept_id'] : ''; ?><?php echo $p['clr_pos_id'] ? '&clr_position_id='.$p['clr_pos_id'] : ''; ?>" class="btn btn-outline-primary btn-sm"><i class="fas fa-cog mr-1"></i> Configure</a>
          <?php else: ?>
          <form method="POST" style="display:inline;">
            <input type="hidden" name="action" value="assign_clearance_instance">
            <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
            <button type="submit" class="btn btn-outline-success btn-sm"><i class="fas fa-check mr-1"></i> Accept</button>
          </form>
          <?php endif; ?>
        <form method="POST" style="display:inline;" onsubmit="return confirm('Mark Department-Position Clearance as not applicable for <?php echo htmlspecialchars(addslashes($p['employee_name'])); ?>?');">
          <input type="hidden" name="action" value="decline_clearance">
          <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
          <button type="submit" class="btn btn-outline-danger btn-sm"><i class="fas fa-ban mr-1"></i> Decline</button>
        </form>
        <?php elseif ($p['clearance_status'] === 'not_applicable'): ?>
        <form method="POST" style="display:inline;" onsubmit="return confirm('Revert the Decline for <?php echo htmlspecialchars(addslashes($p['employee_name'])); ?>?');">
          <input type="hidden" name="action" value="revert_clearance_decline">
          <input type="hidden" name="exit_id" value="<?php echo $p['id']; ?>">
          <button type="submit" class="btn btn-outline-secondary btn-sm"><i class="fas fa-rotate-left mr-1"></i> Revert</button>
        </form>
        <?php else: ?>
          <?php if (!empty($p['clr_ph_token'])): ?>
            <?php if (empty($p['clr_notified_at'])): ?>
            <button type="button" class="btn btn-outline-primary btn-sm" onclick="openNotifyModal(<?php echo $p['id']; ?>, '<?php echo htmlspecialchars(addslashes($p['employee_name'])); ?>', '<?php echo htmlspecialchars(addslashes($p['ph_email'] ?: $p['ph_pemail'])); ?>', '<?php echo htmlspecialchars(addslashes($p['ph_mobile'] ?: $p['ph_phone'])); ?>', '<?php echo htmlspecialchars(addslashes($p['clr_ph_token'])); ?>')"><i class="fas fa-paper-plane mr-1"></i> Notify</button>
            <?php else: ?>
            <button type="button" class="btn btn-outline-secondary btn-sm" onclick="openNotifyModal(<?php echo $p['id']; ?>, '<?php echo htmlspecialchars(addslashes($p['employee_name'])); ?>', '<?php echo htmlspecialchars(addslashes($p['ph_email'] ?: $p['ph_pemail'])); ?>', '<?php echo htmlspecialchars(addslashes($p['ph_mobile'] ?: $p['ph_phone'])); ?>', '<?php echo htmlspecialchars(addslashes($p['clr_ph_token'])); ?>')"><i class="fas fa-paper-plane mr-1"></i> Re-notify</button>
            <?php endif; ?>
          <?php endif; ?>
          <button type="button" class="btn btn-outline-secondary btn-sm" onclick="openHistoryModal(<?php echo $p['id']; ?>)"><i class="fas fa-history mr-1"></i> History</button>
        <?php endif; ?>
        <?php if ($p['clearance_status'] === 'completed'): ?>
          <a href="hr-exit-employee-interview.php?tab=interviews&view=pending" class="btn btn-success btn-sm" style="margin-top:4px;white-space:nowrap;display:inline-block;"><i class="fas fa-arrow-right mr-1"></i> Go to Interview &amp; Settlement</a>
        <?php endif; ?>
        <a href="?tab=clearance2&exit_id=<?php echo $p['id']; ?>" class="btn btn-outline-primary btn-sm"><i class="fas fa-cog mr-1"></i> Manage</a>
        <a href="hr-exit-handover.php?view_clearance_doc=<?php echo $p['id']; ?>" target="_blank" class="btn btn-primary btn-sm" style="margin-left:4px;"><i class="fas fa-file-pdf mr-1"></i> View PDF</a>
      </td>
    </tr>
    <?php endforeach; ?>
    <?php if (empty($clearancePendingExits)): ?><tr><td colspan="6" class="ctrack-empty">No exits to show.</td></tr><?php endif; ?>
    <tr id="clearanceNoResultsRow" style="display:none;"><td colspan="6" class="ctrack-empty">No matching records found.</td></tr>
    </tbody></table>
      </div>
      <div class="paging-wrap">
        <div class="paging-info" id="clearancePagingInfo"></div>
        <div class="paging-btns" id="clearancePagingBtns"></div>
      </div>
    </div>
  </div>

  <?php elseif (!$clearanceInstance): ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:10px;margin-bottom:8px;">
      <h5 style="margin:0;"><i class="fas fa-user-shield mr-2"></i>Department-Position Clearance — <?php echo htmlspecialchars($exitRow['exit_number']); ?> (<?php echo htmlspecialchars($empRow['name'] ?? ''); ?>)</h5>
      <a href="?tab=clearance2&clearance_mode=manage" class="btn btn-sm btn-outline-primary" style="text-decoration:none;"><i class="fas fa-cog mr-1"></i> Configure</a>
    </div>
    <p style="color:#64748b;font-size:13px;">Accept to generate a clearance link for the Position Head to review and sign off. (Or decline if not applicable.)</p>
    <div style="display:flex;gap:10px;">
      <?php if (!$clearanceTemplate || empty($clearanceTemplate['position_head_employee_id'])): ?>
        <button type="button" class="btn btn-secondary btn-sm" disabled title="Please configure the template and assign a Position Head first."><i class="fas fa-lock mr-1"></i> Accept (Blocked)</button>
      <?php else: ?>
      <form method="POST">
        <input type="hidden" name="action" value="assign_clearance_instance">
        <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
        <button type="submit" class="btn btn-outline-success btn-sm"><i class="fas fa-check mr-1"></i> Accept</button>
      </form>
      <?php endif; ?>
      <form method="POST" onsubmit="return confirm('Mark Department-Position Clearance as not applicable for this employee?');">
        <input type="hidden" name="action" value="decline_clearance">
        <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
        <button type="submit" class="btn btn-outline-danger btn-sm"><i class="fas fa-ban mr-1"></i> Decline</button>
      </form>
    </div>
  </div>

  <?php else: ?>
  <div class="card-box">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:10px;">
      <h5 style="margin:0;"><i class="fas fa-user-shield mr-2"></i><?php echo htmlspecialchars($exitRow['exit_number']); ?> — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
      <div>
        <?php
        $clr_dbadge_map = [
            'completed'                    => ['b-acknowledged', 'Approved & Completed'],
            'pending_position_head_review' => ['b-filled', 'Pending Position Head Review'],
            'rejected_by_position_head'    => ['b-rejected', 'Rejected by Position Head'],
            'pending_hr_approval'          => ['b-filled', 'Pending HR Approval'],
            'not_applicable'               => ['b-pending', 'Not Applicable'],
        ];
        $clr_dbadge = $clr_dbadge_map[$clearanceInstance['status']] ?? ['b-pending', 'In Progress'];
        ?>
        <span class="badge <?php echo $clr_dbadge[0]; ?>"><?php echo $clr_dbadge[1]; ?></span>
        <?php if (!in_array($clearanceInstance['status'], ['not_applicable'])): ?>
        <button type="button" class="btn btn-sm btn-outline-secondary" style="margin-left:8px;" onclick="openHistoryModal(<?php echo $exit_id; ?>)"><i class="fas fa-history mr-1"></i> History</button>
        <a href="hr-exit-handover.php?view_clearance_doc=<?php echo $exit_id; ?>" target="_blank" class="btn btn-sm btn-outline-primary" style="text-decoration:none;margin-left:8px;"><i class="fas fa-eye mr-1"></i> Preview</a>
        <?php endif; ?>
        <a href="?tab=clearance2&clearance_mode=manage" class="btn btn-sm btn-outline-primary" style="text-decoration:none;margin-left:8px;"><i class="fas fa-cog mr-1"></i> Configure</a>
      </div>
    </div>

    <?php if (!empty($clearanceInstance['position_head_token']) && !in_array($clearanceInstance['status'], ['not_applicable'])):
        $clr_ph_base = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . rtrim('/hrm', '/');
        $clr_ph_link = $clr_ph_base . '/hr-exit-handover.php?ph_review=' . intval($clearanceInstance['id']) . '&token=' . urlencode($clearanceInstance['position_head_token']);
    ?>
    <div style="display:flex;gap:8px;align-items:center;margin:14px 0;padding:10px 14px;background:#eef2ff;border:1px solid #c7d2fe;border-radius:8px;flex-wrap:wrap;">
      <i class="fas fa-link" style="color:#3730a3;"></i>
      <input type="text" readonly value="<?php echo htmlspecialchars($clr_ph_link); ?>" id="clrPhLink" style="flex:1;border:none;background:transparent;font-size:12px;color:#3730a3;min-width:200px;" onclick="this.select();">
      <button type="button" class="btn-p btn-navy" style="padding:6px 14px;font-size:11px;" onclick="copyClrPhLink()"><i class="fas fa-copy mr-1"></i> Copy Link</button>
      
      <?php if (empty($clearanceInstance['position_head_notified_at'])): ?>
        <button type="button" class="btn-p" style="background:#2563eb;color:#fff;padding:6px 14px;font-size:11px;border:none;" onclick="openNotifyModal(<?php echo $exit_id; ?>, '<?php echo htmlspecialchars(addslashes($empRow['name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['ph_email'])); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['ph_phone'])); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['position_head_token'])); ?>')"><i class="fas fa-envelope mr-1"></i> Notify Position Head</button>
      <?php else: ?>
        <span style="font-size:11px;font-weight:700;color:#065f46;background:#d1fae5;padding:6px 12px;border-radius:4px;"><i class="fas fa-check-circle mr-1"></i> Notified <?php echo date('d M, h:i A', strtotime($clearanceInstance['position_head_notified_at'])); ?></span>
        <button type="button" class="btn-p" style="background:#f1f5f9;color:#64748b;padding:6px 14px;font-size:11px;border:1px solid #cbd5e1;" onclick="openNotifyModal(<?php echo $exit_id; ?>, '<?php echo htmlspecialchars(addslashes($empRow['name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['ph_email'])); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['ph_phone'])); ?>', '<?php echo htmlspecialchars(addslashes($clearanceInstance['position_head_token'])); ?>')"><i class="fas fa-envelope mr-1"></i> Notify Again</button>
      <?php endif; ?>
    </div>
    <?php endif; ?>

    <hr style="margin:24px 0;">

    <?php if ($clearanceInstance['status'] === 'completed'): ?>
      <div class="alert alert-success">
        <i class="fas fa-check-circle mr-1"></i> Signed by employee on <?php echo date('d M Y', strtotime($clearanceInstance['employee_signed_at'])); ?>,
        by <?php echo htmlspecialchars($clearanceHeadName); ?> on <?php echo date('d M Y', strtotime($clearanceInstance['position_head_signed_at'])); ?>,
        approved by <?php echo htmlspecialchars($clearanceInstance['hr_reviewed_by']); ?> on <?php echo date('d M Y', strtotime($clearanceInstance['hr_reviewed_at'])); ?>.
      </div>
      <?php if (!empty($clearanceInstance['employee_remarks'])): ?><p style="font-size:14px;color:#475569;margin-top:10px;"><strong>Employee Remarks:</strong> <?php echo htmlspecialchars($clearanceInstance['employee_remarks']); ?></p><?php endif; ?>
      <?php if (!empty($clearanceInstance['position_head_remarks'])): ?><p style="font-size:14px;color:#475569;"><strong><?php echo htmlspecialchars($clearanceTemplateForInstance['signatory_title'] ?? 'Position Head'); ?> Remarks:</strong> <?php echo htmlspecialchars($clearanceInstance['position_head_remarks']); ?></p><?php endif; ?>
      <div style="display:flex;gap:16px;flex-wrap:wrap;">
        <?php if (!empty($clearanceInstance['employee_signature_data'])): ?><img src="<?php echo htmlspecialchars($clearanceInstance['employee_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
        <?php if (!empty($clearanceInstance['position_head_signature_data'])): ?><img src="<?php echo htmlspecialchars($clearanceInstance['position_head_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
      </div>
    <?php elseif ($clearanceInstance['status'] === 'pending_hr_approval'): ?>
      <div class="alert alert-warning"><i class="fas fa-hourglass-half mr-1"></i> Signed off by <?php echo htmlspecialchars($clearanceHeadName); ?> on <?php echo date('d M Y', strtotime($clearanceInstance['position_head_signed_at'])); ?>. Awaiting HR's final approval.</div>
      <?php if (!empty($clearanceInstance['employee_remarks'])): ?><p style="font-size:14px;color:#475569;margin-top:10px;"><strong>Employee Remarks:</strong> <?php echo htmlspecialchars($clearanceInstance['employee_remarks']); ?></p><?php endif; ?>
      <?php if (!empty($clearanceInstance['position_head_remarks'])): ?><p style="font-size:14px;color:#475569;"><strong><?php echo htmlspecialchars($clearanceTemplateForInstance['signatory_title'] ?? 'Position Head'); ?> Remarks:</strong> <?php echo htmlspecialchars($clearanceInstance['position_head_remarks']); ?></p><?php endif; ?>
      <div style="display:flex;gap:16px;flex-wrap:wrap;margin-bottom:12px;">
        <?php if (!empty($clearanceInstance['employee_signature_data'])): ?><img src="<?php echo htmlspecialchars($clearanceInstance['employee_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
        <?php if (!empty($clearanceInstance['position_head_signature_data'])): ?><img src="<?php echo htmlspecialchars($clearanceInstance['position_head_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
      </div>
      <button type="button" class="btn-p btn-green" onclick="approveClearanceHr(<?php echo $clearanceInstance['id']; ?>)"><i class="fas fa-check mr-1"></i> Approve (Final)</button>
      <button type="button" class="btn-p" style="background:#dc2626;" onclick="openRejectClrHrModal(<?php echo $clearanceInstance['id']; ?>)"><i class="fas fa-times mr-1"></i> Reject</button>
    <?php elseif ($clearanceInstance['status'] === 'pending_position_head_review'): ?>
      <div class="alert alert-warning"><i class="fas fa-hourglass-half mr-1"></i> Signed by the employee on <?php echo date('d M Y', strtotime($clearanceInstance['employee_signed_at'])); ?>. Awaiting sign-off from <strong><?php echo htmlspecialchars($clearanceHeadName ?: 'the Position Head'); ?></strong> (<?php echo htmlspecialchars($clearanceTemplateForInstance['signatory_title'] ?? 'Position Head'); ?>).</div>
      <?php if (!empty($clearanceInstance['employee_signature_data'])): ?><img src="<?php echo htmlspecialchars($clearanceInstance['employee_signature_data']); ?>" style="max-height:90px;border:1px solid #e2e8f0;border-radius:8px;display:block;margin-bottom:12px;"><?php endif; ?>
      <h6 style="font-weight:800;color:var(--navy);"><?php echo htmlspecialchars($clearanceTemplateForInstance['signatory_title'] ?? 'Position Head'); ?> Sign-Off</h6>
      <div class="fg"><label class="fl">Remarks (optional)</label><textarea id="clrHeadRemarks" class="fc" rows="2"></textarea></div>
      <div style="border:2px dashed #a78bfa;border-radius:10px;background:#faf5ff;padding:12px;max-width:500px;">
        <canvas id="clrHeadSigCanvas" width="460" height="150" style="width:100%;height:150px;border:1px solid #ddd6fe;border-radius:8px;background:#fff;cursor:crosshair;touch-action:none;display:block;"></canvas>
        <div style="margin-top:8px;display:flex;gap:8px;">
          <button type="button" class="btn-p" style="background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;" onclick="clearClrHeadSig()">Clear</button>
          <button type="button" class="btn-p btn-green" onclick="approveClearancePositionHead(<?php echo $clearanceInstance['id']; ?>)">Sign &amp; Approve</button>
          <button type="button" class="btn-p" style="background:#dc2626;" onclick="openRejectClrPHModal(<?php echo $clearanceInstance['id']; ?>)">Reject</button>
        </div>
      </div>
    <?php endif; ?>

    <?php if ($clearanceInstance['status'] === 'rejected_by_position_head'): ?>
    <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 16px;font-size:12.5px;color:#991b1b;margin:16px 0;">
      <strong>Rejected by <?php echo htmlspecialchars($clearanceHeadName ?: 'the Position Head'); ?></strong><br>
      Reason: <?php echo htmlspecialchars($clearanceInstance['position_head_rejection_reason']); ?><br>
      The employee needs to review, update, and re-sign via their exit link.
    </div>
    <?php endif; ?>
    <?php if ($clearanceInstance['status'] === 'in_progress' && !empty($clearanceInstance['hr_rejection_reason'])): ?>
    <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 16px;font-size:12.5px;color:#991b1b;margin:16px 0;">
      <strong>Sent back by HR</strong> (<?php echo htmlspecialchars($clearanceInstance['hr_reviewed_by']); ?>)<br>
      Reason: <?php echo htmlspecialchars($clearanceInstance['hr_rejection_reason']); ?><br>
      Both signatures were cleared — this must be re-signed by the employee and re-reviewed by the Position Head.
    </div>
    <?php endif; ?>

    <div style="display:flex;flex-wrap:wrap;gap:16px;margin:16px 0;padding:14px 16px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;font-size:12.5px;">
      <div><strong>Employee ID:</strong> <?php echo htmlspecialchars($empRow['employee_id'] ?? '—'); ?></div>
      <div><strong>Department:</strong> <?php echo htmlspecialchars($empRow['department'] ?? '—'); ?></div>
      <div><strong>Designation:</strong> <?php echo htmlspecialchars($empRow['position'] ?? '—'); ?></div>
      <div><strong><?php echo htmlspecialchars($clearanceTemplateForInstance['signatory_title'] ?? 'Position Head'); ?>:</strong> <?php echo htmlspecialchars($clearanceHeadName ?: '—'); ?></div>
    </div>

    <?php if ($clearanceInstance['status'] === 'not_applicable'): ?>
    <div style="text-align:center;color:#94a3b8;padding:30px;">Department-Position Clearance was marked as not applicable for this employee — there is nothing to fill in or review.</div>
    <?php else: ?>

    <?php $clr_readonly = !in_array($clearanceInstance['status'], ['in_progress','rejected_by_position_head']); ?>

    <?php foreach ($clearanceGrouped as $cg_name => $cg_data): ?>
    <div style="font-weight:800;color:var(--navy);font-size:14px;margin:20px 0 10px;padding-bottom:6px;border-bottom:2px solid #eef2ff;"><?php echo htmlspecialchars($cg_name); ?></div>
    <div style="overflow-x:auto;">
      <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
        <colgroup>
          <col style="width:5%;"><col style="width:45%;"><col style="width:10%;"><col style="width:10%;"><col style="width:10%;"><col style="width:20%;">
        </colgroup>
        <thead><tr><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; text-align:center;">Sl. No.</th><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Clearance Item</th><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; text-align:center;">Yes</th><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; text-align:center;">No</th><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; text-align:center;">N/A</th><th style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Remarks</th></tr></thead>
        <tbody>
        <?php foreach ($cg_data['items'] as $cidx => $it2): ?>
        <tr style="background:<?php echo $cidx%2==1?'#f8faff':'#fff'; ?>;">
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; text-align:center;"><?php echo $cidx+1; ?></td>
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; overflow-wrap:break-word; word-break:break-word;"><?php echo htmlspecialchars($it2['item_text']); ?></td>
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669;"><?php echo $it2['response']==='yes' ? '&#10003;' : ''; ?></td>
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669;"><?php echo $it2['response']==='no' ? '&#10003;' : ''; ?></td>
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669;"><?php echo $it2['response']==='na' ? '&#10003;' : ''; ?></td>
          <td style="box-sizing:border-box; border:1px solid #cbd5e1; padding:8px 10px; overflow-wrap:break-word; word-break:break-word;"><?php echo htmlspecialchars($it2['remarks'] ?? ''); ?></td>
        </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endforeach; ?>

    <?php if (empty($clearanceGrouped)): ?>
    <div style="text-align:center;color:#94a3b8;padding:20px;">No checklist items configured — set them up under "Manage Clearance Template".</div>
    <?php endif; ?>


    <?php endif; ?>
  </div>
  <?php endif; ?>

<?php endif; ?>

<?php else: ?>

<?php if (!$exit_id): ?>
<div class="card-box">
  <h5><i class="fas fa-user-clock mr-2"></i>Exits Awaiting Handover Assignment</h5>
  <table><thead><tr><th>Exit #</th><th>Employee</th><th>Last Working Day</th><th>Action</th></tr></thead><tbody>
  <?php foreach ($pendingExits as $p): ?>
  <tr>
    <td><?php echo htmlspecialchars($p['exit_number']); ?></td>
    <td><?php echo htmlspecialchars($p['employee_name']); ?></td>
    <td><?php echo $p['final_last_working_day'] ? date('d M Y', strtotime($p['final_last_working_day'])) : '—'; ?></td>
    <td><a href="?exit_id=<?php echo $p['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;">Assign Handover</a></td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($pendingExits)): ?><tr><td colspan="4" style="text-align:center;color:#94a3b8;padding:30px;">No exits awaiting handover.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<?php elseif (!$instance): ?>
<div class="card-box">
  <h5><i class="fas fa-user-check mr-2"></i>Nominate Receiver — <?php echo htmlspecialchars($exitRow['exit_number']); ?> (<?php echo htmlspecialchars($empRow['name'] ?? ''); ?>)</h5>
  <form method="POST">
    <input type="hidden" name="action" value="assign_handover">
    <input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
    <div class="fg"><label class="fl">Supervisor / Successor Receiving the Handover</label>
      <select name="nominated_to_id" class="fc" required>
        <option value="">-- Select --</option>
        <?php foreach ($employees as $e): if ($e['id']==$exitRow['employee_id']) continue; ?>
        <option value="<?php echo $e['id']; ?>"><?php echo htmlspecialchars($e['name'].' — '.($e['position']??'')); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <button type="submit" class="btn-p btn-navy"><i class="fas fa-check mr-1"></i> Assign & Generate Checklist</button>
  </form>
</div>

<?php else: ?>
<div class="card-box">
  <h5><i class="fas fa-clipboard-list mr-2"></i><?php echo htmlspecialchars($exitRow['exit_number']); ?> — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
  <p style="font-size:13px;color:#64748b;">Receiving supervisor: <strong><?php echo htmlspecialchars($instance['nominated_name'] ?? ''); ?></strong></p>
  <div style="margin-bottom:14px;">
    <div style="display:flex;justify-content:space-between;font-size:12px;font-weight:700;color:var(--navy);margin-bottom:5px;"><span><?php echo $ack_items; ?> of <?php echo $total_items; ?> items acknowledged</span><span><?php echo $pct; ?>%</span></div>
    <div class="progress-track"><div class="progress-fill" style="width:<?php echo $pct; ?>%;"></div></div>
  </div>

  <?php foreach ($items as $it): ?>
  <div class="item-card <?php echo $it['status']; ?>">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;">
      <div>
        <strong><?php echo htmlspecialchars($it['item_title']); ?></strong>
        <?php if ($it['description']): ?><div style="font-size:12px;color:#64748b;"><?php echo htmlspecialchars($it['description']); ?></div><?php endif; ?>
        <?php if ($it['employee_notes']): ?><div style="font-size:12px;margin-top:6px;background:#f8fafc;padding:8px;border-radius:6px;"><strong>Notes:</strong> <?php echo nl2br(htmlspecialchars($it['employee_notes'])); ?></div><?php endif; ?>
      </div>
      <span class="badge b-<?php echo $it['status']; ?>"><?php echo ucfirst($it['status']); ?></span>
    </div>

    <?php if ($it['status']=='pending'): ?>
    <form method="POST" class="mt-2">
      <input type="hidden" name="action" value="fill_item"><input type="hidden" name="item_id" value="<?php echo $it['id']; ?>"><input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
      <textarea name="employee_notes" class="fc" style="height:60px;" placeholder="Describe current status / pending details..." required></textarea>
      <button type="submit" class="btn-p btn-navy mt-2" style="padding:6px 14px;font-size:11px;">Submit Details</button>
    </form>
    <?php elseif ($it['status']=='filled'): ?>
    <form method="POST" class="mt-2">
      <input type="hidden" name="action" value="acknowledge_item"><input type="hidden" name="item_id" value="<?php echo $it['id']; ?>"><input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
      <button type="submit" class="btn-p btn-green" style="padding:6px 14px;font-size:11px;"><i class="fas fa-check mr-1"></i> Acknowledge Receipt</button>
    </form>
    <?php endif; ?>
  </div>
  <?php endforeach; ?>
  <?php if (empty($items)): ?>
  <div style="text-align:center;color:#94a3b8;padding:20px;">No template items configured for this role yet — set them up under "Template Setup".</div>
  <?php endif; ?>

  <?php if ($pct == 100 && $total_items > 0): ?>
  <div class="alert alert-success mt-3"><i class="fas fa-check-circle mr-1"></i> Handover complete. <a href="hr-exit-clearance.php?exit_id=<?php echo $exit_id; ?>">Proceed to Department Clearance →</a></div>
  <?php endif; ?>
</div>
<?php endif; ?>
<?php endif; ?>

</div>

<!-- Add Asset Section Modal -->
<div class="modal fade" id="addAssetHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="add_asset_heading">
        <input type="hidden" name="department_id" value="<?php echo $asset_dept_id; ?>">
        <div class="modal-header"><h5 class="modal-title">Add Checklist Section</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Section Name</label><input type="text" name="heading_name" class="fc" required placeholder="e.g. Asset Return Checklist"></div>
          <div class="fg"><label style="display:flex;align-items:center;gap:8px;font-size:12px;font-weight:700;color:var(--navy);"><input type="checkbox" name="show_condition_field" style="width:16px;height:16px;"> Include a "Condition" column (for physical assets)</label></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Save Section</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Edit Asset Section Modal -->
<div class="modal fade" id="editAssetHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="edit_asset_heading">
        <input type="hidden" name="id" id="edit_asset_heading_id">
        <div class="modal-header"><h5 class="modal-title">Edit Section</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Section Name</label><input type="text" name="heading_name" id="edit_asset_heading_name" class="fc" required></div>
          <div class="fg"><label style="display:flex;align-items:center;gap:8px;font-size:12px;font-weight:700;color:var(--navy);"><input type="checkbox" name="show_condition_field" id="edit_asset_show_condition" style="width:16px;height:16px;"> Include a "Condition" column</label></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Update</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Add Asset Item Modal -->
<div class="modal fade" id="addAssetItemModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="add_asset_item">
        <input type="hidden" name="heading_id" id="add_asset_item_heading_id">
        <div class="modal-header"><h5 class="modal-title">Add Item to "<span id="add_asset_item_heading_label"></span>"</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Item Text</label><input type="text" name="item_text" class="fc" required></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Save Item</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Edit Asset Item Modal -->
<div class="modal fade" id="editAssetItemModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="edit_asset_item">
        <input type="hidden" name="id" id="edit_asset_item_id">
        <div class="modal-header"><h5 class="modal-title">Edit Item</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Item Text</label><input type="text" name="item_text" id="edit_asset_item_text" class="fc" required></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Update</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Asset Confirmation Overlays -->
<div id="ahConfirmOverlay" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.6);z-index:9999;align-items:center;justify-content:center;">
    <div style="background:#fff;width:400px;border-radius:16px;padding:30px;text-align:center;box-shadow:0 10px 25px rgba(0,0,0,0.2);">
        <div style="width:60px;height:60px;border-radius:50%;background:#d1fae5;color:#059669;display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 15px;"><i class="fas fa-check"></i></div>
        <h5 style="font-weight:800;color:var(--navy);margin-bottom:10px;">Approve Asset Handover</h5>
        <p style="color:#475569;font-size:14px;margin-bottom:24px;">Are you sure you want to approve this checklist? This will file it in the employee's documents.</p>
        <input type="hidden" id="ahConfirmInstanceId">
        <div style="display:flex;gap:12px;width:100%;">
            <button type="button" class="btn-p btn-outline" style="flex:1;" onclick="document.getElementById('ahConfirmOverlay').style.display='none'">Cancel</button>
            <button type="button" class="btn-p btn-green" style="flex:1;" onclick="submitApproveAsset()">Yes, Approve</button>
        </div>
    </div>
</div>

<div id="ahRejectOverlay" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.6);z-index:9999;align-items:center;justify-content:center;">
    <div style="background:#fff;width:400px;border-radius:16px;padding:30px;text-align:center;box-shadow:0 10px 25px rgba(0,0,0,0.2);">
        <div style="width:60px;height:60px;border-radius:50%;background:#fee2e2;color:#dc2626;display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 15px;"><i class="fas fa-times"></i></div>
        <h5 style="font-weight:800;color:var(--navy);margin-bottom:10px;">Reject Asset Handover</h5>
        <p style="color:#475569;font-size:13px;margin-bottom:16px;">Please provide a reason. This will be sent back to the employee.</p>
        <input type="hidden" id="ahRejectInstanceId">
        <textarea id="ahRejectReason" class="fc" rows="3" placeholder="Reason for rejection..." style="margin-bottom:20px;"></textarea>
        <div style="display:flex;gap:12px;width:100%;">
            <button type="button" class="btn-p btn-outline" style="flex:1;" onclick="document.getElementById('ahRejectOverlay').style.display='none'">Cancel</button>
            <button type="button" class="btn-p" style="flex:1;background:#dc2626;" onclick="submitRejectAsset()">Reject & Notify</button>
        </div>
    </div>
</div>

<!-- Add Clearance Section Modal -->
<div class="modal fade" id="addClrHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="add_clearance_heading">
        <input type="hidden" name="template_id" value="<?php echo $clearanceTemplate['id'] ?? ''; ?>">
        <div class="modal-header"><h5 class="modal-title">Add Checklist Section</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Section Name</label><input type="text" name="heading_name" class="fc" required placeholder="e.g. Shipment &amp; Records Handover"></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Save Section</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Edit Clearance Section Modal -->
<div class="modal fade" id="editClrHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="edit_clearance_heading">
        <input type="hidden" name="id" id="edit_clr_heading_id">
        <div class="modal-header"><h5 class="modal-title">Edit Section</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Section Name</label><input type="text" name="heading_name" id="edit_clr_heading_name" class="fc" required></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Update</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Add Clearance Item Modal -->
<div class="modal fade" id="addClrItemModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="add_clearance_item">
        <input type="hidden" name="heading_id" id="add_clr_item_heading_id">
        <div class="modal-header"><h5 class="modal-title">Add Item to "<span id="add_clr_item_heading_label"></span>"</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Clearance Item</label><input type="text" name="item_text" class="fc" required></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Save Item</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Edit Clearance Item Modal -->
<div class="modal fade" id="editClrItemModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <form method="POST">
        <input type="hidden" name="action" value="edit_clearance_item">
        <input type="hidden" name="id" id="edit_clr_item_id">
        <div class="modal-header"><h5 class="modal-title">Edit Item</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
          <div class="fg"><label class="fl">Clearance Item</label><input type="text" name="item_text" id="edit_clr_item_text" class="fc" required></div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="submit" class="btn-p btn-navy">Update</button></div>
      </form>
    </div>
  </div>
</div>

<!-- Reject (Position Head) Modal -->
<div class="modal fade" id="rejectClrPHModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <div class="modal-header"><h5 class="modal-title">Reject Clearance</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <input type="hidden" id="rejectClrPHInstanceId">
        <div class="fg"><label class="fl">Reason for Rejection</label><textarea id="rejectClrPHReason" class="fc" rows="4" placeholder="e.g. Item 5 is missing details, please recheck with the employee."></textarea></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="button" class="btn-p" style="background:#dc2626;" onclick="submitRejectClrPH()">Reject &amp; Notify Employee</button></div>
    </div>
  </div>
</div>

<!-- Reject (HR Final) Modal -->
<div class="modal fade" id="rejectClrHrModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <div class="modal-header"><h5 class="modal-title">Reject Clearance (Final)</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <input type="hidden" id="rejectClrHrInstanceId">
        <p style="font-size:12.5px;color:#64748b;">This clears both the employee's and the Position Head's signatures — it must be re-signed and re-reviewed from scratch.</p>
        <div class="fg"><label class="fl">Reason for Rejection</label><textarea id="rejectClrHrReason" class="fc" rows="4"></textarea></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button><button type="button" class="btn-p" style="background:#dc2626;" onclick="submitRejectClrHr()">Reject &amp; Notify Employee</button></div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function showTplTab(which) {
    var sections = document.getElementById('tplPanel_sections');
    var preview = document.getElementById('tplPanel_preview');
    var btnSections = document.getElementById('tplTabBtn_sections');
    var btnPreview = document.getElementById('tplTabBtn_preview');
    if (!sections || !preview) return;
    if (which === 'preview') {
        sections.style.display = 'none'; preview.style.display = 'block';
        btnSections.classList.remove('active'); btnPreview.classList.add('active');
    } else {
        sections.style.display = 'block'; preview.style.display = 'none';
        btnPreview.classList.remove('active'); btnSections.classList.add('active');
    }
}

function editAssetHeading(h) {
    document.getElementById('edit_asset_heading_id').value = h.id;
    document.getElementById('edit_asset_heading_name').value = h.heading_name;
    document.getElementById('edit_asset_show_condition').checked = (h.show_condition_field == 1);
    $('#editAssetHeadingModal').modal('show');
}
function openAddAssetItemModal(headingId, headingName) {
    document.getElementById('add_asset_item_heading_id').value = headingId;
    document.getElementById('add_asset_item_heading_label').textContent = headingName;
    $('#addAssetItemModal').modal('show');
}
function editAssetItem(item) {
    document.getElementById('edit_asset_item_id').value = item.id;
    document.getElementById('edit_asset_item_text').value = item.item_text;
    $('#editAssetItemModal').modal('show');
}

function toggleAssetItem(id, checked) {
    $.post('', { ajax_action: 'toggle_asset_item', run_item_id: id, checked: checked ? 1 : 0 });
}
function saveAssetDetail(id) {
    var condEl = document.getElementById('cond_' + id);
    var remEl = document.getElementById('rem_' + id);
    $.post('', { ajax_action: 'save_asset_item_detail', run_item_id: id, condition_text: condEl ? condEl.value : '', remarks: remEl ? remEl.value : '' });
}
function addAssetCustomRow(instanceId, headingId) {
    var inputEl = document.getElementById('newRowText_' + headingId);
    var text = inputEl.value.trim();
    if (!text) { alert('Enter an item description first.'); return; }
    $.post('', { ajax_action: 'add_asset_custom_row', instance_id: instanceId, heading_id: headingId, item_text: text }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to add row.'); }
    }, 'json');
}
function removeAssetCustomRow(id) {
    if (!confirm('Remove this row?')) return;
    $.post('', { ajax_action: 'remove_asset_custom_row', run_item_id: id }, function(resp) {
        if (resp.success) { var row = document.getElementById('assetRow_' + id); if (row) row.remove(); }
    }, 'json');
}

var assetSigCanvas = document.getElementById('assetSigCanvas');
var assetSigCtx = null;
var assetSigDrawing = false;
if (assetSigCanvas) {
    assetSigCanvas.width = assetSigCanvas.offsetWidth;
    assetSigCanvas.height = assetSigCanvas.offsetHeight;
    assetSigCtx = assetSigCanvas.getContext('2d');
    assetSigCtx.strokeStyle = '#1a3fc4'; assetSigCtx.lineWidth = 2; assetSigCtx.lineCap = 'round';
    var assetSigPos = function(e) {
        var r = assetSigCanvas.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    assetSigCanvas.addEventListener('mousedown', function(e){ assetSigDrawing = true; var p = assetSigPos(e); assetSigCtx.beginPath(); assetSigCtx.moveTo(p.x, p.y); });
    assetSigCanvas.addEventListener('mousemove', function(e){ if (!assetSigDrawing) return; var p = assetSigPos(e); assetSigCtx.lineTo(p.x, p.y); assetSigCtx.stroke(); });
    assetSigCanvas.addEventListener('mouseup', function(){ assetSigDrawing = false; });
    assetSigCanvas.addEventListener('mouseleave', function(){ assetSigDrawing = false; });
    assetSigCanvas.addEventListener('touchstart', function(e){ e.preventDefault(); assetSigDrawing = true; var p = assetSigPos(e); assetSigCtx.beginPath(); assetSigCtx.moveTo(p.x, p.y); }, {passive:false});
    assetSigCanvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!assetSigDrawing) return; var p = assetSigPos(e); assetSigCtx.lineTo(p.x, p.y); assetSigCtx.stroke(); }, {passive:false});
    assetSigCanvas.addEventListener('touchend', function(e){ e.preventDefault(); assetSigDrawing = false; }, {passive:false});
}
function clearAssetSig() {
    if (!assetSigCanvas || !assetSigCtx) return;
    assetSigCtx.clearRect(0, 0, assetSigCanvas.width, assetSigCanvas.height);
}
function finalizeAssetSignature(instanceId) {
    if (!assetSigCanvas) return;
    var blank = document.createElement('canvas');
    blank.width = assetSigCanvas.width; blank.height = assetSigCanvas.height;
    if (assetSigCanvas.toDataURL() === blank.toDataURL()) { alert('Please draw your signature first.'); return; }
    if (!confirm('Finalize and sign this checklist? You will not be able to edit it after signing.')) return;
    var dataUrl = assetSigCanvas.toDataURL('image/png');
    $.post('', { ajax_action: 'save_asset_signature', instance_id: instanceId, signature_data: dataUrl }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to save signature.'); }
    }, 'json');
}

function approveAssetHandover(instanceId) {
    document.getElementById('ahConfirmInstanceId').value = instanceId;
    document.getElementById('ahConfirmOverlay').style.display = 'flex';
}
function submitApproveAsset() {
    var instanceId = document.getElementById('ahConfirmInstanceId').value;
    document.getElementById('ahConfirmOverlay').style.display = 'none';
    $.post('', { ajax_action: 'approve_asset_handover', instance_id: instanceId }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Could not approve. Please try again.'); }
    }, 'json');
}
function openRejectAssetModal(instanceId) {
    document.getElementById('ahRejectInstanceId').value = instanceId;
    document.getElementById('ahRejectReason').value = '';
    document.getElementById('ahRejectOverlay').style.display = 'flex';
}
function submitRejectAsset() {
    var instanceId = document.getElementById('ahRejectInstanceId').value;
    var reason = document.getElementById('ahRejectReason').value.trim();
    if (!reason) { alert('Please provide a reason for rejection.'); return; }
    document.getElementById('ahRejectOverlay').style.display = 'none';
    $.post('', { ajax_action: 'reject_asset_handover', instance_id: instanceId, reason: reason }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Could not reject. Please try again.'); }
    }, 'json');
}

/* ===== Department-Position Clearance ===== */

function showClrTplTab(which) {
    var sections = document.getElementById('clrTplPanel_sections');
    var preview = document.getElementById('clrTplPanel_preview');
    var btnSections = document.getElementById('clrTabBtn_sections');
    var btnPreview = document.getElementById('clrTabBtn_preview');
    if (!sections || !preview) return;
    if (which === 'preview') {
        sections.style.display = 'none'; preview.style.display = 'block';
        btnSections.classList.remove('active'); btnPreview.classList.add('active');
    } else {
        sections.style.display = 'block'; preview.style.display = 'none';
        btnPreview.classList.remove('active'); btnSections.classList.add('active');
    }
}
function editClrHeading(h) {
    document.getElementById('edit_clr_heading_id').value = h.id;
    document.getElementById('edit_clr_heading_name').value = h.heading_name;
    $('#editClrHeadingModal').modal('show');
}
function openAddClrItemModal(headingId, headingName) {
    document.getElementById('add_clr_item_heading_id').value = headingId;
    document.getElementById('add_clr_item_heading_label').textContent = headingName;
    $('#addClrItemModal').modal('show');
}
function editClrItem(item) {
    document.getElementById('edit_clr_item_id').value = item.id;
    document.getElementById('edit_clr_item_text').value = item.item_text;
    $('#editClrItemModal').modal('show');
}

function setClearanceResponse(id, response) {
    $.post('', { ajax_action: 'set_clearance_response', run_item_id: id, response: response });
}
function saveClearanceItemRemarks(id, remarks) {
    $.post('', { ajax_action: 'save_clearance_item_remarks', run_item_id: id, remarks: remarks });
}

function setupSigPad(canvasId) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return null;
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    var ctx = canvas.getContext('2d');
    ctx.strokeStyle = '#1a3fc4'; ctx.lineWidth = 2; ctx.lineCap = 'round';
    var drawing = false;
    var pos = function(e) {
        var r = canvas.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    canvas.addEventListener('mousedown', function(e){ drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); });
    canvas.addEventListener('mousemove', function(e){ if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); });
    canvas.addEventListener('mouseup', function(){ drawing = false; });
    canvas.addEventListener('mouseleave', function(){ drawing = false; });
    canvas.addEventListener('touchstart', function(e){ e.preventDefault(); drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); }, {passive:false});
    canvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); }, {passive:false});
    canvas.addEventListener('touchend', function(e){ e.preventDefault(); drawing = false; }, {passive:false});
    return { canvas: canvas, ctx: ctx };
}
function isSigPadBlank(canvas) {
    var blank = document.createElement('canvas');
    blank.width = canvas.width; blank.height = canvas.height;
    return canvas.toDataURL() === blank.toDataURL();
}

var clrEmpSigPad = setupSigPad('clrEmpSigCanvas');
var clrHeadSigPad = setupSigPad('clrHeadSigCanvas');

function clearClrEmpSig() {
    if (!clrEmpSigPad) return;
    clrEmpSigPad.ctx.clearRect(0, 0, clrEmpSigPad.canvas.width, clrEmpSigPad.canvas.height);
}
function clearClrHeadSig() {
    if (!clrHeadSigPad) return;
    clrHeadSigPad.ctx.clearRect(0, 0, clrHeadSigPad.canvas.width, clrHeadSigPad.canvas.height);
}

function copyClrPhLink() {
    var el = document.getElementById('clrPhLink');
    el.select(); el.setSelectionRange(0, 99999);
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(el.value).then(function(){ alert('Link copied.'); }).catch(function(){ document.execCommand('copy'); alert('Link copied.'); });
    } else {
        document.execCommand('copy'); alert('Link copied.');
    }
}

function saveClearanceEmployeeSignature(instanceId) {
    if (!clrEmpSigPad || isSigPadBlank(clrEmpSigPad.canvas)) { alert('Please draw the employee\'s signature first.'); return; }
    if (!confirm('Submit for Position Head review? The checklist will lock until reviewed.')) return;
    var dataUrl = clrEmpSigPad.canvas.toDataURL('image/png');
    $.post('', { ajax_action: 'save_clearance_employee_signature', instance_id: instanceId, signature_data: dataUrl }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to save signature.'); }
    }, 'json');
}

function approveClearancePositionHead(instanceId) {
    if (!clrHeadSigPad || isSigPadBlank(clrHeadSigPad.canvas)) { alert('Please draw your signature first.'); return; }
    if (!confirm('Sign and approve? This moves the checklist to HR for final approval.')) return;
    var dataUrl = clrHeadSigPad.canvas.toDataURL('image/png');
    var remarks = document.getElementById('clrHeadRemarks') ? document.getElementById('clrHeadRemarks').value : '';
    $.post('', { ajax_action: 'approve_clearance_position_head', instance_id: instanceId, signature_data: dataUrl, remarks: remarks }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Could not approve. Please try again.'); }
    }, 'json');
}
function openRejectClrPHModal(instanceId) {
    document.getElementById('rejectClrPHInstanceId').value = instanceId;
    document.getElementById('rejectClrPHReason').value = '';
    $('#rejectClrPHModal').modal('show');
}
function submitRejectClrPH() {
    var instanceId = document.getElementById('rejectClrPHInstanceId').value;
    var reason = document.getElementById('rejectClrPHReason').value.trim();
    if (!reason) { alert('Please provide a reason for rejection.'); return; }
    $.post('', { ajax_action: 'reject_clearance_position_head', instance_id: instanceId, reason: reason }, function(resp) {
        if (resp.success) { $('#rejectClrPHModal').modal('hide'); location.reload(); } else { alert(resp.message || 'Could not reject. Please try again.'); }
    }, 'json');
}

function approveClearanceHr(instanceId) {
    if (!confirm('Approve clearance and advance candidate to the Interview & Settlement phase? This will file the document and advance the exit process.')) return;
    $.post('', { ajax_action: 'approve_clearance_hr', instance_id: instanceId }, function(resp) {
        if (resp.success) { location.reload(); } else { alert(resp.message || 'Could not approve. Please try again.'); }
    }, 'json');
}
function openRejectClrHrModal(instanceId) {
    document.getElementById('rejectClrHrInstanceId').value = instanceId;
    document.getElementById('rejectClrHrReason').value = '';
    $('#rejectClrHrModal').modal('show');
}
function submitRejectClrHr() {
    var instanceId = document.getElementById('rejectClrHrInstanceId').value;
    var reason = document.getElementById('rejectClrHrReason').value.trim();
    if (!reason) { alert('Please provide a reason for rejection.'); return; }
    $.post('', { ajax_action: 'reject_clearance_hr', instance_id: instanceId, reason: reason }, function(resp) {
        if (resp.success) { $('#rejectClrHrModal').modal('hide'); location.reload(); } else { alert(resp.message || 'Could not reject. Please try again.'); }
    }, 'json');
}
</script>
<?php if (isset($_GET['auto_preview']) && $_GET['auto_preview'] == 1): ?>
<script>
  $(document).ready(function() {
      if (typeof showClrTplTab === 'function') {
          showClrTplTab('preview');
      }
  });
</script>
<?php endif; ?>
<?php
} catch (\Throwable $e) {
    echo "<div style='padding:20px;color:#991b1b;background:#fee2e2;border:1px solid #fecaca;margin:20px;font-family:sans-serif;border-radius:8px;'>";
    echo "<h3 style='margin-top:0;'>Fatal Error Details</h3>";
    echo "<strong>Error:</strong> " . htmlspecialchars($e->getMessage()) . "<br><br>";
    echo "<strong>File:</strong> " . htmlspecialchars($e->getFile()) . "<br>";
    echo "<strong>Line:</strong> " . $e->getLine() . "<br><br>";
    echo "<strong>Trace:</strong><br><pre>" . htmlspecialchars($e->getTraceAsString()) . "</pre>";
    echo "</div>";
}
?>
<!-- New Configuration Modal -->
<div class="modal fade" id="newConfigModal" tabindex="-1" role="dialog">
  <div class="modal-dialog modal-dialog-centered" role="document" style="max-width:500px;">
    <div class="modal-content" style="border-radius:12px;overflow:hidden;border:none;box-shadow:0 10px 25px rgba(0,0,0,0.1);">
      <form method="GET">
        <input type="hidden" name="tab" value="clearance2">
        <input type="hidden" name="clearance_mode" value="manage">
        <div class="modal-header" style="background:var(--navy);color:#fff;border-bottom:none;padding:16px 20px;">
          <h5 class="modal-title" style="font-weight:800;"><i class="fas fa-plus mr-2"></i>New Configuration</h5>
          <button type="button" class="close" data-dismiss="modal" style="color:#fff;opacity:0.8;text-shadow:none;"><span>&times;</span></button>
        </div>
        <div class="modal-body" style="padding:24px;">
          <p style="color:#64748b;font-size:13px;margin-bottom:20px;">Select a department and position to start configuring a clearance template.</p>
          <div class="fg">
            <label class="fl" style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;">DEPARTMENT</label>
            <select name="clr_department_id" id="modal_dept" class="fc" onchange="updateModalPositions()" required>
              <option value="">-- Select Department --</option>
              <?php foreach ($departments as $d): ?>
              <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="fg">
            <label class="fl" style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;">POSITION</label>
            <select name="clr_position_id" id="modal_pos" class="fc" required>
              <option value="">-- Select Position --</option>
              <!-- Populated by JS -->
            </select>
          </div>
        </div>
        <div class="modal-footer" style="border-top:1px solid #e2e8f0;background:#f8fafc;padding:12px 20px;">
          <button type="button" class="btn-p" data-dismiss="modal" style="background:#64748b;font-size:13px;padding:8px 16px;border:none;color:#fff;">Cancel</button>
          <button type="submit" class="btn-p btn-navy" style="background:#2563eb;font-size:13px;padding:8px 16px;border:none;color:#fff;">Proceed &rarr;</button>
        </div>
      </form>
    </div>
  </div>
</div>

<?php
$allPosQ = mysqli_query($con, "SELECT id, title, department_id FROM hr_positions ORDER BY title ASC");
$allPos = [];
if ($allPosQ) {
  while ($row = mysqli_fetch_assoc($allPosQ)) $allPos[] = $row;
}
?>
<script>
  var allPositions = <?php echo json_encode($allPos); ?>;
  function updateModalPositions() {
    var deptId = document.getElementById('modal_dept').value;
    var posSelect = document.getElementById('modal_pos');
    posSelect.innerHTML = '<option value="">-- Select Position --</option>';
    if(deptId) {
      allPositions.forEach(function(p) {
        if(p.department_id == deptId) {
          var opt = document.createElement('option');
          opt.value = p.id;
          opt.textContent = p.title;
          posSelect.appendChild(opt);
        }
      });
    }
  }
</script>

<!-- Position Head Notify Modal -->
<div class="modal fade" id="notifyPHModal" tabindex="-1" role="dialog" style="z-index:99999;">
  <div class="modal-dialog modal-lg"><div class="modal-content" style="border-radius:12px;overflow:hidden;border:none;box-shadow:0 10px 25px rgba(0,0,0,0.1);">
    <div class="modal-header" style="background:#f8faff;border-bottom:1px solid #e0e7ff;padding:16px 20px;">
      <h5 class="modal-title" style="font-weight:800;color:var(--navy);"><i class="fas fa-paper-plane mr-2 text-primary" style="color:#6366f1;"></i>Notify Position Head</h5>
      <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px;">
      <input type="hidden" id="rn_exit_id">

      <!-- Email Section -->
      <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
        <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
        <div class="fg"><label class="fl" style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;">To</label><input type="email" id="rn_email_to" class="fc"></div>
        <div class="fg"><label class="fl" style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;">Subject</label><input type="text" id="rn_email_subj" class="fc"></div>
        <div class="fg"><label class="fl" style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;">Message</label><textarea id="rn_email_body" class="fc" style="height:140px;resize:vertical;"></textarea></div>
        <button type="button" onclick="sendPhNotifyEmail(event)" class="btn-p btn-navy" style="background:#2563eb;font-size:13px;padding:8px 16px;border:none;color:#fff;"><i class="fas fa-paper-plane mr-1"></i> Send Email Now</button>
      </div>

      <!-- WhatsApp Section -->
      <div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;margin-bottom:16px;" id="rn_wa_container">
        <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
        <div style="margin-bottom:10px;">
          <label style="font-size:11px;font-weight:800;text-transform:uppercase;color:#065f46;display:block;margin-bottom:4px;">Phone Number</label>
          <input type="text" id="rn_phone_display" class="fc" style="width:100%;" placeholder="+91XXXXXXXXXX">
        </div>
        <textarea id="rn_wa_msg" class="fc" style="height:100px;resize:vertical;"></textarea>
        <div style="margin-top:10px;">
          <button type="button" onclick="openPhWhatsApp()" class="btn-p" style="background:#25d366;color:#fff;border:none;padding:8px 16px;font-size:13px;"><i class="fab fa-whatsapp mr-1"></i> Open WhatsApp</button>
        </div>
      </div>
      
    </div>
  </div></div>
</div>

<script>
function openNotifyModal(exitId, empName, phEmail, phPhone, phToken) {
    document.getElementById('rn_exit_id').value = exitId;
    
    var link = document.getElementById('clrPhLink') ? document.getElementById('clrPhLink').value : '';
    if (!link && phToken) {
        var base = window.location.origin + window.location.pathname.replace('hr-exit-handover.php', '');
        link = base + 'hr-exit-handover.php?ph_review=' + exitId + '&token=' + phToken;
    }
    
    empName = empName || 'the employee';
    var defaultSubj = "Action Required: Employee Clearance Request";
    var defaultBody = "Hello,\n\nPlease review and complete the exit clearance checklist for " + empName + ".\n\nYou can access the checklist and provide your digital signature using the link below:\n\n" + link + "\n\nProcedure & Responsibilities:\n1. Open the secure link to view the clearance checklist tailored for your department.\n2. Review each item carefully. Verify the return of assets, handover of documents, and completion of knowledge transfer.\n3. Mark each item as Yes, No, or N/A. You may add specific remarks for any discrepancies.\n4. Once all items are verified, provide your digital signature at the bottom of the form to officially approve the clearance.\n\nPlease complete this review promptly to ensure a smooth exit process for the employee.";
    
    document.getElementById('rn_email_to').value = phEmail || '';
    document.getElementById('rn_email_subj').value = defaultSubj;
    document.getElementById('rn_email_body').value = defaultBody;
    
    document.getElementById('rn_phone_display').value = phPhone || '';
    document.getElementById('rn_wa_msg').value = defaultBody;

    $('#notifyPHModal').modal('show');
}

function sendPhNotifyEmail(event) {
    var exitId = document.getElementById('rn_exit_id').value;
    var to = document.getElementById('rn_email_to').value;
    var subj = document.getElementById('rn_email_subj').value;
    var body = document.getElementById('rn_email_body').value;
    
    if(!to) { alert('Please enter an email address.'); return; }
    
    var btn = event.currentTarget;
    var orig = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Sending...';
    btn.disabled = true;
    
    $.post('hr-exit-handover.php', {
        ajax_action: 'notify_ph_email_ajax',
        exit_id: exitId,
        email_to: to,
        email_subject: subj,
        email_body: body
    }, function(res){
        try {
            var r = JSON.parse(res);
            if(r.status === 'success') {
                location.reload();
            } else {
                alert('Error: ' + r.message);
                btn.innerHTML = orig;
                btn.disabled = false;
            }
        } catch(e) {
            alert('Server error.');
            btn.innerHTML = orig;
            btn.disabled = false;
        }
    });
}

function openPhWhatsApp() {
    var ph = document.getElementById('rn_phone_display').value.trim();
    var msg = document.getElementById('rn_wa_msg').value;
    
    if(!ph) { alert('Please enter a phone number.'); return; }
    
    ph = ph.replace(/[^0-9]/g, '');
    if(ph.length === 10) ph = '91' + ph;
    
    var url = 'https://wa.me/' + ph + '?text=' + encodeURIComponent(msg);
    window.open(url, '_blank');
}

function openHistoryModal(exitId) {
    $.post('', { ajax_action: 'get_clearance_history', exit_id: exitId }, function(resp) {
        if (resp.success) {
            $('#historyModalBody').html(resp.html);
            $('#historyModal').modal('show');
        } else {
            alert('Could not load history.');
        }
    }, 'json');
}
</script>

<!-- History Modal -->
<div class="modal fade" id="historyModal" tabindex="-1" role="dialog">
  <div class="modal-dialog modal-dialog-centered" role="document" style="max-width:550px;">
    <div class="modal-content" style="border-radius:12px;overflow:hidden;border:none;box-shadow:0 10px 25px rgba(0,0,0,0.1);">
      <div class="modal-header" style="background:var(--navy);color:#fff;border-bottom:none;padding:16px 20px;">
        <h5 class="modal-title" style="font-weight:800;"><i class="fas fa-history mr-2"></i>Clearance History Log</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;opacity:0.8;text-shadow:none;"><span>&times;</span></button>
      </div>
      <div class="modal-body" id="historyModalBody" style="padding:24px;max-height:400px;overflow-y:auto;">
      </div>
    </div>
  </div>
</div>

<script>
$(document).ready(function() {

    // ── Shared helpers (same pagination-range + CSV pattern as hr_candidate_tracking.php) ──
    function buildPageRange(current, max) {
        if (max <= 7) return Array.from({length: max}, function(_, i) { return i + 1; });
        var pages = [1];
        if (current > 3) pages.push('…');
        for (var i = Math.max(2, current - 1); i <= Math.min(max - 1, current + 1); i++) pages.push(i);
        if (current < max - 2) pages.push('…');
        pages.push(max);
        return pages;
    }

    function downloadCSV(filename, headers, rows) {
        var csv = [headers.join(',')];
        rows.forEach(function(r) {
            csv.push(r.map(function(v) { return '"' + String(v == null ? '' : v).replace(/"/g, '""').trim() + '"'; }).join(','));
        });
        var blob = new Blob(['﻿' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = filename;
        a.click();
    }

    function downloadExcelHtml(filename, headers, rows) {
        var html = '<table border="1"><tr>' + headers.map(function(h) { return '<th>' + h + '</th>'; }).join('') + '</tr>';
        rows.forEach(function(r) {
            html += '<tr>' + r.map(function(v) { return '<td>' + (v == null ? '' : String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;')) + '</td>'; }).join('') + '</tr>';
        });
        html += '</table>';
        var blob = new Blob(['﻿' + html], { type: 'application/vnd.ms-excel' });
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = filename;
        a.click();
    }

    // ── Clearance Template Sections Export/Import (Manage Clearance Template) ──
    // NOTE: rows are ['Section', 'Item'] — this is the exact format the Import button expects back.
    var clrTemplateExportRows = <?php echo json_encode(array_merge(...array_map(function($ch) {
        if (empty($ch['items'])) return [[$ch['heading_name'], '']];
        return array_map(function($ci) use ($ch) { return [$ch['heading_name'], $ci['item_text']]; }, $ch['items']);
    }, $clearanceHeadings ?: []) ?: [[]]), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>;
    window.exportClrTemplateCSV = function() {
        var rows = clrTemplateExportRows.filter(function(r){ return r.length; });
        downloadCSV('Clearance_Template_<?php echo $clr_dept_id; ?>_<?php echo $clr_pos_id; ?>.csv', ['Section', 'Item'], rows);
    };
    window.downloadClrImportTemplate = function() {
        var rows = clrTemplateExportRows.filter(function(r){ return r.length; });
        if (!rows.length) rows = [['Example Section', 'Example checklist item'], ['Example Section', 'Another checklist item']];
        downloadCSV('Clearance_Template_Import_Format.csv', ['Section', 'Item'], rows);
    };

    // ── Asset Handover Table ──
    if ($('#assetHandoverTable').length > 0) {
        var assetPage = 1, assetPageSize = 25;

        var assetStatuses = [];
        $('#assetTbody .asset-row').each(function() {
            var v = $(this).data('status');
            if (v && assetStatuses.indexOf(v) === -1) assetStatuses.push(v);
        });
        assetStatuses.sort().forEach(function(v) {
            $('#assetStatus').append('<option value="' + v + '">' + v + '</option>');
        });

        function getVisibleAssetRows() {
            var dateFrom = $('#assetDateFrom').val();
            var dateTo   = $('#assetDateTo').val();
            var status   = $('#assetStatus').val();
            var search   = $('#assetSearch').val().toLowerCase().trim();
            return $('#assetTbody .asset-row').filter(function() {
                var $r = $(this);
                var lwd = $r.data('lwd') ? String($r.data('lwd')) : '';
                if (status && String($r.data('status')) !== status) return false;
                if (dateFrom && (!lwd || lwd < dateFrom)) return false;
                if (dateTo && (!lwd || lwd > dateTo)) return false;
                if (search && String($r.data('search') || '').indexOf(search) === -1) return false;
                return true;
            });
        }

        function renderAssetTable() {
            var rows = getVisibleAssetRows();
            var total = rows.length;
            var maxPage = Math.max(1, Math.ceil(total / assetPageSize));
            if (assetPage > maxPage) assetPage = maxPage;
            var start = (assetPage - 1) * assetPageSize, end = start + assetPageSize;

            $('#assetTbody .asset-row').hide();
            rows.slice(start, end).show();

            $('#assetNoResultsRow').toggle(total === 0);
            $('#assetTableCount').text(total + (total === 1 ? ' record' : ' records'));
            $('#assetPagingInfo').text(total === 0 ? 'No results' : 'Showing ' + (start + 1) + '–' + Math.min(end, total) + ' of ' + total);

            var $btns = $('#assetPagingBtns').empty();
            if (maxPage <= 1) return;
            buildPageRange(assetPage, maxPage).forEach(function(p) {
                var $btn = $('<button type="button" class="paging-btn"></button>').text(p);
                if (p === assetPage) $btn.addClass('active');
                if (p === '…') { $btn.prop('disabled', true); }
                else { $btn.on('click', function() { assetPage = p; renderAssetTable(); }); }
                $btns.append($btn);
            });
        }

        $('#assetDateFrom, #assetDateTo, #assetStatus').on('change', function() { assetPage = 1; renderAssetTable(); });
        $('#assetSearch').on('input', function() { assetPage = 1; renderAssetTable(); });

        window.exportAssetCSV = function(kind) {
            var headers = ['Exit #', 'Employee', 'Last Working Day', 'Status'];
            var rows = getVisibleAssetRows().get().map(function(el) {
                var $r = $(el);
                return [$r.find('td').eq(0).text().trim(), $r.find('td').eq(1).text().trim(), $r.find('td').eq(2).text().trim(), $r.data('status')];
            });
            if (kind === 'excel') downloadExcelHtml('Asset_Handover.xls', headers, rows);
            else downloadCSV('Asset_Handover.csv', headers, rows);
        };

        renderAssetTable();
    }

    // ── Department-Position Clearance Table ──
    if ($('#clearanceTable').length > 0) {
        var clrPage = 1, clrPageSize = 25;

        var clrDepts = [], clrPositions = [], clrStatuses = [];
        $('#clearanceTbody .clearance-row').each(function() {
            var d = $(this).data('dept'), ps = $(this).data('pos'), s = $(this).data('status');
            if (d && clrDepts.indexOf(d) === -1) clrDepts.push(d);
            if (ps && clrPositions.indexOf(ps) === -1) clrPositions.push(ps);
            if (s && clrStatuses.indexOf(s) === -1) clrStatuses.push(s);
        });
        clrDepts.sort().forEach(function(v) { $('#clearanceDepartment').append('<option value="' + v + '">' + v + '</option>'); });
        clrPositions.sort().forEach(function(v) { $('#clearancePosition').append('<option value="' + v + '">' + v + '</option>'); });
        clrStatuses.sort().forEach(function(v) { $('#clearanceStatus').append('<option value="' + v + '">' + v + '</option>'); });

        function getVisibleClearanceRows() {
            var dateFrom = $('#clearanceDateFrom').val();
            var dateTo   = $('#clearanceDateTo').val();
            var dept     = $('#clearanceDepartment').val();
            var pos      = $('#clearancePosition').val();
            var status   = $('#clearanceStatus').val();
            var search   = $('#clearanceSearch').val().toLowerCase().trim();
            return $('#clearanceTbody .clearance-row').filter(function() {
                var $r = $(this);
                var lwd = $r.data('lwd') ? String($r.data('lwd')) : '';
                if (dept && String($r.data('dept')) !== dept) return false;
                if (pos && String($r.data('pos')) !== pos) return false;
                if (status && String($r.data('status')) !== status) return false;
                if (dateFrom && (!lwd || lwd < dateFrom)) return false;
                if (dateTo && (!lwd || lwd > dateTo)) return false;
                if (search && String($r.data('search') || '').indexOf(search) === -1) return false;
                return true;
            });
        }

        function renderClearanceTable() {
            var rows = getVisibleClearanceRows();
            var total = rows.length;
            var maxPage = Math.max(1, Math.ceil(total / clrPageSize));
            if (clrPage > maxPage) clrPage = maxPage;
            var start = (clrPage - 1) * clrPageSize, end = start + clrPageSize;

            $('#clearanceTbody .clearance-row').hide();
            rows.slice(start, end).show();

            $('#clearanceNoResultsRow').toggle(total === 0);
            $('#clearanceTableCount').text(total + (total === 1 ? ' record' : ' records'));
            $('#clearancePagingInfo').text(total === 0 ? 'No results' : 'Showing ' + (start + 1) + '–' + Math.min(end, total) + ' of ' + total);

            var $btns = $('#clearancePagingBtns').empty();
            if (maxPage <= 1) return;
            buildPageRange(clrPage, maxPage).forEach(function(p) {
                var $btn = $('<button type="button" class="paging-btn"></button>').text(p);
                if (p === clrPage) $btn.addClass('active');
                if (p === '…') { $btn.prop('disabled', true); }
                else { $btn.on('click', function() { clrPage = p; renderClearanceTable(); }); }
                $btns.append($btn);
            });
        }

        $('#clearanceDateFrom, #clearanceDateTo, #clearanceDepartment, #clearancePosition, #clearanceStatus').on('change', function() { clrPage = 1; renderClearanceTable(); });
        $('#clearanceSearch').on('input', function() { clrPage = 1; renderClearanceTable(); });

        window.exportClearanceCSV = function(kind) {
            var headers = ['Exit #', 'Employee', 'Department', 'Position', 'Last Working Day', 'Status'];
            var rows = getVisibleClearanceRows().get().map(function(el) {
                var $r = $(el);
                return [$r.find('td').eq(0).text().trim(), $r.find('td').eq(1).text().trim(), $r.data('dept') || '—', $r.data('pos') || '—', $r.find('td').eq(3).text().trim(), $r.data('status')];
            });
            if (kind === 'excel') downloadExcelHtml('Department_Position_Clearance.xls', headers, rows);
            else downloadCSV('Department_Position_Clearance.csv', headers, rows);
        };

        renderClearanceTable();
    }
});
</script>
</body>

<script>
(function(){
  var UE = <?php echo json_encode($GLOBALS['__fue'] ?? ''); ?>;
  if(!UE) return;
  function add(u){
    if(!u) return u;
    if(/^(https?:|\/\/|#|mailto:|tel:|javascript:|data:)/i.test(u)) return u;
    if(u.indexOf('.php')===-1) return u;
    // this folder is served via an alias, so links can come out as bare
    // 'foo.php' or as '/dashboard/foo.php' - both must resolve under /hrm/.
    if(/^\/dashboard\/hr[_-][A-Za-z0-9._-]*\.php(\?|$)/.test(u)) u = u.replace(/^\/dashboard\//, '/hrm/');
    else if(/^[A-Za-z0-9._-]+\.php(\?|$)/.test(u)) u = '/hrm/' + u;
    if(/[?&]user_email=/.test(u)) return u;
    return u + (u.indexOf('?')===-1?'?':'&') + 'user_email=' + encodeURIComponent(UE);
  }
  function fix(){
    document.querySelectorAll('a[href]').forEach(function(a){ a.setAttribute('href', add(a.getAttribute('href'))); });
    document.querySelectorAll('form').forEach(function(f){
      var m=(f.getAttribute('method')||'get').toLowerCase();
      var act=f.getAttribute('action');
      if(act!==null) f.setAttribute('action', add(act));
      if(!f.querySelector('input[name="user_email"]')){
        var i=document.createElement('input'); i.type='hidden'; i.name='user_email'; i.value=UE; f.appendChild(i);
      }
    });
  }
  if(document.readyState!=='loading') fix(); else document.addEventListener('DOMContentLoaded', fix);
  document.addEventListener('click', function(e){
    var a=e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if(a) a.setAttribute('href', add(a.getAttribute('href')));
  }, true);
  // --- carry user_email on EVERY same-site .php AJAX call too ---
  try{ var _f=window.fetch; if(_f) window.fetch=function(i,init){ try{ if(typeof i==='string') i=add(i); else if(i&&i.url) i=new Request(add(i.url),i); }catch(e){} return _f.call(this,i,init); }; }catch(e){}
  try{ var _o=XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open=function(m,u){ try{ if(typeof u==='string') u=add(u); }catch(e){} return _o.apply(this,[m,u].concat([].slice.call(arguments,2))); }; }catch(e){}
  try{ if(window.jQuery&&window.jQuery.ajaxPrefilter) window.jQuery.ajaxPrefilter(function(o){ try{ o.url=add(o.url); }catch(e){} }); }catch(e){}
})();
</script>
</html>