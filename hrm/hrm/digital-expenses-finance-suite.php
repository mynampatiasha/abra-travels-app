<?php
// =========================================================================
// DIGITAL EXPENSES — EMPLOYEE SUITE
// =========================================================================
// - Employee-facing only (no approve/decline/history-of-others/admin actions)
// - New Voucher (multi-file proof upload), Edit (Pending/Declined only),
//   Delete (Pending only), Submit Explanation/Rebuttal (Declined only)
// - Own stats cards, own filters (status/search/date range), table + list view
// - View Voucher modal with proof images
// - Print / Download voucher (same-file browser-print view, like the
//   appraisal certificate pattern — no external PDF library required)
// - Own Activity Log (own vouchers only)
// =========================================================================

// --- FLUTTER WEBVIEW AUTH INJECTION (same block as hr-attendance-list.php / hr-leave-requests.php) ---
if (!headers_sent()) { header('Content-Type: text/html; charset=utf-8'); }
if (session_status() === PHP_SESSION_NONE) { session_start(); }
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
        $_SESSION['employee_id'] = $auth_user['employee_id'];
        $_SESSION['role_id'] = $auth_user['role_id'] ?? 0;
        $_SESSION['role_name'] = 'hr';
        $_SESSION['flutter_user_email'] = $__fue;
        $_SESSION['ge_cname'] = $auth_user['company_name'] ?? ($_SESSION['ge_cname'] ?? 'Abra');
        if (empty($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
        if (!headers_sent()) { setcookie('abra_hrm_email', $__fue, time() + 43200, '/'); }
    } elseif (isset($_REQUEST['user_email'])) {
        // An email was supplied but is not an employee: drop any previous login so
        // the page never silently shows another person's data.
        unset($_SESSION['user_name'], $_SESSION['user_id'], $_SESSION['employee_id'], $_SESSION['flutter_user_email']);
        if (!headers_sent()) { setcookie('abra_hrm_email', '', time() - 3600, '/'); }
        $__fue = '';
    }
}
if (!isset($_SESSION['ge_cname']))    { $_SESSION['ge_cname'] = 'Abra'; }
if (!isset($_SESSION['ge_timezone'])) { $_SESSION['ge_timezone'] = 'Asia/Kolkata'; }
$GLOBALS['__fue'] = $__fue;
// --------------------------------------

error_reporting(E_ALL);
ini_set('display_errors', 0);

date_default_timezone_set('Asia/Kolkata');

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require_once('requirelanguage.php');

$con = conexion();
if (!$con) die("Database connection failed");
mysqli_set_charset($con, 'utf8mb4');

if (function_exists('isUser')) isUser();

