<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

// =========================================================================
// HR EMPLOYEE PREVIEW CHECKLIST
// Employee-facing view: shows only items marked "visible_to_employee".
// Signature-required items use a signature pad instead of a checkbox.
// HR view: shows ALL items, with HR-Only pills, signature previews, status.
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
// WHO IS VIEWING?
// =========================================================================
// Every logged-in user only ever sees their own checklist — no exceptions.
// Match against hr_employees (the master roster) instead of hr_screenings,
// since employees added directly (before the screening flow existed) never
// have an hr_screenings row at all.
$is_hr_user             = false;
$logged_in_candidate_id = 0;

if (!empty($currentUserName)) {
    $un_e = mysqli_real_escape_string($con, $currentUserName);

    // Step 1: Confirm this session name matches a real employee record
    $emp_self = mysqli_fetch_assoc(mysqli_query($con,
        "SELECT id, name, department, position_id FROM hr_employees WHERE LOWER(TRIM(name))=LOWER(TRIM('$un_e')) LIMIT 1"
    ));
    if (!$emp_self) {
        // Fallback: partial match for nickname/short-name mismatches
        $emp_self = mysqli_fetch_assoc(mysqli_query($con,
            "SELECT id, name, department, position_id FROM hr_employees WHERE name LIKE '%$un_e%' LIMIT 1"
        ));
    }

    if ($emp_self) {
        $emp_name_e = mysqli_real_escape_string($con, $emp_self['name']);

        // Step 2: Find their checklist run directly by candidate_name
        $run_self = mysqli_fetch_assoc(mysqli_query($con,
            "SELECT candidate_id FROM hr_checklist_runs WHERE LOWER(TRIM(candidate_name))=LOWER(TRIM('$emp_name_e')) LIMIT 1"
        ));

        if ($run_self) {
            $logged_in_candidate_id = intval($run_self['candidate_id']);
        } else {
            // Step 3: No run exists yet for this employee — auto-create one now,
            // sourced from hr_employees (not hr_screenings), so pre-existing
            // employees get a checklist the first time they open this page.
            $emp_dept_name_e = mysqli_real_escape_string($con, trim($emp_self['department'] ?? ''));
            $dept_row = mysqli_fetch_assoc(mysqli_query($con,
                "SELECT id, name FROM hr_departments WHERE TRIM(LOWER(name))=TRIM(LOWER('$emp_dept_name_e')) LIMIT 1"
            ));
            $dept_id   = $dept_row ? intval($dept_row['id']) : 0;
            $dept_name = $dept_row ? $dept_row['name'] : ($emp_self['department'] ?? '');
            $pos_id    = intval($emp_self['position_id'] ?? 0);

            $pos_row = $pos_id > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id LIMIT 1")) : null;
            $pos_name = $pos_row ? $pos_row['title'] : '';

            $new_run_dept_name_e = mysqli_real_escape_string($con, $dept_name);
            $new_run_pos_name_e  = mysqli_real_escape_string($con, $pos_name);

            mysqli_query($con, "INSERT INTO hr_checklist_runs
                (candidate_id, candidate_name, department_id, department_name, position_id, position_name, status, created_by)
                VALUES (" . intval($emp_self['id']) . ", '$emp_name_e', $dept_id, '$new_run_dept_name_e', $pos_id, '$new_run_pos_name_e', 'in_progress', 'system_auto')");
            $new_run_id = mysqli_insert_id($con);

            // Snapshot ALL global checklist headings/items into this new run
            $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
            while ($h = mysqli_fetch_assoc($h_res)) {
                $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . intval($h['id']) . " AND is_active=1 ORDER BY sort_order ASC, id ASC");
                while ($it = mysqli_fetch_assoc($i_res)) {
                    $heading_name_e = mysqli_real_escape_string($con, $h['heading_name']);
                    $item_text_e    = mysqli_real_escape_string($con, $it['item_text']);
                    $desc_e         = mysqli_real_escape_string($con, $it['description'] ?? '');
                    $doc_path_sql   = $it['document_path']    ? "'" . mysqli_real_escape_string($con, $it['document_path']) . "'"    : "NULL";
                    $doc_fname_sql  = $it['document_filename'] ? "'" . mysqli_real_escape_string($con, $it['document_filename']) . "'" : "NULL";
                    $vid_path_sql   = $it['video_path']        ? "'" . mysqli_real_escape_string($con, $it['video_path']) . "'"        : "NULL";
                    $vid_fname_sql  = $it['video_filename']    ? "'" . mysqli_real_escape_string($con, $it['video_filename']) . "'"     : "NULL";
                    $vis_emp_snap   = intval($it['visible_to_employee'] ?? 0);
                    $req_sig_snap   = intval($it['require_signature'] ?? 0);

                    mysqli_query($con, "INSERT INTO hr_checklist_run_items
                        (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature)
                        VALUES ($new_run_id, '$heading_name_e', " . intval($h['sort_order']) . ", 'global', " . intval($it['id']) . ", '$item_text_e', '$desc_e', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, " . intval($it['sort_order']) . ", $vis_emp_snap, $req_sig_snap)");
                }
            }

            $logged_in_candidate_id = intval($emp_self['id']);
        }
    }
}

// =========================================================================
// EXPORT SELECTED ITEMS (CSV / Excel)
// =========================================================================
if (isset($_GET['export']) && in_array($_GET['export'], ['csv', 'excel'])) {
    $export_run_id = intval($_GET['run_id'] ?? 0);
    $selected_ids  = isset($_GET['ids']) ? array_filter(array_map('intval', explode(',', $_GET['ids']))) : [];

    if ($export_run_id <= 0 || empty($selected_ids)) {
        die("No items selected for export.");
    }

    // Authorization: confirm this run belongs to the logged-in employee (or HR)
    $run_owner = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id, candidate_name FROM hr_checklist_runs WHERE id=$export_run_id LIMIT 1"));
    if (!$run_owner || (!$is_hr_user && intval($run_owner['candidate_id']) !== $logged_in_candidate_id)) {
        die("Not authorized to export this checklist.");
    }

    $ids_sql = implode(',', $selected_ids);
    $item_cond = $is_hr_user ? "" : "AND visible_to_employee=1";
    $items_res = mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE run_id=$export_run_id AND id IN ($ids_sql) $item_cond ORDER BY scope_level DESC, heading_sort ASC, item_sort ASC, id ASC");

    $ext  = $_GET['export'] === 'excel' ? 'xls' : 'csv';
    $mime = $_GET['export'] === 'excel' ? 'application/vnd.ms-excel' : 'text/csv';
    header("Content-Type: $mime; charset=utf-8");
    header('Content-Disposition: attachment; filename=onboarding_checklist_' . preg_replace('/[^a-zA-Z0-9]/', '_', $run_owner['candidate_name']) . '_' . date('Y-m-d') . '.' . $ext);

    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));

    fputcsv($out, ['Employee', 'Heading', 'Item', 'Description', 'Signature Required', 'Completed', 'Completed By', 'Completed By Type', 'Completed At', 'Has Signature']);

    while ($ei = mysqli_fetch_assoc($items_res)) {
        fputcsv($out, [
            $run_owner['candidate_name'],
            $ei['heading_name'],
            $ei['item_text'],
            $ei['description'] ?: '',
            $ei['require_signature'] ? 'Yes' : 'No',
            $ei['is_checked'] ? 'Yes' : 'No',
            $ei['checked_by_name'] ?: '',
            $ei['checked_by_type'] ? ucfirst($ei['checked_by_type']) : '',
            $ei['checked_at'] ? date('d M Y, h:i A', strtotime($ei['checked_at'])) : '',
            !empty($ei['signature_data']) ? 'Yes' : 'No'
        ]);
    }
    fclose($out);
    exit;
}

