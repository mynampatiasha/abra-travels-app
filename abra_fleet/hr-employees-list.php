<?php
// =========================================================================
// EMPLOYEE LIST PAGE - Enhanced with Employee Type & Birthday Ticket System
// =========================================================================

ob_start(); // Output buffering to prevent header errors
error_reporting(E_ALL);
ini_set('display_errors', 0);
error_reporting(0);
session_start();
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

// Ensure database handles emojis (for birthday cakes 🎂)
mysqli_set_charset($con, 'utf8mb4');

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
// isUser();

$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// FILE SIZE CONFIGURATION (in MB)
// =========================================================================
define('MAX_PHOTO_SIZE_MB', 2);  // 2 MB for profile photos
define('MAX_DOCUMENT_SIZE_MB', 5);  // 5 MB for documents
define('MAX_PHOTO_SIZE_BYTES', MAX_PHOTO_SIZE_MB * 1024 * 1024);
define('MAX_DOCUMENT_SIZE_BYTES', MAX_DOCUMENT_SIZE_MB * 1024 * 1024);

// =========================================================================
// 🎂 ENHANCED AUTOMATED BIRTHDAY TICKET SYSTEMisUser();
// =========================================================================
function runBirthdayCheck($con) {
    // 1. Identify Target HR (Keerthi - ABRA033)
    $hr_query = mysqli_query($con, "
        SELECT id, employee_id, name, email 
        FROM hr_employees 
        WHERE employee_id = 'ABRA033' 
        AND LOWER(status) = 'active' 
        LIMIT 1
    ");
    
    if(!$hr_query || mysqli_num_rows($hr_query) == 0) {
        error_log("Birthday Check: HR employee ABRA033 (Keerthi) not found");
        return; // Exit if HR not found
    }
    
    $hr_row = mysqli_fetch_assoc($hr_query);
    $hr_db_id = $hr_row['id'];
    $hr_name = $hr_row['name'];
    
    // 2. Get Tomorrow's Date (Month-Day format)
    $tomorrow_md = date('m-d', strtotime('+1 day'));
    $display_date = date('d M Y', strtotime('+1 day'));
    $current_year = date('Y');
    
    // 3. Find Active Employees with Birthday Tomorrow
    $bday_sql = "
        SELECT employee_id, name, department, email, dob
        FROM hr_employees 
        WHERE DATE_FORMAT(dob, '%m-%d') = '$tomorrow_md' 
        AND LOWER(status) = 'active'
        AND employee_id != 'ABRA033'
    ";
    
    $bday_result = mysqli_query($con, $bday_sql);
    
    if(!$bday_result) {
        error_log("Birthday Check SQL Error: " . mysqli_error($con));
        return;
    }
    
    $tickets_created = 0;
    
    if(mysqli_num_rows($bday_result) > 0) {
        while($emp = mysqli_fetch_assoc($bday_result)) {
            
            // 4. Create Unique Tag to prevent duplicate tickets for the same year
            $ref_tag = "[Auto-Birthday: {$emp['employee_id']}-$current_year]";
            
            // 5. Check if ticket already exists for this birthday this year
            $check_sql = "
                SELECT id, ticket_number, status 
                FROM tickets 
                WHERE message LIKE '%$ref_tag%' 
                LIMIT 1
            ";
            $check_ticket = mysqli_query($con, $check_sql);
            
            if($check_ticket && mysqli_num_rows($check_ticket) == 0) {
                // 6. No existing ticket - Create New Ticket
                $ticket_number = 'BDAY-' . date('Ymd') . '-' . rand(1000, 9999);
                
                // Calculate age
                $age = '';
                if($emp['dob']) {
                    $dob_ts = strtotime($emp['dob']);
                    $age_calc = floor((strtotime($display_date) - $dob_ts) / (365.25 * 24 * 60 * 60));
                    $age = " (Turning $age_calc)";
                }
                
                $subject = "🎂 Birthday Alert: {$emp['name']} - Tomorrow $display_date$age";
                
                $message = "🎉 **UPCOMING BIRTHDAY NOTIFICATION**\n" .
                           "========================================\n" .
                           "👤 Employee: **{$emp['name']}** ({$emp['employee_id']})\n" .
                           "🏢 Department: {$emp['department']}\n" .
                           "📅 Birthday Date: Tomorrow - $display_date$age\n" .
                           "📧 Email: {$emp['email']}\n" .
                           "========================================\n" .
                           "ℹ️ ACTION REQUIRED:\n" .
                           "• Send birthday wishes email/message\n" .
                           "• Arrange for cake/celebration if applicable\n" .
                           "• Update internal birthday calendar\n" .
                           "• Coordinate with team for any surprises\n\n" .
                           "This is an automated notification generated by the HR system.\n\n" .
                           $ref_tag;
                
                $safe_subject = mysqli_real_escape_string($con, $subject);
                $safe_message = mysqli_real_escape_string($con, $message);
                $created_by = 'System - Birthday Bot';
                
                // Priority: Low (it's a celebration!)
                $priority = 'Low';
                $status = 'Open';
                
                $insert_sql = "
                    INSERT INTO tickets 
                    (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at) 
                    VALUES 
                    ('$ticket_number', '$created_by', '$safe_subject', '$safe_message', '$status', '$priority', '$hr_db_id', NOW(), NOW())
                ";
                
                if(mysqli_query($con, $insert_sql)) {
                    $tickets_created++;
                    error_log("Birthday Ticket Created: #$ticket_number for {$emp['name']} assigned to $hr_name");
                } else {
                    error_log("Birthday Ticket Creation Failed: " . mysqli_error($con));
                }
            } else {
                // Ticket already exists
                $existing = mysqli_fetch_assoc($check_ticket);
                error_log("Birthday Ticket Already Exists: #{$existing['ticket_number']} for {$emp['name']} (Status: {$existing['status']})");
            }
        }
    }
    
    // Log summary
    if($tickets_created > 0) {
        error_log("Birthday Check Complete: $tickets_created new birthday tickets created");
    }
}

// Execute the birthday check on page load
runBirthdayCheck($con);

// =========================================================================
// FETCH MASTER DATA FOR FILTERS
// =========================================================================
$dept_sql = "SELECT * FROM hr_departments ORDER BY name ASC";
$dept_query = mysqli_query($con, $dept_sql);

$pos_sql = "SELECT * FROM hr_positions ORDER BY title ASC";
$pos_query = mysqli_query($con, $pos_sql);

$loc_sql = "SELECT * FROM hr_work_locations ORDER BY location_name ASC";
$loc_query = mysqli_query($con, $loc_sql);

// FETCH COMPANIES FOR FILTER
$company_sql = "SELECT * FROM hr_companies ORDER BY company_name ASC";
$company_query = mysqli_query($con, $company_sql);

// =========================================================================
// LOAD LOCATION DATA (Country/State)
// =========================================================================
define('LOCATIONS_FILE', __DIR__ . '/global_locations.json');
$location_data = [];
if (file_exists(LOCATIONS_FILE)) {
    $json_content = file_get_contents(LOCATIONS_FILE);
    $location_data = json_decode($json_content, true);
}

// =========================================================================
// ADMIN CHECK
// =========================================================================
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');

$isAdmin = false;
foreach($authorized_admin_names as $admin_name) {
    if(stripos($currentUserName, $admin_name) !== false || stripos($admin_name, $currentUserName) !== false) {
        $isAdmin = true;
        break;
    }
}

// =========================================================================
// DELETE DOCUMENT (ADMIN ONLY)
// =========================================================================
if (isset($_GET['delete_doc']) && $isAdmin) {
    $doc_id = intval($_GET['delete_doc']);
    
    $doc_query = mysqli_query($con, "SELECT filepath FROM hr_employee_documents WHERE id = $doc_id");
    if ($doc_row = mysqli_fetch_assoc($doc_query)) {
        $filepath = $doc_row['filepath'];
        
        if (mysqli_query($con, "DELETE FROM hr_employee_documents WHERE id = $doc_id")) {
            if (file_exists($filepath)) {
                unlink($filepath);
            }
            $_SESSION['success_message'] = "Document deleted successfully";
        } else {
            $_SESSION['error_message'] = "Failed to delete document";
        }
    }
    header("Location: $current_page");
    exit;
}

// =========================================================================
// CSV EXPORT - TEMPLATE
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] == 'template') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=hr_employees_template_' . date('Y-m-d') . '.csv');
    
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    
    fputcsv($output, array(
        'Employee ID', 'Name', 'Gender', 'DOB', 'Blood Group', 'Personal Email', 'Phone', 'Alt Phone', 'Address', 'Country', 'State',
        'Aadhar', 'PAN', 'Emergency Contact', 'Relationship', 'Emergency Phone', 'Emergency Alt Phone',
        'Degree', 'Year', 'Percentage/CGPA',
        'Bank Account', 'IFSC', 'Bank Branch',
        'Official Email', 'Hire Date', 'Department', 'Position', 'Employee Type', 'Salary', 'Work Location', 'Timings', 'Company Name', 'Status'
    ));
    
    fclose($output);
    exit;
}

