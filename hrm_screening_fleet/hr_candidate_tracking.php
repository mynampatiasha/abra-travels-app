<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');

// =========================================================================
// ADMIN CHECK FOR DASHBOARD BUTTON
// =========================================================================
$btn_currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$btn_authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$btn_isAdmin = false;
foreach($btn_authorized_admin_names as $admin_name) {
    if(stripos($btn_currentUserName, $admin_name) !== false || stripos($admin_name, $btn_currentUserName) !== false) {
        $btn_isAdmin = true;
        break;
    }
}
$dashboard_url = $btn_isAdmin ? 'index.php' : 'raise-a-ticket.php';

require_once('funciones.php');
require 'requirelanguage.php';

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE (Flutter WebView Auth)
// =========================================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$session_name = trim($_SESSION['user_name'] ?? '');
$emp_data = null;
$db_link = isset($dbConn) ? $dbConn : (isset($con) ? $con : null);

if ($db_link && !empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($db_link, $currentUserEmail);
    $eq = mysqli_query($db_link, "
        SELECT id, employee_id, name, department, position 
        FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
        $_SESSION['user_name'] = $emp_data['name'];
        $_SESSION['user_id'] = $emp_data['id'];
        $session_name = $emp_data['name'];
    }
}

if (!$emp_data && $session_name && $db_link) {
    $safe_name = mysqli_real_escape_string($db_link, $session_name);
    $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name = '$safe_name' AND status = 'Active' LIMIT 1");
    if (!$eq || mysqli_num_rows($eq) == 0) {
        $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name LIKE '$safe_name%' AND status = 'Active' LIMIT 1");
    }
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
    }
}

