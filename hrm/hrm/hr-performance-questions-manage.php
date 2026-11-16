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

date_default_timezone_set($_SESSION['ge_timezone']);
isUser();

// Admin Check
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek', 'Keerthi Patil', 'Keerthi', 'keerthi');

$isAdmin = false;
foreach($authorized_admin_names as $admin_name) {
    if(stripos($currentUserName, $admin_name) !== false) {
        $isAdmin = true;
        break;
    }
}

if(!$isAdmin) {
    die("Access Denied: Only HR can access this page");
}

// Get all departments from employees
$dept_query = mysqli_query($con, "SELECT DISTINCT department FROM hr_employees WHERE department IS NOT NULL AND department != '' ORDER BY department");
$departments = array();
while($row = mysqli_fetch_assoc($dept_query)) {
    $departments[] = $row['department'];
}

// Add default "General" department
array_unshift($departments, 'General');

// Handle Bulk Add Questions
if(isset($_POST['bulk_add_questions'])) {
    $department = mysqli_real_escape_string($con, $_POST['department']);
    $review_type = mysqli_real_escape_string($con, $_POST['review_type']);
    $review_by = mysqli_real_escape_string($con, $_POST['review_by']);
    
    // Get current max question number
    $num_query = mysqli_query($con, "SELECT MAX(question_number) as max_num FROM performance_questions WHERE department='$department' AND review_type='$review_type' AND review_by='$review_by'");
    $num_row = mysqli_fetch_assoc($num_query);
    $next_num = ($num_row['max_num'] ?? 0) + 1;
    
    $success_count = 0;
    $error_count = 0;
    
    // Loop through all question sets
    if(isset($_POST['questions']) && is_array($_POST['questions'])) {
        foreach($_POST['questions'] as $index => $question_data) {
            $question_text = mysqli_real_escape_string($con, trim($question_data['text']));
            
            // Skip empty questions
            if(empty($question_text)) continue;
            
            $input_type = mysqli_real_escape_string($con, $question_data['input_type']);
            $has_sub = isset($question_data['has_sub']) ? 1 : 0;
            $sub_text = $has_sub && !empty($question_data['sub_text']) ? mysqli_real_escape_string($con, trim($question_data['sub_text'])) : '';
            
            // Handle options for select type
            $options_json = 'NULL';
            if($input_type == 'select' && isset($question_data['options'])) {
                $options = array_filter($question_data['options'], function($val) { return !empty(trim($val)); });
                if(!empty($options)) {
                    $options_json = "'" . mysqli_real_escape_string($con, json_encode(array_values($options))) . "'";
                }
            }
            
            $sql = "INSERT INTO performance_questions 
                    (department, review_type, review_by, question_number, question_text, input_type, options_json, has_sub_question, sub_question_text, is_active)
                    VALUES 
                    ('$department', '$review_type', '$review_by', $next_num, '$question_text', '$input_type', $options_json, $has_sub, " . ($has_sub && !empty($sub_text) ? "'$sub_text'" : "NULL") . ", 1)";
            
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
    if($error_count > 0) {
        $_SESSION['error_msg'] = "✗ Failed to add $error_count question(s).";
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . urlencode($department) . "&filter_type=" . $review_type . "&filter_by=" . $review_by);
    exit;
}

// Handle Edit Question
if(isset($_POST['edit_question'])) {
    $q_id = intval($_POST['question_id']);
    $question_text = mysqli_real_escape_string($con, $_POST['edit_question_text']);
    $input_type = mysqli_real_escape_string($con, $_POST['edit_input_type']);
    $has_sub = isset($_POST['edit_has_sub']) ? 1 : 0;
    $sub_text = $has_sub ? mysqli_real_escape_string($con, $_POST['edit_sub_text']) : '';
    
    // Handle options for select type
    $options_json = 'NULL';
    if($input_type == 'select' && isset($_POST['edit_options'])) {
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
        $_SESSION['error_msg'] = "✗ Error updating question: " . mysqli_error($con);
    }
    
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . $_GET['filter_dept'] . "&filter_type=" . $_GET['filter_type'] . "&filter_by=" . $_GET['filter_by']);
    exit;
}

// Handle Delete Question
if(isset($_GET['delete_q'])) {
    $q_id = intval($_GET['delete_q']);
    mysqli_query($con, "UPDATE performance_questions SET is_active = 0 WHERE id = $q_id");
    $_SESSION['success_msg'] = "✓ Question deleted successfully!";
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . $_GET['filter_dept'] . "&filter_type=" . $_GET['filter_type'] . "&filter_by=" . $_GET['filter_by']);
    exit;
}

