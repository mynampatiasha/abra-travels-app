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
if (!$con) die("Database connection failed: " . mysqli_connect_error());
mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// AUTO-CREATE / MIGRATE TABLE
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_daily_planner (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id VARCHAR(50) NOT NULL,
    employee_name VARCHAR(255) NOT NULL,
    plan_date DATE NOT NULL,
    priorities JSON DEFAULT NULL,
    todo_notes TEXT DEFAULT NULL,
    if_have_time TEXT DEFAULT NULL,
    focus_notes TEXT DEFAULT NULL,
    goals_notes TEXT DEFAULT NULL,
    schedule_slots JSON DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_emp_date (employee_id, plan_date),
    INDEX idx_employee_id (employee_id),
    INDEX idx_plan_date (plan_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

function ensureColumn($con, $table, $col, $defSql) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM $table LIKE '$col'");
    if ($chk && mysqli_num_rows($chk) == 0) {
        mysqli_query($con, "ALTER TABLE $table ADD COLUMN $defSql");
    }
}
ensureColumn($con, 'hr_daily_planner', 'priorities', "priorities JSON DEFAULT NULL AFTER plan_date");
ensureColumn($con, 'hr_daily_planner', 'schedule_slots', "schedule_slots JSON DEFAULT NULL AFTER goals_notes");
ensureColumn($con, 'hr_daily_planner', 'approval_status', "approval_status ENUM('pending','approved','declined') NOT NULL DEFAULT 'pending'");
ensureColumn($con, 'hr_daily_planner', 'approval_reason', "approval_reason TEXT DEFAULT NULL");
ensureColumn($con, 'hr_daily_planner', 'approved_by', "approved_by VARCHAR(255) DEFAULT NULL");
ensureColumn($con, 'hr_daily_planner', 'approved_at', "approved_at DATETIME DEFAULT NULL");

// =========================================================================
// IDENTIFY LOGGED-IN HR/ADMIN
// =========================================================================
$hr_session_name = trim($_SESSION['user_name'] ?? 'HR Admin');
$hr_emp_pk = 0; // hr_employees.id of the logged-in HR/admin (for ticket created_by)
$safe_hr_name = mysqli_real_escape_string($con, $hr_session_name);
$hrq = mysqli_query($con, "SELECT id FROM hr_employees WHERE name = '$safe_hr_name' LIMIT 1");
if ($hrq && mysqli_num_rows($hrq) > 0) {
    $hr_emp_pk = mysqli_fetch_assoc($hrq)['id'];
} else {
    $hrq2 = mysqli_query($con, "SELECT id FROM hr_employees ORDER BY id ASC LIMIT 1");
    if ($hrq2 && mysqli_num_rows($hrq2) > 0) $hr_emp_pk = mysqli_fetch_assoc($hrq2)['id'];
}

// =========================================================================
// HELPER: create ONE summary ticket
// =========================================================================
function createSummaryTicket($con, $assigned_to_emp_pk, $created_by_emp_pk, $subject, $message, $priority = 'medium', $timeline_minutes = 1440) {
    $result = mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets");
    $row    = $result ? mysqli_fetch_assoc($result) : ['max_id' => 0];
    $nextId = ($row['max_id'] ?? 0) + 1;
    $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
    $deadline = date('Y-m-d H:i:s', strtotime("+{$timeline_minutes} minutes"));
    $status = 'open';

    $stmt = mysqli_prepare($con,
        "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', NOW(), NOW(), ?, ?)");
    if (!$stmt) return false;
    $name_field = ''; // ticket "name" column = creator/reporter label
    mysqli_stmt_bind_param($stmt, "ssssssisii",
        $ticket_number, $name_field, $subject, $message, $status,
        $priority, $timeline_minutes, $deadline, $assigned_to_emp_pk, $created_by_emp_pk);
    $ok = mysqli_stmt_execute($stmt);
    mysqli_stmt_close($stmt);
    return $ok ? $ticket_number : false;
}

// =========================================================================
// AJAX: departments list (for filter dropdown)
// =========================================================================
if (isset($_GET['get_departments'])) {
    $dq = mysqli_query($con, "SELECT DISTINCT department FROM hr_employees WHERE department IS NOT NULL AND department != '' ORDER BY department ASC");
    $deps = [];
    if ($dq) while ($dr = mysqli_fetch_assoc($dq)) $deps[] = $dr['department'];
    header('Content-Type: application/json');
    echo json_encode($deps);
    exit;
}

// =========================================================================
// AJAX: employees list (for filter dropdown / manual ticket assign)
// =========================================================================
if (isset($_GET['get_employees'])) {
    $eq = mysqli_query($con, "SELECT id, employee_id, name, department FROM hr_employees WHERE status='Active' ORDER BY name ASC");
    $emps = [];
    if ($eq) while ($er = mysqli_fetch_assoc($eq)) $emps[] = $er;
    header('Content-Type: application/json');
    echo json_encode($emps);
    exit;
}

// =========================================================================
// AJAX: employee summary list with filters (month, department, status)
// =========================================================================
if (isset($_GET['get_summary'])) {
    $month = preg_match('/^\d{4}-\d{2}$/', $_GET['month'] ?? '') ? $_GET['month'] : date('Y-m');
    $dept  = trim($_GET['department'] ?? '');
    $stat  = trim($_GET['status'] ?? '');
    $emp_filter = trim($_GET['employee_id'] ?? '');

    $safe_month = mysqli_real_escape_string($con, $month);
    $where_emp = "e.status='Active'";
    if ($dept !== '') $where_emp .= " AND e.department = '" . mysqli_real_escape_string($con, $dept) . "'";
    if ($emp_filter !== '') $where_emp .= " AND e.employee_id = '" . mysqli_real_escape_string($con, $emp_filter) . "'";

    $sql = "SELECT e.id as emp_pk, e.employee_id, e.name, e.department, e.position,
                COUNT(p.id) as total_entries,
                SUM(p.approval_status='pending')  as pending_count,
                SUM(p.approval_status='approved') as approved_count,
                SUM(p.approval_status='declined') as declined_count
            FROM hr_employees e
            LEFT JOIN hr_daily_planner p ON p.employee_id = e.employee_id AND DATE_FORMAT(p.plan_date,'%Y-%m') = '$safe_month'
            WHERE $where_emp
            GROUP BY e.id
            ORDER BY e.name ASC";
    $rq = mysqli_query($con, $sql);
    $rows = [];
    if ($rq) {
        while ($r = mysqli_fetch_assoc($rq)) {
            $r['total_entries']    = (int)$r['total_entries'];
            $r['pending_count']    = (int)$r['pending_count'];
            $r['approved_count']   = (int)$r['approved_count'];
            $r['declined_count']   = (int)$r['declined_count'];
            if ($stat === 'pending'    && $r['pending_count']  == 0) continue;
            if ($stat === 'approved'   && $r['approved_count'] == 0) continue;
            if ($stat === 'declined'   && $r['declined_count'] == 0) continue;
            if ($stat === 'not_filled' && $r['total_entries']  != 0) continue;
            $rows[] = $r;
        }
    }
    header('Content-Type: application/json');
    echo json_encode($rows);
    exit;
}

// =========================================================================
// AJAX: entries for one employee + month (detail view)
// =========================================================================
if (isset($_GET['get_entries'])) {
    $eid   = mysqli_real_escape_string($con, $_GET['employee_id'] ?? '');
    $month = preg_match('/^\d{4}-\d{2}$/', $_GET['month'] ?? '') ? $_GET['month'] : date('Y-m');
    $safe_month = mysqli_real_escape_string($con, $month);
    $rq = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE employee_id='$eid' AND DATE_FORMAT(plan_date,'%Y-%m')='$safe_month' ORDER BY plan_date ASC");
    $rows = [];
    if ($rq) while ($r = mysqli_fetch_assoc($rq)) $rows[] = $r;
    header('Content-Type: application/json');
    echo json_encode($rows);
    exit;
}

// =========================================================================
// AJAX: single entry view
// =========================================================================
if (isset($_GET['view_entry'])) {
    $safe_id = intval($_GET['view_entry']);
    $vq = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE id=$safe_id LIMIT 1");
    $row = ($vq && mysqli_num_rows($vq) > 0) ? mysqli_fetch_assoc($vq) : null;
    header('Content-Type: application/json');
    echo json_encode($row ?: ['empty' => true]);
    exit;
}

// =========================================================================
// POST: bulk approve / decline (creates ONE summary ticket)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['bulk_action'])) {
    header('Content-Type: application/json');
    try {
        $ids        = $_POST['entry_ids'] ?? [];
        $action     = $_POST['action'] ?? '';
        $reason     = trim($_POST['reason'] ?? '');
        $emp_id     = trim($_POST['employee_id'] ?? '');
        $emp_name   = trim($_POST['employee_name'] ?? '');

        $ids = array_filter(array_map('intval', $ids));
        if (empty($ids) || !in_array($action, ['approved','declined']) || $emp_id === '') {
            echo json_encode(['ok'=>false,'msg'=>'Invalid request.']); exit;
        }
        if ($action === 'declined' && $reason === '') {
            echo json_encode(['ok'=>false,'msg'=>'A reason is required to decline.']); exit;
        }

        $safe_eid    = mysqli_real_escape_string($con, $emp_id);
        $safe_reason = mysqli_real_escape_string($con, $reason);
        $safe_hr     = mysqli_real_escape_string($con, $hr_session_name);
        $id_list     = implode(',', $ids);

        $sql = "UPDATE hr_daily_planner SET approval_status='$action', approval_reason=" . ($action==='declined' ? "'$safe_reason'" : "NULL") . ",
                approved_by='$safe_hr', approved_at=NOW()
                WHERE id IN ($id_list) AND employee_id='$safe_eid'";
        $ok = mysqli_query($con, $sql);

        // fetch the dates affected, for the ticket summary
        $dq = mysqli_query($con, "SELECT plan_date FROM hr_daily_planner WHERE id IN ($id_list) AND employee_id='$safe_eid' ORDER BY plan_date ASC");
        $dates = [];
        if ($dq) while ($dr = mysqli_fetch_assoc($dq)) $dates[] = date('d M Y', strtotime($dr['plan_date']));

        // resolve employee's hr_employees.id for ticket assignment
        $assigned_pk = 0;
        $aq = mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id='$safe_eid' LIMIT 1");
        if ($aq && mysqli_num_rows($aq) > 0) $assigned_pk = mysqli_fetch_assoc($aq)['id'];

        $label = $action === 'approved' ? 'Approved' : 'Declined';
        $subject = "Monthly Planner Review - $emp_name - $label (" . count($ids) . " date" . (count($ids)>1?'s':'') . ")";
        $message = "Monthly Planner review summary for $emp_name.\n\n";
        $message .= "Decision: $label\n";
        $message .= "Daily Planner Dates (" . count($dates) . "): " . implode(', ', $dates) . "\n";
        if ($action === 'declined') $message .= "Reason: $reason\n";
        $message .= "Reviewed by: $hr_session_name on " . date('d M Y H:i');

        $priority = $action === 'declined' ? 'high' : 'low';
        $ticket_number = false;
        if ($assigned_pk) {
            $ticket_number = createSummaryTicket($con, $assigned_pk, $hr_emp_pk, $subject, $message, $priority);
        }

        echo json_encode(['ok' => (bool)$ok, 'ticket' => $ticket_number]);
    } catch (\Throwable $e) {
        echo json_encode(['ok' => false, 'msg' => 'Fatal Error: ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine()]);
    }
    exit;
}

// =========================================================================
// POST: admin adds a task to an employee's planner (as a priority item)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_task'])) {
    header('Content-Type: application/json');
    $emp_id    = trim($_POST['employee_id'] ?? '');
    $emp_name  = trim($_POST['employee_name'] ?? '');
    $plan_date = trim($_POST['plan_date'] ?? '');
    $task_text = trim($_POST['task_text'] ?? '');
    $task_time = trim($_POST['task_time'] ?? '');
    $raise_ticket = !empty($_POST['raise_ticket']);
    $priority  = trim($_POST['priority'] ?? 'medium');
    $timeline  = intval($_POST['timeline'] ?? 1440);

    if ($emp_id === '' || $plan_date === '' || $task_text === '') {
        echo json_encode(['ok'=>false,'msg'=>'Employee, date and task text are required.']); exit;
    }

    $safe_eid   = mysqli_real_escape_string($con, $emp_id);
    $safe_ename = mysqli_real_escape_string($con, $emp_name);
    $safe_date  = mysqli_real_escape_string($con, $plan_date);

    $rq  = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE employee_id='$safe_eid' AND plan_date='$safe_date' LIMIT 1");
    $row = ($rq && mysqli_num_rows($rq) > 0) ? mysqli_fetch_assoc($rq) : null;

    $pris = [];
    if ($row && !empty($row['priorities'])) {
        $decoded = json_decode($row['priorities'], true);
        if (is_array($decoded)) {
            foreach ($decoded as $p) {
                $pris[] = is_string($p) ? ['type'=>'self','text'=>$p,'time'=>'','completed'=>false,'assigned_by'=>''] : $p;
            }
        }
    }
    $pris[] = [
        'type'        => 'admin',
        'text'        => $task_text,
        'time'        => $task_time,
        'completed'   => false,
        'assigned_by' => $hr_session_name
    ];
    $pris_json = mysqli_real_escape_string($con, json_encode($pris));

    if ($row) {
        mysqli_query($con, "UPDATE hr_daily_planner SET priorities='$pris_json', updated_at=NOW() WHERE id={$row['id']}");
    } else {
        mysqli_query($con, "INSERT INTO hr_daily_planner (employee_id,employee_name,plan_date,priorities) VALUES ('$safe_eid','$safe_ename','$safe_date','$pris_json')");
    }

    $ticket_number = false;
    if ($raise_ticket) {
        $assigned_pk = 0;
        $aq = mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id='$safe_eid' LIMIT 1");
        if ($aq && mysqli_num_rows($aq) > 0) $assigned_pk = mysqli_fetch_assoc($aq)['id'];
        if ($assigned_pk) {
            $subject = "New Task Assigned - $emp_name - " . date('d M Y', strtotime($plan_date));
            $message = "A new task has been assigned via Monthly Planner.\n\n";
            $message .= "Date: " . date('d M Y', strtotime($plan_date)) . "\n";
            $message .= "Task: $task_text\n";
            if ($task_time) $message .= "Time: $task_time\n";
            $message .= "Assigned by: $hr_session_name on " . date('d M Y H:i');
            $ticket_number = createSummaryTicket($con, $assigned_pk, $hr_emp_pk, $subject, $message, $priority, $timeline);
        }
    }

    echo json_encode(['ok'=>true, 'ticket'=>$ticket_number]);
    exit;
}

// =========================================================================
// POST: manual ticket raise (independent of approval)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['manual_ticket'])) {
    header('Content-Type: application/json');
    $subject     = trim($_POST['subject'] ?? '');
    $message     = trim($_POST['message'] ?? '');
    $priority    = trim($_POST['priority'] ?? 'medium');
    $assigned_to = intval($_POST['assigned_to'] ?? 0);
    $timeline    = intval($_POST['timeline'] ?? 1440);

    if ($subject === '' || $message === '' || $assigned_to === 0) {
        echo json_encode(['ok'=>false,'msg'=>'Please fill subject, message and assignee.']); exit;
    }
    $ticket_number = createSummaryTicket($con, $assigned_to, $hr_emp_pk, $subject, $message, $priority, $timeline);
    echo json_encode(['ok' => (bool)$ticket_number, 'ticket' => $ticket_number]);
    exit;
}

