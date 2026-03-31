<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
session_start();

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');


// --- ADMIN & DASHBOARD LINK LOGIC ---
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// Get current user's employee data for department-based permissions
$employee_id = '';
$employee_name = '';
$employee_department = '';
$employee_position = '';

if (!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($con, $currentUserName);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$name_safe%') AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    }
}

// --- DEPARTMENT-BASED PERMISSION CHECKS ---
// Check if user is in admin departments (Management or Human Resources)
$is_management_dept = (stripos($employee_department, 'Management') !== false);
$is_hr_dept = (stripos($employee_department, 'Human Resources') !== false || 
               stripos($employee_department, 'Human Resources Department') !== false);

// Check if user is Managing Director
$is_managing_director = (stripos($employee_position, 'managing director') !== false || 
                         stripos($employee_position, 'md') !== false ||
                         stripos($employee_position, 'ceo') !== false);

// Legacy name-based checks (kept for backward compatibility)
$is_abishek = (stripos($employee_name, 'abishek') !== false || stripos($currentUserName, 'abishek') !== false);
$is_keerthi = (stripos($employee_name, 'keerti') !== false || stripos($employee_name, 'keerthi') !== false ||
               stripos($currentUserName, 'keerti') !== false || stripos($currentUserName, 'keerthi') !== false);

// Final access check: Admin departments, Managing Director, or legacy names
$hasAccess = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_abishek || $is_keerthi);

// Define the "Back to Dashboard" URL Logic
// Default: Everyone (including Keerthi) goes to Raise a Ticket
$dashboard_url = 'https://crm.abra-logistic.com/dashboard/raise-a-ticket.php';

// Exception: Only Abishek goes to the main Dashboard
if ($is_abishek) {
    $dashboard_url = 'https://crm.abra-logistic.com/dashboard/';
}

// Block access if not authorized
if(!$hasAccess) {
    die("Access Denied: User '" . htmlspecialchars($currentUserName) . "' does not have permissions to access this page.<br><br>
    <strong>Access Requirements:</strong><br>
    - Management Department<br>
    - Human Resources Department<br>
    - Managing Director position<br><br>
    <a href='".$dashboard_url."'>Back to Dashboard</a>");
}
// --- END ADMIN CHECK ---

// --- UPDATED: Get Departments from Master Table ---
$departments = array();
$dept_query = mysqli_query($con, "SELECT name FROM hr_departments ORDER BY name ASC");
if($dept_query) {
    while($row = mysqli_fetch_assoc($dept_query)) {
        $departments[] = $row['name'];
    }
}
// Add default "General" department
if(!in_array('General', $departments)) {
    array_unshift($departments, 'General');
}

// --- UPDATED: Get Positions from Master Table ---
$positions = array();
$pos_query = mysqli_query($con, "SELECT title FROM hr_positions ORDER BY title ASC");
if($pos_query) {
    while($row = mysqli_fetch_assoc($pos_query)) {
        $positions[] = $row['title'];
    }
}
// Add default "General" position
if(!in_array('General', $positions)) {
    array_unshift($positions, 'General');
}

// Get filter values FIRST - before any operations
$filter_dept = isset($_GET['filter_dept']) ? $_GET['filter_dept'] : (isset($_POST['filter_dept']) ? $_POST['filter_dept'] : 'General');
$filter_pos = isset($_GET['filter_pos']) ? $_GET['filter_pos'] : (isset($_POST['filter_pos']) ? $_POST['filter_pos'] : 'General');
$filter_type = isset($_GET['filter_type']) ? $_GET['filter_type'] : (isset($_POST['filter_type']) ? $_POST['filter_type'] : 'daily');
$filter_by = isset($_GET['filter_by']) ? $_GET['filter_by'] : (isset($_POST['filter_by']) ? $_POST['filter_by'] : 'self');

// --- NEW DETAILED MATRIX DATA (Dept -> Pos -> Type -> By) ---
// We need to fetch count grouped by Dept, Position, Review Type, AND Review By
$matrix_data = array();
$matrix_query = "SELECT department, position, review_type, review_by, COUNT(*) as total 
                 FROM performance_questions 
                 WHERE is_active = 1 
                 GROUP BY department, position, review_type, review_by";
$matrix_result = mysqli_query($con, $matrix_query);

// Structure: $matrix_data[Dept][Position][ReviewType][ReviewBy] = Count
while($row = mysqli_fetch_assoc($matrix_result)) {
    $d = $row['department'];
    $p = $row['position'];
    $rt = $row['review_type'];
    $rb = $row['review_by']; // 'self' or 'manager'
    
    if(!isset($matrix_data[$d])) $matrix_data[$d] = array();
    if(!isset($matrix_data[$d][$p])) $matrix_data[$d][$p] = array();
    if(!isset($matrix_data[$d][$p][$rt])) $matrix_data[$d][$p][$rt] = array();
    
    $matrix_data[$d][$p][$rt][$rb] = $row['total'];
}

$review_types_list = ['daily', 'weekly', 'monthly', 'quarterly', 'halfyearly', 'yearly'];

// Handle CSV Template Download
if(isset($_GET['download_template'])) {
    header('Content-Type: text/csv');
    header('Content-Disposition: attachment; filename="question_import_template.csv"');
    header('Pragma: no-cache');
    header('Expires: 0');
    
    echo "Question Text,Input Type,Options (separated by |),Follow-up Question\n";
    echo "What were your key achievements this period?,text,,\n";
    echo "How would you rate your overall performance?,select,Excellent|Good|Average|Below Average|Poor,Please explain your rating\n";
    // --- MODIFIED LINE BELOW: Added Not Yet and Not Applicable ---
    echo "Did you complete all assigned tasks?,select,Yes|No|Partially|Not Yet|Not Applicable,What challenges did you face?\n";
    echo "What skills would you like to develop?,text,,\n";
    echo "How well did you collaborate with your team?,select,Very Well|Well|Average|Poorly|Very Poorly|Not Applicable,\n";
    echo "What are your goals for the next review period?,text,,\n";
    exit;
}

// Handle Export Questions to CSV
if(isset($_GET['export_questions'])) {
    $export_dept = mysqli_real_escape_string($con, $_GET['export_dept']);
    $export_pos = mysqli_real_escape_string($con, $_GET['export_pos']);
    $export_type = mysqli_real_escape_string($con, $_GET['export_type']);
    $export_by = mysqli_real_escape_string($con, $_GET['export_by']);
    
    $export_query = "SELECT * FROM performance_questions 
                     WHERE department = '$export_dept' 
                     AND position = '$export_pos' 
                     AND review_type = '$export_type' 
                     AND review_by = '$export_by' 
                     AND is_active = 1
                     ORDER BY question_number ASC";
    $export_result = mysqli_query($con, $export_query);
    
    $filename = "questions_" . $export_dept . "_" . $export_pos . "_" . $export_type . "_" . $export_by . "_" . date('Y-m-d') . ".csv";
    
    header('Content-Type: text/csv');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Pragma: no-cache');
    header('Expires: 0');
    
    echo "Question Text,Input Type,Options (separated by |),Follow-up Question\n";
    
    while($row = mysqli_fetch_assoc($export_result)) {
        $question_text = str_replace('"', '""', $row['question_text']);
        $input_type = $row['input_type'];
        
        $options_str = '';
        if($input_type == 'select' && !empty($row['options_json'])) {
            $options = json_decode($row['options_json'], true);
            if($options) {
                $options_str = implode('|', $options);
            }
        }
        
        $sub_question = '';
        if($row['has_sub_question'] && !empty($row['sub_question_text'])) {
            $sub_question = str_replace('"', '""', $row['sub_question_text']);
        }
        
        echo '"' . $question_text . '","' . $input_type . '","' . $options_str . '","' . $sub_question . '"' . "\n";
    }
    exit;
}

// Handle CSV Import
if(isset($_POST['import_csv']) && isset($_FILES['csv_file'])) {
    try {
        $department = mysqli_real_escape_string($con, $_POST['import_department']);
        $position = mysqli_real_escape_string($con, $_POST['import_position']);
        $review_type = mysqli_real_escape_string($con, $_POST['import_review_type']);
        $review_by = mysqli_real_escape_string($con, $_POST['import_review_by']);
        
        if($_FILES['csv_file']['error'] !== UPLOAD_ERR_OK) {
            throw new Exception("File upload error: " . $_FILES['csv_file']['error']);
        }
        
        $file = $_FILES['csv_file']['tmp_name'];
        if(!file_exists($file)) {
            throw new Exception("Uploaded file not found");
        }
        
        $success_count = 0;
        $error_count = 0;
        $errors = array();
        
        function utf8_convert($string) {
            return mb_convert_encoding($string, 'UTF-8', 'UTF-8, Windows-1252, ISO-8859-1');
        }
        
        if(($handle = fopen($file, "r")) !== FALSE) {
            $header = fgetcsv($handle, 1000, ",");
            
            $num_query = mysqli_query($con, "SELECT MAX(question_number) as max_num FROM performance_questions WHERE department='$department' AND position='$position' AND review_type='$review_type' AND review_by='$review_by'");
            $num_row = mysqli_fetch_assoc($num_query);
            $next_num = isset($num_row['max_num']) && $num_row['max_num'] !== null ? intval($num_row['max_num']) + 1 : 1;
            
            $row_number = 1;
            
            while (($data = fgetcsv($handle, 1000, ",")) !== FALSE) {
                $row_number++;
                if(empty($data[0]) || trim($data[0]) == '') continue;
                
                $raw_question = utf8_convert(trim($data[0]));
                $question_text = mysqli_real_escape_string($con, $raw_question);
                
                $raw_input_type = isset($data[1]) ? utf8_convert(trim($data[1])) : 'text';
                $input_type = !empty($raw_input_type) ? mysqli_real_escape_string($con, $raw_input_type) : 'text';
                
                if(!in_array($input_type, ['text', 'select'])) {
                    $input_type = 'text';
                }
                
                $options_json = 'NULL';
                if($input_type == 'select' && isset($data[2]) && !empty(trim($data[2]))) {
                    $raw_options = utf8_convert($data[2]);
                    // Explode by | to get options like "Yes", "No", "Not Applicable"
                    $options = array_map('trim', explode('|', $raw_options));
                    $options = array_filter($options, function($val) { return !empty($val); });
                    if(!empty($options)) {
                        // This stores "Not Applicable" as a string in the JSON
                        $options_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($options))) . "'";
                    }
                }
                
                $has_sub = isset($data[3]) && !empty(trim($data[3])) ? 1 : 0;
                $sub_text = '';
                if($has_sub) {
                    $raw_sub = utf8_convert(trim($data[3]));
                    $sub_text = mysqli_real_escape_string($con, $raw_sub);
                }
                
                $sql = "INSERT INTO performance_questions 
                        (department, position, review_type, review_by, question_number, question_text, input_type, options_json, has_sub_question, sub_question_text, is_active)
                        VALUES 
                        ('$department', '$position', '$review_type', '$review_by', $next_num, '$question_text', '$input_type', $options_json, $has_sub, " . ($has_sub && !empty($sub_text) ? "'$sub_text'" : "NULL") . ", 1)";
                
                if(mysqli_query($con, $sql)) {
                    $success_count++;
                    $next_num++;
                } else {
                    $error_count++;
                    $errors[] = "Row $row_number: " . mysqli_error($con);
                }
            }
            fclose($handle);
        } else {
            throw new Exception("Could not open CSV file");
        }
        
        if($success_count > 0) {
            $_SESSION['success_msg'] = "✓ Successfully imported $success_count question(s)!";
        }
        if($error_count > 0) {
            $_SESSION['error_msg'] = "✗ Failed to import $error_count question(s). " . implode('; ', array_slice($errors, 0, 3));
        }
        
    } catch(Exception $e) {
        $_SESSION['error_msg'] = "✗ Import Error: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($department) . "&filter_pos=" . urlencode($position) . "&filter_type=" . $review_type . "&filter_by=" . $review_by);
    exit;
}

