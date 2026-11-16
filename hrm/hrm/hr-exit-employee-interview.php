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
mysqli_report(MYSQLI_REPORT_OFF);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

$con = conexion();
if (!$con) die("Database connection failed: " . mysqli_connect_error());

// --- ENSURE DATABASE TABLES EXIST & COLS ARE MIGRATED ---

// Table: hr_exit_rounds (Dynamic user-managed rounds)
$check_r_tbl = mysqli_query($con, "SHOW TABLES LIKE 'hr_exit_rounds'");
if ($check_r_tbl && mysqli_num_rows($check_r_tbl) == 0) {
    mysqli_query($con, "CREATE TABLE hr_exit_rounds (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        round_number INT(11) NOT NULL,
        round_name VARCHAR(255) NOT NULL,
        description TEXT DEFAULT NULL,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // Seed default rounds if newly created
    mysqli_query($con, "INSERT INTO hr_exit_rounds (round_number, round_name, description, created_by) VALUES 
        (1, 'Initial Exit Feedback', 'HR initial exit interview and reason for departure', 'System'),
        (2, 'Management Exit Review', 'Final management review and handover confirmation', 'System')");
}

// Table: hr_exit_interview_questions
$check_q = mysqli_query($con, "SHOW TABLES LIKE 'hr_exit_interview_questions'");
if ($check_q && mysqli_num_rows($check_q) == 0) {
    mysqli_query($con, "CREATE TABLE hr_exit_interview_questions (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL DEFAULT 0,
        position_id INT(11) NOT NULL DEFAULT 0,
        round_number INT(11) NOT NULL DEFAULT 1,
        question_text TEXT NOT NULL,
        input_type VARCHAR(50) DEFAULT 'text',
        options_json TEXT DEFAULT NULL,
        sort_order INT(11) DEFAULT 0,
        is_active TINYINT(1) DEFAULT 1,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} else {
    $cols_res = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_interview_questions");
    $existing_cols = [];
    if ($cols_res) { while ($c = mysqli_fetch_assoc($cols_res)) { $existing_cols[] = strtolower($c['Field']); } }
    if (!in_array('input_type', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN input_type VARCHAR(50) DEFAULT 'text'"); }
    if (!in_array('round_number', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN round_number INT(11) NOT NULL DEFAULT 1"); }
    if (!in_array('is_active', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN is_active TINYINT(1) DEFAULT 1"); }
    if (!in_array('department_id', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN department_id INT(11) NOT NULL DEFAULT 0"); }
    if (!in_array('position_id', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN position_id INT(11) NOT NULL DEFAULT 0"); }
    if (!in_array('options_json', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN options_json TEXT DEFAULT NULL"); }
    if (!in_array('sort_order', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN sort_order INT(11) DEFAULT 0"); }
    if (!in_array('created_by', $existing_cols)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_questions ADD COLUMN created_by VARCHAR(255) DEFAULT NULL"); }
}

// Table: hr_exit_interview_answers
$check_a = mysqli_query($con, "SHOW TABLES LIKE 'hr_exit_interview_answers'");
if ($check_a && mysqli_num_rows($check_a) == 0) {
    mysqli_query($con, "CREATE TABLE hr_exit_interview_answers (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        exit_id INT(11) NOT NULL,
        employee_id INT(11) NOT NULL,
        question_id INT(11) NOT NULL,
        round_number INT(11) NOT NULL DEFAULT 1,
        answer_text TEXT DEFAULT NULL,
        submitted_by VARCHAR(255) DEFAULT NULL,
        submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} else {
    $cols_a = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_interview_answers");
    $ex_a = [];
    if ($cols_a) { while ($c = mysqli_fetch_assoc($cols_a)) { $ex_a[] = strtolower($c['Field']); } }
    if (!in_array('round_number', $ex_a)) { mysqli_query($con, "ALTER TABLE hr_exit_interview_answers ADD COLUMN round_number INT(11) NOT NULL DEFAULT 1"); }
}

// Add current_exit_round column to hr_exit_requests if missing
$check_r_col = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_requests LIKE 'current_exit_round'");
if ($check_r_col && mysqli_num_rows($check_r_col) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_requests ADD COLUMN current_exit_round INT(11) NOT NULL DEFAULT 1");
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$current_page    = basename($_SERVER['PHP_SELF']);

// Navigation State
$main_tab = isset($_GET['tab']) && $_GET['tab'] == 'questions' ? 'questions' : 'interviews';
$sub_tab  = isset($_GET['sub']) && $_GET['sub'] == 'rounds' ? 'rounds' : 'questions';
$view     = isset($_GET['view']) && $_GET['view'] == 'completed' ? 'completed' : 'pending';

// Helper: Fetch all defined Exit Rounds sorted by round_number
function getExitRounds($con) {
    $rounds = [];
    $rq = mysqli_query($con, "SELECT * FROM hr_exit_rounds ORDER BY round_number ASC");
    if ($rq) {
        while ($r = mysqli_fetch_assoc($rq)) {
            $rounds[] = $r;
        }
    }
    return $rounds;
}

// Helper: Get map of round_number => round_name
function getExitRoundsMap($con) {
    $map = [];
    $rounds = getExitRounds($con);
    foreach ($rounds as $r) {
        $map[$r['round_number']] = $r['round_name'];
    }
    return $map;
}

$exit_rounds_list = getExitRounds($con);
$exit_rounds_map  = getExitRoundsMap($con);

// =========================================================================
// SELF-HEAL: Ensure settlement tables/columns exist
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_exit_settlement (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL UNIQUE,
    pending_salary DECIMAL(12,2) DEFAULT 0,
    leave_encashment DECIMAL(12,2) DEFAULT 0,
    bonus_incentive DECIMAL(12,2) DEFAULT 0,
    gratuity_amount DECIMAL(12,2) DEFAULT 0,
    pension_amount DECIMAL(12,2) DEFAULT 0,
    severance_pay DECIMAL(12,2) DEFAULT 0,
    loan_recovery DECIMAL(12,2) DEFAULT 0,
    notice_shortfall_deduction DECIMAL(12,2) DEFAULT 0,
    other_deductions DECIMAL(12,2) DEFAULT 0,
    net_amount DECIMAL(12,2) DEFAULT 0,
    payment_within_days INT DEFAULT 30,
    notes TEXT DEFAULT NULL,
    status ENUM('pending','approved') DEFAULT 'pending',
    approved_by VARCHAR(255) DEFAULT NULL,
    approved_at DATETIME DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add payment_within_days if missing (existing installs)
$chk_pwd = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_settlement LIKE 'payment_within_days'");
if ($chk_pwd && mysqli_num_rows($chk_pwd) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_settlement ADD COLUMN payment_within_days INT DEFAULT 30 AFTER net_amount");
}

// Custom dynamic line items per settlement
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_exit_settlement_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    label VARCHAR(255) NOT NULL,
    amount DECIMAL(12,2) DEFAULT 0,
    item_type ENUM('earning','deduction') DEFAULT 'earning',
    sort_order INT DEFAULT 0,
    INDEX(exit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// =========================================================================
// AJAX ENDPOINTS (BEFORE ANY HTML OUTPUT)
// =========================================================================

// -0a. AJAX: Fetch existing settlement data for a candidate
if (isset($_GET['fetch_settlement_data'])) {
    $exit_id = intval($_GET['exit_id'] ?? 0);
    header('Content-Type: application/json');

    $s = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_settlement WHERE exit_id=$exit_id LIMIT 1"));
    $items_q = mysqli_query($con, "SELECT * FROM hr_exit_settlement_items WHERE exit_id=$exit_id ORDER BY item_type, sort_order ASC");
    $items = [];
    if ($items_q) while ($it = mysqli_fetch_assoc($items_q)) $items[] = $it;

    echo json_encode(['settlement' => $s ?: null, 'items' => $items]);
    exit;
}

// -0b. AJAX: Save settlement from interview portal
if (isset($_POST['ajax_action']) && $_POST['ajax_action'] === 'save_settlement_from_interview') {
    header('Content-Type: application/json');
    $exit_id = intval($_POST['exit_id'] ?? 0);
    if ($exit_id <= 0) { echo json_encode(['success' => false, 'message' => 'Invalid exit ID']); exit; }

    $payment_within_days = intval($_POST['payment_within_days'] ?? 30);
    $notes = mysqli_real_escape_string($con, trim($_POST['notes'] ?? ''));
    $final_lwd = mysqli_real_escape_string($con, trim($_POST['final_last_working_day'] ?? ''));

    // Fixed fields
    $num = function($k) { return isset($_POST[$k]) && $_POST[$k] !== '' ? (float)$_POST[$k] : 0; };
    $pending_salary = $num('pending_salary');
    $leave_encashment = $num('leave_encashment');
    $bonus_incentive = $num('bonus_incentive');
    $gratuity_amount = $num('gratuity_amount');
    $pension_amount = $num('pension_amount');
    $severance_pay = $num('severance_pay');
    $loan_recovery = $num('loan_recovery');
    $notice_shortfall = $num('notice_shortfall_deduction');
    $other_deductions = $num('other_deductions');

    // Dynamic custom items
    $custom_earnings = 0;
    $custom_deductions = 0;
    $custom_labels = $_POST['custom_label'] ?? [];
    $custom_amounts = $_POST['custom_amount'] ?? [];
    $custom_types   = $_POST['custom_type'] ?? [];

    // Save fixed settlement
    $net = ($pending_salary + $leave_encashment + $bonus_incentive + $gratuity_amount + $pension_amount + $severance_pay)
         - ($loan_recovery + $notice_shortfall + $other_deductions);

    // Add custom items to net
    mysqli_query($con, "DELETE FROM hr_exit_settlement_items WHERE exit_id=$exit_id");
    foreach ($custom_labels as $i => $lbl) {
        $lbl = mysqli_real_escape_string($con, trim($lbl));
        $amt = (float)($custom_amounts[$i] ?? 0);
        $typ = ($custom_types[$i] ?? 'earning') === 'deduction' ? 'deduction' : 'earning';
        if ($lbl === '' && $amt == 0) continue;
        if ($typ === 'earning') { $custom_earnings += $amt; } else { $custom_deductions += $amt; }
        $so = $i;
        mysqli_query($con, "INSERT INTO hr_exit_settlement_items (exit_id, label, amount, item_type, sort_order) VALUES ($exit_id, '$lbl', $amt, '$typ', $so)");
    }
    $net += $custom_earnings - $custom_deductions;

    mysqli_query($con, "INSERT INTO hr_exit_settlement
        (exit_id, pending_salary, leave_encashment, bonus_incentive, gratuity_amount, pension_amount, severance_pay,
         loan_recovery, notice_shortfall_deduction, other_deductions, net_amount, payment_within_days, notes)
        VALUES ($exit_id, $pending_salary, $leave_encashment, $bonus_incentive, $gratuity_amount, $pension_amount, $severance_pay,
                $loan_recovery, $notice_shortfall, $other_deductions, $net, $payment_within_days, '$notes')
        ON DUPLICATE KEY UPDATE
        pending_salary=$pending_salary, leave_encashment=$leave_encashment, bonus_incentive=$bonus_incentive,
        gratuity_amount=$gratuity_amount, pension_amount=$pension_amount, severance_pay=$severance_pay,
        loan_recovery=$loan_recovery, notice_shortfall_deduction=$notice_shortfall, other_deductions=$other_deductions,
        net_amount=$net, payment_within_days=$payment_within_days, notes='$notes'");

    if (!empty($final_lwd)) {
        mysqli_query($con, "UPDATE hr_exit_requests SET final_last_working_day='$final_lwd' WHERE id=$exit_id");
    }

    // Advance to documents if requested
    $advance = intval($_POST['advance_to_documents'] ?? 0);
    if ($advance === 1) {
        mysqli_query($con, "UPDATE hr_exit_requests SET status='documents' WHERE id=$exit_id AND status='interview_settlement'");
    }

    // Fetch employee/exit data for the settlement preview
    $exit_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT r.*, e.name as emp_name, e.employee_id as emp_code, e.department as emp_dept, e.position as emp_pos, e.hire_date, e.phone as emp_phone, e.address as emp_addr, e.company_name as emp_company FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.id=$exit_id LIMIT 1"));

    // Build settlement statement HTML inline (compact version)
    $emp_name = htmlspecialchars($exit_row['emp_name'] ?? '');
    $emp_code = htmlspecialchars($exit_row['emp_code'] ?? '');
    $emp_dept = htmlspecialchars($exit_row['emp_dept'] ?? '');
    $emp_pos  = htmlspecialchars($exit_row['emp_pos'] ?? '');
    $lwd_display = !empty($exit_row['final_last_working_day']) ? date('d M Y', strtotime($exit_row['final_last_working_day'])) : '—';
    $join_date = !empty($exit_row['hire_date']) ? date('d M Y', strtotime($exit_row['hire_date'])) : '—';

    $rows_html = '';
    $all_items = [
        ['Pending Salary', $pending_salary, 'earning'],
        ['Leave Encashment', $leave_encashment, 'earning'],
        ['Bonus / Incentive', $bonus_incentive, 'earning'],
        ['Gratuity', $gratuity_amount, 'earning'],
        ['Pension', $pension_amount, 'earning'],
        ['Severance / Notice Pay', $severance_pay, 'earning'],
    ];
    foreach ($custom_labels as $i => $lbl) {
        $lbl2 = trim($lbl);
        $amt2 = (float)($custom_amounts[$i] ?? 0);
        $typ2 = ($custom_types[$i] ?? 'earning');
        if ($lbl2 !== '' || $amt2 != 0) $all_items[] = [$lbl2 ?: 'Custom', $amt2, $typ2];
    }
    $deductions = [
        ['Loan Recovery', $loan_recovery],
        ['Notice Shortfall Deduction', $notice_shortfall],
        ['Other Deductions', $other_deductions],
    ];
    foreach ($custom_labels as $i => $lbl) {
        $lbl2 = trim($lbl);
        $amt2 = (float)($custom_amounts[$i] ?? 0);
        $typ2 = ($custom_types[$i] ?? 'earning');
        // already included above for deductions
    }

    $sl = 1;
    foreach ($all_items as $item) {
        if ($item[1] == 0 && $item[2] !== 'deduction') continue;
        $color = $item[2] === 'deduction' ? '#991b1b' : '#0f2557';
        $rows_html .= '<tr><td style="border:1px solid #cbd5e1;padding:7px 10px;">'.$sl.'</td><td style="border:1px solid #cbd5e1;padding:7px 10px;color:'.$color.';font-weight:600;">'.htmlspecialchars($item[0]).'</td><td style="border:1px solid #cbd5e1;padding:7px 10px;text-align:right;color:'.$color.';font-weight:700;">'.($item[2]==='deduction'?'− ':'').'₹ '.number_format($item[1],2).'</td></tr>';
        $sl++;
    }
    foreach ($deductions as $d) {
        if ($d[1] == 0) continue;
        $rows_html .= '<tr><td style="border:1px solid #cbd5e1;padding:7px 10px;">'.$sl.'</td><td style="border:1px solid #cbd5e1;padding:7px 10px;color:#991b1b;font-weight:600;">'.htmlspecialchars($d[0]).'</td><td style="border:1px solid #cbd5e1;padding:7px 10px;text-align:right;color:#991b1b;font-weight:700;">− ₹ '.number_format($d[1],2).'</td></tr>';
        $sl++;
    }

    $preview_html = '
    <div style="font-family:\'Plus Jakarta Sans\',sans-serif; background:#fff; padding:28px; border:1px solid #e2e8f0; border-radius:12px; max-width:720px; margin:0 auto;">
      <div style="text-align:center; border-bottom:3px solid #0f2557; padding-bottom:14px; margin-bottom:18px;">
        <div style="font-size:18px; font-weight:900; color:#0f2557; letter-spacing:1px;">FULL &amp; FINAL SETTLEMENT STATEMENT</div>
      </div>
      <table style="width:100%; font-size:12.5px; margin-bottom:14px; border-collapse:collapse;">
        <tr><td style="padding:4px 8px;color:#475569;font-weight:600;">Employee Name</td><td style="padding:4px 8px;font-weight:800;color:#0f2557;">'.$emp_name.'</td><td style="padding:4px 8px;color:#475569;font-weight:600;">Employee Code</td><td style="padding:4px 8px;font-weight:700;">'.$emp_code.'</td></tr>
        <tr><td style="padding:4px 8px;color:#475569;font-weight:600;">Department</td><td style="padding:4px 8px;">'.$emp_dept.'</td><td style="padding:4px 8px;color:#475569;font-weight:600;">Designation</td><td style="padding:4px 8px;">'.$emp_pos.'</td></tr>
        <tr><td style="padding:4px 8px;color:#475569;font-weight:600;">Date of Joining</td><td style="padding:4px 8px;">'.$join_date.'</td><td style="padding:4px 8px;color:#475569;font-weight:600;">Last Working Day</td><td style="padding:4px 8px;">'.$lwd_display.'</td></tr>
      </table>
      <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:16px;">
        <thead><tr>
          <th style="border:1px solid #cbd5e1;padding:7px 10px;background:#0f2557;color:#fff;font-size:11px;text-transform:uppercase;width:8%;">Sl.</th>
          <th style="border:1px solid #cbd5e1;padding:7px 10px;background:#0f2557;color:#fff;font-size:11px;text-transform:uppercase;">Particulars</th>
          <th style="border:1px solid #cbd5e1;padding:7px 10px;background:#0f2557;color:#fff;font-size:11px;text-transform:uppercase;text-align:right;width:25%;">Amount (₹)</th>
        </tr></thead>
        <tbody>'.$rows_html.'</tbody>
        <tfoot><tr>
          <td colspan="2" style="border:1px solid #0f2557;padding:9px 10px;background:#0f2557;color:#fff;font-weight:800;font-size:13px;text-align:right;">NET PAYABLE</td>
          <td style="border:1px solid #0f2557;padding:9px 10px;background:#0f2557;color:#fff;font-weight:900;font-size:14px;text-align:right;">₹ '.number_format($net,2).'</td>
        </tr></tfoot>
      </table>
      '.(!empty($notes) ? '<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#475569;margin-bottom:14px;"><strong>Notes:</strong> '.htmlspecialchars($notes).'</div>' : '').'
      <div style="font-size:12px;color:#475569;margin-bottom:16px;">Payment will be processed within <strong>'.$payment_within_days.' days</strong> of the last working date.</div>
    </div>';

    echo json_encode(['success' => true, 'net' => $net, 'preview_html' => $preview_html, 'advanced' => ($advance === 1)]);
    exit;
}

// 0. AJAX: Fetch Interview History for a candidate
if (isset($_GET['fetch_interview_history'])) {
    $exit_id = intval($_GET['exit_id'] ?? 0);
    header('Content-Type: application/json');

    $rounds_map = $exit_rounds_map;

    // Get all rounds that have answers for this exit
    $rq = mysqli_query($con, "SELECT DISTINCT a.round_number, MAX(a.submitted_by) as submitted_by, MAX(a.submitted_at) as submitted_at
        FROM hr_exit_interview_answers a
        WHERE a.exit_id=$exit_id
        GROUP BY a.round_number
        ORDER BY a.round_number ASC");

    $result = [];
    if ($rq) {
        while ($round = mysqli_fetch_assoc($rq)) {
            $rnum = intval($round['round_number']);
            $rname = $rounds_map[$rnum] ?? ('Round '.$rnum);
            $submitted_at_fmt = !empty($round['submitted_at']) ? date('d M Y, h:i A', strtotime($round['submitted_at'])) : '—';

            // Fetch Q&A for this round
            $aq = mysqli_query($con, "SELECT q.question_text, a.answer_text
                FROM hr_exit_interview_answers a
                JOIN hr_exit_interview_questions q ON q.id = a.question_id
                WHERE a.exit_id=$exit_id AND a.round_number=$rnum
                ORDER BY q.sort_order ASC, q.id ASC");

            $answers = [];
            if ($aq) {
                while ($ar = mysqli_fetch_assoc($aq)) {
                    $answers[] = [
                        'question_text' => htmlspecialchars($ar['question_text']),
                        'answer_text'   => htmlspecialchars($ar['answer_text'] ?? '')
                    ];
                }
            }

            $result[] = [
                'round_number' => $rnum,
                'round_name'   => htmlspecialchars($rname),
                'submitted_by' => htmlspecialchars($round['submitted_by'] ?? '—'),
                'submitted_at' => $submitted_at_fmt,
                'answers'      => $answers
            ];
        }
    }

    echo json_encode($result);
    exit;
}

// 1. AJAX: Fetch Sequential Multi-Round Interview Questions
if (isset($_GET['fetch_interview_questions'])) {
    $exit_id       = intval($_GET['exit_id'] ?? 0);
    $active_round  = intval($_GET['round_number'] ?? 0);

    // Fetch candidate current_exit_round from exit_requests
    $cand_req = mysqli_fetch_assoc(mysqli_query($con, "SELECT current_exit_round, status FROM hr_exit_requests WHERE id=$exit_id LIMIT 1"));
    $cand_curr_round = intval($cand_req['current_exit_round'] ?? 1);
    $is_already_completed = in_array($cand_req['status'] ?? '', ['interview_settlement','documents','closed']);

    // Fetch answers
    $answers = [];
    if ($exit_id > 0) {
        $aq = mysqli_query($con, "SELECT question_id, answer_text FROM hr_exit_interview_answers WHERE exit_id=$exit_id");
        if ($aq) { while ($a = mysqli_fetch_assoc($aq)) $answers[$a['question_id']] = $a['answer_text']; }
    }

    // Configured rounds from DB
    $configured_rounds_map = $exit_rounds_map;
    $configured_round_nums = array_keys($configured_rounds_map);
    if (empty($configured_round_nums)) $configured_round_nums = [1];
    sort($configured_round_nums);

    if ($active_round <= 0) $active_round = $cand_curr_round;
    if (!in_array($active_round, $configured_round_nums)) $active_round = $configured_round_nums[0];

    $max_round = max($configured_round_nums);

    // Round status map
    $round_status = [];
    foreach ($configured_round_nums as $rnd) {
        $t_q = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_exit_interview_questions WHERE round_number=$rnd AND (is_active=1 OR is_active IS NULL)"))['cnt'] ?? 0;
        $a_q = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(DISTINCT a.question_id) as cnt 
            FROM hr_exit_interview_answers a 
            JOIN hr_exit_interview_questions q ON q.id = a.question_id 
            WHERE a.exit_id=$exit_id AND q.round_number=$rnd AND TRIM(a.answer_text) != ''"))['cnt'] ?? 0;

        $is_done = ($t_q > 0 && $a_q >= $t_q) || ($rnd < $cand_curr_round) || $is_already_completed;
        $round_status[$rnd] = [
            'total' => $t_q,
            'answered' => $a_q,
            'completed' => $is_done,
            'unlocked' => ($rnd == 1 || ($round_status[$rnd - 1]['completed'] ?? false) || $rnd <= $cand_curr_round || $is_already_completed)
        ];
    }

    $html = '';

    // Render Round Stepper / Tabs Bar inside Modal
    $html .= '<div style="margin-bottom:20px; border-bottom:2px solid #e4e9f2; padding-bottom:12px; display:flex; gap:10px; flex-wrap:wrap; align-items:center;">';
    foreach ($configured_round_nums as $rnd) {
        $st = $round_status[$rnd];
        $is_active_tab = ($rnd == $active_round);
        $r_title = $configured_rounds_map[$rnd] ?? ('Round '.$rnd);

        if ($st['unlocked']) {
            $btn_bg = $is_active_tab ? 'linear-gradient(135deg,#0f2557,#1a3fc4)' : '#f1f5f9';
            $btn_col = $is_active_tab ? '#fff' : '#0f2557';
            $badge = $st['completed'] ? '<i class="fas fa-check-circle text-success ml-1"></i>' : '<span class="badge badge-light ml-1">'.$st['answered'].'/'.$st['total'].'</span>';
            
            $html .= '<button type="button" class="btn-p" style="background:'.$btn_bg.'; color:'.$btn_col.'; font-size:12.5px; padding:7px 16px; border-radius:8px; cursor:pointer;" onclick="switchInterviewRound('.$exit_id.', '.$rnd.')">';
            $html .= '<i class="fas fa-layer-group mr-1"></i> Round '.$rnd.': '.htmlspecialchars($r_title).' '.$badge;
            $html .= '</button>';
        } else {
            $html .= '<button type="button" class="btn-p" style="background:#f8fafc; color:#94a3b8; font-size:12.5px; padding:7px 16px; border-radius:8px; border:1px dashed #cbd5e1; cursor:not-allowed;" title="Complete previous round to unlock Round '.$rnd.'">';
            $html .= '<i class="fas fa-lock mr-1"></i> Round '.$rnd.': '.htmlspecialchars($r_title).' <span class="badge badge-secondary ml-1">Locked</span>';
            $html .= '</button>';
        }
    }
    $html .= '</div>';

    $html .= '<input type="hidden" name="submitted_round" value="'.$active_round.'">';
    $html .= '<input type="hidden" name="max_configured_round" value="'.$max_round.'">';

    // Questions for active round
    $qq = mysqli_query($con, "SELECT * FROM hr_exit_interview_questions WHERE round_number=$active_round AND (is_active=1 OR is_active IS NULL) ORDER BY sort_order ASC, id ASC");
    
    if (!$qq || mysqli_num_rows($qq) == 0) {
        $html .= '<div class="alert-err"><i class="fas fa-exclamation-triangle"></i> No questions configured for Round '.$active_round.' ('.htmlspecialchars($configured_rounds_map[$active_round] ?? 'Round '.$active_round).'). Add questions in the "Manage Questions" tab.</div>';
    } else {
        $html .= '<div style="margin-bottom:12px; font-weight:700; color:#1a3fc4; font-size:13px;"><i class="fas fa-clipboard-list mr-1"></i> Round '.$active_round.' ('.htmlspecialchars($configured_rounds_map[$active_round] ?? 'Round '.$active_round).') Questions:</div>';
        $q_count = 1;
        while ($q = mysqli_fetch_assoc($qq)) {
            $qid  = $q['id'];
            $ans  = $answers[$qid] ?? '';
            $opts = (!empty($q['options_json'])) ? (json_decode($q['options_json'], true) ?: []) : [];

            $html .= '<div style="background:#f8fafc; padding:16px 20px; border-radius:10px; border:1px solid #e4e9f2; border-left:4px solid #1a3fc4; margin-bottom:16px;">';
            $html .= '<div style="font-weight:700; color:#0f2557; margin-bottom:10px; font-size:14px; display:flex; align-items:center; gap:8px;">';
            $html .= '<span style="background:#1a3fc4; color:#fff; width:24px; height:24px; border-radius:50%; display:inline-flex; align-items:center; justify-content:center; font-size:12px;">'.$q_count.'</span>';
            $html .= htmlspecialchars($q['question_text']);
            $html .= '</div>';

            switch ($q['input_type']) {
                case 'textarea':
                    $html .= '<textarea name="answers['.$qid.']" class="fc" rows="3" placeholder="Type response for Round '.$active_round.'...">'.htmlspecialchars($ans).'</textarea>';
                    break;
                case 'select':
                    $html .= '<select name="answers['.$qid.']" class="fc"><option value="">-- Select Option --</option>';
                    foreach ($opts as $opt) {
                        $sel = ($ans === $opt) ? 'selected' : '';
                        $html .= '<option value="'.htmlspecialchars($opt).'" '.$sel.'>'.htmlspecialchars($opt).'</option>';
                    }
                    $html .= '</select>';
                    break;
                case 'radio':
                    $html .= '<div style="display:flex; flex-wrap:wrap; gap:16px;">';
                    foreach ($opts as $opt) {
                        $uid = 'r_'.$qid.'_'.md5($opt);
                        $chk = ($ans === $opt) ? 'checked' : '';
                        $html .= '<label style="font-weight:600; font-size:13px; cursor:pointer; display:flex; align-items:center; gap:6px; color:#0f172a;">';
                        $html .= '<input type="radio" id="'.$uid.'" name="answers['.$qid.']" value="'.htmlspecialchars($opt).'" '.$chk.'> '.htmlspecialchars($opt);
                        $html .= '</label>';
                    }
                    $html .= '</div>';
                    break;
                case 'checkbox':
                    $ans_arr = array_map('trim', explode(',', $ans));
                    $html .= '<div style="display:flex; flex-wrap:wrap; gap:16px;">';
                    foreach ($opts as $opt) {
                        $uid = 'c_'.$qid.'_'.md5($opt);
                        $chk = in_array(trim($opt), $ans_arr) ? 'checked' : '';
                        $html .= '<label style="font-weight:600; font-size:13px; cursor:pointer; display:flex; align-items:center; gap:6px; color:#0f172a;">';
                        $html .= '<input type="checkbox" id="'.$uid.'" name="answers['.$qid.'][]" value="'.htmlspecialchars($opt).'" '.$chk.'> '.htmlspecialchars($opt);
                        $html .= '</label>';
                    }
                    $html .= '</div>';
                    break;
                default:
                    $html .= '<input type="text" name="answers['.$qid.']" class="fc" value="'.htmlspecialchars($ans).'" placeholder="Enter response...">';
            }
            $html .= '</div>';
            $q_count++;
        }
    }

    // Interview History Log
    $hist_q = mysqli_query($con, "SELECT round_number, MAX(submitted_at) as completed_at, MAX(submitted_by) as completed_by FROM hr_exit_interview_answers WHERE exit_id=$exit_id GROUP BY round_number ORDER BY round_number ASC");
    if ($hist_q && mysqli_num_rows($hist_q) > 0) {
        $html .= '<div style="margin-top:20px; padding:16px; background:#f0fdf4; border:1px solid #bbf7d0; border-radius:10px;">';
        $html .= '<h6 style="font-weight:800; color:#166534; font-size:13px; margin-bottom:10px;"><i class="fas fa-history mr-1"></i> Interview Submission History</h6>';
        $html .= '<ul style="margin:0; padding-left:20px; font-size:13px; color:#14532d;">';
        while ($hq = mysqli_fetch_assoc($hist_q)) {
            $h_rnd = intval($hq['round_number']);
            $h_by = htmlspecialchars($hq['completed_by'] ?: 'System');
            $h_at = date('d M Y, h:i A', strtotime($hq['completed_at']));
            $r_title = htmlspecialchars($configured_rounds_map[$h_rnd] ?? 'Round '.$h_rnd);
            $html .= '<li style="margin-bottom:6px;"><strong>Round '.$h_rnd.' ('.$r_title.')</strong> was completed by <strong>'.$h_by.'</strong> on <em>'.$h_at.'</em>.</li>';
        }
        $html .= '</ul></div>';
    }

    $is_last_round = ($active_round >= $max_round);
    $html .= '<input type="hidden" id="ajax_is_last_round" value="'.($is_last_round ? '1' : '0').'">';
    $html .= '<input type="hidden" id="ajax_active_round" value="'.$active_round.'">';
    $html .= '<input type="hidden" id="ajax_next_round" value="'.($active_round + 1).'">';

    header('Content-Type: text/html; charset=utf-8');
    echo $html;
    exit;
}

// 2. EXPORT QUESTIONS CSV
if (isset($_GET['action']) && $_GET['action'] == 'export_questions') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=exit_interview_questions_'.date('Y-m-d').'.csv');
    $output = fopen('php://output', 'w');
    fputcsv($output, ['Round Number', 'Question Text', 'Input Type', 'Options (comma separated)', 'Sort Order']);
    
    $eq = mysqli_query($con, "SELECT round_number, question_text, input_type, options_json, sort_order FROM hr_exit_interview_questions WHERE is_active=1 OR is_active IS NULL ORDER BY round_number ASC, sort_order ASC, id ASC");
    if ($eq) {
        while ($row = mysqli_fetch_assoc($eq)) {
            $opts = (!empty($row['options_json'])) ? implode(', ', (json_decode($row['options_json'], true) ?: [])) : '';
            fputcsv($output, [$row['round_number'], $row['question_text'], $row['input_type'], $opts, $row['sort_order']]);
        }
    }
    fclose($output);
    exit;
}

// 3. DOWNLOAD CSV TEMPLATE
if (isset($_GET['action']) && $_GET['action'] == 'download_template') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=exit_questions_template.csv');
    $output = fopen('php://output', 'w');
    fputcsv($output, ['Round Number', 'Question Text', 'Input Type', 'Options (CSV)', 'Sort Order']);
    fputcsv($output, ['1', 'What is your primary reason for leaving?', 'textarea', '', '1']);
    fputcsv($output, ['1', 'How would you rate the work culture?', 'select', 'Excellent, Good, Average, Poor', '2']);
    fputcsv($output, ['2', 'Would you consider returning to the company in the future?', 'radio', 'Yes, No, Maybe', '1']);
    fclose($output);
    exit;
}

// =========================================================================
// POST ACTIONS HANDLER
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action'])) {
    $act = $_POST['action'];

    // --- MANAGE DYNAMIC EXIT ROUNDS (ADD / EDIT / DELETE) ---
    if ($act == 'add_exit_round') {
        $r_num  = intval($_POST['round_number'] ?? 1);
        $r_name = mysqli_real_escape_string($con, trim($_POST['round_name'] ?? ''));
        $desc   = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        if ($r_num > 0 && !empty($r_name)) {
            $res = mysqli_query($con, "INSERT INTO hr_exit_rounds (round_number, round_name, description, created_by) VALUES ($r_num, '$r_name', '$desc', '$currentUserName')");
            if ($res) {
                $_SESSION['success_message'] = "Exit Round '$r_name' (Round $r_num) created successfully.";
            } else {
                $_SESSION['error_message'] = "Database error creating round: " . mysqli_error($con);
            }
        } else {
            $_SESSION['error_message'] = "Round number and round name are required.";
        }
        header("Location: $current_page?tab=questions&sub=rounds");
        exit;
    }

    if ($act == 'edit_exit_round') {
        $id     = intval($_POST['id'] ?? 0);
        $r_num  = intval($_POST['round_number'] ?? 1);
        $r_name = mysqli_real_escape_string($con, trim($_POST['round_name'] ?? ''));
        $desc   = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));

        if ($id > 0 && $r_num > 0 && !empty($r_name)) {
            $res = mysqli_query($con, "UPDATE hr_exit_rounds SET round_number=$r_num, round_name='$r_name', description='$desc' WHERE id=$id");
            if ($res) {
                $_SESSION['success_message'] = "Exit Round updated successfully.";
            } else {
                $_SESSION['error_message'] = "Database error updating round: " . mysqli_error($con);
            }
        } else {
            $_SESSION['error_message'] = "Invalid round details.";
        }
        header("Location: $current_page?tab=questions&sub=rounds");
        exit;
    }

    if ($act == 'delete_exit_round') {
        $id = intval($_POST['id'] ?? 0);
        if ($id > 0) {
            mysqli_query($con, "DELETE FROM hr_exit_rounds WHERE id=$id");
            $_SESSION['success_message'] = "Exit Round deleted successfully.";
        }
        header("Location: $current_page?tab=questions&sub=rounds");
        exit;
    }

    // --- SAVE / COMPLETE INTERVIEW / ADVANCE ROUND ---
    if ($act == 'save_interview' || $act == 'complete_interview' || $act == 'complete_round_next') {
        $exit_id         = intval($_POST['exit_id'] ?? 0);
        $employee_id     = intval($_POST['employee_id'] ?? 0);
        $submitted_round = intval($_POST['submitted_round'] ?? 1);
        $max_round       = intval($_POST['max_configured_round'] ?? 1);
        $answers         = isset($_POST['answers']) ? (array)$_POST['answers'] : [];

        foreach ($answers as $q_id => $ans) {
            $q_id = intval($q_id);
            if ($q_id <= 0) continue;
            if (is_array($ans)) $ans = implode(', ', $ans);
            $ans_s = mysqli_real_escape_string($con, (string)$ans);
            
            $exists = mysqli_query($con, "SELECT id FROM hr_exit_interview_answers WHERE exit_id=$exit_id AND question_id=$q_id");
            if ($exists && mysqli_num_rows($exists) > 0) {
                mysqli_query($con, "UPDATE hr_exit_interview_answers SET answer_text='$ans_s', round_number=$submitted_round, submitted_by='$currentUserName', submitted_at=NOW() WHERE exit_id=$exit_id AND question_id=$q_id");
            } else {
                mysqli_query($con, "INSERT INTO hr_exit_interview_answers (exit_id, employee_id, question_id, round_number, answer_text, submitted_by) VALUES ($exit_id, $employee_id, $q_id, $submitted_round, '$ans_s', '$currentUserName')");
            }
        }

        if ($act == 'complete_round_next') {
            $next_r = $submitted_round + 1;
            mysqli_query($con, "UPDATE hr_exit_requests SET current_exit_round=$next_r WHERE id=$exit_id");
            $_SESSION['success_message'] = "Round $submitted_round completed! Advanced candidate to Round $next_r.";
        } elseif ($act == 'complete_interview') {
            mysqli_query($con, "UPDATE hr_exit_requests SET status='interview_settlement', current_exit_round=99 WHERE id=$exit_id");
            $_SESSION['success_message'] = "All Exit Interview rounds completed successfully!";
        } else {
            $_SESSION['success_message'] = "Draft answers for Round $submitted_round saved successfully.";
        }
        header("Location: $current_page?tab=interviews&view=$view");
        exit;
    }

    // --- ADD / EDIT QUESTION ---
    if ($act == 'add_question' || $act == 'edit_question') {
        $round_number  = intval($_POST['round_number'] ?? 1);
        if ($round_number <= 0) $round_number = 1;
        $question_text = mysqli_real_escape_string($con, trim($_POST['question_text'] ?? ''));
        $input_type    = mysqli_real_escape_string($con, trim($_POST['input_type'] ?? 'text'));
        $sort_order    = intval($_POST['sort_order'] ?? 0);
        $opts_json     = 'NULL';

        if (in_array($input_type, ['select','radio','checkbox']) && !empty($_POST['options_csv'])) {
            $clean = array_filter(array_map('trim', explode(',', $_POST['options_csv'])));
            $opts_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($clean))) . "'";
        }

        if ($act == 'add_question' && !empty($question_text)) {
            $ins = mysqli_query($con, "INSERT INTO hr_exit_interview_questions (department_id, position_id, round_number, question_text, input_type, options_json, sort_order, is_active, created_by) VALUES (0, 0, $round_number, '$question_text', '$input_type', $opts_json, $sort_order, 1, '$currentUserName')");
            if ($ins) {
                $_SESSION['success_message'] = "Question added to Round $round_number successfully.";
            } else {
                $_SESSION['error_message'] = "Database error adding question: " . mysqli_error($con);
            }
        } elseif ($act == 'edit_question') {
            $id = intval($_POST['id']);
            if ($id > 0 && !empty($question_text)) {
                $upd = mysqli_query($con, "UPDATE hr_exit_interview_questions SET round_number=$round_number, question_text='$question_text', input_type='$input_type', options_json=$opts_json, sort_order=$sort_order WHERE id=$id");
                if ($upd) {
                    $_SESSION['success_message'] = "Question updated successfully.";
                } else {
                    $_SESSION['error_message'] = "Database error updating question: " . mysqli_error($con);
                }
            }
        } else {
            $_SESSION['error_message'] = "Question text is required.";
        }
        header("Location: $current_page?tab=questions&sub=questions");
        exit;
    }

    // --- DELETE SINGLE QUESTION ---
    if ($act == 'delete_question') {
        $id = intval($_POST['id']);
        if ($id > 0) {
            mysqli_query($con, "DELETE FROM hr_exit_interview_questions WHERE id=$id");
            $_SESSION['success_message'] = "Question deleted successfully.";
        }
        header("Location: $current_page?tab=questions&sub=questions");
        exit;
    }

    // --- DELETE BULK QUESTIONS ---
    if ($act == 'delete_questions_bulk') {
        $ids = isset($_POST['ids']) ? array_filter(array_map('intval', (array)$_POST['ids'])) : [];
        if (!empty($ids)) {
            mysqli_query($con, "DELETE FROM hr_exit_interview_questions WHERE id IN (" . implode(',', $ids) . ")");
            $_SESSION['success_message'] = count($ids) . " question(s) deleted successfully.";
        } else {
            $_SESSION['error_message'] = "No questions selected for deletion.";
        }
        header("Location: $current_page?tab=questions&sub=questions");
        exit;
    }

    // --- IMPORT CSV QUESTIONS ---
    if ($act == 'import_questions' && isset($_FILES['import_file']) && $_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
        $fh = fopen($_FILES['import_file']['tmp_name'], 'r');
        $header = fgetcsv($fh);
        $imp = 0;

        while (($data = fgetcsv($fh)) !== false) {
            if (empty($data) || count($data) < 2) continue;

            $r_num = 1;
            if (is_numeric(trim($data[0]))) {
                $r_num = intval(trim($data[0]));
                $qt = mysqli_real_escape_string($con, trim($data[1]));
                $it = mysqli_real_escape_string($con, trim($data[2] ?? 'text'));
                $oc = isset($data[3]) ? trim($data[3]) : '';
                $so = isset($data[4]) ? intval($data[4]) : 0;
            } else {
                $qt = mysqli_real_escape_string($con, trim($data[0]));
                $it = mysqli_real_escape_string($con, trim($data[1] ?? 'text'));
                $oc = isset($data[2]) ? trim($data[2]) : '';
                $so = isset($data[3]) ? intval($data[3]) : 0;
            }

            $it = strtolower($it);
            if (!in_array($it, ['text','textarea','select','radio','checkbox'])) $it = 'text';

            $oj = 'NULL';
            if (!empty($oc) && in_array($it, ['select','radio','checkbox'])) {
                $oa = array_filter(array_map('trim', explode(',', $oc)));
                $oj = "'" . mysqli_real_escape_string($con, json_encode(array_values($oa))) . "'";
            }

            if (!empty($qt)) {
                mysqli_query($con, "INSERT INTO hr_exit_interview_questions (department_id, position_id, round_number, question_text, input_type, options_json, sort_order, is_active, created_by) VALUES (0, 0, $r_num, '$qt', '$it', $oj, $so, 1, '$currentUserName')");
                $imp++;
            }
        }
        fclose($fh);
        $_SESSION['success_message'] = "Imported $imp exit question(s) successfully.";
        header("Location: $current_page?tab=questions&sub=questions");
        exit;
    }
}

// =========================================================================
// FETCH STATS & DATA FOR VIEWS
// =========================================================================

// Stat Counters
$stat_pending = 0;
$stat_completed = 0;
$stat_questions = 0;

$sq_p = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_exit_requests WHERE status = 'interview_settlement' AND (current_exit_round < 99 OR current_exit_round IS NULL)");
if ($sq_p) { $stat_pending = intval(mysqli_fetch_assoc($sq_p)['cnt']); }

$sq_c = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_exit_requests WHERE status IN ('documents','closed') OR (status='interview_settlement' AND current_exit_round = 99)");
if ($sq_c) { $stat_completed = intval(mysqli_fetch_assoc($sq_c)['cnt']); }

$sq_q = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_exit_interview_questions WHERE is_active = 1 OR is_active IS NULL");
if ($sq_q) { $stat_questions = intval(mysqli_fetch_assoc($sq_q)['cnt']); }

// 1. Fetch Candidates (for Interviews tab)
$candidates = [];
if ($main_tab == 'interviews') {
    $status_filter = ($view == 'completed')
        ? "(r.status IN ('documents','closed') OR (r.status='interview_settlement' AND r.current_exit_round = 99))"
        : "(r.status = 'interview_settlement' AND (r.current_exit_round < 99 OR r.current_exit_round IS NULL))";
    $cq = mysqli_query($con, "SELECT r.id, r.employee_id, r.exit_number, r.status, r.current_exit_round, r.final_last_working_day,
            e.name as employee_name, e.department as dept_name, e.position as pos_title
        FROM hr_exit_requests r
        LEFT JOIN hr_employees e ON e.id = r.employee_id
        WHERE $status_filter
        ORDER BY r.id DESC");

    if ($cq) {
        while ($row = mysqli_fetch_assoc($cq)) {
            $candidates[] = $row;
        }
    }
}

// 2. Fetch Questions (for Questions Management tab)
$questions_list = [];
if ($main_tab == 'questions') {
    $qq = mysqli_query($con, "SELECT * FROM hr_exit_interview_questions WHERE is_active=1 OR is_active IS NULL ORDER BY round_number ASC, sort_order ASC, id ASC");
    if ($qq) {
        while ($row = mysqli_fetch_assoc($qq)) {
            $questions_list[] = $row;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>HR Exit Interview Portal</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>

<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--success:#10b981;--warn:#f59e0b;--danger:#ef4444;--bg:#f0f4f9;--card:#fff;--border:#e4e9f2;--muted:#64748b;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;color:#0f172a;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:18px 28px;display:flex;justify-content:space-between;align-items:center;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-size:1.3rem;font-weight:800;margin:0;}
.wrap{max-width:100%;margin:0 auto;padding:24px 24px;}
.card-s{background:var(--card);border-radius:14px;border:1px solid var(--border);box-shadow:0 2px 10px rgba(0,0,0,.05);padding:24px;margin-bottom:20px;}
.sec-lbl{font-weight:800;font-size:11px;text-transform:uppercase;color:var(--blue);margin-bottom:14px;padding-bottom:8px;border-bottom:2px solid #eef2ff;display:flex;align-items:center;gap:7px;}
.fc{border:2px solid var(--border);border-radius:9px;padding:10px 13px;font-size:13px;font-family:inherit;font-weight:600;width:100%;transition:.2s;background:#fff;color:#0f172a;}
.fc:focus{outline:none;border-color:var(--blue);box-shadow:0 0 0 3px rgba(26,63,196,.08);}
label.fl{font-weight:700;font-size:12px;display:block;margin-bottom:5px;color:var(--navy);}
.fg{margin-bottom:14px;}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;}
.btn-p{padding:11px 22px;border:none;border-radius:10px;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:7px;transition:.2s;text-decoration:none;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;}
.btn-green{background:linear-gradient(135deg,var(--success),#059669);color:#fff;}
.btn-warn{background:linear-gradient(135deg,var(--warn),#d97706);color:#fff;}
.btn-light{background:#f1f5f9;color:var(--navy);border:1px solid var(--border);}
.btn-p:hover{transform:translateY(-1px);box-shadow:0 5px 15px rgba(0,0,0,.12);color:#fff;text-decoration:none;}

.status-badge{padding:5px 14px;border-radius:20px;font-size:12px;font-weight:800;display:inline-block;}
.s-pending{background:#fef9c3;color:#713f12;}
.s-completed{background:#dcfce7;color:#065f46;}
.s-ready{background:#dbeafe;color:#1e40af;}

/* Navigation Tabs */
.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 20px; }
.nav-btn {
    padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
    font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
    display: flex; align-items: center; gap: 8px; border: 2px solid transparent; transition: .2s;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

.alert-ok{background:#dcfce7;border:1px solid #86efac;color:#065f46;padding:12px 16px;border-radius:10px;font-weight:700;margin-bottom:16px;display:flex;align-items:center;gap:8px;}
.alert-err{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:12px 16px;border-radius:10px;font-weight:700;margin-bottom:16px;display:flex;align-items:center;gap:8px;}
.stat-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:20px; margin-bottom:20px; }
.stat-card { background:white; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.06); display:flex; align-items:center; gap:14px; transition:transform .15s, box-shadow .15s; }
.stat-card[style*="cursor:pointer"]:hover { transform:translateY(-2px); box-shadow:0 6px 16px rgba(0,0,0,.1); border-color:#cbd5e1; }
.stat-icon { width:48px; height:48px; border-radius:10px; display:flex; align-items:center; justify-content:center; color:white; font-size:20px; flex-shrink:0; }
.stat-card h3 { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin:0 0 6px 0; letter-spacing:0.5px; }
.stat-card p { font-size:24px; color:#0f2557; font-weight:800; margin:0; line-height:1; }

.filter-card { background:#fff; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.04); display:flex; gap:16px; align-items:flex-end; flex-wrap:wrap; margin-bottom:20px; }
.filter-group { display:flex; flex-direction:column; gap:6px; flex:1; min-width:160px; }
.filter-group label { font-size:11px; font-weight:800; color:#64748b; text-transform:uppercase; letter-spacing:0.5px; margin:0; }
.filter-group select, .filter-group input { border:2px solid #e2e8f0; border-radius:8px; padding:9px 12px; font-size:13px; font-weight:600; color:#0f2557; outline:none; transition:.2s; width:100%; }
.filter-group select:focus, .filter-group input:focus { border-color:#1a3fc4; }

/* ── Filter bar + table (matches hr_candidate_tracking.php / hr-exit-handover.php) ── */
.dt-filters { display: flex; gap: 12px; margin-bottom: 16px; align-items: center; background: #fff; padding: 14px 16px; border-radius: 12px; border: 1px solid var(--border); box-shadow: 0 2px 10px rgba(0,0,0,.05); flex-wrap: wrap; }
.dt-filters input, .dt-filters select { padding: 10px 14px; border: 2px solid var(--border); border-radius: 9px; font-size: 13px; font-weight: 500; color: #334155; background: #fff; transition: .2s; width: 170px; }
.dt-filters input[type="date"] { width: 150px; }
.dt-filters input:focus, .dt-filters select:focus { outline: none; border-color: var(--blue); box-shadow: 0 0 0 3px rgba(26,63,196,.12); }
.dt-search-wrap { position: relative; min-width: 220px; flex: 1; }
.dt-search-wrap i { position: absolute; left: 14px; top: 50%; transform: translateY(-50%); color: #94a3b8; font-size: 13px; }
.dt-search-wrap input { width: 100%; padding: 10px 14px 10px 38px; }
.dt-export-btn { background: linear-gradient(135deg,var(--success),#059669); border: none; border-radius: 9px; color: #fff; font-size: 12.5px; font-weight: 700; padding: 10px 18px; cursor: pointer; transition: all 0.2s; display: inline-flex; align-items: center; gap: 6px; box-shadow: 0 3px 10px rgba(16,185,129,.25); }
.dt-export-btn:hover { transform: translateY(-1px); box-shadow: 0 5px 16px rgba(16,185,129,.35); }

.table-card { background: #fff; border-radius: 14px; box-shadow: 0 2px 12px rgba(0,0,0,.08); overflow: hidden; }
.table-card-header { padding: 16px 20px; border-bottom: 2px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
.table-card-header h5 { font-weight: 700; color: var(--navy); margin: 0; font-size: 14px; }
.table-scroll { overflow-x: auto; overflow-y: auto; max-height: 68vh; }
.ctrack-table { width: 100%; border-collapse: collapse; min-width: 900px; }
.ctrack-table thead th { background: linear-gradient(135deg,var(--navy),var(--blue)); color: #fff; font-weight: 700; font-size: 12.5px; text-transform: uppercase; letter-spacing: .4px; padding: 13px 16px; white-space: nowrap; border-right: 1px solid rgba(255,255,255,.15); position: sticky; top: 0; z-index: 10; }
.ctrack-table thead th:last-child { border-right: none; }
.ctrack-table tbody tr { border-bottom: 1px solid #f1f5f9; transition: .15s; }
.ctrack-table tbody tr:hover { background: #f8fafc; }
.ctrack-table tbody td { padding: 13px 16px; font-size: 13.5px; font-weight: 500; color: #334155; vertical-align: middle; }
.ctrack-empty { text-align: center; padding: 40px 20px; color: #94a3b8; }

.paging-wrap { padding: 16px 20px; display: flex; align-items: center; justify-content: space-between; border-top: 2px solid var(--border); flex-wrap: wrap; gap: 12px; }
.paging-info { color: #64748b; font-size: 13px; font-weight: 600; }
.paging-btns { display: flex; gap: 6px; }
.paging-btn { padding: 7px 14px; border-radius: 8px; border: 2px solid var(--border); background: #fff; color: var(--navy); font-weight: 700; font-size: 13px; cursor: pointer; transition: .2s; }
.paging-btn:hover, .paging-btn.active { background: var(--navy); color: #fff; border-color: var(--navy); }
.paging-btn:disabled { opacity: .4; cursor: not-allowed; }

/* DataTables Custom Styling */
/* DataTables Custom Styling */
.dataTables_wrapper { padding: 0; font-size: 13px; }
.table-filter-bar { background:#fff; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.04); display:flex; gap:16px; align-items:flex-end; justify-content: space-between; flex-wrap:wrap; margin-top:15px; }
.table-footer-bar { display: flex; justify-content: space-between; align-items: center; margin-top: 15px; background: #fff; padding: 15px 20px; border-radius: 10px; border: 1px solid var(--border); box-shadow: 0 2px 6px rgba(0,0,0,0.02); margin-bottom: 20px; }
.dataTables_length select, .dataTables_filter input { 
    border:2px solid #e2e8f0; border-radius:8px; padding:6px 12px; font-size:13px; font-weight:600; color:#0f2557; outline:none; transition:.2s; margin-left: 6px;
}
.dataTables_length label, .dataTables_filter label { font-size:13px; font-weight:700; color:#334155; margin:0; display: flex; align-items: center; }
.dataTables_length select:focus, .dataTables_filter input:focus { border-color: var(--blue); }
table.dataTable.no-footer { border-bottom: none; clear: both; }
table.dataTable { border-collapse: collapse !important; width: 100% !important; background: #fff; border-radius: 10px; overflow: hidden; border: 1px solid var(--border) !important; box-shadow: 0 1px 3px rgba(0,0,0,.05); margin-top: 0 !important; margin-bottom: 0 !important; }
table.dataTable thead th { background: linear-gradient(135deg,#0f2557,#1a3fc4) !important; color: white !important; font-weight: 800 !important; font-size: 11px !important; text-transform: uppercase; text-align: left !important; padding: 13px 25px 13px 14px !important; border-bottom: none !important; border-top: none !important; letter-spacing: 0.5px; }
table.dataTable tbody td { padding: 14px !important; border-bottom: 1px solid var(--border) !important; font-size: 13px; font-weight: 700; color: var(--navy); vertical-align: middle !important; }
table.dataTable tbody tr:last-child td { border-bottom: none !important; }
table.dataTable tbody tr:hover { background:#f8fafc !important; }
.dataTables_info, .dataTables_paginate { font-size: 12px; color: var(--muted); margin: 0; }
.paginate_button { padding: 4px 10px !important; border-radius: 6px !important; font-weight: 700; border: 1px solid var(--border) !important; background: #fff !important; margin: 0 2px; cursor: pointer; }
.paginate_button.current { background: var(--navy) !important; color: #fff !important; border-color: var(--navy) !important; }
.paginate_button:hover { background: #f1f5f9 !important; color: var(--navy) !important; }

@media(max-width:768px){ .hdr{flex-direction:column;gap:10px;} }
</style>
</head>
<body>

<!-- Header Banner -->
<div class="hdr">
  <div>
    <h1><i class="fas fa-comments mr-2"></i>HR Exit Interview Portal</h1>
    <div style="color:rgba(255,255,255,.7);font-size:12px;margin-top:3px;">
      Manage exit rounds, exit questions, and conduct multi-round exit interviews.
    </div>
  </div>
  <div style="display:flex;gap:9px;flex-wrap:wrap;">
    
    <a href="hr-exit-initiation.php" class="btn-p btn-light no-print"><i class="fas fa-arrow-left"></i> Exit Initiation</a>
    <a href="hr-exit-settlement.php" class="btn-p btn-green no-print"><i class="fas fa-arrow-right"></i> Settlement</a>
  </div>
</div>

<div class="wrap">

  <!-- STAT CARDS (Matched to Digital Expenses) -->
  <div class="stat-grid">
    <div class="stat-card">
      <div class="stat-icon" style="background:#2980B9;"><i class="fas fa-clock"></i></div>
      <div>
        <h3>Pending Interviews</h3>
        <p><?php echo $stat_pending; ?></p>
      </div>
    </div>
    <div class="stat-card">
      <div class="stat-icon" style="background:#27AE60;"><i class="fas fa-check-circle"></i></div>
      <div>
        <h3>Completed</h3>
        <p><?php echo $stat_completed; ?></p>
      </div>
    </div>
    <div class="stat-card">
      <div class="stat-icon" style="background:#E67E22;"><i class="fas fa-sliders-h"></i></div>
      <div>
        <h3>Total Rounds</h3>
        <p><?php echo count($exit_rounds_list); ?></p>
      </div>
    </div>
    <div class="stat-card">
      <div class="stat-icon" style="background:#1e3a8a;"><i class="fas fa-question-circle"></i></div>
      <div>
        <h3>Total Questions</h3>
        <p><?php echo $stat_questions; ?></p>
      </div>
    </div>
  </div>

  <!-- Flash Alerts -->
  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert-ok"><i class="fas fa-check-circle"></i> <?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?></div>
  <?php endif; ?>
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert-err"><i class="fas fa-exclamation-circle"></i> <?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?></div>
  <?php endif; ?>

  <!-- Navigation Tabs -->
  <div class="nav-tabs-container">
    <a href="?tab=interviews" class="nav-btn <?php echo $main_tab == 'interviews' ? 'active' : ''; ?>">
      <i class="fas fa-user-check"></i> Conduct Exit Interviews (<?php echo $stat_pending; ?> Pending)
    </a>
    <a href="?tab=questions" class="nav-btn <?php echo $main_tab == 'questions' ? 'active' : ''; ?>">
      <i class="fas fa-sliders-h"></i> Manage Rounds &amp; Questions (<?php echo count($exit_rounds_list); ?> Rounds / <?php echo $stat_questions; ?> Qs)
    </a>
  </div>

  <!-- TAB 1: CONDUCT INTERVIEWS -->
  <?php if ($main_tab == 'interviews'): ?>

    <div style="display:flex; gap:10px; margin-bottom:16px;">
      <a href="?tab=interviews&view=pending" class="status-badge <?php echo $view=='pending' ? 's-ready' : 's-draft'; ?>" style="text-decoration:none;">
        <i class="fas fa-clock mr-1"></i> Pending Interviews (<?php echo $stat_pending; ?>)
      </a>
      <a href="?tab=interviews&view=completed" class="status-badge <?php echo $view=='completed' ? 's-accepted' : 's-draft'; ?>" style="text-decoration:none;">
        <i class="fas fa-check-circle mr-1"></i> Completed Interviews (<?php echo $stat_completed; ?>)
      </a>
    </div>

    <div class="dt-filters" id="candidatesFilters">
      <input type="date" id="candDateFrom" title="From date (LWD)">
      <input type="date" id="candDateTo" title="To date (LWD)">
      <select id="candDepartment" title="Department">
        <option value="">All — Department</option>
      </select>
      <select id="candPosition" title="Position">
        <option value="">All — Position</option>
      </select>
      <div class="dt-search-wrap"><i class="fas fa-search"></i><input type="text" id="candSearch" placeholder="Search by exit #, employee, department, position…"></div>
      <button type="button" class="dt-export-btn" onclick="exportCandidatesCSV('excel')"><i class="fas fa-file-excel"></i> Export Excel</button>
      <button type="button" class="dt-export-btn" onclick="exportCandidatesCSV('csv')"><i class="fas fa-file-csv"></i> Export CSV</button>
    </div>
    <div class="table-card">
      <div class="table-card-header">
        <h5><i class="fas fa-list mr-2"></i>Exit Interview Records</h5>
        <span id="candidatesTableCount" style="font-size:13px;color:#64748b;font-weight:600;"></span>
      </div>
      <div class="table-scroll">
      <table class="ctrack-table" id="candidatesTable">
        <thead>
          <tr>
            <th>Exit #</th>
            <th>Employee Name</th>
            <th>Department</th>
            <th>Position</th>
            <th>Current Stage</th>
            <th>Last Working Day</th>
            <th>Status</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody id="candidatesTbody">
          <?php foreach ($candidates as $row):
              $c_round_num = intval($row['current_exit_round'] ?? 1);
              $c_round_name = $exit_rounds_map[$c_round_num] ?? ('Round '.$c_round_num);
              $c_dept = $row['dept_name'] ?? '';
              $c_pos = $row['pos_title'] ?? '';
              $c_lwd_iso = !empty($row['final_last_working_day']) ? date('Y-m-d', strtotime($row['final_last_working_day'])) : '';
              $c_search = strtolower(($row['exit_number'] ?? '').' '.($row['employee_name'] ?? '').' '.$c_dept.' '.$c_pos);
          ?>
            <tr class="candidate-row" data-dept="<?php echo htmlspecialchars($c_dept); ?>" data-pos="<?php echo htmlspecialchars($c_pos); ?>" data-lwd="<?php echo $c_lwd_iso; ?>" data-search="<?php echo htmlspecialchars($c_search); ?>">
              <td><strong style="color:var(--blue);"><?php echo htmlspecialchars($row['exit_number'] ?? ''); ?></strong></td>
              <td><strong><?php echo htmlspecialchars($row['employee_name'] ?? ''); ?></strong></td>
              <td><?php echo htmlspecialchars($row['dept_name'] ?? '—'); ?></td>
              <td><?php echo htmlspecialchars($row['pos_title'] ?? '—'); ?></td>
              <td>
                <?php if ($c_round_num == 99): ?>
                  <span class="status-badge s-ready" style="background:#d1fae5;color:#065f46;">
                    <i class="fas fa-check-double mr-1"></i> All Rounds Completed
                  </span>
                <?php else: ?>
                  <span class="status-badge s-ready">
                    <i class="fas fa-layer-group mr-1"></i> Round <?php echo $c_round_num; ?>: <?php echo htmlspecialchars($c_round_name); ?>
                  </span>
                <?php endif; ?>
              </td>
              <td><?php echo !empty($row['final_last_working_day']) ? date('d M Y', strtotime($row['final_last_working_day'])) : 'Pending'; ?></td>
              <td>
                <?php if ($view == 'pending'): ?>
                  <span class="status-badge s-sent"><i class="fas fa-clock mr-1"></i> Pending</span>
                <?php else: ?>
                  <span class="status-badge s-accepted"><i class="fas fa-check-circle mr-1"></i> Completed</span>
                <?php endif; ?>
              </td>
              <td>
                <?php
                $modal_data = json_encode([
                    'exit_id'       => (int)$row['id'],
                    'employee_id'   => (int)$row['employee_id'],
                    'employee_name' => $row['employee_name'] ?? '',
                    'current_round' => $c_round_num,
                    'is_completed'  => ($view == 'completed'),
                ]);
                ?>
                <div style="display:flex; gap:6px; flex-wrap:wrap; align-items:center;">
                <button class="btn-p btn-navy" style="padding:6px 14px; font-size:12px;" onclick='openInterviewModal(<?php echo htmlspecialchars($modal_data, ENT_QUOTES); ?>)'>
                  <?php if ($view == 'completed'): ?>
                    <i class="fas fa-edit"></i> View / Edit Answers
                  <?php else: ?>
                    <i class="fas fa-comments"></i> Conduct Round <?php echo $c_round_num; ?>
                  <?php endif; ?>
                </button>
                <button class="btn-p btn-light" style="padding:6px 12px; font-size:12px; border:1px solid #e2e8f0; color:#0f2557;" onclick="openInterviewHistoryModal(<?php echo (int)$row['id']; ?>, '<?php echo htmlspecialchars($row['employee_name'] ?? '', ENT_QUOTES); ?>')" title="View History">
                  <i class="fas fa-history"></i> History
                </button>
                <?php if ($view == 'completed'): ?>
                <button class="btn-p btn-green" style="padding:6px 14px; font-size:12px;" onclick="openSettlementModal(<?php echo (int)$row['id']; ?>, '<?php echo htmlspecialchars($row['employee_name'] ?? '', ENT_QUOTES); ?>', '<?php echo htmlspecialchars($row['final_last_working_day'] ?? '', ENT_QUOTES); ?>')">
                  <i class="fas fa-file-invoice-dollar mr-1"></i> Enter Settlement
                </button>
                <?php endif; ?>
                </div>
              </td>
            </tr>
          <?php endforeach; ?>
          <?php if (empty($candidates)): ?><tr><td colspan="8" class="ctrack-empty">No candidate records found.</td></tr><?php endif; ?>
          <tr id="candidatesNoResultsRow" style="display:none;"><td colspan="8" class="ctrack-empty">No matching records found.</td></tr>
        </tbody>
      </table>
      </div>
      <div class="paging-wrap">
        <div class="paging-info" id="candidatesPagingInfo"></div>
        <div class="paging-btns" id="candidatesPagingBtns"></div>
      </div>
    </div>

  <!-- TAB 2: MANAGE ROUNDS & QUESTIONS -->
  <?php else: ?>

    <div style="display:flex; gap:10px; margin-bottom:16px;">
      <a href="?tab=questions&sub=rounds" class="status-badge <?php echo $sub_tab=='rounds' ? 's-ready' : 's-draft'; ?>" style="text-decoration:none;">
        <i class="fas fa-layer-group mr-1"></i> Manage Exit Rounds (<?php echo count($exit_rounds_list); ?>)
      </a>
      <a href="?tab=questions&sub=questions" class="status-badge <?php echo $sub_tab=='questions' ? 's-ready' : 's-draft'; ?>" style="text-decoration:none;">
        <i class="fas fa-question-circle mr-1"></i> Manage Exit Questions (<?php echo $stat_questions; ?>)
      </a>
    </div>

    <!-- SUB-TAB 2A: MANAGE EXIT ROUNDS -->
    <?php if ($sub_tab == 'rounds'): ?>

      <div class="card-s" style="margin-bottom:16px; padding:16px 24px;">
        <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
          <div>
            <div class="sec-lbl" style="margin:0; padding:0; border:none;"><i class="fas fa-layer-group"></i> Configured Exit Interview Rounds</div>
            <small class="text-muted">Create, edit, and order custom exit interview rounds.</small>
          </div>
          <div>
            <button class="btn-p btn-green" style="padding:8px 16px; font-size:12px;" data-toggle="modal" data-target="#addRoundModal"><i class="fas fa-plus"></i> Create Exit Round</button>
          </div>
        </div>
      </div>

      <div class="card-s">
        <table class="table table-hover dataTable" id="roundsTable">
          <thead>
            <tr>
              <th style="width:100px;">Round #</th>
              <th>Round Name</th>
              <th>Description</th>
              <th>Created By</th>
              <th style="width:120px;">Actions</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($exit_rounds_list as $r_item): ?>
              <tr>
                <td>
                  <span class="status-badge s-ready">
                    <i class="fas fa-layer-group mr-1"></i> Round <?php echo intval($r_item['round_number']); ?>
                  </span>
                </td>
                <td><strong style="color:#0f172a; font-size:14px;"><?php echo htmlspecialchars($r_item['round_name']); ?></strong></td>
                <td><span class="text-muted"><?php echo htmlspecialchars($r_item['description'] ?: '—'); ?></span></td>
                <td><small class="text-muted"><?php echo htmlspecialchars($r_item['created_by'] ?: 'Admin'); ?></small></td>
                <td>
                  <button type="button" class="btn-p btn-light" style="padding:4px 10px; font-size:12px;" onclick='editRoundModal(<?php echo json_encode($r_item); ?>)' title="Edit Round"><i class="fas fa-edit"></i> Edit</button>
                  <button type="button" class="btn-p btn-light" style="padding:4px 10px; font-size:12px; color:#ef4444;" onclick="if(confirm('Delete Round <?php echo $r_item['round_number']; ?>? Questions in this round may need reassigning.')){document.getElementById('dr_<?php echo $r_item['id']; ?>').submit();}" title="Delete Round"><i class="fas fa-trash"></i></button>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
        
        <!-- Hidden Delete Round Forms -->
        <?php foreach ($exit_rounds_list as $r_item): ?>
          <form id="dr_<?php echo $r_item['id']; ?>" method="POST" style="display:none;">
            <input type="hidden" name="action" value="delete_exit_round">
            <input type="hidden" name="id" value="<?php echo $r_item['id']; ?>">
          </form>
        <?php endforeach; ?>
      </div>

    <!-- SUB-TAB 2B: MANAGE QUESTIONS -->
    <?php else: ?>

      <div class="card-s" style="margin-bottom:16px; padding:16px 24px;">
        <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
          <div>
            <div class="sec-lbl" style="margin:0; padding:0; border:none;"><i class="fas fa-list-ol"></i> Exit Interview Questions</div>
            <small class="text-muted">Questions linked to user-configured exit interview rounds.</small>
          </div>
          <div style="display:flex; gap:8px; flex-wrap:wrap;">
            <button type="button" class="btn-p btn-warn" id="bulkDeleteBtn" style="display:none; padding:8px 16px; font-size:12px; background:#ef4444; color:#fff;" onclick="bulkDeleteQuestions()"><i class="fas fa-trash-alt"></i> Delete Selected</button>
            <button class="btn-p btn-green" style="padding:8px 16px; font-size:12px;" data-toggle="modal" data-target="#addQuestionModal"><i class="fas fa-plus"></i> Add Question</button>
            <a href="?action=export_questions" class="btn-p btn-navy" style="padding:8px 16px; font-size:12px;"><i class="fas fa-file-download"></i> Export CSV</a>
            <button class="btn-p btn-warn" style="padding:8px 16px; font-size:12px;" data-toggle="modal" data-target="#importQuestionsModal"><i class="fas fa-file-upload"></i> Import CSV</button>
          </div>
        </div>
      </div>

      <div class="card-s">
        <form id="bulkForm" method="POST">
          <input type="hidden" name="action" value="delete_questions_bulk">
          <table class="table table-hover dataTable" id="questionsTable">
            <thead>
              <tr>
                <th style="width:40px;"><input type="checkbox" id="selAll"></th>
                <th style="width:160px;">Assigned Round</th>
                <th style="width:70px;">Sort</th>
                <th>Question Text</th>
                <th>Input Type</th>
                <th>Options</th>
                <th style="width:110px;">Actions</th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($questions_list as $row):
                  $opts_arr = (!empty($row['options_json'])) ? (json_decode($row['options_json'], true) ?: []) : [];
                  $r_num = intval($row['round_number'] ?? 1);
                  $r_name = $exit_rounds_map[$r_num] ?? ('Round '.$r_num);
              ?>
                <tr>
                  <td><input type="checkbox" name="ids[]" class="qchk" value="<?php echo $row['id']; ?>"></td>
                  <td>
                    <span class="status-badge s-ready">
                      <i class="fas fa-layer-group mr-1"></i> Round <?php echo $r_num; ?>: <?php echo htmlspecialchars($r_name); ?>
                    </span>
                  </td>
                  <td><strong><?php echo intval($row['sort_order']); ?></strong></td>
                  <td><strong style="color:#0f172a; font-size:13.5px;"><?php echo htmlspecialchars($row['question_text']); ?></strong></td>
                  <td><span class="status-badge s-draft"><?php echo htmlspecialchars(ucfirst($row['input_type'])); ?></span></td>
                  <td><small class="text-muted"><?php echo !empty($opts_arr) ? htmlspecialchars(implode(', ', $opts_arr)) : '—'; ?></small></td>
                  <td>
                    <button type="button" class="btn-p btn-light" style="padding:4px 10px; font-size:12px;" onclick='editQuestionModal(<?php echo json_encode($row); ?>)' title="Edit"><i class="fas fa-edit"></i></button>
                    <button type="button" class="btn-p btn-light" style="padding:4px 10px; font-size:12px; color:#ef4444;" onclick="if(confirm('Delete this question?')){document.getElementById('dq<?php echo $row['id']; ?>').submit();}" title="Delete"><i class="fas fa-trash"></i></button>
                  </td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </form>
        
        <!-- Hidden Single Delete Forms -->
        <?php foreach ($questions_list as $row): ?>
          <form id="dq<?php echo $row['id']; ?>" method="POST" style="display:none;">
            <input type="hidden" name="action" value="delete_question">
            <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
          </form>
        <?php endforeach; ?>
      </div>

    <?php endif; ?>

  <?php endif; ?>

</div><!-- /wrap -->

<!-- MODAL 1: CONDUCT INTERVIEW FORM -->
<div class="modal fade" id="interviewModal" tabindex="-1" role="dialog" aria-hidden="true" data-backdrop="static">
  <div class="modal-dialog modal-lg" role="document" style="max-width:820px;">
    <div class="modal-content" style="border-radius:14px; border:none;">
      <form method="POST" id="interviewForm">
        <input type="hidden" name="action"      id="form_action"    value="save_interview">
        <input type="hidden" name="exit_id"     id="int_exit_id">
        <input type="hidden" name="employee_id" id="int_employee_id">
        
        <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
          <h5 class="modal-title" style="font-weight:700; color:#fff;"><i class="fas fa-comments mr-2"></i>Exit Interview: <span id="int_emp_name"></span></h5>
          <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
        </div>
        
        <div class="modal-body" style="padding:24px; max-height: calc(100vh - 220px); overflow-y: auto;">
          <div id="loadingQ" class="text-center py-4">
            <i class="fas fa-spinner fa-spin fa-2x text-muted mb-2"></i>
            <p class="text-muted font-weight-700">Loading round questions...</p>
          </div>
          <div id="questionsContainer" style="display:none;"></div>
        </div>
        
        <div class="modal-footer">
          <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
          <button type="button" class="btn-p btn-navy" onclick="doSubmitInterview('save_interview')"><i class="fas fa-save"></i> Save Draft</button>
          <button type="button" class="btn-p btn-green" id="btnNextRound" onclick="submitRoundAction()"><i class="fas fa-arrow-right"></i> Complete &amp; Next Round</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- MODAL 2A: ADD ROUND -->
<div class="modal fade" id="addRoundModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:14px; border:none;">
    <form method="POST">
      <input type="hidden" name="action" value="add_exit_round">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-layer-group mr-2"></i>Create Exit Interview Round</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div class="grid2">
          <div class="fg">
            <label class="fl">Round Number <span class="text-danger">*</span></label>
            <input type="number" name="round_number" class="fc" value="<?php echo count($exit_rounds_list)+1; ?>" min="1" required>
          </div>
          <div class="fg">
            <label class="fl">Round Name <span class="text-danger">*</span></label>
            <input type="text" name="round_name" class="fc" placeholder="e.g. HR Clearance Round" required>
          </div>
        </div>
        <div class="fg">
          <label class="fl">Description (Optional)</label>
          <textarea name="description" class="fc" rows="2" placeholder="Brief details about what is evaluated in this round..."></textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <button type="submit" class="btn-p btn-green">Create Round</button>
      </div>
    </form>
  </div></div>
</div>

<!-- MODAL 2B: EDIT ROUND -->
<div class="modal fade" id="editRoundModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:14px; border:none;">
    <form method="POST">
      <input type="hidden" name="action" value="edit_exit_round">
      <input type="hidden" name="id" id="edit_r_id">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-edit mr-2"></i>Edit Exit Round</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div class="grid2">
          <div class="fg">
            <label class="fl">Round Number <span class="text-danger">*</span></label>
            <input type="number" name="round_number" id="edit_r_num" class="fc" min="1" required>
          </div>
          <div class="fg">
            <label class="fl">Round Name <span class="text-danger">*</span></label>
            <input type="text" name="round_name" id="edit_r_name" class="fc" required>
          </div>
        </div>
        <div class="fg">
          <label class="fl">Description</label>
          <textarea name="description" id="edit_r_desc" class="fc" rows="2"></textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <button type="submit" class="btn-p btn-warn">Update Round</button>
      </div>
    </form>
  </div></div>
</div>

<!-- MODAL 3: ADD QUESTION -->
<div class="modal fade" id="addQuestionModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg"><div class="modal-content" style="border-radius:14px; border:none;">
    <form method="POST">
      <input type="hidden" name="action" value="add_question">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-plus-circle mr-2"></i>Add Exit Interview Question</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div class="grid2" style="margin-bottom:14px;">
          <div class="fg" style="margin:0;">
            <label class="fl">Select Exit Round <span class="text-danger">*</span></label>
            <select name="round_number" class="fc" required>
              <?php foreach ($exit_rounds_list as $r_item): ?>
                <option value="<?php echo $r_item['round_number']; ?>">
                  Round <?php echo $r_item['round_number']; ?> (<?php echo htmlspecialchars($r_item['round_name']); ?>)
                </option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="fg" style="margin:0;">
            <label class="fl">Sort Order</label>
            <input type="number" name="sort_order" class="fc" value="0">
          </div>
        </div>
        <div class="fg">
          <label class="fl">Question Text <span class="text-danger">*</span></label>
          <textarea name="question_text" class="fc" rows="3" placeholder="e.g. What factor contributed most to your decision to leave?" required></textarea>
        </div>
        <div class="fg">
          <label class="fl">Input Type</label>
          <select name="input_type" class="fc" onchange="toggleOptionsWrap(this.value, 'add_opts_wrap')">
            <option value="text">Short Text</option>
            <option value="textarea">Long Text (Paragraph)</option>
            <option value="select">Dropdown (Select)</option>
            <option value="radio">Radio Buttons (Single Choice)</option>
            <option value="checkbox">Checkboxes (Multiple Choice)</option>
          </select>
        </div>
        <div class="fg" id="add_opts_wrap" style="display:none;">
          <label class="fl">Options (Comma separated) <span class="text-danger">*</span></label>
          <input type="text" name="options_csv" class="fc" placeholder="e.g. Excellent, Good, Average, Poor">
          <small class="text-muted">Required for Dropdown, Radio, or Checkbox input types.</small>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <button type="submit" class="btn-p btn-green">Save Question</button>
      </div>
    </form>
  </div></div>
</div>

<!-- MODAL 4: EDIT QUESTION -->
<div class="modal fade" id="editQuestionModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg"><div class="modal-content" style="border-radius:14px; border:none;">
    <form method="POST">
      <input type="hidden" name="action" value="edit_question">
      <input type="hidden" name="id" id="edit_id">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-edit mr-2"></i>Edit Question</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div class="grid2" style="margin-bottom:14px;">
          <div class="fg" style="margin:0;">
            <label class="fl">Select Exit Round</label>
            <select name="round_number" id="edit_round" class="fc" required>
              <?php foreach ($exit_rounds_list as $r_item): ?>
                <option value="<?php echo $r_item['round_number']; ?>">
                  Round <?php echo $r_item['round_number']; ?> (<?php echo htmlspecialchars($r_item['round_name']); ?>)
                </option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="fg" style="margin:0;">
            <label class="fl">Sort Order</label>
            <input type="number" name="sort_order" id="edit_sort" class="fc">
          </div>
        </div>
        <div class="fg">
          <label class="fl">Question Text <span class="text-danger">*</span></label>
          <textarea name="question_text" id="edit_text" class="fc" rows="3" required></textarea>
        </div>
        <div class="fg">
          <label class="fl">Input Type</label>
          <select name="input_type" id="edit_type" class="fc" onchange="toggleOptionsWrap(this.value, 'edit_opts_wrap')">
            <option value="text">Short Text</option>
            <option value="textarea">Long Text (Paragraph)</option>
            <option value="select">Dropdown (Select)</option>
            <option value="radio">Radio Buttons (Single Choice)</option>
            <option value="checkbox">Checkboxes (Multiple Choice)</option>
          </select>
        </div>
        <div class="fg" id="edit_opts_wrap" style="display:none;">
          <label class="fl">Options (Comma separated)</label>
          <input type="text" name="options_csv" id="edit_options_val" class="fc">
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <button type="submit" class="btn-p btn-warn">Update Question</button>
      </div>
    </form>
  </div></div>
</div>

<!-- MODAL 5: IMPORT CSV -->
<div class="modal fade" id="importQuestionsModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:14px; border:none;">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="import_questions">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-file-upload mr-2"></i>Import Questions from CSV</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div class="mb-4 text-center">
          <a href="?action=download_template" class="btn-p btn-light" style="padding:8px 16px; font-size:12px;"><i class="fas fa-download"></i> Download CSV Template</a>
        </div>
        <div class="fg">
          <label class="fl">Select CSV File</label>
          <input type="file" name="import_file" class="fc" accept=".csv" required>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <button type="submit" class="btn-p btn-warn">Import Questions</button>
      </div>
    </form>
  </div></div>
</div>

<!-- MODAL: INTERVIEW HISTORY -->
<div class="modal fade" id="interviewHistoryModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg" style="max-width:760px;">
    <div class="modal-content" style="border-radius:14px; border:none;">
      <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff; border-radius:14px 14px 0 0;">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-history mr-2"></i>Interview History: <span id="hist_emp_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <div class="modal-body" style="padding:24px; max-height:calc(100vh - 220px); overflow-y:auto;">
        <div id="historyLoading" class="text-center py-4">
          <i class="fas fa-spinner fa-spin fa-2x text-muted mb-2"></i>
          <p class="text-muted">Loading history...</p>
        </div>
        <div id="historyContent" style="display:none;"></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<!-- MODAL: FULL & FINAL SETTLEMENT ENTRY -->
<div class="modal fade" id="settlementEntryModal" tabindex="-1" role="dialog" aria-hidden="true" data-backdrop="static">
  <div class="modal-dialog" style="max-width:820px;" role="document">
    <div class="modal-content" style="border-radius:14px; border:none;">
      <div class="modal-header" style="background:linear-gradient(135deg,#065f46,#10b981); color:#fff; border-radius:14px 14px 0 0; padding:16px 22px;">
        <h5 class="modal-title" style="color:#fff; font-weight:800;"><i class="fas fa-file-invoice-dollar mr-2"></i>Full &amp; Final Settlement — <span id="stl_emp_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff; opacity:.9;">&times;</button>
      </div>
      <!-- Tab Bar -->
      <div style="display:flex; border-bottom:2px solid #e2e8f0; background:#f8fafc;">
        <button type="button" id="stlTabEditBtn" onclick="switchStlTab('edit')" style="padding:11px 22px; font-weight:700; font-size:13px; border:none; background:transparent; border-bottom:3px solid #10b981; color:#065f46;">
          <i class="fas fa-edit mr-1"></i> Enter Settlement
        </button>
        <button type="button" id="stlTabPreviewBtn" onclick="switchStlTab('preview')" style="padding:11px 22px; font-weight:700; font-size:13px; border:none; background:transparent; border-bottom:3px solid transparent; color:#94a3b8;">
          <i class="fas fa-eye mr-1"></i> Preview Document
        </button>
      </div>
      <div class="modal-body" style="padding:24px; max-height:calc(100vh - 260px); overflow-y:auto;">
        <input type="hidden" id="stl_exit_id">

        <!-- EDIT PANEL -->
        <div id="stlEditPanel">
          <div class="row">
            <div class="col-md-6">
              <div class="fg"><label class="fl">Last Working Day</label><input type="date" id="stl_lwd" class="fc"></div>
            </div>
            <div class="col-md-6">
              <div class="fg"><label class="fl">Payment Within (Days)</label><input type="number" id="stl_pwd" class="fc" value="30" min="1"></div>
            </div>
          </div>

          <!-- EARNINGS -->
          <div style="font-weight:800; color:#065f46; font-size:13px; margin:16px 0 10px; padding-bottom:6px; border-bottom:2px solid #d1fae5;"><i class="fas fa-plus-circle mr-1"></i> Earnings</div>
          <div class="row" id="stlFixedEarnings">
            <div class="col-md-6"><div class="fg"><label class="fl">Pending Salary (₹)</label><input type="number" step="0.01" id="stl_ps" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl">Leave Encashment (₹)</label><input type="number" step="0.01" id="stl_le" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl">Bonus / Incentive (₹)</label><input type="number" step="0.01" id="stl_bi" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl">Gratuity (₹)</label><input type="number" step="0.01" id="stl_ga" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl">Pension (₹)</label><input type="number" step="0.01" id="stl_pa" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl">Severance / Notice Pay (₹)</label><input type="number" step="0.01" id="stl_sp" class="fc stl-amt" placeholder="0.00"></div></div>
          </div>
          <!-- Custom Earnings -->
          <div id="stlCustomEarningsWrap"></div>
          <button type="button" onclick="addStlRow('earning')" style="background:#d1fae5;color:#065f46;border:1.5px dashed #6ee7b7;border-radius:8px;padding:6px 14px;font-size:12px;font-weight:700;cursor:pointer;margin-bottom:14px;"><i class="fas fa-plus mr-1"></i> Add Custom Earning</button>

          <!-- DEDUCTIONS -->
          <div style="font-weight:800; color:#991b1b; font-size:13px; margin:16px 0 10px; padding-bottom:6px; border-bottom:2px solid #fee2e2;"><i class="fas fa-minus-circle mr-1"></i> Deductions</div>
          <div class="row" id="stlFixedDeductions">
            <div class="col-md-6"><div class="fg"><label class="fl" style="color:#991b1b;">Loan Recovery (₹)</label><input type="number" step="0.01" id="stl_lr" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl" style="color:#991b1b;">Notice Shortfall Deduction (₹)</label><input type="number" step="0.01" id="stl_nsd" class="fc stl-amt" placeholder="0.00"></div></div>
            <div class="col-md-6"><div class="fg"><label class="fl" style="color:#991b1b;">Other Deductions (₹)</label><input type="number" step="0.01" id="stl_od" class="fc stl-amt" placeholder="0.00"></div></div>
          </div>
          <!-- Custom Deductions -->
          <div id="stlCustomDeductionsWrap"></div>
          <button type="button" onclick="addStlRow('deduction')" style="background:#fee2e2;color:#991b1b;border:1.5px dashed #fca5a5;border-radius:8px;padding:6px 14px;font-size:12px;font-weight:700;cursor:pointer;margin-bottom:14px;"><i class="fas fa-plus mr-1"></i> Add Custom Deduction</button>

          <!-- NET -->
          <div style="background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; border-radius:10px; padding:14px 20px; display:flex; justify-content:space-between; align-items:center; margin:8px 0 16px;">
            <span style="font-weight:800; font-size:15px;"><i class="fas fa-rupee-sign mr-1"></i> Net Payable (Auto-Calculated)</span>
            <span id="stl_net_display" style="font-size:22px; font-weight:900;">₹ 0.00</span>
          </div>

          <div class="fg"><label class="fl">Notes</label><textarea id="stl_notes" class="fc" rows="2" placeholder="Any additional notes..."></textarea></div>
        </div>

        <!-- PREVIEW PANEL -->
        <div id="stlPreviewPanel" style="display:none;">
          <div id="stlPreviewContent" style="min-height:200px;"></div>
        </div>
      </div>

      <div class="modal-footer" style="justify-content:space-between; flex-wrap:wrap; gap:8px;">
        <button type="button" class="btn-p btn-light" data-dismiss="modal">Close</button>
        <div style="display:flex; gap:8px; flex-wrap:wrap;">
          <button type="button" class="btn-p btn-navy" onclick="saveSettlement(0)"><i class="fas fa-save mr-1"></i> Save Settlement</button>
          <button type="button" class="btn-p" style="background:linear-gradient(135deg,#065f46,#10b981);" onclick="saveSettlement(0, true)"><i class="fas fa-eye mr-1"></i> Save &amp; Preview</button>
          <button type="button" class="btn-p" style="background:linear-gradient(135deg,#7c3aed,#a78bfa);" onclick="finalizeSettlement()"><i class="fas fa-check-double mr-1"></i> Finalize → Move to Documents</button>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- Scripts -->
<!-- Custom Toast Notification -->
<div id="customToast" style="position:fixed; top:24px; right:-350px; width:300px; background:#fff; border-left:5px solid #10b981; border-radius:10px; box-shadow:0 10px 40px rgba(0,0,0,0.15); padding:16px 20px; z-index:9999; transition:right 0.4s cubic-bezier(0.175,0.885,0.32,1.275); display:flex; align-items:center; gap:12px;">
  <div id="toastIcon" style="background:#d1fae5; color:#065f46; width:36px; height:36px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:16px; flex-shrink:0;">
    <i class="fas fa-check"></i>
  </div>
  <div style="flex:1;">
    <div id="toastTitle" style="font-weight:800; color:#0f2557; font-size:14px; margin-bottom:2px;">Success</div>
    <div id="toastMsg" style="font-size:12.5px; color:#64748b; font-weight:600; line-height:1.4;">Saved successfully</div>
  </div>
</div>

<!-- Custom Confirm Modal -->
<div class="modal fade" id="customConfirmModal" tabindex="-1" role="dialog" style="z-index:99999;">
  <div class="modal-dialog modal-sm modal-dialog-centered" role="document">
    <div class="modal-content" style="border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,0.2);">
      <div class="modal-body text-center" style="padding:28px 20px;">
        <div style="background:#fee2e2; color:#dc2626; width:64px; height:64px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:28px; margin:0 auto 16px;">
          <i class="fas fa-exclamation-triangle"></i>
        </div>
        <h5 style="font-weight:800; color:#0f2557; margin-bottom:10px;">Are you sure?</h5>
        <p id="confirmMsg" style="font-size:13.5px; color:#64748b; margin-bottom:20px;">Do you want to proceed?</p>
        <div style="display:flex; gap:10px; justify-content:center;">
          <button type="button" class="btn-p btn-light" data-dismiss="modal" style="flex:1; justify-content:center;">Cancel</button>
          <button type="button" class="btn-p btn-navy" id="confirmOkBtn" style="flex:1; justify-content:center; background:linear-gradient(135deg,#7c3aed,#a78bfa);">Finalize</button>
        </div>
      </div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script>
function buildCtrackPageRange(current, max) {
    if (max <= 7) return Array.from({length: max}, function(_, i) { return i + 1; });
    var pages = [1];
    if (current > 3) pages.push('…');
    for (var i = Math.max(2, current - 1); i <= Math.min(max - 1, current + 1); i++) pages.push(i);
    if (current < max - 2) pages.push('…');
    pages.push(max);
    return pages;
}

function ctrackDownloadCSV(filename, headers, rows) {
    var csv = [headers.join(',')];
    rows.forEach(function(r) {
        csv.push(r.map(function(v) { return '"' + String(v == null ? '' : v).replace(/"/g, '""').trim() + '"'; }).join(','));
    });
    var blob = new Blob(['﻿' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
}

function ctrackDownloadExcelHtml(filename, headers, rows) {
    var html = '<table border="1"><tr>' + headers.map(function(h) { return '<th>' + h + '</th>'; }).join('') + '</tr>';
    rows.forEach(function(r) {
        html += '<tr>' + r.map(function(v) { return '<td>' + (v == null ? '' : String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;')) + '</td>'; }).join('') + '</tr>';
    });
    html += '</table>';
    var blob = new Blob(['﻿' + html], { type: 'application/vnd.ms-excel' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
}

$(document).ready(function(){
    if ($('#candidatesTable').length > 0) {
        var candPage = 1, candPageSize = 25;

        var candDepts = [], candPositions = [];
        $('#candidatesTbody .candidate-row').each(function() {
            var d = $(this).data('dept'), p = $(this).data('pos');
            if (d && candDepts.indexOf(d) === -1) candDepts.push(d);
            if (p && candPositions.indexOf(p) === -1) candPositions.push(p);
        });
        candDepts.sort().forEach(function(v) { $('#candDepartment').append('<option value="' + v + '">' + v + '</option>'); });
        candPositions.sort().forEach(function(v) { $('#candPosition').append('<option value="' + v + '">' + v + '</option>'); });

        function getVisibleCandidateRows() {
            var dateFrom = $('#candDateFrom').val();
            var dateTo   = $('#candDateTo').val();
            var dept     = $('#candDepartment').val();
            var pos      = $('#candPosition').val();
            var search   = $('#candSearch').val().toLowerCase().trim();
            return $('#candidatesTbody .candidate-row').filter(function() {
                var $r = $(this);
                var lwd = $r.data('lwd') ? String($r.data('lwd')) : '';
                if (dept && String($r.data('dept')) !== dept) return false;
                if (pos && String($r.data('pos')) !== pos) return false;
                if (dateFrom && (!lwd || lwd < dateFrom)) return false;
                if (dateTo && (!lwd || lwd > dateTo)) return false;
                if (search && String($r.data('search') || '').indexOf(search) === -1) return false;
                return true;
            });
        }

        function renderCandidatesTable() {
            var rows = getVisibleCandidateRows();
            var total = rows.length;
            var maxPage = Math.max(1, Math.ceil(total / candPageSize));
            if (candPage > maxPage) candPage = maxPage;
            var start = (candPage - 1) * candPageSize, end = start + candPageSize;

            $('#candidatesTbody .candidate-row').hide();
            rows.slice(start, end).show();

            $('#candidatesNoResultsRow').toggle(total === 0);
            $('#candidatesTableCount').text(total + (total === 1 ? ' record' : ' records'));
            $('#candidatesPagingInfo').text(total === 0 ? 'No results' : 'Showing ' + (start + 1) + '–' + Math.min(end, total) + ' of ' + total);

            var $btns = $('#candidatesPagingBtns').empty();
            if (maxPage <= 1) return;
            buildCtrackPageRange(candPage, maxPage).forEach(function(p) {
                var $btn = $('<button type="button" class="paging-btn"></button>').text(p);
                if (p === candPage) $btn.addClass('active');
                if (p === '…') { $btn.prop('disabled', true); }
                else { $btn.on('click', function() { candPage = p; renderCandidatesTable(); }); }
                $btns.append($btn);
            });
        }

        $('#candDateFrom, #candDateTo, #candDepartment, #candPosition').on('change', function() { candPage = 1; renderCandidatesTable(); });
        $('#candSearch').on('input', function() { candPage = 1; renderCandidatesTable(); });

        window.exportCandidatesCSV = function(kind) {
            var headers = ['Exit #', 'Employee Name', 'Department', 'Position', 'Last Working Day', 'Status'];
            var rows = getVisibleCandidateRows().get().map(function(el) {
                var $r = $(el);
                return [$r.find('td').eq(0).text().trim(), $r.find('td').eq(1).text().trim(), $r.data('dept') || '—', $r.data('pos') || '—', $r.find('td').eq(5).text().trim(), $r.find('td').eq(6).text().trim()];
            });
            if (kind === 'excel') ctrackDownloadExcelHtml('Exit_Interviews.xls', headers, rows);
            else ctrackDownloadCSV('Exit_Interviews.csv', headers, rows);
        };

        renderCandidatesTable();
    }
    if ($('#roundsTable').length > 0) {
        $('#roundsTable').DataTable({
            dom: 'rt<"table-filter-bar"lf><"table-footer-bar"ip>',
            pageLength: 25,
            order: [[0, 'asc']],
            language: { emptyTable: 'No rounds created yet.', search: 'Search:', lengthMenu: 'Show _MENU_ entries' }
        });
    }
    if ($('#questionsTable').length > 0) {
        $('#questionsTable').DataTable({
            dom: 'rt<"table-filter-bar"lf><"table-footer-bar"ip>',
            pageLength: 25,
            columnDefs: [{ orderable: false, targets: [0, 6] }],
            order: [[1, 'asc']],
            language: { emptyTable: 'No questions configured.', search: 'Search:', lengthMenu: 'Show _MENU_ entries' }
        });
    }
    
    $('#selAll').on('click', function() {
        $('.qchk').prop('checked', this.checked);
        toggleBulkBtn();
    });
    $(document).on('click', '.qchk', function() {
        if (!this.checked) $('#selAll').prop('checked', false);
        toggleBulkBtn();
    });
});

function toggleBulkBtn() {
    $('#bulkDeleteBtn').toggle($('.qchk:checked').length > 0);
}

function bulkDeleteQuestions() {
    if (confirm('Delete all selected questions?')) {
        $('#bulkForm').submit();
    }
}

function editRoundModal(data) {
    $('#edit_r_id').val(data.id);
    $('#edit_r_num').val(data.round_number);
    $('#edit_r_name').val(data.round_name);
    $('#edit_r_desc').val(data.description || '');
    $('#editRoundModal').modal('show');
}

function toggleOptionsWrap(val, wrapId) {
    var show = ['select','radio','checkbox'].includes(val);
    document.getElementById(wrapId).style.display = show ? 'block' : 'none';
}

function editQuestionModal(data) {
    $('#edit_id').val(data.id);
    $('#edit_round').val(data.round_number || 1);
    $('#edit_text').val(data.question_text);
    $('#edit_type').val(data.input_type);
    $('#edit_sort').val(data.sort_order);
    toggleOptionsWrap(data.input_type, 'edit_opts_wrap');
    
    if (['select','radio','checkbox'].includes(data.input_type) && data.options_json) {
        try {
            var opts = JSON.parse(data.options_json);
            $('#edit_options_val').val(Array.isArray(opts) ? opts.join(', ') : '');
        } catch(e) { $('#edit_options_val').val(''); }
    } else {
        $('#edit_options_val').val('');
    }
    $('#editQuestionModal').modal('show');
}

function openInterviewModal(data) {
    $('#int_exit_id').val(data.exit_id);
    $('#int_employee_id').val(data.employee_id);
    $('#int_emp_name').text(data.employee_name);
    
    $('#interviewModal').modal('show');
    switchInterviewRound(data.exit_id, data.current_round || 1);
}

function switchInterviewRound(exitId, roundNum) {
    $('#loadingQ').show();
    $('#questionsContainer').hide().html('');
    
    $.ajax({
        url: '?fetch_interview_questions=1&exit_id=' + exitId + '&round_number=' + roundNum,
        method: 'GET',
        success: function(html) {
            $('#loadingQ').hide();
            $('#questionsContainer').html(html).show();
            
            var isLast = $('#ajax_is_last_round').val() === '1';
            var activeR = $('#ajax_active_round').val();
            var nextR = $('#ajax_next_round').val();
            
            if (isLast) {
                $('#btnNextRound').html('<i class="fas fa-check-circle mr-1"></i> Complete Exit Interview & Move to Settlement').removeClass('btn-navy').addClass('btn-green').data('action', 'complete_interview');
            } else {
                $('#btnNextRound').html('<i class="fas fa-arrow-right mr-1"></i> Complete Round ' + activeR + ' & Proceed to Round ' + nextR).removeClass('btn-green').addClass('btn-navy').data('action', 'complete_round_next');
            }
        },
        error: function() {
            $('#loadingQ').hide();
            $('#questionsContainer').html('<div class="alert-err">Error loading round questions.</div>').show();
        }
    });
}

function submitRoundAction() {
    var act = $('#btnNextRound').data('action') || 'complete_round_next';
    doSubmitInterview(act);
}

function doSubmitInterview(action) {
    if (action === 'complete_interview') {
        if (!confirm('Mark all Exit Interview rounds as completed? Candidate will move to Settlement phase.')) return;
    }
    $('#form_action').val(action);
    $('#interviewForm').submit();
}

function openInterviewHistoryModal(exitId, empName) {
    $('#hist_emp_name').text(empName);
    $('#historyLoading').show();
    $('#historyContent').hide().html('');
    $('#interviewHistoryModal').modal('show');

    $.ajax({
        url: '?fetch_interview_history=1&exit_id=' + exitId,
        method: 'GET',
        success: function(data) {
            $('#historyLoading').hide();
            var html = '';
            if (!data || data.length === 0) {
                html = '<div class="alert-err"><i class="fas fa-info-circle mr-1"></i> No interview history found for this employee.</div>';
            } else {
                $.each(data, function(i, round) {
                    html += '<div style="margin-bottom:22px;">';
                    html += '<div style="font-weight:800; font-size:14px; color:#0f2557; margin-bottom:10px; padding-bottom:8px; border-bottom:2px solid #eef2ff;">';
                    html += '<i class="fas fa-layer-group mr-1" style="color:#1a3fc4;"></i> Round ' + round.round_number + ': ' + round.round_name;
                    html += ' <span style="font-size:11px; color:#64748b; font-weight:600; margin-left:8px;">Completed by <strong>' + round.submitted_by + '</strong> on <em>' + round.submitted_at + '</em></span>';
                    html += '</div>';
                    if (round.answers && round.answers.length > 0) {
                        $.each(round.answers, function(j, ans) {
                            html += '<div style="background:#f8fafc; padding:12px 16px; border-radius:8px; border-left:4px solid #1a3fc4; margin-bottom:10px;">';
                            html += '<div style="font-weight:700; color:#0f172a; font-size:13px; margin-bottom:4px;">' + (j+1) + '. ' + ans.question_text + '</div>';
                            html += '<div style="color:#334155; font-size:13px;">' + (ans.answer_text || '<em class="text-muted">No answer provided</em>') + '</div>';
                            html += '</div>';
                        });
                    } else {
                        html += '<div class="text-muted" style="font-size:13px;"><i class="fas fa-info-circle mr-1"></i> No answers recorded for this round.</div>';
                    }
                    html += '</div>';
                });
            }
            $('#historyContent').html(html).show();
        },
        error: function() {
            $('#historyLoading').hide();
            $('#historyContent').html('<div class="alert-err">Error loading history.</div>').show();
        },
        dataType: 'json'
    });
}

// =========================================================
// SETTLEMENT MODAL JS
// =========================================================
var stlCustomRowCount = 0;

function openSettlementModal(exitId, empName, lwd) {
    $('#stl_exit_id').val(exitId);
    $('#stl_emp_name').text(empName);
    $('#stl_lwd').val(lwd || '');
    $('#stl_pwd').val(30);
    // Clear fields
    ['stl_ps','stl_le','stl_bi','stl_ga','stl_pa','stl_sp','stl_lr','stl_nsd','stl_od'].forEach(function(id){ $('#'+id).val(''); });
    $('#stl_notes').val('');
    $('#stlCustomEarningsWrap').empty();
    $('#stlCustomDeductionsWrap').empty();
    stlCustomRowCount = 0;
    switchStlTab('edit');
    $('#stlPreviewContent').html('');

    // Load existing settlement data if any
    $.ajax({
        url: '?fetch_settlement_data=1&exit_id=' + exitId,
        method: 'GET',
        dataType: 'json',
        success: function(data) {
            if (data.settlement) {
                var s = data.settlement;
                $('#stl_lwd').val(s.final_last_working_day || lwd || '');
                $('#stl_pwd').val(s.payment_within_days || 30);
                $('#stl_ps').val(s.pending_salary > 0 ? s.pending_salary : '');
                $('#stl_le').val(s.leave_encashment > 0 ? s.leave_encashment : '');
                $('#stl_bi').val(s.bonus_incentive > 0 ? s.bonus_incentive : '');
                $('#stl_ga').val(s.gratuity_amount > 0 ? s.gratuity_amount : '');
                $('#stl_pa').val(s.pension_amount > 0 ? s.pension_amount : '');
                $('#stl_sp').val(s.severance_pay > 0 ? s.severance_pay : '');
                $('#stl_lr').val(s.loan_recovery > 0 ? s.loan_recovery : '');
                $('#stl_nsd').val(s.notice_shortfall_deduction > 0 ? s.notice_shortfall_deduction : '');
                $('#stl_od').val(s.other_deductions > 0 ? s.other_deductions : '');
                $('#stl_notes').val(s.notes || '');
            }
            // Load custom items
            if (data.items && data.items.length > 0) {
                data.items.forEach(function(item) {
                    addStlRowWithData(item.item_type, item.label, item.amount);
                });
            }
            recalcStlNet();
        }
    });

    recalcStlNet();
    $('#settlementEntryModal').modal('show');
}

function switchStlTab(which) {
    if (which === 'edit') {
        $('#stlEditPanel').show(); $('#stlPreviewPanel').hide();
        $('#stlTabEditBtn').css({'border-bottom':'3px solid #10b981','color':'#065f46'});
        $('#stlTabPreviewBtn').css({'border-bottom':'3px solid transparent','color':'#94a3b8'});
    } else {
        $('#stlEditPanel').hide(); $('#stlPreviewPanel').show();
        $('#stlTabPreviewBtn').css({'border-bottom':'3px solid #10b981','color':'#065f46'});
        $('#stlTabEditBtn').css({'border-bottom':'3px solid transparent','color':'#94a3b8'});
    }
}

function addStlRow(type) {
    addStlRowWithData(type, '', '');
}

function addStlRowWithData(type, label, amount) {
    stlCustomRowCount++;
    var idx = stlCustomRowCount;
    var isDeduction = (type === 'deduction');
    var color = isDeduction ? '#991b1b' : '#065f46';
    var wrap = isDeduction ? '#stlCustomDeductionsWrap' : '#stlCustomEarningsWrap';
    var html = '<div id="stlRow_'+idx+'" style="display:flex; gap:8px; align-items:center; margin-bottom:10px; background:'+(isDeduction?'#fff5f5':'#f0fdf4')+'; padding:10px; border-radius:8px; border:1px solid '+(isDeduction?'#fca5a5':'#6ee7b7')+';">'
        + '<input type="text" name="custom_label[]" class="fc" style="flex:2;" placeholder="Label (e.g. Salary April)" value="'+$('<div>').text(label).html()+'">'
        + '<input type="number" name="custom_amount[]" step="0.01" class="fc stl-amt" style="flex:1;" placeholder="0.00" value="'+(amount||'')+'">'
        + '<input type="hidden" name="custom_type[]" value="'+type+'">'
        + '<button type="button" onclick="$(\'#stlRow_'+idx+'\').remove(); recalcStlNet();" style="background:#dc2626;color:#fff;border:none;border-radius:6px;padding:6px 10px;cursor:pointer;font-size:12px;" title="Remove"><i class="fas fa-times"></i></button>'
        + '</div>';
    $(wrap).append(html);
}

function recalcStlNet() {
    var g = function(id) { return parseFloat($('#'+id).val()) || 0; };
    var earnings = g('stl_ps') + g('stl_le') + g('stl_bi') + g('stl_ga') + g('stl_pa') + g('stl_sp');
    var deductions = g('stl_lr') + g('stl_nsd') + g('stl_od');

    // Custom rows
    $('input[name="custom_amount[]"]').each(function(i, el) {
        var type = $('input[name="custom_type[]"]').eq(i).val();
        var amt = parseFloat($(el).val()) || 0;
        if (type === 'deduction') deductions += amt; else earnings += amt;
    });

    var net = earnings - deductions;
    $('#stl_net_display').text('₹ ' + net.toFixed(2));
    return net;
}

function getStlFormData(advance) {
    var data = {
        ajax_action: 'save_settlement_from_interview',
        exit_id: $('#stl_exit_id').val(),
        final_last_working_day: $('#stl_lwd').val(),
        payment_within_days: $('#stl_pwd').val(),
        pending_salary: $('#stl_ps').val(),
        leave_encashment: $('#stl_le').val(),
        bonus_incentive: $('#stl_bi').val(),
        gratuity_amount: $('#stl_ga').val(),
        pension_amount: $('#stl_pa').val(),
        severance_pay: $('#stl_sp').val(),
        loan_recovery: $('#stl_lr').val(),
        notice_shortfall_deduction: $('#stl_nsd').val(),
        other_deductions: $('#stl_od').val(),
        notes: $('#stl_notes').val(),
        advance_to_documents: advance ? 1 : 0,
        'custom_label[]': [],
        'custom_amount[]': [],
        'custom_type[]': []
    };
    // Gather dynamic rows - use FormData for array fields
    return data;
}

function showToast(title, msg, type) {
    $('#toastTitle').text(title);
    $('#toastMsg').text(msg);
    if(type === 'error') {
        $('#customToast').css('border-left-color', '#ef4444');
        $('#toastIcon').css({'background':'#fee2e2', 'color':'#b91c1c'}).html('<i class="fas fa-times"></i>');
    } else {
        $('#customToast').css('border-left-color', '#10b981');
        $('#toastIcon').css({'background':'#d1fae5', 'color':'#065f46'}).html('<i class="fas fa-check"></i>');
    }
    $('#customToast').css('right', '24px');
    setTimeout(function(){ $('#customToast').css('right', '-350px'); }, 4000);
}

function saveSettlement(advance, showPreview) {
    var fd = new FormData();
    fd.append('ajax_action', 'save_settlement_from_interview');
    fd.append('exit_id', $('#stl_exit_id').val());
    fd.append('final_last_working_day', $('#stl_lwd').val());
    fd.append('payment_within_days', $('#stl_pwd').val());
    fd.append('pending_salary', $('#stl_ps').val());
    fd.append('leave_encashment', $('#stl_le').val());
    fd.append('bonus_incentive', $('#stl_bi').val());
    fd.append('gratuity_amount', $('#stl_ga').val());
    fd.append('pension_amount', $('#stl_pa').val());
    fd.append('severance_pay', $('#stl_sp').val());
    fd.append('loan_recovery', $('#stl_lr').val());
    fd.append('notice_shortfall_deduction', $('#stl_nsd').val());
    fd.append('other_deductions', $('#stl_od').val());
    fd.append('notes', $('#stl_notes').val());
    fd.append('advance_to_documents', advance ? 1 : 0);

    // Dynamic rows
    $('[name="custom_label[]"]').each(function(i, el){ fd.append('custom_label[]', $(el).val()); });
    $('[name="custom_amount[]"]').each(function(i, el){ fd.append('custom_amount[]', $(el).val()); });
    $('[name="custom_type[]"]').each(function(i, el){ fd.append('custom_type[]', $(el).val()); });

    $.ajax({
        url: window.location.href,
        method: 'POST',
        data: fd,
        contentType: false,
        processData: false,
        dataType: 'json',
        success: function(res) {
            if (res.success) {
                if (showPreview) {
                    $('#stlPreviewContent').html(res.preview_html);
                    switchStlTab('preview');
                    showToast('Saved successfully', 'Net Payable: ₹ ' + parseFloat(res.net).toFixed(2), 'success');
                } else {
                    showToast('Saved successfully', 'Net Payable: ₹ ' + parseFloat(res.net).toFixed(2), 'success');
                }
                if (res.advanced) {
                    setTimeout(function(){ location.reload(); }, 1500);
                }
            } else {
                showToast('Error', res.message || 'Could not save settlement.', 'error');
            }
        },
        error: function() { showToast('Error', 'Server error while saving settlement.', 'error'); }
    });
}

function finalizeSettlement() {
    $('#confirmMsg').html('This will save all entered amounts and advance the exit to the <b>Documents</b> phase.');
    $('#customConfirmModal').modal('show');
    $('#confirmOkBtn').off('click').on('click', function(){
        $('#customConfirmModal').modal('hide');
        saveSettlement(1, false);
    });
}

$(document).on('input', '.stl-amt', function(){ recalcStlNet(); });
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