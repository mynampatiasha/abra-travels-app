<?php 
// ============================================================================
// ATTENDANCE SYSTEM - FLEET VERSION (Full Feature Parity)
// ✅ Email-based auth via ?user_email= (Flutter WebView)
// ✅ HR Attendance Overrides (holiday/leave marking by admin)
// ✅ Midnight crossover detection (night shift checkout)
// ✅ att_date_input date picker (yesterday checkout support)
// ✅ check_date_status AJAX handler
// ✅ delete_attendance admin handler
// ✅ UNION query: real attendance + overrides in admin view
// ✅ Override-aware stats (checked-in, not-checked-in)
// ============================================================================
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);
date_default_timezone_set('Asia/Kolkata');

session_start();

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed");
mysqli_set_charset($con, 'utf8mb4');

// ============================================================================
// ENSURE hr_attendance_overrides TABLE EXISTS
// ============================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS `hr_attendance_overrides` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `employee_id` INT(11) NOT NULL,
  `attendance_date` DATE NOT NULL,
  `status` ENUM('present','absent','holiday','leave','half_day') NOT NULL DEFAULT 'present',
  `reason` TEXT NULL,
  `created_by` VARCHAR(100) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_emp_date` (`employee_id`, `attendance_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// ✅ FLUTTER WEBVIEW: Accept email from URL parameter
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';

// If email came from Flutter, skip the isUser() session check
if(empty($currentUserEmail)) {
    isUser();
}

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// // ============================================================================
// // ROLE DETECTION (UPDATED TO MATCH KPI EVALUATION STRUCTURE)
// // ============================================================================
//  $is_super_admin = (stripos($currentUserName, 'Abishek') !== false || stripos($currentUserName, 'abishek') !== false);
//  $is_keerti = (stripos($currentUserName, 'Keerti') !== false || stripos($currentUserName, 'Keerthi') !== false);

// // Check if user is Managing Director (can see everyone)
//  $is_managing_director = false;
// if($user_emp_data) {
//     $user_position = isset($user_emp_data['position']) ? $user_emp_data['position'] : '';
//     $is_managing_director = (stripos($user_position, 'managing director') !== false || 
//                              stripos($user_position, 'md') !== false ||
//                              stripos($user_position, 'ceo') !== false);
// }

// // Check if user is a Reporting Manager (can see their team)
// $is_reporting_manager = false;
// $managed_employees = [];

// if($user_emp_data) {
//     $emp_id_safe = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
    
//     // Find all employees where current user is reporting_manager_1 or reporting_manager_2
//     $manager_query = mysqli_query($con, "
//         SELECT employee_id, name, department, position 
//         FROM hr_employees 
//         WHERE (
//             reporting_manager_1 = '$emp_id_safe' 
//             OR reporting_manager_2 = '$emp_id_safe'
//             OR reporting_manager_1 LIKE '%($emp_id_safe)%'
//             OR reporting_manager_2 LIKE '%($emp_id_safe)%'
//         )
//         AND status = 'active'
//         ORDER BY name ASC
//     ");
    
//     if ($manager_query && mysqli_num_rows($manager_query) > 0) {
//         $is_reporting_manager = true;
//         while ($emp = mysqli_fetch_assoc($manager_query)) {
//             $managed_employees[$emp['employee_id']] = $emp;
//         }
//     }
// }

// // Final admin flag (matches KPI evaluation logic)
// $is_admin = ($is_super_admin || $is_keerti || $is_managing_director);

// ============================================================================
// AJAX: CHECK ATTENDANCE STATUS FOR A DATE
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'check_date_status') {
    // Need user_emp_data first — do a quick lookup
    $tmp_email = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';
    $tmp_emp = null;
    if(!empty($tmp_email)) {
        $tmp_e = mysqli_real_escape_string($con, $tmp_email);
        $tmp_q = mysqli_query($con, "SELECT * FROM hr_employees WHERE (email='$tmp_e' OR personal_email='$tmp_e') AND status='active' LIMIT 1");
        if($tmp_q && mysqli_num_rows($tmp_q) > 0) $tmp_emp = mysqli_fetch_assoc($tmp_q);
    }
    header('Content-Type: application/json');
    if(!$tmp_emp) { echo json_encode(['state'=>'nothing','msg'=>'Employee not found']); exit; }
    $chk_date = mysqli_real_escape_string($con, $_GET['date'] ?? date('Y-m-d'));
    $emp_id_s = mysqli_real_escape_string($con, $tmp_emp['employee_id']);
    $rec = mysqli_query($con, "SELECT * FROM hr_attendance WHERE employee_id='$emp_id_s' AND date='$chk_date' LIMIT 1");
    $row = $rec ? mysqli_fetch_assoc($rec) : null;
    if(!$row) {
        echo json_encode(['state'=>'nothing', 'msg'=>'No attendance marked for ' . date('D, d M Y', strtotime($chk_date)) . '. You can Check In now.']);
    } elseif(!empty($row['check_in_time']) && empty($row['check_out_time'])) {
        echo json_encode(['state'=>'checkin_only', 'checkin_time'=>date('h:i A', strtotime($row['check_in_time'])), 'msg'=>'Checked in at ' . date('h:i A', strtotime($row['check_in_time'])) . ' on ' . date('D, d M Y', strtotime($chk_date)) . '. Check Out pending.']);
    } else {
        echo json_encode(['state'=>'all_done', 'checkin_time'=>date('h:i A', strtotime($row['check_in_time'])), 'checkout_time'=>date('h:i A', strtotime($row['check_out_time'])), 'msg'=>'Check In: ' . date('h:i A', strtotime($row['check_in_time'])) . ' → Check Out: ' . date('h:i A', strtotime($row['check_out_time']))]);
    }
    exit;
}

// ============================================================================
// EXPORT FUNCTIONALITY (with Day column, override-aware)
// ============================================================================
if(isset($_GET['action']) && $_GET['action'] == 'export') {
    $export_type = isset($_GET['export_type']) ? $_GET['export_type'] : 'admin';
    
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=attendance_export_' . date('Y-m-d') . '.csv');
    
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($output, ['Date', 'Day', 'Employee ID', 'Employee Name', 'Check In Time', 'Check Out Time', 'Work Hours', 'Status', 'Check In Location']);
    
    if($export_type == 'personal' && !empty($currentUserEmail)) {
        // Need emp data for personal export
        $pe_safe = mysqli_real_escape_string($con, $currentUserEmail);
        $pe_q = mysqli_query($con, "SELECT * FROM hr_employees WHERE (email='$pe_safe' OR personal_email='$pe_safe') AND status='active' LIMIT 1");
        if($pe_q && mysqli_num_rows($pe_q) > 0) {
            $pe_emp = mysqli_fetch_assoc($pe_q);
            $emp_id = mysqli_real_escape_string($con, $pe_emp['employee_id']);
            $mf_start = isset($_GET['mf_start']) ? mysqli_real_escape_string($con, $_GET['mf_start']) : date('Y-m-d', strtotime('monday this week'));
            $mf_end   = isset($_GET['mf_end'])   ? mysqli_real_escape_string($con, $_GET['mf_end'])   : date('Y-m-d');
            $res = mysqli_query($con, "SELECT a.* FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE a.employee_id = '$emp_id' AND a.date BETWEEN '$mf_start' AND '$mf_end' AND ao.id IS NULL ORDER BY a.date DESC");
            while($row = mysqli_fetch_assoc($res)) {
                fputcsv($output, [date('Y-m-d', strtotime($row['date'])), date('l', strtotime($row['date'])), $row['employee_id'], $row['employee_name'], date('H:i:s', strtotime($row['check_in_time'])), $row['check_out_time'] ? date('H:i:s', strtotime($row['check_out_time'])) : 'Not Checked Out', $row['work_hours'] ? $row['work_hours'].' hours' : '0', ucfirst($row['status']), $row['check_in_location']]);
            }
        }
    } else {
        $date_from  = isset($_GET['date_from']) ? mysqli_real_escape_string($con, $_GET['date_from']) : date('Y-m-d');
        $date_to    = isset($_GET['date_to'])   ? mysqli_real_escape_string($con, $_GET['date_to'])   : date('Y-m-d');
        $emp_filter = isset($_GET['employee'])  ? mysqli_real_escape_string($con, $_GET['employee'])  : '';
        $where = ["a.date BETWEEN '$date_from' AND '$date_to'"];
        if($emp_filter) $where[] = "a.employee_id = '$emp_filter'";
        $res = mysqli_query($con, "SELECT a.* FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE " . implode(' AND ', $where) . " AND ao.id IS NULL ORDER BY a.date DESC, a.employee_name ASC");
        while($row = mysqli_fetch_assoc($res)) {
            fputcsv($output, [date('Y-m-d', strtotime($row['date'])), date('l', strtotime($row['date'])), $row['employee_id'], $row['employee_name'], date('H:i:s', strtotime($row['check_in_time'])), $row['check_out_time'] ? date('H:i:s', strtotime($row['check_out_time'])) : 'Not Checked Out', $row['work_hours'] ? $row['work_hours'].' hours' : '0', ucfirst($row['status']), $row['check_in_location']]);
        }
    }
    
    fclose($output);
    exit;
}

// ============================================================================
// DELETE ATTENDANCE (ADMIN ONLY)
// ============================================================================
if(isset($_POST['delete_attendance'])) {
    // Quick admin check using email
    $del_email = isset($_POST['user_email']) ? trim($_POST['user_email']) : $currentUserEmail;
    $del_is_admin = false;
    if(!empty($del_email)) {
        $de_safe = mysqli_real_escape_string($con, $del_email);
        $de_q = mysqli_query($con, "SELECT position, department FROM hr_employees WHERE (email='$de_safe' OR personal_email='$de_safe') AND status='active' LIMIT 1");
        if($de_q && mysqli_num_rows($de_q) > 0) {
            $de_row = mysqli_fetch_assoc($de_q);
            $del_is_admin = (
                stripos($de_row['position'], 'managing director') !== false ||
                stripos($de_row['position'], 'md') !== false ||
                stripos($de_row['position'], 'ceo') !== false ||
                stripos($de_row['department'], 'hr') !== false ||
                stripos($de_row['department'], 'human resource') !== false ||
                stripos($de_row['department'], 'management') !== false
            );
        }
    }
    header('Content-Type: application/json');
    if(!$del_is_admin) { echo json_encode(['success'=>false,'message'=>'Not authorized']); exit; }
    try {
        $del_emp_id = mysqli_real_escape_string($con, $_POST['employee_id']);
        $del_date   = mysqli_real_escape_string($con, $_POST['date']);
        // Get internal employee id for override table
        $emp_int_q = mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id='$del_emp_id' LIMIT 1");
        $emp_int_id = null;
        if($emp_int_q && mysqli_num_rows($emp_int_q) > 0) $emp_int_id = mysqli_fetch_assoc($emp_int_q)['id'];
        // Delete attendance
        mysqli_query($con, "DELETE FROM hr_attendance WHERE employee_id='$del_emp_id' AND date='$del_date'");
        $att_rows = mysqli_affected_rows($con);
        // Delete override if exists
        $ov_rows = 0;
        if($emp_int_id) {
            mysqli_query($con, "DELETE FROM hr_attendance_overrides WHERE employee_id=$emp_int_id AND attendance_date='$del_date'");
            $ov_rows = mysqli_affected_rows($con);
        }
        $total = $att_rows + $ov_rows;
        if($total > 0) echo json_encode(['success'=>true,'message'=>"Attendance deleted ($total record(s) removed)"]);
        else echo json_encode(['success'=>false,'message'=>'No matching record found']);
    } catch(Exception $e) {
        echo json_encode(['success'=>false,'message'=>$e->getMessage()]);
    }
    exit;
}