// WhatsApp approvals (approval requests to L1/L2, rejection notice to the employee)
require_once('digital-expense-wa.php');
dewaEnsureTables($con);
// NOTE: dewaRememberBase() is intentionally NOT called from the HRM copy. It stores this page's
// folder as the WhatsApp webhook's base URL; calling it from /hrm/ would repoint the CRM webhook.

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// ENSURE TABLES / COLUMNS EXIST
// =========================================================================
// Persistent, never-decreasing sequence for voucher numbers. Using
// COUNT(*) on finance_digital_expenses (the old approach) reissues a
// number once its original voucher is deleted, silently colliding with
// that voucher's still-existing history log entries. This table's
// auto-increment id never resets or decrements, so numbers stay unique
// forever regardless of how many vouchers get deleted later.
mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_voucher_seq (
    id INT AUTO_INCREMENT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Defensive one-time seed: if the sequence table is still empty, start it
// AFTER the highest voucher number already in use (from the old counting
// system, or any legacy data), instead of from zero — otherwise a fresh
// or rebuilt sequence table would immediately reissue DE0001 and collide
// with whatever already exists.
$seqCountQ = mysqli_query($con, "SELECT COUNT(*) c FROM finance_voucher_seq");
$seqCount = $seqCountQ ? intval(mysqli_fetch_assoc($seqCountQ)['c']) : 0;
if ($seqCount === 0) {
    $maxQ = mysqli_query($con, "SELECT MAX(CAST(SUBSTRING(voucher_number, 3) AS UNSIGNED)) as m FROM finance_digital_expenses WHERE voucher_number REGEXP '^DE[0-9]+$'");
    $maxNum = ($maxQ && $mr = mysqli_fetch_assoc($maxQ)) ? intval($mr['m']) : 0;
    if ($maxNum > 0) {
        mysqli_query($con, "ALTER TABLE finance_voucher_seq AUTO_INCREMENT = " . ($maxNum + 1));
    }
}

mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_digital_expenses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    voucher_number VARCHAR(50) NOT NULL,
    expense_date DATE NOT NULL,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(100) DEFAULT NULL,
    amount_paid_to VARCHAR(255) DEFAULT NULL,
    amount_in_words VARCHAR(255) DEFAULT NULL,
    on_account_of TEXT,
    expense_category VARCHAR(150) NOT NULL,
    received_by VARCHAR(150) DEFAULT NULL,
    proof_files TEXT,
    rebuttal_proof_files TEXT,
    employee_response TEXT,
    employee_response_at DATETIME DEFAULT NULL,
    status ENUM('Pending','Approved','Declined','Response Submitted') NOT NULL DEFAULT 'Pending',
    manager_reason TEXT,
    approved_at DATETIME DEFAULT NULL,
    added_by VARCHAR(50) NOT NULL,
    added_by_name VARCHAR(200) DEFAULT NULL,
    department VARCHAR(150) DEFAULT NULL,
    company_name VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_added_by (added_by),
    INDEX idx_status (status),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_digital_expense_categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(150) NOT NULL,
    added_by VARCHAR(50) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_digital_expense_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    action VARCHAR(100) NOT NULL,
    voucher_number VARCHAR(50) DEFAULT NULL,
    details TEXT,
    performed_by VARCHAR(150) DEFAULT NULL,
    employee_id VARCHAR(50) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_emp (employee_id),
    INDEX idx_voucher (voucher_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

function ensureColumn($con, $table, $col, $definition) {
    $c = mysqli_query($con, "SHOW COLUMNS FROM `$table` LIKE '$col'");
    if (!$c || mysqli_num_rows($c) == 0) {
        mysqli_query($con, "ALTER TABLE `$table` ADD COLUMN $col $definition");
        return true;
    }
    return false;
}
ensureColumn($con, 'finance_digital_expenses', 'ticket_numbers', "TEXT DEFAULT NULL");

// =========================================================================
// IDENTIFY CURRENT EMPLOYEE (own-records scoping)
// =========================================================================
$employee_id = ''; $employee_name_db = ''; $employee_department = ''; $employee_position = ''; $employee_company = '';
$employee_email = '';
if (!empty($currentUserName) || !empty($_SESSION['flutter_user_email']) || !empty($_SESSION['employee_id'])) {
    // Same approach as the attendance page: resolve by login email first, then employee code,
    // then the exact name, and only then the old name-prefix match.
    $row = null;
    $probeEmail = strtolower(trim($_SESSION['flutter_user_email'] ?? ''));
    $probeEid   = trim($_SESSION['employee_id'] ?? '');
    $exactUserName = trim($currentUserName);
    $searchPattern = $exactUserName . '%';
    $cols = "id, employee_id, name, email, personal_email, department, position, company_name";
    $attempts = [];
    if ($probeEmail !== '') $attempts[] = ["SELECT $cols FROM hr_employees WHERE status='active' AND (LOWER(TRIM(email)) = ? OR LOWER(TRIM(personal_email)) = ?) LIMIT 1", 'ss', [$probeEmail, $probeEmail]];
    if ($probeEid !== '')   $attempts[] = ["SELECT $cols FROM hr_employees WHERE status='active' AND employee_id = ? LIMIT 1", 's', [$probeEid]];
    if ($exactUserName !== '') {
        $attempts[] = ["SELECT $cols FROM hr_employees WHERE status='active' AND LOWER(TRIM(name)) = LOWER(?) LIMIT 1", 's', [$exactUserName]];
        $attempts[] = ["SELECT $cols FROM hr_employees WHERE status='active' AND name LIKE ? LIMIT 1", 's', [$searchPattern]];
    }
    foreach ($attempts as $at) {
        $stmt = $con->prepare($at[0]);
        if (!$stmt) continue;
        $stmt->bind_param($at[1], ...$at[2]);
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result ? $result->fetch_assoc() : null;
        $stmt->close();
        if ($row) break;
    }
    if ($row) {
        $employee_id = $row['employee_id'];
        $employee_name_db = $row['name'];
        $employee_email = strtolower(trim($row['email'] ?: ($row['personal_email'] ?? '')));
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
        $employee_company = !empty($row['company_name']) ? $row['company_name'] : '';
    }
}

if (empty($employee_id)) {
    die("<div style='font-family:Poppins,Arial;text-align:center;margin-top:100px;'>
        <h2 style='color:#dc2626;'>Access Denied</h2>
        <p>We could not match your login to an active employee record, so digital expenses cannot be attached to you.</p>
        <p><a href='/dashboard/raise-a-ticket.php'>&larr; Back to Dashboard</a></p></div>");
}

// =========================================================================
// ADMIN IDENTIFICATION — same pattern as active-shipments.php, so the
// same person who gets admin rights there gets admin rights here too.
// =========================================================================
// Resolved from the employee record (email / employee code) rather than a loose name match.
$isAdmin = false; // L2 approver — final approval stage, plus override rights.
if ($employee_email === 'abishek.veeraswamy@fleet.abra-travels.com' || in_array($employee_id, array('AT003', 'ABRA001'), true)) {
    $isAdmin = true;
} elseif (stripos($employee_name_db, 'Abishek') !== false) {
    $isAdmin = true; // same name rule the attendance page uses for the Master Super Admin
}

// L1 approver: anyone in the Finance Department (any position) reviews a
// voucher first. L2 ($isAdmin) reviews second, and can only act once L1 has
// approved — unless L2 uses the override path to bypass that gate.
$isL1Approver = (!$isAdmin) && (strtolower(trim($employee_department)) === 'finance department');
$canViewAllVouchers = $isAdmin || $isL1Approver;
// Only the Administrator login may change the WhatsApp approvers
$isAdminLogin = (($_SESSION['user_type'] ?? '') === 'Administrator') || $isAdmin;

ensureColumn($con, 'finance_digital_expenses', 'approved_by', "VARCHAR(200) DEFAULT NULL");

// Two-stage approval tracking — L1 (Finance Department) then L2 (admin).
$l1ColAdded = ensureColumn($con, 'finance_digital_expenses', 'l1_status', "VARCHAR(30) NOT NULL DEFAULT 'Pending'");
ensureColumn($con, 'finance_digital_expenses', 'l1_by', "VARCHAR(200) DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l1_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l1_reason', "TEXT DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l2_status', "VARCHAR(30) NOT NULL DEFAULT 'Pending'");
ensureColumn($con, 'finance_digital_expenses', 'l2_by', "VARCHAR(200) DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l2_at', "DATETIME DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l2_reason', "TEXT DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'l2_override', "TINYINT(1) NOT NULL DEFAULT 0");
ensureColumn($con, 'finance_digital_expenses', 'l2_override_reason', "TEXT DEFAULT NULL");

// One-time backfill: vouchers already Approved/Declined under the old
// single-stage flow (before L1/L2 existed) get retrofitted L2-only values —
// attributed to whoever approved/declined them back then (now the L2 role) —
// so the new columns don't silently contradict a voucher's existing status.
if ($l1ColAdded) {
    mysqli_query($con, "UPDATE finance_digital_expenses SET
        l1_status='Skipped (Legacy)',
        l2_status='Approved', l2_by=approved_by, l2_at=approved_at
        WHERE status='Approved'");
    mysqli_query($con, "UPDATE finance_digital_expenses SET
        l1_status='Skipped (Legacy)',
        l2_status='Declined', l2_by=approved_by, l2_at=updated_at, l2_reason=manager_reason
        WHERE status='Declined'");
}

// Widen the status enum to add the intermediate "Pending L2 Approval" stage.
// Existing rows/values are untouched — this only adds a new allowed value.
$stColQ = mysqli_query($con, "SHOW COLUMNS FROM finance_digital_expenses LIKE 'status'");
$stColRow = $stColQ ? mysqli_fetch_assoc($stColQ) : null;
if ($stColRow && strpos($stColRow['Type'], 'Pending L2 Approval') === false) {
    mysqli_query($con, "ALTER TABLE finance_digital_expenses MODIFY COLUMN status ENUM('Pending','Pending L2 Approval','Approved','Declined','Response Submitted') NOT NULL DEFAULT 'Pending'");
}

ensureColumn($con, 'finance_digital_expenses', 'payment_status', "VARCHAR(100) DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'payment_status_updated_by', "VARCHAR(200) DEFAULT NULL");
ensureColumn($con, 'finance_digital_expenses', 'payment_status_updated_at', "DATETIME DEFAULT NULL");

$payment_status_options = ['Payment Initiated', 'Initiated from Bank', 'Released to Source Account', 'Payment Completed', 'On Hold', 'Payment Failed / Returned'];

// One color per payment stage, so the badge itself communicates progress at a glance —
// used by both the employee "My Vouchers" table and the Finance/Admin table below.
$payment_status_colors = [
    'Pending'                     => ['bg' => '#f1f5f9', 'c' => '#64748b'], // approved, payment not started yet
    'Payment Initiated'           => ['bg' => '#fef9c3', 'c' => '#854d0e'], // dark yellow
    'Initiated from Bank'         => ['bg' => '#fef9c3', 'c' => '#854d0e'], // dark yellow
    'Released to Source Account'  => ['bg' => '#eef2ff', 'c' => '#4338ca'], // indigo
    'Payment Completed'           => ['bg' => '#f0fdfa', 'c' => '#0f766e'], // teal — a different green from the "Approved" badges in the L1/L2 columns next to it
    'On Hold'                     => ['bg' => '#fefce8', 'c' => '#a16207'], // amber
    'Payment Failed / Returned'   => ['bg' => '#fef2f2', 'c' => '#b91c1c'], // red
];

// Renders the payment-status badge (colored per stage) + "by X, on date" underneath it.
// Only shown once a voucher is fully Approved — before that, payment isn't relevant yet.
function renderPaymentStatusBadge($overallStatus, $paymentStatus, $updatedBy, $updatedAt, $colors) {
    if ($overallStatus !== 'Approved') return '';
    $label = $paymentStatus ?: 'Pending';
    $style = $colors[$label] ?? ['bg' => '#f1f5f9', 'c' => '#64748b'];
    // Same solid-fill "button" treatment as the Approved badge — each stage keeps its own
    // distinguishing color, just as a solid background with white text instead of a pastel pill.
    $html  = '<div style="margin-top:6px;"><span class="badge-status" style="background:' . $style['c'] . ';color:#ffffff;box-shadow:0 1px 4px ' . $style['c'] . '66;"><i class="fas fa-university" style="margin-right:4px;"></i>' . htmlspecialchars($label) . '</span>';
    if (!empty($paymentStatus) && !empty($updatedBy)) {
        $html .= '<div style="font-size:10.5px;color:#94a3b8;margin-top:3px;">by ' . htmlspecialchars($updatedBy);
        if (!empty($updatedAt)) $html .= ', ' . date('d M Y, h:i A', strtotime($updatedAt));
        $html .= '</div>';
    }
    $html .= '</div>';
    return $html;
}

mysqli_query($con, "CREATE TABLE IF NOT EXISTS finance_admin_signature (
    id INT AUTO_INCREMENT PRIMARY KEY,
    signature_path VARCHAR(500) NOT NULL,
    uploaded_by VARCHAR(200) DEFAULT NULL,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$dashboard_url = '/dashboard/raise-a-ticket.php';
$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']==='on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
$script_path = $base_url . $_SERVER['PHP_SELF'];

// =========================================================================
// HELPERS
// =========================================================================
function logExpHistory($con, $action, $voucherNumber, $details, $performedBy, $employeeId) {
    $a = mysqli_real_escape_string($con, $action);
    $v = $voucherNumber ? "'".mysqli_real_escape_string($con, $voucherNumber)."'" : 'NULL';
    $d = mysqli_real_escape_string($con, $details);
    $p = mysqli_real_escape_string($con, $performedBy);
    $e = mysqli_real_escape_string($con, $employeeId);
    mysqli_query($con, "INSERT INTO finance_digital_expense_history (action, voucher_number, details, performed_by, employee_id) VALUES ('$a', $v, '$d', '$p', '$e')");
}

function renderReasonNote($text, $color, $title) {
    if (empty($text)) return '';
    $short = mb_strlen($text) > 40 ? mb_substr($text, 0, 40) . '...' : $text;
    $html = '<span class="adm-reason-note" style="color:' . $color . ';" data-fulltext="' . htmlspecialchars($text, ENT_QUOTES) . '" data-title="' . htmlspecialchars($title, ENT_QUOTES) . '">' . htmlspecialchars($short);
    if (mb_strlen($text) > 40) $html .= ' <a href="javascript:void(0)" class="reason-readmore" onclick="showFullTextModal(this)">Read more</a>';
    $html .= '</span>';
    return $html;
}

function isPdfFile($filename) {
    // Avoids str_ends_with(), which requires PHP 8.0+ and would fatal-error on older servers.
    return substr(strtolower((string)$filename), -4) === '.pdf';
}

function getStatusStyle($status) {
    // Every status badge on this page is now a solid-fill "button" (colored background,
    // white text) instead of a pastel pill — one consistent UI, each status keeping its
    // own distinguishing color.
    switch (strtoupper($status)) {
        case 'APPROVED': return ['bg' => '#25D366', 'c' => '#ffffff', 'icon' => '✅']; // solid WhatsApp green
        case 'DECLINED': return ['bg' => '#dc2626', 'c' => '#ffffff', 'icon' => '❌'];
        case 'RESPONSE SUBMITTED': return ['bg' => '#7b1fa2', 'c' => '#ffffff', 'icon' => '💬'];
        case 'PENDING L2 APPROVAL': return ['bg' => '#4338ca', 'c' => '#ffffff', 'icon' => '🕑'];
        default: return ['bg' => '#c2410c', 'c' => '#ffffff', 'icon' => '⏳']; // Pending
    }
}

function ensureCategoryExists($con, $categoryName, $employeeId) {
    $cat = trim($categoryName);
    if ($cat === '') return;
    $catEsc = mysqli_real_escape_string($con, $cat);
    $chk = mysqli_query($con, "SELECT id FROM finance_digital_expense_categories WHERE category_name='$catEsc' LIMIT 1");
    if ($chk && mysqli_num_rows($chk) > 0) return;
    mysqli_query($con, "INSERT INTO finance_digital_expense_categories (category_name, added_by) VALUES ('$catEsc', '".mysqli_real_escape_string($con,$employeeId)."')");
}

function generateVoucherNumber($con) {
    mysqli_query($con, "INSERT INTO finance_voucher_seq () VALUES ()");
    $nextId = mysqli_insert_id($con);
    if (!$nextId) {
        // Fallback (should not normally happen): derive from current max as a last resort.
        $q = mysqli_query($con, "SELECT MAX(id) as m FROM finance_voucher_seq");
        $nextId = ($q && $r = mysqli_fetch_assoc($q)) ? intval($r['m']) + 1 : 1;
    }
    return 'DE' . str_pad($nextId, 4, '0', STR_PAD_LEFT);
}

$upload_dir = __DIR__ . '/uploads/digital_expenses/';
if (!is_dir($upload_dir)) @mkdir($upload_dir, 0755, true);
// Build the URL relative to wherever this script actually lives (e.g. /dashboard/),
// so it always matches the physical save path above regardless of deployment folder.
$script_dir = rtrim(str_replace('\\', '/', dirname($_SERVER['PHP_SELF'])), '/');
$upload_url_base = $script_dir . '/uploads/digital_expenses/';
$allowed_ext = ['jpg','jpeg','png','gif','webp','pdf'];
$max_file_size = 10 * 1024 * 1024; // 10MB

$signature_upload_dir = __DIR__ . '/uploads/signatures/';
if (!is_dir($signature_upload_dir)) @mkdir($signature_upload_dir, 0755, true);
$signature_upload_url_base = $script_dir . '/uploads/signatures/';
$signature_allowed_ext = ['jpg','jpeg','png','webp'];
$signature_max_size = 2 * 1024 * 1024; // 2MB

function handleUploads($files_field, $upload_dir, $upload_url_base, $allowed_ext, $max_file_size, &$err) {
    $saved = [];
    if (!isset($_FILES[$files_field])) return $saved;
    $f = $_FILES[$files_field];
    $count = is_array($f['name']) ? count($f['name']) : 0;
    for ($i = 0; $i < $count; $i++) {
        if ($f['error'][$i] !== UPLOAD_ERR_OK) continue;
        if ($f['size'][$i] > $max_file_size) { $err[] = $f['name'][$i] . ' exceeds 10MB limit.'; continue; }
        $ext = strtolower(pathinfo($f['name'][$i], PATHINFO_EXTENSION));
        if (!in_array($ext, $allowed_ext)) { $err[] = $f['name'][$i] . ' is not an allowed file type.'; continue; }
        $fname = 'd-exp-' . time() . '-' . mt_rand(100000,999999) . '.' . $ext;
        $dest = $upload_dir . $fname;
        if (move_uploaded_file($f['tmp_name'][$i], $dest)) {
            $saved[] = [
                'filename' => $fname,
                'originalName' => $f['name'][$i],
                'path' => $upload_url_base . $fname,
                'size' => $f['size'][$i],
                'mimetype' => $f['type'][$i]
            ];
        }
    }
    return $saved;
}

function deleteProofFiles($proof_json_str, $upload_dir) {
    $arr = json_decode($proof_json_str, true);
    if (!is_array($arr)) return;
    foreach ($arr as $p) {
        if (!empty($p['filename'])) {
            $abs = $upload_dir . $p['filename'];
            if (file_exists($abs)) @unlink($abs);
        }
    }
}

// =========================================================================
// AJAX: GET CATEGORIES
// =========================================================================
if (isset($_GET['ajax_get_categories'])) {
    header('Content-Type: application/json');
    $q = mysqli_query($con, "SELECT DISTINCT category_name FROM finance_digital_expense_categories ORDER BY category_name ASC");
    $cats = [];
    if ($q) while ($r = mysqli_fetch_assoc($q)) $cats[] = $r['category_name'];
    echo json_encode(['success' => true, 'data' => $cats]);
    exit;
}

// =========================================================================
// AJAX: ADD CATEGORY
// =========================================================================
if (isset($_POST['ajax_add_category'])) {
    header('Content-Type: application/json');
    $cat = trim($_POST['categoryName'] ?? '');
    if ($cat === '') { echo json_encode(['success'=>false,'message'=>'Category name is required.']); exit; }
    $catEsc = mysqli_real_escape_string($con, $cat);
    $chk = mysqli_query($con, "SELECT id FROM finance_digital_expense_categories WHERE category_name='$catEsc' LIMIT 1");
    if ($chk && mysqli_num_rows($chk) > 0) { echo json_encode(['success'=>true,'message'=>'Category already exists']); exit; }
    mysqli_query($con, "INSERT INTO finance_digital_expense_categories (category_name, added_by) VALUES ('$catEsc', '".mysqli_real_escape_string($con,$employee_id)."')");
    echo json_encode(['success' => true, 'message' => 'Category added']);
    exit;
}

// =========================================================================
// AJAX: CREATE EXPENSE (own voucher)
// =========================================================================
if (isset($_POST['ajax_create_expense'])) {
    header('Content-Type: application/json');
    $date = mysqli_real_escape_string($con, $_POST['date'] ?? '');
    $amount = floatval($_POST['amount'] ?? 0);
    $paymentMethod = mysqli_real_escape_string($con, $_POST['paymentMethod'] ?? '');
    $amountPaidTo = mysqli_real_escape_string($con, $_POST['amountPaidTo'] ?? '');
    $amountInWords = mysqli_real_escape_string($con, $_POST['amountInWords'] ?? '');
    $onAccountOf = mysqli_real_escape_string($con, $_POST['onAccountOf'] ?? '');
    $expenseCategory = mysqli_real_escape_string($con, $_POST['expenseCategory'] ?? '');
    $receivedBy = mysqli_real_escape_string($con, $_POST['receivedBy'] ?? '');

    $errors = [];
    if (empty($_POST['date'])) $errors[] = 'Date is required';
    if (empty($_POST['expenseCategory'])) $errors[] = 'Expense Category is required';
    if ($amount <= 0) $errors[] = 'Valid amount is required';
    if (!empty($errors)) { echo json_encode(['success'=>false,'message'=>'Validation failed','errors'=>$errors]); exit; }

    $upErr = [];
    $files = handleUploads('proofFiles', $upload_dir, $upload_url_base, $allowed_ext, $max_file_size, $upErr);
    $filesJson = mysqli_real_escape_string($con, json_encode($files));

    $voucherNumber = generateVoucherNumber($con);
    $empIdEsc = mysqli_real_escape_string($con, $employee_id);
    $empNameEsc = mysqli_real_escape_string($con, $employee_name_db);
    $deptEsc = mysqli_real_escape_string($con, $employee_department);
    $coEsc = mysqli_real_escape_string($con, $employee_company);

    $sql = "INSERT INTO finance_digital_expenses
        (voucher_number, expense_date, amount, payment_method, amount_paid_to, amount_in_words, on_account_of, expense_category, received_by, proof_files, status, added_by, added_by_name, department, company_name)
        VALUES
        ('$voucherNumber', '$date', $amount, '$paymentMethod', '$amountPaidTo', '$amountInWords', '$onAccountOf', '$expenseCategory', '$receivedBy', '$filesJson', 'Pending', '$empIdEsc', '$empNameEsc', '$deptEsc', '$coEsc')";

    if (!mysqli_query($con, $sql)) { echo json_encode(['success'=>false,'message'=>'DB Error: '.mysqli_error($con)]); exit; }
    // read the voucher's id straight after its INSERT — the category / history inserts below would change mysqli_insert_id()
    $newId = mysqli_insert_id($con);

    ensureCategoryExists($con, $_POST['expenseCategory'], $employee_id);
    logExpHistory($con, 'Created', $voucherNumber, "Created expense voucher for ₹".number_format($amount,2)." (".$_POST['expenseCategory'].")", $employee_name_db, $employee_id);

    dewaDefer(function ($con) use ($newId) { dewaSendLevel($con, $newId, 1); });
    $ticketNums = [];
    $ticketWarning = null;
    if (!empty($_POST['raise_ticket'])) {
        $ticketSubject = trim($_POST['ticket_subject'] ?? '');
        $ticketMessage = trim($_POST['ticket_message'] ?? '');
        $ticketAssignedTo = array_filter(array_map('intval', (array)($_POST['ticket_assigned_to'] ?? [])));
        if ($ticketSubject === '' || $ticketMessage === '' || empty($ticketAssignedTo)) {
            $ticketWarning = 'Voucher saved, but the ticket was NOT raised — subject, message, and at least one assignee are required.';
        } else {
            $createdBy = resolveEmployeePk($con, $employee_id);
            $ticketDbError = null;
            $ticketNums = raiseTicketsForAssignees($con, $employee_name_db, $ticketSubject, $ticketMessage, $ticketAssignedTo, $createdBy, 'medium', 1440, $ticketDbError);
            if (!empty($ticketNums)) {
                logExpHistory($con, 'Ticket Raised', $voucherNumber, 'Raised ticket(s): ' . implode(', ', $ticketNums), $employee_name_db, $employee_id);
                attachTicketNumbersToVoucher($con, $newId, $ticketNums);
            } else {
                $ticketWarning = 'Voucher saved, but the ticket could not be raised' . ($ticketDbError ? ': ' . $ticketDbError : '.');
            }
        }
    }

    echo json_encode(['success' => true, 'message' => 'Digital expense submitted successfully', 'id' => $newId, 'voucher_number' => $voucherNumber, 'upload_warnings' => $upErr, 'ticket_numbers' => $ticketNums, 'ticket_warning' => $ticketWarning]);
    exit;
}

// =========================================================================
// AJAX: EDIT EXPENSE (own, Pending/Declined only)
// =========================================================================
if (isset($_POST['ajax_edit_expense'])) {
    header('Content-Type: application/json');
    $id = intval($_POST['id'] ?? 0);
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id AND added_by='".mysqli_real_escape_string($con,$employee_id)."' LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }
    if (!in_array($exp['status'], ['Pending','Declined'])) { echo json_encode(['success'=>false,'message'=>'Only Pending or Declined vouchers can be edited.']); exit; }

    $date = mysqli_real_escape_string($con, $_POST['date'] ?? $exp['expense_date']);
    $amount = isset($_POST['amount']) && $_POST['amount'] !== '' ? floatval($_POST['amount']) : floatval($exp['amount']);
    $paymentMethod = mysqli_real_escape_string($con, $_POST['paymentMethod'] ?? $exp['payment_method']);
    $amountPaidTo = mysqli_real_escape_string($con, $_POST['amountPaidTo'] ?? $exp['amount_paid_to']);
    $amountInWords = mysqli_real_escape_string($con, $_POST['amountInWords'] ?? $exp['amount_in_words']);
    $onAccountOf = mysqli_real_escape_string($con, $_POST['onAccountOf'] ?? $exp['on_account_of']);
    $expenseCategory = mysqli_real_escape_string($con, $_POST['expenseCategory'] ?? $exp['expense_category']);
    $receivedBy = mysqli_real_escape_string($con, $_POST['receivedBy'] ?? $exp['received_by']);

    $filesSql = '';
    $upErr = [];
    if (!empty($_FILES['proofFiles']['name'][0])) {
        $newFiles = handleUploads('proofFiles', $upload_dir, $upload_url_base, $allowed_ext, $max_file_size, $upErr);
        if (!empty($newFiles)) {
            deleteProofFiles($exp['proof_files'], $upload_dir);
            $filesSql = ", proof_files='" . mysqli_real_escape_string($con, json_encode($newFiles)) . "'";
        }
    }

    // Editing a Declined voucher resets it back to Pending for re-review —
    // and back to the L1 stage, clearing both stages' prior decisions.
    $statusSql = ($exp['status'] === 'Declined')
        ? ", status='Pending', manager_reason=NULL, l1_status='Pending', l1_by=NULL, l1_at=NULL, l1_reason=NULL, l2_status='Pending', l2_by=NULL, l2_at=NULL, l2_reason=NULL, l2_override=0, l2_override_reason=NULL, approved_by=NULL, approved_at=NULL"
        : "";

    $sql = "UPDATE finance_digital_expenses SET
        expense_date='$date', amount=$amount, payment_method='$paymentMethod', amount_paid_to='$amountPaidTo',
        amount_in_words='$amountInWords', on_account_of='$onAccountOf', expense_category='$expenseCategory', received_by='$receivedBy'
        $filesSql $statusSql
        WHERE id=$id";

    if (!mysqli_query($con, $sql)) { echo json_encode(['success'=>false,'message'=>'DB Error: '.mysqli_error($con)]); exit; }
    if (!empty($_POST['expenseCategory'])) ensureCategoryExists($con, $_POST['expenseCategory'], $employee_id);
    logExpHistory($con, 'Updated', $exp['voucher_number'], 'Updated expense details', $employee_name_db, $employee_id);
    // edited (or edited after a rejection) -> back to L1, so L1 gets the updated details and files
    $waNote = ($exp['status'] === 'Declined') ? 'Edited and resubmitted by the employee after rejection' : 'Updated by the employee — replaces the earlier request';
    dewaDefer(function ($con) use ($id, $waNote) { dewaSendLevel($con, $id, 1, $waNote); });
    echo json_encode(['success' => true, 'message' => 'Voucher updated successfully', 'upload_warnings' => $upErr]);
    exit;
}

// =========================================================================
// AJAX: SUBMIT REBUTTAL / EXPLANATION (own, Declined only)
// =========================================================================
if (isset($_POST['ajax_submit_rebuttal'])) {
    header('Content-Type: application/json');
    $id = intval($_POST['id'] ?? 0);
    $response = trim($_POST['employeeResponse'] ?? '');
    if ($response === '') { echo json_encode(['success'=>false,'message'=>'Explanation is required.']); exit; }

    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id AND added_by='".mysqli_real_escape_string($con,$employee_id)."' LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }
    if ($exp['status'] !== 'Declined') { echo json_encode(['success'=>false,'message'=>'Only declined vouchers can be rebutted.']); exit; }

    $upErr = [];
    $newFiles = handleUploads('rebuttalProofFiles', $upload_dir, $upload_url_base, $allowed_ext, $max_file_size, $upErr);
    $filesSql = '';
    if (!empty($newFiles)) {
        deleteProofFiles($exp['rebuttal_proof_files'], $upload_dir);
        $filesSql = ", rebuttal_proof_files='" . mysqli_real_escape_string($con, json_encode($newFiles)) . "'";
    }

    $respEsc = mysqli_real_escape_string($con, $response);
    // Resubmitting always restarts the two-stage review from L1, regardless
    // of whether L1, L2, or an L2 override declined it originally.
    mysqli_query($con, "UPDATE finance_digital_expenses SET status='Response Submitted', employee_response='$respEsc', employee_response_at=NOW(), l1_status='Pending', l1_by=NULL, l1_at=NULL, l2_status='Pending', l2_by=NULL, l2_at=NULL, l2_override=0 $filesSql WHERE id=$id");
    logExpHistory($con, 'Rebuttal Submitted', $exp['voucher_number'], 'Employee submitted a response/explanation — sent back to L1 for review', $employee_name_db, $employee_id);
    dewaDefer(function ($con) use ($id) { dewaSendLevel($con, $id, 1, 'Resubmitted with explanation after rejection'); });
    echo json_encode(['success' => true, 'message' => 'Response submitted successfully', 'upload_warnings' => $upErr]);
    exit;
}

// =========================================================================
// AJAX: DELETE EXPENSE (own, Pending only)
// =========================================================================
if (isset($_POST['ajax_delete_expense'])) {
    header('Content-Type: application/json');
    $id = intval($_POST['id'] ?? 0);
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id AND added_by='".mysqli_real_escape_string($con,$employee_id)."' LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }
    if ($exp['status'] !== 'Pending') { echo json_encode(['success'=>false,'message'=>'Only Pending vouchers can be deleted.']); exit; }

    deleteProofFiles($exp['proof_files'], $upload_dir);
    deleteProofFiles($exp['rebuttal_proof_files'], $upload_dir);
    mysqli_query($con, "DELETE FROM finance_digital_expenses WHERE id=$id");
    logExpHistory($con, 'Deleted', $exp['voucher_number'], 'Deleted expense voucher', $employee_name_db, $employee_id);
    echo json_encode(['success' => true, 'message' => 'Voucher deleted successfully']);
    exit;
}

// =========================================================================
// AJAX: OWN ACTIVITY LOG
// =========================================================================
if (isset($_GET['ajax_activity'])) {
    header('Content-Type: application/json');
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expense_history WHERE employee_id='".mysqli_real_escape_string($con,$employee_id)."' ORDER BY created_at DESC LIMIT 100");
    $list = [];
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        $list[] = [
            'action' => $r['action'],
            'voucher_number' => $r['voucher_number'],
            'details' => $r['details'],
            'date' => date('d M Y, h:i A', strtotime($r['created_at']))
        ];
    }
    echo json_encode(['success' => true, 'data' => $list]);
    exit;
}

// =========================================================================
// AJAX: RAISE-A-TICKET SUPPORT (per-voucher, quick-raise from this page)
// =========================================================================
function buildTicketTextFromVoucher($exp, $employeeName) {
    $subject = 'Query on Digital Expense Voucher ' . $exp['voucher_number'];
    $message = "Hi,\n\n" .
        "I'd like to raise a query regarding my Digital Expense voucher.\n\n" .
        "Voucher No: " . $exp['voucher_number'] . "\n" .
        "Date: " . date('d/m/Y', strtotime($exp['expense_date'])) . "\n" .
        "Amount: Rs. " . number_format($exp['amount'], 2) . "\n" .
        "Category: " . $exp['expense_category'] . "\n" .
        (!empty($exp['on_account_of']) ? "On Account Of: " . $exp['on_account_of'] . "\n" : "") .
        "Status: " . $exp['status'] .
        (!empty($exp['manager_reason']) ? "\nDecline Reason: " . $exp['manager_reason'] : "") . "\n\n" .
        "Please review and advise.\n\nThanks,\n" . $employeeName;
    return [$subject, $message];
}

// Resolves this employee's hr_employees.id (integer PK) — tickets.created_by /
// assigned_to reference that PK, not the employee_id string used elsewhere here.
function resolveEmployeePk($con, $employeeIdStr) {
    $q = mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id='" . mysqli_real_escape_string($con, $employeeIdStr) . "' LIMIT 1");
    if ($q && $row = mysqli_fetch_assoc($q)) return intval($row['id']);
    return 0;
}

// Creates one ticket per assignee. Returns the array of created ticket numbers (empty on total failure).
function raiseTicketsForAssignees($con, $reporterName, $subject, $message, $assignedToList, $createdByPk, $priority = 'medium', $timelineMinutes = 1440, &$errorOut = null) {
    // Same flow as hr-leave-requests.php: the ticket is created in the Fleet system
    // (Node API -> MongoDB) so the assignee sees it in the Fleet app's "All Tickets" screen,
    // and a linking row is kept in the MySQL `tickets` table with the same ticket number.
    // If the Fleet API is unreachable the ticket is still saved in MySQL with an EX- number.
    $deadline = date('Y-m-d H:i:s', strtotime("+{$timelineMinutes} minutes"));
    $attachment = '';
    $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by) VALUES (?, ?, ?, ?, 'Open', ?, ?, ?, ?, NOW(), NOW(), ?, ?)");
    if (!$stmt) { $errorOut = 'Prepare failed: ' . mysqli_error($con); return []; }

    // Creator (the employee raising the ticket)
    $creatorName = $reporterName; $creatorEmail = '';
    $cq = mysqli_query($con, "SELECT name, email, personal_email FROM hr_employees WHERE id=" . intval($createdByPk) . " LIMIT 1");
    if ($cq && $crow = mysqli_fetch_assoc($cq)) {
        $creatorName  = $crow['name'];
        $creatorEmail = strtolower(trim($crow['email'] ?: ($crow['personal_email'] ?? '')));
    }
    $internalKey = getenv('FLEET_INTERNAL_KEY') ?: 'abra_internal_2026';

    $ticketNums = [];
    foreach ($assignedToList as $assignedTo) {
        $ticketNumber = null;
        $ap = null;
        $aq = mysqli_query($con, "SELECT name, email, personal_email FROM hr_employees WHERE id=" . intval($assignedTo) . " LIMIT 1");
        if ($aq) $ap = mysqli_fetch_assoc($aq);
        $apEmail = $ap ? strtolower(trim($ap['email'] ?: ($ap['personal_email'] ?? ''))) : '';

        if ($ap && $apEmail !== '' && function_exists('curl_init')) {
            $payload = json_encode([
                'subject'        => $subject,
                'message'        => $message,
                'priority'       => $priority,
                'timeline'       => $timelineMinutes,
                'assigned_name'  => $ap['name'],
                'assigned_email' => $apEmail,
                'creator_name'   => $creatorName,
                'creator_email'  => $creatorEmail,
                'source'         => 'digital_expense',
            ]);
            $ch = curl_init('http://localhost:3001/api/tickets/internal/create');
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST           => true,
                CURLOPT_POSTFIELDS     => $payload,
                CURLOPT_HTTPHEADER     => ['Content-Type: application/json', 'x-internal-key: ' . $internalKey],
                CURLOPT_TIMEOUT        => 15,
                CURLOPT_SSL_VERIFYPEER => false,
            ]);
            $res  = curl_exec($ch);
            $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $err  = curl_error($ch);
            curl_close($ch);
            $json = json_decode((string)$res, true);
            if (!empty($json['success']) && !empty($json['ticket_number'])) {
                $ticketNumber = $json['ticket_number'];
            } else {
                error_log("Expense ticket -> Fleet API failed (HTTP $http): " . ($err ?: (string)$res));
            }
        } else {
            error_log("Expense ticket: assignee #" . intval($assignedTo) . " has no email; cannot create Fleet ticket.");
        }

        if ($ticketNumber === null) {
            $ticketNumber = 'EX-' . date('Ymd') . '-' . rand(1000, 9999) . '-' . intval($assignedTo);
        }

        // MySQL linking row (skipped if this ticket_number already exists)
        $tnEsc = mysqli_real_escape_string($con, $ticketNumber);
        $ex = mysqli_query($con, "SELECT id FROM tickets WHERE ticket_number='$tnEsc' LIMIT 1");
        if ($ex && mysqli_num_rows($ex) > 0) { $ticketNums[] = $ticketNumber; continue; }
        $assignedToInt = intval($assignedTo);
        $createdByInt  = intval($createdByPk);
        mysqli_stmt_bind_param($stmt, "sssssissii", $ticketNumber, $reporterName, $subject, $message, $priority, $timelineMinutes, $deadline, $attachment, $assignedToInt, $createdByInt);
        if (mysqli_stmt_execute($stmt)) {
            $ticketNums[] = $ticketNumber;
        } else {
            $errorOut = 'Insert failed: ' . mysqli_stmt_error($stmt);
            error_log('Expense ticket MySQL link row failed: ' . mysqli_stmt_error($stmt));
            // The Fleet ticket exists even if the link row failed, so still report it.
            if (strpos($ticketNumber, 'EX-') !== 0) $ticketNums[] = $ticketNumber;
        }
    }
    mysqli_stmt_close($stmt);
    return $ticketNums;
}

// Merges new ticket numbers onto a voucher's stored ticket_numbers column.
function attachTicketNumbersToVoucher($con, $voucherId, $newTicketNums) {
    if (!$voucherId || empty($newTicketNums)) return;
    $eq = mysqli_query($con, "SELECT ticket_numbers FROM finance_digital_expenses WHERE id=$voucherId LIMIT 1");
    $existing = ($eq && $erow = mysqli_fetch_assoc($eq)) ? array_filter(array_map('trim', explode(',', (string)$erow['ticket_numbers']))) : [];
    $merged = array_unique(array_merge($existing, $newTicketNums));
    mysqli_query($con, "UPDATE finance_digital_expenses SET ticket_numbers='" . mysqli_real_escape_string($con, implode(',', $merged)) . "' WHERE id=$voucherId");
}

if (isset($_GET['ajax_get_active_employees'])) {
    header('Content-Type: application/json');
    $q = mysqli_query($con, "SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name");
    $list = [];
    if ($q) while ($r = mysqli_fetch_assoc($q)) $list[] = ['id' => $r['id'], 'name' => $r['name']];
    echo json_encode(['success' => true, 'data' => $list]);
    exit;
}

if (isset($_GET['ajax_ticket_preview'])) {
    header('Content-Type: application/json');
    $voucherId = intval($_GET['voucher_id'] ?? 0);
    if ($voucherId) {
        $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$voucherId AND added_by='".mysqli_real_escape_string($con,$employee_id)."' LIMIT 1");
        $exp = $q ? mysqli_fetch_assoc($q) : null;
        if ($exp) {
            list($subject, $message) = buildTicketTextFromVoucher($exp, $employee_name_db);
            echo json_encode(['success' => true, 'subject' => $subject, 'message' => $message]);
            exit;
        }
    }
    $subject = 'Query from ' . $employee_name_db;
    $message = "Hi,\n\nI have a question / request regarding my Digital Expenses. Please assist.\n\nThanks,\n" . $employee_name_db;
    echo json_encode(['success' => true, 'subject' => $subject, 'message' => $message]);
    exit;
}

if (isset($_POST['ajax_raise_ticket'])) {
    header('Content-Type: application/json');
    $subject = trim($_POST['subject'] ?? '');
    $message = trim($_POST['message'] ?? '');
    $assignedToList = array_filter(array_map('intval', (array)($_POST['assigned_to'] ?? [])));
    $voucherId = intval($_POST['voucher_id'] ?? 0);

    if ($subject === '' || $message === '' || empty($assignedToList)) {
        echo json_encode(['success' => false, 'message' => 'Subject, message and at least one assignee are required.']);
        exit;
    }

    $createdBy = resolveEmployeePk($con, $employee_id);

    $voucherNumberForLog = null;
    if ($voucherId) {
        $vq = mysqli_query($con, "SELECT voucher_number FROM finance_digital_expenses WHERE id=$voucherId AND added_by='".mysqli_real_escape_string($con,$employee_id)."' LIMIT 1");
        if ($vq && $vrow = mysqli_fetch_assoc($vq)) $voucherNumberForLog = $vrow['voucher_number'];
    }

    $ticketNums = raiseTicketsForAssignees($con, $employee_name_db, $subject, $message, $assignedToList, $createdBy);

    if (!empty($ticketNums)) {
        logExpHistory($con, 'Ticket Raised', $voucherNumberForLog, 'Raised ticket(s): ' . implode(', ', $ticketNums), $employee_name_db, $employee_id);
        attachTicketNumbersToVoucher($con, $voucherId, $ticketNums);
        echo json_encode(['success' => true, 'message' => count($ticketNums) . ' ticket(s) raised.', 'ticket_numbers' => $ticketNums]);
    } else {
        echo json_encode(['success' => false, 'message' => 'Could not create ticket(s).']);
    }
    exit;
}

// =========================================================================
// ADMIN AJAX — every endpoint below is gated on $isAdmin server-side.
// These let the one authorized admin (see identification block above)
// see and act on ALL employees' vouchers, not just their own.
// =========================================================================

if (isset($_GET['ajax_admin_filter_options'])) {
    header('Content-Type: application/json');
    if (!$canViewAllVouchers) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }
    $emps = [];
    $eq = mysqli_query($con, "SELECT DISTINCT added_by, added_by_name FROM finance_digital_expenses WHERE added_by_name IS NOT NULL AND added_by_name != '' ORDER BY added_by_name ASC");
    if ($eq) while ($er = mysqli_fetch_assoc($eq)) $emps[] = ['id' => $er['added_by'], 'name' => $er['added_by_name']];
    $companies = [];
    $cq = mysqli_query($con, "SELECT DISTINCT company_name FROM finance_digital_expenses WHERE company_name IS NOT NULL AND company_name != '' ORDER BY company_name ASC");
    if ($cq) while ($cr = mysqli_fetch_assoc($cq)) $companies[] = $cr['company_name'];
    echo json_encode(['success' => true, 'employees' => $emps, 'companies' => $companies]);
    exit;
}

if (isset($_GET['ajax_admin_list'])) {
    header('Content-Type: application/json');
    if (!$canViewAllVouchers) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }

    $aStatus = trim($_GET['a_status'] ?? 'All');
    $aEmp    = trim($_GET['a_employee'] ?? '');
    $aCompany= trim($_GET['a_company'] ?? '');
    $aSearch = trim($_GET['a_search'] ?? '');
    $aFrom   = trim($_GET['a_from'] ?? '');
    $aTo     = trim($_GET['a_to'] ?? '');

    $aWhere = "1=1";
    if ($aStatus !== 'All' && $aStatus !== '') $aWhere .= " AND status='" . mysqli_real_escape_string($con, $aStatus) . "'";
    if ($aEmp !== '') $aWhere .= " AND added_by='" . mysqli_real_escape_string($con, $aEmp) . "'";
    if ($aCompany !== '') $aWhere .= " AND company_name='" . mysqli_real_escape_string($con, $aCompany) . "'";
    if ($aFrom !== '') $aWhere .= " AND expense_date >= '" . mysqli_real_escape_string($con, $aFrom) . "'";
    if ($aTo !== '') $aWhere .= " AND expense_date <= '" . mysqli_real_escape_string($con, $aTo) . "'";
    if ($aSearch !== '') {
        $s = mysqli_real_escape_string($con, $aSearch);
        $aWhere .= " AND (voucher_number LIKE '%$s%' OR expense_category LIKE '%$s%' OR amount_paid_to LIKE '%$s%' OR added_by_name LIKE '%$s%' OR company_name LIKE '%$s%' OR status LIKE '%$s%')";
    }

    // Same filters, but WITHOUT the status clause — this is what the stat
    // cards are computed from, so clicking one status doesn't zero out
    // the others. The table itself still uses $aWhere (with status).
    $aWhereNoStatus = "1=1";
    if ($aEmp !== '') $aWhereNoStatus .= " AND added_by='" . mysqli_real_escape_string($con, $aEmp) . "'";
    if ($aCompany !== '') $aWhereNoStatus .= " AND company_name='" . mysqli_real_escape_string($con, $aCompany) . "'";
    if ($aFrom !== '') $aWhereNoStatus .= " AND expense_date >= '" . mysqli_real_escape_string($con, $aFrom) . "'";
    if ($aTo !== '') $aWhereNoStatus .= " AND expense_date <= '" . mysqli_real_escape_string($con, $aTo) . "'";
    if ($aSearch !== '') {
        $s = mysqli_real_escape_string($con, $aSearch);
        $aWhereNoStatus .= " AND (voucher_number LIKE '%$s%' OR expense_category LIKE '%$s%' OR amount_paid_to LIKE '%$s%' OR added_by_name LIKE '%$s%' OR company_name LIKE '%$s%' OR status LIKE '%$s%')";
    }

    $rows = [];
    $rq = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE $aWhere ORDER BY id DESC LIMIT 500");
    if ($rq) {
        while ($r = mysqli_fetch_assoc($rq)) {
            $pf = json_decode($r['proof_files'], true);
            $r['has_proof'] = !empty($pf);
            $rows[] = $r;
        }
    }

    $stat = ['total_amt'=>0,'approved'=>0,'declined'=>0,'pending'=>0,'response_submitted'=>0,'with_proof'=>0,'without_proof'=>0,'count'=>0];
    $sq = mysqli_query($con, "SELECT amount, status, proof_files FROM finance_digital_expenses WHERE $aWhereNoStatus");
    if ($sq) {
        while ($r = mysqli_fetch_assoc($sq)) {
            $pf = json_decode($r['proof_files'], true);
            $stat['count']++;
            $stat['total_amt'] += floatval($r['amount']);
            $st = strtoupper($r['status']);
            if ($st === 'APPROVED') $stat['approved']++;
            elseif ($st === 'DECLINED') $stat['declined']++;
            elseif ($st === 'RESPONSE SUBMITTED') $stat['response_submitted']++;
            else $stat['pending']++;
            if (!empty($pf)) $stat['with_proof']++; else $stat['without_proof']++;
        }
    }
    echo json_encode(['success' => true, 'data' => $rows, 'stats' => $stat]);
    exit;
}