// Handle Bulk Add Questions
if(isset($_POST['bulk_add_questions'])) {
    try {
        $department = mysqli_real_escape_string($con, $_POST['department']);
        $position = mysqli_real_escape_string($con, $_POST['position']);
        $review_type = mysqli_real_escape_string($con, $_POST['review_type']);
        $review_by = mysqli_real_escape_string($con, $_POST['review_by']);
        
        $num_query = mysqli_query($con, "SELECT MAX(question_number) as max_num FROM performance_questions WHERE department='$department' AND position='$position' AND review_type='$review_type' AND review_by='$review_by'");
        $num_row = mysqli_fetch_assoc($num_query);
        $next_num = isset($num_row['max_num']) && $num_row['max_num'] !== null ? intval($num_row['max_num']) + 1 : 1;
        
        $success_count = 0;
        $error_count = 0;
        
        if(isset($_POST['questions']) && is_array($_POST['questions'])) {
            foreach($_POST['questions'] as $index => $question_data) {
                if(!isset($question_data['text']) || empty(trim($question_data['text']))) {
                    continue;
                }
                
                $question_text = mysqli_real_escape_string($con, trim($question_data['text']));
                $input_type = isset($question_data['input_type']) ? mysqli_real_escape_string($con, $question_data['input_type']) : 'text';
                
                if(!in_array($input_type, ['text', 'select'])) {
                    $input_type = 'text';
                }
                
                $has_sub = isset($question_data['has_sub']) ? 1 : 0;
                $sub_text = ($has_sub && isset($question_data['sub_text']) && !empty(trim($question_data['sub_text']))) ? mysqli_real_escape_string($con, trim($question_data['sub_text'])) : '';
                
                $options_json = 'NULL';
                if($input_type == 'select' && isset($question_data['options']) && is_array($question_data['options'])) {
                    $options = array_filter($question_data['options'], function($val) { return !empty(trim($val)); });
                    if(!empty($options)) {
                        $options_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($options))) . "'";
                    }
                }
                
                $sql = "INSERT INTO performance_questions 
                        (department, position, review_type, review_by, question_number, question_text, input_type, options_json, has_sub_question, sub_question_text, is_active)
                        VALUES 
                        ('$department', '$position', '$review_type', '$review_by', $next_num, '$question_text', '$input_type', $options_json, $has_sub, " . ($has_sub && !empty($sub_text) ? "'$sub_text'" : "NULL") . ", 1)";
                
                if(mysqli_query($con, $sql)) {
                    $success_count++;
                    $next_num++;
                } else {
                    $error_count++;
                }
            }
        }
        
        if($success_count > 0) {
            $_SESSION['success_msg'] = "✓ Successfully added $success_count question(s)!";
        }
        
    } catch(Exception $e) {
        $_SESSION['error_msg'] = "✗ Error: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($department) . "&filter_pos=" . urlencode($position) . "&filter_type=" . $review_type . "&filter_by=" . $review_by);
    exit;
}

// Handle Edit Question
if(isset($_POST['edit_question'])) {
    try {
        $q_id = intval($_POST['question_id']);
        $question_text = mysqli_real_escape_string($con, $_POST['edit_question_text']);
        $input_type = mysqli_real_escape_string($con, $_POST['edit_input_type']);
        
        if(!in_array($input_type, ['text', 'select'])) {
            throw new Exception("Invalid input type");
        }
        
        $has_sub = isset($_POST['edit_has_sub']) ? 1 : 0;
        $sub_text = ($has_sub && isset($_POST['edit_sub_text'])) ? mysqli_real_escape_string($con, $_POST['edit_sub_text']) : '';
        
        $options_json = 'NULL';
        if($input_type == 'select' && isset($_POST['edit_options']) && is_array($_POST['edit_options'])) {
            $options = array_filter($_POST['edit_options'], function($val) { return !empty(trim($val)); });
            if(!empty($options)) {
                $options_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($options))) . "'";
            }
        }
        
        $sql = "UPDATE performance_questions SET 
                question_text = '$question_text',
                input_type = '$input_type',
                options_json = $options_json,
                has_sub_question = $has_sub,
                sub_question_text = " . ($has_sub && !empty($sub_text) ? "'$sub_text'" : "NULL") . "
                WHERE id = $q_id";
        
        if(mysqli_query($con, $sql)) {
            $_SESSION['success_msg'] = "✓ Question updated successfully!";
        } else {
            throw new Exception(mysqli_error($con));
        }
        
    } catch(Exception $e) {
        $_SESSION['error_msg'] = "✗ Error updating question: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($filter_dept) . "&filter_pos=" . urlencode($filter_pos) . "&filter_type=" . $filter_type . "&filter_by=" . $filter_by);
    exit;
}

// Handle Bulk Delete
if(isset($_POST['bulk_delete'])) {
    if(isset($_POST['selected_questions']) && is_array($_POST['selected_questions']) && count($_POST['selected_questions']) > 0) {
        $delete_count = 0;
        foreach($_POST['selected_questions'] as $q_id) {
            $q_id = intval($q_id);
            if(mysqli_query($con, "DELETE FROM performance_questions WHERE id = $q_id")) {
                $delete_count++;
            }
        }
        $_SESSION['success_msg'] = "✓ Successfully deleted $delete_count question(s) permanently!";
    } else {
        $_SESSION['error_msg'] = "✗ Please select at least one question to delete.";
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($filter_dept) . "&filter_pos=" . urlencode($filter_pos) . "&filter_type=" . $filter_type . "&filter_by=" . $filter_by);
    exit;
}

// Handle Single Delete
if(isset($_GET['delete_q'])) {
    $q_id = intval($_GET['delete_q']);
    mysqli_query($con, "DELETE FROM performance_questions WHERE id = $q_id");
    $_SESSION['success_msg'] = "✓ Question deleted permanently!";
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($filter_dept) . "&filter_pos=" . urlencode($filter_pos) . "&filter_type=" . $filter_type . "&filter_by=" . $filter_by);
    exit;
}

// Fetch questions for LIST VIEW
$questions_query = "SELECT * FROM performance_questions 
                    WHERE department = '" . mysqli_real_escape_string($con, $filter_dept) . "' 
                    AND position = '" . mysqli_real_escape_string($con, $filter_pos) . "' 
                    AND review_type = '" . mysqli_real_escape_string($con, $filter_type) . "' 
                    AND review_by = '" . mysqli_real_escape_string($con, $filter_by) . "' 
                    AND is_active = 1
                    ORDER BY question_number ASC";
$questions_result = mysqli_query($con, $questions_query);

// Count active questions for LIST VIEW
$count_query = "SELECT COUNT(*) as total FROM performance_questions 
                WHERE department = '" . mysqli_real_escape_string($con, $filter_dept) . "' 
                AND position = '" . mysqli_real_escape_string($con, $filter_pos) . "' 
                AND review_type = '" . mysqli_real_escape_string($con, $filter_type) . "' 
                AND review_by = '" . mysqli_real_escape_string($con, $filter_by) . "' 
                AND is_active = 1";