// Handle Restore Question
if(isset($_GET['restore_q'])) {
    $q_id = intval($_GET['restore_q']);
    mysqli_query($con, "UPDATE performance_questions SET is_active = 1 WHERE id = $q_id");
    $_SESSION['success_msg'] = "✓ Question restored successfully!";
    header("Location: " . $_SERVER['PHP_SELF'] . "?filter_dept=" . $_GET['filter_dept'] . "&filter_type=" . $_GET['filter_type'] . "&filter_by=" . $_GET['filter_by']);
    exit;
}

// Get filter values
$filter_dept = isset($_GET['filter_dept']) ? $_GET['filter_dept'] : 'General';
$filter_type = isset($_GET['filter_type']) ? $_GET['filter_type'] : 'daily';
$filter_by = isset($_GET['filter_by']) ? $_GET['filter_by'] : 'self';

// Fetch questions
$questions_query = "SELECT * FROM performance_questions 
                    WHERE department = '" . mysqli_real_escape_string($con, $filter_dept) . "' 
                    AND review_type = '" . mysqli_real_escape_string($con, $filter_type) . "' 
                    AND review_by = '" . mysqli_real_escape_string($con, $filter_by) . "' 
                    ORDER BY question_number ASC";
$questions_result = mysqli_query($con, $questions_query);

// Count active questions
$count_query = "SELECT COUNT(*) as total FROM performance_questions 
                WHERE department = '" . mysqli_real_escape_string($con, $filter_dept) . "' 
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
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { 
    font-family: 'Inter', sans-serif; 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
    min-height: 100vh; 
    padding: 30px 0; 
}
.container { max-width: 1800px; }

.page-header { 
    background: white; 
    border-radius: 20px; 
    padding: 40px; 
    margin-bottom: 30px; 
    box-shadow: 0 20px 60px rgba(0,0,0,0.15); 
}
.page-header h1 { 
    font-size: 36px; 
    font-weight: 800; 
    color: #1a202c; 
    margin: 0; 
    letter-spacing: -0.5px;
}
.page-header p { 
    color: #718096; 
    font-size: 16px; 
    margin: 8px 0 0 0; 
    font-weight: 500;
}

.nav-links { 
    display: flex; 
    gap: 12px; 
    margin-bottom: 30px; 
    flex-wrap: wrap; 
}
.nav-link { 
    text-decoration: none; 
    padding: 14px 26px; 
    border-radius: 12px; 
    background: #fff; 
    color: #64748b; 
    font-weight: 700; 
    box-shadow: 0 4px 6px rgba(0,0,0,.08); 
    transition: all .3s; 
    font-size: 15px;
}
.nav-link:hover, .nav-link.active { 
    background: #667eea; 
    color: #fff; 
    text-decoration: none; 
    transform: translateY(-2px);
    box-shadow: 0 8px 12px rgba(102,126,234,.3);
}

.card { 
    background: white; 
    border-radius: 24px; 
    padding: 40px; 
    box-shadow: 0 10px 40px rgba(0,0,0,0.12); 
    margin-bottom: 30px; 
}

.filter-bar { 
    background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%); 
    padding: 30px; 
    border-radius: 16px; 
    margin-bottom: 30px; 
    border: 3px solid #cbd5e1; 
    box-shadow: 0 4px 15px rgba(0,0,0,0.08);
}
.filter-row { 
    display: flex; 
    gap: 20px; 
    align-items: center; 
    flex-wrap: wrap; 
}
.filter-group { 
    flex: 1; 
    min-width: 220px; 
}
.filter-group label { 
    font-weight: 700; 
    color: #334155; 
    font-size: 15px; 
    margin-bottom: 8px; 
    display: block; 
    letter-spacing: 0.3px;
}
.filter-group select { 
    width: 100%; 
    padding: 14px 18px; 
    border: 3px solid #cbd5e1; 
    border-radius: 10px; 
    font-size: 16px; 
    font-weight: 600; 
    background: white;
    transition: all .3s;
}
.filter-group select:focus {
    border-color: #667eea;
    outline: none;
    box-shadow: 0 0 0 4px rgba(102,126,234,0.1);
}