// =========================================================================
// WHATSAPP APPROVERS — admin or Finance Department picks who gets the L1 / L2 approval requests
// =========================================================================
if (isset($_POST['ajax_dewa_get'])) {
    header('Content-Type: application/json');
    if (!$isAdminLogin) { echo json_encode(['success'=>false,'message'=>'Only the Administrator login can change the WhatsApp approvers.']); exit; }
    $s = dewaSettings($con);
    $emps = [];
    $q = mysqli_query($con, "SELECT id, name, phone, department, position FROM hr_employees WHERE status='active' ORDER BY name");
    while ($q && ($r = mysqli_fetch_assoc($q))) {
        $emps[] = ['id' => (int) $r['id'], 'name' => $r['name'], 'phone' => dewaPhone($r['phone']), 'department' => (string) $r['department'], 'position' => (string) $r['position']];
    }
    echo json_encode(['success' => true, 'enabled' => (int) $s['enabled'], 'lang' => $s['lang'] ?: 'en',
        'l1' => dewaIdList($s['l1_ids']), 'l2' => dewaIdList($s['l2_ids']), 'employees' => $emps,
        'updated_by' => $s['updated_by'] ?? '', 'updated_at' => !empty($s['updated_at']) ? date('d-m-Y h:i A', strtotime($s['updated_at'])) : '']);
    exit;
}
if (isset($_POST['ajax_dewa_save'])) {
    header('Content-Type: application/json');
    if (!$isAdminLogin) { echo json_encode(['success'=>false,'message'=>'Only the Administrator login can change the WhatsApp approvers.']); exit; }
    dewaSettings($con);
    $l1 = implode(',', array_unique(array_filter(array_map('intval', (array) ($_POST['l1'] ?? [])))));
    $l2 = implode(',', array_unique(array_filter(array_map('intval', (array) ($_POST['l2'] ?? [])))));
    $enabled = !empty($_POST['enabled']) ? 1 : 0;
    $lang = preg_replace('/[^A-Za-z_]/', '', (string) ($_POST['lang'] ?? 'en')) ?: 'en';
    if ($enabled && ($l1 === '' || $l2 === '')) { echo json_encode(['success'=>false,'message'=>'Pick at least one L1 and one L2 approver before turning WhatsApp approvals on.']); exit; }
    mysqli_query($con, "UPDATE finance_de_wa_settings SET enabled=$enabled, l1_ids='$l1', l2_ids='$l2', lang='$lang', updated_by='" . mysqli_real_escape_string($con, $currentUserName) . "', updated_at=NOW() WHERE id=1");
    echo json_encode(['success' => true, 'message' => 'WhatsApp approvers saved.']);
    exit;
}

