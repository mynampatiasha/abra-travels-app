<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
session_start();

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed: " . mysqli_connect_error());
mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
// isUser();

$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// AUTO-CREATE TABLE
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

// Migrate old schema if needed
$chk = mysqli_query($con, "SHOW COLUMNS FROM hr_daily_planner LIKE 'priorities'");
if ($chk && mysqli_num_rows($chk) == 0) {
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN priorities JSON DEFAULT NULL AFTER plan_date");
}
$chk2 = mysqli_query($con, "SHOW COLUMNS FROM hr_daily_planner LIKE 'schedule_slots'");
if ($chk2 && mysqli_num_rows($chk2) == 0) {
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN schedule_slots JSON DEFAULT NULL AFTER goals_notes");
}
$chk3 = mysqli_query($con, "SHOW COLUMNS FROM hr_daily_planner LIKE 'approval_status'");
if ($chk3 && mysqli_num_rows($chk3) == 0) {
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN approval_status ENUM('pending','approved','declined') NOT NULL DEFAULT 'pending'");
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN approval_reason TEXT DEFAULT NULL");
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN approved_by VARCHAR(255) DEFAULT NULL");
    mysqli_query($con, "ALTER TABLE hr_daily_planner ADD COLUMN approved_at DATETIME DEFAULT NULL");
}

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE
// Supports both Flutter WebView (email via URL) and browser session
// =========================================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$session_name = trim($_SESSION['user_name'] ?? '');
$emp_data = null;

// ---------------------------------------------------------------
// STEP 1: Flutter WebView path — email passed via URL parameter
// ---------------------------------------------------------------
if (!empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($con, $currentUserEmail);
    $eq = mysqli_query($con, "
        SELECT id, employee_id, name, timings, department, position 
        FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
        // Keep session in sync for any session-dependent code below
        $_SESSION['user_name'] = $emp_data['name'];
        $session_name = $emp_data['name'];
    }
}

// ---------------------------------------------------------------
// STEP 2: Browser/session path — fallback to session user_name
// ---------------------------------------------------------------
if (!$emp_data && $session_name) {
    $safe_name = mysqli_real_escape_string($con, $session_name);
    $eq = mysqli_query($con, "SELECT id, employee_id, name, timings, department, position FROM hr_employees WHERE name = '$safe_name' AND status = 'Active' LIMIT 1");
    if (!$eq || mysqli_num_rows($eq) == 0) {
        $eq = mysqli_query($con, "SELECT id, employee_id, name, timings, department, position FROM hr_employees WHERE name LIKE '%$safe_name%' AND status = 'Active' LIMIT 1");
    }
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
    }
}

// ---------------------------------------------------------------
// STEP 3: Still nothing found — stop with a clear error message
// ---------------------------------------------------------------
if (!$emp_data) {
    die("
        <div style='font-family:sans-serif; max-width:600px; margin:60px auto; padding:30px; 
                    border:2px solid #ef4444; border-radius:12px; background:#fef2f2; color:#b91c1c;'>
            <h2 style='margin-top:0;'>&#10060; Authentication Failed</h2>
            <p>Could not identify your employee record. Please try one of the following:</p>
            <ul>
                <li>Make sure your email address is registered in the HR system</li>
                <li>Contact HR to link your account to an employee record</li>
            </ul>
            <hr style='border-color:#fecaca;'>
            <p style='font-size:13px; color:#dc2626;'>
                <strong>Debug info:</strong><br>
                Email received: " . htmlspecialchars($currentUserEmail ?: '(none)') . "<br>
                Session name: "  . htmlspecialchars($session_name  ?: '(none)') . "
            </p>
        </div>
    ");
}

$emp_id   = $emp_data['employee_id'];
$emp_name = $emp_data['name'];
$timings  = $emp_data['timings'] ?? '';

$url_email = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';

// Auto-cleanup any previously imported blank rows for this user
$safe_eid_clean = mysqli_real_escape_string($con, $emp_id);
mysqli_query($con, "DELETE FROM hr_daily_planner WHERE employee_id='$safe_eid_clean' AND 
    (priorities IS NULL OR priorities = '[]' OR priorities = 'null' OR priorities = '') AND 
    (todo_notes IS NULL OR todo_notes = '') AND 
    (if_have_time IS NULL OR if_have_time = '') AND 
    (focus_notes IS NULL OR focus_notes = '') AND 
    (goals_notes IS NULL OR goals_notes = '') AND 
    (schedule_slots IS NULL OR schedule_slots = '{}' OR schedule_slots = 'null' OR schedule_slots = '[]' OR schedule_slots = '')");

// Parse timings to get start/end hour slots
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
    if (preg_match('/(\d{1,2}:\d{2})\s*[-–TO]+\s*(\d{1,2}:\d{2})/', $ts, $m)) {
        $sh = (int)explode(':', $m[1])[0];
        $eh = (int)explode(':', $m[2])[0];
        $slots = [];
        for ($h = $sh; $h <= $eh; $h++) {
            $ampm = $h < 12 ? 'AM' : 'PM';
            $disp = $h % 12 == 0 ? 12 : $h % 12;
            $slots[] = sprintf('%02d:00 %s', $disp, $ampm);
        }
        return $slots;
    }
    return $default;
}

$time_slots = parseTimingSlots($timings);

// =========================================================================
// HANDLE SAVE
// =========================================================================
// Handle CSV import
$import_msg = ''; $import_type = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['import_csv'])) {
    if (isset($_FILES['import_file']) && $_FILES['import_file']['error'] == 0) {
        $handle = fopen($_FILES['import_file']['tmp_name'], 'r');
        fgetcsv($handle); // skip header
        $imported = 0; $skipped = 0;
        $safe_eid = mysqli_real_escape_string($con, $emp_id);
        $safe_ename = mysqli_real_escape_string($con, $emp_name);
        while (($row = fgetcsv($handle)) !== false) {
            if (empty($row[0])) continue;
            $plan_date_raw = trim($row[0]);
            $expected_day  = trim($row[1] ?? '');
            $plan_date = '';
            
            if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $plan_date_raw, $dm) && checkdate((int)$dm[2], (int)$dm[3], (int)$dm[1])) {
                $plan_date = $plan_date_raw;
            } else {
                // Excel changed the date format (e.g. 6/1/2026). Try common formats and validate against the expected Day.
                $formats = ['n/j/Y', 'j/n/Y', 'm/d/Y', 'd/m/Y', 'Y/m/d'];
                foreach ($formats as $fmt) {
                    $d = DateTime::createFromFormat($fmt, $plan_date_raw);
                    if ($d && strcasecmp($d->format('l'), $expected_day) === 0) {
                        $plan_date = $d->format('Y-m-d');
                        break;
                    }
                }
                // Fallback to basic strtotime
                if (!$plan_date) {
                    $ts = strtotime($plan_date_raw);
                    if ($ts && strcasecmp(date('l', $ts), $expected_day) === 0) {
                        $plan_date = date('Y-m-d', $ts);
                    }
                }
            }
            
            if (empty($plan_date)) {
                $skipped++;
                continue;
            }
            $pris = array_values(array_filter(array_map('trim', explode('|', trim($row[3]??'')))));
            $todo   = trim($row[4]??'');
            $iftime = trim($row[5]??'');
            $focus  = trim($row[6]??'');
            $goals  = trim($row[7]??'');
            $slots  = [];
            foreach ($time_slots as $i => $slot) { $v = trim($row[8+$i]??''); if ($v!=='') $slots[$slot]=$v; }
            
            // Skip importing if the user didn't fill in any data for this date
            if (empty($pris) && empty($todo) && empty($iftime) && empty($focus) && empty($goals) && empty($slots)) {
                $skipped++;
                continue;
            }

            $pris_json = mysqli_real_escape_string($con, json_encode($pris));
            $todo   = mysqli_real_escape_string($con, $todo);
            $iftime = mysqli_real_escape_string($con, $iftime);
            $focus  = mysqli_real_escape_string($con, $focus);
            $goals  = mysqli_real_escape_string($con, $goals);
            $slots_json = mysqli_real_escape_string($con, json_encode($slots));
            $safe_date  = mysqli_real_escape_string($con, $plan_date);
            $sql = "INSERT INTO hr_daily_planner (employee_id,employee_name,plan_date,priorities,todo_notes,if_have_time,focus_notes,goals_notes,schedule_slots)
                VALUES ('$safe_eid','$safe_ename','$safe_date','$pris_json','$todo','$iftime','$focus','$goals','$slots_json')
                ON DUPLICATE KEY UPDATE priorities='$pris_json',todo_notes='$todo',if_have_time='$iftime',focus_notes='$focus',goals_notes='$goals',schedule_slots='$slots_json',updated_at=NOW()";
            if (mysqli_query($con, $sql)) $imported++; else $skipped++;
        }
        fclose($handle);
        $import_msg = "Import complete! $imported imported" . ($skipped ? ", $skipped failed." : ".");
        $import_type = 'ok';
    } else { $import_msg = 'Select a valid CSV file.'; $import_type = 'err'; }
}

