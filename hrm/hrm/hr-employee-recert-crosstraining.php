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
mysqli_report(MYSQLI_REPORT_OFF); // Disable fatal exceptions for mysql queries in PHP 8.1+

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$active_tab = $_GET['tab'] ?? 'recert';

// =========================================================================
// CREATE TABLES IF NOT EXIST
// =========================================================================
$tables = [
"CREATE TABLE IF NOT EXISTS hr_oje_recert_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    cycle_number INT NOT NULL DEFAULT 1,
    interval_months INT DEFAULT 12,
    interval_type ENUM('days','months','years') DEFAULT 'months',
    pass_percent DECIMAL(5,2) DEFAULT 95.00,
    max_attempts INT DEFAULT 3,
    created_by VARCHAR(255) DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_recert_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    cycle_number INT NOT NULL DEFAULT 1,
    question_text TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_recert_question_options (
    id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    option_label VARCHAR(255) NOT NULL,
    points INT NOT NULL DEFAULT 0,
    is_correct TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_recert_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    cycle_number INT DEFAULT 1,
    attempt_number INT DEFAULT 1,
    total_marks INT DEFAULT 0,
    obtained_marks INT DEFAULT 0,
    percentage DECIMAL(5,2) DEFAULT 0,
    passed TINYINT(1) DEFAULT 0,
    answers_json LONGTEXT DEFAULT NULL,
    attempted_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_cross_training (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    from_dept_id INT NOT NULL DEFAULT 0,
    from_pos_id INT NOT NULL DEFAULT 0,
    to_dept_id INT NOT NULL,
    to_pos_id INT NOT NULL DEFAULT 0,
    start_date DATE DEFAULT NULL,
    status ENUM('active','completed','cancelled') DEFAULT 'active',
    initiated_by VARCHAR(255) DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) @mysqli_query($con, $sql);
try {
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD COLUMN cycle_number INT NOT NULL DEFAULT 1");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD COLUMN interval_type ENUM('days','months','years') DEFAULT 'months'");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config DROP INDEX uniq_dept_pos");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD UNIQUE KEY uniq_dept_pos_cycle (department_id, position_id, cycle_number)");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_questions ADD COLUMN cycle_number INT NOT NULL DEFAULT 1");
} catch (Exception $e) {
    // Silently ignore if column/key already exists or index doesn't exist
}
try {
    mysqli_query($con, "ALTER TABLE hr_oje_recert_questions ADD COLUMN question_type ENUM('mcq','text') NOT NULL DEFAULT 'mcq'");
} catch (Exception $e) {
    // Silently ignore if already applied
}
try { mysqli_query($con, "ALTER TABLE hr_positions ADD COLUMN worker_category VARCHAR(20) NOT NULL DEFAULT 'professional'"); } catch (Throwable $e) {}

// =========================================================================
// RESOLVE EMPLOYEE
// =========================================================================
$empRow = null; $employee_id = 0; $dept_id = 0; $pos_id = 0;

