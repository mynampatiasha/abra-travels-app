<?php
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 0); // Set to 0 for production

if (session_status() == PHP_SESSION_NONE) {
    session_start();
    // TEMP DEBUG - REMOVE AFTER FIXING
if (isset($_GET['debug_session'])) {
    echo "<pre style='background:#fff3cd;padding:20px;margin:20px;border:2px solid #ffc107;'>";
    echo "<strong>SESSION DATA:</strong>\n";
    print_r($_SESSION);
    echo "\n<strong>GET DATA:</strong>\n";
    print_r($_GET);
    echo "</pre>";
    exit;
}
}

// --- TIMEZONE FIX (Force India Time) ---
date_default_timezone_set('Asia/Kolkata');

// Include required files
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require_once('requirelanguage.php');

$con = conexion();
if (!$con) die("Database connection failed");

// --- CHARSET FIX ---
mysqli_set_charset($con, 'utf8mb4');

// if(function_exists('isUser')) isUser();

// --- SYSTEM CONFIGURATION ---
$system_start_date = '2026-01-28'; 

// --- FETCH MASTER DATA FOR FILTERS ---
$depts_master = [];
$res_d = mysqli_query($con, "SELECT name FROM hr_departments ORDER BY name ASC");
if($res_d) { while($d = mysqli_fetch_assoc($res_d)) { $depts_master[] = $d['name']; } }

$pos_master = [];
$res_p = mysqli_query($con, "SELECT title FROM hr_positions ORDER BY title ASC");
if($res_p) { while($p = mysqli_fetch_assoc($res_p)) { $pos_master[] = $p['title']; } }

// --- AJAX & EXPORT HANDLERS ---

/**
 * 1. BULK CSV EXPORT HANDLER
 */
if (isset($_GET['export_history_csv'])) {
    ob_clean();
    $filename = "Performance_Bulk_Export_" . date('Ymd_His') . ".csv";
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    $output = fopen('php://output', 'w');
    
    // Header Row
    fputcsv($output, ['Review Type', 'Employee ID', 'Employee Name', 'Manager Name', 'Period Start', 'Period End', 'Score (%)', 'Rating Status']);

    $f_start = $_GET['start'] ?? '';
    $f_end = $_GET['end'] ?? '';
    $f_type = $_GET['type_filter'] ?? '';
    $f_emp = $_GET['emp_filter'] ?? '';
    $view_context = $_GET['view_context'] ?? 'self';
    $current_emp_id = $_GET['current_user_id'] ?? '';
    $is_admin_mode = ($_GET['is_admin'] == '1');

    $tables = [];
    if (strpos($view_context, 'mgr') !== false) {
        $tables = [
            ['tbl'=>'performance_weekly_manager', 'date'=>'week_start_date', 'label'=>'Weekly Manager', 'k'=>'weekly_manager'],
            ['tbl'=>'performance_monthly_manager', 'date'=>'review_month', 'label'=>'Monthly Manager', 'k'=>'monthly_manager'],
            ['tbl'=>'performance_quarterly_manager', 'date'=>'review_quarter', 'label'=>'Quarterly Manager', 'k'=>'quarterly_manager'],
            ['tbl'=>'performance_halfyearly_manager', 'date'=>'review_halfyear', 'label'=>'Half-Yearly Manager', 'k'=>'halfyearly_manager'],
            ['tbl'=>'performance_yearly_manager', 'date'=>'review_year', 'label'=>'Yearly Manager', 'k'=>'yearly_manager']
        ];
    } else {
        $tables = [
            ['tbl'=>'performance_daily_self', 'date'=>'review_date', 'label'=>'Daily Self', 'k'=>'daily_self'],
            ['tbl'=>'performance_weekly_self', 'date'=>'week_start_date', 'label'=>'Weekly Self', 'k'=>'weekly_self'],
            ['tbl'=>'performance_monthly_self', 'date'=>'review_month', 'label'=>'Monthly Self', 'k'=>'monthly_self'],
            ['tbl'=>'performance_quarterly_self', 'date'=>'review_quarter', 'label'=>'Quarterly Self', 'k'=>'quarterly_self'],
            ['tbl'=>'performance_halfyearly_self', 'date'=>'review_halfyear', 'label'=>'Half-Yearly Self', 'k'=>'halfyearly_self'],
            ['tbl'=>'performance_yearly_self', 'date'=>'review_year', 'label'=>'Yearly Self', 'k'=>'yearly_self']
        ];
    }

    foreach ($tables as $t) {
        if ($f_type && strpos($t['k'], $f_type) === false) continue;

        $sql = "SELECT * FROM `{$t['tbl']}` WHERE 1=1";
        if (!$is_admin_mode) $sql .= " AND employee_id='$current_emp_id'";
        if ($is_admin_mode && $f_emp) $sql .= " AND employee_id='$f_emp'";
        
        // Handle date filtering based on column type
        if ($f_start) {
            if ($t['date'] == 'review_month') {
                // For monthly reviews, extract year-month from start date
                $sql .= " AND {$t['date']} >= '" . date('Y-m', strtotime($f_start)) . "'";
            } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
                // For quarter/halfyear/year, we need to check if the period overlaps with the date range
                // For now, just do a simple string comparison which works for these formats
                $sql .= " AND {$t['date']} >= '" . date('Y', strtotime($f_start)) . "'";
            } else {
                $sql .= " AND {$t['date']} >= '$f_start'";
            }
        }
        if ($f_end) {
            if ($t['date'] == 'review_month') {
                // For monthly reviews, extract year-month from end date
                $sql .= " AND {$t['date']} <= '" . date('Y-m', strtotime($f_end)) . "'";
            } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
                // For quarter/halfyear/year, check if period is within range
                $sql .= " AND {$t['date']} <= '" . date('Y', strtotime($f_end)) . "'";
            } else {
                $sql .= " AND {$t['date']} <= '$f_end'";
            }
        }

        $q = mysqli_query($con, $sql);
        while ($row = mysqli_fetch_assoc($q)) {
            $score_val = $row['total_score'];
            $rating_label = "N/A";
            if ($score_val == -1) { $rating_label = "On Leave"; $score_val = "0"; }
            else if ($score_val >= 95) $rating_label = "Significant";
            else if ($score_val >= 90) $rating_label = "Outstanding";
            else if ($score_val >= 85) $rating_label = "Excellent";
            else if ($score_val >= 80) $rating_label = "Good";
            else if ($score_val >= 70) $rating_label = "Average";
            else $rating_label = "Poor";

            fputcsv($output, [
                $t['label'],
                $row['employee_id'],
                $row['employee_name'],
                $row['manager_name'] ?? 'Self',
                $row[$t['date']],
                $row['week_end_date'] ?? $row[$t['date']],
                ($row['total_score'] == -1 ? 'On Leave' : $row['total_score'].'%'),
                $rating_label
            ]);
        }
    }
    fclose($output);
    exit;
}

/**
 * 2. INDIVIDUAL RECORD EXPORT HANDLER
 */
if (isset($_GET['export_single_csv'])) {
    ob_clean();
    $review_id = intval($_GET['export_single_csv']);
    $review_type = mysqli_real_escape_string($con, $_GET['type']);
    
    // Determine tables
    $table = ''; $ans_table = '';
    if(strpos($review_type, 'manager') !== false) {
        $ans_table = 'performance_answers_manager';
        $mapping = [
            'weekly_manager' => 'performance_weekly_manager',
            'monthly_manager' => 'performance_monthly_manager',
            'quarterly_manager' => 'performance_quarterly_manager',
            'halfyearly_manager' => 'performance_halfyearly_manager',
            'yearly_manager' => 'performance_yearly_manager'
        ];
        $table = $mapping[$review_type] ?? '';
    } else {
        $ans_table = 'performance_answers_self';
        $mapping = [
            'daily_self' => 'performance_daily_self',
            'weekly_self' => 'performance_weekly_self',
            'monthly_self' => 'performance_monthly_self',
            'quarterly_self' => 'performance_quarterly_self',
            'halfyearly_self' => 'performance_halfyearly_self',
            'yearly_self' => 'performance_yearly_self'
        ];
        $table = $mapping[$review_type] ?? '';
    }

    if($table) {
        $res = mysqli_query($con, "SELECT * FROM `$table` WHERE id=$review_id LIMIT 1");
        $master = mysqli_fetch_assoc($res);
        if($master) {
            $filename = "Review_" . $review_type . "_" . $master['employee_id'] . "_" . date('Ymd') . ".csv";
            header('Content-Type: text/csv; charset=utf-8');
            header('Content-Disposition: attachment; filename="' . $filename . '"');
            $output = fopen('php://output', 'w');

            // Metadata info
            fputcsv($output, ['PERFORMANCE REVIEW REPORT']);
            fputcsv($output, ['Employee', $master['employee_name'] . ' (' . $master['employee_id'] . ')']);
            fputcsv($output, ['Review Type', strtoupper(str_replace('_', ' ', $review_type))]);
            fputcsv($output, ['Score', ($master['total_score'] == -1 ? 'ON LEAVE' : $master['total_score'] . '%')]);
            fputcsv($output, []);
            fputcsv($output, ['Question #', 'Question Text', 'Answer', 'Additional Details / Comments']);

            $ans_res = mysqli_query($con, "
                SELECT a.question_number,
                       a.answer_text,
                       a.sub_answer_text,
                       CASE 
                           WHEN a.question_text IS NOT NULL AND TRIM(a.question_text) != ''
                               THEN a.question_text
                           ELSE COALESCE(q.question_text, CONCAT('Question #', a.question_number))
                       END as question_text
                FROM `$ans_table` a 
                LEFT JOIN performance_questions q ON a.question_id = q.id 
                WHERE a.review_id = $review_id 
                AND a.review_type = '$review_type'
                ORDER BY a.question_number ASC
            ");
            while($ans = mysqli_fetch_assoc($ans_res)) {
                fputcsv($output, [
                    $ans['question_number'],
                    $ans['question_text'],
                    $ans['answer_text'],
                    $ans['sub_answer_text'] ?? ''
                ]);
            }
            fclose($output);
            exit;
        }
    }
    die("Record not found.");
}

// Check if ticket exists
if(isset($_GET['ajax_check_ticket'])) {
    ob_clean();
    header('Content-Type: application/json');
    
    $review_id = mysqli_real_escape_string($con, $_GET['review_id']);
    $review_type = mysqli_real_escape_string($con, $_GET['review_type']);
    $ref_tag = "[Ref: $review_type-$review_id"; // Matches partial ref to catch any question ticket
    
    $check_sql = "SELECT t.ticket_number, t.status, e.name as assigned_name 
                  FROM tickets t 
                  LEFT JOIN hr_employees e ON t.assigned_to = e.id 
                  WHERE t.message LIKE '%$ref_tag%' LIMIT 1";
                  
    $result = mysqli_query($con, $check_sql);
    
    if($result && mysqli_num_rows($result) > 0) {
        $row = mysqli_fetch_assoc($result);
        echo json_encode([
            'exists' => true, 
            'ticket_number' => $row['ticket_number'],
            'status' => $row['status'],
            'assigned_name' => $row['assigned_name'] ? $row['assigned_name'] : 'Unknown Employee'
        ]);
    } else {
        echo json_encode(['exists' => false]);
    }
    exit;
}

// --- SMART TICKET CREATION LOGIC (MULTIPLE TICKETS) ---
if(isset($_POST['ajax_create_ticket'])) {
    ob_clean();
    header('Content-Type: application/json');
    
    try {
        $review_id = mysqli_real_escape_string($con, $_POST['review_id']);
        $review_type = mysqli_real_escape_string($con, $_POST['review_type']);
        $target_emp_name = mysqli_real_escape_string($con, $_POST['target_employee_name']);
        $target_emp_id_str = mysqli_real_escape_string($con, $_POST['target_employee_id']);
        $score = mysqli_real_escape_string($con, $_POST['score']);
        $notes = mysqli_real_escape_string($con, $_POST['notes']);
        
        $current_user_name = isset($_SESSION['user_name']) ? $_SESSION['user_name'] : 'System';
        
        // Find Assigned Employee ID
        $assigned_to = null;
        $emp_lookup = mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id = '$target_emp_id_str' AND (status = 'Active' OR status = 'active') LIMIT 1");
        
        if($emp_lookup && mysqli_num_rows($emp_lookup) > 0) {
            $emp_row = mysqli_fetch_assoc($emp_lookup);
            $assigned_to = $emp_row['id'];
        } else {
            $name_lookup = mysqli_query($con, "SELECT id FROM hr_employees WHERE name = '$target_emp_name' AND (status = 'Active' OR status = 'active') LIMIT 1");
            if($name_lookup && mysqli_num_rows($name_lookup) > 0) {
                $emp_row = mysqli_fetch_assoc($name_lookup);
                $assigned_to = $emp_row['id'];
            }
        }
        
        if(!$assigned_to) {
            echo json_encode(['success' => false, 'message' => "Error: Could not find active employee record to assign ticket."]);
            exit;
        }

        // --- FETCH ANSWERS & GENERATE MULTIPLE TICKETS ---
        $ans_table = (strpos($review_type, 'manager') !== false) ? 'performance_answers_manager' : 'performance_answers_self';
        
        $q_details = mysqli_query($con, "
            SELECT a.question_number, a.answer_text, a.sub_answer_text, 
                   COALESCE(a.question_text, q.question_text, 'Question Not Found') as question_text
            FROM `$ans_table` a 
            LEFT JOIN performance_questions q ON a.question_id = q.id 
            WHERE a.review_id = '$review_id'
            AND a.review_type = '$review_type'
        ");
        
        $negative_keywords = ['no', 'weak', 'poor', 'bad', 'not met', 'low', 'average', 'partially', '0', '1', '2'];
        $tickets_generated = 0;
        $priority = ($score < 60) ? 'high' : 'medium';

        if($q_details) {
            while($ans = mysqli_fetch_assoc($q_details)) {
                $raw_ans = strtolower(trim($ans['answer_text']));
                $is_negative = false;
                
                // Detection Logic
                if(in_array($raw_ans, $negative_keywords)) $is_negative = true;
                if(strlen($raw_ans) > 15) $is_negative = true; // Assume detailed explanation implies an issue/context
                
                if($is_negative) {
                    // --- CREATE INDIVIDUAL TICKET ---
                    
                    // Unique Ticket Number for each insertion
                    $ticket_number = 'PERF-' . date('Ymd') . '-' . rand(1000, 9999);
                    
                    // Unique Subject with Question #
                    $subject = "[Performance Issue] $target_emp_name - Q#{$ans['question_number']}";
                    
                    // Specific Message content
                    $message = "🌟 SPECIFIC PERFORMANCE ISSUE - Q{$ans['question_number']}\n" .
                               "==================================================\n" .
                               "❓ Question: " . $ans['question_text'] . "\n" .
                               "💬 Answer: " . $ans['answer_text'] . "\n";
                               
                    if(!empty($ans['sub_answer_text'])) {
                        $message .= "📝 Details: " . $ans['sub_answer_text'] . "\n";
                    }
                    
                    $message .= "==================================================\n" .
                                "👮 Manager Notes: " . $notes . "\n" .
                                "📊 Score: $score ($review_type)\n" .
                                "[Ref: $review_type-$review_id-Q{$ans['question_number']}]"; // Unique Ref

                    $safe_subject = mysqli_real_escape_string($con, $subject);
                    $safe_message = mysqli_real_escape_string($con, $message);
                    
                    // Insert Query Inside Loop
                    $sql = "INSERT INTO tickets 
                            (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at) 
                            VALUES 
                            ('$ticket_number', '$current_user_name', '$safe_subject', '$safe_message', 'Open', '$priority', '$assigned_to', NOW(), NOW())";
                    
                    if(mysqli_query($con, $sql)) {
                        $tickets_generated++;
                    }
                }
            }
        }
        
        // --- FALLBACK: If no specific questions were flagged but manager wants a ticket (e.g., Score Low) ---
        if($tickets_generated == 0) {
            $ticket_number = 'PERF-' . date('Ymd') . '-' . rand(1000, 9999);
            $subject = "[Performance Review] $target_emp_name - General Feedback";
            $message = "🌟 PERFORMANCE REVIEW FEEDBACK\n" .
                       "==================================================\n" .
                       "No specific questions were flagged automatically, but the manager has raised this ticket.\n" .
                       "📊 Score: $score\n" .
                       "📝 MANAGER NOTES:\n" . $notes . "\n" .
                       "[Ref: $review_type-$review_id-General]";
            
            $safe_subject = mysqli_real_escape_string($con, $subject);
            $safe_message = mysqli_real_escape_string($con, $message);
            
            $sql = "INSERT INTO tickets 
                    (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at) 
                    VALUES 
                    ('$ticket_number', '$current_user_name', '$safe_subject', '$safe_message', 'Open', '$priority', '$assigned_to', NOW(), NOW())";
            if(mysqli_query($con, $sql)) $tickets_generated++;
        }
        
        echo json_encode([
            'success' => true, 
            'message' => "Successfully generated $tickets_generated individual ticket(s) for $target_emp_name!"
        ]);
        
    } catch(Exception $e) {
        echo json_encode([
            'success' => false, 
            'message' => "System error: " . $e->getMessage()
        ]);
    }
    exit;
}

// --- USER AUTHENTICATION & MAPPING ---
// ✅ UPDATED: Accept user_email from URL parameter (for Flutter WebView integration)
// ✅ UPDATED: Accept user_email from URL parameter (for Flutter WebView integration)
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';  // ✅ Removed hardcoded default

$employee_id = '';
$employee_name = '';
$employee_department = 'General';
$employee_position = 'General';

// Admin mapping - REMOVED HARDCODED POSITIONS
// Now fetches actual position from database for all users including admins
$admin_mapping = array(
    'abishek'           => array('email_hint' => 'abishekveeraswamy@fleet.abra-travels.com'),
    'keerthi'           => array('email_hint' => 'hr-admin@fleet.abra-travels.com'),
    'keerti'            => array('email_hint' => 'hr-admin@fleet.abra-travels.com'),
    'admin'             => array('email_hint' => 'admin@abrafleet.com'),
    'admin@abrafleet.com'                            => array('email_hint' => 'admin@abrafleet.com'),
    'hr-admin@fleet.abra-travels.com'                => array('email_hint' => 'hr-admin@fleet.abra-travels.com'),
    'abishekveeraswamy@fleet.abra-travels.com'       => array('email_hint' => 'abishekveeraswamy@fleet.abra-travels.com'),
);

// ✅ PRIORITY 1: Try email from URL parameter (Flutter WebView)
if (!empty($currentUserEmail)) {
    error_log("=== HR-KPI USER LOOKUP ===");
    error_log("Looking up user by email: $currentUserEmail");
    $email_safe = mysqli_real_escape_string($con, $currentUserEmail);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE (email = '$email_safe' OR personal_email = '$email_safe') AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
        // Set session for consistency
        $_SESSION['user_name'] = $employee_name;
        error_log("✅ User found: $employee_name ($employee_id) - $employee_department / $employee_position");
    } else {
        error_log("❌ User NOT found for email: $currentUserEmail");
    }
    error_log("=== END USER LOOKUP ===");
}

// ✅ FALLBACK: Lookup by email from database (admin mapping)
if (empty($employee_id)) {
    $user_key_lower = strtolower($currentUserName);
    if (isset($admin_mapping[$user_key_lower])) {
        $hint_email = mysqli_real_escape_string($con, $admin_mapping[$user_key_lower]['email_hint']);
        $res = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE (email='$hint_email' OR personal_email='$hint_email') AND (status='Active' OR status='active') LIMIT 1");
        if ($res && mysqli_num_rows($res) > 0) {
            $row = mysqli_fetch_assoc($res);
            $employee_id   = $row['employee_id'];
            $employee_name = $row['name'];
            $employee_department = !empty($row['department']) ? $row['department'] : 'General';
            $employee_position   = !empty($row['position'])   ? $row['position']   : 'General';
        }
    }
}

// $user_key = strtolower($currentUserName);
// if (isset($admin_mapping[$user_key])) {
//     $employee_id = $admin_mapping[$user_key]['id'];
//     $employee_name = $admin_mapping[$user_key]['name'];
    
//     // Fetch actual department and position from database
//     $admin_lookup = mysqli_query($con, "SELECT department, position FROM hr_employees WHERE employee_id = '$employee_id' AND (status = 'Active' OR status = 'active') LIMIT 1");
//     if ($admin_lookup && mysqli_num_rows($admin_lookup) > 0) {
//         $admin_data = mysqli_fetch_assoc($admin_lookup);
//         $employee_department = !empty($admin_data['department']) ? $admin_data['department'] : 'General';
//         $employee_position = !empty($admin_data['position']) ? $admin_data['position'] : 'General';
//     } else {
//         // Fallback if not found in database
//         $employee_department = 'General';
//         $employee_position = 'General';
//     }
// }

if (empty($employee_id) && !empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($con, $currentUserName);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    } else {
        // Try partial match if exact match fails
        $res2 = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$name_safe%') AND (status = 'Active' OR status = 'active') LIMIT 1");
        if ($res2 && mysqli_num_rows($res2) > 0) {
            $row = mysqli_fetch_assoc($res2);
            $employee_id = $row['employee_id'];
            $employee_name = $row['name'];
            $employee_department = !empty($row['department']) ? $row['department'] : 'General';
            $employee_position = !empty($row['position']) ? $row['position'] : 'General';
        }
    }
}

if (empty($employee_id)) {
    // Fallback: get first active employee
    $fallback = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE status = 'active' LIMIT 1");
    if ($fallback && mysqli_num_rows($fallback) > 0) {
        $row = mysqli_fetch_assoc($fallback);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    } else {
        die("No active employees found in database.");
    }
}

// --- FETCH CURRENT USER'S FULL EMPLOYEE DATA (including reporting managers) ---
$current_user_data = [];
$user_data_query = mysqli_query($con, "SELECT * FROM hr_employees WHERE employee_id = '$employee_id' LIMIT 1");
if ($user_data_query && mysqli_num_rows($user_data_query) > 0) {
    $current_user_data = mysqli_fetch_assoc($user_data_query);
}

// --- PERMISSIONS LOGIC ---
// Check if user is in admin departments (Management or Human Resources)
$is_management_dept = (stripos($employee_department, 'Management') !== false);

// ✅ IMPROVED: Trim and normalize department for better matching
$dept_normalized = strtolower(trim($employee_department));
$is_hr_dept = (stripos($employee_department, 'Human Resources') !== false || 
               stripos($employee_department, 'Human Resources Department') !== false ||
               $dept_normalized === 'hr' ||  // ✅ Exact match for "HR" (case-insensitive)
               strpos($dept_normalized, 'hr') === 0);  // ✅ Starts with "hr"

// Legacy name-based checks (kept for backward compatibility during transition)
$is_abishek = (stripos($employee_name, 'abishek') !== false);
$is_keerthi = (stripos($employee_name, 'keerti') !== false || stripos($employee_name, 'keerthi') !== false);

// Check if user is Managing Director (can see everyone)
$is_managing_director = (stripos($employee_position, 'managing director') !== false || 
                         stripos($employee_position, 'md') !== false ||
                         stripos($employee_position, 'ceo') !== false);

// ✅ NEW: Check if user is HR Manager (any level)
$pos_normalized = strtolower(trim($employee_position));
$is_hr_manager = (stripos($pos_normalized, 'hr manager') !== false ||
                  stripos($pos_normalized, 'hr-manager') !== false ||
                  stripos($pos_normalized, 'human resources manager') !== false ||
                  strpos($pos_normalized, 'hr manager') === 0);  // ✅ Starts with "hr manager"

// Check if user is a Reporting Manager (can see their team)
// ALWAYS check this, regardless of other roles
$is_reporting_manager = false;
$managed_employees = [];

