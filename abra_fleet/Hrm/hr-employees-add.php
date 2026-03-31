<?php
// =========================================================================
// EMPLOYEE ADD PAGE - Complete OCR Integration + Dynamic DB Fields
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
// FETCH MASTER DATA FROM DATABASE (Dynamic Dropdowns)
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

// 5. Fetch Companies
$company_sql = "SELECT * FROM hr_companies ORDER BY company_name ASC";
$company_query = mysqli_query($con, $company_sql);

// 6. Fetch All Employees for Reporting Manager Dropdown
$employees_sql = "SELECT employee_id, name FROM hr_employees WHERE status='Active' ORDER BY name ASC";
$employees_query = mysqli_query($con, $employees_sql);


// =========================================================================
// LOAD LOCATION DATA (For Country/State JSON)
// =========================================================================
define('LOCATIONS_FILE', __DIR__ . '/global_locations.json');
$location_data = [];
if (file_exists(LOCATIONS_FILE)) {
    $json_content = file_get_contents(LOCATIONS_FILE);
    $location_data = json_decode($json_content, true);
}

// =========================================================================
// CLEAR OCR SESSION
// =========================================================================
if (isset($_GET['clear_ocr'])) {
    if (isset($_SESSION['ocr_result'])) unset($_SESSION['ocr_result']);
    if (isset($_SESSION['ocr_success'])) unset($_SESSION['ocr_success']);
    if (isset($_SESSION['ocr_image_path'])) unset($_SESSION['ocr_image_path']);
    header("Location: $current_page");
    exit;
}

// =========================================================================
// STEP 1: CHECK FOR OCR DATA
// =========================================================================
$ocr_data = array();
$ocr_success = false;
$ocr_has_data = false;

if (isset($_SESSION['ocr_result'])) {
    $ocr_data = $_SESSION['ocr_result'];
    
    // Check if OCR actually extracted any useful data
    $ocr_has_data = !empty($ocr_data['name']) || 
                    !empty($ocr_data['email']) ||
                    !empty($ocr_data['phone']) || 
                    !empty($ocr_data['aadhar_card']) ||
                    !empty($ocr_data['pan_number']) ||
                    !empty($ocr_data['address']);
    
    if ($ocr_has_data) {
        $ocr_success = true;
    }
}

// =========================================================================
// STEP 2: INITIALIZE ALL FORM VARIABLES WITH OCR DATA
// =========================================================================

// Official Information
$email_value = !empty($ocr_data['email']) ? $ocr_data['email'] : '';
$hire_date_value = !empty($ocr_data['hire_date']) ? $ocr_data['hire_date'] : '';
$department_value = !empty($ocr_data['department']) ? $ocr_data['department'] : '';
$position_value = !empty($ocr_data['position']) ? $ocr_data['position'] : '';
$status_value = !empty($ocr_data['status']) ? $ocr_data['status'] : 'Active';
$employee_type_value = !empty($ocr_data['employee_type']) ? $ocr_data['employee_type'] : '';
$salary_value = !empty($ocr_data['salary']) ? $ocr_data['salary'] : '';
$work_location_value = !empty($ocr_data['work_location']) ? $ocr_data['work_location'] : '';
$timings_value = !empty($ocr_data['timings']) ? $ocr_data['timings'] : '';
$company_name_value = !empty($ocr_data['company_name']) ? $ocr_data['company_name'] : '';

// Personal Information
$name_value = !empty($ocr_data['name']) ? $ocr_data['name'] : '';
$gender_value = !empty($ocr_data['gender']) ? $ocr_data['gender'] : '';
$dob_value = !empty($ocr_data['dob']) ? $ocr_data['dob'] : '';
$blood_group_value = !empty($ocr_data['blood_group']) ? $ocr_data['blood_group'] : '';
$personal_email_value = !empty($ocr_data['personal_email']) ? $ocr_data['personal_email'] : '';
$phone_value = !empty($ocr_data['phone']) ? $ocr_data['phone'] : '';
$alt_phone_value = !empty($ocr_data['alt_phone']) ? $ocr_data['alt_phone'] : '';
$address_value = !empty($ocr_data['address']) ? $ocr_data['address'] : '';
$country_value = !empty($ocr_data['country']) ? $ocr_data['country'] : '';
$state_value = !empty($ocr_data['state']) ? $ocr_data['state'] : '';

// Identity Documents
$aadhar_card_value = !empty($ocr_data['aadhar_card']) ? $ocr_data['aadhar_card'] : '';
$pan_number_value = !empty($ocr_data['pan_number']) ? $ocr_data['pan_number'] : '';

// Emergency Contact
$contact_name_value = !empty($ocr_data['contact_name']) ? $ocr_data['contact_name'] : '';
$relationship_value = !empty($ocr_data['relationship']) ? $ocr_data['relationship'] : '';
$contact_phone_value = !empty($ocr_data['contact_phone']) ? $ocr_data['contact_phone'] : '';
$contact_alt_phone_value = !empty($ocr_data['contact_alt_phone']) ? $ocr_data['contact_alt_phone'] : '';

// Education
$university_degree_value = !empty($ocr_data['university_degree']) ? $ocr_data['university_degree'] : '';
$year_completion_value = !empty($ocr_data['year_completion']) ? $ocr_data['year_completion'] : '';
$percentage_cgpa_value = !empty($ocr_data['percentage_cgpa']) ? $ocr_data['percentage_cgpa'] : '';

// Bank Details
$bank_account_number_value = !empty($ocr_data['bank_account_number']) ? $ocr_data['bank_account_number'] : '';
$ifsc_code_value = !empty($ocr_data['ifsc_code']) ? $ocr_data['ifsc_code'] : '';
$bank_branch_value = !empty($ocr_data['bank_branch']) ? $ocr_data['bank_branch'] : '';

