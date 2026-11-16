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

// =========================================================================
// HR ONBOARDING CHECKLIST — EMPLOYEE + HR COMBINED VIEW
// Auto-assembles a per-employee checklist (Department-level + Position-level
// items) the moment a candidate's decision flips to "hired", and lets both
// the employee and HR track / check off progress against it.
// =========================================================================

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page    = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// CONFIG — Schema variables (confirmed against hr_screenings table)
// =========================================================================
$CANDIDATES_TABLE  = 'hr_screenings';   // table that holds candidates/employees
$CAND_ID_COL       = 'id';
$CAND_NAME_COL     = 'candidate_name';  // full name column
$CAND_DEPT_COL     = 'department';      // column that stores the department name (string)
$CAND_POS_COL      = 'position_id';
$CAND_DECISION_COL = 'hr_decision';     // column that stores the decision
$HIRED_VALUE       = 'hired';           // exact value meaning "hired"

// How do we tell HR staff apart from a logged-in Employee?
// Anyone accessing this via the CRM dashboard without a candidate session is an HR user.
$is_hr_user = !isset($_SESSION['candidate_id']);

// If the logged-in person is the Employee (not HR), we need their own
// candidate_id from session to show only THEIR checklist(s). candidate_type
// disambiguates which table that id belongs to (see hr_checklist_runs.candidate_type)
// — without it, two different people sharing the same numeric id across the
// hr_employees/hr_screenings tables could see each other's checklist.
$logged_in_candidate_id   = isset($_SESSION['candidate_id']) ? intval($_SESSION['candidate_id']) : 0;
$logged_in_candidate_type = isset($_SESSION['candidate_type']) ? $_SESSION['candidate_type'] : 'screening';

// Absolute base URL for this exact script — used for all view_item links so they never
// inherit a broken/duplicated path from whatever page the click originated on.
$view_item_base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm' . '/hr-checklist.php';

