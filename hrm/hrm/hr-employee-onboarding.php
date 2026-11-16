<?php
// =========================================================================
// HR EMPLOYEE ONBOARDING FORM - External Employee Facing Page
// =========================================================================
// ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);
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
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

$con = conexion();
mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set('Asia/Kolkata');

// =========================================================================
// FILE SIZE CONFIGURATION
// =========================================================================
define('MAX_PHOTO_SIZE_MB', 2);
define('MAX_DOCUMENT_SIZE_MB', 5);
define('MAX_PHOTO_SIZE_BYTES', MAX_PHOTO_SIZE_MB * 1024 * 1024);
define('MAX_DOCUMENT_SIZE_BYTES', MAX_DOCUMENT_SIZE_MB * 1024 * 1024);

// =========================================================================
// CREATE PENDING TABLE IF NOT EXISTS
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_employee_onboarding_pending (
    id int(11) NOT NULL AUTO_INCREMENT,
    token varchar(100) NOT NULL,
    candidate_id int(11) DEFAULT NULL,
    candidate_name varchar(255) DEFAULT NULL,
    status enum('pending','approved','declined','resubmit') DEFAULT 'pending',
    decline_reason text DEFAULT NULL,
    allow_resubmit tinyint(1) DEFAULT 0,
    notify_employee tinyint(1) DEFAULT 0,
    submitted_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at timestamp NULL DEFAULT NULL,
    reviewed_by varchar(255) DEFAULT NULL,
    name varchar(255) DEFAULT NULL,
    gender varchar(20) DEFAULT NULL,
    dob date DEFAULT NULL,
    blood_group varchar(10) DEFAULT NULL,
    personal_email varchar(255) DEFAULT NULL,
    phone varchar(20) DEFAULT NULL,
    alt_phone varchar(20) DEFAULT NULL,
    address text DEFAULT NULL,
    country varchar(100) DEFAULT NULL,
    state varchar(100) DEFAULT NULL,
    aadhar_card varchar(20) DEFAULT NULL,
    pan_number varchar(20) DEFAULT NULL,
    contact_name varchar(255) DEFAULT NULL,
    relationship varchar(100) DEFAULT NULL,
    contact_phone varchar(20) DEFAULT NULL,
    contact_alt_phone varchar(20) DEFAULT NULL,
    university_degree varchar(255) DEFAULT NULL,
    year_completion varchar(10) DEFAULT NULL,
    percentage_cgpa varchar(20) DEFAULT NULL,
    bank_account_number varchar(50) DEFAULT NULL,
    ifsc_code varchar(20) DEFAULT NULL,
    bank_branch varchar(255) DEFAULT NULL,
    email varchar(255) DEFAULT NULL,
    hire_date date DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    position varchar(255) DEFAULT NULL,
    reporting_manager_1 varchar(50) DEFAULT NULL,
    reporting_manager_2 varchar(50) DEFAULT NULL,
    salary decimal(10,2) DEFAULT NULL,
    work_location varchar(255) DEFAULT NULL,
    timings varchar(255) DEFAULT NULL,
    company_name varchar(255) DEFAULT NULL,
    employee_type varchar(100) DEFAULT NULL,
    documents_json longtext DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY token (token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// =========================================================================
// CREATE ONBOARDING LINKS TABLE IF NOT EXISTS
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_onboarding_links (
    id int(11) NOT NULL AUTO_INCREMENT,
    candidate_id int(11) NOT NULL,
    token varchar(100) NOT NULL,
    candidate_name varchar(255) DEFAULT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    joining_date date DEFAULT NULL,
    status enum('pending','submitted','approved','declined') DEFAULT 'pending',
    expiry_at datetime DEFAULT NULL,
    created_by varchar(255) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY token (token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// =========================================================================
// VALIDATE TOKEN
// =========================================================================
$token = trim($_GET['token'] ?? '');
$page_error = '';
$page_success = false;
$already_submitted = false;
$link_data = null;
$candidate_info = null;
$pending_row = [];

if (empty($token)) {
    $page_error = 'Invalid or missing onboarding link. Please contact HR.';
} else {
    $safe_token = mysqli_real_escape_string($con, $token);
    $link_res = mysqli_query($con, "SELECT * FROM hr_onboarding_links WHERE token='$safe_token' LIMIT 1");
    
    if (!$link_res || mysqli_num_rows($link_res) == 0) {
        $page_error = 'This onboarding link is invalid or has been removed. Please contact HR.';
    } else {
        $link_data = mysqli_fetch_assoc($link_res);
        
        // Check expiry
        if (!empty($link_data['expiry_at']) && strtotime($link_data['expiry_at']) < time()) {
            $page_error = 'This onboarding link has expired. Please contact HR for a new link.';
        } else {
            // ALWAYS try to fetch the pending row to get saved data (especially for Resubmit)
            $pending_res = mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending WHERE token='$safe_token' LIMIT 1");
            if ($pending_res && mysqli_num_rows($pending_res) > 0) {
                $pending_row = mysqli_fetch_assoc($pending_res);
                if ($pending_row['status'] == 'resubmit') {
                    // Allow resubmission, data will be prefilled
                    $already_submitted = false;
                } elseif ($pending_row['status'] == 'declined') {
                    $page_error = 'Your onboarding application was declined. Reason: ' . htmlspecialchars($pending_row['decline_reason'] ?? 'No reason provided') . ' Please contact HR for assistance.';
                } else {
                    // 'pending' or 'approved' in hr_employee_onboarding_pending
                    $already_submitted = true;
                }
            } else {
                // If there's no pending row, they definitely haven't submitted yet
                if ($link_data['status'] == 'submitted' || $link_data['status'] == 'approved') {
                    $already_submitted = true; // Fallback if data is missing but link says submitted
                } else {
                    $already_submitted = false;
                }
            }
        }
        
        // Fetch candidate info from hr_screenings
        if ($link_data['candidate_id']) {
            $cid = intval($link_data['candidate_id']);
            $cand_res = mysqli_query($con, "SELECT * FROM hr_screenings WHERE id=$cid LIMIT 1");
            if ($cand_res) $candidate_info = mysqli_fetch_assoc($cand_res);
        }
    }
}

// =========================================================================
// FETCH MASTER DATA FOR DROPDOWNS
// =========================================================================
$dept_query   = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
$pos_query    = mysqli_query($con, "SELECT * FROM hr_positions ORDER BY title ASC");
$loc_query    = mysqli_query($con, "SELECT * FROM hr_work_locations ORDER BY location_name ASC");
$time_query   = mysqli_query($con, "SELECT * FROM hr_office_timings ORDER BY id ASC");
$company_query= mysqli_query($con, "SELECT * FROM hr_companies ORDER BY company_name ASC");
$emp_query    = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE status='Active' ORDER BY name ASC");

// Load location data
define('LOCATIONS_FILE', __DIR__ . '/global_locations.json');
$location_data = [];
if (file_exists(LOCATIONS_FILE)) {
    $location_data = json_decode(file_get_contents(LOCATIONS_FILE), true);
}

// =========================================================================
// HANDLE FORM SUBMISSION
// =========================================================================
$form_error = '';

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['submit_onboarding']) && $link_data && empty($page_error) && !$already_submitted) {
    
    $safe_token = mysqli_real_escape_string($con, $token);
    
    // Collect all fields
    $name               = mysqli_real_escape_string($con, trim($_POST['name'] ?? ''));
    $gender             = mysqli_real_escape_string($con, trim($_POST['gender'] ?? ''));
    $dob                = mysqli_real_escape_string($con, trim($_POST['dob'] ?? ''));
    $blood_group        = mysqli_real_escape_string($con, trim($_POST['blood_group'] ?? ''));
    $personal_email     = mysqli_real_escape_string($con, trim($_POST['personal_email'] ?? ''));
    $phone              = mysqli_real_escape_string($con, trim($_POST['phone'] ?? ''));
    $alt_phone          = mysqli_real_escape_string($con, trim($_POST['alt_phone'] ?? ''));
    $address            = mysqli_real_escape_string($con, trim($_POST['address'] ?? ''));
    $country            = mysqli_real_escape_string($con, trim($_POST['country'] ?? ''));
    $state              = mysqli_real_escape_string($con, trim($_POST['state'] ?? ''));
    $aadhar_card        = mysqli_real_escape_string($con, trim($_POST['aadhar_card'] ?? ''));
    $pan_number         = strtoupper(mysqli_real_escape_string($con, trim($_POST['pan_number'] ?? '')));
    $contact_name       = mysqli_real_escape_string($con, trim($_POST['contact_name'] ?? ''));
    $relationship       = mysqli_real_escape_string($con, trim($_POST['relationship'] ?? ''));
    $contact_phone      = mysqli_real_escape_string($con, trim($_POST['contact_phone'] ?? ''));
    $contact_alt_phone  = mysqli_real_escape_string($con, trim($_POST['contact_alt_phone'] ?? ''));
    $university_degree  = mysqli_real_escape_string($con, trim($_POST['university_degree'] ?? ''));
    $year_completion    = mysqli_real_escape_string($con, trim($_POST['year_completion'] ?? ''));
    $percentage_cgpa    = mysqli_real_escape_string($con, trim($_POST['percentage_cgpa'] ?? ''));
    $bank_account_number= mysqli_real_escape_string($con, trim($_POST['bank_account_number'] ?? ''));
    $ifsc_code          = strtoupper(mysqli_real_escape_string($con, trim($_POST['ifsc_code'] ?? '')));
    $bank_branch        = mysqli_real_escape_string($con, trim($_POST['bank_branch'] ?? ''));
    $email              = mysqli_real_escape_string($con, trim($_POST['email'] ?? ''));
    $hire_date          = mysqli_real_escape_string($con, trim($_POST['hire_date'] ?? ''));
    $department         = mysqli_real_escape_string($con, trim($_POST['department'] ?? ''));
    $position           = mysqli_real_escape_string($con, trim($_POST['position'] ?? ''));
    $salary             = mysqli_real_escape_string($con, trim($_POST['salary'] ?? '0'));
    $work_location      = mysqli_real_escape_string($con, trim($_POST['work_location'] ?? ''));
    $company_name       = mysqli_real_escape_string($con, trim($_POST['company_name'] ?? ''));
    $employee_type      = mysqli_real_escape_string($con, trim($_POST['employee_type'] ?? ''));
    $reporting_manager_1= mysqli_real_escape_string($con, trim($_POST['reporting_manager_1'] ?? ''));
    $reporting_manager_2= mysqli_real_escape_string($con, trim($_POST['reporting_manager_2'] ?? ''));
    
    $timings = mysqli_real_escape_string($con, trim($_POST['timings_select'] ?? ''));
    if ($timings == 'Manual') {
        $timings = mysqli_real_escape_string($con, trim($_POST['timings_manual'] ?? ''));
    }
    
    // Handle document uploads
    $uploaded_docs = [];
    
    // Retain existing documents that were not removed
    if (isset($_POST['existing_documents']) && is_array($_POST['existing_documents'])) {
        foreach ($_POST['existing_documents'] as $ex_json) {
            $ex_doc = json_decode($ex_json, true);
            if ($ex_doc && isset($ex_doc['type']) && isset($ex_doc['filepath'])) {
                $uploaded_docs[] = $ex_doc;
            }
        }
    }
    
    if (isset($_FILES['document_file']) && is_array($_FILES['document_file']['name'])) {
        $upload_dir = 'uploads/onboarding_documents/' . $safe_token . '/';
        $upload_dir_abs = __DIR__ . '/' . $upload_dir;
        if (!is_dir($upload_dir_abs)) mkdir($upload_dir_abs, 0777, true);
        
        $document_types  = $_POST['document_type'] ?? [];
        $custom_names    = $_POST['document_custom_name'] ?? [];
        
        foreach ($_FILES['document_file']['name'] as $key => $filename) {
            if ($_FILES['document_file']['error'][$key] === UPLOAD_ERR_OK && !empty($filename)) {
                $file_size = $_FILES['document_file']['size'][$key];
                $file_ext  = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
                $image_exts = ['jpg','jpeg','png','gif','webp'];
                $max_size   = in_array($file_ext, $image_exts) ? MAX_PHOTO_SIZE_BYTES : MAX_DOCUMENT_SIZE_BYTES;
                
                if ($file_size > $max_size) continue;
                
                $doc_type = $document_types[$key] ?? '';
                if ($doc_type === 'Other' && !empty($custom_names[$key])) {
                    $doc_type = $custom_names[$key];
                }
                if (empty($doc_type)) continue;
                
                $new_filename = 'onboard_' . preg_replace('/[^a-zA-Z0-9]/', '_', $doc_type) . '_' . time() . '.' . $file_ext;
                $target_path  = $upload_dir_abs . $new_filename;
                $rel_path     = $upload_dir . $new_filename;
                
                if (move_uploaded_file($_FILES['document_file']['tmp_name'][$key], $target_path)) {
                    $uploaded_docs[] = [
                        'type'     => $doc_type,
                        'filename' => $new_filename,
                        'filepath' => $rel_path
                    ];
                }
            }
        }
    }
    
    $docs_json = mysqli_real_escape_string($con, json_encode($uploaded_docs));
    $candidate_id_val = $link_data['candidate_id'] ? intval($link_data['candidate_id']) : 'NULL';
    $candidate_name_val = mysqli_real_escape_string($con, $link_data['candidate_name'] ?? $name);
    
    $dob_sql = $dob ? "'$dob'" : "NULL";
    $hire_date_sql = $hire_date ? "'$hire_date'" : "NULL";
    $salary_sql = ($salary === '' || $salary === null) ? "NULL" : "'$salary'";
    
    // Check if already exists (resubmit scenario)
    $existing = mysqli_query($con, "SELECT id FROM hr_employee_onboarding_pending WHERE token='$safe_token' LIMIT 1");
    
    if ($existing && mysqli_num_rows($existing) > 0) {
        // Update existing record
        $update_sql = "UPDATE hr_employee_onboarding_pending SET
            status='pending', decline_reason=NULL, allow_resubmit=0,
            name='$name', gender='$gender', dob=$dob_sql, blood_group='$blood_group',
            personal_email='$personal_email', phone='$phone', alt_phone='$alt_phone',
            address='$address', country='$country', state='$state',
            aadhar_card='$aadhar_card', pan_number='$pan_number',
            contact_name='$contact_name', relationship='$relationship',
            contact_phone='$contact_phone', contact_alt_phone='$contact_alt_phone',
            university_degree='$university_degree', year_completion='$year_completion',
            percentage_cgpa='$percentage_cgpa', bank_account_number='$bank_account_number',
            ifsc_code='$ifsc_code', bank_branch='$bank_branch',
            email='$email', hire_date=$hire_date_sql, department='$department',
            position='$position', reporting_manager_1='$reporting_manager_1',
            reporting_manager_2='$reporting_manager_2', salary=$salary_sql,
            work_location='$work_location', timings='$timings',
            company_name='$company_name', employee_type='$employee_type',
            documents_json='$docs_json', submitted_at=NOW()
            WHERE token='$safe_token'";
        mysqli_query($con, $update_sql) or die(mysqli_error($con));
    } else {
        // Insert new record
        $insert_sql = "INSERT INTO hr_employee_onboarding_pending (
            token, candidate_id, candidate_name, status,
            name, gender, dob, blood_group, personal_email, phone, alt_phone,
            address, country, state, aadhar_card, pan_number,
            contact_name, relationship, contact_phone, contact_alt_phone,
            university_degree, year_completion, percentage_cgpa,
            bank_account_number, ifsc_code, bank_branch,
            email, hire_date, department, position,
            reporting_manager_1, reporting_manager_2, salary,
            work_location, timings, company_name, employee_type, documents_json
        ) VALUES (
            '$safe_token', $candidate_id_val, '$candidate_name_val', 'pending',
            '$name', '$gender', $dob_sql, '$blood_group', '$personal_email', '$phone', '$alt_phone',
            '$address', '$country', '$state', '$aadhar_card', '$pan_number',
            '$contact_name', '$relationship', '$contact_phone', '$contact_alt_phone',
            '$university_degree', '$year_completion', '$percentage_cgpa',
            '$bank_account_number', '$ifsc_code', '$bank_branch',
            '$email', $hire_date_sql, '$department', '$position',
            '$reporting_manager_1', '$reporting_manager_2', $salary_sql,
            '$work_location', '$timings', '$company_name', '$employee_type', '$docs_json'
        )";
        mysqli_query($con, $insert_sql) or die(mysqli_error($con));
    }
    
    // Update the link status
    mysqli_query($con, "UPDATE hr_onboarding_links SET status='submitted' WHERE token='$safe_token'");
    
    $page_success = true;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Employee Onboarding Form</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet"/>
  <link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet"/>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; }

    .onboard-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 30px;
      text-align: center;
      color: white;
      box-shadow: 0 4px 20px rgba(30,58,138,0.3);
    }
    .onboard-header h1 { font-size: 1.8rem; font-weight: 700; margin-bottom: 5px; }
    .onboard-header p  { opacity: 0.85; font-size: 0.95rem; margin: 0; }

    .welcome-banner {
      background: linear-gradient(135deg, #ecfdf5, #d1fae5);
      border-left: 5px solid #10b981;
      padding: 20px 25px;
      border-radius: 10px;
      margin-bottom: 25px;
    }
    .welcome-banner h4 { color: #065f46; font-weight: 700; margin-bottom: 5px; }
    .welcome-banner p  { color: #047857; margin: 0; font-size: 0.9rem; }

    .form-container {
      background: white;
      padding: 30px;
      border-radius: 12px;
      box-shadow: 0 2px 12px rgba(0,0,0,0.08);
      margin-bottom: 25px;
    }

    .section-title {
      color: #1e3a8a;
      font-weight: 700;
      font-size: 1.1rem;
      margin-top: 30px;
      margin-bottom: 20px;
      padding-bottom: 10px;
      border-bottom: 3px solid #1e3a8a;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .section-title:first-child { margin-top: 0; }

    .form-group label {
      font-weight: 600;
      color: #334155;
      margin-bottom: 8px;
      font-size: 0.95rem;
      display: block;
    }
    .required { color: #dc2626; font-weight: 700; }

    .form-control {
      border: 2px solid #e2e8f0;
      border-radius: 8px;
      padding: 14px 16px;
      font-size: 1rem;
      height: 52px;
      transition: all 0.3s;
      font-family: 'Poppins', sans-serif;
      font-weight: 500;
      color: #1e293b;
      width: 100%;
    }
    textarea.form-control { height: auto; min-height: 100px; }
    .form-control:focus {
      border-color: #1e3a8a;
      box-shadow: 0 0 0 3px rgba(30,58,138,0.1);
      outline: none;
    }
    select.form-control {
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%231e3a8a' d='M6 9L1 4h10z'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 16px center;
      padding-right: 40px;
    }

    .btn-submit {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      border: none;
      padding: 16px 40px;
      border-radius: 10px;
      color: white;
      font-weight: 700;
      font-size: 1.1rem;
      width: 100%;
      margin-top: 25px;
      cursor: pointer;
      transition: all 0.3s;
      box-shadow: 0 4px 15px rgba(30,58,138,0.3);
      font-family: 'Poppins', sans-serif;
    }
    .btn-submit:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(30,58,138,0.4);
    }

    /* Error / Success pages */
    .error-page, .success-page, .submitted-page {
      max-width: 600px;
      margin: 80px auto;
      text-align: center;
      padding: 40px;
      background: white;
      border-radius: 16px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }
    .error-page .icon   { font-size: 60px; color: #ef4444; margin-bottom: 20px; }
    .success-page .icon { font-size: 60px; color: #10b981; margin-bottom: 20px; }
    .submitted-page .icon { font-size: 60px; color: #f59e0b; margin-bottom: 20px; }

    /* Document upload */
    .document-row {
      background: #f8fafc;
      padding: 15px;
      border-radius: 8px;
      margin-bottom: 12px;
      border: 2px dashed #e2e8f0;
    }

    /* Progress steps */
    .progress-steps {
      display: flex;
      justify-content: center;
      gap: 0;
      margin-bottom: 30px;
      flex-wrap: wrap;
    }
    .step {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 18px;
      background: #f1f5f9;
      color: #64748b;
      font-weight: 600;
      font-size: 13px;
      border-radius: 0;
      position: relative;
    }
    .step:first-child { border-radius: 8px 0 0 8px; }
    .step:last-child  { border-radius: 0 8px 8px 0; }
    .step.active { background: #1e3a8a; color: white; }
    .step .step-num {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255,255,255,0.3);
      display: flex; align-items: center; justify-content: center;
      font-size: 12px; font-weight: 800;
    }

    .info-box {
      background: #eff6ff;
      border: 1px solid #bfdbfe;
      border-radius: 8px;
      padding: 14px 18px;
      margin-bottom: 20px;
      font-size: 13px;
      color: #1e40af;
      font-weight: 500;
    }

    .wrap { max-width: 1000px; margin: 0 auto; padding: 30px 20px; }
  </style>
</head>
<body>

<!-- Header -->
<div class="onboard-header" style="position:relative;">
  <?php 
      $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek']);
      $dashboard_url = $is_admin ? '../index.php' : '../raise-a-ticket.php';
  ?>
  
  <i class="fas fa-id-badge" style="font-size:2rem; margin-bottom:10px; display:block;"></i>
  <h1>Employee Joining Form</h1>
  <p>Welcome! Please complete your onboarding details below.</p>
</div>

<?php if (!empty($page_error)): ?>
<!-- Error State -->
<div class="error-page">
  <div class="icon"><i class="fas fa-exclamation-circle"></i></div>
  <h3 style="color:#1e293b; font-weight:700; margin-bottom:10px;">Access Denied</h3>
  <p style="color:#64748b; margin-bottom:20px;"><?php echo $page_error; ?></p>
  <p style="font-size:13px; color:#94a3b8;">If you believe this is an error, please contact your HR department.</p>
</div>

<?php elseif ($page_success): ?>
<!-- Success State -->
<div class="success-page">
  <div class="icon"><i class="fas fa-check-circle"></i></div>
  <h3 style="color:#1e293b; font-weight:700; margin-bottom:10px;">Form Submitted Successfully!</h3>
  <p style="color:#64748b; margin-bottom:20px;">
    Thank you, <strong><?php echo htmlspecialchars($_POST['name'] ?? 'Employee'); ?></strong>!
    Your joining details have been submitted and are pending HR approval.
  </p>
  <div style="background:#f0fdf4; border:1px solid #86efac; border-radius:10px; padding:20px; text-align:left; margin-bottom:20px;">
    <p style="font-weight:700; color:#065f46; margin-bottom:8px;"><i class="fas fa-info-circle"></i> What happens next?</p>
    <ul style="color:#047857; font-size:13px; margin:0; padding-left:18px;">
      <li>HR will review your submitted details</li>
      <li>You will be notified once your profile is approved</li>
      <li>If any corrections are needed, HR will reach out to you</li>
      <li>Once approved, your employee profile will be activated</li>
    </ul>
  </div>
  <p style="font-size:13px; color:#94a3b8;">You can close this page now.</p>
</div>

<?php elseif ($already_submitted): ?>
<!-- Already Submitted State -->
<div class="submitted-page">
  <div class="icon"><i class="fas fa-clock"></i></div>
  <h3 style="color:#1e293b; font-weight:700; margin-bottom:10px;">Already Submitted</h3>
  <p style="color:#64748b; margin-bottom:20px;">
    Your onboarding form has already been submitted and is currently <strong>pending HR review</strong>.
  </p>
  <p style="font-size:13px; color:#94a3b8;">Please wait for HR to review your details. You will be contacted if any changes are needed.</p>
</div>

<?php else: ?>
<!-- The Onboarding Form -->
<div class="wrap">

  <?php if ($candidate_info): ?>
  <div class="welcome-banner">
    <h4><i class="fas fa-hand-wave"></i> Welcome, <?php echo htmlspecialchars($link_data['candidate_name'] ?? $candidate_info['candidate_name']); ?>!</h4>
    <p>
      You have been selected for the position of <strong><?php echo htmlspecialchars($candidate_info['position_applied']); ?></strong>
      in the <strong><?php echo htmlspecialchars($candidate_info['department']); ?></strong> department.
      <?php if ($link_data['joining_date']): ?>
        Your joining date is <strong><?php echo date('d M Y', strtotime($link_data['joining_date'])); ?></strong>.
      <?php endif; ?>
    </p>
  </div>
  <?php endif; ?>

  <div class="info-box">
    <i class="fas fa-info-circle"></i>
    <strong>Instructions:</strong> Please fill all required fields marked with <span style="color:#dc2626;">*</span>.
    Ensure all information is accurate as it will be used for your official employment records.
    Upload supporting documents wherever applicable.
  </div>

  
  <?php
  $pending_row = $pending_row ?? [];
  $candidate_info = $candidate_info ?? [];
  $link_data = $link_data ?? [];

  $d_email = $pending_row['email'] ?? $candidate_info['candidate_email'] ?? '';
  $d_hire_date = $pending_row['hire_date'] ?? $link_data['joining_date'] ?? '';
  $d_department = $pending_row['department'] ?? $candidate_info['department'] ?? '';
  $d_position = $pending_row['position'] ?? $candidate_info['position_applied'] ?? '';
  $d_employee_type = $pending_row['employee_type'] ?? '';
  $d_reporting_manager_1 = $pending_row['reporting_manager_1'] ?? '';
  $d_reporting_manager_2 = $pending_row['reporting_manager_2'] ?? '';
  $d_salary = $pending_row['salary'] ?? '';
  $d_work_location = $pending_row['work_location'] ?? '';
  $d_company_name = $pending_row['company_name'] ?? '';
  $d_timings = $pending_row['timings'] ?? '';
  $d_name = $pending_row['name'] ?? $link_data['candidate_name'] ?? $candidate_info['candidate_name'] ?? '';
  $d_gender = $pending_row['gender'] ?? '';
  $d_dob = $pending_row['dob'] ?? '';
  $d_blood_group = $pending_row['blood_group'] ?? '';
  $d_personal_email = $pending_row['personal_email'] ?? '';
  $d_phone = $pending_row['phone'] ?? $candidate_info['candidate_phone'] ?? '';
  $d_alt_phone = $pending_row['alt_phone'] ?? '';
  $d_address = $pending_row['address'] ?? '';
  $d_country = $pending_row['country'] ?? '';
  $d_state = $pending_row['state'] ?? '';
  $d_aadhar_card = $pending_row['aadhar_card'] ?? '';
  $d_pan_number = $pending_row['pan_number'] ?? '';
  $d_contact_name = $pending_row['contact_name'] ?? '';
  $d_relationship = $pending_row['relationship'] ?? '';
  $d_contact_phone = $pending_row['contact_phone'] ?? '';
  $d_contact_alt_phone = $pending_row['contact_alt_phone'] ?? '';
  $d_university_degree = $pending_row['university_degree'] ?? '';
  $d_year_completion = $pending_row['year_completion'] ?? '';
  $d_percentage_cgpa = $pending_row['percentage_cgpa'] ?? '';
  $d_bank_account_number = $pending_row['bank_account_number'] ?? '';
  $d_ifsc_code = $pending_row['ifsc_code'] ?? '';
  $d_bank_branch = $pending_row['bank_branch'] ?? '';
  $d_documents_json = $pending_row['documents_json'] ?? '[]';
  $d_documents = json_decode($d_documents_json, true) ?: [];

  // Pull DV documents using candidate_id from hr_onboarding_links
  $dv_docs = [];
  if (!empty($link_data['candidate_id'])) {
      $cid_dv = intval($link_data['candidate_id']);
      $dv_req_row = mysqli_fetch_assoc(mysqli_query($con,
          "SELECT id FROM hr_dv_requests WHERE candidate_id=$cid_dv ORDER BY id DESC LIMIT 1"));
      if ($dv_req_row) {
          $dv_res = mysqli_query($con,
              "SELECT * FROM hr_dv_documents
               WHERE request_id={$dv_req_row['id']}
               AND file_path IS NOT NULL AND file_path != ''
               ORDER BY id ASC");
          while ($dv_row = mysqli_fetch_assoc($dv_res)) {
              $dv_docs[] = [
                  'type'     => $dv_row['document_name'],
                  'filename' => $dv_row['file_name'],
                  'filepath' => $dv_row['file_path']
              ];
          }
      }
  }
  // Merge: existing onboarding docs take priority, DV docs fill the rest
  $merged_types = array_column($d_documents, 'type');
  foreach ($dv_docs as $dv_doc) {
      if (!in_array($dv_doc['type'], $merged_types)) {
          $d_documents[] = $dv_doc;
      }
  }

  // Add the signed offer letter as a display-only reference (not saved into documents_json)
  if (!empty($link_data['candidate_id'])) {
      $cid_offer = intval($link_data['candidate_id']);
      $offer_row = mysqli_fetch_assoc(mysqli_query($con,
          "SELECT token FROM hr_offer_letters WHERE candidate_id=$cid_offer AND status='accepted' ORDER BY id DESC LIMIT 1"));
      if ($offer_row && !empty($offer_row['token'])) {
          $offer_base_url   = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
          $offer_script_dir = '/hrm';
          $d_documents[] = [
              'type'         => 'Signed Offer Letter',
              'filename'     => 'offer_letter.pdf',
              'filepath'     => $offer_base_url . $offer_script_dir . '/hr-employee-offer.php?token=' . $offer_row['token'] . '&download=1',
              'display_only' => true
          ];
      }
  }
  ?>
  <form method="POST" enctype="multipart/form-data" id="onboardingForm">

    <div class="form-container">

      <!-- Official Info as Hidden Fields (HR fills during approval) -->
      <input type="hidden" name="email" value="<?php echo htmlspecialchars($d_email); ?>">
      <input type="hidden" name="hire_date" value="<?php echo htmlspecialchars($d_hire_date); ?>">
      <input type="hidden" name="department" value="<?php echo htmlspecialchars($d_department); ?>">
      <input type="hidden" name="position" value="<?php echo htmlspecialchars($d_position); ?>">
      <input type="hidden" name="employee_type" value="<?php echo htmlspecialchars($d_employee_type); ?>">
      <input type="hidden" name="reporting_manager_1" value="<?php echo htmlspecialchars($d_reporting_manager_1); ?>">
      <input type="hidden" name="reporting_manager_2" value="<?php echo htmlspecialchars($d_reporting_manager_2); ?>">
      <input type="hidden" name="salary" value="<?php echo htmlspecialchars($d_salary); ?>">
      <input type="hidden" name="work_location" value="<?php echo htmlspecialchars($d_work_location); ?>">
      <input type="hidden" name="company_name" value="<?php echo htmlspecialchars($d_company_name); ?>">
      <input type="hidden" name="timings_select" value="<?php echo htmlspecialchars($d_timings); ?>">

      <!-- Personal Information -->
      <div class="section-title"><i class="fas fa-user"></i> Personal Information</div>
      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Full Name <span class="required">*</span></label>
            <input type="text" name="name" class="form-control"
                   value="<?php echo htmlspecialchars($d_name); ?>"
                   placeholder="Enter full name" required>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Gender <span class="required">*</span></label>
            <select name="gender" class="form-control" required>
              <option value="">Select</option>
              <option value="Male" <?php echo ($d_gender=='Male')?'selected':''; ?>>Male</option>
              <option value="Female" <?php echo ($d_gender=='Female')?'selected':''; ?>>Female</option>
              <option value="Other" <?php echo ($d_gender=='Other')?'selected':''; ?>>Other</option>
            </select>
          </div>
        </div>
        <div class="col-md-3">
          <div class="form-group">
            <label>Date of Birth <span class="required">*</span></label>
            <input type="date" name="dob" class="form-control" value="<?php echo htmlspecialchars($d_dob); ?>" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Blood Group <span class="required">*</span></label>
            <select name="blood_group" class="form-control" required>
              <option value="">Select</option>
              <?php foreach (['A+','A-','B+','B-','O+','O-','AB+','AB-'] as $bg): ?>
              <option value="<?php echo $bg; ?>" <?php echo ($d_blood_group==$bg)?'selected':''; ?>><?php echo $bg; ?></option>
              <?php endforeach; ?>
            </select>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Mobile Number <span class="required">*</span></label>
            <input type="text" name="phone" class="form-control"
                   value="<?php echo htmlspecialchars($d_phone); ?>"
                   placeholder="10 digit mobile" pattern="[0-9]{10}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="alt_phone" class="form-control" value="<?php echo htmlspecialchars($d_alt_phone); ?>" placeholder="Alternate contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Personal Email</label>
            <input type="email" name="personal_email" class="form-control" value="<?php echo htmlspecialchars($d_personal_email); ?>" placeholder="personal@email.com">
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
            <textarea name="address" class="form-control" rows="3" placeholder="Full address with pincode" required><?php echo htmlspecialchars($d_address); ?></textarea>
          </div>
        </div>
      </div>

      <!-- Identity Documents -->
      <div class="section-title"><i class="fas fa-id-card"></i> Identity Documents</div>
      <div class="row">
        <div class="col-md-6">
          <div class="form-group">
            <label>Aadhar Card Number <span class="required">*</span></label>
            <input type="text" name="aadhar_card" class="form-control" value="<?php echo htmlspecialchars($d_aadhar_card); ?>" placeholder="12 digit Aadhar" pattern="[0-9]{12}" required>
          </div>
        </div>
        <div class="col-md-6">
          <div class="form-group">
            <label>PAN Number <span class="required">*</span></label>
            <input type="text" name="pan_number" class="form-control" value="<?php echo htmlspecialchars($d_pan_number); ?>" style="text-transform:uppercase;" placeholder="e.g. ABCDE1234F" pattern="[A-Z]{5}[0-9]{4}[A-Z]{1}" required>
          </div>
        </div>
      </div>

      <!-- Emergency Contact -->
      <div class="section-title"><i class="fas fa-phone-square"></i> Emergency Contact</div>
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Contact Name <span class="required">*</span></label>
            <input type="text" name="contact_name" class="form-control" value="<?php echo htmlspecialchars($d_contact_name); ?>" placeholder="Emergency contact name" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Relationship <span class="required">*</span></label>
            <input type="text" name="relationship" class="form-control" value="<?php echo htmlspecialchars($d_relationship); ?>" placeholder="Father, Spouse, etc." required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Phone Number <span class="required">*</span></label>
            <input type="text" name="contact_phone" class="form-control" value="<?php echo htmlspecialchars($d_contact_phone); ?>" placeholder="Emergency contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>
      <div class="row">
        <div class="col-md-12">
          <div class="form-group">
            <label>Alternate Phone <span class="required">*</span></label>
            <input type="text" name="contact_alt_phone" class="form-control" value="<?php echo htmlspecialchars($d_contact_alt_phone); ?>" placeholder="Alternate emergency contact" pattern="[0-9]{10}" required>
          </div>
        </div>
      </div>

      <!-- Education -->
      <div class="section-title"><i class="fas fa-graduation-cap"></i> Education</div>
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Degree / University <span class="required">*</span></label>
            <input type="text" name="university_degree" class="form-control" value="<?php echo htmlspecialchars($d_university_degree); ?>" placeholder="e.g. B.Tech, MBA" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Year of Completion <span class="required">*</span></label>
            <input type="text" name="year_completion" class="form-control" value="<?php echo htmlspecialchars($d_year_completion); ?>" placeholder="e.g. 2023" pattern="[0-9]{4}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Percentage / CGPA <span class="required">*</span></label>
            <input type="text" name="percentage_cgpa" class="form-control" value="<?php echo htmlspecialchars($d_percentage_cgpa); ?>" placeholder="e.g. 7.8 or 75%" required>
          </div>
        </div>
      </div>

      <!-- Bank Details -->
      <div class="section-title"><i class="fas fa-university"></i> Bank Details</div>
      <div class="row">
        <div class="col-md-4">
          <div class="form-group">
            <label>Bank Account Number <span class="required">*</span></label>
            <input type="text" name="bank_account_number" class="form-control"
                   placeholder="Account number" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>IFSC Code <span class="required">*</span></label>
            <input type="text" name="ifsc_code" class="form-control"
                   style="text-transform:uppercase;" placeholder="e.g. SBIN0001234"
                   pattern="[A-Z]{4}0[A-Z0-9]{6}" required>
          </div>
        </div>
        <div class="col-md-4">
          <div class="form-group">
            <label>Bank Branch <span class="required">*</span></label>
            <input type="text" name="bank_branch" class="form-control"
                   placeholder="Branch name" required>
          </div>
        </div>
      </div>

      <!-- Document Upload -->
      <div class="section-title"><i class="fas fa-file-upload"></i> Upload Documents</div>
      <div class="info-box">
        <strong>Upload Documents:</strong> Aadhar, PAN, Resume, Degree Certificate, etc. |
        <strong>Formats:</strong> PDF, JPG, PNG, DOC, DOCX |
        <strong>Size Limits:</strong> Photos: <?php echo MAX_PHOTO_SIZE_MB; ?>MB | Documents: <?php echo MAX_DOCUMENT_SIZE_MB; ?>MB
      </div>

      <div id="documentUploadContainer">

        <?php if (!empty($d_documents)): ?>
          <div style="margin-bottom:20px; padding:15px; background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px;">
            <div style="font-weight:700; color:#0f2557; margin-bottom:12px; font-size:14px;">
              <i class="fas fa-check-circle text-success mr-1"></i> Previously Uploaded Documents
            </div>
            <p style="font-size:12px; color:#64748b; margin-bottom:15px;">These documents are already saved. If you wish to replace one, simply click "Remove" and upload a new one below.</p>
            <div class="existing-documents-list" style="display:flex; flex-direction:column; gap:10px;">
              <?php foreach ($d_documents as $doc): ?>
                <?php if (!empty($doc['display_only'])): ?>
                <div class="existing-document-row" style="background:#fff; border:1px solid #cbd5e1; border-radius:8px; padding:12px 15px; display:flex; align-items:center; justify-content:space-between; box-shadow:0 1px 3px rgba(0,0,0,0.05);">
                  <div style="display:flex; align-items:center; gap:12px;">
                    <div style="width:36px; height:36px; border-radius:8px; background:#dbeafe; color:#1e40af; display:flex; align-items:center; justify-content:center; font-size:16px;">
                      <i class="fas fa-file-signature"></i>
                    </div>
                    <div>
                      <strong style="color:#0f2557; font-size:13px; display:block;"><?php echo htmlspecialchars($doc['type']); ?></strong>
                      <div style="font-size:11.5px; color:#64748b; margin-top:2px;">Signed &amp; accepted by candidate</div>
                    </div>
                  </div>
                  <a href="<?php echo htmlspecialchars($doc['filepath']); ?>" target="_blank" class="btn btn-sm btn-outline-primary" style="border-radius:6px; font-size:12px; font-weight:600; padding:4px 10px;">
                    <i class="fa fa-eye"></i> View / Download
                  </a>
                </div>
                <?php else: ?>
                <div class="existing-document-row" style="background:#fff; border:1px solid #cbd5e1; border-radius:8px; padding:12px 15px; display:flex; align-items:center; justify-content:space-between; box-shadow:0 1px 3px rgba(0,0,0,0.05);">
                  <div style="display:flex; align-items:center; gap:12px;">
                    <div style="width:36px; height:36px; border-radius:8px; background:#e0e7ff; color:#4f46e5; display:flex; align-items:center; justify-content:center; font-size:16px;">
                      <i class="fas fa-file-alt"></i>
                    </div>
                    <div>
                      <strong style="color:#0f2557; font-size:13px; display:block;"><?php echo htmlspecialchars($doc['type']); ?></strong>
                      <div style="font-size:11.5px; color:#64748b; margin-top:2px;">Saved File: <?php echo htmlspecialchars($doc['filename']); ?></div>
                    </div>
                  </div>
                  <input type="hidden" name="existing_documents[]" value="<?php echo htmlspecialchars(json_encode($doc)); ?>">
                  <button type="button" class="btn btn-sm btn-outline-danger btn-remove-existing-doc" style="border-radius:6px; font-size:12px; font-weight:600; padding:4px 10px;">
                    <i class="fa fa-trash"></i> Remove
                  </button>
                </div>
                <?php endif; ?>
              <?php endforeach; ?>
            </div>
          </div>
        <?php endif; ?>

        <div class="document-row">
          <div class="row">
            <div class="col-md-4">
              <div class="form-group mb-0">
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
                  <option value="Other">Other (Custom Name)</option>
                </select>
              </div>
            </div>
            <div class="col-md-3">
              <div class="form-group mb-0">
                <label>Custom Name (if Other)</label>
                <input type="text" name="document_custom_name[]" class="form-control document-custom-name"
                       placeholder="Document name" style="display:none;">
              </div>
            </div>
            <div class="col-md-4">
              <div class="form-group mb-0">
                <label>Choose File</label>
                <input type="file" name="document_file[]" class="form-control-file doc-file-input"
                       accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
                       style="padding:10px; border:2px solid #e2e8f0; border-radius:8px; width:100%;">
              </div>
            </div>
            <div class="col-md-1 d-flex align-items-end">
              <button type="button" class="btn btn-danger btn-sm btn-remove-doc" style="display:none; margin-bottom:1px;">
                <i class="fa fa-trash"></i>
              </button>
            </div>
          </div>
        </div>
      </div>

      <button type="button" class="btn btn-success mb-3" id="btnAddDoc">
        <i class="fa fa-plus"></i> Add Another Document
      </button>

      <button type="submit" name="submit_onboarding" class="btn-submit">
        <i class="fas fa-paper-plane"></i> Submit Joining Form
      </button>

    </div>
  </form>
</div>
<?php endif; ?>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>

<script>
var PREFILL_COUNTRY = "<?php echo addslashes($d_country); ?>";
var PREFILL_STATE = "<?php echo addslashes($d_state); ?>";

var locationData = <?php echo json_encode($location_data); ?>;
var MAX_PHOTO_SIZE    = <?php echo MAX_PHOTO_SIZE_BYTES; ?>;
var MAX_DOCUMENT_SIZE = <?php echo MAX_DOCUMENT_SIZE_BYTES; ?>;
var MAX_PHOTO_SIZE_MB    = <?php echo MAX_PHOTO_SIZE_MB; ?>;
var MAX_DOCUMENT_SIZE_MB = <?php echo MAX_DOCUMENT_SIZE_MB; ?>;

$(document).ready(function() {

  // Select2 for managers
  $('.select2-manager').select2({ placeholder: 'Select Manager', allowClear: true, width: '100%' });

  // Populate countries
  var countrySelect = document.getElementById('country');
  var stateSelect   = document.getElementById('state');
  if (countrySelect && Object.keys(locationData).length > 0) {
    Object.keys(locationData).sort().forEach(function(c) {
      var o = document.createElement('option');
      o.value = c; o.textContent = c;
      countrySelect.appendChild(o);
    });
  }

  if (countrySelect) {
    countrySelect.addEventListener('change', function() {
      var sel = this.value;
      stateSelect.innerHTML = '<option value="">Select State</option>';
      if (sel && locationData[sel]) {
        var states = Array.isArray(locationData[sel]) ? locationData[sel] : Object.keys(locationData[sel]);
        states.sort().forEach(function(s) {
          var o = document.createElement('option');
          o.value = s; o.textContent = s;
          stateSelect.appendChild(o);
        });
      }
    });
  }

  // Pre-fill country and state if variables exist
  if (PREFILL_COUNTRY) {
    $('#country').val(PREFILL_COUNTRY).trigger('change');
    if (PREFILL_STATE) {
      setTimeout(function() {
        $('#state').val(PREFILL_STATE);
      }, 50);
    }
  }



  // Document type custom name toggle
  $(document).on('change', '.document-type-select', function() {
    var $custom = $(this).closest('.document-row').find('.document-custom-name');
    if ($(this).val() === 'Other') {
      $custom.show().prop('required', true);
    } else {
      $custom.hide().prop('required', false).val('');
    }
  });

  // File size validation
  $(document).on('change', '.doc-file-input', function() {
    if (this.files && this.files[0]) {
      var file    = this.files[0];
      var ext     = file.name.split('.').pop().toLowerCase();
      var imgExts = ['jpg','jpeg','png','gif','webp'];
      var maxSize = imgExts.includes(ext) ? MAX_PHOTO_SIZE : MAX_DOCUMENT_SIZE;
      var maxMB   = imgExts.includes(ext) ? MAX_PHOTO_SIZE_MB : MAX_DOCUMENT_SIZE_MB;
      if (file.size > maxSize) {
        alert('File too large! Max allowed: ' + maxMB + ' MB. Please compress and try again.');
        $(this).val('');
      }
    }
  });

  // Add document row
  $('#btnAddDoc').on('click', function() {
    var newRow = `
      <div class="document-row">
        <div class="row">
          <div class="col-md-4">
            <div class="form-group mb-0">
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
                <option value="Other">Other (Custom Name)</option>
              </select>
            </div>
          </div>
          <div class="col-md-3">
            <div class="form-group mb-0">
              <label>Custom Name (if Other)</label>
              <input type="text" name="document_custom_name[]" class="form-control document-custom-name"
                     placeholder="Document name" style="display:none;">
            </div>
          </div>
          <div class="col-md-4">
            <div class="form-group mb-0">
              <label>Choose File</label>
              <input type="file" name="document_file[]" class="form-control-file doc-file-input"
                     accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
                     style="padding:10px; border:2px solid #e2e8f0; border-radius:8px; width:100%;">
            </div>
          </div>
          <div class="col-md-1 d-flex align-items-end">
            <button type="button" class="btn btn-danger btn-sm btn-remove-doc" style="margin-bottom:1px;">
              <i class="fa fa-trash"></i>
            </button>
          </div>
        </div>
      </div>`;
    $('#documentUploadContainer').append(newRow);
  });

  // Remove document row
  $(document).on('click', '.btn-remove-doc', function() {
    $(this).closest('.document-row').remove();
  });

  // Remove existing document row
  $(document).on('click', '.btn-remove-existing-doc', function() {
    if (confirm('Are you sure you want to remove this document? You will need to upload a replacement if it is a required document.')) {
      $(this).closest('.existing-document-row').remove();
    }
  });

  // Form validation
  $('#onboardingForm').on('submit', function(e) {
    var valid = true;
    $(this).find('[required]').each(function() {
      if (!$(this).val()) {
        valid = false;
        $(this).css('border-color', '#dc2626');
      } else {
        $(this).css('border-color', '#e2e8f0');
      }
    });
    if (!valid) {
      e.preventDefault();
      $('html, body').animate({ scrollTop: $('.form-control[style*="dc2626"]').first().offset().top - 100 }, 500);
      alert('Please fill all required fields before submitting.');
    }
  });

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
<?php if (ob_get_level() > 0) { ob_end_flush(); } ?>
