<?php 
// ============================================================================
// ATTENDANCE SYSTEM - WITH MIDNIGHT CROSSOVER FIX
// Fix: Employees who check in before midnight can check out after midnight
// Logic: If no today record found for checkout AND time < 06:00 AM,
//        look back to yesterday's unclosed check-in
// ============================================================================
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);
date_default_timezone_set('Asia/Kolkata');

if(session_status() === PHP_SESSION_NONE) session_start();

require_once('database.php');
require_once('library.php');
require_once('funciones.php');

isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// ============================================================================
// ROLE DETECTION
// ============================================================================
$is_super_admin = (stripos($currentUserName, 'Abishek') !== false || stripos($currentUserName, 'abishek') !== false);
$is_keerti      = (stripos($currentUserName, 'Keerti')  !== false || stripos($currentUserName, 'Keerthi') !== false);

$user_emp_data = null;
if(!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($dbConn, $currentUserName);
    $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) AND status = 'active' LIMIT 1");
    if(!$emp_check || mysqli_num_rows($emp_check) == 0) {
        if($is_super_admin)
            $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%abishek%' OR employee_id = 'ABRA001') AND status = 'active' LIMIT 1");
        elseif($is_keerti)
            $emp_check = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE (LOWER(name) LIKE '%keerti%' OR LOWER(name) LIKE '%keerthi%') AND status = 'active' LIMIT 1");
    }
    if($emp_check && mysqli_num_rows($emp_check) > 0)
        $user_emp_data = mysqli_fetch_assoc($emp_check);
    
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
}

$is_managing_director = false;
if($user_emp_data) {
    $user_position        = $user_emp_data['position'] ?? '';
    $is_managing_director = (
        stripos($user_position, 'managing director') !== false ||
        stripos($user_position, 'md')                !== false ||
        stripos($user_position, 'ceo')               !== false
    );
}

$is_admin = ($is_super_admin || $is_keerti || $is_managing_director);

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
$current_hour   = intval(date('H')); // 0–23
$is_after_midnight_before_6am = ($current_hour >= 0 && $current_hour < 6);

