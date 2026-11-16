<?php
// =========================================================================
// HR EMPLOYEE ONBOARDING PENDING LIST - HR Review Dashboard
// =========================================================================
ob_start();
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
if (file_exists('mail_helper.php')) { require_once('mail_helper.php'); }

// =========================================================================
// ADMIN CHECK FOR DASHBOARD BUTTON
// =========================================================================
mysqli_report(MYSQLI_REPORT_OFF);
$btn_currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$btn_authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$btn_isAdmin = false;
foreach($btn_authorized_admin_names as $admin_name) {
    if(stripos($btn_currentUserName, $admin_name) !== false || stripos($admin_name, $btn_currentUserName) !== false) {
        $btn_isAdmin = true;
        break;
    }
}
$dashboard_url = $btn_isAdmin ? 'index.php' : 'db-dashboard.php';

require_once('funciones.php');

$con = conexion();
mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

// Ensure hr_employees has all newly added columns to prevent INSERT from failing
$he_cols = [
    'email' => 'VARCHAR(255) DEFAULT NULL',
    'hire_date' => 'DATE DEFAULT NULL',
    'department' => 'VARCHAR(255) DEFAULT NULL',
    'position' => 'VARCHAR(255) DEFAULT NULL',
    'reporting_manager_1' => 'VARCHAR(255) DEFAULT NULL',
    'reporting_manager_2' => 'VARCHAR(255) DEFAULT NULL',
    'salary' => 'VARCHAR(100) DEFAULT NULL',
    'work_location' => 'VARCHAR(255) DEFAULT NULL',
    'timings' => 'VARCHAR(255) DEFAULT NULL',
    'company_name' => 'VARCHAR(255) DEFAULT NULL',
    'employee_type' => 'VARCHAR(100) DEFAULT NULL'
];
foreach ($he_cols as $c_name => $c_def) {
    $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_employees LIKE '$c_name'");
    if (!$chk || mysqli_num_rows($chk) == 0) {
        mysqli_query($con, "ALTER TABLE hr_employees ADD COLUMN $c_name $c_def");
    }
}

// =========================================================================
// SAFE EMPLOYEE ID GENERATION
// Prevents two approvals racing to the same ABRAxxx id (which was causing
// different candidates' documents to land in the same employee folder).
// Uses a locked counter row instead of "SELECT MAX + 1".
// =========================================================================
function hr_generate_employee_id($con) {
    mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_employee_id_seq (
        id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
        next_number INT UNSIGNED NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $seed = 1;
    $seed_row = mysqli_fetch_assoc(mysqli_query($con,
        "SELECT employee_id FROM hr_employees WHERE employee_id LIKE 'ABRA%'
         ORDER BY CAST(SUBSTRING(employee_id, 5) AS UNSIGNED) DESC LIMIT 1"));
    if ($seed_row && preg_match('/ABRA(\d+)/', $seed_row['employee_id'], $m)) {
        $seed = (int)$m[1] + 1;
    }
    mysqli_query($con, "INSERT IGNORE INTO hr_employee_id_seq (id, next_number) VALUES (1, $seed)");

    mysqli_begin_transaction($con);
    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT next_number FROM hr_employee_id_seq WHERE id = 1 FOR UPDATE"));
    $number = (int)$row['next_number'];

    // Stay ahead of any row inserted outside this function so an id already in use is never reissued.
    $max_row = mysqli_fetch_assoc(mysqli_query($con,
        "SELECT employee_id FROM hr_employees WHERE employee_id LIKE 'ABRA%'
         ORDER BY CAST(SUBSTRING(employee_id, 5) AS UNSIGNED) DESC LIMIT 1"));
    if ($max_row && preg_match('/ABRA(\d+)/', $max_row['employee_id'], $m2) && (int)$m2[1] >= $number) {
        $number = (int)$m2[1] + 1;
    }

    mysqli_query($con, "UPDATE hr_employee_id_seq SET next_number = " . ($number + 1) . " WHERE id = 1");
    mysqli_commit($con);

    return "ABRA" . str_pad($number, 3, "0", STR_PAD_LEFT);
}

// Safety net: guarantee the DB itself rejects a duplicate employee_id even in an unforeseen edge case.
function hr_ensure_employee_id_unique_index($con) {
    $idx = mysqli_query($con, "SHOW INDEX FROM hr_employees WHERE Key_name = 'uniq_employee_id'");
    if ($idx && mysqli_num_rows($idx) > 0) return;

    $dupe = mysqli_query($con,
        "SELECT employee_id FROM hr_employees WHERE employee_id IS NOT NULL AND employee_id != ''
         GROUP BY employee_id HAVING COUNT(*) > 1 LIMIT 1");
    if ($dupe && mysqli_num_rows($dupe) > 0) {
        error_log("hr_employees has duplicate employee_id values - resolve manually before a UNIQUE index can be added.");
        return;
    }

    mysqli_query($con, "ALTER TABLE hr_employees ADD UNIQUE KEY uniq_employee_id (employee_id)");
}
hr_ensure_employee_id_unique_index($con);

// =========================================================================
// STORE SIGNED OFFER LETTER INTO hr_employee_documents ON APPROVAL
// The offer letter is rendered on-demand (no static PDF on disk), so we
// store a document row pointing at its download link rather than a file copy.
// =========================================================================
function hr_store_signed_offer_letter_document($con, $token, $employee_id) {
    $safe_tok = mysqli_real_escape_string($con, $token);
    $link = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id FROM hr_onboarding_links WHERE token='$safe_tok' LIMIT 1"));
    if (!$link || empty($link['candidate_id'])) return;

    $cid = intval($link['candidate_id']);
    $offer = mysqli_fetch_assoc(mysqli_query($con, "SELECT token FROM hr_offer_letters WHERE candidate_id=$cid AND status='accepted' ORDER BY id DESC LIMIT 1"));
    if (!$offer || empty($offer['token'])) return;

    $eid = mysqli_real_escape_string($con, $employee_id);

    // Don't duplicate the row if this ever runs twice for the same employee.
    $exists = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employee_documents WHERE employee_id='$eid' AND document_type='Signed Offer Letter' LIMIT 1"));
    if ($exists) return;

    $base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
    $filepath = $base_url . '/hr-employee-offer.php?token=' . $offer['token'] . '&download=1';
    $fp_e = mysqli_real_escape_string($con, $filepath);

    mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath)
                       VALUES ('$eid', 'Signed Offer Letter', 'offer_letter.pdf', '$fp_e')");
}

isUser();

$current_page = basename($_SERVER['PHP_SELF']);
$current_user = $_SESSION['user_name'] ?? 'HR';

// =========================================================================
// AJAX: GET APPROVE DATA (NEW)
// =========================================================================
if (isset($_POST['ajax_get_approve_data'])) {
    header('Content-Type: application/json');
    $pending_id = intval($_POST['pending_id']);
    
    $p = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));
    if (!$p) { echo json_encode(['success'=>false,'message'=>'Record not found']); exit; }

    // Fetch dropdown data
    $depts = []; $res = mysqli_query($con, "SELECT name FROM hr_departments ORDER BY name ASC");
    while($row = mysqli_fetch_assoc($res)) $depts[] = $row['name'];

    $positions = []; $res = mysqli_query($con, "SELECT title FROM hr_positions ORDER BY title ASC");
    while($row = mysqli_fetch_assoc($res)) $positions[] = $row['title'];

    $emps = []; $res = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE status='Active' ORDER BY name ASC");
    while($row = mysqli_fetch_assoc($res)) $emps[] = $row;

    $locs = []; $res = mysqli_query($con, "SELECT location_name FROM hr_work_locations ORDER BY location_name ASC");
    while($row = mysqli_fetch_assoc($res)) $locs[] = $row['location_name'];

    $comps = []; $res = mysqli_query($con, "SELECT company_name FROM hr_companies ORDER BY company_name ASC");
    while($row = mysqli_fetch_assoc($res)) $comps[] = $row['company_name'];

    $timings = []; $res = mysqli_query($con, "SELECT start_time, end_time FROM hr_office_timings ORDER BY id ASC");
    while($row = mysqli_fetch_assoc($res)) $timings[] = $row['start_time'].' - '.$row['end_time'];

    echo json_encode([
        'success' => true,
        'data' => $p,
        'dropdowns' => [
            'departments' => $depts,
            'positions' => $positions,
            'employees' => $emps,
            'locations' => $locs,
            'companies' => $comps,
            'timings' => $timings
        ]
    ]);
    exit;
}

// =========================================================================
// AJAX: APPROVE EMPLOYEE
// =========================================================================
if (isset($_POST['ajax_approve'])) {
    header('Content-Type: application/json');
    $pending_id    = intval($_POST['pending_id']);
    $notify        = intval($_POST['notify_employee'] ?? 0);

    $pending = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));
    if (!$pending) { echo json_encode(['success'=>false,'message'=>'Record not found']); exit; }

    // Safely generate a unique Employee ID (locked counter, see hr_generate_employee_id above)
    $employee_id = hr_generate_employee_id($con);

    // Escape all fields
    $eid  = mysqli_real_escape_string($con, $employee_id);
    $f    = []; // sanitised fields
    $cols = ['name','gender','dob','blood_group','personal_email','phone','alt_phone','address',
             'country','state','aadhar_card','pan_number','contact_name','relationship',
             'contact_phone','contact_alt_phone','university_degree','year_completion',
             'percentage_cgpa','bank_account_number','ifsc_code','bank_branch','email',
             'hire_date','department','position','reporting_manager_1','reporting_manager_2',
             'salary','work_location','timings','company_name','employee_type'];
    foreach ($cols as $col) {
        $f[$col] = mysqli_real_escape_string($con, $pending[$col] ?? '');
    }

    // Insert into hr_employees
    $insert_sql = "INSERT INTO hr_employees (
        employee_id, name, gender, dob, blood_group, personal_email, phone, alt_phone,
        address, country, state, aadhar_card, pan_number, contact_name, relationship,
        contact_phone, contact_alt_phone, university_degree, year_completion, percentage_cgpa,
        bank_account_number, ifsc_code, bank_branch, email, hire_date, department, position,
        reporting_manager_1, reporting_manager_2, salary, work_location, timings, company_name,
        employee_type, status
    ) VALUES (
        '$eid', '{$f['name']}', '{$f['gender']}', '{$f['dob']}', '{$f['blood_group']}',
        '{$f['personal_email']}', '{$f['phone']}', '{$f['alt_phone']}', '{$f['address']}',
        '{$f['country']}', '{$f['state']}', '{$f['aadhar_card']}', '{$f['pan_number']}',
        '{$f['contact_name']}', '{$f['relationship']}', '{$f['contact_phone']}',
        '{$f['contact_alt_phone']}', '{$f['university_degree']}', '{$f['year_completion']}',
        '{$f['percentage_cgpa']}', '{$f['bank_account_number']}', '{$f['ifsc_code']}',
        '{$f['bank_branch']}', '{$f['email']}', '{$f['hire_date']}', '{$f['department']}',
        '{$f['position']}', '{$f['reporting_manager_1']}', '{$f['reporting_manager_2']}',
        '{$f['salary']}', '{$f['work_location']}', '{$f['timings']}', '{$f['company_name']}',
        '{$f['employee_type']}', 'Active'
    )";

    if (mysqli_query($con, $insert_sql)) {
        $inserted_id = mysqli_insert_id($con);

        // Move documents from onboarding folder to employee documents folder
        if (!empty($pending['documents_json'])) {
            $docs = json_decode($pending['documents_json'], true);
            if (is_array($docs)) {
                $doc_dir = __DIR__ . '/uploads/employee_documents/' . $employee_id . '/';
                if (!is_dir($doc_dir)) mkdir($doc_dir, 0777, true);
                foreach ($docs as $doc) {
                    $src  = __DIR__ . '/' . $doc['filepath'];
                    $ext  = pathinfo($doc['filename'], PATHINFO_EXTENSION);
                    $dest_filename = $employee_id . '_' . preg_replace('/[^a-zA-Z0-9]/', '_', $doc['type']) . '_' . time() . '.' . $ext;
                    $dest = $doc_dir . $dest_filename;
                    $rel  = 'uploads/employee_documents/' . $employee_id . '/' . $dest_filename;
                    if (file_exists($src)) rename($src, $dest);
                    $dt_e = mysqli_real_escape_string($con, $doc['type']);
                    $fn_e = mysqli_real_escape_string($con, $dest_filename);
                    $fp_e = mysqli_real_escape_string($con, $rel);
                    mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath)
                                       VALUES ('$eid', '$dt_e', '$fn_e', '$fp_e')");
                }
            }
        }

        // Store the signed offer letter alongside the employee's other documents
        hr_store_signed_offer_letter_document($con, $pending['token'], $employee_id);

        // Update pending record
        $safe_user = mysqli_real_escape_string($con, $current_user);
        mysqli_query($con, "UPDATE hr_employee_onboarding_pending SET status='approved', notify_employee=$notify,
                            reviewed_at=NOW(), reviewed_by='$safe_user' WHERE id=$pending_id");

        // Update onboarding link status
        $safe_tok = mysqli_real_escape_string($con, $pending['token']);
        mysqli_query($con, "UPDATE hr_onboarding_links SET status='approved' WHERE token='$safe_tok'");

        if ($notify == 1) {
            $to = $pending['email'] ?: $pending['personal_email'];
            if ($to) {
                $onb_company_id = getCompanyIdByOnboardingToken($con, $pending['token']);
                $subject = "Welcome to the Team! - Employee Profile Approved";
                $comp_name_row = $onb_company_id ? mysqli_fetch_assoc(mysqli_query($con, "SELECT company_name FROM hr_companies WHERE id=$onb_company_id LIMIT 1")) : null;
                $welcome_name = $comp_name_row['company_name'] ?? 'the team';
                $body = "Dear {$pending['name']},\n\nWe are pleased to inform you that your onboarding details have been successfully verified and approved. Your official Employee ID is {$employee_id}.\n\nWelcome to {$welcome_name}!\n\nBest Regards,\nHR Department";
                sendCompanyMail($con, $onb_company_id, $to, $subject, $body);
            }
        }

        echo json_encode(['success'=>true, 'employee_id'=>$employee_id]);
    } else {
        echo json_encode(['success'=>false, 'message'=>mysqli_error($con)]);
    }
    exit;
}

