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
// !!! CONFIG — PLEASE CONFIRM/EDIT THESE 7 LINES TO MATCH YOUR ACTUAL SCHEMA !!!
// I don't have hr_screening.php's exact candidate table/column names in front
// of me right now, so these are my best-guess placeholders. Everything below
// this block reads from these variables only, so fixing these 7 lines is all
// that's needed to wire it up correctly if any guess is wrong.
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
// candidate_id from session to show only THEIR checklist(s).
$logged_in_candidate_id = isset($_SESSION['candidate_id']) ? intval($_SESSION['candidate_id']) : 0;

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

    mysqli_query($con, "INSERT INTO hr_checklist_runs
        (candidate_id, candidate_name, department_id, department_name, position_id, position_name, status, created_by)
        VALUES ($cand_id_e, '$cand_name_e', $dept_id_e, '$dept_name_e', $pos_id_e, '$pos_name_e', 'in_progress', '$created_by_e')");
    $run_id = mysqli_insert_id($con);

    // Merge Department-level (position_id=0) + Position-level (position_id=$pos_id) items, snapshot them
    $scopes = [
        ['pos' => 0,        'level' => 'department'],
        ['pos' => $pos_id_e,'level' => 'position'],
    ];
    foreach ($scopes as $scope) {
        $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings WHERE department_id=$dept_id_e AND position_id=" . $scope['pos'] . " ORDER BY sort_order ASC, id ASC");
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

                mysqli_query($con, "INSERT INTO hr_checklist_run_items
                    (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort)
                    VALUES ($run_id, '$heading_name_e', " . intval($h['sort_order']) . ", '" . $scope['level'] . "', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ")");
            }
        }
    }
    return $run_id;
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
// AJAX: TOGGLE ITEM CHECK (employee ticks their own / HR overrides)
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'toggle_item') {
    header('Content-Type: application/json');
    $item_row_id = intval($_POST['item_row_id']);
    $checked     = intval($_POST['checked']) == 1 ? 1 : 0;

    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT run_id FROM hr_checklist_run_items WHERE id=$item_row_id"));
    if (!$row) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    $run_chk = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id FROM hr_checklist_runs WHERE id=" . intval($row['run_id'])));
    if (!$is_hr_user && $run_chk && intval($run_chk['candidate_id']) !== $logged_in_candidate_id) {
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
// FORM: START NEW RUN MANUALLY (HR only — e.g. promotion to a new position)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'start_new_run' && $is_hr_user) {
    $cand_id   = intval($_POST['candidate_id']);
    $cand_name = trim($_POST['candidate_name']);
    $dept_id   = intval($_POST['department_id']);
    $pos_id    = intval($_POST['position_id']);
    if ($cand_id > 0 && $dept_id > 0 && $pos_id > 0) {
        $new_run_id = create_checklist_run($con, $cand_id, $cand_name, $dept_id, $pos_id, $currentUserName);
        $_SESSION['success_message'] = "New checklist run started.";
        header("Location: $current_page?run_id=$new_run_id");
        exit;
    } else {
        $_SESSION['error_message'] = "Please select Candidate, Department and Position.";
        header("Location: $current_page");
        exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================
$view_run_id = isset($_GET['run_id']) ? intval($_GET['run_id']) : 0;

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

if ($view_run_id > 0) {
    // ---- DETAIL VIEW: single checklist run ----
    $run = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE id=$view_run_id"));
    if (!$run) { die("Checklist run not found."); }

    if (!$is_hr_user && intval($run['candidate_id']) !== $logged_in_candidate_id) {
        die("You are not authorized to view this checklist.");
    }

    $items_res = mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE run_id=$view_run_id ORDER BY scope_level DESC, heading_sort ASC, item_sort ASC, id ASC");
    $grouped = [];
    $total_items = 0; $done_items = 0;
    while ($it = mysqli_fetch_assoc($items_res)) {
        $key = $it['scope_level'] . '||' . $it['heading_name'];
        if (!isset($grouped[$key])) {
            $grouped[$key] = ['heading_name' => $it['heading_name'], 'scope_level' => $it['scope_level'], 'items' => []];
        }
        $grouped[$key]['items'][] = $it;
        $total_items++;
        if ($it['is_checked']) $done_items++;
    }

    if ($total_items == 0 && $is_hr_user) {
        $added = 0;
        $dept_id_e = intval($run['department_id']);
        $pos_id_e = intval($run['position_id']);
        $scopes = [
            ['pos' => 0,        'level' => 'department'],
            ['pos' => $pos_id_e,'level' => 'position'],
        ];
        foreach ($scopes as $scope) {
            $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings WHERE department_id=$dept_id_e AND position_id=" . $scope['pos'] . " ORDER BY sort_order ASC, id ASC");
            while ($h = mysqli_fetch_assoc($h_res)) {
                $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . intval($h['id']) . " AND is_active=1 ORDER BY sort_order ASC, id ASC");
                while ($it = mysqli_fetch_assoc($i_res)) {
                    $added++;
                    $heading_name_e = mysqli_real_escape_string($con, $h['heading_name']);
                    $item_text_e    = mysqli_real_escape_string($con, $it['item_text']);
                    $desc_e         = mysqli_real_escape_string($con, $it['description'] ?? '');
                    $doc_path_sql   = $it['document_path']     ? "'" . mysqli_real_escape_string($con, $it['document_path']) . "'"     : "NULL";
                    $doc_fname_sql  = $it['document_filename']  ? "'" . mysqli_real_escape_string($con, $it['document_filename']) . "'"  : "NULL";
                    $vid_path_sql   = $it['video_path']         ? "'" . mysqli_real_escape_string($con, $it['video_path']) . "'"         : "NULL";
                    $vid_fname_sql  = $it['video_filename']     ? "'" . mysqli_real_escape_string($con, $it['video_filename']) . "'"      : "NULL";

                    mysqli_query($con, "INSERT INTO hr_checklist_run_items
                        (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort)
                        VALUES ($view_run_id, '$heading_name_e', " . intval($h['sort_order']) . ", '" . $scope['level'] . "', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ")");
                }
            }
        }
        if ($added > 0) {
            header("Location: $current_page?run_id=$view_run_id");
            exit;
        }
    }

    $progress_pct = $total_items > 0 ? round(($done_items / $total_items) * 100) : 0;
} else {
    // ---- LIST VIEW: all runs (HR sees all, employee sees only their own) ----
    if ($is_hr_user) {
        $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs ORDER BY created_at DESC");
    } else {
        $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE candidate_id=$logged_in_candidate_id ORDER BY created_at DESC");
    }
    $runs_arr = [];
    while ($r = mysqli_fetch_assoc($runs_res)) {
        $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=" . $r['id']));
        $r['total_items'] = intval($tot['total']);
        $r['done_items']  = intval($tot['done']);
        $r['progress_pct'] = $r['total_items'] > 0 ? round(($r['done_items'] / $r['total_items']) * 100) : 0;
        $runs_arr[] = $r;
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?> | Onboarding Checklist</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    .container-fluid { max-width: 1400px; margin: 0 auto; padding: 0 20px; }

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
    .progress-bar { background: linear-gradient(90deg,#10b981,#059669); }
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
    }
    .checklist-row.is-done { background: #f0fdf4; border-color: #bbf7d0; }
    .check-box-input { width: 20px; height: 20px; margin-top: 2px; cursor: pointer; flex-shrink: 0; }
    .item-text { font-weight: 700; color: #0f2557; font-size: 13.5px; margin-bottom: 4px; }
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

    .top-progress-summary { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
    .empty-hint { text-align: center; padding: 40px; color: #94a3b8; }
    .config-warning {
      background: #fff7ed; border: 1px solid #fed7aa; color: #92400e; padding: 12px 16px;
      border-radius: 8px; font-size: 13px; margin-bottom: 16px;
    }
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
            <h1><i class="fas fa-tasks mr-2"></i> <?php echo $view_run_id > 0 ? 'Onboarding Checklist' : 'Onboarding Checklists'; ?></h1>
        </div>
        <div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap;">
            <?php if ($view_run_id == 0 && $is_hr_user): ?>
            <!-- Quick Select Employee Dropdown -->
            <form method="GET" class="form-inline m-0 p-0" id="quickSelectForm">
                <select class="form-control" onchange="if(this.value) window.location.href='?run_id='+this.value;">
                    <option value="">-- View Employee Checklist --</option>
                    <?php 
                    // Fetch existing runs for quick selection
                    $qs_res = mysqli_query($con, "SELECT id, candidate_name FROM hr_checklist_runs ORDER BY candidate_name ASC");
                    while ($qs_row = mysqli_fetch_assoc($qs_res)):
                    ?>
                        <option value="<?php echo $qs_row['id']; ?>"><?php echo htmlspecialchars($qs_row['candidate_name']); ?></option>
                    <?php endwhile; ?>
                </select>
            </form>
            <?php endif; ?>

            <?php if ($view_run_id > 0): ?>
                <a href="<?php echo $current_page; ?>" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back to List</a>
            <?php elseif ($is_hr_user): ?>
                <a href="hr_screening.php" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back to Screening</a>
                <button class="btn btn-success" data-toggle="modal" data-target="#newRunModal"><i class="fas fa-plus"></i> Start New Run</button>
            <?php endif; ?>
        </div>
    </div>

    <?php if ($is_hr_user): ?>
    <div class="config-warning">
        <i class="fas fa-info-circle mr-1"></i>
        Heads up — the candidate table/column names at the top of this file (<code>$CANDIDATES_TABLE</code>, <code>$CAND_DECISION_COL</code>, etc.) and the HR/Employee role check are best-guess placeholders. Confirm these against your actual schema so the "hired → auto checklist" trigger fires correctly.
    </div>
    <?php endif; ?>

    <?php if ($view_run_id > 0): ?>
        <!-- ============================= DETAIL VIEW ============================= -->
        <div class="card-box">
            <div class="top-progress-summary">
                <div>
                    <div style="font-weight:800; color:#0f2557; font-size:18px;"><?php echo htmlspecialchars($run['candidate_name']); ?></div>
                    <div class="meta" style="color:#64748b; font-size:13px;">
                        <?php echo htmlspecialchars($run['department_name']); ?> &middot; <?php echo htmlspecialchars($run['position_name']); ?>
                        &middot; Started <?php echo date('d M Y', strtotime($run['created_at'])); ?>
                    </div>
                </div>
                <span class="status-pill <?php echo $run['status']; ?>"><?php echo $run['status'] == 'completed' ? 'Completed' : 'In Progress'; ?></span>
                <div class="progress-wrap">
                    <div class="d-flex justify-content-between mb-1">
                        <small id="progressLabel" style="font-weight:700;color:#0f2557;"><?php echo $done_items; ?> / <?php echo $total_items; ?> done</small>
                        <small id="progressPct" style="font-weight:700;color:#10b981;"><?php echo $progress_pct; ?>%</small>
                    </div>
                    <div class="progress">
                        <div class="progress-bar" id="progressBarFill" role="progressbar" style="width: <?php echo $progress_pct; ?>%"></div>
                    </div>
                </div>
            </div>
        </div>

        <?php if (empty($grouped)): ?>
            <div class="card-box"><div class="empty-hint"><i class="fas fa-list-ul fa-3x mb-3"></i><h5>No checklist items found for this department/position yet. Add some in the Checklist Configuration screen.</h5></div></div>
        <?php else: foreach ($grouped as $group): ?>
            <div class="card-box">
                <div class="heading-block">
                    <div class="heading-block-head">
                        <h6><i class="fas fa-layer-group mr-2" style="color:<?php echo $group['scope_level']=='department' ? '#1e3a8a' : '#5b21b6'; ?>;"></i><?php echo htmlspecialchars($group['heading_name']); ?></h6>
                        <span class="scope-badge <?php echo $group['scope_level']; ?>"><?php echo $group['scope_level'] == 'department' ? 'Department-Level' : 'Position-Level'; ?></span>
                    </div>
                    <div class="heading-block-body">
                        <?php foreach ($group['items'] as $item): ?>
                            <div class="checklist-row <?php echo $item['is_checked'] ? 'is-done' : ''; ?>" id="row_<?php echo $item['id']; ?>">
                                <input type="checkbox" class="check-box-input item-checkbox" data-row-id="<?php echo $item['id']; ?>" <?php echo $item['is_checked'] ? 'checked' : ''; ?>>
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
                                        <div class="checked-meta">
                                            <i class="fas fa-check-circle"></i>
                                            Marked done by <?php echo htmlspecialchars($item['checked_by_name']); ?>
                                            (<?php echo $item['checked_by_type'] == 'hr' ? 'HR' : 'Employee'; ?>)
                                            on <?php echo date('d M Y, h:i A', strtotime($item['checked_at'])); ?>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>
        <?php endforeach; endif; ?>

    <?php else: ?>
        <!-- ============================= LIST VIEW ============================= -->
        <div class="card-box">
            <?php if (empty($runs_arr)): ?>
                <div class="empty-hint">
                    <i class="fas fa-clipboard-list fa-3x mb-3"></i>
                    <h5><?php echo $is_hr_user ? 'No onboarding checklists yet. They will appear automatically once a candidate is marked Hired.' : 'You don\'t have an onboarding checklist yet.'; ?></h5>
                </div>
            <?php else: foreach ($runs_arr as $r): ?>
                <a href="<?php echo $current_page; ?>?run_id=<?php echo $r['id']; ?>" style="text-decoration:none;">
                    <div class="run-card">
                        <div>
                            <div class="name"><?php echo htmlspecialchars($r['candidate_name']); ?></div>
                            <div class="meta"><?php echo htmlspecialchars($r['department_name']); ?> &middot; <?php echo htmlspecialchars($r['position_name']); ?> &middot; Started <?php echo date('d M Y', strtotime($r['created_at'])); ?></div>
                        </div>
                        <span class="status-pill <?php echo $r['status']; ?>"><?php echo $r['status'] == 'completed' ? 'Completed' : 'In Progress'; ?></span>
                        <div class="progress-wrap">
                            <div class="d-flex justify-content-between mb-1">
                                <small style="font-weight:700;color:#0f2557;"><?php echo $r['done_items']; ?> / <?php echo $r['total_items']; ?></small>
                                <small style="font-weight:700;color:#10b981;"><?php echo $r['progress_pct']; ?>%</small>
                            </div>
                            <div class="progress"><div class="progress-bar" style="width: <?php echo $r['progress_pct']; ?>%"></div></div>
                        </div>
                    </div>
                </a>
            <?php endforeach; endif; ?>
        </div>
    <?php endif; ?>

</div>

<?php if ($is_hr_user && $view_run_id == 0): ?>
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
                    <div class="form-group">
                        <label>Department</label>
                        <select name="department_id" id="newRunDept" class="form-control" required onchange="loadPositionsForNewRun()">
                            <option value="">-- Select Department --</option>
                            <?php foreach ($departments_arr as $d): ?>
                                <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Position</label>
                        <select name="position_id" id="newRunPos" class="form-control" required>
                            <option value="">-- Select Department First --</option>
                        </select>
                    </div>
                    <small class="text-muted">Use this for promotions, transfers, or to manually re-trigger a checklist. Past completions for this employee are preserved as separate history.</small>
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

function loadPositionsForNewRun() {
    var deptId = document.getElementById('newRunDept').value;
    var posSelect = document.getElementById('newRunPos');
    posSelect.innerHTML = '<option value="">Loading...</option>';
    if (!deptId) { posSelect.innerHTML = '<option value="">-- Select Department First --</option>'; return; }

    $.get('hr-checklist-employee.php', { get_positions: 1, dept_id: deptId }, function(data) {
        var positions = JSON.parse(data);
        var html = '<option value="">-- Select Position --</option>';
        positions.forEach(function(p) {
            html += '<option value="' + p.id + '">' + p.title + '</option>';
        });
        posSelect.innerHTML = html;
    });
}

// Checkbox toggle — AJAX, no page reload
document.querySelectorAll('.item-checkbox').forEach(function(cb) {
    cb.addEventListener('change', function() {
        var rowId = this.getAttribute('data-row-id');
        var checked = this.checked ? 1 : 0;
        var row = document.getElementById('row_' + rowId);
        var textEl = row.querySelector('.item-text');

        $.post('', { ajax_action: 'toggle_item', item_row_id: rowId, checked: checked }, function(resp) {
            var data = JSON.parse(resp);
            if (data.success) {
                row.classList.toggle('is-done', checked == 1);
                textEl.classList.toggle('is-done', checked == 1);
                var pct = data.total > 0 ? Math.round((data.done / data.total) * 100) : 0;
                document.getElementById('progressLabel').textContent = data.done + ' / ' + data.total + ' done';
                document.getElementById('progressPct').textContent = pct + '%';
                document.getElementById('progressBarFill').style.width = pct + '%';
                if (checked == 1) {
                    location.reload(); // reload to show "checked by" meta line cleanly
                }
            } else {
                alert(data.message || 'Could not update item.');
                this_checked_revert(rowId, !checked);
            }
        });
    });
});

function this_checked_revert(rowId, val) {
    var cb = document.querySelector('.item-checkbox[data-row-id="' + rowId + '"]');
    if (cb) cb.checked = val;
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
