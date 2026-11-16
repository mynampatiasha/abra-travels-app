<?php
// =========================================================================
// EMPLOYEE LIST PAGE - Enhanced with Employee Type & Birthday Ticket System
// =========================================================================

ob_start(); // Output buffering to prevent header errors
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
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

$col_check_wc = mysqli_query($con, "SHOW COLUMNS FROM hr_employees LIKE 'worker_category'");
if ($col_check_wc && mysqli_num_rows($col_check_wc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_employees ADD COLUMN worker_category VARCHAR(50) DEFAULT 'White Collar'");
}

// On PHP 8.1+, mysqli throws exceptions on query errors by default instead of
// returning false. This file's code (old and new) is written to check
// "if ($result) { ... }" after every mysqli_query() call, so force mysqli back
// to the classic error mode: return false on failure instead of throwing.
mysqli_report(MYSQLI_REPORT_OFF);

// Ensure database handles emojis (for birthday cakes 🎂)
mysqli_set_charset($con, 'utf8mb4');

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// FILE SIZE CONFIGURATION (in MB)
// =========================================================================
define('MAX_PHOTO_SIZE_MB', 2);  // 2 MB for profile photos
define('MAX_DOCUMENT_SIZE_MB', 5);  // 5 MB for documents
define('MAX_PHOTO_SIZE_BYTES', MAX_PHOTO_SIZE_MB * 1024 * 1024);
define('MAX_DOCUMENT_SIZE_BYTES', MAX_DOCUMENT_SIZE_MB * 1024 * 1024);

// =========================================================================
// 🎂 ENHANCED AUTOMATED BIRTHDAY TICKET SYSTEM
// =========================================================================
function runBirthdayCheck($con) {
    // 1. Identify ALL HR Department Employees (not just one person)
    $hr_query = mysqli_query($con, "
        SELECT id, employee_id, name, email
        FROM hr_employees
        WHERE department = 'HR'
        AND status = 'Active'
        ORDER BY name ASC
    ");

    if(!$hr_query || mysqli_num_rows($hr_query) == 0) {
        error_log("Birthday Check: No active HR department employees found");
        return; // Exit if no HR employees found
    }

    // Get all HR employees
    $hr_employees = [];
    while($hr_row = mysqli_fetch_assoc($hr_query)) {
        $hr_employees[] = $hr_row;
    }

    // 2. Get Tomorrow's Date (Month-Day format)
    $tomorrow_md = date('m-d', strtotime('+1 day'));
    $display_date = date('d M Y', strtotime('+1 day'));
    $current_year = date('Y');

    // 3. Find Active Employees with Birthday Tomorrow
    $bday_sql = "
        SELECT employee_id, name, department, email, dob
        FROM hr_employees
        WHERE DATE_FORMAT(dob, '%m-%d') = '$tomorrow_md'
        AND status = 'Active'
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
                // 6. No existing ticket - Create Tickets for ALL HR Employees

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

                // Create ticket for EACH HR employee
                foreach($hr_employees as $hr_person) {
                    $ticket_number = 'BDAY-' . date('Ymd') . '-' . $hr_person['employee_id'] . '-' . rand(100, 999);

                    $insert_sql = "
                        INSERT INTO tickets
                        (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at)
                        VALUES
                        ('$ticket_number', '$created_by', '$safe_subject', '$safe_message', '$status', '$priority', '{$hr_person['id']}', NOW(), NOW())
                    ";

                    if(mysqli_query($con, $insert_sql)) {
                        $tickets_created++;
                        error_log("Birthday Ticket Created: #$ticket_number for {$emp['name']} assigned to {$hr_person['name']}");
                    } else {
                        error_log("Birthday Ticket Creation Failed for {$hr_person['name']}: " . mysqli_error($con));
                    }
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
        error_log("Birthday Check Complete: $tickets_created new birthday tickets created for HR team");
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

// Admin lands on the Overview dashboard by default when opening this page.
// Add ?tableview=1 to the URL to land on the employee table instead.
$ov_default = ($isAdmin && !isset($_GET['tableview']));

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
        'Official Email', 'Hire Date', 'Department', 'Position', 'Employee Type', 'Worker Category', 'Salary', 'Work Location', 'Timings', 'Company Name', 'Status'
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
        email, hire_date, department, position, employee_type, worker_category, salary, work_location, timings, company_name, status
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
        'Official Email', 'Hire Date', 'Department', 'Position', 'Employee Type', 'Worker Category', 'Salary', 'Work Location', 'Timings', 'Company Name', 'Status'
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
// SYNC EMPLOYEE DEPARTMENT/POSITION WITH LATEST COMPLETED CROSS TRAINING
// (Catches any transfers that completed before the live sync was in place,
// and acts as a safety net for future completions too.)
// =========================================================================
$sync_sql = "
    SELECT ct.employee_id, ct.to_dept_id, ct.to_pos_id, td.name as to_dept_name, tp.title as to_pos_name
    FROM hr_oje_cross_training ct
    INNER JOIN (
        SELECT employee_id, MAX(created_at) as latest_created
        FROM hr_oje_cross_training
        WHERE status = 'completed'
        GROUP BY employee_id
    ) latest ON latest.employee_id = ct.employee_id AND latest.latest_created = ct.created_at
    LEFT JOIN hr_departments td ON td.id = ct.to_dept_id
    LEFT JOIN hr_positions   tp ON tp.id = ct.to_pos_id
    WHERE ct.status = 'completed'
";
$sync_res = mysqli_query($con, $sync_sql);
if ($sync_res) {
    while ($sr = mysqli_fetch_assoc($sync_res)) {
        $sr_dept_name = mysqli_real_escape_string($con, $sr['to_dept_name'] ?? '');
        $sr_pos_name  = mysqli_real_escape_string($con, $sr['to_pos_name'] ?? '');
        $sr_pos_id    = intval($sr['to_pos_id']);
        $sr_emp_id    = intval($sr['employee_id']);
        if ($sr_dept_name !== '') {
            mysqli_query($con, "UPDATE hr_employees SET department='$sr_dept_name', position='$sr_pos_name', position_id=$sr_pos_id WHERE id=$sr_emp_id AND (department != '$sr_dept_name' OR position != '$sr_pos_name' OR position_id != $sr_pos_id)");
        }
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
// COUNT UPCOMING BIRTHDAYS AND GET NAMES
// =========================================================================
$upcoming_birthdays_count = 0;
$upcoming_birthdays_list = [];
$today_md = date('m-d');
$next_7_days = [];
for($i = 1; $i <= 7; $i++) {
    $next_7_days[] = date('m-d', strtotime("+$i days"));
}
$birthday_list_sql = implode("','", $next_7_days);

// Fetch birthday details with names and dates
$upcoming_bday_query = mysqli_query($con, "
    SELECT name, employee_id, dob, department,
           DATE_FORMAT(dob, '%d %b') as birthday_display,
           DATEDIFF(
               STR_TO_DATE(CONCAT(YEAR(CURDATE()), '-', DATE_FORMAT(dob, '%m-%d')), '%Y-%m-%d'),
               CURDATE()
           ) as days_until
    FROM hr_employees
    WHERE DATE_FORMAT(dob, '%m-%d') IN ('$birthday_list_sql')
    AND status = 'Active'
    ORDER BY days_until ASC, name ASC
");

if($upcoming_bday_query) {
    while($bday_row = mysqli_fetch_assoc($upcoming_bday_query)) {
        $upcoming_birthdays_list[] = $bday_row;
    }
    $upcoming_birthdays_count = count($upcoming_birthdays_list);
}

// =========================================================================
// ADMIN OVERVIEW DASHBOARD DATA — Active / Inactive tabs, 6 charts each
// =========================================================================

// Strips punctuation and common legal-entity suffix words ("pvt", "ltd",
// "private", "limited", etc.) so "Abra E Logistic" and "Abra E Logistic
// Pvt. Ltd." normalize to the same key and can be merged into one bucket.
function hr_normalize_company_name($s) {
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    $s = preg_replace('/\b(pvt|private|ltd|limited|llp|inc|incorporated|co|company|corp|corporation)\b/', '', $s);
    $s = trim(preg_replace('/\s+/', ' ', $s));
    return $s;
}

// Builds the label/count/detail arrays for one status bucket ('active' or
// 'inactive') that feed the 6 Overview charts. Department, Type, Location,
// Gender are grouped straight off hr_employees (just TRIM()'d for stray
// whitespace). Company additionally gets fuzzy-matched against the
// hr_companies master list ($master_companies) via hr_normalize_company_name()
// so old free-text spellings and the current "Pvt. Ltd." naming collapse
// into a single bucket labeled with the master table's current name, instead
// of showing up as two separate slices. Anything that matches no master
// entry still shows up under its own raw text — nothing is silently dropped.
function hr_build_overview_bucket($con, $status_value, $master_companies) {
    $status_lc = mysqli_real_escape_string($con, strtolower($status_value));
    $data = array(
        'dept_labels' => array(), 'dept_counts' => array(), 'dept_employees' => array(),
        'status_labels' => array(), 'status_counts' => array(), 'status_employees' => array(),
        'type_labels' => array(), 'type_counts' => array(), 'type_employees' => array(),
        'loc_labels' => array(), 'loc_counts' => array(), 'loc_employees' => array(),
        'company_labels' => array(), 'company_counts' => array(), 'company_employees' => array(),
        'gender_labels' => array(), 'gender_counts' => array(), 'gender_employees' => array(),
    );

    $dq = mysqli_query($con, "SELECT TRIM(department) AS department, COUNT(*) c FROM hr_employees WHERE department IS NOT NULL AND TRIM(department) != '' AND LOWER(status)='$status_lc' GROUP BY TRIM(department) ORDER BY c DESC");
    if ($dq) { while ($row = mysqli_fetch_assoc($dq)) { $data['dept_labels'][] = $row['department']; $data['dept_counts'][] = (int)$row['c']; } }

    $sq = mysqli_query($con, "SELECT status, COUNT(*) c FROM hr_employees WHERE status IS NOT NULL AND status != '' AND LOWER(status)='$status_lc' GROUP BY status ORDER BY c DESC");
    if ($sq) { while ($row = mysqli_fetch_assoc($sq)) { $data['status_labels'][] = ucfirst($row['status']); $data['status_counts'][] = (int)$row['c']; } }

    $tq = mysqli_query($con, "SELECT employee_type, COUNT(*) c FROM hr_employees WHERE employee_type IS NOT NULL AND employee_type != '' AND LOWER(status)='$status_lc' GROUP BY employee_type ORDER BY c DESC");
    if ($tq) { while ($row = mysqli_fetch_assoc($tq)) { $data['type_labels'][] = $row['employee_type']; $data['type_counts'][] = (int)$row['c']; } }

    $lq = mysqli_query($con, "SELECT work_location, COUNT(*) c FROM hr_employees WHERE work_location IS NOT NULL AND work_location != '' AND LOWER(status)='$status_lc' GROUP BY work_location ORDER BY c DESC");
    if ($lq) { while ($row = mysqli_fetch_assoc($lq)) { $data['loc_labels'][] = $row['work_location']; $data['loc_counts'][] = (int)$row['c']; } }

    $gq = mysqli_query($con, "SELECT gender, COUNT(*) c FROM hr_employees WHERE gender IS NOT NULL AND gender != '' AND LOWER(status)='$status_lc' GROUP BY gender ORDER BY c DESC");
    if ($gq) { while ($row = mysqli_fetch_assoc($gq)) { $data['gender_labels'][] = $row['gender']; $data['gender_counts'][] = (int)$row['c']; } }

    $deq = mysqli_query($con, "SELECT TRIM(department) AS department, name, position FROM hr_employees WHERE department IS NOT NULL AND TRIM(department) != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($deq) { while ($row = mysqli_fetch_assoc($deq)) { $data['dept_employees'][$row['department']][] = array('primary' => $row['name'], 'secondary' => $row['position']); } }

    $seq = mysqli_query($con, "SELECT status, name, employee_id FROM hr_employees WHERE status IS NOT NULL AND status != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($seq) { while ($row = mysqli_fetch_assoc($seq)) { $data['status_employees'][ucfirst($row['status'])][] = array('primary' => $row['name'], 'secondary' => $row['employee_id']); } }

    $teq = mysqli_query($con, "SELECT employee_type, name, department FROM hr_employees WHERE employee_type IS NOT NULL AND employee_type != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($teq) { while ($row = mysqli_fetch_assoc($teq)) { $data['type_employees'][$row['employee_type']][] = array('primary' => $row['name'], 'secondary' => $row['department']); } }

    $leq = mysqli_query($con, "SELECT work_location, name, department FROM hr_employees WHERE work_location IS NOT NULL AND work_location != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($leq) { while ($row = mysqli_fetch_assoc($leq)) { $data['loc_employees'][$row['work_location']][] = array('primary' => $row['name'], 'secondary' => $row['department']); } }

    $geq = mysqli_query($con, "SELECT gender, name, department FROM hr_employees WHERE gender IS NOT NULL AND gender != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($geq) { while ($row = mysqli_fetch_assoc($geq)) { $data['gender_employees'][$row['gender']][] = array('primary' => $row['name'], 'secondary' => $row['department']); } }

    // --- Company: fetch raw text per employee, then bucket in PHP using the
    // normalized master-list match, instead of grouping raw text in SQL. ---
    $norm_master_map = array();
    foreach ($master_companies as $mcname) {
        $norm_master_map[hr_normalize_company_name($mcname)] = $mcname;
    }
    $company_counts_map = array();
    $ceq = mysqli_query($con, "SELECT TRIM(company_name) AS company_name, name, department FROM hr_employees WHERE company_name IS NOT NULL AND TRIM(company_name) != '' AND LOWER(status)='$status_lc' ORDER BY name ASC");
    if ($ceq) {
        while ($row = mysqli_fetch_assoc($ceq)) {
            $norm = hr_normalize_company_name($row['company_name']);
            $label = isset($norm_master_map[$norm]) ? $norm_master_map[$norm] : $row['company_name'];
            if (!isset($company_counts_map[$label])) { $company_counts_map[$label] = 0; }
            $company_counts_map[$label]++;
            $data['company_employees'][$label][] = array('primary' => $row['name'], 'secondary' => $row['department']);
        }
    }
    arsort($company_counts_map);
    foreach ($company_counts_map as $label => $cnt) {
        $data['company_labels'][] = $label;
        $data['company_counts'][] = $cnt;
    }

    return $data;
}

if ($isAdmin) {
    $ov_emp_total = $resultado->num_rows;

    $ov_active_count = 0;
    $acq = mysqli_query($con, "SELECT COUNT(*) c FROM hr_employees WHERE LOWER(status)='active'");
    if ($acq) { $ov_active_count = (int)mysqli_fetch_assoc($acq)['c']; }

    $ov_inactive_count = 0;
    $icq = mysqli_query($con, "SELECT COUNT(*) c FROM hr_employees WHERE LOWER(status)='inactive'");
    if ($icq) { $ov_inactive_count = (int)mysqli_fetch_assoc($icq)['c']; }

    $ov_dept_total = 0;
    $odq = mysqli_query($con, "SELECT COUNT(DISTINCT TRIM(department)) c FROM hr_employees WHERE department IS NOT NULL AND TRIM(department) != '' AND LOWER(status)='active'");
    if ($odq) { $ov_dept_total = (int)mysqli_fetch_assoc($odq)['c']; }

    $ov_loc_total = 0;
    $olq = mysqli_query($con, "SELECT COUNT(DISTINCT work_location) c FROM hr_employees WHERE work_location IS NOT NULL AND work_location != '' AND LOWER(status)='active'");
    if ($olq) { $ov_loc_total = (int)mysqli_fetch_assoc($olq)['c']; }

    // Master company list, used to fuzzy-merge legal-entity spelling variants
    // (e.g. "Abra E Logistic" vs "Abra E Logistic Pvt. Ltd.") into one bucket.
    $hr_master_companies = array();
    if ($company_query && mysqli_num_rows($company_query) > 0) {
        mysqli_data_seek($company_query, 0);
        while ($mc_row = mysqli_fetch_assoc($company_query)) { $hr_master_companies[] = $mc_row['company_name']; }
    }

    // Active + Inactive datasets for the 6 charts (switched client-side via tabs)
    $ov_active_data = hr_build_overview_bucket($con, 'active', $hr_master_companies);
    $ov_inactive_data = hr_build_overview_bucket($con, 'inactive', $hr_master_companies);

    // Companies total now comes straight from the merged/bucketed active data,
    // so the stat card always matches what the chart actually shows.
    $ov_company_total = count($ov_active_data['company_labels']);

    // Back-compat aliases used by the stat-card summaries below
    $ov_dept_labels = $ov_active_data['dept_labels'];
    $ov_dept_counts = $ov_active_data['dept_counts'];
    $ov_loc_labels = $ov_active_data['loc_labels'];
    $ov_loc_counts = $ov_active_data['loc_counts'];
    $ov_company_labels = $ov_active_data['company_labels'];
    $ov_company_counts = $ov_active_data['company_counts'];

    // --- Stat-card click details (Total / Active / Departments / Locations / Companies / Birthdays) ---
    // "Total Employees" card intentionally still shows everyone, since "Active" already has its own card.
    $ov_all_employees_list = array();
    $aeq = mysqli_query($con, "SELECT name, employee_id, department, status FROM hr_employees ORDER BY name ASC");
    if ($aeq) { while ($row = mysqli_fetch_assoc($aeq)) { $ov_all_employees_list[] = array('primary' => $row['name'], 'secondary' => ($row['department'] ?: 'No Department') . ' — ' . ucfirst($row['status'] ?: 'N/A')); } }

    $ov_active_employees_list = array();
    $atq = mysqli_query($con, "SELECT name, employee_id, department FROM hr_employees WHERE LOWER(status)='active' ORDER BY name ASC");
    if ($atq) { while ($row = mysqli_fetch_assoc($atq)) { $ov_active_employees_list[] = array('primary' => $row['name'], 'secondary' => $row['department'] ?: 'No Department'); } }

    $ov_inactive_employees_list = array();
    $itq = mysqli_query($con, "SELECT name, employee_id, department FROM hr_employees WHERE LOWER(status)='inactive' ORDER BY name ASC");
    if ($itq) { while ($row = mysqli_fetch_assoc($itq)) { $ov_inactive_employees_list[] = array('primary' => $row['name'], 'secondary' => $row['department'] ?: 'No Department'); } }

    $ov_dept_summary_list = array();
    foreach ($ov_dept_labels as $i => $dn) { $ov_dept_summary_list[] = array('primary' => $dn, 'secondary' => $ov_dept_counts[$i] . ' employee' . ($ov_dept_counts[$i] != 1 ? 's' : '')); }

    $ov_loc_summary_list = array();
    foreach ($ov_loc_labels as $i => $ln) { $ov_loc_summary_list[] = array('primary' => $ln, 'secondary' => $ov_loc_counts[$i] . ' employee' . ($ov_loc_counts[$i] != 1 ? 's' : '')); }

    $ov_company_summary_list = array();
    foreach ($ov_company_labels as $i => $cn) { $ov_company_summary_list[] = array('primary' => $cn, 'secondary' => $ov_company_counts[$i] . ' employee' . ($ov_company_counts[$i] != 1 ? 's' : '')); }
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

    .btn-warn { background: linear-gradient(135deg, #f97316 0%, #ea580c 100%); box-shadow: 0 4px 15px rgba(249, 115, 22, 0.3); }
    .btn-warn:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(249, 115, 22, 0.4); color: white; text-decoration: none; }

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

    /* Active / Inactive overview tabs */
    .ov-tab-btn {
      border: 2px solid #e2e8f0;
      background: #fff;
      color: #64748b;
      font-weight: 700;
      font-size: 14px;
      padding: 10px 22px;
      border-radius: 10px;
      cursor: pointer;
      transition: all 0.2s;
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }
    .ov-tab-btn:hover { border-color: #1e40af; color: #1e3a8a; }
    .ov-tab-btn.ov-tab-active {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      border-color: #1e3a8a;
      color: #fff;
      box-shadow: 0 4px 12px rgba(30, 58, 138, 0.3);
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
      <div class="birthday-alert" onclick="$('#birthdayModal').modal('show')" style="cursor: pointer;" title="Click to view details">
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
    
    <a href="hr-employees-add.php" class="btn-action btn-add">
      <i class="fas fa-user-plus"></i> Add Employee
    </a>
    <a href="hr-appraisal.php" class="btn-action btn-warn">
      <i class="fas fa-chart-line"></i> Employee Appraisal
    </a>
    <button type="button" class="btn-action btn-import" onclick="$('#importModal').modal('show')">
      <i class="fas fa-upload"></i> Import CSV
    </button>
    <a href="?export=csv" class="btn-action btn-export">
      <i class="fas fa-download"></i> Export Data
    </a>
    <?php if ($isAdmin): ?>
    <button type="button" id="ovToggleBtn" class="btn-action btn-dashboard" onclick="showOvPanel()">
      <i class="fas fa-chart-pie"></i> View Overview
    </button>
    <?php endif; ?>
  </div>

  <?php if ($isAdmin): ?>
  <!-- ============================================================
       ADMIN OVERVIEW — GRAPHS SUMMARIZING THE EMPLOYEE LIST
  ============================================================ -->
  <div id="ovPanel" style="display:<?php echo $ov_default ? 'block' : 'none'; ?>;">
    <div class="action-bar" style="justify-content:flex-start;">
      <button type="button" class="btn-action btn-dashboard" onclick="hideOvPanel()">
        <i class="fas fa-table"></i> Back to Employee List
      </button>
    </div>

    <div style="display:flex;flex-wrap:wrap;gap:16px;margin-bottom:20px;">
        <div onclick="showOvDetail('<i class=\'fas fa-users\'></i> All Employees', ovAllEmployees)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #1e3a8a;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_emp_total; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Total Employees</div>
        </div>
        <div onclick="showOvDetail('<i class=\'fas fa-user-check\'></i> Active Employees', ovActiveEmployees)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #059669;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_active_count; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Active</div>
        </div>
        <div onclick="showOvDetail('<i class=\'fas fa-sitemap\'></i> Departments', ovDeptSummary)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #f59e0b;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_dept_total; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Departments</div>
        </div>
        <div onclick="showOvDetail('<i class=\'fas fa-map-marker-alt\'></i> Work Locations', ovLocSummary)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #8b5cf6;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_loc_total; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Work Locations</div>
        </div>
        <div onclick="showOvDetail('<i class=\'fas fa-building\'></i> Companies', ovCompanySummary)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #dc2626;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_company_total; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Companies</div>
        </div>
        <div onclick="showOvDetail('<i class=\'fas fa-user-slash\'></i> Inactive Employees', ovInactiveEmployees)" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #94a3b8;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $ov_inactive_count; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Inactive</div>
        </div>
        <div onclick="$('#birthdayModal').modal('show')" style="cursor:pointer;flex:1;min-width:140px;background:#fff;border-radius:12px;padding:18px 20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border-left:4px solid #ec4899;transition:transform .15s;" onmouseover="this.style.transform='translateY(-2px)'" onmouseout="this.style.transform='translateY(0)'">
            <div style="font-size:1.8rem;font-weight:800;color:#1e3a8a;"><?php echo $upcoming_birthdays_count; ?></div>
            <div style="font-size:12px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.5px;">Birthdays This Week</div>
        </div>
    </div>

    <!-- ACTIVE / INACTIVE TAB TOGGLE — switches the 6 charts below between the two datasets -->
    <div style="display:flex;gap:10px;margin-bottom:18px;">
        <button type="button" id="ovTabActiveBtn" class="ov-tab-btn ov-tab-active" onclick="switchOvTab('active')">
            <i class="fas fa-user-check"></i> Active Employees
        </button>
        <button type="button" id="ovTabInactiveBtn" class="ov-tab-btn" onclick="switchOvTab('inactive')">
            <i class="fas fa-user-slash"></i> Inactive Employees
        </button>
    </div>

    <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">
        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);grid-column: span 2;">
            <h4 style="margin:0 0 4px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-sitemap"></i> Employees per Department</h4>
            <p style="margin:0 0 14px;color:#94a3b8;font-size:12px;font-weight:600;"><i class="fas fa-hand-pointer"></i> Click a bar to view that department's employees</p>
            <div style="position:relative;height:320px;">
                <canvas id="ovDeptChart"></canvas>
            </div>
        </div>

        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 18px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-user-check"></i> Employees by Status</h4>
            <div style="position:relative;height:260px;">
                <canvas id="ovStatusChart"></canvas>
            </div>
        </div>

        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 18px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-id-badge"></i> Employees by Type</h4>
            <div style="position:relative;height:260px;">
                <canvas id="ovTypeChart"></canvas>
            </div>
        </div>

        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 18px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-map-marker-alt"></i> Employees by Work Location</h4>
            <div style="position:relative;height:260px;">
                <canvas id="ovLocChart"></canvas>
            </div>
        </div>

        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);">
            <h4 style="margin:0 0 18px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-building"></i> Employees by Company</h4>
            <div style="position:relative;height:260px;">
                <canvas id="ovCompanyChart"></canvas>
            </div>
        </div>

        <div style="background:#fff;border-radius:14px;padding:24px 28px;box-shadow:0 2px 10px rgba(0,0,0,0.08);grid-column: span 2;">
            <h4 style="margin:0 0 18px;color:#1e3a8a;font-weight:800;font-size:1.1rem;"><i class="fas fa-venus-mars"></i> Employees by Gender</h4>
            <div style="position:relative;height:240px;">
                <canvas id="ovGenderChart"></canvas>
            </div>
        </div>
    </div>

    <!-- INLINE DETAIL PANEL — opens on this same page when a chart above is clicked -->
    <div id="ovDetailPanel" style="display:none;background:#fff;border-radius:14px;padding:24px 28px;margin-top:20px;box-shadow:0 2px 10px rgba(0,0,0,0.08);border:2px solid #dbeafe;">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
            <h4 id="ovDetailTitle" style="margin:0;color:#1e3a8a;font-weight:800;font-size:1.1rem;"></h4>
            <button type="button" onclick="closeOvDetail()" style="background:#f1f5f9;border:none;border-radius:6px;padding:6px 14px;cursor:pointer;color:#64748b;font-weight:700;font-size:12px;">
                <i class="fas fa-times"></i> Close
            </button>
        </div>
        <div id="ovDetailBody"></div>
    </div>
  </div>
  <?php endif; ?>

  <div id="empListMainView" style="display:<?php echo $ov_default ? 'none' : 'block'; ?>;">

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
          <option value="Training & OJE">Training & OJE</option>
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
          <th>Worker Category</th>
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

            // Count cross-training history for this employee (career path indicator)
            $ct_hist_query = mysqli_query($con, "SELECT COUNT(*) as count FROM hr_oje_cross_training WHERE employee_id = " . intval($row['id']));
            $ct_hist_row = $ct_hist_query ? mysqli_fetch_assoc($ct_hist_query) : ['count' => 0];
            $ct_hist_count = $ct_hist_row['count'];
        ?>
        <tr>
          <td><?php echo $sl_no++; ?></td>
          <td><strong><?php echo htmlspecialchars($row['employee_id'] ?? ''); ?></strong></td>
          <td>
            <?php echo htmlspecialchars($row['name'] ?? ''); ?>
            <?php if ($ct_hist_count > 0): ?>
              <a href="#" onclick="viewCrossTrainingHistory('<?php echo $row['id']; ?>', '<?php echo addslashes($row['name']); ?>'); return false;" title="View Cross-Training Career Path" style="margin-left:6px;color:#8b5cf6;">
                <i class="fas fa-route"></i>
              </a>
            <?php endif; ?>
          </td>
          <td class="text-wrap-cell"><?php echo htmlspecialchars($row['position'] ?? ''); ?></td>
          <td class="text-wrap-cell"><?php echo htmlspecialchars($row['department'] ?? ''); ?></td>
          <td><?php echo htmlspecialchars($row['employee_type'] ?? ''); ?></td>
          <td>
            <?php 
            $wc = htmlspecialchars($row['worker_category'] ?? 'White Collar'); 
            if($wc == 'Blue Collar') {
                echo '<span class="badge" style="background:#1e40af;color:white;">Blue Collar</span>';
            } else {
                echo '<span class="badge" style="background:#64748b;color:white;">White Collar</span>';
            }
            ?>
          </td>
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
  <!-- /#empListMainView -->

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

<!-- BIRTHDAY MODAL -->
<div class="modal fade" id="birthdayModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #ec4899 0%, #db2777 100%);">
        <h4 class="modal-title"><i class="fas fa-birthday-cake"></i> Upcoming Birthdays This Week</h4>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <?php if(!empty($upcoming_birthdays_list)): ?>
          <div class="alert alert-info" style="border-radius: 10px; background: #fef3c7; border: none; color: #92400e; margin-bottom: 20px;">
            <i class="fas fa-info-circle"></i> <strong>Celebrate with your colleagues!</strong> The following employees have birthdays coming up this week.
          </div>

          <div style="display: grid; gap: 15px;">
            <?php foreach($upcoming_birthdays_list as $bday): ?>
              <?php
                $days_until = $bday['days_until'];
                $when_text = '';
                if($days_until == 0) {
                  $when_text = '<span style="background: #10b981; color: white; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700;">TODAY 🎉</span>';
                } elseif($days_until == 1) {
                  $when_text = '<span style="background: #f59e0b; color: white; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700;">TOMORROW</span>';
                } else {
                  $when_text = '<span style="background: #6366f1; color: white; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700;">IN ' . $days_until . ' DAYS</span>';
                }
              ?>
              <div style="background: linear-gradient(135deg, #fdf2f8 0%, #fce7f3 100%); padding: 20px; border-radius: 12px; border-left: 5px solid #ec4899; display: flex; align-items: center; justify-content: space-between;">
                <div style="flex: 1;">
                  <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 8px;">
                    <i class="fas fa-birthday-cake" style="font-size: 24px; color: #ec4899;"></i>
                    <div>
                      <div style="font-size: 18px; font-weight: 700; color: #831843;">
                        <?php echo htmlspecialchars($bday['name']); ?>
                      </div>
                      <div style="font-size: 13px; color: #9f1239; margin-top: 2px;">
                        <i class="fas fa-id-badge"></i> <?php echo htmlspecialchars($bday['employee_id']); ?>
                        | <i class="fas fa-building"></i> <?php echo htmlspecialchars($bday['department']); ?>
                      </div>
                    </div>
                  </div>
                </div>
                <div style="text-align: right;">
                  <div style="font-size: 16px; font-weight: 700; color: #be185d; margin-bottom: 6px;">
                    <i class="far fa-calendar-alt"></i> <?php echo $bday['birthday_display']; ?>
                  </div>
                  <?php echo $when_text; ?>
                </div>
              </div>
            <?php endforeach; ?>
          </div>

          <div style="margin-top: 25px; padding: 20px; background: #f0fdf4; border-radius: 10px; border-left: 4px solid #10b981;">
            <strong style="color: #065f46;"><i class="fas fa-lightbulb"></i> Reminder:</strong>
            <ul style="margin: 10px 0 0 20px; color: #047857;">
              <li>Birthday tickets have been automatically created for the HR team</li>
              <li>Coordinate with your team to send wishes and arrange celebrations</li>
              <li>Check your tickets dashboard for birthday notifications</li>
            </ul>
          </div>
        <?php else: ?>
          <div style="text-align: center; padding: 40px;">
            <i class="fas fa-calendar-check" style="font-size: 64px; color: #d1d5db; margin-bottom: 20px;"></i>
            <p style="color: #6b7280; font-size: 16px;">No upcoming birthdays this week.</p>
          </div>
        <?php endif; ?>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<!-- CROSS TRAINING HISTORY MODAL -->
<div class="modal fade" id="crossTrainingModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);">
        <h4 class="modal-title" style="color:white;"><i class="fas fa-route"></i> Cross-Training Career Path - <span id="ctEmployeeName"></span></h4>
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      </div>
      <div class="modal-body">
        <div id="ctHistoryContent">
          <div style="text-align: center; padding: 40px;">
            <div class="spinner"></div>
            <p style="color: #64748b; font-weight: 600; margin-top: 15px;">Loading career path...</p>
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
      </div>
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
<?php if ($isAdmin): ?>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<?php endif; ?>

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
        { width: "180px", targets: 6 },  // Worker Category
        { width: "320px", targets: 7 },  // Official Email
        { width: "150px", targets: 8 },  // Mobile
        { width: "200px", targets: 9 },  // Work Location
        { width: "250px", targets: 10 },  // Company Name
        { width: "150px", targets: 11 }, // Salary
        { width: "130px", targets: 12 }, // Status
        { width: "150px", targets: 13 }, // Country
        { width: "150px", targets: 14 }, // State
        { width: "110px", targets: 15 }, // Gender
        { width: "140px", targets: 16 }, // DOB
        { width: "110px", targets: 17 }, // Blood
        { width: "150px", targets: 18 }, // Alt Phone
        { width: "170px", targets: 19 }, // Aadhar
        { width: "150px", targets: 20 }, // PAN
        { width: "320px", targets: 21 }, // Personal Email
        { width: "400px", targets: 22, className: "text-wrap-cell" }, // Address
        { width: "200px", targets: 23 }, // Emg.Contact
        { width: "140px", targets: 24 }, // Relation
        { width: "150px", targets: 25 }, // Emg.Phone
        { width: "150px", targets: 26 }, // Emg.Alt
        { width: "280px", targets: 27 }, // Degree
        { width: "110px", targets: 28 }, // Year
        { width: "130px", targets: 29 }, // GPA/%
        { width: "200px", targets: 30 }, // Bank Acc
        { width: "150px", targets: 31 }, // IFSC
        { width: "250px", targets: 32 }, // Branch
        { width: "150px", targets: 33 }, // Join Date
        { width: "250px", targets: 34 }, // Timings
        { width: "220px", targets: 35 }, // Reporting Manager 1
        { width: "220px", targets: 36 }, // Reporting Manager 2
        { width: "200px", targets: 37 }  // Actions
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
      // 0:Sl, 1:ID, 2:Name, 3:Desig, 4:Dept, 5:Type, 6:Worker Category, 7:Email, 8:Mob, 9:Loc, 10:Company, 11:Sal, 12:Status, 13:Country, 14:State
      var status = data[12] || '';
      var dept = data[4] || '';
      var type = data[5] || '';
      var position = data[3] || '';
      var location = data[9] || '';
      var company = data[10] || '';
      var country = data[13] || '';
      var state = data[14] || '';

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

    <?php if ($ov_default): ?>
    // Admin default view: land on the Overview dashboard, charts included
    ovChartsInitialized = true;
    renderOvCharts(ovCurrentTab);
    <?php endif; ?>
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

  // View Cross-Training History Function
  function viewCrossTrainingHistory(employeeId, employeeName) {
    $('#ctEmployeeName').text(employeeName);
    $('#crossTrainingModal').modal('show');

    $.ajax({
      url: 'get-employee-crosstraining-history.php',
      method: 'GET',
      data: { employee_id: employeeId },
      success: function(response) {
        $('#ctHistoryContent').html(response);
      },
      error: function() {
        $('#ctHistoryContent').html('<div class="alert alert-danger">Failed to load career path</div>');
      }
    });
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

  <?php if ($isAdmin): ?>
  // =====================================================================
  // ADMIN OVERVIEW — graphs summarizing employees, with an Active/Inactive
  // tab toggle (inline detail, no page redirect on click)
  // =====================================================================
  var ovDatasets = {
    active: <?php echo json_encode($ov_active_data); ?>,
    inactive: <?php echo json_encode($ov_inactive_data); ?>
  };

  // Stat-card click data
  var ovAllEmployees = <?php echo json_encode($ov_all_employees_list); ?>;
  var ovActiveEmployees = <?php echo json_encode($ov_active_employees_list); ?>;
  var ovInactiveEmployees = <?php echo json_encode($ov_inactive_employees_list); ?>;
  var ovDeptSummary = <?php echo json_encode($ov_dept_summary_list); ?>;
  var ovLocSummary = <?php echo json_encode($ov_loc_summary_list); ?>;
  var ovCompanySummary = <?php echo json_encode($ov_company_summary_list); ?>;

  var ovChartsInitialized = false;
  var ovCurrentTab = 'active';
  var ovChartInstances = {};

  function showOvPanel() {
    $('#empListMainView').hide();
    $('#ovPanel').show();
    if (!ovChartsInitialized) {
      renderOvCharts(ovCurrentTab);
      ovChartsInitialized = true;
    }
  }

  function hideOvPanel() {
    $('#ovPanel').hide();
    $('#empListMainView').show();
    if (table) { table.columns.adjust(); }
  }

  function switchOvTab(tab) {
    if (tab === ovCurrentTab) return;
    ovCurrentTab = tab;
    document.getElementById('ovTabActiveBtn').classList.toggle('ov-tab-active', tab === 'active');
    document.getElementById('ovTabInactiveBtn').classList.toggle('ov-tab-active', tab === 'inactive');
    closeOvDetail();
    renderOvCharts(tab);
  }

  function showOvDetail(title, rows) {
    var body = '';
    if (!rows || rows.length === 0) {
      body = '<div style="text-align:center;padding:24px;color:#94a3b8;font-weight:600;">No records found.</div>';
    } else {
      body = '<div style="display:flex;flex-direction:column;gap:8px;max-height:360px;overflow-y:auto;">';
      rows.forEach(function(r) {
        body += '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;background:#f8fafc;border-radius:8px;padding:10px 14px;">' +
                '<span style="font-weight:700;color:#0f172a;">' + r.primary + '</span>' +
                (r.secondary ? '<span style="font-size:12px;color:#64748b;font-weight:600;white-space:nowrap;">' + r.secondary + '</span>' : '') +
                '</div>';
      });
      body += '</div>';
    }
    $('#ovDetailTitle').html(title);
    $('#ovDetailBody').html(body);
    var panel = document.getElementById('ovDetailPanel');
    panel.style.display = 'block';
    panel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  function closeOvDetail() {
    document.getElementById('ovDetailPanel').style.display = 'none';
  }

  function destroyOvChart(id) {
    if (ovChartInstances[id]) {
      ovChartInstances[id].destroy();
      delete ovChartInstances[id];
    }
  }

  function renderOvCharts(tab) {
    var d = ovDatasets[tab];

    ['ovDeptChart','ovStatusChart','ovTypeChart','ovLocChart','ovCompanyChart','ovGenderChart'].forEach(destroyOvChart);

    var deptCtx = document.getElementById('ovDeptChart');
    if (deptCtx && d.dept_labels.length > 0) {
      ovChartInstances['ovDeptChart'] = new Chart(deptCtx.getContext('2d'), {
        type: 'bar',
        data: { labels: d.dept_labels, datasets: [{ label: 'Employees', data: d.dept_counts, backgroundColor: '#1e3a8a', borderRadius: 6, borderSkipped: false }] },
        options: {
          responsive: true, maintainAspectRatio: false, animation: false,
          onClick: function(evt, elements) {
            if (elements.length > 0) {
              var idx = elements[0].index;
              var dept = d.dept_labels[idx];
              showOvDetail('<i class="fas fa-sitemap"></i> ' + dept + ' — Employees', d.dept_employees[dept]);
            }
          },
          onHover: function(evt, elements) { evt.native.target.style.cursor = elements.length ? 'pointer' : 'default'; },
          plugins: { legend: { display: false }, tooltip: { callbacks: { label: function(c){ return c.parsed.y + ' employee' + (c.parsed.y != 1 ? 's' : '') + ' — click to view'; } } } },
          scales: {
            x: { grid: { display: false }, ticks: { font: { size: 11, weight: '600' }, color: '#334155', maxRotation: 40, minRotation: 0 } },
            y: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: 'rgba(0,0,0,0.05)' } }
          }
        }
      });
    }

    function makeOvDoughnut(canvasId, labels, counts, employeesMap, colors, iconHtml) {
      var ctx = document.getElementById(canvasId);
      if (!ctx || labels.length === 0) return;
      ovChartInstances[canvasId] = new Chart(ctx.getContext('2d'), {
        type: 'doughnut',
        data: { labels: labels, datasets: [{ data: counts, backgroundColor: colors }] },
        options: {
          responsive: true, maintainAspectRatio: false,
          onClick: function(evt, elements) {
            if (elements.length > 0) {
              var idx = elements[0].index;
              var key = labels[idx];
              showOvDetail(iconHtml + ' ' + key, employeesMap[key]);
            }
          },
          onHover: function(evt, elements) { evt.native.target.style.cursor = elements.length ? 'pointer' : 'default'; },
          plugins: { legend: { position: 'bottom', labels: { boxWidth: 12, font: { size: 11 } } } }
        }
      });
    }

    var palette = ['#1e3a8a','#059669','#f59e0b','#8b5cf6','#dc2626','#0891b2','#ec4899','#64748b'];
    makeOvDoughnut('ovStatusChart', d.status_labels, d.status_counts, d.status_employees, ['#059669','#f59e0b','#dc2626','#64748b'], '<i class="fas fa-user-check"></i>');
    makeOvDoughnut('ovTypeChart', d.type_labels, d.type_counts, d.type_employees, palette, '<i class="fas fa-id-badge"></i>');
    makeOvDoughnut('ovLocChart', d.loc_labels, d.loc_counts, d.loc_employees, palette, '<i class="fas fa-map-marker-alt"></i>');
    makeOvDoughnut('ovCompanyChart', d.company_labels, d.company_counts, d.company_employees, palette, '<i class="fas fa-building"></i>');
    makeOvDoughnut('ovGenderChart', d.gender_labels, d.gender_counts, d.gender_employees, ['#3b82f6','#ec4899','#8b5cf6'], '<i class="fas fa-venus-mars"></i>');
  }
  <?php endif; ?>
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