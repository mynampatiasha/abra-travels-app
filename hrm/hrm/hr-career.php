<?php 
// ============================================================================
// CRM - HR CAREER MODULE (Job Postings + Applications Review)
// ============================================================================
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);
date_default_timezone_set('Asia/Kolkata');

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

require_once('database.php');
require_once('library.php');
require_once('funciones.php');

isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// ── ROLE CHECK ──
$is_super_admin = (stripos($currentUserName, 'Abishek') !== false);
$is_keerti      = (stripos($currentUserName, 'Keerti') !== false || stripos($currentUserName, 'Keerthi') !== false);

// Check employee position for MD/CEO/HR roles
$user_position = '';
$user_dept_role = '';
if(!empty($currentUserName) && !empty($dbConn)) {
    $name_safe_role = mysqli_real_escape_string($dbConn, $currentUserName);
    $role_check = mysqli_query($dbConn, "SELECT position, department FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe_role')) AND status = 'active' LIMIT 1");
    if($role_check && mysqli_num_rows($role_check) > 0) {
        $role_row = mysqli_fetch_assoc($role_check);
        $user_position   = strtolower(trim($role_row['position'] ?? ''));
        $user_dept_role  = strtolower(trim($role_row['department'] ?? ''));
    }
}

$is_managing_director = (
    stripos($user_position, 'managing director') !== false ||
    stripos($user_position, 'md') !== false ||
    stripos($user_position, 'ceo') !== false ||
    stripos($user_position, 'director') !== false
);

$is_hr_role = (
    stripos($user_position, 'hr') !== false ||
    stripos($user_dept_role, 'hr') !== false ||
    stripos($user_position, 'human resource') !== false ||
    stripos($user_dept_role, 'human resource') !== false
);

// Any logged-in user can access this page (HR, MD, Admins)
// Restrict destructive actions to admins/HR only
$is_admin = ($is_super_admin || $is_keerti || $is_managing_director || $is_hr_role || !empty($currentUserName));

// Only management can delete applications
$can_delete_apps = ($is_super_admin || $is_keerti || $is_managing_director);

// Pass flags to JS
$js_can_delete = $can_delete_apps ? 'true' : 'false';
$js_current_user = htmlspecialchars(addslashes($currentUserName));

// ── ENSURE email_sent COLUMN EXISTS ──
if($dbConn) @mysqli_query($dbConn, "ALTER TABLE hr_career_applications ADD COLUMN IF NOT EXISTS email_sent TINYINT(1) DEFAULT 0");

