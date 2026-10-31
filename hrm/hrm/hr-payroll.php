<?php
// ✅ FIX: buffer output from the very first byte. If any stray character
// (a UTF-8 BOM, blank line, or space) ends up before this <?php tag — which
// commonly happens when a file is re-saved/re-uploaded through some FTP
// clients or Windows editors — PHP normally sends that byte to the browser
// immediately, which "sends headers" and makes the session_start() call
// below fail with "Session cannot be started after headers have already
// been sent". Output buffering holds everything until the script finishes,
// so that stray byte (if present) never triggers the error.
if (!ob_get_level()) { ob_start(); }
// ============================================================================
// PAYROLL SYSTEM - FINAL CLEAN VERSION
// ============================================================================
// LOGIC:
//   Base = 26 days ALWAYS (fixed average for any month)
//   Per day = Gross / 26
//
//   Count ALL attendance (Mon to Sun, any day)
//   present_days = total check-ins this month + HR added days + holidays
//
//   If present_days < 26  → deduct absent days
//   If present_days = 26  → full salary
//   If present_days > 26  → full salary + OT for extra days
//
//   OT days  = MAX(0, present_days - 26)
//   OT amount = OT days × per_day  (auto calculated)
//
// NO week_off_day column needed — works for everyone automatically
// HR can add extra days in form for short months like February
// ============================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
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

try {
    require_once('database.php');
    require_once('library.php');
    require_once('funciones.php');
} catch(Exception $e) { die("Error: " . $e->getMessage()); }

date_default_timezone_set('Asia/Kolkata');

// ============================================================================
// NO-LOGOUT (no check-out) SALARY-CUT POLICY START DATE
// Months BEFORE this date: missing check-out = FULL day (no money cut)
// Months FROM this date:   missing check-out = 0.5 day salary
// ============================================================================
define('NO_LOGOUT_POLICY_START', '2026-06-01');

if(!isset($_SESSION['user_name'])) { header("Location: login.php"); exit; }
if(!isset($dbConn) || !$dbConn)    die("Database connection failed.");

// On PHP 8.1+, mysqli throws exceptions on query errors by default instead of
// returning false. This file's code is written to check "if ($result) { ... }"
// / mysqli_error() after every mysqli_query() call, so force mysqli back to
// the classic error mode: return false on failure instead of throwing.
mysqli_report(MYSQLI_REPORT_OFF);

// ============================================================================
// AUTHORIZATION
// ============================================================================
$currentUserName = trim($_SESSION['user_name'] ?? '');
$emp_name_db     = '';
$emp_dept        = '';
$emp_position    = '';

if(!empty($currentUserName)) {
    $ns  = mysqli_real_escape_string($dbConn, $currentUserName);
    $res = mysqli_query($dbConn, "SELECT name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$ns%') AND status='active' LIMIT 1");
    if($res && mysqli_num_rows($res) > 0) {
        $r            = mysqli_fetch_assoc($res);
        $emp_name_db  = $r['name'];
        $emp_dept     = $r['department'] ?? '';
        $emp_position = $r['position']   ?? '';
    }
}

$is_abishek = (stripos($emp_name_db,'abishek')!==false || stripos($currentUserName,'abishek')!==false);
$is_keerti  = (stripos($emp_name_db,'keerti') !==false || stripos($currentUserName,'keerti') !==false);
$is_md      = (stripos($emp_position,'managing director')!==false || stripos($emp_position,'ceo')!==false);
$is_hr      = (stripos($emp_dept,'Human Resources')!==false || stripos($emp_dept,'Management')!==false);
$isAdmin    = $is_abishek;

// ============================================================================
// MANAGEMENT APPROVAL GATE — salary release / payslip email workflow
// Management (Managing Director / CEO), the HR admin/department, or the
// system admin (Abishek) can approve a payroll record for release. Payslips
// are NEVER emailed to an employee automatically — only this approval
// action triggers the email.
// ============================================================================
$can_approve_payroll = ($isAdmin || $is_md || $is_hr);

// Payroll Overview dashboard — Managing Director only. $pv_tab decides which
// tab renders; defaults to Overview for the MD, List for everyone else, and
// non-viewers can never switch to Overview even via a manual ?pv_tab= URL.
$is_payroll_overview_viewer = ($is_abishek || $is_md);
$pv_tab = isset($_GET['pv_tab']) ? $_GET['pv_tab'] : ($is_payroll_overview_viewer ? 'overview' : 'list');
if(!$is_payroll_overview_viewer) $pv_tab = 'list';

if(!($is_abishek || $is_keerti || $is_md || $is_hr) && !isset($_GET['download_payslip']))
    die("<div style='font-family:Arial;text-align:center;margin-top:100px;'><h2>Access Denied</h2><p><a href='raise-a-ticket.php'>Back</a></p></div>");

