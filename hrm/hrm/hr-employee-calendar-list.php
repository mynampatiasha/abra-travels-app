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

$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// AUTO-CREATE / UPDATE hr_employee_reports TABLE
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_employee_reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id VARCHAR(50) NOT NULL,
  employee_name VARCHAR(255) NOT NULL,
  report_type ENUM('weekly','monthly','monthly_summary','monthly_calendar') NOT NULL,
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  notes TEXT DEFAULT NULL,
  submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_employee (employee_id),
  INDEX idx_type (report_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$check_notes = mysqli_query($con, "SHOW COLUMNS FROM hr_employee_reports LIKE 'notes'");
if ($check_notes && mysqli_num_rows($check_notes) == 0) {
    mysqli_query($con, "ALTER TABLE hr_employee_reports ADD COLUMN notes TEXT DEFAULT NULL");
}

// =========================================================================
// IDENTIFY CURRENT HR USER (for created_by on tickets)
// =========================================================================
$current_user_name = trim($_SESSION['user_name'] ?? '');
$created_by_id = 0;
if ($current_user_name) {
    $safe_un = mysqli_real_escape_string($con, $current_user_name);
    $ur = mysqli_query($con, "SELECT id FROM hr_employees WHERE name = '$safe_un' LIMIT 1");
    if ($ur && mysqli_num_rows($ur) > 0) {
        $created_by_id = mysqli_fetch_assoc($ur)['id'];
    } else {
        $ur2 = mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$safe_un%' LIMIT 1");
        if ($ur2 && mysqli_num_rows($ur2) > 0) {
            $created_by_id = mysqli_fetch_assoc($ur2)['id'];
        }
    }
}

// =========================================================================
// HANDLE: SEND REPORT REQUEST TICKETS
// =========================================================================
if (isset($_POST['send_report_tickets'])) {
    $emp_ids       = $_POST['employee_ids'] ?? [];
    $report_type   = $_POST['report_type'] ?? '';
    $message_tpl   = $_POST['message_template'] ?? '';

    if (empty($emp_ids) || !in_array($report_type, ['weekly', 'monthly', 'both'])) {
        $_SESSION['error_message'] = "Please select employees and a report type.";
    } elseif (empty(trim($message_tpl))) {
        $_SESSION['error_message'] = "Message cannot be empty.";
    } else {
        $type_label = ($report_type == 'weekly') ? 'Weekly Report' : (($report_type == 'monthly') ? 'Monthly Report' : 'Weekly + Monthly Report');
        $created_count = 0;
        $request_date = date('Y-m-d');
        $deadline = date('Y-m-d H:i:s', strtotime('+2 days'));
        $timeline_minutes = 2880; // 2 days

        foreach ($emp_ids as $eid) {
            $eid = intval($eid);
            $er = mysqli_query($con, "SELECT id, employee_id, name FROM hr_employees WHERE id = $eid LIMIT 1");
            if (!$er || mysqli_num_rows($er) == 0) continue;
            $emp = mysqli_fetch_assoc($er);

            // Replace placeholder with employee's actual name
            $personal_message = str_replace('{EMPLOYEE_NAME}', $emp['name'], $message_tpl);
            $personal_message .= "\n\n[ReportReq:" . $emp['employee_id'] . "|" . $report_type . "|" . $request_date . "]";

            $subject = $type_label . " Submission Required - " . $emp['name'];

            $rid = mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets");
            $rrow = mysqli_fetch_assoc($rid);
            $next_id = ($rrow['max_id'] ?? 0) + 1;
            $ticket_number = 'TICKET' . date('Y') . str_pad($next_id, 4, '0', STR_PAD_LEFT);

            $safe_subject = mysqli_real_escape_string($con, $subject);
            $safe_message = mysqli_real_escape_string($con, $personal_message);
            $safe_created_by_name = mysqli_real_escape_string($con, $current_user_name ?: 'HR System');

            $insert = "INSERT INTO tickets
                (ticket_number, name, subject, message, status, priority, timeline, deadline, created_at, updated_at, assigned_to, created_by)
                VALUES
                ('$ticket_number', '$safe_created_by_name', '$safe_subject', '$safe_message', 'open', 'High', $timeline_minutes, '$deadline', NOW(), NOW(), {$emp['id']}, $created_by_id)";

            if (mysqli_query($con, $insert)) {
                $created_count++;
            }
        }

        if ($created_count > 0) {
            $_SESSION['success_message'] = "$created_count report request ticket(s) raised successfully. Deadline: " . date('d M Y H:i', strtotime($deadline));
        } else {
            $_SESSION['error_message'] = "No tickets could be created. Please try again.";
        }
    }
    header("Location: $current_page");
    exit;
}

// =========================================================================
// FETCH ALL EMPLOYEES (for Assign Tickets tab)
// =========================================================================
$employees_list = [];
$emp_q = mysqli_query($con, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE status = 'Active' ORDER BY name ASC");
if ($emp_q) {
    while ($r = mysqli_fetch_assoc($emp_q)) {
        $employees_list[] = $r;
    }
}

// Departments for filter dropdowns
$departments_list = [];
$dq = mysqli_query($con, "SELECT DISTINCT department FROM hr_employees WHERE department IS NOT NULL AND department != '' ORDER BY department ASC");
if ($dq) {
    while ($r = mysqli_fetch_assoc($dq)) {
        $departments_list[] = $r['department'];
    }
}

// =========================================================================
// FETCH ALL SUBMITTED REPORTS (existing Reports tab)
// =========================================================================
$all_reports = [];
$rq = mysqli_query($con, "SELECT * FROM hr_employee_reports ORDER BY submitted_at DESC");
if ($rq) {
    while ($row = mysqli_fetch_assoc($rq)) {
        $all_reports[] = $row;
    }
}
$employee_names = [];
foreach ($all_reports as $r) {
    $employee_names[$r['employee_name']] = true;
}

// =========================================================================
// SUBMISSION STATUS — OPTION B
// Only employees with an OPEN report-request ticket (tagged [ReportReq:...])
// created today or yesterday are checked against hr_employee_reports.
// =========================================================================
$report_status_list = [];
$yesterday_start = date('Y-m-d 00:00:00', strtotime('-1 day'));

$tq = mysqli_query($con, "
    SELECT id, ticket_number, message, status, assigned_to, created_at, deadline
    FROM tickets
    WHERE message LIKE '%[ReportReq:%'
    AND status NOT IN ('closed', 'resolved')
    AND created_at >= '$yesterday_start'
    ORDER BY created_at DESC
");

if ($tq) {
    while ($t = mysqli_fetch_assoc($tq)) {
        if (preg_match('/\[ReportReq:([^\|]+)\|([^\|]+)\|([^\]]+)\]/', $t['message'], $m)) {
            $req_emp_id   = $m[1];
            $req_type     = $m[2]; // weekly | monthly | both
            $req_date     = $m[3];

            $safe_eid = mysqli_real_escape_string($con, $req_emp_id);
            $eq = mysqli_query($con, "SELECT id, employee_id, name, department FROM hr_employees WHERE employee_id = '$safe_eid' LIMIT 1");
            if (!$eq || mysqli_num_rows($eq) == 0) continue;
            $emp = mysqli_fetch_assoc($eq);

            // Determine which report categories are required
            $needs_weekly  = ($req_type == 'weekly' || $req_type == 'both');
            $needs_monthly = ($req_type == 'monthly' || $req_type == 'both');

            $weekly_ok = true;
            $monthly_ok = true;

            if ($needs_weekly) {
                $wq = mysqli_query($con, "SELECT id FROM hr_employee_reports
                    WHERE employee_id = '$safe_eid' AND report_type = 'weekly'
                    AND submitted_at >= '{$t['created_at']}' LIMIT 1");
                $weekly_ok = ($wq && mysqli_num_rows($wq) > 0);
            }
            if ($needs_monthly) {
                $mq = mysqli_query($con, "SELECT id FROM hr_employee_reports
                    WHERE employee_id = '$safe_eid'
                    AND report_type IN ('monthly','monthly_summary','monthly_calendar')
                    AND submitted_at >= '{$t['created_at']}' LIMIT 1");
                $monthly_ok = ($mq && mysqli_num_rows($mq) > 0);
            }

            $submitted = ($needs_weekly ? $weekly_ok : true) && ($needs_monthly ? $monthly_ok : true);

            $report_status_list[] = [
                'ticket_number' => $t['ticket_number'],
                'employee_id'   => $emp['employee_id'],
                'employee_name' => $emp['name'],
                'department'    => $emp['department'],
                'report_type'   => $req_type,
                'requested_on'  => $t['created_at'],
                'deadline'      => $t['deadline'],
                'submitted'     => $submitted
            ];
        }
    }
}

$submitted_list     = array_filter($report_status_list, fn($r) => $r['submitted']);
$not_submitted_list = array_filter($report_status_list, fn($r) => !$r['submitted']);

// =========================================================================
// FETCH MISSING WEEKLY REPORTS
// =========================================================================
$missing_weekly_reports = [];
$week_start = date('Y-m-d 00:00:00', strtotime('monday this week'));
$week_end   = date('Y-m-d 23:59:59', strtotime('sunday this week'));

$all_emp_q = mysqli_query($con, "SELECT * FROM hr_employees WHERE status = 'Active' OR status = 'active' ORDER BY name ASC");
$missing_weekly_reports = [];
$missing_monthly_reports = [];

$all_emp_q = mysqli_query($con, "SELECT * FROM hr_employees WHERE status = 'Active' OR status = 'active' ORDER BY name ASC");

if ($all_emp_q) {
    while ($emp = mysqli_fetch_assoc($all_emp_q)) {
        $emp_id_safe = mysqli_real_escape_string($con, $emp['employee_id']);
        
        // Check Weekly (ensure the report's date_to is within this week)
        $week_start_date = date('Y-m-d', strtotime('monday this week'));
        $chk_w = mysqli_query($con, "SELECT id FROM hr_employee_reports WHERE employee_id = '$emp_id_safe' AND report_type = 'weekly' AND date_to >= '$week_start_date' LIMIT 1");
        if (!$chk_w || mysqli_num_rows($chk_w) == 0) {
            $missing_weekly_reports[] = $emp;
        }

        // Check Monthly (ensure the report's date_to is within this month)
        $month_start_date = date('Y-m-01');
        $chk_m = mysqli_query($con, "SELECT id FROM hr_employee_reports WHERE employee_id = '$emp_id_safe' AND report_type IN ('monthly', 'monthly_summary', 'monthly_calendar') AND date_to >= '$month_start_date' LIMIT 1");
        if (!$chk_m || mysqli_num_rows($chk_m) == 0) {
            $missing_monthly_reports[] = $emp;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title><?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?> | All Employee Calendars & Reports</title>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root { --navy-800: #0d1f3c; --navy-600: #153060; --navy-500: #1a3a72; --navy-300: #2563c4; --green: #10b981; --red: #ef4444; --amber: #f59e0b; }
* { font-family: 'Outfit', sans-serif; box-sizing: border-box; }
body { background: #f0f4f8; }
.container-fluid { max-width: 1400px; margin: 0 auto; padding: 24px 20px; }

.page-header {
  background: linear-gradient(135deg, var(--navy-800) 0%, var(--navy-600) 100%);
  padding: 24px 30px; border-radius: 14px 14px 0 0;
  display: flex; align-items: center; gap: 14px;
}
.page-header .icon { width: 50px; height: 50px; background: rgba(255,255,255,.12); border-radius: 12px;
  display: flex; align-items: center; justify-content: center; color: #f59e0b; font-size: 22px; flex-shrink: 0; }
.page-header h1 { color: #fff; font-weight: 800; font-size: 20px; margin: 0; }
.page-header p { color: rgba(255,255,255,.6); font-size: 13px; margin: 2px 0 0; }

.card-body-section { background: #fff; padding: 26px 30px; border-radius: 0 0 14px 14px; box-shadow: 0 8px 30px rgba(13,31,61,.08); }

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
.status-badge {
    display:inline-block; padding:5px 13px; border-radius:20px;
    font-size:12px; font-weight:700; color:#fff;
    white-space:nowrap;
}

/* Tabs */
.tabs-wrapper { display: flex; gap: 12px; margin-bottom: 22px; flex-wrap: wrap; }
.tab-btn {
  background: #fff; border: 1.5px solid #cbd5e1; color: var(--navy-300);
  border-radius: 8px; padding: 12px 22px; font-weight: 700; font-size: 14px;
  cursor: pointer; transition: all 0.2s; display: flex; align-items: center; gap: 8px;
}
.tab-btn:hover { background: #f8fafc; border-color: var(--navy-300); }
.tab-btn.active { background: var(--navy-600); color: #fff; border-color: var(--navy-600); }
.tab-content { display: none; }
.tab-content.active { display: block; }

.alert-box { padding: 12px 18px; border-radius: 10px; margin-bottom: 18px; font-size: 14px; font-weight: 500; }
.alert-ok { background: #d1fae5; color: #065f46; border: 1px solid #6ee7b7; }
.alert-err { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }

/* Filter bar (shared) */
.filter-row { display: flex; gap: 12px; margin-bottom: 18px; flex-wrap: wrap; align-items: center; }
.filter-row select, .filter-row input { padding: 9px 14px; border: 2px solid #cbd5e1; border-radius: 8px; font-size: 13px; min-width: 180px; }

/* Summary mini cards */
.mini-summary { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 22px; }
.mini-card { border-radius: 12px; padding: 16px 20px; display: flex; align-items: center; gap: 14px; }
.mini-card.ok { background: #ecfdf5; border: 1.5px solid #6ee7b7; }
.mini-card.bad { background: #fef2f2; border: 1.5px solid #fca5a5; }
.mini-card .num { font-size: 26px; font-weight: 800; }
.mini-card.ok .num { color: #065f46; }
.mini-card.bad .num { color: #991b1b; }
.mini-card .lbl { font-size: 12px; font-weight: 700; text-transform: uppercase; color: #475569; }
.mini-names { font-size: 12px; color: #475569; margin-top: 4px; max-height: 60px; overflow-y: auto; }

table.reports-table { width: 100%; border-collapse: collapse; }
table.reports-table th { background: var(--navy-600); color: #fff; padding: 10px 12px; font-size: 12px; text-align: left; white-space: nowrap; }
table.reports-table td { padding: 10px 12px; border-bottom: 1px solid #e2e8f0; font-size: 13px; color: #1e293b; }
table.reports-table tbody tr:hover { background: #f1f5f9; }
.badge-type { padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 700; }
.badge-weekly { background: #dbeafe; color: #1e40af; }
.badge-monthly, .badge-monthly_summary, .badge-monthly_calendar { background: #fef3c7; color: #92400e; }
.badge-both { background: #ede9fe; color: #5b21b6; }
.badge-submitted { background: #d1fae5; color: #065f46; }
.badge-pending { background: #fee2e2; color: #991b1b; }
.btn-view-file { background: #10b981; color: #fff; padding: 5px 12px; border-radius: 6px; font-size: 12px; font-weight: 600; text-decoration: none; }
.btn-view-file:hover { background: #059669; color: #fff; text-decoration: none; }

/* Assign tickets tab */
.assign-grid { display: grid; grid-template-columns: 380px 1fr; gap: 24px; }
@media (max-width: 900px) { .assign-grid { grid-template-columns: 1fr; } }

.emp-select-box { border: 1.5px solid #e2e8f0; border-radius: 12px; padding: 16px; background: #f8fafc; max-height: 520px; overflow-y: auto; }
.emp-select-box .search-input { width: 100%; padding: 9px 12px; border: 2px solid #cbd5e1; border-radius: 8px; margin-bottom: 10px; font-size: 13px; }
.emp-row { display: flex; align-items: center; gap: 10px; padding: 8px 6px; border-radius: 6px; cursor: pointer; }
.emp-row:hover { background: #e2e8f0; }
.emp-row label { margin: 0; font-size: 13px; color: #1e293b; cursor: pointer; flex: 1; }
.emp-row small { color: #64748b; display: block; font-size: 11px; }
.select-all-row { display: flex; align-items: center; gap: 10px; padding: 8px 6px; border-bottom: 1.5px solid #cbd5e1; margin-bottom: 6px; font-weight: 700; }

.right-panel { display: flex; flex-direction: column; gap: 16px; }
.field-block label { font-weight: 700; font-size: 13px; color: #112347; margin-bottom: 6px; display: block; }
.field-block select { width: 100%; padding: 12px 14px; border: 2px solid #cbd5e1; border-radius: 8px; font-size: 14px; }
.field-block textarea { width: 100%; min-height: 220px; padding: 14px; border: 2px solid #cbd5e1; border-radius: 10px; font-size: 13px; font-family: monospace; line-height: 1.6; }
.field-block textarea:focus, .field-block select:focus { outline: none; border-color: var(--navy-300); }

.selected-count { font-size: 13px; font-weight: 700; color: var(--navy-500); margin-bottom: 8px; }

.btn-send-tickets {
  background: linear-gradient(135deg, var(--navy-500), var(--navy-300));
  color: #fff; border: none; padding: 14px; border-radius: 10px;
  font-weight: 700; font-size: 15px; cursor: pointer; width: 100%;
}
.btn-send-tickets:hover { opacity: 0.92; }
</style>
</head>
<body>

<div class="container-fluid">

  <div class="page-header">
    <div class="icon"><i class="fa fa-users"></i></div>
    <div style="flex:1;">
      <h1>All Employee Calendars & Reports</h1>
      <p>Weekly and monthly submissions, report requests, and tracking across all employees</p>
    </div>
    
  </div>

  <div class="card-body-section">

    <!-- Upcoming Alert Banners -->
    <div style="display: flex; flex-direction: column; gap: 14px; margin-bottom: 22px; margin-top: -10px;">
        <!-- Weekly Missing -->
        <?php if (!empty($missing_weekly_reports)): ?>
        <div class="alert-banner" onclick="$('#alertModalWeekly').modal('show')" style="background: linear-gradient(135deg, #ef4444, #dc2626); box-shadow: 0 4px 14px rgba(239, 68, 68, .35); margin-bottom: 0;">
            <i class="fas fa-exclamation-triangle"></i>
            <span><?php echo count($missing_weekly_reports); ?> employee<?php echo count($missing_weekly_reports) > 1 ? 's are' : ' is'; ?> missing their weekly report for this week</span>
            <span class="count-pill"><?php echo count($missing_weekly_reports); ?> pending</span>
            <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
        </div>
        <?php endif; ?>

        <!-- Monthly Missing -->
        <?php if (!empty($missing_monthly_reports)): ?>
        <div class="alert-banner" onclick="$('#alertModalMonthly').modal('show')" style="background: linear-gradient(135deg, #f59e0b, #d97706); box-shadow: 0 4px 14px rgba(245, 158, 11, .35); margin-bottom: 0;">
            <i class="fas fa-calendar-times"></i>
            <span><?php echo count($missing_monthly_reports); ?> employee<?php echo count($missing_monthly_reports) > 1 ? 's are' : ' is'; ?> missing their monthly report for this month</span>
            <span class="count-pill"><?php echo count($missing_monthly_reports); ?> pending</span>
            <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
        </div>
        <?php endif; ?>
    </div>

    <?php if (isset($_SESSION['success_message'])): ?>
      <div class="alert-box alert-ok"><i class="fa fa-check-circle"></i> <?php echo htmlspecialchars($_SESSION['success_message']); unset($_SESSION['success_message']); ?></div>
    <?php endif; ?>
    <?php if (isset($_SESSION['error_message'])): ?>
      <div class="alert-box alert-err"><i class="fa fa-exclamation-circle"></i> <?php echo htmlspecialchars($_SESSION['error_message']); unset($_SESSION['error_message']); ?></div>
    <?php endif; ?>

    <!-- TABS -->
    <div class="tabs-wrapper">
      <button type="button" class="tab-btn active" onclick="switchTab('reports')"><i class="fas fa-table"></i> All Reports</button>
      <button type="button" class="tab-btn" onclick="switchTab('assign')"><i class="fas fa-paper-plane"></i> Assign Report Tickets</button>
      <!--<button type="button" class="tab-btn" onclick="switchTab('status')"><i class="fas fa-list-check"></i> Submission Status</button>-->
    </div>

    <!-- ===================== TAB 1: ALL REPORTS ===================== -->
    <div id="tab-reports" class="tab-content active">



      <div class="filter-row">
        <input type="text" id="searchBox" placeholder="Search by employee name...">
        <select id="typeFilter">
          <option value="">All Types</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
          <option value="monthly_summary">Monthly Summary</option>
          <option value="monthly_calendar">Monthly Calendar</option>
        </select>
        <select id="employeeFilter">
          <option value="">All Employees</option>
          <?php foreach ($employee_names as $name => $v): ?>
            <option value="<?php echo htmlspecialchars($name); ?>"><?php echo htmlspecialchars($name); ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <table class="reports-table" id="reportsTable">
        <thead>
          <tr><th>Employee</th><th>Emp ID</th><th>Type</th><th>Date Range</th><th>Submitted On</th><th>File</th></tr>
        </thead>
        <tbody>
          <?php if (count($all_reports) > 0): ?>
            <?php foreach ($all_reports as $rep): ?>
            <tr data-type="<?php echo $rep['report_type']; ?>" data-employee="<?php echo htmlspecialchars($rep['employee_name']); ?>">
              <td><?php echo htmlspecialchars($rep['employee_name']); ?></td>
              <td><?php echo htmlspecialchars($rep['employee_id']); ?></td>
              <td><span class="badge-type badge-<?php echo $rep['report_type']; ?>"><?php echo ucfirst(str_replace('_', ' ', $rep['report_type'])); ?></span></td>
              <td><?php echo date('d M Y', strtotime($rep['date_from'])); ?> &mdash; <?php echo date('d M Y', strtotime($rep['date_to'])); ?></td>
              <td><?php echo date('d M Y, H:i', strtotime($rep['submitted_at'])); ?></td>
              <td>
<?php if (!empty($rep['file_path'])): 
    // Fix spaces in file names by encoding the path parts
    $parts = explode('/', $rep['file_path']);
    $encoded_path = implode('/', array_map('rawurlencode', $parts));
?>
    <a href="<?php echo htmlspecialchars($encoded_path); ?>" target="_blank" class="btn-view-file"><i class="fa fa-eye"></i> View</a>
<?php else: ?>
    <span style="color:#94a3b8;font-size:12px;font-style:italic;display:inline-block;padding:5px 12px;background:#f1f5f9;border-radius:6px;"><i class="fa fa-ban mr-1"></i>No File</span>
<?php endif; ?>
</td>
            </tr>
            <?php endforeach; ?>
          <?php else: ?>
            <tr><td colspan="6" style="text-align:center; color:#94a3b8; padding:30px;">No reports submitted yet by any employee.</td></tr>
          <?php endif; ?>
        </tbody>
      </table>
    </div>

    <!-- ===================== TAB 2: ASSIGN REPORT TICKETS ===================== -->
    <div id="tab-assign" class="tab-content">
      <form method="POST" id="assignTicketsForm" onsubmit="return confirmSendTickets();">

        <div class="filter-row">
          <select id="empDeptFilter" onchange="filterEmployeeList()">
            <option value="">All Departments</option>
            <?php foreach ($departments_list as $d): ?>
              <option value="<?php echo htmlspecialchars($d); ?>"><?php echo htmlspecialchars($d); ?></option>
            <?php endforeach; ?>
          </select>
        </div>

        <div class="assign-grid">

          <!-- LEFT: Employee multi-select -->
          <div>
            <div class="emp-select-box">
              <input type="text" class="search-input" id="empSearchInput" placeholder="Search employee by name or ID..." onkeyup="filterEmployeeList()">
              <div class="select-all-row">
                <input type="checkbox" id="selectAllEmp" onclick="toggleSelectAllEmp(this)">
                <label for="selectAllEmp" style="cursor:pointer;">Select All Employees</label>
              </div>
              <div id="empListContainer">
                <?php foreach ($employees_list as $emp): ?>
                  <div class="emp-row" data-name="<?php echo htmlspecialchars(strtolower($emp['name'])); ?>" data-empid="<?php echo htmlspecialchars(strtolower($emp['employee_id'])); ?>" data-dept="<?php echo htmlspecialchars($emp['department']); ?>">
                    <input type="checkbox" name="employee_ids[]" value="<?php echo $emp['id']; ?>" class="emp-checkbox">
                    <label>
                      <?php echo htmlspecialchars($emp['name']); ?>
                      <small><?php echo htmlspecialchars($emp['employee_id']); ?> &middot; <?php echo htmlspecialchars($emp['department']); ?> &middot; <?php echo htmlspecialchars($emp['position']); ?></small>
                    </label>
                  </div>
                <?php endforeach; ?>
              </div>
            </div>
            <div class="selected-count" id="selectedCount" style="margin-top:10px;">0 employee(s) selected</div>
          </div>

          <!-- RIGHT: Report type + message preview -->
          <div class="right-panel">
            <div class="field-block">
              <label>Report Type <span style="color:#ef4444;">*</span></label>
              <select name="report_type" id="reportTypeSelect" onchange="updateMessageTemplate()" required>
                <option value="">Select Report Type</option>
                <option value="weekly">Weekly Report</option>
                <option value="monthly">Monthly Report</option>
                <option value="both">Weekly + Monthly Report</option>
              </select>
            </div>

            <div class="field-block">
              <label>Message Preview (Editable) <span style="color:#ef4444;">*</span></label>
              <textarea name="message_template" id="messageTemplate" placeholder="Select a report type above to load the default message..."></textarea>
              <small style="color:#64748b;">Use <code>{EMPLOYEE_NAME}</code> as a placeholder — it will be replaced with each employee's own name automatically.</small>
            </div>

            <button type="submit" name="send_report_tickets" class="btn-send-tickets">
              <i class="fas fa-paper-plane"></i> Send Ticket Request
            </button>
          </div>

        </div>
      </form>
    </div>

    <!-- ===================== TAB 3: SUBMISSION STATUS ===================== -->
    <div id="tab-status" class="tab-content">

      <div class="filter-row">
        <input type="text" id="statusSearchBox" placeholder="Search by employee name...">
        <select id="statusTypeFilter">
          <option value="">All Types</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
          <option value="both">Weekly + Monthly</option>
        </select>
        <select id="statusFilter">
          <option value="">All (Submitted + Not Submitted)</option>
          <option value="submitted">Submitted Only</option>
          <option value="pending">Not Submitted Only</option>
        </select>
      </div>

      <table class="reports-table" id="statusTable">
        <thead>
          <tr><th>Employee</th><th>Emp ID</th><th>Department</th><th>Requested Type</th><th>Requested On</th><th>Deadline</th><th>Status</th></tr>
        </thead>
        <tbody>
          <?php if (count($report_status_list) > 0): ?>
            <?php foreach ($report_status_list as $rs): ?>
            <tr data-status="<?php echo $rs['submitted'] ? 'submitted' : 'pending'; ?>" data-type="<?php echo $rs['report_type']; ?>" data-employee="<?php echo htmlspecialchars($rs['employee_name']); ?>">
              <td><?php echo htmlspecialchars($rs['employee_name']); ?></td>
              <td><?php echo htmlspecialchars($rs['employee_id']); ?></td>
              <td><?php echo htmlspecialchars($rs['department']); ?></td>
              <td><span class="badge-type badge-<?php echo $rs['report_type']; ?>"><?php echo $rs['report_type'] == 'both' ? 'Weekly + Monthly' : ucfirst($rs['report_type']); ?></span></td>
              <td><?php echo date('d M Y, H:i', strtotime($rs['requested_on'])); ?></td>
              <td><?php echo date('d M Y, H:i', strtotime($rs['deadline'])); ?></td>
              <td><span class="badge-type <?php echo $rs['submitted'] ? 'badge-submitted' : 'badge-pending'; ?>"><?php echo $rs['submitted'] ? 'Submitted' : 'Not Submitted'; ?></span></td>
            </tr>
            <?php endforeach; ?>
          <?php else: ?>
            <tr><td colspan="7" style="text-align:center; color:#94a3b8; padding:30px;">No active report-request tickets in the last 2 days.</td></tr>
          <?php endif; ?>
        </tbody>
      </table>
    </div>

  </div>
</div>

<script>
// ── Tab switching ──────────────────────────────────────────
function switchTab(tab) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.querySelector('.tab-btn[onclick="switchTab(\'' + tab + '\')"]').classList.add('active');
  document.getElementById('tab-' + tab).classList.add('active');
}

// ── TAB 1: All Reports filters ────────────────────────────
function applyReportFilters() {
  var search = document.getElementById('searchBox').value.toLowerCase();
  var type = document.getElementById('typeFilter').value;
  var emp = document.getElementById('employeeFilter').value;
  document.querySelectorAll('#reportsTable tbody tr').forEach(function(row) {
    var rowType = row.getAttribute('data-type') || '';
    var rowEmp = row.getAttribute('data-employee') || '';
    var matchesSearch = rowEmp.toLowerCase().includes(search);
    var matchesType = !type || rowType === type;
    var matchesEmp = !emp || rowEmp === emp;
    row.style.display = (matchesSearch && matchesType && matchesEmp) ? '' : 'none';
  });
}
document.getElementById('searchBox').addEventListener('keyup', applyReportFilters);
document.getElementById('typeFilter').addEventListener('change', applyReportFilters);
document.getElementById('employeeFilter').addEventListener('change', applyReportFilters);

// ── TAB 2: Employee multi-select ──────────────────────────
function filterEmployeeList() {
  var search = document.getElementById('empSearchInput').value.toLowerCase();
  var dept = document.getElementById('empDeptFilter').value;
  document.querySelectorAll('#empListContainer .emp-row').forEach(function(row) {
    var name = row.getAttribute('data-name');
    var empid = row.getAttribute('data-empid');
    var rdept = row.getAttribute('data-dept');
    var matchesSearch = name.includes(search) || empid.includes(search);
    var matchesDept = !dept || rdept === dept;
    row.style.display = (matchesSearch && matchesDept) ? '' : 'none';
  });
}

function toggleSelectAllEmp(box) {
  document.querySelectorAll('#empListContainer .emp-row').forEach(function(row) {
    if (row.style.display !== 'none') {
      row.querySelector('.emp-checkbox').checked = box.checked;
    }
  });
  updateSelectedCount();
}

document.getElementById('empListContainer').addEventListener('change', updateSelectedCount);
function updateSelectedCount() {
  var n = document.querySelectorAll('.emp-checkbox:checked').length;
  document.getElementById('selectedCount').textContent = n + ' employee(s) selected';
}

// ── TAB 2: Message templates per report type ──────────────
var templates = {
  weekly: "Dear {EMPLOYEE_NAME},\n\nYou are requested to submit your Weekly Report within the next 2 days through the Employee Portal (My Calendar & Reports section).\n\nPlease ensure timely submission.\n\nThank you,\nHR Team",
  monthly: "Dear {EMPLOYEE_NAME},\n\nYou are requested to submit your Monthly Report within the next 2 days through the Employee Portal (My Calendar & Reports section).\n\nPlease ensure timely submission.\n\nThank you,\nHR Team",
  both: "Dear {EMPLOYEE_NAME},\n\nYou are requested to submit both your Weekly Report and Monthly Report within the next 2 days through the Employee Portal (My Calendar & Reports section).\n\nPlease ensure timely submission.\n\nThank you,\nHR Team"
};
function updateMessageTemplate() {
  var type = document.getElementById('reportTypeSelect').value;
  document.getElementById('messageTemplate').value = templates[type] || '';
}

function confirmSendTickets() {
  var n = document.querySelectorAll('.emp-checkbox:checked').length;
  var type = document.getElementById('reportTypeSelect').value;
  var msg = document.getElementById('messageTemplate').value.trim();
  if (n === 0) { alert('Please select at least one employee.'); return false; }
  if (!type) { alert('Please select a report type.'); return false; }
  if (!msg) { alert('Message cannot be empty.'); return false; }
  return confirm('Raise report request ticket(s) to ' + n + ' employee(s)? This cannot be undone.');
}

// ── TAB 3: Submission Status filters ──────────────────────
function applyStatusFilters() {
  var search = document.getElementById('statusSearchBox').value.toLowerCase();
  var type = document.getElementById('statusTypeFilter').value;
  var status = document.getElementById('statusFilter').value;
  document.querySelectorAll('#statusTable tbody tr').forEach(function(row) {
    var rowEmp = (row.getAttribute('data-employee') || '').toLowerCase();
    var rowType = row.getAttribute('data-type') || '';
    var rowStatus = row.getAttribute('data-status') || '';
    var matchesSearch = rowEmp.includes(search);
    var matchesType = !type || rowType === type;
    var matchesStatus = !status || rowStatus === status;
    row.style.display = (matchesSearch && matchesType && matchesStatus) ? '' : 'none';
  });
}
document.getElementById('statusSearchBox').addEventListener('keyup', applyStatusFilters);
document.getElementById('statusTypeFilter').addEventListener('change', applyStatusFilters);
document.getElementById('statusFilter').addEventListener('change', applyStatusFilters);

// Show alert modal if clicked
// Includes bootstrap functionality automatically since we included bootstrap js

</script>

<!-- =====================================================================
     MODAL: ALERT — Missing Weekly Reports
===================================================================== -->
<div class="modal fade" id="alertModalWeekly" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content" style="border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,.18);">
    <div class="modal-header" style="background:linear-gradient(135deg,#ef4444,#dc2626); color:#fff; border-radius:14px 14px 0 0; padding:20px 26px; border-bottom:none;">
        <h5 class="modal-title" style="font-weight:700; font-size:1.1rem;"><i class="fas fa-exclamation-triangle mr-2"></i>Missing Weekly Reports</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9; text-shadow:none; font-size:24px;">&times;</button>
    </div>
    <div class="modal-body" style="padding:26px;">
        <?php if (empty($missing_weekly_reports)): ?>
            <div style="text-align:center;padding:40px;color:#64748b;">
                <i class="fas fa-check-circle fa-3x" style="margin-bottom:14px;opacity:.3; color:#10b981;"></i>
                <p>All active employees have submitted their weekly reports for this week.</p>
            </div>
        <?php else: ?>
            <div style="margin-bottom:14px;background:#fef2f2;border-radius:10px;padding:12px 16px;border-left:4px solid #ef4444;font-size:13px;color:#991b1b;">
                <i class="fas fa-info-circle mr-1"></i>
                The following active employees have <strong>not</strong> submitted a weekly report for the current week.
            </div>
            <?php foreach ($missing_weekly_reports as $emp): ?>
            <div style="background:#f8fafc;border-radius:12px;padding:16px;margin-bottom:14px;border-left:4px solid #ef4444;display:flex;justify-content:space-between;align-items:flex-start;gap:14px;">
                <div>
                    <div style="font-weight:700;font-size:15px;color:#1e3a8a;"><?php echo htmlspecialchars($emp['name']); ?> <span style="font-size:12px;color:#64748b;font-weight:500;">(<?php echo htmlspecialchars($emp['employee_id']); ?>)</span></div>
                    <div style="font-size:12px;color:#64748b;margin-top:3px;">
                        <i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($emp['department'] ?? 'N/A'); ?>
                        &nbsp;|&nbsp;<i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($emp['position'] ?? 'N/A'); ?>
                        <?php if(!empty($emp['phone'])): ?>
                            &nbsp;|&nbsp;<i class="fas fa-phone mr-1"></i><?php echo htmlspecialchars($emp['phone']); ?>
                        <?php endif; ?>
                    </div>
                </div>
                <div style="text-align:right;flex-shrink:0;">
                    <span class="status-badge" style="background:#ef4444;margin-bottom:7px;display:inline-block;">Not Submitted</span><br>
                    <?php if(!empty($emp['phone'])): 
                        $wa_msg = urlencode("Hello " . $emp['name'] . ", please submit your weekly report for this week on the HR Portal.");
                    ?>
                    <a href="https://wa.me/<?php echo preg_replace('/[^0-9]/', '', $emp['phone']); ?>?text=<?php echo $wa_msg; ?>" target="_blank" class="btn btn-sm btn-success" style="font-size:11px;font-weight:600;padding:4px 10px;border-radius:6px;">
                        <i class="fab fa-whatsapp mr-1"></i>Remind
                    </a>
                    <?php endif; ?>
                </div>
            </div>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>
    <div class="modal-footer" style="padding:16px 26px; border-top:2px solid #e2e8f0;">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: ALERT — Missing Monthly Reports
===================================================================== -->
<div class="modal fade" id="alertModalMonthly" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content" style="border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,.18);">
    <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706); color:#fff; border-radius:14px 14px 0 0; padding:20px 26px; border-bottom:none;">
        <h5 class="modal-title" style="font-weight:700; font-size:1.1rem;"><i class="fas fa-calendar-times mr-2"></i>Missing Monthly Reports</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9; text-shadow:none; font-size:24px;">&times;</button>
    </div>
    <div class="modal-body" style="padding:26px;">
        <?php if (empty($missing_monthly_reports)): ?>
            <div style="text-align:center;padding:40px;color:#64748b;">
                <i class="fas fa-check-circle fa-3x" style="margin-bottom:14px;opacity:.3; color:#10b981;"></i>
                <p>All active employees have submitted their monthly reports for this month.</p>
            </div>
        <?php else: ?>
            <div style="margin-bottom:14px;background:#fffbeb;border-radius:10px;padding:12px 16px;border-left:4px solid #f59e0b;font-size:13px;color:#b45309;">
                <i class="fas fa-info-circle mr-1"></i>
                The following active employees have <strong>not</strong> submitted a monthly report for the current month.
            </div>
            <?php foreach ($missing_monthly_reports as $emp): ?>
            <div style="background:#f8fafc;border-radius:12px;padding:16px;margin-bottom:14px;border-left:4px solid #f59e0b;display:flex;justify-content:space-between;align-items:flex-start;gap:14px;">
                <div>
                    <div style="font-weight:700;font-size:15px;color:#1e3a8a;"><?php echo htmlspecialchars($emp['name']); ?> <span style="font-size:12px;color:#64748b;font-weight:500;">(<?php echo htmlspecialchars($emp['employee_id']); ?>)</span></div>
                    <div style="font-size:12px;color:#64748b;margin-top:3px;">
                        <i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($emp['department'] ?? 'N/A'); ?>
                        &nbsp;|&nbsp;<i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($emp['position'] ?? 'N/A'); ?>
                        <?php if(!empty($emp['phone'])): ?>
                            &nbsp;|&nbsp;<i class="fas fa-phone mr-1"></i><?php echo htmlspecialchars($emp['phone']); ?>
                        <?php endif; ?>
                    </div>
                </div>
                <div style="text-align:right;flex-shrink:0;">
                    <span class="status-badge" style="background:#f59e0b;margin-bottom:7px;display:inline-block;">Not Submitted</span><br>
                    <?php if(!empty($emp['phone'])): 
                        $wa_msg = urlencode("Hello " . $emp['name'] . ", please submit your monthly report for this month on the HR Portal.");
                    ?>
                    <a href="https://wa.me/<?php echo preg_replace('/[^0-9]/', '', $emp['phone']); ?>?text=<?php echo $wa_msg; ?>" target="_blank" class="btn btn-sm btn-success" style="font-size:11px;font-weight:600;padding:4px 10px;border-radius:6px;">
                        <i class="fab fa-whatsapp mr-1"></i>Remind
                    </a>
                    <?php endif; ?>
                </div>
            </div>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>
    <div class="modal-footer" style="padding:16px 26px; border-top:2px solid #e2e8f0;">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- Add jQuery and Bootstrap JS for modal functionality -->
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