// =========================================================================
// ENSURE TABLES EXIST
// =========================================================================
$check_runs = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_runs'");
if (mysqli_num_rows($check_runs) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_runs (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        candidate_id INT(11) NOT NULL,
        candidate_name VARCHAR(255) DEFAULT NULL,
        department_id INT(11) NOT NULL,
        department_name VARCHAR(255) DEFAULT NULL,
        position_id INT(11) NOT NULL,
        position_name VARCHAR(255) DEFAULT NULL,
        status VARCHAR(20) DEFAULT 'in_progress',
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        completed_at DATETIME DEFAULT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

$check_run_items = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_run_items'");
if (mysqli_num_rows($check_run_items) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_run_items (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        run_id INT(11) NOT NULL,
        heading_name VARCHAR(255) NOT NULL,
        heading_sort INT(11) DEFAULT 0,
        scope_level VARCHAR(20) DEFAULT 'department',
        item_id INT(11) DEFAULT NULL,
        item_text VARCHAR(500) NOT NULL,
        description TEXT DEFAULT NULL,
        document_path VARCHAR(500) DEFAULT NULL,
        document_filename VARCHAR(255) DEFAULT NULL,
        video_path VARCHAR(500) DEFAULT NULL,
        video_filename VARCHAR(255) DEFAULT NULL,
        item_sort INT(11) DEFAULT 0,
        is_checked TINYINT(1) DEFAULT 0,
        checked_by_type VARCHAR(20) DEFAULT NULL,
        checked_by_name VARCHAR(255) DEFAULT NULL,
        checked_at DATETIME DEFAULT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// Add new columns if table already existed before this update
$col_checks_run = [
    ["hr_checklist_run_items", "visible_to_employee", "ALTER TABLE hr_checklist_run_items ADD COLUMN visible_to_employee TINYINT(1) DEFAULT 0 AFTER item_sort"],
    ["hr_checklist_run_items", "require_signature",   "ALTER TABLE hr_checklist_run_items ADD COLUMN require_signature TINYINT(1) DEFAULT 0 AFTER visible_to_employee"],
    ["hr_checklist_run_items", "signature_data",      "ALTER TABLE hr_checklist_run_items ADD COLUMN signature_data LONGTEXT DEFAULT NULL AFTER require_signature"],
    ["hr_checklist_run_items", "item_type",           "ALTER TABLE hr_checklist_run_items ADD COLUMN item_type VARCHAR(30) DEFAULT 'tick' AFTER signature_data"],
    ["hr_checklist_run_items", "field_schema",        "ALTER TABLE hr_checklist_run_items ADD COLUMN field_schema LONGTEXT DEFAULT NULL AFTER item_type"],
    ["hr_checklist_run_items", "filled_data",         "ALTER TABLE hr_checklist_run_items ADD COLUMN filled_data LONGTEXT DEFAULT NULL AFTER field_schema"],
    ["hr_checklist_run_items", "approval_status",      "ALTER TABLE hr_checklist_run_items ADD COLUMN approval_status VARCHAR(20) DEFAULT NULL AFTER filled_data"],
    ["hr_checklist_run_items", "rejection_reason",     "ALTER TABLE hr_checklist_run_items ADD COLUMN rejection_reason TEXT DEFAULT NULL AFTER approval_status"],
    ["hr_checklist_run_items", "reviewed_by",          "ALTER TABLE hr_checklist_run_items ADD COLUMN reviewed_by VARCHAR(255) DEFAULT NULL AFTER rejection_reason"],
    ["hr_checklist_run_items", "reviewed_at",          "ALTER TABLE hr_checklist_run_items ADD COLUMN reviewed_at DATETIME DEFAULT NULL AFTER reviewed_by"],
    ["hr_checklist_runs", "final_signature_data",     "ALTER TABLE hr_checklist_runs ADD COLUMN final_signature_data LONGTEXT DEFAULT NULL AFTER completed_at"],
    ["hr_checklist_runs", "final_signed_by",          "ALTER TABLE hr_checklist_runs ADD COLUMN final_signed_by VARCHAR(255) DEFAULT NULL AFTER final_signature_data"],
    ["hr_checklist_runs", "final_signed_at",          "ALTER TABLE hr_checklist_runs ADD COLUMN final_signed_at DATETIME DEFAULT NULL AFTER final_signed_by"],
    // candidate_id is overloaded — it stores an hr_employees.id for pre-existing
    // employees and an hr_screenings.id for screening-flow hires, with nothing to
    // tell the two apart. Two unrelated people whose IDs happen to collide across
    // those tables end up seeing each other's checklist. This column disambiguates
    // which table a given candidate_id actually refers to.
    ["hr_checklist_runs", "candidate_type",           "ALTER TABLE hr_checklist_runs ADD COLUMN candidate_type ENUM('employee','screening') DEFAULT NULL AFTER candidate_id"],
];
foreach ($col_checks_run as [$tbl, $col, $sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $sql);
}

// One-time backfill for existing rows created before candidate_type existed —
// only touches rows still NULL, so this is cheap/no-op on every load after the
// first. Matches on candidate_id AND candidate_name together against each
// source table, so a collision (two different people sharing the same numeric
// candidate_id from two different tables) still resolves each run correctly,
// since only the genuinely matching table will also match the stored name.
mysqli_query($con, "UPDATE hr_checklist_runs r
    LEFT JOIN hr_employees e ON e.id = r.candidate_id AND LOWER(TRIM(e.name)) = LOWER(TRIM(r.candidate_name))
    LEFT JOIN hr_screenings s ON s.id = r.candidate_id AND LOWER(TRIM(s.candidate_name)) = LOWER(TRIM(r.candidate_name))
    SET r.candidate_type = CASE WHEN e.id IS NOT NULL THEN 'employee' WHEN s.id IS NOT NULL THEN 'screening' ELSE NULL END
    WHERE r.candidate_type IS NULL AND (e.id IS NOT NULL OR s.id IS NOT NULL)");

// =========================================================================
// HELPERS
// =========================================================================

function create_checklist_run($con, $cand_id, $cand_name, $dept_id, $pos_id, $created_by) {
    $dept_id_e = intval($dept_id);
    $pos_id_e  = intval($pos_id);

    $dept_name_r = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id_e"));
    $pos_name_r  = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id_e"));
    $dept_name = $dept_name_r ? $dept_name_r['name'] : '';
    $pos_name  = $pos_name_r ? $pos_name_r['title'] : '';

    $cand_id_e    = intval($cand_id);
    $cand_name_e  = mysqli_real_escape_string($con, $cand_name);
    $dept_name_e  = mysqli_real_escape_string($con, $dept_name);
    $pos_name_e   = mysqli_real_escape_string($con, $pos_name);
    $created_by_e = mysqli_real_escape_string($con, $created_by);

    // This function always sources $cand_id from $CANDIDATES_TABLE ('hr_screenings'),
    // so every run it creates is definitively the 'screening' candidate_type.
    mysqli_query($con, "INSERT INTO hr_checklist_runs
        (candidate_id, candidate_type, candidate_name, department_id, department_name, position_id, position_name, status, created_by)
        VALUES ($cand_id_e, 'screening', '$cand_name_e', $dept_id_e, '$dept_name_e', $pos_id_e, '$pos_name_e', 'in_progress', '$created_by_e')");
    $run_id = mysqli_insert_id($con);

    // Merge ALL global headings and items, snapshot them
    $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($h_res)) {
        $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . intval($h['id']) . " AND is_active=1 ORDER BY sort_order ASC, id ASC");
        while ($it = mysqli_fetch_assoc($i_res)) {
            $heading_name_e = mysqli_real_escape_string($con, $h['heading_name']);
            $item_text_e    = mysqli_real_escape_string($con, $it['item_text']);
            $desc_e         = mysqli_real_escape_string($con, $it['description'] ?? '');
            $doc_path_sql   = $it['document_path']     ? "'" . mysqli_real_escape_string($con, $it['document_path']) . "'"     : "NULL";
            $doc_fname_sql  = $it['document_filename']  ? "'" . mysqli_real_escape_string($con, $it['document_filename']) . "'"  : "NULL";
            $vid_path_sql   = $it['video_path']         ? "'" . mysqli_real_escape_string($con, $it['video_path']) . "'"         : "NULL";
            $vid_fname_sql  = $it['video_filename']     ? "'" . mysqli_real_escape_string($con, $it['video_filename']) . "'"      : "NULL";

            $vis_emp_snap = intval($it['visible_to_employee'] ?? 0);
            $req_sig_snap = intval($it['require_signature'] ?? 0);
            $item_type_snap = mysqli_real_escape_string($con, $it['item_type'] ?? 'tick');
            $field_schema_snap = !empty($it['field_schema']) ? "'" . mysqli_real_escape_string($con, $it['field_schema']) . "'" : "NULL";
            mysqli_query($con, "INSERT INTO hr_checklist_run_items
                (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature, item_type, field_schema)
                VALUES ($run_id, '$heading_name_e', " . intval($h['sort_order']) . ", 'global', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ", $vis_emp_snap, $req_sig_snap, '$item_type_snap', $field_schema_snap)");
        }
    }
    return $run_id;
}

function getRunCompanySettings($con, $candidate_id, $candidate_type = null) {
    if ($candidate_id <= 0) return [];

    // When the run's candidate_type is known, go straight to the right table
    // instead of guessing — candidate_id alone is ambiguous between the two
    // ID systems sharing this column (see hr_checklist_runs.candidate_type).
    $try_screening = ($candidate_type === null || $candidate_type === 'screening');
    $try_employee  = ($candidate_type === null || $candidate_type === 'employee');

    if ($try_screening) {
        $q = "SELECT cs.*, hc.company_name as live_company_name FROM hr_screenings s
              JOIN hr_offer_company_settings cs ON cs.company_id = s.company_id
              LEFT JOIN hr_companies hc ON hc.id = cs.company_id
              WHERE s.id = " . intval($candidate_id) . " LIMIT 1";
        $res = mysqli_query($con, $q);
        $r = $res ? mysqli_fetch_assoc($res) : null;
        if ($r) {
            if (!empty($r['live_company_name'])) $r['company_name'] = $r['live_company_name'];
            if (empty($r['company_signature']) && !empty($r['signature_path'])) $r['company_signature'] = $r['signature_path'];
            return $r;
        }
    }

    if (!$try_employee) return [];

    $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT company_name FROM hr_employees WHERE id=" . intval($candidate_id) . " LIMIT 1"));
    if ($emp && !empty($emp['company_name'])) {
        $cname_e = mysqli_real_escape_string($con, $emp['company_name']);

        // Resolve the master company row FIRST (strict identity source of truth)
        $hc_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$cname_e')) LIMIT 1"));
        if ($hc_row) {
            // Strict ID-based join: only settings rows actually linked to this exact company_id
            $r2 = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_id=" . intval($hc_row['id']) . " LIMIT 1"));
            if ($r2) {
                $r2['company_name'] = $hc_row['company_name'];
                if (empty($r2['company_signature']) && !empty($r2['signature_path'])) $r2['company_signature'] = $r2['signature_path'];
                return $r2;
            }
        }
    }

    return [];
}

function resolveEmployeeRecord($con, $candidate_id, $candidate_name) {
    $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE id=" . intval($candidate_id) . " LIMIT 1"));
    if ($emp) return $emp;

    $name_e = mysqli_real_escape_string($con, trim($candidate_name));
    $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE TRIM(LOWER(name))=TRIM(LOWER('$name_e')) LIMIT 1"));
    if ($emp) return $emp;

    $emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE name LIKE '%$name_e%' LIMIT 1"));
    return $emp ?: null;
}

function sync_new_hires($con, $CANDIDATES_TABLE, $CAND_ID_COL, $CAND_NAME_COL, $CAND_DEPT_COL, $CAND_POS_COL, $CAND_DECISION_COL, $HIRED_VALUE, $currentUserName) {
    $check = mysqli_query($con, "SHOW TABLES LIKE '$CANDIDATES_TABLE'");
    if (!$check || mysqli_num_rows($check) == 0) return; // table not found yet — skip silently until CONFIG is confirmed

    $sql = "SELECT c.$CAND_ID_COL as cand_id, c.$CAND_NAME_COL as cand_name, d.id as dept_id, c.$CAND_POS_COL as pos_id
            FROM $CANDIDATES_TABLE c
            LEFT JOIN hr_departments d ON TRIM(LOWER(d.name)) = TRIM(LOWER(c.$CAND_DEPT_COL))
            WHERE TRIM(LOWER(c.$CAND_DECISION_COL)) = 'hired'
            AND d.id IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM hr_checklist_runs r
                WHERE r.candidate_id = c.$CAND_ID_COL
            )";
    $res = mysqli_query($con, $sql);
    if (!$res) return;
    while ($row = mysqli_fetch_assoc($res)) {
        if (intval($row['dept_id']) > 0) {
            create_checklist_run($con, $row['cand_id'], $row['cand_name'], $row['dept_id'], intval($row['pos_id']), 'system_auto');
        }
    }
}

sync_new_hires($con, $CANDIDATES_TABLE, $CAND_ID_COL, $CAND_NAME_COL, $CAND_DEPT_COL, $CAND_POS_COL, $CAND_DECISION_COL, $HIRED_VALUE, $currentUserName);

// =========================================================================
// VIEW / DOWNLOAD A FILLABLE DOCUMENT (works blank/unsigned or filled/signed)
// =========================================================================
if (isset($_GET['view_item'])) {
    $item_row_id = intval($_GET['view_item']);
    $item = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE id=$item_row_id LIMIT 1"));
    if (!$item) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Document not found.</h3></div>"); }

    $run = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE id=" . intval($item['run_id']) . " LIMIT 1"));
    if (!$run) { die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Checklist not found.</h3></div>"); }

    if (!$is_hr_user && (intval($run['candidate_id']) !== $logged_in_candidate_id || ($run['candidate_type'] ?? 'screening') !== $logged_in_candidate_type)) {
        die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Not authorized to view this document.</h3></div>");
    }

    $cs_v = getRunCompanySettings($con, intval($run['candidate_id']), $run['candidate_type'] ?? null);
    $schema_v = !empty($item['field_schema']) ? json_decode($item['field_schema'], true) : ['fields'=>[], 'body'=>''];
    $filled_v = !empty($item['filled_data']) ? json_decode($item['filled_data'], true) : [];

    $body_txt_v = str_replace('{{name}}', htmlspecialchars($run['candidate_name']), $schema_v['body'] ?? '');
    foreach (($schema_v['fields'] ?? []) as $sf) {
        $val = $filled_v[$sf['key']] ?? '_______________________';
        $body_txt_v = str_replace('{{' . $sf['key'] . '}}', htmlspecialchars($val), $body_txt_v);
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title><?php echo htmlspecialchars($item['item_text']); ?> — <?php echo htmlspecialchars($run['candidate_name']); ?></title>
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
    .doc-field { margin-bottom:14px; page-break-inside: avoid; break-inside: avoid; }
    .doc-field label { font-weight:700; font-size:13px; display:block; margin-bottom:4px; color:#334155; }
    .doc-field .val { border-bottom:1px solid #94a3b8; padding:6px 4px; font-size:14px; min-height:18px; }
    table.asset-tbl { width:100%; border-collapse:collapse; margin:20px 0; font-size:13px; table-layout:fixed; }
    table.asset-tbl th, table.asset-tbl td { border:1px solid #cbd5e1; padding:10px 12px; text-align:left; vertical-align:middle; word-wrap:break-word; }
    table.asset-tbl th { background:#0f2557; color:#fff; font-weight:700; font-size:12px; text-transform:uppercase; letter-spacing:0.3px; }
    table.asset-tbl tbody tr:nth-child(even) { background:#f8faff; }
    table.asset-tbl tbody tr:hover { background:#eef2ff; }
    table.asset-tbl td { color:#1a202c; line-height:1.5; }
    .checklist-section { font-weight:800; color:#0f2557; font-size:13px; margin:16px 0 8px; page-break-inside: avoid; break-inside: avoid; }
    .checklist-item { font-size:13px; color:#334155; margin-bottom:6px; padding-left:24px; position:relative; page-break-inside: avoid; break-inside: avoid; }
    .checklist-item .box { position:absolute; left:0; top:1px; width:15px; height:15px; border:2px solid #94a3b8; border-radius:3px; display:inline-block; }
    .doc-body { font-size:14px; line-height:1.8; color:#1a202c; margin:20px 0; white-space:pre-wrap; }
    .sig-area { margin-top:40px; display:flex; justify-content:space-between; page-break-inside: avoid; break-inside: avoid; }
    .sig-box { width:260px; }
    .sig-box img { max-height:120px; max-width:260px; }
    .sig-line { border-top:1px solid #334155; margin-top:8px; padding-top:6px; font-size:12px; font-weight:700; }
    .no-print { text-align:center; margin-bottom:20px; }

    @media print{
        @page { margin: 0; }
        body { padding: 0 !important; margin: 0 !important; background: #fff !important; }
        .no-print { display: none !important; }
        * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
        .pdf-preview { padding: 0 !important; margin: 0 !important; width: 100% !important; min-height: 0 !important; border: none !important; box-shadow: none !important; max-width: none !important; border-radius: 0 !important; }
        thead { display: table-header-group; }
        tfoot { display: table-footer-group; }
    }
    </style>
    </head>
    <body>
    <div class="no-print" style="text-align:center; margin-bottom:20px;">
       <button onclick="window.print()" style="padding:14px 28px; background:#0f2557; color:#fff; border:none; border-radius:10px; font-weight:bold; cursor:pointer; box-shadow:0 4px 12px rgba(15,37,87,0.2);">🖨️ Print / Save as PDF</button>
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
                <?php if($cs_v['company_phone'] ?? ''): ?><span><i class="fas fa-phone-alt"></i> <?php echo htmlspecialchars($cs_v['company_phone']); ?></span><?php endif; ?>
                <?php if($cs_v['company_email'] ?? ''): ?><span><i class="fas fa-envelope"></i> <?php echo htmlspecialchars($cs_v['company_email']); ?></span><?php endif; ?>
                <?php if($cs_v['company_website'] ?? ''): ?><span><i class="fas fa-globe"></i> <?php echo htmlspecialchars($cs_v['company_website']); ?></span><?php endif; ?>
            </div>
            <div class="letter-header-right">
                <?php if (!empty($cs_v['company_logo'])): ?><img src="<?php echo htmlspecialchars($cs_v['company_logo']); ?>" alt="Logo"><?php endif; ?>
            </div>
        </div>
        </td></tr></thead>
        <tbody><tr><td style="padding: 0; border:none;">
        <div class="pdf-content-wrapper">

            <div class="doc-title"><?php echo htmlspecialchars($item['item_text']); ?></div>

            <?php foreach (($schema_v['fields'] ?? []) as $sf): ?>
            <div class="doc-field">
                <label><?php echo htmlspecialchars($sf['label']); ?></label>
                <div class="val"><?php echo htmlspecialchars($filled_v[$sf['key']] ?? ''); ?></div>
            </div>
            <?php endforeach; ?>

            <?php if (!empty($schema_v['checklist'])): ?>
                <?php $checked_v = $filled_v['checklist'] ?? []; ?>
                <?php foreach ($schema_v['checklist'] as $sec_idx => $section): ?>
                    <div class="checklist-section"><?php echo htmlspecialchars($section['section']); ?></div>
                    <?php foreach ($section['items'] as $it_idx => $ci): ?>
                        <?php $ckey = $sec_idx . '_' . $it_idx; $is_ck_v = !empty($checked_v[$ckey]); ?>
                        <div class="checklist-item"><span class="box" style="<?php echo $is_ck_v ? 'background:#0f2557;' : ''; ?>"><?php echo $is_ck_v ? '<i class="fas fa-check" style="color:#fff;font-size:10px;position:absolute;left:1px;top:0px;"></i>' : ''; ?></span><?php echo htmlspecialchars($ci); ?></div>
                    <?php endforeach; ?>
                <?php endforeach; ?>
            <?php endif; ?>

            <?php if (!empty($schema_v['table'])): ?>
            <table class="asset-tbl">
                <thead><tr><?php foreach ($schema_v['table']['columns'] as $col): ?><th><?php echo htmlspecialchars($col); ?></th><?php endforeach; ?></tr></thead>
                <tbody>
                <?php
                $table_rows_v = $filled_v['table'] ?? [];
                if (empty($table_rows_v)) {
                    echo '<tr>' . str_repeat('<td>&nbsp;</td>', count($schema_v['table']['columns'])) . '</tr>';
                } else {
                    foreach ($table_rows_v as $trow) {
                        echo '<tr>';
                        foreach ($schema_v['table']['columns'] as $ci => $col) echo '<td>' . htmlspecialchars($trow[$ci] ?? '') . '</td>';
                        echo '</tr>';
                    }
                }
                ?>
                </tbody>
            </table>
            <?php endif; ?>

            <div class="doc-body"><?php echo nl2br($body_txt_v); ?></div>

            <div class="sig-area">
                <div class="sig-box">
                    <?php if (!empty($cs_v['company_signature'])): ?>
                        <img src="<?php echo htmlspecialchars($cs_v['company_signature']); ?>" alt="Company Signature">
                    <?php else: ?>
                        <div style="height:80px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        For <?php echo htmlspecialchars($cs_v['company_name'] ?? 'ABRA GROUPS'); ?><br>
                        <?php echo htmlspecialchars($cs_v['signatory_name'] ?? 'Authorized Signatory'); ?>
                    </div>
                </div>
                <div class="sig-box">
                    <?php if (!empty($item['signature_data'])): ?>
                        <img src="<?php echo htmlspecialchars($item['signature_data']); ?>" alt="Signature">
                    <?php else: ?>
                        <div style="height:80px;"></div>
                    <?php endif; ?>
                    <div class="sig-line">
                        Signature: <?php echo htmlspecialchars($run['candidate_name']); ?><br><br>
                        Date: <?php echo !empty($item['checked_at']) ? date('d M Y', strtotime($item['checked_at'])) : '_______________________'; ?>
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
// AJAX: TOGGLE ITEM CHECK (employee ticks their own / HR overrides)
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'toggle_item') {
    header('Content-Type: application/json');
    $item_row_id = intval($_POST['item_row_id']);
    $checked     = intval($_POST['checked']) == 1 ? 1 : 0;

    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT run_id FROM hr_checklist_run_items WHERE id=$item_row_id"));
    if (!$row) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    $run_chk = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id, candidate_type FROM hr_checklist_runs WHERE id=" . intval($row['run_id'])));
    if (!$is_hr_user && $run_chk && (intval($run_chk['candidate_id']) !== $logged_in_candidate_id || ($run_chk['candidate_type'] ?? 'screening') !== $logged_in_candidate_type)) {
        echo json_encode(['success' => false, 'message' => 'Not authorized for this checklist']);
        exit;
    }

    if ($checked) {
        $by_type = $is_hr_user ? 'hr' : 'employee';
        $by_name = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=1, checked_by_type='$by_type', checked_by_name='$by_name', checked_at=NOW() WHERE id=$item_row_id");
    } else {
        mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=0, checked_by_type=NULL, checked_by_name=NULL, checked_at=NULL WHERE id=$item_row_id");
    }

    // Recompute run completion status
    $run_id = intval($row['run_id']);
    $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    $total = intval($totals['total']);
    $done  = intval($totals['done']);
    if ($total > 0 && $done == $total) {
        mysqli_query($con, "UPDATE hr_checklist_runs SET status='completed', completed_at=NOW() WHERE id=$run_id");
    } else {
        mysqli_query($con, "UPDATE hr_checklist_runs SET status='in_progress', completed_at=NULL WHERE id=$run_id");
    }

    echo json_encode(['success' => true, 'done' => $done, 'total' => $total]);
    exit;
}

// =========================================================================
// =========================================================================
// AJAX: SAVE FILLABLE + SIGNED DOCUMENT — goes to Pending HR Approval, not complete
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'save_fillable') {
    header('Content-Type: application/json');
    $item_row_id = intval($_POST['item_row_id']);
    $filled_data = $_POST['filled_data'] ?? '{}';
    $signature   = $_POST['signature_data'] ?? '';

    if (empty($signature)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }

    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT run_id FROM hr_checklist_run_items WHERE id=$item_row_id"));
    if (!$row) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    $run_chk = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id, candidate_type FROM hr_checklist_runs WHERE id=" . intval($row['run_id'])));
    if (!$is_hr_user && $run_chk && (intval($run_chk['candidate_id']) !== $logged_in_candidate_id || ($run_chk['candidate_type'] ?? 'screening') !== $logged_in_candidate_type)) {
        echo json_encode(['success' => false, 'message' => 'Not authorized for this checklist']);
        exit;
    }

    $by_type = $is_hr_user ? 'hr' : 'employee';
    $by_name = mysqli_real_escape_string($con, $currentUserName);
    $filled_data_e = mysqli_real_escape_string($con, $filled_data);
    $signature_e   = mysqli_real_escape_string($con, $signature);

    mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=0, approval_status='pending_approval', rejection_reason=NULL, checked_by_type='$by_type', checked_by_name='$by_name', checked_at=NOW(), filled_data='$filled_data_e', signature_data='$signature_e' WHERE id=$item_row_id");

    $run_id = intval($row['run_id']);
    $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    mysqli_query($con, "UPDATE hr_checklist_runs SET status='in_progress', completed_at=NULL WHERE id=$run_id");

    echo json_encode(['success' => true, 'done' => intval($totals['done']), 'total' => intval($totals['total']), 'pending_approval' => true]);
    exit;
}

// =========================================================================
// AJAX: HR APPROVE A SIGNED FILLABLE DOCUMENT
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'approve_fillable' && $is_hr_user) {
    header('Content-Type: application/json');
    $item_row_id = intval($_POST['item_row_id']);

    $item = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE id=$item_row_id LIMIT 1"));
    if (!$item) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    $run_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE id=" . intval($item['run_id']) . " LIMIT 1"));
    if (!$run_row) { echo json_encode(['success' => false, 'message' => 'Checklist not found']); exit; }

    $by_name = mysqli_real_escape_string($con, $currentUserName);
    mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=1, approval_status='approved', reviewed_by='$by_name', reviewed_at=NOW() WHERE id=$item_row_id");

    $emp = resolveEmployeeRecord($con, intval($run_row['candidate_id']), $run_row['candidate_name']);
    if ($emp && !empty($emp['employee_id'])) {
        $doc_url = 'hr-checklist.php?view_item=' . $item_row_id;
        $eid_e   = mysqli_real_escape_string($con, $emp['employee_id']);
        $dt_e    = mysqli_real_escape_string($con, $item['item_text']);
        $fn_e    = mysqli_real_escape_string($con, $item['item_text'] . '.pdf');
        $fp_e    = mysqli_real_escape_string($con, $doc_url);
        $exists = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employee_documents WHERE employee_id='$eid_e' AND document_type='$dt_e' LIMIT 1"));
        if ($exists) {
            mysqli_query($con, "UPDATE hr_employee_documents SET filename='$fn_e', filepath='$fp_e' WHERE id=" . intval($exists['id']));
        } else {
            mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath) VALUES ('$eid_e', '$dt_e', '$fn_e', '$fp_e')");
        }
    }

    $run_id = intval($item['run_id']);
    $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    $total = intval($totals['total']);
    $done  = intval($totals['done']);
    if ($total > 0 && $done == $total) {
        mysqli_query($con, "UPDATE hr_checklist_runs SET status='completed', completed_at=NOW() WHERE id=$run_id");
    } else {
        mysqli_query($con, "UPDATE hr_checklist_runs SET status='in_progress', completed_at=NULL WHERE id=$run_id");
    }

    echo json_encode(['success' => true, 'done' => $done, 'total' => $total]);
    exit;
}

// =========================================================================
// AJAX: HR REJECT A SIGNED FILLABLE DOCUMENT — reverts signature + auto-raises a ticket
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'reject_fillable' && $is_hr_user) {
    header('Content-Type: application/json');
    $item_row_id = intval($_POST['item_row_id']);
    $reason      = trim($_POST['reason'] ?? '');
    if (empty($reason)) { echo json_encode(['success' => false, 'message' => 'Please provide a rejection reason.']); exit; }

    $item = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE id=$item_row_id LIMIT 1"));
    if (!$item) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    $run_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE id=" . intval($item['run_id']) . " LIMIT 1"));
    if (!$run_row) { echo json_encode(['success' => false, 'message' => 'Checklist not found']); exit; }

    $by_name  = mysqli_real_escape_string($con, $currentUserName);
    $reason_e = mysqli_real_escape_string($con, $reason);

    // Revert: clear signature/completion, keep filled_data so the employee can just fix and re-sign
    mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=0, approval_status='rejected', rejection_reason='$reason_e', reviewed_by='$by_name', reviewed_at=NOW(), signature_data=NULL WHERE id=$item_row_id");

    $emp = resolveEmployeeRecord($con, intval($run_row['candidate_id']), $run_row['candidate_name']);
    $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE TRIM(LOWER(name))=TRIM(LOWER('$by_name')) LIMIT 1"));
    if (!$hr_self) $hr_self = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$by_name%' LIMIT 1"));

    if ($emp && $hr_self) {
        $t_subject   = "Document Rejected — " . $item['item_text'];
        $t_message   = "Your submission for \"" . $item['item_text'] . "\" was reviewed and rejected by {$currentUserName}.\n\nReason: {$reason}\n\nPlease review, correct if needed, and resubmit via the Onboarding Checklist.";
        $t_name_e    = mysqli_real_escape_string($con, $currentUserName);
        $t_subject_e = mysqli_real_escape_string($con, $t_subject);
        $t_message_e = mysqli_real_escape_string($con, $t_message);
        $t_priority  = 'medium';
        $t_timeline  = 1440;
        $t_deadline  = date('Y-m-d H:i:s', strtotime('+1440 minutes'));

        $tk_row  = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
        $tk_next = ($tk_row['max_id'] ?? 0) + 1;
        $ticket_number = 'TICKET' . date('Y') . str_pad($tk_next, 4, '0', STR_PAD_LEFT);

        mysqli_query($con, "INSERT INTO tickets
            (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
            VALUES
            ('$ticket_number', '$t_name_e', '$t_subject_e', '$t_message_e', 'open', '$t_priority', $t_timeline, '$t_deadline', '', NOW(), NOW(), " . intval($emp['id']) . ", " . intval($hr_self['id']) . ")");
    }

    $run_id = intval($item['run_id']);
    mysqli_query($con, "UPDATE hr_checklist_runs SET status='in_progress', completed_at=NULL WHERE id=$run_id");
    $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));

    echo json_encode(['success' => true, 'done' => intval($totals['done']), 'total' => intval($totals['total'])]);
    exit;
}

// =========================================================================
// AJAX: SAVE FINAL CHECKLIST SIGNATURE (mandatory once all items are done)
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'save_final_signature') {
    header('Content-Type: application/json');
    $run_id    = intval($_POST['run_id']);
    $signature = $_POST['signature_data'] ?? '';

    if (empty($signature)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }

    $run_chk = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id, candidate_type FROM hr_checklist_runs WHERE id=$run_id"));
    if (!$run_chk) { echo json_encode(['success' => false, 'message' => 'Checklist not found']); exit; }
    if (!$is_hr_user && (intval($run_chk['candidate_id']) !== $logged_in_candidate_id || ($run_chk['candidate_type'] ?? 'screening') !== $logged_in_candidate_type)) {
        echo json_encode(['success' => false, 'message' => 'Not authorized for this checklist']);
        exit;
    }

    $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    if (intval($totals['total']) == 0 || intval($totals['done']) != intval($totals['total'])) {
        echo json_encode(['success' => false, 'message' => 'Please complete all checklist items before signing.']);
        exit;
    }

    $by_name = mysqli_real_escape_string($con, $currentUserName);
    $signature_e = mysqli_real_escape_string($con, $signature);
    mysqli_query($con, "UPDATE hr_checklist_runs SET final_signature_data='$signature_e', final_signed_by='$by_name', final_signed_at=NOW(), status='completed', completed_at=NOW() WHERE id=$run_id");

    echo json_encode(['success' => true]);
    exit;
}

// =========================================================================
// FORM: START NEW RUN MANUALLY (HR only — e.g. promotion to a new position)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'start_new_run' && $is_hr_user) {
    $cand_id   = intval($_POST['candidate_id']);
    $cand_name = trim($_POST['candidate_name']);
    if ($cand_id > 0) {
        // Fetch candidate's department and position from hr_screenings
        $c_res = mysqli_query($con, "SELECT c.$CAND_DEPT_COL as dept_name, c.$CAND_POS_COL as pos_id, d.id as dept_id 
                                     FROM $CANDIDATES_TABLE c 
                                     LEFT JOIN hr_departments d ON TRIM(LOWER(d.name)) = TRIM(LOWER(c.$CAND_DEPT_COL))
                                     WHERE c.$CAND_ID_COL = $cand_id");
        $c_data = mysqli_fetch_assoc($c_res);
        $dept_id = $c_data ? intval($c_data['dept_id']) : 0;
        $pos_id  = $c_data ? intval($c_data['pos_id']) : 0;

        $new_run_id = create_checklist_run($con, $cand_id, $cand_name, $dept_id, $pos_id, $currentUserName);
        $_SESSION['success_message'] = "New checklist run started.";
        header("Location: $current_page?run_id=$new_run_id");
        exit;
    } else {
        $_SESSION['error_message'] = "Please select an Employee.";
        header("Location: $current_page");
        exit;
    }
}

// =========================================================================
// FORM: DELETE A CHECKLIST RUN (HR only)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'delete_run' && $is_hr_user) {
    $del_id = intval($_POST['run_id']);
    if ($del_id > 0) {
        mysqli_query($con, "DELETE FROM hr_checklist_run_items WHERE run_id=$del_id");
        mysqli_query($con, "DELETE FROM hr_checklist_runs WHERE id=$del_id");
        $_SESSION['success_message'] = "Checklist run deleted successfully.";
    }
    header("Location: $current_page");
    exit;
}

// =========================================================================
// PAGE DATA
// =========================================================================
$view_run_id = isset($_GET['run_id']) ? intval($_GET['run_id']) : 0;

// =========================================================================
// EXPORT (CSV / Excel) — respects filters, but works fine with none set
// =========================================================================
if (isset($_GET['export']) && in_array($_GET['export'], ['csv', 'excel']) && $is_hr_user) {
    $f_dept   = isset($_GET['f_dept'])   ? trim($_GET['f_dept'])   : '';
    $f_pos    = isset($_GET['f_pos'])    ? trim($_GET['f_pos'])    : '';
    $f_status = isset($_GET['f_status']) ? trim($_GET['f_status']) : '';
    $f_name   = isset($_GET['f_name'])   ? trim($_GET['f_name'])   : '';

    $where = [];
    if ($f_dept   !== '') $where[] = "department_name = '" . mysqli_real_escape_string($con, $f_dept) . "'";
    if ($f_pos    !== '') $where[] = "position_name = '" . mysqli_real_escape_string($con, $f_pos) . "'";
    if ($f_status !== '') $where[] = "status = '" . mysqli_real_escape_string($con, $f_status) . "'";
    if ($f_name   !== '') $where[] = "candidate_name LIKE '%" . mysqli_real_escape_string($con, $f_name) . "%'";
    $where_sql = !empty($where) ? "WHERE " . implode(" AND ", $where) : "";

    $exp_runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs $where_sql ORDER BY candidate_name ASC");

    $ext  = $_GET['export'] === 'excel' ? 'xls' : 'csv';
    $mime = $_GET['export'] === 'excel' ? 'application/vnd.ms-excel' : 'text/csv';
    header("Content-Type: $mime; charset=utf-8");
    header('Content-Disposition: attachment; filename=onboarding_checklist_export_' . date('Y-m-d_His') . '.' . $ext);

    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF)); // BOM for Excel

    fputcsv($out, ['Employee Name', 'Department', 'Position', 'Overall Status', 'Progress %', 'Started Date',
                   'Heading', 'Item', 'Completed', 'Completed By', 'Completed By Type', 'Completed At', 'Has Signature']);

    while ($er = mysqli_fetch_assoc($exp_runs_res)) {
        $er_run_id = intval($er['id']);
        $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$er_run_id"));
        $er_total = intval($tot['total']);
        $er_done  = intval($tot['done']);
        $er_pct   = $er_total > 0 ? round(($er_done / $er_total) * 100) : 0;

        $items_res = mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE run_id=$er_run_id ORDER BY scope_level DESC, heading_sort ASC, item_sort ASC, id ASC");
        if (mysqli_num_rows($items_res) == 0) {
            fputcsv($out, [$er['candidate_name'], $er['department_name'], $er['position_name'], ucfirst($er['status']), $er_pct . '%', date('d M Y', strtotime($er['created_at'])), '', '', '', '', '', '', '']);
        } else {
            while ($ei = mysqli_fetch_assoc($items_res)) {
                fputcsv($out, [
                    $er['candidate_name'],
                    $er['department_name'],
                    $er['position_name'],
                    ucfirst($er['status']),
                    $er_pct . '%',
                    date('d M Y', strtotime($er['created_at'])),
                    $ei['heading_name'],
                    $ei['item_text'],
                    $ei['is_checked'] ? 'Yes' : 'No',
                    $ei['checked_by_name'] ?: '',
                    $ei['checked_by_type'] ? ucfirst($ei['checked_by_type']) : '',
                    $ei['checked_at'] ? date('d M Y, h:i A', strtotime($ei['checked_at'])) : '',
                    !empty($ei['signature_data']) ? 'Yes' : 'No'
                ]);
            }
        }
    }
    fclose($out);
    exit;
}

$departments_arr = [];
$dept_q = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
while ($d = mysqli_fetch_assoc($dept_q)) $departments_arr[] = $d;

// For the "start new run" modal — list of hired candidates (HR only)
$hired_candidates_arr = [];
if ($is_hr_user) {
    $check = mysqli_query($con, "SHOW TABLES LIKE '$CANDIDATES_TABLE'");
    if ($check && mysqli_num_rows($check) > 0) {
        $cq = mysqli_query($con, "SELECT c.$CAND_ID_COL as id, c.$CAND_NAME_COL as name, d.id as dept_id, c.$CAND_POS_COL as pos_id 
                                  FROM $CANDIDATES_TABLE c 
                                  LEFT JOIN hr_departments d ON TRIM(LOWER(d.name)) = TRIM(LOWER(c.$CAND_DEPT_COL))
                                  WHERE TRIM(LOWER(c.$CAND_DECISION_COL)) = 'hired' AND d.id IS NOT NULL ORDER BY c.$CAND_NAME_COL ASC");
        if ($cq) while ($c = mysqli_fetch_assoc($cq)) $hired_candidates_arr[] = $c;
    }
}

if ($is_hr_user) {
    $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs ORDER BY created_at DESC");
} else {
    $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE candidate_id=$logged_in_candidate_id AND candidate_type='" . mysqli_real_escape_string($con, $logged_in_candidate_type) . "' ORDER BY created_at DESC");
}

$runs_arr = [];
while ($r = mysqli_fetch_assoc($runs_res)) {
    $run_id = intval($r['id']);
    $r['company_settings'] = getRunCompanySettings($con, intval($r['candidate_id']), $r['candidate_type'] ?? null);
    
    if ($is_hr_user) {
        // Diff-based sync: insert any global item this run is missing (not just when totally empty)
        $existing_item_ids = [];
        $existing_res = mysqli_query($con, "SELECT item_id FROM hr_checklist_run_items WHERE run_id=$run_id AND item_id IS NOT NULL");
        while ($ex = mysqli_fetch_assoc($existing_res)) $existing_item_ids[intval($ex['item_id'])] = true;

        $added = 0;
        $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
        while ($h = mysqli_fetch_assoc($h_res)) {
            $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . intval($h['id']) . " AND is_active=1 ORDER BY sort_order ASC, id ASC");
            while ($it = mysqli_fetch_assoc($i_res)) {
                if (isset($existing_item_ids[intval($it['id'])])) {
                    // item already present in this run — sync type/schema if not yet completed
                    mysqli_query($con, "UPDATE hr_checklist_run_items 
                        SET item_type='" . mysqli_real_escape_string($con, $it['item_type'] ?? 'tick') . "',
                            field_schema=" . (!empty($it['field_schema']) ? "'" . mysqli_real_escape_string($con, $it['field_schema']) . "'" : "NULL") . "
                        WHERE run_id=$run_id AND item_id=" . intval($it['id']) . " AND is_checked=0");
                    continue;
                }

                $added++;
                $heading_name_e = mysqli_real_escape_string($con, $h['heading_name']);
                $item_text_e    = mysqli_real_escape_string($con, $it['item_text']);
                $desc_e         = mysqli_real_escape_string($con, $it['description'] ?? '');
                $doc_path_sql   = $it['document_path']     ? "'" . mysqli_real_escape_string($con, $it['document_path']) . "'"     : "NULL";
                $doc_fname_sql  = $it['document_filename']  ? "'" . mysqli_real_escape_string($con, $it['document_filename']) . "'"  : "NULL";
                $vid_path_sql   = $it['video_path']         ? "'" . mysqli_real_escape_string($con, $it['video_path']) . "'"         : "NULL";
                $vid_fname_sql  = $it['video_filename']     ? "'" . mysqli_real_escape_string($con, $it['video_filename']) . "'"      : "NULL";

                $vis_emp_snap = intval($it['visible_to_employee'] ?? 0);
                $req_sig_snap = intval($it['require_signature'] ?? 0);
                $item_type_snap = mysqli_real_escape_string($con, $it['item_type'] ?? 'tick');
                $field_schema_snap = !empty($it['field_schema']) ? "'" . mysqli_real_escape_string($con, $it['field_schema']) . "'" : "NULL";
                mysqli_query($con, "INSERT INTO hr_checklist_run_items
                    (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature, item_type, field_schema)
                    VALUES ($run_id, '$heading_name_e', " . intval($h['sort_order']) . ", 'global', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ", $vis_emp_snap, $req_sig_snap, '$item_type_snap', $field_schema_snap)");
            }
        }
    }

    $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    $r['total_items'] = intval($tot['total']);
    
    $r['done_items']  = intval($tot['done']);
    $r['progress_pct'] = $r['total_items'] > 0 ? round(($r['done_items'] / $r['total_items']) * 100) : 0;
    
    $items_res = mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE run_id=$run_id ORDER BY scope_level DESC, heading_sort ASC, item_sort ASC, id ASC");
    $grouped = [];
    while ($it = mysqli_fetch_assoc($items_res)) {
        $key = $it['scope_level'] . '||' . $it['heading_name'];
        if (!isset($grouped[$key])) {
            $grouped[$key] = ['heading_name' => $it['heading_name'], 'scope_level' => $it['scope_level'], 'items' => []];
        }
        $grouped[$key]['items'][] = $it;
    }
    $r['grouped'] = $grouped;
    
    $runs_arr[] = $r;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?> | Onboarding Checklists</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    .container-fluid { max-width: 1400px; margin: 0 auto; padding: 0 20px; }

/* Navigation Tabs */
.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; }
.nav-btn {
    padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
    font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
    display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }

    .card-box { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px; }

    .run-card {
      display: flex; justify-content: space-between; align-items: center; gap: 16px;
      background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px 20px; margin-bottom: 12px;
    }
    .run-card .name { font-weight: 700; color: #0f2557; font-size: 15px; }
    .run-card .meta { font-size: 12px; color: #64748b; margin-top: 2px; }
    .progress-wrap { width: 220px; }
    .progress { height: 10px; border-radius: 6px; background: #e2e8f0; }
    .progress-bar { background: linear-gradient(90deg,#10b981,#059669); transition: width 0.3s ease; }
    .status-pill { font-size: 11px; font-weight: 800; padding: 4px 12px; border-radius: 20px; text-transform: uppercase; }
    .status-pill.in_progress { background: #fef9c3; color: #713f12; }
    .status-pill.completed { background: #dcfce7; color: #166534; }

    .scope-badge { font-size: 11px; font-weight: 800; padding: 3px 10px; border-radius: 20px; text-transform: uppercase; }
    .scope-badge.department { background: #dbeafe; color: #1e40af; }
    .scope-badge.position { background: #ede9fe; color: #5b21b6; }

    .heading-block { border: 1px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden; }
    .heading-block-head {
      background: #f8faff; padding: 14px 18px; display: flex; justify-content: space-between; align-items: center;
      border-bottom: 1px solid #e0e7ff;
    }
    .heading-block-head h6 { margin: 0; font-weight: 800; color: #0f2557; font-size: 14px; }
    .heading-block-body { padding: 14px 18px; }

    .checklist-row {
      display: flex; align-items: flex-start; gap: 14px;
      padding: 14px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 10px;
      transition: all 0.2s ease;
    }
    .checklist-row.is-done { background: #f0fdf4; border-color: #bbf7d0; }
    .check-box-input { width: 20px; height: 20px; margin-top: 2px; cursor: pointer; flex-shrink: 0; }
    .item-text { font-weight: 700; color: #0f2557; font-size: 13.5px; margin-bottom: 4px; transition: all 0.2s ease; }
    .item-text.is-done { text-decoration: line-through; color: #15803d; }
    .item-desc { font-size: 12px; color: #64748b; margin-bottom: 8px; }
    .attach-pill {
      display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700;
      padding: 4px 10px; border-radius: 14px; margin-right: 6px; text-decoration: none;
    }
    .attach-pill.doc { background: #ede9fe; color: #5b21b6; }
    .attach-pill.vid { background: #fef9c3; color: #713f12; }
    video.preview-video { max-width: 320px; border-radius: 8px; margin-top: 8px; display: block; }
    .checked-meta { font-size: 11px; color: #15803d; margin-top: 6px; font-weight: 600; }

    .empty-hint { text-align: center; padding: 40px; color: #94a3b8; }
  </style>
</head>
<body>

<div class="container-fluid">

    <?php if(isset($_SESSION['success_message'])): ?>
        <div class="alert alert-success alert-dismissible fade show">
            <i class="fas fa-check-circle mr-2"></i> <?php echo $_SESSION['success_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['success_message']); ?>
    <?php endif; ?>
    <?php if(isset($_SESSION['error_message'])): ?>
        <div class="alert alert-danger alert-dismissible fade show">
            <i class="fas fa-exclamation-circle mr-2"></i> <?php echo $_SESSION['error_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['error_message']); ?>
    <?php endif; ?>

    <div class="page-header">
        <div style="flex:1;">
            <h1><i class="fas fa-tasks mr-2"></i> Onboarding Checklists</h1>
        </div>
        <div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
            <?php if ($is_hr_user): ?>
            <!-- Quick Select Employee Dropdown -->
            <form method="GET" class="form-inline m-0 p-0" id="quickSelectForm">
                <select class="form-control" onchange="if(this.value) { $('.collapse').collapse('hide'); $('#collapseRun'+this.value).collapse('show'); document.getElementById('collapseRun'+this.value).scrollIntoView({behavior:'smooth'}); }">
                    <option value="">-- View Employee Checklist --</option>
                    <?php 
                    // Fetch existing runs for quick selection
                    $qs_res = mysqli_query($con, "SELECT id, candidate_name FROM hr_checklist_runs ORDER BY candidate_name ASC");
                    while ($qs_row = mysqli_fetch_assoc($qs_res)):
                    ?>
                        <option value="<?php echo $qs_row['id']; ?>" <?php echo $view_run_id == $qs_row['id'] ? 'selected' : ''; ?>><?php echo htmlspecialchars($qs_row['candidate_name']); ?></option>
                    <?php endwhile; ?>
                </select>
            </form>
            <?php
            $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
            $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
            ?>
            
            <button class="btn btn-success" data-toggle="modal" data-target="#newRunModal"><i class="fas fa-plus"></i> Start New Run</button>
            <?php endif; ?>
        </div>
    </div>

<?php if ($is_hr_user): ?>
<!-- NAVIGATION TABS -->
<div class="nav-tabs-container">
    <a href="hr-employee-onboarding-pending-list.php" class="nav-btn">
        <i class="fas fa-user-plus"></i> Onboarding
    </a>
    <a href="hr-checklist-employee.php" class="nav-btn">
        <i class="fas fa-tasks"></i> Internal Checklist
    </a>
    <a href="hr-checklist.php" class="nav-btn active">
        <i class="fas fa-clipboard-check"></i> Employee Checklist
    </a>
</div>
<?php endif; ?>

    <?php if (empty($runs_arr)): ?>
        <div class="card-box">
            <div class="empty-hint">
                <i class="fas fa-clipboard-list fa-3x mb-3"></i>
                <h5><?php echo $is_hr_user ? 'No onboarding checklists yet. They will appear automatically once a candidate is marked Hired.' : 'You don\'t have an onboarding checklist yet.'; ?></h5>
            </div>
        </div>
    <?php else: ?>
        <?php if ($is_hr_user): ?>
        <div class="card-box" style="padding:16px 20px;">
            <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;">
                <div style="flex:2;min-width:200px;">
                    <label style="font-size:12px;font-weight:700;color:#475569;display:block;margin-bottom:5px;">Search Employee</label>
                    <input type="text" id="employeeSearchInput" class="form-control" placeholder="Search by employee name..." onkeyup="filterRuns()">
                </div>
                <div style="flex:1;min-width:160px;">
                    <label style="font-size:12px;font-weight:700;color:#475569;display:block;margin-bottom:5px;">Department</label>
                    <select id="filterDept" class="form-control" onchange="filterRuns()">
                        <option value="">All Departments</option>
                        <?php
                        $dept_names = array_unique(array_column($runs_arr, 'department_name'));
                        sort($dept_names);
                        foreach ($dept_names as $dn): if (!$dn) continue; ?>
                            <option value="<?php echo htmlspecialchars($dn); ?>"><?php echo htmlspecialchars($dn); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div style="flex:1;min-width:160px;">
                    <label style="font-size:12px;font-weight:700;color:#475569;display:block;margin-bottom:5px;">Position</label>
                    <select id="filterPos" class="form-control" onchange="filterRuns()">
                        <option value="">All Positions</option>
                        <?php
                        $pos_names = array_unique(array_column($runs_arr, 'position_name'));
                        sort($pos_names);
                        foreach ($pos_names as $pn): if (!$pn) continue; ?>
                            <option value="<?php echo htmlspecialchars($pn); ?>"><?php echo htmlspecialchars($pn); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div style="flex:1;min-width:150px;">
                    <label style="font-size:12px;font-weight:700;color:#475569;display:block;margin-bottom:5px;">Status</label>
                    <select id="filterStatus" class="form-control" onchange="filterRuns()">
                        <option value="">All Status</option>
                        <option value="in_progress">In Progress</option>
                        <option value="completed">Completed</option>
                    </select>
                </div>
                <div>
                    <button class="btn btn-secondary" onclick="resetChecklistFilters()" style="margin-right:6px;"><i class="fas fa-redo"></i> Reset</button>
                </div>
                <div class="dropdown">
                    <button class="btn btn-success dropdown-toggle" type="button" id="exportDropdown" data-toggle="dropdown">
                        <i class="fas fa-download"></i> Export
                    </button>
                    <div class="dropdown-menu dropdown-menu-right">
                        <a class="dropdown-item" href="#" onclick="doExport('csv'); return false;"><i class="fas fa-file-csv mr-1"></i> Export CSV</a>
                        <a class="dropdown-item" href="#" onclick="doExport('excel'); return false;"><i class="fas fa-file-excel mr-1"></i> Export Excel</a>
                    </div>
                </div>
            </div>
        </div>
        <?php endif; ?>

        <div class="accordion" id="runsAccordion">
            <?php foreach ($runs_arr as $r): ?>
                <div class="card-box" style="padding:0; overflow:hidden;" data-department="<?php echo htmlspecialchars($r['department_name']); ?>" data-position="<?php echo htmlspecialchars($r['position_name']); ?>" data-status="<?php echo htmlspecialchars($r['status']); ?>">
                    <div class="run-card" style="margin-bottom:0; border:none; border-radius:0; cursor:pointer;" data-toggle="collapse" data-target="#collapseRun<?php echo $r['id']; ?>" aria-expanded="<?php echo ($view_run_id == $r['id'] || count($runs_arr) == 1) ? 'true' : 'false'; ?>">
                        <div>
                            <div class="name"><?php echo htmlspecialchars($r['candidate_name']); ?></div>
                            <div class="meta"><?php echo htmlspecialchars($r['department_name']); ?> &middot; <?php echo htmlspecialchars($r['position_name']); ?> &middot; Started <?php echo date('d M Y', strtotime($r['created_at'])); ?></div>
                        </div>
                        <span class="status-pill <?php echo $r['status']; ?>" id="statusPill_<?php echo $r['id']; ?>"><?php echo $r['status'] == 'completed' ? 'Completed' : 'In Progress'; ?></span>
                        <div class="progress-wrap">
                            <div class="d-flex justify-content-between mb-1">
                                <small id="progressLabel_<?php echo $r['id']; ?>" style="font-weight:700;color:#0f2557;"><?php echo $r['done_items']; ?> / <?php echo $r['total_items']; ?> done</small>
                                <small id="progressPct_<?php echo $r['id']; ?>" style="font-weight:700;color:#10b981;"><?php echo $r['progress_pct']; ?>%</small>
                            </div>
                            <div class="progress"><div class="progress-bar" id="progressBarFill_<?php echo $r['id']; ?>" style="width: <?php echo $r['progress_pct']; ?>%"></div></div>
                        </div>
                        <?php if ($is_hr_user): ?>
                            <form method="POST" style="margin:0;" onsubmit="return confirm('Are you sure you want to permanently delete this entire checklist run? This action cannot be undone.');">
                                <input type="hidden" name="action" value="delete_run">
                                <input type="hidden" name="run_id" value="<?php echo $r['id']; ?>">
                                <button type="submit" class="btn btn-sm btn-outline-danger" title="Delete Checklist Run" style="border-radius:8px; padding:6px 10px;" onclick="event.stopPropagation();"><i class="fas fa-trash"></i></button>
                            </form>
                        <?php endif; ?>
                    </div>

                    <div id="collapseRun<?php echo $r['id']; ?>" class="collapse <?php echo ($view_run_id == $r['id'] || count($runs_arr) == 1) ? 'show' : ''; ?>" data-parent="#runsAccordion">
                        <div style="padding: 20px; border-top: 1px solid #e2e8f0; background: #fff;">
                            <?php if (empty($r['grouped'])): ?>
                                <div class="empty-hint"><i class="fas fa-list-ul fa-2x mb-3"></i><h6>No checklist items found for this department/position yet. Add some in the Checklist Configuration screen.</h6></div>
                            <?php else: foreach ($r['grouped'] as $group): ?>
                                <div class="heading-block">
                                    <div class="heading-block-head">
                                        <h6><i class="fas fa-layer-group mr-2" style="color:<?php echo $group['scope_level']=='department' ? '#1e3a8a' : '#5b21b6'; ?>;"></i><?php echo htmlspecialchars($group['heading_name']); ?></h6>
                                        <span class="scope-badge <?php echo $group['scope_level']; ?>"><?php echo $group['scope_level'] == 'department' ? 'Department-Level' : 'Position-Level'; ?></span>
                                    </div>
                                    <div class="heading-block-body">
                                        <?php foreach ($group['items'] as $item): ?>
                                        <?php if (($item['item_type'] ?? 'tick') === 'fillable_signature'): ?>
                                            <?php
                                                $schema = !empty($item['field_schema']) ? json_decode($item['field_schema'], true) : ['fields'=>[], 'body'=>''];
                                                $filled = !empty($item['filled_data']) ? json_decode($item['filled_data'], true) : [];
                                                $cs_r = $r['company_settings'] ?? [];
                                                $body_txt = str_replace('{{name}}', htmlspecialchars($r['candidate_name']), $schema['body'] ?? '');
                                                foreach (($schema['fields'] ?? []) as $sf) {
                                                    $val = $filled[$sf['key']] ?? '';
                                                    $body_txt = str_replace('{{' . $sf['key'] . '}}', htmlspecialchars($val), $body_txt);
                                                }
                                            ?>
                                            <?php $apv_status = $item['approval_status'] ?? null; ?>
                                            <div class="checklist-row <?php echo $item['is_checked'] ? 'is-done' : ''; ?>" id="row_<?php echo $item['id']; ?>" style="align-items:center;">
                                                <div style="flex:1;">
                                                    <div class="item-text <?php echo $item['is_checked'] ? 'is-done' : ''; ?>">
                                                        <i class="fas fa-file-signature mr-1" style="color:#6d28d9;"></i> <?php echo htmlspecialchars($item['item_text']); ?>
                                                        <?php if ($apv_status === 'pending_approval'): ?>
                                                            <span style="display:inline-flex;align-items:center;gap:4px;font-size:10px;font-weight:800;padding:3px 10px;border-radius:20px;background:#fef9c3;color:#713f12;margin-left:8px;"><i class="fas fa-hourglass-half"></i>Pending HR Approval</span>
                                                        <?php elseif ($apv_status === 'rejected'): ?>
                                                            <span style="display:inline-flex;align-items:center;gap:4px;font-size:10px;font-weight:800;padding:3px 10px;border-radius:20px;background:#fee2e2;color:#991b1b;margin-left:8px;"><i class="fas fa-times-circle"></i>Rejected</span>
                                                        <?php elseif ($item['is_checked']): ?>
                                                            <span style="display:inline-flex;align-items:center;gap:4px;font-size:10px;font-weight:800;padding:3px 10px;border-radius:20px;background:#dcfce7;color:#166534;margin-left:8px;"><i class="fas fa-check-circle"></i>Approved</span>
                                                        <?php endif; ?>
                                                    </div>
                                                    <?php if ($apv_status === 'rejected'): ?>
                                                        <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:8px 12px;font-size:12px;color:#991b1b;margin:6px 0;">
                                                            <strong>Rejected by <?php echo htmlspecialchars($item['reviewed_by']); ?></strong> on <?php echo date('d M Y, h:i A', strtotime($item['reviewed_at'])); ?><br>
                                                            Reason: <?php echo htmlspecialchars($item['rejection_reason']); ?>
                                                        </div>
                                                    <?php endif; ?>
                                                    <?php if ($item['is_checked'] || $apv_status === 'pending_approval'): ?>
                                                        <div class="checked-meta" style="margin-bottom:6px;">
                                                            <i class="fas fa-check-circle"></i> Signed by <?php echo htmlspecialchars($item['checked_by_name']); ?>
                                                            (<?php echo $item['checked_by_type'] == 'hr' ? 'HR' : 'Employee'; ?>) on <?php echo date('d M Y, h:i A', strtotime($item['checked_at'])); ?>
                                                        </div>
                                                        <?php if (!empty($item['signature_data'])): ?>
                                                            <img src="<?php echo htmlspecialchars($item['signature_data']); ?>" alt="Signature" style="max-height:70px; border:1px solid #ddd6fe; border-radius:8px; background:#faf5ff; padding:4px; display:block; margin-bottom:8px;" />
                                                        <?php endif; ?>
                                                    <?php endif; ?>
                                                </div>
                                                <div style="display:flex;gap:6px;flex-shrink:0;flex-wrap:wrap;">
                                                    <button type="button" class="btn btn-sm btn-outline-primary" onclick="window.open('<?php echo $view_item_base_url; ?>?view_item=<?php echo $item['id']; ?>', '_blank')" title="View / Download this document">
                                                        <i class="fas fa-file-download"></i> View / Download
                                                    </button>
                                                    <?php if ($apv_status === 'pending_approval'): ?>
                                                        <button type="button" class="btn btn-sm btn-success" onclick="approveFillable(<?php echo $item['id']; ?>, <?php echo $r['id']; ?>)"><i class="fas fa-check"></i> Approve</button>
                                                        <button type="button" class="btn btn-sm btn-danger" onclick="openRejectFillableModal(<?php echo $item['id']; ?>)"><i class="fas fa-times"></i> Reject</button>
                                                    <?php else: ?>
                                                        <button type="button" class="btn btn-sm <?php echo $item['is_checked'] ? 'btn-outline-secondary' : 'btn-primary'; ?>" data-toggle="modal" data-target="#fillModal_<?php echo $item['id']; ?>">
                                                            <i class="fas fa-<?php echo $item['is_checked'] ? 'eye' : 'pen-nib'; ?>"></i> <?php echo $item['is_checked'] ? 'View Signed Document' : 'Fill & Sign'; ?>
                                                        </button>
                                                    <?php endif; ?>
                                                </div>
                                            </div>

                                            <!-- Fill & Sign Modal -->
                                            <div class="modal fade" id="fillModal_<?php echo $item['id']; ?>" tabindex="-1" role="dialog">
                                                <div class="modal-dialog modal-lg" role="document">
                                                    <div class="modal-content">
                                                        <div class="modal-header" style="background:linear-gradient(135deg,#0f2557,#1a3fc4);">
                                                            <h5 class="modal-title" style="color:#fff;"><?php echo htmlspecialchars($item['item_text']); ?></h5>
                                                            <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
                                                        </div>
                                                        <div class="modal-body" style="max-height:75vh;overflow-y:auto;">
                                                            <div style="border:1px solid #e0e7ff;border-radius:10px;padding:16px 20px;margin-bottom:16px;background:#f8faff;">
                                                                <div style="font-weight:800;font-size:13px;color:#0f2557;">
                                                                    <?php echo htmlspecialchars($cs_r['company_name'] ?? 'ABRA GROUPS'); ?>
                                                                </div>
                                                                <?php if (!empty($cs_r['company_address'])): ?><div style="font-size:11px;color:#64748b;"><?php echo nl2br(htmlspecialchars($cs_r['company_address'])); ?></div><?php endif; ?>
                                                                <div style="font-size:11px;color:#64748b;">
                                                                    <?php echo htmlspecialchars($cs_r['company_email'] ?? ''); ?> <?php echo !empty($cs_r['company_phone']) ? ' | ' . htmlspecialchars($cs_r['company_phone']) : ''; ?>
                                                                </div>
                                                            </div>

                                                            <form id="fillForm_<?php echo $item['id']; ?>" onsubmit="return false;">
                                                                <?php foreach (($schema['fields'] ?? []) as $sf): ?>
                                                                <div class="form-group">
                                                                    <label style="font-weight:700;font-size:12px;"><?php echo htmlspecialchars($sf['label']); ?></label>
                                                                    <input type="<?php echo htmlspecialchars($sf['type'] ?? 'text'); ?>" class="form-control fillable-field" data-key="<?php echo htmlspecialchars($sf['key']); ?>" value="<?php echo htmlspecialchars($filled[$sf['key']] ?? ''); ?>" <?php echo $item['is_checked'] ? 'disabled' : ''; ?>>
                                                                </div>
                                                                <?php endforeach; ?>

                                                                <?php if (!empty($schema['checklist'])): ?>
                                                                <?php $checked_items = $filled['checklist'] ?? []; ?>
                                                                <div class="form-group">
                                                                <?php foreach ($schema['checklist'] as $sec_idx => $section): ?>
                                                                    <div style="font-weight:800;color:#0f2557;font-size:13px;margin:14px 0 8px;"><?php echo htmlspecialchars($section['section']); ?></div>
                                                                    <?php foreach ($section['items'] as $it_idx => $ci): ?>
                                                                        <?php $ckey = $sec_idx . '_' . $it_idx; $is_ck = !empty($checked_items[$ckey]); ?>
                                                                        <label style="display:flex;align-items:flex-start;gap:8px;font-size:13px;font-weight:500;margin-bottom:6px;cursor:<?php echo $item['is_checked'] ? 'default' : 'pointer'; ?>;">
                                                                            <input type="checkbox" class="checklist-cb" data-ckey="<?php echo $ckey; ?>" <?php echo $is_ck ? 'checked' : ''; ?> <?php echo $item['is_checked'] ? 'disabled' : ''; ?> style="margin-top:2px;">
                                                                            <?php echo htmlspecialchars($ci); ?>
                                                                        </label>
                                                                    <?php endforeach; ?>
                                                                <?php endforeach; ?>
                                                                </div>
                                                                <?php endif; ?>

                                                                <?php if (!empty($schema['table'])): ?>
                                                                <div class="form-group">
                                                                    <label style="font-weight:700;font-size:12px;">Asset Details</label>
                                                                    <div class="table-responsive">
                                                                    <table class="table table-bordered table-sm" id="assetTable_<?php echo $item['id']; ?>">
                                                                        <thead><tr><?php foreach ($schema['table']['columns'] as $col): ?><th style="font-size:11px;"><?php echo htmlspecialchars($col); ?></th><?php endforeach; ?><?php if (!$item['is_checked']): ?><th></th><?php endif; ?></tr></thead>
                                                                        <tbody>
                                                                        <?php
                                                                        $table_rows = $filled['table'] ?? [[]];
                                                                        if (empty($table_rows)) $table_rows = [[]];
                                                                        foreach ($table_rows as $trow):
                                                                        ?>
                                                                        <tr>
                                                                            <?php foreach ($schema['table']['columns'] as $ci => $col): ?>
                                                                            <td><input type="text" class="form-control form-control-sm asset-cell" value="<?php echo htmlspecialchars($trow[$ci] ?? ''); ?>" <?php echo $item['is_checked'] ? 'disabled' : ''; ?>></td>
                                                                            <?php endforeach; ?>
                                                                            <?php if (!$item['is_checked']): ?><td><button type="button" class="btn btn-sm btn-outline-danger" onclick="this.closest('tr').remove()"><i class="fas fa-times"></i></button></td><?php endif; ?>
                                                                        </tr>
                                                                        <?php endforeach; ?>
                                                                        </tbody>
                                                                    </table>
                                                                    </div>
                                                                    <?php if (!$item['is_checked']): ?>
                                                                    <button type="button" class="btn btn-sm btn-outline-primary" onclick="addAssetRow(<?php echo $item['id']; ?>, <?php echo count($schema['table']['columns']); ?>)"><i class="fas fa-plus"></i> Add Row</button>
                                                                    <?php endif; ?>
                                                                </div>
                                                                <?php endif; ?>

                                                                <div style="font-size:13px;color:#334155;line-height:1.7;background:#fff;border:1px solid #e2e8f0;border-radius:8px;padding:14px;margin-top:10px;">
                                                                    <?php echo nl2br($body_txt); ?>
                                                                </div>

                                                                <?php if (!$item['is_checked']): ?>
                                                                <div style="margin-top:16px;">
                                                                    <label style="font-weight:700;font-size:12px;">Draw Your Signature</label><br>
                                                                    <canvas id="sigCanvas_<?php echo $item['id']; ?>" style="border:2px dashed #cbd5e1;border-radius:10px;background:#f8faff;cursor:crosshair;width:100%;height:140px;"></canvas>
                                                                    <button type="button" class="btn btn-sm btn-link" onclick="clearFillSig(<?php echo $item['id']; ?>)">Clear Signature</button>
                                                                </div>
                                                                <?php endif; ?>
                                                            </form>
                                                        </div>
                                                        <div class="modal-footer">
                                                            <button type="button" class="btn btn-outline-primary" onclick="window.open('<?php echo $view_item_base_url; ?>?view_item=<?php echo $item['id']; ?>', '_blank')"><i class="fas fa-print"></i> Print / Download</button>
                                                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                                                            <?php if (!$item['is_checked']): ?>
                                                            <button type="button" class="btn btn-primary" onclick="submitFillable(<?php echo $item['id']; ?>, <?php echo $r['id']; ?>)"><i class="fas fa-check"></i> Sign & Submit</button>
                                                            <?php endif; ?>
                                                        </div>
                                                    </div>
                                                </div>
                                            </div>
                                        <?php else: ?>
                                            <div class="checklist-row <?php echo $item['is_checked'] ? 'is-done' : ''; ?>" id="row_<?php echo $item['id']; ?>">
                                                <input type="checkbox" class="check-box-input item-checkbox" data-run-id="<?php echo $r['id']; ?>" data-row-id="<?php echo $item['id']; ?>" data-original-checked="<?php echo $item['is_checked'] ? '1' : '0'; ?>" <?php echo $item['is_checked'] ? 'checked' : ''; ?>>
                                                <div style="flex:1;">
                                                    <div class="item-text <?php echo $item['is_checked'] ? 'is-done' : ''; ?>"><?php echo htmlspecialchars($item['item_text']); ?></div>
                                                    <?php if (!empty($item['description'])): ?>
                                                        <div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div>
                                                    <?php endif; ?>
                                                    <div>
                                                        <?php if (!empty($item['document_path'])): ?>
                                                            <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="attach-pill doc"><i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?></a>
                                                        <?php endif; ?>
                                                        <?php if (!empty($item['video_path'])): ?>
                                                            <span class="attach-pill vid"><i class="fas fa-video"></i> <?php echo htmlspecialchars($item['video_filename']); ?></span>
                                                        <?php endif; ?>
                                                    </div>
                                                    <?php if (!empty($item['video_path'])): ?>
                                                        <video class="preview-video" controls preload="metadata">
                                                            <source src="<?php echo htmlspecialchars($item['video_path']); ?>">
                                                        </video>
                                                    <?php endif; ?>
                                                    <?php if ($item['is_checked']): ?>
                                                        <div class="checked-meta" style="margin-bottom:6px;">
                                                            <i class="fas fa-check-circle"></i>
                                                            Marked done by <?php echo htmlspecialchars($item['checked_by_name']); ?>
                                                            (<?php echo $item['checked_by_type'] == 'hr' ? 'HR' : 'Employee'; ?>)
                                                            on <?php echo date('d M Y, h:i A', strtotime($item['checked_at'])); ?>
                                                        </div>
                                                        <?php if (!empty($item['signature_data'])): ?>
                                                            <div style="margin-top:4px;">
                                                                <img src="<?php echo htmlspecialchars($item['signature_data']); ?>" alt="Employee Signature" style="max-height:80px; border:1px solid #ddd6fe; border-radius:8px; background:#faf5ff; padding:4px; display:block;" />
                                                            </div>
                                                        <?php endif; ?>
                                                    <?php endif; ?>
                                                </div>
                                            </div>
                                        <?php endif; ?>
                                        <?php endforeach; ?>
                                    </div>
                                </div>
                            <?php endforeach; endif; ?>

                            <?php if ($r['total_items'] > 0 && $r['done_items'] == $r['total_items']): ?>
                                <?php if (!empty($r['final_signature_data'])): ?>
                                <div style="margin-top:20px;padding:18px 22px;background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;border-radius:12px;">
                                    <div style="font-weight:800;color:#065f46;font-size:14px;margin-bottom:8px;"><i class="fas fa-check-circle mr-2"></i>Checklist signed by <?php echo htmlspecialchars($r['final_signed_by']); ?> on <?php echo date('d M Y, h:i A', strtotime($r['final_signed_at'])); ?></div>
                                    <img src="<?php echo htmlspecialchars($r['final_signature_data']); ?>" alt="Final Signature" style="max-height:80px;border:1px solid #86efac;border-radius:8px;background:#fff;padding:4px;">
                                </div>
                                <?php else: ?>
                                <div style="margin-top:20px;padding:18px 22px;background:linear-gradient(135deg,#eff6ff,#dbeafe);border:2px solid #93c5fd;border-radius:12px;">
                                    <div style="font-weight:800;color:#1e40af;font-size:14px;margin-bottom:10px;"><i class="fas fa-file-signature mr-2"></i>All items complete — please sign below to confirm this checklist.</div>
                                    <?php $cs_final = $r['company_settings'] ?? []; ?>
                                    <div style="border:1px solid #bfdbfe;border-radius:10px;padding:12px 16px;margin-bottom:12px;background:#fff;">
                                        <div style="font-weight:800;font-size:13px;color:#0f2557;"><?php echo htmlspecialchars($cs_final['company_name'] ?? 'ABRA GROUPS'); ?></div>
                                        <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($cs_final['company_email'] ?? ''); ?> <?php echo !empty($cs_final['company_phone']) ? ' | ' . htmlspecialchars($cs_final['company_phone']) : ''; ?></div>
                                    </div>
                                    <p style="font-size:12px;color:#1e3a8a;">I, <?php echo htmlspecialchars($r['candidate_name']); ?>, confirm that I have completed and reviewed all items in this onboarding checklist.</p>
                                    <canvas id="finalSigCanvas_<?php echo $r['id']; ?>" style="border:2px dashed #93c5fd;border-radius:10px;background:#f8faff;cursor:crosshair;width:100%;height:140px;"></canvas>
                                    <div style="margin-top:8px;display:flex;gap:8px;">
                                        <button type="button" class="btn btn-sm btn-link" onclick="clearFinalSig(<?php echo $r['id']; ?>)">Clear</button>
                                        <button type="button" class="btn btn-primary btn-sm" onclick="submitFinalSignature(<?php echo $r['id']; ?>)"><i class="fas fa-check"></i> Confirm & Sign Checklist</button>
                                    </div>
                                </div>
                                <?php endif; ?>
                            <?php endif; ?>

                            <!-- Save Progress Button -->
                            <div id="saveBar_<?php echo $r['id']; ?>" style="display:none;margin-top:20px;padding:16px 20px;background:linear-gradient(135deg,#eff6ff,#dbeafe);border:2px solid #93c5fd;border-radius:12px;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
                                <div style="display:flex;align-items:center;gap:10px;">
                                    <span style="font-size:20px;">📝</span>
                                    <div>
                                        <div style="font-weight:800;color:#1e40af;font-size:13px;">You have unsaved changes</div>
                                        <div style="font-size:11px;color:#3b82f6;">Click Save Progress to record your selections.</div>
                                    </div>
                                </div>
                                <button type="button" onclick="saveProgress(<?php echo $r['id']; ?>)" id="saveBtn_<?php echo $r['id']; ?>" style="padding:10px 24px;border:none;border-radius:10px;background:linear-gradient(135deg,#1e3a8a,#1e40af);color:#fff;font-weight:800;font-size:13px;cursor:pointer;display:flex;align-items:center;gap:8px;">
                                    <i class="fas fa-save"></i> Save Progress
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>

</div>

<?php if ($is_hr_user): ?>
<!-- Reject Fillable Document Modal -->
<div class="modal fade" id="rejectFillableModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header" style="background:linear-gradient(135deg,#ef4444,#dc2626);">
                <h4 class="modal-title" style="color:#fff;">Reject Document</h4>
                <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
            </div>
            <div class="modal-body">
                <input type="hidden" id="rejectItemId">
                <label style="font-weight:700;font-size:13px;">Reason for Rejection <span style="color:#dc2626;">*</span></label>
                <textarea id="rejectReasonInput" class="form-control" rows="4" placeholder="e.g. Details entered are incorrect, please re-check and resubmit."></textarea>
                <p style="font-size:12px;color:#64748b;margin-top:8px;">The employee will be notified via a ticket and asked to resubmit.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
                <button type="button" class="btn btn-danger" onclick="submitRejectFillable()"><i class="fas fa-times"></i> Confirm Rejection</button>
            </div>
        </div>
    </div>
</div>

<!-- Start New Run Modal (promotion / re-run scenario) -->
<div class="modal fade" id="newRunModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="POST">
                <input type="hidden" name="action" value="start_new_run">
                <div class="modal-header">
                    <h4 class="modal-title">Start New Checklist Run</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Employee</label>
                        <select name="candidate_id" id="newRunCandidate" class="form-control" required onchange="fillCandidateName()">
                            <option value="">-- Select Hired Employee --</option>
                            <?php foreach ($hired_candidates_arr as $c): ?>
                                <option value="<?php echo $c['id']; ?>" data-name="<?php echo htmlspecialchars($c['name']); ?>"><?php echo htmlspecialchars($c['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                        <input type="hidden" name="candidate_name" id="newRunCandidateName">
                    </div>
                    <small class="text-muted">Use this for manually re-triggering a checklist. Past completions for this employee are preserved as separate history.</small>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-success">Start Checklist</button>
                </div>
            </form>
        </div>
    </div>
</div>
<?php endif; ?>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function fillCandidateName() {
    var sel = document.getElementById('newRunCandidate');
    var opt = sel.options[sel.selectedIndex];
    document.getElementById('newRunCandidateName').value = opt ? (opt.getAttribute('data-name') || '') : '';
}

function filterRuns() {
    var nameInput = document.getElementById('employeeSearchInput');
    var deptSel   = document.getElementById('filterDept');
    var posSel    = document.getElementById('filterPos');
    var statusSel = document.getElementById('filterStatus');

    var nameFilter   = nameInput ? nameInput.value.toLowerCase() : '';
    var deptFilter   = deptSel ? deptSel.value : '';
    var posFilter    = posSel ? posSel.value : '';
    var statusFilter = statusSel ? statusSel.value : '';

    var runs = document.querySelectorAll('#runsAccordion > .card-box');
    runs.forEach(function(card) {
        var nameEl = card.querySelector('.name');
        var txtValue = nameEl ? (nameEl.textContent || nameEl.innerText) : '';
        var matchesName   = !nameFilter || txtValue.toLowerCase().indexOf(nameFilter) > -1;
        var matchesDept   = !deptFilter || card.getAttribute('data-department') === deptFilter;
        var matchesPos    = !posFilter || card.getAttribute('data-position') === posFilter;
        var matchesStatus = !statusFilter || card.getAttribute('data-status') === statusFilter;

        card.style.display = (matchesName && matchesDept && matchesPos && matchesStatus) ? "" : "none";
    });
}

function resetChecklistFilters() {
    var nameInput = document.getElementById('employeeSearchInput');
    var deptSel   = document.getElementById('filterDept');
    var posSel    = document.getElementById('filterPos');
    var statusSel = document.getElementById('filterStatus');
    if (nameInput) nameInput.value = '';
    if (deptSel) deptSel.value = '';
    if (posSel) posSel.value = '';
    if (statusSel) statusSel.value = '';
    filterRuns();
}

function doExport(type) {
    var nameInput = document.getElementById('employeeSearchInput');
    var deptSel   = document.getElementById('filterDept');
    var posSel    = document.getElementById('filterPos');
    var statusSel = document.getElementById('filterStatus');

    var params = new URLSearchParams();
    params.set('export', type);
    if (nameInput && nameInput.value) params.set('f_name', nameInput.value);
    if (deptSel && deptSel.value) params.set('f_dept', deptSel.value);
    if (posSel && posSel.value) params.set('f_pos', posSel.value);
    if (statusSel && statusSel.value) params.set('f_status', statusSel.value);

    window.location.href = 'hr-checklist.php?' + params.toString();
}

// Removed loadPositionsForNewRun()

// Track pending changes per run
var pendingChanges = {};

// Checkbox change — mark visually, show Save button ONLY if value actually differs from saved state
document.querySelectorAll('.item-checkbox').forEach(function(cb) {
    cb.addEventListener('change', function() {
        var runId = this.getAttribute('data-run-id');
        var rowId = this.getAttribute('data-row-id');
        var checked = this.checked ? 1 : 0;
        var originalChecked = parseInt(this.getAttribute('data-original-checked'), 10);
        var row = document.getElementById('row_' + rowId);
        var textEl = row.querySelector('.item-text');

        // Visual feedback immediately
        row.classList.toggle('is-done', checked == 1);
        if (textEl) textEl.classList.toggle('is-done', checked == 1);

        var saveBar = document.getElementById('saveBar_' + runId);

        if (checked === originalChecked) {
            // No real change from what's saved — clear any pending entry for this row
            if (pendingChanges[runId]) delete pendingChanges[runId][rowId];

            // Hide save bar for this run if nothing else is pending
            if (saveBar && (!pendingChanges[runId] || Object.keys(pendingChanges[runId]).length === 0)) {
                saveBar.style.display = 'none';
            }
            return;
        }

        // Track pending change
        if (!pendingChanges[runId]) pendingChanges[runId] = {};
        pendingChanges[runId][rowId] = checked;

        // Show save bar for this run
        if (saveBar) saveBar.style.display = 'flex';
    });
});

// Save all pending changes for a run
function saveProgress(runId) {
    var changes = pendingChanges[runId];
    if (!changes || Object.keys(changes).length === 0) return;

    var btn = document.getElementById('saveBtn_' + runId);
    var oldHtml = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
    btn.disabled = true;

    var rowIds = Object.keys(changes);
    var saved = 0;
    var lastDone = 0, lastTotal = 0;

    rowIds.forEach(function(rowId) {
        var checked = changes[rowId];
        $.post('', { ajax_action: 'toggle_item', item_row_id: rowId, checked: checked }, function(resp) {
            var data = JSON.parse(resp);
            saved++;
            if (data.success) {
                lastDone = data.done;
                lastTotal = data.total;
            }
            if (saved === rowIds.length) {
                // All done — update UI
                var pct = lastTotal > 0 ? Math.round((lastDone / lastTotal) * 100) : 0;
                var label = document.getElementById('progressLabel_' + runId);
                var pctEl = document.getElementById('progressPct_' + runId);
                var bar = document.getElementById('progressBarFill_' + runId);
                var statusPill = document.getElementById('statusPill_' + runId);
                if (label) label.textContent = lastDone + ' / ' + lastTotal + ' done';
                if (pctEl) pctEl.textContent = pct + '%';
                if (bar) bar.style.width = pct + '%';
                if (statusPill) {
                    if (lastDone === lastTotal && lastTotal > 0) {
                        statusPill.className = 'status-pill completed';
                        statusPill.textContent = 'Completed';
                    } else {
                        statusPill.className = 'status-pill in_progress';
                        statusPill.textContent = 'In Progress';
                    }
                }

                // Clear pending, hide save bar, show success then reload
                pendingChanges[runId] = {};
                btn.innerHTML = '<i class="fas fa-check"></i> Saved!';
                btn.style.background = 'linear-gradient(135deg,#10b981,#059669)';
                setTimeout(function() {
                    location.reload();
                }, 800);
            }
        });
    });
}

function this_checked_revert(rowId, val) {
    var cb = document.querySelector('.item-checkbox[data-row-id="' + rowId + '"]');
    if (cb) cb.checked = val;
}

// ---- Generic signature pad setup (fillable-doc modals + final signature) ----
var sigPads = {};
function setupSigPad(canvasId) {
    var canvas = document.getElementById(canvasId);
    if (!canvas || sigPads[canvasId]) return;
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    var ctx = canvas.getContext('2d');
    ctx.strokeStyle = '#1a3fc4'; ctx.lineWidth = 2; ctx.lineCap = 'round';
    var drawing = false;
    function pos(e) {
        var r = canvas.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    }
    canvas.addEventListener('mousedown', function(e){ drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); });
    canvas.addEventListener('mousemove', function(e){ if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); });
    canvas.addEventListener('mouseup', function(){ drawing = false; });
    canvas.addEventListener('mouseleave', function(){ drawing = false; });
    canvas.addEventListener('touchstart', function(e){ e.preventDefault(); drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); }, {passive:false});
    canvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); }, {passive:false});
    canvas.addEventListener('touchend', function(e){ e.preventDefault(); drawing = false; }, {passive:false});
    sigPads[canvasId] = canvas;
}

function isSigBlank(canvasId) {
    var canvas = document.getElementById(canvasId);
    var blank = document.createElement('canvas');
    blank.width = canvas.width; blank.height = canvas.height;
    return canvas.toDataURL() === blank.toDataURL();
}

$(document).on('shown.bs.modal', '.modal', function() {
    var canvas = $(this).find('canvas')[0];
    if (canvas) setupSigPad(canvas.id);
});

function clearFillSig(itemId) {
    var canvas = document.getElementById('sigCanvas_' + itemId);
    if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
}

function clearFinalSig(runId) {
    var canvas = document.getElementById('finalSigCanvas_' + runId);
    if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
}

function addAssetRow(itemId, colCount) {
    var tbody = document.querySelector('#assetTable_' + itemId + ' tbody');
    var tr = document.createElement('tr');
    for (var i = 0; i < colCount; i++) {
        var td = document.createElement('td');
        td.innerHTML = '<input type="text" class="form-control form-control-sm asset-cell">';
        tr.appendChild(td);
    }
    var tdBtn = document.createElement('td');
    tdBtn.innerHTML = '<button type="button" class="btn btn-sm btn-outline-danger" onclick="this.closest(\'tr\').remove()"><i class="fas fa-times"></i></button>';
    tr.appendChild(tdBtn);
    tbody.appendChild(tr);
}

function submitFillable(itemId, runId) {
    var canvasId = 'sigCanvas_' + itemId;
    if (isSigBlank(canvasId)) { alert('Please sign before submitting.'); return; }

    var data = {};
    document.querySelectorAll('#fillForm_' + itemId + ' .fillable-field').forEach(function(inp) {
        data[inp.getAttribute('data-key')] = inp.value;
    });

    var checklistData = {};
    document.querySelectorAll('#fillForm_' + itemId + ' .checklist-cb').forEach(function(cb) {
        checklistData[cb.getAttribute('data-ckey')] = cb.checked;
    });
    if (Object.keys(checklistData).length > 0) data.checklist = checklistData;

    var table = document.getElementById('assetTable_' + itemId);
    if (table) {
        var rows = [];
        table.querySelectorAll('tbody tr').forEach(function(tr) {
            var cells = [];
            tr.querySelectorAll('.asset-cell').forEach(function(c) { cells.push(c.value); });
            if (cells.some(function(v) { return v.trim() !== ''; })) rows.push(cells);
        });
        data.table = rows;
    }

    var signature = document.getElementById(canvasId).toDataURL();

    $.post('', {
        ajax_action: 'save_fillable',
        item_row_id: itemId,
        filled_data: JSON.stringify(data),
        signature_data: signature
    }, function(resp) {
        var r = JSON.parse(resp);
        if (r.success) {
            location.reload();
        } else {
            alert(r.message || 'Could not save. Please try again.');
        }
    });
}

function submitFinalSignature(runId) {
    var canvasId = 'finalSigCanvas_' + runId;
    if (isSigBlank(canvasId)) { alert('Please sign before confirming.'); return; }
    var signature = document.getElementById(canvasId).toDataURL();
    $.post('', { ajax_action: 'save_final_signature', run_id: runId, signature_data: signature }, function(resp) {
        var r = JSON.parse(resp);
        if (r.success) {
            location.reload();
        } else {
            alert(r.message || 'Could not save signature.');
        }
    });
}

function approveFillable(itemId, runId) {
    if (!confirm('Approve this signed document? It will be marked complete and saved to the employee\'s records.')) return;
    $.post('', { ajax_action: 'approve_fillable', item_row_id: itemId }, function(resp) {
        var r = typeof resp === 'string' ? JSON.parse(resp) : resp;
        if (r.success) { location.reload(); } else { alert(r.message || 'Could not approve. Please try again.'); }
    });
}

function openRejectFillableModal(itemId) {
    document.getElementById('rejectItemId').value = itemId;
    document.getElementById('rejectReasonInput').value = '';
    $('#rejectFillableModal').modal('show');
}

function submitRejectFillable() {
    var itemId = document.getElementById('rejectItemId').value;
    var reason = document.getElementById('rejectReasonInput').value.trim();
    if (!reason) { alert('Please provide a reason for rejection.'); return; }
    $.post('', { ajax_action: 'reject_fillable', item_row_id: itemId, reason: reason }, function(resp) {
        var r = typeof resp === 'string' ? JSON.parse(resp) : resp;
        if (r.success) { $('#rejectFillableModal').modal('hide'); location.reload(); } else { alert(r.message || 'Could not reject. Please try again.'); }
    });
}
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