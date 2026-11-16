<?php
// BUILD-MARKER: hr-attendance-list-v8-hotfix-2026-08-01 -- if you don't see
// this exact string in 'view page source' on the live site, the server is
// NOT running this file yet (old file, cache, or wrong path).
// ============================================================================
// ATTENDANCE SYSTEM
// Policy: Checkout must be completed on the SAME DAY as check-in.
//         Midnight crossover feature has been removed per management instruction.
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

// PHP 8.1+ default: mysqli throws an exception on a failed query instead of
// just returning false/a warning — and @ suppression does NOT catch
// exceptions. Must be set before any query that might legitimately fail
// (like the "does this column already exist" migration right below), or a
// duplicate-column ALTER TABLE fatals the whole page with an HTTP 500.
mysqli_report(MYSQLI_REPORT_OFF);

$office_holidays = [];
// Auto-migrate to add worker_category — checked first (not just @-suppressed)
// so this is safe to run on every page load, not just the very first one.
$wc_col_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_employees LIKE 'worker_category'");
if ($wc_col_check && mysqli_num_rows($wc_col_check) == 0) {
    mysqli_query($dbConn, "ALTER TABLE hr_employees ADD COLUMN worker_category VARCHAR(50) DEFAULT 'White Collar'");
}
$oh_q = mysqli_query($dbConn, "SELECT holiday_date, holiday_name FROM hr_office_holidays");
if($oh_q) {
    while($oh = mysqli_fetch_assoc($oh_q)) {
        $office_holidays[$oh['holiday_date']] = $oh['holiday_name'];
    }
}

isUser();

// (mysqli_report(MYSQLI_REPORT_OFF) is set at the top of the file, before
// the worker_category migration query — see the comment up there.)

// FIX: Ensure hr_attendance_overrides table exists, otherwise SELECT queries will fail and cause errors!
$check_overrides = mysqli_query($dbConn, "SHOW TABLES LIKE 'hr_attendance_overrides'");
if ($check_overrides && mysqli_num_rows($check_overrides) == 0) {
    mysqli_query($dbConn, "CREATE TABLE hr_attendance_overrides (
        id INT AUTO_INCREMENT PRIMARY KEY,
        employee_id INT NOT NULL,
        attendance_date DATE NOT NULL,
        status VARCHAR(50) NOT NULL,
        reason TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
}

// FIX: Ensure hr_attendance_access_list table exists for dynamic Admin Attendance permissions
try {
    $check_access_tbl = mysqli_query($dbConn, "SHOW TABLES LIKE 'hr_attendance_access_list'");
    if ($check_access_tbl && mysqli_num_rows($check_access_tbl) == 0) {
        mysqli_query($dbConn, "CREATE TABLE hr_attendance_access_list (
            id INT AUTO_INCREMENT PRIMARY KEY,
            employee_id VARCHAR(50) NOT NULL,
            employee_db_id INT NOT NULL DEFAULT 0,
            employee_name VARCHAR(150),
            employee_email VARCHAR(150),
            can_view_admin ENUM('No','Yes') NOT NULL DEFAULT 'Yes',
            granted_by VARCHAR(150),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_emp_id (employee_id)
        )");
        // Seed default HR admin (Keerti) if exists
        $seed_hr = mysqli_query($dbConn, "SELECT id, employee_id, name, email FROM hr_employees WHERE LOWER(name) LIKE '%keerti%' OR LOWER(name) LIKE '%keerthi%'");
        if ($seed_hr) {
            while ($shr = mysqli_fetch_assoc($seed_hr)) {
                $seid = mysqli_real_escape_string($dbConn, $shr['employee_id']);
                $sedbid = intval($shr['id']);
                $senm = mysqli_real_escape_string($dbConn, $shr['name']);
                $seem = mysqli_real_escape_string($dbConn, $shr['email'] ?? '');
                mysqli_query($dbConn, "INSERT IGNORE INTO hr_attendance_access_list (employee_id, employee_db_id, employee_name, employee_email, can_view_admin, granted_by) VALUES ('$seid', $sedbid, '$senm', '$seem', 'Yes', 'System Default')");
            }
        }
    }
} catch (Throwable $e) {}

// Ensure the "Attendance Location" column exists (HR-controlled free-login flag)
try {
    $col_check_afl = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_employees LIKE 'attendance_free_login'");
    if ($col_check_afl && mysqli_num_rows($col_check_afl) == 0) {
        mysqli_query($dbConn, "ALTER TABLE hr_employees ADD COLUMN attendance_free_login ENUM('No','Yes') NOT NULL DEFAULT 'No' AFTER work_location");
    }
} catch (Throwable $e) {}

// Ensure a marker column exists so an 'absent' row that came from the
// 5-lates=1-absent policy can be told apart from an absence for any other
// reason. Without this there was no way to answer "how many of these
// absences were actually from lateness" precisely -- every 'absent' row in
// a date range looked the same, which is exactly what caused the "14 late
// but 3 absent, shouldn't that be 2?" confusion: some of that 3 wasn't from
// the late policy at all, but nothing distinguished it.
// PHP 8.1+ changed mysqli's default error mode: a failed query now THROWS
// (mysqli_sql_exception) instead of quietly returning false like it always
// used to. None of this file's DB calls (old or new) were written expecting
// that, so try/catch is added around every new query block as a safety net
// -- a failed/unexpected query degrades that one feature instead of taking
// the whole page down with an uncaught exception (a blank "HTTP ERROR 500").
try {
    $col_check_lpc = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_attendance LIKE 'late_policy_converted'");
    if ($col_check_lpc && mysqli_num_rows($col_check_lpc) == 0) {
        mysqli_query($dbConn, "ALTER TABLE hr_attendance ADD COLUMN late_policy_converted ENUM('No','Yes') NOT NULL DEFAULT 'No' AFTER status");
    }
    // SELF-HEALING: If the old engine previously converted late days to 'absent' before the 'late_policy_converted'
    // column was added, they are permanently stuck as 'absent' without the flag, confusing the new engine and the UI.
    // This restores any day where the employee actually checked in back to its true 'late' or 'present' status,
    // allowing the new mathematically stable engine to correctly re-apply penalties with the proper flag.
    mysqli_query($dbConn, "UPDATE hr_attendance SET status = IF(TIME(check_in_time) > '09:30:00', 'late', 'present') WHERE status='absent' AND check_in_time IS NOT NULL AND (late_policy_converted='No' OR late_policy_converted IS NULL)");
} catch (Throwable $e) {
    // Column may already exist under a race, or ALTER isn't permitted --
    // either way, don't crash the page over it.
}

// ============================================================================
// LATE POLICY ENGINE (shared)
// Every 6 total late days in a calendar month = 1 of those days converted to
// 'absent' (which is what actually drives the salary deduction downstream in
// payroll). This used to only run when an admin opened the "6-Day Late
// Policy" card and clicked "Apply" -- so until someone remembered to click
// it, employees could rack up 10, 15, 20 late days and NOT ONE of them would
// ever get converted to absent, and no salary would ever be deducted, even
// though the dashboard text implied the policy was already active. This
// function is now called automatically (see below) so the conversion always
// reflects reality instead of depending on a manual click.
// Returns the list of newly-converted dates (empty array if nothing to do).
// ============================================================================
function abra_apply_late_policy_for_employee($dbConn, $employee_id_escaped, $month_start = null, $month_end = null) {
    // Defaults to the real current month for backward compatibility, but
    // callers can pass any completed month's boundaries too -- see
    // abra_apply_late_policy_for_range() below, which is what actually lets
    // a PAST month (e.g. July, once it's August) still get its 5-lates=1-
    // absent conversion applied when someone views that month's data,
    // instead of that month being frozen forever the moment it ends.
    // Everything below is wrapped in try/catch: on PHP 8.1+, a failed query
    // throws instead of returning false, and this whole function is called
    // on every page load for every employee -- one bad row or one blocked
    // query must never be able to take the page down.
    try {
        $policy_from   = '2026-06-01';
        if($month_start === null) $month_start = date('Y-m-01');
        if($month_end   === null) $month_end   = date('Y-m-t');
        $lates_per_abs = 6;
        $eid           = $employee_id_escaped; // already mysqli_real_escape_string'd by caller

        $emp_q = mysqli_query($dbConn, "SELECT id FROM hr_employees WHERE employee_id='$eid' LIMIT 1");
        $emp_db_id = 0;
        if($emp_q && mysqli_num_rows($emp_q) > 0) {
            $emp_db_id = intval(mysqli_fetch_assoc($emp_q)['id']);
        }

        // 1. Reset existing conversions in the period to avoid stale penalties (like when HR overrides a day later)
        mysqli_query($dbConn, "UPDATE hr_attendance SET status='late', late_policy_converted='No'
            WHERE employee_id='$eid' AND late_policy_converted='Yes' AND date >= '$policy_from' AND date BETWEEN '$month_start' AND '$month_end'");

        // 2. Count legitimate lates (excluding HR overrides)
        $lm = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT COUNT(DISTINCT a.date) as cnt FROM hr_attendance a
            LEFT JOIN hr_attendance_overrides o ON o.employee_id=$emp_db_id AND a.date = o.attendance_date
            WHERE a.employee_id='$eid' AND a.status='late'
            AND (a.check_out_time IS NOT NULL AND a.check_out_time != '')
            AND a.date >= '$policy_from' AND a.date BETWEEN '$month_start' AND '$month_end'
            AND (o.status IS NULL OR o.status NOT IN ('present','holiday','leave'))
        "));

        $total_late  = intval($lm['cnt'] ?? 0);
        $absents_due = intval($total_late / $lates_per_abs);

        $applied  = [];
        if($absents_due > 0) {
            $late_days = mysqli_query($dbConn, "
                SELECT DISTINCT a.date FROM hr_attendance a
                LEFT JOIN hr_attendance_overrides o ON o.employee_id=$emp_db_id AND a.date = o.attendance_date
                WHERE a.employee_id='$eid' AND a.status='late'
                AND (a.check_out_time IS NOT NULL AND a.check_out_time != '')
                AND a.date >= '$policy_from' AND a.date BETWEEN '$month_start' AND '$month_end'
                AND (o.status IS NULL OR o.status NOT IN ('present','holiday','leave'))
                ORDER BY a.date ASC
            ");
            $ldays = [];
            if($late_days) while($ld = mysqli_fetch_assoc($late_days)) $ldays[] = $ld['date'];

            for($i = 1; $i <= $absents_due; $i++) {
                $idx = ($i * $lates_per_abs) - 1;
                if(isset($ldays[$idx])) {
                    $ds = mysqli_real_escape_string($dbConn, $ldays[$idx]);
                    mysqli_query($dbConn, "UPDATE hr_attendance SET status='absent', late_policy_converted='Yes' WHERE employee_id='$eid' AND date='$ds'");
                    $applied[] = $ldays[$idx];
                }
            }
        }
        return $applied;
    } catch (Throwable $e) {
        return [];
    }
}

// ============================================================================
// Applies the late policy to EVERY calendar month touched by an arbitrary
// date range (e.g. a "My Attendance" or admin filter that spans one or more
// past months). Without this, the policy silently only ever ran against
// "the real month right now" -- so a month that already ended before anyone
// applied it (a real scenario: 16 late days in July, nobody clicked Apply
// before August 1st) would NEVER get its absent-day conversion, no matter
// how many times the data was viewed afterwards. This walks month-by-month
// across the range and re-runs the (idempotent) per-month check for each.
// ============================================================================
function abra_apply_late_policy_for_range($dbConn, $employee_id_escaped, $range_start, $range_end) {
    $applied_all = [];
    if(empty($range_start) || empty($range_end)) return $applied_all;
    $cursor = date('Y-m-01', strtotime($range_start));
    $end_ts = strtotime(date('Y-m-01', strtotime($range_end)));
    $guard  = 0;
    while(strtotime($cursor) <= $end_ts && $guard < 240) { // 240 months = 20yr safety cap
        $m_start = $cursor;
        $m_end   = date('Y-m-t', strtotime($cursor));
        $applied_all = array_merge($applied_all, abra_apply_late_policy_for_employee($dbConn, $employee_id_escaped, $m_start, $m_end));
        $cursor = date('Y-m-01', strtotime($cursor . ' +1 month'));
        $guard++;
    }
    return $applied_all;
}

// Present/Absent day-counts can now carry a .5 (half-day credit -- see
// where $half_day_credit is added). number_format($n) alone would silently
// round 24.5 up to "25", hiding the exact fraction the stat card exists to
// show. Whole numbers still render clean with no decimal.
function abra_fmt_days($n) {
    return (floor($n) == $n) ? number_format($n) : number_format($n, 1);
}

// Expands a start_date/end_date pair into a flat array of 'Y-m-d' strings.
// Used for every half-day-leave date lookup (admin table, personal table,
// missed-logout exemption). Malformed/legacy date data -- an empty string,
// a MySQL zero-date '0000-00-00', or an end_date before start_date -- used
// to go straight into `new DateTime(...)`, which throws an uncaught
// Exception on an unparseable string and took the WHOLE page down with a
// 500 for every visitor, not just the one bad row. This validates first and
// simply skips the record if it can't be parsed, so one bad hr_leaves row
// can never crash attendance for everyone else again.
function abra_safe_date_range($start_date, $end_date) {
    $dates = [];
    if(empty($start_date) || empty($end_date)) return $dates;
    if($start_date === '0000-00-00' || $end_date === '0000-00-00') return $dates;
    try {
        $start = new DateTime($start_date);
        $end   = new DateTime($end_date);
    } catch (Exception $e) {
        return $dates;
    }
    if($end < $start) return $dates;
    // Hard cap so a corrupt/huge range can never turn into a runaway loop.
    if($start->diff($end)->days > 366) return $dates;
    try {
        $period = new DatePeriod($start, new DateInterval('P1D'), $end->modify('+1 day'));
        foreach ($period as $d) $dates[] = $d->format('Y-m-d');
    } catch (Exception $e) {
        return [];
    }
    return $dates;
}

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// ============================================================================
// ROLE DETECTION & MASTER SUPER ADMIN RESOLUTION
// ============================================================================
// Identity is taken ONLY from the authenticated session (never straight from a
// cookie / URL param), so a stale cookie cannot grant someone else's identity.
$current_probe_email = $_SESSION['flutter_user_email'] ?? $_SESSION['user_email'] ?? $_SESSION['email'] ?? '';

// Master Super Admin (original name rule; the email/ID rule is applied below
// against the resolved employee record).
$is_super_admin = (stripos($currentUserName, 'Abishek') !== false);
$atn_tab   = isset($_GET['atn_tab']) ? $_GET['atn_tab'] : 'overview';
$is_keerti = (stripos($currentUserName, 'Keerti') !== false || stripos($currentUserName, 'Keerthi') !== false);

$user_emp_data = null;

// 1. Try resolving by Email (Official or Personal email from session/cookie/request)
if(!empty($current_probe_email)) {
    $eml_safe = mysqli_real_escape_string($dbConn, trim(strtolower($current_probe_email)));
    $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE (LOWER(TRIM(email)) = '$eml_safe' OR LOWER(TRIM(personal_email)) = '$eml_safe') ORDER BY status ASC LIMIT 1");
    if($emp_check && mysqli_num_rows($emp_check) > 0) {
        $user_emp_data = mysqli_fetch_assoc($emp_check);
    }
}

// 2. Try resolving by employee_id from session if available (e.g. AT006)
if(!$user_emp_data && !empty($_SESSION['employee_id'])) {
    $eid_safe = mysqli_real_escape_string($dbConn, trim($_SESSION['employee_id']));
    $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE employee_id = '$eid_safe' ORDER BY status ASC LIMIT 1");
    if($emp_check && mysqli_num_rows($emp_check) > 0) {
        $user_emp_data = mysqli_fetch_assoc($emp_check);
    }
}

// 3. Try resolving by user_id from session
if(!$user_emp_data && !empty($_SESSION['user_id']) && is_numeric($_SESSION['user_id'])) {
    $uid_safe = intval($_SESSION['user_id']);
    $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE id = $uid_safe ORDER BY status ASC LIMIT 1");
    if($emp_check && mysqli_num_rows($emp_check) > 0) {
        $user_emp_data = mysqli_fetch_assoc($emp_check);
    }
}

// 4. Try resolving by Username / Full Name (handles initial/suffix like SREESHMA KS)
if(!$user_emp_data && !empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($dbConn, $currentUserName);
    $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) ORDER BY status ASC LIMIT 1");
    
    // Fuzzy matching for names with initials or phonetic variations (e.g. 'sreeshma' or 'shreeshma' -> 'SREESHMA KS')
    if(!$emp_check || mysqli_num_rows($emp_check) == 0) {
        // Only accepted when the FIRST NAME matches exactly one employee (no substring matches).
        $orig_first  = explode(' ', strtolower(trim($currentUserName)))[0];
        $clean_first = str_replace('sh', 's', $orig_first);
        $of_safe = mysqli_real_escape_string($dbConn, $orig_first);
        $cf_safe = mysqli_real_escape_string($dbConn, $clean_first);
        $emp_check   = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE
            (LOWER(SUBSTRING_INDEX(TRIM(name), ' ', 1)) = '$of_safe' OR
             REPLACE(LOWER(SUBSTRING_INDEX(TRIM(name), ' ', 1)), 'sh', 's') = '$cf_safe')
            AND status = 'active'
            ORDER BY id ASC LIMIT 2");
        if($emp_check && mysqli_num_rows($emp_check) != 1) { $emp_check = null; }
    }

    if(!$emp_check || mysqli_num_rows($emp_check) == 0) {
        if($is_super_admin)
            $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%abishek%' OR employee_id = 'ABRA001' OR employee_id = 'AT003') ORDER BY status ASC LIMIT 1");
        elseif($is_keerti)
            $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%keerti%' OR LOWER(name) LIKE '%keerthi%' OR employee_id = 'AT001') ORDER BY status ASC LIMIT 1");
    }
    if($emp_check && mysqli_num_rows($emp_check) > 0)
        $user_emp_data = mysqli_fetch_assoc($emp_check);
}

    $is_active_employee = ($user_emp_data && strtolower($user_emp_data['status'] ?? '') === 'active');

    // If admin still not found in hr_employees, create a virtual record for attendance purposes
    if(!$user_emp_data && ($is_super_admin || $is_keerti)) {
        $user_emp_data = [
            'employee_id' => $is_super_admin ? 'ADMIN001' : 'ADMIN002',
            'name' => $currentUserName,
            'position' => 'Administrator',
            'department' => 'Management',
            'work_location' => '',
            'timings' => '09:00 AM',
            'status' => 'active'
        ];
    }

// Double check master super admin status against employee record
if($user_emp_data) {
    if(!empty($user_emp_data['email']) && stripos($user_emp_data['email'], 'abishek.veeraswamy@fleet.abra-travels.com') !== false) {
        $is_super_admin = true;
    }
    if(!empty($user_emp_data['employee_id']) && $user_emp_data['employee_id'] === 'ABRA001') {
        $is_super_admin = true;
    }
}

// Load authorized admin viewers from hr_attendance_access_list
$attendance_access_allowed = [];
try {
    $acc_chk = mysqli_query($dbConn, "SELECT employee_id, employee_db_id, employee_email FROM hr_attendance_access_list WHERE can_view_admin = 'Yes'");
    if($acc_chk) {
        while($arow = mysqli_fetch_assoc($acc_chk)) {
            if(!empty($arow['employee_id']))    $attendance_access_allowed[strtolower(trim($arow['employee_id']))] = true;
            if(!empty($arow['employee_email'])) $attendance_access_allowed[strtolower(trim($arow['employee_email']))] = true;
            if(!empty($arow['employee_db_id'])) $attendance_access_allowed['db_' . intval($arow['employee_db_id'])] = true;
        }
    }
} catch (Throwable $e) {}

// Managing Director / Executive matching with strict word boundary check (prevents false matches like 'sales and marketing')
$is_managing_director = false;
if($user_emp_data) {
    $user_position = trim($user_emp_data['position'] ?? '');
    $is_managing_director = (
        stripos($user_position, 'managing director') !== false ||
        preg_match('/\b(md|ceo)\b/i', $user_position) === 1
    );
}

// Check if user has permission to view Admin Attendance Dashboard:
// 1. Master Super Admin (Abishek / abishek.veeraswamy@fleet.abra-travels.com)
// 2. HR Admin (Keerti)
// 3. Legitimate Managing Director / CEO
// 4. Any employee explicitly granted access in hr_attendance_access_list
$has_attendance_admin_access = false;
if($is_super_admin || $is_keerti || $is_managing_director) {
    $has_attendance_admin_access = true;
} elseif($user_emp_data) {
    $cur_eid  = strtolower(trim($user_emp_data['employee_id'] ?? ''));
    $cur_eml  = strtolower(trim($user_emp_data['email'] ?? ($user_emp_data['personal_email'] ?? '')));
    $cur_dbid = 'db_' . intval($user_emp_data['id'] ?? 0);

    if(
        (!empty($cur_eid) && isset($attendance_access_allowed[$cur_eid])) ||
        (!empty($cur_eml) && isset($attendance_access_allowed[$cur_eml])) ||
        isset($attendance_access_allowed[$cur_dbid])
    ) {
        $has_attendance_admin_access = true;
    }
}

$is_admin = $has_attendance_admin_access;

$md_exclude_sql = " AND (position IS NULL OR (LOWER(position) NOT LIKE '%managing director%' AND LOWER(position) NOT LIKE '%ceo%'))";

// ============================================================================
// TRAINING / OJE KPI EXEMPTION (moved up so it's available BEFORE the
// attendance-submission handler below, not just for the display badges).
// Employees flagged as Training/OJE (checked across their hr_employees
// fields, same rule the page already used for the on-screen badges), and
// inactive employees, are exempt from the mandatory KPI-before-checkout
// requirement. This used to only be computed further down the file, AFTER
// the checkout POST handler had already run -- so the checkout handler had
// no way to know about the exemption and blocked these employees with
// "Daily KPI Review Required" even though the rest of the page (and the
// pre-camera JS gate) treated them as exempt. Computing it here fixes that
// mismatch at the source.
// ============================================================================
$is_oje_training = false;
if($user_emp_data) {
    foreach($user_emp_data as $key => $val) {
        if(is_string($val)) {
            $v = strtolower($val);
            if(strpos($v, 'oje') !== false || strpos($v, 'training') !== false) {
                $is_oje_training = true;
                break;
            }
        }
    }
}
// Convenience flag used by the checkout handler (and reused later for the
// display badges/JS gate) -- true when this employee should NOT be blocked
// by the KPI-before-checkout requirement at all.
$is_kpi_exempt = (!$is_active_employee || $is_oje_training);

// AUTO-APPLY the 5-lates-=-1-absent policy for the CURRENTLY LOGGED IN
// employee, every page load. Previously this only ever happened when an
// admin manually opened the "6-Day Late Policy" card and clicked Apply --
// so the salary deduction it's supposed to trigger (via the resulting
// 'absent' row) silently never happened unless someone remembered to do
// that by hand. Real employee IDs only; the virtual admin records (ADMIN001/
// ADMIN002) have no matching hr_attendance rows so this is a harmless no-op
// for them.
if($user_emp_data && !empty($user_emp_data['employee_id'])) {
    $auto_lp_eid = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    abra_apply_late_policy_for_employee($dbConn, $auto_lp_eid);
}

// ============================================================================
// ATTENDANCE LOCATION MODE (HR-controlled, per employee)
// Set on the employee's profile: Add/Edit Employee → "Attendance Location".
// Replaces the old hardcoded position/department name matching.
// ============================================================================
$bypass_location = (
    isset($user_emp_data['attendance_free_login']) &&
    strtolower(trim($user_emp_data['attendance_free_login'])) === 'yes'
);
// Virtual admin records (no real hr_employees row) have no work location to
// enforce, so they stay free-login by default.
if (!isset($user_emp_data['attendance_free_login']) && ($is_super_admin || $is_keerti)) {
    $bypass_location = true;
}

// ============================================================================
// AJAX: CHECK ATTENDANCE STATUS FOR A DATE
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'check_date_status' && $user_emp_data) {
    header('Content-Type: application/json');
    $chk_date  = mysqli_real_escape_string($dbConn, $_GET['date'] ?? date('Y-m-d'));
    $emp_id_s  = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $rec       = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id='$emp_id_s' AND date='$chk_date' LIMIT 1");
    $row       = $rec ? mysqli_fetch_assoc($rec) : null;
    if(!$row) {
        echo json_encode(['state'=>'nothing', 'msg'=>'No attendance marked for ' . date('D, d M Y', strtotime($chk_date)) . '. You can Check In now.']);
    } elseif(!empty($row['check_in_time']) && empty($row['check_out_time'])) {
        echo json_encode(['state'=>'checkin_only', 'checkin_time' => date('h:i A', strtotime($row['check_in_time'])), 'msg'=>'Checked in at ' . date('h:i A', strtotime($row['check_in_time'])) . ' on ' . date('D, d M Y', strtotime($chk_date)) . '. Check Out pending.']);
    } else {
        echo json_encode(['state'=>'all_done', 'checkin_time' => date('h:i A', strtotime($row['check_in_time'])), 'checkout_time' => date('h:i A', strtotime($row['check_out_time'])), 'msg'=>'Check In: ' . date('h:i A', strtotime($row['check_in_time'])) . ' → Check Out: ' . date('h:i A', strtotime($row['check_out_time']))]);
    }
    exit;
}

// ============================================================================
// AJAX: APPLY LATE ATTENDANCE POLICY (admin only)
// Every 6 total late days in a month = 1 day marked absent
// ============================================================================
// ============================================================================
// AJAX: ATTENDANCE ACCESS LIST (Super Admin & HR)
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'get_attendance_access_list' && ($is_super_admin || $is_keerti)) {
    header('Content-Type: application/json');
    $emps_q = mysqli_query($dbConn, "
        SELECT e.id, e.employee_id, e.name, e.department, e.position, e.email,
               IFNULL(a.can_view_admin, 'No') AS can_view_admin,
               a.updated_at, a.granted_by
        FROM hr_employees e
        LEFT JOIN hr_attendance_access_list a ON (a.employee_id = e.employee_id OR a.employee_db_id = e.id)
        WHERE e.status = 'active'
        ORDER BY e.name ASC
    ");
    $list = [];
    if($emps_q) {
        while($r = mysqli_fetch_assoc($emps_q)) {
            $list[] = [
                'id'             => intval($r['id']),
                'employee_id'    => $r['employee_id'],
                'name'           => $r['name'],
                'department'     => $r['department'] ?? '',
                'position'       => $r['position'] ?? '',
                'email'          => $r['email'] ?? '',
                'can_view_admin' => ($r['can_view_admin'] === 'Yes') ? 'Yes' : 'No'
            ];
        }
    }
    echo json_encode(['success' => true, 'employees' => $list]);
    exit();
}

if(isset($_POST['action']) && $_POST['action'] == 'toggle_attendance_access' && ($is_super_admin || $is_keerti)) {
    header('Content-Type: application/json');
    $target_emp_id = mysqli_real_escape_string($dbConn, trim($_POST['employee_id'] ?? ''));
    $target_db_id  = intval($_POST['employee_db_id'] ?? 0);
    $new_status    = (isset($_POST['can_view_admin']) && $_POST['can_view_admin'] === 'Yes') ? 'Yes' : 'No';
    $granted_by    = mysqli_real_escape_string($dbConn, $currentUserName ?: 'Admin');

    if(empty($target_emp_id) && $target_db_id <= 0) {
        echo json_encode(['success' => false, 'message' => 'Invalid employee ID']);
        exit();
    }

    $einfo_q = mysqli_query($dbConn, "SELECT id, employee_id, name, email FROM hr_employees WHERE employee_id = '$target_emp_id' OR id = $target_db_id LIMIT 1");
    $einfo = $einfo_q ? mysqli_fetch_assoc($einfo_q) : null;
    $emp_id_str = $einfo ? $einfo['employee_id'] : $target_emp_id;
    $emp_db_id  = $einfo ? intval($einfo['id']) : $target_db_id;
    $emp_name   = mysqli_real_escape_string($dbConn, $einfo['name'] ?? '');
    $emp_email  = mysqli_real_escape_string($dbConn, $einfo['email'] ?? '');

    $save_q = mysqli_query($dbConn, "
        INSERT INTO hr_attendance_access_list (employee_id, employee_db_id, employee_name, employee_email, can_view_admin, granted_by)
        VALUES ('$emp_id_str', $emp_db_id, '$emp_name', '$emp_email', '$new_status', '$granted_by')
        ON DUPLICATE KEY UPDATE can_view_admin = '$new_status', granted_by = '$granted_by', updated_at = CURRENT_TIMESTAMP
    ");

    if($save_q) {
        echo json_encode(['success' => true, 'message' => 'Access updated successfully', 'can_view_admin' => $new_status]);
    } else {
        echo json_encode(['success' => false, 'message' => 'Database update failed: ' . mysqli_error($dbConn)]);
    }
    exit();
}

if(isset($_GET['action']) && $_GET['action'] == 'apply_late_policy' && $is_admin) {
    header('Content-Type: application/json');
    $affected = [];

    // Manual bulk trigger, kept for admins who want to force a re-check /
    // backfill across everyone right now. Auto-apply (below, near the
    // employee-stats section) already runs this per-employee on every page
    // load, so in normal use this button will usually report "0 required" --
    // that's expected, it means the policy is already up to date.
    $emp_all = mysqli_query($dbConn, "SELECT employee_id, name FROM hr_employees WHERE status='active' $md_exclude_sql");
    while($emp = mysqli_fetch_assoc($emp_all)) {
        $eid = mysqli_real_escape_string($dbConn, $emp['employee_id']);
        $applied_dates = abra_apply_late_policy_for_employee($dbConn, $eid);
        foreach($applied_dates as $ad) {
            $affected[] = ['name' => $emp['name'], 'date' => date('d M Y', strtotime($ad))];
        }
    }

    echo json_encode(['success' => true, 'count' => count($affected), 'affected' => $affected]);
    exit;
}

// AJAX: CHECK who has 6+ total late days this month (for admin badge)
if(isset($_GET['action']) && $_GET['action'] == 'check_late_policy' && $is_admin) {
    header('Content-Type: application/json');
    $flagged     = [];
    $policy_from = '2026-06-01';
    $month_start = (isset($_GET['date_from']) && !empty($_GET['date_from'])) ? mysqli_real_escape_string($dbConn, $_GET['date_from']) : date('Y-m-01');
    $month_end   = (isset($_GET['date_to']) && !empty($_GET['date_to'])) ? mysqli_real_escape_string($dbConn, $_GET['date_to']) : date('Y-m-t');

    $lp_emp_filter = isset($_GET['employee']) ? mysqli_real_escape_string($dbConn, $_GET['employee']) : '';
    $lp_where = "status='active'";
    if($lp_emp_filter) $lp_where .= " AND employee_id = '$lp_emp_filter'";
    $emp_all = mysqli_query($dbConn, "SELECT employee_id, name FROM hr_employees WHERE $lp_where $md_exclude_sql");
    while($emp = mysqli_fetch_assoc($emp_all)) {
        $eid = mysqli_real_escape_string($dbConn, $emp['employee_id']);
        $lm  = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT COUNT(*) as cnt FROM hr_attendance
            WHERE employee_id='$eid' AND (status='late' OR (status='absent' AND late_policy_converted='Yes'))
            AND date >= '$policy_from' AND date BETWEEN '$month_start' AND '$month_end'
        "));
        $total_late = intval($lm['cnt'] ?? 0);
        $am = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT COUNT(*) as cnt FROM hr_attendance
            WHERE employee_id='$eid' AND status='absent' AND late_policy_converted='Yes'
            AND date BETWEEN '$month_start' AND '$month_end'
        "));
        $absents_existing = intval($am['cnt'] ?? 0);
        $absents_due      = intval($total_late / 6);
        $pending_action   = $absents_due - $absents_existing;
        if($total_late >= 6) {
            $flagged[] = ['name' => $emp['name'], 'total_late' => $total_late, 'pending_absent' => $pending_action, 'absents_existing' => $absents_existing];
        }
    }
    echo json_encode(['flagged' => $flagged, 'count' => count($flagged)]);
    exit;
}

// ============================================================================
// EXPORT
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'export') {
    $export_type = isset($_GET['export_type']) ? $_GET['export_type'] : 'admin';
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=attendance_export_' . date('Y-m-d') . '.csv');
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($output, ['Date','Day','Employee ID','Employee Name','Check In','Check Out','Work Hours','Status','Location']);

    if($export_type == 'personal' && $user_emp_data) {
        $emp_id   = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
        $mf_start = isset($_GET['mf_start']) ? mysqli_real_escape_string($dbConn, $_GET['mf_start']) : date('Y-m-d', strtotime('monday this week'));
        $mf_end   = isset($_GET['mf_end'])   ? mysqli_real_escape_string($dbConn, $_GET['mf_end'])   : date('Y-m-d');
        $res = mysqli_query($dbConn, "SELECT a.* FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE a.employee_id = '$emp_id' AND a.date BETWEEN '$mf_start' AND '$mf_end' AND ao.id IS NULL ORDER BY a.date DESC");
        while($row = mysqli_fetch_assoc($res)) {
            fputcsv($output, [date('Y-m-d', strtotime($row['date'])),date('l', strtotime($row['date'])),$row['employee_id'],$row['employee_name'],date('H:i:s', strtotime($row['check_in_time'])),$row['check_out_time'] ? date('H:i:s', strtotime($row['check_out_time'])) : 'Not Checked Out',$row['work_hours'] ? $row['work_hours'].' hours' : '0',ucfirst($row['status']),$row['check_in_location']]);
        }
    } else {
        $date_from  = isset($_GET['date_from']) ? mysqli_real_escape_string($dbConn, $_GET['date_from']) : date('Y-m-d');
        $date_to    = isset($_GET['date_to'])   ? mysqli_real_escape_string($dbConn, $_GET['date_to'])   : date('Y-m-d');
        $emp_filter = isset($_GET['employee'])  ? mysqli_real_escape_string($dbConn, $_GET['employee'])  : '';
        $where = ["a.date BETWEEN '$date_from' AND '$date_to'"];
        if($emp_filter) $where[] = "a.employee_id = '$emp_filter'";
        $res = mysqli_query($dbConn, "SELECT a.* FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE " . implode(' AND ', $where) . " AND ao.id IS NULL ORDER BY a.date DESC, a.employee_name ASC");
        while($row = mysqli_fetch_assoc($res)) {
            fputcsv($output, [date('Y-m-d', strtotime($row['date'])),date('l', strtotime($row['date'])),$row['employee_id'],$row['employee_name'],date('H:i:s', strtotime($row['check_in_time'])),$row['check_out_time'] ? date('H:i:s', strtotime($row['check_out_time'])) : 'Not Checked Out',$row['work_hours'] ? $row['work_hours'].' hours' : '0',ucfirst($row['status']),$row['check_in_location']]);
        }
    }
    fclose($output);
    exit;
}

// ============================================================================
// FIX EXISTING PHOTO PATHS (ADMIN ONLY - ONE TIME)
// Converts relative paths like "uploads/attendance_photos/..."
// to absolute paths like "/uploads/attendance_photos/..."
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'fix_photo_paths' && $is_admin) {
    header('Content-Type: application/json');
    $fixed = 0;

    // Normalize any photo path to /uploads/attendance_photos/...
    // Handles: full URLs with domain, /hrm/uploads/..., relative paths
    function normalizePhotoPath($path) {
        if(empty($path)) return $path;
        // Strip domain if full URL e.g. https://crm.abra-logistic.com/uploads/...
        if(preg_match('#https?://[^/]+(/.+)#', $path, $m)) {
            $path = $m[1];
        }
        // Extract from /uploads/ onwards (removes any /dashboard/ prefix)
        if (preg_match('#attendance_photos/(.+)$#', $path, $m)) { return '/hrm/uploads/attendance_photos/' . $m[1]; }
        // Relative path like uploads/attendance_photos/...
        if(substr($path, 0, 1) !== '/') {
            $path = '/' . ltrim($path, './');
        }
        return $path;
    }

    $res = mysqli_query($dbConn, "SELECT id, check_in_photo, check_out_photo FROM hr_attendance WHERE check_in_photo IS NOT NULL OR check_out_photo IS NOT NULL");
    while($row = mysqli_fetch_assoc($res)) {
        $updates = [];
        $new_in  = normalizePhotoPath($row['check_in_photo']);
        $new_out = normalizePhotoPath($row['check_out_photo']);
        if($new_in  !== $row['check_in_photo'])  $updates[] = "check_in_photo='"  . mysqli_real_escape_string($dbConn, $new_in)  . "'";
        if($new_out !== $row['check_out_photo']) $updates[] = "check_out_photo='" . mysqli_real_escape_string($dbConn, $new_out) . "'";
        if(!empty($updates)) {
            mysqli_query($dbConn, "UPDATE hr_attendance SET " . implode(',', $updates) . " WHERE id=" . intval($row['id']));
            $fixed++;
        }
    }
    echo json_encode(['success' => true, 'fixed' => $fixed, 'message' => "Fixed $fixed attendance photo paths. All now use /uploads/attendance_photos/... format."]);
    exit;
}

