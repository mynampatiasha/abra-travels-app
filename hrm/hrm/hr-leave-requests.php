<?php
// =========================================================================
// LEAVE MANAGEMENT - FIXED v2
// ✅ FIX 1: Duplicate leave check before inserting (same employee + overlapping dates)
// ✅ FIX 2: Status sync runs only once per hour (not on every page load)  
// ✅ FIX 3: Submit button disabled immediately on click (prevents double-submit)
// ✅ FIX 4: Proper null handling for lat/lng (PHP 7+ compatible)
// =========================================================================

ob_start();
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

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('library.php');
require_once('funciones.php');

if(!isset($dbConn) || !$dbConn) { die("Database connection failed."); }

date_default_timezone_set('Asia/Kolkata');

function get_leave_emoji($type, $session = '') {
    $type = strtolower(trim($type));
    if($type == 'paid') return '🌟 Paid Leave';
    if($type == 'sick') return '🤒 Sick';
    if($type == 'casual') return '🏖️ Casual';
    if($type == 'earned') return '💰 Earned';
    if($type == 'emergency') return '🚨 Emergency';
    if($type == 'unpaid') return '💸 Unpaid';
    if($type == 'half_day') {
        if($session == 'first')  return '🌅 Half Day (Morning)';
        if($session == 'second') return '🌆 Half Day (Afternoon)';
        return '🌗 Half Day';
    }
    return ucfirst($type);
}

function get_half_session_badge($session) {
    if($session == 'first')  return '<span style="background:#fef3c7;color:#92400e;padding:2px 8px;border-radius:6px;font-size:11px;font-weight:700;border:1px solid #f59e0b;">🌅 Morning Off</span>';
    if($session == 'second') return '<span style="background:#e0f2fe;color:#0369a1;padding:2px 8px;border-radius:6px;font-size:11px;font-weight:700;border:1px solid #0284c7;">🌆 Afternoon Off</span>';
    return '';
}

