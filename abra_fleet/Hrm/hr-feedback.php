<?php 
session_start();
// Turn off error reporting for production
error_reporting(E_ERROR | E_WARNING | E_PARSE);
require_once('database.php');
require_once('library.php');
require_once('funciones.php');

isUser();

$current_page = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// Get email
$currentUserEmail = '';
if(!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($dbConn, $currentUserName);
    $email_query = mysqli_query($dbConn, "SELECT email FROM hr_employees WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) AND status = 'active' LIMIT 1");
    
    if($email_query && mysqli_num_rows($email_query) > 0) {
        $email_data = mysqli_fetch_assoc($email_query);
        $currentUserEmail = $email_data['email'];
    } else {
        $cust_query = mysqli_query($dbConn, "SELECT email FROM tbl_clients WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name_safe')) AND estado = 1 LIMIT 1");
        if($cust_query && mysqli_num_rows($cust_query) > 0) {
            $cust_data = mysqli_fetch_assoc($cust_query);
            $currentUserEmail = $cust_data['email'];
        }
    }
}

if(empty($currentUserEmail)) {
    $currentUserEmail = $currentUserName;
}

// ============================================================================
// ROLE DETECTION - DEPARTMENT-BASED
// ============================================================================

// Get current user's employee data for department-based permissions
$employee_id = '';
$employee_name = '';
$employee_department = '';
$employee_position = '';

if (!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($dbConn, $currentUserName);
    $res = mysqli_query($dbConn, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$name_safe%') AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    }
}

// Check if user is in admin departments (Management or Human Resources)
$is_management_dept = (stripos($employee_department, 'Management') !== false);
$is_hr_dept = (stripos($employee_department, 'Human Resources') !== false || 
               stripos($employee_department, 'Human Resources Department') !== false);

// Check if user is Managing Director
$is_managing_director = (stripos($employee_position, 'managing director') !== false || 
                         stripos($employee_position, 'md') !== false ||
                         stripos($employee_position, 'ceo') !== false);

// Legacy name-based checks (kept for backward compatibility)
// SUPER ADMIN - Abishek
$is_super_admin = false;
$super_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
foreach($super_admin_names as $admin_name) {
    if(stripos($currentUserName, $admin_name) !== false || stripos($admin_name, $currentUserName) !== false ||
       stripos($employee_name, $admin_name) !== false) {
        $is_super_admin = true;
        break;
    }
}

// HR ADMIN - Keerti
$is_keerti = false;
$keerti_names = array('Keerti Patil', 'Keerti', 'keerti', 'Keerthi Patil', 'Keerthi', 'keerthi');
foreach($keerti_names as $keerti_name) {
    if(stripos($currentUserName, $keerti_name) !== false || stripos($keerti_name, $currentUserName) !== false ||
       stripos($employee_name, $keerti_name) !== false) {
        $is_keerti = true;
        break;
    }
}

// General ADMIN Flag - Department-based OR position-based OR legacy names
$is_admin = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_super_admin || $is_keerti);

// User type detection
$user_type = null;
$user_full_name = '';
$user_identifier = '';

$emp_check_query = "SELECT name, email FROM hr_employees 
                    WHERE LOWER(TRIM(email)) = LOWER(TRIM('$currentUserEmail')) 
                    AND status = 'active' 
                    LIMIT 1";
$emp_check = mysqli_query($dbConn, $emp_check_query);

if($emp_check && mysqli_num_rows($emp_check) > 0) {
    $emp_data = mysqli_fetch_assoc($emp_check);
    $user_type = 'employee';
    $user_full_name = $emp_data['name'];
    $user_identifier = $emp_data['email'];
} else {
    $cust_check_query = "SELECT name, email FROM tbl_clients 
                         WHERE LOWER(TRIM(email)) = LOWER(TRIM('$currentUserEmail')) 
                         AND estado = 1 
                         LIMIT 1";
    $cust_check = mysqli_query($dbConn, $cust_check_query);
    
    if($cust_check && mysqli_num_rows($cust_check) > 0) {
        $cust_data = mysqli_fetch_assoc($cust_check);
        $user_type = 'customer';
        $user_full_name = $cust_data['name'];
        $user_identifier = $cust_data['email'];
    }
}

// FIX: Fallback if DB lookup fails but user is logged in (Handles the "Specific Employee" issue)
// If the employee is not found in DB by email, we assume they are an employee using their session name
if (empty($user_type) && !empty($currentUserName)) {
    $user_type = 'employee'; 
    $user_full_name = $currentUserName;
    $user_identifier = $currentUserEmail; 
}

// Automated response function
function getAutomatedResponse($feedback_type, $employee_name) {
    $responses = array(
        'suggestion' => "Dear " . $employee_name . ",\n\nThank you for taking the time to share your valuable suggestion with us! 💡\n\nWe truly appreciate your input and innovative thinking. Your suggestion has been received and will be carefully reviewed by our team.\n\nWe believe that employee suggestions play a crucial role in our continuous improvement. Our team will analyze your suggestion and get back to you with feedback or implementation plans as soon as possible.\n\nThank you for helping us grow and improve!\n\nBest regards,\nThe Management Team",
        'complaint' => "Dear " . $employee_name . ",\n\nWe have received your complaint and we sincerely apologize for any inconvenience or concern you've experienced. ⚠️\n\nYour feedback is extremely important to us, and we take all complaints very seriously. Our team is already reviewing your concern and will investigate the matter thoroughly.\n\nWe are committed to resolving this issue promptly and will reach out to you with updates and solutions as soon as possible.\n\nYour patience and understanding are greatly appreciated. If you need immediate assistance, please don't hesitate to reach out to management directly.\n\nThank you for bringing this to our attention.\n\nBest regards,\nThe Management Team",
        'appreciation' => "Dear " . $employee_name . ",\n\nThank you so much for your kind words and appreciation! 🎉\n\nIt's wonderful to hear positive feedback, and we're thrilled that you took the time to share your experience. Your acknowledgment means a lot to us and motivates our entire team to continue delivering excellence.\n\nWe truly appreciate employees like you who recognize and celebrate good work. Your positive energy contributes to our wonderful workplace culture.\n\nThank you once again for your heartwarming message!\n\nWarm regards,\nThe Management Team",
        'general' => "Dear " . $employee_name . ",\n\nThank you for your feedback! 📝\n\nWe have received your message and our team will review it carefully. Your input is valuable to us and helps us understand your perspective better.\n\nWe will get back to you with a response as soon as possible. If your feedback requires any specific action, rest assured that we will address it appropriately.\n\nThank you for taking the time to share your thoughts with us.\n\nBest regards,\nThe Management Team"
    );
    return isset($responses[$feedback_type]) ? $responses[$feedback_type] : $responses['general'];
}

$error_message = '';
$success_message = '';

