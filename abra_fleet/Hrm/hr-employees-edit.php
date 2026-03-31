<?php
// =========================================================================
// EMPLOYEE EDIT PAGE - With Dynamic Master Data & Document Management
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
session_start();
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');


$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// FILE SIZE CONFIGURATION (in MB)
// =========================================================================
define('MAX_PHOTO_SIZE_MB', 2);  // 2 MB for profile photos
define('MAX_DOCUMENT_SIZE_MB', 5);  // 5 MB for documents
define('MAX_PHOTO_SIZE_BYTES', MAX_PHOTO_SIZE_MB * 1024 * 1024);
define('MAX_DOCUMENT_SIZE_BYTES', MAX_DOCUMENT_SIZE_MB * 1024 * 1024);

// =========================================================================
// LOAD LOCATION DATA (For Country/State)
// =========================================================================
define('LOCATIONS_FILE', __DIR__ . '/global_locations.json');
$location_data = [];
if (file_exists(LOCATIONS_FILE)) {
    $json_content = file_get_contents(LOCATIONS_FILE);
    $location_data = json_decode($json_content, true);
}

// =========================================================================
// FETCH MASTER DATA FOR DROPDOWNS
// =========================================================================
// 1. Fetch Departments
$dept_sql = "SELECT * FROM hr_departments ORDER BY name ASC";
$dept_query = mysqli_query($con, $dept_sql);

// 2. Fetch Positions (Designations)
$pos_sql = "SELECT * FROM hr_positions ORDER BY title ASC";
$pos_query = mysqli_query($con, $pos_sql);

// 3. Fetch Work Locations
$loc_sql = "SELECT * FROM hr_work_locations ORDER BY location_name ASC";
$loc_query = mysqli_query($con, $loc_sql);

// 4. Fetch Office Timings
$time_sql = "SELECT * FROM hr_office_timings ORDER BY id ASC";
$time_query = mysqli_query($con, $time_sql);

// 5. Fetch Companies (NEW: Dynamic Company Dropdown)
$company_sql = "SELECT * FROM hr_companies ORDER BY company_name ASC";
$company_query = mysqli_query($con, $company_sql);

// 6. Fetch All Employees for Reporting Manager Dropdown
$employees_sql = "SELECT employee_id, name FROM hr_employees WHERE status='Active' ORDER BY name ASC";
$employees_query = mysqli_query($con, $employees_sql);

// =========================================================================
// GET EMPLOYEE ID
// =========================================================================
if (!isset($_GET['id']) || empty($_GET['id'])) {
    $_SESSION['error_message'] = "Invalid Employee ID";
    header("Location: hr-employees-list.php");
    exit();
}

$db_id = intval($_GET['id']);

// =========================================================================
// FETCH EMPLOYEE DATA
// =========================================================================
$query = "SELECT * FROM hr_employees WHERE id = $db_id LIMIT 1";
$result = mysqli_query($con, $query);

if (!$result || mysqli_num_rows($result) == 0) {
    $_SESSION['error_message'] = "Employee not found";
    header("Location: hr-employees-list.php");
    exit();
}

$employee = mysqli_fetch_assoc($result);
$employee_unique_id = $employee['employee_id']; // This is the ABRA001 string

// =========================================================================
// HANDLE DOCUMENT DELETION
// =========================================================================
if (isset($_GET['delete_doc']) && isset($_GET['doc_id'])) {
    $doc_id = intval($_GET['doc_id']);
    
    // Get file path first to delete from server
    $get_doc = mysqli_query($con, "SELECT filepath FROM hr_employee_documents WHERE id = $doc_id AND employee_id = '$employee_unique_id'");
    if ($row = mysqli_fetch_assoc($get_doc)) {
        if (file_exists($row['filepath'])) {
            unlink($row['filepath']); // Delete physical file
        }
        // Delete record from database
        mysqli_query($con, "DELETE FROM hr_employee_documents WHERE id = $doc_id");
        
        $_SESSION['success_message'] = "Document deleted successfully.";
        header("Location: $current_page?id=$db_id");
        exit();
    }
}