// ── ENSURE TABLES EXIST ──
if($dbConn) mysqli_query($dbConn, "
    CREATE TABLE IF NOT EXISTS hr_job_postings (
        id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(200) NOT NULL,
        department VARCHAR(100) NOT NULL,
        location VARCHAR(100) NOT NULL,
        job_type ENUM('Full Time','Part Time','Contract','Internship') DEFAULT 'Full Time',
        experience VARCHAR(100),
        description TEXT,
        requirements TEXT,
        deadline DATE,
        status ENUM('active','closed','draft') DEFAULT 'active',
        posted_by VARCHAR(100),
        posted_date DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

if($dbConn) mysqli_query($dbConn, "
    CREATE TABLE IF NOT EXISTS hr_career_applications (
        id INT AUTO_INCREMENT PRIMARY KEY,
        job_id INT DEFAULT 0,
        job_title VARCHAR(200),
        department VARCHAR(100),
        applicant_name VARCHAR(150) NOT NULL,
        email VARCHAR(150) NOT NULL,
        phone VARCHAR(20),
        city VARCHAR(100),
        experience VARCHAR(100),
        cover_letter TEXT,
        resume_path VARCHAR(300),
        status ENUM('new','reviewed','shortlisted','interview','selected','rejected','on_hold') DEFAULT 'new',
        hr_notes TEXT,
        email_sent TINYINT(1) DEFAULT 0,
        applied_date DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        updated_by VARCHAR(100)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// ============================================================================
// AJAX ACTIONS
// ============================================================================
if(isset($_POST['ajax_action'])) {
    header('Content-Type: application/json');
    $action = $_POST['ajax_action'];

    // ── POST JOB ──
    if($action == 'post_job' && $is_admin) {
        $title      = mysqli_real_escape_string($dbConn, trim($_POST['title']));
        $dept       = mysqli_real_escape_string($dbConn, trim($_POST['department']));
        $location   = mysqli_real_escape_string($dbConn, trim($_POST['location']));
        $type       = mysqli_real_escape_string($dbConn, trim($_POST['job_type']));
        $exp        = mysqli_real_escape_string($dbConn, trim($_POST['experience']));
        $desc       = mysqli_real_escape_string($dbConn, trim($_POST['description']));
        $req        = mysqli_real_escape_string($dbConn, trim($_POST['requirements']));
        $deadline   = !empty($_POST['deadline']) ? mysqli_real_escape_string($dbConn, $_POST['deadline']) : 'NULL';
        $deadline_val = $deadline == 'NULL' ? 'NULL' : "'$deadline'";
        $status     = mysqli_real_escape_string($dbConn, trim($_POST['status']));
        $posted_by  = mysqli_real_escape_string($dbConn, $currentUserName);

        if(empty($title) || empty($dept) || empty($location)) {
            echo json_encode(['success'=>false, 'message'=>'Title, Department, and Location are required.']);
            exit;
        }

        $r = mysqli_query($dbConn, "INSERT INTO hr_job_postings (title,department,location,job_type,experience,description,requirements,deadline,status,posted_by) VALUES ('$title','$dept','$location','$type','$exp','$desc','$req',$deadline_val,'$status','$posted_by')");
        echo json_encode(['success'=>(bool)$r, 'message' => $r ? 'Job posted successfully!' : mysqli_error($dbConn)]);
        exit;
    }

    // ── UPDATE JOB ──
    if($action == 'update_job' && $is_admin) {
        $id       = intval($_POST['id']);
        $title    = mysqli_real_escape_string($dbConn, trim($_POST['title']));
        $dept     = mysqli_real_escape_string($dbConn, trim($_POST['department']));
        $location = mysqli_real_escape_string($dbConn, trim($_POST['location']));
        $type     = mysqli_real_escape_string($dbConn, trim($_POST['job_type']));
        $exp      = mysqli_real_escape_string($dbConn, trim($_POST['experience']));
        $desc     = mysqli_real_escape_string($dbConn, trim($_POST['description']));
        $req      = mysqli_real_escape_string($dbConn, trim($_POST['requirements']));
        $deadline = !empty($_POST['deadline']) ? "'".mysqli_real_escape_string($dbConn,$_POST['deadline'])."'" : 'NULL';
        $status   = mysqli_real_escape_string($dbConn, trim($_POST['status']));

        $r = mysqli_query($dbConn, "UPDATE hr_job_postings SET title='$title',department='$dept',location='$location',job_type='$type',experience='$exp',description='$desc',requirements='$req',deadline=$deadline,status='$status' WHERE id=$id");
        echo json_encode(['success'=>(bool)$r, 'message' => $r ? 'Job updated successfully!' : mysqli_error($dbConn)]);
        exit;
    }

    // ── DELETE JOB ──
    if($action == 'delete_job' && $is_admin) {
        $id = intval($_POST['id']);
        $r = mysqli_query($dbConn, "DELETE FROM hr_job_postings WHERE id=$id");
        echo json_encode(['success'=>(bool)$r]);
        exit;
    }

    // ── DELETE APPLICATION ──
    if($action == 'delete_application' && $is_admin) {
        $id = intval($_POST['id']);
        $r = mysqli_query($dbConn, "DELETE FROM hr_career_applications WHERE id=$id");
        echo json_encode(['success'=>(bool)$r]);
        exit;
    }

    // ── SEND EMAIL TO APPLICANT ──
    if($action == 'send_applicant_email') {
        $to      = mysqli_real_escape_string($dbConn, trim($_POST['to_email']));
        $subject = strip_tags(trim($_POST['subject']));
        $body    = strip_tags(trim($_POST['body']));
        $from    = 'HR Team <hr-admin@abra-logistic.com>';
        if(empty($to) || empty($subject) || empty($body)) {
            echo json_encode(['success'=>false,'message'=>'To, Subject and Message are required.']);
            exit;
        }
        $headers  = "From: $from
";
        $headers .= "Reply-To: hr-admin@abra-logistic.com
";
        $headers .= "MIME-Version: 1.0
";
        $headers .= "Content-Type: text/plain; charset=UTF-8
";
        $sent = @mail($to, $subject, $body, $headers);
        if($sent) {
            // Mark email_sent on the application
            $app_id_email = intval($_POST['app_id'] ?? 0);
            if($app_id_email > 0) mysqli_query($dbConn, "UPDATE hr_career_applications SET email_sent=1 WHERE id=$app_id_email");
        }
        echo json_encode(['success'=>$sent, 'message'=> $sent ? 'Email sent successfully!' : 'Failed to send email. Please try again.']);
        exit;
    }

    // ── BULK DELETE APPLICATIONS ──
    if($action == 'bulk_delete_applications' && $is_admin) {
        $raw_ids = $_POST['ids'] ?? '';
        $ids = array_filter(array_map('intval', explode(',', $raw_ids)));
        if(empty($ids)) { echo json_encode(['success'=>false,'message'=>'No IDs provided']); exit; }
        $id_list = implode(',', $ids);
        $r = mysqli_query($dbConn, "DELETE FROM hr_career_applications WHERE id IN ($id_list)");
        echo json_encode(['success'=>(bool)$r, 'deleted'=>count($ids)]);
        exit;
    }

    // ── UPDATE APPLICATION STATUS ──
    if($action == 'update_app_status' && $is_admin) {
        $id     = intval($_POST['id']);
        $status = mysqli_real_escape_string($dbConn, trim($_POST['status']));
        $notes  = mysqli_real_escape_string($dbConn, trim($_POST['notes']));
        $by     = mysqli_real_escape_string($dbConn, $currentUserName);
        $r = mysqli_query($dbConn, "UPDATE hr_career_applications SET status='$status',hr_notes='$notes',updated_by='$by' WHERE id=$id");
        echo json_encode(['success'=>(bool)$r]);
        exit;
    }

    echo json_encode(['success'=>false,'message'=>'Invalid action or permission denied.','debug'=>['action'=>$action,'is_admin'=>$is_admin,'user'=>$currentUserName,'position'=>$user_position,'dept'=>$user_dept_role]]);
    exit;
}

// ── STATS (safe - no fatal if table missing) ──
function cr_count($dbConn, $sql) {
    if(!$dbConn) return 0;
    $r = mysqli_query($dbConn, $sql);
    if(!$r) return 0;
    $row = mysqli_fetch_assoc($r);
    return intval($row['c'] ?? 0);
}
$stat_jobs_active = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_job_postings WHERE status='active'");
$stat_jobs_total  = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_job_postings");
$stat_apps_total  = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications");
$stat_apps_new    = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications WHERE status='new'");
$stat_apps_short  = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications WHERE status='shortlisted'");
$stat_apps_sel    = cr_count($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications WHERE status='selected'");

// ── FETCH JOBS & APPLICATIONS ──
$jobs_result = $dbConn ? mysqli_query($dbConn, "SELECT * FROM hr_job_postings ORDER BY posted_date DESC") : false;
$apps_result = $dbConn ? mysqli_query($dbConn, "SELECT * FROM hr_career_applications ORDER BY applied_date DESC LIMIT 500") : false;
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Career Management | <?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'CRM'; ?></title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/css/select2.min.css" />
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
  
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    .container-fluid { max-width: 1600px; margin: 0 auto; padding: 0 20px; }

    /* ── PAGE HEADER ── */
    .page-header { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30,58,138,0.3); margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }
    .page-header h1 { color: white; font-weight: 700; margin: 0; font-size: 1.8rem; }
    .page-header .header-info { color: rgba(255,255,255,0.8); font-size: 0.85rem; margin-top: 4px; }

    /* ── TABS ── */
    .cr-tab-bar { display: flex; gap: 4px; background: white; padding: 6px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,.08); margin-bottom: 20px; overflow-x: auto; }
    .cr-tab-btn { padding: 12px 28px; border: none; border-radius: 9px; background: transparent; font-weight: 700; font-size: 14px; color: #64748b; cursor: pointer; transition: all .2s; white-space: nowrap; display: flex; align-items: center; gap: 8px; }
    .cr-tab-btn:hover { background: #f1f5f9; color: #1e3a8a; }
    .cr-tab-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; box-shadow: 0 4px 14px rgba(30,58,138,.3); }
    .cr-tab-content { display: none; }
    .cr-tab-content.active { display: block; }

    /* ── STATS ── */
    .stats-row { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: nowrap; overflow-x: auto; }
    .stat-card { background: white; border-radius: 10px; padding: 16px 14px; display: flex; align-items: center; gap: 12px; border-left: 4px solid; box-shadow: 0 2px 10px rgba(0,0,0,.08); flex: 1; min-width: 0; transition: all .3s; }
    .stat-card:hover { transform: translateY(-3px); box-shadow: 0 6px 20px rgba(0,0,0,.12); }
    .stat-card.blue   { border-left-color: #1e40af; }
    .stat-card.green  { border-left-color: #10b981; }
    .stat-card.amber  { border-left-color: #f59e0b; }
    .stat-card.red    { border-left-color: #ef4444; }
    .stat-card.purple { border-left-color: #8b5cf6; }
    .stat-card.teal   { border-left-color: #06b6d4; }
    .stat-icon { width: 46px; height: 46px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 20px; color: white; flex-shrink: 0; }
    .stat-icon.blue   { background: linear-gradient(135deg, #1e3a8a, #1e40af); }
    .stat-icon.green  { background: linear-gradient(135deg, #10b981, #059669); }
    .stat-icon.amber  { background: linear-gradient(135deg, #f59e0b, #d97706); }
    .stat-icon.red    { background: linear-gradient(135deg, #ef4444, #dc2626); }
    .stat-icon.purple { background: linear-gradient(135deg, #8b5cf6, #7c3aed); }
    .stat-icon.teal   { background: linear-gradient(135deg, #06b6d4, #0284c7); }
    .stat-content h3  { margin: 0; font-size: 24px; font-weight: 800; color: #0f172a; }
    .stat-content p   { margin: 3px 0 0 0; font-size: 10px; font-weight: 600; color: #64748b; text-transform: uppercase; }

    /* ── BUTTONS ── */
    .btn-hdr { padding: 11px 22px; border-radius: 9px; font-weight: 700; cursor: pointer; border: none; display: inline-flex; align-items: center; gap: 8px; transition: all .3s; text-decoration: none; font-size: 14px; color: white; }
    .btn-primary-c { background: linear-gradient(135deg,#1e3a8a,#1e40af); box-shadow: 0 4px 14px rgba(30,58,138,.3); }
    .btn-primary-c:hover { transform: translateY(-2px); box-shadow: 0 8px 24px rgba(30,58,138,.4); color: white; }
    .btn-success-c { background: linear-gradient(135deg,#10b981,#059669); box-shadow: 0 4px 14px rgba(16,185,129,.3); }
    .btn-success-c:hover { transform: translateY(-2px); color: white; }
    .btn-danger-c  { background: linear-gradient(135deg,#ef4444,#dc2626); box-shadow: 0 4px 14px rgba(239,68,68,.3); }
    .btn-danger-c:hover  { transform: translateY(-2px); color: white; }
    .btn-sm-edit   { background: #e0e7ff; color: #3730a3; border: none; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; transition: all .2s; }
    .btn-sm-edit:hover { background: #3730a3; color: white; }
    .btn-sm-del    { background: #fee2e2; color: #dc2626; border: none; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; transition: all .2s; }
    .btn-sm-del:hover  { background: #dc2626; color: white; }
    .btn-sm-view   { background: #d1fae5; color: #065f46; border: none; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; transition: all .2s; }
    .btn-sm-view:hover { background: #065f46; color: white; }

    /* ── CARDS / FORM PANEL ── */
    .panel { background: white; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,.08); margin-bottom: 20px; overflow: hidden; }
    .panel-head { background: linear-gradient(135deg,#1e3a8a,#1e40af); padding: 16px 22px; display: flex; align-items: center; justify-content: space-between; }
    .panel-head h5 { color: white; font-weight: 700; margin: 0; font-size: 15px; }
    .panel-body { padding: 22px; }

    /* ── FORM ── */
    .form-row-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; }
    .form-row-3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 16px; margin-bottom: 16px; }
    .fg { display: flex; flex-direction: column; gap: 5px; }
    .fg label { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .5px; color: #64748b; }
    .fg label span { color: #ef4444; margin-left: 2px; }
    .fi, .fs, .ft {
        border: 2px solid #e2e8f0; border-radius: 8px;
        padding: 10px 14px; font-size: 14px; font-family: 'Poppins', sans-serif;
        color: #1e293b; background: white; transition: border .2s; width: 100%; outline: none;
    }
    .fi:focus, .fs:focus, .ft:focus { border-color: #1e40af; box-shadow: 0 0 0 3px rgba(30,64,175,.08); }
    .ft { min-height: 100px; resize: vertical; }
    .fs { appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%2364748b' stroke-width='2' fill='none' stroke-linecap='round'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 14px center; padding-right: 36px; }

    /* ── TABLE ── */
    .table-container { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,.08); margin-bottom: 20px; overflow-x: auto; }
    .table-hdr-actions { display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; flex-wrap: wrap; gap: 10px; }
    .table-hdr-actions h5 { color: #1e3a8a; font-weight: 700; margin: 0; font-size: 15px; }
    table.dataTable { width: 100% !important; border-collapse: separate !important; border-spacing: 0 !important; }
    table.dataTable thead th { background: linear-gradient(135deg,#1e3a8a,#1e40af) !important; color: white !important; font-weight: 700 !important; padding: 13px 10px !important; border: 1px solid #1e3a8a !important; font-size: 12px !important; }
    table.dataTable tbody td { border: 1px solid #e2e8f0 !important; padding: 11px 10px !important; vertical-align: middle !important; font-weight: 500 !important; color: #1e293b !important; font-size: 12px !important; }
    table.dataTable tbody tr { background: white !important; transition: background .2s; }
    table.dataTable tbody tr:hover { background: #f1f5f9 !important; }

    /* ── BADGES ── */
    .badge { padding: 5px 12px; border-radius: 20px; font-weight: 700; font-size: 11px; text-transform: uppercase; }
    .badge-active      { background: #d1fae5; color: #065f46; }
    .badge-closed      { background: #fee2e2; color: #991b1b; }
    .badge-draft       { background: #f1f5f9; color: #64748b; }
    .badge-new         { background: #dbeafe; color: #1e40af; }
    .badge-reviewed    { background: #fef3c7; color: #92400e; }
    .badge-shortlisted { background: #d1fae5; color: #065f46; }
    .badge-interview   { background: #ede9fe; color: #5b21b6; }
    .badge-selected    { background: #ecfdf5; color: #047857; border: 1px solid #6ee7b7; }
    .badge-rejected    { background: #fee2e2; color: #991b1b; }
    .badge-on_hold     { background: #fff7ed; color: #c2410c; }
    .badge-ft { background: #dbeafe; color: #1e40af; }
    .badge-pt { background: #fef3c7; color: #92400e; }
    .badge-ct { background: #d1fae5; color: #065f46; }
    .badge-in { background: #ede9fe; color: #5b21b6; }

    /* ── MODAL ── */
    .modal-content { border-radius: 14px; border: none; box-shadow: 0 10px 40px rgba(0,0,0,.2); }
    .modal-header  { background: linear-gradient(135deg,#1e3a8a,#1e40af); color: white; border-radius: 14px 14px 0 0; padding: 18px 26px; }
    .modal-body    { padding: 26px; max-height: 75vh; overflow-y: auto; }
    .close { color: white; opacity: .9; text-shadow: none; font-size: 26px; }

    /* ── APP DETAIL CARD ── */
    .app-info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 18px; }
    .app-info-item { background: #f8fafc; border-radius: 9px; padding: 12px 14px; border-left: 3px solid #1e40af; }
    .app-info-item label { font-size: 10px; font-weight: 800; text-transform: uppercase; color: #64748b; display: block; margin-bottom: 3px; }
    .app-info-item span  { font-size: 14px; font-weight: 700; color: #1e293b; }

    /* ── STATUS SELECT IN MODAL ── */
    .status-update-box { background: #f1f5f9; border-radius: 10px; padding: 18px; margin-bottom: 14px; }
    .status-update-box h6 { color: #1e3a8a; font-weight: 700; margin-bottom: 12px; font-size: 13px; }

    /* ── ALERT ── */
    .alert-container { position: fixed; top: 20px; right: 20px; z-index: 9999; min-width: 300px; }
    .alert { border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,.15); }

    /* ── EMPTY STATE ── */
    .empty-state { text-align: center; padding: 50px 20px; }
    .empty-state i { font-size: 56px; color: #cbd5e1; margin-bottom: 16px; }
    .empty-state h4 { color: #475569; font-weight: 700; }
    .empty-state p  { color: #94a3b8; font-size: 14px; }

    @media (max-width: 768px) {
        .page-header { flex-direction: column; }
        .form-row-2, .form-row-3 { grid-template-columns: 1fr; }
        .app-info-grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>

<div class="alert-container" id="alertContainer"></div>

<div class="container-fluid">

  <!-- PAGE HEADER -->
  <div class="page-header">
    <div>
      <h1><i class="fas fa-briefcase"></i> Career Management</h1>
      <div class="header-info"><?php echo date('l, F d, Y'); ?> &nbsp;|&nbsp; Manage job postings and review applications</div>
    </div>
    <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;">
      <button class="btn-hdr btn-success-c" onclick="openPostJob()">
        <i class="fas fa-plus-circle"></i> Post New Job
      </button>
      
    </div>
  </div>

  <!-- STATS -->
  <div class="stats-row">
    <div class="stat-card blue">
      <div class="stat-icon blue"><i class="fas fa-briefcase"></i></div>
      <div class="stat-content"><h3><?php echo $stat_jobs_total; ?></h3><p>Total Jobs Posted</p></div>
    </div>
    <div class="stat-card green">
      <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
      <div class="stat-content"><h3><?php echo $stat_jobs_active; ?></h3><p>Active Openings</p></div>
    </div>
    <div class="stat-card purple">
      <div class="stat-icon purple"><i class="fas fa-users"></i></div>
      <div class="stat-content"><h3><?php echo $stat_apps_total; ?></h3><p>Total Applications</p></div>
    </div>
    <div class="stat-card amber">
      <div class="stat-icon amber"><i class="fas fa-inbox"></i></div>
      <div class="stat-content"><h3><?php echo $stat_apps_new; ?></h3><p>New / Unreviewed</p></div>
    </div>
    <div class="stat-card teal">
      <div class="stat-icon teal"><i class="fas fa-star"></i></div>
      <div class="stat-content"><h3><?php echo $stat_apps_short; ?></h3><p>Shortlisted</p></div>
    </div>
    <div class="stat-card green">
      <div class="stat-icon green"><i class="fas fa-trophy"></i></div>
      <div class="stat-content"><h3><?php echo $stat_apps_sel; ?></h3><p>Selected</p></div>
    </div>
  </div>

  <!-- TABS -->
  <div class="cr-tab-bar">
    <button class="cr-tab-btn active" onclick="switchTab('tab_jobs', this)">
      <i class="fas fa-list-alt"></i> Job Postings
    </button>
    <button class="cr-tab-btn" onclick="switchTab('tab_apps', this)">
      <i class="fas fa-file-alt"></i> Applications
      <?php if($stat_apps_new > 0): ?><span style="background:#ef4444;color:white;border-radius:20px;padding:2px 8px;font-size:11px;"><?php echo $stat_apps_new; ?> New</span><?php endif; ?>
    </button>
  </div>

  <!-- ══════════════════════════════════════════════════════════════ -->
  <!-- TAB 1: JOB POSTINGS — CARD VIEW -->
  <!-- ══════════════════════════════════════════════════════════════ -->
  <div class="cr-tab-content active" id="tab_jobs">

    <!-- Job Filter Bar -->
    <div class="panel" style="margin-bottom:16px;">
      <div class="panel-body" style="padding:14px 20px;">
        <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;">
          <div class="fg" style="flex:2;min-width:180px;">
            <label>Search Jobs</label>
            <input type="text" class="fi" id="job_search_filter" placeholder="Title, department, location…" oninput="filterJobCards()">
          </div>
          <div class="fg" style="flex:1;min-width:140px;">
            <label>Status</label>
            <select class="fs" id="job_status_filter" onchange="filterJobCards()">
              <option value="">All Status</option>
              <option value="active">Active</option>
              <option value="draft">Draft</option>
              <option value="closed">Closed</option>
            </select>
          </div>
          <div class="fg" style="flex:1;min-width:140px;">
            <label>Job Type</label>
            <select class="fs" id="job_type_filter" onchange="filterJobCards()">
              <option value="">All Types</option>
              <option value="Full Time">Full Time</option>
              <option value="Part Time">Part Time</option>
              <option value="Contract">Contract</option>
              <option value="Internship">Internship</option>
            </select>
          </div>
          <div style="margin-top:20px;">
            <span id="jobs_visible_count" style="background:#e0e7ff;color:#3730a3;padding:8px 16px;border-radius:20px;font-size:12px;font-weight:700;white-space:nowrap;">
              <?php echo $jobs_result ? mysqli_num_rows($jobs_result) : 0; ?> Jobs
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Job Cards Grid -->
    <?php if($jobs_result && mysqli_num_rows($jobs_result) > 0): ?>
    <div id="job_cards_grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:18px;margin-bottom:20px;">

      <?php
      mysqli_data_seek($jobs_result, 0);
      while($job = mysqli_fetch_assoc($jobs_result)):
        $r_ac = $dbConn ? mysqli_query($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications WHERE job_id={$job['id']}") : false;
        $app_count = ($r_ac && ($r_ac_row = mysqli_fetch_assoc($r_ac))) ? intval($r_ac_row['c']) : 0;
        $r_na = $dbConn ? mysqli_query($dbConn, "SELECT COUNT(*) as c FROM hr_career_applications WHERE job_id={$job['id']} AND status='new'") : false;
        $new_apps = ($r_na && ($r_na_row = mysqli_fetch_assoc($r_na))) ? intval($r_na_row['c']) : 0;
        $is_expired  = !empty($job['deadline']) && strtotime($job['deadline']) < strtotime('today');
        $type_colors = ['Full Time'=>'#1e40af','Part Time'=>'#d97706','Contract'=>'#059669','Internship'=>'#7c3aed'];
        $type_bgs    = ['Full Time'=>'#dbeafe','Part Time'=>'#fef3c7','Contract'=>'#d1fae5','Internship'=>'#ede9fe'];
        $type_color  = $type_colors[$job['job_type']] ?? '#1e40af';
        $type_bg     = $type_bgs[$job['job_type']] ?? '#dbeafe';
        $status_color = $job['status']=='active' ? '#065f46' : ($job['status']=='draft' ? '#64748b' : '#991b1b');
        $status_bg    = $job['status']=='active' ? '#d1fae5' : ($job['status']=='draft' ? '#f1f5f9' : '#fee2e2');
        $border_color = $job['status']=='active' ? '#1e40af' : ($job['status']=='draft' ? '#94a3b8' : '#ef4444');
      ?>

      <div class="job-card-item"
           data-search="<?php echo htmlspecialchars(strtolower($job['title'].' '.$job['department'].' '.$job['location'])); ?>"
           data-status="<?php echo $job['status']; ?>"
           data-type="<?php echo htmlspecialchars($job['job_type']); ?>"
           style="background:white;border-radius:14px;box-shadow:0 2px 12px rgba(0,0,0,0.08);overflow:hidden;border-top:4px solid <?php echo $border_color; ?>;transition:transform .2s,box-shadow .2s;">

        <!-- Card Header -->
        <div style="padding:18px 20px 14px;">
          <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:10px;">
            <div style="flex:1;">
              <div style="font-size:16px;font-weight:800;color:#0f172a;line-height:1.3;margin-bottom:6px;">
                <?php echo htmlspecialchars($job['title']); ?>
              </div>
              <div style="display:flex;flex-wrap:wrap;gap:6px;">
                <span style="background:<?php echo $type_bg; ?>;color:<?php echo $type_color; ?>;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;">
                  <?php echo htmlspecialchars($job['job_type']); ?>
                </span>
                <span style="background:<?php echo $status_bg; ?>;color:<?php echo $status_color; ?>;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;">
                  <?php echo ucfirst($job['status']); ?>
                </span>
                <?php if($is_expired && $job['status']=='active'): ?>
                <span style="background:#fee2e2;color:#dc2626;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;">
                  ⚠️ Expired
                </span>
                <?php endif; ?>
              </div>
            </div>
            <!-- App count bubble -->
            <div style="text-align:center;background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;border-radius:12px;padding:8px 12px;min-width:60px;flex-shrink:0;">
              <div style="font-size:20px;font-weight:900;line-height:1;"><?php echo $app_count; ?></div>
              <div style="font-size:9px;font-weight:700;opacity:.85;text-transform:uppercase;letter-spacing:.3px;">Apps</div>
              <?php if($new_apps > 0): ?>
              <div style="font-size:9px;background:#ef4444;color:white;border-radius:10px;padding:1px 5px;margin-top:3px;font-weight:700;"><?php echo $new_apps; ?> new</div>
              <?php endif; ?>
            </div>
          </div>

          <!-- Meta info -->
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:12px;">
            <div style="display:flex;align-items:center;gap:6px;font-size:12px;color:#475569;">
              <span style="width:20px;height:20px;background:#f1f5f9;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:11px;">🏢</span>
              <?php echo htmlspecialchars($job['department']); ?>
            </div>
            <div style="display:flex;align-items:center;gap:6px;font-size:12px;color:#475569;">
              <span style="width:20px;height:20px;background:#f1f5f9;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:11px;">📍</span>
              <?php echo htmlspecialchars($job['location']); ?>
            </div>
            <?php if(!empty($job['experience'])): ?>
            <div style="display:flex;align-items:center;gap:6px;font-size:12px;color:#475569;">
              <span style="width:20px;height:20px;background:#f1f5f9;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:11px;">🎯</span>
              <?php echo htmlspecialchars($job['experience']); ?>
            </div>
            <?php endif; ?>
          </div>
        </div>

        <!-- Description snippet -->
        <?php if(!empty($job['description'])): ?>
        <div style="padding:0 20px 12px;">
          <div style="font-size:12px;color:#64748b;line-height:1.6;background:#f8fafc;border-radius:8px;padding:10px 12px;border-left:3px solid <?php echo $border_color; ?>;">
            <?php echo htmlspecialchars(mb_substr(strip_tags($job['description']), 0, 130)); ?><?php echo mb_strlen(strip_tags($job['description'])) > 130 ? '…' : ''; ?>
          </div>
        </div>
        <?php endif; ?>

        <!-- Footer -->
        <div style="padding:12px 20px;background:#f8fafc;border-top:1px solid #e2e8f0;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;">
          <div>
            <div style="font-size:10px;color:#94a3b8;font-weight:600;">Posted by <?php echo htmlspecialchars($job['posted_by']); ?></div>
            <div style="font-size:11px;color:#64748b;font-weight:600;margin-top:2px;">
              <i class="fas fa-calendar-alt" style="font-size:10px;"></i> <?php echo date('M d, Y', strtotime($job['posted_date'])); ?>
              <?php if(!empty($job['deadline'])): ?>
                &nbsp;·&nbsp; <i class="fas fa-clock" style="font-size:10px;color:<?php echo $is_expired ? '#ef4444' : '#f59e0b'; ?>"></i>
                <span style="color:<?php echo $is_expired ? '#ef4444' : '#92400e'; ?>">
                  Deadline: <?php echo date('M d, Y', strtotime($job['deadline'])); ?>
                </span>
              <?php endif; ?>
            </div>
          </div>
          <div style="display:flex;gap:6px;">
            <button class="btn-sm-edit" onclick='editJob(<?php echo htmlspecialchars(json_encode($job)); ?>)' title="Edit">
              <i class="fas fa-edit"></i> Edit
            </button>
            <button class="btn-sm-del" onclick="deleteJob(<?php echo $job['id']; ?>)" title="Delete">
              <i class="fas fa-trash"></i>
            </button>
          </div>
        </div>
      </div>

      <?php endwhile; ?>
    </div>

    <div id="job_cards_empty" style="display:none;text-align:center;padding:50px 20px;background:white;border-radius:12px;box-shadow:0 2px 10px rgba(0,0,0,.08);">
      <i class="fas fa-search" style="font-size:48px;color:#cbd5e1;"></i>
      <h4 style="color:#475569;margin:16px 0 8px;">No Jobs Match Your Filter</h4>
      <p style="color:#94a3b8;font-size:14px;">Try adjusting your search or clearing the filters.</p>
    </div>

    <?php else: ?>
    <div style="text-align:center;padding:60px 20px;background:white;border-radius:14px;box-shadow:0 2px 10px rgba(0,0,0,.08);">
      <div style="font-size:64px;margin-bottom:16px;">💼</div>
      <h4 style="color:#0f172a;font-weight:800;margin-bottom:8px;">No Jobs Posted Yet</h4>
      <p style="color:#64748b;font-size:14px;margin-bottom:20px;">Click "Post New Job" to create your first opening.</p>
      <button class="btn-hdr btn-success-c" onclick="openPostJob()"><i class="fas fa-plus"></i> Post New Job</button>
    </div>
    <?php endif; ?>

  </div>

  <!-- ══════════════════════════════════════════════════════════════ -->
  <!-- TAB 2: APPLICATIONS -->
  <!-- ══════════════════════════════════════════════════════════════ -->
  <div class="cr-tab-content" id="tab_apps">

    <!-- Filter Bar -->
    <div class="panel" style="margin-bottom:16px;">
      <div class="panel-body" style="padding:16px 22px;">
        <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;">
          <div class="fg" style="flex:1;min-width:150px;">
            <label>Filter by Status</label>
            <select class="fs" id="app_status_filter" onchange="filterApps()">
              <option value="">All Statuses</option>
              <option value="new">New</option>
              <option value="reviewed">Reviewed</option>
              <option value="shortlisted">Shortlisted</option>
              <option value="interview">Interview</option>
              <option value="selected">Selected</option>
              <option value="rejected">Rejected</option>
              <option value="on_hold">On Hold</option>
            </select>
          </div>
          <div class="fg" style="flex:1;min-width:150px;">
            <label>Filter by Department</label>
            <select class="fs" id="app_dept_filter" onchange="filterApps()">
              <option value="">All Departments</option>
              <?php
              $dp = mysqli_query($dbConn, "SELECT DISTINCT department FROM hr_career_applications ORDER BY department");
              while($d = mysqli_fetch_assoc($dp)) echo '<option value="'.htmlspecialchars($d['department']).'">'.htmlspecialchars($d['department']).'</option>';
              ?>
            </select>
          </div>
          <div class="fg" style="flex:2;min-width:180px;">
            <label>Search Applicant</label>
            <input type="text" class="fi" id="app_search" placeholder="Name, email, phone…" oninput="filterApps()">
          </div>
        </div>
      </div>
    </div>

    <?php if($apps_result && mysqli_num_rows($apps_result) > 0): ?>
    <!-- Bulk Action Bar -->
    <div id="bulk_action_bar" style="display:none;background:linear-gradient(135deg,#1e3a8a,#1e40af);border-radius:10px;padding:12px 20px;margin-bottom:12px;display:none;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;">
      <span id="bulk_count_label" style="color:white;font-weight:700;font-size:14px;">0 selected</span>
      <div style="display:flex;gap:8px;">
        <button onclick="bulkDeleteApps()" style="background:#ef4444;color:white;border:none;padding:8px 18px;border-radius:8px;font-weight:700;cursor:pointer;font-size:13px;">
          <i class="fas fa-trash"></i> Delete Selected
        </button>
        <button onclick="clearSelection()" style="background:rgba(255,255,255,.2);color:white;border:none;padding:8px 18px;border-radius:8px;font-weight:700;cursor:pointer;font-size:13px;">
          Cancel
        </button>
      </div>
    </div>

    <div class="table-container">
      <div class="table-hdr-actions">
        <h5><i class="fas fa-file-alt"></i> All Job Applications</h5>
        <span id="app_count_label" style="background:#e0e7ff;color:#3730a3;padding:6px 16px;border-radius:20px;font-size:12px;font-weight:700;">
          <?php echo mysqli_num_rows($apps_result); ?> Total
        </span>
      </div>
      <table id="appsTable" class="display" style="width:100%">
        <thead>
          <tr>
            <th><input type="checkbox" id="chk_all" onclick="toggleAllApps(this)" title="Select All" style="width:16px;height:16px;cursor:pointer;accent-color:#1e40af;"></th>
            <th>Applicant</th>
            <th>Job Applied</th>
            <th>Experience</th>
            <th>City</th>
            <th>Status</th>
            <th>Date</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php
          $sno = 1;
          mysqli_data_seek($apps_result, 0);
          while($app = mysqli_fetch_assoc($apps_result)):
          ?>
          <tr data-status="<?php echo $app['status']; ?>" data-dept="<?php echo htmlspecialchars($app['department']); ?>" data-search="<?php echo htmlspecialchars(strtolower($app['applicant_name'].' '.$app['email'].' '.$app['phone'])); ?>" data-id="<?php echo $app['id']; ?>" data-app-id="<?php echo $app['id']; ?>"<?php if(!empty($app['email_sent'])): ?> style="border-left:4px solid #059669;"<?php endif; ?>>
            <td><input type="checkbox" class="app-chk" value="<?php echo $app['id']; ?>" onclick="updateBulkBar()" style="width:16px;height:16px;cursor:pointer;accent-color:#1e40af;"></td>
            <td>
              <div style="font-weight:700;color:#1e293b;font-size:13px;"><?php echo htmlspecialchars($app['applicant_name']); ?></div>
              <div style="font-size:11px;color:#64748b;margin-top:2px;">
                <i class="fas fa-envelope" style="font-size:10px;"></i> <?php echo htmlspecialchars($app['email']); ?>
              </div>
              <div style="font-size:11px;color:#64748b;margin-top:1px;">
                <i class="fas fa-phone" style="font-size:10px;"></i> <?php echo htmlspecialchars($app['phone']); ?>
              </div>
              <?php if($app['status'] == 'new'): ?>
                <span style="font-size:10px;background:#dbeafe;color:#1e40af;padding:1px 7px;border-radius:10px;font-weight:700;display:inline-block;margin-top:3px;">🆕 New</span>
              <?php endif; ?>
            </td>
            <td>
              <div style="font-weight:600;font-size:13px;color:#0f172a;"><?php echo htmlspecialchars($app['job_title'] ?: 'Open Application'); ?></div>
              <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($app['department'] ?: ''); ?></div>
            </td>
            <td style="font-size:13px;"><?php echo htmlspecialchars($app['experience'] ?: '—'); ?></td>
            <td style="font-size:13px;"><?php echo htmlspecialchars($app['city'] ?: '—'); ?></td>
            <td><span class="badge badge-<?php echo $app['status']; ?>"><?php echo ucfirst(str_replace('_',' ',$app['status'])); ?></span></td>
            <td style="font-size:12px;white-space:nowrap;"><?php echo date('M d, Y', strtotime($app['applied_date'])); ?></td>
            <td>
              <div style="display:flex;gap:4px;align-items:center;">
                <?php if(!empty($app['resume_path'])): 
                    // Handle both old relative paths and new full URLs
                    $resume_url = (strpos($app['resume_path'],'http')===0) 
                        ? $app['resume_path'] 
                        : 'https://abra-logistic.com/' . ltrim($app['resume_path'],'/');
                ?>
                  <a href="<?php echo htmlspecialchars($resume_url); ?>" target="_blank" class="btn-sm-view" title="View Resume" style="text-decoration:none;">
                    <i class="fas fa-file-pdf"></i> CV
                  </a>
                <?php endif; ?>
                <button class="btn-sm-edit" onclick='openAppDetail(<?php echo htmlspecialchars(json_encode($app)); ?>)' title="Review">
                  <i class="fas fa-eye"></i> Review
                </button>
                <button class="btn-sm-view email-btn" onclick='quickEmail(<?php echo htmlspecialchars(json_encode(["id"=>$app["id"],"name"=>$app["applicant_name"],"email"=>$app["email"],"job"=>$app["job_title"]])); ?>)' title="<?php echo !empty($app['email_sent']) ? 'Email already sent — click to send again' : 'Send Email'; ?>" style="background:<?php echo !empty($app['email_sent']) ? '#059669;color:white' : '#d1fae5;color:#065f46'; ?>;">
                  <i class="fas <?php echo !empty($app['email_sent']) ? 'fa-envelope-open-text' : 'fa-envelope'; ?>"></i>
                </button>
                <?php if($can_delete_apps): ?>
                <button class="btn-sm-del" onclick="deleteApplication(<?php echo $app['id']; ?>, '<?php echo htmlspecialchars(addslashes($app['applicant_name'])); ?>')" title="Delete Application">
                  <i class="fas fa-trash"></i>
                </button>
                <?php endif; ?>
              </div>
            </td>
          </tr>
          <?php endwhile; ?>
        </tbody>
      </table>
    </div>
    <?php else: ?>
    <div class="panel">
      <div class="panel-body">
        <div class="empty-state">
          <i class="fas fa-inbox"></i>
          <h4>No Applications Yet</h4>
          <p>Once candidates apply through the website, their applications will appear here.</p>
        </div>
      </div>
    </div>
    <?php endif; ?>
  </div>

</div>

<!-- ══════════════════════════════════════════════════════════════ -->
<!-- MODAL: POST / EDIT JOB -->
<!-- ══════════════════════════════════════════════════════════════ -->
<div class="modal fade" id="jobModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h4 class="modal-title" id="jobModalTitle"><i class="fas fa-plus-circle"></i> Post New Job</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="job_edit_id">

        <div class="form-row-2">
          <div class="fg">
            <label>Job Title <span>*</span></label>
            <input type="text" id="job_title" class="fi" placeholder="e.g. Logistics Coordinator">
          </div>
          <div class="fg">
            <label>Department <span>*</span></label>
            <input type="text" id="job_dept" class="fi" list="dept_list" placeholder="e.g. Operations">
            <datalist id="dept_list">
              <option>Operations</option><option>Sales</option><option>Marketing</option>
              <option>HR</option><option>Finance</option><option>Technology</option>
              <option>Logistics</option><option>Customer Support</option><option>Management</option>
            </datalist>
          </div>
        </div>

        <div class="form-row-3">
          <div class="fg">
            <label>Location <span>*</span></label>
            <input type="text" id="job_loc" class="fi" placeholder="e.g. Bangalore">
          </div>
          <div class="fg">
            <label>Job Type</label>
            <select id="job_type" class="fs">
              <option value="Full Time">Full Time</option>
              <option value="Part Time">Part Time</option>
              <option value="Contract">Contract</option>
              <option value="Internship">Internship</option>
            </select>
          </div>
          <div class="fg">
            <label>Status</label>
            <select id="job_status" class="fs">
              <option value="active">Active</option>
              <option value="draft">Draft</option>
              <option value="closed">Closed</option>
            </select>
          </div>
        </div>

        <div class="form-row-3">
          <div class="fg">
            <label>Experience Required</label>
            <input type="text" id="job_exp" class="fi" placeholder="e.g. 2–5 years">
          </div>
          <div class="fg">
            <label>Application Deadline</label>
            <input type="date" id="job_deadline" class="fi">
          </div>
        </div>

        <div class="fg" style="margin-bottom:14px">
          <label>Job Description <span>*</span></label>
          <textarea id="job_desc" class="ft" placeholder="Describe the role, responsibilities, and day-to-day tasks…"></textarea>
        </div>

        <div class="fg" style="margin-bottom:20px">
          <label>Requirements / Qualifications</label>
          <textarea id="job_req" class="ft" placeholder="List must-have skills, qualifications, certifications…"></textarea>
        </div>

        <div style="text-align:right;">
          <button type="button" class="btn-hdr btn-primary-c" onclick="saveJob()">
            <i class="fas fa-save"></i> <span id="jobSaveLbl">Post Job</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- ══════════════════════════════════════════════════════════════ -->
<!-- MODAL: APPLICATION DETAIL / REVIEW -->
<!-- ══════════════════════════════════════════════════════════════ -->
<div class="modal fade" id="appModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h4 class="modal-title"><i class="fas fa-user-circle"></i> Applicant Review</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="app_edit_id">

        <div class="app-info-grid">
          <div class="app-info-item"><label>Applicant Name</label><span id="av_name">—</span></div>
          <div class="app-info-item"><label>Job Applied For</label><span id="av_job">—</span></div>
          <div class="app-info-item"><label>Email</label><span id="av_email">—</span></div>
          <div class="app-info-item"><label>Phone</label><span id="av_phone">—</span></div>
          <div class="app-info-item"><label>City</label><span id="av_city">—</span></div>
          <div class="app-info-item"><label>Experience</label><span id="av_exp">—</span></div>
          <div class="app-info-item"><label>Applied Date</label><span id="av_date">—</span></div>
        </div>

        <div id="av_cover_wrap" style="background:#f8fafc;border-radius:9px;padding:14px;margin-bottom:16px;border-left:3px solid #1e40af;display:none;">
          <div style="font-size:11px;font-weight:800;text-transform:uppercase;color:#64748b;margin-bottom:6px;">Cover Letter</div>
          <div id="av_cover" style="font-size:13px;color:#1e293b;line-height:1.7;white-space:pre-wrap;"></div>
        </div>

        <div id="av_resume_wrap" style="margin-bottom:18px;display:none;">
          <a id="av_resume_link" href="#" target="_blank" class="btn-hdr btn-primary-c" style="font-size:13px;">
            <i class="fas fa-file-pdf"></i> Download Resume
          </a>
        </div>

        <!-- STATUS UPDATE -->
        <div class="status-update-box">
          <h6><i class="fas fa-pencil-alt"></i> Update Application Status</h6>
          <div class="form-row-2" style="margin-bottom:12px;">
            <div class="fg">
              <label>Status</label>
              <select id="av_status" class="fs">
                <option value="new">New</option>
                <option value="reviewed">Reviewed</option>
                <option value="shortlisted">Shortlisted</option>
                <option value="interview">Interview Scheduled</option>
                <option value="selected">Selected</option>
                <option value="rejected">Rejected</option>
                <option value="on_hold">On Hold</option>
              </select>
            </div>
          </div>
          <div class="fg" style="margin-bottom:14px;">
            <label>HR Notes / Remarks</label>
            <textarea id="av_notes" class="ft" style="min-height:80px;" placeholder="Add your review notes, interview feedback, or reason for rejection…"></textarea>
          </div>
          <button class="btn-hdr btn-success-c" onclick="saveAppStatus()">
            <i class="fas fa-save"></i> Save Review
          </button>
        </div>



        <!-- Delete button for management only -->
        <?php if($can_delete_apps): ?>
        <div style="margin-top:16px;text-align:right;">
          <button class="btn-hdr" style="background:#fee2e2;color:#dc2626;border:none;" onclick="deleteAppFromModal()">
            <i class="fas fa-trash"></i> Delete This Application
          </button>
        </div>
        <?php endif; ?>

      </div>
    </div>
  </div>
</div>

<!-- QUICK EMAIL MODAL -->
<div class="modal fade" id="quickEmailModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#065f46,#059669);">
        <h4 class="modal-title" style="color:white;"><i class="fas fa-envelope"></i> Send Email to <span id="qe_name"></span></h4>
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <input type="hidden" id="qe_app_id">
        <input type="hidden" id="qe_email_to">

        <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:10px 14px;margin-bottom:16px;font-size:13px;">
          <i class="fas fa-paper-plane" style="color:#16a34a;"></i>
          Sending to: <strong id="qe_email_display" style="color:#065f46;"></strong>
        </div>

        <!-- Quick templates -->
        <div style="margin-bottom:14px;">
          <div style="font-size:12px;font-weight:700;color:#475569;margin-bottom:8px;text-transform:uppercase;letter-spacing:.5px;">Quick Templates</div>
          <div style="display:flex;gap:6px;flex-wrap:wrap;">
            <button class="btn-hdr" style="background:#dbeafe;color:#1e40af;border:none;font-size:12px;padding:6px 12px;" onclick="qeFillTemplate('shortlisted')">✅ Shortlisted</button>
            <button class="btn-hdr" style="background:#fef3c7;color:#92400e;border:none;font-size:12px;padding:6px 12px;" onclick="qeFillTemplate('interview')">📅 Interview</button>
            <button class="btn-hdr" style="background:#fee2e2;color:#dc2626;border:none;font-size:12px;padding:6px 12px;" onclick="qeFillTemplate('rejected')">❌ Rejected</button>
            <button class="btn-hdr" style="background:#f1f5f9;color:#475569;border:none;font-size:12px;padding:6px 12px;" onclick="qeFillTemplate('custom')">✏️ Custom</button>
          </div>
        </div>

        <div class="fg" style="margin-bottom:10px;">
          <label>Subject</label>
          <input type="text" id="qe_subject" class="fi" placeholder="Email subject…">
        </div>
        <div class="fg" style="margin-bottom:16px;">
          <label>Message</label>
          <textarea id="qe_body" class="ft" style="min-height:180px;" placeholder="Type your message…"></textarea>
        </div>

        <div style="display:flex;gap:10px;justify-content:flex-end;">
          <button class="btn-hdr" style="background:#e2e8f0;color:#475569;border:none;" data-dismiss="modal">Cancel</button>
          <button class="btn-hdr" id="qe_send_btn" style="background:linear-gradient(135deg,#065f46,#059669);color:white;border:none;" onclick="qeSendEmail()">
            <i class="fas fa-paper-plane"></i> Send Email
          </button>
        </div>
        <div id="qe_status" style="display:none;margin-top:12px;padding:10px 14px;border-radius:8px;font-size:13px;font-weight:700;"></div>
      </div>
    </div>
  </div>
</div>

<script>
// Pass PHP flags to JS
const CAN_DELETE_APPS = <?php echo $js_can_delete; ?>;
const CURRENT_USER    = '<?php echo $js_current_user; ?>';

// Current quick-email context
let qeContext = {};

function quickEmail(app) {
    qeContext = app;
    document.getElementById('qe_app_id').value       = app.id;
    document.getElementById('qe_email_to').value     = app.email;
    document.getElementById('qe_name').textContent   = app.name;
    document.getElementById('qe_email_display').textContent = app.email;
    document.getElementById('qe_subject').value      = '';
    document.getElementById('qe_body').value         = '';
    document.getElementById('qe_status').style.display = 'none';
    $('#quickEmailModal').modal('show');
}

function markEmailSent(appId) {
    // Find the email button for this app and turn it green with a checkmark
    document.querySelectorAll('[data-app-id="' + appId + '"] .email-btn').forEach(btn => {
        btn.style.background = '#059669';
        btn.style.color      = 'white';
        btn.title            = 'Email already sent';
        btn.innerHTML        = '<i class="fas fa-envelope-open-text"></i>';
    });
    // Also mark the row visually
    const row = document.querySelector('tr[data-app-id="' + appId + '"]');
    if(row) row.style.borderLeft = '4px solid #059669';
}

function qeFillTemplate(type) {
    const name = qeContext.name  || '';
    const job  = qeContext.job   || 'the position';
    const t = {
        shortlisted: {
            subject: 'Congratulations! You have been Shortlisted — Abra E-Logistic',
            body: `Dear ${name},

We are pleased to inform you that your application for "${job}" has been reviewed and you have been shortlisted!

Our HR team will be in touch shortly with further details on the next steps.

Thank you for your interest in joining Abra E-Logistic.

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        },
        interview: {
            subject: 'Interview Invitation — Abra E-Logistic',
            body: `Dear ${name},

Thank you for applying for "${job}" at Abra E-Logistic.

We would like to invite you for an interview. Please reply to confirm your availability.

Interview Format : [Online / In-Person]
Date & Time       : [To be confirmed]
Location / Link   : [To be shared]

Please carry a copy of your resume.

We look forward to meeting you!

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        },
        rejected: {
            subject: 'Update on your Application — Abra E-Logistic',
            body: `Dear ${name},

Thank you for applying for "${job}" at Abra E-Logistic and for your interest in joining our team.

After careful consideration, we regret to inform you that we will not be moving forward with your application at this time.

We wish you the very best in your job search and encourage you to apply for future openings.

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        },
        custom: { subject: '', body: `Dear ${name},



Warm regards,
HR Team
Abra E-Logistic` }
    };
    if(t[type]) {
        document.getElementById('qe_subject').value = t[type].subject;
        document.getElementById('qe_body').value    = t[type].body;
    }
}

function qeSendEmail() {
    const to      = document.getElementById('qe_email_to').value.trim();
    const subject = document.getElementById('qe_subject').value.trim();
    const body    = document.getElementById('qe_body').value.trim();
    const st      = document.getElementById('qe_status');
    const btn     = document.getElementById('qe_send_btn');

    if(!subject) { document.getElementById('qe_subject').focus(); return; }
    if(!body)    { document.getElementById('qe_body').focus();    return; }

    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending…';

    const fd = new FormData();
    const appId = document.getElementById('qe_app_id').value;
    fd.append('ajax_action', 'send_applicant_email');
    fd.append('to_email', to);
    fd.append('subject',  subject);
    fd.append('body',     body);
    fd.append('app_id',   appId);

    fetch(location.href, { method:'POST', body:fd })
    .then(r => r.json())
    .then(res => {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-paper-plane"></i> Send Email';
        st.style.display = 'block';
        st.style.background = res.success ? '#d1fae5' : '#fee2e2';
        st.style.color      = res.success ? '#065f46' : '#dc2626';
        st.textContent      = res.success ? '✅ ' + res.message : '❌ ' + res.message;
        if(res.success) {
            // Turn email button green in table to show mail was sent
            markEmailSent(appId);
            setTimeout(() => $('#quickEmailModal').modal('hide'), 2000);
        }
    });
}
</script>

<!-- SCRIPTS -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/js/select2.min.js"></script>

<script>
// ── TABS ──
function switchTab(id, btn) {
    document.querySelectorAll('.cr-tab-content').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.cr-tab-btn').forEach(b => b.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    btn.classList.add('active');
}

// ── ALERT ──
function showAlert(msg, type='success') {
    const el = document.createElement('div');
    el.className = 'alert alert-' + (type=='success'?'success':'danger') + ' alert-dismissible fade show';
    el.innerHTML = '<strong>' + (type=='success'?'✅ Success!':'❌ Error!') + '</strong> ' + msg + '<button type="button" class="close" data-dismiss="alert">&times;</button>';
    document.getElementById('alertContainer').prepend(el);
    setTimeout(() => el.remove(), 5000);
}

// ── OPEN POST JOB ──
function openPostJob() {
    document.getElementById('job_edit_id').value = '';
    document.getElementById('jobModalTitle').innerHTML = '<i class="fas fa-plus-circle"></i> Post New Job';
    document.getElementById('jobSaveLbl').textContent = 'Post Job';
    ['job_title','job_dept','job_loc','job_exp','job_desc','job_req','job_deadline'].forEach(id => document.getElementById(id).value = '');
    document.getElementById('job_type').value = 'Full Time';
    document.getElementById('job_status').value = 'active';
    $('#jobModal').modal('show');
}

// ── EDIT JOB ──
function editJob(job) {
    document.getElementById('job_edit_id').value  = job.id;
    document.getElementById('job_title').value    = job.title;
    document.getElementById('job_dept').value     = job.department;
    document.getElementById('job_loc').value      = job.location;
    document.getElementById('job_type').value     = job.job_type;
    document.getElementById('job_status').value   = job.status;
    document.getElementById('job_exp').value      = job.experience || '';
    document.getElementById('job_deadline').value = job.deadline || '';
    document.getElementById('job_desc').value     = job.description || '';
    document.getElementById('job_req').value      = job.requirements || '';
    document.getElementById('jobModalTitle').innerHTML = '<i class="fas fa-edit"></i> Edit Job Posting';
    document.getElementById('jobSaveLbl').textContent = 'Update Job';
    $('#jobModal').modal('show');
}

// ── SAVE JOB ──
function saveJob() {
    const id      = document.getElementById('job_edit_id').value;
    const title   = document.getElementById('job_title').value.trim();
    const dept    = document.getElementById('job_dept').value.trim();
    const loc     = document.getElementById('job_loc').value.trim();

    if(!title || !dept || !loc) { showAlert('Title, Department, and Location are required.', 'error'); return; }

    const fd = new FormData();
    fd.append('ajax_action',   id ? 'update_job' : 'post_job');
    fd.append('id',            id);
    fd.append('title',         title);
    fd.append('department',    dept);
    fd.append('location',      loc);
    fd.append('job_type',      document.getElementById('job_type').value);
    fd.append('status',        document.getElementById('job_status').value);
    fd.append('experience',    document.getElementById('job_exp').value.trim());
    fd.append('deadline',      document.getElementById('job_deadline').value);
    fd.append('description',   document.getElementById('job_desc').value.trim());
    fd.append('requirements',  document.getElementById('job_req').value.trim());

    fetch(location.href, { method: 'POST', body: fd })
    .then(r => r.json())
    .then(res => {
        if(res.success) { showAlert(res.message); $('#jobModal').modal('hide'); setTimeout(()=>location.reload(),1000); }
        else showAlert(res.message || 'Error saving job.', 'error');
    })
    .catch(() => showAlert('Connection error.', 'error'));
}

// ── DELETE JOB ──
function deleteJob(id) {
    if(!confirm('Are you sure you want to delete this job posting? This cannot be undone.')) return;
    const fd = new FormData();
    fd.append('ajax_action', 'delete_job');
    fd.append('id', id);
    fetch(location.href, { method:'POST', body:fd })
    .then(r=>r.json())
    .then(res => { if(res.success) { showAlert('Job deleted.'); setTimeout(()=>location.reload(),800); } else showAlert('Error deleting job.','error'); });
}

// ── EMAIL TEMPLATES ──
function fillEmailTemplate(type) {
    const name    = document.getElementById('av_name').textContent.trim();
    const job     = document.getElementById('av_job').textContent.trim();
    const templates = {
        shortlisted: {
            subject: 'Congratulations! You have been Shortlisted — Abra E-Logistic',
            body: `Dear ${name},

We are pleased to inform you that your application for the position of "${job}" at Abra E-Logistic has been reviewed, and we are happy to let you know that you have been shortlisted!

Our HR team will be in touch shortly with further details regarding the next steps in the selection process.

Thank you for your interest in joining Abra E-Logistic. We look forward to speaking with you.

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        },
        interview: {
            subject: 'Interview Invitation — Abra E-Logistic',
            body: `Dear ${name},

Thank you for applying for the "${job}" position at Abra E-Logistic.

We are pleased to invite you for an interview. Please reply to this email to confirm your availability, and our team will share the interview details with you.

Interview Format: [Online / In-Person]
Location / Link: [To be shared]
Date & Time: [To be confirmed]

Please carry a copy of your resume and any relevant documents.

We look forward to meeting you!

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        },
        rejected: {
            subject: 'Update on your Application — Abra E-Logistic',
            body: `Dear ${name},

Thank you for taking the time to apply for the "${job}" position at Abra E-Logistic and for your interest in joining our team.

After careful consideration, we regret to inform you that we will not be moving forward with your application at this time. This was a difficult decision as we received many strong applications.

We encourage you to keep an eye on our careers page for future opportunities that may be a better fit.

We appreciate your interest in Abra E-Logistic and wish you the very best in your job search.

Warm regards,
HR Team
Abra E-Logistic
📞 (+91) 8867288076
📧 hr-admin@abra-logistic.com`
        }
    };
    if(templates[type]) {
        document.getElementById('email_subject').value = templates[type].subject;
        document.getElementById('email_body').value    = templates[type].body;
    }
}

function sendApplicantEmail() {
    const to      = document.getElementById('av_email').textContent.trim();
    const subject = document.getElementById('email_subject').value.trim();
    const body    = document.getElementById('email_body').value.trim();
    const status  = document.getElementById('email_send_status');

    if(!to || to === '—')    { showAlert('No email address found for this applicant.', 'error'); return; }
    if(!subject)             { document.getElementById('email_subject').focus(); showAlert('Please enter a subject.', 'error'); return; }
    if(!body)                { document.getElementById('email_body').focus();    showAlert('Please enter a message.', 'error'); return; }

    const btn = event.currentTarget;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending…';

    const fd = new FormData();
    fd.append('ajax_action', 'send_applicant_email');
    fd.append('to_email',    to);
    fd.append('subject',     subject);
    fd.append('body',        body);
    fd.append('app_id',      document.getElementById('app_edit_id').value);

    fetch(location.href, { method:'POST', body:fd })
    .then(r => r.json())
    .then(res => {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-paper-plane"></i> Send Email';
        status.style.display = 'block';
        status.style.cssText = `display:block;padding:10px 14px;border-radius:8px;font-size:13px;font-weight:700;margin-top:10px;background:${res.success?'#d1fae5':'#fee2e2'};color:${res.success?'#065f46':'#dc2626'}`;
        status.textContent = res.success ? '✅ ' + res.message : '❌ ' + res.message;
        if(res.success) {
            document.getElementById('email_subject').value = '';
            document.getElementById('email_body').value    = '';
            setTimeout(() => status.style.display = 'none', 4000);
        }
    });
}

function deleteAppFromModal() {
    const id   = document.getElementById('app_edit_id').value;
    const name = document.getElementById('av_name').textContent.trim();
    if(!CAN_DELETE_APPS) { showAlert('You do not have permission to delete applications.', 'error'); return; }
    if(!confirm('Delete application from "' + name + '"?\nThis cannot be undone.')) return;
    const fd = new FormData();
    fd.append('ajax_action', 'delete_application');
    fd.append('id', id);
    fetch(location.href, { method:'POST', body:fd })
    .then(r => r.json())
    .then(res => {
        if(res.success) {
            $('#appModal').modal('hide');
            showAlert('Application deleted.');
            setTimeout(() => location.reload(), 800);
        } else {
            showAlert('Error deleting application.', 'error');
        }
    });
}

// ── BULK SELECT ──
function toggleAllApps(chk) {
    document.querySelectorAll('.app-chk').forEach(c => c.checked = chk.checked);
    updateBulkBar();
}

function updateBulkBar() {
    const checked = document.querySelectorAll('.app-chk:checked');
    const bar = document.getElementById('bulk_action_bar');
    const lbl = document.getElementById('bulk_count_label');
    if(checked.length > 0) {
        bar.style.display = 'flex';
        lbl.textContent = checked.length + ' application' + (checked.length > 1 ? 's' : '') + ' selected';
    } else {
        bar.style.display = 'none';
        document.getElementById('chk_all').checked = false;
    }
}

function clearSelection() {
    document.querySelectorAll('.app-chk').forEach(c => c.checked = false);
    document.getElementById('chk_all').checked = false;
    document.getElementById('bulk_action_bar').style.display = 'none';
}

function bulkDeleteApps() {
    const checked = document.querySelectorAll('.app-chk:checked');
    if(checked.length === 0) return;
    if(!confirm('Delete ' + checked.length + ' selected application(s)?\nThis cannot be undone.')) return;

    const ids = Array.from(checked).map(c => c.value).join(',');
    const fd = new FormData();
    fd.append('ajax_action', 'bulk_delete_applications');
    fd.append('ids', ids);

    fetch(location.href, { method:'POST', body:fd })
    .then(r => r.json())
    .then(res => {
        if(res.success) {
            showAlert(res.deleted + ' application(s) deleted.');
            // Remove rows from DataTable
            const table = $('#appsTable').DataTable();
            checked.forEach(chk => {
                const row = chk.closest('tr');
                if(row) table.row(row).remove();
            });
            table.draw();
            clearSelection();
        } else {
            showAlert('Error deleting applications.', 'error');
        }
    });
}

// ── DELETE APPLICATION ──
function deleteApplication(id, name) {
    if(!confirm('Delete application from "' + name + '"?\nThis cannot be undone.')) return;
    const fd = new FormData();
    fd.append('ajax_action', 'delete_application');
    fd.append('id', id);
    fetch(location.href, { method:'POST', body:fd })
    .then(r=>r.json())
    .then(res => {
        if(res.success) {
            showAlert('Application deleted successfully.');
            // Remove row from table without full reload
            const table = $('#appsTable').DataTable();
            const btn = document.querySelector('[onclick*="deleteApplication(' + id + ',"]');
            if(btn) {
                const row = btn.closest('tr');
                table.row(row).remove().draw();
            } else {
                setTimeout(()=>location.reload(), 800);
            }
        } else {
            showAlert('Error deleting application.', 'error');
        }
    });
}

// ── OPEN APPLICATION DETAIL ──
function openAppDetail(app) {
    document.getElementById('app_edit_id').value = app.id;
    document.getElementById('av_name').textContent    = app.applicant_name;
    document.getElementById('av_job').textContent     = app.job_title || 'Open Application';
    document.getElementById('av_email').textContent   = app.email;
    document.getElementById('av_phone').textContent   = app.phone || '—';
    document.getElementById('av_city').textContent    = app.city || '—';
    document.getElementById('av_exp').textContent     = app.experience || '—';
    document.getElementById('av_date').textContent    = app.applied_date;
    document.getElementById('av_status').value        = app.status;
    document.getElementById('av_notes').value         = app.hr_notes || '';


    // Cover letter
    if(app.cover_letter) {
        document.getElementById('av_cover').textContent = app.cover_letter;
        document.getElementById('av_cover_wrap').style.display = 'block';
    } else {
        document.getElementById('av_cover_wrap').style.display = 'none';
    }

    // Resume
    if(app.resume_path) {
        // Handle both old relative paths and new full URLs
        const resumeUrl = app.resume_path.startsWith('http') 
            ? app.resume_path 
            : 'https://abra-logistic.com/' + app.resume_path.replace(/^\//, '');
        document.getElementById('av_resume_link').href = resumeUrl;
        document.getElementById('av_resume_link').style.display = 'inline-flex';
        document.getElementById('av_resume_wrap').style.display = 'block';
    } else {
        document.getElementById('av_resume_wrap').style.display = 'none';
    }

    $('#appModal').modal('show');
}

// ── SAVE APPLICATION STATUS ──
function saveAppStatus() {
    const id     = document.getElementById('app_edit_id').value;
    const status = document.getElementById('av_status').value;
    const notes  = document.getElementById('av_notes').value;

    const fd = new FormData();
    fd.append('ajax_action', 'update_app_status');
    fd.append('id', id);
    fd.append('status', status);
    fd.append('notes', notes);

    fetch(location.href, { method:'POST', body:fd })
    .then(r=>r.json())
    .then(res => {
        if(res.success) {
            showAlert('Application status updated!');
            $('#appModal').modal('hide');
            setTimeout(()=>location.reload(),900);
        } else showAlert('Error updating status.','error');
    })
    .catch(() => showAlert('Connection error.','error'));
}

// ── FILTER JOB CARDS ──
function filterJobCards() {
    const searchVal = (document.getElementById('job_search_filter').value || '').toLowerCase();
    const statusVal = (document.getElementById('job_status_filter').value || '').toLowerCase();
    const typeVal   = (document.getElementById('job_type_filter').value   || '').toLowerCase();

    const cards   = document.querySelectorAll('.job-card-item');
    let   visible = 0;

    cards.forEach(card => {
        const s   = (card.dataset.search || '').toLowerCase();
        const st  = (card.dataset.status || '').toLowerCase();
        const tp  = (card.dataset.type   || '').toLowerCase();
        const match = (!searchVal || s.includes(searchVal))
                   && (!statusVal || st === statusVal)
                   && (!typeVal   || tp === typeVal);
        card.style.display = match ? '' : 'none';
        if(match) visible++;
    });

    const emptyEl = document.getElementById('job_cards_empty');
    const countEl = document.getElementById('jobs_visible_count');
    if(emptyEl) emptyEl.style.display = (visible === 0 && cards.length > 0) ? 'block' : 'none';
    if(countEl) countEl.textContent = visible + ' Job' + (visible !== 1 ? 's' : '');
}

// ── FILTER APPLICATIONS TABLE (client-side) ──
function filterApps() {
    const statusVal = document.getElementById('app_status_filter').value.toLowerCase();
    const deptVal   = document.getElementById('app_dept_filter').value.toLowerCase();
    const searchVal = document.getElementById('app_search').value.toLowerCase();

    document.querySelectorAll('#appsTable tbody tr').forEach(row => {
        const s  = (row.dataset.status || '').toLowerCase();
        const d  = (row.dataset.dept   || '').toLowerCase();
        const sr = (row.dataset.search || '').toLowerCase();
        const match = (!statusVal || s.includes(statusVal))
                   && (!deptVal   || d.includes(deptVal))
                   && (!searchVal || sr.includes(searchVal));
        row.style.display = match ? '' : 'none';
    });
}

$(document).ready(function() {
    // Job cards hover lift
    document.querySelectorAll('.job-card-item').forEach(card => {
        card.addEventListener('mouseenter', () => { card.style.transform = 'translateY(-4px)'; card.style.boxShadow = '0 10px 30px rgba(0,0,0,0.13)'; });
        card.addEventListener('mouseleave', () => { card.style.transform = ''; card.style.boxShadow = ''; });
    });
    // Applications DataTable
    if($('#appsTable tbody tr').length > 0) {
        $('#appsTable').DataTable({
            pageLength: 25,
            order: [[6,'desc']],
            scrollX: false,
            autoWidth: false,
            columnDefs: [
                { width: '3%',  targets: 0, orderable: false, searchable: false },
                { width: '24%', targets: 1 },
                { width: '18%', targets: 2 },
                { width: '11%', targets: 3 },
                { width: '9%',  targets: 4 },
                { width: '11%', targets: 5 },
                { width: '10%', targets: 6 },
                { width: '14%', targets: 7, orderable: false },
            ]
        });
    }
    setTimeout(() => $('.alert').fadeOut(), 4000);
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