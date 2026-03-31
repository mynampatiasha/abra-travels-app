<?php
// =========================================================================
// LEAVE MANAGEMENT - FIXED v2
// ✅ FIX 1: Duplicate leave check before inserting (same employee + overlapping dates)
// ✅ FIX 2: Status sync runs only once per hour (not on every page load)  
// ✅ FIX 3: Submit button disabled immediately on click (prevents double-submit)
// ✅ FIX 4: Proper null handling for lat/lng (PHP 7+ compatible)
// =========================================================================

ob_start();
session_start();

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('library.php');
require_once('funciones.php');

if(!isset($dbConn) || !$dbConn) { die("Database connection failed."); }

date_default_timezone_set('Asia/Kolkata');

function get_leave_emoji($type) {
    $type = strtolower(trim($type));
    if($type == 'sick') return '🤒 Sick';
    if($type == 'casual') return '🏖️ Casual';
    if($type == 'earned') return '💰 Earned';
    if($type == 'emergency') return '🚨 Emergency';
    if($type == 'unpaid') return '💸 Unpaid';
    return ucfirst($type);
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

$is_management_dept   = (stripos($current_user_department, 'Management') !== false);
$is_hr_dept           = (stripos($current_user_department, 'Human Resources') !== false);
$is_managing_director = (stripos($current_user_position, 'Managing Director') !== false || stripos($current_user_position, 'md') !== false || stripos($current_user_position, 'ceo') !== false);
$is_role_admin        = (stripos($current_user_role, 'Admin') !== false || stripos($current_user_role, 'HR') !== false);
$is_abishek           = (stripos($current_user_name, 'abishek') !== false);
$is_keerti            = (stripos($current_user_name, 'keerti') !== false || stripos($current_user_name, 'keerthi') !== false);
$is_admin             = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_role_admin || $is_abishek || $is_keerti);