// =========================================================================
// CSV EXPORT - FULL DATA
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] == 'csv') {
    $export_query = "SELECT 
        employee_id, name, gender, dob, blood_group, personal_email, phone, alt_phone, address, country, state,
        aadhar_card, pan_number, contact_name, relationship, contact_phone, contact_alt_phone,
        university_degree, year_completion, percentage_cgpa,
        bank_account_number, ifsc_code, bank_branch,
        email, hire_date, department, position, employee_type, salary, work_location, timings, company_name, status
    FROM hr_employees ORDER BY id DESC";
    
    $export_result = mysqli_query($con, $export_query);
    
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=hr_employees_data_' . date('Y-m-d_His') . '.csv');
    
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    
    fputcsv($output, array(
        'Employee ID', 'Name', 'Gender', 'DOB', 'Blood Group', 'Personal Email', 'Phone', 'Alt Phone', 'Address', 'Country', 'State',
        'Aadhar', 'PAN', 'Emergency Contact', 'Relationship', 'Emergency Phone', 'Emergency Alt Phone',
        'Degree', 'Year', 'Percentage/CGPA',
        'Bank Account', 'IFSC', 'Bank Branch',
        'Official Email', 'Hire Date', 'Department', 'Position', 'Employee Type', 'Salary', 'Work Location', 'Timings', 'Company Name', 'Status'
    ));
    
    while ($row = mysqli_fetch_assoc($export_result)) {
        fputcsv($output, $row);
    }
    
    fclose($output);
    exit;
}

// =========================================================================
// CSV IMPORT
// =========================================================================
if (isset($_POST['import_csv']) && isset($_FILES['import_file'])) {
    $file = $_FILES['import_file'];
    $errors = array();
    $success_count = 0;
    $failed_count = 0;
    $total_records = 0;
    
    if ($file['error'] === UPLOAD_ERR_OK) {
        $ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        
        if ($ext === 'csv') {
            $handle = fopen($file['tmp_name'], 'r');
            $header = fgetcsv($handle);
            
            while (($data = fgetcsv($handle)) !== FALSE) {
                $total_records++;
                
                $employee_id = trim($data[0] ?? '');
                $name = trim($data[1] ?? '');
                $gender = trim($data[2] ?? '');
                $dob = trim($data[3] ?? '');
                $blood_group = trim($data[4] ?? '');
                $personal_email = trim($data[5] ?? '');
                $phone = trim($data[6] ?? '');
                $alt_phone = trim($data[7] ?? '');
                $address = trim($data[8] ?? '');
                $country = trim($data[9] ?? '');
                $state = trim($data[10] ?? '');
                $aadhar_card = trim($data[11] ?? '');
                $pan_number = strtoupper(trim($data[12] ?? ''));
                $contact_name = trim($data[13] ?? '');
                $relationship = trim($data[14] ?? '');
                $contact_phone = trim($data[15] ?? '');
                $contact_alt_phone = trim($data[16] ?? '');
                $university_degree = trim($data[17] ?? '');
                $year_completion = trim($data[18] ?? '');
                $percentage_cgpa = trim($data[19] ?? '');
                $bank_account_number = trim($data[20] ?? '');
                $ifsc_code = strtoupper(trim($data[21] ?? ''));
                $bank_branch = trim($data[22] ?? '');
                $email = trim($data[23] ?? '');
                $hire_date = trim($data[24] ?? '');
                $department = trim($data[25] ?? '');
                $position = trim($data[26] ?? '');
                $employee_type = trim($data[27] ?? ''); // New Field
                $salary = trim($data[28] ?? '0');
                $work_location = trim($data[29] ?? '');
                $timings = trim($data[30] ?? '');
                $company_name = trim($data[31] ?? '');
                $status = trim($data[32] ?? 'Active');
                
                if (empty($name) || empty($email) || empty($phone)) {
                    $failed_count++;
                    $errors[] = "Row $total_records: Missing required fields";
                    continue;
                }
                
                $insert = "INSERT INTO hr_employees (
                    employee_id, name, gender, dob, blood_group, personal_email, phone, alt_phone, address, country, state,
                    aadhar_card, pan_number, contact_name, relationship, contact_phone, contact_alt_phone,
                    university_degree, year_completion, percentage_cgpa,
                    bank_account_number, ifsc_code, bank_branch,
                    email, hire_date, department, position, employee_type, salary, work_location, timings, company_name, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
                
                $stmt = mysqli_prepare($con, $insert);
                mysqli_stmt_bind_param($stmt, "sssssssssssssssssssssssssssssssss", 
                    $employee_id, $name, $gender, $dob, $blood_group, $personal_email, $phone, $alt_phone, $address, $country, $state,
                    $aadhar_card, $pan_number, $contact_name, $relationship, $contact_phone, $contact_alt_phone,
                    $university_degree, $year_completion, $percentage_cgpa,
                    $bank_account_number, $ifsc_code, $bank_branch,
                    $email, $hire_date, $department, $position, $employee_type, $salary, $work_location, $timings, $company_name, $status
                );
                
                if (mysqli_stmt_execute($stmt)) {
                    $success_count++;
                } else {
                    $failed_count++;
                    $errors[] = "Row $total_records: " . mysqli_error($con);
                }
                mysqli_stmt_close($stmt);
            }
            
            fclose($handle);
            
            $_SESSION['import_result'] = array(
                'total' => $total_records,
                'success' => $success_count,
                'failed' => $failed_count,
                'errors' => $errors
            );
            
            header("Location: $current_page?msg=imported");
            exit;
        }
    }
}

