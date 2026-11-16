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

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');

// =========================================================================
// ADMIN CHECK FOR DASHBOARD BUTTON
// =========================================================================
$btn_currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$btn_authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$btn_isAdmin = false;
foreach($btn_authorized_admin_names as $admin_name) {
    if(stripos($btn_currentUserName, $admin_name) !== false || stripos($admin_name, $btn_currentUserName) !== false) {
        $btn_isAdmin = true;
        break;
    }
}
$dashboard_url = $btn_isAdmin ? 'index.php' : 'raise-a-ticket.php';

require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed: " . mysqli_connect_error());
mysqli_report(MYSQLI_REPORT_OFF);

mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page   = basename($_SERVER['PHP_SELF']);
$currentUser    = isset($_SESSION['user_name'])  ? trim($_SESSION['user_name'])  : 'HR';
$companyName    = isset($_SESSION['ge_cname'])   ? trim($_SESSION['ge_cname'])   : 'Company';

// =========================================================================
// AUTO-CREATE TABLES
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_candidate_tracking (
    id              INT(11) AUTO_INCREMENT PRIMARY KEY,
    department_id   INT(11) DEFAULT 0,
    position_id     INT(11) DEFAULT 0,
    department_name VARCHAR(255) DEFAULT '',
    position_name   VARCHAR(255) DEFAULT '',
    name            VARCHAR(255) NOT NULL,
    phone           VARCHAR(30)  NOT NULL,
    email           VARCHAR(255) DEFAULT '',
    resume_path     VARCHAR(500) DEFAULT '',
    resume_name     VARCHAR(255) DEFAULT '',
    jd_path         VARCHAR(500) DEFAULT '',
    jd_name         VARCHAR(255) DEFAULT '',
    current_status  VARCHAR(50)  DEFAULT 'New',
    trigger_datetime DATETIME    DEFAULT NULL,
    last_note       TEXT,
    last_updated_by VARCHAR(255) DEFAULT '',
    created_by      VARCHAR(255) DEFAULT '',
    created_at      DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_candidate_tracking_log (
    id              INT(11) AUTO_INCREMENT PRIMARY KEY,
    candidate_id    INT(11) NOT NULL,
    status          VARCHAR(50)  DEFAULT '',
    notes           TEXT,
    trigger_datetime DATETIME    DEFAULT NULL,
    updated_by      VARCHAR(255) DEFAULT '',
    updated_at      DATETIME     DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$src_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'candidate_source'");
if ($src_col_check && mysqli_num_rows($src_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN candidate_source VARCHAR(50) DEFAULT ''");
}
$loc_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'location'");
if ($loc_col_check && mysqli_num_rows($loc_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN location VARCHAR(255) DEFAULT ''");
}
$lang_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'language_known'");
if ($lang_col_check && mysqli_num_rows($lang_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN language_known VARCHAR(255) DEFAULT ''");
}
$upd_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'last_updated_by'");
if ($upd_col_check && mysqli_num_rows($upd_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN last_updated_by VARCHAR(255) DEFAULT ''");
}
$log_trig_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking_log LIKE 'trigger_datetime'");
if ($log_trig_check && mysqli_num_rows($log_trig_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking_log ADD COLUMN trigger_datetime DATETIME DEFAULT NULL");
}
$candidate_sources = ['Reference','Walk-in','Naukri','Apna','Indeed','LinkedIn','Other'];
$candidate_locations = ['Kasturi Nagar','Whitefield','Vasanth Nagar','Other'];
$candidate_languages = ['English','Hindi','Tamil','Telugu','Kannada','Malayalam','Bengali','Other'];

// Collapses the "Language Known" checkboxes (+ optional free-text "Other" languages)
// posted from either the Add or Edit form into one comma-separated string for storage.
function buildLanguageKnownString($checked, $otherRaw) {
    $parts = [];
    $checked = is_array($checked) ? $checked : [];
    foreach ($checked as $c) {
        $c = trim($c);
        if ($c === '' || $c === 'Other') continue;
        $parts[] = $c;
    }
    $otherRaw = trim($otherRaw ?? '');
    if ($otherRaw !== '') {
        foreach (explode(',', $otherRaw) as $custom) {
            $custom = trim($custom);
            if ($custom !== '') $parts[] = $custom;
        }
    }
    return implode(', ', $parts);
}

// Indexes for the columns the list filters on — the table only had its
// primary key before, so every filtered lookup was a full table scan.
// Self-healing like the column checks above; safe to run every load.
$ct_index_checks = [
    'current_status'  => null, // VARCHAR(50) — a 191-char prefix is longer than the column itself, which MySQL rejects
    'department_name' => 191, 'position_name' => 191,
    'created_by'       => 191, 'location' => 191,
    'created_at'       => null, 'trigger_datetime' => null,
];
foreach ($ct_index_checks as $ct_idx_col => $ct_idx_len) {
    $ct_idx_name = 'idx_' . $ct_idx_col;
    $ct_idx_chk = mysqli_query($con, "SHOW INDEX FROM hr_candidate_tracking WHERE Key_name='$ct_idx_name'");
    if ($ct_idx_chk && mysqli_num_rows($ct_idx_chk) == 0) {
        $ct_idx_expr = $ct_idx_len ? "$ct_idx_col($ct_idx_len)" : $ct_idx_col;
        mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD INDEX $ct_idx_name ($ct_idx_expr)");
    }
}

// Records which round a candidate was rejected at (e.g. "Round 2: Manager Round", or "Overall")
// so the tracking table can label rejections instead of just showing a bare "Rejected" status.
$rejround_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'rejected_round'");
if ($rejround_col_check && mysqli_num_rows($rejround_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN rejected_round VARCHAR(255) DEFAULT NULL");
}

// Permanent rejection log — shared with hr_screening.php / hr-rejected-candidates.php.
// Created here too in case this page is used to reject a candidate before hr_screening.php
// has ever run and created this table.
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_rejection_log (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) DEFAULT NULL,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    company_id int(11) DEFAULT NULL,
    round_number int(11) DEFAULT 0,
    round_name varchar(255) DEFAULT 'Overall',
    round_type varchar(30) DEFAULT 'overall',
    reason text NOT NULL,
    rejected_by varchar(255) DEFAULT NULL,
    kept_in_database tinyint(1) DEFAULT 1,
    resume_filename varchar(500) DEFAULT NULL,
    resume_path varchar(500) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$rl_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_rejection_log LIKE 'rejection_source'");
if ($rl_col_check && mysqli_num_rows($rl_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_rejection_log ADD COLUMN rejection_source VARCHAR(30) DEFAULT 'hr_screening'");
}

// Message templates for WhatsApp / Email notifications
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_message_templates (
    id          INT(11) AUTO_INCREMENT PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    statuses    VARCHAR(500) DEFAULT 'General',
    body        TEXT NOT NULL,
    created_by  VARCHAR(255) DEFAULT '',
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// SEED EXAMPLE TEMPLATE IF EMPTY
$check_tpl = mysqli_query($con, "SELECT id FROM hr_message_templates LIMIT 1");
if ($check_tpl && mysqli_num_rows($check_tpl) == 0) {
    $seed_title = mysqli_real_escape_string($con, "Interview Scheduled Reminder");
    $seed_statuses = mysqli_real_escape_string($con, "Scheduled");
    $seed_body = mysqli_real_escape_string($con, "Hi {name},\n\nGreetings from {company}!\n\nThis is a friendly reminder that your interview for the {position} role in our {department} department is confirmed.\n\n📅 Date: {date}\n⏰ Time: {time}\n\nPlease ensure you are available at the scheduled time. If you need to reschedule or have any questions, you can reach out to us at {phone}. \n\nWe look forward to speaking with you!\n\nBest regards,\n{sender}\nHR Team, {company}");
    mysqli_query($con, "INSERT INTO hr_message_templates (title, statuses, body, created_by) VALUES ('$seed_title', '$seed_statuses', '$seed_body', 'System')");
}

// Upload directory
$upload_dir = 'uploads/candidate_tracking/';
if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);

// Statuses that show the trigger date/time field
$trigger_statuses = ['Scheduled', 'Follow Up', 'Interested', 'Call Later', 'Callback', 'Round 1', 'Round 2', 'Round 3', 'Round 4', 'Round 5'];
// Statuses where the trigger date/time is MANDATORY. "Interested" is deliberately excluded —
// a candidate can be Interested without an interview being scheduled yet (e.g. salary mismatch).
$trigger_required_statuses = ['Scheduled', 'Follow Up', 'Call Later', 'Callback', 'Round 1', 'Round 2', 'Round 3', 'Round 4', 'Round 5'];

$all_statuses = ['New','Called','Interested','Not Interested','Candidate did not answer the call','Candidate disconnected the call','Call Later','Callback','Scheduled','Follow Up','Round 1','Round 2','Round 3','Round 4','Round 5','No Response','Rejected','Hired'];

// Status badge colour map
$status_colors = [
    'New'           => '#6366f1',
    'Called'        => '#3b82f6',
    'Interested'    => '#10b981',
    'Not Interested'=> '#ef4444',
    'Candidate did not answer the call'   => '#fb923c',
    'Candidate disconnected the call'=> '#e11d48',
    'Call Later'    => '#f59e0b',
    'Callback'      => '#f97316',
    'Scheduled'     => '#8b5cf6',
    'Follow Up'     => '#06b6d4',
    'Round 1'       => '#0ea5e9',
    'Round 2'       => '#3b82f6',
    'Round 3'       => '#6366f1',
    'Round 4'       => '#8b5cf6',
    'Round 5'       => '#a855f7',
    'No Response'   => '#94a3b8',
    'Rejected'      => '#dc2626',
    'Hired'         => '#059669',
];

// Custom statuses added by HR (global — visible to everyone, managed via "Manage Statuses")
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_candidate_status_types (
    id          INT(11) AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    created_by  VARCHAR(255) DEFAULT '',
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$custom_statuses = [];
$cst_res = mysqli_query($con, "SELECT name FROM hr_candidate_status_types ORDER BY name ASC");
if ($cst_res) { while ($cst_row = mysqli_fetch_assoc($cst_res)) { $custom_statuses[] = $cst_row['name']; } }

// Custom statuses sit alongside Round 1-5 etc., right before the terminal outcomes (Rejected/Hired)
array_splice($all_statuses, array_search('Rejected', $all_statuses), 0, $custom_statuses);

// The Schedule Date & Time field is available for custom statuses but never mandatory (same as "Interested")
$trigger_statuses = array_merge($trigger_statuses, $custom_statuses);

// =========================================================================
// HELPER: UPLOAD FILE
// =========================================================================
function uploadCandidateFile($file_key, $candidate_id, $type) {
    global $upload_dir;
    if (!isset($_FILES[$file_key]) || $_FILES[$file_key]['error'] !== UPLOAD_ERR_OK) return ['path'=>'','name'=>''];
    $original  = basename($_FILES[$file_key]['name']);
    $ext       = strtolower(pathinfo($original, PATHINFO_EXTENSION));
    $allowed   = ['pdf','doc','docx','png','jpg','jpeg'];
    if (!in_array($ext, $allowed)) return ['path'=>'','name'=>''];
    $safe_name = $type . '_' . $candidate_id . '_' . time() . '.' . $ext;
    $dest      = $upload_dir . $safe_name;
    if (move_uploaded_file($_FILES[$file_key]['tmp_name'], $dest)) {
        return ['path' => $dest, 'name' => $original];
    }
    return ['path'=>'','name'=>''];
}

// =========================================================================
// AJAX: GET POSITIONS
// =========================================================================
// =========================================================================
// SHARED FILTER-TO-SQL BUILDER — used by both the paginated list query below
// and the CSV export handler, so the two can never drift out of sync (export
// always matches exactly what the current filters show, just without the
// page LIMIT).
// =========================================================================
function buildCandidateTrackingWhere($con) {
    $where = [];

    $search = trim($_GET['search'] ?? '');
    if ($search !== '') {
        $s = mysqli_real_escape_string($con, $search);
        $where[] = "(name LIKE '%$s%' OR phone LIKE '%$s%' OR department_name LIKE '%$s%' OR position_name LIKE '%$s%' OR email LIKE '%$s%' OR current_status LIKE '%$s%' OR candidate_source LIKE '%$s%' OR location LIKE '%$s%' OR last_note LIKE '%$s%' OR created_by LIKE '%$s%')";
    }

    $status = trim($_GET['status'] ?? '');
    if ($status !== '') {
        $where[] = "current_status = '" . mysqli_real_escape_string($con, $status) . "'";
    }

    // Matches a row if EITHER created_at OR trigger_datetime falls within the
    // chosen range — same semantics the old client-side filter used.
    $date_from = trim($_GET['date_from'] ?? '');
    $date_to   = trim($_GET['date_to'] ?? '');
    if ($date_from !== '' || $date_to !== '') {
        $c_cond = "1=1";
        $t_cond = "trigger_datetime IS NOT NULL";
        if ($date_from !== '') {
            $df = mysqli_real_escape_string($con, $date_from);
            $c_cond .= " AND DATE(created_at) >= '$df'";
            $t_cond .= " AND DATE(trigger_datetime) >= '$df'";
        }
        if ($date_to !== '') {
            $dt = mysqli_real_escape_string($con, $date_to);
            $c_cond .= " AND DATE(created_at) <= '$dt'";
            $t_cond .= " AND DATE(trigger_datetime) <= '$dt'";
        }
        $where[] = "(($c_cond) OR ($t_cond))";
    }

    $added_by = trim($_GET['added_by'] ?? '');
    if ($added_by !== '') {
        $where[] = "LOWER(created_by) = '" . mysqli_real_escape_string($con, strtolower($added_by)) . "'";
    }
    $location = trim($_GET['location'] ?? '');
    if ($location !== '') {
        $where[] = "LOWER(location) = '" . mysqli_real_escape_string($con, strtolower($location)) . "'";
    }
    $department = trim($_GET['department'] ?? '');
    if ($department !== '') {
        $where[] = "LOWER(department_name) = '" . mysqli_real_escape_string($con, strtolower($department)) . "'";
    }
    $position = trim($_GET['position'] ?? '');
    if ($position !== '') {
        $where[] = "LOWER(position_name) = '" . mysqli_real_escape_string($con, strtolower($position)) . "'";
    }

    return !empty($where) ? ('WHERE ' . implode(' AND ', $where)) : '';
}

// =========================================================================
// CSV EXPORT — streams every row matching the current filters (not just the
// current page), generated server-side instead of scraping already-rendered
// DOM rows, so it works correctly now that the table is paginated.
// =========================================================================
if (isset($_GET['download_sample_csv'])) {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=Candidate_Import_Sample.csv');
    $out = fopen('php://output', 'w');
    fwrite($out, chr(0xEF) . chr(0xBB) . chr(0xBF)); // UTF-8 BOM so Excel renders it properly
    fputcsv($out, ['Candidate Name*', 'Phone*', 'Email', 'Department', 'Position', 'Source', 'Location', 'Language Known', 'Status', 'Schedule Date & Time', 'Notes']);
    
    // Sample candidate rows demonstrating required fields (Name, Phone) and optional fields
    fputcsv($out, ['Rahul Sharma', '9876543210', 'rahul.sharma@example.com', 'Engineering', 'Software Engineer', 'Naukri', 'Whitefield', 'English, Hindi, Kannada', 'Interview Scheduled', date('Y-m-d 14:30', strtotime('+2 days')), 'Strong experience in backend PHP & MySQL']);
    fputcsv($out, ['Priya Patel', '9812345678', 'priya.p@example.com', 'Human Resources', 'HR Executive', 'LinkedIn', 'Kasturi Nagar', 'English, Tamil', 'Call Not Answered', '', 'Will follow up tomorrow morning']);
    fputcsv($out, ['Amit Kumar', '9700012345', '', '', '', 'Walk-in', 'Vasanth Nagar', 'Hindi, English', 'New', '', 'Met at office walk-in drive']);
    
    fclose($out);
    exit;
}

if (isset($_GET['export_csv'])) {
    $ct_where_sql = buildCandidateTrackingWhere($con);
    $res = mysqli_query($con, "SELECT * FROM hr_candidate_tracking $ct_where_sql ORDER BY id DESC");
    $total_rows = $res ? mysqli_num_rows($res) : 0;

    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=Candidate_Tracking_' . date('Y-m-d') . '.csv');
    $out = fopen('php://output', 'w');
    fwrite($out, chr(0xEF) . chr(0xBB) . chr(0xBF)); // UTF-8 BOM so Excel renders it correctly
    fputcsv($out, ['#','Name','Phone','Email','Department','Position','Source','Location','Language Known','Status','Trigger Date/Time','Last Note','Added By','Last Updated By']);
    $i = 0;
    while ($row = mysqli_fetch_assoc($res)) {
        $i++;
        fputcsv($out, [
            $total_rows - $i + 1,
            $row['name'], $row['phone'], $row['email'] ?? '', $row['department_name'], $row['position_name'],
            $row['candidate_source'] ?? '', $row['location'] ?? '', $row['language_known'] ?? '', $row['current_status'],
            $row['trigger_datetime'] ? date('d M Y, h:i A', strtotime($row['trigger_datetime'])) : '',
            $row['last_note'] ?? '', $row['created_by'], $row['last_updated_by']
        ]);
    }
    fclose($out);
    exit;
}

if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $rows = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// =========================================================================
// AJAX: GET CANDIDATE DETAILS (for view modal)
// =========================================================================
if (isset($_GET['get_candidate'])) {
    header('Content-Type: application/json');
    $id  = intval($_GET['id']);
    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
    echo json_encode($row ?: []); exit;
}

// =========================================================================
// AJAX: CHECK DUPLICATE (phone/email) BEFORE ADDING
// =========================================================================
if (isset($_GET['check_duplicate'])) {
    header('Content-Type: application/json');
    $phone = mysqli_real_escape_string($con, trim($_GET['phone'] ?? ''));
    $email = mysqli_real_escape_string($con, trim($_GET['email'] ?? ''));
    $dept  = mysqli_real_escape_string($con, trim($_GET['dept'] ?? ''));
    $pos   = mysqli_real_escape_string($con, trim($_GET['pos'] ?? ''));
    
    $result = ['duplicate' => false];
    if ($phone || $email) {
        $cond = [];
        if ($phone) {
             $phone_digits = preg_replace('/\D/', '', $phone);
             if ($phone_digits) $cond[] = "phone LIKE '%$phone_digits%'";
        }
        if ($email) $cond[] = "email='$email'";
        
        if (!empty($cond)) {
            $q_str = "SELECT id, name, current_status, department_name, position_name FROM hr_candidate_tracking WHERE (" . implode(' OR ', $cond) . ") ";
            if ($dept) $q_str .= " AND department_name='$dept'";
            if ($pos) $q_str .= " AND position_name='$pos'";
            $q_str .= " LIMIT 1";

            $q = mysqli_query($con, $q_str);
            if ($q && $row = mysqli_fetch_assoc($q)) {
                $result = ['duplicate' => true, 'name' => $row['name'], 'id' => $row['id'], 'status' => $row['current_status']];
            }
        }
    }
    echo json_encode($result); exit;
}

// =========================================================================
// AJAX: GET LOG
// =========================================================================
if (isset($_GET['get_log'])) {
    header('Content-Type: application/json');
    $id   = intval($_GET['id']);
    $logs = [];
    $q    = mysqli_query($con, "SELECT * FROM hr_candidate_tracking_log WHERE candidate_id=$id ORDER BY updated_at DESC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) $logs[] = $r;
    echo json_encode($logs); exit;
}

// =========================================================================
// AJAX: GET MESSAGE TEMPLATES
// =========================================================================
if (isset($_GET['get_templates'])) {
    header('Content-Type: application/json');
    $rows = [];
    $q = mysqli_query($con, "SELECT * FROM hr_message_templates ORDER BY title ASC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        $r['statuses'] = array_values(array_filter(array_map('trim', explode(',', $r['statuses']))));
        $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// =========================================================================
// AJAX: GET CUSTOM STATUSES
// =========================================================================
if (isset($_GET['get_custom_statuses'])) {
    header('Content-Type: application/json');
    $rows = [];
    $q = mysqli_query($con, "SELECT id, name FROM hr_candidate_status_types ORDER BY name ASC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) { $rows[] = $r; }
    echo json_encode($rows); exit;
}

// =========================================================================
// POST: ADD CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add_candidate') {
    $dept_id   = intval($_POST['department_id']);
    $pos_id    = intval($_POST['position_id']);
    $dept_name = mysqli_real_escape_string($con, trim($_POST['department_name'] ?? ''));
    $pos_name  = mysqli_real_escape_string($con, trim($_POST['position_name']   ?? ''));
    $name      = mysqli_real_escape_string($con, trim($_POST['name']));
    $phone     = mysqli_real_escape_string($con, trim($_POST['phone']));
    $email     = mysqli_real_escape_string($con, trim($_POST['email'] ?? ''));
    $created_by= mysqli_real_escape_string($con, $currentUser);

    if (empty($name) || empty($phone)) {
        $_SESSION['error_message'] = "Name and Phone are required.";
        header("Location: $current_page"); exit;
    }

    $src_select_raw = trim($_POST['candidate_source'] ?? '');
    $src_other_raw  = trim($_POST['candidate_source_other'] ?? '');
    $source_raw     = ($src_select_raw === 'Other' && $src_other_raw !== '') ? $src_other_raw : $src_select_raw;
    $source         = mysqli_real_escape_string($con, $source_raw);

    $loc_select_raw = trim($_POST['location_select'] ?? '');
    $loc_other_raw  = trim($_POST['location_other'] ?? '');
    $location_raw   = ($loc_select_raw === 'Other' && $loc_other_raw !== '') ? $loc_other_raw : $loc_select_raw;
    $location       = mysqli_real_escape_string($con, $location_raw);

    $language_raw = buildLanguageKnownString($_POST['language_known'] ?? [], $_POST['language_known_other'] ?? '');
    $language     = mysqli_real_escape_string($con, $language_raw);

    if (empty($_POST['confirm_duplicate'])) {
        $dup_check = mysqli_query($con, "SELECT id, name FROM hr_candidate_tracking WHERE phone='$phone'" . (!empty($email) ? " OR email='$email'" : "") . " LIMIT 1");
        if ($dup_check && mysqli_num_rows($dup_check) > 0) {
            $dup_row = mysqli_fetch_assoc($dup_check);
            $_SESSION['error_message'] = "A candidate with this phone/email already exists: " . htmlspecialchars($dup_row['name']) . " (ID #" . $dup_row['id'] . "). Use the 'Add anyway' checkbox if this is a different person.";
            header("Location: $current_page"); exit;
        }
    }

    mysqli_query($con, "INSERT INTO hr_candidate_tracking (department_id,position_id,department_name,position_name,name,phone,email,candidate_source,location,language_known,current_status,created_by,last_updated_by) VALUES ($dept_id,$pos_id,'$dept_name','$pos_name','$name','$phone','$email','$source','$location','$language','New','$created_by','$created_by')");
    $new_id = mysqli_insert_id($con);

    // Upload files
    $resume = uploadCandidateFile('resume', $new_id, 'resume');
    $jd     = uploadCandidateFile('jd',     $new_id, 'jd');

    if ($resume['path'] || $jd['path']) {
        $rp = mysqli_real_escape_string($con, $resume['path']);
        $rn = mysqli_real_escape_string($con, $resume['name']);
        $jp = mysqli_real_escape_string($con, $jd['path']);
        $jn = mysqli_real_escape_string($con, $jd['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET resume_path='$rp',resume_name='$rn',jd_path='$jp',jd_name='$jn' WHERE id=$new_id");
    }

    // Initial log entry
    mysqli_query($con, "INSERT INTO hr_candidate_tracking_log (candidate_id,status,notes,updated_by) VALUES ($new_id,'New','Candidate created.','$created_by')");

    $_SESSION['success_message'] = "Candidate added successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: EDIT CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'edit_candidate') {
    $id        = intval($_POST['id']);
    $dept_id   = intval($_POST['department_id']);
    $pos_id    = intval($_POST['position_id']);
    $dept_name = mysqli_real_escape_string($con, trim($_POST['department_name'] ?? ''));
    $pos_name  = mysqli_real_escape_string($con, trim($_POST['position_name']   ?? ''));
    $name      = mysqli_real_escape_string($con, trim($_POST['name']));
    $phone     = mysqli_real_escape_string($con, trim($_POST['phone']));
    $email     = mysqli_real_escape_string($con, trim($_POST['email'] ?? ''));

    $loc_select_raw = trim($_POST['location_select'] ?? '');
    $loc_other_raw  = trim($_POST['location_other'] ?? '');
    $location_raw   = ($loc_select_raw === 'Other' && $loc_other_raw !== '') ? $loc_other_raw : $loc_select_raw;
    $location       = mysqli_real_escape_string($con, $location_raw);

    $language_raw = buildLanguageKnownString($_POST['language_known'] ?? [], $_POST['language_known_other'] ?? '');
    $language     = mysqli_real_escape_string($con, $language_raw);

    if (empty($name) || empty($phone)) {
        $_SESSION['error_message'] = "Name and Phone are required.";
        header("Location: $current_page"); exit;
    }

    mysqli_query($con, "UPDATE hr_candidate_tracking SET department_id=$dept_id,position_id=$pos_id,department_name='$dept_name',position_name='$pos_name',name='$name',phone='$phone',email='$email',location='$location',language_known='$language' WHERE id=$id");

    // Handle new file uploads (only replace if new file uploaded)
    $resume = uploadCandidateFile('resume', $id, 'resume');
    $jd     = uploadCandidateFile('jd',     $id, 'jd');
    if ($resume['path']) {
        $rp = mysqli_real_escape_string($con, $resume['path']);
        $rn = mysqli_real_escape_string($con, $resume['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET resume_path='$rp',resume_name='$rn' WHERE id=$id");
    }
    if ($jd['path']) {
        $jp = mysqli_real_escape_string($con, $jd['path']);
        $jn = mysqli_real_escape_string($con, $jd['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET jd_path='$jp',jd_name='$jn' WHERE id=$id");
    }

    $_SESSION['success_message'] = "Candidate updated successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: UPDATE STATUS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'update_status') {
    $id              = intval($_POST['id']);
    $status          = mysqli_real_escape_string($con, $_POST['status']);
    $trigger_raw     = trim($_POST['trigger_datetime'] ?? '');
    $trigger_sql     = (!empty($trigger_raw)) ? "'" . mysqli_real_escape_string($con, $trigger_raw) . "'" : "NULL";
    $updated_by      = mysqli_real_escape_string($con, $currentUser);

    // ---- REJECTION requires a mandatory reason + round, same rules as hr_screening.php ----
    if ($_POST['status'] === 'Rejected') {
        $reject_reason_raw = trim($_POST['reject_reason'] ?? '');
        $reject_round_raw  = trim($_POST['reject_round'] ?? '');
        if ($reject_round_raw === '') $reject_round_raw = 'Overall';

        if ($reject_reason_raw === '') {
            $_SESSION['error_message'] = "A rejection reason is required.";
            header("Location: $current_page"); exit;
        }

        $cand_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
        if (!$cand_row) {
            $_SESSION['error_message'] = "Candidate not found.";
            header("Location: $current_page"); exit;
        }

        $reject_reason_esc = mysqli_real_escape_string($con, $reject_reason_raw);
        $reject_round_esc  = mysqli_real_escape_string($con, $reject_round_raw);
        $note_combined     = "Rejected at $reject_round_raw. Reason: $reject_reason_raw";
        $note_combined_esc = mysqli_real_escape_string($con, $note_combined);

        // Capture details BEFORE deleting the working row — needed for hr_rejection_log
        $cname_esc      = mysqli_real_escape_string($con, $cand_row['name']);
        $cemail_esc     = mysqli_real_escape_string($con, $cand_row['email']);
        $cphone_esc     = mysqli_real_escape_string($con, $cand_row['phone']);
        $pos_esc        = mysqli_real_escape_string($con, $cand_row['position_name']);
        $dept_esc       = mysqli_real_escape_string($con, $cand_row['department_name']);
        $screening_sql  = !empty($cand_row['screening_id']) ? intval($cand_row['screening_id']) : 'NULL';
        $resume_fn_esc  = mysqli_real_escape_string($con, $cand_row['resume_name'] ?? '');
        $resume_pt_esc  = mysqli_real_escape_string($con, $cand_row['resume_path'] ?? '');

        // 1) Write the PERMANENT rejection record first — this survives even after we delete the tracking row below
        mysqli_query($con, "INSERT INTO hr_rejection_log
            (screening_id, candidate_name, candidate_email, candidate_phone, position_applied, department,
             round_number, round_name, round_type, reason, rejected_by, kept_in_database, resume_filename, resume_path, rejection_source)
            VALUES
            ($screening_sql, '$cname_esc', '$cemail_esc', '$cphone_esc', '$pos_esc', '$dept_esc',
             0, '$reject_round_esc', 'overall', '$reject_reason_esc', '$updated_by', 1, '$resume_fn_esc', '$resume_pt_esc', 'candidate_tracking')");

        // 2) If this candidate is also tracked in hr_screenings, keep that record's decision in sync.
        if (!empty($cand_row['screening_id'])) {
            mysqli_query($con, "UPDATE hr_screenings SET hr_decision='rejected', screening_notes='$reject_reason_esc', updated_at=NOW() WHERE id=" . intval($cand_row['screening_id']));
        }

        // 3) Now that the rejection is permanently logged, remove the working row from
        //    hr_candidate_tracking entirely — this is what moves the candidate OUT of the
        //    tracking list and leaves them visible only on the Rejection Log page.
        if ($cand_row['resume_path'] && file_exists($cand_row['resume_path'])) @unlink($cand_row['resume_path']);
        if ($cand_row['jd_path']     && file_exists($cand_row['jd_path']))     @unlink($cand_row['jd_path']);
        mysqli_query($con, "DELETE FROM hr_candidate_tracking_log WHERE candidate_id=$id");
        mysqli_query($con, "DELETE FROM hr_candidate_tracking WHERE id=$id");

        $_SESSION['success_message'] = "Candidate rejected, logged, and removed from tracking.";
        header("Location: $current_page"); exit;
    }

    // ---- Normal (non-rejection) status update ----
    $notes_raw = trim($_POST['notes'] ?? '');
    if ($notes_raw === '') {
        $existing_note_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT last_note FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
        $notes_raw = $existing_note_row ? $existing_note_row['last_note'] : '';
    }
    $notes = mysqli_real_escape_string($con, $notes_raw);

    $language_raw = buildLanguageKnownString($_POST['language_known'] ?? [], $_POST['language_known_other'] ?? '');
    $language     = mysqli_real_escape_string($con, $language_raw);

    mysqli_query($con, "UPDATE hr_candidate_tracking SET current_status='$status',last_note='$notes',trigger_datetime=$trigger_sql,language_known='$language',last_updated_by='$updated_by' WHERE id=$id");
    mysqli_query($con, "INSERT INTO hr_candidate_tracking_log (candidate_id,status,notes,trigger_datetime,updated_by) VALUES ($id,'$status','$notes',$trigger_sql,'$updated_by')");

    $_SESSION['success_message'] = "Status and details updated successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: IMPORT CANDIDATES FROM CSV
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'import_candidates') {
    if (!isset($_FILES['csv_file']) || $_FILES['csv_file']['error'] !== UPLOAD_ERR_OK) {
        $_SESSION['error_message'] = "Please upload a valid CSV file.";
        header("Location: $current_page"); exit;
    }

    $fileTmp  = $_FILES['csv_file']['tmp_name'];
    $fileName = $_FILES['csv_file']['name'];
    $fileExt  = strtolower(pathinfo($fileName, PATHINFO_EXTENSION));

    if ($fileExt !== 'csv') {
        $_SESSION['error_message'] = "Only CSV format (.csv) is supported for import.";
        header("Location: $current_page"); exit;
    }

    $handle = fopen($fileTmp, "r");
    if (!$handle) {
        $_SESSION['error_message'] = "Failed to open uploaded CSV file.";
        header("Location: $current_page"); exit;
    }

    // Auto-detect delimiter (comma, semicolon, tab)
    $sampleLine = fgets($handle);
    $delimiters = [',', ';', "\t", '|'];
    $delimiter = ',';
    $maxCount = 0;
    foreach ($delimiters as $d) {
        $count = substr_count($sampleLine, $d);
        if ($count > $maxCount) {
            $maxCount = $count;
            $delimiter = $d;
        }
    }
    rewind($handle);

    // Read header row
    $header = fgetcsv($handle, 10000, $delimiter);
    if (!$header) {
        fclose($handle);
        $_SESSION['error_message'] = "Uploaded CSV file is empty.";
        header("Location: $current_page"); exit;
    }

    // Strip BOM from first column header if present
    if (isset($header[0])) {
        $header[0] = preg_replace('/^\xEF\xBB\xBF/', '', $header[0]);
        $header[0] = trim($header[0], "\xEF\xBB\xBF \t\n\r\0\x0B");
    }

    $headerMap = [];
    foreach ($header as $idx => $h) {
        $cleanH = strtolower(trim($h));
        $cleanH = preg_replace('/[^a-z0-9]/', '', $cleanH);
        if ($cleanH !== '') {
            $headerMap[$cleanH] = $idx;
        }
    }

    $getVal = function($row, $aliases, $fallbackIndex = -1) use ($headerMap) {
        foreach ($aliases as $alias) {
            $norm = strtolower(preg_replace('/[^a-z0-9]/', '', $alias));
            if (isset($headerMap[$norm]) && isset($row[$headerMap[$norm]])) {
                $val = trim($row[$headerMap[$norm]]);
                if ($val !== '') return $val;
            }
        }
        if ($fallbackIndex >= 0 && isset($row[$fallbackIndex])) {
            return trim($row[$fallbackIndex]);
        }
        return '';
    };

    // Pre-cache departments and positions for fast lookup
    $dept_cache = [];
    $dq = mysqli_query($con, "SELECT * FROM hr_departments");
    if ($dq) while ($dr = mysqli_fetch_assoc($dq)) {
        $d_name = $dr['name'] ?? ($dr['department_name'] ?? '');
        if ($d_name !== '') {
            $dept_cache[strtolower(trim($d_name))] = intval($dr['id']);
        }
    }

    $pos_cache = [];
    $pq = mysqli_query($con, "SELECT * FROM hr_positions");
    if ($pq) while ($pr = mysqli_fetch_assoc($pq)) {
        $p_title = $pr['title'] ?? ($pr['position_name'] ?? ($pr['name'] ?? ''));
        if ($p_title !== '') {
            $pos_cache[strtolower(trim($p_title))] = ['id' => intval($pr['id']), 'department_id' => intval($pr['department_id'] ?? 0)];
        }
    }

    $total_rows   = 0;
    $imported     = [];
    $skipped      = [];
    $currentUserE = mysqli_real_escape_string($con, $currentUser);

    while (($row = fgetcsv($handle, 10000, $delimiter)) !== false) {
        // Skip entirely empty rows
        if (empty(array_filter($row, function($v) { return trim($v) !== ''; }))) {
            continue;
        }

        $total_rows++;
        $rowNum = $total_rows + 1; // 1-based row index including header

        $name       = $getVal($row, ['Candidate Name', 'Name', 'candidatename', 'full name', 'candidate'], 0);
        $phone      = $getVal($row, ['Phone', 'Phone Number', 'Mobile', 'Contact', 'telephone', 'phonenumber'], 1);
        $email      = $getVal($row, ['Email', 'Email Address', 'Mail', 'emailid'], 2);
        $dept_name  = $getVal($row, ['Department', 'Department Name', 'dept'], 3);
        $pos_name   = $getVal($row, ['Position', 'Position Applied', 'Job Title', 'Role', 'designation'], 4);
        $source     = $getVal($row, ['Source', 'Candidate Source', 'candidatesource'], 5);
        $location   = $getVal($row, ['Location', 'recruiting location', 'city'], 6);
        $languages  = $getVal($row, ['Language Known', 'Languages', 'Language', 'languages known', 'languagesknown'], 7);
        $status     = $getVal($row, ['Status', 'Current Status', 'currentstatus'], 8);
        $trigger_dt = $getVal($row, ['Schedule Date & Time', 'Trigger Date/Time', 'Schedule Date', 'Trigger Datetime', 'Date & Time', 'Scheduled Time', 'scheduledate'], 9);
        $notes      = $getVal($row, ['Notes', 'Remarks', 'Last Note', 'Comment', 'lastnote'], 10);

        // Clean phone digits for duplicate check
        $clean_phone = preg_replace('/[^0-9]/', '', $phone);
        $phone_last10 = (strlen($clean_phone) > 10) ? substr($clean_phone, -10) : $clean_phone;

        // 1. Validation: Required fields (Only Name and Phone are mandatory; Department & Position are optional)
        $missing = [];
        if ($name === '') $missing[] = 'Candidate Name';
        if ($phone === '') $missing[] = 'Phone';

        if (!empty($missing)) {
            $skipped[] = [
                'row'    => $rowNum,
                'name'   => $name ?: '(Empty Name)',
                'phone'  => $phone ?: '-',
                'email'  => $email ?: '-',
                'dept'   => $dept_name ?: '-',
                'pos'    => $pos_name ?: '-',
                'reason' => 'Missing required field(s): ' . implode(', ', $missing)
            ];
            continue;
        }

        // 2. Duplicate Detection: Check against hr_candidate_tracking by Phone (last 10 digits) or Email
        $dup_where = [];
        if (!empty($phone_last10)) {
            $dup_where[] = "phone LIKE '%" . mysqli_real_escape_string($con, $phone_last10) . "%'";
        }
        if (!empty($email)) {
            $dup_where[] = "email = '" . mysqli_real_escape_string($con, $email) . "'";
        }

        $is_duplicate = false;
        $dup_details = null;
        if (!empty($dup_where)) {
            $dup_sql = "SELECT id, name, phone, email, department_name, position_name, current_status FROM hr_candidate_tracking WHERE " . implode(' OR ', $dup_where) . " LIMIT 1";
            $dup_res = mysqli_query($con, $dup_sql);
            if ($dup_res && mysqli_num_rows($dup_res) > 0) {
                $is_duplicate = true;
                $dup_details = mysqli_fetch_assoc($dup_res);
            }
        }

        if ($is_duplicate) {
            $matched_by = [];
            if (!empty($phone_last10) && strpos(preg_replace('/[^0-9]/', '', $dup_details['phone']), $phone_last10) !== false) {
                $matched_by[] = "Phone (" . $dup_details['phone'] . ")";
            }
            if (!empty($email) && strtolower($dup_details['email']) === strtolower($email)) {
                $matched_by[] = "Email (" . $dup_details['email'] . ")";
            }
            $match_str = !empty($matched_by) ? implode(' & ', $matched_by) : 'Phone/Email';

            $skipped[] = [
                'row'    => $rowNum,
                'name'   => $name,
                'phone'  => $phone,
                'email'  => $email ?: '-',
                'dept'   => $dept_name,
                'pos'    => $pos_name,
                'reason' => "Duplicate: Candidate and details already exist in the system (Matched by $match_str: Existing '" . $dup_details['name'] . "', Department: " . $dup_details['department_name'] . ", Status: " . $dup_details['current_status'] . ")"
            ];
            continue;
        }

        // 3. Resolve department and position IDs
        $dept_id = 0;
        $dept_key = strtolower($dept_name);
        if (isset($dept_cache[$dept_key])) {
            $dept_id = $dept_cache[$dept_key];
        }

        $pos_id = 0;
        $pos_key = strtolower($pos_name);
        if (isset($pos_cache[$pos_key])) {
            $pos_id = $pos_cache[$pos_key]['id'];
            if ($dept_id === 0 && !empty($pos_cache[$pos_key]['department_id'])) {
                $dept_id = $pos_cache[$pos_key]['department_id'];
            }
        }

        // 4. Default values for optional fields
        if ($status === '' || !in_array($status, $all_statuses)) {
            $status = 'New';
        }
        if ($source === '') $source = 'Other';
        if ($location === '') $location = 'Other';

        $trigger_sql = "NULL";
        if (!empty($trigger_dt)) {
            $parsed_time = strtotime($trigger_dt);
            if ($parsed_time) {
                $trigger_sql = "'" . date('Y-m-d H:i:s', $parsed_time) . "'";
            }
        }

        $name_esc     = mysqli_real_escape_string($con, $name);
        $phone_esc    = mysqli_real_escape_string($con, $phone);
        $email_esc    = mysqli_real_escape_string($con, $email);
        $dept_esc     = mysqli_real_escape_string($con, $dept_name);
        $pos_esc      = mysqli_real_escape_string($con, $pos_name);
        $source_esc   = mysqli_real_escape_string($con, $source);
        $location_esc = mysqli_real_escape_string($con, $location);
        $lang_esc     = mysqli_real_escape_string($con, $languages);
        $status_esc   = mysqli_real_escape_string($con, $status);
        $notes_esc    = mysqli_real_escape_string($con, $notes);

        $insert_q = "INSERT INTO hr_candidate_tracking
            (department_id, position_id, department_name, position_name, name, phone, email, candidate_source, location, language_known, current_status, trigger_datetime, last_note, created_by, last_updated_by)
            VALUES
            ($dept_id, $pos_id, '$dept_esc', '$pos_esc', '$name_esc', '$phone_esc', '$email_esc', '$source_esc', '$location_esc', '$lang_esc', '$status_esc', $trigger_sql, '$notes_esc', '$currentUserE', '$currentUserE')";

        if (mysqli_query($con, $insert_q)) {
            $new_id = mysqli_insert_id($con);
            mysqli_query($con, "INSERT INTO hr_candidate_tracking_log (candidate_id, status, notes, trigger_datetime, updated_by) VALUES ($new_id, '$status_esc', '$notes_esc', $trigger_sql, '$currentUserE')");
            $imported[] = [
                'name'  => $name,
                'phone' => $phone,
                'dept'  => $dept_name,
                'pos'   => $pos_name
            ];
        } else {
            $skipped[] = [
                'row'    => $rowNum,
                'name'   => $name,
                'phone'  => $phone,
                'email'  => $email ?: '-',
                'dept'   => $dept_name,
                'pos'    => $pos_name,
                'reason' => 'Database error: ' . mysqli_error($con)
            ];
        }
    }
    fclose($handle);

    $_SESSION['import_results'] = [
        'total'          => $total_rows,
        'imported_count' => count($imported),
        'skipped_count'  => count($skipped),
        'imported'       => $imported,
        'skipped'        => $skipped
    ];

    $n_imp = count($imported);
    $n_skp = count($skipped);
    if ($n_imp > 0 && $n_skp === 0) {
        $_SESSION['success_message'] = "Successfully imported $n_imp candidate(s).";
    } elseif ($n_imp > 0 && $n_skp > 0) {
        $_SESSION['success_message'] = "Import completed: $n_imp candidate(s) imported, $n_skp skipped/duplicate.";
    } else {
        $_SESSION['error_message'] = "Import completed: 0 imported, $n_skp row(s) skipped/already exist as duplicates.";
    }

    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: DELETE CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_candidate') {
    $id  = intval($_POST['id']);
    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT resume_path,jd_path FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
    if ($row) {
        if ($row['resume_path'] && file_exists($row['resume_path'])) unlink($row['resume_path']);
        if ($row['jd_path']     && file_exists($row['jd_path']))     unlink($row['jd_path']);
    }
    mysqli_query($con, "DELETE FROM hr_candidate_tracking_log WHERE candidate_id=$id");
    mysqli_query($con, "DELETE FROM hr_candidate_tracking WHERE id=$id");
    $_SESSION['success_message'] = "Candidate deleted.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: SAVE MESSAGE TEMPLATE (add or edit)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'save_template') {
    header('Content-Type: application/json');
    $tid       = intval($_POST['id'] ?? 0);
    $title     = trim($_POST['title'] ?? '');
    $body      = trim($_POST['body'] ?? '');
    $statuses  = isset($_POST['statuses']) && is_array($_POST['statuses']) ? $_POST['statuses'] : [];
    if (empty($statuses)) $statuses = ['General'];
    $statuses_str = mysqli_real_escape_string($con, implode(',', $statuses));
    $title_esc = mysqli_real_escape_string($con, $title);
    $body_esc  = mysqli_real_escape_string($con, $body);
    $by_esc    = mysqli_real_escape_string($con, $currentUser);

    if ($title === '' || $body === '') {
        echo json_encode(['success' => false, 'error' => 'Title and message body are required.']); exit;
    }

    if ($tid > 0) {
        mysqli_query($con, "UPDATE hr_message_templates SET title='$title_esc', statuses='$statuses_str', body='$body_esc' WHERE id=$tid");
    } else {
        mysqli_query($con, "INSERT INTO hr_message_templates (title, statuses, body, created_by) VALUES ('$title_esc','$statuses_str','$body_esc','$by_esc')");
        $tid = mysqli_insert_id($con);
    }
    echo json_encode(['success' => true, 'id' => $tid]); exit;
}

// =========================================================================
// POST: DELETE MESSAGE TEMPLATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_template') {
    header('Content-Type: application/json');
    $tid = intval($_POST['id'] ?? 0);
    mysqli_query($con, "DELETE FROM hr_message_templates WHERE id=$tid");
    echo json_encode(['success' => true]); exit;
}

// =========================================================================
// POST: ADD CUSTOM STATUS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add_custom_status') {
    header('Content-Type: application/json');
    $status_name = mb_substr(trim($_POST['name'] ?? ''), 0, 100);

    if ($status_name === '') {
        echo json_encode(['success' => false, 'error' => 'Status name is required.']); exit;
    }
    if (in_array(strtolower($status_name), array_map('strtolower', $all_statuses))) {
        echo json_encode(['success' => false, 'error' => 'This status already exists.']); exit;
    }

    $name_esc = mysqli_real_escape_string($con, $status_name);
    $by_esc   = mysqli_real_escape_string($con, $currentUser);
    mysqli_query($con, "INSERT INTO hr_candidate_status_types (name, created_by) VALUES ('$name_esc', '$by_esc')");
    echo json_encode(['success' => true]); exit;
}

// =========================================================================
// POST: DELETE CUSTOM STATUS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_custom_status') {
    header('Content-Type: application/json');
    $stid = intval($_POST['id'] ?? 0);
    mysqli_query($con, "DELETE FROM hr_candidate_status_types WHERE id=$stid");
    echo json_encode(['success' => true]); exit;
}

// =========================================================================
// FETCH DATA
// =========================================================================
$departments_arr = [];
$dq = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
while ($d = mysqli_fetch_assoc($dq)) $departments_arr[] = $d;

// Was previously "SELECT * ... ORDER BY id DESC" with no LIMIT — fetched and
// rendered the ENTIRE table on every load regardless of filters, which is
// what made the page progressively slower as candidates were added. Now
// filtered and paginated at the SQL level, so only the rows actually shown
// are ever fetched or turned into HTML.
$ct_where_sql  = buildCandidateTrackingWhere($con);
$ct_page_size  = 50;
$ct_page       = max(1, intval($_GET['page'] ?? 1));

$ct_total = 0;
$ct_count_res = mysqli_query($con, "SELECT COUNT(*) as c FROM hr_candidate_tracking $ct_where_sql");
if ($ct_count_res) $ct_total = intval(mysqli_fetch_assoc($ct_count_res)['c']);

$ct_max_page = max(1, (int)ceil($ct_total / $ct_page_size));
if ($ct_page > $ct_max_page) $ct_page = $ct_max_page;
$ct_offset = ($ct_page - 1) * $ct_page_size;
$ct_start  = $ct_total === 0 ? 0 : $ct_offset + 1;
$ct_end    = min($ct_offset + $ct_page_size, $ct_total);

$candidates = [];
$cq = mysqli_query($con, "SELECT * FROM hr_candidate_tracking $ct_where_sql ORDER BY id DESC LIMIT $ct_page_size OFFSET $ct_offset");
while ($c = mysqli_fetch_assoc($cq)) $candidates[] = $c;

// Current filter values, echoed back into the filter bar's inputs below so
// they stay visually selected after a reload (filters now trigger a real
// page navigation instead of pure client-side JS).
$ct_f_search   = htmlspecialchars(trim($_GET['search'] ?? ''), ENT_QUOTES);
$ct_f_status   = trim($_GET['status'] ?? '');
$ct_f_datefrom = htmlspecialchars(trim($_GET['date_from'] ?? ''), ENT_QUOTES);
$ct_f_dateto   = htmlspecialchars(trim($_GET['date_to'] ?? ''), ENT_QUOTES);
$ct_f_addedby  = trim($_GET['added_by'] ?? '');
$ct_f_location = trim($_GET['location'] ?? '');
$ct_f_dept     = trim($_GET['department'] ?? '');
$ct_f_pos      = trim($_GET['position'] ?? '');

$added_by_list = [];
$abq = mysqli_query($con, "SELECT DISTINCT created_by FROM hr_candidate_tracking WHERE created_by <> '' ORDER BY created_by ASC");
while ($abr = mysqli_fetch_assoc($abq)) $added_by_list[] = $abr['created_by'];

// Filter dropdown source lists — only values actually used by existing candidates,
// same approach as $added_by_list above.
$filter_dept_list = [];
$fdq = mysqli_query($con, "SELECT DISTINCT department_name FROM hr_candidate_tracking WHERE department_name <> '' ORDER BY department_name ASC");
while ($fdr = mysqli_fetch_assoc($fdq)) $filter_dept_list[] = $fdr['department_name'];

$filter_pos_list = [];
$fpq = mysqli_query($con, "SELECT DISTINCT position_name FROM hr_candidate_tracking WHERE position_name <> '' ORDER BY position_name ASC");
while ($fpr = mysqli_fetch_assoc($fpq)) $filter_pos_list[] = $fpr['position_name'];


// Full list (overdue + today + tomorrow) — used to populate the popup, which then
// defaults its own view to today via the date filter JS already applies.
$tomorrow_end   = date('Y-m-d 23:59:59', strtotime('+1 day'));
$alert_candidates = [];
$aq = mysqli_query($con, "SELECT * FROM hr_candidate_tracking
    WHERE trigger_datetime IS NOT NULL
      AND trigger_datetime <= '$tomorrow_end'
      AND current_status NOT IN ('Rejected','Hired','No Response','Not Interested')
    ORDER BY trigger_datetime ASC");
while ($a = mysqli_fetch_assoc($aq)) $alert_candidates[] = $a;

// Today-only count — this is what the top banner badge shows
$today_start = date('Y-m-d 00:00:00');
$today_end   = date('Y-m-d 23:59:59');
$today_count = 0;
$atq = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_candidate_tracking
    WHERE trigger_datetime IS NOT NULL
      AND trigger_datetime BETWEEN '$today_start' AND '$today_end'
      AND current_status NOT IN ('Rejected','Hired','No Response','Not Interested')");
if ($atq) { $today_row = mysqli_fetch_assoc($atq); $today_count = intval($today_row['cnt']); }


?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?php echo htmlspecialchars($companyName); ?> | HR Candidate Tracking</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>

<style>
:root {
    --primary:    #1e3a8a;
    --primary-lt: #1e40af;
    --accent:     #6366f1;
    --success:    #10b981;
    --danger:     #ef4444;
    --warning:    #f59e0b;
    --bg:         #f1f5f9;
    --card:       #ffffff;
    --border:     #e2e8f0;
    --text:       #1e293b;
    --muted:      #64748b;
}

* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Inter',sans-serif; background:var(--bg); min-height:100vh; color:var(--text); }
html.modal-open { overflow:hidden; }

/* ── Layout ── */
.page-wrap { max-width:1600px; margin:0 auto; padding:24px 20px; }

/* ── Header ── */
.page-header {
    background: linear-gradient(135deg, var(--primary) 0%, var(--primary-lt) 100%);
    padding:22px 30px; border-radius:14px;
    box-shadow:0 4px 20px rgba(30,58,138,.25);
    display:flex; justify-content:space-between; align-items:center;
    margin-bottom:22px;
}
.page-header h1 { color:#fff; font-weight:700; font-size:1.6rem; margin:0; }
.page-header .back-btn {
    background:rgba(255,255,255,.15); color:#fff; border:2px solid rgba(255,255,255,.3);
    padding:9px 20px; border-radius:9px; font-weight:600; text-decoration:none;
    transition:.2s;
}
.page-header .back-btn:hover { background:rgba(255,255,255,.25); color:#fff; text-decoration:none; }

/* ── Alert Banner ── */
.alert-banner {
    background:linear-gradient(135deg,#f97316,#ea580c);
    border-radius:12px; padding:14px 22px;
    display:flex; align-items:center; gap:14px;
    color:#fff; font-weight:600; margin-bottom:22px;
    cursor:pointer; box-shadow:0 4px 14px rgba(249,115,22,.35);
    animation: gentlePulse 2.5s infinite;
}
@keyframes gentlePulse { 0%,100%{opacity:1} 50%{opacity:.85} }
.alert-banner i { font-size:1.3rem; }
.alert-banner .count-pill {
    background:rgba(255,255,255,.25); border-radius:20px;
    padding:3px 12px; font-size:.85rem;
}

/* ── Action bar ── */
.action-bar {
    background:var(--card); border-radius:12px;
    padding:18px 22px; margin-bottom:20px;
    display:flex; gap:12px; align-items:center; flex-wrap:wrap;
    box-shadow:0 2px 10px rgba(0,0,0,.07);
}
.btn-primary-custom {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; border:none; padding:11px 24px; border-radius:10px;
    font-weight:700; font-size:14px; cursor:pointer;
    display:inline-flex; align-items:center; gap:8px;
    transition:.25s; box-shadow:0 3px 12px rgba(30,58,138,.28);
}
.btn-primary-custom:hover { transform:translateY(-2px); box-shadow:0 6px 20px rgba(30,58,138,.4); }

/* ── Search bar ── */
.search-wrap { flex:1; min-width:220px; position:relative; }
.search-wrap input {
    width:100%; padding:11px 16px 11px 42px;
    border:2px solid var(--border); border-radius:10px;
    font-size:14px; font-weight:500; color:var(--text);
    transition:.2s;
}
.search-wrap input:focus { outline:none; border-color:var(--primary-lt); }
.search-wrap i { position:absolute; left:14px; top:50%; transform:translateY(-50%); color:var(--muted); }

/* ── Table card ── */
.table-card {
    background:var(--card); border-radius:14px;
    box-shadow:0 2px 12px rgba(0,0,0,.08);
    overflow:hidden;
}
.table-card-header {
    padding:18px 22px; border-bottom:2px solid var(--border);
    display:flex; justify-content:space-between; align-items:center;
}
.table-card-header h5 { font-weight:700; color:var(--primary); margin:0; }
.table-scroll { overflow-x:auto; overflow-y:auto; max-height:68vh; cursor:grab; }
.table-scroll:active { cursor:grabbing; }

/* ── Table styles ── */
.ctrack-table { width:100%; border-collapse:collapse; min-width:1200px; }
.ctrack-table thead th {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; font-weight:700; font-size:13px;
    padding:14px 14px; white-space:nowrap;
    border-right:1px solid rgba(255,255,255,.15);
    position:sticky; top:0; z-index:10;
}
.ctrack-table thead th:last-child { border-right:none; }
.ctrack-table tbody tr { border-bottom:1px solid #f1f5f9; transition:.15s; }
.ctrack-table tbody tr:hover { background:#f8fafc; }
.ctrack-table tbody td {
    padding:13px 14px; font-size:13px; font-weight:500;
    color:var(--text); white-space:nowrap; vertical-align:middle;
}
.ctrack-table tbody td.note-cell {
    max-width:200px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
}
.sl-cell { font-weight:700; color:var(--muted); text-align:center; width:52px; }
.name-cell { font-weight:700; color:var(--primary); }
.empty-state {
    text-align:center; padding:70px 20px; color:var(--muted);
}
.empty-state i { font-size:52px; margin-bottom:14px; opacity:.3; display:block; }

/* ── Status badge ── */
.status-badge {
    display:inline-block; padding:5px 13px; border-radius:20px;
    font-size:12px; font-weight:700; color:#fff;
    white-space:nowrap;
}

/* ── Trigger datetime cell ── */
.trigger-cell { color:var(--warning); font-weight:700; font-size:12px; }
.trigger-cell.overdue { color:var(--danger); }
.trigger-cell.today   { color:var(--success); }

/* ── Action buttons ── */
.act-btn {
    display:inline-flex; align-items:center; justify-content:center;
    width:32px; height:32px; border-radius:8px; border:none;
    font-size:13px; cursor:pointer; transition:.2s; text-decoration:none;
    margin:0 2px;
}
.act-btn:hover { transform:scale(1.12); text-decoration:none; }
.act-view   { background:#e0f2fe; color:#0284c7; }
.act-edit   { background:#e0e7ff; color:#4f46e5; }
.act-status { background:#d1fae5; color:#059669; }
.act-log    { background:#fef3c7; color:#d97706; }
.act-wa     { background:#dcfce7; color:#16a34a; }
.act-del    { background:#fee2e2; color:#dc2626; }

/* ── Pagination ── */
.paging-wrap {
    padding:18px 22px; display:flex; align-items:center;
    justify-content:space-between; border-top:2px solid var(--border);
    flex-wrap:wrap; gap:12px;
}
.paging-info { color:var(--muted); font-size:13px; font-weight:600; }
.paging-btns { display:flex; gap:6px; }
.paging-btn {
    padding:7px 14px; border-radius:8px; border:2px solid var(--border);
    background:#fff; color:var(--primary); font-weight:700; font-size:13px;
    cursor:pointer; transition:.2s;
}
.paging-btn:hover, .paging-btn.active { background:var(--primary); color:#fff; border-color:var(--primary); }
.paging-btn:disabled { opacity:.4; cursor:not-allowed; }

/* ── Modals ── */
.modal-content { border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,.18); }
.modal-header {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; border-radius:14px 14px 0 0; padding:20px 26px;
    border-bottom:none;
}
.modal-title { font-weight:700; font-size:1.1rem; }
.modal-header .close { color:#fff; opacity:.9; text-shadow:none; font-size:24px; }
.modal-body { padding:26px; }
.modal-footer { padding:16px 26px; border-top:2px solid var(--border); }

.form-label { font-weight:600; font-size:13px; color:var(--muted); margin-bottom:6px; display:block; }
.form-control-ct {
    width:100%; padding:10px 14px;
    border:2px solid var(--border); border-radius:9px;
    font-size:14px; font-weight:500; color:var(--text);
    transition:.2s; background:#fff;
}
.form-control-ct:focus { outline:none; border-color:var(--primary-lt); box-shadow:0 0 0 3px rgba(30,64,175,.1); }
.req-star { color:var(--danger); margin-left:3px; }
.optional-tag { color:var(--muted); font-size:11px; font-weight:500; margin-left:6px; }
.section-divider { border:none; border-top:2px dashed var(--border); margin:20px 0; }
.lang-checkbox-group {
    display:flex; flex-wrap:wrap; gap:8px;
    border:2px solid var(--border); border-radius:9px; padding:10px 12px; background:#fff;
}
.lang-check-item {
    display:inline-flex; align-items:center; gap:5px; margin:0;
    font-size:13px; font-weight:500; color:var(--text); cursor:pointer;
    background:#f8fafc; border:1px solid var(--border); border-radius:20px; padding:5px 12px;
}
.lang-check-item input { margin:0; cursor:pointer; }
.lang-check-item:has(input:checked) { background:#e0e7ff; border-color:var(--primary-lt); color:var(--primary); font-weight:700; }

/* ── Log timeline ── */
.log-timeline { max-height:420px; overflow-y:auto; padding-right:4px; }
.log-item {
    display:flex; gap:14px; margin-bottom:20px;
}
.log-dot {
    width:38px; height:38px; border-radius:50%;
    display:flex; align-items:center; justify-content:center;
    font-size:14px; color:#fff; flex-shrink:0;
}
.log-body {
    flex:1; background:#f8fafc; border-radius:10px;
    padding:12px 16px; border-left:3px solid var(--border);
}
.log-status { font-weight:700; font-size:14px; color:var(--primary); margin-bottom:4px; }
.log-note { font-size:13px; color:var(--text); margin-bottom:6px; }
.log-meta { font-size:12px; color:var(--muted); }
.log-trigger { font-size:12px; color:var(--warning); font-weight:600; margin-top:4px; }

/* ── View detail card ── */
.detail-row { display:flex; gap:0; margin-bottom:14px; border-radius:10px; overflow:hidden; border:2px solid var(--border); }
.detail-label { background:#f8fafc; padding:10px 16px; font-weight:700; font-size:13px; color:var(--muted); min-width:160px; border-right:2px solid var(--border); }
.detail-value { padding:10px 16px; font-size:14px; font-weight:600; color:var(--text); flex:1; }
.doc-dl-btn {
    display:inline-flex; align-items:center; gap:7px;
    background:var(--primary); color:#fff; padding:8px 18px;
    border-radius:9px; font-weight:700; font-size:13px; text-decoration:none;
    transition:.2s;
}
.doc-dl-btn:hover { background:var(--primary-lt); color:#fff; text-decoration:none; transform:translateY(-1px); }
.doc-dl-btn.jd { background:#8b5cf6; }
.doc-dl-btn.jd:hover { background:#7c3aed; }

/* ── WhatsApp Preview ── */
.wa-preview-box {
    background:#e7ffdb; border-radius:12px; padding:16px 18px;
    font-size:14px; font-weight:500; color:#1a472a;
    border-left:4px solid #25d366; white-space:pre-wrap;
    line-height:1.6; margin-bottom:16px;
    font-family:'Inter',sans-serif;
}

/* ── Responsive ── */
@media(max-width:768px) {
    .page-header { flex-direction:column; gap:14px; text-align:center; }
    .action-bar  { flex-direction:column; }
}

/* Custom scrollbar */
.table-scroll::-webkit-scrollbar,
.log-timeline::-webkit-scrollbar { width:8px; height:8px; }
.table-scroll::-webkit-scrollbar-track,
.log-timeline::-webkit-scrollbar-track { background:#f1f5f9; border-radius:6px; }
.table-scroll::-webkit-scrollbar-thumb { background:linear-gradient(135deg,var(--primary),var(--primary-lt)); border-radius:6px; }
</style>
</head>
<body>
<div class="page-wrap">

<?php
// Flash messages
if (isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show" style="border-radius:10px;margin-bottom:16px;">
    <i class="fas fa-check-circle mr-2"></i><?php echo htmlspecialchars($_SESSION['success_message']); ?>
    <button type="button" class="close" data-dismiss="alert">&times;</button>
</div>
<?php unset($_SESSION['success_message']); endif;
if (isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show" style="border-radius:10px;margin-bottom:16px;">
    <i class="fas fa-exclamation-circle mr-2"></i><?php echo htmlspecialchars($_SESSION['error_message']); ?>
    <button type="button" class="close" data-dismiss="alert">&times;</button>
</div>
<?php unset($_SESSION['error_message']); endif; ?>

<!-- Header -->
<div class="page-header">
    <h1><i class="fas fa-user-clock mr-2"></i>HR Candidate Tracking</h1>
    
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    

    <a href="hr_screening.php" class="btn-action" style="background: rgba(255,255,255,.15); border: 2px solid rgba(255,255,255,.3); box-shadow: none; color: white; text-decoration: none; padding: 9px 20px; border-radius: 8px; font-weight: 600; display: inline-flex; align-items: center; gap: 8px; transition: all 0.3s; margin-right: 15px;">
      <i class="fas fa-arrow-left"></i> Back to HR Candidate Screening
    </a>

</div>

<!-- Upcoming Alert Banner (today only) -->
<?php if ($today_count > 0): ?>
<div class="alert-banner" onclick="$('#alertModal').modal('show')">
    <i class="fas fa-bell"></i>
    <span><?php echo $today_count; ?> follow-up<?php echo $today_count > 1 ? 's' : ''; ?> due today</span>
    <span class="count-pill"><?php echo $today_count; ?> pending</span>
    <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
</div>
<?php elseif (!empty($alert_candidates)): ?>
<div class="alert-banner" style="background:linear-gradient(135deg,#94a3b8,#64748b);" onclick="$('#alertModal').modal('show')">
    <i class="fas fa-bell"></i>
    <span>No follow-ups due today &mdash; <?php echo count($alert_candidates); ?> overdue/upcoming pending</span>
    <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
</div>
<?php endif; ?>

<!-- Action Bar -->
<div class="action-bar">
    <button class="btn-primary-custom" data-toggle="modal" data-target="#addModal" onclick="document.getElementById('addCandidateForm').reset(); document.getElementById('add_location_other').style.display='none'; document.getElementById('add_source_other').style.display='none'; document.getElementById('dupWarningBox').style.display='none';">
        <i class="fas fa-user-plus"></i> Add Candidate
    </button>
    <div class="search-wrap">
        <i class="fas fa-search"></i>
        <input type="text" id="globalSearch" value="<?php echo $ct_f_search; ?>" placeholder="Search by name, phone, department, position, source, added by…">
    </div>
    <input type="date" id="filterDateFrom" class="form-control-ct" style="width:150px;" title="From date" value="<?php echo $ct_f_datefrom; ?>">
    <input type="date" id="filterDateTo" class="form-control-ct" style="width:150px;" title="To date" value="<?php echo $ct_f_dateto; ?>">
    <select id="filterDepartment" class="form-control-ct" style="width:170px;">
        <option value="">All — Department</option>
        <?php foreach ($filter_dept_list as $fd): ?>
        <option value="<?php echo strtolower(htmlspecialchars($fd)); ?>" <?php echo (strtolower($fd) === $ct_f_dept) ? 'selected' : ''; ?>><?php echo htmlspecialchars($fd); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterPosition" class="form-control-ct" style="width:170px;">
        <option value="">All — Position</option>
        <?php foreach ($filter_pos_list as $fp): ?>
        <option value="<?php echo strtolower(htmlspecialchars($fp)); ?>" <?php echo (strtolower($fp) === $ct_f_pos) ? 'selected' : ''; ?>><?php echo htmlspecialchars($fp); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterAddedBy" class="form-control-ct" style="width:170px;">
        <option value="">All — Added By</option>
        <?php foreach ($added_by_list as $ab): ?>
        <option value="<?php echo strtolower(htmlspecialchars($ab)); ?>" <?php echo (strtolower($ab) === $ct_f_addedby) ? 'selected' : ''; ?>><?php echo htmlspecialchars($ab); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterStatusDropdown" class="form-control-ct" style="width:170px;">
        <option value="">All Statuses</option>
        <?php foreach ($all_statuses as $st): ?>
        <option value="<?php echo htmlspecialchars($st); ?>" <?php echo ($st === $ct_f_status) ? 'selected' : ''; ?>><?php echo htmlspecialchars($st); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterLocation" class="form-control-ct" style="width:170px;">
        <option value="">All Locations</option>
        <?php foreach ($candidate_locations as $loc): if ($loc === 'Other') continue; ?>
        <option value="<?php echo strtolower(htmlspecialchars($loc)); ?>" <?php echo (strtolower($loc) === $ct_f_location) ? 'selected' : ''; ?>><?php echo htmlspecialchars($loc); ?></option>
        <?php endforeach; ?>
    </select>
    <button class="btn-primary-custom" style="background:linear-gradient(135deg,#0284c7,#0369a1);" data-toggle="modal" data-target="#importModal">
        <i class="fas fa-file-import"></i> Import
    </button>
    <a class="btn-primary-custom" id="exportCsvBtn" style="background:linear-gradient(135deg,#10b981,#059669);text-decoration:none;" href="#" onclick="return false;">
        <i class="fas fa-file-export"></i> Export
    </a>
    <button class="btn-primary-custom" style="background:linear-gradient(135deg,#f59e0b,#d97706);" onclick="openManageTemplates()">
        <i class="fas fa-comment-dots"></i> Manage Templates
    </button>
    <button class="btn-primary-custom" style="background:linear-gradient(135deg,#6366f1,#4f46e5);" onclick="openManageStatuses()">
        <i class="fas fa-tags"></i> Manage Statuses
    </button>
</div>

<?php
// Builds a page URL that preserves every current filter — used for both the
// pagination links below and by the JS filter handlers to know the base
// query string to reload with.
function ctPageUrl($page, $current_page) {
    $params = [
        'search' => $_GET['search'] ?? '', 'status' => $_GET['status'] ?? '',
        'date_from' => $_GET['date_from'] ?? '', 'date_to' => $_GET['date_to'] ?? '',
        'added_by' => $_GET['added_by'] ?? '', 'location' => $_GET['location'] ?? '',
        'department' => $_GET['department'] ?? '', 'position' => $_GET['position'] ?? '',
        'page' => $page,
    ];
    $params = array_filter($params, function($v) { return $v !== ''; });
    return htmlspecialchars($current_page . '?' . http_build_query($params));
}
?>
<!-- Table Card -->
<div class="table-card">
    <div class="table-card-header">
        <h5><i class="fas fa-list mr-2"></i>Candidate List</h5>
        <span id="tableCount" style="font-size:13px;color:var(--muted);font-weight:600;"><?php echo $ct_total; ?> candidate<?php echo $ct_total !== 1 ? 's' : ''; ?></span>
    </div>
    <div class="table-scroll" id="tableScroll">
        <table class="ctrack-table" id="candidateTable">
            <thead>
                <tr>
                    <th class="sl-cell">#</th>
                    <th>Name</th>
                    <th>Phone</th>
                    <th>Department</th>
                    <th>Position</th>
                    <th>Language Known</th>
                    <th>Source</th>
                    <th>Location</th>
                    <th>Status</th>
                    <th>Trigger Date / Time</th>
                    <th>Last Note</th>
                    <th>Added By</th>
                    <th>Last Updated By</th>
                    <th style="text-align:center;">Actions</th>
                </tr>
            </thead>
            <tbody id="candidateTbody">
            <?php if (empty($candidates)): ?>
                <tr><td colspan="13">
                    <div class="empty-state">
                        <i class="fas fa-users"></i>
                        <p style="font-weight:700;font-size:16px;">No candidates yet.</p>
                        <p style="font-size:13px;">Click <strong>Add Candidate</strong> to get started.</p>
                    </div>
                </td></tr>
            <?php else:
                $sl = $ct_total - $ct_offset; // global position (most-recent-first) — the newest candidate overall gets $ct_total, so the total headcount is always readable off the newest row's number
                foreach ($candidates as $c):
                    $sc   = $status_colors[$c['current_status']] ?? '#6b7280';
                    $tdt  = $c['trigger_datetime'];
                    $tdt_display = '';
                    $tdt_class   = 'trigger-cell';
                    if ($tdt) {
                        $tts = strtotime($tdt);
                        $now = time();
                        $tdt_display = date('d M Y, h:i A', $tts);
                        if ($tts < $now)            $tdt_class .= ' overdue';
                        elseif (date('Y-m-d',$tts) == date('Y-m-d')) $tdt_class .= ' today';
                    }
                    $note_short = $c['last_note'] ? (mb_strlen($c['last_note']) > 60 ? mb_substr($c['last_note'],0,60).'…' : $c['last_note']) : '—';
                    $has_wa = !empty($c['phone']);
            ?>
                <tr class="candidate-row">
                    <td class="sl-cell"><?php echo $sl--; ?></td>
                    <td class="name-cell"><?php echo htmlspecialchars($c['name']); ?></td>
                    <td><?php echo htmlspecialchars($c['phone']); ?></td>
                    <td><?php echo htmlspecialchars($c['department_name']); ?></td>
                    <td><?php echo htmlspecialchars($c['position_name']); ?></td>
                    <td><?php echo htmlspecialchars($c['language_known'] ?? '') ?: '—'; ?></td>
                    <td><?php echo htmlspecialchars($c['candidate_source'] ?? '') ?: '—'; ?></td>
                    <td><?php echo htmlspecialchars($c['location'] ?? '') ?: '—'; ?></td>
                    <td>
                        <select class="status-dropdown"
                            data-id="<?php echo $c['id']; ?>"
                            data-name="<?php echo htmlspecialchars(addslashes($c['name'])); ?>"
                            data-current="<?php echo htmlspecialchars($c['current_status']); ?>"
                            style="background:<?php echo $sc; ?>;color:#fff;border:none;border-radius:20px;padding:6px 26px 6px 12px;font-size:12px;font-weight:700;cursor:pointer;appearance:none;-webkit-appearance:none;-moz-appearance:none;background-image:url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 24 24%22 fill=%22white%22><path d=%22M7 10l5 5 5-5z%22/></svg>');background-repeat:no-repeat;background-position:right 8px center;background-size:14px;"
                            onchange="handleStatusDropdownChange(this)">
                            <?php foreach ($all_statuses as $st): ?>
                            <option value="<?php echo htmlspecialchars($st); ?>" <?php echo ($c['current_status'] === $st) ? 'selected' : ''; ?> style="background:#fff;color:#1e293b;"><?php echo htmlspecialchars($st); ?></option>
                            <?php endforeach; ?>
                        </select>
                        <?php if ($c['current_status'] === 'Rejected' && !empty($c['rejected_round'])): ?>
                        <div style="font-size:11px;color:#dc2626;font-weight:700;margin-top:3px;"><i class="fas fa-flag mr-1"></i><?php echo htmlspecialchars($c['rejected_round']); ?></div>
                        <?php endif; ?>
                    </td>
                    <td class="<?php echo $tdt_class; ?>"><?php echo $tdt_display ?: '—'; ?></td>
                    <td class="note-cell" title="<?php echo htmlspecialchars($c['last_note'] ?? ''); ?>"><?php echo htmlspecialchars($note_short); ?></td>
                    <td><?php echo htmlspecialchars($c['created_by']); ?></td>
                    <td><?php echo htmlspecialchars($c['last_updated_by']); ?></td>
                    <td style="text-align:center;white-space:nowrap;">
                        <!-- View -->
                        <button class="act-btn act-view" title="View Details"
                            onclick="openView(<?php echo $c['id']; ?>)">
                            <i class="fas fa-eye"></i>
                        </button>
                        <!-- Edit -->
                        <button class="act-btn act-edit" title="Edit"
                            onclick="openEdit(<?php echo $c['id']; ?>)">
                            <i class="fas fa-edit"></i>
                        </button>
                        <!-- Update Status -->
                        <button class="act-btn act-status" title="Update Status"
                            onclick="openStatus(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-sync-alt"></i>
                        </button>
                        <!-- Log -->
                        <button class="act-btn act-log" title="View History Log"
                            onclick="openLog(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-history"></i>
                        </button>
                        <!-- Email / WhatsApp (always visible) — both open the Template Picker first -->
                        <?php
                            $row_phone_clean = preg_replace('/[^0-9]/', '', $c['phone'] ?? '');
                            if (strlen($row_phone_clean) === 10) $row_phone_clean = '91' . $row_phone_clean;
                            $row_ctx = json_encode([
                                'id'          => $c['id'],
                                'name'        => $c['name'],
                                'phone'       => $c['phone'] ?? '',
                                'phone_clean' => $row_phone_clean,
                                'email'       => $c['email'] ?? '',
                                'status'      => $c['current_status'],
                                'tdt'         => $tdt_display ?: '',
                                'department'  => $c['department_name'] ?? '',
                                'position'    => $c['position_name'] ?? '',
                            ]);
                        ?>
                        <button class="act-btn" title="Send Email Notification"
                            style="background:#dbeafe;color:#1d4ed8;"
                            data-ctx='<?php echo htmlspecialchars($row_ctx, ENT_QUOTES); ?>'
                            onclick="openTemplatePicker(JSON.parse(this.dataset.ctx))">
                            <i class="fas fa-envelope"></i>
                        </button>
                        <button class="act-btn act-wa" title="Send WhatsApp Notification"
                            data-ctx='<?php echo htmlspecialchars($row_ctx, ENT_QUOTES); ?>'
                            onclick="openTemplatePicker(JSON.parse(this.dataset.ctx))">
                            <i class="fab fa-whatsapp"></i>
                        </button>
                        <!-- Delete -->
                        <button class="act-btn act-del" title="Delete"
                            onclick="doDelete(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>

                </tr>
            <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
    <div class="paging-wrap">
        <div class="paging-info">
            <?php if ($ct_total === 0): ?>
                No results
            <?php else: ?>
                Showing <?php echo $ct_start; ?>–<?php echo $ct_end; ?> of <?php echo $ct_total; ?>
            <?php endif; ?>
        </div>
        <div class="paging-btns">
            <?php if ($ct_max_page > 1):
                // Same first/current±1/last-with-ellipsis range as the old client-side buildPageRange().
                if ($ct_max_page <= 7) {
                    $ct_pages = range(1, $ct_max_page);
                } else {
                    $ct_pages = [1];
                    if ($ct_page > 3) $ct_pages[] = '…';
                    for ($i = max(2, $ct_page - 1); $i <= min($ct_max_page - 1, $ct_page + 1); $i++) $ct_pages[] = $i;
                    if ($ct_page < $ct_max_page - 2) $ct_pages[] = '…';
                    $ct_pages[] = $ct_max_page;
                }
                foreach ($ct_pages as $ct_p):
                    if ($ct_p === '…'): ?>
                        <span class="paging-btn disabled" style="pointer-events:none;">…</span>
                    <?php else: ?>
                        <a class="paging-btn<?php echo ($ct_p === $ct_page) ? ' active' : ''; ?>" style="text-decoration:none;display:inline-block;" href="<?php echo ctPageUrl($ct_p, $current_page); ?>"><?php echo $ct_p; ?></a>
                    <?php endif;
                endforeach;
            endif; ?>
        </div>
    </div>
</div>

</div><!-- /page-wrap -->

<!-- =====================================================================
     MODAL: ADD CANDIDATE
===================================================================== -->
<div class="modal fade" id="addModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <form method="POST" enctype="multipart/form-data" id="addCandidateForm" onsubmit="return validateAddCandidateForm(event)">
    <input type="hidden" name="action" value="add_candidate">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-user-plus mr-2"></i>Add New Candidate</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <!-- Department + Position -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Department <span class="optional-tag">(optional)</span></label>
                <select name="department_id" id="add_dept" class="form-control-ct"
                    onchange="fetchPositions(this.value,'add_pos','add_dept_name','add_pos_name')">
                    <option value="">Select Department…</option>
                    <?php foreach ($departments_arr as $d): ?>
                    <option value="<?php echo $d['id']; ?>" data-name="<?php echo htmlspecialchars($d['name']); ?>">
                        <?php echo htmlspecialchars($d['name']); ?>
                    </option>
                    <?php endforeach; ?>
                </select>
                <input type="hidden" name="department_name" id="add_dept_name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Position <span class="optional-tag">(optional)</span></label>
                <select name="position_id" id="add_pos" class="form-control-ct">
                    <option value="">Select Position…</option>
                </select>
                <input type="hidden" name="position_name" id="add_pos_name">
            </div>
        </div>
        <hr class="section-divider">
        <!-- Name + Phone -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Full Name <span class="req-star">*</span></label>
                <input type="text" name="name" class="form-control-ct" required placeholder="Candidate full name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Phone Number <span class="req-star">*</span></label>
                <input type="text" name="phone" id="add_phone" class="form-control-ct" required placeholder="e.g. 9876543210">
            </div>
        </div>
        <!-- Email -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Email <span class="optional-tag">(optional)</span></label>
                <input type="email" name="email" id="add_email" class="form-control-ct" placeholder="candidate@email.com">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Candidate Source <span class="optional-tag">(optional)</span></label>
                <select name="candidate_source" id="add_candidate_source" class="form-control-ct" onchange="toggleLocationOther(this,'add_source_other')">
                    <option value="">Select Source…</option>
                    <?php foreach ($candidate_sources as $src): ?>
                    <option value="<?php echo htmlspecialchars($src); ?>"><?php echo htmlspecialchars($src); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="candidate_source_other" id="add_source_other" class="form-control-ct" placeholder="Enter source" style="display:none;margin-top:8px;">
            </div>
        </div>
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Location <span class="optional-tag">(optional — recruiting location)</span></label>
                <select name="location_select" id="add_location_select" class="form-control-ct" onchange="toggleLocationOther(this,'add_location_other')">
                    <option value="">Select Location…</option>
                    <?php foreach ($candidate_locations as $loc): ?>
                    <option value="<?php echo htmlspecialchars($loc); ?>"><?php echo htmlspecialchars($loc); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="location_other" id="add_location_other" class="form-control-ct" placeholder="Enter location" style="display:none;margin-top:8px;">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Language Known <span class="optional-tag">(optional — select all that apply)</span></label>
                <div class="lang-checkbox-group" id="add_language_group">
                    <?php foreach ($candidate_languages as $lang): ?>
                    <?php if ($lang === 'Other'): ?>
                    <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="Other" onchange="toggleLangOther('add_language_known_other', this.checked)"> Other</label>
                    <?php else: ?>
                    <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="<?php echo htmlspecialchars($lang); ?>"> <?php echo htmlspecialchars($lang); ?></label>
                    <?php endif; ?>
                    <?php endforeach; ?>
                </div>
                <input type="text" name="language_known_other" id="add_language_known_other" class="form-control-ct" placeholder="Enter other language(s), comma separated" style="display:none;margin-top:8px;">
            </div>
        </div>
        <input type="hidden" name="confirm_duplicate" id="add_confirm_duplicate" value="">
        <div id="dupWarningBox" style="display:none;background:#fff7ed;border:1px solid #fcd34d;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#92400e;margin-bottom:12px;"></div>
        <hr class="section-divider">
        <!-- Resume + JD -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Resume <span class="optional-tag">(PDF/DOC/DOCX)</span></label>
                <input type="file" name="resume" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Job Description (JD) <span class="optional-tag">(PDF/DOC/DOCX)</span></label>
                <input type="file" name="jd" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom"><i class="fas fa-save mr-1"></i> Save Candidate</button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: EDIT CANDIDATE
===================================================================== -->
<div class="modal fade" id="editModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
    <input type="hidden" name="action" value="edit_candidate">
    <input type="hidden" name="id" id="edit_id">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit mr-2"></i>Edit Candidate</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Department <span class="req-star">*</span></label>
                <select name="department_id" id="edit_dept" class="form-control-ct" required
                    onchange="fetchPositions(this.value,'edit_pos','edit_dept_name','edit_pos_name')">
                    <option value="">Select Department…</option>
                    <?php foreach ($departments_arr as $d): ?>
                    <option value="<?php echo $d['id']; ?>" data-name="<?php echo htmlspecialchars($d['name']); ?>">
                        <?php echo htmlspecialchars($d['name']); ?>
                    </option>
                    <?php endforeach; ?>
                </select>
                <input type="hidden" name="department_name" id="edit_dept_name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Position <span class="req-star">*</span></label>
                <select name="position_id" id="edit_pos" class="form-control-ct" required>
                    <option value="">Select Position…</option>
                </select>
                <input type="hidden" name="position_name" id="edit_pos_name">
            </div>
        </div>
        <hr class="section-divider">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Full Name <span class="req-star">*</span></label>
                <input type="text" name="name" id="edit_name" class="form-control-ct" required>
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Phone Number <span class="req-star">*</span></label>
                <input type="text" name="phone" id="edit_phone" class="form-control-ct" required>
            </div>
        </div>
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Email <span class="optional-tag">(optional)</span></label>
                <input type="email" name="email" id="edit_email" class="form-control-ct">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Location <span class="optional-tag">(optional — recruiting location)</span></label>
                <select name="location_select" id="edit_location_select" class="form-control-ct" onchange="toggleLocationOther(this,'edit_location_other')">
                    <option value="">Select Location…</option>
                    <?php foreach ($candidate_locations as $loc): ?>
                    <option value="<?php echo htmlspecialchars($loc); ?>"><?php echo htmlspecialchars($loc); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="location_other" id="edit_location_other" class="form-control-ct" placeholder="Enter location" style="display:none;margin-top:8px;">
            </div>
        </div>
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Language Known <span class="optional-tag">(optional — select all that apply)</span></label>
                <div class="lang-checkbox-group" id="edit_language_group">
                    <?php foreach ($candidate_languages as $lang): ?>
                    <?php if ($lang === 'Other'): ?>
                    <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="Other" onchange="toggleLangOther('edit_language_known_other', this.checked)"> Other</label>
                    <?php else: ?>
                    <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="<?php echo htmlspecialchars($lang); ?>"> <?php echo htmlspecialchars($lang); ?></label>
                    <?php endif; ?>
                    <?php endforeach; ?>
                </div>
                <input type="text" name="language_known_other" id="edit_language_known_other" class="form-control-ct" placeholder="Enter other language(s), comma separated" style="display:none;margin-top:8px;">
            </div>
        </div>
        <hr class="section-divider">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Replace Resume <span class="optional-tag">(leave blank to keep existing)</span></label>
                <input type="file" name="resume" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Replace JD <span class="optional-tag">(leave blank to keep existing)</span></label>
                <input type="file" name="jd" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom"><i class="fas fa-save mr-1"></i> Update Candidate</button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: UPDATE STATUS
===================================================================== -->
<div class="modal fade" id="statusModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
    <form method="POST">
    <input type="hidden" name="action" value="update_status">
    <input type="hidden" name="id" id="status_id">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-sync-alt mr-2"></i>Update Status — <span id="status_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="mb-3">
            <label class="form-label">Status <span class="req-star">*</span></label>
            <select name="status" id="status_select" class="form-control-ct" required onchange="toggleTrigger(this.value); toggleRejectFields(this.value)">
                <?php foreach ($all_statuses as $st): ?>
                <option value="<?php echo $st; ?>"><?php echo $st; ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="mb-3" id="trigger_wrap" style="display:none;">
            <label class="form-label">
                <i class="fas fa-calendar-alt mr-1" style="color:var(--warning)"></i>
                Schedule Date &amp; Time <span class="req-star" id="trigger_required_star">*</span>
            </label>
            <input type="datetime-local" name="trigger_datetime" id="status_trigger" class="form-control-ct">
            <small style="color:var(--muted);font-size:12px;margin-top:5px;display:block;">
                <i class="fas fa-info-circle mr-1"></i>This will trigger an alert banner on the day and 1 day before.
            </small>
        </div>
        <div class="mb-3" id="reject_wrap" style="display:none;background:#fef2f2;border:1px solid #fecaca;border-radius:9px;padding:14px 16px;">
            <label class="form-label" style="color:#991b1b;margin-bottom:10px;">
                <i class="fas fa-times-circle mr-1"></i>Rejection Details
            </label>
            <div class="mb-2">
                <label class="form-label" style="font-size:12px;">Rejected At <span class="optional-tag">(round or stage — leave blank for "Overall")</span></label>
                <input type="text" name="reject_round" id="reject_round" class="form-control-ct" placeholder="e.g. Round 2, Telephonic Screening, Overall">
            </div>
            <div>
                <label class="form-label" style="font-size:12px;">Rejection Reason <span class="req-star">*</span></label>
                <textarea name="reject_reason" id="reject_reason" class="form-control-ct" rows="3" placeholder="Why is this candidate being rejected?"></textarea>
            </div>
        </div>
        <div class="mb-3">
            <label class="form-label">Language Known <span class="optional-tag">(optional — select all that apply)</span></label>
            <div class="lang-checkbox-group" id="status_language_group">
                <?php foreach ($candidate_languages as $lang): ?>
                <?php if ($lang === 'Other'): ?>
                <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="Other" onchange="toggleLangOther('status_language_known_other', this.checked)"> Other</label>
                <?php else: ?>
                <label class="lang-check-item"><input type="checkbox" name="language_known[]" value="<?php echo htmlspecialchars($lang); ?>"> <?php echo htmlspecialchars($lang); ?></label>
                <?php endif; ?>
                <?php endforeach; ?>
            </div>
            <input type="text" name="language_known_other" id="status_language_known_other" class="form-control-ct" placeholder="Enter other language(s), comma separated" style="display:none;margin-top:8px;">
        </div>
        <div class="mb-3" id="current_note_display" style="display:none;">
            <label class="form-label">Current Note <span class="optional-tag">(kept automatically if you leave the box below blank)</span></label>
            <div style="background:#f8fafc;padding:10px 14px;border-radius:8px;font-size:13px;color:var(--text);border:1px solid var(--border);" id="current_note_text"></div>
        </div>
        <div class="mb-3">
            <label class="form-label">Notes / Remarks</label>
            <textarea name="notes" class="form-control-ct" rows="4" placeholder="Leave blank to keep the existing note above, or type a new one to replace it…"></textarea>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom" style="background:linear-gradient(135deg,#10b981,#059669);">
            <i class="fas fa-check mr-1"></i> Save Status
        </button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: IMPORT CANDIDATES (CSV)
===================================================================== -->
<div class="modal fade" id="importModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
    <input type="hidden" name="action" value="import_candidates">
    <div class="modal-header" style="background:linear-gradient(135deg,#0284c7,#0369a1);color:#fff;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-file-import mr-2"></i>Import Candidates from CSV</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <!-- Step 1: Download Sample File -->
        <div style="background:#f0f9ff;border:1.5px dashed #7dd3fc;border-radius:10px;padding:16px 20px;margin-bottom:20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;">
            <div>
                <div style="font-weight:700;color:#0369a1;font-size:14px;margin-bottom:3px;"><i class="fas fa-file-csv mr-1"></i> Step 1: Download Sample CSV Template</div>
                <div style="font-size:12.5px;color:#0c4a6e;">Includes pre-filled sample rows showing required headers, formats, and values.</div>
            </div>
            <a href="?download_sample_csv=1" class="btn-primary-custom" style="background:linear-gradient(135deg,#0284c7,#0369a1);text-decoration:none;padding:9px 18px;font-size:12.5px;">
                <i class="fas fa-download mr-1"></i> Download Sample CSV
            </a>
        </div>

        <!-- Field Guide: Required vs Optional -->
        <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px;margin-bottom:20px;">
            <div style="font-weight:700;font-size:13px;color:var(--navy);margin-bottom:8px;"><i class="fas fa-info-circle mr-1" style="color:var(--primary);"></i> Column Field Guide &amp; Validation Rules:</div>
            <div class="row" style="font-size:12.5px;">
                <div class="col-md-6 mb-2">
                    <div style="font-weight:700;color:#b91c1c;margin-bottom:4px;"><i class="fas fa-asterisk fa-xs mr-1"></i> Required Fields (Must be filled):</div>
                    <ul style="margin:0;padding-left:20px;color:#334155;line-height:1.6;">
                        <li><strong>Candidate Name</strong></li>
                        <li><strong>Phone</strong> (Used for automatic duplicate check)</li>
                    </ul>
                </div>
                <div class="col-md-6 mb-2">
                    <div style="font-weight:700;color:#0369a1;margin-bottom:4px;"><i class="fas fa-check-circle fa-xs mr-1"></i> Optional Fields (Can be skipped):</div>
                    <ul style="margin:0;padding-left:20px;color:#64748b;line-height:1.6;">
                        <li><strong>Department</strong> &middot; <strong>Position</strong></li>
                        <li><strong>Email</strong> (Checked for duplicates if provided)</li>
                        <li><strong>Source</strong> (e.g. Naukri, LinkedIn, Walk-in)</li>
                        <li><strong>Location</strong> &middot; <strong>Language Known</strong></li>
                        <li><strong>Status</strong> &middot; <strong>Schedule Date &amp; Time</strong> &middot; <strong>Notes</strong></li>
                    </ul>
                </div>
            </div>
            <div style="margin-top:10px;padding-top:8px;border-top:1px solid #e2e8f0;font-size:12px;color:#92400e;background:#fffbeb;padding:8px 12px;border-radius:6px;">
                <i class="fas fa-shield-alt mr-1"></i> <strong>Automatic Duplicate Protection:</strong> If a candidate with the same Phone number or Email already exists in the system, they will be automatically skipped and recorded in the detailed rejection report.
            </div>
        </div>

        <!-- Step 2: Upload CSV -->
        <div class="mb-3">
            <label class="form-label" style="font-weight:700;font-size:13px;">Step 2: Select Filled CSV File to Upload <span class="req-star">*</span></label>
            <input type="file" name="csv_file" accept=".csv" required class="form-control-ct" style="padding:10px;">
            <small style="color:var(--muted);font-size:12px;display:block;margin-top:4px;">Only <code>.csv</code> format is supported.</small>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom" style="background:linear-gradient(135deg,#0284c7,#0369a1);">
            <i class="fas fa-upload mr-1"></i> Import Candidates Now
        </button>
    </div>
    </form>
</div></div></div>

<?php if (!empty($_SESSION['import_results'])): 
    $import_res = $_SESSION['import_results'];
    unset($_SESSION['import_results']);
?>
<!-- =====================================================================
     MODAL: IMPORT RESULTS & DUPLICATE REJECTION REPORT
===================================================================== -->
<div class="modal fade" id="importResultsModal" tabindex="-1">
<div class="modal-dialog modal-lg modal-dialog-scrollable">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),#1e293b);color:#fff;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-clipboard-list mr-2"></i>Candidate Import &amp; Rejection Summary</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <div class="row mb-3" style="text-align:center;">
            <div class="col-4">
                <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:12px;">
                    <div style="font-size:11px;font-weight:700;color:#64748b;text-transform:uppercase;">Total Processed</div>
                    <div style="font-size:24px;font-weight:800;color:var(--navy);"><?php echo intval($import_res['total']); ?></div>
                </div>
            </div>
            <div class="col-4">
                <div style="background:#ecfdf5;border:1px solid #a7f3d0;border-radius:10px;padding:12px;">
                    <div style="font-size:11px;font-weight:700;color:#047857;text-transform:uppercase;">Imported Successfully</div>
                    <div style="font-size:24px;font-weight:800;color:#059669;"><?php echo intval($import_res['imported_count']); ?></div>
                </div>
            </div>
            <div class="col-4">
                <div style="background:#fff1f2;border:1px solid #fecdd3;border-radius:10px;padding:12px;">
                    <div style="font-size:11px;font-weight:700;color:#be123c;text-transform:uppercase;">Skipped / Rejected</div>
                    <div style="font-size:24px;font-weight:800;color:#dc2626;"><?php echo intval($import_res['skipped_count']); ?></div>
                </div>
            </div>
        </div>

        <?php if (!empty($import_res['skipped'])): ?>
        <div style="margin-top:16px;">
            <h6 style="font-weight:800;color:#991b1b;margin-bottom:10px;">
                <i class="fas fa-exclamation-triangle mr-1"></i> Rejected / Skipped Records Report (<?php echo count($import_res['skipped']); ?>)
            </h6>
            <div style="overflow-x:auto;border:1px solid #fee2e2;border-radius:8px;">
                <table class="table table-sm table-striped" style="font-size:12px;margin:0;">
                    <thead style="background:#fee2e2;color:#991b1b;">
                        <tr>
                            <th># Row</th>
                            <th>Candidate Name</th>
                            <th>Phone</th>
                            <th>Email</th>
                            <th>Dept / Position</th>
                            <th>Rejection Reason</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($import_res['skipped'] as $sk): ?>
                        <tr>
                            <td style="font-weight:700;"><?php echo htmlspecialchars($sk['row'] ?? '-'); ?></td>
                            <td style="font-weight:700;color:#0f172a;"><?php echo htmlspecialchars($sk['name'] ?? '-'); ?></td>
                            <td><?php echo htmlspecialchars($sk['phone'] ?? '-'); ?></td>
                            <td><?php echo htmlspecialchars($sk['email'] ?? '-'); ?></td>
                            <td><?php echo htmlspecialchars(($sk['dept'] ?? '-') . ' / ' . ($sk['pos'] ?? '-')); ?></td>
                            <td style="color:#b91c1c;font-weight:600;"><?php echo htmlspecialchars($sk['reason'] ?? '-'); ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>
<?php endif; ?>

<!-- =====================================================================
     MODAL: VIEW DETAILS
===================================================================== -->
<div class="modal fade" id="viewModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#4f46e5,#6366f1);">
        <h5 class="modal-title"><i class="fas fa-user mr-2"></i>Candidate Details — <span id="view_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" id="viewBody">
        <div style="text-align:center;padding:40px;">
            <i class="fas fa-spinner fa-spin fa-2x" style="color:var(--primary)"></i>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: HISTORY LOG
===================================================================== -->
<div class="modal fade" id="logModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#d97706,#f59e0b);">
        <h5 class="modal-title"><i class="fas fa-history mr-2"></i>History Log — <span id="log_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="log-timeline" id="logTimeline">
            <div style="text-align:center;padding:40px;">
                <i class="fas fa-spinner fa-spin fa-2x" style="color:var(--warning)"></i>
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: WHATSAPP
===================================================================== -->
<div class="modal fade" id="waModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title"><i class="fab fa-whatsapp mr-2"></i>Send WhatsApp Reminder</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            This pre-filled message will open in WhatsApp Web / App. You can edit it before sending.
        </p>
        <label class="form-label">Preview Message</label>
        <div class="wa-preview-box" id="waPreview"></div>
        <div style="font-size:13px;color:var(--muted);">
            <i class="fas fa-phone mr-1"></i> Sending to: <strong id="waPhone"></strong>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <a id="waLink" href="#" target="_blank" class="btn btn-success" style="font-weight:700;border-radius:9px;padding:10px 22px;">
            <i class="fab fa-whatsapp mr-1"></i> Open WhatsApp
        </a>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: ALERT — Upcoming Follow-ups
===================================================================== -->
<div class="modal fade" id="alertModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f97316,#ea580c);">
        <h5 class="modal-title"><i class="fas fa-bell mr-2"></i>Upcoming Follow-ups / Scheduled Calls</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <?php if (empty($alert_candidates)): ?>
            <div style="text-align:center;padding:40px;color:var(--muted);">
                <i class="fas fa-check-circle fa-3x" style="margin-bottom:14px;opacity:.3;"></i>
                <p>No upcoming follow-ups.</p>
            </div>
        <?php else: ?>
            <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px;background:#f8fafc;border-radius:10px;padding:12px 16px;">
                <input type="date" id="alertDateFrom" class="form-control-ct" style="width:150px;" title="From date">
                <input type="date" id="alertDateTo" class="form-control-ct" style="width:150px;" title="To date">
                <select id="alertStatusFilter" class="form-control-ct" style="width:170px;">
                    <option value="">All Statuses</option>
                    <?php foreach ($trigger_statuses as $st): ?>
                    <option value="<?php echo htmlspecialchars($st); ?>"><?php echo htmlspecialchars($st); ?></option>
                    <?php endforeach; ?>
                </select>
                <button onclick="applyAlertFilter()" style="padding:9px 16px;border:none;border-radius:8px;background:#f97316;color:#fff;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-filter mr-1"></i>Filter</button>
                <button onclick="resetAlertFilterToday()" style="padding:9px 16px;border:1px solid #e2e8f0;border-radius:8px;background:#fff;color:#475569;font-weight:700;font-size:12px;cursor:pointer;">Today Only</button>
                <button onclick="exportAlertCSV()" style="padding:9px 16px;border:none;border-radius:8px;background:#10b981;color:#fff;font-weight:700;font-size:12px;cursor:pointer;margin-left:auto;"><i class="fas fa-file-export mr-1"></i>Export</button>
            </div>
            <div id="alertCardsContainer">
            <?php foreach ($alert_candidates as $ac):
                $sc    = $status_colors[$ac['current_status']] ?? '#6b7280';
                $tdt_f = date('d M Y, h:i A', strtotime($ac['trigger_datetime']));
                $is_today = date('Y-m-d', strtotime($ac['trigger_datetime'])) == date('Y-m-d');
                $is_overdue = strtotime($ac['trigger_datetime']) < time();
                $ac_phone_clean = preg_replace('/[^0-9]/', '', $ac['phone']);
                if (strlen($ac_phone_clean) === 10) $ac_phone_clean = '91' . $ac_phone_clean;
                $has_email = !empty($ac['email']);
            ?>
            <div class="alert-card-item"
                data-status="<?php echo htmlspecialchars($ac['current_status']); ?>"
                data-tdate="<?php echo date('Y-m-d', strtotime($ac['trigger_datetime'])); ?>"
                data-name="<?php echo htmlspecialchars($ac['name']); ?>"
                data-phone="<?php echo htmlspecialchars($ac['phone']); ?>"
                data-dept="<?php echo htmlspecialchars($ac['department_name']); ?>"
                data-pos="<?php echo htmlspecialchars($ac['position_name']); ?>"
                data-tdt="<?php echo htmlspecialchars($tdt_f); ?>"
                data-note="<?php echo htmlspecialchars($ac['last_note'] ?? ''); ?>"
                style="background:#f8fafc;border-radius:12px;padding:16px;margin-bottom:14px;border-left:4px solid <?php echo $sc; ?>;" >
                <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:14px;">
                    <div>
                        <div style="font-weight:700;font-size:15px;color:var(--primary);"><?php echo htmlspecialchars($ac['name']); ?></div>
                        <div style="font-size:12px;color:var(--muted);margin-top:3px;">
                            <i class="fas fa-phone mr-1"></i><?php echo htmlspecialchars($ac['phone']); ?>
                            &nbsp;|&nbsp;<i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($ac['department_name']); ?>
                            &nbsp;|&nbsp;<i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($ac['position_name']); ?>
                        </div>
                        <?php if ($ac['last_note']): ?>
                        <div style="font-size:12px;color:var(--text);margin-top:6px;"><i class="fas fa-sticky-note mr-1" style="color:var(--warning)"></i><?php echo htmlspecialchars(mb_substr($ac['last_note'],0,80)); ?></div>
                        <?php endif; ?>
                    </div>
                    <div style="text-align:right;flex-shrink:0;">
                        <span class="status-badge" style="background:<?php echo $sc; ?>;margin-bottom:7px;display:inline-block;"><?php echo htmlspecialchars($ac['current_status']); ?></span><br>
                        <span style="font-size:12px;font-weight:700;color:<?php echo $is_overdue ? '#ef4444' : ($is_today ? '#10b981' : '#f59e0b'); ?>">
                            <i class="fas fa-clock mr-1"></i><?php echo $tdt_f; ?>
                            <?php echo $is_overdue ? ' — <strong>OVERDUE</strong>' : ($is_today ? ' — <strong>TODAY</strong>' : ' — Tomorrow'); ?>
                        </span>
                    </div>
                </div>
                <!-- Notify Buttons -->
                <?php
                    $ac_ctx = json_encode([
                        'id'          => $ac['id'],
                        'name'        => $ac['name'],
                        'phone'       => $ac['phone'],
                        'phone_clean' => $ac_phone_clean,
                        'email'       => $ac['email'] ?? '',
                        'status'      => $ac['current_status'],
                        'tdt'         => $tdt_f,
                        'department'  => $ac['department_name'] ?? '',
                        'position'    => $ac['position_name'] ?? '',
                    ]);
                ?>
                <div style="display:flex;gap:8px;margin-top:12px;padding-top:10px;border-top:1px dashed #e2e8f0;">
                    <button type="button"
                        data-ctx='<?php echo htmlspecialchars($ac_ctx, ENT_QUOTES); ?>'
                        onclick="openTemplatePicker(JSON.parse(this.dataset.ctx))"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#0077b5,#006097);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fas fa-envelope"></i> Email
                    </button>
                    <?php if (!empty($ac['phone'])): ?>
                    <button type="button"
                        data-ctx='<?php echo htmlspecialchars($ac_ctx, ENT_QUOTES); ?>'
                        onclick="openTemplatePicker(JSON.parse(this.dataset.ctx))"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#25d366,#128c7e);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fab fa-whatsapp"></i> WhatsApp
                    </button>
                    <?php endif; ?>
                    <button type="button"
                        onclick="$('#alertModal').modal('hide'); setTimeout(function(){ openStatus(<?php echo $ac['id']; ?>, '<?php echo htmlspecialchars(addslashes($ac['name'])); ?>'); }, 400);"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fas fa-sync-alt"></i> Update Status
                    </button>
                </div>
            </div>
            <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: TEMPLATE PICKER
===================================================================== -->
<div class="modal fade" id="templatePickerModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h5 class="modal-title"><i class="fas fa-comment-dots mr-2"></i>Choose a Message Template — <span id="tpl_pick_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="search-wrap" style="margin-bottom:16px;">
            <i class="fas fa-search"></i>
            <input type="text" id="tplSearchInput" class="form-control-ct" style="padding-left:42px;" placeholder="Search templates by name, status, or keyword…">
        </div>
        <div id="tplPickerList" style="max-height:420px;overflow-y:auto;"></div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: MANAGE TEMPLATES
===================================================================== -->
<div class="modal fade" id="manageTemplatesModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h5 class="modal-title"><i class="fas fa-comment-dots mr-2"></i>Manage Message Templates</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div style="background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:16px;margin-bottom:18px;">
            <input type="hidden" id="tpl_edit_id" value="">
            <div class="mb-2">
                <label class="form-label">Template Title <span class="req-star">*</span></label>
                <input type="text" id="tpl_title" class="form-control-ct" placeholder="e.g. Interview Reminder">
            </div>
            <div class="mb-2">
                <label class="form-label">Applies To Status(es) <span class="optional-tag">(select one or more, or leave as General)</span></label>
                <div id="tpl_status_checks" style="display:flex;flex-wrap:wrap;gap:8px 14px;max-height:110px;overflow-y:auto;padding:8px;border:1px solid var(--border);border-radius:8px;background:#fff;"></div>
            </div>
            <div class="mb-2">
                <label class="form-label">Message Body <span class="req-star">*</span></label>
                <textarea id="tpl_body" class="form-control-ct" rows="6" placeholder="Hi {name}, your interview for {position} at {company} is scheduled on {date} at {time}..."></textarea>
                <small style="color:var(--muted);font-size:11.5px;display:block;margin-top:5px;">
                    Available placeholders: <code>{name}</code> <code>{position}</code> <code>{department}</code> <code>{company}</code> <code>{date}</code> <code>{time}</code> <code>{phone}</code> <code>{sender}</code>
                </small>
            </div>
            <button type="button" class="btn-primary-custom" id="tpl_save_btn" onclick="saveTemplate()"><i class="fas fa-save mr-1"></i> Save Template</button>
            <button type="button" class="btn btn-secondary" id="tpl_cancel_edit_btn" style="display:none;" onclick="resetTemplateForm()">Cancel Edit</button>
        </div>
        <h6 style="font-weight:700;color:var(--primary);margin-bottom:12px;">Existing Templates</h6>
        <div id="tplManageList"></div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: MANAGE CUSTOM STATUSES
===================================================================== -->
<div class="modal fade" id="manageStatusesModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#6366f1,#4f46e5);">
        <h5 class="modal-title"><i class="fas fa-tags mr-2"></i>Manage Custom Statuses</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div style="background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:16px;margin-bottom:18px;">
            <label class="form-label">New Status Name <span class="req-star">*</span></label>
            <div style="display:flex;gap:10px;">
                <input type="text" id="newStatusName" class="form-control-ct" placeholder="e.g. Salary Negotiation" style="flex:1;">
                <button type="button" class="btn-primary-custom" style="background:linear-gradient(135deg,#6366f1,#4f46e5);white-space:nowrap;" onclick="addCustomStatus()"><i class="fas fa-plus mr-1"></i> Add</button>
            </div>
            <small style="color:var(--muted);font-size:11.5px;display:block;margin-top:8px;">
                New statuses appear in the status dropdown for every candidate, right alongside Round 1, Round 2, etc. The Schedule Date &amp; Time field will be available but optional for them, same as "Interested".
            </small>
        </div>
        <h6 style="font-weight:700;color:var(--primary);margin-bottom:12px;">Existing Custom Statuses</h6>
        <div id="customStatusList"></div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- Delete form (hidden) -->
<form method="POST" id="deleteForm" style="display:none;">
    <input type="hidden" name="action" value="delete_candidate">
    <input type="hidden" name="id" id="delete_id">
</form>

<!-- =====================================================================
     MODAL: NOTIFY CANDIDATE (Email + WhatsApp)
===================================================================== -->
<div class="modal fade" id="notifyModal" tabindex="-1">
<div class="modal-dialog modal-lg modal-dialog-scrollable">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title"><i class="fas fa-paper-plane mr-2"></i>Notify Candidate — <span id="notify_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            Review and edit the messages below before sending via Email or WhatsApp.
        </p>
        <input type="hidden" id="notify_name_hidden">
        <input type="hidden" id="notify_tdt_hidden">
        <div style="margin-bottom:18px;">
            <label class="form-label">Sender Name <span class="optional-tag">(shown in &ldquo;Regards,&rdquo; &mdash; auto-filled, editable)</span></label>
            <input type="text" id="notify_sender_name" class="form-control-ct" oninput="regenerateNotifyMessages()" style="max-width:280px;">
        </div>

        <div id="saveAsTemplateBox" style="display:none;background:#fffbeb;border:1px solid #fde68a;border-radius:10px;padding:14px 16px;margin-bottom:18px;">
            <label style="font-weight:700;font-size:13px;color:#92400e;cursor:pointer;display:flex;align-items:center;gap:8px;">
                <input type="checkbox" id="saveAsTemplateCheck" onchange="document.getElementById('saveAsTemplateFields').style.display=this.checked?'block':'none';">
                Save this message as a reusable template for next time
            </label>
            <div id="saveAsTemplateFields" style="display:none;margin-top:10px;">
                <label class="form-label">Template Title</label>
                <input type="text" id="saveAsTemplateTitle" class="form-control-ct" placeholder="e.g. Custom Reminder">
                <small style="color:var(--muted);font-size:11.5px;display:block;margin-top:6px;">Saved with whatever text you actually send below — swap in specific names/dates for placeholders like <code>{name}</code> first if you want it reusable. It will be tagged to this candidate's current status (<span id="saveAsTemplateStatusLabel"></span>).</small>
            </div>
        </div>

        <!-- Email Section -->
        <div style="background:#eff6ff;border-radius:12px;padding:20px;margin-bottom:18px;border:1px solid #bfdbfe;">
            <div style="font-weight:700;font-size:14px;color:#1d4ed8;margin-bottom:14px;">
                <i class="fas fa-envelope mr-2"></i>Send via Email
            </div>
            <div class="row">
                <div class="col-md-6 mb-3">
                    <label class="form-label">To (Email Address)</label>
                    <input type="email" id="notify_email_to" class="form-control-ct" placeholder="candidate@email.com">
                </div>
                <div class="col-md-6 mb-3">
                    <label class="form-label">Subject</label>
                    <input type="text" id="notify_email_subject" class="form-control-ct">
                </div>
            </div>
            <div class="mb-3">
                <label class="form-label">Email Body (Plain Text)</label>
                <textarea id="notify_email_body" class="form-control-ct" rows="6" style="resize:vertical;"></textarea>
            </div>
            <button type="button" onclick="sendNotifyEmail()" style="padding:10px 22px;border:none;border-radius:9px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;font-weight:700;font-size:13px;cursor:pointer;">
                <i class="fas fa-paper-plane mr-2"></i>Send Email
            </button>
            <span id="notify_email_status" style="font-size:12px;margin-left:12px;"></span>
        </div>

        <!-- WhatsApp Section -->
        <div style="background:#f0fdf4;border-radius:12px;padding:20px;border:1px solid #bbf7d0;">
            <div style="font-weight:700;font-size:14px;color:#15803d;margin-bottom:14px;">
                <i class="fab fa-whatsapp mr-2"></i>Send via WhatsApp
            </div>
            <div class="mb-3">
                <label class="form-label">WhatsApp Message</label>
                <textarea id="notify_wa_body" class="form-control-ct" rows="6" style="resize:vertical;font-family:'Inter',sans-serif;"></textarea>
            </div>
            <div style="font-size:13px;color:var(--muted);margin-bottom:12px;">
                <i class="fas fa-phone mr-1"></i> Sending to: <strong id="notify_wa_phone_display"></strong>
            </div>
            <a id="notify_wa_link" href="#" target="_blank"
                onclick="updateWALink()"
                style="display:inline-block;padding:10px 22px;border-radius:9px;background:linear-gradient(135deg,#16a34a,#22c55e);color:#fff;font-weight:700;font-size:13px;text-decoration:none;">
                <i class="fab fa-whatsapp mr-2"></i>Open WhatsApp
            </a>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     Scripts
===================================================================== -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>

<script>
// ── Config from PHP ──────────────────────────────────────
var TRIGGER_STATUSES = <?php echo json_encode($trigger_statuses); ?>;
var TRIGGER_REQUIRED_STATUSES = <?php echo json_encode($trigger_required_statuses); ?>;
var STATUS_COLORS    = <?php echo json_encode($status_colors); ?>;
var COMPANY_NAME     = <?php echo json_encode($companyName); ?>;
var HR_NAME          = <?php echo json_encode($currentUser); ?>;
var ALL_STATUSES     = <?php echo json_encode($all_statuses); ?>;

function validateAddCandidateForm(e) {
    if (document.getElementById('add_confirm_duplicate').value === '1') {
        return true; // Already confirmed
    }
    
    e.preventDefault();
    var form = e.target;
    var phone = document.getElementById('add_phone').value.trim();
    var email = document.getElementById('add_email').value.trim();
    var dept  = document.getElementById('add_dept_name').value.trim();
    var pos   = document.getElementById('add_pos_name').value.trim();
    var box = document.getElementById('dupWarningBox');
    
    if (!phone && !email) { form.submit(); return false; }
    
    var btn = form.querySelector('button[type="submit"]');
    var oldHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Checking...';
    
    fetch('<?php echo $current_page; ?>?check_duplicate=1&phone=' + encodeURIComponent(phone) + '&email=' + encodeURIComponent(email) + '&dept=' + encodeURIComponent(dept) + '&pos=' + encodeURIComponent(pos))
        .then(function(r) { return r.json(); })
        .then(function(res) {
            btn.disabled = false;
            btn.innerHTML = oldHtml;
            if (res.duplicate) {
                box.innerHTML = '<i class="fas fa-exclamation-triangle mr-1"></i> A candidate named <strong>' + res.name + '</strong> (ID #' + res.id + ', status: ' + res.status + ') already exists for this department and position.<br>' +
                    '<label style="margin-top:8px;font-weight:700;cursor:pointer;"><input type="checkbox" onchange="document.getElementById(\'add_confirm_duplicate\').value=this.checked?\'1\':\'\'" > I confirm this is a separate application (Add anyway)</label>';
                box.style.display = 'block';
            } else {
                document.getElementById('add_confirm_duplicate').value = '1';
                form.submit();
            }
        }).catch(function() {
            btn.disabled = false;
            btn.innerHTML = oldHtml;
            alert('Error checking duplicate.');
        });
    return false;
}

// ── Smooth horizontal scroll with mouse drag ─────────────
(function() {
    var el = document.getElementById('tableScroll');
    var isDown = false, startX, scrollLeft;
    el.addEventListener('mousedown', function(e) {
        isDown = true; el.style.cursor = 'grabbing';
        startX = e.pageX - el.offsetLeft; scrollLeft = el.scrollLeft;
    });
    el.addEventListener('mouseleave', function() { isDown = false; el.style.cursor = 'grab'; });
    el.addEventListener('mouseup',    function() { isDown = false; el.style.cursor = 'grab'; });
    el.addEventListener('mousemove',  function(e) {
        if (!isDown) return;
        e.preventDefault();
        var x = e.pageX - el.offsetLeft;
        el.scrollLeft = scrollLeft - (x - startX);
    });
})();

// Filters and search now trigger a real page reload with query params —
// filtering/pagination happens in SQL now, not by hiding/showing rows that
// were all fetched and rendered on every load regardless of what was needed.
// Search is debounced so typing doesn't reload on every keystroke.
function ctBuildFilterParams() {
    var params = new URLSearchParams();
    var search   = document.getElementById('globalSearch').value.trim();
    var status   = document.getElementById('filterStatusDropdown').value;
    var dateFrom = document.getElementById('filterDateFrom').value;
    var dateTo   = document.getElementById('filterDateTo').value;
    var addedBy  = document.getElementById('filterAddedBy').value;
    var location = document.getElementById('filterLocation').value;
    var dept     = document.getElementById('filterDepartment').value;
    var pos      = document.getElementById('filterPosition').value;
    if (search)   params.set('search', search);
    if (status)   params.set('status', status);
    if (dateFrom) params.set('date_from', dateFrom);
    if (dateTo)   params.set('date_to', dateTo);
    if (addedBy)  params.set('added_by', addedBy);
    if (location) params.set('location', location);
    if (dept)     params.set('department', dept);
    if (pos)      params.set('position', pos);
    return params;
}

function ctReloadWithFilters() {
    var qs = ctBuildFilterParams().toString();
    window.location.href = window.location.pathname + (qs ? '?' + qs : '');
}

document.getElementById('filterDateFrom').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterDateTo').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterAddedBy').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterLocation').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterDepartment').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterPosition').addEventListener('change', ctReloadWithFilters);
document.getElementById('filterStatusDropdown').addEventListener('change', ctReloadWithFilters);

var ctSearchDebounce = null;
document.getElementById('globalSearch').addEventListener('input', function() {
    clearTimeout(ctSearchDebounce);
    ctSearchDebounce = setTimeout(ctReloadWithFilters, 600);
});
document.getElementById('globalSearch').addEventListener('keydown', function(e) {
    if (e.key === 'Enter') { clearTimeout(ctSearchDebounce); ctReloadWithFilters(); }
});

// Export streams a fresh CSV from the server matching whatever's currently in
// the filter inputs (even if search hasn't finished its debounce yet) — it no
// longer scrapes already-rendered DOM rows, since only the current page's
// rows exist in the DOM now.
document.getElementById('exportCsvBtn').addEventListener('click', function(e) {
    e.preventDefault();
    var params = ctBuildFilterParams();
    params.set('export_csv', '1');
    window.location.href = window.location.pathname + '?' + params.toString();
});

// ── Fetch positions dynamically ────────────────────────────
function fetchPositions(deptId, posSelectId, deptNameId, posNameId) {
    var deptSel = document.querySelector('[id="' + (deptId ? 'add_dept' : '') + '"], select[onchange*="' + posSelectId + '"]');
    // Get dept name from selected option
    var deptSelEl = document.getElementById(posSelectId === 'add_pos' ? 'add_dept' : 'edit_dept');
    if (deptSelEl) {
        var selOpt = deptSelEl.options[deptSelEl.selectedIndex];
        if (selOpt && document.getElementById(deptNameId)) {
            document.getElementById(deptNameId).value = selOpt.dataset.name || selOpt.text;
        }
    }
    var posEl = document.getElementById(posSelectId);
    posEl.innerHTML = '<option value="">Loading…</option>';
    if (!deptId) { posEl.innerHTML = '<option value="">Select Position…</option>'; return; }
    fetch('<?php echo $current_page; ?>?get_positions=1&dept_id=' + deptId)
        .then(function(r) { return r.json(); })
        .then(function(data) {
            posEl.innerHTML = '<option value="">Select Position…</option>';
            data.forEach(function(p) {
                posEl.innerHTML += '<option value="' + p.id + '" data-name="' + p.title + '">' + p.title + '</option>';
            });
            // Update position name on change
            posEl.onchange = function() {
                var opt = posEl.options[posEl.selectedIndex];
                if (document.getElementById(posNameId)) {
                    document.getElementById(posNameId).value = opt ? (opt.dataset.name || opt.text) : '';
                }
            };
        });
}

// ── Toggle trigger datetime ────────────────────────────────
var LOCATIONS_LIST = <?php echo json_encode($candidate_locations); ?>;

function toggleLocationOther(sel, otherId) {
    var box = document.getElementById(otherId);
    box.style.display = (sel.value === 'Other') ? 'block' : 'none';
    if (sel.value !== 'Other') box.value = '';
}

function setLocationField(prefix, value) {
    var sel = document.getElementById(prefix + '_location_select');
    var txt = document.getElementById(prefix + '_location_other');
    if (!sel || !txt) return;
    if (!value) { sel.value = ''; txt.style.display = 'none'; txt.value = ''; return; }
    if (LOCATIONS_LIST.indexOf(value) !== -1 && value !== 'Other') {
        sel.value = value;
        txt.style.display = 'none';
        txt.value = '';
    } else {
        sel.value = 'Other';
        txt.style.display = 'block';
        txt.value = value;
    }
}

var LANGUAGES_LIST = <?php echo json_encode($candidate_languages); ?>;

function toggleLangOther(otherId, checked) {
    var box = document.getElementById(otherId);
    box.style.display = checked ? 'block' : 'none';
    if (!checked) box.value = '';
}

// value = comma-separated string from the DB, e.g. "English, Tamil, French"
function setLanguageField(prefix, value) {
    var group = document.getElementById(prefix + '_language_group');
    var txt   = document.getElementById(prefix + '_language_known_other');
    if (!group || !txt) return;

    var checkboxes = group.querySelectorAll('input[type=checkbox]');
    checkboxes.forEach(function(cb) { cb.checked = false; });
    txt.style.display = 'none';
    txt.value = '';
    if (!value) return;

    var parts = value.split(',').map(function(s) { return s.trim(); }).filter(Boolean);
    var leftover = [];
    parts.forEach(function(p) {
        var matched = false;
        checkboxes.forEach(function(cb) {
            if (cb.value !== 'Other' && cb.value.toLowerCase() === p.toLowerCase()) {
                cb.checked = true;
                matched = true;
            }
        });
        if (!matched) leftover.push(p);
    });

    if (leftover.length) {
        var otherCb = group.querySelector('input[value="Other"]');
        if (otherCb) otherCb.checked = true;
        txt.style.display = 'block';
        txt.value = leftover.join(', ');
    }
}

function toggleTrigger(status) {
    var wrap = document.getElementById('trigger_wrap');
    var inp  = document.getElementById('status_trigger');
    var lbl  = document.getElementById('trigger_required_star');
    if (TRIGGER_STATUSES.indexOf(status) !== -1) {
        wrap.style.display = 'block';
        var isRequired = TRIGGER_REQUIRED_STATUSES.indexOf(status) !== -1;
        inp.required = isRequired;
        if (lbl) lbl.style.display = isRequired ? 'inline' : 'none';
    } else {
        wrap.style.display = 'none';
        inp.required = false;
    }
}

// ── Toggle rejection reason/round fields ────────────────────
function toggleRejectFields(status) {
    var wrap   = document.getElementById('reject_wrap');
    var reason = document.getElementById('reject_reason');
    if (status === 'Rejected') {
        wrap.style.display = 'block';
        reason.required = true;
    } else {
        wrap.style.display = 'none';
        reason.required = false;
    }
}

// ── Status dropdown in table row → opens Update Status modal pre-filled ──
function handleStatusDropdownChange(selectEl) {
    var id         = selectEl.dataset.id;
    var name       = selectEl.dataset.name;
    var newStatus  = selectEl.value;
    var current    = selectEl.dataset.current;

    // Visually snap the dropdown back to the saved status — the real change
    // only takes effect once the modal form is submitted (so mandatory date/
    // reason fields are always respected).
    selectEl.value = current;

    openStatus(id, name);
    // Give openStatus's fetch a moment to populate the modal, then force the
    // status dropdown inside the modal to the one the user picked in the table.
    setTimeout(function() {
        document.getElementById('status_select').value = newStatus;
        toggleTrigger(newStatus);
        toggleRejectFields(newStatus);
    }, 350);
}

// ── Open Status modal ──────────────────────────────────────
function openStatus(id, name) {
    document.getElementById('status_id').value    = id;
    document.getElementById('status_cname').textContent = name;
    document.querySelector('[name="notes"]').value   = '';
    document.getElementById('reject_reason').value = '';
    document.getElementById('reject_round').value  = '';
    setLanguageField('status', '');
    $('#statusModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('status_select').value = c.current_status || 'New';
            toggleTrigger(c.current_status || 'New');
            toggleRejectFields(c.current_status || 'New');
            document.getElementById('status_trigger').value = c.trigger_datetime ? c.trigger_datetime.replace(' ', 'T').substring(0,16) : '';
            setLanguageField('status', c.language_known || '');
            var noteWrap = document.getElementById('current_note_display');
            var noteText = document.getElementById('current_note_text');
            if (c.last_note) { noteText.textContent = c.last_note; noteWrap.style.display = 'block'; }
            else { noteWrap.style.display = 'none'; }
        });
}

// ── Open Edit modal ────────────────────────────────────────
function openEdit(id) {
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('edit_id').value    = c.id;
            document.getElementById('edit_name').value  = c.name;
            document.getElementById('edit_phone').value = c.phone;
            document.getElementById('edit_email').value = c.email || '';
            setLocationField('edit', c.location || '');
            setLanguageField('edit', c.language_known || '');
            var deptEl = document.getElementById('edit_dept');
            deptEl.value = c.department_id;
            if (document.getElementById('edit_dept_name')) document.getElementById('edit_dept_name').value = c.department_name;
            // Load positions then select
            fetch('<?php echo $current_page; ?>?get_positions=1&dept_id=' + c.department_id)
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    var posEl = document.getElementById('edit_pos');
                    posEl.innerHTML = '<option value="">Select Position…</option>';
                    data.forEach(function(p) {
                        posEl.innerHTML += '<option value="' + p.id + '" data-name="' + p.title + '"' + (p.id == c.position_id ? ' selected' : '') + '>' + p.title + '</option>';
                    });
                    if (document.getElementById('edit_pos_name')) document.getElementById('edit_pos_name').value = c.position_name;
                    posEl.onchange = function() {
                        var opt = posEl.options[posEl.selectedIndex];
                        document.getElementById('edit_pos_name').value = opt ? (opt.dataset.name || opt.text) : '';
                    };
                });
            $('#editModal').modal('show');
        });
}

// ── Open View modal ────────────────────────────────────────
function openView(id) {
    document.getElementById('viewBody').innerHTML = '<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--primary)"></i></div>';
    document.getElementById('view_name').textContent = '';
    $('#viewModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('view_name').textContent = c.name;
            var sc  = STATUS_COLORS[c.current_status] || '#6b7280';
            var tdt = c.trigger_datetime ? new Date(c.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) : '—';
            var resumeBtn = c.resume_path
                ? '<a href="' + c.resume_path + '" target="_blank" class="doc-dl-btn"><i class="fas fa-file-alt"></i> ' + (c.resume_name || 'Download Resume') + '</a>'
                : '<span style="color:var(--muted);font-size:13px;">No resume uploaded</span>';
            var jdBtn = c.jd_path
                ? '<a href="' + c.jd_path + '" target="_blank" class="doc-dl-btn jd"><i class="fas fa-file-contract"></i> ' + (c.jd_name || 'Download JD') + '</a>'
                : '<span style="color:var(--muted);font-size:13px;">No JD uploaded</span>';
            var html = [
                row('Department',  c.department_name || '—'),
                row('Position',    c.position_name   || '—'),
                row('Location',    c.location || '—'),
                row('Language Known', c.language_known || '—'),
                row('Phone',       c.phone),
                row('Email',       c.email || '—'),
                row('Status',      '<span class="status-badge" style="background:' + sc + '">' + c.current_status + '</span>' + (c.current_status === 'Rejected' && c.rejected_round ? '<div style="font-size:12px;color:#dc2626;font-weight:700;margin-top:5px;"><i class="fas fa-flag mr-1"></i>' + c.rejected_round + '</div>' : '')),
                row('Trigger Date/Time', '<span style="color:var(--warning);font-weight:700;">' + tdt + '</span>'),
                row('Last Note',   c.last_note || '—'),
                row('Last Updated By', c.last_updated_by || '—'),
                row('Added By',    c.created_by || '—'),
                row('Added On',    c.created_at || '—'),
                row('Resume',      resumeBtn),
                row('Job Description', jdBtn),
            ].join('');
            document.getElementById('viewBody').innerHTML = html;
        });
}

function row(label, val) {
    return '<div class="detail-row"><div class="detail-label">' + label + '</div><div class="detail-value">' + val + '</div></div>';
}

// ── Open Log modal ─────────────────────────────────────────
function openLog(id, name) {
    document.getElementById('log_cname').textContent = name;
    document.getElementById('logTimeline').innerHTML = '<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--warning)"></i></div>';
    $('#logModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_log=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(logs) {
            if (!logs.length) {
                document.getElementById('logTimeline').innerHTML = '<div style="text-align:center;padding:40px;color:var(--muted);"><i class="fas fa-inbox fa-2x" style="opacity:.3;margin-bottom:10px;display:block;"></i>No history yet.</div>';
                return;
            }
            var sc_map = STATUS_COLORS;
            var html = logs.map(function(l) {
                var sc  = sc_map[l.status] || '#6b7280';
                var tdt = l.trigger_datetime ? new Date(l.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) : '';
                var dt  = new Date(l.updated_at).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'});
                return '<div class="log-item">' +
                    '<div class="log-dot" style="background:' + sc + '"><i class="fas fa-circle" style="font-size:10px;"></i></div>' +
                    '<div class="log-body">' +
                    '<div class="log-status"><span class="status-badge" style="background:' + sc + ';font-size:11px;">' + l.status + '</span></div>' +
                    (l.notes ? '<div class="log-note" style="margin-top:8px;">' + escHtml(l.notes) + '</div>' : '') +
                    (tdt ? '<div class="log-trigger"><i class="fas fa-calendar-check mr-1"></i>Scheduled: ' + tdt + '</div>' : '') +
                    '<div class="log-meta"><i class="fas fa-user mr-1"></i>' + escHtml(l.updated_by) + ' &nbsp;•&nbsp; <i class="fas fa-clock mr-1"></i>' + dt + '</div>' +
                    '</div></div>';
            }).join('');
            document.getElementById('logTimeline').innerHTML = html;
        });
}

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Open WhatsApp modal ────────────────────────────────────
function openWhatsApp(id) {
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            var tdt = c.trigger_datetime
                ? new Date(c.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit',hour12:true})
                : 'the scheduled time';
            var statusLabel = c.current_status;
            // Build a natural-language label for the scheduled event
            var eventLabel = 'follow-up call';
            if (statusLabel === 'Scheduled') eventLabel = 'interview / meeting';
            else if (statusLabel === 'Callback') eventLabel = 'callback call';
            else if (statusLabel === 'Call Later') eventLabel = 'call';
            else if (statusLabel === 'Follow Up') eventLabel = 'follow-up call';
            var msg = 'Hi ' + c.name + ',\n\n' +
                      'This is a friendly reminder from ' + COMPANY_NAME + '.\n\n' +
                      'Your ' + eventLabel + ' is scheduled on:\n' +
                      '\uD83D\uDCC5 ' + tdt + '\n\n' +
                      'Please make sure you are available at that time. Looking forward to connecting with you!\n\n' +
                      'Regards,\n' + HR_NAME + '\n' + COMPANY_NAME + ' — HR Team';
            document.getElementById('waPreview').textContent = msg;
            document.getElementById('waPhone').textContent   = c.phone;
            // Clean phone: remove spaces, dashes, +91 etc → keep digits
            var cleanPhone = c.phone.replace(/\D/g,'');
            // If Indian number without country code, prepend 91
            if (cleanPhone.length === 10) cleanPhone = '91' + cleanPhone;
            var waUrl = 'https://wa.me/' + cleanPhone + '?text=' + encodeURIComponent(msg);
            document.getElementById('waLink').href = waUrl;
            $('#waModal').modal('show');
        });
}

// ── Delete ─────────────────────────────────────────────────
function doDelete(id, name) {
    if (!confirm('Delete candidate "' + name + '"?\n\nThis will permanently remove the candidate and all their history. This cannot be undone.')) return;
    document.getElementById('delete_id').value = id;
    document.getElementById('deleteForm').submit();
}

// ── Template-driven Notify system ───────────────────────────
var _notifyWAPhone        = '';
var _notifyCtx             = null;   // candidate context: {id,name,phone,phone_clean,email,status,tdt,department,position}
var _currentRawTemplateBody = '';    // last used template/custom body (with placeholders resolved for preview)
var _isCustomFlow          = false;
var _templatesCache        = null;   // cached array of templates from server

function capitalizeFirst(str) {
    if (!str) return str;
    str = str.trim();
    return str.charAt(0).toUpperCase() + str.slice(1);
}

function splitDateTime(tdt) {
    if (!tdt) return { date: 'Not yet scheduled', time: '' };
    var parts = tdt.split(',');
    if (parts.length >= 2) return { date: parts[0].trim(), time: parts.slice(1).join(',').trim() };
    return { date: tdt, time: '' };
}

// Fallback body used for the free-typed "Other" option
function buildReminderMsg(name, status, tdt, senderName) {
    var dt = splitDateTime(tdt);
    var sender = capitalizeFirst(senderName || HR_NAME);
    return 'Hi ' + name + ',\n\n' +
        'Greetings from ' + COMPANY_NAME + '.\n' +
        'This is a friendly reminder regarding your scheduled follow-up call.\n\n' +
        'Our HR team will contact you on:\n' +
        'Date: ' + dt.date + '\n' +
        'Time: ' + dt.time + '\n\n' +
        'Kindly ensure that you are available to receive the call at the scheduled time. If you are unavailable, please let us know in advance.\n\n' +
        'We look forward to speaking with you.\n\n' +
        'Regards,\n' + sender + '\n' +
        'HR Team\n' +
        COMPANY_NAME;
}

// Replace {name} {position} {department} {company} {date} {time} {phone} {sender} in a template body
function fillPlaceholders(text, ctx, senderOverride) {
    var dt = splitDateTime(ctx.tdt);
    var sender = capitalizeFirst(senderOverride || HR_NAME);
    return String(text || '')
        .replace(/\{name\}/gi, ctx.name || '')
        .replace(/\{position\}/gi, ctx.position || '—')
        .replace(/\{department\}/gi, ctx.department || '—')
        .replace(/\{company\}/gi, COMPANY_NAME || '')
        .replace(/\{date\}/gi, dt.date || '')
        .replace(/\{time\}/gi, dt.time || '')
        .replace(/\{phone\}/gi, ctx.phone || '')
        .replace(/\{sender\}/gi, sender);
}

function loadTemplatesCache(callback) {
    if (_templatesCache) { callback(_templatesCache); return; }
    fetch('<?php echo $current_page; ?>?get_templates=1')
        .then(function(r) { return r.json(); })
        .then(function(data) { _templatesCache = data; callback(data); });
}

// ── Step 1: Template Picker ─────────────────────────────────
function openTemplatePicker(ctx) {
    _notifyCtx = ctx;
    document.getElementById('tpl_pick_cname').textContent = ctx.name;
    document.getElementById('tplSearchInput').value = '';
    $('#alertModal').modal('hide');
    setTimeout(function() {
        $('#templatePickerModal').modal('show');
        _templatesCache = null; // refresh each time in case templates changed
        loadTemplatesCache(function() { renderTemplatePickerList(''); });
    }, 250);
}

function renderTemplatePickerList(filterText) {
    var listEl = document.getElementById('tplPickerList');
    var q = (filterText || '').toLowerCase().trim();
    var templates = (_templatesCache || []).filter(function(t) {
        if (!q) return true;
        var hay = (t.title + ' ' + t.statuses.join(' ') + ' ' + t.body).toLowerCase();
        return hay.indexOf(q) !== -1;
    });

    var html = '';
    // "Other / type your own" always shown first
    html += '<div onclick="pickCustomTemplate()" style="cursor:pointer;background:#fffbeb;border:2px dashed #fbbf24;border-radius:10px;padding:14px 16px;margin-bottom:12px;">' +
        '<div style="font-weight:700;color:#92400e;"><i class="fas fa-pen mr-2"></i>Other — Type your own message</div>' +
        '<div style="font-size:12px;color:#92400e;opacity:.8;margin-top:3px;">Skip templates and write a custom message for this candidate.</div>' +
        '</div>';

    if (!templates.length) {
        if (q) {
            html += '<div style="text-align:center;padding:24px;color:var(--muted);">No templates match "' + escHtml(filterText) + '".</div>';
        } else {
            html += '<div style="text-align:center;padding:24px;color:var(--muted);">No templates yet — use "Manage Templates" to create one, or pick "Other" above.</div>';
        }
    } else {
        templates.forEach(function(t) {
            var badges = t.statuses.map(function(s) {
                var c = STATUS_COLORS[s] || '#6366f1';
                return '<span style="background:' + c + ';color:#fff;font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;margin-right:4px;">' + escHtml(s) + '</span>';
            }).join('');
            var preview = t.body.length > 110 ? t.body.substring(0,110) + '…' : t.body;
            html += '<div onclick=\'pickTemplate(' + t.id + ')\' style="cursor:pointer;background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:14px 16px;margin-bottom:10px;transition:.15s;" onmouseover="this.style.borderColor=\'#f59e0b\'" onmouseout="this.style.borderColor=\'#e2e8f0\'">' +
                '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;">' +
                '<div style="font-weight:700;color:var(--primary);">' + escHtml(t.title) + '</div>' +
                '<div>' + badges + '</div>' +
                '</div>' +
                '<div style="font-size:12.5px;color:var(--muted);margin-top:6px;white-space:pre-wrap;">' + escHtml(preview) + '</div>' +
                '</div>';
        });
    }
    listEl.innerHTML = html;
}

document.getElementById('tplSearchInput') && document.getElementById('tplSearchInput').addEventListener('input', function() {
    renderTemplatePickerList(this.value);
});

function pickTemplate(id) {
    var tpl = (_templatesCache || []).find(function(t) { return t.id == id; });
    if (!tpl) return;
    _isCustomFlow = false;
    $('#templatePickerModal').modal('hide');
    setTimeout(function() { showNotifyModal(tpl.body, false); }, 300);
}

function pickCustomTemplate() {
    _isCustomFlow = true;
    var defaultBody = buildReminderMsg(_notifyCtx.name, _notifyCtx.status, _notifyCtx.tdt, HR_NAME);
    $('#templatePickerModal').modal('hide');
    setTimeout(function() { showNotifyModal(defaultBody, true); }, 300);
}

// ── Step 2: Final Notify Modal (Email + WhatsApp) ───────────
function showNotifyModal(rawBody, isCustom) {
    var ctx = _notifyCtx;
    _notifyWAPhone = ctx.phone_clean || ctx.phone;
    _currentRawTemplateBody = rawBody;

    document.getElementById('notify_cname').textContent = ctx.name;
    document.getElementById('notify_email_to').value    = ctx.email || '';
    document.getElementById('notify_email_subject').value = 'Message from ' + COMPANY_NAME + ' HR';
    document.getElementById('notify_sender_name').value = capitalizeFirst(HR_NAME);
    document.getElementById('notify_name_hidden').value = ctx.name;
    document.getElementById('notify_tdt_hidden').value  = ctx.tdt;

    var msg = fillPlaceholders(rawBody, ctx, HR_NAME);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    document.getElementById('notify_wa_phone_display').textContent = ctx.phone;
    document.getElementById('notify_email_status').textContent = '';

    var saveBox = document.getElementById('saveAsTemplateBox');
    if (isCustom) {
        saveBox.style.display = 'block';
        document.getElementById('saveAsTemplateCheck').checked = false;
        document.getElementById('saveAsTemplateFields').style.display = 'none';
        document.getElementById('saveAsTemplateTitle').value = '';
        document.getElementById('saveAsTemplateStatusLabel').textContent = ctx.status;
    } else {
        saveBox.style.display = 'none';
    }

    updateWALink();
    $('#notifyModal').modal('show');
}

function regenerateNotifyMessages() {
    var sender = document.getElementById('notify_sender_name').value;
    var msg = fillPlaceholders(_currentRawTemplateBody, _notifyCtx, sender);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    updateWALink();
}

function updateWALink() {
    var msg = document.getElementById('notify_wa_body').value;
    var waUrl = 'https://wa.me/' + _notifyWAPhone + '?text=' + encodeURIComponent(msg);
    document.getElementById('notify_wa_link').href = waUrl;
}
document.getElementById('notify_wa_body') && document.getElementById('notify_wa_body').addEventListener('input', updateWALink);

// Called after Send (Email or WhatsApp) if this was a custom "Other" message
function maybeSaveAsTemplate(sentBody) {
    if (!_isCustomFlow) return;
    var check = document.getElementById('saveAsTemplateCheck');
    if (!check || !check.checked) return;
    var title = document.getElementById('saveAsTemplateTitle').value.trim();
    if (!title) { alert('Please enter a template title to save it.'); return; }

    var fd = new FormData();
    fd.append('action', 'save_template');
    fd.append('title', title);
    fd.append('body', sentBody);
    fd.append('statuses[]', _notifyCtx.status);

    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                _templatesCache = null; // force refresh next time picker opens
                check.checked = false;
            }
        });
}

// ── Manage Templates modal ──────────────────────────────────
function buildStatusChecks(selectedList) {
    selectedList = selectedList || [];
    var wrap = document.getElementById('tpl_status_checks');
    var opts = ['General'].concat(ALL_STATUSES);
    wrap.innerHTML = opts.map(function(s) {
        var checked = selectedList.indexOf(s) !== -1 ? 'checked' : '';
        var id = 'tplstat_' + s.replace(/[^a-zA-Z0-9]/g,'_');
        return '<label style="font-size:12.5px;font-weight:600;display:flex;align-items:center;gap:5px;cursor:pointer;">' +
            '<input type="checkbox" value="' + escHtml(s) + '" ' + checked + ' id="' + id + '"> ' + escHtml(s) +
            '</label>';
    }).join('');
}

function getCheckedStatuses() {
    return Array.from(document.querySelectorAll('#tpl_status_checks input[type=checkbox]:checked')).map(function(i){ return i.value; });
}

function openManageTemplates() {
    resetTemplateForm();
    $('#manageTemplatesModal').modal('show');
    _templatesCache = null;
    loadTemplatesCache(renderManageList);
}

function renderManageList(templates) {
    var el = document.getElementById('tplManageList');
    if (!templates.length) {
        el.innerHTML = '<div style="text-align:center;padding:24px;color:var(--muted);">No templates created yet.</div>';
        return;
    }
    el.innerHTML = templates.map(function(t) {
        var badges = t.statuses.map(function(s) {
            var c = STATUS_COLORS[s] || '#6366f1';
            return '<span style="background:' + c + ';color:#fff;font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;margin-right:4px;">' + escHtml(s) + '</span>';
        }).join('');
        return '<div style="background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:14px 16px;margin-bottom:10px;">' +
            '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;">' +
            '<div><div style="font-weight:700;color:var(--primary);">' + escHtml(t.title) + '</div><div style="margin-top:5px;">' + badges + '</div></div>' +
            '<div style="white-space:nowrap;">' +
            '<button class="act-btn act-edit" title="Edit" onclick=\'editTemplate(' + t.id + ')\'><i class="fas fa-edit"></i></button>' +
            '<button class="act-btn act-del" title="Delete" onclick=\'deleteTemplate(' + t.id + ', "' + escHtml(t.title).replace(/"/g,'&quot;') + '")\'><i class="fas fa-trash"></i></button>' +
            '</div></div>' +
            '<div style="font-size:12.5px;color:var(--muted);margin-top:8px;white-space:pre-wrap;">' + escHtml(t.body) + '</div>' +
            '</div>';
    }).join('');
}

function editTemplate(id) {
    var tpl = (_templatesCache || []).find(function(t) { return t.id == id; });
    if (!tpl) return;
    document.getElementById('tpl_edit_id').value = tpl.id;
    document.getElementById('tpl_title').value = tpl.title;
    document.getElementById('tpl_body').value = tpl.body;
    buildStatusChecks(tpl.statuses);
    document.getElementById('tpl_save_btn').innerHTML = '<i class="fas fa-save mr-1"></i> Update Template';
    document.getElementById('tpl_cancel_edit_btn').style.display = 'inline-block';
    document.getElementById('tpl_title').scrollIntoView({behavior:'smooth', block:'center'});
}

function resetTemplateForm() {
    document.getElementById('tpl_edit_id').value = '';
    document.getElementById('tpl_title').value = '';
    document.getElementById('tpl_body').value = '';
    buildStatusChecks(['General']);
    document.getElementById('tpl_save_btn').innerHTML = '<i class="fas fa-save mr-1"></i> Save Template';
    document.getElementById('tpl_cancel_edit_btn').style.display = 'none';
}

function saveTemplate() {
    var id     = document.getElementById('tpl_edit_id').value;
    var title  = document.getElementById('tpl_title').value.trim();
    var body   = document.getElementById('tpl_body').value.trim();
    var statuses = getCheckedStatuses();
    if (!title || !body) { alert('Title and message body are required.'); return; }

    var fd = new FormData();
    fd.append('action', 'save_template');
    if (id) fd.append('id', id);
    fd.append('title', title);
    fd.append('body', body);
    if (!statuses.length) statuses = ['General'];
    statuses.forEach(function(s) { fd.append('statuses[]', s); });

    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                resetTemplateForm();
                _templatesCache = null;
                loadTemplatesCache(renderManageList);
            } else {
                alert(res.error || 'Failed to save template.');
            }
        });
}

function deleteTemplate(id, title) {
    if (!confirm('Delete template "' + title + '"?')) return;
    var fd = new FormData();
    fd.append('action', 'delete_template');
    fd.append('id', id);
    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                _templatesCache = null;
                loadTemplatesCache(renderManageList);
            }
        });
}

// ── Manage Custom Statuses modal ─────────────────────────────
function openManageStatuses() {
    document.getElementById('newStatusName').value = '';
    $('#manageStatusesModal').modal('show');
    loadCustomStatusList();
}

function loadCustomStatusList() {
    fetch('<?php echo $current_page; ?>?get_custom_statuses=1')
        .then(function(r) { return r.json(); })
        .then(renderCustomStatusList);
}

function renderCustomStatusList(list) {
    var el = document.getElementById('customStatusList');
    if (!list.length) {
        el.innerHTML = '<div style="text-align:center;padding:20px;color:var(--muted);">No custom statuses added yet.</div>';
        return;
    }
    el.innerHTML = list.map(function(s) {
        return '<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border:1px solid var(--border);border-radius:8px;margin-bottom:8px;">' +
            '<span style="font-weight:700;">' + escHtml(s.name) + '</span>' +
            '<button class="act-btn act-del" title="Delete" onclick=\'deleteCustomStatus(' + s.id + ', "' + escHtml(s.name).replace(/"/g,'&quot;') + '")\'><i class="fas fa-trash"></i></button>' +
            '</div>';
    }).join('');
}

function addCustomStatus() {
    var name = document.getElementById('newStatusName').value.trim();
    if (!name) { alert('Please enter a status name.'); return; }
    var fd = new FormData();
    fd.append('action', 'add_custom_status');
    fd.append('name', name);
    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                location.reload();
            } else {
                alert(res.error || 'Failed to add status.');
            }
        });
}

function deleteCustomStatus(id, name) {
    if (!confirm('Delete custom status "' + name + '"? Candidates already on this status will keep it, but it will no longer be selectable going forward.')) return;
    var fd = new FormData();
    fd.append('action', 'delete_custom_status');
    fd.append('id', id);
    fetch('<?php echo $current_page; ?>', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                location.reload();
            } else {
                alert(res.error || 'Failed to delete status.');
            }
        });
}

function sendNotifyEmail() {
    var to      = document.getElementById('notify_email_to').value.trim();
    var subject = document.getElementById('notify_email_subject').value.trim();
    var body    = document.getElementById('notify_email_body').value.trim();
    var statusEl = document.getElementById('notify_email_status');
    if (!to) { alert('Please enter the candidate email address.'); return; }
    if (!confirm('Send email to ' + to + '?')) return;
    statusEl.textContent = 'Sending...';
    statusEl.style.color = 'var(--muted)';
    var mailtoUrl = 'mailto:' + encodeURIComponent(to)
        + '?subject=' + encodeURIComponent(subject)
        + '&body=' + encodeURIComponent(body);
    window.open(mailtoUrl, '_blank');
    statusEl.textContent = 'Email client opened!';
    statusEl.style.color = 'var(--success)';
    maybeSaveAsTemplate(body);
}

// ── Auto-dismiss alerts ────────────────────────────────────
setTimeout(function() { $('.alert').fadeOut('slow'); }, 6000);

function applyAlertFilter() {
    var from = document.getElementById('alertDateFrom').value;
    var to   = document.getElementById('alertDateTo').value;
    var status = document.getElementById('alertStatusFilter').value;
    document.querySelectorAll('.alert-card-item').forEach(function(card) {
        var show = true;
        if (from && card.dataset.tdate < from) show = false;
        if (to   && card.dataset.tdate > to)   show = false;
        if (status && card.dataset.status !== status) show = false;
        card.style.display = show ? '' : 'none';
    });
}

function resetAlertFilterToday() {
    var today = new Date().toISOString().split('T')[0];
    document.getElementById('alertDateFrom').value = today;
    document.getElementById('alertDateTo').value = today;
    document.getElementById('alertStatusFilter').value = '';
    applyAlertFilter();
}

function csvField(v) {
    return '"' + String(v || '').replace(/"/g,'""').trim() + '"';
}

function exportAlertCSV() {
    var csv = [['Name','Phone','Department','Position','Status','Trigger Date/Time','Note'].map(csvField).join(',')];
    document.querySelectorAll('.alert-card-item').forEach(function(card) {
        if (card.style.display === 'none') return;
        var d = card.dataset;
        var line = [d.name, d.phone, d.dept, d.pos, d.status, d.tdt, d.note].map(csvField);
        csv.push(line.join(','));
    });
    var blob = new Blob(['\ufeff' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'Upcoming_Followups.csv';
    a.click();
}

// Bootstrap only locks scroll on <body>; this page's real scrollbar is on
// <html>, so mirror the lock there too or the background keeps scrolling.
$(document).on('show.bs.modal', '.modal', function() {
    document.documentElement.classList.add('modal-open');
});
$(document).on('hidden.bs.modal', '.modal', function() {
    if (!$('.modal.show').length) {
        document.documentElement.classList.remove('modal-open');
    }
});

$('#alertModal').on('shown.bs.modal', function() {
    if (!window._alertFilterInit) {
        window._alertFilterInit = true;
        resetAlertFilterToday();
    }
});

<?php if (!empty($import_res)): ?>
$(document).ready(function() {
    $('#importResultsModal').modal('show');
});
<?php endif; ?>
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