$dashboard_url = "https://crm.abra-logistic.com/dashboard/raise-a-ticket.php"; 
if($is_managing_director || $is_abishek) $dashboard_url = "https://crm.abra-logistic.com/dashboard/index.php"; 

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
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS `hr_leaves` (`id` int(11) NOT NULL AUTO_INCREMENT, `employee_id` int(11) DEFAULT NULL, `primary_approver_id` int(11) DEFAULT NULL, `secondary_approver_id` int(11) DEFAULT NULL, `start_date` date DEFAULT NULL, `end_date` date DEFAULT NULL, `leave_type` varchar(50) DEFAULT NULL, `reason` text, `location_latitude` decimal(10,8) DEFAULT NULL, `location_longitude` decimal(11,8) DEFAULT NULL, `location_address` text DEFAULT NULL, `status` varchar(20) DEFAULT 'pending', `is_urgent` tinyint(1) DEFAULT 0, `approved_by` int(11) DEFAULT NULL, `rejected_by` int(11) DEFAULT NULL, `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS `hr_leave_documents` (`id` int(11) NOT NULL AUTO_INCREMENT, `leave_id` int(11) NOT NULL, `employee_id` varchar(50) DEFAULT NULL, `document_name` varchar(255) NOT NULL, `file_path` varchar(500) NOT NULL, `location` varchar(255) DEFAULT NULL, `latitude` decimal(10,8) DEFAULT NULL, `longitude` decimal(11,8) DEFAULT NULL, `address` text DEFAULT NULL, `uploaded_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`id`), KEY `leave_id` (`leave_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

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
    $start_date = mysqli_real_escape_string($dbConn, $_POST['start_date']);
    $end_date   = mysqli_real_escape_string($dbConn, $_POST['end_date']);
    $leave_type = mysqli_real_escape_string($dbConn, $_POST['leave_type']);
    $reason     = mysqli_real_escape_string($dbConn, $_POST['reason']);
    $latitude   = !empty($_POST['latitude'])  ? floatval($_POST['latitude'])  : null;
    $longitude  = !empty($_POST['longitude']) ? floatval($_POST['longitude']) : null;
    $address    = !empty($_POST['address'])   ? mysqli_real_escape_string($dbConn, trim($_POST['address'])) : null;

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
        $dup = mysqli_fetch_assoc($dup_q);
        echo json_encode([
            'success' => false,
            'message' => "⚠️ Duplicate Leave Detected!\n\nYou already have an active leave request (Leave ID: #{$dup['id']}) that overlaps with the dates you selected ({$start_date} to {$end_date}).\n\nPlease check your 'My Leaves' tab. If incorrect, contact HR."
        ]);
        exit;
    }

    $start  = new DateTime($start_date);
    $end    = new DateTime($end_date);
    $days   = $end->diff($start)->days + 1;
    $urgent = (date('Y-m-d') == $start_date) ? 1 : 0;

    $emp_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT name, position, employee_id FROM hr_employees WHERE id=$emp_id LIMIT 1"));
    if(!$emp_row) {
        echo json_encode(['success' => false, 'message' => '❌ Employee record not found.']);
        exit;
    }

    // ✅ FIX 4: Safe null handling for lat/lng (PHP 7 compatible — ?? 'NULL' only works in PHP 8+)
    $lat_val = ($latitude  !== null) ? floatval($latitude)  : 'NULL';
    $lng_val = ($longitude !== null) ? floatval($longitude) : 'NULL';
    $adr_val = ($address   !== null) ? "'$address'" : 'NULL';

    $ins_sql = "INSERT INTO hr_leaves 
        (employee_id, primary_approver_id, secondary_approver_id, start_date, end_date, leave_type, reason, location_latitude, location_longitude, location_address, status, is_urgent) 
        VALUES ($emp_id, $pri_app_id, ".($sec_app_id > 0 ? $sec_app_id : 'NULL').", '$start_date', '$end_date', '$leave_type', '$reason', $lat_val, $lng_val, $adr_val, 'pending', $urgent)";

    if(!mysqli_query($dbConn, $ins_sql)) {
        echo json_encode(['success' => false, 'message' => '❌ Database error: '.mysqli_error($dbConn)]);
        exit;
    }

    $leave_id = mysqli_insert_id($dbConn);

    // Guard: verify leave was actually saved
    if(!$leave_id) {
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
    $loc_i = $address ? "\n📍 LOCATION: $address\n" : '';
    $created_tickets = [];

    // Create L1 ticket
    $tn1 = 'LV-'.date('Ymd').'-'.rand(1000,9999).'-L1';
    $sb1 = mysqli_real_escape_string($dbConn, "[L1 Leave Request] ".ucfirst($leave_type)." - $days days ({$emp_row['name']})");
    $bd1 = mysqli_real_escape_string($dbConn, "🏖️ LEAVE L1 APPROVAL\n👤 {$emp_row['name']}\n📅 $start_date to $end_date\n🗓️ $days day(s)\n📝 $leave_type\n$loc_i\n💬 Reason: $reason\n✅ Set Ticket to APPROVED to grant.");
    if(mysqli_query($dbConn, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level) VALUES ('$tn1','".addslashes($emp_row['name'])."','$sb1','$bd1','Open','$prio',$pri_app_id,NOW(),NOW(),$leave_id,'primary')")) {
        $created_tickets[] = $tn1;
    }

    // Create L2 ticket (only if a secondary approver was selected)
    if($sec_app_id > 0) {
        $tn2 = 'LV-'.date('Ymd').'-'.rand(1000,9999).'-L2';
        $sb2 = mysqli_real_escape_string($dbConn, "[L2 Leave Request] ".ucfirst($leave_type)." - $days days ({$emp_row['name']})");
        $bd2 = mysqli_real_escape_string($dbConn, "🏖️ LEAVE L2 APPROVAL\n👤 {$emp_row['name']}\n📅 $start_date to $end_date\n🗓️ $days day(s)\n📝 $leave_type\n$loc_i\n💬 Reason: $reason\n✅ Set Ticket to APPROVED to grant.");
        if(mysqli_query($dbConn, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, assigned_to, created_at, updated_at, leave_id, approver_level) VALUES ('$tn2','".addslashes($emp_row['name'])."','$sb2','$bd2','Open','$prio',$sec_app_id,NOW(),NOW(),$leave_id,'secondary')")) {
            $created_tickets[] = $tn2;
        }
    }

    $ticket_str = implode(' & ', $created_tickets);
    echo json_encode(['success' => true, 'message' => "✅ Leave submitted successfully!\nTicket(s) created: $ticket_str"]);
    exit;
}

// =========================================================================
// DATA FETCHING (HIERARCHY LOGIC)
// =========================================================================
$primary_approvers = [];
$secondary_approvers = [];

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
    }
}

$cur_yr = date('Y');
$bal = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT 
    SUM(CASE WHEN leave_type='sick' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as sick_taken,
    SUM(CASE WHEN leave_type='casual' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as casual_taken,
    SUM(CASE WHEN leave_type='earned' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as earned_taken,
    SUM(CASE WHEN leave_type='emergency' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as emergency_taken,
    SUM(CASE WHEN leave_type='unpaid' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as unpaid_taken
    FROM hr_leaves WHERE employee_id=$current_user_id AND status='approved' AND YEAR(start_date)=$cur_yr"));

$sick_rem     = 7 - ($bal['sick_taken']??0);
$cas_rem      = 7 - ($bal['casual_taken']??0);
$ear_rem      = 8 - ($bal['earned_taken']??0);
$eml_rem      = 4 - ($bal['emergency_taken']??0);
$unpaid_taken = $bal['unpaid_taken'] ?? 0;
$total_entitlement = 26;

$my_leaves = mysqli_query($dbConn, "SELECT l.*, e1.name as pri_name, e2.name as sec_name, e3.name as app_n, e4.name as rej_n, GROUP_CONCAT(t.ticket_number ORDER BY t.approver_level SEPARATOR ' | ') as t_nums, GROUP_CONCAT(t.status ORDER BY t.approver_level SEPARATOR ' | ') as t_stats, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count FROM hr_leaves l LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id LEFT JOIN hr_employees e3 ON l.approved_by=e3.id LEFT JOIN hr_employees e4 ON l.rejected_by=e4.id LEFT JOIN tickets t ON t.leave_id=l.id WHERE l.employee_id=$current_user_id GROUP BY l.id ORDER BY l.id DESC");

$all_leaves_system = null;
if($is_admin) {
    $all_leaves_system = mysqli_query($dbConn, "SELECT l.*, COALESCE(e.name, CONCAT('[Unknown Emp #', l.employee_id, ']')) as emp_name, COALESCE(e.position, 'Unknown') as emp_pos, COALESCE(e.work_location, '') as work_location, e1.name as pri_n, e2.name as sec_n, GROUP_CONCAT(t.ticket_number ORDER BY t.approver_level SEPARATOR ' | ') as t_nums, GROUP_CONCAT(t.status ORDER BY t.approver_level SEPARATOR ' | ') as t_stats, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count FROM hr_leaves l LEFT JOIN hr_employees e ON l.employee_id=e.id LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id LEFT JOIN tickets t ON t.leave_id=l.id GROUP BY l.id ORDER BY l.id DESC");
}

$approvals_pending = mysqli_query($dbConn, "SELECT l.*, COALESCE(e.name, CONCAT('[Unknown Emp #', l.employee_id, ']')) as emp_name, COALESCE(e.position, 'Unknown') as emp_pos, COALESCE(e.work_location, '') as work_location, (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count, t.ticket_number as my_ticket, t.status as my_ticket_status FROM hr_leaves l LEFT JOIN hr_employees e ON l.employee_id=e.id LEFT JOIN tickets t ON t.leave_id=l.id AND t.assigned_to=$current_user_id WHERE (l.primary_approver_id=$current_user_id OR l.secondary_approver_id=$current_user_id) AND (t.status IS NULL OR LOWER(t.status) NOT IN ('approved','rejected','closed','resolved')) ORDER BY l.is_urgent DESC, l.created_at ASC");
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
            <a href="<?php echo $dashboard_url; ?>" class="btn-header btn-primary-custom"><i class="fas fa-arrow-left"></i> Dashboard</a>
        </div>
    </div>

    <div class="stats-row">
        <div class="stat-card indigo"><div class="stat-icon indigo"><i class="fas fa-calendar-alt"></i></div><div class="stat-content"><h3><?php echo $total_entitlement; ?></h3><p>Total Annual Quota</p></div></div>
        <div class="stat-card blue"><div class="stat-icon blue"><i class="fas fa-notes-medical"></i></div><div class="stat-content"><h3><?php echo $sick_rem; ?></h3><p>Sick Leave (SL)</p></div></div>
        <div class="stat-card green"><div class="stat-icon green"><i class="fas fa-umbrella-beach"></i></div><div class="stat-content"><h3><?php echo $cas_rem; ?></h3><p>Casual Leave (CL)</p></div></div>
        <div class="stat-card orange"><div class="stat-icon orange"><i class="fas fa-star"></i></div><div class="stat-content"><h3><?php echo $ear_rem; ?></h3><p>Earned Leave (EL)</p></div></div>
        <div class="stat-card" style="border-left-color:#ef4444;"><div class="stat-icon" style="background:linear-gradient(135deg,#ef4444,#dc2626);color:white;"><i class="fas fa-exclamation-triangle"></i></div><div class="stat-content"><h3><?php echo $eml_rem; ?></h3><p>Emergency Leave (EML)</p></div></div>
        <div class="stat-card purple"><div class="stat-icon purple"><i class="fas fa-hand-holding-usd"></i></div><div class="stat-content"><h3><?php echo $unpaid_taken; ?></h3><p>Unpaid Taken</p></div></div>
    </div>

    <ul class="nav nav-tabs" id="leaveTabs">
        <li class="nav-item"><a class="nav-link active" data-toggle="tab" href="#myLeaves">My Leaves</a></li>
        <?php if($is_admin): ?><li class="nav-item"><a class="nav-link" data-toggle="tab" href="#allLeaves">All Employee Leaves</a></li><?php endif; ?>
        <?php if(mysqli_num_rows($approvals_pending)>0): ?><li class="nav-item"><a class="nav-link" data-toggle="tab" href="#approvals">Approvals <span class="badge badge-danger ml-1"><?php echo mysqli_num_rows($approvals_pending); ?></span></a></li><?php endif; ?>
    </ul>

    <div class="tab-content">
        <!-- MY LEAVES -->
        <div id="myLeaves" class="tab-pane fade show active">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-filter mr-2"></i> Filter My Leaves</h6>
                <div class="row">
                    <div class="col-md-3 form-group"><label>From Date</label><input type="date" class="form-control-modern" id="myFilterFrom"></div>
                    <div class="col-md-3 form-group"><label>To Date</label><input type="date" class="form-control-modern" id="myFilterTo"></div>
                    <div class="col-md-2 form-group"><label>Type</label><select class="form-control-modern" id="myFilterType"><option value="">All</option><option value="sick">🤒 Sick</option><option value="casual">🏖️ Casual</option><option value="earned">💰 Earned</option><option value="emergency">🚨 Emergency</option><option value="unpaid">💸 Unpaid</option></select></div>
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
                    <?php mysqli_data_seek($my_leaves,0); while($l=mysqli_fetch_assoc($my_leaves)): $s=new DateTime($l['start_date']); $e=new DateTime($l['end_date']); $days=$e->diff($s)->days+1; ?>
                    <tr data-start="<?php echo $l['start_date']; ?>" data-end="<?php echo $l['end_date']; ?>" data-type="<?php echo strtolower($l['leave_type']); ?>" data-status="<?php echo strtolower($l['status']); ?>">
                        <td><strong><?php echo date('d M Y',strtotime($l['created_at'])); ?></strong></td>
                        <td style="font-size:16px;"><?php echo get_leave_emoji($l['leave_type']); ?><br><small style="font-weight:600;color:#64748b;"><?php echo $days; ?> day(s)</small></td>
                        <td style="white-space:nowrap;"><?php echo date('d M',strtotime($l['start_date'])).' - '.date('d M Y',strtotime($l['end_date'])); ?></td>
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
                        <td style="font-size:16px;"><?php echo get_leave_emoji($l['leave_type']); ?></td>
                        <td style="font-size:13px;"><?php echo date('d M',strtotime($l['start_date'])).' - '.date('d M',strtotime($l['end_date'])); ?></td>
                        <td><strong><?php echo (new DateTime($l['end_date']))->diff(new DateTime($l['start_date']))->days+1; ?></strong></td>
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
                    <?php mysqli_data_seek($approvals_pending,0); while($a=mysqli_fetch_assoc($approvals_pending)): $days=(new DateTime($a['end_date']))->diff(new DateTime($a['start_date']))->days+1; $st=strtolower($a['my_ticket_status']??''); $cls='t-yellow'; if(in_array($st,['approved','closed','resolved'])) $cls='t-green'; elseif($st=='rejected') $cls='t-red'; ?>
                    <tr data-start="<?php echo $a['start_date']; ?>" data-end="<?php echo $a['end_date']; ?>" data-name="<?php echo strtolower($a['emp_name']); ?>" data-loc="<?php echo strtolower($a['work_location']??''); ?>">
                        <td><strong><?php echo $a['emp_name']; ?></strong><br><small style="font-weight:600;color:#64748b;"><?php echo $a['emp_pos']; ?></small></td>
                        <td style="font-size:16px;"><?php echo get_leave_emoji($a['leave_type']); ?></td>
                        <td style="font-size:13px;"><?php echo date('d M',strtotime($a['start_date'])).' - '.date('d M',strtotime($a['end_date'])); ?></td>
                        <td><strong><?php echo $days; ?></strong></td>
                        <td style="max-width:250px;font-size:13px;"><?php echo $a['reason']; ?></td>
                        <td><?php if($a['my_ticket']): ?><a href="https://crm.abra-logistic.com/dashboard/my-tickets.php?ticket_number=<?php echo $a['my_ticket']; ?>" target="_blank" class="t-badge <?php echo $cls; ?>"><?php echo $a['my_ticket']; ?></a><?php else: echo '<span class="text-muted small">No Ticket</span>'; endif; ?></td>
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
        <div class="modal-header"><h4 class="modal-title"><i class="fas fa-paper-plane mr-2"></i> Request New Leave</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div>
        <div class="modal-body">
            <form id="leaveForm">
                <input type="hidden" id="leave_emp_id" value="<?php echo $current_user_id; ?>">
                <div style="background:#e0f2fe;border:2px solid #0284c7;border-radius:12px;padding:20px;margin-bottom:20px;color:#0369a1;font-size:14px;">
                    <strong><i class="fas fa-info-circle mr-1"></i> Your Approval Hierarchy:</strong><br>
                    <small>Approvers are automatically assigned based on your position (<?php echo $current_user_position; ?>).</small>
                </div>
                <div class="location-box" id="locBox">
                    <label style="font-weight:800;color:#1e40af;"><i class="fas fa-map-marker-alt"></i> Location Check-in (Required)</label>
                    <input type="hidden" id="lLat"><input type="hidden" id="lLng"><input type="hidden" id="lAddr">
                    <input type="text" id="lDisplay" class="form-control-modern mb-2 text-center" readonly placeholder="Waiting for GPS capture..." style="background:#fff;">
                    <button type="button" class="btn-location" id="btnCapture" onclick="getGPS()"><i class="fas fa-crosshairs"></i> Capture My Location</button>
                </div>
                <div class="row">
                    <div class="col-md-6 form-group"><label style="font-weight:700;">Start Date *</label><input type="date" class="form-control-modern" id="lStart" required min="<?php echo date('Y-m-d'); ?>"></div>
                    <div class="col-md-6 form-group"><label style="font-weight:700;">End Date *</label><input type="date" class="form-control-modern" id="lEnd" required></div>
                </div>
                <div class="form-group"><label style="font-weight:700;">Leave Type *</label>
                    <select class="form-control-modern" id="lType" required><option value="">-- Select Type --</option><option value="sick">🤒 Sick Leave</option><option value="casual">🏖️ Casual Leave</option><option value="earned">💰 Earned Leave</option><option value="emergency">🚨 Emergency Leave</option><option value="unpaid">💸 Unpaid Leave</option></select>
                </div>
                <div class="row">
                    <div class="col-md-6 form-group">
                        <label style="font-weight:700;">L1 Approver (Primary) *</label>
                        <select class="form-control-modern" id="lPri" required>
                            <?php if(empty($primary_approvers)): ?><option value="">-- No Approver Found --</option>
                            <?php else: foreach($primary_approvers as $p): ?><option value="<?php echo $p['id']; ?>" selected><?php echo $p['name']; ?> (<?php echo $p['position']; ?>)</option><?php endforeach; endif; ?>
                        </select>
                    </div>
                    <div class="col-md-6 form-group">
                        <label style="font-weight:700;">L2 Approver (Secondary)</label>
                        <select class="form-control-modern" id="lSec">
                            <?php if(empty($secondary_approvers)): ?><option value="">-- No Secondary Approver --</option>
                            <?php else: foreach($secondary_approvers as $s): ?><option value="<?php echo $s['id']; ?>" selected><?php echo $s['name']; ?> (<?php echo $s['position']; ?>)</option><?php endforeach; ?><option value="">(Optional) Remove Secondary</option><?php endif; ?>
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
            </form>
        </div>
    </div></div>
</div>

<!-- Modal: Docs -->
<div class="modal fade" id="docsModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header"><h4><i class="fas fa-folder-open mr-2"></i> Documents Viewer</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div><div class="modal-body" id="docsContent">Loading documents...</div></div></div></div>

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
    if(!$('#lStart').val()||!$('#lEnd').val()) return alert('❌ Start and End dates are required!');
    if($('#lEnd').val()<$('#lStart').val()) return alert('❌ End date cannot be before start date!');
    if(!$('#lType').val()) return alert('❌ Please select a leave type!');
    if(!$('#lReason').val().trim()) return alert('❌ Reason is required!');

    const btn=$(this);
    btn.prop('disabled',true).text('⏳ SUBMITTING... PLEASE WAIT');

    const fd=new FormData();
    fd.append('ajax_create_leave','1');
    fd.append('employee_id',$('#leave_emp_id').val());
    fd.append('primary_approver_id',$('#lPri').val());
    fd.append('secondary_approver_id',$('#lSec').val());
    fd.append('start_date',$('#lStart').val());
    fd.append('end_date',$('#lEnd').val());
    fd.append('leave_type',$('#lType').val());
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
            if(r.success){
                alert(r.message);
                location.reload();
            } else {
                // Show exact error (including duplicate message) and re-enable so they can correct it
                alert(r.message||'❌ Something went wrong.');
                btn.prop('disabled',false).text('SUBMIT LEAVE APPLICATION');
            }
        },
        error: ()=>{ alert('Network Error — please try again.'); btn.prop('disabled',false).text('SUBMIT LEAVE APPLICATION'); }
    });
});

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
function exportToCSV(tableId,filename){
    let csv=[]; const rows=document.querySelectorAll('#'+tableId+' tr:not([style*="display: none"])');
    for(let i=0;i<rows.length;i++){ let row=[]; const cols=rows[i].querySelectorAll('td,th'); for(let j=0;j<cols.length;j++){ let txt=cols[j].innerText.replace(/"/g,'""').replace(/\n/g,' ').trim(); row.push('"'+txt+'"'); } csv.push(row.join(',')); }
    const blob=new Blob(['\ufeff'+csv.join('\n')],{type:'text/csv;charset=utf-8;'}); const link=document.createElement('a'); link.href=URL.createObjectURL(blob); link.download=filename; link.click();
}
</script>
</body>
</html>
<?php ob_end_flush(); ?>