$count_result = mysqli_query($con, $count_query);
$count_row = mysqli_fetch_assoc($count_result);
$active_count = $count_row['total'];
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Question Management System</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<!-- Select2 CSS -->
<link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { 
    font-family: 'Poppins', sans-serif; 
    background: #f0f4f8; 
    min-height: 100vh; 
    padding: 30px 0; 
}
.container { max-width: 1800px; }

/* Page Header */
.page-header { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    border-radius: 12px; 
    padding: 25px 35px; 
    margin-bottom: 30px; 
    box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
    color: white;
    border: 3px solid #1e40af;
}
.page-header h1 { 
    font-size: 28px; 
    font-weight: 700; 
    color: white; 
    margin: 0; 
    letter-spacing: -0.5px;
}
.page-header p { 
    color: rgba(255, 255, 255, 0.9); 
    font-size: 14px; 
    margin: 8px 0 0 0; 
    font-weight: 400;
}

/* Nav Links */
.nav-links { 
    display: flex; 
    gap: 12px; 
    margin-bottom: 30px; 
    flex-wrap: wrap; 
}
.nav-link { 
    text-decoration: none; 
    padding: 12px 24px; 
    border-radius: 10px; 
    background: #fff; 
    color: #64748b; 
    font-weight: 600; 
    box-shadow: 0 2px 5px rgba(0,0,0,.05); 
    transition: all .3s; 
    font-size: 14px;
    border: 2px solid #e2e8f0;
}
.nav-link:hover { 
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0,0,0,.1);
    text-decoration: none;
}
.nav-link.active { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    color: #fff; 
    border-color: #1e3a8a;
}
.nav-link.dashboard-btn {
    background: linear-gradient(135deg, #475569 0%, #334155 100%);
    color: white;
    border-color: #475569;
}
.nav-link.dashboard-btn:hover {
    background: linear-gradient(135deg, #334155 0%, #1e293b 100%);
    box-shadow: 0 4px 12px rgba(71, 85, 105, 0.4);
    color: white;
}

/* MATRIX STYLES (NEW) */
.matrix-card {
    background: white;
    border-radius: 12px;
    padding: 0;
    margin-bottom: 30px;
    border: 3px solid #e2e8f0;
    box-shadow: 0 2px 10px rgba(0,0,0,0.08);
    overflow: hidden;
    transition: all 0.3s ease;
}
.matrix-header {
    background: #f1f5f9;
    padding: 15px 25px;
    border-bottom: 1px solid #e2e8f0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    cursor: pointer;
}
.matrix-header:hover {
    background: #e2e8f0;
}
.matrix-header h5 {
    margin: 0;
    font-weight: 700;
    color: #1e3a8a;
    font-size: 16px;
}
.matrix-content {
    padding: 20px;
    /* display: none; is handled inline for safety */
    overflow-x: auto;
}
.matrix-table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    overflow: hidden;
}
.matrix-table th {
    text-align: center;
    padding: 12px;
    background: #e2e8f0;
    color: #475569;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    border-bottom: 2px solid #cbd5e1;
}
.matrix-table th.dept-col {
    text-align: left;
    background: #1e3a8a;
    color: white;
    width: 250px;
    position: sticky;
    left: 0;
    z-index: 2;
}
.matrix-table th.pos-col {
    text-align: left;
    background: #334155;
    color: white;
    width: 250px;
    border-right: 1px solid #475569;
}
.matrix-table td {
    padding: 10px;
    border-bottom: 1px solid #e2e8f0;
    border-right: 1px solid #e2e8f0;
    vertical-align: middle;
}
.matrix-table td.dept-cell {
    background: #f8fafc;
    font-weight: 700;
    color: #1e3a8a;
    border-right: 2px solid #e2e8f0;
}
.matrix-table td.pos-cell {
    background: #fff;
    font-weight: 600;
    color: #475569;
    border-right: 2px solid #e2e8f0;
    font-size: 13px;
}
.matrix-count-badge {
    display: inline-block;
    padding: 4px 8px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 700;
    margin: 2px;
    text-decoration: none;
    transition: all 0.2s;
    min-width: 35px;
    text-align: center;
}
.badge-self {
    background: #dbeafe;
    color: #1e40af;
    border: 1px solid #bfdbfe;
}
.badge-self:hover {
    background: #2563eb;
    color: white;
    text-decoration: none;
}
.badge-manager {
    background: #ffedd5;
    color: #c2410c;
    border: 1px solid #fed7aa;
}
.badge-manager:hover {
    background: #ea580c;
    color: white;
    text-decoration: none;
}
.empty-cell {
    background: #fcfcfc;
}

/* Cards & Filters */
.card { 
    background: white; 
    border-radius: 12px; 
    padding: 30px; 
    box-shadow: 0 2px 10px rgba(0,0,0,0.08); 
    margin-bottom: 30px; 
    border: 3px solid #e2e8f0;
}

.filter-bar { 
    background: white; 
    padding: 28px; 
    border-radius: 12px; 
    margin-bottom: 30px; 
    border: 3px solid #e2e8f0; 
    box-shadow: 0 2px 10px rgba(0,0,0,0.08);
}
.filter-row { 
    display: flex; 
    gap: 20px; 
    align-items: flex-end; 
    flex-wrap: wrap; 
}
.filter-group { 
    flex: 1; 
    min-width: 220px; 
}
.filter-group label { 
    font-weight: 600; 
    color: #475569; 
    font-size: 13px; 
    margin-bottom: 10px; 
    display: block; 
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
.filter-group select { 
    width: 100%; 
    padding: 13px 16px; 
    border: 2px solid #e2e8f0; 
    border-radius: 10px; 
    font-size: 15px; 
    font-weight: 500; 
    background: white;
    transition: all .3s;
    color: #1e293b;
    height: 50px;
}
.filter-group select:focus {
    border-color: #1e40af;
    outline: none;
    box-shadow: 0 0 0 4px rgba(30,64,175,0.1);
}

/* Select2 Custom Styling */
.select2-container .select2-selection--single {
    height: 50px !important;
    border: 2px solid #e2e8f0 !important;
    border-radius: 10px !important;
    display: flex !important;
    align-items: center !important;
}
.select2-container--default .select2-selection--single .select2-selection__rendered {
    color: #1e293b !important;
    font-weight: 500 !important;
    font-size: 15px !important;
    padding-left: 16px !important;
    line-height: 46px !important;
}
.select2-container--default .select2-selection--single .select2-selection__arrow {
    height: 46px !important;
    right: 12px !important;
}
.select2-dropdown {
    border: 2px solid #e2e8f0 !important;
    border-radius: 10px !important;
    box-shadow: 0 10px 20px rgba(0,0,0,0.08) !important;
    padding: 5px !important;
}
.select2-search__field {
    border: 1px solid #e2e8f0 !important;
    border-radius: 6px !important;
    padding: 10px !important;
}
.select2-results__option {
    padding: 10px 16px !important;
    font-size: 14px !important;
    border-radius: 6px !important;
    margin-bottom: 2px !important;
}
.select2-results__option--highlighted[aria-selected] {
    background-color: #1e3a8a !important;
    color: white !important;
}

/* Buttons */
.btn-apply { 
    padding: 13px 28px; 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    color: white; 
    border: none; 
    border-radius: 10px; 
    font-weight: 600; 
    cursor: pointer; 
    font-size: 15px;
    box-shadow: 0 4px 12px rgba(30,64,175,0.3);
    transition: all .3s;
    height: 50px;
}
.btn-apply:hover { 
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(30,64,175,0.4);
}
.btn-import {
    padding: 13px 28px;
    background: linear-gradient(135deg, #10b981 0%, #059669 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-weight: 600;
    cursor: pointer;
    font-size: 15px;
    box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
    transition: all 0.3s ease;
    height: 50px;
    margin-left: 10px;
    text-decoration: none;
    display: flex;
    align-items: center;
    gap: 8px;
}
.btn-import:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(16, 185, 129, 0.4);
    color: white;
    text-decoration: none;
}
.btn-export {
    padding: 13px 28px;
    background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-weight: 600;
    cursor: pointer;
    font-size: 15px;
    box-shadow: 0 4px 12px rgba(245, 158, 11, 0.3);
    transition: all 0.3s ease;
    height: 50px;
    margin-left: 10px;
    text-decoration: none;
    display: flex;
    align-items: center;
    gap: 8px;
}
.btn-export:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(245, 158, 11, 0.4);
    color: white;
    text-decoration: none;
}

/* Forms */
.form-group label { 
    font-weight: 600; 
    color: #475569; 
    margin-bottom: 10px; 
    display: block; 
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}
.form-control { 
    border: 2px solid #e2e8f0; 
    border-radius: 10px; 
    padding: 13px 16px; 
    font-size: 15px; 
    transition: all .3s;
    font-weight: 500;
    color: #1e293b;
}
.form-control:focus { 
    border-color: #1e40af; 
    outline: none; 
    box-shadow: 0 0 0 4px rgba(30, 64, 175, 0.1); 
}
.form-control.extra-large { 
    min-height: 140px !important; 
    font-size: 15px !important; 
    padding: 16px !important;
}
.form-control.large { 
    min-height: 110px; 
    font-size: 15px;
    padding: 16px;
}

.btn-primary { 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    border: none; 
    padding: 14px 28px; 
    border-radius: 10px; 
    font-weight: 600; 
    font-size: 15px;
    box-shadow: 0 4px 15px rgba(30,58,138,0.3);
    transition: all .3s;
}
.btn-primary:hover { 
    background: linear-gradient(135deg, #1e40af 0%, #2563eb 100%); 
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(30,58,138,0.4);
}
.btn-danger { 
    background: #ef4444;
    border: none; 
    padding: 10px 18px; 
    border-radius: 10px; 
    font-weight: 600; 
    font-size: 13px; 
    transition: all .3s;
}
.btn-danger:hover {
    background: #dc2626;
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(220,38,38,0.3);
}
.btn-warning { 
    background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); 
    border: none; 
    padding: 10px 18px; 
    border-radius: 10px; 
    font-weight: 600; 
    font-size: 13px; 
    color: white;
    transition: all .3s;
}
.btn-warning:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(245,158,11,0.3);
    color: white;
}
.alert { 
    border-radius: 10px; 
    padding: 16px 22px; 
    margin-bottom: 25px; 
    font-weight: 500;
    font-size: 14px;
    border: none;
    box-shadow: 0 4px 12px rgba(0,0,0,0.05);
}