// Find all employees where current user is reporting_manager_1 or reporting_manager_2
// Handle both formats: just ID (ABRA030) or with name (rajmohan (ABRA030))
$manager_query = mysqli_query($con, "
    SELECT employee_id, name, department, position 
    FROM hr_employees 
    WHERE (
        reporting_manager_1 = '$employee_id' 
        OR reporting_manager_2 = '$employee_id'
        OR reporting_manager_1 LIKE '%($employee_id)%'
        OR reporting_manager_2 LIKE '%($employee_id)%'
    )
    AND (status = 'Active' OR status = 'active')
    ORDER BY name ASC
");

if ($manager_query && mysqli_num_rows($manager_query) > 0) {
    $is_reporting_manager = true;
    while ($emp = mysqli_fetch_assoc($manager_query)) {
        $managed_employees[$emp['employee_id']] = $emp;
    }
}

// Final permission flags
$is_admin = ($is_abishek || $is_keerthi || $is_managing_director || $is_management_dept || $is_hr_dept || $is_hr_manager);
$show_self_review = true; // Everyone can see their own reviews
$can_evaluate_team = ($is_admin || $is_reporting_manager);

// Build WHERE clause for employee visibility
$employee_visibility_where = "";
$employee_visibility_where_team_only = ""; // For Evaluate Team tab (excludes manager)

if ($is_managing_director || $is_abishek || $is_keerthi || $is_management_dept || $is_hr_dept) {
    // Managing Director, Management dept, and HR dept can see everyone
    $employee_visibility_where = "(status = 'Active' OR status = 'active')";
    $employee_visibility_where_team_only = "(status = 'Active' OR status = 'active')";
} elseif ($is_reporting_manager) {
    // Reporting managers can see their team + themselves (for filters)
    $managed_ids = array_keys($managed_employees);
    $managed_ids_with_self = $managed_ids;
    $managed_ids_with_self[] = $employee_id; // Add self
    $ids_list_with_self = "'" . implode("','", $managed_ids_with_self) . "'";
    $employee_visibility_where = "employee_id IN ($ids_list_with_self) AND (status = 'Active' OR status = 'active')";
    
    // For Evaluate Team tab, exclude manager themselves
    if(count($managed_ids) > 0) {
        $ids_list_team_only = "'" . implode("','", $managed_ids) . "'";
        $employee_visibility_where_team_only = "employee_id IN ($ids_list_team_only) AND (status = 'Active' OR status = 'active')";
    } else {
        $employee_visibility_where_team_only = "1=0"; // No team members
    }
} else {
    // Regular employees can only see themselves
    $employee_visibility_where = "employee_id = '$employee_id' AND (status = 'Active' OR status = 'active')";
    $employee_visibility_where_team_only = "employee_id = '$employee_id' AND (status = 'Active' OR status = 'active')";
}

// --- NAVIGATION URL LOGIC ---
$dashboard_url = "https://crm.abra-logistic.com/dashboard/raise-a-ticket.php";
if ($is_abishek) {
    $dashboard_url = "/dashboard/index.php";
}

// Date Utils
$today = date('Y-m-d');
$current_week_start = date('Y-m-d', strtotime('monday this week'));
$current_week_end = date('Y-m-d', strtotime('sunday this week'));
$current_month = date('Y-m');
$current_quarter = 'Q' . ceil(date('n') / 3) . '-' . date('Y');
$current_halfyear = (date('n') <= 6 ? 'H1' : 'H2') . '-' . date('Y');
$current_year = date('Y');

// --- INSPIRATIONAL QUOTES CONFIGURATION ---
$motivational_quotes = [
    "Quality is not an act, it is a habit. – Aristotle",
    "Believe you can and you're halfway there. – Theodore Roosevelt",
    "Success is the sum of small efforts, repeated day in and day out. – Robert Collier",
    "The only way to do great work is to love what you do. – Steve Jobs",
    "Don't watch the clock; do what it does. Keep going. – Sam Levenson",
    "Perfection is not attainable, but if we chase perfection we can catch excellence. – Vince Lombardi",
    "Your attitude, not your aptitude, will determine your altitude. – Zig Ziglar",
    "Action is the foundational key to all success. – Pablo Picasso",
    "What gets measured gets managed. – Peter Drucker",
    "Strive not to be a success, but rather to be of value. – Albert Einstein",
    "The secret of getting ahead is getting started. – Mark Twain",
    "It always seems impossible until it’s done. – Nelson Mandela"
];

// --- HELPER FUNCTIONS ---
function getQuestionsFromDatabase($con, $review_type, $review_by, $department = 'General', $position = 'General') {
    $review_type_safe = mysqli_real_escape_string($con, $review_type);
    $review_by_safe = mysqli_real_escape_string($con, $review_by);
    $department_safe = mysqli_real_escape_string($con, $department);
    $position_safe = mysqli_real_escape_string($con, $position);
    
    $result = null;
    $query_used = '';
    $dept_used = '';
    $pos_used = '';
    
    // Try 1: Exact match (dept + pos)
    $query = "SELECT * FROM performance_questions 
              WHERE department = '$department_safe' 
              AND position = '$position_safe' 
              AND review_type = '$review_type_safe' 
              AND review_by = '$review_by_safe' 
              AND is_active = 1 
              ORDER BY question_number ASC";
    
    $result = mysqli_query($con, $query);
    
    if ($result && mysqli_num_rows($result) > 0) {
        $query_used = "Exact match";
        $dept_used = $department_safe;
        $pos_used = $position_safe;
    } else {
        // Try 2: Fallback to General position (only if no results from Try 1)
        $query = "SELECT * FROM performance_questions 
                  WHERE department = '$department_safe' 
                  AND position = 'General' 
                  AND review_type = '$review_type_safe' 
                  AND review_by = '$review_by_safe' 
                  AND is_active = 1 
                  ORDER BY question_number ASC";
        $result = mysqli_query($con, $query);
        
        if ($result && mysqli_num_rows($result) > 0) {
            $query_used = "Fallback 1 (General position)";
            $dept_used = $department_safe;
            $pos_used = 'General';
        } else {
            // Try 3: Fallback to General/General (only if no results from Try 1 and Try 2)
            $query = "SELECT * FROM performance_questions 
                      WHERE department = 'General' 
                      AND position = 'General' 
                      AND review_type = '$review_type_safe' 
                      AND review_by = '$review_by_safe' 
                      AND is_active = 1 
                      ORDER BY question_number ASC";
            $result = mysqli_query($con, $query);
            
            if ($result && mysqli_num_rows($result) > 0) {
                $query_used = "Fallback 2 (General/General)";
                $dept_used = 'General';
                $pos_used = 'General';
            }
        }
    }
    
    $questions = array();
    
    // CRITICAL FIX: Only process ONE result set - whichever query succeeded first
    // Reset the result pointer to ensure we read from the beginning
    if ($result && mysqli_num_rows($result) > 0) {
        mysqli_data_seek($result, 0); // Reset pointer to start
        
        while ($row = mysqli_fetch_assoc($result)) {
            $q_num = $row['question_number'];
            
            // CRITICAL FIX: Only add each question_number ONCE
            // Skip if this question number already exists (shouldn't happen, but safety check)
            if (isset($questions[$q_num])) {
                error_log("WARNING: Duplicate question_number $q_num found for $dept_used/$pos_used/$review_type_safe/$review_by_safe");
                continue;
            }
            
            // Store question with its number as key
            $questions[$q_num] = array(
                'q' => $row['question_text'], 
                't' => $row['input_type'], 
                'id' => $row['id'],
                'dept' => $row['department'],
                'pos' => $row['position']
            );
            
            if ($row['input_type'] == 'select' && !empty($row['options_json'])) {
                $questions[$q_num]['o'] = json_decode($row['options_json'], true) ?: array();
            }
            if ($row['has_sub_question'] && !empty($row['sub_question_text'])) {
                $questions[$q_num]['sub'] = $row['sub_question_text'];
            }
        }
    }
    
    // Debug logging
    if (isset($_GET['debug'])) {
        error_log("getQuestionsFromDatabase: $query_used ($dept_used / $pos_used) - Returned " . count($questions) . " questions for $review_type_safe/$review_by_safe");
    }
    
    return $questions;
}

function getQuestionsConfig($con, $type, $department = 'General', $position = 'General') {
    $type_mapping = array(
        'daily_self' => array('review_type' => 'daily', 'review_by' => 'self'),
        'weekly_self' => array('review_type' => 'weekly', 'review_by' => 'self'),
        'monthly_self' => array('review_type' => 'monthly', 'review_by' => 'self'),
        'quarterly_self' => array('review_type' => 'quarterly', 'review_by' => 'self'),
        'halfyearly_self' => array('review_type' => 'halfyearly', 'review_by' => 'self'),
        'yearly_self' => array('review_type' => 'yearly', 'review_by' => 'self'),
        'weekly_manager' => array('review_type' => 'weekly', 'review_by' => 'manager'),
        'monthly_manager' => array('review_type' => 'monthly', 'review_by' => 'manager'),
        'quarterly_manager' => array('review_type' => 'quarterly', 'review_by' => 'manager'),
        'halfyearly_manager' => array('review_type' => 'halfyearly', 'review_by' => 'manager'),
        'yearly_manager' => array('review_type' => 'yearly', 'review_by' => 'manager')
    );
    if (!isset($type_mapping[$type])) return array();
    $mapping = $type_mapping[$type];
    return getQuestionsFromDatabase($con, $mapping['review_type'], $mapping['review_by'], $department, $position);
}

// --- UPDATED RATING LOGIC (6-TIER) ---
function getPerfStyle($s) {
    if ($s == -1) return array('r' => '🏖️ On Leave', 'c' => '#64748b', 'bg' => '#f1f5f9', 'icon'=>'🏖️', 'border'=>'#94a3b8');
    
    // Significant (95-100)
    if ($s >= 95) return array('r' => '💎 Significant', 'c' => '#0f766e', 'bg' => '#ccfbf1', 'icon'=>'💎', 'border'=>'#0f766e');
    
    // Outstanding (90-94)
    elseif ($s >= 90) return array('r' => '🏆 Outstanding', 'c' => '#059669', 'bg' => '#ecfdf5', 'icon'=>'🏆', 'border'=>'#059669');
    
    // Excellent (85-89)
    elseif ($s >= 85) return array('r' => '⭐ Excellent', 'c' => '#10b981', 'bg' => '#d1fae5', 'icon'=>'⭐', 'border'=>'#10b981');
    
    // Good (80-84)
    elseif ($s >= 80) return array('r' => '✨ Good', 'c' => '#2563eb', 'bg' => '#eff6ff', 'icon'=>'✨', 'border'=>'#2563eb');
    
    // Average (70-79)
    elseif ($s >= 70) return array('r' => '👍 Average', 'c' => '#d97706', 'bg' => '#fffbeb', 'icon'=>'👍', 'border'=>'#d97706');
    
    // Poor (< 70)
    else return array('r' => '🚫 Poor', 'c' => '#dc2626', 'bg' => '#fef2f2', 'icon'=>'🚫', 'border'=>'#dc2626');
}

function getEmployeeAvgScore($con, $employee_id) {
    $total_score = 0;
    $total_count = 0;
    
    $mgr_tables = [
        'performance_weekly_manager',
        'performance_monthly_manager',
        'performance_quarterly_manager',
        'performance_halfyearly_manager',
        'performance_yearly_manager'
    ];
    
    foreach($mgr_tables as $table) {
        $query = mysqli_query($con, "SELECT SUM(total_score) as sum, COUNT(*) as cnt FROM `$table` WHERE employee_id='$employee_id' AND total_score >= 0");
        if($query) {
            $row = mysqli_fetch_assoc($query);
            if($row['cnt'] > 0) {
                $total_score += $row['sum'];
                $total_count += $row['cnt'];
            }
        }
    }
    return $total_count > 0 ? round($total_score / $total_count, 2) : 0;
}

// --- FORM SUBMISSION ---
if($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['form_type'])) {
    $type = mysqli_real_escape_string($con, $_POST['form_type']);
    
    // CRITICAL FIX 1: For manager reviews, ALWAYS fetch target employee's dept/pos from database
    // Do NOT rely on hidden fields or manager's own department
    $is_manager_review = (strpos($type, 'manager') !== false);
    
    if ($is_manager_review) {
        // Manager review - MUST use target employee's department and position
        if (!isset($_POST['target_id']) || empty($_POST['target_id'])) {
            $_SESSION['error_msg'] = "Error: Target employee information is missing.";
            header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard");
            exit();
        }
        
        $target_id = mysqli_real_escape_string($con, $_POST['target_id']);
        
        // ALWAYS fetch from database - this is the source of truth
        $target_lookup = mysqli_query($con, "SELECT department, position FROM hr_employees WHERE employee_id='$target_id' AND (status='Active' OR status='active') LIMIT 1");
        
        if ($target_lookup && mysqli_num_rows($target_lookup) > 0) {
            $target_data = mysqli_fetch_assoc($target_lookup);
            $department = !empty($target_data['department']) ? $target_data['department'] : 'General';
            $position = !empty($target_data['position']) ? $target_data['position'] : 'General';
        } else {
            $_SESSION['error_msg'] = "Error: Target employee not found in database.";
            header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard");
            exit();
        }
        
        error_log("Manager review submission: target_id=$target_id, dept=$department, pos=$position");
    } else {
        // Self review - use posted values (which should match current user's dept/pos)
        $department = isset($_POST['department']) ? mysqli_real_escape_string($con, $_POST['department']) : $employee_department;
        $position = isset($_POST['position']) ? mysqli_real_escape_string($con, $_POST['position']) : $employee_position;
        
        error_log("Self review submission: employee_id=$employee_id, dept=$department, pos=$position");
    }
    
    // Validation: Ensure department and position are not empty
    if (empty($department)) {
        $_SESSION['error_msg'] = "Error: Department is missing. Please contact HR to update your employee record.";
        header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard");
        exit();
    }
    
    $form_date = isset($_POST['submission_review_date']) ? $_POST['submission_review_date'] : date('Y-m-d');
    $is_leave = isset($_POST['is_leave']); 

    $score = 0;
    $max_possible_score = 0;
    
    // CRITICAL: Fetch questions using the EXACT dept/pos determined above
    $questions = getQuestionsConfig($con, $type, $department, $position);
    $q_count = count($questions);
    
    // Log what questions were loaded
    error_log("Loaded $q_count questions for type=$type, dept=$department, pos=$position");

    $answer_data = array();

    if ($is_leave) {
        $score = -1;
        foreach($questions as $n => $q) {
            $answer_data[$n] = array(
                'text' => 'On Leave / Holiday', 
                'sub' => '', 
                'score' => 0, 
                'q_id' => $q['id'],
                'q_text' => mysqli_real_escape_string($con, $q['q'])  // Store the actual question text
            );
        }
    } else {
        if ($q_count == 0) {
            $_SESSION['error_msg'] = "No questions found for this review type.";
            header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard");
            exit();
        }

        foreach($questions as $n => $q) {
            $val = isset($_POST["q$n"]) ? trim($_POST["q$n"]) : '';
            $sub_val = isset($_POST["q{$n}_sub"]) ? trim($_POST["q{$n}_sub"]) : '';
            $input_type = isset($q['t']) ? $q['t'] : 'text'; 
            
            $pts = 0;
            $cv = strtolower(trim($val));
            
            if ($input_type == 'select' && !empty($cv)) {
                // Check if answer is "Not Applicable" - treat as non-scoring (like text questions)
                if(in_array($cv, array('not applicable', 'n/a', 'na'))) {
                    // Don't add to max score and don't add points - treat as text question
                    $pts = 0;
                }
                else {
                    $max_possible_score += 10;
                    if(in_array($cv, array('yes', 'excellent', 'very well', 'high', 'strong', 'happy', '5', '5 - excellent', '10', 'exceeded', 'fully met'))) { $pts = 10; }
                    elseif(in_array($cv, array('partially', 'partially met', 'average', 'moderate', 'good', 'well', 'satisfactory', 'met', '4', '4 - good', '3', '3 - average', '7', '8', '9', '6'))) { $pts = 5; }
                    elseif(in_array($cv, array('no', 'weak', 'poorly', 'very poorly', 'stressed', 'needs improvement', 'not met', 'bad', 'low', '2', '1', '0', 'below average', 'poor', 'not yet'))) { $pts = 0; }
                }
            } 

            $answer_data[$n] = array(
                'text' => mysqli_real_escape_string($con, $val), 
                'sub' => mysqli_real_escape_string($con, $sub_val), 
                'score' => $pts, 
                'q_id' => $q['id'],
                'q_text' => mysqli_real_escape_string($con, $q['q'])  // CRITICAL FIX 2: Always store question text
            );
            $score += $pts;
        }
        
        // Log the question mapping for debugging
        error_log("Question mapping for review: " . json_encode(array_map(function($d) { 
            return ['q_num' => $d['score'], 'q_id' => $d['q_id'], 'q_preview' => substr($d['q_text'], 0, 50)]; 
        }, $answer_data)));
        
        if($max_possible_score > 0) {
            $score = round(($score / $max_possible_score) * 100, 2);
        } else {
            $score = 0; 
        }
        if($score > 100) $score = 100;
    }

    $is_manager_review = false;
    $sql = "";
    $current_timestamp = date('Y-m-d H:i:s'); // Current submission time
    
    // Period calculations
    $f_week_start = date('Y-m-d', strtotime('monday this week', strtotime($form_date)));
    $f_week_end = date('Y-m-d', strtotime('sunday this week', strtotime($form_date)));
    $f_month = date('Y-m', strtotime($form_date));
    $f_quarter = 'Q' . ceil(date('n', strtotime($form_date)) / 3) . '-' . date('Y', strtotime($form_date));
    $f_halfyear = (date('n', strtotime($form_date)) <= 6 ? 'H1' : 'H2') . '-' . date('Y', strtotime($form_date));
    $f_year = date('Y', strtotime($form_date));

    if($type == 'daily_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_daily_self WHERE employee_id='$employee_id' AND review_date='$form_date'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_daily_self SET total_score='$score', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND review_date='$form_date'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_daily_self (employee_id, employee_name, review_date, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$form_date', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif($type == 'weekly_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_weekly_self WHERE employee_id='$employee_id' AND week_start_date='$f_week_start'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_weekly_self SET total_score='$score', week_end_date='$f_week_end', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND week_start_date='$f_week_start'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_weekly_self (employee_id, employee_name, week_start_date, week_end_date, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$f_week_start', '$f_week_end', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif($type == 'monthly_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_monthly_self WHERE employee_id='$employee_id' AND review_month='$f_month'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_monthly_self SET total_score='$score', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND review_month='$f_month'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_monthly_self (employee_id, employee_name, review_month, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$f_month', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif($type == 'quarterly_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_quarterly_self WHERE employee_id='$employee_id' AND review_quarter='$f_quarter'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_quarterly_self SET total_score='$score', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND review_quarter='$f_quarter'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_quarterly_self (employee_id, employee_name, review_quarter, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$f_quarter', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif($type == 'halfyearly_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_halfyearly_self WHERE employee_id='$employee_id' AND review_halfyear='$f_halfyear'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_halfyearly_self SET total_score='$score', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND review_halfyear='$f_halfyear'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_halfyearly_self (employee_id, employee_name, review_halfyear, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$f_halfyear', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif($type == 'yearly_self') {
        // Check if already exists
        $check = mysqli_query($con, "SELECT id FROM performance_yearly_self WHERE employee_id='$employee_id' AND review_year='$f_year'");
        if(mysqli_num_rows($check) > 0) {
            // Update existing
            $sql = "UPDATE performance_yearly_self SET total_score='$score', submitted_at='$current_timestamp' WHERE employee_id='$employee_id' AND review_year='$f_year'";
        } else {
            // Insert new
            $sql = "INSERT INTO performance_yearly_self (employee_id, employee_name, review_year, total_score, submitted_at, department, position) VALUES ('$employee_id', '$employee_name', '$f_year', '$score', '$current_timestamp', '$department', '$position')";
        }
    } elseif(strpos($type, 'manager') !== false) {
        $is_manager_review = true;
        if(!isset($_POST['target_id'])) die("Error: Employee information missing");
        $target_id = mysqli_real_escape_string($con, $_POST['target_id']);
        $target_name = mysqli_real_escape_string($con, $_POST['target_name']);
        
        // Fetch target employee's department and position
        $target_emp_query = mysqli_query($con, "SELECT department, position FROM hr_employees WHERE employee_id='$target_id' LIMIT 1");
        if($target_emp_query && mysqli_num_rows($target_emp_query) > 0) {
            $target_emp_data = mysqli_fetch_assoc($target_emp_query);
            $target_department = $target_emp_data['department'] ? $target_emp_data['department'] : 'General';
            $target_position = $target_emp_data['position'] ? $target_emp_data['position'] : 'General';
        } else {
            $target_department = 'General';
            $target_position = 'General';
        }
        
        if($type == 'weekly_manager') {
            // Check if already exists
            $check = mysqli_query($con, "SELECT id FROM performance_weekly_manager WHERE employee_id='$target_id' AND week_start_date='$f_week_start'");
            if(mysqli_num_rows($check) > 0) {
                $sql = "UPDATE performance_weekly_manager SET total_score='$score', manager_id='$employee_id', manager_name='$employee_name', week_end_date='$f_week_end', submitted_at='$current_timestamp' WHERE employee_id='$target_id' AND week_start_date='$f_week_start'";
            } else {
                $sql = "INSERT INTO performance_weekly_manager (employee_id, employee_name, manager_id, manager_name, week_start_date, week_end_date, total_score, submitted_at, department, position) VALUES ('$target_id', '$target_name', '$employee_id', '$employee_name', '$f_week_start', '$f_week_end', '$score', '$current_timestamp', '$target_department', '$target_position')";
            }
        } elseif($type == 'monthly_manager') {
            $check = mysqli_query($con, "SELECT id FROM performance_monthly_manager WHERE employee_id='$target_id' AND review_month='$f_month'");
            if(mysqli_num_rows($check) > 0) {
                $sql = "UPDATE performance_monthly_manager SET total_score='$score', manager_id='$employee_id', manager_name='$employee_name', submitted_at='$current_timestamp' WHERE employee_id='$target_id' AND review_month='$f_month'";
            } else {
                $sql = "INSERT INTO performance_monthly_manager (employee_id, employee_name, manager_id, manager_name, review_month, total_score, submitted_at, department, position) VALUES ('$target_id', '$target_name', '$employee_id', '$employee_name', '$f_month', '$score', '$current_timestamp', '$target_department', '$target_position')";
            }
        } elseif($type == 'quarterly_manager') {
            $check = mysqli_query($con, "SELECT id FROM performance_quarterly_manager WHERE employee_id='$target_id' AND review_quarter='$f_quarter'");
            if(mysqli_num_rows($check) > 0) {
                $sql = "UPDATE performance_quarterly_manager SET total_score='$score', manager_id='$employee_id', manager_name='$employee_name', submitted_at='$current_timestamp' WHERE employee_id='$target_id' AND review_quarter='$f_quarter'";
            } else {
                $sql = "INSERT INTO performance_quarterly_manager (employee_id, employee_name, manager_id, manager_name, review_quarter, total_score, submitted_at, department, position) VALUES ('$target_id', '$target_name', '$employee_id', '$employee_name', '$f_quarter', '$score', '$current_timestamp', '$target_department', '$target_position')";
            }
        } elseif($type == 'halfyearly_manager') {
            $check = mysqli_query($con, "SELECT id FROM performance_halfyearly_manager WHERE employee_id='$target_id' AND review_halfyear='$f_halfyear'");
            if(mysqli_num_rows($check) > 0) {
                $sql = "UPDATE performance_halfyearly_manager SET total_score='$score', manager_id='$employee_id', manager_name='$employee_name', submitted_at='$current_timestamp' WHERE employee_id='$target_id' AND review_halfyear='$f_halfyear'";
            } else {
                $sql = "INSERT INTO performance_halfyearly_manager (employee_id, employee_name, manager_id, manager_name, review_halfyear, total_score, submitted_at, department, position) VALUES ('$target_id', '$target_name', '$employee_id', '$employee_name', '$f_halfyear', '$score', '$current_timestamp', '$target_department', '$target_position')";
            }
        } else {
            $check = mysqli_query($con, "SELECT id FROM performance_yearly_manager WHERE employee_id='$target_id' AND review_year='$f_year'");
            if(mysqli_num_rows($check) > 0) {
                $sql = "UPDATE performance_yearly_manager SET total_score='$score', manager_id='$employee_id', manager_name='$employee_name', submitted_at='$current_timestamp' WHERE employee_id='$target_id' AND review_year='$f_year'";
            } else {
                $sql = "INSERT INTO performance_yearly_manager (employee_id, employee_name, manager_id, manager_name, review_year, total_score, submitted_at, department, position) VALUES ('$target_id', '$target_name', '$employee_id', '$employee_name', '$f_year', '$score', '$current_timestamp', '$target_department', '$target_position')";
            }
        }
    }

    if(mysqli_query($con, $sql)) {
        // Get review_id (either from insert or from existing record)
        if(strpos($sql, 'UPDATE') !== false) {
            // For updates, get the existing review_id
            if($type == 'daily_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_daily_self WHERE employee_id='$employee_id' AND review_date='$form_date'");
            } elseif($type == 'weekly_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_weekly_self WHERE employee_id='$employee_id' AND week_start_date='$f_week_start'");
            } elseif($type == 'monthly_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_monthly_self WHERE employee_id='$employee_id' AND review_month='$f_month'");
            } elseif($type == 'quarterly_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_quarterly_self WHERE employee_id='$employee_id' AND review_quarter='$f_quarter'");
            } elseif($type == 'halfyearly_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_halfyearly_self WHERE employee_id='$employee_id' AND review_halfyear='$f_halfyear'");
            } elseif($type == 'yearly_self') {
                $result = mysqli_query($con, "SELECT id FROM performance_yearly_self WHERE employee_id='$employee_id' AND review_year='$f_year'");
            } elseif($type == 'weekly_manager') {
                $result = mysqli_query($con, "SELECT id FROM performance_weekly_manager WHERE employee_id='$target_id' AND week_start_date='$f_week_start'");
            } elseif($type == 'monthly_manager') {
                $result = mysqli_query($con, "SELECT id FROM performance_monthly_manager WHERE employee_id='$target_id' AND review_month='$f_month'");
            } elseif($type == 'quarterly_manager') {
                $result = mysqli_query($con, "SELECT id FROM performance_quarterly_manager WHERE employee_id='$target_id' AND review_quarter='$f_quarter'");
            } elseif($type == 'halfyearly_manager') {
                $result = mysqli_query($con, "SELECT id FROM performance_halfyearly_manager WHERE employee_id='$target_id' AND review_halfyear='$f_halfyear'");
            } elseif($type == 'yearly_manager') {
                $result = mysqli_query($con, "SELECT id FROM performance_yearly_manager WHERE employee_id='$target_id' AND review_year='$f_year'");
            }
            $row = mysqli_fetch_assoc($result);
            $review_id = $row['id'];
            
            // CRITICAL FIX: Delete ALL old answers for this review_id and review_type combination
            // This ensures no orphaned or duplicate answers remain
            $answers_table = $is_manager_review ? 'performance_answers_manager' : 'performance_answers_self';
            $delete_result = mysqli_query($con, "DELETE FROM `$answers_table` WHERE review_id=$review_id AND review_type='$type'");
            
            // Log deletion for debugging
            if ($delete_result) {
                $deleted_count = mysqli_affected_rows($con);
                error_log("Deleted $deleted_count old answers for review_id=$review_id, review_type=$type");
            }
        } else {
            $review_id = mysqli_insert_id($con);
            
            // SAFETY CHECK: Delete any orphaned answers for this new review_id and review_type
            // This shouldn't happen, but protects against data corruption
            $answers_table = $is_manager_review ? 'performance_answers_manager' : 'performance_answers_self';
            $delete_result = mysqli_query($con, "DELETE FROM `$answers_table` WHERE review_id=$review_id AND review_type='$type'");
            
            if ($delete_result && mysqli_affected_rows($con) > 0) {
                error_log("WARNING: Found and deleted orphaned answers for new review_id=$review_id, review_type=$type");
            }
        }
        
        // Insert new answers with complete information
        $answers_table = $is_manager_review ? 'performance_answers_manager' : 'performance_answers_self';
        $insert_count = 0;
        $insert_errors = [];
        
        foreach($answer_data as $num => $data) {
            $sub_part = !empty($data['sub']) ? "'{$data['sub']}'" : "NULL";
            
            // PERMANENT FIX: Ensure question_text is NEVER NULL or empty
            // If somehow q_text is missing, use a fallback
            $q_text_safe = (!empty($data['q_text'])) ? "'{$data['q_text']}'" : "'Question #$num'";
            
            // CRITICAL: Ensure we're inserting with the correct review_type
            $insert_sql = "INSERT INTO `$answers_table` (review_id, review_type, question_id, question_number, question_text, answer_text, answer_score, sub_answer_text) 
                          VALUES ($review_id, '$type', {$data['q_id']}, $num, $q_text_safe, '{$data['text']}', {$data['score']}, $sub_part)";
            
            if(mysqli_query($con, $insert_sql)) {
                $insert_count++;
            } else {
                $insert_errors[] = "Q$num: " . mysqli_error($con);
                error_log("Failed to insert answer Q$num: " . mysqli_error($con));
            }
        }
        
        // Log insertion results
        error_log("Inserted $insert_count answers for review_id=$review_id, review_type=$type, department=$department, position=$position");
        if (!empty($insert_errors)) {
            error_log("Answer insertion errors: " . implode("; ", $insert_errors));
        }
        
        $msg_text = $is_leave ? "Leave status recorded successfully!" : "Review submitted successfully!";
        $_SESSION['success_msg'] = "✓ " . $msg_text;
        header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard&msg=success");
        exit();
    } else {
        $_SESSION['error_msg'] = "Database Error: " . mysqli_error($con);
        header("Location: " . $_SERVER['PHP_SELF'] . "?view=dashboard");
        exit();
    }
}

$view = isset($_GET['view']) ? $_GET['view'] : 'dashboard';
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Performance Pro | <?php echo htmlspecialchars($employee_name); ?></title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/dataTables.bootstrap4.min.css">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&family=Dancing+Script:wght@700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<!-- HTML2CANVAS LIBRARY FOR FULL SCREENSHOT EXPORT -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>

<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { 
    font-family: 'Poppins', sans-serif; 
    background: #f0f4f8; 
    min-height: 100vh; 
    padding: 30px 0; 
    color: #334155; 
}
.main-wrapper { max-width: 1400px; margin: 0 auto; padding: 0 20px; }

.header-card { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    border-radius: 12px; 
    padding: 25px 35px; 
    margin-bottom: 30px; 
    box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
    border: 3px solid #1e40af;
    color: white;
}
.header-content { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 20px; }
.header-title h1 { font-size: 28px; font-weight: 700; margin-bottom: 5px; color: white; letter-spacing: -0.5px; }
.header-title p { color: rgba(255,255,255,0.9); font-size: 14px; margin: 0; font-weight: 400; }
.header-user { 
    background: rgba(255,255,255,0.15); 
    color: white; 
    padding: 10px 25px; 
    border-radius: 50px; 
    font-weight: 600; 
    border: 1px solid rgba(255,255,255,0.3);
    text-align: right;
    min-width: 250px;
}

.nav-bar { display: flex; gap: 12px; margin-bottom: 30px; flex-wrap: wrap; }
.nav-link { 
    text-decoration: none; 
    padding: 12px 24px; 
    border-radius: 10px; 
    background: #fff; 
    color: #64748b; 
    font-weight: 600; 
    border: 2px solid #e2e8f0;
    transition: all .3s; 
    font-size: 14px;
    box-shadow: 0 2px 5px rgba(0,0,0,.05);
}
.nav-link:hover { background: #f8fafc; text-decoration: none; color: #1e3a8a; transform: translateY(-2px); border-color: #cbd5e1; }
.nav-link.active { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    color: #fff; 
    border-color: #1e3a8a; 
    box-shadow: 0 4px 12px rgba(30,64,175,.3);
}

.card { 
    background: white; 
    border-radius: 12px; 
    padding: 30px; 
    box-shadow: 0 2px 10px rgba(0,0,0,0.08); 
    margin-bottom: 25px; 
    border: 2px solid #e2e8f0; 
    position: relative;
    overflow: hidden;
}
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }

.btn { padding: 10px 18px; border-radius: 10px; font-weight: 600; cursor: pointer; border: none; display: inline-flex; align-items: center; gap: 8px; transition: all .3s; text-decoration: none; font-size: 13px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }

.btn-primary { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    color: #fff; 
    box-shadow: 0 4px 15px rgba(30,58,138,0.3);
}
.btn-primary:hover { background: linear-gradient(135deg, #1e40af 0%, #2563eb 100%); transform: translateY(-2px); color: white; box-shadow: 0 6px 20px rgba(30,58,138,0.4); text-decoration: none; }

.btn-success {
    background: linear-gradient(135deg, #10b981 0%, #059669 100%);
    color: white;
    box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
}
.btn-success:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(16, 185, 129, 0.4); text-decoration: none; }

.btn-warning {
    background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
    color: white;
    box-shadow: 0 4px 12px rgba(245, 158, 11, 0.3);
}
.btn-warning:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(245, 158, 11, 0.4); text-decoration: none; }

.btn-gray { background: linear-gradient(135deg, #64748b 0%, #475569 100%); color: white; box-shadow: 0 4px 12px rgba(100, 116, 139, 0.3); border:none; }
.btn-gray:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(100, 116, 139, 0.4); }

.btn-info { background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); color: white; box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3); border:none; }
.btn-info:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(59, 130, 246, 0.4); }

.btn-teal { background: linear-gradient(135deg, #14b8a6 0%, #0d9488 100%); color: white; box-shadow: 0 4px 12px rgba(20, 184, 166, 0.3); border:none; }
.btn-teal:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(20, 184, 166, 0.4); }

.btn-purple { background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); color: white; box-shadow: 0 4px 12px rgba(139, 92, 246, 0.3); border:none; }
.btn-purple:hover { transform: translateY(-2px); color:white; box-shadow: 0 6px 18px rgba(139, 92, 246, 0.4); }

.btn-outline { background: #fff; border: 2px solid #e2e8f0; color: #64748b; }
.btn-outline:hover { background: #f8fafc; border-color: #1e3a8a; color: #1e3a8a; transform: translateY(-2px); text-decoration: none; }

.form-group { margin-bottom: 25px; padding: 20px; background: #f8fafc; border-radius: 10px; border: 2px solid #e2e8f0; }
.form-label { font-weight: 600; display: block; margin-bottom: 10px; font-size: 14px; color: #1e3a8a; text-transform: uppercase; letter-spacing: 0.5px; }
.form-control { 
    width: 100%; padding: 13px 16px; border: 2px solid #e2e8f0; border-radius: 10px; 
    font-size: 15px; background: #fff; transition: all 0.3s ease; color: #1e293b; font-weight: 500;
}

select.form-control {
    height: 50px !important;
    padding: 10px 16px !important;
    line-height: 1.5;
    background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
    background-repeat: no-repeat;
    background-position: right 1rem center;
    background-size: 1em;
    -webkit-appearance: none;
    -moz-appearance: none;
    appearance: none;
}

.form-control:focus { border-color: #1e40af; outline: none; box-shadow: 0 0 0 4px rgba(30, 64, 175, 0.1); }
textarea.form-control { min-height: 150px; }
.sub-question { margin-top: 15px; padding: 15px; background: #fff; border-radius: 8px; border: 2px dashed #cbd5e1; }

.filter-panel { 
    background: white; 
    padding: 25px; 
    border-radius: 12px; 
    margin-bottom: 25px; 
    border: 2px solid #e2e8f0; 
    box-shadow: 0 2px 10px rgba(0,0,0,0.08);
}
.filter-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid #f1f5f9; padding-bottom: 12px; }
.filter-header h4 { margin: 0; font-weight: 700; font-size: 18px; color: #1e3a8a; }
.filter-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; }
.filter-group label { font-size: 13px; color: #64748b; margin-bottom: 8px; display: block; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }

.select2-container { width: 100% !important; }
.select2-container .select2-selection--single { height: 50px !important; border: 2px solid #e2e8f0 !important; border-radius: 10px !important; background-color: #fff !important; }
.select2-container--default .select2-selection--single .select2-selection__rendered { line-height: 46px !important; color: #1e293b !important; padding-left: 16px !important; font-size: 15px !important; font-weight: 500 !important; }
.select2-container--default .select2-selection--single .select2-selection__arrow { height: 46px !important; right: 10px !important; }
.select2-dropdown { border: 2px solid #e2e8f0 !important; border-radius: 10px !important; box-shadow: 0 10px 20px rgba(0,0,0,0.1) !important; padding: 5px !important; }
.select2-results__option { padding: 10px 16px !important; font-size: 14px !important; border-radius: 6px !important; margin-bottom: 2px !important; }
.select2-results__option--highlighted[aria-selected] { background-color: #1e3a8a !important; color: white !important; }

.alert { padding: 16px 22px; border-radius: 10px; border: none; margin-bottom: 25px; font-weight: 500; font-size: 14px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
.alert-success { background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; }
.alert-danger { background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; }

.table-responsive { border-radius: 12px; border: 2px solid #e2e8f0; overflow: hidden; }
.table { margin-bottom: 0; width: 100%; border-collapse: collapse; }
.table thead th { 
    background: #1e3a8a; 
    color: white; 
    border: none; 
    padding: 15px; 
    font-weight: 600; 
    font-size: 13px; 
    text-transform: uppercase; 
    letter-spacing: 0.5px; 
}
.table td { 
    vertical-align: middle; 
    padding: 15px; 
    border-bottom: 1px solid #cbd5e1; 
    color: #334155; 
    font-size: 14px;
    background: white;
}
.table tr:last-child td { border-bottom: none; }
.table tr:hover td { background-color: #f8fafc; }
.table-bordered th, .table-bordered td { border: 1px solid #cbd5e1; }

.perf-progress { height: 8px; border-radius: 4px; background: #e2e8f0; overflow: hidden; margin-top: 6px; }
.perf-progress-bar { height: 100%; border-radius: 4px; }
.badge-dept { background: #f1f5f9; color: #64748b; padding: 4px 10px; border-radius: 6px; font-size: 11px; font-weight: 600; border: 1px solid #cbd5e1; }
.badge-pos { background: #fff; color: #1e3a8a; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700; border: 1px solid #cbd5e1; }
.badge-type { background: #e0e7ff; color: #1e3a8a; padding: 5px 12px; border-radius: 20px; font-weight: 600; font-size: 12px; border: 1px solid #c7d2fe; text-transform: capitalize; }

/* Status Badges */
.status-badge { position: absolute; top: 20px; right: 20px; padding: 5px 12px; border-radius: 20px; font-size: 11px; font-weight: 700; text-transform: uppercase; }
.status-done { background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; }
.status-pending { background: #fff1f2; color: #be123c; border: 1px solid #fda4af; }

/* PRINT STYLES - FIXED FOR EMPTY PAGE ISSUE */
@media print { 
    body * { visibility: hidden; }
    #certificate-view, #certificate-view * { visibility: visible; }
    #certificate-view {
        position: absolute;
        left: 0;
        top: 0;
        width: 100%;
        margin: 0;
        padding: 0;
        background: white !important;
        z-index: 99999;
    }
    .cert-page {
        box-shadow: none !important;
        border: none !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
    }
    .no-print { display: none !important; }
}
</style>
</head>
<body>

<?php
// DEBUG: Show permission info (remove after testing)
if (isset($_GET['debug_permissions'])) {
    echo "<div style='background:#fff3cd; padding:20px; margin:20px; border:2px solid #ffc107; border-radius:8px; position:relative; z-index:9999;'>";
    echo "<h3>🔍 Permission Debug Info</h3>";
    echo "<p><strong>Session User Name:</strong> " . htmlspecialchars($currentUserName) . "</p>";
    echo "<p><strong>Current User:</strong> $employee_name ($employee_id)</p>";
    echo "<p><strong>Position:</strong> $employee_position</p>";
    echo "<p><strong>Department:</strong> $employee_department</p>";
    echo "<p><strong>Is Managing Director:</strong> " . ($is_managing_director ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is Management Department:</strong> " . ($is_management_dept ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is HR Department:</strong> " . ($is_hr_dept ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is Abishek (legacy):</strong> " . ($is_abishek ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is Keerthi (legacy):</strong> " . ($is_keerthi ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is Admin:</strong> " . ($is_admin ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Is Reporting Manager:</strong> " . ($is_reporting_manager ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Can Evaluate Team:</strong> " . ($can_evaluate_team ? 'YES' : 'NO') . "</p>";
    echo "<p><strong>Managed Employees Count:</strong> " . count($managed_employees) . "</p>";
    if (!empty($managed_employees)) {
        echo "<p><strong>Managed Employees:</strong></p><ul>";
        foreach ($managed_employees as $emp_id => $emp_data) {
            echo "<li>$emp_id - {$emp_data['name']} ({$emp_data['position']})</li>";
        }
        echo "</ul>";
    }
    echo "<p><strong>Visibility WHERE:</strong> <code>" . htmlspecialchars($employee_visibility_where) . "</code></p>";
    
    // Show the actual query used to find managed employees
    echo "<hr><h4>Manager Query Used:</h4>";
    $debug_sql = "SELECT employee_id, name FROM hr_employees WHERE (reporting_manager_1 = '$employee_id' OR reporting_manager_2 = '$employee_id' OR reporting_manager_1 LIKE '%($employee_id)%' OR reporting_manager_2 LIKE '%($employee_id)%') AND status='Active'";
    echo "<pre style='background:#f8f9fa; padding:10px; border:1px solid #dee2e6; overflow:auto; font-size:11px;'>" . htmlspecialchars($debug_sql) . "</pre>";
    
    // Show actual database values
    echo "<hr><h4>Database Check - Employees with Reporting Managers:</h4>";
    $debug_query = mysqli_query($con, "SELECT employee_id, name, reporting_manager_1, reporting_manager_2 FROM hr_employees WHERE status='Active' AND (reporting_manager_1 IS NOT NULL OR reporting_manager_2 IS NOT NULL) AND (reporting_manager_1 != '' OR reporting_manager_2 != '') ORDER BY name");
    if ($debug_query && mysqli_num_rows($debug_query) > 0) {
        echo "<table border='1' cellpadding='5' style='border-collapse:collapse; font-size:12px;'>";
        echo "<tr style='background:#e9ecef;'><th>Employee ID</th><th>Name</th><th>Manager 1</th><th>Manager 2</th></tr>";
        while ($debug_row = mysqli_fetch_assoc($debug_query)) {
            $highlight = '';
            if ($debug_row['reporting_manager_1'] == $employee_id || $debug_row['reporting_manager_2'] == $employee_id) {
                $highlight = 'background:#d4edda; font-weight:bold;';
            }
            echo "<tr style='$highlight'>";
            echo "<td>{$debug_row['employee_id']}</td>";
            echo "<td>{$debug_row['name']}</td>";
            echo "<td>" . ($debug_row['reporting_manager_1'] ?: '-') . "</td>";
            echo "<td>" . ($debug_row['reporting_manager_2'] ?: '-') . "</td>";
            echo "</tr>";
        }
        echo "</table>";
        echo "<p><small><strong>Green rows</strong> = employees you manage</small></p>";
    } else {
        echo "<p style='color:red;'><strong>⚠️ NO employees found with reporting managers!</strong></p>";
    }
    echo "</div>";
}
?>

<div class="main-wrapper no-print">
<div class="header-card">
<div class="header-content">
<div class="header-title">
<h1><i class="fas fa-chart-line"></i> Performance Pro</h1>
<p>ABRA Travels - Fleet Management</p>
</div>
<div class="header-user">
<div style="font-size:16px; font-weight:700;"><i class="fas fa-user-circle"></i> <?php echo htmlspecialchars($employee_name); ?></div>
<div style="font-size:12px; margin-top:4px; opacity:0.9;">
    <span style="background:rgba(255,255,255,0.2); padding:2px 8px; border-radius:4px;"><?php echo htmlspecialchars($employee_position); ?></span>
    <?php if($is_admin): ?>
    <span style="background:#f59e0b; color:#fff; padding:2px 8px; border-radius:4px; margin-left:5px; font-weight:bold;">MANAGER MODE</span>
    <?php endif; ?>
</div>
</div>
</div>
</div>

<div class="nav-bar">
<!-- <a href="<?php echo $dashboard_url; ?>" class="nav-link"><i class="fas fa-arrow-left"></i> Back to Dashboard</a> -->
<a href="?view=dashboard" class="nav-link <?php echo $view=='dashboard'?'active':''; ?>"><i class="fas fa-th-large"></i> Overview</a>

<?php if($can_evaluate_team): ?>
<a href="?view=admin_eval" class="nav-link <?php echo $view=='admin_eval'?'active':''; ?>"><i class="fas fa-users-cog"></i> Evaluate Team</a>
<a href="?view=history_self" class="nav-link <?php echo $view=='history_self'?'active':''; ?>"><i class="fas fa-user-check"></i> My Self Logs</a>
<a href="?view=history_admin_self" class="nav-link <?php echo $view=='history_admin_self'?'active':''; ?>"><i class="fas fa-history"></i> Employee Self Reviews</a>
<a href="?view=history_admin_mgr" class="nav-link <?php echo $view=='history_admin_mgr'?'active':''; ?>"><i class="fas fa-clipboard-check"></i> Manager Reviews</a>
<a href="?view=history_mgr_feedback" class="nav-link <?php echo $view=='history_mgr_feedback'?'active':''; ?>"><i class="fas fa-comment-dots"></i> Manager Feedback</a>
<?php else: ?>
<a href="?view=history_self" class="nav-link <?php echo $view=='history_self'?'active':''; ?>"><i class="fas fa-file-alt"></i> My History</a>
<a href="?view=history_mgr" class="nav-link <?php echo $view=='history_mgr'?'active':''; ?>"><i class="fas fa-comment-dots"></i> Manager Feedback</a>
<?php endif; ?></div>

<?php if(isset($_GET['msg']) && $_GET['msg'] == 'success'): ?>
<div class="alert alert-success"><i class="fas fa-check-circle"></i> Review submitted successfully!</div>
<?php endif; ?>

<?php if(isset($_SESSION['error_msg'])): ?>
<div class="alert alert-danger"><i class="fas fa-exclamation-circle"></i> <?php echo $_SESSION['error_msg']; unset($_SESSION['error_msg']); ?></div>
<?php endif; ?>

<?php if(isset($_SESSION['success_msg'])): ?>
<div class="alert alert-success"><i class="fas fa-check-circle"></i> <?php echo $_SESSION['success_msg']; unset($_SESSION['success_msg']); ?></div>
<?php endif; ?>

<?php if($view == 'dashboard'): ?>

<?php
// --- SIMPLIFIED REVIEW SYSTEM ---
// Check current period submissions
$today_submitted = false;
$today_score = 0;
$q_today = mysqli_query($con, "SELECT total_score FROM performance_daily_self WHERE employee_id='$employee_id' AND review_date='$today' LIMIT 1");
if($q_today && mysqli_num_rows($q_today) > 0) {
    $row_today = mysqli_fetch_assoc($q_today);
    $today_submitted = true;
    $today_score = $row_today['total_score'];
}

$current_week_submitted = false;
$current_week_score = 0;
$q_week = mysqli_query($con, "SELECT total_score FROM performance_weekly_self WHERE employee_id='$employee_id' AND week_start_date='$current_week_start' LIMIT 1");
if($q_week && mysqli_num_rows($q_week) > 0) {
    $row_week = mysqli_fetch_assoc($q_week);
    $current_week_submitted = true;
    $current_week_score = $row_week['total_score'];
}

$current_month_submitted = false;
$current_month_score = 0;
$q_month = mysqli_query($con, "SELECT total_score FROM performance_monthly_self WHERE employee_id='$employee_id' AND review_month='$current_month' LIMIT 1");
if($q_month && mysqli_num_rows($q_month) > 0) {
    $row_month = mysqli_fetch_assoc($q_month);
    $current_month_submitted = true;
    $current_month_score = $row_month['total_score'];
}

// Simplified pending count - just count missing reviews in last 30 days
$pending_daily = [];
$pending_weekly = [];
$pending_monthly = [];
$total_pending = 0;

// Check quarterly, half-yearly, yearly
$curr_q = ceil(date('n') / 3);
$curr_y = date('Y');
$quarterly_target = 'Q' . $curr_q . '-' . $curr_y;
$quarterly_submitted = false;
$q_qt = mysqli_query($con, "SELECT id FROM performance_quarterly_self WHERE employee_id='$employee_id' AND review_quarter='$quarterly_target' LIMIT 1");
if($q_qt && mysqli_num_rows($q_qt) > 0) $quarterly_submitted = true;

$curr_h = (date('n') <= 6 ? 'H1' : 'H2');
$halfyearly_target = $curr_h . '-' . $curr_y;
$halfyearly_submitted = false;
$q_hy = mysqli_query($con, "SELECT id FROM performance_halfyearly_self WHERE employee_id='$employee_id' AND review_halfyear='$halfyearly_target' LIMIT 1");
if($q_hy && mysqli_num_rows($q_hy) > 0) $halfyearly_submitted = true;

$yearly_target = date('Y');
$yearly_submitted = false;
$q_yr = mysqli_query($con, "SELECT id FROM performance_yearly_self WHERE employee_id='$employee_id' AND review_year='$yearly_target' LIMIT 1");
if($q_yr && mysqli_num_rows($q_yr) > 0) $yearly_submitted = true;
?>

<!-- CHECKPOINT 1: Variables initialized -->

<div class="row" style="margin-bottom: 25px;">
    <?php
    $total_self_reviews = 0; $avg_self_score = 0; $total_mgr_reviews = 0; $avg_mgr_score = 0;
    
    // FIX: Ensure WHERE clause is valid for admins (was returning empty string which breaks SQL)
    $where_clause = $is_admin ? "WHERE 1=1" : "WHERE employee_id='$employee_id'";
    
    // EXCLUDE LEAVES (-1) FROM AVERAGE CALCULATION
    $daily_count = mysqli_query($con, "SELECT COUNT(*) as cnt, COALESCE(AVG(total_score), 0) as avg FROM performance_daily_self $where_clause AND total_score >= 0");
    $weekly_count = mysqli_query($con, "SELECT COUNT(*) as cnt, COALESCE(AVG(total_score), 0) as avg FROM performance_weekly_self $where_clause AND total_score >= 0");
    $monthly_count = mysqli_query($con, "SELECT COUNT(*) as cnt, COALESCE(AVG(total_score), 0) as avg FROM performance_monthly_self $where_clause AND total_score >= 0");
    
    if($daily_count) { 
        $d = mysqli_fetch_assoc($daily_count); 
        $total_self_reviews += intval($d['cnt']); 
        $avg_self_score += floatval($d['avg']) * intval($d['cnt']); 
    }
    if($weekly_count) { 
        $w = mysqli_fetch_assoc($weekly_count); 
        $total_self_reviews += intval($w['cnt']); 
        $avg_self_score += floatval($w['avg']) * intval($w['cnt']); 
    }
    if($monthly_count) { 
        $m = mysqli_fetch_assoc($monthly_count); 
        $total_self_reviews += intval($m['cnt']); 
        $avg_self_score += floatval($m['avg']) * intval($m['cnt']); 
    }
    
    if($total_self_reviews > 0) $avg_self_score = round($avg_self_score / $total_self_reviews, 1);
    // if($total_self_reviews == 0) $avg_self_score = -1; // Show On Leave
    
    $mgr_weekly = mysqli_query($con, "SELECT COUNT(*) as cnt, COALESCE(AVG(total_score), 0) as avg FROM performance_weekly_manager $where_clause AND total_score >= 0");
    $mgr_monthly = mysqli_query($con, "SELECT COUNT(*) as cnt, COALESCE(AVG(total_score), 0) as avg FROM performance_monthly_manager $where_clause AND total_score >= 0");
    
    if($mgr_weekly) { 
        $mw = mysqli_fetch_assoc($mgr_weekly); 
        $total_mgr_reviews += intval($mw['cnt']); 
        $avg_mgr_score += floatval($mw['avg']) * intval($mw['cnt']); 
    }
    if($mgr_monthly) { 
        $mm = mysqli_fetch_assoc($mgr_monthly); 
        $total_mgr_reviews += intval($mm['cnt']); 
        $avg_mgr_score += floatval($mm['avg']) * intval($mm['cnt']); 
    }
    
    if($total_mgr_reviews > 0) $avg_mgr_score = round($avg_mgr_score / $total_mgr_reviews, 1);
    
    $self_style = getPerfStyle($avg_self_score);
    $mgr_style = getPerfStyle($avg_mgr_score);
    ?>
    
    <!-- DEBUG: Statistics calculated successfully -->
    
    <div class="col-md-3 mb-3">
        <div class="card" style="border-left: 5px solid #1e3a8a; margin-bottom: 0;">
            <div style="display: flex; align-items: center; gap: 15px;">
                <div style="width: 50px; height: 50px; background: #f8fafc; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 24px;">📝</div>
                <div>
                    <div style="font-size: 13px; color: #64748b; font-weight: 600; text-transform: uppercase;">Total Self Reviews</div>
                    <div style="font-size: 26px; font-weight: 700; color: #1e293b;"><?php echo number_format($total_self_reviews); ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3 mb-3">
        <div class="card" style="border-left: 5px solid <?php echo $self_style['c']; ?>; margin-bottom: 0;">
            <div style="display: flex; align-items: center; gap: 15px;">
                <div style="width: 50px; height: 50px; background: <?php echo $self_style['bg']; ?>; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 24px;"><?php echo $self_style['icon']; ?></div>
                <div>
                    <div style="font-size: 13px; color: #64748b; font-weight: 600; text-transform: uppercase;">Avg Self Score</div>
                    <div style="font-size: 26px; font-weight: 700; color: <?php echo $self_style['c']; ?>;"><?php echo $avg_self_score; ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3 mb-3">
        <div class="card" style="border-left: 5px solid #1e3a8a; margin-bottom: 0;">
            <div style="display: flex; align-items: center; gap: 15px;">
                <div style="width: 50px; height: 50px; background: #f8fafc; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 24px;">👔</div>
                <div>
                    <div style="font-size: 13px; color: #64748b; font-weight: 600; text-transform: uppercase;">Manager Reviews</div>
                    <div style="font-size: 26px; font-weight: 700; color: #1e3a8a;"><?php echo number_format($total_mgr_reviews); ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-3 mb-3">
        <div class="card" style="border-left: 5px solid <?php echo $mgr_style['c']; ?>; margin-bottom: 0;">
            <div style="display: flex; align-items: center; gap: 15px;">
                <div style="width: 50px; height: 50px; background: <?php echo $mgr_style['bg']; ?>; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 24px;"><?php echo $mgr_style['icon']; ?></div>
                <div>
                    <div style="font-size: 13px; color: #64748b; font-weight: 600; text-transform: uppercase;">Avg Manager Score</div>
                    <div style="font-size: 26px; font-weight: 700; color: <?php echo $mgr_style['c']; ?>;"><?php echo $avg_mgr_score; ?></div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php if($show_self_review): ?>
<h2 style="margin-bottom:15px; font-size:16px; color:#475569; font-weight:700; text-transform:uppercase;">Current Period Reviews</h2>

<div class="grid" style="margin-bottom:20px">
    
    <!-- TODAY'S REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($today_submitted): ?>
            <?php if($today_score == -1): ?>
                <div class="status-badge" style="background:#f1f5f9; color:#64748b; border:1px solid #94a3b8;"><i class="fas fa-umbrella-beach"></i> On Leave</div>
            <?php else: ?>
                <div class="status-badge status-done"><i class="fas fa-check"></i> Done: <?php echo $today_score; ?>%</div>
            <?php endif; ?>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Today's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('d M Y', strtotime($today)); ?></p>
            
            <?php if(strtotime($today) < strtotime('-7 days')): ?>
                <button class="btn btn-outline" disabled style="width:100%;justify-content:center; color:#b91c1c; border-color:#b91c1c; background:#fef2f2; opacity:0.7;"><i class="fas fa-lock"></i> Review Locked</button>
            <?php else: ?>
                <a href="?view=form&type=daily&review_date=<?php echo $today; ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:8px;">Edit Submission</a>
            <?php endif; ?>
        <?php else: ?>
            <?php 
            // Check if today's review is overdue (it's past today)
            $is_overdue = (date('Y-m-d') > $today);
            ?>
            <?php if($is_overdue): ?>
                <div class="status-badge" style="background:#fef2f2; color:#b91c1c; border:1px solid #ef4444;"><i class="fas fa-exclamation-triangle"></i> Overdue</div>
            <?php else: ?>
                <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <?php endif; ?>
            <h3 style="font-size:18px; font-weight:700; color:<?php echo $is_overdue ? '#b91c1c' : '#1e3a8a'; ?>">Today's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('d M Y', strtotime($today)); ?></p>
            <a href="?view=form&type=daily&review_date=<?php echo $today; ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:8px; <?php echo $is_overdue ? 'background:#b91c1c; border-color:#b91c1c;' : ''; ?>">
                <?php echo $is_overdue ? 'Submit Overdue Review' : 'Submit Today\'s Review'; ?>
            </a>
        <?php endif; ?>
        <button class="btn btn-outline open-date-picker" data-type="daily" style="width:100%;justify-content:center; font-size:13px;">
            <i class="fas fa-calendar-alt"></i> Submit for Different Date
        </button>
    </div>

    <!-- THIS WEEK'S REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($current_week_submitted): ?>
            <div class="status-badge status-done"><i class="fas fa-check"></i> Done: <?php echo $current_week_score; ?>%</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">This Week's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('d M', strtotime($current_week_start)) . ' - ' . date('d M', strtotime($current_week_start . ' +6 days')); ?></p>
            
            <?php if(strtotime($current_week_start) < strtotime('-7 days')): ?>
                <button class="btn btn-outline" disabled style="width:100%;justify-content:center; color:#b91c1c; border-color:#b91c1c; background:#fef2f2; opacity:0.7;"><i class="fas fa-lock"></i> Review Locked</button>
            <?php else: ?>
                <a href="?view=form&type=weekly&review_date=<?php echo $current_week_start; ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:8px;">Edit Submission</a>
            <?php endif; ?>
        <?php else: ?>
            <?php 
            // Check if week review is overdue (it's past Sunday of this week)
            $week_end = date('Y-m-d', strtotime($current_week_start . ' +6 days'));
            $is_overdue = (date('Y-m-d') > $week_end);
            ?>
            <?php if($is_overdue): ?>
                <div class="status-badge" style="background:#fef2f2; color:#b91c1c; border:1px solid #ef4444;"><i class="fas fa-exclamation-triangle"></i> Overdue</div>
            <?php else: ?>
                <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <?php endif; ?>
            <h3 style="font-size:18px; font-weight:700; color:<?php echo $is_overdue ? '#b91c1c' : '#1e3a8a'; ?>">This Week's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('d M', strtotime($current_week_start)) . ' - ' . date('d M', strtotime($current_week_start . ' +6 days')); ?></p>
            <a href="?view=form&type=weekly&review_date=<?php echo $current_week_start; ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:8px; <?php echo $is_overdue ? 'background:#b91c1c; border-color:#b91c1c;' : ''; ?>">
                <?php echo $is_overdue ? 'Submit Overdue Review' : 'Submit This Week'; ?>
            </a>
        <?php endif; ?>
        <button class="btn btn-outline open-date-picker" data-type="weekly" style="width:100%;justify-content:center; font-size:13px;">
            <i class="fas fa-calendar-alt"></i> Submit for Different Week
        </button>
    </div>

    <!-- THIS MONTH'S REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($current_month_submitted): ?>
            <div class="status-badge status-done"><i class="fas fa-check"></i> Done: <?php echo $current_month_score; ?>%</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">This Month's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('F Y', strtotime($current_month . '-01')); ?></p>
            
            <?php if(strtotime($current_month . '-01') < strtotime('-7 days')): ?>
                <button class="btn btn-outline" disabled style="width:100%;justify-content:center; color:#b91c1c; border-color:#b91c1c; background:#fef2f2; opacity:0.7;"><i class="fas fa-lock"></i> Review Locked</button>
            <?php else: ?>
                <a href="?view=form&type=monthly&review_date=<?php echo $current_month . '-01'; ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:8px;">Edit Submission</a>
            <?php endif; ?>
        <?php else: ?>
            <?php 
            // Check if month review is overdue (it's past the last day of the month)
            $month_end = date('Y-m-t', strtotime($current_month . '-01'));
            $is_overdue = (date('Y-m-d') > $month_end);
            ?>
            <?php if($is_overdue): ?>
                <div class="status-badge" style="background:#fef2f2; color:#b91c1c; border:1px solid #ef4444;"><i class="fas fa-exclamation-triangle"></i> Overdue</div>
            <?php else: ?>
                <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <?php endif; ?>
            <h3 style="font-size:18px; font-weight:700; color:<?php echo $is_overdue ? '#b91c1c' : '#1e3a8a'; ?>">This Month's Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo date('F Y'); ?></p>
            <a href="?view=form&type=monthly&review_date=<?php echo $current_month . '-01'; ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:8px; <?php echo $is_overdue ? 'background:#b91c1c; border-color:#b91c1c;' : ''; ?>">
                <?php echo $is_overdue ? 'Submit Overdue Review' : 'Submit This Month'; ?>
            </a>
        <?php endif; ?>
        <button class="btn btn-outline open-date-picker" data-type="monthly" style="width:100%;justify-content:center; font-size:13px;">
            <i class="fas fa-calendar-alt"></i> Submit for Different Month
        </button>
    </div>
</div>

<?php if($total_pending > 0): ?>
<h2 style="margin-bottom:15px; font-size:16px; color:#475569; font-weight:700; text-transform:uppercase;">
    Pending Reviews <span style="background:#ef4444; color:white; padding:2px 10px; border-radius:12px; font-size:13px; margin-left:8px;"><?php echo $total_pending; ?></span>
</h2>

<div class="card" style="margin-bottom:20px; background:#fef2f2; border-left:5px solid #ef4444;">
    <p style="margin:0 0 15px 0; color:#64748b; font-size:14px;">You have <strong><?php echo $total_pending; ?> pending reviews</strong>. Click any date below to submit.</p>
    
    <?php if(count($pending_daily) > 0): ?>
        <div style="margin-bottom:20px;">
            <h4 style="font-size:14px; font-weight:700; color:#1e3a8a; margin-bottom:10px;">
                <i class="fas fa-calendar-day"></i> Daily Reviews (<?php echo count($pending_daily); ?>)
            </h4>
            <div style="display:flex; flex-wrap:wrap; gap:8px;">
                <?php foreach($pending_daily as $pdate): ?>
                    <a href="?view=form&type=daily&review_date=<?php echo $pdate; ?>" 
                       class="btn btn-sm" 
                       style="background:white; color:#1e3a8a; border:1px solid #cbd5e1; padding:6px 12px; font-size:13px; text-decoration:none;">
                        <?php echo date('d M', strtotime($pdate)); ?>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>
    <?php endif; ?>
    
    <?php if(count($pending_weekly) > 0): ?>
        <div style="margin-bottom:20px;">
            <h4 style="font-size:14px; font-weight:700; color:#1e3a8a; margin-bottom:10px;">
                <i class="fas fa-calendar-week"></i> Weekly Reviews (<?php echo count($pending_weekly); ?>)
            </h4>
            <div style="display:flex; flex-wrap:wrap; gap:8px;">
                <?php foreach($pending_weekly as $wdate): ?>
                    <?php 
                    $week_end = date('Y-m-d', strtotime($wdate . ' +6 days'));
                    ?>
                    <a href="?view=form&type=weekly&review_date=<?php echo $wdate; ?>" 
                       class="btn btn-sm" 
                       style="background:white; color:#1e3a8a; border:1px solid #cbd5e1; padding:6px 12px; font-size:13px; text-decoration:none;">
                        <?php echo date('d M', strtotime($wdate)) . ' - ' . date('d M', strtotime($week_end)); ?>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>
    <?php endif; ?>
    
    <?php if(count($pending_monthly) > 0): ?>
        <div>
            <h4 style="font-size:14px; font-weight:700; color:#1e3a8a; margin-bottom:10px;">
                <i class="fas fa-calendar-alt"></i> Monthly Reviews (<?php echo count($pending_monthly); ?>)
            </h4>
            <div style="display:flex; flex-wrap:wrap; gap:8px;">
                <?php foreach($pending_monthly as $mdate): ?>
                    <a href="?view=form&type=monthly&review_date=<?php echo $mdate . '-01'; ?>" 
                       class="btn btn-sm" 
                       style="background:white; color:#1e3a8a; border:1px solid #cbd5e1; padding:6px 12px; font-size:13px; text-decoration:none;">
                        <?php echo date('F Y', strtotime($mdate . '-01')); ?>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>
    <?php endif; ?>
</div>
<?php endif; ?>

<h2 style="margin-bottom:15px; font-size:16px; color:#475569; font-weight:700; text-transform:uppercase;">Other Reviews</h2>
<div class="grid" style="margin-bottom:40px">
    <!-- QUARTERLY REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($quarterly_submitted): ?>
            <div class="status-badge status-done"><i class="fas fa-check"></i> Submitted</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Quarterly Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $quarterly_target; ?></p>
            <a href="?view=form&type=quarterly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:10px;">Edit</a>
            <button class="btn btn-outline open-date-picker" data-type="quarterly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Quarter
            </button>
        <?php else: ?>
            <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Quarterly Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $quarterly_target; ?></p>
            <a href="?view=form&type=quarterly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:10px;">Start Quarterly</a>
            <button class="btn btn-outline open-date-picker" data-type="quarterly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Quarter
            </button>
        <?php endif; ?>
    </div>

    <!-- HALF-YEARLY REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($halfyearly_submitted): ?>
            <div class="status-badge status-done"><i class="fas fa-check"></i> Submitted</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Half-Yearly</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $halfyearly_target; ?></p>
            <a href="?view=form&type=halfyearly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:10px;">Edit</a>
            <button class="btn btn-outline open-date-picker" data-type="halfyearly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Half-Year
            </button>
        <?php else: ?>
            <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Half-Yearly</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $halfyearly_target; ?></p>
            <a href="?view=form&type=halfyearly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:10px;">Start Half-Yearly</a>
            <button class="btn btn-outline open-date-picker" data-type="halfyearly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Half-Year
            </button>
        <?php endif; ?>
    </div>

    <!-- YEARLY REVIEW CARD -->
    <div class="card" style="border-top:5px solid #1e3a8a">
        <?php if($yearly_submitted): ?>
            <div class="status-badge status-done"><i class="fas fa-check"></i> Submitted</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Yearly Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $yearly_target; ?></p>
            <a href="?view=form&type=yearly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-outline" style="width:100%;justify-content:center; margin-bottom:10px;">Edit</a>
            <button class="btn btn-outline open-date-picker" data-type="yearly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Year
            </button>
        <?php else: ?>
            <div class="status-badge status-pending"><i class="fas fa-clock"></i> Pending</div>
            <h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Yearly Review</h3>
            <p style="margin:8px 0;color:#64748b;font-size:14px"><?php echo $yearly_target; ?></p>
            <a href="?view=form&type=yearly&review_date=<?php echo date('Y-m-d'); ?>" class="btn btn-primary" style="width:100%;justify-content:center; margin-bottom:10px;">Start Yearly</a>
            <button class="btn btn-outline open-date-picker" data-type="yearly" style="width:100%;justify-content:center; font-size:13px;">
                <i class="fas fa-calendar-alt"></i> Submit for Different Year
            </button>
        <?php endif; ?>
    </div>
</div>
<?php endif; ?>

<?php if($can_evaluate_team): ?>
<h2 style="margin-bottom:15px; font-size:16px; color:#475569; font-weight:700; text-transform:uppercase;">Manager Tools</h2>
<div class="grid">
<div class="card" style="border-left:5px solid #1e3a8a">
<h3 style="font-size:18px; font-weight:700; color:#1e3a8a">Team Evaluation</h3>
<p style="margin:8px 0;color:#64748b;font-size:14px">Evaluate your team's performance.</p>
<a href="?view=admin_eval" class="btn btn-primary"><i class="fas fa-arrow-right"></i> Go to Evaluation Portal</a>
</div>
<div class="card" style="border-left:5px solid #1e3a8a">
<h3 style="font-size:18px; font-weight:700; color:#1e3a8a">View All Reviews</h3>
<p style="margin:8px 0;color:#64748b;font-size:14px">Access all employee reviews.</p>
<a href="?view=history_admin_self" class="btn btn-primary"><i class="fas fa-arrow-right"></i> View All Reviews</a>
</div>
</div>
<?php endif; ?>

<?php elseif($view == 'admin_eval' && $can_evaluate_team): ?>
<!-- TEAM EVALUATION VIEW (Admin & Reporting Managers) -->

<div class="filter-panel">
    <div class="filter-header"><h4><i class="fas fa-search"></i> Search & Filter Team</h4></div>
    <form method="GET">
        <input type="hidden" name="view" value="admin_eval">
        
        <div class="row">
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Global Search</label>
                    <input type="text" name="global_search" class="form-control" placeholder="Search..." value="<?php echo isset($_GET['global_search']) ? htmlspecialchars($_GET['global_search']) : ''; ?>">
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Department</label>
                    <select name="f_dept" class="filter-control select2">
                        <option value="">All Departments</option>
                        <?php foreach($depts_master as $dm): ?>
                            <option value="<?php echo htmlspecialchars($dm); ?>" <?php echo (isset($_GET['f_dept']) && $_GET['f_dept']==$dm)?'selected':''; ?>><?php echo htmlspecialchars($dm); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Position</label>
                    <select name="f_pos" class="filter-control select2">
                        <option value="">All Positions</option>
                        <?php foreach($pos_master as $pm): ?>
                            <option value="<?php echo htmlspecialchars($pm); ?>" <?php echo (isset($_GET['f_pos']) && $_GET['f_pos']==$pm)?'selected':''; ?>><?php echo htmlspecialchars($pm); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Select Employee</label>
                    <select name="f_emp" class="filter-control select2">
                        <option value="">Specific Employee</option>
                        <?php 
                        $emp_q = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE $employee_visibility_where ORDER BY name ASC");
                        while($e = mysqli_fetch_assoc($emp_q)) {
                            $selected = (isset($_GET['f_emp']) && $_GET['f_emp'] == $e['employee_id']) ? 'selected' : '';
                            echo "<option value='{$e['employee_id']}' $selected>{$e['name']} ({$e['employee_id']})</option>";
                        }
                        ?>
                    </select>
                </div>
            </div>
        </div>
        
        <div style="text-align: right; margin-top: 15px;">
            <a href="?view=admin_eval" class="btn btn-outline" style="padding:10px 20px; margin-right:10px;">Clear</a>
            <button type="submit" class="btn btn-primary" style="padding:10px 20px;">Apply Filters</button>
        </div>
    </form>
</div>

<div class="card">
<h2 style="font-size:18px; font-weight:700; color:#1e3a8a; margin-bottom:20px; text-transform:uppercase;">Team Performance Overview</h2>
<div class="table-responsive">
<table class="table table-bordered table-hover">
<thead>
    <tr>
        <th>Employee Details</th>
        <th>Designation</th>
        <th style="width: 25%;">Avg. Performance (Manager Only)</th>
        <th style="text-align:right; min-width: 350px;">Evaluate Action</th>
    </tr>
</thead>
<tbody>
<?php 
$where = $employee_visibility_where_team_only; // Use team-only visibility (excludes manager)

if(!empty($_GET['global_search'])) {
    $s = mysqli_real_escape_string($con, $_GET['global_search']);
    $where .= " AND (name LIKE '%$s%' OR employee_id LIKE '%$s%')";
} else {
    if(!empty($_GET['f_emp'])) $where .= " AND employee_id = '".mysqli_real_escape_string($con, $_GET['f_emp'])."'";
    if(!empty($_GET['f_dept'])) $where .= " AND department='".mysqli_real_escape_string($con, $_GET['f_dept'])."'";
    if(!empty($_GET['f_pos'])) $where .= " AND position='".mysqli_real_escape_string($con, $_GET['f_pos'])."'";
}

// DEBUG: Show the actual query being used
if (isset($_GET['debug_permissions'])) {
    echo "<tr><td colspan='4' style='background:#fff3cd; padding:15px;'>";
    echo "<strong>DEBUG - Evaluate Team Query:</strong><br>";
    echo "<code>SELECT employee_id, name, department, position FROM hr_employees WHERE $where ORDER BY name LIMIT 100</code><br>";
    echo "<strong>WHERE clause:</strong> <code>" . htmlspecialchars($where) . "</code>";
    echo "</td></tr>";
}

$emps = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE $where ORDER BY name LIMIT 100");

// DEBUG: Show query result
if (isset($_GET['debug_permissions'])) {
    echo "<tr><td colspan='4' style='background:#d4edda; padding:15px;'>";
    if ($emps) {
        echo "<strong>Query executed successfully!</strong><br>";
        echo "<strong>Number of rows returned:</strong> " . mysqli_num_rows($emps);
    } else {
        echo "<strong style='color:red;'>Query FAILED!</strong><br>";
        echo "<strong>Error:</strong> " . mysqli_error($con);
    }
    echo "</td></tr>";
}

if($emps && mysqli_num_rows($emps) > 0) {
    while($row = mysqli_fetch_assoc($emps)): 
        $emp_dept = $row['department'] ? $row['department'] : 'General';
        $emp_pos = $row['position'] ? $row['position'] : 'General';
        $avg_val = getEmployeeAvgScore($con, $row['employee_id']);
        
        // Use new 6-tier rating system
        $rating_style = getPerfStyle($avg_val);
    ?>
    <tr style="border-left: 5px solid <?php echo $rating_style['c']; ?>;">
    <td>
        <div style="font-weight:700; color:#1e293b; font-size:15px;"><?php echo htmlspecialchars($row['name']); ?></div>
        <div style="font-size:12px; color:#64748b;">ID: <code><?php echo htmlspecialchars($row['employee_id']); ?></code></div>
    </td>
    <td>
        <span class="badge-pos"><?php echo htmlspecialchars($emp_pos); ?></span><br>
        <span class="badge-dept" style="display:inline-block; margin-top:4px;"><?php echo htmlspecialchars($emp_dept); ?></span>
    </td>
    <td>
        <div style="display:flex; justify-content:space-between; font-size:13px; font-weight:700; color:<?php echo $rating_style['c']; ?>;">
            <span><?php echo $rating_style['icon'] . ' ' . $rating_style['r']; ?></span>
            <span><?php echo $avg_val; ?>%</span>
        </div>
        <div class="perf-progress">
            <div class="perf-progress-bar" style="width:<?php echo $avg_val; ?>%; background:<?php echo $rating_style['c']; ?>;"></div>
        </div>
    </td>
    <td style="text-align:right">
        <div class="btn-group">
            <button class="btn btn-gray open-mgr-date-picker" 
                    data-type="mgr_weekly" 
                    data-eid="<?php echo htmlspecialchars($row['employee_id']); ?>" 
                    data-ename="<?php echo htmlspecialchars($row['name']); ?>" 
                    data-edept="<?php echo htmlspecialchars($emp_dept); ?>" 
                    data-epos="<?php echo htmlspecialchars($emp_pos); ?>" 
                    title="Weekly Review">Wk</button>
            <button class="btn btn-info open-mgr-date-picker" 
                    data-type="mgr_monthly" 
                    data-eid="<?php echo htmlspecialchars($row['employee_id']); ?>" 
                    data-ename="<?php echo htmlspecialchars($row['name']); ?>" 
                    data-edept="<?php echo htmlspecialchars($emp_dept); ?>" 
                    data-epos="<?php echo htmlspecialchars($emp_pos); ?>" 
                    title="Monthly Review">Mo</button>
            <button class="btn btn-teal open-mgr-date-picker" 
                    data-type="mgr_quarterly" 
                    data-eid="<?php echo htmlspecialchars($row['employee_id']); ?>" 
                    data-ename="<?php echo htmlspecialchars($row['name']); ?>" 
                    data-edept="<?php echo htmlspecialchars($emp_dept); ?>" 
                    data-epos="<?php echo htmlspecialchars($emp_pos); ?>" 
                    title="Quarterly Review">Qtly</button>
            <button class="btn btn-purple open-mgr-date-picker" 
                    data-type="mgr_halfyearly" 
                    data-eid="<?php echo htmlspecialchars($row['employee_id']); ?>" 
                    data-ename="<?php echo htmlspecialchars($row['name']); ?>" 
                    data-edept="<?php echo htmlspecialchars($emp_dept); ?>" 
                    data-epos="<?php echo htmlspecialchars($emp_pos); ?>" 
                    title="Half-Yearly Review">H-Yr</button>
            <button class="btn btn-success open-mgr-date-picker" 
                    data-type="mgr_yearly" 
                    data-eid="<?php echo htmlspecialchars($row['employee_id']); ?>" 
                    data-ename="<?php echo htmlspecialchars($row['name']); ?>" 
                    data-edept="<?php echo htmlspecialchars($emp_dept); ?>" 
                    data-epos="<?php echo htmlspecialchars($emp_pos); ?>" 
                    title="Yearly Review">Yearly</button>
        </div>
    </td>
    </tr>
    <?php endwhile; 
} else {
    echo '<tr><td colspan="4" style="text-align:center; padding:30px; color:#64748b;">No active employees found matching the criteria.</td></tr>';
}
?>
</tbody>
</table>
</div>
</div>

<?php elseif($view == 'history_self' || strpos($view, 'history_') !== false): 
    $is_mgr_view = (strpos($view, 'mgr') !== false); 
    $is_admin_view = (strpos($view, 'admin') !== false); 
    $view_title = ($view == 'history_self') ? 'My Review History' : str_replace('_', ' ', strtoupper($view));
    
    // --- SMART DEFAULT DATE LOGIC (Requested Features) ---
    $default_start = '';
    $default_end = '';
    
    if($view == 'history_self' && !$is_admin) {
        $default_start = date('Y-m-d', strtotime('monday this week'));
        $default_end = date('Y-m-d', strtotime('sunday this week'));
    }
    elseif($view == 'history_mgr') {
        $default_start = date('Y-m-01');
        $default_end = date('Y-m-t');
    }
    elseif($view == 'history_admin_self') {
        $default_start = date('Y-m-d');
        $default_end = date('Y-m-d');
    }
    elseif($view == 'history_admin_mgr' || $view == 'history_mgr_feedback') {
        $default_start = date('Y-m-01');
        $default_end = date('Y-m-t');
    }
    
    $f_start = isset($_GET['start']) && $_GET['start'] != '' ? $_GET['start'] : $default_start;
    $f_end = isset($_GET['end']) && $_GET['end'] != '' ? $_GET['end'] : $default_end;
    $f_type = isset($_GET['type_filter']) ? $_GET['type_filter'] : '';
    $f_search = isset($_GET['search']) ? $_GET['search'] : '';
    $f_emp = isset($_GET['emp_filter']) ? $_GET['emp_filter'] : '';
?>
<div class="filter-panel no-print">
    <div class="filter-header"><h4><i class="fas fa-filter"></i> Filter History <?php if($default_start && empty($_GET['start'])) echo "<small style='font-size:12px;color:#64748b;font-weight:400;'>(Showing Active Period)</small>"; ?></h4></div>
    <form method="GET">
        <input type="hidden" name="view" value="<?php echo $view; ?>">
        
        <div class="row">
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Start Date</label>
                    <input type="date" name="start" class="form-control" value="<?php echo $f_start; ?>">
                </div>
            </div>
            <div class="col-md-3">
                <div class="filter-group">
                    <label>End Date</label>
                    <input type="date" name="end" class="form-control" value="<?php echo $f_end; ?>">
                </div>
            </div>
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Review Type</label>
                    <select name="type_filter" class="form-control">
                        <option value="">All Types</option>
                        <option value="daily" <?php if($f_type=='daily') echo 'selected'; ?>>Daily</option>
                        <option value="weekly" <?php if($f_type=='weekly') echo 'selected'; ?>>Weekly</option>
                        <option value="monthly" <?php if($f_type=='monthly') echo 'selected'; ?>>Monthly</option>
                        <option value="quarterly" <?php if($f_type=='quarterly') echo 'selected'; ?>>Quarterly</option>
                        <option value="halfyearly" <?php if($f_type=='halfyearly') echo 'selected'; ?>>Half-Yearly</option>
                        <option value="yearly" <?php if($f_type=='yearly') echo 'selected'; ?>>Yearly</option>
                    </select>
                </div>
            </div>
            
            <?php if($is_admin_view): ?>
            <div class="col-md-3">
                <div class="filter-group">
                    <label>Employee</label>
                    <select name="emp_filter" class="filter-control select2">
                        <option value="">All Employees</option>
                        <?php 
                        $all_history_emps = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE $employee_visibility_where ORDER BY name");
                        while($ae = mysqli_fetch_assoc($all_history_emps)) {
                            $sel = ($f_emp == $ae['employee_id']) ? 'selected' : '';
                            echo "<option value='{$ae['employee_id']}' $sel>{$ae['name']}</option>";
                        }
                        ?>
                    </select>
                </div>
            </div>
            <?php endif; ?>

            <div class="col-md-12" style="display:flex; align-items:flex-end; justify-content:flex-end; gap: 10px; margin-top:10px;">
                 <a href="?export_history_csv=1&view_context=<?php echo $view; ?>&start=<?php echo $f_start; ?>&end=<?php echo $f_end; ?>&type_filter=<?php echo $f_type; ?>&emp_filter=<?php echo $f_emp; ?>&is_admin=<?php echo $is_admin_view?'1':'0'; ?>&current_user_id=<?php echo $employee_id; ?>" class="btn btn-success" style="height: 50px;"><i class="fas fa-file-export"></i> Bulk Export to CSV</a>
                 <button type="submit" class="btn btn-primary" style="height: 50px; justify-content: center;"><i class="fas fa-search"></i> Apply Filters</button>
            </div>
        </div>
    </form>
</div>

<!-- GRAPHS SECTION FOR HISTORY VIEWS -->
<?php
// Prepare data for graphs
$graph_data = [
    'significant' => 0,
    'significant_employees' => [],
    'outstanding' => 0,
    'outstanding_employees' => [],
    'excellent' => 0,
    'excellent_employees' => [],
    'good' => 0,
    'good_employees' => [],
    'average' => 0,
    'average_employees' => [],
    'poor' => 0,
    'poor_employees' => [],
    'on_leave' => 0,
    'on_leave_employees' => []
];

$type_breakdown = [];
$completion_data = [
    'completed' => [],
    'not_completed' => []
];

// Get all active employees for completion tracking (based on permissions)
$all_active_employees = [];
$emp_query = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE $employee_visibility_where ORDER BY name ASC");
while($emp_row = mysqli_fetch_assoc($emp_query)) {
    $all_active_employees[$emp_row['employee_id']] = $emp_row['name'];
}

// Track which employees have submitted reviews
$employees_with_reviews = [];

// First pass: collect all data for graphs
$tables_for_graph = [];
if($is_mgr_view) {
    if(!$f_type || $f_type=='weekly') $tables_for_graph[] = ['tbl'=>'performance_weekly_manager', 'date'=>'week_start_date', 'label'=>'Weekly', 'k'=>'weekly_manager'];
    if(!$f_type || $f_type=='monthly') $tables_for_graph[] = ['tbl'=>'performance_monthly_manager', 'date'=>'review_month', 'label'=>'Monthly', 'k'=>'monthly_manager'];
    if(!$f_type || $f_type=='quarterly') $tables_for_graph[] = ['tbl'=>'performance_quarterly_manager', 'date'=>'review_quarter', 'label'=>'Quarterly', 'k'=>'quarterly_manager'];
    if(!$f_type || $f_type=='halfyearly') $tables_for_graph[] = ['tbl'=>'performance_halfyearly_manager', 'date'=>'review_halfyear', 'label'=>'Half-Yearly', 'k'=>'halfyearly_manager'];
    if(!$f_type || $f_type=='yearly') $tables_for_graph[] = ['tbl'=>'performance_yearly_manager', 'date'=>'review_year', 'label'=>'Yearly', 'k'=>'yearly_manager'];
} else {
    if(!$f_type || $f_type=='daily') $tables_for_graph[] = ['tbl'=>'performance_daily_self', 'date'=>'review_date', 'label'=>'Daily', 'k'=>'daily_self'];
    if(!$f_type || $f_type=='weekly') $tables_for_graph[] = ['tbl'=>'performance_weekly_self', 'date'=>'week_start_date', 'label'=>'Weekly', 'k'=>'weekly_self'];
    if(!$f_type || $f_type=='monthly') $tables_for_graph[] = ['tbl'=>'performance_monthly_self', 'date'=>'review_month', 'label'=>'Monthly', 'k'=>'monthly_self'];
    if(!$f_type || $f_type=='quarterly') $tables_for_graph[] = ['tbl'=>'performance_quarterly_self', 'date'=>'review_quarter', 'label'=>'Quarterly', 'k'=>'quarterly_self'];
    if(!$f_type || $f_type=='halfyearly') $tables_for_graph[] = ['tbl'=>'performance_halfyearly_self', 'date'=>'review_halfyear', 'label'=>'Half-Yearly', 'k'=>'halfyearly_self'];
    if(!$f_type || $f_type=='yearly') $tables_for_graph[] = ['tbl'=>'performance_yearly_self', 'date'=>'review_year', 'label'=>'Yearly', 'k'=>'yearly_self'];
}

foreach($tables_for_graph as $t) {
    $sql = "SELECT * FROM `{$t['tbl']}` WHERE 1=1";
    
    // Apply employee visibility based on permissions
    if($is_admin_view) {
        // For admin/manager views, apply visibility filter
        if($f_emp) {
            // Specific employee selected
            $sql .= " AND employee_id='$f_emp'";
        } else {
            // Show all visible employees based on permissions
            if($is_managing_director || $is_abishek || $is_keerthi || $is_management_dept || $is_hr_dept) {
                // Managing directors and admins see everyone (no additional filter)
            } elseif($is_reporting_manager) {
                // Reporting managers see ONLY their team (exclude themselves from admin views)
                $managed_ids = array_keys($managed_employees);
                if(count($managed_ids) > 0) {
                    $ids_list = "'" . implode("','", $managed_ids) . "'";
                    $sql .= " AND employee_id IN ($ids_list)";
                } else {
                    // No team members, show nothing
                    $sql .= " AND 1=0";
                }
            } else {
                // Regular users only see themselves
                $sql .= " AND employee_id='$employee_id'";
            }
        }
    } else {
        // For self views, only show current user
        $sql .= " AND employee_id='$employee_id'";
    }
    
    // Handle date filtering based on column type
    if(!empty($f_start)) {
        if ($t['date'] == 'review_month') {
            // For monthly reviews, extract year-month from start date
            $sql .= " AND {$t['date']} >= '" . date('Y-m', strtotime($f_start)) . "'";
        } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
            // For quarter/halfyear/year, check if period is within range
            $sql .= " AND {$t['date']} >= '" . date('Y', strtotime($f_start)) . "'";
        } else {
            $sql .= " AND {$t['date']} >= '$f_start'";
        }
    }
    if(!empty($f_end)) {
        if ($t['date'] == 'review_month') {
            // For monthly reviews, extract year-month from end date
            $sql .= " AND {$t['date']} <= '" . date('Y-m', strtotime($f_end)) . "'";
        } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
            // For quarter/halfyear/year, check if period is within range
            $sql .= " AND {$t['date']} <= '" . date('Y', strtotime($f_end)) . "'";
        } else {
            $sql .= " AND {$t['date']} <= '$f_end'";
        }
    }
    
    if($f_search) {
        $s = mysqli_real_escape_string($con, $f_search);
        $sql .= " AND (employee_name LIKE '%$s%'";
        if($is_mgr_view) $sql .= " OR manager_name LIKE '%$s%'";
        $sql .= ")";
    }

    $q = mysqli_query($con, $sql);
    if($q && mysqli_num_rows($q)>0) {
        while($row = mysqli_fetch_assoc($q)) {
            $score = $row['total_score'];
            $emp_id = $row['employee_id'];
            $emp_name = $row['employee_name'];
            
            // Track employees who have submitted
            if(!in_array($emp_id, $employees_with_reviews)) {
                $employees_with_reviews[] = $emp_id;
                $completion_data['completed'][] = ['id' => $emp_id, 'name' => $emp_name];
            }
            
            // Category breakdown with employee names
            if($score == -1) {
                $graph_data['on_leave']++;
                $graph_data['on_leave_employees'][] = ['name' => $emp_name, 'score' => 'On Leave', 'id' => $emp_id];
            } elseif($score >= 95) {
                $graph_data['significant']++;
                $graph_data['significant_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            } elseif($score >= 90) {
                $graph_data['outstanding']++;
                $graph_data['outstanding_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            } elseif($score >= 85) {
                $graph_data['excellent']++;
                $graph_data['excellent_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            } elseif($score >= 80) {
                $graph_data['good']++;
                $graph_data['good_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            } elseif($score >= 70) {
                $graph_data['average']++;
                $graph_data['average_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            } else {
                $graph_data['poor']++;
                $graph_data['poor_employees'][] = ['name' => $emp_name, 'score' => $score, 'id' => $emp_id];
            }
            
            // Type breakdown
            if(!isset($type_breakdown[$t['label']])) {
                $type_breakdown[$t['label']] = ['count' => 0, 'total_score' => 0];
            }
            $type_breakdown[$t['label']]['count']++;
            if($score >= 0) {
                $type_breakdown[$t['label']]['total_score'] += $score;
            }
        }
    }
}

// Calculate not completed employees (only for admin view)
if($is_admin_view) {
    foreach($all_active_employees as $emp_id => $emp_name) {
        if(!in_array($emp_id, $employees_with_reviews)) {
            $completion_data['not_completed'][] = ['id' => $emp_id, 'name' => $emp_name];
        }
    }
}

$completed_count = count($completion_data['completed']);
$not_completed_count = count($completion_data['not_completed']);
?>

<div class="card" style="margin-bottom: 25px;">
    <h3 style="color:#1e3a8a; margin-bottom:20px; font-size:18px;"><i class="fas fa-chart-bar"></i> Performance Analytics</h3>
    
    <div class="row">
        <!-- Performance Distribution Chart -->
        <div class="col-md-6 mb-4">
            <div style="background:#f8fafc; padding:20px; border-radius:10px; border:2px solid #e2e8f0;">
                <h4 style="font-size:15px; color:#1e3a8a; margin-bottom:15px; font-weight:700;">Performance Distribution</h4>
                <div style="height: 300px;">
                    <canvas id="performanceDistChart"></canvas>
                </div>
            </div>
        </div>
        
        <!-- Review Type Breakdown Chart -->
        <div class="col-md-6 mb-4">
            <div style="background:#f8fafc; padding:20px; border-radius:10px; border:2px solid #e2e8f0;">
                <h4 style="font-size:15px; color:#1e3a8a; margin-bottom:15px; font-weight:700;">Review Type Breakdown</h4>
                <div style="height: 300px;">
                    <canvas id="typeBreakdownChart"></canvas>
                </div>
            </div>
        </div>
    </div>
    
    <?php if($is_admin_view): ?>
    <div class="row">
        <div class="col-md-12">
            <div style="background:#f8fafc; padding:20px; border-radius:10px; border:2px solid #e2e8f0;">
                <h4 style="font-size:15px; color:#1e3a8a; margin-bottom:15px; font-weight:700;">
                    <i class="fas fa-tasks"></i> Completion Status 
                    <small style="font-size:12px; color:#64748b; font-weight:400;">(Click on chart to see employee names)</small>
                </h4>
                <div style="height: 300px;">
                    <canvas id="completionChart"></canvas>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Employee List Display -->
    <div id="employeeListDisplay" style="display:none; margin-top:20px; padding:20px; background:#f8fafc; border-radius:10px; border:2px solid #e2e8f0;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px;">
            <h4 style="margin:0; font-size:16px; color:#1e3a8a; font-weight:700;">
                <i class="fas fa-users"></i> <span id="listTitle"></span>
            </h4>
            <button onclick="document.getElementById('employeeListDisplay').style.display='none'" style="background:#64748b; color:white; border:none; padding:6px 12px; border-radius:6px; cursor:pointer; font-weight:600;">
                <i class="fas fa-times"></i> Close
            </button>
        </div>
        <div id="employeeListContent" style="display:grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap:15px;"></div>
    </div>
    <?php endif; ?>
</div>

<script>
(function() {
    // Performance Distribution Chart
    var distCtx = document.getElementById('performanceDistChart');
    if(distCtx) {
        distCtx = distCtx.getContext('2d');
        
        // Store employee data for each category
        var employeesByCategory = {
            'significant': <?php echo json_encode($graph_data['significant_employees']); ?>,
            'outstanding': <?php echo json_encode($graph_data['outstanding_employees']); ?>,
            'excellent': <?php echo json_encode($graph_data['excellent_employees']); ?>,
            'good': <?php echo json_encode($graph_data['good_employees']); ?>,
            'average': <?php echo json_encode($graph_data['average_employees']); ?>,
            'poor': <?php echo json_encode($graph_data['poor_employees']); ?>,
            'on_leave': <?php echo json_encode($graph_data['on_leave_employees']); ?>
        };
        
        var categoryNames = ['significant', 'outstanding', 'excellent', 'good', 'average', 'poor', 'on_leave'];
        var categoryLabels = ['💎 Significant (95%+)', '🏆 Outstanding (90-94%)', '⭐ Excellent (85-89%)', '✨ Good (80-84%)', '👍 Average (70-79%)', '🚫 Poor (<70%)', '🏖️ On Leave'];
        
        var distChart = new Chart(distCtx, {
            type: 'doughnut',
            data: {
                labels: categoryLabels,
                datasets: [{
                    data: [
                        <?php echo $graph_data['significant']; ?>,
                        <?php echo $graph_data['outstanding']; ?>,
                        <?php echo $graph_data['excellent']; ?>,
                        <?php echo $graph_data['good']; ?>,
                        <?php echo $graph_data['average']; ?>,
                        <?php echo $graph_data['poor']; ?>,
                        <?php echo $graph_data['on_leave']; ?>
                    ],
                    backgroundColor: ['#0f766e', '#059669', '#10b981', '#2563eb', '#d97706', '#dc2626', '#94a3b8'],
                    borderWidth: 2,
                    borderColor: '#fff'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 15,
                            font: { size: 11, weight: '600' },
                            usePointStyle: true
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        titleFont: { size: 14, weight: 'bold' },
                        bodyFont: { size: 13 },
                        callbacks: {
                            afterLabel: function(context) {
                                return '👆 Click to see employee names';
                            }
                        }
                    }
                },
                onClick: function(evt, activeElements) {
                    if (activeElements.length > 0) {
                        var index = activeElements[0].index;
                        var category = categoryNames[index];
                        var employees = employeesByCategory[category];
                        var label = categoryLabels[index];
                        
                        if (employees && employees.length > 0) {
                            showEmployeeList(label, employees);
                        } else {
                            alert('No employees in this category');
                        }
                    }
                }
            }
        });
        
        // Function to display employee list
        function showEmployeeList(categoryLabel, employees) {
            var listDisplay = document.getElementById('employeeListDisplay');
            var listContent = document.getElementById('employeeListContent');
            var listTitle = document.getElementById('listTitle');
            
            if (!listDisplay || !listContent || !listTitle) {
                console.error('Employee list elements not found');
                return;
            }
            
            listTitle.textContent = categoryLabel + ' (' + employees.length + ' employees)';
            
            var html = '';
            employees.forEach(function(emp) {
                html += '<div style="background:white; padding:15px; border-radius:8px; border:1px solid #e2e8f0; box-shadow:0 1px 3px rgba(0,0,0,0.1);">';
                html += '<div style="font-weight:700; color:#1e3a8a; margin-bottom:5px; font-size:14px;">' + emp.name + '</div>';
                html += '<div style="font-size:12px; color:#64748b;">Score: <strong>' + emp.score + (emp.score !== 'On Leave' ? '%' : '') + '</strong></div>';
                html += '</div>';
            });
            
            listContent.innerHTML = html;
            listDisplay.style.display = 'block';
            
            // Scroll to the list
            listDisplay.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
    }
    
    // Review Type Breakdown Chart
    var typeCtx = document.getElementById('typeBreakdownChart');
    if(typeCtx) {
        typeCtx = typeCtx.getContext('2d');
        var typeLabels = <?php echo json_encode(array_keys($type_breakdown)); ?>;
        var typeCounts = <?php echo json_encode(array_column($type_breakdown, 'count')); ?>;
        
        new Chart(typeCtx, {
            type: 'bar',
            data: {
                labels: typeLabels,
                datasets: [{
                    label: 'Number of Reviews',
                    data: typeCounts,
                    backgroundColor: '#1e3a8a',
                    borderRadius: 8,
                    barPercentage: 0.6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1,
                            font: { size: 12, weight: '600' }
                        },
                        grid: { color: '#e2e8f0' }
                    },
                    x: {
                        grid: { display: false },
                        ticks: {
                            font: { size: 12, weight: '700' },
                            color: '#1e293b'
                        }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        titleFont: { size: 14, weight: 'bold' },
                        bodyFont: { size: 13 }
                    }
                }
            }
        });
    }
    
    <?php if($is_admin_view): ?>
    // Completion Status Chart
    var completionCtx = document.getElementById('completionChart');
    if(completionCtx) {
        completionCtx = completionCtx.getContext('2d');
        
        var completedEmployees = <?php echo json_encode($completion_data['completed']); ?>;
        var notCompletedEmployees = <?php echo json_encode($completion_data['not_completed']); ?>;
        
        new Chart(completionCtx, {
            type: 'bar',
            data: {
                labels: ['Completed', 'Not Completed'],
                datasets: [{
                    label: 'Employees',
                    data: [<?php echo $completed_count; ?>, <?php echo $not_completed_count; ?>],
                    backgroundColor: ['#10b981', '#ef4444'],
                    borderRadius: 8,
                    barPercentage: 0.5
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                onClick: function(evt, elements) {
                    if(elements.length > 0) {
                        var index = elements[0].index;
                        var employees = index === 0 ? completedEmployees : notCompletedEmployees;
                        var title = index === 0 ? 'Completed Reviews (' + employees.length + ')' : 'Not Completed Reviews (' + employees.length + ')';
                        var color = index === 0 ? '#10b981' : '#ef4444';
                        
                        document.getElementById('listTitle').textContent = title;
                        var html = '';
                        
                        if(employees.length === 0) {
                            html = '<div style="text-align:center; padding:40px; color:#64748b;">No employees in this category</div>';
                        } else {
                            employees.forEach(function(emp) {
                                html += '<div style="background:white; padding:15px; border-radius:8px; border-left:4px solid ' + color + ';">' +
                                        '<div style="font-weight:700; font-size:15px; color:#1e293b; margin-bottom:5px;">' + emp.name + '</div>' +
                                        '<div style="font-size:11px; color:#64748b;">ID: ' + emp.id + '</div>' +
                                        '</div>';
                            });
                        }
                        
                        document.getElementById('employeeListContent').innerHTML = html;
                        document.getElementById('employeeListDisplay').style.display = 'block';
                        document.getElementById('employeeListDisplay').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1,
                            font: { size: 12, weight: '600' }
                        },
                        grid: { color: '#e2e8f0' }
                    },
                    x: {
                        grid: { display: false },
                        ticks: {
                            font: { size: 13, weight: '700' },
                            color: '#1e293b'
                        }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: '#1e293b',
                        padding: 12,
                        cornerRadius: 8,
                        titleFont: { size: 14, weight: 'bold' },
                        bodyFont: { size: 13 },
                        callbacks: {
                            label: function(context) {
                                var total = <?php echo $completed_count + $not_completed_count; ?>;
                                var percentage = total > 0 ? Math.round((context.parsed.y / total) * 100) : 0;
                                return ['Employees: ' + context.parsed.y, 'Percentage: ' + percentage + '%', '👆 Click to see names'];
                            }
                        }
                    }
                }
            }
        });
    }
    <?php endif; ?>
})();
</script>


<div class="card">
<h2 style="margin-bottom:25px; color:#1e3a8a"><i class="fas fa-history"></i> <?php echo $view_title; ?></h2>
<div class="table-responsive">
<table class="table table-bordered table-hover">
<thead><tr><th style="min-width: 180px;">Type</th><th>Employee</th><?php if($is_mgr_view) echo '<th>Manager</th>'; ?><th>Period/Date</th><th>Score</th><th>Rating</th><th>Submitted At</th><th>Actions</th></tr></thead>
<tbody>
<?php
$tables = [];
if($is_mgr_view) {
    if(!$f_type || $f_type=='weekly') $tables[] = ['tbl'=>'performance_weekly_manager', 'date'=>'week_start_date', 'label'=>'Weekly Manager', 'k'=>'weekly_manager'];
    if(!$f_type || $f_type=='monthly') $tables[] = ['tbl'=>'performance_monthly_manager', 'date'=>'review_month', 'label'=>'Monthly Manager', 'k'=>'monthly_manager'];
    if(!$f_type || $f_type=='quarterly') $tables[] = ['tbl'=>'performance_quarterly_manager', 'date'=>'review_quarter', 'label'=>'Quarterly Manager', 'k'=>'quarterly_manager'];
    if(!$f_type || $f_type=='halfyearly') $tables[] = ['tbl'=>'performance_halfyearly_manager', 'date'=>'review_halfyear', 'label'=>'Half-Yearly Manager', 'k'=>'halfyearly_manager'];
    if(!$f_type || $f_type=='yearly') $tables[] = ['tbl'=>'performance_yearly_manager', 'date'=>'review_year', 'label'=>'Yearly Manager', 'k'=>'yearly_manager'];
} else {
    if(!$f_type || $f_type=='daily') $tables[] = ['tbl'=>'performance_daily_self', 'date'=>'review_date', 'label'=>'Daily Self', 'k'=>'daily_self'];
    if(!$f_type || $f_type=='weekly') $tables[] = ['tbl'=>'performance_weekly_self', 'date'=>'week_start_date', 'label'=>'Weekly Self', 'k'=>'weekly_self'];
    if(!$f_type || $f_type=='monthly') $tables[] = ['tbl'=>'performance_monthly_self', 'date'=>'review_month', 'label'=>'Monthly Self', 'k'=>'monthly_self'];
    if(!$f_type || $f_type=='quarterly') $tables[] = ['tbl'=>'performance_quarterly_self', 'date'=>'review_quarter', 'label'=>'Quarterly Self', 'k'=>'quarterly_self'];
    if(!$f_type || $f_type=='halfyearly') $tables[] = ['tbl'=>'performance_halfyearly_self', 'date'=>'review_halfyear', 'label'=>'Half-Yearly Self', 'k'=>'halfyearly_self'];
    if(!$f_type || $f_type=='yearly') $tables[] = ['tbl'=>'performance_yearly_self', 'date'=>'review_year', 'label'=>'Yearly Self', 'k'=>'yearly_self'];
}

$all_rows = [];

foreach($tables as $t) {
    $sql = "SELECT * FROM `{$t['tbl']}` WHERE 1=1";
    
    // Apply employee visibility based on permissions
    if($is_admin_view) {
        // For admin/manager views, apply visibility filter
        if($f_emp) {
            // Specific employee selected
            $sql .= " AND employee_id='$f_emp'";
        } else {
            // Show all visible employees based on permissions
            if($is_managing_director || $is_abishek || $is_keerthi || $is_management_dept || $is_hr_dept) {
                // Managing directors and admins see everyone (no additional filter)
            } elseif($is_reporting_manager) {
                // Reporting managers see ONLY their team (exclude themselves from admin views)
                $managed_ids = array_keys($managed_employees);
                if(count($managed_ids) > 0) {
                    $ids_list = "'" . implode("','", $managed_ids) . "'";
                    $sql .= " AND employee_id IN ($ids_list)";
                } else {
                    // No team members, show nothing
                    $sql .= " AND 1=0";
                }
            } else {
                // Regular users only see themselves
                $sql .= " AND employee_id='$employee_id'";
            }
        }
    } else {
        // For self views, only show current user
        $sql .= " AND employee_id='$employee_id'";
    }
    
    // Handle date filtering based on column type
    if(!empty($f_start)) {
        if ($t['date'] == 'review_month') {
            // For monthly reviews, extract year-month from start date
            $sql .= " AND {$t['date']} >= '" . date('Y-m', strtotime($f_start)) . "'";
        } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
            // For quarter/halfyear/year, check if period is within range
            $sql .= " AND {$t['date']} >= '" . date('Y', strtotime($f_start)) . "'";
        } else {
            $sql .= " AND {$t['date']} >= '$f_start'";
        }
    }
    if(!empty($f_end)) {
        if ($t['date'] == 'review_month') {
            // For monthly reviews, extract year-month from end date
            $sql .= " AND {$t['date']} <= '" . date('Y-m', strtotime($f_end)) . "'";
        } elseif ($t['date'] == 'review_quarter' || $t['date'] == 'review_halfyear' || $t['date'] == 'review_year') {
            // For quarter/halfyear/year, check if period is within range
            $sql .= " AND {$t['date']} <= '" . date('Y', strtotime($f_end)) . "'";
        } else {
            $sql .= " AND {$t['date']} <= '$f_end'";
        }
    }
    
    if($f_search) {
        $s = mysqli_real_escape_string($con, $f_search);
        $sql .= " AND (employee_name LIKE '%$s%'";
        if($is_mgr_view) $sql .= " OR manager_name LIKE '%$s%'";
        $sql .= ")";
    }

    $q = mysqli_query($con, $sql);
    if($q && mysqli_num_rows($q)>0) {
        while($row = mysqli_fetch_assoc($q)) {
            $row['meta_type_label'] = $t['label'];
            $row['meta_type_key'] = $t['k'];
            $row['meta_date_col'] = $t['date'];
            $row['sort_date'] = $row[$t['date']]; 
            $all_rows[] = $row;
        }
    }
}

usort($all_rows, function($a, $b) {
    if ($a['sort_date'] == $b['sort_date']) {
        return $b['id'] - $a['id'];
    }
    return strcmp($b['sort_date'], $a['sort_date']);
});

if(count($all_rows) > 0) {
    foreach($all_rows as $row) {
        $t_label = $row['meta_type_label'];
        $t_key = $row['meta_type_key'];
        $date_val = $row[$row['meta_date_col']];
        $style = getPerfStyle($row['total_score']);
        $date_display = $date_val;
        if(isset($row['week_end_date'])) $date_display .= ' to ' . $row['week_end_date'];
        
        // Format submission timestamp
        $submitted_at = isset($row['submitted_at']) && $row['submitted_at'] ? $row['submitted_at'] : 'N/A';
        $submitted_display = 'N/A';
        $is_late_submission = false;
        
        if($submitted_at != 'N/A') {
            $submitted_display = date('d M Y, h:i A', strtotime($submitted_at));
            
            // Calculate if submission was late based on review type
            $submitted_date = date('Y-m-d', strtotime($submitted_at));
            
            // For weekly reviews: late if submitted after the week ends (after Sunday)
            if(isset($row['week_end_date'])) {
                $week_end_date = $row['week_end_date'];
                // Late if submitted on a different day than the week end date or after
                if($submitted_date > $week_end_date) {
                    $is_late_submission = true;
                }
            }
            // For monthly reviews: late if submitted after the month ends
            elseif(isset($row['review_month'])) {
                $month_end = date('Y-m-t', strtotime($row['review_month'] . '-01'));
                // Late if submitted after the month ends
                if($submitted_date > $month_end) {
                    $is_late_submission = true;
                }
            }
            // For daily reviews: late if submitted on a different day than the review date
            else {
                $review_date = $date_val;
                // Late if submitted on any day after the review date
                if($submitted_date > $review_date) {
                    $is_late_submission = true;
                }
            }
        }
        
        $ticket_ref = "[Ref: $t_key-{$row['id']}"; // Partial match for any question ticket
        $ticket_query = mysqli_query($con, "SELECT ticket_number, status FROM tickets WHERE message LIKE '%$ticket_ref%' LIMIT 1");
        $ticket_data = ($ticket_query && mysqli_num_rows($ticket_query) > 0) ? mysqli_fetch_assoc($ticket_query) : null;

        echo "<tr>";
        echo "<td><span class='badge-type'>{$t_label}</span></td>";
        echo "<td><b>".htmlspecialchars($row['employee_name'])."</b></td>";
        if($is_mgr_view) echo "<td>".htmlspecialchars($row['manager_name'])."</td>";
        echo "<td>$date_display</td>";
        
        if($row['total_score'] == -1) {
            echo "<td><span style='color:#94a3b8; font-weight:bold;'>--</span></td>";
            echo "<td><span style='background:#f1f5f9;color:#64748b;padding:4px 10px;border-radius:20px;font-weight:700;font-size:12px;border:1px solid #cbd5e1;'><i class='fas fa-umbrella-beach'></i> On Leave</span></td>";
        } else {
            echo "<td><b style='color:{$style['c']}'>{$row['total_score']}</b></td>";
            echo "<td><span style='background:{$style['bg']};color:{$style['c']};padding:4px 10px;border-radius:20px;font-weight:700;font-size:12px'>{$style['icon']} {$style['r']}</span></td>";
        }
        
        // Display submission timestamp with late badge if applicable
        echo "<td>";
        echo "<div style='font-size:12px; color:#64748b;'><i class='fas fa-clock'></i> $submitted_display</div>";
        if($is_late_submission) {
            echo "<span style='background:#fef3c7; color:#92400e; padding:2px 8px; border-radius:12px; font-size:10px; font-weight:700; margin-top:4px; display:inline-block;'><i class='fas fa-exclamation-triangle'></i> Late Submission</span>";
        }
        echo "</td>";
        
        echo "<td>";
        echo "<div class='btn-group'>";
        echo "<a href='?view=view_review&type={$t_key}&id={$row['id']}' class='btn btn-outline' style='padding:6px 10px;font-size:12px' title='View Details'><i class='fas fa-eye'></i></a>";
        
        // INDIVIDUAL CSV DOWNLOAD BUTTON
        echo "<a href='?export_single_csv={$row['id']}&type={$t_key}' class='btn btn-info' style='padding:6px 10px;font-size:12px;color:white;' title='Download CSV Report'><i class='fas fa-file-csv'></i></a>";

        if($is_mgr_view) {
            echo "<a href='?view=certificate&type={$t_key}&id={$row['id']}' target='_blank' class='btn btn-primary' style='padding:6px 10px;font-size:12px' title='Download Certificate'><i class='fas fa-certificate'></i></a>";
        }

        if ($is_admin && $row['total_score'] != -1) { 
            if($ticket_data) {
                $t_status = strtolower($ticket_data['status']);
                $is_closed = ($t_status == 'closed' || $t_status == 'resolved');
                $badge_class = $is_closed ? 'badge-success' : 'badge-warning';
                $icon_class = $is_closed ? 'fa-check-double' : 'fa-check-circle';
                $label_suffix = $is_closed ? ' (Closed)' : '';

                echo "<span class='badge $badge_class' style='padding:8px; font-size:11px;' title='Ticket Status: {$ticket_data['status']}'>
                        <i class='fas $icon_class'></i> Ticket: {$ticket_data['ticket_number']}$label_suffix
                      </span>";
            } else {
                echo "<button class='btn btn-warning ticket-btn' style='padding:6px 10px;font-size:12px;color:white' 
                  data-id='{$row['id']}' 
                  data-type='{$t_key}' 
                  data-emp='".htmlspecialchars($row['employee_name'])."'
                  data-empid='{$row['employee_id']}'
                  data-score='{$row['total_score']}'
                  title='Raise Ticket'><i class='fas fa-ticket-alt'></i></button>";
            }
        }
        echo "</div>";
        echo "</td></tr>";
    }
} else {
    echo "<tr><td colspan='8' style='text-align:center;color:#94a3b8;padding:30px'>No records found matching filters/period.</td></tr>";
}
?>
</tbody>
</table>
</div>
</div>

<?php elseif($view == 'form'): 
$ftype = isset($_GET['type']) ? $_GET['type'] : '';
$config_key = '';
if($ftype == 'daily') $config_key = 'daily_self';
elseif($ftype == 'weekly') $config_key = 'weekly_self';
elseif($ftype == 'monthly') $config_key = 'monthly_self';
elseif($ftype == 'quarterly') $config_key = 'quarterly_self';
elseif($ftype == 'halfyearly') $config_key = 'halfyearly_self';
elseif($ftype == 'yearly') $config_key = 'yearly_self';
elseif($ftype == 'mgr_weekly') $config_key = 'weekly_manager';
elseif($ftype == 'mgr_monthly') $config_key = 'monthly_manager';
elseif($ftype == 'mgr_quarterly') $config_key = 'quarterly_manager';
elseif($ftype == 'mgr_halfyearly') $config_key = 'halfyearly_manager';
elseif($ftype == 'mgr_yearly') $config_key = 'yearly_manager';

$form_review_date = isset($_GET['review_date']) ? $_GET['review_date'] : date('Y-m-d');

$display_period_text = '';
$ts = strtotime($form_review_date);

if(strpos($ftype, 'daily') !== false) {
    $display_period_text = "Date: " . date('l, d F Y', $ts);
} elseif(strpos($ftype, 'weekly') !== false) {
    $w_start = date('d M', strtotime('monday this week', $ts));
    $w_end = date('d M Y', strtotime('sunday this week', $ts));
    $display_period_text = "Week: $w_start to $w_end";
} elseif(strpos($ftype, 'monthly') !== false) {
    $display_period_text = "Month: " . date('F Y', $ts);
} elseif(strpos($ftype, 'quarterly') !== false) {
    $q_num = ceil(date('n', $ts)/3);
    $y_num = date('Y', $ts);
    $q_start = date('d M', strtotime("$y_num-" . (($q_num*3)-2) . "-01"));
    $q_end = date('d M Y', strtotime('last day of ' . "$y_num-" . ($q_num*3) . "-01"));
    $display_period_text = "Quarter $q_num - $y_num ($q_start to $q_end)";
} elseif(strpos($ftype, 'halfyearly') !== false) {
    $h_num = (date('n', $ts) <= 6) ? 1 : 2;
    $y_num = date('Y', $ts);
    $h_start = ($h_num == 1) ? "01 Jan" : "01 Jul";
    $h_end = ($h_num == 1) ? "30 Jun $y_num" : "31 Dec $y_num";
    $display_period_text = "Half-Year $h_num - $y_num ($h_start to $h_end)";
} elseif(strpos($ftype, 'yearly') !== false) {
    $y_num = date('Y', $ts);
    $display_period_text = "Annual Review: 01 Jan $y_num to 31 Dec $y_num";
}

$t_name = isset($_GET['ename']) ? $_GET['ename'] : '';
$t_id = isset($_GET['eid']) ? $_GET['eid'] : '';
$t_dept = isset($_GET['edept']) ? urldecode($_GET['edept']) : '';
$t_pos = isset($_GET['epos']) ? urldecode($_GET['epos']) : '';

// For manager reviews, ALWAYS use target employee's dept/pos
// For self reviews, use current user's dept/pos
if (strpos($config_key, 'manager') !== false) {
    // Manager review - MUST use target employee's department and position
    if ($t_id) {
        // Always fetch from database to ensure accuracy
        $target_lookup = mysqli_query($con, "SELECT department, position FROM hr_employees WHERE employee_id='".mysqli_real_escape_string($con, $t_id)."' LIMIT 1");
        if ($target_lookup && mysqli_num_rows($target_lookup) > 0) {
            $target_data = mysqli_fetch_assoc($target_lookup);
            $review_dept = !empty($target_data['department']) ? $target_data['department'] : 'General';
            $review_pos = !empty($target_data['position']) ? $target_data['position'] : 'General';
        } else {
            // Fallback to URL params if database lookup fails
            $review_dept = $t_dept ? $t_dept : 'General';
            $review_pos = $t_pos ? $t_pos : 'General';
        }
    } else {
        // No employee ID - use URL params or fallback to General
        $review_dept = $t_dept ? $t_dept : 'General';
        $review_pos = $t_pos ? $t_pos : 'General';
    }
} else {
    // Self review - use current user's department and position
    $review_dept = $employee_department;
    $review_pos = $employee_position;
    
    // CRITICAL SAFETY CHECK: If dept/pos are empty, don't default to 'General'
    // This would load ALL General questions from all departments
    if (empty($review_dept)) {
        die("<div style='background:#fee;padding:20px;margin:20px;border:2px solid #c00;border-radius:8px;'>
            <h2 style='color:#c00;'>❌ Error: Department Not Found</h2>
            <p>Your user account does not have a department assigned.</p>
            <p><strong>Current User:</strong> {$employee_name} ({$employee_id})</p>
            <p><strong>Department:</strong> <code>" . var_export($employee_department, true) . "</code></p>
            <p><strong>Position:</strong> <code>" . var_export($employee_position, true) . "</code></p>
            <p>Please contact HR to update your employee record with the correct department and position.</p>
            <p><a href='?view=dashboard'>← Back to Dashboard</a></p>
            </div>");
    }
}

$questions = getQuestionsConfig($con, $config_key, $review_dept, $review_pos);
$random_quote = $motivational_quotes[array_rand($motivational_quotes)];

// DEBUG: Add this temporarily to see what's happening
if (isset($_GET['debug'])) {
    echo "<div style='background:#fff3cd; padding:20px; margin:20px; border:2px solid #ffc107; border-radius:8px;'>";
    echo "<h3 style='color:#856404;'>🔍 DEBUG INFORMATION</h3>";
    echo "<p><strong>Current Logged-in User:</strong> " . htmlspecialchars($employee_name) . " (" . htmlspecialchars($employee_id) . ")</p>";
    echo "<p><strong>User's Department:</strong> " . htmlspecialchars($employee_department) . "</p>";
    echo "<p><strong>User's Position:</strong> " . htmlspecialchars($employee_position) . "</p>";
    echo "<hr>";
    echo "<p><strong>Form Type (ftype):</strong> " . htmlspecialchars($ftype) . "</p>";
    echo "<p><strong>Config Key:</strong> " . htmlspecialchars($config_key) . "</p>";
    echo "<p><strong>Is Manager Review:</strong> " . (strpos($config_key, 'manager') !== false ? 'YES' : 'NO') . "</p>";
    echo "<hr>";
    echo "<p><strong>Target Employee ID (t_id):</strong> " . htmlspecialchars($t_id) . "</p>";
    echo "<p><strong>Target Employee Name (t_name):</strong> " . htmlspecialchars($t_name) . "</p>";
    echo "<p><strong>URL Param edept (t_dept):</strong> " . htmlspecialchars($t_dept) . "</p>";
    echo "<p><strong>URL Param epos (t_pos):</strong> " . htmlspecialchars($t_pos) . "</p>";
    echo "<hr>";
    echo "<p><strong>FINAL Review Department (used for questions):</strong> <span style='background:yellow;padding:2px 8px;'>" . htmlspecialchars($review_dept) . "</span></p>";
    echo "<p><strong>FINAL Review Position (used for questions):</strong> <span style='background:yellow;padding:2px 8px;'>" . htmlspecialchars($review_pos) . "</span></p>";
    echo "<p><strong>Number of Questions Loaded:</strong> <span style='background:yellow;padding:2px 8px;font-size:18px;font-weight:bold;'>" . count($questions) . "</span></p>";
    
    if ($t_id) {
        $db_check = mysqli_query($con, "SELECT department, position FROM hr_employees WHERE employee_id='".mysqli_real_escape_string($con, $t_id)."' LIMIT 1");
        if ($db_check && mysqli_num_rows($db_check) > 0) {
            $db_data = mysqli_fetch_assoc($db_check);
            echo "<p><strong>Database Lookup for Target Employee:</strong></p>";
            echo "<p>  - Database Department: " . htmlspecialchars($db_data['department']) . "</p>";
            echo "<p>  - Database Position: " . htmlspecialchars($db_data['position']) . "</p>";
        }
    }
    
    // Show actual SQL query being used
    $test_dept = mysqli_real_escape_string($con, $review_dept);
    $test_pos = mysqli_real_escape_string($con, $review_pos);
    $mapping = ['daily_self' => ['review_type' => 'daily', 'review_by' => 'self'],
        'weekly_self' => ['review_type' => 'weekly', 'review_by' => 'self'],
        'monthly_self' => ['review_type' => 'monthly', 'review_by' => 'self'],
        'quarterly_self' => ['review_type' => 'quarterly', 'review_by' => 'self'],
        'halfyearly_self' => ['review_type' => 'halfyearly', 'review_by' => 'self'],
        'yearly_self' => ['review_type' => 'yearly', 'review_by' => 'self'],
        'weekly_manager' => ['review_type' => 'weekly', 'review_by' => 'manager'],
        'monthly_manager' => ['review_type' => 'monthly', 'review_by' => 'manager'],
        'quarterly_manager' => ['review_type' => 'quarterly', 'review_by' => 'manager'],
        'halfyearly_manager' => ['review_type' => 'halfyearly', 'review_by' => 'manager'],
        'yearly_manager' => ['review_type' => 'yearly', 'review_by' => 'manager']];
    
    if (isset($mapping[$config_key])) {
        $m = $mapping[$config_key];
        $test_query = "SELECT * FROM performance_questions WHERE department = '$test_dept' AND position = '$test_pos' AND review_type = '{$m['review_type']}' AND review_by = '{$m['review_by']}' AND is_active = 1 ORDER BY question_number ASC";
        echo "<hr>";
        echo "<p><strong>SQL Query Used:</strong></p>";
        echo "<code style='background:#f5f5f5;padding:10px;display:block;margin-top:5px;word-wrap:break-word;'>" . htmlspecialchars($test_query) . "</code>";
        
        $test_result = mysqli_query($con, $test_query);
        echo "<p><strong>Query Result:</strong> " . ($test_result ? mysqli_num_rows($test_result) . " rows returned" : "FAILED - " . mysqli_error($con)) . "</p>";
    }
    
    echo "<hr>";
    echo "<p><strong>Questions Loaded (by number):</strong></p>";
    echo "<table style='width:100%;background:white;border-collapse:collapse;'>";
    echo "<tr style='background:#1e3a8a;color:white;'><th style='padding:8px;text-align:left;'>Q#</th><th style='padding:8px;text-align:left;'>Question Preview</th><th style='padding:8px;text-align:left;'>ID</th><th style='padding:8px;text-align:left;'>Dept</th><th style='padding:8px;text-align:left;'>Pos</th></tr>";
    foreach($questions as $num => $q) {
        echo "<tr style='border-bottom:1px solid #e2e8f0;'>";
        echo "<td style='padding:8px;'><strong>Q" . $num . "</strong></td>";
        echo "<td style='padding:8px;'>" . htmlspecialchars(substr($q['q'], 0, 60)) . "...</td>";
        echo "<td style='padding:8px;'>" . $q['id'] . "</td>";
        echo "<td style='padding:8px;'>" . (isset($q['dept']) ? $q['dept'] : 'N/A') . "</td>";
        echo "<td style='padding:8px;'>" . (isset($q['pos']) ? $q['pos'] : 'N/A') . "</td>";
        echo "</tr>";
    }
    echo "</table>";
    echo "</div>";
}
?>

<div class="card" style="max-width:1000px;margin:0 auto">
<div style="text-align:center;margin-bottom:40px; padding:30px; background:linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); border-radius:10px; color:white;">
<h2 style="font-size:24px;color:white;text-transform:capitalize; margin-bottom:10px; font-weight:700;"><?php echo str_replace('_',' ',$config_key); ?></h2>
<p style="color:#fbbf24; font-weight:700; font-size:18px; margin-bottom:5px;"><?php echo $display_period_text; ?></p>
<?php if($t_name): ?><p style="font-weight:600;color:#e2e8f0;font-size:16px;margin-top:10px;">Evaluating: <?php echo htmlspecialchars(urldecode($t_name)); ?></p><?php endif; ?>
<div style="display:flex; gap:30px; justify-content:center; margin-top:15px; flex-wrap:wrap;">
<p style="color:#cbd5e1; font-size:14px;"><i class="fas fa-building"></i> Dept: <?php echo htmlspecialchars($review_dept); ?></p>
<p style="color:#cbd5e1; font-size:14px;"><i class="fas fa-user-tie"></i> Position: <?php echo htmlspecialchars($review_pos); ?></p>
</div>
</div>

<form method="POST" onsubmit="return confirm('Are you sure you want to submit this review?')">
<input type="hidden" name="form_type" value="<?php echo htmlspecialchars($config_key, ENT_QUOTES, 'UTF-8'); ?>">
<input type="hidden" name="department" value="<?php echo htmlspecialchars($review_dept, ENT_QUOTES, 'UTF-8'); ?>">
<input type="hidden" name="position" value="<?php echo htmlspecialchars($review_pos, ENT_QUOTES, 'UTF-8'); ?>">
<input type="hidden" name="submission_review_date" value="<?php echo htmlspecialchars($form_review_date, ENT_QUOTES, 'UTF-8'); ?>">

<?php if($t_id): ?>
<input type="hidden" name="target_id" value="<?php echo htmlspecialchars($t_id, ENT_QUOTES, 'UTF-8'); ?>">
<input type="hidden" name="target_name" value="<?php echo htmlspecialchars(urldecode($t_name), ENT_QUOTES, 'UTF-8'); ?>">
<?php endif; ?>

<?php if($config_key == 'daily_self'): ?>
<div class="form-group" style="background:#fff7ed; border-color:#fdba74;">
    <div class="custom-control custom-checkbox">
        <input type="checkbox" class="custom-control-input" id="leaveCheck" name="is_leave" value="1">
        <label class="custom-control-label" for="leaveCheck" style="font-weight:700; color:#c2410c; font-size:15px;">
            🏖️ I was on Leave / Holiday today
        </label>
        <div style="font-size:12px; color:#9a3412; margin-top:5px;">Check this box if you were on leave. Questions will be disabled.</div>
    </div>
</div>
<?php endif; ?>

<div id="questionsContainer">
<?php if(empty($questions)): ?>
<div class="card" style="text-align:center; padding:50px; border:2px dashed #cbd5e1; box-shadow:none;">
<i class="fas fa-clipboard-list" style="font-size:48px; color:#94a3b8; margin-bottom:20px;"></i>
<h3 style="color:#1e293b; font-size:18px;">Questions Not Configured</h3>
<p style="color:#64748b; font-size:14px">HR has not added questions for this review type yet.</p>
</div>
<?php else: ?>
<?php foreach($questions as $n => $q): ?>
<div class="form-group question-block">
<label class="form-label"><span style="display:inline-block; background:#1e3a8a; color:white; padding:3px 8px; border-radius:4px; margin-right:10px; font-size:12px;">Q<?php echo $n; ?></span><?php echo htmlspecialchars($q['q']); ?></label>
<?php if($q['t'] == 'select'): ?>
<select name="q<?php echo $n; ?>" class="form-control" required><option value="">-- Select Your Answer --</option><?php foreach($q['o'] as $opt) echo "<option value='$opt'>$opt</option>"; ?></select>
<?php else: ?>
<textarea name="q<?php echo $n; ?>" class="form-control" rows="10" required></textarea>
<?php endif; ?>
<?php if(isset($q['sub'])): ?>
<div class="sub-question"><label style="font-size:13px; font-weight:600; color:#475569;"><i class="fas fa-level-down-alt" style="margin-right:8px; color:#1e3a8a"></i><?php echo htmlspecialchars($q['sub']); ?></label><textarea name="q<?php echo $n; ?>_sub" class="form-control" rows="5"></textarea></div>
<?php endif; ?>
</div>
<?php endforeach; ?>
<?php endif; ?>
</div>

<div style="text-align:center; padding: 20px; margin: 20px 0; border-top: 1px solid #e2e8f0; border-bottom: 1px solid #e2e8f0;">
    <i class="fas fa-quote-left" style="color:#cbd5e1; font-size:20px; margin-right:10px;"></i>
    <span style="font-style: italic; color:#64748b; font-weight:500; font-size:14px;"><?php echo $random_quote; ?></span>
    <i class="fas fa-quote-right" style="color:#cbd5e1; font-size:20px; margin-left:10px;"></i>
</div>

<div style="display:flex;gap:15px;margin-top:40px"><button type="submit" class="btn btn-primary" style="flex:2;justify-content:center;padding:15px; font-size:16px;">Submit Review</button><a href="?view=dashboard" class="btn btn-outline" style="flex:1;justify-content:center; padding:15px;">Cancel</a></div>
</form>
</div>

<?php elseif($view == 'view_review'): 
$review_type = isset($_GET['type']) ? $_GET['type'] : '';
$review_id = isset($_GET['id']) ? intval($_GET['id']) : 0;
$table = ''; $answers_table = '';

if(strpos($review_type, 'manager') !== false) {
    $answers_table = 'performance_answers_manager';
    if($review_type == 'weekly_manager') $table = 'performance_weekly_manager';
    elseif($review_type == 'monthly_manager') $table = 'performance_monthly_manager';
    elseif($review_type == 'quarterly_manager') $table = 'performance_quarterly_manager';
    elseif($review_type == 'halfyearly_manager') $table = 'performance_halfyearly_manager';
    elseif($review_type == 'yearly_manager') $table = 'performance_yearly_manager';
} else {
    $answers_table = 'performance_answers_self';
    if($review_type == 'daily_self') $table = 'performance_daily_self';
    elseif($review_type == 'weekly_self') $table = 'performance_weekly_self';
    elseif($review_type == 'monthly_self') $table = 'performance_monthly_self';
    elseif($review_type == 'quarterly_self') $table = 'performance_quarterly_self';
    elseif($review_type == 'halfyearly_self') $table = 'performance_halfyearly_self';
    elseif($review_type == 'yearly_self') $table = 'performance_yearly_self';
}

$review_query = mysqli_query($con, "SELECT * FROM `$table` WHERE id = $review_id LIMIT 1");
$review = mysqli_fetch_assoc($review_query);

if($review):
    $style = getPerfStyle($review['total_score']);
    
    // PERMANENT FIX: Use CASE statement to prioritize stored question_text
    // This ensures history ALWAYS shows what was asked at submission time
    $answers_query = mysqli_query($con, "
        SELECT a.*, 
               CASE 
                   WHEN a.question_text IS NOT NULL AND TRIM(a.question_text) != ''
                       THEN a.question_text
                   ELSE COALESCE(q.question_text, CONCAT('Question #', a.question_number))
               END as question_text,
               q.input_type as db_input_type,
               q.department as db_dept,
               q.position as db_pos
        FROM `$answers_table` a 
        LEFT JOIN performance_questions q ON a.question_id = q.id
        WHERE a.review_id = $review_id 
        AND a.review_type = '$review_type'
        ORDER BY a.question_number ASC
    ");
    
    $all_answers = [];
    $scorable_question_count = 0;
    
    if($answers_query) {
        while($row = mysqli_fetch_assoc($answers_query)) {
            // Use db_input_type if available, otherwise default to 'text'
            $row['input_type'] = !empty($row['db_input_type']) ? $row['db_input_type'] : 'text';
            
            $all_answers[] = $row;
            
            if($row['input_type'] == 'select') {
                $scorable_question_count++;
            }
        }
    }
    
    // Debug logging
    error_log("view_review: review_id=$review_id, review_type=$review_type, answers_count=" . count($all_answers) . ", scorable_count=$scorable_question_count");
    
    $weight_per_question = ($scorable_question_count > 0) ? (100 / $scorable_question_count) : 0;
?>
<div class="card" style="max-width:1000px;margin:0 auto">

<?php if(isset($_GET['debug'])): ?>
<div style="background:#fff3cd; padding:20px; margin-bottom:20px; border:2px solid #ffc107; border-radius:8px;">
    <h3 style="color:#856404;">🔍 DEBUG INFORMATION - Review Display</h3>
    <p><strong>Review ID:</strong> <?php echo $review_id; ?></p>
    <p><strong>Review Type:</strong> <?php echo htmlspecialchars($review_type); ?></p>
    <p><strong>Answers Table:</strong> <?php echo htmlspecialchars($answers_table); ?></p>
    <p><strong>Master Table:</strong> <?php echo htmlspecialchars($table); ?></p>
    <p><strong>Employee:</strong> <?php echo htmlspecialchars($review['employee_name']); ?> (<?php echo htmlspecialchars($review['employee_id']); ?>)</p>
    <p><strong>Department (from master):</strong> <?php echo htmlspecialchars($review['department'] ?? 'N/A'); ?></p>
    <p><strong>Position (from master):</strong> <?php echo htmlspecialchars($review['position'] ?? 'N/A'); ?></p>
    <p><strong>Total Answers Found:</strong> <?php echo count($all_answers); ?></p>
    <p><strong>Scorable Questions:</strong> <?php echo $scorable_question_count; ?></p>
    <hr>
    <p><strong>SQL Query Used:</strong></p>
    <code style="background:#f5f5f5;padding:10px;display:block;margin-top:5px;word-wrap:break-word;">
        SELECT a.*, a.question_text as stored_question_text, q.question_text as current_question_text, q.input_type as current_input_type, q.department as current_dept, q.position as current_pos, COALESCE(a.question_text, q.question_text, 'Question Not Found') as question_text, COALESCE(q.input_type, 'text') as input_type FROM `<?php echo $answers_table; ?>` a LEFT JOIN performance_questions q ON a.question_id = q.id WHERE a.review_id = <?php echo $review_id; ?> AND a.review_type = '<?php echo $review_type; ?>' ORDER BY a.question_number ASC
    </code>
    <hr>
    <p><strong>Answer Details:</strong></p>
    <table style="width:100%;background:white;border-collapse:collapse;font-size:12px;">
        <tr style="background:#1e3a8a;color:white;">
            <th style="padding:8px;text-align:left;">Q#</th>
            <th style="padding:8px;text-align:left;">Question ID</th>
            <th style="padding:8px;text-align:left;">Displayed Question Text</th>
            <th style="padding:8px;text-align:left;">Source</th>
            <th style="padding:8px;text-align:left;">DB Dept/Pos</th>
        </tr>
        <?php foreach($all_answers as $ans): ?>
        <tr style="border-bottom:1px solid #e2e8f0;">
            <td style="padding:8px;"><?php echo $ans['question_number']; ?></td>
            <td style="padding:8px;"><?php echo $ans['question_id']; ?></td>
            <td style="padding:8px;"><?php echo htmlspecialchars(substr($ans['question_text'], 0, 60)); ?>...</td>
            <td style="padding:8px;">
                <?php 
                // Check if this came from stored text or database
                $from_stored = (!empty($ans['question_text']) && $ans['question_text'] != 'Question Not Found');
                echo $from_stored ? '✅ Stored' : '⚠️ Fallback';
                ?>
            </td>
            <td style="padding:8px;"><?php echo htmlspecialchars(($ans['db_dept'] ?? 'N/A') . ' / ' . ($ans['db_pos'] ?? 'N/A')); ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</div>
<?php endif; ?>

<div style="background:white; border:1px solid #e2e8f0; border-top:5px solid #1e3a8a; padding:30px; border-radius:10px; margin-bottom:30px">
<h2 style="color:#1e3a8a; margin-bottom:15px; font-size:22px"><i class="fas fa-file-alt"></i> Review Details</h2>
<div style="display:flex;gap:30px;flex-wrap:wrap;margin-top:20px">
<div><div style="font-size:12px;color:#64748b;text-transform:uppercase;">Employee</div><div style="font-size:15px;font-weight:700;color:#1e293b"><?php echo htmlspecialchars($review['employee_name']); ?></div></div>
<?php if(isset($review['manager_name'])): ?><div><div style="font-size:12px;color:#64748b;text-transform:uppercase;">Manager</div><div style="font-size:15px;font-weight:700;color:#1e293b"><?php echo htmlspecialchars($review['manager_name']); ?></div></div><?php endif; ?>
<div><div style="font-size:12px;color:#64748b;text-transform:uppercase;">Review Type</div><div style="font-size:15px;font-weight:700;color:#1e293b;text-transform:capitalize"><?php echo str_replace('_', ' ', $review_type); ?></div></div>
<div>
    <div style="font-size:12px;color:#64748b;text-transform:uppercase;">Total Score</div>
    <?php if($review['total_score'] == -1): ?>
        <div style="font-size:24px;font-weight:800;color:#64748b">--</div>
    <?php else: ?>
        <div style="font-size:24px;font-weight:800;color:#1e3a8a"><?php echo $review['total_score'] + 0; ?>%</div>
    <?php endif; ?>
</div>
<div><div style="font-size:12px;color:#64748b;text-transform:uppercase;">Rating</div><div style="font-size:15px;font-weight:700;color:#1e293b"><?php echo $style['icon']; ?> <?php echo $style['r']; ?></div></div>
</div>
</div>
<h3 style="margin-bottom:25px;color:#1e3a8a;font-size:16px"><i class="fas fa-list-ol"></i> Answers</h3>

<?php 
$q_num = 1; 
foreach($all_answers as $answer): 
    $is_text_question = (isset($answer['input_type']) && $answer['input_type'] == 'text');
    $weighted_score_display = 0;
    if(!$is_text_question) {
        $weighted_score_display = ($answer['answer_score'] / 10) * $weight_per_question;
    }
?>
<div style="background:#f8fafc;padding:20px;border-radius:8px;margin-bottom:15px;border:1px solid #e2e8f0;">
<div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:10px">
    <div style="flex:1">
        <div style="font-weight:700;font-size:14px;color:#1e293b;margin-bottom:8px">
            <span style="background:<?php echo $is_text_question ? '#64748b' : '#1e3a8a'; ?>;color:white;padding:3px 8px;border-radius:4px;margin-right:10px;font-size:11px;">Q<?php echo $q_num; ?></span>
            <?php echo htmlspecialchars($answer['question_text']); ?>
        </div>
    </div>
    
    <div style="text-align:right;margin-left:20px; display:flex; flex-direction:column; align-items:flex-end;">
        <?php if($review['total_score'] == -1): ?>
             <div style="background:#e2e8f0; color:#475569; padding:5px 12px; border-radius:15px; font-size:11px; font-weight:700; border:1px solid #cbd5e1;">
                On Leave
            </div>
        <?php elseif($is_text_question): ?>
            <div style="background:#e2e8f0; color:#475569; padding:5px 12px; border-radius:15px; font-size:11px; font-weight:700; border:1px solid #cbd5e1;">
                <i class="fas fa-comment-alt"></i> Non-Scoring
            </div>
        <?php else: ?>
            <div style="font-size:18px;font-weight:800;color:#1e3a8a">
                <?php echo round($weighted_score_display, 2); ?> <span style="font-size:14px; color:#64748b; font-weight:500;">/ <?php echo round($weight_per_question, 2); ?></span>
            </div>
            <div style="font-size:11px; color:#64748b; margin-top:4px;">
                (<?php echo $answer['answer_score']; ?> Points)
            </div>
        <?php endif; ?>
    </div>
</div>
<div style="background:white;padding:20px;border-radius:6px;border:1px solid #e2e8f0;font-size:15px;line-height:1.8;color:#334155;white-space:pre-wrap;min-height:100px"><?php echo htmlspecialchars($answer['answer_text']); ?></div>
<?php if(!empty($answer['sub_answer_text'])): ?>
    <div style="margin-top:10px;background:#fff7ed;padding:15px;border-radius:6px;border-left:3px solid #f59e0b">
        <div style="font-weight:700;color:#92400e;margin-bottom:6px;font-size:13px"><i class="fas fa-comment-dots"></i> Additional Details:</div>
        <div style="font-size:14px;color:#78350f;line-height:1.7;white-space:pre-wrap"><?php echo htmlspecialchars($answer['sub_answer_text']); ?></div>
    </div>
<?php endif; ?>
</div>
<?php $q_num++; endforeach; ?>

<div style="margin-top:30px"><a href="javascript:history.back()" class="btn btn-outline"><i class="fas fa-arrow-left"></i> Back</a></div>
</div>
<?php else: ?>
<div class="card"><div class="alert alert-danger">Review not found!</div><a href="?view=dashboard" class="btn btn-outline">Back</a></div>
<?php endif; ?>

<?php elseif($view == 'certificate'): 
    $rid = intval($_GET['id']);
    $rtype = $_GET['type'];
    $tbl = '';
    if($rtype == 'weekly_manager') $tbl = 'performance_weekly_manager';
    elseif($rtype == 'monthly_manager') $tbl = 'performance_monthly_manager';
    elseif($rtype == 'quarterly_manager') $tbl = 'performance_quarterly_manager';
    elseif($rtype == 'halfyearly_manager') $tbl = 'performance_halfyearly_manager';
    elseif($rtype == 'yearly_manager') $tbl = 'performance_yearly_manager';
    
    if($tbl) {
        $res = mysqli_query($con, "SELECT * FROM `$tbl` WHERE id=$rid");
        if($row = mysqli_fetch_assoc($res)) {
            $emp_id = $row['employee_id'];
            $emp_query = mysqli_query($con, "SELECT company_name FROM hr_employees WHERE employee_id='$emp_id' LIMIT 1");
            $emp_data = mysqli_fetch_assoc($emp_query);
            $company_name = $emp_data['company_name'] ?? 'ABRA Travels - Fleet Management';
            
            $logo_path = '';
            if($company_name) {
                $logo_query = mysqli_query($con, "SELECT logo_path FROM hr_companies WHERE company_name='$company_name' LIMIT 1");
                if($logo_row = mysqli_fetch_assoc($logo_query)) {
                    $logo_path = $logo_row['logo_path'];
                }
            }
            
            $cert_style = getPerfStyle($row['total_score']);
            $theme_color = $cert_style['c'];
            $bg_gradient = "linear-gradient(135deg, #ffffff 0%, ". $cert_style['bg'] ." 100%)";
            
            // DYNAMIC TITLE & CONTENT LOGIC
            $cert_title = "PERFORMANCE ACHIEVEMENT";
            $achievement_text = "has successfully achieved an evaluation status of";
            
            if($row['total_score'] < 70) {
                $cert_title = "PERFORMANCE EVALUATION REPORT";
                $achievement_text = "has completed the scheduled performance assessment with a status of";
            }
            
            $rating_text = strtoupper($cert_style['r']);

            $period = '';
            $period_label = 'ASSESSMENT PERIOD';
            if(isset($row['week_start_date'])) {
                $period = date('d M Y', strtotime($row['week_start_date'])) . " - " . date('d M Y', strtotime($row['week_start_date'] . ' +6 days'));
                $period_label = 'WEEKLY EVALUATION';
            } elseif(isset($row['review_month'])) {
                $period = date('F Y', strtotime($row['review_month']));
                $period_label = 'MONTHLY EVALUATION';
            } elseif(isset($row['review_quarter'])) {
                $period = "Quarter " . $row['review_quarter'];
                $period_label = 'QUARTERLY EVALUATION';
            } elseif(isset($row['review_year'])) {
                $period = "Year " . $row['review_year'];
                $period_label = 'ANNUAL EVALUATION';
            }
?>
<style>
@import url('https://fonts.googleapis.com/css2?family=Cinzel:wght@400;700&family=Cormorant+Garamond:wght@400;600;700&family=Libre+Baskerville:wght@400;700&display=swap');

#certificate-view {
    background: <?php echo $bg_gradient; ?>;
    padding: 50px 20px;
    min-height: 100vh;
}

.cert-page {
    max-width: 1100px;
    margin: 0 auto;
    background: white;
    padding: 45px;
    box-shadow: 0 20px 60px rgba(0,0,0,0.1);
    border: 15px solid <?php echo $theme_color; ?>;
    position: relative;
}

.cert-inner-border {
    border: 5px double #e2e8f0;
    padding: 35px;
}

.cert-header { text-align: center; margin-bottom: 28px; }
.cert-company { font-family: 'Cinzel', serif; font-size: 26px; font-weight: 700; color: #1e293b; }
.cert-title { font-family: 'Libre Baskerville', serif; font-size: 44px; color: <?php echo $theme_color; ?>; margin: 12px 0; text-transform: uppercase; }
.cert-name { font-family: 'Cinzel', serif; font-size: 52px; font-weight: 700; color: #1e293b; border-bottom: 3px solid #e2e8f0; display: inline-block; padding: 0 30px; margin: 20px 0; }
.cert-message { font-family: 'Cormorant Garamond', serif; font-size: 22px; color: #334155; line-height: 1.6; max-width: 800px; margin: 0 auto; }
.cert-score-box { background: <?php echo $theme_color; ?>; color: white; padding: 25px; border-radius: 50%; width: 150px; height: 150px; display: flex; flex-direction: column; justify-content: center; align-items: center; margin: 30px auto; }

.cert-signatures { display: flex; justify-content: space-between; margin-top: 60px; }
.signature-block { text-align: center; border-top: 2px solid #e2e8f0; width: 250px; padding-top: 15px; font-family: 'Cinzel', serif; position: relative; }
/* BEAUTIFUL DIGITAL SIGNATURE FONT - FIXED STRAIGHT */
.signature-text { 
    font-family: 'Dancing Script', cursive; 
    font-size: 36px; 
    color: #1e3a8a; 
    position: absolute; 
    bottom: 30px; 
    width: 100%; 
    text-align: center;
    /* Rotation removed for clean straight look */
}

@media print {
    body * { visibility: hidden; }
    #certificate-view, #certificate-view * { visibility: visible; }
    #certificate-view {
        position: absolute;
        left: 0;
        top: 0;
        width: 100%;
        margin: 0;
        padding: 0;
        background: white !important;
        z-index: 99999;
    }
    .cert-page {
        box-shadow: none !important;
        border: none !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
    }
    .no-print { display: none !important; }
}
</style>

<div id="certificate-view">
    <div class="cert-page" id="cert-content">
        <div class="cert-inner-border">
            <div class="cert-header">
                <?php if(!empty($logo_path) && file_exists($logo_path)): ?>
                    <!-- INCREASED LOGO SIZE -->
                    <img src="<?php echo htmlspecialchars($logo_path); ?>" alt="Logo" style="max-height: 160px; margin-bottom: 15px;">
                <?php endif; ?>
                <div class="cert-company"><?php echo strtoupper(htmlspecialchars($company_name)); ?></div>
                <div class="cert-title"><?php echo $cert_title; ?></div>
            </div>
            
            <div style="text-align: center;">
                <p class="cert-message">This is to certify that</p>
                <div class="cert-name"><?php echo strtoupper(htmlspecialchars($row['employee_name'])); ?></div>
                <p class="cert-message"><?php echo $achievement_text; ?> <strong><?php echo $rating_text; ?></strong> with a performance score of:</p>
                
                <div class="cert-score-box">
                    <span style="font-size: 48px; font-weight: 700;"><?php echo $row['total_score']; ?></span>
                    <span style="font-size: 14px;">PERCENT</span>
                </div>
                
                <p class="cert-message" style="margin-top: 20px; font-family: 'Poppins', sans-serif; font-size: 16px; font-weight: 400; color: #475569;">
                    <?php echo $period_label; ?>: <?php echo $period; ?>
                </p>
            </div>
            
            <div class="cert-signatures">
                <div class="signature-block">
                    <!-- CLEAN SIGNATURE LOOK: SCRIPT FONT NAME + TITLE BELOW -->
                    <div class="signature-text">Abishek Veeraswamy</div>
                    <div style="font-size: 12px; margin-top: 5px;">Managing Director</div>
                </div>
                <div class="signature-block">
                    <div class="signature-text">Keerti Patil</div>
                    <div style="font-size: 12px; margin-top: 5px;">HR Manager</div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="text-center no-print" style="margin: 30px;">
        <!-- NEW DOWNLOAD IMAGE BUTTON -->
        <button id="btn-download-img" class="btn btn-success btn-lg"><i class="fas fa-file-image"></i> Download Image</button>
        
        <a href="?view=dashboard" class="btn btn-outline btn-lg"><i class="fas fa-arrow-left"></i> Back</a>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // 1. IMAGE DOWNLOAD LOGIC
    document.getElementById('btn-download-img').addEventListener('click', function() {
        var element = document.getElementById('cert-content');
        var btn = this;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Generating...';
        
        html2canvas(element, {
            scale: 2, // High resolution
            useCORS: true,
            backgroundColor: '#ffffff'
        }).then(canvas => {
            var link = document.createElement('a');
            link.download = 'Certificate_<?php echo $row['employee_id']; ?>.jpg';
            link.href = canvas.toDataURL('image/jpeg', 0.9);
            link.click();
            btn.innerHTML = '<i class="fas fa-file-image"></i> Download Image';
        });
    });
});
</script>

<?php 
        } else echo "<div class='alert alert-danger'>Review not found.</div>";
    } else echo "<div class='alert alert-danger'>Invalid certificate type.</div>";
?>
<?php endif; ?>
</div>

<div class="modal fade" id="ticketModal" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header" style="background:#1e3a8a;color:white;">
                <h5 class="modal-title" style="font-weight:700;"><i class="fas fa-ticket-alt"></i> Raise Performance Ticket</h5>
                <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
            </div>
            <div class="modal-body" style="padding:25px;">
                <div id="ticketWarning" class="alert alert-warning" style="display:none; font-size: 14px;">
                    <i class="fas fa-exclamation-triangle"></i> <span id="ticketWarningMsg"></span>
                </div>
                <div class="form-group" style="padding: 15px; border-left: 5px solid #1e3a8a; margin-bottom: 20px;">
                    <label style="font-size: 12px; color: #64748b; font-weight: bold;">TARGET EMPLOYEE</label>
                    <div id="modalTargetEmp" style="font-weight: 700; font-size: 16px;"></div>
                    <label style="font-size: 12px; color: #64748b; font-weight: bold; margin-top: 10px;">REVIEW TYPE</label>
                    <div id="modalReviewType" style="font-weight: 700; font-size: 16px;"></div>
                    <label style="font-size: 12px; color: #64748b; font-weight: bold; margin-top: 10px;">SCORE</label>
                    <div id="modalScore" style="font-weight: 700; font-size: 16px;"></div>
                </div>
                <div class="alert alert-info" style="font-size: 13px; background:#eff6ff; color:#1e3a8a; border:1px solid #bfdbfe;">
                    <i class="fas fa-info-circle"></i> This ticket will be automatically assigned to: 
                    <strong id="autoAssigneeName"></strong>
                </div>
                <div class="form-group" style="padding: 0; background: none; border: none; box-shadow: none;">
                    <label style="font-weight: 700;">Additional Notes <span class="text-danger">*</span></label>
                    <textarea id="ticketNotes" class="form-control" style="min-height: 100px;" placeholder="Describe why you are escalating this review..."></textarea>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-outline" data-dismiss="modal">Cancel</button>
                <button type="button" id="submitTicketBtn" class="btn btn-primary"><i class="fas fa-paper-plane"></i> Raise Ticket</button>
            </div>
        </div>
    </div>
</div>

<!-- DATE PICKER MODAL FOR BACKDATED SUBMISSIONS -->
<div class="modal fade" id="datePickerModal" tabindex="-1">
    <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content" style="border:none; box-shadow:0 10px 40px rgba(0,0,0,0.2);">
            <div class="modal-header" style="background:#1e3a8a; color:white; border-bottom:none;">
                <h5 class="modal-title" style="font-weight:700;"><i class="fas fa-calendar-alt"></i> <span id="modalTitle">Select Review Date</span></h5>
                <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
            </div>
            <div class="modal-body" style="padding:30px;">
                <div style="margin-bottom:20px;">
                    <p style="color:#64748b; font-size:14px; margin-bottom:15px;">
                        <i class="fas fa-info-circle"></i> <span id="modalDescription">You can submit reviews for previous dates.</span>
                    </p>
                    
                    <!-- Single Date Picker (for Daily) -->
                    <div id="singleDatePicker" style="display:none;">
                        <label style="font-weight:700; color:#1e3a8a; margin-bottom:10px;">Review Date:</label>
                        <input type="date" id="backdatedReviewDate" class="form-control" style="font-size:16px; padding:12px;" max="<?php echo date('Y-m-d'); ?>">
                    </div>
                    
                    <!-- Date Range Picker (for Weekly/Monthly) -->
                    <div id="dateRangePicker" style="display:none;">
                        <div style="margin-bottom:15px;">
                            <label style="font-weight:700; color:#1e3a8a; margin-bottom:10px;">Start Date:</label>
                            <input type="date" id="startDate" class="form-control" style="font-size:16px; padding:12px;" max="<?php echo date('Y-m-d'); ?>">
                        </div>
                        <div>
                            <label style="font-weight:700; color:#1e3a8a; margin-bottom:10px;">End Date:</label>
                            <input type="date" id="endDate" class="form-control" style="font-size:16px; padding:12px;" max="<?php echo date('Y-m-d'); ?>">
                        </div>
                    </div>
                </div>
                <div id="datePickerInfo" style="padding:15px; background:#eff6ff; border-radius:8px; border-left:4px solid #2563eb; margin-bottom:20px; display:none;">
                    <div style="font-size:13px; color:#1e40af; font-weight:600;">
                        <i class="fas fa-calendar-week"></i> <span id="datePickerInfoText"></span>
                    </div>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-outline" data-dismiss="modal">Cancel</button>
                <button type="button" id="submitDatePicker" class="btn btn-primary"><i class="fas fa-arrow-right"></i> Continue to Review</button>
            </div>
        </div>
    </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/popper.js@1.16.1/dist/umd/popper.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
$(document).ready(function() {
    $('.select2').select2({ width: '100%', placeholder: "Select an option", allowClear: true });
    setTimeout(function() { $('.alert').fadeOut('slow'); }, 5000);
    
    $('#leaveCheck').change(function() {
        if($(this).is(':checked')) {
            $('#questionsContainer').slideUp();
            $('.question-block input, .question-block select, .question-block textarea').prop('required', false);
        } else {
            $('#questionsContainer').slideDown();
            $('.question-block select, .question-block textarea:not([name*="_sub"])').prop('required', true);
        }
    });
    if($('#leaveCheck').is(':checked')) { $('#leaveCheck').trigger('change'); }

    var currentTicketData = {};
    $('.ticket-btn').click(function() {
        var btn = $(this);
        currentTicketData = { id: btn.data('id'), type: btn.data('type'), emp: btn.data('emp'), empid: btn.data('empid'), score: btn.data('score') };
        $('#modalTargetEmp').text(currentTicketData.emp);
        $('#modalReviewType').text(currentTicketData.type.replace(/_/g, ' ').toUpperCase());
        $('#modalScore').text(currentTicketData.score + ' / 100');
        $('#autoAssigneeName').text(currentTicketData.emp);
        $('#ticketNotes').val('');
        $('#ticketWarning').hide();
        
        $.ajax({
            url: window.location.href, type: 'GET', dataType: 'json',
            data: { ajax_check_ticket: true, review_id: currentTicketData.id, review_type: currentTicketData.type },
            success: function(response) {
                if(response.exists) {
                    var msg = "A ticket (#" + response.ticket_number + ") for this review was already raised to " + response.assigned_name + ". You can create another if needed.";
                    $('#ticketWarningMsg').text(msg); $('#ticketWarning').show();
                }
            }
        });
        $('#ticketModal').modal('show');
    });

    $('#submitTicketBtn').click(function() {
        var notes = $('#ticketNotes').val().trim();
        if(!notes) { alert('Please provide some notes explaining the ticket.'); return; }
        var btn = $(this); btn.prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Processing...');
        
        $.ajax({
            url: window.location.href, type: 'POST', dataType: 'json',
            data: {
                ajax_create_ticket: true, review_id: currentTicketData.id, review_type: currentTicketData.type,
                target_employee_name: currentTicketData.emp, target_employee_id: currentTicketData.empid,
                score: currentTicketData.score, notes: notes
            },
            success: function(response) {
                if(response.success) { alert(response.message); $('#ticketModal').modal('hide'); location.reload(); } 
                else { alert('Error: ' + response.message); }
                btn.prop('disabled', false).html('<i class="fas fa-paper-plane"></i> Raise Ticket');
            },
            error: function() { alert('System error occurred.'); btn.prop('disabled', false).html('<i class="fas fa-paper-plane"></i> Raise Ticket'); }
        });
    });

    /**
     * CHART EXPORT LOGIC
     */
    $('#btnDownloadChart').click(function() {
        var element = document.getElementById('admin-dashboard-stats');
        if(element) {
            window.scrollTo(0, 0);
            html2canvas(element, {
                scale: 2,
                useCORS: true,
                backgroundColor: '#ffffff'
            }).then(canvas => {
                var link = document.createElement('a');
                link.download = 'Performance_Dashboard_Report_' + new Date().toISOString().slice(0,10) + '.png';
                link.href = canvas.toDataURL('image/png');
                link.click();
            }).catch(err => {
                console.error("Screenshot failed:", err);
                alert("Could not generate image. Please ensure all assets are loaded.");
            });
        }
    });
    
    // DATE PICKER MODAL FUNCTIONALITY
    var currentReviewType = '';
    
    $('.open-date-picker').click(function() {
        currentReviewType = $(this).data('type');
        $('#datePickerInfo').hide();
        
        // Show appropriate picker based on review type
        if(currentReviewType === 'daily') {
            $('#modalTitle').text('Select Daily Review Date');
            $('#modalDescription').text('Select the date you want to submit the daily review for:');
            $('#singleDatePicker').show();
            $('#dateRangePicker').hide();
            $('#backdatedReviewDate').val('<?php echo date('Y-m-d'); ?>');
        } else if(currentReviewType === 'weekly') {
            $('#modalTitle').text('Select Weekly Review Period');
            $('#modalDescription').text('Select the start and end date for the week (Monday to Sunday):');
            $('#singleDatePicker').hide();
            $('#dateRangePicker').show();
            // Set default to current week
            var today = new Date();
            var dayOfWeek = today.getDay();
            var diff = today.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
            var monday = new Date(today.setDate(diff));
            var sunday = new Date(monday);
            sunday.setDate(monday.getDate() + 6);
            $('#startDate').val(monday.toISOString().split('T')[0]);
            $('#endDate').val(sunday.toISOString().split('T')[0]);
        } else if(currentReviewType === 'monthly') {
            $('#modalTitle').text('Select Monthly Review Period');
            $('#modalDescription').text('Select the start and end date for the month:');
            $('#singleDatePicker').hide();
            $('#dateRangePicker').show();
            // Set default to current month
            var today = new Date();
            var firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
            var lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
            $('#startDate').val(firstDay.toISOString().split('T')[0]);
            $('#endDate').val(lastDay.toISOString().split('T')[0]);
        } else {
            $('#modalTitle').text('Select Review Date');
            $('#modalDescription').text('Select the date you want to submit the review for:');
            $('#singleDatePicker').show();
            $('#dateRangePicker').hide();
            $('#backdatedReviewDate').val('<?php echo date('Y-m-d'); ?>');
        }
        
        $('#datePickerModal').modal('show');
    });
    
    // Handle single date change
    $('#backdatedReviewDate').change(function() {
        var selectedDate = $(this).val();
        if(selectedDate) {
            var date = new Date(selectedDate);
            var formattedDate = date.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
            $('#datePickerInfoText').html('Date: ' + formattedDate);
            $('#datePickerInfo').show();
        }
    });
    
    // Handle date range change
    $('#startDate, #endDate').change(function() {
        var startDate = $('#startDate').val();
        var endDate = $('#endDate').val();
        
        if(startDate && endDate) {
            var start = new Date(startDate);
            var end = new Date(endDate);
            
            // Validate that end date is after start date
            if(end < start) {
                alert('End date must be after start date');
                return;
            }
            
            var dateRange = start.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) + ' - ' + 
                           end.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
            
            if(currentReviewType === 'weekly') {
                // Validate it's Monday to Sunday
                if(start.getDay() !== 1) {
                    $('#datePickerInfoText').html('<span style="color:#b91c1c;">⚠️ Start date should be a Monday</span>');
                } else if(end.getDay() !== 0) {
                    $('#datePickerInfoText').html('<span style="color:#b91c1c;">⚠️ End date should be a Sunday</span>');
                } else {
                    $('#datePickerInfoText').html('Week: ' + dateRange);
                }
            } else if(currentReviewType === 'monthly') {
                $('#datePickerInfoText').html('Month: ' + dateRange);
            }
            $('#datePickerInfo').show();
        }
    });
    
    $('#submitDatePicker').click(function() {
        var selectedDate = '';
        
        if(currentReviewType === 'daily' || currentReviewType === 'quarterly' || currentReviewType === 'halfyearly' || currentReviewType === 'yearly') {
            selectedDate = $('#backdatedReviewDate').val();
            if(!selectedDate) {
                alert('Please select a date');
                return;
            }
        } else if(currentReviewType === 'weekly' || currentReviewType === 'monthly') {
            var startDate = $('#startDate').val();
            var endDate = $('#endDate').val();
            
            if(!startDate || !endDate) {
                alert('Please select both start and end dates');
                return;
            }
            
            // For weekly, validate Monday to Sunday
            if(currentReviewType === 'weekly') {
                var start = new Date(startDate);
                var end = new Date(endDate);
                if(start.getDay() !== 1) {
                    alert('Start date must be a Monday');
                    return;
                }
                if(end.getDay() !== 0) {
                    alert('End date must be a Sunday');
                    return;
                }
            }
            
            // Use start date as the review_date parameter
            selectedDate = startDate;
        }
        
        window.location.href = '?view=form&type=' + currentReviewType + '&review_date=' + selectedDate;
    });
    
    // MANAGER REVIEW DATE PICKER FUNCTIONALITY
    var currentMgrReviewType = '';
    var currentEmployeeId = '';
    var currentEmployeeName = '';
    var currentEmployeeDept = '';
    var currentEmployeePos = '';
    
    $('.open-mgr-date-picker').click(function() {
        currentMgrReviewType = $(this).data('type');
        currentEmployeeId = $(this).data('eid');
        currentEmployeeName = $(this).data('ename');
        currentEmployeeDept = $(this).data('edept');
        currentEmployeePos = $(this).data('epos');
        
        $('#datePickerInfo').hide();
        
        // Show appropriate picker based on review type
        if(currentMgrReviewType === 'mgr_weekly') {
            $('#modalTitle').text('Select Weekly Review Period for ' + currentEmployeeName);
            $('#modalDescription').text('Select the start and end date for the week (Monday to Sunday):');
            $('#singleDatePicker').hide();
            $('#dateRangePicker').show();
            // Set default to current week
            var today = new Date();
            var dayOfWeek = today.getDay();
            var diff = today.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
            var monday = new Date(today.setDate(diff));
            var sunday = new Date(monday);
            sunday.setDate(monday.getDate() + 6);
            $('#startDate').val(monday.toISOString().split('T')[0]);
            $('#endDate').val(sunday.toISOString().split('T')[0]);
        } else if(currentMgrReviewType === 'mgr_monthly') {
            $('#modalTitle').text('Select Monthly Review Period for ' + currentEmployeeName);
            $('#modalDescription').text('Select the start and end date for the month:');
            $('#singleDatePicker').hide();
            $('#dateRangePicker').show();
            // Set default to current month
            var today = new Date();
            var firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
            var lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
            $('#startDate').val(firstDay.toISOString().split('T')[0]);
            $('#endDate').val(lastDay.toISOString().split('T')[0]);
        } else {
            $('#modalTitle').text('Select Review Date for ' + currentEmployeeName);
            $('#modalDescription').text('Select the date you want to submit the review for:');
            $('#singleDatePicker').show();
            $('#dateRangePicker').hide();
            $('#backdatedReviewDate').val('<?php echo date('Y-m-d'); ?>');
        }
        
        $('#datePickerModal').modal('show');
    });
    
    // Update the submit button to handle manager reviews
    $('#submitDatePicker').off('click').click(function() {
        var selectedDate = '';
        var reviewType = currentMgrReviewType || currentReviewType;
        
        if(reviewType === 'daily' || reviewType === 'quarterly' || reviewType === 'halfyearly' || reviewType === 'yearly' || 
           reviewType === 'mgr_quarterly' || reviewType === 'mgr_halfyearly' || reviewType === 'mgr_yearly') {
            selectedDate = $('#backdatedReviewDate').val();
            if(!selectedDate) {
                alert('Please select a date');
                return;
            }
        } else if(reviewType === 'weekly' || reviewType === 'monthly' || reviewType === 'mgr_weekly' || reviewType === 'mgr_monthly') {
            var startDate = $('#startDate').val();
            var endDate = $('#endDate').val();
            
            if(!startDate || !endDate) {
                alert('Please select both start and end dates');
                return;
            }
            
            selectedDate = startDate;
        }
        
        // Build URL based on whether it's a manager review or self review
        if(currentMgrReviewType) {
            window.location.href = '?view=form&type=' + currentMgrReviewType + 
                                   '&eid=' + encodeURIComponent(currentEmployeeId) + 
                                   '&ename=' + encodeURIComponent(currentEmployeeName) + 
                                   '&edept=' + encodeURIComponent(currentEmployeeDept) + 
                                   '&epos=' + encodeURIComponent(currentEmployeePos) + 
                                   '&review_date=' + selectedDate;
        } else {
            window.location.href = '?view=form&type=' + reviewType + '&review_date=' + selectedDate;
        }
    });
});
</script
</body>
</html>