.btn-apply { 
    padding: 14px 32px; 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
    color: white; 
    border: none; 
    border-radius: 10px; 
    font-weight: 700; 
    cursor: pointer; 
    margin-top: 28px; 
    font-size: 16px;
    box-shadow: 0 4px 12px rgba(102,126,234,0.4);
    transition: all .3s;
}
.btn-apply:hover { 
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(102,126,234,0.5);
}

.form-group label { 
    font-weight: 800; 
    color: #1e293b; 
    margin-bottom: 10px; 
    display: block; 
    font-size: 16px;
    letter-spacing: 0.3px;
}

.form-control { 
    border: 3px solid #e2e8f0; 
    border-radius: 12px; 
    padding: 18px 20px; 
    font-size: 17px; 
    line-height: 1.6;
    transition: all .3s;
    font-weight: 500;
}
.form-control:focus { 
    border-color: #667eea; 
    outline: none; 
    box-shadow: 0 0 0 5px rgba(102, 126, 234, 0.15); 
}

.form-control.extra-large { 
    min-height: 180px !important; 
    font-size: 18px !important; 
    line-height: 1.8 !important;
    padding: 22px !important;
    font-weight: 500 !important;
}

.form-control.large { 
    min-height: 140px; 
    font-size: 17px; 
    line-height: 1.7;
    padding: 20px;
}

.btn-primary { 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
    border: none; 
    padding: 18px 36px; 
    border-radius: 12px; 
    font-weight: 800; 
    font-size: 17px;
    box-shadow: 0 6px 20px rgba(102,126,234,0.4);
    transition: all .3s;
}
.btn-primary:hover { 
    background: linear-gradient(135deg, #5568d3 0%, #6a4190 100%); 
    transform: translateY(-2px);
    box-shadow: 0 8px 25px rgba(102,126,234,0.5);
}

.btn-danger { 
    background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); 
    border: none; 
    padding: 10px 20px; 
    border-radius: 10px; 
    font-weight: 700; 
    font-size: 14px; 
    transition: all .3s;
}
.btn-danger:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(239,68,68,0.4);
}

.btn-success { 
    background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    border: none; 
    padding: 10px 20px; 
    border-radius: 10px; 
    font-weight: 700; 
    font-size: 14px; 
    transition: all .3s;
}
.btn-success:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(16,185,129,0.4);
}

.btn-warning { 
    background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); 
    border: none; 
    padding: 10px 20px; 
    border-radius: 10px; 
    font-weight: 700; 
    font-size: 14px; 
    color: white;
    transition: all .3s;
}
.btn-warning:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(245,158,11,0.4);
}

.alert { 
    border-radius: 14px; 
    padding: 18px 24px; 
    margin-bottom: 25px; 
    font-weight: 600;
    font-size: 16px;
    border: none;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.question-item { 
    background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%); 
    padding: 35px; 
    border-radius: 16px; 
    margin-bottom: 20px; 
    border-left: 6px solid #667eea; 
    box-shadow: 0 4px 15px rgba(0,0,0,0.08);
    transition: all .3s;
}
.question-item:hover {
    transform: translateY(-3px);
    box-shadow: 0 8px 25px rgba(0,0,0,0.12);
}

.question-item.inactive { 
    opacity: 0.6; 
    border-left-color: #dc2626; 
}

.question-text { 
    font-weight: 700; 
    color: #0f172a; 
    font-size: 20px; 
    margin-bottom: 16px; 
    line-height: 1.7;
    letter-spacing: 0.2px;
}

.question-meta { 
    font-size: 15px; 
    color: #475569; 
    line-height: 2;
    font-weight: 500;
}