// Override with POST data if form was submitted
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add_employee'])) {
    $email_value = $_POST['email'];
    $hire_date_value = $_POST['hire_date'];
    $department_value = $_POST['department'];
    $position_value = $_POST['position'];
    $status_value = $_POST['status'];
    $employee_type_value = $_POST['employee_type'];
    $salary_value = $_POST['salary'];
    $work_location_value = $_POST['work_location'];
    $company_name_value = $_POST['company_name'];
    $name_value = $_POST['name'];
    $gender_value = $_POST['gender'];
    $dob_value = $_POST['dob'];
    $blood_group_value = $_POST['blood_group'];
    $personal_email_value = $_POST['personal_email'];
    $phone_value = $_POST['phone'];
    $alt_phone_value = $_POST['alt_phone'];
    $address_value = $_POST['address'];
    $country_value = $_POST['country'];
    $state_value = $_POST['state'];
    $aadhar_card_value = $_POST['aadhar_card'];
    $pan_number_value = $_POST['pan_number'];
    $contact_name_value = $_POST['contact_name'];
    $relationship_value = $_POST['relationship'];
    $contact_phone_value = $_POST['contact_phone'];
    $contact_alt_phone_value = $_POST['contact_alt_phone'];
    $university_degree_value = $_POST['university_degree'];
    $year_completion_value = $_POST['year_completion'];
    $percentage_cgpa_value = $_POST['percentage_cgpa'];
    $bank_account_number_value = $_POST['bank_account_number'];
    $ifsc_code_value = $_POST['ifsc_code'];
    $bank_branch_value = $_POST['bank_branch'];
}

// =========================================================================
// OCR PROCESSING
// =========================================================================
if (isset($_POST['process_ocr']) && isset($_FILES['ocr_image'])) {
    $file = $_FILES['ocr_image'];
    
    if ($file['error'] === UPLOAD_ERR_OK) {
        // Check file size (2 MB limit for OCR images)
        if ($file['size'] > MAX_PHOTO_SIZE_BYTES) {
            $actualSizeMB = round($file['size'] / (1024 * 1024), 2);
            $_SESSION['error_message'] = "⚠️ Image too large! Size: {$actualSizeMB} MB. Maximum allowed: " . MAX_PHOTO_SIZE_MB . " MB. Please compress and try again.";
            header("Location: $current_page");
            exit;
        }
        
        $allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
        $file_ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        
        if (in_array($file['type'], $allowed_types) || in_array($file_ext, ['jpg', 'jpeg', 'png', 'gif', 'webp'])) {
            $ocr_dir = 'uploads/ocr/';
            if (!file_exists($ocr_dir)) mkdir($ocr_dir, 0777, true);
            
            $filename = 'employee_scan_' . time() . '.' . $file_ext;
            $filepath = $ocr_dir . $filename;
            
            if (move_uploaded_file($file['tmp_name'], $filepath)) {
                
                $extracted_data = array();
                
                try {
                    // Run Tesseract OCR
                    $output = shell_exec("tesseract " . escapeshellarg($filepath) . " stdout 2>&1");
                    
                    if (!empty($output)) {
                        
                        // Basic Regex Extraction
                        if (preg_match('/Name:\s*(.+?)(?:\n|$)/im', $output, $matches)) {
                            $extracted_data['name'] = trim($matches[1]);
                        }
                        
                        // Emails
                        if (preg_match_all('/\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b/i', $output, $matches)) {
                            foreach ($matches[1] as $email) {
                                if (preg_match('/Official\s+Email:/i', $output) && strpos($output, $email) !== false) {
                                    $extracted_data['email'] = $email;
                                } elseif (!isset($extracted_data['email'])) {
                                    $extracted_data['email'] = $email; // Fallback
                                }
                            }
                        }
                        
                        // Phone numbers
                        if (preg_match_all('/\b([6-9][0-9]{9})\b/', $output, $matches)) {
                            $extracted_data['phone'] = isset($matches[1][0]) ? $matches[1][0] : '';
                            $extracted_data['alt_phone'] = isset($matches[1][1]) ? $matches[1][1] : '';
                        }
                        
                        // IDs
                        if (preg_match('/Aadhar:\s*([0-9]{12})/i', $output, $matches)) {
                            $extracted_data['aadhar_card'] = $matches[1];
                        }
                        
                        if (preg_match('/PAN:\s*([A-Z]{5}[0-9]{4}[A-Z]{1})/i', $output, $matches)) {
                            $extracted_data['pan_number'] = strtoupper($matches[1]);
                        }
                        
                        // Address
                        if (preg_match('/Address:\s*(.+?)(?:\n|$)/is', $output, $matches)) {
                            $extracted_data['address'] = preg_replace('/\s+/', ' ', trim($matches[1]));
                        }
                        
                        // Attempt to match Department/Position from text against DB (Simple fuzzy check)
                        // This is optional but helpful
                        
                    }
                    
                    if (empty($extracted_data)) {
                        $_SESSION['error_message'] = "Could not extract data. Please ensure the image is clear.";
                    } else {
                        $_SESSION['ocr_result'] = $extracted_data;
                        $_SESSION['ocr_success'] = true;
                        $_SESSION['ocr_image_path'] = $filepath;
                        header("Location: $current_page?ocr=success");
                        exit;
                    }
                    
                } catch (Exception $e) {
                    $_SESSION['error_message'] = "OCR error: " . $e->getMessage();
                    header("Location: $current_page");
                    exit;
                }
            }
        } else {
            $_SESSION['error_message'] = "Invalid file type.";
            header("Location: $current_page");
            exit;
        }
    }
}