// =========================================================================
// AJAX DOCUMENT HANDLER
// =========================================================================
if(isset($_GET['ajax_get_documents']) && isset($_GET['leave_id'])) {
    $leave_id = intval($_GET['leave_id']);
    $session_id = 0;
    if(isset($_SESSION['user_id'])) $session_id = intval($_SESSION['user_id']);
    elseif(isset($_SESSION['id'])) $session_id = intval($_SESSION['id']);
    $current_user_data = null;
    if($session_id > 0) {
        $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE id=$session_id OR user_id=$session_id LIMIT 1");
        if($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
    }
    if(!$current_user_data && isset($_SESSION['user_name'])) {
        $n = mysqli_real_escape_string($dbConn, $_SESSION['user_name']);
        $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE name='$n' OR name LIKE '$n%' LIMIT 1");
        if($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
    }
    if(!$current_user_data) { echo "<div style='padding:20px;background:#fee2e2;border-radius:10px;color:#991b1b;'><strong>⚠️ Session Error</strong><br>Please refresh the page.</div>"; exit; }
    $current_user_id = $current_user_data['id'];
    $leave_query = mysqli_query($dbConn, "SELECT employee_id FROM hr_leaves WHERE id=$leave_id LIMIT 1");
    if(!$leave_query || mysqli_num_rows($leave_query) == 0) { die("<div class='alert alert-danger'>Leave not found</div>"); }
    $leave_data = mysqli_fetch_assoc($leave_query);
    $docs_query = mysqli_query($dbConn, "SELECT * FROM hr_leave_documents WHERE leave_id=$leave_id ORDER BY uploaded_at DESC");
    $num_docs = mysqli_num_rows($docs_query);
    echo '<div style="margin-bottom:25px;"><h5 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fa fa-paperclip"></i> Attached Documents</h5>';
    if($num_docs == 0) {
        echo '<div style="padding:40px;text-align:center;background:#f8fafc;border-radius:12px;border:2px dashed #cbd5e1;color:#64748b;"><i class="fa fa-folder-open" style="font-size:30px;display:block;margin-bottom:10px;"></i>No documents uploaded yet</div>';
    } else {
        echo '<div id="docCarousel" class="carousel slide" data-ride="carousel" data-interval="false" style="background:#f1f5f9;border-radius:12px;overflow:hidden;border:1px solid #e2e8f0;">';
        if($num_docs > 1) { echo '<ol class="carousel-indicators" style="bottom:-15px;">'; for($i=0;$i<$num_docs;$i++) echo '<li data-target="#docCarousel" data-slide-to="'.$i.'" class="'.($i==0?'active':'').'" style="background-color:#1e3a8a;"></li>'; echo '</ol>'; }
        echo '<div class="carousel-inner">';
        $count = 0;
        while($doc = mysqli_fetch_assoc($docs_query)) {
            $active = ($count == 0) ? 'active' : '';
            $ext = strtolower(pathinfo($doc['file_path'], PATHINFO_EXTENSION));
            $is_img = in_array($ext, ['jpg','jpeg','png','gif','webp']);
            $is_pdf = ($ext === 'pdf');
            echo '<div class="carousel-item '.$active.'"><div class="d-flex justify-content-center align-items-center" style="height:500px;background:#fff;">';
            if($is_img) echo '<img src="'.htmlspecialchars($doc['file_path']).'" class="d-block" style="max-height:100%;max-width:100%;object-fit:contain;">';
            elseif($is_pdf) echo '<iframe src="'.htmlspecialchars($doc['file_path']).'" style="width:100%;height:100%;border:none;"></iframe>';
            else echo '<div class="text-center p-5"><i class="fas fa-file-alt" style="font-size:60px;color:#64748b;"></i><br><br><b>'.$ext.'</b> file preview not available.</div>';
            echo '</div><div style="background:rgba(255,255,255,0.95);padding:15px;border-top:1px solid #e2e8f0;display:flex;justify-content:space-between;align-items:center;"><div><h6 style="margin:0;font-weight:700;color:#1e3a8a;">'.htmlspecialchars($doc['document_name']).'</h6>';
            if(!empty($doc['address'])) echo '<small style="color:#64748b;"><i class="fas fa-map-marker-alt"></i> '.htmlspecialchars($doc['address']).'</small>';
            echo '</div><a href="'.htmlspecialchars($doc['file_path']).'" target="_blank" class="btn btn-sm btn-primary" style="font-weight:700;background:linear-gradient(135deg,#1e3a8a,#1e40af);"><i class="fas fa-download"></i> Download</a></div></div>';
            $count++;
        }
        echo '</div>';
        if($num_docs > 1) {
            echo '<a class="carousel-control-prev" href="#docCarousel" role="button" data-slide="prev" style="width:5%;"><span class="carousel-control-prev-icon" aria-hidden="true" style="background-color:rgba(0,0,0,0.3);border-radius:50%;padding:20px;"></span></a>';
            echo '<a class="carousel-control-next" href="#docCarousel" role="button" data-slide="next" style="width:5%;"><span class="carousel-control-next-icon" aria-hidden="true" style="background-color:rgba(0,0,0,0.3);border-radius:50%;padding:20px;"></span></a>';
        }
        echo '</div>';
    }
    echo '</div>';
    if($leave_data['employee_id'] == $current_user_id) {
        echo '<div style="background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:2px solid #3b82f6;border-radius:12px;padding:25px;margin-top:20px;"><h5 style="color:#1e40af;font-weight:700;margin-bottom:15px;"><i class="fa fa-cloud-upload-alt"></i> Upload New Document</h5>';
        echo '<form method="POST" enctype="multipart/form-data" id="uploadDocForm" onsubmit="return validateDocUpload()">';
        echo '<input type="hidden" name="upload_leave_document" value="1"><input type="hidden" name="leave_id" value="'.$leave_id.'"><input type="hidden" name="latitude" id="docLatitude"><input type="hidden" name="longitude" id="docLongitude"><input type="hidden" name="address" id="docAddress">';
        echo '<div class="form-group"><label style="font-weight:600;font-size:13px;">Select File *</label><input type="file" name="document_file" id="docFile" class="form-control-modern" required></div>';
        echo '<div class="form-group"><label style="font-weight:600;font-size:13px;">Description</label><input type="text" name="document_location" class="form-control-modern" placeholder="e.g. Medical Certificate"></div>';
        echo '<div style="background:#fef3c7;padding:15px;border-radius:10px;border:1px solid #f59e0b;margin-bottom:15px;"><label style="font-weight:700;color:#92400e;display:block;margin-bottom:10px;"><i class="fa fa-map-marker-alt"></i> Location Required (MANDATORY)</label><input type="text" id="docLocationDisplay" class="form-control-modern" readonly required placeholder="Waiting for GPS..." style="margin-bottom:10px;background:#fff;"><button type="button" class="btn-location" onclick="getDocLocationAjax()" style="font-size:13px;">GET GPS FOR UPLOAD</button></div>';
        echo '<button type="submit" class="btn-submit-modern">UPLOAD DOCUMENT</button></form></div>';
    }
    exit;
}

// =========================================================================
// USER AUTHENTICATION
// =========================================================================
$session_id = 0;
if (isset($_SESSION['user_id'])) $session_id = intval($_SESSION['user_id']);
elseif (isset($_SESSION['id'])) $session_id = intval($_SESSION['id']);

$current_user_data = null;
if ($session_id > 0) {
    $q_user = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE id = $session_id OR user_id = $session_id LIMIT 1");
    if($q_user && mysqli_num_rows($q_user) > 0) $current_user_data = mysqli_fetch_assoc($q_user);
} elseif (isset($_SESSION['user_name'])) {
    $n = mysqli_real_escape_string($dbConn, $_SESSION['user_name']);
    $q_user = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE name='$n' OR name LIKE '$n%' LIMIT 1");
    if($q_user && mysqli_num_rows($q_user) > 0) $current_user_data = mysqli_fetch_assoc($q_user);
}

if (!$current_user_data) { die("<div style='padding:50px;text-align:center;'><h4>Session Expired. Please Login.</h4><a href='login.php'>Login</a></div>"); }

$current_user_id          = $current_user_data['id'];
$current_user_name        = $current_user_data['name'];
$current_user_employee_id = $current_user_data['employee_id'] ?? '';
$current_user_pos_id      = !empty($current_user_data['position_id']) ? intval($current_user_data['position_id']) : 0;
$current_user_position    = !empty($current_user_data['position']) ? $current_user_data['position'] : 'Employee';
$current_user_department  = !empty($current_user_data['department']) ? $current_user_data['department'] : 'General';
$current_user_role        = isset($current_user_data['role']) ? $current_user_data['role'] : 'Employee';
$current_user_hire_date   = $current_user_data['hire_date'] ?? null;

// =========================================================================
// LEAVE ELIGIBILITY CHECK (9-MONTH PROBATION)
// =========================================================================
$is_eligible_for_paid_leaves = false;
$months_since_joining = 0;
$eligibility_date = null;
$missing_hire_date = false;

if ($current_user_hire_date) {
    $hire_date_obj = new DateTime($current_user_hire_date);
    $today = new DateTime();
    $interval = $hire_date_obj->diff($today);
    $months_since_joining = ($interval->y * 12) + $interval->m;
    
    // Eligible if completed 9 months
    $is_eligible_for_paid_leaves = ($months_since_joining >= 9);
    
    // Calculate eligibility date (9 months from hire date)
    $eligibility_date_obj = clone $hire_date_obj;
    $eligibility_date_obj->modify('+9 months');
    $eligibility_date = $eligibility_date_obj->format('d M Y');
} else {
    // No hire date set - mark as missing
    $missing_hire_date = true;
    // Default to eligible to maintain backward compatibility
    $is_eligible_for_paid_leaves = true;
}

$is_management_dept   = (stripos($current_user_department, 'Management') !== false);
$is_hr_dept           = (stripos($current_user_department, 'Human Resources') !== false);
$is_managing_director = (stripos($current_user_position, 'Managing Director') !== false || stripos($current_user_position, 'md') !== false || stripos($current_user_position, 'ceo') !== false);
$is_role_admin        = (stripos($current_user_role, 'Admin') !== false || stripos($current_user_role, 'HR') !== false);
$is_abishek           = (stripos($current_user_name, 'abishek') !== false);
$is_keerti            = (stripos($current_user_name, 'keerti') !== false || stripos($current_user_name, 'keerthi') !== false);
$is_admin             = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_role_admin || $is_abishek || $is_keerti);

// Leave Overview dashboard — Managing Director only (narrower than $is_admin,
// which also covers HR/management/Keerti). Same MD-only pattern used for the
// Payroll and Attendance Overview dashboards.
$is_leave_overview_viewer = ($is_managing_director || $is_abishek);

// OVERVIEW TAB date range — own session key, defaults to a 6-month window so
// the Monthly Trend chart has enough data to actually show a trend.
$lv_filter_from = $_POST['lv_filter_from'] ?? $_SESSION['leave_ov_from'] ?? date('Y-m-01', strtotime('-5 months'));
$lv_filter_to   = $_POST['lv_filter_to']   ?? $_SESSION['leave_ov_to']   ?? date('Y-m-t');
if(isset($_POST['lv_apply_filter'])) {
    $_SESSION['leave_ov_from'] = $lv_filter_from;
    $_SESSION['leave_ov_to']   = $lv_filter_to;
}

$dashboard_url = "/dashboard/raise-a-ticket.php";
if($is_managing_director || $is_abishek) $dashboard_url = "/dashboard/index.php"; 

// =========================================================================
// DROPDOWN DATA
// =========================================================================
$dropdown_employees = [];
$dropdown_locations = [];
$emp_q = mysqli_query($dbConn, "SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name ASC");
while($row = mysqli_fetch_assoc($emp_q)) $dropdown_employees[] = $row;
$loc_q = mysqli_query($dbConn, "SELECT DISTINCT work_location FROM hr_employees WHERE work_location IS NOT NULL AND work_location != '' ORDER BY work_location ASC");
while($row = mysqli_fetch_assoc($loc_q)) $dropdown_locations[] = $row['work_location'];

// =========================================================================
// TABLE SETUP
// =========================================================================
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS `hr_leave_hierarchy` (`position_id` int(11) NOT NULL, `approver_1_id` int(11) DEFAULT NULL, `approver_2_id` int(11) DEFAULT NULL, PRIMARY KEY (`position_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS `hr_leaves` (`id` int(11) NOT NULL AUTO_INCREMENT, `employee_id` int(11) DEFAULT NULL, `primary_approver_id` int(11) DEFAULT NULL, `secondary_approver_id` int(11) DEFAULT NULL, `start_date` date DEFAULT NULL, `end_date` date DEFAULT NULL, `leave_days` int(11) DEFAULT NULL, `leave_type` varchar(50) DEFAULT NULL, `reason` text, `location_latitude` decimal(10,8) DEFAULT NULL, `location_longitude` decimal(11,8) DEFAULT NULL, `location_address` text DEFAULT NULL, `status` varchar(20) DEFAULT 'pending', `is_urgent` tinyint(1) DEFAULT 0, `approved_by` int(11) DEFAULT NULL, `rejected_by` int(11) DEFAULT NULL, `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS `hr_leave_documents` (`id` int(11) NOT NULL AUTO_INCREMENT, `leave_id` int(11) NOT NULL, `employee_id` varchar(50) DEFAULT NULL, `document_name` varchar(255) NOT NULL, `file_path` varchar(500) NOT NULL, `location` varchar(255) DEFAULT NULL, `latitude` decimal(10,8) DEFAULT NULL, `longitude` decimal(11,8) DEFAULT NULL, `address` text DEFAULT NULL, `uploaded_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `leave_id` (`leave_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add half_day_session column if missing (stores 'first' or 'second' for half-day leaves)
$hds_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_leaves LIKE 'half_day_session'");
if(!$hds_check || mysqli_num_rows($hds_check) == 0)
    mysqli_query($dbConn, "ALTER TABLE hr_leaves ADD COLUMN half_day_session ENUM('first','second','') DEFAULT '' AFTER leave_type");

// Add original_leave_type column if missing (remembers the real leave type
// before a probation-period auto-conversion to unpaid, so it can be restored
// once the employee completes 9 months)
$olt_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_leaves LIKE 'original_leave_type'");
if(!$olt_check || mysqli_num_rows($olt_check) == 0)
    mysqli_query($dbConn, "ALTER TABLE hr_leaves ADD COLUMN original_leave_type VARCHAR(50) DEFAULT NULL AFTER leave_type");

// Ensure leave_days accepts decimals
$ld_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_leaves LIKE 'leave_days'");
if($ld_check && mysqli_num_rows($ld_check) > 0) {
    $ld_row = mysqli_fetch_assoc($ld_check);
    if(stripos($ld_row['Type'], 'int') !== false)
        mysqli_query($dbConn, "ALTER TABLE hr_leaves MODIFY COLUMN leave_days DECIMAL(5,1) DEFAULT 1");
}

// FEATURE: auto-sync approved paid leave into attendance (no more manual HR override).
// attendance_synced tracks whether we've already pushed this leave's dates into
// hr_attendance_overrides, so a later manual correction by HR in Payroll never gets
// silently clobbered by this running again on a future page load.
$as_check = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_leaves LIKE 'attendance_synced'");
if(!$as_check || mysqli_num_rows($as_check) == 0)
    mysqli_query($dbConn, "ALTER TABLE hr_leaves ADD COLUMN attendance_synced TINYINT(1) DEFAULT 0 AFTER status");

// Same table Payroll uses for manual overrides -- create here too in case Payroll's
// page has never been opened yet on a fresh install.
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_attendance_overrides (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    attendance_date DATE NOT NULL,
    status ENUM('present','absent','holiday','leave','half_day') DEFAULT 'present',
    reason TEXT, created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_emp_date (employee_id, attendance_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// ✅ FIX 2: Status sync runs at most once per hour per session — NOT on every page load.
// The old code ran 3 UPDATE queries on every single page load, which could reset
// statuses at bad times and caused race conditions with approvals happening concurrently.
$sync_key = 'leave_status_synced_at';
if(!isset($_SESSION[$sync_key]) || (time() - $_SESSION[$sync_key]) > 3600) {
    mysqli_query($dbConn, "UPDATE hr_leaves l SET l.status='pending', l.approved_by=NULL, l.rejected_by=NULL WHERE l.id NOT IN (SELECT DISTINCT leave_id FROM tickets WHERE leave_id IS NOT NULL AND LOWER(status) IN ('approved','rejected'))");
    mysqli_query($dbConn, "UPDATE hr_leaves l JOIN tickets t ON t.leave_id=l.id SET l.status='approved', l.approved_by=t.assigned_to WHERE LOWER(t.status)='approved'");
    mysqli_query($dbConn, "UPDATE hr_leaves l JOIN tickets t ON t.leave_id=l.id SET l.status='rejected', l.rejected_by=t.assigned_to WHERE LOWER(t.status)='rejected'");
    $_SESSION[$sync_key] = time();
}

// FEATURE (continued): push approved-but-unsynced PAID leaves into hr_attendance_overrides.
// Runs every page load (cheap — usually zero rows to process) but each leave is only
// ever processed once thanks to attendance_synced, so manual HR edits made afterward
// in Payroll are never overwritten by this.
$unsynced = mysqli_query($dbConn, "SELECT id, employee_id, start_date, end_date, leave_type, half_day_session
    FROM hr_leaves
    WHERE status='approved' AND attendance_synced=0
    AND leave_type IN ('paid','sick','casual','earned','emergency','half_day')");
if($unsynced) {
    while($lv = mysqli_fetch_assoc($unsynced)) {
        $lv_emp_id = intval($lv['employee_id']);

        if($lv['leave_type'] === 'half_day') {
            // Single day, half-day override -- counts as 0.5 present day in payroll,
            // same as when HR marks it manually today.
            $dates = [$lv['start_date']];
            $ov_status = 'half_day';
            $reason_txt = 'Auto: Approved Half-Day Leave' . ($lv['half_day_session'] === 'second' ? ' (Afternoon)' : ' (Morning)');
        } else {
            // Full paid-leave date range, inclusive.
            $dates = [];
            $cursor = new DateTime($lv['start_date']);
            $end_dt = new DateTime($lv['end_date']);
            while($cursor <= $end_dt) {
                $dates[] = $cursor->format('Y-m-d');
                $cursor->modify('+1 day');
            }
            $ov_status = 'leave';
            $reason_txt = 'Auto: Approved ' . ucfirst($lv['leave_type']) . ' Leave';
        }

        $reason_sql = mysqli_real_escape_string($dbConn, $reason_txt);
        foreach($dates as $dt) {
            $chk = mysqli_query($dbConn, "SELECT id FROM hr_attendance_overrides WHERE employee_id=$lv_emp_id AND attendance_date='$dt'");
            if($chk && mysqli_num_rows($chk) > 0) {
                mysqli_query($dbConn, "UPDATE hr_attendance_overrides SET status='$ov_status', reason='$reason_sql', created_by='System (Auto-Sync)' WHERE employee_id=$lv_emp_id AND attendance_date='$dt'");
            } else {
                mysqli_query($dbConn, "INSERT INTO hr_attendance_overrides (employee_id, attendance_date, status, reason, created_by) VALUES ($lv_emp_id, '$dt', '$ov_status', '$reason_sql', 'System (Auto-Sync)')");
            }
        }

        mysqli_query($dbConn, "UPDATE hr_leaves SET attendance_synced=1 WHERE id=" . intval($lv['id']));
    }
}

// =========================================================================
// POST HANDLERS
// =========================================================================
if(isset($_POST['upload_leave_document']) && isset($_FILES['document_file'])) {
    $leave_id  = intval($_POST['leave_id']);
    $location  = mysqli_real_escape_string($dbConn, trim($_POST['document_location']??''));
    $latitude  = !empty($_POST['latitude'])  ? floatval($_POST['latitude'])  : null;
    $longitude = !empty($_POST['longitude']) ? floatval($_POST['longitude']) : null;
    $address   = !empty($_POST['address'])   ? mysqli_real_escape_string($dbConn, trim($_POST['address'])) : null;
    if($latitude === null) { $_SESSION['error_msg'] = "❌ GPS Location is MANDATORY!"; header("Location: ".$_SERVER['PHP_SELF']); exit; }
    $file = $_FILES['document_file'];
    if($file['error'] === UPLOAD_ERR_OK) {
        $upload_dir = 'uploads/leave_documents/'.$current_user_employee_id.'/';
        if(!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);
        $ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        $dest = $upload_dir.'leave_'.$leave_id.'_'.time().'.'.$ext;
        if(move_uploaded_file($file['tmp_name'], $dest)) {
            $dn = mysqli_real_escape_string($dbConn, $file['name']);
            mysqli_query($dbConn, "INSERT INTO hr_leave_documents (leave_id, employee_id, document_name, file_path, location, latitude, longitude, address) VALUES ($leave_id, '$current_user_employee_id', '$dn', '$dest', '$location', $latitude, $longitude, '$address')");
            $_SESSION['success_msg'] = "✓ Document uploaded successfully!";
        }
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

if(isset($_POST['ajax_create_leave'])) {
    header('Content-Type: application/json');
    $emp_id     = intval($_POST['employee_id']);
    $pri_app_id = intval($_POST['primary_approver_id']);
    $sec_app_id = !empty($_POST['secondary_approver_id']) ? intval($_POST['secondary_approver_id']) : 0;
    $ter_app_id = !empty($_POST['tertiary_approver_id']) ? intval($_POST['tertiary_approver_id']) : 0;
    $start_date = mysqli_real_escape_string($dbConn, $_POST['start_date']);
    $end_date   = mysqli_real_escape_string($dbConn, $_POST['end_date']);
    $leave_days_raw = $_POST['leave_days'] ?? '0';
    $leave_days = floatval($leave_days_raw);
    $leave_type = mysqli_real_escape_string($dbConn, $_POST['leave_type']);
    $sess = $_POST['half_day_session'] ?? '';
    $half_day_session = in_array($sess, ['first','second']) ? $sess : '';

    // Validate leave days
    if ($leave_days <= 0) { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success' => false, 'message' => '❌ Invalid leave days. Please check your dates.']);
        exit;
    }

    $reason    = mysqli_real_escape_string($dbConn, $_POST['reason']);
    $latitude  = !empty($_POST['latitude'])  ? floatval($_POST['latitude'])  : null;
    $longitude = !empty($_POST['longitude']) ? floatval($_POST['longitude']) : null;
    $address   = !empty($_POST['address'])   ? mysqli_real_escape_string($dbConn, trim($_POST['address'])) : null;

    // ✅ ELIGIBILITY CHECK: Validate 9-month probation for paid leaves
    // Check eligibility based on LEAVE START DATE, not application date
    $emp_data = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT hire_date FROM hr_employees WHERE id=$emp_id LIMIT 1"));
    if ($emp_data && !empty($emp_data['hire_date'])) {
        $hire_dt = new DateTime($emp_data['hire_date']);
        $leave_start_dt = new DateTime($start_date);
        
        // Calculate months employed at the time of TAKING THE LEAVE
        $interval = $hire_dt->diff($leave_start_dt);
        $months_at_leave_date = ($interval->y * 12) + $interval->m;
        
        // If less than 9 months at leave start date and trying to apply for paid leave, reject
        if ($months_at_leave_date < 9 && !in_array($leave_type, ['unpaid','half_day'])) { if (ob_get_level() > 0) { ob_clean(); }
            echo json_encode([
                'success' => false,
                'message' => "❌ Paid Leave Not Available!\n\nYou will have completed only $months_at_leave_date month(s) by the leave start date ($start_date).\n\nPaid leaves are available after completing 9 months of employment.\n\nYou can only apply for 'Unpaid Leave' at this time."
            ]);
            exit;
        }
    }

    // ✅ STRICT BALANCE LOCK: Check ONLY Total Paid Leaves
    if (in_array($leave_type, ['sick', 'casual', 'earned', 'emergency']) && isset($months_at_leave_date) && $months_at_leave_date >= 9) {
        $paid_leaves_earned = ($months_at_leave_date - 3) * 2;
        $taken_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT
            SUM(CASE WHEN leave_type IN ('paid', 'sick', 'casual', 'earned', 'emergency') THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) +
            SUM(CASE WHEN leave_type='half_day' THEN COALESCE(leave_days, 0.5) ELSE 0 END) as taken
            FROM hr_leaves WHERE employee_id=$emp_id AND status='approved'"));
        $already_taken_total = floatval($taken_row['taken'] ?? 0);
        $remaining_total_paid = max(0, $paid_leaves_earned - $already_taken_total);
        
        if ($leave_days > $remaining_total_paid) { if (ob_get_level() > 0) { ob_clean(); }
            echo json_encode([
                'success' => false,
                'message' => "❌ Insufficient Total Leave Balance!\n\nYou only have $remaining_total_paid total Paid Leave(s) accrued, but this request is for $leave_days day(s).\n\nPlease reduce the number of days or apply for Unpaid Leave."
            ]);
            exit;
        }
    }

    // ✅ FIX 1: Check for duplicate/overlapping leave before doing anything
    // This is the root cause: same person submitting from the same location on the same day
    // created duplicate hr_leaves rows AND duplicate tickets with no guard
    $dup_q = mysqli_query($dbConn, "SELECT id FROM hr_leaves 
        WHERE employee_id = $emp_id 
        AND status != 'rejected'
        AND start_date <= '$end_date' 
        AND end_date >= '$start_date'
        LIMIT 1");

    if($dup_q && mysqli_num_rows($dup_q) > 0) {
        $dup = mysqli_fetch_assoc($dup_q); if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode([
            'success' => false,
            'message' => "⚠️ Duplicate Leave Detected!\n\nYou already have an active leave request (Leave ID: #{$dup['id']}) that overlaps with the dates you selected ({$start_date} to {$end_date}).\n\nPlease check your 'My Leaves' tab. If incorrect, contact HR."
        ]);
        exit;
    }

    $start  = new DateTime($start_date);
    $end    = new DateTime($end_date);
    $days   = $leave_days; // Use manual count instead of auto-calculation
    $urgent = (date('Y-m-d') == $start_date) ? 1 : 0;

    $emp_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT name, position, employee_id FROM hr_employees WHERE id=$emp_id LIMIT 1"));
    if(!$emp_row) { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success' => false, 'message' => '❌ Employee record not found.']);
        exit;
    }

    // ✅ FIX 4: Safe null handling for lat/lng (PHP 7 compatible — ?? 'NULL' only works in PHP 8+)
    $lat_val = ($latitude  !== null) ? floatval($latitude)  : 'NULL';
    $lng_val = ($longitude !== null) ? floatval($longitude) : 'NULL';
    $adr_val = ($address   !== null) ? "'$address'" : 'NULL';

    $ins_sql = "INSERT INTO hr_leaves 
        (employee_id, primary_approver_id, secondary_approver_id, tertiary_approver_id, start_date, end_date, leave_days, leave_type, half_day_session, reason, location_latitude, location_longitude, location_address, status, is_urgent) 
        VALUES ($emp_id, $pri_app_id, ".($sec_app_id > 0 ? $sec_app_id : 'NULL').", ".($ter_app_id > 0 ? $ter_app_id : 'NULL').", '$start_date', '$end_date', $leave_days, '$leave_type', '$half_day_session', '$reason', $lat_val, $lng_val, $adr_val, 'pending', $urgent)";

    if(!mysqli_query($dbConn, $ins_sql)) { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success' => false, 'message' => '❌ Database error: '.mysqli_error($dbConn)]);
        exit;
    }

    $leave_id = mysqli_insert_id($dbConn);

    // Guard: verify leave was actually saved
    if(!$leave_id) { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success' => false, 'message' => '❌ Leave not saved. No tickets were created.']);
        exit;
    }

    // Upload documents
    if(isset($_FILES['leave_documents'])) {
        $up_dir = 'uploads/leave_documents/'.$emp_row['employee_id'].'/';
        if(!is_dir($up_dir)) mkdir($up_dir, 0755, true);
        for($i = 0; $i < count($_FILES['leave_documents']['name']); $i++) {
            if($_FILES['leave_documents']['error'][$i] === 0) {
                $ext = strtolower(pathinfo($_FILES['leave_documents']['name'][$i], PATHINFO_EXTENSION));
                $dest = $up_dir.'lv_'.$leave_id.'_'.time().'_'.$i.'.'.$ext;
                if(move_uploaded_file($_FILES['leave_documents']['tmp_name'][$i], $dest)) {
                    $orig_name = mysqli_real_escape_string($dbConn, $_FILES['leave_documents']['name'][$i]);
                    mysqli_query($dbConn, "INSERT INTO hr_leave_documents (leave_id, employee_id, document_name, file_path, latitude, longitude, address) VALUES ($leave_id, '{$emp_row['employee_id']}', '$orig_name', '$dest', $lat_val, $lng_val, $adr_val)");
                }
            }
        }
    }

    $prio  = ($days > 1) ? 'high' : 'medium';
    $days_display = ($days == 0.5) ? '½ Day' : (fmod($days, 1) == 0.5 ? $days.' days (incl. half day)' : $days.' day(s)');
    $session_display = '';
    if(!empty($half_day_session)) {
        $session_display = ($half_day_session === 'second') ? ' [Afternoon Start/End]' : ' [Morning Start/End]';
    }
    $loc_i = $address ? "\n📍 LOCATION: $address\n" : '';
    $created_tickets = [];

    // Create L1 ticket
    $tn1 = 'LV-'.date('Ymd').'-'.rand(1000,9999).'-L1';
    $sb1 = mysqli_real_escape_string($dbConn, "[L1 Leave Request] ".ucfirst(str_replace('_',' ',$leave_type))."$session_display - $days_display ({$emp_row['name']})");
    $bd1 = mysqli_real_escape_string($dbConn, "🏖️ LEAVE L1 APPROVAL\n👤 {$emp_row['name']}\n📅 $start_date".($leave_type==='half_day'?'':" to $end_date")."\n🗓️ $days_display$session_display\n📝 ".ucfirst(str_replace('_',' ',$leave_type))."\n$loc_i\n💬 Reason: $reason\n✅ Set Ticket to APPROVED to grant.");
    if(mysqli_query($dbConn, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level, deadline, timeline) VALUES ('$tn1','".addslashes($emp_row['name'])."','$sb1','$bd1','Open','$prio',$pri_app_id,NOW(),NOW(),$leave_id,'primary',DATE_ADD(NOW(), INTERVAL 1 DAY),'1 day')")) {
        $created_tickets[] = $tn1;
    }

    // Create L2 ticket (only if a secondary approver was selected)
    if($sec_app_id > 0) {
        $tn2 = 'LV-'.date('Ymd').'-'.rand(1000,9999).'-L2';
        $sb2 = mysqli_real_escape_string($dbConn, "[L2 Leave Request] ".ucfirst(str_replace('_',' ',$leave_type))."$session_display - $days_display ({$emp_row['name']})");
        $bd2 = mysqli_real_escape_string($dbConn, "🏖️ LEAVE L2 APPROVAL\n👤 {$emp_row['name']}\n📅 $start_date".($leave_type==='half_day'?'':" to $end_date")."\n🗓️ $days_display$session_display\n📝 ".ucfirst(str_replace('_',' ',$leave_type))."\n$loc_i\n💬 Reason: $reason\n✅ Set Ticket to APPROVED to grant.");
        if(mysqli_query($dbConn, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level, deadline, timeline) VALUES ('$tn2','".addslashes($emp_row['name'])."','$sb2','$bd2','Open','$prio',$sec_app_id,NOW(),NOW(),$leave_id,'secondary',DATE_ADD(NOW(), INTERVAL 1 DAY),'1 day')")) {
            $created_tickets[] = $tn2;
        }
    }

    // Create L3 ticket (only if a tertiary approver was selected)
    if($ter_app_id > 0) {
        $tn3 = 'LV-'.date('Ymd').'-'.rand(1000,9999).'-L3';
        $sb3 = mysqli_real_escape_string($dbConn, "[L3 Leave Request] ".ucfirst(str_replace('_',' ',$leave_type))."$session_display - $days_display ({$emp_row['name']})");
        $bd3 = mysqli_real_escape_string($dbConn, "🏖️ LEAVE L3 APPROVAL\n👤 {$emp_row['name']}\n📅 $start_date".($leave_type==='half_day'?'':" to $end_date")."\n🗓️ $days_display$session_display\n📝 ".ucfirst(str_replace('_',' ',$leave_type))."\n$loc_i\n💬 Reason: $reason\n✅ Set Ticket to APPROVED to grant.");
        if(mysqli_query($dbConn, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level, deadline, timeline) VALUES ('$tn3','".addslashes($emp_row['name'])."','$sb3','$bd3','Open','$prio',$ter_app_id,NOW(),NOW(),$leave_id,'tertiary',DATE_ADD(NOW(), INTERVAL 1 DAY),'1 day')")) {
            $created_tickets[] = $tn3;
        }
    }

    $ticket_str = implode(' & ', $created_tickets); if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode(['success' => true, 'message' => "✅ Leave submitted successfully!\nTicket(s) created: $ticket_str"]);
    exit;
}

// =========================================================================
// DATA FETCHING (HIERARCHY LOGIC)
// =========================================================================
$primary_approvers = [];
$secondary_approvers = [];
$tertiary_approvers = [];

if($current_user_pos_id == 0 && !empty($current_user_position)) {
    $fix_q = mysqli_query($dbConn, "SELECT id FROM hr_positions WHERE title='".mysqli_real_escape_string($dbConn, $current_user_position)."' LIMIT 1");
    if($fix_q && mysqli_num_rows($fix_q) > 0) $current_user_pos_id = mysqli_fetch_assoc($fix_q)['id'];
}

if($current_user_pos_id > 0) {
    $hier_query = mysqli_query($dbConn, "SELECT * FROM hr_leave_hierarchy WHERE position_id=$current_user_pos_id LIMIT 1");
    if($hier_query && mysqli_num_rows($hier_query) > 0) {
        $hierarchy = mysqli_fetch_assoc($hier_query);
        $approver_1_pos_id = $hierarchy['approver_1_id'];
        $approver_2_pos_id = $hierarchy['approver_2_id'];
        $approver_3_pos_id = $hierarchy['approver_3_id'] ?? null;
        
        if(!empty($approver_1_pos_id)) {
            $t1_q = mysqli_query($dbConn, "SELECT title FROM hr_positions WHERE id=$approver_1_pos_id");
            $t1 = ($t1_q && mysqli_num_rows($t1_q)>0) ? mysqli_fetch_assoc($t1_q)['title'] : '';
            $sql1 = "SELECT id, name, position FROM hr_employees WHERE status='active' AND (position_id=$approver_1_pos_id";
            if($t1) $sql1 .= " OR position LIKE '".mysqli_real_escape_string($dbConn, $t1)."'";
            $sql1 .= ")";
            $l1_q = mysqli_query($dbConn, $sql1);
            while($row = mysqli_fetch_assoc($l1_q)) $primary_approvers[] = $row;
        }
        if(!empty($approver_2_pos_id)) {
            $t2_q = mysqli_query($dbConn, "SELECT title FROM hr_positions WHERE id=$approver_2_pos_id");
            $t2 = ($t2_q && mysqli_num_rows($t2_q)>0) ? mysqli_fetch_assoc($t2_q)['title'] : '';
            $sql2 = "SELECT id, name, position FROM hr_employees WHERE status='active' AND (position_id=$approver_2_pos_id";
            if($t2) $sql2 .= " OR position LIKE '".mysqli_real_escape_string($dbConn, $t2)."'";
            $sql2 .= ")";
            $l2_q = mysqli_query($dbConn, $sql2);
            while($row = mysqli_fetch_assoc($l2_q)) $secondary_approvers[] = $row;
        }
        if(!empty($approver_3_pos_id)) {
            $t3_q = mysqli_query($dbConn, "SELECT title FROM hr_positions WHERE id=$approver_3_pos_id");
            $t3 = ($t3_q && mysqli_num_rows($t3_q)>0) ? mysqli_fetch_assoc($t3_q)['title'] : '';
            $sql3 = "SELECT id, name, position FROM hr_employees WHERE status='active' AND (position_id=$approver_3_pos_id";
            if($t3) $sql3 .= " OR position LIKE '".mysqli_real_escape_string($dbConn, $t3)."'";
            $sql3 .= ")";
            $l3_q = mysqli_query($dbConn, $sql3);
            while($row = mysqli_fetch_assoc($l3_q)) $tertiary_approvers[] = $row;
        }
    }
}

$cur_yr = date('Y');
$bal = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT 
    SUM(CASE WHEN leave_type='sick' THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) as sick_taken,
    SUM(CASE WHEN leave_type='casual' THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) as casual_taken,
    SUM(CASE WHEN leave_type='earned' THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) as earned_taken,
    SUM(CASE WHEN leave_type='emergency' THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) as emergency_taken,
    SUM(CASE WHEN leave_type='unpaid' THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) as unpaid_taken,
    SUM(CASE WHEN leave_type='half_day' THEN COALESCE(leave_days, 0.5) ELSE 0 END) as half_day_taken,
    COUNT(CASE WHEN leave_type='half_day' THEN 1 END) as half_day_count,
    SUM(CASE WHEN leave_type='half_day' AND (half_day_session='first' OR half_day_session='') THEN 1 ELSE 0 END) as half_day_morning_count,
    SUM(CASE WHEN leave_type='half_day' AND half_day_session='second' THEN 1 ELSE 0 END) as half_day_afternoon_count
    FROM hr_leaves WHERE employee_id=$current_user_id AND status='approved' AND YEAR(start_date)=$cur_yr"));

// =========================================================================
// ONE-TIME BACKFILL: some leaves were converted to unpaid by an older version
// of this code, before original_leave_type existed, so nothing was saved to
// restore them to. Recover the original type from that leave's own request
// ticket subject (e.g. "[L1 Leave Request] Sick - 1 day(s) (Name)"), which was
// written at application time and still holds the real type.
// =========================================================================
$bf_q = mysqli_query($dbConn, "SELECT id FROM hr_leaves WHERE employee_id=$current_user_id AND leave_type='unpaid' AND original_leave_type IS NULL");
if ($bf_q) {
    while ($bf = mysqli_fetch_assoc($bf_q)) {
        $t_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT subject FROM tickets WHERE leave_id=" . intval($bf['id']) . " ORDER BY id ASC LIMIT 1"));
        if ($t_row && !empty($t_row['subject']) && preg_match('/\]\s*([A-Za-z]+)/', $t_row['subject'], $bm)) {
            $bf_label = strtolower(trim($bm[1]));
            if (in_array($bf_label, ['sick','casual','earned','emergency'])) {
                mysqli_query($dbConn, "UPDATE hr_leaves SET original_leave_type='$bf_label' WHERE id=" . intval($bf['id']));
            }
        }
    }
}

// =========================================================================
// Leaves APPLIED before this date are grandfathered -- the 9-month probation
// unpaid rule only governs leaves applied on/after this date. This is the
// date the rule went live; anything applied earlier keeps its original type.
// =========================================================================
$probation_rule_start_date = '2026-07-11';

// =========================================================================
// UNLOCK: restore any leave previously auto-converted to unpaid back to its
// original paid type, when EITHER (a) it was applied before the rule existed
// (grandfathered -- always restore, regardless of tenure), OR (b) the employee
// has now completed 9 months. Counting/balance logic is unchanged -- this only
// flips the type back for leaves that carry a saved original_leave_type.
// =========================================================================
$unlock_where = "employee_id=$current_user_id AND leave_type='unpaid' AND original_leave_type IS NOT NULL AND (created_at < '$probation_rule_start_date'";
if ($is_eligible_for_paid_leaves) $unlock_where .= " OR 1=1";
$unlock_where .= ")";
mysqli_query($dbConn, "UPDATE hr_leaves SET leave_type = original_leave_type WHERE $unlock_where");

// =========================================================================
// CHECK FOR RETROACTIVE PAID LEAVES TAKEN BEFORE ELIGIBILITY
// =========================================================================
$has_ineligible_paid_leaves = false;
$ineligible_leaves_list = [];
$auto_converted_count = 0;

if ($current_user_hire_date) {
    // Check ALL paid leaves to see if they were TAKEN before 9 months eligibility
    $check_query = mysqli_query($dbConn, "SELECT id, leave_type, start_date, end_date, status, created_at 
        FROM hr_leaves 
        WHERE employee_id=$current_user_id 
        AND leave_type IN ('sick', 'casual', 'earned', 'emergency')
        ORDER BY created_at DESC");
    
    if ($check_query && mysqli_num_rows($check_query) > 0) {
        $hire_date_obj = new DateTime($current_user_hire_date);
        
        while ($leave = mysqli_fetch_assoc($check_query)) {
            // Use the LEAVE START DATE (when leave was actually taken), not application date
            $leave_start_date = new DateTime($leave['start_date']);
            
            // Calculate months employed at the time of TAKING THE LEAVE
            $interval = $hire_date_obj->diff($leave_start_date);
            $months_at_leave_date = ($interval->y * 12) + $interval->m;
            
            // If leave was TAKEN before completing 9 months, it should be unpaid --
            // but only for leaves APPLIED after the rule went live. Anything applied
            // before that is grandfathered and keeps its original paid type.
            if ($months_at_leave_date < 9 && $leave['created_at'] >= $probation_rule_start_date) {
                $has_ineligible_paid_leaves = true;
                $old_type = $leave['leave_type'];
                
                // AUTO-CONVERT TO UNPAID (saves original type so it can be
                // restored automatically once 9 months are completed)
                $old_type_sql = mysqli_real_escape_string($dbConn, $old_type);
                mysqli_query($dbConn, "UPDATE hr_leaves SET leave_type='unpaid', original_leave_type='$old_type_sql' WHERE id={$leave['id']}");
                $auto_converted_count++;
                
                $ineligible_leaves_list[] = [
                    'id' => $leave['id'],
                    'old_type' => $old_type,
                    'type' => 'unpaid',
                    'start' => $leave['start_date'],
                    'end' => $leave['end_date'],
                    'status' => $leave['status'],
                    'applied' => $leave['created_at'],
                    'months_at_time' => $months_at_leave_date
                ];
            }
        }
    }
}

$sick_rem     = 7 - ($bal['sick_taken']??0);
$cas_rem      = 7 - ($bal['casual_taken']??0);
$ear_rem      = 8 - ($bal['earned_taken']??0);
$eml_rem      = 4 - ($bal['emergency_taken']??0);
$unpaid_taken       = $bal['unpaid_taken'] ?? 0;
$half_day_taken     = floatval($bal['half_day_taken'] ?? 0);
$half_day_count     = intval($bal['half_day_count'] ?? 0);
$half_day_morning   = intval($bal['half_day_morning_count'] ?? 0);
$half_day_afternoon = intval($bal['half_day_afternoon_count'] ?? 0);
$total_entitlement  = 26;

// =========================================================================
// ACCRUAL-BASED PAID LEAVE CALCULATION (2 leaves/month after 9-month probation)
// =========================================================================
$paid_leaves_per_month   = 2;
$paid_leaves_earned      = 0;
$paid_leaves_availed     = 0;
$paid_leaves_remaining   = 0;
$accrual_months_complete = 0;
$accrual_start_label     = null;
$joining_date_label      = null;

if ($current_user_hire_date && $is_eligible_for_paid_leaves) {
    $hire_dt         = new DateTime($current_user_hire_date);
    $eligibility_dt  = clone $hire_dt;
    $eligibility_dt->modify('+9 months');   // accrual starts after probation
    $joining_date_label  = $hire_dt->format('d M Y');       // actual date of joining
    $accrual_start_label = $eligibility_dt->format('d M Y'); // eligibility date

    $today_dt = new DateTime();

    // CHANGED: calendar-month based accrual, not hire-date-anniversary based.
    // Leaves credit on the 1st of each new calendar month, regardless of the
    // exact day-of-month the employee was hired on.
    $accrual_months_complete = (intval($today_dt->format("Y")) - intval($hire_dt->format("Y"))) * 12
                              + (intval($today_dt->format("n")) - intval($hire_dt->format("n")));
    
    // Earned: (Total Months - 3) * 2
    // Since they are eligible, they have >= 9 months.
    $paid_leaves_earned = max(0, ($accrual_months_complete - 3) * 2);
    
    $availed_res = mysqli_fetch_assoc(mysqli_query($dbConn, "
        SELECT
            SUM(CASE WHEN leave_type IN ('paid','sick','casual','earned','emergency')
                THEN COALESCE(leave_days, DATEDIFF(end_date,start_date)+1) ELSE 0 END) +
            SUM(CASE WHEN leave_type='half_day'
                THEN COALESCE(leave_days, 0.5) ELSE 0 END) as paid_availed
        FROM hr_leaves
        WHERE employee_id = $current_user_id
        AND status = 'approved'
    "));
    $paid_leaves_availed   = floatval($availed_res['paid_availed'] ?? 0);
    $paid_leaves_remaining = max(0, $paid_leaves_earned - $paid_leaves_availed);
} elseif (!$current_user_hire_date) {
    // No hire date — fall back to showing 0
    $paid_leaves_earned  = 0;
    $paid_leaves_availed = floatval($bal['sick_taken']      ?? 0)
                         + floatval($bal['casual_taken']    ?? 0)
                         + floatval($bal['earned_taken']    ?? 0)
                         + floatval($bal['emergency_taken'] ?? 0)
                         + floatval($bal['half_day_taken']  ?? 0);
    $paid_leaves_remaining = 0;
}

// Get all employee leave balances for admin view
$employee_balances = [];
if($is_admin) {
    $cur_yr = date('Y');
    $balance_query = "
        SELECT 
            e.id,
            e.name,
            e.employee_id,
            e.position,
            e.department,
            e.work_location,
            e.hire_date,
            
            COALESCE(SUM(CASE WHEN l.leave_type='unpaid' AND l.status='approved' THEN l.leave_days ELSE 0 END), 0) as unpaid_used,
            COALESCE(SUM(CASE WHEN l.leave_type='half_day' AND l.status='approved' THEN l.leave_days ELSE 0 END), 0) as half_day_used,
            COALESCE(COUNT(CASE WHEN l.leave_type='half_day' AND l.status='approved' THEN 1 END), 0) as half_day_count,
            
            -- Earned is calculated in PHP dynamically based on hire_date for each row
            0 as total_remaining
            
            -- Keep the overall paid_used for total_remaining calculation
            ,COALESCE(SUM(CASE WHEN l.leave_type IN ('paid','sick','casual','earned','emergency') AND l.status='approved' THEN l.leave_days ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN l.leave_type='half_day' AND l.status='approved' THEN l.leave_days ELSE 0 END), 0) as paid_used
        FROM hr_employees e
        LEFT JOIN hr_leaves l ON l.employee_id = e.id AND l.status = 'approved'
        WHERE e.status = 'active'
        GROUP BY e.id, e.name, e.employee_id, e.position, e.department, e.work_location, e.hire_date
        ORDER BY e.name ASC
    ";
    
    $balance_result = mysqli_query($dbConn, $balance_query);
    if($balance_result) {
        while($row = mysqli_fetch_assoc($balance_result)) {
            $employee_balances[] = $row;
        }
    }
}

$my_leaves = mysqli_query($dbConn, "SELECT l.*, l.half_day_session, e1.name as pri_name, e2.name as sec_name, e3.name as app_n, e4.name as rej_n, GROUP_CONCAT(t.ticket_number ORDER BY t.approver_level SEPARATOR ' | ') as t_nums, GROUP_CONCAT(t.status ORDER BY t.approver_level SEPARATOR ' | ') as t_stats, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count FROM hr_leaves l LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id LEFT JOIN hr_employees e3 ON l.approved_by=e3.id LEFT JOIN hr_employees e4 ON l.rejected_by=e4.id LEFT JOIN tickets t ON t.leave_id=l.id WHERE l.employee_id=$current_user_id GROUP BY l.id ORDER BY l.id DESC");

$all_leaves_system = null;
if($is_admin) {
    $all_leaves_system = mysqli_query($dbConn, "SELECT l.*, l.half_day_session, COALESCE(e.name, CONCAT('[Unknown Emp #', l.employee_id, ']')) as emp_name, COALESCE(e.position, 'Unknown') as emp_pos, COALESCE(e.work_location, '') as work_location, e1.name as pri_n, e2.name as sec_n, GROUP_CONCAT(t.ticket_number ORDER BY t.approver_level SEPARATOR ' | ') as t_nums, GROUP_CONCAT(t.status ORDER BY t.approver_level SEPARATOR ' | ') as t_stats, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count FROM hr_leaves l LEFT JOIN hr_employees e ON l.employee_id=e.id LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id LEFT JOIN tickets t ON t.leave_id=l.id GROUP BY l.id ORDER BY l.id DESC");
}

$approvals_pending = mysqli_query($dbConn, "SELECT l.*, l.half_day_session, COALESCE(e.name, CONCAT('[Unknown Emp #', l.employee_id, ']')) as emp_name, COALESCE(e.position, 'Unknown') as emp_pos, COALESCE(e.work_location, '') as work_location, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count, t.ticket_number as my_ticket, t.status as my_ticket_status FROM hr_leaves l LEFT JOIN hr_employees e ON l.employee_id=e.id LEFT JOIN tickets t ON t.leave_id=l.id AND t.assigned_to=$current_user_id WHERE (l.primary_approver_id=$current_user_id OR l.secondary_approver_id=$current_user_id) AND (t.status IS NULL OR LOWER(t.status) NOT IN ('approved','rejected','closed','resolved')) ORDER BY l.is_urgent DESC, l.created_at ASC");

// ============================================================================
// LEAVE OVERVIEW TAB DATA — Managing Director only. One row per leave request
// in the overview's own date range; department / position / type / monthly
// aggregation is done client-side in JS from this dataset, same low-risk
// approach used for the Payroll and Attendance Overview dashboards.
// ============================================================================
$leave_overview_records = [];
$lv_pending_count = $lv_approved_count = $lv_rejected_count = 0;
$lv_total_days_approved = 0;
$lv_emp_seen = [];
if($is_leave_overview_viewer) {
    $lv_data = mysqli_query($dbConn, "SELECT l.id, l.employee_id, l.start_date, l.end_date, l.leave_days, l.leave_type, l.status, l.created_at,
            COALESCE(e.name, CONCAT('[Unknown Emp #', l.employee_id, ']')) as emp_name,
            COALESCE(e.position,'Unassigned') as emp_pos,
            COALESCE(NULLIF(e.department,''),'Unassigned') as emp_dept,
            COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as emp_company
        FROM hr_leaves l
        LEFT JOIN hr_employees e ON l.employee_id = e.id
        WHERE l.start_date BETWEEN '$lv_filter_from' AND '$lv_filter_to'
        ORDER BY l.start_date ASC");
    if($lv_data) {
        while($lr = mysqli_fetch_assoc($lv_data)) {
            $lv_days = !empty($lr['leave_days']) ? floatval($lr['leave_days']) : ((new DateTime($lr['end_date']))->diff(new DateTime($lr['start_date']))->days + 1);
            $lv_status = strtolower($lr['status']);
            if($lv_status === 'pending') $lv_pending_count++;
            elseif($lv_status === 'approved') { $lv_approved_count++; $lv_total_days_approved += $lv_days; }
            elseif($lv_status === 'rejected') $lv_rejected_count++;
            $lv_emp_seen[$lr['employee_id']] = true;
            $leave_overview_records[] = [
                'employee'   => $lr['emp_name'],
                'emp_id'     => $lr['employee_id'],
                'department' => $lr['emp_dept'],
                'position'   => $lr['emp_pos'],
                'company'    => $lr['emp_company'],
                'type'       => $lr['leave_type'],
                'status'     => $lv_status,
                'days'       => $lv_days,
                'start_date' => $lr['start_date'],
                'end_date'   => $lr['end_date'],
                'month_label'=> date('M Y', strtotime($lr['start_date'])),
                'month'      => intval(date('n', strtotime($lr['start_date']))),
                'year'       => intval(date('Y', strtotime($lr['start_date']))),
                'applied_at' => date('d M Y', strtotime($lr['created_at'])),
            ];
        }
    }
}
$lv_total_records   = count($leave_overview_records);
$lv_total_employees = count($lv_emp_seen);
$lv_records_json    = json_encode($leave_overview_records);
$lv_from_dt = new DateTime($lv_filter_from);
$lv_to_dt   = new DateTime($lv_filter_to);
$lv_period_label = ($lv_from_dt->format('Y-m') === $lv_to_dt->format('Y-m'))
    ? $lv_from_dt->format('F Y')
    : $lv_from_dt->format('d M Y').' - '.$lv_to_dt->format('d M Y');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <title>Leave Management | CRM</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:20px 0; }
        .container-fluid { max-width:1600px; margin:0 auto; padding:0 20px; }
        .page-header { background:linear-gradient(135deg,#1e3a8a,#1e40af); padding:25px 32px; border-radius:12px; box-shadow:0 6px 20px rgba(30,58,138,0.3); margin-bottom:25px; display:flex; justify-content:space-between; align-items:center; color:white; }
        .page-header h1 { font-weight:700; margin:0; font-size:1.8rem; }
        .header-info { opacity:0.9; font-size:14px; margin-top:5px; }
        .btn-header { padding:12px 24px; border-radius:10px; font-weight:700; cursor:pointer; border:none; display:inline-flex; align-items:center; gap:8px; transition:0.3s; color:white; text-decoration:none; font-size:14px; }
        .btn-primary-custom { background:linear-gradient(135deg,#1e3a8a,#1e40af); }
        .btn-success-custom { background:linear-gradient(135deg,#10b981,#059669); }
        .btn-header:hover { transform:translateY(-2px); box-shadow:0 8px 25px rgba(0,0,0,0.15); color:white; text-decoration:none; }
        .stats-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:15px; margin-bottom:25px; }
        .stat-card { background:white; border-radius:12px; padding:18px; display:flex; align-items:center; gap:15px; border-left:5px solid; box-shadow:0 3px 12px rgba(0,0,0,0.08); }
        .stat-card.indigo { border-left-color:#4f46e5; } .stat-card.blue { border-left-color:#1e40af; } .stat-card.green { border-left-color:#10b981; } .stat-card.orange { border-left-color:#f59e0b; } .stat-card.purple { border-left-color:#9333ea; }
        .stat-icon { width:50px; height:50px; border-radius:10px; display:flex; align-items:center; justify-content:center; font-size:20px; color:white; }
        .stat-icon.indigo { background:linear-gradient(135deg,#4f46e5,#4338ca); } .stat-icon.blue { background:linear-gradient(135deg,#1e3a8a,#1e40af); } .stat-icon.green { background:linear-gradient(135deg,#10b981,#059669); } .stat-icon.orange { background:linear-gradient(135deg,#f59e0b,#d97706); } .stat-icon.purple { background:linear-gradient(135deg,#9333ea,#7e22ce); }
        .stat-content h3 { margin:0; font-size:26px; font-weight:800; color:#0f172a; }
        .stat-content p { margin:2px 0 0 0; font-size:11px; font-weight:700; color:#64748b; text-transform:uppercase; }
        .filter-bar { background:white; padding:25px; border-radius:12px; box-shadow:0 3px 12px rgba(0,0,0,0.08); margin-bottom:25px; border:1px solid #e2e8f0; }
        .nav-tabs { border:none; margin-bottom:0; }
        .nav-link { border:none !important; font-weight:700; color:#64748b; padding:15px 30px; border-radius:12px 12px 0 0 !important; }
        .nav-link.active { background:white !important; color:#1e3a8a !important; box-shadow:0 -4px 15px rgba(0,0,0,0.05); }
        .tab-content { background:white; padding:30px; border-radius:0 12px 12px 12px; box-shadow:0 10px 30px rgba(0,0,0,0.05); border:1px solid #e2e8f0; border-top:none; }
        table.table thead th { background:linear-gradient(135deg,#1e3a8a,#1e40af) !important; color:white !important; font-weight:800; padding:16px !important; border:none !important; font-size:14px; text-transform:uppercase; }
        table.table tbody td { padding:16px !important; vertical-align:middle !important; border-bottom:1px solid #f1f5f9 !important; font-size:15px; font-weight:700; color:#0f172a; }
        .badge-status { padding:6px 14px; border-radius:20px; font-weight:800; font-size:12px; text-transform:uppercase; }
        .badge-pending { background:#fef3c7; color:#92400e; }
        .badge-approved { background:#d1fae5; color:#065f46; }
        .badge-rejected { background:#fee2e2; color:#991b1b; }
        .t-badge { display:inline-block; padding:6px 15px; border-radius:8px; font-size:13px; font-weight:800; color:white; text-decoration:none; margin:2px; transition:0.2s; box-shadow:0 2px 5px rgba(0,0,0,0.1); letter-spacing:0.5px; cursor:default; }
        a.t-badge { cursor:pointer; } a.t-badge:hover { transform:translateY(-2px); text-decoration:none; color:white; }
        .t-green { background:linear-gradient(135deg,#10b981,#059669); } .t-red { background:linear-gradient(135deg,#ef4444,#dc2626); } .t-yellow { background:linear-gradient(135deg,#f59e0b,#d97706); }
        .btn-doc-wrapper { position:relative; display:inline-block; }
        .action-btn { width:40px; height:40px; border-radius:10px; border:2px solid #e2e8f0; background:#fff; color:#1e3a8a; display:inline-flex; align-items:center; justify-content:center; cursor:pointer; transition:0.3s; }
        .action-btn:hover { background:#1e3a8a; color:#fff; transform:scale(1.1); }
        .count-badge { position:absolute; top:-8px; right:-8px; background-color:#ef4444; color:white; border-radius:50%; font-size:10px; font-weight:800; width:20px; height:20px; display:flex; align-items:center; justify-content:center; border:2px solid #fff; z-index:10; }
        .form-control-modern { border:2px solid #e2e8f0; border-radius:10px; padding:12px 15px; font-size:14px; height:auto; transition:0.3s; width:100%; font-weight:600; }
        .form-control-modern:focus { border-color:#1e40af; box-shadow:0 0 0 4px rgba(30,64,175,0.1); outline:none; }
        .location-box { background:#f0f9ff; border:2px dashed #3b82f6; border-radius:15px; padding:20px; text-align:center; margin-bottom:20px; }
        .btn-location { background:linear-gradient(135deg,#f59e0b,#d97706); border:none; color:white; padding:10px 25px; border-radius:10px; font-weight:700; cursor:pointer; }
        .btn-submit-modern { background:linear-gradient(135deg,#10b981,#059669); border:none; color:white; width:100%; padding:15px; border-radius:12px; font-weight:800; font-size:16px; margin-top:15px; }
        .btn-submit-modern:disabled { opacity:0.6; cursor:not-allowed; }
        .lv-chart-card{background:white;border:1px solid #e2e8f0;border-radius:12px;padding:20px;box-shadow:0 3px 12px rgba(0,0,0,0.08);}
        .lv-chart-card h4{color:#1e3a8a;font-weight:700;margin-bottom:14px;font-size:15px;}
        .lv-chart-card .lv-ch-wrap{position:relative;height:280px;}
        .lv-charts-grid{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:25px;}
        @media (max-width:1100px){.lv-charts-grid{grid-template-columns:1fr!important;}}
        .lv-chip{display:inline-flex;align-items:center;gap:8px;background:#4338ca;color:white;padding:6px 12px;border-radius:20px;font-size:12px;font-weight:700;}
        .lv-chip button{background:rgba(255,255,255,.25);border:none;color:white;border-radius:12px;padding:2px 8px;font-weight:700;cursor:pointer;font-size:11px;}
        .lv-chip.clear-all{background:#64748b;cursor:pointer;}
        .lv-lb-row{cursor:pointer;}
        .lv-lb-row:hover{background:#f8fafc;}
    </style>
</head>
<body>
<div class="container-fluid">
    <div class="page-header">
        <div>
            <h1><i class="fas fa-calendar-check mr-2"></i> Leave Management</h1>
            <div class="header-info">Employee: <strong><?php echo $current_user_name; ?></strong> (<?php echo $current_user_position; ?>)</div>
        </div>
        <div class="d-flex" style="gap:15px;">
            <button class="btn-header btn-success-custom" data-toggle="modal" data-target="#applyLeaveModal"><i class="fas fa-plus-circle"></i> Request Leave</button>
            
        </div>
    </div>

    <?php if ($missing_hire_date): ?>
    <div style="background:linear-gradient(135deg,#fef3c7,#fde68a);border:3px solid #f59e0b;border-radius:15px;padding:25px;margin-bottom:25px;box-shadow:0 8px 20px rgba(245,158,11,0.2);">
        <div style="display:flex;align-items:center;gap:20px;">
            <div style="width:70px;height:70px;background:linear-gradient(135deg,#f59e0b,#d97706);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:32px;color:white;flex-shrink:0;">
                <i class="fas fa-exclamation-circle"></i>
            </div>
            <div style="flex:1;">
                <h4 style="margin:0 0 10px 0;color:#92400e;font-weight:800;font-size:18px;">
                    <i class="fas fa-calendar-times"></i> Missing Hire Date - Cannot Verify Eligibility
                </h4>
                <p style="margin:0;color:#78350f;font-size:15px;line-height:1.6;font-weight:600;">
                    Your employee profile does not have a <strong>hire date</strong> set.<br>
                    The system cannot verify your eligibility for paid leaves without this information.<br>
                    <strong style="color:#92400e;">⚠️ Please contact HR to update your hire date in the system.</strong>
                </p>
                <div style="background:#fff;border:2px solid #f59e0b;border-radius:10px;padding:12px;margin-top:12px;">
                    <p style="margin:0;color:#92400e;font-size:13px;font-weight:700;">
                        <i class="fas fa-tools"></i> <strong>For HR/Admin:</strong> 
                        <a href="check_employee_eligibility.php?name=<?php echo urlencode($current_user_name); ?>" 
                           style="color:#1e40af;text-decoration:underline;" target="_blank">
                            Click here to check and fix this employee's eligibility
                        </a>
                    </p>
                </div>
            </div>
        </div>
    </div>
    <?php endif; ?>

    <?php if ($has_ineligible_paid_leaves): ?>
    <div style="background:linear-gradient(135deg,#e0f2fe,#bae6fd);border:2px solid #0284c7;border-radius:12px;padding:25px;margin-bottom:25px;box-shadow:0 4px 12px rgba(2,132,199,0.15);">
        <div style="display:flex;align-items:flex-start;gap:20px;">
            <div style="width:60px;height:60px;background:linear-gradient(135deg,#0284c7,#0369a1);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:28px;color:white;flex-shrink:0;">
                <i class="fas fa-info-circle"></i>
            </div>
            <div style="flex:1;">
                <h4 style="margin:0 0 12px 0;color:#0c4a6e;font-weight:700;font-size:17px;">
                    Leave Policy Notice - Probation Period
                </h4>
                <p style="margin:0 0 15px 0;color:#075985;font-size:14px;line-height:1.7;font-weight:500;">
                    As per company policy, paid leaves are available only after completing 9 months of employment. 
                    Your leave(s) taken during the probation period have been adjusted to unpaid status.
                </p>
                <div style="background:#fff;border-radius:8px;padding:15px;border:1px solid #bae6fd;margin-bottom:15px;">
                    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:15px;margin-bottom:12px;">
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Joining Date</small>
                            <div style="color:#0c4a6e;font-weight:700;font-size:14px;"><?php echo date('d M Y', strtotime($current_user_hire_date)); ?></div>
                        </div>
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Current Tenure</small>
                            <div style="color:#0c4a6e;font-weight:700;font-size:14px;"><?php echo $months_since_joining; ?> month(s)</div>
                        </div>
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Paid Leaves From</small>
                            <div style="color:#059669;font-weight:700;font-size:14px;"><?php echo $eligibility_date; ?></div>
                        </div>
                    </div>
                    <div style="border-top:1px solid #e2e8f0;padding-top:12px;">
                        <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;display:block;margin-bottom:8px;">Adjusted Leaves:</small>
                        <?php foreach ($ineligible_leaves_list as $il): ?>
                        <div style="padding:8px 12px;background:#f8fafc;border-left:3px solid #0284c7;margin-bottom:6px;border-radius:4px;display:flex;justify-content:space-between;align-items:center;">
                            <div>
                                <span style="color:#0c4a6e;font-weight:600;font-size:13px;">
                                    <?php echo date('d M Y', strtotime($il['start'])); ?> - <?php echo date('d M Y', strtotime($il['end'])); ?>
                                </span>
                                <span style="color:#64748b;font-size:12px;margin-left:8px;">
                                    (Applied: <?php echo date('d M', strtotime($il['applied'])); ?>)
                                </span>
                            </div>
                            <div style="display:flex;align-items:center;gap:8px;">
                                <span style="color:#64748b;font-size:12px;font-weight:600;">Changed to:</span>
                                <span style="background:#059669;color:white;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:700;">
                                    💸 UNPAID
                                </span>
                            </div>
                        </div>
                        <?php endforeach; ?>
                    </div>
                </div>
                <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;padding:12px;">
                    <p style="margin:0;color:#075985;font-size:13px;font-weight:500;line-height:1.6;">
                        <i class="fas fa-lightbulb" style="color:#f59e0b;"></i> 
                        You can continue to apply for unpaid leaves during your probation period. 
                        All paid leave types (Sick, Casual, Earned, Emergency) will become available after <strong><?php echo $eligibility_date; ?></strong>.
                    </p>
                </div>
            </div>
        </div>
    </div>
    <?php endif; ?>

    <?php if (!$is_eligible_for_paid_leaves && $current_user_hire_date && !$has_ineligible_paid_leaves): ?>
    <div style="background:linear-gradient(135deg,#fef3c7,#fde68a);border:2px solid #f59e0b;border-radius:12px;padding:25px;margin-bottom:25px;box-shadow:0 4px 12px rgba(245,158,11,0.15);">
        <div style="display:flex;align-items:flex-start;gap:20px;">
            <div style="width:60px;height:60px;background:linear-gradient(135deg,#f59e0b,#d97706);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:28px;color:white;flex-shrink:0;">
                <i class="fas fa-hourglass-half"></i>
            </div>
            <div style="flex:1;">
                <h4 style="margin:0 0 12px 0;color:#92400e;font-weight:700;font-size:17px;">
                    Probation Period - Paid Leaves Not Yet Available
                </h4>
                <p style="margin:0 0 15px 0;color:#78350f;font-size:14px;line-height:1.7;font-weight:500;">
                    As per company policy, paid leave benefits become available after completing 9 months of employment. 
                    You can currently apply for unpaid leaves only.
                </p>
                <div style="background:#fff;border-radius:8px;padding:15px;border:1px solid #fde68a;">
                    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:15px;">
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Joining Date</small>
                            <div style="color:#92400e;font-weight:700;font-size:14px;"><?php echo date('d M Y', strtotime($current_user_hire_date)); ?></div>
                        </div>
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Completed</small>
                            <div style="color:#92400e;font-weight:700;font-size:14px;"><?php echo $months_since_joining; ?> of 9 months</div>
                        </div>
                        <div>
                            <small style="color:#64748b;font-size:11px;font-weight:600;text-transform:uppercase;">Eligible From</small>
                            <div style="color:#059669;font-weight:700;font-size:14px;"><?php echo $eligibility_date; ?></div>
                        </div>
                    </div>
                </div>
                <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:12px;margin-top:15px;">
                    <p style="margin:0;color:#78350f;font-size:13px;font-weight:500;line-height:1.6;">
                        <i class="fas fa-check-circle" style="color:#059669;"></i> 
                        You can apply for <strong>Unpaid Leave</strong> at any time. 
                        Paid leave types (Sick, Casual, Earned, Emergency) will be available after <strong><?php echo $eligibility_date; ?></strong>.
                    </p>
                </div>
            </div>
        </div>
    </div>
    <?php endif; ?>

    <ul class="nav nav-tabs" id="leaveTabs">
        <?php if($is_leave_overview_viewer): ?>
        <li class="nav-item"><a class="nav-link active" data-toggle="tab" href="#leaveOverview"><i class="fas fa-chart-line mr-1"></i> Overview</a></li>
        <?php endif; ?>
        <li class="nav-item"><a class="nav-link <?php echo !$is_leave_overview_viewer ? 'active' : ''; ?>" data-toggle="tab" href="#myLeaves">My Leaves</a></li>
        <?php if($is_admin): ?>
        <li class="nav-item"><a class="nav-link" data-toggle="tab" href="#allLeaves">All Employee Leaves</a></li>
        <li class="nav-item"><a class="nav-link" data-toggle="tab" href="#leaveBalances">Employee Leave Balances</a></li>
        <?php endif; ?>
        <?php if(mysqli_num_rows($approvals_pending)>0): ?><li class="nav-item"><a class="nav-link" data-toggle="tab" href="#approvals">Approvals <span class="badge badge-danger ml-1"><?php echo mysqli_num_rows($approvals_pending); ?></span></a></li><?php endif; ?>
    </ul>

    <div class="tab-content">
        <?php if($is_leave_overview_viewer): ?>
        <!-- LEAVE OVERVIEW (Managing Director only) -->
        <div id="leaveOverview" class="tab-pane fade show active">
            <div class="stats-row">
                <div class="stat-card blue"><div class="stat-icon blue"><i class="fas fa-calendar-day"></i></div><div class="stat-content"><h3><?php echo htmlspecialchars($lv_period_label); ?></h3><p>Overview Period</p></div></div>
                <div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-users"></i></div><div class="stat-content"><h3><?php echo $lv_total_employees; ?></h3><p>Employees With Requests</p></div></div>
                <div class="stat-card green"><div class="stat-icon green"><i class="fas fa-check-circle"></i></div><div class="stat-content"><h3><?php echo $lv_approved_count; ?></h3><p>Approved (<?php echo $lv_total_days_approved; ?> days)</p></div></div>
                <div class="stat-card orange"><div class="stat-icon orange"><i class="fas fa-hourglass-half"></i></div><div class="stat-content"><h3><?php echo $lv_pending_count; ?></h3><p>Pending</p></div></div>
                <div class="stat-card" style="border-left-color:#ef4444;"><div class="stat-icon" style="background:linear-gradient(135deg,#ef4444,#dc2626);color:white;"><i class="fas fa-times-circle"></i></div><div class="stat-content"><h3><?php echo $lv_rejected_count; ?></h3><p>Rejected</p></div></div>
            </div>

            <div class="filter-bar">
                <form method="POST" class="row" style="margin:0;align-items:flex-end;">
                    <input type="hidden" name="lv_tab_marker" value="1">
                    <div class="col-md-3 form-group"><label>From Date</label><input type="date" name="lv_filter_from" class="form-control-modern" value="<?php echo htmlspecialchars($lv_filter_from); ?>"></div>
                    <div class="col-md-3 form-group"><label>To Date</label><input type="date" name="lv_filter_to" class="form-control-modern" value="<?php echo htmlspecialchars($lv_filter_to); ?>"></div>
                    <div class="col-md-2 form-group"><button type="submit" name="lv_apply_filter" class="btn btn-primary btn-block" style="font-weight:700;height:48px;"><i class="fas fa-filter mr-1"></i> Apply</button></div>
                </form>
            </div>

            <?php if($lv_total_records === 0): ?>
                <div style="text-align:center;padding:60px 20px;color:#94a3b8;background:white;border-radius:12px;">
                    <i class="fas fa-inbox" style="font-size:40px;display:block;margin-bottom:12px;"></i> No leave requests found for this period.
                </div>
            <?php else: ?>

            <div class="filter-bar">
                <div class="row" style="align-items:flex-end;">
                    <div class="col-md-3 form-group"><label>Employee</label>
                        <select id="lvFilterEmployee" class="form-control-modern" onchange="lvApplyFilter('employee', this.value)">
                            <option value="">— All Employees —</option>
                        </select>
                    </div>
                    <div class="col-md-3 form-group"><label>Department</label>
                        <select id="lvFilterDept" class="form-control-modern" onchange="lvApplyFilter('department', this.value)">
                            <option value="">— All Departments —</option>
                        </select>
                    </div>
                    <div class="col-md-3 form-group"><label>Leave Type</label>
                        <select id="lvFilterType" class="form-control-modern" onchange="lvApplyFilter('type', this.value)">
                            <option value="">— All Types —</option>
                        </select>
                    </div>
                    <div class="col-md-3 form-group">
                        <button type="button" class="btn btn-secondary btn-block" style="font-weight:700;height:48px;" onclick="lvClearAllFilters()"><i class="fas fa-times mr-1"></i> Clear Filters</button>
                    </div>
                </div>
            </div>

            <div id="lvChips" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px;"></div>

            <div class="lv-charts-grid">
                <div class="lv-chart-card">
                    <h4><i class="fas fa-tags mr-1"></i> Days Taken by Leave Type <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
                    <div class="lv-ch-wrap"><canvas id="lvChartType"></canvas></div>
                </div>
                <div class="lv-chart-card">
                    <h4><i class="fas fa-sitemap mr-1"></i> Days Taken by Department <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
                    <div class="lv-ch-wrap"><canvas id="lvChartDept"></canvas></div>
                </div>
                <div class="lv-chart-card">
                    <h4><i class="fas fa-id-badge mr-1"></i> Days Taken by Position <small style="font-weight:600;color:#94a3b8;">(click a bar for details)</small></h4>
                    <div class="lv-ch-wrap"><canvas id="lvChartPosition"></canvas></div>
                </div>
                <div class="lv-chart-card">
                    <h4><i class="fas fa-chart-line mr-1"></i> Monthly Trend (Requests / Days) <small style="font-weight:600;color:#94a3b8;">(click a point for details)</small></h4>
                    <div class="lv-ch-wrap"><canvas id="lvChartTrend"></canvas></div>
                </div>
            </div>

            <div class="lv-chart-card" style="margin-bottom:25px;">
                <h4><i class="fas fa-trophy mr-1"></i> Employee Leaderboard <span id="lvLbCount" style="font-weight:600;font-size:12px;color:#94a3b8;"></span> <small style="font-weight:600;color:#94a3b8;">(click a row for full details)</small></h4>
                <div class="table-responsive" style="max-height:480px;overflow-y:auto;">
                    <table class="table" style="margin:0;">
                        <thead><tr><th>Employee</th><th>Department</th><th>Position</th><th>Requests</th><th>Approved Days</th><th>Pending</th><th>Rejected</th></tr></thead>
                        <tbody id="lvLbBody"></tbody>
                    </table>
                </div>
            </div>

            <?php endif; ?>
        </div>
        <?php endif; ?>

        <!-- MY LEAVES -->
        <div id="myLeaves" class="tab-pane fade <?php echo !$is_leave_overview_viewer ? 'show active' : ''; ?>">
            <!-- ACCRUAL-BASED PAID LEAVE SUMMARY CARD -->
            <div style="background:linear-gradient(135deg,#1e3a8a,#1e40af);border-radius:14px;padding:20px 25px;margin-bottom:20px;box-shadow:0 4px 15px rgba(30,58,138,0.25);color:white;">
                <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px;">
                    <div style="width:44px;height:44px;background:rgba(255,255,255,0.15);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0;">
                        <i class="fas fa-calendar-check"></i>
                    </div>
                    <div>
                        <div style="font-size:1.05rem;font-weight:700;letter-spacing:0.3px;">Paid Leave Balance</div>
                        <?php if($joining_date_label): ?>
                        <div style="font-size:0.78rem;opacity:0.8;margin-top:2px;">Date of Joining: <?php echo $joining_date_label; ?> &nbsp;|&nbsp; Paid Leave Eligible from: <?php echo $accrual_start_label; ?> &nbsp;|&nbsp; Rate: <?php echo $paid_leaves_per_month; ?> leaves/month &nbsp;|&nbsp; <?php echo $accrual_months_complete; ?> month(s) since joining</div>
                        <?php else: ?>
                        <div style="font-size:0.78rem;opacity:0.8;margin-top:2px;">Update your hire date in profile to see accrual details</div>
                        <?php endif; ?>
                    </div>
                </div>
                <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;">
                    <div style="background:rgba(255,255,255,0.12);border-radius:10px;padding:14px;text-align:center;border:1px solid rgba(255,255,255,0.2);">
                        <div style="font-size:2rem;font-weight:800;line-height:1;"><?php echo number_format($paid_leaves_earned, 1); ?></div>
                        <div style="font-size:0.78rem;opacity:0.9;margin-top:5px;font-weight:600;">Paid Leaves Earned<br><span style="opacity:0.75;font-weight:400;">from date of joining</span></div>
                    </div>
                    <div style="background:rgba(255,255,255,0.12);border-radius:10px;padding:14px;text-align:center;border:1px solid rgba(255,255,255,0.2);">
                        <div style="font-size:2rem;font-weight:800;line-height:1;color:#fcd34d;"><?php echo number_format($paid_leaves_availed, 1); ?></div>
                        <div style="font-size:0.78rem;opacity:0.9;margin-top:5px;font-weight:600;">Leaves Availed<br><span style="opacity:0.75;font-weight:400;">approved this year</span></div>
                    </div>
                    <div style="background:rgba(255,255,255,0.15);border-radius:10px;padding:14px;text-align:center;border:2px solid rgba(255,255,255,0.4);">
                        <div style="font-size:2rem;font-weight:800;line-height:1;color:#86efac;"><?php echo number_format($paid_leaves_remaining, 1); ?></div>
                        <div style="font-size:0.78rem;opacity:0.9;margin-top:5px;font-weight:600;">Remaining Balance<br><span style="opacity:0.75;font-weight:400;">available to use</span></div>
                    </div>
                </div>
            </div>

            <div class="stats-row">
                <div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-hand-holding-usd"></i></div><div class="stat-content"><h3><?php echo $unpaid_taken; ?></h3><p>Unpaid Taken</p></div></div>
                <div class="stat-card" style="border-left-color:#f59e0b;">
                    <div class="stat-icon" style="background:linear-gradient(135deg,#f59e0b,#d97706);color:white;"><i class="fas fa-adjust"></i></div>
                    <div class="stat-content">
                        <h3><?php echo $half_day_count; ?> <small style="font-size:13px;color:#92400e;">(<?php echo $half_day_taken; ?> days)</small></h3>
                        <p>Half Day Used</p>
                        <?php if($half_day_count > 0): ?>
                        <small style="color:#92400e;font-weight:600;">
                            🌅 <?php echo $half_day_morning; ?> Morning &nbsp;|&nbsp; 🌆 <?php echo $half_day_afternoon; ?> Afternoon
                        </small>
                        <?php endif; ?>
                    </div>
                </div>
            </div>

            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-filter mr-2"></i> Filter My Leaves</h6>
                <div class="row">
                    <div class="col-md-3 form-group"><label>From Date</label><input type="date" class="form-control-modern" id="myFilterFrom"></div>
                    <div class="col-md-3 form-group"><label>To Date</label><input type="date" class="form-control-modern" id="myFilterTo"></div>
                    <div class="col-md-2 form-group"><label>Type</label><select class="form-control-modern" id="myFilterType"><option value="">All</option><option value="sick">🤒 Sick</option><option value="casual">🏖️ Casual</option><option value="earned">💰 Earned</option><option value="emergency">🚨 Emergency</option><option value="unpaid">💸 Unpaid</option><option value="half_day">🌗 Half Day</option></select></div>
                    <div class="col-md-2 form-group"><label>Status</label><select class="form-control-modern" id="myFilterStatus"><option value="">All</option><option value="pending">Pending</option><option value="approved">Approved</option><option value="rejected">Rejected</option></select></div>
                    <div class="col-md-2" style="padding-top:31px;display:flex;gap:10px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyMyFilter()">Apply</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:60px;" onclick="exportToCSV('myLeavesTable','My_Leaves.csv')" title="Export"><i class="fas fa-file-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="myLeavesTable">
                    <thead><tr><th>Applied</th><th>Type</th><th>Dates</th><th>Approvers</th><th>Tickets</th><th>Status</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($my_leaves,0); while($l=mysqli_fetch_assoc($my_leaves)): $days = !empty($l['leave_days']) ? $l['leave_days'] : ((new DateTime($l['end_date']))->diff(new DateTime($l['start_date']))->days + 1); $days_label = (floatval($days) == 0.5) ? '½ day' : $days.' day(s)'; ?>
                    <tr data-start="<?php echo $l['start_date']; ?>" data-end="<?php echo $l['end_date']; ?>" data-type="<?php echo strtolower($l['leave_type']); ?>" data-status="<?php echo strtolower($l['status']); ?>">
                        <td><strong><?php echo date('d M Y',strtotime($l['created_at'])); ?></strong></td>
                        <td style="font-size:16px;"><?php echo get_leave_emoji($l['leave_type'], $l['half_day_session']??''); ?><br><small style="font-weight:600;color:#64748b;"><?php echo $days_label; ?></small><?php if($l['leave_type']==='half_day' && !empty($l['half_day_session'])): ?><br><?php echo get_half_session_badge($l['half_day_session']); ?><?php endif; ?></td>
                        <td style="white-space:nowrap;"><?php 
                            if($l['leave_type']==='half_day') {
                                echo date('d M Y',strtotime($l['start_date']));
                            } else {
                                echo date('d M',strtotime($l['start_date'])).' - '.date('d M Y',strtotime($l['end_date']));
                            }
                        ?></td>
                        <td style="font-size:12px;font-weight:600;">1: <?php echo $l['pri_name']; ?><br>2: <?php echo $l['sec_name']?:'—'; ?></td>
                        <td><?php $tks=explode(' | ',$l['t_nums']??""); $tst=explode(' | ',$l['t_stats']??""); foreach($tks as $idx=>$tk){ if(!$tk) continue; $st=strtolower($tst[$idx]??''); $cls='t-yellow'; if(in_array($st,['approved','closed','resolved','completed'])) $cls='t-green'; elseif($st=='rejected') $cls='t-red'; echo "<span class='t-badge $cls'>$tk</span>"; } ?></td>
                        <td>
                            <span class="badge-status badge-<?php echo $l['status']; ?>"><?php echo $l['status']; ?></span>
                            <?php if($l['app_n']) echo "<br><small class='text-success' style='font-weight:700;'>✓ {$l['app_n']}</small>"; ?>
                            <?php if($l['rej_n']) echo "<br><small class='text-danger' style='font-weight:700;'>✗ {$l['rej_n']}</small>"; ?>
                        </td>
                        <td><div class="btn-doc-wrapper"><button class="action-btn" onclick="viewDocs(<?php echo $l['id']; ?>)"><i class="fas fa-folder-open"></i></button><?php if($l['doc_count']>0): ?><span class="count-badge"><?php echo $l['doc_count']; ?></span><?php endif; ?></div></td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>

        <?php if($is_admin): ?>
        <!-- ALL EMPLOYEE LEAVES -->
        <div id="allLeaves" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-search mr-2"></i> Search Employee Leaves</h6>
                <div class="row">
                    <div class="col-md-2 form-group"><label>From Date</label><input type="date" class="form-control-modern" id="adminFilterFrom"></div>
                    <div class="col-md-2 form-group"><label>To Date</label><input type="date" class="form-control-modern" id="adminFilterTo"></div>
                    <div class="col-md-2 form-group"><label>Employee</label><select class="form-control-modern" id="adminFilterEmp"><option value="">All Employees</option><?php foreach($dropdown_employees as $e): ?><option value="<?php echo strtolower($e['name']); ?>"><?php echo $e['name']; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-2 form-group"><label>Location</label><select class="form-control-modern" id="adminFilterLoc"><option value="">All Locations</option><?php foreach($dropdown_locations as $loc): ?><option value="<?php echo strtolower($loc); ?>"><?php echo $loc; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-2 form-group"><label>Status</label><select class="form-control-modern" id="adminFilterStatus"><option value="">All</option><option value="pending">Pending</option><option value="approved">Approved</option><option value="rejected">Rejected</option></select></div>
                    <div class="col-md-2" style="padding-top:31px;display:flex;gap:10px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyAdminFilter()">Filter</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:60px;" onclick="exportToCSV('allLeavesTable','Company_Leaves.csv')" title="Export"><i class="fas fa-file-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="allLeavesTable">
                    <thead><tr><th>Employee</th><th>Location</th><th>Type</th><th>Duration</th><th>Days</th><th>Tickets</th><th>Status</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($all_leaves_system,0); while($l=mysqli_fetch_assoc($all_leaves_system)): ?>
                    <tr data-start="<?php echo $l['start_date']; ?>" data-end="<?php echo $l['end_date']; ?>" data-applied="<?php echo date('Y-m-d', strtotime($l['created_at'])); ?>" data-name="<?php echo strtolower($l['emp_name']); ?>" data-loc="<?php echo strtolower($l['work_location']??""); ?>" data-type="<?php echo strtolower($l['leave_type']); ?>" data-status="<?php echo strtolower($l['status']); ?>">
                        <td><strong><?php echo $l['emp_name']; ?></strong><br><small style="font-weight:600;color:#64748b;"><?php echo $l['emp_pos']; ?></small></td>
                        <td><?php echo $l['work_location']??"N/A"; ?></td>
                        <td style="font-size:16px;"><?php echo get_leave_emoji($l['leave_type'], $l['half_day_session']??''); ?><?php if($l['leave_type']==='half_day' && !empty($l['half_day_session'])): ?><br><?php echo get_half_session_badge($l['half_day_session']); ?><?php endif; ?></td>
                        <td style="font-size:13px;"><?php 
                            if($l['leave_type']==='half_day') {
                                echo date('d M Y',strtotime($l['start_date']));
                            } else {
                                echo date('d M',strtotime($l['start_date'])).' - '.date('d M',strtotime($l['end_date']));
                            }
                        ?></td>
                        <td><strong><?php 
                            $ld = !empty($l['leave_days']) ? floatval($l['leave_days']) : ((new DateTime($l['end_date']))->diff(new DateTime($l['start_date']))->days+1);
                            echo ($ld == 0.5) ? '½' : $ld;
                        ?></strong></td>
                        <td><?php $tks=explode(' | ',$l['t_nums']??""); $tst=explode(' | ',$l['t_stats']??""); foreach($tks as $idx=>$tk){ if(!$tk) continue; $st=strtolower($tst[$idx]??''); $cls='t-yellow'; if(in_array($st,['approved','closed','resolved','completed'])) $cls='t-green'; elseif($st=='rejected') $cls='t-red'; echo "<span class='t-badge $cls'>$tk</span>"; } ?></td>
                        <td><span class="badge-status badge-<?php echo $l['status']; ?>"><?php echo $l['status']; ?></span></td>
                        <td><div class="btn-doc-wrapper"><button class="action-btn" onclick="viewDocs(<?php echo $l['id']; ?>)"><i class="fas fa-folder-open"></i></button><?php if($l['doc_count']>0): ?><span class="count-badge"><?php echo $l['doc_count']; ?></span><?php endif; ?></div></td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- EMPLOYEE LEAVE BALANCES (ADMIN ONLY) -->
        <?php if($is_admin): ?>
        <div id="leaveBalances" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-chart-bar mr-2"></i> Employee Leave Balances - <?php echo date('Y'); ?></h6>
                <div class="row">
                    <div class="col-md-2 form-group"><label>Employee</label><select class="form-control-modern" id="balanceFilterEmp"><option value="">All Employees</option><?php foreach($dropdown_employees as $e): ?><option value="<?php echo strtolower($e['name']); ?>"><?php echo $e['name']; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-2 form-group"><label>Department</label><input type="text" class="form-control-modern" id="balanceFilterDept" placeholder="Filter by department"></div>
                    <div class="col-md-2 form-group"><label>Location</label><select class="form-control-modern" id="balanceFilterLoc"><option value="">All Locations</option><?php foreach($dropdown_locations as $loc): ?><option value="<?php echo strtolower($loc); ?>"><?php echo $loc; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-2 form-group"><label>Eligibility</label>
                        <select class="form-control-modern" id="balanceFilterEligibility">
                            <option value="">All</option>
                            <option value="eligible">✅ Eligible for Paid Leave</option>
                            <option value="probation">⏳ Not Eligible (Probation)</option>
                        </select>
                    </div>
                    <div class="col-md-2" style="padding-top:31px;display:flex;gap:10px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyBalanceFilter()">Filter</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:60px;" onclick="exportToCSV('balancesTable','Leave_Balances_<?php echo date('Y'); ?>.csv')" title="Export"><i class="fas fa-file-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="balancesTable">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Position</th>
                            <th>Location</th>
                            <th>Eligibility</th>
                            <th style="background:#10b981 !important;">🌟 Paid Leave<br><small>Used</small></th>
                            <th style="background:#6366f1 !important;">💸 Unpaid<br><small>Used</small></th>
                            <th style="background:#d97706 !important;">🌗 Half Day<br><small>Used</small></th>
                            <th style="background:#059669 !important;">Remaining Paid</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php foreach($employee_balances as $eb): ?>
                    <?php
                        // Compute eligibility once per row using the SAME calendar-month
                        // logic used for the main accrual calculation above, so the badge,
                        // the filter, and the "Remaining Paid" figure all agree with each other.
                        $eb_is_eligible = false;
                        $eb_months_employed = 0;
                        if (!empty($eb['hire_date'])) {
                            $eb_hire_dt = new DateTime($eb['hire_date']);
                            $eb_today_dt = new DateTime();
                            $eb_months_employed = (intval($eb_today_dt->format("Y")) - intval($eb_hire_dt->format("Y"))) * 12
                                                 + (intval($eb_today_dt->format("n")) - intval($eb_hire_dt->format("n")));
                            $eb_is_eligible = ($eb_months_employed >= 9);
                        }
                    ?>
                    <tr data-name="<?php echo strtolower($eb['name']); ?>" data-dept="<?php echo strtolower($eb['department']??''); ?>" data-loc="<?php echo strtolower($eb['work_location']??''); ?>" data-eligible="<?php echo $eb_is_eligible ? 'eligible' : 'probation'; ?>">
                        <td><strong><?php echo $eb['name']; ?></strong><br><small style="color:#64748b;font-size:11px;"><?php echo $eb['employee_id']; ?></small></td>
                        <td style="font-size:13px;"><?php echo $eb['position']; ?></td>
                        <td style="font-size:13px;"><?php echo $eb['work_location']?:'N/A'; ?></td>
                        <td style="text-align:center;">
                            <?php if ($eb_is_eligible): ?>
                                <span style="background:#d1fae5;color:#065f46;padding:4px 10px;border-radius:20px;font-size:11px;font-weight:800;white-space:nowrap;">✅ Eligible</span>
                            <?php else: ?>
                                <span style="background:#fef3c7;color:#92400e;padding:4px 10px;border-radius:20px;font-size:11px;font-weight:800;white-space:nowrap;">⏳ Probation (<?php echo $eb_months_employed; ?>/9 mo)</span>
                            <?php endif; ?>
                        </td>
                        <td style="text-align:center;">
                            <div style="font-size:18px;font-weight:800;color:#059669;">
                                <?php echo $eb['paid_used']; ?>
                            </div>
                            <small style="color:#64748b;font-weight:600;">days taken</small>
                        </td>
                        <td style="text-align:center;">
                            <div style="font-size:18px;font-weight:800;color:#6366f1;">
                                <?php echo $eb['unpaid_used']; ?>
                            </div>
                            <small style="color:#64748b;font-weight:600;">days taken</small>
                        </td>
                        <td style="text-align:center;">
                            <?php $hd_used = floatval($eb['half_day_used']??0); $hd_cnt = intval($eb['half_day_count']??0); ?>
                            <div style="font-size:18px;font-weight:800;color:#d97706;">
                                <?php echo $hd_cnt; ?> <small style="font-size:12px;"><?php echo $hd_cnt===1?'time':'times'; ?></small>
                            </div>
                            <?php if($hd_cnt > 0): ?>
                            <small style="color:#92400e;font-weight:600;display:block;">= <?php echo $hd_used; ?> day(s)</small>
                            <?php else: ?>
                            <small style="color:#94a3b8;font-weight:600;">none taken</small>
                            <?php endif; ?>
                        </td>
                        <td style="text-align:center;">
                            <?php
                                // Reuse eligibility computed above for this row -- no second
                                // recalculation, so this figure can never disagree with the badge.
                                $admin_total_rem = 0;
                                if ($eb_is_eligible) {
                                    $emp_earned = max(0, ($eb_months_employed - 3) * 2);
                                    $admin_total_rem = max(0, $emp_earned - floatval($eb['paid_used']));
                                }
                            ?>
                            <div style="font-size:22px;font-weight:800;color:<?php echo $admin_total_rem<5?'#dc2626':($admin_total_rem<10?'#f59e0b':'#059669'); ?>">
                                <?php echo $admin_total_rem; ?>
                            </div>
                            <small style="color:#64748b;font-weight:600;">paid days</small>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- APPROVALS -->
        <div id="approvals" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-bell mr-2"></i> Pending Approvals</h6>
                <div class="row">
                    <div class="col-md-2 form-group"><label>From Date</label><input type="date" class="form-control-modern" id="approvalFilterFrom"></div>
                    <div class="col-md-2 form-group"><label>To Date</label><input type="date" class="form-control-modern" id="approvalFilterTo"></div>
                    <div class="col-md-3 form-group"><label>Employee</label><select class="form-control-modern" id="approvalFilterEmp"><option value="">All Employees</option><?php foreach($dropdown_employees as $e): ?><option value="<?php echo strtolower($e['name']); ?>"><?php echo $e['name']; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-2 form-group"><label>Location</label><select class="form-control-modern" id="approvalFilterLoc"><option value="">All Locations</option><?php foreach($dropdown_locations as $loc): ?><option value="<?php echo strtolower($loc); ?>"><?php echo $loc; ?></option><?php endforeach; ?></select></div>
                    <div class="col-md-3" style="padding-top:31px;display:flex;gap:10px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyApprovalFilter()">Search</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:60px;" onclick="exportToCSV('approvalsTable','Pending_Approvals.csv')" title="Export"><i class="fas fa-file-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="approvalsTable">
                    <thead><tr><th>Employee</th><th>Leave Type</th><th>Dates</th><th>Days</th><th>Reason</th><th>Ticket</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($approvals_pending,0); while($a=mysqli_fetch_assoc($approvals_pending)): $days = !empty($a['leave_days']) ? floatval($a['leave_days']) : ((new DateTime($a['end_date']))->diff(new DateTime($a['start_date']))->days+1); $days_lbl = ($days==0.5)?'½ day':$days.' day(s)'; $st=strtolower($a['my_ticket_status']??''); $cls='t-yellow'; if(in_array($st,['approved','closed','resolved'])) $cls='t-green'; elseif($st=='rejected') $cls='t-red'; ?>
                    <tr data-start="<?php echo $a['start_date']; ?>" data-end="<?php echo $a['end_date']; ?>" data-name="<?php echo strtolower($a['emp_name']); ?>" data-loc="<?php echo strtolower($a['work_location']??''); ?>">
                        <td><strong><?php echo $a['emp_name']; ?></strong><br><small style="font-weight:600;color:#64748b;"><?php echo $a['emp_pos']; ?></small></td>
                        <td style="font-size:15px;"><?php echo get_leave_emoji($a['leave_type'], $a['half_day_session']??''); ?><?php if($a['leave_type']==='half_day' && !empty($a['half_day_session'])): ?><br><?php echo get_half_session_badge($a['half_day_session']); ?><?php endif; ?></td>
                        <td style="font-size:13px;"><?php 
                            if($a['leave_type']==='half_day') echo date('d M Y',strtotime($a['start_date']));
                            else echo date('d M',strtotime($a['start_date'])).' – '.date('d M Y',strtotime($a['end_date']));
                        ?></td>
                        <td><strong><?php echo $days_lbl; ?></strong></td>
                        <td style="max-width:250px;font-size:13px;"><?php echo $a['reason']; ?></td>
                        <td><?php if($a['my_ticket']): ?><a href="/dashboard/my-tickets.php?ticket_number=<?php echo $a['my_ticket']; ?>" target="_blank" class="t-badge <?php echo $cls; ?>"><?php echo $a['my_ticket']; ?></a><?php else: echo '<span class="text-muted small">No Ticket</span>'; endif; ?></td>
                        <td><div class="btn-doc-wrapper"><button class="action-btn" onclick="viewDocs(<?php echo $a['id']; ?>)"><i class="fas fa-folder-open"></i></button><?php if($a['doc_count']>0): ?><span class="count-badge"><?php echo $a['doc_count']; ?></span><?php endif; ?></div></td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>

<!-- Modal: Apply Leave -->
<div class="modal fade" id="applyLeaveModal" tabindex="-1">
    <div class="modal-dialog modal-lg"><div class="modal-content">
        <div class="modal-header"><h4 class="modal-title"><i class="fas fa-paper-plane mr-2"></i> Request Leave</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
            <form id="leaveForm">
                <input type="hidden" id="leave_emp_id" value="<?php echo $current_user_id; ?>">
                <input type="hidden" id="lHalfSession" value="">

                <!-- STEP 1: Leave Type FIRST -->
                <div class="form-group">
                    <label style="font-weight:800;color:#1e3a8a;font-size:14px;">① Leave Type *</label>
                    <?php if (!$is_eligible_for_paid_leaves): ?>
                    <div style="background:#fee2e2;border:2px solid #dc2626;border-radius:10px;padding:12px;margin-bottom:10px;color:#991b1b;font-size:13px;font-weight:700;">
                        <i class="fas fa-lock"></i> Paid leaves locked until 9 months. Only Unpaid Leave available.
                    </div>
                    <?php endif; ?>
                    <select class="form-control-modern" id="lType" required onchange="handleLeaveTypeChange(this.value)">
                        <option value="">-- Select Leave Type --</option>
                        <?php if ($is_eligible_for_paid_leaves): ?>
                        <option value="sick">🤒 Sick Leave</option>
                        <option value="casual">🏖️ Casual Leave</option>
                        <option value="earned">💰 Earned Leave</option>
                        <option value="emergency">🚨 Emergency Leave</option>
                        <?php endif; ?>
                        <option value="unpaid">💸 Unpaid Leave</option>
                    </select>
                    <!-- FEATURE: live remaining-balance indicator, updates as type/dates change -->
                    <div id="leaveBalanceHint" style="display:none;margin-top:8px;padding:10px 14px;border-radius:8px;font-size:12px;font-weight:700;"></div>
                </div>

                <!-- STEP 2: Date range with start/end half-day options -->
                <div id="dateSection" style="display:none;">
                    <div style="background:#f0fdf4;border:2px solid #10b981;border-radius:12px;padding:16px;margin-bottom:18px;">
                        <label style="font-weight:800;color:#065f46;font-size:14px;display:block;margin-bottom:14px;">② Select Dates &amp; Leave Duration</label>

                        <!-- Start Date Row -->
                        <div class="row" style="margin-bottom:12px;">
                            <div class="col-md-5">
                                <label style="font-weight:700;font-size:13px;color:#1e40af;">Start Date *</label>
                                <input type="date" class="form-control-modern" id="lStart" onchange="recalcDays()">
                            </div>
                            <div class="col-md-7">
                                <label style="font-weight:700;font-size:13px;color:#1e40af;">On the start date, when does leave begin?</label>
                                <div style="display:flex;gap:8px;margin-top:4px;">
                                    <label id="lblStartFull" style="flex:1;display:flex;align-items:center;gap:6px;padding:9px 12px;border-radius:8px;border:2px solid #10b981;background:#f0fdf4;cursor:pointer;font-weight:700;font-size:12px;color:#065f46;transition:all 0.15s;">
                                        <input type="radio" name="start_half" value="full" checked onchange="recalcDays()"> 🌅 From Morning<br><span style="font-size:10px;font-weight:500;color:#64748b;">Off the whole day</span>
                                    </label>
                                    <label id="lblStartAM" style="flex:1;display:flex;align-items:center;gap:6px;padding:9px 12px;border-radius:8px;border:2px solid #e2e8f0;background:#fff;cursor:pointer;font-weight:700;font-size:12px;color:#64748b;transition:all 0.15s;">
                                        <input type="radio" name="start_half" value="second" onchange="recalcDays()"> 🌆 From Afternoon<br><span style="font-size:10px;font-weight:500;color:#64748b;">Work morning, leave from 1 PM</span>
                                    </label>
                                </div>
                            </div>
                        </div>

                        <!-- End Date Row -->
                        <div class="row" style="margin-bottom:12px;">
                            <div class="col-md-5">
                                <label style="font-weight:700;font-size:13px;color:#1e40af;">End Date *</label>
                                <input type="date" class="form-control-modern" id="lEnd" onchange="recalcDays()">
                            </div>
                            <div class="col-md-7">
                                <label style="font-weight:700;font-size:13px;color:#1e40af;">On the end date, when do you return?</label>
                                <div style="display:flex;gap:8px;margin-top:4px;">
                                    <label id="lblEndFull" style="flex:1;display:flex;align-items:center;gap:6px;padding:9px 12px;border-radius:8px;border:2px solid #10b981;background:#f0fdf4;cursor:pointer;font-weight:700;font-size:12px;color:#065f46;transition:all 0.15s;">
                                        <input type="radio" name="end_half" value="full" checked onchange="recalcDays()"> 🌙 End of Day<br><span style="font-size:10px;font-weight:500;color:#64748b;">Off till end of day</span>
                                    </label>
                                    <label id="lblEndPM" style="flex:1;display:flex;align-items:center;gap:6px;padding:9px 12px;border-radius:8px;border:2px solid #e2e8f0;background:#fff;cursor:pointer;font-weight:700;font-size:12px;color:#64748b;transition:all 0.15s;">
                                        <input type="radio" name="end_half" value="first" onchange="recalcDays()"> 🌤️ Back by Afternoon<br><span style="font-size:10px;font-weight:500;color:#64748b;">On leave till 1 PM, return after</span>
                                    </label>
                                </div>
                            </div>
                        </div>

                        <!-- Day-by-day calendar breakdown -->
                        <div id="dayCalendarBox" style="display:none;margin-top:12px;">
                            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;flex-wrap:wrap;gap:8px;">
                                <div style="font-size:12px;font-weight:700;color:#1e40af;">
                                    ③ Your leave days — <span style="color:#dc2626;">uncheck any holidays / optional offs</span>
                                </div>
                                <div style="font-size:11px;color:#64748b;">
                                    <span style="background:#f1f5f9;padding:2px 7px;border-radius:4px;margin-right:4px;">☐ = not counted</span>
                                    <span style="background:#dcfce7;padding:2px 7px;border-radius:4px;margin-right:4px;">✓ Full day</span>
                                    <span style="background:#fef3c7;padding:2px 7px;border-radius:4px;">✓ Half day</span>
                                </div>
                            </div>
                            <div id="dayGrid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:7px;max-height:280px;overflow-y:auto;padding:4px 2px;"></div>
                            <div id="calcDaysError" style="display:none;background:#fee2e2;border:2px solid #dc2626;border-radius:8px;padding:10px;margin-top:8px;color:#991b1b;font-size:13px;font-weight:600;"></div>
                            <!-- Summary bar -->
                            <div id="calcSummaryBar" style="display:none;background:white;border:2px solid #3b82f6;border-radius:10px;padding:12px 16px;margin-top:10px;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;">
                                <div id="calcSummaryText" style="font-size:12px;color:#475569;flex:1;"></div>
                                <div style="text-align:right;">
                                    <div style="font-size:11px;color:#64748b;font-weight:700;text-transform:uppercase;">Total Leave Days</div>
                                    <div style="font-size:30px;font-weight:900;color:#1e40af;line-height:1;" id="calcDaysNum">0</div>
                                </div>
                            </div>
                            <input type="hidden" id="lDays" value="0">
                        </div>
                        <div id="calcDaysBox" style="display:none;"></div>
                    </div>
                </div>

                <!-- STEP 3: GPS -->
                <div id="gpsSection" style="display:none;">
                    <div class="location-box" id="locBox">
                        <label style="font-weight:800;color:#1e40af;">④ <i class="fas fa-map-marker-alt"></i> Location Check-in (Required)</label>
                        <input type="hidden" id="lLat"><input type="hidden" id="lLng"><input type="hidden" id="lAddr">
                        <input type="text" id="lDisplay" class="form-control-modern mb-2 text-center" readonly placeholder="Waiting for GPS capture..." style="background:#fff;">
                        <button type="button" class="btn-location" id="btnCapture" onclick="getGPS()"><i class="fas fa-crosshairs"></i> Capture My Location</button>
                    </div>
                </div>

                <!-- STEP 4: Approvers + Reason -->
                <div id="approverSection" style="display:none;">
                    <div class="row">
                        <div class="col-md-4 form-group">
                            <label style="font-weight:700;">⑤ L1 Approver (Primary) *</label>
                            <select class="form-control-modern" id="lPri" required>
                                <?php if(empty($primary_approvers)): ?><option value="">-- No Approver Found --</option>
                                <?php else: foreach($primary_approvers as $p): ?><option value="<?php echo $p['id']; ?>" selected><?php echo $p['name']; ?> (<?php echo $p['position']; ?>)</option><?php endforeach; endif; ?>
                            </select>
                        </div>
                        <div class="col-md-4 form-group">
                            <label style="font-weight:700;">L2 Approver (Secondary)</label>
                            <select class="form-control-modern" id="lSec">
                                <?php if(empty($secondary_approvers)): ?><option value="">-- No Secondary Approver --</option>
                                <?php else: foreach($secondary_approvers as $s): ?><option value="<?php echo $s['id']; ?>" selected><?php echo $s['name']; ?> (<?php echo $s['position']; ?>)</option><?php endforeach; ?><option value="">(Optional) Remove Secondary</option><?php endif; ?>
                            </select>
                        </div>
                        <div class="col-md-4 form-group">
                            <label style="font-weight:700;">L3 Approver (Tertiary)</label>
                            <select class="form-control-modern" id="lTer">
                                <?php if(empty($tertiary_approvers)): ?><option value="">-- No Tertiary Approver --</option>
                                <?php else: foreach($tertiary_approvers as $t): ?><option value="<?php echo $t['id']; ?>" selected><?php echo $t['name']; ?> (<?php echo $t['position']; ?>)</option><?php endforeach; ?><option value="">(Optional) Remove Tertiary</option><?php endif; ?>
                            </select>
                        </div>
                    </div>
                    <div class="form-group"><label style="font-weight:700;">Reason for Leave *</label><textarea class="form-control-modern" id="lReason" rows="3" required placeholder="Explain why you are requesting leave..."></textarea></div>
                    <div class="form-group">
                        <label style="font-weight:700;">Attach Supporting Documents (Optional)</label>
                        <input type="file" id="lFiles" multiple class="form-control-modern" style="height:auto;padding:10px;">
                        <div id="fileListDisplay" class="mt-2" style="font-size:12px;color:#1e3a8a;"></div>
                    </div>
                    <button type="button" class="btn-submit-modern" id="lSubmitBtn">SUBMIT LEAVE APPLICATION</button>
                </div>

            </form>
        </div>
    </div></div>
</div>

<!-- Modal: Docs -->
<div class="modal fade" id="docsModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header"><h4><i class="fas fa-folder-open mr-2"></i> Documents Viewer</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div><div class="modal-body" id="docsContent">Loading documents...</div></div></div></div>

<!-- LEAVE OVERVIEW DRILL-DOWN MODAL — raw records for the clicked chart
     segment or leaderboard row, matching the Payroll/Attendance pattern. -->
<div class="modal fade" id="lvDrillModal" tabindex="-1">
  <div class="modal-dialog modal-lg" style="max-width:900px;">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;">
        <h4 id="lvDrillModalTitle"><i class="fas fa-list mr-2"></i> Details</h4>
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      </div>
      <div class="modal-body" style="max-height:500px;overflow-y:auto;">
        <table class="table table-sm" style="font-size:12px;margin:0;">
          <thead style="background:#eef2ff;">
            <tr>
              <th>Employee</th><th>Department</th><th>Position</th><th>Type</th>
              <th>Dates</th><th>Days</th><th>Status</th><th>Applied</th>
            </tr>
          </thead>
          <tbody id="lvDrillModalBody"></tbody>
        </table>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button></div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
$(document).ready(function(){
    setDefaults();
    $('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
        const t=$(e.target).attr("href");
        if(t==="#myLeaves") applyMyFilter();
        if(t==="#allLeaves") applyAdminFilter();
        if(t==="#approvals") applyApprovalFilter();
    });
    // Reset form when modal closes
    $('#applyLeaveModal').on('hidden.bs.modal', function(){
        $('#leaveForm')[0].reset();
        $('#lType').val('');
        $('#lDays').val(0);
        $('#dateSection,#gpsSection,#approverSection').hide();
        $('#dayCalendarBox,#calcSummaryBar').hide();
        $('#dayGrid').html('');
        $('#lLat,#lLng,#lAddr').val('');
        $('#lDisplay').val('');
        $('#locBox').css({'border-color':'','background':''});
        $('#btnCapture').html('<i class="fas fa-crosshairs"></i> Capture My Location').prop('disabled',false);
        $('input[name="start_half"][value="full"]').prop('checked',true);
        $('input[name="end_half"][value="full"]').prop('checked',true);
        $('#lHalfSession').val('');
    });
});

function setDefaults(){
    const now=new Date(), fmt=d=>d.toISOString().split('T')[0];

    // My Leaves & Approvals: current month
    const mStart=new Date(now.getFullYear(),now.getMonth(),1);
    const mEnd=new Date(now.getFullYear(),now.getMonth()+1,0);
    if($('#myFilterFrom').length){ $('#myFilterFrom').val(fmt(mStart)); $('#myFilterTo').val(fmt(mEnd)); applyMyFilter(); }
    if($('#approvalFilterFrom').length){ $('#approvalFilterFrom').val(fmt(mStart)); $('#approvalFilterTo').val(fmt(mEnd)); applyApprovalFilter(); }

    // ✅ FIX: Admin view defaults to FULL CURRENT MONTH (not just this week)
    // Previously used a week window — so leaves for next week (e.g. 24 Feb applied today 20 Feb)
    // were invisible to admin until they manually widened the date range.
    // Now admin sees everything applied OR starting within the current month by default.
    if($('#adminFilterFrom').length){
        $('#adminFilterFrom').val(fmt(mStart));
        $('#adminFilterTo').val(fmt(mEnd));
        applyAdminFilter();
    }
}

function handleLeaveTypeChange(val) {
    if(val) {
        $('#dateSection').show();
        $('#gpsSection').show();
        $('#approverSection').show();
    } else {
        $('#dateSection').hide();
        $('#gpsSection').hide();
        $('#approverSection').hide();
    }
    recalcDays();
}

// ============================================================
// HELPERS
// ============================================================
const DAY_NAMES   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const MONTH_NAMES = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

// FEATURE: remaining paid-leave balance for the logged-in employee, computed
// server-side the same way as the admin balances table (caps: sick 7, casual 7,
// earned 8, emergency 4 per year), so the "X remaining" hint below always matches
// what HR sees.
const totalPaidRemaining = <?php echo max(0, floatval($paid_leaves_remaining)); ?>;
const leaveTypeLabels = { sick: 'Sick Leave', casual: 'Casual Leave', earned: 'Earned Leave', emergency: 'Emergency Leave' };

function updateBalanceHint() {
    const box  = $('#leaveBalanceHint');
    const type = $('#lType').val();
    if(!type || !['sick','casual','earned','emergency'].includes(type)) { box.hide(); return; }

    const requested = parseFloat($('#lDays').val()) || 0;
    const label = leaveTypeLabels[type];

    if(requested > 0 && requested > totalPaidRemaining) {
        box.css({background:'#fee2e2', border:'2px solid #dc2626', color:'#991b1b'})
           .html('⚠️ You only have <strong>' + totalPaidRemaining + '</strong> total Paid Leave(s) remaining, but this request is for <strong>' + requested + '</strong> day(s).')
           .show();
    } else {
        box.css({background:'#f0fdf4', border:'2px solid #10b981', color:'#065f46'})
           .html('✅ You have <strong>' + totalPaidRemaining + '</strong> total Paid Leave(s) available. You can apply for this ' + label + '.')
           .show();
    }
}

function fmtDate(d) {
    return ('0'+d.getDate()).slice(-2)+' '+MONTH_NAMES[d.getMonth()];
}
function dateKey(d) {
    return d.getFullYear()+'-'+('0'+(d.getMonth()+1)).slice(-2)+'-'+('0'+d.getDate()).slice(-2);
}
function parseLocalDate(str) {
    const p = str.split('-');
    return new Date(parseInt(p[0]), parseInt(p[1])-1, parseInt(p[2]));
}

// ============================================================
// MAIN RECALC — builds day grid
// ============================================================
function recalcDays() {
    const startStr  = $('#lStart').val();
    const endStr    = $('#lEnd').val();
    const startHalf = $('input[name="start_half"]:checked').val() || 'full';
    const endHalf   = $('input[name="end_half"]:checked').val()   || 'full';

    // Highlight radio labels
    $('label[id^="lblStart"]').css({'border-color':'#e2e8f0','background':'#fff','color':'#64748b'});
    $('label[id^="lblEnd"]').css({'border-color':'#e2e8f0','background':'#fff','color':'#64748b'});
    if(startHalf==='full') $('#lblStartFull').css({'border-color':'#10b981','background':'#f0fdf4','color':'#065f46'});
    else                   $('#lblStartAM').css({'border-color':'#f59e0b','background':'#fef3c7','color':'#92400e'});
    if(endHalf==='full')   $('#lblEndFull').css({'border-color':'#10b981','background':'#f0fdf4','color':'#065f46'});
    else                   $('#lblEndPM').css({'border-color':'#3b82f6','background':'#dbeafe','color':'#1e40af'});

    if(!startStr || !endStr) {
        $('#dayCalendarBox').hide(); $('#calcSummaryBar').hide(); return;
    }

    // ── SAME-DAY CONTRADICTION CHECK ──────────────────────────
    if(startStr === endStr && startHalf === 'second' && endHalf === 'first') {
        $('#dayCalendarBox').show();
        $('#dayGrid').html(`
            <div style="grid-column:1/-1;background:#fef2f2;border:2px solid #dc2626;border-radius:10px;padding:16px 18px;">
                <div style="font-size:15px;font-weight:800;color:#dc2626;margin-bottom:6px;">
                    ❌ Contradictory selection
                </div>
                <div style="font-size:13px;color:#7f1d1d;line-height:1.6;">
                    You selected <strong>Afternoon Start</strong> AND <strong>Morning End</strong> on the same day.<br>
                    That means you'd start from the afternoon but also end by morning — which is impossible on the same day.<br><br>
                    <strong>What did you mean?</strong><br>
                    • Taking the <strong>morning off</strong> (coming in at 1 PM) → Set Start = <em>Full Day</em>, End = <em>Morning End</em><br>
                    • Taking the <strong>afternoon off</strong> (leaving at 1 PM) → Set Start = <em>Afternoon Start</em>, End = <em>Full Day</em><br>
                    • Taking the <strong>whole day</strong> → Set both to <em>Full Day</em>
                </div>
            </div>`);
        $('#calcSummaryBar').hide();
        $('#lDays').val(0);
        return;
    }

    if(endStr < startStr) {
        $('#dayCalendarBox').show();
        $('#dayGrid').html('<div style="grid-column:1/-1;color:#dc2626;font-weight:700;padding:10px;">❌ End date cannot be before start date.</div>');
        $('#calcSummaryBar').hide(); $('#lDays').val(0); return;
    }

    const start = parseLocalDate(startStr);
    const end   = parseLocalDate(endStr);
    const diffMs = end - start;

    if(diffMs > 60 * 86400000) {
        $('#dayCalendarBox').show();
        $('#dayGrid').html('<div style="grid-column:1/-1;color:#dc2626;font-weight:700;padding:10px;">❌ Range too large (max 60 days).</div>');
        $('#calcSummaryBar').hide(); $('#lDays').val(0); return;
    }

    // ── BUILD GRID ─────────────────────────────────────────────
    let grid = '';
    const cur = new Date(start);

    while(cur <= end) {
        const key     = dateKey(cur);
        const dow     = cur.getDay();
        const isSun   = (dow === 0);
        const isSat   = (dow === 6);
        const isStart = (key === startStr);
        const isEnd   = (key === endStr);
        const isSameDay = (startStr === endStr);

        // Determine weight & label for this day
        let weight = 1, halfLabel = '', halfBadgeStyle = '';

        if(isSameDay && isStart && isEnd) {
            if(startHalf==='second') {
                weight=0.5; halfLabel='🌆 Afternoon off'; halfBadgeStyle='background:#fef3c7;color:#92400e;';
            } else if(endHalf==='first') {
                weight=0.5; halfLabel='🌅 Morning off'; halfBadgeStyle='background:#dbeafe;color:#1e40af;';
            } else {
                weight=1; halfLabel='Full Day'; halfBadgeStyle='background:#dcfce7;color:#166534;';
            }
        } else if(isStart && startHalf==='second') {
            weight=0.5; halfLabel='🌆 PM start (−½)'; halfBadgeStyle='background:#fef3c7;color:#92400e;';
        } else if(isEnd && endHalf==='first') {
            weight=0.5; halfLabel='🌅 AM end (−½)'; halfBadgeStyle='background:#dbeafe;color:#1e40af;';
        } else {
            halfLabel='Full'; halfBadgeStyle='background:#dcfce7;color:#166534;';
        }

        if(isSun) {
            // Sunday — unchecked by default (most don't work), but can be ticked if they did
            grid += `<label style="display:flex;flex-direction:column;gap:3px;border:2px dashed #c084fc;border-radius:8px;padding:8px 10px;background:#faf5ff;cursor:pointer;opacity:0.7;transition:all 0.15s;" class="day-card sun-card" data-weight="${weight}">
                <div style="display:flex;align-items:center;gap:6px;">
                    <input type="checkbox" class="day-check" data-weight="${weight}" data-key="${key}" data-issun="1" style="width:15px;height:15px;flex-shrink:0;">
                    <span style="font-weight:700;font-size:12px;color:#7e22ce;">Sun ${fmtDate(cur)}</span>
                </div>
                <div style="display:flex;gap:4px;flex-wrap:wrap;">
                    <span style="background:#f3e8ff;color:#7e22ce;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;">☀️ Sunday</span>
                    ${weight < 1 ? `<span style="padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;${halfBadgeStyle}">${halfLabel}</span>` : ''}
                </div>
                <div style="font-size:10px;color:#9333ea;margin-top:1px;">Tick only if you worked this Sunday</div>
            </label>`;
        } else if(isSat) {
            // Saturday — shown with a warning, checked by default (working Saturday),
            // employee can uncheck if it's an off-Saturday
            const satBorder = '#f59e0b';
            const satBg     = '#fffbeb';
            grid += `<label style="display:flex;flex-direction:column;gap:3px;border:2px solid ${satBorder};border-radius:8px;padding:8px 10px;background:${satBg};cursor:pointer;transition:all 0.15s;" class="day-card" data-weight="${weight}">
                <div style="display:flex;align-items:center;gap:6px;">
                    <input type="checkbox" class="day-check" data-weight="${weight}" data-key="${key}" checked style="width:15px;height:15px;flex-shrink:0;">
                    <span style="font-weight:700;font-size:12px;">Sat ${fmtDate(cur)}</span>
                </div>
                <div style="display:flex;align-items:center;gap:5px;flex-wrap:wrap;">
                    <span style="padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;${halfBadgeStyle}">${halfLabel}</span>
                    <span style="background:#fef9c3;color:#854d0e;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;">⚠️ Saturday</span>
                </div>
                <div style="font-size:10px;color:#92400e;margin-top:1px;">Uncheck if this is a non-working Saturday</div>
            </label>`;
        } else {
            // Normal working day
            const borderColor = weight<1 ? '#f59e0b' : (isStart||isEnd ? '#3b82f6' : '#10b981');
            const bgColor     = weight<1 ? '#fffbeb' : (isStart||isEnd ? '#eff6ff' : '#f0fdf4');
            const edgeBadge   = (isStart&&!isSameDay)
                ? '<span style="background:#dbeafe;color:#1e40af;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;">Start</span>'
                : ((isEnd&&!isSameDay)
                ? '<span style="background:#dbeafe;color:#1e40af;padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;">End</span>'
                : '');

            grid += `<label style="display:flex;flex-direction:column;gap:3px;border:2px solid ${borderColor};border-radius:8px;padding:8px 10px;background:${bgColor};cursor:pointer;transition:all 0.15s;" class="day-card" data-weight="${weight}">
                <div style="display:flex;align-items:center;gap:6px;">
                    <input type="checkbox" class="day-check" data-weight="${weight}" data-key="${key}" checked style="width:15px;height:15px;flex-shrink:0;">
                    <span style="font-weight:700;font-size:12px;">${DAY_NAMES[dow]} ${fmtDate(cur)}</span>
                </div>
                <div style="display:flex;align-items:center;gap:5px;flex-wrap:wrap;">
                    <span style="padding:1px 6px;border-radius:4px;font-size:10px;font-weight:700;${halfBadgeStyle}">${halfLabel}</span>
                    ${edgeBadge}
                </div>
            </label>`;
        }
        cur.setDate(cur.getDate() + 1);
    }

    $('#dayGrid').html(grid);
    $('#dayCalendarBox').show();
    updateTotalFromGrid();
}

// ── UPDATE TOTAL FROM CHECKED BOXES ──────────────────────────
function updateTotalFromGrid() {
    let total = 0, checkedCount = 0, halfCount = 0, sunCount = 0;
    $('.day-check:checked').each(function(){
        const w = parseFloat($(this).data('weight'));
        total += w;
        checkedCount++;
        if(w < 1) halfCount++;
        if($(this).data('issun')) sunCount++;
    });
    total = Math.round(total * 2) / 2;
    $('#lDays').val(total);
    updateBalanceHint();

    if(total === 0) { $('#calcSummaryBar').hide(); return; }

    const fullDays  = checkedCount - halfCount;
    const unchecked = $('.day-check').length - checkedCount;
    let parts = [];
    if(fullDays  > 0) parts.push(fullDays  + ' full day'  + (fullDays !==1?'s':''));
    if(halfCount > 0) parts.push(halfCount + ' half day'  + (halfCount!==1?'s':''));
    if(unchecked > 0) parts.push(unchecked + ' holiday/off excluded');
    if(sunCount  > 0) parts.push(sunCount  + ' Sunday'    + (sunCount !==1?'s':'')+' (working)');

    const daysLabel = total===0.5 ? '½' : (total%1!==0 ? total.toFixed(1) : total);
    $('#calcDaysNum').html(daysLabel + '<span style="font-size:14px;color:#64748b;margin-left:3px;">day'+(total!==1?'s':'')+'</span>');
    $('#calcSummaryText').html(parts.join(' + '));
    $('#calcSummaryBar').css('display','flex').show();

    // Derive half_day_session for DB
    const startHalf = $('input[name="start_half"]:checked').val()||'full';
    const endHalf   = $('input[name="end_half"]:checked').val()||'full';
    if(startHalf==='second') $('#lHalfSession').val('second');
    else if(endHalf==='first') $('#lHalfSession').val('first');
    else $('#lHalfSession').val('');
}

// Live update when employee ticks/unticks a day card
$(document).on('change', '.day-check', function(){
    const card   = $(this).closest('label');
    const isSun  = $(this).data('issun');
    const isSat  = card.find('span:contains("Saturday")').length > 0;
    const isHalf = parseFloat($(this).data('weight')) < 1;
    if($(this).is(':checked')) {
        if(isSun)       card.css({'opacity':'1','border-color':'#9333ea','border-style':'solid','background':'#f3e8ff'});
        else if(isSat)  card.css({'opacity':'1','border-color':'#f59e0b','border-style':'solid'});
        else if(isHalf) card.css({'opacity':'1','border-color':'#f59e0b','border-style':'solid'});
        else            card.css({'opacity':'1','border-color':'#10b981','border-style':'solid'});
    } else {
        card.css({'opacity':'0.38','border-color':'#e2e8f0','border-style':'dashed','background':'#f8fafc'});
    }
    updateTotalFromGrid();
});

// Radio highlight effect (legacy)
$(document).on('change', 'input[name="half_session_ui"]', function() {
    $('#lHalfSession').val($(this).val());
});

// Auto-set end date = start when end is empty
$('#lStart').on('change', function() {
    if(!$('#lEnd').val()) $('#lEnd').val($(this).val());
    recalcDays();
});

// ── HALF-DAY CONFIRMATION POPUP ───────────────────────────────
// Shows before GPS step when total is 0.5 or has half-boundaries
function showHalfDayConfirm(days, onConfirm) {
    const startHalf = $('input[name="start_half"]:checked').val()||'full';
    const endHalf   = $('input[name="end_half"]:checked').val()||'full';
    const startStr  = $('#lStart').val();
    const endStr    = $('#lEnd').val();
    const isSameDay = startStr === endStr;

    let msg = '', workMsg = '';

    if(days === 0.5 && isSameDay) {
        if(startHalf === 'second') {
            msg      = '🌆 <strong>Afternoon Off</strong> on ' + startStr;
            workMsg  = 'You are expected to be at work <strong>in the morning (9 AM – 1 PM)</strong>.<br>You will leave from <strong>1 PM onwards</strong>.';
        } else {
            msg      = '🌅 <strong>Morning Off</strong> on ' + startStr;
            workMsg  = 'You are expected to come to work <strong>in the afternoon (1 PM – 6 PM)</strong>.<br>You are off in the <strong>morning session</strong>.';
        }
    } else if(days % 1 !== 0) {
        // Has a half-day boundary
        if(startHalf === 'second') {
            msg     = '🌆 Leave starts <strong>afternoon of ' + startStr + '</strong>';
            workMsg = 'On your first day, you should be at work in the <strong>morning (9 AM – 1 PM)</strong> and leave from 1 PM.';
        } else if(endHalf === 'first') {
            msg     = '🌅 Leave ends <strong>morning of ' + endStr + '</strong>';
            workMsg = 'On your last day, you return to work in the <strong>afternoon (1 PM – 6 PM)</strong>.';
        }
    } else {
        // Whole days — no popup needed, go straight to GPS
        onConfirm(); return;
    }

    // Build popup
    const popup = $(`
        <div id="halfDayPopup" style="position:fixed;inset:0;background:rgba(0,0,0,0.55);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;">
            <div style="background:white;border-radius:16px;padding:28px 32px;max-width:440px;width:100%;box-shadow:0 20px 60px rgba(0,0,0,0.3);">
                <div style="font-size:28px;text-align:center;margin-bottom:12px;">⏰</div>
                <h4 style="color:#1e3a8a;font-weight:800;text-align:center;margin-bottom:8px;">Confirm Your Half-Day Leave</h4>
                <div style="background:#fef3c7;border:2px solid #f59e0b;border-radius:10px;padding:14px;margin-bottom:14px;text-align:center;font-size:14px;font-weight:600;color:#92400e;">${msg}</div>
                <div style="background:#f0fdf4;border:2px solid #10b981;border-radius:10px;padding:14px;margin-bottom:20px;font-size:13px;color:#065f46;line-height:1.7;">
                    <strong>📋 Your work schedule on this day:</strong><br>${workMsg}
                </div>
                <div style="display:flex;gap:12px;">
                    <button id="popupCancel" style="flex:1;padding:12px;border-radius:10px;border:2px solid #e2e8f0;background:white;font-weight:700;font-size:14px;cursor:pointer;color:#64748b;">✏️ Change</button>
                    <button id="popupConfirm" style="flex:1;padding:12px;border-radius:10px;border:none;background:linear-gradient(135deg,#10b981,#059669);color:white;font-weight:800;font-size:14px;cursor:pointer;">✅ Yes, Confirm</button>
                </div>
            </div>
        </div>`);

    $('body').append(popup);

    $('#popupConfirm').on('click', function(){
        $('#halfDayPopup').remove();
        onConfirm();
    });
    $('#popupCancel').on('click', function(){
        $('#halfDayPopup').remove();
    });
}

function getGPS(){
    if(!navigator.geolocation) return alert('GPS not supported');
    $('#btnCapture').html('<i class="fas fa-spinner fa-spin"></i> Locating...').prop('disabled',true);
    navigator.geolocation.getCurrentPosition(p=>{
        const lat=p.coords.latitude, lng=p.coords.longitude;
        $('#lLat').val(lat); $('#lLng').val(lng);
        fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`).then(r=>r.json()).then(d=>{
            const a=d.display_name||lat+','+lng;
            $('#lAddr').val(a); $('#lDisplay').val(a);
            $('#locBox').css({'border-color':'#10b981','background':'#f0fdf4'});
            $('#btnCapture').html('<i class="fas fa-check-circle"></i> Captured').prop('disabled',false);
        });
    }, e=>{ alert('GPS Error: Enable location access'); $('#btnCapture').html('<i class="fas fa-crosshairs"></i> Retry').prop('disabled',false); },{enableHighAccuracy:true});
}

function getDocLocationAjax(){
    navigator.geolocation.getCurrentPosition(p=>{
        const lat=p.coords.latitude, lng=p.coords.longitude;
        $('#docLatitude').val(lat); $('#docLongitude').val(lng);
        fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`).then(r=>r.json()).then(d=>{ $('#docAddress').val(d.display_name); $('#docLocationDisplay').val(d.display_name); });
    });
}
function validateDocUpload(){ if(!$('#docLatitude').val()){ alert("❌ Location check-in is required!"); return false; } return true; }

$('#lFiles').on('change',function(){ const files=$(this)[0].files; let str=""; for(let i=0;i<files.length;i++) str+="<div><i class='fas fa-paperclip mr-1'></i> "+files[i].name+"</div>"; $('#fileListDisplay').html(str); });

// ✅ FIX 3: Button disabled immediately on click — prevents double-submit from rapid clicks
$('#lSubmitBtn').on('click', function(){
    if(!$('#lLat').val()) return alert('❌ GPS Check-in is mandatory!');
    if(!$('#lPri').val()) return alert('❌ Primary (L1) Approver is required!');
    const lType = $('#lType').val();
    if(!lType) return alert('❌ Please select a leave type!');
    const startDate = $('#lStart').val();
    const endDate   = $('#lEnd').val();
    if(!startDate || !endDate) return alert('❌ Please select start and end dates!');
    if(endDate < startDate) return alert('❌ End date cannot be before start date!');
    const lDaysVal = parseFloat($('#lDays').val());
    if(!lDaysVal || lDaysVal <= 0) return alert('❌ Leave days could not be calculated. Please check your dates and selections.');
    if(!$('#lReason').val().trim()) return alert('❌ Reason is required!');

    // ✅ STRICT LOCK: block submission client-side when request exceeds remaining balance
    // (server also enforces this -- this just avoids a round-trip for the common case)
    if(['sick','casual','earned','emergency'].includes(lType)) {
        if(lDaysVal > totalPaidRemaining) {
            return alert('❌ Insufficient Leave Balance!\n\nYou only have ' + totalPaidRemaining + ' Paid Leave(s) remaining, but this request is for ' + lDaysVal + ' day(s).\n\nPlease reduce the number of days or choose Unpaid Leave.');
        }
    }

    // Show half-day confirmation popup if needed, then submit
    showHalfDayConfirm(lDaysVal, function() {
        doSubmitLeave();
    });
});

function doSubmitLeave() {
    const btn = $('#lSubmitBtn');
    btn.prop('disabled',true).text('⏳ SUBMITTING... PLEASE WAIT');

    const lType      = $('#lType').val();
    const startDate  = $('#lStart').val();
    const endDate    = $('#lEnd').val();
    const lDaysVal   = parseFloat($('#lDays').val());
    const halfSession = $('#lHalfSession').val() || '';

    const fd=new FormData();
    fd.append('ajax_create_leave','1');
    fd.append('employee_id',$('#leave_emp_id').val());
    fd.append('primary_approver_id',$('#lPri').val());
    fd.append('secondary_approver_id',$('#lSec').val());
    fd.append('tertiary_approver_id',$('#lTer').val());
    fd.append('start_date', startDate);
    fd.append('end_date',   endDate);
    fd.append('leave_days', lDaysVal);
    fd.append('leave_type', lType);
    fd.append('half_day_session', halfSession);
    fd.append('reason',$('#lReason').val());
    fd.append('latitude',$('#lLat').val());
    fd.append('longitude',$('#lLng').val());
    fd.append('address',$('#lAddr').val());
    const files=$('#lFiles')[0].files;
    for(let i=0;i<files.length;i++) fd.append('leave_documents[]',files[i]);

    $.ajax({
        url:'<?php echo $_SERVER["PHP_SELF"]; ?>',
        type:'POST', data:fd, processData:false, contentType:false,
        success: r=>{
            if(typeof r === 'string') {
                try { r = JSON.parse(r); } catch(e) {
                    alert("Server error: " + r.substring(0, 100));
                    console.error("RAW JSON ERROR:", r);
                    btn.prop('disabled',false).text('SUBMIT LEAVE APPLICATION');
                    return;
                }
            }
            if(r.success){
                alert(r.message);
                location.reload();
            } else {
                alert(r.message || '❌ Something went wrong.');
                btn.prop('disabled',false).text('SUBMIT LEAVE APPLICATION');
            }
        },
        error: (xhr)=>{ alert('Network Error: ' + xhr.responseText.substring(0, 100)); btn.prop('disabled',false).text('SUBMIT LEAVE APPLICATION'); }
    });
}

function viewDocs(id){ $('#docsModal').modal('show'); $('#docsContent').html('<div class="text-center p-5"><i class="fas fa-spinner fa-spin fa-2x"></i></div>'); $.get('?ajax_get_documents=1&leave_id='+id,r=>$('#docsContent').html(r)); }

function applyMyFilter(){
    const fDate=$('#myFilterFrom').val(),tDate=$('#myFilterTo').val(),lType=$('#myFilterType').val(),lStat=$('#myFilterStatus').val();
    $('#myLeavesTable tbody tr').each(function(){ const rS=$(this).data('start'),rT=$(this).data('type'),rSt=$(this).data('status'); let show=true; if(fDate&&rS<fDate)show=false; if(tDate&&rS>tDate)show=false; if(lType&&rT!=lType)show=false; if(lStat&&rSt!=lStat)show=false; $(this).toggle(show); });
}
function applyAdminFilter(){
    const fDate=$('#adminFilterFrom').val(),tDate=$('#adminFilterTo').val(),name=$('#adminFilterEmp').val(),loc=$('#adminFilterLoc').val(),status=$('#adminFilterStatus').val();
    $('#allLeavesTable tbody tr').each(function(){
        // ✅ FIX: Match on EITHER applied date OR leave start date
        // A leave applied today (20 Feb) for next week (24 Feb) must show up
        // when admin's date filter covers the applied date (20 Feb) OR the start date (24 Feb)
        const rApplied=$(this).data('applied'), rS=$(this).data('start'), rN=$(this).data('name'), rL=$(this).data('loc'), rSt=$(this).data('status');
        let show=true;
        if(fDate && tDate){
            // Show if applied date OR start date falls within the selected range
            const inRangeByApplied = rApplied && rApplied>=fDate && rApplied<=tDate;
            const inRangeByStart   = rS && rS>=fDate && rS<=tDate;
            if(!inRangeByApplied && !inRangeByStart) show=false;
        } else {
            if(fDate && rS<fDate && (!rApplied||rApplied<fDate)) show=false;
            if(tDate && rS>tDate && (!rApplied||rApplied>tDate)) show=false;
        }
        if(name&&rN!=name)show=false;
        if(loc&&rL!=loc)show=false;
        if(status&&rSt!=status)show=false;
        $(this).toggle(show);
    });
}
function applyApprovalFilter(){
    const fDate=$('#approvalFilterFrom').val(),tDate=$('#approvalFilterTo').val(),name=$('#approvalFilterEmp').val(),loc=$('#approvalFilterLoc').val();
    $('#approvalsTable tbody tr').each(function(){ const rS=$(this).data('start'),rN=$(this).data('name'),rL=$(this).data('loc'); let show=true; if(fDate&&rS<fDate)show=false; if(tDate&&rS>tDate)show=false; if(name&&rN!=name)show=false; if(loc&&rL!=loc)show=false; $(this).toggle(show); });
}
function applyBalanceFilter(){
    const name=$('#balanceFilterEmp').val(),dept=$('#balanceFilterDept').val().toLowerCase(),loc=$('#balanceFilterLoc').val(),elig=$('#balanceFilterEligibility').val();
    $('#balancesTable tbody tr').each(function(){ 
        const rN=$(this).data('name'),rD=$(this).data('dept'),rL=$(this).data('loc'),rE=$(this).data('eligible'); 
        let show=true; 
        if(name&&rN!=name)show=false; 
        if(dept&&rD.indexOf(dept)===-1)show=false; 
        if(loc&&rL!=loc)show=false; 
        if(elig&&rE!=elig)show=false;
        $(this).toggle(show); 
    });
}
function exportToCSV(tableId,filename){
    let csv=[]; const rows=document.querySelectorAll('#'+tableId+' tr:not([style*="display: none"])');
    for(let i=0;i<rows.length;i++){ let row=[]; const cols=rows[i].querySelectorAll('td,th'); for(let j=0;j<cols.length;j++){ let txt=cols[j].innerText.replace(/"/g,'""').replace(/\n/g,' ').trim(); row.push('"'+txt+'"'); } csv.push(row.join(',')); }
    const blob=new Blob(['\ufeff'+csv.join('\n')],{type:'text/csv;charset=utf-8;'}); const link=document.createElement('a'); link.href=URL.createObjectURL(blob); link.download=filename; link.click();
}
</script>

<?php if($is_leave_overview_viewer && $lv_total_records > 0): ?>
<script>
const lvRecords = <?php echo $lv_records_json; ?>;

let lvFilters = { department: '', position: '', employee: '', type: '', month: '' };
let lvTypeChart, lvDeptChart, lvPositionChart, lvTrendChart;

function lvGroupDays(records, keyFn){
    const map = {};
    records.forEach(r => {
        if(r.status !== 'approved') return;
        const k = keyFn(r);
        if(!map[k]) map[k] = { days:0, count:0 };
        map[k].days += r.days; map[k].count++;
    });
    return map;
}

function lvFilteredRecords(){
    return lvRecords.filter(r =>
        (!lvFilters.department || r.department === lvFilters.department) &&
        (!lvFilters.position   || r.position   === lvFilters.position) &&
        (!lvFilters.employee   || r.employee   === lvFilters.employee) &&
        (!lvFilters.type       || r.type       === lvFilters.type) &&
        (!lvFilters.month      || r.month_label === lvFilters.month)
    );
}

function lvApplyFilter(type, value){
    lvFilters[type] = value;
    if(type === 'department') document.getElementById('lvFilterDept').value = value;
    if(type === 'employee')   document.getElementById('lvFilterEmployee').value = value;
    if(type === 'type')       document.getElementById('lvFilterType').value = value;
    lvRenderAll();
}

function lvClearOneFilter(type){ lvApplyFilter(type, ''); }

function lvClearAllFilters(){
    lvFilters = { department: '', position: '', employee: '', type: '', month: '' };
    document.getElementById('lvFilterDept').value = '';
    document.getElementById('lvFilterEmployee').value = '';
    document.getElementById('lvFilterType').value = '';
    lvRenderAll();
}

function lvRenderAll(){
    lvRefreshCharts();
    lvRenderLeaderboard();
    lvRenderChips();
}

function lvRenderChips(){
    const labels = { department: 'Department', position: 'Position', employee: 'Employee', type: 'Type', month: 'Month' };
    const active = Object.keys(lvFilters).filter(k => lvFilters[k]);
    const box = document.getElementById('lvChips');
    if(active.length === 0){ box.innerHTML = ''; return; }
    box.innerHTML = active.map(k =>
        `<span class="lv-chip">${labels[k]}: ${lvFilters[k]} <button onclick="lvClearOneFilter('${k}')">\u2715</button></span>`
    ).join('') + (active.length > 1 ? `<span class="lv-chip clear-all" onclick="lvClearAllFilters()">Clear All \u2715</span>` : '');
}

function lvPopulateDropdowns(){
    const fill = (id, values) => {
        const sel = document.getElementById(id);
        values.forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
    };
    fill('lvFilterEmployee', [...new Set(lvRecords.map(r => r.employee))].sort());
    fill('lvFilterDept',     [...new Set(lvRecords.map(r => r.department))].sort());
    fill('lvFilterType',     [...new Set(lvRecords.map(r => r.type))].sort());
}

function lvStatusBadge(status){
    if(status === 'approved') return '<span style="color:#059669;font-weight:700;">Approved</span>';
    if(status === 'rejected') return '<span style="color:#dc2626;font-weight:700;">Rejected</span>';
    return '<span style="color:#d97706;font-weight:700;">Pending</span>';
}

function lvOpenDrillModal(title, records){
    document.getElementById('lvDrillModalTitle').innerHTML = '<i class="fas fa-list mr-2"></i> ' + title + ' <small style="font-weight:600;opacity:.8;">(' + records.length + ' record' + (records.length===1?'':'s') + ')</small>';
    const body = document.getElementById('lvDrillModalBody');
    body.innerHTML = records.map(r => `
        <tr>
          <td style="font-weight:700;color:#1e40af;">${r.employee}</td>
          <td>${r.department}</td>
          <td>${r.position}</td>
          <td>${r.type}</td>
          <td>${r.start_date} \u2192 ${r.end_date}</td>
          <td style="text-align:center;">${r.days}</td>
          <td>${lvStatusBadge(r.status)}</td>
          <td>${r.applied_at}</td>
        </tr>`).join('');
    $('#lvDrillModal').modal('show');
}

function lvRenderLeaderboard(){
    const recs = lvFilteredRecords();
    const byEmp = {};
    recs.forEach(r => {
        if(!byEmp[r.emp_id]) byEmp[r.emp_id] = {
            employee:r.employee, department:r.department, position:r.position,
            requests:0, approved_days:0, pending:0, rejected:0
        };
        const e = byEmp[r.emp_id];
        e.requests++;
        if(r.status === 'approved') e.approved_days += r.days;
        else if(r.status === 'pending') e.pending++;
        else if(r.status === 'rejected') e.rejected++;
    });
    const list = Object.values(byEmp).sort((a,b) => b.approved_days - a.approved_days);
    document.getElementById('lvLbCount').textContent = '(' + list.length + ' employee' + (list.length===1?'':'s') + ')';
    const body = document.getElementById('lvLbBody');
    body.innerHTML = list.map(e => `
        <tr class="lv-lb-row" onclick='lvOpenDrillModal(${JSON.stringify(e.employee)}, lvRecords.filter(r => r.employee === ${JSON.stringify(e.employee)}))'>
          <td style="font-weight:700;color:#1e40af;">${e.employee}</td>
          <td>${e.department}</td>
          <td>${e.position}</td>
          <td style="text-align:center;">${e.requests}</td>
          <td style="font-weight:900;color:#059669;">${e.approved_days}</td>
          <td style="text-align:center;color:#d97706;">${e.pending}</td>
          <td style="text-align:center;color:#dc2626;">${e.rejected}</td>
        </tr>`).join('');
}

function lvBarData(groupKeyFn){
    const grouped = lvGroupDays(lvFilteredRecords(), groupKeyFn);
    const labels = Object.keys(grouped).sort((a,b) => grouped[b].days - grouped[a].days);
    return { labels: labels, data: labels.map(l => grouped[l].days) };
}

function lvMakeBarChart(canvasId, groupKeyFn, drillType, colorBase){
    const d = lvBarData(groupKeyFn);
    const ctx = document.getElementById(canvasId).getContext('2d');
    const chart = new Chart(ctx, {
        type: 'bar',
        data: { labels: d.labels, datasets: [{ label: 'Days Taken', data: d.data, backgroundColor: colorBase, borderRadius: 6 }] },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            plugins: { legend: { display: false } },
            scales: { x: { grid: { display: false } }, y: { beginAtZero: true } },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    const label = chart.data.labels[idx];
                    lvApplyFilter(drillType, label);
                    const matching = lvRecords.filter(r => r[drillType] === label);
                    lvOpenDrillModal(drillType.charAt(0).toUpperCase() + drillType.slice(1) + ': ' + label, matching);
                }
            }
        }
    });
    chart.lvGroupKeyFn = groupKeyFn;
    return chart;
}

function lvTrendData(){
    const recs = lvFilteredRecords();
    const map = {};
    recs.forEach(r => {
        const k = r.month_label + '|' + r.year + '|' + String(r.month).padStart(2,'0');
        if(!map[k]) map[k] = { requests:0, days:0 };
        map[k].requests++;
        if(r.status === 'approved') map[k].days += r.days;
    });
    const keys = Object.keys(map).sort((a,b) => a.split('|')[1]+a.split('|')[2] > b.split('|')[1]+b.split('|')[2] ? 1 : -1);
    return {
        labels: keys.map(k => k.split('|')[0]),
        requests: keys.map(k => map[k].requests),
        days: keys.map(k => map[k].days)
    };
}

function lvMakeTrendChart(){
    const t = lvTrendData();
    const ctx = document.getElementById('lvChartTrend').getContext('2d');
    const chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: t.labels,
            datasets: [
                { label: 'Requests', data: t.requests, borderColor: '#4338ca', backgroundColor: 'rgba(67,56,202,.08)', tension: .3, fill: true, pointRadius: 5, pointHoverRadius: 7 },
                { label: 'Approved Days', data: t.days, borderColor: '#059669', backgroundColor: 'rgba(5,150,105,.08)', tension: .3, fill: true, pointRadius: 5, pointHoverRadius: 7 }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            scales: { y: { beginAtZero: true } },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    const label = chart.data.labels[idx];
                    lvApplyFilter('month', label);
                    const matching = lvRecords.filter(r => r.month_label === label);
                    lvOpenDrillModal('Month: ' + label, matching);
                }
            }
        }
    });
    return chart;
}

function lvRefreshCharts(){
    const ty = lvBarData(lvTypeChart.lvGroupKeyFn);
    lvTypeChart.data.labels = ty.labels; lvTypeChart.data.datasets[0].data = ty.data; lvTypeChart.update();

    const dpt = lvBarData(lvDeptChart.lvGroupKeyFn);
    lvDeptChart.data.labels = dpt.labels; lvDeptChart.data.datasets[0].data = dpt.data; lvDeptChart.update();

    const pos = lvBarData(lvPositionChart.lvGroupKeyFn);
    lvPositionChart.data.labels = pos.labels; lvPositionChart.data.datasets[0].data = pos.data; lvPositionChart.update();

    const t = lvTrendData();
    lvTrendChart.data.labels = t.labels;
    lvTrendChart.data.datasets[0].data = t.requests;
    lvTrendChart.data.datasets[1].data = t.days;
    lvTrendChart.update();
}

document.addEventListener('DOMContentLoaded', function(){
    lvPopulateDropdowns();
    lvTypeChart     = lvMakeBarChart('lvChartType', r => r.type, 'type', '#6366f1');
    lvDeptChart     = lvMakeBarChart('lvChartDept', r => r.department, 'department', '#3b82f6');
    lvPositionChart = lvMakeBarChart('lvChartPosition', r => r.position, 'position', '#8b5cf6');
    lvTrendChart    = lvMakeTrendChart();
    lvRenderLeaderboard();
});
</script>
<?php endif; ?>
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