// =========================================================================
// AJAX: APPROVE CONFIRM (NEW LOGIC)
// =========================================================================
if (isset($_POST['ajax_approve_confirm'])) {
    header('Content-Type: application/json');
    $pending_id = intval($_POST['pending_id']);
    $notify = intval($_POST['notify_employee'] ?? 0);

    // Official data coming from HR Modal
    $official = [
        'email' => mysqli_real_escape_string($con, trim($_POST['email'] ?? '')),
        'hire_date' => mysqli_real_escape_string($con, trim($_POST['hire_date'] ?? '')),
        'department' => mysqli_real_escape_string($con, trim($_POST['department'] ?? '')),
        'position' => mysqli_real_escape_string($con, trim($_POST['position'] ?? '')),
        'employee_type' => mysqli_real_escape_string($con, trim($_POST['employee_type'] ?? '')),
        'reporting_manager_1' => mysqli_real_escape_string($con, trim($_POST['reporting_manager_1'] ?? '')),
        'reporting_manager_2' => mysqli_real_escape_string($con, trim($_POST['reporting_manager_2'] ?? '')),
        'salary' => mysqli_real_escape_string($con, trim($_POST['salary'] ?? '0')),
        'work_location' => mysqli_real_escape_string($con, trim($_POST['work_location'] ?? '')),
        'company_name' => mysqli_real_escape_string($con, trim($_POST['company_name'] ?? '')),
        'timings' => mysqli_real_escape_string($con, trim($_POST['timings'] ?? ''))
    ];

    $pending = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));
    if (!$pending) { echo json_encode(['success'=>false,'message'=>'Record not found']); exit; }

    // Safely generate a unique Employee ID (locked counter, see hr_generate_employee_id above)
    $employee_id = hr_generate_employee_id($con);

    $eid = mysqli_real_escape_string($con, $employee_id);
    
    // Base Candidate Data (already in DB)
    $f = [];
    $cols = ['name','gender','dob','blood_group','personal_email','phone','alt_phone','address',
             'country','state','aadhar_card','pan_number','contact_name','relationship',
             'contact_phone','contact_alt_phone','university_degree','year_completion','percentage_cgpa',
             'bank_account_number','ifsc_code','bank_branch'];
    foreach ($cols as $col) {
        $f[$col] = mysqli_real_escape_string($con, $pending[$col] ?? '');
    }

    // Merge Official Data
    foreach ($official as $key => $val) {
        $f[$key] = $val;
    }

    $insert_sql = "INSERT INTO hr_employees (
        employee_id, name, gender, dob, blood_group, personal_email, phone, alt_phone,
        address, country, state, aadhar_card, pan_number, contact_name, relationship,
        contact_phone, contact_alt_phone, university_degree, year_completion, percentage_cgpa,
        bank_account_number, ifsc_code, bank_branch, email, hire_date, department, position,
        reporting_manager_1, reporting_manager_2, salary, work_location, timings, company_name,
        employee_type, status
    ) VALUES (
        '$eid', '{$f['name']}', '{$f['gender']}', '{$f['dob']}', '{$f['blood_group']}',
        '{$f['personal_email']}', '{$f['phone']}', '{$f['alt_phone']}', '{$f['address']}',
        '{$f['country']}', '{$f['state']}', '{$f['aadhar_card']}', '{$f['pan_number']}',
        '{$f['contact_name']}', '{$f['relationship']}', '{$f['contact_phone']}',
        '{$f['contact_alt_phone']}', '{$f['university_degree']}', '{$f['year_completion']}',
        '{$f['percentage_cgpa']}', '{$f['bank_account_number']}', '{$f['ifsc_code']}',
        '{$f['bank_branch']}', '{$f['email']}', '{$f['hire_date']}', '{$f['department']}',
        '{$f['position']}', '{$f['reporting_manager_1']}', '{$f['reporting_manager_2']}',
        '{$f['salary']}', '{$f['work_location']}', '{$f['timings']}', '{$f['company_name']}',
        '{$f['employee_type']}', 'Active'
    )";

    if (mysqli_query($con, $insert_sql)) {
        
        // Move Documents
        if (!empty($pending['documents_json'])) {
            $docs = json_decode($pending['documents_json'], true);
            if (is_array($docs)) {
                $doc_dir = __DIR__ . '/uploads/employee_documents/' . $employee_id . '/';
                if (!is_dir($doc_dir)) mkdir($doc_dir, 0777, true);
                foreach ($docs as $doc) {
                    $src = __DIR__ . '/' . $doc['filepath'];
                    $ext = pathinfo($doc['filename'], PATHINFO_EXTENSION);
                    $dest_filename = $employee_id . '_' . preg_replace('/[^a-zA-Z0-9]/', '_', $doc['type']) . '_' . time() . '.' . $ext;
                    $dest = $doc_dir . $dest_filename;
                    $rel = 'uploads/employee_documents/' . $employee_id . '/' . $dest_filename;
                    if (file_exists($src)) rename($src, $dest);
                    
                    $dt_e = mysqli_real_escape_string($con, $doc['type']);
                    $fn_e = mysqli_real_escape_string($con, $dest_filename);
                    $fp_e = mysqli_real_escape_string($con, $rel);
                    mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath) VALUES ('$eid', '$dt_e', '$fn_e', '$fp_e')");
                }
            }
        }

        // Store the signed offer letter alongside the employee's other documents
        hr_store_signed_offer_letter_document($con, $pending['token'], $employee_id);

        // Update pending & link records
        $safe_user = mysqli_real_escape_string($con, $current_user);
        mysqli_query($con, "UPDATE hr_employee_onboarding_pending SET status='approved', notify_employee=$notify, reviewed_at=NOW(), reviewed_by='$safe_user' WHERE id=$pending_id");
        
        $safe_tok = mysqli_real_escape_string($con, $pending['token']);
        mysqli_query($con, "UPDATE hr_onboarding_links SET status='approved' WHERE token='$safe_tok'");

        // Send Notification
        if ($notify == 1) {
            $to = $f['email'] ?: $f['personal_email'];
            if ($to) {
                $onb_company_id = getCompanyIdByOnboardingToken($con, $pending['token']);
                $comp_name_row = $onb_company_id ? mysqli_fetch_assoc(mysqli_query($con, "SELECT company_name FROM hr_companies WHERE id=$onb_company_id LIMIT 1")) : null;
                $welcome_name = $comp_name_row['company_name'] ?? 'the team';
                $subject = "Welcome to the Team! - Employee Profile Approved";
                $body = "Dear {$f['name']},\n\nWe are pleased to inform you that your onboarding details have been successfully verified and approved. Your official Employee ID is {$employee_id}.\n\nWelcome to {$welcome_name}!\n\nBest Regards,\nHR Department";
                sendCompanyMail($con, $onb_company_id, $to, $subject, $body);
            }
        }
        echo json_encode(['success'=>true, 'employee_id'=>$employee_id]);
    } else {
        echo json_encode(['success'=>false, 'message'=>mysqli_error($con)]);
    }
    exit;
}