/* List View */
.questions-list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 25px;
    padding-bottom: 20px;
    border-bottom: 2px solid #e2e8f0;
}
.bulk-actions-bar {
    display: flex;
    gap: 15px;
    align-items: center;
    background: #f8fafc;
    padding: 18px 24px;
    border-radius: 10px;
    margin-bottom: 25px;
    border: 2px solid #e2e8f0;
}
.select-all-checkbox {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 600;
    color: #475569;
    font-size: 14px;
}
.select-all-checkbox input[type="checkbox"] {
    width: 20px;
    height: 20px;
    cursor: pointer;
}
.bulk-delete-btn {
    padding: 12px 24px;
    background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-weight: 600;
    font-size: 14px;
    cursor: pointer;
    transition: all .3s;
    box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3);
}
.bulk-delete-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 18px rgba(239, 68, 68, 0.4);
}
.bulk-delete-btn:disabled {
    background: #94a3b8;
    cursor: not-allowed;
    transform: none;
    box-shadow: none;
}
.selected-count {
    color: #1e3a8a;
    font-weight: 700;
    font-size: 14px;
    padding: 8px 16px;
    background: #e0e7ff;
    border-radius: 20px;
}
.question-list-item { 
    display: flex;
    align-items: flex-start;
    gap: 20px;
    background: white;
    padding: 24px; 
    border-radius: 12px; 
    margin-bottom: 15px; 
    border: 2px solid #e2e8f0;
    border-left: 5px solid #1e3a8a; 
    box-shadow: 0 2px 6px rgba(0,0,0,0.04);
    transition: all .3s;
}
.question-list-item:hover {
    background: #f8fafc;
    transform: translateX(5px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.08);
    border-left-color: #2563eb;
}
.question-checkbox {
    flex-shrink: 0;
    padding-top: 4px;
}
.question-checkbox input[type="checkbox"] {
    width: 20px;
    height: 20px;
    cursor: pointer;
    border: 2px solid #cbd5e1;
    border-radius: 4px;
}
.question-number {
    flex-shrink: 0;
    width: 50px;
    height: 50px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
    color: white;
    border-radius: 10px;
    font-weight: 700;
    font-size: 18px;
    box-shadow: 0 4px 10px rgba(30, 58, 138, 0.2);
}
.question-content {
    flex: 1;
    min-width: 0;
}
.question-text { 
    font-weight: 600; 
    color: #1e3a8a; 
    font-size: 16px; 
    margin-bottom: 12px; 
    line-height: 1.6;
}
.question-meta { 
    font-size: 13px; 
    color: #64748b; 
    line-height: 1.8;
    font-weight: 500;
}
.option-badge { 
    display: inline-block; 
    background: #e2e8f0;
    color: #475569; 
    padding: 5px 13px; 
    border-radius: 14px; 
    margin: 3px; 
    font-size: 12px; 
    font-weight: 600; 
}
.question-actions {
    flex-shrink: 0;
    display: flex;
    gap: 10px;
    align-items: flex-start;
}
.no-questions { 
    text-align: center; 
    padding: 70px; 
    color: #94a3b8; 
}
.option-input-group { 
    margin-bottom: 12px; 
    display: flex; 
    gap: 12px; 
    align-items: center; 
}
.option-input-group input { 
    flex: 1; 
    font-size: 15px;
    padding: 13px 16px;
}
.btn-remove-option { 
    background: #ef4444; 
    color: white; 
    border: none; 
    padding: 10px 14px; 
    border-radius: 8px; 
    cursor: pointer; 
    font-weight: 600;
    transition: all .3s;
}
.btn-remove-option:hover {
    background: #dc2626;
}
.btn-add-option { 
    background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    color: white; 
    border: none; 
    padding: 10px 18px; 
    border-radius: 10px; 
    cursor: pointer; 
    font-weight: 600; 
    font-size: 13px; 
    margin-top: 8px;
    box-shadow: 0 4px 12px rgba(16,185,129,0.2);
    transition: all .3s;
}
.btn-add-option:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(16,185,129,0.3);
}

/* Question Block */
.question-block { 
    background: #f8fafc;
    padding: 32px; 
    border-radius: 12px; 
    margin-bottom: 25px; 
    border: 2px dashed #cbd5e1;
    position: relative; 
    box-shadow: none;
}
.question-block-header { 
    display: flex; 
    justify-content: space-between; 
    align-items: center; 
    margin-bottom: 22px; 
    padding-bottom: 18px;
    border-bottom: 2px solid #e2e8f0;
}
.question-block-title { 
    font-weight: 700; 
    color: #1e3a8a; 
    font-size: 18px; 
}
.btn-remove-question { 
    background: #ef4444;
    color: white; 
    border: none; 
    padding: 10px 18px; 
    border-radius: 10px; 
    cursor: pointer; 
    font-size: 13px; 
    font-weight: 600; 
    transition: all .3s;
}
.btn-remove-question:hover {
    background: #dc2626;
    transform: translateY(-2px);
}
.btn-add-question-block { 
    background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    color: white; 
    border: none; 
    padding: 16px 32px; 
    border-radius: 10px; 
    font-weight: 600; 
    margin-bottom: 28px; 
    font-size: 15px; 
    box-shadow: 0 4px 15px rgba(16,185,129,0.3);
    transition: all .3s;
    display: block;
    width: 100%;
}
.btn-add-question-block:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(16,185,129,0.4);
}