.option-badge { 
    display: inline-block; 
    background: linear-gradient(135deg, #ddd6fe 0%, #c4b5fd 100%); 
    color: #5b21b6; 
    padding: 8px 18px; 
    border-radius: 25px; 
    margin: 5px; 
    font-size: 14px; 
    font-weight: 700; 
    box-shadow: 0 2px 6px rgba(91,33,182,0.2);
}

.no-questions { 
    text-align: center; 
    padding: 80px; 
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
    font-size: 16px;
    padding: 16px 18px;
}

.btn-remove-option { 
    background: #ef4444; 
    color: white; 
    border: none; 
    padding: 12px 16px; 
    border-radius: 8px; 
    cursor: pointer; 
    font-weight: 700;
    transition: all .3s;
}
.btn-remove-option:hover {
    background: #dc2626;
    transform: scale(1.05);
}

.btn-add-option { 
    background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    color: white; 
    border: none; 
    padding: 12px 24px; 
    border-radius: 10px; 
    cursor: pointer; 
    font-weight: 700; 
    font-size: 15px; 
    margin-top: 10px;
    box-shadow: 0 4px 12px rgba(16,185,129,0.3);
    transition: all .3s;
}
.btn-add-option:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(16,185,129,0.4);
}

.question-block { 
    background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%); 
    padding: 35px; 
    border-radius: 16px; 
    margin-bottom: 25px; 
    border: 4px solid #f59e0b; 
    position: relative; 
    box-shadow: 0 6px 20px rgba(245,158,11,0.2);
}

.question-block-header { 
    display: flex; 
    justify-content: space-between; 
    align-items: center; 
    margin-bottom: 25px; 
    padding-bottom: 20px;
    border-bottom: 3px dashed #f59e0b;
}

.question-block-title { 
    font-weight: 800; 
    color: #92400e; 
    font-size: 20px; 
    letter-spacing: 0.5px;
}

.btn-remove-question { 
    background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); 
    color: white; 
    border: none; 
    padding: 10px 20px; 
    border-radius: 10px; 
    cursor: pointer; 
    font-size: 14px; 
    font-weight: 700; 
    box-shadow: 0 4px 12px rgba(239,68,68,0.3);
    transition: all .3s;
}
.btn-remove-question:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 15px rgba(239,68,68,0.4);
}

.btn-add-question-block { 
    background: linear-gradient(135deg, #10b981 0%, #059669 100%); 
    color: white; 
    border: none; 
    padding: 16px 32px; 
    border-radius: 12px; 
    font-weight: 800; 
    margin-bottom: 25px; 
    font-size: 17px; 
    box-shadow: 0 6px 20px rgba(16,185,129,0.4);
    transition: all .3s;
    display: block;
    width: 100%;
}
.btn-add-question-block:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 25px rgba(16,185,129,0.5);
}

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
    border-radius: 20px; 
    width: 90%; 
    max-width: 1000px; 
    box-shadow: 0 20px 60px rgba(0,0,0,0.4); 
    animation: slideDown 0.3s ease-out;
}