// =========================================================================
// AJAX: DECLINE EMPLOYEE
// =========================================================================
if (isset($_POST['ajax_decline'])) {
    header('Content-Type: application/json');
    $pending_id    = intval($_POST['pending_id']);
    $reason        = mysqli_real_escape_string($con, trim($_POST['decline_reason'] ?? ''));
    $allow_resubmit= intval($_POST['allow_resubmit'] ?? 0);
    $notify        = intval($_POST['notify_employee'] ?? 0);
    $safe_user     = mysqli_real_escape_string($con, $current_user);

    $new_status = $allow_resubmit ? 'resubmit' : 'declined';

    // Get token first
    $pend = mysqli_fetch_assoc(mysqli_query($con, "SELECT token FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));

    mysqli_query($con, "UPDATE hr_employee_onboarding_pending SET
        status='$new_status', decline_reason='$reason', allow_resubmit=$allow_resubmit,
        notify_employee=$notify, reviewed_at=NOW(), reviewed_by='$safe_user'
        WHERE id=$pending_id");

    if ($pend) {
        $safe_tok = mysqli_real_escape_string($con, $pend['token']);
        $link_status = $allow_resubmit ? 'pending' : 'declined';
        mysqli_query($con, "UPDATE hr_onboarding_links SET status='$link_status' WHERE token='$safe_tok'");
        
        if ($notify == 1) {
            $full_pend = mysqli_fetch_assoc(mysqli_query($con, "SELECT name, email, personal_email FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));
            $to = $full_pend['email'] ?: $full_pend['personal_email'];
            if ($to) {
                $onb_company_id = getCompanyIdByOnboardingToken($con, $pend['token']);

                if ($allow_resubmit) {
                    $base_url = (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
                    $link_url = $base_url . '/hr-employee-onboarding.php?token=' . $pend['token'];
                    $subject = "Action Required: Update Your Onboarding Details";
                    $body = "Dear {$full_pend['name']},\n\nWe have reviewed your onboarding submission. However, we need you to update some information before we can proceed.\n\nReason: " . strip_tags($reason) . "\n\nPlease click the secure link below to update and resubmit your details:\n{$link_url}\n\nBest Regards,\nHR Department";
                } else {
                    $subject = "Update regarding your Onboarding Application";
                    $body = "Dear {$full_pend['name']},\n\nThank you for submitting your onboarding details. Unfortunately, your submission has been declined.\n\nReason: " . strip_tags($reason) . "\n\nIf you have any questions, please contact the HR department.\n\nBest Regards,\nHR Department";
                }
                sendCompanyMail($con, $onb_company_id, $to, $subject, $body);
            }
        }
    }

    echo json_encode(['success'=>true]);
    exit;
}

// =========================================================================
// AJAX: DELETE SUBMISSION
// =========================================================================
if (isset($_POST['ajax_delete_submission'])) {
    header('Content-Type: application/json');
    $pending_id = intval($_POST['pending_id']);
    
    // Check if exists
    $pending = mysqli_fetch_assoc(mysqli_query($con, "SELECT token FROM hr_employee_onboarding_pending WHERE id=$pending_id LIMIT 1"));
    if ($pending) {
        $safe_tok = mysqli_real_escape_string($con, $pending['token']);
        mysqli_query($con, "DELETE FROM hr_employee_onboarding_pending WHERE id=$pending_id");
        mysqli_query($con, "UPDATE hr_onboarding_links SET status='expired' WHERE token='$safe_tok'");
    }
    
    echo json_encode(['success'=>true]);
    exit;
}

// =========================================================================
// AJAX: VIEW FULL DETAILS
// =========================================================================
if (isset($_GET['ajax_view'])) {
    $pid = intval($_GET['id']);
    $p   = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending WHERE id=$pid LIMIT 1"));
    if (!$p) { echo '<p style="color:red;padding:20px;">Not found.</p>'; exit; }

    $docs = !empty($p['documents_json']) ? json_decode($p['documents_json'], true) : [];
    if (!is_array($docs)) $docs = [];

    // Fetch DV docs dynamically for backward compatibility / viewing
    $link_data = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_id FROM hr_onboarding_links WHERE token='{$p['token']}' LIMIT 1"));
    if ($link_data && !empty($link_data['candidate_id'])) {
        $cid_dv = intval($link_data['candidate_id']);
        $dv_req_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_dv_requests WHERE candidate_id=$cid_dv ORDER BY id DESC LIMIT 1"));
        if ($dv_req_row) {
            $dv_res = mysqli_query($con, "SELECT document_name, file_name, file_path FROM hr_dv_documents WHERE request_id={$dv_req_row['id']} AND file_path IS NOT NULL AND file_path != '' ORDER BY id ASC");
            $existing_types = array_column($docs, 'type');
            while ($dv_row = mysqli_fetch_assoc($dv_res)) {
                if (!in_array($dv_row['document_name'], $existing_types)) {
                    $docs[] = [
                        'type' => $dv_row['document_name'],
                        'filename' => $dv_row['file_name'],
                        'filepath' => $dv_row['file_path']
                    ];
                    $existing_types[] = $dv_row['document_name'];
                }
            }
        }
    }

    // Fetch Signed Offer Letter (if exists)
    if (isset($link_data) && !empty($link_data['candidate_id'])) {
        $cid_offer = intval($link_data['candidate_id']);
        $offer_row = mysqli_fetch_assoc(mysqli_query($con, 
            "SELECT token FROM hr_offer_letters WHERE candidate_id=$cid_offer AND status='accepted' ORDER BY id DESC LIMIT 1"));
        if ($offer_row && !empty($offer_row['token'])) {
            $offer_base_url   = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
            $offer_script_dir = '/hrm';
            $docs[] = [
                'type'         => 'Signed Offer Letter',
                'filename'     => 'offer_letter.pdf',
                'filepath'     => $offer_base_url . $offer_script_dir . '/hr-employee-offer.php?token=' . $offer_row['token'] . '&download=1',
                'display_only' => true
            ];
        }
    }

    $status_colors = [
        'pending'  => ['bg'=>'#fef9c3','color'=>'#713f12','label'=>'Pending Review'],
        'approved' => ['bg'=>'#dcfce7','color'=>'#065f46','label'=>'Approved'],
        'declined' => ['bg'=>'#fee2e2','color'=>'#991b1b','label'=>'Declined'],
        'resubmit' => ['bg'=>'#fff7ed','color'=>'#92400e','label'=>'Resubmit Required'],
    ];
    $sc = $status_colors[$p['status']] ?? $status_colors['pending'];

    $fields = [
        'Official Info' => [
            'Official Email' => $p['email'],
            'Department'     => $p['department'],
            'Position'       => $p['position'],
            'Employee Type'  => $p['employee_type'],
            'Salary'         => $p['salary'] ? '₹' . number_format($p['salary'], 2) : '-',
            'Work Location'  => $p['work_location'],
            'Timings'        => $p['timings'],
            'Company'        => $p['company_name'],
            'Join Date'      => $p['hire_date'] ? date('d M Y', strtotime($p['hire_date'])) : '-',
        ],
        'Personal Info' => [
            'Full Name'      => $p['name'],
            'Gender'         => $p['gender'],
            'Date of Birth'  => $p['dob'] ? date('d M Y', strtotime($p['dob'])) : '-',
            'Blood Group'    => $p['blood_group'],
            'Mobile'         => $p['phone'],
            'Alt Phone'      => $p['alt_phone'],
            'Personal Email' => $p['personal_email'],
            'Country'        => $p['country'],
            'State'          => $p['state'],
            'Address'        => $p['address'],
        ],
        'Identity Documents' => [
            'Aadhar Card'    => $p['aadhar_card'],
            'PAN Number'     => $p['pan_number'],
        ],
        'Emergency Contact' => [
            'Contact Name'   => $p['contact_name'],
            'Relationship'   => $p['relationship'],
            'Phone'          => $p['contact_phone'],
            'Alt Phone'      => $p['contact_alt_phone'],
        ],
        'Education' => [
            'Degree'         => $p['university_degree'],
            'Year'           => $p['year_completion'],
            'Percentage/CGPA'=> $p['percentage_cgpa'],
        ],
        'Bank Details' => [
            'Account Number' => $p['bank_account_number'],
            'IFSC Code'      => $p['ifsc_code'],
            'Branch'         => $p['bank_branch'],
        ],
    ];
    ?>
    <div style="font-family:'Poppins',sans-serif;">
      <!-- Status Banner -->
      <div style="background:<?php echo $sc['bg']; ?>;color:<?php echo $sc['color']; ?>;
                  padding:14px 20px;border-radius:10px;margin-bottom:20px;
                  display:flex;align-items:center;justify-content:space-between;">
        <div>
          <strong style="font-size:15px;"><?php echo $sc['label']; ?></strong>
          <?php if ($p['status'] == 'declined' || $p['status'] == 'resubmit'): ?>
            <div style="font-size:13px;margin-top:4px;">
              <strong>Reason:</strong> <?php echo htmlspecialchars($p['decline_reason'] ?? 'N/A'); ?>
            </div>
          <?php endif; ?>
        </div>
        <div style="font-size:12px;opacity:.8;">
          Submitted: <?php echo date('d M Y, h:i A', strtotime($p['submitted_at'])); ?>
          <?php if ($p['reviewed_at']): ?>
            <br>Reviewed by <?php echo htmlspecialchars($p['reviewed_by']); ?>
            on <?php echo date('d M Y, h:i A', strtotime($p['reviewed_at'])); ?>
          <?php endif; ?>
        </div>
      </div>

      <?php foreach ($fields as $section => $flds): ?>
      <div style="margin-bottom:20px;">
        <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#1e3a8a;
                    border-bottom:2px solid #e0e7ff;padding-bottom:8px;margin-bottom:12px;">
          <?php echo $section; ?>
        </div>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;">
          <?php foreach ($flds as $label => $val): ?>
          <div style="background:#f8fafc;border-radius:8px;padding:12px;border:1px solid #e2e8f0;">
            <div style="font-size:10px;font-weight:700;color:#64748b;text-transform:uppercase;margin-bottom:3px;">
              <?php echo $label; ?>
            </div>
            <div style="font-weight:700;color:#1e293b;font-size:13px;">
              <?php echo htmlspecialchars($val ?: '—'); ?>
            </div>
          </div>
          <?php endforeach; ?>
        </div>
      </div>
      <?php endforeach; ?>

      <!-- Documents -->
      <?php if (!empty($docs)): ?>
      <div style="margin-bottom:20px;">
        <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#1e3a8a;
                    border-bottom:2px solid #e0e7ff;padding-bottom:8px;margin-bottom:12px;">
          Uploaded Documents (<?php echo count($docs); ?>)
        </div>
        <div style="display:flex;flex-wrap:wrap;gap:10px;">
          <?php foreach ($docs as $doc): ?>
          <a href="<?php echo htmlspecialchars($doc['filepath']); ?>" target="_blank"
             style="display:inline-flex;align-items:center;gap:8px;padding:10px 16px;
                    background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;
                    color:#1e40af;font-weight:700;font-size:13px;text-decoration:none;">
            <i class="fas fa-file"></i> <?php echo htmlspecialchars($doc['type']); ?>
          </a>
          <?php endforeach; ?>
        </div>
      </div>
      <?php endif; ?>

      <!-- Action Buttons (only for pending / resubmit status) -->
      <?php if ($p['status'] == 'pending' || $p['status'] == 'resubmit'): ?>
      <div style="display:flex;gap:12px;margin-top:20px;padding-top:20px;border-top:2px solid #f1f5f9;">
        <button onclick="openApprove(<?php echo $pid; ?>, '<?php echo addslashes(htmlspecialchars($p['name'])); ?>')"
                style="flex:1;padding:14px;border:none;border-radius:10px;
                       background:linear-gradient(135deg,#10b981,#059669);color:#fff;
                       font-family:'Poppins',sans-serif;font-weight:700;font-size:14px;cursor:pointer;">
          <i class="fas fa-check-circle"></i> Approve & Add to Employee List
        </button>
        <button onclick="openDecline(<?php echo $pid; ?>, '<?php echo addslashes(htmlspecialchars($p['name'])); ?>')"
                style="flex:1;padding:14px;border:none;border-radius:10px;
                       background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;
                       font-family:'Poppins',sans-serif;font-weight:700;font-size:14px;cursor:pointer;">
          <i class="fas fa-times-circle"></i> Decline
        </button>
      </div>
      <?php endif; ?>
    </div>
    <?php
    exit;
}

// =========================================================================
// GENERATE ONBOARDING LINK (called from this page too)
// =========================================================================
if (isset($_POST['ajax_generate_onboarding_link'])) {
    header('Content-Type: application/json');
    $candidate_id    = intval($_POST['candidate_id']);
    $candidate_name  = mysqli_real_escape_string($con, $_POST['candidate_name'] ?? '');
    $candidate_email = mysqli_real_escape_string($con, $_POST['candidate_email'] ?? '');
    $joining_date    = mysqli_real_escape_string($con, $_POST['joining_date'] ?? '');
    $expiry_hours    = intval($_POST['expiry_hours'] ?? 72);
    $created_by      = mysqli_real_escape_string($con, $current_user);

    // Ensure table exists
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

    // Delete existing link if any
    mysqli_query($con, "DELETE FROM hr_onboarding_links WHERE candidate_id=$candidate_id");

    $token       = bin2hex(random_bytes(32));
    $expiry_sql  = $expiry_hours > 0 ? "'" . date('Y-m-d H:i:s', strtotime("+{$expiry_hours} hours")) . "'" : "NULL";
    $joining_date_sql = empty($joining_date) ? "NULL" : "'$joining_date'";

    mysqli_query($con, "INSERT INTO hr_onboarding_links
        (candidate_id, token, candidate_name, candidate_email, joining_date, status, expiry_at, created_by)
        VALUES ($candidate_id, '$token', '$candidate_name', '$candidate_email', $joining_date_sql, 'pending', $expiry_sql, '$created_by')");

    $base_url = (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
    $link_url = $base_url . '/hr-employee-onboarding.php?token=' . $token;

    echo json_encode(['success'=>true, 'link'=>$link_url, 'token'=>$token]);
    exit;
}

// =========================================================================
// SEND ONBOARDING EMAIL
// =========================================================================
if (isset($_POST['ajax_send_onboarding_email'])) {
    header('Content-Type: application/json');
    $to      = filter_var($_POST['to'] ?? '', FILTER_SANITIZE_EMAIL);
    $subject = strip_tags($_POST['subject'] ?? 'Onboarding Process');
    $body_text = strip_tags($_POST['body'] ?? '');

    if (empty($to) || empty($subject) || empty($body_text)) { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success' => false, 'message' => 'Missing email fields.']);
        exit;
    }

    // The onboarding link carries the token as a query param — pull it out to
    // resolve which company this candidate belongs to.
    $onb_token = '';
    $link_param = $_POST['link'] ?? '';
    if ($link_param) {
        $qs = parse_url($link_param, PHP_URL_QUERY);
        if ($qs) { parse_str($qs, $qs_parts); $onb_token = $qs_parts['token'] ?? ''; }
    }
    $onb_company_id = $onb_token ? getCompanyIdByOnboardingToken($con, $onb_token) : 0;

    $result = sendCompanyMail($con, $onb_company_id, $to, $subject, $body_text); if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode($result);
    exit;
}

// =========================================================================
// FETCH ALL PENDING SUBMISSIONS
// =========================================================================
$filter_status = $_GET['status'] ?? '';
$where = '';
if ($filter_status && in_array($filter_status, ['pending','approved','declined','resubmit'])) {
    $where = "WHERE status = '$filter_status'";
}
$all_pending = mysqli_query($con, "SELECT * FROM hr_employee_onboarding_pending $where ORDER BY submitted_at DESC");

// Stats
$stats = mysqli_fetch_assoc(mysqli_query($con, "SELECT
    COUNT(*) as total,
    SUM(status='pending') as pending,
    SUM(status='approved') as approved,
    SUM(status='declined') as declined,
    SUM(status='resubmit') as resubmit
    FROM hr_employee_onboarding_pending"));

// Fetch Hired Candidates for Link Generation
$hired_candidates = [];
$hc_query = mysqli_query($con, "SELECT * FROM hr_screenings WHERE hr_decision='Hired' ORDER BY candidate_name ASC");
if ($hc_query) {
    while ($row = mysqli_fetch_assoc($hc_query)) {
        $hired_candidates[] = $row;
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Onboarding Pending List</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:20px 0; }
    .container-fluid { max-width:1500px; margin:0 auto; padding:0 20px; }

    /* Header */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 10px;
      box-shadow: 0 4px 15px rgba(30,58,138,0.3);
      margin-bottom: 20px;
      display: flex; justify-content: space-between; align-items: center;
    }
    .page-header h1 { color:white; font-weight:700; margin:0; font-size:1.6rem; }

    .btn-back {
      background: rgba(255,255,255,0.2); color:white; padding:10px 20px;
      border-radius:8px; text-decoration:none; font-weight:600;
      display:inline-flex; align-items:center; gap:8px; transition:all 0.3s;
    }
    .btn-back:hover { background:rgba(255,255,255,0.3); color:white; text-decoration:none; }

    /* Navigation Tabs */
    .nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; flex-wrap: wrap; }
    .nav-btn {
        padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
        font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
        display: flex; align-items: center; gap: 8px; border: 2px solid transparent; transition: all 0.3s;
    }
    .nav-btn:hover { text-decoration: none; color: #1e3a8a; }
    .nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

    /* Stats */
    .stats-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:15px; margin-bottom:20px; }
    .stat-card {
      background:white; border-radius:10px; padding:20px;
      box-shadow:0 2px 8px rgba(0,0,0,0.06); text-align:center;
      border-top:4px solid #e2e8f0; cursor:pointer; transition:all 0.3s;
    }
    .stat-card:hover { transform:translateY(-3px); box-shadow:0 6px 20px rgba(0,0,0,0.1); }
    .stat-card.active { border-color:current; }
    .stat-card .num  { font-size:2rem; font-weight:800; }
    .stat-card .lbl  { font-size:12px; font-weight:600; color:#64748b; margin-top:4px; text-transform:uppercase; }
    .stat-total   { border-color:#1e3a8a; }  .stat-total .num   { color:#1e3a8a; }
    .stat-pending { border-color:#f59e0b; }  .stat-pending .num { color:#f59e0b; }
    .stat-approved{ border-color:#10b981; }  .stat-approved .num{ color:#10b981; }
    .stat-declined{ border-color:#ef4444; }  .stat-declined .num{ color:#ef4444; }
    .stat-resubmit{ border-color:#8b5cf6; }  .stat-resubmit .num{ color:#8b5cf6; }

    /* Filter bar */
    .filter-bar {
      background:white; padding:18px 22px; border-radius:10px;
      box-shadow:0 2px 8px rgba(0,0,0,0.06); margin-bottom:20px;
      display:flex; align-items:center; gap:15px; flex-wrap:wrap;
    }
    .filter-bar input, .filter-bar select {
      border:2px solid #e2e8f0; border-radius:8px;
      padding:10px 14px; font-size:14px; font-family:'Poppins',sans-serif;
      font-weight:500; transition:all 0.3s;
    }
    .filter-bar input:focus, .filter-bar select:focus {
      outline:none; border-color:#1e3a8a;
    }

    /* Table */
    .table-wrap { background:white; border-radius:10px; box-shadow:0 2px 8px rgba(0,0,0,0.06); overflow-x:auto; overflow-y:hidden; }
    .table-wrap table { width:100%; border-collapse:collapse; }
    .table-wrap thead th {
      background:linear-gradient(135deg,#1e3a8a,#1e40af);
      color:white; font-weight:700; padding:14px 16px;
      font-size:12px; text-transform:uppercase; white-space:nowrap;
    }
    .table-wrap tbody td {
      padding:14px 16px; border-bottom:1px solid #f1f5f9;
      font-size:13px; font-weight:600; vertical-align:middle; color:#1e293b;
    }
    .table-wrap tbody tr:hover { background:#f8fafc; }

    /* Badges */
    .badge-status {
      padding:5px 14px; border-radius:20px; font-weight:700;
      font-size:11px; text-transform:uppercase; white-space:nowrap; display:inline-block;
    }
    .bs-pending  { background:#fef9c3; color:#713f12; }
    .bs-approved { background:#dcfce7; color:#065f46; }
    .bs-declined { background:#fee2e2; color:#991b1b; }
    .bs-resubmit { background:#ede9fe; color:#5b21b6; }

    /* Action buttons */
    .act-btn {
      display:inline-flex; align-items:center; justify-content:center;
      width:34px; height:34px; border-radius:8px; cursor:pointer;
      border:none; font-size:13px; transition:all 0.3s; text-decoration:none;
    }
    .act-btn:hover { transform:scale(1.1); text-decoration:none; }
    .act-view     { background:#eff6ff; color:#1e40af; }
    .act-approve  { background:#f0fdf4; color:#059669; }
    .act-decline  { background:#fef2f2; color:#dc2626; }
    .act-notify   { background:#fff7ed; color:#ea580c; }
    .act-delete   { background:#fef2f2; color:#b91c1c; }

    /* Modal */
    .modal-content { border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,0.2); }
    .modal-header  { background:linear-gradient(135deg,#1e3a8a,#1e40af); color:white; border-radius:14px 14px 0 0; padding:18px 25px; }
    .modal-header h5 { color:white; font-weight:700; margin:0; }
    .modal-header .close { color:white; opacity:0.85; font-size:24px; }
    .modal-body  { padding:25px; max-height:80vh; overflow-y:auto; }

    /* Form controls in modal */
    .modal-fc {
      border:2px solid #e2e8f0; border-radius:8px;
      padding:10px 14px; font-size:14px; font-family:'Poppins',sans-serif;
      font-weight:500; width:100%; transition:all 0.3s; margin-bottom:12px;
    }
    .modal-fc:focus { outline:none; border-color:#1e3a8a; }

    .option-row {
      background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px;
      padding:16px; margin-bottom:12px;
    }
    .option-row label { display:flex; align-items:center; gap:10px; cursor:pointer; font-weight:600; }
    .option-row input[type=radio] { width:18px; height:18px; accent-color:#1e3a8a; }

    .btn-approve-final {
      width:100%; padding:14px; border:none; border-radius:10px;
      background:linear-gradient(135deg,#10b981,#059669); color:white;
      font-family:'Poppins',sans-serif; font-weight:700; font-size:15px;
      cursor:pointer; transition:all 0.3s;
    }
    .btn-approve-final:hover { transform:translateY(-2px); box-shadow:0 6px 20px rgba(16,185,129,0.3); }

    .btn-decline-final {
      width:100%; padding:14px; border:none; border-radius:10px;
      background:linear-gradient(135deg,#ef4444,#dc2626); color:white;
      font-family:'Poppins',sans-serif; font-weight:700; font-size:15px;
      cursor:pointer; transition:all 0.3s;
    }
    .btn-decline-final:hover { transform:translateY(-2px); box-shadow:0 6px 20px rgba(239,68,68,0.3)); }

    /* Alert */
    .alert-container { position:fixed; top:20px; right:20px; z-index:9999; min-width:300px; }

    /* Generate Link Section */
    .link-gen-box {
      background:#f0f9ff; border:2px solid #bae6fd; border-radius:12px;
      padding:20px; margin-bottom:20px;
    }
    .link-gen-box h5 { color:#0369a1; font-weight:700; margin-bottom:15px; }

    .empty-state {
      text-align:center; padding:60px 20px; color:#64748b;
    }
    .empty-state i { font-size:64px; opacity:0.3; margin-bottom:20px; display:block; }

    .spinner { border:3px solid #f3f3f3; border-top:3px solid #1e3a8a; border-radius:50%; width:40px; height:40px; animation:spin 0.8s linear infinite; margin:30px auto; }
    @keyframes spin { 0%{ transform:rotate(0deg); } 100%{ transform:rotate(360deg); } }
  </style>
</head>
<body>

<!-- Alert Container -->
<div class="alert-container" id="alertContainer"></div>

<div class="container-fluid">

  <!-- Header -->
  <div class="page-header">
    <h1><i class="fas fa-user-clock mr-2"></i> Employee Onboarding — Pending Approvals</h1>

    <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;flex:1;justify-content:flex-end;">
      <?php
      $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek']);
      $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
      ?>
      
      <button onclick="$('#generateLinkModal').modal('show')"
              style="background:linear-gradient(135deg,#10b981,#059669);color:white;border:none;
                     padding:10px 20px;border-radius:8px;font-family:'Poppins',sans-serif;
                     font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:8px;">
        <i class="fas fa-link"></i> Generate Onboarding Link
      </button>
      <a href="hr-employees-list.php" class="btn-back">
        <i class="fas fa-users"></i> Employee List
      </a>
    </div>
  </div>

  <!-- NAVIGATION TABS -->
  <div class="nav-tabs-container">
      <a href="hr-employee-onboarding-pending-list.php" class="nav-btn active">
          <i class="fas fa-user-plus"></i> Onboarding
      </a>
      <a href="hr-checklist-employee.php" class="nav-btn">
          <i class="fas fa-tasks"></i> Internal Checklist
      </a>
      <a href="hr-checklist.php" class="nav-btn">
          <i class="fas fa-clipboard-check"></i> Employee Checklist
      </a>
  </div>

  <!-- Stats -->
  <div class="stats-row">
    <div class="stat-card stat-total" onclick="filterByStatus('')">
      <div class="num"><?php echo $stats['total'] ?? 0; ?></div>
      <div class="lbl">Total Submissions</div>
    </div>
    <div class="stat-card stat-pending" onclick="filterByStatus('pending')">
      <div class="num"><?php echo $stats['pending'] ?? 0; ?></div>
      <div class="lbl">Pending Review</div>
    </div>
    <div class="stat-card stat-approved" onclick="filterByStatus('approved')">
      <div class="num"><?php echo $stats['approved'] ?? 0; ?></div>
      <div class="lbl">Approved</div>
    </div>
    <div class="stat-card stat-declined" onclick="filterByStatus('declined')">
      <div class="num"><?php echo $stats['declined'] ?? 0; ?></div>
      <div class="lbl">Declined</div>
    </div>
    <div class="stat-card stat-resubmit" onclick="filterByStatus('resubmit')">
      <div class="num"><?php echo $stats['resubmit'] ?? 0; ?></div>
      <div class="lbl">Resubmit Required</div>
    </div>
  </div>

  <!-- Filter Bar -->
  <div class="filter-bar">
    <input type="text" id="searchInput" placeholder="🔍 Search by name, email, department..."
           style="flex:1; min-width:250px;" onkeyup="filterTable()">
    <select id="statusFilter" onchange="filterTable()" style="min-width:160px;">
      <option value="">All Status</option>
      <option value="pending" <?php echo ($filter_status=='pending')?'selected':''; ?>>Pending</option>
      <option value="approved" <?php echo ($filter_status=='approved')?'selected':''; ?>>Approved</option>
      <option value="declined" <?php echo ($filter_status=='declined')?'selected':''; ?>>Declined</option>
      <option value="resubmit" <?php echo ($filter_status=='resubmit')?'selected':''; ?>>Resubmit</option>
    </select>
    <button onclick="filterByStatus('')"
            style="padding:10px 18px;background:#ef4444;color:white;border:none;border-radius:8px;
                   font-family:'Poppins',sans-serif;font-weight:600;cursor:pointer;">
      <i class="fas fa-redo"></i> Reset
    </button>
  </div>

  <!-- Table -->
  <div class="table-wrap">
    <table id="pendingTable">
      <thead>
        <tr>
          <th>#</th>
          <th>Candidate Name</th>
          <th>Department</th>
          <th>Position</th>
          <th>Email</th>
          <th>Phone</th>
          <th>Submitted On</th>
          <th>Status</th>
          <th>Reviewed By</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody id="tableBody">
        <?php
        $sno = 1;
        if (mysqli_num_rows($all_pending) == 0):
        ?>
        <tr>
          <td colspan="10">
            <div class="empty-state">
              <i class="fas fa-inbox"></i>
              <h5 style="font-weight:700; color:#1e293b;">No Submissions Yet</h5>
              <p>No onboarding submissions found. Generate a link and share with new employees.</p>
            </div>
          </td>
        </tr>
        <?php else: while ($row = mysqli_fetch_assoc($all_pending)): ?>
        <tr data-name="<?php echo strtolower(htmlspecialchars($row['name'].' '.$row['email'].' '.$row['department'])); ?>"
            data-status="<?php echo $row['status']; ?>">
          <td><?php echo $sno++; ?></td>
          <td>
            <div style="font-weight:700;"><?php echo htmlspecialchars($row['name'] ?? $row['candidate_name'] ?? '—'); ?></div>
            <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($row['candidate_name'] ?? ''); ?></div>
          </td>
          <td><?php echo htmlspecialchars($row['department'] ?? '—'); ?></td>
          <td><?php echo htmlspecialchars($row['position'] ?? '—'); ?></td>
          <td><?php echo htmlspecialchars($row['email'] ?? '—'); ?></td>
          <td><?php echo htmlspecialchars($row['phone'] ?? '—'); ?></td>
          <td style="white-space:nowrap;"><?php echo date('d M Y, h:i A', strtotime($row['submitted_at'])); ?></td>
          <td>
            <?php
            $bs = ['pending'=>'bs-pending','approved'=>'bs-approved','declined'=>'bs-declined','resubmit'=>'bs-resubmit'];
            $bl = ['pending'=>'⏳ Pending','approved'=>'✅ Approved','declined'=>'❌ Declined','resubmit'=>'🔄 Resubmit'];
            $bclass = $bs[$row['status']] ?? 'bs-pending';
            $blabel = $bl[$row['status']] ?? ucfirst($row['status']);
            ?>
            <span class="badge-status <?php echo $bclass; ?>"><?php echo $blabel; ?></span>
            <?php if ($row['status'] == 'approved' && $row['reviewed_by']): ?>
              <div style="font-size:10px;color:#64748b;margin-top:3px;">→ Added to Employee List</div>
            <?php endif; ?>
            <?php if (($row['status'] == 'declined' || $row['status'] == 'resubmit') && $row['decline_reason']): ?>
              <div style="font-size:10px;color:#dc2626;margin-top:3px;max-width:180px;" title="<?php echo htmlspecialchars($row['decline_reason']); ?>">
                "<?php echo htmlspecialchars(substr($row['decline_reason'], 0, 40)) . (strlen($row['decline_reason']) > 40 ? '...' : ''); ?>"
              </div>
            <?php endif; ?>
          </td>
          <td style="font-size:12px;"><?php echo htmlspecialchars($row['reviewed_by'] ?? '—'); ?></td>
          <td>
            <div style="display:flex;gap:6px;flex-wrap:nowrap;">
              <button class="act-btn act-view" title="View Details"
                      onclick="viewDetails(<?php echo $row['id']; ?>)">
                <i class="fas fa-eye"></i>
              </button>
              <?php if ($row['status'] == 'pending' || $row['status'] == 'resubmit'): ?>
              <button class="act-btn act-approve" title="Approve"
                      onclick="openApprove(<?php echo $row['id']; ?>, '<?php echo addslashes(htmlspecialchars($row['name'] ?? $row['candidate_name'])); ?>')">
                <i class="fas fa-check"></i>
              </button>
              <button class="act-btn act-decline" title="Decline / Resubmit"
                      onclick="openDecline(<?php echo $row['id']; ?>, '<?php echo addslashes(htmlspecialchars($row['name'] ?? $row['candidate_name'])); ?>')">
                <i class="fas fa-times"></i>
              </button>
              <?php endif; ?>
              <?php
              $base_url = (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
              $emp_link = $row['token'] ? $base_url . '/hr-employee-onboarding.php?token=' . $row['token'] : '';
              if ($emp_link):
                  $emp_email = $row['email'] ?: ($row['personal_email'] ?: ($row['candidate_email'] ?: ''));
                  $emp_subj = rawurlencode("Update regarding your Onboarding Application");
                  $emp_body = rawurlencode("Dear " . ($row['name'] ?: $row['candidate_name']) . ",\n\nPlease click the link below to access your onboarding form:\n\n" . $emp_link . "\n\nBest Regards,\nHR Department");
              ?>
              <button class="act-btn act-notify" title="Send Manual Notification"
                      onclick="openOnboardingNotify('<?php echo addslashes($emp_email); ?>', '<?php echo $emp_subj; ?>', '<?php echo $emp_body; ?>', '<?php echo addslashes($emp_link); ?>')">
                <i class="fas fa-paper-plane"></i>
              </button>
              <?php endif; ?>
              <button class="act-btn act-delete" title="Delete Submission"
                      onclick="deleteSubmission(<?php echo $row['id']; ?>)">
                <i class="fas fa-trash"></i>
              </button>
            </div>
          </td>
        </tr>
        <?php endwhile; endif; ?>
      </tbody>
    </table>
  </div>

</div>

<!-- VIEW DETAILS MODAL -->
<div class="modal fade" id="viewModal" tabindex="-1">
  <div class="modal-dialog modal-xl">
    <div class="modal-content">
      <div class="modal-header">
        <h5><i class="fas fa-user-circle mr-2"></i> Onboarding Submission Details</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="viewModalBody">
        <div class="spinner"></div>
      </div>
    </div>
  </div>
</div>

<!-- APPROVE MODAL (WITH OFFICIAL INFO) -->
<div class="modal fade" id="approveModal" tabindex="-1">
  <div class="modal-dialog modal-xl">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#10b981,#059669);">
        <h5><i class="fas fa-check-circle mr-2"></i> Approve Employee Onboarding & Enter Official Info</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="background:#f8fafc;">
        <input type="hidden" id="approve_pending_id">
        
        <div style="text-align:center;margin-bottom:20px;">
          <h5 style="font-weight:800;color:#1e293b;margin-top:12px;">Candidate: <span id="approve_name" style="color:#10b981;"></span></h5>
          <p style="color:#64748b;font-size:13px;">Please verify and complete the official employment data before final approval.</p>
        </div>

        <form id="approveOfficialForm">
          <div class="row">
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Official Email *</label>
              <input type="email" id="app_email" class="modal-fc" required>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Hire Date *</label>
              <input type="date" id="app_hire_date" class="modal-fc" required>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Department *</label>
              <select id="app_department" class="modal-fc" required></select>
            </div>
          </div>

          <div class="row">
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Position *</label>
              <select id="app_position" class="modal-fc" required></select>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Employee Type *</label>
              <select id="app_employee_type" class="modal-fc" required>
                <option value="Probation period">Probation period</option>
                <option value="Permanent Employee">Permanent Employee</option>
              </select>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Salary (₹) *</label>
              <input type="number" step="0.01" id="app_salary" class="modal-fc" required>
            </div>
          </div>

          <div class="row">
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Work Location *</label>
              <select id="app_work_location" class="modal-fc" required></select>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Company *</label>
              <select id="app_company_name" class="modal-fc" required></select>
            </div>
            <div class="col-md-4">
              <label style="font-weight:600;font-size:12px;">Timings *</label>
              <select id="app_timings" class="modal-fc" required></select>
            </div>
          </div>

          <div class="row">
            <div class="col-md-6">
              <label style="font-weight:600;font-size:12px;">Reporting Manager 1</label>
              <select id="app_reporting_manager_1" class="modal-fc"></select>
            </div>
            <div class="col-md-6">
              <label style="font-weight:600;font-size:12px;">Reporting Manager 2</label>
              <select id="app_reporting_manager_2" class="modal-fc"></select>
            </div>
          </div>

          <div class="option-row" style="margin-top:15px;background:#fff;">
            <div style="font-weight:700;color:#1e293b;margin-bottom:10px;font-size:13px;">
              <i class="fas fa-bell"></i> Notify Employee?
            </div>
            <label style="margin-right:20px;">
              <input type="radio" name="notify_approve" value="1"> Yes — Send confirmation
            </label>
            <label>
              <input type="radio" name="notify_approve" value="0" checked> No — Save silently
            </label>
          </div>
        </form>

        <button class="btn-approve-final mt-3" onclick="submitApprove()">
          <i class="fas fa-check-circle"></i> Confirm Approval & Generate ID
        </button>
      </div>
    </div>
  </div>
</div>

<!-- DECLINE MODAL -->
<div class="modal fade" id="declineModal" tabindex="-1">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#ef4444,#dc2626);">
        <h5><i class="fas fa-times-circle mr-2"></i> Decline Onboarding Submission</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="decline_pending_id">
        <div style="text-align:center;margin-bottom:20px;">
          <h5 style="font-weight:800;color:#1e293b;">Decline <span id="decline_name"></span>?</h5>
          <p style="color:#64748b;font-size:13px;">Please provide a reason for declining and choose the next step.</p>
        </div>

        <div style="margin-bottom:14px;">
          <label style="font-weight:700;color:#1e293b;font-size:13px;display:block;margin-bottom:6px;">
            Reason for Decline <span style="color:#dc2626;">*</span>
          </label>
          <textarea id="decline_reason" class="modal-fc" rows="3"
                    placeholder="e.g. Missing Aadhar card, incorrect bank details, etc."></textarea>
        </div>

        <div class="option-row">
          <div style="font-weight:700;color:#1e293b;margin-bottom:10px;font-size:13px;">
            <i class="fas fa-redo"></i> Allow Employee to Resubmit?
          </div>
          <label style="margin-bottom:8px;">
            <input type="radio" name="resubmit_option" value="1"> Yes — Let employee correct and resubmit
          </label><br>
          <label>
            <input type="radio" name="resubmit_option" value="0" checked> No — Final rejection
          </label>
        </div>

        <div class="option-row">
          <div style="font-weight:700;color:#1e293b;margin-bottom:10px;font-size:13px;">
            <i class="fas fa-bell"></i> Notify Employee?
          </div>
          <label style="margin-bottom:8px;">
            <input type="radio" name="notify_decline" value="1"> Yes — Notify with reason
          </label><br>
          <label>
            <input type="radio" name="notify_decline" value="0" checked> No — Do not notify
          </label>
        </div>

        <button class="btn-decline-final" onclick="submitDecline()">
          <i class="fas fa-times-circle"></i> Confirm Decline
        </button>
      </div>
    </div>
  </div>
</div>

<!-- GENERATE ONBOARDING LINK MODAL -->
<div class="modal fade" id="generateLinkModal" tabindex="-1">
  <div class="modal-dialog modal-dialog-centered modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#1e3a8a,#1e40af);">
        <h5><i class="fas fa-link mr-2"></i> Generate Employee Onboarding Link</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">

        <div class="link-gen-box">
          <h5><i class="fas fa-info-circle mr-1"></i> How it works</h5>
          <p style="font-size:13px;color:#0369a1;margin:0;">
            Generate a secure unique link and share it with the new employee.
            The employee fills the joining form online. Their submission appears here for your approval.
          </p>
        </div>

        <div class="row">
          <div class="col-md-6">
            <div class="form-group">
              <label style="font-weight:700;font-size:13px;color:#1e293b;">Candidate Name <span style="color:#dc2626;">*</span></label>
              <select id="gen_candidate_select" class="modal-fc" onchange="autoFillCandidate()">
                <option value="">-- Select Hired Candidate --</option>
                <option value="manual">Enter manually...</option>
                <?php foreach ($hired_candidates as $hc): 
                  $pos = $hc['position'] ?? $hc['position_applied'] ?? '';
                  $label = htmlspecialchars($hc['candidate_name']) . ' (' . htmlspecialchars($hc['department'] . ($pos ? ' - ' . $pos : '')) . ')';
                ?>
                  <option value="<?php echo htmlspecialchars(json_encode($hc)); ?>"><?php echo $label; ?></option>
                <?php endforeach; ?>
              </select>
              <input type="text" id="gen_candidate_name" class="modal-fc" placeholder="Full name" style="display:none; margin-top:10px;">
            </div>
          </div>
          <div class="col-md-6">
            <div class="form-group">
              <label style="font-weight:700;font-size:13px;color:#1e293b;">Candidate Email</label>
              <input type="email" id="gen_candidate_email" class="modal-fc" placeholder="email@example.com">
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col-md-6">
            <div class="form-group">
              <label style="font-weight:700;font-size:13px;color:#1e293b;">Joining Date</label>
              <input type="date" id="gen_joining_date" class="modal-fc">
            </div>
          </div>
          <div class="col-md-6">
            <div class="form-group">
              <label style="font-weight:700;font-size:13px;color:#1e293b;">Link Expiry</label>
              <select id="gen_expiry" class="modal-fc">
                <option value="24">24 Hours</option>
                <option value="48" selected>48 Hours</option>
                <option value="72">3 Days</option>
                <option value="168">7 Days</option>
                <option value="0">No Expiry</option>
              </select>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col-md-12">
            <div class="form-group">
              <label style="font-weight:700;font-size:13px;color:#1e293b;">Candidate ID (from Screening, optional)</label>
              <input type="number" id="gen_candidate_id" class="modal-fc" placeholder="Leave blank if not from screening">
            </div>
          </div>
        </div>

        <button onclick="generateLink()"
                style="width:100%;padding:14px;border:none;border-radius:10px;
                       background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;
                       font-family:'Poppins',sans-serif;font-weight:700;font-size:15px;cursor:pointer;">
          <i class="fas fa-link"></i> Generate Secure Link
        </button>

        <div id="generatedLinkBox" style="display:none;margin-top:20px;
             background:#f0fdf4;border:2px solid #86efac;border-radius:12px;padding:20px;">
          <div style="font-weight:700;color:#065f46;margin-bottom:12px;">
            <i class="fas fa-check-circle"></i> Link Generated Successfully!
          </div>
          <div style="display:flex;gap:10px;align-items:center;margin-bottom:12px;">
            <input type="text" id="generatedLinkInput" class="modal-fc" readonly style="flex:1;margin:0;background:#fff;">
            <button onclick="copyLink()"
                    style="padding:10px 16px;border:none;border-radius:8px;
                           background:#1e3a8a;color:white;font-family:'Poppins',sans-serif;
                           font-weight:700;cursor:pointer;white-space:nowrap;">
              <i class="fas fa-copy"></i> Copy
            </button>
          </div>
          <div style="display:flex;gap:10px;flex-wrap:wrap;" id="shareBtns"></div>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- =====================================================================
     MODAL: NOTIFY (EMAIL + WHATSAPP)
===================================================================== -->
<div class="modal fade" id="notifyModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title"><i class="fas fa-paper-plane mr-2"></i>Notify Candidate</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <input type="hidden" id="notifyLink">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            Review and edit the messages below before sending via Email or WhatsApp.
        </p>

        <!-- Email Section -->
        <div style="background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; padding:15px; margin-bottom:20px;">
            <div style="font-weight:800;font-size:13px;color:#1e3a8a;margin-bottom:12px;">
                <i class="fas fa-envelope mr-2" style="color:#3b82f6;"></i> Send via Email
            </div>
            <div class="row">
                <div class="col-md-6">
                    <label style="font-size:12px;font-weight:600;color:#64748b;margin-bottom:4px;">To (Email Address)</label>
                    <input type="text" id="rn_email_to" class="modal-fc" style="margin-bottom:10px;">
                </div>
                <div class="col-md-6">
                    <label style="font-size:12px;font-weight:600;color:#64748b;margin-bottom:4px;">Subject</label>
                    <input type="text" id="rn_email_subj" class="modal-fc" style="margin-bottom:10px;">
                </div>
            </div>
            <label style="font-size:12px;font-weight:600;color:#64748b;margin-bottom:4px;">Email Body (Plain Text)</label>
            <textarea id="rn_email_body" class="modal-fc" style="height:120px;resize:vertical;"></textarea>
            <div style="margin-top:10px;text-align:right;">
                <button type="button" id="btnNotifyEmail" onclick="sendNotifyEmail()" style="background:#3b82f6;color:white;border:none;border-radius:8px;padding:8px 16px;font-weight:700;cursor:pointer;">
                    <i class="fas fa-paper-plane mr-1"></i> Send Email
                </button>
            </div>
        </div>

        <!-- WhatsApp Section -->
        <div style="background:#f0fdf4; border:1px solid #bbf7d0; border-radius:10px; padding:15px;">
            <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;">
                <i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp
            </div>
            <label style="font-size:12px;font-weight:600;color:#065f46;margin-bottom:4px;">WhatsApp Message</label>
            <textarea id="rn_wa_msg" class="modal-fc" style="height:120px;resize:vertical;"></textarea>
            <div style="margin-top:10px;text-align:right;">
                <button type="button" onclick="openNotifyWhatsApp()" style="background:#25d366;color:white;border:none;border-radius:8px;padding:8px 16px;font-weight:700;cursor:pointer;">
                    <i class="fab fa-whatsapp mr-1"></i> Open WhatsApp
                </button>
            </div>
        </div>

    </div>
</div></div></div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>

function showAlert(msg, type) {
    type = type || 'success';
    var bg = type === 'success' ? '#dcfce7' : '#fee2e2';
    var col = type === 'success' ? '#065f46' : '#991b1b';
    var ic = type === 'success' ? 'fa-check-circle' : 'fa-exclamation-circle';
    var el = $('<div>').css({
        background: bg, color: col, padding: '14px 18px', borderRadius: '10px',
        boxShadow: '0 4px 12px rgba(0,0,0,0.12)', fontWeight: '700',
        fontSize: '14px', marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '10px'
    }).html('<i class="fas ' + ic + '"></i> ' + msg);
    $('#alertContainer').append(el);
    setTimeout(function() { el.fadeOut(400, function() { el.remove(); }); }, 4000);
}

function filterByStatus(status) {
    window.location.href = '?status=' + status;
}

function filterTable() {
    var search = $('#searchInput').val().toLowerCase();
    var status = $('#statusFilter').val();
    $('#tableBody tr').each(function() {
        var name   = $(this).data('name') || '';
        var rowSt  = $(this).data('status') || '';
        var show   = true;
        if (search && name.indexOf(search) === -1) show = false;
        if (status && rowSt !== status) show = false;
        $(this).toggle(show);
    });
}

function viewDetails(id) {
    $('#viewModalBody').html('<div class="spinner"></div>');
    $('#viewModal').modal('show');
    $.get(window.location.pathname + '?ajax_view=1&id=' + id, function(html) {
        $('#viewModalBody').html(html);
    }).fail(function() {
        $('#viewModalBody').html('<p style="color:red;padding:20px;text-align:center;">Failed to load details.</p>');
    });
}

function openApprove(id, name) {
    $('#approve_pending_id').val(id);
    $('#approve_name').text(name);
    $('input[name="notify_approve"][value="0"]').prop('checked', true);
    $('#viewModal').modal('hide');
    
    // Fetch data and populate modal
    $.post(window.location.pathname, { ajax_get_approve_data: 1, pending_id: id }, function(resp) {
        if(resp.success) {
            let d = resp.data;
            let dr = resp.dropdowns;

            // Populate Dropdowns
            let popSelect = (id, arr, valKey, textKey, selectedVal) => {
                let html = '<option value="">Select...</option>';
                arr.forEach(i => {
                    let v = valKey ? i[valKey] : i;
                    let t = textKey ? i[textKey] : i;
                    let sel = (v === selectedVal) ? 'selected' : '';
                    html += `<option value="${v}" ${sel}>${t}</option>`;
                });
                $(id).html(html);
            };

            popSelect('#app_department', dr.departments, null, null, d.department);
            popSelect('#app_position', dr.positions, null, null, d.position);
            popSelect('#app_work_location', dr.locations, null, null, d.work_location);
            popSelect('#app_company_name', dr.companies, null, null, d.company_name);
            
            // Managers (value=employee_id, text=name)
            let mgrHtml = '<option value="">Select Manager</option>';
            dr.employees.forEach(e => {
                let sel = (e.employee_id === d.reporting_manager_1) ? 'selected' : '';
                mgrHtml += `<option value="${e.employee_id}" ${sel}>${e.name} (${e.employee_id})</option>`;
            });
            $('#app_reporting_manager_1').html(mgrHtml).val(d.reporting_manager_1);
            $('#app_reporting_manager_2').html(mgrHtml).val(d.reporting_manager_2);

            // Timings (append custom if needed)
            let timeHtml = '<option value="">Select Shift</option>';
            let foundTime = false;
            dr.timings.forEach(t => {
                let sel = (t === d.timings) ? 'selected' : '';
                if(sel) foundTime = true;
                timeHtml += `<option value="${t}" ${sel}>${t}</option>`;
            });
            if (d.timings && !foundTime) {
                timeHtml += `<option value="${d.timings}" selected>${d.timings} (Custom)</option>`;
            }
            $('#app_timings').html(timeHtml);

            // Text fields
            $('#app_email').val(d.email || d.personal_email);
            $('#app_hire_date').val(d.hire_date);
            $('#app_salary').val(d.salary);
            $('#app_employee_type').val(d.employee_type || 'Probation period');

            setTimeout(function() { $('#approveModal').modal('show'); }, 300);
        } else {
            showAlert('Failed to load data', 'error');
        }
    }, 'json');
}

function submitApprove() {
    // Validate required fields
    let form = document.getElementById('approveOfficialForm');
    if (!form.checkValidity()) {
        form.reportValidity();
        return;
    }

    var btn = $('.btn-approve-final');
    btn.html('<i class="fas fa-spinner fa-spin"></i> Processing...').prop('disabled', true);

    $.post(window.location.pathname, {
        ajax_approve_confirm: 1,
        pending_id: $('#approve_pending_id').val(),
        notify_employee: $('input[name="notify_approve"]:checked').val(),
        email: $('#app_email').val(),
        hire_date: $('#app_hire_date').val(),
        department: $('#app_department').val(),
        position: $('#app_position').val(),
        employee_type: $('#app_employee_type').val(),
        salary: $('#app_salary').val(),
        work_location: $('#app_work_location').val(),
        company_name: $('#app_company_name').val(),
        timings: $('#app_timings').val(),
        reporting_manager_1: $('#app_reporting_manager_1').val(),
        reporting_manager_2: $('#app_reporting_manager_2').val()
    }, function(resp) {
        btn.html('<i class="fas fa-check-circle"></i> Confirm Approval & Generate ID').prop('disabled', false);
        if (resp.success) {
            $('#approveModal').modal('hide');
            showAlert('✅ Employee approved! Employee ID: ' + resp.employee_id, 'success');
            setTimeout(function() { location.reload(); }, 2000);
        } else {
            showAlert('Error: ' + (resp.message || 'Could not approve.'), 'error');
        }
    }, 'json').fail(function() {
        btn.html('<i class="fas fa-check-circle"></i> Confirm Approval & Generate ID').prop('disabled', false);
        showAlert('Server error. Please try again.', 'error');
    });
}

function openDecline(id, name) {
    $('#decline_pending_id').val(id);
    $('#decline_name').text(name);
    $('#decline_reason').val('');
    $('input[name="resubmit_option"][value="0"]').prop('checked', true);
    $('input[name="notify_decline"][value="0"]').prop('checked', true);
    $('#viewModal').modal('hide');
    setTimeout(function() { $('#declineModal').modal('show'); }, 300);
}

function submitDecline() {
    var id      = $('#decline_pending_id').val();
    var reason  = $('#decline_reason').val().trim();
    var resubmit= $('input[name="resubmit_option"]:checked').val();
    var notify  = $('input[name="notify_decline"]:checked').val();
    var btn     = $('.btn-decline-final');

    if (!reason) {
        alert('Please enter a reason for declining.');
        return;
    }

    btn.html('<i class="fas fa-spinner fa-spin"></i> Processing...').prop('disabled', true);

    $.post(window.location.pathname, {
        ajax_decline: 1,
        pending_id: id,
        decline_reason: reason,
        allow_resubmit: resubmit,
        notify_employee: notify
    }, function(resp) {
        btn.html('<i class="fas fa-times-circle"></i> Confirm Decline').prop('disabled', false);
        if (resp.success) {
            $('#declineModal').modal('hide');
            var msg = resubmit == '1' ? '🔄 Employee notified to resubmit with corrections.' : '❌ Submission declined.';
            showAlert(msg, 'success');
            setTimeout(function() { location.reload(); }, 2000);
        } else {
            showAlert('Error occurred. Please try again.', 'error');
        }
    }, 'json').fail(function() {
        btn.html('<i class="fas fa-times-circle"></i> Confirm Decline').prop('disabled', false);
        showAlert('Server error. Please try again.', 'error');
    });
}

function deleteSubmission(id) {
    if (confirm('Are you sure you want to permanently delete this submission? This cannot be undone.')) {
        $.post(window.location.pathname, { ajax_delete_submission: 1, pending_id: id }, function(resp) {
            if (resp.success) {
                showAlert('🗑️ Submission deleted successfully.', 'success');
                setTimeout(function() { location.reload(); }, 2000);
            } else {
                showAlert('Error occurred. Please try again.', 'error');
            }
        }, 'json').fail(function() {
            showAlert('Server error. Please try again.', 'error');
        });
    }
}

function generateLink() {
    var name    = $('#gen_candidate_name').val().trim();
    var email   = $('#gen_candidate_email').val().trim();
    var date    = $('#gen_joining_date').val();
    var expiry  = $('#gen_expiry').val();
    var cid     = $('#gen_candidate_id').val() || 0;

    if (!name) { alert('Please enter the candidate name.'); return; }

    $.post(window.location.pathname, {
        ajax_generate_onboarding_link: 1,
        candidate_id: cid,
        candidate_name: name,
        candidate_email: email,
        joining_date: date,
        expiry_hours: expiry
    }, function(resp) {
        if (resp.success) {
            $('#generatedLinkInput').val(resp.link);
            var subj = 'Your Employee Joining Form — Please Complete';
            var bodyText = 'Dear ' + name + ',\n\nWelcome to our team! Please complete your joining form using the secure link below:\n' + resp.link + '\n\nBest Regards,\nHR Team';
            var shareBtns = '<button onclick="openOnboardingNotify(\'' + (email||'') + '\', \'' + encodeURIComponent(subj) + '\', \'' + encodeURIComponent(bodyText) + '\', \'' + resp.link + '\')" style="padding:10px 16px;border:none;border-radius:8px;background:#6366f1;color:white;font-family:Poppins,sans-serif;font-weight:700;font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;"><i class="fas fa-paper-plane"></i> Notify Candidate</button>';
            $('#shareBtns').html(shareBtns);
            $('#generatedLinkBox').fadeIn(300);
        } else {
            alert('Failed to generate link. Please try again.');
        }
    }, 'json').fail(function() {
        alert('Server error. Please try again.');
    });
}

function copyLink() {
    var input = document.getElementById('generatedLinkInput');
    input.select();
    document.execCommand('copy');
    showAlert('Link copied to clipboard!', 'success');
}

function openOnboardingNotify(email, subjEncoded, bodyEncoded, link) {
    $('#rn_email_to').val(email);
    $('#rn_email_subj').val(decodeURIComponent(subjEncoded));
    $('#rn_email_body').val(decodeURIComponent(bodyEncoded));
    $('#rn_wa_msg').val(decodeURIComponent(bodyEncoded));
    $('#notifyLink').val(link);
    $('#notifyModal').modal('show');
}

function sendNotifyEmail() {
    var email = $('#rn_email_to').val().trim();
    var subj = $('#rn_email_subj').val().trim();
    var body = $('#rn_email_body').val().trim();
    var link = $('#notifyLink').val();
    if (!email) { alert('Please enter candidate email.'); return; }

    var btn = $('#btnNotifyEmail');
    var oldHtml = btn.html();
    btn.html('<i class="fas fa-spinner fa-spin"></i> Sending...').prop('disabled', true);
    
    $.post(window.location.pathname, {
        ajax_send_onboarding_email: 1,
        to: email,
        subject: subj,
        body: body,
        link: link
    }, function(resp) {
        btn.html(oldHtml).prop('disabled', false);
        if (resp.success) {
            showAlert('📧 Email sent to ' + email + ' successfully!', 'success');
            $('#notifyModal').modal('hide');
        } else {
            showAlert('Error: ' + resp.message, 'error');
        }
    }, 'json').fail(function() {
        btn.html(oldHtml).prop('disabled', false);
        showAlert('Server error while sending email.', 'error');
    });
}

function openNotifyWhatsApp() {
    var msg = $('#rn_wa_msg').val().trim();
    var waUrl = 'https://wa.me/?text=' + encodeURIComponent(msg);
    window.open(waUrl, '_blank');
}

function autoFillCandidate() {
    var sel = document.getElementById('gen_candidate_select').value;
    var nameInput = document.getElementById('gen_candidate_name');
    var emailInput = document.getElementById('gen_candidate_email');
    var idInput = document.getElementById('gen_candidate_id');
    
    if (sel === 'manual') {
        nameInput.style.display = 'block';
        nameInput.value = '';
        emailInput.value = '';
        idInput.value = '';
        emailInput.readOnly = false;
        idInput.readOnly = false;
    } else if (sel !== '') {
        nameInput.style.display = 'none';
        var data = JSON.parse(sel);
        nameInput.value = data.candidate_name || '';
        emailInput.value = data.candidate_email || '';
        idInput.value = data.id || '';
        emailInput.readOnly = true;
        idInput.readOnly = true;
    } else {
        nameInput.style.display = 'none';
        nameInput.value = '';
        emailInput.value = '';
        idInput.value = '';
        emailInput.readOnly = false;
        idInput.readOnly = false;
    }
}

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