// ============================================================================
// DELETE ATTENDANCE (ADMIN ONLY)
// ============================================================================
if(isset($_POST['delete_attendance']) && $is_admin) {
    header('Content-Type: application/json');
    try {
        $emp_id = mysqli_real_escape_string($dbConn, $_POST['employee_id']);
        $date = mysqli_real_escape_string($dbConn, $_POST['date']);

        // First, get the employee's internal ID for override table
        $emp_query = mysqli_query($dbConn, "SELECT id FROM hr_employees WHERE employee_id = '$emp_id' LIMIT 1");
        $emp_internal_id = null;
        if($emp_query && mysqli_num_rows($emp_query) > 0) {
            $emp_internal_id = mysqli_fetch_assoc($emp_query)['id'];
        }

        // Delete from hr_attendance table
        $delete_query = "DELETE FROM hr_attendance WHERE employee_id = '$emp_id' AND date = '$date'";
        $deleted_attendance = mysqli_query($dbConn, $delete_query);
        $attendance_rows = mysqli_affected_rows($dbConn);

        // Also delete from hr_attendance_overrides table if exists
        $deleted_override = false;
        $override_rows = 0;
        if($emp_internal_id) {
            $delete_override = "DELETE FROM hr_attendance_overrides WHERE employee_id = $emp_internal_id AND attendance_date = '$date'";
            $deleted_override = mysqli_query($dbConn, $delete_override);
            $override_rows = mysqli_affected_rows($dbConn);
        }

        $total_deleted = $attendance_rows + $override_rows;

        if($total_deleted > 0) {
            echo json_encode([
                'success' => true,
                'message' => "Attendance record deleted successfully ($total_deleted record(s) removed)"
            ]);
        } else {
            echo json_encode([
                'success' => false,
                'message' => 'No matching attendance record found to delete'
            ]);
        }
    } catch(Exception $e) {
        echo json_encode(['success' => false, 'message' => $e->getMessage()]);
    }
    exit;
}

// ============================================================================
// LOAD LOCATIONS
// ============================================================================
$all_valid_offices = [];
$loc_q = mysqli_query($dbConn, "SELECT location_name, latitude, longitude FROM hr_work_locations WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND latitude != 0 AND longitude != 0 ORDER BY location_name ASC");
if($loc_q && mysqli_num_rows($loc_q) > 0)
    while($loc = mysqli_fetch_assoc($loc_q))
        $all_valid_offices[$loc['location_name']] = ['lat' => floatval($loc['latitude']), 'lng' => floatval($loc['longitude'])];

$user_assigned_location = '';
if($user_emp_data && !empty($user_emp_data['work_location']) && array_key_exists(trim($user_emp_data['work_location']), $all_valid_offices))
    $user_assigned_location = trim($user_emp_data['work_location']);

$user_work_timings   = '';
$late_time_threshold = '09:00';

if($user_emp_data && !empty($user_emp_data['timings'])) {
    $user_work_timings = trim($user_emp_data['timings']);
    if(preg_match('/(\d{1,2})(?::(\d{2}))?\s*AM/i', $user_work_timings, $matches)) {
        $hour   = intval($matches[1]);
        $minute = intval($matches[2] ?? 0);
        if($hour == 12) $hour = 0;
        $late_time_threshold = sprintf('%02d:%02d', $hour, $minute);
    } elseif(preg_match('/(\d{1,2}):(\d{2})\s*(AM|PM)?/i', $user_work_timings, $matches)) {
        $hour     = intval($matches[1]);
        $minute   = intval($matches[2]);
        $meridiem = isset($matches[3]) ? strtoupper($matches[3]) : '';
        if($meridiem == 'PM' && $hour != 12) $hour += 12;
        if($meridiem == 'AM' && $hour == 12) $hour  = 0;
        $late_time_threshold = sprintf('%02d:%02d', $hour, $minute);
    }
}

// ============================================================================
// MIDNIGHT CROSSOVER DETECTION
// Check if employee has an unclosed check-in from YESTERDAY
// (used for both PHP logic and JS frontend)
// ============================================================================
$today          = date('Y-m-d');
$yesterday      = date('Y-m-d', strtotime('-1 day'));

// ============================================================================
// TEMPORARY TEST AID -- simulate a future "today" for the WEEKLY/MONTHLY
// deadline checks only, so you can confirm the checkout block works
// without waiting for a real Saturday/month-end. Admin-only. Does NOT
// change $today itself (real check-in/out timestamps are unaffected) --
// only $kpi_sim_today, which the weekly/monthly due-date comparisons use.
// Usage: hr-attendance-list.php?kpi_test_date=2026-08-01
// Remove this block once you're done testing.
// ============================================================================
$kpi_sim_today = $today;
if (($is_super_admin || $is_keerti) && !empty($_GET['kpi_test_date'])) {
    $kpi_test_candidate = $_GET['kpi_test_date'];
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $kpi_test_candidate) && strtotime($kpi_test_candidate) !== false) {
        $kpi_sim_today = $kpi_test_candidate;
    }
}
$kpi_test_mode_active = ($kpi_sim_today !== $today);
$current_hour   = intval(date('H')); // 0–23
$is_after_midnight_before_6am = ($current_hour >= 0 && $current_hour < 6);

// Midnight crossover DISABLED - checkout must be on the same day
$pending_yesterday_checkin = null;

// ============================================================================
// ATTENDANCE SUBMISSION
// ============================================================================
$error_message   = '';
$success_message = '';