// =========================================================================
// UPDATE EMPLOYEE
// =========================================================================
if (isset($_POST['update_employee'])) {
    try {
        // Collect form data
        $name = mysqli_real_escape_string($con, trim($_POST['name']));
        $gender = mysqli_real_escape_string($con, trim($_POST['gender']));
        $dob = mysqli_real_escape_string($con, trim($_POST['dob']));
        $blood_group = mysqli_real_escape_string($con, trim($_POST['blood_group']));
        $personal_email = mysqli_real_escape_string($con, trim($_POST['personal_email']));
        $phone = mysqli_real_escape_string($con, trim($_POST['phone']));
        $alt_phone = mysqli_real_escape_string($con, trim($_POST['alt_phone']));
        $address = mysqli_real_escape_string($con, trim($_POST['address']));
        $country = mysqli_real_escape_string($con, trim($_POST['country']));
        $state = mysqli_real_escape_string($con, trim($_POST['state']));
        $aadhar_card = mysqli_real_escape_string($con, trim($_POST['aadhar_card']));
        $pan_number = strtoupper(mysqli_real_escape_string($con, trim($_POST['pan_number'])));
        $contact_name = mysqli_real_escape_string($con, trim($_POST['contact_name']));
        $relationship = mysqli_real_escape_string($con, trim($_POST['relationship']));
        $contact_phone = mysqli_real_escape_string($con, trim($_POST['contact_phone']));
        $contact_alt_phone = mysqli_real_escape_string($con, trim($_POST['contact_alt_phone']));
        $university_degree = mysqli_real_escape_string($con, trim($_POST['university_degree']));
        $year_completion = mysqli_real_escape_string($con, trim($_POST['year_completion']));
        $percentage_cgpa = mysqli_real_escape_string($con, trim($_POST['percentage_cgpa']));
        $bank_account_number = mysqli_real_escape_string($con, trim($_POST['bank_account_number']));
        $ifsc_code = strtoupper(mysqli_real_escape_string($con, trim($_POST['ifsc_code'])));
        $bank_branch = mysqli_real_escape_string($con, trim($_POST['bank_branch']));
        $email = mysqli_real_escape_string($con, trim($_POST['email']));
        $hire_date = mysqli_real_escape_string($con, trim($_POST['hire_date']));
        $department = mysqli_real_escape_string($con, trim($_POST['department']));
        $position = mysqli_real_escape_string($con, trim($_POST['position']));
        $salary = mysqli_real_escape_string($con, trim($_POST['salary']));
        $work_location = mysqli_real_escape_string($con, trim($_POST['work_location']));
        $company_name = mysqli_real_escape_string($con, trim($_POST['company_name']));
        $employee_type = mysqli_real_escape_string($con, trim($_POST['employee_type'])); // Collected Employee Type
        
        $timings = mysqli_real_escape_string($con, trim($_POST['timings_select']));
        if($timings == 'Manual') {
            $timings = mysqli_real_escape_string($con, trim($_POST['timings_manual']));
        }
        
        $status = mysqli_real_escape_string($con, trim($_POST['status']));
        
        // Reporting Managers
        $reporting_manager_1 = mysqli_real_escape_string($con, trim($_POST['reporting_manager_1']));
        $reporting_manager_2 = mysqli_real_escape_string($con, trim($_POST['reporting_manager_2']));

        $sql = "UPDATE hr_employees SET 
            name = '$name',
            gender = '$gender',
            dob = '$dob',
            blood_group = '$blood_group',
            personal_email = '$personal_email',
            phone = '$phone',
            alt_phone = '$alt_phone',
            address = '$address',
            country = '$country',
            state = '$state',
            aadhar_card = '$aadhar_card',
            pan_number = '$pan_number',
            contact_name = '$contact_name',
            relationship = '$relationship',
            contact_phone = '$contact_phone',
            contact_alt_phone = '$contact_alt_phone',
            university_degree = '$university_degree',
            year_completion = '$year_completion',
            percentage_cgpa = '$percentage_cgpa',
            bank_account_number = '$bank_account_number',
            ifsc_code = '$ifsc_code',
            bank_branch = '$bank_branch',
            email = '$email',
            hire_date = '$hire_date',
            department = '$department',
            position = '$position',
            reporting_manager_1 = '$reporting_manager_1',
            reporting_manager_2 = '$reporting_manager_2',
            salary = '$salary',
            work_location = '$work_location',
            timings = '$timings',
            company_name = '$company_name',
            status = '$status',
            employee_type = '$employee_type'
        WHERE id = $db_id";

        if(mysqli_query($con, $sql)) {
            
            // =========================================================================
            // HANDLE NEW DOCUMENT UPLOADS WITH FILE SIZE VALIDATION
            // =========================================================================
            $uploaded_count = 0;
            $size_errors = [];
            
            if (isset($_FILES['document_file']) && is_array($_FILES['document_file']['name'])) {
                $upload_dir = 'uploads/employee_documents/' . $employee_unique_id . '/';
                if (!file_exists($upload_dir)) {
                    mkdir($upload_dir, 0777, true);
                }
                
                $document_types = $_POST['document_type'];
                $custom_names = $_POST['document_custom_name'];
                
                foreach ($_FILES['document_file']['name'] as $key => $filename) {
                    if ($_FILES['document_file']['error'][$key] === UPLOAD_ERR_OK && !empty($filename)) {
                        
                        // FILE SIZE VALIDATION
                        $file_size = $_FILES['document_file']['size'][$key];
                        $file_ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
                        
                        // Check if it's a photo/image
                        $image_extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
                        $max_size = in_array($file_ext, $image_extensions) ? MAX_PHOTO_SIZE_BYTES : MAX_DOCUMENT_SIZE_BYTES;
                        
                        if ($file_size > $max_size) {
                            $size_errors[] = "$filename";
                            continue; // Skip this file
                        }
                        
                        $doc_type = $document_types[$key];
                        if ($doc_type === 'Other' && !empty($custom_names[$key])) {
                            $doc_type = $custom_names[$key];
                        }
                        
                        if (empty($doc_type)) continue;
                        
                        $new_filename = $employee_unique_id . '_' . preg_replace('/[^a-zA-Z0-9]/', '_', $doc_type) . '_' . time() . '.' . $file_ext;
                        $target_path = $upload_dir . $new_filename;
                        
                        if (move_uploaded_file($_FILES['document_file']['tmp_name'][$key], $target_path)) {
                            $doc_type_db = mysqli_real_escape_string($con, $doc_type);
                            $doc_filename_db = mysqli_real_escape_string($con, $new_filename);
                            $doc_filepath_db = mysqli_real_escape_string($con, $target_path);
                            
                            $doc_sql = "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath, uploaded_at) 
                                        VALUES ('$employee_unique_id', '$doc_type_db', '$doc_filename_db', '$doc_filepath_db', NOW())";
                            mysqli_query($con, $doc_sql);
                            $uploaded_count++;
                        }
                    }
                }
            }
            
            if (!empty($size_errors)) {
                $_SESSION['warning_message'] = "⚠️ Some files were too large and skipped: " . implode(', ', $size_errors);
            }

            $doc_msg = $uploaded_count > 0 ? " | $uploaded_count document(s) uploaded." : "";
            $_SESSION['success_message'] = "Employee Updated Successfully!" . $doc_msg;
            header("Location: hr-employees-list.php");
            exit();
        } else {
            throw new Exception(mysqli_error($con));
        }
    } catch (Exception $e) {
        $_SESSION['error_message'] = "Error: " . $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $_SESSION['ge_cname']; ?> | Edit Employee</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { 
      font-family: 'Poppins', sans-serif; 
      background: #f0f4f8; 
      min-height: 100vh; 
      padding: 20px 0; 
    }
    
    .container-fluid { max-width: 98%; margin: 0 auto; }

    /* Alert Messages */
    .alert-container { position: fixed; top: 20px; right: 20px; z-index: 9999; min-width: 300px; max-width: 500px; }
    .alert { border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); }

    /* Page Header */
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
    
    .page-header h1 { 
      color: white; 
      font-weight: 600; 
      margin: 0; 
      font-size: 1.8rem; 
    }

    /* Employee ID Badge */
    .employee-id-badge {
      background: rgba(255, 255, 255, 0.2);
      color: white;
      padding: 12px 24px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 1.2rem;
      display: flex;
      align-items: center;
      gap: 10px;
    }

    /* Back Button */
    .btn-back {
      background: rgba(255, 255, 255, 0.2);
      color: white;
      padding: 10px 20px;
      border-radius: 8px;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-weight: 600;
      transition: all 0.3s;
    }
    
    .btn-back:hover {
      background: rgba(255, 255, 255, 0.3);
      color: white;
      text-decoration: none;
      transform: translateX(-3px);
    }

    /* Form Container */
    .form-container {
      background: white;
      padding: 30px;
      border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
      margin-bottom: 30px;
    }

    /* Section Titles */
    .form-section-title {
      color: #1e3a8a;
      font-weight: 700;
      font-size: 1.3rem;
      margin-top: 30px;
      margin-bottom: 25px;
      padding-bottom: 10px;
      border-bottom: 3px solid #1e3a8a;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    
    .form-section-title:first-child {
      margin-top: 0;
    }

    /* Form Groups */
    .form-group {
      margin-bottom: 25px;
    }
    
    .form-group label {
      font-weight: 600;
      color: #334155;
      margin-bottom: 10px;
      font-size: 1rem;
      display: block;
    }
    
    .form-group label .required {
      color: #dc2626;
      font-weight: 700;
    }

    /* LARGE INPUT FIELDS */
    .form-control {
      border: 2px solid #e2e8f0;
      border-radius: 8px;
      padding: 18px 20px;
      font-size: 1.1rem;
      width: 100%;
      height: 60px;
      transition: all 0.3s;
      font-weight: 500;
      color: #1e293b;
    }
    
    textarea.form-control {
      min-height: 120px;
      height: auto;
      resize: vertical;
      padding-top: 18px;
    }
    
    select.form-control {
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%231e3a8a' d='M6 9L1 4h10z'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 20px center;
      padding-right: 50px;
    }
    
    .form-control:focus {
      border-color: #1e3a8a;
      box-shadow: 0 0 0 4px rgba(30, 58, 138, 0.1);
      outline: none;
    }
    
    .form-control::placeholder {
      color: #94a3b8;
      font-weight: 400;
    }

    /* Existing Document Card */
    .doc-card {
        background: white;
        border: 1px solid #e2e8f0;
        border-radius: 10px;
        padding: 15px;
        margin-bottom: 20px;
        transition: all 0.3s;
        position: relative;
    }
    .doc-card:hover {
        box-shadow: 0 4px 15px rgba(0,0,0,0.05);
        border-color: #1e3a8a;
    }
    .doc-icon {
        font-size: 2rem;
        color: #1e3a8a;
        margin-bottom: 10px;
    }
    .doc-title {
        font-weight: 600;
        color: #334155;
        font-size: 0.95rem;
        margin-bottom: 5px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .btn-delete-doc {
        position: absolute;
        top: 10px;
        right: 10px;
        color: #ef4444;
        background: #fee2e2;
        border-radius: 50%;
        width: 30px;
        height: 30px;
        display: flex;
        align-items: center;
        justify-content: center;
        text-decoration: none;
        transition: all 0.2s;
    }
    .btn-delete-doc:hover {
        background: #ef4444;
        color: white;
    }

    /* Submit Button */
    .btn-submit {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      border: none;
      padding: 18px 40px;
      border-radius: 12px;
      color: white;
      font-weight: 700;
      font-size: 1.15rem;
      width: 100%;
      margin-top: 30px;
      cursor: pointer;
      transition: all 0.3s ease;
      box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
    }
    
    .btn-submit:hover {
      background: linear-gradient(135deg, #1e40af 0%, #2563eb 100%);
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(30, 58, 138, 0.4);
    }
    
    optgroup {
        font-weight: 700;
        color: #1e3a8a;
        background-color: #f8fafc;
    }
    option {
        color: #334155;
        padding: 5px;
    }
    
    /* Select2 Custom Styling */
    .select2-container--default .select2-selection--single {
        border: 2px solid #e2e8f0;
        border-radius: 8px;
        height: 60px;
        padding: 10px 20px;
        font-size: 1.1rem;
        font-weight: 500;
    }
    
    .select2-container--default .select2-selection--single .select2-selection__rendered {
        line-height: 38px;
        color: #1e293b;
        padding-left: 0;
    }
    
    .select2-container--default .select2-selection--single .select2-selection__arrow {
        height: 58px;
        right: 10px;
    }
    
    .select2-container--default.select2-container--focus .select2-selection--single {
        border-color: #1e3a8a;
        box-shadow: 0 0 0 4px rgba(30, 58, 138, 0.1);
    }
    
    .select2-dropdown {
        border: 2px solid #1e3a8a;
        border-radius: 8px;
        box-shadow: 0 4px 15px rgba(0,0,0,0.1);
    }
    
    .select2-container--default .select2-results__option--highlighted[aria-selected] {
        background-color: #1e3a8a;
    }
    
    .select2-search--dropdown .select2-search__field {
        border: 2px solid #e2e8f0;
        border-radius: 6px;
        padding: 8px 12px;
        font-size: 1rem;
    }
    
    .select2-search--dropdown .select2-search__field:focus {
        border-color: #1e3a8a;
        outline: none;
    }
  </style>
</head>
<body>

<!-- Alert Container -->
<div class="alert-container">
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible fade show">
      <strong><i class="fa fa-exclamation-triangle"></i> Error!</strong> 
      <?php echo $_SESSION['error_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['error_message']); ?>
  <?php endif; ?>
  
  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible fade show">
      <strong><i class="fa fa-check-circle"></i> Success!</strong> 
      <?php echo $_SESSION['success_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['success_message']); ?>
  <?php endif; ?>
  
  <?php if (isset($_SESSION['warning_message'])): ?>
    <div class="alert alert-warning alert-dismissible fade show">
      <strong><i class="fa fa-exclamation-circle"></i> Warning!</strong><br>
      <?php echo $_SESSION['warning_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['warning_message']); ?>
  <?php endif; ?>
</div>

<div class="container-fluid">
  
  <!-- Page Header -->
  <div class="page-header">
    <h1><i class="fas fa-user-edit"></i> Edit Employee</h1>
    <div style="display: flex; gap: 15px; align-items: center;">
      <div class="employee-id-badge">
        <i class="fas fa-id-badge"></i>
        <?php echo htmlspecialchars($employee['employee_id']); ?>
      </div>
      <a href="hr-employees-list.php" class="btn-back">
        <i class="fas fa-arrow-left"></i> Back to List
      </a>
    </div>
  </div>

  <!-- Form Container -->
  <div class="form-container">
    <form method="POST" enctype="multipart/form-data" id="employeeForm">
      
      <!-- Official Information -->
      <div class="form-section-title">
        <i class="fas fa-briefcase"></i> Official Information
      </div>
      
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Official Email ID <span class="required">*</span></label>
            <input type="email" name="email" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['email']); ?>" 
                   placeholder="name@company.com" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Date of Joining <span class="required">*</span></label>
            <input type="date" name="hire_date" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['hire_date']); ?>" required>
          </div>
        </div>
        
        <div class="col-md-4">
          <div class="form-group">
            <label>Department <span class="required">*</span></label>
            <select name="department" class="form-control" required>
              <option value="">Select Department</option>
              <?php
              if(mysqli_num_rows($dept_query) > 0) {
                  mysqli_data_seek($dept_query, 0);
                  while($row = mysqli_fetch_assoc($dept_query)) {
                      $selected = ($employee['department'] == $row['name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['name']).'" '.$selected.'>'.htmlspecialchars($row['name']).'</option>';
                  }
              }
              ?>
            </select>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-3">
          <div class="form-group">
            <label>Designation/Position <span class="required">*</span></label>
            <select name="position" class="form-control" required>
                <option value="">Select Position</option>
                <?php
                if(mysqli_num_rows($pos_query) > 0) {
                    mysqli_data_seek($pos_query, 0);
                    while($row = mysqli_fetch_assoc($pos_query)) {
                        $selected = ($employee['position'] == $row['title']) ? 'selected' : '';
                        echo '<option value="'.htmlspecialchars($row['title']).'" '.$selected.'>'.htmlspecialchars($row['title']).'</option>';
                    }
                }
                ?>
            </select>
          </div>
        </div>
        
        <!-- REPORTING MANAGER 1 -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Reporting Manager 1</label>
            <select name="reporting_manager_1" class="form-control">
                <option value="">Select Manager</option>
                <?php
                if(mysqli_num_rows($employees_query) > 0) {
                    mysqli_data_seek($employees_query, 0);
                    while($row = mysqli_fetch_assoc($employees_query)) {
                        $selected = ($employee['reporting_manager_1'] == $row['employee_id']) ? 'selected' : '';
                        echo '<option value="'.htmlspecialchars($row['employee_id']).'" '.$selected.'>'.htmlspecialchars($row['name']).' ('.htmlspecialchars($row['employee_id']).')</option>';
                    }
                }
                ?>
            </select>
          </div>
        </div>
        
        <!-- REPORTING MANAGER 2 -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Reporting Manager 2</label>
            <select name="reporting_manager_2" class="form-control">
                <option value="">Select Manager</option>
                <?php
                if(mysqli_num_rows($employees_query) > 0) {
                    mysqli_data_seek($employees_query, 0);
                    while($row = mysqli_fetch_assoc($employees_query)) {
                        $selected = ($employee['reporting_manager_2'] == $row['employee_id']) ? 'selected' : '';
                        echo '<option value="'.htmlspecialchars($row['employee_id']).'" '.$selected.'>'.htmlspecialchars($row['name']).' ('.htmlspecialchars($row['employee_id']).')</option>';
                    }
                }
                ?>
            </select>
          </div>
        </div>

        <div class="col-md-3">
          <div class="form-group">
            <label>Status <span class="required">*</span></label>
            <select name="status" class="form-control" required>
              <option value="Active" <?php echo ($employee['status'] == 'Active') ? 'selected' : ''; ?>>Active</option>
              <option value="Inactive" <?php echo ($employee['status'] == 'Inactive') ? 'selected' : ''; ?>>Inactive</option>
              <option value="Terminated" <?php echo ($employee['status'] == 'Terminated') ? 'selected' : ''; ?>>Terminated</option>
            </select>
          </div>
        </div>
      </div>

      <div class="row">
        <!-- EMPLOYEE TYPE DROPDOWN -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Employee Type <span class="required">*</span></label>
            <select name="employee_type" class="form-control" required>
              <option value="">Select Type</option>
              <option value="Probation period" <?php echo ($employee['employee_type'] == 'Probation period') ? 'selected' : ''; ?>>Probation period</option>
              <option value="Permanent Employee" <?php echo ($employee['employee_type'] == 'Permanent Employee') ? 'selected' : ''; ?>>Permanent Employee</option>
            </select>
          </div>
        </div>

        <div class="col-md-3">
          <div class="form-group">
            <label>Total Salary (₹) <span class="required">*</span></label>
            <input type="number" step="0.01" name="salary" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['salary']); ?>" 
                   placeholder="e.g. 35000" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-3">
          <div class="form-group">
            <label>Work Location <span class="required">*</span></label>
            <select name="work_location" class="form-control" required>
              <option value="">Select Location</option>
              <?php
              if(mysqli_num_rows($loc_query) > 0) {
                  mysqli_data_seek($loc_query, 0);
                  while($row = mysqli_fetch_assoc($loc_query)) {
                      $selected = ($employee['work_location'] == $row['location_name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['location_name']).'" '.$selected.'>'.htmlspecialchars($row['location_name']).'</option>';
                  }
              }
              ?>
              <option value="Other" <?php echo ($employee['work_location'] == 'Other') ? 'selected' : ''; ?>>Other</option>
            </select>
          </div>
        </div>
        
        <!-- COMPANY NAME -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Company Name <span class="required">*</span></label>
            <select name="company_name" class="form-control" required>
              <option value="">Select Company</option>
              <?php
              if(mysqli_num_rows($company_query) > 0) {
                  mysqli_data_seek($company_query, 0);
                  while($row = mysqli_fetch_assoc($company_query)) {
                      $selected = ($employee['company_name'] == $row['company_name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['company_name']).'" '.$selected.'>'.htmlspecialchars($row['company_name']).'</option>';
                  }
              }
              ?>
            </select>
          </div>
        </div>
        
        <div class="col-md-6">
          <div class="form-group">
            <label>Timings <span class="required">*</span></label>
            <div class="row">
              <div class="col-md-6">
                <select name="timings_select" class="form-control timings-select" required>
                  <option value="">Select Shift</option>
                  <?php
                  $is_manual = true;
                  if(mysqli_num_rows($time_query) > 0) {
                      mysqli_data_seek($time_query, 0);
                      while($row = mysqli_fetch_assoc($time_query)) {
                          $timing_str = $row['start_time'] . ' - ' . $row['end_time'];
                          if($employee['timings'] == $timing_str) {
                              $selected = 'selected';
                              $is_manual = false;
                          } else {
                              $selected = '';
                          }
                          echo '<option value="'.htmlspecialchars($timing_str).'" '.$selected.'>'.htmlspecialchars($timing_str).'</option>';
                      }
                  }
                  if(empty($employee['timings'])) $is_manual = false;
                  ?>
                  <option value="Manual" <?php echo $is_manual ? 'selected' : ''; ?>>Custom Timings (Manual Entry)</option>
                </select>
              </div>
              <div class="col-md-6">
                <input type="text" name="timings_manual" class="form-control timings-manual" 
                       style="display:<?php echo $is_manual ? 'block' : 'none'; ?>;" 
                       value="<?php echo $is_manual ? htmlspecialchars($employee['timings']) : ''; ?>" 
                       placeholder="e.g. 10:00 AM - 7:00 PM">
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Personal Information -->
      <div class="form-section-title">
        <i class="fas fa-user"></i> Personal Information
      </div>
      
      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Full Name <span class="required">*</span></label>
            <input type="text" name="name" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['name']); ?>" 
                   placeholder="Enter full name" required>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Gender <span class="required">*</span></label>
            <select name="gender" class="form-control" required>
              <option value="">Select</option>
              <option value="Male" <?php echo ($employee['gender'] == 'Male') ? 'selected' : ''; ?>>Male</option>
              <option value="Female" <?php echo ($employee['gender'] == 'Female') ? 'selected' : ''; ?>>Female</option>
              <option value="Other" <?php echo ($employee['gender'] == 'Other') ? 'selected' : ''; ?>>Other</option>
            </select>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Date of Birth <span class="required">*</span></label>
            <input type="date" name="dob" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['dob']); ?>" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Blood Group <span class="required">*</span></label>
            <select name="blood_group" class="form-control" required>
              <option value="">Select</option>
              <option value="A+" <?php echo ($employee['blood_group'] == 'A+') ? 'selected' : ''; ?>>A+</option>
              <option value="A-" <?php echo ($employee['blood_group'] == 'A-') ? 'selected' : ''; ?>>A-</option>
              <option value="B+" <?php echo ($employee['blood_group'] == 'B+') ? 'selected' : ''; ?>>B+</option>
              <option value="B-" <?php echo ($employee['blood_group'] == 'B-') ? 'selected' : ''; ?>>B-</option>
              <option value="O+" <?php echo ($employee['blood_group'] == 'O+') ? 'selected' : ''; ?>>O+</option>
              <option value="O-" <?php echo ($employee['blood_group'] == 'O-') ? 'selected' : ''; ?>>O-</option>
              <option value="AB+" <?php echo ($employee['blood_group'] == 'AB+') ? 'selected' : ''; ?>>AB+</option>
              <option value="AB-" <?php echo ($employee['blood_group'] == 'AB-') ? 'selected' : ''; ?>>AB-</option>
            </select>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Mobile Number <span class="required">*</span></label>
            <input type="text" name="phone" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['phone']); ?>" 
                   placeholder="10 digit mobile" pattern="[0-9]{10}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="alt_phone" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['alt_phone']); ?>" 
                   placeholder="Alternate contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Personal Email ID <span class="required">*</span></label>
            <input type="email" name="personal_email" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['personal_email']); ?>" 
                   placeholder="personal@email.com" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Country <span class="required">*</span></label>
            <select name="country" id="country" class="form-control" required>
              <option value="">Select Country</option>
            </select>
          </div>
        </div>
        <div class="col-md-6">
          <div class="form-group">
            <label>State <span class="required">*</span></label>
            <select name="state" id="state" class="form-control" required>
              <option value="">Select State</option>
            </select>
          </div>
        </div>
      </div>
      
      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Residential Address <span class="required">*</span></label>
            <textarea name="address" class="form-control" rows="3" 
                      placeholder="Full address with pincode" required><?php echo htmlspecialchars($employee['address']); ?></textarea>
          </div>
        </div>
      </div>

      <!-- Identity Documents -->
      <div class="form-section-title">
        <i class="fas fa-id-card"></i> Identity Documents
      </div>
      
      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Aadhar Card Number <span class="required">*</span></label>
            <input type="text" name="aadhar_card" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['aadhar_card']); ?>" 
                   placeholder="12 digit Aadhar" pattern="[0-9]{12}" required>
          </div>
        </div>
        <div class="col-md-6">
          <div class="form-group">
            <label>PAN Number <span class="required">*</span></label>
            <input type="text" name="pan_number" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['pan_number']); ?>" 
                   style="text-transform:uppercase;" placeholder="e.g. ABCDE1234F" 
                   pattern="[A-Z]{5}[0-9]{4}[A-Z]{1}" required>
          </div>
        </div>
      </div>

      <!-- Emergency Contact -->
      <div class="form-section-title">
        <i class="fas fa-phone-square"></i> Emergency Contact
      </div>
      
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Contact Name <span class="required">*</span></label>
            <input type="text" name="contact_name" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['contact_name']); ?>" 
                   placeholder="Emergency contact name" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Relationship <span class="required">*</span></label>
            <input type="text" name="relationship" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['relationship']); ?>" 
                   placeholder="Father, Spouse, etc." required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Phone Number <span class="required">*</span></label>
            <input type="text" name="contact_phone" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['contact_phone']); ?>" 
                   placeholder="Emergency contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>
      
      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="contact_alt_phone" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['contact_alt_phone']); ?>" 
                   placeholder="Alternate emergency contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>

      <!-- Education -->
      <div class="form-section-title">
        <i class="fas fa-graduation-cap"></i> Education
      </div>
      
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Degree/University <span class="required">*</span></label>
            <input type="text" name="university_degree" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['university_degree']); ?>" 
                   placeholder="e.g. B.Tech, MBA" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Year of Completion <span class="required">*</span></label>
            <input type="text" name="year_completion" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['year_completion']); ?>" 
                   placeholder="e.g. 2025" pattern="[0-9]{4}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Percentage/CGPA <span class="required">*</span></label>
            <input type="text" name="percentage_cgpa" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['percentage_cgpa']); ?>" 
                   placeholder="e.g. 7.8 or 75%" required>
          </div>
        </div>
      </div>

      <!-- Bank Details -->
      <div class="form-section-title">
        <i class="fas fa-university"></i> Bank Details
      </div>
      
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Bank Account Number <span class="required">*</span></label>
            <input type="text" name="bank_account_number" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['bank_account_number']); ?>" 
                   placeholder="Account number" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>IFSC Code <span class="required">*</span></label>
            <input type="text" name="ifsc_code" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['ifsc_code']); ?>" 
                   style="text-transform:uppercase;" placeholder="e.g. SBIN0001234" 
                   pattern="[A-Z]{4}0[A-Z0-9]{6}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Bank Branch <span class="required">*</span></label>
            <input type="text" name="bank_branch" class="form-control" 
                   value="<?php echo htmlspecialchars($employee['bank_branch']); ?>" 
                   placeholder="Branch name" required>
          </div>
        </div>
      </div>

      <!-- EXISTING DOCUMENTS -->
      <?php
      $doc_query = mysqli_query($con, "SELECT * FROM hr_employee_documents WHERE employee_id = '$employee_unique_id' ORDER BY uploaded_at DESC");
      if(mysqli_num_rows($doc_query) > 0) {
      ?>
      <div class="form-section-title">
        <i class="fas fa-folder-open"></i> Existing Documents
      </div>
      <div class="row">
        <?php while($doc = mysqli_fetch_assoc($doc_query)) { ?>
        <div class="col-md-3 col-sm-6">
            <div class="doc-card">
                <a href="<?php echo $current_page; ?>?id=<?php echo $db_id; ?>&delete_doc=true&doc_id=<?php echo $doc['id']; ?>" class="btn-delete-doc" onclick="return confirm('Are you sure you want to delete this document?');" title="Delete">
                    <i class="fas fa-trash-alt"></i>
                </a>
                <a href="<?php echo $doc['filepath']; ?>" target="_blank" style="text-decoration: none;">
                    <div class="text-center">
                        <div class="doc-icon">
                            <?php 
                            $ext = strtolower(pathinfo($doc['filename'], PATHINFO_EXTENSION));
                            if(in_array($ext, ['jpg','jpeg','png'])) echo '<i class="fas fa-file-image"></i>';
                            elseif($ext == 'pdf') echo '<i class="fas fa-file-pdf"></i>';
                            elseif(in_array($ext, ['doc','docx'])) echo '<i class="fas fa-file-word"></i>';
                            else echo '<i class="fas fa-file"></i>';
                            ?>
                        </div>
                        <div class="doc-title"><?php echo htmlspecialchars($doc['document_type']); ?></div>
                        <div class="doc-date"><i class="far fa-calendar-alt"></i> <?php echo date('d M Y', strtotime($doc['uploaded_at'])); ?></div>
                    </div>
                </a>
            </div>
        </div>
        <?php } ?>
      </div>
      <?php } ?>

      <!-- NEW DOCUMENT UPLOAD -->
      <div class="form-section-title">
        <i class="fas fa-file-upload"></i> Upload New Documents
      </div>

      <div class="alert alert-info" style="border-radius: 8px; margin-bottom: 20px;">
        <strong>📏 Size Limits:</strong> Photos: <?php echo MAX_PHOTO_SIZE_MB; ?> MB | Documents: <?php echo MAX_DOCUMENT_SIZE_MB; ?> MB
      </div>

      <div id="documentUploadContainer">
        <div class="row" style="margin-bottom: 15px; padding: 15px; background: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;">
          <div class="col-md-4">
            <div class="form-group">
              <label>Document Type</label>
              <select name="document_type[]" class="form-control document-type-select">
                <option value="">Select Type</option>
                <option value="Aadhar Card">Aadhar Card</option>
                <option value="PAN Card">PAN Card</option>
                <option value="Passport">Passport</option>
                <option value="Driving License">Driving License</option>
                <option value="10th Marksheet">10th Marksheet</option>
                <option value="12th Marksheet">12th Marksheet</option>
                <option value="Degree Certificate">Degree Certificate</option>
                <option value="Resume/CV">Resume/CV</option>
                <option value="Experience Letter">Experience Letter</option>
                <option value="Bank Passbook">Bank Passbook</option>
                <option value="Cancelled Cheque">Cancelled Cheque</option>
                <option value="Photo">Photo</option>
                <option value="Medical Certificate">Medical Certificate</option>
                <option value="Police Verification">Police Verification</option>
                <option value="Other">Other (Custom Name)</option>
              </select>
            </div>
          </div>
          <div class="col-md-3">
            <div class="form-group">
              <label>Custom Name (if Other)</label>
              <input type="text" name="document_custom_name[]" class="form-control document-custom-name" 
                     placeholder="Document name" style="display:none;">
            </div>
          </div>
          <div class="col-md-4">
            <div class="form-group">
              <label>Choose File</label>
              <input type="file" name="document_file[]" class="form-control-file document-file-input" 
                     accept=".pdf,.jpg,.jpeg,.png,.doc,.docx" 
                     style="padding: 10px; border: 2px solid #e2e8f0; border-radius: 8px; width: 100%;">
            </div>
          </div>
          <div class="col-md-1">
            <div class="form-group">
              <label style="opacity: 0;">X</label><br>
              <button type="button" class="btn btn-danger btn-sm btn-remove-document" style="display:none; width: 100%;">
                <i class="fa fa-trash"></i>
              </button>
            </div>
          </div>
        </div>
      </div>

      <button type="button" class="btn btn-success" id="btnAddDocument" style="margin-bottom: 20px;">
        <i class="fa fa-plus"></i> Add Another Document
      </button>

      <!-- Submit Button -->
      <button type="submit" name="update_employee" class="btn-submit">
        <i class="fas fa-save"></i> Update Employee
      </button>
      
    </form>
  </div>