// Create override table if missing
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_attendance_overrides (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    attendance_date DATE NOT NULL,
    status ENUM('present','absent','holiday','leave','half_day') DEFAULT 'present',
    reason TEXT, created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_emp_date (employee_id, attendance_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add per_day_salary column if missing
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'per_day_salary'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN per_day_salary DECIMAL(10,2) DEFAULT 0.00 AFTER net_salary");

// Ensure hr_office_holidays table exists (created here so payroll works even before departments page is visited)
$cht = mysqli_query($dbConn, "SHOW TABLES LIKE 'hr_office_holidays'");
if(!$cht || mysqli_num_rows($cht)==0)
    mysqli_query($dbConn, "CREATE TABLE hr_office_holidays (
        id INT AUTO_INCREMENT PRIMARY KEY,
        holiday_date DATE NOT NULL,
        holiday_name VARCHAR(200) NOT NULL,
        year INT(4) NOT NULL,
        month INT(2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_holiday_date (holiday_date)
    )");

// Add arrears_days column if missing
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'arrears_days'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN arrears_days DECIMAL(6,1) DEFAULT 0 AFTER arrears");

// Add other_earnings column if missing
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'other_earnings'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN other_earnings DECIMAL(10,2) DEFAULT 0.00 AFTER incentives");

// Add other_deductions column if missing
$c0 = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'paid_leave_days'");
if(!$c0 || mysqli_num_rows($c0)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN paid_leave_days DECIMAL(5,1) DEFAULT 0 AFTER present_days");

$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'other_deductions'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN other_deductions DECIMAL(10,2) DEFAULT 0.00 AFTER penalty");

// ============================================================================
// SALARY RELEASE / MANAGEMENT APPROVAL WORKFLOW — new columns
// approval_status: pending (default, just generated/edited) -> approved
// (Management signed off, payslip email sent) or rejected (Management held
// it back, no email sent). payslip_sent / payslip_sent_at record whether the
// email actually went out (kept separate from approval_status so a failed
// email doesn't silently look "approved & delivered").
// ============================================================================
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'approval_status'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN approval_status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending' AFTER net_salary");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'approved_by'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN approved_by VARCHAR(150) NULL AFTER approval_status");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'approved_at'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN approved_at DATETIME NULL AFTER approved_by");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'payslip_sent'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN payslip_sent TINYINT(1) NOT NULL DEFAULT 0 AFTER approved_at");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'payslip_sent_at'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN payslip_sent_at DATETIME NULL AFTER payslip_sent");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'payslip_send_error'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN payslip_send_error VARCHAR(255) NULL AFTER payslip_sent_at");

$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'approve_ot'");
if(!$c || mysqli_num_rows($c)==0) {
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN approve_ot DECIMAL(5,1) NOT NULL DEFAULT 0 AFTER payslip_send_error");
} else {
    $c_row = mysqli_fetch_assoc($c);
    if(stripos($c_row['Type'], 'tinyint') !== false || stripos($c_row['Type'], 'int') !== false) {
        mysqli_query($dbConn, "ALTER TABLE hr_payroll MODIFY COLUMN approve_ot DECIMAL(5,1) NOT NULL DEFAULT 0");
    }
}
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'reduce_days'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN reduce_days DECIMAL(5,1) NOT NULL DEFAULT 0 AFTER approve_ot");
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'calendar_ot'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN calendar_ot DECIMAL(5,1) NOT NULL DEFAULT 0 AFTER reduce_days");

// Fix present_days and absent_days to support 0.5 (half days)
$pd_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'present_days'");
if($pd_check && mysqli_num_rows($pd_check) > 0) {
    $pd_row = mysqli_fetch_assoc($pd_check);
    if(stripos($pd_row['Type'], 'int') !== false || stripos($pd_row['Type'], 'tinyint') !== false)
        mysqli_query($dbConn, "ALTER TABLE hr_payroll MODIFY COLUMN present_days DECIMAL(6,1) DEFAULT 0");
}
$ad_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'absent_days'");
if($ad_check && mysqli_num_rows($ad_check) > 0) {
    $ad_row = mysqli_fetch_assoc($ad_check);
    if(stripos($ad_row['Type'], 'int') !== false || stripos($ad_row['Type'], 'tinyint') !== false)
        mysqli_query($dbConn, "ALTER TABLE hr_payroll MODIFY COLUMN absent_days DECIMAL(6,1) DEFAULT 0");
}
$ww_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'weekends_worked'");
if($ww_check && mysqli_num_rows($ww_check) > 0) {
    $ww_row = mysqli_fetch_assoc($ww_check);
    if(stripos($ww_row['Type'], 'int') !== false || stripos($ww_row['Type'], 'tinyint') !== false)
        mysqli_query($dbConn, "ALTER TABLE hr_payroll MODIFY COLUMN weekends_worked DECIMAL(6,1) DEFAULT 0");
}

$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'late_days'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN late_days DECIMAL(5,1) NOT NULL DEFAULT 0 AFTER reduce_days");


// ============================================================================
// CORE SALARY CALCULATION
// ============================================================================
// RULES:
//   per_day       = gross / 26
//   normal_days   = MIN(total_present, 26)   → salary
//   ot_days       = MAX(0, total_present - 26) → OT bonus
//   absent_days   = MAX(0, 26 - total_present)
//   net           = (normal_days × per_day) + (ot_days × per_day) - deductions
//
// total_present = ALL attendance days (Mon-Sun) + holidays + HR added days
// ============================================================================
function calcSalary($gross, $total_present, $total_absents, $extra_ot = 0, $approved_calendar_ot = 0) {
    if($gross <= 0) return ['per_day'=>0,'normal_days'=>0,'ot_days'=>0,'absent_days'=>26,'earned'=>0,'ot_amount'=>0,'net'=>0, 'calendar_ot'=>0, 'approve_ot'=>0];

    $per_day     = round($gross / 26, 4);
    $normal_days = min($total_present, 26 - $total_absents);
    if($normal_days < 0) $normal_days = 0;
    
    $calendar_ot = max(0, $total_present - 26);
    $approved_calendar_ot = min((float)$approved_calendar_ot, $calendar_ot);
    
    // Total OT is HR-added manual extra days + (calendar OT approved)
    $ot_days = $extra_ot + $approved_calendar_ot;
    
    $absent_days = max(0, 26 - $normal_days);

    $earned    = round($per_day * $normal_days, 2);
    $ot_amount = round($per_day * $ot_days, 2);

    // Employee-favorable rounding
    $net     = $earned + $ot_amount;
    $decimal = $net - floor($net);
    $net     = ($decimal >= 0.50) ? ceil($net) : floor($net);

    return [
        'per_day'     => round($per_day, 2),
        'normal_days' => $normal_days,
        'ot_days'     => $ot_days,
        'absent_days' => $absent_days,
        'earned'      => $earned,
        'ot_amount'   => $ot_amount,
        'net'         => $net,
        'calendar_ot' => round($calendar_ot, 1),
        'approve_ot'  => round($approved_calendar_ot, 1)
    ];
}

// ============================================================================
// GET TOTAL ATTENDANCE DAYS FOR AN EMPLOYEE IN A MONTH
// Counts ALL days (Mon-Sun) — no day is excluded
// ============================================================================
function getTotalAttendanceDays($dbConn, $emp_db_id, $emp_code, $month, $year) {
    $start = "$year-" . str_pad($month,2,'0',STR_PAD_LEFT) . "-01";
    $end   = "$year-" . str_pad($month,2,'0',STR_PAD_LEFT) . "-" . str_pad(cal_days_in_month(CAL_GREGORIAN,$month,$year),2,'0',STR_PAD_LEFT);

    // ========================================================================
    // NO-LOGOUT PENALTY POLICY — EFFECTIVE FROM JUNE 2026 ONWARDS
    // For months BEFORE June 2026: check-in without check-out = FULL day
    // (no salary cut). From June 2026: check-in without check-out = 0.5 day.
    // ========================================================================
    $penalty_applies = (strtotime($start) >= strtotime(NO_LOGOUT_POLICY_START));
    $today_date = date('Y-m-d');

    if($penalty_applies) {
        // Full days = check-in AND check-out both done
        $q = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
            AND status IN ('present','late')
            AND check_out_time IS NOT NULL AND check_out_time != ''");
        $bio_full = intval(mysqli_fetch_assoc($q)['cnt']);
        
        $qh = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
            AND status = 'half_day'
            AND check_out_time IS NOT NULL AND check_out_time != ''");
        $bio_half = intval(mysqli_fetch_assoc($qh)['cnt']) * 0.5;
        
        $bio_days = $bio_full + $bio_half;

        // Half-days: checked-in but NO check-out (past dates only — today is excluded)
        $q_half = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
            AND date < '$today_date'
            AND status IN ('present','late','half_day')
            AND (check_out_time IS NULL OR check_out_time = '')");
        $half_days = intval(mysqli_fetch_assoc($q_half)['cnt']);
    } else {
        // PRE-JUNE 2026: ANY check-in counts as a FULL day, with or without checkout
        $q = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
            AND status IN ('present','late')");
        $bio_full = intval(mysqli_fetch_assoc($q)['cnt']);
        
        $qh = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
            AND status = 'half_day'");
        $bio_half = intval(mysqli_fetch_assoc($qh)['cnt']) * 0.5;
        
        $bio_days = $bio_full + $bio_half;
        $half_days = 0; // no half-day penalty before June 2026
    }
    $half_day_value = $half_days * 0.5; // each no-checkout = 0.5 day salary (Jun 2026 onwards)

    // Manual overrides — present/holiday/leave = add days, absent = subtract
    $oq = mysqli_query($dbConn, "SELECT attendance_date, status, created_by FROM hr_attendance_overrides
        WHERE employee_id=$emp_db_id AND attendance_date BETWEEN '$start' AND '$end'");

    $ov_present = 0;
    $ov_absent  = 0;
    $ov_dates   = [];
    
    $late_policy_absents = 0;
    $unpaid_leave_days   = 0;
    $paid_leave_days     = 0;

    while($ov = mysqli_fetch_assoc($oq)) {
        $ov_dates[] = $ov['attendance_date'];
        if(in_array($ov['status'], ['present','holiday'])) {
            $ov_present++;
        }
        elseif($ov['status'] == 'leave') {
            $ov_present++;
            $paid_leave_days++;
        }
        elseif($ov['status'] == 'absent') {
            $ov_absent++;
        }
        elseif($ov['status'] == 'half_day') {
            $ov_present += 0.5; // Partial present
            $ov_absent  += 0.5; // Partial absent
        }
        elseif($ov['status'] == 'unpaid_half_leave') {             
            $ov_present += 0.5;
            $ov_absent += 0.5; // Manual HR overrides still use ov_absent for explicit deduction if needed
            $unpaid_leave_days += 0.5;
        } // Unpaid half day
    }

    // Virtual overrides from approved leaves (hr_leaves)
    // Applies leave management automatically if no manual HR override was added
    $lq = mysqli_query($dbConn, "SELECT start_date, end_date, leave_type, leave_days FROM hr_leaves 
        WHERE employee_id=$emp_db_id AND status='approved' 
        AND start_date <= '$end' AND end_date >= '$start'");
        
    if($lq) {
        while($lr = mysqli_fetch_assoc($lq)) {
            $ls = max($start, $lr['start_date']);
            $le = min($end, $lr['end_date']);
            $curr = $ls;
            $remaining = floatval($lr['leave_days']);
            while(strtotime($curr) <= strtotime($le) && $remaining > 0) {
                // only process if a manual override hasn't already claimed this date
                if(!in_array($curr, $ov_dates)) {
                    $ltype = $lr['leave_type'];
                    $v_status = 'leave'; // default is full paid leave
                    
                    if($ltype == 'half_day') {
                        $v_status = 'half_day';
                        $remaining -= 0.5;
                    } elseif($ltype == 'unpaid') {
                        if($remaining >= 1) {
                            $v_status = 'absent';
                            $remaining -= 1;
                        } else {
                            $v_status = 'unpaid_half_leave';
                            $remaining -= 0.5;
                        }
                    } else {
                        if($remaining >= 1) {
                            $v_status = 'leave';
                            $remaining -= 1;
                        } else {
                            $v_status = 'half_day';
                            $remaining -= 0.5;
                        }
                    }
                    
                    $ov_dates[] = $curr;
                    if(in_array($v_status, ['present','holiday'])) {
                        $ov_present++;
                    }
                    elseif($v_status == 'leave') {
                        $ov_present++;
                        $paid_leave_days++;
                    }
                    elseif($v_status == 'absent') {
                        $unpaid_leave_days += 1;
                    }
                    elseif($v_status == 'half_day') {
                        $ov_present += 0.5;
                        $paid_leave_days += 0.5;
                    }
                    elseif($v_status == 'unpaid_half_leave') {             
                        $ov_present += 0.5;
                        $unpaid_leave_days += 0.5;
                    }
                }
                $curr = date('Y-m-d', strtotime($curr . ' +1 day'));
            }
        }
    }

    // Remove biometric days that have overrides (to avoid double counting)
    if(!empty($ov_dates)) {
        $ds = "'" . implode("','", $ov_dates) . "'";
        if($penalty_applies) {
            $q_f  = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
                WHERE employee_id='$emp_code' AND date IN ($ds) AND status IN ('present','late')
                AND check_out_time IS NOT NULL AND check_out_time != ''");
            $q_h  = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
                WHERE employee_id='$emp_code' AND date IN ($ds) AND status = 'half_day'
                AND check_out_time IS NOT NULL AND check_out_time != ''");
        } else {
            $q_f  = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
                WHERE employee_id='$emp_code' AND date IN ($ds) AND status IN ('present','late')");
            $q_h  = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
                WHERE employee_id='$emp_code' AND date IN ($ds) AND status = 'half_day'");
        }
        $override_bio_cnt = intval(mysqli_fetch_assoc($q_f)['cnt']) + (intval(mysqli_fetch_assoc($q_h)['cnt']) * 0.5);
        $bio_days -= $override_bio_cnt;
        // Also subtract any half-days that have overrides (only when penalty policy applies)
        if($penalty_applies) {
            $q_hov = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
                WHERE employee_id='$emp_code' AND date IN ($ds)
                AND (check_out_time IS NULL OR check_out_time = '') AND date < '$today_date'");
            $half_days -= intval(mysqli_fetch_assoc($q_hov)['cnt']);
            if($half_days < 0) $half_days = 0;
            $half_day_value = $half_days * 0.5;
        }
    }

    $total = max(0, $bio_days + $half_day_value + $ov_present - $ov_absent);

    $db_abs_q_str = "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance WHERE employee_id='$emp_code' AND status='absent' AND date BETWEEN '$start' AND '$end'";
    if(!empty($ov_dates)) {
        $ds = "'" . implode("','", $ov_dates) . "'";
        $db_abs_q_str .= " AND date NOT IN ($ds)";
    }
    $db_abs_q = mysqli_query($dbConn, $db_abs_q_str);
    $db_absent = intval(mysqli_fetch_assoc($db_abs_q)['cnt']);
    
    $db_half_q_str = "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance WHERE employee_id='$emp_code' AND status='half_day' AND date BETWEEN '$start' AND '$end'";
    if($penalty_applies) $db_half_q_str .= " AND check_out_time IS NOT NULL AND check_out_time != ''";
    if(!empty($ov_dates)) {
        $ds = "'" . implode("','", $ov_dates) . "'"; // just to be sure
        $db_half_q_str .= " AND date NOT IN ($ds)";
    }
    $db_half_q = mysqli_query($dbConn, $db_half_q_str);
    $db_absent += (intval(mysqli_fetch_assoc($db_half_q)['cnt']) * 0.5);
    
    // Add no-logout half-days as 0.5 absent each
    $db_absent += ($half_days * 0.5);
    
    $late_q_str = "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance WHERE employee_id='$emp_code' AND status='late' AND date BETWEEN '$start' AND '$end'";
    if(!empty($ov_dates)) $late_q_str .= " AND date NOT IN ($ds)";
    $late_q = mysqli_query($dbConn, $late_q_str);
    $total_late = intval(mysqli_fetch_assoc($late_q)['cnt']);
    
    $lp_q_str = "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance WHERE employee_id='$emp_code' AND status='absent' AND late_policy_converted='Yes' AND date BETWEEN '$start' AND '$end'";
    if(!empty($ov_dates)) $lp_q_str .= " AND date NOT IN ($ds)";
    $lp_q = mysqli_query($dbConn, $lp_q_str);
    $late_policy_absents = intval(mysqli_fetch_assoc($lp_q)['cnt']);
    
    // Add unpaid_leave_days to total_absent so it caps the salary at working_days_base - total_absents
    $total_absent = $db_absent + $ov_absent + $unpaid_leave_days;

    return [
        'total'       => $total,
        'total_absent'=> $total_absent,
        'bio_days'    => max(0, $bio_days),
        'half_days'   => $half_days,
        'ov_present'  => $ov_present,
        'ov_absent'   => $ov_absent,
        'penalty_applies' => $penalty_applies,
        'has_overrides' => count($ov_dates) > 0,
        'late_policy_absents' => $late_policy_absents,
        'unpaid_leave_days'   => $unpaid_leave_days,
        'paid_leave_days'     => $paid_leave_days,
        'total_late'          => $total_late
    ];
}

// ============================================================================
// ============================================================================
// PAYSLIP HTML BUILDER — shared by "Download Payslip" and the approval email.
// Returns ['html' => <payslip HTML string>, 'data' => <payroll+employee row>]
// or null if the payroll record doesn't exist. Building this in one place
// means the emailed payslip and the downloaded/printed payslip can never
// drift apart.
// ============================================================================
function buildPayslipHtml($dbConn, $pid) {
    $pid    = intval($pid);
    $result = mysqli_query($dbConn, "SELECT p.*, e.name, e.employee_id as emp_code,
        e.company_name, e.employee_type,
        COALESCE(e.position,'N/A') as designation,
        COALESCE(e.department,'N/A') as department,
        e.personal_email as emp_email
        FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id
        WHERE p.id=$pid LIMIT 1");
    if(!$result || mysqli_num_rows($result)==0) return null;
    $d = mysqli_fetch_assoc($result);

    $company_name = $d['company_name'] ?: 'Abra E Logistics Private Limited';
    $logo_base64  = '';
    $company_name_safe = mysqli_real_escape_string($dbConn, trim($company_name));
    $lq = mysqli_query($dbConn,"SELECT logo_path FROM hr_companies WHERE LOWER(TRIM(company_name))=LOWER('$company_name_safe') LIMIT 1");
    if($lq && mysqli_num_rows($lq)>0) {
        $lp = mysqli_fetch_assoc($lq)['logo_path'];
        if(!empty($lp) && file_exists($lp))
            $logo_base64 = 'data:image/'.pathinfo($lp,PATHINFO_EXTENSION).';base64,'.base64_encode(file_get_contents($lp));
    }

    $month_name   = date("F", mktime(0,0,0,$d['pay_month'],10));
    $year         = $d['pay_year'];
    $pay_date_fmt = date("d-M-Y", mktime(0,0,0,$d['pay_month']+1,10,$d['pay_year']));
    $per_day      = floatval($d['per_day_salary']) ?: round(floatval($d['gross_pay'])/26, 2);
    $ot_value     = floatval($d['ot_amount'] ?? $d['ot']);
    $ot_days      = floatval($d['weekends_worked'] ?? 0); // stored as ot_days
    $gross        = floatval($d['gross_pay']);
    $absent_deduct = round($per_day * floatval($d['absent_days']), 2);
    $total_deduct  = floatval($d['esi']) + floatval($d['pt']) + floatval($d['tds']) + $absent_deduct + floatval($d['advance_salary']) + floatval($d['penalty']);
    $pf_emp       = floatval($d['pf']);
    if($pf_emp==0 && stripos($d['employee_type'],'Permanent')!==false) $pf_emp=round(floatval($d['basic_salary'])*0.12,2);

    ob_start();
    echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Payslip - '.htmlspecialchars($d['name']).'</title>
    <style>
    @page{margin:15mm 10mm;size:A4;}
    @media print{*{-webkit-print-color-adjust:exact!important;}html,body{margin:0;padding:0;background:white;}.no-print{display:none!important;}}
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:Arial,sans-serif;background:#f5f5f5;padding:20px;}
    .ps{max-width:750px;margin:0 auto;background:white;border:3px solid #1e3a8a;box-shadow:0 0 20px rgba(0,0,0,.1);}
    .hd{padding:20px 30px 12px;border-bottom:3px solid #1e3a8a;text-align:center;}
    .logo{min-height:120px;display:flex;align-items:center;justify-content:center;margin-bottom:10px;}
    .logo img{max-height:120px;max-width:600px;object-fit:contain;}
    .cn{font-size:18px;font-weight:bold;color:#1e3a8a;margin-bottom:8px;}
    .hb{background:#1e3a8a;color:white;padding:7px 12px;}
    .hb .t{font-size:14px;font-weight:bold;letter-spacing:2px;}
    .hb .p{font-size:11px;}
    .es{padding:8px 30px;background:#f8f9fa;border-bottom:2px solid #dee2e6;}
    .it{width:100%;border-collapse:collapse;}
    .it td{padding:4px 6px;font-size:10px;}
    .it td:nth-child(odd){color:#495057;width:20%;}
    .it td:nth-child(even){color:#212529;font-weight:bold;width:30%;}
    .ss{padding:8px 30px;}
    .sg{display:grid;grid-template-columns:1fr 1fr;gap:15px;}
    .sc h3{background:#1e3a8a;color:white;padding:6px 10px;font-size:10px;font-weight:bold;margin-bottom:8px;text-transform:uppercase;}
    .st{width:100%;border-collapse:collapse;border:1px solid #dee2e6;}
    .st tr{border-bottom:1px solid #dee2e6;}
    .st td{padding:5px 8px;font-size:10px;}
    .st td:last-child{text-align:right;font-weight:bold;font-family:"Courier New",monospace;}
    .tr{background:#1e3a8a!important;}.tr td{color:white!important;font-weight:bold!important;font-size:11px!important;}
    .cr{background:#059669!important;}.cr td{color:white!important;font-weight:bold!important;font-size:11px!important;}
    .or{background:#fffbeb!important;}.or td{color:#92400e!important;font-weight:bold!important;}
    .at{padding:0 30px 8px;}
    .at h3{background:#1e3a8a;color:white;padding:6px 10px;font-size:10px;font-weight:bold;margin-bottom:8px;text-transform:uppercase;}
    .att{width:100%;border-collapse:collapse;border:1px solid #dee2e6;}
    .att td{padding:7px;font-size:10px;border-right:1px solid #dee2e6;text-align:center;}
    .lc{background:#f8f9fa;color:#495057;}
    .vc{background:white;color:#212529;font-weight:bold;}
    .vc.ot{color:#d97706!important;background:#fffbeb!important;}
    .ns{background:#1e3a8a;color:white;padding:10px 30px;text-align:center;border-top:2px solid #1e40af;}
    .nl{font-size:11px;font-weight:bold;letter-spacing:2px;margin-bottom:3px;}
    .na{font-size:22px;font-weight:bold;font-family:"Courier New",monospace;}
    .sg2{padding:10px 30px 8px;display:flex;justify-content:space-between;border-top:2px solid #dee2e6;}
    .sb{width:45%;}
    .sn{font-family:"Brush Script MT",cursive;font-size:18px;color:#1e3a8a;text-align:center;}
    .sl{border-top:2px solid #212529;margin:3px 0;}
    .slb{font-size:8px;color:#495057;font-weight:bold;text-transform:uppercase;text-align:center;}
    .st2{font-size:7px;color:#6c757d;font-style:italic;text-align:center;}
    .pb{text-align:center;padding:12px;}
    .pb button{background:#1e3a8a;color:white;padding:14px 36px;border:none;border-radius:6px;font-size:15px;font-weight:600;cursor:pointer;min-height:48px;-webkit-tap-highlight-color:rgba(0,0,0,.1);}
    </style></head><body>
    <div class="ps">
    <div class="hd">';
    if($logo_base64) echo '<div class="logo"><img src="'.$logo_base64.'" alt="Logo"></div>';
    echo '<div class="cn">'.strtoupper(htmlspecialchars($company_name)).'</div>
    <div class="hb"><div class="t">SALARY SLIP</div><div class="p">Month: '.$month_name.' '.$year.'</div></div></div>
    <div class="es"><table class="it">
    <tr><td>Employee Name:</td><td>'.strtoupper(htmlspecialchars($d['name'])).'</td><td>Employee ID:</td><td>'.htmlspecialchars($d['emp_code']).'</td></tr>
    <tr><td>Designation:</td><td>'.htmlspecialchars($d['designation']).'</td><td>Department:</td><td>'.htmlspecialchars($d['department']).'</td></tr>
    <tr><td>Pay Date:</td><td>'.$pay_date_fmt.'</td><td>Pay Period:</td><td>'.$month_name.' '.$year.'</td></tr>
    </table></div>
    <div class="ss"><div class="sg">
    <div class="sc"><h3>Earnings</h3><table class="st">
    <tr><td>Basic Salary</td><td>&#8377; '.number_format($d['basic_salary'],2).'</td></tr>
    <tr><td>HRA</td><td>&#8377; '.number_format($d['hra'],2).'</td></tr>
    <tr><td>Conveyance</td><td>&#8377; '.number_format($d['conveyance'],2).'</td></tr>
    <tr><td>Special Allowance</td><td>&#8377; '.number_format($d['special_allowance'],2).'</td></tr>
    <tr class="tr"><td>GROSS SALARY (26 Day Base)</td><td>&#8377; '.number_format($gross,2).'</td></tr>';
    if($ot_value>0) echo '<tr class="or"><td>OT Amount ('.$ot_days.' extra days × &#8377;'.number_format($per_day,2).')</td><td>&#8377; '.number_format($ot_value,2).'</td></tr>';
    if(floatval($d['arrears'])>0) echo '<tr><td>Arrears ('.floatval($d['arrears_days']??0).' days)</td><td>&#8377; '.number_format($d['arrears'],2).'</td></tr>';
    if(floatval($d['overtime'])>0) echo '<tr><td>Overtime</td><td>&#8377; '.number_format($d['overtime'],2).'</td></tr>';
    if(floatval($d['incentives'])>0) echo '<tr><td>Incentives</td><td>&#8377; '.number_format($d['incentives'],2).'</td></tr>';
    if(floatval($d['other_earnings']??0)>0) echo '<tr><td>Other Earnings</td><td>&#8377; '.number_format($d['other_earnings'],2).'</td></tr>';
    echo '</table></div>
    <div class="sc"><h3>Deductions</h3><table class="st">';
    if(floatval($d['esi'])>0)            echo '<tr><td>ESI</td><td>&#8377; '.number_format($d['esi'],2).'</td></tr>';
    if(floatval($d['pt'])>0)             echo '<tr><td>Professional Tax</td><td>&#8377; '.number_format($d['pt'],2).'</td></tr>';
    if(floatval($d['tds'])>0)            echo '<tr><td>TDS</td><td>&#8377; '.number_format($d['tds'],2).'</td></tr>';
    if($absent_deduct>0)                 echo '<tr><td>Absent Deduction ('.$d['absent_days'].' days)</td><td>&#8377; '.number_format($absent_deduct,2).'</td></tr>';
    if(floatval($d['advance_salary'])>0) echo '<tr><td>Advance Salary</td><td>&#8377; '.number_format($d['advance_salary'],2).'</td></tr>';
    if(floatval($d['penalty'])>0)        echo '<tr><td>Penalty</td><td>&#8377; '.number_format($d['penalty'],2).'</td></tr>';
    if(floatval($d['other_deductions']??0)>0) echo '<tr><td>Other Deductions</td><td>&#8377; '.number_format($d['other_deductions'],2).'</td></tr>';
    $total_deduct += floatval($d['other_deductions']??0);
    if($total_deduct>0) echo '<tr class="tr"><td>TOTAL DEDUCTIONS</td><td>&#8377; '.number_format($total_deduct,2).'</td></tr>';
    else                echo '<tr><td colspan="2" style="text-align:center;padding:15px;font-style:italic;color:#6c757d">No Deductions</td></tr>';
    echo '</table></div></div></div>
    <div class="at"><h3>Attendance Summary (Base: 26 Days | No-Logout = 0.5 Day from Jun 2026)</h3>
    <table class="att">
    <tr>
      <td class="lc">Days Present (All Days)</td>
      <td class="lc">Normal Days (Max 26)</td>
      <td class="lc">Absent Days</td>
      '.($ot_days > 0 || $ot_value > 0 ? '<td class="lc">OT Days (Beyond 26)</td><td class="lc">OT Amount</td>' : '').'
    </tr>
    <tr>
      <td class="vc"><strong>'.($d['present_days'] + $ot_days).'</strong></td>
      <td class="vc"><strong>'.$d['present_days'].'</strong></td>
      <td class="vc"><strong>'.$d['absent_days'].'</strong></td>
      '.($ot_days > 0 || $ot_value > 0 ? '<td class="vc ot"><strong>'.$ot_days.'</strong></td><td class="vc ot">&#8377; '.number_format($ot_value,2).'</td>' : '').'
    </tr>
    </table></div>
    <div class="ns"><div class="nl">NET SALARY PAYABLE</div><div class="na">&#8377; '.number_format($d['net_salary'],2).'</div></div>
    <div class="sg2">
    <div class="sb"><div class="sn">'.htmlspecialchars($d['name']).'</div><div class="sl"></div><div class="slb">Employee Signature</div></div>
    <div class="sb"><div class="sn">Abishek Veeraswamy</div><div class="sl"></div><div class="slb">Authorized Signatory</div><div class="st2">Managing Director</div></div>
    </div></div>
    <div class="pb no-print"><button onclick="window.print()">PRINT / SAVE AS PDF</button></div>
    </body></html>';
    $html = ob_get_clean();
    return ['html' => $html, 'data' => $d];
}

// ============================================================================
// SMTP CONFIG — sending mailbox: hr-admin@abra-logistic.com (hosting-provider
// mailbox, e.g. cPanel). ONE thing is still required below: PAYSLIP_SMTP_PASS
// and PAYSLIP_SMTP_HOST must be confirmed against your actual hosting panel —
// see the two TODOs. Everything else is already set.
//
// HOW TO GET THE EXACT VALUES (cPanel or similar hosting panel):
//   1. Log into your hosting control panel (cPanel) for abra-logistic.com.
//   2. Go to "Email Accounts", find hr-admin@abra-logistic.com, click
//      "Connect Devices" (or "Set Up Mail Client") next to it.
//   3. It shows the exact "Outgoing Server (SMTP)" hostname + port, e.g.
//      mail.abra-logistic.com on port 587 (STARTTLS) or 465 (SSL). Use
//      whichever it lists — it's usually mail.<yourdomain> but not always.
//   4. PAYSLIP_SMTP_PASS is just that mailbox's normal login password (the
//      one you use to open its webmail) — no app password needed here,
//      that's only a Gmail/Outlook thing.
// ============================================================================
define('PAYSLIP_SMTP_HOST',   'mail.abra-logistic.com'); // confirmed from cPanel > Email Accounts > Connect Devices
define('PAYSLIP_SMTP_PORT',   465); // confirmed from cPanel > Email Accounts > Connect Devices
define('PAYSLIP_SMTP_SECURE', 'ssl'); // confirmed from cPanel: "Secure SSL/TLS Settings" = port 465
define('PAYSLIP_SMTP_USER',   'hr-admin@abra-logistic.com');
define('PAYSLIP_SMTP_PASS',   'Abragroup@123');
define('PAYSLIP_FROM_EMAIL',  'hr-admin@abra-logistic.com');
define('PAYSLIP_FROM_NAME',   'Abra E Logistics HR');

// ============================================================================
// RAW SMTP CLIENT — sends one HTML email via authenticated SMTP. No external
// library (PHPMailer/Composer) required, so this works on any PHP install.
// Returns true on success; on failure sets $err to the SMTP server's own
// response line, which tells you exactly what went wrong (bad login, bad
// recipient, connection blocked, etc.) instead of a generic mail() failure.
// ============================================================================
function smtp_send_mail($to, $subject, $htmlBody, &$err = null) {
    $host   = PAYSLIP_SMTP_HOST;
    $port   = PAYSLIP_SMTP_PORT;
    $secure = PAYSLIP_SMTP_SECURE; // 'tls' or 'ssl'
    $user   = PAYSLIP_SMTP_USER;
    $pass   = PAYSLIP_SMTP_PASS;
    $fromEmail = PAYSLIP_FROM_EMAIL;
    $fromName  = PAYSLIP_FROM_NAME;

    $remote = ($secure === 'ssl' ? 'ssl://' : '') . $host . ':' . $port;
    $fp = @stream_socket_client($remote, $errno, $errstr, 15);
    if (!$fp) { $err = "Could not connect to $host:$port — $errstr ($errno)"; return false; }
    stream_set_timeout($fp, 15);

    $readResp = function() use ($fp) {
        $data = '';
        while (($line = fgets($fp, 515)) !== false) {
            $data .= $line;
            if (isset($line[3]) && $line[3] === ' ') break; // last line of a multi-line reply
        }
        return $data;
    };
    $cmd = function($c) use ($fp, $readResp) { fwrite($fp, $c . "\r\n"); return $readResp(); };

    $resp = $readResp(); // server greeting
    if (substr($resp, 0, 1) !== '2') { $err = "SMTP greeting failed: $resp"; fclose($fp); return false; }

    $helo = (isset($_SERVER['SERVER_NAME']) && $_SERVER['SERVER_NAME']) ? $_SERVER['SERVER_NAME'] : 'localhost';
    $resp = $cmd("EHLO $helo");

    if ($secure === 'tls') {
        $resp = $cmd("STARTTLS");
        if (substr($resp, 0, 3) !== '220') { $err = "STARTTLS refused: $resp"; fclose($fp); return false; }
        if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
            $err = "TLS handshake failed"; fclose($fp); return false;
        }
        $resp = $cmd("EHLO $helo");
    }

    $resp = $cmd("AUTH LOGIN");
    if (substr($resp, 0, 3) !== '334') { $err = "SMTP server rejected AUTH LOGIN: $resp"; fclose($fp); return false; }
    $resp = $cmd(base64_encode($user));
    if (substr($resp, 0, 3) !== '334') { $err = "SMTP username rejected: $resp"; fclose($fp); return false; }
    $resp = $cmd(base64_encode($pass));
    if (substr($resp, 0, 3) !== '235') { $err = "SMTP login failed — check PAYSLIP_SMTP_USER / PAYSLIP_SMTP_PASS (Gmail needs an App Password, not your normal password): $resp"; fclose($fp); return false; }

    $resp = $cmd("MAIL FROM: <$fromEmail>");
    if (substr($resp, 0, 1) !== '2') { $err = "Sender address rejected by SMTP server: $resp"; fclose($fp); return false; }
    $resp = $cmd("RCPT TO: <$to>");
    if (substr($resp, 0, 1) !== '2') { $err = "Recipient address rejected by SMTP server: $resp"; fclose($fp); return false; }

    $resp = $cmd("DATA");
    if (substr($resp, 0, 1) !== '3') { $err = "SMTP server refused DATA: $resp"; fclose($fp); return false; }

    $encodedSubject = "=?UTF-8?B?" . base64_encode($subject) . "?=";
    $headers = "From: $fromName <$fromEmail>\r\n"
             . "To: <$to>\r\n"
             . "Subject: $encodedSubject\r\n"
             . "MIME-Version: 1.0\r\n"
             . "Content-Type: text/html; charset=UTF-8\r\n"
             . "Date: " . date('r') . "\r\n";

    // Dot-stuffing per SMTP spec: any line starting with "." must have a
    // second "." prepended, or the server treats it as end-of-message.
    $bodyStuffed = preg_replace('/^\./m', '..', $htmlBody);
    $data = $headers . "\r\n" . $bodyStuffed . "\r\n.";

    $resp = $cmd($data);
    if (substr($resp, 0, 3) !== '250') { $err = "SMTP server rejected the message: $resp"; fclose($fp); return false; }

    $cmd("QUIT");
    fclose($fp);
    return true;
}

// ============================================================================
// SEND PAYSLIP EMAIL — called ONLY from the Management approval action below.
// Nothing else in this file emails a payslip; salary release to an employee's
// inbox happens exclusively after Management approves the record.
// ============================================================================
function send_payslip_email($dbConn, $pid, &$err = null) {
    $ps = buildPayslipHtml($dbConn, $pid);
    if(!$ps) { $err = 'Payroll record not found.'; return false; }
    $d = $ps['data'];

    $to = trim($d['emp_email'] ?? '');
    if(empty($to) || !filter_var($to, FILTER_VALIDATE_EMAIL)) {
        $err = 'No personal email on file for '.$d['name'].'.';
        return false;
    }

    // Email clients strip onclick="" JS handlers, so the in-page
    // "PRINT / SAVE AS PDF" button does nothing when embedded in an
    // email -- swap it for a real link to the live payslip page instead,
    // where printing/saving actually works.
    $scheme      = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host        = $_SERVER['HTTP_HOST'] ?? 'crm.abra-logistic.com';
    $script_path = $_SERVER['PHP_SELF'] ?? '/dashboard/hr-payroll.php';
    $payslip_url = $scheme.'://'.$host.$script_path.'?download_payslip='.$pid;
    $print_btn_html = '<div class="pb no-print"><button onclick="window.print()">PRINT / SAVE AS PDF</button></div>';
    $print_link_html = '<div style="text-align:center;padding:12px;"><a href="'.htmlspecialchars($payslip_url).'" style="display:inline-block;background:#1e3a8a;color:white;padding:12px 30px;border-radius:5px;font-size:14px;font-weight:600;text-decoration:none;">View / Print / Save as PDF</a></div>';

    if(PAYSLIP_SMTP_PASS === 'REPLACE_WITH_MAILBOX_PASSWORD') {
        $err = 'SMTP is not configured yet — set PAYSLIP_SMTP_PASS (and confirm PAYSLIP_SMTP_HOST/PORT) at the top of this file.';
        return false;
    }

    $month_name   = date("F", mktime(0,0,0,$d['pay_month'],10));
    $company_name = $d['company_name'] ?: 'Abra E Logistics Private Limited';
    $subject      = 'Payslip - '.$month_name.' '.$d['pay_year'].' - '.$company_name;

    $email_html = str_replace($print_btn_html, $print_link_html, $ps['html']);
    $body = '<div style="padding:20px 20px 0;font-family:Arial,sans-serif;">'
          . '<p>Dear '.htmlspecialchars(trim($d['name'])).',</p>'
          . '<p>This is your payslip for <strong>'.$month_name.' '.$d['pay_year'].'</strong>. Please find it attached below.</p>'
          . '</div>'
          . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="height:30px;line-height:30px;font-size:1px;">&nbsp;</td></tr></table>'
          . $email_html
          . '<p style="font-size:11px;color:#94a3b8;margin-top:10px;">This is a system-generated email. Please do not reply.</p>';

    $smtp_err = null;
    $sent = smtp_send_mail($to, $subject, $body, $smtp_err);
    if(!$sent) {
        $err = $smtp_err ?: ('Failed to send to '.$to.'.');
        error_log("Payslip SMTP send failed for payroll id $pid to $to: " . $err);
        return false;
    }
    return true;
}

// ============================================================================
// DOWNLOAD PAYSLIP (view / print — unrelated to the approval email; anyone
// with access to this page can still preview a payslip before approving it)
// ============================================================================
if(isset($_GET['download_payslip'])) {
    $pid = intval($_GET['download_payslip']);
    $ps  = buildPayslipHtml($dbConn, $pid);
    if(!$ps) die("Not found");

    $is_staff_viewer = ($is_abishek || $is_keerti || $is_md || $is_hr);
    $is_own_payslip  = (!empty($currentUserName) && !empty($ps['data']['name'])
        && (stripos($ps['data']['name'], $currentUserName) !== false || stripos($currentUserName, $ps['data']['name']) !== false));
    if(!$is_staff_viewer && !$is_own_payslip)
        die("<div style='font-family:Arial;text-align:center;margin-top:100px;'><h2>Access Denied</h2><p>You can only view your own payslip.</p></div>");

    if (ob_get_level() > 0) { ob_end_clean(); }
    echo $ps['html'];
    exit;
}

// ============================================================================
// BULK MARK HOLIDAY
// ============================================================================
if(isset($_POST['bulk_mark_holiday'])) {
    $emp_ids   = $_POST['employee_ids'] ?? [];
    $from_date = mysqli_real_escape_string($dbConn, $_POST['from_date']);
    $to_date   = mysqli_real_escape_string($dbConn, $_POST['to_date']);
    $status    = mysqli_real_escape_string($dbConn, $_POST['mark_status']);
    $reason    = mysqli_real_escape_string($dbConn, $_POST['mark_reason']);
    if(empty($emp_ids)) { $_SESSION['msg'] = "❌ Select at least one employee"; }
    else {
        $cnt      = 0;
        $interval = (new DateTime($to_date))->diff(new DateTime($from_date))->days + 1;
        foreach($emp_ids as $eid) {
            $eid = intval($eid);
            $emp_info_q = mysqli_query($dbConn, "SELECT employee_id, name FROM hr_employees WHERE id=$eid");
            if(!$emp_info_q || mysqli_num_rows($emp_info_q) == 0) continue;
            $emp_info = mysqli_fetch_assoc($emp_info_q);
            $emp_emp_id = mysqli_real_escape_string($dbConn, $emp_info['employee_id']);
            $emp_name = mysqli_real_escape_string($dbConn, $emp_info['name']);

            for($i=0; $i<$interval; $i++) {
                $dt  = date('Y-m-d', strtotime("$from_date +$i days"));
                
                if ($status == 'force_login') {
                    $in_time = mysqli_real_escape_string($dbConn, $_POST['f_in_time'] ?? '09:00');
                    $out_time = mysqli_real_escape_string($dbConn, $_POST['f_out_time'] ?? '18:00');
                    
                    $raw_seconds = strtotime("$dt $out_time") - strtotime("$dt $in_time");
                    $raw_hours   = $raw_seconds / 3600;
                    $final_hours = ($raw_hours > 1) ? $raw_hours - 1 : $raw_hours;
                    $hours       = max(0, round($final_hours, 2));
                    
                    $chk_att = mysqli_query($dbConn, "SELECT id FROM hr_attendance WHERE employee_id='$emp_emp_id' AND date='$dt'");
                    if (mysqli_num_rows($chk_att) > 0) {
                        mysqli_query($dbConn, "UPDATE hr_attendance SET check_in_time='$in_time', check_out_time='$out_time', work_hours='$hours', status='present', check_in_location='Force In by HR' WHERE employee_id='$emp_emp_id' AND date='$dt'");
                    } else {
                        mysqli_query($dbConn, "INSERT INTO hr_attendance (employee_id, employee_name, date, check_in_time, check_out_time, work_hours, status, check_in_location, check_out_location, daily_salary) VALUES ('$emp_emp_id', '$emp_name', '$dt', '$in_time', '$out_time', '$hours', 'present', 'Force In by HR', 'Force In by HR', '0')");
                    }
                } else {
                    $chk = mysqli_query($dbConn,"SELECT id FROM hr_attendance_overrides WHERE employee_id=$eid AND attendance_date='$dt'");
                    if(mysqli_num_rows($chk)>0)
                        mysqli_query($dbConn,"UPDATE hr_attendance_overrides SET status='$status',reason='$reason',created_by='$currentUserName' WHERE employee_id=$eid AND attendance_date='$dt'");
                    else
                        mysqli_query($dbConn,"INSERT INTO hr_attendance_overrides (employee_id,attendance_date,status,reason,created_by) VALUES ($eid,'$dt','$status','$reason','$currentUserName')");
                }
                $cnt++;
            }
        }
        $lbl = ($status == 'force_login') ? 'Force Log In' : ucfirst($status);
        $_SESSION['msg'] = "✓ Marked $cnt days for ".count($emp_ids)." employee(s) as $lbl. Regenerate payroll to update.";
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// DELETE OVERRIDE
// ============================================================================
if(isset($_POST['delete_override'])) {
    mysqli_query($dbConn,"DELETE FROM hr_attendance_overrides WHERE id=".intval($_POST['override_id']));
    $_SESSION['msg'] = "✓ Override removed";
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// FORCE OUT (FORCE LOGOUT) — moved here from Attendance page
// HR sets a check-out time for employees who forgot to log off.
// After forcing out, click "Generate Payroll" to refresh salary numbers.
// ============================================================================
if(isset($_POST['force_checkout'])) {
    try {
        $att_id   = intval($_POST['att_id']);
        $out_time = preg_replace('/[^0-9:]/','', $_POST['force_out_time'] ?? '');
        if(empty($out_time)) $out_time = '18:00';
        if(strlen($out_time) == 5) $out_time .= ':00';

        $rq = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE id=$att_id LIMIT 1");
        if(!$rq || mysqli_num_rows($rq)==0) throw new Exception("Attendance record not found");
        $rec = mysqli_fetch_assoc($rq);
        if(!empty($rec['check_out_time'])) throw new Exception("Already checked out at ".date('h:i A', strtotime($rec['check_out_time'])));

        // Work hours = checkout − checkin (same day)
        $in_dt  = $rec['date'].' '.$rec['check_in_time'];
        $out_dt = $rec['date'].' '.$out_time;
        $secs   = strtotime($out_dt) - strtotime($in_dt);
        if($secs <= 0) throw new Exception("Force-out time must be AFTER check-in time (".date('h:i A', strtotime($rec['check_in_time'])).")");
        $hours = round($secs / 3600, 2);

        $out_safe = mysqli_real_escape_string($dbConn, $out_time);
        mysqli_query($dbConn, "UPDATE hr_attendance SET
            check_out_time='$out_safe',
            work_hours='$hours',
            check_out_location='Force Out by HR (Payroll) - $currentUserName'
            WHERE id=$att_id");
        if(mysqli_error($dbConn)) throw new Exception(mysqli_error($dbConn));

        $_SESSION['msg'] = "✓ Force Out done for <strong>".htmlspecialchars($rec['employee_name'])."</strong> on ".date('d M Y', strtotime($rec['date']))." at ".date('h:i A', strtotime($out_time))." ($hours hrs). <strong>Click \"Generate Payroll\" to update salary.</strong>";
    } catch(Exception $e) { $_SESSION['msg'] = "❌ Force Out error: ".$e->getMessage(); }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// BULK FORCE OUT — multi-select: force logout for MANY records at once
// ============================================================================
if(isset($_POST['bulk_force_checkout'])) {
    $att_ids = $_POST['att_ids'] ?? [];
    $times   = $_POST['force_out_time'] ?? [];
    if(empty($att_ids)) {
        $_SESSION['msg'] = "❌ Select at least one record to Force Out (tick the checkboxes)";
        header("Location: ".$_SERVER['PHP_SELF']); exit;
    }
    $done = 0; $errs = [];
    foreach($att_ids as $aid) {
        $aid = intval($aid);
        try {
            $out_time = preg_replace('/[^0-9:]/','', $times[$aid] ?? '18:00');
            if(empty($out_time)) $out_time = '18:00';
            if(strlen($out_time) == 5) $out_time .= ':00';

            $rq = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE id=$aid LIMIT 1");
            if(!$rq || mysqli_num_rows($rq)==0) throw new Exception("Record #$aid not found");
            $rec = mysqli_fetch_assoc($rq);
            if(!empty($rec['check_out_time'])) throw new Exception($rec['employee_name']." (".date('d M', strtotime($rec['date'])).") already checked out");

            $secs = strtotime($rec['date'].' '.$out_time) - strtotime($rec['date'].' '.$rec['check_in_time']);
            if($secs <= 0) throw new Exception($rec['employee_name']." (".date('d M', strtotime($rec['date'])).") — force-out time must be after check-in ".date('h:i A', strtotime($rec['check_in_time'])));
            $hours = round($secs / 3600, 2);

            $out_safe = mysqli_real_escape_string($dbConn, $out_time);
            mysqli_query($dbConn, "UPDATE hr_attendance SET
                check_out_time='$out_safe',
                work_hours='$hours',
                check_out_location='Force Out by HR (Payroll Bulk) - $currentUserName'
                WHERE id=$aid");
            if(mysqli_error($dbConn)) throw new Exception(mysqli_error($dbConn));
            $done++;
        } catch(Exception $e) { $errs[] = $e->getMessage(); }
    }
    $msg = "✓ Force Out done for <strong>$done record(s)</strong>. <strong>Click \"Generate Payroll\" to update salaries.</strong>";
    if(count($errs)) $msg .= "<br><small style='color:#dc2626'>⚠️ ".implode("; ", array_slice($errs,0,4))."</small>";
    $_SESSION['msg'] = $msg;
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// BULK FORCE LOG IN — multi-select: for employees who missed morning punch
// ============================================================================
if(isset($_POST['bulk_force_login'])) {
    $att_ids = $_POST['att_ids'] ?? [];
    $times   = $_POST['force_in_time'] ?? [];
    if(empty($att_ids)) {
        $_SESSION['msg'] = "❌ Select at least one record to Force Log In (tick the checkboxes)";
        header("Location: ".$_SERVER['PHP_SELF']); exit;
    }
    $done = 0; $errs = [];
    foreach($att_ids as $aid) {
        $aid = intval($aid);
        try {
            $in_time = preg_replace('/[^0-9:]/','', $times[$aid] ?? '09:00');
            if(empty($in_time)) $in_time = '09:00';
            if(strlen($in_time) == 5) $in_time .= ':00';

            $rq = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE id=$aid LIMIT 1");
            if(!$rq || mysqli_num_rows($rq)==0) throw new Exception("Record #$aid not found");
            $rec = mysqli_fetch_assoc($rq);
            if(!empty($rec['check_out_time'])) throw new Exception($rec['employee_name']." (".date('d M', strtotime($rec['date'])).") already has check-out");

            $existing_punch = $rec['check_in_time'];
            
            $secs = strtotime($rec['date'].' '.$existing_punch) - strtotime($rec['date'].' '.$in_time);
            if($secs <= 0) {
                // assume next day crossover
                $secs = strtotime($rec['date'].' '.$existing_punch.' +1 day') - strtotime($rec['date'].' '.$in_time);
            }
            $hours = round($secs / 3600, 2);

            $in_safe = mysqli_real_escape_string($dbConn, $in_time);
            $out_safe = mysqli_real_escape_string($dbConn, $existing_punch);
            $curr = mysqli_real_escape_string($dbConn, $currentUserName);
            
            mysqli_query($dbConn, "UPDATE hr_attendance SET
                check_in_time='$in_safe',
                check_out_time='$out_safe',
                work_hours='$hours',
                check_in_location='Force In by HR (Payroll Bulk) - $curr'
                WHERE id=$aid");
            if(mysqli_error($dbConn)) throw new Exception(mysqli_error($dbConn));
            $done++;
        } catch(Exception $e) { $errs[] = $e->getMessage(); }
    }
    $msg = "✓ Force Log In done for <strong>$done record(s)</strong>. <strong>Click \"Generate Payroll\" to update salaries.</strong>";
    if(count($errs)) $msg .= "<br><small style='color:#dc2626'>⚠️ ".implode("; ", array_slice($errs,0,4))."</small>";
    $_SESSION['msg'] = $msg;
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// BULK FORCE LOG IN — multi-select: for employees who missed morning punch
// ============================================================================
if(isset($_POST['bulk_force_login'])) {
    $att_ids = $_POST['att_ids'] ?? [];
    $times   = $_POST['force_in_time'] ?? [];
    if(empty($att_ids)) {
        $_SESSION['msg'] = "❌ Select at least one record to Force Log In (tick the checkboxes)";
        header("Location: ".$_SERVER['PHP_SELF']); exit;
    }
    $done = 0; $errs = [];
    foreach($att_ids as $aid) {
        $aid = intval($aid);
        try {
            $in_time = preg_replace('/[^0-9:]/','', $times[$aid] ?? '09:00');
            if(empty($in_time)) $in_time = '09:00';
            if(strlen($in_time) == 5) $in_time .= ':00';

            $rq = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE id=$aid LIMIT 1");
            if(!$rq || mysqli_num_rows($rq)==0) throw new Exception("Record #$aid not found");
            $rec = mysqli_fetch_assoc($rq);
            if(!empty($rec['check_out_time'])) throw new Exception($rec['employee_name']." (".date('d M', strtotime($rec['date'])).") already has check-out");

            $existing_punch = $rec['check_in_time'];
            
            $secs = strtotime($rec['date'].' '.$existing_punch) - strtotime($rec['date'].' '.$in_time);
            if($secs <= 0) {
                // assume next day crossover
                $secs = strtotime($rec['date'].' '.$existing_punch.' +1 day') - strtotime($rec['date'].' '.$in_time);
            }
            $hours = round($secs / 3600, 2);

            $in_safe = mysqli_real_escape_string($dbConn, $in_time);
            $out_safe = mysqli_real_escape_string($dbConn, $existing_punch);
            $curr = mysqli_real_escape_string($dbConn, $currentUserName);
            
            mysqli_query($dbConn, "UPDATE hr_attendance SET
                check_in_time='$in_safe',
                check_out_time='$out_safe',
                work_hours='$hours',
                check_in_location='Force In by HR (Payroll Bulk) - $curr'
                WHERE id=$aid");
            if(mysqli_error($dbConn)) throw new Exception(mysqli_error($dbConn));
            $done++;
        } catch(Exception $e) { $errs[] = $e->getMessage(); }
    }
    $msg = "✓ Force Log In done for <strong>$done record(s)</strong>. <strong>Click \"Generate Payroll\" to update salaries.</strong>";
    if(count($errs)) $msg .= "<br><small style='color:#dc2626'>⚠️ ".implode("; ", array_slice($errs,0,4))."</small>";
    $_SESSION['msg'] = $msg;
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// DELETE PAYROLL
// ============================================================================
if(isset($_POST['delete_payroll'])) {
    $pid = intval($_POST['payroll_id']);
    $r   = mysqli_query($dbConn,"SELECT e.name,p.pay_month,p.pay_year FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE p.id=$pid LIMIT 1");
    if($r && mysqli_num_rows($r)>0) {
        $rec = mysqli_fetch_assoc($r);
        if(mysqli_query($dbConn,"DELETE FROM hr_payroll WHERE id=$pid"))
            $_SESSION['msg'] = "✓ Deleted for <strong>{$rec['name']}</strong> (".date("F",mktime(0,0,0,$rec['pay_month'],10))." {$rec['pay_year']})";
        else $_SESSION['msg'] = "Error: ".mysqli_error($dbConn);
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// MANAGEMENT APPROVAL — APPROVE & RELEASE (sends payslip email ONLY here)
// ============================================================================
if(isset($_POST['approve_payroll'])) {
    $pid = intval($_POST['payroll_id']);
    if(!$can_approve_payroll) {
        $_SESSION['msg'] = "⛔ Only Management can approve payroll for payslip release.";
    } else {
        $by = mysqli_real_escape_string($dbConn, $currentUserName);
        mysqli_query($dbConn, "UPDATE hr_payroll SET approval_status='approved', approved_by='$by', approved_at=NOW() WHERE id=$pid");

        $err = null;
        $r = mysqli_query($dbConn,"SELECT e.name,p.pay_month,p.pay_year FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE p.id=$pid LIMIT 1");
        $rec = $r ? mysqli_fetch_assoc($r) : null;
        $label = $rec ? ($rec['name']." (".date("F",mktime(0,0,0,$rec['pay_month'],10))." ".$rec['pay_year'].")") : "record #$pid";

        if(send_payslip_email($dbConn, $pid, $err)) {
            mysqli_query($dbConn, "UPDATE hr_payroll SET payslip_sent=1, payslip_sent_at=NOW(), payslip_send_error=NULL WHERE id=$pid");
            $_SESSION['msg'] = "✓ Approved and payslip emailed for <strong>$label</strong>.";
        } else {
            $err_esc = mysqli_real_escape_string($dbConn, $err);
            mysqli_query($dbConn, "UPDATE hr_payroll SET payslip_sent=0, payslip_send_error='$err_esc' WHERE id=$pid");
            $_SESSION['msg'] = "✓ Approved for <strong>$label</strong>, but the payslip email failed: ".htmlspecialchars($err)." You can retry sending from the payroll row.";
        }
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// MANAGEMENT APPROVAL — REJECT / HOLD BACK (no email is ever sent for this)
// ============================================================================
if(isset($_POST['reject_payroll'])) {
    $pid = intval($_POST['payroll_id']);
    if(!$can_approve_payroll) {
        $_SESSION['msg'] = "⛔ Only Management can update payroll approval status.";
    } else {
        $by = mysqli_real_escape_string($dbConn, $currentUserName);
        mysqli_query($dbConn, "UPDATE hr_payroll SET approval_status='rejected', approved_by='$by', approved_at=NOW(), payslip_sent=0 WHERE id=$pid");
        $_SESSION['msg'] = "Payroll record held back — no payslip was sent.";
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// MANAGEMENT APPROVAL — BULK APPROVE & RELEASE SELECTED
// ============================================================================
if(isset($_POST['bulk_approve_payroll'])) {
    if(!$can_approve_payroll) {
        $_SESSION['msg'] = "⛔ Only Management can approve payroll for payslip release.";
    } else {
        $ids = $_POST['payroll_ids'] ?? [];
        $by  = mysqli_real_escape_string($dbConn, $currentUserName);
        $ok = 0; $fail = 0;
        foreach($ids as $rawId) {
            $pid = intval($rawId);
            if($pid <= 0) continue;
            mysqli_query($dbConn, "UPDATE hr_payroll SET approval_status='approved', approved_by='$by', approved_at=NOW() WHERE id=$pid");
            $err = null;
            if(send_payslip_email($dbConn, $pid, $err)) {
                mysqli_query($dbConn, "UPDATE hr_payroll SET payslip_sent=1, payslip_sent_at=NOW(), payslip_send_error=NULL WHERE id=$pid");
                $ok++;
            } else {
                $err_esc = mysqli_real_escape_string($dbConn, $err);
                mysqli_query($dbConn, "UPDATE hr_payroll SET payslip_sent=0, payslip_send_error='$err_esc' WHERE id=$pid");
                $fail++;
            }
        }
        $_SESSION['msg'] = "✓ Approved $ok payroll record(s)".($fail>0 ? ", $fail payslip email(s) failed to send (see row for details)." : " and emailed all payslips successfully.");
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// TOGGLE APPROVE OT (AJAX)
// ============================================================================
if(isset($_POST['toggle_approve_ot'])) {
    header('Content-Type: application/json');
    try {
        $pid = intval($_POST['pid']);
        $approved_days = floatval($_POST['approved_days']); 
        
        $q = mysqli_query($dbConn, "SELECT * FROM hr_payroll WHERE id=$pid LIMIT 1");
        if($q && mysqli_num_rows($q) > 0) {
            $old = mysqli_fetch_assoc($q);
            
            $gross = floatval($old['gross_pay']);
            $base_present = floatval($old['present_days']) + floatval($old['calendar_ot']) + floatval($old['reduce_days']);
            $reduce_days = floatval($old['reduce_days']);
            $new_total_present = max(0, $base_present - $reduce_days);
            
            $hr_extra_days = floatval($old['weekends_worked']) - floatval($old['approve_ot']);
            if($hr_extra_days < 0) $hr_extra_days = 0;
            
            $calc = calcSalary($gross, $new_total_present, 0, $hr_extra_days, $approved_days);
            
            $actual_approved = $calc['approve_ot'];
            $ot_days = floatval($calc['ot_days']);
            $per_day = floatval($calc['per_day']);
            $auto_ot = floatval($calc['ot_amount']);
            
            $ota = floatval($old['ot_amount']); 
            $arr = floatval($old['arrears']);
            $ovt = floatval($old['overtime']);
            $inc = floatval($old['incentives']);
            $oear = floatval($old['other_earnings']);
            $extras = $auto_ot + $arr + $ovt + $inc + $oear;
            
            $adv = floatval($old['advance_salary']);
            $pen = floatval($old['penalty']);
            $oded = floatval($old['other_deductions']);
            $pf = floatval($old['pf']);
            
            // Only sum up taxes/PF for the total_deduction column, but do NOT subtract them from net_salary
            // as per the company's rule (PF is totally separate)
            $new_deductions = $pf + floatval($old['esi']) + floatval($old['pt']) + floatval($old['tds']);
            
            // $calc['earned'] already accounts for absent days, so no need to subtract absent_deduct again.
            // Only subtract advance, penalty, and other deductions from the net take-home pay.
            $final_net = max(0, floatval($calc['earned']) + $extras - $adv - $pen - $oded);
            
            // Employee favorable rounding for net
            $decimal = $final_net - floor($final_net);
            $final_net = ($decimal >= 0.50) ? ceil($final_net) : floor($final_net);
            
            mysqli_query($dbConn, "UPDATE hr_payroll SET
                present_days={$calc['normal_days']}, absent_days={$calc['absent_days']},
                calendar_ot={$calc['calendar_ot']}, approve_ot=$actual_approved,
                weekends_worked=$ot_days, ot_amount=$auto_ot,
                total_deduction=$new_deductions, net_salary=$final_net, amount=$final_net
                WHERE id=$pid");
                
            echo json_encode(['success'=>true, 'msg'=>"OT approved days updated successfully."]);
        } else {
            echo json_encode(['success'=>false, 'msg'=>"Record not found."]);
        }
    } catch(Exception $e) {
        echo json_encode(['success'=>false, 'msg'=>$e->getMessage()]);
    }
    exit;
}

// ============================================================================
// EXCUSE LATE PENALTIES (AJAX)
// ============================================================================
if(isset($_POST['excuse_late_penalties'])) {
    header('Content-Type: application/json');
    try {
        $emp_db_id = intval($_POST['emp_id']);
        $monthStr = mysqli_real_escape_string($dbConn, $_POST['month']); // YYYY-MM
        
        $emp_query = mysqli_query($dbConn, "SELECT id, employee_id FROM hr_employees WHERE id = $emp_db_id LIMIT 1");
        if($emp_query && mysqli_num_rows($emp_query) > 0) {
            $emp = mysqli_fetch_assoc($emp_query);
            $emp_code = $emp['employee_id'];
            
            $start = "$monthStr-01";
            $end = "$monthStr-31";
            $q = mysqli_query($dbConn, "SELECT date FROM hr_attendance WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end' AND status='absent' AND late_policy_converted='Yes'");
            $count = 0;
            if($q) {
                while($r = mysqli_fetch_assoc($q)) {
                    $dt = $r['date'];
                    mysqli_query($dbConn, "DELETE FROM hr_attendance_overrides WHERE employee_id=$emp_db_id AND attendance_date='$dt'");
                    mysqli_query($dbConn, "INSERT INTO hr_attendance_overrides (employee_id, attendance_date, status, reason, created_by) VALUES ($emp_db_id, '$dt', 'present', 'Auto: Excused from Late Policy', '$currentUserName')");
                    $count++;
                }
            }
            if($count > 0) {
                echo json_encode(['success' => true, 'message' => "Excused $count late penalty days! Please click 'Generate Payroll' to recalculate the salary."]);
            } else {
                echo json_encode(['success' => false, 'error' => "No late penalties found for this month."]);
            }
        } else {
            echo json_encode(['success' => false, 'error' => "Employee not found."]);
        }
    } catch(Exception $e) {
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    }
    exit;
}

// ============================================================================
// EXPORT PDF SUMMARY (COMPANY & DEPARTMENT WISE)
// ============================================================================
if(isset($_POST['export_pdf_summary'])) {
    $from = $_POST['export_from'];
    $to   = $_POST['export_to'];
    
    // Grouping structure: [Company Name] => [Department Name] => [ array of employee rows ]
    $report = [];
    $md_exclude_sql_e = " AND (e.position IS NULL OR (LOWER(e.position) NOT LIKE '%managing director%' AND LOWER(e.position) NOT LIKE '%ceo%'))";
    $res = mysqli_query($dbConn, "SELECT p.*, e.name, e.employee_id as ec, COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as company_name, COALESCE(NULLIF(e.department,''),'Unassigned') as department FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$from' AND '$to' AND e.status='active' $md_exclude_sql_e ORDER BY company_name, department, e.name");
    
    if($res) {
        while($r = mysqli_fetch_assoc($res)) {
            $raw_c = trim($r['company_name']);
            // Normalize company name slightly for display group
            $company = strtoupper($raw_c);
            $dept = strtoupper(trim($r['department']));
            $report[$company][$dept][] = $r;
        }
    }
    
    echo '<!DOCTYPE html><html><head><title>Payroll Summary PDF</title>';
    echo '<style>
        body { font-family: Arial, sans-serif; font-size: 12px; margin: 20px; color:#000; }
        h1, h2, h3 { margin: 0 0 10px 0; }
        .page-break { page-break-before: always; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #000; padding: 5px 8px; text-align: left; }
        th { background: #eee; font-weight: bold; }
        .num { text-align: right; }
        .summary-row { font-weight: bold; background: #f9f9f9; }
        .company-header { background: #1e3a8a; color: #fff; padding: 10px; margin-top: 30px; font-size: 16px; font-weight: bold; border:2px solid #000; }
        .dept-header { background: #e5e7eb; color: #000; padding: 8px; margin-top: 15px; font-size: 14px; font-weight: bold; border:1px solid #000; border-bottom:none; }
        .grand-total { border: 3px solid #000; padding: 20px; font-size: 20px; font-weight: bold; background: #eee; margin-top: 40px; text-align:center; }
        @media print {
            body { margin: 0; }
            .no-print { display: none; }
            .company-header { background: #e5e7eb !important; color:#000 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        }
    </style></head><body>';
    
    echo '<div class="no-print" style="margin-bottom:20px;text-align:center;"><button onclick="window.print()" style="padding:12px 24px; font-size:16px; background:#1e3a8a; color:white; border:none; border-radius:5px; cursor:pointer;">Print / Save as PDF</button></div>';
    
    echo '<h1 style="text-align:center;">Payroll Spending Summary</h1>';
    echo '<p style="text-align:center;font-size:16px;"><strong>Period:</strong> ' . date('F Y', strtotime($from)) . '</p>';
    
    if(empty($report)) {
        echo '<h3 style="text-align:center;color:red;">No payroll records found for this period.</h3>';
        echo '</body></html>';
        exit;
    }
    
    $grand_total_gross = 0;
    $grand_total_net = 0;
    
    foreach($report as $company => $departments) {
        echo '<div class="company-header">' . htmlspecialchars($company) . '</div>';
        $company_total_gross = 0;
        $company_total_net = 0;
        
        foreach($departments as $dept => $employees) {
            echo '<div class="dept-header">Department: ' . htmlspecialchars($dept) . '</div>';
            echo '<table>';
            echo '<thead><tr><th>Emp Code</th><th>Employee Name</th><th class="num">Present</th><th class="num">Gross Pay</th><th class="num">Extras (OT)</th><th class="num">Deductions</th><th class="num">Net Salary</th></tr></thead>';
            echo '<tbody>';
            
            $dept_total_gross = 0;
            $dept_total_net = 0;
            $dept_total_ded = 0;
            
            foreach($employees as $emp) {
                $gross = floatval($emp['gross_pay']);
                $net = floatval($emp['net_salary']);
                $extras = floatval($emp['ot_amount']??$emp['ot']) + floatval($emp['incentives']) + floatval($emp['arrears']);
                $deductions = floatval($emp['penalty']) + floatval($emp['advance_salary']) + floatval($emp['other_deductions']) + floatval($emp['pf']);
                
                $dept_total_gross += $gross;
                $dept_total_net += $net;
                $dept_total_ded += $deductions;
                
                echo '<tr>';
                echo '<td>' . htmlspecialchars($emp['ec']) . '</td>';
                echo '<td>' . htmlspecialchars($emp['name']) . '</td>';
                echo '<td class="num">' . $emp['present_days'] . '</td>';
                echo '<td class="num">' . number_format($gross, 2) . '</td>';
                echo '<td class="num">' . number_format($extras, 2) . '</td>';
                echo '<td class="num">' . number_format($deductions, 2) . '</td>';
                echo '<td class="num" style="font-weight:bold;">' . number_format($net, 2) . '</td>';
                echo '</tr>';
            }
            
            $company_total_gross += $dept_total_gross;
            $company_total_net += $dept_total_net;
            
            echo '<tr class="summary-row">';
            echo '<td colspan="3" style="text-align:right;">' . htmlspecialchars($dept) . ' SUBTOTAL:</td>';
            echo '<td class="num">Rs. ' . number_format($dept_total_gross, 2) . '</td>';
            echo '<td class="num"></td>';
            echo '<td class="num">Rs. ' . number_format($dept_total_ded, 2) . '</td>';
            echo '<td class="num">Rs. ' . number_format($dept_total_net, 2) . '</td>';
            echo '</tr>';
            
            echo '</tbody></table>';
        }
        
        $grand_total_gross += $company_total_gross;
        $grand_total_net += $company_total_net;
        
        echo '<div style="text-align:right; font-size:16px; font-weight:bold; padding:12px; border:2px solid #000; margin-bottom:40px; background:#f3f4f6;">';
        echo htmlspecialchars($company) . ' TOTAL SPENT (NET): <span style="font-size:18px;">Rs. ' . number_format($company_total_net, 2) . '</span>';
        echo '</div>';
    }
    
    echo '<div class="grand-total">';
    echo 'GRAND TOTAL SPENT ACROSS ALL COMPANIES (NET): <span style="font-size:24px;">Rs. ' . number_format($grand_total_net, 2) . '</span>';
    echo '<br><span style="font-size:14px; font-weight:normal; color:#444;">(Total Gross Spending: Rs. ' . number_format($grand_total_gross, 2) . ')</span>';
    echo '</div>';
    
    echo '<script>window.print();</script>';
    echo '</body></html>';
    exit;
}

// ============================================================================
// EXPORT CSV
// ============================================================================
if(isset($_POST['export_csv'])) {
    $from = $_POST['export_from'];
    $to   = $_POST['export_to'];
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=Payroll_'.$from.'_to_'.$to.'.csv');
    $out = fopen('php://output','w');
    fputcsv($out,['Month','Year','Emp ID','Name','Basic','HRA','Conv','Special','Gross','Per Day','Present Days','Paid Leave Days','Absent Days','OT Days','OT Amount','Arrears Days','Arrears','Overtime','Incentives','Other Earnings','PF','Total CTC','Advance','Penalty','Other Deductions','Net Salary','Pay Date']);
    $md_exclude_sql_e = " AND (e.position IS NULL OR (LOWER(e.position) NOT LIKE '%managing director%' AND LOWER(e.position) NOT LIKE '%ceo%'))";
    $res = mysqli_query($dbConn,"SELECT p.*,e.name,e.employee_id as ec FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$from' AND '$to' AND e.status='active' $md_exclude_sql_e ORDER BY p.pay_year DESC,p.pay_month DESC,e.name");
    while($r=mysqli_fetch_assoc($res)) {
        $ot_val  = $r['ot_amount']??$r['ot'];
        $ot_days = $r['weekends_worked']??0;
        fputcsv($out,[date("F",mktime(0,0,0,$r['pay_month'],10)),$r['pay_year'],$r['ec'],$r['name'],
            $r['basic_salary'],$r['hra'],$r['conveyance'],$r['special_allowance'],$r['gross_pay'],
            isset($r['per_day_salary'])?$r['per_day_salary']:round($r['gross_pay']/26,2),
            $r['present_days'],$r['paid_leave_days']??0,$r['absent_days'],$ot_days,$ot_val,
            $r['arrears_days']??0,$r['arrears'],$r['overtime'],$r['incentives'],$r['other_earnings']??0,
            $r['pf'],$r['total_ctc'],
            $r['advance_salary'],$r['penalty'],$r['other_deductions']??0,$r['net_salary'],$r['pay_date']]);
    }
    fclose($out); exit;
}

// ============================================================================
// AUTO GENERATE PAYROLL
// ============================================================================
if(isset($_POST['auto_generate'])) {
    try {
        if(!empty($_POST['filter_from'])) {
            $dp = explode('-',$_POST['filter_from']);
            $yr = intval($dp[0]);
            $mo = intval($dp[1]);
        } else { $mo=date('n'); $yr=date('Y'); }

        $add_working_days = intval($_POST['add_working_days']);
        $global_reduce_days = floatval($_POST['reduce_working_days'] ?? 0);
        $prev_global_reduce = floatval($_SESSION['payroll_reduce_working_days'] ?? 0);
        $global_reduce_changed = ($global_reduce_days !== $prev_global_reduce);
        $total_days       = cal_days_in_month(CAL_GREGORIAN,$mo,$yr);
        $pay_date         = date('Y-m-d', mktime(0,0,0,$mo+1,10,$yr));

        // ── Auto-fetch holidays from hr_office_holidays for this month/year ──
        $hol_res = mysqli_query($dbConn, "SELECT holiday_date FROM hr_office_holidays WHERE year=$yr AND month=$mo ORDER BY holiday_date ASC");
        $holiday_dates = [];
        if($hol_res) while($hd = mysqli_fetch_assoc($hol_res)) $holiday_dates[] = $hd['holiday_date'];
        $holidays = count($holiday_dates); // total holidays this month (used for existing employees)

        $md_exclude_sql = " AND (position IS NULL OR (LOWER(position) NOT LIKE '%managing director%' AND LOWER(position) NOT LIKE '%ceo%'))";
        $emps = mysqli_query($dbConn,"SELECT id,employee_id,name,salary,employee_type,COALESCE(pf,0) as employee_pf,hire_date FROM hr_employees WHERE status='active' $md_exclude_sql ORDER BY name");
        $created=$updated=0; $errors=[];

        while($emp=mysqli_fetch_assoc($emps)) {
            try {
                $eid       = intval($emp['id']);
                $ecd       = mysqli_real_escape_string($dbConn,$emp['employee_id']);
                $enm       = mysqli_real_escape_string($dbConn,$emp['name']);
                $hire_date = $emp['hire_date'];

                // Skip if not joined yet
                $month_end = "$yr-".str_pad($mo,2,'0',STR_PAD_LEFT)."-".str_pad($total_days,2,'0',STR_PAD_LEFT);
                if(!empty($hire_date) && strtotime($hire_date) > strtotime($month_end)) continue;

                // ── Eligibility: count only holidays ON OR AFTER the employee's hire_date ──
                $emp_holidays = 0;
                foreach($holiday_dates as $hdate) {
                    if(empty($hire_date) || strtotime($hdate) >= strtotime($hire_date)) {
                        $emp_holidays++;
                    }
                }

                // Get TOTAL attendance days (ALL days including Sundays)
                $att = getTotalAttendanceDays($dbConn,$eid,$ecd,$mo,$yr);
                $total_present_bio = $att['total'];

                // FEATURE: paid leave days for this employee/month, for its own column
                $paid_leave_days = $att['paid_leave_days'];
                $total_late = $att['total_late'];

                // Add holidays and HR extra days
                // emp_holidays = only holidays on/after hire_date (eligibility checked above)
                $month_start = "$yr-".str_pad($mo,2,'0',STR_PAD_LEFT)."-01";
                $extra       = $emp_holidays + $add_working_days;

                // Check existing record FIRST so we can carry over approve_ot and reduce_days
                $ex = mysqli_query($dbConn,"SELECT id,arrears,arrears_days,COALESCE(ot_amount,ot) as ot_val,overtime,incentives,COALESCE(other_earnings,0) as other_earnings,COALESCE(other_deductions,0) as other_deductions,advance_salary,penalty,approve_ot,reduce_days FROM hr_payroll WHERE employee_id=$eid AND pay_month=$mo AND pay_year=$yr LIMIT 1");
                
                $approve_ot = 0;
                $reduce_days = $global_reduce_days;
                $exr = null;
                
                if($ex && mysqli_num_rows($ex)>0) {
                    $exr = mysqli_fetch_assoc($ex);
                    $approve_ot = intval($exr['approve_ot']);
                    
                    if ($global_reduce_changed) {
                        $reduce_days = $global_reduce_days;
                    } else {
                        $reduce_days = floatval($exr['reduce_days']);
                    }
                }

                // TOTAL PRESENT = biometric + overrides + eligible holidays + HR added days
                $total_present = $total_present_bio + $emp_holidays; // only add holidays to present, not manual extra days
                
                // Apply manual reduce_days
                $total_present = max(0, $total_present - $reduce_days);
                
                $extra_ot = $add_working_days; // HR added days go straight to OT

                // CORE CALCULATION — simple and clean
                $gross  = floatval(str_replace(',','',$emp['salary']));
                $calc   = calcSalary($gross, $total_present, $att['total_absent'], $extra_ot, $approve_ot);

                $per_day     = $calc['per_day'];
                $normal_days = $calc['normal_days'];  // capped at 26
                $ot_days     = $calc['ot_days'];       // beyond 26
                $absent_days = $calc['absent_days'];
                $auto_ot     = $calc['ot_amount'];     // auto calculated
                $earned      = $calc['earned'];
                $calendar_ot = $calc['calendar_ot'];

                // Salary structure breakdown
                $basic   = round($gross*0.40,2);
                $hra     = round($basic*0.50,2);
                $conv    = 3000;
                $special = max(0,round($gross-($basic+$hra+$conv),2));

                $pf = floatval($emp['employee_pf']);
                if($pf==0 && stripos($emp['employee_type'],'Permanent')!==false) $pf=round($basic*0.12,2);
                if($pf<0) $pf=0;

                $total_ctc = $gross + $pf + $auto_ot;
                $policy_note = $att['penalty_applies'] ? "no-logout=0.5d" : "PRE-JUN2026: no-logout=FULL day (no cut)";
                $comment   = mysqli_real_escape_string($dbConn,"Auto | Total present: $total_present (reduced by: $reduce_days) | $policy_note | OT days: $ot_days | OT: ₹$auto_ot | " . $att['half_days'] . " half-day | " . $att['unpaid_leave_days'] . " unpaid-leave | " . $att['late_policy_absents'] . " late-absent");

                if($exr) {
                    $exid     = $exr['id'];
                    $arr_days = floatval($exr['arrears_days']);
                    $arr      = round($arr_days * $per_day, 2); // recalc arrears from days
                    $ovt      = floatval($exr['overtime']);
                    $inc      = floatval($exr['incentives']);
                    $oear     = floatval($exr['other_earnings']);
                    $oded     = floatval($exr['other_deductions']);
                    $adv      = floatval($exr['advance_salary']);
                    $pen      = floatval($exr['penalty']);

                    // Net = earned from normal days + auto OT + manual extras - deductions
                    $net       = max(0, $earned + $auto_ot + $arr + $ovt + $inc + $oear - $adv - $pen - $oded);
                    $total_ctc = $gross + $pf + $auto_ot + $arr + $ovt + $inc + $oear;

                    mysqli_query($dbConn,"UPDATE hr_payroll SET
                        basic_salary=$basic,hra=$hra,conveyance=$conv,special_allowance=$special,gross_pay=$gross,
                        pf=$pf,total_deduction=$pf,total_ctc=$total_ctc,
                        present_days=$normal_days,absent_days=$absent_days,working_days=26,
                        paid_leave_days=$paid_leave_days, late_days=$total_late,
                        holidays_in_month=$emp_holidays,
                        ot_amount=$auto_ot,weekends_worked=$ot_days,
                        arrears_days=$arr_days,arrears=$arr,
                        net_salary=$net,per_day_salary=$per_day,amount=$net,
                        pay_date='$pay_date',comment='$comment',
                        calendar_ot=$calendar_ot, approve_ot=$approve_ot, reduce_days=$reduce_days
                        WHERE id=$exid");
                    if(!mysqli_error($dbConn)) $updated++;
                    else $errors[] = "$enm: ".mysqli_error($dbConn);

                } else {
                    $net       = max(0, $earned + $auto_ot);
                    $total_ctc = $gross + $pf + $auto_ot;

                    mysqli_query($dbConn,"INSERT INTO hr_payroll (
                        employee_id,basic_salary,hra,conveyance,special_allowance,gross_pay,
                        arrears,ot,overtime,incentives,ot_amount,
                        pf,esi,pt,tds,total_deduction,total_ctc,
                        pay_date,pay_month,pay_year,amount,
                        present_days,absent_days,working_days,paid_leave_days,late_days,
                        weekends_in_month,holidays_in_month,weekends_worked,holidays_worked,
                        advance_salary,net_salary,per_day_salary,penalty,comment,
                        calendar_ot, approve_ot, reduce_days
                    ) VALUES (
                        $eid,$basic,$hra,$conv,$special,$gross,
                        0,0,0,0,$auto_ot,
                        $pf,0,0,0,$pf,$total_ctc,
                        '$pay_date',$mo,$yr,$net,
                        $normal_days,$absent_days,26,$paid_leave_days,$total_late,
                        0,$emp_holidays,$ot_days,0,
                        0,$net,$per_day,0,'$comment',
                        $calendar_ot, $approve_ot, $reduce_days
                    )");
                    if(!mysqli_error($dbConn)) $created++;
                    else $errors[] = "$enm: ".mysqli_error($dbConn);
                }

            } catch(Exception $e) { $errors[]=$emp['name'].": ".$e->getMessage(); }
        }

        $mn  = date('F Y',mktime(0,0,0,$mo,1,$yr));
        $msg = "✓ Payroll generated for <strong>$mn</strong> | Holidays auto-fetched: $holidays (per employee eligibility applied) | Add Days: $add_working_days | Created: $created | Updated: $updated";
        if(count($errors)) $msg .= "<br><small style='color:red'>".implode("; ",array_slice($errors,0,3))."</small>";
        $msg .= "<br><small style='color:#059669'>💡 All days counted (including Sundays). Days beyond 26 = auto OT.</small>";
        $_SESSION['msg'] = $msg;
        $_SESSION['payroll_filter_from']      = $_POST['filter_from'] ?? '';
        $_SESSION['payroll_filter_to']        = $_POST['filter_to']   ?? '';
        $_SESSION['payroll_add_working_days'] = $add_working_days;
        $_SESSION['payroll_reduce_working_days'] = $global_reduce_days;

    } catch(Exception $e) { $_SESSION['msg']="Error: ".$e->getMessage(); }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// UPDATE SINGLE PAYROLL
// ============================================================================
if(isset($_POST['update_payroll'])) {
    try {
        $id  = intval($_POST['payroll_id']);
        $old = mysqli_fetch_assoc(mysqli_query($dbConn,"SELECT * FROM hr_payroll WHERE id=$id LIMIT 1"));
        if(!$old) throw new Exception("Not found");

        $approve_ot  = isset($_POST['approve_ot']) ? floatval($_POST['approve_ot']) : floatval($old['approve_ot']);
        $reduce_days = floatval($_POST['reduce_days'] ?? 0);

        $arr_days = floatval($_POST['arrears_days']);
        $ota      = floatval($_POST['ot_amount']);
        $ovt      = floatval($_POST['overtime']);
        $inc      = floatval($_POST['incentives']);
        $adv      = floatval($_POST['advance']);
        $pen      = floatval($_POST['penalty']);
        $oear     = floatval($_POST['other_earnings']);
        $oded     = floatval($_POST['other_deductions']);

        $gross    = floatval($old['gross_pay']);
        $pf       = floatval($old['pf']);
        $per_day  = floatval($old['per_day_salary']) ?: round($gross/26,2);

        // 1. Reconstruct base_present and hr_extra_days
        $old_present_days = floatval($old['present_days']);
        $old_calendar_ot  = floatval($old['calendar_ot']);
        $old_reduce_days  = floatval($old['reduce_days']);
        $old_approve_ot   = intval($old['approve_ot']);
        $old_weekends     = floatval($old['weekends_worked']);
        
        $base_present = $old_present_days + $old_calendar_ot + $old_reduce_days;
        $hr_extra_days = $old_weekends - ($old_approve_ot ? $old_calendar_ot : 0);
        if($hr_extra_days < 0) $hr_extra_days = 0;
        
        // 2. Apply new reduction
        $new_total_present = max(0, $base_present - $reduce_days);
        
        // 3. Recalculate based on rules
        $calc = calcSalary($gross, $new_total_present, 0, $hr_extra_days, floatval($old['approve_ot']));
        
        $normal_days = $calc['normal_days'];
        $absent_days = $calc['absent_days'];
        $calendar_ot = $calc['calendar_ot'];
        
        $ot_days = $hr_extra_days + $calc['approve_ot'];
        $auto_ot = round($per_day * $ot_days, 2);

        // Arrears amount = arrears_days × per_day
        $arr = round($arr_days * $per_day, 2);

        // If HR manually entered OT AMOUNT, use that instead of calculated auto_ot
        $final_ot = ($ota > 0) ? $ota : $auto_ot;

        $earned = $per_day * $normal_days;
        $net    = max(0, $earned + $final_ot + $arr + $ovt + $inc + $oear - $adv - $pen - $oded);
        
        // Employee favorable rounding for net
        $decimal = $net - floor($net);
        $net     = ($decimal >= 0.50) ? ceil($net) : floor($net);

        $ctc    = $gross + $pf + $final_ot + $arr + $ovt + $inc + $oear;

        mysqli_query($dbConn,"UPDATE hr_payroll SET
            present_days=$normal_days, absent_days=$absent_days,
            working_days=26,
            calendar_ot=$calendar_ot, approve_ot=$approve_ot, reduce_days=$reduce_days,
            weekends_worked=$ot_days, ot_amount=$final_ot,
            arrears_days=$arr_days, arrears=$arr,
            overtime=$ovt, incentives=$inc,
            other_earnings=$oear, other_deductions=$oded,
            advance_salary=$adv, penalty=$pen,
            net_salary=$net, total_ctc=$ctc, amount=$net
            WHERE id=$id");
        if (isset($_POST['reject_after_edit'])) {
            if ($can_approve_payroll) {
                $by = mysqli_real_escape_string($dbConn, $currentUserName);
                mysqli_query($dbConn, "UPDATE hr_payroll SET approval_status='rejected', approved_by='$by', approved_at=NOW(), payslip_sent=0 WHERE id=$id");
                $_SESSION['msg'] = "✓ Payroll updated and Held Back.";
            } else {
                $_SESSION['msg'] = "✓ Payroll updated. (Hold Back failed: Only Management can update approval status).";
            }
        } else {
            $_SESSION['msg'] = mysqli_error($dbConn) ? "Error: ".mysqli_error($dbConn) : "✓ Payroll updated";
        }

    } catch(Exception $e) { $_SESSION['msg']="Error: ".$e->getMessage(); }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// FETCH DATA
// ============================================================================
$current_month = date('n');
$current_year  = date('Y');

$filter_from = $_POST['filter_from'] ?? $_SESSION['payroll_filter_from'] ?? date('Y-m-01');
$filter_to   = $_POST['filter_to']   ?? $_SESSION['payroll_filter_to']   ?? date('Y-m-t');

// Strips punctuation and common legal-entity suffix words ("pvt", "ltd",
// "private", "limited", etc.) so "Abra E Logistic" and "Abra E Logistic
// Pvt. Ltd." normalize to the same key — same fix already applied on the
// Employee List Overview page's Company chart.
function hr_normalize_company_name($s) {
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    $s = preg_replace('/\b(pvt|private|ltd|limited|llp|inc|incorporated|co|company|corp|corporation)\b/', '', $s);
    $s = trim(preg_replace('/\s+/', ' ', $s));
    return $s;
}

// Master company-name map, built once and reused everywhere a company-name
// duplicate could appear (summary table + the Overview tab's company chart /
// leaderboard) — normalized key -> the spelling actually registered in
// Departments > Companies (hr_companies), which is the source of truth.
$hr_master_companies_for_summary = [];
$mc_res = mysqli_query($dbConn, "SELECT company_name FROM hr_companies WHERE company_name IS NOT NULL AND company_name != ''");
if ($mc_res) { while ($mc_row = mysqli_fetch_assoc($mc_res)) { $hr_master_companies_for_summary[] = $mc_row['company_name']; } }
$company_norm_to_label = [];
foreach ($hr_master_companies_for_summary as $mcname) {
    $company_norm_to_label[hr_normalize_company_name($mcname)] = $mcname;
}
function hr_canonical_company_label($raw, $company_norm_to_label) {
    if ($raw === '' || $raw === '(No Company Set)') return $raw;
    $norm = hr_normalize_company_name($raw);
    return isset($company_norm_to_label[$norm]) ? $company_norm_to_label[$norm] : $raw;
}

// ✅ ROOT-CAUSE FIX: hr_companies only ever has ONE row per company — the
// duplicates showing up in this page's dropdown/filter come from employees'
// free-text company_name field having different spellings ("Abra E Logistic"
// vs "Abra E Logistic Pvt. Ltd." typed on different employee records), not
// from extra rows in hr_companies. Build a normalized-key -> [every raw
// spelling seen] map from BOTH hr_companies and hr_employees, so the dropdown
// can show one canonical entry per company and the filter can match every
// spelling variant, not just the one the dropdown option happens to say.
$company_norm_to_variants = [];
foreach ($hr_master_companies_for_summary as $mcname) {
    $norm = hr_normalize_company_name($mcname);
    if (!isset($company_norm_to_variants[$norm])) $company_norm_to_variants[$norm] = [];
    if (!in_array($mcname, $company_norm_to_variants[$norm])) $company_norm_to_variants[$norm][] = $mcname;
}
$emp_cn_res = mysqli_query($dbConn, "SELECT DISTINCT TRIM(company_name) as company_name FROM hr_employees WHERE company_name IS NOT NULL AND company_name != ''");
if ($emp_cn_res) {
    while ($ecn = mysqli_fetch_assoc($emp_cn_res)) {
        $raw = trim($ecn['company_name']);
        if ($raw === '') continue;
        $norm = hr_normalize_company_name($raw);
        if (!isset($company_norm_to_variants[$norm])) $company_norm_to_variants[$norm] = [];
        if (!in_array($raw, $company_norm_to_variants[$norm])) $company_norm_to_variants[$norm][] = $raw;
    }
}

// COMPANY / ENTITY FILTER — manager can view payroll per company
$filter_company = $_POST['filter_company'] ?? $_SESSION['payroll_filter_company'] ?? '';
if(isset($_POST['apply_filter'])) {
    $_SESSION['payroll_filter_from']    = $filter_from;
    $_SESSION['payroll_filter_to']      = $filter_to;
    $_SESSION['payroll_filter_company'] = $filter_company;
}
$company_sql = '';
if(!empty($filter_company)) {
    if ($filter_company === '(No Company Set)') {
        $company_sql = " AND COALESCE(NULLIF(e.company_name,''),'(No Company Set)') = '(No Company Set)' ";
    } else {
        // ✅ FIX: match ANY spelling variant that normalizes to the selected
        // company — so picking "Abra E Logistic" from the dropdown also
        // catches employees whose record says "Abra E Logistic Pvt. Ltd.",
        // instead of only the one exact spelling the option value holds.
        $filter_norm  = hr_normalize_company_name($filter_company);
        $variants     = isset($company_norm_to_variants[$filter_norm]) ? $company_norm_to_variants[$filter_norm] : [$filter_company];
        $variant_list = [];
        foreach ($variants as $v) { $variant_list[] = "'" . mysqli_real_escape_string($dbConn, trim($v)) . "'"; }
        $company_sql  = " AND TRIM(e.company_name) IN (" . implode(',', $variant_list) . ") ";
    }
}

// OVERVIEW TAB date range — independent of the list filter above, defaults to
// a 6-month window so the Monthly Trend chart actually has a trend to show.
$pv_filter_from = $_POST['pv_filter_from'] ?? $_SESSION['payroll_ov_from'] ?? date('Y-m-01', strtotime('-5 months'));
$pv_filter_to   = $_POST['pv_filter_to']   ?? $_SESSION['payroll_ov_to']   ?? date('Y-m-t');
if(isset($_POST['pv_apply_filter'])) {
    $_SESSION['payroll_ov_from'] = $pv_filter_from;
    $_SESSION['payroll_ov_to']   = $pv_filter_to;
}

// List of companies (from employees + hr_companies master)
// ✅ FIX: one dropdown entry per NORMALIZED company (using $company_norm_to_variants
// built above), not one per raw spelling — this is what actually collapses
// "Abra E Logistic" and "Abra E Logistic Pvt. Ltd." into a single option,
// since a plain trim/lower dedupe never caught that (genuinely different text).
$companies_list = [];
foreach ($company_norm_to_variants as $norm => $variants) {
    $companies_list[] = isset($company_norm_to_label[$norm]) ? $company_norm_to_label[$norm] : $variants[0];
}
sort($companies_list);

$saved_add = intval($_SESSION['payroll_add_working_days'] ?? 0);
$saved_reduce = floatval($_SESSION['payroll_reduce_working_days'] ?? 0);

$md_exclude_sql_e = " AND (e.position IS NULL OR (LOWER(e.position) NOT LIKE '%managing director%' AND LOWER(e.position) NOT LIKE '%ceo%'))";
$data = mysqli_query($dbConn,"SELECT p.*,e.name,e.employee_id as emp_code,e.personal_email as emp_email,COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as company_name FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$filter_from' AND '$filter_to' AND e.status='active' $company_sql $md_exclude_sql_e ORDER BY p.pay_year DESC,p.pay_month DESC,e.name");
if(!$data) die("Error: ".mysqli_error($dbConn));

// ============================================================================
// COMPANY-WISE (ENTITY-WISE) PAYROLL SUMMARY for the filtered period
// Per company: how many employees + how much we are paying
// ============================================================================
// ✅ FIX: a plain COALESCE/GROUP BY only catches an empty company_name — it still
// shows "Abra E Logistic" and "Abra E Logistic Pvt. Ltd." as two separate rows,
// because that's genuinely different text, not just formatting. This bucket is
// now built in PHP using the legal-entity-suffix-stripping normalization above,
// which merges those into one row.
$company_summary_rows = [];
$cs_res = mysqli_query($dbConn, "SELECT
        e.id as emp_id,
        TRIM(COALESCE(NULLIF(e.company_name,''),'(No Company Set)')) as company_raw,
        p.gross_pay, p.net_salary, p.total_ctc, COALESCE(p.ot_amount, p.ot) as ot_amt
    FROM hr_payroll p
    INNER JOIN hr_employees e ON p.employee_id = e.id
    WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$filter_from' AND '$filter_to'
    AND e.status='active' $md_exclude_sql_e");
if ($cs_res) {
    while ($csr = mysqli_fetch_assoc($cs_res)) {
        $raw  = $csr['company_raw'];
        $norm = ($raw === '(No Company Set)') ? '__none__' : hr_normalize_company_name($raw);
        if (!isset($company_summary_rows[$norm])) {
            $label = isset($company_norm_to_label[$norm]) ? $company_norm_to_label[$norm] : $raw;
            $company_summary_rows[$norm] = [
                'company' => $label, 'emp_count' => 0, 'emp_ids' => [],
                'sum_gross' => 0, 'sum_ot' => 0, 'sum_ctc' => 0, 'sum_net' => 0,
            ];
        }
        if (!isset($company_summary_rows[$norm]['emp_ids'][$csr['emp_id']])) {
            $company_summary_rows[$norm]['emp_ids'][$csr['emp_id']] = true;
            $company_summary_rows[$norm]['emp_count']++;
        }
        $company_summary_rows[$norm]['sum_gross'] += floatval($csr['gross_pay']);
        $company_summary_rows[$norm]['sum_ot']    += floatval($csr['ot_amt']);
        $company_summary_rows[$norm]['sum_ctc']   += floatval($csr['total_ctc']);
        $company_summary_rows[$norm]['sum_net']   += floatval($csr['net_salary']);
    }
}
uasort($company_summary_rows, function($a, $b) { return $b['sum_net'] <=> $a['sum_net']; });

$total_records = mysqli_num_rows($data);
$hq = mysqli_query($dbConn,"SELECT holidays_in_month FROM hr_payroll WHERE pay_month=$current_month AND pay_year=$current_year LIMIT 1");
$holidays = ($hq && mysqli_num_rows($hq)>0) ? intval(mysqli_fetch_assoc($hq)['holidays_in_month']) : 0;

// Auto-fetch holiday count from hr_office_holidays for the current filter month
$filter_mo_auto = intval(date('n', strtotime($filter_from)));
$filter_yr_auto = intval(date('Y', strtotime($filter_from)));
$auto_hol_res   = mysqli_query($dbConn,"SELECT COUNT(*) as cnt FROM hr_office_holidays WHERE year=$filter_yr_auto AND month=$filter_mo_auto");
$auto_hol_count = ($auto_hol_res) ? intval(mysqli_fetch_assoc($auto_hol_res)['cnt']) : 0;

$md_exclude_sql = " AND (position IS NULL OR (LOWER(position) NOT LIKE '%managing director%' AND LOWER(position) NOT LIKE '%ceo%'))";
$active_emps = mysqli_query($dbConn,"SELECT id,name,employee_id,position FROM hr_employees WHERE status='active' $md_exclude_sql ORDER BY name");

// Overrides: show for the FILTERED period, not just current month
// Extract month/year from filter for display
$filter_from_dt = new DateTime($filter_from);
$filter_to_dt   = new DateTime($filter_to);
$overrides_label = ($filter_from_dt->format('Y-m') === $filter_to_dt->format('Y-m'))
    ? $filter_from_dt->format('F Y')
    : $filter_from_dt->format('d M Y').' – '.$filter_to_dt->format('d M Y');

$overrides = mysqli_query($dbConn,"SELECT o.*,e.name,e.employee_id as ec FROM hr_attendance_overrides o INNER JOIN hr_employees e ON o.employee_id=e.id WHERE o.attendance_date BETWEEN '$filter_from' AND '$filter_to' $md_exclude_sql_e ORDER BY o.attendance_date DESC,e.name");

// ============================================================================
// PENDING NO-LOGOUT RECORDS (for Force Out section)
// Checked-in but never checked-out, past dates only, within filter period
// ============================================================================
$today_str = date('Y-m-d');
$pending_raw = mysqli_query($dbConn, "SELECT a.id, a.employee_id, a.employee_name, a.date, a.check_in_time,
    COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as company_name, e.timings
    FROM hr_attendance a
    INNER JOIN hr_employees e ON e.employee_id = a.employee_id
    WHERE a.date BETWEEN '$filter_from' AND '$filter_to'
    AND a.date < '$today_str'
    AND a.status IN ('present','late')
    AND (a.check_out_time IS NULL OR a.check_out_time = '')
    AND e.status='active' $company_sql $md_exclude_sql_e
    ORDER BY a.date DESC, a.employee_name");

$force_out_list = [];
$force_in_list = [];

if($pending_raw) {
    while($row = mysqli_fetch_assoc($pending_raw)) {
        $shift_start = '09:00';
        $shift_end = '18:00';
        if(!empty($row['timings'])) {
            if(preg_match('/(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\s*(?:to|-)\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)/i', $row['timings'], $m)) {
                $h1 = intval($m[1]); $mer1 = strtoupper($m[3]);
                if($mer1=='PM' && $h1!=12) $h1+=12;
                if($mer1=='AM' && $h1==12) $h1=0;
                $shift_start = sprintf('%02d:%02d', $h1, intval($m[2]??0));
                
                $h2 = intval($m[4]); $mer2 = strtoupper($m[6]);
                if($mer2=='PM' && $h2!=12) $h2+=12;
                if($mer2=='AM' && $h2==12) $h2=0;
                $shift_end = sprintf('%02d:%02d', $h2, intval($m[5]??0));
            } elseif(preg_match('/(\d{1,2})(?::(\d{2}))?\s*(AM|PM)/i', $row['timings'], $m)) {
                $h1 = intval($m[1]); $mer1 = strtoupper($m[3]);
                if($mer1=='PM' && $h1!=12) $h1+=12;
                if($mer1=='AM' && $h1==12) $h1=0;
                $shift_start = sprintf('%02d:%02d', $h1, intval($m[2]??0));
            }
        }
        $row['shift_start'] = $shift_start;
        $row['shift_end'] = $shift_end;

        $ci = substr($row['check_in_time'], 0, 5);
        $is_night_shift = ($shift_start >= '16:00');
        
        $is_missed_login = false;
        if(!$is_night_shift && $ci >= '14:00') {
            $is_missed_login = true;
        } elseif($is_night_shift && $ci >= '04:00' && $ci <= '12:00') {
            $is_missed_login = true;
        }

        if($is_missed_login) {
            $force_in_list[] = $row;
        } else {
            $force_out_list[] = $row;
        }
    }
}
$pending_count = count($force_out_list);
$pending_in_count = count($force_in_list);

$total_gross=$total_net=$total_ctc_sum=$total_ot=0;
if($total_records>0) {
    mysqli_data_seek($data,0);
    while($r=mysqli_fetch_assoc($data)) {
        $total_gross   += floatval($r['gross_pay']);
        $total_net     += floatval($r['net_salary']);
        $total_ctc_sum += floatval($r['total_ctc']);
        $total_ot      += floatval($r['ot_amount']??$r['ot']);
    }
}

// ============================================================================
// PAYROLL OVERVIEW TAB DATA — Managing Director only. One row per
// employee-payroll-record in the overview's own date range; department /
// position / company / monthly aggregation is done client-side in JS from
// this dataset, same low-risk approach used for the Attendance Overview tab.
// Only computed for MD/Abishek so nobody else pays the extra query cost.
// ✅ FIX: 'company' is passed through hr_canonical_company_label() so the
// Overview tab's "by Company" chart and leaderboard merge the same
// legal-entity-suffix spelling variants the summary table above now merges,
// instead of splitting one company's numbers across two bars/rows.
// ============================================================================
$payroll_overview_records = [];
$pv_total_net = $pv_total_gross = $pv_total_ot = $pv_total_deductions = 0;
$pv_emp_seen = [];
if($is_payroll_overview_viewer) {
    $pv_data = mysqli_query($dbConn, "SELECT p.*, e.name, e.employee_id as emp_code,
            COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as company_name,
            COALESCE(NULLIF(e.department,''),'Unassigned') as pv_department,
            COALESCE(NULLIF(e.position,''),'Unassigned') as pv_position
        FROM hr_payroll p
        INNER JOIN hr_employees e ON p.employee_id = e.id
        WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$pv_filter_from' AND '$pv_filter_to'
        AND e.status='active' $md_exclude_sql_e
        ORDER BY p.pay_year ASC, p.pay_month ASC, e.name ASC");
    if($pv_data) {
        while($pvr = mysqli_fetch_assoc($pv_data)) {
            $pv_net    = floatval($pvr['net_salary']);
            $pv_gross  = floatval($pvr['gross_pay']);
            $pv_ot     = floatval($pvr['ot_amount'] ?? $pvr['ot'] ?? 0);
            $pv_ded    = floatval($pvr['penalty'] ?? 0) + floatval($pvr['other_deductions'] ?? 0);
            $pv_total_net += $pv_net; $pv_total_gross += $pv_gross; $pv_total_ot += $pv_ot; $pv_total_deductions += $pv_ded;
            $pv_emp_seen[$pvr['emp_code']] = true;
            $payroll_overview_records[] = [
                'employee'   => $pvr['name'],
                'emp_code'   => $pvr['emp_code'],
                'company'    => hr_canonical_company_label($pvr['company_name'], $company_norm_to_label),
                'department' => $pvr['pv_department'],
                'position'   => $pvr['pv_position'],
                'month'      => intval($pvr['pay_month']),
                'year'       => intval($pvr['pay_year']),
                'month_label'=> date('M Y', mktime(0,0,0,intval($pvr['pay_month']),1,intval($pvr['pay_year']))),
                'gross'      => $pv_gross,
                'net'        => $pv_net,
                'ctc'        => floatval($pvr['total_ctc'] ?? 0),
                'ot'         => $pv_ot,
                'present_days'    => floatval($pvr['present_days'] ?? 0),
                'paid_leave_days' => floatval($pvr['paid_leave_days'] ?? 0),
                'absent_days'     => floatval($pvr['absent_days'] ?? 0),
                'basic'      => floatval($pvr['basic_salary'] ?? 0),
                'hra'        => floatval($pvr['hra'] ?? 0),
                'deductions' => $pv_ded,
            ];
        }
    }
}
$pv_total_records   = count($payroll_overview_records);
$pv_total_employees = count($pv_emp_seen);
$pv_avg_net = $pv_total_records > 0 ? ($pv_total_net / $pv_total_records) : 0;
$pv_records_json = json_encode($payroll_overview_records);
$pv_from_dt = new DateTime($pv_filter_from);
$pv_to_dt   = new DateTime($pv_filter_to);
$pv_period_label = ($pv_from_dt->format('Y-m') === $pv_to_dt->format('Y-m'))
    ? $pv_from_dt->format('F Y')
    : $pv_from_dt->format('d M Y').' - '.$pv_to_dt->format('d M Y');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Payroll System</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Inter',sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;padding:20px;color:#1a202c;}
    .wrap{max-width:1900px;margin:0 auto;background:white;border-radius:24px;box-shadow:0 25px 50px -12px rgba(0,0,0,.25);overflow:hidden;}
    .hdr{background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);color:white;padding:35px 50px;display:flex;justify-content:space-between;align-items:center;}
    .hdr h1{margin:0 0 5px;font-size:32px;font-weight:900;}
    .hdr p{margin:0;font-size:14px;opacity:.9;}
    .btn-back{background:rgba(255,255,255,.2);color:white;padding:10px 20px;border-radius:10px;font-weight:600;text-decoration:none;display:inline-flex;align-items:center;gap:8px;border:1px solid rgba(255,255,255,.3);transition:all .3s;}
    .btn-back:hover{background:white;color:#1e3c72;text-decoration:none;}
    .content{padding:35px 50px;}
    .alert-m{padding:15px 20px;border-radius:10px;margin-bottom:25px;font-weight:600;background:linear-gradient(135deg,#d4edda,#c3e6cb);color:#155724;border-left:4px solid #28a745;}
    .info-box{background:#f0fdf4;border:2px solid #10b981;border-radius:12px;padding:15px 20px;margin-bottom:25px;font-size:13px;color:#065f46;line-height:1.6;}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:16px;margin-bottom:30px;}
    .sc{color:white;padding:20px;border-radius:14px;box-shadow:0 8px 15px -3px rgba(0,0,0,.1);transition:all .3s;}
    .sc:hover{transform:translateY(-4px);}
    .sc.blue{background:linear-gradient(135deg,#3b82f6,#2563eb);}
    .sc.green{background:linear-gradient(135deg,#10b981,#059669);}
    .sc.orange{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .sc.purple{background:linear-gradient(135deg,#8b5cf6,#7c3aed);}
    .sc.teal{background:linear-gradient(135deg,#14b8a6,#0d9488);}
    .sc .lbl{font-size:11px;font-weight:700;text-transform:uppercase;opacity:.9;margin-bottom:6px;}
    .sc .val{font-size:26px;font-weight:900;}
    .ctrl{background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:2px solid #3b82f6;border-radius:14px;padding:25px;margin-bottom:30px;}
    .ctrl-row{display:flex;gap:15px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;}
    label{display:block;font-weight:700;margin-bottom:6px;color:#1e40af;font-size:13px;}
    .fc{padding:9px 13px;border:2px solid #bfdbfe;border-radius:8px;font-size:13px;font-weight:600;background:white;}
    .btn{padding:9px 20px;border-radius:9px;font-weight:700;font-size:13px;border:none;cursor:pointer;transition:all .3s;display:inline-flex;align-items:center;gap:7px;box-shadow:0 3px 6px rgba(0,0,0,.1);}
    .btn:hover{transform:translateY(-2px);}
    .btn-p{background:linear-gradient(135deg,#3b82f6,#2563eb);color:white;}
    .btn-s{background:linear-gradient(135deg,#10b981,#059669);color:white;}
    .btn-d{background:linear-gradient(135deg,#ef4444,#dc2626);color:white;}
    .btn-v{background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:white;}
    .tw{background:white;border-radius:14px;border:2px solid #e5e7eb;overflow-x:auto;overflow-y:auto;max-height:620px;box-shadow:0 4px 6px rgba(0,0,0,.08);margin-bottom:25px;}
    .pt{width:100%;border-collapse:collapse;font-size:13px;min-width:2300px;border:1px solid #1e3a8a;}
    .pt thead{background:linear-gradient(135deg,#1e40af,#1e3a8a);color:white;position:sticky;top:0;z-index:10;}
    .pt th{padding:16px 13px;text-align:left;font-weight:800;font-size:12px;text-transform:uppercase;border:1px solid #1e3a8a;white-space:nowrap;}
    .pt td{padding:13px;border:1px solid #1e3a8a;font-size:13px;font-weight:500;white-space:nowrap;}
    .pt tbody tr:hover{background:#f8fafc;}
    .pt tbody tr:nth-child(even){background:#fafafa;}
    .pt tbody tr.ot-row{background:#fffbeb!important;}
    .ab{width:33px;height:33px;border-radius:7px;border:none;cursor:pointer;transition:all .3s;display:inline-flex;align-items:center;justify-content:center;color:white;margin-right:4px;}
    .ab.edit{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .ab.dl{background:linear-gradient(135deg,#10b981,#059669);}
    .ab.del{background:linear-gradient(135deg,#ef4444,#dc2626);}
    .ab.appr{background:linear-gradient(135deg,#3b82f6,#1e40af);}
    .ab.rej{background:linear-gradient(135deg,#64748b,#475569);}
    .ab.resend{background:linear-gradient(135deg,#8b5cf6,#6d28d9);}
    .apr-badge{display:inline-block;padding:3px 9px;border-radius:6px;font-size:11px;font-weight:700;white-space:nowrap;}
    .apr-badge.pending{background:#fef3c7;color:#b45309;}
    .apr-badge.approved{background:#d1fae5;color:#059669;}
    .apr-badge.rejected{background:#fee2e2;color:#dc2626;}
    .apr-badge.failed{background:#fee2e2;color:#dc2626;}
    .ab:hover{transform:scale(1.1);}
    .totals{background:linear-gradient(135deg,#1e3c72,#2a5298);color:white;padding:20px 25px;border-radius:12px;margin-top:15px;display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:15px;}
    .ti{text-align:center;}
    .ti .tl{font-size:11px;font-weight:700;text-transform:uppercase;opacity:.85;margin-bottom:5px;}
    .ti .tv{font-size:24px;font-weight:900;}
    .mc{border-radius:18px!important;border:none!important;box-shadow:0 20px 50px rgba(0,0,0,.2)!important;}
    .mh{border-radius:18px 18px 0 0!important;padding:22px 28px!important;border:none!important;}
    .mb{padding:28px!important;}
    .chip{display:inline-flex;align-items:center;gap:8px;background:#4338ca;color:white;padding:6px 12px;border-radius:20px;font-size:12px;font-weight:700;}
    .chip button{background:rgba(255,255,255,.25);border:none;color:white;border-radius:12px;padding:2px 8px;font-weight:700;cursor:pointer;font-size:11px;}
    .chip.clear-all{background:#64748b;cursor:pointer;}
    .pv-lb-row{cursor:pointer;}
    .pv-lb-row:hover{background:#f8fafc;}
    @media (max-width:1100px){.pv-charts-grid{grid-template-columns:1fr!important;}}
  </style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <div>
      <h1><i class="fa fa-calculator"></i> Payroll System</h1>
      <p>Fixed 26-Day Base &nbsp;|&nbsp; ALL Days Counted (Mon–Sun) &nbsp;|&nbsp; Beyond 26 = Auto OT &nbsp;|&nbsp; Simple & Fair for Everyone</p>
    </div>
    <div style="display:flex;gap:10px;align-items:center;">
      <a href="hr-manpower.php" class="btn-back">
        <i class="fa fa-chart-line"></i> Manpower Cost
      </a>
      
    </div>
  </div>

  <div class="content">
    <?php if(isset($_SESSION['msg'])): ?>
    <div class="alert-m"><i class="fa fa-check-circle"></i> <?php echo $_SESSION['msg']; unset($_SESSION['msg']); ?></div>
    <?php endif; ?>

    <?php if($is_payroll_overview_viewer): ?>
    <div style="display:flex;gap:10px;margin-bottom:25px;">
      <a href="?pv_tab=overview" style="text-decoration:none;padding:11px 24px;border-radius:10px;font-weight:800;font-size:14px;display:inline-flex;align-items:center;gap:8px;<?php echo $pv_tab==='overview' ? 'background:linear-gradient(135deg,#1e3c72,#2a5298);color:white;box-shadow:0 4px 10px rgba(30,60,114,.3);' : 'background:#f1f5f9;color:#475569;'; ?>">
        <i class="fa fa-line-chart"></i> Overview
      </a>
      <a href="?pv_tab=list" style="text-decoration:none;padding:11px 24px;border-radius:10px;font-weight:800;font-size:14px;display:inline-flex;align-items:center;gap:8px;<?php echo $pv_tab==='list' ? 'background:linear-gradient(135deg,#1e3c72,#2a5298);color:white;box-shadow:0 4px 10px rgba(30,60,114,.3);' : 'background:#f1f5f9;color:#475569;'; ?>">
        <i class="fa fa-table"></i> Payroll List
      </a>
    </div>
    <?php endif; ?>

    <div id="pvListTabContent" style="<?php echo ($pv_tab === 'overview') ? 'display:none;' : ''; ?>">
    <!-- INFO BOX -->
    <div class="info-box">
      <strong><i class="fa fa-info-circle"></i> How Salary is Calculated:</strong><br>
      &nbsp;&nbsp; ✅ <strong>Base = 26 days always</strong> (fixed for every month)<br>
      &nbsp;&nbsp; ✅ <strong>All attendance counted</strong> — Monday to Sunday, any day employee comes in<br>
      &nbsp;&nbsp; ✅ <strong>Present &lt; 26</strong> → Absent deduction &nbsp;|&nbsp; <strong>Present = 26</strong> → Full salary &nbsp;|&nbsp; <strong>Present &gt; 26</strong> → Full salary + OT<br>
      &nbsp;&nbsp; ✅ <strong>February short month?</strong> HR adds extra days in "Add Working Days" → counts towards 26<br>
      &nbsp;&nbsp; ✅ <strong>No week-off configuration needed</strong> — works automatically for everyone<br>
      &nbsp;&nbsp; <span style="color:#b45309;background:#fef3c7;padding:2px 8px;border-radius:6px;font-weight:700;">⚠️ <strong>NO LOGOUT = 0.5 Day (FROM JUNE 2026 ONWARDS)</strong> — If an employee checks in but does NOT check out, that day counts as <strong>0.5</strong> (half day salary). Full day requires both check-in AND check-out.</span><br>
      &nbsp;&nbsp; <span style="color:#065f46;background:#d1fae5;padding:2px 8px;border-radius:6px;font-weight:700;">✅ <strong>BEFORE JUNE 2026: No money cut</strong> — for May 2026 and earlier months, days without check-out still count as <strong>FULL days</strong> (old rule). Re-click "Generate Payroll" for old months to apply this.</span>
    </div>

    <!-- STATS -->
    <div class="stats">
      <div class="sc blue"><div class="lbl">Filter Period</div><div class="val" style="font-size:16px"><?php echo date('M Y',strtotime($filter_from)).' – '.date('M Y',strtotime($filter_to)); ?><?php if(!empty($filter_company)): ?><br><span style="font-size:11px;opacity:.95;"><i class="fa fa-building"></i> <?php echo htmlspecialchars($filter_company); ?></span><?php endif; ?></div></div>
      <div class="sc purple"><div class="lbl"><i class="fa fa-users"></i> Records</div><div class="val"><?php echo $total_records; ?></div></div>
      <div class="sc orange"><div class="lbl"><i class="fa fa-flag"></i> Holidays This Month</div><div class="val"><?php echo $holidays; ?></div></div>
      <div class="sc teal"><div class="lbl"><i class="fa fa-star"></i> Total Auto OT</div><div class="val">₹<?php echo number_format($total_ot); ?></div></div>
      <div class="sc green"><div class="lbl"><i class="fa fa-money"></i> Total Net Salary</div><div class="val">₹<?php echo number_format($total_net); ?></div></div>
    </div>

    <!-- CONTROLS -->
    <div class="ctrl">
      <div class="ctrl-row">
        <div style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;">
          <form method="POST" style="display:inline-flex;gap:10px;align-items:flex-end;flex-wrap:wrap;">
            <div>
              <label style="font-size:12px;font-weight:700;color:#1e40af;">
                <i class="fa fa-calendar"></i> Holidays (Auto)
                <small style="display:block;color:#059669;font-size:10px;">From Master Settings</small>
              </label>
              <div style="display:flex;align-items:center;gap:6px;">
                <span style="display:inline-block;background:linear-gradient(135deg,#1e3a8a,#2563eb);color:#fff;font-weight:800;font-size:16px;border-radius:8px;padding:7px 14px;min-width:50px;text-align:center;">
                  <?php echo $auto_hol_count; ?>
                </span>
                <a href="hr-departments-list.php?view=office_holidays&hy=<?php echo $filter_yr_auto; ?>&hm=<?php echo $filter_mo_auto; ?>" target="_blank"
                   style="font-size:11px;color:#2563eb;text-decoration:none;font-weight:600;" title="Manage holidays">
                  <i class="fa fa-edit"></i> Manage
                </a>
              </div>
            </div>
            <div>
              <label title="For short months like Feb - adds to present days">Add Working Days
                <small style="color:#059669;font-size:10px;display:block;">For Feb/short months</small>
              </label>
              <input type="number" name="add_working_days" value="<?php echo $saved_add; ?>" min="0" max="10" class="fc" style="width:75px">
            </div>
            <div>
              <label title="For 31-day months - deducts from present days">Reduce Working Days
                <small style="color:#ef4444;font-size:10px;display:block;">For 31-day months</small>
              </label>
              <input type="number" name="reduce_working_days" value="<?php echo $saved_reduce; ?>" min="0" max="10" step="0.5" class="fc" style="width:75px">
            </div>
            <input type="hidden" name="filter_from" value="<?php echo $filter_from; ?>">
            <input type="hidden" name="filter_to"   value="<?php echo $filter_to; ?>">
            <button type="submit" name="auto_generate" class="btn btn-s"><i class="fa fa-refresh"></i> Generate Payroll</button>
          </form>
          <button type="button" class="btn btn-v" data-toggle="modal" data-target="#markModal"><i class="fa fa-users"></i> Mark Specific Employees</button>
        </div>
        <div style="display:flex;gap:10px;align-items:flex-end;">
          <form method="POST" style="display:flex;gap:10px;align-items:flex-end;background:#dbeafe;padding:10px 14px;border-radius:10px;flex-wrap:wrap;">
            <div><label style="font-size:12px">From</label><input type="date" name="filter_from" class="fc" style="height:40px;font-size:13px" value="<?php echo $filter_from; ?>"></div>
            <div><label style="font-size:12px">To</label><input type="date" name="filter_to" class="fc" style="height:40px;font-size:13px" value="<?php echo $filter_to; ?>"></div>
            <div>
              <label style="font-size:12px;white-space:nowrap;"><i class="fa fa-building"></i> Company / Entity</label>
              <select name="filter_company" class="fc" style="height:40px;font-size:13px;min-width:280px;max-width:380px;width:auto;padding:8px 12px;font-weight:600;">
                <option value="">— All Companies —</option>
                <?php foreach($companies_list as $cn): ?>
                <option value="<?php echo htmlspecialchars($cn); ?>" <?php echo ($filter_company === $cn) ? 'selected' : ''; ?>><?php echo htmlspecialchars($cn); ?></option>
                <?php endforeach; ?>
                <option value="(No Company Set)" <?php echo ($filter_company === '(No Company Set)') ? 'selected' : ''; ?>>(No Company Set)</option>
              </select>
            </div>
            <button type="submit" name="apply_filter" class="btn btn-p" style="height:40px"><i class="fa fa-filter"></i> Apply</button>
          </form>
          <form method="POST" target="_blank" style="display:flex;gap:5px;">
            <input type="hidden" name="export_from" value="<?php echo $filter_from; ?>">
            <input type="hidden" name="export_to"   value="<?php echo $filter_to; ?>">
            <button type="submit" name="export_pdf_summary" class="btn btn-s" style="height:33px;background:#dc2626;border-color:#b91c1c;"><i class="fa fa-file-pdf-o"></i> Download PDF Summary</button>
            <button type="submit" name="export_csv" class="btn btn-s" style="height:33px"><i class="fa fa-download"></i> Export CSV</button>
          </form>
        </div>
      </div>
    </div>

    <!-- COMPANY / ENTITY-WISE PAYROLL SUMMARY -->
    <?php if(!empty($company_summary_rows)): ?>
    <div style="background:#eef2ff;border:2px solid #6366f1;border-radius:12px;padding:18px;margin-bottom:25px;">
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:12px;">
        <h4 style="color:#3730a3;font-weight:800;margin:0;"><i class="fa fa-building"></i> Company-wise Payroll — <?php echo htmlspecialchars($overrides_label); ?></h4>
        <?php if(!empty($filter_company)): ?>
          <form method="POST" style="margin:0;">
            <input type="hidden" name="filter_from" value="<?php echo $filter_from; ?>">
            <input type="hidden" name="filter_to" value="<?php echo $filter_to; ?>">
            <input type="hidden" name="filter_company" value="">
            <button type="submit" name="apply_filter" style="background:#3730a3;color:white;padding:5px 14px;border-radius:20px;font-size:12px;font-weight:700;border:none;cursor:pointer;">
              Viewing: <?php echo htmlspecialchars($filter_company); ?> &nbsp;✕ Clear
            </button>
          </form>
        <?php else: ?>
          <span style="background:#6366f1;color:white;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:700;"><?php echo count($company_summary_rows); ?> compan<?php echo count($company_summary_rows)==1?'y':'ies'; ?></span>
        <?php endif; ?>
      </div>
      <div style="background:#e0e7ff;border:1px solid #6366f1;border-radius:8px;padding:10px 14px;margin-bottom:12px;font-size:12px;color:#3730a3;">
        <i class="fa fa-info-circle"></i> <strong>For each company:</strong> how many employees and how much we are paying for the selected period.
        Click <strong>"View Employees"</strong> on a company to filter the payroll table below to ONLY that company's employees.
      </div>
      <div style="overflow-x:auto;">
        <table class="table table-condensed" style="background:white;border-radius:8px;font-size:13px;margin:0;">
          <thead style="background:#6366f1;color:white;">
            <tr>
              <th style="padding:10px;">Company / Entity</th>
              <th style="padding:10px;text-align:center;">Employees</th>
              <th style="padding:10px;text-align:right;">Total Gross</th>
              <th style="padding:10px;text-align:right;">Total OT</th>
              <th style="padding:10px;text-align:right;">Total CTC</th>
              <th style="padding:10px;text-align:right;">Total Net Paying</th>
              <th style="padding:10px;text-align:center;">Action</th>
            </tr>
          </thead>
          <tbody>
            <?php
            $g_emp=$g_gross=$g_ot=$g_ctc=$g_net=0;
            foreach($company_summary_rows as $cs):
                $is_active_filter = ($filter_company === $cs['company']);
                $g_emp += intval($cs['emp_count']); $g_gross += floatval($cs['sum_gross']);
                $g_ot  += floatval($cs['sum_ot']);  $g_ctc   += floatval($cs['sum_ctc']);
                $g_net += floatval($cs['sum_net']);
            ?>
            <tr style="<?php echo $is_active_filter ? 'background:#e0e7ff;border-left:4px solid #4338ca;' : ''; ?>">
              <td style="padding:10px;font-weight:700;color:#3730a3;">
                <i class="fa fa-building-o"></i> <?php echo htmlspecialchars($cs['company']); ?>
                <?php if($is_active_filter): ?><span style="background:#4338ca;color:white;padding:2px 8px;border-radius:10px;font-size:10px;margin-left:6px;">FILTERED</span><?php endif; ?>
              </td>
              <td style="padding:10px;text-align:center;font-weight:800;color:#1e40af;"><?php echo floatval($cs['emp_count']); ?></td>
              <td style="padding:10px;text-align:right;font-weight:600;">₹<?php echo number_format($cs['sum_gross']); ?></td>
              <td style="padding:10px;text-align:right;color:#d97706;font-weight:600;">₹<?php echo number_format($cs['sum_ot']); ?></td>
              <td style="padding:10px;text-align:right;color:#7c3aed;font-weight:600;">₹<?php echo number_format($cs['sum_ctc']); ?></td>
              <td style="padding:10px;text-align:right;font-weight:900;color:#059669;font-size:14px;">₹<?php echo number_format($cs['sum_net']); ?></td>
              <td style="padding:10px;text-align:center;">
                <form method="POST" style="margin:0;">
                  <input type="hidden" name="filter_from" value="<?php echo $filter_from; ?>">
                  <input type="hidden" name="filter_to" value="<?php echo $filter_to; ?>">
                  <input type="hidden" name="filter_company" value="<?php echo htmlspecialchars($cs['company']); ?>">
                  <button type="submit" name="apply_filter" class="btn btn-v" style="height:30px;padding:4px 12px;font-size:11px;">
                    <i class="fa fa-users"></i> View Employees
                  </button>
                </form>
              </td>
            </tr>
            <?php endforeach; ?>
          </tbody>
          <tfoot style="background:#312e81;color:white;font-weight:800;">
            <tr>
              <td style="padding:10px;">TOTAL — ALL COMPANIES</td>
              <td style="padding:10px;text-align:center;"><?php echo $g_emp; ?></td>
              <td style="padding:10px;text-align:right;">₹<?php echo number_format($g_gross); ?></td>
              <td style="padding:10px;text-align:right;">₹<?php echo number_format($g_ot); ?></td>
              <td style="padding:10px;text-align:right;">₹<?php echo number_format($g_ctc); ?></td>
              <td style="padding:10px;text-align:right;font-size:14px;">₹<?php echo number_format($g_net); ?></td>
              <td style="padding:10px;"></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
    <?php endif; ?>

    <!-- FORCE OUT (NO-LOGOUT) SECTION — moved here from Attendance page -->
    <?php if($pending_count > 0): ?>
    <div style="background:#fff1f2;border:2px solid #ef4444;border-radius:12px;padding:18px;margin-bottom:25px;">
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:12px;">
        <h4 style="color:#991b1b;font-weight:800;margin:0;"><i class="fa fa-sign-out"></i> Force Out — Employees Who Did NOT Log Off (<?php echo htmlspecialchars($overrides_label); ?>)</h4>
        <span style="background:#991b1b;color:white;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:700;"><?php echo $pending_count; ?> pending</span>
      </div>
      <div style="background:#fef2f2;border:1px solid #ef4444;border-radius:8px;padding:10px 14px;margin-bottom:12px;font-size:12px;color:#7f1d1d;">
        <i class="fa fa-info-circle"></i> <strong>Tick the checkboxes (or Select All), set the time, and click "Force Out Selected"</strong> to close many days at once.
        From <strong>June 2026</strong>, an un-closed day pays only <strong style="color:#d97706;">0.5 day</strong> — forcing out makes it a <strong style="color:#059669;">full day</strong>.
        Months <strong>before June 2026</strong> already count as full days (no cut), but you can still force out to clean the records.
        <strong>After forcing out, click "Generate Payroll" to refresh salary.</strong>
      </div>
      <form method="POST" id="bulkForceOutForm" onsubmit="return confirmBulkForceOut();">
      <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:10px;background:white;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;">
        <label style="margin:0;color:#991b1b;font-size:13px;display:flex;align-items:center;gap:6px;cursor:pointer;">
          <input type="checkbox" id="foSelectAll" onclick="toggleAllForceOut(this)" style="width:17px;height:17px;cursor:pointer;"> Select All
        </label>
        <span style="color:#991b1b;font-size:12px;font-weight:700;" id="foSelectedCount">0 selected</span>
        <span style="color:#7f1d1d;font-size:12px;">| Set time for ALL selected:</span>
        <input type="time" id="foBulkTime" value="18:00" class="fc" style="width:110px;height:32px;font-size:12px;" onchange="applyBulkTime(this.value)">
        <button type="submit" name="bulk_force_checkout" class="btn btn-d" style="height:34px;padding:6px 18px;font-size:13px;">
          <i class="fa fa-sign-out"></i> Force Out Selected
        </button>
      </div>
      <div style="max-height:320px;overflow-y:auto;">
        <table class="table table-condensed" style="background:white;border-radius:8px;font-size:13px;margin:0;">
          <thead style="background:#ef4444;color:white;position:sticky;top:0;">
            <tr>
              <th style="padding:10px;width:40px;text-align:center;"><i class="fa fa-check-square-o"></i></th>
              <th style="padding:10px;">Employee</th>
              <th style="padding:10px;">Company</th>
              <th style="padding:10px;">Date</th>
              <th style="padding:10px;">Check In</th>
              <th style="padding:10px;">Salary Impact</th>
              <th style="padding:10px;">Force Out Time</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach($force_out_list as $pl):
                $pl_penalty = (strtotime($pl['date']) >= strtotime(NO_LOGOUT_POLICY_START));
                $pid = intval($pl['id']);
            ?>
            <tr>
              <td style="padding:10px;text-align:center;">
                <input type="checkbox" name="att_ids[]" value="<?php echo $pid; ?>" class="fo-check" onclick="updateFoCount()" style="width:17px;height:17px;cursor:pointer;">
              </td>
              <td style="padding:10px;font-weight:700;color:#1e40af;">
                <?php echo htmlspecialchars($pl['employee_name']); ?>
                <br><small style="color:#64748b;"><?php echo htmlspecialchars($pl['employee_id']); ?></small>
              </td>
              <td style="padding:10px;font-size:12px;color:#3730a3;font-weight:600;"><?php echo htmlspecialchars($pl['company_name']); ?></td>
              <td style="padding:10px;font-weight:600;">
                <?php echo date('d M Y', strtotime($pl['date'])); ?>
                <br><small style="color:#64748b;"><?php echo date('l', strtotime($pl['date'])); ?></small>
              </td>
              <td style="padding:10px;"><?php echo date('h:i A', strtotime($pl['check_in_time'])); ?></td>
              <td style="padding:10px;">
                <?php if($pl_penalty): ?>
                  <span style="background:#fef3c7;color:#b45309;padding:3px 8px;border-radius:6px;font-weight:700;font-size:11px;">⚠️ Counts 0.5 day until forced out</span>
                <?php else: ?>
                  <span style="background:#d1fae5;color:#065f46;padding:3px 8px;border-radius:6px;font-weight:700;font-size:11px;">✅ Full day (before Jun 2026 — no cut)</span>
                <?php endif; ?>
              </td>
              <td style="padding:10px;">
                <input type="time" name="force_out_time[<?php echo $pid; ?>]" value="18:00" class="fc fo-time" style="width:110px;height:32px;font-size:12px;" required>
              </td>
            </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      </form>
      <script>
      function toggleAllForceOut(master){
        document.querySelectorAll('.fo-check').forEach(function(c){ c.checked = master.checked; });
        updateFoCount();
      }
      function updateFoCount(){
        var n = document.querySelectorAll('.fo-check:checked').length;
        document.getElementById('foSelectedCount').textContent = n + ' selected';
        var all = document.querySelectorAll('.fo-check').length;
        document.getElementById('foSelectAll').checked = (n === all && all > 0);
      }
      function applyBulkTime(t){
        if(!t) return;
        document.querySelectorAll('.fo-time').forEach(function(i){ i.value = t; });
      }
      function confirmBulkForceOut(){
        var n = document.querySelectorAll('.fo-check:checked').length;
        if(n === 0){ alert('Please select at least one record (tick the checkboxes) to Force Out.'); return false; }
        return confirm('Force Out ' + n + ' selected record(s)?\nAfter this, click "Generate Payroll" to update salaries.');
      }
      </script>
    </div>
    <?php else: ?>
    <div style="background:#f0fdf4;border:2px dashed #10b981;border-radius:12px;padding:14px;margin-bottom:25px;text-align:center;color:#059669;font-size:13px;font-weight:600;">
      <i class="fa fa-check-circle"></i> No pending logouts in <strong><?php echo htmlspecialchars($overrides_label); ?></strong> — all employees checked out properly.
    </div>
    <?php endif; ?>

    <!-- FORCE IN (MISSED LOGIN) SECTION -->
    <?php if($pending_in_count > 0): ?>
    <div style="background:#f0f9ff;border:2px solid #3b82f6;border-radius:12px;padding:18px;margin-bottom:25px;">
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:12px;">
        <h4 style="color:#1e40af;font-weight:800;margin:0;"><i class="fa fa-sign-in"></i> Force Log In — Employees Who Missed Check-In (<?php echo htmlspecialchars($overrides_label); ?>)</h4>
        <span style="background:#1e40af;color:white;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:700;"><?php echo $pending_in_count; ?> pending</span>
      </div>
      <div style="background:#eff6ff;border:1px solid #3b82f6;border-radius:8px;padding:10px 14px;margin-bottom:12px;font-size:12px;color:#1e3a8a;">
        <i class="fa fa-info-circle"></i> <strong>These employees forgot to log in.</strong> Their recorded check-in time is actually their <strong>log-off</strong> punch! 
        Set their missing morning Check-In time below (default is their shift start time). This will shift their late punch to Check-Out and calculate full hours.
      </div>
      <form method="POST" id="bulkForceInForm" onsubmit="return confirmBulkForceIn();">
      <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:10px;background:white;border:1px solid #93c5fd;border-radius:8px;padding:10px 14px;">
        <label style="margin:0;color:#1e40af;font-size:13px;display:flex;align-items:center;gap:6px;cursor:pointer;">
          <input type="checkbox" id="fiSelectAll" onclick="toggleAllForceIn(this)" style="width:17px;height:17px;cursor:pointer;"> Select All
        </label>
        <span style="color:#1e40af;font-size:12px;font-weight:700;" id="fiSelectedCount">0 selected</span>
        <span style="color:#1e3a8a;font-size:12px;">| Set time for ALL selected:</span>
        <input type="time" id="fiBulkTime" value="09:00" class="fc" style="width:110px;height:32px;font-size:12px;" onchange="applyBulkTimeIn(this.value)">
        <button type="submit" name="bulk_force_login" class="btn btn-v" style="height:34px;padding:6px 18px;font-size:13px;">
          <i class="fa fa-sign-in"></i> Force Log In Selected
        </button>
      </div>
      <div style="max-height:320px;overflow-y:auto;">
        <table class="table table-condensed" style="background:white;border-radius:8px;font-size:13px;margin:0;">
          <thead style="background:#3b82f6;color:white;position:sticky;top:0;">
            <tr>
              <th style="padding:10px;width:40px;text-align:center;"><i class="fa fa-check-square-o"></i></th>
              <th style="padding:10px;">Employee</th>
              <th style="padding:10px;">Company</th>
              <th style="padding:10px;">Date</th>
              <th style="padding:10px;">Late Punch (Becomes Out)</th>
              <th style="padding:10px;">Salary Impact</th>
              <th style="padding:10px;">Force Log In Time</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach($force_in_list as $pl):
                $pl_penalty = (strtotime($pl['date']) >= strtotime(NO_LOGOUT_POLICY_START));
                $pid = intval($pl['id']);
            ?>
            <tr>
              <td style="padding:10px;text-align:center;">
                <input type="checkbox" name="att_ids[]" value="<?php echo $pid; ?>" class="fi-check" onclick="updateFiCount()" style="width:17px;height:17px;cursor:pointer;">
              </td>
              <td style="padding:10px;font-weight:700;color:#1e40af;">
                <?php echo htmlspecialchars($pl['employee_name']); ?>
                <br><small style="color:#64748b;"><?php echo htmlspecialchars($pl['employee_id']); ?></small>
              </td>
              <td style="padding:10px;font-size:12px;color:#3730a3;font-weight:600;"><?php echo htmlspecialchars($pl['company_name']); ?></td>
              <td style="padding:10px;font-weight:600;">
                <?php echo date('d M Y', strtotime($pl['date'])); ?>
                <br><small style="color:#64748b;"><?php echo date('l', strtotime($pl['date'])); ?></small>
              </td>
              <td style="padding:10px;"><strong style="color:#ef4444;"><?php echo date('h:i A', strtotime($pl['check_in_time'])); ?></strong></td>
              <td style="padding:10px;">
                <?php if($pl_penalty): ?>
                  <span style="background:#fef3c7;color:#b45309;padding:3px 8px;border-radius:6px;font-weight:700;font-size:11px;">⚠️ Counts 0.5 day until forced in</span>
                <?php else: ?>
                  <span style="background:#d1fae5;color:#065f46;padding:3px 8px;border-radius:6px;font-weight:700;font-size:11px;">✅ Full day</span>
                <?php endif; ?>
              </td>
              <td style="padding:10px;">
                <input type="time" name="force_in_time[<?php echo $pid; ?>]" value="<?php echo $pl['shift_start']; ?>" class="fc fi-time" style="width:110px;height:32px;font-size:12px;" required>
              </td>
            </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      </form>
      <script>
      function toggleAllForceIn(master){
        document.querySelectorAll('.fi-check').forEach(function(c){ c.checked = master.checked; });
        updateFiCount();
      }
      function updateFiCount(){
        var n = document.querySelectorAll('.fi-check:checked').length;
        document.getElementById('fiSelectedCount').innerText = n + ' selected';
      }
      function applyBulkTimeIn(val){
        if(val) {
          document.querySelectorAll('.fi-time').forEach(function(inp){ inp.value = val; });
        }
      }
      function confirmBulkForceIn(){
        var n = document.querySelectorAll('.fi-check:checked').length;
        if(n === 0){ alert('Please select at least one record (tick the checkboxes) to Force Log In.'); return false; }
        return confirm('Force Log In ' + n + ' selected record(s)?\nTheir recorded late punch will become their log off time.\nAfter this, click "Generate Payroll" to update salaries.');
      }
      </script>
    </div>
    <?php else: ?>
    <div style="background:#f0fdf4;border:2px dashed #10b981;border-radius:12px;padding:14px;margin-bottom:25px;text-align:center;color:#059669;font-size:13px;font-weight:600;">
      <i class="fa fa-check-circle"></i> No missed morning check-ins detected in <strong><?php echo htmlspecialchars($overrides_label); ?></strong>.
    </div>
    <?php endif; ?>

    <!-- OVERRIDES -->
    <?php if($overrides && mysqli_num_rows($overrides)>0): ?>
    <div style="background:#fef3c7;border:2px solid #f59e0b;border-radius:12px;padding:18px;margin-bottom:25px;">
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:12px;">
        <h4 style="color:#92400e;font-weight:800;margin:0;"><i class="fa fa-calendar-check-o"></i> Administration Attendance Overrides — <?php echo htmlspecialchars($overrides_label); ?></h4>
        <span style="background:#92400e;color:white;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:700;"><?php echo mysqli_num_rows($overrides); ?> override(s)</span>
      </div>
      <div style="background:#fffbeb;border:1px solid #f59e0b;border-radius:8px;padding:10px 14px;margin-bottom:12px;font-size:12px;color:#78350f;">
        <i class="fa fa-info-circle"></i> <strong>These are days Administration manually overrode attendance.</strong>
        Present/Holiday/Leave = <strong style="color:#059669;">adds to present days (paid)</strong> &nbsp;|&nbsp;
        Absent = <strong style="color:#dc2626;">deducts from present days</strong> &nbsp;|&nbsp;
        Half Day = <strong style="color:#d97706;">counts as 0.5 day</strong>
      </div>
      <div style="max-height:280px;overflow-y:auto;">
        <table class="table table-condensed" style="background:white;border-radius:8px;font-size:13px;margin:0;">
          <thead style="background:#f59e0b;color:white;position:sticky;top:0;">
            <tr>
              <th style="padding:10px;">Employee</th>
              <th style="padding:10px;">Date</th>
              <th style="padding:10px;">Status</th>
              <th style="padding:10px;">Reason Given by Administration</th>
              <th style="padding:10px;">Marked By</th>
              <th style="padding:10px;">Impact on Salary</th>
              <th style="padding:10px;"></th>
            </tr>
          </thead>
          <tbody>
            <?php while($ov=mysqli_fetch_assoc($overrides)):
                $impact_color = '#059669';
                $impact_text  = '+1 day (paid)';
                $impact_bg    = '#f0fdf4';
                if($ov['status'] === 'absent') {
                    $impact_color = '#dc2626'; $impact_text = '−1 day (deducted)'; $impact_bg = '#fef2f2';
                } elseif($ov['status'] === 'half_day') {
                    $impact_color = '#d97706'; $impact_text = '+0.5 day (half day)'; $impact_bg = '#fffbeb';
                } elseif($ov['status'] === 'holiday') {
                    $impact_text = '+1 day (holiday)'; $impact_bg = '#f0fdf4';
                } elseif($ov['status'] === 'leave') {
                    $impact_text = '+1 day (leave)'; $impact_bg = '#eff6ff'; $impact_color = '#2563eb';
                }
            ?>
            <tr style="border-bottom:1px solid #e5e7eb;">
              <td style="padding:10px;">
                <strong><?php echo htmlspecialchars($ov['name']); ?></strong><br>
                <small style="color:#64748b;"><?php echo htmlspecialchars($ov['ec']); ?></small>
              </td>
              <td style="padding:10px;">
                <strong><?php echo date('d M Y',strtotime($ov['attendance_date'])); ?></strong><br>
                <small style="color:#64748b;"><?php echo date('l',strtotime($ov['attendance_date'])); ?></small>
              </td>
              <td style="padding:10px;">
                <span style="background:<?php echo $impact_bg; ?>;color:<?php echo $impact_color; ?>;padding:3px 10px;border-radius:6px;font-weight:700;font-size:12px;">
                  <?php echo ucfirst($ov['status']); ?>
                </span>
              </td>
              <td style="padding:10px;max-width:200px;">
                <?php if(!empty($ov['reason'])): ?>
                  <div style="background:#fef9c3;border-left:3px solid #f59e0b;padding:6px 10px;border-radius:4px;font-size:12px;color:#78350f;font-weight:600;">
                    "<?php echo htmlspecialchars($ov['reason']); ?>"
                  </div>
                <?php else: ?>
                  <span style="color:#94a3b8;font-style:italic;font-size:12px;">No reason given</span>
                <?php endif; ?>
              </td>
              <td style="padding:10px;">
                <?php if($ov['created_by'] === 'System (Auto-Sync)'): ?>
                  <span style="background:#ecfdf5;color:#059669;padding:3px 10px;border-radius:6px;font-weight:700;font-size:11px;">Administration Override</span>
                <?php else: ?>
                  <span style="background:#eff6ff;color:#2563eb;padding:3px 10px;border-radius:6px;font-weight:700;font-size:11px;">HR Override</span>
                <?php endif; ?>
                <div style="font-size:12px;font-weight:600;color:#1e40af;margin-top:4px;"><?php echo htmlspecialchars($ov['created_by']); ?></div>
                <?php if(!empty($ov['created_at'])): ?>
                  <small style="color:#94a3b8;"><?php echo date('d M, h:i A',strtotime($ov['created_at'])); ?></small>
                <?php endif; ?>
              </td>
              <td style="padding:10px;">
                <span style="background:<?php echo $impact_bg; ?>;color:<?php echo $impact_color; ?>;padding:4px 10px;border-radius:6px;font-weight:800;font-size:13px;border:1px solid <?php echo $impact_color; ?>;">
                  <?php echo $impact_text; ?>
                </span>
              </td>
              <td style="padding:10px;">
                <form method="POST" style="display:inline">
                  <input type="hidden" name="override_id" value="<?php echo $ov['id']; ?>">
                  <button type="submit" name="delete_override" class="btn btn-xs btn-danger" onclick="return confirm('Remove this override for <?php echo addslashes($ov['name']); ?>?')">
                    <i class="fa fa-trash"></i> Remove
                  </button>
                </form>
              </td>
            </tr>
            <?php endwhile; ?>
          </tbody>
        </table>
      </div>
    </div>
    <?php else: ?>
    <div style="background:#f8fafc;border:2px dashed #e2e8f0;border-radius:12px;padding:16px;margin-bottom:25px;text-align:center;color:#94a3b8;font-size:13px;">
      <i class="fa fa-calendar-check-o" style="font-size:22px;display:block;margin-bottom:6px;"></i>
      No attendance overrides for <strong><?php echo htmlspecialchars($overrides_label); ?></strong>
    </div>
    <?php endif; ?>

    <!-- PAYROLL TABLE -->
    <?php if($total_records>0): ?>
    <div class="tw">
      <form method="POST" id="payslipSendForm">
      <?php if($can_approve_payroll): ?>
      <div class="payslip-send-bar" style="display:flex;align-items:center;gap:14px;padding:10px 14px;background:#eff6ff;border:2px solid #bfdbfe;border-radius:10px;margin-bottom:12px;flex-wrap:wrap;">
        <label style="display:flex;align-items:center;gap:6px;font-weight:700;color:#1e40af;font-size:13px;cursor:pointer;margin:0;">
          <input type="checkbox" id="selAllPayslip" style="width:16px;height:16px;cursor:pointer;"> Select All Employees
        </label>
        <span id="payslipSelCount" style="font-size:12px;color:#64748b;font-weight:600;">0 selected</span>
        <button type="submit" name="bulk_approve_payroll" class="btn btn-p" id="sendSelectedBtn" style="margin-left:auto;" disabled><i class="fa fa-paper-plane"></i> Send Selected Payslips</button>
      </div>
      <?php endif; ?>
      <table class="pt">
        <thead>
          <tr>
            <?php if($can_approve_payroll): ?><th style="width:34px;"><input type="checkbox" id="selAllPayslipHead" title="Select All"></th><?php endif; ?>
            <th>Sl</th><th>Month</th><th>Employee</th>
            <th>Basic</th><th>HRA</th><th>Conv</th><th>Special</th><th>Gross</th><th>Per Day</th>
            <th>Present Days</th><th>📉 Reduce Days</th><th>🏖️ Paid Leave</th><th>⚠️ No-Logout</th><th>🛏️ Unpaid Leave</th><th>⏱️ Late Days</th><th>⏱️ Late Policy (Deducted)</th><th>Absent Days</th><th>⭐ OT Days</th><th>⭐ OT Amount</th>
            <th>Arrears</th><th>Overtime</th><th>Incentives</th><th style="color:#10b981">Other Earnings</th>
            <th>PF</th><th>Total CTC</th>
            <th>Advance</th><th>Penalty</th><th style="color:#ef4444">Other Deductions</th><th>Net Salary</th>
            <th>Approval</th><th>Payslip</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php
          // Build cache: total holidays per month/year from master table
          $hol_totals_cache = [];
          $htc = mysqli_query($dbConn,"SELECT year,month,COUNT(*) as cnt FROM hr_office_holidays GROUP BY year,month");
          if($htc) while($hc=mysqli_fetch_assoc($htc)) $hol_totals_cache[$hc['year'].'-'.$hc['month']] = floatval($hc['cnt']);

          $sl=1; mysqli_data_seek($data,0);
          while($row=mysqli_fetch_assoc($data)):
              $ot_val   = floatval($row['ot_amount']??$row['ot']);
              $ot_days  = floatval($row['weekends_worked']??0);
              $per_day  = floatval($row['per_day_salary']??0) ?: round(floatval($row['gross_pay'])/26,2);
              $my       = date("M Y", mktime(0,0,0,$row['pay_month'],1,$row['pay_year']));
              $is_ot    = $ot_val > 0;
              $total_present = floatval($row['present_days']) + $ot_days; // normal + OT
          ?>
          <tr class="<?php echo $is_ot ? 'ot-row' : ''; ?>">
            <?php if($can_approve_payroll): ?><td><input type="checkbox" name="payroll_ids[]" value="<?php echo $row['id']; ?>" class="payslip-chk"></td><?php endif; ?>
            <td><?php echo $sl++; ?></td>
            <td style="font-weight:700;color:#8b5cf6"><?php echo $my; ?></td>
            <td style="font-weight:700;color:#1e40af">
              <?php echo htmlspecialchars($row['name']); ?>
              <br><small style="color:#64748b"><?php echo htmlspecialchars($row['emp_code']); ?></small>
              <br><small style="color:#6366f1;font-weight:600;"><i class="fa fa-building-o"></i> <?php echo htmlspecialchars($row['company_name']); ?></small>
            </td>
            <td>₹<?php echo number_format($row['basic_salary']); ?></td>
            <td>₹<?php echo number_format($row['hra']); ?></td>
            <td>₹<?php echo number_format($row['conveyance']); ?></td>
            <td>₹<?php echo number_format($row['special_allowance']); ?></td>
            <td style="font-weight:700;color:#3b82f6">₹<?php echo number_format($row['gross_pay']); ?></td>
            <td style="color:#8b5cf6;font-weight:700">₹<?php echo number_format($per_day,2); ?></td>
            <td>
              <div style="font-weight:800;font-size:14px;color:#10b981"><?php
                $pd = floatval($row['present_days']);
                echo ($pd == intval($pd)) ? intval($pd) : $pd;
              ?></div>
              <small style="color:#64748b;font-weight:600;">/ 26 base</small>
              <?php if($total_present != $row['present_days']): ?>
                <br><small style="color:#64748b;font-weight:700;">Total: <?php echo $total_present; ?></small>
              <?php endif; ?>
            </td>
            <td>
              <div style="font-weight:700;color:#ef4444"><?php
                $rd = floatval($row['reduce_days'] ?? 0);
                echo ($rd > 0) ? "-".$rd : "0";
              ?></div>
            </td>
            <td>
              <div style="font-weight:700;color:#f59e0b"><?php
                $pld = floatval($row['paid_leave_days'] ?? 0);
                echo ($pld == intval($pld)) ? intval($pld) : $pld;
              ?></div>
              <?php
                $emp_hols       = intval($row['holidays_in_month'] ?? 0);
                $total_hols_mo  = $hol_totals_cache[$row['pay_year'].'-'.$row['pay_month']] ?? 0;
                if($total_hols_mo > 0):
                  if($emp_hols < $total_hols_mo):
              ?>
                <br><small style="color:#dc2626;font-weight:700;background:#fee2e2;padding:2px 7px;border-radius:6px;display:inline-block;margin-top:3px;"
                  title="This employee joined after some holidays this month — those holidays are not counted for them">
                  <i class="fa fa-calendar-times-o"></i> <?php echo $emp_hols; ?>/<?php echo $total_hols_mo; ?> holidays (joined mid-month)
                </small>
              <?php else: ?>
                <br><small style="color:#059669;font-weight:700;background:#d1fae5;padding:2px 7px;border-radius:6px;display:inline-block;margin-top:3px;">
                  <i class="fa fa-calendar-check-o"></i> <?php echo $emp_hols; ?>/<?php echo $total_hols_mo; ?> holidays
                </small>
              <?php endif; endif; ?>
            </td>
            <td>
              <?php
                if(!empty($row['comment']) && preg_match('/(\d+) half-day/', $row['comment'], $hm) && intval($hm[1]) > 0):
              ?>
                <small style="color:#f59e0b;font-weight:600;" title="Employees who checked-in but did not check-out get 0.5 day salary">
                  <i class="fa fa-exclamation-triangle"></i> <?php echo $hm[1]; ?>× 0.5 day each
                </small>
              <?php else: ?>
                <small style="color:#94a3b8;">—</small>
              <?php endif; ?>
            </td>
            <td>
              <?php
                if(!empty($row['comment']) && preg_match('/([0-9\.]+) unpaid-leave/', $row['comment'], $hm) && floatval($hm[1]) > 0):
              ?>
                <small style="color:#ef4444;font-weight:700;"><i class="fa fa-bed"></i> <?php echo $hm[1]; ?> days</small>
              <?php else: ?>
                <small style="color:#94a3b8;">—</small>
              <?php endif; ?>
            </td>
            <td>
              <?php
                $ld = floatval($row['late_days'] ?? 0);
                if($ld > 0):
              ?>
                <small style="color:#d97706;font-weight:700;"><i class="fa fa-clock-o"></i> <?php echo $ld; ?> days</small>
              <?php else: ?>
                <small style="color:#94a3b8;">—</small>
              <?php endif; ?>
            </td>
            <td>
              <?php
                if(!empty($row['comment']) && preg_match('/(\d+) late-absent/', $row['comment'], $hm) && intval($hm[1]) > 0):
              ?>
                <small style="color:#dc2626;font-weight:700;"><i class="fa fa-minus-circle"></i> <?php echo $hm[1]; ?> days deducted</small>
              <?php else: ?>
                <small style="color:#94a3b8;">—</small>
              <?php endif; ?>
            </td>
            <td style="color:#ef4444;font-weight:700"><?php
              $ad = floatval($row['absent_days']);
              echo ($ad == intval($ad)) ? intval($ad) : $ad;
            ?></td>
            <td style="<?php echo ($ot_days>0 || floatval($row['calendar_ot'])>0)?'color:#d97706;font-weight:800;background:#fffbeb;':'color:#64748b;'; ?>">
              <?php 
                $cal_ot = floatval($row['calendar_ot']);
                $approved_days = floatval($row['approve_ot']);
                $display_ot = $ot_days;
                if($cal_ot > 0 && $approved_days < $cal_ot) {
                    $display_ot += ($cal_ot - $approved_days); 
                }
              ?>
              <?php if($display_ot>0): ?>⭐ <?php endif; ?><?php echo ($display_ot == intval($display_ot)) ? intval($display_ot) : $display_ot; ?>
              <?php if($display_ot>0): ?><br><small>extra days</small><?php endif; ?>
              
              <?php if($cal_ot > 0): ?>
                  <div style="margin-top:6px;display:flex;flex-direction:column;gap:5px;">
                  <?php if($approved_days == 0): ?>
                      <span style="font-size:10px;font-weight:700;color:#d97706;background:#fef3c7;padding:2px 6px;border-radius:4px;display:inline-block;width:max-content;line-height:1;">Pending Approval</span>
                  <?php elseif($approved_days < $cal_ot): ?>
                      <span style="font-size:10px;font-weight:700;color:#0ea5e9;background:#e0f2fe;padding:2px 6px;border-radius:4px;display:inline-block;width:max-content;line-height:1;">Partial: <?php echo $approved_days; ?>d Approved</span>
                  <?php else: ?>
                      <span style="font-size:10px;font-weight:700;color:#059669;background:#d1fae5;padding:2px 6px;border-radius:4px;display:inline-block;width:max-content;line-height:1;">Approved</span>
                  <?php endif; ?>
                  
                  <button type="button" class="btn-s" style="padding:4px 8px;font-size:10px;border-radius:4px;box-shadow:none;width:max-content;" onclick="toggleOt(<?php echo $row['id']; ?>, <?php echo $cal_ot; ?>, <?php echo $approved_days; ?>)">Edit OT</button>
                  </div>
              <?php endif; ?>
            </td>
            <td style="<?php echo $ot_val>0?'color:#d97706;font-weight:800;background:#fffbeb;':'color:#64748b;'; ?>">
              ₹<?php echo number_format($ot_val); ?>
            </td>
            <td>
              <?php $arr_days = floatval($row['arrears_days']??0); ?>
              ₹<?php echo number_format($row['arrears']); ?>
              <?php if($arr_days>0): ?><br><small style="color:#64748b;"><?php echo $arr_days; ?> days</small><?php endif; ?>
            </td>
            <td>₹<?php echo number_format($row['overtime']); ?></td>
            <td>₹<?php echo number_format($row['incentives']); ?></td>
            <td style="color:#10b981;font-weight:700">₹<?php echo number_format($row['other_earnings']??0); ?></td>
            <td style="color:#ef4444;font-weight:700">₹<?php echo number_format($row['pf']); ?></td>
            <td style="font-weight:700;color:#8b5cf6">₹<?php echo number_format($row['total_ctc']); ?></td>
            <td>₹<?php echo number_format($row['advance_salary']); ?></td>
            <td>₹<?php echo number_format($row['penalty']); ?></td>
            <td style="color:#ef4444;font-weight:700">₹<?php echo number_format($row['other_deductions']??0); ?></td>
            <td style="font-weight:900;color:#10b981;font-size:15px">₹<?php echo number_format($row['net_salary']); ?></td>
            <td>
              <?php
                $apr_status = $row['approval_status'] ?? 'pending';
                $apr_sent   = intval($row['payslip_sent'] ?? 0);
                $apr_err    = $row['payslip_send_error'] ?? '';
              ?>
              <?php if($apr_status === 'approved' && $apr_sent): ?>
                <span class="apr-badge approved" title="Sent <?php echo !empty($row['payslip_sent_at']) ? date('d M Y, h:i A', strtotime($row['payslip_sent_at'])) : ''; ?>"><i class="fa fa-check-circle"></i> Sent</span>
              <?php elseif($apr_status === 'approved' && !$apr_sent): ?>
                <span class="apr-badge failed" title="<?php echo htmlspecialchars($apr_err); ?>"><i class="fa fa-exclamation-triangle"></i> Approved, email failed</span>
              <?php elseif($apr_status === 'rejected'): ?>
                <span class="apr-badge rejected"><i class="fa fa-ban"></i> Held Back</span>
              <?php else: ?>
                <span class="apr-badge pending"><i class="fa fa-clock-o"></i> Pending Approval</span>
              <?php endif; ?>
              <?php if($can_approve_payroll): ?>
                <?php
                  // FIX: this button used to be hidden once a row was
                  // approved+sent ($apr_status!=='approved' || !$apr_sent),
                  // so there was no way to resend a payslip after the first
                  // successful send — e.g. to correct a wrong email address,
                  // or resend after a personal_email was added/fixed later.
                  // Always show a button; just relabel it "Resend" once sent.
                  $apr_btn_label = ($apr_status === 'approved' && $apr_sent) ? 'Resend' : (($apr_status === 'approved') ? 'Retry Send' : 'Approve');
                ?>
                <br><button type="button" class="ab appr" style="width:auto;height:auto;padding:4px 9px;font-size:10px;margin-top:4px;" onclick='confirmApprove(<?php echo $row["id"]; ?>,"<?php echo addslashes($row["name"]); ?>","<?php echo $my; ?>","<?php echo addslashes($row["emp_email"] ?? ""); ?>")' title="Send Payslip Again"><i class="fa fa-check"></i> <?php echo $apr_btn_label; ?></button>
                <?php if($apr_status === 'pending'): ?>
                <button type="button" class="ab rej" style="width:auto;height:auto;padding:4px 9px;font-size:10px;margin-top:4px;" onclick='confirmReject(<?php echo $row["id"]; ?>,"<?php echo addslashes($row["name"]); ?>","<?php echo $my; ?>")' title="Hold Back (no email)"><i class="fa fa-ban"></i> Hold</button>
                <?php endif; ?>
              <?php endif; ?>
            </td>
            <td><a href="?download_payslip=<?php echo $row['id']; ?>" target="_blank" class="ab dl" title="Payslip"><i class="fa fa-download"></i></a></td>
            <td>
              <div style="display:flex;gap:5px;justify-content:center;">
                <button class="ab edit" style="background:#10b981;color:white;border-color:#059669;" onclick='excuseLatePenalties(<?php echo $row["id"]; ?>, <?php echo $row["employee_id"]; ?>, "<?php echo $row["pay_year"]; ?>-<?php echo str_pad($row["pay_month"],2,"0",STR_PAD_LEFT); ?>", "<?php echo addslashes($row['name']); ?>")' title="Excuse Late Penalties"><i class="fa fa-magic"></i></button>
                <button class="ab edit" onclick='editPayroll(<?php echo json_encode($row,JSON_HEX_APOS|JSON_HEX_QUOT); ?>)' title="Edit"><i class="fa fa-pencil"></i></button>
                <button class="ab del" onclick='confirmDelete(<?php echo $row["id"]; ?>,"<?php echo addslashes($row['name']); ?>","<?php echo $my; ?>")' title="Delete"><i class="fa fa-trash"></i></button>
              </div>
            </td>
          </tr>
          <?php endwhile; ?>
        </tbody>
      </table>
      </form>
    </div>
    <div class="totals">
      <div class="ti"><div class="tl">Records</div><div class="tv"><?php echo $total_records; ?></div></div>
      <div class="ti"><div class="tl">Total Gross</div><div class="tv">₹<?php echo number_format($total_gross); ?></div></div>
      <div class="ti"><div class="tl">⭐ Total OT</div><div class="tv" style="color:#fcd34d">₹<?php echo number_format($total_ot); ?></div></div>
      <div class="ti"><div class="tl">Total CTC</div><div class="tv">₹<?php echo number_format($total_ctc_sum); ?></div></div>
      <div class="ti"><div class="tl">Total Net Salary</div><div class="tv">₹<?php echo number_format($total_net); ?></div></div>
    </div>
    <?php else: ?>
    <div style="text-align:center;padding:80px;color:#64748b;">
      <i class="fa fa-database" style="font-size:80px;color:#cbd5e1;display:block;margin-bottom:20px;"></i>
      <h3>No Payroll Data</h3>
      <p>Click "Generate Payroll" to create records for the selected period.</p>
    </div>
    <?php endif; ?>
    </div><!-- /pvListTabContent -->

    <?php if($is_payroll_overview_viewer): ?>
    <div id="pvOverviewTabContent" style="<?php echo ($pv_tab !== 'overview') ? 'display:none;' : ''; ?>">
      <div class="stats">
        <div class="sc blue"><div class="lbl">Overview Period</div><div class="val" style="font-size:15px;"><?php echo htmlspecialchars($pv_period_label); ?></div></div>
        <div class="sc purple"><div class="lbl"><i class="fa fa-users"></i> Employees Paid</div><div class="val"><?php echo $pv_total_employees; ?></div></div>
        <div class="sc green"><div class="lbl"><i class="fa fa-money"></i> Total Net Paid</div><div class="val">₹<?php echo number_format($pv_total_net); ?></div></div>
        <div class="sc blue"><div class="lbl"><i class="fa fa-briefcase"></i> Total Gross</div><div class="val">₹<?php echo number_format($pv_total_gross); ?></div></div>
        <div class="sc teal"><div class="lbl"><i class="fa fa-star"></i> Total OT</div><div class="val">₹<?php echo number_format($pv_total_ot); ?></div></div>
        <div class="sc orange"><div class="lbl"><i class="fa fa-minus-circle"></i> Total Deductions</div><div class="val">₹<?php echo number_format($pv_total_deductions); ?></div></div>
      </div>

      <div class="ctrl">
        <form method="POST" style="display:flex;gap:15px;align-items:flex-end;flex-wrap:wrap;">
          <input type="hidden" name="pv_tab_marker" value="1">
          <div><label>From</label><input type="date" name="pv_filter_from" class="fc" value="<?php echo htmlspecialchars($pv_filter_from); ?>"></div>
          <div><label>To</label><input type="date" name="pv_filter_to" class="fc" value="<?php echo htmlspecialchars($pv_filter_to); ?>"></div>
          <button type="submit" name="pv_apply_filter" class="btn btn-p"><i class="fa fa-filter"></i> Apply</button>
        </form>
      </div>

      <?php if($pv_total_records === 0): ?>
        <div style="text-align:center;padding:60px 20px;color:#64748b;">
          <i class="fa fa-inbox" style="font-size:40px;display:block;margin-bottom:12px;"></i> No payroll records found for this period.
        </div>
      <?php else: ?>

      <div style="background:#eef2ff;border:2px solid #6366f1;border-radius:14px;padding:16px 20px;margin-bottom:20px;display:flex;gap:15px;align-items:flex-end;flex-wrap:wrap;justify-content:space-between;">
        <div><label style="color:#1e40af;">Employee</label>
          <select id="pvFilterEmployee" class="fc" style="min-width:210px;" onchange="pvApplyFilter('employee', this.value)">
            <option value="">— All Employees —</option>
          </select>
        </div>
        <div><label style="color:#1e40af;">Department</label>
          <select id="pvFilterDept" class="fc" style="min-width:180px;" onchange="pvApplyFilter('department', this.value)">
            <option value="">— All Departments —</option>
          </select>
        </div>
        <div><label style="color:#1e40af;">Position</label>
          <select id="pvFilterPosition" class="fc" style="min-width:180px;" onchange="pvApplyFilter('position', this.value)">
            <option value="">— All Positions —</option>
          </select>
        </div>
        <button type="button" class="btn" style="background:linear-gradient(135deg,#64748b,#475569);color:white;" onclick="pvClearAllFilters()"><i class="fa fa-times"></i> Clear Filters</button>
      </div>

      <div id="pvChips" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px;"></div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:22px;margin-bottom:30px;" class="pv-charts-grid">
        <div style="background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);">
          <h4 style="color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;"><i class="fa fa-building"></i> Net Salary &amp; Gross Pay by Company <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
          <div style="position:relative;height:280px;"><canvas id="pvChartCompany"></canvas></div>
        </div>
        <div style="background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);">
          <h4 style="color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;"><i class="fa fa-sitemap"></i> Net Salary &amp; Gross Pay by Department <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
          <div style="position:relative;height:280px;"><canvas id="pvChartDept"></canvas></div>
        </div>
        <div style="background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);">
          <h4 style="color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;"><i class="fa fa-id-badge"></i> Net Salary &amp; Gross Pay by Position <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
          <div style="position:relative;height:280px;"><canvas id="pvChartPosition"></canvas></div>
        </div>
        <div style="background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);">
          <h4 style="color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;"><i class="fa fa-line-chart"></i> Monthly Trend (Net / Gross / OT) <small style="font-weight:600;color:#94a3b8;">(click a point for details)</small></h4>
          <div style="position:relative;height:280px;"><canvas id="pvChartTrend"></canvas></div>
        </div>
      </div>

      <div style="background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);margin-bottom:30px;">
        <h4 style="color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;"><i class="fa fa-trophy"></i> Employee Leaderboard <span id="pvLbCount" style="font-weight:600;font-size:12px;color:#64748b;"></span> <small style="font-weight:600;color:#94a3b8;">(click a row for full details)</small></h4>
        <div style="background:white;border-radius:14px;overflow-x:auto;max-height:520px;overflow-y:auto;">
          <table class="table table-condensed" style="width:100%;font-size:13px;min-width:900px;margin:0;">
            <thead style="background:linear-gradient(135deg,#1e40af,#1e3a8a);color:white;position:sticky;top:0;">
              <tr>
                <th style="padding:10px;">Employee</th><th style="padding:10px;">Company</th><th style="padding:10px;">Department</th><th style="padding:10px;">Position</th>
                <th style="padding:10px;">Records</th><th style="padding:10px;">Present Days</th><th style="padding:10px;">Total Gross</th><th style="padding:10px;">Total OT</th><th style="padding:10px;">Total Deductions</th><th style="padding:10px;">Total Net</th>
              </tr>
            </thead>
            <tbody id="pvLbBody"></tbody>
          </table>
        </div>
      </div>

      <?php endif; ?>
    </div>
    <?php endif; ?><!-- /pvOverviewTabContent -->
  </div>
</div>

<!-- PAYROLL OVERVIEW DRILL-DOWN MODAL — shows raw records for the clicked
     chart segment or leaderboard row, matching the KPI/Attendance pattern. -->
<div id="pvDrillModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog modal-lg" style="width:900px;">
    <div class="modal-content mc">
      <div class="modal-header mh" style="background:linear-gradient(135deg,#1e3c72,#2a5298);">
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
        <h4 class="modal-title" id="pvDrillModalTitle"><i class="fa fa-list"></i> Details</h4>
      </div>
      <div class="modal-body mb" style="max-height:500px;overflow-y:auto;">
        <table class="table table-condensed" style="font-size:12px;margin:0;">
          <thead style="background:#eef2ff;">
            <tr>
              <th>Employee</th><th>Month</th><th>Company</th><th>Department</th><th>Position</th>
              <th>Present Days</th><th>Gross</th><th>OT</th><th>Deductions</th><th>Net</th>
            </tr>
          </thead>
          <tbody id="pvDrillModalBody"></tbody>
        </table>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Close</button></div>
    </div>
  </div>
</div>

<!-- MARK EMPLOYEES MODAL -->
<div class="modal fade" id="markModal" tabindex="-1">
  <div class="modal-dialog modal-lg" style="width:800px;">
    <div class="modal-content mc">
      <div class="modal-header mh" style="background:linear-gradient(135deg,#8b5cf6,#7c3aed);">
        <button type="button" class="close" data-dismiss="modal" style="color:white;opacity:1;">&times;</button>
        <h4 class="modal-title" style="font-weight:800;font-size:18px;"><i class="fa fa-users"></i> Mark Holiday / Leave / Absent for Employees</h4>
      </div>
      <form method="POST">
        <div class="modal-body mb">
          <div style="background:#f0fdf4;border:2px solid #10b981;border-radius:10px;padding:12px;margin-bottom:20px;font-size:13px;color:#065f46;">
            <strong><i class="fa fa-info-circle"></i> How this affects payroll:</strong><br>
            • <strong>Holiday / Leave (Paid)</strong> → Adds to present days count (counts towards 26)<br>
            • <strong>Present (Force)</strong> → Marks as present even without biometric<br>
            • <strong>Half Day</strong> → Counts as 0.5 day (e.g. no logout, or came half day)<br>
            • <strong>Absent</strong> → Subtracts from present days (salary deduction)
          </div>
          <div style="margin-bottom:10px;">
            <input type="text" id="empSearch" class="form-control" placeholder="Search employee..." style="border:2px solid #8b5cf6;border-radius:8px;height:38px;font-size:13px;">
          </div>
          <div style="max-height:250px;overflow-y:auto;border:2px solid #8b5cf6;border-radius:10px;">
            <label style="display:block;padding:10px 14px;background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:white;font-weight:800;cursor:pointer;margin:0;position:sticky;top:0;z-index:1;">
              <input type="checkbox" id="selAll" style="width:17px;height:17px;margin-right:10px;vertical-align:middle;"> Select All
            </label>
            <div style="padding:10px;" class="emp-list">
              <?php while($e=mysqli_fetch_assoc($active_emps)): ?>
              <label class="emp-item" style="display:block;padding:9px;margin-bottom:5px;background:white;border-radius:7px;border:2px solid #e9d5ff;cursor:pointer;font-weight:normal;transition:all .2s;" onmouseover="this.style.background='#f3e8ff'" onmouseout="this.style.background='white'">
                <input type="checkbox" name="employee_ids[]" value="<?php echo $e['id']; ?>" style="width:16px;height:16px;margin-right:8px;vertical-align:middle;">
                <strong style="color:#7c3aed"><?php echo htmlspecialchars($e['name']); ?></strong>
                <span style="color:#64748b;font-size:12px;margin-left:6px;">(<?php echo htmlspecialchars($e['employee_id']); ?>)</span>
              </label>
              <?php endwhile; ?>
            </div>
          </div>
          <div class="row" style="margin-top:18px;">
            <div class="col-md-6"><label>From Date *</label><input type="date" name="from_date" class="form-control fc" required></div>
            <div class="col-md-6"><label>To Date *</label><input type="date" name="to_date" class="form-control fc" required></div>
          </div>
          <div style="margin-top:15px;">
            <label>Mark As *</label>
            <script>
            function checkMarkStatus(val) {
                if(val === 'force_login') {
                    document.getElementById('forceLoginTimes').style.display = 'block';
                } else {
                    document.getElementById('forceLoginTimes').style.display = 'none';
                }
            }
            </script>
            <select name="mark_status" class="form-control fc" required onchange="checkMarkStatus(this.value)">
              <option value="">-- Select Status --</option>
              <option value="holiday">🏖️ Holiday (Paid — adds to present count)</option>
              <option value="leave">📅 Leave (Paid — adds to present count)</option>
              <option value="present">✅ Present (Force mark - HR Override)</option>
              <option value="force_login">🕒 Force Log In (Creates normal check-in record)</option>
              <option value="half_day">🌗 Half Day (0.5 — no logout / partial day)</option>
              <option value="absent">❌ Absent (Deduction)</option>
            </select>
          </div>
          <div id="forceLoginTimes" style="display:none; margin-top:15px; background:#f0f9ff; padding:15px; border-radius:8px; border:1px solid #3b82f6;">
            <div class="row">
              <div class="col-md-6"><label>Check In Time</label><input type="time" name="f_in_time" value="09:00" class="form-control fc"></div>
              <div class="col-md-6"><label>Check Out Time</label><input type="time" name="f_out_time" value="18:00" class="form-control fc"></div>
            </div>
            <p style="margin:5px 0 0 0;font-size:11px;color:#0284c7;"><i class="fa fa-info-circle"></i> This creates an actual attendance record as if the employee tapped in and out.</p>
          </div>
          <div style="margin-top:15px;">
            <label>Reason (Optional)</label>
            <textarea name="mark_reason" class="form-control" rows="2" style="border:2px solid #8b5cf6;border-radius:8px;font-size:13px;" placeholder="e.g. Public holiday, Medical leave..."></textarea>
          </div>
        </div>
        <div class="modal-footer" style="background:#faf5ff;border-top:2px solid #8b5cf6;">
          <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
          <button type="submit" name="bulk_mark_holiday" class="btn btn-v"><i class="fa fa-check"></i> Mark Selected Employees</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL -->
<div id="editModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content mc">
      <div class="modal-header mh" style="background:linear-gradient(135deg,#1e3c72,#2a5298);">
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
        <h4 class="modal-title"><i class="fa fa-edit"></i> Edit Payroll</h4>
      </div>
      <form method="POST">
        <div class="modal-body mb">
          <input type="hidden" name="update_payroll" value="1">
          <input type="hidden" name="payroll_id" id="m_id">
          <div style="background:linear-gradient(135deg,#dbeafe,#bfdbfe);padding:15px;border-radius:10px;margin-bottom:18px;">
            <strong id="m_name" style="color:#1e40af;font-size:17px;"></strong>
            <br><small id="m_code" style="color:#64748b;font-weight:600;"></small>
          </div>
          <div style="background:#f1f5f9;border:1px solid #cbd5e1;border-radius:9px;padding:12px;margin-bottom:18px;">
            <div class="row">
                <div class="col-xs-6">
                    <label style="color:#0f172a;"><i class="fa fa-star" style="color:#f59e0b;"></i> Approved Auto OT Days <span id="ot_display" style="color:#d97706;font-weight:700;margin-left:4px;"></span></label>
                    <input type="number" step="0.5" min="0" name="approve_ot" id="m_approve_ot" class="form-control fc" placeholder="e.g. 1.5">
                </div>
                <div class="col-xs-6">
                    <label style="color:#0f172a;"><i class="fa fa-minus-circle" style="color:#ef4444;"></i> Reduce Working Days</label>
                    <input type="number" step="0.5" min="0" name="reduce_days" id="m_reduce_days" class="form-control fc" placeholder="e.g. 1">
                </div>
            </div>
          </div>
          <h5 style="color:#10b981;font-weight:800;border-bottom:2px solid #10b981;padding-bottom:8px;margin-bottom:15px;"><i class="fa fa-plus-circle"></i> Additional Earnings</h5>
          <div class="row">
            <div class="col-xs-3">
              <label>Arrears Days</label>
              <input type="number" step="0.5" min="0" name="arrears_days" id="m_arr_days" class="form-control fc" placeholder="e.g. 2">
              <small style="color:#64748b;">Amount auto = days × per day</small>
            </div>
            <div class="col-xs-3"><label>OT Amount <small style="color:#94a3b8;">(override)</small></label><input type="number" step="0.01" name="ot_amount" id="m_ot" class="form-control fc"></div>
            <div class="col-xs-3"><label>Overtime</label><input type="number" step="0.01" name="overtime" id="m_ovt" class="form-control fc"></div>
            <div class="col-xs-3"><label>Incentives</label><input type="number" step="0.01" name="incentives" id="m_inc" class="form-control fc"></div>
          </div>
          <div class="row" style="margin-top:12px;">
            <div class="col-xs-12">
              <label style="color:#10b981;font-weight:700;"><i class="fa fa-plus"></i> Other Earnings</label>
              <input type="number" step="0.01" min="0" name="other_earnings" id="m_oear" class="form-control fc" placeholder="Any extra earning not listed above">
            </div>
          </div>
          <h5 style="color:#ef4444;font-weight:800;border-bottom:2px solid #ef4444;padding-bottom:8px;margin:20px 0 15px;"><i class="fa fa-minus-circle"></i> Deductions</h5>
          <div class="row">
            <div class="col-xs-4"><label>Advance Salary</label><input type="number" step="0.01" name="advance" id="m_adv" class="form-control fc"></div>
            <div class="col-xs-4"><label>Penalty</label><input type="number" step="0.01" name="penalty" id="m_pen" class="form-control fc"></div>
            <div class="col-xs-4">
              <label style="color:#ef4444;font-weight:700;"><i class="fa fa-minus"></i> Other Deductions</label>
              <input type="number" step="0.01" min="0" name="other_deductions" id="m_oded" class="form-control fc" placeholder="Any extra deduction">
            </div>
          </div>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-default pull-left" data-dismiss="modal">Cancel</button>
            <button type="submit" name="reject_after_edit" value="1" class="btn btn-d"><i class="fa fa-ban"></i> Save & Hold Back</button>
            <button type="submit" name="save_only" value="1" class="btn btn-p"><i class="fa fa-save"></i> Save</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- DELETE MODAL -->
<div id="delModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content mc">
    <div class="modal-header mh" style="background:linear-gradient(135deg,#ef4444,#dc2626);">
      <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      <h4 class="modal-title"><i class="fa fa-trash"></i> Confirm Delete</h4>
    </div>
    <form method="POST"><div class="modal-body mb" style="text-align:center;">
      <input type="hidden" name="delete_payroll" value="1">
      <input type="hidden" name="payroll_id" id="del_id">
      <i class="fa fa-exclamation-triangle" style="font-size:50px;color:#ef4444;margin-bottom:15px;display:block;"></i>
      <h4>Delete this payroll record?</h4>
      <p style="margin-top:10px;"><strong id="del_name" style="color:#1e40af;"></strong><br><span id="del_my" style="color:#8b5cf6;"></span></p>
    </div>
    <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-d"><i class="fa fa-trash"></i> Delete</button></div>
    </form></div>
  </div>
</div>

<!-- APPROVE & SEND PAYSLIP MODAL (Management Approval) -->
<div id="approveModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content mc">
    <div class="modal-header mh" style="background:linear-gradient(135deg,#3b82f6,#1e40af);">
      <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      <h4 class="modal-title"><i class="fa fa-check-circle"></i> Approve & Release Payslip</h4>
    </div>
    <form method="POST"><div class="modal-body mb" style="text-align:center;">
      <input type="hidden" name="approve_payroll" value="1">
      <input type="hidden" name="payroll_id" id="apr_id">
      <i class="fa fa-paper-plane" style="font-size:50px;color:#3b82f6;margin-bottom:15px;display:block;"></i>
      <h4>Approve this payroll and email the payslip?</h4>
      <p style="margin-top:10px;"><strong id="apr_name" style="color:#1e40af;"></strong><br><span id="apr_my" style="color:#8b5cf6;"></span></p>
      <p style="margin-top:8px;font-size:13px;">Payslip will be sent to: <strong id="apr_email" style="color:#059669;"></strong></p>
      <p id="apr_no_email_warn" style="display:none;margin-top:8px;font-size:12px;color:#dc2626;font-weight:700;">⚠️ No personal email on file — approval will succeed but the email will fail. Add a personal email to the employee's profile first.</p>
      <p style="margin-top:12px;font-size:12px;color:#64748b;">The payslip is only ever emailed after this approval step — nothing sends automatically.</p>
    </div>
    <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-p"><i class="fa fa-check"></i> Approve & Send</button></div>
    </form></div>
  </div>
</div>

<!-- REJECT / HOLD BACK MODAL (Management Approval) -->
<div id="rejectModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content mc">
    <div class="modal-header mh" style="background:linear-gradient(135deg,#64748b,#475569);">
      <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      <h4 class="modal-title"><i class="fa fa-ban"></i> Hold Back Payroll</h4>
    </div>
    <form method="POST"><div class="modal-body mb" style="text-align:center;">
      <input type="hidden" name="reject_payroll" value="1">
      <input type="hidden" name="payroll_id" id="rej_id">
      <i class="fa fa-exclamation-triangle" style="font-size:50px;color:#64748b;margin-bottom:15px;display:block;"></i>
      <h4>Hold back this payroll record?</h4>
      <p style="margin-top:10px;"><strong id="rej_name" style="color:#1e40af;"></strong><br><span id="rej_my" style="color:#8b5cf6;"></span></p>
      <p style="margin-top:8px;font-size:12px;color:#64748b;">No payslip email will be sent. You can approve it later once it's ready.</p>
    </div>
    <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-d"><i class="fa fa-ban"></i> Hold Back</button></div>
    </form></div>
  </div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/js/bootstrap.min.js"></script>
<script>
$('#selAll').on('change', function() { $('input[name="employee_ids[]"]').prop('checked', this.checked); });
$('#empSearch').on('keyup', function() {
    var v = $(this).val().toLowerCase();
    $('.emp-list .emp-item').filter(function() { $(this).toggle($(this).text().toLowerCase().includes(v)); });
});

function editPayroll(d) {
    $('#m_id').val(d.id);
    $('#m_name').text(d.name);
    $('#m_code').text('ID: ' + d.emp_code);
    var ot = d.ot_amount ? parseFloat(d.ot_amount) : parseFloat(d.ot||0);
    
    // New fields binding
    var approve_ot = parseFloat(d.approve_ot || 0);
    var reduce_days = parseFloat(d.reduce_days || 0);
    var calendar_ot = parseFloat(d.calendar_ot || 0);
    
    $('#m_arr_days').val(d.arrears_days||0); $('#m_ot').val(ot);
    $('#m_ovt').val(d.overtime); $('#m_inc').val(d.incentives);
    $('#m_oear').val(d.other_earnings||0);
    $('#m_adv').val(d.advance_salary); $('#m_pen').val(d.penalty);
    $('#m_oded').val(d.other_deductions||0);
    
    $('#m_approve_ot').val(approve_ot);
    $('#m_reduce_days').val(reduce_days);
    
    if(calendar_ot > 0) {
        $('#ot_display').text('(Max: ' + calendar_ot + ')');
    } else {
        $('#ot_display').text('(No Auto OT)');
    }
    
    $('#editModal').modal('show');
}

function excuseLatePenalties(payrollId, empId, monthStr, empName) {
    if(confirm('Are you sure you want to excuse all Late Penalties for ' + empName + ' for ' + monthStr + '?')) {
        $.ajax({
            url: window.location.href,
            type: 'POST',
            data: { excuse_late_penalties: 1, emp_id: empId, month: monthStr },
            dataType: 'json',
            success: function(res) {
                if(res.success) {
                    alert(res.message);
                    location.reload();
                } else {
                    alert('Error: ' + (res.error || 'Failed to excuse late penalties.'));
                }
            },
            error: function() {
                alert('Network error while processing request.');
            }
        });
    }
}

function confirmDelete(id, name, my) {
    $('#del_id').val(id); $('#del_name').text(name); $('#del_my').text(my);
    $('#delModal').modal('show');
}

function confirmApprove(id, name, my, email) {
    $('#apr_id').val(id); $('#apr_name').text(name); $('#apr_my').text(my);
    if(email) {
        $('#apr_email').text(email);
        $('#apr_no_email_warn').hide();
    } else {
        $('#apr_email').text('(none on file)');
        $('#apr_no_email_warn').show();
    }
    $('#approveModal').modal('show');
}

function confirmReject(id, name, my) {
    $('#rej_id').val(id); $('#rej_name').text(name); $('#rej_my').text(my);
    $('#rejectModal').modal('show');
}

// ── Send Payslips: tick/untick employees, bulk-approve & email selected ──
function updatePayslipSelection() {
    var checked = $('.payslip-chk:checked').length;
    var total   = $('.payslip-chk').length;
    $('#payslipSelCount').text(checked + ' of ' + total + ' selected');
    $('#sendSelectedBtn').prop('disabled', checked === 0);
    $('#selAllPayslip, #selAllPayslipHead').prop('checked', total > 0 && checked === total);
}
$(document).on('change', '.payslip-chk', updatePayslipSelection);
$(document).on('change', '#selAllPayslip, #selAllPayslipHead', function() {
    var on = $(this).is(':checked');
    $('.payslip-chk').prop('checked', on);
    $('#selAllPayslip, #selAllPayslipHead').prop('checked', on);
    updatePayslipSelection();
});
$('#payslipSendForm').on('submit', function(e) {
    var n = $('.payslip-chk:checked').length;
    if (n === 0) { e.preventDefault(); return false; }
    if (!confirm('Send payslips to ' + n + ' selected employee(s) now?\n\nThis will approve and email each one immediately — this cannot be undone.')) {
        e.preventDefault();
        return false;
    }
});
$(function(){ updatePayslipSelection(); });

function toggleOt(pid, current_cal_ot, currently_approved) {
    let msg = 'How many OT days do you want to approve?\n(Available Auto OT: ' + current_cal_ot + ')';
    let def = currently_approved || current_cal_ot;
    let days = prompt(msg, def);
    
    if(days !== null) {
        let parsedDays = parseFloat(days);
        if(isNaN(parsedDays) || parsedDays < 0 || parsedDays > current_cal_ot) {
            alert('Invalid number of days. Must be between 0 and ' + current_cal_ot);
            return;
        }
        
        $.post('<?php echo $_SERVER['PHP_SELF']; ?>', {
            toggle_approve_ot: 1, 
            pid: pid, 
            approved_days: parsedDays
        }, function(r){
            if(r.success) { location.reload(); }
            else { alert(r.msg); }
        });
    }
}
</script>

<?php if($is_payroll_overview_viewer && $pv_total_records > 0): ?>
<script>
const pvRecords = <?php echo $pv_records_json; ?>;

// Unified filter state — populated either from the Employee/Department/Position
// dropdowns above the charts, or from clicking a chart bar/point (both write
// here, so charts + leaderboard always stay in sync from one source of truth).
let pvFilters = { department: '', position: '', employee: '', month: '', company: '' };
let pvCompanyChart, pvDeptChart, pvPositionChart, pvTrendChart;

function pvFmtMoney(n){ return '₹' + Math.round(n).toLocaleString('en-IN'); }

function pvGroupSum(records, keyFn){
    const map = {};
    records.forEach(r => {
        const k = keyFn(r);
        if(!map[k]) map[k] = { net:0, gross:0, ot:0, emp:new Set() };
        map[k].net += r.net; map[k].gross += r.gross; map[k].ot += r.ot;
        map[k].emp.add(r.emp_code);
    });
    return map;
}

function pvFilteredRecords(){
    return pvRecords.filter(r =>
        (!pvFilters.department || r.department === pvFilters.department) &&
        (!pvFilters.position   || r.position   === pvFilters.position) &&
        (!pvFilters.employee   || r.employee   === pvFilters.employee) &&
        (!pvFilters.month      || r.month_label === pvFilters.month) &&
        (!pvFilters.company    || r.company    === pvFilters.company)
    );
}

function pvApplyFilter(type, value){
    pvFilters[type] = value;
    if(type === 'department') document.getElementById('pvFilterDept').value = value;
    if(type === 'position')   document.getElementById('pvFilterPosition').value = value;
    if(type === 'employee')   document.getElementById('pvFilterEmployee').value = value;
    pvRenderAll();
}

function pvClearOneFilter(type){ pvApplyFilter(type, ''); }

function pvClearAllFilters(){
    pvFilters = { department: '', position: '', employee: '', month: '', company: '' };
    document.getElementById('pvFilterDept').value = '';
    document.getElementById('pvFilterPosition').value = '';
    document.getElementById('pvFilterEmployee').value = '';
    pvRenderAll();
}

function pvRenderAll(){
    pvRefreshCharts();
    pvRenderLeaderboard();
    pvRenderChips();
}

function pvRenderChips(){
    const labels = { department: 'Department', position: 'Position', employee: 'Employee', month: 'Month', company: 'Company' };
    const active = Object.keys(pvFilters).filter(k => pvFilters[k]);
    const box = document.getElementById('pvChips');
    if(active.length === 0){ box.innerHTML = ''; return; }
    box.innerHTML = active.map(k =>
        `<span class="chip">${labels[k]}: ${pvFilters[k]} <button onclick="pvClearOneFilter('${k}')">✕</button></span>`
    ).join('') + (active.length > 1 ? `<span class="chip clear-all" onclick="pvClearAllFilters()">Clear All ✕</span>` : '');
}

function pvPopulateDropdowns(){
    const fill = (id, values) => {
        const sel = document.getElementById(id);
        values.forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
    };
    fill('pvFilterEmployee', [...new Set(pvRecords.map(r => r.employee))].sort());
    fill('pvFilterDept',     [...new Set(pvRecords.map(r => r.department))].sort());
    fill('pvFilterPosition', [...new Set(pvRecords.map(r => r.position))].sort());
}

// Opens the "all details" modal — raw, un-aggregated records for whatever
// dimension/value was clicked (chart bar/point or a leaderboard row).
function pvOpenDrillModal(title, records){
    document.getElementById('pvDrillModalTitle').innerHTML = '<i class="fa fa-list"></i> ' + title + ' <small style="font-weight:600;opacity:.8;">(' + records.length + ' record' + (records.length===1?'':'s') + ')</small>';
    const body = document.getElementById('pvDrillModalBody');
    body.innerHTML = records.map(r => `
        <tr>
          <td style="font-weight:700;color:#1e40af;">${r.employee}</td>
          <td>${r.month_label}</td>
          <td>${r.company}</td>
          <td>${r.department}</td>
          <td>${r.position}</td>
          <td style="text-align:center;">${r.present_days}</td>
          <td>${pvFmtMoney(r.gross)}</td>
          <td style="color:#d97706;">${pvFmtMoney(r.ot)}</td>
          <td style="color:#dc2626;">${pvFmtMoney(r.deductions)}</td>
          <td style="font-weight:900;color:#059669;">${pvFmtMoney(r.net)}</td>
        </tr>`).join('');
    $('#pvDrillModal').modal('show');
}

function pvRenderLeaderboard(){
    const recs = pvFilteredRecords();
    const byEmp = {};
    recs.forEach(r => {
        if(!byEmp[r.emp_code]) byEmp[r.emp_code] = {
            employee:r.employee, company:r.company, department:r.department, position:r.position,
            records:0, present_days:0, gross:0, ot:0, deductions:0, net:0
        };
        const e = byEmp[r.emp_code];
        e.records++; e.present_days += r.present_days; e.gross += r.gross;
        e.ot += r.ot; e.deductions += r.deductions; e.net += r.net;
    });
    const list = Object.values(byEmp).sort((a,b) => b.net - a.net);
    document.getElementById('pvLbCount').textContent = '(' + list.length + ' employee' + (list.length===1?'':'s') + ')';
    const body = document.getElementById('pvLbBody');
    body.innerHTML = list.map(e => `
        <tr class="pv-lb-row" onclick='pvOpenDrillModal(${JSON.stringify(e.employee)}, pvRecords.filter(r => r.employee === ${JSON.stringify(e.employee)}))'>
          <td style="font-weight:700;color:#1e40af;">${e.employee}</td>
          <td>${e.company}</td>
          <td>${e.department}</td>
          <td>${e.position}</td>
          <td style="text-align:center;">${e.records}</td>
          <td style="text-align:center;">${e.present_days}</td>
          <td>${pvFmtMoney(e.gross)}</td>
          <td style="color:#d97706;">${pvFmtMoney(e.ot)}</td>
          <td style="color:#dc2626;">${pvFmtMoney(e.deductions)}</td>
          <td style="font-weight:900;color:#059669;">${pvFmtMoney(e.net)}</td>
        </tr>`).join('');
}

function pvBarData(groupKeyFn){
    const grouped = pvGroupSum(pvFilteredRecords(), groupKeyFn);
    const labels = Object.keys(grouped).sort((a,b) => grouped[b].net - grouped[a].net);
    return {
        labels: labels,
        data: labels.map(l => grouped[l].net),
        gross: labels.map(l => grouped[l].gross)
    };
}

function pvMakeBarChart(canvasId, groupKeyFn, drillType, colorBase, grossColor){
    const d = pvBarData(groupKeyFn);
    const ctx = document.getElementById(canvasId).getContext('2d');
    const chart = new Chart(ctx, {
        type: 'bar',
        data: { labels: d.labels, datasets: [
            { label: 'Net Salary', data: d.data, backgroundColor: colorBase, borderRadius: 6 },
            { label: 'Gross Pay', data: d.gross, backgroundColor: grossColor, borderRadius: 6 }
        ] },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            plugins: {
                legend: { display: true, position: 'top', labels: { boxWidth: 12, font: { size: 11 } } },
                tooltip: { callbacks: { label: (c) => c.dataset.label + ': ' + pvFmtMoney(c.parsed.y) } }
            },
            scales: {
                x: { grid: { display: false } },
                y: { beginAtZero: true, ticks: { callback: (v) => '₹' + (v/1000) + 'k' } }
            },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    const label = chart.data.labels[idx];
                    pvApplyFilter(drillType, label);
                    const matching = pvRecords.filter(r => r[drillType] === label);
                    pvOpenDrillModal(drillType.charAt(0).toUpperCase() + drillType.slice(1) + ': ' + label, matching);
                }
            }
        }
    });
    chart.pvGroupKeyFn = groupKeyFn;
    return chart;
}

function pvTrendData(){
    const grouped = pvGroupSum(pvFilteredRecords(), r => r.month_label + '|' + r.year + '|' + String(r.month).padStart(2,'0'));
    const keys = Object.keys(grouped).sort((a,b) => a.split('|')[1]+a.split('|')[2] > b.split('|')[1]+b.split('|')[2] ? 1 : -1);
    return {
        labels: keys.map(k => k.split('|')[0]),
        net: keys.map(k => grouped[k].net),
        gross: keys.map(k => grouped[k].gross),
        ot: keys.map(k => grouped[k].ot)
    };
}

function pvMakeTrendChart(){
    const t = pvTrendData();
    const ctx = document.getElementById('pvChartTrend').getContext('2d');
    const chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: t.labels,
            datasets: [
                { label: 'Net Salary', data: t.net, borderColor: '#059669', backgroundColor: 'rgba(5,150,105,.1)', tension: .3, fill: true, pointRadius: 5, pointHoverRadius: 7 },
                { label: 'Gross Pay', data: t.gross, borderColor: '#2563eb', backgroundColor: 'rgba(37,99,235,.05)', tension: .3, fill: true, pointRadius: 5, pointHoverRadius: 7 },
                { label: 'OT Amount', data: t.ot, borderColor: '#d97706', backgroundColor: 'rgba(217,119,6,.05)', tension: .3, fill: true, pointRadius: 5, pointHoverRadius: 7 }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            plugins: { tooltip: { callbacks: { label: (c) => c.dataset.label + ': ' + pvFmtMoney(c.parsed.y) } } },
            scales: { y: { beginAtZero: true, ticks: { callback: (v) => '₹' + (v/1000) + 'k' } } },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    const label = chart.data.labels[idx];
                    pvApplyFilter('month', label);
                    const matching = pvRecords.filter(r => r.month_label === label);
                    pvOpenDrillModal('Month: ' + label, matching);
                }
            }
        }
    });
    return chart;
}

function pvRefreshCharts(){
    const c = pvBarData(pvCompanyChart.pvGroupKeyFn);
    pvCompanyChart.data.labels = c.labels; pvCompanyChart.data.datasets[0].data = c.data; pvCompanyChart.data.datasets[1].data = c.gross; pvCompanyChart.update();

    const dpt = pvBarData(pvDeptChart.pvGroupKeyFn);
    pvDeptChart.data.labels = dpt.labels; pvDeptChart.data.datasets[0].data = dpt.data; pvDeptChart.data.datasets[1].data = dpt.gross; pvDeptChart.update();

    const pos = pvBarData(pvPositionChart.pvGroupKeyFn);
    pvPositionChart.data.labels = pos.labels; pvPositionChart.data.datasets[0].data = pos.data; pvPositionChart.data.datasets[1].data = pos.gross; pvPositionChart.update();

    const t = pvTrendData();
    pvTrendChart.data.labels = t.labels;
    pvTrendChart.data.datasets[0].data = t.net;
    pvTrendChart.data.datasets[1].data = t.gross;
    pvTrendChart.data.datasets[2].data = t.ot;
    pvTrendChart.update();
}

document.addEventListener('DOMContentLoaded', function(){
    pvPopulateDropdowns();
    pvCompanyChart  = pvMakeBarChart('pvChartCompany', r => r.company, 'company', '#059669', '#6366f1');
    pvDeptChart     = pvMakeBarChart('pvChartDept', r => r.department, 'department', '#059669', '#3b82f6');
    pvPositionChart = pvMakeBarChart('pvChartPosition', r => r.position, 'position', '#059669', '#8b5cf6');
    pvTrendChart    = pvMakeTrendChart();
    pvRenderLeaderboard();
});
</script>
<?php endif; ?>
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