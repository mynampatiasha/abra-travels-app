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

// =========================================================================
// ADMIN CHECK — same pattern as hr-employees-list.php, so "Back to Dashboard"
// goes to the same place for the same people across the app.
// =========================================================================
$authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$isAdmin = false;
foreach ($authorized_admin_names as $admin_name) {
    if (stripos($currentUserName, $admin_name) !== false || stripos($admin_name, $currentUserName) !== false) {
        $isAdmin = true;
        break;
    }
}

// =========================================================================
// CREATE TABLES IF NOT EXIST (mirrors hr-OJE.php so this page also works
// safely even if opened before hr-OJE.php has ever been visited)
// =========================================================================
$tables = [
"CREATE TABLE IF NOT EXISTS hr_oje_training_materials (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_material_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    heading_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    item_title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT NULL,
    document_path VARCHAR(500) DEFAULT NULL,
    document_filename VARCHAR(255) DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    training_days INT DEFAULT 7,
    oje_days INT DEFAULT 7,
    training_pass_percent DECIMAL(5,2) DEFAULT 95.00,
    oje_pass_percent DECIMAL(5,2) DEFAULT 95.00,
    max_attempts INT DEFAULT 3,
    created_by VARCHAR(255) DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_dept_pos (department_id, position_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_oje_content (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    content TEXT DEFAULT NULL,
    document_path VARCHAR(500) DEFAULT NULL,
    document_filename VARCHAR(255) DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    type ENUM('training','oje') NOT NULL DEFAULT 'training',
    question_text TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_question_options (
    id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    option_label VARCHAR(255) NOT NULL,
    points INT NOT NULL DEFAULT 0,
    is_correct TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_employee_progress (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    stage ENUM('training','training_test','oje_reading','oje_test','certified','failed') DEFAULT 'training',
    training_started_at DATETIME DEFAULT NULL,
    training_completed_at DATETIME DEFAULT NULL,
    oje_started_at DATETIME DEFAULT NULL,
    oje_reading_done_at DATETIME DEFAULT NULL,
    certified_at DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_emp_dept_pos (employee_id, department_id, position_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_material_completions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    item_id INT NOT NULL,
    completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_emp_item (employee_id, item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_test_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    type ENUM('training','oje') NOT NULL,
    attempt_number INT DEFAULT 1,
    total_marks INT DEFAULT 0,
    obtained_marks INT DEFAULT 0,
    percentage DECIMAL(5,2) DEFAULT 0,
    passed TINYINT(1) DEFAULT 0,
    answers_json LONGTEXT DEFAULT NULL,
    attempted_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_oje_completions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    oje_id INT NOT NULL,
    status ENUM('understood','not_understood') DEFAULT 'understood',
    completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_emp_oje (employee_id, oje_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) mysqli_query($con, $sql);
try { mysqli_query($con, "ALTER TABLE hr_oje_material_completions ADD COLUMN status ENUM('understood','not_understood') DEFAULT 'understood'"); } catch (Throwable $e) {}
try { mysqli_query($con, "ALTER TABLE hr_positions ADD COLUMN worker_category VARCHAR(20) NOT NULL DEFAULT 'professional'"); } catch (Throwable $e) {}

// =========================================================================
// HELPER FUNCTIONS
// =========================================================================

// Works out department_id / position_id for an hr_employees row, whether
// that table stores numeric IDs (department_id/position_id) or plain text
// names (department/position) — looks up hr_departments / hr_positions
// by name as a fallback.
function resolveDeptPos($con, $empRow) {
    $deptVal = $empRow['department_id'] ?? ($empRow['department'] ?? null);
    $posVal  = $empRow['position_id']   ?? ($empRow['position']   ?? null);
    $dept_id = 0; $pos_id = 0;

    if ($deptVal !== null && $deptVal !== '') {
        if (is_numeric($deptVal)) {
            $dept_id = intval($deptVal);
        } else {
            $dn = mysqli_real_escape_string($con, trim($deptVal));
            $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1"));
            if ($r) $dept_id = intval($r['id']);
        }
    }
    if ($posVal !== null && $posVal !== '') {
        if (is_numeric($posVal)) {
            $pos_id = intval($posVal);
        } else {
            $pn = mysqli_real_escape_string($con, trim($posVal));
            $where = $dept_id > 0 ? "AND department_id=$dept_id" : "";
            $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_positions WHERE title='$pn' $where LIMIT 1"));
            if ($r) $pos_id = intval($r['id']);
        }
    }
    return [$dept_id, $pos_id];
}

function getQuestionsWithOptions($con, $dept_id, $pos_id, $type) {
    $qs = [];
    $type = ($type === 'oje') ? 'oje' : 'training';
    $sql = "SELECT q.*, GROUP_CONCAT(o.id,'::',o.option_label,'::',o.points,'::',o.is_correct ORDER BY o.sort_order SEPARATOR '||') as options_raw
            FROM hr_oje_questions q LEFT JOIN hr_oje_question_options o ON o.question_id=q.id
            WHERE q.department_id=$dept_id AND (q.position_id=$pos_id OR q.position_id=0) AND q.type='$type'
            GROUP BY q.id ORDER BY q.sort_order ASC, q.id ASC";
    $r = mysqli_query($con, $sql);
    if ($r) while ($row = mysqli_fetch_assoc($r)) {
        $row['options'] = [];
        if (!empty($row['options_raw'])) {
            foreach (explode('||', $row['options_raw']) as $opt) {
                $p = explode('::', $opt);
                if (count($p) == 4) {
                    $row['options'][] = ['id' => intval($p[0]), 'label' => $p[1], 'points' => intval($p[2]), 'is_correct' => intval($p[3])];
                }
            }
        }
        $qs[] = $row;
    }
    return $qs;
}

function gradeTest($con, $dept_id, $pos_id, $type, $answers) {
    $questions = getQuestionsWithOptions($con, $dept_id, $pos_id, $type);
    $total = 0; $obtained = 0; $detail = [];
    foreach ($questions as $q) {
        if (empty($q['options'])) continue;
        $maxPts = 0;
        foreach ($q['options'] as $o) $maxPts = max($maxPts, $o['points']);
        $total += $maxPts;
        $selOptId = intval($answers[$q['id']] ?? 0);
        $gotPts = 0; $selLabel = '';
        foreach ($q['options'] as $o) {
            if ($o['id'] == $selOptId) { $gotPts = $o['points']; $selLabel = $o['label']; }
        }
        $obtained += $gotPts;
        $detail[] = [
            'question_id' => $q['id'], 'question_text' => $q['question_text'],
            'selected_option_id' => $selOptId, 'selected_label' => $selLabel,
            'points' => $gotPts, 'max' => $maxPts
        ];
    }
    $pct = $total > 0 ? round(($obtained / $total) * 100, 2) : 0;
    return [$total, $obtained, $pct, $detail];
}

function getAttempts($con, $employee_id, $dept_id, $pos_id, $type) {
    $rows = [];
    $type = ($type === 'oje') ? 'oje' : 'training';
    $r = mysqli_query($con, "SELECT * FROM hr_oje_test_attempts WHERE employee_id=$employee_id AND department_id=$dept_id AND position_id=$pos_id AND type='$type' ORDER BY attempt_number ASC");
    if ($r) while ($row = mysqli_fetch_assoc($r)) $rows[] = $row;
    return $rows;
}

// Auto-raises a ticket (using the existing tickets table/schema) assigned to
// whoever created the test questions, when an employee exhausts all attempts.
function raiseFailureTicket($con, $empRow, $type, $dept_id, $pos_id, $percentage, $deptName, $posName) {
    $type = ($type === 'oje') ? 'oje' : 'training';
    $typeLabel = ($type === 'oje') ? 'OJE' : 'Training';

    $credRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT created_by FROM hr_oje_questions WHERE department_id=$dept_id AND (position_id=$pos_id OR position_id=0) AND type='$type' AND created_by IS NOT NULL AND created_by<>'' ORDER BY id DESC LIMIT 1"));
    $creatorName = $credRow['created_by'] ?? '';
    $assigned_to = 0;
    if ($creatorName) {
        $cn = mysqli_real_escape_string($con, $creatorName);
        $cr = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE name='$cn' LIMIT 1"));
        if ($cr) $assigned_to = intval($cr['id']);
    }
    if (!$assigned_to) {
        $fr = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE status='active' ORDER BY id ASC LIMIT 1"));
        if ($fr) $assigned_to = intval($fr['id']);
    }
    if (!$assigned_to) return false;

    $rowmax = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
    $nextId = intval($rowmax['max_id'] ?? 0) + 1;
    $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
    $timeline = 1440;
    $deadline = date('Y-m-d H:i:s', strtotime("+{$timeline} minutes"));
    $name = $empRow['name'];
    $subject = "$typeLabel Test Failed (3/3 Attempts) - " . $empRow['name'];
    $message = "Employee: {$empRow['name']}\nDepartment: $deptName\nPosition: $posName\nTest Type: $typeLabel Test\nFinal Score: " . number_format($percentage, 1) . "%\n\nThe employee has used all available attempts and was unable to reach the required passing percentage. Please review their answers and follow up.";
    $priority = 'high';
    $status = 'open';
    $attachment = '';
    $created_by = intval($empRow['id']);

    $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), ?, ?)");
    if (!$stmt) return false;
    mysqli_stmt_bind_param($stmt, "ssssssissii", $ticket_number, $name, $subject, $message, $status, $priority, $timeline, $deadline, $attachment, $assigned_to, $created_by);
    $ok = mysqli_stmt_execute($stmt);
    mysqli_stmt_close($stmt);
    return $ok;
}

// =========================================================================
// RESOLVE MODE: HR viewing an employee (read-only) vs employee viewing self
// =========================================================================
$isHRView = false;
$empRow = null;
$employee_id = 0;
$dept_id = 0;
$pos_id = 0;

$isCrossTraining = false;
if (isset($_GET['view_emp']) && intval($_GET['view_emp']) > 0) {
    $isHRView = true;
    $employee_id = intval($_GET['view_emp']);
    $dept_id = intval($_GET['dept_id'] ?? 0);
    $pos_id  = intval($_GET['pos_id'] ?? 0);
    $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$employee_id LIMIT 1"));
    if (isset($_GET['is_cross']) && $_GET['is_cross'] == '1') $isCrossTraining = true;
} else {
    if ($currentUserName) {
        $un = mysqli_real_escape_string($con, $currentUserName);
        $r = mysqli_query($con, "SELECT * FROM hr_employees WHERE name='$un' LIMIT 1");
        if ($r && mysqli_num_rows($r) > 0) {
            $empRow = mysqli_fetch_assoc($r);
        } else {
            $r2 = mysqli_query($con, "SELECT * FROM hr_employees WHERE name LIKE '%$un%' LIMIT 1");
            if ($r2 && mysqli_num_rows($r2) > 0) $empRow = mysqli_fetch_assoc($r2);
        }
    }
    if ($empRow) {
        $employee_id = intval($empRow['id']);
        if (isset($_GET['cross_dept_id']) && isset($_GET['cross_pos_id'])) {
            $dept_id = intval($_GET['cross_dept_id']);
            $pos_id  = intval($_GET['cross_pos_id']);
            $isCrossTraining = true;
        } else {
            list($dept_id, $pos_id) = resolveDeptPos($con, $empRow);
        }
    }
}

$crossSuffix = $isCrossTraining ? "cross_dept_id={$dept_id}&cross_pos_id={$pos_id}" : "";

$noEmployee   = !$empRow;
$noDeptConfig = (!$noEmployee && $dept_id <= 0);

// Blue Collar positions don't require Training & OJE — the Observation Period substitutes for it.
$isBlueCollarPosition = false;
if ($pos_id > 0) {
    $wcRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT worker_category FROM hr_positions WHERE id=$pos_id"));
    $isBlueCollarPosition = $wcRow && ($wcRow['worker_category'] === 'blue_collar');
}

// =========================================================================
// COMPANY SETTINGS FOR LOGO & SIGNATURE
// =========================================================================
$co_settings = null;
if ($empRow && !empty($empRow['company_name'])) {
    $cn = mysqli_real_escape_string($con, $empRow['company_name']);
    $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_name='$cn' LIMIT 1"));
}
if (!$co_settings) {
    // Fallback to first available company if no match
    $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings ORDER BY id ASC LIMIT 1"));
}

// =========================================================================
// PROGRESS ROW (auto-created on first visit for self mode)
// =========================================================================
$progress = null;
if (!$noEmployee && !$noDeptConfig) {
    $progress = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_employee_progress WHERE employee_id=$employee_id AND department_id=$dept_id AND position_id=$pos_id LIMIT 1"));

    // Training only actually starts when the employee clicks "Start Training"
    // below (see the 'start_training' action) — not silently on page load.
    if (!$progress && !$isHRView && !$isBlueCollarPosition && $_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'start_training') {
        mysqli_query($con, "INSERT INTO hr_oje_employee_progress (employee_id, department_id, position_id, stage, training_started_at) VALUES ($employee_id, $dept_id, $pos_id, 'training', NOW())");
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }
}

// =========================================================================
// CONFIG (exact dept+pos match, fallback to dept + "all positions")
// =========================================================================
$config = null;
if ($dept_id > 0) {
    $config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_config WHERE department_id=$dept_id AND position_id=$pos_id LIMIT 1"));
    if (!$config) $config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_config WHERE department_id=$dept_id AND position_id=0 LIMIT 1"));
}
$training_days         = intval($config['training_days'] ?? 7);
$oje_days               = intval($config['oje_days'] ?? 7);
$training_pass_percent = floatval($config['training_pass_percent'] ?? 95);
$oje_pass_percent       = floatval($config['oje_pass_percent'] ?? 95);
$max_attempts           = intval($config['max_attempts'] ?? 3);

$deptName = 'N/A'; $posName = 'All Positions';
if ($dept_id > 0) {
    $dn = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id"));
    if ($dn) $deptName = $dn['name'];
}
if ($pos_id > 0) {
    $pn = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id"));
    if ($pn) $posName = $pn['title'];
}

// =========================================================================
// TRAINING MATERIALS + COMPLETIONS
// =========================================================================
$training_headings = [];
$allItemIds = [];
$total_items = 0;
if ($progress) {
    $hq = mysqli_query($con, "SELECT * FROM hr_oje_training_materials WHERE department_id=$dept_id AND (position_id=$pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($hq)) {
        $h['items'] = [];
        $iq = mysqli_query($con, "SELECT * FROM hr_oje_material_items WHERE heading_id={$h['id']} ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($iq)) { $h['items'][] = $i; $allItemIds[] = intval($i['id']); $total_items++; }
        $training_headings[] = $h;
    }
}
$completedItems = [];
if ($progress) {
    $cr = mysqli_query($con, "SELECT item_id, status FROM hr_oje_material_completions WHERE employee_id=$employee_id");
    while ($c = mysqli_fetch_assoc($cr)) $completedItems[intval($c['item_id'])] = $c['status'];
}
$completedItemIds = array_keys($completedItems);
$understoodItemIds = array_keys(array_filter($completedItems, function($s) { return $s === 'understood'; }));
$completed_count = count(array_intersect($understoodItemIds, $allItemIds));

// =========================================================================
// OJE CONTENT
// =========================================================================
$oje_contents = [];
$allOjeIds = [];
if ($progress) {
    $oq = mysqli_query($con, "SELECT * FROM hr_oje_oje_headings WHERE department_id=$dept_id AND (position_id=$pos_id OR position_id=0) ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($oq)) {
        $h['items'] = [];
        $iq = mysqli_query($con, "SELECT * FROM hr_oje_oje_items WHERE heading_id={$h['id']} ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($iq)) {
            $h['items'][] = $i;
            $allOjeIds[] = intval($i['id']);
        }
        $oje_contents[] = $h;
    }
}

$completedOjeItems = [];
if ($progress) {
    $ocr = mysqli_query($con, "SELECT item_id, status FROM hr_oje_material_completions WHERE employee_id=$employee_id AND item_id IN (SELECT id FROM hr_oje_oje_items WHERE department_id=$dept_id AND (position_id=$pos_id OR position_id=0))");
    while ($c = mysqli_fetch_assoc($ocr)) $completedOjeItems[intval($c['item_id'])] = $c['status'];
}
$completedOjeIds = array_keys($completedOjeItems);
$understoodOjeIds = array_keys(array_filter($completedOjeItems, function($s) { return $s === 'understood'; }));
$oje_completed_count = count(array_intersect($understoodOjeIds, $allOjeIds));

// =========================================================================
// DAYS / UNLOCK CALCULATIONS
// =========================================================================
$trainingDaysLeft = null; $trainingExpired = false;
if ($progress) {
    $startDateStr = (!empty($empRow['hire_date']) && $empRow['hire_date'] !== '0000-00-00') ? $empRow['hire_date'] : ($progress['training_started_at'] ?? '');
    if ($startDateStr) {
        $deadlineTs = strtotime($startDateStr) + ($training_days * 86400);
        $trainingDaysLeft = ceil(($deadlineTs - time()) / 86400);
        $trainingExpired = time() >= $deadlineTs;
    }
}
$trainingUnlocked = ($total_items > 0 && $completed_count >= $total_items);

$ojeDaysLeft = null; $ojeExpired = false; $ojeDeadlineTs = 0;
if ($progress && !empty($progress['oje_started_at'])) {
    $ojeDeadlineTs = strtotime($progress['oje_started_at']) + ($oje_days * 86400);
    $ojeDaysLeft = ceil(($ojeDeadlineTs - time()) / 86400);
    $ojeExpired = time() >= $ojeDeadlineTs;
}
$total_oje_items = count($allOjeIds);
$ojeTestUnlocked = ($total_oje_items > 0 && $oje_completed_count >= $total_oje_items);

// =========================================================================
// ATTEMPTS
// =========================================================================
$trainingAttempts   = $progress ? getAttempts($con, $employee_id, $dept_id, $pos_id, 'training') : [];
$ojeAttemptsArr     = $progress ? getAttempts($con, $employee_id, $dept_id, $pos_id, 'oje') : [];
$trainingAttemptsUsed = count($trainingAttempts);
$ojeAttemptsUsed      = count($ojeAttemptsArr);

$failedStageType = null;
if ($progress && $progress['stage'] === 'failed') {
    $lastOje = !empty($ojeAttemptsArr) ? end($ojeAttemptsArr) : null;
    $lastTraining = !empty($trainingAttempts) ? end($trainingAttempts) : null;
    if ($lastOje && intval($lastOje['attempt_number']) >= $max_attempts && !$lastOje['passed']) {
        $failedStageType = 'oje';
    } elseif ($lastTraining && intval($lastTraining['attempt_number']) >= $max_attempts && !$lastTraining['passed']) {
        $failedStageType = 'training';
    }
}

// =========================================================================
// POST HANDLERS (employee actions only — HR view is read-only)
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && !$isHRView && $progress) {
    $action = $_POST['action'];

    if ($action === 'mark_item_done' && $progress['stage'] === 'training') {
        $item_id = intval($_POST['item_id']);
        $status = in_array($_POST['status'] ?? '', ['understood','not_understood']) ? $_POST['status'] : 'understood';
        if (in_array($item_id, $allItemIds)) {
            mysqli_query($con, "INSERT INTO hr_oje_material_completions (employee_id, item_id, status) VALUES ($employee_id, $item_id, '$status') ON DUPLICATE KEY UPDATE status='$status', completed_at=NOW()");
        }
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if ($action === 'edit_item_done' && $progress['stage'] === 'training') {
        $item_id = intval($_POST['item_id']);
        mysqli_query($con, "DELETE FROM hr_oje_material_completions WHERE employee_id=$employee_id AND item_id=$item_id");
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if ($action === 'mark_oje_done' && $progress['stage'] === 'oje_reading') {
        $item_id = intval($_POST['oje_id']);
        $status = in_array($_POST['status'] ?? '', ['understood','not_understood']) ? $_POST['status'] : 'understood';
        if (in_array($item_id, $allOjeIds)) {
            mysqli_query($con, "INSERT INTO hr_oje_material_completions (employee_id, item_id, status) VALUES ($employee_id, $item_id, '$status') ON DUPLICATE KEY UPDATE status='$status', completed_at=NOW()");
        }
        header("Location: hr-employee-OJE.php?tab=oje_reading&$crossSuffix"); exit;
    }

    if ($action === 'edit_oje_done' && $progress['stage'] === 'oje_reading') {
        $item_id = intval($_POST['oje_id']);
        mysqli_query($con, "DELETE FROM hr_oje_material_completions WHERE employee_id=$employee_id AND item_id=$item_id");
        header("Location: hr-employee-OJE.php?tab=oje_reading&$crossSuffix"); exit;
    }

    if ($action === 'proceed_to_training_test' && $progress['stage'] === 'training' && $trainingUnlocked) {
        mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='training_test', training_completed_at=NOW() WHERE id={$progress['id']}");
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if ($action === 'proceed_to_oje_test' && $progress['stage'] === 'oje_reading' && $ojeTestUnlocked) {
        mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='oje_test' WHERE id={$progress['id']}");
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if (($action === 'submit_training_test' && $progress['stage'] === 'training_test') ||
        ($action === 'submit_oje_test' && $progress['stage'] === 'oje_test')) {

        $type = ($action === 'submit_oje_test') ? 'oje' : 'training';
        $answers = $_POST['answers'] ?? [];
        list($total, $obtained, $pct, $detail) = gradeTest($con, $dept_id, $pos_id, $type, $answers);
        $passPercent   = ($type === 'oje') ? $oje_pass_percent : $training_pass_percent;
        $attemptNumber = ($type === 'oje' ? $ojeAttemptsUsed : $trainingAttemptsUsed) + 1;
        $passed        = ($total > 0 && $pct >= $passPercent) ? 1 : 0;
        $answersJson   = mysqli_real_escape_string($con, json_encode($detail));

        mysqli_query($con, "INSERT INTO hr_oje_test_attempts (employee_id, department_id, position_id, type, attempt_number, total_marks, obtained_marks, percentage, passed, answers_json) VALUES ($employee_id, $dept_id, $pos_id, '$type', $attemptNumber, $total, $obtained, $pct, $passed, '$answersJson')");
$dbErr = mysqli_error($con);
if ($dbErr) {
    error_log("Test Insert Error: " . $dbErr);
    $_SESSION['error_message'] = "DB Error: " . $dbErr;
}

        if ($passed) {
            if ($type === 'training') {
                mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='oje_reading', oje_started_at=NOW() WHERE id={$progress['id']}");
                $_SESSION['success_message'] = "Congratulations! You scored " . number_format($pct, 1) . "% and passed the Training Test. You can now move on to the OJE stage.";
            } else {
                mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='certified', certified_at=NOW() WHERE id={$progress['id']}");
                $_SESSION['success_message'] = "Congratulations! You scored " . number_format($pct, 1) . "% and passed the OJE Test. Your certificate is ready below.";
            }
        } else {
            if ($attemptNumber >= $max_attempts) {
                mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='failed' WHERE id={$progress['id']}");
                raiseFailureTicket($con, $empRow, $type, $dept_id, $pos_id, $pct, $deptName, $posName);
                $_SESSION['error_message'] = "You scored " . number_format($pct, 1) . "% (required: " . number_format($passPercent, 1) . "%). You have used all $max_attempts attempts. A support ticket has been raised — HR will reach out to you shortly.";
            } else {
                $_SESSION['error_message'] = "You scored " . number_format($pct, 1) . "% (required: " . number_format($passPercent, 1) . "%). Attempt $attemptNumber of $max_attempts used — please review the material and try again.";
            }
        }
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if ($action === 'retrain' && $progress['stage'] === 'failed') {
        $failedType = $_POST['failed_type'] ?? 'training';
        $newStage = ($failedType === 'oje') ? 'oje_reading' : 'training';
        
        // Delete previous attempts for the failed stage so they get a fresh start
        mysqli_query($con, "DELETE FROM hr_oje_test_attempts WHERE employee_id=$employee_id AND department_id=$dept_id AND position_id=$pos_id AND type='$failedType'");
        
        // Reset the stage
        mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='$newStage' WHERE id={$progress['id']}");
        
        $_SESSION['success_message'] = "Your attempts have been reset. Please review the material and try again.";
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }

    if ($action === 'review_material_mid_test') {
        $stageType = $_POST['stage_type'] ?? 'training';
        $newStage = ($stageType === 'oje') ? 'oje_reading' : 'training';
        
        // Just move the stage back without deleting attempt history
        mysqli_query($con, "UPDATE hr_oje_employee_progress SET stage='$newStage' WHERE id={$progress['id']}");
        header("Location: hr-employee-OJE.php?$crossSuffix"); exit;
    }
}

// =========================================================================
// DATA FOR THE CURRENT STAGE'S RENDER
// =========================================================================
$trainingQuestions = ($progress && $progress['stage'] === 'training_test') ? getQuestionsWithOptions($con, $dept_id, $pos_id, 'training') : [];
$ojeQuestions       = ($progress && $progress['stage'] === 'oje_test')       ? getQuestionsWithOptions($con, $dept_id, $pos_id, 'oje')      : [];

$certNumber = '';
if ($progress && $progress['stage'] === 'certified' && !empty($progress['certified_at'])) {
    $certNumber = 'CERT-' . date('Y', strtotime($progress['certified_at'])) . '-' . str_pad($employee_id, 5, '0', STR_PAD_LEFT);
}

$stageOrder = ['training' => 1, 'training_test' => 2, 'oje_reading' => 3, 'oje_test' => 4, 'certified' => 5, 'failed' => 0];
$stageOrderNames = [1 => 'training', 2 => 'training_test', 3 => 'oje_reading', 4 => 'oje_test', 5 => 'certified'];

$currentStageIdx = $progress ? ($stageOrder[$progress['stage']] ?? 1) : 0;
$effectiveStageIdx = $currentStageIdx;
if ($progress && $progress['stage'] === 'failed') {
    $effectiveStageIdx = ($failedStageType === 'oje') ? 4 : 2;
}

$requestedTab = $_GET['tab'] ?? null;
$viewStage = ($requestedTab && isset($stageOrder[$requestedTab]) && $requestedTab !== 'failed') ? $requestedTab : ($stageOrderNames[$effectiveStageIdx] ?? 'training');
$viewStageIdx = $stageOrder[$viewStage];

$viewState = 'locked';
if ($viewStageIdx < $effectiveStageIdx) $viewState = 'done';
elseif ($viewStageIdx == $effectiveStageIdx) $viewState = ($progress && $progress['stage'] === 'failed') ? 'failed' : 'current';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>My Training & OJE — <?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="css/app.css" type="text/css"/>
<style>
:root {
  --navy: #0f2557;
  --blue: #1a3fc4;
  --light-blue: #e0e7ff;
  --green: #10b981;
  --amber: #f59e0b;
  --red: #ef4444;
  --gray-bg: #f0f4f8;
  --gold: #d4af37;
}
* { box-sizing: border-box; }
body { font-family: 'Plus Jakarta Sans', sans-serif; background: var(--gray-bg); min-height: 100vh; margin: 0; padding: 0; }

.oje-header {
  background: linear-gradient(135deg, #0f2557 0%, #1a3fc4 100%);
  padding: 22px 32px; display: flex; justify-content: space-between; align-items: center;
  border-radius: 12px; margin-bottom: 20px; box-shadow: 0 4px 20px rgba(15,37,87,0.3); flex-wrap: wrap; gap: 14px;
}
.oje-header h1 { color: #fff; font-weight: 800; margin: 0; font-size: 1.4rem; }
.oje-header p { color: rgba(255,255,255,0.65); font-size: 12px; margin: 4px 0 0; }
.oje-header .emp-meta { display: flex; gap: 18px; flex-wrap: wrap; }
.oje-header .emp-meta div { color: #fff; font-size: 12px; }
.oje-header .emp-meta strong { display: block; font-size: 13px; font-weight: 800; }
.oje-header .emp-meta span { color: rgba(255,255,255,0.6); }
.btn-back-dashboard {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 10px 20px; border-radius: 10px; text-decoration: none;
  background: rgba(255,255,255,.15); color: #fff; font-weight: 700; font-size: 13.5px;
  transition: background .15s; white-space: nowrap;
}
.btn-back-dashboard:hover { background: rgba(255,255,255,.25); color: #fff; text-decoration: none; }

.hr-view-banner {
  background: #fff7ed; border: 1.5px solid #fed7aa; color: #9a3412;
  border-radius: 10px; padding: 10px 16px; font-size: 13px; font-weight: 700;
  margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;
}
.hr-view-banner a { color: #9a3412; text-decoration: underline; font-weight: 700; }

.card-box { background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 2px 10px rgba(0,0,0,0.06); margin-bottom: 20px; }
.card-box h5 { font-weight: 800; color: var(--navy); margin-bottom: 16px; font-size: 15px; }
.empty-hint { text-align: center; padding: 40px; color: #94a3b8; }

/* ── Stepper ── */
.stepper { display: flex; align-items: flex-start; margin-bottom: 24px; background: #fff; border-radius: 12px; padding: 24px 16px; box-shadow: 0 2px 10px rgba(0,0,0,0.06); overflow-x: auto; }
.step { flex: 1; min-width: 130px; text-align: center; position: relative; }
.step .step-circle {
  width: 46px; height: 46px; border-radius: 50%; display: flex; align-items: center; justify-content: center;
  margin: 0 auto 8px; font-size: 17px; font-weight: 800; border: 3px solid #e2e8f0; background: #f8fafc; color: #94a3b8;
  position: relative; z-index: 2;
}
.step .step-line { position: absolute; top: 23px; left: -50%; width: 100%; height: 3px; background: #e2e8f0; z-index: 1; }
.step:first-child .step-line { display: none; }
.step .step-label { font-size: 12px; font-weight: 700; color: #94a3b8; }
.step .step-sub { font-size: 10px; color: #cbd5e1; margin-top: 2px; }

.step.done .step-circle { background: var(--green); border-color: var(--green); color: #fff; }
.step.done .step-line { background: var(--green); }
.step.done .step-label { color: var(--green); }

.step.current .step-circle { background: var(--blue); border-color: var(--blue); color: #fff; box-shadow: 0 0 0 6px rgba(26,63,196,0.15); }
.step.current .step-label { color: var(--blue); }

.step.failed .step-circle { background: var(--red); border-color: var(--red); color: #fff; }
.step.failed .step-line { background: var(--red); }
.step.failed .step-label { color: var(--red); }

/* ── Status banners ── */
.status-banner { border-radius: 10px; padding: 12px 18px; font-size: 13px; font-weight: 600; margin-bottom: 18px; display: flex; align-items: center; gap: 10px; }
.status-banner.info { background: #eff6ff; border: 1.5px solid #bfdbfe; color: #1e40af; }
.status-banner.warn { background: #fef3c7; border: 1.5px solid #fcd34d; color: #92400e; }
.status-banner.ok   { background: #d1fae5; border: 1.5px solid #6ee7b7; color: #065f46; }

/* ── Training materials ── */
.heading-block { border: 1.5px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden; }
.heading-block-head { background: #f8faff; padding: 12px 18px; border-bottom: 1.5px solid #e0e7ff; }
.heading-block-head h6 { margin: 0; font-weight: 800; color: var(--navy); font-size: 13px; }
.heading-block-body { padding: 14px 18px; }
.material-item { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; padding: 12px 14px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px; }
.material-item.is-done { background: #f0fdf4; border-color: #bbf7d0; }
.material-item .item-title { font-weight: 700; color: var(--navy); font-size: 13px; margin-bottom: 3px; }
.material-item .item-desc { font-size: 11px; color: #64748b; margin-bottom: 6px;}
.doc-pill { display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 12px; background: #ede9fe; color: #5b21b6; text-decoration: none; }
.btn-mark-done { background: var(--blue); color: #fff; border: none; padding: 6px 14px; border-radius: 7px; font-size: 12px; font-weight: 700; cursor: pointer; white-space: nowrap; }
.badge-done { background: var(--green); color: #fff; padding: 6px 12px; border-radius: 7px; font-size: 11px; font-weight: 800; white-space: nowrap; }

.progress-wrap { margin-bottom: 18px; }
.progress-wrap .pct-label { display: flex; justify-content: space-between; font-size: 12px; font-weight: 700; color: var(--navy); margin-bottom: 5px; }
.progress-track { height: 10px; border-radius: 5px; background: #e0e7ff; overflow: hidden; }
.progress-fill { height: 100%; background: linear-gradient(90deg, var(--blue), #4a8ae8); border-radius: 5px; transition: width .5s; }

/* ── Test ── */
.q-card { border: 1.5px solid #e0e7ff; border-radius: 10px; padding: 18px; margin-bottom: 14px; user-select: none; -webkit-user-select: none; -moz-user-select: none; -ms-user-select: none; }
.q-card .q-num { font-size: 11px; font-weight: 800; color: var(--blue); text-transform: uppercase; margin-bottom: 6px; }
.q-card .q-text { font-weight: 700; color: var(--navy); font-size: 14px; margin-bottom: 12px; }
.opt-label { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-radius: 8px; margin-bottom: 6px; background: #f8fafc; border: 1.5px solid #e2e8f0; cursor: pointer; font-size: 13px; font-weight: 600; color: #334155; transition: .15s; }
.opt-label:hover { border-color: var(--blue); background: #f0f4ff; }
.opt-label input { width: 16px; height: 16px; margin: 0; }
.opt-label input:checked ~ span { color: var(--blue); }

.attempt-pill { display: inline-flex; align-items: center; gap: 6px; background: #ede9fe; color: #5b21b6; font-size: 12px; font-weight: 800; padding: 5px 12px; border-radius: 14px; }

/* ── History table ── */
.history-table { width: 100%; border-collapse: collapse; margin-top: 10px; }
.history-table th { background: #f0f4f8; color: var(--navy); font-weight: 800; font-size: 11px; text-transform: uppercase; padding: 8px 12px; text-align: left; }
.history-table td { padding: 8px 12px; border-bottom: 1px solid #f1f5f9; font-size: 12px; }
.pf-pass { color: #065f46; font-weight: 800; }
.pf-fail { color: #991b1b; font-weight: 800; }

/* ── Certificate ── */
.cert-wrap { display: flex; justify-content: center; }
.certificate {
  width: 100%; max-width: 820px; background: #fffefb; border: 10px solid var(--navy);
  border-radius: 6px; padding: 50px 60px; text-align: center; position: relative;
  background-image: radial-gradient(circle at top left, rgba(212,175,55,0.06), transparent 60%), radial-gradient(circle at bottom right, rgba(212,175,55,0.06), transparent 60%);
}
.certificate::before { content: ''; position: absolute; inset: 14px; border: 2px solid var(--gold); border-radius: 4px; pointer-events: none; }
.certificate .cert-icon { font-size: 46px; color: var(--gold); margin-bottom: 6px; }
.certificate .cert-co { font-size: 13px; font-weight: 800; letter-spacing: 2px; text-transform: uppercase; color: var(--navy); }
.certificate .cert-title { font-size: 30px; font-weight: 800; color: var(--navy); margin: 14px 0 4px; letter-spacing: 1px; }
.certificate .cert-sub { font-size: 13px; color: #64748b; margin-bottom: 26px; }
.certificate .cert-name { font-size: 28px; font-weight: 800; color: var(--blue); margin: 10px 0; font-family: 'Plus Jakarta Sans', serif; }
.certificate .cert-body { font-size: 14px; color: #334155; max-width: 560px; margin: 0 auto 26px; line-height: 1.7; }
.certificate .cert-footer { display: flex; justify-content: space-between; margin-top: 30px; font-size: 12px; color: #64748b; }
.certificate .cert-footer strong { display: block; color: var(--navy); font-size: 13px; }
.btn-cert-action { background: var(--navy); color: #fff; border: none; padding: 10px 22px; border-radius: 8px; font-weight: 700; font-size: 13px; cursor: pointer; }
.btn-cert-action.outline { background: #fff; color: var(--navy); border: 2px solid var(--navy); }

/* ── Failed ── */
.failed-icon { font-size: 50px; color: var(--red); margin-bottom: 10px; }

.btn-add { background: var(--blue); color: #fff; border: none; padding: 10px 22px; border-radius: 8px; font-weight: 700; font-size: 13px; cursor: pointer; }
.btn-add:hover { background: var(--navy); }
.btn-add:disabled { background: #cbd5e1; cursor: not-allowed; }
.btn-add[disabled] { background: #cbd5e1; cursor: not-allowed; }

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
<div class="container-fluid" style="margin:0 auto;padding:20px 30px;">

<?php if (isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show"><i class="fas fa-check-circle mr-2"></i><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>
<?php if (isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show"><i class="fas fa-exclamation-circle mr-2"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>

<?php if ($isHRView): ?>
<div class="hr-view-banner">
  <span><i class="fas fa-eye mr-1"></i> Viewing as HR — read only</span>
  <a href="hr-OJE.php?dept_id=<?php echo $dept_id; ?>&pos_id=<?php echo $pos_id; ?>&tab=performance"><i class="fas fa-arrow-left mr-1"></i> Back to Performance</a>
</div>
<?php endif; ?>

<!-- HEADER -->
<div class="oje-header">
  <div>
    <h1><i class="fas fa-graduation-cap mr-2"></i> My Training &amp; OJE</h1>
    <p>Track your training progress, tests and certification</p>
    <?php if ($isCrossTraining): ?>
    <div style="margin-top:8px; display:inline-block; background:#10b981; color:#fff; font-size:11px; font-weight:800; padding:4px 10px; border-radius:12px; text-transform:uppercase;"><i class="fas fa-exchange-alt mr-1"></i> Cross-Training Mode</div>
    <?php endif; ?>
  </div>
  <div style="display:flex; align-items:center; gap:18px; flex-wrap:wrap;">
    <?php if ($empRow): ?>
    <div class="emp-meta d-flex align-items-center">
      <div><span>Employee</span><strong><?php echo htmlspecialchars($empRow['name'] ?? ''); ?></strong></div>
      <div><span>Department</span><strong><?php echo htmlspecialchars($deptName); ?></strong></div>
      <div><span>Position</span><strong><?php echo htmlspecialchars($posName); ?></strong></div>
    </div>
    <?php endif; ?>
    
  </div>
</div>

<?php if ($noEmployee): ?>
  <div class="card-box"><div class="empty-hint"><i class="fas fa-user-slash fa-3x mb-3"></i><h5>Employee record not found</h5><p>We couldn't match your account to an employee record. Please contact HR/Admin.</p></div></div>

<?php elseif ($noDeptConfig): ?>
  <div class="card-box"><div class="empty-hint"><i class="fas fa-building fa-3x mb-3"></i><h5>Department/Position not set</h5><p>We couldn't determine your department or position. Please contact HR to update your employee profile.</p></div></div>

<?php elseif ($isBlueCollarPosition): ?>
  <div class="card-box"><div class="empty-hint">
    <i class="fas fa-clipboard-check fa-3x mb-3" style="color:#3730a3;"></i>
    <h5>Training &amp; OJE Not Required</h5>
    <p><?php echo htmlspecialchars($posName); ?> is classified as a Blue Collar role — the Observation Period covers skill and suitability assessment instead of formal Training &amp; OJE testing.</p>
  </div></div>

<?php elseif (!$progress && $isHRView): ?>
  <div class="card-box"><div class="empty-hint"><i class="fas fa-hourglass-half fa-3x mb-3"></i><h5>No training record yet</h5><p>This employee hasn't started the Training &amp; OJE process for this department/position.</p></div></div>

<?php elseif (!$progress): ?>
  <div class="card-box"><div class="empty-hint">
    <i class="fas fa-graduation-cap fa-3x mb-3"></i>
    <h5>Ready to begin your Training &amp; OJE</h5>
    <p>You haven't started this yet for <?php echo htmlspecialchars($deptName); ?> — <?php echo htmlspecialchars($posName); ?>. Click below when you're ready to begin.</p>
    <form method="POST" style="margin-top:10px;">
      <input type="hidden" name="action" value="start_training">
      <button type="submit" class="btn btn-primary" style="font-weight:700; background:var(--blue); border:none; padding:10px 28px;"><i class="fas fa-play mr-2"></i>Start Training</button>
    </form>
  </div></div>

<?php else: ?>

<ul class="nav nav-tabs mb-4" id="employeeTabs" role="tablist" style="border-bottom: 2px solid #e2e8f0; border-radius: 0;">
  <li class="nav-item">
    <a class="nav-link active" id="current-tab" data-toggle="tab" href="#current" role="tab" style="font-weight:700; color:var(--navy); padding:12px 24px; border:none; background:transparent;"><i class="fas fa-book-open mr-1"></i> Current Progress</a>
  </li>
  <li class="nav-item">
    <a class="nav-link" href="hr-employee-recert-crosstraining.php<?php echo $isCrossTraining ? '?dept_id='.$dept_id.'&pos_id='.$pos_id : ''; ?>" style="font-weight:700; color:#64748b; padding:12px 24px; border:none; background:transparent;"><i class="fas fa-sync-alt mr-1"></i> Recertification</a>
  </li>
  <li class="nav-item">
    <a class="nav-link" href="hr-employee-recert-crosstraining.php?tab=crosstraining<?php echo $isCrossTraining ? '&dept_id='.$dept_id.'&pos_id='.$pos_id : ''; ?>" style="font-weight:700; color:#64748b; padding:12px 24px; border:none; background:transparent;"><i class="fas fa-exchange-alt mr-1"></i> Cross Training</a>
  </li>
  <li class="nav-item">
    <a class="nav-link" href="hr-employee-recert-crosstraining.php?tab=history<?php echo $isCrossTraining ? '&dept_id='.$dept_id.'&pos_id='.$pos_id : ''; ?>" style="font-weight:700; color:#64748b; padding:12px 24px; border:none; background:transparent;"><i class="fas fa-history mr-1"></i> History & Certificates</a>
  </li>
</ul>

<div class="tab-content" id="employeeTabsContent">
  <div class="tab-pane fade show active" id="current" role="tabpanel">

<!-- ======================= STEPPER ======================= -->
<div class="stepper">
  <?php
  $steps = [
    1 => ['icon' => 'fa-book-open',         'label' => 'Training',      'sub' => 'Materials'],
    2 => ['icon' => 'fa-question-circle',   'label' => 'Training Test', 'sub' => 'Evaluation'],
    3 => ['icon' => 'fa-briefcase',         'label' => 'OJE Reading',   'sub' => 'Roles & Duties'],
    4 => ['icon' => 'fa-clipboard-check',   'label' => 'OJE Test',      'sub' => 'Final Evaluation'],
    5 => ['icon' => 'fa-award',             'label' => 'Certified',     'sub' => 'Completion'],
  ];
  foreach ($steps as $num => $s):
      if ($num < $effectiveStageIdx) $state = 'done';
      elseif ($num == $effectiveStageIdx) $state = ($progress && $progress['stage'] === 'failed') ? 'failed' : 'pending';
      else $state = 'locked';
      
      $isActiveTab = ($num == $viewStageIdx);
      $icon = $state === 'done' ? 'fa-check' : ($state === 'failed' ? 'fa-times' : ($state === 'locked' ? 'fa-lock' : $s['icon']));
      
      $crossParam = $isCrossTraining ? "&cross_dept_id={$dept_id}&cross_pos_id={$pos_id}" : "";
      $stepClick = ' onclick="window.location.href=\'hr-employee-OJE.php?tab=' . $stageOrderNames[$num] . $crossParam . '\'" style="cursor:pointer;" title="View ' . $s['label'] . '" ';
      $displayState = $isActiveTab ? ($state === 'failed' ? 'failed' : 'current') : $state;
  ?>
  <div class="step <?php echo $displayState; ?>" <?php echo $stepClick; ?>>
    <div class="step-line"></div>
    <div class="step-circle"><i class="fas <?php echo $icon; ?>"></i></div>
    <div class="step-label"><?php echo $s['label']; ?></div>
    <div class="step-sub"><?php echo $s['sub']; ?></div>
  </div>
  <?php endforeach; ?>
</div>

<!-- Link to Recertification & Cross Training -->
<!--
<div style="text-align:right;margin-bottom:16px;">
  <a href="hr-employee-recert-crosstraining.php<?php echo $isCrossTraining ? "?dept_id=$dept_id&pos_id=$pos_id" : ""; ?>" style="display:inline-flex;align-items:center;gap:8px;background:#fff;border:2px solid #e0e7ff;border-radius:10px;padding:9px 18px;font-size:13px;font-weight:700;color:var(--blue);text-decoration:none;box-shadow:0 2px 8px rgba(0,0,0,0.05);">
    <i class="fas fa-sync-alt"></i> My Recertification & Cross Training
  </a>
</div>
-->

<?php
// =====================================================================
// STAGE: TRAINING MATERIALS
// =====================================================================
if ($viewStage === 'training'): ?>
<?php if ($viewState === 'locked'): ?>
<div class="card-box text-center" style="padding:60px 20px;">
  <i class="fas fa-lock" style="font-size:48px;color:#94a3b8;margin-bottom:16px;"></i>
  <h5 style="color:#334155;">Section Locked</h5>
  <p style="color:#64748b;font-size:14px;">You must complete the previous stages before you can access this section.</p>
</div>
<?php else: ?>
<div class="card-box">
  <h5><i class="fas fa-book-open mr-2 text-primary"></i>Training Materials</h5>

  <div class="progress-wrap">
    <div class="pct-label"><span><?php echo $completed_count; ?> of <?php echo $total_items; ?> items completed</span><span><?php echo $total_items > 0 ? round(($completed_count / $total_items) * 100) : 0; ?>%</span></div>
    <div class="progress-track"><div class="progress-fill" style="width:<?php echo $total_items > 0 ? round(($completed_count / $total_items) * 100) : 0; ?>%;"></div></div>
  </div>

  <?php if ($trainingExpired && !$trainingUnlocked): ?>
    <div class="status-banner warn"><i class="fas fa-clock"></i> Your training period has ended. Please complete all items below as soon as possible to proceed to the test.</div>
  <?php elseif ($trainingDaysLeft !== null && !$trainingUnlocked): ?>
    <div class="status-banner info"><i class="fas fa-calendar-day"></i> <?php echo $trainingDaysLeft; ?> day(s) remaining in your training period (deadline: <?php echo date('d M Y', $deadlineTs); ?>).</div>
  <?php endif; ?>

  <?php if (empty($training_headings)): ?>
    <div class="empty-hint"><i class="fas fa-book fa-2x mb-2"></i><p>No training materials have been assigned yet. Please check back later or contact HR.</p></div>
  <?php else: foreach ($training_headings as $h): ?>
    <div class="heading-block">
      <div class="heading-block-head"><h6><i class="fas fa-layer-group mr-2" style="color:var(--blue);"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6></div>
      <div class="heading-block-body">
        <?php if (empty($h['items'])): ?>
          <p class="text-muted small mb-0">No items in this section.</p>
        <?php else: foreach ($h['items'] as $item):
          $isDone = in_array(intval($item['id']), $completedItemIds);
          $trainerMsg = !empty($h['trainer_name']) ? ' Please contact ' . addslashes($h['trainer_name']) . (!empty($h['trainer_designation']) ? ' (' . addslashes($h['trainer_designation']) . ')' : '') . ' for clarification.' : ''; ?>
          <div class="material-item <?php echo $isDone ? 'is-done' : ''; ?>">
            <div>
              <div class="item-title"><?php echo htmlspecialchars($item['item_title']); ?></div>
              <?php if (!empty($item['description'])): ?><div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div><?php endif; ?>
              <?php if (!empty($item['document_path'])): ?>
                <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="doc-pill"><i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?></a>
              <?php endif; ?>
            </div>
            <?php if ($isDone): ?>
              <div class="d-flex align-items-center" style="gap:10px;">
                  <span class="badge-done" style="background:<?php echo ($completedItems[$item['id']] === 'not_understood') ? '#fecaca; color:#ef4444' : '#dcfce7; color:#10b981'; ?>;">
                      <i class="fas <?php echo ($completedItems[$item['id']] === 'not_understood') ? 'fa-times' : 'fa-check'; ?> mr-1"></i> <?php echo ($completedItems[$item['id']] === 'not_understood') ? 'Not Understood' : 'Understood'; ?>
                  </span>
                  <?php if (!$isHRView && $viewState !== 'done'): ?>
                  <form method="POST" style="margin:0;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
                      <input type="hidden" name="action" value="edit_item_done">
                      <input type="hidden" name="item_id" value="<?php echo $item['id']; ?>">
                      <button type="button" class="btn btn-sm btn-light border" style="font-size:12px; font-weight:600; padding:4px 8px; border-radius:6px; color:#64748b;" onclick="return showCustomAction(this, 'edit', 'Are you sure you want to change your understanding status for this material?');"><i class="fas fa-edit"></i> Edit</button>
                  </form>
                  <?php endif; ?>
              </div>
            <?php elseif (!$isHRView && $viewState !== 'done'): ?>
              <form method="POST" style="display:flex; gap:8px;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
                <input type="hidden" name="action" value="mark_item_done">
                <input type="hidden" name="item_id" value="<?php echo $item['id']; ?>">
                <button type="button" class="btn-mark-done" style="background:#10b981;" onclick="return showCustomAction(this, 'understood', 'By marking this as Understood, you confirm you have read and comprehended the material. This will be recorded for your upcoming test.<br><br><b>Proceed?</b>');"><i class="fas fa-check mr-1"></i> Understood</button>
                <button type="button" class="btn-mark-done" style="background:#ef4444;" onclick="return showCustomAction(this, 'not_understood', 'Are you sure you want to mark this material as Not Understood?<br><br>You will still be tested on it.<?php echo addslashes($trainerMsg ?? ''); ?>');"><i class="fas fa-times mr-1"></i> Not Understood</button>
              </form>
            <?php endif; ?>
          </div>
        <?php endforeach; endif; ?>
      </div>
    </div>
  <?php endforeach; endif; ?>

  <?php if (!$isHRView && $viewState !== 'done'): ?>
  <form method="POST" class="mt-3" id="proceedTrainingForm">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
    <input type="hidden" name="action" value="proceed_to_training_test">
    <button type="button" class="btn-add" <?php echo $trainingUnlocked ? 'onclick="$(\'#testRulesModal\').modal(\'show\'); document.getElementById(\'rulesProceedBtn\').onclick = function() { document.getElementById(\'proceedTrainingForm\').submit(); };"' : 'disabled'; ?>>
      <i class="fas fa-arrow-right mr-1"></i> Proceed to Training Test
    </button>
    <?php if (!$trainingUnlocked): ?><span class="ml-2" style="font-size:12px;color:#94a3b8;">Complete all items above to proceed.</span><?php endif; ?>
  </form>
  <?php endif; ?>
</div>
<?php endif; ?>

<?php
// =====================================================================
// STAGE: TRAINING TEST
// =====================================================================
elseif ($viewStage === 'training_test'): ?>
<?php if ($viewState === 'locked'): ?>
<div class="card-box text-center" style="padding:60px 20px;">
  <i class="fas fa-lock" style="font-size:48px;color:#94a3b8;margin-bottom:16px;"></i>
  <h5 style="color:#334155;">Section Locked</h5>
  <p style="color:#64748b;font-size:14px;">You must complete the previous stages before you can access this section.</p>
</div>
<?php else: ?>
<div class="card-box">
  <div class="d-flex justify-content-between align-items-center mb-3 flex-wrap" style="gap:10px;">
    <h5 style="margin:0;"><i class="fas fa-question-circle mr-2 text-warning"></i>Training Test</h5>
    <span class="attempt-pill"><i class="fas fa-redo"></i> Attempt <?php echo $trainingAttemptsUsed + 1; ?> of <?php echo $max_attempts; ?></span>
  </div>
  <div class="status-banner info"><i class="fas fa-info-circle"></i> You need <strong><?php echo number_format($training_pass_percent, 0); ?>%</strong> or higher to pass and unlock OJE.</div>

  <?php if ($viewState === 'done'): ?>
    <div class="status-banner ok" style="padding:40px 20px; text-align:center; background:#f0fdf4; border:1px solid #bbf7d0; box-shadow:0 4px 15px rgba(16,185,129,0.1); border-radius:12px; margin-top:20px; margin-bottom:20px;">
        <i class="fas fa-trophy" style="font-size:48px; color:#10b981; margin-bottom:15px;"></i>
        <h4 style="color:#166534; font-weight:800; margin-bottom:8px;">Congratulations!</h4>
        <p style="color:#15803d; font-size:15px; margin:0;">You have successfully passed the Training Evaluation. OJE is now unlocked.</p>
    </div>
  <?php elseif (empty($trainingQuestions)): ?>
    <div class="empty-hint"><i class="fas fa-question fa-2x mb-2"></i><p>No test questions have been configured yet. Please contact HR.</p></div>
  <?php elseif ($viewState === 'failed'): ?>
    <div class="card-box text-center" style="box-shadow:none; border:1.5px solid #fecaca; background:#fffbfb;">
      <div class="failed-icon" style="font-size:50px; color:var(--red); margin-bottom:10px;"><i class="fas fa-times-circle"></i></div>
      <h5 style="color:var(--red);">Training Test — Maximum Attempts Reached</h5>
      <p style="color:#64748b;font-size:14px;max-width:480px;margin:0 auto 14px;">
        You did not reach the required passing percentage after <?php echo $max_attempts; ?> attempts.
        A support ticket has been raised automatically and HR will follow up with you regarding next steps.
      </p>
      <?php if (!$isHRView): ?>
      <form method="POST" class="mt-4">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
        <input type="hidden" name="action" value="retrain">
        <input type="hidden" name="failed_type" value="training">
        <button type="submit" class="btn-add"><i class="fas fa-redo-alt mr-1"></i> Reset Attempts & Go Back to Training</button>
      </form>
      <?php endif; ?>
    </div>
  <?php elseif (!$isHRView): ?>
    <form method="POST" id="trainingTestForm" oncontextmenu="return false;" onselectstart="return false;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
      <input type="hidden" name="action" value="submit_training_test">
      <?php foreach ($trainingQuestions as $idx => $q): ?>
      <div class="q-card">
        <div class="q-num">Question <?php echo $idx + 1; ?> of <?php echo count($trainingQuestions); ?></div>
        <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
        <?php foreach ($q['options'] as $opt): ?>
          <label class="opt-label">
            <input type="radio" name="answers[<?php echo $q['id']; ?>]" value="<?php echo $opt['id']; ?>" required>
            <span><?php echo htmlspecialchars($opt['label']); ?></span>
          </label>
        <?php endforeach; ?>
      </div>
      <?php endforeach; ?>
      <div style="display:flex; gap:12px; margin-top:20px; align-items:center; flex-wrap:wrap;">
        <button type="submit" class="btn-add"><i class="fas fa-paper-plane mr-1"></i> Submit Test</button>
        <button type="button" onclick="document.getElementById('reviewFormTraining').submit();" class="btn-add" style="background:#64748b; color:#fff;"><i class="fas fa-book-open mr-1"></i> Review Material</button>
      </div>
    </form>
    <form method="POST" id="reviewFormTraining" style="display:none;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
        <input type="hidden" name="action" value="review_material_mid_test">
        <input type="hidden" name="stage_type" value="training">
    </form>
  <?php else: ?>
    <div class="empty-hint"><i class="fas fa-eye fa-2x mb-2"></i><p>Employee is currently taking/about to take this test.</p></div>
  <?php endif; ?>

  <?php if (!empty($trainingAttempts)): ?>
    <h6 class="mt-4" style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;">Attempt History</h6>
    <table class="history-table">
      <thead><tr><th>#</th><th>Date</th><th>Score</th><th>Result</th></tr></thead>
      <tbody>
        <?php foreach ($trainingAttempts as $a): ?>
        <tr data-toggle="collapse" data-target="#attemptDetail_training_<?php echo $a['id']; ?>" class="accordion-toggle" style="cursor:pointer;" title="Click to view answers">
          <td><?php echo $a['attempt_number']; ?> <i class="fas fa-chevron-down text-muted ml-1" style="font-size:10px;"></i></td>
          <td><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
          <td><?php echo number_format($a['percentage'], 1); ?>%</td>
          <td class="<?php echo $a['passed'] ? 'pf-pass' : 'pf-fail'; ?>"><?php echo $a['passed'] ? 'Passed' : 'Failed'; ?></td>
        </tr>
        <tr>
          <td colspan="4" style="padding:0; border:none;">
            <div class="accordian-body collapse" id="attemptDetail_training_<?php echo $a['id']; ?>" style="background:#f8fafc; border-bottom:1px solid #e2e8f0; text-align:left;">
              <div style="padding:15px 20px;">
              <?php
              $answers = json_decode($a['answers_json'], true);
              if (!empty($answers)) {
                 foreach ($answers as $idx => $ans) {
                     $isCorrect = ($ans['points'] == $ans['max']) && ($ans['max'] > 0);
                     $icon = $isCorrect ? '<i class="fas fa-check-circle" style="color:#10b981;"></i>' : '<i class="fas fa-times-circle" style="color:#ef4444;"></i>';
                     echo "<div style='margin-bottom:12px; font-size:13px; border-bottom:1px solid #e2e8f0; padding-bottom:8px;'>";
                     echo "<div style='font-weight:700; color:#0f2557; margin-bottom:4px;'>Q" . ($idx+1) . ": " . htmlspecialchars($ans['question_text']) . "</div>";
                     echo "<div style='color:#475569; display:flex; align-items:center; gap:6px;'>";
                     echo "<span><strong>Your Answer:</strong> " . htmlspecialchars($ans['selected_label'] ?: 'None') . "</span>";
                     echo "<span>" . $icon . " (" . $ans['points'] . "/" . $ans['max'] . " pts)</span>";
                     echo "</div></div>";
                 }
              } else {
                 echo "<div style='font-size:13px;color:#64748b;'>No answer details available.</div>";
              }
              ?>
              </div>
            </div>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  <?php endif; ?>
</div>
<?php endif; ?>

<?php
// =====================================================================
// STAGE: OJE READING
// =====================================================================
elseif ($viewStage === 'oje_reading'): ?>
<?php if ($viewState === 'locked'): ?>
<div class="card-box text-center" style="padding:60px 20px;">
  <i class="fas fa-lock" style="font-size:48px;color:#94a3b8;margin-bottom:16px;"></i>
  <h5 style="color:#334155;">Section Locked</h5>
  <p style="color:#64748b;font-size:14px;">You must complete the previous stages before you can access this section.</p>
</div>
<?php else: ?>
<div class="card-box">
  <h5><i class="fas fa-briefcase mr-2 text-info"></i>OJE — Roles &amp; Responsibilities</h5>

  <?php if ($ojeExpired && !$ojeTestUnlocked): ?>
    <div class="status-banner warn"><i class="fas fa-clock"></i> Your OJE reading period has ended. Please mark all items below as Understood as soon as possible to proceed to the test.</div>
  <?php elseif ($ojeDaysLeft !== null && !$ojeTestUnlocked): ?>
    <div class="status-banner info"><i class="fas fa-calendar-day"></i> <?php echo $ojeDaysLeft; ?> day(s) remaining in your OJE reading period (deadline: <?php echo date('d M Y', $ojeDeadlineTs); ?>).</div>
  <?php endif; ?>

  <?php if (empty($oje_contents)): ?>
    <div class="empty-hint"><i class="fas fa-briefcase fa-2x mb-2"></i><p>No OJE content has been assigned yet. Please check back later or contact HR.</p></div>
  <?php else: foreach ($oje_contents as $h): ?>
    <div class="heading-block">
      <div class="heading-block-head">
        <div>
          <h6><i class="fas fa-briefcase mr-2" style="color:#1e40af;"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6>
          <?php if (!empty($h['trainer_name'])): ?>
          <span style="font-size:11px;font-weight:700;color:#64748b;"><i class="fas fa-chalkboard-teacher mr-1" style="color:#1e40af;"></i><?php echo htmlspecialchars($h['trainer_name']); ?><?php if (!empty($h['trainer_designation'])): ?> &mdash; <?php echo htmlspecialchars($h['trainer_designation']); ?><?php endif; ?></span>
          <?php endif; ?>
        </div>
      </div>
      <div class="heading-block-body">
        <?php if (empty($h['items'])): ?>
          <p class="text-muted small mb-0">No items in this section.</p>
        <?php else: foreach ($h['items'] as $item):
          $isOjeDone = in_array(intval($item['id']), $completedOjeIds);
          $trainerMsg = !empty($h['trainer_name']) ? ' Please contact ' . addslashes($h['trainer_name']) . (!empty($h['trainer_designation']) ? ' (' . addslashes($h['trainer_designation']) . ')' : '') . ' for clarification.' : '';
        ?>
          <div class="material-item <?php echo $isOjeDone ? 'is-done' : ''; ?>">
            <div>
              <div class="item-title"><?php echo htmlspecialchars($item['item_title']); ?></div>
              <?php if (!empty($item['description'])): ?><div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div><?php endif; ?>
              <?php if (!empty($item['document_path'])): ?>
                <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="doc-pill"><i class="fas fa-file-alt"></i> <?php echo htmlspecialchars($item['document_filename']); ?></a>
              <?php endif; ?>
            </div>
            <?php if ($isOjeDone): ?>
              <div class="d-flex align-items-center" style="gap:10px;">
                  <span class="badge-done" style="background:<?php echo ($completedOjeItems[$item['id']] === 'not_understood') ? '#fecaca; color:#ef4444' : '#dcfce7; color:#10b981'; ?>;">
                      <i class="fas <?php echo ($completedOjeItems[$item['id']] === 'not_understood') ? 'fa-times' : 'fa-check'; ?> mr-1"></i> <?php echo ($completedOjeItems[$item['id']] === 'not_understood') ? 'Not Understood' : 'Understood'; ?>
                  </span>
                  <?php if (!$isHRView && $viewState !== 'done'): ?>
                  <form method="POST" style="margin:0;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
                      <input type="hidden" name="action" value="edit_oje_done">
                      <input type="hidden" name="oje_id" value="<?php echo $item['id']; ?>">
                      <button type="button" class="btn btn-sm btn-light border" style="font-size:12px; font-weight:600; padding:4px 8px; border-radius:6px; color:#64748b;" onclick="return showCustomAction(this, 'edit', 'Are you sure you want to change your understanding status for this material?');"><i class="fas fa-edit"></i> Edit</button>
                  </form>
                  <?php endif; ?>
              </div>
            <?php elseif (!$isHRView && $viewState !== 'done'): ?>
              <form method="POST" style="display:flex; gap:8px;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
                <input type="hidden" name="action" value="mark_oje_done">
                <input type="hidden" name="oje_id" value="<?php echo $item['id']; ?>">
                <button type="button" class="btn-mark-done" style="background:#10b981;" onclick="return showCustomAction(this, 'understood', 'By marking this as Understood, you confirm you have read and comprehended the material. This will be recorded for your upcoming test.<br><br><b>Proceed?</b>');"><i class="fas fa-check mr-1"></i> Understood</button>
                <button type="button" class="btn-mark-done" style="background:#ef4444;" onclick="return showCustomAction(this, 'not_understood', 'Are you sure you want to mark this material as Not Understood?<br><br>You will still be tested on it.<?php echo addslashes($trainerMsg); ?>');"><i class="fas fa-times mr-1"></i> Not Understood</button>
              </form>
            <?php endif; ?>
          </div>
        <?php endforeach; endif; ?>
      </div>
    </div>
  <?php endforeach; endif; ?>

  <?php if (!$isHRView && $viewState !== 'done'): ?>
  <form method="POST" class="mt-3" id="proceedOjeForm">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
    <input type="hidden" name="action" value="proceed_to_oje_test">
    <button type="button" class="btn-add" <?php echo $ojeTestUnlocked ? 'onclick="$(\'#testRulesModal\').modal(\'show\'); document.getElementById(\'rulesProceedBtn\').onclick = function() { document.getElementById(\'proceedOjeForm\').submit(); };"' : 'disabled'; ?>>
      <i class="fas fa-arrow-right mr-1"></i> Take OJE Test
    </button>
    <?php if (!$ojeTestUnlocked): ?><span class="ml-2" style="font-size:12px;color:#94a3b8;">Mark all items above as Understood to proceed.</span><?php endif; ?>
  </form>
  <?php endif; ?>
</div>
<?php endif; ?>

<?php
// =====================================================================
// STAGE: OJE TEST
// =====================================================================
elseif ($viewStage === 'oje_test'): ?>
<?php if ($viewState === 'locked'): ?>
<div class="card-box text-center" style="padding:60px 20px;">
  <i class="fas fa-lock" style="font-size:48px;color:#94a3b8;margin-bottom:16px;"></i>
  <h5 style="color:#334155;">Section Locked</h5>
  <p style="color:#64748b;font-size:14px;">You must complete the previous stages before you can access this section.</p>
</div>
<?php else: ?>
<div class="card-box">
  <div class="d-flex justify-content-between align-items-center mb-3 flex-wrap" style="gap:10px;">
    <h5 style="margin:0;"><i class="fas fa-clipboard-check mr-2 text-success"></i>OJE Test</h5>
    <span class="attempt-pill"><i class="fas fa-redo"></i> Attempt <?php echo $ojeAttemptsUsed + 1; ?> of <?php echo $max_attempts; ?></span>
  </div>
  <div class="status-banner info"><i class="fas fa-info-circle"></i> You need <strong><?php echo number_format($oje_pass_percent, 0); ?>%</strong> or higher to pass and receive your certificate.</div>

  <?php if ($viewState === 'done'): ?>
    <div class="status-banner ok" style="padding:40px 20px; text-align:center; background:#f0fdf4; border:1px solid #bbf7d0; box-shadow:0 4px 15px rgba(16,185,129,0.1); border-radius:12px; margin-top:20px; margin-bottom:20px;">
        <i class="fas fa-certificate" style="font-size:48px; color:#10b981; margin-bottom:15px;"></i>
        <h4 style="color:#166534; font-weight:800; margin-bottom:8px;">Congratulations!</h4>
        <p style="color:#15803d; font-size:15px; margin:0;">You have successfully passed the OJE Final Evaluation and earned your certificate!</p>
    </div>
  <?php elseif (empty($ojeQuestions)): ?>
    <div class="empty-hint"><i class="fas fa-clipboard fa-2x mb-2"></i><p>No OJE test questions have been configured yet. Please contact HR.</p></div>
  <?php elseif ($viewState === 'failed'): ?>
    <div class="card-box text-center" style="box-shadow:none; border:1.5px solid #fecaca; background:#fffbfb;">
      <div class="failed-icon" style="font-size:50px; color:var(--red); margin-bottom:10px;"><i class="fas fa-times-circle"></i></div>
      <h5 style="color:var(--red);">OJE Test — Maximum Attempts Reached</h5>
      <p style="color:#64748b;font-size:14px;max-width:480px;margin:0 auto 14px;">
        You did not reach the required passing percentage after <?php echo $max_attempts; ?> attempts.
        A support ticket has been raised automatically and HR will follow up with you regarding next steps.
      </p>
      <?php if (!$isHRView): ?>
      <form method="POST" class="mt-4">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
        <input type="hidden" name="action" value="retrain">
        <input type="hidden" name="failed_type" value="oje">
        <button type="submit" class="btn-add"><i class="fas fa-redo-alt mr-1"></i> Reset Attempts & Go Back to OJE Reading</button>
      </form>
      <?php endif; ?>
    </div>
  <?php elseif (!$isHRView): ?>
    <form method="POST" id="ojeTestForm" oncontextmenu="return false;" onselectstart="return false;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
      <input type="hidden" name="action" value="submit_oje_test">
      <?php foreach ($ojeQuestions as $idx => $q): ?>
      <div class="q-card">
        <div class="q-num">Question <?php echo $idx + 1; ?> of <?php echo count($ojeQuestions); ?></div>
        <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
        <?php foreach ($q['options'] as $opt): ?>
          <label class="opt-label">
            <input type="radio" name="answers[<?php echo $q['id']; ?>]" value="<?php echo $opt['id']; ?>" required>
            <span><?php echo htmlspecialchars($opt['label']); ?></span>
          </label>
        <?php endforeach; ?>
      </div>
      <?php endforeach; ?>
      <div style="display:flex; gap:12px; margin-top:20px; align-items:center; flex-wrap:wrap;">
        <button type="submit" class="btn-add"><i class="fas fa-paper-plane mr-1"></i> Submit Test</button>
        <button type="button" onclick="document.getElementById('reviewFormOJE').submit();" class="btn-add" style="background:#64748b; color:#fff;"><i class="fas fa-book-open mr-1"></i> Review Material</button>
      </div>
    </form>
    <form method="POST" id="reviewFormOJE" style="display:none;">
<?php if ($isCrossTraining): ?>
<input type="hidden" name="cross_dept_id" value="<?php echo $dept_id; ?>">
<input type="hidden" name="cross_pos_id" value="<?php echo $pos_id; ?>">
<?php endif; ?>
        <input type="hidden" name="action" value="review_material_mid_test">
        <input type="hidden" name="stage_type" value="oje">
    </form>
  <?php else: ?>
    <div class="empty-hint"><i class="fas fa-eye fa-2x mb-2"></i><p>Employee is currently taking/about to take this test.</p></div>
  <?php endif; ?>

  <?php if (!empty($ojeAttemptsArr)): ?>
    <h6 class="mt-4" style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;">Attempt History</h6>
    <table class="history-table">
      <thead><tr><th>#</th><th>Date</th><th>Score</th><th>Result</th></tr></thead>
      <tbody>
        <?php foreach ($ojeAttemptsArr as $a): ?>
        <tr data-toggle="collapse" data-target="#attemptDetail_oje_<?php echo $a['id']; ?>" class="accordion-toggle" style="cursor:pointer;" title="Click to view answers">
          <td><?php echo $a['attempt_number']; ?> <i class="fas fa-chevron-down text-muted ml-1" style="font-size:10px;"></i></td>
          <td><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
          <td><?php echo number_format($a['percentage'], 1); ?>%</td>
          <td class="<?php echo $a['passed'] ? 'pf-pass' : 'pf-fail'; ?>"><?php echo $a['passed'] ? 'Passed' : 'Failed'; ?></td>
        </tr>
        <tr>
          <td colspan="4" style="padding:0; border:none;">
            <div class="accordian-body collapse" id="attemptDetail_oje_<?php echo $a['id']; ?>" style="background:#f8fafc; border-bottom:1px solid #e2e8f0; text-align:left;">
              <div style="padding:15px 20px;">
              <?php
              $answers = json_decode($a['answers_json'], true);
              if (!empty($answers)) {
                 foreach ($answers as $idx => $ans) {
                     $isCorrect = ($ans['points'] == $ans['max']) && ($ans['max'] > 0);
                     $icon = $isCorrect ? '<i class="fas fa-check-circle" style="color:#10b981;"></i>' : '<i class="fas fa-times-circle" style="color:#ef4444;"></i>';
                     echo "<div style='margin-bottom:12px; font-size:13px; border-bottom:1px solid #e2e8f0; padding-bottom:8px;'>";
                     echo "<div style='font-weight:700; color:#0f2557; margin-bottom:4px;'>Q" . ($idx+1) . ": " . htmlspecialchars($ans['question_text']) . "</div>";
                     echo "<div style='color:#475569; display:flex; align-items:center; gap:6px;'>";
                     echo "<span><strong>Your Answer:</strong> " . htmlspecialchars($ans['selected_label'] ?: 'None') . "</span>";
                     echo "<span>" . $icon . " (" . $ans['points'] . "/" . $ans['max'] . " pts)</span>";
                     echo "</div></div>";
                 }
              } else {
                 echo "<div style='font-size:13px;color:#64748b;'>No answer details available.</div>";
              }
              ?>
              </div>
            </div>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  <?php endif; ?>
</div>
<?php endif; ?>

<?php
// =====================================================================
// STAGE: CERTIFIED
// =====================================================================
elseif ($viewStage === 'certified'): ?>
<?php if ($viewState === 'locked'): ?>
<div class="card-box text-center" style="padding:60px 20px;">
  <i class="fas fa-lock" style="font-size:48px;color:#94a3b8;margin-bottom:16px;"></i>
  <h5 style="color:#334155;">Section Locked</h5>
  <p style="color:#64748b;font-size:14px;">You must complete the previous stages before you can access this section.</p>
</div>
<?php else: ?>
  <div class="cert-wrap">
    <div class="certificate" id="certificateCard">
      <?php if (!empty($co_settings['company_logo'])): ?>
        <img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" alt="Company Logo" style="max-height:130px; max-width:320px; object-fit:contain; margin-bottom:10px; display:block; margin-left:auto; margin-right:auto;">
      <?php else: ?>
        <div class="cert-icon"><i class="fas fa-award"></i></div>
      <?php endif; ?>
      <div class="cert-co"><?php echo htmlspecialchars(!empty($co_settings['company_name']) ? $co_settings['company_name'] : ($_SESSION['ge_cname'] ?? 'Company')); ?></div>
      <div class="cert-title">Certificate of Completion</div>
      <div class="cert-sub">Training &amp; On-Job Evaluation Program</div>
      <div style="font-size:13px;color:#64748b;">This certifies that</div>
      <div class="cert-name"><?php echo htmlspecialchars($empRow['name'] ?? ''); ?></div>
      <div class="cert-body">
        has successfully completed all stages of the Training &amp; On-Job Evaluation Program
        for the position of <strong><?php echo htmlspecialchars($posName); ?></strong> in the
        <strong><?php echo htmlspecialchars($deptName); ?></strong> department, demonstrating the
        required knowledge and competency in both the Training and On-Job Evaluation assessments.
      </div>
      <div class="cert-footer">
        <div><strong><?php echo date('d M Y', strtotime($progress['certified_at'])); ?></strong>Date Issued</div>
        <div><strong><?php echo htmlspecialchars($certNumber); ?></strong>Certificate No.</div>
        <div>
          <?php if (!empty($co_settings['company_signature'])): ?>
            <img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" alt="Authorized Signature" style="max-height:140px; max-width:320px; display:block; margin: 0 auto 5px;">
          <?php endif; ?>
          <strong>Authorized Signatory</strong>
        </div>
      </div>
    </div>
  </div>
<div class="text-center mt-3" style="display:flex;justify-content:center;gap:12px;">
  <button type="button" class="btn-cert-action" onclick="downloadCertificate()"><i class="fas fa-download mr-1"></i> Download Image</button>
  <button type="button" class="btn-cert-action outline" onclick="window.print()"><i class="fas fa-print mr-1"></i> Print</button>
</div>
<?php endif; ?>

<?php
// History data for the History tab
$oje_history_q = mysqli_query($con, "SELECT p.*, d.name as dept_name, pos.title as pos_title
    FROM hr_oje_employee_progress p
    LEFT JOIN hr_departments d ON d.id=p.department_id
    LEFT JOIN hr_positions pos ON pos.id=p.position_id
    WHERE p.employee_id=$employee_id
    ORDER BY p.certified_at DESC, p.id DESC");
$oje_history = [];
if ($oje_history_q) {
    while ($h = mysqli_fetch_assoc($oje_history_q)) {
        $oje_history[] = $h;
    }
}
?>

<!-- History Tab Pane -->
    </div><!-- End Current Progress Tab -->
    
    <div class="tab-pane fade" id="history" role="tabpanel">
        <div class="card-box">
            <h5 style="margin-bottom:20px;"><i class="fas fa-history mr-2 text-warning"></i>Training &amp; OJE History &amp; Certificates</h5>
            <?php if (empty($oje_history)): ?>
                <div style="text-align:center; padding:40px; color:#94a3b8;">No OJE history found.</div>
            <?php else: ?>
                <div class="table-responsive">
                    <table style="width:100%; border-collapse:collapse; margin-top:10px;">
                        <thead>
                            <tr>
                                <th style="background:#f0f4f8; color:#0f2557; font-weight:800; font-size:11px; text-transform:uppercase; padding:8px 12px; text-align:left;">Department</th>
                                <th style="background:#f0f4f8; color:#0f2557; font-weight:800; font-size:11px; text-transform:uppercase; padding:8px 12px; text-align:left;">Position</th>
                                <th style="background:#f0f4f8; color:#0f2557; font-weight:800; font-size:11px; text-transform:uppercase; padding:8px 12px; text-align:left;">Stage</th>
                                <th style="background:#f0f4f8; color:#0f2557; font-weight:800; font-size:11px; text-transform:uppercase; padding:8px 12px; text-align:left;">Started</th>
                                <th style="background:#f0f4f8; color:#0f2557; font-weight:800; font-size:11px; text-transform:uppercase; padding:8px 12px; text-align:left;">Certified At</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($oje_history as $h): ?>
                            <tr>
                                <td style="padding:8px 12px; border-bottom:1px solid #f1f5f9; font-size:12px; font-weight:600;"><?php echo htmlspecialchars($h['dept_name']); ?></td>
                                <td style="padding:8px 12px; border-bottom:1px solid #f1f5f9; font-size:12px; font-weight:600;"><?php echo htmlspecialchars($h['pos_title'] ?? 'All Positions'); ?></td>
                                <td style="padding:8px 12px; border-bottom:1px solid #f1f5f9; font-size:12px; font-weight:700;">
                                    <?php if ($h['stage'] == 'certified'): ?>
                                        <span style="color:#065f46; background:#d1fae5; padding:2px 8px; border-radius:12px;">Certified</span>
                                        <div style="margin-top:6px;"><a href="javascript:void(0)" onclick="$('#cert-oje-<?php echo $h['id']; ?>').slideToggle()" style="font-size:11px; text-decoration:underline; font-weight:700; color:var(--blue);">View Certificate</a></div>
                                    <?php else: ?>
                                        <span style="color:#1e40af; background:#dbeafe; padding:2px 8px; border-radius:12px;"><?php echo ucfirst(str_replace('_',' ',$h['stage'])); ?></span>
                                    <?php endif; ?>
                                </td>
                                <td style="padding:8px 12px; border-bottom:1px solid #f1f5f9; font-size:12px;"><?php echo $h['training_started_at'] ? date('d M Y', strtotime($h['training_started_at'])) : '-'; ?></td>
                                <td style="padding:8px 12px; border-bottom:1px solid #f1f5f9; font-size:12px;"><?php echo $h['certified_at'] ? date('d M Y, h:i A', strtotime($h['certified_at'])) : '-'; ?></td>
                            </tr>
                            <?php if ($h['stage'] == 'certified'): ?>
                            <tr id="cert-oje-<?php echo $h['id']; ?>" style="display:none; background:#f8fafc;">
                                <td colspan="5" style="padding:30px;">
                                    <div class="cert-wrap" style="margin:0;">
                                        <div class="certificate" id="cert-card-oje-<?php echo $h['id']; ?>">
                                            <?php if (!empty($co_settings['company_logo'])): ?>
                                              <img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" alt="Company Logo" style="max-height:130px; max-width:320px; object-fit:contain; margin-bottom:10px; display:block; margin-left:auto; margin-right:auto;">
                                            <?php else: ?>
                                              <div class="cert-icon"><i class="fas fa-award"></i></div>
                                            <?php endif; ?>
                                            
                                            <div style="font-size:16px;font-weight:700;color:var(--navy);margin-bottom:15px;text-transform:uppercase;letter-spacing:1px;text-align:center;">
                                              <?php echo htmlspecialchars(!empty($co_settings['company_name']) ? $co_settings['company_name'] : ($_SESSION['ge_cname'] ?? 'Company')); ?>
                                            </div>
                                            
                                            <div class="cert-title">Certificate of Completion</div>
                                            <div class="cert-sub" style="font-size:14px;color:var(--blue);font-weight:700;text-transform:uppercase;letter-spacing:.5px;margin-bottom:12px;text-align:center;">Training &amp; On-Job Evaluation Program</div>
                                            <div style="font-size:13px;color:#64748b;text-align:center;">This certifies that</div>
                                            <div class="cert-name"><?php echo htmlspecialchars($empRow['name']); ?></div>
                                            <div class="cert-body" style="margin-bottom:15px;">
                                                has successfully completed all stages of the Training &amp; On-Job Evaluation Program for the position of <strong><?php echo htmlspecialchars($h['pos_title'] ?? 'All Positions'); ?></strong> in the <strong><?php echo htmlspecialchars($h['dept_name']); ?></strong> department, demonstrating the required knowledge and competency in both the Training and On-Job Evaluation assessments.
                                            </div>
                                            <div class="cert-footer">
                                              <div><strong><?php echo date('d M Y', strtotime($h['certified_at'])); ?></strong>Date Issued</div>
                                              <div><strong>CERT-<?php echo date('Y', strtotime($h['certified_at'])) . '-' . str_pad($employee_id, 5, '0', STR_PAD_LEFT); ?></strong>Certificate No.</div>
                                              <div>
                                                <?php if (!empty($co_settings['company_signature'])): ?>
                                                  <img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" alt="Authorized Signature" style="max-height:140px; max-width:320px; display:block; margin: 0 auto 5px;">
                                                <?php endif; ?>
                                                <strong>Authorized Signatory</strong>
                                              </div>
                                            </div>
                                        </div>
                                    </div>
                                    <div class="text-center mt-3" style="display:flex;justify-content:center;gap:12px;">
                                      <button type="button" class="btn-cert-action" onclick="downloadCertificate('cert-card-oje-<?php echo $h['id']; ?>')"><i class="fas fa-download mr-1"></i> Download</button>
                                      <button type="button" class="btn-cert-action outline" onclick="window.print()"><i class="fas fa-print mr-1"></i> Print</button>
                                    </div>
                                </td>
                            </tr>
                            <?php endif; ?>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </div>
    </div><!-- End History Tab -->
  </div><!-- End Tab Content -->

<?php endif; ?> <!-- End if ($noEmployee)/else -->

</div><!-- End container-fluid -->

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


<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="js/ui-load.js"></script><script src="js/ui-jp.config.js"></script>
<script src="js/ui-jp.js"></script><script src="js/ui-nav.js"></script><script src="js/ui-toggle.js"></script>
<script>
function downloadCertificate(certId) {
  var id = certId || 'certificateCard';
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
      link.download = 'Certificate_<?php echo preg_replace("/[^A-Za-z0-9_-]/", "_", $empRow["name"] ?? "Employee"); ?>.png';
      link.href = canvas.toDataURL('image/png');
      link.click();
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download mr-1"></i> Download Image'; }
  }).catch(function(err) {
      console.error('Image generation failed:', err);
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download mr-1"></i> Download Image'; }
  });
}
</script>
<?php if ($progress && in_array($viewStage, ['training_test', 'oje_test']) && !$isHRView && $viewState !== 'done'): ?>
<div id="antiCheatOverlay" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(15, 37, 87, 0.95); z-index:999999; flex-direction:column; justify-content:center; align-items:center; text-align:center; backdrop-filter:blur(10px);">
    <i class="fas fa-exclamation-triangle" style="font-size:72px; color:#ef4444; margin-bottom:24px;"></i>
    <h2 style="color:#fff; font-weight:800; font-size:32px; margin-bottom:12px;">Activity Flagged!</h2>
    <p id="antiCheatMsg" style="color:#e2e8f0; font-size:18px; font-weight:500; max-width:600px; margin-bottom:30px; line-height:1.6;">Tab switching or leaving the browser window is prohibited during the test.</p>
    <button type="button" onclick="document.getElementById('antiCheatOverlay').style.display='none'" class="btn-add" style="background:#ef4444; padding:14px 32px; font-size:16px; border-radius:12px; box-shadow:0 10px 25px rgba(239,68,68,0.3);">
        <i class="fas fa-check-circle mr-2"></i> I Understand
    </button>
</div>
<script>
// Anti-Cheat Logic
function showAntiCheatOverlay(msg) {
    var overlay = document.getElementById('antiCheatOverlay');
    if (overlay) {
        document.getElementById('antiCheatMsg').innerText = msg;
        overlay.style.display = 'flex';
    }
}

document.addEventListener('contextmenu', event => {
    event.preventDefault();
});

document.addEventListener('copy', event => { 
    event.preventDefault(); 
    showAntiCheatOverlay("Copying text is strictly prohibited during the evaluation."); 
});
document.addEventListener('cut', event => { 
    event.preventDefault(); 
    showAntiCheatOverlay("Cutting text is strictly prohibited during the evaluation."); 
});
document.addEventListener('paste', event => { 
    event.preventDefault(); 
    showAntiCheatOverlay("Pasting text from external sources is strictly prohibited."); 
});

document.addEventListener("visibilitychange", function() {
    if (document.hidden) {
        showAntiCheatOverlay("Tab switching or leaving the browser window is prohibited during the test. Your activity has been flagged.");
    }
});
</script>
<?php endif; ?>

<!-- Custom Action Modal Overlay -->
<div id="customActionOverlay" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(15, 37, 87, 0.6); z-index:999999; flex-direction:column; justify-content:center; align-items:center; backdrop-filter:blur(4px);">
    <div style="background:#fff; border-radius:16px; box-shadow:0 20px 60px rgba(0,0,0,0.15); width:100%; max-width:400px; padding:30px 24px 24px; text-align:center; position:relative;">
        <div id="customActionIcon" style="font-size:64px; margin-bottom:16px;"></div>
        <h4 id="customActionTitle" style="font-weight:800; margin-bottom:12px; font-size:22px;"></h4>
        <p id="customActionMsg" style="color:#64748b; font-size:15px; line-height:1.6; margin-bottom:30px; padding:0 10px;"></p>
        <div style="display:flex; gap:12px; justify-content:center;">
            <button type="button" onclick="document.getElementById('customActionOverlay').style.display='none'" class="btn btn-light" style="font-weight:600; padding:10px 24px; border-radius:10px; color:#64748b; border:1px solid #e2e8f0; flex:1;">Cancel</button>
            <button type="button" id="customActionProceedBtn" class="btn" style="font-weight:700; padding:10px 24px; border-radius:10px; border:none; color:#fff; flex:1;">Proceed</button>
        </div>
    </div>
</div>
<script>
function showCustomAction(btn, type, msg) {
    var overlay = document.getElementById('customActionOverlay');
    var icon = document.getElementById('customActionIcon');
    var title = document.getElementById('customActionTitle');
    var msgEl = document.getElementById('customActionMsg');
    var proceedBtn = document.getElementById('customActionProceedBtn');
    
    if (type === 'understood') {
        icon.innerHTML = '<i class="fas fa-check-circle" style="color:#10b981;"></i>';
        title.innerText = 'Mark as Understood';
        title.style.color = '#065f46';
        msgEl.innerHTML = msg;
        proceedBtn.style.background = '#10b981';
        proceedBtn.innerText = 'Yes, Understood';
    } else if (type === 'not_understood') {
        icon.innerHTML = '<i class="fas fa-times-circle" style="color:#ef4444;"></i>';
        title.innerText = 'Not Understood?';
        title.style.color = '#991b1b';
        msgEl.innerHTML = msg;
        proceedBtn.style.background = '#ef4444';
        proceedBtn.innerText = 'Yes, Not Understood';
    } else if (type === 'edit') {
        icon.innerHTML = '<i class="fas fa-edit" style="color:#3b82f6;"></i>';
        title.innerText = 'Edit Status';
        title.style.color = '#1e40af';
        msgEl.innerHTML = msg;
        proceedBtn.style.background = '#3b82f6';
        proceedBtn.innerText = 'Yes, Edit';
    }
    
    proceedBtn.onclick = function() {
        var form = btn.closest('form');
        if (type === 'understood' || type === 'not_understood') {
            var statusInput = document.createElement('input');
            statusInput.type = 'hidden';
            statusInput.name = 'status';
            statusInput.value = type;
            form.appendChild(statusInput);
        }
        form.submit();
    };
    
    overlay.style.display = 'flex';
    return false;
}
</script>

  </div><!-- End Tab Content -->
  <?php endif; ?>
</div>

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