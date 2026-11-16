<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
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
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}
mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

// =========================================================================
// AUTO-CREATE TABLE (runs once, no-op after that)
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_employee_reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id VARCHAR(50) NOT NULL,
  employee_name VARCHAR(255) NOT NULL,
  report_type ENUM('weekly','monthly') NOT NULL,
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_employee (employee_id),
  INDEX idx_type (report_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Update enum and add notes column if it doesn't exist
mysqli_query($con, "ALTER TABLE hr_employee_reports MODIFY COLUMN report_type ENUM('weekly', 'monthly', 'monthly_summary', 'monthly_calendar') NOT NULL");

$check_notes = mysqli_query($con, "SHOW COLUMNS FROM hr_employee_reports LIKE 'notes'");
if (mysqli_num_rows($check_notes) == 0) {
    mysqli_query($con, "ALTER TABLE hr_employee_reports ADD COLUMN notes TEXT DEFAULT NULL");
}

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE OR HR VIEW
// =========================================================================
$isHRView = isset($_GET['view_emp']) && intval($_GET['view_emp']) > 0;
$user_name = trim($_SESSION['user_name'] ?? '');
$current_employee = null;

if ($isHRView) {
    $emp_id = intval($_GET['view_emp']);
    $r = mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE id = $emp_id LIMIT 1");
    if ($r && mysqli_num_rows($r) > 0) {
        $current_employee = mysqli_fetch_assoc($r);
    }
} else if ($user_name) {
    $safe = mysqli_real_escape_string($con, $user_name);
    $r = mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE name = '$safe' LIMIT 1");
    if ($r && mysqli_num_rows($r) > 0) {
        $current_employee = mysqli_fetch_assoc($r);
    } else {
        $r2 = mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE name LIKE '%$safe%' LIMIT 1");
        if ($r2 && mysqli_num_rows($r2) > 0) {
            $current_employee = mysqli_fetch_assoc($r2);
        }
    }
}

if (!$current_employee) {
    die("Employee record not found for your account. Please contact HR.");
}

// =========================================================================
// HANDLE REPORT UPLOAD
// =========================================================================
if (!$isHRView && isset($_POST['submit_report'])) {
    $report_type = $_POST['report_type'] ?? '';
    $date_from   = $_POST['date_from'] ?? '';
    $date_to     = $_POST['date_to'] ?? '';
    $notes       = $_POST['notes'] ?? '';

    if (!in_array($report_type, ['weekly', 'monthly', 'monthly_summary', 'monthly_calendar'])) {
        $_SESSION['error_message'] = "Invalid report type.";
    } elseif (empty($date_from) || empty($date_to)) {
        $_SESSION['error_message'] = "Please select a date range.";
    } elseif (strtotime($date_to) < strtotime($date_from)) {
        $_SESSION['error_message'] = "End date cannot be before start date.";
    } elseif (empty($_FILES['report_file']['name'])) {
        $_SESSION['error_message'] = "Please select a file to upload.";
    } else {
        $file     = $_FILES['report_file'];
        $allowed  = ['pdf','doc','docx','xls','xlsx','ppt','pptx','csv','jpg','jpeg','png','zip'];
        $ext      = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        $maxSize  = 20 * 1024 * 1024;

        if ($file['error'] !== UPLOAD_ERR_OK) {
            $_SESSION['error_message'] = "File upload error.";
        } elseif (!in_array($ext, $allowed)) {
            $_SESSION['error_message'] = "File type .$ext is not allowed.";
        } elseif ($file['size'] > $maxSize) {
            $_SESSION['error_message'] = "File exceeds 20MB limit.";
        } else {
            $uploadDir = 'uploads/employee_reports/' . $current_employee['employee_id'] . '/';
            if (!file_exists($uploadDir)) mkdir($uploadDir, 0777, true);

            $newName = $report_type . '_' . time() . '_' . basename($file['name']);

            if (move_uploaded_file($file['tmp_name'], $uploadDir . $newName)) {
                $filePath = $uploadDir . $newName;

                $stmt = mysqli_prepare($con, "INSERT INTO hr_employee_reports
                    (employee_id, employee_name, report_type, date_from, date_to, file_path, notes, submitted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, NOW())");
                mysqli_stmt_bind_param($stmt, "sssssss",
                    $current_employee['employee_id'],
                    $current_employee['name'],
                    $report_type,
                    $date_from,
                    $date_to,
                    $filePath,
                    $notes
                );

                if (mysqli_stmt_execute($stmt)) {
                    $_SESSION['success_message'] = ucfirst($report_type) . " report submitted successfully!";
                } else {
                    $_SESSION['error_message'] = "Database error: " . mysqli_stmt_error($stmt);
                }
                mysqli_stmt_close($stmt);
            } else {
                $_SESSION['error_message'] = "Failed to save uploaded file.";
            }
        }
    }
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit();
}

// =========================================================================
// HANDLE REPORT DELETION
// =========================================================================
if (!$isHRView && isset($_POST['delete_report'])) {
    $report_id = intval($_POST['delete_report']);
    $safe_emp_id = mysqli_real_escape_string($con, $current_employee['employee_id']);
    
    $check_q = mysqli_query($con, "SELECT file_path FROM hr_employee_reports WHERE id = $report_id AND employee_id = '$safe_emp_id'");
    if ($check_q && mysqli_num_rows($check_q) > 0) {
        $row = mysqli_fetch_assoc($check_q);
        if (!empty($row['file_path']) && file_exists($row['file_path'])) {
            unlink($row['file_path']);
        }
        mysqli_query($con, "DELETE FROM hr_employee_reports WHERE id = $report_id");
        $_SESSION['success_message'] = "Report deleted successfully!";
    } else {
        $_SESSION['error_message'] = "Report not found or permission denied.";
    }
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit();
}

// =========================================================================
// HANDLE REPORT REPLACEMENT
// =========================================================================
if (!$isHRView && isset($_POST['replace_report']) && isset($_FILES['replace_file'])) {
    $report_id = intval($_POST['replace_report']);
    $safe_emp_id = mysqli_real_escape_string($con, $current_employee['employee_id']);
    
    $check_q = mysqli_query($con, "SELECT report_type, file_path FROM hr_employee_reports WHERE id = $report_id AND employee_id = '$safe_emp_id'");
    if ($check_q && mysqli_num_rows($check_q) > 0) {
        $row = mysqli_fetch_assoc($check_q);
        $old_file = $row['file_path'];
        $report_type = $row['report_type'];
        
        $file = $_FILES['replace_file'];
        $allowed  = ['pdf','doc','docx','xls','xlsx','ppt','pptx','csv','jpg','jpeg','png','zip'];
        $ext      = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        $maxSize  = 20 * 1024 * 1024;

        if ($file['error'] !== UPLOAD_ERR_OK) {
            $_SESSION['error_message'] = "File upload error.";
        } elseif (!in_array($ext, $allowed)) {
            $_SESSION['error_message'] = "File type .$ext is not allowed.";
        } elseif ($file['size'] > $maxSize) {
            $_SESSION['error_message'] = "File exceeds 20MB limit.";
        } else {
            $uploadDir = 'uploads/employee_reports/' . $current_employee['employee_id'] . '/';
            if (!file_exists($uploadDir)) mkdir($uploadDir, 0777, true);
            $newName = $report_type . '_' . time() . '_replaced_' . basename($file['name']);
            $newPath = $uploadDir . $newName;

            if (move_uploaded_file($file['tmp_name'], $newPath)) {
                if (!empty($old_file) && file_exists($old_file)) {
                    unlink($old_file);
                }
                $stmt = mysqli_prepare($con, "UPDATE hr_employee_reports SET file_path = ?, submitted_at = NOW() WHERE id = ?");
                mysqli_stmt_bind_param($stmt, "si", $newPath, $report_id);
                mysqli_stmt_execute($stmt);
                mysqli_stmt_close($stmt);
                $_SESSION['success_message'] = "Report file replaced successfully!";
            } else {
                $_SESSION['error_message'] = "Failed to save the new file.";
            }
        }
    } else {
        $_SESSION['error_message'] = "Report not found or permission denied.";
    }
    header('Location: ' . $_SERVER['PHP_SELF']);
    exit();
}

// =========================================================================
// FETCH MY SUBMISSIONS & STATS
// =========================================================================
$my_reports = [];
$stats = ['weekly' => 0, 'monthly_summary' => 0, 'monthly_calendar' => 0, 'total' => 0];

$safe_emp_id = mysqli_real_escape_string($con, $current_employee['employee_id']);
$rq = mysqli_query($con, "SELECT * FROM hr_employee_reports WHERE employee_id = '$safe_emp_id' ORDER BY submitted_at DESC");
if ($rq) {
    while ($row = mysqli_fetch_assoc($rq)) {
        $my_reports[] = $row;
        $stats['total']++;
        if ($row['report_type'] == 'weekly') $stats['weekly']++;
        if ($row['report_type'] == 'monthly_summary' || $row['report_type'] == 'monthly') $stats['monthly_summary']++;
        if ($row['report_type'] == 'monthly_calendar') $stats['monthly_calendar']++;
    }
}

// =========================================================================
// DYNAMIC REMINDERS
// =========================================================================
$friday_alert = '';
$eom_alert = '';

if (date('w') == 5 || date('w') == 6) {
    $day_name = date('w') == 5 ? "Friday" : "Saturday";
    $friday_alert = "<strong>Friendly Reminder:</strong> It's $day_name! Please ensure you create and upload your Weekly Report.";
}

$days_in_month = date('t');
$current_day = date('j');
if ($days_in_month - $current_day <= 3) {
    $eom_alert = "<strong>End of Month Reminder:</strong> Please be prepared to submit your Monthly Summary and the Monthly Calendar for the upcoming month.";
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title><?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?> | My Calendar & Reports</title>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root {
  --navy-800: #0d1f3c; --navy-600: #153060; --navy-500: #1a3a72;
  --navy-300: #2563c4; --accent: #f59e0b;
  --red-500: #ef4444; --red-100: #fee2e2; --red-800: #991b1b;
  --blue-500: #3b82f6; --blue-100: #dbeafe; --blue-800: #1e40af;
}
* { font-family: 'Outfit', sans-serif; box-sizing: border-box; }
body { background: #f0f4f8; margin: 0; }
.container-fluid { width: 100%; padding: 24px 30px; }

.page-header {
  background: linear-gradient(135deg, var(--navy-800) 0%, var(--navy-600) 100%);
  padding: 24px 30px; border-radius: 14px 14px 0 0;
  display: flex; align-items: center; justify-content: space-between; gap: 14px;
}
.ph-left { display: flex; align-items: center; gap: 14px; }
.page-header .icon { width: 50px; height: 50px; background: rgba(255,255,255,.12); border-radius: 12px;
  display: flex; align-items: center; justify-content: center; color: var(--accent); font-size: 22px; flex-shrink: 0; }
.page-header h1 { color: #fff; font-weight: 800; font-size: 20px; margin: 0; }
.page-header p { color: rgba(255,255,255,.6); font-size: 13px; margin: 2px 0 0; }

.btn-dashboard { background: rgba(255,255,255,0.1); color: #fff; padding: 8px 16px; border-radius: 8px; font-weight: 600; font-size: 13px; text-decoration: none; border: 1px solid rgba(255,255,255,0.2); transition: all 0.2s; }
.btn-dashboard:hover { background: #fff; color: var(--navy-800); text-decoration: none; }

.card-body-section { background: #fff; padding: 28px 30px; border-radius: 0 0 14px 14px; box-shadow: 0 8px 30px rgba(13,31,61,.08); margin-bottom: 24px; }

/* Summary Cards */
.summary-cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px; }
.sum-card { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 12px; padding: 16px; display: flex; align-items: center; gap: 16px; }
.sum-icon { width: 48px; height: 48px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 22px; color: #fff; }
.sum-card h2 { margin: 0 0 2px; font-size: 24px; font-weight: 800; color: #0f172a; line-height: 1; }
.sum-card p { margin: 0; font-size: 11px; font-weight: 700; color: #64748b; text-transform: uppercase; }

/* Tabs */
.tabs-wrapper { display: flex; gap: 12px; margin-bottom: 24px; }
.tab-btn {
  background: #fff; border: 1px solid #cbd5e1; color: var(--blue-500);
  border-radius: 8px; padding: 12px 24px; font-weight: 600; font-size: 14px;
  cursor: pointer; transition: all 0.2s; display: flex; align-items: center;
}
.tab-btn i { font-size: 15px; }
.tab-btn:hover { background: #f8fafc; border-color: var(--blue-500); }
.tab-btn.active { background: var(--navy-600); color: #fff; border-color: var(--navy-600); }
.tab-btn.active i { color: #fff; }

.tab-content { display: none; }
.tab-content.active { display: block; }

/* Cards Grid */
.cards-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
@media (max-width: 800px) { .cards-grid { grid-template-columns: 1fr; } }

.report-card {
  background: #fff; border: 1px solid #e2e8f0; border-radius: 12px;
  box-shadow: 0 4px 15px rgba(0,0,0,0.03); padding: 20px;
}
.rc-header { display: flex; align-items: flex-start; margin-bottom: 16px; }
.rc-icon {
  width: 48px; height: 48px; border-radius: 10px; display: flex; align-items: center;
  justify-content: center; font-size: 20px; color: #fff; flex-shrink: 0;
}
.rc-icon.red { background: var(--red-500); }
.rc-icon.blue { background: var(--blue-500); }

.rc-title-block { margin-left: 14px; flex-grow: 1; }
.rc-title-block h4 { font-size: 16px; font-weight: 800; color: #0f172a; margin: 0 0 4px; }
.rc-date-inputs { display: flex; align-items: center; gap: 6px; }
.rc-date-inputs input[type="date"] {
  font-size: 11px; padding: 4px 6px; border: 1px solid #cbd5e1; border-radius: 4px;
  color: #475569; background: #fff; outline: none; width: 105px;
}
.rc-date-inputs span { font-size: 11px; color: #64748b; font-weight: 600; }

.rc-badge {
  padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 700;
  background: var(--red-100); color: var(--red-800);
}

.rc-body { border-top: 1px dashed #cbd5e1; padding-top: 16px; }
.rc-dropzone {
  border: 2px dashed #cbd5e1; border-radius: 10px; padding: 25px 20px;
  text-align: center; position: relative; cursor: pointer; background: #f8fafc;
  transition: all 0.2s;
}
.rc-dropzone:hover, .rc-dropzone.dragover { border-color: var(--blue-500); background: #f1f5f9; }
.rc-dropzone i { font-size: 28px; color: #94a3b8; margin-bottom: 8px; }
.rc-dropzone h5 { font-size: 14px; font-weight: 700; color: #475569; margin: 0 0 4px; }
.rc-dropzone p { font-size: 11px; color: #94a3b8; margin: 0; text-transform: uppercase; font-weight: 600; }
.rc-file-input { position: absolute; inset: 0; opacity: 0; cursor: pointer; width: 100%; height: 100%; }

.file-name-display {
  font-size: 12px; font-weight: 600; color: var(--navy-600); margin-top: 8px;
  word-break: break-all; display: none;
}

.rc-notes {
  width: 100%; padding: 10px 14px; border: 1px solid #cbd5e1; border-radius: 8px;
  font-size: 13px; margin-top: 16px; color: #334155; outline: none;
}
.rc-notes:focus { border-color: var(--blue-500); }

.rc-submit {
  width: 100%; padding: 12px; border-radius: 8px; border: none; color: #fff;
  font-weight: 700; font-size: 14px; margin-top: 12px; cursor: pointer; transition: opacity 0.2s;
}
.rc-submit:hover { opacity: 0.9; }
.rc-submit.red { background: var(--red-500); }
.rc-submit.blue { background: var(--blue-500); }

/* History Table */
table.reports-table { width: 100%; border-collapse: collapse; margin-top: 6px; }
table.reports-table th { background: #f8fafc; color: #475569; padding: 12px; font-size: 12px; text-align: left; border-bottom: 2px solid #e2e8f0; }
table.reports-table td { padding: 12px; border-bottom: 1px solid #e2e8f0; font-size: 13px; color: #1e293b; vertical-align: middle; }
.badge-type { padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 700; }
.badge-weekly { background: #dbeafe; color: #1e40af; }
.badge-monthly { background: #fef3c7; color: #92400e; }
.btn-view-file { background: var(--navy-600); color: #fff; padding: 6px 14px; border-radius: 6px; font-size: 12px; font-weight: 600; text-decoration: none; display: inline-block; }
.btn-view-file:hover { background: var(--navy-800); color: #fff; text-decoration: none; }
.notes-text { font-size: 12px; color: #64748b; font-style: italic; max-width: 250px; }

.alert-box { padding: 12px 18px; border-radius: 10px; margin-bottom: 18px; font-size: 14px; font-weight: 500; }
.alert-ok { background: #d1fae5; color: #065f46; border: 1px solid #6ee7b7; }
.alert-err { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
.alert-info { background: #e0f2fe; color: #075985; border: 1px solid #bae6fd; }
.alert-warn { background: #fef3c7; color: #92400e; border: 1px solid #fde68a; }
</style>
</head>
<body>
<?php if ($isHRView) include("header.php"); ?>

<div id="content" class="<?php echo $isHRView ? 'app-content' : ''; ?>" role="main">
<div class="<?php echo $isHRView ? 'app-content-body' : ''; ?>">

<div class="container-fluid">

  <div class="page-header">
    <div class="ph-left">
      <div class="icon"><i class="fa fa-calendar-check"></i></div>
      <div>
        <h1>My Calendar & Reports</h1>
        <p><?php echo htmlspecialchars($current_employee['name']); ?> (<?php echo htmlspecialchars($current_employee['employee_id']); ?>)</p>
      </div>
    </div>
    
  </div>

  <div class="card-body-section">

    <!-- SUMMARY CARDS -->
    <div class="summary-cards">
      <div class="sum-card">
        <div class="sum-icon" style="background:#0f172a;"><i class="fas fa-folder-open"></i></div>
        <div>
          <h2><?php echo $stats['total']; ?></h2>
          <p>Total Submissions</p>
        </div>
      </div>
      <div class="sum-card">
        <div class="sum-icon" style="background:#3b82f6;"><i class="fas fa-file-alt"></i></div>
        <div>
          <h2><?php echo $stats['weekly']; ?></h2>
          <p>Weekly Reports</p>
        </div>
      </div>
      <div class="sum-card">
        <div class="sum-icon" style="background:#ef4444;"><i class="fas fa-clipboard-list"></i></div>
        <div>
          <h2><?php echo $stats['monthly_summary']; ?></h2>
          <p>Monthly Summaries</p>
        </div>
      </div>
      <div class="sum-card">
        <div class="sum-icon" style="background:#f59e0b;"><i class="fas fa-calendar-alt"></i></div>
        <div>
          <h2><?php echo $stats['monthly_calendar']; ?></h2>
          <p>Monthly Calendars</p>
        </div>
      </div>
    </div>

    <!-- REMINDERS -->
    <?php if ($friday_alert): ?>
      <div class="alert-box alert-info"><i class="fas fa-bell mr-2"></i> <?php echo $friday_alert; ?></div>
    <?php endif; ?>
    <?php if ($eom_alert): ?>
      <div class="alert-box alert-warn"><i class="fas fa-exclamation-triangle mr-2"></i> <?php echo $eom_alert; ?></div>
    <?php endif; ?>

    <?php if ($isHRView): ?>
    <div class="alert-box alert-err" style="background:#fff7ed; border:1.5px solid #fed7aa; color:#9a3412; display:flex; justify-content:space-between; align-items:center;">
      <span><i class="fas fa-eye mr-2"></i> Viewing as HR — read only</span>
      <a href="javascript:history.back()" style="color:#9a3412; font-weight:700; text-decoration:none;"><i class="fas fa-arrow-left mr-1"></i> Back</a>
    </div>
    <?php endif; ?>

    <?php if (isset($_SESSION['success_message'])): ?>
      <div class="alert-box alert-ok"><i class="fa fa-check-circle"></i> <?php echo htmlspecialchars($_SESSION['success_message']); unset($_SESSION['success_message']); ?></div>
    <?php endif; ?>
    <?php if (isset($_SESSION['error_message'])): ?>
      <div class="alert-box alert-err"><i class="fa fa-exclamation-circle"></i> <?php echo htmlspecialchars($_SESSION['error_message']); unset($_SESSION['error_message']); ?></div>
    <?php endif; ?>

    <div class="tabs-wrapper">
      <?php if (!$isHRView): ?>
      <button type="button" class="tab-btn active" id="tabUploadBtn" onclick="switchTab('upload')"><i class="fas fa-upload mr-2"></i> Upload Reports</button>
      <?php endif; ?>
      <button type="button" class="tab-btn <?php echo $isHRView ? 'active' : ''; ?>" id="tabHistoryBtn" onclick="switchTab('history')"><i class="fas fa-history mr-2"></i> My Submission History</button>
    </div>

    <?php if (!$isHRView): ?>
    <!-- UPLOAD TAB -->
    <div id="tabUpload" class="tab-content active">
      <div class="cards-grid" style="grid-template-columns: 1fr 1fr 1fr;">
        
        <!-- MONTHLY CALENDAR CARD -->
        <div class="report-card">
          <form method="POST" enctype="multipart/form-data">
            <input type="hidden" name="report_type" value="monthly_calendar">
            <div class="rc-header">
              <div class="rc-icon" style="background:#f59e0b;"><i class="fas fa-calendar-alt"></i></div>
              <div class="rc-title-block">
                <h4>Monthly Calendar</h4>
                <div class="rc-date-inputs">
                  <input type="date" name="date_from" required title="Start Date" style="width:100px;">
                  <span>to</span>
                  <input type="date" name="date_to" required title="End Date" style="width:100px;">
                </div>
              </div>
            </div>
            <div class="rc-body">
              <div class="rc-dropzone" id="dzCalendar">
                <i class="fas fa-cloud-upload-alt"></i>
                <h5>Click or drag file here</h5>
                <p>PDF DOC DOCX TXT CSV — Max 20MB</p>
                <input type="file" name="report_file" class="rc-file-input" required onchange="showFileName(this, 'fnCalendar')">
                <div id="fnCalendar" class="file-name-display"></div>
              </div>
              <input type="text" name="notes" class="rc-notes" placeholder="Optional notes...">
              <button type="submit" name="submit_report" class="rc-submit" style="background:#f59e0b;"><i class="fas fa-upload mr-2"></i> Upload Calendar</button>
            </div>
          </form>
        </div>

        <!-- MONTHLY SUMMARY CARD -->
        <div class="report-card">
          <form method="POST" enctype="multipart/form-data">
            <input type="hidden" name="report_type" value="monthly_summary">
            <div class="rc-header">
              <div class="rc-icon red"><i class="fas fa-clipboard-list"></i></div>
              <div class="rc-title-block">
                <h4>Monthly Summary</h4>
                <div class="rc-date-inputs">
                  <input type="date" name="date_from" required title="Start Date" style="width:100px;">
                  <span>to</span>
                  <input type="date" name="date_to" required title="End Date" style="width:100px;">
                </div>
              </div>
            </div>
            <div class="rc-body">
              <div class="rc-dropzone" id="dzMonthly">
                <i class="fas fa-cloud-upload-alt"></i>
                <h5>Click or drag file here</h5>
                <p>PDF DOC DOCX TXT CSV — Max 20MB</p>
                <input type="file" name="report_file" class="rc-file-input" required onchange="showFileName(this, 'fnMonthly')">
                <div id="fnMonthly" class="file-name-display"></div>
              </div>
              <input type="text" name="notes" class="rc-notes" placeholder="Optional notes...">
              <button type="submit" name="submit_report" class="rc-submit red"><i class="fas fa-upload mr-2"></i> Upload Summary</button>
            </div>
          </form>
        </div>

        <!-- WEEKLY REPORT CARD -->
        <div class="report-card">
          <form method="POST" enctype="multipart/form-data">
            <input type="hidden" name="report_type" value="weekly">
            <div class="rc-header">
              <div class="rc-icon blue"><i class="fas fa-file-alt"></i></div>
              <div class="rc-title-block">
                <h4>Weekly Report</h4>
                <div class="rc-date-inputs">
                  <input type="date" name="date_from" required title="Start Date" style="width:100px;">
                  <span>to</span>
                  <input type="date" name="date_to" required title="End Date" style="width:100px;">
                </div>
              </div>
            </div>
            <div class="rc-body">
              <div class="rc-dropzone" id="dzWeekly">
                <i class="fas fa-cloud-upload-alt"></i>
                <h5>Click or drag file here</h5>
                <p>PDF DOC DOCX TXT CSV — Max 20MB</p>
                <input type="file" name="report_file" class="rc-file-input" required onchange="showFileName(this, 'fnWeekly')">
                <div id="fnWeekly" class="file-name-display"></div>
              </div>
              <input type="text" name="notes" class="rc-notes" placeholder="Optional notes...">
              <button type="submit" name="submit_report" class="rc-submit blue"><i class="fas fa-upload mr-2"></i> Upload Weekly Report</button>
            </div>
          </form>
        </div>

      </div>
    </div>
    <?php endif; ?>

    <!-- HISTORY TAB -->
    <div id="tabHistory" class="tab-content <?php echo $isHRView ? 'active' : ''; ?>">
      <?php if (count($my_reports) > 0): ?>
      <div style="overflow-x:auto;">
        <table class="reports-table">
          <thead>
            <tr>
              <th>Type</th>
              <th>Date Range</th>
              <th>Submitted On</th>
              <th>Notes</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($my_reports as $rep): 
              $type_formatted = '';
              if ($rep['report_type'] == 'weekly') $type_formatted = 'Weekly';
              if ($rep['report_type'] == 'monthly_summary' || $rep['report_type'] == 'monthly') $type_formatted = 'M. Summary';
              if ($rep['report_type'] == 'monthly_calendar') $type_formatted = 'M. Calendar';
            ?>
            <tr>
              <td><span class="badge-type badge-<?php echo ($rep['report_type']=='monthly_summary'?'monthly':$rep['report_type']); ?>" <?php if($rep['report_type'] == 'monthly_calendar') echo 'style="background:#fef3c7;color:#d97706;"'; ?>><?php echo $type_formatted; ?></span></td>
              <td><strong><?php echo date('d M Y', strtotime($rep['date_from'])); ?></strong> <span style="color:#94a3b8;margin:0 4px;">to</span> <strong><?php echo date('d M Y', strtotime($rep['date_to'])); ?></strong></td>
              <td><?php echo date('d M Y, h:i A', strtotime($rep['submitted_at'])); ?></td>
              <td><div class="notes-text"><?php echo !empty($rep['notes']) ? htmlspecialchars($rep['notes']) : '<span style="color:#cbd5e1;">-</span>'; ?></div></td>
              <td>
  <div style="display:flex; gap:8px;">
    <?php if (!empty($rep['file_path'])): 
        $parts = explode('/', $rep['file_path']);
        $encoded_path = implode('/', array_map('rawurlencode', $parts));
    ?>
    <a href="<?php echo htmlspecialchars($encoded_path); ?>" target="_blank" class="btn-view-file" style="padding:6px 12px; background:#1e3a8a; color:#fff; border-radius:6px; font-size:12px; font-weight:600; text-decoration:none;"><i class="fas fa-external-link-alt mr-1"></i> View File</a>
    <?php else: ?>
    <span style="padding:6px 12px; background:#f1f5f9; color:#94a3b8; border-radius:6px; font-size:12px; font-weight:600;"><i class="fa fa-ban mr-1"></i>No File</span>
    <?php endif; ?>
    
    <form method="POST" enctype="multipart/form-data" style="display:inline;margin:0;">
        <input type="hidden" name="replace_report" value="<?php echo $rep['id']; ?>">
        <label class="btn btn-warning btn-sm" style="font-size:12px;font-weight:600;padding:6px 12px;border-radius:6px;cursor:pointer;margin:0;color:#fff;">
            <i class="fas fa-upload mr-1"></i> Replace
            <input type="file" name="replace_file" style="display:none;" onchange="if(confirm('Are you sure you want to replace this report file?')) this.form.submit(); else this.value='';">
        </label>
    </form>

    <form method="POST" style="display:inline;margin:0;" onsubmit="return confirm('Are you sure you want to completely delete this report? This cannot be undone.');">
        <input type="hidden" name="delete_report" value="<?php echo $rep['id']; ?>">
        <button type="submit" class="btn btn-danger btn-sm" style="font-size:12px;font-weight:600;padding:6px 12px;border-radius:6px;margin:0;"><i class="fas fa-trash-alt mr-1"></i> Delete</button>
    </form>
  </div>
</td>
            </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      <?php else: ?>
        <div style="text-align:center; padding: 40px 20px; background:#f8fafc; border-radius:12px; border:2px dashed #e2e8f0;">
          <i class="fas fa-folder-open mb-3" style="font-size:32px; color:#cbd5e1;"></i>
          <h5 style="font-weight:700; color:#475569; margin:0 0 6px;">No reports found</h5>
          <p style="color:#94a3b8; font-size:13px; margin:0;">You haven't submitted any reports yet.</p>
        </div>
      <?php endif; ?>
    </div>

  </div>
</div>

</div>
</div>

<?php if ($isHRView) include("footer.php"); ?>

<script>
function switchTab(tabId) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  
  if (tabId === 'upload') {
    document.getElementById('tabUploadBtn').classList.add('active');
    document.getElementById('tabUpload').classList.add('active');
  } else {
    document.getElementById('tabHistoryBtn').classList.add('active');
    document.getElementById('tabHistory').classList.add('active');
  }
}

function showFileName(input, displayId) {
  const display = document.getElementById(displayId);
  if (input.files && input.files.length > 0) {
    display.textContent = 'Selected: ' + input.files[0].name;
    display.style.display = 'block';
  } else {
    display.style.display = 'none';
  }
}

// Drag and drop visual feedback
document.querySelectorAll('.rc-file-input').forEach(input => {
  const dropzone = input.parentElement;
  
  input.addEventListener('dragenter', () => dropzone.classList.add('dragover'));
  input.addEventListener('dragleave', () => dropzone.classList.remove('dragover'));
  input.addEventListener('drop', () => dropzone.classList.remove('dragover'));
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
</html>l>