$isHRView = false;
if (isset($_GET['view_emp']) && intval($_GET['view_emp']) > 0) {
    $isHRView    = true;
    $employee_id = intval($_GET['view_emp']);
    $dept_id     = intval($_GET['dept_id'] ?? 0);
    $pos_id      = intval($_GET['pos_id']  ?? 0);
    $eq = mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$employee_id LIMIT 1");
    $empRow = $eq ? mysqli_fetch_assoc($eq) : null;
} else {
    if ($currentUserName) {
        $un  = mysqli_real_escape_string($con, $currentUserName);
        $r   = mysqli_query($con, "SELECT * FROM hr_employees WHERE name='$un' LIMIT 1");
        if ($r && mysqli_num_rows($r) > 0) $empRow = mysqli_fetch_assoc($r);
    }
    if ($empRow) {
        $employee_id = intval($empRow['id']);
        $deptVal = $empRow['department_id'] ?? ($empRow['department'] ?? null);
        $posVal  = $empRow['position_id']   ?? ($empRow['position']   ?? null);
        if (is_numeric($deptVal)) $dept_id = intval($deptVal);
        else { $dn = mysqli_real_escape_string($con, trim($deptVal ?? '')); $q2 = mysqli_query($con, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1"); $r2 = $q2 ? mysqli_fetch_assoc($q2) : null; if($r2) $dept_id = intval($r2['id']); }
        if (is_numeric($posVal)) $pos_id = intval($posVal);
        else { $pn = mysqli_real_escape_string($con, trim($posVal ?? '')); $q3 = mysqli_query($con, "SELECT id FROM hr_positions WHERE title='$pn' LIMIT 1"); $r3 = $q3 ? mysqli_fetch_assoc($q3) : null; if($r3) $pos_id = intval($r3['id']); }
    }
}

// =========================================================================
// FETCH COMPANY SETTINGS FOR CERTIFICATE
// =========================================================================
$co_settings = null;
if ($empRow && !empty($empRow['company_name'])) {
    $cn = mysqli_real_escape_string($con, $empRow['company_name']);
    $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_name='$cn' LIMIT 1"));
}
if (!$co_settings) {
    $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings ORDER BY id ASC LIMIT 1"));
}

// =========================================================================
// CYCLE CALCULATION & RECERT CONFIG WITH FALLBACK LOGIC
// =========================================================================

// Main progress (certified check)
$main_progress = null;
if ($employee_id > 0 && $dept_id > 0) {
    $mpq = mysqli_query($con, "SELECT * FROM hr_oje_employee_progress WHERE employee_id=$employee_id AND department_id=$dept_id AND position_id=$pos_id LIMIT 1");
    $main_progress = $mpq ? mysqli_fetch_assoc($mpq) : null;
}
$is_certified = ($main_progress && $main_progress['stage'] === 'certified');

// Blue Collar positions are exempt from Recertification/Cross-training.
$isBlueCollarPosition = false;
if ($pos_id > 0) {
    $wcRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT worker_category FROM hr_positions WHERE id=$pos_id"));
    $isBlueCollarPosition = $wcRow && ($wcRow['worker_category'] === 'blue_collar');
}

// Cycle logic
$cycle_number = 1; $cycle_start = null; $due_date = null;
$days_left = null; $is_due = false; $recert_overdue = false;
$recert_attempts = []; $recert_attempts_used = 0;
$recert_passed_this_cycle = false; $recert_failed = false;
$recert_questions = [];

$recert_interval = 0; $recert_int_type = 'months'; $recert_pass_pct = 95; $recert_max_att = 3;
$target_cycle = 1;

if ($is_certified) {
    $lq = mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE employee_id=$employee_id AND department_id=$dept_id AND position_id=$pos_id AND passed=1 ORDER BY attempted_at DESC LIMIT 1");
    $lastPass = $lq ? mysqli_fetch_assoc($lq) : null;
    $cycle_start  = $lastPass ? $lastPass['attempted_at'] : $main_progress['certified_at'];
    $cycle_number = $lastPass ? (intval($lastPass['cycle_number']) + 1) : 1;
    
    // Fallback Logic: Try to fetch config for $cycle_number. If not found, get the highest available cycle configuration.
    $recert_config = null;
    if ($dept_id > 0) {
        $cq = mysqli_query($con, "SELECT cycle_number FROM hr_oje_recert_config WHERE department_id=$dept_id AND position_id=$pos_id ORDER BY cycle_number DESC");
        if (!$cq || mysqli_num_rows($cq) == 0) {
            $cq = mysqli_query($con, "SELECT cycle_number FROM hr_oje_recert_config WHERE department_id=$dept_id AND position_id=0 ORDER BY cycle_number DESC");
        }
        
        $available_cycles = [];
        if ($cq) {
            while ($c = mysqli_fetch_assoc($cq)) {
                $available_cycles[] = intval($c['cycle_number']);
            }
        }
        
        if (in_array($cycle_number, $available_cycles)) {
            $target_cycle = $cycle_number;
            $is_configured = true;
        } else {
            $target_cycle = $cycle_number;
            $is_configured = false;
        }
        
        if ($is_configured) {
            $rcq = mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id=$dept_id AND position_id=$pos_id AND cycle_number=$target_cycle LIMIT 1");
            $recert_config = $rcq ? mysqli_fetch_assoc($rcq) : null;
            if (!$recert_config) {
                $rcq2 = mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id=$dept_id AND position_id=0 AND cycle_number=$target_cycle LIMIT 1");
                $recert_config = $rcq2 ? mysqli_fetch_assoc($rcq2) : null;
            }
            
            $aq = mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE employee_id=$employee_id AND department_id=$dept_id AND cycle_number=$target_cycle ORDER BY attempt_number ASC");
            if ($aq) {
                while ($a = mysqli_fetch_assoc($aq)) {
                    $recert_attempts[] = $a;
                }
            }
            $recert_attempts_used = count($recert_attempts);
        }
    }
    
    if ($is_configured && $recert_config) {
        $recert_interval  = intval($recert_config['interval_months'] ?? 0);
        $recert_int_type  = $recert_config['interval_type'] ?? 'months';
        $recert_pass_pct  = floatval($recert_config['pass_percent'] ?? 95);
        $recert_max_att   = intval($recert_config['max_attempts'] ?? 3);
        
        $due_date     = date('Y-m-d', strtotime($cycle_start . " +{$recert_interval} {$recert_int_type}"));
        $due_ts       = strtotime($due_date);
        $days_left    = ceil(($due_ts - time()) / 86400);
        $is_due       = (time() >= $due_ts);
        $recert_overdue = $is_due;
        $lastAtt = !empty($recert_attempts) ? end($recert_attempts) : null;
        $recert_passed_this_cycle = ($lastAtt && $lastAtt['passed']);
        $recert_failed = ($recert_attempts_used >= $recert_max_att && !$recert_passed_this_cycle);

        if ($is_due && !$recert_passed_this_cycle && !$recert_failed) {
            $qq = mysqli_query($con, "SELECT q.*, GROUP_CONCAT(o.id,'::',o.option_label,'::',o.points,'::',o.is_correct ORDER BY o.sort_order SEPARATOR '||') as options_raw
                FROM hr_oje_recert_questions q LEFT JOIN hr_oje_recert_question_options o ON o.question_id=q.id
                WHERE q.department_id=$dept_id AND (q.position_id=$pos_id OR q.position_id=0) AND q.cycle_number=$target_cycle
                GROUP BY q.id ORDER BY q.sort_order ASC");
            if ($qq) {
                while ($q = mysqli_fetch_assoc($qq)) {
                    $q['options'] = [];
                    if (!empty($q['options_raw'])) {
                        foreach (explode('||', $q['options_raw']) as $opt) {
                            $parts = explode('::', $opt);
                            if (count($parts) == 4) $q['options'][] = ['id'=>intval($parts[0]),'label'=>$parts[1],'points'=>intval($parts[2]),'is_correct'=>intval($parts[3])];
                        }
                    }
                    $recert_questions[] = $q;
                }
            }
        }
    }
}

// =========================================================================
// CROSS TRAINING RECORDS FOR THIS EMPLOYEE
// =========================================================================
$cross_training_active = [];
if ($employee_id > 0) {
    $ctq = mysqli_query($con, "SELECT ct.*,
        fd.name as from_dept_name, fp.title as from_pos_name,
        td.name as to_dept_name, tp.title as to_pos_name,
        p.stage as ct_stage, p.certified_at as ct_certified_at
        FROM hr_oje_cross_training ct
        LEFT JOIN hr_departments fd ON fd.id=ct.from_dept_id
        LEFT JOIN hr_positions   fp ON fp.id=ct.from_pos_id
        LEFT JOIN hr_departments td ON td.id=ct.to_dept_id
        LEFT JOIN hr_positions   tp ON tp.id=ct.to_pos_id
        LEFT JOIN hr_oje_employee_progress p ON p.employee_id=ct.employee_id AND p.department_id=ct.to_dept_id AND p.position_id=ct.to_pos_id
        WHERE ct.employee_id=$employee_id AND ct.status IN ('active','completed')
        ORDER BY ct.created_at DESC");
    if ($ctq) {
        while ($ct = mysqli_fetch_assoc($ctq)) {
            // Auto-complete if certified
            if ($ct['ct_stage'] === 'certified' && $ct['status'] === 'active') {
                mysqli_query($con, "UPDATE hr_oje_cross_training SET status='completed', updated_at=NOW() WHERE id={$ct['id']}");
                $ct['status'] = 'completed';

                // Sync employee's home department/position to the new (target) role
                $new_dept_name = mysqli_real_escape_string($con, $ct['to_dept_name'] ?? '');
                $new_pos_name  = mysqli_real_escape_string($con, $ct['to_pos_name'] ?? '');
                $new_pos_id    = intval($ct['to_pos_id']);
                $sync_emp_id   = intval($ct['employee_id']);
                if ($new_dept_name !== '') {
                    mysqli_query($con, "UPDATE hr_employees SET department='$new_dept_name', position='$new_pos_name', position_id=$new_pos_id WHERE id=$sync_emp_id");
                }
            }
            $cross_training_active[] = $ct;
        }
    }
}

// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && !$isHRView) {
    $action = $_POST['action'];

    if ($action === 'acknowledge_anti_cheat') {
        unset($_SESSION['anti_cheat_failed']);
        header("Location: hr-employee-recert-crosstraining.php"); exit;
    }

    if ($action === 'submit_recert_test' && $is_certified && $is_due && !$recert_passed_this_cycle && !$recert_failed) {
        $answers = $_POST['answers'] ?? [];

        // Grade
        $total = 0; $obtained = 0; $detail = [];
        foreach ($recert_questions as $q) {
            // Text-area questions are non-scoring: recorded for review but excluded
            // from the total/obtained marks used to calculate the pass percentage.
            if (($q['question_type'] ?? 'mcq') === 'text') {
                $detail[] = ['question_id'=>$q['id'],'question_text'=>$q['question_text'],'question_type'=>'text','answer_text'=>trim((string) ($answers[$q['id']] ?? '')),'points'=>0,'max'=>0];
                continue;
            }
            if (empty($q['options'])) continue;
            $maxPts = 0;
            foreach ($q['options'] as $o) $maxPts = max($maxPts, $o['points']);
            $total += $maxPts;
            $selOptId = intval($answers[$q['id']] ?? 0);
            $gotPts = 0; $selLabel = '';
            foreach ($q['options'] as $o) { if ($o['id'] == $selOptId) { $gotPts = $o['points']; $selLabel = $o['label']; } }
            $obtained += $gotPts;
            $detail[] = ['question_id'=>$q['id'],'question_text'=>$q['question_text'],'question_type'=>'mcq','selected_option_id'=>$selOptId,'selected_label'=>$selLabel,'points'=>$gotPts,'max'=>$maxPts];
        }

        $pct        = $total > 0 ? round(($obtained / $total) * 100, 2) : 0;
        $passed     = ($total > 0 && $pct >= $recert_pass_pct) ? 1 : 0;
        $attempt_no = $recert_attempts_used + 1;
        $json       = mysqli_real_escape_string($con, json_encode($detail));

        $ins = mysqli_query($con, "INSERT INTO hr_oje_recert_attempts (employee_id,department_id,position_id,cycle_number,attempt_number,total_marks,obtained_marks,percentage,passed,answers_json)
            VALUES ($employee_id,$dept_id,$pos_id,$cycle_number,$attempt_no,$total,$obtained,$pct,$passed,'$json')");

        if (!$ins) {
            $_SESSION['error_message'] = "Database error: " . mysqli_error($con);
        } else if ($passed) {
            $_SESSION['success_message'] = "Congratulations! You scored " . number_format($pct,1) . "% and passed Recertification Cycle $cycle_number!";
        } else {
            $remaining = $recert_max_att - $attempt_no;
            if ($remaining > 0) {
                $_SESSION['error_message'] = "You scored " . number_format($pct,1) . "% (required: " . number_format($recert_pass_pct,1) . "%). $remaining attempt(s) remaining.";
            } else {
                // Raise failure ticket
                $mxq = mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"); $maxRow = $mxq ? mysqli_fetch_assoc($mxq) : null;
                $nextId = intval($maxRow['max_id'] ?? 0) + 1;
                $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
                $timeline = 2880; $deadline = date('Y-m-d H:i:s', strtotime("+{$timeline} minutes"));
                $dnq = mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id"); $dnr = $dnq ? mysqli_fetch_assoc($dnq) : null; $deptName = $dnr ? $dnr['name'] : '';
                $pnq = mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id"); $pnr = ($pos_id > 0 && $pnq) ? mysqli_fetch_assoc($pnq) : null; $posName = $pnr ? $pnr['title'] : 'All Positions';
                $subj = "Recertification Test Failed — All Attempts Used (Cycle $cycle_number)";
                $msg  = "Employee: {$empRow['name']}\nDepartment: $deptName\nPosition: $posName\nCycle: $cycle_number\nFinal Score: ".number_format($pct,1)."%\n\nThe employee has used all $recert_max_att attempts for Recertification Cycle $cycle_number. Please review and reset if needed.";
                $pri = 'high'; $stat = 'open'; $att = ''; $ename = $empRow['name'];
                $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number,name,subject,message,status,priority,timeline,deadline,attachment,created_at,updated_at,assigned_to,created_by) VALUES (?,?,?,?,?,?,?,?,?,NOW(),NOW(),?,?)");
                if ($stmt) {
                    mysqli_stmt_bind_param($stmt, "ssssssissii", $ticket_number, $ename, $subj, $msg, $stat, $pri, $timeline, $deadline, $att, $employee_id, $employee_id);
                    mysqli_stmt_execute($stmt);
                    mysqli_stmt_close($stmt);
                }
                $_SESSION['error_message'] = "You scored " . number_format($pct,1) . "% and have used all $recert_max_att attempts. HR has been notified via ticket.";
            }
        }
        header("Location: hr-employee-recert-crosstraining.php"); exit;
    }
}

// =========================================================================
// NAMES
// =========================================================================
$deptName = 'N/A'; $posName = 'All Positions';
if ($dept_id > 0) { $dq2 = mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id"); $dn2 = $dq2 ? mysqli_fetch_assoc($dq2) : null; if($dn2) $deptName = $dn2['name']; }
if ($pos_id  > 0) { $pq2 = mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id");  $pn2 = $pq2 ? mysqli_fetch_assoc($pq2) : null; if($pn2) $posName  = $pn2['title']; }

$recert_cert_number = '';
if ($recert_passed_this_cycle && !empty($lastAtt['attempted_at'])) {
    $recert_cert_number = 'RECERT-' . date('Y', strtotime($lastAtt['attempted_at'])) . '-C' . $cycle_number . '-' . str_pad($employee_id, 5, '0', STR_PAD_LEFT);
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>My Recertification & Cross Training — <?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="css/app.css" type="text/css"/>
<style>
:root { --navy:#0f2557; --blue:#1a3fc4; --green:#10b981; --amber:#f59e0b; --red:#ef4444; --gold:#d4af37; --gray-bg:#f0f4f8; }
* { box-sizing:border-box; }
body { font-family:'Plus Jakarta Sans',sans-serif; background:var(--gray-bg); min-height: 100vh; margin: 0; padding: 0; }

.oje-header { background:linear-gradient(135deg,#0f2557 0%,#1a3fc4 100%); padding:22px 32px; display:flex; justify-content:space-between; align-items:center; border-radius:12px; margin-bottom:20px; box-shadow:0 4px 20px rgba(15,37,87,0.3); flex-wrap:wrap; gap:14px; }
.oje-header h1 { color:#fff; font-weight:800; margin:0; font-size:1.4rem; }
.oje-header p  { color:rgba(255,255,255,0.65); font-size:12px; margin:4px 0 0; }

.card-box { background:#fff; border-radius:12px; padding:24px; box-shadow:0 2px 10px rgba(0,0,0,0.06); margin-bottom:20px; }
.card-box h5 { font-weight:800; color:var(--navy); margin-bottom:16px; font-size:15px; }
.empty-hint { text-align:center; padding:40px; color:#94a3b8; }

.countdown-card { background:linear-gradient(135deg,#fffbeb,#fef3c7); border:2px solid #fcd34d; border-radius:14px; padding:28px; text-align:center; margin-bottom:20px; }
.countdown-card .days-num { font-size:64px; font-weight:800; color:#92400e; line-height:1; }
.countdown-card .days-label { font-size:14px; font-weight:700; color:#b45309; margin-top:4px; }
.countdown-card .due-info { font-size:13px; color:#78350f; margin-top:10px; }

.overdue-banner { background:#fee2e2; border:2px solid #fca5a5; border-radius:12px; padding:16px 20px; display:flex; align-items:center; gap:12px; margin-bottom:20px; }
.overdue-banner i { font-size:24px; color:var(--red); }
.overdue-banner .ob-title { font-weight:800; color:#991b1b; font-size:14px; }
.overdue-banner .ob-sub { font-size:12px; color:#b91c1c; margin-top:2px; }

.status-banner { border-radius:10px; padding:12px 18px; font-size:13px; font-weight:600; margin-bottom:18px; display:flex; align-items:center; gap:10px; }
.status-banner.info { background:#eff6ff; border:1.5px solid #bfdbfe; color:#1e40af; }
.status-banner.ok   { background:#d1fae5; border:1.5px solid #6ee7b7; color:#065f46; }
.status-banner.warn { background:#fef3c7; border:1.5px solid #fcd34d; color:#92400e; }

.q-card { border:1.5px solid #e0e7ff; border-radius:10px; padding:18px; margin-bottom:14px; user-select:none; -webkit-user-select:none; -moz-user-select:none; -ms-user-select:none; }
.q-card .q-num  { font-size:11px; font-weight:800; color:var(--blue); text-transform:uppercase; margin-bottom:6px; }
.q-card .q-text { font-weight:700; color:var(--navy); font-size:14px; margin-bottom:12px; }
.opt-label { display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:8px; margin-bottom:6px; background:#f8fafc; border:1.5px solid #e2e8f0; cursor:pointer; font-size:13px; font-weight:600; color:#334155; transition:.15s; }
.opt-label:hover { border-color:var(--blue); background:#f0f4ff; }
.opt-label input { width:16px; height:16px; margin:0; }

.attempt-pill { display:inline-flex; align-items:center; gap:6px; background:#ede9fe; color:#5b21b6; font-size:12px; font-weight:800; padding:5px 12px; border-radius:14px; }

.history-table { width:100%; border-collapse:collapse; margin-top:10px; }
.history-table th { background:#f0f4f8; color:var(--navy); font-weight:800; font-size:13px; text-transform:uppercase; padding:12px 16px; text-align:left; border-bottom: 2px solid #e2e8f0; }

/* Custom Table Header Colors */
.history-table.table-training th { background: #eff6ff; color: #1e3a8a; border-bottom: 2px solid #bfdbfe; }
.history-table.table-recert th { background: #fefce8; color: #854d0e; border-bottom: 2px solid #fef08a; }
.history-table.table-cross th { background: #f0fdfa; color: #115e59; border-bottom: 2px solid #99f6e4; }

/* Custom Section Header Colors */
.section-head { padding: 10px 15px; border-radius: 8px; display: inline-block; width: 100%; margin-bottom: 15px; font-weight: 800; font-size: 13px; text-transform: uppercase; }
.section-head-training { background: #eff6ff; color: #1e3a8a; border-left: 4px solid #3b82f6; }
.section-head-recert { background: #fefce8; color: #854d0e; border-left: 4px solid #eab308; }
.section-head-cross { background: #f0fdfa; color: #115e59; border-left: 4px solid #14b8a6; }
.history-table td { padding:12px 16px; border-bottom:1px solid #f1f5f9; font-size:14px; }
.pf-pass { color:#065f46; font-weight:800; }
.pf-fail { color:#991b1b; font-weight:800; }

.nav-tabs .nav-link { color:#64748b !important; font-weight:700; padding:12px 24px; border:none; border-bottom:3px solid transparent; background:transparent; transition:.2s; }
.nav-tabs .nav-link:hover { color:var(--blue) !important; border-bottom-color:var(--light-blue); }
.nav-tabs .nav-link.active { color:var(--navy) !important; border-bottom-color:var(--navy) !important; }

.cert-wrap { display:flex; justify-content:center; margin-bottom:20px; }
.certificate { width:100%; max-width:820px; background:#fffefb; border:10px solid var(--navy); border-radius:6px; padding:50px 60px; text-align:center; position:relative; background-image:radial-gradient(circle at top left,rgba(212,175,55,0.06),transparent 60%),radial-gradient(circle at bottom right,rgba(212,175,55,0.06),transparent 60%); }
.certificate::before { content:''; position:absolute; inset:14px; border:2px solid var(--gold); border-radius:4px; pointer-events:none; }
.certificate .cert-icon { font-size:46px; color:var(--gold); margin-bottom:6px; }
.certificate .cert-title { font-size:26px; font-weight:800; color:var(--navy); margin:14px 0 4px; }
.certificate .cert-name  { font-size:28px; font-weight:800; color:var(--blue); margin:10px 0; }
.certificate .cert-body  { font-size:14px; color:#334155; max-width:560px; margin:0 auto 26px; line-height:1.7; }
.certificate .cert-footer { display:flex; justify-content:space-between; margin-top:30px; font-size:12px; color:#64748b; }
.certificate .cert-footer strong { display:block; color:var(--navy); font-size:13px; }

.ct-card { border:1.5px solid #e0e7ff; border-radius:12px; padding:20px; margin-bottom:16px; background:#fff; }
.ct-card .ct-title { font-weight:800; color:var(--navy); font-size:14px; margin-bottom:12px; }
.ct-flow { display:flex; align-items:center; gap:8px; flex-wrap:wrap; margin-bottom:12px; }
.ct-flow .ct-node { padding:6px 14px; border-radius:20px; font-size:12px; font-weight:700; background:#e0e7ff; color:var(--blue); }
.ct-flow .ct-arrow { color:#94a3b8; font-size:16px; }
.ct-flow .ct-node.active { background:var(--blue); color:#fff; }
.ct-flow .ct-node.done   { background:var(--green); color:#fff; }

.stage-flow { display:flex; gap:6px; flex-wrap:wrap; margin-top:10px; }
.stage-pill { padding:5px 12px; border-radius:20px; font-size:11px; font-weight:800; }
.stage-pill.done    { background:#d1fae5; color:#065f46; }
.stage-pill.current { background:var(--blue); color:#fff; }
.stage-pill.locked  { background:#f1f5f9; color:#94a3b8; }

.btn-add { background:var(--blue); color:#fff; border:none; padding:10px 22px; border-radius:8px; font-weight:700; font-size:13px; cursor:pointer; }
.btn-add:hover { background:var(--navy); }
@media print {
  @page { size: landscape; margin: 0; }
  body { margin: 0; padding: 0; background: #fff; }
  body * { visibility: hidden; }
  .cert-wrap, .cert-wrap * { visibility: visible; }
  .cert-wrap {
    position: fixed;
    top: 0;
    left: 0;
    width: 100vw;
    height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
    background: #fff;
    z-index: 9999;
  }
  .certificate {
    max-width: 95vw !important;
    border: 10px solid #0f2557 !important;
    box-shadow: none !important;
    page-break-inside: avoid;
    transform: scale(0.95);
  }
}
</style>
</head>
<body>
<?php if (isset($_SESSION['anti_cheat_failed'])): ?>
    <div style="position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(15, 37, 87, 0.95); z-index:999999; display:flex; flex-direction:column; justify-content:center; align-items:center; text-align:center; backdrop-filter:blur(10px);">
        <i class="fas fa-times-circle" style="font-size:80px; color:#ef4444; margin-bottom:24px;"></i>
        <h2 style="color:#fff; font-weight:800; font-size:36px; margin-bottom:16px;">Test Attempt Failed!</h2>
        <p style="color:#e2e8f0; font-size:18px; font-weight:500; max-width:600px; margin-bottom:30px; line-height:1.6;">
            Your test attempt has automatically been failed and marked as 0% due to a violation of the strict anti-cheat rules (e.g. switching tabs or leaving the browser window).
        </p>
        <form method="POST" style="margin:0;">
            <input type="hidden" name="action" value="acknowledge_anti_cheat">
            <button type="submit" class="btn-add" style="background:#ef4444; padding:16px 40px; font-size:18px; border-radius:12px; box-shadow:0 10px 25px rgba(239,68,68,0.3); border:none; color:#fff; font-weight:700; cursor:pointer;">
                <i class="fas fa-check-circle mr-2"></i> I Understand
            </button>
        </form>
    </div>
<?php endif; ?>
<div class="container-fluid" style="margin:0 auto;padding:20px 30px;">

<?php if(isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show"><i class="fas fa-check-circle mr-2"></i><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>
<?php if(isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show"><i class="fas fa-exclamation-circle mr-2"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>

<!-- HEADER -->
<div class="oje-header">
  <div>
    <h1><i class="fas fa-sync-alt mr-2"></i> My Recertification & Cross Training</h1>
    <p>Track your recertification cycles and cross training assignments</p>
  </div>
  <div style="display:flex;gap:10px;align-items:center;">
    <?php if ($empRow): ?>
    <span style="color:#fff;font-size:13px;font-weight:700;"><i class="fas fa-user mr-1"></i><?php echo htmlspecialchars($empRow['name']); ?></span>
    <?php endif; ?>
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    
    <a href="hr-employee-OJE.php<?php echo $isHRView ? "?view_emp=$employee_id&dept_id=$dept_id&pos_id=$pos_id" : ""; ?>" class="btn btn-light btn-sm" style="font-weight:700;"><i class="fas fa-arrow-left mr-1"></i> Back to Training</a>
  </div>
</div>

<?php if (!$empRow): ?>
<div class="card-box"><div class="empty-hint"><i class="fas fa-user-slash fa-3x mb-3"></i><h5>Employee record not found</h5></div></div>

<?php else: ?>

  <ul class="nav nav-tabs mb-4" id="employeeTabs" role="tablist" style="border-bottom: 2px solid #e2e8f0; border-radius: 0;">
    <li class="nav-item">
      <a class="nav-link" href="hr-employee-OJE.php"><i class="fas fa-book-open mr-1"></i> Current Progress</a>
    </li>
    <li class="nav-item">
      <a class="nav-link <?php echo $active_tab==='recert'?'active':''; ?>" data-toggle="tab" href="#recert" role="tab"><i class="fas fa-sync-alt mr-1"></i> Recertification</a>
    </li>
    <li class="nav-item">
      <a class="nav-link <?php echo $active_tab==='crosstraining'?'active':''; ?>" data-toggle="tab" href="#crosstraining" role="tab"><i class="fas fa-exchange-alt mr-1"></i> Cross Training</a>
    </li>
    <li class="nav-item">
      <a class="nav-link <?php echo $active_tab==='history'?'active':''; ?>" data-toggle="tab" href="#history" role="tab"><i class="fas fa-history mr-1"></i> History & Certificates</a>
    </li>
  </ul>
  
  <div class="tab-content" id="employeeTabsContent">
    <div class="tab-pane <?php echo $active_tab==='recert'?'fade show active':'fade'; ?>" id="recert" role="tabpanel">

<!-- ======================= RECERTIFICATION SECTION ======================= -->
<div class="card-box">
  <h5><i class="fas fa-sync-alt mr-2 text-warning"></i>Recertification</h5>

  <?php if ($isBlueCollarPosition): ?>
    <div class="empty-hint"><i class="fas fa-clipboard-check fa-2x mb-2" style="color:#3730a3;"></i><p>This role is classified Blue Collar — Recertification &amp; Cross-training is not required.</p></div>

  <?php elseif (!$is_certified): ?>
    <div class="empty-hint"><i class="fas fa-lock fa-2x mb-2"></i><p>Recertification is only available after you have completed and certified in the main Training & OJE program.</p></div>

  <?php elseif (!$is_configured): ?>
    <div class="status-banner info"><i class="fas fa-info-circle"></i> You are up to date! HR has not configured the next recertification cycle yet.</div>

  <?php elseif (!$is_due): ?>
    <!-- NOT YET DUE — countdown card -->
    <div class="card-box" style="border:1.5px solid #fde68a;background:#fffbeb;margin-bottom:20px;">
      <div style="text-align:center;padding:20px 0;">
        <div style="font-size:48px;font-weight:900;color:#b45309;line-height:1;margin-bottom:8px;"><?php echo max(0, $days_left); ?></div>
        <div style="font-size:14px;font-weight:700;color:#d97706;text-transform:uppercase;letter-spacing:1px;margin-bottom:12px;">Day(s) Until Recertification</div>
        <div style="font-size:13px;color:#92400e;">
          <i class="fas fa-calendar-alt mr-1"></i> Due Date: <strong><?php echo date('d M Y', strtotime($due_date)); ?></strong> | Cycle <?php echo $cycle_number; ?> | Interval: Every <?php echo $recert_interval; ?> <?php echo $recert_int_type; ?>
        </div>
      </div>
    </div>
    <div class="status-banner info"><i class="fas fa-info-circle"></i> You are on track. The recertification test will become available on <?php echo date('d M Y', strtotime($due_date)); ?>.</div>
  <?php endif; ?>

  <?php if ((!$is_due || !$is_configured) && $lastPass): ?>
    <?php 
    $cert_cycle = intval($lastPass['cycle_number']); 
    $recert_cert_number = 'RECERT-' . date('Y', strtotime($lastPass['attempted_at'])) . '-C' . $cert_cycle . '-' . str_pad($employee_id, 5, '0', STR_PAD_LEFT);
    ?>
    <div class="cert-wrap" style="margin-top:40px;">
      <div class="certificate" id="recertCertCard">
        <?php if (!empty($co_settings['company_logo'])): ?>
          <img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" alt="Company Logo" style="max-height:130px; max-width:320px; object-fit:contain; margin-bottom:10px; display:block; margin-left:auto; margin-right:auto;">
        <?php else: ?>
          <div class="cert-icon"><i class="fas fa-award"></i></div>
        <?php endif; ?>
        
        <div style="font-size:16px;font-weight:700;color:var(--navy);margin-bottom:15px;text-transform:uppercase;letter-spacing:1px;">
          <?php echo htmlspecialchars(!empty($co_settings['company_name']) ? $co_settings['company_name'] : ($_SESSION['ge_cname'] ?? 'Company')); ?>
        </div>
        
        <div class="cert-title">Recertification Certificate</div>
        <div style="font-size:13px;color:#64748b;margin-bottom:10px;">Cycle <?php echo $cert_cycle; ?> — <?php echo htmlspecialchars($deptName); ?> / <?php echo htmlspecialchars($posName); ?></div>
        <div style="font-size:13px;color:#64748b;">This certifies that</div>
        <div class="cert-name"><?php echo htmlspecialchars($empRow['name']); ?></div>
        <div class="cert-body">has successfully completed Recertification Cycle <?php echo $cert_cycle; ?> for the position of <strong><?php echo htmlspecialchars($posName); ?></strong> in the <strong><?php echo htmlspecialchars($deptName); ?></strong> department, demonstrating continued knowledge and competency.</div>
        <div class="cert-footer">
          <div><strong><?php echo date('d M Y', strtotime($lastPass['attempted_at'])); ?></strong>Date Issued</div>
          <div><strong><?php echo $recert_cert_number; ?></strong>Certificate No.</div>
          <div>
            <?php if (!empty($co_settings['company_signature'])): ?>
              <img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" alt="Authorized Signature" style="max-height:140px; max-width:320px; display:block; margin: 0 auto 5px;">
            <?php endif; ?>
            <strong>Authorized Signatory</strong>
          </div>
        </div>
      </div>
    </div>
    <div class="text-center" style="display:flex;justify-content:center;gap:12px;">
      <button type="button" class="btn-add" onclick="downloadRecertCert()"><i class="fas fa-download mr-1"></i> Download Image</button>
      <button type="button" class="btn-add" style="background:#fff;color:var(--navy);border:2px solid var(--navy);" onclick="window.print()"><i class="fas fa-print mr-1"></i> Print</button>
    </div>
    <?php endif; ?>

  <?php if ($recert_failed): ?>
    <!-- FAILED ALL ATTEMPTS -->
    <div style="text-align:center;padding:40px 20px;background:#fffbfb;border:1.5px solid #fecaca;border-radius:12px;">
      <i class="fas fa-times-circle" style="font-size:50px;color:var(--red);margin-bottom:14px;"></i>
      <h5 style="color:var(--red);">Recertification Cycle <?php echo $cycle_number; ?> — All Attempts Used</h5>
      <p style="color:#64748b;font-size:14px;max-width:480px;margin:0 auto;">You have used all <?php echo $recert_max_att; ?> attempts for this cycle. HR has been notified and will follow up with you shortly regarding next steps.</p>
    </div>



  <?php elseif ($is_configured && $is_due): ?>
    <!-- DUE — show test -->
    <div class="overdue-banner">
      <i class="fas fa-exclamation-circle"></i>
      <div>
        <div class="ob-title">Recertification Test Due — Cycle <?php echo $cycle_number; ?></div>
        <div class="ob-sub">Due date: <?php echo date('d M Y', strtotime($due_date)); ?> &nbsp;|&nbsp; Attempt <?php echo $recert_attempts_used + 1; ?> of <?php echo $recert_max_att; ?></div>
      </div>
    </div>
    <div class="status-banner warn"><i class="fas fa-info-circle"></i> You need <strong><?php echo number_format($recert_pass_pct, 0); ?>%</strong> or higher to pass.</div>

    <?php if (empty($recert_questions)): ?>
      <div class="empty-hint"><i class="fas fa-question fa-2x mb-2"></i><p>No recertification questions configured yet. Please contact HR.</p></div>
    <?php elseif (!$isHRView): ?>
      <div id="startRecertBlock" class="text-center" style="margin:40px 0;">
        <button type="button" id="btnStartRecert" class="btn-add" style="font-size:16px;padding:14px 30px;" onclick="document.getElementById('startRecertBlock').style.display='none'; document.getElementById('recertTestForm').style.display='block';"><i class="fas fa-play mr-2"></i> Start Recertification Test</button>
      </div>
      <form method="POST" id="recertTestForm" style="display:none;" oncontextmenu="return false;" onselectstart="return false;">
        <input type="hidden" name="action" value="submit_recert_test">
        <?php foreach ($recert_questions as $idx => $q): ?>
        <div class="q-card">
          <div class="q-num">Question <?php echo $idx+1; ?> of <?php echo count($recert_questions); ?></div>
          <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
          <?php if (($q['question_type'] ?? 'mcq') === 'text'): ?>
          <textarea name="answers[<?php echo $q['id']; ?>]" rows="4" required placeholder="Type your answer here..." style="width:100%;border:1.5px solid #e0e7ff;border-radius:8px;padding:10px 12px;font-size:13px;font-family:inherit;resize:vertical;"></textarea>
          <?php else: ?>
          <?php foreach ($q['options'] as $opt): ?>
          <label class="opt-label">
            <input type="radio" name="answers[<?php echo $q['id']; ?>]" value="<?php echo $opt['id']; ?>" required>
            <span><?php echo htmlspecialchars($opt['label']); ?></span>
          </label>
          <?php endforeach; ?>
          <?php endif; ?>
        </div>
        <?php endforeach; ?>
        <button type="submit" class="btn-add"><i class="fas fa-paper-plane mr-1"></i> Submit Recertification Test</button>
      </form>
    <?php endif; ?>
  <?php endif; ?>

  <!-- Attempt History -->
  <?php if (!empty($recert_attempts)): ?>
  <h6 class="mt-4" style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;">Cycle <?php echo $cycle_number; ?> Attempt History</h6>
  <table class="history-table">
    <thead><tr><th>#</th><th>Date</th><th>Score</th><th>Result</th></tr></thead>
    <tbody>
      <?php foreach ($recert_attempts as $a): ?>
      <tr>
        <td><?php echo $a['attempt_number']; ?></td>
        <td><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
        <td><?php echo number_format($a['percentage'], 1); ?>%</td>
        <td class="<?php echo $a['passed']?'pf-pass':'pf-fail'; ?>"><?php echo $a['passed']?'Passed':'Failed'; ?></td>
      </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>
</div>

</div><!-- End Recertification Tab -->

    <div class="tab-pane <?php echo $active_tab==='crosstraining'?'fade show active':'fade'; ?>" id="crosstraining" role="tabpanel">
<!-- ======================= CROSS TRAINING SECTION ======================= -->
<?php if (!empty($cross_training_active)): ?>
<div class="card-box">
  <h5><i class="fas fa-exchange-alt mr-2 text-info"></i>My Cross Training Assignments</h5>

  <?php foreach ($cross_training_active as $ct):
    $ctStage = $ct['ct_stage'] ?? 'training';
    $stageOrder = ['training'=>1,'training_test'=>2,'oje_reading'=>3,'oje_test'=>4,'certified'=>5];
    $stageNames = ['training'=>'Training','training_test'=>'Training Test','oje_reading'=>'OJE Reading','oje_test'=>'OJE Test','certified'=>'Certified'];
    $ctCurrent = $stageOrder[$ctStage] ?? 1;
  ?>
  <div class="ct-card">
    <div class="ct-title">
      <i class="fas fa-exchange-alt mr-2" style="color:var(--blue);"></i>
      <?php echo htmlspecialchars($ct['from_dept_name'] ?? 'N/A'); ?> → <?php echo htmlspecialchars($ct['to_dept_name'] ?? 'N/A'); ?>
      <?php if ($ct['status'] === 'completed'): ?>
        <span style="background:#d1fae5;color:#065f46;font-size:11px;font-weight:800;padding:3px 10px;border-radius:12px;margin-left:8px;"><i class="fas fa-check mr-1"></i>Completed</span>
      <?php elseif ($ct['status'] === 'cancelled'): ?>
        <span style="background:#f1f5f9;color:#64748b;font-size:11px;font-weight:800;padding:3px 10px;border-radius:12px;margin-left:8px;">Cancelled</span>
      <?php endif; ?>
    </div>

    <div style="font-size:12px;color:#64748b;margin-bottom:12px;">
      <i class="fas fa-calendar mr-1"></i> Start: <?php echo $ct['start_date'] ? date('d M Y', strtotime($ct['start_date'])) : '—'; ?>
      &nbsp;|&nbsp; <i class="fas fa-user mr-1"></i> Initiated by: <?php echo htmlspecialchars($ct['initiated_by'] ?? ''); ?>
      <?php if (!empty($ct['to_pos_name'])): ?>&nbsp;|&nbsp; <i class="fas fa-briefcase mr-1"></i> Target Position: <?php echo htmlspecialchars($ct['to_pos_name']); ?><?php endif; ?>
    </div>

    <!-- Stage flow -->
    <div class="stage-flow">
      <?php foreach ($stageOrder as $sKey => $sIdx):
        $state = $sIdx < $ctCurrent ? 'done' : ($sIdx == $ctCurrent ? 'current' : 'locked');
      ?>
      <span class="stage-pill <?php echo $state; ?>">
        <?php if ($state==='done'): ?><i class="fas fa-check mr-1"></i><?php elseif($state==='current'): ?><i class="fas fa-circle mr-1" style="font-size:8px;"></i><?php else: ?><i class="fas fa-lock mr-1" style="font-size:9px;"></i><?php endif; ?>
        <?php echo $stageNames[$sKey]; ?>
      </span>
      <?php endforeach; ?>
    </div>

    <div class="mt-3">
      <?php 
        $btnText = ($ctStage === 'certified' || $ct['status'] === 'completed') ? 'View Training Details' : 'Start / Accept Cross Training';
        $ctLink = "hr-employee-OJE.php?";
        if ($isHRView) {
            $ctLink .= "view_emp=$employee_id&dept_id={$ct['to_dept_id']}&pos_id={$ct['to_pos_id']}&is_cross=1";
        } else {
            $ctLink .= "cross_dept_id={$ct['to_dept_id']}&cross_pos_id={$ct['to_pos_id']}";
        }
      ?>
      <a href="<?php echo $ctLink; ?>" class="btn-add" style="font-size:12px;padding:8px 16px;text-decoration:none;">
        <i class="fas <?php echo ($ctStage === 'certified' || $ct['status'] === 'completed') ? 'fa-eye' : 'fa-arrow-right'; ?> mr-1"></i> <?php echo $btnText; ?>
      </a>
    </div>

    <?php if ($ctStage === 'certified'): ?>
    <div style="margin-top:12px;padding:10px 14px;background:#d1fae5;border:1px solid #6ee7b7;border-radius:8px;font-size:13px;font-weight:700;color:#065f46;">
      <i class="fas fa-certificate mr-1"></i> Cross Training Certified! You are now qualified in <?php echo htmlspecialchars($ct['to_dept_name']); ?>.
    </div>
    <?php endif; ?>
  </div>
  <?php endforeach; ?>
</div>
<?php else: ?>
  <div class="card-box">
    <div class="empty-hint"><i class="fas fa-exchange-alt fa-2x mb-2"></i><p>You have no active cross training assignments.</p></div>
  </div>
<?php endif; ?>
<?php
// History data for the History tab
$history_q = mysqli_query($con, "SELECT a.*, d.name as dept_name, p.title as pos_title
    FROM hr_oje_recert_attempts a
    LEFT JOIN hr_departments d ON d.id=a.department_id
    LEFT JOIN hr_positions p ON p.id=a.position_id
    WHERE a.employee_id=$employee_id
    ORDER BY a.attempted_at DESC");
$full_history = [];
if ($history_q) {
    while ($h = mysqli_fetch_assoc($history_q)) {
        $full_history[] = $h;
    }
}
?>
<!-- History Tab Pane -->
    </div><!-- End Cross Training Tab -->
    
    <div class="tab-pane <?php echo $active_tab==='history'?'fade show active':'fade'; ?>" id="history" role="tabpanel">
        <div class="card-box">
          <h5 style="margin-bottom:20px;"><i class="fas fa-history mr-2 text-warning"></i>Full History & Certificates</h5>
        
          <!-- OJE/Training Certificates -->
          <h6 class="section-head section-head-training"><i class="fas fa-graduation-cap mr-2" style="color:#3b82f6;"></i>Training & OJE Certificates</h6>
          <?php
          $oje_hist = mysqli_query($con, "SELECT p.*, d.name as dept_name, pos.title as pos_title, (SELECT percentage FROM hr_oje_test_attempts a WHERE a.employee_id=p.employee_id AND a.department_id=p.department_id AND a.position_id=p.position_id ORDER BY a.id DESC LIMIT 1) as latest_score FROM hr_oje_employee_progress p LEFT JOIN hr_departments d ON d.id=p.department_id LEFT JOIN hr_positions pos ON pos.id=p.position_id WHERE p.employee_id=$employee_id ORDER BY p.certified_at DESC, p.id DESC");
          $oje_hist_rows = [];
          if ($oje_hist) while ($h = mysqli_fetch_assoc($oje_hist)) $oje_hist_rows[] = $h;
          ?>
          <?php if (empty($oje_hist_rows)): ?>
            <p style="color:#94a3b8;font-size:13px;margin-bottom:20px;">No training records found.</p>
          <?php else: ?>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:10px;">
            <div style="display:flex; gap:8px; align-items:center;">
              <input type="date" id="oje-from" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="From Date">
              <input type="date" id="oje-to" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="To Date">
              <button class="btn btn-sm btn-light" onclick="filterTableDates('table-training', 'oje-from', 'oje-to', 0)" style="font-weight:700;"><i class="fas fa-filter"></i></button>
              <button class="btn btn-sm btn-light" onclick="resetTableDates('table-training', 'oje-from', 'oje-to')" style="font-weight:700;"><i class="fas fa-sync-alt"></i></button>
            </div>
            <button class="btn btn-sm" onclick="exportTable('table-training', 'Training_Certificates.csv')" style="font-weight:700;background:var(--blue);color:#fff;border:none;"><i class="fas fa-file-export mr-1"></i> Export CSV</button>
          </div>
          <div class="table-responsive" style="margin-bottom:24px;">
            <table class="history-table table-training">
              <thead><tr>
                <th>Date</th>
                <th>Department</th>
                <th>Position</th>
                <th>Stage</th>
                <th>Score</th>
                <th>Result</th>
              </tr></thead>
              <tbody>
                <?php foreach ($oje_hist_rows as $h): ?>
                <tr>
                  <td><?php echo $h['training_started_at'] ? date('d M Y, h:i A', strtotime($h['training_started_at'])) : '-'; ?></td>
                  <td><?php echo htmlspecialchars($h['dept_name']); ?></td>
                  <td><?php echo htmlspecialchars($h['pos_title'] ?? 'All'); ?></td>
                  <td><?php echo ucfirst(str_replace('_',' ',$h['stage'])); ?></td>
                  <td style="font-weight:700;"><?php echo isset($h['latest_score']) ? number_format($h['latest_score'], 1) . '%' : '-'; ?></td>
                  <td>
                    <?php if ($h['stage'] === 'certified'): ?>
                      <span class="pf-pass"><i class="fas fa-check-circle mr-1"></i>Passed</span>
                      <div style="margin-top:4px;"><a href="javascript:void(0)" onclick="$('#oje-cert-<?php echo $h['id']; ?>').slideToggle()" style="font-size:11px;text-decoration:underline;font-weight:700;color:var(--blue);">View Certificate</a></div>
                    <?php elseif ($h['stage'] === 'failed'): ?>
                      <span class="pf-fail"><i class="fas fa-times-circle mr-1"></i>Failed</span>
                    <?php else: ?>
                      <span style="color:#1e40af;font-weight:800;"><i class="fas fa-spinner fa-spin mr-1"></i>In Progress</span>
                    <?php endif; ?>
                  </td>
                </tr>
                <?php if ($h['stage'] === 'certified'): ?>
                <tr id="oje-cert-<?php echo $h['id']; ?>" style="display:none;background:#f8fafc;">
                  <td colspan="6" style="padding:24px;">
                    <div style="display:flex;justify-content:center;">
                      <div class="certificate" id="oje-cert-card-<?php echo $h['id']; ?>">
                        <?php if (!empty($co_settings['company_logo'])): ?>
                          <img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" style="max-height:100px;max-width:240px;object-fit:contain;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto;">
                        <?php endif; ?>
                        <div style="font-size:14px;font-weight:800;color:var(--navy);text-transform:uppercase;letter-spacing:1px;"><?php echo htmlspecialchars($co_settings['company_name'] ?? ''); ?></div>
                        <div class="cert-title">Certificate of Completion</div>
                        <div style="font-size:12px;color:#64748b;margin-bottom:10px;">Training & OJE Program</div>
                        <div style="font-size:12px;color:#64748b;">This certifies that</div>
                        <div class="cert-name"><?php echo htmlspecialchars($empRow['name']); ?></div>
                        <div class="cert-body">has successfully completed the Training & OJE Program for <strong><?php echo htmlspecialchars($h['pos_title'] ?? 'All Positions'); ?></strong> in <strong><?php echo htmlspecialchars($h['dept_name']); ?></strong> department.</div>
                        <div class="cert-footer">
                          <div><strong><?php echo date('d M Y', strtotime($h['certified_at'])); ?></strong>Date Issued</div>
                          <div><strong>CERT-<?php echo date('Y',strtotime($h['certified_at'])).'-'.str_pad($employee_id,5,'0',STR_PAD_LEFT); ?></strong>Cert No.</div>
                          <div><?php if (!empty($co_settings['company_signature'])): ?><img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" style="max-height:60px;display:block;margin:0 auto 4px;"><?php endif; ?><strong>Authorized Signatory</strong></div>
                        </div>
                      </div>
                    </div>
                    <div style="text-align:center;margin-top:12px;display:flex;justify-content:center;gap:10px;">
                      <button onclick="downloadRecertCert('oje-cert-card-<?php echo $h['id']; ?>')" class="btn-add" style="font-size:12px;padding:8px 16px;"><i class="fas fa-download mr-1"></i> Download</button>
                      <button onclick="window.print()" class="btn-add" style="font-size:12px;padding:8px 16px;background:#fff;color:var(--navy);border:2px solid var(--navy);"><i class="fas fa-print mr-1"></i> Print</button>
                    </div>
                  </td>
                </tr>
                <?php endif; ?>
                <?php endforeach; ?>
              </tbody>
            </table>
          </div>
          <?php endif; ?>
        
          <!-- Recertification History -->
          <h6 class="section-head section-head-recert"><i class="fas fa-sync-alt mr-2" style="color:#eab308;"></i>Recertification History</h6>
          <?php
          $recert_hist = mysqli_query($con, "SELECT a.*, d.name as dept_name, p.title as pos_title FROM hr_oje_recert_attempts a LEFT JOIN hr_departments d ON d.id=a.department_id LEFT JOIN hr_positions p ON p.id=a.position_id WHERE a.employee_id=$employee_id ORDER BY a.attempted_at DESC");
          $recert_hist_rows = [];
          if ($recert_hist) while ($h = mysqli_fetch_assoc($recert_hist)) $recert_hist_rows[] = $h;
          ?>
          <?php if (empty($recert_hist_rows)): ?>
            <p style="color:#94a3b8;font-size:13px;margin-bottom:20px;">No recertification attempts yet.</p>
          <?php else: ?>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:10px;">
            <div style="display:flex; gap:8px; align-items:center;">
              <input type="date" id="recert-from" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="From Date">
              <input type="date" id="recert-to" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="To Date">
              <button class="btn btn-sm btn-light" onclick="filterTableDates('table-recert', 'recert-from', 'recert-to', 0)" style="font-weight:700;"><i class="fas fa-filter"></i></button>
              <button class="btn btn-sm btn-light" onclick="resetTableDates('table-recert', 'recert-from', 'recert-to')" style="font-weight:700;"><i class="fas fa-sync-alt"></i></button>
            </div>
            <button class="btn btn-sm" onclick="exportTable('table-recert', 'Recertification_History.csv')" style="font-weight:700;background:#eab308;color:#fff;border:none;"><i class="fas fa-file-export mr-1"></i> Export CSV</button>
          </div>
          <div class="table-responsive" style="margin-bottom:24px;">
            <table class="history-table table-recert">
              <thead><tr>
                <th>Date</th><th>Department</th><th>Position</th><th>Cycle</th><th>Score</th><th>Result</th>
              </tr></thead>
              <tbody>
                <?php foreach ($recert_hist_rows as $h): ?>
                <tr>
                  <td><?php echo date('d M Y, h:i A', strtotime($h['attempted_at'])); ?></td>
                  <td><?php echo htmlspecialchars($h['dept_name']); ?></td>
                  <td><?php echo htmlspecialchars($h['pos_title'] ?? 'All'); ?></td>
                  <td>C<?php echo $h['cycle_number']; ?> / Att <?php echo $h['attempt_number']; ?></td>
                  <td style="font-weight:700;"><?php echo number_format($h['percentage'],1); ?>%</td>
                  <td>
                    <?php if ($h['passed']): ?>
                      <span class="pf-pass"><i class="fas fa-check-circle mr-1"></i>Passed</span>
                      <div style="margin-top:4px;"><a href="javascript:void(0)" onclick="$('#recert-cert-<?php echo $h['id']; ?>').slideToggle()" style="font-size:11px;text-decoration:underline;font-weight:700;color:var(--blue);">View Certificate</a></div>
                    <?php else: ?>
                      <span class="pf-fail"><i class="fas fa-times-circle mr-1"></i>Failed</span>
                    <?php endif; ?>
                  </td>
                </tr>
                <?php if ($h['passed']): ?>
                <tr id="recert-cert-<?php echo $h['id']; ?>" style="display:none;background:#f8fafc;">
                  <td colspan="6" style="padding:24px;">
                    <div style="display:flex;justify-content:center;">
                      <div class="certificate" id="recert-cert-card-<?php echo $h['id']; ?>">
                        <?php if (!empty($co_settings['company_logo'])): ?><img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" style="max-height:100px;max-width:240px;object-fit:contain;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto;"><?php endif; ?>
                        <div style="font-size:14px;font-weight:800;color:var(--navy);text-transform:uppercase;letter-spacing:1px;"><?php echo htmlspecialchars($co_settings['company_name'] ?? ''); ?></div>
                        <div class="cert-title">Recertification Certificate</div>
                        <div style="font-size:12px;color:#64748b;margin-bottom:10px;">Cycle <?php echo $h['cycle_number']; ?> — <?php echo htmlspecialchars($h['dept_name']); ?></div>
                        <div style="font-size:12px;color:#64748b;">This certifies that</div>
                        <div class="cert-name"><?php echo htmlspecialchars($empRow['name']); ?></div>
                        <div class="cert-body">has successfully completed Recertification Cycle <?php echo $h['cycle_number']; ?> for <strong><?php echo htmlspecialchars($h['pos_title'] ?? 'All Positions'); ?></strong> in <strong><?php echo htmlspecialchars($h['dept_name']); ?></strong> department. Score: <strong><?php echo number_format($h['percentage'],1); ?>%</strong></div>
                        <div class="cert-footer">
                          <div><strong><?php echo date('d M Y', strtotime($h['attempted_at'])); ?></strong>Date Issued</div>
                          <div><strong>RECERT-<?php echo date('Y',strtotime($h['attempted_at'])).'-C'.$h['cycle_number'].'-'.str_pad($employee_id,5,'0',STR_PAD_LEFT); ?></strong>Cert No.</div>
                          <div><?php if (!empty($co_settings['company_signature'])): ?><img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" style="max-height:60px;display:block;margin:0 auto 4px;"><?php endif; ?><strong>Authorized Signatory</strong></div>
                        </div>
                      </div>
                    </div>
                    <div style="text-align:center;margin-top:12px;display:flex;justify-content:center;gap:10px;">
                      <button onclick="downloadRecertCert('recert-cert-card-<?php echo $h['id']; ?>')" class="btn-add" style="font-size:12px;padding:8px 16px;"><i class="fas fa-download mr-1"></i> Download</button>
                      <button onclick="window.print()" class="btn-add" style="font-size:12px;padding:8px 16px;background:#fff;color:var(--navy);border:2px solid var(--navy);"><i class="fas fa-print mr-1"></i> Print</button>
                    </div>
                  </td>
                </tr>
                <?php endif; ?>
                <?php endforeach; ?>
              </tbody>
            </table>
          </div>
          <?php endif; ?>
        
          <!-- Cross Training History -->
          <h6 class="section-head section-head-cross"><i class="fas fa-exchange-alt mr-2" style="color:#14b8a6;"></i>Cross Training History</h6>
          <?php
          $ct_hist = mysqli_query($con, "SELECT ct.*, fd.name as from_dept_name, fp.title as from_pos_name, td.name as to_dept_name, tp.title as to_pos_name, p.stage as ct_stage, p.certified_at as ct_certified_at, (SELECT percentage FROM hr_oje_test_attempts a WHERE a.employee_id=ct.employee_id AND a.department_id=ct.to_dept_id AND a.position_id=ct.to_pos_id ORDER BY a.id DESC LIMIT 1) as latest_score FROM hr_oje_cross_training ct LEFT JOIN hr_departments fd ON fd.id=ct.from_dept_id LEFT JOIN hr_positions fp ON fp.id=ct.from_pos_id LEFT JOIN hr_departments td ON td.id=ct.to_dept_id LEFT JOIN hr_positions tp ON tp.id=ct.to_pos_id LEFT JOIN hr_oje_employee_progress p ON p.employee_id=ct.employee_id AND p.department_id=ct.to_dept_id AND p.position_id=ct.to_pos_id WHERE ct.employee_id=$employee_id ORDER BY ct.created_at DESC");
          $ct_hist_rows = [];
          if ($ct_hist) while ($h = mysqli_fetch_assoc($ct_hist)) $ct_hist_rows[] = $h;
          ?>
          <?php if (empty($ct_hist_rows)): ?>
            <p style="color:#94a3b8;font-size:13px;">No cross training records found.</p>
          <?php else: ?>
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; flex-wrap:wrap; gap:10px;">
            <div style="display:flex; gap:8px; align-items:center;">
              <input type="date" id="cross-from" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="From Date">
              <input type="date" id="cross-to" class="form-control form-control-sm" style="width:130px; height:32px; font-size:12px;" title="To Date">
              <button class="btn btn-sm btn-light" onclick="filterTableDates('table-cross', 'cross-from', 'cross-to', 0)" style="font-weight:700;"><i class="fas fa-filter"></i></button>
              <button class="btn btn-sm btn-light" onclick="resetTableDates('table-cross', 'cross-from', 'cross-to')" style="font-weight:700;"><i class="fas fa-sync-alt"></i></button>
            </div>
            <button class="btn btn-sm" onclick="exportTable('table-cross', 'CrossTraining_History.csv')" style="font-weight:700;background:#14b8a6;color:#fff;border:none;"><i class="fas fa-file-export mr-1"></i> Export CSV</button>
          </div>
          <div class="table-responsive">
            <table class="history-table table-cross">
              <thead><tr>
                <th>Date</th>
                <th>From</th>
                <th>To</th>
                <th>Stage</th>
                <th>Score</th>
                <th>Result</th>
              </tr></thead>
              <tbody>
                <?php foreach ($ct_hist_rows as $h): ?>
                <tr>
                  <td><?php echo $h['start_date'] ? date('d M Y', strtotime($h['start_date'])) : '-'; ?></td>
                  <td><?php echo htmlspecialchars($h['from_dept_name']); ?><br><span style="color:#64748b;font-size:11px;"><?php echo htmlspecialchars($h['from_pos_name'] ?? 'All'); ?></span></td>
                  <td><?php echo htmlspecialchars($h['to_dept_name']); ?><br><span style="color:#64748b;font-size:11px;"><?php echo htmlspecialchars($h['to_pos_name'] ?? 'All'); ?></span></td>
                  <td><?php echo $h['ct_stage'] ? ucfirst(str_replace('_',' ',$h['ct_stage'])) : '-'; ?></td>
                  <td style="font-weight:700;"><?php echo isset($h['latest_score']) ? number_format($h['latest_score'], 1) . '%' : '-'; ?></td>
                  <td>
                    <?php if ($h['status'] === 'completed'): ?>
                      <span class="pf-pass"><i class="fas fa-check-circle mr-1"></i>Passed</span>
                      <?php if ($h['ct_stage'] === 'certified' && !empty($h['ct_certified_at'])): ?>
                        <div style="margin-top:4px;font-size:11px;color:#64748b;">Cert: <?php echo date('d M Y', strtotime($h['ct_certified_at'])); ?></div>
                      <?php endif; ?>
                    <?php elseif ($h['status'] === 'cancelled'): ?>
                      <span class="pf-fail"><i class="fas fa-times-circle mr-1"></i>Failed (Cancelled)</span>
                    <?php else: ?>
                      <span style="color:#1e40af;font-weight:800;"><i class="fas fa-spinner fa-spin mr-1"></i>In Progress</span>
                    <?php endif; ?>
                  </td>
                </tr>
                <?php endforeach; ?>
              </tbody>
            </table>
          </div>
          <?php endif; ?>
        </div>
    </div><!-- End History Tab -->
  </div><!-- End Tab Content -->

<?php endif; ?> <!-- End $empRow check -->

</div> <!-- End Container Fluid -->

<!-- Anti-Cheat Overlay -->
<div id="antiCheatOverlay" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(15, 37, 87, 0.95); z-index:999999; flex-direction:column; justify-content:center; align-items:center; text-align:center; backdrop-filter:blur(10px);">
    <i class="fas fa-exclamation-triangle" style="font-size:72px; color:#ef4444; margin-bottom:24px;"></i>
    <h2 style="color:#fff; font-weight:800; font-size:32px; margin-bottom:12px;">Activity Flagged!</h2>
    <p id="antiCheatMsg" style="color:#e2e8f0; font-size:18px; font-weight:500; max-width:600px; margin-bottom:30px; line-height:1.6;">Tab switching or leaving the browser window is prohibited during the test.</p>
    <button type="button" onclick="document.getElementById('antiCheatOverlay').style.display='none'" class="btn-add" style="background:#ef4444; padding:14px 32px; font-size:16px; border-radius:12px; box-shadow:0 10px 25px rgba(239,68,68,0.3);">
        <i class="fas fa-check-circle mr-2"></i> I Understand
    </button>
</div>

<!-- Test Rules Modal -->
<div class="modal fade" id="testRulesModal" tabindex="-1" role="dialog" data-backdrop="static">
  <div class="modal-dialog modal-dialog-centered" style="max-width:500px;">
    <div class="modal-content" style="border-radius:16px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.15);">
      <div class="modal-header" style="background:#fefce8;border-radius:16px 16px 0 0;border-bottom:1px solid #fef08a;">
        <h5 class="modal-title" style="font-weight:800;color:#854d0e;"><i class="fas fa-exclamation-triangle mr-2"></i>Test Rules & Guidelines</h5>
      </div>
      <div class="modal-body" style="padding:24px;color:#334155;font-size:14px;line-height:1.6;">
        <p>Before you begin the test, please read the following rules carefully:</p>
        <ul style="margin-top:10px;margin-bottom:20px;padding-left:20px;">
            <li style="margin-bottom:8px;"><strong>No Copying or Pasting:</strong> Copying questions or pasting answers from external sources is strictly prohibited and technically disabled.</li>
            <li style="margin-bottom:8px;"><strong>No Tab Switching:</strong> Do not switch to other browser tabs or windows during the test. Your activity is monitored.</li>
            <li style="margin-bottom:8px;"><strong>No Context Menus:</strong> Right-clicking is disabled.</li>
        </ul>
        <p style="margin:0;font-weight:600;color:#b91c1c;">Violating these rules may result in automatic failure or disciplinary action.</p>
      </div>
      <div class="modal-footer" style="border-top:1px solid #e2e8f0;">
        <button type="button" class="btn btn-light" data-dismiss="modal" style="font-weight:600;">Cancel</button>
        <button type="button" class="btn btn-primary" id="rulesProceedBtn" style="font-weight:700;background:var(--blue);border:none;">I Understand, Start Test</button>
      </div>
    </div>
  </div>
</div>

<script>
function downloadRecertCert(certId) {
  var id = certId || 'recertCertCard';
  var el = document.getElementById(id);
  if (!el) return;

  var btn = event ? event.target.closest('button') : null;
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Preparing...'; }

  if (typeof html2canvas === 'undefined') {
      alert("Image generation library not loaded.");
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download mr-1"></i> Download Image'; }
      return;
  }

  html2canvas(el, { scale: 2, useCORS: true }).then(function(canvas) {
      var link = document.createElement('a');
      link.download = 'Certificate_Of_Completion.png';
      link.href = canvas.toDataURL('image/png');
      link.click();
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download mr-1"></i> Download Image'; }
  }).catch(function(err) {
      console.error('Image generation failed:', err);
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download mr-1"></i> Download Image'; }
  });
}
</script>
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="js/ui-load.js"></script><script src="js/ui-jp.config.js"></script>
<script src="js/ui-jp.js"></script><script src="js/ui-nav.js"></script><script src="js/ui-toggle.js"></script>
<script>
$(document).ready(function() {
    // If URL has a tab param or hash, switch to it automatically
    var urlParams = new URLSearchParams(window.location.search);
    var tabParam = urlParams.get('tab');
    var hash = window.location.hash;
    if (tabParam) {
        $('.nav-tabs a[href="#' + tabParam + '"]').tab('show');
    } else if (hash) {
        $('.nav-tabs a[href="' + hash + '"]').tab('show');
    }
});

function parseTableDate(dateStr) {
    if (!dateStr || dateStr.trim() === '-' || dateStr.trim() === '') return null;
    var cleanStr = dateStr.split(',')[0].trim();
    var d = new Date(cleanStr);
    return isNaN(d.getTime()) ? null : d;
}

function filterTableDates(tableClass, fromId, toId, colIndex) {
    var fromStr = document.getElementById(fromId).value;
    var toStr = document.getElementById(toId).value;
    
    var fromDate = fromStr ? new Date(fromStr) : null;
    var toDate = toStr ? new Date(toStr) : null;
    if (fromDate) fromDate.setHours(0,0,0,0);
    if (toDate) toDate.setHours(23,59,59,999);

    var table = document.querySelector('.' + tableClass);
    if (!table) return;
    var tbody = table.querySelector('tbody');
    var rows = tbody.querySelectorAll('tr:not([id^="oje-cert-"]):not([id^="recert-cert-"])');

    rows.forEach(function(row) {
        var dateCell = row.cells[colIndex];
        if (!dateCell) return;
        var rowDate = parseTableDate(dateCell.innerText);
        
        var show = true;
        if (rowDate) {
            if (fromDate && rowDate < fromDate) show = false;
            if (toDate && rowDate > toDate) show = false;
        } else {
            if (fromDate || toDate) show = false;
        }
        
        if (show) {
            row.style.display = '';
        } else {
            row.style.display = 'none';
            var nextRow = row.nextElementSibling;
            if (nextRow && nextRow.id && (nextRow.id.indexOf('-cert-') !== -1)) {
                nextRow.style.display = 'none';
            }
        }
    });
}

function resetTableDates(tableClass, fromId, toId) {
    document.getElementById(fromId).value = '';
    document.getElementById(toId).value = '';
    filterTableDates(tableClass, fromId, toId, 0);
}

function exportTable(tableClass, filename) {
    var table = document.querySelector('.' + tableClass);
    if (!table) return;
    
    var csv = [];
    var rows = table.querySelectorAll('tr:not([id^="oje-cert-"]):not([id^="recert-cert-"])');
    
    // Add header
    var theadRow = table.querySelector('thead tr');
    if (theadRow) {
        var header = [];
        var ths = theadRow.querySelectorAll('th');
        ths.forEach(function(th) {
            header.push('"' + th.innerText.replace(/"/g, '""') + '"');
        });
        csv.push(header.join(','));
    }
    
    // Add data
    for (var i = 0; i < rows.length; i++) {
        var row = [], cols = rows[i].querySelectorAll('td');
        if (rows[i].style.display === 'none') continue;
        
        for (var j = 0; j < cols.length; j++) {
            var data = cols[j].innerText.replace(/(\r\n|\n|\r)/gm, ' ').replace(/"/g, '""').trim();
            if (data.indexOf('View Certificate') !== -1) {
                data = data.replace('View Certificate', '').trim();
            }
            if (data.indexOf('Passed') === 0) data = data.replace('Passed', 'Passed ');
            if (data.indexOf('Failed') === 0) data = data.replace('Failed', 'Failed ');
            row.push('"' + data.trim() + '"');
        }
        csv.push(row.join(','));
    }
    
    var csvFile = new Blob([csv.join('\n')], {type: 'text/csv'});
    var downloadLink = document.createElement('a');
    downloadLink.download = filename;
    downloadLink.href = window.URL.createObjectURL(csvFile);
    downloadLink.style.display = 'none';
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
}

// Anti-Cheat Logic for Recertification
var testInProgress = false;
var elem = document.documentElement;

function startTestFullscreen() {
    if (elem.requestFullscreen) { elem.requestFullscreen(); }
    else if (elem.webkitRequestFullscreen) { elem.webkitRequestFullscreen(); }
    else if (elem.msRequestFullscreen) { elem.msRequestFullscreen(); }
}

$('#rulesProceedBtn').on('click', function() {
    $('#testRulesModal').modal('hide');
    startTestFullscreen();
    $('#startRecertBlock').hide();
    $('#recertTestForm').show();
    testInProgress = true;
});

function showAntiCheatOverlay(msg) {
    var overlay = document.getElementById('antiCheatOverlay');
    if (overlay) {
        document.getElementById('antiCheatMsg').innerText = msg;
        overlay.style.display = 'flex';
    }
}

document.addEventListener('copy', event => { if(testInProgress){ event.preventDefault(); showAntiCheatOverlay("Copying text is strictly prohibited."); } });
document.addEventListener('cut', event => { if(testInProgress){ event.preventDefault(); showAntiCheatOverlay("Cutting text is strictly prohibited."); } });
document.addEventListener('paste', event => { if(testInProgress){ event.preventDefault(); showAntiCheatOverlay("Pasting text from external sources is strictly prohibited."); } });
document.addEventListener('contextmenu', event => { if(testInProgress){ event.preventDefault(); } });

document.addEventListener("visibilitychange", function() {
    if (document.hidden && testInProgress) {
        showAntiCheatOverlay("Tab switching or leaving the browser window is prohibited during the test. Your activity has been flagged and your attempt has been submitted.");
        var tForm = document.getElementById('recertTestForm');
        if (tForm) {
            var statusInput = document.createElement('input');
            statusInput.type = 'hidden';
            statusInput.name = 'anti_cheat_violation';
            statusInput.value = '1';
            tForm.appendChild(statusInput);
            tForm.submit();
        }
    }
});
</script>



<?php if ($isHRView) include("footer.php"); ?>
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