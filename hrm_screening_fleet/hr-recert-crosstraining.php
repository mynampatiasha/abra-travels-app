<?php
session_start();
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
// isUser();

$current_page    = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// AJAX: GET POSITIONS
// =========================================================================
if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $rows = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

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

// Check and upgrade schema for date interval
$check = mysqli_query($con, "SHOW COLUMNS FROM hr_oje_recert_config LIKE 'interval_date'");
if (!$check || mysqli_num_rows($check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD COLUMN interval_date DATE DEFAULT NULL");
}
$check2 = mysqli_query($con, "SHOW COLUMNS FROM hr_oje_recert_config LIKE 'interval_type'");
if ($check2 && $row2 = mysqli_fetch_assoc($check2)) {
    if (strpos($row2['Type'], 'date') === false) {
        mysqli_query($con, "ALTER TABLE hr_oje_recert_config MODIFY interval_type ENUM('days','months','years','date') DEFAULT 'months'");
    }
}

try {
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD COLUMN interval_type ENUM('days','months','years') DEFAULT 'months'");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD COLUMN cycle_number INT NOT NULL DEFAULT 1");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config DROP INDEX uniq_dept_pos");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_config ADD UNIQUE KEY uniq_dept_pos_cycle (department_id, position_id, cycle_number)");
    mysqli_query($con, "ALTER TABLE hr_oje_recert_questions ADD COLUMN cycle_number INT NOT NULL DEFAULT 1");
} catch (Exception $e) {
    // Silently ignore if already applied
}

// =========================================================================
// PAGE FILTERS
// =========================================================================
$sel_dept   = isset($_GET['dept_id']) ? intval($_GET['dept_id']) : 0;
$sel_pos    = isset($_GET['pos_id'])  ? intval($_GET['pos_id'])  : 0;
$active_tab = $_GET['tab'] ?? 'recertification';

$departments = [];
$dq = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
while ($d = mysqli_fetch_assoc($dq)) $departments[] = $d;

$positions = [];
if ($sel_dept > 0) {
    $pq = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$sel_dept ORDER BY title ASC");
    if ($pq) while ($p = mysqli_fetch_assoc($pq)) $positions[] = $p;
}

function getDeptName($depts, $id) { foreach($depts as $d) if($d['id']==$id) return $d['name']; return ''; }
function getPosTitle($positions, $id) { foreach($positions as $p) if($p['id']==$id) return $p['title']; return 'All Positions'; }

$sel_dept_name = getDeptName($departments, $sel_dept);
$sel_pos_title = getPosTitle($positions, $sel_pos);

// =========================================================================
// CSV IMPORT/EXPORT HANDLERS (GET)
// =========================================================================
if (isset($_GET['action'])) {
    if ($_GET['action'] == 'download_template') {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=Recertification_Questions_Template.csv');
        $output = fopen('php://output', 'w');
        fputcsv($output, ['question_text','option1','points1','correct1','option2','points2','correct2','option3','points3','correct3','option4','points4','correct4','option5','points5','correct5','option6','points6','correct6']);
        fputcsv($output, ['Sample Question: Is this true?','Yes','10','Y','Partially','5','N','No','0','N','','','','','','','','','']);
        fclose($output);
        exit;
    }
    if ($_GET['action'] == 'export_questions') {
        $dept_id = intval($_GET['dept_id'] ?? 0);
        $pos_id = intval($_GET['pos_id'] ?? 0);
        
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=Recertification_Questions_Export.csv');
        $output = fopen('php://output', 'w');
        fputcsv($output, ['question_text','option1','points1','correct1','option2','points2','correct2','option3','points3','correct3','option4','points4','correct4','option5','points5','correct5','option6','points6','correct6']);
        
        $qres = mysqli_query($con, "SELECT * FROM hr_oje_recert_questions WHERE department_id=$dept_id AND position_id=$pos_id ORDER BY sort_order ASC, id ASC");
        while ($q = mysqli_fetch_assoc($qres)) {
            $row = [$q['question_text']];
            $ores = mysqli_query($con, "SELECT * FROM hr_oje_recert_question_options WHERE question_id={$q['id']} ORDER BY sort_order ASC, id ASC");
            $opts = [];
            while ($o = mysqli_fetch_assoc($ores)) $opts[] = $o;
            
            for ($i=0; $i<6; $i++) {
                if (isset($opts[$i])) {
                    $row[] = $opts[$i]['option_label'];
                    $row[] = $opts[$i]['points'];
                    $row[] = $opts[$i]['is_correct'] ? 'Y' : 'N';
                } else {
                    $row[] = ''; $row[] = ''; $row[] = '';
                }
            }
            fputcsv($output, $row);
        }
        fclose($output);
        exit;
    }
}

// =========================================================================


// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];
    // ---- CREATE NEXT CYCLE ----
    if ($action == 'create_next_cycle') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $cycle    = intval($_POST['cycle_number']);
        
        // Copy config from previous cycle if exists, else insert default
        $prev = $cycle - 1;
        $q = mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id=$dept_id AND position_id=$pos_id AND cycle_number=$prev LIMIT 1");
        if ($q && mysqli_num_rows($q) > 0) {
            $r = mysqli_fetch_assoc($q);
            mysqli_query($con, "INSERT INTO hr_oje_recert_config (department_id, position_id, cycle_number, interval_months, interval_type, pass_percent, max_attempts) VALUES ($dept_id, $pos_id, $cycle, '{$r['interval_months']}', '{$r['interval_type']}', '{$r['pass_percent']}', '{$r['max_attempts']}')");
        } else {
            mysqli_query($con, "INSERT INTO hr_oje_recert_config (department_id, position_id, cycle_number) VALUES ($dept_id, $pos_id, $cycle)");
        }
        
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=recertification&cycle=$cycle"); exit;
    }

    // ---- SAVE RECERT CONFIG ----
    if ($action == 'save_recert_config') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $cycle    = intval($_POST['cycle_number'] ?? 1);
        $interval = intval($_POST['interval_months']);
        $int_type = mysqli_real_escape_string($con, $_POST['interval_type'] ?? 'months');
        $int_date = !empty($_POST['interval_date']) ? "'" . mysqli_real_escape_string($con, $_POST['interval_date']) . "'" : "NULL";
        $pass_pct = floatval($_POST['pass_percent']);
        $max_att  = intval($_POST['max_attempts']);
        $cb       = mysqli_real_escape_string($con, $currentUserName);
        $inserted = mysqli_query($con, "INSERT INTO hr_oje_recert_config (department_id,position_id,cycle_number,interval_months,interval_type,interval_date,pass_percent,max_attempts,created_by)
            VALUES ($dept_id,$pos_id,$cycle,$interval,'$int_type',$int_date,$pass_pct,$max_att,'$cb')
            ON DUPLICATE KEY UPDATE interval_months=$interval,interval_type='$int_type',interval_date=$int_date,pass_percent=$pass_pct,max_attempts=$max_att");
        
        if ($inserted) {
            $_SESSION['success_message'] = "Recertification configuration saved for Cycle $cycle.";
        } else {
            $_SESSION['error_message'] = "Failed save configuration: " . mysqli_error($con);
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=recertification&cycle=$cycle"); exit;
    }

    // ---- IMPORT RECERT QUESTIONS ----
    if ($action == 'import_questions') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $cycle    = intval($_POST['cycle_number'] ?? 1);
        $cb       = mysqli_real_escape_string($con, $currentUserName);
        
        if (isset($_FILES['csv_file']) && $_FILES['csv_file']['error'] === UPLOAD_ERR_OK) {
            $file = $_FILES['csv_file']['tmp_name'];
            if (($handle = fopen($file, "r")) !== FALSE) {
                // skip header
                $header = fgetcsv($handle, 1000, ",");
                $imported = 0;
                while (($data = fgetcsv($handle, 1000, ",")) !== FALSE) {
                    $qtext = mysqli_real_escape_string($con, trim($data[0] ?? ''));
                    if (!$qtext) continue;
                    
                    $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_recert_questions WHERE department_id=$dept_id AND position_id=$pos_id AND cycle_number=$cycle"));
                    $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
                    mysqli_query($con, "INSERT INTO hr_oje_recert_questions (department_id,position_id,cycle_number,question_text,sort_order,created_by) VALUES ($dept_id,$pos_id,$cycle,'$qtext',$ns,'$cb')");
                    $qid = mysqli_insert_id($con);
                    
                    $col = 1;
                    $optIndex = 0;
                    while ($col < count($data) && $col < 19) {
                        $ol = mysqli_real_escape_string($con, trim($data[$col]));
                        $pts = intval($data[$col+1] ?? 0);
                        $is_corr_str = strtoupper(trim($data[$col+2] ?? 'N'));
                        $isc = ($is_corr_str == 'Y' || $is_corr_str == '1') ? 1 : 0;
                        if ($ol) {
                            mysqli_query($con, "INSERT INTO hr_oje_recert_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$optIndex)");
                            $optIndex++;
                        }
                        $col += 3;
                    }
                    $imported++;
                }
                fclose($handle);
                $_SESSION['success_message'] = "$imported questions imported successfully.";
            } else {
                $_SESSION['error_message'] = "Could not open CSV file.";
            }
        } else {
            $_SESSION['error_message'] = "Please upload a valid CSV file.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=recertification&cycle=$cycle"); exit;
    }

    // ---- ADD RECERT QUESTION ----
    if ($action == 'add_recert_question') {
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $cycle   = intval($_POST['cycle_number'] ?? 1);
        $qtext   = mysqli_real_escape_string($con, trim($_POST['question_text']));
        $options = $_POST['options'] ?? [];
        $points  = $_POST['points'] ?? [];
        $correct = intval($_POST['correct_option'] ?? 0);
        $cb      = mysqli_real_escape_string($con, $currentUserName);
        if ($qtext && !empty($options)) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_recert_questions WHERE department_id=$dept_id AND position_id=$pos_id AND cycle_number=$cycle"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            mysqli_query($con, "INSERT INTO hr_oje_recert_questions (department_id,position_id,cycle_number,question_text,sort_order,created_by) VALUES ($dept_id,$pos_id,$cycle,'$qtext',$ns,'$cb')");
            $qid = mysqli_insert_id($con);
            foreach ($options as $i => $opt) {
                $ol  = mysqli_real_escape_string($con, trim($opt));
                $pts = intval($points[$i] ?? 0);
                $isc = ($i == $correct) ? 1 : 0;
                if ($ol) mysqli_query($con, "INSERT INTO hr_oje_recert_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$i)");
            }
            $_SESSION['success_message'] = "Recertification question added.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=recertification&cycle=$cycle"); exit;
    }

    // ---- EDIT RECERT QUESTION ----
    if ($action == 'edit_recert_question') {
        $qid     = intval($_POST['question_id']);
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $cycle   = intval($_POST['cycle_number'] ?? 1);
        $qtext   = mysqli_real_escape_string($con, trim($_POST['question_text']));
        $options = $_POST['options'] ?? [];
        $points  = $_POST['points'] ?? [];
        $correct = intval($_POST['correct_option'] ?? 0);
        if ($qid > 0 && $qtext && !empty($options)) {
            mysqli_query($con, "UPDATE hr_oje_recert_questions SET question_text='$qtext' WHERE id=$qid");
            mysqli_query($con, "DELETE FROM hr_oje_recert_question_options WHERE question_id=$qid");
            foreach ($options as $i => $opt) {
                $ol  = mysqli_real_escape_string($con, trim($opt));
                $pts = intval($points[$i] ?? 0);
                $isc = ($i == $correct) ? 1 : 0;
                if ($ol) mysqli_query($con, "INSERT INTO hr_oje_recert_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$i)");
            }
            $_SESSION['success_message'] = "Question updated.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=recertification&cycle=$cycle"); exit;
    }

    // ---- DELETE RECERT QUESTION ----
    if ($action == 'delete_recert_question') {
        $id = intval($_POST['id']);
        mysqli_query($con, "DELETE FROM hr_oje_recert_question_options WHERE question_id=$id");
        mysqli_query($con, "DELETE FROM hr_oje_recert_questions WHERE id=$id");
        $_SESSION['success_message'] = "Question deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- INITIATE CROSS TRAINING ----
    if ($action == 'initiate_cross_training') {
        $emp_id     = intval($_POST['employee_id']);
        $to_dept_id = intval($_POST['to_dept_id']);
        $to_pos_id  = intval($_POST['to_pos_id']);
        $start_date = mysqli_real_escape_string($con, trim($_POST['start_date']));
        $notes      = mysqli_real_escape_string($con, trim($_POST['notes'] ?? ''));
        $cb         = mysqli_real_escape_string($con, $currentUserName);

        // Sync employee's department/position to their latest completed cross training BEFORE
        // resolving "from" — prevents stale "from" values when multiple transfers happen in quick succession.
        $presync = mysqli_fetch_assoc(mysqli_query($con, "
            SELECT ct.to_dept_id, ct.to_pos_id, td.name as to_dept_name, tp.title as to_pos_name
            FROM hr_oje_cross_training ct
            LEFT JOIN hr_departments td ON td.id = ct.to_dept_id
            LEFT JOIN hr_positions   tp ON tp.id = ct.to_pos_id
            WHERE ct.employee_id = $emp_id AND ct.status = 'completed'
            ORDER BY ct.created_at DESC LIMIT 1
        "));
        if ($presync && !empty($presync['to_dept_name'])) {
            $ps_dept = mysqli_real_escape_string($con, $presync['to_dept_name']);
            $ps_pos  = mysqli_real_escape_string($con, $presync['to_pos_name'] ?? '');
            $ps_posid = intval($presync['to_pos_id']);
            mysqli_query($con, "UPDATE hr_employees SET department='$ps_dept', position='$ps_pos', position_id=$ps_posid WHERE id=$emp_id");
        }

        $empRow  = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$emp_id LIMIT 1"));
        $toDept  = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$to_dept_id LIMIT 1"));
        $toPos   = $to_pos_id > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$to_pos_id LIMIT 1")) : null;

        // Resolve from dept/pos
        $deptVal = $empRow['department_id'] ?? ($empRow['department'] ?? null);
        $posVal  = $empRow['position_id']   ?? ($empRow['position']   ?? null);
        $from_dept_id = 0; $from_pos_id = 0;
        if (is_numeric($deptVal)) $from_dept_id = intval($deptVal);
        else { $dn = mysqli_real_escape_string($con, trim($deptVal ?? '')); $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1")); if($r) $from_dept_id = intval($r['id']); }
        if (is_numeric($posVal)) $from_pos_id = intval($posVal);
        else { $pn = mysqli_real_escape_string($con, trim($posVal ?? '')); $r = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_positions WHERE title='$pn' LIMIT 1")); if($r) $from_pos_id = intval($r['id']); }

        $fromDept = $from_dept_id > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$from_dept_id LIMIT 1")) : null;
        $fromPos  = $from_pos_id  > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$from_pos_id LIMIT 1"))  : null;

        $from_dept_name = $fromDept['name']  ?? 'N/A';
        $from_pos_name  = $fromPos['title']  ?? 'N/A';
        $to_dept_name   = $toDept['name']    ?? 'N/A';
        $to_pos_name    = $toPos['title']    ?? 'All Positions';
        $emp_name       = $empRow['name']    ?? '';

        // Check duplicate active
        $dup = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_oje_cross_training WHERE employee_id=$emp_id AND to_dept_id=$to_dept_id AND to_pos_id=$to_pos_id AND status='active' LIMIT 1"));
        if ($dup) {
            $_SESSION['error_message'] = "This employee already has an active cross training for that role.";
            header("Location: $current_page?tab=cross_training"); exit;
        }

        $inserted = mysqli_query($con, "INSERT INTO hr_oje_cross_training (employee_id,from_dept_id,from_pos_id,to_dept_id,to_pos_id,start_date,status,initiated_by,notes)
            VALUES ($emp_id,$from_dept_id,$from_pos_id,$to_dept_id,$to_pos_id,'$start_date','active','$cb','$notes')");

        if ($inserted) {
            // Create progress row for new role
            mysqli_query($con, "INSERT IGNORE INTO hr_oje_employee_progress (employee_id,department_id,position_id,stage,training_started_at)
                VALUES ($emp_id,$to_dept_id,$to_pos_id,'training',NOW())");

            // Raise ticket
            $maxRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
            $nextId = intval($maxRow['max_id'] ?? 0) + 1;
            $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
            $timeline   = 2880;
            $deadline   = date('Y-m-d H:i:s', strtotime("+{$timeline} minutes"));
            $link       = "hr-employee-OJE.php?cross_dept_id={$to_dept_id}&cross_pos_id={$to_pos_id}";
            $subject    = "You Have Been Assigned for Cross Training";
            $message    = "Dear {$emp_name},\n\nYou have been assigned for Cross Training.\n\nFrom: {$from_dept_name} â†’ {$from_pos_name}\nTo: {$to_dept_name} â†’ {$to_pos_name}\nInitiated By: {$currentUserName}\nStart Date: {$start_date}\n\nPlease begin your cross training here: {$link}";
            $priority   = 'high'; $status = 'open'; $attachment = '';
            $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number,name,subject,message,status,priority,timeline,deadline,attachment,created_at,updated_at,assigned_to,created_by) VALUES (?,?,?,?,?,?,?,?,?,NOW(),NOW(),?,?)");
            if ($stmt) {
                mysqli_stmt_bind_param($stmt, "ssssssissii", $ticket_number, $emp_name, $subject, $message, $status, $priority, $timeline, $deadline, $attachment, $emp_id, $emp_id);
                mysqli_stmt_execute($stmt);
                mysqli_stmt_close($stmt);
            }
            $_SESSION['success_message'] = "Cross training initiated for $emp_name. Employee notified via ticket.";
        } else {
            $_SESSION['error_message'] = "Failed initiate cross training. " . mysqli_error($con);
        }
        header("Location: $current_page?tab=cross_training"); exit;
    }

    // ---- CANCEL CROSS TRAINING ----
    if ($action == 'cancel_cross_training') {
        $id = intval($_POST['id']);
        mysqli_query($con, "UPDATE hr_oje_cross_training SET status='cancelled', updated_at=NOW() WHERE id=$id");
        $_SESSION['success_message'] = "Cross training cancelled.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- SEND RECERT TICKET ----
    if ($action == 'send_recert_ticket') {
        $emp_id  = intval($_POST['employee_id']);
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $cycle   = intval($_POST['cycle_number']);
        $cb      = mysqli_real_escape_string($con, $currentUserName);

        $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_employees WHERE id=$emp_id LIMIT 1"));
        $dRow   = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id LIMIT 1"));
        $pRow   = $pos_id > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id LIMIT 1")) : null;

        $emp_name = $empRow['name'] ?? 'Employee';
        $d_name   = $dRow['name'] ?? 'Department';
        $p_name   = $pRow['title'] ?? 'All Positions';

        $maxRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
        $nextId = intval($maxRow['max_id'] ?? 0) + 1;
        $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
        
        $timeline   = 2880; // 48 hours
        $deadline   = date('Y-m-d H:i:s', strtotime("+{$timeline} minutes"));
        $link       = "hr-employee-recert-crosstraining.php?view_emp={$emp_id}&dept_id={$dept_id}&pos_id={$pos_id}";
        $subject    = "Action Required: Recertification Due (Cycle $cycle)";
        $message    = "Dear {$emp_name},\n\nYour recertification for Cycle {$cycle} ({$d_name} - {$p_name}) is now due.\n\nPlease complete your recertification here: {$link}";
        $priority   = 'high'; $status = 'open'; $attachment = '';
        
        $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number,name,subject,message,status,priority,timeline,deadline,attachment,created_at,updated_at,assigned_to,created_by) VALUES (?,?,?,?,?,?,?,?,?,NOW(),NOW(),?,?)");
        if ($stmt) {
            mysqli_stmt_bind_param($stmt, "ssssssissii", $ticket_number, $emp_name, $subject, $message, $status, $priority, $timeline, $deadline, $attachment, $emp_id, $emp_id);
            mysqli_stmt_execute($stmt);
            mysqli_stmt_close($stmt);
            $_SESSION['success_message'] = "Reminder ticket sent to $emp_name.";
        } else {
            $_SESSION['error_message'] = "Failed create ticket: " . mysqli_error($con);
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- RESET RECERT ATTEMPTS (HR manual reset) ----
    if ($action == 'reset_recert_attempts') {
        $emp_id  = intval($_POST['employee_id']);
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $cycle   = intval($_POST['cycle_number']);
        mysqli_query($con, "DELETE FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id=$dept_id AND position_id=$pos_id AND cycle_number=$cycle");
        $_SESSION['success_message'] = "Recertification attempts reset. Employee can retake Cycle $cycle.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================

$sel_cycle = isset($_GET['cycle']) ? intval($_GET['cycle']) : 1;

// Available Cycles
$available_cycles = [];
if ($sel_dept > 0) {
    $cq = mysqli_query($con, "SELECT DISTINCT cycle_number FROM hr_oje_recert_config WHERE department_id=$sel_dept AND position_id=$sel_pos ORDER BY cycle_number ASC");
    if (mysqli_num_rows($cq) == 0) {
        $cq = mysqli_query($con, "SELECT DISTINCT cycle_number FROM hr_oje_recert_config WHERE department_id=$sel_dept AND position_id=0 ORDER BY cycle_number ASC");
    }
    while ($c = mysqli_fetch_assoc($cq)) {
        $available_cycles[] = intval($c['cycle_number']);
    }
    if (empty($available_cycles)) {
        $available_cycles = [1];
    }
    if (!in_array($sel_cycle, $available_cycles)) {
        $sel_cycle = end($available_cycles);
    }
}

// Recert config
$recert_config = null;
if ($sel_dept > 0) {
    $recert_config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id=$sel_dept AND position_id=$sel_pos AND cycle_number=$sel_cycle LIMIT 1"));
    if (!$recert_config) $recert_config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id=$sel_dept AND position_id=0 AND cycle_number=$sel_cycle LIMIT 1"));
}

// Recert questions
$recert_questions = [];
if ($sel_dept > 0) {
    $qq = mysqli_query($con, "SELECT q.*, GROUP_CONCAT(o.id,'::',o.option_label,'::',o.points,'::',o.is_correct ORDER BY o.sort_order SEPARATOR '||') as options_raw
        FROM hr_oje_recert_questions q
        LEFT JOIN hr_oje_recert_question_options o ON o.question_id=q.id
        WHERE q.department_id=$sel_dept AND q.position_id=$sel_pos AND q.cycle_number=$sel_cycle
        GROUP BY q.id ORDER BY q.sort_order ASC");
    while ($q = mysqli_fetch_assoc($qq)) {
        $q['options'] = [];
        if (!empty($q['options_raw'])) {
            foreach (explode('||', $q['options_raw']) as $opt) {
                $parts = explode('::', $opt);
                if (count($parts) == 4) $q['options'][] = ['id'=>$parts[0],'label'=>$parts[1],'points'=>$parts[2],'is_correct'=>$parts[3]];
            }
        }
        $recert_questions[] = $q;
    }
}

// Employee recert status
$recert_employee_status = [];
if ($sel_dept > 0) {
    $interval_months = intval($recert_config['interval_months'] ?? 12);
    $interval_type   = $recert_config['interval_type'] ?? 'months';
    $max_att         = intval($recert_config['max_attempts'] ?? 3);
    $pass_pct        = floatval($recert_config['pass_percent'] ?? 95);
    $epq = mysqli_query($con, "SELECT p.employee_id, p.department_id, p.position_id, p.certified_at,
          e.name as emp_name, e.position as emp_position, e.department as emp_current_dept_name
          FROM hr_oje_employee_progress p
          INNER JOIN hr_employees e ON e.id=p.employee_id
          WHERE p.stage='certified' AND p.department_id=$sel_dept" . ($sel_pos > 0 ? " AND p.position_id=$sel_pos" : "") . "
          ORDER BY e.name ASC");

    while ($ep = mysqli_fetch_assoc($epq)) {
        $emp_id = intval($ep['employee_id']);

        // Skip if this is no longer the employee's current department (they were cross-trained away).
        // Their history remains visible in the History & Analytics tab and their career path.
        if (strcasecmp(trim($ep['emp_current_dept_name'] ?? ''), trim($sel_dept_name)) !== 0) {
            continue;
        }

        // Find last passed recert to determine cycle
        $lastPass = mysqli_fetch_assoc(mysqli_query($con, "SELECT attempted_at, cycle_number FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id={$ep['department_id']} AND position_id={$ep['position_id']} AND passed=1 ORDER BY attempted_at DESC LIMIT 1"));
        $cycleStart   = $lastPass ? $lastPass['attempted_at'] : $ep['certified_at'];
        $cycle_number = $lastPass ? (intval($lastPass['cycle_number']) + 1) : 1;
        $cConfigQ = mysqli_query($con, "SELECT * FROM hr_oje_recert_config WHERE department_id={$ep['department_id']} AND (position_id={$ep['position_id']} OR position_id=0) AND cycle_number=$cycle_number ORDER BY position_id DESC LIMIT 1");
        $empCycleConfig = mysqli_fetch_assoc($cConfigQ);
        $is_configured = $empCycleConfig ? true : false;

        if ($is_configured) {
            $e_int_type = $empCycleConfig['interval_type'] ?? 'months';
            $e_int_months = intval($empCycleConfig['interval_months'] ?? 12);
            $e_max_att = intval($empCycleConfig['max_attempts'] ?? 3);
            
            if ($e_int_type === 'date' && !empty($empCycleConfig['interval_date'])) {
                $due_date = $empCycleConfig['interval_date'];
            } else {
                $due_date = date('Y-m-d', strtotime($cycleStart . " +{$e_int_months} {$e_int_type}"));
            }
        } else {
            $due_date = '';
            $e_max_att = 3;
        }

        // Attempts this cycle
        $attemptsUsed = intval(mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id={$ep['department_id']} AND position_id={$ep['position_id']} AND cycle_number=$cycle_number"))['c']);
        $lastAttempt  = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id={$ep['department_id']} AND position_id={$ep['position_id']} AND cycle_number=$cycle_number ORDER BY attempt_number DESC LIMIT 1"));

        $is_due    = $is_configured && !empty($due_date) ? (strtotime($due_date) <= strtotime('+2 days')) : false;
        $is_failed = $is_configured ? ($attemptsUsed >= $e_max_att && !($lastAttempt['passed'] ?? 0)) : false;
        $is_passed = ($lastAttempt['passed'] ?? 0) && ($lastAttempt['cycle_number'] ?? 0) == $cycle_number;

        // Auto-generate ticket if it's exactly the due date (or past due) and no ticket was created yet
        if ($is_configured && !empty($due_date) && date('Y-m-d') >= date('Y-m-d', strtotime($due_date)) && !$is_passed && !$is_failed) {
            $tq = mysqli_query($con, "SELECT id FROM tickets WHERE assigned_to=$emp_id AND subject='Action Required: Recertification Due (Cycle {$cycle_number})' LIMIT 1");
            if ($tq && mysqli_num_rows($tq) == 0) {
                $maxRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
                $nextId = intval($maxRow['max_id'] ?? 0) + 1;
                $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);
                $timeline   = 2880;
                $deadline   = date('Y-m-d H:i:s', strtotime("+{$timeline} minutes"));
                
                $dRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id={$ep['department_id']} LIMIT 1"));
                $pRow = $ep['position_id'] > 0 ? mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id={$ep['position_id']} LIMIT 1")) : null;
                $d_name = $dRow['name'] ?? 'Department';
                $p_name = $pRow['title'] ?? 'All Positions';
                
                $link = "hr-employee-recert-crosstraining.php?view_emp={$emp_id}&dept_id={$ep['department_id']}&pos_id={$ep['position_id']}";
                $subject = "Action Required: Recertification Due (Cycle {$cycle_number})";
                $message = "Dear {$ep['emp_name']},\n\nYour recertification for Cycle {$cycle_number} ({$d_name} - {$p_name}) is now due.\n\nPlease complete your recertification here: {$link}";
                $priority = 'high'; $status = 'open'; $attachment = '';
                
                $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number,name,subject,message,status,priority,timeline,deadline,attachment,created_at,updated_at,assigned_to,created_by) VALUES (?,?,?,?,?,?,?,?,?,NOW(),NOW(),?,?)");
                if ($stmt) {
                    mysqli_stmt_bind_param($stmt, "ssssssissii", $ticket_number, $ep['emp_name'], $subject, $message, $status, $priority, $timeline, $deadline, $attachment, $emp_id, $emp_id);
                    mysqli_stmt_execute($stmt);
                    mysqli_stmt_close($stmt);
                }
            }
        }

        $ep['cycle_number']   = $cycle_number;
        $ep['due_date']       = $due_date;
        $ep['attempts_used']  = $attemptsUsed;
        $ep['max_attempts']   = $e_max_att;
        $ep['is_configured']  = $is_configured;
        $ep['is_due']         = $is_due;
        $ep['is_failed']      = $is_failed;
        $ep['is_passed_this_cycle'] = $is_passed;
        $ep['last_pct']       = $lastAttempt['percentage'] ?? null;

        $recert_employee_status[] = $ep;
    }
}

// Cross training records
$cross_training_records = [];
$ctWhere = $sel_dept > 0 ? "WHERE ct.to_dept_id=$sel_dept" . ($sel_pos > 0 ? " AND ct.to_pos_id=$sel_pos" : "") : "";
$ctq = mysqli_query($con, "SELECT ct.*, e.name as emp_name,
    fd.name as from_dept_name, fp.title as from_pos_name,
    td.name as to_dept_name, tp.title as to_pos_name,
    p.stage as current_stage
    FROM hr_oje_cross_training ct
    INNER JOIN hr_employees e ON e.id=ct.employee_id
    LEFT JOIN hr_departments fd ON fd.id=ct.from_dept_id
    LEFT JOIN hr_positions fp ON fp.id=ct.from_pos_id
    LEFT JOIN hr_departments td ON td.id=ct.to_dept_id
    LEFT JOIN hr_positions tp ON tp.id=ct.to_pos_id
    LEFT JOIN hr_oje_employee_progress p ON p.employee_id=ct.employee_id AND p.department_id=ct.to_dept_id AND p.position_id=ct.to_pos_id
    $ctWhere
    ORDER BY ct.created_at DESC");
if ($ctq) {
    while ($ct = mysqli_fetch_assoc($ctq)) {
        // Auto-complete + sync employee's home department/position if certified
        if (($ct['current_stage'] ?? '') === 'certified' && $ct['status'] === 'active') {
            mysqli_query($con, "UPDATE hr_oje_cross_training SET status='completed', updated_at=NOW() WHERE id={$ct['id']}");
            $ct['status'] = 'completed';

            $new_dept_name = mysqli_real_escape_string($con, $ct['to_dept_name'] ?? '');
            $new_pos_name  = mysqli_real_escape_string($con, $ct['to_pos_name'] ?? '');
            $new_pos_id    = intval($ct['to_pos_id']);
            $sync_emp_id   = intval($ct['employee_id']);
            if ($new_dept_name !== '') {
                mysqli_query($con, "UPDATE hr_employees SET department='$new_dept_name', position='$new_pos_name', position_id=$new_pos_id WHERE id=$sync_emp_id");
            }
        }
        $cross_training_records[] = $ct;
    }
}

// Group cross training records into per-employee chains (chronological)
$ct_chains = [];
foreach ($cross_training_records as $ctr) {
    $ct_chains[$ctr['employee_id']]['emp_name'] = $ctr['emp_name'];
    $ct_chains[$ctr['employee_id']]['hops'][] = $ctr;
}
foreach ($ct_chains as $eid => &$chain) {
    usort($chain['hops'], function($a, $b) { return strtotime($a['created_at']) <=> strtotime($b['created_at']); });
}
unset($chain);

// All employees for CT modal
$all_employees = [];
$eq = mysqli_query($con, "SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name ASC");
if ($eq) while ($e = mysqli_fetch_assoc($eq)) $all_employees[] = $e;

// =========================================================================
// HISTORY & ANALYTICS DATA
// =========================================================================
function hojeSafeCount($con, $sql) {
    $r = @mysqli_query($con, $sql);
    if (!$r) return 0;
    $row = mysqli_fetch_assoc($r);
    return intval($row['c'] ?? 0);
}

$history_employees = [];
$heWhere = $sel_dept > 0 ? "WHERE department_id=$sel_dept" . ($sel_pos > 0 ? " AND position_id=$sel_pos" : "") : "";
$heq = mysqli_query($con, "SELECT DISTINCT employee_id FROM hr_oje_employee_progress $heWhere");
$emp_ids = [];
if ($heq) while ($r = mysqli_fetch_assoc($heq)) $emp_ids[] = intval($r['employee_id']);

$deptScope = $sel_dept > 0 ? " AND department_id=$sel_dept" . ($sel_pos > 0 ? " AND position_id=$sel_pos" : "") : "";

foreach ($emp_ids as $emp_id) {
    $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT name, department, position FROM hr_employees WHERE id=$emp_id LIMIT 1"));
    if (!$empRow) continue;

    $progRows = [];
    $pq = mysqli_query($con, "SELECT * FROM hr_oje_employee_progress WHERE employee_id=$emp_id" . $deptScope);
    if ($pq) while ($pr = mysqli_fetch_assoc($pq)) $progRows[] = $pr;
    $certified_count = 0;
    foreach ($progRows as $pr) if ($pr['stage'] == 'certified') $certified_count++;

    $training_completed = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_material_completions mc INNER JOIN hr_oje_material_items mi ON mi.id=mc.item_id WHERE mc.employee_id=$emp_id");
    $oje_completed      = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_material_completions mc INNER JOIN hr_oje_oje_items oi ON oi.id=mc.item_id WHERE mc.employee_id=$emp_id");

    $trRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) attempts, MAX(percentage) best_pct FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND type='training'" . $deptScope));
    $ojRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) attempts, MAX(percentage) best_pct FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND type='oje'" . $deptScope));

    $recert_passed = hojeSafeCount($con, "SELECT COUNT(DISTINCT cycle_number) c FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND passed=1" . $deptScope);
    $ct_total     = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_cross_training WHERE employee_id=$emp_id");
    $ct_active    = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_cross_training WHERE employee_id=$emp_id AND status='active'");

    $t_best = $trRow['best_pct'] ?? null;
    $o_best = $ojRow['best_pct'] ?? null;
    $overall_pct = null;
    if ($t_best !== null && $o_best !== null) $overall_pct = ($t_best + $o_best) / 2;
    elseif ($t_best !== null) $overall_pct = $t_best;
    elseif ($o_best !== null) $overall_pct = $o_best;

    // Full drill-down detail
    $detail = ['training_items'=>[], 'oje_items'=>[], 'training_attempts_list'=>[], 'oje_attempts_list'=>[], 'recert_list'=>[], 'ct_list'=>[]];

    $r1 = mysqli_query($con, "SELECT mi.item_title, htm.heading_name, mc.completed_at FROM hr_oje_material_completions mc INNER JOIN hr_oje_material_items mi ON mi.id=mc.item_id INNER JOIN hr_oje_training_materials htm ON htm.id=mi.heading_id WHERE mc.employee_id=$emp_id ORDER BY mc.completed_at DESC");
    if ($r1) while ($row = mysqli_fetch_assoc($r1)) $detail['training_items'][] = $row;

    $r2 = mysqli_query($con, "SELECT oi.item_title, ohh.heading_name, mc.completed_at FROM hr_oje_material_completions mc INNER JOIN hr_oje_oje_items oi ON oi.id=mc.item_id INNER JOIN hr_oje_oje_headings ohh ON ohh.id=oi.heading_id WHERE mc.employee_id=$emp_id ORDER BY mc.completed_at DESC");
    if ($r2) while ($row = mysqli_fetch_assoc($r2)) $detail['oje_items'][] = $row;

    $r3 = mysqli_query($con, "SELECT * FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND type='training' ORDER BY attempted_at DESC");
    if ($r3) while ($row = mysqli_fetch_assoc($r3)) $detail['training_attempts_list'][] = $row;

    $r4 = mysqli_query($con, "SELECT * FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND type='oje' ORDER BY attempted_at DESC");
    if ($r4) while ($row = mysqli_fetch_assoc($r4)) $detail['oje_attempts_list'][] = $row;

    $r5 = mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE employee_id=$emp_id ORDER BY cycle_number DESC, attempt_number DESC");
    if ($r5) while ($row = mysqli_fetch_assoc($r5)) $detail['recert_list'][] = $row;

    $r6 = mysqli_query($con, "SELECT ct.*, fd.name as from_dept_name, fp.title as from_pos_name, td.name as to_dept_name, tp.title as to_pos_name,
      p.stage as current_stage
      FROM hr_oje_cross_training ct
      INNER JOIN hr_employees e ON e.id=ct.employee_id
      LEFT JOIN hr_departments fd ON fd.id=ct.from_dept_id LEFT JOIN hr_positions fp ON fp.id=ct.from_pos_id
      LEFT JOIN hr_oje_employee_progress p ON p.employee_id=ct.employee_id AND p.department_id=ct.to_dept_id AND p.position_id=ct.to_pos_id
      LEFT JOIN hr_departments td ON td.id=ct.to_dept_id LEFT JOIN hr_positions tp ON tp.id=ct.to_pos_id
      WHERE ct.employee_id=$emp_id ORDER BY ct.created_at DESC");
    if ($r6) while ($row = mysqli_fetch_assoc($r6)) $detail['ct_list'][] = $row;

    $history_employees[] = [
        'employee_id' => $emp_id, 'emp_name' => $empRow['name'],
        'department' => $empRow['department'] ?? '', 'position' => $empRow['position'] ?? '',
        'training_completed' => $training_completed, 'oje_completed' => $oje_completed,
        'training_attempts' => intval($trRow['attempts'] ?? 0), 'training_best_pct' => $t_best,
        'oje_attempts' => intval($ojRow['attempts'] ?? 0), 'oje_best_pct' => $o_best,
        'recert_passed' => $recert_passed, 'ct_total' => $ct_total, 'ct_active' => $ct_active,
        'certified_count' => $certified_count, 'overall_pct' => $overall_pct, 'detail' => $detail,
    ];
}

usort($history_employees, function($a, $b) {
    // 1. Overall %
    if ($a['overall_pct'] === null && $b['overall_pct'] !== null) return 1;
    if ($b['overall_pct'] === null && $a['overall_pct'] !== null) return -1;
    if ($a['overall_pct'] !== null && $b['overall_pct'] !== null) {
        $cmp = $b['overall_pct'] <=> $a['overall_pct'];
        if ($cmp !== 0) return $cmp;
    }
    
    // 2. Certified (Descending)
    $cmp = $b['certified_count'] <=> $a['certified_count'];
    if ($cmp !== 0) return $cmp;
    
    // 3. Recert Passed (Descending)
    $cmp = $b['recert_passed'] <=> $a['recert_passed'];
    if ($cmp !== 0) return $cmp;
    
    // 4. Cross Training (Descending)
    $cmp = $b['ct_total'] <=> $a['ct_total'];
    if ($cmp !== 0) return $cmp;
    
    // 5. Total items completed (Descending)
    $total_a = $a['training_completed'] + $a['oje_completed'];
    $total_b = $b['training_completed'] + $b['oje_completed'];
    $cmp = $total_b <=> $total_a;
    if ($cmp !== 0) return $cmp;
    
    // 6. Name (Ascending)
    return strcmp($a['emp_name'], $b['emp_name']);
});

// ---- Chart data (counts-based, not percentage) ----

// Certification status
$cert_yes = 0; $cert_no = 0;
foreach ($history_employees as $he) { if ($he['certified_count'] > 0) $cert_yes++; else $cert_no++; }

// Cross training status
$ctConds = [];
if ($sel_dept > 0) { $ctConds[] = "to_dept_id=$sel_dept"; if ($sel_pos > 0) $ctConds[] = "to_pos_id=$sel_pos"; }
$ctWhereStr = $ctConds ? "WHERE " . implode(" AND ", $ctConds) : "";
$ct_active_total = 0; $ct_completed_total = 0; $ct_cancelled_total = 0;
$ctAggQ = mysqli_query($con, "SELECT status, COUNT(*) c FROM hr_oje_cross_training $ctWhereStr GROUP BY status");
if ($ctAggQ) while ($r = mysqli_fetch_assoc($ctAggQ)) {
    if ($r['status']=='active') $ct_active_total = intval($r['c']);
    elseif ($r['status']=='completed') $ct_completed_total = intval($r['c']);
    elseif ($r['status']=='cancelled') $ct_cancelled_total = intval($r['c']);
}

// Recertification pass/fail
$recertConds = ["passed=1"];
if ($sel_dept > 0) { $recertConds[] = "department_id=$sel_dept"; if ($sel_pos > 0) $recertConds[] = "position_id=$sel_pos"; }
$recert_pass_total = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_recert_attempts WHERE " . implode(" AND ", $recertConds));
$recertConds[0] = "passed=0";
$recert_fail_total = hojeSafeCount($con, "SELECT COUNT(*) c FROM hr_oje_recert_attempts WHERE " . implode(" AND ", $recertConds));

// ---- Org-wide aggregate totals (scales regardless of employee count) ----
$agg_training_completed = array_sum(array_column($history_employees, 'training_completed'));
$agg_oje_completed      = array_sum(array_column($history_employees, 'oje_completed'));
$agg_recert_passed      = array_sum(array_column($history_employees, 'recert_passed'));
$agg_ct_total           = array_sum(array_column($history_employees, 'ct_total'));
$agg_certified_emps     = $cert_yes;
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Recertification & Cross Training  <?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="css/app.css" type="text/css"/>
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
function confirmForm(btn, msg) {
    var form = btn.closest('form');
    Swal.fire({
        title: 'Are you sure?',
        text: msg,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#10b981',
        cancelButtonColor: '#ef4444',
        confirmButtonText: 'Yes, proceed!'
    }).then((result) => {
        if (result.isConfirmed) {
            form.submit();
        }
    });
    return false;
}
function confirmOnSubmit(e, msg) {
    e.preventDefault();
    var form = e.target;
    Swal.fire({
        title: 'Are you sure?',
        text: msg,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#10b981',
        cancelButtonColor: '#ef4444',
        confirmButtonText: 'Yes, proceed!'
    }).then((result) => {
        if (result.isConfirmed) {
            form.submit();
        }
    });
}
</script>
<style>
:root {
  --navy: #0f2557; --blue: #1a3fc4; --light-blue: #e0e7ff;
  --green: #10b981; --amber: #f59e0b; --red: #ef4444; --gray-bg: #f0f4f8;
}
* { box-sizing: border-box; }
body { font-family: 'Plus Jakarta Sans', sans-serif; background: var(--gray-bg); }

.oje-header {
  background: linear-gradient(135deg, #0f2557 0%, #1a3fc4 100%);
  padding: 22px 32px; display: flex; justify-content: space-between; align-items: center;
  border-radius: 12px; margin-bottom: 24px; box-shadow: 0 4px 20px rgba(15,37,87,0.3);
}
.oje-header h1 { color: #fff; font-weight: 800; margin: 0; font-size: 1.5rem; }
.oje-header p  { color: rgba(255,255,255,0.65); font-size: 12px; margin: 4px 0 0; }

.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; flex-wrap: wrap; }
.nav-btn {
  padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
  font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05);
  display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

.filter-bar {
  background: #fff; padding: 18px 24px; border-radius: 10px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.06); margin-bottom: 20px;
  display: flex; align-items: center; flex-wrap: wrap; gap: 14px;
}
.filter-bar label { font-weight: 700; font-size: 13px; color: var(--navy); margin: 0; }
.filter-bar select { border: 2px solid #e0e7ff; border-radius: 8px; padding: 8px 14px; font-size: 13px; font-weight: 600; color: var(--navy); min-width: 200px; }

/* DataTables controls alignment fix */
.dataTables_wrapper .dt-buttons { display: flex; gap: 8px; flex-wrap: wrap; }
.dataTables_wrapper .dataTables_filter input { border: 2px solid #e0e7ff; border-radius: 8px; padding: 6px 12px; font-size: 13px; margin-left: 6px; }
.dataTables_wrapper .dataTables_length select { border: 2px solid #e0e7ff; border-radius: 8px; padding: 6px 10px; font-size: 13px; }

.main-tabs { display: flex; gap: 0; border-bottom: 2px solid #e0e7ff; margin-bottom: 24px; flex-wrap: wrap; }
.main-tab {
  padding: 12px 22px; font-weight: 700; font-size: 13px; color: #64748b;
  cursor: pointer; border-bottom: 3px solid transparent; margin-bottom: -2px; transition: all .2s; white-space: nowrap;
}
.main-tab:hover { color: var(--blue); }
.main-tab.active { color: var(--blue); border-bottom-color: var(--blue); }

.card-box { background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 2px 10px rgba(0,0,0,0.06); margin-bottom: 20px; }
.card-box h5 { font-weight: 800; color: var(--navy); margin-bottom: 16px; font-size: 14px; }
.empty-hint { text-align: center; padding: 40px; color: #94a3b8; }

.q-card { border: 1.5px solid #e0e7ff; border-radius: 10px; padding: 16px; margin-bottom: 12px; }
.q-card .q-num  { font-size: 11px; font-weight: 800; color: var(--blue); text-transform: uppercase; margin-bottom: 6px; }
.q-card .q-text { font-weight: 700; color: var(--navy); font-size: 14px; margin-bottom: 10px; }
.option-row { display: flex; align-items: center; gap: 8px; padding: 6px 10px; border-radius: 6px; margin-bottom: 4px; background: #f8fafc; }
.option-row.correct { background: #d1fae5; }
.option-badge { font-size: 11px; font-weight: 800; padding: 2px 8px; border-radius: 10px; }
.option-badge.correct { background: #10b981; color: #fff; }
.option-badge.pts { background: #e0e7ff; color: var(--blue); }

.btn-add { background: var(--blue); color: #fff; border: none; padding: 8px 18px; border-radius: 8px; font-weight: 700; font-size: 13px; cursor: pointer; }
.btn-add:hover { background: var(--navy); }
.btn-sm-del { background: #fee2e2; color: var(--red); border: 1px solid #fca5a5; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; }

.config-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
@media(max-width:600px){ .config-grid { grid-template-columns: 1fr; } }

.form-field { margin-bottom: 16px; }
.form-field label { display: block; font-weight: 700; font-size: 12px; color: var(--navy); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.5px; }
.form-field input, .form-field select, .form-field textarea {
  width: 100%; padding: 10px 14px; border: 2px solid #e0e7ff; border-radius: 8px;
  font-size: 13px; font-weight: 600; color: var(--navy); font-family: inherit; transition: .2s;
}
.form-field input:focus, .form-field select:focus, .form-field textarea:focus {
  border-color: var(--blue); box-shadow: 0 0 0 3px rgba(26,63,196,.08); outline: none;
}

.perf-table { width: 100%; border-collapse: collapse; }
.perf-table th { background: #f0f4f8; color: var(--navy); font-weight: 800; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; padding: 10px 14px; border-bottom: 2px solid #e0e7ff; }
.perf-table td { padding: 12px 14px; border-bottom: 1px solid #f1f5f9; font-size: 13px; vertical-align: middle; }
.perf-table tr:hover td { background: #f8faff; }

.status-badge-ct { display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 800; }
.status-badge-ct.active    { background: #dbeafe; color: #1e40af; }
.status-badge-ct.completed { background: #d1fae5; color: #065f46; }
.status-badge-ct.cancelled { background: #f1f5f9; color: #64748b; }

.recert-status-badge { display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 800; }
.recert-status-badge.due    { background: #fef3c7; color: #92400e; }
.recert-status-badge.ok     { background: #d1fae5; color: #065f46; }
.recert-status-badge.failed { background: #fee2e2; color: #991b1b; }
.recert-status-badge.passed { background: #d1fae5; color: #065f46; }

.option-builder { border: 1.5px solid #e0e7ff; border-radius: 8px; overflow: hidden; }
.option-builder-row { display: grid; grid-template-columns: 1fr auto auto auto; gap: 8px; align-items: center; padding: 8px 12px; border-bottom: 1px solid #f1f5f9; }
.option-builder-row:last-child { border-bottom: none; }
.option-builder-header { background: #f8faff; font-weight: 700; font-size: 11px; text-transform: uppercase; color: #94a3b8; }

.ct-stage-badge { display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 800; }
.ct-stage-badge.training      { background: #e0e7ff; color: var(--blue); }
.ct-stage-badge.training_test { background: #fef3c7; color: #92400e; }
.ct-stage-badge.oje_reading   { background: #dbeafe; color: #1e40af; }
.ct-stage-badge.oje_test      { background: #ede9fe; color: #5b21b6; }
.ct-stage-badge.certified     { background: #d1fae5; color: #065f46; }
.ct-stage-badge.failed        { background: #fee2e2; color: #991b1b; }

/* Hide footer copyright notice on this page */
footer, .footer, .site-footer { display: none !important; }
</style>
</head>
<body>
<div class="container-fluid" style="padding: 30px; max-width: 1400px; margin: 0 auto;">

<?php if(isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show"><i class="fas fa-check-circle mr-2"></i><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>
<?php if(isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show"><i class="fas fa-exclamation-circle mr-2"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>

<!-- HEADER -->
<div class="oje-header">
  <div>
    <h1><i class="fas fa-sync-alt mr-2"></i> Recertification & Cross Training</h1>
    <p>Manage employee recertification cycles and cross training assignments</p>
  </div>
  <?php
  $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
  $dashboard_url = $is_admin ? 'index.php' : 'db-dashboard.php';
  ?>
  <a href="<?php echo isset($dashboard_url) ? $dashboard_url : 'index.php'; ?>" class="btn-action btn-dashboard" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); box-shadow: 0 4px 15px rgba(139, 92, 246, 0.3); color: white; text-decoration: none; padding: 10px 20px; border-radius: 8px; font-weight: 600; display: inline-flex; align-items: center; gap: 8px; transition: all 0.3s;">
    <i class="fas fa-arrow-left"></i> Back to Dashboard
  </a>
</div>

<!-- NAV TABS -->
<div class="nav-tabs-container">
  <a href="hr-OJE.php" class="nav-btn"><i class="fas fa-graduation-cap"></i> Training & OJE</a>
  <a href="hr-recert-crosstraining.php" class="nav-btn <?php echo $active_tab != 'history' ? 'active' : ''; ?>"><i class="fas fa-sync-alt"></i> Recertification & Cross Training</a>
  <a href="hr-recert-crosstraining.php?tab=history" class="nav-btn <?php echo $active_tab == 'history' ? 'active' : ''; ?>"><i class="fas fa-history"></i> History & Analytics</a>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
  <form method="GET" class="d-flex align-items-center flex-wrap" style="gap:14px;" id="filterForm">
    <input type="hidden" name="tab" value="<?php echo htmlspecialchars($active_tab); ?>">
    <div class="d-flex align-items-center" style="gap:8px;">
      <label>Department:</label>
      <select name="dept_id" onchange="document.getElementById('filterForm').submit()">
        <option value="0">All Departments</option>
        <?php foreach($departments as $d): ?>
        <option value="<?php echo $d['id']; ?>" <?php if($sel_dept==$d['id']) echo 'selected'; ?>><?php echo htmlspecialchars($d['name']); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <?php if ($sel_dept > 0): ?>
    <div class="d-flex align-items-center" style="gap:8px;">
      <label>Position:</label>
      <select name="pos_id" onchange="document.getElementById('filterForm').submit()">
        <option value="0">All Positions</option>
        <?php foreach($positions as $p): ?>
        <option value="<?php echo $p['id']; ?>" <?php if($sel_pos==$p['id']) echo 'selected'; ?>><?php echo htmlspecialchars($p['title']); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <?php endif; ?>
  </form>
</div>

<!-- MAIN TABS -->
<div class="main-tabs" style="display: <?php echo $active_tab == 'history' ? 'none' : 'flex'; ?>;">
  <div class="main-tab <?php echo $active_tab=='recertification'?'active':''; ?>" onclick="switchTab('recertification')">
    <i class="fas fa-sync-alt mr-1"></i> Recertification
  </div>
  <div class="main-tab <?php echo $active_tab=='cross_training'?'active':''; ?>" onclick="switchTab('cross_training')">
    <i class="fas fa-exchange-alt mr-1"></i> Cross Training
  </div>
</div>

  <!-- ======================= TAB: RECERTIFICATION ======================= -->
<div id="tab-recertification" class="tab-panel" style="display:<?php echo $active_tab=='recertification'?'block':'none'; ?>">

  <?php if ($sel_dept == 0): ?>
  <div class="d-flex justify-content-between align-items-center mb-4 mt-2">
    <h4 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-layer-group mr-2 text-primary"></i>All Recertification Configurations</h4>
    <div>
      <button type="button" class="btn btn-outline-primary mr-2" style="font-weight:700;border-radius:8px;border-color:var(--blue);color:var(--blue);" onclick="$('#allEmpRecertSection').slideToggle();"><i class="fas fa-users mr-1"></i> View All Employees</button>
      <button class="btn-add" data-toggle="modal" data-target="#newRecertConfigModal"><i class="fas fa-plus mr-1"></i> New Configuration</button>
    </div>
  </div>
  
  <?php
  // Fetch overview for recertification configs
  $overviewQuery = "
      SELECT 
          d.id as dept_id, d.name as dept_name,
          p.id as pos_id, p.title as pos_title,
          (SELECT MAX(cycle_number) FROM hr_oje_recert_config WHERE department_id = d.id AND position_id = COALESCE(p.id, 0)) as max_cycles,
          (SELECT COUNT(*) FROM hr_oje_recert_questions WHERE department_id = d.id AND position_id = COALESCE(p.id, 0)) as total_questions
      FROM (
          SELECT department_id, position_id FROM hr_oje_recert_config
          UNION
          SELECT department_id, position_id FROM hr_oje_recert_questions
      ) as configs
      JOIN hr_departments d ON d.id = configs.department_id
      LEFT JOIN hr_positions p ON p.id = configs.position_id
      ORDER BY d.name ASC, p.title ASC
  ";
  $overviewRes = mysqli_query($con, $overviewQuery);
  if (!$overviewRes) {
      echo '<div class="alert alert-danger">SQL Error: ' . mysqli_error($con) . '</div>';
  }
  ?>
  <div class="row">
  <?php 
  if ($overviewRes && mysqli_num_rows($overviewRes) > 0) {
      while ($row = mysqli_fetch_assoc($overviewRes)) {
          $dept_name = $row['dept_name'];
          $pos_title = empty($row['pos_id']) ? 'All Positions' : $row['pos_title'];
          $link = "hr-recert-crosstraining.php?tab=recertification&dept_id={$row['dept_id']}&pos_id=" . intval($row['pos_id']);
          
          echo '<div class="col-md-4 mb-4">';
          echo '<div class="card-box" style="height:100%; display:flex; flex-direction:column; padding:20px;">';
          echo '<div style="flex:1;">';
          echo '<div style="font-size:12px; font-weight:800; color:#64748b; text-transform:uppercase; margin-bottom:4px;"><i class="fas fa-building mr-1"></i>' . htmlspecialchars($dept_name) . '</div>';
          echo '<h5 style="font-weight:800; color:#0f2557; margin-bottom:12px;"><i class="fas fa-briefcase mr-1" style="color:#1e40af;"></i>' . htmlspecialchars($pos_title) . '</h5>';
          
          echo '<div style="display:flex; gap:10px; margin-bottom:15px; flex-wrap:wrap;">';
          echo '<span style="font-size:12px; font-weight:700; background:#f0fdf4; color:#16a34a; padding:4px 10px; border-radius:20px;"><i class="fas fa-sync mr-1"></i>' . ($row['max_cycles'] ?? 1) . ' Cycles Configured</span>';
          echo '<span style="font-size:12px; font-weight:700; background:#eff6ff; color:#2563eb; padding:4px 10px; border-radius:20px;"><i class="fas fa-question-circle mr-1"></i>' . $row['total_questions'] . ' Total Questions</span>';
          echo '</div>';
          echo '</div>';
          
          echo '<a href="'.$link.'" class="btn btn-primary btn-sm text-center" style="display:block; text-decoration:none; border-radius:8px; font-weight:700;"><i class="fas fa-cog mr-1"></i> Manage Configuration</a>';
          echo '</div>';
          echo '</div>';
      }
  } else {
      echo '<div class="col-12"><div class="card-box"><div class="empty-hint"><i class="fas fa-clipboard-list fa-2x mb-3"></i><p style="margin:0;">No Recertification configurations found. Create one to get started.</p></div></div></div>';
  }
  ?>
  </div>

  <?php
  // ---- ALL EMPLOYEES  RECERTIFICATION (combined across departments/positions, respects filters) ----
  $allRecertWhere = ["p.stage='certified'"];
  if ($sel_dept > 0) { $allRecertWhere[] = "p.department_id=$sel_dept"; if ($sel_pos > 0) $allRecertWhere[] = "p.position_id=$sel_pos"; }
  $allRecertWhereSql = "WHERE " . implode(" AND ", $allRecertWhere);
  $allRecertQ = mysqli_query($con, "SELECT p.employee_id, p.department_id, p.position_id, p.certified_at,
      e.name as emp_name, e.department as emp_current_dept_name, d.name as dept_name, pos.title as pos_title
      FROM hr_oje_employee_progress p
      LEFT JOIN hr_employees e ON e.id=p.employee_id
      LEFT JOIN hr_departments d ON d.id=p.department_id
      LEFT JOIN hr_positions pos ON pos.id=p.position_id
      $allRecertWhereSql
      ORDER BY e.name ASC");
  $allRecertRows = [];
  if ($allRecertQ) {
      while ($ep = mysqli_fetch_assoc($allRecertQ)) {
          $emp_id = intval($ep['employee_id']);

          // Only track recertification for the employee's CURRENT department (skip stale entries after transfer)
          if (strcasecmp(trim($ep['emp_current_dept_name'] ?? ''), trim($ep['dept_name'] ?? '')) !== 0) {
              continue;
          }
          $lastPass = mysqli_fetch_assoc(mysqli_query($con, "SELECT attempted_at, cycle_number FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id={$ep['department_id']} AND position_id={$ep['position_id']} AND passed=1 ORDER BY attempted_at DESC LIMIT 1"));
          $cycle_number = $lastPass ? (intval($lastPass['cycle_number']) + 1) : 1;
          $lastAttempt = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE employee_id=$emp_id AND department_id={$ep['department_id']} AND position_id={$ep['position_id']} AND cycle_number=$cycle_number ORDER BY attempt_number DESC LIMIT 1"));
          $ep['cycle_number'] = $cycle_number;
          $ep['last_pct'] = $lastAttempt['percentage'] ?? null;
          $ep['is_passed_this_cycle'] = ($lastAttempt['passed'] ?? 0) ? true : false;
          $allRecertRows[] = $ep;
      }
  }
  ?>

  <div id="allEmpRecertSection" style="display:none;">
  <div class="d-flex justify-content-between align-items-center mb-3 mt-4">
    <h4 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-users mr-2 text-primary"></i>Employee Recertification  All Employees</h4>
    <span style="font-size:12px;color:#64748b;" id="table1LiveCount"><?php echo count($allRecertRows); ?> certified employees found</span>
  </div>
  <?php if (!empty($allRecertRows)): ?>
  <div class="card-box" id="table1FilterBar" style="margin-bottom:14px;">
    <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Employees</h5>
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
        <input type="text" id="t1-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Department</label>
        <select id="t1-dept" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Departments</option>
          <?php foreach ($departments as $d): ?><option value="<?php echo htmlspecialchars($d['name']); ?>"><?php echo htmlspecialchars($d['name']); ?></option><?php endforeach; ?>
        </select>
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Position</label>
        <select id="t1-pos" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Positions</option>
          <?php
          $all_pos_q1 = mysqli_query($con, "SELECT DISTINCT title FROM hr_positions ORDER BY title ASC");
          if ($all_pos_q1) while ($pr = mysqli_fetch_assoc($all_pos_q1)): ?>
            <option value="<?php echo htmlspecialchars($pr['title']); ?>"><?php echo htmlspecialchars($pr['title']); ?></option>
          <?php endwhile; ?>
        </select>
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Certified From</label>
        <input type="date" id="t1-from" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Certified To</label>
        <input type="date" id="t1-to" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div>
        <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetT1Filters()"><i class="fas fa-redo mr-1"></i> Reset</button>
      </div>
      <div style="display:flex;gap:8px;">
        <button type="button" class="btn btn-success btn-sm" onclick="window.t1 && window.t1.button(0).trigger();"><i class="fas fa-file-excel mr-1"></i> Excel</button>
        <button type="button" class="btn btn-info btn-sm" onclick="window.t1 && window.t1.button(1).trigger();"><i class="fas fa-file-csv mr-1"></i> CSV</button>
      </div>
    </div>
  </div>
  <?php endif; ?>
  <div class="card-box" style="padding:0;overflow:hidden;">
    <?php if (empty($allRecertRows)): ?>
      <div class="empty-hint"><i class="fas fa-users fa-2x mb-2"></i><p>No certified employees found<?php echo $sel_dept>0 ? ' for this filter.' : '.'; ?></p></div>
    <?php else: ?>
    <div style="overflow-x:auto;">
      <table class="perf-table" id="table1">
        <thead>
          <tr>
            <th>Employee</th>
            <th>Department / Position</th>
            <th>Cycle</th>
            <th>Last Score</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($allRecertRows as $rs): 
            $isCross = (strtolower(trim($rs['emp_dept'] ?? '')) !== strtolower(trim($rs['dept_name'] ?? ''))) || (strtolower(trim($rs['emp_pos'] ?? '')) !== strtolower(trim($rs['pos_title'] ?? 'All Positions')));
          ?>
          <tr data-empname="<?php echo htmlspecialchars(strtolower($rs['emp_name'] ?? '')); ?>" data-dept="<?php echo htmlspecialchars($rs['dept_name'] ?? ''); ?>" data-pos="<?php echo htmlspecialchars($rs['pos_title'] ?? ''); ?>" data-startdate="<?php echo $rs['certified_at'] ? date('Y-m-d', strtotime($rs['certified_at'])) : ''; ?>">
            <td>
              <div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($rs['emp_name']); ?></div>

            </td>
            <td>
              <div style="font-size:12px;font-weight:700;color:#334155;"><?php echo htmlspecialchars($rs['dept_name'] ?? '  '); ?></div>
              <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($rs['pos_title'] ?? 'All Positions'); ?></div>
            </td>
            <td><span style="font-weight:800;color:var(--blue);">Cycle <?php echo $rs['cycle_number']; ?></span></td>
            <td><?php echo $rs['last_pct'] !== null ? number_format($rs['last_pct'],1).'%' : '  '; ?></td>
            <td>
              <?php if ($rs['is_passed_this_cycle']): ?>
                <span class="recert-status-badge passed"><i class="fas fa-check-circle"></i> Passed</span>
              <?php else: ?>
                <span class="recert-status-badge ok"><i class="fas fa-shield-alt"></i> On Track</span>
              <?php endif; ?>
            </td>
            <td>
              <button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;"
                onclick="openUnifiedViewModal(<?php echo $rs['employee_id']; ?>, <?php echo $rs['department_id']; ?>, <?php echo $rs['position_id']; ?>, 'recert', <?php echo $rs['cycle_number']; ?>, '<?php echo htmlspecialchars(addslashes($rs['emp_name'])); ?>', '<?php echo htmlspecialchars(addslashes($rs['dept_name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($rs['pos_title'] ?? '')); ?>')">
                <i class="fas fa-eye mr-1"></i> View
              </button>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
  </div>

  <?php else: ?>

  <!-- Cycle Navigation -->
  <div style="display:flex; gap:10px; margin-bottom:20px; align-items:center; flex-wrap:wrap;">
    <span style="font-size:13px; font-weight:800; color:var(--navy); text-transform:uppercase; letter-spacing:1px; margin-right:10px;"><i class="fas fa-sync-alt mr-1"></i> Configure Cycle:</span>
    <?php foreach ($available_cycles as $cyc): ?>
      <a href="?tab=recertification&dept_id=<?php echo $sel_dept; ?>&pos_id=<?php echo $sel_pos; ?>&cycle=<?php echo $cyc; ?>" class="btn btn-sm <?php echo $sel_cycle == $cyc ? 'btn-primary' : 'btn-light'; ?>" style="font-weight:700; border-radius:8px;">
        Cycle <?php echo $cyc; ?>
      </a>
    <?php endforeach; ?>
    <?php $next_cycle = max($available_cycles) + 1; ?>
    <form method="POST" style="margin:0;">
      <input type="hidden" name="action" value="create_next_cycle">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="cycle_number" value="<?php echo $next_cycle; ?>">
      <button type="button" class="btn btn-sm btn-outline-success" style="font-weight:700; border-radius:8px;" onclick="return confirmForm(this, 'Create Cycle <?php echo $next_cycle; ?> configuration?');">
        <i class="fas fa-plus"></i> Add Cycle <?php echo $next_cycle; ?>
      </button>
    </form>
  </div>

  <!-- Config -->
  <div class="card-box">
    <h5><i class="fas fa-cog mr-2"></i>Cycle <?php echo $sel_cycle; ?> Configuration  <?php echo htmlspecialchars($sel_dept_name); ?><?php echo $sel_pos > 0 ? ' â†’ '.htmlspecialchars($sel_pos_title) : ''; ?></h5>
    <form method="POST">
      <input type="hidden" name="action" value="save_recert_config">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="cycle_number" value="<?php echo $sel_cycle; ?>">
      <div class="config-grid">
        <div class="form-field">
          <label><i class="fas fa-calendar-alt mr-1"></i> Recertification Interval</label>
          <div class="d-flex" style="gap:10px;" id="intervalInputsContainer">
            <input type="number" id="interval_number" name="interval_months" min="1" max="1000" value="<?php echo $recert_config['interval_months'] ?? 12; ?>" required style="flex:1; <?php echo (isset($recert_config['interval_type']) && $recert_config['interval_type']=='date') ? 'display:none;' : ''; ?>">
            <input type="date" id="interval_date" name="interval_date" value="<?php echo $recert_config['interval_date'] ?? ''; ?>" style="flex:1; <?php echo (isset($recert_config['interval_type']) && $recert_config['interval_type']=='date') ? '' : 'display:none;'; ?>">
            <select name="interval_type" id="interval_type" style="width:120px;" required onchange="toggleIntervalInput(this.value)">
              <option value="days" <?php echo (isset($recert_config['interval_type']) && $recert_config['interval_type']=='days') ? 'selected' : ''; ?>>Days</option>
              <option value="months" <?php echo (!isset($recert_config['interval_type']) || $recert_config['interval_type']=='months') ? 'selected' : ''; ?>>Months</option>
              <option value="years" <?php echo (isset($recert_config['interval_type']) && $recert_config['interval_type']=='years') ? 'selected' : ''; ?>>Years</option>
              <option value="date" <?php echo (isset($recert_config['interval_type']) && $recert_config['interval_type']=='date') ? 'selected' : ''; ?>>Date</option>
            </select>
          </div>
          <script>
          function toggleIntervalInput(val) {
              var numInput = document.getElementById('interval_number');
              var dateInput = document.getElementById('interval_date');
              if (val === 'date') {
                  numInput.style.display = 'none'; numInput.removeAttribute('required');
                  dateInput.style.display = 'block'; dateInput.setAttribute('required', 'required');
              } else {
                  numInput.style.display = 'block'; numInput.setAttribute('required', 'required');
                  dateInput.style.display = 'none'; dateInput.removeAttribute('required');
              }
          }
          document.addEventListener("DOMContentLoaded", function() {
              var sel = document.getElementById('interval_type');
              if(sel) toggleIntervalInput(sel.value);
          });
          </script>
        </div>
        <div class="form-field">
          <label><i class="fas fa-percent mr-1"></i> Pass Percentage</label>
          <input type="number" name="pass_percent" min="1" max="100" step="0.01" value="<?php echo $recert_config['pass_percent'] ?? 95; ?>" required>
        </div>
        <div class="form-field">
          <label><i class="fas fa-redo mr-1"></i> Max Attempts Per Cycle</label>
          <input type="number" name="max_attempts" min="1" max="10" value="<?php echo $recert_config['max_attempts'] ?? 3; ?>" required>
        </div>
      </div>
      <button type="submit" class="btn-add"><i class="fas fa-save mr-1"></i> Save Configuration</button>
    </form>
  </div>

  <!-- Question Bank -->
  <div class="card-box">
      <div class="d-flex justify-content-between align-items-center mb-3">
        <h5 style="margin:0;"><i class="fas fa-question-circle mr-2 text-warning"></i>Recertification Question Bank</h5>
        <div class="d-flex gap-2" style="gap:8px;">
          <a href="?action=export_questions&dept_id=<?php echo $sel_dept; ?>&pos_id=<?php echo $sel_pos; ?>" class="btn btn-sm" style="background:#f1f5f9;border:1px solid #cbd5e1;color:#475569;font-weight:700;"><i class="fas fa-file-export mr-1"></i> Export</a>
          <button class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick="openImportModal()"><i class="fas fa-file-import mr-1"></i> Import</button>
          <button class="btn-add" onclick="openAddRecertQModal()"><i class="fas fa-plus mr-1"></i> Add Question</button>
        </div>
      </div>
    <?php if (empty($recert_questions)): ?>
      <div class="empty-hint"><i class="fas fa-question fa-2x mb-2"></i><p>No recertification questions yet.</p></div>
    <?php else: foreach ($recert_questions as $idx => $q): ?>
      <div class="q-card">
        <div class="q-num">Question <?php echo $idx+1; ?></div>
        <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
        <div style="margin-bottom:8px;">
          <?php foreach ($q['options'] as $opt): ?>
            <div class="option-row <?php echo $opt['is_correct']?'correct':''; ?>">
              <span style="flex:1;font-size:12px;font-weight:600;color:#334155;"><?php echo htmlspecialchars($opt['label']); ?></span>
              <span class="option-badge pts"><i class="fas fa-star" style="color:#f59e0b;"></i> <?php echo $opt['points']; ?> pts</span>
              <?php if ($opt['is_correct']): ?><span class="option-badge correct"><i class="fas fa-check"></i> Correct</span><?php endif; ?>
            </div>
          <?php endforeach; ?>
        </div>
        <div class="d-flex gap-2" style="gap:8px;">
          <button type="button" class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick='openEditRecertQModal(<?php echo htmlspecialchars(json_encode($q), ENT_QUOTES, "UTF-8"); ?>)'><i class="fas fa-edit mr-1"></i> Edit</button>
          <form method="POST" style="display:inline;" onsubmit="confirmOnSubmit(event, 'Delete this question?')">
            <input type="hidden" name="action" value="delete_recert_question">
            <input type="hidden" name="id" value="<?php echo $q['id']; ?>">
            <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
            <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
            <input type="hidden" name="cycle_number" value="<?php echo $sel_cycle; ?>">
            <button type="submit" class="btn-sm-del"><i class="fas fa-trash mr-1"></i> Delete</button>
          </form>
        </div>
      </div>
    <?php endforeach; endif; ?>
  </div>

  <!-- Employee Recert Status -->
  <?php if (!empty($recert_employee_status)): ?>
  <div class="card-box" id="table2FilterBar" style="margin-bottom:14px;">
    <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Employees</h5>
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
        <input type="text" id="t2-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Due Date From</label>
        <input type="date" id="t2-from" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Due Date To</label>
        <input type="date" id="t2-to" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div>
        <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetT2Filters()"><i class="fas fa-redo mr-1"></i> Reset</button>
      </div>
      <div style="display:flex;gap:8px;">
        <button type="button" class="btn btn-success btn-sm" onclick="window.t2 && window.t2.button(0).trigger();"><i class="fas fa-file-excel mr-1"></i> Excel</button>
        <button type="button" class="btn btn-info btn-sm" onclick="window.t2 && window.t2.button(1).trigger();"><i class="fas fa-file-csv mr-1"></i> CSV</button>
      </div>
    </div>
  </div>
  <?php endif; ?>
  <div class="card-box" style="padding:0;overflow:hidden;">
    <div style="padding:18px 24px;border-bottom:2px solid #f1f5f9;display:flex;justify-content:space-between;align-items:center;">
      <h5 style="margin:0;font-weight:800;color:var(--navy);"><i class="fas fa-users mr-2"></i>Employee Recertification Status</h5>
      <span style="font-size:12px;color:#64748b;"><?php echo count($recert_employee_status); ?> certified employees</span>
    </div>
    <?php if (empty($recert_employee_status)): ?>
      <div class="empty-hint"><i class="fas fa-users fa-2x mb-2"></i><p>No certified employees found for this filter.</p></div>
    <?php else: ?>
    <div style="overflow-x:auto;">
      <table class="perf-table" id="table2">
        <thead>
          <tr>
            <th>Employee</th>
            <th>Cycle</th>
            <th>Due Date</th>
            <th>Attempts Used</th>
            <th>Last Score</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($recert_employee_status as $rs): ?>
          <tr data-empname="<?php echo htmlspecialchars(strtolower($rs['emp_name'] ?? '')); ?>" data-startdate="<?php echo !empty($rs['due_date']) ? date('Y-m-d', strtotime($rs['due_date'])) : ''; ?>">
            <td><div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($rs['emp_name']); ?></div></td>
            <td><span style="font-weight:800;color:var(--blue);">Cycle <?php echo $rs['cycle_number']; ?></span></td>
            <td><?php echo date('d M Y', strtotime($rs['due_date'])); ?></td>
            <td><?php echo $rs['attempts_used']; ?> / <?php echo $rs['max_attempts']; ?></td>
            <td><?php echo $rs['last_pct'] !== null ? number_format($rs['last_pct'], 1).'%' : '  '; ?></td>
            <td>
              <?php if (!$rs['is_configured']): ?>
                <span class="recert-status-badge ok" style="background:#f1f5f9;color:#64748b;border:1px solid #cbd5e1;"><i class="fas fa-cog"></i> Not Configured</span>
              <?php elseif ($rs['is_failed']): ?>
                <span class="recert-status-badge failed"><i class="fas fa-times-circle"></i> Failed</span>
              <?php elseif ($rs['is_passed_this_cycle']): ?>
                <span class="recert-status-badge passed"><i class="fas fa-check-circle"></i> Passed</span>
              <?php elseif ($rs['is_due']): ?>
                <span class="recert-status-badge due"><i class="fas fa-clock"></i> Due Soon</span>
              <?php else: ?>
                <span class="recert-status-badge ok"><i class="fas fa-shield-alt"></i> On Track</span>
              <?php endif; ?>
            </td>
            <td>
              <?php if ($rs['is_failed']): ?>
              <form method="POST" style="display:inline;" onsubmit="confirmOnSubmit(event, 'Reset attempts for Cycle <?php echo $rs['cycle_number']; ?>? Employee can retake the test.')">
                <input type="hidden" name="action" value="reset_recert_attempts">
                <input type="hidden" name="employee_id" value="<?php echo $rs['employee_id']; ?>">
                <input type="hidden" name="department_id" value="<?php echo $rs['department_id']; ?>">
                <input type="hidden" name="position_id" value="<?php echo $rs['position_id']; ?>">
                <input type="hidden" name="cycle_number" value="<?php echo $rs['cycle_number']; ?>">
                <button type="submit" class="btn btn-sm btn-warning" style="font-size:11px;font-weight:700;"><i class="fas fa-redo mr-1"></i> Reset</button>
              </form>
              <?php else: ?>
                <?php if ($rs['is_due']): ?>
                <form method="POST" style="display:inline;" onsubmit="confirmOnSubmit(event, 'Send a Recertification reminder ticket to this employee?')">
                  <input type="hidden" name="action" value="send_recert_ticket">
                  <input type="hidden" name="employee_id" value="<?php echo $rs['employee_id']; ?>">
                  <input type="hidden" name="department_id" value="<?php echo $rs['department_id']; ?>">
                  <input type="hidden" name="position_id" value="<?php echo $rs['position_id']; ?>">
                  <input type="hidden" name="cycle_number" value="<?php echo $rs['cycle_number']; ?>">
                  <button type="submit" class="btn btn-sm btn-primary" style="font-size:11px;font-weight:700;margin-right:4px;"><i class="fas fa-bell mr-1"></i> Notify</button>
                </form>
                <?php endif; ?>
              <button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;"
                onclick="openUnifiedViewModal(<?php echo $rs['employee_id']; ?>, <?php echo $rs['department_id']; ?>, <?php echo $rs['position_id']; ?>, 'recert', <?php echo $rs['cycle_number']; ?>, '<?php echo htmlspecialchars(addslashes($rs['emp_name'])); ?>', '<?php echo htmlspecialchars(addslashes($sel_dept_name)); ?>', '<?php echo htmlspecialchars(addslashes($sel_pos_title)); ?>')">
                <i class="fas fa-eye mr-1"></i> View</button>
              <?php endif; ?>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>

  <?php endif; ?>
</div>

<!-- ======================= TAB: CROSS TRAINING ======================= -->
<div id="tab-cross_training" class="tab-panel" style="display:<?php echo $active_tab=='cross_training'?'block':'none'; ?>">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h5 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-exchange-alt mr-2 text-info"></i>Cross Training Assignments</h5>
    <button class="btn-add" data-toggle="modal" data-target="#initiateCTModal"><i class="fas fa-plus mr-1"></i> Initiate Cross Training</button>
  </div>

  <?php if (!empty($ct_chains)): ?>
  <div class="card-box">
    <h5 style="margin-bottom:16px;"><i class="fas fa-route mr-2 text-info"></i>Employee Career Path (Cross Training Chains)</h5>
    <?php foreach ($ct_chains as $eid => $chain): ?>
      <div style="border:1.5px solid #e0e7ff;border-radius:10px;padding:16px 18px;margin-bottom:14px;">
        <div style="font-weight:800;color:var(--navy);margin-bottom:10px;"><i class="fas fa-user mr-1"></i><?php echo htmlspecialchars($chain['emp_name']); ?></div>
        <div style="display:flex;align-items:center;flex-wrap:wrap;gap:8px;">
          <?php foreach ($chain['hops'] as $i => $hop): ?>
            <?php if ($i === 0): ?>
              <span style="padding:6px 14px;border-radius:20px;font-size:12px;font-weight:700;background:#f1f5f9;color:#475569;">
                <?php echo htmlspecialchars($hop['from_dept_name'] ?? 'N/A'); ?><?php echo !empty($hop['from_pos_name']) ? ' ('.htmlspecialchars($hop['from_pos_name']).')' : ''; ?>
              </span>
              <i class="fas fa-long-arrow-alt-right" style="color:#94a3b8;"></i>
            <?php endif; ?>
            <span style="padding:6px 14px;border-radius:20px;font-size:12px;font-weight:700;
              <?php echo $hop['status']==='completed' ? 'background:#d1fae5;color:#065f46;' : ($hop['status']==='cancelled' ? 'background:#f1f5f9;color:#94a3b8;text-decoration:line-through;' : 'background:#dbeafe;color:#1e40af;'); ?>">
              <?php echo htmlspecialchars($hop['to_dept_name'] ?? 'N/A'); ?><?php echo !empty($hop['to_pos_name']) ? ' ('.htmlspecialchars($hop['to_pos_name']).')' : ''; ?>
              <?php if ($hop['status']==='completed'): ?><i class="fas fa-check-circle ml-1"></i><?php elseif($hop['status']==='active'): ?><i class="fas fa-spinner fa-spin ml-1"></i><?php else: ?><i class="fas fa-times-circle ml-1"></i><?php endif; ?>
            </span>
            <?php if ($i < count($chain['hops']) - 1): ?>
              <i class="fas fa-long-arrow-alt-right" style="color:#94a3b8;"></i>
            <?php endif; ?>
          <?php endforeach; ?>
        </div>
        <div style="font-size:11px;color:#94a3b8;margin-top:8px;">
          <?php echo count($chain['hops']); ?> transfer<?php echo count($chain['hops'])>1?'s':''; ?> recorded
          <?php $lastHop = end($chain['hops']); if ($lastHop['status']==='completed'): ?>
            &nbsp;|&nbsp; Current: <strong style="color:#065f46;"><?php echo htmlspecialchars($lastHop['to_dept_name'] ?? ''); ?></strong>
          <?php endif; ?>
        </div>
      </div>
    <?php endforeach; ?>
  </div>
  <?php endif; ?>

  <?php if (empty($cross_training_records)): ?>
    <div class="card-box"><div class="empty-hint"><i class="fas fa-exchange-alt fa-2x mb-2"></i><p>No cross training assignments yet.</p></div></div>
  <?php else: ?>
  <div class="card-box" id="ctFilterBar" style="margin-bottom:14px;">
    <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Assignments</h5>
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
        <input type="text" id="ct3-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Department (To)</label>
        <select id="ct3-dept" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Departments</option>
          <?php foreach ($departments as $d): ?><option value="<?php echo htmlspecialchars($d['name']); ?>"><?php echo htmlspecialchars($d['name']); ?></option><?php endforeach; ?>
        </select>
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Position (To)</label>
        <select id="ct3-pos" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Positions</option>
          <?php
          $all_pos_q = mysqli_query($con, "SELECT DISTINCT title FROM hr_positions ORDER BY title ASC");
          if ($all_pos_q) while ($pr = mysqli_fetch_assoc($all_pos_q)): ?>
            <option value="<?php echo htmlspecialchars($pr['title']); ?>"><?php echo htmlspecialchars($pr['title']); ?></option>
          <?php endwhile; ?>
        </select>
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date From</label>
        <input type="date" id="ct3-from" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date To</label>
        <input type="date" id="ct3-to" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div>
        <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetCT3Filters()"><i class="fas fa-redo mr-1"></i> Reset</button>
      </div>
      <div style="display:flex;gap:8px;">
        <button type="button" class="btn btn-success btn-sm" onclick="window.t3 && window.t3.button(0).trigger();"><i class="fas fa-file-excel mr-1"></i> Excel</button>
        <button type="button" class="btn btn-info btn-sm" onclick="window.t3 && window.t3.button(1).trigger();"><i class="fas fa-file-csv mr-1"></i> CSV</button>
      </div>
    </div>
  </div>
  <div class="card-box" style="padding:0;overflow:hidden;">
    <div style="overflow-x:auto;">
      <table class="perf-table" id="table3">
        <thead>
          <tr>
            <th>Employee</th>
            <th>From</th>
            <th>To</th>
            <th>Start Date</th>
            <th>Current Stage</th>
            <th>Status</th>
            <th>Initiated By</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($cross_training_records as $ct): ?>
          <tr data-empname="<?php echo htmlspecialchars(strtolower($ct['emp_name'] ?? '')); ?>" data-dept="<?php echo htmlspecialchars($ct['to_dept_name'] ?? ''); ?>" data-pos="<?php echo htmlspecialchars($ct['to_pos_name'] ?? ''); ?>" data-startdate="<?php echo $ct['start_date'] ? date('Y-m-d', strtotime($ct['start_date'])) : ''; ?>">
            <td><div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($ct['emp_name'] ?? ''); ?></div></td>
            <td>
              <div style="font-size:12px;font-weight:700;color:#334155;"><?php echo htmlspecialchars($ct['from_dept_name'] ?? '  '); ?></div>
              <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($ct['from_pos_name'] ?? 'All'); ?></div>
            </td>
            <td>
              <div style="font-size:12px;font-weight:700;color:#334155;"><?php echo htmlspecialchars($ct['to_dept_name'] ?? '  '); ?></div>
              <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($ct['to_pos_name'] ?? 'All'); ?></div>
            </td>
            <td><?php echo $ct['start_date'] ? date('d M Y', strtotime($ct['start_date'])) : '  '; ?></td>
            <td>
              <?php $stage = $ct['current_stage'] ?? 'training'; ?>
              <span class="ct-stage-badge <?php echo $stage; ?>">
                <?php $sl = ['training'=>'Training','training_test'=>'Training Test','oje_reading'=>'OJE Reading','oje_test'=>'OJE Test','certified'=>'Certified','failed'=>'Failed']; echo $sl[$stage] ?? $stage; ?>
              </span>
            </td>
            <td><span class="status-badge-ct <?php echo $ct['status']; ?>"><?php echo ucfirst($ct['status']); ?></span></td>
            <td style="font-size:12px;color:#64748b;"><?php echo htmlspecialchars($ct['initiated_by'] ?? ''); ?></td>
            <td>
              <div class="d-flex gap-2" style="gap:6px;">
                <button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;"
                  onclick="openUnifiedViewModal(<?php echo $ct['employee_id']; ?>, <?php echo $ct['to_dept_id']; ?>, <?php echo $ct['to_pos_id']; ?>, 'cross_training', 0, '<?php echo htmlspecialchars(addslashes($ct['emp_name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($ct['from_dept_name'])); ?> â†’ <?php echo htmlspecialchars(addslashes($ct['to_dept_name'])); ?>', '<?php echo htmlspecialchars(addslashes($ct['to_pos_name'] ?? '')); ?>')">
                  <i class="fas fa-eye mr-1"></i> View
                </button>
                <?php if ($ct['status'] == 'active'): ?>
                <form method="POST" style="display:inline;" onsubmit="confirmOnSubmit(event, 'Cancel this cross training assignment?')">
                  <input type="hidden" name="action" value="cancel_cross_training">
                  <input type="hidden" name="id" value="<?php echo $ct['id']; ?>">
                  <button type="submit" class="btn btn-sm btn-danger" style="font-size:11px;font-weight:700;"><i class="fas fa-times mr-1"></i> Cancel</button>
                </form>
                <?php endif; ?>
              </div>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
  <?php endif; ?>
</div>

<!-- ======================= TAB: HISTORY & ANALYTICS ======================= -->
<div id="tab-history" class="tab-panel" style="display:<?php echo $active_tab=='history'?'block':'none'; ?>">

  <!-- Analytics Charts -->
  <div class="card-box">
    <h5 style="margin-bottom:18px;"><i class="fas fa-chart-pie mr-2"></i>Analytics Overview</h5>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:24px;align-items:start;">
      <div style="text-align:center;">
        <div style="font-size:12px;font-weight:800;color:var(--navy);text-transform:uppercase;margin-bottom:8px;">Overall Status Distribution</div>
        <div style="position:relative; height:240px; width:100%; display:flex; justify-content:center;">
          <canvas id="combinedPieChart"></canvas>
        </div>
      </div>
      <div style="text-align:center;">
        <div style="font-size:12px;font-weight:800;color:var(--navy);text-transform:uppercase;margin-bottom:8px;">Organization Totals</div>
        <div style="position:relative; height:240px; width:100%; display:flex; justify-content:center;">
          <canvas id="orgBarChart"></canvas>
        </div>
      </div>
    </div>
  </div>

  <?php if (!empty($history_employees)): ?>
  <div class="card-box" id="table4FilterBar" style="margin-bottom:14px;">
    <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Employees</h5>
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
        <input type="text" id="t4-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Department</label>
        <select id="t4-dept" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Departments</option>
          <?php foreach ($departments as $d): ?><option value="<?php echo htmlspecialchars($d['name']); ?>"><?php echo htmlspecialchars($d['name']); ?></option><?php endforeach; ?>
        </select>
      </div>
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Position</label>
        <select id="t4-pos" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Positions</option>
          <?php
          $all_pos_t4 = mysqli_query($con, "SELECT DISTINCT title FROM hr_positions ORDER BY title ASC");
          if ($all_pos_t4) while ($pr = mysqli_fetch_assoc($all_pos_t4)): ?>
            <option value="<?php echo htmlspecialchars($pr['title']); ?>"><?php echo htmlspecialchars($pr['title']); ?></option>
          <?php endwhile; ?>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Certification Status</label>
        <select id="t4-cert" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="yes">Certified</option>
          <option value="no">Not Certified</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Training Test</label>
        <select id="t4-trainingtaken" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="yes">Taken</option>
          <option value="no">Not Taken</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Training Result</label>
        <select id="t4-trainingresult" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="pass">Pass (≥95%)</option>
          <option value="fail">Fail (&lt;95%)</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">OJE Test</label>
        <select id="t4-ojetaken" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="yes">Taken</option>
          <option value="no">Not Taken</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">OJE Result</label>
        <select id="t4-ojeresult" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="pass">Pass (≥95%)</option>
          <option value="fail">Fail (&lt;95%)</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Recertification</label>
        <select id="t4-hasrecert" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="yes">Has Passed Recert(s)</option>
          <option value="no">None Passed</option>
        </select>
      </div>
      <div style="min-width:170px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Cross Training</label>
        <select id="t4-hasct" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All</option>
          <option value="yes">Has Cross Training</option>
          <option value="no">None</option>
        </select>
      </div>
      <div style="min-width:120px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Overall % Min</label>
        <input type="number" id="t4-overall-min" min="0" max="100" placeholder="0" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:120px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Overall % Max</label>
        <input type="number" id="t4-overall-max" min="0" max="100" placeholder="100" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div>
        <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetT4Filters()"><i class="fas fa-redo mr-1"></i> Reset</button>
      </div>
      <div style="display:flex;gap:8px;">
        <button type="button" class="btn btn-success btn-sm" onclick="exportTable4('excel');"><i class="fas fa-file-excel mr-1"></i> Excel</button>
        <button type="button" class="btn btn-info btn-sm" onclick="exportTable4('csv');"><i class="fas fa-file-csv mr-1"></i> CSV</button>
      </div>
    </div>
  </div>
  <?php endif; ?>
  <div class="card-box" style="padding:0;overflow:hidden;">
    <div style="padding:18px 24px;border-bottom:2px solid #f1f5f9;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">
      <h5 style="margin:0;font-weight:800;color:var(--navy);"><i class="fas fa-history mr-2"></i>Employee History & Analytics</h5>
      <span style="font-size:12px;color:#64748b;" id="table4LiveCount"><?php echo count($history_employees); ?> employees Â· sorted by overall performance</span>
    </div>
    <?php if (empty($history_employees)): ?>
      <div class="empty-hint"><i class="fas fa-users fa-2x mb-2"></i><p>No employee history found for this filter.</p></div>
    <?php else: ?>
    <div style="overflow-x:auto;">
      <table class="perf-table" id="table4">
        <thead><tr>
          <th>#</th><th>Employee</th><th>Training Completed</th><th>OJE Completed</th>
          <th>Training Test</th><th>OJE Test</th><th>Recerts Passed</th><th>Cross Trainings</th>
          <th>Certified</th><th>Overall %</th><th>Actions</th>
        </tr></thead>
        <tbody>
        <?php foreach ($history_employees as $idx => $he): 
            $t4_training_taken = $he['training_attempts'] > 0 ? 'yes' : 'no';
            $t4_oje_taken = $he['oje_attempts'] > 0 ? 'yes' : 'no';
            $t4_training_result = $he['training_attempts'] > 0 ? ($he['training_best_pct'] >= 95 ? 'pass' : 'fail') : '';
            $t4_oje_result = $he['oje_attempts'] > 0 ? ($he['oje_best_pct'] >= 95 ? 'pass' : 'fail') : '';
            $t4_has_ct = $he['ct_total'] > 0 ? 'yes' : 'no';
            $t4_has_recert = $he['recert_passed'] > 0 ? 'yes' : 'no';
            $t4_overall = $he['overall_pct'] !== null ? round($he['overall_pct'], 1) : '';
        ?>
          <tr data-empname="<?php echo htmlspecialchars(strtolower($he['emp_name'] ?? '')); ?>" data-dept="<?php echo htmlspecialchars($he['department'] ?? ''); ?>" data-pos="<?php echo htmlspecialchars($he['position'] ?? ''); ?>" data-certified="<?php echo $he['certified_count'] > 0 ? 'yes' : 'no'; ?>" data-trainingtaken="<?php echo $t4_training_taken; ?>" data-trainingresult="<?php echo $t4_training_result; ?>" data-ojetaken="<?php echo $t4_oje_taken; ?>" data-ojeresult="<?php echo $t4_oje_result; ?>" data-hasct="<?php echo $t4_has_ct; ?>" data-hasrecert="<?php echo $t4_has_recert; ?>" data-overall="<?php echo $t4_overall; ?>">
            <td>
              <?php if ($idx==0): ?><i class="fas fa-trophy" style="color:#f59e0b;"></i>
              <?php elseif ($idx==1): ?><i class="fas fa-medal" style="color:#94a3b8;"></i>
              <?php elseif ($idx==2): ?><i class="fas fa-medal" style="color:#b45309;"></i>
              <?php else: echo $idx+1; endif; ?>
            </td>
            <td><div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($he['emp_name']); ?></div>
                <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($he['department']); ?> Â· <?php echo htmlspecialchars($he['position']); ?></div></td>
            <td><span style="font-weight:700;color:#16a34a;"><?php echo $he['training_completed']; ?></span> items</td>
            <td><span style="font-weight:700;color:#2563eb;"><?php echo $he['oje_completed']; ?></span> items</td>
            <td><?php if ($he['training_attempts']>0): ?><?php echo number_format($he['training_best_pct'],1); ?>% <span style="color:#94a3b8;font-size:11px;">(<?php echo $he['training_attempts']; ?> att.)</span><?php else: ?><span style="color:#94a3b8;font-size:12px;">Not taken</span><?php endif; ?></td>
            <td><?php if ($he['oje_attempts']>0): ?><?php echo number_format($he['oje_best_pct'],1); ?>% <span style="color:#94a3b8;font-size:11px;">(<?php echo $he['oje_attempts']; ?> att.)</span><?php else: ?><span style="color:#94a3b8;font-size:12px;">Not taken</span><?php endif; ?></td>
            <td><span style="font-weight:700;color:#5b21b6;"><?php echo $he['recert_passed']; ?></span></td>
            <td><span style="font-weight:700;"><?php echo $he['ct_total']; ?></span> (<?php echo $he['ct_active']; ?> active)</td>
            <td><?php if ($he['certified_count']>0): ?><span style="color:#065f46;font-weight:800;font-size:12px;"><i class="fas fa-certificate mr-1"></i><?php echo $he['certified_count']; ?></span><?php else: ?><span style="color:#94a3b8;font-size:12px;">  </span><?php endif; ?></td>
            <td><?php echo $he['overall_pct']!==null ? '<strong>'.number_format($he['overall_pct'],1).'%</strong>' : '  '; ?></td>
            <td><button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;" onclick="toggleHistoryDetail(<?php echo $he['employee_id']; ?>)"><i class="fas fa-chevron-down mr-1"></i> Full History</button></td>
          </tr>
          <tr id="history_detail_row_<?php echo $he['employee_id']; ?>" class="history-detail-row" style="display:none;">
            <td colspan="11" style="background:#f8fafc;padding:20px;">
              <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-book-open mr-1"></i>Training Materials Completed</h6>
                  <?php if (empty($he['detail']['training_items'])): ?><p class="text-muted small">No items completed yet.</p>
                  <?php else: foreach ($he['detail']['training_items'] as $ti): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;"><i class="fas fa-check text-success mr-1"></i><?php echo htmlspecialchars($ti['item_title']); ?> <span style="color:#94a3b8;">   <?php echo htmlspecialchars($ti['heading_name']); ?> Â· <?php echo date('d M Y', strtotime($ti['completed_at'])); ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-briefcase mr-1"></i>OJE Content Completed</h6>
                  <?php if (empty($he['detail']['oje_items'])): ?><p class="text-muted small">No items completed yet.</p>
                  <?php else: foreach ($he['detail']['oje_items'] as $oi): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;"><i class="fas fa-check text-success mr-1"></i><?php echo htmlspecialchars($oi['item_title']); ?> <span style="color:#94a3b8;">   <?php echo htmlspecialchars($oi['heading_name']); ?> Â· <?php echo date('d M Y', strtotime($oi['completed_at'])); ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-question-circle mr-1"></i>Training Test Attempts</h6>
                  <?php if (empty($he['detail']['training_attempts_list'])): ?><p class="text-muted small">No attempts yet.</p>
                  <?php else: foreach ($he['detail']['training_attempts_list'] as $ta): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;">Attempt <?php echo $ta['attempt_number']; ?>: <strong style="color:<?php echo $ta['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($ta['percentage'],1); ?>%</strong> <?php echo $ta['passed']?'(Passed)':'(Failed)'; ?> <span style="color:#94a3b8;"> Â· <?php echo date('d M Y', strtotime($ta['attempted_at'])); ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-clipboard-check mr-1"></i>OJE Test Attempts</h6>
                  <?php if (empty($he['detail']['oje_attempts_list'])): ?><p class="text-muted small">No attempts yet.</p>
                  <?php else: foreach ($he['detail']['oje_attempts_list'] as $oa): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;">Attempt <?php echo $oa['attempt_number']; ?>: <strong style="color:<?php echo $oa['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($oa['percentage'],1); ?>%</strong> <?php echo $oa['passed']?'(Passed)':'(Failed)'; ?> <span style="color:#94a3b8;"> Â· <?php echo date('d M Y', strtotime($oa['attempted_at'])); ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-sync-alt mr-1"></i>Recertification Cycles</h6>
                  <?php if (empty($he['detail']['recert_list'])): ?><p class="text-muted small">No recertification attempts yet.</p>
                  <?php else: foreach ($he['detail']['recert_list'] as $rc): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;">Cycle <?php echo $rc['cycle_number']; ?>, Attempt <?php echo $rc['attempt_number']; ?>: <strong style="color:<?php echo $rc['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($rc['percentage'],1); ?>%</strong> <?php echo $rc['passed']?'(Passed)':'(Failed)'; ?> <span style="color:#94a3b8;"> Â· <?php echo date('d M Y', strtotime($rc['attempted_at'])); ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
                <div>
                  <h6 style="font-weight:800;color:var(--navy);font-size:12px;text-transform:uppercase;"><i class="fas fa-exchange-alt mr-1"></i>Cross Training Records</h6>
                  <?php if (empty($he['detail']['ct_list'])): ?><p class="text-muted small">No cross training records.</p>
                  <?php else: foreach ($he['detail']['ct_list'] as $cl): ?>
                    <div style="font-size:12px;padding:5px 0;border-bottom:1px solid #eee;"><?php echo htmlspecialchars($cl['from_dept_name'] ?? '  '); ?> â†’ <strong><?php echo htmlspecialchars($cl['to_dept_name'] ?? '  '); ?> <?php echo htmlspecialchars($cl['to_pos_name'] ?? ''); ?></strong> <span class="status-badge-ct <?php echo $cl['status']; ?>" style="margin-left:6px;"><?php echo ucfirst($cl['status']); ?></span> <span style="color:#94a3b8;"> Â· Started <?php echo $cl['start_date']?date('d M Y', strtotime($cl['start_date'])):'  '; ?></span></div>
                  <?php endforeach; endif; ?>
                </div>
              </div>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
</div>

</div>

<!-- ======================= MODALS ======================= -->

<!-- History View Modal -->
<div class="modal fade" id="viewHistoryModal" tabindex="-1">
  <div class="modal-dialog modal-xl" style="max-width:90%; height:90vh;">
    <div class="modal-content" style="height:100%; border-radius:16px; border:none; overflow:hidden;">
      <div class="modal-header" style="background:var(--navy); color:#fff; padding:15px 25px;">
        <h5 class="modal-title" style="font-weight:800; font-size:18px;"><i class="fas fa-history mr-2"></i>Employee Progress & History</h5>
        <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="padding:0; height:calc(100% - 60px);">
        <iframe id="historyIframe" src="" style="width:100%; height:100%; border:none;"></iframe>
      </div>
    </div>
  </div>
</div>

<!-- Import Questions Modal -->
<div class="modal fade" id="importQuestionsModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="import_questions">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="cycle_number" value="<?php echo $sel_cycle; ?>">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-file-import mr-2"></i>Import Recertification Questions</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p style="font-size:13px;color:#64748b;margin-bottom:15px;">Please use the standard CSV template. Make sure to download the template first if you haven't.</p>
        <div class="mb-3 text-center">
          <a href="?action=download_template" class="btn btn-sm btn-outline-primary" style="font-weight:700;"><i class="fas fa-download mr-1"></i> Download CSV Template</a>
        </div>
        <div class="form-group">
          <label style="font-weight:700;font-size:12px;color:var(--navy);">Select CSV File</label>
          <input type="file" name="csv_file" accept=".csv" class="form-control" style="padding:6px;height:auto;" required>
        </div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Import File</button></div>
    </form>
  </div></div>
</div>

<!-- Add Recert Question Modal -->
<div class="modal fade" id="addRecertQModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="add_recert_question">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="cycle_number" value="<?php echo $sel_cycle; ?>">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-plus mr-2"></i>Add Recertification Question</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Question Text</label><textarea name="question_text" rows="3" required placeholder="Enter your question..."></textarea></div>
        <label style="font-weight:700;font-size:12px;color:var(--navy);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;display:block;">Answer Options & Points</label>
        <div class="option-builder">
          <div class="option-builder-row option-builder-header"><span>Option</span><span>Points</span><span>Correct?</span><span></span></div>
          <div id="recertOptContainer">
            <?php foreach ([['Yes',10],['Partially',5],['No',0]] as $i => $o): ?>
            <div class="option-builder-row" id="ropt_<?php echo $i; ?>">
              <input type="text" name="options[]" value="<?php echo $o[0]; ?>" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>
              <input type="number" name="points[]" value="<?php echo $o[1]; ?>" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">
              <input type="radio" name="correct_option" value="<?php echo $i; ?>" <?php echo $i==0?'checked':''; ?> style="width:18px;height:18px;">
              <button type="button" onclick="removeROpt(<?php echo $i; ?>)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button>
            </div>
            <?php endforeach; ?>
          </div>
        </div>
        <button type="button" onclick="addROpt()" style="margin-top:10px;background:#f0f4f8;border:1.5px dashed #cbd5e1;border-radius:8px;padding:8px 16px;font-size:13px;font-weight:700;cursor:pointer;width:100%;color:#64748b;">+ Add Option</button>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Question</button></div>
    </form>
  </div></div>
</div>

<!-- Edit Recert Question Modal -->
<div class="modal fade" id="editRecertQModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="edit_recert_question">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="cycle_number" value="<?php echo $sel_cycle; ?>">
      <input type="hidden" name="question_id" id="erq_id">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-edit mr-2"></i>Edit Recertification Question</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Question Text</label><textarea name="question_text" id="erq_text" rows="3" required></textarea></div>
        <label style="font-weight:700;font-size:12px;color:var(--navy);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;display:block;">Answer Options & Points</label>
        <div class="option-builder">
          <div class="option-builder-row option-builder-header"><span>Option</span><span>Points</span><span>Correct?</span><span></span></div>
          <div id="editRecertOptContainer"></div>
        </div>
        <button type="button" onclick="addEditROpt()" style="margin-top:10px;background:#f0f4f8;border:1.5px dashed #cbd5e1;border-radius:8px;padding:8px 16px;font-size:13px;font-weight:700;cursor:pointer;width:100%;color:#64748b;">+ Add Option</button>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Changes</button></div>
    </form>
  </div></div>
</div>

<!-- Initiate Cross Training Modal -->
<div class="modal fade" id="initiateCTModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="initiate_cross_training">
      <div class="modal-header" style="background:var(--navy);border-radius:8px 8px 0 0;">
        <h5 class="modal-title" style="color:#fff;font-weight:800;"><i class="fas fa-exchange-alt mr-2"></i>Initiate Cross Training</h5>
        <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px; min-height:400px;">
        <div class="form-field">
          <label>Employee</label>
          <select name="employee_id" required>
            <option value="">-- Select Employee --</option>
            <?php foreach ($all_employees as $emp): ?>
            <option value="<?php echo $emp['id']; ?>"><?php echo htmlspecialchars($emp['name']); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="config-grid">
          <div class="form-field">
            <label>Target Department</label>
            <select name="to_dept_id" id="ct_to_dept" onchange="fetchCTPositions(this.value)" required>
              <option value="">-- Select Department --</option>
              <?php foreach ($departments as $d): ?>
              <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="form-field">
            <label>Target Position</label>
            <select name="to_pos_id" id="ct_to_pos">
              <option value="0">All Positions</option>
            </select>
          </div>
        </div>
        <div class="form-field">
          <label>Start Date</label>
          <input type="date" name="start_date" required min="<?php echo date('Y-m-d'); ?>">
        </div>
        <div class="form-field">
          <label>Notes (optional)</label>
          <textarea name="notes" rows="2" placeholder="Any additional notes..."></textarea>
        </div>
        <div style="padding:12px 14px;background:#fef3c7;border:1px solid #fcd34d;border-radius:8px;font-size:12px;font-weight:600;color:#92400e;">
          <i class="fas fa-info-circle mr-1"></i> The employee will be assigned the full Training â†’ Test â†’ OJE â†’ Test â†’ Certified for the target role. Their original certification remains unaffected. - notification ticket will be raised automatically.
        </div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary" style="font-weight:700;"><i class="fas fa-paper-plane mr-1"></i> Initiate</button></div>
    </form>
  </div></div>
</div>

<!-- New Recert Configuration Modal -->
<div class="modal fade" id="newRecertConfigModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:12px; border:none; box-shadow:0 10px 30px rgba(0,0,0,0.1);">
    <div class="modal-header" style="background:var(--navy); color:white; border-radius:12px 12px 0 0;">
      <h5 class="modal-title" style="font-weight:800;"><i class="fas fa-plus mr-2"></i>New Configuration</h5>
      <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px; min-height:350px;">
      <p style="font-size:14px; color:#64748b; margin-bottom:20px;">Select a department and position to start configuring their recertification cycles.</p>
      <div class="form-field">
        <label>Department</label>
        <select id="newRecertConfigDept" onchange="fetchPositionsForNewRecertConfig(this.value)">
          <option value="">-- Select Department --</option>
          <?php foreach($departments as $d): ?>
            <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
          <?php endforeach; ?>
        </select>
      </div>
      <div class="form-field">
        <label>Position</label>
        <select id="newRecertConfigPos">
          <option value="0">All Positions</option>
        </select>
      </div>
      <button type="button" class="btn btn-primary btn-block mt-3" style="font-weight:800; border-radius:8px; padding:12px;" onclick="goToNewRecertConfig()">Create Configuration</button>
    </div>
  </div></div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function fetchPositions(dept_id, target_sel_id) {
    let ps = document.getElementById(target_sel_id);
    ps.innerHTML = '<option value="0">All Positions</option>';
    if(dept_id) {
        $.get('hr-recert-crosstraining.php', { get_positions: 1, dept_id: dept_id }, function(res) {
            try {
                var data = typeof res === 'string' ? JSON.parse(res) : res;
                data.forEach(function(p) {
                    ps.innerHTML += '<option value="'+p.id+'">'+p.title+'</option>';
                });
            } catch(e){}
        });
    }
}
function fetchPositionsForNewRecertConfig(dept_id) {
    fetchPositions(dept_id, 'newRecertConfigPos');
}
function fetchCTPositions(dept_id) {
    fetchPositions(dept_id, 'ct_to_pos');
}
function goToNewRecertConfig() {
    let d = document.getElementById('newRecertConfigDept').value;
    let p = document.getElementById('newRecertConfigPos').value;
    if(d) {
        window.location.href = '?tab=recertification&dept_id=' + d + '&pos_id=' + (p || 0);
    }
}
function openImportModal() {
  $('#importQuestionsModal').modal('show');
}
function toggleHistoryDetail(empId) {
  var row = document.getElementById('history_detail_row_'+empId);
  if (row) row.style.display = (row.style.display === 'none') ? 'table-row' : 'none';
}

// ---- TABLE 4 (History & Analytics) — custom filter + export ----
// Not run through DataTables since expand/collapse detail rows would break
// its row model; filtering/export are handled manually here instead.
document.addEventListener('DOMContentLoaded', function() {
    var t4 = document.getElementById('table4');
    if (!t4) return;

    function t4MainRows() {
        return Array.prototype.slice.call(t4.querySelectorAll('tbody tr:not(.history-detail-row)'));
    }

    function applyT4Filters() {
        var name = document.getElementById('t4-name').value.toLowerCase();
        var dept = document.getElementById('t4-dept').value;
        var pos = document.getElementById('t4-pos').value;
        var cert = document.getElementById('t4-cert').value;
        var trainingTaken = document.getElementById('t4-trainingtaken').value;
        var trainingResult = document.getElementById('t4-trainingresult').value;
        var ojeTaken = document.getElementById('t4-ojetaken').value;
        var ojeResult = document.getElementById('t4-ojeresult').value;
        var hasRecert = document.getElementById('t4-hasrecert').value;
        var hasCt = document.getElementById('t4-hasct').value;
        var overallMin = document.getElementById('t4-overall-min').value;
        var overallMax = document.getElementById('t4-overall-max').value;
        var visibleCount = 0;

        t4MainRows().forEach(function(row) {
            var match = true;
            var rName = row.getAttribute('data-empname') || '';
            var rDept = row.getAttribute('data-dept') || '';
            var rPos = row.getAttribute('data-pos') || '';
            var rCert = row.getAttribute('data-certified') || '';
            var rTrainingTaken = row.getAttribute('data-trainingtaken') || '';
            var rTrainingResult = row.getAttribute('data-trainingresult') || '';
            var rOjeTaken = row.getAttribute('data-ojetaken') || '';
            var rOjeResult = row.getAttribute('data-ojeresult') || '';
            var rHasRecert = row.getAttribute('data-hasrecert') || '';
            var rHasCt = row.getAttribute('data-hasct') || '';
            var rOverallStr = row.getAttribute('data-overall');
            var rOverall = rOverallStr !== '' && rOverallStr !== null ? parseFloat(rOverallStr) : null;

            if (name && rName.indexOf(name) === -1) match = false;
            if (dept && rDept !== dept) match = false;
            if (pos && rPos !== pos) match = false;
            if (cert && rCert !== cert) match = false;
            if (trainingTaken && rTrainingTaken !== trainingTaken) match = false;
            if (trainingResult && rTrainingResult !== trainingResult) match = false;
            if (ojeTaken && rOjeTaken !== ojeTaken) match = false;
            if (ojeResult && rOjeResult !== ojeResult) match = false;
            if (hasRecert && rHasRecert !== hasRecert) match = false;
            if (hasCt && rHasCt !== hasCt) match = false;
            if (overallMin !== '' && (rOverall === null || rOverall < parseFloat(overallMin))) match = false;
            if (overallMax !== '' && (rOverall === null || rOverall > parseFloat(overallMax))) match = false;

            row.style.display = match ? '' : 'none';
            var detailRow = row.nextElementSibling;
            if (detailRow && detailRow.classList.contains('history-detail-row')) {
                if (!match) detailRow.style.display = 'none';
            }
            if (match) visibleCount++;
        });

        var countEl = document.getElementById('table4LiveCount');
        if (countEl) countEl.textContent = visibleCount + ' employees Â· sorted by overall performance';
    }

    var t4TextFields = ['t4-name'];
    var t4ChangeFields = ['t4-dept','t4-pos','t4-cert','t4-trainingtaken','t4-trainingresult','t4-ojetaken','t4-ojeresult','t4-hasrecert','t4-hasct'];
    var t4NumberFields = ['t4-overall-min','t4-overall-max'];

    t4TextFields.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('keyup', applyT4Filters);
    });
    t4ChangeFields.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('change', applyT4Filters);
    });
    t4NumberFields.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('input', applyT4Filters);
    });

    window.resetT4Filters = function() {
        document.getElementById('t4-name').value = '';
        document.getElementById('t4-dept').value = '';
        document.getElementById('t4-pos').value = '';
        document.getElementById('t4-cert').value = '';
        document.getElementById('t4-trainingtaken').value = '';
        document.getElementById('t4-trainingresult').value = '';
        document.getElementById('t4-ojetaken').value = '';
        document.getElementById('t4-ojeresult').value = '';
        document.getElementById('t4-hasrecert').value = '';
        document.getElementById('t4-hasct').value = '';
        document.getElementById('t4-overall-min').value = '';
        document.getElementById('t4-overall-max').value = '';
        applyT4Filters();
    };

    window.exportTable4 = function(type) {
        var headerCells = t4.querySelectorAll('thead th');
        var headers = [];
        headerCells.forEach(function(th) {
            if (th.textContent.trim() !== 'Actions') headers.push(th.textContent.trim());
        });

        var csvRows = [headers.map(function(h) { return '"' + h.replace(/"/g,'""') + '"'; }).join(',')];

        t4MainRows().forEach(function(row) {
            if (row.style.display === 'none') return;
            var cells = row.querySelectorAll('td');
            var rowData = [];
            cells.forEach(function(td, idx) {
                if (idx === cells.length - 1) return; // skip Actions column
                var text = td.textContent.replace(/\s+/g,' ').trim();
                rowData.push('"' + text.replace(/"/g,'""') + '"');
            });
            csvRows.push(rowData.join(','));
        });

        var csvContent = csvRows.join('\n');
        var mime = type === 'excel' ? 'application/vnd.ms-excel' : 'text/csv';
        var ext = type === 'excel' ? 'xls' : 'csv';
        var blob = new Blob([csvContent], { type: mime });
        var link = document.createElement('a');
        link.href = window.URL.createObjectURL(blob);
        link.download = 'Employee_History_Analytics.' + ext;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };
});

// ---- Analytics Charts ----
document.addEventListener('DOMContentLoaded', function() {
  var pieCtx = document.getElementById('combinedPieChart');
  if (pieCtx) {
    new Chart(pieCtx, {
      type: 'pie',
      data: {
        labels: ['Certified', 'Not Certified', 'CT Active', 'CT Completed', 'CT Cancelled', 'Recert Passed', 'Recert Failed'],
        datasets: [{
          data: [
            <?php echo $cert_yes; ?>, <?php echo $cert_no; ?>,
            <?php echo $ct_active_total; ?>, <?php echo $ct_completed_total; ?>, <?php echo $ct_cancelled_total; ?>,
            <?php echo $recert_pass_total; ?>, <?php echo $recert_fail_total; ?>
          ],
          backgroundColor: ['#10b981', '#e2e8f0', '#1a3fc4', '#0ea5e9', '#94a3b8', '#16a34a', '#ef4444']
        }]
      },
      options: { maintainAspectRatio: false, plugins: { legend: { position: 'bottom', labels: { font: { size: 10 }, boxWidth: 12 } } } }
    });
  }

  var barCtx = document.getElementById('orgBarChart');
  if (barCtx) {
    new Chart(barCtx, {
      type: 'bar',
      data: {
        labels: ['Training Completed', 'OJE Completed', 'Recerts Passed', 'Cross Trainings', 'Certified'],
        datasets: [{
          data: [
            <?php echo $agg_training_completed; ?>, <?php echo $agg_oje_completed; ?>,
            <?php echo $agg_recert_passed; ?>, <?php echo $agg_ct_total; ?>, <?php echo $agg_certified_emps; ?>
          ],
          backgroundColor: ['#16a34a', '#2563eb', '#5b21b6', '#f59e0b', '#10b981']
        }]
      },
      options: {
        maintainAspectRatio: false,
        responsive: true,
        plugins: { legend: { display: false } },
        scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
      }
    });
  }
});
function switchTab(tab) {
  document.querySelectorAll('.tab-panel').forEach(p => p.style.display='none');
  document.querySelectorAll('.main-tab').forEach(t => t.classList.remove('active'));
  document.getElementById('tab-'+tab).style.display = 'block';
  event.currentTarget.classList.add('active');
  var url = new URL(window.location.href);
  url.searchParams.set('tab', tab);
  window.history.replaceState({}, '', url);
  document.querySelector('input[name="tab"]').value = tab;
}



// ---- Recert Question Options ----
var rOptCount = 3;
function addROpt() {
  var i = rOptCount++;
  document.getElementById('recertOptContainer').insertAdjacentHTML('beforeend',
    '<div class="option-builder-row" id="ropt_'+i+'">'+
    '<input type="text" name="options[]" placeholder="Option" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>'+
    '<input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">'+
    '<input type="radio" name="correct_option" value="'+i+'" style="width:18px;height:18px;">'+
    '<button type="button" onclick="removeROpt('+i+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button>'+
    '</div>');
}
function removeROpt(i) { var r = document.getElementById('ropt_'+i); if(r) r.remove(); }

function openAddRecertQModal() {
  document.getElementById('recertOptContainer').innerHTML = `
    <div class="option-builder-row" id="ropt_0"><input type="text" name="options[]" value="Yes" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required><input type="number" name="points[]" value="10" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;"><input type="radio" name="correct_option" value="0" checked style="width:18px;height:18px;"><button type="button" onclick="removeROpt(0)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button></div>
    <div class="option-builder-row" id="ropt_1"><input type="text" name="options[]" value="Partially" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required><input type="number" name="points[]" value="5" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;"><input type="radio" name="correct_option" value="1" style="width:18px;height:18px;"><button type="button" onclick="removeROpt(1)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button></div>
    <div class="option-builder-row" id="ropt_2"><input type="text" name="options[]" value="No" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required><input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;"><input type="radio" name="correct_option" value="2" style="width:18px;height:18px;"><button type="button" onclick="removeROpt(2)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button></div>`;
  rOptCount = 3;
  $('#addRecertQModal').modal('show');
}

var editROptCount = 0;
function openEditRecertQModal(q) {
  document.getElementById('erq_id').value = q.id;
  document.getElementById('erq_text').value = q.question_text;
  var html = '';
  editROptCount = 0;
  (q.options || []).forEach(function(opt, i) {
    var checked = (opt.is_correct == 1 || opt.is_correct === true) ? 'checked' : '';
    html += '<div class="option-builder-row" id="eropt_'+i+'">'+
      '<input type="text" name="options[]" value="'+opt.label.replace(/"/g,'&quot;')+'" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>'+
      '<input type="number" name="points[]" value="'+opt.points+'" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">'+
      '<input type="radio" name="correct_option" value="'+i+'" '+checked+' style="width:18px;height:18px;">'+
      '<button type="button" onclick="removeEditROpt('+i+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button>'+
      '</div>';
    editROptCount++;
  });
  document.getElementById('editRecertOptContainer').innerHTML = html;
  $('#editRecertQModal').modal('show');
}
function addEditROpt() {
  var i = editROptCount++;
  document.getElementById('editRecertOptContainer').insertAdjacentHTML('beforeend',
    '<div class="option-builder-row" id="eropt_'+i+'">'+
    '<input type="text" name="options[]" placeholder="Option" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>'+
    '<input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">'+
    '<input type="radio" name="correct_option" value="'+i+'" style="width:18px;height:18px;">'+
    '<button type="button" onclick="removeEditROpt('+i+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;">Ã—</button>'+
    '</div>');
}
function removeEditROpt(i) { var r = document.getElementById('eropt_'+i); if(r) r.remove(); }

function viewEmployeeHistory(url) {
  document.getElementById('historyIframe').src = url;
  $('#viewHistoryModal').modal('show');
}
</script>
<?php include("footer.php");

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
 ?>
<!-- CT View Modal -->
<div class="modal fade" id="ctViewModal" tabindex="-1" role="dialog" style="z-index:99999;">
  <div class="modal-dialog modal-xl" style="max-width:900px;">
    <div class="modal-content" style="border-radius:16px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.2);">
      <div class="modal-header" style="background:linear-gradient(135deg,#0f2557,#1a3fc4);border-radius:16px 16px 0 0;padding:20px 28px;">
        <div>
          <h5 class="modal-title" style="color:#fff;font-weight:800;margin:0;" id="ctModalTitle">Employee Progress</h5>
          <p id="ctModalSubtitle" style="color:rgba(255,255,255,0.65);font-size:12px;margin:4px 0 0;"></p>
        </div>
        <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="padding:28px;max-height:80vh;overflow-y:auto;" id="ctModalBody">
        <div class="text-center p-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i><p class="mt-2 text-muted">Loading...</p></div>
      </div>
    </div>
  </div>
</div>

<script>
function openUnifiedViewModal(empId, deptId, posId, context, cycle, empName, deptName, posName) {
  document.getElementById('ctModalTitle').innerText = empName + '  Progress';
  document.getElementById('ctModalSubtitle').innerText = deptName + (posName ? ' (' + posName + ')' : '');
  document.getElementById('ctModalBody').innerHTML = '<div class="text-center p-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i><p class="mt-2 text-muted">Loading...</p></div>';
  $('#ctViewModal').modal('show');

  $.get('hr-ct-view-ajax.php', {
    emp_id: empId, dept_id: deptId, pos_id: posId, context: context, cycle: cycle || 0
  }, function(html) {
    document.getElementById('ctModalBody').innerHTML = html;
  }).fail(function() {
    document.getElementById('ctModalBody').innerHTML = '<div class="alert alert-danger">Failed load data.</div>';
  });
}
</script>

<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script>
function downloadCTCert(empId) {
  var el = document.getElementById('ctCertCard_' + empId);
  if (!el) {
      alert("Certificate element not found.");
      return;
  }
  var originalStyle = el.style.cssText;
  el.style.maxHeight = 'none';
  el.style.overflow = 'visible';
  html2canvas(el, { scale: 2, useCORS: true, logging: false }).then(function(canvas) {
    el.style.cssText = originalStyle;
    var link = document.createElement('a');
    link.download = 'Certificate_of_Completion.png';
    link.href = canvas.toDataURL('image/png');
    link.click();
  }).catch(function(err) {
      alert("Error generating certificate image.");
      el.style.cssText = originalStyle;
  });
}
</script>

<!-- DataTables Scripts -->
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap4.min.css"/>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/buttons/2.3.6/css/buttons.bootstrap4.min.css"/>
<script type="text/javascript" src="https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap4.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/dataTables.buttons.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/buttons.bootstrap4.min.js"></script>
<script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.1.3/jszip.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/buttons.html5.min.js"></script>
<script>
$(document).ready(function() {
    var dtConfig = {
        "pageLength": 25,
        "dom": "<'row'<'col-sm-12'tr>>" +
               "<'row mt-3'<'col-sm-12 col-md-5'i><'col-sm-12 col-md-7'p>>",
        "buttons": [
            { extend: 'excelHtml5', className: 'btn btn-success btn-sm', text: '<i class="fas fa-file-excel mr-1"></i> Excel', exportOptions: { modifier: { search: 'applied' } } },
            { extend: 'csvHtml5', className: 'btn btn-info btn-sm', text: '<i class="fas fa-file-csv mr-1"></i> CSV', exportOptions: { modifier: { search: 'applied' } } }
        ]
    };
    if ($('#table1').length) { window.t1 = $('#table1').DataTable(dtConfig); }
    if ($('#table2').length) { window.t2 = $('#table2').DataTable(dtConfig); }
    if ($('#table3').length) { window.t3 = $('#table3').DataTable(dtConfig); }
    var t1 = window.t1, t2 = window.t2, t3 = window.t3;

    function inRange(dateStr, from, to) {
        if (!dateStr) return !(from || to);
        var d = new Date(dateStr);
        if (from && d < new Date(from)) return false;
        if (to && d > new Date(to)) return false;
        return true;
    }

    // ---- TABLE 3 (Cross Training) ----
    if (t3) {
        $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
            if (settings.nTable.id !== 'table3') return true;
            var $row = $(t3.row(dataIndex).node());
            var name = $('#ct3-name').val().toLowerCase();
            var dept = $('#ct3-dept').val();
            var pos = $('#ct3-pos').val();
            var from = $('#ct3-from').val();
            var to = $('#ct3-to').val();
            if (name && ($row.data('empname') || '').indexOf(name) === -1) return false;
            if (dept && $row.data('dept') !== dept) return false;
            if (pos && $row.data('pos') !== pos) return false;
            if (!inRange($row.data('startdate'), from, to)) return false;
            return true;
        });
        $('#ct3-name, #ct3-dept, #ct3-pos, #ct3-from, #ct3-to').on('keyup change', function() { t3.draw(); });
    }
    window.resetCT3Filters = function() {
        $('#ct3-name').val(''); $('#ct3-dept').val(''); $('#ct3-pos').val('');
        $('#ct3-from').val(''); $('#ct3-to').val('');
        if (t3) t3.draw();
    };

    // ---- TABLE 1 (All Employees Recert) ----
    if (t1) {
        $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
            if (settings.nTable.id !== 'table1') return true;
            var $row = $(t1.row(dataIndex).node());
            var name = $('#t1-name').val().toLowerCase();
            var dept = $('#t1-dept').val();
            var pos = $('#t1-pos').val();
            var from = $('#t1-from').val();
            var to = $('#t1-to').val();
            if (name && ($row.data('empname') || '').indexOf(name) === -1) return false;
            if (dept && $row.data('dept') !== dept) return false;
            if (pos && $row.data('pos') !== pos) return false;
            if (!inRange($row.data('startdate'), from, to)) return false;
            return true;
        });
        $('#t1-name, #t1-dept, #t1-pos, #t1-from, #t1-to').on('keyup change', function() { t1.draw(); });
        t1.on('draw', function() {
            $('#table1LiveCount').text(t1.rows({search:'applied'}).count() + ' certified employees found');
        });
    }
    window.resetT1Filters = function() {
        $('#t1-name').val(''); $('#t1-dept').val(''); $('#t1-pos').val('');
        $('#t1-from').val(''); $('#t1-to').val('');
        if (t1) t1.draw();
    };

    // ---- TABLE 2 (Employee Recert Status) ----
    if (t2) {
        $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
            if (settings.nTable.id !== 'table2') return true;
            var $row = $(t2.row(dataIndex).node());
            var name = $('#t2-name').val().toLowerCase();
            var from = $('#t2-from').val();
            var to = $('#t2-to').val();
            if (name && ($row.data('empname') || '').indexOf(name) === -1) return false;
            if (!inRange($row.data('startdate'), from, to)) return false;
            return true;
        });
        $('#t2-name, #t2-from, #t2-to').on('keyup change', function() { t2.draw(); });
    }
    window.resetT2Filters = function() {
        $('#t2-name').val(''); $('#t2-from').val(''); $('#t2-to').val('');
        if (t2) t2.draw();
    };
});
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