// Handle employee feedback submission
if(isset($_POST['submit_employee_feedback'])) {
    $employee_email = $user_identifier;
    $employee_name = $user_full_name;
    if($is_keerti && isset($_POST['employee_name'])) {
        $employee_name = $_POST['employee_name'];
    }
    
    $feedback_type = mysqli_real_escape_string($dbConn, $_POST['feedback_type']);
    
    // FIX FOR 500 ERROR: Truncate Subject to 250 characters
    $raw_subject = trim($_POST['subject']);
    $short_subject = mb_substr($raw_subject, 0, 250, 'UTF-8'); 
    $subject = mysqli_real_escape_string($dbConn, $short_subject);
    
    $message = mysqli_real_escape_string($dbConn, trim($_POST['message']));
    $rating = intval($_POST['rating']);
    
    if(!$is_keerti && ($user_type !== 'employee' || empty($employee_email))) {
        $error_message = "Error: You must be logged in as an employee to submit feedback.";
    } else {
        $employee_email_safe = mysqli_real_escape_string($dbConn, $employee_email);
        $employee_name_safe = mysqli_real_escape_string($dbConn, $employee_name);
        
        $check_dup = mysqli_query($dbConn, 
            "SELECT id FROM employee_feedback 
             WHERE employee_email = '$employee_email_safe' 
             AND subject = '$subject' 
             AND date_submitted > DATE_SUB(NOW(), INTERVAL 1 MINUTE)");
        
        if(mysqli_num_rows($check_dup) == 0) {
            $sql = "INSERT INTO employee_feedback 
                    (employee_email, employee_name, feedback_type, subject, message, rating, date_submitted, parent_feedback_id) 
                    VALUES 
                    ('$employee_email_safe', '$employee_name_safe', '$feedback_type', '$subject', '$message', $rating, NOW(), 0)";
            
            if(mysqli_query($dbConn, $sql)) {
                $feedback_id = mysqli_insert_id($dbConn);
                
                $auto_response = getAutomatedResponse($feedback_type, $employee_name);
                $auto_response_escaped = mysqli_real_escape_string($dbConn, $auto_response);
                
                $auto_reply_sql = "INSERT INTO employee_feedback 
                                  (employee_email, employee_name, feedback_type, subject, message, rating, date_submitted, parent_feedback_id) 
                                  VALUES 
                                  ('admin@system', 'Automated Response', 'general', 'Auto-Reply', '$auto_response_escaped', 5, DATE_ADD(NOW(), INTERVAL 2 SECOND), $feedback_id)";
                mysqli_query($dbConn, $auto_reply_sql);
                
                header("Location: " . $_SERVER['PHP_SELF'] . "?success=1");
                exit();
            } else {
                $error_message = "Error submitting feedback: " . mysqli_error($dbConn);
            }
        } else {
            $error_message = "You have already submitted similar feedback recently.";
        }
    }
}

// Handle customer feedback submission
if(isset($_POST['submit_customer_feedback'])) {
    $customer_email = $user_identifier;
    $customer_name = $user_full_name;
    $feedback_type = mysqli_real_escape_string($dbConn, $_POST['feedback_type']);
    
    // FIX FOR 500 ERROR: Truncate Subject
    $raw_subject = trim($_POST['subject']);
    $short_subject = mb_substr($raw_subject, 0, 250, 'UTF-8');
    $subject = mysqli_real_escape_string($dbConn, $short_subject);
    
    $message = mysqli_real_escape_string($dbConn, trim($_POST['message']));
    $rating = intval($_POST['rating']);
    
    if($user_type !== 'customer' || empty($customer_email)) {
        $error_message = "Error: You must be logged in as a customer to submit feedback.";
    } else {
        $customer_email_safe = mysqli_real_escape_string($dbConn, $customer_email);
        $customer_name_safe = mysqli_real_escape_string($dbConn, $customer_name);
        
        $check_dup = mysqli_query($dbConn, 
            "SELECT id FROM customer_feedback 
             WHERE customer_email = '$customer_email_safe' 
             AND subject = '$subject' 
             AND date_submitted > DATE_SUB(NOW(), INTERVAL 1 MINUTE)");
        
        if(mysqli_num_rows($check_dup) == 0) {
            $sql = "INSERT INTO customer_feedback 
                    (customer_email, customer_name, feedback_type, subject, message, rating, date_submitted, parent_feedback_id) 
                    VALUES 
                    ('$customer_email_safe', '$customer_name_safe', '$feedback_type', '$subject', '$message', $rating, NOW(), 0)";
            
            if(mysqli_query($dbConn, $sql)) {
                $feedback_id = mysqli_insert_id($dbConn);
                
                $auto_response = getAutomatedResponse($feedback_type, $customer_name);
                $auto_response_escaped = mysqli_real_escape_string($dbConn, $auto_response);
                
                $auto_reply_sql = "INSERT INTO customer_feedback 
                                  (customer_email, customer_name, feedback_type, subject, message, rating, date_submitted, parent_feedback_id) 
                                  VALUES 
                                  ('admin@system', 'Automated Response', 'general', 'Auto-Reply', '$auto_response_escaped', 5, DATE_ADD(NOW(), INTERVAL 2 SECOND), $feedback_id)";
                mysqli_query($dbConn, $auto_reply_sql);
                
                header("Location: " . $_SERVER['PHP_SELF'] . "?success=1");
                exit();
            } else {
                $error_message = "Error submitting feedback: " . mysqli_error($dbConn);
            }
        } else {
            $error_message = "You have already submitted similar feedback recently.";
        }
    }
}

if(isset($_GET['success']) && $_GET['success'] == '1') {
    $success_message = "Thank you! Your feedback has been submitted successfully.";
}

// AJAX: Get conversation
if(isset($_GET['ajax_get_conversation'])) {
    header('Content-Type: application/json');
    $feedback_id = mysqli_real_escape_string($dbConn, $_GET['feedback_id']);
    $feedback_source = mysqli_real_escape_string($dbConn, $_GET['feedback_source']);
    
    $table = ($feedback_source === 'employee') ? 'employee_feedback' : 'customer_feedback';
    $name_field = ($feedback_source === 'employee') ? 'employee_name' : 'customer_name';
    $email_field = ($feedback_source === 'employee') ? 'employee_email' : 'customer_email';
    
    $clicked_query = "SELECT * FROM $table WHERE id = '$feedback_id' LIMIT 1";
    $clicked_result = mysqli_query($dbConn, $clicked_query);
    $clicked_row = mysqli_fetch_assoc($clicked_result);
    
    if(!$clicked_row) {
        echo json_encode(['success' => false, 'message' => 'Feedback not found']);
        exit;
    }
    
    $thread_id = ($clicked_row['parent_feedback_id'] > 0) ? $clicked_row['parent_feedback_id'] : $clicked_row['id'];
    
    $thread_query = "SELECT * FROM $table 
                     WHERE (id = '$thread_id') 
                     OR (parent_feedback_id = '$thread_id' AND parent_feedback_id > 0)
                     ORDER BY date_submitted ASC, id ASC";
    
    $thread_result = mysqli_query($dbConn, $thread_query);
    
    $all_messages = array();
    $original_subject = '';
    
    while($row = mysqli_fetch_assoc($thread_result)) {
        if($row['parent_feedback_id'] == 0 || $row['parent_feedback_id'] == '' || $row['id'] == $thread_id) {
            if(!empty($row['subject']) && empty($original_subject)) {
                $original_subject = $row['subject'];
            }
        }
        
        $is_admin_message = (
            $row[$email_field] === 'admin@system' || 
            $row[$name_field] === 'System Admin' ||
            $row[$name_field] === 'Automated Response'
        );
        
        $all_messages[] = array(
            'id' => $row['id'],
            'sender' => $row[$name_field],
            'sender_email' => $row[$email_field],
            'message' => $row['message'],
            'subject' => ($row['id'] == $thread_id) ? $row['subject'] : '',
            'rating' => ($row['id'] == $thread_id && !$is_admin_message) ? $row['rating'] : 0,
            'date' => $row['date_submitted'],
            'is_admin' => $is_admin_message,
            'type' => $is_admin_message ? 'admin' : 'user',
            'sort_timestamp' => strtotime($row['date_submitted'])
        );
    }
    
    echo json_encode([
        'success' => true, 
        'conversation' => $all_messages, 
        'subject' => $original_subject,
        'total_messages' => count($all_messages),
        'thread_id' => $thread_id,
        'feedback_source' => $feedback_source
    ]);
    exit;
}

// AJAX: Check for existing tickets
if(isset($_GET['ajax_check_ticket_history'])) {
    header('Content-Type: application/json');
    $name = mysqli_real_escape_string($dbConn, $_GET['name']);
    $subject_raw = trim($_GET['subject']);
    $expected_subject = mysqli_real_escape_string($dbConn, "[Feedback Portal] " . $subject_raw);
    
    $check_sql = "SELECT t.assigned_to, e.name as emp_name, t.status, t.ticket_number 
                  FROM tickets t 
                  LEFT JOIN hr_employees e ON t.assigned_to = e.id 
                  WHERE t.name = '$name' AND t.subject = '$expected_subject' 
                  AND t.status NOT IN ('Deleted', 'Cancelled', 'Rejected', 'Spam')
                  LIMIT 1";
                  
    $result = mysqli_query($dbConn, $check_sql);
    
    if($result && mysqli_num_rows($result) > 0) {
        $row = mysqli_fetch_assoc($result);
        echo json_encode([
            'exists' => true, 
            'assigned_name' => $row['emp_name'] ? $row['emp_name'] : 'Unknown Employee',
            'status' => $row['status'],
            'ticket_number' => $row['ticket_number']
        ]);
    } else {
        echo json_encode(['exists' => false]);
    }
    exit;
}

// AJAX: Assign ticket
if(isset($_POST['ajax_assign_ticket']) && $is_admin) {
    header('Content-Type: application/json');
    $feedback_id = mysqli_real_escape_string($dbConn, $_POST['feedback_id']);
    $feedback_source = mysqli_real_escape_string($dbConn, $_POST['feedback_source']);
    $assigned_to = mysqli_real_escape_string($dbConn, $_POST['assigned_to']);
    
    $table = ($feedback_source === 'employee') ? 'employee_feedback' : 'customer_feedback';
    $name_field = ($feedback_source === 'employee') ? 'employee_name' : 'customer_name';
    
    $feedback_query = "SELECT * FROM $table WHERE id = '$feedback_id' LIMIT 1";
    $feedback_result = mysqli_query($dbConn, $feedback_query);
    
    if($feedback_result && mysqli_num_rows($feedback_result) > 0) {
        $feedback = mysqli_fetch_assoc($feedback_result);
        $ticket_number = 'FB-' . date('Ymd') . '-' . rand(1000, 9999);
        $name = mysqli_real_escape_string($dbConn, $feedback[$name_field]);
        $subject = mysqli_real_escape_string($dbConn, "[Feedback Portal] " . $feedback['subject']);
        $message_body = "🌟 FEEDBACK ESCALATION TICKET\n" .
                        "==================================================\n" .
                        "📌 ORIGINAL SUBJECT\n" . $feedback['subject'] . "\n\n" .
                        "📝 MESSAGE CONTENT\n" . $feedback['message'] . "\n";
        $message = mysqli_real_escape_string($dbConn, $message_body);
        
        $priority = 'medium';
        if (strtolower($feedback['feedback_type']) === 'complaint') $priority = 'high';
        
        $sql = "INSERT INTO tickets 
                (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at) 
                VALUES 
                ('$ticket_number', '$name', '$subject', '$message', 'Open', '$priority', '$assigned_to', NOW(), NOW())";
        
        if(mysqli_query($dbConn, $sql)) {
            $ticket_id = mysqli_insert_id($dbConn);
            echo json_encode(['success' => true, 'message' => "Ticket #{$ticket_id} created successfully!", 'ticket_id' => $ticket_id]);
        } else {
            echo json_encode(['success' => false, 'message' => 'Failed to create ticket: ' . mysqli_error($dbConn)]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'Feedback not found']);
    }
    exit;
}

// AJAX: Send reply
if(isset($_POST['ajax_send_reply'])) {
    header('Content-Type: application/json');
    $thread_id = mysqli_real_escape_string($dbConn, $_POST['thread_id']);
    $reply_message = mysqli_real_escape_string($dbConn, trim($_POST['reply_message']));
    $feedback_source = mysqli_real_escape_string($dbConn, $_POST['feedback_source']);
    
    if(empty($reply_message)) {
        echo json_encode(['success' => false, 'message' => 'Message cannot be empty']);
        exit;
    }
    
    $table = ($feedback_source === 'employee') ? 'employee_feedback' : 'customer_feedback';
    $name_field = ($feedback_source === 'employee') ? 'employee_name' : 'customer_name';
    $email_field = ($feedback_source === 'employee') ? 'employee_email' : 'customer_email';
    
    if($is_admin) {
        $sender_email = 'admin@system';
        $sender_name = 'System Admin';
    } else {
        $sender_email = $currentUserEmail;
        $sender_name = $currentUserName;
    }
    
    $sql = "INSERT INTO $table ($email_field, $name_field, feedback_type, subject, message, rating, date_submitted, parent_feedback_id) 
            VALUES ('$sender_email', '$sender_name', 'general', 'Reply', '$reply_message', 5, NOW(), '$thread_id')";
    
    if(mysqli_query($dbConn, $sql)) {
        echo json_encode(['success' => true, 'message' => 'Reply sent successfully!']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Database error: ' . mysqli_error($dbConn)]);
    }
    exit;
}

// Get employees list for Ticket Assign
$employees_list = array();
if($is_admin) {
    $emp_list_query = mysqli_query($dbConn, "SELECT id, name FROM hr_employees WHERE status = 'active' ORDER BY name ASC");
    while($emp_row = mysqli_fetch_assoc($emp_list_query)) {
        $employees_list[] = $emp_row;
    }
}

// Admin view - Fetch all feedback
if($is_admin) {
    // 1. GATHER FILTER INPUTS
    $source_filter = isset($_GET['source']) ? $_GET['source'] : 'all';
    $name_filter = isset($_GET['name_filter']) ? $_GET['name_filter'] : '';
    $type_filter = isset($_GET['type']) ? $_GET['type'] : 'all';
    $date_from = isset($_GET['date_from']) ? $_GET['date_from'] : '';
    $date_to = isset($_GET['date_to']) ? $_GET['date_to'] : '';
    $search = isset($_GET['search']) ? $_GET['search'] : '';

    // 2. CONSTRUCT BASE SQL CONDITIONS
    // Employee Base Condition
    $emp_conditions = array();
    $emp_conditions[] = "(employee_feedback.parent_feedback_id = 0 OR employee_feedback.parent_feedback_id IS NULL)";
    $emp_conditions[] = "employee_feedback.employee_email != 'admin@system'";
    
    // Customer Base Condition
    $cust_conditions = array();
    $cust_conditions[] = "(customer_feedback.parent_feedback_id = 0 OR customer_feedback.parent_feedback_id IS NULL)";
    $cust_conditions[] = "customer_feedback.customer_email != 'admin@system'";

    // Apply Dates
    if(!empty($date_from)) {
        $safe_date_from = mysqli_real_escape_string($dbConn, $date_from);
        $emp_conditions[] = "DATE(employee_feedback.date_submitted) >= '$safe_date_from'";
        $cust_conditions[] = "DATE(customer_feedback.date_submitted) >= '$safe_date_from'";
    }
    if(!empty($date_to)) {
        $safe_date_to = mysqli_real_escape_string($dbConn, $date_to);
        $emp_conditions[] = "DATE(employee_feedback.date_submitted) <= '$safe_date_to'";
        $cust_conditions[] = "DATE(customer_feedback.date_submitted) <= '$safe_date_to'";
    }

    // Apply Type Filter
    if($type_filter !== 'all') {
        $safe_type = mysqli_real_escape_string($dbConn, $type_filter);
        $emp_conditions[] = "employee_feedback.feedback_type = '$safe_type'";
        $cust_conditions[] = "customer_feedback.feedback_type = '$safe_type'";
    }

    // Apply Name Filter
    if(!empty($name_filter)) {
        $safe_name = mysqli_real_escape_string($dbConn, $name_filter);
        $emp_conditions[] = "employee_feedback.employee_name = '$safe_name'";
        $cust_conditions[] = "customer_feedback.customer_name = '$safe_name'";
    }

    // Apply Search
    if(!empty($search)) {
        $safe_search = mysqli_real_escape_string($dbConn, $search);
        $emp_conditions[] = "(employee_feedback.employee_name LIKE '%$safe_search%' OR employee_feedback.subject LIKE '%$safe_search%' OR employee_feedback.message LIKE '%$safe_search%')";
        $cust_conditions[] = "(customer_feedback.customer_name LIKE '%$safe_search%' OR customer_feedback.subject LIKE '%$safe_search%' OR customer_feedback.message LIKE '%$safe_search%')";
    }

    $emp_where_sql = implode(' AND ', $emp_conditions);
    $cust_where_sql = implode(' AND ', $cust_conditions);

    // 3. STATISTICS FOR GRAPHS (USING FILTERS)
    // Initialize counters to 0
    $emp_suggestion_count = 0; $emp_complaint_count = 0; $emp_appreciation_count = 0; $emp_general_count = 0;
    $cust_suggestion_count = 0; $cust_complaint_count = 0; $cust_appreciation_count = 0; $cust_general_count = 0;
    $total_employee = 0; $total_customer = 0;

    // Calculate Employee Statistics ONLY if source is all or employee
    if($source_filter === 'all' || $source_filter === 'employee') {
        $emp_suggestion_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM employee_feedback WHERE $emp_where_sql AND feedback_type = 'suggestion'"));
        $emp_complaint_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM employee_feedback WHERE $emp_where_sql AND feedback_type = 'complaint'"));
        $emp_appreciation_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM employee_feedback WHERE $emp_where_sql AND feedback_type = 'appreciation'"));
        $emp_general_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM employee_feedback WHERE $emp_where_sql AND feedback_type = 'general'"));
        $total_employee = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM employee_feedback WHERE $emp_where_sql"));
    }

    // Calculate Customer Statistics ONLY if source is all or customer
    if($source_filter === 'all' || $source_filter === 'customer') {
        $cust_suggestion_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM customer_feedback WHERE $cust_where_sql AND feedback_type = 'suggestion'"));
        $cust_complaint_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM customer_feedback WHERE $cust_where_sql AND feedback_type = 'complaint'"));
        $cust_appreciation_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM customer_feedback WHERE $cust_where_sql AND feedback_type = 'appreciation'"));
        $cust_general_count = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM customer_feedback WHERE $cust_where_sql AND feedback_type = 'general'"));
        $total_customer = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM customer_feedback WHERE $cust_where_sql"));
    }

    $overall_suggestion = $emp_suggestion_count + $cust_suggestion_count;
    $overall_complaint = $emp_complaint_count + $cust_complaint_count;
    $overall_appreciation = $emp_appreciation_count + $cust_appreciation_count;
    $overall_general = $emp_general_count + $cust_general_count;

    // 4. FETCH DATA FOR TABLE
    $records_per_page = 15;
    $page = isset($_GET['page']) && is_numeric($_GET['page']) ? (int)$_GET['page'] : 1;
    $offset = ($page - 1) * $records_per_page;
    
    $employee_names = array();
    $emp_names_query = mysqli_query($dbConn, "SELECT DISTINCT name FROM hr_employees WHERE status = 'active' ORDER BY name ASC");
    while($row = mysqli_fetch_array($emp_names_query)) { if(!empty($row['name'])) $employee_names[] = $row['name']; }
    
    $customer_names = array();
    $cust_names_query = mysqli_query($dbConn, "SELECT DISTINCT name FROM tbl_clients WHERE estado = 1 ORDER BY name ASC");
    while($row = mysqli_fetch_array($cust_names_query)) { if(!empty($row['name'])) $customer_names[] = $row['name']; }
    
    $raw_feedback = array();
    
    // Fetch Table Data (UPDATED WITH JOIN TO TICKETS & EXCLUDING DELETED)
    if($source_filter === 'all' || $source_filter === 'employee') {
        // We join based on the naming convention used in ajax_assign_ticket
        $emp_query = "SELECT employee_feedback.*, 
                             employee_feedback.employee_name as submitter_name, 
                             employee_feedback.employee_email as submitter_email, 
                             'employee' as source,
                             tickets.ticket_number,
                             tickets.status as ticket_status,
                             hr_employees.name as assigned_employee
                      FROM employee_feedback 
                      LEFT JOIN tickets ON tickets.subject = CONCAT('[Feedback Portal] ', employee_feedback.subject) 
                                        AND tickets.name = employee_feedback.employee_name
                                        AND tickets.status NOT IN ('Deleted', 'Cancelled', 'Rejected', 'Spam')
                      LEFT JOIN hr_employees ON tickets.assigned_to = hr_employees.id
                      WHERE $emp_where_sql 
                      ORDER BY employee_feedback.date_submitted DESC";
                      
        $emp_result = mysqli_query($dbConn, $emp_query);
        while($row = mysqli_fetch_assoc($emp_result)) { $raw_feedback[] = $row; }
    }
    
    if($source_filter === 'all' || $source_filter === 'customer') {
        $cust_query = "SELECT customer_feedback.*, 
                              customer_feedback.customer_name as submitter_name, 
                              customer_feedback.customer_email as submitter_email, 
                              'customer' as source,
                              tickets.ticket_number,
                              tickets.status as ticket_status,
                              hr_employees.name as assigned_employee
                       FROM customer_feedback 
                       LEFT JOIN tickets ON tickets.subject = CONCAT('[Feedback Portal] ', customer_feedback.subject) 
                                         AND tickets.name = customer_feedback.customer_name
                                         AND tickets.status NOT IN ('Deleted', 'Cancelled', 'Rejected', 'Spam')
                       LEFT JOIN hr_employees ON tickets.assigned_to = hr_employees.id
                       WHERE $cust_where_sql 
                       ORDER BY customer_feedback.date_submitted DESC";
                       
        $cust_result = mysqli_query($dbConn, $cust_query);
        while($row = mysqli_fetch_assoc($cust_result)) { $raw_feedback[] = $row; }
    }
    
    usort($raw_feedback, function($a, $b) { return strtotime($b['date_submitted']) - strtotime($a['date_submitted']); });
    
    foreach($raw_feedback as &$feedback_item) {
        $check_table = ($feedback_item['source'] === 'employee') ? 'employee_feedback' : 'customer_feedback';
        $check_replies_query = "SELECT COUNT(*) as reply_count FROM $check_table WHERE parent_feedback_id = " . $feedback_item['id'] . " AND parent_feedback_id > 0";
        $check_result = mysqli_query($dbConn, $check_replies_query);
        $check_data = mysqli_fetch_assoc($check_result);
        $feedback_item['has_conversation'] = ($check_data['reply_count'] > 0 || !empty($feedback_item['admin_response']));
    }
    
    $total_records = count($raw_feedback);
    $total_pages = ceil($total_records / $records_per_page);
    $paginated_feedback = array_slice($raw_feedback, $offset, $records_per_page);
}

// Keerti's Personal History
$keerti_personal_feedback = array();
$keerti_total_count = 0; $keerti_responded_count = 0; $keerti_pending_count = 0;

if($is_keerti && !empty($user_identifier)) {
    // FIX: Search by Email OR Name to ensure history shows even if email mismatches
    $safeEmail = mysqli_real_escape_string($dbConn, $user_identifier);
    $safeName = mysqli_real_escape_string($dbConn, $currentUserName);
    
    $k_where = array(
        "(employee_email = '$safeEmail' OR employee_name = '$safeName')",
        "(parent_feedback_id = 0 OR parent_feedback_id IS NULL)", 
        "employee_email != 'admin@system'"
    );
    
    if(isset($_GET['my_date_from']) && !empty($_GET['my_date_from'])) { $k_where[] = "DATE(date_submitted) >= '".mysqli_real_escape_string($dbConn, $_GET['my_date_from'])."'"; }
    if(isset($_GET['my_date_to']) && !empty($_GET['my_date_to'])) { $k_where[] = "DATE(date_submitted) <= '".mysqli_real_escape_string($dbConn, $_GET['my_date_to'])."'"; }
    
    $k_where_sql = implode(' AND ', $k_where);
    $keerti_feedback_query = "SELECT *, 'employee' as source FROM employee_feedback WHERE $k_where_sql ORDER BY date_submitted DESC";
    $keerti_feedback_result = mysqli_query($dbConn, $keerti_feedback_query);
    
    if($keerti_feedback_result) {
        while($row = mysqli_fetch_assoc($keerti_feedback_result)) {
            $check_replies_query = "SELECT COUNT(*) as reply_count FROM employee_feedback WHERE parent_feedback_id = " . $row['id'] . " AND parent_feedback_id > 0";
            $check_result = mysqli_query($dbConn, $check_replies_query);
            $check_data = mysqli_fetch_assoc($check_result);
            $row['has_conversation'] = ($check_data['reply_count'] > 0 || !empty($row['admin_response']));
            
            $keerti_total_count++;
            if($row['has_conversation']) $keerti_responded_count++; else $keerti_pending_count++;
            $keerti_personal_feedback[] = $row;
        }
    }
}

// Regular User History
if(!$is_admin && !empty($user_identifier)) {
    // FIX: Search by Email OR Name to ensure history shows even if email mismatches
    $safeEmail = mysqli_real_escape_string($dbConn, $user_identifier);
    $safeName = mysqli_real_escape_string($dbConn, $user_full_name);
    
    $reg_where = array();
    // Add logic to check both name and email for robustness
    if($user_type === 'customer') {
        $reg_where[] = "(customer_email = '$safeEmail' OR customer_name = '$safeName')";
        $reg_where[] = "customer_email != 'admin@system'";
    } else {
        $reg_where[] = "(employee_email = '$safeEmail' OR employee_name = '$safeName')";
        $reg_where[] = "employee_email != 'admin@system'";
    }
    
    $reg_where[] = "(parent_feedback_id = 0 OR parent_feedback_id IS NULL)";
    
    if(isset($_GET['my_date_from']) && !empty($_GET['my_date_from'])) { $reg_where[] = "DATE(date_submitted) >= '".mysqli_real_escape_string($dbConn, $_GET['my_date_from'])."'"; }
    if(isset($_GET['my_date_to']) && !empty($_GET['my_date_to'])) { $reg_where[] = "DATE(date_submitted) <= '".mysqli_real_escape_string($dbConn, $_GET['my_date_to'])."'"; }
    
    $reg_where_sql = implode(' AND ', $reg_where);
    $my_feedback_query = ($user_type === 'customer') ? "SELECT *, 'customer' as source FROM customer_feedback WHERE $reg_where_sql ORDER BY date_submitted DESC" : "SELECT *, 'employee' as source FROM employee_feedback WHERE $reg_where_sql ORDER BY date_submitted DESC";
    $my_feedback_result = mysqli_query($dbConn, $my_feedback_query);
    
    $total_feedback_count = 0; $responded_count = 0; $pending_count = 0; $my_feedback_array = array();
    
    if($my_feedback_result) {
        while($row = mysqli_fetch_assoc($my_feedback_result)) {
            $table = $row['source'] === 'employee' ? 'employee_feedback' : 'customer_feedback';
            $check_replies_query = "SELECT COUNT(*) as reply_count FROM $table WHERE parent_feedback_id = " . $row['id'] . " AND parent_feedback_id > 0";
            $check_result = mysqli_query($dbConn, $check_replies_query);
            $check_data = mysqli_fetch_assoc($check_result);
            $row['has_conversation'] = ($check_data['reply_count'] > 0 || !empty($row['admin_response']));
            
            $total_feedback_count++;
            if($row['has_conversation']) $responded_count++; else $pending_count++;
            $my_feedback_array[] = $row;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Feedback Management | <?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'CRM'; ?></title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  
  <link rel="shortcut icon" type="image/png" href="img/favicon.png"/>
  
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/css/select2.min.css" />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet">
  
  <style>
    :root {
        --primary: #6366f1;
        --primary-dark: #4f46e5;
        --primary-light: #818cf8;
        --secondary: #8b5cf6;
        --success: #10b981;
        --warning: #f59e0b;
        --danger: #ef4444;
        --info: #3b82f6;
        --bg-gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        --bg-light: #f8fafc;
        --card-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        --card-shadow-hover: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
        --whatsapp-bg: #e5ddd5;
        --whatsapp-user: #dcf8c6;
        --whatsapp-admin: #ffffff;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
        background: var(--bg-light);
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
        color: #0f172a;
        font-size: 14px;
        line-height: 1.6;
        padding-top: 70px;
    }

    body::before {
        content: '';
        position: fixed;
        top: 0; left: 0; right: 0;
        height: 350px;
        background: var(--bg-gradient);
        z-index: -1;
        opacity: 0.05;
    }

    .top-header {
        position: fixed;
        top: 0; left: 0; right: 0;
        height: 70px;
        background: var(--bg-gradient);
        box-shadow: 0 10px 40px rgba(0,0,0,0.15);
        z-index: 1000;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 32px;
    }

    .header-brand {
        display: flex;
        align-items: center;
        gap: 16px;
        color: white;
    }

    .brand-icon {
        width: 48px;
        height: 48px;
        background: rgba(255,255,255,0.25);
        border-radius: 14px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 22px;
        backdrop-filter: blur(10px);
        border: 2px solid rgba(255,255,255,0.4);
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    }

    .brand-text h1 {
        margin: 0;
        font-size: 20px;
        font-weight: 900;
        color: white;
        line-height: 1.1;
        letter-spacing: -0.5px;
    }

    .brand-text p {
        margin: 3px 0 0 0;
        font-size: 11px;
        color: rgba(255,255,255,0.9);
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 1px;
    }

    .header-actions {
        display: flex;
        gap: 10px;
        align-items: center;
    }

    .btn-header {
        padding: 11px 22px;
        border-radius: 12px;
        font-weight: 700;
        font-size: 13px;
        text-decoration: none;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        display: inline-flex;
        align-items: center;
        gap: 8px;
        border: none;
        cursor: pointer;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        background: rgba(255,255,255,0.2);
        color: white;
        border: 2px solid rgba(255,255,255,0.4);
        box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    
    .btn-header:hover {
        background: white;
        color: var(--primary);
        transform: translateY(-3px);
        box-shadow: 0 12px 30px rgba(0,0,0,0.2);
        text-decoration: none;
    }

    .btn-header.submit-btn {
        background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        border-color: #f59e0b;
        box-shadow: 0 4px 14px rgba(245, 158, 11, 0.4);
    }
    
    .btn-header.submit-btn:hover {
        background: linear-gradient(135deg, #d97706 0%, #b45309 100%);
        color: white;
        border-color: #d97706;
        transform: translateY(-3px);
        box-shadow: 0 12px 30px rgba(245, 158, 11, 0.5);
    }

    .main-wrap {
        max-width: 1600px;
        margin: 0 auto;
        padding: 28px 32px 100px 32px;
    }

    .alert-modern {
        border-radius: 16px;
        border: none;
        padding: 18px 24px;
        margin-bottom: 24px;
        font-weight: 600;
        display: flex;
        align-items: center;
        gap: 14px;
        box-shadow: var(--card-shadow);
        animation: slideDown 0.5s cubic-bezier(0.4, 0, 0.2, 1);
    }

    @keyframes slideDown {
        from { opacity: 0; transform: translateY(-30px); }
        to { opacity: 1; transform: translateY(0); }
    }

    .alert-modern.success {
        background: linear-gradient(135deg, #d1fae5 0%, #a7f3d0 100%);
        color: #065f46;
        border-left: 5px solid var(--success);
    }

    .alert-modern.error {
        background: linear-gradient(135deg, #fee2e2 0%, #fecaca 100%);
        color: #991b1b;
        border-left: 5px solid var(--danger);
    }

    .alert-close {
        margin-left: auto;
        background: rgba(0,0,0,0.08);
        border: none;
        width: 32px;
        height: 32px;
        border-radius: 10px;
        cursor: pointer;
        font-size: 18px;
        transition: all 0.3s;
    }
    
    .alert-close:hover {
        background: rgba(0,0,0,0.15);
        transform: rotate(90deg);
    }

    .stats-row {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 20px;
        margin-bottom: 32px;
    }

    .stat-box {
        background: white;
        border-radius: 20px;
        padding: 26px;
        display: flex;
        align-items: center;
        gap: 18px;
        border: 1px solid #e2e8f0;
        transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
        box-shadow: var(--card-shadow);
        position: relative;
        overflow: hidden;
    }
    
    .stat-box::before {
        content: '';
        position: absolute;
        top: 0;
        right: 0;
        width: 100px;
        height: 100px;
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.1), rgba(139, 92, 246, 0.1));
        border-radius: 0 20px 0 100%;
    }
    
    .stat-box:hover { 
        transform: translateY(-8px); 
        box-shadow: var(--card-shadow-hover); 
        border-color: var(--primary);
    }

    .stat-icon-wrap {
        width: 68px; 
        height: 68px; 
        border-radius: 18px; 
        display: flex; 
        align-items: center; 
        justify-content: center; 
        font-size: 30px; 
        color: white;
        box-shadow: 0 8px 20px rgba(0,0,0,0.15);
        position: relative;
        z-index: 1;
    }
    
    .stat-icon-wrap.blue { 
        background: linear-gradient(135deg, #6366f1 0%, #4f46e5 100%); 
    }
    
    .stat-icon-wrap.green { 
        background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    }
    
    .stat-icon-wrap.orange {
        background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
    }

    .stat-content {
        position: relative;
        z-index: 1;
    }
    
    .stat-content h3 { 
        margin: 0 0 6px 0; 
        font-size: 36px; 
        font-weight: 900; 
        color: #0f172a; 
        line-height: 1;
    }
    
    .stat-content p { 
        margin: 0; 
        font-size: 12px; 
        font-weight: 700; 
        color: #64748b; 
        text-transform: uppercase; 
        letter-spacing: 0.8px; 
    }

    .charts-row-top {
        margin-bottom: 32px;
    }
    
    .charts-row-bottom {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(450px, 1fr));
        gap: 24px;
        margin-bottom: 32px;
    }

    .chart-card {
        background: white;
        border-radius: 20px;
        padding: 28px;
        border: 1px solid #e2e8f0;
        box-shadow: var(--card-shadow);
        transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
        height: 100%;
    }

    .chart-card:hover {
        transform: translateY(-5px);
        box-shadow: var(--card-shadow-hover);
    }

    .chart-card h4 {
        color: #0f172a;
        font-weight: 800;
        font-size: 18px;
        margin-bottom: 20px;
        padding-bottom: 12px;
        border-bottom: 2px solid #e2e8f0;
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .chart-container {
        position: relative;
        height: 300px;
        display: flex;
        align-items: center;
        justify-content: center;
    }

    .filter-section {
        background: white;
        border-radius: 18px;
        padding: 22px 26px;
        margin-bottom: 26px;
        border: 1px solid #e2e8f0;
        box-shadow: var(--card-shadow);
    }
    
    .filter-grid { 
        display: grid; 
        grid-template-columns: 2fr 1fr 1fr 1fr 1fr 1fr auto; 
        gap: 12px; 
        align-items: center; 
    }

    .personal-filter-grid {
        display: grid;
        grid-template-columns: 1fr 1fr auto;
        gap: 12px;
        align-items: center;
        max-width: 600px;
    }
    
    .search-box { position: relative; }
    
    .search-box input { 
        width: 100%; 
        height: 50px; 
        padding: 0 18px 0 50px; 
        border: 2px solid #e2e8f0; 
        border-radius: 14px; 
        font-size: 14px; 
        font-weight: 500; 
        outline: none; 
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); 
        background: white;
    }
    
    .search-box input:focus { 
        border-color: var(--primary); 
        box-shadow: 0 0 0 4px rgba(99, 102, 241, 0.1);
    }
    
    .search-box i { 
        position: absolute; 
        left: 18px; 
        top: 17px; 
        color: #94a3b8; 
        font-size: 17px; 
    }

    .btn-filter {
        height: 50px; 
        padding: 0 22px; 
        border: 2px solid #e2e8f0; 
        border-radius: 14px; 
        background: white; 
        color: #475569;
        font-weight: 700; 
        font-size: 13px; 
        cursor: pointer; 
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); 
        text-transform: uppercase;
        white-space: nowrap;
    }
    
    .btn-filter:hover { 
        background: var(--bg-gradient); 
        color: white; 
        border-color: var(--primary);
        transform: translateY(-2px);
        box-shadow: 0 8px 20px rgba(99, 102, 241, 0.3);
    }

    .select2-container--default .select2-selection--single {
        height: 48px !important;
        border: 2px solid #e2e8f0 !important;
        border-radius: 13px !important;
        padding: 0 10px !important;
        display: flex !important;
        align-items: center !important;
        background-color: #fff !important;
        transition: all 0.3s !important;
    }
    
    .select2-container--default.select2-container--open .select2-selection--single {
        border-color: var(--primary) !important;
        box-shadow: 0 0 0 4px rgba(99, 102, 241, 0.1) !important;
    }

    .select2-container--default .select2-selection--single .select2-selection__rendered {
        color: #475569 !important;
        font-weight: 600 !important;
        font-size: 13px !important;
        line-height: 46px !important;
    }

    .feedback-table-wrap {
        background: white;
        border-radius: 18px;
        border: 1px solid #e2e8f0;
        overflow: hidden;
        box-shadow: var(--card-shadow);
        margin-bottom: 32px;
    }

    .feedback-table {
        width: 100%;
        border-collapse: collapse;
    }

    .feedback-table thead {
        background: var(--bg-gradient);
    }

    .feedback-table th {
        padding: 20px 18px;
        text-align: left;
        font-size: 14px;
        font-weight: 800;
        color: white;
        text-transform: uppercase;
        letter-spacing: 1px;
        border-right: 1px solid rgba(255, 255, 255, 0.2);
        white-space: nowrap;
    }

    .feedback-table th:last-child {
        border-right: none;
        text-align: center;
    }

    .feedback-table tbody tr {
        border-bottom: 1px solid #f1f5f9;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }

    .feedback-table tbody tr:hover {
        background: linear-gradient(90deg, #f8fafc 0%, #f1f5f9 100%);
        box-shadow: 0 4px 12px rgba(99, 102, 241, 0.1);
    }

    /* TICKET STATUS ROW STYLES */
    .ticket-row-open {
        background-color: #fff9c4 !important; /* Light Yellow */
    }
    
    .ticket-row-open:hover {
        background-color: #fff59d !important; /* Slightly Darker Yellow on Hover */
    }

    .ticket-row-closed {
        background-color: #d1e7dd !important; /* Light Green */
    }
    
    .ticket-row-closed:hover {
        background-color: #c3e6cb !important;
    }

    .feedback-table td {
        padding: 18px;
        vertical-align: top;
        font-size: 15px;
        color: #334155;
        white-space: nowrap;
        border-bottom: 1px solid #f1f5f9;
    }

    .feedback-table td:last-child {
        text-align: center;
        vertical-align: top;
    }

    .feedback-table td.text-wrap {
        white-space: normal;
        max-width: 250px;
        line-height: 1.5;
    }

    /* Read More Button Styles */
    .view-content-btn {
        color: var(--primary);
        font-weight: 700;
        font-size: 13px;
        cursor: pointer;
        text-decoration: none;
        display: inline-block;
        margin-top: 4px;
    }
    
    .view-content-btn:hover {
        text-decoration: underline;
        color: var(--primary-dark);
    }

    /* Modal for View Content */
    .modal-body-content {
        font-size: 16px;
        color: #334155;
        line-height: 1.8;
        padding: 10px;
        white-space: pre-wrap;
        word-wrap: break-word;
    }

    .action-icons {
        display: inline-flex;
        gap: 8px;
    }

    .action-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 38px;
        height: 38px;
        border-radius: 10px;
        border: 2px solid #e2e8f0;
        background: white;
        color: #64748b;
        cursor: pointer;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        text-decoration: none;
        font-size: 14px;
    }
    
    .action-btn.chat-btn:hover {
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
        border-color: var(--success);
        transform: translateY(-3px);
        box-shadow: 0 6px 16px rgba(16, 185, 129, 0.4);
    }
    
    .action-btn.ticket-btn {
        background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        color: white;
        border-color: #f59e0b;
    }
    
    .action-btn.ticket-btn:hover {
        background: linear-gradient(135deg, #d97706 0%, #b45309 100%);
        transform: translateY(-3px);
        box-shadow: 0 6px 16px rgba(245, 158, 11, 0.4);
    }

    .badge {
        display: inline-block;
        padding: 6px 14px;
        border-radius: 14px;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    
    .badge-suggestion { background: #dbeafe; color: #1e40af; }
    .badge-complaint { background: #fee2e2; color: #991b1b; }
    .badge-appreciation { background: #fce7f3; color: #9f1239; }
    .badge-general { background: #f3f4f6; color: #374151; }
    .badge-employee { background: #e0e7ff; color: #4338ca; }
    .badge-customer { background: #d1fae5; color: #065f46; }
    
    .badge-responded {
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
        box-shadow: 0 2px 8px rgba(16, 185, 129, 0.3);
        margin-top: 5px;
    }
    
    .badge-pending {
        background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        color: white;
        box-shadow: 0 2px 8px rgba(245, 158, 11, 0.3);
    }

    /* Ticket Badges */
    .badge-warning {
        background: #ffc107;
        color: #212529;
    }

    .badge-success {
        background: #198754;
        color: white;
    }

    .rating { 
        color: #fbbf24; 
        font-size: 15px; 
        letter-spacing: 1px; 
        font-weight: 600;
    }

    .pagination-area { 
        margin-top: 32px; 
        display: flex; 
        justify-content: space-between; 
        align-items: center; 
        flex-wrap: wrap; 
        gap: 16px; 
    }
    
    .pagination-info {
        color: #64748b;
        font-weight: 600;
        font-size: 13px;
    }
    
    .pagination { 
        margin: 0; 
        display: flex; 
        gap: 6px; 
    }
    
    .pagination > li > a { 
        border-radius: 12px; 
        border: 2px solid #e2e8f0; 
        color: #64748b; 
        font-weight: 700; 
        padding: 11px 18px; 
        font-size: 13px; 
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }
    
    .pagination > li.active > a {
        background: var(--bg-gradient);
        border-color: var(--primary); 
        color: white;
        box-shadow: 0 4px 12px rgba(99, 102, 241, 0.3);
    }
    
    .pagination > li > a:hover { 
        background: #f1f5f9; 
        color: var(--primary); 
        border-color: var(--primary);
        transform: translateY(-2px);
    }

    .modal-content { 
        border-radius: 24px; 
        border: none; 
        box-shadow: 0 25px 50px -12px rgba(0,0,0,0.25); 
    }
    
    .modal-header { 
        background: var(--bg-gradient); 
        color: white; 
        border-radius: 24px 24px 0 0; 
        padding: 22px 28px; 
        border-bottom: none;
    }
    
    .modal-title {
        font-weight: 800;
        font-size: 18px;
        display: flex;
        align-items: center;
        gap: 10px;
    }
    
    .modal-body { padding: 0; }
    
    .close { 
        color: white; 
        opacity: 0.9; 
        text-shadow: none; 
        font-size: 32px;
        font-weight: 300;
        transition: all 0.3s;
    }
    
    .close:hover {
        opacity: 1;
        transform: rotate(90deg);
    }
    
    .form-group label {
        font-weight: 700;
        color: #475569;
        margin-bottom: 8px;
        font-size: 13px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    .detail-box {
        padding: 14px 18px;
        background: #f8fafc;
        border-radius: 12px;
        border-left: 4px solid var(--primary);
        color: #334155;
        font-size: 14px;
        margin-bottom: 16px;
        font-weight: 600;
    }

    .conversation-thread {
        max-height: 550px;
        overflow-y: auto;
        padding: 24px;
        background: var(--whatsapp-bg);
        background-image: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><text x="50" y="50" font-size="60" opacity="0.03" text-anchor="middle" fill="%23000">💬</text></svg>');
    }

    .message-bubble {
        margin-bottom: 14px;
        padding: 12px 16px;
        border-radius: 10px;
        position: relative;
        animation: fadeIn 0.4s cubic-bezier(0.4, 0, 0.2, 1);
        max-width: 75%;
        word-wrap: break-word;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        clear: both;
    }

    @keyframes fadeIn {
        from { opacity: 0; transform: translateY(15px); }
        to { opacity: 1; transform: translateY(0); }
    }

    .message-bubble.user-message {
        background: var(--whatsapp-user);
        margin-left: auto;
        float: right;
        clear: both;
        border-radius: 10px 10px 0 10px;
    }

    .message-bubble.admin-message {
        background: var(--whatsapp-admin);
        margin-right: auto;
        float: left;
        clear: both;
        border-radius: 10px 10px 10px 0;
        border-left: 4px solid #1565c0;
    }

    .message-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 8px;
        padding-bottom: 6px;
        border-bottom: 1px solid rgba(0,0,0,0.06);
    }

    .message-sender {
        font-weight: 700;
        font-size: 12px;
        color: #075e54;
    }

    .admin-message .message-sender {
        color: #1565c0;
    }

    .message-time {
        font-size: 10px;
        color: #667781;
        font-weight: 600;
        margin-left: 12px;
    }

    .message-content {
        color: #303030;
        font-size: 14px;
        line-height: 1.5;
        word-wrap: break-word;
        white-space: pre-wrap;
    }

    .message-subject {
        font-weight: 700;
        color: #075e54;
        margin-bottom: 8px;
        font-size: 13px;
    }

    .message-rating {
        margin-top: 8px;
        font-size: 13px;
        color: #f59e0b;
    }

    .loading-conversation {
        text-align: center;
        padding: 50px;
        color: #667781;
    }

    .conversation-footer {
        padding: 24px 28px;
        background: #f0f2f5;
        border-top: 1px solid #e2e8f0;
    }

    .typing-indicator {
        display: none;
        padding: 10px 18px;
        background: rgba(16, 185, 129, 0.1);
        border-radius: 12px;
        font-size: 12px;
        color: var(--success);
        font-weight: 700;
        margin-bottom: 12px;
        animation: pulse 1.5s ease-in-out infinite;
    }

    .typing-indicator.active {
        display: block;
    }

    @keyframes pulse {
        0%, 100% { opacity: 0.6; }
        50% { opacity: 1; }
    }

    .reply-input-group {
        display: flex;
        gap: 12px;
        align-items: flex-end;
    }

    .reply-input-group textarea {
        flex: 1;
        border: 2px solid #e2e8f0;
        border-radius: 14px;
        padding: 14px 18px;
        resize: none;
        font-size: 14px;
        min-height: 90px;
        max-height: 130px;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }

    .reply-input-group textarea:focus {
        border-color: var(--primary);
        box-shadow: 0 0 0 4px rgba(99, 102, 241, 0.1);
        outline: none;
    }

    .reply-input-group button {
        background: var(--bg-gradient);
        color: white;
        border: none;
        padding: 14px 26px;
        border-radius: 12px;
        font-weight: 700;
        cursor: pointer;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        white-space: nowrap;
        min-height: 52px;
    }

    .reply-input-group button:hover {
        transform: translateY(-3px);
        box-shadow: 0 10px 30px rgba(99, 102, 241, 0.4);
    }

    .reply-input-group button:disabled {
        background: #cbd5e1;
        cursor: not-allowed;
        transform: none;
        box-shadow: none;
    }

    textarea.form-control, input.form-control, select.form-control {
        border: 2px solid #e2e8f0;
        border-radius: 14px;
        padding: 14px 18px;
        resize: vertical;
        font-size: 14px;
        color: #0f172a;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    }
    
    input.form-control, select.form-control {
        height: 52px !important;
        line-height: normal;
    }
    
    select.form-control {
        color: #334155;
        background-color: #fff;
    }
    
    textarea.form-control {
        min-height: 140px;
    }
    
    textarea.form-control:focus, input.form-control:focus, select.form-control:focus {
        border-color: var(--primary);
        box-shadow: 0 0 0 4px rgba(99, 102, 241, 0.1);
        outline: none;
    }

    .empty-state {
        text-align: center;
        padding: 70px 20px;
        background: white;
        border-radius: 18px;
        border: 2px dashed #cbd5e1;
    }
    
    .empty-state i {
        font-size: 72px;
        color: #cbd5e1;
        margin-bottom: 24px;
    }
    
    .empty-state h3 {
        font-size: 26px;
        font-weight: 700;
        color: #334155;
        margin-bottom: 12px;
    }
    
    .empty-state p {
        color: #64748b;
        font-size: 15px;
    }

    .form-section {
        background: white;
        border-radius: 18px;
        padding: 28px 32px;
        margin-bottom: 32px;
        border: 1px solid #e2e8f0;
        box-shadow: var(--card-shadow);
    }

    .form-section h4 {
        color: #0f172a;
        font-weight: 800;
        font-size: 20px;
        margin-bottom: 24px;
        padding-bottom: 16px;
        border-bottom: 2px solid #e2e8f0;
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .btn-primary {
        background: var(--bg-gradient);
        color: white;
        border: none;
        padding: 14px 28px;
        border-radius: 12px;
        font-weight: 700;
        cursor: pointer;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        font-size: 14px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    .btn-primary:hover {
        transform: translateY(-3px);
        box-shadow: 0 10px 30px rgba(99, 102, 241, 0.4);
    }
    
    .btn-primary:disabled {
        background: #cbd5e1;
        cursor: not-allowed;
        transform: none;
        box-shadow: none;
    }

    .section-header-with-toggle {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 26px;
        flex-wrap: wrap;
        gap: 16px;
    }

    .section-header-with-toggle h4 {
        color: #0f172a;
        font-weight: 800;
        font-size: 22px;
        margin: 0;
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .personal-section-divider {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        height: 4px;
        border-radius: 2px;
        margin: 50px 0 32px 0;
        position: relative;
    }

    .personal-section-divider::before {
        content: 'MY PERSONAL FEEDBACK';
        position: absolute;
        top: -15px;
        left: 50%;
        transform: translateX(-50%);
        background: white;
        padding: 5px 20px;
        font-size: 12px;
        font-weight: 900;
        color: #667eea;
        letter-spacing: 2px;
        border-radius: 20px;
        box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
    }

    @media (max-width: 1024px) {
        .filter-grid { 
            grid-template-columns: 1fr 1fr; 
        }
        .search-box {
            grid-column: 1 / -1;
        }
        .charts-row-bottom {
            grid-template-columns: 1fr;
        }
        .personal-filter-grid {
            grid-template-columns: 1fr;
        }
    }

    @media (max-width: 768px) {
        .main-wrap {
            padding: 20px 16px 80px 16px;
        }
        .top-header {
            padding: 0 16px;
        }
        .brand-text h1 {
            font-size: 16px;
        }
        .brand-text p {
            font-size: 10px;
        }
        .filter-grid { grid-template-columns: 1fr; }
        .feedback-table { font-size: 12px; }
        .feedback-table th, .feedback-table td { padding: 14px; }
        .message-bubble { max-width: 90%; }
        .reply-input-group { flex-direction: column; }
        .reply-input-group button { width: 100%; }
        .stats-row {
            grid-template-columns: 1fr;
        }
    }
  </style>
</head>
<body>

<audio id="notificationSound" preload="auto">
    <source src="notification.mp3" type="audio/wav">
</audio>

<header class="top-header">
    <div class="header-brand">
        <div class="brand-icon">
            <i class="fa fa-comments"></i>
        </div>
        <div class="brand-text">
            <h1><?php echo $is_admin ? 'Admin Feedback Center' : 'Feedback Portal'; ?></h1>
            <p><?php echo $is_admin ? 'Manage All Feedback' : 'Share Your Experience'; ?></p>
        </div>
    </div>
    <div class="header-actions">
        <?php if($is_keerti): ?>
        <button class="btn-header submit-btn" onclick="$('#submitFeedbackModal').modal('show')">
            <i class="fa fa-edit"></i> Submit Feedback
        </button>
        <?php endif; ?>
        
        <!-- UPDATED DASHBOARD LINK LOGIC -->
        <?php 
            $dashboard_url = $is_super_admin ? "index.php" : "https://crm.abra-logistic.com/dashboard/raise-a-ticket.php";
        ?>
        <a href="<?php echo $dashboard_url; ?>" class="btn-header">
            <i class="fa fa-arrow-left"></i> Dashboard
        </a>
    </div>
</header>

<div class="main-wrap">
    
    <?php if(!empty($success_message)): ?>
    <div id="flashMessage" class="alert-modern success">
        <i class="fa fa-check-circle"></i>
        <div><?php echo $success_message; ?></div>
        <button class="alert-close" onclick="this.parentElement.remove()">×</button>
    </div>
    <?php endif; ?>
    
    <?php if(!empty($error_message)): ?>
    <div id="flashMessage" class="alert-modern error">
        <i class="fa fa-exclamation-circle"></i>
        <div><?php echo $error_message; ?></div>
        <button class="alert-close" onclick="this.parentElement.remove()">×</button>
    </div>
    <?php endif; ?>

    <?php if($is_admin): ?>
        <!-- ADMIN VIEW (Both Abishek and Keerti) -->
        
        <!-- SINGLE FILTER BLOCK (ABOVE STATS & DASHBOARD) -->
        <form method="GET" action="" id="filterForm">
            <div class="filter-section">
                <div class="filter-grid">
                    <div class="search-box">
                        <i class="fa fa-search"></i>
                        <input type="text" name="search" placeholder="Search feedback..." 
                               value="<?php echo htmlspecialchars($search); ?>">
                    </div>
                    
                    <select name="source" class="filter-select select2-init" id="sourceFilter">
                        <option value="all">All Sources</option>
                        <option value="employee" <?php echo $source_filter === 'employee' ? 'selected' : ''; ?>>Employees Only</option>
                        <option value="customer" <?php echo $source_filter === 'customer' ? 'selected' : ''; ?>>Customers Only</option>
                    </select>
                    
                    <select name="name_filter" class="filter-select select2-init" id="nameFilter">
                        <option value="">All People</option>
                        <?php if($source_filter === 'all'): ?>
                            <?php if(!empty($employee_names)): ?>
                                <optgroup label="Employees">
                                    <?php foreach($employee_names as $emp_name): ?>
                                        <option value="<?php echo htmlspecialchars($emp_name); ?>" <?php echo $name_filter === $emp_name ? 'selected' : ''; ?>>
                                            <?php echo htmlspecialchars($emp_name); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </optgroup>
                            <?php endif; ?>
                            <?php if(!empty($customer_names)): ?>
                                <optgroup label="Customers">
                                    <?php foreach($customer_names as $cust_name): ?>
                                        <option value="<?php echo htmlspecialchars($cust_name); ?>" <?php echo $name_filter === $cust_name ? 'selected' : ''; ?>>
                                            <?php echo htmlspecialchars($cust_name); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </optgroup>
                            <?php endif; ?>
                        <?php elseif($source_filter === 'employee'): ?>
                            <?php foreach($employee_names as $emp_name): ?>
                                <option value="<?php echo htmlspecialchars($emp_name); ?>" <?php echo $name_filter === $emp_name ? 'selected' : ''; ?>>
                                    <?php echo htmlspecialchars($emp_name); ?>
                                </option>
                            <?php endforeach; ?>
                        <?php elseif($source_filter === 'customer'): ?>
                            <?php foreach($customer_names as $cust_name): ?>
                                <option value="<?php echo htmlspecialchars($cust_name); ?>" <?php echo $name_filter === $cust_name ? 'selected' : ''; ?>>
                                    <?php echo htmlspecialchars($cust_name); ?>
                                </option>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </select>
                    
                    <select name="type" class="filter-select select2-init">
                        <option value="all">All Types</option>
                        <option value="suggestion" <?php echo $type_filter === 'suggestion' ? 'selected' : ''; ?>>Suggestion</option>
                        <option value="complaint" <?php echo $type_filter === 'complaint' ? 'selected' : ''; ?>>Complaint</option>
                        <option value="appreciation" <?php echo $type_filter === 'appreciation' ? 'selected' : ''; ?>>Appreciation</option>
                        <option value="general" <?php echo $type_filter === 'general' ? 'selected' : ''; ?>>General</option>
                    </select>
                    
                    <input type="date" name="date_from" value="<?php echo htmlspecialchars($date_from); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                    
                    <input type="date" name="date_to" value="<?php echo htmlspecialchars($date_to); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                    
                    <button type="submit" class="btn-filter">
                        <i class="fa fa-filter"></i> Apply
                    </button>
                </div>
            </div>
        </form>
        
        <div class="stats-row">
            <div class="stat-box">
                <div class="stat-icon-wrap blue">
                    <i class="fa fa-users"></i>
                </div>
                <div class="stat-content">
                    <h3><?php echo number_format($total_employee); ?></h3>
                    <p>Employee Feedback</p>
                </div>
            </div>
            <div class="stat-box">
                <div class="stat-icon-wrap green">
                    <i class="fa fa-user"></i>
                </div>
                <div class="stat-content">
                    <h3><?php echo number_format($total_customer); ?></h3>
                    <p>Customer Feedback</p>
                </div>
            </div>
        </div>

        <!-- GRAPHS -->
        <div class="charts-row-top">
            <div class="chart-card">
                <h4><i class="fa fa-pie-chart"></i> Overall Feedback Distribution</h4>
                <div class="chart-container">
                    <canvas id="overallPieChart"></canvas>
                </div>
            </div>
        </div>

        <div class="charts-row-bottom">
            <div class="chart-card">
                <h4><i class="fa fa-bar-chart"></i> Employee Feedback (Bar)</h4>
                <div class="chart-container">
                    <canvas id="employeeBarChart"></canvas>
                </div>
            </div>

            <div class="chart-card">
                <h4><i class="fa fa-bar-chart"></i> Customer Feedback (Bar)</h4>
                <div class="chart-container">
                    <canvas id="customerBarChart"></canvas>
                </div>
            </div>
        </div>

        <?php if($total_records > 0): ?>
            
            <div class="feedback-table-wrap">
                <table class="feedback-table">
                    <thead>
                        <tr>
                            <th style="width: 110px;">Date</th>
                            <th style="width: 90px;">Source</th>
                            <th style="width: 150px;">Name</th>
                            <th style="width: 110px;">Type</th>
                            <th style="width: 200px;">Subject</th>
                            <th style="width: auto;">Message</th>
                            <th style="width: 100px;">Rating</th>
                            <th style="width: 120px;">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php 
                    foreach($paginated_feedback as $item): 
                        $has_reply = $item['has_conversation'];
                        $stars = str_repeat('★', $item['rating']) . str_repeat('☆', 5 - $item['rating']);
                        
                        // Subject Logic
                        $full_subj = htmlspecialchars($item['subject']);
                        $display_subj = $full_subj;
                        $has_long_subj = false;
                        if(strlen($full_subj) > 40) {
                            $display_subj = substr($full_subj, 0, 40) . '...';
                            $has_long_subj = true;
                        }

                        // Message Logic
                        $full_msg = htmlspecialchars($item['message']);
                        $display_msg = $full_msg;
                        $has_long_msg = false;
                        if(strlen($full_msg) > 90) {
                            $display_msg = substr($full_msg, 0, 90) . '...';
                            $has_long_msg = true;
                        }

                        // Ticket Logic - Coloring rows based on ticket status
                        $row_class = '';
                        $ticket_exists = false;
                        $ticket_status = '';
                        $ticket_number = '';
                        $assigned_emp = '';
                        
                        // Check if ticket data exists
                        if (!empty($item['ticket_number'])) {
                            $ticket_status = strtolower($item['ticket_status']);
                            $assigned_emp = !empty($item['assigned_employee']) ? $item['assigned_employee'] : 'Unknown';
                            
                            // Define explicit Active Statuses (Yellow)
                            $active_statuses = array('open', 'new', 'in progress', 'pending', 'on hold', 'assigned', 're-open');
                            // Define explicit Closed Statuses (Green)
                            $closed_statuses = array('closed', 'resolved', 'completed');
                            
                            if (in_array($ticket_status, $active_statuses)) {
                                $ticket_exists = true;
                                $ticket_number = $item['ticket_number'];
                                $row_class = 'ticket-row-open'; // Yellow
                            } elseif (in_array($ticket_status, $closed_statuses)) {
                                $ticket_exists = true;
                                $ticket_number = $item['ticket_number'];
                                $row_class = 'ticket-row-closed'; // Green
                            }
                            // Else: Ignore status (treat as if no ticket exists to allow new one)
                        }
                    ?>
                        <tr class="<?php echo $row_class; ?>">
                            <td style="font-size: 13px; color: #64748b; font-weight: 600;">
                                <?php echo date('M d, Y', strtotime($item['date_submitted'])); ?>
                            </td>
                            <td>
                                <span class="badge badge-<?php echo $item['source']; ?>">
                                    <?php echo ucfirst($item['source']); ?>
                                </span>
                            </td>
                            <td>
                                <strong style="font-size: 15px; font-weight: 700;">
                                    <?php echo htmlspecialchars($item['submitter_name']); ?>
                                </strong>
                            </td>
                            <td>
                                <span class="badge badge-<?php echo $item['feedback_type']; ?>">
                                    <?php echo ucfirst($item['feedback_type']); ?>
                                </span>
                            </td>
                            <!-- SUBJECT COLUMN WITH MODAL TRIGGER -->
                            <td>
                                <strong style="font-size: 15px; font-weight: 700; white-space: normal;">
                                    <?php echo $display_subj; ?>
                                </strong>
                                <?php if($has_long_subj): ?>
                                    <div class="full-content-storage" style="display:none;"><?php echo $full_subj; ?></div>
                                    <a class="view-content-btn" data-title="Full Subject">Read More</a>
                                <?php endif; ?>

                                <?php if($has_reply): ?>
                                <br><span class="badge badge-responded">
                                    <i class="fa fa-check-circle"></i> Responded
                                </span>
                                <?php endif; ?>
                            </td>
                            <!-- MESSAGE COLUMN WITH MODAL TRIGGER -->
                            <td class="text-wrap">
                                <?php echo $display_msg; ?>
                                <?php if($has_long_msg): ?>
                                    <div class="full-content-storage" style="display:none;"><?php echo $full_msg; ?></div>
                                    <br><a class="view-content-btn" data-title="Full Message">Read More</a>
                                <?php endif; ?>
                            </td>
                            <td>
                                <span class="rating">
                                    <?php echo $stars; ?>
                                </span>
                            </td>
                            <td>
                                <div class="action-icons">
                                    <a href="#" class="action-btn chat-btn" 
                                       data-id="<?php echo $item['id']; ?>"
                                       data-source="<?php echo $item['source']; ?>"
                                       title="View Conversation">
                                        <i class="fa fa-comments"></i>
                                    </a>
                                    
                                    <?php if ($ticket_exists): ?>
                                        <!-- Show ticket info instead of button if ticket exists -->
                                        <?php if ($row_class == 'ticket-row-closed'): ?>
                                            <span class="badge badge-success" style="text-align: left;">
                                                <i class="fa fa-check"></i> Closed #<?php echo $ticket_number; ?>
                                                <div style="font-size: 9px; opacity: 0.9; margin-top: 2px;">To: <?php echo htmlspecialchars($assigned_emp); ?></div>
                                            </span>
                                        <?php else: ?>
                                            <span class="badge badge-warning" style="text-align: left;">
                                                <i class="fa fa-ticket"></i> Ticket #<?php echo $ticket_number; ?>
                                                <div style="font-size: 9px; opacity: 0.9; margin-top: 2px;">To: <?php echo htmlspecialchars($assigned_emp); ?></div>
                                            </span>
                                        <?php endif; ?>
                                    <?php else: ?>
                                        <!-- Show Create Ticket Button if no ticket exists -->
                                        <a href="#" class="action-btn ticket-btn" 
                                           data-id="<?php echo $item['id']; ?>"
                                           data-source="<?php echo $item['source']; ?>"
                                           data-name="<?php echo htmlspecialchars($item['submitter_name']); ?>"
                                           data-subject="<?php echo htmlspecialchars($item['subject']); ?>"
                                           title="Create Ticket">
                                            <i class="fa fa-ticket"></i>
                                        </a>
                                    <?php endif; ?>
                                </div>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <div class="pagination-area">
                <div class="pagination-info">
                    Showing <?php echo $offset + 1; ?> to <?php echo min($offset + $records_per_page, $total_records); ?> of <?php echo $total_records; ?> feedback
                </div>
                <ul class="pagination">
                    <?php 
                    $params = $_GET;
                    unset($params['page']);
                    $qs = http_build_query($params);
                    if($page > 1): ?>
                        <li><a href="?page=<?php echo ($page-1); ?>&<?php echo $qs; ?>"><i class="fa fa-chevron-left"></i></a></li>
                    <?php endif; ?>
                    <?php for($i=1; $i<=$total_pages; $i++): 
                        if($i == 1 || $i == $total_pages || ($i >= $page-2 && $i <= $page+2)): ?>
                        <li class="<?php echo ($i == $page) ? 'active' : ''; ?>">
                            <a href="?page=<?php echo $i; ?>&<?php echo $qs; ?>"><?php echo $i; ?></a>
                        </li>
                    <?php elseif($i == $page-3 || $i == $page+3): ?>
                        <li><a>...</a></li>
                    <?php endif; endfor; ?>
                    <?php if($page < $total_pages): ?>
                        <li><a href="?page=<?php echo ($page+1); ?>&<?php echo $qs; ?>"><i class="fa fa-chevron-right"></i></a></li>
                    <?php endif; ?>
                </ul>
            </div>
        <?php else: ?>
            <div class="empty-state">
                <i class="fa fa-search"></i>
                <h3>No feedback found</h3>
                <p>No feedback matches your current filters.</p>
            </div>
        <?php endif; ?>

        <?php if($is_keerti): ?>
        <!-- KEERTI'S PERSONAL FEEDBACK HISTORY SECTION -->
        <div class="personal-section-divider"></div>

        <div class="stats-row">
            <div class="stat-box">
                <div class="stat-icon-wrap blue"><i class="fa fa-user"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($keerti_total_count); ?></h3>
                    <p>My Total Feedback</p>
                </div>
            </div>
            <div class="stat-box">
                <div class="stat-icon-wrap green"><i class="fa fa-check-circle"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($keerti_responded_count); ?></h3>
                    <p>Responded</p>
                </div>
            </div>
            <div class="stat-box">
                <div class="stat-icon-wrap orange"><i class="fa fa-clock-o"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($keerti_pending_count); ?></h3>
                    <p>Pending</p>
                </div>
            </div>
        </div>

        <!-- Personal History Filters -->
        <form method="GET" action="">
            <div class="filter-section" style="padding: 16px;">
                <div class="personal-filter-grid">
                    <input type="date" name="my_date_from" value="<?php echo htmlspecialchars($_GET['my_date_from'] ?? ''); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                    <input type="date" name="my_date_to" value="<?php echo htmlspecialchars($_GET['my_date_to'] ?? ''); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                    <button type="submit" class="btn-filter"><i class="fa fa-filter"></i> Filter</button>
                </div>
            </div>
        </form>
        
        <?php if($keerti_total_count > 0): ?>
        <div class="feedback-table-wrap">
            <table class="feedback-table">
                <thead>
                    <tr>
                        <th style="width: 110px;">Date</th>
                        <th style="width: 110px;">Type</th>
                        <th style="width: 200px;">Subject</th>
                        <th style="width: auto;">Message</th>
                        <th style="width: 100px;">Rating</th>
                        <th style="width: 100px;">Status</th>
                        <th style="width: 70px;">Actions</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach($keerti_personal_feedback as $feedback): 
                    $has_reply = $feedback['has_conversation'];
                    $stars = str_repeat('★', $feedback['rating']) . str_repeat('☆', 5 - $feedback['rating']);
                    
                    // Logic for Truncation
                    $full_subj = htmlspecialchars($feedback['subject']);
                    $display_subj = $full_subj;
                    $has_long_subj = (strlen($full_subj) > 40);
                    if($has_long_subj) $display_subj = substr($full_subj, 0, 40) . '...';
                    
                    $full_msg = htmlspecialchars($feedback['message']);
                    $display_msg = $full_msg;
                    $has_long_msg = (strlen($full_msg) > 90);
                    if($has_long_msg) $display_msg = substr($full_msg, 0, 90) . '...';
                ?>
                    <tr>
                        <td style="font-size: 13px; color: #64748b; font-weight: 600;">
                            <?php echo date('M d, Y', strtotime($feedback['date_submitted'])); ?>
                        </td>
                        <td>
                            <span class="badge badge-<?php echo $feedback['feedback_type']; ?>">
                                <?php echo ucfirst($feedback['feedback_type']); ?>
                            </span>
                        </td>
                        <td>
                            <strong style="font-size: 15px; font-weight: 700; white-space: normal;">
                                <?php echo $display_subj; ?>
                            </strong>
                            <?php if($has_long_subj): ?>
                                <div class="full-content-storage" style="display:none;"><?php echo $full_subj; ?></div>
                                <a class="view-content-btn" data-title="Full Subject">Read More</a>
                            <?php endif; ?>
                        </td>
                        <td class="text-wrap">
                            <?php echo $display_msg; ?>
                            <?php if($has_long_msg): ?>
                                <div class="full-content-storage" style="display:none;"><?php echo $full_msg; ?></div>
                                <br><a class="view-content-btn" data-title="Full Message">Read More</a>
                            <?php endif; ?>
                        </td>
                        <td>
                            <span class="rating">
                                <?php echo $stars; ?>
                            </span>
                        </td>
                        <td>
                            <?php if($has_reply): ?>
                            <span class="badge badge-responded"><i class="fa fa-check-circle"></i> Responded</span>
                            <?php else: ?>
                            <span class="badge badge-pending"><i class="fa fa-clock-o"></i> Pending</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <a href="#" class="action-btn chat-btn user-chat-btn" 
                               data-id="<?php echo $feedback['id']; ?>"
                               data-source="<?php echo $feedback['source']; ?>"
                               title="View Conversation">
                                <i class="fa fa-comments"></i>
                            </a>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php else: ?>
            <div class="empty-state">
                <i class="fa fa-inbox"></i>
                <h3>No feedback submitted yet</h3>
                <p>Be the first to share your thoughts!</p>
            </div>
        <?php endif; ?>
        <?php endif; ?>

    <?php else: ?>
        <!-- NON-ADMIN VIEW (Regular Users) -->
        
        <div class="stats-row">
            <div class="stat-box">
                <div class="stat-icon-wrap blue"><i class="fa fa-comments"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($total_feedback_count); ?></h3>
                    <p>Total Feedback</p>
                </div>
            </div>
            <div class="stat-box">
                <div class="stat-icon-wrap green"><i class="fa fa-check-circle"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($responded_count); ?></h3>
                    <p>Responded</p>
                </div>
            </div>
            <div class="stat-box">
                <div class="stat-icon-wrap orange"><i class="fa fa-clock-o"></i></div>
                <div class="stat-content">
                    <h3><?php echo number_format($pending_count); ?></h3>
                    <p>Pending</p>
                </div>
            </div>
        </div>
        
        <div class="form-section">
            <h4><i class="fa fa-edit"></i> Submit New Feedback</h4>
            
            <form method="POST" action="">
                <div class="row">
                    <div class="col-md-4">
                        <div class="form-group">
                            <label>Your Name <span style="color: var(--danger);">*</span></label>
                            <input type="text" class="form-control" name="<?php echo $user_type === 'employee' ? 'employee_name' : 'customer_name'; ?>" value="<?php echo htmlspecialchars($user_full_name); ?>" readonly required>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="form-group">
                            <label>Feedback Type <span style="color: var(--danger);">*</span></label>
                            <select class="form-control" name="feedback_type" required>
                                <option value="" disabled selected>Select Type</option>
                                <option value="suggestion">💡 Suggestion</option>
                                <option value="complaint">⚠️ Complaint</option>
                                <option value="general">📝 General Feedback</option>
                                <option value="appreciation">🎉 Appreciation</option>
                            </select>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="form-group">
                            <label>Rating <span style="color: var(--danger);">*</span></label>
                            <select class="form-control" name="rating" required>
                                <option value="" disabled selected>Select Rating</option>
                                <option value="5">★★★★★ Excellent</option>
                                <option value="4">★★★★☆ Good</option>
                                <option value="3">★★★☆☆ Average</option>
                                <option value="2">★★☆☆☆ Poor</option>
                                <option value="1">★☆☆☆☆ Very Poor</option>
                            </select>
                        </div>
                    </div>
                </div>
                
                <div class="form-group">
                    <label>Subject <span style="color: var(--danger);">*</span></label>
                    <input type="text" class="form-control" name="subject" placeholder="Brief subject of your feedback" required>
                </div>
                
                <div class="form-group">
                    <label>Message <span style="color: var(--danger);">*</span></label>
                    <textarea class="form-control" name="message" placeholder="Please provide detailed feedback..." required></textarea>
                </div>
                
                <div class="form-group" style="margin-bottom: 0;">
                    <button type="submit" name="<?php echo $user_type === 'employee' ? 'submit_employee_feedback' : 'submit_customer_feedback'; ?>" class="btn btn-primary">
                        <i class="fa fa-paper-plane"></i> Submit Feedback
                    </button>
                </div>
            </form>
        </div>
        
        <div style="margin-top: 40px;">
            <div class="section-header-with-toggle">
                <h4><i class="fa fa-history"></i> Your Feedback History</h4>
            </div>

            <form method="GET" action="">
                <div class="filter-section" style="padding: 16px;">
                    <div class="personal-filter-grid">
                        <input type="date" name="my_date_from" value="<?php echo htmlspecialchars($_GET['my_date_from'] ?? ''); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                        <input type="date" name="my_date_to" value="<?php echo htmlspecialchars($_GET['my_date_to'] ?? ''); ?>" class="filter-select" style="padding: 0 12px; height: 48px; border: 2px solid #e2e8f0; border-radius: 13px;">
                        <button type="submit" class="btn-filter"><i class="fa fa-filter"></i> Filter</button>
                    </div>
                </div>
            </form>
            
            <?php if(!empty($my_feedback_array)): ?>
                
                <div class="feedback-table-wrap">
                    <table class="feedback-table">
                        <thead>
                            <tr>
                                <th style="width: 110px;">Date</th>
                                <th style="width: 110px;">Type</th>
                                <th style="width: 200px;">Subject</th>
                                <th style="width: auto;">Message</th>
                                <th style="width: 100px;">Rating</th>
                                <th style="width: 100px;">Status</th>
                                <th style="width: 70px;">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                        <?php foreach($my_feedback_array as $feedback): 
                            $has_reply = $feedback['has_conversation'];
                            $stars = str_repeat('★', $feedback['rating']) . str_repeat('☆', 5 - $feedback['rating']);
                            
                            // Truncation
                            $full_subj = htmlspecialchars($feedback['subject']);
                            $display_subj = $full_subj;
                            $has_long_subj = (strlen($full_subj) > 40);
                            if($has_long_subj) $display_subj = substr($full_subj, 0, 40) . '...';
                            
                            $full_msg = htmlspecialchars($feedback['message']);
                            $display_msg = $full_msg;
                            $has_long_msg = (strlen($full_msg) > 90);
                            if($has_long_msg) $display_msg = substr($full_msg, 0, 90) . '...';
                        ?>
                            <tr>
                                <td style="font-size: 13px; color: #64748b; font-weight: 600;">
                                    <?php echo date('M d, Y', strtotime($feedback['date_submitted'])); ?>
                                </td>
                                <td>
                                    <span class="badge badge-<?php echo $feedback['feedback_type']; ?>">
                                        <?php echo ucfirst($feedback['feedback_type']); ?>
                                    </span>
                                </td>
                                <td>
                                    <strong style="font-size: 15px; font-weight: 700; white-space: normal;">
                                        <?php echo $display_subj; ?>
                                    </strong>
                                    <?php if($has_long_subj): ?>
                                        <div class="full-content-storage" style="display:none;"><?php echo $full_subj; ?></div>
                                        <a class="view-content-btn" data-title="Full Subject">Read More</a>
                                    <?php endif; ?>
                                </td>
                                <td class="text-wrap">
                                    <?php echo $display_msg; ?>
                                    <?php if($has_long_msg): ?>
                                        <div class="full-content-storage" style="display:none;"><?php echo $full_msg; ?></div>
                                        <br><a class="view-content-btn" data-title="Full Message">Read More</a>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <span class="rating">
                                        <?php echo $stars; ?>
                                    </span>
                                </td>
                                <td>
                                    <?php if($has_reply): ?>
                                    <span class="badge badge-responded"><i class="fa fa-check-circle"></i> Responded</span>
                                    <?php else: ?>
                                    <span class="badge badge-pending"><i class="fa fa-clock-o"></i> Pending</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <a href="#" class="action-btn chat-btn user-chat-btn" 
                                       data-id="<?php echo $feedback['id']; ?>"
                                       data-source="<?php echo $feedback['source']; ?>"
                                       title="View Conversation">
                                        <i class="fa fa-comments"></i>
                                    </a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php else: ?>
                <div class="empty-state">
                    <i class="fa fa-inbox"></i>
                    <h3>No feedback submitted yet</h3>
                    <p>Be the first to share your thoughts! Submit your feedback above.</p>
                </div>
            <?php endif; ?>
        </div>
    <?php endif; ?>

</div>

<!-- CONVERSATION MODAL -->
<div class="modal fade" id="conversationModal" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title">
                    <i class="fa fa-comments"></i> Conversation
                </h4>
            </div>
            <div class="modal-body">
                <div class="conversation-thread" id="conversationThread">
                    <div class="loading-conversation">
                        <i class="fa fa-spinner fa-spin" style="font-size: 32px; color: #667781;"></i>
                        <p style="margin-top: 16px; font-weight: 600;">Loading conversation...</p>
                    </div>
                </div>
                <div class="conversation-footer">
                    <div class="typing-indicator" id="typingIndicator">
                        <i class="fa fa-circle-o-notch fa-spin"></i> Sending message...
                    </div>
                    <div class="reply-input-group">
                        <textarea id="replyMessage" placeholder="Type your reply here..." class="reply-textarea"></textarea>
                        <button type="button" id="sendReplyBtn" class="send-reply-btn">
                            <i class="fa fa-paper-plane"></i> Send
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- VIEW FULL CONTENT MODAL (CARD STYLE) -->
<div class="modal fade" id="viewContentModal" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title">Full Content</h4>
            </div>
            <div class="modal-body">
                <div class="modal-body-content"></div>
            </div>
        </div>
    </div>
</div>

<!-- TICKET ASSIGNMENT MODAL -->
<div class="modal fade" id="ticketModal" tabindex="-1" role="dialog">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title"><i class="fa fa-ticket"></i> Create Ticket</h4>
            </div>
            <div class="modal-body" style="padding: 28px;">
                <!-- Warning for existing tickets -->
                <div id="ticketWarning" class="alert alert-warning" style="display:none; font-size: 13px; padding: 10px; margin-bottom: 15px;">
                    <i class="fa fa-exclamation-triangle"></i> <span id="ticketWarningMsg"></span>
                </div>

                <div class="detail-box">
                    <strong>From:</strong> <span id="ticketName"></span><br>
                    <strong>Subject:</strong> <span id="ticketSubject"></span>
                </div>
                <div class="form-group">
                    <label>Assign To Employee:</label>
                    <select class="form-control" id="assignToEmployee" required>
                        <option value="">Select Employee</option>
                        <?php foreach($employees_list as $emp): ?>
                            <option value="<?php echo $emp['id']; ?>"><?php echo htmlspecialchars($emp['name']); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <button type="button" id="createTicketBtn" class="btn btn-primary">
                    <i class="fa fa-check"></i> Create Ticket
                </button>
            </div>
        </div>
    </div>
</div>

<?php if($is_keerti): ?>
<!-- KEERTI SUBMIT FEEDBACK MODAL -->
<div class="modal fade" id="submitFeedbackModal" tabindex="-1" role="dialog">
    <div class="modal-dialog modal-lg" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal">&times;</button>
                <h4 class="modal-title"><i class="fa fa-edit"></i> Submit Your Feedback</h4>
            </div>
            <div class="modal-body" style="padding: 28px;">
                <form method="POST" action="">
                    <div class="row">
                        <div class="col-md-4">
                            <div class="form-group">
                                <label>Your Name <span style="color: var(--danger);">*</span></label>
                                <input type="text" class="form-control" name="employee_name" value="<?php echo htmlspecialchars($currentUserName); ?>" readonly required>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="form-group">
                                <label>Feedback Type <span style="color: var(--danger);">*</span></label>
                                <select class="form-control" name="feedback_type" required>
                                    <option value="" disabled selected>Select Type</option>
                                    <option value="suggestion">💡 Suggestion</option>
                                    <option value="complaint">⚠️ Complaint</option>
                                    <option value="general">📝 General Feedback</option>
                                    <option value="appreciation">🎉 Appreciation</option>
                                </select>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="form-group">
                                <label>Rating <span style="color: var(--danger);">*</span></label>
                                <select class="form-control" name="rating" required>
                                    <option value="" disabled selected>Select Rating</option>
                                    <option value="5">★★★★★ Excellent</option>
                                    <option value="4">★★★★☆ Good</option>
                                    <option value="3">★★★☆☆ Average</option>
                                    <option value="2">★★☆☆☆ Poor</option>
                                    <option value="1">★☆☆☆☆ Very Poor</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    
                    <div class="form-group">
                        <label>Subject <span style="color: var(--danger);">*</span></label>
                        <input type="text" class="form-control" name="subject" placeholder="Brief subject of your feedback" required>
                    </div>
                    
                    <div class="form-group">
                        <label>Message <span style="color: var(--danger);">*</span></label>
                        <textarea class="form-control" name="message" placeholder="Please provide detailed feedback..." required></textarea>
                    </div>
                    
                    <button type="submit" name="submit_employee_feedback" class="btn btn-primary">
                        <i class="fa fa-paper-plane"></i> Submit Feedback
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>
<?php endif; ?>

<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/js/bootstrap.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.13/js/select2.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>

<script>
function playNotificationSound() {
    var sound = document.getElementById('notificationSound');
    if (sound) {
        sound.pause();
        sound.currentTime = 0; // Rewind sound to start for rapid replays
        sound.play().catch(function(error) { 
            console.log('Notification sound play failed (Autoplay policy):', error); 
        });
    }
}

$(document).ready(function() {
    $('.select2-init').select2({ width: '100%', minimumResultsForSearch: 5 });
    
    // Check URL parameters for successful submission to play sound
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.has('success') && urlParams.get('success') === '1') {
        playNotificationSound();
    }
    
    setTimeout(function() { $('#flashMessage').fadeOut('slow'); }, 10000);
    $('#sourceFilter').on('change', function() { $('#filterForm').submit(); });

    // READ MORE LOGIC (MODAL)
    $(document).on('click', '.view-content-btn', function(e) {
        e.preventDefault();
        var title = $(this).data('title');
        // Get the hidden content from the adjacent div
        var content = $(this).parent().find('.full-content-storage').html();
        
        // Update Modal
        $('#viewContentModal .modal-title').html(title);
        $('#viewContentModal .modal-body-content').html(content);
        $('#viewContentModal').modal('show');
    });

    <?php if($is_admin): ?>
    // CHARTS - Updated to include Percentages in Tooltips
    
    // Common Tooltip Callback for Percentage
    const tooltipPercentageCallback = {
        label: function(context) {
            let label = context.dataset.label || '';
            if (label) {
                label += ': ';
            }
            if (context.chart.config.type === 'pie') {
                label = context.label + ': ';
            }
            
            let value = context.raw;
            let total = 0;
            // Calculate total based on dataset
            context.dataset.data.forEach(val => { total += val; });
            
            let percentage = 0;
            if(total > 0) {
                percentage = Math.round((value / total) * 100);
            }
            
            return label + value + ' (' + percentage + '%)';
        }
    };

    var overallCtx = document.getElementById('overallPieChart');
    if (overallCtx) {
        new Chart(overallCtx.getContext('2d'), {
            type: 'pie',
            data: {
                labels: ['Suggestions', 'Complaints', 'Appreciation', 'General'],
                datasets: [{
                    data: [<?php echo $overall_suggestion; ?>, <?php echo $overall_complaint; ?>, <?php echo $overall_appreciation; ?>, <?php echo $overall_general; ?>],
                    backgroundColor: ['#3b82f6', '#ef4444', '#ec4899', '#6b7280'],
                    borderWidth: 2, borderColor: '#fff'
                }]
            },
            options: { 
                responsive: true, 
                maintainAspectRatio: false, 
                plugins: { 
                    legend: { position: 'bottom' },
                    tooltip: {
                        callbacks: tooltipPercentageCallback
                    }
                } 
            }
        });
    }

    var empCtx = document.getElementById('employeeBarChart');
    if (empCtx) {
        new Chart(empCtx.getContext('2d'), {
            type: 'bar',
            data: {
                labels: ['Suggestions', 'Complaints', 'Appreciation', 'General'],
                datasets: [{
                    label: 'Count',
                    data: [<?php echo $emp_suggestion_count; ?>, <?php echo $emp_complaint_count; ?>, <?php echo $emp_appreciation_count; ?>, <?php echo $emp_general_count; ?>],
                    backgroundColor: ['#3b82f6', '#ef4444', '#ec4899', '#6b7280'],
                    borderRadius: 6
                }]
            },
            options: { 
                responsive: true, 
                maintainAspectRatio: false, 
                plugins: { 
                    legend: { display: false },
                    tooltip: {
                        callbacks: tooltipPercentageCallback
                    }
                }, 
                scales: { y: { beginAtZero: true } } 
            }
        });
    }

    var custCtx = document.getElementById('customerBarChart');
    if (custCtx) {
        new Chart(custCtx.getContext('2d'), {
            type: 'bar',
            data: {
                labels: ['Suggestions', 'Complaints', 'Appreciation', 'General'],
                datasets: [{
                    label: 'Count',
                    data: [<?php echo $cust_suggestion_count; ?>, <?php echo $cust_complaint_count; ?>, <?php echo $cust_appreciation_count; ?>, <?php echo $cust_general_count; ?>],
                    backgroundColor: ['#3b82f6', '#ef4444', '#ec4899', '#6b7280'],
                    borderRadius: 6
                }]
            },
            options: { 
                responsive: true, 
                maintainAspectRatio: false, 
                plugins: { 
                    legend: { display: false },
                    tooltip: {
                        callbacks: tooltipPercentageCallback
                    }
                }, 
                scales: { y: { beginAtZero: true } } 
            }
        });
    }
    <?php endif; ?>
    
    var currentThreadId = null;
    var currentFeedbackSource = null;
    var previousMessageCount = 0;
    
    $(document).on('click', '.chat-btn, .user-chat-btn', function(e) {
        e.preventDefault();
        var feedbackId = $(this).data('id');
        var feedbackSource = $(this).data('source');
        
        currentThreadId = null;
        currentFeedbackSource = feedbackSource;
        previousMessageCount = 0;
        
        $('#conversationModal').modal('show');
        $('#conversationThread').html('<div class="loading-conversation"><i class="fa fa-spinner fa-spin" style="font-size: 32px; color: #667781;"></i><p style="margin-top: 16px; font-weight: 600;">Loading conversation...</p></div>');
        $('#replyMessage').val('');
        
        $.ajax({
            url: '<?php echo $_SERVER['PHP_SELF']; ?>', type: 'GET',
            data: { ajax_get_conversation: true, feedback_id: feedbackId, feedback_source: feedbackSource },
            success: function(response) {
                if(response.success) {
                    currentThreadId = response.thread_id;
                    previousMessageCount = response.total_messages;
                    var html = '';
                    $.each(response.conversation, function(index, msg) {
                        var messageClass = msg.is_admin ? 'admin-message' : 'user-message';
                        var formattedDate = new Date(msg.date).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
                        html += '<div class="message-bubble ' + messageClass + '"><div class="message-header"><span class="message-sender">' + escapeHtml(msg.sender) + '</span><span class="message-time">' + formattedDate + '</span></div>';
                        if(msg.subject && msg.subject !== 'Reply' && msg.subject !== 'Auto-Reply') html += '<div class="message-subject">' + escapeHtml(msg.subject) + '</div>';
                        html += '<div class="message-content">' + escapeHtml(msg.message).replace(/\n/g, '<br>') + '</div>';
                        if(msg.rating > 0) html += '<div class="message-rating">' + '★'.repeat(msg.rating) + '☆'.repeat(5 - msg.rating) + '</div>';
                        html += '</div>';
                    });
                    $('#conversationThread').html(html);
                    scrollToBottom();
                } else {
                    $('#conversationThread').html('<div class="loading-conversation"><i class="fa fa-exclamation-triangle" style="font-size: 32px; color: #ef4444;"></i><p style="margin-top: 16px; font-weight: 600; color: #ef4444;">Error: ' + response.message + '</p></div>');
                }
            },
            error: function() { $('#conversationThread').html('<div class="loading-conversation"><i class="fa fa-exclamation-triangle" style="font-size: 32px; color: #ef4444;"></i><p style="margin-top: 16px; font-weight: 600; color: #ef4444;">Failed to load conversation</p></div>'); }
        });
    });
    
    $('#sendReplyBtn').on('click', function() {
        if(!currentThreadId) { alert('Error: No conversation selected'); return; }
        var replyMessage = $('#replyMessage').val().trim();
        if(replyMessage === '') { alert('Please enter a message'); return; }
        
        $('#sendReplyBtn').prop('disabled', true);
        $('#typingIndicator').addClass('active');
        
        $.ajax({
            url: '<?php echo $_SERVER['PHP_SELF']; ?>', type: 'POST',
            data: { ajax_send_reply: true, thread_id: currentThreadId, reply_message: replyMessage, feedback_source: currentFeedbackSource },
            success: function(response) {
                if(response.success) {
                    // Play sound immediately on successful send
                    playNotificationSound();
                    
                    var currentFeedbackId = currentThreadId;
                    $.ajax({
                        url: '<?php echo $_SERVER['PHP_SELF']; ?>', type: 'GET',
                        data: { ajax_get_conversation: true, feedback_id: currentFeedbackId, feedback_source: currentFeedbackSource },
                        success: function(response) {
                            if(response.success) {
                                // Also play sound if incoming messages arrived
                                if(response.total_messages > previousMessageCount + 1) { 
                                    playNotificationSound();
                                }
                                previousMessageCount = response.total_messages;
                                var html = '';
                                $.each(response.conversation, function(index, msg) {
                                    var messageClass = msg.is_admin ? 'admin-message' : 'user-message';
                                    var formattedDate = new Date(msg.date).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
                                    html += '<div class="message-bubble ' + messageClass + '"><div class="message-header"><span class="message-sender">' + escapeHtml(msg.sender) + '</span><span class="message-time">' + formattedDate + '</span></div>';
                                    if(msg.subject && msg.subject !== 'Reply' && msg.subject !== 'Auto-Reply') html += '<div class="message-subject">' + escapeHtml(msg.subject) + '</div>';
                                    html += '<div class="message-content">' + escapeHtml(msg.message).replace(/\n/g, '<br>') + '</div>';
                                    if(msg.rating > 0) html += '<div class="message-rating">' + '★'.repeat(msg.rating) + '☆'.repeat(5 - msg.rating) + '</div>';
                                    html += '</div>';
                                });
                                $('#conversationThread').html(html);
                                $('#replyMessage').val('');
                                scrollToBottom();
                            }
                        }
                    });
                } else { alert('Error: ' + response.message); }
                $('#sendReplyBtn').prop('disabled', false); $('#typingIndicator').removeClass('active');
            },
            error: function() { alert('Failed to send reply. Please try again.'); $('#sendReplyBtn').prop('disabled', false); $('#typingIndicator').removeClass('active'); }
        });
    });
    
    $('#replyMessage').on('keydown', function(e) { if(e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#sendReplyBtn').click(); } });
    
    var ticketFeedbackId = null; var ticketFeedbackSource = null;
    $('.ticket-btn').on('click', function(e) {
        e.preventDefault();
        ticketFeedbackId = $(this).data('id'); ticketFeedbackSource = $(this).data('source');
        var submitterName = $(this).data('name');
        var subject = $(this).data('subject');
        
        $('#ticketName').text(submitterName); 
        $('#ticketSubject').text(subject);
        $('#assignToEmployee').val('').trigger('change');
        
        // Reset warning state
        $('#ticketWarning').hide();
        $('#ticketWarningMsg').text('');
        
        // Check for existing tickets via AJAX
        $.ajax({
            url: '<?php echo $_SERVER['PHP_SELF']; ?>',
            type: 'GET',
            data: { 
                ajax_check_ticket_history: true, 
                name: submitterName, 
                subject: subject 
            },
            success: function(response) {
                if(response.exists) {
                    var msg = "Already raised to " + response.assigned_name + ". Ticket #" + response.ticket_number;
                    $('#ticketWarningMsg').text(msg);
                    $('#ticketWarning').show();
                }
            }
        });
        
        $('#ticketModal').modal('show');
    });
    
    $('#createTicketBtn').on('click', function() {
        var assignedTo = $('#assignToEmployee').val();
        if(!assignedTo) { alert('Please select an employee to assign the ticket to'); return; }
        
        $(this).prop('disabled', true).html('<i class="fa fa-spinner fa-spin"></i> Creating...');
        
        $.ajax({
            url: '<?php echo $_SERVER['PHP_SELF']; ?>', type: 'POST',
            data: { ajax_assign_ticket: true, feedback_id: ticketFeedbackId, feedback_source: ticketFeedbackSource, assigned_to: assignedTo },
            success: function(response) {
                if(response.success) { playNotificationSound(); alert(response.message); $('#ticketModal').modal('hide'); window.location.reload(); } else { alert('Error: ' + response.message); }
                $('#createTicketBtn').prop('disabled', false).html('<i class="fa fa-check"></i> Create Ticket');
            },
            error: function() { alert('Failed to create ticket. Please try again.'); $('#createTicketBtn').prop('disabled', false).html('<i class="fa fa-check"></i> Create Ticket'); }
        });
    });
    
    function scrollToBottom() { var thread = $('#conversationThread'); thread.scrollTop(thread[0].scrollHeight); }
    function escapeHtml(text) { var map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }; return text.replace(/[&<>"']/g, function(m) { return map[m]; }); }
});
</script>
</body>
</html>