// =========================================================================
// ADD EMPLOYEE WITH DOCUMENT UPLOAD
// =========================================================================
if (isset($_POST['add_employee'])) {
    try {
        // Auto-generate Employee ID
        $id_sql = "SELECT employee_id FROM hr_employees WHERE employee_id LIKE 'AT%' 
                   ORDER BY CAST(SUBSTRING(employee_id, 5) AS UNSIGNED) DESC LIMIT 1";
        $id_query = $con->query($id_sql);
        
        if ($id_query && $id_query->num_rows > 0) {
            $row = $id_query->fetch_assoc();
            if (preg_match('/AT(\d+)/', $row['employee_id'], $matches)) {
                $number = (int)$matches[1] + 1;
                $employee_id = "AT" . str_pad($number, 3, "0", STR_PAD_LEFT);
            } else {
                $employee_id = "AT001";
            }
        } else {
            $employee_id = "AT001";
        }
        
        // Collect form data
        $name = mysqli_real_escape_string($con, trim($name_value));
        $gender = mysqli_real_escape_string($con, trim($gender_value));
        $dob = mysqli_real_escape_string($con, trim($dob_value));
        $blood_group = mysqli_real_escape_string($con, trim($blood_group_value));
        $personal_email = mysqli_real_escape_string($con, trim($personal_email_value));
        $phone = mysqli_real_escape_string($con, trim($phone_value));
        $alt_phone = mysqli_real_escape_string($con, trim($alt_phone_value));
        $address = mysqli_real_escape_string($con, trim($address_value));
        $country = mysqli_real_escape_string($con, trim($country_value));
        $state = mysqli_real_escape_string($con, trim($state_value));
        $aadhar_card = mysqli_real_escape_string($con, trim($aadhar_card_value));
        $pan_number = strtoupper(mysqli_real_escape_string($con, trim($pan_number_value)));
        $contact_name = mysqli_real_escape_string($con, trim($contact_name_value));
        $relationship = mysqli_real_escape_string($con, trim($relationship_value));
        $contact_phone = mysqli_real_escape_string($con, trim($contact_phone_value));
        $contact_alt_phone = mysqli_real_escape_string($con, trim($contact_alt_phone_value));
        $university_degree = mysqli_real_escape_string($con, trim($university_degree_value));
        $year_completion = mysqli_real_escape_string($con, trim($year_completion_value));
        $percentage_cgpa = mysqli_real_escape_string($con, trim($percentage_cgpa_value));
        $bank_account_number = mysqli_real_escape_string($con, trim($bank_account_number_value));
        $ifsc_code = strtoupper(mysqli_real_escape_string($con, trim($ifsc_code_value)));
        $bank_branch = mysqli_real_escape_string($con, trim($bank_branch_value));
        $email = mysqli_real_escape_string($con, trim($email_value));
        $hire_date = mysqli_real_escape_string($con, trim($hire_date_value));
        $department = mysqli_real_escape_string($con, trim($department_value));
        $position = mysqli_real_escape_string($con, trim($position_value));
        $salary = mysqli_real_escape_string($con, trim($salary_value));
        $work_location = mysqli_real_escape_string($con, trim($work_location_value));
        $company_name = mysqli_real_escape_string($con, trim($company_name_value));
        $employee_type = mysqli_real_escape_string($con, trim($employee_type_value));
        
        $timings = mysqli_real_escape_string($con, trim($_POST['timings_select']));
        if($timings == 'Manual') {
            $timings = mysqli_real_escape_string($con, trim($_POST['timings_manual']));
        }
        
        $status = mysqli_real_escape_string($con, trim($status_value));
        
        // Reporting Managers
        $reporting_manager_1 = mysqli_real_escape_string($con, trim($_POST['reporting_manager_1']));
        $reporting_manager_2 = mysqli_real_escape_string($con, trim($_POST['reporting_manager_2']));

        // Insert employee record
        $sql = "INSERT INTO hr_employees (
            employee_id, name, gender, dob, blood_group, personal_email, phone, alt_phone, address, country, state,
            aadhar_card, pan_number, contact_name, relationship, contact_phone, contact_alt_phone,
            university_degree, year_completion, percentage_cgpa,
            bank_account_number, ifsc_code, bank_branch,
            email, hire_date, department, position, reporting_manager_1, reporting_manager_2, salary, work_location, timings, company_name, status, employee_type
        ) VALUES (
            '$employee_id', '$name', '$gender', '$dob', '$blood_group', '$personal_email', '$phone', '$alt_phone', '$address', '$country', '$state',
            '$aadhar_card', '$pan_number', '$contact_name', '$relationship', '$contact_phone', '$contact_alt_phone',
            '$university_degree', '$year_completion', '$percentage_cgpa',
            '$bank_account_number', '$ifsc_code', '$bank_branch',
            '$email', '$hire_date', '$department', '$position', '$reporting_manager_1', '$reporting_manager_2', '$salary', '$work_location', '$timings', '$company_name', '$status', '$employee_type'
        )";

        if(mysqli_query($con, $sql)) {
            $inserted_id = mysqli_insert_id($con);
            
            // Initialize uploaded docs counter
            $uploaded_docs = [];
            
            // =========================================================================
            // HANDLE DOCUMENT UPLOADS WITH FILE SIZE VALIDATION
            // =========================================================================
            if (isset($_FILES['document_file']) && is_array($_FILES['document_file']['name'])) {
                $upload_dir = 'uploads/employee_documents/' . $employee_id . '/';
                if (!file_exists($upload_dir)) {
                    mkdir($upload_dir, 0777, true);
                }
                
                $document_types = $_POST['document_type'];
                $custom_names = $_POST['document_custom_name'];
                $size_errors = [];
                
                foreach ($_FILES['document_file']['name'] as $key => $filename) {
                    if ($_FILES['document_file']['error'][$key] === UPLOAD_ERR_OK && !empty($filename)) {
                        
                        // FILE SIZE VALIDATION
                        $file_size = $_FILES['document_file']['size'][$key];
                        $file_ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
                        
                        // Check if it's a photo/image
                        $image_extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
                        $max_size = in_array($file_ext, $image_extensions) ? MAX_PHOTO_SIZE_BYTES : MAX_DOCUMENT_SIZE_BYTES;
                        $max_size_mb = in_array($file_ext, $image_extensions) ? MAX_PHOTO_SIZE_MB : MAX_DOCUMENT_SIZE_MB;
                        
                        if ($file_size > $max_size) {
                            $actual_size_mb = round($file_size / (1024 * 1024), 2);
                            $size_errors[] = "$filename - {$actual_size_mb} MB (Max: {$max_size_mb} MB)";
                            continue; // Skip this file
                        }
                        
                        $doc_type = $document_types[$key];
                        
                        // If "Other" is selected, use custom name
                        if ($doc_type === 'Other' && !empty($custom_names[$key])) {
                            $doc_type = $custom_names[$key];
                        }
                        
                        // Skip if no document type selected
                        if (empty($doc_type)) continue;
                        
                        $new_filename = $employee_id . '_' . preg_replace('/[^a-zA-Z0-9]/', '_', $doc_type) . '_' . time() . '.' . $file_ext;
                        $target_path = $upload_dir . $new_filename;
                        
                        if (move_uploaded_file($_FILES['document_file']['tmp_name'][$key], $target_path)) {
                            $uploaded_docs[] = [
                                'type' => $doc_type,
                                'filename' => $new_filename,
                                'filepath' => $target_path
                            ];
                        }
                    }
                }
                
                // Store document info in database
                if (!empty($uploaded_docs)) {
                    foreach ($uploaded_docs as $doc) {
                        $doc_type_db = mysqli_real_escape_string($con, $doc['type']);
                        $doc_filename_db = mysqli_real_escape_string($con, $doc['filename']);
                        $doc_filepath_db = mysqli_real_escape_string($con, $doc['filepath']);
                        
                        $doc_sql = "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath, uploaded_at) 
            VALUES ('$employee_id', '$doc_type_db', '$doc_filename_db', '$doc_filepath_db', NOW())";
                        mysqli_query($con, $doc_sql);
                    }
                }
                
                // Show size error warnings if any
                if (!empty($size_errors)) {
                    $_SESSION['warning_message'] = "⚠️ Some files were too large and skipped:<br>" . implode('<br>', $size_errors) . "<br><br>Please compress these files and upload them separately.";
                }
            }
            
            // Clear OCR data after successful submission
            if (isset($_SESSION['ocr_result'])) {
                unset($_SESSION['ocr_result']);
            }
            
            $_SESSION['success_message'] = "Employee Added Successfully! Employee ID: " . $employee_id . " | " . count($uploaded_docs) . " document(s) uploaded.";
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
<title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra Travels'; ?> | Add Employee</title>
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

    /* OCR Button */
    .btn-ocr {
      background: linear-gradient(135deg, #ec4899 0%, #db2777 100%);
      color: white;
      padding: 12px 24px;
      border-radius: 10px;
      border: none;
      font-weight: 700;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      cursor: pointer;
      box-shadow: 0 4px 15px rgba(236, 72, 153, 0.3);
      transition: all 0.3s;
    }
    
    .btn-ocr:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(236, 72, 153, 0.4);
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

    /* ✅ OCR HIGHLIGHT STYLES */
    .ocr-highlight {
      background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%) !important;
      border-color: #f59e0b !important;
      box-shadow: 0 0 0 4px rgba(245, 158, 11, 0.15) !important;
      animation: highlightPulse 2s ease-in-out;
      font-weight: 700 !important;
      color: #92400e !important;
    }

    @keyframes highlightPulse {
      0%, 100% { transform: scale(1); }
      50% { transform: scale(1.02); }
    }

    /* Document Upload Row */
    .document-upload-row {
      background: #f8fafc;
      padding: 15px;
      border-radius: 8px;
      margin-bottom: 15px;
      border: 2px dashed #e2e8f0;
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

    /* Modal Styles */
    .modal-content {
      border-radius: 15px;
      border: none;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
    }
    
    .modal-header {
      background: linear-gradient(135deg, #ec4899 0%, #db2777 100%);
      color: white;
      border-radius: 15px 15px 0 0;
      padding: 20px 30px;
    }
    
    .modal-body {
      padding: 30px;
    }

    /* Upload Zone */
    .upload-zone {
      border: 3px dashed #e2e8f0;
      border-radius: 16px;
      padding: 50px;
      text-align: center;
      transition: all 0.3s;
      cursor: pointer;
      background: #f8fafc;
    }
    
    .upload-zone:hover {
      border-color: #ec4899;
      background: #fdf2f8;
    }

    /* OCR Success Alert */
    .alert-modern {
      border-radius: 16px;
      padding: 20px 30px;
      margin-bottom: 30px;
      border: none;
      box-shadow: 0 4px 15px rgba(0,0,0,0.1);
      display: flex;
      align-items: flex-start;
      gap: 15px;
    }
    
    .alert-warning-modern {
      background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%);
      color: #92400e;
      border-left: 5px solid #f59e0b;
    }

    /* Clear Form Link */
    .clear-form-link {
      color: #dc2626;
      text-decoration: underline;
      font-weight: 600;
      margin-left: 20px;
      display: inline-flex;
      align-items: center;
      gap: 5px;
    }
    
    /* Optgroup styling */
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
    <h1><i class="fas fa-user-plus"></i> Add New Employee</h1>
    <div style="display: flex; gap: 15px; align-items: center;">
      <button type="button" class="btn-ocr" onclick="$('#ocrModal').modal('show')">
        <i class="fas fa-camera"></i> Scan Document
      </button>
      <a href="hr-employees-list.php" class="btn-back">
        <i class="fas fa-arrow-left"></i> Back to List
      </a>
    </div>
  </div>

  <?php if ($ocr_success && isset($_SESSION['ocr_result'])): ?>
  <!-- OCR Success Banner -->
  <div class="alert alert-modern alert-warning-modern">
    <i class="fa fa-magic" style="font-size: 24px;"></i>
    <div style="flex: 1;">
      <strong>🎉 OCR Scan Complete!</strong><br>
      Employee details have been automatically extracted from your document. Fields highlighted in <span style="background: #fef3c7; padding: 2px 6px; border-radius: 4px; font-weight: 700;">yellow</span> were auto-filled.
      <br><br>
      <strong>📋 Extracted Data:</strong>
      <ul style="margin: 8px 0 0 20px;">
        <?php if (!empty($ocr_data['name'])): ?>
          <li><strong>Name:</strong> <?php echo htmlspecialchars($ocr_data['name']); ?></li>
        <?php endif; ?>
        <?php if (!empty($ocr_data['email'])): ?>
          <li><strong>Official Email:</strong> <?php echo htmlspecialchars($ocr_data['email']); ?></li>
        <?php endif; ?>
        <?php if (!empty($ocr_data['phone'])): ?>
          <li><strong>Mobile:</strong> <?php echo htmlspecialchars($ocr_data['phone']); ?></li>
        <?php endif; ?>
        <?php if (!empty($ocr_data['aadhar_card'])): ?>
          <li><strong>Aadhar:</strong> <?php echo htmlspecialchars($ocr_data['aadhar_card']); ?></li>
        <?php endif; ?>
        <?php if (!empty($ocr_data['pan_number'])): ?>
          <li><strong>PAN:</strong> <?php echo htmlspecialchars($ocr_data['pan_number']); ?></li>
        <?php endif; ?>
      </ul>
      <br>
      <strong>⚠️ Note:</strong> Please verify the extracted data and fill in any missing required fields before saving.
      <div style="margin-top: 15px;">
        <button type="button" class="btn btn-ocr" onclick="$('#ocrModal').modal('show')" style="margin-right: 15px;">
          <i class="fas fa-camera"></i> Scan Another Document
        </button>
        <a href="<?php echo $current_page; ?>?clear_ocr=1" class="clear-form-link">
          <i class="fa fa-times-circle"></i> Clear Form & Start Fresh
        </a>
      </div>
    </div>
  </div>
  <?php endif; ?>

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
            <input type="email" name="email" 
                   class="form-control <?php echo !empty($email_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($email_value); ?>" 
                   placeholder="name@company.com" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Date of Joining <span class="required">*</span></label>
            <input type="date" name="hire_date" 
                   class="form-control <?php echo !empty($hire_date_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($hire_date_value); ?>" 
                   required>
          </div>
        </div>
        
        <!-- DYNAMIC DEPARTMENT -->
        <div class="col-md-4">
          <div class="form-group">
            <label>Department <span class="required">*</span></label>
            <select name="department" class="form-control <?php echo !empty($department_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="">Select Department</option>
              <?php
              if(mysqli_num_rows($dept_query) > 0) {
                  mysqli_data_seek($dept_query, 0); // Reset pointer
                  while($row = mysqli_fetch_assoc($dept_query)) {
                      $selected = ($department_value == $row['name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['name']).'" '.$selected.'>'.htmlspecialchars($row['name']).'</option>';
                  }
              }
              ?>
            </select>
          </div>
        </div>
      </div>

      <div class="row">
        <!-- DYNAMIC POSITION -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Designation/Position <span class="required">*</span></label>
            <select name="position" class="form-control <?php echo !empty($position_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
                <option value="">Select Position</option>
                <?php
                if(mysqli_num_rows($pos_query) > 0) {
                    mysqli_data_seek($pos_query, 0);
                    while($row = mysqli_fetch_assoc($pos_query)) {
                        $selected = ($position_value == $row['title']) ? 'selected' : '';
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
                        echo '<option value="'.htmlspecialchars($row['employee_id']).'">'.htmlspecialchars($row['name']).' ('.htmlspecialchars($row['employee_id']).')</option>';
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
                        echo '<option value="'.htmlspecialchars($row['employee_id']).'">'.htmlspecialchars($row['name']).' ('.htmlspecialchars($row['employee_id']).')</option>';
                    }
                }
                ?>
            </select>
          </div>
        </div>
        
        <div class="col-md-3">
          <div class="form-group">
            <label>Status <span class="required">*</span></label>
            <select name="status" class="form-control <?php echo !empty($status_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="Active" <?php echo ($status_value == 'Active') ? 'selected' : ''; ?>>Active</option>
              <option value="Inactive" <?php echo ($status_value == 'Inactive') ? 'selected' : ''; ?>>Inactive</option>
              <option value="Terminated" <?php echo ($status_value == 'Terminated') ? 'selected' : ''; ?>>Terminated</option>
            </select>
          </div>
        </div>
      </div>

      <div class="row">
        <!-- NEW EMPLOYEE TYPE DROPDOWN -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Employee Type <span class="required">*</span></label>
            <select name="employee_type" class="form-control" required>
              <option value="">Select Type</option>
              <option value="Probation period" <?php echo ($employee_type_value == 'Probation period') ? 'selected' : ''; ?>>Probation period</option>
              <option value="Permanent Employee" <?php echo ($employee_type_value == 'Permanent Employee') ? 'selected' : ''; ?>>Permanent Employee</option>
            </select>
          </div>
        </div>

        <div class="col-md-3">
          <div class="form-group">
            <label>Total Salary (₹) <span class="required">*</span></label>
            <input type="number" step="0.01" name="salary" 
                   class="form-control <?php echo !empty($salary_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($salary_value); ?>"
                   placeholder="e.g. 35000" required>
          </div>
        </div>
      </div>

      <div class="row">
        <!-- DYNAMIC WORK LOCATION -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Work Location <span class="required">*</span></label>
            <select name="work_location" class="form-control <?php echo !empty($work_location_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="">Select Location</option>
              <?php
              if(mysqli_num_rows($loc_query) > 0) {
                  mysqli_data_seek($loc_query, 0);
                  while($row = mysqli_fetch_assoc($loc_query)) {
                      $selected = ($work_location_value == $row['location_name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['location_name']).'" '.$selected.'>'.htmlspecialchars($row['location_name']).'</option>';
                  }
              }
              ?>
              <option value="Other" <?php echo ($work_location_value == 'Other') ? 'selected' : ''; ?>>Other</option>
            </select>
          </div>
        </div>
        
        <!-- DYNAMIC COMPANY NAME DROPDOWN -->
        <div class="col-md-3">
          <div class="form-group">
            <label>Company Name <span class="required">*</span></label>
            <select name="company_name" class="form-control <?php echo !empty($company_name_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="">Select Company</option>
              <?php
              if(mysqli_num_rows($company_query) > 0) {
                  mysqli_data_seek($company_query, 0);
                  while($row = mysqli_fetch_assoc($company_query)) {
                      $selected = ($company_name_value == $row['company_name']) ? 'selected' : '';
                      echo '<option value="'.htmlspecialchars($row['company_name']).'" '.$selected.'>'.htmlspecialchars($row['company_name']).'</option>';
                  }
              }
              ?>
            </select>
          </div>
        </div>
        
        <!-- DYNAMIC TIMINGS -->
        <div class="col-md-6">
          <div class="form-group">
            <label>Timings <span class="required">*</span></label>
            <div class="row">
              <div class="col-md-6">
                <select name="timings_select" class="form-control timings-select <?php echo !empty($timings_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
                  <option value="">Select Shift</option>
                  <?php
                  if(mysqli_num_rows($time_query) > 0) {
                      mysqli_data_seek($time_query, 0);
                      while($row = mysqli_fetch_assoc($time_query)) {
                          $timing_str = $row['start_time'] . ' - ' . $row['end_time'];
                          $selected = ($timings_value == $timing_str) ? 'selected' : '';
                          echo '<option value="'.htmlspecialchars($timing_str).'" '.$selected.'>'.htmlspecialchars($timing_str).'</option>';
                      }
                  }
                  ?>
                  <option value="Manual">Custom Timings (Manual Entry)</option>
                </select>
              </div>
              <div class="col-md-6">
                <input type="text" name="timings_manual" class="form-control timings-manual" 
                       style="display:none;" placeholder="e.g. 10:00 AM - 7:00 PM">
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
            <input type="text" name="name" 
                   class="form-control <?php echo !empty($name_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($name_value); ?>" 
                   placeholder="Enter full name" required>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Gender <span class="required">*</span></label>
            <select name="gender" class="form-control <?php echo !empty($gender_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="">Select</option>
              <option value="Male" <?php echo ($gender_value == 'Male') ? 'selected' : ''; ?>>Male</option>
              <option value="Female" <?php echo ($gender_value == 'Female') ? 'selected' : ''; ?>>Female</option>
              <option value="Other" <?php echo ($gender_value == 'Other') ? 'selected' : ''; ?>>Other</option>
            </select>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Date of Birth <span class="required">*</span></label>
            <input type="date" name="dob" 
                   class="form-control <?php echo !empty($dob_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($dob_value); ?>" 
                   required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Blood Group <span class="required">*</span></label>
            <select name="blood_group" class="form-control <?php echo !empty($blood_group_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" required>
              <option value="">Select</option>
              <option value="A+" <?php echo ($blood_group_value == 'A+') ? 'selected' : ''; ?>>A+</option>
              <option value="A-" <?php echo ($blood_group_value == 'A-') ? 'selected' : ''; ?>>A-</option>
              <option value="B+" <?php echo ($blood_group_value == 'B+') ? 'selected' : ''; ?>>B+</option>
              <option value="B-" <?php echo ($blood_group_value == 'B-') ? 'selected' : ''; ?>>B-</option>
              <option value="O+" <?php echo ($blood_group_value == 'O+') ? 'selected' : ''; ?>>O+</option>
              <option value="O-" <?php echo ($blood_group_value == 'O-') ? 'selected' : ''; ?>>O-</option>
              <option value="AB+" <?php echo ($blood_group_value == 'AB+') ? 'selected' : ''; ?>>AB+</option>
              <option value="AB-" <?php echo ($blood_group_value == 'AB-') ? 'selected' : ''; ?>>AB-</option>
            </select>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Mobile Number <span class="required">*</span></label>
            <input type="text" name="phone" 
                   class="form-control <?php echo !empty($phone_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($phone_value); ?>" 
                   placeholder="10 digit mobile" pattern="[0-9]{10}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="alt_phone" 
                   class="form-control <?php echo !empty($alt_phone_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($alt_phone_value); ?>"
                   placeholder="Alternate contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Personal Email</label>
            <input type="email" name="personal_email" 
                   class="form-control <?php echo !empty($personal_email_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($personal_email_value); ?>"
                   placeholder="personal@email.com">
          </div>
        </div>
      </div>

      <!-- New Location Fields Row -->
      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Country <span class="required">*</span></label>
            <select name="country" id="country" class="form-control" required>
              <option value="">Select Country</option>
              <!-- Populated by JS -->
            </select>
          </div>
        </div>
        <div class="col-md-6">
          <div class="form-group">
            <label>State <span class="required">*</span></label>
            <select name="state" id="state" class="form-control" required>
              <option value="">Select State</option>
              <!-- Populated by JS -->
            </select>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Residential Address <span class="required">*</span></label>
            <textarea name="address" 
                      class="form-control <?php echo !empty($address_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                      rows="3" 
                      placeholder="Full address with pincode" required><?php echo htmlspecialchars($address_value); ?></textarea>
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
            <input type="text" name="aadhar_card" 
                   class="form-control <?php echo !empty($aadhar_card_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($aadhar_card_value); ?>" 
                   placeholder="12 digit Aadhar" pattern="[0-9]{12}" required>
          </div>
        </div>
        <div class="col-md-6">
          <div class="form-group">
            <label>PAN Number <span class="required">*</span></label>
            <input type="text" name="pan_number" 
                   class="form-control <?php echo !empty($pan_number_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($pan_number_value); ?>" 
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
            <input type="text" name="contact_name" 
                   class="form-control <?php echo !empty($contact_name_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($contact_name_value); ?>"
                   placeholder="Emergency contact name" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Relationship <span class="required">*</span></label>
            <input type="text" name="relationship" 
                   class="form-control <?php echo !empty($relationship_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($relationship_value); ?>"
                   placeholder="Father, Spouse, etc." required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Phone Number <span class="required">*</span></label>
            <input type="text" name="contact_phone" 
                   class="form-control <?php echo !empty($contact_phone_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($contact_phone_value); ?>"
                   placeholder="Emergency contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>
      
      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="contact_alt_phone" 
                   class="form-control <?php echo !empty($contact_alt_phone_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($contact_alt_phone_value); ?>"
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
            <input type="text" name="university_degree" 
                   class="form-control <?php echo !empty($university_degree_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($university_degree_value); ?>"
                   placeholder="e.g. B.Tech, MBA" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Year of Completion <span class="required">*</span></label>
            <input type="text" name="year_completion" 
                   class="form-control <?php echo !empty($year_completion_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($year_completion_value); ?>"
                   placeholder="e.g. 2025" pattern="[0-9]{4}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Percentage/CGPA <span class="required">*</span></label>
            <input type="text" name="percentage_cgpa" 
                   class="form-control <?php echo !empty($percentage_cgpa_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($percentage_cgpa_value); ?>"
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
            <input type="text" name="bank_account_number" 
                   class="form-control <?php echo !empty($bank_account_number_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($bank_account_number_value); ?>"
                   placeholder="Account number" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>IFSC Code <span class="required">*</span></label>
            <input type="text" name="ifsc_code" 
                   class="form-control <?php echo !empty($ifsc_code_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($ifsc_code_value); ?>"
                   style="text-transform:uppercase;" placeholder="e.g. SBIN0001234" 
                   pattern="[A-Z]{4}0[A-Z0-9]{6}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Bank Branch <span class="required">*</span></label>
            <input type="text" name="bank_branch" 
                   class="form-control <?php echo !empty($bank_branch_value) && $ocr_success ? 'ocr-highlight' : ''; ?>" 
                   value="<?php echo htmlspecialchars($bank_branch_value); ?>"
                   placeholder="Branch name" required>
          </div>
        </div>
      </div>

      <!-- Document Upload Section -->
      <div class="form-section-title">
        <i class="fas fa-file-upload"></i> Upload Documents
      </div>

      <div class="alert alert-info" style="border-radius: 8px; margin-bottom: 20px;">
        <strong>📄 Upload Documents:</strong> Aadhar, PAN, Resume, etc. | <strong>Formats:</strong> PDF, JPG, PNG, DOC, DOCX<br>
        <strong>📏 Size Limits:</strong> Photos/Images: <?php echo MAX_PHOTO_SIZE_MB; ?> MB | Documents: <?php echo MAX_DOCUMENT_SIZE_MB; ?> MB
      </div>

      <!-- Document Upload Repeater -->
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
      <button type="submit" name="add_employee" class="btn-submit">
        <i class="fas fa-save"></i> Save Employee
      </button>
      
    </form>
  </div>

</div>

<!-- OCR SCAN MODAL -->
<div class="modal fade" id="ocrModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h4 class="modal-title"><i class="fas fa-camera"></i> Scan Employee Document (AI-Powered OCR)</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST" enctype="multipart/form-data">
        <div class="modal-body">
          <div class="alert alert-info" style="border-radius: 12px; border: none;">
            <strong><i class="fas fa-magic"></i> OCR Technology</strong><br>
            Upload a photo of ID card, document, or form. AI will extract all visible information automatically.<br>
            <strong>📏 Size Limit:</strong> Maximum <?php echo MAX_PHOTO_SIZE_MB; ?> MB
          </div>
          
          <div class="form-group">
            <label style="font-weight: 600; margin-bottom: 12px;">
              <i class="fas fa-camera"></i> Upload Document Image
            </label>
            <div class="upload-zone" onclick="document.getElementById('ocrImage').click()">
              <i class="fas fa-camera" style="font-size: 64px; color: #ec4899; margin-bottom: 20px;"></i>
              <h4 style="margin: 0 0 8px 0; font-weight: 700; color: #475569;">Take Photo or Upload Image</h4>
              <p style="color: #94a3b8; margin: 0 0 16px 0;">Supports JPG, PNG, GIF formats (Max: <?php echo MAX_PHOTO_SIZE_MB; ?> MB)</p>
              <input type="file" name="ocr_image" id="ocrImage" accept="image/*" capture="environment" required style="display: none;">
              <button type="button" class="btn" style="background: linear-gradient(135deg, #ec4899 0%, #db2777 100%); color: white; border: none; padding: 12px 28px; border-radius: 10px; font-weight: 700; pointer-events: none;">
                <i class="fas fa-camera"></i> Choose Image
              </button>
              <p id="ocrFileName" style="margin-top: 15px; font-weight: 600; color: #ec4899;"></p>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" name="process_ocr" class="btn" style="background: linear-gradient(135deg, #ec4899 0%, #db2777 100%); color: white; border: none; font-weight: 700; padding: 10px 24px;">
            <i class="fas fa-magic"></i> Process Document
          </button>
        </div>
      </form>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>

<script>
var documentRowCount = 1;
var maxDocuments = 10;
var locationData = <?php echo json_encode($location_data); ?>;
var preSelectedCountry = "<?php echo htmlspecialchars($country_value); ?>";
var preSelectedState = "<?php echo htmlspecialchars($state_value); ?>";

// File size constants (in bytes)
var MAX_PHOTO_SIZE = <?php echo MAX_PHOTO_SIZE_BYTES; ?>;
var MAX_DOCUMENT_SIZE = <?php echo MAX_DOCUMENT_SIZE_BYTES; ?>;
var MAX_PHOTO_SIZE_MB = <?php echo MAX_PHOTO_SIZE_MB; ?>;
var MAX_DOCUMENT_SIZE_MB = <?php echo MAX_DOCUMENT_SIZE_MB; ?>;

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
  
  // Initialize Location Dropdowns
  initializeLocationFilters();

  // Timings selector
  $('.timings-select').on('change', function() {
    var manual = $('.timings-manual');
    if ($(this).val() === 'Manual') {
      manual.show().prop('required', true);
    } else {
      manual.hide().prop('required', false).val('');
    }
  });

  // OCR file upload with size validation
  $('#ocrImage').on('change', function(e) {
    if (e.target.files.length > 0) {
      var file = e.target.files[0];
      var fileSize = file.size;
      
      if (fileSize > MAX_PHOTO_SIZE) {
        var actualSizeMB = (fileSize / (1024 * 1024)).toFixed(2);
        alert('⚠️ IMAGE TOO LARGE!\n\n' +
              'File: ' + file.name + '\n' +
              'Size: ' + actualSizeMB + ' MB\n' +
              'Maximum allowed: ' + MAX_PHOTO_SIZE_MB + ' MB\n\n' +
              'Please compress the image and try again.\n\n' +
              'Tips:\n' +
              '• Use online compression tools\n' +
              '• Reduce image quality/resolution');
        $(this).val(''); // Clear the input
        $('#ocrFileName').text('');
        return false;
      }
      
      $('#ocrFileName').text('✓ Selected: ' + file.name + ' (' + (fileSize / (1024 * 1024)).toFixed(2) + ' MB)');
    }
  });

  // Document file size validation
  $(document).on('change', '.document-file-input', function(e) {
    if (e.target.files.length > 0) {
      var file = e.target.files[0];
      var fileSize = file.size;
      var fileName = file.name;
      var fileExt = fileName.split('.').pop().toLowerCase();
      
      // Check if it's an image
      var imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
      var maxSize = imageExtensions.includes(fileExt) ? MAX_PHOTO_SIZE : MAX_DOCUMENT_SIZE;
      var maxSizeMB = imageExtensions.includes(fileExt) ? MAX_PHOTO_SIZE_MB : MAX_DOCUMENT_SIZE_MB;
      var fileType = imageExtensions.includes(fileExt) ? 'photo/image' : 'document';
      
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
        $(this).val(''); // Clear the input
        return false;
      }
    }
  });

  // Auto-dismiss alerts
  setTimeout(function() {
    $('.alert').fadeOut('slow');
  }, 8000);

  // Document type selector - show/hide custom name field
  $(document).on('change', '.document-type-select', function() {
    var $customName = $(this).closest('.row').find('.document-custom-name');
    if ($(this).val() === 'Other') {
      $customName.show().prop('required', true);
    } else {
      $customName.hide().prop('required', false).val('');
    }
  });

  // Add document row - creates fresh HTML
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
            <button type="button" class="btn btn-danger btn-sm btn-remove-document" style="width: 100%;">
              <i class="fa fa-trash"></i>
            </button>
          </div>
        </div>
      </div>
    `;
    $('#documentUploadContainer').append(newRow);
  });

  // Remove document row
  $(document).on('click', '.btn-remove-document', function() {
    $(this).closest('.row').remove();
    documentRowCount--;
  });

  // Form validation on submit
  $('#employeeForm').on('submit', function(e) {
    var isValid = true;
    $(this).find('[required]').each(function() {
      if (!$(this).val()) {
        isValid = false;
        $(this).css('border-color', '#dc2626');
      } else {
        $(this).css('border-color', '#e2e8f0');
      }
    });
    
    if (!isValid) {
      e.preventDefault();
      alert('Please fill all required fields!');
    }
  });

  // Smooth scroll to first highlighted field on page load
  var firstHighlight = $('.ocr-highlight').first();
  if (firstHighlight.length) {
    setTimeout(function() {
      $('html, body').animate({
        scrollTop: firstHighlight.offset().top - 150
      }, 800);
    }, 500);
  }
});

function initializeLocationFilters() {
    const countrySelect = document.getElementById('country');
    const stateSelect = document.getElementById('state');
    
    // Populate Countries
    if (Object.keys(locationData).length > 0) {
        const countries = Object.keys(locationData).sort();
        countries.forEach(country => {
            const option = document.createElement('option');
            option.value = country;
            option.textContent = country;
            if (country === preSelectedCountry) {
                option.selected = true;
            }
            countrySelect.appendChild(option);
        });
    }

    // Trigger state population if country is pre-selected
    if (preSelectedCountry) {
        populateStates(preSelectedCountry, preSelectedState);
    }
    
    // Country change event
    countrySelect.addEventListener('change', function() {
        const selectedCountry = this.value;
        populateStates(selectedCountry, '');
    });

    function populateStates(country, selectedState) {
        stateSelect.innerHTML = '<option value="">Select State</option>';
        
        if (country && locationData[country]) {
            let states = [];
            // Handle both Array and Object structures for states
            if (Array.isArray(locationData[country])) {
                 states = locationData[country].sort();
            } else {
                 states = Object.keys(locationData[country]).sort();
            }

            states.forEach(state => {
                const option = document.createElement('option');
                option.value = state;
                option.textContent = state;
                if (state === selectedState) {
                    option.selected = true;
                }
                stateSelect.appendChild(option);
            });
        }
    }
}
</script>

</body>
</html>