// =========================================================================
// DELETE EMPLOYEE
// =========================================================================
if (isset($_GET['delete_id'])) {
    if (!$isAdmin) {
        $_SESSION['error_message'] = "Access Denied: Only Abishek can delete employees";
        header("Location: $current_page");
        exit;
    }
    
    $delete_id = intval($_GET['delete_id']);
    if ($delete_id > 0) {
        $emp_query = mysqli_query($con, "SELECT employee_id FROM hr_employees WHERE id = $delete_id");
        if ($emp_row = mysqli_fetch_assoc($emp_query)) {
            $employee_id = $emp_row['employee_id'];
            
            $docs_query = mysqli_query($con, "SELECT filepath FROM hr_employee_documents WHERE employee_id = '$employee_id'");
            while ($doc = mysqli_fetch_assoc($docs_query)) {
                if (file_exists($doc['filepath'])) {
                    unlink($doc['filepath']);
                }
            }
            mysqli_query($con, "DELETE FROM hr_employee_documents WHERE employee_id = '$employee_id'");
            
            $employee_folder = 'uploads/employee_documents/' . $employee_id . '/';
            if (is_dir($employee_folder)) {
                rmdir($employee_folder);
            }
            
            mysqli_query($con, "DELETE FROM hr_employees WHERE id = $delete_id");
            $_SESSION['success_message'] = "Employee and all associated documents deleted successfully";
        }
        header("Location: $current_page");
        exit;
    }
}

// =========================================================================
// FETCH ALL EMPLOYEES
// =========================================================================
$query = "SELECT * FROM hr_employees ORDER BY 
    CASE 
        WHEN LOWER(status) = 'active' THEN 1 
        WHEN LOWER(status) = 'inactive' THEN 2 
        ELSE 3 
    END, id DESC";

$resultado = $con->query($query);