// =========================================================================
// ENSURE COLUMNS EXIST (idempotent — safe to run every load)
// =========================================================================
$col_checks = [
    ["hr_checklist_run_items", "visible_to_employee", "ALTER TABLE hr_checklist_run_items ADD COLUMN visible_to_employee TINYINT(1) DEFAULT 0 AFTER item_sort"],
    ["hr_checklist_run_items", "require_signature",   "ALTER TABLE hr_checklist_run_items ADD COLUMN require_signature TINYINT(1) DEFAULT 0 AFTER visible_to_employee"],
    ["hr_checklist_run_items", "signature_data",      "ALTER TABLE hr_checklist_run_items ADD COLUMN signature_data LONGTEXT DEFAULT NULL AFTER require_signature"],
];
foreach ($col_checks as [$tbl, $col, $sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $sql);
}

// =========================================================================
// AJAX: TOGGLE ITEM (checkbox) OR SAVE SIGNATURE
// =========================================================================
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] == 'toggle_item') {
    header('Content-Type: application/json');
    $item_row_id   = intval($_POST['item_row_id']);
    $checked       = intval($_POST['checked']) == 1 ? 1 : 0;
    $sig_data      = isset($_POST['signature_data']) ? trim($_POST['signature_data']) : '';

    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT run_id, require_signature, visible_to_employee FROM hr_checklist_run_items WHERE id=$item_row_id"));
    if (!$row) { echo json_encode(['success' => false, 'message' => 'Item not found']); exit; }

    // Authorisation: employee can only touch their own run
    $run_chk = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id FROM hr_checklist_runs WHERE id=" . intval($row['run_id'])));
    if (!$is_hr_user && $run_chk && intval($run_chk['candidate_id']) !== $logged_in_candidate_id) {
        echo json_encode(['success' => false, 'message' => 'Not authorized']); exit;
    }

    // Employee cannot check items that aren't visible to them
    if (!$is_hr_user && !$row['visible_to_employee']) {
        echo json_encode(['success' => false, 'message' => 'Not authorized']); exit;
    }

    if ($checked) {
        $by_type = $is_hr_user ? 'hr' : 'employee';
        $by_name = mysqli_real_escape_string($con, $currentUserName);
        $sig_sql = '';
        if ($row['require_signature'] && !empty($sig_data)) {
            $sig_escaped = mysqli_real_escape_string($con, $sig_data);
            $sig_sql = ", signature_data='$sig_escaped'";
        }
        mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=1, checked_by_type='$by_type', checked_by_name='$by_name', checked_at=NOW()$sig_sql WHERE id=$item_row_id");
    } else {
        mysqli_query($con, "UPDATE hr_checklist_run_items SET is_checked=0, checked_by_type=NULL, checked_by_name=NULL, checked_at=NULL, signature_data=NULL WHERE id=$item_row_id");
    }

    // Recompute run progress (only count items visible to employee for employee, all for hr)
    $run_id = intval($row['run_id']);
    if ($is_hr_user) {
        $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id"));
    } else {
        $totals = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id AND visible_to_employee=1"));
    }
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
// PAGE DATA
// =========================================================================
$view_run_id = isset($_GET['run_id']) ? intval($_GET['run_id']) : 0;

if ($is_hr_user) {
    $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs ORDER BY created_at DESC");
} else {
    $runs_res = mysqli_query($con, "SELECT * FROM hr_checklist_runs WHERE candidate_id=$logged_in_candidate_id ORDER BY created_at DESC");
}

$runs_arr = [];
while ($r = mysqli_fetch_assoc($runs_res)) {
    $run_id   = intval($r['id']);
    $item_cond = $is_hr_user ? "" : "AND visible_to_employee=1";

    $tot = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as total, SUM(is_checked) as done FROM hr_checklist_run_items WHERE run_id=$run_id $item_cond"));
    $r['total_items']  = intval($tot['total']);
    $r['done_items']   = intval($tot['done']);
    $r['progress_pct'] = $r['total_items'] > 0 ? round(($r['done_items'] / $r['total_items']) * 100) : 0;

    // Fetch items — HR sees all, employee sees only visible ones
    $items_res = mysqli_query($con, "SELECT * FROM hr_checklist_run_items WHERE run_id=$run_id $item_cond ORDER BY scope_level DESC, heading_sort ASC, item_sort ASC, id ASC");
    $grouped = [];
    while ($it = mysqli_fetch_assoc($items_res)) {
        $key = $it['scope_level'] . '||' . $it['heading_name'];
        if (!isset($grouped[$key])) {
            $grouped[$key] = [
                'heading_name' => $it['heading_name'],
                'scope_level'  => $it['scope_level'],
                'items'        => []
            ];
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
  <title><?php echo isset($_SESSION['ge_cname']) ? htmlspecialchars($_SESSION['ge_cname']) : 'Abra'; ?> | Employee Onboarding Checklist</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">

  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 24px 0 60px; }
    .container-fluid { max-width: 1300px; margin: 0 auto; padding: 0 20px; }

    /* ── PAGE HEADER ── */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 12px;
      box-shadow: 0 4px 20px rgba(30,58,138,.35);
      margin-bottom: 24px;
      display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;
    }
    .page-header h1 { color: #fff; font-weight: 700; margin: 0; font-size: 1.6rem; }

    /* ── ALERTS ── */
    .alert { border-radius: 10px; font-size: 14px; }

    /* ── RUN CARD (accordion header) ── */
    .card-box { background: #fff; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,.08); margin-bottom: 20px; overflow: hidden; }
    .run-card {
      display: flex; align-items: center; gap: 16px; flex-wrap: wrap;
      padding: 18px 24px; cursor: pointer;
      transition: background .15s;
    }
    .run-card:hover { background: #f8faff; }
    .run-card .name  { font-weight: 800; color: #0f2557; font-size: 15px; }
    .run-card .meta  { font-size: 12px; color: #64748b; margin-top: 2px; }
    .progress-wrap   { width: 220px; }
    .progress        { height: 10px; border-radius: 6px; background: #e2e8f0; margin-top: 0; }
    .progress-bar    { background: linear-gradient(90deg, #10b981, #059669); transition: width .35s ease; }

    /* ── STATUS PILLS ── */
    .status-pill { font-size: 10px; font-weight: 800; padding: 4px 12px; border-radius: 20px; text-transform: uppercase; white-space: nowrap; }
    .status-pill.in_progress { background: #fef9c3; color: #713f12; }
    .status-pill.completed   { background: #dcfce7; color: #166534; }

    /* ── SCOPE / ROLE BADGES ── */
    .scope-badge { font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px; text-transform: uppercase; white-space: nowrap; }
    .scope-badge.department { background: #dbeafe; color: #1e40af; }
    .scope-badge.position   { background: #ede9fe; color: #5b21b6; }
    .badge-hr-only { font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px; text-transform: uppercase; background: #fee2e2; color: #991b1b; white-space: nowrap; }

    /* ── HEADING BLOCKS ── */
    .heading-block { border: 1px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden; }
    .heading-block-head {
      background: #f8faff; padding: 14px 18px;
      display: flex; justify-content: space-between; align-items: center; gap: 8px; flex-wrap: wrap;
      border-bottom: 1px solid #e0e7ff;
    }
    .heading-block-head h6 { margin: 0; font-weight: 800; color: #0f2557; font-size: 14px; display: flex; align-items: center; gap: 8px; }
    .heading-block-body { padding: 14px 18px; }

    /* ── CHECKLIST ROW ── */
    .checklist-row {
      display: flex; align-items: flex-start; gap: 14px;
      padding: 16px; background: #f8fafc; border: 1px solid #e2e8f0;
      border-radius: 10px; margin-bottom: 12px; transition: all .2s ease;
      position: relative;
    }
    .checklist-row.is-done        { background: #f0fdf4; border-color: #bbf7d0; }
    .checklist-row.hr-only-row   { background: #fff8f8; border-color: #fecaca; border-style: dashed; }
    .checklist-row.sig-required  { background: #faf5ff; border-color: #d8b4fe; }
    .checklist-row.sig-required.is-done { background: #f5f3ff; border-color: #c4b5fd; }

    .check-box-input { width: 20px; height: 20px; margin-top: 3px; cursor: pointer; flex-shrink: 0; accent-color: #10b981; }

    .item-text       { font-weight: 700; color: #0f2557; font-size: 13.5px; margin-bottom: 4px; }
    .item-text.is-done { text-decoration: line-through; color: #15803d; }
    .item-desc       { font-size: 12px; color: #64748b; margin-bottom: 8px; }

    /* ── ATTACHMENT PILLS ── */
    .attach-pill {
      display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700;
      padding: 4px 10px; border-radius: 14px; margin-right: 6px; text-decoration: none;
    }
    .attach-pill.doc { background: #ede9fe; color: #5b21b6; }
    .attach-pill.vid { background: #fef9c3; color: #713f12; }
    video.preview-video { max-width: 320px; border-radius: 8px; margin-top: 8px; display: block; }

    /* ── CHECKED META ── */
    .checked-meta { font-size: 11px; color: #15803d; margin-top: 8px; font-weight: 600; }

    /* ── SIGNATURE PAD AREA ── */
    .sig-pad-wrap {
      margin-top: 12px; border: 2px dashed #a78bfa; border-radius: 10px;
      background: #fff; padding: 12px; display: inline-block; max-width: 420px; width: 100%;
    }
    .sig-pad-label { font-size: 11px; font-weight: 700; color: #6d28d9; margin-bottom: 8px; display: flex; align-items: center; gap: 6px; }
    canvas.sig-canvas {
      display: block; width: 100%; max-width: 380px; height: 120px;
      border: 1px solid #ddd6fe; border-radius: 8px; background: #faf5ff;
      cursor: crosshair; touch-action: none;
    }
    .sig-pad-actions { margin-top: 8px; display: flex; gap: 8px; flex-wrap: wrap; }
    .btn-sig-clear   { font-size: 11px; font-weight: 700; padding: 5px 14px; border-radius: 8px; border: 1.5px solid #a78bfa; background: #fff; color: #6d28d9; cursor: pointer; }
    .btn-sig-confirm { font-size: 11px; font-weight: 700; padding: 5px 14px; border-radius: 8px; border: none; background: linear-gradient(135deg,#7c3aed,#6d28d9); color: #fff; cursor: pointer; }
    .btn-sig-confirm:disabled { background: #c4b5fd; cursor: not-allowed; }

    /* ── SIGNED DISPLAY (HR view) ── */
    .sig-display { margin-top: 10px; }
    .sig-display img { max-width: 240px; border: 1px solid #ddd6fe; border-radius: 8px; background: #faf5ff; display: block; margin-top: 6px; }
    .badge-signed    { font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px; background: #dcfce7; color: #166534; }
    .badge-awaiting  { font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px; background: #fef9c3; color: #713f12; }

    /* ── SAVE BAR ── */
    .save-bar {
      display: none; margin-top: 20px; padding: 16px 20px;
      background: linear-gradient(135deg, #eff6ff, #dbeafe);
      border: 2px solid #93c5fd; border-radius: 12px;
      align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap;
    }
    .save-bar.visible { display: flex; }
    .save-bar-text h6 { font-weight: 800; color: #1e40af; font-size: 13px; margin: 0; }
    .save-bar-text p  { font-size: 11px; color: #3b82f6; margin: 0; }
    .btn-save-progress {
      padding: 10px 24px; border: none; border-radius: 10px;
      background: linear-gradient(135deg, #1e3a8a, #1e40af);
      color: #fff; font-weight: 800; font-size: 13px; cursor: pointer;
      display: flex; align-items: center; gap: 8px;
    }
    .btn-save-progress:disabled { opacity: .6; cursor: not-allowed; }

    /* ── EMPTY ── */
    .empty-hint { text-align: center; padding: 48px 20px; color: #94a3b8; }
    .empty-hint i { display: block; margin-bottom: 12px; }

    /* ── SIG REQUIRED INDICATOR ON ITEM ── */
    .sig-required-tag {
      display: inline-flex; align-items: center; gap: 4px;
      font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px;
      background: #ede9fe; color: #6d28d9; margin-right: 6px;
    }

    /* ── EMPLOYEE ONLY NOTE ── */
    .employee-visible-tag {
      display: inline-flex; align-items: center; gap: 4px;
      font-size: 10px; font-weight: 800; padding: 3px 10px; border-radius: 20px;
      background: #d1fae5; color: #065f46; margin-right: 6px;
    }
  </style>
</head>
<body>
<div class="container-fluid">

  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible fade show mt-2">
      <i class="fas fa-check-circle mr-2"></i> <?php echo $_SESSION['success_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['success_message']); ?>
  <?php endif; ?>
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible fade show mt-2">
      <i class="fas fa-exclamation-circle mr-2"></i> <?php echo $_SESSION['error_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['error_message']); ?>
  <?php endif; ?>

  <!-- PAGE HEADER -->
  <div class="page-header">
    <div>
      <h1><i class="fas fa-tasks mr-2"></i>Your Onboarding Checklist</h1>
    </div>
  </div>

  <?php if (empty($runs_arr)): ?>
    <div class="card-box">
      <div class="empty-hint">
        <i class="fas fa-clipboard-list fa-3x"></i>
        <h5>You don't have an onboarding checklist assigned yet. Please check back soon.</h5>
      </div>
    </div>

  <?php else: ?>
    <div class="accordion" id="runsAccordion">
      <?php foreach ($runs_arr as $r): ?>
        <?php
          $run_id      = $r['id'];
          $is_open     = ($view_run_id == $run_id || count($runs_arr) == 1);
          $pct         = $r['progress_pct'];
          $done_label  = $r['done_items'] . ' / ' . $r['total_items'] . ' done';
        ?>
        <div class="card-box">

          <!-- RUN HEADER (accordion toggle) -->
          <div class="run-card" data-toggle="collapse" data-target="#collapseRun<?php echo $run_id; ?>" aria-expanded="<?php echo $is_open ? 'true' : 'false'; ?>">
            <div style="flex:1; min-width:180px;">
              <div class="name"><?php echo htmlspecialchars($r['candidate_name']); ?></div>
              <div class="meta">
                <?php echo htmlspecialchars($r['department_name']); ?> &middot;
                <?php echo htmlspecialchars($r['position_name']); ?> &middot;
                Started <?php echo date('d M Y', strtotime($r['created_at'])); ?>
              </div>
            </div>
            <span class="status-pill <?php echo $r['status']; ?>" id="statusPill_<?php echo $run_id; ?>">
              <?php echo $r['status'] == 'completed' ? 'Completed' : 'In Progress'; ?>
            </span>
            <div class="progress-wrap">
              <div class="d-flex justify-content-between mb-1">
                <small id="progressLabel_<?php echo $run_id; ?>" style="font-weight:700;color:#0f2557;"><?php echo $done_label; ?></small>
                <small id="progressPct_<?php echo $run_id; ?>" style="font-weight:700;color:#10b981;"><?php echo $pct; ?>%</small>
              </div>
              <div class="progress">
                <div class="progress-bar" id="progressBarFill_<?php echo $run_id; ?>" style="width:<?php echo $pct; ?>%;"></div>
              </div>
            </div>
            <i class="fas fa-chevron-down" style="color:#94a3b8;transition:transform .2s;" id="chevron_<?php echo $run_id; ?>"></i>
          </div>

          <!-- RUN BODY -->
          <div id="collapseRun<?php echo $run_id; ?>" class="collapse <?php echo $is_open ? 'show' : ''; ?>" data-parent="#runsAccordion">
            <div style="padding:20px;border-top:1px solid #e2e8f0;">

              <?php if (empty($r['grouped'])): ?>
                <div class="empty-hint" style="padding:24px;">
                  <i class="fas fa-list-ul fa-2x mb-2"></i>
                  <p><?php echo $is_hr_user
                    ? 'No checklist items found for this run. Add items in the Checklist Configuration screen.'
                    : 'No checklist items have been assigned to you yet.'; ?></p>
                </div>

              <?php else: ?>
                <div style="background:#eff6ff;border:1px solid #93c5fd;border-radius:10px;padding:12px 16px;margin-bottom:16px;display:flex;align-items:center;gap:10px;">
                  <i class="fas fa-info-circle" style="color:#1e40af;font-size:16px;"></i>
                  <span style="font-size:12.5px;font-weight:600;color:#1e40af;">
                    Tip: Check the small box next to any item to select it, then use the <strong>Export</strong> button below to download the selected items as CSV or Excel.
                  </span>
                </div>
                <?php foreach ($r['grouped'] as $group): ?>
                  <div class="heading-block">
                    <div class="heading-block-head">
                      <h6>
                        <i class="fas fa-layer-group" style="color:<?php echo $group['scope_level']=='department' ? '#1e3a8a' : '#5b21b6'; ?>;"></i>
                        <?php echo htmlspecialchars($group['heading_name']); ?>
                      </h6>
                      <span class="scope-badge <?php echo $group['scope_level']; ?>">
                        <?php echo $group['scope_level'] == 'department' ? 'Dept-Level' : 'Position-Level'; ?>
                      </span>
                    </div>

                    <div class="heading-block-body">
                      <?php foreach ($group['items'] as $item): ?>
                        <?php
                          $item_id      = $item['id'];
                          $is_checked   = $item['is_checked'];
                          $req_sig      = $item['require_signature'];
                          $vis_emp      = $item['visible_to_employee'];
                          $has_sig      = !empty($item['signature_data']);
                          $row_classes  = 'checklist-row';
                          if ($is_checked)                    $row_classes .= ' is-done';
                          if (!$vis_emp && $is_hr_user)       $row_classes .= ' hr-only-row';
                          if ($req_sig)                       $row_classes .= ' sig-required';
                        ?>
                        <div class="<?php echo $row_classes; ?>" id="row_<?php echo $item_id; ?>">

                          <input type="checkbox" class="export-select-checkbox" data-run-id="<?php echo $run_id; ?>" data-item-id="<?php echo $item_id; ?>" style="width:18px;height:18px;margin-top:3px;cursor:pointer;flex-shrink:0;" title="Select for export" onchange="updateExportBar(<?php echo $run_id; ?>)">

                          <?php if ($req_sig): ?>
                            <!-- Signature item: no checkbox, signature pad drives completion -->
                            <div style="flex-shrink:0;width:24px;text-align:center;padding-top:2px;">
                              <?php if ($is_checked): ?>
                                <i class="fas fa-signature" style="color:#10b981;font-size:18px;" title="Signed"></i>
                              <?php else: ?>
                                <i class="fas fa-signature" style="color:#a78bfa;font-size:18px;" title="Signature required"></i>
                              <?php endif; ?>
                            </div>
                          <?php else: ?>
                            <input type="checkbox"
                              class="check-box-input item-checkbox"
                              data-run-id="<?php echo $run_id; ?>"
                              data-row-id="<?php echo $item_id; ?>"
                              data-requires-sig="0"
                              <?php echo $is_checked ? 'checked' : ''; ?>
                              <?php echo (!$is_hr_user && !$vis_emp) ? 'disabled' : ''; ?>>
                          <?php endif; ?>

                          <div style="flex:1;min-width:0;">

                            <!-- Item text + tags row -->
                            <div style="display:flex;align-items:flex-start;gap:6px;flex-wrap:wrap;margin-bottom:4px;">
                              <span class="item-text <?php echo $is_checked ? 'is-done' : ''; ?>"><?php echo htmlspecialchars($item['item_text']); ?></span>
                              <?php if ($req_sig): ?>
                                <span class="sig-required-tag"><i class="fas fa-pen-nib"></i> Signature Required</span>
                              <?php endif; ?>
                              <?php if ($is_hr_user): ?>
                                <?php if ($vis_emp): ?>
                                  <span class="employee-visible-tag"><i class="fas fa-eye"></i> Visible to Employee</span>
                                <?php else: ?>
                                  <span class="badge-hr-only"><i class="fas fa-lock"></i> HR Only</span>
                                <?php endif; ?>
                              <?php endif; ?>
                            </div>

                            <?php if (!empty($item['description'])): ?>
                              <div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div>
                            <?php endif; ?>

                            <!-- Attachments -->
                            <div style="margin-bottom:6px;">
                              <?php if (!empty($item['document_path'])): ?>
                                <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="attach-pill doc">
                                  <i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?>
                                </a>
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

                            <!-- ── SIGNATURE PAD (employee, not yet signed) ── -->
                            <?php if ($req_sig && !$is_checked && !$is_hr_user && $vis_emp): ?>
                              <div class="sig-pad-wrap" id="sigWrap_<?php echo $item_id; ?>">
                                <div class="sig-pad-label">
                                  <i class="fas fa-pen-nib"></i>
                                  Sign below to confirm you have completed this item
                                </div>
                                <canvas class="sig-canvas" id="sigCanvas_<?php echo $item_id; ?>" width="760" height="240"></canvas>
                                
                                <div style="margin: 12px 14px 16px 14px; background: #f8fafc; border: 1px solid #cbd5e1; padding: 12px 16px; border-radius: 8px; display: flex; align-items: flex-start; gap: 12px;">
                                    <input type="checkbox" id="sigAccept_<?php echo $item_id; ?>" style="width:20px; height:20px; margin-top:2px; cursor:pointer; flex-shrink:0;" onchange="checkSigState(<?php echo $item_id; ?>)">
                                    <label for="sigAccept_<?php echo $item_id; ?>" style="font-size: 13px; color: #334155; margin: 0; font-weight: 500; cursor:pointer; line-height: 1.5;">
                                      I accept full responsibility for the item(s) confirmed above. I acknowledge that I am solely responsible for its proper use and care, and that any damage, loss, or misuse may result in corresponding deductions or disciplinary action.
                                    </label>
                                </div>

                                <div class="sig-pad-actions">
                                  <button type="button" class="btn-sig-clear" onclick="clearSig(<?php echo $item_id; ?>)"><i class="fas fa-eraser mr-1"></i>Clear</button>
                                  <button type="button" class="btn-sig-confirm" id="sigConfirmBtn_<?php echo $item_id; ?>" disabled
                                    onclick="confirmSig(<?php echo $run_id; ?>, <?php echo $item_id; ?>)">
                                    <i class="fas fa-check mr-1"></i>Confirm Signature
                                  </button>
                                </div>
                              </div>
                            <?php endif; ?>

                            <!-- ── SIGNED DISPLAY (HR view or already done) ── -->
                            <?php if ($req_sig && $is_hr_user): ?>
                              <div class="sig-display">
                                <?php if ($is_checked && $has_sig): ?>
                                  <span class="badge-signed"><i class="fas fa-check-circle mr-1"></i>Signed</span>
                                  <img src="<?php echo htmlspecialchars($item['signature_data']); ?>" alt="Employee Signature" />
                                <?php elseif ($is_checked && !$has_sig): ?>
                                  <span class="badge-signed"><i class="fas fa-check-circle mr-1"></i>Marked Done (no signature image)</span>
                                <?php else: ?>
                                  <span class="badge-awaiting"><i class="fas fa-clock mr-1"></i>Awaiting Signature</span>
                                <?php endif; ?>
                              </div>
                            <?php endif; ?>

                            <!-- ── EMPLOYEE: already signed display ── -->
                            <?php if ($req_sig && !$is_hr_user && $is_checked): ?>
                              <div class="checked-meta" style="margin-bottom:6px;">
                                <i class="fas fa-signature"></i> Signed &amp; confirmed
                                <?php if (!empty($item['checked_at'])): ?>
                                  on <?php echo date('d M Y, h:i A', strtotime($item['checked_at'])); ?>
                                <?php endif; ?>
                              </div>
                              <?php if ($has_sig): ?>
                                <div class="sig-display" style="margin-top:0;">
                                  <img src="<?php echo htmlspecialchars($item['signature_data']); ?>" alt="Your Signature" />
                                </div>
                              <?php endif; ?>
                            <?php endif; ?>

                            <!-- ── NORMAL CHECKED META ── -->
                            <?php if (!$req_sig && $is_checked): ?>
                              <div class="checked-meta">
                                <i class="fas fa-check-circle"></i>
                                Marked done by <?php echo htmlspecialchars($item['checked_by_name']); ?>
                                (<?php echo $item['checked_by_type'] == 'hr' ? 'HR' : 'Employee'; ?>)
                                <?php if (!empty($item['checked_at'])): ?>
                                  on <?php echo date('d M Y, h:i A', strtotime($item['checked_at'])); ?>
                                <?php endif; ?>
                              </div>
                            <?php endif; ?>

                          </div><!-- /flex:1 -->
                        </div><!-- /checklist-row -->
                      <?php endforeach; ?>
                    </div><!-- /heading-block-body -->
                  </div><!-- /heading-block -->
                <?php endforeach; ?>

                <!-- SAVE BAR -->
                <div class="save-bar" id="saveBar_<?php echo $run_id; ?>">
                  <div class="save-bar-text">
                    <h6><i class="fas fa-info-circle mr-1"></i> You have unsaved changes</h6>
                    <p>Click Save Progress to record your selections.</p>
                  </div>
                  <button type="button" class="btn-save-progress" id="saveBtn_<?php echo $run_id; ?>"
                    onclick="saveProgress(<?php echo $run_id; ?>)">
                    <i class="fas fa-save"></i> Save Progress
                  </button>
                </div>

                <!-- EXPORT BAR -->
                <div class="save-bar" id="exportBar_<?php echo $run_id; ?>" style="background:linear-gradient(135deg,#f0fdf4,#dcfce7);border-color:#86efac;">
                  <div class="save-bar-text">
                    <h6 style="color:#065f46;"><i class="fas fa-check-square mr-1"></i> <span id="exportCount_<?php echo $run_id; ?>">0</span> item(s) selected</h6>
                    <p style="color:#059669;">Choose a format to export the selected items.</p>
                  </div>
                  <div style="display:flex;gap:8px;">
                    <button type="button" class="btn-save-progress" style="background:linear-gradient(135deg,#10b981,#059669);" onclick="exportSelected(<?php echo $run_id; ?>, 'csv')">
                      <i class="fas fa-file-csv"></i> Export CSV
                    </button>
                    <button type="button" class="btn-save-progress" style="background:linear-gradient(135deg,#059669,#047857);" onclick="exportSelected(<?php echo $run_id; ?>, 'excel')">
                      <i class="fas fa-file-excel"></i> Export Excel
                    </button>
                  </div>
                </div>

              <?php endif; ?>
            </div>
          </div><!-- /collapse -->
        </div><!-- /card-box -->
      <?php endforeach; ?>
    </div><!-- /accordion -->
  <?php endif; ?>

</div><!-- /container -->

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
// ============================================================
// CHEVRON ROTATION ON ACCORDION
// ============================================================
document.querySelectorAll('[data-toggle="collapse"]').forEach(function(el) {
  var target = el.getAttribute('data-target');
  var chevron = el.querySelector('i.fa-chevron-down');
  var collapseEl = document.querySelector(target);
  if (!collapseEl || !chevron) return;
  if (collapseEl.classList.contains('show')) chevron.style.transform = 'rotate(180deg)';
  $(collapseEl).on('show.bs.collapse', function() { chevron.style.transform = 'rotate(180deg)'; });
  $(collapseEl).on('hide.bs.collapse', function() { chevron.style.transform = 'rotate(0deg)'; });
});

// ============================================================
// QUICK-SELECT JUMP
// ============================================================
function jumpToRun(runId) {
  if (!runId) return;
  document.querySelectorAll('.collapse.show').forEach(function(el) { $(el).collapse('hide'); });
  var target = document.getElementById('collapseRun' + runId);
  if (target) {
    $(target).collapse('show');
    setTimeout(function() { target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }, 300);
  }
}

// ============================================================
// PENDING CHANGES TRACKER
// ============================================================
var pendingChanges = {}; // { runId: { rowId: { checked, signature_data? } } }

function markPending(runId, rowId, checked, sigData) {
  if (!pendingChanges[runId]) pendingChanges[runId] = {};
  pendingChanges[runId][rowId] = { checked: checked };
  if (sigData !== undefined) pendingChanges[runId][rowId].signature_data = sigData;
  var saveBar = document.getElementById('saveBar_' + runId);
  if (saveBar) saveBar.classList.add('visible');
}

// ============================================================
// CHECKBOX ITEMS
// ============================================================
document.querySelectorAll('.item-checkbox').forEach(function(cb) {
  cb.addEventListener('change', function() {
    var runId  = this.getAttribute('data-run-id');
    var rowId  = this.getAttribute('data-row-id');
    var checked = this.checked ? 1 : 0;
    var row    = document.getElementById('row_' + rowId);
    var textEl = row ? row.querySelector('.item-text') : null;
    if (row)   row.classList.toggle('is-done', checked == 1);
    if (textEl) textEl.classList.toggle('is-done', checked == 1);
    markPending(runId, rowId, checked);
  });
});

// ============================================================
// SIGNATURE PAD
// ============================================================
var sigState = {}; // { canvasId: { drawing, lastX, lastY, isEmpty } }

function initSigCanvas(canvasId) {
  var canvas = document.getElementById(canvasId);
  if (!canvas || sigState[canvasId]) return;
  sigState[canvasId] = { drawing: false, isEmpty: true };
  var ctx = canvas.getContext('2d');
  ctx.strokeStyle = '#1e3a8a';
  ctx.lineWidth   = 2.2;
  ctx.lineCap     = 'round';
  ctx.lineJoin    = 'round';

  function getPos(e) {
    var rect = canvas.getBoundingClientRect();
    var scaleX = canvas.width  / rect.width;
    var scaleY = canvas.height / rect.height;
    var src = e.touches ? e.touches[0] : e;
    return { x: (src.clientX - rect.left) * scaleX, y: (src.clientY - rect.top) * scaleY };
  }

  function start(e) {
    e.preventDefault();
    sigState[canvasId].drawing = true;
    var p = getPos(e);
    ctx.beginPath(); ctx.moveTo(p.x, p.y);
    sigState[canvasId].lastX = p.x; sigState[canvasId].lastY = p.y;
  }
  function draw(e) {
    e.preventDefault();
    if (!sigState[canvasId].drawing) return;
    var p = getPos(e);
    ctx.lineTo(p.x, p.y); ctx.stroke();
    sigState[canvasId].lastX = p.x; sigState[canvasId].lastY = p.y;
    sigState[canvasId].isEmpty = false;
    var itemId = canvasId.replace('sigCanvas_', '');
    checkSigState(itemId);
  }
  function stop(e) { sigState[canvasId].drawing = false; }

  canvas.addEventListener('mousedown',  start);
  canvas.addEventListener('mousemove',  draw);
  canvas.addEventListener('mouseup',    stop);
  canvas.addEventListener('mouseleave', stop);
  canvas.addEventListener('touchstart', start, { passive: false });
  canvas.addEventListener('touchmove',  draw,  { passive: false });
  canvas.addEventListener('touchend',   stop);
}

// Init all canvases on page load
document.querySelectorAll('canvas.sig-canvas').forEach(function(c) { initSigCanvas(c.id); });
// Also init when accordion opens (in case canvas was hidden)
document.querySelectorAll('.collapse').forEach(function(el) {
  $(el).on('shown.bs.collapse', function() {
    this.querySelectorAll('canvas.sig-canvas').forEach(function(c) { initSigCanvas(c.id); });
  });
});

function clearSig(itemId) {
  var canvas = document.getElementById('sigCanvas_' + itemId);
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  sigState['sigCanvas_' + itemId] = { drawing: false, isEmpty: true };
  
  var cb = document.getElementById('sigAccept_' + itemId);
  if (cb) cb.checked = false;
  checkSigState(itemId);
}

function checkSigState(itemId) {
  var canvasId = 'sigCanvas_' + itemId;
  var btn = document.getElementById('sigConfirmBtn_' + itemId);
  var cb = document.getElementById('sigAccept_' + itemId);
  var state = sigState[canvasId];
  if (btn && cb && state) {
    btn.disabled = (state.isEmpty || !cb.checked);
  }
}

function confirmSig(runId, itemId) {
  var canvas = document.getElementById('sigCanvas_' + itemId);
  if (!canvas) return;
  var state = sigState['sigCanvas_' + itemId];
  var cb = document.getElementById('sigAccept_' + itemId);
  
  if (!state || state.isEmpty) { alert('Please sign before confirming.'); return; }
  if (cb && !cb.checked) { alert('Please check the responsibility acceptance box before confirming.'); return; }

  var dataURL = canvas.toDataURL('image/png');
  // Visual feedback on the row
  var row = document.getElementById('row_' + itemId);
  if (row) {
    row.classList.add('is-done');
    var textEl = row.querySelector('.item-text');
    if (textEl) textEl.classList.add('is-done');
    var sigWrap = document.getElementById('sigWrap_' + itemId);
    if (sigWrap) {
      sigWrap.innerHTML = '<div class="checked-meta" style="margin-top:0;"><i class="fas fa-signature mr-1"></i> Signature captured — click <strong>Save Progress</strong> to submit.</div>';
    }
  }
  markPending(runId, itemId, 1, dataURL);
}

// ============================================================
// SAVE PROGRESS
// ============================================================
function saveProgress(runId) {
  var changes = pendingChanges[runId];
  if (!changes || Object.keys(changes).length === 0) return;

  var btn = document.getElementById('saveBtn_' + runId);
  var oldHtml = btn ? btn.innerHTML : '';
  if (btn) { btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...'; btn.disabled = true; }

  var rowIds = Object.keys(changes);
  var saved  = 0, lastDone = 0, lastTotal = 0;

  rowIds.forEach(function(rowId) {
    var c = changes[rowId];
    var postData = { ajax_action: 'toggle_item', item_row_id: rowId, checked: c.checked };
    if (c.signature_data) postData.signature_data = c.signature_data;

    $.post('', postData, function(resp) {
      var data = typeof resp === 'string' ? JSON.parse(resp) : resp;
      saved++;
      if (data.success) { lastDone = data.done; lastTotal = data.total; }

      if (saved === rowIds.length) {
        var pct = lastTotal > 0 ? Math.round((lastDone / lastTotal) * 100) : 0;

        var label = document.getElementById('progressLabel_' + runId);
        var pctEl = document.getElementById('progressPct_' + runId);
        var bar   = document.getElementById('progressBarFill_' + runId);
        var pill  = document.getElementById('statusPill_' + runId);
        if (label) label.textContent = lastDone + ' / ' + lastTotal + ' done';
        if (pctEl)  pctEl.textContent = pct + '%';
        if (bar)    bar.style.width   = pct + '%';
        if (pill) {
          if (lastTotal > 0 && lastDone === lastTotal) {
            pill.className   = 'status-pill completed';
            pill.textContent = 'Completed';
          } else {
            pill.className   = 'status-pill in_progress';
            pill.textContent = 'In Progress';
          }
        }
        pendingChanges[runId] = {};
        if (btn) { btn.innerHTML = '<i class="fas fa-check"></i> Saved!'; btn.style.background = 'linear-gradient(135deg,#10b981,#059669)'; }
        setTimeout(function() { location.reload(); }, 900);
      }
    }).fail(function() {
      saved++;
      if (saved === rowIds.length && btn) {
        btn.innerHTML = oldHtml; btn.disabled = false;
        alert('Save failed. Please try again.');
      }
    });
  });
}
// ============================================================
// EXPORT SELECTED ITEMS
// ============================================================
function updateExportBar(runId) {
  var checkboxes = document.querySelectorAll('.export-select-checkbox[data-run-id="' + runId + '"]:checked');
  var bar = document.getElementById('exportBar_' + runId);
  var countEl = document.getElementById('exportCount_' + runId);
  if (countEl) countEl.textContent = checkboxes.length;
  if (bar) bar.classList.toggle('visible', checkboxes.length > 0);
  if (bar) bar.style.display = checkboxes.length > 0 ? 'flex' : 'none';
}

function exportSelected(runId, type) {
  var checkboxes = document.querySelectorAll('.export-select-checkbox[data-run-id="' + runId + '"]:checked');
  if (checkboxes.length === 0) { alert('Please select at least one item to export.'); return; }
  var ids = Array.from(checkboxes).map(function(cb) { return cb.getAttribute('data-item-id'); });
  var url = window.location.pathname + '?export=' + type + '&run_id=' + runId + '&ids=' + ids.join(',');
  window.location.href = url;
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