// Parse timings (reused for displaying schedule slots inside view modal)
function parseTimingSlots($timings_str) {
    $default = [];
    for ($h = 8; $h <= 17; $h++) {
        $ampm = $h < 12 ? 'AM' : 'PM';
        $disp = $h % 12 == 0 ? 12 : $h % 12;
        $default[] = sprintf('%02d:00 %s', $disp, $ampm);
    }
    if (empty($timings_str)) return $default;
    $ts = strtoupper(trim($timings_str));
    if (preg_match('/(\d{1,2}(?::\d{2})?\s*(?:AM|PM))\s*[-–TO]+\s*(\d{1,2}(?::\d{2})?\s*(?:AM|PM))/i', $ts, $m)) {
        $sh = (int)date('G', strtotime($m[1]));
        $eh = (int)date('G', strtotime($m[2]));
        if ($sh && $eh) {
            $slots = [];
            for ($h = $sh; $h <= $eh; $h++) {
                $ampm = $h < 12 ? 'AM' : 'PM';
                $disp = $h % 12 == 0 ? 12 : $h % 12;
                $slots[] = sprintf('%02d:00 %s', $disp, $ampm);
            }
            return $slots;
        }
    }
    return $default;
}

$default_month = date('Y-m');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'HR'); ?> | Planner Approvals</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root {
    --navy:#0d1f3c; --navy2:#153060; --blue:#2563c4;
    --red:#c0392b; --red2:#e74c3c; --amber:#f59e0b;
    --green:#10b981; --bg:#f0f4f8; --border:#cbd5e1;
    --text:#1e293b; --muted:#64748b; --purple:#7c3aed; --purple2:#6d28d9;
}
*{font-family:'Outfit',sans-serif;box-sizing:border-box;margin:0;padding:0;}
body{background:var(--bg);color:var(--text);}
.wrap{max-width:1420px;margin:0 auto;padding:20px 16px;}