if(isset($_POST['submit_attendance']) && $user_emp_data) {
    try {
        $action_type = $_POST['action_type'];
        $latitude    = floatval($_POST['latitude']);
        $longitude   = floatval($_POST['longitude']);
        $gps_address = mysqli_real_escape_string($dbConn, trim($_POST['location_name']));
        $photo_data  = $_POST['photo_data'];

        if($latitude == 0 || $longitude == 0) throw new Exception("GPS location missing.");
        if(empty($photo_data))                 throw new Exception("Photo required.");

        // $bypass_location is already computed globally above from the
        // employee's HR-set "Attendance Location" field.

        $is_within_range       = false;
        $matched_location_name = 'Unknown';
        $min_distance          = 999999;

        if($bypass_location) {
            $is_within_range       = true;
            $matched_location_name = 'Remote/Field Work';
        } else {
            $target_offices = $all_valid_offices;
            if(!empty($user_assigned_location))
                $target_offices = [$user_assigned_location => $all_valid_offices[$user_assigned_location]];
            foreach($target_offices as $office_name => $coords) {
                $dLat   = deg2rad($coords['lat'] - $latitude);
                $dLng   = deg2rad($coords['lng'] - $longitude);
                $a      = sin($dLat/2)*sin($dLat/2) + cos(deg2rad($latitude))*cos(deg2rad($coords['lat']))*sin($dLng/2)*sin($dLng/2);
                $dist_m = round(6371 * 2 * atan2(sqrt($a), sqrt(1-$a)) * 1000);
                if($dist_m < $min_distance) $min_distance = $dist_m;
                if($dist_m <= 200) { $is_within_range = true; $matched_location_name = $office_name; break; }
            }
            if(!$is_within_range)
                throw new Exception("Location Error: You are {$min_distance}m away from office (Max 200m).");
        }

        $photo_dir_web = '/hrm/uploads/attendance_photos/' . date('Y/m') . '/';
        $photo_dir_fs  = dirname(__DIR__) . $photo_dir_web;  // this site's own hrm/uploads/
        if(!file_exists($photo_dir_fs)) mkdir($photo_dir_fs, 0777, true);

        $emp_id   = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
        $emp_name = mysqli_real_escape_string($dbConn, $user_emp_data['name']);
        $now      = date('H:i:s');

        $photo_binary = base64_decode(str_replace(['data:image/png;base64,',' '], ['','+'], $photo_data));
        $photo_name   = preg_replace('/[^A-Za-z0-9\-]/', '', $emp_id) . '_' . date('YmdHis') . '.png';
        $photo_path   = $photo_dir_web . $photo_name;  // absolute web path saved to DB
        file_put_contents($photo_dir_fs . $photo_name, $photo_binary);

        $final_loc = mysqli_real_escape_string($dbConn, "$matched_location_name ($gps_address)");

        // Use the date the employee selected (supports yesterday for OT/night shift)
        // Always use today — date selection removed per policy
        $att_date = $today;

        $check    = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id = '$emp_id' AND date = '$att_date' LIMIT 1");
        $existing = mysqli_fetch_assoc($check);

        if($action_type == 'check_in') {
            if($existing) throw new Exception("Already checked in on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_in_time'])) . ".");
            $check_hhmm = substr($now, 0, 5);
            $late_hhmm  = $late_time_threshold;

            // FEATURE: if this employee has an APPROVED half-day leave for the
            // MORNING session (half_day_session='first') covering today, they are
            // expected to check in after lunch -- do NOT mark them late, and don't
            // let this day count toward the "5 lates = 1 absent" policy (that policy
            // only counts rows with status='late'). Record as half_day instead.
            $morning_half_day_leave = false;
            $hd_chk = mysqli_query($dbConn, "SELECT id FROM hr_leaves
                WHERE employee_id=" . intval($user_emp_data['id']) . "
                AND leave_type='half_day' AND status='approved' AND half_day_session='first'
                AND '$att_date' BETWEEN start_date AND end_date LIMIT 1");
            if($hd_chk && mysqli_num_rows($hd_chk) > 0) $morning_half_day_leave = true;

            if($morning_half_day_leave) {
                // Still expected to check in on time for the AFTERNOON half.
                // 1:45 PM cutoff -- after that, mark late instead of a blanket half_day.
                $afternoon_late_hhmm = '13:45';
                $status = ($check_hhmm > $afternoon_late_hhmm) ? 'late' : 'half_day';
            } else {
                $status = ($check_hhmm > $late_hhmm) ? 'late' : 'present';
            }
            mysqli_query($dbConn, "INSERT INTO hr_attendance (employee_id, employee_name, date, check_in_time, check_in_photo, check_in_latitude, check_in_longitude, check_in_location, status, daily_salary) VALUES ('$emp_id', '$emp_name', '$att_date', '$now', '$photo_path', '$latitude', '$longitude', '$final_loc', '$status', '0')");
            header("Location: " . $_SERVER['PHP_SELF'] . "?success=checkin"); exit();

        } elseif($action_type == 'check_out') {
            // POLICY: Checkout only allowed on the same day
            if($att_date != $today) throw new Exception("⛔ Checkout must be completed on the same day. The checkout window for " . date('D, d M Y', strtotime($att_date)) . " has expired. Please contact HR if you need assistance.");
            if(!$existing) throw new Exception("No check-in found for " . date('D, d M Y', strtotime($att_date)) . ". Please check in first.");
            if(!empty($existing['check_out_time'])) throw new Exception("Already checked out on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_out_time'])) . ".");

            // KPI only required for today's checkout -- and only for
            // employees who are NOT KPI-exempt (Training/OJE employees and
            // inactive employees are exempt; see $is_kpi_exempt computed
            // near the top of the file, right after $user_emp_data/
            // $is_active_employee are known). Previously this block ran
            // unconditionally for everyone, so a Training/OJE employee could
            // pass the pre-camera JS check (which DID know about the
            // exemption), take their check-out photo, and then get rejected
            // here with "Daily KPI Review Required" anyway -- the exemption
            // existed on screen but not in the actual gate.
            if($att_date == $today && !$is_kpi_exempt) {
                $kpi_check = mysqli_query($dbConn, "SELECT id FROM performance_daily_self WHERE employee_id = '$emp_id' AND review_date = '$today' LIMIT 1");
                if(!$kpi_check || mysqli_num_rows($kpi_check) == 0)
                    throw new Exception("❌ Daily KPI Review Required: Please complete your Daily Self-Evaluation before checking out.");

                // MANDATORY: Weekly self-review due by Saturday of the current
                // week, Monthly self-review due by the last day of the current
                // month -- same rule as the Daily KPI check above. Never blocks
                // a period that started before the employee's joining date.
                $emp_hire_date_chk = (!empty($user_emp_data['hire_date']) && $user_emp_data['hire_date'] != '0000-00-00') ? $user_emp_data['hire_date'] : null;

                $wk_monday_chk   = date('Y-m-d', strtotime('monday this week'));
                $wk_saturday_chk = date('Y-m-d', strtotime($wk_monday_chk . ' +5 days'));
                if($kpi_sim_today >= $wk_saturday_chk && (!$emp_hire_date_chk || strtotime($emp_hire_date_chk) <= strtotime($wk_monday_chk))) {
                    $wk_check = mysqli_query($dbConn, "SELECT id FROM performance_weekly_self WHERE employee_id = '$emp_id' AND week_start_date = '$wk_monday_chk' LIMIT 1");
                    if(!$wk_check || mysqli_num_rows($wk_check) == 0)
                        throw new Exception("❌ Weekly KPI Review Required: Please complete your Weekly Self-Evaluation (this week) before checking out.");
                }

                $mn_chk          = date('Y-m');
                $mn_last_day_chk = date('Y-m-t');
                if($kpi_sim_today >= $mn_last_day_chk && (!$emp_hire_date_chk || strtotime($emp_hire_date_chk) <= strtotime($mn_chk . '-01'))) {
                    $mo_check = mysqli_query($dbConn, "SELECT id FROM performance_monthly_self WHERE employee_id = '$emp_id' AND review_month = '$mn_chk' LIMIT 1");
                    if(!$mo_check || mysqli_num_rows($mo_check) == 0)
                        throw new Exception("❌ Monthly KPI Review Required: Please complete your Monthly Self-Evaluation (this month) before checking out.");
                }
            }

            $checkin_datetime  = $att_date . ' ' . $existing['check_in_time'];
            $checkout_datetime = $today    . ' ' . $now;
            $raw_seconds = strtotime($checkout_datetime) - strtotime($checkin_datetime);
            $raw_hours   = $raw_seconds / 3600;
            $final_hours = ($raw_hours > 1) ? $raw_hours - 1 : $raw_hours;
            $hours       = max(0, round($final_hours, 2));

            mysqli_query($dbConn, "UPDATE hr_attendance SET check_out_time='$now', check_out_photo='$photo_path', check_out_latitude='$latitude', check_out_longitude='$longitude', check_out_location='$final_loc', work_hours='$hours' WHERE id={$existing['id']}");
            header("Location: " . $_SERVER['PHP_SELF'] . "?success=checkout"); exit();
        }
    } catch (Exception $e) {
        $error_message = "⚠️ " . $e->getMessage();
    }
}

if(isset($_GET['success'])) {
    if($_GET['success'] == 'checkin') $success_message = "✓ Check-In Recorded!";
    else                              $success_message = "✓ Check-Out Recorded!";
}




// ============================================================================
// DATA FETCH
// ============================================================================
$admin_result = false;
if($is_admin) {
    $today      = date('Y-m-d');
    $date_from  = isset($_GET['date_from']) ? $_GET['date_from'] : $today;
    $date_to    = isset($_GET['date_to'])   ? $_GET['date_to']   : $today;
    $emp_filter = isset($_GET['employee'])  ? mysqli_real_escape_string($dbConn, $_GET['employee']) : '';

    // AUTO-APPLY the late policy org-wide before computing any admin stats,
    // so the dashboard numbers (Absent count, salary-impacting status, the
    // "6-Day Late Policy" card, exports, etc.) always reflect the policy as
    // already applied instead of requiring the admin to remember to click
    // "Apply" first. Covers BOTH the real current month AND -- crucially --
    // every month actually spanned by the admin's selected date_from/date_to,
    // so viewing a PAST completed month (e.g. July, once it's August) still
    // triggers its conversion instead of that month being frozen forever.
    // Cheap: only 2 small COUNT queries per employee per month unless a
    // conversion is actually due.
    try {
        $auto_lp_targets = [];
        if($emp_filter) {
            $auto_lp_targets[] = $emp_filter;
        } else {
            $auto_lp_emp_rs = mysqli_query($dbConn, "SELECT employee_id FROM hr_employees WHERE status='active' $md_exclude_sql");
            if($auto_lp_emp_rs) while($auto_lp_emp = mysqli_fetch_assoc($auto_lp_emp_rs)) {
                $auto_lp_targets[] = mysqli_real_escape_string($dbConn, $auto_lp_emp['employee_id']);
            }
        }
        foreach($auto_lp_targets as $auto_lp_eid2) {
            abra_apply_late_policy_for_employee($dbConn, $auto_lp_eid2); // real current month
            abra_apply_late_policy_for_range($dbConn, $auto_lp_eid2, $date_from, $date_to); // whatever's being viewed
        }
    } catch (Throwable $e) {
        // Never let the auto-apply step block the rest of the admin dashboard
        // from rendering.
    }

    $where      = ["a.date BETWEEN '$date_from' AND '$date_to'"];
    if($emp_filter) $where[] = "a.employee_id = '$emp_filter'";

    // Get both regular attendance and overrides - HR overrides treated as "present"
    $admin_result = mysqli_query($dbConn, "
        SELECT
            a.id, a.employee_id, a.employee_name, a.date,
            a.check_in_time, a.check_out_time, a.work_hours,
            a.status,
            a.check_in_photo, a.check_out_photo,
            a.check_in_latitude, a.check_in_longitude, a.check_in_location,
            a.check_out_latitude, a.check_out_longitude, a.check_out_location,
            a.daily_salary, 'attendance' as record_type, ao.reason as override_reason, ao.status as override_status, a.late_policy_converted
        FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
        WHERE " . implode(' AND ', $where) . "

        UNION ALL

        SELECT
            NULL as id, e.employee_id, e.name as employee_name, ao.attendance_date as date,
            '09:00:00' as check_in_time, '18:00:00' as check_out_time, '8' as work_hours,
            CASE
                WHEN ao.status IN ('present', 'holiday', 'leave') THEN 'present'
                ELSE ao.status
            END as status,
            NULL as check_in_photo, NULL as check_out_photo,
            NULL as check_in_latitude, NULL as check_in_longitude, NULL as check_in_location,
            NULL as check_out_latitude, NULL as check_out_longitude, NULL as check_out_location,
            NULL as daily_salary, 'override' as record_type, ao.reason as override_reason, ao.status as override_status, 'No' as late_policy_converted
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$date_from' AND '$date_to'
        AND NOT EXISTS (SELECT 1 FROM hr_attendance a2 WHERE a2.employee_id = e.employee_id AND a2.date = ao.attendance_date)
        " . ($emp_filter ? "AND e.employee_id = '$emp_filter'" : "") . "

        ORDER BY date DESC, check_in_time DESC LIMIT 500
    ");

    // FIX: "Half Day Leave" was only ever detected two ways -- (1) status=half_day
    // on the attendance row, which the check-in code only ever sets for a MORNING
    // (half_day_session=first) leave and only at the moment of check-in; or (2)
    // an UNPAID 0.5-day leave, via the lookup just below. A PAID half-day leave
    // for the AFTERNOON session (half_day_session=second) -- where the employee
    // checks in and checks out completely normally, then has the afternoon off --
    // was never detected at all. This lookup now covers every approved half-day
    // leave for the date range, both sessions, paid or unpaid, keyed only by
    // employee+date, so the badge is correct regardless of whether check-in and
    // check-out both happened normally, only one happened, or neither did.
    $unpaid_half_day_dates = [];
    $full_day_leave_dates = [];
    try {
        $uhd_q = mysqli_query($dbConn, "
            SELECT e.employee_id as emp_code, l.start_date, l.end_date, l.leave_type, l.leave_days
            FROM hr_leaves l
            INNER JOIN hr_employees e ON l.employee_id = e.id
            WHERE l.status = 'approved'
            AND '$date_from' <= l.end_date AND '$date_to' >= l.start_date
            " . ($emp_filter ? "AND e.employee_id = '$emp_filter'" : "") . "
        ");
        if($uhd_q) while($uhd_row = mysqli_fetch_assoc($uhd_q)) {
            $remaining = floatval($uhd_row['leave_days']);
            $ltype = $uhd_row['leave_type'];
            
            $dates_to_process = abra_safe_date_range($uhd_row['start_date'], $uhd_row['end_date']);
            
            // Check which days in the range have actual attendance for this employee
            $has_att = [];
            $range_start = $dates_to_process[0] ?? '1970-01-01';
            $range_end = end($dates_to_process) ?? '1970-01-01';
            $att_q = mysqli_query($dbConn, "SELECT date FROM hr_attendance WHERE employee_id='{$uhd_row['emp_code']}' AND date >= '$range_start' AND date <= '$range_end' AND check_in_time IS NOT NULL");
            if ($att_q) while ($ar = mysqli_fetch_assoc($att_q)) $has_att[$ar['date']] = true;

            $fractional = $remaining - floor($remaining);
            $assignments = [];

            // First pass: assign 0.5 to a date WITH attendance if there's a fractional remainder
            if ($fractional == 0.5 && $ltype !== 'half_day') {
                foreach ($dates_to_process as $dt) {
                    if (isset($has_att[$dt]) && $remaining >= 0.5) {
                        $assignments[$dt] = 0.5;
                        $remaining -= 0.5;
                        break;
                    }
                }
            }

            // Second pass: assign remaining days
            foreach ($dates_to_process as $dt) {
                if ($remaining <= 0) break;
                if (isset($assignments[$dt])) continue;
                
                if ($ltype == 'half_day') {
                    $assignments[$dt] = 0.5;
                    $remaining -= 0.5;
                } else {
                    if ($remaining >= 1) {
                        $assignments[$dt] = 1.0;
                        $remaining -= 1.0;
                    } else {
                        $assignments[$dt] = 0.5;
                        $remaining -= 0.5;
                    }
                }
            }

            foreach ($assignments as $dt => $val) {
                if ($val == 0.5) {
                    $unpaid_half_day_dates[$uhd_row['emp_code'] . '|' . $dt] = ($ltype == 'unpaid') ? 'Half Day Unpaid Leave' : 'Half Day Paid Leave';
                } else {
                    $full_day_leave_dates[$uhd_row['emp_code'] . '|' . $dt] = ($ltype == 'unpaid') ? 'Full Day Unpaid Leave' : 'Full Day Paid Leave';
                }
            }
        }
    } catch (Throwable $e) {
        $unpaid_half_day_dates = [];
        $full_day_leave_dates = [];
    }

    $emp_list_query  = mysqli_query($dbConn, "SELECT employee_id, name, id, status FROM hr_employees WHERE 1=1 $md_exclude_sql ORDER BY status ASC, name ASC");

    // ============================================================================
    // ATTENDANCE OVERVIEW TAB DATA
    // All Present/Absent/Half-day/Late records for a selectable date range,
    // shipped to the client as one JSON array so filtering, charts, and
    // drill-down all happen instantly on the same page (no reloads).
    // ============================================================================
    $ovatt_start = isset($_GET['ovatt_start']) && !empty($_GET['ovatt_start']) ? $_GET['ovatt_start'] : date('Y-m-01');
    $ovatt_end   = isset($_GET['ovatt_end'])   && !empty($_GET['ovatt_end'])   ? $_GET['ovatt_end']   : date('Y-m-d');
    $ovatt_start_esc = mysqli_real_escape_string($dbConn, $ovatt_start);
    $ovatt_end_esc   = mysqli_real_escape_string($dbConn, $ovatt_end);

    $ovatt_departments = [];
    $ovatt_positions   = [];
    $ovatt_employees   = [];
    $ovatt_active_employees = [];
    $ovatt_records     = [];
    if($is_super_admin):
    $check_col_hd = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_employees LIKE 'hire_date'");
    $has_joining = ($check_col_hd && mysqli_num_rows($check_col_hd) > 0);
    $emp_sql = "SELECT employee_id, name, department, position, status" . ($has_joining ? ", hire_date" : "") . " FROM hr_employees WHERE 1=1 $md_exclude_sql ORDER BY status ASC, name ASC";
    $ovatt_emp_q = mysqli_query($dbConn, $emp_sql);
    if($ovatt_emp_q) while($e = mysqli_fetch_assoc($ovatt_emp_q)) {
        $d = trim($e['department']) !== '' ? trim($e['department']) : 'Unassigned';
        $p = trim($e['position'] ?? '') !== '' ? trim($e['position']) : 'Unassigned';
        $display_name = $e['name'] . ($e['status'] !== 'active' ? ' (Inactive)' : '');
        $emp_data = ['id' => $e['employee_id'], 'name' => $display_name, 'dept' => $d, 'pos' => $p];
        if($has_joining && !empty($e['hire_date']) && $e['hire_date'] != '0000-00-00') {
            $emp_data['hire_date'] = $e['hire_date'];
        }
        $ovatt_employees[] = $emp_data;
        if($e['status'] === 'active') {
            $ovatt_active_employees[] = $emp_data;
        }
        if(!in_array($d, $ovatt_departments)) $ovatt_departments[] = $d;
        if(!in_array($p, $ovatt_positions)) $ovatt_positions[] = $p;
    }
    sort($ovatt_departments);
    sort($ovatt_positions);

    $ovatt_q = mysqli_query($dbConn, "
        SELECT a.employee_id, a.employee_name, e.department, e.position, a.date, a.status
        FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
        WHERE a.date BETWEEN '$ovatt_start_esc' AND '$ovatt_end_esc' AND ao.id IS NULL

        UNION ALL

        SELECT e.employee_id, e.name as employee_name, e.department, e.position,
               ao.attendance_date as date,
               CASE WHEN ao.status IN ('present','holiday','leave') THEN 'present' ELSE ao.status END as status
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$ovatt_start_esc' AND '$ovatt_end_esc'
    ");
    if($ovatt_q) {
        while($row = mysqli_fetch_assoc($ovatt_q)) {
            $d = trim($row['department']) !== '' ? trim($row['department']) : 'Unassigned';
            $p = trim($row['position'] ?? '') !== '' ? trim($row['position']) : 'Unassigned';
            $ovatt_records[] = [
                'emp'    => $row['employee_id'],
                'name'   => $row['employee_name'],
                'dept'   => $d,
                'pos'    => $p,
                'date'   => $row['date'],
                'status' => $row['status'],
            ];
        }
    }

    // Also add "missing" days as absent -- neither a check-in/out nor an HR
    // override on a working day (non-Sunday) is a plain absence, same rule
    // as the daily tab's Absent card. Bounded to a max 366-day span per
    // employee so a wide/odd date range can never run away.
    $ovatt_covered = [];
    foreach($ovatt_records as $r) {
        if(in_array($r['status'], ['present','late','half_day'])) {
            $ovatt_covered[$r['emp'] . '|' . $r['date']] = true;
        }
    }
    $ovatt_days_safety = 0;
    foreach($ovatt_active_employees as $oe) {
        $emp_start = $ovatt_start_esc;
        if(isset($oe['hire_date']) && strtotime($oe['hire_date']) > strtotime($emp_start)) {
            $emp_start = $oe['hire_date'];
        }
        if(isset($oe['hire_date']) && strtotime($oe['hire_date']) > strtotime($ovatt_end_esc)) {
            continue; // Not hired yet in this period
        }
        $cur = $emp_start;
        while(strtotime($cur) <= strtotime($ovatt_end_esc) && $ovatt_days_safety < 366 * 50) {
            if(date('w', strtotime($cur)) != 0 && !isset($ovatt_covered[$oe['id'] . '|' . $cur])) {
                $ovatt_records[] = [
                    'emp'    => $oe['id'],
                    'name'   => $oe['name'],
                    'dept'   => $oe['dept'],
                    'pos'    => $oe['pos'],
                    'date'   => $cur,
                    'status' => 'absent',
                ];
            }
            $cur = date('Y-m-d', strtotime($cur . ' +1 day'));
            $ovatt_days_safety++;
        }
    }
    endif;


    // ============================================================================
    // ADMIN STATS - FIXED TO RESPECT EMPLOYEE FILTER
    // ============================================================================
    $stats_date_from = isset($_GET['date_from']) && !empty($_GET['date_from']) ? $_GET['date_from'] : $today;
    $stats_date_to   = isset($_GET['date_to'])   && !empty($_GET['date_to'])   ? $_GET['date_to']   : $today;

    $check_col        = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_employees LIKE 'hire_date'");
    $has_joining_date = ($check_col && mysqli_num_rows($check_col) > 0);

    $employee_stats = [
        'total'               => 0,
        'checked_in'          => 0,
        'not_checked_in'      => 0,
        'late_today'          => 0,
        'not_logged_off'      => 0,
        'present_days'        => 0,
        'absent_days'         => 0,
        'half_days'           => 0,
        'not_checked_in_list' => [],
        'checked_in_list'     => [],
        'late_today_list'     => [],
        'not_logged_off_list' => []
    ];

    // Apply employee filter to all statistics queries
    $emp_filter_condition = '';
    if($emp_filter) {
        $emp_filter_condition = " AND a.employee_id = '$emp_filter'";
    }

    // Total - respect employee filter
    if($emp_filter) {
        $r = mysqli_query($dbConn, "SELECT COUNT(*) as total FROM hr_employees WHERE status = 'active' AND employee_id = '$emp_filter' $md_exclude_sql");
    } else {
        $r = mysqli_query($dbConn, "SELECT COUNT(*) as total FROM hr_employees WHERE status = 'active' $md_exclude_sql");
    }
    if($r) $employee_stats['total'] = mysqli_fetch_assoc($r)['total'];

    // Checked in - respect employee filter and include HR overrides
    $checked_in_where = "date BETWEEN '$stats_date_from' AND '$stats_date_to'";
    if($emp_filter) $checked_in_where .= " AND employee_id = '$emp_filter'";
    $override_where = "ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to' AND ao.status IN ('present', 'holiday', 'leave')";
    if($emp_filter) $override_where .= " AND e.employee_id = '$emp_filter'";

    $r = mysqli_query($dbConn, "
        SELECT COUNT(DISTINCT emp_id) as cnt FROM (
            SELECT employee_id as emp_id FROM hr_attendance WHERE $checked_in_where
            UNION
            SELECT e.employee_id as emp_id FROM hr_attendance_overrides ao INNER JOIN hr_employees e ON ao.employee_id = e.id WHERE $override_where
        ) as combined
    ");
    if($r) $employee_stats['checked_in'] = intval(mysqli_fetch_assoc($r)['cnt']);

    // Checked in list - respect employee filter and include HR overrides
    $checked_in_list_where = "a.date BETWEEN '$stats_date_from' AND '$stats_date_to'";
    if($emp_filter) $checked_in_list_where .= " AND a.employee_id = '$emp_filter'";

    // Get regular attendance
    $r = mysqli_query($dbConn, "
        SELECT a.employee_id, a.employee_name, a.date, a.check_in_time, a.check_out_time, a.status,
               e.work_location, e.timings, e.department, 'attendance' as record_type
        FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        WHERE $checked_in_list_where
        ORDER BY a.employee_name ASC, a.date DESC
    ");
    if($r) while($row = mysqli_fetch_assoc($r)) $employee_stats['checked_in_list'][] = $row;

    // Get HR overrides for the list (always include, not just when filtered)
    $override_list_where = "ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to' AND ao.status IN ('present', 'holiday', 'leave')";
    if($emp_filter) $override_list_where .= " AND e.employee_id = '$emp_filter'";
    $override_r = mysqli_query($dbConn, "
        SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date,
               '09:00:00' as check_in_time, '18:00:00' as check_out_time, 'present' as status,
               e.work_location, e.timings, e.department, 'override' as record_type
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE $override_list_where
        ORDER BY e.name ASC, ao.attendance_date DESC
    ");
    if($override_r) while($row = mysqli_fetch_assoc($override_r)) $employee_stats['checked_in_list'][] = $row;

    // Late - respect employee filter
    $late_where = "date BETWEEN '$stats_date_from' AND '$stats_date_to' AND status = 'late'";
    if($emp_filter) $late_where .= " AND employee_id = '$emp_filter'";
    $r = mysqli_query($dbConn, "SELECT COUNT(*) as cnt FROM hr_attendance WHERE $late_where");
    if($r) $employee_stats['late_today'] = mysqli_fetch_assoc($r)['cnt'];

    // Not logged off (past dates only) - respect employee filter, exclude HR overrides
    $not_logged_off_where = "a.date >= '$stats_date_from' AND a.date < '$today' AND a.check_out_time IS NULL";
    if($emp_filter) $not_logged_off_where .= " AND a.employee_id = '$emp_filter'";

    // Only count actual attendance records that are missing checkout, not HR overrides
    $r = mysqli_query($dbConn, "
        SELECT COUNT(*) as cnt FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
        WHERE $not_logged_off_where AND ao.id IS NULL
    ");
    if($r) $employee_stats['not_logged_off'] = mysqli_fetch_assoc($r)['cnt'];

    // ── NOT CHECKED IN ── respect employee filter and include HR overrides
    $status_cond = $emp_filter ? "" : " AND status = 'active'";
    $emp_where_condition = $emp_filter ? " AND employee_id = '$emp_filter'" : "";
    $all_emp_q = mysqli_query($dbConn, "
        SELECT employee_id, name, work_location, timings, department,
               id as emp_db_id, status
               " . ($has_joining_date ? ", hire_date" : "") . "
        FROM hr_employees WHERE 1=1 $status_cond $emp_where_condition $md_exclude_sql ORDER BY name ASC
    ");

    $not_checked_employees = [];
    $all_active_employees_for_stats = [];

    if($all_emp_q) {
        while($emp = mysqli_fetch_assoc($all_emp_q)) {
            $emp_start_date = $stats_date_from;

            if($has_joining_date && !empty($emp['hire_date']) && $emp['hire_date'] != '0000-00-00') {
                if(strtotime($emp['hire_date']) > strtotime($stats_date_to)) continue;
                if(strtotime($emp['hire_date']) > strtotime($stats_date_from))
                    $emp_start_date = $emp['hire_date'];
            }
            
            $all_active_employees_for_stats[] = [
                'employee_id' => $emp['employee_id'],
                'name' => $emp['name'],
                'emp_start_date' => $emp_start_date
            ];

            // Get regular attendance
            $att_q = mysqli_query($dbConn, "
                SELECT DISTINCT date FROM hr_attendance
                WHERE employee_id = '{$emp['employee_id']}'
                AND date BETWEEN '$emp_start_date' AND '$stats_date_to'
            ");
            $attended = [];
            if($att_q) while($a = mysqli_fetch_assoc($att_q)) $attended[] = $a['date'];

            // Get HR overrides
            $override = [];
            if($emp['emp_db_id']) {
                $ov_q = mysqli_query($dbConn, "
                    SELECT DISTINCT attendance_date FROM hr_attendance_overrides
                    WHERE employee_id = {$emp['emp_db_id']}
                    AND attendance_date BETWEEN '$emp_start_date' AND '$stats_date_to'
                    AND status IN ('present', 'holiday', 'leave')
                ");
                if($ov_q) while($ov = mysqli_fetch_assoc($ov_q)) $override[] = $ov['attendance_date'];
            }

            // Combine both regular attendance and HR overrides
            $covered = array_unique(array_merge($attended, $override));

            // Find missing working days (exclude Sundays and official holidays)
            $missing = [];
            $holidays_missed = [];
            $cur     = $emp_start_date;
            while(strtotime($cur) <= strtotime($stats_date_to)) {
                if(!in_array($cur, $covered)) {
                    if(isset($office_holidays[$cur])) {
                        $holidays_missed[] = $cur;
                    } elseif(date('w', strtotime($cur)) != 0) {
                        $missing[] = $cur;
                    }
                }
                $cur = date('Y-m-d', strtotime($cur . ' +1 day'));
            }

            if(count($missing) > 0 || count($holidays_missed) > 0) {
                $emp['missing_dates'] = $missing;
                $emp['holiday_dates'] = $holidays_missed;
                $emp['missing_count'] = count($missing);
                $emp['emp_start_date'] = $emp_start_date;
                $not_checked_employees[] = $emp;
            }
        }
    }

    $employee_stats['not_checked_in']      = count($not_checked_employees);
    $employee_stats['not_checked_in_list'] = $not_checked_employees;

    // When filtering by a specific employee, the dashboard pivots from
    // "Count of Employees" to "Count of Days" for relevance. Update the
    // "Not Checked In" card to show total missing dates instead of just "1" employee.
    if($emp_filter && !empty($not_checked_employees)) {
        $employee_stats['not_checked_in'] = $not_checked_employees[0]['missing_count'];
    }

    // Late list - respect employee filter
    $late_list_where = "a.date BETWEEN '$stats_date_from' AND '$stats_date_to' AND a.status = 'late'";
    if($emp_filter) $late_list_where .= " AND a.employee_id = '$emp_filter'";
    $r = mysqli_query($dbConn, "
        SELECT a.employee_id, a.employee_name, a.check_in_time, a.date, e.work_location, e.timings
        FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        WHERE $late_list_where
        ORDER BY a.date DESC, a.employee_name ASC
    ");
    if($r) while($row = mysqli_fetch_assoc($r)) $employee_stats['late_today_list'][] = $row;

    // Not logged off list - respect employee filter, exclude HR overrides
    $not_logged_off_list_where = "a.date >= '$stats_date_from' AND a.date < '$today' AND a.check_out_time IS NULL";
    if($emp_filter) $not_logged_off_list_where .= " AND a.employee_id = '$emp_filter'";

    $r = mysqli_query($dbConn, "
        SELECT a.employee_id, a.employee_name, a.check_in_time, a.date, e.work_location, e.timings
        FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
        WHERE $not_logged_off_list_where AND ao.id IS NULL
        ORDER BY a.date DESC, a.employee_name ASC
    ");
    if($r) while($row = mysqli_fetch_assoc($r)) $employee_stats['not_logged_off_list'][] = $row;

    // ============================================================================
    // PRESENT / ABSENT / HALF-DAY DAY-COUNTS FOR SELECTED RANGE
    // Shown directly on the main dashboard cards (no click-through required).
    // Combines real check-ins (hr_attendance) with HR overrides
    // (hr_attendance_overrides), de-duplicated by date so a day is never
    // double-counted if both a real record and an override exist.
    // ============================================================================
    $pah_emp_cond    = $emp_filter ? " AND employee_id = '$emp_filter'" : "";
    $pah_emp_cond_ov = $emp_filter ? " AND e.employee_id = '$emp_filter'" : "";

    $present_r = mysqli_query($dbConn, "
        SELECT employee_id, employee_name, date FROM hr_attendance
        WHERE date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND status IN ('present','late')
        $pah_emp_cond

        UNION

        SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND ao.status IN ('present','holiday','leave')
        $pah_emp_cond_ov
        ORDER BY date DESC, employee_name ASC
    ");
    $employee_stats['present_list'] = [];
    if($present_r) while($row = mysqli_fetch_assoc($present_r)) $employee_stats['present_list'][] = $row;
    
    // Inject ALL official office holidays into present_list so every active employee receives attendance credit
    // regardless of whether they worked on that day or missed it (just like hr-payroll does).
    foreach($all_active_employees_for_stats as $emp) {
        foreach($office_holidays as $hdate => $hname) {
            if($hdate >= $emp['emp_start_date'] && $hdate <= $stats_date_to) {
                $employee_stats['present_list'][] = [
                    'employee_id' => $emp['employee_id'],
                    'employee_name' => $emp['name'],
                    'date' => $hdate
                ];
            }
        }
    }
    // present_days / checked_in are finalized below, AFTER the half-day-leave
    // reconciliation, so they don't briefly hold a stale over-counted value.

    $half_r = mysqli_query($dbConn, "
        SELECT employee_id, employee_name, date FROM hr_attendance
        WHERE date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND status = 'half_day'
        $pah_emp_cond

        UNION

        SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND ao.status = 'half_day'
        $pah_emp_cond_ov
        ORDER BY date DESC, employee_name ASC
    ");
    $employee_stats['half_day_list'] = [];
    if($half_r) while($row = mysqli_fetch_assoc($half_r)) $employee_stats['half_day_list'][] = $row;

    // RECONCILE with the hr_leaves-based half-day detection ($unpaid_half_day_dates,
    // built earlier from approved half_day / unpaid-0.5-day leaves -- see the
    // "Half Day Leave" row-badge fix above). Without this, a date that the
    // attendance TABLE correctly labels "Half Day Leave" (because the employee
    // checked in/out normally for a paid afternoon-session leave, so its raw
    // status is still 'present') was being counted as a full Present day here
    // AND excluded from the Half Day card entirely -- Present overstated by
    // one, Half Day undercounted by one, for every such leave. Move any
    // present-list date that's flagged as a half-day leave over to the
    // half-day bucket instead, so the two cards agree with what the table
    // actually shows.
    if(!empty($unpaid_half_day_dates) || !empty($full_day_leave_dates)) {
        $pah_reclassified = [];
        $fdl_reclassified = [];
        foreach($employee_stats['present_list'] as $pl_row) {
            $pl_key = $pl_row['employee_id'] . '|' . $pl_row['date'];
            if(isset($unpaid_half_day_dates[$pl_key])) {
                $pah_reclassified[$pl_key] = true;
                $employee_stats['half_day_list'][] = $pl_row;
            } elseif(isset($full_day_leave_dates[$pl_key]) && $full_day_leave_dates[$pl_key] === 'Unpaid Leave') {
                $fdl_reclassified[$pl_key] = true;
                // Will add to absent_list below
            }
        }
        if(!empty($pah_reclassified) || !empty($fdl_reclassified)) {
            $employee_stats['present_list'] = array_values(array_filter(
                $employee_stats['present_list'],
                function($pl_row) use ($pah_reclassified, $fdl_reclassified) {
                    $pl_key = $pl_row['employee_id'] . '|' . $pl_row['date'];
                    return !isset($pah_reclassified[$pl_key]) && !isset($fdl_reclassified[$pl_key]);
                }
            ));
        }
    }
    $employee_stats['present_days'] = count($employee_stats['present_list']);
    // "checked_in" is finalized further below (present + half-day count,
    // kept as a whole number on purpose -- see the FRACTIONAL HALF-DAY
    // CREDIT section).
    $employee_stats['half_days'] = count($employee_stats['half_day_list']);

    $absent_r = mysqli_query($dbConn, "
        SELECT employee_id, employee_name, date FROM hr_attendance
        WHERE date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND status = 'absent'
        $pah_emp_cond

        UNION

        SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to'
        AND ao.status = 'absent'
        $pah_emp_cond_ov
        ORDER BY date DESC, employee_name ASC
    ");
    $employee_stats['absent_list'] = [];
    if($absent_r) while($row = mysqli_fetch_assoc($absent_r)) $employee_stats['absent_list'][] = $row;

    // Add the reclassified full day unpaid leaves to absent list
    if(!empty($fdl_reclassified)) {
        // We don't have the full original rows here easily, but we just need the count and basic info.
        // We can just construct a dummy row for the absent list since it's mostly just counted.
        foreach($fdl_reclassified as $pl_key => $true) {
            list($eid, $dt) = explode('|', $pl_key);
            $employee_stats['absent_list'][] = [
                'employee_id' => $eid,
                'date' => $dt
            ];
        }
    }

    // Also count days where the employee did NEITHER a check-in NOR a
    // check-out and has NO HR override covering that day -- that's a plain
    // absence even if no explicit 'absent' status row was ever written.
    // (Reuses the same missing-day computation as the "Not Checked In" card.)
    $absent_seen = [];
    foreach($employee_stats['absent_list'] as $a) {
        $absent_seen[$a['employee_id'] . '|' . $a['date']] = true;
    }
    foreach($not_checked_employees as $nce) {
        foreach($nce['missing_dates'] as $md) {
            $key = $nce['employee_id'] . '|' . $md;
            if(!isset($absent_seen[$key])) {
                $employee_stats['absent_list'][] = [
                    'employee_id'   => $nce['employee_id'],
                    'employee_name' => $nce['name'],
                    'date'          => $md,
                ];
                $absent_seen[$key] = true;
            }
        }
    }
    $employee_stats['absent_days'] = count($employee_stats['absent_list']);

    // "Checked In" is a different question from Present/Absent -- it's just
    // "did they physically show up and check in that day", which is always a
    // whole number (either it happened or it didn't, no such thing as half a
    // check-in event). Lock it in as present days + half days (both whole)
    // BEFORE the fractional .5 credit below touches present_days, so it
    // never inherits the .5 that Present/Absent are meant to show.
    if($emp_filter) $employee_stats['checked_in'] = $employee_stats['present_days'] + count($employee_stats['half_day_list']);

    // FRACTIONAL HALF-DAY CREDIT -- standard payroll treatment: a half day is
    // half worked (0.5 toward Present) and half not worked (0.5 toward
    // Absent), not a whole day parked in a separate bucket disconnected from
    // both. "Half Day" stays as-is below (a whole-number count of half-day
    // INSTANCES, useful on its own), but Present/Absent now also carry the
    // .5 so the two headline numbers actually reflect partial attendance
    // instead of silently omitting it. ("Checked In" above is deliberately
    // computed BEFORE this, so it stays a clean whole number.)
    $half_day_credit = count($employee_stats['half_day_list']) * 0.5;
    $employee_stats['present_days'] += $half_day_credit;
    $employee_stats['absent_days']  += $half_day_credit;

}

$my_result    = false;
$my_stats     = ['total'=>0,'present'=>0,'late'=>0,'hours'=>0,'ot_days'=>0];
$today_record = null;
$days_this_month = 0;

$default_start = $is_admin ? date('Y-m-d', strtotime('monday this week')) : date('Y-m-01');
$mf_start = isset($_GET['mf_start']) ? mysqli_real_escape_string($dbConn, $_GET['mf_start']) : $default_start;
$mf_end   = isset($_GET['mf_end'])   ? mysqli_real_escape_string($dbConn, $_GET['mf_end'])   : date('Y-m-d');

$user_assigned_location = '';
$user_work_timings      = '';

if($user_emp_data) {
    $my_id = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $today_q = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id = '$my_id' AND date = '$today'");
    if($today_q) $today_record = mysqli_fetch_assoc($today_q);

    $user_assigned_location = $user_emp_data['work_location'] ?? '';
    $user_work_timings      = $user_emp_data['timings'] ?? '';

    // AUTO-APPLY the late policy across every month spanned by the range this
    // employee is actually looking at. The earlier "current real month" call
    // near the top of the file only ever catches the month that's happening
    // right now -- so a PAST month (e.g. viewing July's history after August
    // has started) never got its 5-lates=1-absent conversion applied and the
    // late days just sat there forever with no action taken. This re-runs
    // the (idempotent) check for each month in [mf_start, mf_end].
    abra_apply_late_policy_for_range($dbConn, $my_id, $mf_start, $mf_end);

    // LATE / SALARY-DEDUCTION SUMMARY FOR THE PERIOD BEING VIEWED --
    // the existing "Late Policy Applied" banner further down only ever
    // reports on the real CURRENT calendar month, so it went blank/silent
    // for anyone looking at a past period (e.g. July, once August started)
    // even though that period clearly had late days and, after the
    // auto-apply above, absences converted from them. This computes the
    // same numbers scoped to mf_start/mf_end so the "My Attendance Records"
    // table below always has a matching answer to "how many days late, how
    // much salary deducted" for whatever range is on screen.
    //
    // IMPORTANT: "late day(s)" below is the count STILL showing status='late'
    // right now -- it's what's LEFT after any conversions already happened,
    // not the original total. Dividing that number by 5 will NOT match the
    // absent count, and that's expected, not a bug: e.g. 17 late days ever
    // recorded -> 3 converted (17/5=3) -> 14 still sitting as "late". The
    // "Absent (this policy)" figure below is read straight off the
    // late_policy_converted marker (set only when THIS policy did the
    // converting), so it's never confused with an absence for some other
    // reason -- previously this just counted every 'absent' row in range,
    // which silently mixed in unrelated absences and made the math look
    // wrong even when it wasn't.
    $mf_range_total_late = 0;
    $mf_range_absent_dates = [];       // from the late policy specifically
    $mf_range_other_absent_count = 0;  // absences NOT from this policy
    try {
        $mf_lm = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT COUNT(*) as cnt FROM hr_attendance
            WHERE employee_id='$my_id' AND status='late'
            AND date BETWEEN '$mf_start' AND '$mf_end'
        "));
        $mf_range_total_late = intval($mf_lm['cnt'] ?? 0);
        $mf_ab_q = mysqli_query($dbConn, "
            SELECT date, late_policy_converted FROM hr_attendance
            WHERE employee_id='$my_id' AND status='absent'
            AND date BETWEEN '$mf_start' AND '$mf_end'
            ORDER BY date ASC
        ");
        if($mf_ab_q) while($mf_ab_row = mysqli_fetch_assoc($mf_ab_q)) {
            if(($mf_ab_row['late_policy_converted'] ?? 'No') === 'Yes') {
                $mf_range_absent_dates[] = $mf_ab_row['date'];
            } else {
                $mf_range_other_absent_count++;
            }
        }
    } catch (Throwable $e) {
        // late_policy_converted column may not exist yet on this install if
        // the earlier migration didn't run -- fall back to "no data" rather
        // than crash the whole attendance page over one banner.
        $mf_range_total_late = 0;
        $mf_range_absent_dates = [];
        $mf_range_other_absent_count = 0;
    }
    $mf_range_absent_count = count($mf_range_absent_dates);
    $mf_range_total_late_ever = $mf_range_total_late + $mf_range_absent_count;

    // Updated stats query - simplified to ensure HR overrides count as "present"
    $stats_q = mysqli_query($dbConn, "
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN status='present' THEN 1 ELSE 0 END) as present,
            SUM(CASE WHEN status='late' OR (status='absent' AND late_policy_converted='Yes') THEN 1 ELSE 0 END) as late,
            SUM(work_hours) as hours
        FROM (
            SELECT a.status, a.late_policy_converted, COALESCE(a.work_hours, 0) as work_hours
            FROM hr_attendance a
            LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
            LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
            WHERE a.employee_id = '$my_id' AND a.date BETWEEN '$mf_start' AND '$mf_end'

            UNION ALL

            SELECT 'present' as status, 'No' as late_policy_converted, 0 as work_hours
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id'
            AND ao.attendance_date BETWEEN '$mf_start' AND '$mf_end'
            AND ao.status IN ('present', 'holiday', 'leave')
            AND NOT EXISTS (SELECT 1 FROM hr_attendance a2 WHERE a2.employee_id = e.employee_id AND a2.date = ao.attendance_date)
        ) combined_records
    ");

    if($stats_q) {
        $s = mysqli_fetch_assoc($stats_q);
        $my_stats['total']   = intval($s['total']);
        $my_stats['present'] = intval($s['present']);
        $my_stats['late']    = intval($s['late']);
        $my_stats['hours']   = floatval($s['hours']);
    }

    // Updated monthly attendance count to include overrides - CORRECTED LOGIC
    $month_att_q = mysqli_query($dbConn, "
        SELECT COUNT(DISTINCT date) as days_this_month
        FROM (
            SELECT date FROM hr_attendance
            WHERE employee_id = '$my_id'
            AND date BETWEEN '$mf_start' AND '$mf_end'
            AND status IN ('present','late','half_day')

            UNION

            SELECT ao.attendance_date as date
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id'
            AND ao.attendance_date BETWEEN '$mf_start' AND '$mf_end'
            AND ao.status IN ('present','holiday','leave')
            AND NOT EXISTS (SELECT 1 FROM hr_attendance a2 WHERE a2.employee_id = e.employee_id AND a2.date = ao.attendance_date)
        ) combined_days
    ");

    if($month_att_q) $days_this_month = intval(mysqli_fetch_assoc($month_att_q)['days_this_month']);
    $my_stats['ot_days'] = max(0, $days_this_month - 26);
    $my_result = mysqli_query($dbConn, "
        SELECT * FROM (
            SELECT
                a.id, a.employee_id, a.employee_name, a.date,
                a.check_in_time, a.check_out_time, a.work_hours,
                a.status,
                a.check_in_photo, a.check_out_photo,
                a.check_in_latitude, a.check_in_longitude, a.check_in_location,
                a.check_out_latitude, a.check_out_longitude, a.check_out_location,
                a.daily_salary, 'attendance' as record_type, ao.reason as override_reason, ao.status as override_status, a.late_policy_converted
            FROM hr_attendance a
            LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
            LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
            WHERE a.employee_id = '$my_id' AND a.date BETWEEN '$mf_start' AND '$mf_end'

            UNION ALL

            SELECT
                NULL as id, e.employee_id, e.name as employee_name, ao.attendance_date as date,
                '09:00:00' as check_in_time, '18:00:00' as check_out_time, '0' as work_hours,
                CASE
                    WHEN ao.status IN ('present', 'holiday', 'leave') THEN 'present'
                    ELSE ao.status
                END as status,
                NULL as check_in_photo, NULL as check_out_photo,
                NULL as check_in_latitude, NULL as check_in_longitude, NULL as check_in_location,
                NULL as check_out_latitude, NULL as check_out_longitude, NULL as check_out_location,
                NULL as daily_salary, 'override' as record_type, ao.reason as override_reason, ao.status as override_status, 'No' as late_policy_converted
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id' AND ao.attendance_date BETWEEN '$mf_start' AND '$mf_end'
            AND NOT EXISTS (SELECT 1 FROM hr_attendance a2 WHERE a2.employee_id = e.employee_id AND a2.date = ao.attendance_date)
        ) combined_records
        ORDER BY date DESC, check_in_time DESC LIMIT 500
    ");

    $my_half_day_dates = [];
    $my_full_day_leaves = [];
    try {
        $my_hd_q = mysqli_query($dbConn, "
            SELECT l.start_date, l.end_date, l.leave_type, l.leave_days
            FROM hr_leaves l
            WHERE l.employee_id = " . intval($user_emp_data['id']) . "
              AND l.status = 'approved'
              AND '$mf_start' <= l.end_date AND '$mf_end' >= l.start_date
        ");
        if($my_hd_q) while($my_hd_row = mysqli_fetch_assoc($my_hd_q)) {
            $remaining = floatval($my_hd_row['leave_days']);
            $ltype = $my_hd_row['leave_type'];
            $dates_to_process = abra_safe_date_range($my_hd_row['start_date'], $my_hd_row['end_date']);
            
            $has_att = [];
            $range_start = $dates_to_process[0] ?? '1970-01-01';
            $range_end = end($dates_to_process) ?? '1970-01-01';
            $uid = intval($user_emp_data['employee_id'] ?? $user_emp_data['id']); // employee code or db id depending on context
            
            // For safety on this query, let's just query by user ID or code
            $uid_db = intval($user_emp_data['id']);
            $att_q = mysqli_query($dbConn, "SELECT date FROM hr_attendance WHERE employee_id IN (SELECT employee_id FROM hr_employees WHERE id=$uid_db) AND date >= '$range_start' AND date <= '$range_end' AND check_in_time IS NOT NULL");
            if ($att_q) while ($ar = mysqli_fetch_assoc($att_q)) $has_att[$ar['date']] = true;

            $fractional = $remaining - floor($remaining);
            $assignments = [];

            if ($fractional == 0.5 && $ltype !== 'half_day') {
                foreach ($dates_to_process as $dt) {
                    if (isset($has_att[$dt]) && $remaining >= 0.5) {
                        $assignments[$dt] = 0.5;
                        $remaining -= 0.5;
                        break;
                    }
                }
            }

            foreach ($dates_to_process as $dt) {
                if ($remaining <= 0) break;
                if (isset($assignments[$dt])) continue;
                
                if ($ltype == 'half_day') {
                    $assignments[$dt] = 0.5;
                    $remaining -= 0.5;
                } else {
                    if ($remaining >= 1) {
                        $assignments[$dt] = 1.0;
                        $remaining -= 1.0;
                    } else {
                        $assignments[$dt] = 0.5;
                        $remaining -= 0.5;
                    }
                }
            }

            foreach ($assignments as $dt => $val) {
                if ($val == 0.5) {
                    $my_half_day_dates[$dt] = ($ltype == 'unpaid') ? 'Half Day Unpaid Leave' : 'Half Day Paid Leave';
                } else {
                    $my_full_day_leaves[$dt] = ($ltype == 'unpaid') ? 'Full Day Unpaid Leave' : 'Full Day Paid Leave';
                }
            }
        }
    } catch (Throwable $e) {
        $my_half_day_dates = [];
        $my_full_day_leaves = [];
    }
    // Replaced entirely above
}

$user_attendance_complete = ($today_record && !empty($today_record['check_out_time']));
$user_kpi_complete = false;
$user_kpi_score    = null;

// Weekly / Monthly mandatory review status -- same due-date rule as the
// Daily KPI check: weekly is due once Saturday of its week arrives,
// monthly is due once the last day of its month arrives. "_due" tracks
// whether the deadline has actually arrived (and the employee had already
// joined by then), so badges/blocking only kick in once truly mandatory.
$user_weekly_due       = false;
$user_weekly_complete  = false;
$user_monthly_due      = false;
$user_monthly_complete = false;

if($is_active_employee) {
    $emp_id_safe = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $kpi_check   = mysqli_query($dbConn, "SELECT id, total_score FROM performance_daily_self WHERE employee_id = '$emp_id_safe' AND review_date = '$today' AND submitted_at IS NOT NULL LIMIT 1");
    if($kpi_check && mysqli_num_rows($kpi_check) > 0) { $user_kpi_complete = true; $user_kpi_score = mysqli_fetch_assoc($kpi_check)['total_score']; }

    $emp_hire_date = (!empty($user_emp_data['hire_date']) && $user_emp_data['hire_date'] != '0000-00-00') ? $user_emp_data['hire_date'] : null;

    $wk_monday   = date('Y-m-d', strtotime('monday this week'));
    $wk_saturday = date('Y-m-d', strtotime($wk_monday . ' +5 days'));
    if($kpi_sim_today >= $wk_saturday && (!$emp_hire_date || strtotime($emp_hire_date) <= strtotime($wk_monday))) {
        $user_weekly_due = true;
        $wk_check = mysqli_query($dbConn, "SELECT id FROM performance_weekly_self WHERE employee_id = '$emp_id_safe' AND week_start_date = '$wk_monday' LIMIT 1");
        if($wk_check && mysqli_num_rows($wk_check) > 0) $user_weekly_complete = true;
    }

    $mn          = date('Y-m');
    $mn_last_day = date('Y-m-t');
    if($kpi_sim_today >= $mn_last_day && (!$emp_hire_date || strtotime($emp_hire_date) <= strtotime($mn . '-01'))) {
        $user_monthly_due = true;
        $mo_check = mysqli_query($dbConn, "SELECT id FROM performance_monthly_self WHERE employee_id = '$emp_id_safe' AND review_month = '$mn' LIMIT 1");
        if($mo_check && mysqli_num_rows($mo_check) > 0) $user_monthly_complete = true;
    }
}

// $is_oje_training / $is_kpi_exempt are now computed once, near the top of
// the file (right after $is_active_employee), so the checkout POST handler
// above can also see them. Reused here for the on-screen KPI badges.
$is_blue_collar = (isset($user_emp_data['worker_category']) && strtolower(trim($user_emp_data['worker_category'])) === 'blue collar');

if($user_emp_data && $is_kpi_exempt) {
    // Inactive employees or OJE/Training employees are exempt from KPIs
    $user_kpi_complete = true;
    $user_weekly_due = false;
    $user_monthly_due = false;
}

// Convenience flags consumed by the checkout-blocking modal / JS below --
// "ok" means either not due yet, or due and already completed.
$user_weekly_ok  = (!$user_weekly_due)  || $user_weekly_complete;
$user_monthly_ok = (!$user_monthly_due) || $user_monthly_complete;

// Monthly Planner requirement -- must be submitted for the UPCOMING month by
// the 29th/30th/31st (whatever the current month's last few days are) of the
// month before it. This used to only ever check "is today's day-of-month
// >= 29" and look at NEXT month's planner -- so the moment the calendar
// rolled over into a new month, day-of-month reset to 1 and the whole check
// silently stopped firing, even if the requirement was never actually met
// (e.g. the 29th/30th/31st fell on a holiday with no checkout that day, so
// the block never got a chance to show, and then it's simply gone once the
// new month starts). Fixed by picking the "due month" instead of gating on
// a fixed day number: on/after the 29th, the due month is next month; any
// earlier day, the due month is THIS month (i.e. the planner that should
// have already been submitted last month). Either way it keeps checking the
// same due month's planner every single day until it's actually submitted,
// so it can never silently clear itself just by the date changing.
$user_planner_ok = true;
if ($is_active_employee && !$is_blue_collar) {
    $due_month_basis = (intval(date('d', strtotime($kpi_sim_today))) >= 29)
        ? strtotime($kpi_sim_today . ' +1 month')
        : strtotime($kpi_sim_today);
    $due_month_start = date('Y-m-01', $due_month_basis);
    $due_month_end   = date('Y-m-t', $due_month_basis);
    $emp_id_safe = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $planner_check = mysqli_query($dbConn, "SELECT id FROM hr_daily_planner WHERE employee_id = '$emp_id_safe' AND plan_date >= '$due_month_start' AND plan_date <= '$due_month_end' LIMIT 1");
    if (!$planner_check || mysqli_num_rows($planner_check) == 0) {
        $user_planner_ok = false;
    }
}

// ============================================================================
// DETERMINE BUTTON STATE
// today_in  = checked in today OR has pending yesterday checkin (midnight case)
// today_out = completed checkout
// ============================================================================
$today_in  = ($today_record && !empty($today_record['check_in_time'])) || ($pending_yesterday_checkin !== null);
$today_out = ($today_record && !empty($today_record['check_out_time'])) ||
             ($pending_yesterday_checkin === null && $today_record && !empty($today_record['check_out_time']));

// If yesterday had a pending checkin and it's now checked out, mark as done
if($pending_yesterday_checkin) {
    $pcheck = mysqli_query($dbConn, "SELECT check_out_time FROM hr_attendance WHERE id = {$pending_yesterday_checkin['id']}");
    if($pcheck) {
        $prow = mysqli_fetch_assoc($pcheck);
        if(!empty($prow['check_out_time'])) {
            $today_in  = true;
            $today_out = true;
            $pending_yesterday_checkin = null;
        }
    }
}

// ============================================================================
// POLICY WARNINGS (from June 2026 onwards)
// 1. Missed logout → half salary cut warning
// 2. Every 6 total late days in a month → 1 day marked absent
// ============================================================================
$policy_start         = '2026-06-01';
$cur_month_start      = date('Y-m-01');
$cur_month_end        = date('Y-m-t');
$missed_logout_dates  = [];
$total_late_month     = 0;   // total late days this month
$lates_per_absent     = 6;   // every 6 lates = 1 absent
$late_policy_absent_dates = [];

if($user_emp_data) {
    $uid = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);

    // Half-day leave dates since policy_start -- an approved half day (either
    // session, paid or unpaid) already means the employee is only on the
    // hook for half the day. If they leave after that approved half and
    // never tap "check out" for the full day, that is NOT a missed logout in
    // the sense this policy is meant to punish (staying late/forgetting to
    // clock out of a FULL shift) -- it's expected. Charging the ½-day missed-
    // logout cut on TOP of an already-approved half day would be double
    // penalizing the same day. So these dates are excluded from the
    // missed-logout scan below.
    $ml_half_day_dates = [];
    try {
        $ml_hd_q = mysqli_query($dbConn, "
            SELECT l.start_date, l.end_date, l.leave_days
            FROM hr_leaves l
            WHERE l.employee_id = " . intval($user_emp_data['id']) . "
              AND l.status = 'approved'
              AND '$policy_start' <= l.end_date AND '$today' >= l.start_date
        ");
        if($ml_hd_q) while($ml_hd_row = mysqli_fetch_assoc($ml_hd_q)) {
            $remaining = floatval($ml_hd_row['leave_days']);
            foreach (abra_safe_date_range($ml_hd_row['start_date'], $ml_hd_row['end_date']) as $ml_hd_date_str) {
                if ($remaining <= 0) break;
                $ml_half_day_dates[$ml_hd_date_str] = true;
                if ($remaining >= 1) {
                    $remaining -= 1;
                } else {
                    $remaining -= 0.5;
                }
            }
        }
    } catch (Throwable $e) {
        $ml_half_day_dates = [];
    }

    // Missed logouts from June onwards (past days, not today), excluding
    // approved half-day leave dates (see above).
    $ml = mysqli_query($dbConn, "
        SELECT date FROM hr_attendance
        WHERE employee_id='$uid'
        AND date >= '$policy_start'
        AND date BETWEEN '$mf_start' AND '$mf_end'
        AND date < '$today'
        AND check_in_time IS NOT NULL
        AND check_out_time IS NULL
        ORDER BY date DESC
    ");
    if($ml) while($r = mysqli_fetch_assoc($ml)) {
        if(isset($ml_half_day_dates[$r['date']])) continue; // exempt: already an approved half day
        $missed_logout_dates[] = $r['date'];
    }

    // Get employee DB ID for joining overrides
    $db_id_for_card = intval($user_emp_data['id'] ?? 0);

    // Total late days in selected range (from June onwards) - excluding HR overrides
    $lm = mysqli_fetch_assoc(mysqli_query($dbConn, "
        SELECT COUNT(DISTINCT a.date) as cnt FROM hr_attendance a
        LEFT JOIN hr_attendance_overrides o ON o.employee_id=$db_id_for_card AND a.date = o.attendance_date
        WHERE a.employee_id='$uid'
        AND (a.status='late' OR (a.status='absent' AND a.late_policy_converted='Yes'))
        AND (a.check_out_time IS NOT NULL AND a.check_out_time != '')
        AND a.date >= '$policy_start'
        AND a.date BETWEEN '$mf_start' AND '$mf_end'
        AND (o.status IS NULL OR o.status NOT IN ('present','holiday','leave'))
    "));
    $total_late_month = intval($lm['cnt'] ?? 0);

    // Fetch actual late dates for banner display
    $late_dates_q = mysqli_query($dbConn, "
        SELECT DISTINCT a.date FROM hr_attendance a
        LEFT JOIN hr_attendance_overrides o ON o.employee_id=$db_id_for_card AND a.date = o.attendance_date
        WHERE a.employee_id='$uid'
        AND (a.status='late' OR (a.status='absent' AND a.late_policy_converted='Yes'))
        AND (a.check_out_time IS NOT NULL AND a.check_out_time != '')
        AND a.date >= '$policy_start'
        AND a.date BETWEEN '$mf_start' AND '$mf_end'
        AND (o.status IS NULL OR o.status NOT IN ('present','holiday','leave'))
        ORDER BY a.date ASC
    ");
    $banner_late_dates = [];
    if($late_dates_q) {
        while($r = mysqli_fetch_assoc($late_dates_q)) {
            $banner_late_dates[] = date('d M', strtotime($r['date']));
        }
    }

    // Absent days due to late policy in selected range
    $ab_q = mysqli_query($dbConn, "
        SELECT date FROM hr_attendance
        WHERE employee_id='$uid'
        AND status='absent'
        AND late_policy_converted='Yes'
        AND date >= '$policy_start'
        AND date BETWEEN '$mf_start' AND '$mf_end'
        ORDER BY date DESC
    ");
    if($ab_q) while($r = mysqli_fetch_assoc($ab_q)) $late_policy_absent_dates[] = $r['date'];
}

?>
<!-- BUILD-MARKER: hr-attendance-list-v8-hotfix-2026-08-01 -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Attendance | <?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'CRM'; ?></title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css"/>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/css/select2.min.css"/>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Poppins',sans-serif;background:#f0f4f8;min-height:100vh;padding:20px 0;}
    .container-fluid{max-width:1600px;margin:0 auto;padding:0 20px;}
    .alert-container{position:fixed;top:20px;right:20px;z-index:9999;min-width:300px;}
    .page-header{background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);padding:20px 30px;border-radius:10px;box-shadow:0 4px 15px rgba(30,58,138,0.3);margin-bottom:20px;display:flex;justify-content:space-between;align-items:center;}
    .page-header h1{color:white;font-weight:600;margin:0;font-size:1.8rem;}
    .header-info{color:rgba(255,255,255,0.9);font-size:0.9rem;margin-top:5px;}
    .header-stats{display:flex;gap:20px;align-items:center;flex-wrap:wrap;}
    .btn-header{padding:12px 24px;border-radius:10px;font-weight:700;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:8px;transition:all 0.3s;text-decoration:none;font-size:14px;color:white;}
    .btn-primary-custom{background:linear-gradient(135deg,#1e3a8a,#1e40af);box-shadow:0 4px 15px rgba(30,58,138,0.3);}
    .btn-primary-custom:hover{transform:translateY(-2px);color:white;text-decoration:none;}
    .btn-success-custom{background:linear-gradient(135deg,#10b981,#059669);}
    .btn-success-custom:hover{transform:translateY(-2px);color:white;text-decoration:none;}
    .btn-danger-custom{background:linear-gradient(135deg,#ef4444,#dc2626);}
    .btn-danger-custom:hover{transform:translateY(-2px);color:white;text-decoration:none;}
    .btn-export-custom{background:linear-gradient(135deg,#3b82f6,#2563eb);}
    .btn-export-custom:hover{transform:translateY(-2px);color:white;text-decoration:none;}
    .stats-row{display:flex;gap:12px;margin-bottom:25px;flex-wrap:nowrap;overflow-x:auto;}
    .stat-card{background:white;border-radius:10px;padding:15px 12px;display:flex;align-items:center;gap:10px;border-left:4px solid;box-shadow:0 2px 10px rgba(0,0,0,0.08);transition:all 0.3s;flex:1;min-width:0;}
    .stat-card:hover{transform:translateY(-3px);}
    .stat-card.clickable{cursor:pointer;}
    .stat-card.blue{border-left-color:#1e40af;}.stat-card.green{border-left-color:#10b981;}.stat-card.orange{border-left-color:#f59e0b;}.stat-card.red{border-left-color:#ef4444;}.stat-card.purple{border-left-color:#8b5cf6;}.stat-card.yellow{border-left-color:#f59e0b;}
    .stat-icon{width:45px;height:45px;border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:20px;color:white;flex-shrink:0;}
    .stat-icon.blue{background:linear-gradient(135deg,#1e3a8a,#1e40af);}.stat-icon.green{background:linear-gradient(135deg,#10b981,#059669);}.stat-icon.orange{background:linear-gradient(135deg,#f59e0b,#d97706);}.stat-icon.red{background:linear-gradient(135deg,#ef4444,#dc2626);}.stat-icon.purple{background:linear-gradient(135deg,#8b5cf6,#7c3aed);}.stat-icon.yellow{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .stat-content h3{margin:0;font-size:24px;font-weight:800;color:#0f172a;}
    .stat-content p{margin:3px 0 0 0;font-size:10px;font-weight:600;color:#64748b;text-transform:uppercase;}
    .filter-bar{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.08);margin-bottom:20px;}
    .filter-bar h5{color:#1e3a8a;font-weight:700;margin-bottom:15px;font-size:16px;}
    .filter-row{display:flex;gap:15px;align-items:center;flex-wrap:wrap;}
    .filter-group{flex:1;min-width:200px;}
    .filter-group label{font-weight:600;color:#475569;font-size:13px;margin-bottom:5px;display:block;}
    .filter-group input,.filter-group select{width:100%;padding:10px 15px;border:2px solid #e2e8f0;border-radius:8px;font-size:14px;font-weight:500;color:#1e293b;}
    .table-container{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.08);margin-bottom:25px;overflow-x:auto;}
    .table-header-actions{display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;flex-wrap:wrap;gap:10px;}
    .table-header-actions h5{color:#1e3a8a;font-weight:700;margin:0;font-size:16px;}
    table.dataTable{width:100%!important;}
    table.dataTable thead th{background:linear-gradient(135deg,#1e3a8a,#1e40af)!important;color:white!important;font-weight:700!important;padding:15px 10px!important;border:1px solid #1e3a8a!important;font-size:13px!important;}
    table.dataTable tbody td{border:1px solid #e2e8f0!important;padding:12px 10px!important;vertical-align:middle!important;font-weight:500!important;color:#1e293b!important;font-size:13px!important;}
    table.dataTable tbody tr{background-color:#ffffff!important;}
    table.dataTable tbody tr:hover{background-color:#f1f5f9!important;}
    .badge{padding:6px 14px;border-radius:20px;font-weight:600;font-size:12px;text-transform:uppercase;}
    .badge-success{background:#d1fae5;color:#065f46;}.badge-warning{background:#fef3c7;color:#92400e;}.badge-danger{background:#fee2e2;color:#991b1b;}.badge-info{background:#dbeafe;color:#1e40af;}.badge-secondary{background:#f1f5f9;color:#475569;}
    .photo-thumb{width:50px;height:50px;object-fit:cover;border-radius:8px;cursor:pointer;border:2px solid #e2e8f0;margin:2px;transition:0.3s;}
    .photo-thumb:hover{transform:scale(1.15);border-color:#1e40af;}
    .modal-content{border-radius:15px;border:none;box-shadow:0 10px 40px rgba(0,0,0,0.2);}
    .modal-header{background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;border-radius:15px 15px 0 0;padding:20px 30px;}
    .modal-body{padding:30px;max-height:70vh;overflow-y:auto;}
    .close{color:white;opacity:0.9;text-shadow:none;font-size:28px;}
    #video{width:100%;max-width:480px;height:auto;min-height:300px;background:#000;border-radius:12px;margin:0 auto;display:block;}
    #canvas{display:none;}
    #preview{display:none;width:100%;max-width:480px;border-radius:12px;border:3px solid #10b981;margin:0 auto;}
    .gps-status{padding:15px;border-radius:10px;margin:15px 0;text-align:center;font-weight:600;}
    .gps-ok{background:#d1fae5;color:#065f46;border:2px solid #10b981;}
    .gps-bad{background:#fee2e2;color:#991b1b;border:2px solid #ef4444;}
    .info-card{background:#f8fafc;padding:15px;border-radius:10px;margin-bottom:15px;border-left:4px solid #1e40af;}

    /* MIDNIGHT CROSSOVER NOTICE */
    .midnight-notice{background:linear-gradient(135deg,#1e3a8a,#7c3aed);color:white;padding:12px 18px;border-radius:10px;margin-bottom:15px;display:flex;align-items:center;gap:12px;font-weight:600;}

    .section-divider{margin:40px 0 25px;text-align:center;position:relative;}
    .section-divider span{background:#f0f4f8;padding:0 20px;color:#64748b;font-weight:700;text-transform:uppercase;letter-spacing:1px;position:relative;z-index:1;}
    .section-divider::before{content:'';position:absolute;top:50%;left:0;right:0;border-top:2px dashed #cbd5e1;z-index:0;}
    .select2-container--default .select2-selection--single{height:44px!important;border:2px solid #e2e8f0!important;border-radius:8px!important;}
    .select2-container--default .select2-selection--single .select2-selection__rendered{line-height:40px!important;padding-left:15px!important;}
    .select2-container--default .select2-selection--single .select2-selection__arrow{height:42px!important;}
    .employee-list{max-height:400px;overflow-y:auto;}
    .employee-item{padding:12px;border-bottom:1px solid #e2e8f0;transition:background 0.2s;}
    .employee-item:hover{background:#f8fafc;}
    .employee-name{font-weight:600;color:#1e293b;}
    .employee-id{font-size:12px;color:#64748b;}
    .employee-info{font-size:11px;color:#94a3b8;margin-top:2px;}
    .ot-info-bar{background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #10b981;border-radius:10px;padding:12px 18px;margin-bottom:20px;display:flex;align-items:center;gap:15px;flex-wrap:wrap;}
    /* Reason column - prevent overflow */
    .dt-reason-col { white-space: normal !important; word-wrap: break-word !important; }
    #adminTable td:nth-child(8),
    #personalTable td:nth-child(7) { white-space: normal !important; word-wrap: break-word !important; min-width: 150px; max-width: 200px; }
    .btn-delete-attendance{background:linear-gradient(135deg,#ef4444,#dc2626);color:white;border:none;padding:8px 12px;border-radius:8px;cursor:pointer;transition:all 0.3s;font-weight:600;display:inline-flex;align-items:center;gap:5px;}
    .btn-delete-attendance:hover{transform:translateY(-2px);box-shadow:0 4px 12px rgba(239,68,68,0.4);}
    @media(max-width:768px){.page-header{flex-direction:column;gap:15px;}.filter-row{flex-direction:column;}.stat-card{min-width:150px;}}
  </style>
</head>
<body>

<div class="alert-container">
  <?php if($kpi_test_mode_active): ?>
    <div class="alert alert-warning fade show" style="border:2px solid #f59e0b;font-weight:700;">
      <i class="fas fa-flask"></i> TEST MODE: Weekly/Monthly deadline checks are simulating "today" as
      <?php echo date('d M Y (D)', strtotime($kpi_sim_today)); ?>. Real check-in/out timestamps are unaffected.
      <a href="<?php echo strtok($_SERVER['REQUEST_URI'], '?'); ?>" style="color:#92400e;text-decoration:underline;margin-left:8px;">Exit test mode</a>
    </div>
  <?php endif; ?>
  <?php if(!empty($success_message)): ?>
    <div class="alert alert-success alert-dismissible fade show"><strong><i class="fas fa-check-circle"></i></strong> <?php echo $success_message; ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
  <?php endif; ?>
  <?php if(!empty($error_message)): ?>
    <div class="alert alert-danger alert-dismissible fade show"><strong><i class="fas fa-exclamation-triangle"></i> Error!</strong> <?php echo $error_message; ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
  <?php endif; ?>
</div>

<div class="container-fluid">

  <div class="page-header">
    <div>
      <h1><i class="fas fa-clock"></i> Attendance</h1>
      <div class="header-info"><?php echo date('l, F d, Y'); ?></div>
      <?php if($user_emp_data): ?>
      <div class="header-info" style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;">
        <?php if($user_kpi_complete): ?>
          <span style="background:#d1fae5;color:#065f46;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-check-circle"></i> Daily KPI: Completed <?php echo ($user_kpi_score >= 0) ? '('.$user_kpi_score.'%)' : '(On Leave)'; ?></span>
        <?php else: ?>
          <span style="background:#fee2e2;color:#991b1b;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-exclamation-circle"></i> Daily KPI: Pending</span>
        <?php endif; ?>
        <?php if($user_weekly_due): ?>
          <?php if($user_weekly_complete): ?>
            <span style="background:#d1fae5;color:#065f46;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-check-circle"></i> Weekly KPI: Completed</span>
          <?php else: ?>
            <span style="background:#fee2e2;color:#991b1b;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-exclamation-circle"></i> Weekly KPI: Pending</span>
          <?php endif; ?>
        <?php endif; ?>
        <?php if($user_monthly_due): ?>
          <?php if($user_monthly_complete): ?>
            <span style="background:#d1fae5;color:#065f46;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-check-circle"></i> Monthly KPI: Completed</span>
          <?php else: ?>
            <span style="background:#fee2e2;color:#991b1b;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-exclamation-circle"></i> Monthly KPI: Pending</span>
          <?php endif; ?>
        <?php endif; ?>
        <?php if($my_stats['ot_days'] > 0): ?>
          <span style="background:#fffbeb;color:#92400e;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;border:1px solid #f59e0b;"><i class="fas fa-star"></i> OT Days This Month: <?php echo $my_stats['ot_days']; ?></span>
        <?php endif; ?>
        <?php if($pending_yesterday_checkin): ?>
          <span style="background:#7c3aed;color:white;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;"><i class="fas fa-moon"></i> Night Shift: Checkout Pending from <?php echo date('M d', strtotime($yesterday)); ?></span>
        <?php endif; ?>
      </div>
      <?php endif; ?>
    </div>
    <div class="header-stats">
      <?php if($is_super_admin || $is_keerti): ?>
      <button type="button" class="btn-header" style="background:linear-gradient(135deg,#4f46e5,#4338ca);color:white;border:none;padding:8px 16px;border-radius:8px;font-weight:700;cursor:pointer;margin-right:8px;font-size:13px;display:inline-flex;align-items:center;gap:6px;" onclick="openAccessListModal()" title="Manage employee access to Admin Attendance">
        <i class="fas fa-user-shield"></i> Attendance Access List
      </button>
      <?php endif; ?>
      <?php if($is_active_employee): ?>
      <button class="btn-header btn-success-custom" onclick="handleMarkAttendance()">
        <i class="fas fa-plus-circle"></i> Mark Attendance
      </button>
      <?php endif; ?>
      
    </div>
  </div>

  <?php if($is_admin): ?>
  <?php if($is_super_admin): ?>
  <div class="atn-tabs" style="display:flex;gap:10px;margin-bottom:18px;">
    <button type="button" class="atn-tab-btn" id="atnTabBtnDaily" onclick="switchAtnTab('daily')" style="padding:10px 22px;border-radius:8px;border:none;font-weight:700;cursor:pointer;<?php echo $atn_tab === 'daily' ? 'background:#1e40af;color:white;' : 'background:#e2e8f0;color:#334155;'; ?>"><i class="fas fa-calendar-day"></i> Daily Attendance</button>
    <button type="button" class="atn-tab-btn" id="atnTabBtnOverview" onclick="switchAtnTab('overview')" style="padding:10px 22px;border-radius:8px;border:none;font-weight:700;cursor:pointer;<?php echo $atn_tab === 'daily' ? 'background:#e2e8f0;color:#334155;' : 'background:#1e40af;color:white;'; ?>"><i class="fas fa-chart-pie"></i> Attendance Overview</button>
  </div>
  <?php endif; ?>

  <div id="atnDailyTab" style="<?php echo ($is_super_admin && $atn_tab !== 'daily') ? 'display:none;' : ''; ?>">
  <div class="stats-row">
    <div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-users"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['total']); ?></h3><p>Total Employees</p></div></div>
    <div class="stat-card green clickable" onclick="showPresentDays()"><div class="stat-icon green"><i class="fas fa-calendar-check"></i></div><div class="stat-content"><h3><?php echo abra_fmt_days($employee_stats['present_days']); ?></h3><p>Present</p></div></div>
    <div class="stat-card red clickable" onclick="showAbsentDays()"><div class="stat-icon red"><i class="fas fa-calendar-times"></i></div><div class="stat-content"><h3><?php echo abra_fmt_days($employee_stats['absent_days']); ?></h3><p>Absent</p></div></div>
    <div class="stat-card yellow clickable" onclick="showHalfDays()"><div class="stat-icon yellow"><i class="fas fa-adjust"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['half_days']); ?></h3><p>Half Day</p></div></div>
    <div class="stat-card green clickable" onclick="showCheckedIn()"><div class="stat-icon green"><i class="fas fa-user-check"></i></div><div class="stat-content"><h3><?php echo abra_fmt_days($employee_stats['checked_in']); ?></h3><p>Checked In</p></div></div>
    <div class="stat-card orange clickable" onclick="showLateEmployees()"><div class="stat-icon orange"><i class="fas fa-clock"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['late_today']); ?></h3><p>Late</p></div></div>
    <div class="stat-card red clickable" onclick="showNotCheckedIn()"><div class="stat-icon red"><i class="fas fa-user-times"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['not_checked_in']); ?></h3><p>Not Checked In</p></div></div>
    <div class="stat-card blue clickable" onclick="showNotLoggedOff()"><div class="stat-icon blue"><i class="fas fa-sign-out-alt"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['not_logged_off']); ?></h3><p>Not Logged Off</p></div></div>
    <div class="stat-card clickable" style="border-left-color:#dc2626;cursor:pointer;" onclick="checkLatePolicy()">
      <div class="stat-icon" style="background:linear-gradient(135deg,#dc2626,#b91c1c);color:white;border-radius:10px;padding:10px;"><i class="fas fa-user-slash"></i></div>
      <div class="stat-content"><h3 id="late-policy-count" style="color:#dc2626;">...</h3><p>6-Day Late Policy <span id="late-policy-badge" class="badge badge-danger" style="display:none;">!</span></p></div>
    </div>
  </div>
  <form method="GET">
    <input type="hidden" name="atn_tab" value="daily">
    <div class="filter-bar">
      <h5><i class="fas fa-filter"></i> Filter Records</h5>
      <div class="filter-row">
        <div class="filter-group"><label>From Date</label><input type="date" name="date_from" value="<?php echo htmlspecialchars($date_from); ?>"></div>
        <div class="filter-group"><label>To Date</label><input type="date" name="date_to" value="<?php echo htmlspecialchars($date_to); ?>"></div>
        <div class="filter-group">
          <label>Employee</label>
          <select name="employee" class="select2">
            <option value="">All Employees</option>
            <?php if(isset($emp_list_query)): while($emp = mysqli_fetch_assoc($emp_list_query)): ?>
              <option value="<?php echo htmlspecialchars($emp['employee_id']); ?>" <?php echo (isset($emp_filter) && $emp_filter == $emp['employee_id']) ? 'selected' : ''; ?>><?php echo htmlspecialchars($emp['name']); ?><?php echo ($emp['status'] !== 'active') ? ' (Inactive)' : ''; ?></option>
            <?php endwhile; endif; ?>
          </select>
        </div>
        <div style="margin-top:22px;"><button type="submit" class="btn-header btn-primary-custom"><i class="fas fa-search"></i> Apply</button></div>
      </div>
    </div>
  </form>

  <?php
  // Build combined array of actual attendance and missing days for the main table
  $admin_table_records = [];
  if($admin_result && mysqli_num_rows($admin_result) > 0) {
      mysqli_data_seek($admin_result, 0);
      while($row = mysqli_fetch_assoc($admin_result)) {
          $admin_table_records[] = $row;
      }
  }
  // Inject missing days as "Absent" so they appear in the main data table
  if(!empty($employee_stats['not_checked_in_list'])) {
      foreach($employee_stats['not_checked_in_list'] as $emp) {
          foreach($emp['missing_dates'] as $md) {
              $admin_table_records[] = [
                  'id' => null,
                  'employee_id' => $emp['employee_id'],
                  'employee_name' => $emp['name'],
                  'date' => $md,
                  'check_in_time' => null,
                  'check_out_time' => null,
                  'work_hours' => 0,
                  'status' => 'absent',
                  'check_in_photo' => null,
                  'check_out_photo' => null,
                  'check_in_location' => '',
                  'check_out_location' => '',
                  'record_type' => 'missing',
                  'override_reason' => null,
                  'override_status' => null,
                  'late_policy_converted' => 'No'
              ];
          }
          if(!empty($emp['holiday_dates'])) {
              foreach($emp['holiday_dates'] as $hd) {
                  $admin_table_records[] = [
                      'id' => null,
                      'employee_id' => $emp['employee_id'],
                      'employee_name' => $emp['name'],
                      'date' => $hd,
                      'check_in_time' => null,
                      'check_out_time' => null,
                      'work_hours' => 0,
                      'status' => 'holiday',
                      'check_in_photo' => null,
                      'check_out_photo' => null,
                      'check_in_location' => '',
                      'check_out_location' => '',
                      'record_type' => 'holiday',
                      'override_reason' => $office_holidays[$hd] ?? 'Office Holiday',
                      'override_status' => 'holiday',
                      'late_policy_converted' => 'No'
                  ];
              }
          }
      }
  }
  // Sort combined records by date DESC, then name ASC
  usort($admin_table_records, function($a, $b) {
      if ($a['date'] == $b['date']) return strcmp($a['employee_name'], $b['employee_name']);
      return ($a['date'] < $b['date']) ? 1 : -1;
  });
  ?>

  <?php if(!empty($admin_table_records)): ?>
  <div class="table-container">
    <div class="table-header-actions">
      <h5><i class="fas fa-table"></i> All Employee Attendance</h5>
      <a href="?action=export&export_type=admin&date_from=<?php echo urlencode($date_from); ?>&date_to=<?php echo urlencode($date_to); ?>&employee=<?php echo urlencode(isset($emp_filter)?$emp_filter:''); ?>" class="btn-header btn-export-custom"><i class="fas fa-download"></i> Export CSV</a>
    </div>
    <table id="adminTable" class="display nowrap" style="width:100%">
      <thead><tr><th>Date</th><th>Day</th><th>Employee</th><th>Check In</th><th>Check Out</th><th>Work Hrs</th><th>Status</th><th>Reason</th><th>Photos</th><th>Actions</th></tr></thead>
      <tbody>
        <?php foreach($admin_table_records as $row):
            $is_half_day_leave = (isset($row['override_status']) && $row['override_status'] === 'half_day')
                || isset($unpaid_half_day_dates[$row['employee_id'] . '|' . $row['date']]);

            $half_day_label = 'Half Day';
            if(isset($unpaid_half_day_dates[$row['employee_id'] . '|' . $row['date']])) {
                $half_day_label = $unpaid_half_day_dates[$row['employee_id'] . '|' . $row['date']];
            } elseif(isset($row['override_status']) && $row['override_status'] === 'half_day') {
                $half_day_label = 'Half Day (HR)';
            }

            $is_full_day_leave = isset($full_day_leave_dates[$row['employee_id'] . '|' . $row['date']]);
            $leave_type_label = $is_full_day_leave ? $full_day_leave_dates[$row['employee_id'] . '|' . $row['date']] : '';
        ?>
        <tr <?php echo (isset($row['record_type']) && $row['record_type'] == 'override') ? 'style="background-color: #f0f9ff; border-left: 4px solid #3b82f6;"' : ''; ?>>
          <td><?php echo date('M d, Y', strtotime($row['date'])); ?></td>
          <td><?php echo date('l', strtotime($row['date'])); ?></td>
          <td>
            <div style="font-weight:700"><?php echo htmlspecialchars($row['employee_name']); ?></div>
            <div style="font-size:11px;color:#64748b"><?php echo htmlspecialchars($row['employee_id']); ?></div>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <?php if(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto:') === 0): ?>
                <div style="font-size:10px;color:#059669;font-weight:600;"><i class="fas fa-user-edit"></i> Administration Override</div>
              <?php else: ?>
                <div style="font-size:10px;color:#3b82f6;font-weight:600;"><i class="fas fa-user-edit"></i> HR Override</div>
              <?php endif; ?>
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">Override</span>
            <?php elseif(isset($row['record_type']) && $row['record_type'] == 'missing'): ?>
              <?php if(isset($is_full_day_leave) && $is_full_day_leave): ?>
                <span style="color:#3b82f6;font-weight:bold;">—</span>
              <?php else: ?>
                <span style="color:#dc2626;font-weight:bold;">Not Checked In</span>
              <?php endif; ?>
            <?php elseif(isset($row['record_type']) && $row['record_type'] == 'holiday'): ?>
              <span style="color:#0ea5e9;font-weight:bold;">Holiday</span>
            <?php else: ?>
              <?php echo date('h:i A', strtotime($row['check_in_time'])); ?>
              <!-- Removed duplicate late text -->
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">Override</span>
            <?php elseif(isset($row['record_type']) && $row['record_type'] == 'missing'): ?>
              <span style="color:#94a3b8;">—</span>
            <?php elseif(isset($row['record_type']) && $row['record_type'] == 'holiday'): ?>
              <span style="color:#94a3b8;">—</span>
            <?php else: ?>
              <?php if($row['check_out_time']): ?>
                <?php echo date('h:i A', strtotime($row['check_out_time'])); ?>
                <?php if(substr($row['check_out_time'],0,5) < substr($row['check_in_time'],0,5)): ?>
                  <span style="font-size:10px;color:#7c3aed;font-weight:700;display:block;"><i class="fas fa-moon"></i> Next Day Checkout</span>
                <?php endif; ?>
              <?php else: ?>—<?php endif; ?>
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && ($row['record_type'] == 'override' || $row['record_type'] == 'missing' || $row['record_type'] == 'holiday')): ?>
              <span style="color:#64748b;font-style:italic;">—</span>
            <?php else: ?>
              <?php
                if($row['work_hours']) {
                    $wh = floatval($row['work_hours']);
                    if($is_half_day_leave) {
                        // Approved half-day leave for this date -- shorter hours are expected, not a shortfall.
                        echo '<span style="color:#0891b2;font-weight:700;">' . $row['work_hours'] . ' hr</span>';
                    } else {
                        $wh_color = ($wh < 8) ? '#dc2626' : '#059669';
                        echo '<span style="color:' . $wh_color . ';font-weight:700;">' . $row['work_hours'] . ' hr</span>';
                    }
                } else {
                    echo '—';
                }
              ?>
            <?php endif; ?>
          </td>
          <td>
            <?php $missed_logout = (!empty($row['check_in_time']) && empty($row['check_out_time']) && $row['date'] < date('Y-m-d') && (!isset($row['record_type']) || ($row['record_type'] != 'override' && $row['record_type'] != 'missing')) && (!isset($row['override_status']) || !in_array($row['override_status'], ['leave', 'half_day', 'holiday'])) && !$is_half_day_leave && !(isset($is_full_day_leave) && $is_full_day_leave)); ?>
            <span class="badge badge-<?php
              echo $is_half_day_leave?'info':(
                  (isset($is_full_day_leave) && $is_full_day_leave)?'primary':(
                  ($row['status']=='present'?'success':
                  ($row['status']=='late'?'warning':'danger'))));
            ?>">
              <?php
              if(isset($row['record_type']) && $row['record_type'] == 'override') {
                $lbl = isset($row['override_status']) ? ucfirst($row['override_status']) : ucfirst($row['status']);
                if($lbl == 'Half_day') $lbl = 'Half Day';
                if(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto: Excused') !== false) {
                  echo 'Late (Excused)';
                } elseif(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto:') === 0) {
                  if ($is_half_day_leave) {
                      echo $half_day_label;
                  } elseif (isset($is_full_day_leave) && $is_full_day_leave) {
                      echo $leave_type_label;
                  } else {
                      echo $lbl . ' (Administration)';
                  }
                } else {
                  echo $lbl . ' (HR)';
                }
              } elseif(isset($row['record_type']) && $row['record_type'] == 'missing') {
                if(isset($is_full_day_leave) && $is_full_day_leave) {
                    echo $leave_type_label;
                } else {
                    echo 'Missing';
                }
              } elseif(isset($row['record_type']) && $row['record_type'] == 'holiday') {
                echo 'HOLIDAY';
              } elseif($is_half_day_leave) {
                echo $half_day_label;
              } elseif(isset($is_full_day_leave) && $is_full_day_leave) {
                echo $leave_type_label;
              } else {
                if($row['status'] == 'absent' && isset($row['late_policy_converted']) && $row['late_policy_converted'] == 'Yes') {
                    echo 'Late (Absent)';
                } elseif(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto: Excused') !== false) {
                    echo 'Late (Excused)';
                } else {
                    $base = ucfirst($row['status']);
                    if(isset($row['check_in_location']) && stripos($row['check_in_location'], 'Force In by HR') !== false) {
                        $base .= ' (Force In)';
                    } elseif(isset($row['check_out_location']) && stripos($row['check_out_location'], 'Force Out by HR') !== false) {
                        $base .= ' (Force Out)';
                    }
                    echo $base;
                }
              }
              ?>
            </span>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <?php if(!empty($row['override_reason'])): ?>
                <?php
                $reason_text = htmlspecialchars($row['override_reason']);
                $reason_id   = 'reason_' . $row['id'] . '_' . md5($row['date'] . $row['employee_id']);
                ?>
                <div style="color:#1e40af;font-size:11px;width:150px;white-space:normal;word-wrap:break-word;line-height:1.4;">
                  <i class="fas fa-info-circle" style="flex-shrink:0;"></i>
                  <span id="short_<?php echo $reason_id; ?>" style="font-style:italic;">
                    <?php echo mb_substr($reason_text, 0, 50) . (mb_strlen($reason_text) > 50 ? '...' : ''); ?>
                  </span>
                  <span id="full_<?php echo $reason_id; ?>" style="font-style:italic;display:none;">
                    <?php echo $reason_text; ?>
                  </span>
                  <?php if(mb_strlen($row['override_reason']) > 50): ?>
                  <br><a href="javascript:void(0)" onclick="toggleReason('<?php echo $reason_id; ?>')" id="toggle_<?php echo $reason_id; ?>"
                     style="color:#7c3aed;font-weight:700;font-style:normal;font-size:11px;">Read more</a>
                  <?php endif; ?>
                </div>
              <?php else: ?>
                <span style="color:#94a3b8;font-style:italic;font-size:12px;">—</span>
              <?php endif; ?>
            <?php elseif(isset($row['record_type']) && $row['record_type'] == 'missing'): ?>
              <?php if(isset($is_full_day_leave) && $is_full_day_leave): ?>
                <span style="color:#64748b;font-style:italic;font-size:12px;">Auto: Approved Leave</span>
              <?php else: ?>
                <span style="color:#94a3b8;font-size:12px;">—</span>
              <?php endif; ?>
            <?php else: ?>
              <?php
                $reasons = [];
                if($missed_logout) {
                    $reasons[] = '<span style="color:#d97706;font-size:11px;font-weight:600;white-space:nowrap;"><i class="fas fa-exclamation-triangle"></i> No Log Off Policy</span>';
                } elseif(isset($row['late_policy_converted']) && $row['late_policy_converted'] === 'Yes') {
                    $reasons[] = '<span style="color:#dc2626;font-size:11px;font-weight:600;white-space:nowrap;"><i class="fas fa-exclamation-triangle"></i> Converted from Late (Policy)</span>';
                }
                if(count($reasons) > 0) {
                    echo implode('<br>', $reasons);
                } else {
                    echo '<span style="color:#94a3b8;font-size:12px;">—</span>';
                }
              ?>
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && ($row['record_type'] == 'override' || $row['record_type'] == 'missing' || $row['record_type'] == 'holiday')): ?>
              <span style="color:#64748b;font-style:italic;">—</span>
            <?php else: ?>
              <?php if($row['check_in_photo']): ?><img src="<?php echo str_replace('/dashboard/uploads/','/hrm/uploads/',$row['check_in_photo']); ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
              <?php if($row['check_out_photo']): ?><img src="<?php echo str_replace('/dashboard/uploads/','/hrm/uploads/',$row['check_out_photo']); ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            <?php endif; ?>
          </td>
          <td>
            <button class="btn-delete-attendance" onclick="deleteAttendance('<?php echo $row['employee_id']; ?>', '<?php echo $row['date']; ?>', '<?php echo htmlspecialchars(addslashes($row['employee_name'])); ?>')" title="Delete Attendance">
                <i class="fas fa-trash-alt"></i>
            </button>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php else: ?>
  <div style="text-align:center;padding:60px 20px;background:#f1f5f9;border-radius:12px;margin:20px 0;"><i class="fas fa-calendar-times" style="font-size:64px;color:#94a3b8;margin-bottom:20px;display:block;"></i><h4 style="color:#475569">No Attendance Records Found</h4></div>
  <?php endif; ?>
  </div><!-- /atnDailyTab -->

  <?php if($is_super_admin): ?>
  <div id="atnOverviewTab">
    <form method="GET" style="margin-bottom:18px;">
      <input type="hidden" name="atn_tab" value="overview">
      <div class="filter-bar">
        <h5><i class="fas fa-filter"></i> Overview Filters</h5>
        <div class="filter-row">
          <div class="filter-group"><label>From Date</label><input type="date" name="ovatt_start" value="<?php echo htmlspecialchars($ovatt_start); ?>"></div>
          <div class="filter-group"><label>To Date</label><input type="date" name="ovatt_end" value="<?php echo htmlspecialchars($ovatt_end); ?>"></div>
          <div class="filter-group">
            <label>Department</label>
            <select id="atnDeptFilter" onchange="renderAtnOverview()">
              <option value="">All Departments</option>
              <?php foreach($ovatt_departments as $d): ?>
                <option value="<?php echo htmlspecialchars($d); ?>"><?php echo htmlspecialchars($d); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="filter-group">
            <label>Position</label>
            <select id="atnPosFilter" onchange="renderAtnOverview()">
              <option value="">All Positions</option>
              <?php foreach($ovatt_positions as $p): ?>
                <option value="<?php echo htmlspecialchars($p); ?>"><?php echo htmlspecialchars($p); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="filter-group">
            <label>Employee</label>
            <select id="atnEmpFilter" onchange="renderAtnOverview()">
              <option value="">All Employees</option>
              <?php foreach($ovatt_employees as $emp): ?>
                <option value="<?php echo htmlspecialchars($emp['id']); ?>"><?php echo htmlspecialchars($emp['name']); ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div style="margin-top:22px;"><button type="submit" class="btn-header btn-primary-custom"><i class="fas fa-search"></i> Apply Date Range</button></div>
        </div>
      </div>
    </form>

    <div class="stats-row" id="atnOverviewCards"></div>

    <div class="table-container">
      <h5><i class="fas fa-chart-pie"></i> Status Distribution <span style="font-weight:400;font-size:12px;color:#64748b;">(click a slice for details)</span></h5>
      <div style="max-width:280px;height:240px;margin:0 auto;">
        <canvas id="atnDistChart"></canvas>
      </div>
    </div>

    <div class="table-container">
      <h5><i class="fas fa-chart-line"></i> Daily Trend <span style="font-weight:400;font-size:12px;color:#64748b;">(click a point for that day's details)</span></h5>
      <canvas id="atnTrendChart" height="90"></canvas>
    </div>

    <div class="table-container">
      <h5><i class="fas fa-building"></i> Department Breakdown <span style="font-weight:400;font-size:12px;color:#64748b;">(click a bar for details)</span></h5>
      <canvas id="atnDeptChart" height="100"></canvas>
    </div>

    <div class="table-container">
      <h5><i class="fas fa-id-badge"></i> Position Breakdown <span style="font-weight:400;font-size:12px;color:#64748b;">(click a bar for details)</span></h5>
      <canvas id="atnPosChart" height="100"></canvas>
    </div>

    <div class="table-container">
      <div class="table-header-actions"><h5><i class="fas fa-users"></i> Employee Leaderboard <span style="font-weight:400;font-size:12px;color:#64748b;">(click a row for details)</span></h5></div>
      <table id="atnEmpTable" class="display nowrap" style="width:100%">
        <thead><tr><th>Employee</th><th>Department</th><th>Position</th><th>Present</th><th>Absent</th><th>Half Day</th><th>Late</th></tr></thead>
        <tbody id="atnEmpTableBody"></tbody>
      </table>
    </div>
  </div><!-- /atnOverviewTab -->
  <?php endif; ?>

  <!-- ATTENDANCE OVERVIEW DRILL-DOWN MODAL -->
  <div id="atnDetailModalBackdrop" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.55);z-index:9999;" onclick="if(event.target===this) closeAtnDetail();">
    <div style="background:white;max-width:700px;margin:60px auto;border-radius:12px;max-height:78vh;overflow-y:auto;">
      <div style="padding:16px 20px;border-bottom:2px solid #e2e8f0;display:flex;justify-content:space-between;align-items:center;position:sticky;top:0;background:white;border-radius:12px 12px 0 0;">
        <h5 id="atnDetailTitle" style="margin:0;"></h5>
        <button onclick="closeAtnDetail()" style="border:none;background:none;font-size:22px;cursor:pointer;line-height:1;">&times;</button>
      </div>
      <div id="atnDetailBody" style="padding:20px;"></div>
    </div>
  </div>

  <?php endif; ?>

  <!-- PERSONAL ATTENDANCE SECTION - shown for logged-in employees; hidden for
       the super admin (Abishek) since it's redundant with the Overview tab
       and personal attendance is available to him elsewhere. -->
  <?php if($user_emp_data && !$is_super_admin): ?>
  <div class="section-divider"><span>My Personal Attendance</span></div>

  <div class="stats-row">
    <div class="stat-card blue"><div class="stat-icon blue"><i class="fas fa-calendar-alt"></i></div><div class="stat-content"><h3><?php echo $days_this_month; ?></h3><p>Days This Month</p></div></div>
    <div class="stat-card green"><div class="stat-icon green"><i class="fas fa-check-circle"></i></div><div class="stat-content"><h3><?php echo number_format($my_stats['present']); ?></h3><p>On Time</p></div></div>
    <div class="stat-card orange"><div class="stat-icon orange"><i class="fas fa-clock"></i></div><div class="stat-content"><h3><?php echo number_format($my_stats['late']); ?></h3><p>Late</p></div></div>
    <div class="stat-card yellow"><div class="stat-icon yellow"><i class="fas fa-star"></i></div><div class="stat-content"><h3><?php echo $my_stats['ot_days']; ?></h3><p>OT Days (Month)</p></div></div>
    <div class="stat-card red"><div class="stat-icon red"><i class="fas fa-hourglass-half"></i></div><div class="stat-content"><h3><?php echo number_format($my_stats['hours'],1); ?></h3><p>Total Hours</p></div></div>
  </div>

  <!-- OT Info Bar -->
  <?php if($days_this_month > 0): ?>
  <div class="ot-info-bar">
    <div>
      <strong style="color:#065f46;font-size:14px;"><i class="fas fa-info-circle"></i> This Month Summary</strong>
    </div>
    <div style="font-size:13px;color:#047857;">
      Days Attended: <strong><?php echo $days_this_month; ?></strong>
      &nbsp;|&nbsp; Base: <strong>26</strong>
      &nbsp;|&nbsp; Absent: <strong style="color:#dc2626;"><?php echo max(0, 26 - $days_this_month); ?></strong>
      &nbsp;|&nbsp; OT Days: <strong style="color:#d97706;"><?php echo max(0, $days_this_month - 26); ?></strong>
    </div>
  </div>
  <?php endif; ?>

  <?php
  $absents_triggered    = intval($total_late_month / $lates_per_absent);
  $lates_in_cur_cycle  = $total_late_month % $lates_per_absent; // position within current 6-block
  $lates_remaining_to_next = ($lates_in_cur_cycle === 0 && $total_late_month > 0)
                              ? $lates_per_absent          // just completed a cycle, 6 more until next
                              : $lates_per_absent - $lates_in_cur_cycle;
  $progress_pct = ($lates_in_cur_cycle === 0 && $total_late_month > 0)
                  ? 0   // just reset after completing a cycle
                  : round($lates_in_cur_cycle / $lates_per_absent * 100);
  ?>

  <style>
  @keyframes pbPulse {
    0%,100%{box-shadow:0 4px 20px var(--pb-glow);}
    50%{box-shadow:0 4px 32px var(--pb-glow),0 0 0 5px rgba(255,255,255,0.4);}
  }
  .pb-wrap {
    border-radius:16px;margin-bottom:14px;overflow:hidden;
    animation:pbPulse 2.5s ease-in-out infinite;
  }
  .pb-inner { display:flex;align-items:stretch; }
  .pb-icon-col {
    padding:22px 18px;display:flex;align-items:center;justify-content:center;
    min-width:68px;
  }
  .pb-body { padding:15px 18px;flex:1; }
  .pb-title { font-size:15px;font-weight:800;margin-bottom:4px; }
  .pb-desc  { font-size:12.5px;line-height:1.55;margin-bottom:10px;opacity:0.88; }
  .pb-chip  {
    display:inline-flex;align-items:center;gap:5px;
    border-radius:8px;padding:4px 10px;font-size:11.5px;font-weight:600;
    margin:2px;border:1px solid rgba(255,255,255,0.5);
    background:rgba(255,255,255,0.35);
  }
  .pb-badge {
    display:inline-block;border-radius:20px;padding:2px 10px;
    font-size:11px;font-weight:700;margin-left:8px;vertical-align:middle;
    background:rgba(255,255,255,0.4);
  }
  .pb-progress-track { height:8px;background:rgba(255,255,255,0.35);border-radius:5px;overflow:hidden;margin-top:4px; }
  .pb-progress-fill  { height:100%;border-radius:5px;background:rgba(255,255,255,0.8);transition:width .5s ease; }
  .pb-meta { font-size:11px;opacity:0.75;margin-bottom:4px;display:flex;justify-content:space-between; }
  </style>

  <?php if(!empty($missed_logout_dates)): ?>
  <div class="pb-wrap" style="--pb-glow:rgba(30,58,138,0.4);background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 60%,#2563eb 100%);">
    <div class="pb-inner">
      <div class="pb-icon-col" style="background:rgba(255,255,255,0.12);border-right:1px solid rgba(255,255,255,0.2);">
        <i class="fas fa-money-bill-wave" style="font-size:2rem;color:white;"></i>
      </div>
      <div class="pb-body" style="color:white;">
        <div class="pb-title">
          ⚠️ Missed Logout — Salary Deduction Applied
          <span class="pb-badge"><?php echo count($missed_logout_dates); ?> day(s)</span>
        </div>
        <div class="pb-desc">
          Policy (from <strong>June 2026</strong>): <strong>½ day salary deducted</strong> for each missed logout. Always log out before leaving.
        </div>
        <div style="display:flex;flex-wrap:wrap;gap:5px;">
          <?php foreach($missed_logout_dates as $md): ?>
          <span class="pb-chip">
            <i class="fas fa-calendar-times"></i>
            <?php echo date('d M Y (D)', strtotime($md)); ?>
            <span style="background:rgba(0,0,0,0.2);border-radius:4px;padding:1px 7px;font-size:10px;font-weight:700;">−½ day</span>
          </span>
          <?php endforeach; ?>
        </div>
      </div>
    </div>
  </div>
  <?php endif; ?>

  <?php if($total_late_month > 0): ?>
  <?php
  $is_triggered = $absents_triggered > 0;
  $bg   = 'linear-gradient(135deg,#1e3a8a 0%,#1e40af 60%,#2563eb 100%)';
  $glow = 'rgba(30,58,138,0.4)';
  ?>
  <div class="pb-wrap" style="--pb-glow:<?php echo $glow; ?>;background:<?php echo $bg; ?>;">
    <div class="pb-inner">
      <div class="pb-icon-col" style="background:rgba(255,255,255,0.12);border-right:1px solid rgba(255,255,255,0.2);">
        <i class="fas <?php echo $is_triggered ? 'fa-user-slash' : 'fa-clock'; ?>" style="font-size:2rem;color:white;"></i>
      </div>
      <div class="pb-body" style="color:white;">
        <div class="pb-title">
          <?php if($is_triggered): ?>
            🚨 Late Policy Applied — <?php echo $absents_triggered; ?> Absent Day(s) Marked
            <span class="pb-badge">Action Taken</span>
          <?php else: ?>
            🕐 Late Warning — <?php echo $total_late_month; ?> Late Day(s) in Selected Range
            <span class="pb-badge"><?php echo $lates_remaining_to_next; ?> more = absent</span>
          <?php endif; ?>
        </div>
        <div class="pb-desc">
          <?php if($is_triggered): ?>
            Total late check-ins this month: <strong><?php echo $total_late_month; ?></strong> (which is exactly <strong><?php echo $total_late_month - $absents_triggered; ?> remaining late days</strong> + <strong><?php echo $absents_triggered; ?> converted to Absent</strong>). Every <strong>6th late day = 1 absent</strong>.
          <?php else: ?>
            You have <strong><?php echo $total_late_month; ?> late day(s)</strong> this month. Every <strong>6th late day = 1 absent</strong> (from June 2026). <strong><?php echo $lates_remaining_to_next; ?> more</strong> and an absent will be marked.
          <?php endif; ?>
        </div>
        <div>
          <div class="pb-meta">
            <span>Remaining Late Days: <strong><?php echo $total_late_month - $absents_triggered; ?></strong></span>
            <span>Cycle: <?php echo $lates_in_cur_cycle; ?> / <?php echo $lates_per_absent; ?> &nbsp;·&nbsp; <?php echo $lates_remaining_to_next; ?> to next absent</span>
          </div>
          <div style="font-size:12px;margin-top:8px;margin-bottom:8px;padding:6px 10px;background:rgba(0,0,0,0.2);border-radius:6px;line-height:1.4;">
            <strong>Dates marked as Late:</strong><br>
            <span style="color:#cbd5e1;"><?php echo empty($banner_late_dates) ? 'None' : implode(', ', $banner_late_dates); ?></span>
          </div>
          <div class="pb-progress-track">
            <div class="pb-progress-fill" style="width:<?php echo $progress_pct; ?>%;"></div>
          </div>
        </div>
        <?php if(!empty($late_policy_absent_dates)): ?>
        <div style="display:flex;flex-wrap:wrap;gap:5px;margin-top:10px;">
          <?php foreach($late_policy_absent_dates as $ad): ?>
          <span class="pb-chip">
            <i class="fas fa-user-slash"></i>
            <?php echo date('d M Y (D)', strtotime($ad)); ?>
            <span style="background:rgba(0,0,0,0.2);border-radius:4px;padding:1px 7px;font-size:10px;font-weight:700;">Absent</span>
          </span>
          <?php endforeach; ?>
        </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
  <?php endif; ?>

  <form method="GET">
    <?php if($is_admin && isset($_GET['date_from'])): ?>
      <input type="hidden" name="date_from" value="<?php echo htmlspecialchars($_GET['date_from']); ?>">
      <input type="hidden" name="date_to"   value="<?php echo htmlspecialchars($_GET['date_to']); ?>">
    <?php endif; ?>
    <div class="filter-bar">
      <h5><i class="fas fa-user-clock"></i> My Attendance</h5>
      <div class="filter-row">
        <div class="filter-group"><label>From Date</label><input type="date" name="mf_start" value="<?php echo htmlspecialchars($mf_start); ?>"></div>
        <div class="filter-group"><label>To Date</label><input type="date" name="mf_end" value="<?php echo htmlspecialchars($mf_end); ?>"></div>
        <div style="margin-top:22px;"><button type="submit" class="btn-header btn-primary-custom"><i class="fas fa-search"></i> Filter</button></div>
        <?php if(!empty($user_assigned_location)): ?><div style="margin-top:22px;"><span class="badge badge-success" style="padding:10px 15px;"><i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($user_assigned_location); ?></span></div><?php endif; ?>
        <?php if(!empty($user_work_timings)): ?><div style="margin-top:22px;"><span class="badge badge-warning" style="padding:10px 15px;"><i class="fas fa-clock"></i> <?php echo htmlspecialchars($user_work_timings); ?></span></div><?php endif; ?>
      </div>
    </div>
  </form>



  <?php
  // Build combined array of actual attendance and missing days (holidays) for the My Attendance table
  $my_table_records = [];
  $my_covered_dates = [];
  if($my_result && mysqli_num_rows($my_result) > 0) {
      mysqli_data_seek($my_result, 0);
      while($row = mysqli_fetch_assoc($my_result)) {
          $my_table_records[] = $row;
          $my_covered_dates[] = $row['date'];
      }
  }
  
  // Inject missed holidays AND missing dates that are actually approved leaves
  if(isset($my_id)) {
      $cur_date = $mf_start;
      $hire_date = (!empty($user_emp_data['hire_date']) && $user_emp_data['hire_date'] != '0000-00-00') ? $user_emp_data['hire_date'] : null;
      
      while(strtotime($cur_date) <= strtotime($mf_end)) {
          // Skip days before hire date
          if($hire_date && strtotime($cur_date) < strtotime($hire_date)) {
              $cur_date = date('Y-m-d', strtotime($cur_date . ' +1 day'));
              continue;
          }
          
          if(!in_array($cur_date, $my_covered_dates)) {
              if(isset($office_holidays[$cur_date])) {
                  // It's a holiday
                  $my_table_records[] = [
                      'id' => null, 'employee_id' => $my_id, 'employee_name' => '',
                      'date' => $cur_date, 'check_in_time' => null, 'check_out_time' => null,
                      'work_hours' => 0, 'status' => 'holiday',
                      'check_in_photo' => null, 'check_out_photo' => null,
                      'check_in_location' => '', 'check_out_location' => '',
                      'record_type' => 'holiday',
                      'override_reason' => $office_holidays[$cur_date] ?? 'Office Holiday',
                      'override_status' => 'holiday', 'late_policy_converted' => 'No'
                  ];
              } elseif(date('w', strtotime($cur_date)) != 0) { // Exclude Sundays
                  // It's a missing working day, only inject if they had approved leave
                  if(isset($my_full_day_leaves[$cur_date]) || isset($my_half_day_dates[$cur_date])) {
                      $my_table_records[] = [
                          'id' => null, 'employee_id' => $my_id, 'employee_name' => '',
                          'date' => $cur_date, 'check_in_time' => null, 'check_out_time' => null,
                          'work_hours' => 0, 'status' => 'absent',
                          'check_in_photo' => null, 'check_out_photo' => null,
                          'check_in_location' => '', 'check_out_location' => '',
                          'record_type' => 'missing',
                          'override_reason' => '', 'override_status' => '', 'late_policy_converted' => 'No'
                      ];
                  }
              }
          }
          $cur_date = date('Y-m-d', strtotime($cur_date . ' +1 day'));
      }
  }
  
  // Sort combined records by date DESC
  usort($my_table_records, function($a, $b) {
      return ($a['date'] < $b['date']) ? 1 : -1;
  });
  ?>

  <div class="table-container">
    <div class="table-header-actions">
      <h5><i class="fas fa-user"></i> My Attendance Records</h5>
      <?php if(!empty($my_table_records)): ?>
      <a href="?action=export&export_type=personal&mf_start=<?php echo urlencode($mf_start); ?>&mf_end=<?php echo urlencode($mf_end); ?>" class="btn-header btn-export-custom"><i class="fas fa-download"></i> Export My Records</a>
      <?php endif; ?>
    </div>
    <table id="personalTable" class="display nowrap" style="width:100%">
      <thead><tr><th>Date</th><th>Day</th><th>Check In</th><th>Check Out</th><th>Work Hours</th><th>Status</th><th>Reason</th><th>Photos</th></tr></thead>
      <tbody>
      <?php if(!empty($my_table_records)):
          foreach($my_table_records as $row):
              $my_is_half_day_leave = (isset($row['override_status']) && $row['override_status'] === 'half_day')
                  || isset($my_half_day_dates[$row['date']]);

              $my_half_day_label = 'Half Day';
              if(isset($my_half_day_dates[$row['date']])) {
                  $my_half_day_label = $my_half_day_dates[$row['date']];
              } elseif(isset($row['override_status']) && $row['override_status'] === 'half_day') {
                  $my_half_day_label = 'Half Day (HR)';
              }

              $my_is_full_day_leave = isset($my_full_day_leaves[$row['date']]);
              $my_leave_type_label = $my_is_full_day_leave ? $my_full_day_leaves[$row['date']] : '';
      ?>
      <tr <?php echo (isset($row['record_type']) && $row['record_type'] == 'override') ? 'style="background-color: #f0f9ff; border-left: 4px solid #3b82f6;"' : ''; ?>>
        <td>
          <strong><?php echo date('M d, Y', strtotime($row['date'])); ?></strong>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <?php if(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto:') === 0): ?>
              <div style="font-size:10px;color:#059669;font-weight:600;"><i class="fas fa-user-edit"></i> Administration Override</div>
            <?php else: ?>
              <div style="font-size:10px;color:#3b82f6;font-weight:600;"><i class="fas fa-user-edit"></i> HR Override</div>
            <?php endif; ?>
          <?php endif; ?>
        </td>
        <td><?php echo date('l', strtotime($row['date'])); ?></td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">Override</span>
          <?php elseif(isset($row['record_type']) && $row['record_type'] == 'holiday'): ?>
            <span style="color:#0ea5e9;font-weight:bold;">Holiday</span>
          <?php elseif(isset($row['record_type']) && $row['record_type'] == 'missing'): ?>
            <?php if(isset($my_is_full_day_leave) && $my_is_full_day_leave): ?>
              <span style="color:#3b82f6;font-weight:bold;">—</span>
            <?php else: ?>
              <span style="color:#dc2626;font-weight:bold;">Not Checked In</span>
            <?php endif; ?>
          <?php else: ?>
            <?php echo date('h:i A', strtotime($row['check_in_time'])); ?>
              <!-- Removed duplicate late text -->
          <?php endif; ?>
        </td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">Override</span>
          <?php elseif(isset($row['record_type']) && ($row['record_type'] == 'holiday' || $row['record_type'] == 'missing')): ?>
            <span style="color:#94a3b8;">—</span>
          <?php else: ?>
            <?php if($row['check_out_time']): ?>
              <?php echo date('h:i A', strtotime($row['check_out_time'])); ?>
              <?php if(substr($row['check_out_time'],0,5) < substr($row['check_in_time'],0,5)): ?>
                <span style="font-size:10px;color:#7c3aed;font-weight:700;display:block;"><i class="fas fa-moon"></i> Next Day</span>
              <?php endif; ?>
            <?php else: ?>—<?php endif; ?>
          <?php endif; ?>
        </td>
        <td>
          <?php if(isset($row['record_type']) && ($row['record_type'] == 'override' || $row['record_type'] == 'holiday' || $row['record_type'] == 'missing')): ?>
            <span style="color:#64748b;font-style:italic;">—</span>
          <?php else: ?>
            <?php
                if($row['work_hours']) {
                    $wh = floatval($row['work_hours']);
                    if($my_is_half_day_leave) {
                        // Approved half-day leave for this date -- shorter hours are expected, not a shortfall.
                        echo '<span style="color:#0891b2;font-weight:700;">' . $row['work_hours'] . ' hr</span>';
                    } else {
                        $wh_color = ($wh < 8) ? '#dc2626' : '#059669';
                        echo '<span style="color:' . $wh_color . ';font-weight:700;">' . $row['work_hours'] . ' hr</span>';
                    }
                } else {
                    echo '—';
                }
              ?>
          <?php endif; ?>
        </td>
        <td>
          <?php $missed_logout = (empty($row['check_out_time']) && $row['date'] < date('Y-m-d') && (!isset($row['record_type']) || $row['record_type'] != 'override') && (!isset($row['override_status']) || !in_array($row['override_status'], ['leave', 'half_day', 'holiday'])) && !$my_is_half_day_leave && !(isset($my_is_full_day_leave) && $my_is_full_day_leave)); ?>
          <span class="badge badge-<?php
            echo $my_is_half_day_leave?'info':(
                (isset($my_is_full_day_leave) && $my_is_full_day_leave)?'primary':(
                ($row['status']=='present'?'success':
                ($row['status']=='late'?'warning':'danger'))));
          ?>">
            <?php
            if(isset($row['record_type']) && $row['record_type'] == 'override') {
              $lbl = isset($row['override_status']) ? ucfirst($row['override_status']) : ucfirst($row['status']);
              if($lbl == 'Half_day') $lbl = 'Half Day';
              if(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto: Excused') !== false) {
                echo 'Late (Excused)';
              } elseif(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto:') === 0) {
                  if ($my_is_half_day_leave) {
                      echo $my_half_day_label;
                  } elseif (isset($my_is_full_day_leave) && $my_is_full_day_leave) {
                      echo $my_leave_type_label;
                  } else {
                      echo $lbl . ' (Administration)';
                  }
              } else {
                echo $lbl . ' (HR)';
              }
            } elseif(isset($row['record_type']) && $row['record_type'] == 'missing') {
              if(isset($my_is_full_day_leave) && $my_is_full_day_leave) {
                  echo $my_leave_type_label;
              } else {
                  echo 'Missing';
              }
            } elseif(isset($row['record_type']) && $row['record_type'] == 'holiday') {
              echo 'HOLIDAY';
            } elseif($my_is_half_day_leave) {
              echo $my_half_day_label;
            } elseif(isset($my_is_full_day_leave) && $my_is_full_day_leave) {
              echo $my_leave_type_label;
            } else {
              if($row['status'] == 'absent' && isset($row['late_policy_converted']) && $row['late_policy_converted'] == 'Yes') {
                  echo 'Late (Absent)';
              } elseif(!empty($row['override_reason']) && stripos($row['override_reason'], 'Auto: Excused') !== false) {
                  echo 'Late (Excused)';
              } else {
                  $base = ucfirst($row['status']);
                  if(isset($row['check_in_location']) && stripos($row['check_in_location'], 'Force In by HR') !== false) {
                      $base .= ' (Force In)';
                  } elseif(isset($row['check_out_location']) && stripos($row['check_out_location'], 'Force Out by HR') !== false) {
                      $base .= ' (Force Out)';
                  }
                  echo $base;
              }
            }
            ?>
          </span>
        </td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <?php if(!empty($row['override_reason'])): ?>
              <?php
              $reason_text2 = htmlspecialchars($row['override_reason']);
              $reason_id2   = 'preason_' . ($row['id'] ?? md5($row['date'])) . '_' . md5($row['date']);
              ?>
              <div style="color:#1e40af;font-size:11px;width:150px;white-space:normal;word-wrap:break-word;line-height:1.4;">
                <i class="fas fa-info-circle" style="flex-shrink:0;"></i>
                <span id="short_<?php echo $reason_id2; ?>" style="font-style:italic;">
                  <?php echo mb_substr($reason_text2, 0, 50) . (mb_strlen($reason_text2) > 50 ? '...' : ''); ?>
                </span>
                <span id="full_<?php echo $reason_id2; ?>" style="font-style:italic;display:none;">
                  <?php echo $reason_text2; ?>
                </span>
                <?php if(mb_strlen($row['override_reason']) > 50): ?>
                <br><a href="javascript:void(0)" onclick="toggleReason('<?php echo $reason_id2; ?>')" id="toggle_<?php echo $reason_id2; ?>"
                   style="color:#7c3aed;font-weight:700;font-style:normal;font-size:11px;">Read more</a>
                <?php endif; ?>
              </div>
            <?php else: ?>
              <span style="color:#94a3b8;font-style:italic;font-size:12px;">—</span>
            <?php endif; ?>
          <?php elseif(isset($row['record_type']) && $row['record_type'] == 'holiday'): ?>
            <span style="color:#94a3b8;font-size:12px;">—</span>
          <?php elseif(isset($row['record_type']) && $row['record_type'] == 'missing'): ?>
            <?php if(isset($my_is_full_day_leave) && $my_is_full_day_leave): ?>
              <span style="color:#64748b;font-style:italic;font-size:12px;">Auto: Approved Leave</span>
            <?php else: ?>
              <span style="color:#94a3b8;font-size:12px;">—</span>
            <?php endif; ?>
          <?php else: ?>
            <?php
              $reasons = [];
              if($missed_logout) {
                  $reasons[] = '<span style="color:#d97706;font-size:11px;font-weight:600;white-space:nowrap;"><i class="fas fa-exclamation-triangle"></i> No Log Off Policy</span>';
              } elseif(isset($row['late_policy_converted']) && $row['late_policy_converted'] === 'Yes') {
                  $reasons[] = '<span style="color:#dc2626;font-size:11px;font-weight:600;white-space:nowrap;"><i class="fas fa-exclamation-triangle"></i> Converted from Late (Policy)</span>';
              }
              if(count($reasons) > 0) {
                  echo implode('<br>', $reasons);
              } else {
                  echo '<span style="color:#94a3b8;font-size:12px;">—</span>';
              }
            ?>
          <?php endif; ?>
        </td>
        <td>
          <?php if(isset($row['record_type']) && ($row['record_type'] == 'override' || $row['record_type'] == 'holiday')): ?>
            <span style="color:#64748b;font-style:italic;">—</span>
          <?php else: ?>
            <?php if($row['check_in_photo']): ?><img src="<?php echo str_replace('/dashboard/uploads/','/hrm/uploads/',$row['check_in_photo']); ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            <?php if($row['check_out_photo']): ?><img src="<?php echo str_replace('/dashboard/uploads/','/hrm/uploads/',$row['check_out_photo']); ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; else: ?>
        <tr><td colspan="8" style="text-align:center;padding:30px;color:#94a3b8">No records found.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<!-- MARK ATTENDANCE MODAL -->
<?php if($is_active_employee): ?>
<div class="modal fade" id="markModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal">&times;</button>
        <h4 class="modal-title"><i class="fas fa-camera"></i> Mark Attendance</h4>
      </div>
      <div class="modal-body">

        <!-- DATE auto-set to TODAY — no picker -->
        <div id="datePickerStep" style="display:none;">
          <input type="hidden" id="att_date" value="<?php echo date('Y-m-d'); ?>">
        </div>

        <!-- STATUS PANEL — shown after date is checked (via AJAX) -->
        <div id="statusPanel" style="display:none;">

          <!-- State A: Both done -->
          <div id="stateAllDone" style="display:none;text-align:center;padding:30px;">
            <i class="fas fa-check-circle" style="font-size:64px;color:#10b981;"></i>
            <h3 style="margin-top:15px;color:#065f46;">Attendance Complete!</h3>
            <p id="stateAllDoneMsg" style="color:#64748b;margin-top:8px;"></p>
          </div>

          <!-- State B: Only check-in done, check-out pending -->
          <div id="stateCheckedInOnly" style="display:none;">
            <div style="background:#fef3c7;border:2px solid #f59e0b;border-radius:10px;padding:15px;margin-bottom:15px;display:flex;align-items:center;gap:12px;">
              <i class="fas fa-sign-in-alt" style="font-size:28px;color:#d97706;"></i>
              <div>
                <div style="font-weight:700;color:#92400e;">Already Checked In</div>
                <div id="checkedInMsg" style="font-size:13px;color:#92400e;margin-top:3px;"></div>
              </div>
            </div>
            <p style="font-size:13px;color:#64748b;margin-bottom:12px;">You have not checked out yet. Capture photo &amp; GPS to check out.</p>
          </div>

          <!-- State C: Nothing done yet -->
          <div id="stateNothing" style="display:none;">
            <div style="background:#d1fae5;border:2px solid #10b981;border-radius:10px;padding:12px 15px;margin-bottom:15px;display:flex;align-items:center;gap:10px;">
              <i class="fas fa-clock" style="color:#059669;font-size:20px;"></i>
              <div style="font-weight:600;color:#065f46;" id="nothingMsg"></div>
            </div>
          </div>

          <!-- Employee Info -->
          <div class="info-card">
            <h6><i class="fas fa-user"></i> <?php echo htmlspecialchars($user_emp_data['name']); ?> &nbsp;<small style="color:#94a3b8;"><?php echo htmlspecialchars($user_emp_data['employee_id']); ?></small></h6>
            <?php if($user_assigned_location): ?><p style="margin-top:6px;font-size:13px;"><i class="fas fa-map-marker-alt" style="color:#10b981;"></i> <?php echo htmlspecialchars($user_assigned_location); ?> &nbsp; <i class="fas fa-clock" style="color:#f59e0b;"></i> <?php echo htmlspecialchars($user_work_timings); ?></p><?php endif; ?>
          </div>

          <!-- Camera + GPS Form (shown for check-in OR check-out) -->
          <div id="attFormWrap">
            <form method="POST" id="attForm">
              <input type="hidden" name="action_type" id="att_action_type">
              <!-- att_date_input removed — server always uses today -->
              <input type="hidden" name="latitude"       id="lat">
              <input type="hidden" name="longitude"      id="lng">
              <input type="hidden" name="location_name"  id="loc_name">
              <input type="hidden" name="photo_data"     id="photo_data">

              <div style="position:relative;margin-bottom:15px;text-align:center;">
                <video id="video" autoplay playsinline></video>
                <canvas id="canvas"></canvas>
                <img id="preview" alt="Captured Photo">
              </div>
              <div style="text-align:center;margin-bottom:15px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap;">
                <button type="button" class="btn-header btn-primary-custom" id="btnStart" onclick="startCamera()"><i class="fas fa-video"></i> Start Camera</button>
                <button type="button" class="btn-header btn-primary-custom" style="display:none;" id="btnSnap" onclick="takePhoto()"><i class="fas fa-camera"></i> Capture</button>
                <button type="button" class="btn-header btn-danger-custom" style="display:none;" id="btnRetake" onclick="resetCamera()"><i class="fas fa-redo"></i> Retake</button>
              </div>
              <div id="gpsStatus" class="gps-status" style="background:#f1f5f9;color:#64748b;"><i class="fas fa-spinner fa-spin"></i> Getting Location...</div>
              <button type="submit" name="submit_attendance" id="btnSubmit"
                class="btn-header btn-success-custom"
                style="width:100%;justify-content:center;margin-top:15px;display:none;" disabled>
                <i class="fas fa-check-circle"></i> <span id="btnSubmitLabel">Confirm Check In</span>
              </button>
            </form>
          </div>

        </div><!-- /statusPanel -->

      </div>
    </div>
  </div>
</div>
<?php endif; ?>


<!-- PHOTO MODAL -->
<div class="modal fade" id="photoModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header"><button type="button" class="close" data-dismiss="modal">&times;</button><h4 class="modal-title"><i class="fas fa-image"></i> Photo</h4></div><div class="modal-body text-center"><img id="viewImg" src="" style="max-width:100%;border-radius:12px"></div></div></div>
</div>

<!-- ADMIN MODALS - CORRECTED LOGIC FROM PERMISSIONS FILE -->
<?php if($is_admin): ?>
<!-- NOT CHECKED IN -->
<div class="modal fade" id="notCheckedInModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header"><h4 class="modal-title"><i class="fas fa-user-times"></i> Employees Not Checked In</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['not_checked_in_list'])): ?>
          <div class="employee-list">
            <?php foreach($employee_stats['not_checked_in_list'] as $emp): ?>
            <div class="employee-item" style="display:block;padding:15px;">
              <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($emp['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($emp['employee_id']); ?></div>
                  <div class="employee-info">
                    <?php if(!empty($emp['department'])): ?><i class="fas fa-building"></i> <?php echo htmlspecialchars($emp['department']); ?><?php endif; ?>
                    <?php if(!empty($emp['work_location'])): ?> | <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($emp['work_location']); ?><?php endif; ?>
                    <?php if(!empty($emp['hire_date']) && $emp['hire_date'] != '0000-00-00'): ?> | <i class="fas fa-calendar-plus"></i> Joined: <?php echo date('M d, Y', strtotime($emp['hire_date'])); ?><?php endif; ?>
                  </div>
                </div>
                <span class="badge badge-danger"><?php echo $emp['missing_count']; ?> Days Absent</span>
              </div>
              <div style="background:#fee2e2;padding:10px;border-radius:8px;">
                <strong style="color:#991b1b;font-size:12px;">
                  Missing Dates
                  <?php if(!empty($emp['emp_start_date']) && $emp['emp_start_date'] != $stats_date_from): ?>
                    (from joining date <?php echo date('M d, Y', strtotime($emp['emp_start_date'])); ?>):
                  <?php else: ?>:
                  <?php endif; ?>
                </strong>
                <div style="margin-top:5px;display:flex;flex-wrap:wrap;gap:5px;">
                  <?php foreach($emp['missing_dates'] as $md): ?>
                    <span style="background:white;padding:4px 8px;border-radius:5px;font-size:11px;color:#991b1b;border:1px solid #fecaca;">
                      <?php echo date('M d (D)', strtotime($md)); ?>
                    </span>
                  <?php endforeach; ?>
                </div>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px">
            <i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i>
            <h4 style="margin-top:15px">Perfect Attendance!</h4>
            <p style="color:#64748b">All employees have marked attendance for all working days.</p>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- CHECKED IN -->
<div class="modal fade" id="checkedInModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#10b981,#059669);">
        <h4 class="modal-title"><i class="fas fa-user-check"></i> Employees Checked In</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['checked_in_list'])): ?>
          <div class="employee-list">
            <?php
            $grouped = [];
            foreach($employee_stats['checked_in_list'] as $emp) {
                $grouped[$emp['employee_id']]['name']          = $emp['employee_name'];
                $grouped[$emp['employee_id']]['dept']          = $emp['department']    ?? '';
                $grouped[$emp['employee_id']]['work_location'] = $emp['work_location'] ?? '';
                $grouped[$emp['employee_id']]['timings']       = $emp['timings']       ?? '';
                $grouped[$emp['employee_id']]['dates'][]       = $emp;
            }
            foreach($grouped as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:15px;">
              <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($eid); ?></div>
                  <div class="employee-info">
                    <?php if($ed['dept']): ?><i class="fas fa-building"></i> <?php echo htmlspecialchars($ed['dept']); ?><?php endif; ?>
                    <?php if($ed['work_location']): ?> | <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($ed['work_location']); ?><?php endif; ?>
                    <?php if($ed['timings']): ?> | <i class="fas fa-clock"></i> <?php echo htmlspecialchars($ed['timings']); ?><?php endif; ?>
                  </div>
                </div>
                <span class="badge badge-success"><?php echo count($ed['dates']); ?> Days</span>
              </div>
              <div style="background:#f0fdf4;padding:10px;border-radius:8px;border-left:3px solid #10b981;">
                <strong style="color:#065f46;font-size:12px;">Check-In Records:</strong>
                <div style="margin-top:5px;display:flex;flex-wrap:wrap;gap:5px;">
                  <?php foreach($ed['dates'] as $dr): ?>
                  <div style="background:white;padding:6px 10px;border-radius:5px;font-size:11px;color:#047857;border:1px solid #d1fae5;min-width:200px;">
                    <div style="font-weight:700;margin-bottom:3px;">
                      <i class="fas fa-calendar"></i> <?php echo date('M d, Y', strtotime($dr['date'])); ?>
                      (<?php echo date('l', strtotime($dr['date'])); ?>)
                      <span class="badge badge-<?php echo $dr['status']=='present'?'success':'warning'; ?>" style="font-size:9px;padding:2px 6px;margin-left:4px;"><?php echo ucfirst($dr['status']); ?></span>
                    </div>
                    <div style="color:#059669;">
                      <i class="fas fa-sign-in-alt"></i> In: <strong><?php echo date('h:i A', strtotime($dr['check_in_time'])); ?></strong>
                      <?php if(!empty($dr['check_out_time'])): ?>
                        | <i class="fas fa-sign-out-alt"></i> Out: <strong><?php echo date('h:i A', strtotime($dr['check_out_time'])); ?></strong>
                      <?php else: ?>
                        | <span style="color:#dc2626;"><i class="fas fa-exclamation-circle"></i> Not Out</span>
                      <?php endif; ?>
                    </div>
                  </div>
                  <?php endforeach; ?>
                </div>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-user-times" style="font-size:48px;color:#ef4444"></i><h4 style="margin-top:15px">No Check-Ins Yet!</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Present Days -->
<div class="modal fade" id="presentDaysModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#10b981,#059669);">
        <h4 class="modal-title"><i class="fas fa-calendar-check"></i> Present Days</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['present_list'])): ?>
          <div class="employee-list">
            <?php
            $grouped_x = [];
            foreach($employee_stats['present_list'] as $emp) {
                $grouped_x[$emp['employee_id']]['name']  = $emp['employee_name'];
                $grouped_x[$emp['employee_id']]['dates'][] = $emp['date'];
            }
            foreach($grouped_x as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:15px;">
              <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($eid); ?></div>
                </div>
                <span class="badge badge-success"><?php echo count($ed['dates']); ?> Days</span>
              </div>
              <div style="display:flex;flex-wrap:wrap;gap:5px;">
                <?php foreach($ed['dates'] as $dd): ?>
                  <span style="background:white;padding:4px 8px;border-radius:5px;font-size:11px;border:1px solid #e2e8f0;">
                    <?php echo date('M d, Y (D)', strtotime($dd)); ?>
                  </span>
                <?php endforeach; ?>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-calendar-times" style="font-size:48px;color:#94a3b8"></i><h4 style="margin-top:15px">No Present Records</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Absent Days -->
<div class="modal fade" id="absentDaysModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#ef4444,#dc2626);">
        <h4 class="modal-title"><i class="fas fa-calendar-times"></i> Absent Days</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['absent_list'])): ?>
          <div class="employee-list">
            <?php
            $grouped_x = [];
            foreach($employee_stats['absent_list'] as $emp) {
                $grouped_x[$emp['employee_id']]['name']  = $emp['employee_name'];
                $grouped_x[$emp['employee_id']]['dates'][] = $emp['date'];
            }
            foreach($grouped_x as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:15px;">
              <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($eid); ?></div>
                </div>
                <span class="badge badge-danger"><?php echo count($ed['dates']); ?> Days</span>
              </div>
              <div style="display:flex;flex-wrap:wrap;gap:5px;">
                <?php foreach($ed['dates'] as $dd): ?>
                  <span style="background:white;padding:4px 8px;border-radius:5px;font-size:11px;border:1px solid #e2e8f0;">
                    <?php echo date('M d, Y (D)', strtotime($dd)); ?>
                  </span>
                <?php endforeach; ?>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-check-circle" style="font-size:48px;color:#94a3b8"></i><h4 style="margin-top:15px">No Absent Records — Great!</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Half Days -->
<div class="modal fade" id="halfDaysModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h4 class="modal-title"><i class="fas fa-adjust"></i> Half Days</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['half_day_list'])): ?>
          <div class="employee-list">
            <?php
            $grouped_x = [];
            foreach($employee_stats['half_day_list'] as $emp) {
                $grouped_x[$emp['employee_id']]['name']  = $emp['employee_name'];
                $grouped_x[$emp['employee_id']]['dates'][] = $emp['date'];
            }
            foreach($grouped_x as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:15px;">
              <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($eid); ?></div>
                </div>
                <span class="badge badge-warning"><?php echo count($ed['dates']); ?> Days</span>
              </div>
              <div style="display:flex;flex-wrap:wrap;gap:5px;">
                <?php foreach($ed['dates'] as $dd): ?>
                  <span style="background:white;padding:4px 8px;border-radius:5px;font-size:11px;border:1px solid #e2e8f0;">
                    <?php echo date('M d, Y (D)', strtotime($dd)); ?>
                  </span>
                <?php endforeach; ?>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-check-circle" style="font-size:48px;color:#94a3b8"></i><h4 style="margin-top:15px">No Half-Day Records</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- LATE -->
<div class="modal fade" id="lateEmployeesModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h4 class="modal-title"><i class="fas fa-clock"></i> Late Employees</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['late_today_list'])): ?>
          <div class="employee-list">
            <?php
            $gl = [];
            foreach($employee_stats['late_today_list'] as $emp) {
                $gl[$emp['employee_id']]['name']    = $emp['employee_name'];
                $gl[$emp['employee_id']]['dates'][] = $emp;
            }
            foreach($gl as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:12px;">
              <div style="display:flex;justify-content:space-between;">
                <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                <span class="badge badge-warning"><?php echo count($ed['dates']); ?> Days Late</span>
              </div>
              <div style="background:#fef3c7;padding:8px;border-radius:8px;margin-top:8px;display:flex;flex-wrap:wrap;gap:5px;">
                <?php foreach($ed['dates'] as $dr): ?>
                  <div style="background:white;padding:5px 8px;border-radius:5px;font-size:11px;color:#92400e;border:1px solid #fde68a;">
                    <?php echo date('M d (D)', strtotime($dr['date'])); ?> | <?php echo date('h:i A', strtotime($dr['check_in_time'])); ?>
                  </div>
                <?php endforeach; ?>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i><h4 style="margin-top:15px">No Late Arrivals!</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- NOT LOGGED OFF -->
<div class="modal fade" id="notLoggedOffModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#3b82f6,#2563eb);">
        <h4 class="modal-title"><i class="fas fa-sign-out-alt"></i> Not Logged Off</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['not_logged_off_list'])): ?>
          <div class="employee-list">
            <?php
            $gnl = [];
            foreach($employee_stats['not_logged_off_list'] as $emp) {
                $gnl[$emp['employee_id']]['name']    = $emp['employee_name'];
                $gnl[$emp['employee_id']]['dates'][] = $emp;
            }
            foreach($gnl as $eid => $ed):
            ?>
            <div class="employee-item" style="display:block;padding:12px;">
              <div style="display:flex;justify-content:space-between;">
                <div class="employee-name"><?php echo htmlspecialchars($ed['name']); ?></div>
                <span class="badge badge-danger"><?php echo count($ed['dates']); ?> Days</span>
              </div>
              <div style="background:#dbeafe;padding:8px;border-radius:8px;margin-top:8px;display:flex;flex-wrap:wrap;gap:5px;">
                <?php foreach($ed['dates'] as $dr): ?>
                  <div style="background:white;padding:5px 8px;border-radius:5px;font-size:11px;color:#1e40af;border:1px solid #bfdbfe;">
                    <?php echo date('M d (D)', strtotime($dr['date'])); ?> | In: <?php echo date('h:i A', strtotime($dr['check_in_time'])); ?>
                    <span style="color:#dc2626;margin-left:4px;"><i class="fas fa-exclamation-triangle"></i> No Checkout</span>
                  </div>
                <?php endforeach; ?>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px"><i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i><h4 style="margin-top:15px">All Logged Off!</h4></div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- LATE POLICY MODAL -->
<div class="modal fade" id="latePolicyModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#dc2626,#b91c1c);">
        <h4 class="modal-title" style="color:white;"><i class="fas fa-user-slash"></i> Late Attendance Policy — 6 Total Days</h4>
        <button type="button" class="close" style="color:white;" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div class="alert alert-warning" style="font-size:13px;">
          <i class="fas fa-info-circle"></i> <strong>Policy:</strong> If an employee is late for a total of <strong>6 working days</strong>, one day (the 6th late day) will be automatically marked as <strong>Absent</strong>.
        </div>
        <div id="late-policy-list">
          <div class="text-center py-4"><i class="fas fa-spinner fa-spin fa-2x text-muted"></i><p class="mt-2">Checking...</p></div>
        </div>
        <div id="late-policy-result" style="display:none;"></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
        <button type="button" id="apply-late-policy-btn" class="btn btn-danger" onclick="applyLatePolicy()" style="display:none;">
          <i class="fas fa-user-slash"></i> Apply Policy (Mark Absent)
        </button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- ATTENDANCE ACCESS LIST MODAL (Super Admin & HR) -->
<?php if($is_super_admin || $is_keerti): ?>
<div class="modal fade" id="attendanceAccessListModal" tabindex="-1" role="dialog" aria-hidden="true">
  <div class="modal-dialog modal-lg" style="max-width:850px;">
    <div class="modal-content" style="border-radius:12px;border:none;box-shadow:0 10px 30px rgba(0,0,0,0.15);">
      <div class="modal-header" style="background:linear-gradient(135deg,#1e40af,#3b82f6);color:white;border-radius:12px 12px 0 0;padding:16px 24px;">
        <h4 class="modal-title" style="font-weight:700;display:flex;align-items:center;gap:10px;margin:0;">
          <i class="fas fa-user-shield"></i> Attendance Admin Access Permissions
        </h4>
        <button type="button" class="close" data-dismiss="modal" aria-label="Close" style="color:white;opacity:0.8;font-size:24px;border:none;background:none;cursor:pointer;">
          <span aria-hidden="true">&times;</span>
        </button>
      </div>
      <div class="modal-body" style="padding:24px;">
        <div style="background:#eff6ff;border-left:4px solid #3b82f6;padding:12px 16px;border-radius:6px;margin-bottom:18px;">
          <div style="font-weight:700;color:#1e40af;font-size:13px;margin-bottom:2px;">
            <i class="fas fa-info-circle"></i> Access Control Settings
          </div>
          <div style="font-size:12px;color:#334155;line-height:1.6;">
            Employees enabled below have permission to view the company-wide <strong>Admin Attendance Dashboard & Overview</strong>.
            Employees toggled <strong>Disabled</strong> will only view their own personal attendance.
            <br>
            <span style="color:#059669;font-weight:600;"><i class="fas fa-shield-alt"></i> Master Super Admin (<code>abishek.veeraswamy@fleet.abra-travels.com</code>) always has full permanent access.</span>
          </div>
        </div>

        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;gap:12px;">
          <input type="text" id="accessListSearchInput" class="form-control" placeholder="Search employee name, department, or ID..." style="border-radius:8px;padding:8px 14px;border:1px solid #cbd5e1;font-size:13px;" onkeyup="filterAccessListTable()">
          <div style="font-size:12px;color:#64748b;white-space:nowrap;" id="accessListCountBadge">Loading...</div>
        </div>

        <div style="max-height:420px;overflow-y:auto;border:1px solid #e2e8f0;border-radius:8px;">
          <table class="table table-hover" style="margin:0;font-size:13px;">
            <thead style="background:#f8fafc;position:sticky;top:0;z-index:2;">
              <tr>
                <th style="padding:10px 14px;font-weight:700;color:#475569;">Employee</th>
                <th style="padding:10px 14px;font-weight:700;color:#475569;">Department</th>
                <th style="padding:10px 14px;font-weight:700;color:#475569;">Position</th>
                <th style="padding:10px 14px;font-weight:700;color:#475569;text-align:center;">Admin View</th>
              </tr>
            </thead>
            <tbody id="accessListTableBody">
              <tr><td colspan="4" style="text-align:center;padding:30px;color:#94a3b8;"><i class="fas fa-spinner fa-spin"></i> Loading access list...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
      <div class="modal-footer" style="background:#f8fafc;border-top:1px solid #e2e8f0;border-radius:0 0 12px 12px;padding:12px 24px;display:flex;justify-content:space-between;align-items:center;">
        <span style="font-size:11px;color:#64748b;">Changes take effect immediately upon toggle.</span>
        <button type="button" class="btn btn-secondary" data-dismiss="modal" style="border-radius:6px;padding:7px 18px;font-size:13px;font-weight:600;">Close</button>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- KPI BLOCKING MODAL -->
<div class="modal fade" id="kpiBlockingModal" tabindex="-1" data-backdrop="static" data-keyboard="false">
  <div class="modal-dialog modal-lg"><div class="modal-content" style="border:3px solid #dc2626;"><div class="modal-header" style="background:linear-gradient(135deg,#dc2626,#b91c1c);border:none;"><h4 class="modal-title" style="color:white;font-size:24px;font-weight:800;"><i class="fas fa-ban"></i> Complete Your Self-Review First</h4></div><div class="modal-body" style="padding:50px 30px;text-align:center;background:#fef2f2;"><i class="fas fa-lock" style="font-size:100px;color:#dc2626;margin-bottom:30px;display:block;"></i><h2 style="color:#991b1b;font-weight:800;margin-bottom:20px;">Check-Out Blocked</h2>
  <div id="kpiBlockingList" style="font-size:16px;color:#475569;margin-bottom:30px;text-align:left;max-width:420px;margin-left:auto;margin-right:auto;">
    <p id="kpiBlockDaily" style="display:none;margin-bottom:8px;"><i class="fas fa-circle-exclamation" style="color:#dc2626;margin-right:8px;"></i>Complete your <strong>Daily Self-Evaluation</strong> (today).</p>
    <p id="kpiBlockWeekly" style="display:none;margin-bottom:8px;"><i class="fas fa-circle-exclamation" style="color:#dc2626;margin-right:8px;"></i>Complete your <strong>Weekly Self-Evaluation</strong> (this week).</p>
    <p id="kpiBlockMonthly" style="display:none;margin-bottom:8px;"><i class="fas fa-circle-exclamation" style="color:#dc2626;margin-right:8px;"></i>Complete your <strong>Monthly Self-Evaluation</strong> (this month).</p>
    <p id="plannerBlockMonthly" style="display:none;margin-bottom:8px;"><i class="fas fa-circle-exclamation" style="color:#dc2626;margin-right:8px;"></i>Complete your <strong>Monthly Planner</strong> (next month).</p>
  </div>
  <div style="display:flex;gap:15px;justify-content:center;flex-wrap:wrap;"><a href="hr-kpi-evaluation.php" class="btn-header btn-danger-custom" style="font-size:18px;padding:15px 30px;"><i class="fas fa-clipboard-check"></i> Complete Review</a><a href="hr-employee-daily-planner.php" id="plannerBlockBtn" class="btn-header btn-primary-custom" style="display:none;font-size:18px;padding:15px 30px;"><i class="fas fa-calendar-day"></i> Complete Planner</a><button type="button" class="btn-header btn-primary-custom" onclick="$('#kpiBlockingModal').modal('hide')" style="font-size:18px;padding:15px 30px;background:#64748b;border-color:#64748b;"><i class="fas fa-times"></i> Close</button></div></div></div></div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/js/select2.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
const userAssignedLocation    = "<?php echo $user_assigned_location; ?>";
const allOffices              = <?php echo json_encode($all_valid_offices); ?>;
const todayCheckedIn          = <?php echo $today_in  ? 'true' : 'false'; ?>;
const userKpiComplete         = <?php echo $user_kpi_complete ? 'true' : 'false'; ?>;
const userWeeklyOk            = <?php echo $user_weekly_ok  ? 'true' : 'false'; ?>;
const userMonthlyOk           = <?php echo $user_monthly_ok ? 'true' : 'false'; ?>;
const userPlannerOk           = <?php echo $user_planner_ok ? 'true' : 'false'; ?>;
const hasPendingNightCheckout = <?php echo $pending_yesterday_checkin ? 'true' : 'false'; ?>;
const ovattRecords            = <?php echo $is_super_admin ? json_encode($ovatt_records) : '[]'; ?>;

// Single source of truth: mirrors the $bypass_location PHP value computed above,
// which is now HR-controlled per employee (Add/Edit Employee → "Attendance Location").
const bypassLocation = <?php echo $bypass_location ? 'true' : 'false'; ?>;

function openAccessListModal() {
  $('#attendanceAccessListModal').modal('show');
  loadAccessList();
}

function loadAccessList() {
  var tbody = $('#accessListTableBody');
  tbody.html('<tr><td colspan="4" style="text-align:center;padding:25px;color:#64748b;"><i class="fas fa-spinner fa-spin"></i> Loading employee access list...</td></tr>');
  
  $.getJSON('<?php echo $_SERVER['PHP_SELF']; ?>?action=get_attendance_access_list', function(resp) {
    if(!resp || !resp.success || !resp.employees) {
      tbody.html('<tr><td colspan="4" style="text-align:center;padding:20px;color:#dc2626;">Failed to load access list.</td></tr>');
      return;
    }
    window._accessListEmployees = resp.employees;
    renderAccessListRows(resp.employees);
  }).fail(function() {
    tbody.html('<tr><td colspan="4" style="text-align:center;padding:20px;color:#dc2626;">Error loading access list. Please try again.</td></tr>');
  });
}

function renderAccessListRows(list) {
  var tbody = $('#accessListTableBody');
  if(!list || list.length === 0) {
    tbody.html('<tr><td colspan="4" style="text-align:center;padding:25px;color:#94a3b8;">No active employees found.</td></tr>');
    $('#accessListCountBadge').text('0 employees');
    return;
  }
  
  var grantedCount = 0;
  var html = '';
  for(var i = 0; i < list.length; i++) {
    var e = list[i];
    var isGranted = (e.can_view_admin === 'Yes');
    if(isGranted) grantedCount++;
    
    var isMasterSuper = (
      (e.name && e.name.toLowerCase().indexOf('abishek') !== -1) ||
      (e.email && e.email.toLowerCase().indexOf('abishek.veeraswamy@fleet.abra-travels.com') !== -1) ||
      (e.employee_id === 'ABRA001')
    );
    
    html += '<tr class="access-row" data-search="' + (e.name + ' ' + (e.department||'') + ' ' + (e.position||'') + ' ' + e.employee_id).toLowerCase() + '">';
    html += '<td style="padding:10px 14px;">';
    html +=   '<div style="font-weight:700;color:#1e293b;">' + $('<div>').text(e.name).html() + '</div>';
    html +=   '<div style="font-size:11px;color:#64748b;">' + $('<div>').text(e.employee_id + (e.email ? ' • ' + e.email : '')).html() + '</div>';
    html += '</td>';
    html += '<td style="padding:10px 14px;color:#475569;font-size:12px;">' + $('<div>').text(e.department || '—').html() + '</td>';
    html += '<td style="padding:10px 14px;color:#475569;font-size:12px;">' + $('<div>').text(e.position || '—').html() + '</td>';
    html += '<td style="padding:10px 14px;text-align:center;vertical-align:middle;">';
    
    if(isMasterSuper) {
      html += '<span style="background:#dcfce7;color:#15803d;padding:4px 10px;border-radius:20px;font-size:11px;font-weight:700;"><i class="fas fa-crown"></i> Super Admin</span>';
    } else {
      var checked = isGranted ? 'checked' : '';
      var labelText = isGranted ? 'Enabled' : 'Disabled';
      var labelColor = isGranted ? '#059669' : '#94a3b8';
      
      html += '<label style="display:inline-flex;align-items:center;gap:8px;cursor:pointer;margin:0;">';
      html +=   '<input type="checkbox" ' + checked + ' data-empid="' + $('<div>').text(e.employee_id).html() + '" data-dbid="' + e.id + '" onchange="toggleAccessPermission(this)" style="width:18px;height:18px;cursor:pointer;accent-color:#2563eb;">';
      html +=   '<span id="access_lbl_' + e.id + '" style="font-size:11px;font-weight:700;color:' + labelColor + ';">' + labelText + '</span>';
      html += '</label>';
    }
    
    html += '</td>';
    html += '</tr>';
  }
  
  tbody.html(html);
  $('#accessListCountBadge').text(grantedCount + ' of ' + list.length + ' have admin access');
}

function filterAccessListTable() {
  var q = ($('#accessListSearchInput').val() || '').toLowerCase().trim();
  $('.access-row').each(function() {
    var s = $(this).attr('data-search') || '';
    if(!q || s.indexOf(q) !== -1) {
      $(this).show();
    } else {
      $(this).hide();
    }
  });
}

function toggleAccessPermission(cb) {
  var empId = $(cb).attr('data-empid');
  var dbId = parseInt($(cb).attr('data-dbid'), 10);
  var isChecked = cb.checked;
  var newStatus = isChecked ? 'Yes' : 'No';
  var lbl = $('#access_lbl_' + dbId);
  lbl.text('Saving...').css('color', '#d97706');
  
  $.post('<?php echo $_SERVER['PHP_SELF']; ?>', {
    action: 'toggle_attendance_access',
    employee_id: empId,
    employee_db_id: dbId,
    can_view_admin: newStatus
  }, function(res) {
    if(res && res.success) {
      lbl.text(isChecked ? 'Enabled' : 'Disabled').css('color', isChecked ? '#059669' : '#94a3b8');
      if(window._accessListEmployees) {
        for(var i=0; i<window._accessListEmployees.length; i++) {
          if(window._accessListEmployees[i].id == dbId) {
            window._accessListEmployees[i].can_view_admin = newStatus;
            break;
          }
        }
      }
      var count = 0;
      if(window._accessListEmployees) {
        for(var i=0; i<window._accessListEmployees.length; i++) {
          if(window._accessListEmployees[i].can_view_admin === 'Yes') count++;
        }
        $('#accessListCountBadge').text(count + ' of ' + window._accessListEmployees.length + ' have admin access');
      }
    } else {
      cb.checked = !isChecked;
      lbl.text(!isChecked ? 'Enabled' : 'Disabled').css('color', !isChecked ? '#059669' : '#94a3b8');
      alert('Failed to update access: ' + (res.message || 'Unknown error'));
    }
  }, 'json').fail(function() {
    cb.checked = !isChecked;
    lbl.text(!isChecked ? 'Enabled' : 'Disabled').css('color', !isChecked ? '#059669' : '#94a3b8');
    alert('Network error while saving permission.');
  });
}

function showNotCheckedIn()  { $('#notCheckedInModal').modal('show'); }
function showCheckedIn()     { $('#checkedInModal').modal('show'); }
function showLateEmployees() { $('#lateEmployeesModal').modal('show'); }
function showNotLoggedOff()  { $('#notLoggedOffModal').modal('show'); }
function showPresentDays()   { $('#presentDaysModal').modal('show'); }
function showAbsentDays()    { $('#absentDaysModal').modal('show'); }
function showHalfDays()      { $('#halfDaysModal').modal('show'); }

function handleMarkAttendance() {
    // Always use today — skip date picker, go straight to status check
    resetCamera();
    $('#statusPanel').hide();
    $('#markModal').modal('show');
    // Auto-check today's status immediately
    checkDateStatus();
}

function checkDateStatus() {
    var selDate = $('#att_date').val();
    if(!selDate) { alert('Please select a date.'); return; }

    $.getJSON(window.location.pathname + '?action=check_date_status&date=' + selDate, function(data) {
        // Hide all state panels first
        $('#stateAllDone, #stateCheckedInOnly, #stateNothing').hide();
        $('#attFormWrap').show();
        $('#datePickerStep').hide();
        $('#statusPanel').show();

        // Date is always today on server — just reset camera
        resetCamera();
        $('#btnStart').show();
        $('#btnSnap, #btnRetake, #btnSubmit').hide();

        if(data.state === 'all_done') {
            // Both check-in and check-out done — show completion, hide form
            $('#stateAllDone').show();
            $('#stateAllDoneMsg').text(data.msg);
            $('#attFormWrap').hide();

        } else if(data.state === 'checkin_only') {
            // Checked in, needs checkout
            $('#stateCheckedInOnly').show();
            $('#checkedInMsg').text('Checked in at ' + data.checkin_time);
            $('#att_action_type').val('check_out');
            $('#btnSubmitLabel').text('Confirm Check Out');
            // KPI check — only block for today's checkout. Covers Daily
            // (always required same-day), plus Weekly (due Saturday) and
            // Monthly (due month-end) once their deadline has arrived.
            var isToday = (selDate === '<?php echo date('Y-m-d'); ?>');
            if(isToday && todayCheckedIn && (!userKpiComplete || !userWeeklyOk || !userMonthlyOk || !userPlannerOk)) {
                $('#attFormWrap').hide();
                $('#kpiBlockDaily').toggle(!userKpiComplete);
                $('#kpiBlockWeekly').toggle(!userWeeklyOk);
                $('#kpiBlockMonthly').toggle(!userMonthlyOk);
                $('#plannerBlockMonthly').toggle(!userPlannerOk);
                $('#plannerBlockBtn').toggle(!userPlannerOk);
                $('#kpiBlockingModal').modal('show');
                return;
            }
            initGPS();

        } else {
            // Nothing done — check-in mode
            $('#stateNothing').show();
            $('#nothingMsg').text('No attendance for ' + selDate + '. Tap Check In below.');
            $('#att_action_type').val('check_in');
            $('#btnSubmitLabel').text('Confirm Check In');
            initGPS();
        }
    }).fail(function() {
        alert('Could not check attendance status. Please try again.');
    });
}

$(document).ready(function() {
    $('.select2').select2({ width: '100%' });
    <?php if($is_admin && $admin_result && mysqli_num_rows($admin_result) > 0): ?>
    $('#adminTable').DataTable({ pageLength:50, order:[[0,'desc']] });
    <?php endif; ?>
    <?php if($user_emp_data && $my_result && mysqli_num_rows($my_result) > 0): ?>
    $('#personalTable').DataTable({ pageLength:50, order:[[0,'desc']] });
    <?php endif; ?>
    $('#markModal').on('shown.bs.modal', function() { $('.modal-body').scrollTop(0); });
    $('#markModal').on('hidden.bs.modal', function() { if(typeof stream!=='undefined'&&stream) stream.getTracks().forEach(t=>t.stop()); resetCamera(); });
    setTimeout(function() { $('.alert').fadeOut('slow'); }, 6000);
});


function toggleReason(id) {
    var short  = document.getElementById('short_'  + id);
    var full   = document.getElementById('full_'   + id);
    var toggle = document.getElementById('toggle_' + id);
    if (full.style.display === 'none') {
        short.style.display  = 'none';
        full.style.display   = 'inline';
        toggle.textContent   = 'Read less';
    } else {
        short.style.display  = 'inline';
        full.style.display   = 'none';
        toggle.textContent   = 'Read more';
    }
}

function showPhoto(src) { $('#viewImg').attr('src',src); $('#photoModal').modal('show'); }

function deleteAttendance(empId, date, empName) {
  if(!confirm(`⚠️ Delete attendance record?\n\nEmployee: ${empName}\nDate: ${date}\n\nThis action cannot be undone.`)) {
    return;
  }

  $.ajax({
    url: window.location.href,
    type: 'POST',
    data: {
      delete_attendance: 1,
      employee_id: empId,
      date: date
    },
    dataType: 'json',
    success: function(response) {
      if(response.success) {
        alert('✅ ' + response.message);
        location.reload();
      } else {
        alert('❌ Error: ' + response.message);
      }
    },
    error: function() {
      alert('❌ Network error. Please try again.');
    }
  });
}

function initGPS() {
    if(!navigator.geolocation) { $('#gpsStatus').attr('class','gps-status gps-bad').html('<i class="fas fa-times-circle"></i> GPS not supported'); return; }
    navigator.geolocation.getCurrentPosition(function(pos) {
        const lat = pos.coords.latitude, lng = pos.coords.longitude;
        $('#lat').val(lat); $('#lng').val(lng);
        if(bypassLocation) {
            $('#gpsStatus').attr('class','gps-status gps-ok').html('<i class="fas fa-check-circle"></i> Location Verified: Remote/Field Work');
            $('#btnSubmit').prop('disabled',false);
            fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`).then(r=>r.json()).then(d=>$('#loc_name').val(d.display_name)).catch(()=>{});
            return;
        }
        let targetOffices = allOffices;
        if(userAssignedLocation && allOffices[userAssignedLocation]) { targetOffices={}; targetOffices[userAssignedLocation]=allOffices[userAssignedLocation]; }
        let minDist=999999, nearName='Unknown';
        for(let name in targetOffices) {
            let d=getDistance(lat,lng,targetOffices[name].lat,targetOffices[name].lng);
            if(d<minDist){minDist=d;nearName=name;}
        }
        fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`).then(r=>r.json()).then(d=>$('#loc_name').val(d.display_name)).catch(()=>{});
        if(minDist<=200) {
            $('#gpsStatus').attr('class','gps-status gps-ok').html(`<i class="fas fa-check-circle"></i> Verified: ${nearName} (${Math.round(minDist)}m)`);
            $('#btnSubmit').prop('disabled',false);
        } else {
            $('#gpsStatus').attr('class','gps-status gps-bad').html(`<i class="fas fa-times-circle"></i> Too far: ${Math.round(minDist)}m from office`);
        }
    }, function() {
        $('#gpsStatus').attr('class','gps-status gps-bad').html('<i class="fas fa-exclamation-triangle"></i> Please enable GPS');
    }, {enableHighAccuracy:true,timeout:10000,maximumAge:0});
}

function getDistance(lat1,lon1,lat2,lon2) {
    const dLat=(lat2-lat1)*Math.PI/180,dLon=(lon2-lon1)*Math.PI/180;
    const a=Math.sin(dLat/2)*Math.sin(dLat/2)+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
    return 6371*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a))*1000;
}

let stream;
function startCamera() {
    navigator.mediaDevices.getUserMedia({video:{facingMode:'user',width:640,height:480}})
        .then(s=>{stream=s;$('#video')[0].srcObject=s;$('#btnStart').hide();$('#btnSnap').show();})
        .catch(()=>alert("Camera access required"));
}
function takePhoto() {
    const v=$('#video')[0],c=$('#canvas')[0];
    c.width=v.videoWidth;c.height=v.videoHeight;c.getContext('2d').drawImage(v,0,0);
    const data=c.toDataURL('image/png');
    $('#photo_data').val(data);$('#preview').attr('src',data).show();
    $('#video').hide();$('#btnSnap').hide();$('#btnRetake').show();$('#btnSubmit').show();
}
function resetCamera() {
    $('#preview').hide();$('#photo_data').val('');$('#video').show();
    $('#btnRetake').hide();$('#btnSnap').show();$('#btnSubmit').hide();
}
$('#attForm').on('submit',function(e){
    if(!$('#photo_data').val()||!$('#lat').val()||!$('#lng').val()){e.preventDefault();alert("Photo and GPS required");return false;}
});

// ============================================================
// LATE POLICY FUNCTIONS
// ============================================================
function checkLatePolicy() {
    $('#latePolicyModal').modal('show');
    $('#late-policy-list').html('<div class="text-center py-4"><i class="fas fa-spinner fa-spin fa-2x text-muted"></i><p class="mt-2">Checking employees...</p></div>');
    $('#late-policy-result').hide();
    $('#apply-late-policy-btn').hide();

    const _lpEmpFilter = new URLSearchParams(window.location.search).get('employee') || '';
    const _lpDateFrom = new URLSearchParams(window.location.search).get('date_from') || '';
    const _lpDateTo = new URLSearchParams(window.location.search).get('date_to') || '';

    let lpUrl = '?action=check_late_policy';
    if (_lpEmpFilter) lpUrl += '&employee=' + encodeURIComponent(_lpEmpFilter);
    if (_lpDateFrom) lpUrl += '&date_from=' + encodeURIComponent(_lpDateFrom);
    if (_lpDateTo) lpUrl += '&date_to=' + encodeURIComponent(_lpDateTo);

    $.getJSON(lpUrl, function(data) {
        if(data.count === 0) {
            $('#late-policy-list').html('<div style="text-align:center;padding:30px"><i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i><h5 style="margin-top:15px;color:#059669">No employees with 6+ total late days.</h5></div>');
        } else {
            let html = '<table class="table table-bordered table-sm"><thead style="background:#dc2626;color:white;"><tr><th>Employee</th><th>Total Late Days</th><th>Converted to Absent</th><th>Action Needed</th></tr></thead><tbody>';
            let hasPending = false;
            data.flagged.forEach(function(emp) {
                if (emp.pending_absent > 0) hasPending = true;
                let actionText = emp.pending_absent > 0
                    ? '<span class="text-danger"><i class="fas fa-exclamation-triangle"></i> ' + emp.pending_absent + ' pending conversion</span>'
                    : '<span class="text-success"><i class="fas fa-check-circle"></i> Auto-converted</span>';

                html += '<tr><td><strong>' + emp.name + '</strong></td><td><span class="badge badge-warning" style="font-size:13px;color:black;">' + emp.total_late + ' days</span></td><td><span class="badge badge-danger" style="font-size:13px;">' + emp.absents_existing + ' days</span></td><td>' + actionText + '</td></tr>';
            });
            html += '</tbody></table>';
            $('#late-policy-list').html(html);
            if (hasPending) {
                $('#apply-late-policy-btn').show();
            } else {
                $('#apply-late-policy-btn').hide();
            }
        }
    });
}

function applyLatePolicy() {
    if(!confirm('⚠️ This will mark the 5th consecutive late day as ABSENT for all flagged employees.\n\nAre you sure?')) return;
    $('#apply-late-policy-btn').prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Applying...');

    $.getJSON('?action=apply_late_policy', function(data) {
        if(data.count === 0) {
            $('#late-policy-result').html('<div class="alert alert-info">No employees required action.</div>').show();
        } else {
            let html = '<div class="alert alert-success"><strong><i class="fas fa-check-circle"></i> Policy Applied to ' + data.count + ' employee(s):</strong><ul style="margin-top:8px;">';
            data.affected.forEach(function(a) {
                html += '<li>' + a.name + ' — ' + a.date + ' marked as <strong>Absent</strong></li>';
            });
            html += '</ul></div>';
            $('#late-policy-result').html(html).show();
        }
        $('#apply-late-policy-btn').hide();
        $('#late-policy-list').hide();
    });
}

// ============================================================================
// ATTENDANCE OVERVIEW TAB - client-side aggregation, charts, drill-down
// ============================================================================
let atnDistChartObj, atnTrendChartObj, atnDeptChartObj, atnPosChartObj;
const atnStatusMeta = {
    present:  {label:'Present',  color:'#10b981'},
    late:     {label:'Late',     color:'#f59e0b'},
    half_day: {label:'Half Day', color:'#eab308'},
    absent:   {label:'Absent',   color:'#ef4444'}
};

function switchAtnTab(tab) {
    if(tab === 'daily') {
        $('#atnDailyTab').show();
        $('#atnOverviewTab').hide();
        $('#atnTabBtnDaily').css({background:'#1e40af',color:'white'});
        $('#atnTabBtnOverview').css({background:'#e2e8f0',color:'#334155'});
    } else {
        $('#atnDailyTab').hide();
        $('#atnOverviewTab').show();
        $('#atnTabBtnOverview').css({background:'#1e40af',color:'white'});
        $('#atnTabBtnDaily').css({background:'#e2e8f0',color:'#334155'});
        renderAtnOverview();
    }
}

function atnFilteredRecords() {
    const dept = $('#atnDeptFilter').val();
    const pos  = $('#atnPosFilter').val();
    const emp  = $('#atnEmpFilter').val();
    return ovattRecords.filter(function(r) {
        if(dept && r.dept !== dept) return false;
        if(pos && r.pos !== pos) return false;
        if(emp && r.emp !== emp) return false;
        return true;
    });
}

function renderAtnOverview() {
    const recs = atnFilteredRecords();

    // ── STAT CARDS ──
    const counts = {present:0, late:0, half_day:0, absent:0};
    recs.forEach(function(r) { if(counts.hasOwnProperty(r.status)) counts[r.status]++; else counts[r.status] = (counts[r.status]||0)+1; });
    const cardsHtml =
        '<div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-list"></i></div><div class="stat-content"><h3>' + recs.length + '</h3><p>Total Records</p></div></div>' +
        '<div class="stat-card green clickable" onclick="atnShowStatusDetail(\'present\')"><div class="stat-icon green"><i class="fas fa-calendar-check"></i></div><div class="stat-content"><h3>' + (counts.present||0) + '</h3><p>Present</p></div></div>' +
        '<div class="stat-card orange clickable" onclick="atnShowStatusDetail(\'late\')"><div class="stat-icon orange"><i class="fas fa-clock"></i></div><div class="stat-content"><h3>' + (counts.late||0) + '</h3><p>Late</p></div></div>' +
        '<div class="stat-card yellow clickable" onclick="atnShowStatusDetail(\'half_day\')"><div class="stat-icon yellow"><i class="fas fa-adjust"></i></div><div class="stat-content"><h3>' + (counts.half_day||0) + '</h3><p>Half Day</p></div></div>' +
        '<div class="stat-card red clickable" onclick="atnShowStatusDetail(\'absent\')"><div class="stat-icon red"><i class="fas fa-calendar-times"></i></div><div class="stat-content"><h3>' + (counts.absent||0) + '</h3><p>Absent</p></div></div>';
    $('#atnOverviewCards').html(cardsHtml);

    // ── STATUS DISTRIBUTION (doughnut) ──
    const statusKeys = Object.keys(atnStatusMeta).filter(function(k){ return counts[k] > 0; });
    const distCtx = document.getElementById('atnDistChart').getContext('2d');
    if(atnDistChartObj) atnDistChartObj.destroy();
    atnDistChartObj = new Chart(distCtx, {
        type: 'doughnut',
        data: {
            labels: statusKeys.map(function(k){ return atnStatusMeta[k].label; }),
            datasets: [{ data: statusKeys.map(function(k){ return counts[k]; }), backgroundColor: statusKeys.map(function(k){ return atnStatusMeta[k].color; }) }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            onClick: function(evt, els) { if(els.length) atnShowStatusDetail(statusKeys[els[0].index]); },
            plugins: { legend: { position: 'bottom' } }
        }
    });

    // ── DAILY TREND (line, present vs absent vs late vs half-day per date) ──
    const byDate = {};
    recs.forEach(function(r) {
        if(!byDate[r.date]) byDate[r.date] = {present:0, late:0, half_day:0, absent:0};
        if(byDate[r.date].hasOwnProperty(r.status)) byDate[r.date][r.status]++;
    });
    const dateKeys = Object.keys(byDate).sort();
    const trendCtx = document.getElementById('atnTrendChart').getContext('2d');
    if(atnTrendChartObj) atnTrendChartObj.destroy();
    atnTrendChartObj = new Chart(trendCtx, {
        type: 'line',
        data: {
            labels: dateKeys,
            datasets: Object.keys(atnStatusMeta).map(function(k) {
                return { label: atnStatusMeta[k].label, data: dateKeys.map(function(d){ return byDate[d][k]||0; }), borderColor: atnStatusMeta[k].color, backgroundColor: atnStatusMeta[k].color, tension: 0.25 };
            })
        },
        options: {
            onClick: function(evt) {
                const elements = atnTrendChartObj.getElementsAtEventForMode(evt, 'nearest', {intersect: true}, true);
                if(!elements.length) return;
                const el = elements[0];
                const clickedStatus = Object.keys(atnStatusMeta)[el.datasetIndex];
                atnShowDateDetail(dateKeys[el.index], clickedStatus);
            },
            interaction: { mode: 'nearest', intersect: true },
            scales: { y: { beginAtZero: true, ticks: { precision: 0 } } }
        }
    });

    // ── DEPARTMENT BREAKDOWN (vertical bars) ──
    const byDept = {};
    recs.forEach(function(r) {
        const d = r.dept || 'Unassigned';
        if(!byDept[d]) byDept[d] = {present:0, late:0, half_day:0, absent:0};
        if(byDept[d].hasOwnProperty(r.status)) byDept[d][r.status]++;
    });
    const deptKeys = Object.keys(byDept).sort();
    const deptCtx = document.getElementById('atnDeptChart').getContext('2d');
    if(atnDeptChartObj) atnDeptChartObj.destroy();
    atnDeptChartObj = new Chart(deptCtx, {
        type: 'bar',
        data: {
            labels: deptKeys,
            datasets: Object.keys(atnStatusMeta).map(function(k) {
                return {
                    label: atnStatusMeta[k].label,
                    data: deptKeys.map(function(d){ return byDept[d][k]||0; }),
                    backgroundColor: atnStatusMeta[k].color,
                    borderRadius: 4,
                    borderSkipped: false,
                    barPercentage: 1.0,
                    categoryPercentage: 0.8,
                    maxBarThickness: 26
                };
            })
        },
        options: {
            onClick: function(evt) {
                const elements = atnDeptChartObj.getElementsAtEventForMode(evt, 'nearest', {intersect: true}, true);
                if(!elements.length) return;
                const el = elements[0];
                const clickedStatus = Object.keys(atnStatusMeta)[el.datasetIndex];
                atnShowDeptDetail(deptKeys[el.index], clickedStatus);
            },
            interaction: { mode: 'nearest', intersect: true },
            layout: { padding: { top: 4 } },
            plugins: { legend: { position: 'top', labels: { usePointStyle: true, boxWidth: 8 } } },
            scales: {
                x: { stacked: true, grid: { display: false } },
                y: { stacked: true, beginAtZero: true, ticks: { precision: 0 }, grid: { color: '#f1f5f9' } }
            }
        }
    });

    // ── POSITION BREAKDOWN (same style as Department Breakdown) ──
    const byPos = {};
    recs.forEach(function(r) {
        const p = r.pos || 'Unassigned';
        if(!byPos[p]) byPos[p] = {present:0, late:0, half_day:0, absent:0};
        if(byPos[p].hasOwnProperty(r.status)) byPos[p][r.status]++;
    });
    const posKeys = Object.keys(byPos).sort();
    const posCtx = document.getElementById('atnPosChart').getContext('2d');
    if(atnPosChartObj) atnPosChartObj.destroy();
    atnPosChartObj = new Chart(posCtx, {
        type: 'bar',
        data: {
            labels: posKeys,
            datasets: Object.keys(atnStatusMeta).map(function(k) {
                return {
                    label: atnStatusMeta[k].label,
                    data: posKeys.map(function(p){ return byPos[p][k]||0; }),
                    backgroundColor: atnStatusMeta[k].color,
                    borderRadius: 4,
                    borderSkipped: false,
                    barPercentage: 1.0,
                    categoryPercentage: 0.8,
                    maxBarThickness: 26
                };
            })
        },
        options: {
            onClick: function(evt) {
                const elements = atnPosChartObj.getElementsAtEventForMode(evt, 'nearest', {intersect: true}, true);
                if(!elements.length) return;
                const el = elements[0];
                const clickedStatus = Object.keys(atnStatusMeta)[el.datasetIndex];
                atnShowPosDetail(posKeys[el.index], clickedStatus);
            },
            interaction: { mode: 'nearest', intersect: true },
            layout: { padding: { top: 4 } },
            plugins: { legend: { position: 'top', labels: { usePointStyle: true, boxWidth: 8 } } },
            scales: {
                x: { stacked: true, grid: { display: false } },
                y: { stacked: true, beginAtZero: true, ticks: { precision: 0 }, grid: { color: '#f1f5f9' } }
            }
        }
    });

    // ── EMPLOYEE LEADERBOARD ──
    const byEmp = {};
    recs.forEach(function(r) {
        if(!byEmp[r.emp]) byEmp[r.emp] = {name:r.name, dept:r.dept, pos:r.pos, present:0, late:0, half_day:0, absent:0};
        if(byEmp[r.emp].hasOwnProperty(r.status)) byEmp[r.emp][r.status]++;
    });
    const empRows = Object.keys(byEmp).map(function(eid){ return Object.assign({emp:eid}, byEmp[eid]); });
    empRows.sort(function(a,b){ return b.present - a.present; });
    let empHtml = '';
    empRows.forEach(function(e) {
        empHtml += '<tr style="cursor:pointer;" onclick="atnShowEmpDetail(\'' + e.emp + '\')">' +
            '<td><strong>' + e.name + '</strong><br><span style="font-size:11px;color:#64748b;">' + e.emp + '</span></td>' +
            '<td>' + (e.dept||'—') + '</td>' +
            '<td>' + (e.pos||'—') + '</td>' +
            '<td><span class="badge badge-success">' + e.present + '</span></td>' +
            '<td><span class="badge badge-danger">' + e.absent + '</span></td>' +
            '<td><span class="badge badge-warning">' + e.half_day + '</span></td>' +
            '<td><span class="badge badge-warning">' + e.late + '</span></td>' +
        '</tr>';
    });
    $('#atnEmpTableBody').html(empHtml || '<tr><td colspan="7" style="text-align:center;color:#94a3b8;padding:30px;">No records for this range/filter</td></tr>');
    if($.fn.DataTable.isDataTable('#atnEmpTable')) $('#atnEmpTable').DataTable().destroy();
    $('#atnEmpTable').DataTable({ pageLength: 10, order: [] });
}

function atnRenderDetailRows(recs) {
    if(!recs.length) return '<p style="text-align:center;color:#94a3b8;padding:20px;">No records found.</p>';
    let html = '<div style="display:flex;flex-direction:column;gap:8px;">';
    recs.forEach(function(r) {
        const meta = atnStatusMeta[r.status] || {label: r.status, color:'#64748b'};
        html += '<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 14px;background:#f8fafc;border-radius:8px;border-left:4px solid ' + meta.color + ';">' +
            '<div><strong>' + r.name + '</strong><br><span style="font-size:11px;color:#64748b;">' + r.emp + ' &nbsp;|&nbsp; ' + (r.dept||'—') + '</span></div>' +
            '<div style="text-align:right;"><span class="badge" style="background:' + meta.color + ';color:white;">' + meta.label + '</span><br><span style="font-size:11px;color:#64748b;">' + r.date + '</span></div>' +
        '</div>';
    });
    html += '</div>';
    return html;
}

function atnOpenDetail(title, recs) {
    $('#atnDetailTitle').text(title + ' (' + recs.length + ')');
    $('#atnDetailBody').html(atnRenderDetailRows(recs));
    $('#atnDetailModalBackdrop').css('display', 'block');
}
function closeAtnDetail() { $('#atnDetailModalBackdrop').css('display', 'none'); }

function atnShowStatusDetail(status) {
    const recs = atnFilteredRecords().filter(function(r){ return r.status === status; });
    atnOpenDetail((atnStatusMeta[status] ? atnStatusMeta[status].label : status) + ' Records', recs);
}
function atnShowDateDetail(date, status) {
    let recs = atnFilteredRecords().filter(function(r){ return r.date === date; });
    let title = 'Records for ' + date;
    if(status) {
        recs = recs.filter(function(r){ return r.status === status; });
        title = (atnStatusMeta[status] ? atnStatusMeta[status].label : status) + ' — ' + date;
    }
    atnOpenDetail(title, recs);
}
function atnShowDeptDetail(dept, status) {
    let recs = atnFilteredRecords().filter(function(r){ return r.dept === dept; });
    let title = dept + ' Department Records';
    if(status) {
        recs = recs.filter(function(r){ return r.status === status; });
        title = dept + ' — ' + (atnStatusMeta[status] ? atnStatusMeta[status].label : status) + ' Records';
    }
    atnOpenDetail(title, recs);
}
function atnShowPosDetail(pos, status) {
    let recs = atnFilteredRecords().filter(function(r){ return r.pos === pos; });
    let title = pos + ' Position Records';
    if(status) {
        recs = recs.filter(function(r){ return r.status === status; });
        title = pos + ' — ' + (atnStatusMeta[status] ? atnStatusMeta[status].label : status) + ' Records';
    }
    atnOpenDetail(title, recs);
}
function atnShowEmpDetail(empId) {
    const recs = atnFilteredRecords().filter(function(r){ return r.emp === empId; });
    const nm = recs.length ? recs[0].name : empId;
    atnOpenDetail(nm + ' — Attendance Records', recs);
}
$(document).keyup(function(e){ if(e.key === 'Escape') closeAtnDetail(); });

// Attendance Overview is the default landing tab for the super admin, so
// render its charts/cards immediately on page load instead of waiting for
// a tab click.
$(document).ready(function() {
    <?php if($is_super_admin): ?>
    renderAtnOverview();
    <?php endif; ?>
});

// Load late policy badge count on page load
$(document).ready(function() {
    <?php if($is_admin): ?>
    const _lpEmpFilter = new URLSearchParams(window.location.search).get('employee') || '';
    const _lpDateFrom = new URLSearchParams(window.location.search).get('date_from') || '';
    const _lpDateTo = new URLSearchParams(window.location.search).get('date_to') || '';

    let lpUrl = '?action=check_late_policy';
    if (_lpEmpFilter) lpUrl += '&employee=' + encodeURIComponent(_lpEmpFilter);
    if (_lpDateFrom) lpUrl += '&date_from=' + encodeURIComponent(_lpDateFrom);
    if (_lpDateTo) lpUrl += '&date_to=' + encodeURIComponent(_lpDateTo);

    $.getJSON(lpUrl, function(data) {
        $('#late-policy-count').text(data.count);
        if(data.count > 0) {
            $('#late-policy-badge').show();
        }
    });
    <?php endif; ?>
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