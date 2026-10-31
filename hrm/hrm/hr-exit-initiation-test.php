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

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// SMTP CONFIG (authenticated sending — same setup as hr_screening.php / hr-appraisal.php)
// =========================================================================
define('SMTP_HOST', 'mail.abra-logistic.com');
define('SMTP_PORT', 465);
define('SMTP_SECURE', 'ssl');
define('SMTP_USER', 'support@abra-logistic.com');
define('SMTP_PASS', 'support@12345');
define('SMTP_FROM_NAME_DEFAULT', 'ABRA E-LOGISTIC HR');

$PHPMAILER_AVAILABLE = false;
$pm1 = __DIR__ . '/PHPMailer/src/Exception.php';
$pm2 = __DIR__ . '/PHPMailer/src/PHPMailer.php';
$pm3 = __DIR__ . '/PHPMailer/src/SMTP.php';
if (file_exists($pm1) && file_exists($pm2) && file_exists($pm3)) {
    require_once($pm1);
    require_once($pm2);
    require_once($pm3);
    $PHPMAILER_AVAILABLE = true;
}

function sendSmtpMail($to_list, $subject, $body_text, $from_name = null) {
    global $PHPMAILER_AVAILABLE;
    if (!$PHPMAILER_AVAILABLE) {
        $to = implode(',', array_filter((array)$to_list, function($e){ return filter_var(trim($e), FILTER_VALIDATE_EMAIL); }));
        if (!$to) return ['success' => false, 'message' => 'No valid email address found.'];
        $headers = "From: " . ($from_name ?: SMTP_FROM_NAME_DEFAULT) . " <" . SMTP_USER . ">\r\nReply-To: " . SMTP_USER . "\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n";
        $sent = @mail($to, $subject, $body_text, $headers);
        return ['success' => $sent, 'message' => $sent ? 'Email sent (fallback mail() — upload PHPMailer folder for reliable SMTP).' : 'mail() returned false.'];
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
            if ($to !== '' && filter_var($to, FILTER_VALIDATE_EMAIL)) $mail->addAddress($to);
        }
        $mail->addReplyTo(SMTP_USER, $from_name ?: SMTP_FROM_NAME_DEFAULT);
        $mail->isHTML(false);
        $mail->Subject = $subject;
        $mail->Body    = $body_text;
        $mail->send();
        return ['success' => true, 'message' => 'Email sent.'];
    } catch (\Exception $e) {
        return ['success' => false, 'message' => 'SMTP Error: ' . $mail->ErrorInfo];
    }
}

// =========================================================================
// TABLE SETUP
// =========================================================================
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

// Shared with hr-exit-documents.php — created here too so type-specific letters
// (Termination / Retirement / Non-Renewal) can be issued directly from this page.
"CREATE TABLE IF NOT EXISTS hr_exit_documents (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    doc_type ENUM('relieving_letter','experience_certificate','settlement_statement','termination_letter','retirement_confirmation_letter','non_renewal_notification') NOT NULL,
    token VARCHAR(64) DEFAULT NULL,
    generated_by VARCHAR(255) DEFAULT NULL,
    generated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    sent_at DATETIME DEFAULT NULL,
    UNIQUE KEY uniq_exit_doc (exit_id, doc_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) mysqli_query($con, $sql);

if (mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_settings WHERE id=1")) == 0) {
    mysqli_query($con, "INSERT INTO hr_exit_settings (id, retirement_age) VALUES (1, 60)");
}

// =========================================================================
// SAFE SCHEMA MIGRATION HELPERS (non-destructive — additive only)
// =========================================================================
function ensureColumn($con, $table, $col, $def) {
    $r = mysqli_query($con, "SHOW COLUMNS FROM $table LIKE '$col'");
    if (!$r || mysqli_num_rows($r) == 0) mysqli_query($con, "ALTER TABLE $table ADD COLUMN $col $def");
}
function ensureEnumValue($con, $table, $col, $value, $fullEnumSql) {
    $r = mysqli_query($con, "SHOW COLUMNS FROM $table LIKE '$col'");
    $row = $r ? mysqli_fetch_assoc($r) : null;
    if ($row && strpos($row['Type'], "'$value'") === false) {
        mysqli_query($con, "ALTER TABLE $table MODIFY COLUMN $col $fullEnumSql");
    }
}

// Covers installs where hr_exit_requests already existed before this revision
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

// Ensure hr_employees has exit-tracking columns (non-destructive)
ensureColumn($con, 'hr_employees', 'employment_status', "VARCHAR(20) DEFAULT 'active'");
ensureColumn($con, 'hr_employees', 'rehire_eligible', "VARCHAR(10) DEFAULT NULL");
ensureColumn($con, 'hr_employees', 'contract_end_date', "DATE DEFAULT NULL");

// =========================================================================
// HELPERS
// =========================================================================
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

function generateExitNumber($con) {
    $q = mysqli_query($con, "SELECT exit_number FROM hr_exit_requests ORDER BY id DESC LIMIT 1");
    $last = $q ? mysqli_fetch_assoc($q) : null;
    if ($last && $last['exit_number']) {
        preg_match('/EX(\d+)/', $last['exit_number'], $m);
        $next = isset($m[1]) ? intval($m[1]) + 1 : 1;
    } else { $next = 1; }
    return 'EX' . str_pad($next, 4, '0', STR_PAD_LEFT);
}

function getNoticeDays($con, $dept_id, $pos_id) {
    $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT notice_days FROM hr_exit_notice_policy WHERE department_id=$dept_id AND position_id=$pos_id LIMIT 1"));
    if (!$r) $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT notice_days FROM hr_exit_notice_policy WHERE department_id=$dept_id AND position_id=0 LIMIT 1"));
    return $r ? intval($r['notice_days']) : 30;
}

// Raises one ticket per assignee — same tickets table and ticket_number
// pattern used by raise-a-ticket.php, so these show up in the normal
// ticket inbox alongside every other ticket in the system.
function raiseExitTickets($con, $currentUserName, $subject, $message, $priority, $timeline_minutes, $assigned_to_list) {
    $subject = mysqli_real_escape_string($con, $subject);
    $message = mysqli_real_escape_string($con, $message);
    $priority = in_array($priority, ['low','medium','high']) ? $priority : 'medium';
    $timeline_minutes = max(1, intval($timeline_minutes));
    $deadline = date('Y-m-d H:i:s', strtotime("+{$timeline_minutes} minutes"));
    $name = mysqli_real_escape_string($con, $currentUserName);

    $created_by = 0;
    $un = mysqli_real_escape_string($con, $currentUserName);
    $ur = mysqli_query($con, "SELECT id FROM hr_employees WHERE name='$un' LIMIT 1");
    if ($ur && mysqli_num_rows($ur) > 0) {
        $created_by = intval(mysqli_fetch_assoc($ur)['id']);
    } else {
        $ur2 = mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$un%' LIMIT 1");
        if ($ur2 && mysqli_num_rows($ur2) > 0) $created_by = intval(mysqli_fetch_assoc($ur2)['id']);
    }

    $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by) VALUES (?, ?, ?, ?, 'open', ?, ?, ?, '', NOW(), NOW(), ?, ?)");
    if (!$stmt) return 0;
    $inserted = 0;
    foreach ($assigned_to_list as $assigned_to) {
        $assigned_to = intval($assigned_to);
        if ($assigned_to <= 0) continue;
        $rowmax = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
        $nextId = intval($rowmax['max_id'] ?? 0) + 1;
        $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
        mysqli_stmt_bind_param($stmt, "sssssisii", $ticket_number, $name, $subject, $message, $priority, $timeline_minutes, $deadline, $assigned_to, $created_by);
        if (mysqli_stmt_execute($stmt)) $inserted++;
    }
    mysqli_stmt_close($stmt);
    return $inserted;
}

define('RESIGNATION_LINK_EXPIRY_DAYS', 7);

$reasonCategories = ['Better Opportunity','Higher Studies','Relocation','Health','Family / Personal','Compensation','Work-Life Balance','Other'];

// Safely embeds a PHP value as a JS literal inside an HTML attribute (e.g. onclick="fn(<?php echo $j($v); ?>)")
$jsonOpts = JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP;
$j = fn($v) => htmlspecialchars(json_encode($v, $jsonOpts), ENT_QUOTES, 'UTF-8');

// Resolves an HR/employee display name back to hr_employees.id — same
// name-match fallback used by raiseExitTickets() below.
function resolveEmployeeIdByName($con, $name) {
    $n = mysqli_real_escape_string($con, trim($name));
    if ($n === '') return 0;
    $r = mysqli_query($con, "SELECT id FROM hr_employees WHERE name='$n' LIMIT 1");
    if ($r && mysqli_num_rows($r) > 0) return intval(mysqli_fetch_assoc($r)['id']);
    $r2 = mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$n%' LIMIT 1");
    if ($r2 && mysqli_num_rows($r2) > 0) return intval(mysqli_fetch_assoc($r2)['id']);
    return 0;
}