</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>

<script>
var documentRowCount = 1;
var locationData = <?php echo json_encode($location_data); ?>;
var preSelectedCountry = "<?php echo htmlspecialchars($employee['country'] ?? ''); ?>";
var preSelectedState = "<?php echo htmlspecialchars($employee['state'] ?? ''); ?>";

var MAX_PHOTO_SIZE = <?php echo MAX_PHOTO_SIZE_BYTES; ?>;
var MAX_DOCUMENT_SIZE = <?php echo MAX_DOCUMENT_SIZE_BYTES; ?>;

$(document).ready(function() {
  // Initialize Select2 for Reporting Manager dropdowns
  $('select[name="reporting_manager_1"]').select2({
    placeholder: 'Select Manager',
    allowClear: true,
    width: '100%'
  });
  
  $('select[name="reporting_manager_2"]').select2({
    placeholder: 'Select Manager',
    allowClear: true,
    width: '100%'
  });
  
  initializeLocationFilters();

  $('.timings-select').on('change', function() {
    var manual = $('.timings-manual');
    if ($(this).val() === 'Manual') {
      manual.show().prop('required', true);
    } else {
      manual.hide().prop('required', false).val('');
    }
  });

  $(document).on('change', '.document-file-input', function(e) {
    if (e.target.files.length > 0) {
      var file = e.target.files[0];
      var fileExt = file.name.split('.').pop().toLowerCase();
      var imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
      var maxSize = imageExtensions.includes(fileExt) ? MAX_PHOTO_SIZE : MAX_DOCUMENT_SIZE;
      
      if (file.size > maxSize) {
        alert('File is too large! Please compress and try again.');
        $(this).val('');
      }
    }
  });

  $(document).on('change', '.document-type-select', function() {
    var $customName = $(this).closest('.row').find('.document-custom-name');
    if ($(this).val() === 'Other') {
      $customName.show().prop('required', true);
    } else {
      $customName.hide().prop('required', false).val('');
    }
  });

  $('#btnAddDocument').on('click', function() {
    documentRowCount++;
    var newRow = `
      <div class="row" style="margin-bottom: 15px; padding: 15px; background: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;">
        <div class="col-md-4">
          <div class="form-group">
            <label>Document Type</label>
            <select name="document_type[]" class="form-control document-type-select">
              <option value="">Select Type</option>
              <option value="Aadhar Card">Aadhar Card</option>
              <option value="PAN Card">PAN Card</option>
              <option value="Passport">Passport</option>
              <option value="Driving License">Driving License</option>
              <option value="10th Marksheet">10th Marksheet</option>
              <option value="12th Marksheet">12th Marksheet</option>
              <option value="Degree Certificate">Degree Certificate</option>
              <option value="Resume/CV">Resume/CV</option>
              <option value="Experience Letter">Experience Letter</option>
              <option value="Bank Passbook">Bank Passbook</option>
              <option value="Cancelled Cheque">Cancelled Cheque</option>
              <option value="Photo">Photo</option>
              <option value="Medical Certificate">Medical Certificate</option>
              <option value="Police Verification">Police Verification</option>
              <option value="Other">Other (Custom Name)</option>
            </select>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Custom Name</label>
            <input type="text" name="document_custom_name[]" class="form-control document-custom-name" style="display:none;">
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Choose File</label>
            <input type="file" name="document_file[]" class="form-control-file document-file-input">
          </div>
        </div>
        <div class="col-md-1">
          <label style="opacity: 0;">X</label><br>
          <button type="button" class="btn btn-danger btn-sm btn-remove-document" style="width: 100%;">
            <i class="fa fa-trash"></i>
          </button>
        </div>
      </div>`;
    $('#documentUploadContainer').append(newRow);
  });

  $(document).on('click', '.btn-remove-document', function() {
    $(this).closest('.row').remove();
  });
});

function initializeLocationFilters() {
    const countrySelect = document.getElementById('country');
    const stateSelect = document.getElementById('state');
    
    if (Object.keys(locationData).length > 0) {
        Object.keys(locationData).sort().forEach(country => {
            const option = document.createElement('option');
            option.value = country;
            option.textContent = country;
            if (country === preSelectedCountry) option.selected = true;
            countrySelect.appendChild(option);
        });
    }

    if (preSelectedCountry) populateStates(preSelectedCountry, preSelectedState);
    
    countrySelect.addEventListener('change', function() {
        populateStates(this.value, '');
    });

    function populateStates(country, selectedState) {
        stateSelect.innerHTML = '<option value="">Select State</option>';
        if (country && locationData[country]) {
            let states = Array.isArray(locationData[country]) ? locationData[country] : Object.keys(locationData[country]);
            states.sort().forEach(state => {
                const option = document.createElement('option');
                option.value = state;
                option.textContent = state;
                if (state === selectedState) option.selected = true;
                stateSelect.appendChild(option);
            });
        }
    }
}
</script>

</body>
</html>