.page-header{background:linear-gradient(135deg,var(--navy) 0%,var(--navy2) 100%);border-radius:14px 14px 0 0;padding:20px 28px;display:flex;align-items:center;gap:16px;}
.ph-icon{width:48px;height:48px;background:rgba(255,255,255,.12);border-radius:12px;display:flex;align-items:center;justify-content:center;color:var(--amber);font-size:20px;flex-shrink:0;}
.page-header h1{color:#fff;font-weight:800;font-size:19px;margin:0;}
.page-header p{color:rgba(255,255,255,.6);font-size:12px;margin:2px 0 0;}
.hr-chip{margin-left:auto;background:rgba(255,255,255,.14);border-radius:30px;padding:8px 18px;color:#fff;font-size:13px;font-weight:600;white-space:nowrap;}

.card-shell{background:#fff;border-radius:0 0 14px 14px;box-shadow:0 8px 30px rgba(13,31,61,.08);padding:24px 28px;}

.top-actions{display:flex;gap:10px;margin-bottom:18px;flex-wrap:wrap;align-items:center;}
.btn-back{background:#fff;border:1.5px solid var(--border);color:var(--navy);border-radius:8px;padding:8px 16px;font-size:13px;font-weight:700;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;}
.btn-back:hover{background:#f1f5f9;text-decoration:none;color:var(--navy);}
.btn-raise-ticket{background:linear-gradient(135deg,var(--red),var(--red2));color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;margin-left:auto;}
.btn-raise-ticket:hover{opacity:.9;}

/* FILTER BAR */
.filter-bar{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;background:#f8fafc;border:1.5px solid var(--border);border-radius:12px;padding:16px;margin-bottom:20px;}
.filter-field{display:flex;flex-direction:column;gap:5px;min-width:160px;}
.filter-field label{font-size:11px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.4px;}
.filter-field select,.filter-field input{padding:9px 12px;border:1.5px solid var(--border);border-radius:8px;font-size:13px;font-weight:600;color:var(--text);outline:none;background:#fff;}
.filter-field select:focus,.filter-field input:focus{border-color:var(--navy2);}
.btn-apply-filter{background:linear-gradient(135deg,var(--navy2),var(--blue));color:#fff;border:none;border-radius:8px;padding:10px 22px;font-size:13px;font-weight:700;cursor:pointer;height:38px;}
.btn-apply-filter:hover{opacity:.9;}

/* SUMMARY TABLE */
.summary-table{width:100%;border-collapse:collapse;}
.summary-table th{text-align:left;font-size:11px;font-weight:800;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;padding:10px 14px;border-bottom:2px solid var(--border);}
.summary-table td{padding:12px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;vertical-align:middle;}
.summary-table tr:hover td{background:#f8fafc;}
.emp-name-cell{font-weight:700;color:var(--navy);}
.emp-dept-cell{color:var(--muted);font-size:12px;}
.count-pill{display:inline-flex;align-items:center;gap:5px;padding:4px 11px;border-radius:20px;font-size:12px;font-weight:700;}
.count-pending{background:#fef3c7;color:#92400e;}
.count-approved{background:#d1fae5;color:#065f46;}
.count-declined{background:#fee2e2;color:#991b1b;}
.count-total{background:#e0e7ff;color:#3730a3;}
.btn-open-detail{background:var(--navy2);color:#fff;border:none;border-radius:6px;padding:7px 16px;font-size:12px;font-weight:700;cursor:pointer;}
.btn-open-detail:hover{opacity:.9;}
.empty-row{text-align:center;padding:40px;color:var(--muted);}

/* DETAIL VIEW */
.detail-header{display:flex;align-items:center;gap:12px;margin-bottom:16px;flex-wrap:wrap;}
.detail-header h2{font-size:17px;font-weight:800;color:var(--navy);margin:0;}
.detail-header .dh-sub{font-size:12px;color:var(--muted);font-weight:600;}
.btn-back-list{background:#fff;border:1.5px solid var(--border);color:var(--navy);border-radius:8px;padding:7px 14px;font-size:12px;font-weight:700;cursor:pointer;}
.btn-back-list:hover{background:#f1f5f9;}

.entry-table-wrap{border:1.5px solid var(--border);border-radius:10px;overflow:hidden;margin-bottom:16px;}
.entry-table{width:100%;border-collapse:collapse;}
.entry-table th{background:#f8fafc;text-align:left;font-size:11px;font-weight:800;color:var(--muted);text-transform:uppercase;letter-spacing:.4px;padding:10px 14px;border-bottom:1.5px solid var(--border);}
.entry-table td{padding:10px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;}
.entry-table tr:last-child td{border-bottom:none;}
.status-badge-sm{display:inline-flex;align-items:center;gap:4px;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;}
.status-pending{background:#fef3c7;color:#92400e;}
.status-approved{background:#d1fae5;color:#065f46;}
.status-declined{background:#fee2e2;color:#991b1b;}
.btn-view-sm{background:var(--blue);color:#fff;border:none;border-radius:6px;padding:5px 12px;font-size:11px;font-weight:700;cursor:pointer;}
.btn-view-sm:hover{opacity:.9;}

.bulk-bar{display:flex;align-items:center;gap:12px;background:#f8fafc;border:1.5px solid var(--border);border-radius:10px;padding:12px 16px;flex-wrap:wrap;}
.bulk-bar .sel-count{font-size:13px;font-weight:700;color:var(--navy);}
.btn-bulk-approve{background:linear-gradient(135deg,var(--green),#059669);color:#fff;border:none;border-radius:8px;padding:9px 20px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;}
.btn-bulk-approve:hover{opacity:.9;}
.btn-bulk-decline{background:linear-gradient(135deg,var(--red),var(--red2));color:#fff;border:none;border-radius:8px;padding:9px 20px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;}
.btn-bulk-decline:hover{opacity:.9;}

/* MODAL BASE */
.modal-overlay{position:fixed;inset:0;background:rgba(13,31,61,.5);z-index:8000;display:none;align-items:flex-start;justify-content:center;padding:40px 16px;overflow-y:auto;}
.modal-overlay.active{display:flex;}
.modal-box{background:#fff;border-radius:14px;width:100%;max-width:700px;box-shadow:0 20px 60px rgba(0,0,0,.2);overflow:hidden;margin:auto;}
.modal-head{background:linear-gradient(135deg,var(--navy),var(--navy2));padding:18px 24px;display:flex;align-items:center;gap:12px;}
.modal-head.head-red{background:linear-gradient(135deg,var(--red),var(--red2));}
.modal-head.head-green{background:linear-gradient(135deg,var(--green),#059669);}
.modal-head.head-purple{background:linear-gradient(135deg,var(--purple),var(--purple2));}
.modal-head h3{color:#fff;font-weight:800;font-size:16px;margin:0;flex:1;}
.modal-close{background:rgba(255,255,255,.15);border:none;color:#fff;width:30px;height:30px;border-radius:6px;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;}
.modal-close:hover{background:rgba(255,255,255,.28);}
.modal-body{padding:22px 24px;}
.modal-body label{display:block;font-size:12px;font-weight:700;color:var(--navy);margin-bottom:6px;text-transform:uppercase;letter-spacing:.4px;}
.modal-body textarea,.modal-body input,.modal-body select{width:100%;padding:11px 14px;border:1.5px solid var(--border);border-radius:8px;font-size:13px;font-weight:500;color:var(--text);outline:none;margin-bottom:16px;}
.modal-body textarea:focus,.modal-body input:focus,.modal-body select:focus{border-color:var(--navy2);}
.btn-modal-submit{width:100%;border:none;border-radius:8px;padding:12px;font-size:14px;font-weight:800;color:#fff;cursor:pointer;}
.btn-modal-submit.bg-red{background:linear-gradient(135deg,var(--red),var(--red2));}
.btn-modal-submit.bg-green{background:linear-gradient(135deg,var(--green),#059669);}
.btn-modal-submit.bg-navy{background:linear-gradient(135deg,var(--navy2),var(--blue));}

/* VIEW ENTRY MODAL CONTENT */
.view-section{margin-bottom:16px;}
.view-section-title{font-size:11px;font-weight:800;color:var(--red);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;}
.view-text-box{background:#f8fafc;border-radius:8px;padding:12px;font-size:13px;white-space:pre-wrap;min-height:50px;}
.view-schedule-row{display:flex;gap:10px;padding:5px 8px;font-size:12px;border-bottom:1px solid #f1f5f9;}
.vs-time{font-weight:800;color:var(--navy);width:80px;flex-shrink:0;}

.loading-overlay{position:fixed;inset:0;background:rgba(13,31,61,.35);display:none;align-items:center;justify-content:center;z-index:9999;}
.loading-overlay.active{display:flex;}
.loading-spinner{background:#fff;border-radius:14px;padding:28px 36px;text-align:center;}
.spinner-ring{width:42px;height:42px;border:4px solid #e2e8f0;border-top-color:var(--navy2);border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 10px;}
@keyframes spin{to{transform:rotate(360deg);}}

.alert-ok{background:#d1fae5;color:#065f46;border:1px solid #6ee7b7;border-radius:8px;padding:12px 16px;margin-bottom:16px;font-weight:600;font-size:14px;}
.alert-err{background:#fee2e2;color:#991b1b;border:1px solid #fca5a5;border-radius:8px;padding:12px 16px;margin-bottom:16px;font-weight:600;font-size:14px;}
</style>
</head>
<body>

<div class="loading-overlay" id="loadingOverlay">
    <div class="loading-spinner">
        <div class="spinner-ring"></div>
        <div style="font-weight:700;color:var(--navy);font-size:14px;">Loading...</div>
    </div>
</div>

<!-- VIEW ENTRY MODAL -->
<div class="modal-overlay" id="viewEntryModal">
  <div class="modal-box" style="max-width:900px;">
    <div class="modal-head">
      <i class="fas fa-calendar-day" style="color:var(--amber);font-size:18px;"></i>
      <h3 id="viewEntryTitle">Planner Entry</h3>
      <button class="modal-close" onclick="closeModal('viewEntryModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body" id="viewEntryBody"><div style="text-align:center;padding:30px;">Loading...</div></div>
  </div>
</div>

<!-- DECLINE REASON MODAL -->
<div class="modal-overlay" id="declineModal">
  <div class="modal-box">
    <div class="modal-head head-red">
      <i class="fas fa-times-circle" style="color:#fff;font-size:18px;"></i>
      <h3>Decline Entries — Reason Required</h3>
      <button class="modal-close" onclick="closeModal('declineModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body">
      <p style="font-size:13px;color:var(--muted);margin-bottom:14px;" id="declineSummaryText"></p>
      <label>Reason for Decline <span style="color:#ef4444;">*</span></label>
      <textarea id="declineReasonInput" rows="4" placeholder="Explain why these entries are being declined..."></textarea>
      <button type="button" class="btn-modal-submit bg-red" onclick="submitBulkAction('declined')"><i class="fas fa-times-circle"></i> Confirm Decline &amp; Send Ticket</button>
    </div>
  </div>
</div>

<!-- APPROVE CONFIRM MODAL -->
<div class="modal-overlay" id="approveModal">
  <div class="modal-box">
    <div class="modal-head head-green">
      <i class="fas fa-check-circle" style="color:#fff;font-size:18px;"></i>
      <h3>Approve Entries</h3>
      <button class="modal-close" onclick="closeModal('approveModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body">
      <p style="font-size:13px;color:var(--muted);margin-bottom:16px;" id="approveSummaryText"></p>
      <button type="button" class="btn-modal-submit bg-green" onclick="submitBulkAction('approved')"><i class="fas fa-check-circle"></i> Confirm Approve &amp; Send Ticket</button>
    </div>
  </div>
</div>

<!-- MANUAL RAISE TICKET MODAL -->
<div class="modal-overlay" id="manualTicketModal">
  <div class="modal-box">
    <div class="modal-head head-purple">
      <i class="fas fa-ticket-alt" style="color:#fff;font-size:18px;"></i>
      <h3>Raise a Ticket</h3>
      <button class="modal-close" onclick="closeModal('manualTicketModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body">
      <label>Assign To</label>
      <select id="manualAssignTo"></select>
      <label>Priority</label>
      <select id="manualPriority">
        <option value="low">Low</option>
        <option value="medium" selected>Medium</option>
        <option value="high">High</option>
      </select>
      <label>Timeline</label>
      <select id="manualTimeline">
        <option value="60">1 Hour</option>
        <option value="1440" selected>24 Hours</option>
        <option value="2880">48 Hours</option>
        <option value="10080">1 Week</option>
      </select>
      <label>Subject</label>
      <input type="text" id="manualSubject" placeholder="Ticket subject"/>
      <label>Message</label>
      <textarea id="manualMessage" rows="4" placeholder="Describe the issue..."></textarea>
      <button type="button" class="btn-modal-submit bg-navy" onclick="submitManualTicket()"><i class="fas fa-paper-plane"></i> Submit Ticket</button>
    </div>
  </div>
</div>

<!-- ADD TASK MODAL -->
<div class="modal-overlay" id="addTaskModal">
  <div class="modal-box">
    <div class="modal-head head-purple">
      <i class="fas fa-tasks" style="color:#fff;font-size:18px;"></i>
      <h3>Add Task for Employee</h3>
      <button class="modal-close" onclick="closeModal('addTaskModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body">
      <p style="font-size:13px;color:var(--muted);margin-bottom:14px;" id="addTaskSummaryText"></p>
      <label>Task</label>
      <textarea id="taskText" rows="3" placeholder="Describe the task..."></textarea>
      <label>Time (optional)</label>
      <input type="text" id="taskTime" placeholder="e.g. 3:00 PM"/>
      <label style="display:flex;align-items:center;gap:8px;text-transform:none;font-weight:600;">
        <input type="checkbox" id="taskRaiseTicket" style="width:auto;margin:0;"/> Also raise a ticket for this task
      </label>
      <div id="taskTicketFields" style="display:none;">
        <label>Priority</label>
        <select id="taskPriority">
          <option value="low">Low</option>
          <option value="medium" selected>Medium</option>
          <option value="high">High</option>
        </select>
        <label>Timeline</label>
        <select id="taskTimeline">
          <option value="60">1 Hour</option>
          <option value="1440" selected>24 Hours</option>
          <option value="2880">48 Hours</option>
          <option value="10080">1 Week</option>
        </select>
      </div>
      <button type="button" class="btn-modal-submit bg-navy" onclick="submitAddTask()"><i class="fas fa-paper-plane"></i> Add Task</button>
    </div>
  </div>
</div>

<div class="wrap">
  <div class="page-header">
    <div class="ph-icon"><i class="fas fa-tasks"></i></div>
    <div>
      <h1>Monthly Planner — Approvals Dashboard</h1>
      <p>Review, approve or decline employee monthly planners</p>
    </div>
    <div class="hr-chip"><i class="fas fa-user-shield" style="margin-right:6px;"></i><?php echo htmlspecialchars($hr_session_name); ?></div>
  </div>

  <div class="card-shell">

    <div class="top-actions">
      <a href="javascript:history.back()" class="btn-back"><i class="fas fa-arrow-left"></i> Back</a>
      <button type="button" class="btn-raise-ticket" style="margin-left:0;background:linear-gradient(135deg,var(--red),var(--red2));" onclick="downloadHRSummaryPDF()"><i class="fas fa-file-pdf"></i> Download HR Summary PDF</button>
      <button type="button" class="btn-raise-ticket" onclick="openManualTicket()"><i class="fas fa-ticket-alt"></i> Raise a Ticket</button>
    </div>

    <div id="alertBox"></div>

    <!-- ====== LIST VIEW ====== -->
    <div id="listView">

      <div class="filter-bar">
        <div class="filter-field">
          <label>Month</label>
          <input type="month" id="filterMonth" value="<?php echo $default_month; ?>"/>
        </div>
        <div class="filter-field">
          <label>Department</label>
          <select id="filterDepartment"><option value="">All Departments</option></select>
        </div>
        <div class="filter-field">
          <label>Employee</label>
          <select id="filterEmployee"><option value="">All Employees</option></select>
        </div>
        <div class="filter-field">
          <label>Status</label>
          <select id="filterStatus">
            <option value="">All Statuses</option>
            <option value="pending">Has Pending</option>
            <option value="approved">Has Approved</option>
            <option value="declined">Has Declined</option>
            <option value="not_filled">Not Filled This Month</option>
          </select>
        </div>
        <button type="button" class="btn-apply-filter" onclick="loadSummary()"><i class="fas fa-filter"></i> Apply</button>
      </div>

      <div style="overflow-x:auto;">
        <table class="summary-table">
          <thead>
            <tr>
              <th>Employee</th>
              <th>Department</th>
              <th>Total Entries</th>
              <th>Pending</th>
              <th>Approved</th>
              <th>Declined</th>
              <th></th>
            </tr>
          </thead>
          <tbody id="summaryTableBody">
            <tr><td colspan="7" class="empty-row">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    </div><!-- /listView -->

    <!-- ====== DETAIL VIEW ====== -->
    <div id="detailView" style="display:none;">

      <div class="detail-header">
        <button type="button" class="btn-back-list" onclick="backToList()"><i class="fas fa-arrow-left"></i> Back to List</button>
        <div>
          <h2 id="detailEmpName">—</h2>
          <div class="dh-sub" id="detailEmpSub">—</div>
        </div>
        <button type="button" class="btn-raise-ticket" style="margin-left:auto;background:linear-gradient(135deg,var(--red),var(--red2));" onclick="downloadEmployeeMonthPDF()"><i class="fas fa-file-pdf"></i> Download Month PDF</button>
      </div>

      <div class="entry-table-wrap">
        <table class="entry-table">
          <thead>
            <tr>
              <th style="width:30px;"><input type="checkbox" id="selectAllEntries" onclick="toggleSelectAll(this)"/></th>
              <th>Date</th>
              <th>Day</th>
              <th>Status</th>
              <th>Reviewed By</th>
              <th></th>
            </tr>
          </thead>
          <tbody id="detailTableBody">
            <tr><td colspan="6" class="empty-row">Loading...</td></tr>
          </tbody>
        </table>
      </div>

      <div class="bulk-bar">
        <span class="sel-count" id="selCountText">0 selected</span>
        <button type="button" class="btn-bulk-approve" onclick="openApproveConfirm()"><i class="fas fa-check"></i> Approve Selected</button>
        <button type="button" class="btn-bulk-decline" onclick="openDeclineConfirm()"><i class="fas fa-times"></i> Decline Selected</button>
      </div>

    </div><!-- /detailView -->

  </div><!-- /card-shell -->
</div><!-- /wrap -->

<script>
const currentPage = '<?php echo $current_page; ?>';
let currentEmpId = '', currentEmpName = '', currentMonth = '';
let allEntries = [];
const dayNames = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

function showLoading(on) { document.getElementById('loadingOverlay').classList.toggle('active', on); }
function openModal(id){ document.getElementById(id).classList.add('active'); }
function closeModal(id){ document.getElementById(id).classList.remove('active'); }
document.querySelectorAll('.modal-overlay').forEach(m=>{
    m.addEventListener('click', e=>{ if(e.target===m) m.classList.remove('active'); });
});
function escHtml(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function safeJson(v) { try { return typeof v==='string' ? JSON.parse(v) : v; } catch(e) { return null; } }

function priorityViewItemHtml(p, i) {
    if (typeof p === 'string') {
        return `<div style="display:flex;gap:8px;padding:5px 8px;background:#f8fafc;border-radius:5px;margin-bottom:4px;font-size:13px;"><span style="color:var(--red);font-weight:800;">${i+1}.</span>${escHtml(p)}</div>`;
    }
    const badge = p.type === 'admin' ? `<span style="background:#f59e0b;color:#fff;font-size:9px;font-weight:800;padding:1px 6px;border-radius:8px;margin-left:6px;">ASSIGNED BY ${escHtml(p.assigned_by||'HR')}</span>` : '';
    const time = p.time ? `<span style="font-size:11px;color:#92400e;margin-left:6px;"><i class="fas fa-clock"></i> ${escHtml(p.time)}</span>` : '';
    const done = p.completed ? 'text-decoration:line-through;color:#94a3b8;' : '';
    return `<div style="display:flex;gap:8px;padding:5px 8px;background:#f8fafc;border-radius:5px;margin-bottom:4px;font-size:13px;${done}"><span style="color:var(--red);font-weight:800;">${i+1}.</span>${escHtml(p.text||'')}${badge}${time}</div>`;
}
function showAlert(type, msg) {
    document.getElementById('alertBox').innerHTML = `<div class="alert-${type==='ok'?'ok':'err'}"><i class="fas fa-${type==='ok'?'check-circle':'exclamation-circle'}"></i> ${escHtml(msg)}</div>`;
    setTimeout(()=>{ document.getElementById('alertBox').innerHTML=''; }, 6000);
}

// ── Init filter dropdowns ──────────────────────────────────
function initFilters() {
    fetch(`${currentPage}?get_departments=1`).then(r=>r.json()).then(deps=>{
        const sel = document.getElementById('filterDepartment');
        deps.forEach(d=>{ const o=document.createElement('option'); o.value=d; o.textContent=d; sel.appendChild(o); });
    });
    fetch(`${currentPage}?get_employees=1`).then(r=>r.json()).then(emps=>{
        const sel = document.getElementById('filterEmployee');
        const assignSel = document.getElementById('manualAssignTo');
        emps.forEach(e=>{
            const o=document.createElement('option'); o.value=e.employee_id; o.textContent=e.name+' — '+(e.department||''); sel.appendChild(o);
            const o2=document.createElement('option'); o2.value=e.id; o2.textContent=e.name; assignSel.appendChild(o2);
        });
    });
}
initFilters();

// ── Load summary table ─────────────────────────────────────
function loadSummary() {
    showLoading(true);
    const month = document.getElementById('filterMonth').value || '<?php echo $default_month; ?>';
    const dept  = document.getElementById('filterDepartment').value;
    const emp   = document.getElementById('filterEmployee').value;
    const stat  = document.getElementById('filterStatus').value;
    const qs = new URLSearchParams({get_summary:1, month, department:dept, employee_id:emp, status:stat});
    fetch(`${currentPage}?${qs.toString()}`).then(r=>r.json()).then(rows=>{
        showLoading(false);
        const tbody = document.getElementById('summaryTableBody');
        if (!rows.length) { tbody.innerHTML = '<tr><td colspan="7" class="empty-row">No employees match this filter.</td></tr>'; return; }
        tbody.innerHTML = rows.map(r=>`
            <tr>
                <td class="emp-name-cell">${escHtml(r.name)}</td>
                <td class="emp-dept-cell">${escHtml(r.department||'—')}</td>
                <td><span class="count-pill count-total">${r.total_entries}</span></td>
                <td>${r.pending_count>0?`<span class="count-pill count-pending">${r.pending_count}</span>`:'—'}</td>
                <td>${r.approved_count>0?`<span class="count-pill count-approved">${r.approved_count}</span>`:'—'}</td>
                <td>${r.declined_count>0?`<span class="count-pill count-declined">${r.declined_count}</span>`:'—'}</td>
                <td><button type="button" class="btn-open-detail" onclick="openDetail('${r.employee_id}','${escHtml(r.name)}','${escHtml(r.department||'')}')"><i class="fas fa-eye"></i> View</button></td>
            </tr>`).join('');
    });
}
loadSummary();

// ── Detail view ─────────────────────────────────────────────
function openDetail(empId, empName, empDept) {
    currentEmpId = empId; currentEmpName = empName;
    currentMonth = document.getElementById('filterMonth').value || '<?php echo $default_month; ?>';
    document.getElementById('detailEmpName').textContent = empName;
    document.getElementById('detailEmpSub').textContent = empDept + ' · ' + currentMonth;
    document.getElementById('listView').style.display = 'none';
    document.getElementById('detailView').style.display = 'block';
    loadEntries();
}
function backToList() {
    document.getElementById('detailView').style.display = 'none';
    document.getElementById('listView').style.display = 'block';
    loadSummary();
}

function loadEntries() {
    showLoading(true);
    const qs = new URLSearchParams({get_entries:1, employee_id:currentEmpId, month:currentMonth});
    fetch(`${currentPage}?${qs.toString()}`).then(r=>r.json()).then(rows=>{
        showLoading(false);
        allEntries = rows;
        const tbody = document.getElementById('detailTableBody');
        if (!rows.length) { tbody.innerHTML = '<tr><td colspan="6" class="empty-row">No planner entries for this month.</td></tr>'; updateSelCount(); return; }
        tbody.innerHTML = rows.map(r=>{
            const d = new Date(r.plan_date+'T00:00:00');
            const statusCls = 'status-'+r.approval_status;
            const statusLabel = r.approval_status.charAt(0).toUpperCase()+r.approval_status.slice(1);
            return `<tr>
                <td><input type="checkbox" class="entry-check" value="${r.id}" onchange="updateSelCount()"></td>
                <td>${d.toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'})}</td>
                <td>${dayNames[d.getDay()]}</td>
                <td><span class="status-badge-sm ${statusCls}">${statusLabel}</span></td>
                <td>${escHtml(r.approved_by||'—')}</td>
                <td><button type="button" class="btn-view-sm" onclick="viewEntry(${r.id})"><i class="fas fa-eye"></i> View</button>
                    <button type="button" class="btn-view-sm" style="background:var(--amber);margin-left:4px;" onclick="openAddTask('${r.plan_date}')"><i class="fas fa-plus"></i> Add Task</button></td>
            </tr>`;
        }).join('');
        updateSelCount();
    });
}

function toggleSelectAll(box) {
    document.querySelectorAll('.entry-check').forEach(c=>c.checked = box.checked);
    updateSelCount();
}
function updateSelCount() {
    const n = document.querySelectorAll('.entry-check:checked').length;
    document.getElementById('selCountText').textContent = n + ' selected';
}
function getSelectedIds() {
    return Array.from(document.querySelectorAll('.entry-check:checked')).map(c=>c.value);
}

// ── View single entry ───────────────────────────────────────
function viewEntry(id) {
    openModal('viewEntryModal');
    document.getElementById('viewEntryBody').innerHTML = '<div style="text-align:center;padding:30px;">Loading...</div>';
    fetch(`${currentPage}?view_entry=${id}`).then(r=>r.json()).then(data=>{
        if (data.empty) { document.getElementById('viewEntryBody').innerHTML='<div style="padding:30px;text-align:center;">Entry not found.</div>'; return; }
        const d = new Date(data.plan_date+'T00:00:00');
        document.getElementById('viewEntryTitle').textContent = d.toLocaleDateString('en-IN',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
        const pris  = safeJson(data.priorities) || [];
        const slots = safeJson(data.schedule_slots) || {};
        let priHtml = pris.length ? pris.map((p,i)=>priorityViewItemHtml(p,i)).join('') : '<div style="color:var(--muted);">—</div>';
        let slotHtml = Object.keys(slots).length ? Object.keys(slots).map(s=>`<div class="view-schedule-row"><div class="vs-time">${s}</div><div>${escHtml(slots[s]||'—')}</div></div>`).join('') : '<div style="color:var(--muted);font-size:12px;">No schedule data.</div>';
        const statusCls = 'status-'+data.approval_status;
        document.getElementById('viewEntryBody').innerHTML = `
            <div style="margin-bottom:14px;"><span class="status-badge-sm ${statusCls}">${data.approval_status.charAt(0).toUpperCase()+data.approval_status.slice(1)}</span>
            ${data.approval_reason?`<div style="margin-top:8px;background:#fee2e2;border-radius:6px;padding:8px 12px;font-size:12px;color:#991b1b;"><b>Decline reason:</b> ${escHtml(data.approval_reason)}</div>`:''}</div>
            <div style="display:grid;grid-template-columns:1fr 260px;gap:18px;">
                <div>
                    <div class="view-section"><div class="view-section-title">Top Priorities</div>${priHtml}</div>
                    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
                        <div class="view-section"><div class="view-section-title">To Do</div><div class="view-text-box">${escHtml(data.todo_notes||'—')}</div></div>
                        <div class="view-section"><div class="view-section-title">If I Have Time</div><div class="view-text-box">${escHtml(data.if_have_time||'—')}</div></div>
                        <div class="view-section"><div class="view-section-title">Focus</div><div class="view-text-box">${escHtml(data.focus_notes||'—')}</div></div>
                        <div class="view-section"><div class="view-section-title">Goals</div><div class="view-text-box">${escHtml(data.goals_notes||'—')}</div></div>
                    </div>
                </div>
                <div class="view-section"><div class="view-section-title">Plan &amp; Schedules</div>${slotHtml}</div>
            </div>`;
    });
}

// ── Approve / Decline flow ──────────────────────────────────
function openApproveConfirm() {
    const ids = getSelectedIds();
    if (!ids.length) { alert('Select at least one entry first.'); return; }
    document.getElementById('approveSummaryText').textContent = `You are about to APPROVE ${ids.length} entry(ies) for ${currentEmpName}. One summary ticket will be sent automatically.`;
    openModal('approveModal');
}
function openDeclineConfirm() {
    const ids = getSelectedIds();
    if (!ids.length) { alert('Select at least one entry first.'); return; }
    document.getElementById('declineSummaryText').textContent = `You are about to DECLINE ${ids.length} entry(ies) for ${currentEmpName}. A reason is required and one summary ticket will be sent automatically.`;
    document.getElementById('declineReasonInput').value = '';
    openModal('declineModal');
}

function submitBulkAction(action) {
    const ids = getSelectedIds();
    let reason = '';
    if (action === 'declined') {
        reason = document.getElementById('declineReasonInput').value.trim();
        if (!reason) { alert('Please enter a reason for declining.'); return; }
    }
    showLoading(true);
    const fd = new FormData();
    fd.append('bulk_action', '1');
    ids.forEach(id => fd.append('entry_ids[]', id));
    fd.append('action', action);
    fd.append('reason', reason);
    fd.append('employee_id', currentEmpId);
    fd.append('employee_name', currentEmpName);
    fetch(currentPage, { method:'POST', body: fd }).then(r=>r.json()).then(res=>{
        showLoading(false);
        closeModal('approveModal'); closeModal('declineModal');
        if (res.ok) {
            showAlert('ok', `Entries ${action}. ${res.ticket ? 'Ticket '+res.ticket+' created.' : ''}`);
            loadEntries();
        } else {
            showAlert('err', res.msg || 'Action failed.');
        }
    }).catch(()=>{ showLoading(false); showAlert('err','Action failed.'); });
}

// ── Manual ticket ────────────────────────────────────────────
function openManualTicket() {
    document.getElementById('manualSubject').value = '';
    document.getElementById('manualMessage').value = '';
    openModal('manualTicketModal');
}
function submitManualTicket() {
    const subject = document.getElementById('manualSubject').value.trim();
    const message = document.getElementById('manualMessage').value.trim();
    const assigned_to = document.getElementById('manualAssignTo').value;
    const priority = document.getElementById('manualPriority').value;
    const timeline = document.getElementById('manualTimeline').value;
    if (!subject || !message || !assigned_to) { alert('Please fill subject, message and assignee.'); return; }
    showLoading(true);
    const fd = new FormData();
    fd.append('manual_ticket','1');
    fd.append('subject', subject);
    fd.append('message', message);
    fd.append('assigned_to', assigned_to);
    fd.append('priority', priority);
    fd.append('timeline', timeline);
    fetch(currentPage, { method:'POST', body: fd }).then(r=>r.json()).then(res=>{
        showLoading(false);
        closeModal('manualTicketModal');
        if (res.ok) showAlert('ok', `Ticket ${res.ticket} created successfully.`);
        else showAlert('err', res.msg || 'Could not create ticket.');
    }).catch(()=>{ showLoading(false); showAlert('err','Could not create ticket.'); });
}

// ── Add Task (Admin → Employee) ─────────────────────────────
document.getElementById('taskRaiseTicket')?.addEventListener('change', function(){
    document.getElementById('taskTicketFields').style.display = this.checked ? 'block' : 'none';
});
let addTaskDate = '';
function openAddTask(planDate) {
    addTaskDate = planDate;
    document.getElementById('taskText').value = '';
    document.getElementById('taskTime').value = '';
    document.getElementById('taskRaiseTicket').checked = false;
    document.getElementById('taskTicketFields').style.display = 'none';
    const d = new Date(planDate+'T00:00:00');
    document.getElementById('addTaskSummaryText').textContent = `Assign a task to ${currentEmpName} for ${d.toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'})}.`;
    openModal('addTaskModal');
}
function submitAddTask() {
    const text = document.getElementById('taskText').value.trim();
    if (!text) { alert('Please enter the task.'); return; }
    showLoading(true);
    const fd = new FormData();
    fd.append('add_task','1');
    fd.append('employee_id', currentEmpId);
    fd.append('employee_name', currentEmpName);
    fd.append('plan_date', addTaskDate);
    fd.append('task_text', text);
    fd.append('task_time', document.getElementById('taskTime').value.trim());
    fd.append('raise_ticket', document.getElementById('taskRaiseTicket').checked ? '1' : '');
    fd.append('priority', document.getElementById('taskPriority').value);
    fd.append('timeline', document.getElementById('taskTimeline').value);
    fetch(currentPage, { method:'POST', body: fd }).then(r=>r.json()).then(res=>{
        showLoading(false);
        closeModal('addTaskModal');
        if (res.ok) { showAlert('ok', `Task added.${res.ticket?' Ticket '+res.ticket+' created.':''}`); loadEntries(); }
        else showAlert('err', res.msg || 'Could not add task.');
    }).catch(()=>{ showLoading(false); showAlert('err','Could not add task.'); });
}

// ── PDF exports ──────────────────────────────────────────────
function priorityRowHtml(p,i){
    if (typeof p === 'string') return `<div style="font-size:11px;padding:3px 6px;background:#f8fafc;margin-bottom:3px;"><b>${i+1}.</b> ${escHtml(p)}</div>`;
    const badge = p.type==='admin' ? ' [HR]' : '';
    const time = p.time ? ` (${escHtml(p.time)})` : '';
    return `<div style="font-size:11px;padding:3px 6px;background:#f8fafc;margin-bottom:3px;"><b>${i+1}.</b> ${escHtml(p.text||'')}${badge}${time}</div>`;
}
function downloadEmployeeMonthPDF() {
    if (!allEntries.length) { alert('No entries loaded for this employee/month.'); return; }
    let body = allEntries.map(data=>{
        const d = new Date(data.plan_date+'T00:00:00');
        const pris = safeJson(data.priorities) || [];
        const slots = safeJson(data.schedule_slots) || {};
        const slotHtml = Object.keys(slots).map(s=>`<div style="font-size:11px;padding:3px 6px;border-bottom:1px solid #f1f5f9;"><b>${s}</b>: ${escHtml(slots[s]||'—')}</div>`).join('');
        return `<div style="page-break-inside:avoid;margin-bottom:20px;border-bottom:1px solid #cbd5e1;padding-bottom:14px;">
            <h3 style="font-size:14px;color:#0d1f3c;">${d.toLocaleDateString('en-IN',{weekday:'long',day:'2-digit',month:'long',year:'numeric'})} — ${data.approval_status||'pending'}</h3>
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:6px;">
                <div><b style="font-size:11px;color:#c0392b;">PRIORITIES</b>${pris.map(priorityRowHtml).join('')||'—'}</div>
                <div><b style="font-size:11px;color:#c0392b;">SCHEDULE</b>${slotHtml||'—'}</div>
            </div>
        </div>`;
    }).join('');
    openPrintWindow(`Planner — ${currentEmpName} — ${currentMonth}`, body);
}
function downloadHRSummaryPDF() {
    const rows = Array.from(document.querySelectorAll('#summaryTableBody tr')).map(tr=>{
        const clone = tr.cloneNode(true);
        const lastTd = clone.querySelector('td:last-child');
        if (lastTd) lastTd.remove();
        return clone.outerHTML;
    }).join('');
    if (!rows) { alert('No summary data loaded.'); return; }
    const body = `<table style="width:100%;border-collapse:collapse;font-size:12px;">
        <thead><tr style="text-align:left;border-bottom:2px solid #cbd5e1;">
            <th style="padding:6px;">Employee</th><th>Dept</th><th>Total</th><th>Pending</th><th>Approved</th><th>Declined</th>
        </tr></thead><tbody>${rows}</tbody></table>`;
    openPrintWindow(`HR Planner Summary — ${document.getElementById('filterMonth').value}`, body);
}
function openPrintWindow(title, bodyHtml) {
    const win = window.open('','_blank');
    win.document.write(`<html><head><meta charset="utf-8"><title>${escHtml(title)}</title></head>
        <body style="font-family:'Segoe UI',sans-serif;color:#1e293b;padding:28px;">
        <h1 style="font-size:20px;color:#0d1f3c;border-bottom:2px solid #e2e8f0;padding-bottom:12px;">${escHtml(title)}</h1>
        ${bodyHtml}</body></html>`);
    win.document.close(); win.focus();
    setTimeout(()=>win.print(), 500);
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
