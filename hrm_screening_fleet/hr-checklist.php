<?php
session_start();
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

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE (Flutter WebView Auth)
// =========================================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$session_name = trim($_SESSION['user_name'] ?? '');
$emp_data = null;
$db_link = isset($dbConn) ? $dbConn : (isset($con) ? $con : null);

if ($db_link && !empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($db_link, $currentUserEmail);
    $eq = mysqli_query($db_link, "
        SELECT id, employee_id, name, department, position 
        FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
        $_SESSION['user_name'] = $emp_data['name'];
        $_SESSION['user_id'] = $emp_data['id'];
        $session_name = $emp_data['name'];
    }
}

if (!$emp_data && $session_name && $db_link) {
    $safe_name = mysqli_real_escape_string($db_link, $session_name);
    $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name = '$safe_name' AND status = 'Active' LIMIT 1");
    if (!$eq || mysqli_num_rows($eq) == 0) {
        $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name LIKE '$safe_name%' AND status = 'Active' LIMIT 1");
    }
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
    }
}

if (!$emp_data) {
    die("
        <div style='font-family:sans-serif; max-width:600px; margin:60px auto; padding:30px; 
                    border:2px solid #ef4444; border-radius:12px; background:#fef2f2; color:#b91c1c;'>
            <h2 style='margin-top:0;'>&#10060; Authentication Failed</h2>
            <p>Could not identify your employee record.</p>
        </div>
    ");
}

$url_email = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';
// =========================================================================


$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
// isUser();

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

// Add new columns if table already existed before this update
$col_checks_run = [
    ["hr_checklist_run_items", "visible_to_employee", "ALTER TABLE hr_checklist_run_items ADD COLUMN visible_to_employee TINYINT(1) DEFAULT 0 AFTER item_sort"],
    ["hr_checklist_run_items", "require_signature",   "ALTER TABLE hr_checklist_run_items ADD COLUMN require_signature TINYINT(1) DEFAULT 0 AFTER visible_to_employee"],
    ["hr_checklist_run_items", "signature_data",      "ALTER TABLE hr_checklist_run_items ADD COLUMN signature_data LONGTEXT DEFAULT NULL AFTER require_signature"],
];
foreach ($col_checks_run as [$tbl, $col, $sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $sql);
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
            mysqli_query($con, "INSERT INTO hr_checklist_run_items
                (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature)
                VALUES ($run_id, '$heading_name_e', " . intval($h['sort_order']) . ", 'global', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ", $vis_emp_snap, $req_sig_snap)");
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
    $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE candidate_id=$logged_in_candidate_id ORDER BY created_at DESC");
}

$runs_arr = [];
while ($r = mysqli_fetch_assoc($runs_res)) {
    $run_id = intval($r['id']);
    
    $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    $r['total_items'] = intval($tot['total']);
    
    if ($r['total_items'] == 0 && $is_hr_user) {
        $added = 0;
        $dept_id_e = intval($r['department_id']);
        $pos_id_e = intval($r['position_id']);
        $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
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

                $vis_emp_snap = intval($it['visible_to_employee'] ?? 0);
                $req_sig_snap = intval($it['require_signature'] ?? 0);
                mysqli_query($con, "INSERT INTO hr_checklist_run_items
                    (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature)
                    VALUES ($run_id, '$heading_name_e', " . intval($h['sort_order']) . ", 'global', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ", $vis_emp_snap, $req_sig_snap)");
            }
        }
        if ($added > 0) {
            $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
            $r['total_items'] = intval($tot['total']);
        }
    }
    
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
            <a href="<?php echo $dashboard_url; ?>" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
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
                                        <?php endforeach; ?>
                                    </div>
                                </div>
                            <?php endforeach; endif; ?>

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
</script>


<!-- Flutter State Preserver -->
<script>
document.addEventListener("DOMContentLoaded", function() {
    const urlEmail = "<?php echo !empty($currentUserEmail) ? '?user_email=' . urlencode($currentUserEmail) : ''; ?>";
    const urlEmailAmp = "<?php echo !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : ''; ?>";
    if (urlEmail) {
        document.querySelectorAll("a").forEach(a => {
            let href = a.getAttribute("href");
            if (href && href.includes(".php")) {
                if (href.includes("?")) {
                    a.setAttribute("href", href + urlEmailAmp);
                } else {
                    a.setAttribute("href", href + urlEmail);
                }
            }
        });
        document.querySelectorAll("form").forEach(f => {
            if (!f.querySelector('input[name="user_email"]')) {
                let input = document.createElement('input');
                input.type = 'hidden';
                input.name = 'user_email';
                input.value = "<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES); ?>";
                f.appendChild(input);
            }
        });
    }
});
</script>

</body>
</html>