$pending_yesterday_checkin = null;
if($user_emp_data) {
    $emp_id_safe = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $prev_q = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id = '$emp_id_safe' AND date = '$yesterday' AND check_out_time IS NULL LIMIT 1");
    if($prev_q && mysqli_num_rows($prev_q) > 0 && $is_after_midnight_before_6am) {
        $pending_yesterday_checkin = mysqli_fetch_assoc($prev_q);
    }
}

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

        $user_position_check   = strtolower(trim($user_emp_data['position']   ?? ''));
        $user_department_check = strtolower(trim($user_emp_data['department'] ?? ''));
        $bypass_location = (
            stripos($user_position_check,   'managing director') !== false ||
            stripos($user_position_check,   'management')        !== false ||
            stripos($user_department_check, 'management')        !== false ||
            stripos($user_position_check,   'admin executive')   !== false ||
            stripos($user_position_check,   'warehouse manager') !== false ||
            stripos($user_position_check,   'delivery agent')    !== false
        );

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

        $photo_dir = 'uploads/attendance_photos/' . date('Y/m/');
        if(!file_exists($photo_dir)) mkdir($photo_dir, 0777, true);

        $emp_id   = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
        $emp_name = mysqli_real_escape_string($dbConn, $user_emp_data['name']);
        $now      = date('H:i:s');

        $photo_binary = base64_decode(str_replace(['data:image/png;base64,',' '], ['','+'], $photo_data));
        $photo_name   = preg_replace('/[^A-Za-z0-9\-]/', '', $emp_id) . '_' . date('YmdHis') . '.png';
        $photo_path   = $photo_dir . $photo_name;
        file_put_contents($photo_path, $photo_binary);

        $final_loc = mysqli_real_escape_string($dbConn, "$matched_location_name ($gps_address)");

        // Use the date the employee selected (supports yesterday for OT/night shift)
        $att_date  = isset($_POST['att_date_input']) && !empty($_POST['att_date_input'])
                     ? mysqli_real_escape_string($dbConn, $_POST['att_date_input'])
                     : $today;

        $check    = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id = '$emp_id' AND date = '$att_date' LIMIT 1");
        $existing = mysqli_fetch_assoc($check);

        if($action_type == 'check_in') {
            if($existing) throw new Exception("Already checked in on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_in_time'])) . ".");
            $check_hhmm = substr($now, 0, 5);
            $late_hhmm  = $late_time_threshold;
            $status = ($check_hhmm > $late_hhmm) ? 'late' : 'present';
            mysqli_query($dbConn, "INSERT INTO hr_attendance (employee_id, employee_name, date, check_in_time, check_in_photo, check_in_latitude, check_in_longitude, check_in_location, status, daily_salary) VALUES ('$emp_id', '$emp_name', '$att_date', '$now', '$photo_path', '$latitude', '$longitude', '$final_loc', '$status', '0')");
            header("Location: " . $_SERVER['PHP_SELF'] . "?success=checkin"); exit();

        } elseif($action_type == 'check_out') {
            if(!$existing) throw new Exception("No check-in found for " . date('D, d M Y', strtotime($att_date)) . ". Please check in first.");
            if(!empty($existing['check_out_time'])) throw new Exception("Already checked out on " . date('D, d M Y', strtotime($att_date)) . " at " . date('h:i A', strtotime($existing['check_out_time'])) . ".");

            // KPI only required for today's checkout
            if($att_date == $today) {
                $kpi_check = mysqli_query($dbConn, "SELECT id FROM performance_daily_self WHERE employee_id = '$emp_id' AND review_date = '$today' LIMIT 1");
                if(!$kpi_check || mysqli_num_rows($kpi_check) == 0)
                    throw new Exception("❌ Daily KPI Review Required: Please complete your Daily Self-Evaluation before checking out.");
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
    $where      = ["a.date BETWEEN '$date_from' AND '$date_to'"];
    if($emp_filter) $where[] = "a.employee_id = '$emp_filter'";
    
    // Get both regular attendance and overrides - HR overrides treated as "present"
    $admin_result = mysqli_query($dbConn, "
        SELECT a.*, 'attendance' as record_type FROM hr_attendance a 
        LEFT JOIN hr_employees e ON a.employee_id = e.employee_id 
        LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date 
        WHERE " . implode(' AND ', $where) . " AND ao.id IS NULL
        
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
            NULL as daily_salary, 'override' as record_type
        FROM hr_attendance_overrides ao
        INNER JOIN hr_employees e ON ao.employee_id = e.id
        WHERE ao.attendance_date BETWEEN '$date_from' AND '$date_to'
        " . ($emp_filter ? "AND e.employee_id = '$emp_filter'" : "") . "
        
        ORDER BY date DESC, check_in_time DESC LIMIT 500
    ");
    
    $emp_list_query  = mysqli_query($dbConn, "SELECT employee_id, name, id FROM hr_employees WHERE status = 'active' ORDER BY name ASC");

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
        $r = mysqli_query($dbConn, "SELECT COUNT(*) as total FROM hr_employees WHERE status = 'active' AND employee_id = '$emp_filter'");
    } else {
        $r = mysqli_query($dbConn, "SELECT COUNT(*) as total FROM hr_employees WHERE status = 'active'");
    }
    if($r) $employee_stats['total'] = mysqli_fetch_assoc($r)['total'];

    // Checked in - respect employee filter and include HR overrides
    $checked_in_count = 0;
    
    // Count regular attendance
    $checked_in_where = "date BETWEEN '$stats_date_from' AND '$stats_date_to'";
    if($emp_filter) $checked_in_where .= " AND employee_id = '$emp_filter'";
    $r = mysqli_query($dbConn, "SELECT COUNT(DISTINCT employee_id) as cnt FROM hr_attendance WHERE $checked_in_where");
    if($r) $checked_in_count += intval(mysqli_fetch_assoc($r)['cnt']);
    
    // Count HR overrides for the same employee if filtering by employee
    if($emp_filter) {
        $override_r = mysqli_query($dbConn, "
            SELECT COUNT(DISTINCT e.employee_id) as cnt 
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$emp_filter' 
            AND ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to'
            AND ao.status IN ('present', 'holiday', 'leave')
        ");
        if($override_r) {
            $override_count = intval(mysqli_fetch_assoc($override_r)['cnt']);
            if($override_count > 0) $checked_in_count = 1; // Employee has overrides, so they're "checked in"
        }
    }
    
    $employee_stats['checked_in'] = $checked_in_count;

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
    
    // Get HR overrides if filtering by employee
    if($emp_filter) {
        $override_r = mysqli_query($dbConn, "
            SELECT e.employee_id, e.name as employee_name, ao.attendance_date as date, 
                   '09:00:00' as check_in_time, '18:00:00' as check_out_time, 'present' as status,
                   e.work_location, e.timings, e.department, 'override' as record_type
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$emp_filter' 
            AND ao.attendance_date BETWEEN '$stats_date_from' AND '$stats_date_to'
            AND ao.status IN ('present', 'holiday', 'leave')
            ORDER BY e.name ASC, ao.attendance_date DESC
        ");
        if($override_r) while($row = mysqli_fetch_assoc($override_r)) $employee_stats['checked_in_list'][] = $row;
    }

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
    $emp_where_condition = $emp_filter ? " AND employee_id = '$emp_filter'" : "";
    $all_emp_q = mysqli_query($dbConn, "
        SELECT employee_id, name, work_location, timings, department,
               id as emp_db_id
               " . ($has_joining_date ? ", hire_date" : "") . "
        FROM hr_employees WHERE status = 'active'$emp_where_condition ORDER BY name ASC
    ");

    $not_checked_employees = [];

    if($all_emp_q) {
        while($emp = mysqli_fetch_assoc($all_emp_q)) {
            $emp_start_date = $stats_date_from;

            if($has_joining_date && !empty($emp['hire_date']) && $emp['hire_date'] != '0000-00-00') {
                if(strtotime($emp['hire_date']) > strtotime($stats_date_to)) continue;
                if(strtotime($emp['hire_date']) > strtotime($stats_date_from))
                    $emp_start_date = $emp['hire_date'];
            }

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

            // Find missing working days (exclude Sundays)
            $missing = [];
            $cur     = $emp_start_date;
            while(strtotime($cur) <= strtotime($stats_date_to)) {
                if(date('w', strtotime($cur)) != 0 && !in_array($cur, $covered))
                    $missing[] = $cur;
                $cur = date('Y-m-d', strtotime($cur . ' +1 day'));
            }

            if(count($missing) > 0) {
                $emp['missing_dates'] = $missing;
                $emp['missing_count'] = count($missing);
                $emp['emp_start_date'] = $emp_start_date;
                $not_checked_employees[] = $emp;
            }
        }
    }

    $employee_stats['not_checked_in']      = count($not_checked_employees);
    $employee_stats['not_checked_in_list'] = $not_checked_employees;

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

}

$my_result    = false;
$my_stats     = ['total'=>0,'present'=>0,'late'=>0,'hours'=>0,'ot_days'=>0];
$today_record = null;
$days_this_month = 0;

if($user_emp_data) {
    $my_id = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $today_q = mysqli_query($dbConn, "SELECT * FROM hr_attendance WHERE employee_id = '$my_id' AND date = '$today'");
    if($today_q) $today_record = mysqli_fetch_assoc($today_q);

    // For non-admins, default to 1 month history instead of current week
    $default_start = $is_admin ? date('Y-m-d', strtotime('monday this week')) : date('Y-m-01'); // First day of current month
    $mf_start = isset($_GET['mf_start']) ? mysqli_real_escape_string($dbConn, $_GET['mf_start']) : $default_start;
    $mf_end   = isset($_GET['mf_end'])   ? mysqli_real_escape_string($dbConn, $_GET['mf_end'])   : date('Y-m-d');
    
    // Updated stats query - simplified to ensure HR overrides count as "present"
    $stats_q = mysqli_query($dbConn, "
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN status='present' THEN 1 ELSE 0 END) as present,
            SUM(CASE WHEN status='late' THEN 1 ELSE 0 END) as late,
            SUM(work_hours) as hours
        FROM (
            SELECT a.status, COALESCE(a.work_hours, 0) as work_hours
            FROM hr_attendance a 
            LEFT JOIN hr_employees e ON a.employee_id = e.employee_id 
            LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date 
            WHERE a.employee_id = '$my_id' AND a.date BETWEEN '$mf_start' AND '$mf_end' AND ao.id IS NULL
            
            UNION ALL
            
            SELECT 'present' as status, 0 as work_hours
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id' 
            AND ao.attendance_date BETWEEN '$mf_start' AND '$mf_end'
            AND ao.status IN ('present', 'holiday', 'leave')
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
    $cur_month_start = date('Y-m-01');
    $cur_month_end   = date('Y-m-t');
    $month_att_q = mysqli_query($dbConn, "
        SELECT COUNT(DISTINCT date) as days_this_month
        FROM (
            SELECT date FROM hr_attendance 
            WHERE employee_id = '$my_id' 
            AND date BETWEEN '$cur_month_start' AND '$cur_month_end' 
            AND status IN ('present','late','half_day')
            
            UNION
            
            SELECT ao.attendance_date as date 
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id' 
            AND ao.attendance_date BETWEEN '$cur_month_start' AND '$cur_month_end'
            AND ao.status IN ('present','holiday','leave')
        ) combined_days
    ");
    
    if($month_att_q) $days_this_month = intval(mysqli_fetch_assoc($month_att_q)['days_this_month']);
    $my_stats['ot_days'] = max(0, $days_this_month - 26);
    $my_result = mysqli_query($dbConn, "
        SELECT * FROM (
            SELECT a.*, 'attendance' as record_type FROM hr_attendance a 
            LEFT JOIN hr_employees e ON a.employee_id = e.employee_id 
            LEFT JOIN hr_attendance_overrides ao ON e.id = ao.employee_id AND a.date = ao.attendance_date 
            WHERE a.employee_id = '$my_id' AND a.date BETWEEN '$mf_start' AND '$mf_end' AND ao.id IS NULL
            
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
                NULL as daily_salary, 'override' as record_type
            FROM hr_attendance_overrides ao
            INNER JOIN hr_employees e ON ao.employee_id = e.id
            WHERE e.employee_id = '$my_id' AND ao.attendance_date BETWEEN '$mf_start' AND '$mf_end'
        ) combined_records
        ORDER BY date DESC, check_in_time DESC LIMIT 500
    ");
}

$user_attendance_complete = ($today_record && !empty($today_record['check_out_time']));
$user_kpi_complete = false;
$user_kpi_score    = null;
if($user_emp_data) {
    $emp_id_safe = mysqli_real_escape_string($dbConn, $user_emp_data['employee_id']);
    $kpi_check   = mysqli_query($dbConn, "SELECT id, total_score FROM performance_daily_self WHERE employee_id = '$emp_id_safe' AND review_date = '$today' AND submitted_at IS NOT NULL LIMIT 1");
    if($kpi_check && mysqli_num_rows($kpi_check) > 0) { $user_kpi_complete = true; $user_kpi_score = mysqli_fetch_assoc($kpi_check)['total_score']; }
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

?>
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
    .btn-delete-attendance{background:linear-gradient(135deg,#ef4444,#dc2626);color:white;border:none;padding:8px 12px;border-radius:8px;cursor:pointer;transition:all 0.3s;font-weight:600;display:inline-flex;align-items:center;gap:5px;}
    .btn-delete-attendance:hover{transform:translateY(-2px);box-shadow:0 4px 12px rgba(239,68,68,0.4);}
    @media(max-width:768px){.page-header{flex-direction:column;gap:15px;}.filter-row{flex-direction:column;}.stat-card{min-width:150px;}}
  </style>
</head>
<body>

<div class="alert-container">
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
      <?php if($user_emp_data): ?>
      <button class="btn-header btn-success-custom" onclick="handleMarkAttendance()">
        <i class="fas fa-plus-circle"></i> Mark Attendance
      </button>
      <?php endif; ?>
      <a href="<?php echo $is_super_admin ? 'index.php' : 'https://crm.abra-logistic.com/dashboard/raise-a-ticket.php'; ?>" class="btn-header btn-primary-custom">
        <i class="fas fa-arrow-left"></i> Dashboard
      </a>
    </div>
  </div>

  <?php if($is_admin): ?>
  <div class="stats-row">
    <div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-users"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['total']); ?></h3><p>Total Employees</p></div></div>
    <div class="stat-card green clickable" onclick="showCheckedIn()"><div class="stat-icon green"><i class="fas fa-user-check"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['checked_in']); ?></h3><p>Checked In</p></div></div>
    <div class="stat-card orange clickable" onclick="showLateEmployees()"><div class="stat-icon orange"><i class="fas fa-clock"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['late_today']); ?></h3><p>Late</p></div></div>
    <div class="stat-card red clickable" onclick="showNotCheckedIn()"><div class="stat-icon red"><i class="fas fa-user-times"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['not_checked_in']); ?></h3><p>Not Checked In</p></div></div>
    <div class="stat-card blue clickable" onclick="showNotLoggedOff()"><div class="stat-icon blue"><i class="fas fa-sign-out-alt"></i></div><div class="stat-content"><h3><?php echo number_format($employee_stats['not_logged_off']); ?></h3><p>Not Logged Off</p></div></div>
  </div>
  <form method="GET">
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
              <option value="<?php echo htmlspecialchars($emp['employee_id']); ?>" <?php echo (isset($emp_filter) && $emp_filter == $emp['employee_id']) ? 'selected' : ''; ?>><?php echo htmlspecialchars($emp['name']); ?></option>
            <?php endwhile; endif; ?>
          </select>
        </div>
        <div style="margin-top:22px;"><button type="submit" class="btn-header btn-primary-custom"><i class="fas fa-search"></i> Apply</button></div>
      </div>
    </div>
  </form>
  
  <?php if($admin_result && mysqli_num_rows($admin_result) > 0): ?>
  <div class="table-container">
    <div class="table-header-actions">
      <h5><i class="fas fa-table"></i> All Employee Attendance</h5>
      <a href="?action=export&export_type=admin&date_from=<?php echo urlencode($date_from); ?>&date_to=<?php echo urlencode($date_to); ?>&employee=<?php echo urlencode(isset($emp_filter)?$emp_filter:''); ?>" class="btn-header btn-export-custom"><i class="fas fa-download"></i> Export CSV</a>
    </div>
    <table id="adminTable" class="display nowrap" style="width:100%">
      <thead><tr><th>Date</th><th>Day</th><th>Employee</th><th>Check In</th><th>Check Out</th><th>Work Hrs</th><th>Status</th><th>Photos</th><?php if($is_admin): ?><th>Actions</th><?php endif; ?></tr></thead>
      <tbody>
        <?php mysqli_data_seek($admin_result, 0); while($row = mysqli_fetch_assoc($admin_result)): ?>
        <tr <?php echo (isset($row['record_type']) && $row['record_type'] == 'override') ? 'style="background-color: #f0f9ff; border-left: 4px solid #3b82f6;"' : ''; ?>>
          <td><?php echo date('M d, Y', strtotime($row['date'])); ?></td>
          <td><?php echo date('l', strtotime($row['date'])); ?></td>
          <td>
            <div style="font-weight:700"><?php echo htmlspecialchars($row['employee_name']); ?></div>
            <div style="font-size:11px;color:#64748b"><?php echo htmlspecialchars($row['employee_id']); ?></div>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <div style="font-size:10px;color:#3b82f6;font-weight:600;"><i class="fas fa-user-edit"></i> HR Override</div>
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">Override</span>
            <?php else: ?>
              <?php echo date('h:i A', strtotime($row['check_in_time'])); ?>
            <?php endif; ?>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">Override</span>
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
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">—</span>
            <?php else: ?>
              <?php echo $row['work_hours'] ? $row['work_hours'].' hr' : '—'; ?>
            <?php endif; ?>
          </td>
          <td>
            <span class="badge badge-<?php 
              echo $row['status']=='present'?'success':
                  ($row['status']=='late'?'warning':'danger'); 
            ?>">
              <?php 
              if(isset($row['record_type']) && $row['record_type'] == 'override') {
                echo 'Present (HR)';
              } else {
                echo ucfirst($row['status']); 
              }
              ?>
            </span>
          </td>
          <td>
            <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
              <span style="color:#64748b;font-style:italic;">—</span>
            <?php else: ?>
              <?php if($row['check_in_photo']): ?><img src="<?php echo $row['check_in_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
              <?php if($row['check_out_photo']): ?><img src="<?php echo $row['check_out_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            <?php endif; ?>
          </td>
          <?php if($is_admin): ?>
          <td>
            <button class="btn-delete-attendance" onclick="deleteAttendance('<?php echo $row['employee_id']; ?>', '<?php echo $row['date']; ?>', '<?php echo htmlspecialchars($row['employee_name']); ?>')" title="Delete Attendance">
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
  <div style="text-align:center;padding:60px 20px;background:#f1f5f9;border-radius:12px;margin:20px 0;"><i class="fas fa-calendar-times" style="font-size:64px;color:#94a3b8;margin-bottom:20px;display:block;"></i><h4 style="color:#475569">No Attendance Records Found</h4></div>
  <?php endif; ?>
  <?php endif; ?>

  <!-- PERSONAL ATTENDANCE SECTION - ALWAYS SHOWN FOR LOGGED IN USERS -->
  <?php if($user_emp_data): ?>
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
  <div class="table-container">
    <div class="table-header-actions">
      <h5><i class="fas fa-user"></i> My Attendance Records</h5>
      <?php if($my_result && mysqli_num_rows($my_result) > 0): ?>
      <a href="?action=export&export_type=personal&mf_start=<?php echo urlencode($mf_start); ?>&mf_end=<?php echo urlencode($mf_end); ?>" class="btn-header btn-export-custom"><i class="fas fa-download"></i> Export My Records</a>
      <?php endif; ?>
    </div>
    <table id="personalTable" class="display nowrap" style="width:100%">
      <thead><tr><th>Date</th><th>Day</th><th>Check In</th><th>Check Out</th><th>Work Hours</th><th>Status</th><th>Photos</th></tr></thead>
      <tbody>
      <?php if($my_result && mysqli_num_rows($my_result) > 0):
          mysqli_data_seek($my_result, 0);
          while($row = mysqli_fetch_assoc($my_result)): ?>
      <tr <?php echo (isset($row['record_type']) && $row['record_type'] == 'override') ? 'style="background-color: #f0f9ff; border-left: 4px solid #3b82f6;"' : ''; ?>>
        <td>
          <strong><?php echo date('M d, Y', strtotime($row['date'])); ?></strong>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <div style="font-size:10px;color:#3b82f6;font-weight:600;"><i class="fas fa-user-edit"></i> HR Override</div>
          <?php endif; ?>
        </td>
        <td><?php echo date('l', strtotime($row['date'])); ?></td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">Override</span>
          <?php else: ?>
            <?php echo date('h:i A', strtotime($row['check_in_time'])); ?>
          <?php endif; ?>
        </td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">Override</span>
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
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">—</span>
          <?php else: ?>
            <?php echo $row['work_hours'] ? $row['work_hours'].' hr' : '—'; ?>
          <?php endif; ?>
        </td>
        <td>
          <span class="badge badge-<?php 
            echo $row['status']=='present'?'success':
                ($row['status']=='late'?'warning':'danger'); 
          ?>">
            <?php 
            if(isset($row['record_type']) && $row['record_type'] == 'override') {
              echo 'Present (HR)';
            } else {
              echo ucfirst($row['status']); 
            }
            ?>
          </span>
        </td>
        <td>
          <?php if(isset($row['record_type']) && $row['record_type'] == 'override'): ?>
            <span style="color:#64748b;font-style:italic;">—</span>
          <?php else: ?>
            <?php if($row['check_in_photo']): ?><img src="<?php echo $row['check_in_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
            <?php if($row['check_out_photo']): ?><img src="<?php echo $row['check_out_photo']; ?>" class="photo-thumb" onclick="showPhoto(this.src)"><?php endif; ?>
          <?php endif; ?>
        </td>
      </tr>
      <?php endwhile; else: ?>
        <tr><td colspan="7" style="text-align:center;padding:30px;color:#94a3b8">No records found.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

<!-- MARK ATTENDANCE MODAL -->
<?php if($user_emp_data): ?>
<div class="modal fade" id="markModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal">&times;</button>
        <h4 class="modal-title"><i class="fas fa-camera"></i> Mark Attendance</h4>
      </div>
      <div class="modal-body">

        <!-- DATE PICKER — always shown first -->
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
              <input type="hidden" name="action_type"    id="att_action_type">
              <input type="hidden" name="att_date_input" id="att_date_input">
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
<?php endif; ?>

<!-- KPI BLOCKING MODAL -->
<div class="modal fade" id="kpiBlockingModal" tabindex="-1" data-backdrop="static" data-keyboard="false">
  <div class="modal-dialog modal-lg"><div class="modal-content" style="border:3px solid #dc2626;"><div class="modal-header" style="background:linear-gradient(135deg,#dc2626,#b91c1c);border:none;"><h4 class="modal-title" style="color:white;font-size:24px;font-weight:800;"><i class="fas fa-ban"></i> Complete Your Daily KPI First</h4></div><div class="modal-body" style="padding:50px 30px;text-align:center;background:#fef2f2;"><i class="fas fa-lock" style="font-size:100px;color:#dc2626;margin-bottom:30px;display:block;"></i><h2 style="color:#991b1b;font-weight:800;margin-bottom:20px;">Check-Out Blocked</h2><p style="font-size:16px;color:#475569;margin-bottom:30px;">Complete your <strong>Daily Self-Evaluation Review</strong> before checking out.</p><div style="display:flex;gap:15px;justify-content:center;flex-wrap:wrap;"><a href="hr-kpi-evaluation.php" class="btn-header btn-danger-custom" style="font-size:18px;padding:15px 30px;"><i class="fas fa-clipboard-check"></i> Complete Daily Review</a><button type="button" class="btn-header btn-primary-custom" onclick="$('#kpiBlockingModal').modal('hide')" style="font-size:18px;padding:15px 30px;"><i class="fas fa-times"></i> Close</button></div></div></div></div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/js/select2.min.js"></script>
<script>
const userAssignedLocation    = "<?php echo $user_assigned_location; ?>";
const allOffices              = <?php echo json_encode($all_valid_offices); ?>;
const todayCheckedIn          = <?php echo $today_in  ? 'true' : 'false'; ?>;
const userKpiComplete         = <?php echo $user_kpi_complete ? 'true' : 'false'; ?>;
const hasPendingNightCheckout = <?php echo $pending_yesterday_checkin ? 'true' : 'false'; ?>;
const userPosition            = "<?php echo strtolower(trim($user_emp_data['position']   ?? '')); ?>";
const userDepartment          = "<?php echo strtolower(trim($user_emp_data['department'] ?? '')); ?>";

const bypassLocation = (
    userPosition.includes('managing director') || userPosition.includes('management') ||
    userDepartment.includes('management')      || userPosition.includes('admin executive') ||
    userPosition.includes('warehouse manager') || userPosition.includes('delivery agent')
);

function showNotCheckedIn()  { $('#notCheckedInModal').modal('show'); }
function showCheckedIn()     { $('#checkedInModal').modal('show'); }
function showLateEmployees() { $('#lateEmployeesModal').modal('show'); }
function showNotLoggedOff()  { $('#notLoggedOffModal').modal('show'); }

function handleMarkAttendance() {
    // Reset modal to date picker step every time
    $('#statusPanel').hide();
    $('#datePickerStep').show();
    resetCamera();
    $('#att_date').val('<?php echo date('Y-m-d'); ?>');
    $('#markModal').modal('show');
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

        // Set the hidden date & reset camera
        $('#att_date_input').val(selDate);
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
            // KPI check — only block for today's checkout
            var isToday = (selDate === '<?php echo date('Y-m-d'); ?>');
            if(isToday && todayCheckedIn && !userKpiComplete) {
                $('#attFormWrap').hide();
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
</script>
</body>
</html>