$save_msg = ''; $save_type = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_planner'])) {
    $plan_date  = $_POST['plan_date'] ?? date('Y-m-d');
    $safe_date  = mysqli_real_escape_string($con, $plan_date);
    $safe_eid   = mysqli_real_escape_string($con, $emp_id);
    $safe_ename = mysqli_real_escape_string($con, $emp_name);
    $pris_input = $_POST['priorities_json'] ?? '[]';
    $pris_decoded = json_decode($pris_input, true);
    if (!is_array($pris_decoded)) $pris_decoded = [];
    $pris_clean = [];
    foreach ($pris_decoded as $p) {
        if (!is_array($p)) continue;
        $text = trim($p['text'] ?? '');
        if ($text === '') continue;
        $pris_clean[] = [
            'type'        => ($p['type'] ?? 'self') === 'admin' ? 'admin' : 'self',
            'text'        => $text,
            'time'        => trim($p['time'] ?? ''),
            'completed'   => !empty($p['completed']),
            'assigned_by' => trim($p['assigned_by'] ?? '')
        ];
    }
    $pris_json  = mysqli_real_escape_string($con, json_encode($pris_clean));
    $todo   = mysqli_real_escape_string($con, $_POST['todo_notes'] ?? '');
    $iftime = mysqli_real_escape_string($con, $_POST['if_have_time'] ?? '');
    $focus  = mysqli_real_escape_string($con, $_POST['focus_notes'] ?? '');
    $goals  = mysqli_real_escape_string($con, $_POST['goals_notes'] ?? '');
    $slots_clean = [];
    foreach ($_POST['schedule'] ?? [] as $k => $v) $slots_clean[$k] = $v;
    $slots_json = mysqli_real_escape_string($con, json_encode($slots_clean));
    $sql = "INSERT INTO hr_daily_planner (employee_id,employee_name,plan_date,priorities,todo_notes,if_have_time,focus_notes,goals_notes,schedule_slots)
        VALUES ('$safe_eid','$safe_ename','$safe_date','$pris_json','$todo','$iftime','$focus','$goals','$slots_json')
        ON DUPLICATE KEY UPDATE priorities='$pris_json',todo_notes='$todo',if_have_time='$iftime',focus_notes='$focus',goals_notes='$goals',schedule_slots='$slots_json',updated_at=NOW()";
    if (mysqli_query($con, $sql)) { $save_msg = 'Planner saved for '.date('d M Y', strtotime($plan_date)).'!'; $save_type = 'ok'; }
    else { $save_msg = 'Error: '.mysqli_error($con); $save_type = 'err'; }
}

// =========================================================================
// LOAD DATA FOR SELECTED DATE (AJAX)
// =========================================================================
if (isset($_GET['load_date'])) {
    $req_date = $_GET['load_date'];
    $safe_rd  = mysqli_real_escape_string($con, $req_date);
    $safe_eid = mysqli_real_escape_string($con, $emp_id);
    $lq = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE employee_id='$safe_eid' AND plan_date='$safe_rd' LIMIT 1");
    $row = ($lq && mysqli_num_rows($lq) > 0) ? mysqli_fetch_assoc($lq) : null;
    if ($row && empty($row['priorities'])) {
        $legacy = [];
        for ($i=1; $i<=7; $i++) if (!empty($row["priority_$i"])) $legacy[] = $row["priority_$i"];
        if (!empty($legacy)) $row['priorities'] = json_encode($legacy);
    }
    header('Content-Type: application/json');
    echo json_encode($row ?: ['empty' => true]);
    exit;
}