if (isset($_POST['ajax_admin_set_status'])) {
    header('Content-Type: application/json');

    $id = intval($_POST['id'] ?? 0);
    // l1_approve | l1_decline | l2_approve | l2_decline | l2_override_approve | l2_override_decline | revert
    $action = trim($_POST['action'] ?? '');
    $reason = trim($_POST['reason'] ?? '');
    $overrideReason = trim($_POST['override_reason'] ?? '');

    $isL1Action = in_array($action, ['l1_approve', 'l1_decline', 'l1_revert']);
    $isL2Action = in_array($action, ['l2_approve', 'l2_decline', 'l2_override_approve', 'l2_override_decline']);
    $isOverrideAction = in_array($action, ['l2_override_approve', 'l2_override_decline']);

    if ($isL1Action && !$isL1Approver) { echo json_encode(['success'=>false,'message'=>'Not authorized. Only Finance Department members can act on L1 approval.']); exit; }
    if (($isL2Action || $action === 'revert') && !$isAdmin) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }
    if (!$isL1Action && !$isL2Action && $action !== 'revert') { echo json_encode(['success'=>false,'message'=>'Invalid action.']); exit; }

    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }

    if (in_array($action, ['l1_decline','l2_decline','l2_override_decline']) && $reason === '') {
        echo json_encode(['success'=>false,'message'=>'A reason is required to decline.']); exit;
    }
    if ($isOverrideAction && $overrideReason === '') {
        echo json_encode(['success'=>false,'message'=>'A justification is required to override L1.']); exit;
    }
    if (in_array($action, ['l2_approve','l2_decline']) && $exp['l1_status'] !== 'Approved') {
        echo json_encode(['success'=>false,'message'=>'This voucher is still waiting for L1 approval. Use Override if you need to act on it now.']); exit;
    }

    $nameEsc = mysqli_real_escape_string($con, $currentUserName);

    if ($action === 'l1_approve') {
        mysqli_query($con, "UPDATE finance_digital_expenses SET l1_status='Approved', l1_by='$nameEsc', l1_at=NOW(), l1_reason=NULL, status='Pending L2 Approval' WHERE id=$id");
        logExpHistory($con, 'L1 Approved', $exp['voucher_number'], 'L1 approved by ' . $currentUserName, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l1_decline') {
        $reasonEsc = mysqli_real_escape_string($con, $reason);
        mysqli_query($con, "UPDATE finance_digital_expenses SET l1_status='Declined', l1_by='$nameEsc', l1_at=NOW(), l1_reason='$reasonEsc', status='Declined', manager_reason='$reasonEsc' WHERE id=$id");
        logExpHistory($con, 'L1 Declined', $exp['voucher_number'], 'L1 declined by ' . $currentUserName . ': ' . $reason, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l1_revert') {
        if ($exp['l2_status'] !== 'Pending') {
            echo json_encode(['success'=>false,'message'=>'L2 has already acted on this voucher — it can no longer be reverted at L1.']); exit;
        }
        if (!in_array($exp['l1_status'], ['Approved','Declined'])) {
            echo json_encode(['success'=>false,'message'=>'Nothing to revert — L1 has not acted on this voucher yet.']); exit;
        }
        mysqli_query($con, "UPDATE finance_digital_expenses SET l1_status='Pending', l1_by=NULL, l1_at=NULL, l1_reason=NULL, status='Pending', manager_reason=NULL WHERE id=$id");
        logExpHistory($con, 'L1 Reverted', $exp['voucher_number'], 'L1 decision reverted back to Pending by ' . $currentUserName, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l2_approve') {
        mysqli_query($con, "UPDATE finance_digital_expenses SET l2_status='Approved', l2_by='$nameEsc', l2_at=NOW(), l2_reason=NULL, status='Approved', manager_reason=NULL, approved_by='$nameEsc', approved_at=NOW() WHERE id=$id");
        logExpHistory($con, 'L2 Approved', $exp['voucher_number'], 'L2 (admin) approved by ' . $currentUserName, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l2_decline') {
        $reasonEsc = mysqli_real_escape_string($con, $reason);
        mysqli_query($con, "UPDATE finance_digital_expenses SET l2_status='Declined', l2_by='$nameEsc', l2_at=NOW(), l2_reason='$reasonEsc', status='Declined', manager_reason='$reasonEsc', approved_by=NULL, approved_at=NULL WHERE id=$id");
        logExpHistory($con, 'L2 Declined', $exp['voucher_number'], 'L2 (admin) declined by ' . $currentUserName . ': ' . $reason, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l2_override_approve') {
        $overrideEsc = mysqli_real_escape_string($con, $overrideReason);
        $l1SkipSql = ($exp['l1_status'] !== 'Approved') ? ", l1_status='Skipped (L2 Override)'" : "";
        mysqli_query($con, "UPDATE finance_digital_expenses SET l2_status='Approved', l2_by='$nameEsc', l2_at=NOW(), l2_reason=NULL, l2_override=1, l2_override_reason='$overrideEsc' $l1SkipSql, status='Approved', manager_reason=NULL, approved_by='$nameEsc', approved_at=NOW() WHERE id=$id");
        logExpHistory($con, 'L2 Approved (Override)', $exp['voucher_number'], 'L2 (admin) approved via override by ' . $currentUserName . ' — bypassed L1. Justification: ' . $overrideReason, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'l2_override_decline') {
        $reasonEsc = mysqli_real_escape_string($con, $reason);
        $overrideEsc = mysqli_real_escape_string($con, $overrideReason);
        $l1SkipSql = ($exp['l1_status'] !== 'Approved') ? ", l1_status='Skipped (L2 Override)'" : "";
        mysqli_query($con, "UPDATE finance_digital_expenses SET l2_status='Declined', l2_by='$nameEsc', l2_at=NOW(), l2_reason='$reasonEsc', l2_override=1, l2_override_reason='$overrideEsc' $l1SkipSql, status='Declined', manager_reason='$reasonEsc', approved_by=NULL, approved_at=NULL WHERE id=$id");
        logExpHistory($con, 'L2 Declined (Override)', $exp['voucher_number'], 'L2 (admin) declined via override by ' . $currentUserName . ' — bypassed L1. Justification: ' . $overrideReason . '. Reason: ' . $reason, $exp['added_by_name'], $exp['added_by']);

    } elseif ($action === 'revert') {
        // Once a payment has been initiated/completed on an Approved voucher,
        // undoing the approval would contradict money that's already moving —
        // block the revert in that case.
        if ($exp['status'] === 'Approved' && !empty($exp['payment_status'])) {
            echo json_encode(['success'=>false,'message'=>'Cannot revert — a payment status (' . $exp['payment_status'] . ') has already been set for this voucher.']); exit;
        }
        // Reverting a fully Approved voucher wipes BOTH stages clean — L1 and
        // L2 each make a fresh decision, nothing carries over.
        // Reverting a Declined voucher preserves a genuine L1 approval when
        // L2 was the one who declined it — only L2's stage resets, since
        // L1 already made a real decision that still stands. If L1 itself
        // declined it (or never genuinely reviewed it), both stages reset.
        $preserveL1 = ($exp['status'] === 'Declined' && $exp['l1_status'] === 'Approved');
        if ($preserveL1) {
            mysqli_query($con, "UPDATE finance_digital_expenses SET status='Pending L2 Approval', manager_reason=NULL, approved_at=NULL, approved_by=NULL, l2_status='Pending', l2_by=NULL, l2_at=NULL, l2_reason=NULL, l2_override=0, l2_override_reason=NULL WHERE id=$id");
            logExpHistory($con, 'Reverted', $exp['voucher_number'], 'Reverted to Pending L2 Approval by admin (' . $currentUserName . ') — L1 approval kept, only L2 reset', $exp['added_by_name'], $exp['added_by']);
        } else {
            mysqli_query($con, "UPDATE finance_digital_expenses SET status='Pending', manager_reason=NULL, approved_at=NULL, approved_by=NULL, l1_status='Pending', l1_by=NULL, l1_at=NULL, l1_reason=NULL, l2_status='Pending', l2_by=NULL, l2_at=NULL, l2_reason=NULL, l2_override=0, l2_override_reason=NULL WHERE id=$id");
            logExpHistory($con, 'Reverted', $exp['voucher_number'], 'Reverted to Pending (L1) by admin (' . $currentUserName . ')', $exp['added_by_name'], $exp['added_by']);
        }
    }

    // WhatsApp follow-ups — same as when the decision is made from WhatsApp
    $waMe = $employee_id; $waMeName = $currentUserName;
    if ($action === 'l1_approve') {
        dewaDefer(function ($con) use ($id, $waMe, $waMeName) { dewaSendLevel($con, $id, 2); dewaThankApprover($con, $id, 1, $waMe, $waMeName); });
    } elseif (in_array($action, ['l2_approve', 'l2_override_approve'])) {
        // final approval -> finance (L1) asked to initiate the payment, approver thanked
        dewaDefer(function ($con) use ($id, $waMe, $waMeName) { dewaNotifyPayment($con, $id, $waMeName); dewaThankApprover($con, $id, 2, $waMe, $waMeName); });
    } elseif (in_array($action, ['l1_decline', 'l2_decline', 'l2_override_decline'])) {
        $waBy = $currentUserName;
        dewaDefer(function ($con) use ($id, $waBy, $reason) { dewaNotifyRejected($con, $id, $waBy, $reason); });
    } elseif ($action === 'l1_revert') {
        dewaDefer(function ($con) use ($id) { dewaSendLevel($con, $id, 1, 'L1 decision was reverted — please review again'); });
    } elseif ($action === 'revert') {
        $waLevel = !empty($preserveL1) ? 2 : 1;
        dewaDefer(function ($con) use ($id, $waLevel) { dewaSendLevel($con, $id, $waLevel, 'Sent back for review by admin'); });
    }

    echo json_encode(['success' => true, 'message' => 'Voucher updated successfully.']);
    exit;
}

if (isset($_POST['ajax_admin_delete'])) {
    header('Content-Type: application/json');
    if (!$isAdmin) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }

    $id = intval($_POST['id'] ?? 0);
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }

    deleteProofFiles($exp['proof_files'], $upload_dir);
    deleteProofFiles($exp['rebuttal_proof_files'], $upload_dir);
    mysqli_query($con, "DELETE FROM finance_digital_expenses WHERE id=$id");
    logExpHistory($con, 'Deleted', $exp['voucher_number'], 'Deleted by admin (' . $currentUserName . ')', $exp['added_by_name'], $exp['added_by']);

    echo json_encode(['success' => true, 'message' => 'Voucher deleted successfully.']);
    exit;
}

// =========================================================================
// ADMIN SIGNATURE — upload/fetch the digital signature stamped onto
// approved vouchers in the printed PDF.
// =========================================================================
if (isset($_GET['ajax_admin_get_signature'])) {
    header('Content-Type: application/json');
    if (!$canViewAllVouchers) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }
    $sq = mysqli_query($con, "SELECT signature_path, uploaded_by, uploaded_at FROM finance_admin_signature ORDER BY id DESC LIMIT 1");
    $srow = $sq ? mysqli_fetch_assoc($sq) : null;
    echo json_encode(['success' => true, 'signature' => $srow]);
    exit;
}

if (isset($_POST['ajax_admin_upload_signature'])) {
    header('Content-Type: application/json');
    if (!$canViewAllVouchers) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }

    if (empty($_FILES['signature_file']) || $_FILES['signature_file']['error'] !== UPLOAD_ERR_OK) {
        echo json_encode(['success'=>false,'message'=>'Please choose a signature image to upload.']); exit;
    }
    $f = $_FILES['signature_file'];
    if ($f['size'] > $signature_max_size) {
        echo json_encode(['success'=>false,'message'=>'Signature image must be under 2MB.']); exit;
    }
    $ext = strtolower(pathinfo($f['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, $signature_allowed_ext)) {
        echo json_encode(['success'=>false,'message'=>'Only JPG, PNG, or WEBP images are allowed for the signature.']); exit;
    }
    $fname = 'signature-' . time() . '-' . mt_rand(1000,9999) . '.' . $ext;
    $dest = $signature_upload_dir . $fname;
    if (!move_uploaded_file($f['tmp_name'], $dest)) {
        echo json_encode(['success'=>false,'message'=>'Could not save the uploaded file.']); exit;
    }
    $urlPath = $signature_upload_url_base . $fname;
    $urlPathEsc = mysqli_real_escape_string($con, $urlPath);
    $adminNameEsc = mysqli_real_escape_string($con, $currentUserName);
    mysqli_query($con, "INSERT INTO finance_admin_signature (signature_path, uploaded_by) VALUES ('$urlPathEsc', '$adminNameEsc')");
    echo json_encode(['success' => true, 'message' => 'Signature uploaded successfully.', 'signature_path' => $urlPath]);
    exit;
}

// =========================================================================
// PAYMENT STATUS — post-approval money-movement stage. Available to the
// whole finance team ($canViewAllVouchers), not just the true admin, since
// tracking disbursement is a finance-ops task separate from approve/decline.
// Only applies once the voucher's main status is Approved.
// =========================================================================
if (isset($_POST['ajax_update_payment_status'])) {
    header('Content-Type: application/json');
    if (!$canViewAllVouchers) { echo json_encode(['success'=>false,'message'=>'Not authorized.']); exit; }

    $id = intval($_POST['id'] ?? 0);
    $newPayStatus = trim($_POST['payment_status'] ?? '');
    if ($newPayStatus === '' || !in_array($newPayStatus, $payment_status_options)) {
        echo json_encode(['success'=>false,'message'=>'Please choose a valid payment status.']); exit;
    }

    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }
    if (strtolower($exp['status']) !== 'approved') {
        echo json_encode(['success'=>false,'message'=>'Payment status can only be set on Approved vouchers.']); exit;
    }

    $payStatusEsc = mysqli_real_escape_string($con, $newPayStatus);
    $userEsc = mysqli_real_escape_string($con, $currentUserName);
    mysqli_query($con, "UPDATE finance_digital_expenses SET payment_status='$payStatusEsc', payment_status_updated_by='$userEsc', payment_status_updated_at=NOW() WHERE id=$id");
    logExpHistory($con, 'Payment Status Updated', $exp['voucher_number'], 'Payment status set to "' . $newPayStatus . '" by ' . $currentUserName, $exp['added_by_name'], $exp['added_by']);

    if (in_array($newPayStatus, ['Payment Initiated', 'Initiated from Bank'])) {
        $initUser = $currentUserName;
        dewaDefer(function ($c) use ($id, $initUser) {
            dewaNotifyPaymentInitiated($c, $id, $initUser);
        });
    }

    echo json_encode(['success' => true, 'message' => 'Payment status updated.' . ($newPayStatus === 'Payment Initiated' ? ' WhatsApp alert sent to employee.' : '')]);
    exit;
}

// =========================================================================
// PER-VOUCHER HISTORY — full lifecycle timeline for ONE voucher (created,
// approved, declined, response submitted, payment status changes, etc.).
// Visible to anyone allowed to see the voucher: its owner, the admin, or
// finance-read-only viewers.
// =========================================================================
if (isset($_GET['ajax_voucher_history'])) {
    header('Content-Type: application/json');
    $id = intval($_GET['ajax_voucher_history']);
    $ownerClauseHist = $canViewAllVouchers ? "1=1" : "added_by='".mysqli_real_escape_string($con,$employee_id)."'";
    $q = mysqli_query($con, "SELECT voucher_number, added_by_name, added_by, created_at FROM finance_digital_expenses WHERE id=$id AND $ownerClauseHist LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }

    $vnEsc = mysqli_real_escape_string($con, $exp['voucher_number']);
    $createdAtEsc = mysqli_real_escape_string($con, $exp['created_at']);
    // Guard against pre-existing voucher-number collisions (from before numbers
    // were made permanently unique): only pull history from this voucher's own
    // creation time onward, so an older, unrelated voucher that happened to
    // reuse the same number never bleeds into this timeline.
    $hq = mysqli_query($con, "SELECT action, details, performed_by, created_at FROM finance_digital_expense_history WHERE voucher_number='$vnEsc' AND created_at >= '$createdAtEsc' ORDER BY created_at ASC");
    $timeline = [];
    if ($hq) {
        while ($h = mysqli_fetch_assoc($hq)) {
            $timeline[] = [
                'action' => $h['action'],
                'details' => $h['details'],
                'performed_by' => $h['performed_by'],
                'date' => date('d M Y, h:i A', strtotime($h['created_at']))
            ];
        }
    }
    echo json_encode(['success' => true, 'voucher_number' => $exp['voucher_number'], 'created_by' => $exp['added_by_name'], 'created_at' => date('d M Y, h:i A', strtotime($exp['created_at'])), 'timeline' => $timeline]);
    exit;
}



// =========================================================================
if (isset($_GET['ajax_get_voucher'])) {
    header('Content-Type: application/json');
    $id = intval($_GET['ajax_get_voucher']);
    $ownerClause = $canViewAllVouchers ? "1=1" : "added_by='".mysqli_real_escape_string($con,$employee_id)."'";
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id AND $ownerClause LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) { echo json_encode(['success'=>false,'message'=>'Voucher not found.']); exit; }
    $exp['proof_files_arr'] = json_decode($exp['proof_files'], true) ?: [];
    $exp['rebuttal_proof_files_arr'] = json_decode($exp['rebuttal_proof_files'], true) ?: [];
    $exp['ticket_numbers_arr'] = !empty($exp['ticket_numbers']) ? array_filter(array_map('trim', explode(',', $exp['ticket_numbers']))) : [];
    echo json_encode(['success' => true, 'data' => $exp]);
    exit;
}

// =========================================================================
// PRINT / VIEW VOUCHER (browser-print page, same convention as certificates)
// =========================================================================
if (isset($_GET['view']) && $_GET['view'] === 'voucher' && isset($_GET['id'])) {
    $id = intval($_GET['id']);
    $ownerClausePrint = $canViewAllVouchers ? "1=1" : "added_by='".mysqli_real_escape_string($con,$employee_id)."'";
    $q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE id=$id AND $ownerClausePrint LIMIT 1");
    $exp = $q ? mysqli_fetch_assoc($q) : null;
    if (!$exp) die("<div style='padding:60px;text-align:center;font-family:Arial,sans-serif;'><h3>Voucher not found.</h3></div>");
    render_voucher_print($con, $exp);
    exit;
}

function render_voucher_print($con, $a) {
    $proofs = json_decode($a['proof_files'], true) ?: [];
    $rebuttalProofs = json_decode($a['rebuttal_proof_files'] ?? '', true) ?: [];
    $style = getStatusStyle($a['status']);
    $dateDisplay = date('d/m/Y', strtotime($a['expense_date']));
    $isApproved = strtolower($a['status']) === 'approved';
    $signaturePath = null;
    if ($isApproved) {
        $sq = mysqli_query($con, "SELECT signature_path FROM finance_admin_signature ORDER BY id DESC LIMIT 1");
        if ($sq && $srow = mysqli_fetch_assoc($sq)) $signaturePath = $srow['signature_path'];
    }
    ?>
    <!DOCTYPE html>
    <html><head><meta charset="utf-8">
    <title>Voucher — <?php echo htmlspecialchars($a['voucher_number']); ?></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    html, body, .v-page, .v-page * {
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
        color-adjust: exact !important;
    }
    body{font-family:'Poppins',sans-serif;background:#eef2f7;padding:40px 20px;}
    .v-page{max-width:760px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 20px 60px rgba(0,0,0,.18);overflow:hidden;}
    .v-header{background:linear-gradient(135deg,#0D1B3E,#1A3A6B);color:#fff;padding:22px 30px;display:flex;justify-content:space-between;align-items:center;}
    .v-header h2{font-size:19px;font-weight:700;}
    .v-header .sub{font-size:12px;opacity:.85;margin-top:3px;}
    .v-body{padding:30px;}
    .v-status{display:inline-block;padding:7px 18px;border-radius:20px;font-weight:700;font-size:13px;background:<?php echo $style['bg']; ?>;color:<?php echo $style['c']; ?>;margin-bottom:20px;}
    .v-row{display:flex;padding:10px 0;border-bottom:1px dashed #e2e8f0;}
    .v-label{width:180px;color:#64748b;font-size:12.5px;font-weight:600;}
    .v-value{flex:1;color:#0f172a;font-weight:600;font-size:14px;}
    .v-decline{background:#fef2f2;border-radius:8px;padding:12px 16px;margin-top:16px;color:#991b1b;font-size:13px;}
    .v-sig{display:flex;justify-content:space-around;margin-top:40px;}
    .v-sig-block{width:200px;text-align:center;border-top:1.5px solid #94a3b8;padding-top:10px;font-size:12px;font-weight:700;color:#0f2557;}
    .v-proofs{margin-top:26px;}
    .v-proofs-grid img{page-break-inside:avoid;}
    .v-proofs h4{font-size:14px;color:#0f2557;margin-bottom:12px;}
    .v-proofs-grid{display:flex;flex-wrap:wrap;gap:10px;}
    .v-proofs-grid img{width:230px;height:230px;object-fit:cover;border-radius:8px;border:1px solid #e2e8f0;display:block;}
    .proof-pdf-chip{display:flex;align-items:center;gap:10px;background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:10px 14px;text-decoration:none;color:#0f172a;max-width:280px;}
    .proof-pdf-chip i.fa-file-pdf{color:#dc2626;font-size:18px;flex-shrink:0;}
    .proof-pdf-name{font-size:12px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;}
    .proof-pdf-dl{font-size:11px;font-weight:700;color:#1a3fc4;white-space:nowrap;}
    .no-print{text-align:center;margin-bottom:18px;}
    .no-print button{padding:12px 26px;background:#0f2557;color:#fff;border:none;border-radius:9px;font-weight:700;cursor:pointer;font-family:inherit;font-size:13px;margin:0 5px;}
    @media print{
        body{background:#fff;padding:0;}
        .no-print{display:none!important;}
        .v-page{box-shadow:none;max-width:100%;}
        @page { margin: 12mm; }
    }
    </style>
    </head><body>
    <div class="no-print">
        <button onclick="downloadV()"><i class="fas fa-download"></i> Download as Image</button>
        <button onclick="window.print()" style="background:#475569;"><i class="fas fa-print"></i> Print / Save as PDF</button>
    </div>
    <div class="v-page" id="vBox">
        <div class="v-header">
            <div>
                <h2>Payment Voucher — <?php echo htmlspecialchars($a['voucher_number']); ?></h2>
                <div class="sub"><?php echo htmlspecialchars($a['company_name'] ?: 'Abra'); ?></div>
            </div>
            <i class="fas fa-receipt" style="font-size:22px;opacity:.85;"></i>
        </div>
        <div class="v-body">
            <div class="v-status"><?php echo $style['icon'].' '.htmlspecialchars($a['status']); ?></div>
            <?php if ($a['status'] === 'Declined' && !empty($a['manager_reason'])): ?>
            <div class="v-decline"><strong>Reason for Decline:</strong> <?php echo htmlspecialchars($a['manager_reason']); ?></div>
            <?php endif; ?>
            <?php if (!empty($a['l1_status']) && $a['l1_status'] !== 'Pending'): ?>
            <div class="v-row"><div class="v-label">L1 Approval</div><div class="v-value"><?php echo htmlspecialchars($a['l1_status']); ?><?php if (!empty($a['l1_by'])) echo ' — ' . htmlspecialchars($a['l1_by']); ?><?php if (!empty($a['l1_at'])) echo ' (' . date('d/m/Y H:i', strtotime($a['l1_at'])) . ')'; ?></div></div>
            <?php endif; ?>
            <?php if (!empty($a['l2_status']) && $a['l2_status'] !== 'Pending'): ?>
            <div class="v-row"><div class="v-label">L2 Approval</div><div class="v-value"><?php echo htmlspecialchars($a['l2_status']); ?><?php if (!empty($a['l2_by'])) echo ' — ' . htmlspecialchars($a['l2_by']); ?><?php if (!empty($a['l2_at'])) echo ' (' . date('d/m/Y H:i', strtotime($a['l2_at'])) . ')'; ?><?php if (!empty($a['l2_override'])) echo ' (Override)'; ?></div></div>
            <?php endif; ?>

            <div class="v-row"><div class="v-label">Voucher No</div><div class="v-value"><?php echo htmlspecialchars($a['voucher_number']); ?></div></div>
            <div class="v-row"><div class="v-label">Date</div><div class="v-value"><?php echo $dateDisplay; ?></div></div>
            <div class="v-row"><div class="v-label">Amount</div><div class="v-value">₹<?php echo number_format($a['amount'],2); ?></div></div>
            <div class="v-row"><div class="v-label">Payment Method</div><div class="v-value"><?php echo htmlspecialchars($a['payment_method'] ?: '-'); ?></div></div>
            <div class="v-row"><div class="v-label">Amount Paid To</div><div class="v-value"><?php echo htmlspecialchars($a['amount_paid_to'] ?: '-'); ?></div></div>
            <div class="v-row"><div class="v-label">Amount in Words</div><div class="v-value"><?php echo htmlspecialchars($a['amount_in_words'] ?: '-'); ?></div></div>
            <div class="v-row"><div class="v-label">On Account Of</div><div class="v-value"><?php echo htmlspecialchars($a['on_account_of'] ?: '-'); ?></div></div>
            <div class="v-row"><div class="v-label">Received Person</div><div class="v-value"><?php echo htmlspecialchars($a['received_by'] ?: '-'); ?></div></div>
            <div class="v-row"><div class="v-label">Expense Category</div><div class="v-value"><?php echo htmlspecialchars($a['expense_category']); ?></div></div>
            <?php if (!empty($a['ticket_numbers'])): ?>
            <?php if (!empty($a['payment_status'])): ?>
            <div class="v-row"><div class="v-label">Payment Status</div><div class="v-value" style="color:#0f766e;"><?php echo htmlspecialchars($a['payment_status']); ?></div></div>
            <?php endif; ?>
            <div class="v-row"><div class="v-label">Linked Ticket(s)</div><div class="v-value"><?php echo htmlspecialchars(implode(', ', array_filter(array_map('trim', explode(',', $a['ticket_numbers']))))); ?></div></div>
            <?php endif; ?>

            <div class="v-sig">
                <div class="v-sig-block"><?php echo htmlspecialchars($a['added_by_name'] ?: 'Employee'); ?><br><span style="font-weight:400;color:#64748b;">Prepared By</span></div>
                <div style="width:220px;">
                    <?php if ($isApproved && $signaturePath): ?>
                    <img src="<?php echo htmlspecialchars($signaturePath); ?>" style="max-height:100px;max-width:220px;display:block;margin:0 auto 4px;">
                    <?php endif; ?>
                    <div class="v-sig-block" style="width:100%;color:<?php echo $isApproved ? '#059669' : '#c2410c'; ?>;">
                        <?php echo $isApproved ? 'Approved Digitally' : 'Pending Approval'; ?><br><span style="font-weight:400;color:#64748b;">Manager Approval</span>
                    </div>
                </div>
            </div>

            <?php if (!empty($proofs)): ?>
            <div class="v-proofs">
                <h4><i class="fas fa-paperclip"></i> Attached Proofs</h4>
                <div class="v-proofs-grid">
                <?php foreach ($proofs as $p): ?>
                    <?php if (!empty($p['filename'])): ?>
                        <?php if (isPdfFile($p['filename'])): ?>
                        <a class="proof-pdf-chip" href="<?php echo htmlspecialchars($p['path']); ?>" target="_blank">
                            <i class="fas fa-file-pdf"></i>
                            <span class="proof-pdf-name"><?php echo htmlspecialchars($p['originalName'] ?? $p['filename']); ?></span>
                            <span class="proof-pdf-dl"><i class="fas fa-download"></i> Download</span>
                        </a>
                        <?php else: ?>
                        <img src="<?php echo htmlspecialchars($p['path']); ?>" alt="proof">
                        <?php endif; ?>
                    <?php endif; ?>
                <?php endforeach; ?>
                </div>
            </div>
            <?php endif; ?>

            <?php if (!empty($a['employee_response']) || !empty($rebuttalProofs)): ?>
            <div class="v-proofs" style="margin-top:22px;">
                <h4 style="color:#7b1fa2;"><i class="fas fa-reply"></i> Rebuttal / Employee Explanation</h4>
                <?php if (!empty($a['employee_response'])): ?>
                <div style="background:#f3e5f5;border-radius:8px;padding:12px 16px;color:#6a1b9a;font-size:13px;margin-bottom:14px;"><?php echo nl2br(htmlspecialchars($a['employee_response'])); ?></div>
                <?php endif; ?>
                <?php if (!empty($rebuttalProofs)): ?>
                <div class="v-proofs-grid">
                <?php foreach ($rebuttalProofs as $p): ?>
                    <?php if (!empty($p['filename'])): ?>
                        <?php if (isPdfFile($p['filename'])): ?>
                        <a class="proof-pdf-chip" href="<?php echo htmlspecialchars($p['path']); ?>" target="_blank">
                            <i class="fas fa-file-pdf"></i>
                            <span class="proof-pdf-name"><?php echo htmlspecialchars($p['originalName'] ?? $p['filename']); ?></span>
                            <span class="proof-pdf-dl"><i class="fas fa-download"></i> Download</span>
                        </a>
                        <?php else: ?>
                        <img src="<?php echo htmlspecialchars($p['path']); ?>" alt="rebuttal proof">
                        <?php endif; ?>
                    <?php endif; ?>
                <?php endforeach; ?>
                </div>
                <?php endif; ?>
            </div>
            <?php endif; ?>
        </div>
    </div>
    <script>
    function downloadV(){
        html2canvas(document.getElementById('vBox'), {scale:2, useCORS:true, backgroundColor:'#ffffff'}).then(function(canvas){
            var link = document.createElement('a');
            link.download = 'Voucher_<?php echo preg_replace('/[^A-Za-z0-9]/','_',$a['voucher_number']); ?>.jpg';
            link.href = canvas.toDataURL('image/jpeg', 0.92);
            link.click();
        });
    }
    </script>
    </body></html>
    <?php
}

// =========================================================================
// FILTER VALUES (main page)
// =========================================================================
$filter_status = isset($_GET['f_status']) ? $_GET['f_status'] : 'All';
$filter_search = isset($_GET['f_search']) ? trim($_GET['f_search']) : '';
$filter_from   = isset($_GET['f_from']) ? $_GET['f_from'] : '';
$filter_to     = isset($_GET['f_to']) ? $_GET['f_to'] : '';
$status_options = ['All','Pending','Pending L2 Approval','Approved','Declined','Response Submitted'];

$where = "added_by='" . mysqli_real_escape_string($con, $employee_id) . "'";
if ($filter_status !== 'All') $where .= " AND status='" . mysqli_real_escape_string($con, $filter_status) . "'";
if (!empty($filter_from)) $where .= " AND expense_date >= '" . mysqli_real_escape_string($con, $filter_from) . "'";
if (!empty($filter_to)) $where .= " AND expense_date <= '" . mysqli_real_escape_string($con, $filter_to) . "'";
if (!empty($filter_search)) {
    $s = mysqli_real_escape_string($con, $filter_search);
    $where .= " AND (
        voucher_number LIKE '%$s%'
        OR expense_category LIKE '%$s%'
        OR amount_paid_to LIKE '%$s%'
        OR on_account_of LIKE '%$s%'
        OR received_by LIKE '%$s%'
        OR payment_method LIKE '%$s%'
        OR amount_in_words LIKE '%$s%'
        OR status LIKE '%$s%'
        OR added_by_name LIKE '%$s%'
        OR company_name LIKE '%$s%'
        OR department LIKE '%$s%'
        OR ticket_numbers LIKE '%$s%'
        OR manager_reason LIKE '%$s%'
        OR employee_response LIKE '%$s%'
        OR CAST(amount AS CHAR) LIKE '%$s%'
        OR DATE_FORMAT(expense_date, '%d/%m/%Y') LIKE '%$s%'
        OR DATE_FORMAT(expense_date, '%d-%m-%Y') LIKE '%$s%'
        OR DATE_FORMAT(created_at, '%d/%m/%Y') LIKE '%$s%'
    )";
}

$list_q = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE $where ORDER BY created_at DESC");
$expenses = [];
$stat_total_amt = 0; $stat_approved = 0; $stat_declined = 0; $stat_pending = 0; $stat_with_proof = 0; $stat_without_proof = 0;
if ($list_q) {
    while ($r = mysqli_fetch_assoc($list_q)) {
        $expenses[] = $r;
        $stat_total_amt += floatval($r['amount']);
        $st = strtoupper($r['status']);
        if ($st === 'APPROVED') $stat_approved++;
        elseif ($st === 'DECLINED') $stat_declined++;
        else $stat_pending++; // Pending or Response Submitted counted as pending-bucket for the badge
        $pf = json_decode($r['proof_files'], true);
        if (!empty($pf)) $stat_with_proof++; else $stat_without_proof++;
    }
}
$total_vouchers = count($expenses);

// =========================================================================
// EXPORT (CSV) — respects whatever filters are currently applied above
// (status / search / date range), or exports everything if no filters set.
// Must run before any HTML output.
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] === 'csv') {
    $filename = 'digital-expenses-' . $employee_id . '-' . date('Ymd-His') . '.csv';
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    $out = fopen('php://output', 'w');
    fputs($out, "\xEF\xBB\xBF"); // UTF-8 BOM so ₹ and names render correctly in Excel
    fputcsv($out, ['Voucher No', 'Date', 'Category', 'Description', 'Amount', 'Payment Method', 'Paid To', 'Received Person', 'Amount in Words', 'Status', 'Has Proof', 'Linked Ticket(s)', 'Created At']);
    foreach ($expenses as $row) {
        $pf = json_decode($row['proof_files'], true);
        fputcsv($out, [
            $row['voucher_number'],
            date('d/m/Y', strtotime($row['expense_date'])),
            $row['expense_category'],
            $row['on_account_of'],
            number_format((float)$row['amount'], 2, '.', ''),
            $row['payment_method'],
            $row['amount_paid_to'],
            $row['received_by'],
            $row['amount_in_words'],
            $row['status'],
            !empty($pf) ? 'Yes' : 'No',
            $row['ticket_numbers'],
            date('d/m/Y H:i', strtotime($row['created_at']))
        ]);
    }
    fclose($out);
    exit;
}

// =========================================================================
// EXPORT (CSV) — Admin / All Vouchers (Read Only) panel.
// Respects that panel's own filters (employee/company/status/search/date).
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] === 'csv_admin') {
    if (!$canViewAllVouchers) { die('Not authorized.'); }

    $eStatus = trim($_GET['a_status'] ?? 'All');
    $eEmp    = trim($_GET['a_employee'] ?? '');
    $eCompany= trim($_GET['a_company'] ?? '');
    $eSearch = trim($_GET['a_search'] ?? '');
    $eFrom   = trim($_GET['a_from'] ?? '');
    $eTo     = trim($_GET['a_to'] ?? '');

    $eWhere = "1=1";
    if ($eStatus !== 'All' && $eStatus !== '') $eWhere .= " AND status='" . mysqli_real_escape_string($con, $eStatus) . "'";
    if ($eEmp !== '') $eWhere .= " AND added_by='" . mysqli_real_escape_string($con, $eEmp) . "'";
    if ($eCompany !== '') $eWhere .= " AND company_name='" . mysqli_real_escape_string($con, $eCompany) . "'";
    if ($eFrom !== '') $eWhere .= " AND expense_date >= '" . mysqli_real_escape_string($con, $eFrom) . "'";
    if ($eTo !== '') $eWhere .= " AND expense_date <= '" . mysqli_real_escape_string($con, $eTo) . "'";
    if ($eSearch !== '') {
        $s = mysqli_real_escape_string($con, $eSearch);
        $eWhere .= " AND (voucher_number LIKE '%$s%' OR expense_category LIKE '%$s%' OR amount_paid_to LIKE '%$s%' OR added_by_name LIKE '%$s%' OR company_name LIKE '%$s%' OR status LIKE '%$s%')";
    }

    $filename = 'digital-expenses-all-' . date('Ymd-His') . '.csv';
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    $out = fopen('php://output', 'w');
    fputs($out, "\xEF\xBB\xBF");
    fputcsv($out, ['Employee', 'Voucher No', 'Date', 'Category', 'Description', 'Amount', 'Payment Method', 'Paid To', 'Received Person', 'Amount in Words', 'Status', 'Decline Reason', 'L1 Status', 'L1 By', 'L1 At', 'L2 Status', 'L2 By', 'L2 At', 'L2 Override', 'Has Proof', 'Linked Ticket(s)', 'Created At']);
    $eq = mysqli_query($con, "SELECT * FROM finance_digital_expenses WHERE $eWhere ORDER BY created_at DESC");
    if ($eq) {
        while ($row = mysqli_fetch_assoc($eq)) {
            $pf = json_decode($row['proof_files'], true);
            fputcsv($out, [
                $row['added_by_name'],
                $row['voucher_number'],
                date('d/m/Y', strtotime($row['expense_date'])),
                $row['expense_category'],
                $row['on_account_of'],
                number_format((float)$row['amount'], 2, '.', ''),
                $row['payment_method'],
                $row['amount_paid_to'],
                $row['received_by'],
                $row['amount_in_words'],
                $row['status'],
                $row['manager_reason'],
                $row['l1_status'],
                $row['l1_by'],
                $row['l1_at'] ? date('d/m/Y H:i', strtotime($row['l1_at'])) : '',
                $row['l2_status'],
                $row['l2_by'],
                $row['l2_at'] ? date('d/m/Y H:i', strtotime($row['l2_at'])) : '',
                $row['l2_override'] ? 'Yes' : 'No',
                !empty($pf) ? 'Yes' : 'No',
                $row['ticket_numbers'],
                date('d/m/Y H:i', strtotime($row['created_at']))
            ]);
        }
    }
    fclose($out);
    exit;
}
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Digital Expenses</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
* { margin:0; padding:0; box-sizing:border-box; }
html, body { overflow-x:hidden; max-width:100%; }
body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:30px 0; color:#334155; width:100%; }
.main-wrapper { max-width:1550px; margin:0 auto; padding:0 20px; width:100%; }

.header-card { background:linear-gradient(135deg,#0f2557 0%,#1a3fc4 100%); border-radius:12px; padding:25px 35px; margin-bottom:25px; box-shadow:0 4px 20px rgba(15,37,87,.35); color:white; }

.dx-tabs { display:flex; gap:10px; margin-bottom:20px; }
.dx-tab { flex:1; padding:14px 20px; border:none; border-radius:10px; background:#fff; color:#64748b; font-weight:700; font-size:14px; cursor:pointer; box-shadow:0 2px 8px rgba(0,0,0,.06); display:flex; align-items:center; justify-content:center; gap:8px; transition:all .2s; }
.dx-tab:hover { background:#f1f5f9; }
.dx-tab.active { background:linear-gradient(135deg,#7c2d12,#c2410c); color:#fff; box-shadow:0 4px 14px rgba(194,65,12,.3); }
.dx-tab.active#tabBtnMine { background:linear-gradient(135deg,#0f2557,#1a3fc4); box-shadow:0 4px 14px rgba(15,37,87,.3); }
.adm-reason-note { font-size:10.5px; margin-top:4px; max-width:170px; display:block; line-height:1.4; }
.adm-reason-note .reason-readmore { color:#1a3fc4; font-weight:700; text-decoration:underline; cursor:pointer; margin-left:3px; white-space:nowrap; }
.header-content { display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:15px; }
.header-title h1 { font-size:26px; font-weight:700; margin-bottom:5px; }
.header-title p { color:rgba(255,255,255,.9); font-size:13px; }
.btn-back { background:rgba(255,255,255,.18); color:white; padding:10px 20px; border-radius:10px; font-weight:600; text-decoration:none; border:1px solid rgba(255,255,255,.3); display:inline-flex; align-items:center; gap:8px; }
.btn-back:hover { background:white; color:#0f2557; text-decoration:none; }

.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px; margin-bottom:25px; }
.stat-card { background:white; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.06); display:flex; align-items:center; gap:14px; transition:transform .15s, box-shadow .15s; }
.stat-card[style*="cursor:pointer"]:hover { transform:translateY(-2px); box-shadow:0 6px 16px rgba(0,0,0,.1); border-color:#cbd5e1; }
.stat-icon { width:46px; height:46px; border-radius:10px; display:flex; align-items:center; justify-content:center; font-size:21px; color:#fff; }
.stat-label { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; }
.stat-value { font-size:20px; font-weight:800; color:#1e293b; }

.filter-panel { background:white; padding:18px 22px; border-radius:12px; margin-bottom:20px; border:2px solid #e2e8f0; box-shadow:0 2px 10px rgba(0,0,0,.06); }
.filter-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:14px; align-items:end; }
.filter-group label { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; display:block; margin-bottom:6px; }
.filter-group select, .filter-group input { width:100%; padding:10px 12px; border:2px solid #e2e8f0; border-radius:9px; font-size:13px; font-weight:500; color:#1e293b; }
.filter-group select:focus, .filter-group input:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }
.btn-apply { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border:none; padding:10px 20px; border-radius:9px; font-weight:700; font-size:13px; cursor:pointer; width:100%; }
.btn-newv { background:linear-gradient(135deg,#10b981,#059669); color:white; border:none; padding:10px 20px; border-radius:9px; font-weight:700; font-size:13px; cursor:pointer; width:100%; }

.table-responsive { border-radius:12px; border:2px solid #e2e8f0; overflow-x:auto; overflow-y:auto; max-height:640px; background:white; box-shadow:0 2px 10px rgba(0,0,0,.06); width:100%; cursor:grab; user-select:none; }
.table-responsive.dragging { cursor:grabbing; }
.table-responsive.dragging * { cursor:grabbing !important; }
table.exp-table thead th { position:sticky; top:0; z-index:5; }
table.exp-table { width:100%; border-collapse:collapse; min-width:1100px; }
table.exp-table thead th { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; padding:13px 12px; font-weight:700; font-size:12px; text-transform:uppercase; letter-spacing:.4px; text-align:left; white-space:nowrap; }
table.exp-table td { padding:13px 12px; border-bottom:1px solid #e2e8f0; font-size:13px; vertical-align:middle; }
table.exp-table tbody tr:hover { background:#f8fafc; }
.badge-status { padding:4px 12px; border-radius:14px; font-size:11px; font-weight:700; white-space:nowrap; display:inline-block; }
.proof-yes { color:#10b981; }
.proof-no { color:#ef4444; }

.btn-sm-action { padding:7px 12px; border-radius:8px; font-size:11.5px; font-weight:700; border:none; cursor:pointer; display:inline-flex; align-items:center; gap:5px; margin:2px; transition:transform .15s, box-shadow .15s; }
.btn-sm-action:hover { transform:translateY(-2px) scale(1.08); box-shadow:0 4px 10px rgba(0,0,0,.18); }
.btn-view { background:#eff6ff; color:#2563eb; }
.btn-edit { background:#fff7ed; color:#c2410c; }
.btn-print { background:#f1f5f9; color:#475569; }
.btn-del { background:#fef2f2; color:#dc2626; }
.btn-rebut { background:#f3e5f5; color:#7b1fa2; }
.btn-ticket { background:#e0e7ff; color:#4338ca; }

.modal-content { border-radius:16px; border:none; }
.modal-header { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border-radius:16px 16px 0 0; padding:18px 26px; }
.modal-title { font-weight:700; font-size:17px; }
.close { color:white; opacity:.9; }
.form-group label { font-weight:700; color:#0f2557; font-size:11.5px; text-transform:uppercase; letter-spacing:.4px; display:block; margin-bottom:7px; }
.form-control-custom { width:100%; padding:11px 13px; border:2px solid #e2e8f0; border-radius:9px; font-size:14px; font-weight:500; color:#1e293b; }
.form-control-custom:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }

.cat-dropdown { position:relative; }
.cat-dropdown-list { display:none; position:absolute; top:calc(100% + 4px); left:0; right:0; background:#fff; border:1px solid #e2e8f0; border-radius:9px; box-shadow:0 10px 30px rgba(0,0,0,.12); max-height:220px; overflow-y:auto; z-index:2000; }
.cat-dropdown-list.show { display:block; }
.cat-dropdown-item { padding:10px 14px; font-size:13.5px; color:#1e293b; cursor:pointer; display:flex; align-items:center; gap:9px; }
.cat-dropdown-item:hover { background:#f1f5f9; }
.cat-dropdown-item i { color:#1a3fc4; font-size:11px; }
.cat-dropdown-empty { padding:10px 14px; font-size:12.5px; color:#94a3b8; }
.cat-dropdown-newhint { padding:8px 14px; font-size:12px; color:#059669; border-top:1px solid #e2e8f0; background:#f0fdf4; }
.cat-dropdown-addnew { padding:11px 14px; font-size:13px; font-weight:700; color:#059669; border-top:2px solid #e2e8f0; background:#f0fdf4; cursor:pointer; display:flex; align-items:center; gap:8px; position:sticky; bottom:0; }
.cat-dropdown-addnew:hover { background:#dcfce7; }

.file-chip-list { display:flex; flex-wrap:wrap; gap:8px; margin-top:10px; }
.file-chip { display:inline-flex; align-items:center; gap:8px; background:#eef2ff; border:1px solid #c7d2fe; color:#1a3fc4; padding:6px 10px; border-radius:8px; font-size:12px; font-weight:600; max-width:220px; }
.file-chip span.fname { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.file-chip button { background:none; border:none; color:#dc2626; font-size:15px; font-weight:800; line-height:1; cursor:pointer; padding:0; }
.file-chip-empty { font-size:12px; color:#94a3b8; }

.rt-multiselect { position:relative; border:2px solid #e2e8f0; border-radius:9px; background:#fff; }
.rt-multiselect:focus-within { border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }
.rt-tag-area { display:flex; flex-wrap:wrap; gap:6px; align-items:center; padding:8px 12px; min-height:44px; cursor:text; }
.rt-tag-area input { border:none; outline:none; font-size:13px; min-width:130px; flex:1; font-family:inherit; background:transparent; }
.rt-tag { display:inline-flex; align-items:center; gap:5px; background:#eef2ff; color:#1a3fc4; border:1px solid #c7d2fe; border-radius:20px; padding:3px 10px 3px 8px; font-size:12px; font-weight:600; white-space:nowrap; }
.rt-tag-x { cursor:pointer; font-size:14px; line-height:1; color:#1a3fc4; margin-left:2px; }
.rt-tag-x:hover { color:#dc2626; }
.rt-dropdown { display:none; border-top:1px solid #f1f5f9; max-height:200px; overflow-y:auto; }
.rt-opt { padding:10px 14px; font-size:13px; display:flex; align-items:center; gap:10px; cursor:pointer; }
.rt-opt:hover { background:#f8fafc; }
.rt-opt.selected { background:#eff6ff; }
.rt-check { width:16px; height:16px; border:2px solid #cbd5e1; border-radius:4px; display:inline-flex; align-items:center; justify-content:center; flex-shrink:0; }
.rt-opt.selected .rt-check { background:#1a3fc4; border-color:#1a3fc4; }
.rt-opt.selected .rt-check::after { content:'✓'; font-size:10px; color:#fff; font-weight:700; }
.rt-ticket-chip { display:inline-flex; align-items:center; gap:8px; background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; padding:10px 20px; border-radius:10px; font-size:16px; font-weight:800; letter-spacing:.5px; box-shadow:0 4px 14px rgba(15,37,87,.3); }

.v-detail-row { display:flex; padding:8px 0; border-bottom:1px dashed #e2e8f0; }
.v-detail-label { width:160px; color:#64748b; font-size:12px; font-weight:600; }
.v-detail-value { flex:1; color:#0f172a; font-weight:600; font-size:13.5px; }
.proof-thumb-grid { display:flex; flex-wrap:wrap; gap:14px; }
.proof-card { width:160px; border:1px solid #e2e8f0; border-radius:10px; background:#fff; overflow:hidden; display:flex; flex-direction:column; box-shadow:0 2px 10px rgba(0,0,0,.04); }
.proof-card-preview { height:110px; background:#f8fafc; display:flex; align-items:center; justify-content:center; border-bottom:1px solid #e2e8f0; overflow:hidden; }
.proof-card-preview img { width:100%; height:100%; object-fit:cover; }
.proof-card-preview i.fa-file-pdf { font-size:36px; color:#dc2626; }
.proof-card-info { padding:12px; text-align:center; }
.proof-card-name { font-size:12px; font-weight:700; color:#0f2557; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-bottom:10px; }
.proof-card-actions { display:flex; gap:6px; }
.proof-card-btn { flex:1; padding:6px 0; font-size:11px; font-weight:700; border-radius:6px; text-decoration:none; text-align:center; transition:.2s; display:inline-block; }
.proof-btn-view { background:#e0e7ff; color:#3730a3; }
.proof-btn-view:hover { background:#c7d2fe; text-decoration:none; color:#312e81; }
.proof-btn-dl { background:#ecfdf5; color:#065f46; }
.proof-btn-dl:hover { background:#d1fae5; text-decoration:none; color:#064e3b; }

.activity-item { background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; padding:12px 16px; margin-bottom:8px; font-size:12.5px; }

.toast-card { position:fixed; top:24px; right:-400px; width:340px; background:#fff; border-left:5px solid #10b981; border-radius:10px; box-shadow:0 10px 40px rgba(0,0,0,.18); padding:16px 20px; z-index:99999; transition:right .4s cubic-bezier(.175,.885,.32,1.275); display:flex; align-items:center; gap:14px; }
.toast-card.show { right:24px; }
.toast-card.error { border-left-color:#ef4444; }
.toast-icon { font-size:22px; color:#10b981; }
.toast-card.error .toast-icon { color:#ef4444; }
.toast-text { font-size:13px; font-weight:700; color:#0f2557; }
</style>
</head>
<body>
<div class="main-wrapper">

<div class="header-card">
  <div class="header-content">
    <div class="header-title">
      <h1><i class="fas fa-receipt"></i> Digital Expenses</h1>
      <p>Your submitted expense vouchers &mdash; <?php echo htmlspecialchars($employee_name_db); ?> (<?php echo htmlspecialchars($employee_id); ?>)</p>
    </div>
    <a href="<?php echo $dashboard_url; ?>" class="btn-back"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
  </div>
</div>

<?php if ($canViewAllVouchers): ?>
<div class="dx-tabs">
  <button type="button" class="dx-tab active" id="tabBtnAdmin" onclick="switchDxTab('admin')"><i class="fas <?php echo $isAdmin ? 'fa-user-shield' : 'fa-check-double'; ?>"></i> <?php echo $isAdmin ? 'Admin Vouchers (L2)' : 'Finance Approvals (L1)'; ?></button>
  <button type="button" class="dx-tab" id="tabBtnMine" onclick="switchDxTab('mine')"><i class="fas fa-user"></i> My Vouchers</button>
</div>
<?php endif; ?>

<div id="myVouchersPanel" style="<?php echo $canViewAllVouchers ? 'display:none;' : ''; ?>">

<!-- STATS -->
<div class="stats">
  <div class="stat-card"><div class="stat-icon" style="background:#2980B9;"><i class="fas fa-wallet"></i></div><div><div class="stat-label">Total Amount</div><div class="stat-value">₹<?php echo number_format($stat_total_amt,2); ?></div></div></div>
  <div class="stat-card"><div class="stat-icon" style="background:#27AE60;"><i class="fas fa-check-circle"></i></div><div><div class="stat-label">Approved</div><div class="stat-value"><?php echo $stat_approved; ?></div></div></div>
  <div class="stat-card"><div class="stat-icon" style="background:#E67E22;"><i class="fas fa-exclamation-triangle"></i></div><div><div class="stat-label">Declined / Pending</div><div class="stat-value"><?php echo $stat_declined; ?> / <?php echo $stat_pending; ?></div></div></div>
  <div class="stat-card"><div class="stat-icon" style="background:#1e3a8a;"><i class="fas fa-paperclip"></i></div><div><div class="stat-label">With / Without Proof</div><div class="stat-value"><?php echo $stat_with_proof; ?> / <?php echo $stat_without_proof; ?></div></div></div>
</div>

<!-- FILTERS -->
<div class="filter-panel">
  <form method="GET" id="filterForm">
    <div class="filter-row">
      <div class="filter-group">
        <label>Status</label>
        <select name="f_status">
          <?php foreach ($status_options as $so): ?>
          <option value="<?php echo htmlspecialchars($so); ?>" <?php echo ($filter_status==$so)?'selected':''; ?>><?php echo htmlspecialchars($so); ?></option>
          <?php endforeach; ?>
        </select>
      </div>
      <div class="filter-group"><label>Search</label><input type="text" name="f_search" placeholder="Search anything — amount, name, date, status..." value="<?php echo htmlspecialchars($filter_search); ?>"></div>
      <div class="filter-group"><label>From Date</label><input type="date" name="f_from" value="<?php echo htmlspecialchars($filter_from); ?>"></div>
      <div class="filter-group"><label>To Date</label><input type="date" name="f_to" value="<?php echo htmlspecialchars($filter_to); ?>"></div>
      <div class="filter-group"><button type="submit" class="btn-apply"><i class="fas fa-search"></i> Apply Filters</button></div>
      <div class="filter-group"><button type="button" class="btn-newv" onclick="openNewVoucherModal()"><i class="fas fa-plus"></i> New Voucher</button></div>
      <div class="filter-group"><button type="button" class="btn-apply" style="background:#475569;" onclick="openActivityModal()"><i class="fas fa-history"></i> My Activity</button></div>
      <div class="filter-group"><button type="button" class="btn-apply" style="background:#25D366;" onclick="openWhatsAppReportModal()"><i class="fab fa-whatsapp"></i> WhatsApp Report</button></div>
      <div class="filter-group">
        <a class="btn-apply" style="background:#0f766e;display:block;text-align:center;text-decoration:none;" href="?export=csv&f_status=<?php echo urlencode($filter_status); ?>&f_search=<?php echo urlencode($filter_search); ?>&f_from=<?php echo urlencode($filter_from); ?>&f_to=<?php echo urlencode($filter_to); ?>">
          <i class="fas fa-file-export"></i> Export
        </a>
      </div>
    </div>
  </form>
</div>

<!-- TABLE -->
<div class="table-responsive">
<table class="exp-table">
<thead>
<tr>
  <th>Voucher</th><th>Date</th><th>Category / Desc</th><th>Amount (₹)</th><th>Paid To</th><th>Proof</th><th>Status</th><th style="text-align:right;">Actions</th>
</tr>
</thead>
<tbody>
<?php if (count($expenses) > 0): foreach ($expenses as $exp):
    $style = getStatusStyle($exp['status']);
    $pf = json_decode($exp['proof_files'], true);
    $hasProof = !empty($pf);
    $canEdit = in_array($exp['status'], ['Pending','Declined']);
    $canDelete = $exp['status'] === 'Pending';
    $canRebut = $exp['status'] === 'Declined';
?>
<tr>
  <td><strong style="color:#0f2557;"><?php echo htmlspecialchars($exp['voucher_number']); ?></strong></td>
  <td><?php echo date('d/m/Y', strtotime($exp['expense_date'])); ?><div style="font-size:10.5px;color:#94a3b8;margin-top:2px;"><?php echo date('h:i A', strtotime($exp['created_at'])); ?></div></td>
  <td>
    <div style="font-weight:700;color:#0f2557;font-size:12.5px;"><?php echo htmlspecialchars($exp['expense_category']); ?></div>
    <?php if (!empty($exp['on_account_of'])): ?><div style="font-size:11.5px;color:#64748b;max-width:220px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"><?php echo htmlspecialchars($exp['on_account_of']); ?></div><?php endif; ?>
  </td>
  <td><strong>₹<?php echo number_format($exp['amount'],2); ?></strong></td>
  <td><?php echo htmlspecialchars($exp['amount_paid_to'] ?: '-'); ?></td>
  <td><?php echo $hasProof ? '<i class="fas fa-paperclip proof-yes"></i>' : '<i class="fas fa-exclamation-triangle proof-no" title="No proof"></i>'; ?></td>
  <td>
    <?php if ($exp['status'] !== 'Approved'): ?>
    <span class="badge-status" style="background:<?php echo $style['bg']; ?>;color:<?php echo $style['c']; ?>;"><?php echo htmlspecialchars($exp['status']); ?></span>
    <?php endif; ?>
    <?php if ($exp['status'] === 'Declined' && !empty($exp['manager_reason'])): ?>
    <?php echo renderReasonNote($exp['manager_reason'], '#b91c1c', 'Decline Reason'); ?>
    <?php elseif ($exp['status'] === 'Response Submitted' && !empty($exp['employee_response'])): ?>
    <?php echo renderReasonNote($exp['employee_response'], '#7b1fa2', 'Your Explanation'); ?>
    <?php endif; ?>
    <?php echo renderPaymentStatusBadge($exp['status'], $exp['payment_status'], $exp['payment_status_updated_by'], $exp['payment_status_updated_at'], $payment_status_colors); ?>
  </td>
  <td style="text-align:right;white-space:nowrap;">
    <button type="button" class="btn-sm-action btn-view" title="View Details" onclick="viewVoucher(<?php echo $exp['id']; ?>)"><i class="fas fa-eye"></i></button>
    <?php if ($canEdit): ?><button type="button" class="btn-sm-action btn-edit" title="Edit Voucher" onclick="openEditVoucherModal(<?php echo $exp['id']; ?>)"><i class="fas fa-edit"></i></button><?php endif; ?>
    <a class="btn-sm-action btn-print" title="Print / Download" href="?view=voucher&id=<?php echo $exp['id']; ?>" target="_blank"><i class="fas fa-print"></i></a>
    <button type="button" class="btn-sm-action btn-ticket" title="Raise a Ticket" onclick="openRaiseTicketModal(<?php echo $exp['id']; ?>)"><i class="fas fa-ticket-alt"></i></button>
    <button type="button" class="btn-sm-action" style="background:#f1f5f9;color:#475569;" title="History" onclick="openVoucherHistory(<?php echo $exp['id']; ?>)"><i class="fas fa-history"></i></button>
    <?php if ($canRebut): ?><button type="button" class="btn-sm-action btn-rebut" title="Submit Explanation" onclick="openRebuttalModal(<?php echo $exp['id']; ?>)"><i class="fas fa-reply"></i></button><?php endif; ?>
    <?php if ($canDelete): ?><button type="button" class="btn-sm-action btn-del" title="Delete Voucher" onclick="deleteVoucher(<?php echo $exp['id']; ?>)"><i class="fas fa-trash"></i></button><?php endif; ?>
  </td>
</tr>
<?php endforeach; else: ?>
<tr><td colspan="8" style="text-align:center;padding:40px;color:#94a3b8;">No digital expenses found matching the criteria.</td></tr>
<?php endif; ?>
</tbody>
</table>
</div>

</div><!-- /myVouchersPanel -->

<?php if ($canViewAllVouchers): ?>
<div id="adminVouchersPanel">

<!-- ADMIN STATS -->
<div class="stats">
  <div class="stat-card"><div class="stat-icon" style="background:#2980B9;"><i class="fas fa-wallet"></i></div><div><div class="stat-label">Total Amount</div><div class="stat-value" id="admStatAmt">₹0.00</div></div></div>
  <div class="stat-card" style="cursor:pointer;" onclick="filterAdminByStatus('Approved')" title="Show only Approved"><div class="stat-icon" style="background:#27AE60;"><i class="fas fa-check-circle"></i></div><div><div class="stat-label">Approved</div><div class="stat-value" id="admStatApproved">0</div></div></div>
  <div class="stat-card" style="cursor:pointer;" onclick="filterAdminByStatus('Pending')" title="Show only vouchers waiting for approval"><div class="stat-icon" style="background:#E67E22;"><i class="fas fa-hourglass-half"></i></div><div><div class="stat-label">Waiting for Approval</div><div class="stat-value" id="admStatPending">0</div></div></div>
  <div class="stat-card" style="cursor:pointer;" onclick="filterAdminByStatus('Declined')" title="Show only Declined"><div class="stat-icon" style="background:#DC2626;"><i class="fas fa-times-circle"></i></div><div><div class="stat-label">Declined</div><div class="stat-value" id="admStatDeclined">0</div></div></div>
  <div class="stat-card" style="cursor:pointer;" onclick="filterAdminByStatus('Response Submitted')" title="Show only Response Submitted"><div class="stat-icon" style="background:#7B1FA2;"><i class="fas fa-reply"></i></div><div><div class="stat-label">Response Submitted</div><div class="stat-value" id="admStatResponse">0</div></div></div>
  <div class="stat-card"><div class="stat-icon" style="background:#1e3a8a;"><i class="fas fa-paperclip"></i></div><div><div class="stat-label">With / Without Proof</div><div class="stat-value" id="admStatProof">0 / 0</div></div></div>
</div>

<!-- ADMIN FILTERS -->
<div class="filter-panel">
  <div class="filter-row">
    <div class="filter-group"><label>Employee</label><select id="adm_f_employee"><option value="">All Employees</option></select></div>
    <div class="filter-group"><label>Company</label><select id="adm_f_company"><option value="">All Companies</option></select></div>
    <div class="filter-group">
      <label>Status</label>
      <select id="adm_f_status">
        <option value="All">All</option><option value="Pending">Pending</option><option value="Pending L2 Approval">Pending L2 Approval</option><option value="Approved">Approved</option><option value="Declined">Declined</option><option value="Response Submitted">Response Submitted</option>
      </select>
    </div>
    <div class="filter-group"><label>Search</label><input type="text" id="adm_f_search" placeholder="Search anything..."></div>
    <div class="filter-group"><label>From Date</label><input type="date" id="adm_f_from"></div>
    <div class="filter-group"><label>To Date</label><input type="date" id="adm_f_to"></div>
    <div class="filter-group"><button type="button" class="btn-apply" onclick="loadAdminList()"><i class="fas fa-search"></i> Apply Filters</button></div>
    <div class="filter-group">
      <a class="btn-apply" style="background:#0f766e;display:block;text-align:center;text-decoration:none;" href="#" id="admExportLink" onclick="return doAdminExport();">
        <i class="fas fa-file-export"></i> Export
      </a>
    </div>
    <div class="filter-group"><button type="button" class="btn-apply" style="background:#25D366;" onclick="openAdminWhatsAppModal()"><i class="fab fa-whatsapp"></i> WhatsApp Report</button></div>
    <?php if ($canViewAllVouchers): ?>
    <div class="filter-group"><button type="button" class="btn-apply" style="background:linear-gradient(135deg,#0f766e,#0d9488);" onclick="openSignatureModal()"><i class="fas fa-signature"></i> Manage Signature</button></div>
    <?php endif; ?>
    <?php if ($isAdminLogin): ?>
    <div class="filter-group"><button type="button" class="btn-apply" style="background:linear-gradient(135deg,#128C7E,#25D366);" onclick="openDewaModal()"><i class="fab fa-whatsapp"></i> WhatsApp Approvers</button></div>
    <?php endif; ?>
  </div>
</div>

<!-- ADMIN TABLE -->
<div class="table-responsive" id="adminTableScroll">
<table class="exp-table">
<thead>
<tr>
  <th>Employee</th><th>Voucher</th><th>Date</th><th>Category</th><th>Amount (₹)</th><th>Paid To</th><th>Proof</th><th>Status</th><th>L1 Approval</th><th>L2 Approval</th><th style="text-align:right;">Actions</th>
</tr>
</thead>
<tbody id="adminTableBody">
<tr><td colspan="11" style="text-align:center;padding:40px;color:#94a3b8;">Loading...</td></tr>
</tbody>
</table>
</div>

</div><!-- /adminVouchersPanel -->
<?php endif; ?>

</div><!-- /main-wrapper -->

<!-- =========================================================================
     NEW / EDIT VOUCHER MODAL
========================================================================== -->
<div class="modal fade" id="voucherFormModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="vf_title"><i class="fas fa-plus-circle"></i> New Voucher</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form id="voucherForm" enctype="multipart/form-data">
      <div class="modal-body">
        <input type="hidden" id="vf_id" name="id">
        <div class="row">
          <div class="col-md-6 form-group"><label>Date *</label><input type="date" class="form-control-custom" id="vf_date" name="date" value="<?php echo date('Y-m-d'); ?>" required></div>
          <div class="col-md-6 form-group"><label>Amount (₹) *</label><input type="number" step="0.01" class="form-control-custom" id="vf_amount" name="amount" required></div>
        </div>
        <div class="row">
          <div class="col-md-6 form-group">
            <label>Expense Category *</label>
            <div class="cat-dropdown">
              <input type="text" class="form-control-custom" id="vf_category" name="expenseCategory" placeholder="Search or type new category..." autocomplete="off" required>
              <div class="cat-dropdown-list" id="vf_category_list"></div>
            </div>
          </div>
          <div class="col-md-6 form-group"><label>Payment Method</label>
            <select class="form-control-custom" id="vf_payment_method" name="paymentMethod">
              <option value="Cash">Cash</option><option value="UPI">UPI</option><option value="Bank Transfer">Bank Transfer</option><option value="Card">Card</option><option value="Cheque">Cheque</option>
            </select>
          </div>
        </div>
        <div class="row">
          <div class="col-md-6 form-group"><label>Amount Paid To</label><input type="text" class="form-control-custom" id="vf_paid_to" name="amountPaidTo"></div>
          <div class="col-md-6 form-group"><label>Received Person</label><input type="text" class="form-control-custom" id="vf_received_by" name="receivedBy"></div>
        </div>
        <div class="form-group"><label>Amount in Words</label><input type="text" class="form-control-custom" id="vf_words" name="amountInWords" placeholder="Auto-filled from amount — you can still edit it"></div>
        <div class="form-group"><label>On Account Of</label><textarea class="form-control-custom" id="vf_account_of" name="onAccountOf" rows="3"></textarea></div>
        <div class="form-group">
          <label>Proof Files (images/PDF, up to 5)</label>
          <input type="file" class="form-control-custom" id="vf_files" name="proofFiles[]" multiple accept=".jpg,.jpeg,.png,.gif,.webp,.pdf">
          <div id="vf_files_preview" class="file-chip-list"></div>
          <div id="vf_existing_files" style="margin-top:8px;font-size:12px;color:#64748b;"></div>
        </div>
        <div class="form-group" id="vf_raise_ticket_wrap" style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:9px;padding:12px 16px;">
          <div style="display:flex;align-items:center;gap:10px;">
            <input type="checkbox" id="vf_raise_ticket" style="width:18px;height:18px;flex-shrink:0;">
            <label style="margin:0;font-weight:600;color:#1a3fc4;font-size:13px;" for="vf_raise_ticket">Also raise a ticket about this voucher</label>
          </div>
          <div id="vf_ticket_fields" style="display:none;margin-top:14px;padding-top:14px;border-top:1px solid #bfdbfe;">
            <label>Assign Ticket To *</label>
            <div id="vftMultiSelectWrap" class="rt-multiselect">
              <div id="vftTagArea" class="rt-tag-area">
                <input type="text" id="vftSearch" placeholder="Search employees…" autocomplete="off">
              </div>
              <div id="vftDropdown" class="rt-dropdown"></div>
            </div>
            <div id="vftError" style="display:none;color:#ef4444;font-size:12px;margin-top:4px;">Please select at least one employee.</div>
            <label style="margin-top:12px;">Ticket Subject</label>
            <input type="text" class="form-control-custom" id="vft_subject" placeholder="Subject">
            <label style="margin-top:12px;">Ticket Message</label>
            <textarea class="form-control-custom" id="vft_message" rows="4" placeholder="Message"></textarea>
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-newv" style="width:auto;padding:10px 24px;"><i class="fas fa-save"></i> Save Voucher</button>
      </div>
      </form>
    </div>
  </div>
</div>

<!-- =========================================================================
     VIEW VOUCHER MODAL
========================================================================== -->
<div class="modal fade" id="viewVoucherModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-receipt"></i> Voucher Details</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="viewVoucherContent">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>
      </div>
      <div class="modal-footer">
        <a id="vv_print_link" href="#" target="_blank" class="btn-newv" style="width:auto;padding:10px 20px;background:#475569;"><i class="fas fa-print"></i> Print / Download</a>
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<!-- =========================================================================
     REBUTTAL / EXPLANATION MODAL
========================================================================== -->
<div class="modal fade" id="rebuttalModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#7b1fa2,#9c27b0);">
        <h5 class="modal-title"><i class="fas fa-reply"></i> Submit Explanation</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form id="rebuttalForm" enctype="multipart/form-data">
      <div class="modal-body">
        <input type="hidden" id="rb_id" name="id">
        <p style="font-size:13px;color:#64748b;">Provide an explanation for this expense to be re-reviewed by the admin.</p>
        <div class="form-group"><label>Explanation *</label><textarea class="form-control-custom" id="rb_response" name="employeeResponse" rows="4" required></textarea></div>
        <div class="form-group">
          <label>New Proof Files (optional)</label>
          <input type="file" class="form-control-custom" id="rb_files" name="rebuttalProofFiles[]" multiple accept=".jpg,.jpeg,.png,.gif,.webp,.pdf">
          <div id="rb_files_preview" class="file-chip-list"></div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#7b1fa2,#9c27b0);"><i class="fas fa-paper-plane"></i> Submit</button>
      </div>
      </form>
    </div>
  </div>
</div>

<!-- =========================================================================
     ACTIVITY MODAL
========================================================================== -->
<div class="modal fade" id="activityModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-history"></i> My Activity</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="activityContent">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Close</button></div>
    </div>
  </div>
</div>

<!-- =========================================================================
     RAISE TICKET MODAL
========================================================================== -->
<div class="modal fade" id="raiseTicketModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#0f2557,#1a3fc4);">
        <h5 class="modal-title"><i class="fas fa-ticket-alt"></i> Raise a Ticket</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div id="rtFormView">
          <input type="hidden" id="rt_voucher_id">
          <div class="form-group">
            <label>Assign To *</label>
            <div id="rtMultiSelectWrap" class="rt-multiselect">
              <div id="rtTagArea" class="rt-tag-area">
                <input type="text" id="rtSearch" placeholder="Search employees…" autocomplete="off">
              </div>
              <div id="rtDropdown" class="rt-dropdown"></div>
            </div>
            <div id="rtError" style="display:none;color:#ef4444;font-size:12px;margin-top:4px;">Please select at least one employee.</div>
          </div>
          <div class="form-group">
            <label>Ticket Text <span style="font-weight:400;font-size:11px;color:#64748b;">— this is exactly what gets sent, edit if needed</span></label>
            <input type="text" class="form-control-custom" id="rt_subject" style="margin-bottom:10px;" placeholder="Subject">
            <textarea class="form-control-custom" id="rt_message" rows="7" placeholder="Message"></textarea>
          </div>
        </div>
        <div id="rtSuccessView" style="display:none;text-align:center;padding:20px 10px;">
          <i class="fas fa-check-circle" style="font-size:52px;color:#10b981;margin-bottom:14px;"></i>
          <h4 style="color:#0f2557;font-weight:800;margin-bottom:14px;">Ticket Raised Successfully</h4>
          <div id="rtTicketNumbers" style="display:flex;flex-wrap:wrap;gap:10px;justify-content:center;margin-bottom:10px;"></div>
          <p style="color:#64748b;font-size:13px;">You can track this in your Tickets page.</p>
        </div>
      </div>
      <div class="modal-footer" id="rtFormFooter">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;" onclick="submitRaiseTicket()"><i class="fas fa-paper-plane"></i> Send Ticket</button>
      </div>
      <div class="modal-footer" id="rtSuccessFooter" style="display:none;">
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;" data-dismiss="modal">Done</button>
      </div>
    </div>
  </div>
</div>

<?php if ($canViewAllVouchers): ?>
<!-- L1/L2 DECLINE REASON MODAL (shared by L1, L2, and L2 Override decline) -->
<div class="modal fade" id="admDeclineModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#b91c1c,#dc2626);">
        <h5 class="modal-title" id="admDeclineModalTitle"><i class="fas fa-times-circle"></i> Decline Voucher</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="adm_decline_id">
        <input type="hidden" id="adm_decline_action">
        <div class="form-group"><label>Reason for Decline *</label><textarea class="form-control-custom" id="adm_decline_reason" rows="4" placeholder="Explain why this voucher is being declined — the employee will see this..."></textarea></div>
        <div class="form-group" id="adm_override_wrap" style="display:none;background:#fffbeb;border:1px solid #fde68a;border-radius:9px;padding:12px 16px;">
          <label style="color:#92400e;"><i class="fas fa-bolt"></i> Override Justification *</label>
          <textarea class="form-control-custom" id="adm_override_reason" rows="3" placeholder="Why are you acting before L1 has approved this voucher? (audit trail only, not shown to employee)"></textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#b91c1c,#dc2626);" onclick="submitDeclineReason()"><i class="fas fa-times-circle"></i> Confirm Decline</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<?php if ($isAdmin): ?>
<!-- L2 OVERRIDE APPROVE MODAL -->
<div class="modal fade" id="overrideApproveModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#92400e,#b45309);">
        <h5 class="modal-title"><i class="fas fa-bolt"></i> Override Approve (Bypass L1)</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="ovr_approve_id">
        <p style="font-size:12.5px;color:#92400e;background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:10px 14px;">This approves the voucher immediately without waiting for L1. L1's stage will be marked as skipped. Use only for genuine exceptions.</p>
        <div class="form-group"><label>Override Justification *</label><textarea class="form-control-custom" id="ovr_approve_reason" rows="4" placeholder="Why are you approving before L1 has reviewed this voucher? (audit trail only)"></textarea></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#92400e,#b45309);" onclick="submitOverrideApprove()"><i class="fas fa-bolt"></i> Confirm Override Approve</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<?php if ($canViewAllVouchers): ?>
<!-- SIGNATURE MODAL — whole finance team can manage this, not just the admin -->
<div class="modal fade" id="signatureModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#0f766e,#0d9488);">
        <h5 class="modal-title"><i class="fas fa-signature"></i> Manage Digital Signature</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p style="font-size:13px;color:#64748b;">This signature is stamped onto every voucher approved by the admin, and appears in the printed/downloaded PDF. Anyone on the finance team can upload or replace it.</p>
        <div id="sig_current_wrap" style="margin-bottom:18px;"></div>
        <div class="form-group">
          <label>Upload New Signature <span style="font-weight:400;font-size:11px;color:#64748b;">(PNG with transparent background works best, max 2MB)</span></label>
          <input type="file" class="form-control-custom" id="sig_file" accept=".jpg,.jpeg,.png,.webp">
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#0f766e,#0d9488);" onclick="uploadSignature()"><i class="fas fa-upload"></i> Upload &amp; Save</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- =========================================================================
     WHATSAPP REPORT MODAL
========================================================================== -->
<div class="modal fade" id="waReportModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#128C7E,#25D366);">
        <h5 class="modal-title"><i class="fab fa-whatsapp"></i> WhatsApp Report</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p style="font-size:13px;color:#64748b;">Choose a date range to summarize (leave blank to use everything currently shown in the table).</p>
        <div class="row">
          <div class="col-md-6 form-group"><label>From Date</label><input type="date" class="form-control-custom" id="wa_from"></div>
          <div class="col-md-6 form-group"><label>To Date</label><input type="date" class="form-control-custom" id="wa_to"></div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#128C7E,#25D366);" onclick="sendWhatsAppReport()"><i class="fab fa-whatsapp"></i> Send Report</button>
      </div>
    </div>
  </div>
</div>

<!-- ADMIN WHATSAPP REPORT MODAL -->
<div class="modal fade" id="admWaReportModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#128C7E,#25D366);">
        <h5 class="modal-title"><i class="fab fa-whatsapp"></i> WhatsApp Report — All Vouchers</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p style="font-size:13px;color:#64748b;">Uses whatever is currently loaded in the table above (respecting your Employee/Company/Status/Search/Date filters).</p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#128C7E,#25D366);" onclick="sendAdminWhatsAppReport()"><i class="fab fa-whatsapp"></i> Send Report</button>
      </div>
    </div>
  </div>
</div>

<?php if ($isAdminLogin): ?>
<!-- WHATSAPP APPROVERS MODAL (Administrator login only) -->
<style>
.dewa-cols { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
@media (max-width:700px) { .dewa-cols { grid-template-columns:1fr; } }
.dewa-col { border:1px solid #e2e8f0; border-radius:10px; overflow:hidden; display:flex; flex-direction:column; }
.dewa-col h6 { margin:0; padding:10px 12px; background:#f8fafc; border-bottom:1px solid #e2e8f0; font-size:13px; font-weight:700; color:#1e293b; }
.dewa-col h6 small { display:block; font-weight:500; color:#64748b; margin-top:2px; }
.dewa-chips { padding:8px 10px; display:flex; flex-wrap:wrap; gap:6px; min-height:40px; border-bottom:1px solid #f1f5f9; }
.dewa-chip { background:#dcfce7; color:#166534; border-radius:14px; padding:3px 10px; font-size:12px; font-weight:600; }
.dewa-chips .dewa-none { color:#94a3b8; font-size:12px; }
.dewa-col input[type=text] { margin:8px 10px; padding:7px 10px; border:1px solid #cbd5e1; border-radius:8px; font-size:13px; }
.dewa-list { max-height:260px; overflow-y:auto; padding:0 6px 8px; }
.dewa-row { display:flex; align-items:center; gap:8px; padding:6px; border-radius:7px; font-size:13px; cursor:pointer; margin:0; }
.dewa-row:hover { background:#f1f5f9; }
.dewa-row input { width:16px; height:16px; flex-shrink:0; }
.dewa-row .dewa-meta { color:#64748b; font-size:11px; display:block; }
.dewa-row.no-phone { opacity:.55; cursor:not-allowed; }
</style>
<div class="modal fade" id="dewaModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#128C7E,#25D366);">
        <h5 class="modal-title"><i class="fab fa-whatsapp"></i> WhatsApp Approvers</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p style="font-size:13px;color:#475569;margin-bottom:12px;">
          When a voucher is submitted, a WhatsApp message (E-Logistics number) with who submitted it, the amount, paid to and the description goes to the <b>L1</b> approvers below with
          <b>Approve / Reject</b> buttons and a link to all details and files. Once L1 approves, it goes to the <b>L2</b> approvers; if L1 rejects, it stops there.
          A rejection at either level asks for the reason, and the employee is told on WhatsApp.
          Messages go to the phone number in each employee's record.
        </p>
        <label style="display:flex;align-items:center;gap:8px;font-weight:700;font-size:14px;margin-bottom:12px;cursor:pointer;">
          <input type="checkbox" id="dewaEnabled" style="width:18px;height:18px;" onchange="$('#dewaOffNote').toggle(!this.checked)"> Send approval requests on WhatsApp
        </label>
        <div id="dewaOffNote" style="display:none;margin:-6px 0 12px;background:#fef2f2;color:#b91c1c;border-radius:8px;padding:8px 12px;font-size:12px;font-weight:600;">WhatsApp sending is OFF — tick the box above and Save, otherwise no approval requests are sent.</div>
        <div class="dewa-cols">
          <div class="dewa-col">
            <h6>L1 approvers — Finance review<small>First approval</small></h6>
            <div class="dewa-chips" id="dewaChips1"></div>
            <input type="text" placeholder="Search employees…" oninput="renderDewaList(1)" id="dewaSearch1">
            <div class="dewa-list" id="dewaList1"></div>
          </div>
          <div class="dewa-col">
            <h6>L2 approvers — Final approval<small>After L1 approves</small></h6>
            <div class="dewa-chips" id="dewaChips2"></div>
            <input type="text" placeholder="Search employees…" oninput="renderDewaList(2)" id="dewaSearch2">
            <div class="dewa-list" id="dewaList2"></div>
          </div>
        </div>
        <div style="margin-top:12px;display:flex;align-items:center;gap:8px;font-size:12px;color:#64748b;flex-wrap:wrap;">
          Template language code
          <input type="text" id="dewaLang" style="width:80px;padding:5px 8px;border:1px solid #cbd5e1;border-radius:7px;font-size:12px;" value="en">
          <span>(must match the language the Meta templates were approved in, e.g. <b>en</b> or <b>en_US</b>)</span>
        </div>
        <div id="dewaUpdated" style="margin-top:8px;font-size:11px;color:#94a3b8;"></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" id="dewaSaveBtn" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#128C7E,#25D366);" onclick="saveDewa()"><i class="fas fa-save"></i> Save</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- VOUCHER HISTORY MODAL (visible to everyone who can see the voucher) -->
<div class="modal fade" id="voucherHistoryModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-history"></i> Voucher History — <span id="vh_voucher_number"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="voucherHistoryBody" style="max-height:60vh;overflow-y:auto;">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Close</button></div>
    </div>
  </div>
</div>

<?php if ($canViewAllVouchers): ?>
<!-- PAYMENT STATUS MODAL (finance team — admin + finance-read-only) -->
<div class="modal fade" id="paymentStatusModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#0f766e,#0d9488);">
        <h5 class="modal-title"><i class="fas fa-university"></i> Update Payment Status</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="ps_voucher_id">
        <div class="form-group">
          <label>Payment Status</label>
          <select class="form-control-custom" id="ps_status">
            <?php foreach ($payment_status_options as $pso): ?>
            <option value="<?php echo htmlspecialchars($pso); ?>"><?php echo htmlspecialchars($pso); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-newv" style="width:auto;padding:10px 24px;background:linear-gradient(135deg,#0f766e,#0d9488);" onclick="submitPaymentStatus()"><i class="fas fa-save"></i> Save</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- IMAGE VIEWER MODAL -->
<div class="modal fade" id="imageViewerModal" tabindex="-1" style="z-index: 1060;">
  <div class="modal-dialog modal-xl modal-dialog-centered">
    <div class="modal-content" style="background:transparent; border:none; box-shadow:none;">
      <div class="modal-header" style="border:none; padding:0; justify-content:flex-end;">
        <button type="button" class="btn btn-light rounded-circle shadow" style="width:40px;height:40px;margin-bottom:10px;" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body text-center" style="position:relative; overflow:auto; max-height:85vh; background:rgba(0,0,0,0.85); border-radius:10px; padding:20px;">
        <div style="position:absolute; top:20px; right:30px; z-index:10; display:flex; gap:10px;">
            <button class="btn btn-light shadow-sm" onclick="zoomImage(0.2)" title="Zoom In"><i class="fas fa-search-plus"></i></button>
            <button class="btn btn-light shadow-sm" onclick="zoomImage(-0.2)" title="Zoom Out"><i class="fas fa-search-minus"></i></button>
            <button class="btn btn-light shadow-sm" onclick="resetZoom()" title="Reset Zoom"><i class="fas fa-expand"></i></button>
        </div>
        <img id="viewerImage" src="" style="max-width:100%; transition:transform 0.2s ease; transform-origin: top center;" alt="Proof">
      </div>
    </div>
  </div>
</div>

<!-- Toast Card -->
<!-- FULL TEXT MODAL (Read More) -->
<div class="modal fade" id="fullTextModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="fullTextModalTitle">Details</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="fullTextModalBody" style="white-space:pre-wrap;font-size:14px;color:#1e293b;"></div>
      <div class="modal-footer"><button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Close</button></div>
    </div>
  </div>
</div>

<div id="toastCard" class="toast-card">
  <i id="toastIcon" class="fas fa-check-circle toast-icon"></i>
  <div id="toastText" class="toast-text">Message</div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/popper.js@1.16.1/dist/umd/popper.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script>
var IS_ADMIN = <?php echo $isAdmin ? 'true' : 'false'; ?>; // L2 approver
var IS_L1 = <?php echo $isL1Approver ? 'true' : 'false'; ?>; // L1 approver

function fmtDT(s) {
  if (!s) return '';
  var d = new Date(String(s).replace(' ', 'T'));
  if (isNaN(d.getTime())) return s;
  return d.toLocaleDateString('en-GB', {day:'2-digit',month:'short',year:'numeric'}) + ', ' + d.toLocaleTimeString('en-GB', {hour:'2-digit',minute:'2-digit',hour12:true});
}

function fmtTimeOnly(s) {
  if (!s) return '';
  var d = new Date(String(s).replace(' ', 'T'));
  if (isNaN(d.getTime())) return '';
  return d.toLocaleTimeString('en-GB', {hour:'2-digit',minute:'2-digit',hour12:true});
}

function buildStageCellHtml(stageLabel, status, by, at, reason, overrideFlag, overrideReason) {
  var badge = '', extra = '';
  if (status === 'Approved') {
    badge = '<span class="badge-status" style="background:#25D366;color:#ffffff;box-shadow:0 1px 4px rgba(37,211,102,.4);">Approved</span>';
    extra = '<div style="font-size:11px;color:#64748b;margin-top:4px;">by ' + escapeHtml(by || '-') + '<br>' + fmtDT(at) + '</div>';
  } else if (status === 'Declined') {
    badge = '<span class="badge-status" style="background:#dc2626;color:#ffffff;">Declined</span>';
    extra = '<div style="font-size:11px;color:#64748b;margin-top:4px;">by ' + escapeHtml(by || '-') + '<br>' + fmtDT(at) + '</div>';
    if (reason) extra += buildReasonNoteHtml(reason, '#b91c1c', stageLabel + ' Decline Reason');
  } else if (status && status.indexOf('Skipped') === 0) {
    badge = '<span class="badge-status" style="background:#64748b;color:#ffffff;">' + escapeHtml(status) + '</span>';
  } else {
    badge = '<span class="badge-status" style="background:#c2410c;color:#ffffff;">Waiting for ' + stageLabel + '</span>';
  }
  if (overrideFlag) {
    extra += '<div style="margin-top:4px;"><span class="badge-status" style="background:#92400e;color:#ffffff;font-size:10px;"><i class="fas fa-bolt"></i> Override</span>' +
      (overrideReason ? buildReasonNoteHtml(overrideReason, '#92400e', 'Override Justification') : '') + '</div>';
  }
  return badge + extra;
}
var ADMIN_EXPENSES_DATA = [];

function doAdminExport() {
  var qs = new URLSearchParams({
    export: 'csv_admin',
    a_status: $('#adm_f_status').val(),
    a_employee: $('#adm_f_employee').val(),
    a_company: $('#adm_f_company').val(),
    a_search: $('#adm_f_search').val(),
    a_from: $('#adm_f_from').val(),
    a_to: $('#adm_f_to').val()
  });
  window.location.href = window.location.pathname + '?' + qs.toString();
  return false;
}

// ---- WHATSAPP APPROVERS (admin) ----
var DEWA = { employees: [], sel: { 1: [], 2: [] } };
function openDewaModal() {
  $.post(window.location.pathname, { ajax_dewa_get: 1 }, function(resp) {
    if (!resp.success) { showToast(resp.message || 'Could not load WhatsApp approvers.', true); return; }
    DEWA.employees = resp.employees;
    DEWA.sel = { 1: resp.l1.slice(), 2: resp.l2.slice() };
    $('#dewaEnabled').prop('checked', resp.enabled == 1);
    $('#dewaOffNote').toggle(resp.enabled != 1);
    $('#dewaLang').val(resp.lang || 'en');
    $('#dewaSearch1, #dewaSearch2').val('');
    $('#dewaUpdated').text(resp.updated_by ? 'Last saved by ' + resp.updated_by + ' on ' + resp.updated_at : '');
    renderDewaList(1); renderDewaList(2);
    $('#dewaModal').modal('show');
  }, 'json').fail(function(){ showToast('Server error while loading WhatsApp approvers.', true); });
}
function dewaEsc(t) { return String(t == null ? '' : t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function renderDewaList(level) {
  var q = ($('#dewaSearch' + level).val() || '').toLowerCase();
  var sel = DEWA.sel[level], html = '', chips = '';
  DEWA.employees.forEach(function(e) {
    var on = sel.indexOf(e.id) !== -1;
    if (on) chips += '<span class="dewa-chip">' + dewaEsc(e.name) + '</span>';
    var hay = (e.name + ' ' + e.department + ' ' + e.position + ' ' + e.phone).toLowerCase();
    if (q && hay.indexOf(q) === -1) return;
    var meta = [e.department, e.position].filter(Boolean).join(' · ') + ' — ' + (e.phone ? '+' + e.phone : 'no phone number');
    html += '<label class="dewa-row' + (e.phone ? '' : ' no-phone') + '"><input type="checkbox" ' + (on ? 'checked ' : '') + (e.phone || on ? '' : 'disabled ')
      + 'onchange="toggleDewa(' + level + ',' + e.id + ',this.checked)"><span>' + dewaEsc(e.name) + '<span class="dewa-meta">' + dewaEsc(meta) + '</span></span></label>';
  });
  $('#dewaList' + level).html(html || '<div style="padding:10px;color:#94a3b8;font-size:12px;">No employees match.</div>');
  $('#dewaChips' + level).html(chips || '<span class="dewa-none">Nobody selected yet</span>');
}
function toggleDewa(level, id, on) {
  var a = DEWA.sel[level], i = a.indexOf(id);
  if (on && i === -1) a.push(id);
  if (!on && i !== -1) a.splice(i, 1);
  renderDewaList(level);
}
function saveDewa() {
  $('#dewaSaveBtn').prop('disabled', true);
  $.post(window.location.pathname, { ajax_dewa_save: 1, enabled: $('#dewaEnabled').is(':checked') ? 1 : 0, lang: $('#dewaLang').val(), l1: DEWA.sel[1], l2: DEWA.sel[2] }, function(resp) {
    $('#dewaSaveBtn').prop('disabled', false);
    if (resp.success) { $('#dewaModal').modal('hide'); showToast($('#dewaEnabled').is(':checked') ? resp.message : 'Saved — but WhatsApp sending is OFF, so no approval requests will go out.', !$('#dewaEnabled').is(':checked')); }
    else showToast(resp.message || 'Could not save.', true);
  }, 'json').fail(function(){ $('#dewaSaveBtn').prop('disabled', false); showToast('Server error while saving.', true); });
}

function openAdminWhatsAppModal() {
  if (!ADMIN_EXPENSES_DATA.length) { showToast('No vouchers currently loaded to report on.', true); return; }
  $('#admWaReportModal').modal('show');
}

function sendAdminWhatsAppReport() {
  var rows = ADMIN_EXPENSES_DATA;
  if (!rows.length) { showToast('No vouchers currently loaded to report on.', true); return; }

  var totalAmount = 0, approved = 0, declined = 0, pending = 0, responseSubmitted = 0;
  var approvedList = [], declinedList = [], pendingList = [], responseList = [];
  rows.forEach(function(e){
    var amt = parseFloat(e.amount) || 0;
    totalAmount += amt;
    var who = e.added_by_name ? (e.added_by_name + ' — ') : '';
    var paidTo = e.amount_paid_to ? ' (' + e.amount_paid_to + ')' : '';
    var line = who + e.voucher_number + ' - Rs.' + amt.toFixed(2) + paidTo;
    var st = (e.status || 'Pending').toUpperCase();
    if (st === 'APPROVED') { approved++; approvedList.push(line); }
    else if (st === 'DECLINED') { declined++; declinedList.push(line); }
    else if (st === 'RESPONSE SUBMITTED') { responseSubmitted++; responseList.push(line); }
    else { pending++; pendingList.push(line); }
  });

  var now = new Date();
  var nowStr = now.toLocaleDateString('en-GB', { day:'2-digit', month:'short', year:'numeric' });

  var msg = '*Digital Expenses Report — All Employees* Generated: ' + nowStr + '\n';
  msg += '*Summary*\n';
  msg += 'Total Vouchers : ' + rows.length + '\n';
  msg += 'Total Amount : Rs.' + totalAmount.toFixed(2) + '\n';
  msg += 'Approved : ' + approved + '\n';
  msg += 'Declined : ' + declined + '\n';
  msg += 'Pending : ' + pending + '\n';
  msg += 'Response Submitted : ' + responseSubmitted + '\n';

  if (approvedList.length) { msg += '*Approved Vouchers*\n' + approvedList.join('\n') + '\n'; }
  if (declinedList.length) { msg += '*Declined Vouchers*\n' + declinedList.join('\n') + '\n'; }
  if (pendingList.length) { msg += '*Pending Vouchers*\n' + pendingList.join('\n') + '\n'; }
  if (responseList.length) { msg += '*Response Submitted*\n' + responseList.join('\n') + '\n'; }

  msg += '\nShared from the Digital Expenses portal.';

  window.open('https://wa.me/?text=' + encodeURIComponent(msg), '_blank');
  $('#admWaReportModal').modal('hide');
}

var EXPENSES_DATA = <?php echo json_encode(array_map(function($e){
    return [
        'voucher_number' => $e['voucher_number'],
        'expense_date' => $e['expense_date'],
        'amount' => floatval($e['amount']),
        'amount_paid_to' => $e['amount_paid_to'],
        'status' => $e['status']
    ];
}, $expenses)); ?>;

$(document).ready(function(){
  loadCategories();
  initFileWidget('vf_files', 'vf_files_preview', 5);
  initFileWidget('rb_files', 'rb_files_preview', 5);
  $(document).on('click', function(e){
    if (!$(e.target).closest('.cat-dropdown').length) $('#vf_category_list').removeClass('show');
  });
  initDragScroll();
});

// ---- CLICK-AND-DRAG SCROLLING (horizontal + vertical) for the voucher table ----
function initDragScroll() {
  var el = document.querySelector('.table-responsive');
  if (!el) return;
  var isDown = false, startX, startY, scrollLeft, scrollTop;

  el.addEventListener('mousedown', function(e){
    isDown = true;
    el.classList.add('dragging');
    startX = e.pageX - el.offsetLeft;
    startY = e.pageY - el.offsetTop;
    scrollLeft = el.scrollLeft;
    scrollTop = el.scrollTop;
  });
  el.addEventListener('mouseleave', function(){ isDown = false; el.classList.remove('dragging'); });
  el.addEventListener('mouseup', function(){ isDown = false; el.classList.remove('dragging'); });
  el.addEventListener('mousemove', function(e){
    if (!isDown) return;
    e.preventDefault();
    var x = e.pageX - el.offsetLeft;
    var y = e.pageY - el.offsetTop;
    var walkX = (x - startX) * 1.4;
    var walkY = (y - startY) * 1.4;
    el.scrollLeft = scrollLeft - walkX;
    el.scrollTop = scrollTop - walkY;
  });
}

function showToast(msg, isError) {
  var tc = document.getElementById('toastCard');
  var ti = document.getElementById('toastIcon');
  var tt = document.getElementById('toastText');
  tc.className = 'toast-card ' + (isError ? 'error' : '') + ' show';
  ti.className = isError ? 'fas fa-exclamation-circle toast-icon' : 'fas fa-check-circle toast-icon';
  tt.innerHTML = msg;
  setTimeout(function(){ tc.classList.remove('show'); }, 4500);
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function showFullTextModal(el) {
  var wrap = $(el).closest('.adm-reason-note');
  $('#fullTextModalTitle').text(wrap.data('title') || 'Details');
  $('#fullTextModalBody').text(wrap.data('fulltext') || '');
  $('#fullTextModal').modal('show');
}

function buildReasonNoteHtml(text, color, title) {
  if (!text) return '';
  var short = text.length > 40 ? text.substring(0, 40) + '...' : text;
  var html = '<span class="adm-reason-note" style="color:' + color + ';" data-fulltext="' + escapeHtml(text) + '" data-title="' + escapeHtml(title) + '">' + escapeHtml(short);
  if (text.length > 40) html += ' <a href="javascript:void(0)" class="reason-readmore" onclick="showFullTextModal(this)">Read more</a>';
  html += '</span>';
  return html;
}

// Mirrors renderPaymentStatusBadge() in PHP — kept in sync so both tables look identical.
var PAYMENT_STATUS_COLORS = <?php echo json_encode($payment_status_colors); ?>;

function buildPaymentStatusBadgeHtml(overallStatus, paymentStatus, updatedBy, updatedAt) {
  if (overallStatus !== 'Approved') return '';
  var label = paymentStatus || 'Pending';
  var style = PAYMENT_STATUS_COLORS[label] || { bg: '#f1f5f9', c: '#64748b' };
  // Same solid-fill "button" treatment as the Approved badge — keeps each stage's own color,
  // just as a solid background with white text instead of a pastel pill.
  var html = '<div style="margin-top:6px;"><span class="badge-status" style="background:' + style.c + ';color:#ffffff;box-shadow:0 1px 4px ' + style.c + '66;"><i class="fas fa-university" style="margin-right:4px;"></i>' + escapeHtml(label) + '</span>';
  if (paymentStatus && updatedBy) {
    html += '<div style="font-size:10.5px;color:#94a3b8;margin-top:3px;">by ' + escapeHtml(updatedBy);
    if (updatedAt) html += ', ' + fmtDateTime(updatedAt);
    html += '</div>';
  }
  html += '</div>';
  return html;
}

function fmtDateTime(s) {
  var d = new Date(s.replace(' ', 'T'));
  if (isNaN(d.getTime())) return s;
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) + ', ' +
         d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: true });
}

// ---- CATEGORY DROPDOWN (searchable, click-to-select, type-to-add-new) ----
var ALL_CATEGORIES = [];

function loadCategories() {
  $.getJSON(window.location.pathname, { ajax_get_categories: 1 }, function(resp) {
    if (resp.success) ALL_CATEGORIES = resp.data;
  });
}

function renderCategoryList() {
  var q = $('#vf_category').val().trim().toLowerCase();
  var matches = ALL_CATEGORIES.filter(function(c){ return c.toLowerCase().indexOf(q) !== -1; });
  var html = '';
  if (matches.length) {
    matches.forEach(function(c){
      html += '<div class="cat-dropdown-item" onclick="selectCategory(\'' + c.replace(/'/g,"\\'") + '\')"><i class="fas fa-circle"></i>' + escapeHtml(c) + '</div>';
    });
  } else {
    html += '<div class="cat-dropdown-empty">No matching categories yet.</div>';
  }
  html += '<div class="cat-dropdown-addnew" onclick="addNewCategoryFromDropdown()"><i class="fas fa-plus-circle"></i> Add New Category</div>';
  $('#vf_category_list').html(html).addClass('show');
}

function addNewCategoryFromDropdown() {
  var typed = $('#vf_category').val().trim();
  var name = typed || prompt('Enter the new category name:');
  if (!name) return;
  name = name.trim();
  if (!name) return;
  $.post(window.location.pathname, { ajax_add_category: 1, categoryName: name }, function(resp) {
    if (resp.success) {
      if (ALL_CATEGORIES.indexOf(name) === -1) ALL_CATEGORIES.push(name);
      selectCategory(name);
      showToast('Category added.');
    } else {
      showToast(resp.message || 'Could not add category.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while adding category.', true); });
}

function selectCategory(c) {
  $('#vf_category').val(c);
  $('#vf_category_list').removeClass('show');
}

$(document).on('focus click', '#vf_category', function(){ renderCategoryList(); });
$(document).on('input', '#vf_category', function(){ renderCategoryList(); });
$(document).on('keydown', '#vf_category', function(e){ if (e.key === 'Enter') { e.preventDefault(); $('#vf_category_list').removeClass('show'); } });

// ---- AUTO AMOUNT IN WORDS ----
function numberToWordsIndian(num) {
  num = Math.round(parseFloat(num) || 0);
  if (num <= 0) return '';
  var ones = ['', 'One','Two','Three','Four','Five','Six','Seven','Eight','Nine','Ten','Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
  var tens = ['', '', 'Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
  function two(n) { return n < 20 ? ones[n] : (tens[Math.floor(n/10)] + (n % 10 ? ' ' + ones[n % 10] : '')); }
  function three(n) {
    var s = '';
    if (n > 99) { s += ones[Math.floor(n/100)] + ' Hundred'; n = n % 100; if (n) s += ' '; }
    if (n) s += two(n);
    return s;
  }
  var crore = Math.floor(num / 10000000); num %= 10000000;
  var lakh = Math.floor(num / 100000); num %= 100000;
  var thousand = Math.floor(num / 1000); num %= 1000;
  var rest = num;
  var parts = [];
  if (crore) parts.push(three(crore) + ' Crore');
  if (lakh) parts.push(three(lakh) + ' Lakh');
  if (thousand) parts.push(three(thousand) + ' Thousand');
  if (rest) parts.push(three(rest));
  return 'Rupees ' + parts.join(' ') + ' Only';
}

$(document).on('input', '#vf_amount', function(){
  $('#vf_words').val(numberToWordsIndian($(this).val()));
});

// ---- REMOVABLE FILE CHIPS (works for New/Edit Voucher and Rebuttal forms) ----
var fileSelections = {};

function initFileWidget(inputId, previewId, maxFiles) {
  fileSelections[inputId] = [];
  $('#' + inputId).on('change', function(){
    var incoming = Array.from(this.files);
    incoming.forEach(function(f){
      if (fileSelections[inputId].length < maxFiles) fileSelections[inputId].push(f);
    });
    if (incoming.length && fileSelections[inputId].length >= maxFiles) showToast('Maximum ' + maxFiles + ' files allowed.', false);
    syncFileInput(inputId);
    renderFileChips(inputId, previewId);
  });
}

function syncFileInput(inputId) {
  var dt = new DataTransfer();
  fileSelections[inputId].forEach(function(f){ dt.items.add(f); });
  document.getElementById(inputId).files = dt.files;
}

function renderFileChips(inputId, previewId) {
  var files = fileSelections[inputId] || [];
  if (!files.length) { $('#' + previewId).html('<span class="file-chip-empty">No files selected</span>'); return; }
  var html = '';
  files.forEach(function(f, idx){
    html += '<span class="file-chip"><span class="fname">' + escapeHtml(f.name) + '</span>' +
      '<button type="button" title="Remove" onclick="removeFileChip(\'' + inputId + '\',\'' + previewId + '\',' + idx + ')">&times;</button></span>';
  });
  $('#' + previewId).html(html);
}

function removeFileChip(inputId, previewId, idx) {
  fileSelections[inputId].splice(idx, 1);
  syncFileInput(inputId);
  renderFileChips(inputId, previewId);
}

function resetFileWidget(inputId, previewId) {
  fileSelections[inputId] = [];
  syncFileInput(inputId);
  renderFileChips(inputId, previewId);
}

// ---- NEW / EDIT VOUCHER ----
function openNewVoucherModal() {
  $('#voucherForm')[0].reset();
  $('#vf_id').val('');
  $('#vf_date').val('<?php echo date('Y-m-d'); ?>');
  $('#vf_title').html('<i class="fas fa-plus-circle"></i> New Voucher');
  $('#vf_existing_files').html('');
  resetFileWidget('vf_files', 'vf_files_preview');
  $('#vf_raise_ticket').prop('checked', false);
  $('#vf_raise_ticket_wrap').show();
  $('#vf_ticket_fields').hide();
  vftSelected = {};
  $('#vftTagArea .rt-tag').remove();
  $('#vft_subject').val('');
  $('#vft_message').val('');
  $('#vftError').hide();
  $('#voucherFormModal').modal('show');
}

function openEditVoucherModal(id) {
  $.getJSON(window.location.pathname, { ajax_get_voucher: id }, function(resp) {
    if (!resp.success) { showToast(resp.message || 'Could not load voucher.', true); return; }
    var d = resp.data;
    $('#voucherForm')[0].reset();
    $('#vf_id').val(d.id);
    $('#vf_title').html('<i class="fas fa-edit"></i> Edit Voucher — ' + d.voucher_number);
    $('#vf_date').val(d.expense_date);
    $('#vf_amount').val(d.amount);
    $('#vf_category').val(d.expense_category);
    $('#vf_payment_method').val(d.payment_method || 'Cash');
    $('#vf_paid_to').val(d.amount_paid_to);
    $('#vf_received_by').val(d.received_by);
    $('#vf_words').val(d.amount_in_words);
    $('#vf_account_of').val(d.on_account_of);
    resetFileWidget('vf_files', 'vf_files_preview');
    var filesTxt = (d.proof_files_arr && d.proof_files_arr.length) ? (d.proof_files_arr.length + ' existing file(s) attached. Uploading new files will replace them.') : 'No files attached yet.';
    $('#vf_existing_files').text(filesTxt);
    // Editing an existing voucher already has its own row-level Raise Ticket button
    $('#vf_raise_ticket').prop('checked', false);
    $('#vf_raise_ticket_wrap').hide();
    if (d.status === 'Declined') showToast('Editing this declined voucher will resubmit it for review.', false);
    $('#voucherFormModal').modal('show');
  });
}

// ---- Inline ticket fields inside the New Voucher modal ----
var vftSelected = {};

$(document).on('change', '#vf_raise_ticket', function(){
  var show = $(this).is(':checked');
  $('#vf_ticket_fields').toggle(show);
  if (show) {
    loadEmployeesForTicket(function(){});
    if (!$('#vft_subject').val()) buildInlineTicketPreview();
  }
});

function buildInlineTicketPreview() {
  var category = $('#vf_category').val().trim() || 'expense';
  var amount = parseFloat($('#vf_amount').val()) || 0;
  var dateVal = $('#vf_date').val();
  var accountOf = $('#vf_account_of').val().trim();
  $('#vft_subject').val('Query on new Digital Expense voucher (' + category + ')');
  $('#vft_message').val(
    "Hi,\n\nI'd like to raise a query regarding a Digital Expense voucher I'm submitting.\n\n" +
    "Date: " + (dateVal || '-') + "\n" +
    "Amount: Rs. " + amount.toFixed(2) + "\n" +
    "Category: " + category + "\n" +
    (accountOf ? "On Account Of: " + accountOf + "\n" : "") + "\n" +
    "(Voucher number will be assigned once saved.)\n\n" +
    "Please review and advise.\n\nThanks,\n<?php echo addslashes($employee_name_db); ?>"
  );
}
$(document).on('input change', '#vf_amount, #vf_category, #vf_date, #vf_account_of', function(){
  if ($('#vf_raise_ticket').is(':checked') && !vftUserEditedText) buildInlineTicketPreview();
});
var vftUserEditedText = false;
$(document).on('input', '#vft_subject, #vft_message', function(){ vftUserEditedText = true; });

function renderVftDropdown(filter) {
  filter = (filter || '').toLowerCase();
  var html = '';
  ALL_EMPLOYEES_FOR_TICKET
    .filter(function(e){ return e.name.toLowerCase().indexOf(filter) !== -1; })
    .forEach(function(e){
      var sel = vftSelected[e.id] ? 'selected' : '';
      html += '<div class="rt-opt ' + sel + '" data-id="' + e.id + '" data-name="' + escapeHtml(e.name) + '" onclick="toggleVftOption(this)"><span class="rt-check"></span>' + escapeHtml(e.name) + '</div>';
    });
  $('#vftDropdown').html(html).show();
}

function toggleVftOption(el) {
  var id = el.dataset.id, name = el.dataset.name;
  if (vftSelected[id]) { delete vftSelected[id]; el.classList.remove('selected'); }
  else { vftSelected[id] = name; el.classList.add('selected'); }
  syncVftTags();
  $('#vftError').hide();
}

function removeVftTag(id) {
  delete vftSelected[id];
  var opt = document.querySelector('#vftDropdown .rt-opt[data-id="' + id + '"]');
  if (opt) opt.classList.remove('selected');
  syncVftTags();
}

function syncVftTags() {
  $('#vftTagArea .rt-tag').remove();
  Object.keys(vftSelected).forEach(function(id){
    var tag = $('<div class="rt-tag"><span>' + escapeHtml(vftSelected[id]) + '</span><span class="rt-tag-x" onclick="removeVftTag(\'' + id + '\')">&times;</span></div>');
    tag.insertBefore('#vftSearch');
  });
}

$(document).on('input focus', '#vftSearch', function(){ renderVftDropdown($(this).val()); });
$(document).on('click', function(e){
  if (!$(e.target).closest('#vftMultiSelectWrap').length) $('#vftDropdown').hide();
});

$('#voucherForm').on('submit', function(e){
  e.preventDefault();
  var id = $('#vf_id').val();
  var raiseTicket = !id && $('#vf_raise_ticket').is(':checked');

  if (raiseTicket) {
    if (!Object.keys(vftSelected).length) { $('#vftError').show(); return; }
    if (!$('#vft_subject').val().trim() || !$('#vft_message').val().trim()) { showToast('Ticket subject and message are required.', true); return; }
  }

  var fd = new FormData(this);
  fd.append(id ? 'ajax_edit_expense' : 'ajax_create_expense', 1);
  if (raiseTicket) {
    fd.append('raise_ticket', '1');
    fd.append('ticket_subject', $('#vft_subject').val());
    fd.append('ticket_message', $('#vft_message').val());
    Object.keys(vftSelected).forEach(function(eid){ fd.append('ticket_assigned_to[]', eid); });
  }

  $.ajax({
    url: window.location.pathname, type: 'POST', data: fd, processData: false, contentType: false, dataType: 'json',
    success: function(resp) {
      if (resp.success) {
        showToast(resp.message);
        if (resp.upload_warnings && resp.upload_warnings.length) showToast(resp.upload_warnings.join('<br>'), true);
        if (resp.ticket_warning) showToast(resp.ticket_warning, true);
        $('#voucherFormModal').modal('hide');
        if (resp.ticket_numbers && resp.ticket_numbers.length) {
          setTimeout(function(){ showTicketSuccessModal(resp.ticket_numbers); }, 400);
        } else {
          setTimeout(function(){ window.location.reload(); }, resp.ticket_warning ? 2500 : 700);
        }
      } else {
        showToast(resp.message || 'Could not save voucher.', true);
      }
    },
    error: function(){ showToast('Server error while saving voucher.', true); }
  });
});

// Reuses the standalone Raise Ticket modal's success view to show ticket numbers prominently
function showTicketSuccessModal(ticketNumbers) {
  var chips = '';
  ticketNumbers.forEach(function(tn){ chips += '<span class="rt-ticket-chip"><i class="fas fa-ticket-alt"></i> ' + escapeHtml(tn) + '</span>'; });
  $('#rtTicketNumbers').html(chips);
  $('#rtFormView').hide();
  $('#rtSuccessView').show();
  $('#rtFormFooter').hide();
  $('#rtSuccessFooter').show();
  rtNeedsReloadOnClose = true;
  $('#raiseTicketModal').modal('show');
}

// ---- RAISE TICKET ----
var ALL_EMPLOYEES_FOR_TICKET = [];
var rtSelected = {};

function loadEmployeesForTicket(cb) {
  if (ALL_EMPLOYEES_FOR_TICKET.length) { cb(); return; }
  $.getJSON(window.location.pathname, { ajax_get_active_employees: 1 }, function(resp) {
    if (resp.success) ALL_EMPLOYEES_FOR_TICKET = resp.data;
    cb();
  });
}

function renderRtDropdown(filter) {
  filter = (filter || '').toLowerCase();
  var html = '';
  ALL_EMPLOYEES_FOR_TICKET
    .filter(function(e){ return e.name.toLowerCase().indexOf(filter) !== -1; })
    .forEach(function(e){
      var sel = rtSelected[e.id] ? 'selected' : '';
      html += '<div class="rt-opt ' + sel + '" data-id="' + e.id + '" data-name="' + escapeHtml(e.name) + '" onclick="toggleRtOption(this)"><span class="rt-check"></span>' + escapeHtml(e.name) + '</div>';
    });
  $('#rtDropdown').html(html).show();
}

function toggleRtOption(el) {
  var id = el.dataset.id, name = el.dataset.name;
  if (rtSelected[id]) { delete rtSelected[id]; el.classList.remove('selected'); }
  else { rtSelected[id] = name; el.classList.add('selected'); }
  syncRtTags();
  $('#rtError').hide();
}

function removeRtTag(id) {
  delete rtSelected[id];
  var opt = document.querySelector('.rt-opt[data-id="' + id + '"]');
  if (opt) opt.classList.remove('selected');
  syncRtTags();
}

function syncRtTags() {
  $('#rtTagArea .rt-tag').remove();
  Object.keys(rtSelected).forEach(function(id){
    var tag = $('<div class="rt-tag"><span>' + escapeHtml(rtSelected[id]) + '</span><span class="rt-tag-x" onclick="removeRtTag(\'' + id + '\')">&times;</span></div>');
    tag.insertBefore('#rtSearch');
  });
}

$(document).on('input focus', '#rtSearch', function(){ renderRtDropdown($(this).val()); });
$(document).on('click', function(e){
  if (!$(e.target).closest('#rtMultiSelectWrap').length) $('#rtDropdown').hide();
});

function openRaiseTicketModal(voucherId) {
  rtSelected = {};
  $('#rt_voucher_id').val(voucherId || '');
  $('#rtTagArea .rt-tag').remove();
  $('#rtSearch').val('');
  $('#rtDropdown').hide().html('');
  $('#rtError').hide();
  $('#rt_subject').val('');
  $('#rt_message').val('Loading suggested text…');
  $('#rtFormView').show();
  $('#rtSuccessView').hide();
  $('#rtFormFooter').show();
  $('#rtSuccessFooter').hide();
  rtNeedsReloadOnClose = false;
  loadEmployeesForTicket(function(){});
  $.getJSON(window.location.pathname, { ajax_ticket_preview: 1, voucher_id: voucherId || '' }, function(resp) {
    if (resp.success) {
      $('#rt_subject').val(resp.subject);
      $('#rt_message').val(resp.message);
    }
  });
  $('#raiseTicketModal').modal('show');
}

var rtNeedsReloadOnClose = false;

function submitRaiseTicket() {
  if (!Object.keys(rtSelected).length) { $('#rtError').show(); return; }
  if (!$('#rt_subject').val().trim() || !$('#rt_message').val().trim()) { showToast('Subject and message are required.', true); return; }
  $.post(window.location.pathname, {
    ajax_raise_ticket: 1,
    voucher_id: $('#rt_voucher_id').val(),
    subject: $('#rt_subject').val(),
    message: $('#rt_message').val(),
    assigned_to: Object.keys(rtSelected)
  }, function(resp) {
    if (resp.success) {
      var chips = '';
      (resp.ticket_numbers || []).forEach(function(tn){ chips += '<span class="rt-ticket-chip"><i class="fas fa-ticket-alt"></i> ' + escapeHtml(tn) + '</span>'; });
      $('#rtTicketNumbers').html(chips);
      $('#rtFormView').hide();
      $('#rtSuccessView').show();
      $('#rtFormFooter').hide();
      $('#rtSuccessFooter').show();
      rtNeedsReloadOnClose = true;
    } else {
      showToast(resp.message || 'Could not raise ticket.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while raising ticket.', true); });
}

$('#raiseTicketModal').on('hidden.bs.modal', function(){
  if (rtNeedsReloadOnClose) window.location.reload();
});

// ---- VIEW VOUCHER ----
function viewVoucher(id) {
  $('#viewVoucherContent').html('<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>');
  $('#vv_print_link').attr('href', '?view=voucher&id=' + id);
  $('#viewVoucherModal').modal('show');
  $.getJSON(window.location.pathname, { ajax_get_voucher: id }, function(resp) {
    if (!resp.success) { $('#viewVoucherContent').html('<div style="color:#dc2626;text-align:center;padding:20px;">' + (resp.message||'Could not load voucher.') + '</div>'); return; }
    var d = resp.data;
    var html = '';
    html += '<div class="v-detail-row"><div class="v-detail-label">Voucher No</div><div class="v-detail-value">' + escapeHtml(d.voucher_number) + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Date</div><div class="v-detail-value">' + d.expense_date + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Amount</div><div class="v-detail-value">₹' + parseFloat(d.amount).toLocaleString('en-IN',{minimumFractionDigits:2}) + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Payment Method</div><div class="v-detail-value">' + escapeHtml(d.payment_method || '-') + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Amount Paid To</div><div class="v-detail-value">' + escapeHtml(d.amount_paid_to || '-') + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Amount in Words</div><div class="v-detail-value">' + escapeHtml(d.amount_in_words || '-') + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">On Account Of</div><div class="v-detail-value">' + escapeHtml(d.on_account_of || '-') + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Received Person</div><div class="v-detail-value">' + escapeHtml(d.received_by || '-') + '</div></div>';
    html += '<div class="v-detail-row"><div class="v-detail-label">Status</div><div class="v-detail-value">' + escapeHtml(d.status) + '</div></div>';
    if (d.payment_status) {
      html += '<div class="v-detail-row"><div class="v-detail-label">Payment Status</div><div class="v-detail-value" style="color:#0f766e;"><i class="fas fa-university"></i> ' + escapeHtml(d.payment_status) + '</div></div>';
    }
    if (d.ticket_numbers_arr && d.ticket_numbers_arr.length) {
      html += '<div class="v-detail-row"><div class="v-detail-label">Linked Ticket(s)</div><div class="v-detail-value">';
      d.ticket_numbers_arr.forEach(function(tn){ html += '<span class="rt-ticket-chip" style="font-size:12px;padding:5px 12px;margin:2px 4px 2px 0;"><i class="fas fa-ticket-alt"></i> ' + escapeHtml(tn) + '</span>'; });
      html += '</div></div>';
    }
    if (d.l1_status && d.l1_status !== 'Pending') {
      html += '<div class="v-detail-row"><div class="v-detail-label">L1 Approval</div><div class="v-detail-value">' + escapeHtml(d.l1_status) + (d.l1_by ? ' — ' + escapeHtml(d.l1_by) : '') + (d.l1_at ? ' (' + fmtDT(d.l1_at) + ')' : '') + '</div></div>';
    }
    if (d.l2_status && d.l2_status !== 'Pending') {
      html += '<div class="v-detail-row"><div class="v-detail-label">L2 Approval</div><div class="v-detail-value">' + escapeHtml(d.l2_status) + (d.l2_by ? ' — ' + escapeHtml(d.l2_by) : '') + (d.l2_at ? ' (' + fmtDT(d.l2_at) + ')' : '') + (d.l2_override == 1 ? ' <span style="color:#92400e;">(Override)</span>' : '') + '</div></div>';
    }
    if (d.status === 'Declined' && d.manager_reason) {
      html += '<div style="margin-top:14px;background:#fef2f2;border-radius:8px;padding:12px 16px;color:#991b1b;font-size:13px;"><strong>Reason for Decline:</strong> ' + escapeHtml(d.manager_reason) + '</div>';
    }
    if (d.employee_response) {
      html += '<div style="margin-top:14px;background:#f3e5f5;border-radius:8px;padding:12px 16px;color:#6a1b9a;font-size:13px;"><strong>Your Explanation:</strong> ' + escapeHtml(d.employee_response) + '</div>';
    }
    if (d.proof_files_arr && d.proof_files_arr.length) {
      html += '<div style="margin-top:18px;"><h6 style="color:#0f2557;font-weight:700;margin-bottom:10px;">Attached Proofs</h6><div class="proof-thumb-grid">';
      d.proof_files_arr.forEach(function(p){ html += renderProofItem(p); });
      html += '</div></div>';
    }
    if (d.rebuttal_proof_files_arr && d.rebuttal_proof_files_arr.length) {
      html += '<div style="margin-top:18px;"><h6 style="color:#7b1fa2;font-weight:700;margin-bottom:10px;">Rebuttal Proofs</h6><div class="proof-thumb-grid">';
      d.rebuttal_proof_files_arr.forEach(function(p){ html += renderProofItem(p); });
      html += '</div></div>';
    }
    $('#viewVoucherContent').html(html);
  });
}

// ---- IMAGE VIEWER ----
var currentZoom = 1;
function openImageViewer(src) {
  currentZoom = 1;
  $('#viewerImage').css('transform', 'scale(' + currentZoom + ')');
  $('#viewerImage').attr('src', src);
  $('#imageViewerModal').modal('show');
}
function zoomImage(delta) {
  currentZoom += delta;
  if (currentZoom < 0.2) currentZoom = 0.2;
  if (currentZoom > 5) currentZoom = 5;
  $('#viewerImage').css('transform', 'scale(' + currentZoom + ')');
}
function resetZoom() {
  currentZoom = 1;
  $('#viewerImage').css('transform', 'scale(1)');
}

function renderProofItem(p) {
  var isPdf = p.filename && p.filename.toLowerCase().endsWith('.pdf');
  var name = escapeHtml(p.originalName || p.filename || 'Proof File');
  var preview = isPdf ? '<i class="fas fa-file-pdf"></i>' : '<img src="' + p.path + '">';
  
  var viewAction = isPdf 
    ? '<a href="' + p.path + '" target="_blank" class="proof-card-btn proof-btn-view"><i class="fas fa-eye"></i> View</a>' 
    : '<button type="button" class="proof-card-btn proof-btn-view" style="border:none;" onclick="openImageViewer(\'' + escapeHtml(p.path) + '\')"><i class="fas fa-eye"></i> View</button>';
  
  return '<div class="proof-card">' +
    '<div class="proof-card-preview">' + preview + '</div>' +
    '<div class="proof-card-info">' +
      '<div class="proof-card-name" title="' + name + '">' + name + '</div>' +
      '<div class="proof-card-actions">' +
        viewAction +
        '<a href="' + p.path + '" download class="proof-card-btn proof-btn-dl"><i class="fas fa-download"></i> DL</a>' +
      '</div>' +
    '</div>' +
  '</div>';
}

// ---- REBUTTAL ----
function openRebuttalModal(id) {
  $('#rebuttalForm')[0].reset();
  $('#rb_id').val(id);
  resetFileWidget('rb_files', 'rb_files_preview');
  $('#rebuttalModal').modal('show');
}

$('#rebuttalForm').on('submit', function(e){
  e.preventDefault();
  var fd = new FormData(this);
  fd.append('ajax_submit_rebuttal', 1);
  $.ajax({
    url: window.location.pathname, type: 'POST', data: fd, processData: false, contentType: false, dataType: 'json',
    success: function(resp) {
      if (resp.success) {
        $('#rebuttalModal').modal('hide');
        showToast(resp.message);
        setTimeout(function(){ window.location.reload(); }, 900);
      } else {
        showToast(resp.message || 'Could not submit explanation.', true);
      }
    },
    error: function(){ showToast('Server error while submitting explanation.', true); }
  });
});

// ---- DELETE ----
function deleteVoucher(id) {
  if (!confirm('Delete this voucher? This cannot be undone.')) return;
  $.post(window.location.pathname, { ajax_delete_expense: 1, id: id }, function(resp) {
    if (resp.success) { showToast(resp.message); setTimeout(function(){ window.location.reload(); }, 800); }
    else showToast(resp.message || 'Could not delete voucher.', true);
  }, 'json').fail(function(){ showToast('Server error while deleting voucher.', true); });
}

// ---- ACTIVITY ----
function openActivityModal() {
  $('#activityContent').html('<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>');
  $('#activityModal').modal('show');
  $.getJSON(window.location.pathname, { ajax_activity: 1 }, function(resp) {
    if (resp.success && resp.data.length) {
      var html = '';
      resp.data.forEach(function(h){
        html += '<div class="activity-item"><strong style="color:#0f2557;">' + escapeHtml(h.action) + '</strong>' +
          (h.voucher_number ? ' — ' + escapeHtml(h.voucher_number) : '') +
          '<div style="color:#64748b;margin-top:4px;">' + escapeHtml(h.details) + '</div>' +
          '<div style="color:#94a3b8;font-size:11px;margin-top:4px;">' + h.date + '</div></div>';
      });
      $('#activityContent').html(html);
    } else {
      $('#activityContent').html('<div style="text-align:center;padding:40px;color:#94a3b8;">No activity yet.</div>');
    }
  });
}

// ---- VOUCHER HISTORY (visible to everyone who can see the voucher) ----
function openVoucherHistory(id) {
  $('#vh_voucher_number').text('');
  $('#voucherHistoryBody').html('<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>');
  $('#voucherHistoryModal').modal('show');
  $.getJSON(window.location.pathname, { ajax_voucher_history: id }, function(resp) {
    if (!resp.success) { $('#voucherHistoryBody').html('<div style="color:#dc2626;text-align:center;padding:20px;">' + (resp.message || 'Could not load history.') + '</div>'); return; }
    $('#vh_voucher_number').text(resp.voucher_number);
    var html = '<div class="activity-item"><strong style="color:#0f2557;">Created</strong><div style="color:#64748b;margin-top:4px;">by ' + escapeHtml(resp.created_by) + '</div><div style="color:#94a3b8;font-size:11px;margin-top:4px;">' + resp.created_at + '</div></div>';
    resp.timeline.forEach(function(h){
      html += '<div class="activity-item"><strong style="color:#0f2557;">' + escapeHtml(h.action) + '</strong>' +
        '<div style="color:#64748b;margin-top:4px;">' + escapeHtml(h.details) + '</div>' +
        '<div style="color:#94a3b8;font-size:11px;margin-top:4px;">by ' + escapeHtml(h.performed_by) + ' &middot; ' + h.date + '</div></div>';
    });
    $('#voucherHistoryBody').html(html);
  }).fail(function(){
    $('#voucherHistoryBody').html('<div style="color:#dc2626;text-align:center;padding:20px;">Server error loading history.</div>');
  });
}

// ---- PAYMENT STATUS (finance team, Approved vouchers only) ----
function openPaymentStatusModal(id, currentStatus) {
  $('#ps_voucher_id').val(id);
  if (currentStatus) $('#ps_status').val(currentStatus);
  $('#paymentStatusModal').modal('show');
}

function submitPaymentStatus() {
  var id = $('#ps_voucher_id').val();
  var status = $('#ps_status').val();
  $.post(window.location.pathname, { ajax_update_payment_status: 1, id: id, payment_status: status }, function(resp) {
    if (resp.success) { $('#paymentStatusModal').modal('hide'); showToast(resp.message); loadAdminList(); }
    else showToast(resp.message || 'Could not update payment status.', true);
  }, 'json').fail(function(){ showToast('Server error.', true); });
}


// ---- WHATSAPP REPORT ----
function openWhatsAppReportModal() {
  $('#wa_from').val('');
  $('#wa_to').val('');
  $('#waReportModal').modal('show');
}

function sendWhatsAppReport() {
  var from = $('#wa_from').val();
  var to = $('#wa_to').val();
  var rows = EXPENSES_DATA.filter(function(e){
    if (from && e.expense_date < from) return false;
    if (to && e.expense_date > to) return false;
    return true;
  });

  if (!rows.length) { showToast('No vouchers found in the selected date range.', true); return; }

  var totalAmount = 0, approved = 0, declined = 0, pending = 0;
  var approvedList = [], declinedList = [], pendingList = [];
  rows.forEach(function(e){
    var amt = parseFloat(e.amount) || 0;
    totalAmount += amt;
    var paidTo = e.amount_paid_to ? ' (' + e.amount_paid_to + ')' : '';
    var line = e.voucher_number + ' - Rs.' + amt.toFixed(2) + paidTo;
    var st = (e.status || 'Pending').toUpperCase();
    if (st === 'APPROVED') { approved++; approvedList.push(line); }
    else if (st === 'DECLINED') { declined++; declinedList.push(line); }
    else { pending++; pendingList.push(line); }
  });

  var now = new Date();
  var nowStr = now.toLocaleDateString('en-GB', { day:'2-digit', month:'short', year:'numeric' });

  var msg = '*Digital Expenses Report* Generated: ' + nowStr + '\n';
  msg += '*Employee:* <?php echo addslashes($employee_name_db); ?>\n';
  msg += '*Summary*\n';
  msg += 'Total Vouchers : ' + rows.length + '\n';
  msg += 'Total Amount : Rs.' + totalAmount.toFixed(2) + '\n';
  msg += 'Approved : ' + approved + '\n';
  msg += 'Declined : ' + declined + '\n';
  msg += 'Pending : ' + pending + '\n';

  if (approvedList.length) { msg += '*Approved Vouchers*\n' + approvedList.join('\n') + '\n'; }
  if (declinedList.length) { msg += '*Declined Vouchers*\n' + declinedList.join('\n') + '\n'; }
  if (pendingList.length) { msg += '*Pending Vouchers*\n' + pendingList.join('\n') + '\n'; }

  msg += '\nShared from the Digital Expenses portal.';

  window.open('https://wa.me/?text=' + encodeURIComponent(msg), '_blank');
  $('#waReportModal').modal('hide');
}

// ---- ADMIN PANEL (in-page tab, visible only if $isAdmin server-side) ----
var adminFilterOptionsLoaded = false;

function switchDxTab(tab) {
  if (tab === 'admin') {
    $('#adminVouchersPanel').show();
    $('#myVouchersPanel').hide();
    $('#tabBtnAdmin').addClass('active');
    $('#tabBtnMine').removeClass('active');
    loadAdminData();
  } else {
    $('#myVouchersPanel').show();
    $('#adminVouchersPanel').hide();
    $('#tabBtnMine').addClass('active');
    $('#tabBtnAdmin').removeClass('active');
  }
}

function filterAdminByStatus(status) {
  $('#adm_f_status').val(status);
  loadAdminList();
  $('html, body').animate({ scrollTop: $('.table-responsive').last().offset().top - 100 }, 300);
}

function loadAdminData() {
  if (!adminFilterOptionsLoaded) {
    $.getJSON(window.location.pathname, { ajax_admin_filter_options: 1 }, function(resp) {
      if (resp.success) {
        var empHtml = '<option value="">All Employees</option>';
        resp.employees.forEach(function(e){ empHtml += '<option value="' + e.id + '">' + escapeHtml(e.name) + '</option>'; });
        $('#adm_f_employee').html(empHtml);
        var coHtml = '<option value="">All Companies</option>';
        resp.companies.forEach(function(c){ coHtml += '<option value="' + escapeHtml(c) + '">' + escapeHtml(c) + '</option>'; });
        $('#adm_f_company').html(coHtml);
      }
      adminFilterOptionsLoaded = true;
    }).fail(function(){
      showToast('Could not load filter options (server error).', true);
    });
  }
  loadAdminList();
}

<?php if ($canViewAllVouchers): ?>
$(document).ready(function(){ loadAdminData(); });
<?php endif; ?>

function loadAdminList() {
  // Preserve the table's scroll position across a refresh — without this,
  // re-rendering the whole tbody after any action (approve/decline/revert/
  // delete/payment-status) snaps the view back to the first rows, losing
  // whatever row the user was working on further down the list.
  var $adminScrollBox = $('#adminTableScroll');
  var savedAdminScrollTop = $adminScrollBox.scrollTop();
  $('#adminTableBody').html('<tr><td colspan="11" style="text-align:center;padding:40px;color:#94a3b8;">Loading...</td></tr>');
  var qs = {
    ajax_admin_list: 1,
    a_status: $('#adm_f_status').val(),
    a_employee: $('#adm_f_employee').val(),
    a_company: $('#adm_f_company').val(),
    a_search: $('#adm_f_search').val(),
    a_from: $('#adm_f_from').val(),
    a_to: $('#adm_f_to').val()
  };
  $.getJSON(window.location.pathname, qs, function(resp) {
    if (!resp.success) { showToast(resp.message || 'Could not load vouchers.', true); $('#adminTableBody').html('<tr><td colspan="11" style="text-align:center;padding:40px;color:#94a3b8;">Could not load vouchers.</td></tr>'); return; }
    var s = resp.stats;
    $('#admStatAmt').text('₹' + parseFloat(s.total_amt).toLocaleString('en-IN', {minimumFractionDigits:2}));
    $('#admStatApproved').text(s.approved);
    $('#admStatPending').text(s.pending);
    $('#admStatDeclined').text(s.declined);
    $('#admStatResponse').text(s.response_submitted);
    $('#admStatProof').text(s.with_proof + ' / ' + s.without_proof);

    if (!resp.data.length) {
      $('#adminTableBody').html('<tr><td colspan="11" style="text-align:center;padding:40px;color:#94a3b8;">No vouchers found matching the criteria.</td></tr>');
      $adminScrollBox.scrollTop(0);
      return;
    }
    var html = '';
    ADMIN_EXPENSES_DATA = resp.data;
    resp.data.forEach(function(exp) {
      var st = exp.status;
      var badgeStyle = 'background:#c2410c;color:#ffffff;';
      if (st === 'Approved') badgeStyle = 'background:#25D366;color:#ffffff;box-shadow:0 1px 4px rgba(37,211,102,.4);';
      else if (st === 'Declined') badgeStyle = 'background:#dc2626;color:#ffffff;';
      else if (st === 'Response Submitted') badgeStyle = 'background:#7b1fa2;color:#ffffff;';
      else if (st === 'Pending L2 Approval') badgeStyle = 'background:#4338ca;color:#ffffff;';

      var canL1Review = IS_L1 && exp.l1_status === 'Pending';
      var canL1Revert = IS_L1 && exp.l2_status === 'Pending' && (exp.l1_status === 'Approved' || exp.l1_status === 'Declined');
      var canL2Review = IS_ADMIN && exp.l1_status === 'Approved' && exp.l2_status === 'Pending';
      var canL2Override = IS_ADMIN && exp.l2_status === 'Pending' && exp.l1_status !== 'Approved';
      var canRevert = IS_ADMIN && ((st === 'Approved' && !exp.payment_status) || st === 'Declined');
      var canDeleteRow = IS_ADMIN;

      var statusExtra = '';
      if (st === 'Declined' && exp.manager_reason) {
        statusExtra = buildReasonNoteHtml(exp.manager_reason, '#b91c1c', 'Decline Reason');
      } else if (st === 'Response Submitted' && exp.employee_response) {
        statusExtra = buildReasonNoteHtml(exp.employee_response, '#7b1fa2', 'Your Explanation');
      }
      statusExtra += buildPaymentStatusBadgeHtml(st, exp.payment_status, exp.payment_status_updated_by, exp.payment_status_updated_at);

      var l1Cell = buildStageCellHtml('L1', exp.l1_status, exp.l1_by, exp.l1_at, exp.l1_reason, false, null);
      var l2Cell = buildStageCellHtml('L2', exp.l2_status, exp.l2_by, exp.l2_at, exp.l2_reason, exp.l2_override == 1, exp.l2_override_reason);

      html += '<tr>';
      html += '<td><strong>' + escapeHtml(exp.added_by_name || '-') + '</strong></td>';
      html += '<td><strong style="color:#0f2557;">' + escapeHtml(exp.voucher_number) + '</strong></td>';
      html += '<td>' + new Date(exp.expense_date).toLocaleDateString('en-GB') + '<div style="font-size:10.5px;color:#94a3b8;margin-top:2px;">' + fmtTimeOnly(exp.created_at) + '</div></td>';
      html += '<td>' + escapeHtml(exp.expense_category) + '</td>';
      html += '<td><strong>₹' + parseFloat(exp.amount).toLocaleString('en-IN', {minimumFractionDigits:2}) + '</strong></td>';
      html += '<td>' + escapeHtml(exp.amount_paid_to || '-') + '</td>';
      html += '<td>' + (exp.has_proof ? '<i class="fas fa-paperclip proof-yes"></i>' : '<i class="fas fa-exclamation-triangle proof-no"></i>') + '</td>';
      var mainStatusBadge = st !== 'Approved' ? '<span class="badge-status" style="' + badgeStyle + '">' + escapeHtml(st) + '</span>' : '';
      html += '<td>' + mainStatusBadge + statusExtra + '</td>';
      html += '<td>' + l1Cell + '</td>';
      html += '<td>' + l2Cell + '</td>';
      html += '<td style="text-align:right;white-space:nowrap;">';
      html += '<button type="button" class="btn-sm-action btn-view" title="View" onclick="viewVoucher(' + exp.id + ')"><i class="fas fa-eye"></i></button>';
      html += '<a class="btn-sm-action btn-print" title="Print" href="?view=voucher&id=' + exp.id + '" target="_blank"><i class="fas fa-print"></i></a>';
      html += '<button type="button" class="btn-sm-action" style="background:#f1f5f9;color:#475569;" title="History" onclick="openVoucherHistory(' + exp.id + ')"><i class="fas fa-history"></i></button>';
      if (st === 'Approved') {
        html += '<button type="button" class="btn-sm-action" style="background:#ecfeff;color:#0f766e;" title="Update Payment Status" onclick="openPaymentStatusModal(' + exp.id + ',\'' + escapeHtml(exp.payment_status || '') + '\')"><i class="fas fa-university"></i></button>';
      }
      if (canL1Review) {
        html += '<button type="button" class="btn-sm-action" style="background:#ecfdf5;color:#059669;" title="L1 Approve" onclick="adminSetStatus(' + exp.id + ',\'l1_approve\')"><i class="fas fa-check-circle"></i> L1</button>';
        html += '<button type="button" class="btn-sm-action" style="background:#fef2f2;color:#dc2626;" title="L1 Decline" onclick="openDeclineModal(' + exp.id + ',\'l1_decline\',\'L1 Decline Voucher\',false)"><i class="fas fa-times-circle"></i> L1</button>';
      }
      if (canL1Revert) {
        html += '<button type="button" class="btn-sm-action" style="background:#fff7ed;color:#c2410c;" title="Revert my L1 decision" onclick="adminSetStatus(' + exp.id + ',\'l1_revert\')"><i class="fas fa-undo"></i> L1</button>';
      }
      if (canL2Review) {
        html += '<button type="button" class="btn-sm-action" style="background:#ecfdf5;color:#059669;" title="L2 Approve (Final)" onclick="adminSetStatus(' + exp.id + ',\'l2_approve\')"><i class="fas fa-check-circle"></i> L2</button>';
        html += '<button type="button" class="btn-sm-action" style="background:#fef2f2;color:#dc2626;" title="L2 Decline" onclick="openDeclineModal(' + exp.id + ',\'l2_decline\',\'L2 Decline Voucher\',false)"><i class="fas fa-times-circle"></i> L2</button>';
      }
      if (canL2Override) {
        html += '<button type="button" class="btn-sm-action" style="background:#fef3c7;color:#92400e;" title="Override Approve (bypass L1)" onclick="openOverrideApproveModal(' + exp.id + ')"><i class="fas fa-bolt"></i> Ovr</button>';
        html += '<button type="button" class="btn-sm-action" style="background:#fef3c7;color:#92400e;" title="Override Decline (bypass L1)" onclick="openDeclineModal(' + exp.id + ',\'l2_override_decline\',\'L2 Override Decline\',true)"><i class="fas fa-bolt"></i> Ovr</button>';
      }
      if (canRevert) {
        html += '<button type="button" class="btn-sm-action" style="background:#fff7ed;color:#c2410c;" title="Revert to Pending (L1)" onclick="adminSetStatus(' + exp.id + ',\'revert\')"><i class="fas fa-undo"></i></button>';
      }
      if (canDeleteRow) {
        html += '<button type="button" class="btn-sm-action btn-del" title="Delete" onclick="adminDeleteVoucher(' + exp.id + ')"><i class="fas fa-trash"></i></button>';
      }
      html += '</td></tr>';
    });
    $('#adminTableBody').html(html);
    $adminScrollBox.scrollTop(savedAdminScrollTop);
  }).fail(function(jqXHR){
    var msg = 'Could not load vouchers (server error' + (jqXHR && jqXHR.status ? ', HTTP ' + jqXHR.status : '') + ').';
    showToast(msg, true);
    $('#adminTableBody').html('<tr><td colspan="11" style="text-align:center;padding:40px;color:#dc2626;">' + msg + '</td></tr>');
  });
}

function adminSetStatus(id, action) {
  var confirmMsgs = {
    l1_approve: 'Approve this voucher at L1?',
    l1_revert: 'Revert your L1 decision on this voucher back to Pending?',
    l2_approve: 'Approve this voucher at L2 (final approval)?',
    revert: "Revert this voucher? If only L2 declined it, L1's existing approval is kept and just L2 resets — otherwise both L1 and L2 reset."
  };
  if (!confirm(confirmMsgs[action] || 'Proceed?')) return;
  $.post(window.location.pathname, { ajax_admin_set_status: 1, id: id, action: action }, function(resp) {
    if (resp.success) { showToast(resp.message); loadAdminList(); }
    else showToast(resp.message || 'Action failed.', true);
  }, 'json').fail(function(){ showToast('Server error.', true); });
}

function openDeclineModal(id, action, title, isOverride) {
  $('#adm_decline_id').val(id);
  $('#adm_decline_action').val(action);
  $('#adm_decline_reason').val('');
  $('#adm_override_reason').val('');
  $('#admDeclineModalTitle').text(title || 'Decline Voucher');
  $('#adm_override_wrap').toggle(!!isOverride);
  $('#admDeclineModal').modal('show');
}

function openOverrideApproveModal(id) {
  $('#ovr_approve_id').val(id);
  $('#ovr_approve_reason').val('');
  $('#overrideApproveModal').modal('show');
}

function submitOverrideApprove() {
  var id = $('#ovr_approve_id').val();
  var overrideReason = $('#ovr_approve_reason').val().trim();
  if (!overrideReason) { showToast('A justification is required to override L1.', true); return; }
  $.post(window.location.pathname, { ajax_admin_set_status: 1, id: id, action: 'l2_override_approve', override_reason: overrideReason }, function(resp) {
    if (resp.success) { $('#overrideApproveModal').modal('hide'); showToast(resp.message); loadAdminList(); }
    else showToast(resp.message || 'Action failed.', true);
  }, 'json').fail(function(){ showToast('Server error.', true); });
}

function submitDeclineReason() {
  var id = $('#adm_decline_id').val();
  var action = $('#adm_decline_action').val();
  var reason = $('#adm_decline_reason').val().trim();
  var overrideReason = $('#adm_override_reason').val().trim();
  if (!reason) { showToast('A reason is required to decline.', true); return; }
  if ($('#adm_override_wrap').is(':visible') && !overrideReason) { showToast('A justification is required to override L1.', true); return; }
  $.post(window.location.pathname, { ajax_admin_set_status: 1, id: id, action: action, reason: reason, override_reason: overrideReason }, function(resp) {
    if (resp.success) { $('#admDeclineModal').modal('hide'); showToast(resp.message); loadAdminList(); }
    else showToast(resp.message || 'Action failed.', true);
  }, 'json').fail(function(){ showToast('Server error.', true); });
}

function adminDeleteVoucher(id) {
  if (!confirm('Delete this voucher? This cannot be undone.')) return;
  $.post(window.location.pathname, { ajax_admin_delete: 1, id: id }, function(resp) {
    if (resp.success) { showToast(resp.message); loadAdminList(); }
    else showToast(resp.message || 'Could not delete voucher.', true);
  }, 'json').fail(function(){ showToast('Server error.', true); });
}

function openSignatureModal() {
  $('#sig_file').val('');
  $('#sig_current_wrap').html('<div style="text-align:center;padding:20px;color:#94a3b8;"><i class="fas fa-spinner fa-spin"></i> Loading...</div>');
  $('#signatureModal').modal('show');
  $.getJSON(window.location.pathname, { ajax_admin_get_signature: 1 }, function(resp) {
    if (resp.success && resp.signature) {
      $('#sig_current_wrap').html(
        '<label>Current Signature</label>' +
        '<div style="border:2px solid #e2e8f0;border-radius:9px;padding:16px;text-align:center;background:#f8fafc;">' +
        '<img src="' + resp.signature.signature_path + '" style="max-height:80px;max-width:100%;">' +
        '<div style="font-size:11px;color:#94a3b8;margin-top:8px;">Uploaded by ' + escapeHtml(resp.signature.uploaded_by || '') + '</div></div>'
      );
    } else {
      $('#sig_current_wrap').html('<div style="text-align:center;padding:16px;color:#94a3b8;font-size:13px;">No signature uploaded yet.</div>');
    }
  });
}

function uploadSignature() {
  var fileInput = document.getElementById('sig_file');
  if (!fileInput.files.length) { showToast('Please choose a signature image.', true); return; }
  var fd = new FormData();
  fd.append('ajax_admin_upload_signature', '1');
  fd.append('signature_file', fileInput.files[0]);
  $.ajax({
    url: window.location.pathname, type: 'POST', data: fd, processData: false, contentType: false, dataType: 'json',
    success: function(resp) {
      if (resp.success) { showToast(resp.message); openSignatureModal(); }
      else showToast(resp.message || 'Could not upload signature.', true);
    },
    error: function(){ showToast('Server error while uploading signature.', true); }
  });
}
</script>
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
</body>
</html>