@keyframes slideDown {
    from { transform: translateY(-50px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
}

.modal-header { 
    padding: 30px 40px; 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
    color: white; 
    border-radius: 20px 20px 0 0; 
}

.modal-header h2 { 
    margin: 0; 
    font-size: 26px; 
    font-weight: 800; 
    letter-spacing: 0.3px;
}

.modal-body { 
    padding: 40px; 
    max-height: 70vh; 
    overflow-y: auto; 
}

.modal-footer { 
    padding: 25px 40px; 
    border-top: 3px solid #e2e8f0; 
    display: flex; 
    gap: 12px; 
    justify-content: flex-end; 
}

.close { 
    color: white; 
    float: right; 
    font-size: 38px; 
    font-weight: bold; 
    line-height: 1; 
    cursor: pointer; 
    transition: all .3s;
}
.close:hover { 
    color: #fde68a; 
    transform: rotate(90deg);
}

select.form-control { 
    height: auto; 
    padding: 16px 18px;
    font-size: 16px;
}

.stats-badge {
    display: inline-block;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 8px 20px;
    border-radius: 20px;
    font-size: 14px;
    font-weight: 700;
    margin-left: 15px;
    box-shadow: 0 4px 12px rgba(102,126,234,0.3);
}

.section-divider {
    height: 4px;
    background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
    border-radius: 2px;
    margin: 30px 0;
}

.checkbox-label {
    font-size: 16px;
    font-weight: 600;
    color: #334155;
    cursor: pointer;
    user-select: none;
}

input[type="checkbox"] {
    width: 20px;
    height: 20px;
    cursor: pointer;
    margin-right: 10px;
}

.action-buttons {
    margin-top: 20px;
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
}

.btn-secondary {
    background: #64748b;
    color: white;
    border: none;
    padding: 14px 28px;
    border-radius: 10px;
    font-weight: 700;
    font-size: 15px;
    transition: all .3s;
}

.btn-secondary:hover {
    background: #475569;
    transform: translateY(-2px);
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
<p>Create and manage multiple review questions for all departments, review types, and review periods</p>
</div>

<div class="nav-links">
<a href="performance-reviews.php" class="nav-link"><i class="fas fa-arrow-left"></i> Back to Performance System</a>
<a href="hr-employees-list.php" class="nav-link"><i class="fas fa-users"></i> Employee List</a>
<a href="#" class="nav-link active"><i class="fas fa-cogs"></i> Question Management</a>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
<h5 style="font-weight:800; color:#0f172a; margin-bottom:20px; font-size:20px"><i class="fas fa-filter"></i> Filter & View Questions</h5>
<form method="GET">
<div class="filter-row">
<div class="filter-group">
<label><i class="fas fa-building"></i> Department</label>
<select name="filter_dept">
<?php foreach($departments as $dept): ?>
<option value="<?php echo htmlspecialchars($dept); ?>" <?php echo ($filter_dept == $dept) ? 'selected' : ''; ?>><?php echo htmlspecialchars($dept); ?></option>
<?php endforeach; ?>
</select>
</div>
<div class="filter-group">
<label><i class="fas fa-calendar-alt"></i> Review Type</label>
<select name="filter_type">
<option value="daily" <?php echo ($filter_type == 'daily') ? 'selected' : ''; ?>>Daily Review</option>
<option value="weekly" <?php echo ($filter_type == 'weekly') ? 'selected' : ''; ?>>Weekly Review</option>
<option value="monthly" <?php echo ($filter_type == 'monthly') ? 'selected' : ''; ?>>Monthly Review</option>
<option value="quarterly" <?php echo ($filter_type == 'quarterly') ? 'selected' : ''; ?>>Quarterly Review</option>
<option value="halfyearly" <?php echo ($filter_type == 'halfyearly') ? 'selected' : ''; ?>>Half-Yearly Review</option>
<option value="yearly" <?php echo ($filter_type == 'yearly') ? 'selected' : ''; ?>>Yearly Review</option>
</select>
</div>
<div class="filter-group">
<label><i class="fas fa-user-check"></i> Review By</label>
<select name="filter_by">
<option value="self" <?php echo ($filter_by == 'self') ? 'selected' : ''; ?>>Self Review</option>
<option value="manager" <?php echo ($filter_by == 'manager') ? 'selected' : ''; ?>>Manager Review</option>
</select>
</div>
<div>
<button type="submit" class="btn-apply"><i class="fas fa-search"></i> View Questions</button>
</div>
</div>
</form>
</div>

<!-- BULK ADD QUESTIONS FORM -->
<div class="card">
<h3 style="margin-bottom:25px; font-weight:800; color:#0f172a; font-size:26px">
<i class="fas fa-plus-square"></i> Add Multiple Questions at Once
</h3>
<p style="color:#64748b; font-size:16px; margin-bottom:30px; font-weight:500">
Fill in the details below and add as many questions as you need for this review configuration. All questions will be saved together.
</p>

<form method="POST" id="bulkAddForm">
<div class="row">
<div class="col-md-4">
<div class="form-group">
<label><i class="fas fa-building"></i> Select Department</label>
<select name="department" class="form-control" required>
<?php foreach($departments as $dept): ?>
<option value="<?php echo htmlspecialchars($dept); ?>" <?php echo ($filter_dept == $dept) ? 'selected' : ''; ?>><?php echo htmlspecialchars($dept); ?></option>
<?php endforeach; ?>
</select>
</div>
</div>

<div class="col-md-4">
<div class="form-group">
<label><i class="fas fa-calendar-alt"></i> Select Review Type</label>
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

<div class="col-md-4">
<div class="form-group">
<label><i class="fas fa-user-check"></i> Select Review By</label>
<select name="review_by" class="form-control" required>
<option value="self" <?php echo ($filter_by == 'self') ? 'selected' : ''; ?>>Self Review</option>
<option value="manager" <?php echo ($filter_by == 'manager') ? 'selected' : ''; ?>>Manager Review</option>
</select>
</div>
</div>
</div>

<div class="section-divider"></div>

<h4 style="font-weight:800; color:#0f172a; font-size:22px; margin-bottom:25px">
<i class="fas fa-list-ol"></i> Questions to Add
</h4>

<div id="questionsContainer">
<!-- Question blocks will be added here dynamically -->
<div class="question-block" data-question-index="0">
<div class="question-block-header">
<span class="question-block-title"><i class="fas fa-question-circle"></i> Question #1</span>
<button type="button" class="btn-remove-question" onclick="removeQuestionBlock(this)" style="display:none;"><i class="fas fa-trash-alt"></i> Remove Question</button>
</div>

<div class="form-group">
<label><i class="fas fa-edit"></i> Question Text</label>
<textarea name="questions[0][text]" class="form-control extra-large" rows="5" required placeholder="Enter your detailed question here... (You can write as much as you need)"></textarea>
</div>

<div class="row">
<div class="col-md-6">
<div class="form-group">
<label><i class="fas fa-list-ul"></i> Answer Input Type</label>
<select name="questions[0][input_type]" class="form-control input-type-select" data-index="0" required>
<option value="text">Text Area (For detailed answers)</option>
<option value="select">Dropdown Selection (Multiple choice)</option>
</select>
</div>
</div>
</div>

<div class="options-container" id="optionsContainer_0" style="display:none;">
<label style="font-size:16px; font-weight:700; color:#1e293b; margin-bottom:15px">
<i class="fas fa-list"></i> Dropdown Options (Add all possible answer choices)
</label>
<div class="options-list">
<div class="option-input-group">
<input type="text" name="questions[0][options][]" class="form-control" placeholder="Option 1">
</div>
</div>
<button type="button" class="btn-add-option" onclick="addOptionToQuestion(0)"><i class="fas fa-plus-circle"></i> Add Another Option</button>
</div>

<div class="form-group" style="margin-top: 25px;">
<label class="checkbox-label">
<input type="checkbox" name="questions[0][has_sub]" class="has-sub-checkbox" data-index="0"> 
<i class="fas fa-indent"></i> This question has a follow-up sub-question
</label>
<textarea name="questions[0][sub_text]" class="form-control large sub-question-text" id="subQuestion_0" rows="4" placeholder="Enter your follow-up/sub-question text here... (optional)" style="display:none; margin-top:15px"></textarea>
</div>
</div>
</div>

<button type="button" class="btn-add-question-block" onclick="addQuestionBlock()">
<i class="fas fa-plus-circle"></i> Add Another Question to This Review
</button>

<div class="section-divider"></div>

<button type="submit" name="bulk_add_questions" class="btn btn-primary btn-block btn-lg" style="padding:20px; font-size:19px">
<i class="fas fa-save"></i> Save All Questions to Database
</button>
</form>
</div>

<!-- EXISTING QUESTIONS -->
<div class="card">
<h3 style="margin-bottom:20px; font-weight:800; color:#0f172a; font-size:26px">
<i class="fas fa-database"></i> All Saved Questions
<span class="stats-badge"><?php echo $active_count; ?> Active</span>
</h3>
<p style="font-size:15px; color:#64748b; font-weight:600; margin-bottom:25px">
Viewing: <strong style="color:#667eea"><?php echo htmlspecialchars($filter_dept); ?></strong> → 
<strong style="color:#667eea"><?php echo ucfirst($filter_type); ?> Review</strong> → 
<strong style="color:#667eea"><?php echo ucfirst($filter_by); ?> Assessment</strong>
</p>

<?php if(mysqli_num_rows($questions_result) > 0): ?>
<?php while($q = mysqli_fetch_assoc($questions_result)): ?>
<div class="question-item <?php echo $q['is_active'] ? '' : 'inactive'; ?>">
<div class="question-text">
<strong style="color:#667eea">Question #<?php echo $q['question_number']; ?>:</strong> 
<?php echo nl2br(htmlspecialchars($q['question_text'])); ?>
<?php if($q['is_active'] == 0): ?>
<span style="color:#dc2626; font-size:14px; margin-left:12px; font-weight:800">
<i class="fas fa-ban"></i> DELETED
</span>
<?php endif; ?>
</div>

<div class="question-meta">
<strong><i class="fas fa-tag"></i> Answer Type:</strong> 
<span style="background:#dbeafe; color:#1e40af; padding:4px 12px; border-radius:12px; font-weight:700">
<?php echo ucfirst($q['input_type']); ?>
</span>

<?php if($q['input_type'] == 'select' && !empty($q['options_json'])): ?>
<br><strong style="margin-top:10px; display:inline-block"><i class="fas fa-list-ul"></i> Available Options:</strong> 
<?php 
$options = json_decode($q['options_json'], true);
if($options) {
    foreach($options as $opt) {
        echo '<span class="option-badge">' . htmlspecialchars($opt) . '</span>';
    }
}
?>
<?php endif; ?>

<?php if($q['has_sub_question']): ?>
<br><strong style="margin-top:10px; display:inline-block"><i class="fas fa-indent"></i> Follow-up Question:</strong> 
<div style="background:#fff7ed; padding:15px; border-radius:10px; margin-top:8px; border-left:4px solid #f59e0b">
<?php echo nl2br(htmlspecialchars($q['sub_question_text'])); ?>
</div>
<?php endif; ?>
</div>

<div class="action-buttons">
<?php if($q['is_active']): ?>
<button type="button" class="btn btn-warning" onclick="openEditModal(<?php echo htmlspecialchars(json_encode($q)); ?>)">
<i class="fas fa-edit"></i> Edit Question
</button>
<a href="?delete_q=<?php echo $q['id']; ?>&filter_dept=<?php echo urlencode($filter_dept); ?>&filter_type=<?php echo $filter_type; ?>&filter_by=<?php echo $filter_by; ?>" 
   class="btn btn-danger" 
   onclick="return confirm('Are you sure you want to delete this question?')">
<i class="fas fa-trash-alt"></i> Delete Question
</a>
<?php else: ?>
<a href="?restore_q=<?php echo $q['id']; ?>&filter_dept=<?php echo urlencode($filter_dept); ?>&filter_type=<?php echo $filter_type; ?>&filter_by=<?php echo $filter_by; ?>" 
   class="btn btn-success">
<i class="fas fa-undo"></i> Restore Question
</a>
<?php endif; ?>
</div>
</div>
<?php endwhile; ?>
<?php else: ?>
<div class="no-questions">
<i class="fas fa-inbox" style="font-size:80px; margin-bottom:20px; color:#cbd5e1"></i>
<p style="font-weight:700; font-size:20px; color:#64748b">No questions found for this configuration</p>
<p style="font-size:16px; margin-top:10px">Use the form above to add your first questions for this review setup</p>
</div>
<?php endif; ?>
</div>

</div>

<!-- EDIT MODAL -->
<div id="editModal" class="modal">
<div class="modal-content">
<div class="modal-header">
<h2><i class="fas fa-edit"></i> Edit Question Details</h2>
<span class="close" onclick="closeEditModal()">&times;</span>
</div>
<form method="POST" id="editForm">
<div class="modal-body">
<input type="hidden" name="question_id" id="edit_question_id">
<input type="hidden" name="filter_dept" value="<?php echo htmlspecialchars($filter_dept); ?>">
<input type="hidden" name="filter_type" value="<?php echo htmlspecialchars($filter_type); ?>">
<input type="hidden" name="filter_by" value="<?php echo htmlspecialchars($filter_by); ?>">

<div class="form-group">
<label><i class="fas fa-edit"></i> Question Text</label>
<textarea name="edit_question_text" id="edit_question_text" class="form-control extra-large" rows="5" required></textarea>
</div>

<div class="form-group">
<label><i class="fas fa-list-ul"></i> Answer Input Type</label>
<select name="edit_input_type" id="edit_input_type" class="form-control" required>
<option value="text">Text Area (For detailed answers)</option>
<option value="select">Dropdown Selection (Multiple choice)</option>
</select>
</div>

<div id="edit_options_container" style="display:none;">
<label style="font-size:16px; font-weight:700; color:#1e293b; margin-bottom:15px">
<i class="fas fa-list"></i> Dropdown Options
</label>
<div id="edit_options_list"></div>
<button type="button" class="btn-add-option" onclick="addEditOption()"><i class="fas fa-plus-circle"></i> Add Another Option</button>
</div>

<div class="form-group" style="margin-top: 25px;">
<label class="checkbox-label">
<input type="checkbox" name="edit_has_sub" id="edit_has_sub"> 
<i class="fas fa-indent"></i> This question has a follow-up sub-question
</label>
<textarea name="edit_sub_text" id="edit_sub_text" class="form-control large" rows="4" placeholder="Enter your follow-up/sub-question text here... (optional)" style="display:none; margin-top:15px"></textarea>
</div>
</div>
<div class="modal-footer">
<button type="button" class="btn btn-secondary" onclick="closeEditModal()">
<i class="fas fa-times"></i> Cancel
</button>
<button type="submit" name="edit_question" class="btn btn-primary">
<i class="fas fa-check-circle"></i> Update Question
</button>
</div>
</form>
</div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script>
let questionCount = 1;

// Add new question block
function addQuestionBlock() {
    const container = document.getElementById('questionsContainer');
    const newIndex = questionCount;
    
    const questionBlock = document.createElement('div');
    questionBlock.className = 'question-block';
    questionBlock.setAttribute('data-question-index', newIndex);
    questionBlock.innerHTML = `
        <div class="question-block-header">
            <span class="question-block-title"><i class="fas fa-question-circle"></i> Question #${newIndex + 1}</span>
            <button type="button" class="btn-remove-question" onclick="removeQuestionBlock(this)"><i class="fas fa-trash-alt"></i> Remove Question</button>
        </div>

        <div class="form-group">
            <label><i class="fas fa-edit"></i> Question Text</label>
            <textarea name="questions[${newIndex}][text]" class="form-control extra-large" rows="5" required placeholder="Enter your detailed question here... (You can write as much as you need)"></textarea>
        </div>

        <div class="row">
            <div class="col-md-6">
                <div class="form-group">
                    <label><i class="fas fa-list-ul"></i> Answer Input Type</label>
                    <select name="questions[${newIndex}][input_type]" class="form-control input-type-select" data-index="${newIndex}" required>
                        <option value="text">Text Area (For detailed answers)</option>
                        <option value="select">Dropdown Selection (Multiple choice)</option>
                    </select>
                </div>
            </div>
        </div>

        <div class="options-container" id="optionsContainer_${newIndex}" style="display:none;">
            <label style="font-size:16px; font-weight:700; color:#1e293b; margin-bottom:15px">
                <i class="fas fa-list"></i> Dropdown Options (Add all possible answer choices)
            </label>
            <div class="options-list">
                <div class="option-input-group">
                    <input type="text" name="questions[${newIndex}][options][]" class="form-control" placeholder="Option 1">
                </div>
            </div>
            <button type="button" class="btn-add-option" onclick="addOptionToQuestion(${newIndex})"><i class="fas fa-plus-circle"></i> Add Another Option</button>
        </div>

        <div class="form-group" style="margin-top: 25px;">
            <label class="checkbox-label">
                <input type="checkbox" name="questions[${newIndex}][has_sub]" class="has-sub-checkbox" data-index="${newIndex}"> 
                <i class="fas fa-indent"></i> This question has a follow-up sub-question
            </label>
            <textarea name="questions[${newIndex}][sub_text]" class="form-control large sub-question-text" id="subQuestion_${newIndex}" rows="4" placeholder="Enter your follow-up/sub-question text here... (optional)" style="display:none; margin-top:15px"></textarea>
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
        block.querySelector('.question-block-title').innerHTML = `<i class="fas fa-question-circle"></i> Question #${index + 1}`;
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
    const modal = document.getElementById('editModal');
    if (event.target == modal) {
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
});

// Auto-hide alerts
setTimeout(function() {
    $('.alert').fadeOut('slow');
}, 6000);
</script>
</body>
</html>