if (!$emp_data) {
    die("
        <div style='font-family:sans-serif; max-width:600px; margin:60px auto; padding:30px; 
                    border:2px solid #ef4444; border-radius:12px; background:#fef2f2; color:#b91c1c;'>
            <h2 style='margin-top:0;'>&#10060; Authentication Failed</h2>
            <p>Could not identify your employee record.</p>
        </div>
    ");
}

$url_email = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';
// =========================================================================


$con = conexion();
if (!$con) die("Database connection failed: " . mysqli_connect_error());

mysqli_set_charset($con, 'utf8mb4');
date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
// isUser();

$current_page   = basename($_SERVER['PHP_SELF']);
$currentUser    = isset($_SESSION['user_name'])  ? trim($_SESSION['user_name'])  : 'HR';
$companyName    = isset($_SESSION['ge_cname'])   ? trim($_SESSION['ge_cname'])   : 'Company';

// =========================================================================
// AUTO-CREATE TABLES
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_candidate_tracking (
    id              INT(11) AUTO_INCREMENT PRIMARY KEY,
    department_id   INT(11) DEFAULT 0,
    position_id     INT(11) DEFAULT 0,
    department_name VARCHAR(255) DEFAULT '',
    position_name   VARCHAR(255) DEFAULT '',
    name            VARCHAR(255) NOT NULL,
    phone           VARCHAR(30)  NOT NULL,
    email           VARCHAR(255) DEFAULT '',
    resume_path     VARCHAR(500) DEFAULT '',
    resume_name     VARCHAR(255) DEFAULT '',
    jd_path         VARCHAR(500) DEFAULT '',
    jd_name         VARCHAR(255) DEFAULT '',
    current_status  VARCHAR(50)  DEFAULT 'New',
    trigger_datetime DATETIME    DEFAULT NULL,
    last_note       TEXT,
    last_updated_by VARCHAR(255) DEFAULT '',
    created_by      VARCHAR(255) DEFAULT '',
    created_at      DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_candidate_tracking_log (
    id              INT(11) AUTO_INCREMENT PRIMARY KEY,
    candidate_id    INT(11) NOT NULL,
    status          VARCHAR(50)  DEFAULT '',
    notes           TEXT,
    trigger_datetime DATETIME    DEFAULT NULL,
    updated_by      VARCHAR(255) DEFAULT '',
    updated_at      DATETIME     DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$src_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'candidate_source'");
if ($src_col_check && mysqli_num_rows($src_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN candidate_source VARCHAR(50) DEFAULT ''");
}
$loc_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'location'");
if ($loc_col_check && mysqli_num_rows($loc_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN location VARCHAR(255) DEFAULT ''");
}
$candidate_sources = ['Reference','Walk-in','Naukri','Apna','Indeed','LinkedIn','Other'];
$candidate_locations = ['Kasturi Nagar','Whitefield','Vasanth Nagar','Other'];

// Records which round a candidate was rejected at (e.g. "Round 2: Manager Round", or "Overall")
// so the tracking table can label rejections instead of just showing a bare "Rejected" status.
$rejround_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_candidate_tracking LIKE 'rejected_round'");
if ($rejround_col_check && mysqli_num_rows($rejround_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_candidate_tracking ADD COLUMN rejected_round VARCHAR(255) DEFAULT NULL");
}

// Permanent rejection log — shared with hr_screening.php / hr-rejected-candidates.php.
// Created here too in case this page is used to reject a candidate before hr_screening.php
// has ever run and created this table.
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_rejection_log (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) DEFAULT NULL,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    company_id int(11) DEFAULT NULL,
    round_number int(11) DEFAULT 0,
    round_name varchar(255) DEFAULT 'Overall',
    round_type varchar(30) DEFAULT 'overall',
    reason text NOT NULL,
    rejected_by varchar(255) DEFAULT NULL,
    kept_in_database tinyint(1) DEFAULT 1,
    resume_filename varchar(500) DEFAULT NULL,
    resume_path varchar(500) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$rl_col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_rejection_log LIKE 'rejection_source'");
if ($rl_col_check && mysqli_num_rows($rl_col_check) == 0) {
    mysqli_query($con, "ALTER TABLE hr_rejection_log ADD COLUMN rejection_source VARCHAR(30) DEFAULT 'hr_screening'");
}

// Upload directory
$upload_dir = 'uploads/candidate_tracking/';
if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);

// Statuses that show the trigger date/time field
$trigger_statuses = ['Scheduled', 'Follow Up', 'Interested', 'Call Later', 'Callback', 'Round 1', 'Round 2', 'Round 3', 'Round 4', 'Round 5'];
// Statuses where the trigger date/time is MANDATORY. "Interested" is deliberately excluded —
// a candidate can be Interested without an interview being scheduled yet (e.g. salary mismatch).
$trigger_required_statuses = ['Scheduled', 'Follow Up', 'Call Later', 'Callback', 'Round 1', 'Round 2', 'Round 3', 'Round 4', 'Round 5'];

$all_statuses = ['New','Called','Interested','Not Interested','Candidate did not answer the call','Candidate disconnected the call','Call Later','Callback','Scheduled','Follow Up','Round 1','Round 2','Round 3','Round 4','Round 5','No Response','Rejected','Hired'];

// Status badge colour map
$status_colors = [
    'New'           => '#6366f1',
    'Called'        => '#3b82f6',
    'Interested'    => '#10b981',
    'Not Interested'=> '#ef4444',
    'Candidate did not answer the call'   => '#fb923c',
    'Candidate disconnected the call'=> '#e11d48',
    'Call Later'    => '#f59e0b',
    'Callback'      => '#f97316',
    'Scheduled'     => '#8b5cf6',
    'Follow Up'     => '#06b6d4',
    'Round 1'       => '#0ea5e9',
    'Round 2'       => '#3b82f6',
    'Round 3'       => '#6366f1',
    'Round 4'       => '#8b5cf6',
    'Round 5'       => '#a855f7',
    'No Response'   => '#94a3b8',
    'Rejected'      => '#dc2626',
    'Hired'         => '#059669',
];

// =========================================================================
// HELPER: UPLOAD FILE
// =========================================================================
function uploadCandidateFile($file_key, $candidate_id, $type) {
    global $upload_dir;
    if (!isset($_FILES[$file_key]) || $_FILES[$file_key]['error'] !== UPLOAD_ERR_OK) return ['path'=>'','name'=>''];
    $original  = basename($_FILES[$file_key]['name']);
    $ext       = strtolower(pathinfo($original, PATHINFO_EXTENSION));
    $allowed   = ['pdf','doc','docx','png','jpg','jpeg'];
    if (!in_array($ext, $allowed)) return ['path'=>'','name'=>''];
    $safe_name = $type . '_' . $candidate_id . '_' . time() . '.' . $ext;
    $dest      = $upload_dir . $safe_name;
    if (move_uploaded_file($_FILES[$file_key]['tmp_name'], $dest)) {
        return ['path' => $dest, 'name' => $original];
    }
    return ['path'=>'','name'=>''];
}

// =========================================================================
// AJAX: GET POSITIONS
// =========================================================================
if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $rows = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// =========================================================================
// AJAX: GET CANDIDATE DETAILS (for view modal)
// =========================================================================
if (isset($_GET['get_candidate'])) {
    header('Content-Type: application/json');
    $id  = intval($_GET['id']);
    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
    echo json_encode($row ?: []); exit;
}

// =========================================================================
// AJAX: CHECK DUPLICATE (phone/email) BEFORE ADDING
// =========================================================================
if (isset($_GET['check_duplicate'])) {
    header('Content-Type: application/json');
    $phone = mysqli_real_escape_string($con, trim($_GET['phone'] ?? ''));
    $email = mysqli_real_escape_string($con, trim($_GET['email'] ?? ''));
    $dept  = mysqli_real_escape_string($con, trim($_GET['dept'] ?? ''));
    $pos   = mysqli_real_escape_string($con, trim($_GET['pos'] ?? ''));
    
    $result = ['duplicate' => false];
    if ($phone || $email) {
        $cond = [];
        if ($phone) {
             $phone_digits = preg_replace('/\D/', '', $phone);
             if ($phone_digits) $cond[] = "phone LIKE '%$phone_digits%'";
        }
        if ($email) $cond[] = "email='$email'";
        
        if (!empty($cond)) {
            $q_str = "SELECT id, name, current_status, department_name, position_name FROM hr_candidate_tracking WHERE (" . implode(' OR ', $cond) . ") ";
            if ($dept) $q_str .= " AND department_name='$dept'";
            if ($pos) $q_str .= " AND position_name='$pos'";
            $q_str .= " LIMIT 1";

            $q = mysqli_query($con, $q_str);
            if ($q && $row = mysqli_fetch_assoc($q)) {
                $result = ['duplicate' => true, 'name' => $row['name'], 'id' => $row['id'], 'status' => $row['current_status']];
            }
        }
    }
    echo json_encode($result); exit;
}

// =========================================================================
// AJAX: GET LOG
// =========================================================================
if (isset($_GET['get_log'])) {
    header('Content-Type: application/json');
    $id   = intval($_GET['id']);
    $logs = [];
    $q    = mysqli_query($con, "SELECT * FROM hr_candidate_tracking_log WHERE candidate_id=$id ORDER BY updated_at DESC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) $logs[] = $r;
    echo json_encode($logs); exit;
}

// =========================================================================
// POST: ADD CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add_candidate') {
    $dept_id   = intval($_POST['department_id']);
    $pos_id    = intval($_POST['position_id']);
    $dept_name = mysqli_real_escape_string($con, trim($_POST['department_name'] ?? ''));
    $pos_name  = mysqli_real_escape_string($con, trim($_POST['position_name']   ?? ''));
    $name      = mysqli_real_escape_string($con, trim($_POST['name']));
    $phone     = mysqli_real_escape_string($con, trim($_POST['phone']));
    $email     = mysqli_real_escape_string($con, trim($_POST['email'] ?? ''));
    $created_by= mysqli_real_escape_string($con, $currentUser);

    if (empty($name) || empty($phone)) {
        $_SESSION['error_message'] = "Name and Phone are required.";
        header("Location: $current_page"); exit;
    }

    $src_select_raw = trim($_POST['candidate_source'] ?? '');
    $src_other_raw  = trim($_POST['candidate_source_other'] ?? '');
    $source_raw     = ($src_select_raw === 'Other' && $src_other_raw !== '') ? $src_other_raw : $src_select_raw;
    $source         = mysqli_real_escape_string($con, $source_raw);

    $loc_select_raw = trim($_POST['location_select'] ?? '');
    $loc_other_raw  = trim($_POST['location_other'] ?? '');
    $location_raw   = ($loc_select_raw === 'Other' && $loc_other_raw !== '') ? $loc_other_raw : $loc_select_raw;
    $location       = mysqli_real_escape_string($con, $location_raw);

    if (empty($_POST['confirm_duplicate'])) {
        $dup_check = mysqli_query($con, "SELECT id, name FROM hr_candidate_tracking WHERE phone='$phone'" . (!empty($email) ? " OR email='$email'" : "") . " LIMIT 1");
        if ($dup_check && mysqli_num_rows($dup_check) > 0) {
            $dup_row = mysqli_fetch_assoc($dup_check);
            $_SESSION['error_message'] = "A candidate with this phone/email already exists: " . htmlspecialchars($dup_row['name']) . " (ID #" . $dup_row['id'] . "). Use the 'Add anyway' checkbox if this is a different person.";
            header("Location: $current_page"); exit;
        }
    }

    mysqli_query($con, "INSERT INTO hr_candidate_tracking (department_id,position_id,department_name,position_name,name,phone,email,candidate_source,location,current_status,created_by,last_updated_by) VALUES ($dept_id,$pos_id,'$dept_name','$pos_name','$name','$phone','$email','$source','$location','New','$created_by','$created_by')");
    $new_id = mysqli_insert_id($con);

    // Upload files
    $resume = uploadCandidateFile('resume', $new_id, 'resume');
    $jd     = uploadCandidateFile('jd',     $new_id, 'jd');

    if ($resume['path'] || $jd['path']) {
        $rp = mysqli_real_escape_string($con, $resume['path']);
        $rn = mysqli_real_escape_string($con, $resume['name']);
        $jp = mysqli_real_escape_string($con, $jd['path']);
        $jn = mysqli_real_escape_string($con, $jd['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET resume_path='$rp',resume_name='$rn',jd_path='$jp',jd_name='$jn' WHERE id=$new_id");
    }

    // Initial log entry
    mysqli_query($con, "INSERT INTO hr_candidate_tracking_log (candidate_id,status,notes,updated_by) VALUES ($new_id,'New','Candidate created.','$created_by')");

    $_SESSION['success_message'] = "Candidate added successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: EDIT CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'edit_candidate') {
    $id        = intval($_POST['id']);
    $dept_id   = intval($_POST['department_id']);
    $pos_id    = intval($_POST['position_id']);
    $dept_name = mysqli_real_escape_string($con, trim($_POST['department_name'] ?? ''));
    $pos_name  = mysqli_real_escape_string($con, trim($_POST['position_name']   ?? ''));
    $name      = mysqli_real_escape_string($con, trim($_POST['name']));
    $phone     = mysqli_real_escape_string($con, trim($_POST['phone']));
    $email     = mysqli_real_escape_string($con, trim($_POST['email'] ?? ''));

    $loc_select_raw = trim($_POST['location_select'] ?? '');
    $loc_other_raw  = trim($_POST['location_other'] ?? '');
    $location_raw   = ($loc_select_raw === 'Other' && $loc_other_raw !== '') ? $loc_other_raw : $loc_select_raw;
    $location       = mysqli_real_escape_string($con, $location_raw);

    if (empty($name) || empty($phone)) {
        $_SESSION['error_message'] = "Name and Phone are required.";
        header("Location: $current_page"); exit;
    }

    mysqli_query($con, "UPDATE hr_candidate_tracking SET department_id=$dept_id,position_id=$pos_id,department_name='$dept_name',position_name='$pos_name',name='$name',phone='$phone',email='$email',location='$location' WHERE id=$id");

    // Handle new file uploads (only replace if new file uploaded)
    $resume = uploadCandidateFile('resume', $id, 'resume');
    $jd     = uploadCandidateFile('jd',     $id, 'jd');
    if ($resume['path']) {
        $rp = mysqli_real_escape_string($con, $resume['path']);
        $rn = mysqli_real_escape_string($con, $resume['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET resume_path='$rp',resume_name='$rn' WHERE id=$id");
    }
    if ($jd['path']) {
        $jp = mysqli_real_escape_string($con, $jd['path']);
        $jn = mysqli_real_escape_string($con, $jd['name']);
        mysqli_query($con, "UPDATE hr_candidate_tracking SET jd_path='$jp',jd_name='$jn' WHERE id=$id");
    }

    $_SESSION['success_message'] = "Candidate updated successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: UPDATE STATUS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'update_status') {
    $id              = intval($_POST['id']);
    $status          = mysqli_real_escape_string($con, $_POST['status']);
    $trigger_raw     = trim($_POST['trigger_datetime'] ?? '');
    $trigger_sql     = (!empty($trigger_raw)) ? "'" . mysqli_real_escape_string($con, $trigger_raw) . "'" : "NULL";
    $updated_by      = mysqli_real_escape_string($con, $currentUser);

    // ---- REJECTION requires a mandatory reason + round, same rules as hr_screening.php ----
    if ($_POST['status'] === 'Rejected') {
        $reject_reason_raw = trim($_POST['reject_reason'] ?? '');
        $reject_round_raw  = trim($_POST['reject_round'] ?? '');
        if ($reject_round_raw === '') $reject_round_raw = 'Overall';

        if ($reject_reason_raw === '') {
            $_SESSION['error_message'] = "A rejection reason is required.";
            header("Location: $current_page"); exit;
        }

        $cand_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
        if (!$cand_row) {
            $_SESSION['error_message'] = "Candidate not found.";
            header("Location: $current_page"); exit;
        }

        $reject_reason_esc = mysqli_real_escape_string($con, $reject_reason_raw);
        $reject_round_esc  = mysqli_real_escape_string($con, $reject_round_raw);
        $note_combined     = "Rejected at $reject_round_raw. Reason: $reject_reason_raw";
        $note_combined_esc = mysqli_real_escape_string($con, $note_combined);

        // Capture details BEFORE deleting the working row — needed for hr_rejection_log
        $cname_esc      = mysqli_real_escape_string($con, $cand_row['name']);
        $cemail_esc     = mysqli_real_escape_string($con, $cand_row['email']);
        $cphone_esc     = mysqli_real_escape_string($con, $cand_row['phone']);
        $pos_esc        = mysqli_real_escape_string($con, $cand_row['position_name']);
        $dept_esc       = mysqli_real_escape_string($con, $cand_row['department_name']);
        $screening_sql  = !empty($cand_row['screening_id']) ? intval($cand_row['screening_id']) : 'NULL';
        $resume_fn_esc  = mysqli_real_escape_string($con, $cand_row['resume_name'] ?? '');
        $resume_pt_esc  = mysqli_real_escape_string($con, $cand_row['resume_path'] ?? '');

        // 1) Write the PERMANENT rejection record first — this survives even after we delete the tracking row below
        mysqli_query($con, "INSERT INTO hr_rejection_log
            (screening_id, candidate_name, candidate_email, candidate_phone, position_applied, department,
             round_number, round_name, round_type, reason, rejected_by, kept_in_database, resume_filename, resume_path, rejection_source)
            VALUES
            ($screening_sql, '$cname_esc', '$cemail_esc', '$cphone_esc', '$pos_esc', '$dept_esc',
             0, '$reject_round_esc', 'overall', '$reject_reason_esc', '$updated_by', 1, '$resume_fn_esc', '$resume_pt_esc', 'candidate_tracking')");

        // 2) If this candidate is also tracked in hr_screenings, keep that record's decision in sync.
        if (!empty($cand_row['screening_id'])) {
            mysqli_query($con, "UPDATE hr_screenings SET hr_decision='rejected', screening_notes='$reject_reason_esc', updated_at=NOW() WHERE id=" . intval($cand_row['screening_id']));
        }

        // 3) Now that the rejection is permanently logged, remove the working row from
        //    hr_candidate_tracking entirely — this is what moves the candidate OUT of the
        //    tracking list and leaves them visible only on the Rejection Log page.
        if ($cand_row['resume_path'] && file_exists($cand_row['resume_path'])) @unlink($cand_row['resume_path']);
        if ($cand_row['jd_path']     && file_exists($cand_row['jd_path']))     @unlink($cand_row['jd_path']);
        mysqli_query($con, "DELETE FROM hr_candidate_tracking_log WHERE candidate_id=$id");
        mysqli_query($con, "DELETE FROM hr_candidate_tracking WHERE id=$id");

        $_SESSION['success_message'] = "Candidate rejected, logged, and removed from tracking.";
        header("Location: $current_page"); exit;
    }

    // ---- Normal (non-rejection) status update ----
    $notes_raw = trim($_POST['notes'] ?? '');
    if ($notes_raw === '') {
        $existing_note_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT last_note FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
        $notes_raw = $existing_note_row ? $existing_note_row['last_note'] : '';
    }
    $notes = mysqli_real_escape_string($con, $notes_raw);

    mysqli_query($con, "UPDATE hr_candidate_tracking SET current_status='$status',last_note='$notes',trigger_datetime=$trigger_sql,last_updated_by='$updated_by' WHERE id=$id");
    mysqli_query($con, "INSERT INTO hr_candidate_tracking_log (candidate_id,status,notes,trigger_datetime,updated_by) VALUES ($id,'$status','$notes',$trigger_sql,'$updated_by')");

    $_SESSION['success_message'] = "Status updated successfully.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// POST: DELETE CANDIDATE
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_candidate') {
    $id  = intval($_POST['id']);
    $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT resume_path,jd_path FROM hr_candidate_tracking WHERE id=$id LIMIT 1"));
    if ($row) {
        if ($row['resume_path'] && file_exists($row['resume_path'])) unlink($row['resume_path']);
        if ($row['jd_path']     && file_exists($row['jd_path']))     unlink($row['jd_path']);
    }
    mysqli_query($con, "DELETE FROM hr_candidate_tracking_log WHERE candidate_id=$id");
    mysqli_query($con, "DELETE FROM hr_candidate_tracking WHERE id=$id");
    $_SESSION['success_message'] = "Candidate deleted.";
    header("Location: $current_page"); exit;
}

// =========================================================================
// FETCH DATA
// =========================================================================
$departments_arr = [];
$dq = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
while ($d = mysqli_fetch_assoc($dq)) $departments_arr[] = $d;

$candidates = [];
$cq = mysqli_query($con, "SELECT * FROM hr_candidate_tracking ORDER BY id DESC");
while ($c = mysqli_fetch_assoc($cq)) $candidates[] = $c;

$added_by_list = [];
$abq = mysqli_query($con, "SELECT DISTINCT created_by FROM hr_candidate_tracking WHERE created_by <> '' ORDER BY created_by ASC");
while ($abr = mysqli_fetch_assoc($abq)) $added_by_list[] = $abr['created_by'];


// Full list (overdue + today + tomorrow) — used to populate the popup, which then
// defaults its own view to today via the date filter JS already applies.
$tomorrow_end   = date('Y-m-d 23:59:59', strtotime('+1 day'));
$alert_candidates = [];
$aq = mysqli_query($con, "SELECT * FROM hr_candidate_tracking
    WHERE trigger_datetime IS NOT NULL
      AND trigger_datetime <= '$tomorrow_end'
      AND current_status NOT IN ('Rejected','Hired','No Response','Not Interested')
    ORDER BY trigger_datetime ASC");
while ($a = mysqli_fetch_assoc($aq)) $alert_candidates[] = $a;

// Today-only count — this is what the top banner badge shows
$today_start = date('Y-m-d 00:00:00');
$today_end   = date('Y-m-d 23:59:59');
$today_count = 0;
$atq = mysqli_query($con, "SELECT COUNT(*) as cnt FROM hr_candidate_tracking
    WHERE trigger_datetime IS NOT NULL
      AND trigger_datetime BETWEEN '$today_start' AND '$today_end'
      AND current_status NOT IN ('Rejected','Hired','No Response','Not Interested')");
if ($atq) { $today_row = mysqli_fetch_assoc($atq); $today_count = intval($today_row['cnt']); }


?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?php echo htmlspecialchars($companyName); ?> | HR Candidate Tracking</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>

<style>
:root {
    --primary:    #1e3a8a;
    --primary-lt: #1e40af;
    --accent:     #6366f1;
    --success:    #10b981;
    --danger:     #ef4444;
    --warning:    #f59e0b;
    --bg:         #f1f5f9;
    --card:       #ffffff;
    --border:     #e2e8f0;
    --text:       #1e293b;
    --muted:      #64748b;
}

* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Inter',sans-serif; background:var(--bg); min-height:100vh; color:var(--text); }

/* ── Layout ── */
.page-wrap { max-width:1600px; margin:0 auto; padding:24px 20px; }

/* ── Header ── */
.page-header {
    background: linear-gradient(135deg, var(--primary) 0%, var(--primary-lt) 100%);
    padding:22px 30px; border-radius:14px;
    box-shadow:0 4px 20px rgba(30,58,138,.25);
    display:flex; justify-content:space-between; align-items:center;
    margin-bottom:22px;
}
.page-header h1 { color:#fff; font-weight:700; font-size:1.6rem; margin:0; }
.page-header .back-btn {
    background:rgba(255,255,255,.15); color:#fff; border:2px solid rgba(255,255,255,.3);
    padding:9px 20px; border-radius:9px; font-weight:600; text-decoration:none;
    transition:.2s;
}
.page-header .back-btn:hover { background:rgba(255,255,255,.25); color:#fff; text-decoration:none; }

/* ── Alert Banner ── */
.alert-banner {
    background:linear-gradient(135deg,#f97316,#ea580c);
    border-radius:12px; padding:14px 22px;
    display:flex; align-items:center; gap:14px;
    color:#fff; font-weight:600; margin-bottom:22px;
    cursor:pointer; box-shadow:0 4px 14px rgba(249,115,22,.35);
    animation: gentlePulse 2.5s infinite;
}
@keyframes gentlePulse { 0%,100%{opacity:1} 50%{opacity:.85} }
.alert-banner i { font-size:1.3rem; }
.alert-banner .count-pill {
    background:rgba(255,255,255,.25); border-radius:20px;
    padding:3px 12px; font-size:.85rem;
}

/* ── Action bar ── */
.action-bar {
    background:var(--card); border-radius:12px;
    padding:18px 22px; margin-bottom:20px;
    display:flex; gap:12px; align-items:center; flex-wrap:wrap;
    box-shadow:0 2px 10px rgba(0,0,0,.07);
}
.btn-primary-custom {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; border:none; padding:11px 24px; border-radius:10px;
    font-weight:700; font-size:14px; cursor:pointer;
    display:inline-flex; align-items:center; gap:8px;
    transition:.25s; box-shadow:0 3px 12px rgba(30,58,138,.28);
}
.btn-primary-custom:hover { transform:translateY(-2px); box-shadow:0 6px 20px rgba(30,58,138,.4); }

/* ── Search bar ── */
.search-wrap { flex:1; min-width:220px; position:relative; }
.search-wrap input {
    width:100%; padding:11px 16px 11px 42px;
    border:2px solid var(--border); border-radius:10px;
    font-size:14px; font-weight:500; color:var(--text);
    transition:.2s;
}
.search-wrap input:focus { outline:none; border-color:var(--primary-lt); }
.search-wrap i { position:absolute; left:14px; top:50%; transform:translateY(-50%); color:var(--muted); }

/* ── Table card ── */
.table-card {
    background:var(--card); border-radius:14px;
    box-shadow:0 2px 12px rgba(0,0,0,.08);
    overflow:hidden;
}
.table-card-header {
    padding:18px 22px; border-bottom:2px solid var(--border);
    display:flex; justify-content:space-between; align-items:center;
}
.table-card-header h5 { font-weight:700; color:var(--primary); margin:0; }
.table-scroll { overflow-x:auto; overflow-y:auto; max-height:68vh; cursor:grab; }
.table-scroll:active { cursor:grabbing; }

/* ── Table styles ── */
.ctrack-table { width:100%; border-collapse:collapse; min-width:1200px; }
.ctrack-table thead th {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; font-weight:700; font-size:13px;
    padding:14px 14px; white-space:nowrap;
    border-right:1px solid rgba(255,255,255,.15);
    position:sticky; top:0; z-index:10;
}
.ctrack-table thead th:last-child { border-right:none; }
.ctrack-table tbody tr { border-bottom:1px solid #f1f5f9; transition:.15s; }
.ctrack-table tbody tr:hover { background:#f8fafc; }
.ctrack-table tbody td {
    padding:13px 14px; font-size:13px; font-weight:500;
    color:var(--text); white-space:nowrap; vertical-align:middle;
}
.ctrack-table tbody td.note-cell {
    max-width:200px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
}
.sl-cell { font-weight:700; color:var(--muted); text-align:center; width:52px; }
.name-cell { font-weight:700; color:var(--primary); }
.empty-state {
    text-align:center; padding:70px 20px; color:var(--muted);
}
.empty-state i { font-size:52px; margin-bottom:14px; opacity:.3; display:block; }

/* ── Status badge ── */
.status-badge {
    display:inline-block; padding:5px 13px; border-radius:20px;
    font-size:12px; font-weight:700; color:#fff;
    white-space:nowrap;
}

/* ── Trigger datetime cell ── */
.trigger-cell { color:var(--warning); font-weight:700; font-size:12px; }
.trigger-cell.overdue { color:var(--danger); }
.trigger-cell.today   { color:var(--success); }

/* ── Action buttons ── */
.act-btn {
    display:inline-flex; align-items:center; justify-content:center;
    width:32px; height:32px; border-radius:8px; border:none;
    font-size:13px; cursor:pointer; transition:.2s; text-decoration:none;
    margin:0 2px;
}
.act-btn:hover { transform:scale(1.12); text-decoration:none; }
.act-view   { background:#e0f2fe; color:#0284c7; }
.act-edit   { background:#e0e7ff; color:#4f46e5; }
.act-status { background:#d1fae5; color:#059669; }
.act-log    { background:#fef3c7; color:#d97706; }
.act-wa     { background:#dcfce7; color:#16a34a; }
.act-del    { background:#fee2e2; color:#dc2626; }

/* ── Pagination ── */
.paging-wrap {
    padding:18px 22px; display:flex; align-items:center;
    justify-content:space-between; border-top:2px solid var(--border);
    flex-wrap:wrap; gap:12px;
}
.paging-info { color:var(--muted); font-size:13px; font-weight:600; }
.paging-btns { display:flex; gap:6px; }
.paging-btn {
    padding:7px 14px; border-radius:8px; border:2px solid var(--border);
    background:#fff; color:var(--primary); font-weight:700; font-size:13px;
    cursor:pointer; transition:.2s;
}
.paging-btn:hover, .paging-btn.active { background:var(--primary); color:#fff; border-color:var(--primary); }
.paging-btn:disabled { opacity:.4; cursor:not-allowed; }

/* ── Modals ── */
.modal-content { border-radius:14px; border:none; box-shadow:0 10px 40px rgba(0,0,0,.18); }
.modal-header {
    background:linear-gradient(135deg,var(--primary),var(--primary-lt));
    color:#fff; border-radius:14px 14px 0 0; padding:20px 26px;
    border-bottom:none;
}
.modal-title { font-weight:700; font-size:1.1rem; }
.modal-header .close { color:#fff; opacity:.9; text-shadow:none; font-size:24px; }
.modal-body { padding:26px; }
.modal-footer { padding:16px 26px; border-top:2px solid var(--border); }

.form-label { font-weight:600; font-size:13px; color:var(--muted); margin-bottom:6px; display:block; }
.form-control-ct {
    width:100%; padding:10px 14px;
    border:2px solid var(--border); border-radius:9px;
    font-size:14px; font-weight:500; color:var(--text);
    transition:.2s; background:#fff;
}
.form-control-ct:focus { outline:none; border-color:var(--primary-lt); box-shadow:0 0 0 3px rgba(30,64,175,.1); }
.req-star { color:var(--danger); margin-left:3px; }
.optional-tag { color:var(--muted); font-size:11px; font-weight:500; margin-left:6px; }
.section-divider { border:none; border-top:2px dashed var(--border); margin:20px 0; }

/* ── Log timeline ── */
.log-timeline { max-height:420px; overflow-y:auto; padding-right:4px; }
.log-item {
    display:flex; gap:14px; margin-bottom:20px;
}
.log-dot {
    width:38px; height:38px; border-radius:50%;
    display:flex; align-items:center; justify-content:center;
    font-size:14px; color:#fff; flex-shrink:0;
}
.log-body {
    flex:1; background:#f8fafc; border-radius:10px;
    padding:12px 16px; border-left:3px solid var(--border);
}
.log-status { font-weight:700; font-size:14px; color:var(--primary); margin-bottom:4px; }
.log-note { font-size:13px; color:var(--text); margin-bottom:6px; }
.log-meta { font-size:12px; color:var(--muted); }
.log-trigger { font-size:12px; color:var(--warning); font-weight:600; margin-top:4px; }

/* ── View detail card ── */
.detail-row { display:flex; gap:0; margin-bottom:14px; border-radius:10px; overflow:hidden; border:2px solid var(--border); }
.detail-label { background:#f8fafc; padding:10px 16px; font-weight:700; font-size:13px; color:var(--muted); min-width:160px; border-right:2px solid var(--border); }
.detail-value { padding:10px 16px; font-size:14px; font-weight:600; color:var(--text); flex:1; }
.doc-dl-btn {
    display:inline-flex; align-items:center; gap:7px;
    background:var(--primary); color:#fff; padding:8px 18px;
    border-radius:9px; font-weight:700; font-size:13px; text-decoration:none;
    transition:.2s;
}
.doc-dl-btn:hover { background:var(--primary-lt); color:#fff; text-decoration:none; transform:translateY(-1px); }
.doc-dl-btn.jd { background:#8b5cf6; }
.doc-dl-btn.jd:hover { background:#7c3aed; }

/* ── WhatsApp Preview ── */
.wa-preview-box {
    background:#e7ffdb; border-radius:12px; padding:16px 18px;
    font-size:14px; font-weight:500; color:#1a472a;
    border-left:4px solid #25d366; white-space:pre-wrap;
    line-height:1.6; margin-bottom:16px;
    font-family:'Inter',sans-serif;
}

/* ── Responsive ── */
@media(max-width:768px) {
    .page-header { flex-direction:column; gap:14px; text-align:center; }
    .action-bar  { flex-direction:column; }
}

/* Custom scrollbar */
.table-scroll::-webkit-scrollbar,
.log-timeline::-webkit-scrollbar { width:8px; height:8px; }
.table-scroll::-webkit-scrollbar-track,
.log-timeline::-webkit-scrollbar-track { background:#f1f5f9; border-radius:6px; }
.table-scroll::-webkit-scrollbar-thumb { background:linear-gradient(135deg,var(--primary),var(--primary-lt)); border-radius:6px; }
</style>
</head>
<body>
<div class="page-wrap">

<?php
// Flash messages
if (isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show" style="border-radius:10px;margin-bottom:16px;">
    <i class="fas fa-check-circle mr-2"></i><?php echo htmlspecialchars($_SESSION['success_message']); ?>
    <button type="button" class="close" data-dismiss="alert">&times;</button>
</div>
<?php unset($_SESSION['success_message']); endif;
if (isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show" style="border-radius:10px;margin-bottom:16px;">
    <i class="fas fa-exclamation-circle mr-2"></i><?php echo htmlspecialchars($_SESSION['error_message']); ?>
    <button type="button" class="close" data-dismiss="alert">&times;</button>
</div>
<?php unset($_SESSION['error_message']); endif; ?>

<!-- Header -->
<div class="page-header">
    <h1><i class="fas fa-user-clock mr-2"></i>HR Candidate Tracking</h1>
    
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    <a href="<?php echo $dashboard_url; ?>" class="btn-action btn-dashboard" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); box-shadow: 0 4px 15px rgba(139, 92, 246, 0.3); color: white; text-decoration: none; padding: 10px 20px; border-radius: 8px; font-weight: 600; display: inline-flex; align-items: center; gap: 8px; transition: all 0.3s; margin-right: 15px;">
      <i class="fas fa-arrow-left"></i> Back to Dashboard
    </a>

</div>

<!-- Upcoming Alert Banner (today only) -->
<?php if ($today_count > 0): ?>
<div class="alert-banner" onclick="$('#alertModal').modal('show')">
    <i class="fas fa-bell"></i>
    <span><?php echo $today_count; ?> follow-up<?php echo $today_count > 1 ? 's' : ''; ?> due today</span>
    <span class="count-pill"><?php echo $today_count; ?> pending</span>
    <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
</div>
<?php elseif (!empty($alert_candidates)): ?>
<div class="alert-banner" style="background:linear-gradient(135deg,#94a3b8,#64748b);" onclick="$('#alertModal').modal('show')">
    <i class="fas fa-bell"></i>
    <span>No follow-ups due today &mdash; <?php echo count($alert_candidates); ?> overdue/upcoming pending</span>
    <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
</div>
<?php endif; ?>

<!-- Action Bar -->
<div class="action-bar">
    <button class="btn-primary-custom" data-toggle="modal" data-target="#addModal" onclick="document.getElementById('addCandidateForm').reset(); document.getElementById('add_location_other').style.display='none'; document.getElementById('add_source_other').style.display='none'; document.getElementById('dupWarningBox').style.display='none';">
        <i class="fas fa-user-plus"></i> Add Candidate
    </button>
    <div class="search-wrap">
        <i class="fas fa-search"></i>
        <input type="text" id="globalSearch" placeholder="Search by name, phone, department, position, source, added by…">
    </div>
    <input type="date" id="filterDateFrom" class="form-control-ct" style="width:150px;" title="From date">
    <input type="date" id="filterDateTo" class="form-control-ct" style="width:150px;" title="To date">
    <select id="filterAddedBy" class="form-control-ct" style="width:170px;">
        <option value="">All — Added By</option>
        <?php foreach ($added_by_list as $ab): ?>
        <option value="<?php echo strtolower(htmlspecialchars($ab)); ?>"><?php echo htmlspecialchars($ab); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterStatusDropdown" class="form-control-ct" style="width:170px;">
        <option value="">All Statuses</option>
        <?php foreach ($all_statuses as $st): ?>
        <option value="<?php echo htmlspecialchars($st); ?>"><?php echo htmlspecialchars($st); ?></option>
        <?php endforeach; ?>
    </select>
    <select id="filterLocation" class="form-control-ct" style="width:170px;">
        <option value="">All Locations</option>
        <?php foreach ($candidate_locations as $loc): if ($loc === 'Other') continue; ?>
        <option value="<?php echo strtolower(htmlspecialchars($loc)); ?>"><?php echo htmlspecialchars($loc); ?></option>
        <?php endforeach; ?>
    </select>
    <button class="btn-primary-custom" style="background:linear-gradient(135deg,#10b981,#059669);" onclick="exportTrackingCSV()">
        <i class="fas fa-file-export"></i> Export
    </button>
</div>

<!-- Table Card -->
<div class="table-card">
    <div class="table-card-header">
        <h5><i class="fas fa-list mr-2"></i>Candidate List</h5>
        <span id="tableCount" style="font-size:13px;color:var(--muted);font-weight:600;"></span>
    </div>
    <div class="table-scroll" id="tableScroll">
        <table class="ctrack-table" id="candidateTable">
            <thead>
                <tr>
                    <th class="sl-cell">#</th>
                    <th>Name</th>
                    <th>Phone</th>
                    <th>Department</th>
                    <th>Position</th>
                    <th>Source</th>
                    <th>Location</th>
                    <th>Status</th>
                    <th>Trigger Date / Time</th>
                    <th>Last Note</th>
                    <th>Added By</th>
                    <th>Last Updated By</th>
                    <th style="text-align:center;">Actions</th>
                </tr>
            </thead>
            <tbody id="candidateTbody">
            <?php if (empty($candidates)): ?>
                <tr><td colspan="12">
                    <div class="empty-state">
                        <i class="fas fa-users"></i>
                        <p style="font-weight:700;font-size:16px;">No candidates yet.</p>
                        <p style="font-size:13px;">Click <strong>Add Candidate</strong> to get started.</p>
                    </div>
                </td></tr>
            <?php else:
                $sl = count($candidates);
                foreach ($candidates as $c):
                    $sc   = $status_colors[$c['current_status']] ?? '#6b7280';
                    $tdt  = $c['trigger_datetime'];
                    $tdt_display = '';
                    $tdt_class   = 'trigger-cell';
                    if ($tdt) {
                        $tts = strtotime($tdt);
                        $now = time();
                        $tdt_display = date('d M Y, h:i A', $tts);
                        if ($tts < $now)            $tdt_class .= ' overdue';
                        elseif (date('Y-m-d',$tts) == date('Y-m-d')) $tdt_class .= ' today';
                    }
                    $note_short = $c['last_note'] ? (mb_strlen($c['last_note']) > 60 ? mb_substr($c['last_note'],0,60).'…' : $c['last_note']) : '—';
                    $has_wa = !empty($c['phone']);
            ?>
                <tr class="candidate-row"
                    data-status="<?php echo htmlspecialchars($c['current_status']); ?>"
                    data-createdby="<?php echo strtolower(htmlspecialchars($c['created_by'])); ?>"
                    data-created="<?php echo date('Y-m-d', strtotime($c['created_at'])); ?>"
                    data-trigger="<?php echo !empty($c['trigger_datetime']) ? date('Y-m-d', strtotime($c['trigger_datetime'])) : ''; ?>"
                    data-location="<?php echo strtolower(htmlspecialchars($c['location'] ?? '')); ?>"
                    data-search="<?php echo strtolower(htmlspecialchars($c['name'].' '.$c['phone'].' '.$c['department_name'].' '.$c['position_name'].' '.$c['email'].' '.$c['current_status'].' '.($c['candidate_source'] ?? '').' '.($c['location'] ?? '').' '.($c['last_note'] ?? '').' '.$c['created_by'])); ?>">
                    <td class="sl-cell"><?php echo $sl--; ?></td>
                    <td class="name-cell"><?php echo htmlspecialchars($c['name']); ?></td>
                    <td><?php echo htmlspecialchars($c['phone']); ?></td>
                    <td><?php echo htmlspecialchars($c['department_name']); ?></td>
                    <td><?php echo htmlspecialchars($c['position_name']); ?></td>
                    <td><?php echo htmlspecialchars($c['candidate_source'] ?? '') ?: '—'; ?></td>
                    <td><?php echo htmlspecialchars($c['location'] ?? '') ?: '—'; ?></td>
                    <td>
                        <select class="status-dropdown"
                            data-id="<?php echo $c['id']; ?>"
                            data-name="<?php echo htmlspecialchars(addslashes($c['name'])); ?>"
                            data-current="<?php echo htmlspecialchars($c['current_status']); ?>"
                            style="background:<?php echo $sc; ?>;color:#fff;border:none;border-radius:20px;padding:6px 26px 6px 12px;font-size:12px;font-weight:700;cursor:pointer;appearance:none;-webkit-appearance:none;-moz-appearance:none;background-image:url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 24 24%22 fill=%22white%22><path d=%22M7 10l5 5 5-5z%22/></svg>');background-repeat:no-repeat;background-position:right 8px center;background-size:14px;"
                            onchange="handleStatusDropdownChange(this)">
                            <?php foreach ($all_statuses as $st): ?>
                            <option value="<?php echo htmlspecialchars($st); ?>" <?php echo ($c['current_status'] === $st) ? 'selected' : ''; ?> style="background:#fff;color:#1e293b;"><?php echo htmlspecialchars($st); ?></option>
                            <?php endforeach; ?>
                        </select>
                        <?php if ($c['current_status'] === 'Rejected' && !empty($c['rejected_round'])): ?>
                        <div style="font-size:11px;color:#dc2626;font-weight:700;margin-top:3px;"><i class="fas fa-flag mr-1"></i><?php echo htmlspecialchars($c['rejected_round']); ?></div>
                        <?php endif; ?>
                    </td>
                    <td class="<?php echo $tdt_class; ?>"><?php echo $tdt_display ?: '—'; ?></td>
                    <td class="note-cell" title="<?php echo htmlspecialchars($c['last_note'] ?? ''); ?>"><?php echo htmlspecialchars($note_short); ?></td>
                    <td><?php echo htmlspecialchars($c['created_by']); ?></td>
                    <td><?php echo htmlspecialchars($c['last_updated_by']); ?></td>
                    <td style="text-align:center;white-space:nowrap;">
                        <!-- View -->
                        <button class="act-btn act-view" title="View Details"
                            onclick="openView(<?php echo $c['id']; ?>)">
                            <i class="fas fa-eye"></i>
                        </button>
                        <!-- Edit -->
                        <button class="act-btn act-edit" title="Edit"
                            onclick="openEdit(<?php echo $c['id']; ?>)">
                            <i class="fas fa-edit"></i>
                        </button>
                        <!-- Update Status -->
                        <button class="act-btn act-status" title="Update Status"
                            onclick="openStatus(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-sync-alt"></i>
                        </button>
                        <!-- Log -->
                        <button class="act-btn act-log" title="View History Log"
                            onclick="openLog(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-history"></i>
                        </button>
                        <!-- Email (always visible) -->
                        <?php
                            $row_phone_clean = preg_replace('/[^0-9]/', '', $c['phone'] ?? '');
                            if (strlen($row_phone_clean) === 10) $row_phone_clean = '91' . $row_phone_clean;
                            $row_tdt_label = $tdt_display ?: 'the scheduled time';
                        ?>
                        <button class="act-btn" title="Send Email Notification"
                            style="background:#dbeafe;color:#1d4ed8;"
                            onclick="openNotify(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>', '<?php echo htmlspecialchars(addslashes($c['phone'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($c['email'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($c['current_status'])); ?>', '<?php echo htmlspecialchars(addslashes($row_tdt_label)); ?>')">
                            <i class="fas fa-envelope"></i>
                        </button>
                        <!-- WhatsApp (always visible) -->
                        <button class="act-btn act-wa" title="Send WhatsApp Notification"
                            onclick="openNotifyWA(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>', '<?php echo $row_phone_clean; ?>', '<?php echo htmlspecialchars(addslashes($c['current_status'])); ?>', '<?php echo htmlspecialchars(addslashes($row_tdt_label)); ?>')">
                            <i class="fab fa-whatsapp"></i>
                        </button>
                        <!-- Delete -->
                        <button class="act-btn act-del" title="Delete"
                            onclick="doDelete(<?php echo $c['id']; ?>, '<?php echo htmlspecialchars(addslashes($c['name'])); ?>')">
                            <i class="fas fa-trash"></i>
                        </button>
                    </td>

                </tr>
            <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
    <div class="paging-wrap">
        <div class="paging-info" id="pagingInfo"></div>
        <div class="paging-btns" id="pagingBtns"></div>
    </div>
</div>

</div><!-- /page-wrap -->

<!-- =====================================================================
     MODAL: ADD CANDIDATE
===================================================================== -->
<div class="modal fade" id="addModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <form method="POST" enctype="multipart/form-data" id="addCandidateForm" onsubmit="return validateAddCandidateForm(event)">
    <input type="hidden" name="action" value="add_candidate">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-user-plus mr-2"></i>Add New Candidate</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <!-- Department + Position -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Department <span class="optional-tag">(optional)</span></label>
                <select name="department_id" id="add_dept" class="form-control-ct"
                    onchange="fetchPositions(this.value,'add_pos','add_dept_name','add_pos_name')">
                    <option value="">Select Department…</option>
                    <?php foreach ($departments_arr as $d): ?>
                    <option value="<?php echo $d['id']; ?>" data-name="<?php echo htmlspecialchars($d['name']); ?>">
                        <?php echo htmlspecialchars($d['name']); ?>
                    </option>
                    <?php endforeach; ?>
                </select>
                <input type="hidden" name="department_name" id="add_dept_name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Position <span class="optional-tag">(optional)</span></label>
                <select name="position_id" id="add_pos" class="form-control-ct">
                    <option value="">Select Position…</option>
                </select>
                <input type="hidden" name="position_name" id="add_pos_name">
            </div>
        </div>
        <hr class="section-divider">
        <!-- Name + Phone -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Full Name <span class="req-star">*</span></label>
                <input type="text" name="name" class="form-control-ct" required placeholder="Candidate full name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Phone Number <span class="req-star">*</span></label>
                <input type="text" name="phone" id="add_phone" class="form-control-ct" required placeholder="e.g. 9876543210">
            </div>
        </div>
        <!-- Email -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Email <span class="optional-tag">(optional)</span></label>
                <input type="email" name="email" id="add_email" class="form-control-ct" placeholder="candidate@email.com">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Candidate Source <span class="optional-tag">(optional)</span></label>
                <select name="candidate_source" id="add_candidate_source" class="form-control-ct" onchange="toggleLocationOther(this,'add_source_other')">
                    <option value="">Select Source…</option>
                    <?php foreach ($candidate_sources as $src): ?>
                    <option value="<?php echo htmlspecialchars($src); ?>"><?php echo htmlspecialchars($src); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="candidate_source_other" id="add_source_other" class="form-control-ct" placeholder="Enter source" style="display:none;margin-top:8px;">
            </div>
        </div>
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Location <span class="optional-tag">(optional — recruiting location)</span></label>
                <select name="location_select" id="add_location_select" class="form-control-ct" onchange="toggleLocationOther(this,'add_location_other')">
                    <option value="">Select Location…</option>
                    <?php foreach ($candidate_locations as $loc): ?>
                    <option value="<?php echo htmlspecialchars($loc); ?>"><?php echo htmlspecialchars($loc); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="location_other" id="add_location_other" class="form-control-ct" placeholder="Enter location" style="display:none;margin-top:8px;">
            </div>
        </div>
        <input type="hidden" name="confirm_duplicate" id="add_confirm_duplicate" value="">
        <div id="dupWarningBox" style="display:none;background:#fff7ed;border:1px solid #fcd34d;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#92400e;margin-bottom:12px;"></div>
        <hr class="section-divider">
        <!-- Resume + JD -->
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Resume <span class="optional-tag">(PDF/DOC/DOCX)</span></label>
                <input type="file" name="resume" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Job Description (JD) <span class="optional-tag">(PDF/DOC/DOCX)</span></label>
                <input type="file" name="jd" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom"><i class="fas fa-save mr-1"></i> Save Candidate</button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: EDIT CANDIDATE
===================================================================== -->
<div class="modal fade" id="editModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
    <input type="hidden" name="action" value="edit_candidate">
    <input type="hidden" name="id" id="edit_id">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit mr-2"></i>Edit Candidate</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Department <span class="req-star">*</span></label>
                <select name="department_id" id="edit_dept" class="form-control-ct" required
                    onchange="fetchPositions(this.value,'edit_pos','edit_dept_name','edit_pos_name')">
                    <option value="">Select Department…</option>
                    <?php foreach ($departments_arr as $d): ?>
                    <option value="<?php echo $d['id']; ?>" data-name="<?php echo htmlspecialchars($d['name']); ?>">
                        <?php echo htmlspecialchars($d['name']); ?>
                    </option>
                    <?php endforeach; ?>
                </select>
                <input type="hidden" name="department_name" id="edit_dept_name">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Position <span class="req-star">*</span></label>
                <select name="position_id" id="edit_pos" class="form-control-ct" required>
                    <option value="">Select Position…</option>
                </select>
                <input type="hidden" name="position_name" id="edit_pos_name">
            </div>
        </div>
        <hr class="section-divider">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Full Name <span class="req-star">*</span></label>
                <input type="text" name="name" id="edit_name" class="form-control-ct" required>
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Phone Number <span class="req-star">*</span></label>
                <input type="text" name="phone" id="edit_phone" class="form-control-ct" required>
            </div>
        </div>
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Email <span class="optional-tag">(optional)</span></label>
                <input type="email" name="email" id="edit_email" class="form-control-ct">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Location <span class="optional-tag">(optional — recruiting location)</span></label>
                <select name="location_select" id="edit_location_select" class="form-control-ct" onchange="toggleLocationOther(this,'edit_location_other')">
                    <option value="">Select Location…</option>
                    <?php foreach ($candidate_locations as $loc): ?>
                    <option value="<?php echo htmlspecialchars($loc); ?>"><?php echo htmlspecialchars($loc); ?></option>
                    <?php endforeach; ?>
                </select>
                <input type="text" name="location_other" id="edit_location_other" class="form-control-ct" placeholder="Enter location" style="display:none;margin-top:8px;">
            </div>
        </div>
        <hr class="section-divider">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Replace Resume <span class="optional-tag">(leave blank to keep existing)</span></label>
                <input type="file" name="resume" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
            <div class="col-md-6 mb-3">
                <label class="form-label">Replace JD <span class="optional-tag">(leave blank to keep existing)</span></label>
                <input type="file" name="jd" class="form-control-ct" accept=".pdf,.doc,.docx" style="padding:7px;">
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom"><i class="fas fa-save mr-1"></i> Update Candidate</button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: UPDATE STATUS
===================================================================== -->
<div class="modal fade" id="statusModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
    <form method="POST">
    <input type="hidden" name="action" value="update_status">
    <input type="hidden" name="id" id="status_id">
    <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-sync-alt mr-2"></i>Update Status — <span id="status_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="mb-3">
            <label class="form-label">Status <span class="req-star">*</span></label>
            <select name="status" id="status_select" class="form-control-ct" required onchange="toggleTrigger(this.value); toggleRejectFields(this.value)">
                <?php foreach ($all_statuses as $st): ?>
                <option value="<?php echo $st; ?>"><?php echo $st; ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="mb-3" id="trigger_wrap" style="display:none;">
            <label class="form-label">
                <i class="fas fa-calendar-alt mr-1" style="color:var(--warning)"></i>
                Schedule Date &amp; Time <span class="req-star" id="trigger_required_star">*</span>
            </label>
            <input type="datetime-local" name="trigger_datetime" id="status_trigger" class="form-control-ct">
            <small style="color:var(--muted);font-size:12px;margin-top:5px;display:block;">
                <i class="fas fa-info-circle mr-1"></i>This will trigger an alert banner on the day and 1 day before.
            </small>
        </div>
        <div class="mb-3" id="reject_wrap" style="display:none;background:#fef2f2;border:1px solid #fecaca;border-radius:9px;padding:14px 16px;">
            <label class="form-label" style="color:#991b1b;margin-bottom:10px;">
                <i class="fas fa-times-circle mr-1"></i>Rejection Details
            </label>
            <div class="mb-2">
                <label class="form-label" style="font-size:12px;">Rejected At <span class="optional-tag">(round or stage — leave blank for "Overall")</span></label>
                <input type="text" name="reject_round" id="reject_round" class="form-control-ct" placeholder="e.g. Round 2, Telephonic Screening, Overall">
            </div>
            <div>
                <label class="form-label" style="font-size:12px;">Rejection Reason <span class="req-star">*</span></label>
                <textarea name="reject_reason" id="reject_reason" class="form-control-ct" rows="3" placeholder="Why is this candidate being rejected?"></textarea>
            </div>
        </div>
        <div class="mb-3" id="current_note_display" style="display:none;">
            <label class="form-label">Current Note <span class="optional-tag">(kept automatically if you leave the box below blank)</span></label>
            <div style="background:#f8fafc;padding:10px 14px;border-radius:8px;font-size:13px;color:var(--text);border:1px solid var(--border);" id="current_note_text"></div>
        </div>
        <div class="mb-3">
            <label class="form-label">Notes / Remarks</label>
            <textarea name="notes" class="form-control-ct" rows="4" placeholder="Leave blank to keep the existing note above, or type a new one to replace it…"></textarea>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn-primary-custom" style="background:linear-gradient(135deg,#10b981,#059669);">
            <i class="fas fa-check mr-1"></i> Save Status
        </button>
    </div>
    </form>
</div></div></div>

<!-- =====================================================================
     MODAL: VIEW DETAILS
===================================================================== -->
<div class="modal fade" id="viewModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#4f46e5,#6366f1);">
        <h5 class="modal-title"><i class="fas fa-user mr-2"></i>Candidate Details — <span id="view_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" id="viewBody">
        <div style="text-align:center;padding:40px;">
            <i class="fas fa-spinner fa-spin fa-2x" style="color:var(--primary)"></i>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: HISTORY LOG
===================================================================== -->
<div class="modal fade" id="logModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#d97706,#f59e0b);">
        <h5 class="modal-title"><i class="fas fa-history mr-2"></i>History Log — <span id="log_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <div class="log-timeline" id="logTimeline">
            <div style="text-align:center;padding:40px;">
                <i class="fas fa-spinner fa-spin fa-2x" style="color:var(--warning)"></i>
            </div>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: WHATSAPP
===================================================================== -->
<div class="modal fade" id="waModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title"><i class="fab fa-whatsapp mr-2"></i>Send WhatsApp Reminder</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            This pre-filled message will open in WhatsApp Web / App. You can edit it before sending.
        </p>
        <label class="form-label">Preview Message</label>
        <div class="wa-preview-box" id="waPreview"></div>
        <div style="font-size:13px;color:var(--muted);">
            <i class="fas fa-phone mr-1"></i> Sending to: <strong id="waPhone"></strong>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <a id="waLink" href="#" target="_blank" class="btn btn-success" style="font-weight:700;border-radius:9px;padding:10px 22px;">
            <i class="fab fa-whatsapp mr-1"></i> Open WhatsApp
        </a>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: ALERT — Upcoming Follow-ups
===================================================================== -->
<div class="modal fade" id="alertModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f97316,#ea580c);">
        <h5 class="modal-title"><i class="fas fa-bell mr-2"></i>Upcoming Follow-ups / Scheduled Calls</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <?php if (empty($alert_candidates)): ?>
            <div style="text-align:center;padding:40px;color:var(--muted);">
                <i class="fas fa-check-circle fa-3x" style="margin-bottom:14px;opacity:.3;"></i>
                <p>No upcoming follow-ups.</p>
            </div>
        <?php else: ?>
            <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px;background:#f8fafc;border-radius:10px;padding:12px 16px;">
                <input type="date" id="alertDateFrom" class="form-control-ct" style="width:150px;" title="From date">
                <input type="date" id="alertDateTo" class="form-control-ct" style="width:150px;" title="To date">
                <select id="alertStatusFilter" class="form-control-ct" style="width:170px;">
                    <option value="">All Statuses</option>
                    <?php foreach ($trigger_statuses as $st): ?>
                    <option value="<?php echo htmlspecialchars($st); ?>"><?php echo htmlspecialchars($st); ?></option>
                    <?php endforeach; ?>
                </select>
                <button onclick="applyAlertFilter()" style="padding:9px 16px;border:none;border-radius:8px;background:#f97316;color:#fff;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-filter mr-1"></i>Filter</button>
                <button onclick="resetAlertFilterToday()" style="padding:9px 16px;border:1px solid #e2e8f0;border-radius:8px;background:#fff;color:#475569;font-weight:700;font-size:12px;cursor:pointer;">Today Only</button>
                <button onclick="exportAlertCSV()" style="padding:9px 16px;border:none;border-radius:8px;background:#10b981;color:#fff;font-weight:700;font-size:12px;cursor:pointer;margin-left:auto;"><i class="fas fa-file-export mr-1"></i>Export</button>
            </div>
            <div id="alertCardsContainer">
            <?php foreach ($alert_candidates as $ac):
                $sc    = $status_colors[$ac['current_status']] ?? '#6b7280';
                $tdt_f = date('d M Y, h:i A', strtotime($ac['trigger_datetime']));
                $is_today = date('Y-m-d', strtotime($ac['trigger_datetime'])) == date('Y-m-d');
                $is_overdue = strtotime($ac['trigger_datetime']) < time();
                $ac_phone_clean = preg_replace('/[^0-9]/', '', $ac['phone']);
                if (strlen($ac_phone_clean) === 10) $ac_phone_clean = '91' . $ac_phone_clean;
                $has_email = !empty($ac['email']);
            ?>
            <div class="alert-card-item"
                data-status="<?php echo htmlspecialchars($ac['current_status']); ?>"
                data-tdate="<?php echo date('Y-m-d', strtotime($ac['trigger_datetime'])); ?>"
                data-name="<?php echo htmlspecialchars($ac['name']); ?>"
                data-phone="<?php echo htmlspecialchars($ac['phone']); ?>"
                data-dept="<?php echo htmlspecialchars($ac['department_name']); ?>"
                data-pos="<?php echo htmlspecialchars($ac['position_name']); ?>"
                data-tdt="<?php echo htmlspecialchars($tdt_f); ?>"
                data-note="<?php echo htmlspecialchars($ac['last_note'] ?? ''); ?>"
                style="background:#f8fafc;border-radius:12px;padding:16px;margin-bottom:14px;border-left:4px solid <?php echo $sc; ?>;" >
                <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:14px;">
                    <div>
                        <div style="font-weight:700;font-size:15px;color:var(--primary);"><?php echo htmlspecialchars($ac['name']); ?></div>
                        <div style="font-size:12px;color:var(--muted);margin-top:3px;">
                            <i class="fas fa-phone mr-1"></i><?php echo htmlspecialchars($ac['phone']); ?>
                            &nbsp;|&nbsp;<i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($ac['department_name']); ?>
                            &nbsp;|&nbsp;<i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($ac['position_name']); ?>
                        </div>
                        <?php if ($ac['last_note']): ?>
                        <div style="font-size:12px;color:var(--text);margin-top:6px;"><i class="fas fa-sticky-note mr-1" style="color:var(--warning)"></i><?php echo htmlspecialchars(mb_substr($ac['last_note'],0,80)); ?></div>
                        <?php endif; ?>
                    </div>
                    <div style="text-align:right;flex-shrink:0;">
                        <span class="status-badge" style="background:<?php echo $sc; ?>;margin-bottom:7px;display:inline-block;"><?php echo htmlspecialchars($ac['current_status']); ?></span><br>
                        <span style="font-size:12px;font-weight:700;color:<?php echo $is_overdue ? '#ef4444' : ($is_today ? '#10b981' : '#f59e0b'); ?>">
                            <i class="fas fa-clock mr-1"></i><?php echo $tdt_f; ?>
                            <?php echo $is_overdue ? ' — <strong>OVERDUE</strong>' : ($is_today ? ' — <strong>TODAY</strong>' : ' — Tomorrow'); ?>
                        </span>
                    </div>
                </div>
                <!-- Notify Buttons -->
                <div style="display:flex;gap:8px;margin-top:12px;padding-top:10px;border-top:1px dashed #e2e8f0;">
                    <button type="button"
                        onclick="openNotify(<?php echo $ac['id']; ?>, '<?php echo htmlspecialchars(addslashes($ac['name'])); ?>', '<?php echo htmlspecialchars(addslashes($ac['phone'])); ?>', '<?php echo htmlspecialchars(addslashes($ac['email'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($ac['current_status'])); ?>', '<?php echo htmlspecialchars(addslashes($tdt_f)); ?>')"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#0077b5,#006097);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fas fa-envelope"></i> Email
                    </button>
                    <?php if (!empty($ac['phone'])): ?>
                    <button type="button"
                        onclick="openNotifyWA(<?php echo $ac['id']; ?>, '<?php echo htmlspecialchars(addslashes($ac['name'])); ?>', '<?php echo $ac_phone_clean; ?>', '<?php echo htmlspecialchars(addslashes($ac['current_status'])); ?>', '<?php echo htmlspecialchars(addslashes($tdt_f)); ?>')"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#25d366,#128c7e);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fab fa-whatsapp"></i> WhatsApp
                    </button>
                    <?php endif; ?>
                    <button type="button"
                        onclick="$('#alertModal').modal('hide'); setTimeout(function(){ openStatus(<?php echo $ac['id']; ?>, '<?php echo htmlspecialchars(addslashes($ac['name'])); ?>'); }, 400);"
                        style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                        <i class="fas fa-sync-alt"></i> Update Status
                    </button>
                </div>
            </div>
            <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- Delete form (hidden) -->
<form method="POST" id="deleteForm" style="display:none;">
    <input type="hidden" name="action" value="delete_candidate">
    <input type="hidden" name="id" id="delete_id">
</form>

<!-- =====================================================================
     MODAL: NOTIFY CANDIDATE (Email + WhatsApp)
===================================================================== -->
<div class="modal fade" id="notifyModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title"><i class="fas fa-paper-plane mr-2"></i>Notify Candidate — <span id="notify_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            Review and edit the messages below before sending via Email or WhatsApp.
        </p>
        <input type="hidden" id="notify_name_hidden">
        <input type="hidden" id="notify_tdt_hidden">
        <div style="margin-bottom:18px;">
            <label class="form-label">Sender Name <span class="optional-tag">(shown in &ldquo;Regards,&rdquo; &mdash; auto-filled, editable)</span></label>
            <input type="text" id="notify_sender_name" class="form-control-ct" oninput="regenerateNotifyMessages()" style="max-width:280px;">
        </div>

        <!-- Email Section -->
        <div style="background:#eff6ff;border-radius:12px;padding:20px;margin-bottom:18px;border:1px solid #bfdbfe;">
            <div style="font-weight:700;font-size:14px;color:#1d4ed8;margin-bottom:14px;">
                <i class="fas fa-envelope mr-2"></i>Send via Email
            </div>
            <div class="row">
                <div class="col-md-6 mb-3">
                    <label class="form-label">To (Email Address)</label>
                    <input type="email" id="notify_email_to" class="form-control-ct" placeholder="candidate@email.com">
                </div>
                <div class="col-md-6 mb-3">
                    <label class="form-label">Subject</label>
                    <input type="text" id="notify_email_subject" class="form-control-ct">
                </div>
            </div>
            <div class="mb-3">
                <label class="form-label">Email Body (Plain Text)</label>
                <textarea id="notify_email_body" class="form-control-ct" rows="6" style="resize:vertical;"></textarea>
            </div>
            <button type="button" onclick="sendNotifyEmail()" style="padding:10px 22px;border:none;border-radius:9px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;font-weight:700;font-size:13px;cursor:pointer;">
                <i class="fas fa-paper-plane mr-2"></i>Send Email
            </button>
            <span id="notify_email_status" style="font-size:12px;margin-left:12px;"></span>
        </div>

        <!-- WhatsApp Section -->
        <div style="background:#f0fdf4;border-radius:12px;padding:20px;border:1px solid #bbf7d0;">
            <div style="font-weight:700;font-size:14px;color:#15803d;margin-bottom:14px;">
                <i class="fab fa-whatsapp mr-2"></i>Send via WhatsApp
            </div>
            <div class="mb-3">
                <label class="form-label">WhatsApp Message</label>
                <textarea id="notify_wa_body" class="form-control-ct" rows="6" style="resize:vertical;font-family:'Inter',sans-serif;"></textarea>
            </div>
            <div style="font-size:13px;color:var(--muted);margin-bottom:12px;">
                <i class="fas fa-phone mr-1"></i> Sending to: <strong id="notify_wa_phone_display"></strong>
            </div>
            <a id="notify_wa_link" href="#" target="_blank"
                onclick="updateWALink()"
                style="display:inline-block;padding:10px 22px;border-radius:9px;background:linear-gradient(135deg,#16a34a,#22c55e);color:#fff;font-weight:700;font-size:13px;text-decoration:none;">
                <i class="fab fa-whatsapp mr-2"></i>Open WhatsApp
            </a>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<!-- =====================================================================
     Scripts
===================================================================== -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>

<script>
// ── Config from PHP ──────────────────────────────────────
var TRIGGER_STATUSES = <?php echo json_encode($trigger_statuses); ?>;
var TRIGGER_REQUIRED_STATUSES = <?php echo json_encode($trigger_required_statuses); ?>;
var STATUS_COLORS    = <?php echo json_encode($status_colors); ?>;
var COMPANY_NAME     = <?php echo json_encode($companyName); ?>;
var HR_NAME          = <?php echo json_encode($currentUser); ?>;

function validateAddCandidateForm(e) {
    if (document.getElementById('add_confirm_duplicate').value === '1') {
        return true; // Already confirmed
    }
    
    e.preventDefault();
    var form = e.target;
    var phone = document.getElementById('add_phone').value.trim();
    var email = document.getElementById('add_email').value.trim();
    var dept  = document.getElementById('add_dept_name').value.trim();
    var pos   = document.getElementById('add_pos_name').value.trim();
    var box = document.getElementById('dupWarningBox');
    
    if (!phone && !email) { form.submit(); return false; }
    
    var btn = form.querySelector('button[type="submit"]');
    var oldHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Checking...';
    
    fetch('<?php echo $current_page; ?>?check_duplicate=1&phone=' + encodeURIComponent(phone) + '&email=' + encodeURIComponent(email) + '&dept=' + encodeURIComponent(dept) + '&pos=' + encodeURIComponent(pos))
        .then(function(r) { return r.json(); })
        .then(function(res) {
            btn.disabled = false;
            btn.innerHTML = oldHtml;
            if (res.duplicate) {
                box.innerHTML = '<i class="fas fa-exclamation-triangle mr-1"></i> A candidate named <strong>' + res.name + '</strong> (ID #' + res.id + ', status: ' + res.status + ') already exists for this department and position.<br>' +
                    '<label style="margin-top:8px;font-weight:700;cursor:pointer;"><input type="checkbox" onchange="document.getElementById(\'add_confirm_duplicate\').value=this.checked?\'1\':\'\'" > I confirm this is a separate application (Add anyway)</label>';
                box.style.display = 'block';
            } else {
                document.getElementById('add_confirm_duplicate').value = '1';
                form.submit();
            }
        }).catch(function() {
            btn.disabled = false;
            btn.innerHTML = oldHtml;
            alert('Error checking duplicate.');
        });
    return false;
}

// ── Smooth horizontal scroll with mouse drag ─────────────
(function() {
    var el = document.getElementById('tableScroll');
    var isDown = false, startX, scrollLeft;
    el.addEventListener('mousedown', function(e) {
        isDown = true; el.style.cursor = 'grabbing';
        startX = e.pageX - el.offsetLeft; scrollLeft = el.scrollLeft;
    });
    el.addEventListener('mouseleave', function() { isDown = false; el.style.cursor = 'grab'; });
    el.addEventListener('mouseup',    function() { isDown = false; el.style.cursor = 'grab'; });
    el.addEventListener('mousemove',  function(e) {
        if (!isDown) return;
        e.preventDefault();
        var x = e.pageX - el.offsetLeft;
        el.scrollLeft = scrollLeft - (x - startX);
    });
})();

// ── Filter + Search + Pagination ──────────────────────────
var currentStatusFilter = '';
var currentSearch       = '';
var PAGE_SIZE           = 25;
var currentPage         = 1;

function getVisibleRows() {
    var dateFrom = document.getElementById('filterDateFrom') ? document.getElementById('filterDateFrom').value : '';
    var dateTo   = document.getElementById('filterDateTo')   ? document.getElementById('filterDateTo').value   : '';
    var addedBy  = document.getElementById('filterAddedBy')  ? document.getElementById('filterAddedBy').value  : '';
    var location = document.getElementById('filterLocation') ? document.getElementById('filterLocation').value : '';
    return Array.from(document.querySelectorAll('#candidateTbody .candidate-row')).filter(function(row) {
        var statusMatch  = !currentStatusFilter || row.dataset.status === currentStatusFilter;
        var searchMatch  = !currentSearch || row.dataset.search.includes(currentSearch.toLowerCase());
        
        var dateMatch = true;
        var cDate = row.dataset.created;
        var tDate = row.dataset.trigger;
        if (dateFrom || dateTo) {
            var cMatch = true;
            var tMatch = tDate ? true : false;
            
            if (dateFrom) {
                if (cDate < dateFrom) cMatch = false;
                if (tDate && tDate < dateFrom) tMatch = false;
            }
            if (dateTo) {
                if (cDate > dateTo) cMatch = false;
                if (tDate && tDate > dateTo) tMatch = false;
            }
            if (!cMatch && !tMatch) dateMatch = false;
        }
        var addedByMatch = !addedBy || row.dataset.createdby === addedBy;
        var locationMatch = !location || row.dataset.location === location;
        return statusMatch && searchMatch && dateMatch && addedByMatch && locationMatch;
    });
}

function exportTrackingCSV() {
    var rows = getVisibleRows();
    var csv = [['#','Name','Phone','Department','Position','Source','Location','Status','Trigger Date/Time','Last Note','Added By','Last Updated By'].join(',')];
    rows.forEach(function(row, i) {
        var cells = row.querySelectorAll('td');
        var line = [rows.length - i,
            cells[1].innerText, cells[2].innerText, cells[3].innerText, cells[4].innerText,
            cells[5].innerText, cells[6].innerText, cells[7].innerText, cells[8].innerText,
            cells[9].innerText, cells[10].innerText, cells[11].innerText
        ].map(function(v) { return '"' + String(v).replace(/"/g,'""').trim() + '"'; });
        csv.push(line.join(','));
    });
    var blob = new Blob(['\ufeff' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'Candidate_Tracking.csv';
    a.click();
}

document.getElementById('filterDateFrom') && document.getElementById('filterDateFrom').addEventListener('change', function(){ currentPage=1; renderTable(); });
document.getElementById('filterDateTo')   && document.getElementById('filterDateTo').addEventListener('change', function(){ currentPage=1; renderTable(); });
document.getElementById('filterAddedBy')  && document.getElementById('filterAddedBy').addEventListener('change', function(){ currentPage=1; renderTable(); });
document.getElementById('filterLocation') && document.getElementById('filterLocation').addEventListener('change', function(){ currentPage=1; renderTable(); });

function renderTable() {
    var rows     = getVisibleRows();
    var total    = rows.length;
    var maxPage  = Math.max(1, Math.ceil(total / PAGE_SIZE));
    if (currentPage > maxPage) currentPage = maxPage;
    var start    = (currentPage - 1) * PAGE_SIZE;
    var end      = start + PAGE_SIZE;

    // Show/hide all rows
    document.querySelectorAll('#candidateTbody .candidate-row').forEach(function(r) { r.style.display = 'none'; });
    rows.forEach(function(r, i) { r.style.display = (i >= start && i < end) ? '' : 'none'; });

    // Re-number sl column
    var visible = rows.filter(function(r, i) { return i >= start && i < end; });
    visible.forEach(function(r, i) { r.querySelector('.sl-cell').textContent = total - (start + i); });

    // Info
    document.getElementById('tableCount').textContent = total + ' candidate' + (total !== 1 ? 's' : '');
    document.getElementById('pagingInfo').textContent = total === 0 ? 'No results' :
        'Showing ' + (start + 1) + '–' + Math.min(end, total) + ' of ' + total;

    // Buttons
    var btnsEl = document.getElementById('pagingBtns');
    btnsEl.innerHTML = '';
    if (maxPage <= 1) return;
    var pages = buildPageRange(currentPage, maxPage);
    pages.forEach(function(p) {
        var btn = document.createElement('button');
        btn.className = 'paging-btn' + (p === currentPage ? ' active' : '') + (p === '…' ? ' disabled' : '');
        btn.textContent = p;
        btn.disabled    = (p === '…');
        if (p !== '…') btn.onclick = function() { currentPage = p; renderTable(); };
        btnsEl.appendChild(btn);
    });
}

function buildPageRange(current, max) {
    if (max <= 7) return Array.from({length:max}, function(_,i) { return i+1; });
    var pages = [1];
    if (current > 3)  pages.push('…');
    for (var i = Math.max(2,current-1); i <= Math.min(max-1,current+1); i++) pages.push(i);
    if (current < max-2) pages.push('…');
    pages.push(max);
    return pages;
}

// Status filter dropdown
document.getElementById('filterStatusDropdown').addEventListener('change', function() {
    currentStatusFilter = this.value;
    currentPage = 1;
    renderTable();
});

// Global search
document.getElementById('globalSearch').addEventListener('input', function() {
    currentSearch = this.value;
    currentPage   = 1;
    renderTable();
});

renderTable();

// ── Fetch positions dynamically ────────────────────────────
function fetchPositions(deptId, posSelectId, deptNameId, posNameId) {
    var deptSel = document.querySelector('[id="' + (deptId ? 'add_dept' : '') + '"], select[onchange*="' + posSelectId + '"]');
    // Get dept name from selected option
    var deptSelEl = document.getElementById(posSelectId === 'add_pos' ? 'add_dept' : 'edit_dept');
    if (deptSelEl) {
        var selOpt = deptSelEl.options[deptSelEl.selectedIndex];
        if (selOpt && document.getElementById(deptNameId)) {
            document.getElementById(deptNameId).value = selOpt.dataset.name || selOpt.text;
        }
    }
    var posEl = document.getElementById(posSelectId);
    posEl.innerHTML = '<option value="">Loading…</option>';
    if (!deptId) { posEl.innerHTML = '<option value="">Select Position…</option>'; return; }
    fetch('<?php echo $current_page; ?>?get_positions=1&dept_id=' + deptId)
        .then(function(r) { return r.json(); })
        .then(function(data) {
            posEl.innerHTML = '<option value="">Select Position…</option>';
            data.forEach(function(p) {
                posEl.innerHTML += '<option value="' + p.id + '" data-name="' + p.title + '">' + p.title + '</option>';
            });
            // Update position name on change
            posEl.onchange = function() {
                var opt = posEl.options[posEl.selectedIndex];
                if (document.getElementById(posNameId)) {
                    document.getElementById(posNameId).value = opt ? (opt.dataset.name || opt.text) : '';
                }
            };
        });
}

// ── Toggle trigger datetime ────────────────────────────────
var LOCATIONS_LIST = <?php echo json_encode($candidate_locations); ?>;

function toggleLocationOther(sel, otherId) {
    var box = document.getElementById(otherId);
    box.style.display = (sel.value === 'Other') ? 'block' : 'none';
    if (sel.value !== 'Other') box.value = '';
}

function setLocationField(prefix, value) {
    var sel = document.getElementById(prefix + '_location_select');
    var txt = document.getElementById(prefix + '_location_other');
    if (!sel || !txt) return;
    if (!value) { sel.value = ''; txt.style.display = 'none'; txt.value = ''; return; }
    if (LOCATIONS_LIST.indexOf(value) !== -1 && value !== 'Other') {
        sel.value = value;
        txt.style.display = 'none';
        txt.value = '';
    } else {
        sel.value = 'Other';
        txt.style.display = 'block';
        txt.value = value;
    }
}

function toggleTrigger(status) {
    var wrap = document.getElementById('trigger_wrap');
    var inp  = document.getElementById('status_trigger');
    var lbl  = document.getElementById('trigger_required_star');
    if (TRIGGER_STATUSES.indexOf(status) !== -1) {
        wrap.style.display = 'block';
        var isRequired = TRIGGER_REQUIRED_STATUSES.indexOf(status) !== -1;
        inp.required = isRequired;
        if (lbl) lbl.style.display = isRequired ? 'inline' : 'none';
    } else {
        wrap.style.display = 'none';
        inp.required = false;
    }
}

// ── Toggle rejection reason/round fields ────────────────────
function toggleRejectFields(status) {
    var wrap   = document.getElementById('reject_wrap');
    var reason = document.getElementById('reject_reason');
    if (status === 'Rejected') {
        wrap.style.display = 'block';
        reason.required = true;
    } else {
        wrap.style.display = 'none';
        reason.required = false;
    }
}

// ── Status dropdown in table row → opens Update Status modal pre-filled ──
function handleStatusDropdownChange(selectEl) {
    var id         = selectEl.dataset.id;
    var name       = selectEl.dataset.name;
    var newStatus  = selectEl.value;
    var current    = selectEl.dataset.current;

    // Visually snap the dropdown back to the saved status — the real change
    // only takes effect once the modal form is submitted (so mandatory date/
    // reason fields are always respected).
    selectEl.value = current;

    openStatus(id, name);
    // Give openStatus's fetch a moment to populate the modal, then force the
    // status dropdown inside the modal to the one the user picked in the table.
    setTimeout(function() {
        document.getElementById('status_select').value = newStatus;
        toggleTrigger(newStatus);
        toggleRejectFields(newStatus);
    }, 350);
}

// ── Open Status modal ──────────────────────────────────────
function openStatus(id, name) {
    document.getElementById('status_id').value    = id;
    document.getElementById('status_cname').textContent = name;
    document.querySelector('[name="notes"]').value   = '';
    document.getElementById('reject_reason').value = '';
    document.getElementById('reject_round').value  = '';
    $('#statusModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('status_select').value = c.current_status || 'New';
            toggleTrigger(c.current_status || 'New');
            toggleRejectFields(c.current_status || 'New');
            document.getElementById('status_trigger').value = c.trigger_datetime ? c.trigger_datetime.replace(' ', 'T').substring(0,16) : '';
            var noteWrap = document.getElementById('current_note_display');
            var noteText = document.getElementById('current_note_text');
            if (c.last_note) { noteText.textContent = c.last_note; noteWrap.style.display = 'block'; }
            else { noteWrap.style.display = 'none'; }
        });
}

// ── Open Edit modal ────────────────────────────────────────
function openEdit(id) {
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('edit_id').value    = c.id;
            document.getElementById('edit_name').value  = c.name;
            document.getElementById('edit_phone').value = c.phone;
            document.getElementById('edit_email').value = c.email || '';
            setLocationField('edit', c.location || '');
            var deptEl = document.getElementById('edit_dept');
            deptEl.value = c.department_id;
            if (document.getElementById('edit_dept_name')) document.getElementById('edit_dept_name').value = c.department_name;
            // Load positions then select
            fetch('<?php echo $current_page; ?>?get_positions=1&dept_id=' + c.department_id)
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    var posEl = document.getElementById('edit_pos');
                    posEl.innerHTML = '<option value="">Select Position…</option>';
                    data.forEach(function(p) {
                        posEl.innerHTML += '<option value="' + p.id + '" data-name="' + p.title + '"' + (p.id == c.position_id ? ' selected' : '') + '>' + p.title + '</option>';
                    });
                    if (document.getElementById('edit_pos_name')) document.getElementById('edit_pos_name').value = c.position_name;
                    posEl.onchange = function() {
                        var opt = posEl.options[posEl.selectedIndex];
                        document.getElementById('edit_pos_name').value = opt ? (opt.dataset.name || opt.text) : '';
                    };
                });
            $('#editModal').modal('show');
        });
}

// ── Open View modal ────────────────────────────────────────
function openView(id) {
    document.getElementById('viewBody').innerHTML = '<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--primary)"></i></div>';
    document.getElementById('view_name').textContent = '';
    $('#viewModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            document.getElementById('view_name').textContent = c.name;
            var sc  = STATUS_COLORS[c.current_status] || '#6b7280';
            var tdt = c.trigger_datetime ? new Date(c.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) : '—';
            var resumeBtn = c.resume_path
                ? '<a href="' + c.resume_path + '" target="_blank" class="doc-dl-btn"><i class="fas fa-file-alt"></i> ' + (c.resume_name || 'Download Resume') + '</a>'
                : '<span style="color:var(--muted);font-size:13px;">No resume uploaded</span>';
            var jdBtn = c.jd_path
                ? '<a href="' + c.jd_path + '" target="_blank" class="doc-dl-btn jd"><i class="fas fa-file-contract"></i> ' + (c.jd_name || 'Download JD') + '</a>'
                : '<span style="color:var(--muted);font-size:13px;">No JD uploaded</span>';
            var html = [
                row('Department',  c.department_name || '—'),
                row('Position',    c.position_name   || '—'),
                row('Location',    c.location || '—'),
                row('Phone',       c.phone),
                row('Email',       c.email || '—'),
                row('Status',      '<span class="status-badge" style="background:' + sc + '">' + c.current_status + '</span>' + (c.current_status === 'Rejected' && c.rejected_round ? '<div style="font-size:12px;color:#dc2626;font-weight:700;margin-top:5px;"><i class="fas fa-flag mr-1"></i>' + c.rejected_round + '</div>' : '')),
                row('Trigger Date/Time', '<span style="color:var(--warning);font-weight:700;">' + tdt + '</span>'),
                row('Last Note',   c.last_note || '—'),
                row('Last Updated By', c.last_updated_by || '—'),
                row('Added By',    c.created_by || '—'),
                row('Added On',    c.created_at || '—'),
                row('Resume',      resumeBtn),
                row('Job Description', jdBtn),
            ].join('');
            document.getElementById('viewBody').innerHTML = html;
        });
}

function row(label, val) {
    return '<div class="detail-row"><div class="detail-label">' + label + '</div><div class="detail-value">' + val + '</div></div>';
}

// ── Open Log modal ─────────────────────────────────────────
function openLog(id, name) {
    document.getElementById('log_cname').textContent = name;
    document.getElementById('logTimeline').innerHTML = '<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--warning)"></i></div>';
    $('#logModal').modal('show');
    fetch('<?php echo $current_page; ?>?get_log=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(logs) {
            if (!logs.length) {
                document.getElementById('logTimeline').innerHTML = '<div style="text-align:center;padding:40px;color:var(--muted);"><i class="fas fa-inbox fa-2x" style="opacity:.3;margin-bottom:10px;display:block;"></i>No history yet.</div>';
                return;
            }
            var sc_map = STATUS_COLORS;
            var html = logs.map(function(l) {
                var sc  = sc_map[l.status] || '#6b7280';
                var tdt = l.trigger_datetime ? new Date(l.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) : '';
                var dt  = new Date(l.updated_at).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'});
                return '<div class="log-item">' +
                    '<div class="log-dot" style="background:' + sc + '"><i class="fas fa-circle" style="font-size:10px;"></i></div>' +
                    '<div class="log-body">' +
                    '<div class="log-status"><span class="status-badge" style="background:' + sc + ';font-size:11px;">' + l.status + '</span></div>' +
                    (l.notes ? '<div class="log-note" style="margin-top:8px;">' + escHtml(l.notes) + '</div>' : '') +
                    (tdt ? '<div class="log-trigger"><i class="fas fa-calendar-check mr-1"></i>Scheduled: ' + tdt + '</div>' : '') +
                    '<div class="log-meta"><i class="fas fa-user mr-1"></i>' + escHtml(l.updated_by) + ' &nbsp;•&nbsp; <i class="fas fa-clock mr-1"></i>' + dt + '</div>' +
                    '</div></div>';
            }).join('');
            document.getElementById('logTimeline').innerHTML = html;
        });
}

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Open WhatsApp modal ────────────────────────────────────
function openWhatsApp(id) {
    fetch('<?php echo $current_page; ?>?get_candidate=1&id=' + id)
        .then(function(r) { return r.json(); })
        .then(function(c) {
            var tdt = c.trigger_datetime
                ? new Date(c.trigger_datetime).toLocaleString('en-IN',{day:'2-digit',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit',hour12:true})
                : 'the scheduled time';
            var statusLabel = c.current_status;
            // Build a natural-language label for the scheduled event
            var eventLabel = 'follow-up call';
            if (statusLabel === 'Scheduled') eventLabel = 'interview / meeting';
            else if (statusLabel === 'Callback') eventLabel = 'callback call';
            else if (statusLabel === 'Call Later') eventLabel = 'call';
            else if (statusLabel === 'Follow Up') eventLabel = 'follow-up call';
            var msg = 'Hi ' + c.name + ',\n\n' +
                      'This is a friendly reminder from ' + COMPANY_NAME + '.\n\n' +
                      'Your ' + eventLabel + ' is scheduled on:\n' +
                      '\uD83D\uDCC5 ' + tdt + '\n\n' +
                      'Please make sure you are available at that time. Looking forward to connecting with you!\n\n' +
                      'Regards,\n' + HR_NAME + '\n' + COMPANY_NAME + ' — HR Team';
            document.getElementById('waPreview').textContent = msg;
            document.getElementById('waPhone').textContent   = c.phone;
            // Clean phone: remove spaces, dashes, +91 etc → keep digits
            var cleanPhone = c.phone.replace(/\D/g,'');
            // If Indian number without country code, prepend 91
            if (cleanPhone.length === 10) cleanPhone = '91' + cleanPhone;
            var waUrl = 'https://wa.me/' + cleanPhone + '?text=' + encodeURIComponent(msg);
            document.getElementById('waLink').href = waUrl;
            $('#waModal').modal('show');
        });
}

// ── Delete ─────────────────────────────────────────────────
function doDelete(id, name) {
    if (!confirm('Delete candidate "' + name + '"?\n\nThis will permanently remove the candidate and all their history. This cannot be undone.')) return;
    document.getElementById('delete_id').value = id;
    document.getElementById('deleteForm').submit();
}

// ── Notify from Alert Popup (Email + WA) ───────────────────
var _notifyWAPhone = '';

function capitalizeFirst(str) {
    if (!str) return str;
    str = str.trim();
    return str.charAt(0).toUpperCase() + str.slice(1);
}

function splitDateTime(tdt) {
    var parts = (tdt || '').split(',');
    if (parts.length >= 2) return { date: parts[0].trim(), time: parts.slice(1).join(',').trim() };
    return { date: tdt || '', time: '' };
}

function buildReminderMsg(name, status, tdt, senderName) {
    var dt = splitDateTime(tdt);
    var sender = capitalizeFirst(senderName || HR_NAME);
    return 'Hi ' + name + ',\n\n' +
        'Greetings from ' + COMPANY_NAME + '.\n' +
        'This is a friendly reminder regarding your scheduled follow-up call.\n\n' +
        'Our HR team will contact you on:\n' +
        'Date: ' + dt.date + '\n' +
        'Time: ' + dt.time + '\n\n' +
        'Kindly ensure that you are available to receive the call at the scheduled time. If you are unavailable, please let us know in advance.\n\n' +
        'We look forward to speaking with you.\n\n' +
        'Regards,\n' + sender + '\n' +
        'HR Team\n' +
        COMPANY_NAME;
}

function openNotify(id, name, phone, email, status, tdt) {
    _notifyWAPhone = phone;
    document.getElementById('notify_cname').textContent = name;
    document.getElementById('notify_email_to').value    = email || '';
    document.getElementById('notify_email_subject').value = 'Reminder: Scheduled Follow-up Call';
    document.getElementById('notify_sender_name').value = capitalizeFirst(HR_NAME);
    document.getElementById('notify_name_hidden').value = name;
    document.getElementById('notify_tdt_hidden').value  = tdt;
    var msg = buildReminderMsg(name, status, tdt, HR_NAME);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    document.getElementById('notify_wa_phone_display').textContent = phone;
    updateWALink();
    document.getElementById('notify_email_status').textContent = '';
    $('#alertModal').modal('hide');
    setTimeout(function() { $('#notifyModal').modal('show'); }, 400);
}

function regenerateNotifyMessages() {
    var name   = document.getElementById('notify_name_hidden').value;
    var tdt    = document.getElementById('notify_tdt_hidden').value;
    var sender = document.getElementById('notify_sender_name').value;
    var msg = buildReminderMsg(name, '', tdt, sender);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    updateWALink();
}

function openNotifyWA(id, name, phoneClean, status, tdt) {
    var rawMsg = buildReminderMsg(name, status, tdt, HR_NAME);
    var waUrl = 'https://wa.me/' + phoneClean + '?text=' + encodeURIComponent(rawMsg);
    window.open(waUrl, '_blank');
}

function updateWALink() {
    var msg = document.getElementById('notify_wa_body').value;
    var waUrl = 'https://wa.me/' + _notifyWAPhone + '?text=' + encodeURIComponent(msg);
    document.getElementById('notify_wa_link').href = waUrl;
}
document.getElementById('notify_wa_body') && document.getElementById('notify_wa_body').addEventListener('input', updateWALink);

function sendNotifyEmail() {
    var to      = document.getElementById('notify_email_to').value.trim();
    var subject = document.getElementById('notify_email_subject').value.trim();
    var body    = document.getElementById('notify_email_body').value.trim();
    var statusEl = document.getElementById('notify_email_status');
    if (!to) { alert('Please enter the candidate email address.'); return; }
    if (!confirm('Send email to ' + to + '?')) return;
    statusEl.textContent = 'Sending...';
    statusEl.style.color = 'var(--muted)';
    // Build a basic mailto fallback (server-side send requires AJAX endpoint)
    var mailtoUrl = 'mailto:' + encodeURIComponent(to)
        + '?subject=' + encodeURIComponent(subject)
        + '&body=' + encodeURIComponent(body);
    window.open(mailtoUrl, '_blank');
    statusEl.textContent = 'Email client opened!';
    statusEl.style.color = 'var(--success)';
}

// ── Auto-dismiss alerts ────────────────────────────────────
setTimeout(function() { $('.alert').fadeOut('slow'); }, 6000);

function applyAlertFilter() {
    var from = document.getElementById('alertDateFrom').value;
    var to   = document.getElementById('alertDateTo').value;
    var status = document.getElementById('alertStatusFilter').value;
    document.querySelectorAll('.alert-card-item').forEach(function(card) {
        var show = true;
        if (from && card.dataset.tdate < from) show = false;
        if (to   && card.dataset.tdate > to)   show = false;
        if (status && card.dataset.status !== status) show = false;
        card.style.display = show ? '' : 'none';
    });
}

function resetAlertFilterToday() {
    var today = new Date().toISOString().split('T')[0];
    document.getElementById('alertDateFrom').value = today;
    document.getElementById('alertDateTo').value = today;
    document.getElementById('alertStatusFilter').value = '';
    applyAlertFilter();
}

function csvField(v) {
    return '"' + String(v || '').replace(/"/g,'""').trim() + '"';
}

function exportAlertCSV() {
    var csv = [['Name','Phone','Department','Position','Status','Trigger Date/Time','Note'].map(csvField).join(',')];
    document.querySelectorAll('.alert-card-item').forEach(function(card) {
        if (card.style.display === 'none') return;
        var d = card.dataset;
        var line = [d.name, d.phone, d.dept, d.pos, d.status, d.tdt, d.note].map(csvField);
        csv.push(line.join(','));
    });
    var blob = new Blob(['\ufeff' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'Upcoming_Followups.csv';
    a.click();
}

$('#alertModal').on('shown.bs.modal', function() {
    if (!window._alertFilterInit) {
        window._alertFilterInit = true;
        resetAlertFilterToday();
    }
});
</script>

<!-- Flutter State Preserver -->
<script>
document.addEventListener("DOMContentLoaded", function() {
    const urlEmail = "<?php echo !empty($currentUserEmail) ? '?user_email=' . urlencode($currentUserEmail) : ''; ?>";
    const urlEmailAmp = "<?php echo !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : ''; ?>";
    if (urlEmail) {
        document.querySelectorAll("a").forEach(a => {
            let href = a.getAttribute("href");
            if (href && href.includes(".php")) {
                if (href.includes("?")) {
                    a.setAttribute("href", href + urlEmailAmp);
                } else {
                    a.setAttribute("href", href + urlEmail);
                }
            }
        });
        document.querySelectorAll("form").forEach(f => {
            if (!f.querySelector('input[name="user_email"]')) {
                let input = document.createElement('input');
                input.type = 'hidden';
                input.name = 'user_email';
                input.value = "<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES); ?>";
                f.appendChild(input);
            }
        });
    }
});
</script>

</body>
</html>