/* Modals */
.modal { 
    display: none; 
    position: fixed; 
    z-index: 1000; 
    left: 0; 
    top: 0; 
    width: 100%; 
    height: 100%; 
    overflow: auto; 
    background-color: rgba(0,0,0,0.6); 
    backdrop-filter: blur(4px);
}
.modal-content { 
    background-color: #ffffff; 
    margin: 3% auto; 
    padding: 0; 
    border-radius: 16px; 
    width: 90%; 
    max-width: 900px; 
    box-shadow: 0 20px 60px rgba(0,0,0,0.2); 
    border: 3px solid #e2e8f0;
    animation: slideDown 0.3s ease-out;
}
@keyframes slideDown {
    from { transform: translateY(-50px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
}
.modal-header { 
    padding: 22px 32px; 
    background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
    color: white; 
    border-radius: 13px 13px 0 0; 
}
.modal-header h2 { 
    margin: 0; 
    font-size: 20px; 
    font-weight: 700; 
}
.modal-body { 
    padding: 32px; 
    max-height: 70vh; 
    overflow-y: auto; 
}
.modal-footer { 
    padding: 22px 32px; 
    border-top: 2px solid #e2e8f0; 
    display: flex; 
    gap: 12px; 
    justify-content: flex-end; 
}
.close { 
    color: white; 
    float: right; 
    font-size: 30px; 
    font-weight: bold; 
    line-height: 1; 
    cursor: pointer; 
    opacity: 0.8;
    transition: all .3s;
}
.close:hover { 
    opacity: 1;
}

select.form-control { 
    height: auto; 
    padding: 13px 16px;
    font-size: 15px;
}
.stats-badge {
    display: inline-block; 
    background: #e0e7ff;
    color: #1e3a8a;
    padding: 7px 17px;
    border-radius: 16px;
    font-size: 12px;
    font-weight: 700;
    margin-left: 15px;
}
.section-divider {
    height: 2px;
    background: #e2e8f0;
    margin: 32px 0;
}
.checkbox-label {
    font-size: 14px;
    font-weight: 600;
    color: #1e3a8a;
    cursor: pointer;
    user-select: none;
}
input[type="checkbox"] {
    width: 19px;
    height: 19px;
    cursor: pointer;
    margin-right: 10px;
}
.btn-secondary {
    background: #64748b;
    color: white;
    border: none; 
    padding: 12px 22px; 
    border-radius: 10px; 
    font-weight: 600; 
    font-size: 14px; 
    transition: all .3s;
}
.btn-secondary:hover {
    background: #475569;
    transform: translateY(-2px);
}
.file-upload-wrapper {
    position: relative;
    width: 100%;
}
.file-upload-input {
    position: absolute;
    left: -9999px;
}
.file-upload-label {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 16px 24px;
    background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
    border: 2px dashed #cbd5e1;
    border-radius: 12px;
    cursor: pointer;
    transition: all 0.3s ease;
    font-weight: 600;
    color: #475569;
    font-size: 14px;
}
.file-upload-label:hover {
    border-color: #1e3a8a;
    background: linear-gradient(135deg, #1e3a8a10 0%, #1e40af10 100%);
    color: #1e3a8a;
}
.file-upload-label i {
    font-size: 20px;
}
.file-name-display {
    margin-top: 12px;
    padding: 12px 16px;
    background: linear-gradient(135deg, #10b98110 0%, #05966910 100%);
    border-radius: 10px;
    font-size: 13px;
    color: #059669;
    font-weight: 600;
    display: none;
    border: 1px solid #10b98130;
}
.download-template-link {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    padding: 12px 20px;
    background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
    color: white;
    text-decoration: none;
    border-radius: 10px;
    font-weight: 600;
    font-size: 14px;
    transition: all 0.3s ease;
    box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}
.download-template-link:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 18px rgba(59, 130, 246, 0.4);
    text-decoration: none;
    color: white;
}
.info-box {
    background: linear-gradient(135deg, #3b82f615 0%, #2563eb15 100%);
    border-left: 4px solid #3b82f6;
    padding: 16px 20px;
    border-radius: 10px;
    margin-bottom: 22px;
    font-size: 14px;
    color: #1e40af;
    line-height: 1.7;
}
.info-box strong {
    display: block;
    margin-bottom: 8px;
    font-size: 15px;
}
</style>
</head>
<body>
<div class="container">

<?php if(isset($_SESSION['success_msg'])): ?>
<div class="alert alert-success"><i class="fas fa-check-circle"></i> <?php echo $_SESSION['success_msg']; unset($_SESSION['success_msg']); ?></div>
<?php endif; ?>

<?php if(isset($_SESSION['error_msg'])): ?>
<div class="alert alert-danger"><i class="fas fa-exclamation-circle"></i> <?php echo $_SESSION['error_msg']; unset($_SESSION['error_msg']); ?></div>
<?php endif; ?>

<div class="page-header">
<h1><i class="fas fa-clipboard-list"></i> Performance Question Management System</h1>
<p>Create and manage multiple review questions for all departments, positions, review types, and review periods</p>
</div>

<div class="nav-links">
<!-- ADDED BACK BUTTON WITH DYNAMIC URL -->
<a href="<?php echo $dashboard_url; ?>" class="nav-link dashboard-btn"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
<a href="#" class="nav-link active"><i class="fas fa-cogs"></i> Question Management</a>
</div>

<!-- COVERAGE MATRIX SECTION (UPDATED) -->
<div class="matrix-card">
    <!-- Header acts as the button to toggle -->
    <div class="matrix-header" onclick="toggleMatrix()">
        <h5><i class="fas fa-th"></i> Coverage Summary Matrix (Click to Expand/Collapse)</h5>
        <i class="fas fa-chevron-down" id="matrixIcon"></i>
    </div>
    
    <!-- Content hidden by default -->
    <div class="matrix-content" id="matrixContent" style="display: none;">
        <table class="matrix-table">
            <thead>
                <tr>
                    <th class="dept-col">Department</th>
                    <th class="pos-col">Position</th>
                    <?php foreach($review_types_list as $rt): ?>
                        <th><?php echo ucfirst($rt); ?></th>
                    <?php endforeach; ?>
                </tr>
            </thead>
            <tbody>
                <?php 
                $has_data = false;
                foreach($departments as $d_name):
                    // Loop positions to see if this department has ANY data, to avoid printing empty blocks
                    // Note: Since departments and positions are not linked in master, we iterate all positions
                    // But we only show rows that have data to keep the table clean.
                    
                    foreach($positions as $p_name):
                        // Check if this Dept+Pos combo has any data in ANY review type
                        $row_has_data = false;
                        foreach($review_types_list as $rt) {
                             if(isset($matrix_data[$d_name][$p_name][$rt])) {
                                 $row_has_data = true;
                                 break;
                             }
                        }
                        
                        // Only display rows that have at least one question configured
                        if($row_has_data):
                            $has_data = true;
                ?>
                <tr>
                    <td class="dept-cell"><?php echo htmlspecialchars($d_name); ?></td>
                    <td class="pos-cell"><?php echo htmlspecialchars($p_name); ?></td>
                    <?php foreach($review_types_list as $rt): 
                        // Get counts for Self (S) and Manager (M)
                        $count_self = isset($matrix_data[$d_name][$p_name][$rt]['self']) ? $matrix_data[$d_name][$p_name][$rt]['self'] : 0;
                        $count_manager = isset($matrix_data[$d_name][$p_name][$rt]['manager']) ? $matrix_data[$d_name][$p_name][$rt]['manager'] : 0;
                        
                        $cell_class = ($count_self > 0 || $count_manager > 0) ? '' : 'empty-cell';
                    ?>
                        <td class="<?php echo $cell_class; ?>">
                            <?php if($count_self > 0): ?>
                            <a href="?filter_dept=<?php echo urlencode($d_name); ?>&filter_pos=<?php echo urlencode($p_name); ?>&filter_type=<?php echo $rt; ?>&filter_by=self" 
                               class="matrix-count-badge badge-self" title="View Self Reviews">
                                S: <?php echo $count_self; ?>
                            </a>
                            <?php endif; ?>
                            
                            <?php if($count_manager > 0): ?>
                            <a href="?filter_dept=<?php echo urlencode($d_name); ?>&filter_pos=<?php echo urlencode($p_name); ?>&filter_type=<?php echo $rt; ?>&filter_by=manager" 
                               class="matrix-count-badge badge-manager" title="View Manager Reviews">
                                M: <?php echo $count_manager; ?>
                            </a>
                            <?php endif; ?>
                            
                            <?php if($count_self == 0 && $count_manager == 0): ?>
                                <span style="color:#cbd5e1">-</span>
                            <?php endif; ?>
                        </td>
                    <?php endforeach; ?>
                </tr>
                <?php 
                        endif; // End if row_has_data
                    endforeach; // End positions
                endforeach; // End departments
                
                if(!$has_data):
                ?>
                <tr>
                    <td colspan="<?php echo count($review_types_list) + 2; ?>" style="text-align:center; padding:20px; color:#94a3b8;">
                        No questions configured yet. Use the "Add New Questions" form below.
                    </td>
                </tr>
                <?php endif; ?>
            </tbody>
        </table>
        <div style="margin-top:15px; font-size:12px; color:#64748b; text-align:right;">
            <span class="matrix-count-badge badge-self">S: Self Review</span> 
            <span class="matrix-count-badge badge-manager">M: Manager Review</span>
        </div>
    </div>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
<h5 style="font-weight:700; color:#1e3a8a; margin-bottom:22px; font-size:17px"><i class="fas fa-filter"></i> Filter Questions</h5>
<form method="GET">
<div class="filter-row">
<div class="filter-group">
<label>Department</label>
<select name="filter_dept" class="searchable-select" id="filter_dept">
<?php foreach($departments as $dept): ?>
<option value="<?php echo htmlspecialchars($dept); ?>" <?php echo ($filter_dept == $dept) ? 'selected' : ''; ?>><?php echo htmlspecialchars($dept); ?></option>
<?php endforeach; ?>
</select>
</div>
<div class="filter-group">
<label>Position</label>
<select name="filter_pos" class="searchable-select" id="filter_pos">
<?php foreach($positions as $pos): ?>
<option value="<?php echo htmlspecialchars($pos); ?>" <?php echo ($filter_pos == $pos) ? 'selected' : ''; ?>><?php echo htmlspecialchars($pos); ?></option>
<?php endforeach; ?>
</select>
</div>
<div class="filter-group">
<label>Review Type</label>
<select name="filter_type" id="filter_type">
<option value="daily" <?php echo ($filter_type == 'daily') ? 'selected' : ''; ?>>Daily Review</option>
<option value="weekly" <?php echo ($filter_type == 'weekly') ? 'selected' : ''; ?>>Weekly Review</option>
<option value="monthly" <?php echo ($filter_type == 'monthly') ? 'selected' : ''; ?>>Monthly Review</option>
<option value="quarterly" <?php echo ($filter_type == 'quarterly') ? 'selected' : ''; ?>>Quarterly Review</option>
<option value="halfyearly" <?php echo ($filter_type == 'halfyearly') ? 'selected' : ''; ?>>Half-Yearly Review</option>
<option value="yearly" <?php echo ($filter_type == 'yearly') ? 'selected' : ''; ?>>Yearly Review</option>
</select>
</div>
<div class="filter-group">
<label>Review By</label>
<select name="filter_by" id="filter_by">
<option value="self" <?php echo ($filter_by == 'self') ? 'selected' : ''; ?>>Self Review</option>
<option value="manager" <?php echo ($filter_by == 'manager') ? 'selected' : ''; ?>>Manager Review</option>
</select>
</div>
<div style="display: flex; gap: 10px;">
<button type="submit" class="btn-apply"><i class="fas fa-search"></i> View</button>
<button type="button" class="btn-import" onclick="openImportModal()"><i class="fas fa-file-import"></i> Import</button>
<a href="?export_questions=1&export_dept=<?php echo urlencode($filter_dept); ?>&export_pos=<?php echo urlencode($filter_pos); ?>&export_type=<?php echo $filter_type; ?>&export_by=<?php echo $filter_by; ?>" class="btn-export"><i class="fas fa-file-export"></i> Export</a>
</div>
</div>
</form>
</div>

<!-- BULK ADD QUESTIONS FORM -->
<div class="card">
<h3 style="margin-bottom:28px; font-weight:700; color:#1e3a8a; font-size:20px">
<i class="fas fa-plus-circle"></i> Add New Questions
</h3>

<form method="POST" id="bulkAddForm">
<div class="row">
<div class="col-md-3">
<div class="form-group">
<label>Target Department</label>
<select name="department" class="form-control searchable-select" required>
<?php foreach($departments as $dept): ?>
<option value="<?php echo htmlspecialchars($dept); ?>" <?php echo ($filter_dept == $dept) ? 'selected' : ''; ?>><?php echo htmlspecialchars($dept); ?></option>
<?php endforeach; ?>
</select>
</div>
</div>

<div class="col-md-3">
<div class="form-group">
<label>Target Position</label>
<select name="position" class="form-control searchable-select" required>
<?php foreach($positions as $pos): ?>
<option value="<?php echo htmlspecialchars($pos); ?>" <?php echo ($filter_pos == $pos) ? 'selected' : ''; ?>><?php echo htmlspecialchars($pos); ?></option>
<?php endforeach; ?>
</select>
</div>
</div>

<div class="col-md-3">
<div class="form-group">
<label>Review Frequency</label>
<select name="review_type" class="form-control" required>
<option value="daily" <?php echo ($filter_type == 'daily') ? 'selected' : ''; ?>>Daily Review</option>
<option value="weekly" <?php echo ($filter_type == 'weekly') ? 'selected' : ''; ?>>Weekly Review</option>
<option value="monthly" <?php echo ($filter_type == 'monthly') ? 'selected' : ''; ?>>Monthly Review</option>
<option value="quarterly" <?php echo ($filter_type == 'quarterly') ? 'selected' : ''; ?>>Quarterly Review</option>
<option value="halfyearly" <?php echo ($filter_type == 'halfyearly') ? 'selected' : ''; ?>>Half-Yearly Review</option>
<option value="yearly" <?php echo ($filter_type == 'yearly') ? 'selected' : ''; ?>>Yearly Review</option>
</select>
</div>
</div>

<div class="col-md-3">
<div class="form-group">
<label>Assessed By</label>
<select name="review_by" class="form-control" required>
<option value="self" <?php echo ($filter_by == 'self') ? 'selected' : ''; ?>>Self Review</option>
<option value="manager" <?php echo ($filter_by == 'manager') ? 'selected' : ''; ?>>Manager Review</option>
</select>
</div>
</div>
</div>

<div class="section-divider"></div>

<h4 style="font-weight:700; color:#1e3a8a; font-size:17px; margin-bottom:22px">
<i class="fas fa-list-ol"></i> Questions to Add
</h4>

<div id="questionsContainer">
<!-- Question blocks will be added here dynamically -->
<div class="question-block" data-question-index="0">
<div class="question-block-header">
<span class="question-block-title">Question #1</span>
<button type="button" class="btn-remove-question" onclick="removeQuestionBlock(this)" style="display:none;"><i class="fas fa-trash-alt"></i> Remove</button>
</div>

<div class="form-group">
<label>Question Text</label>
<textarea name="questions[0][text]" class="form-control extra-large" rows="3" required placeholder="Enter the question text here..."></textarea>
</div>

<div class="row">
<div class="col-md-6">
<div class="form-group">
<label>Input Type</label>
<select name="questions[0][input_type]" class="form-control input-type-select" data-index="0" required>
<option value="text">Text Area (Free text)</option>
<option value="select">Dropdown Selection (Multiple choice)</option>
</select>
</div>
</div>
</div>

<div class="options-container" id="optionsContainer_0" style="display:none; background:white; padding:18px; border-radius:10px; border:2px solid #e2e8f0; margin-bottom:18px;">
<label style="font-size:13px; font-weight:600; color:#475569; margin-bottom:12px; text-transform: uppercase; letter-spacing: 0.5px;">
Dropdown Options
</label>
<div class="options-list">
<div class="option-input-group">
<input type="text" name="questions[0][options][]" class="form-control" placeholder="Option 1">
</div>
</div>
<button type="button" class="btn-add-option" onclick="addOptionToQuestion(0)"><i class="fas fa-plus"></i> Add Option</button>
</div>

<div class="form-group" style="margin-top: 18px;">
<label class="checkbox-label">
<input type="checkbox" name="questions[0][has_sub]" class="has-sub-checkbox" data-index="0"> 
Has follow-up question?
</label>
<textarea name="questions[0][sub_text]" class="form-control large sub-question-text" id="subQuestion_0" rows="3" placeholder="Enter follow-up question text..." style="display:none; margin-top:12px"></textarea>
</div>
</div>
</div>

<button type="button" class="btn-add-question-block" onclick="addQuestionBlock()">
<i class="fas fa-plus-circle"></i> Add Another Question
</button>

<div class="section-divider"></div>

<button type="submit" name="bulk_add_questions" class="btn btn-primary btn-block btn-lg" style="width:100%; padding:16px; font-size:16px;">
<i class="fas fa-save"></i> Save All Questions
</button>
</form>
</div>

<!-- EXISTING QUESTIONS -->
<div class="card">
<div class="questions-list-header">
<div>
<h3 style="margin:0; font-weight:700; color:#1e3a8a; font-size:20px; display:inline-block">
<i class="fas fa-database"></i> Existing Questions
<span class="stats-badge"><?php echo $active_count; ?> Active</span>
</h3>
<p style="font-size:14px; color:#64748b; font-weight:500; margin:10px 0 0 0;">
<strong style="color:#1e3a8a"><?php echo htmlspecialchars($filter_dept); ?></strong> &rarr; 
<strong style="color:#1e3a8a"><?php echo htmlspecialchars($filter_pos); ?></strong> &rarr; 
<strong style="color:#1e3a8a"><?php echo ucfirst($filter_type); ?></strong> &rarr; 
<strong style="color:#1e3a8a"><?php echo ucfirst($filter_by); ?></strong>
</p>
</div>
</div>

<?php if(mysqli_num_rows($questions_result) > 0): ?>

<!-- BULK ACTIONS BAR -->
<form method="POST" id="bulkDeleteForm">
<input type="hidden" name="filter_dept" value="<?php echo htmlspecialchars($filter_dept); ?>">
<input type="hidden" name="filter_pos" value="<?php echo htmlspecialchars($filter_pos); ?>">
<input type="hidden" name="filter_type" value="<?php echo htmlspecialchars($filter_type); ?>">
<input type="hidden" name="filter_by" value="<?php echo htmlspecialchars($filter_by); ?>">

<div class="bulk-actions-bar">
<label class="select-all-checkbox">
<input type="checkbox" id="selectAll" onclick="toggleSelectAll()">
<span>Select All</span>
</label>
<span class="selected-count" id="selectedCount">0 selected</span>
<button type="submit" name="bulk_delete" class="bulk-delete-btn" id="bulkDeleteBtn" disabled onclick="return confirmBulkDelete()">
<i class="fas fa-trash-alt"></i> Delete Selected (Permanent)
</button>
</div>

<!-- QUESTIONS LIST -->
<?php while($q = mysqli_fetch_assoc($questions_result)): ?>
<div class="question-list-item">
<div class="question-checkbox">
<input type="checkbox" name="selected_questions[]" value="<?php echo $q['id']; ?>" class="question-select-checkbox" onchange="updateSelectedCount()">
</div>

<div class="question-number">
<?php echo $q['question_number']; ?>
</div>

<div class="question-content">
<div class="question-text">
<?php echo nl2br(htmlspecialchars($q['question_text'])); ?>
</div>

<div class="question-meta">
<span style="background:#e0e7ff; color:#1e3a8a; padding:5px 13px; border-radius:14px; font-weight:600; font-size:12px;">
<?php echo ucfirst($q['input_type']); ?>
</span>

<?php if($q['input_type'] == 'select' && !empty($q['options_json'])): ?>
<br><div style="margin-top:10px"><small style="color:#64748b; margin-right:6px">Options:</small> 
<?php 
$options = json_decode($q['options_json'], true);
if($options) {
    foreach($options as $opt) {
        echo '<span class="option-badge">' . htmlspecialchars($opt) . '</span>';
    }
}
?>
</div>
<?php endif; ?>

<?php if($q['has_sub_question']): ?>
<div style="margin-top:12px; border-left:3px solid #cbd5e1; padding-left:12px; color:#475569;">
<small style="font-weight:600; display:block; margin-bottom:3px">Follow-up:</small>
<?php echo nl2br(htmlspecialchars($q['sub_question_text'])); ?>
</div>
<?php endif; ?>
</div>
</div>

<div class="question-actions">
<button type="button" class="btn btn-warning" onclick="openEditModal(<?php echo htmlspecialchars(json_encode($q)); ?>)">
<i class="fas fa-edit"></i> Edit
</button>
<a href="?delete_q=<?php echo $q['id']; ?>&filter_dept=<?php echo urlencode($filter_dept); ?>&filter_pos=<?php echo urlencode($filter_pos); ?>&filter_type=<?php echo $filter_type; ?>&filter_by=<?php echo $filter_by; ?>" 
   class="btn btn-danger" 
   onclick="return confirm('⚠️ WARNING: This will PERMANENTLY delete this question. This action cannot be undone!\n\nAre you absolutely sure you want to delete this question?')">
<i class="fas fa-trash-alt"></i> Delete
</a>
</div>
</div>
<?php endwhile; ?>

</form>

<?php else: ?>
<div class="no-questions">
<i class="fas fa-folder-open" style="font-size:56px; margin-bottom:18px; color:#cbd5e1"></i>
<p style="font-weight:600; font-size:17px; color:#64748b">No questions found</p>
<p style="font-size:14px; margin-top:6px; color:#94a3b8">Use the form above to add questions for this category</p>
</div>
<?php endif; ?>
</div>

</div>

<!-- IMPORT CSV MODAL -->
<div id="importModal" class="modal">
<div class="modal-content" style="max-width: 750px;">
<div class="modal-header">
<h2><i class="fas fa-file-import"></i> Import Questions from CSV</h2>
<span class="close" onclick="closeImportModal()">&times;</span>
</div>
<form method="POST" enctype="multipart/form-data" id="importForm">
<div class="modal-body">
<div class="info-box">
    <strong><i class="fas fa-info-circle"></i> CSV Format:</strong>
    Column 1: Question Text (required)<br>
    Column 2: Input Type (text/select)<br>
    Column 3: Options (separated by | for dropdown. Ex: <strong>Yes|No|Partially|Not Yet|Not Applicable</strong>)<br>
    Column 4: Follow-up Question (optional)
</div>

<div style="margin-bottom: 24px; text-align: center;">
    <a href="?download_template=1" class="download-template-link">
        <i class="fas fa-download"></i>
        <span>Download CSV Template</span>
    </a>
</div>

<div class="row">
<div class="col-md-6">
<div class="form-group">
    <label>Department</label>
    <select name="import_department" class="form-control" id="import_dept" required>
        <?php foreach($departments as $dept): ?>
        <option value="<?php echo htmlspecialchars($dept); ?>" <?php echo ($filter_dept == $dept) ? 'selected' : ''; ?>>
            <?php echo htmlspecialchars($dept); ?>
        </option>
        <?php endforeach; ?>
    </select>
</div>
</div>

<div class="col-md-6">
<div class="form-group">
    <label>Position</label>
    <select name="import_position" class="form-control" id="import_pos" required>
        <?php foreach($positions as $pos): ?>
        <option value="<?php echo htmlspecialchars($pos); ?>" <?php echo ($filter_pos == $pos) ? 'selected' : ''; ?>>
            <?php echo htmlspecialchars($pos); ?>
        </option>
        <?php endforeach; ?>
    </select>
</div>
</div>
</div>

<div class="row">
<div class="col-md-6">
<div class="form-group">
    <label>Review Type</label>
    <select name="import_review_type" class="form-control" id="import_type" required>
        <option value="daily" <?php echo ($filter_type == 'daily') ? 'selected' : ''; ?>>Daily</option>
        <option value="weekly" <?php echo ($filter_type == 'weekly') ? 'selected' : ''; ?>>Weekly</option>
        <option value="monthly" <?php echo ($filter_type == 'monthly') ? 'selected' : ''; ?>>Monthly</option>
        <option value="quarterly" <?php echo ($filter_type == 'quarterly') ? 'selected' : ''; ?>>Quarterly</option>
        <option value="halfyearly" <?php echo ($filter_type == 'halfyearly') ? 'selected' : ''; ?>>Half-Yearly</option>
        <option value="yearly" <?php echo ($filter_type == 'yearly') ? 'selected' : ''; ?>>Yearly</option>
    </select>
</div>
</div>

<div class="col-md-6">
<div class="form-group">
    <label>Review By</label>
    <select name="import_review_by" class="form-control" id="import_by" required>
        <option value="self" <?php echo ($filter_by == 'self') ? 'selected' : ''; ?>>Self</option>
        <option value="manager" <?php echo ($filter_by == 'manager') ? 'selected' : ''; ?>>Manager</option>
    </select>
</div>
</div>
</div>

<div class="form-group">
<label>Select CSV File</label>
<div class="file-upload-wrapper">
    <input type="file" name="csv_file" id="csv_file" class="file-upload-input" accept=".csv" required 
           onchange="displayFileName(this)">
    <label for="csv_file" class="file-upload-label">
        <i class="fas fa-cloud-upload-alt"></i>
        <span>Choose CSV File</span>
    </label>
</div>
<div class="file-name-display" id="fileNameDisplay"></div>
</div>
</div>

<div class="modal-footer">
<button type="button" class="btn btn-secondary" onclick="closeImportModal()">Cancel</button>
<button type="submit" name="import_csv" class="btn btn-primary">
    <i class="fas fa-file-import"></i> Import Questions
</button>
</div>
</form>
</div>
</div>

<!-- EDIT MODAL -->
<div id="editModal" class="modal">
<div class="modal-content">
<div class="modal-header">
<h2><i class="fas fa-edit"></i> Edit Question</h2>
<span class="close" onclick="closeEditModal()">&times;</span>
</div>
<form method="POST" id="editForm">
<div class="modal-body">
<input type="hidden" name="question_id" id="edit_question_id">
<input type="hidden" name="filter_dept" value="<?php echo htmlspecialchars($filter_dept); ?>">
<input type="hidden" name="filter_pos" value="<?php echo htmlspecialchars($filter_pos); ?>">
<input type="hidden" name="filter_type" value="<?php echo htmlspecialchars($filter_type); ?>">
<input type="hidden" name="filter_by" value="<?php echo htmlspecialchars($filter_by); ?>">

<div class="form-group">
<label>Question Text</label>
<textarea name="edit_question_text" id="edit_question_text" class="form-control extra-large" rows="5" required></textarea>
</div>

<div class="form-group">
<label>Input Type</label>
<select name="edit_input_type" id="edit_input_type" class="form-control" required>
<option value="text">Text Area (Free text)</option>
<option value="select">Dropdown Selection (Multiple choice)</option>
</select>
</div>

<div id="edit_options_container" style="display:none; background:#f8fafc; padding:18px; border-radius:10px; margin-bottom:18px; border:2px solid #e2e8f0;">
<label style="font-size:13px; margin-bottom:12px; font-weight: 600; color: #475569; text-transform: uppercase; letter-spacing: 0.5px;">Dropdown Options</label>
<div id="edit_options_list"></div>
<button type="button" class="btn-add-option" onclick="addEditOption()"><i class="fas fa-plus"></i> Add Option</button>
</div>

<div class="form-group" style="margin-top: 18px;">
<label class="checkbox-label">
<input type="checkbox" name="edit_has_sub" id="edit_has_sub"> 
Has follow-up question?
</label>
<textarea name="edit_sub_text" id="edit_sub_text" class="form-control large" rows="4" placeholder="Enter follow-up question..." style="display:none; margin-top:12px"></textarea>
</div>
</div>
<div class="modal-footer">
<button type="button" class="btn btn-secondary" onclick="closeEditModal()">Cancel</button>
<button type="submit" name="edit_question" class="btn btn-primary">Update Question</button>
</div>
</form>
</div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<!-- Select2 JS -->
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
let questionCount = 1;

function toggleMatrix() {
    $('#matrixContent').slideToggle();
    $('#matrixIcon').toggleClass('fa-chevron-down fa-chevron-up');
}

$(document).ready(function() {
    // Initialize Select2 on elements with .searchable-select class
    $('.searchable-select').select2({
        width: '100%',
        placeholder: "Select an option",
        allowClear: true
    });
    
    // Sync filter values with import modal
    $('#filter_dept').on('change', function() {
        $('#import_dept').val($(this).val());
    });
    
    $('#filter_pos').on('change', function() {
        $('#import_pos').val($(this).val());
    });
    
    $('#filter_type').on('change', function() {
        $('#import_type').val($(this).val());
    });
    
    $('#filter_by').on('change', function() {
        $('#import_by').val($(this).val());
    });
});

// Bulk Selection Functions
function toggleSelectAll() {
    const selectAllCheckbox = document.getElementById('selectAll');
    const checkboxes = document.querySelectorAll('.question-select-checkbox');
    
    checkboxes.forEach(checkbox => {
        checkbox.checked = selectAllCheckbox.checked;
    });
    
    updateSelectedCount();
}

function updateSelectedCount() {
    const checkboxes = document.querySelectorAll('.question-select-checkbox:checked');
    const count = checkboxes.length;
    const countDisplay = document.getElementById('selectedCount');
    const bulkDeleteBtn = document.getElementById('bulkDeleteBtn');
    const selectAllCheckbox = document.getElementById('selectAll');
    
    countDisplay.textContent = count + ' selected';
    bulkDeleteBtn.disabled = count === 0;
    
    // Update select all checkbox state
    const totalCheckboxes = document.querySelectorAll('.question-select-checkbox');
    selectAllCheckbox.checked = count === totalCheckboxes.length && count > 0;
}

function confirmBulkDelete() {
    const checkboxes = document.querySelectorAll('.question-select-checkbox:checked');
    const count = checkboxes.length;
    
    if(count === 0) {
        alert('Please select at least one question to delete.');
        return false;
    }
    
    return confirm('⚠️ WARNING: You are about to PERMANENTLY delete ' + count + ' question(s).\n\nThis action CANNOT be undone and the questions will be removed from the database forever.\n\nAre you absolutely sure you want to proceed?');
}

function displayFileName(input) {
    const display = document.getElementById('fileNameDisplay');
    if (input.files && input.files[0]) {
        display.textContent = '📄 ' + input.files[0].name;
        display.style.display = 'block';
    }
}

function openImportModal() {
    // Sync current filter values
    document.getElementById('import_dept').value = document.getElementById('filter_dept').value;
    document.getElementById('import_pos').value = document.getElementById('filter_pos').value;
    document.getElementById('import_type').value = document.getElementById('filter_type').value;
    document.getElementById('import_by').value = document.getElementById('filter_by').value;
    document.getElementById('importModal').style.display = 'block';
}

function closeImportModal() {
    document.getElementById('importModal').style.display = 'none';
    document.getElementById('importForm').reset();
    document.getElementById('fileNameDisplay').style.display = 'none';
}

// Add new question block
function addQuestionBlock() {
    const container = document.getElementById('questionsContainer');
    const newIndex = questionCount;
    
    const questionBlock = document.createElement('div');
    questionBlock.className = 'question-block';
    questionBlock.setAttribute('data-question-index', newIndex);
    questionBlock.innerHTML = `
        <div class="question-block-header">
            <span class="question-block-title">Question #${newIndex + 1}</span>
            <button type="button" class="btn-remove-question" onclick="removeQuestionBlock(this)"><i class="fas fa-trash-alt"></i> Remove</button>
        </div>

        <div class="form-group">
            <label>Question Text</label>
            <textarea name="questions[${newIndex}][text]" class="form-control extra-large" rows="3" required placeholder="Enter the question text here..."></textarea>
        </div>

        <div class="row">
            <div class="col-md-6">
                <div class="form-group">
                    <label>Input Type</label>
                    <select name="questions[${newIndex}][input_type]" class="form-control input-type-select" data-index="${newIndex}" required>
                        <option value="text">Text Area (Free text)</option>
                        <option value="select">Dropdown Selection (Multiple choice)</option>
                    </select>
                </div>
            </div>
        </div>

        <div class="options-container" id="optionsContainer_${newIndex}" style="display:none; background:white; padding:18px; border-radius:10px; border:2px solid #e2e8f0; margin-bottom:18px;">
            <label style="font-size:13px; font-weight:600; color:#475569; margin-bottom:12px; text-transform: uppercase; letter-spacing: 0.5px;">Dropdown Options</label>
            <div class="options-list">
                <div class="option-input-group">
                    <input type="text" name="questions[${newIndex}][options][]" class="form-control" placeholder="Option 1">
                </div>
            </div>
            <button type="button" class="btn-add-option" onclick="addOptionToQuestion(${newIndex})"><i class="fas fa-plus"></i> Add Option</button>
        </div>

        <div class="form-group" style="margin-top: 18px;">
            <label class="checkbox-label">
                <input type="checkbox" name="questions[${newIndex}][has_sub]" class="has-sub-checkbox" data-index="${newIndex}"> 
                Has follow-up question?
            </label>
            <textarea name="questions[${newIndex}][sub_text]" class="form-control large sub-question-text" id="subQuestion_${newIndex}" rows="3" placeholder="Enter follow-up question text..." style="display:none; margin-top:12px"></textarea>
        </div>
    `;
    
    container.appendChild(questionBlock);
    questionCount++;
    
    // Re-attach event listeners
    attachEventListeners();
    updateRemoveButtons();
    
    // Scroll to new question
    questionBlock.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

// Remove question block
function removeQuestionBlock(btn) {
    if(confirm('Are you sure you want to remove this question?')) {
        const block = btn.closest('.question-block');
        block.remove();
        updateQuestionNumbers();
        updateRemoveButtons();
    }
}

// Update question numbers after removal
function updateQuestionNumbers() {
    const blocks = document.querySelectorAll('.question-block');
    blocks.forEach((block, index) => {
        block.querySelector('.question-block-title').innerHTML = `Question #${index + 1}`;
    });
}

// Update remove buttons visibility
function updateRemoveButtons() {
    const blocks = document.querySelectorAll('.question-block');
    blocks.forEach((block, index) => {
        const removeBtn = block.querySelector('.btn-remove-question');
        if (blocks.length > 1) {
            removeBtn.style.display = 'inline-block';
        } else {
            removeBtn.style.display = 'none';
        }
    });
}

// Add option to question
function addOptionToQuestion(index) {
    const container = document.getElementById(`optionsContainer_${index}`).querySelector('.options-list');
    const optionCount = container.querySelectorAll('.option-input-group').length + 1;
    
    const optionGroup = document.createElement('div');
    optionGroup.className = 'option-input-group';
    optionGroup.innerHTML = `
        <input type="text" name="questions[${index}][options][]" class="form-control" placeholder="Option ${optionCount}">
        <button type="button" class="btn-remove-option" onclick="this.closest('.option-input-group').remove()"><i class="fas fa-times"></i></button>
    `;
    
    container.appendChild(optionGroup);
}

// Attach event listeners
function attachEventListeners() {
    // Input type change
    document.querySelectorAll('.input-type-select').forEach(select => {
        select.removeEventListener('change', handleInputTypeChange);
        select.addEventListener('change', handleInputTypeChange);
    });
    
    // Sub-question checkbox
    document.querySelectorAll('.has-sub-checkbox').forEach(checkbox => {
        checkbox.removeEventListener('change', handleSubQuestionChange);
        checkbox.addEventListener('change', handleSubQuestionChange);
    });
}

function handleInputTypeChange(e) {
    const index = e.target.getAttribute('data-index');
    const optionsContainer = document.getElementById(`optionsContainer_${index}`);
    if (e.target.value === 'select') {
        optionsContainer.style.display = 'block';
    } else {
        optionsContainer.style.display = 'none';
    }
}

function handleSubQuestionChange(e) {
    const index = e.target.getAttribute('data-index');
    const subQuestion = document.getElementById(`subQuestion_${index}`);
    if (e.target.checked) {
        subQuestion.style.display = 'block';
    } else {
        subQuestion.style.display = 'none';
    }
}

// Edit Modal Functions
function openEditModal(question) {
    document.getElementById('edit_question_id').value = question.id;
    document.getElementById('edit_question_text').value = question.question_text;
    document.getElementById('edit_input_type').value = question.input_type;
    
    // Handle options
    const optionsContainer = document.getElementById('edit_options_container');
    const optionsList = document.getElementById('edit_options_list');
    optionsList.innerHTML = '';
    
    if (question.input_type === 'select') {
        optionsContainer.style.display = 'block';
        if (question.options_json) {
            const options = JSON.parse(question.options_json);
            options.forEach((opt, index) => {
                const optionGroup = document.createElement('div');
                optionGroup.className = 'option-input-group';
                optionGroup.innerHTML = `
                    <input type="text" name="edit_options[]" class="form-control" value="${opt}" placeholder="Option ${index + 1}">
                    <button type="button" class="btn-remove-option" onclick="this.closest('.option-input-group').remove()"><i class="fas fa-times"></i></button>
                `;
                optionsList.appendChild(optionGroup);
            });
        } else {
            addEditOption();
        }
    } else {
        optionsContainer.style.display = 'none';
    }
    
    // Handle sub-question
    document.getElementById('edit_has_sub').checked = question.has_sub_question == 1;
    document.getElementById('edit_sub_text').value = question.sub_question_text || '';
    document.getElementById('edit_sub_text').style.display = question.has_sub_question == 1 ? 'block' : 'none';
    
    document.getElementById('editModal').style.display = 'block';
}

function closeEditModal() {
    document.getElementById('editModal').style.display = 'none';
}

function addEditOption() {
    const optionsList = document.getElementById('edit_options_list');
    const optionCount = optionsList.querySelectorAll('.option-input-group').length + 1;
    
    const optionGroup = document.createElement('div');
    optionGroup.className = 'option-input-group';
    optionGroup.innerHTML = `
        <input type="text" name="edit_options[]" class="form-control" placeholder="Option ${optionCount}">
        <button type="button" class="btn-remove-option" onclick="this.closest('.option-input-group').remove()"><i class="fas fa-times"></i></button>
    `;
    
    optionsList.appendChild(optionGroup);
}

// Edit input type change
document.getElementById('edit_input_type').addEventListener('change', function() {
    const optionsContainer = document.getElementById('edit_options_container');
    if (this.value === 'select') {
        optionsContainer.style.display = 'block';
        const optionsList = document.getElementById('edit_options_list');
        if (optionsList.children.length === 0) {
            addEditOption();
        }
    } else {
        optionsContainer.style.display = 'none';
    }
});

// Edit sub-question checkbox
document.getElementById('edit_has_sub').addEventListener('change', function() {
    const subQuestion = document.getElementById('edit_sub_text');
    subQuestion.style.display = this.checked ? 'block' : 'none';
});

// Close modal when clicking outside
window.onclick = function(event) {
    const importModal = document.getElementById('importModal');
    const editModal = document.getElementById('editModal');
    if (event.target == importModal) {
        closeImportModal();
    }
    if (event.target == editModal) {
        closeEditModal();
    }
}

// Form validation before submit
document.getElementById('bulkAddForm').addEventListener('submit', function(e) {
    const questionBlocks = document.querySelectorAll('.question-block');
    let hasValidQuestion = false;
    
    questionBlocks.forEach(block => {
        const textarea = block.querySelector('textarea[name*="[text]"]');
        if(textarea && textarea.value.trim() !== '') {
            hasValidQuestion = true;
        }
    });
    
    if(!hasValidQuestion) {
        e.preventDefault();
        alert('Please add at least one question before submitting!');
        return false;
    }
    
    return confirm(`You are about to save ${questionBlocks.length} question(s). Continue?`);
});

// Initialize
document.addEventListener('DOMContentLoaded', function() {
    attachEventListeners();
    updateRemoveButtons();
    updateSelectedCount(); // Initialize selected count on page load
});

// Auto-hide alerts
setTimeout(function() {
    $('.alert').fadeOut('slow');
}, 6000);
</script>
</body>
</html>