// AJAX: history months list
if (isset($_GET['history_months'])) {
    $safe_eid = mysqli_real_escape_string($con, $emp_id);
    $hq = mysqli_query($con, "SELECT DATE_FORMAT(plan_date,'%Y-%m') as ym, DATE_FORMAT(plan_date,'%M %Y') as label, COUNT(*) as cnt
        FROM hr_daily_planner WHERE employee_id='$safe_eid'
        GROUP BY ym ORDER BY ym DESC");
    $months = [];
    if ($hq) while ($hr = mysqli_fetch_assoc($hq)) $months[] = $hr;
    header('Content-Type: application/json');
    echo json_encode($months);
    exit;
}

// AJAX: entries for a month
if (isset($_GET['history_month'])) {
    $safe_eid = mysqli_real_escape_string($con, $emp_id);
    $safe_ym  = mysqli_real_escape_string($con, $_GET['history_month']);
    $hq = mysqli_query($con, "SELECT * FROM hr_daily_planner
        WHERE employee_id='$safe_eid' AND DATE_FORMAT(plan_date,'%Y-%m')='$safe_ym'
        ORDER BY plan_date ASC");
    $entries = [];
    if ($hq) while ($hr = mysqli_fetch_assoc($hq)) $entries[] = $hr;
    header('Content-Type: application/json');
    echo json_encode($entries);
    exit;
}

// AJAX: single entry view
if (isset($_GET['view_entry'])) {
    $safe_eid = mysqli_real_escape_string($con, $emp_id);
    $safe_id  = intval($_GET['view_entry']);
    $vq = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE id=$safe_id AND employee_id='$safe_eid' LIMIT 1");
    $row = ($vq && mysqli_num_rows($vq) > 0) ? mysqli_fetch_assoc($vq) : null;
    if ($row && empty($row['priorities'])) {
        $legacy = [];
        for ($i=1; $i<=7; $i++) if (!empty($row["priority_$i"])) $legacy[] = $row["priority_$i"];
        if (!empty($legacy)) $row['priorities'] = json_encode($legacy);
    }
    header('Content-Type: application/json');
    echo json_encode($row ?: ['empty' => true]);
    exit;
}

// AJAX: delete a single entry (cleanup tool)
if (isset($_GET['delete_entry'])) {
    $safe_eid = mysqli_real_escape_string($con, $emp_id);
    $safe_id  = intval($_GET['delete_entry']);
    mysqli_query($con, "DELETE FROM hr_daily_planner WHERE id=$safe_id AND employee_id='$safe_eid'");
    header('Content-Type: application/json');
    echo json_encode(['ok' => true]);
    exit;
}

// CSV Template download
if (isset($_GET['download_template'])) {
    $month_ym = $_GET['download_template'];
    $ts_parts = explode('-', $month_ym);
    if (count($ts_parts) != 2) { echo 'Invalid'; exit; }
    $yr = intval($ts_parts[0]); $mo = intval($ts_parts[1]);
    $days_in_month = cal_days_in_month(CAL_GREGORIAN, $mo, $yr);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=planner_'.$month_ym.'_template.csv');
    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($out, ['Date','Day','Is Sunday','Priorities (use | to separate)','To Do','If I Have Time','Focus','Goals',...$time_slots]);
    $day_names = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    for ($d = 1; $d <= $days_in_month; $d++) {
        $ds  = sprintf('%04d-%02d-%02d', $yr, $mo, $d);
        $dow = date('w', mktime(0,0,0,$mo,$d,$yr));
        $row = [$ds, $day_names[$dow], ($dow==0?'SUNDAY':''), '', '', '', '', ''];
        foreach ($time_slots as $sl) $row[] = '';
        fputcsv($out, $row);
    }
    fclose($out); exit;
}

// Load today's data by default
$today = date('Y-m-d');
$selected_date = $_GET['date'] ?? $today;
$safe_sel = mysqli_real_escape_string($con, $selected_date);
$safe_eid_q = mysqli_real_escape_string($con, $emp_id);
$init_q = mysqli_query($con, "SELECT * FROM hr_daily_planner WHERE employee_id='$safe_eid_q' AND plan_date='$safe_sel' LIMIT 1");
$init_data = ($init_q && mysqli_num_rows($init_q) > 0) ? mysqli_fetch_assoc($init_q) : null;
$init_pris = [];
$init_slots = [];
if ($init_data) {
    if (!empty($init_data['priorities'])) {
        $init_pris = json_decode($init_data['priorities'], true) ?: [];
    } else {
        for ($i=1; $i<=7; $i++) if (!empty($init_data["priority_$i"])) $init_pris[] = $init_data["priority_$i"];
    }
    if (!empty($init_data['schedule_slots'])) {
        $init_slots = json_decode($init_data['schedule_slots'], true) ?: [];
    }
}

// Dates that have entries (for calendar highlights)
$filled_dates = [];
$fq = mysqli_query($con, "SELECT plan_date FROM hr_daily_planner WHERE employee_id='$safe_eid_q' ORDER BY plan_date ASC");
if ($fq) {
    while ($fr = mysqli_fetch_assoc($fq)) {
        $filled_dates[] = $fr['plan_date'];
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'HR'); ?> | Monthly Planner</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
/* ===== DESIGN TOKENS ===== */
:root {
    --navy:   #0d1f3c;
    --navy2:  #153060;
    --blue:   #2563c4;
    --red:    #c0392b;
    --red2:   #e74c3c;
    --amber:  #f59e0b;
    --green:  #10b981;
    --white:  #ffffff;
    --bg:     #f0f4f8;
    --border: #cbd5e1;
    --text:   #1e293b;
    --muted:  #64748b;
    --card:   #ffffff;
    --sunday: #fff0f0;
    --filled: #ecfdf5;
}

* { font-family: 'Outfit', sans-serif; box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--text); }

/* ===== LAYOUT ===== */
.wrap { max-width: 1380px; margin: 0 auto; padding: 20px 16px; }

/* ===== PAGE HEADER ===== */
.page-header {
    background: linear-gradient(135deg, var(--navy) 0%, var(--navy2) 100%);
    border-radius: 14px 14px 0 0;
    padding: 20px 28px;
    display: flex; align-items: center; gap: 16px;
}
.page-header .ph-icon {
    width: 48px; height: 48px;
    background: rgba(255,255,255,.12); border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    color: var(--amber); font-size: 20px; flex-shrink: 0;
}
.page-header h1 { color: #fff; font-weight: 800; font-size: 19px; margin: 0; }
.page-header p  { color: rgba(255,255,255,.6); font-size: 12px; margin: 2px 0 0; }
.page-header .emp-chip {
    margin-left: auto;
    background: rgba(255,255,255,.14);
    border-radius: 30px; padding: 8px 18px;
    color: #fff; font-size: 13px; font-weight: 600;
    white-space: nowrap;
}

/* ===== CARD SHELL ===== */
.card-shell {
    background: var(--card);
    border-radius: 0 0 14px 14px;
    box-shadow: 0 8px 30px rgba(13,31,61,.08);
    padding: 24px 28px;
}

/* ===== ALERT ===== */
.alert-ok  { background:#d1fae5; color:#065f46; border:1px solid #6ee7b7; border-radius:8px; padding:12px 16px; margin-bottom:18px; font-weight:600; font-size:14px; }
.alert-err { background:#fee2e2; color:#991b1b; border:1px solid #fca5a5; border-radius:8px; padding:12px 16px; margin-bottom:18px; font-weight:600; font-size:14px; }

/* ===== TWO-COLUMN GRID ===== */
.planner-grid {
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: 24px;
    align-items: start;
}
@media(max-width:900px) { .planner-grid { grid-template-columns: 1fr; } }

/* ===== MINI CALENDAR ===== */
.cal-wrap {
    border: 1.5px solid var(--border);
    border-radius: 12px;
    overflow: hidden;
    position: sticky;
    top: 20px;
}
.cal-header {
    background: linear-gradient(135deg, var(--navy) 0%, var(--navy2) 100%);
    padding: 14px;
    display: flex; align-items: center; justify-content: space-between;
}
.cal-header span { color: #fff; font-weight: 700; font-size: 14px; }
.cal-nav-btn {
    background: rgba(255,255,255,.15); border: none; color: #fff;
    width: 28px; height: 28px; border-radius: 6px; cursor: pointer;
    font-size: 13px; display: flex; align-items: center; justify-content: center;
    transition: background .2s;
}
.cal-nav-btn:hover { background: rgba(255,255,255,.28); }
.cal-grid { padding: 10px; background: #fff; }
.cal-weekdays {
    display: grid; grid-template-columns: repeat(7, 1fr);
    margin-bottom: 4px;
}
.cal-weekdays span {
    text-align: center; font-size: 11px; font-weight: 700;
    color: var(--muted); padding: 4px 0;
}
.cal-weekdays span.sun-label { color: var(--red2); }
.cal-days { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; }
.cal-day {
    aspect-ratio: 1; display: flex; align-items: center; justify-content: center;
    border-radius: 6px; font-size: 12px; font-weight: 600; cursor: pointer;
    transition: all .15s; color: var(--text);
    position: relative;
}
.cal-day:hover:not(.cal-empty):not(.cal-sunday-blocked) {
    background: #dbeafe; color: var(--navy);
}
.cal-day.cal-selected  { background: var(--navy2); color: #fff !important; }
.cal-day.cal-today:not(.cal-selected) { border: 2px solid var(--blue); color: var(--blue); font-weight: 800; }
.cal-day.cal-empty     { cursor: default; }
.cal-day.cal-sunday    { color: var(--red2); }
.cal-day.cal-filled::after {
    content: '';
    position: absolute; bottom: 3px; left: 50%; transform: translateX(-50%);
    width: 5px; height: 5px; border-radius: 50%;
    background: var(--green);
}
.cal-day.cal-selected.cal-filled::after { background: rgba(255,255,255,.7); }
.cal-legend {
    padding: 8px 10px;
    border-top: 1px solid var(--border);
    display: flex; gap: 12px; flex-wrap: wrap;
}
.cal-legend-item { display: flex; align-items: center; gap: 5px; font-size: 11px; color: var(--muted); font-weight: 600; }
.cal-legend-dot  { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }

/* ===== DATE DISPLAY BAR ===== */
.date-bar {
    display: flex; align-items: center; gap: 12px;
    background: linear-gradient(135deg, #f8fafc, #f1f5f9);
    border: 1.5px solid var(--border);
    border-radius: 10px; padding: 12px 18px;
    margin-bottom: 20px;
}
.date-bar .db-date { font-size: 17px; font-weight: 800; color: var(--navy); }
.date-bar .db-day  { font-size: 13px; color: var(--muted); font-weight: 600; }
.date-bar .db-sunday-warn {
    margin-left: auto;
    background: #fff0f0; border: 1px solid #fca5a5;
    border-radius: 6px; padding: 5px 12px;
    font-size: 12px; font-weight: 700; color: var(--red2);
    display: flex; align-items: center; gap: 6px;
}
.date-bar .db-saved-badge {
    margin-left: auto;
    background: var(--filled); border: 1px solid #6ee7b7;
    border-radius: 6px; padding: 5px 12px;
    font-size: 12px; font-weight: 700; color: #065f46;
    display: flex; align-items: center; gap: 6px;
}

/* ===== SECTION LABELS (red outlined like the physical planner) ===== */
.section-label {
    display: flex; align-items: center; gap: 0;
    margin-bottom: 10px;
}
.section-label::before,
.section-label::after {
    content: ''; flex: 1;
    height: 1.5px; background: var(--red);
}
.section-label span {
    padding: 0 12px;
    font-size: 12px; font-weight: 700;
    color: var(--red); letter-spacing: .5px;
    text-transform: uppercase; white-space: nowrap;
}

/* ===== PRIORITIES ===== */
.priorities-wrap { margin-bottom: 20px; }
.priority-title {
    font-size: 14px; font-weight: 800;
    color: var(--red); text-align: center;
    text-transform: uppercase; letter-spacing: 1px;
    margin-bottom: 12px;
}
.priority-row {
    display: flex; align-items: center; gap: 10px;
    margin-bottom: 8px;
}
.priority-num {
    width: 22px; font-size: 13px; font-weight: 800;
    color: var(--navy); flex-shrink: 0;
}
.priority-input {
    flex: 1; border: none; border-bottom: 1.5px solid var(--border);
    padding: 6px 4px; font-size: 13px; font-weight: 500;
    background: transparent; outline: none; color: var(--text);
    transition: border-color .2s;
}
.priority-input:focus { border-bottom-color: var(--navy); }

/* ===== TEXTAREA BOXES ===== */
.box-section { margin-bottom: 18px; }
.box-textarea {
    width: 100%; border: 1.5px solid var(--red);
    border-radius: 6px; padding: 12px;
    font-size: 13px; font-weight: 500; color: var(--text);
    resize: vertical; min-height: 100px;
    background: #fff; outline: none;
    transition: border-color .2s;
}
.box-textarea:focus { border-color: var(--navy); }

/* ===== FOCUS + GOALS SIDE BY SIDE ===== */
.focus-goals-row {
    display: grid; grid-template-columns: 1fr 1fr; gap: 14px;
    margin-bottom: 18px;
}
@media(max-width:600px) { .focus-goals-row { grid-template-columns: 1fr; } }
.focus-goals-row .box-textarea { min-height: 160px; }

/* ===== SCHEDULE ===== */
.schedule-wrap { margin-bottom: 20px; }
.schedule-header {
    background: var(--navy); color: #fff;
    font-size: 13px; font-weight: 800;
    text-align: center; padding: 10px;
    border-radius: 8px 8px 0 0; letter-spacing: .5px;
    text-transform: uppercase;
}
.schedule-rows { border: 1.5px solid var(--border); border-top: none; border-radius: 0 0 8px 8px; overflow: hidden; }
.schedule-row {
    display: flex; align-items: center;
    border-bottom: 1px solid #f1f5f9;
}
.schedule-row:last-child { border-bottom: none; }
.schedule-time {
    width: 90px; flex-shrink: 0;
    font-size: 12px; font-weight: 700;
    color: var(--navy); padding: 8px 10px;
    background: #f8fafc; border-right: 1.5px solid var(--border);
}
.schedule-input {
    flex: 1; border: none; padding: 8px 12px;
    font-size: 13px; font-weight: 500; color: var(--text);
    background: transparent; outline: none;
}
.schedule-input:focus { background: #f8faff; }
.schedule-row:nth-child(even) { background: #fafbfd; }

/* ===== RIGHT PANEL LAYOUT ===== */
.right-panel { display: flex; flex-direction: column; gap: 0; }
.planner-right-inner {
    display: grid;
    grid-template-columns: 1fr 340px;
    gap: 20px;
    align-items: start;
}
@media(max-width:1100px) { .planner-right-inner { grid-template-columns: 1fr; } }

/* ===== SAVE BUTTON ===== */
.btn-save-planner {
    background: linear-gradient(135deg, var(--navy2), var(--blue));
    color: #fff; border: none; border-radius: 10px;
    padding: 14px 32px; font-size: 15px; font-weight: 800;
    cursor: pointer; width: 100%;
    transition: opacity .2s, transform .1s;
    letter-spacing: .3px;
    margin-top: 10px;
}
.btn-save-planner:hover { opacity: .92; transform: translateY(-1px); }

.btn-back {
    background: #fff; border: 1.5px solid var(--border);
    color: var(--navy); border-radius: 8px;
    padding: 8px 18px; font-size: 13px; font-weight: 700;
    cursor: pointer; text-decoration: none;
    display: inline-flex; align-items: center; gap: 6px;
    margin-bottom: 16px; transition: all .2s;
}
.btn-back:hover { background: #f1f5f9; text-decoration: none; color: var(--navy); }

/* ===== LOADING OVERLAY ===== */
.loading-overlay {
    position: fixed; inset: 0;
    background: rgba(13,31,61,.35);
    display: none; align-items: center; justify-content: center;
    z-index: 9999;
}
.loading-overlay.active { display: flex; }
.loading-spinner {
    background: #fff; border-radius: 14px; padding: 30px 40px;
    text-align: center;
}
.spinner-ring {
    width: 44px; height: 44px;
    border: 4px solid #e2e8f0;
    border-top-color: var(--navy2);
    border-radius: 50%;
    animation: spin .8s linear infinite;
    margin: 0 auto 12px;
}
@keyframes spin { to { transform: rotate(360deg); } }
.top-actions{display:flex;gap:10px;margin-bottom:18px;flex-wrap:wrap;align-items:center;}
.btn-history{background:linear-gradient(135deg,#7c3aed,#6d28d9);color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;}
.btn-history:hover{opacity:.9;}
.btn-import{background:linear-gradient(135deg,#059669,#047857);color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;}
.btn-import:hover{opacity:.9;}
.modal-overlay{position:fixed;inset:0;background:rgba(13,31,61,.5);z-index:8000;display:none;align-items:flex-start;justify-content:center;padding:40px 16px;overflow-y:auto;}
.modal-overlay.active{display:flex;}
.modal-box{background:#fff;border-radius:14px;width:100%;max-width:820px;box-shadow:0 20px 60px rgba(0,0,0,.2);overflow:hidden;margin:auto;}
.modal-head{background:linear-gradient(135deg,var(--navy),var(--navy2));padding:18px 24px;display:flex;align-items:center;gap:12px;}
.modal-head h3{color:#fff;font-weight:800;font-size:16px;margin:0;flex:1;}
.modal-close{background:rgba(255,255,255,.15);border:none;color:#fff;width:30px;height:30px;border-radius:6px;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;}
.modal-body{padding:22px 24px;}
.month-card{border:1.5px solid var(--border);border-radius:10px;margin-bottom:12px;overflow:hidden;}
.month-card-head{background:#f8fafc;padding:12px 16px;display:flex;align-items:center;justify-content:space-between;cursor:pointer;}
.month-card-head:hover{background:#f1f5f9;}
.mch-label{font-weight:800;color:var(--navy);font-size:14px;}
.mch-count{background:var(--navy2);color:#fff;border-radius:20px;padding:3px 11px;font-size:11px;font-weight:700;}
.month-card-body{display:none;padding:12px 16px;border-top:1.5px solid var(--border);}
.month-card-body.open{display:block;}
.entry-row{display:flex;align-items:center;justify-content:space-between;padding:8px 12px;border-radius:8px;margin-bottom:6px;background:#f8fafc;border:1px solid #e2e8f0;}
.entry-date{font-weight:700;color:var(--navy);font-size:13px;}
.entry-day{font-size:11px;color:var(--muted);font-weight:600;}
.btn-view-entry{background:var(--blue);color:#fff;border:none;border-radius:6px;padding:5px 13px;font-size:12px;font-weight:700;cursor:pointer;}
.btn-pdf-entry{background:var(--red2);color:#fff;border:none;border-radius:6px;padding:5px 13px;font-size:12px;font-weight:700;cursor:pointer;}
.btn-pdf-download{background:linear-gradient(135deg,var(--red),var(--red2));color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:13px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;}
.view-section{margin-bottom:16px;}
.view-section-title{font-size:11px;font-weight:800;color:var(--red);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;}
.view-text-box{background:#f8fafc;border-radius:8px;padding:12px;font-size:13px;white-space:pre-wrap;min-height:50px;}
.view-schedule-row{display:flex;gap:10px;padding:5px 8px;font-size:12px;border-bottom:1px solid #f1f5f9;}
.vs-time{font-weight:800;color:var(--navy);width:80px;flex-shrink:0;}
.import-step{margin-bottom:20px;}
.import-step-title{font-weight:800;font-size:13px;color:var(--navy);margin-bottom:10px;display:flex;align-items:center;gap:8px;}
.step-num{width:24px;height:24px;background:var(--navy2);color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;flex-shrink:0;}
.upload-zone{border:2.5px dashed var(--border);border-radius:10px;padding:28px;text-align:center;cursor:pointer;background:#f8fafc;}
.upload-zone:hover{border-color:var(--green);background:#f0fdf4;}
.btn-do-import{background:linear-gradient(135deg,var(--navy2),var(--blue));color:#fff;border:none;border-radius:8px;padding:11px 24px;font-size:14px;font-weight:800;cursor:pointer;width:100%;margin-top:10px;}
.priority-del{background:none;border:none;color:#ef4444;cursor:pointer;padding:2px 5px;font-size:14px;opacity:.6;}
.priority-del:hover{opacity:1;}
.btn-add-priority{background:none;border:1.5px dashed var(--border);color:var(--blue);border-radius:6px;padding:6px 14px;font-size:12px;font-weight:700;cursor:pointer;width:100%;margin-top:6px;display:flex;align-items:center;justify-content:center;gap:6px;}
.btn-add-priority:hover{border-color:var(--blue);background:#eff6ff;}
.history-section{background:#fff;border:1.5px solid var(--border);border-radius:12px;margin-bottom:20px;overflow:hidden;}
.history-section-head{background:linear-gradient(135deg,#7c3aed,#6d28d9);padding:16px 22px;display:flex;align-items:center;gap:12px;}
.history-section-head h3{color:#fff;font-weight:800;font-size:16px;margin:0;flex:1;}
.history-close{background:rgba(255,255,255,.15);border:none;color:#fff;width:28px;height:28px;border-radius:6px;cursor:pointer;font-size:14px;display:flex;align-items:center;justify-content:center;}
.history-close:hover{background:rgba(255,255,255,.28);}
.history-section-body{padding:18px 22px;max-height:520px;overflow-y:auto;}
.btn-month-pdf{background:linear-gradient(135deg,var(--red),var(--red2));color:#fff;border:none;border-radius:6px;padding:5px 13px;font-size:11px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:5px;}
.btn-month-pdf:hover{opacity:.9;}
.btn-del-entry{background:#fff;border:1.5px solid #fca5a5;color:#dc2626;border-radius:6px;padding:5px 9px;font-size:12px;cursor:pointer;}
.btn-del-entry:hover{background:#fee2e2;}
.db-approval-badge{border-radius:6px;padding:5px 12px;font-size:12px;font-weight:700;display:flex;align-items:center;gap:6px;}
.db-approval-pending{background:#fef3c7;border:1px solid #fcd34d;color:#92400e;}
.db-approval-approved{background:#d1fae5;border:1px solid #6ee7b7;color:#065f46;}
.db-approval-declined{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;}
.decline-reason-box{background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;margin-bottom:18px;font-size:12px;color:#991b1b;}
.status-badge-sm{display:inline-flex;align-items:center;gap:4px;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;}
.status-pending{background:#fef3c7;color:#92400e;}
.status-approved{background:#d1fae5;color:#065f46;}
.status-declined{background:#fee2e2;color:#991b1b;}
</style>
</head>
<body>

<div class="loading-overlay" id="loadingOverlay">
    <div class="loading-spinner">
        <div class="spinner-ring"></div>
        <div style="font-weight:700;color:var(--navy);font-size:14px;">Loading planner...</div>
    </div>
</div>

<!-- VIEW ENTRY MODAL -->
<div class="modal-overlay" id="viewEntryModal">
  <div class="modal-box" style="max-width:900px;">
    <div class="modal-head">
      <i class="fas fa-calendar-day" style="color:var(--amber);font-size:18px;"></i>
      <h3 id="viewEntryTitle">Daily Planner Entry</h3>
      <button class="btn-pdf-download" onclick="downloadPDF()" style="margin-right:10px;"><i class="fas fa-file-pdf"></i> Download PDF</button>
      <button class="modal-close" onclick="closeModal('viewEntryModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body" id="viewEntryBody"><div style="text-align:center;padding:30px;">Loading...</div></div>
  </div>
</div>

<!-- IMPORT MODAL -->
<div class="modal-overlay" id="importModal">
  <div class="modal-box" style="max-width:600px;">
    <div class="modal-head" style="background:linear-gradient(135deg,#059669,#047857);">
      <i class="fas fa-file-import" style="color:#a7f3d0;font-size:18px;"></i>
      <h3>Import from CSV</h3>
      <button class="modal-close" onclick="closeModal('importModal')"><i class="fas fa-times"></i></button>
    </div>
    <div class="modal-body">
      <div class="import-step">
        <div class="import-step-title"><div class="step-num">1</div> Select Month &amp; Download Template</div>
        <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
          <input type="month" id="importMonthPicker" style="padding:8px 12px;border:2px solid var(--border);border-radius:8px;font-size:14px;font-weight:600;" value="<?php echo date('Y-m'); ?>"/>
          <a href="#" onclick="downloadTemplate();return false;" style="background:linear-gradient(135deg,#059669,#047857);color:#fff;border-radius:8px;padding:9px 18px;font-size:13px;font-weight:700;text-decoration:none;display:inline-flex;align-items:center;gap:6px;"><i class="fas fa-download"></i> Download Template</a>
        </div>
        <div style="margin-top:10px;background:#fffbeb;border:1px solid #fcd34d;border-radius:7px;padding:10px;font-size:12px;color:#92400e;font-weight:600;">
          <i class="fas fa-lightbulb" style="margin-right:5px;"></i> Sundays marked as SUNDAY. Separate multiple priorities with <strong>|</strong>
        </div>
      </div>
      <div class="import-step">
        <div class="import-step-title"><div class="step-num">2</div> Upload Filled CSV</div>
        <form method="POST" enctype="multipart/form-data">
          <input type="hidden" name="import_csv" value="1"/>
          <?php if(!empty($currentUserEmail)): ?>
          <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES, 'UTF-8'); ?>"/>
          <?php endif; ?>
          <div class="upload-zone" onclick="document.getElementById('importFile').click()">
            <i class="fas fa-cloud-upload-alt" style="font-size:38px;color:var(--green);display:block;margin-bottom:8px;"></i>
            <div style="font-weight:700;color:var(--navy);">Click to select CSV file</div>
            <input type="file" name="import_file" id="importFile" accept=".csv" style="display:none;" onchange="document.getElementById('importFileName').textContent='✓ '+this.files[0].name;"/>
            <div id="importFileName" style="margin-top:6px;font-weight:700;color:var(--green);font-size:13px;"></div>
          </div>
          <button type="submit" class="btn-do-import"><i class="fas fa-upload"></i> Import Now</button>
        </form>
      </div>
    </div>
  </div>
</div>

<div class="wrap">

    <div class="page-header">
        <div class="ph-icon"><i class="fas fa-calendar-day"></i></div>
        <div>
            <h1>Monthly Planner</h1>
            <p>Plan your month — priorities, tasks, schedule</p>
        </div>
        <div class="emp-chip">
            <i class="fas fa-user-circle" style="margin-right:6px;"></i>
            <?php echo htmlspecialchars($emp_name); ?>
            &nbsp;·&nbsp;
            <?php echo htmlspecialchars($emp_data['department'] ?? ''); ?>
        </div>
    </div>

    <div class="card-shell">

        <div class="top-actions">
          <?php
          $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
          $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
          ?>
          <a href="<?php echo $dashboard_url . $url_email; ?>" class="btn-back" style="margin-bottom:0;"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
          <button type="button" class="btn-history" id="tabPlannerBtn" onclick="switchTab('planner')"><i class="fas fa-calendar-day"></i> Monthly Planner</button>
          <button type="button" class="btn-history" id="tabHistoryBtn" onclick="switchTab('history')" style="background:var(--navy);"><i class="fas fa-history"></i> Planner History</button>
          <button type="button" class="btn-import" onclick="openModal('importModal')"><i class="fas fa-file-import"></i> Import</button>
        </div>

        <div id="sectionHistory" style="display:none; padding:10px 0;">
          <div id="historyBody"><div style="text-align:center;padding:30px;color:var(--muted);">Loading...</div></div>
        </div>

        <?php if ($import_msg): ?>
        <div class="alert-<?php echo $import_type; ?>"><i class="fas fa-check-circle"></i> <?php echo htmlspecialchars($import_msg); ?></div>
        <?php endif; ?>

        <?php if ($save_msg): ?>
            <div class="alert-<?php echo $save_type; ?>">
                <i class="fas fa-<?php echo $save_type == 'ok' ? 'check-circle' : 'exclamation-circle'; ?>"></i>
                <?php echo htmlspecialchars($save_msg); ?>
            </div>
        <?php endif; ?>

        <div id="sectionPlanner">
        <form method="POST" id="plannerForm">
            <input type="hidden" name="plan_date" id="hidden_plan_date" value="<?php echo htmlspecialchars($selected_date); ?>"/>
            <input type="hidden" name="save_planner" value="1"/>
            <input type="hidden" name="priorities_json" id="hidden_priorities_json" value=""/>
            <?php if(!empty($currentUserEmail)): ?>
            <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES, 'UTF-8'); ?>"/>
            <?php endif; ?>

            <div class="planner-grid">

                <!-- ====== LEFT: MINI CALENDAR ====== -->
                <div>
                    <div class="cal-wrap">
                        <div class="cal-header">
                            <button type="button" class="cal-nav-btn" id="calPrev"><i class="fas fa-chevron-left"></i></button>
                            <span id="calMonthLabel"></span>
                            <button type="button" class="cal-nav-btn" id="calNext"><i class="fas fa-chevron-right"></i></button>
                        </div>
                        <div class="cal-grid">
                            <div class="cal-weekdays">
                                <span class="sun-label">Su</span>
                                <span>Mo</span><span>Tu</span><span>We</span>
                                <span>Th</span><span>Fr</span><span>Sa</span>
                            </div>
                            <div class="cal-days" id="calDays"></div>
                        </div>
                        <div class="cal-legend">
                            <div class="cal-legend-item">
                                <div class="cal-legend-dot" style="background:var(--green);"></div> Saved
                            </div>
                            <div class="cal-legend-item">
                                <div class="cal-legend-dot" style="background:var(--navy2);"></div> Selected
                            </div>
                            <div class="cal-legend-item" style="color:var(--red2);">
                                <i class="fas fa-sun" style="font-size:9px;"></i> Sunday
                            </div>
                        </div>
                    </div>

                    <!-- Timings badge -->
                    <?php if ($timings): ?>
                    <div style="margin-top:12px;background:#f0f9ff;border:1.5px solid #bae6fd;border-radius:8px;padding:10px 14px;font-size:12px;">
                        <div style="font-weight:700;color:var(--navy);margin-bottom:2px;"><i class="fas fa-clock" style="margin-right:5px;color:var(--blue);"></i>Your Work Timings</div>
                        <div style="color:var(--muted);font-weight:600;"><?php echo htmlspecialchars($timings); ?></div>
                        <div style="color:#94a3b8;font-size:11px;margin-top:3px;">Schedule slots auto-adjusted to your shift</div>
                    </div>
                    <?php endif; ?>
                </div>

                <!-- ====== RIGHT: PLANNER FORM ====== -->
                <div class="right-panel">

                    <!-- DATE BAR -->
                    <div class="date-bar" id="dateBar">
                        <i class="fas fa-calendar-alt" style="color:var(--navy2);font-size:16px;"></i>
                        <div>
                            <div class="db-date" id="dbDateText"><?php echo date('d F Y', strtotime($selected_date)); ?></div>
                            <div class="db-day" id="dbDayText"><?php echo date('l', strtotime($selected_date)); ?></div>
                        </div>
                        <?php
                        $sel_dow = date('N', strtotime($selected_date));
                        $is_sunday = ($sel_dow == 7);
                        ?>
                        <div class="db-sunday-warn" id="sundayWarn" style="<?php echo $is_sunday ? '' : 'display:none;'; ?>">
                            <i class="fas fa-info-circle"></i> Sunday — optional
                        </div>
                        <?php
                        $has_existing = !empty($init_data);
                        $cur_approval = $init_data['approval_status'] ?? 'pending';
                        ?>
                        <div class="db-saved-badge" id="savedBadge" style="<?php echo $has_existing && !$is_sunday ? '' : 'display:none;'; ?>">
                            <i class="fas fa-check-circle"></i> Entry exists — editing
                        </div>
                        <div class="db-approval-badge db-approval-<?php echo $cur_approval; ?>" id="approvalBadge" style="<?php echo $has_existing ? '' : 'display:none;'; ?>">
                            <i class="fas fa-<?php echo $cur_approval==='approved'?'check-circle':($cur_approval==='declined'?'times-circle':'clock'); ?>"></i>
                            <?php echo ucfirst($cur_approval); ?>
                        </div>
                    </div>

                    <div class="decline-reason-box" id="declineReasonBox" style="<?php echo ($has_existing && $cur_approval==='declined' && !empty($init_data['approval_reason'])) ? '' : 'display:none;'; ?>">
                        <i class="fas fa-exclamation-circle"></i> <strong>HR Decline Reason:</strong> <span id="declineReasonText"><?php echo htmlspecialchars($init_data['approval_reason'] ?? ''); ?></span>
                    </div>

                    <!-- TOP PRIORITIES + TO DO / IF I HAVE TIME (side by side) -->
                    <div class="planner-right-inner">

                        <!-- LEFT: Priorities + Boxes -->
                        <div>
                            <div class="priorities-wrap">
                              <div class="priority-title">Top Priorities</div>
                              <div id="prioritiesList"></div>
                              <button type="button" class="btn-add-priority" onclick="addPriority()">
                                <i class="fas fa-plus"></i> Add Priority
                              </button>
                            </div>

                            <div class="box-section">
                                <div class="section-label"><span>To Do</span></div>
                                <textarea name="todo_notes" class="box-textarea" rows="5"
                                          placeholder="List your tasks for today..."><?php echo htmlspecialchars($init_data['todo_notes'] ?? ''); ?></textarea>
                            </div>

                            <div class="box-section">
                                <div class="section-label"><span>If I Have Time</span></div>
                                <textarea name="if_have_time" class="box-textarea" rows="4"
                                          placeholder="Nice-to-do tasks if time permits..."><?php echo htmlspecialchars($init_data['if_have_time'] ?? ''); ?></textarea>
                            </div>

                            <!-- Focus + Goals -->
                            <div class="focus-goals-row">
                                <div class="box-section" style="margin-bottom:0;">
                                    <div class="section-label"><span>Focus</span></div>
                                    <textarea name="focus_notes" class="box-textarea"
                                              placeholder="What is your main focus today?"><?php echo htmlspecialchars($init_data['focus_notes'] ?? ''); ?></textarea>
                                </div>
                                <div class="box-section" style="margin-bottom:0;">
                                    <div class="section-label"><span>Goals</span></div>
                                    <textarea name="goals_notes" class="box-textarea"
                                              placeholder="What do you want to achieve today?"><?php echo htmlspecialchars($init_data['goals_notes'] ?? ''); ?></textarea>
                                </div>
                            </div>
                        </div>

                        <!-- RIGHT: Schedule -->
                        <div>
                            <div class="schedule-wrap">
                                <div class="schedule-header"><i class="fas fa-clock" style="margin-right:6px;"></i>Plan &amp; Schedules</div>
                                <div class="schedule-rows" id="scheduleRows">
                                    <?php foreach ($time_slots as $slot): ?>
                                    <div class="schedule-row">
                                        <div class="schedule-time"><?php echo $slot; ?></div>
                                        <input type="text"
                                               name="schedule[<?php echo htmlspecialchars($slot); ?>]"
                                               class="schedule-input"
                                               value="<?php echo htmlspecialchars($init_slots[$slot] ?? ''); ?>"
                                               placeholder="—"/>
                                    </div>
                                    <?php endforeach; ?>
                                </div>
                            </div>
                        </div>

                    </div><!-- /planner-right-inner -->

                    <button type="submit" class="btn-save-planner">
                        <i class="fas fa-save" style="margin-right:8px;"></i>Save Planner
                    </button>

                </div><!-- /right-panel -->
            </div><!-- /planner-grid -->
        </form>
        </div><!-- /sectionPlanner -->

    </div><!-- /card-shell -->

    </div><!-- /card-shell -->
</div><!-- /wrap -->

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script>
const filledDates  = <?php echo json_encode($filled_dates); ?>;
const urlEmail     = <?php echo json_encode($url_email); ?>;
const timeSlots    = <?php echo json_encode($time_slots); ?>;
const todayStr     = '<?php echo $today; ?>';
const empName      = <?php echo json_encode($emp_name); ?>;
const empDept      = <?php echo json_encode($emp_data['department'] ?? ''); ?>;
const timingsStr   = <?php echo json_encode($timings); ?>;
let   selectedDate = '<?php echo $selected_date; ?>';
let   calYear, calMonth;
let   currentViewData = null;

const monthNames = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const dayNames   = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

const d0 = new Date(selectedDate + 'T00:00:00');
calYear = d0.getFullYear(); calMonth = d0.getMonth();

function buildCalendar() {
    document.getElementById('calMonthLabel').textContent = monthNames[calMonth] + ' ' + calYear;
    const firstDay = new Date(calYear, calMonth, 1).getDay();
    const daysInMonth = new Date(calYear, calMonth + 1, 0).getDate();
    let html = '';
    for (let i = 0; i < firstDay; i++) html += '<div class="cal-day cal-empty"></div>';
    for (let d = 1; d <= daysInMonth; d++) {
        const mm = String(calMonth+1).padStart(2,'0'), dd = String(d).padStart(2,'0');
        const ds = `${calYear}-${mm}-${dd}`;
        const dow = new Date(calYear, calMonth, d).getDay();
        let cls = 'cal-day';
        if (dow===0) cls += ' cal-sunday';
        if (ds===selectedDate) cls += ' cal-selected';
        if (ds===todayStr) cls += ' cal-today';
        if (filledDates.includes(ds)) cls += ' cal-filled';
        html += `<div class="${cls}" onclick="selectDate('${ds}',${dow===0})">${d}</div>`;
    }
    document.getElementById('calDays').innerHTML = html;
}
document.getElementById('calPrev').onclick = () => { calMonth--; if(calMonth<0){calMonth=11;calYear--;} buildCalendar(); };
document.getElementById('calNext').onclick = () => { calMonth++; if(calMonth>11){calMonth=0;calYear++;} buildCalendar(); };
buildCalendar();

function selectDate(ds, isSun) {
    if (ds === selectedDate) return;
    selectedDate = ds;
    document.getElementById('hidden_plan_date').value = ds;
    const d = new Date(ds + 'T00:00:00');
    document.getElementById('dbDateText').textContent = d.toLocaleDateString('en-IN',{day:'2-digit',month:'long',year:'numeric'});
    document.getElementById('dbDayText').textContent = dayNames[d.getDay()];
    document.getElementById('sundayWarn').style.display = isSun ? '' : 'none';
    document.getElementById('savedBadge').style.display = 'none';
    calYear = d.getFullYear(); calMonth = d.getMonth();
    buildCalendar();
    document.getElementById('loadingOverlay').classList.add('active');
    fetch(`<?php echo $current_page; ?>?load_date=${ds}${urlEmail}`)
        .then(r=>r.json()).then(data=>{ populateForm(data,isSun); document.getElementById('loadingOverlay').classList.remove('active'); })
        .catch(()=>{ populateForm({empty:true},isSun); document.getElementById('loadingOverlay').classList.remove('active'); });
}

function populateForm(data, isSun) {
    const empty = data.empty;
    renderPriorities(empty ? [] : (safeJson(data.priorities) || []));
    ['todo_notes','if_have_time','focus_notes','goals_notes'].forEach(f=>{
        const el = document.querySelector(`textarea[name="${f}"]`);
        if (el) el.value = empty ? '' : (data[f] || '');
    });
    let slots = {};
    if (!empty && data.schedule_slots) { try { slots = JSON.parse(data.schedule_slots); } catch(e){} }
    timeSlots.forEach(s => {
        const el = document.querySelector(`input[name="schedule[${s}]"]`);
        if (el) el.value = slots[s] || '';
    });
    document.getElementById('savedBadge').style.display = (!empty && !isSun) ? '' : 'none';

    const approvalBadge = document.getElementById('approvalBadge');
    const declineBox = document.getElementById('declineReasonBox');
    if (!empty) {
        const status = data.approval_status || 'pending';
        approvalBadge.className = 'db-approval-badge db-approval-' + status;
        approvalBadge.innerHTML = `<i class="fas fa-${status==='approved'?'check-circle':(status==='declined'?'times-circle':'clock')}"></i> ${status.charAt(0).toUpperCase()+status.slice(1)}`;
        approvalBadge.style.display = '';
        if (status === 'declined' && data.approval_reason) {
            document.getElementById('declineReasonText').textContent = data.approval_reason;
            declineBox.style.display = '';
        } else {
            declineBox.style.display = 'none';
        }
    } else {
        approvalBadge.style.display = 'none';
        declineBox.style.display = 'none';
    }
}

let priorCount = 0;
function normalizePriorities(arr) {
    if (!Array.isArray(arr)) return [];
    return arr.map(p => {
        if (typeof p === 'string') return { type:'self', text:p, time:'', completed:false, assigned_by:'' };
        return {
            type: p.type === 'admin' ? 'admin' : 'self',
            text: p.text || '',
            time: p.time || '',
            completed: !!p.completed,
            assigned_by: p.assigned_by || ''
        };
    });
}
function renderPriorities(arr) {
    document.getElementById('prioritiesList').innerHTML = '';
    priorCount = 0;
    const items = normalizePriorities(arr);
    if (!items.length) items.push({ type:'self', text:'', time:'', completed:false, assigned_by:'' });
    items.forEach(it => addPriorityRow(it));
}
function addPriorityRow(item) {
    item = item || { type:'self', text:'', time:'', completed:false, assigned_by:'' };
    priorCount++;
    const n = priorCount;
    const div = document.createElement('div');
    div.className = 'priority-row';
    div.dataset.type = item.type;
    if (item.type === 'admin') {
        div.dataset.time = item.time || '';
        div.dataset.assignedBy = item.assigned_by || '';
        div.style.cssText = 'background:#fff7ed;border:1px solid #fdba74;border-radius:6px;padding:6px 8px;';
        div.innerHTML = `<span class="priority-num">${n}.</span>
            <div style="flex:1;">
              <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                <span style="background:#f59e0b;color:#fff;font-size:10px;font-weight:800;padding:2px 8px;border-radius:10px;">ASSIGNED BY HR</span>
                ${item.time ? `<span style="font-size:11px;color:#92400e;font-weight:700;"><i class="fas fa-clock"></i> ${escHtml(item.time)}</span>` : ''}
              </div>
              <div class="admin-task-text" style="font-size:13px;font-weight:600;color:var(--text);margin-top:3px;${item.completed?'text-decoration:line-through;color:#94a3b8;':''}">${escHtml(item.text)}</div>
            </div>
            <label style="display:flex;align-items:center;gap:5px;font-size:11px;font-weight:700;color:#065f46;cursor:pointer;">
              <input type="checkbox" class="admin-task-done" ${item.completed?'checked':''} onchange="this.closest('.priority-row').querySelector('.admin-task-text').style.textDecoration = this.checked?'line-through':'none';"/> Done
            </label>`;
    } else {
        div.innerHTML = `<span class="priority-num">${n}.</span>
            <input type="text" class="priority-input" value="${escHtml(item.text||'')}" placeholder="Priority ${n}"/>
            ${n>1?'<button type="button" class="priority-del" onclick="removePriority(this)"><i class="fas fa-times"></i></button>':''}`;
    }
    document.getElementById('prioritiesList').appendChild(div);
}
function addPriority() { addPriorityRow({type:'self',text:'',time:'',completed:false}); renumberPriorities(); }
function removePriority(btn) { btn.closest('.priority-row').remove(); renumberPriorities(); }
function renumberPriorities() {
    document.querySelectorAll('#prioritiesList .priority-row').forEach((row,i)=>{
        row.querySelector('.priority-num').textContent = (i+1)+'.';
        const inp = row.querySelector('.priority-input');
        if (inp) inp.placeholder = 'Priority '+(i+1);
    });
    priorCount = document.querySelectorAll('#prioritiesList .priority-row').length;
}
function collectPrioritiesForSubmit() {
    const out = [];
    document.querySelectorAll('#prioritiesList .priority-row').forEach(row=>{
        if (row.dataset.type === 'admin') {
            const text = row.querySelector('.admin-task-text')?.textContent.trim() || '';
            if (!text) return;
            out.push({
                type: 'admin',
                text: text,
                time: row.dataset.time || '',
                completed: row.querySelector('.admin-task-done')?.checked || false,
                assigned_by: row.dataset.assignedBy || ''
            });
        } else {
            const text = row.querySelector('.priority-input')?.value.trim() || '';
            if (!text) return;
            out.push({ type:'self', text:text, time:'', completed:false, assigned_by:'' });
        }
    });
    return out;
}
renderPriorities(<?php echo json_encode($init_pris); ?>);

function openModal(id){ document.getElementById(id).classList.add('active'); }
function closeModal(id){ document.getElementById(id).classList.remove('active'); }
document.querySelectorAll('.modal-overlay').forEach(m=>{
    m.addEventListener('click', e=>{ if(e.target===m) m.classList.remove('active'); });
});

function switchTab(tab) {
    document.getElementById('sectionPlanner').style.display = 'none';
    document.getElementById('sectionHistory').style.display = 'none';
    
    document.getElementById('tabPlannerBtn').style.background = 'var(--navy)';
    document.getElementById('tabHistoryBtn').style.background = 'var(--navy)';
    
    if (tab === 'planner') {
        document.getElementById('sectionPlanner').style.display = 'block';
        document.getElementById('tabPlannerBtn').style.background = 'linear-gradient(135deg,#7c3aed,#6d28d9)';
    } else if (tab === 'history') {
        document.getElementById('sectionHistory').style.display = 'block';
        document.getElementById('tabHistoryBtn').style.background = 'linear-gradient(135deg,#7c3aed,#6d28d9)';
        loadHistory();
    }
}
switchTab('planner');

function openHistory() {
    switchTab('history');
}

function loadHistory() {
    document.getElementById('historyBody').innerHTML = '<div style="text-align:center;padding:30px;color:var(--muted);">Loading...</div>';
    fetch(`<?php echo $current_page; ?>?history_months=1${urlEmail}`)
        .then(r=>r.json()).then(months=>{
            if (!months.length) { document.getElementById('historyBody').innerHTML='<div style="text-align:center;padding:40px;color:var(--muted);">No entries yet.</div>'; return; }
            let html = '';
            months.forEach(m=>{
                html += `<div class="month-card">
                    <div class="month-card-head" onclick="toggleMonth(this,'${m.ym}')">
                        <div class="mch-label"><i class="fas fa-calendar-alt" style="margin-right:7px;color:var(--blue);"></i>${m.label}</div>
                        <div style="display:flex;align-items:center;gap:10px;">
                            <span class="mch-count">${m.cnt} entries</span>
                            <button type="button" class="btn-month-pdf" onclick="event.stopPropagation();downloadMonthPDF('${m.ym}','${m.label}')"><i class="fas fa-file-pdf"></i> Month PDF</button>
                            <i class="fas fa-chevron-down" style="color:var(--muted);font-size:12px;"></i>
                        </div>
                    </div>
                    <div class="month-card-body" id="mbody_${m.ym}"></div>
                </div>`;
            });
            document.getElementById('historyBody').innerHTML = html;
        });
}

function toggleMonth(head, ym) {
    const body = document.getElementById('mbody_' + ym);
    const isOpen = body.classList.contains('open');
    document.querySelectorAll('.month-card-body').forEach(b=>b.classList.remove('open'));
    if (!isOpen) {
        body.classList.add('open');
        if (!body.dataset.loaded) {
            body.innerHTML = '<div style="text-align:center;padding:16px;color:var(--muted);">Loading entries...</div>';
            fetch(`<?php echo $current_page; ?>?history_month=${ym}${urlEmail}`)
                .then(r=>r.json()).then(entries=>{
                    body.dataset.loaded = '1';
                    let html = '';
                    entries.forEach(e=>{
                        const d = new Date(e.plan_date+'T00:00:00');
                        const dLabel = d.toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});
                        const eStatus = e.approval_status || 'pending';
                        html += `<div class="entry-row">
                            <div><div class="entry-date">${dLabel} <span class="status-badge-sm status-${eStatus}" style="margin-left:6px;">${eStatus.charAt(0).toUpperCase()+eStatus.slice(1)}</span></div><div class="entry-day">${dayNames[d.getDay()]}</div></div>
                            <div style="display:flex;gap:8px;">
                                <button class="btn-edit-entry" onclick="editEntry('${e.plan_date}')" style="background:#f0f9ff;border:1.5px solid var(--blue);color:var(--blue);border-radius:6px;padding:5px 9px;font-size:12px;cursor:pointer;" title="Edit this entry in planner"><i class="fas fa-edit"></i> Edit</button>
                                <button class="btn-view-entry" onclick="viewEntry(${e.id})"><i class="fas fa-eye"></i> View</button>
                                <button class="btn-pdf-entry" onclick="viewEntry(${e.id},true)"><i class="fas fa-file-pdf"></i> PDF</button>
                                <button class="btn-del-entry" onclick="deleteEntry(${e.id})" title="Delete this entry"><i class="fas fa-trash"></i></button>
                            </div>
                        </div>`;
                    });
                    body.innerHTML = html || '<div style="padding:12px;color:var(--muted);">No entries.</div>';
                });
        }
    }
}

function editEntry(dateStr) {
    switchTab('planner');
    const isSun = new Date(dateStr+'T00:00:00').getDay() === 0;
    selectDate(dateStr, isSun);
}

function viewEntry(id, autoPdf=false) {
    openModal('viewEntryModal');
    document.getElementById('viewEntryBody').innerHTML = '<div style="text-align:center;padding:30px;">Loading...</div>';
    fetch(`<?php echo $current_page; ?>?view_entry=${id}${urlEmail}`)
        .then(r=>r.json()).then(data=>{
            if (data.empty) { document.getElementById('viewEntryBody').innerHTML='<div style="padding:30px;text-align:center;">Entry not found.</div>'; return; }
            currentViewData = data;
            const d = new Date(data.plan_date+'T00:00:00');
            document.getElementById('viewEntryTitle').textContent = d.toLocaleDateString('en-IN',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
            const pris  = safeJson(data.priorities) || [];
            const slots = safeJson(data.schedule_slots) || {};
            let priHtml = pris.length ? pris.map((p,i)=>renderPriorityViewItem(p,i)).join('') : '<div style="color:var(--muted);">—</div>';
            let slotHtml = timeSlots.map(s=>`<div class="view-schedule-row"><div class="vs-time">${s}</div><div>${escHtml(slots[s]||'—')}</div></div>`).join('');
            const vStatus = data.approval_status || 'pending';
            let vStatusHtml = `<div style="margin-bottom:14px;"><span class="status-badge-sm status-${vStatus}">${vStatus.charAt(0).toUpperCase()+vStatus.slice(1)}</span>
                ${(vStatus==='declined' && data.approval_reason) ? `<div style="margin-top:8px;background:#fee2e2;border-radius:6px;padding:8px 12px;font-size:12px;color:#991b1b;"><b>Decline reason:</b> ${escHtml(data.approval_reason)}</div>` : ''}</div>`;
            document.getElementById('viewEntryBody').innerHTML = `
                ${vStatusHtml}
                <div style="display:grid;grid-template-columns:35fr 65fr;gap:18px;">
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
            if (autoPdf) setTimeout(downloadPDF, 400);
        });
}

function downloadPDF() {
    if (!currentViewData) return;
    const d = new Date(currentViewData.plan_date+'T00:00:00');
    const dLabel = d.toLocaleDateString('en-IN',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
    const pris  = safeJson(currentViewData.priorities) || [];
    const printHtml = `<html><head><meta charset="utf-8"><style>
        body{font-family:'Segoe UI',sans-serif;color:#1e293b;padding:28px;font-size:12px;}
        .sec{font-size:10px;font-weight:800;color:#c0392b;text-transform:uppercase;margin:12px 0 5px;border-bottom:1px solid #fca5a5;padding-bottom:2px;}
        .two{display:grid;grid-template-columns:35fr 65fr;gap:18px;}
        .four{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:8px;}
        .box{background:#f8fafc;border-radius:5px;padding:8px;font-size:11px;min-height:44px;white-space:pre-wrap;}
        .slot{display:flex;gap:8px;padding:4px 6px;font-size:11px;border-bottom:1px solid #f1f5f9;}
        .st{font-weight:800;color:#0d1f3c;width:70px;flex-shrink:0;}
    </style></head><body>
    <div style="text-align:center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #e2e8f0;">
        <h1 style="font-size:24px; color:#0d1f3c; margin:0 0 10px 0;">Daily Planner - ${dLabel}</h1>
        <div style="font-size:13px; color:#475569; display:flex; justify-content:center; gap:20px;">
            <span><b>Prepared by:</b> ${escHtml(empName)}</span>
            <span><b>Dept:</b> ${escHtml(empDept)}</span>
            ${timingsStr?`<span><b>Timings:</b> ${escHtml(timingsStr)}</span>`:''}
        </div>
    </div>
    <div class="two"><div>
        <div class="sec">Top Priorities</div>
        ${pris.map((p,i)=>renderPriorityViewItem(p,i)).join('')||'—'}
        <div class="four">
            <div><div class="sec">To Do</div><div class="box">${escHtml(currentViewData.todo_notes||'—')}</div></div>
            <div><div class="sec">If I Have Time</div><div class="box">${escHtml(currentViewData.if_have_time||'—')}</div></div>
            <div><div class="sec">Focus</div><div class="box">${escHtml(currentViewData.focus_notes||'—')}</div></div>
            <div><div class="sec">Goals</div><div class="box">${escHtml(currentViewData.goals_notes||'—')}</div></div>
        </div>
    </div><div>
        <div class="sec">Plan &amp; Schedules</div>
        ${timeSlots.map(s=>`<div class="slot"><div class="st">${s}</div><div>${escHtml(slots[s]||'—')}</div></div>`).join('')}
    </div></div></body></html>`;
    const win = window.open('','_blank');
    win.document.write(printHtml);
    win.document.close();
    win.focus();
    setTimeout(()=>{ win.print(); }, 500);
}

function downloadTemplate() {
    const ym = document.getElementById('importMonthPicker').value;
    if (!ym) { alert('Select a month first.'); return; }
    window.location.href = `<?php echo $current_page; ?>?download_template=${ym}${urlEmail}`;
}

function deleteEntry(id) {
    if (!confirm('Delete this planner entry? This cannot be undone.')) return;
    fetch(`<?php echo $current_page; ?>?delete_entry=${id}${urlEmail}`)
        .then(r=>r.json()).then(res=>{
            if (res.ok) { openHistory(); }
            else { alert('Could not delete entry.'); }
        });
}

function downloadMonthPDF(ym, label) {
    fetch(`<?php echo $current_page; ?>?history_month=${ym}${urlEmail}`)
        .then(r=>r.json()).then(entries=>{
            if (!entries.length) { alert('No entries found for this month.'); return; }
            
            const globalHeader = `
                <div style="text-align:center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #e2e8f0;">
                    <h1 style="font-size:24px; color:#0d1f3c; margin:0 0 10px 0;">Monthly Calendar - ${escHtml(label)}</h1>
                    <div style="font-size:13px; color:#475569; display:flex; justify-content:center; gap:20px;">
                        <span><b>Prepared by:</b> ${escHtml(empName)}</span>
                        <span><b>Dept:</b> ${escHtml(empDept)}</span>
                        ${timingsStr?`<span><b>Timings:</b> ${escHtml(timingsStr)}</span>`:''}
                    </div>
                </div>
            `;
            
            let pagesHtml = entries.map(data=>{
                const d = new Date(data.plan_date+'T00:00:00');
                const dLabel = d.toLocaleDateString('en-IN',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
                const pris  = safeJson(data.priorities) || [];
                const slots = safeJson(data.schedule_slots) || {};
                return `<div style="padding-bottom:30px; margin-bottom:30px; border-bottom:1px solid #cbd5e1; page-break-inside: avoid;">
                    <h2 style="font-size:16px; color:#0f172a; margin-bottom:12px; border-left:4px solid #3b82f6; padding-left:10px;">${dLabel}</h2>
                    <div class="two"><div>
                        <div class="sec">Top Priorities</div>
                        ${pris.map((p,i)=>renderPriorityViewItem(p,i)).join('')||'—'}
                        <div class="four">
                            <div><div class="sec">To Do</div><div class="box">${escHtml(data.todo_notes||'—')}</div></div>
                            <div><div class="sec">If I Have Time</div><div class="box">${escHtml(data.if_have_time||'—')}</div></div>
                            <div><div class="sec">Focus</div><div class="box">${escHtml(data.focus_notes||'—')}</div></div>
                            <div><div class="sec">Goals</div><div class="box">${escHtml(data.goals_notes||'—')}</div></div>
                        </div>
                    </div><div>
                        <div class="sec">Plan &amp; Schedules</div>
                        ${timeSlots.map(s=>`<div class="slot"><div class="st">${s}</div><div>${escHtml(slots[s]||'—')}</div></div>`).join('')}
                    </div></div>
                </div>`;
            }).join('');
            const printHtml = `<html><head><meta charset="utf-8"><title>${escHtml(label)} Planner</title><style>
                body{font-family:'Segoe UI',sans-serif;color:#1e293b;padding:28px;font-size:12px;}
                .sec{font-size:10px;font-weight:800;color:#c0392b;text-transform:uppercase;margin:12px 0 5px;border-bottom:1px solid #fca5a5;padding-bottom:2px;}
                .two{display:grid;grid-template-columns:35fr 65fr;gap:18px;}
                .four{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:8px;}
                .box{background:#f8fafc;border-radius:5px;padding:8px;font-size:11px;min-height:44px;white-space:pre-wrap;}
                .slot{display:flex;gap:8px;padding:4px 6px;font-size:11px;border-bottom:1px solid #f1f5f9;}
                .st{font-weight:800;color:#0d1f3c;width:70px;flex-shrink:0;}
            </style></head><body>${globalHeader}${pagesHtml}</body></html>`;
            const win = window.open('','_blank');
            win.document.write(printHtml);
            win.document.close();
            win.focus();
            setTimeout(()=>{ win.print(); }, 600);
        });
}

function safeJson(v) { try { return typeof v==='string' ? JSON.parse(v) : v; } catch(e) { return null; } }
function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function renderPriorityViewItem(p, i) {
    if (typeof p === 'string') {
        return `<div style="display:flex;gap:8px;padding:5px 8px;background:#f8fafc;border-radius:5px;margin-bottom:4px;font-size:13px;"><span style="color:var(--red);font-weight:800;">${i+1}.</span>${escHtml(p)}</div>`;
    }
    const badge = p.type === 'admin' ? `<span style="background:#f59e0b;color:#fff;font-size:9px;font-weight:800;padding:1px 6px;border-radius:8px;margin-left:6px;">HR</span>` : '';
    const time = p.time ? `<span style="font-size:11px;color:#92400e;margin-left:6px;"><i class="fas fa-clock"></i> ${escHtml(p.time)}</span>` : '';
    const done = p.completed ? 'text-decoration:line-through;color:#94a3b8;' : '';
    return `<div style="display:flex;gap:8px;padding:5px 8px;background:#f8fafc;border-radius:5px;margin-bottom:4px;font-size:13px;${done}"><span style="color:var(--red);font-weight:800;">${i+1}.</span>${escHtml(p.text||'')}${badge}${time}</div>`;
}

document.getElementById('plannerForm').addEventListener('submit', ()=>{
    document.getElementById('hidden_priorities_json').value = JSON.stringify(collectPrioritiesForSubmit());
    document.getElementById('loadingOverlay').classList.add('active');
});
</script>
</body>
</html>