// =========================================================================
// COUNT UPCOMING BIRTHDAYS
// =========================================================================
$upcoming_birthdays_count = 0;
$today_md = date('m-d');
$next_7_days = [];
for($i = 1; $i <= 7; $i++) {
    $next_7_days[] = date('m-d', strtotime("+$i days"));
}
$birthday_list_sql = implode("','", $next_7_days);
$upcoming_bday_query = mysqli_query($con, "
    SELECT COUNT(*) as count 
    FROM hr_employees 
    WHERE DATE_FORMAT(dob, '%m-%d') IN ('$birthday_list_sql') 
    AND status = 'Active'
");
if($upcoming_bday_query) {
    $bday_count_row = mysqli_fetch_assoc($upcoming_bday_query);
    $upcoming_birthdays_count = $bday_count_row['count'];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $_SESSION['ge_cname']; ?> | Employee Management</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/buttons/2.4.1/css/buttons.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/fixedcolumns/4.3.0/css/fixedColumns.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    
    .container-fluid { 
      max-width: 1600px; 
      margin: 0 auto; 
      padding: 0 20px;
    }

    /* Alert Messages */
    .alert-container { position: fixed; top: 20px; right: 20px; z-index: 9999; min-width: 300px; }
    .alert { border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); }

    /* Header */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px;
      border-radius: 10px;
      box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px;
      display: flex; 
      justify-content: space-between; 
      align-items: center;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }
    .header-stats { display: flex; gap: 20px; align-items: center; }
    .stat-box { text-align: center; padding: 8px 20px; background: rgba(255, 255, 255, 0.15); border-radius: 8px; }
    .stat-box .stat-number { font-size: 1.8rem; font-weight: 700; color: white; }
    .stat-box .stat-label { font-size: 0.85rem; color: rgba(255, 255, 255, 0.9); margin-top: 4px; }
    
    /* Birthday Alert Box */
    .birthday-alert {
      background: linear-gradient(135deg, #ec4899 0%, #db2777 100%);
      padding: 12px 20px;
      border-radius: 8px;
      color: white;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 10px;
      animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.8; }
    }

    /* Action Bar */
    .action-bar {
      background: white; 
      padding: 20px; 
      border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); 
      margin-bottom: 20px;
      display: flex; 
      justify-content: center; 
      align-items: center; 
      flex-wrap: wrap; 
      gap: 15px;
    }
    
    .btn-action {
      border: none; padding: 14px 32px; border-radius: 12px; font-weight: 700;
      transition: all 0.3s; display: inline-flex; align-items: center; gap: 10px;
      font-size: 15px; color: white; text-decoration: none; cursor: pointer;
    }
    
    .btn-add { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3); }
    .btn-add:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(30, 58, 138, 0.5); color: white; text-decoration: none; }
    
    .btn-import { background: linear-gradient(135deg, #10b981 0%, #059669 100%); box-shadow: 0 4px 15px rgba(16, 185, 129, 0.3); }
    .btn-import:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(16, 185, 129, 0.4); color: white; text-decoration: none; }
    
    .btn-export { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); box-shadow: 0 4px 15px rgba(245, 158, 11, 0.3); }
    .btn-export:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(245, 158, 11, 0.4); color: white; text-decoration: none; }
    
    .btn-dashboard { background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); box-shadow: 0 4px 15px rgba(139, 92, 246, 0.3); }
    .btn-dashboard:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(139, 92, 246, 0.4); color: white; text-decoration: none; }
    
    /* Filter Bar */
    .filter-bar {
      background: white;
      padding: 20px;
      border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
      margin-bottom: 20px;
    }
    
    .filter-bar h5 {
      color: #1e3a8a;
      font-weight: 700;
      margin-bottom: 15px;
      font-size: 16px;
    }
    
    .filter-row {
      display: flex;
      gap: 15px;
      align-items: center;
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
      margin-bottom: 5px;
      display: block;
    }
    
    .filter-group select, .filter-group input {
      width: 100%;
      padding: 10px 15px;
      border: 2px solid #e2e8f0;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 500;
      color: #1e293b;
      transition: all 0.3s;
    }
    
    .filter-group select:focus, .filter-group input:focus {
      outline: none;
      border-color: #1e40af;
      box-shadow: 0 0 0 3px rgba(30, 64, 175, 0.1);
    }
    
    .btn-reset-filter {
      padding: 10px 24px;
      background: #ef4444;
      color: white;
      border: none;
      border-radius: 8px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s;
      margin-top: 22px;
    }
    
    .btn-reset-filter:hover {
      background: #dc2626;
      transform: translateY(-2px);
    }

    /* Initial Loader */
    #initial-loader {
        position: absolute;
        top: 200px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 50;
        text-align: center;
        background: rgba(255,255,255,0.95);
        padding: 30px;
        border-radius: 10px;
        box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }

    /* Table Container */
    .table-container { 
      background: white; 
      padding: 20px; 
      border-radius: 10px; 
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); 
      overflow: visible;
      opacity: 0;
      transition: opacity 0.5s ease-in-out;
    }
    
    /* DataTables Scroll Wrapper */
    .dataTables_scrollBody {
        max-height: 70vh !important;
        overflow-y: auto !important;
    }
    
    .dt-buttons {
      display: none !important;
    }

    /* Table Alignment */
    .dataTables_wrapper {
        width: 100% !important;
    }
    
    .dataTables_scroll {
        width: 100% !important;
    }
    
    .dataTables_scrollHead,
    .dataTables_scrollBody {
        width: 100% !important;
    }
    
    .dataTables_scrollBody {
        overflow-x: auto !important;
        overflow-y: auto !important;
    }
    
    .dataTables_scrollHeadInner,
    .dataTables_scrollBody > table {
        width: 100% !important;
        table-layout: fixed !important;
    }

    table.dataTable {
        margin: 0 !important;
        border-collapse: separate !important;
        border-spacing: 0 !important;
        width: 100% !important;
        table-layout: fixed !important;
    }

    /* Header Styling */
    table.dataTable thead th {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important; 
        color: white !important; 
        font-weight: 700 !important; 
        white-space: nowrap !important;
        border: 1px solid #1e3a8a !important; 
        border-bottom: 4px solid #1e3a8a !important;
        padding: 15px 10px !important; 
        vertical-align: middle !important;
        height: 50px !important; 
        line-height: 20px !important;
        text-align: left !important;
        box-sizing: border-box !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
        font-size: 13px !important;
    }

    /* Body Styling */
    table.dataTable tbody td {
        border: 1px solid #1e3a8a !important;
        padding: 12px 10px !important;
        vertical-align: middle !important;
        font-weight: 600 !important;
        color: #1e293b !important;
        white-space: nowrap !important; 
        height: auto !important;
        min-height: 50px !important;
        line-height: 1.4 !important;
        box-sizing: border-box !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
        text-align: left !important;
        font-size: 13px !important;
    }

    /* Remove Ghost Header */
    .dataTables_scrollBody thead {
        visibility: collapse !important;
        height: 0 !important;
    }
    
    .dataTables_scrollBody thead tr {
        height: 0 !important;
        border: none !important;
    }
    
    .dataTables_scrollBody thead th {
        height: 0 !important;
        padding: 0 !important;
        margin: 0 !important;
        border: none !important;
        line-height: 0 !important;
    }

    /* Row Backgrounds */
    table.dataTable tbody tr { 
        background-color: #ffffff !important; 
        transition: background-color 0.2s ease;
    }
    
    table.dataTable tbody tr:hover { 
        background-color: #f1f5f9 !important; 
    }
    
    /* Fixed Column */
    table.dataTable tbody tr td:first-child { 
        border-left: 3px solid #1e3a8a !important; 
        font-weight: 700 !important; 
        background: #f8fafc !important;
    }
    
    table.dataTable tbody tr:hover td:first-child {
        background: #e2e8f0 !important;
    }

    /* Text wrapping for specific cells */
    table.dataTable tbody td.text-wrap-cell {
        white-space: normal !important;
        word-wrap: break-word;
        line-height: 1.4 !important;
    }

    .badge { padding: 6px 14px; border-radius: 20px; font-weight: 600; font-size: 12px; }
    .badge-success { background: #059669; color: white; }
    .badge-warning { background: #d97706; color: white; }
    .badge-danger { background: #dc2626; color: white; }
    .badge-info { background: #3b82f6; color: white; }
    
    .action-btn {
      display: inline-block; 
      width: 38px; 
      height: 38px; 
      line-height: 38px; 
      text-align: center;
      border-radius: 8px; 
      margin: 0 5px; 
      transition: all 0.3s ease; 
      text-decoration: none; 
      font-size: 14px;
      cursor: pointer;
    }
    .btn-docs { background: #8b5cf6; color: white; }
    .btn-edit { background: #1e40af; color: white; }
    .btn-delete { background: #dc2626; color: white; }
    .btn-docs:hover { background: #7c3aed; color: white; transform: scale(1.15); text-decoration: none; }
    .btn-edit:hover { background: #1e3a8a; color: white; transform: scale(1.15); text-decoration: none; }
    .btn-delete:hover { background: #b91c1c; color: white; transform: scale(1.15); text-decoration: none; }

    /* Document Badge */
    .doc-count-badge {
        display: inline-block;
        background: #8b5cf6;
        color: white;
        border-radius: 50%;
        width: 20px;
        height: 20px;
        line-height: 20px;
        text-align: center;
        font-size: 11px;
        font-weight: 700;
        position: absolute;
        top: -5px;
        right: -5px;
    }

    /* DataTables Top Controls Wrapper */
    .dataTables_wrapper .top-controls {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 20px;
        padding: 15px;
        background: #f8fafc;
        border-radius: 10px;
        border: 2px solid #e2e8f0;
    }

    /* DataTables Bottom Controls Wrapper */
    .dataTables_wrapper .bottom-controls {
        margin-top: 25px;
        padding: 20px;
        background: #f8fafc;
        border-radius: 10px;
        border: 2px solid #e2e8f0;
    }

    /* Length Menu Styling */
    .dataTables_wrapper .dataTables_length {
        padding: 0 !important;
        font-weight: 600 !important;
        color: #475569 !important;
        display: flex !important;
        align-items: center !important;
        gap: 10px !important;
    }
    
    .dataTables_wrapper .dataTables_length label {
        display: flex !important;
        align-items: center !important;
        gap: 10px !important;
        margin: 0 !important;
        font-size: 14px !important;
    }
    
    .dataTables_wrapper .dataTables_length select {
        padding: 10px 35px 10px 15px !important;
        border: 2px solid #e2e8f0 !important;
        border-radius: 8px !important;
        font-weight: 700 !important;
        color: #1e3a8a !important;
        font-size: 15px !important;
        cursor: pointer !important;
        background: white !important;
        appearance: none !important;
        background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%231e3a8a' d='M6 9L1 4h10z'/%3E%3C/svg%3E") !important;
        background-repeat: no-repeat !important;
        background-position: right 10px center !important;
        min-width: 100px !important;
    }
    
    .dataTables_wrapper .dataTables_length select:focus {
        outline: none !important;
        border-color: #1e40af !important;
        box-shadow: 0 0 0 3px rgba(30, 64, 175, 0.1) !important;
    }

    /* Search Box Styling - Hide default search box to use global filter */
    .dataTables_wrapper .dataTables_filter {
        display: none;
    }

    /* DataTables Pagination Styling */
    .dataTables_wrapper .dataTables_paginate {
        text-align: center !important;
        padding: 0 !important;
        margin: 0 !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button {
        padding: 12px 20px !important;
        margin: 0 6px !important;
        border-radius: 10px !important;
        border: 2px solid #e2e8f0 !important;
        background: white !important;
        color: #1e3a8a !important;
        font-weight: 700 !important;
        font-size: 15px !important;
        cursor: pointer !important;
        transition: all 0.3s ease !important;
        display: inline-block !important;
        min-width: 45px !important;
        text-align: center !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button:hover {
        background: #1e40af !important;
        color: white !important;
        border-color: #1e40af !important;
        transform: translateY(-3px) !important;
        box-shadow: 0 6px 20px rgba(30, 64, 175, 0.4) !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button.current {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important;
        color: white !important;
        border-color: #1e3a8a !important;
        box-shadow: 0 4px 15px rgba(30, 58, 138, 0.4) !important;
        transform: scale(1.1) !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button.current:hover {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important;
        transform: scale(1.1) !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button.disabled {
        opacity: 0.5 !important;
        cursor: not-allowed !important;
        background: #f1f5f9 !important;
        color: #94a3b8 !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .paginate_button.disabled:hover {
        background: #f1f5f9 !important;
        color: #94a3b8 !important;
        border-color: #e2e8f0 !important;
        transform: none !important;
        box-shadow: none !important;
    }
    
    .dataTables_wrapper .dataTables_paginate .ellipsis {
        padding: 12px 10px !important;
        color: #64748b !important;
        font-weight: 700 !important;
    }
    
    /* DataTables Info */
    .dataTables_wrapper .dataTables_info {
        padding: 0 !important;
        color: #1e3a8a !important;
        font-weight: 700 !important;
        font-size: 15px !important;
        text-align: center !important;
        margin: 0 0 15px 0 !important;
    }

    /* Modal */
    .modal-content { border-radius: 15px; border: none; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
    .modal-header { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; border-radius: 15px 15px 0 0; padding: 20px 30px; }
    .modal-body { padding: 30px; }
    .close { color: white; opacity: 0.9; text-shadow: none; font-size: 28px; }
    
    .upload-zone {
        border: 3px dashed #e2e8f0;
        border-radius: 16px;
        padding: 50px;
        text-align: center;
        transition: all 0.3s;
        cursor: pointer;
        background: #f8fafc;
    }
    .upload-zone:hover { border-color: #10b981; background: #f0fdf4; }

    /* Document List Styles */
    .document-list {
        max-height: 500px;
        overflow-y: auto;
    }
    
    .document-item {
        background: #f8fafc;
        padding: 15px;
        border-radius: 10px;
        margin-bottom: 12px;
        border: 2px solid #e2e8f0;
        display: flex;
        justify-content: space-between;
        align-items: center;
        transition: all 0.3s;
    }
    
    .document-item:hover {
        background: #e0e7ff;
        border-color: #8b5cf6;
    }
    
    .doc-info {
        flex: 1;
    }
    
    .doc-type {
        font-weight: 700;
        color: #1e3a8a;
        font-size: 15px;
        margin-bottom: 4px;
    }
    
    .doc-filename {
        font-size: 13px;
        color: #64748b;
        font-weight: 500;
    }
    
    .doc-date {
        font-size: 12px;
        color: #94a3b8;
        margin-top: 4px;
    }
    
    .doc-actions {
        display: flex;
        gap: 8px;
    }
    
    .btn-download {
        background: #10b981;
        color: white;
        padding: 8px 16px;
        border-radius: 8px;
        text-decoration: none;
        font-weight: 600;
        font-size: 13px;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        transition: all 0.3s;
    }
    
    .btn-download:hover {
        background: #059669;
        color: white;
        text-decoration: none;
        transform: translateY(-2px);
    }
    
    .btn-delete-doc {
        background: #ef4444;
        color: white;
        padding: 8px 16px;
        border-radius: 8px;
        text-decoration: none;
        font-weight: 600;
        font-size: 13px;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        transition: all 0.3s;
        border: none;
        cursor: pointer;
    }
    
    .btn-delete-doc:hover {
        background: #dc2626;
        color: white;
        text-decoration: none;
        transform: translateY(-2px);
    }
    
    .no-documents {
        text-align: center;
        padding: 40px;
        color: #94a3b8;
    }
    
    .no-documents i {
        font-size: 64px;
        margin-bottom: 16px;
        opacity: 0.5;
    }

    .spinner { 
        border: 4px solid #f3f3f3; 
        border-top: 4px solid #1e3a8a; 
        border-radius: 50%; 
        width: 60px; 
        height: 60px; 
        animation: spin 1s linear infinite; 
        margin: 0 auto 15px;
    }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

    /* Custom Scrollbar Styling */
    .dataTables_scrollBody::-webkit-scrollbar {
        width: 12px;
        height: 12px;
    }
    
    .dataTables_scrollBody::-webkit-scrollbar-track {
        background: #f1f5f9;
        border-radius: 10px;
    }
    
    .dataTables_scrollBody::-webkit-scrollbar-thumb {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
        border-radius: 10px;
        border: 2px solid #f1f5f9;
    }
    
    .dataTables_scrollBody::-webkit-scrollbar-thumb:hover {
        background: linear-gradient(135deg, #1e40af 0%, #2563eb 100%);
    }
    
    /* File Size Warning Styling */
    .file-size-warning {
        background: #fef3c7;
        border: 2px solid #f59e0b;
        color: #92400e;
        padding: 12px 16px;
        border-radius: 8px;
        margin-top: 12px;
        font-weight: 600;
        display: none;
    }
    
    .file-size-warning i {
        margin-right: 8px;
    }
  </style>
</head>
<body>

<!-- Alert Container -->
<div class="alert-container">
  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible fade show">
      <strong><i class="fa fa-check-circle"></i> Success!</strong> <?php echo htmlspecialchars($_SESSION['success_message']); ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['success_message']); ?>
  <?php endif; ?>
  
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible fade show">
      <strong><i class="fa fa-exclamation-triangle"></i> Error!</strong> <?php echo htmlspecialchars($_SESSION['error_message']); ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['error_message']); ?>
  <?php endif; ?>
  
  <?php if (isset($_GET['msg']) && $_GET['msg'] == 'imported' && isset($_SESSION['import_result'])): 
    $result = $_SESSION['import_result'];
  ?>
    <div class="alert alert-info alert-dismissible fade show">
      <strong><i class="fa fa-upload"></i> Import Complete!</strong><br>
      Total: <?php echo $result['total']; ?> | 
      Success: <span style="color: #059669; font-weight: 700;"><?php echo $result['success']; ?></span> | 
      Failed: <span style="color: #dc2626; font-weight: 700;"><?php echo $result['failed']; ?></span>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['import_result']); ?>
  <?php endif; ?>
</div>

<div class="container-fluid">
  
  <div class="page-header">
    <h1><i class="fas fa-users"></i> Employee Management System</h1>
    <div class="header-stats">
      <?php if($upcoming_birthdays_count > 0): ?>
      <div class="birthday-alert">
        <i class="fas fa-birthday-cake"></i>
        <span><?php echo $upcoming_birthdays_count; ?> Birthday<?php echo $upcoming_birthdays_count > 1 ? 's' : ''; ?> This Week!</span>
      </div>
      <?php endif; ?>
      <div class="stat-box">
        <div class="stat-number"><?php echo $resultado->num_rows; ?></div>
        <div class="stat-label">Total Employees</div>
      </div>
    </div>
  </div>

  <!-- Action Bar -->
  <div class="action-bar">
    <a href="<?php echo $isAdmin ? '/dashboard/index.php' : '/dashboard/raise-a-ticket.php'; ?>" class="btn-action btn-dashboard">
      <i class="fas fa-arrow-left"></i> Back to Dashboard
    </a>
    <a href="hr-employees-add.php" class="btn-action btn-add">
      <i class="fas fa-user-plus"></i> Add Employee
    </a>
    <button type="button" class="btn-action btn-import" onclick="$('#importModal').modal('show')">
      <i class="fas fa-upload"></i> Import CSV
    </button>
    <a href="?export=csv" class="btn-action btn-export">
      <i class="fas fa-download"></i> Export Data
    </a>
  </div>

  <!-- Filter Bar -->
  <div class="filter-bar">
    <h5><i class="fas fa-filter"></i> Filter Employees</h5>
    <div class="filter-row">
      <div class="filter-group">
        <label>Global Search</label>
        <input type="text" id="globalSearch" placeholder="Search by ID, Name, Phone...">
      </div>
      <div class="filter-group">
        <label>Status</label>
        <select id="statusFilter">
          <option value="">All Status</option>
          <option value="Active">Active</option>
          <option value="Inactive">Inactive</option>
          <option value="Terminated">Terminated</option>
        </select>
      </div>
      
      <!-- DYNAMIC DEPARTMENTS -->
      <div class="filter-group">
        <label>Department</label>
        <select id="departmentFilter">
          <option value="">All Departments</option>
          <?php
          if(mysqli_num_rows($dept_query) > 0) {
              mysqli_data_seek($dept_query, 0);
              while($row = mysqli_fetch_assoc($dept_query)) {
                  echo '<option value="'.htmlspecialchars($row['name']).'">'.htmlspecialchars($row['name']).'</option>';
              }
          }
          ?>
        </select>
      </div>

      <!-- EMPLOYEE TYPE FILTER -->
      <div class="filter-group">
        <label>Employee Type</label>
        <select id="typeFilter">
          <option value="">All Types</option>
          <option value="Probation period">Probation period</option>
          <option value="Permanent Employee">Permanent Employee</option>
        </select>
      </div>

      <!-- DYNAMIC POSITIONS -->
      <div class="filter-group">
        <label>Position</label>
        <select id="positionFilter">
          <option value="">All Positions</option>
          <?php
          if(mysqli_num_rows($pos_query) > 0) {
              mysqli_data_seek($pos_query, 0);
              while($row = mysqli_fetch_assoc($pos_query)) {
                  echo '<option value="'.htmlspecialchars($row['title']).'">'.htmlspecialchars($row['title']).'</option>';
              }
          }
          ?>
        </select>
      </div>

      <!-- DYNAMIC LOCATIONS -->
      <div class="filter-group">
        <label>Work Location</label>
        <select id="locationFilter">
          <option value="">All Locations</option>
          <?php
          if(mysqli_num_rows($loc_query) > 0) {
              mysqli_data_seek($loc_query, 0);
              while($row = mysqli_fetch_assoc($loc_query)) {
                  echo '<option value="'.htmlspecialchars($row['location_name']).'">'.htmlspecialchars($row['location_name']).'</option>';
              }
          }
          ?>
          <option value="Other">Other</option>
        </select>
      </div>

      <!-- DYNAMIC COMPANIES FILTER -->
      <div class="filter-group">
        <label>Company</label>
        <select id="companyFilter">
          <option value="">All Companies</option>
          <?php
          if(mysqli_num_rows($company_query) > 0) {
              mysqli_data_seek($company_query, 0);
              while($row = mysqli_fetch_assoc($company_query)) {
                  echo '<option value="'.htmlspecialchars($row['company_name']).'">'.htmlspecialchars($row['company_name']).'</option>';
              }
          }
          ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Country</label>
        <select id="countryFilter">
          <option value="">All Countries</option>
          <!-- Populated by JS -->
        </select>
      </div>
      <div class="filter-group">
        <label>State</label>
        <select id="stateFilter">
          <option value="">All States</option>
          <!-- Populated by JS -->
        </select>
      </div>
      <div>
        <button class="btn-reset-filter" onclick="resetFilters()">
          <i class="fas fa-redo"></i> Reset
        </button>
      </div>
    </div>
  </div>

  <!-- Initial Loader -->
  <div id="initial-loader">
      <div class="spinner"></div>
      <p style="font-weight: 700; color: #1e3a8a; font-size: 16px; margin: 0;">Loading Employee Database...</p>
  </div>

  <!-- Table -->
  <div class="table-container">
    <table id="employeeTable" class="display nowrap" style="width:100%">
      <thead>
        <tr>
          <th>Sl.No</th>
          <th>Emp ID</th>
          <th>Name</th>
          <th>Designation</th>
          <th>Department</th>
          <th>Employee Type</th>
          <th>Official Email</th>
          <th>Mobile</th>
          <th>Work Location</th>
          <th>Company Name</th>
          <th>Salary (₹)</th>
          <th>Status</th>
          <th>Country</th>
          <th>State</th>
          <th>Gender</th>
          <th>DOB</th>
          <th>Blood</th>
          <th>Alt Phone</th>
          <th>Aadhar</th>
          <th>PAN</th>
          <th>Personal Email</th>
          <th>Address</th>
          <th>Emg.Contact</th>
          <th>Relation</th>
          <th>Emg.Phone</th>
          <th>Emg.Alt</th>
          <th>Degree</th>
          <th>Year</th>
          <th>GPA/%</th>
          <th>Bank Acc</th>
          <th>IFSC</th>
          <th>Branch</th>
          <th>Join Date</th>
          <th>Timings</th>
          <th>Reporting Manager 1</th>
          <th>Reporting Manager 2</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <?php 
        $sl_no = 1;
        $resultado->data_seek(0);
        while($row = $resultado->fetch_assoc()) { 
            $status = strtolower($row['status'] ?? 'inactive');
            $badge_class = 'badge-secondary';
            if ($status == 'active') $badge_class = 'badge-success';
            elseif ($status == 'inactive') $badge_class = 'badge-warning';
            elseif ($status == 'terminated') $badge_class = 'badge-danger';
            
            // Count documents for this employee
            $employee_id = $row['employee_id'];
            $doc_count_query = mysqli_query($con, "SELECT COUNT(*) as count FROM hr_employee_documents WHERE employee_id = '$employee_id'");
            $doc_count_row = mysqli_fetch_assoc($doc_count_query);
            $doc_count = $doc_count_row['count'];
        ?>
        <tr>
          <td><?php echo $sl_no++; ?></td>
          <td><strong><?php echo htmlspecialchars($row['employee_id'] ?? ''); ?></strong></td>
          <td><?php echo htmlspecialchars($row['name'] ?? ''); ?></td>
          <td class="text-wrap-cell"><?php echo htmlspecialchars($row['position'] ?? ''); ?></td>
          <td class="text-wrap-cell"><?php echo htmlspecialchars($row['department'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['employee_type'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['email'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['phone'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['work_location'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['company_name'] ?? ''); ?></td>
          <td>₹<?php echo number_format($row['salary'] ?? 0, 2); ?></td>
          <td><span class="badge <?php echo $badge_class; ?>"><?php echo ucfirst($row['status'] ?? 'N/A'); ?></span></td>
          <td><?php echo htmlspecialchars($row['country'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['state'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['gender'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['dob'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['blood_group'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['alt_phone'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['aadhar_card'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['pan_number'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['personal_email'] ?? ''); ?></td>
          <td class="text-wrap-cell"><?php echo htmlspecialchars($row['address'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['contact_name'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['relationship'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['contact_phone'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['contact_alt_phone'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['university_degree'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['year_completion'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['percentage_cgpa'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['bank_account_number'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['ifsc_code'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['bank_branch'] ?? ''); ?></td>
          <td><?php echo $row['hire_date'] ? date('d-M-Y', strtotime($row['hire_date'])) : ''; ?></td>
          <td><?php echo htmlspecialchars($row['timings'] ?? ''); ?></td>
          <td><?php 
            // Fetch Reporting Manager 1 Name
            if (!empty($row['reporting_manager_1'])) {
                $rm1_query = mysqli_query($con, "SELECT name FROM hr_employees WHERE employee_id = '{$row['reporting_manager_1']}' LIMIT 1");
                if ($rm1_query && $rm1_row = mysqli_fetch_assoc($rm1_query)) {
                    echo htmlspecialchars($rm1_row['name']) . ' (' . htmlspecialchars($row['reporting_manager_1']) . ')';
                } else {
                    echo htmlspecialchars($row['reporting_manager_1']);
                }
            } else {
                echo '-';
            }
          ?></td>
          <td><?php 
            // Fetch Reporting Manager 2 Name
            if (!empty($row['reporting_manager_2'])) {
                $rm2_query = mysqli_query($con, "SELECT name FROM hr_employees WHERE employee_id = '{$row['reporting_manager_2']}' LIMIT 1");
                if ($rm2_query && $rm2_row = mysqli_fetch_assoc($rm2_query)) {
                    echo htmlspecialchars($rm2_row['name']) . ' (' . htmlspecialchars($row['reporting_manager_2']) . ')';
                } else {
                    echo htmlspecialchars($row['reporting_manager_2']);
                }
            } else {
                echo '-';
            }
          ?></td>
          <td style="white-space: nowrap;">
            <a href="#" class="action-btn btn-docs" 
               onclick="viewDocuments('<?php echo $employee_id; ?>', '<?php echo addslashes($row['name']); ?>'); return false;" 
               title="View Documents" 
               style="position: relative;">
              <i class="fas fa-folder"></i>
              <?php if ($doc_count > 0): ?>
                <span class="doc-count-badge"><?php echo $doc_count; ?></span>
              <?php endif; ?>
            </a>
            <a href="hr-employees-edit.php?id=<?php echo $row['id']; ?>" class="action-btn btn-edit" title="Edit"><i class="fas fa-edit"></i></a>
            <?php if($isAdmin) { ?>
              <a href="?delete_id=<?php echo $row['id'];?>" class="action-btn btn-delete" title="Delete (Admin Only)" onclick="return confirm('⚠️ Are you sure you want to delete this employee?\n\nThis action cannot be undone and will delete all documents.')"><i class="fas fa-trash"></i></a>
            <?php } ?>
          </td>
        </tr>
        <?php } ?>
      </tbody>
    </table>
  </div>

</div>

<!-- CSV IMPORT MODAL -->
<div class="modal fade" id="importModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h4 class="modal-title"><i class="fas fa-upload"></i> Import Employees from CSV</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST" enctype="multipart/form-data">
        <div class="modal-body">
          <div class="alert alert-info" style="margin-bottom: 20px; border-radius: 12px; border: none; background: #e0f2fe; color: #075985;">
            <strong><i class="fas fa-info-circle"></i> CSV Import Instructions:</strong><br>
            1. Download the template file below<br>
            2. Fill in employee data following the exact column order<br>
            3. Upload the completed CSV file<br>
            4. System will validate and import all records
          </div>
          
          <div class="form-group">
            <label style="font-weight: 600; margin-bottom: 12px; font-size: 15px;">
              <i class="fas fa-download"></i> Step 1: Download CSV Template
            </label><br>
            <a href="?export=template" class="btn btn-success" style="padding: 12px 24px; border-radius: 10px; font-weight: 600; font-size: 14px;">
              <i class="fas fa-file-download"></i> Download Empty Template
            </a>
          </div>
          
          <div class="form-group" style="margin-top: 25px;">
            <label style="font-weight: 600; margin-bottom: 12px; font-size: 15px;">
              <i class="fas fa-file-csv"></i> Step 2: Upload Filled CSV File
            </label>
            <div class="upload-zone" onclick="document.getElementById('importFile').click()">
              <i class="fas fa-cloud-upload-alt" style="font-size: 56px; color: #10b981; margin-bottom: 16px;"></i>
              <h4 style="margin: 0 0 8px 0; font-weight: 700; color: #475569;">Click to Select CSV File</h4>
              <p style="color: #94a3b8; margin: 0 0 16px 0;">Supports .csv files only</p>
              <input type="file" name="import_file" id="importFile" accept=".csv" required style="display: none;">
              <button type="button" class="btn btn-primary" style="pointer-events: none; padding: 10px 20px; border-radius: 8px; font-weight: 600;">
                <i class="fas fa-folder-open"></i> Choose File
              </button>
              <p id="fileName" style="margin-top: 12px; font-weight: 600; color: #10b981; font-size: 14px;"></p>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
          <button type="submit" name="import_csv" class="btn btn-success" style="background: #10b981; border: none; font-weight: 700; padding: 10px 24px;">
            <i class="fas fa-upload"></i> Import Employees
          </button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- DOCUMENTS VIEWER MODAL -->
<div class="modal fade" id="documentsModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);">
        <h4 class="modal-title"><i class="fas fa-folder-open"></i> Employee Documents - <span id="docEmployeeName"></span></h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div id="documentsContent">
          <div style="text-align: center; padding: 40px;">
            <div class="spinner"></div>
            <p style="color: #64748b; font-weight: 600; margin-top: 15px;">Loading documents...</p>
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdn.datatables.net/buttons/2.4.1/js/dataTables.buttons.min.js"></script>
<script src="https://cdn.datatables.net/buttons/2.4.1/js/buttons.html5.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"></script>

<script>
  var table;
  var isAdmin = <?php echo $isAdmin ? 'true' : 'false'; ?>;
  var locationData = <?php echo json_encode($location_data); ?>;
  
  // File size constants (in bytes)
  var MAX_PHOTO_SIZE = <?php echo MAX_PHOTO_SIZE_BYTES; ?>;
  var MAX_DOCUMENT_SIZE = <?php echo MAX_DOCUMENT_SIZE_BYTES; ?>;
  var MAX_PHOTO_SIZE_MB = <?php echo MAX_PHOTO_SIZE_MB; ?>;
  var MAX_DOCUMENT_SIZE_MB = <?php echo MAX_DOCUMENT_SIZE_MB; ?>;
  
  $(document).ready(function() {
    // Populate Country Filter
    const countryFilter = document.getElementById('countryFilter');
    if (Object.keys(locationData).length > 0) {
        const countries = Object.keys(locationData).sort();
        countries.forEach(country => {
            const option = document.createElement('option');
            option.value = country;
            option.textContent = country;
            countryFilter.appendChild(option);
        });
    }

    // Initialize DataTable with enhanced pagination
    table = $('#employeeTable').DataTable({
      dom: '<"top-controls"l>rt<"bottom-controls"ip>',  // Removed 'f' (search) from DOM, handled manually
      order: [[0, 'asc']],
      pageLength: 50,  // Show more rows by default
      lengthMenu: [[25, 50, 100, -1], [25, 50, 100, "All"]],
      scrollX: true,
      scrollY: '60vh',  // Set viewport-based height
      scrollCollapse: true,
      fixedColumns: { left: 3, right: 1 },
      autoWidth: false,
      searching: true,
      paging: true,
      info: true,
      language: { 
        lengthMenu: "Show _MENU_ employees per page",
        info: "Showing _START_ to _END_ of _TOTAL_ employees",
        infoEmpty: "No employees to display",
        infoFiltered: "(filtered from _MAX_ total employees)",
        zeroRecords: "No matching employees found",
        paginate: {
          first: "« First",
          last: "Last »",
          next: "Next »",
          previous: "« Previous"
        }
      },
      
      columnDefs: [
        { width: "80px", targets: 0 },   // Sl.No
        { width: "150px", targets: 1 },  // Emp ID
        { width: "220px", targets: 2 },  // Name
        { width: "250px", targets: 3, className: "text-wrap-cell" },  // Designation (increased + wrap)
        { width: "250px", targets: 4, className: "text-wrap-cell" },  // Department (increased + wrap)
        { width: "180px", targets: 5 },  // Employee Type
        { width: "320px", targets: 6 },  // Official Email
        { width: "150px", targets: 7 },  // Mobile
        { width: "200px", targets: 8 },  // Work Location
        { width: "250px", targets: 9 },  // Company Name
        { width: "150px", targets: 10 }, // Salary
        { width: "130px", targets: 11 }, // Status
        { width: "150px", targets: 12 }, // Country
        { width: "150px", targets: 13 }, // State
        { width: "110px", targets: 14 }, // Gender
        { width: "140px", targets: 15 }, // DOB
        { width: "110px", targets: 16 }, // Blood
        { width: "150px", targets: 17 }, // Alt Phone
        { width: "170px", targets: 18 }, // Aadhar
        { width: "150px", targets: 19 }, // PAN
        { width: "320px", targets: 20 }, // Personal Email
        { width: "400px", targets: 21, className: "text-wrap-cell" }, // Address
        { width: "200px", targets: 22 }, // Emg.Contact
        { width: "140px", targets: 23 }, // Relation
        { width: "150px", targets: 24 }, // Emg.Phone
        { width: "150px", targets: 25 }, // Emg.Alt
        { width: "280px", targets: 26 }, // Degree
        { width: "110px", targets: 27 }, // Year
        { width: "130px", targets: 28 }, // GPA/%
        { width: "200px", targets: 29 }, // Bank Acc
        { width: "150px", targets: 30 }, // IFSC
        { width: "250px", targets: 31 }, // Branch
        { width: "150px", targets: 32 }, // Join Date
        { width: "250px", targets: 33 }, // Timings
        { width: "220px", targets: 34 }, // Reporting Manager 1
        { width: "220px", targets: 35 }, // Reporting Manager 2
        { width: "200px", targets: 36 }  // Actions
      ],
      
      initComplete: function(settings, json) {
          var api = this.api();
          
          $('#initial-loader').fadeOut(400, function() {
              $('.table-container').css('opacity', '1');
              setTimeout(function(){ api.columns.adjust().draw(false); }, 100);
          });
      }
    });

    // Custom filter functions
    $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
      var statusFilter = $('#statusFilter').val();
      var deptFilter = $('#departmentFilter').val();
      var typeFilter = $('#typeFilter').val();
      var posFilter = $('#positionFilter').val();
      var locFilter = $('#locationFilter').val();
      var companyFilter = $('#companyFilter').val();
      var countryFilter = $('#countryFilter').val();
      var stateFilter = $('#stateFilter').val();
      
      // Column Indices (0-based) based on the table structure:
      // 0:Sl, 1:ID, 2:Name, 3:Desig, 4:Dept, 5:Type, 6:Email, 7:Mob, 8:Loc, 9:Company, 10:Sal, 11:Status, 12:Country, 13:State
      var status = data[11] || ''; 
      var dept = data[4] || ''; 
      var type = data[5] || '';  
      var position = data[3] || ''; 
      var location = data[8] || ''; 
      var company = data[9] || '';
      var country = data[12] || '';
      var state = data[13] || '';
      
      var statusMatch = status.match(/>([^<]+)</);
      if (statusMatch) status = statusMatch[1].trim();
      
      // Removed HTML strip logic for type since it is now plain text
      
      if (statusFilter && !status.toLowerCase().includes(statusFilter.toLowerCase())) return false;
      if (deptFilter && dept !== deptFilter) return false;
      if (typeFilter && type !== typeFilter) return false;
      if (posFilter && position !== posFilter) return false;
      if (locFilter && location !== locFilter) return false;
      if (companyFilter && company !== companyFilter) return false;
      if (countryFilter && country !== countryFilter) return false;
      if (stateFilter && state !== stateFilter) return false;
      
      return true;
    });

    // Event listeners for filters
    $('#statusFilter, #departmentFilter, #typeFilter, #positionFilter, #locationFilter, #companyFilter, #countryFilter, #stateFilter').on('change', function() {
      table.draw();
    });

    // Global Search Listener
    $('#globalSearch').on('keyup', function() {
        table.search(this.value).draw();
    });

    // Dynamic State Dropdown based on Country selection
    $('#countryFilter').on('change', function() {
        const selectedCountry = this.value;
        const stateSelect = document.getElementById('stateFilter');
        stateSelect.innerHTML = '<option value="">All States</option>';
        
        if (selectedCountry && locationData[selectedCountry]) {
            let states = [];
            if (Array.isArray(locationData[selectedCountry])) {
                 states = locationData[selectedCountry].sort();
            } else {
                 states = Object.keys(locationData[selectedCountry]).sort();
            }

            states.forEach(state => {
                const option = document.createElement('option');
                option.value = state;
                option.textContent = state;
                stateSelect.appendChild(option);
            });
        }
        table.draw(); // Redraw to apply filters immediately
    });

    $(window).on('resize', function() { table.columns.adjust(); });

    $('#importFile').on('change', function(e) {
      if (e.target.files.length > 0) {
        $('#fileName').text('✓ Selected: ' + e.target.files[0].name);
      }
    });

    $('#importModal').on('hidden.bs.modal', function () {
      $(this).find('form')[0].reset();
      $(this).find('input[type="file"]').val('');
      $('#fileName').text('');
    });

    setTimeout(function() { $('.alert').fadeOut('slow'); }, 6000);
  });

  function resetFilters() {
    $('#statusFilter, #departmentFilter, #typeFilter, #positionFilter, #locationFilter, #companyFilter, #countryFilter, #stateFilter').val('');
    $('#globalSearch').val('');
    $('#stateFilter').html('<option value="">All States</option>'); // Reset state dropdown
    table.search('').draw();
  }

  // File size validation function
  function validateFileSize(input, maxSize, maxSizeMB, fileType) {
    if (input.files && input.files[0]) {
      var fileSize = input.files[0].size; // in bytes
      var fileName = input.files[0].name;
      
      if (fileSize > maxSize) {
        var actualSizeMB = (fileSize / (1024 * 1024)).toFixed(2);
        alert('⚠️ FILE TOO LARGE!\n\n' +
              'File: ' + fileName + '\n' +
              'Size: ' + actualSizeMB + ' MB\n' +
              'Maximum allowed: ' + maxSizeMB + ' MB\n\n' +
              'Please compress the ' + fileType + ' and upload again.\n\n' +
              'Tips:\n' +
              '• Use online compression tools\n' +
              '• Reduce image quality/resolution\n' +
              '• Convert to more efficient format');
        input.value = ''; // Clear the input
        return false;
      }
      return true;
    }
    return false;
  }

  // View Documents Function
  function viewDocuments(employeeId, employeeName) {
    $('#docEmployeeName').text(employeeName);
    $('#documentsModal').modal('show');
    
    // Load documents via AJAX
    $.ajax({
      url: 'get-employee-documents.php',
      method: 'GET',
      data: { employee_id: employeeId },
      success: function(response) {
        $('#documentsContent').html(response);
      },
      error: function() {
        $('#documentsContent').html('<div class="alert alert-danger">Failed to load documents</div>');
      }
    });
  }

  // Delete Document Function
  function deleteDocument(docId, employeeId, employeeName) {
    if (!isAdmin) {
      alert('⚠️ Access Denied: Only Abishek can delete documents');
      return false;
    }
    
    if (confirm('⚠️ Are you sure you want to delete this document?\n\nThis action cannot be undone.')) {
      window.location.href = '?delete_doc=' + docId;
    }
    return false;
  }
</script>

</body>
</html>