// Builds a chronological "who did what, when" timeline for one exit request,
// reading purely from timestamp/actor columns already captured on the row
// plus any documents issued for it — no separate audit-log table needed.
function buildExitHistory($con, $r) {
    $events = [];
    $add = function($at, $label, $by, $detail = '') use (&$events) {
        if (!$at) return;
        $events[] = ['at' => $at, 'label' => $label, 'by' => $by ?: '—', 'detail' => $detail];
    };

    if ($r['exit_type'] === 'resignation') {
        $add($r['link_generated_at'], 'Resignation link generated', $r['link_generated_by'], 'Reason category: ' . ($r['link_reason_category'] ?: '—'));
        $add($r['submitted_at'], 'Resignation submitted by employee', $r['employee_name'] ?? 'Employee', $r['reason'] ? ('Reason: ' . $r['reason']) : '');
    } else {
        $add($r['created_at'], ucfirst(str_replace('_',' ',$r['exit_type'])) . ' initiated', $r['initiated_by'], $r['reason'] ? ('Reason: ' . $r['reason']) : '');
    }

    if ($r['hr_approved_at']) {
        $add($r['hr_approved_at'], 'HR decision: ' . ucfirst($r['hr_approval']), $r['hr_approved_by'], $r['hr_remarks'] ? ('Remarks: ' . $r['hr_remarks']) : '');
    }
    if ($r['manager_approved_at']) {
        $detail = $r['manager_remarks'] ? ('Remarks: ' . $r['manager_remarks']) : '';
        if ($r['manager_approval'] === 'approved' && $r['final_last_working_day']) {
            $detail .= ($detail ? ' | ' : '') . 'Notice period: ' . $r['notice_start_date'] . ' to ' . $r['final_last_working_day'];
        }
        $add($r['manager_approved_at'], 'Manager decision: ' . ucfirst($r['manager_approval']), $r['manager_approved_by'], $detail);
    }
    if ($r['second_approved_at']) {
        $add($r['second_approved_at'], 'Second-level compliance decision: ' . ucfirst($r['second_approval']), $r['second_approved_by'], '');
    }
    if ($r['link_notified_at']) {
        $add($r['link_notified_at'], 'Employee notified about the link (via ' . ucfirst($r['link_notify_channel'] ?: '—') . ')', $r['link_generated_by'], '');
    }

    $docLabels = ['termination_letter'=>'Termination Letter issued','retirement_confirmation_letter'=>'Retirement Confirmation Letter issued','non_renewal_notification'=>'Non-Renewal Notification issued','relieving_letter'=>'Relieving Letter issued','experience_certificate'=>'Experience Certificate issued','settlement_statement'=>'Settlement Statement issued'];
    $dq = mysqli_query($con, "SELECT * FROM hr_exit_documents WHERE exit_id={$r['id']} ORDER BY generated_at ASC");
    if ($dq) while ($d = mysqli_fetch_assoc($dq)) {
        $add($d['generated_at'], $docLabels[$d['doc_type']] ?? ('Document issued: ' . $d['doc_type']), $d['generated_by'], '');
    }

    usort($events, fn($a, $b) => strtotime($a['at']) <=> strtotime($b['at']));
    return $events;
}

function issueDoc($con, $exit_id, $doc_type, $by) {
    $token = bin2hex(random_bytes(24));
    $by = mysqli_real_escape_string($con, $by);
    mysqli_query($con, "INSERT INTO hr_exit_documents (exit_id, doc_type, token, generated_by) VALUES ($exit_id, '$doc_type', '$token', '$by') ON DUPLICATE KEY UPDATE token='$token', generated_by='$by', generated_at=NOW()");
    return $token;
}

$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']==='on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';

// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    // ---- HR-initiated exit (Termination / manual Retirement / manual Contract End) ----
    // Resignation is intentionally NOT offered here — it must come through the
    // employee-specific link (see generate_resignation_link below).
    if (isset($_POST['action']) && $_POST['action'] === 'initiate_exit') {
        $employee_id = intval($_POST['employee_id']);
        $exit_type = in_array($_POST['exit_type'], ['termination','retirement','contract_end']) ? $_POST['exit_type'] : 'termination';
        $reason = mysqli_real_escape_string($con, $_POST['reason'] ?? '');
        $requested_last_day = mysqli_real_escape_string($con, $_POST['requested_last_day'] ?? '');
        $exit_number = generateExitNumber($con);
        $initiated_by = mysqli_real_escape_string($con, $currentUserName);

        $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$employee_id LIMIT 1"));
        list($dept_id, $pos_id) = $empRow ? resolveDeptPos($con, $empRow) : [0, 0];
        $notice_days = getNoticeDays($con, $dept_id, $pos_id);

        $extraCols = ''; $extraVals = '';
        if ($exit_type === 'termination') {
            $termination_type = in_array($_POST['termination_type'] ?? '', ['performance','misconduct','redundancy','layoff']) ? $_POST['termination_type'] : 'performance';
            $warning_ref = mysqli_real_escape_string($con, $_POST['warning_letter_ref'] ?? '');
            $second_approver = mysqli_real_escape_string($con, $_POST['second_approver_name'] ?? '');
            if (!$reason) { $_SESSION['success_message'] = "Documented reason is mandatory for termination."; header("Location: hr-exit-initiation.php?tab=new"); exit; }
            $extraCols = ", termination_type, warning_letter_ref, second_approver_name";
            $extraVals = ", '$termination_type', " . ($warning_ref ? "'$warning_ref'" : "NULL") . ", " . ($second_approver ? "'$second_approver'" : "NULL");
        }

        mysqli_query($con, "INSERT INTO hr_exit_requests (exit_number, employee_id, exit_type, reason, initiated_by, requested_last_day, policy_notice_days, status $extraCols) VALUES ('$exit_number', $employee_id, '$exit_type', '$reason', '$initiated_by', " . ($requested_last_day ? "'$requested_last_day'" : "NULL") . ", $notice_days, 'initiated' $extraVals)");

        $msg = "Exit request $exit_number created for review.";

        if (isset($_POST['raise_ticket']) && $_POST['raise_ticket'] === '1') {
            $ticket_assignees = array_filter(array_map('intval', (array)($_POST['ticket_assignees'] ?? [])));
            $ticket_subject = trim($_POST['ticket_subject'] ?? '');
            $ticket_message = trim($_POST['ticket_message'] ?? '');
            $ticket_priority = $_POST['ticket_priority'] ?? 'medium';
            $ticket_timeline = intval($_POST['ticket_timeline'] ?? 1440);

            if (!empty($ticket_assignees) && $ticket_subject && $ticket_message) {
                $count = raiseExitTickets($con, $currentUserName, $ticket_subject, $ticket_message, $ticket_priority, $ticket_timeline, $ticket_assignees);
                if ($count > 0) $msg .= " $count ticket(s) raised to notify the selected team members.";
            }
        }

        $_SESSION['success_message'] = $msg;
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Resignation link generation (same pattern as Offer Letter links) ----
    if (isset($_POST['action']) && $_POST['action'] === 'generate_resignation_link') {
        $employee_id = intval($_POST['employee_id']);
        $link_reason = mysqli_real_escape_string($con, $_POST['link_reason'] ?? '');
        $link_reason_category = mysqli_real_escape_string($con, $_POST['link_reason_category'] ?? 'Other');
        // HR sets how long the link stays valid (1-90 days); falls back to the default if left blank/invalid.
        $expiryDays = intval($_POST['link_expiry_days'] ?? RESIGNATION_LINK_EXPIRY_DAYS);
        if ($expiryDays < 1) $expiryDays = RESIGNATION_LINK_EXPIRY_DAYS;
        if ($expiryDays > 90) $expiryDays = 90;
        $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$employee_id LIMIT 1"));
        if (!$empRow) { $_SESSION['success_message'] = "Employee not found."; header("Location: hr-exit-initiation.php?tab=link"); exit; }

        // Reuse an existing not-yet-submitted link for this employee instead of stacking duplicates
        $existing = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE employee_id=$employee_id AND status='link_sent' ORDER BY id DESC LIMIT 1"));
        $by = mysqli_real_escape_string($con, $currentUserName);
        $token = bin2hex(random_bytes(32));
        $expiresAt = date('Y-m-d H:i:s', strtotime("+$expiryDays days"));

        if ($existing) {
            mysqli_query($con, "UPDATE hr_exit_requests SET token='$token', link_generated_by='$by', link_generated_at=NOW(), link_reason='$link_reason', link_reason_category='$link_reason_category', link_expires_at='$expiresAt', link_notified_at=NULL, link_notify_channel=NULL WHERE id={$existing['id']}");
            $newId = intval($existing['id']);
        } else {
            $exit_number = generateExitNumber($con);
            mysqli_query($con, "INSERT INTO hr_exit_requests (exit_number, employee_id, exit_type, initiated_by, token, link_generated_by, link_generated_at, link_reason, link_reason_category, link_expires_at, status) VALUES ('$exit_number', $employee_id, 'resignation', '$by', '$token', '$by', NOW(), '$link_reason', '$link_reason_category', '$expiresAt', 'link_sent')");
            $newId = mysqli_insert_id($con);
        }
        $expiresDisplay = date('d M Y', strtotime($expiresAt));
        $_SESSION['success_message'] = "Resignation link generated for " . htmlspecialchars($empRow['name']) . " — valid until <strong>" . $expiresDisplay . "</strong>. Review the message below and send it to notify them.";
        header("Location: hr-exit-initiation.php?tab=link&generated=1&new_id=$newId"); exit;
    }

    // ---- Notify Candidate: send the resignation link by email ----
    if (isset($_POST['ajax_send_link_email'])) {
        header('Content-Type: application/json');
        $id = intval($_POST['id']);
        $to = trim($_POST['to'] ?? '');
        $subject = trim($_POST['subject'] ?? '');
        $body = trim($_POST['body'] ?? '');
        if (!$to || !$subject || !$body) { echo json_encode(['success'=>false,'message'=>'To, subject and message are required.']); exit; }

        $result = sendSmtpMail([$to], $subject, $body, 'ABRA HR — Exit Process');
        if ($result['success']) {
            mysqli_query($con, "UPDATE hr_exit_requests SET link_notified_at=NOW(), link_notify_channel='email' WHERE id=$id");
        }
        echo json_encode($result);
        exit;
    }

    // ---- Notify Candidate: mark as notified via WhatsApp (the wa.me open itself happens client-side) ----
    if (isset($_POST['ajax_mark_link_notified'])) {
        header('Content-Type: application/json');
        $id = intval($_POST['id']);
        mysqli_query($con, "UPDATE hr_exit_requests SET link_notified_at=NOW(), link_notify_channel='whatsapp' WHERE id=$id");
        echo json_encode(['success' => true]);
        exit;
    }

    // ---- Resignation: Step 4 — HR discussion & decision (Retained / Approved) ----
    if (isset($_POST['action']) && $_POST['action'] === 'hr_decision') {
        $id = intval($_POST['id']);
        $decision = in_array($_POST['decision'], ['approved','retained']) ? $_POST['decision'] : 'retained';
        $remarks = mysqli_real_escape_string($con, $_POST['hr_remarks'] ?? '');
        $by = mysqli_real_escape_string($con, $currentUserName);

        mysqli_query($con, "UPDATE hr_exit_requests SET hr_approval='$decision', hr_approved_by='$by', hr_approved_at=NOW(), hr_remarks='$remarks' WHERE id=$id");
        if ($decision === 'retained') {
            mysqli_query($con, "UPDATE hr_exit_requests SET status='retained' WHERE id=$id");
            $_SESSION['success_message'] = "Employee retained by HR — logged as a retention, not a rejection.";
        } else {
            $_SESSION['success_message'] = "HR approved the exit. Forwarded to Manager.";
        }
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Resignation: Step 5 — Manager discussion & decision (Retained / Approved) ----
    if (isset($_POST['action']) && $_POST['action'] === 'manager_decision') {
        $id = intval($_POST['id']);
        $decision = in_array($_POST['decision'], ['approved','retained']) ? $_POST['decision'] : 'retained';
        $by = mysqli_real_escape_string($con, $currentUserName);
        $manager_remarks = mysqli_real_escape_string($con, $_POST['manager_remarks'] ?? '');

        mysqli_query($con, "UPDATE hr_exit_requests SET manager_approval='$decision', manager_approved_by='$by', manager_approved_at=NOW(), manager_remarks='$manager_remarks' WHERE id=$id");

        if ($decision === 'retained') {
            mysqli_query($con, "UPDATE hr_exit_requests SET status='retained' WHERE id=$id");
            $_SESSION['success_message'] = "Employee retained by Manager — logged as a retention, not a rejection.";
        } else {
            // Notice Start = date of Manager's approval (today), fixed by policy.
            // Notice End / Final Last Working Day = whatever the manager sets (defaults to
            // today + policy notice days, but the manager has full discretion to change it).
            $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT policy_notice_days FROM hr_exit_requests WHERE id=$id"));
            $notice_days = $row ? intval($row['policy_notice_days']) : 30;
            $notice_start = date('Y-m-d');
            $notice_end = mysqli_real_escape_string($con, $_POST['final_last_working_day'] ?? '');
            if (!$notice_end) $notice_end = date('Y-m-d', strtotime("+$notice_days days"));
            mysqli_query($con, "UPDATE hr_exit_requests SET notice_start_date='$notice_start', final_last_working_day='$notice_end', status='approved' WHERE id=$id");
            $_SESSION['success_message'] = "Manager approved the exit. Notice period: $notice_start to $notice_end.";
        }
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Termination: Step 2 — second-level compliance approval ----
    if (isset($_POST['action']) && $_POST['action'] === 'second_decision') {
        $id = intval($_POST['id']);
        $decision = in_array($_POST['decision'], ['approved','rejected']) ? $_POST['decision'] : 'rejected';
        $by = trim($currentUserName);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT initiated_by FROM hr_exit_requests WHERE id=$id"));
        if ($row && $row['initiated_by'] === $by) {
            $_SESSION['success_message'] = "The second-level compliance approver must be different from the person who initiated the termination.";
            header("Location: hr-exit-initiation.php"); exit;
        }
        $byEsc = mysqli_real_escape_string($con, $by);
        mysqli_query($con, "UPDATE hr_exit_requests SET second_approval='$decision', second_approved_by='$byEsc', second_approved_at=NOW() WHERE id=$id");
        if ($decision === 'rejected') {
            mysqli_query($con, "UPDATE hr_exit_requests SET status='rejected' WHERE id=$id");
            $_SESSION['success_message'] = "Termination rejected at compliance review.";
        } else {
            $_SESSION['success_message'] = "Termination approved by second-level compliance review.";
        }
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Termination: Step 3 — notice / severance decision + Step 4 — issue Termination Letter ----
    if (isset($_POST['action']) && $_POST['action'] === 'finalize_termination') {
        $id = intval($_POST['id']);
        $notice_handling = in_array($_POST['notice_handling'] ?? '', ['served','pay_in_lieu','immediate']) ? $_POST['notice_handling'] : 'immediate';
        $final_day = mysqli_real_escape_string($con, $_POST['final_last_working_day'] ?? date('Y-m-d'));
        mysqli_query($con, "UPDATE hr_exit_requests SET notice_handling='$notice_handling', final_last_working_day='$final_day' WHERE id=$id");
        issueDoc($con, $id, 'termination_letter', $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_requests SET status='approved' WHERE id=$id");
        $_SESSION['success_message'] = "Termination Letter issued. Exit countdown started.";
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Retirement: HR confirmation + Retirement Confirmation Letter (from the requests list, for a row already 'initiated') ----
    if (isset($_POST['action']) && $_POST['action'] === 'confirm_retirement') {
        $id = intval($_POST['id']);
        $final_day = mysqli_real_escape_string($con, $_POST['final_last_working_day'] ?? '');
        $remarks = mysqli_real_escape_string($con, $_POST['hr_remarks'] ?? '');
        if (!$final_day) { $_SESSION['success_message'] = "Retirement date is required."; header("Location: hr-exit-initiation.php"); exit; }
        mysqli_query($con, "UPDATE hr_exit_requests SET final_last_working_day='$final_day', hr_remarks='$remarks', status='approved' WHERE id=$id");
        issueDoc($con, $id, 'retirement_confirmation_letter', $currentUserName);
        $_SESSION['success_message'] = "Retirement confirmed. Confirmation letter issued.";
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Retirement: one-click confirm straight from the Retirement Alerts tab (creates + confirms in one step) ----
    if (isset($_POST['action']) && $_POST['action'] === 'initiate_exit_then_confirm_retirement') {
        $employee_id = intval($_POST['employee_id']);
        $final_day = mysqli_real_escape_string($con, $_POST['requested_last_day'] ?? '');
        $reason = mysqli_real_escape_string($con, $_POST['reason'] ?? '');
        $by = mysqli_real_escape_string($con, $currentUserName);
        if (!$employee_id || !$final_day) { $_SESSION['success_message'] = "Employee and retirement date are required."; header("Location: hr-exit-initiation.php?tab=retirement"); exit; }

        $exit_number = generateExitNumber($con);
        mysqli_query($con, "INSERT INTO hr_exit_requests (exit_number, employee_id, exit_type, reason, initiated_by, requested_last_day, final_last_working_day, hr_remarks, status) VALUES ('$exit_number', $employee_id, 'retirement', '$reason', '$by', '$final_day', '$final_day', '$reason', 'approved')");
        $id = mysqli_insert_id($con);
        issueDoc($con, $id, 'retirement_confirmation_letter', $currentUserName);
        $_SESSION['success_message'] = "Retirement confirmed for exit $exit_number. Confirmation letter issued.";
        header("Location: hr-exit-initiation.php?tab=requests"); exit;
    }

    // ---- Contract End: confirm non-renewal for a request already sitting in the list (manual entry path) ----
    if (isset($_POST['action']) && $_POST['action'] === 'confirm_non_renewal_from_list') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT requested_last_day FROM hr_exit_requests WHERE id=$id"));
        $final_day = $row ? $row['requested_last_day'] : date('Y-m-d');
        mysqli_query($con, "UPDATE hr_exit_requests SET final_last_working_day=" . ($final_day ? "'$final_day'" : "NULL") . ", status='approved' WHERE id=$id");
        issueDoc($con, $id, 'non_renewal_notification', $currentUserName);
        $_SESSION['success_message'] = "Non-renewal confirmed. Notification issued.";
        header("Location: hr-exit-initiation.php"); exit;
    }

    // ---- Contract End: mark as renewed (no exit triggered) ----
    if (isset($_POST['action']) && $_POST['action'] === 'renew_contract') {
        $employee_id = intval($_POST['employee_id']);
        $new_end = mysqli_real_escape_string($con, $_POST['new_contract_end_date'] ?? '');
        if ($new_end) mysqli_query($con, "UPDATE hr_employees SET contract_end_date='$new_end' WHERE id=$employee_id");
        $_SESSION['success_message'] = "Contract renewed. No exit process triggered.";
        header("Location: hr-exit-initiation.php?tab=contract"); exit;
    }

    // ---- Contract End: non-renewal, confirmed straight from the Contract Alerts tab (creates + confirms in one step) ----
    if (isset($_POST['action']) && $_POST['action'] === 'initiate_exit_then_confirm_non_renewal') {
        $employee_id = intval($_POST['employee_id']);
        $final_day = mysqli_real_escape_string($con, $_POST['requested_last_day'] ?? '');
        $by = mysqli_real_escape_string($con, $currentUserName);
        if (!$employee_id || !$final_day) { $_SESSION['success_message'] = "Employee and contract end date are required."; header("Location: hr-exit-initiation.php?tab=contract"); exit; }

        $exit_number = generateExitNumber($con);
        mysqli_query($con, "INSERT INTO hr_exit_requests (exit_number, employee_id, exit_type, initiated_by, requested_last_day, final_last_working_day, status) VALUES ('$exit_number', $employee_id, 'contract_end', '$by', '$final_day', '$final_day', 'approved')");
        $id = mysqli_insert_id($con);
        issueDoc($con, $id, 'non_renewal_notification', $currentUserName);
        $_SESSION['success_message'] = "Non-renewal confirmed for exit $exit_number. Notification issued.";
        header("Location: hr-exit-initiation.php?tab=requests"); exit;
    }

    if (isset($_POST['action']) && $_POST['action'] === 'save_notice_policy') {
        $dept_id = intval($_POST['department_id']);
        $pos_id = intval($_POST['position_id'] ?? 0);
        $days = intval($_POST['notice_days']);
        mysqli_query($con, "INSERT INTO hr_exit_notice_policy (department_id, position_id, notice_days) VALUES ($dept_id, $pos_id, $days) ON DUPLICATE KEY UPDATE notice_days=$days");
        $_SESSION['success_message'] = "Notice period policy saved.";
        header("Location: hr-exit-initiation.php?tab=policy"); exit;
    }

    if (isset($_POST['action']) && $_POST['action'] === 'save_retirement_age') {
        $age = intval($_POST['retirement_age']);
        if ($age > 0) mysqli_query($con, "UPDATE hr_exit_settings SET retirement_age=$age WHERE id=1");
        $_SESSION['success_message'] = "Retirement age policy saved.";
        header("Location: hr-exit-initiation.php?tab=retirement"); exit;
    }
}

// =========================================================================
// DATA FOR PAGE
// =========================================================================
$requests = [];
$rq = mysqli_query($con, "SELECT r.*, e.name as employee_name, e.department, e.position FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.status != 'link_sent' ORDER BY r.id DESC");
if ($rq) while ($row = mysqli_fetch_assoc($rq)) $requests[] = $row;

$linkRequests = [];
$lq = mysqli_query($con, "SELECT r.*, e.name as employee_name FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.status='link_sent' ORDER BY r.id DESC");
if ($lq) while ($row = mysqli_fetch_assoc($lq)) $linkRequests[] = $row;

$employees = [];
$eq = mysqli_query($con, "SELECT id, name, department, position, dob, employee_type, contract_end_date FROM hr_employees WHERE employment_status IS NULL OR employment_status='active' ORDER BY name ASC");
if ($eq) while ($row = mysqli_fetch_assoc($eq)) $employees[] = $row;

$departments = [];
$dq = mysqli_query($con, "SELECT id, name FROM hr_departments ORDER BY name ASC");
if ($dq) while ($row = mysqli_fetch_assoc($dq)) $departments[] = $row;

$policies = [];
$pq = mysqli_query($con, "SELECT p.*, d.name as dept_name FROM hr_exit_notice_policy p LEFT JOIN hr_departments d ON d.id=p.department_id ORDER BY d.name ASC");
if ($pq) while ($row = mysqli_fetch_assoc($pq)) $policies[] = $row;

$retirementAge = intval((mysqli_fetch_assoc(mysqli_query($con, "SELECT retirement_age FROM hr_exit_settings WHERE id=1")) ?: ['retirement_age'=>60])['retirement_age']);

// Retirement alerts — employees within 1 year of the configured retirement age, not already exited/in-flight
$retirementAlerts = [];
foreach ($employees as $e) {
    if (empty($e['dob']) || $e['dob'] === '0000-00-00') continue;
    $age = floor((strtotime(date('Y-m-d')) - strtotime($e['dob'])) / (365.25 * 24 * 60 * 60));
    if ($age >= $retirementAge - 1) {
        $already = mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_requests WHERE employee_id={$e['id']} AND exit_type='retirement' AND status NOT IN ('rejected','retained')")) > 0;
        if (!$already) {
            $retirementDate = date('Y-m-d', strtotime($e['dob'] . " +{$retirementAge} years"));
            $retirementAlerts[] = array_merge($e, ['age' => $age, 'retirement_date' => $retirementDate]);
        }
    }
}

// Contract-end alerts — fixed-term employees whose contract_end_date is within 60 days
$contractAlerts = [];
foreach ($employees as $e) {
    if (empty($e['contract_end_date']) || $e['contract_end_date'] === '0000-00-00') continue;
    $daysLeft = floor((strtotime($e['contract_end_date']) - strtotime(date('Y-m-d'))) / 86400);
    if ($daysLeft <= 60) {
        $already = mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_requests WHERE employee_id={$e['id']} AND exit_type='contract_end' AND status NOT IN ('rejected')")) > 0;
        if (!$already) $contractAlerts[] = array_merge($e, ['days_left' => $daysLeft]);
    }
}

$activeTab = $_GET['tab'] ?? 'requests';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Exit Initiation & Approval</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--red:#ef4444;--amber:#f59e0b;--green:#10b981;--gray-bg:#f0f4f8;}
*{box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--gray-bg);margin:0;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:20px 30px;border-radius:12px;margin:20px;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-weight:800;font-size:1.3rem;margin:0;}
.hdr p{color:rgba(255,255,255,.7);font-size:12px;margin:4px 0 0;}
.wrap{max-width:1200px;margin:0 auto;padding:0 20px 30px;}
.tab-bar{display:flex;gap:6px;background:#fff;padding:6px;border-radius:12px;border:1px solid #e2e8f0;margin-bottom:18px;flex-wrap:wrap;}
.tab-bar a{flex:1;min-width:120px;text-align:center;padding:10px;border-radius:8px;font-weight:700;font-size:12.5px;color:#64748b;text-decoration:none;}
.tab-bar a.active{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;}
.card-box{background:#fff;border-radius:12px;padding:22px;box-shadow:0 2px 10px rgba(0,0,0,.06);margin-bottom:18px;}
.card-box h5{font-weight:800;color:var(--navy);margin-bottom:14px;font-size:15px;}
.fc{border:2px solid #e2e8f0;border-radius:8px;padding:9px 12px;font-size:13px;font-weight:600;width:100%;}
label.fl{font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;}
.fg{margin-bottom:12px;}
.btn-p{padding:9px 18px;border:none;border-radius:8px;font-weight:700;font-size:12px;cursor:pointer;color:#fff;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));}
.btn-green{background:linear-gradient(135deg,var(--green),#059669);}
.btn-red{background:linear-gradient(135deg,var(--red),#b91c1c);}
.btn-amber{background:linear-gradient(135deg,var(--amber),#b45309);}
table{width:100%;border-collapse:collapse;}
th{background:#f0f4f8;color:var(--navy);font-weight:800;font-size:11px;text-transform:uppercase;padding:10px 12px;text-align:left;}
td{padding:10px 12px;border-bottom:1px solid #f1f5f9;font-size:12.5px;}
.badge{padding:4px 10px;border-radius:12px;font-size:11px;font-weight:800;}
.b-pending{background:#fef3c7;color:#92400e;}
.b-approved{background:#d1fae5;color:#065f46;}
.b-retained{background:#dbeafe;color:#1e40af;}
.b-rejected{background:#fee2e2;color:#991b1b;}
.b-status{background:#dbeafe;color:#1e40af;}
.link-box{display:flex;gap:8px;align-items:center;background:#f8faff;border:1px solid #e0e7ff;border-radius:8px;padding:10px 12px;font-size:12px;font-family:monospace;word-break:break-all;}
.timeline-item{position:relative;padding:0 0 18px 26px;border-left:2px solid #e2e8f0;margin-left:6px;}
.timeline-item:last-child{border-left-color:transparent;padding-bottom:0;}
.timeline-item::before{content:'';position:absolute;left:-7px;top:2px;width:12px;height:12px;border-radius:50%;background:var(--blue);border:2px solid #fff;box-shadow:0 0 0 2px var(--blue);}
.timeline-label{font-weight:800;font-size:13px;color:var(--navy);}
.timeline-meta{font-size:11px;color:#94a3b8;margin:2px 0 4px;}
.timeline-detail{font-size:12.5px;color:#475569;}
@media print{
  body *{visibility:hidden;}
  .modal.show, .modal.show *{visibility:visible;}
  .modal.show{position:absolute;left:0;top:0;width:100%;}
  .modal-dialog{max-width:100%;margin:0;}
  .modal-footer .btn-p, .modal-header .close{display:none!important;}
}
</style>
</head>
<body>
<div class="hdr"><h1><i class="fas fa-door-open mr-2"></i>Exit Initiation & Approval</h1><p>Resignation, Termination, Retirement & Contract End — all four initiation paths</p></div>
<div class="wrap">

<?php if (isset($_SESSION['success_message'])): ?>
<div class="alert alert-success"><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?></div>
<?php endif; ?>

<div class="tab-bar">
  <a href="?tab=requests" class="<?php echo $activeTab=='requests'?'active':''; ?>"><i class="fas fa-list mr-1"></i>Exit Requests</a>
  <a href="?tab=link" class="<?php echo $activeTab=='link'?'active':''; ?>"><i class="fas fa-link mr-1"></i>Resignation Link</a>
  <a href="?tab=new" class="<?php echo $activeTab=='new'?'active':''; ?>"><i class="fas fa-plus mr-1"></i>Termination / Manual Exit</a>
  <a href="?tab=retirement" class="<?php echo $activeTab=='retirement'?'active':''; ?>"><i class="fas fa-user-clock mr-1"></i>Retirement Alerts <?php if(count($retirementAlerts)) echo '('.count($retirementAlerts).')'; ?></a>
  <a href="?tab=contract" class="<?php echo $activeTab=='contract'?'active':''; ?>"><i class="fas fa-file-contract mr-1"></i>Contract Alerts <?php if(count($contractAlerts)) echo '('.count($contractAlerts).')'; ?></a>
  <a href="?tab=policy" class="<?php echo $activeTab=='policy'?'active':''; ?>"><i class="fas fa-cog mr-1"></i>Policy</a>
</div>

<?php if ($activeTab === 'link'): ?>
<!-- ================= RESIGNATION LINK (same pattern as Offer Letter links) ================= -->
<div class="card-box">
  <h5><i class="fas fa-link mr-2"></i>Generate a Resignation Link</h5>
  <p style="color:#64748b;font-size:13px;">Employees do not get open self-service access to a resignation form. Generate a unique, employee-specific link here and share it with that employee only — they'll use it to formally submit their resignation.</p>
  <form method="POST">
    <input type="hidden" name="action" value="generate_resignation_link">
    <div class="fg"><label class="fl">Employee</label>
      <select name="employee_id" class="fc" required>
        <option value="">-- Select Employee --</option>
        <?php foreach ($employees as $e): ?>
        <option value="<?php echo $e['id']; ?>"><?php echo htmlspecialchars($e['name'].' — '.($e['position']??'').' / '.($e['department']??'')); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fg"><label class="fl">Link Valid For (days)</label><input type="number" name="link_expiry_days" class="fc" value="<?php echo RESIGNATION_LINK_EXPIRY_DAYS; ?>" min="1" max="90" required></div>
    <div class="fg"><label class="fl">Reason Category (from your in-person discussion)</label>
      <select name="link_reason_category" class="fc">
        <?php foreach ($reasonCategories as $rc): ?>
        <option value="<?php echo htmlspecialchars($rc); ?>"><?php echo htmlspecialchars($rc); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fg"><label class="fl">Reason / Notes</label><textarea name="link_reason" class="fc" style="height:70px;" placeholder="What the employee told you in the in-person discussion..."></textarea></div>
    <button type="submit" class="btn-p btn-navy"><i class="fas fa-link mr-1"></i> Generate Link</button>
  </form>
</div>

<div class="card-box">
  <h5><i class="fas fa-clock mr-2"></i>Links Awaiting Employee Submission</h5>
  <table><thead><tr><th>Employee</th><th>Reason</th><th>Generated</th><th>Expires</th><th>Notified</th><th>Link / Actions</th></tr></thead><tbody>
  <?php foreach ($linkRequests as $r):
    $link = $base_url . '/hr-employee-exit-request.php?token=' . $r['token'];
    $expired = $r['link_expires_at'] && strtotime($r['link_expires_at']) < time();
    $expiresLabel = $r['link_expires_at'] ? date('d M Y', strtotime($r['link_expires_at'])) : '—';
    $empEmail = ''; $empPhone = '';
    $empFull = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$r['employee_id']} LIMIT 1"));
    if ($empFull) { $empEmail = $empFull['email'] ?? $empFull['personal_email'] ?? ''; $empPhone = $empFull['phone'] ?? $empFull['mobile'] ?? ''; }
  ?>
  <tr>
    <td><?php echo htmlspecialchars($r['employee_name'] ?? '—'); ?><br><small style="color:#94a3b8;">by <?php echo htmlspecialchars($r['link_generated_by'] ?? '—'); ?>, <?php echo $r['link_generated_at'] ? date('d M Y', strtotime($r['link_generated_at'])) : '—'; ?></small></td>
    <td><span class="badge b-status"><?php echo htmlspecialchars($r['link_reason_category'] ?? '—'); ?></span><?php if ($r['link_reason']): ?><br><small style="color:#64748b;"><?php echo htmlspecialchars($r['link_reason']); ?></small><?php endif; ?></td>
    <td><?php echo $r['link_generated_at'] ? date('d M Y, h:i A', strtotime($r['link_generated_at'])) : '—'; ?></td>
    <td><span class="badge <?php echo $expired ? 'b-rejected' : 'b-approved'; ?>"><?php echo $expiresLabel; ?><?php echo $expired ? ' (Expired)' : ''; ?></span></td>
    <td>
      <?php if ($r['link_notified_at']): ?>
      <span class="badge b-approved">via <?php echo htmlspecialchars(ucfirst($r['link_notify_channel'])); ?></span><br><small style="color:#64748b;"><?php echo date('d M Y, h:i A', strtotime($r['link_notified_at'])); ?></small>
      <?php else: ?>
      <span class="badge b-pending">Not notified</span>
      <?php endif; ?>
    </td>
    <td>
      <div class="link-box" style="margin-bottom:6px;">
        <span id="link-<?php echo $r['id']; ?>" style="flex:1;"><?php echo htmlspecialchars($link); ?></span>
        <button type="button" class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" onclick="copyLink('link-<?php echo $r['id']; ?>')"><i class="fas fa-copy"></i></button>
      </div>
      <button type="button" class="btn-p" style="padding:5px 10px;font-size:11px;background:#6366f1;" onclick="openLinkNotifyModal(<?php echo $r['id']; ?>, <?php echo $j($r['employee_name'] ?? ''); ?>, <?php echo $j($empEmail); ?>, <?php echo $j($empPhone); ?>, <?php echo $j($link); ?>, <?php echo $j($r['link_reason_category'] ?? ''); ?>, <?php echo $j($expiresLabel); ?>)"><i class="fas fa-paper-plane mr-1"></i> Notify Candidate</button>
    </td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($linkRequests)): ?><tr><td colspan="6" style="text-align:center;color:#94a3b8;padding:30px;">No links generated yet.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<!-- Notify Candidate overlay — same Email+WhatsApp modal pattern as hr_screening.php's roundNotifyModal -->
<div class="modal fade" id="linkNotifyModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <div class="modal-header" style="background:#f8faff;border-bottom:1px solid #e0e7ff;">
      <h5 class="modal-title" style="font-weight:800;color:var(--navy);"><i class="fas fa-paper-plane mr-2 text-primary"></i>Notify Candidate: Resignation Link</h5>
      <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px;">
      <input type="hidden" id="ln_id">
      <input type="hidden" id="ln_phone">

      <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
        <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
        <div class="fg"><label class="fl">To</label><input type="email" id="ln_email_to" class="fc"></div>
        <div class="fg"><label class="fl">Subject</label><input type="text" id="ln_email_subj" class="fc"></div>
        <div class="fg"><label class="fl">Message</label><textarea id="ln_email_body" class="fc" style="height:160px;resize:vertical;"></textarea></div>
        <button type="button" onclick="sendLinkEmail()" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Send Email Now</button>
      </div>

      <div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;">
        <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
        <div class="fg"><label class="fl">Phone Number</label><input type="text" id="ln_phone_display" class="fc" placeholder="+91XXXXXXXXXX"></div>
        <textarea id="ln_wa_msg" class="fc" style="height:120px;resize:vertical;"></textarea>
        <div style="margin-top:10px;"><button type="button" onclick="openLinkWhatsApp()" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp mr-1"></i> Open WhatsApp</button></div>
      </div>
    </div>
  </div></div>
</div>

<script>
function copyLink(id) {
  var text = document.getElementById(id).innerText;
  navigator.clipboard.writeText(text).then(function(){ alert('Link copied to clipboard.'); });
}

function openLinkNotifyModal(id, empName, empEmail, empPhone, link, category, expiresLabel) {
  document.getElementById('ln_id').value = id;
  document.getElementById('ln_phone').value = empPhone;
  document.getElementById('ln_phone_display').value = empPhone || '';

  var subj = "Resignation Submission Link — " + empName;
  var msg = "Hi " + empName + ",\n\n" +
    "As discussed (" + (category || "your resignation") + "), please use the secure link below to formally submit your resignation:\n\n" +
    link + "\n\n" +
    "This link is unique to you and valid until " + expiresLabel + ". Please do not share it with anyone else.\n\n" +
    "Warm Regards,\nHR Team";

  document.getElementById('ln_email_to').value = empEmail || '';
  document.getElementById('ln_email_subj').value = subj;
  document.getElementById('ln_email_body').value = msg;
  document.getElementById('ln_wa_msg').value = msg;

  $('#linkNotifyModal').modal('show');
}

function sendLinkEmail() {
  var id = document.getElementById('ln_id').value;
  var to = document.getElementById('ln_email_to').value.trim();
  var subj = document.getElementById('ln_email_subj').value.trim();
  var body = document.getElementById('ln_email_body').value.trim();
  if (!to) { alert('Recipient email is required.'); return; }
  if (!confirm('Send this email to ' + to + '?')) return;

  var btn = event.currentTarget;
  var oldHtml = btn.innerHTML;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Sending...';
  btn.disabled = true;

  $.post(window.location.pathname, { ajax_send_link_email: 1, id: id, to: to, subject: subj, body: body }, function(resp) {
    if (resp.success) { alert('Email sent.'); $('#linkNotifyModal').modal('hide'); location.reload(); }
    else { alert(resp.message || 'Could not send email.'); }
  }, 'json').fail(function() {
    alert('Server error while sending email.');
  }).always(function() {
    btn.innerHTML = oldHtml;
    btn.disabled = false;
  });
}

function openLinkWhatsApp() {
  var id = document.getElementById('ln_id').value;
  var phoneEl = document.getElementById('ln_phone_display');
  var phone = phoneEl ? phoneEl.value.replace(/[^0-9]/g, '') : '';
  var msg = document.getElementById('ln_wa_msg').value;
  if (!phone) { alert('Enter a phone number.'); return; }
  window.open('https://wa.me/' + phone + '?text=' + encodeURIComponent(msg), '_blank');
  $('#linkNotifyModal').modal('hide');
  $.post(window.location.pathname, { ajax_mark_link_notified: 1, id: id }, function() { location.reload(); }, 'json');
}

<?php
$autoOpenId = (isset($_GET['generated']) && isset($_GET['new_id'])) ? intval($_GET['new_id']) : 0;
$autoOpenRow = null;
if ($autoOpenId > 0) {
    foreach ($linkRequests as $r) { if (intval($r['id']) === $autoOpenId) { $autoOpenRow = $r; break; } }
}
?>
<?php if ($autoOpenRow):
    $autoLink = $base_url . '/hr-employee-exit-request.php?token=' . $autoOpenRow['token'];
    $autoExpires = $autoOpenRow['link_expires_at'] ? date('d M Y', strtotime($autoOpenRow['link_expires_at'])) : '—';
    $autoEmpFull = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$autoOpenRow['employee_id']} LIMIT 1"));
    $autoEmail = $autoEmpFull ? ($autoEmpFull['email'] ?? $autoEmpFull['personal_email'] ?? '') : '';
    $autoPhone = $autoEmpFull ? ($autoEmpFull['phone'] ?? $autoEmpFull['mobile'] ?? '') : '';
?>
// Generating a link opens the Notify overlay immediately, with the expiry
// date and message already filled in — nothing further to look up.
$(function() {
  openLinkNotifyModal(
    <?php echo $j($autoOpenRow['id']); ?>,
    <?php echo $j($autoOpenRow['employee_name'] ?? ''); ?>,
    <?php echo $j($autoEmail); ?>,
    <?php echo $j($autoPhone); ?>,
    <?php echo $j($autoLink); ?>,
    <?php echo $j($autoOpenRow['link_reason_category'] ?? ''); ?>,
    <?php echo $j($autoExpires); ?>
  );
});
<?php endif; ?>
</script>

<?php elseif ($activeTab === 'retirement'): ?>
<!-- ================= RETIREMENT ALERTS ================= -->
<div class="card-box">
  <h5><i class="fas fa-user-clock mr-2"></i>Retirement Age Policy</h5>
  <form method="POST" class="form-inline">
    <input type="hidden" name="action" value="save_retirement_age">
    <label class="fl mr-2" style="margin-bottom:0;">Company Retirement Age</label>
    <input type="number" name="retirement_age" class="fc mr-2" style="max-width:120px;" value="<?php echo $retirementAge; ?>" required>
    <button type="submit" class="btn-p btn-navy">Save</button>
  </form>
</div>
<div class="card-box">
  <h5><i class="fas fa-bell mr-2"></i>Employees Approaching Retirement (age <?php echo $retirementAge-1; ?>+)</h5>
  <table><thead><tr><th>Employee</th><th>DOB</th><th>Current Age</th><th>Eligible Retirement Date</th><th>Action</th></tr></thead><tbody>
  <?php foreach ($retirementAlerts as $e): ?>
  <tr>
    <td><?php echo htmlspecialchars($e['name']); ?><br><small style="color:#94a3b8;"><?php echo htmlspecialchars($e['department']??''); ?></small></td>
    <td><?php echo date('d M Y', strtotime($e['dob'])); ?></td>
    <td><?php echo $e['age']; ?></td>
    <td><strong><?php echo date('d M Y', strtotime($e['retirement_date'])); ?></strong></td>
    <td>
      <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#retModal<?php echo $e['id']; ?>">Confirm Retirement</button>
      <div class="modal fade" id="retModal<?php echo $e['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
        <div class="modal-header"><h6 style="font-weight:800;">Confirm Retirement — <?php echo htmlspecialchars($e['name']); ?></h6></div>
        <form method="POST">
          <input type="hidden" name="action" value="initiate_exit_then_confirm_retirement">
          <div class="modal-body">
            <input type="hidden" name="employee_id" value="<?php echo $e['id']; ?>">
            <div class="fg"><label class="fl">Effective Retirement / Last Working Day</label><input type="date" name="requested_last_day" class="fc" value="<?php echo $e['retirement_date']; ?>" required></div>
            <div class="fg"><label class="fl">Remarks (e.g. extension / consultancy discussion)</label><textarea name="reason" class="fc" style="height:60px;"></textarea></div>
          </div>
          <div class="modal-footer"><button type="submit" class="btn-p btn-green">Confirm & Issue Letter</button></div>
        </form>
      </div></div></div>
    </td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($retirementAlerts)): ?><tr><td colspan="5" style="text-align:center;color:#94a3b8;padding:30px;">No employees approaching retirement.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<?php elseif ($activeTab === 'contract'): ?>
<!-- ================= CONTRACT-END ALERTS ================= -->
<div class="card-box">
  <h5><i class="fas fa-file-contract mr-2"></i>Contracts Ending Within 60 Days</h5>
  <table><thead><tr><th>Employee</th><th>Type</th><th>Contract End Date</th><th>Days Left</th><th>Action</th></tr></thead><tbody>
  <?php foreach ($contractAlerts as $e): ?>
  <tr>
    <td><?php echo htmlspecialchars($e['name']); ?><br><small style="color:#94a3b8;"><?php echo htmlspecialchars($e['department']??''); ?></small></td>
    <td><?php echo htmlspecialchars($e['employee_type']??''); ?></td>
    <td><?php echo date('d M Y', strtotime($e['contract_end_date'])); ?></td>
    <td><?php echo $e['days_left'] < 0 ? 'Overdue' : $e['days_left'].' days'; ?></td>
    <td>
      <button class="btn-p btn-green" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#renewModal<?php echo $e['id']; ?>">Renew</button>
      <button class="btn-p btn-red" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#nonRenewModal<?php echo $e['id']; ?>">Non-Renew</button>

      <div class="modal fade" id="renewModal<?php echo $e['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
        <div class="modal-header"><h6 style="font-weight:800;">Renew Contract — <?php echo htmlspecialchars($e['name']); ?></h6></div>
        <form method="POST"><input type="hidden" name="action" value="renew_contract"><input type="hidden" name="employee_id" value="<?php echo $e['id']; ?>">
          <div class="modal-body"><div class="fg"><label class="fl">New Contract End Date</label><input type="date" name="new_contract_end_date" class="fc" required></div></div>
          <div class="modal-footer"><button type="submit" class="btn-p btn-green">Renew — No Exit Triggered</button></div>
        </form>
      </div></div></div>

      <div class="modal fade" id="nonRenewModal<?php echo $e['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
        <div class="modal-header"><h6 style="font-weight:800;">Non-Renew — <?php echo htmlspecialchars($e['name']); ?></h6></div>
        <form method="POST"><input type="hidden" name="action" value="initiate_exit_then_confirm_non_renewal"><input type="hidden" name="employee_id" value="<?php echo $e['id']; ?>">
          <div class="modal-body">
            <input type="hidden" name="requested_last_day" value="<?php echo $e['contract_end_date']; ?>">
            <p style="font-size:13px;">Exit date is the pre-agreed contract end date: <strong><?php echo date('d M Y', strtotime($e['contract_end_date'])); ?></strong>. No separate notice period applies.</p>
          </div>
          <div class="modal-footer"><button type="submit" class="btn-p btn-red">Confirm Non-Renewal & Issue Notification</button></div>
        </form>
      </div></div></div>
    </td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($contractAlerts)): ?><tr><td colspan="5" style="text-align:center;color:#94a3b8;padding:30px;">No contracts ending soon.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<?php elseif ($activeTab === 'new'): ?>
<!-- ================= TERMINATION / MANUAL EXIT ================= -->
<div class="card-box">
  <h5><i class="fas fa-user-minus mr-2"></i>Initiate Termination (Involuntary Exit)</h5>
  <p style="color:#64748b;font-size:12.5px;">Resignation is submitted only via an employee-specific link (see the "Resignation Link" tab). Retirement and Contract End are raised from their Alert tabs when auto-flagged, or manually below.</p>
  <form method="POST">
    <input type="hidden" name="action" value="initiate_exit">
    <div class="fg"><label class="fl">Employee</label>
      <select name="employee_id" class="fc" required>
        <option value="">-- Select Employee --</option>
        <?php foreach ($employees as $e): ?>
        <option value="<?php echo $e['id']; ?>"><?php echo htmlspecialchars($e['name'].' — '.($e['position']??'').' / '.($e['department']??'')); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fg"><label class="fl">Exit Type</label>
      <select name="exit_type" id="exitTypeSel" class="fc" onchange="document.getElementById('termFields').style.display=this.value=='termination'?'block':'none';">
        <option value="termination">Termination (Involuntary)</option>
        <option value="retirement">Retirement (manual entry)</option>
        <option value="contract_end">Contract End (manual entry)</option>
      </select>
    </div>

    <div id="termFields">
      <div class="fg"><label class="fl">Termination Type</label>
        <select name="termination_type" class="fc">
          <option value="performance">Performance-based</option>
          <option value="misconduct">Misconduct</option>
          <option value="redundancy">Redundancy</option>
          <option value="layoff">Layoff</option>
        </select>
      </div>
      <div class="fg"><label class="fl">Warning Letter / Disciplinary Record Reference (if misconduct)</label><input type="text" name="warning_letter_ref" class="fc" placeholder="e.g. WL-2026-014"></div>
      <div class="fg"><label class="fl">Second-Level Approver (senior HR / department head — must differ from initiator)</label>
        <select name="second_approver_name" class="fc">
          <option value="">-- Select --</option>
          <?php foreach ($employees as $e): ?>
          <option value="<?php echo htmlspecialchars($e['name']); ?>"><?php echo htmlspecialchars($e['name'].' — '.($e['position']??'')); ?></option>
          <?php endforeach; ?>
        </select>
      </div>
    </div>

    <div class="fg"><label class="fl">Documented Reason (mandatory)</label><textarea name="reason" id="exitReason" class="fc" style="height:80px;" placeholder="Written justification..." required></textarea></div>
    <div class="fg"><label class="fl">Proposed Last Working Day</label><input type="date" name="requested_last_day" class="fc" required></div>

    <div class="fg" style="border-top:1px solid #f1f5f9;padding-top:16px;">
      <label style="display:flex;align-items:center;gap:8px;font-weight:700;font-size:13px;color:var(--navy);cursor:pointer;">
        <input type="checkbox" name="raise_ticket" id="raiseTicketToggle" value="1" onchange="document.getElementById('ticketSection').style.display=this.checked?'block':'none'; if(this.checked) prefillTicket();" style="width:16px;height:16px;">
        Raise a ticket to notify team members about this exit
      </label>
    </div>

    <div id="ticketSection" style="display:none;background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:16px;margin-bottom:16px;">
      <div class="fg"><label class="fl">Ticket Subject</label><input type="text" name="ticket_subject" id="ticketSubject" class="fc"></div>
      <div class="fg"><label class="fl">Ticket Message (predefined — edit if needed)</label><textarea name="ticket_message" id="ticketMessage" class="fc" style="height:90px;"></textarea></div>
      <div class="row">
        <div class="col-md-6 fg"><label class="fl">Priority</label>
          <select name="ticket_priority" class="fc">
            <option value="high">High</option>
            <option value="medium" selected>Medium</option>
            <option value="low">Low</option>
          </select>
        </div>
        <div class="col-md-6 fg"><label class="fl">Resolve Within</label>
          <select name="ticket_timeline" class="fc">
            <option value="1440" selected>24 Hours</option>
            <option value="2880">48 Hours</option>
            <option value="10080">1 Week</option>
          </select>
        </div>
      </div>
      <div class="fg">
        <label class="fl">Send To (select one or more employees — e.g. IT, Finance, Admin, Manager)</label>
        <div style="max-height:180px;overflow-y:auto;border:2px solid #e2e8f0;border-radius:8px;padding:10px 14px;background:#fff;">
          <?php foreach ($employees as $e): ?>
          <label style="display:flex;align-items:center;gap:8px;font-weight:600;font-size:13px;padding:5px 0;cursor:pointer;">
            <input type="checkbox" name="ticket_assignees[]" value="<?php echo $e['id']; ?>"> <?php echo htmlspecialchars($e['name'].' — '.($e['position']??'')); ?>
          </label>
          <?php endforeach; ?>
        </div>
      </div>
    </div>

    <button type="submit" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Submit</button>
  </form>
</div>
<script>
function prefillTicket() {
  var empSelect = document.querySelector('select[name="employee_id"]');
  var empName = empSelect && empSelect.value ? empSelect.options[empSelect.selectedIndex].text.split(' — ')[0] : '[Employee]';
  var exitType = document.getElementById('exitTypeSel').value;
  var typeLabel = {termination:'termination', retirement:'retirement', contract_end:'contract end'}[exitType] || 'exit';

  document.getElementById('ticketSubject').value = 'Exit Coordination Required — ' + empName;
  document.getElementById('ticketMessage').value =
    empName + ' has an exit in progress (' + typeLabel + '). Please begin the relevant handover, clearance, or coordination steps on your side and confirm once complete.\n\nReason: ' +
    (document.getElementById('exitReason').value || 'As discussed') +
    '\n\nThis ticket was raised automatically from the Exit Initiation form.';
}
document.querySelector('select[name="employee_id"]').addEventListener('change', function() { if (document.getElementById('raiseTicketToggle').checked) prefillTicket(); });
document.getElementById('exitTypeSel').addEventListener('change', function() { if (document.getElementById('raiseTicketToggle').checked) prefillTicket(); });
</script>

<?php elseif ($activeTab === 'policy'): ?>
<div class="card-box">
  <h5><i class="fas fa-calendar-alt mr-2"></i>Set Notice Period (per Department)</h5>
  <form method="POST">
    <input type="hidden" name="action" value="save_notice_policy">
    <div class="row">
      <div class="col-md-6 fg"><label class="fl">Department</label>
        <select name="department_id" class="fc" required>
          <option value="">-- Select --</option>
          <?php foreach ($departments as $d): ?>
          <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
          <?php endforeach; ?>
        </select>
      </div>
      <div class="col-md-6 fg"><label class="fl">Notice Days</label><input type="number" name="notice_days" class="fc" value="30" required></div>
    </div>
    <button type="submit" class="btn-p btn-navy"><i class="fas fa-save mr-1"></i> Save Policy</button>
  </form>
</div>
<div class="card-box">
  <h5>Current Policies</h5>
  <table><thead><tr><th>Department</th><th>Notice Days</th></tr></thead><tbody>
  <?php foreach ($policies as $p): ?>
  <tr><td><?php echo htmlspecialchars($p['dept_name'] ?? 'N/A'); ?></td><td><?php echo $p['notice_days']; ?> days</td></tr>
  <?php endforeach; ?>
  <?php if (empty($policies)): ?><tr><td colspan="2" style="text-align:center;color:#94a3b8;">No policies set yet — default is 30 days.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<?php else: ?>
<!-- ================= EXIT REQUESTS LIST ================= -->
<div class="card-box">
  <h5><i class="fas fa-list mr-2"></i>All Exit Requests</h5>
  <table>
    <thead><tr><th>Exit #</th><th>Employee</th><th>Type</th><th>Last Day</th><th>Status</th><th>Action</th><th>History</th></tr></thead>
    <tbody>
    <?php foreach ($requests as $r): ?>
    <tr>
      <td><strong><?php echo htmlspecialchars($r['exit_number']); ?></strong></td>
      <td><?php echo htmlspecialchars($r['employee_name'] ?? '—'); ?><br><small style="color:#94a3b8;"><?php echo htmlspecialchars($r['department'] ?? ''); ?></small></td>
      <td><?php echo ucfirst(str_replace('_',' ',$r['exit_type'])); ?></td>
      <td><?php echo $r['final_last_working_day'] ? date('d M Y', strtotime($r['final_last_working_day'])) : ($r['requested_last_day'] ? date('d M Y', strtotime($r['requested_last_day'])).' (requested)' : '—'); ?></td>
      <td><span class="badge b-status"><?php echo ucfirst(str_replace('_',' ',$r['status'])); ?></span>
          <?php if ($r['manager_approval']=='retained'): ?><br><span class="badge b-retained">Retained by Manager</span>
          <?php elseif ($r['hr_approval']=='retained'): ?><br><span class="badge b-retained">Retained by HR</span><?php endif; ?>
      </td>
      <td>
        <?php if ($r['exit_type']=='resignation'): ?>
          <?php if ($r['hr_approval']=='pending'): ?>
          <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#hrModal<?php echo $r['id']; ?>">HR Discussion</button>
          <div class="modal fade" id="hrModal<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
            <div class="modal-header"><h6 style="font-weight:800;">HR Decision — <?php echo htmlspecialchars($r['exit_number']); ?></h6></div>
            <form method="POST"><input type="hidden" name="action" value="hr_decision"><input type="hidden" name="id" value="<?php echo $r['id']; ?>">
            <div class="modal-body">
              <div class="fg"><label class="fl">Employee's Reason for Leaving</label><div style="background:#f8fafc;border-radius:8px;padding:10px;font-size:13px;"><?php echo nl2br(htmlspecialchars($r['reason'] ?: '—')); ?></div></div>
              <div class="fg"><label class="fl">Requested Last Working Day</label><div style="font-size:13px;font-weight:700;"><?php echo $r['requested_last_day'] ? date('d M Y', strtotime($r['requested_last_day'])) : '—'; ?></div></div>
              <div class="fg"><label class="fl">Remarks</label><textarea name="hr_remarks" class="fc" style="height:60px;"></textarea></div>
            </div>
            <div class="modal-footer">
              <button type="submit" name="decision" value="retained" class="btn-p btn-amber">Retained by HR</button>
              <button type="submit" name="decision" value="approved" class="btn-p btn-green">Approved — Forward to Manager</button>
            </div></form>
          </div></div></div>
          <?php elseif ($r['hr_approval']=='approved' && $r['manager_approval']=='pending'): ?>
          <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#mgrModal<?php echo $r['id']; ?>">Manager Discussion</button>
          <div class="modal fade" id="mgrModal<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
            <div class="modal-header"><h6 style="font-weight:800;">Manager Decision — <?php echo htmlspecialchars($r['exit_number']); ?></h6></div>
            <form method="POST"><input type="hidden" name="action" value="manager_decision"><input type="hidden" name="id" value="<?php echo $r['id']; ?>">
            <div class="modal-body">
              <div class="fg"><label class="fl">Employee's Reason for Leaving</label><div style="background:#f8fafc;border-radius:8px;padding:10px;font-size:13px;"><?php echo nl2br(htmlspecialchars($r['reason'] ?: '—')); ?></div></div>
              <div class="fg"><label class="fl">Requested Last Working Day</label><div style="font-size:13px;font-weight:700;"><?php echo $r['requested_last_day'] ? date('d M Y', strtotime($r['requested_last_day'])) : '—'; ?></div></div>
              <?php if ($r['hr_remarks']): ?><div class="fg"><label class="fl">HR Remarks</label><div style="font-size:13px;color:#64748b;"><?php echo nl2br(htmlspecialchars($r['hr_remarks'])); ?></div></div><?php endif; ?>
              <?php $mgrDefaultLastDay = date('Y-m-d', strtotime('+' . intval($r['policy_notice_days']) . ' days')); ?>
              <div class="fg"><label class="fl">Final Last Working Day (if approving — defaults to today + <?php echo intval($r['policy_notice_days']); ?> day notice policy, but you can set any date)</label><input type="date" name="final_last_working_day" class="fc" value="<?php echo $mgrDefaultLastDay; ?>"></div>
              <div class="fg"><label class="fl">Remarks</label><textarea name="manager_remarks" class="fc" style="height:60px;"></textarea></div>
            </div>
            <div class="modal-footer">
              <button type="submit" name="decision" value="retained" class="btn-p btn-amber">Retained by Manager</button>
              <button type="submit" name="decision" value="approved" class="btn-p btn-green">Approved — Start Notice Period</button>
            </div></form>
          </div></div></div>
          <?php elseif ($r['status']=='approved'): ?>
          <a href="hr-exit-handover.php?exit_id=<?php echo $r['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;padding:5px 10px;font-size:11px;">Next: Handover →</a>
          <?php else: ?>—<?php endif; ?>

        <?php elseif ($r['exit_type']=='termination'): ?>
          <?php if ($r['second_approval']=='pending'): ?>
          <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#secModal<?php echo $r['id']; ?>">Second Approval</button>
          <div class="modal fade" id="secModal<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
            <div class="modal-header"><h6 style="font-weight:800;">Compliance Review — <?php echo htmlspecialchars($r['exit_number']); ?></h6></div>
            <div class="modal-body" style="font-size:13px;">
              <p><strong>Type:</strong> <?php echo ucfirst($r['termination_type']??''); ?> &nbsp; <strong>Reason:</strong> <?php echo htmlspecialchars($r['reason']); ?></p>
              <p><strong>Initiated by:</strong> <?php echo htmlspecialchars($r['initiated_by']); ?> &nbsp; <strong>Designated approver:</strong> <?php echo htmlspecialchars($r['second_approver_name']??'—'); ?></p>
              <?php if ($r['warning_letter_ref']): ?><p><strong>Warning Letter Ref:</strong> <?php echo htmlspecialchars($r['warning_letter_ref']); ?></p><?php endif; ?>
            </div>
            <form method="POST"><input type="hidden" name="action" value="second_decision"><input type="hidden" name="id" value="<?php echo $r['id']; ?>">
            <div class="modal-footer">
              <button type="submit" name="decision" value="rejected" class="btn-p btn-red">Reject</button>
              <button type="submit" name="decision" value="approved" class="btn-p btn-green">Approve</button>
            </div></form>
          </div></div></div>
          <?php elseif ($r['second_approval']=='approved' && !$r['notice_handling']): ?>
          <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#finModal<?php echo $r['id']; ?>">Set Notice & Issue Letter</button>
          <div class="modal fade" id="finModal<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
            <div class="modal-header"><h6 style="font-weight:800;">Finalize Termination — <?php echo htmlspecialchars($r['exit_number']); ?></h6></div>
            <form method="POST"><input type="hidden" name="action" value="finalize_termination"><input type="hidden" name="id" value="<?php echo $r['id']; ?>">
            <div class="modal-body">
              <div class="fg"><label class="fl">Notice Handling</label>
                <select name="notice_handling" class="fc">
                  <option value="served">Notice period served</option>
                  <option value="pay_in_lieu">Pay in lieu of notice</option>
                  <option value="immediate">Immediate termination (gross misconduct)</option>
                </select>
              </div>
              <div class="fg"><label class="fl">Effective Last Working Day</label><input type="date" name="final_last_working_day" class="fc" value="<?php echo $r['requested_last_day']; ?>" required></div>
            </div>
            <div class="modal-footer"><button type="submit" class="btn-p btn-green">Issue Termination Letter</button></div>
            </form>
          </div></div></div>
          <?php elseif ($r['status']=='approved'): ?>
          <a href="hr-exit-handover.php?exit_id=<?php echo $r['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;padding:5px 10px;font-size:11px;">Next: Handover →</a>
          <?php else: ?>—<?php endif; ?>

        <?php elseif ($r['exit_type']=='retirement'): ?>
          <?php if ($r['status']=='initiated'): ?>
          <button class="btn-p btn-navy" style="padding:5px 10px;font-size:11px;" data-toggle="modal" data-target="#retConfirm<?php echo $r['id']; ?>">Confirm Retirement</button>
          <div class="modal fade" id="retConfirm<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content" style="border-radius:12px;">
            <div class="modal-header"><h6 style="font-weight:800;">Confirm Retirement — <?php echo htmlspecialchars($r['exit_number']); ?></h6></div>
            <form method="POST"><input type="hidden" name="action" value="confirm_retirement"><input type="hidden" name="id" value="<?php echo $r['id']; ?>">
            <div class="modal-body">
              <div class="fg"><label class="fl">Effective Last Working Day</label><input type="date" name="final_last_working_day" class="fc" value="<?php echo $r['requested_last_day']; ?>" required></div>
              <div class="fg"><label class="fl">Remarks</label><textarea name="hr_remarks" class="fc" style="height:60px;"><?php echo htmlspecialchars($r['reason']??''); ?></textarea></div>
            </div>
            <div class="modal-footer"><button type="submit" class="btn-p btn-green">Confirm & Issue Letter</button></div>
            </form>
          </div></div></div>
          <?php elseif ($r['status']=='approved'): ?>
          <a href="hr-exit-handover.php?exit_id=<?php echo $r['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;padding:5px 10px;font-size:11px;">Next: Handover →</a>
          <?php else: ?>—<?php endif; ?>

        <?php elseif ($r['exit_type']=='contract_end'): ?>
          <?php if ($r['status']=='initiated'): ?>
          <form method="POST" style="display:inline;"><input type="hidden" name="action" value="confirm_non_renewal_from_list"><input type="hidden" name="id" value="<?php echo $r['id']; ?>"><button class="btn-p btn-red" style="padding:5px 10px;font-size:11px;">Confirm Non-Renewal</button></form>
          <?php elseif ($r['status']=='approved'): ?>
          <a href="hr-exit-handover.php?exit_id=<?php echo $r['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;padding:5px 10px;font-size:11px;">Next: Handover →</a>
          <?php else: ?>—<?php endif; ?>
        <?php endif; ?>
      </td>
      <td>
        <button class="btn-p" style="padding:5px 10px;font-size:11px;background:#64748b;" data-toggle="modal" data-target="#histModal<?php echo $r['id']; ?>"><i class="fas fa-clock-rotate-left mr-1"></i> History</button>
        <div class="modal fade" id="histModal<?php echo $r['id']; ?>" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content" style="border-radius:12px;">
          <div class="modal-header"><h6 style="font-weight:800;">History — <?php echo htmlspecialchars($r['exit_number']); ?> (<?php echo htmlspecialchars($r['employee_name'] ?? ''); ?>)</h6><button type="button" class="close" data-dismiss="modal">&times;</button></div>
          <div class="modal-body">
            <?php $hist = buildExitHistory($con, $r); ?>
            <?php foreach ($hist as $ev): ?>
            <div class="timeline-item">
              <div class="timeline-label"><?php echo htmlspecialchars($ev['label']); ?></div>
              <div class="timeline-meta">by <?php echo htmlspecialchars($ev['by']); ?> — <?php echo date('d M Y, h:i A', strtotime($ev['at'])); ?></div>
              <?php if ($ev['detail']): ?><div class="timeline-detail"><?php echo nl2br(htmlspecialchars($ev['detail'])); ?></div><?php endif; ?>
            </div>
            <?php endforeach; ?>
            <?php if (empty($hist)): ?><p style="color:#94a3b8;font-size:13px;">No recorded activity yet.</p><?php endif; ?>
          </div>
          <div class="modal-footer"><button type="button" class="btn-p btn-navy" onclick="window.print()"><i class="fas fa-print mr-1"></i> Print</button></div>
        </div></div></div>
      </td>
    </tr>
    <?php endforeach; ?>
    <?php if (empty($requests)): ?><tr><td colspan="7" style="text-align:center;color:#94a3b8;padding:30px;">No exit requests yet.</td></tr><?php endif; ?>
    </tbody>
  </table>
</div>
<?php endif; ?>

</div>
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
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
