<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

// =========================================================================
// HR ONBOARDING CHECKLIST CONFIGURATION (Department + Position scoped)
// =========================================================================

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

$current_page = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// ENSURE TABLES EXIST
// =========================================================================

// Headings: position_id = 0 means "Department-level" (applies to all positions in dept).
// position_id > 0 means "Position-level" (applies only to that specific position).
$check_headings = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_headings'");
if (mysqli_num_rows($check_headings) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_headings (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL,
        position_id INT(11) DEFAULT 0,
        heading_name VARCHAR(255) NOT NULL,
        sort_order INT(11) DEFAULT 0,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

$check_items = mysqli_query($con, "SHOW TABLES LIKE 'hr_checklist_items'");
if (mysqli_num_rows($check_items) == 0) {
    mysqli_query($con, "CREATE TABLE hr_checklist_items (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        heading_id INT(11) NOT NULL,
        department_id INT(11) NOT NULL,
        position_id INT(11) DEFAULT 0,
        item_text VARCHAR(500) NOT NULL,
        description TEXT DEFAULT NULL,
        document_path VARCHAR(500) DEFAULT NULL,
        document_filename VARCHAR(255) DEFAULT NULL,
        video_path VARCHAR(500) DEFAULT NULL,
        video_filename VARCHAR(255) DEFAULT NULL,
        sort_order INT(11) DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        visible_to_employee TINYINT(1) DEFAULT 0,
        require_signature TINYINT(1) DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

// Add columns if table already existed before this update
$col_checks_cfg = [
    ["hr_checklist_items", "visible_to_employee", "ALTER TABLE hr_checklist_items ADD COLUMN visible_to_employee TINYINT(1) DEFAULT 0 AFTER is_active"],
    ["hr_checklist_items", "require_signature",   "ALTER TABLE hr_checklist_items ADD COLUMN require_signature TINYINT(1) DEFAULT 0 AFTER visible_to_employee"],
];
foreach ($col_checks_cfg as [$tbl, $col, $sql]) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM `$tbl` LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) mysqli_query($con, $sql);
}

// Upload directory for checklist documents/videos
$upload_dir = 'uploads/hr_checklist/';
if (!is_dir($upload_dir)) {
    @mkdir($upload_dir, 0755, true);
}

// =========================================================================
// EXPORT SELECTED CHECKLIST ITEMS (CSV / Excel) — template structure only
// =========================================================================
if (isset($_GET['export']) && in_array($_GET['export'], ['csv', 'excel'])) {
    $selected_ids = isset($_GET['ids']) ? array_filter(array_map('intval', explode(',', $_GET['ids']))) : [];
    if (empty($selected_ids)) {
        die("No items selected for export.");
    }

    $ids_sql = implode(',', $selected_ids);
    $items_res = mysqli_query($con, "
        SELECT i.*, h.heading_name
        FROM hr_checklist_items i
        JOIN hr_checklist_headings h ON h.id = i.heading_id
        WHERE i.id IN ($ids_sql)
        ORDER BY h.sort_order ASC, i.sort_order ASC
    ");

    $ext  = $_GET['export'] === 'excel' ? 'xls' : 'csv';
    $mime = $_GET['export'] === 'excel' ? 'application/vnd.ms-excel' : 'text/csv';
    header("Content-Type: $mime; charset=utf-8");
    header('Content-Disposition: attachment; filename=checklist_template_export_' . date('Y-m-d_His') . '.' . $ext);

    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));

    fputcsv($out, ['Heading', 'Item Text', 'Description', 'Document Attachment', 'Video Attachment', 'Visible to Employee', 'Signature Required', 'Active']);

    while ($it = mysqli_fetch_assoc($items_res)) {
        fputcsv($out, [
            $it['heading_name'],
            $it['item_text'],
            $it['description'] ?: '',
            $it['document_filename'] ?: '',
            $it['video_filename'] ?: '',
            $it['visible_to_employee'] ? 'Yes' : 'No',
            $it['require_signature'] ? 'Yes' : 'No',
            $it['is_active'] ? 'Yes' : 'No'
        ]);
    }
    fclose($out);
    exit;
}

// =========================================================================
// FORM SUBMISSIONS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST') {

    // --- ADD HEADING ---
    if (isset($_POST['action']) && $_POST['action'] == 'add_heading') {
        $heading  = mysqli_real_escape_string($con, trim($_POST['heading_name']));

        if (!empty($heading)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_checklist_headings WHERE department_id=0 AND position_id=0"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            mysqli_query($con, "INSERT INTO hr_checklist_headings (department_id, position_id, heading_name, sort_order, created_by) VALUES (0, 0, '$heading', $next_sort, '$currentUserName')");
            $_SESSION['success_message'] = "Heading added successfully.";
        } else {
            $_SESSION['error_message'] = "Please enter a Heading name.";
        }
        header("Location: $current_page");
        exit;
    }

    // --- EDIT HEADING ---
    if (isset($_POST['action']) && $_POST['action'] == 'edit_heading') {
        $id      = intval($_POST['id']);
        $heading = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        if ($id > 0 && !empty($heading)) {
            $old_name_res = mysqli_fetch_assoc(mysqli_query($con, "SELECT heading_name FROM hr_checklist_headings WHERE id=$id"));
            if ($old_name_res) {
                $old_name = mysqli_real_escape_string($con, $old_name_res['heading_name']);
                mysqli_query($con, "UPDATE hr_checklist_run_items SET heading_name='$heading' WHERE heading_name='$old_name'");
            }
            mysqli_query($con, "UPDATE hr_checklist_headings SET heading_name='$heading' WHERE id=$id");
            $_SESSION['success_message'] = "Heading updated successfully.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- DELETE HEADING (cascade items) ---
    if (isset($_POST['action']) && $_POST['action'] == 'delete_heading') {
        $id = intval($_POST['id']);
        // Clean up uploaded files belonging to items under this heading first
        $items_res = mysqli_query($con, "SELECT id, document_path, video_path FROM hr_checklist_items WHERE heading_id=$id");
        while ($it = mysqli_fetch_assoc($items_res)) {
            if (!empty($it['document_path']) && file_exists($it['document_path'])) @unlink($it['document_path']);
            if (!empty($it['video_path']) && file_exists($it['video_path'])) @unlink($it['video_path']);
            
            // Cascade delete to existing runs
            $it_id = $it['id'];
            mysqli_query($con, "DELETE FROM hr_checklist_run_items WHERE item_id=$it_id");
        }
        mysqli_query($con, "DELETE FROM hr_checklist_items WHERE heading_id=$id");
        mysqli_query($con, "DELETE FROM hr_checklist_headings WHERE id=$id");
        $_SESSION['success_message'] = "Heading and its items deleted successfully.";
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // Auto-sync missing items into existing runs (fixes items that failed to cascade)
    mysqli_query($con, "
        INSERT INTO hr_checklist_run_items (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature)
        SELECT 
            r.id, h.heading_name, h.sort_order, 'global', i.id, i.item_text, i.description, i.document_path, i.document_filename, i.video_path, i.video_filename, i.sort_order, i.visible_to_employee, i.require_signature
        FROM hr_checklist_items i
        JOIN hr_checklist_headings h ON i.heading_id = h.id
        JOIN hr_checklist_runs r
        LEFT JOIN hr_checklist_run_items ri ON ri.run_id = r.id AND ri.item_id = i.id
        WHERE ri.id IS NULL
    ");

    // --- ADD ITEM (with optional document / video upload) ---
    if (isset($_POST['action']) && $_POST['action'] == 'add_item') {
        $heading_id  = intval($_POST['heading_id']);
        $item_text   = mysqli_real_escape_string($con, trim($_POST['item_text']));
        $description = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        $doc_path = ''; $doc_fname = '';
        $vid_path = ''; $vid_fname = '';

        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] === UPLOAD_ERR_OK) {
            $df = $_FILES['document_file'];
            $dext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
            $allowed_docs = ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt'];
            if (in_array($dext, $allowed_docs)) {
                $dpath = $upload_dir . 'doc_' . time() . '_' . rand(1000,9999) . '.' . $dext;
                if (move_uploaded_file($df['tmp_name'], $dpath)) {
                    $doc_path = $dpath;
                    $doc_fname = $df['name'];
                }
            }
        }

        if (isset($_FILES['video_file']) && $_FILES['video_file']['error'] === UPLOAD_ERR_OK) {
            $vf = $_FILES['video_file'];
            $vext = strtolower(pathinfo($vf['name'], PATHINFO_EXTENSION));
            $allowed_vids = ['mp4','mov','avi','wmv','webm','mkv'];
            if (in_array($vext, $allowed_vids)) {
                $vpath = $upload_dir . 'vid_' . time() . '_' . rand(1000,9999) . '.' . $vext;
                if (move_uploaded_file($vf['tmp_name'], $vpath)) {
                    $vid_path = $vpath;
                    $vid_fname = $vf['name'];
                }
            }
        }

        if ($heading_id > 0 && !empty($item_text)) {
            $max_sort = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_checklist_items WHERE heading_id=$heading_id"));
            $next_sort = ($max_sort && $max_sort['m'] !== null) ? intval($max_sort['m']) + 1 : 0;
            $doc_path_sql  = $doc_path ? "'" . mysqli_real_escape_string($con, $doc_path) . "'" : "NULL";
            $doc_fname_sql = $doc_fname ? "'" . mysqli_real_escape_string($con, $doc_fname) . "'" : "NULL";
            $vid_path_sql  = $vid_path ? "'" . mysqli_real_escape_string($con, $vid_path) . "'" : "NULL";
            $vid_fname_sql = $vid_fname ? "'" . mysqli_real_escape_string($con, $vid_fname) . "'" : "NULL";

            $vis_emp_val = isset($_POST['visible_to_employee']) ? 1 : 0;
            $req_sig_val = (isset($_POST['require_signature']) && $vis_emp_val) ? 1 : 0;
            mysqli_query($con, "INSERT INTO hr_checklist_items (heading_id, department_id, position_id, item_text, description, document_path, document_filename, video_path, video_filename, sort_order, visible_to_employee, require_signature) VALUES ($heading_id, 0, 0, '$item_text', '$description', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, $next_sort, $vis_emp_val, $req_sig_val)");
            
            $new_item_id = mysqli_insert_id($con);
            
            // Cascade to existing runs so employees instantly see the new item
            $run_q = mysqli_query($con, "SELECT r.id, h.heading_name, h.sort_order as h_sort FROM hr_checklist_runs r JOIN hr_checklist_headings h ON h.id=$heading_id");
            if ($run_q) {
                while ($rq = mysqli_fetch_assoc($run_q)) {
                    $r_id = $rq['id'];
                    $hname = mysqli_real_escape_string($con, $rq['heading_name']);
                    $hsort = intval($rq['h_sort']);
                    mysqli_query($con, "INSERT INTO hr_checklist_run_items (run_id, heading_name, heading_sort, scope_level, item_id, item_text, description, document_path, document_filename, video_path, video_filename, item_sort, visible_to_employee, require_signature) VALUES ($r_id, '$hname', $hsort, 'global', $new_item_id, '" . mysqli_real_escape_string($con, $item_text) . "', '" . mysqli_real_escape_string($con, $description) . "', $doc_path_sql, $doc_fname_sql, $vid_path_sql, $vid_fname_sql, $next_sort, $vis_emp_val, $req_sig_val)");
                }
            }

            $_SESSION['success_message'] = "Checklist item added successfully.";
        } else {
            $_SESSION['error_message'] = "Please enter item text.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- EDIT ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'edit_item') {
        $id          = intval($_POST['id']);
        $item_text   = mysqli_real_escape_string($con, trim($_POST['item_text']));
        $description = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        $set_extra = '';

        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] === UPLOAD_ERR_OK) {
            // Remove old document if present
            $old = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path FROM hr_checklist_items WHERE id=$id"));
            if ($old && !empty($old['document_path']) && file_exists($old['document_path'])) @unlink($old['document_path']);

            $df = $_FILES['document_file'];
            $dext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
            $allowed_docs = ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt'];
            if (in_array($dext, $allowed_docs)) {
                $dpath = $upload_dir . 'doc_' . time() . '_' . rand(1000,9999) . '.' . $dext;
                if (move_uploaded_file($df['tmp_name'], $dpath)) {
                    $set_extra .= ", document_path='" . mysqli_real_escape_string($con, $dpath) . "', document_filename='" . mysqli_real_escape_string($con, $df['name']) . "'";
                }
            }
        }

        if (isset($_FILES['video_file']) && $_FILES['video_file']['error'] === UPLOAD_ERR_OK) {
            $old = mysqli_fetch_assoc(mysqli_query($con, "SELECT video_path FROM hr_checklist_items WHERE id=$id"));
            if ($old && !empty($old['video_path']) && file_exists($old['video_path'])) @unlink($old['video_path']);

            $vf = $_FILES['video_file'];
            $vext = strtolower(pathinfo($vf['name'], PATHINFO_EXTENSION));
            $allowed_vids = ['mp4','mov','avi','wmv','webm','mkv'];
            if (in_array($vext, $allowed_vids)) {
                $vpath = $upload_dir . 'vid_' . time() . '_' . rand(1000,9999) . '.' . $vext;
                if (move_uploaded_file($vf['tmp_name'], $vpath)) {
                    $set_extra .= ", video_path='" . mysqli_real_escape_string($con, $vpath) . "', video_filename='" . mysqli_real_escape_string($con, $vf['name']) . "'";
                }
            }
        }

        $vis_emp_val = isset($_POST['visible_to_employee']) ? 1 : 0;
        $req_sig_val = (isset($_POST['require_signature']) && $vis_emp_val) ? 1 : 0;
        if ($id > 0 && !empty($item_text)) {
            mysqli_query($con, "UPDATE hr_checklist_items SET item_text='$item_text', description='$description', visible_to_employee=$vis_emp_val, require_signature=$req_sig_val$set_extra WHERE id=$id");
            
            // Cascade changes to existing run items so employees instantly see visibility/text updates
            mysqli_query($con, "UPDATE hr_checklist_run_items SET item_text='$item_text', description='$description', visible_to_employee=$vis_emp_val, require_signature=$req_sig_val$set_extra WHERE item_id=$id");
            
            $_SESSION['success_message'] = "Checklist item updated successfully.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- REMOVE DOCUMENT / VIDEO FROM ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'remove_attachment') {
        $id   = intval($_POST['id']);
        $type = $_POST['attachment_type'] == 'video' ? 'video' : 'document';
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path, video_path FROM hr_checklist_items WHERE id=$id"));
        if ($row) {
            $path_col = $type . '_path';
            $fname_col = $type . '_filename';
            if (!empty($row[$path_col]) && file_exists($row[$path_col])) @unlink($row[$path_col]);
            mysqli_query($con, "UPDATE hr_checklist_items SET $path_col=NULL, $fname_col=NULL WHERE id=$id");
        }
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }

    // --- DELETE ITEM ---
    if (isset($_POST['action']) && $_POST['action'] == 'delete_item') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path, video_path FROM hr_checklist_items WHERE id=$id"));
        if ($row) {
            if (!empty($row['document_path']) && file_exists($row['document_path'])) @unlink($row['document_path']);
            if (!empty($row['video_path']) && file_exists($row['video_path'])) @unlink($row['video_path']);
        }
        mysqli_query($con, "DELETE FROM hr_checklist_items WHERE id=$id");
        mysqli_query($con, "DELETE FROM hr_checklist_run_items WHERE item_id=$id");
        $_SESSION['success_message'] = "Checklist item deleted successfully.";
        header("Location: " . $_SERVER['HTTP_REFERER']);
        exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================

// Fetch all global headings and items
function fetch_global_headings($con) {
    $out = [];
    $h_res = mysqli_query($con, "SELECT * FROM hr_checklist_headings ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($h_res)) {
        $h['items'] = [];
        $i_res = mysqli_query($con, "SELECT * FROM hr_checklist_items WHERE heading_id=" . $h['id'] . " ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($i_res)) $h['items'][] = $i;
        $out[] = $h;
    }
    return $out;
}

$global_headings = fetch_global_headings($con);

?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?> | Onboarding Checklist Configuration</title>
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
      margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }

    .action-bar {
      background: white; padding: 20px; border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px;
      display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;
    }
    .btn-action {
      border: none; padding: 10px 20px; border-radius: 8px; font-weight: 600;
      color: white; background: #10b981; cursor: pointer;
    }
    .card-box { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px; }

    .scope-section-title {
      font-weight: 700; color: #1e3a8a; font-size: 1.05rem; margin-bottom: 14px;
      display: flex; align-items: center; gap: 8px; padding-bottom: 10px; border-bottom: 2px solid #eef2ff;
    }
    .scope-badge { font-size: 11px; font-weight: 800; padding: 3px 10px; border-radius: 20px; text-transform: uppercase; }
    .scope-badge.dept { background: #dbeafe; color: #1e40af; }
    .scope-badge.pos { background: #ede9fe; color: #5b21b6; }

    .heading-block {
      border: 1px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden;
    }
    .heading-block-head {
      background: #f8faff; padding: 14px 18px; display: flex; justify-content: space-between; align-items: center;
      border-bottom: 1px solid #e0e7ff;
    }
    .heading-block-head h6 { margin: 0; font-weight: 800; color: #0f2557; font-size: 14px; }
    .heading-block-body { padding: 14px 18px; }

    .checklist-item-row {
      display: flex; justify-content: space-between; align-items: flex-start; gap: 12px;
      padding: 12px 14px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 10px;
    }
    .item-text { font-weight: 700; color: #0f2557; font-size: 13.5px; margin-bottom: 4px; }
    .item-desc { font-size: 12px; color: #64748b; margin-bottom: 6px; }
    .attach-pill {
      display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700;
      padding: 4px 10px; border-radius: 14px; margin-right: 6px; text-decoration: none;
    }
    .attach-pill.doc { background: #ede9fe; color: #5b21b6; }
    .attach-pill.vid { background: #fef9c3; color: #713f12; }
    .attach-pill.none { background: #f1f5f9; color: #94a3b8; }

    .empty-hint { text-align: center; padding: 40px; color: #94a3b8; }

    /* Navigation Tabs */
    .nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; }
    .nav-btn {
        padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
        font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
        display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
    }
    .nav-btn:hover { text-decoration: none; color: #1e3a8a; }
    .nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }
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
        <h1><i class="fas fa-clipboard-check mr-2"></i> Onboarding Checklist Configuration</h1>
        <?php
        $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
        $dashboard_url_header = $is_admin ? 'index.php' : 'raise-a-ticket.php';
        ?>
        <a href="<?php echo $dashboard_url_header; ?>" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
    </div>

    <!-- NAVIGATION TABS -->
    <div class="nav-tabs-container">
        <a href="hr-employee-onboarding-pending-list.php" class="nav-btn">
            <i class="fas fa-user-plus"></i> Onboarding
        </a>
        <a href="hr-checklist-employee.php" class="nav-btn active">
            <i class="fas fa-tasks"></i> Internal Checklist
        </a>
        <a href="hr-checklist.php" class="nav-btn">
            <i class="fas fa-clipboard-check"></i> Employee Checklist
        </a>
    </div>

    <div class="action-bar">



        <div>
            <!-- Filters removed for Global Checklist -->
        </div>
        <div>
            <button class="btn-action" data-toggle="modal" data-target="#addHeadingModal"><i class="fas fa-plus"></i> Add Checklist Heading</button>
        </div>
    </div>

    <div class="card-box">
        <div class="scope-section-title">
            <span class="scope-badge dept"><i class="fas fa-globe mr-1"></i> Global Checklist</span>
            Applies universally to ALL new employees during onboarding.
        </div>
        
        <?php if (empty($global_headings)): ?>
            <div class="empty-hint">
                <i class="fas fa-list-ul fa-3x mb-3"></i>
                <h5>No checklists found.</h5>
                <p>Click "Add Checklist Heading" above to create your first global checklist.</p>
            </div>
        <?php else: ?>
            <?php foreach ($global_headings as $h): ?>
                <div class="heading-block">
                    <div class="heading-block-head">
                        <h6><i class="fas fa-layer-group mr-2" style="color:#1e3a8a;"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6>
                        <div>
                            <button class="btn btn-sm btn-warning" onclick='editHeading(<?php echo json_encode($h); ?>)'><i class="fas fa-edit"></i></button>
                            <button class="btn btn-sm btn-info" onclick="openAddItemModal(<?php echo $h['id']; ?>, '<?php echo htmlspecialchars(addslashes($h['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this heading and ALL its items?');">
                                <input type="hidden" name="action" value="delete_heading">
                                <input type="hidden" name="id" value="<?php echo $h['id']; ?>">
                                <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                            </form>
                        </div>
                    </div>
                    <div class="heading-block-body">
                        <?php if (empty($h['items'])): ?>
                            <p class="text-muted small mb-0">No items under this heading yet.</p>
                        <?php else: foreach ($h['items'] as $item): ?>
                            <div class="checklist-item-row">
                                <input type="checkbox" class="export-select-checkbox" data-item-id="<?php echo $item['id']; ?>" style="width:18px;height:18px;margin-top:3px;margin-right:10px;cursor:pointer;flex-shrink:0;" title="Select for export" onchange="updateExportBar()">
                                <div style="flex:1;">
                                    <div class="item-text"><?php echo htmlspecialchars($item['item_text']); ?></div>
                                    <?php if (!empty($item['description'])): ?>
                                        <div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div>
                                    <?php endif; ?>
                                    <div>
                                        <?php if (!empty($item['document_path'])): ?>
                                            <span class="attach-pill doc"><i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?></span>
                                        <?php endif; ?>
                                        <?php if (!empty($item['video_path'])): ?>
                                            <span class="attach-pill vid"><i class="fas fa-video"></i> <?php echo htmlspecialchars($item['video_filename']); ?></span>
                                        <?php endif; ?>
                                        <?php if (empty($item['document_path']) && empty($item['video_path'])): ?>
                                            <span class="attach-pill none"><i class="fas fa-ban"></i> No attachment</span>
                                        <?php endif; ?>
                                    </div>
                                </div>
                                <div style="white-space:nowrap;">
                                    <button class="btn btn-sm btn-warning" onclick='editItem(<?php echo json_encode($item); ?>)'><i class="fas fa-edit"></i></button>
                                    <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?');">
                                        <input type="hidden" name="action" value="delete_item">
                                        <input type="hidden" name="id" value="<?php echo $item['id']; ?>">
                                        <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                                    </form>
                                </div>
                            </div>
                        <?php endforeach; endif; ?>
                    </div>
                </div>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>

    <div id="exportBar" style="display:none;margin-top:20px;padding:16px 20px;background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;border-radius:12px;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <div>
            <h6 style="color:#065f46;font-weight:800;margin:0;font-size:13px;"><i class="fas fa-check-square mr-1"></i> <span id="exportCount">0</span> item(s) selected</h6>
            <p style="color:#059669;font-size:11px;margin:0;">Choose a format to export the selected checklist items.</p>
        </div>
        <div style="display:flex;gap:8px;">
            <button type="button" class="btn btn-success" onclick="exportSelected('csv')"><i class="fas fa-file-csv"></i> Export CSV</button>
            <button type="button" class="btn btn-success" onclick="exportSelected('excel')" style="background:#047857;border-color:#047857;"><i class="fas fa-file-excel"></i> Export Excel</button>
        </div>
    </div>

</div>

<!-- Add Heading Modal -->
<div class="modal fade" id="addHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="POST">
                <input type="hidden" name="action" value="add_heading">
                <div class="modal-header">
                    <h4 class="modal-title">Add New Heading</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <!-- Scope inputs removed for global checklist -->
                    <div class="form-group">
                        <label>Heading Name (e.g. "Induction", "Documentation")</label>
                        <input type="text" name="heading_name" class="form-control" required>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-primary">Save Heading</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Edit Heading Modal -->
<div class="modal fade" id="editHeadingModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form method="POST">
                <input type="hidden" name="action" value="edit_heading">
                <input type="hidden" name="id" id="edit_heading_id">
                <div class="modal-header">
                    <h4 class="modal-title">Edit Heading</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Heading Name</label>
                        <input type="text" name="heading_name" id="edit_heading_name" class="form-control" required>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-warning">Update Heading</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Add Item Modal -->
<div class="modal fade" id="addItemModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <form method="POST" enctype="multipart/form-data">
                <input type="hidden" name="action" value="add_item">
                <input type="hidden" name="heading_id" id="add_item_heading_id">
                <div class="modal-header">
                    <h4 class="modal-title">Add Item to "<span id="add_item_heading_label"></span>"</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Item Text (e.g. "About the Company")</label>
                        <input type="text" name="item_text" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>Description (optional)</label>
                        <textarea name="description" class="form-control" rows="2"></textarea>
                    </div>
                    <div class="form-group">
                        <label>Document Upload (PPT, PDF, DOC, XLS, etc. — optional)</label>
                        <input type="file" name="document_file" class="form-control-file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt">
                    </div>
                    <div class="form-group">
                        <label>Video Upload (optional)</label>
                        <input type="file" name="video_file" class="form-control-file" accept=".mp4,.mov,.avi,.wmv,.webm,.mkv">
                    </div>
                    <hr>
                    <div class="form-group mb-1">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="visible_to_employee" id="add_visible_to_employee" onchange="document.getElementById('add_require_sig_wrap').style.opacity=this.checked?'1':'0.4'; if(!this.checked) document.getElementById('add_require_signature').checked=false;">
                            <label class="custom-control-label font-weight-bold" for="add_visible_to_employee">
                                <i class="fas fa-eye mr-1 text-success"></i> Visible to Employee
                            </label>
                        </div>
                        <small class="text-muted">Employee will see this item in their onboarding checklist.</small>
                    </div>
                    <div class="form-group mb-0" id="add_require_sig_wrap" style="opacity:0.4;">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="require_signature" id="add_require_signature">
                            <label class="custom-control-label font-weight-bold" for="add_require_signature">
                                <i class="fas fa-pen-nib mr-1 text-purple" style="color:#6d28d9;"></i> Require Digital Signature
                            </label>
                        </div>
                        <small class="text-muted">Employee must draw a signature to mark this item complete. Only available when Visible to Employee is on.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-primary">Save Item</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Edit Item Modal -->
<div class="modal fade" id="editItemModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <form method="POST" enctype="multipart/form-data">
                <input type="hidden" name="action" value="edit_item">
                <input type="hidden" name="id" id="edit_item_id">
                <div class="modal-header">
                    <h4 class="modal-title">Edit Item</h4>
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>Item Text</label>
                        <input type="text" name="item_text" id="edit_item_text" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>Description (optional)</label>
                        <textarea name="description" id="edit_item_description" class="form-control" rows="2"></textarea>
                    </div>
                    <div class="form-group">
                        <label>Current Document</label>
                        <div id="edit_item_current_doc" class="mb-2"></div>
                        <label>Replace Document (optional)</label>
                        <input type="file" name="document_file" class="form-control-file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt">
                    </div>
                    <div class="form-group">
                        <label>Current Video</label>
                        <div id="edit_item_current_vid" class="mb-2"></div>
                        <label>Replace Video (optional)</label>
                        <input type="file" name="video_file" class="form-control-file" accept=".mp4,.mov,.avi,.wmv,.webm,.mkv">
                    </div>
                    <hr>
                    <div class="form-group mb-1">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="visible_to_employee" id="edit_visible_to_employee" onchange="document.getElementById('edit_require_sig_wrap').style.opacity=this.checked?'1':'0.4'; if(!this.checked) document.getElementById('edit_require_signature').checked=false;">
                            <label class="custom-control-label font-weight-bold" for="edit_visible_to_employee">
                                <i class="fas fa-eye mr-1 text-success"></i> Visible to Employee
                            </label>
                        </div>
                        <small class="text-muted">Employee will see this item in their onboarding checklist.</small>
                    </div>
                    <div class="form-group mb-0" id="edit_require_sig_wrap" style="opacity:0.4;">
                        <div class="custom-control custom-switch">
                            <input type="checkbox" class="custom-control-input" name="require_signature" id="edit_require_signature">
                            <label class="custom-control-label font-weight-bold" for="edit_require_signature">
                                <i class="fas fa-pen-nib mr-1" style="color:#6d28d9;"></i> Require Digital Signature
                            </label>
                        </div>
                        <small class="text-muted">Employee must draw a signature to mark this item complete. Only available when Visible to Employee is on.</small>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                    <button type="submit" class="btn btn-info">Update Item</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Standalone remove-attachment forms (submitted via JS confirm) -->
<form method="POST" id="removeAttachForm" style="display:none;">
    <input type="hidden" name="action" value="remove_attachment">
    <input type="hidden" name="id" id="removeAttachId">
    <input type="hidden" name="attachment_type" id="removeAttachType">
</form>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function editHeading(h) {
    document.getElementById('edit_heading_id').value = h.id;
    document.getElementById('edit_heading_name').value = h.heading_name;
    $('#editHeadingModal').modal('show');
}

function openAddItemModal(headingId, headingName) {
    document.getElementById('add_item_heading_id').value = headingId;
    document.getElementById('add_item_heading_label').textContent = headingName;
    $('#addItemModal').modal('show');
}

function editItem(item) {
    document.getElementById('edit_item_id').value = item.id;
    document.getElementById('edit_item_text').value = item.item_text;
    document.getElementById('edit_item_description').value = item.description || '';

    var docBox = document.getElementById('edit_item_current_doc');
    if (item.document_path) {
        docBox.innerHTML = '<a href="' + item.document_path + '" target="_blank" class="badge badge-info" style="font-size:12px;padding:6px 10px;"><i class="fas fa-file-alt mr-1"></i>' + item.document_filename + '</a> ' +
            '<button type="button" class="btn btn-sm btn-outline-danger ml-1" onclick="removeAttachment(' + item.id + ', \'document\')"><i class="fas fa-times"></i> Remove</button>';
    } else {
        docBox.innerHTML = '<span class="text-muted small">No document attached.</span>';
    }

    var vidBox = document.getElementById('edit_item_current_vid');
    if (item.video_path) {
        vidBox.innerHTML = '<a href="' + item.video_path + '" target="_blank" class="badge badge-warning" style="font-size:12px;padding:6px 10px;"><i class="fas fa-video mr-1"></i>' + item.video_filename + '</a> ' +
            '<button type="button" class="btn btn-sm btn-outline-danger ml-1" onclick="removeAttachment(' + item.id + ', \'video\')"><i class="fas fa-times"></i> Remove</button>';
    } else {
        vidBox.innerHTML = '<span class="text-muted small">No video attached.</span>';
    }

    // Restore visible_to_employee + require_signature toggles
    var visChk = document.getElementById('edit_visible_to_employee');
    var sigChk = document.getElementById('edit_require_signature');
    var sigWrap = document.getElementById('edit_require_sig_wrap');
    visChk.checked = item.visible_to_employee == 1;
    sigChk.checked = item.require_signature == 1;
    sigWrap.style.opacity = visChk.checked ? '1' : '0.4';

    $('#editItemModal').modal('show');
}

function removeAttachment(id, type) {
    if (!confirm('Remove this ' + type + '?')) return;
    document.getElementById('removeAttachId').value = id;
    document.getElementById('removeAttachType').value = type;
    document.getElementById('removeAttachForm').submit();
}
function updateExportBar() {
    var checkboxes = document.querySelectorAll('.export-select-checkbox:checked');
    var bar = document.getElementById('exportBar');
    var countEl = document.getElementById('exportCount');
    if (countEl) countEl.textContent = checkboxes.length;
    if (bar) bar.style.display = checkboxes.length > 0 ? 'flex' : 'none';
}

function exportSelected(type) {
    var checkboxes = document.querySelectorAll('.export-select-checkbox:checked');
    if (checkboxes.length === 0) { alert('Please select at least one item to export.'); return; }
    var ids = Array.from(checkboxes).map(function(cb) { return cb.getAttribute('data-item-id'); });
    window.location.href = window.location.pathname + '?export=' + type + '&ids=' + ids.join(',');
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