// ============================================================================
// GET EMPLOYEE DATA
// ============================================================================
// ============================================================================
// GET EMPLOYEE DATA
// ============================================================================
$user_emp_data = null;

// ✅ PRIORITY 1: Email from Flutter WebView URL parameter
if(!empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($con, $currentUserEmail);
    $emp_check = mysqli_query($con, "SELECT * FROM hr_employees WHERE (email = '$email_safe' OR personal_email = '$email_safe') AND status = 'active' LIMIT 1");
    if($emp_check && mysqli_num_rows($emp_check) > 0) {
        $user_emp_data = mysqli_fetch_assoc($emp_check);
        $currentUserName = $user_emp_data['name'];
        $_SESSION['user_name'] = $currentUserName;
    }
}

// ✅ PRIORITY 2: Fallback to session-based name lookup
if(!$user_emp_data && !empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($con, $currentUserName);
    $emp_check = mysqli_query($con, "SELECT * FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) AND status = 'active' LIMIT 1");
    
    if(!$emp_check || mysqli_num_rows($emp_check) == 0) {
        if($is_super_admin) {
            $emp_check = mysqli_query($con, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%abishek%' OR employee_id = 'ABRA001') AND status = 'active' LIMIT 1");
        } elseif($is_keerti) {
            $emp_check = mysqli_query($con, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%keerti%' OR LOWER(name) LIKE '%keerthi%') AND status = 'active' LIMIT 1");
        }
    }
    
    if($emp_check && mysqli_num_rows($emp_check) > 0) {
        $user_emp_data = mysqli_fetch_assoc($emp_check);
    }
}



// ============================================================================
// ROLE DETECTION (UPDATED TO MATCH KPI EVALUATION STRUCTURE)
// ============================================================================
$is_super_admin = (stripos($currentUserName, 'Abishek') !== false || stripos($currentUserName, 'abishek') !== false);
$is_keerti = (stripos($currentUserName, 'Keerti') !== false || stripos($currentUserName, 'Keerthi') !== false);

$is_managing_director = false;
$is_hr_admin = false;
if($user_emp_data) {
    $user_position = isset($user_emp_data['position']) ? $user_emp_data['position'] : '';
    $user_dept = isset($user_emp_data['department']) ? $user_emp_data['department'] : '';
    
    $is_managing_director = (stripos($user_position, 'managing director') !== false || 
                             stripos($user_position, 'md') !== false ||
                             stripos($user_position, 'ceo') !== false);
    
    // Anyone in HR department is admin
    $is_hr_admin = (stripos($user_dept, 'hr') !== false || 
                    stripos($user_dept, 'human resource') !== false);
}

// Check if user is a Reporting Manager (can see their team)
$is_reporting_manager = false;
$managed_employees = [];

if($user_emp_data) {
    $emp_id_safe = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
    
    $manager_query = mysqli_query($con, "
        SELECT employee_id, name, department, position 
        FROM hr_employees 
        WHERE (
            reporting_manager_1 = '$emp_id_safe' 
            OR reporting_manager_2 = '$emp_id_safe'
            OR reporting_manager_1 LIKE '%($emp_id_safe)%'
            OR reporting_manager_2 LIKE '%($emp_id_safe)%'
        )
        AND status = 'active'
        ORDER BY name ASC
    ");
    
    if ($manager_query && mysqli_num_rows($manager_query) > 0) {
        $is_reporting_manager = true;
        while ($emp = mysqli_fetch_assoc($manager_query)) {
            $managed_employees[$emp['employee_id']] = $emp;
        }
    }
}

// Final admin flag (matches KPI evaluation logic)
$is_admin = ($is_super_admin || $is_keerti || $is_managing_director || $is_hr_admin);

// ============================================================================
// EMPLOYEE ATTENDANCE STATUS - UPDATED TO RESPECT DATE FILTERS
// ============================================================================

// ============================================================================
// EMPLOYEE ATTENDANCE STATUS - UPDATED TO RESPECT DATE FILTERS
// ============================================================================
$today = date('Y-m-d');
$employee_stats = [
    'total' => 0,
    'checked_in' => 0,
    'not_checked_in' => 0,
    'late_today' => 0,
    'not_logged_off' => 0,
    'not_checked_in_list' => [],
    'checked_in_list' => [],
    'late_today_list' => [],
    'not_logged_off_list' => []
];

if($is_admin) {
    // Determine the date range for stats (use filter dates if provided, otherwise today)
    $stats_date_from = isset($_GET['date_from']) && !empty($_GET['date_from']) ? $_GET['date_from'] : $today;
    $stats_date_to = isset($_GET['date_to']) && !empty($_GET['date_to']) ? $_GET['date_to'] : $today;
    
    // Check if hire_date column exists
    $check_column = mysqli_query($con, "SHOW COLUMNS FROM hr_employees LIKE 'hire_date'");
    $has_joining_date = ($check_column && mysqli_num_rows($check_column) > 0);
    
    // Debug: Log if hire_date column exists
    error_log("Hire date column exists: " . ($has_joining_date ? "YES" : "NO"));
    
    // Build joining date condition
    $joining_condition = $has_joining_date ? "AND (joining_date IS NULL OR joining_date <= '$stats_date_to')" : "";
    $joining_condition_from = $has_joining_date ? "AND (joining_date IS NULL OR joining_date <= '$stats_date_from')" : "";
    
    // Get total active employees
    $total_emp_query = mysqli_query($con, "SELECT COUNT(*) as total FROM hr_employees WHERE status = 'active'");
    if($total_emp_query) {
        $total_emp = mysqli_fetch_assoc($total_emp_query);
        $employee_stats['total'] = $total_emp['total'];
    }
    
    // ✅ Checked-in count: real attendance + overrides
    $checked_in_count = 0;
    $ci_where = "date BETWEEN '$stats_date_from' AND '$stats_date_to'";
    if(!empty($emp_filter)) $ci_where .= " AND employee_id = '$emp_filter'";
    $r = mysqli_query($con, "SELECT COUNT(DISTINCT employee_id) as cnt FROM hr_attendance WHERE $ci_where");
    if($r) $checked_in_count += intval(mysqli_fetch_assoc($r)['cnt']);
    // Add override-based check-ins
    $ov_ci_where = "ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to' AND ao.status IN ('present','holiday','leave')";
    if(!empty($emp_filter)) $ov_ci_where .= " AND e.employee_id = '$emp_filter'";
    $ov_r = mysqli_query($con, "SELECT COUNT(DISTINCT e.employee_id) as cnt FROM hr_attendance_overrides ao INNER JOIN hr_employees e ON ao.employee_id = e.id WHERE $ov_ci_where");
    if($ov_r) $checked_in_count += intval(mysqli_fetch_assoc($ov_r)['cnt']);
    $employee_stats['checked_in'] = $checked_in_count;
    
    // ✅ Checked-in list: real attendance + overrides
    $ci_list_where = "a.date BETWEEN '$stats_date_from' AND '$stats_date_to'";
    if(!empty($emp_filter)) $ci_list_where .= " AND a.employee_id = '$emp_filter'";
    $r = mysqli_query($con, "SELECT a.employee_id, a.employee_name, a.date, a.check_in_time, a.check_out_time, a.status, e.work_location, e.timings, e.department, 'attendance' as record_type FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id WHERE $ci_list_where ORDER BY a.employee_name ASC, a.date DESC");
    if($r) while($row = mysqli_fetch_assoc($r)) $employee_stats['checked_in_list'][] = $row;
    // Override-based check-ins
    $ov_list_where = "ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to' AND ao.status IN ('present','holiday','leave')";
    if(!empty($emp_filter)) $ov_list_where .= " AND e.employee_id = '$emp_filter'";
    $ov_r = mysqli_query($con, "SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date, '09:00:00' as check_in_time, '18:00:00' as check_out_time, 'present' as status, e.work_location, e.timings, e.department, 'override' as record_type FROM hr_attendance_overrides ao INNER JOIN hr_employees e ON ao.employee_id = e.id WHERE $ov_list_where ORDER BY e.name ASC, ao.attendance_date DESC");
    if($ov_r) while($row = mysqli_fetch_assoc($ov_r)) $employee_stats['checked_in_list'][] = $row;
    
    // Late count
    $late_where = "date BETWEEN '$stats_date_from' AND '$stats_date_to' AND status = 'late'";
    if(!empty($emp_filter)) $late_where .= " AND employee_id = '$emp_filter'";
    $r = mysqli_query($con, "SELECT COUNT(*) as late FROM hr_attendance WHERE $late_where");
    if($r) $employee_stats['late_today'] = mysqli_fetch_assoc($r)['late'];
    
    // Not logged off (past dates, exclude today, exclude overrides)
    $nlo_where = "a.date >= '$stats_date_from' AND a.date < '$today' AND a.check_out_time IS NULL";
    if(!empty($emp_filter)) $nlo_where .= " AND a.employee_id = '$emp_filter'";
    $r = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE $nlo_where AND ao.id IS NULL");
    if($r) $employee_stats['not_logged_off'] = mysqli_fetch_assoc($r)['cnt'];
    
    // ✅ NOT CHECKED IN: day-by-day, exclude Sundays, respect hire date, include overrides
    $emp_where_cond = !empty($emp_filter) ? " AND employee_id = '$emp_filter'" : "";
    $all_emp_cols = $has_joining_date ? "employee_id, name, work_location, timings, department, hire_date, id as emp_db_id" : "employee_id, name, work_location, timings, department, id as emp_db_id";
    $all_employees_query = mysqli_query($con, "SELECT $all_emp_cols FROM hr_employees WHERE status = 'active'$emp_where_cond ORDER BY name ASC");
    
    $not_checked_employees = [];
    
    if($all_employees_query) {
        while($emp = mysqli_fetch_assoc($all_employees_query)) {
            $emp_start_date = $stats_date_from;
            $emp_joining_date = null;
            
            if($has_joining_date && !empty($emp['hire_date']) && $emp['hire_date'] != '0000-00-00') {
                $emp_joining_date = $emp['hire_date'];
                if(strtotime($emp_joining_date) > strtotime($stats_date_to)) continue;
                if(strtotime($emp_joining_date) > strtotime($stats_date_from)) $emp_start_date = $emp_joining_date;
            }
            
            // Real attendance dates
            $att_q = mysqli_query($con, "SELECT DISTINCT date FROM hr_attendance WHERE employee_id = '{$emp['employee_id']}' AND date BETWEEN '$emp_start_date' AND '$stats_date_to'");
            $attended_dates = [];
            if($att_q) while($a = mysqli_fetch_assoc($att_q)) $attended_dates[] = $a['date'];
            
            // Override dates (present/holiday/leave)
            $override_dates = [];
            if(!empty($emp['emp_db_id'])) {
                $ov_q = mysqli_query($con, "SELECT DISTINCT attendance_date FROM hr_attendance_overrides WHERE employee_id = {$emp['emp_db_id']} AND attendance_date BETWEEN '$emp_start_date' AND '$stats_date_to' AND status IN ('present','holiday','leave')");
                if($ov_q) while($ov = mysqli_fetch_assoc($ov_q)) $override_dates[] = $ov['attendance_date'];
            }
            
            $covered_dates = array_unique(array_merge($attended_dates, $override_dates));
            
            $missing_dates = [];
            $current_date = $emp_start_date;
            while(strtotime($current_date) <= strtotime($stats_date_to)) {
                $day_of_week = date('w', strtotime($current_date));
                if($day_of_week != 0 && !in_array($current_date, $covered_dates)) {
                    $missing_dates[] = $current_date;
                }
                $current_date = date('Y-m-d', strtotime($current_date . ' +1 day'));
            }
            
            if(count($missing_dates) > 0) {
                $emp['missing_dates'] = $missing_dates;
                $emp['missing_count'] = count($missing_dates);
                $emp['emp_start_date'] = $emp_start_date;
                $not_checked_employees[] = $emp;
            }
        }
    }
    
    $employee_stats['not_checked_in'] = count($not_checked_employees);
    $employee_stats['not_checked_in_list'] = $not_checked_employees;
    
    // Late list
    $late_list_where = "a.date >= '$stats_date_from' AND a.date <= '$stats_date_to' AND a.status = 'late'";
    if(!empty($emp_filter)) $late_list_where .= " AND a.employee_id = '$emp_filter'";
    $late_list_query = mysqli_query($con, "SELECT a.employee_id, a.employee_name, a.check_in_time, a.date, e.work_location, e.timings FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id WHERE $late_list_where ORDER BY a.date DESC, a.employee_name ASC");
    if($late_list_query) while($emp = mysqli_fetch_assoc($late_list_query)) $employee_stats['late_today_list'][] = $emp;
    
    // Not logged off list (exclude overrides)
    $nlo_list_where = "a.date >= '$stats_date_from' AND a.date < '$today' AND a.check_out_time IS NULL";
    if(!empty($emp_filter)) $nlo_list_where .= " AND a.employee_id = '$emp_filter'";
    $nlo_list_query = mysqli_query($con, "SELECT a.employee_id, a.employee_name, a.check_in_time, a.date, e.work_location, e.timings FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE $nlo_list_where AND ao.id IS NULL ORDER BY a.date DESC, a.employee_name ASC");
    if($nlo_list_query) while($emp = mysqli_fetch_assoc($nlo_list_query)) $employee_stats['not_logged_off_list'][] = $emp;
}

// ============================================================================
// LOAD LOCATIONS
// ============================================================================
$all_valid_offices = array();
$locations_query = mysqli_query($con, "SELECT location_name, latitude, longitude FROM hr_work_locations WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND latitude != 0 AND longitude != 0 ORDER BY location_name ASC");
if($locations_query && mysqli_num_rows($locations_query) > 0) {
    while($loc_row = mysqli_fetch_assoc($locations_query)) {
        $all_valid_offices[$loc_row['location_name']] = array(
            'lat' => floatval($loc_row['latitude']),
            'lng' => floatval($loc_row['longitude'])
        );
    }
}

$user_assigned_location = '';
if($user_emp_data && !empty($user_emp_data['work_location'])) {
    if(array_key_exists(trim($user_emp_data['work_location']), $all_valid_offices)) {
        $user_assigned_location = trim($user_emp_data['work_location']);
    }
}

$user_work_timings = '';
$late_time_threshold = '08:15:00';
if($user_emp_data && !empty($user_emp_data['timings'])) {
    $user_work_timings = trim($user_emp_data['timings']);
    if(preg_match('/(\d{1,2}):(\d{2})\s*(AM|PM)?/i', $user_work_timings, $matches)) {
        $hour = intval($matches[1]);
        $minute = $matches[2];
        $meridiem = isset($matches[3]) ? strtoupper($matches[3]) : '';
        if($meridiem == 'PM' && $hour != 12) $hour += 12;
        if($meridiem == 'AM' && $hour == 12) $hour = 0;
        $total_minutes = ($hour * 60) + intval($minute) + 15;
        $late_hour = floor($total_minutes / 60);
        $late_minute = $total_minutes % 60;
        $late_time_threshold = sprintf('%02d:%02d:00', $late_hour, $late_minute);
    }
}

// ============================================================================
// MIDNIGHT CROSSOVER DETECTION
// Employees who check in before midnight can check out after midnight (night shift)
// ============================================================================
$today     = date('Y-m-d');
$yesterday = date('Y-m-d', strtotime('-1 day'));
$current_hour = intval(date('H'));
$is_after_midnight_before_6am = ($current_hour >= 0 && $current_hour < 6);

$pending_yesterday_checkin = null;
if($user_emp_data) {
    $mc_id = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
    $prev_q = mysqli_query($con, "SELECT * FROM hr_attendance WHERE employee_id='$mc_id' AND date='$yesterday' AND check_out_time IS NULL LIMIT 1");
    if($prev_q && mysqli_num_rows($prev_q) > 0 && $is_after_midnight_before_6am) {
        $pending_yesterday_checkin = mysqli_fetch_assoc($prev_q);
    }
}

// ============================================================================
// ATTENDANCE SUBMISSION (WITH DAILY KPI REVIEW CHECK)
// ============================================================================
$error_message = '';
$success_message = '';

if(isset($_POST['submit_attendance']) && $user_emp_data) {
    try {
        $action_type = $_POST['action_type'];
        $latitude = floatval($_POST['latitude']);
        $longitude = floatval($_POST['longitude']);
        $gps_address = mysqli_real_escape_string($con, trim($_POST['location_name']));
        $photo_data = $_POST['photo_data'];
        
        if($latitude == 0 || $longitude == 0) throw new Exception("GPS location missing.");
        if(empty($photo_data)) throw new Exception("Photo required.");
        
        // Check if user is in Sales, Marketing, or Management department (NO LOCATION RESTRICTION)
        $user_department = isset($user_emp_data['department']) ? strtolower(trim($user_emp_data['department'])) : '';
        $bypass_location = (
            stripos($user_department, 'sales') !== false || 
            stripos($user_department, 'marketing') !== false || 
            stripos($user_department, 'management') !== false
        );
        
        $is_within_range = false;
        $matched_location_name = 'Unknown';
        $min_distance = 999999;
        
        if($bypass_location) {
            $is_within_range = true;
            $matched_location_name = 'Remote/Field Work';
        } else {
            $target_offices = $all_valid_offices;
            if(!empty($user_assigned_location)) {
                $target_offices = array($user_assigned_location => $all_valid_offices[$user_assigned_location]);
            }
            
            foreach($target_offices as $office_name => $coords) {
                $dLat = deg2rad($coords['lat'] - $latitude);
                $dLng = deg2rad($coords['lng'] - $longitude);
                $a = sin($dLat/2) * sin($dLat/2) + cos(deg2rad($latitude)) * cos(deg2rad($coords['lat'])) * sin($dLng/2) * sin($dLng/2);
                $c = 2 * atan2(sqrt($a), sqrt(1-$a));
                $dist_m = round(6371 * $c * 1000);
                
                if($dist_m < $min_distance) $min_distance = $dist_m;
                if($dist_m <= 200) {
                    $is_within_range = true;
                    $matched_location_name = $office_name;
                    break;
                }
            }
            
            if(!$is_within_range) {
                throw new Exception("Location Error: You are {$min_distance}m away from office (Max 200m).");
            }
        }
        
        $photo_dir = 'uploads/attendance_photos/' . date('Y/m/');
        if(!file_exists($photo_dir)) mkdir($photo_dir, 0777, true);
        
        $emp_id   = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
        $emp_name = mysqli_real_escape_string($con, $user_emp_data['name']);
        
        $photo_binary = base64_decode(str_replace(['data:image/png;base64,', ' '], ['', '+'], $photo_data));
        $photo_name = preg_replace('/[^A-Za-z0-9\-]/', '', $emp_id) . '_' . date('YmdHis') . '.png';
        $photo_path = $photo_dir . $photo_name;
        file_put_contents($photo_path, $photo_binary);
        
        $now = date('H:i:s');
        $final_loc = mysqli_real_escape_string($con, "$matched_location_name ($gps_address)");
        
        // ✅ Support att_date_input for night shift / yesterday checkout
        $att_date = isset($_POST['att_date_input']) && !empty($_POST['att_date_input'])
                    ? mysqli_real_escape_string($con, $_POST['att_date_input'])
                    : $today;
        
        $check    = mysqli_query($con, "SELECT * FROM hr_attendance WHERE employee_id = '$emp_id' AND date = '$att_date' LIMIT 1");
        $existing = mysqli_fetch_assoc($check);
        
        if($action_type == 'check_in') {
            if($existing) throw new Exception("Already checked in on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_in_time'])) . ".");
            
            $check_hhmm = substr($now, 0, 5);
            $late_hhmm  = substr($late_time_threshold, 0, 5);
            $status = ($check_hhmm > $late_hhmm) ? 'late' : 'present';
            
            mysqli_query($con, "INSERT INTO hr_attendance (employee_id, employee_name, date, check_in_time, check_in_photo, check_in_latitude, check_in_longitude, check_in_location, status, daily_salary) VALUES ('$emp_id', '$emp_name', '$att_date', '$now', '$photo_path', '$latitude', '$longitude', '$final_loc', '$status', '0')");
            $redirect_url = 'https://abra-travels.com/hrm/hr-attendance-list.php?user_email=' . urlencode($currentUserEmail) . '&success=checkin';
            header("Location: $redirect_url"); exit();
            
        } elseif($action_type == 'check_out') {
            if(!$existing) throw new Exception("No check-in found for " . date('D, d M Y', strtotime($att_date)) . ". Please check in first.");
            if(!empty($existing['check_out_time'])) throw new Exception("Already checked out on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_out_time'])) . ".");
            
            // KPI check only required for today's checkout (not backdated)
            if($att_date == $today) {
                $kpi_check = mysqli_query($con, "SELECT id, total_score FROM performance_daily_self WHERE employee_id = '$emp_id' AND review_date = '$today' LIMIT 1");
                if(!$kpi_check || mysqli_num_rows($kpi_check) == 0) {
                    throw new Exception("❌ Daily KPI Review Required: You must complete your Daily Self-Evaluation Review before checking out. Please visit the KPI Evaluation page first.");
                }
                $kpi_record = mysqli_fetch_assoc($kpi_check);
                // score -1 = On Leave, acceptable
            }
            
            // Calculate working hours (supports midnight crossover)
            $checkin_datetime  = $att_date . ' ' . $existing['check_in_time'];
            $checkout_datetime = $today    . ' ' . $now;
            $raw_seconds = strtotime($checkout_datetime) - strtotime($checkin_datetime);
            $raw_hours   = $raw_seconds / 3600;
            $final_hours = ($raw_hours > 1) ? $raw_hours - 1 : $raw_hours; // deduct 1hr lunch
            $hours = max(0, round($final_hours, 2));
            
            mysqli_query($con, "UPDATE hr_attendance SET check_out_time='$now', check_out_photo='$photo_path', check_out_latitude='$latitude', check_out_longitude='$longitude', check_out_location='$final_loc', work_hours='$hours' WHERE id={$existing['id']}");
            $redirect_url = 'https://abra-travels.com/hrm/hr-attendance-list.php?user_email=' . urlencode($currentUserEmail) . '&success=checkout';
            header("Location: $redirect_url"); exit();
        }
    } catch (Exception $e) {
        $error_message = "⚠️ " . $e->getMessage();
    }
}
if(isset($_GET['success'])) $success_message = ($_GET['success'] == 'checkin') ? "✓ Check-In Recorded!" : "✓ Check-Out Recorded!";

// ============================================================================
// DATA FETCH
// ============================================================================
$admin_result = false;
$admin_stats = ['total'=>0, 'present'=>0, 'late'=>0, 'hours'=>0];

if($is_admin) {
    // DEFAULT: Show today's records for admin
    $today = date('Y-m-d');
    $date_from = isset($_GET['date_from']) ? $_GET['date_from'] : $today;
    $date_to = isset($_GET['date_to']) ? $_GET['date_to'] : $today;
    $emp_filter = isset($_GET['employee']) ? mysqli_real_escape_string($con, $_GET['employee']) : '';
    
    $where = ["a.date BETWEEN '$date_from' AND '$date_to'"];
    if($emp_filter) $where[] = "a.employee_id = '$emp_filter'";
    
    $q_stats = mysqli_query($con, "SELECT COUNT(*) as total, COUNT(CASE WHEN a.status='present' THEN 1 END) as present, COUNT(CASE WHEN a.status='late' THEN 1 END) as late, SUM(a.work_hours) as hours FROM hr_attendance a LEFT JOIN hr_employees e ON a.employee_id = e.employee_id LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date WHERE " . implode(' AND ', $where) . " AND ao.id IS NULL");
    if($q_stats) $admin_stats = mysqli_fetch_assoc($q_stats);

    // ✅ UNION query: real attendance + HR overrides
    $admin_result = mysqli_query($con, "
        SELECT a.*, 'attendance' as record_type FROM hr_attendance a
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date
        WHERE " . implode(' AND ', $where) . " AND ao.id IS NULL

        UNION ALL

        SELECT
            NULL as id, e.employee_id, e.name as employee_name, ao.attendance_date as date,
            '09:00:00' as check_in_time, '18:00:00' as check_out_time, '8' as work_hours,
            CASE WHEN ao.status IN ('present','holiday','leave') THEN 'present' ELSE ao.status END as status,
            NULL as check_in_photo, NULL as check_out_photo,
            NULL as check_in_latitude, NULL as check_in_longitude, NULL as check_in_location,
            NULL as check_out_latitude, NULL as check_out_longitude, NULL as check_out_location,
            NULL as daily_salary, 'override' as record_type
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$date_from' AND '$date_to'
        " . ($emp_filter ? "AND e.employee_id = '$emp_filter'" : "") . "

        ORDER BY date DESC, check_in_time DESC LIMIT 500
    ");
    
    $emp_list_query = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE status = 'active' ORDER BY name ASC");
}

$my_result = false;
$my_stats = ['total'=>0, 'present'=>0, 'late'=>0, 'hours'=>0];
$today_record = null;

if($user_emp_data) {
    $my_id = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
    
    $today_q = mysqli_query($con, "SELECT * FROM hr_attendance WHERE employee_id = '$my_id' AND date = '" . date('Y-m-d') . "'");
    if($today_q) $today_record = mysqli_fetch_assoc($today_q);
    
    // UPDATED LOGIC: DEFAULT TO CURRENT WEEK (Monday to Today/Sunday)
    $start_of_week = date('Y-m-d', strtotime('monday this week'));
    
    $mf_start = isset($_GET['mf_start']) ? mysqli_real_escape_string($con, $_GET['mf_start']) : $start_of_week;
    $mf_end = isset($_GET['mf_end']) ? mysqli_real_escape_string($con, $_GET['mf_end']) : date('Y-m-d');
    
    $my_where = ["employee_id = '$my_id'"];
    if($mf_start) $my_where[] = "date >= '$mf_start'";
    if($mf_end) $my_where[] = "date <= '$mf_end'";
    $my_sql_w = implode(' AND ', $my_where);
    
    $mq_stats = mysqli_query($con, "SELECT COUNT(*) as total, COUNT(CASE WHEN status='present' THEN 1 END) as present, COUNT(CASE WHEN status='late' THEN 1 END) as late, SUM(work_hours) as hours FROM hr_attendance WHERE $my_sql_w");
    if($mq_stats) $my_stats = mysqli_fetch_assoc($mq_stats);
    
    // Order by Date DESC (Latest first) is already handled here
    $my_result = mysqli_query($con, "SELECT * FROM hr_attendance WHERE $my_sql_w ORDER BY date DESC, check_in_time DESC LIMIT 500");
}

// Check if user has completed today's attendance
$user_attendance_complete = false;
if($today_record && !empty($today_record['check_out_time'])) {
    $user_attendance_complete = true;
}

// Check if user has completed today's KPI review
$user_kpi_complete = false;
$user_kpi_score = null;
if($user_emp_data) {
    $emp_id_safe = mysqli_real_escape_string($con, $user_emp_data['employee_id']);
    // CRITICAL FIX: Check if submitted_at is NOT NULL to ensure review is actually completed
    $kpi_check = mysqli_query($con, "SELECT id, total_score, submitted_at FROM performance_daily_self WHERE employee_id = '$emp_id_safe' AND review_date = '$today' AND submitted_at IS NOT NULL LIMIT 1");
    if($kpi_check && mysqli_num_rows($kpi_check) > 0) {
        $user_kpi_complete = true;
        $kpi_data = mysqli_fetch_assoc($kpi_check);
        $user_kpi_score = $kpi_data['total_score'];
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Attendance | <?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'CRM'; ?></title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/css/select2.min.css" />
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
  
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    .container-fluid { max-width: 1600px; margin: 0 auto; padding: 0 20px; }
    .alert-container { position: fixed; top: 20px; right: 20px; z-index: 9999; min-width: 300px; }
    .alert { border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); }
    .page-header { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3); margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }
    .page-header .header-info { color: rgba(255,255,255,0.9); font-size: 0.9rem; margin-top: 5px; }
    .header-stats { display: flex; gap: 20px; align-items: center; flex-wrap: wrap; }
    .btn-header { padding: 12px 24px; border-radius: 10px; font-weight: 700; cursor: pointer; border: none; display: inline-flex; align-items: center; gap: 8px; transition: all 0.3s; text-decoration: none; font-size: 14px; color: white; }
    .btn-primary-custom { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3); }
    .btn-primary-custom:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(30, 58, 138, 0.5); color: white; text-decoration: none; }
    .btn-success-custom { background: linear-gradient(135deg, #10b981 0%, #059669 100%); box-shadow: 0 4px 15px rgba(16, 185, 129, 0.3); }
    .btn-success-custom:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(16, 185, 129, 0.4); color: white; text-decoration: none; }
    .btn-danger-custom { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); box-shadow: 0 4px 15px rgba(239, 68, 68, 0.3); }
    .btn-danger-custom:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(239, 68, 68, 0.4); color: white; text-decoration: none; }
    .btn-export-custom { background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3); }
    .btn-export-custom:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(59, 130, 246, 0.4); color: white; text-decoration: none; }
    .stats-row { display: flex; gap: 12px; margin-bottom: 25px; flex-wrap: nowrap; overflow-x: auto; }
    .stat-card { background: white; border-radius: 10px; padding: 15px 12px; display: flex; align-items: center; gap: 10px; border-left: 4px solid; box-shadow: 0 2px 10px rgba(0,0,0,0.08); transition: all 0.3s; flex: 1; min-width: 0; }
    .stat-card:hover { transform: translateY(-3px); box-shadow: 0 6px 20px rgba(0,0,0,0.12); }
    .stat-card.clickable { cursor: pointer; }
    .stat-card.blue { border-left-color: #1e40af; }
    .stat-card.green { border-left-color: #10b981; }
    .stat-card.orange { border-left-color: #f59e0b; }
    .stat-card.red { border-left-color: #ef4444; }
    .stat-card.purple { border-left-color: #8b5cf6; }
    .stat-icon { width: 45px; height: 45px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 20px; color: white; flex-shrink: 0; }
    .stat-icon.blue { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); }
    .stat-icon.green { background: linear-gradient(135deg, #10b981 0%, #059669 100%); }
    .stat-icon.orange { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); }
    .stat-icon.red { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); }
    .stat-icon.purple { background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); }
    .stat-content { flex: 1; min-width: 0; }
    .stat-content h3 { margin: 0; font-size: 24px; font-weight: 800; color: #0f172a; white-space: nowrap; }
    .stat-content p { margin: 3px 0 0 0; font-size: 10px; font-weight: 600; color: #64748b; text-transform: uppercase; line-height: 1.3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .filter-bar { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px; }
    .filter-bar h5 { color: #1e3a8a; font-weight: 700; margin-bottom: 15px; font-size: 16px; }
    .filter-row { display: flex; gap: 15px; align-items: center; flex-wrap: wrap; }
    .filter-group { flex: 1; min-width: 200px; }
    .filter-group label { font-weight: 600; color: #475569; font-size: 13px; margin-bottom: 5px; display: block; }
    .filter-group input, .filter-group select { width: 100%; padding: 10px 15px; border: 2px solid #e2e8f0; border-radius: 8px; font-size: 14px; font-weight: 500; color: #1e293b; transition: all 0.3s; }
    .filter-group input:focus, .filter-group select:focus { outline: none; border-color: #1e40af; box-shadow: 0 0 0 3px rgba(30, 64, 175, 0.1); }
    .table-container { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 25px; overflow-x: auto; }
    .table-header-actions { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; flex-wrap: wrap; gap: 10px; }
    .table-header-actions h5 { color: #1e3a8a; font-weight: 700; margin: 0; font-size: 16px; }
    table.dataTable { width: 100% !important; border-collapse: separate !important; border-spacing: 0 !important; }
    table.dataTable thead th { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important; color: white !important; font-weight: 700 !important; padding: 15px 10px !important; text-align: left !important; border: 1px solid #1e3a8a !important; font-size: 13px !important; }
    table.dataTable tbody td { border: 1px solid #e2e8f0 !important; padding: 12px 10px !important; vertical-align: middle !important; font-weight: 500 !important; color: #1e293b !important; font-size: 13px !important; }
    table.dataTable tbody tr { background-color: #ffffff !important; transition: background-color 0.2s ease; }
    table.dataTable tbody tr:hover { background-color: #f1f5f9 !important; }
    .badge { padding: 6px 14px; border-radius: 20px; font-weight: 600; font-size: 12px; text-transform: uppercase; }
    .badge-success { background: #d1fae5; color: #065f46; }
    .badge-warning { background: #fef3c7; color: #92400e; }
    .badge-danger { background: #fee2e2; color: #991b1b; }
    .photo-thumb { width: 50px; height: 50px; object-fit: cover; border-radius: 8px; cursor: pointer; border: 2px solid #e2e8f0; margin: 2px; transition: 0.3s; }
    .photo-thumb:hover { transform: scale(1.15); border-color: #1e40af; }
    .modal-content { border-radius: 15px; border: none; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
    .modal-header { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; border-radius: 15px 15px 0 0; padding: 20px 30px; }
    .modal-body { padding: 30px; max-height: 70vh; overflow-y: auto; }
    .modal-dialog { margin: 30px auto; max-width: 600px; }
    .close { color: white; opacity: 0.9; text-shadow: none; font-size: 28px; }
    #video { width: 100%; max-width: 480px; height: 300px; background: #000; border-radius: 12px; margin: 0 auto; display: block; object-fit: cover; }
    #canvas { display: none; }
    #preview { display: none; width: 100%; max-width: 480px; border-radius: 12px; border: 3px solid #10b981; margin: 0 auto; }
    .gps-status { padding: 15px; border-radius: 10px; margin: 15px 0; text-align: center; font-weight: 600; }
    .gps-ok { background: #d1fae5; color: #065f46; border: 2px solid #10b981; }
    .gps-bad { background: #fee2e2; color: #991b1b; border: 2px solid #ef4444; }
    .info-card { background: #f8fafc; padding: 15px; border-radius: 10px; margin-bottom: 15px; border-left: 4px solid #1e40af; }
    .info-card h6 { margin: 0 0 8px 0; color: #1e3a8a; font-weight: 700; font-size: 13px; }
    .info-card p { margin: 0; color: #475569; font-size: 14px; font-weight: 500; }
    .section-divider { margin: 40px 0 25px; text-align: center; position: relative; }
    .section-divider span { background: #f0f4f8; padding: 0 20px; color: #64748b; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; position: relative; z-index: 1; }
    .section-divider::before { content: ''; position: absolute; top: 50%; left: 0; right: 0; border-top: 2px dashed #cbd5e1; z-index: 0; }
    .select2-container--default .select2-selection--single { height: 44px !important; border: 2px solid #e2e8f0 !important; border-radius: 8px !important; }
    .select2-container--default .select2-selection--single .select2-selection__rendered { line-height: 40px !important; padding-left: 15px !important; font-weight: 500 !important; }
    .select2-container--default .select2-selection--single .select2-selection__arrow { height: 42px !important; }
    .dataTables_wrapper .dataTables_paginate .paginate_button { padding: 8px 16px !important; margin: 0 4px !important; border-radius: 8px !important; border: 2px solid #e2e8f0 !important; background: white !important; color: #1e3a8a !important; font-weight: 700 !important; }
    .dataTables_wrapper .dataTables_paginate .paginate_button:hover { background: #1e40af !important; color: white !important; border-color: #1e40af !important; }
    .dataTables_wrapper .dataTables_paginate .paginate_button.current { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important; color: white !important; border-color: #1e3a8a !important; }
    .no-data-msg { text-align: center; padding: 60px 20px; background: linear-gradient(135deg, #f1f5f9 0%, #e2e8f0 100%); border-radius: 12px; margin: 20px 0; }
    .no-data-msg i { font-size: 64px; color: #94a3b8; margin-bottom: 20px; }
    .no-data-msg h4 { color: #475569; font-weight: 700; margin-bottom: 10px; }
    .no-data-msg p { color: #64748b; font-size: 14px; }
    .employee-list { max-height: 400px; overflow-y: auto; }
    .employee-item { padding: 12px; border-bottom: 1px solid #e2e8f0; display: flex; justify-content: space-between; align-items: center; transition: background 0.2s; }
    .employee-item:hover { background: #f8fafc; }
    .employee-item:last-child { border-bottom: none; }
    .employee-name { font-weight: 600; color: #1e293b; }
    .employee-id { font-size: 12px; color: #64748b; }
    .employee-info { font-size: 11px; color: #94a3b8; margin-top: 2px; }
    @media (max-width: 768px) { .page-header { flex-direction: column; gap: 15px; } .filter-row { flex-direction: column; } .filter-group { min-width: 100%; } .stat-card { min-width: 150px; } .stat-content h3 { font-size: 20px; } .stat-content p { font-size: 9px; } .stat-icon { width: 40px; height: 40px; font-size: 18px; } }
  </style>
</head>
<body>

<div class="alert-container">
  <?php if(!empty($success_message)): ?>
    <div class="alert alert-success alert-dismissible fade show">
      <strong><i class="fa fa-check-circle"></i> Success!</strong> <?php echo $success_message; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
  <?php endif; ?>
  
  <?php if(!empty($error_message)): ?>
    <div class="alert alert-danger alert-dismissible fade show">
      <strong><i class="fa fa-exclamation-triangle"></i> Error!</strong> <?php echo $error_message; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
  <?php endif; ?>
</div>

<div class="container-fluid">
  
  <div class="page-header">
    <div>
      <h1><i class="fas fa-clock"></i> Attendance</h1>
      <div class="header-info"><?php echo date('l, F d, Y'); ?></div>
      <?php if($user_emp_data): ?>
      <div class="header-info" style="margin-top: 8px;">
        <?php if($user_kpi_complete): ?>
          <span style="background: #d1fae5; color: #065f46; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600;">
            <i class="fas fa-check-circle"></i> Daily KPI: Completed <?php echo ($user_kpi_score >= 0) ? '('.$user_kpi_score.'%)' : '(On Leave)'; ?>
          </span>
        <?php else: ?>
          <span style="background: #fee2e2; color: #991b1b; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600;">
            <i class="fas fa-exclamation-circle"></i> Daily KPI: Pending
          </span>
        <?php endif; ?>
      </div>
      <?php endif; ?>
    </div>
    <div class="header-stats">
      <?php if($user_emp_data): ?>
      <button class="btn-header btn-success-custom" onclick="handleMarkAttendance()">
        <i class="fas fa-plus-circle"></i> Mark Attendance
      </button>
      <?php endif; ?>
      <!--<a href="<?php echo $is_super_admin ? 'index.php' : 'https://crm.abra-logistic.com/dashboard/raise-a-ticket.php'; ?>" class="btn-header btn-primary-custom" id="dashboardLink">-->
      <!--  <i class="fas fa-arrow-left"></i> Dashboard-->
      <!--</a>-->
    </div>
  </div>

  <?php if($is_admin): ?>
  <!-- Admin Section - SHOWN FIRST -->
  
  <!-- Admin Stats -->
  <div class="stats-row">
    <div class="stat-card purple">
      <div class="stat-icon purple"><i class="fas fa-users"></i></div>
      <div class="stat-content">
        <h3><?php echo number_format($employee_stats['total']); ?></h3>
        <p>Total Employees</p>
      </div>
    </div>
    <div class="stat-card green clickable" onclick="showCheckedIn()">
      <div class="stat-icon green"><i class="fas fa-user-check"></i></div>
      <div class="stat-content">
        <h3><?php echo number_format($employee_stats['checked_in']); ?></h3>
        <p>Checked In <i class="fas fa-external-link-alt" style="font-size:10px"></i></p>
      </div>
    </div>
    <div class="stat-card orange clickable" onclick="showLateEmployees()">
      <div class="stat-icon orange"><i class="fas fa-clock"></i></div>
      <div class="stat-content">
        <h3><?php echo number_format($employee_stats['late_today']); ?></h3>
        <p>Late <i class="fas fa-external-link-alt" style="font-size:10px"></i></p>
      </div>
    </div>
    <div class="stat-card red clickable" onclick="showNotCheckedIn()">
      <div class="stat-icon red"><i class="fas fa-user-times"></i></div>
      <div class="stat-content">
        <h3><?php echo number_format($employee_stats['not_checked_in']); ?></h3>
        <p>Not Checked In <i class="fas fa-external-link-alt" style="font-size:10px"></i></p>
      </div>
    </div>
    <div class="stat-card blue clickable" onclick="showNotLoggedOff()">
      <div class="stat-icon blue"><i class="fas fa-sign-out-alt"></i></div>
      <div class="stat-content">
        <h3><?php echo number_format($employee_stats['not_logged_off']); ?></h3>
        <p>Not Logged Off <i class="fas fa-external-link-alt" style="font-size:10px"></i></p>
      </div>
    </div>
  </div>

  <form method="GET">
      <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail); ?>">
    <div class="filter-bar">
        
      <h5><i class="fas fa-filter"></i> Filter Records</h5>
      <div class="filter-row">
        <div class="filter-group">
          <label>From Date</label>
          <input type="date" name="date_from" value="<?php echo htmlspecialchars($date_from); ?>">
        </div>
        <div class="filter-group">
          <label>To Date</label>
          <input type="date" name="date_to" value="<?php echo htmlspecialchars($date_to); ?>">
        </div>
        <div class="filter-group">
          <label>Employee</label>
          <select name="employee" class="select2">
            <option value="">All Employees</option>
            <?php 
            if(isset($emp_list_query)):
                while($emp = mysqli_fetch_assoc($emp_list_query)): 
            ?>
              <option value="<?php echo htmlspecialchars($emp['employee_id']); ?>" <?php echo ($emp_filter == $emp['employee_id']) ? 'selected' : ''; ?>>
                <?php echo htmlspecialchars($emp['name']); ?>
              </option>
            <?php endwhile; endif; ?>
          </select>
        </div>
        <div style="margin-top: 22px;">
          <button type="submit" class="btn-header btn-primary-custom">
            <i class="fas fa-search"></i> Apply
          </button>
        </div>
      </div>
    </div>
  </form>

  <?php if($admin_result && mysqli_num_rows($admin_result) > 0): ?>
  <div class="table-container">
    <div class="table-header-actions">
      <h5><i class="fas fa-table"></i> All Employee Attendance Records</h5>
      <a href="?action=export&export_type=admin&date_from=<?php echo urlencode($date_from); ?>&date_to=<?php echo urlencode($date_to); ?>&employee=<?php echo urlencode($emp_filter); ?>&user_email=<?php echo urlencode($currentUserEmail); ?>" class="btn-header btn-export-custom">
        <i class="fas fa-download"></i> Export CSV
      </a>
    </div>
    <table id="adminTable" class="display nowrap" style="width:100%">
      <thead>
        <tr>
          <th>Date</th>
          <th>Employee</th>
          <th>Check In</th>
          <th>Check Out</th>
          <th>Work Hours</th>
          <th>Status</th>
          <th>Photos</th>
          <th>Action</th>
        </tr>
      </thead>
      <tbody>
        <?php 
        mysqli_data_seek($admin_result, 0);
        while($row = mysqli_fetch_assoc($admin_result)): 
        ?>
        <tr>
          <td><?php echo date('M d, Y', strtotime($row['date'])); ?></td>
          <td>
            <div style="font-weight:700"><?php echo htmlspecialchars($row['employee_name']); ?></div>
            <div style="font-size:11px;color:#64748b"><?php echo htmlspecialchars($row['employee_id']); ?></div>
          </td>
          <td><?php echo date('h:i A', strtotime($row['check_in_time'])); ?></td>
          <td><?php echo $row['check_out_time'] ? date('h:i A', strtotime($row['check_out_time'])) : '—'; ?></td>
          <td><?php echo $row['work_hours'] ? $row['work_hours'] . ' hr' : '—'; ?></td>
          <td><span class="badge badge-<?php echo $row['status'] == 'present' ? 'success' : ($row['status'] == 'late' ? 'warning' : 'danger'); ?>"><?php echo ucfirst($row['status']); ?></span></td>
          <td>
            <?php if($row['check_in_photo']): ?><img src="<?php echo $row['check_in_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            <?php if($row['check_out_photo']): ?><img src="<?php echo $row['check_out_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
          </td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
          <td><span style="font-size:11px;color:#64748b;font-style:italic;">HR Override</span></td>
          <?php else: ?>
          <td>
            <button type="button" class="btn btn-sm btn-danger" onclick="deleteAttendance('<?php echo htmlspecialchars($row['employee_id']); ?>','<?php echo $row['date']; ?>')" title="Delete">
              <i class="fas fa-trash"></i>
            </button>
          </td>
          <?php endif; ?>
        </tr>
        <?php endwhile; ?>
      </tbody>
    </table>
  </div>
  <?php else: ?>
  <div class="no-data-msg">
    <i class="fas fa-calendar-times"></i>
    <h4>No Attendance Records Found</h4>
    <p>No attendance data available for the selected filters.</p>
  </div>
  <?php endif; ?>
  
  <!-- Personal Section Divider for Admin -->
  <div class="section-divider"><span>My Personal Attendance</span></div>
  <?php endif; ?>

  <?php if($user_emp_data): ?>
    <!-- Personal Stats -->
    <div class="stats-row">
      <div class="stat-card blue">
        <div class="stat-icon blue"><i class="fas fa-calendar-alt"></i></div>
        <div class="stat-content">
          <h3><?php echo number_format($my_stats['total']); ?></h3>
          <p>Total Days</p>
        </div>
      </div>
      <div class="stat-card green">
        <div class="stat-icon green"><i class="fas fa-check-circle"></i></div>
        <div class="stat-content">
          <h3><?php echo number_format($my_stats['present']); ?></h3>
          <p>On Time</p>
        </div>
      </div>
      <div class="stat-card orange">
        <div class="stat-icon orange"><i class="fas fa-clock"></i></div>
        <div class="stat-content">
          <h3><?php echo number_format($my_stats['late']); ?></h3>
          <p>Late</p>
        </div>
      </div>
      <div class="stat-card red">
        <div class="stat-icon red"><i class="fas fa-hourglass-half"></i></div>
        <div class="stat-content">
<h3><?php echo number_format(floatval($my_stats['hours']), 1); ?></h3>
          <p>Hours</p>
        </div>
      </div>
    </div>

    <!-- My Attendance Filter and Table -->
    <form method="GET">
      <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail); ?>">
      <?php if($is_admin && isset($_GET['date_from'])): ?>
        <input type="hidden" name="date_from" value="<?php echo htmlspecialchars($_GET['date_from']); ?>">
        <input type="hidden" name="date_to" value="<?php echo htmlspecialchars($_GET['date_to']); ?>">
      <?php endif; ?>
      
      <div class="filter-bar">
        <h5><i class="fas fa-user-clock"></i> My Attendance</h5>
        <div class="filter-row">
          <div class="filter-group">
            <label>From Date</label>
            <input type="date" name="mf_start" value="<?php echo htmlspecialchars($mf_start); ?>">
          </div>
          <div class="filter-group">
            <label>To Date</label>
            <input type="date" name="mf_end" value="<?php echo htmlspecialchars($mf_end); ?>">
          </div>
          <div style="margin-top: 22px;">
            <button type="submit" class="btn-header btn-primary-custom">
              <i class="fas fa-search"></i> Filter
            </button>
          </div>
          <?php if(!empty($user_assigned_location)): ?>
            <div style="margin-left: auto; margin-top: 22px;">
              <span class="badge badge-success" style="padding: 10px 15px;">
                <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($user_assigned_location); ?>
              </span>
            </div>
          <?php endif; ?>
          <?php if(!empty($user_work_timings)): ?>
            <div style="margin-top: 22px;">
              <span class="badge badge-warning" style="padding: 10px 15px;">
                <i class="fas fa-clock"></i> <?php echo htmlspecialchars($user_work_timings); ?>
              </span>
            </div>
          <?php endif; ?>
        </div>
      </div>
    </form>

    <div class="table-container">
      <div class="table-header-actions">
        <h5><i class="fas fa-user"></i> My Attendance Records</h5>
        <?php if($my_result && mysqli_num_rows($my_result) > 0): ?>
        <a href="?action=export&export_type=personal&mf_start=<?php echo urlencode($mf_start); ?>&mf_end=<?php echo urlencode($mf_end); ?>&user_email=<?php echo urlencode($currentUserEmail); ?>" class="btn-header btn-export-custom">
          <i class="fas fa-download"></i> Export My Records
        </a>
        <?php endif; ?>
      </div>
      <table id="personalTable" class="display nowrap" style="width:100%">
        <thead>
          <tr>
            <th>Date</th>
            <th>Check In</th>
            <th>Check Out</th>
            <th>Work Hours</th>
            <th>Status</th>
            <th>Photos</th>
          </tr>
        </thead>
        <tbody>
        <?php if($my_result && mysqli_num_rows($my_result) > 0): ?>
          <?php 
          mysqli_data_seek($my_result, 0);
          while($row = mysqli_fetch_assoc($my_result)): 
          ?>
          <tr>
            <td><strong><?php echo date('M d, Y', strtotime($row['date'])); ?></strong></td>
            <td><?php echo date('h:i A', strtotime($row['check_in_time'])); ?></td>
            <td><?php echo $row['check_out_time'] ? date('h:i A', strtotime($row['check_out_time'])) : '—'; ?></td>
            <td><?php echo $row['work_hours'] ? $row['work_hours'] . ' hr' : '—'; ?></td>
            <td><span class="badge badge-<?php echo $row['status'] == 'present' ? 'success' : ($row['status'] == 'late' ? 'warning' : 'danger'); ?>"><?php echo ucfirst($row['status']); ?></span></td>
            <td>
              <?php if($row['check_in_photo']): ?><img src="<?php echo $row['check_in_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
              <?php if($row['check_out_photo']): ?><img src="<?php echo $row['check_out_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            </td>
          </tr>
          <?php endwhile; ?>
        <?php else: ?>
          <tr><td colspan="6" style="text-align:center;padding:30px;color:#94a3b8">No attendance records found for the selected date range.</td></tr>
        <?php endif; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>

</div>

<?php if($user_emp_data): 
    $today_in = $today_record && !empty($today_record['check_in_time']);
    $today_out = $today_record && !empty($today_record['check_out_time']);
?>
<div class="modal fade" id="markModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal">&times;</button>
        <h4 class="modal-title"><i class="fas fa-camera"></i> Mark Attendance</h4>
      </div>
      <div class="modal-body">

        <!-- ✅ DATE PICKER STEP — always shown first -->
        <div id="datePickerStep">
          <div style="background:#f8fafc;border-radius:10px;padding:15px;margin-bottom:15px;border:2px solid #e2e8f0;">
            <label style="font-weight:700;color:#1e3a8a;font-size:14px;display:block;margin-bottom:8px;">
              <i class="fas fa-calendar-alt"></i> Select Attendance Date
            </label>
            <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
              <input type="date" id="att_date"
                value="<?php echo date('Y-m-d'); ?>"
                max="<?php echo date('Y-m-d'); ?>"
                style="flex:1;padding:10px 14px;border:2px solid #e2e8f0;border-radius:8px;font-family:'Poppins',sans-serif;font-size:14px;font-weight:600;color:#1e293b;">
              <button type="button" class="btn-header btn-primary-custom" onclick="checkDateStatus()" style="padding:10px 20px;">
                <i class="fas fa-arrow-right"></i> Next
              </button>
            </div>
            <small style="color:#94a3b8;display:block;margin-top:6px;">
              <i class="fas fa-info-circle"></i> Default is today. For overtime past midnight, select yesterday.
            </small>
          </div>
        </div>

        <!-- ✅ STATUS PANEL — shown after date is checked via AJAX -->
        <div id="statusPanel" style="display:none;">

          <!-- State A: Both done -->
          <div id="stateAllDone" style="display:none;text-align:center;padding:30px;">
            <i class="fas fa-check-circle" style="font-size:64px;color:#10b981;"></i>
            <h3 style="margin-top:15px;color:#065f46;">Attendance Complete!</h3>
            <p id="stateAllDoneMsg" style="color:#64748b;margin-top:8px;"></p>
            <button type="button" class="btn-header btn-primary-custom" style="margin-top:15px;" onclick="$('#datePickerStep').show();$('#statusPanel').hide();">
              <i class="fas fa-arrow-left"></i> Back
            </button>
          </div>

          <!-- State B: Checked in, checkout pending -->
          <div id="stateCheckedInOnly" style="display:none;">
            <div style="background:#fef3c7;border:2px solid #f59e0b;border-radius:10px;padding:15px;margin-bottom:15px;display:flex;align-items:center;gap:12px;">
              <i class="fas fa-sign-in-alt" style="font-size:28px;color:#d97706;"></i>
              <div>
                <div style="font-weight:700;color:#92400e;">Already Checked In</div>
                <div id="checkedInMsg" style="font-size:13px;color:#92400e;margin-top:3px;"></div>
              </div>
            </div>
            <p style="font-size:13px;color:#64748b;margin-bottom:12px;">Capture photo &amp; GPS to check out.</p>
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
            <?php if($user_assigned_location): ?>
            <p style="margin-top:6px;font-size:13px;">
              <i class="fas fa-map-marker-alt" style="color:#10b981;"></i> <?php echo htmlspecialchars($user_assigned_location); ?>
              &nbsp;<i class="fas fa-clock" style="color:#f59e0b;"></i> <?php echo htmlspecialchars($user_work_timings); ?>
            </p>
            <?php endif; ?>
          </div>

          <!-- Camera + GPS Form -->
          <div id="attFormWrap">
            <form method="POST" id="attForm">
              <input type="hidden" name="action_type"    id="att_action_type">
              <input type="hidden" name="att_date_input" id="att_date_input">
              <input type="hidden" name="latitude"       id="lat">
              <input type="hidden" name="longitude"      id="lng">
              <input type="hidden" name="location_name"  id="loc_name">
              <input type="hidden" name="photo_data"     id="photo_data">
              <input type="hidden" name="user_email"     value="<?php echo htmlspecialchars($currentUserEmail); ?>">

              <div style="position:relative;margin-bottom:15px;text-align:center;">
                <video id="video" autoplay playsinline muted></video>
                <canvas id="canvas"></canvas>
                <img id="preview" alt="Captured Photo">
              </div>
              <div style="text-align:center;margin-bottom:15px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap;">
                <button type="button" class="btn-header btn-primary-custom" id="btnStart" onclick="startCamera()"><i class="fas fa-video"></i> Start Camera</button>
                <button type="button" class="btn-header btn-primary-custom" style="display:none;" id="btnSnap" onclick="takePhoto()"><i class="fas fa-camera"></i> Capture</button>
                <button type="button" class="btn-header btn-danger-custom" style="display:none;" id="btnRetake" onclick="resetCamera()"><i class="fas fa-redo"></i> Retake</button>
              </div>
              <div id="gpsStatus" class="gps-status" style="background:#f1f5f9;color:#64748b;">
                <i class="fas fa-spinner fa-spin"></i> Getting Location...
              </div>
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

<div class="modal fade" id="photoModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal">&times;</button>
        <h4 class="modal-title"><i class="fas fa-image"></i> Photo</h4>
      </div>
      <div class="modal-body text-center">
        <img id="viewImg" src="" style="max-width:100%;border-radius:12px">
      </div>
    </div>
  </div>
</div>

<!-- Not Checked In Modal -->
<?php if($is_admin): ?>
<div class="modal fade" id="notCheckedInModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h4 class="modal-title"><i class="fas fa-user-times"></i> Employees Not Checked In</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['not_checked_in_list'])): ?>
          <div class="employee-list">
            <?php foreach($employee_stats['not_checked_in_list'] as $emp): ?>
            <div class="employee-item" style="display: block; padding: 15px;">
              <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($emp['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($emp['employee_id']); ?></div>
                  <?php if(!empty($emp['department']) || !empty($emp['work_location'])): ?>
                  <div class="employee-info">
                    <?php if(!empty($emp['department'])): ?>
                      <i class="fas fa-building"></i> <?php echo htmlspecialchars($emp['department']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp['work_location'])): ?>
                      | <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($emp['work_location']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp['hire_date']) && $emp['hire_date'] != '0000-00-00'): ?>
                      | <i class="fas fa-calendar-plus"></i> Joined: <?php echo date('M d, Y', strtotime($emp['hire_date'])); ?>
                    <?php endif; ?>
                  </div>
                  <?php endif; ?>
                </div>
                <div>
                  <span class="badge badge-danger"><?php echo $emp['missing_count']; ?> Days Absent</span>
                </div>
              </div>
              <div style="background: #fee2e2; padding: 10px; border-radius: 8px; margin-top: 10px;">
                <strong style="color: #991b1b; font-size: 12px;">
                  Missing Dates 
                  <?php if(!empty($emp['emp_start_date']) && $emp['emp_start_date'] != $stats_date_from): ?>
                    (from joining date <?php echo date('M d, Y', strtotime($emp['emp_start_date'])); ?>):
                  <?php else: ?>
                    :
                  <?php endif; ?>
                </strong>
                <div style="margin-top: 5px; display: flex; flex-wrap: wrap; gap: 5px;">
                  <?php foreach($emp['missing_dates'] as $missing_date): ?>
                    <span style="background: white; padding: 4px 8px; border-radius: 5px; font-size: 11px; color: #991b1b; border: 1px solid #fecaca;">
                      <?php echo date('M d', strtotime($missing_date)); ?>
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
            <h4 style="margin-top:15px;color:#0f172a">Perfect Attendance!</h4>
            <p style="color:#64748b">All employees have marked their attendance for all days.</p>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Checked In Modal -->
<div class="modal fade" id="checkedInModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #10b981 0%, #059669 100%);">
        <h4 class="modal-title"><i class="fas fa-user-check"></i> Employees Checked In</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['checked_in_list'])): ?>
          <div class="employee-list">
            <?php 
            // Group by employee
            $grouped_checkins = [];
            foreach($employee_stats['checked_in_list'] as $emp) {
                $grouped_checkins[$emp['employee_id']]['name'] = $emp['employee_name'];
                $grouped_checkins[$emp['employee_id']]['department'] = $emp['department'] ?? '';
                $grouped_checkins[$emp['employee_id']]['work_location'] = $emp['work_location'] ?? '';
                $grouped_checkins[$emp['employee_id']]['timings'] = $emp['timings'] ?? '';
                $grouped_checkins[$emp['employee_id']]['dates'][] = $emp;
            }
            
            foreach($grouped_checkins as $emp_id => $emp_data): 
            ?>
            <div class="employee-item" style="display: block; padding: 15px;">
              <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($emp_data['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($emp_id); ?></div>
                  <?php if(!empty($emp_data['department']) || !empty($emp_data['work_location'])): ?>
                  <div class="employee-info">
                    <?php if(!empty($emp_data['department'])): ?>
                      <i class="fas fa-building"></i> <?php echo htmlspecialchars($emp_data['department']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp_data['work_location'])): ?>
                      | <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($emp_data['work_location']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp_data['timings'])): ?>
                      | <i class="fas fa-clock"></i> <?php echo htmlspecialchars($emp_data['timings']); ?>
                    <?php endif; ?>
                  </div>
                  <?php endif; ?>
                </div>
                <div>
                  <span class="badge badge-success"><?php echo count($emp_data['dates']); ?> Days</span>
                </div>
              </div>
              <div style="background: #f0fdf4; padding: 10px; border-radius: 8px; margin-top: 10px; border-left: 3px solid #10b981;">
                <strong style="color: #065f46; font-size: 12px;">Check-In Records:</strong>
                <div style="margin-top: 5px; display: flex; flex-wrap: wrap; gap: 5px;">
                  <?php foreach($emp_data['dates'] as $date_record): ?>
                    <div style="background: white; padding: 6px 10px; border-radius: 5px; font-size: 11px; color: #047857; border: 1px solid #d1fae5; min-width: 200px;">
                      <div style="font-weight: 600; margin-bottom: 3px;">
                        <i class="fas fa-calendar"></i> <?php echo date('M d, Y', strtotime($date_record['date'])); ?>
                        <span class="badge badge-<?php echo $date_record['status'] == 'present' ? 'success' : 'warning'; ?>" style="font-size: 9px; padding: 2px 6px; margin-left: 5px;">
                          <?php echo ucfirst($date_record['status']); ?>
                        </span>
                      </div>
                      <div style="color: #059669;">
                        <i class="fas fa-sign-in-alt"></i> In: <strong><?php echo date('h:i A', strtotime($date_record['check_in_time'])); ?></strong>
                        <?php if(!empty($date_record['check_out_time'])): ?>
                          | <i class="fas fa-sign-out-alt"></i> Out: <strong><?php echo date('h:i A', strtotime($date_record['check_out_time'])); ?></strong>
                        <?php else: ?>
                          | <span style="color: #dc2626;"><i class="fas fa-exclamation-circle"></i> Not Out</span>
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
          <div style="text-align:center;padding:40px">
            <i class="fas fa-user-times" style="font-size:48px;color:#ef4444"></i>
            <h4 style="margin-top:15px;color:#0f172a">No Check-Ins Yet!</h4>
            <p style="color:#64748b">No employees have checked in during this period.</p>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Late Employees Modal -->
<div class="modal fade" id="lateEmployeesModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);">
        <h4 class="modal-title"><i class="fas fa-clock"></i> Employees Late</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['late_today_list'])): ?>
          <div class="employee-list">
            <?php 
            // Group by employee
            $grouped_late = [];
            foreach($employee_stats['late_today_list'] as $emp) {
                $grouped_late[$emp['employee_id']]['name'] = $emp['employee_name'];
                $grouped_late[$emp['employee_id']]['work_location'] = $emp['work_location'] ?? '';
                $grouped_late[$emp['employee_id']]['timings'] = $emp['timings'] ?? '';
                $grouped_late[$emp['employee_id']]['dates'][] = $emp;
            }
            
            foreach($grouped_late as $emp_id => $emp_data): 
            ?>
            <div class="employee-item" style="display: block; padding: 15px;">
              <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($emp_data['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($emp_id); ?></div>
                  <?php if(!empty($emp_data['work_location']) || !empty($emp_data['timings'])): ?>
                  <div class="employee-info">
                    <?php if(!empty($emp_data['work_location'])): ?>
                      <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($emp_data['work_location']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp_data['timings'])): ?>
                      | <i class="fas fa-clock"></i> Expected: <?php echo htmlspecialchars($emp_data['timings']); ?>
                    <?php endif; ?>
                  </div>
                  <?php endif; ?>
                </div>
                <div>
                  <span class="badge badge-warning"><?php echo count($emp_data['dates']); ?> Days Late</span>
                </div>
              </div>
              <div style="background: #fef3c7; padding: 10px; border-radius: 8px; margin-top: 10px; border-left: 3px solid #f59e0b;">
                <strong style="color: #92400e; font-size: 12px;">Late Arrivals:</strong>
                <div style="margin-top: 5px; display: flex; flex-wrap: wrap; gap: 5px;">
                  <?php foreach($emp_data['dates'] as $date_record): ?>
                    <div style="background: white; padding: 6px 10px; border-radius: 5px; font-size: 11px; color: #92400e; border: 1px solid #fde68a;">
                      <div style="font-weight: 600;">
                        <i class="fas fa-calendar"></i> <?php echo date('M d, Y', strtotime($date_record['date'])); ?>
                      </div>
                      <div style="color: #d97706; margin-top: 2px;">
                        <i class="fas fa-clock"></i> Arrived: <strong><?php echo date('h:i A', strtotime($date_record['check_in_time'])); ?></strong>
                      </div>
                    </div>
                  <?php endforeach; ?>
                </div>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px">
            <i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i>
            <h4 style="margin-top:15px;color:#0f172a">No Late Arrivals!</h4>
            <p style="color:#64748b">All checked-in employees arrived on time.</p>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>

<!-- Not Logged Off Modal -->
<div class="modal fade" id="notLoggedOffModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);">
        <h4 class="modal-title"><i class="fas fa-sign-out-alt"></i> Employees Not Logged Off</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($employee_stats['not_logged_off_list'])): ?>
          <div class="employee-list">
            <?php 
            // Group by employee
            $grouped_not_logged = [];
            foreach($employee_stats['not_logged_off_list'] as $emp) {
                $grouped_not_logged[$emp['employee_id']]['name'] = $emp['employee_name'];
                $grouped_not_logged[$emp['employee_id']]['work_location'] = $emp['work_location'] ?? '';
                $grouped_not_logged[$emp['employee_id']]['timings'] = $emp['timings'] ?? '';
                $grouped_not_logged[$emp['employee_id']]['dates'][] = $emp;
            }
            
            foreach($grouped_not_logged as $emp_id => $emp_data): 
            ?>
            <div class="employee-item" style="display: block; padding: 15px;">
              <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 10px;">
                <div>
                  <div class="employee-name"><?php echo htmlspecialchars($emp_data['name']); ?></div>
                  <div class="employee-id">ID: <?php echo htmlspecialchars($emp_id); ?></div>
                  <?php if(!empty($emp_data['work_location']) || !empty($emp_data['timings'])): ?>
                  <div class="employee-info">
                    <?php if(!empty($emp_data['work_location'])): ?>
                      <i class="fas fa-map-marker-alt"></i> <?php echo htmlspecialchars($emp_data['work_location']); ?>
                    <?php endif; ?>
                    <?php if(!empty($emp_data['timings'])): ?>
                      | <i class="fas fa-clock"></i> <?php echo htmlspecialchars($emp_data['timings']); ?>
                    <?php endif; ?>
                  </div>
                  <?php endif; ?>
                </div>
                <div>
                  <span class="badge badge-danger"><?php echo count($emp_data['dates']); ?> Days</span>
                </div>
              </div>
              <div style="background: #dbeafe; padding: 10px; border-radius: 8px; margin-top: 10px; border-left: 3px solid #3b82f6;">
                <strong style="color: #1e40af; font-size: 12px;">Missing Check-Outs:</strong>
                <div style="margin-top: 5px; display: flex; flex-wrap: wrap; gap: 5px;">
                  <?php foreach($emp_data['dates'] as $date_record): ?>
                    <div style="background: white; padding: 6px 10px; border-radius: 5px; font-size: 11px; color: #1e40af; border: 1px solid #bfdbfe;">
                      <div style="font-weight: 600;">
                        <i class="fas fa-calendar"></i> <?php echo date('M d, Y', strtotime($date_record['date'])); ?>
                      </div>
                      <div style="color: #2563eb; margin-top: 2px;">
                        <i class="fas fa-sign-in-alt"></i> In: <strong><?php echo date('h:i A', strtotime($date_record['check_in_time'])); ?></strong>
                        <span style="color: #dc2626; margin-left: 5px;">
                          <i class="fas fa-exclamation-triangle"></i> No Check-Out
                        </span>
                      </div>
                    </div>
                  <?php endforeach; ?>
                </div>
              </div>
            </div>
            <?php endforeach; ?>
          </div>
        <?php else: ?>
          <div style="text-align:center;padding:40px">
            <i class="fas fa-check-circle" style="font-size:48px;color:#10b981"></i>
            <h4 style="margin-top:15px;color:#0f172a">All Logged Off!</h4>
            <p style="color:#64748b">All employees have completed their check-out.</p>
          </div>
        <?php endif; ?>
      </div>
    </div>
  </div>
</div>
<?php endif; ?>

<!-- KPI BLOCKING PAGE - NO ACCESS FOR CHECK-OUT -->
<div class="modal fade" id="kpiBlockingModal" tabindex="-1" data-backdrop="static" data-keyboard="false">
  <div class="modal-dialog modal-lg">
    <div class="modal-content" style="border: 3px solid #dc2626;">
      <div class="modal-header" style="background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%); border: none;">
        <h4 class="modal-title" style="color: white; font-size: 24px; font-weight: 800;">
          <i class="fas fa-ban"></i> ACCESS DENIED
        </h4>
      </div>
      <div class="modal-body" style="padding: 50px 30px; text-align: center; background: #fef2f2;">
        
        <div style="margin-bottom: 30px;">
          <i class="fas fa-lock" style="font-size: 100px; color: #dc2626; opacity: 0.9;"></i>
        </div>
        
        <h2 style="color: #991b1b; font-weight: 800; font-size: 28px; margin-bottom: 20px;">
          You Don't Have Access for Check-Out
        </h2>
        
        <div style="background: white; padding: 25px; border-radius: 12px; border-left: 5px solid #dc2626; margin-bottom: 30px; box-shadow: 0 4px 15px rgba(220, 38, 38, 0.2);">
          <p style="font-size: 18px; color: #1e293b; font-weight: 600; margin: 0 0 15px 0;">
            <i class="fas fa-exclamation-triangle" style="color: #f59e0b;"></i> 
            Daily Review Not Completed
          </p>
          <p style="font-size: 16px; color: #475569; margin: 0; line-height: 1.6;">
            You must complete your <strong>Daily Self-Evaluation Review</strong> before you can check out from attendance.
          </p>
        </div>
        
        <div style="background: #fff7ed; padding: 20px; border-radius: 10px; margin-bottom: 30px; border: 2px dashed #f59e0b;">
          <p style="font-size: 14px; color: #92400e; margin: 0; font-weight: 600;">
            <i class="fas fa-info-circle"></i> This is a mandatory requirement set by management
          </p>
        </div>
        
        <div style="display: flex; gap: 15px; justify-content: center; flex-wrap: wrap;">
          <a href="hr-kpi-evaluation.php" class="btn-header btn-danger-custom" style="font-size: 18px; padding: 15px 30px;">
            <i class="fas fa-clipboard-check"></i> Complete Daily Review Now
          </a>
          <button type="button" class="btn-header btn-primary-custom" onclick="$('#kpiBlockingModal').modal('hide')" style="font-size: 18px; padding: 15px 30px;">
            <i class="fas fa-times"></i> Close
          </button>
        </div>
        
        <p style="margin-top: 30px; font-size: 13px; color: #64748b;">
          After completing your review, return to this page to check out.
        </p>
        
      </div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/js/select2.min.js"></script>

<script>
const userAssignedLocation = "<?php echo $user_assigned_location; ?>";
const allOffices = <?php echo json_encode($all_valid_offices); ?>;
const userAttendanceComplete = <?php echo $user_attendance_complete ? 'true' : 'false'; ?>;
const hasUserData = <?php echo $user_emp_data ? 'true' : 'false'; ?>;
const todayCheckedIn = <?php echo ($today_record && !empty($today_record['check_in_time'])) ? 'true' : 'false'; ?>;
const userKpiComplete = <?php echo $user_kpi_complete ? 'true' : 'false'; ?>;
const userDepartment = "<?php echo isset($user_emp_data['department']) ? strtolower(trim($user_emp_data['department'])) : ''; ?>";

// Check if user is in Sales, Marketing, or Management (NO LOCATION RESTRICTION)
const bypassLocation = (
    userDepartment.includes('sales') || 
    userDepartment.includes('marketing') || 
    userDepartment.includes('management')
);

// Show not checked in modal
function showNotCheckedIn() {
    $('#notCheckedInModal').modal('show');
}

// Show checked in modal
function showCheckedIn() {
    $('#checkedInModal').modal('show');
}

// Show late employees modal
function showLateEmployees() {
    $('#lateEmployeesModal').modal('show');
}

// Show not logged off modal
function showNotLoggedOff() {
    $('#notLoggedOffModal').modal('show');
}

// Handle mark attendance button click
function handleMarkAttendance() {
    // Reset modal to date picker step every time
    $('#statusPanel').hide();
    $('#datePickerStep').show();
    resetCamera();
    $('#att_date').val('<?php echo date('Y-m-d'); ?>');
    $('#markModal').modal('show');
}

// ✅ Check date status via AJAX then show correct state
function checkDateStatus() {
    var selDate = $('#att_date').val();
    if(!selDate) { alert('Please select a date.'); return; }

    var url = window.location.href.split('?')[0]
              + '?action=check_date_status&date=' + selDate
              + '&user_email=' + encodeURIComponent('<?php echo addslashes($currentUserEmail); ?>');

    $.getJSON(url, function(data) {
        $('#stateAllDone, #stateCheckedInOnly, #stateNothing').hide();
        $('#attFormWrap').show();
        $('#datePickerStep').hide();
        $('#statusPanel').show();

        // Set hidden date & reset camera
        $('#att_date_input').val(selDate);
        resetCamera();
        $('#btnStart').show();
        $('#btnSnap, #btnRetake, #btnSubmit').hide();

        if(data.state === 'all_done') {
            $('#stateAllDone').show();
            $('#stateAllDoneMsg').text(data.msg);
            $('#attFormWrap').hide();

        } else if(data.state === 'checkin_only') {
            $('#stateCheckedInOnly').show();
            $('#checkedInMsg').text('Checked in at ' + data.checkin_time);
            $('#att_action_type').val('check_out');
            $('#btnSubmitLabel').text('Confirm Check Out');
            // KPI block only for today's checkout
            var isToday = (selDate === '<?php echo date('Y-m-d'); ?>');
            if(isToday && todayCheckedIn && !userKpiComplete) {
                $('#attFormWrap').hide();
                $('#kpiBlockingModal').modal('show');
                return;
            }
            initGPS();

        } else {
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

// Show KPI blocking page - NO ACCESS for checkout
function showKPIBlockingPage() {
    $('#kpiBlockingModal').modal('show');
}

// Removed leave site confirmation prompts

$(document).ready(function() {
    $('.select2').select2({ width: '100%' });
    
    <?php if($is_admin && $admin_result && mysqli_num_rows($admin_result) > 0): ?>
    $('#adminTable').DataTable({ pageLength: 50, order: [[0, 'desc']] });
    <?php endif; ?>
    
    <?php if($user_emp_data && $my_result && mysqli_num_rows($my_result) > 0): ?>
    // NOTE: Order is set to 0 (Date column), DESC (Latest first)
    $('#personalTable').DataTable({ pageLength: 50, order: [[0, 'desc']] });
    <?php endif; ?>
    
    $('#markModal').on('shown.bs.modal', function() {
        // Scroll modal to top
        $('.modal-body').scrollTop(0);
    });
    
    $('#markModal').on('hidden.bs.modal', function() {
        if(typeof stream !== 'undefined' && stream) stream.getTracks().forEach(t => t.stop());
        resetCamera();
        $('#btnStart').show();
    });
    
    setTimeout(function() { $('.alert').fadeOut('slow'); }, 5000);
});

function showPhoto(src) {
    $('#viewImg').attr('src', src);
    $('#photoModal').modal('show');
}

function initGPS() {
    if(!navigator.geolocation) {
        $('#gpsStatus').attr('class', 'gps-status gps-bad').html('<i class="fas fa-times-circle"></i> GPS not supported');
        return;
    }
    
    $('#gpsStatus').attr('class', 'gps-status').html('<i class="fas fa-spinner fa-spin"></i> Getting Location...');
    
    function tryGPS(highAccuracy) {
        navigator.geolocation.getCurrentPosition(function(pos) {
            const lat = pos.coords.latitude;
            const lng = pos.coords.longitude;
            
            // Sanity check - reject 0,0 coordinates
            if(lat == 0 && lng == 0) {
                $('#gpsStatus').attr('class', 'gps-status gps-bad').html('<i class="fas fa-exclamation-triangle"></i> GPS returned invalid location. Try again.');
                return;
            }
            
            $('#lat').val(lat);
            $('#lng').val(lng);
            
            if(bypassLocation) {
                $('#gpsStatus').attr('class', 'gps-status gps-ok')
                    .html('<i class="fas fa-check-circle"></i> Location Verified: Remote/Field Work Allowed');
                $('#btnSubmit').prop('disabled', false);
                fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`)
                    .then(r=>r.json()).then(d=>$('#loc_name').val(d.display_name)).catch(e=>{});
                return;
            }
            
            let targetOffices = allOffices;
            if(userAssignedLocation && allOffices[userAssignedLocation]) {
                targetOffices = {};
                targetOffices[userAssignedLocation] = allOffices[userAssignedLocation];
            }

            let minDist = 999999;
            let nearName = 'Unknown';
            
            for(let name in targetOffices) {
                let d = getDistance(lat, lng, targetOffices[name].lat, targetOffices[name].lng);
                if(d < minDist) { minDist = d; nearName = name; }
            }
            
            fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`)
                .then(r=>r.json()).then(d=>$('#loc_name').val(d.display_name)).catch(e=>{});
                
            if(minDist <= 200) {
                $('#gpsStatus').attr('class', 'gps-status gps-ok')
                    .html(`<i class="fas fa-check-circle"></i> Verified: ${nearName} (${Math.round(minDist)}m)`);
                $('#btnSubmit').prop('disabled', false);
            } else {
                $('#gpsStatus').attr('class', 'gps-status gps-bad')
                    .html(`<i class="fas fa-times-circle"></i> Too far: ${Math.round(minDist)}m from ${nearName}`);
                $('#btnSubmit').prop('disabled', true);
            }
        }, function(err) {
            if(highAccuracy) {
                // High accuracy failed - try low accuracy
                tryGPS(false);
            } else {
                const errors = {1: 'Permission Denied', 2: 'Position Unavailable', 3: 'Timeout'};
                $('#gpsStatus').attr('class', 'gps-status gps-bad')
                    .html('<i class="fas fa-exclamation-triangle"></i> GPS Error ' + err.code + ': ' + (errors[err.code] || err.message));
            }
        }, {enableHighAccuracy: highAccuracy, timeout: 15000, maximumAge: 0});
    }
    
    tryGPS(true);
}

function getDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2-lat1) * Math.PI/180;
    const dLon = (lon2-lon1) * Math.PI/180;
    const a = Math.sin(dLat/2)*Math.sin(dLat/2) + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
    return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))) * 1000;
}

let stream;
function startCamera() {
    var videoEl = document.getElementById('video');
    
    // Try front camera first, fallback to any camera
    var constraints = { video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 } }, audio: false };
    
    navigator.mediaDevices.getUserMedia(constraints)
        .then(function(s) {
            stream = s;
            videoEl.srcObject = s;
            videoEl.onloadedmetadata = function() {
                videoEl.play().catch(function(e) {
                    console.warn('Video play error:', e);
                });
            };
            $('#btnStart').hide();
            $('#btnSnap').show();
            setTimeout(function() {
                videoEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }, 300);
        })
        .catch(function(err) {
            console.error('Camera error:', err.name, err.message);
            // Fallback: try with minimal constraints
            if(err.name === 'OverconstrainedError' || err.name === 'ConstraintNotSatisfiedError') {
                navigator.mediaDevices.getUserMedia({ video: true, audio: false })
                    .then(function(s) {
                        stream = s;
                        videoEl.srcObject = s;
                        videoEl.onloadedmetadata = function() { videoEl.play(); };
                        $('#btnStart').hide();
                        $('#btnSnap').show();
                    })
                    .catch(function(e2) {
                        alert('Camera Error: ' + e2.message + '\n\nPlease allow camera access and try again.');
                    });
            } else if(err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError') {
                alert('Camera permission denied.\n\nPlease allow camera access in your browser/app settings and try again.');
            } else if(err.name === 'NotFoundError' || err.name === 'DevicesNotFoundError') {
                alert('No camera found on this device.');
            } else {
                alert('Camera Error: ' + err.message + '\n\nPlease try again.');
            }
        });
}

function takePhoto() {
    const v = $('#video')[0];
    const c = $('#canvas')[0];
    
    // Guard: ensure video has actual dimensions
    var w = v.videoWidth || 640;
    var h = v.videoHeight || 480;
    
    c.width = w;
    c.height = h;
    c.getContext('2d').drawImage(v, 0, 0, w, h);
    const data = c.toDataURL('image/png');
    
    // Guard: ensure photo was actually captured (not blank)
    if(!data || data === 'data:,') {
        alert('Photo capture failed. Please wait for camera to load fully and try again.');
        return;
    }
    
    $('#photo_data').val(data);
    $('#preview').attr('src', data).show();
    $('#video').hide();
    $('#btnSnap').hide();
    $('#btnRetake').show();
    $('#btnSubmit').show();
}

function resetCamera() {
    $('#preview').hide();
    $('#photo_data').val('');
    $('#video').show();
    $('#btnRetake').hide();
    $('#btnSnap').show();
    $('#btnSubmit').hide();
}

$('#attForm').on('submit', function(e) {
    if(!$('#photo_data').val() || !$('#lat').val() || !$('#lng').val()) {
        e.preventDefault();
        alert("Photo and GPS required");
        return false;
    }
});

function deleteAttendance(empId, date) {
    if(!confirm('Delete attendance record for ' + empId + ' on ' + date + '?\nThis cannot be undone.')) return;
    $.post('', {
        delete_attendance: 1,
        employee_id: empId,
        date: date,
        user_email: '<?php echo addslashes($currentUserEmail); ?>'
    }, function(r) {
        if(r.success) { alert('✅ ' + r.message); location.reload(); }
        else alert('❌ ' + r.message);
    }, 'json').fail(function() { alert('Request failed. Please try again.'); });
}
</script>
</body>
</html>