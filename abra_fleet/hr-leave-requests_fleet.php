<?php
// =========================================================================
// LEAVE MANAGEMENT - FLEET VERSION (hr-leave-requests.php)
// ✅ Email-based auth via ?user_email= (no session required)
// ✅ CRM-style ticket system via Node.js API (localhost:3001)
// ✅ Tickets created on submission (L1 + L2) AND via manual assignment
// ✅ Ticket numbers stored in hr_leaves (ticket_l1, ticket_l2 columns)
// ✅ Approver emails resolved from hr_employees MySQL table
// ✅ Leave saves even if ticket API is temporarily down
// ✅ Uses $con = conexion() from database-settings.php
// =========================================================================
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed.");
mysqli_set_charset($con, 'utf8mb4');

date_default_timezone_set('Asia/Kolkata');

// =========================================================================
// AUTO-ADD MISSING COLUMNS IF NOT EXISTS
// =========================================================================
@mysqli_query($con, "ALTER TABLE hr_leaves ADD COLUMN IF NOT EXISTS `ticket_l1` varchar(60) DEFAULT NULL");
@mysqli_query($con, "ALTER TABLE hr_leaves ADD COLUMN IF NOT EXISTS `ticket_l2` varchar(60) DEFAULT NULL");
@mysqli_query($con, "ALTER TABLE hr_leaves ADD COLUMN IF NOT EXISTS `ticket_error` text DEFAULT NULL");
@mysqli_query($con, "ALTER TABLE hr_leaves ADD COLUMN IF NOT EXISTS `tertiary_approver_id` int(11) DEFAULT NULL");
@mysqli_query($con, "ALTER TABLE hr_leaves ADD COLUMN IF NOT EXISTS `leave_days` int(11) DEFAULT NULL");
// Ensure hr_leave_hierarchy has approver_3_id column
@mysqli_query($con, "ALTER TABLE hr_leave_hierarchy ADD COLUMN IF NOT EXISTS `approver_3_id` int(11) DEFAULT NULL");

// =========================================================================
// EMAIL-BASED USER IDENTIFICATION
// =========================================================================
$currentUserEmail = '';
if (!empty($_GET['user_email'])) {
    $currentUserEmail = trim($_GET['user_email']);
} elseif (!empty($_POST['user_email'])) {
    $currentUserEmail = trim($_POST['user_email']);
}

$user_emp_data = null;
if (!empty($currentUserEmail)) {
    $esc_email = mysqli_real_escape_string($con, $currentUserEmail);
    $q = mysqli_query($con, "SELECT * FROM hr_employees WHERE email='$esc_email' OR personal_email='$esc_email' LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) {
        $user_emp_data = mysqli_fetch_assoc($q);
    }
}

if (!$user_emp_data) {
    die("<div style='padding:50px;text-align:center;font-family:Poppins,sans-serif;'><h4>Access Denied. No user email provided or employee not found.</h4></div>");
}

$current_user_id          = $user_emp_data['id'];
$current_user_name        = $user_emp_data['name'];
$current_user_email_addr  = $user_emp_data['email'] ?? $currentUserEmail;
$current_user_employee_id = $user_emp_data['employee_id'] ?? '';
$current_user_pos_id      = !empty($user_emp_data['position_id']) ? intval($user_emp_data['position_id']) : 0;
$current_user_position    = !empty($user_emp_data['position']) ? $user_emp_data['position'] : 'Employee';
$current_user_department  = !empty($user_emp_data['department']) ? $user_emp_data['department'] : 'General';
$current_user_hire_date   = $user_emp_data['hire_date'] ?? null;

// =========================================================================
// ROLE DETECTION
// =========================================================================
$is_hr_dept           = (stripos($current_user_department, 'HR') !== false || stripos($current_user_department, 'Human Resource') !== false);
$is_managing_director = (stripos($current_user_position, 'Managing Director') !== false || stripos($current_user_position, 'md') !== false || stripos($current_user_position, 'ceo') !== false);
$is_abishek           = (stripos($current_user_name, 'abishek') !== false);
$is_keerti            = (stripos($current_user_name, 'keerti') !== false || stripos($current_user_name, 'keerthi') !== false);
$is_admin             = ($is_hr_dept || $is_managing_director || $is_abishek || $is_keerti);

$self_url = 'https://www.abra-travels.com/hrm/hr-leave-requests.php';

// =========================================================================
// LEAVE ELIGIBILITY (6-MONTH PROBATION)
// =========================================================================
$is_eligible_for_paid_leaves = true;
$months_since_joining = 0;
$eligibility_date = null;
$missing_hire_date = false;

if ($current_user_hire_date) {
    $hire_date_obj = new DateTime($current_user_hire_date);
    $today = new DateTime();
    $interval = $hire_date_obj->diff($today);
    $months_since_joining = ($interval->y * 12) + $interval->m;
    $is_eligible_for_paid_leaves = ($months_since_joining >= 6);
    $eligibility_date_obj = clone $hire_date_obj;
    $eligibility_date_obj->modify('+6 months');
    $eligibility_date = $eligibility_date_obj->format('d M Y');
} else {
    $missing_hire_date = true;
    $is_eligible_for_paid_leaves = true;
}

// =========================================================================
// HELPERS
// =========================================================================
function get_leave_emoji($type) {
    $type = strtolower(trim($type));
    if ($type == 'sick')      return '🤒 Sick';
    if ($type == 'casual')    return '🏖️ Casual';
    if ($type == 'earned')    return '💰 Earned';
    if ($type == 'emergency') return '🚨 Emergency';
    if ($type == 'unpaid')    return '💸 Unpaid';
    return ucfirst($type);
}

/**
 * Create a ticket via the Node.js internal API.
 * Returns ['success' => bool, 'ticket_number' => string|null, 'error' => string|null]
 */
function create_fleet_ticket($subject, $message, $assigned_name, $assigned_email, $creator_name, $creator_email, $priority = 'medium', $timeline = 1440) {
    $payload = json_encode([
        'subject'        => $subject,
        'message'        => $message,
        'priority'       => $priority,
        'timeline'       => $timeline,
        'assigned_name'  => $assigned_name,
        'assigned_email' => $assigned_email,
        'creator_name'   => $creator_name,
        'creator_email'  => $creator_email,
    ]);

    $ch = curl_init('http://localhost:3001/api/tickets/internal/create');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'x-internal-key: abra_internal_2026'
        ],
        CURLOPT_TIMEOUT        => 15,
        CURLOPT_SSL_VERIFYPEER => false,
    ]);

    $result     = curl_exec($ch);
    $http_code  = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_error = curl_error($ch);
    curl_close($ch);

    if ($curl_error) {
        return ['success' => false, 'ticket_number' => null, 'error' => 'CURL: ' . $curl_error];
    }

    $decoded = json_decode($result, true);
    if (!$decoded || !$decoded['success']) {
        return ['success' => false, 'ticket_number' => null, 'error' => $decoded['error'] ?? 'Unknown API error'];
    }

    return ['success' => true, 'ticket_number' => $decoded['ticket_number'], 'error' => null];
}

// =========================================================================
// AJAX: GET DOCUMENTS
// =========================================================================
if (isset($_GET['ajax_get_documents']) && isset($_GET['leave_id'])) {
    $leave_id = intval($_GET['leave_id']);
    $docs_query = mysqli_query($con, "SELECT * FROM hr_leave_documents WHERE leave_id=$leave_id ORDER BY uploaded_at DESC");
    $num_docs = mysqli_num_rows($docs_query);
    echo '<div style="margin-bottom:25px;"><h5 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fa fa-paperclip"></i> Attached Documents</h5>';
    if ($num_docs == 0) {
        echo '<div style="padding:40px;text-align:center;background:#f8fafc;border-radius:12px;border:2px dashed #cbd5e1;color:#64748b;"><i class="fa fa-folder-open" style="font-size:30px;display:block;margin-bottom:10px;"></i>No documents uploaded yet</div>';
    } else {
        echo '<div id="docCarousel" class="carousel slide" data-ride="carousel" data-interval="false" style="background:#f1f5f9;border-radius:12px;overflow:hidden;border:1px solid #e2e8f0;">';
        if ($num_docs > 1) {
            echo '<ol class="carousel-indicators" style="bottom:-15px;">';
            for ($i = 0; $i < $num_docs; $i++) echo '<li data-target="#docCarousel" data-slide-to="' . $i . '" class="' . ($i == 0 ? 'active' : '') . '" style="background-color:#1e3a8a;"></li>';
            echo '</ol>';
        }
        echo '<div class="carousel-inner">';
        $count = 0;
        while ($doc = mysqli_fetch_assoc($docs_query)) {
            $active = ($count == 0) ? 'active' : '';
            $ext = strtolower(pathinfo($doc['file_path'], PATHINFO_EXTENSION));
            $is_img = in_array($ext, ['jpg', 'jpeg', 'png', 'gif', 'webp']);
            $is_pdf = ($ext === 'pdf');
            echo '<div class="carousel-item ' . $active . '"><div class="d-flex justify-content-center align-items-center" style="height:500px;background:#fff;">';
            if ($is_img) echo '<img src="' . htmlspecialchars($doc['file_path']) . '" class="d-block" style="max-height:100%;max-width:100%;object-fit:contain;">';
            elseif ($is_pdf) echo '<iframe src="' . htmlspecialchars($doc['file_path']) . '" style="width:100%;height:100%;border:none;"></iframe>';
            else echo '<div class="text-center p-5"><i class="fas fa-file-alt" style="font-size:60px;color:#64748b;"></i><br><br><b>' . $ext . '</b> file preview not available.</div>';
            echo '</div><div style="background:rgba(255,255,255,0.95);padding:15px;border-top:1px solid #e2e8f0;display:flex;justify-content:space-between;align-items:center;"><div><h6 style="margin:0;font-weight:700;color:#1e3a8a;">' . htmlspecialchars($doc['document_name']) . '</h6>';
            if (!empty($doc['address'])) echo '<small style="color:#64748b;"><i class="fas fa-map-marker-alt"></i> ' . htmlspecialchars($doc['address']) . '</small>';
            echo '</div><a href="' . htmlspecialchars($doc['file_path']) . '" target="_blank" class="btn btn-sm btn-primary" style="font-weight:700;background:linear-gradient(135deg,#1e3a8a,#1e40af);"><i class="fas fa-download"></i> Download</a></div></div>';
            $count++;
        }
        echo '</div>';
        if ($num_docs > 1) {
            echo '<a class="carousel-control-prev" href="#docCarousel" role="button" data-slide="prev" style="width:5%;"><span class="carousel-control-prev-icon" aria-hidden="true" style="background-color:rgba(0,0,0,0.3);border-radius:50%;padding:20px;"></span></a>';
            echo '<a class="carousel-control-next" href="#docCarousel" role="button" data-slide="next" style="width:5%;"><span class="carousel-control-next-icon" aria-hidden="true" style="background-color:rgba(0,0,0,0.3);border-radius:50%;padding:20px;"></span></a>';
        }
        echo '</div>';
    }
    echo '</div>';

    // Upload form — only for leave owner
    $leave_owner_q = mysqli_query($con, "SELECT employee_id FROM hr_leaves WHERE id=$leave_id LIMIT 1");
    if ($leave_owner_q && mysqli_num_rows($leave_owner_q) > 0) {
        $leave_owner = mysqli_fetch_assoc($leave_owner_q);
        if ($leave_owner['employee_id'] == $current_user_id) {
            echo '<div style="background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:2px solid #3b82f6;border-radius:12px;padding:25px;margin-top:20px;"><h5 style="color:#1e40af;font-weight:700;margin-bottom:15px;"><i class="fa fa-cloud-upload-alt"></i> Upload New Document</h5>';
            echo '<form method="POST" enctype="multipart/form-data">';
            echo '<input type="hidden" name="upload_leave_document" value="1">';
            echo '<input type="hidden" name="leave_id" value="' . $leave_id . '">';
            echo '<input type="hidden" name="user_email" value="' . htmlspecialchars($currentUserEmail) . '">';
            echo '<input type="hidden" name="latitude" id="docLatitude">';
            echo '<input type="hidden" name="longitude" id="docLongitude">';
            echo '<input type="hidden" name="address" id="docAddress">';
            echo '<div class="form-group"><label style="font-weight:600;font-size:13px;">Select File *</label><input type="file" name="document_file" class="form-control" required></div>';
            echo '<div class="form-group"><label style="font-weight:600;font-size:13px;">Description</label><input type="text" name="document_location" class="form-control" placeholder="e.g. Medical Certificate"></div>';
            echo '<div style="background:#fef3c7;padding:15px;border-radius:10px;border:1px solid #f59e0b;margin-bottom:15px;">';
            echo '<label style="font-weight:700;color:#92400e;display:block;margin-bottom:10px;"><i class="fa fa-map-marker-alt"></i> Location (MANDATORY)</label>';
            echo '<input type="text" id="docLocationDisplay" class="form-control mb-2" readonly placeholder="Waiting for GPS..." style="background:#fff;">';
            echo '<button type="button" class="btn btn-warning btn-sm" onclick="getDocLocation()">GET GPS LOCATION</button></div>';
            echo '<button type="submit" class="btn btn-success btn-block" style="font-weight:700;">UPLOAD DOCUMENT</button>';
            echo '</form></div>';
        }
    }
    exit;
}

// =========================================================================
// AJAX: MANUAL ASSIGN & RAISE TICKET (Admin)
// =========================================================================
if (isset($_POST['ajax_manual_assign_ticket'])) {
    header('Content-Type: application/json');
    if (!$is_admin) {
        echo json_encode(['success' => false, 'message' => 'Not authorized']);
        exit;
    }

    $leave_id        = intval($_POST['leave_id'] ?? 0);
    $pri_approver_id = intval($_POST['primary_approver_id'] ?? 0);
    $sec_approver_id = intval($_POST['secondary_approver_id'] ?? 0);

    if (!$leave_id || !$pri_approver_id) {
        echo json_encode(['success' => false, 'message' => 'Missing leave ID or primary approver']);
        exit;
    }

    // Fetch leave details
    $leave_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT l.*, e.name as emp_name, e.position as emp_pos FROM hr_leaves l LEFT JOIN hr_employees e ON l.employee_id=e.id WHERE l.id=$leave_id LIMIT 1"));
    if (!$leave_row) {
        echo json_encode(['success' => false, 'message' => 'Leave not found']);
        exit;
    }

    // Fetch primary approver email
    $pri_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, name, email FROM hr_employees WHERE id=$pri_approver_id LIMIT 1"));
    if (!$pri_row) {
        echo json_encode(['success' => false, 'message' => 'Primary approver not found']);
        exit;
    }

    $start_date = $leave_row['start_date'];
    $end_date   = $leave_row['end_date'];
    $days       = (new DateTime($end_date))->diff(new DateTime($start_date))->days + 1;
    $leave_type = $leave_row['leave_type'];
    $reason     = $leave_row['reason'];
    $emp_name   = $leave_row['emp_name'];
    $loc_info   = $leave_row['location_address'] ? "\n📍 Location: " . $leave_row['location_address'] : '';

    $errors   = [];
    $tickets  = [];

    // L1 Ticket
    $l1_subject = "[L1 Leave Request] " . ucfirst($leave_type) . " - $days day(s) ($emp_name)";
    $l1_message = "🏖️ LEAVE L1 APPROVAL REQUEST\n👤 $emp_name\n📅 $start_date to $end_date\n🗓️ $days day(s)\n📝 " . ucfirst($leave_type) . "$loc_info\n💬 Reason: $reason\n\n✅ Approve or ❌ Reject this ticket to action the leave.";

    $l1_result = create_fleet_ticket(
        $l1_subject, $l1_message,
        $pri_row['name'], $pri_row['email'],
        $current_user_name, $current_user_email_addr
    );

    if ($l1_result['success']) {
        $t1 = mysqli_real_escape_string($con, $l1_result['ticket_number']);
        mysqli_query($con, "UPDATE hr_leaves SET ticket_l1='$t1', primary_approver_id=$pri_approver_id WHERE id=$leave_id");
        $tickets[] = $l1_result['ticket_number'] . ' (L1)';
    } else {
        $errors[] = 'L1 ticket failed: ' . $l1_result['error'];
    }

    // L2 Ticket (optional)
    if ($sec_approver_id > 0) {
        $sec_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, name, email FROM hr_employees WHERE id=$sec_approver_id LIMIT 1"));
        if ($sec_row) {
            $l2_subject = "[L2 Leave Request] " . ucfirst($leave_type) . " - $days day(s) ($emp_name)";
            $l2_message = "🏖️ LEAVE L2 APPROVAL REQUEST\n👤 $emp_name\n📅 $start_date to $end_date\n🗓️ $days day(s)\n📝 " . ucfirst($leave_type) . "$loc_info\n💬 Reason: $reason\n\n✅ Approve or ❌ Reject this ticket to action the leave.";

            $l2_result = create_fleet_ticket(
                $l2_subject, $l2_message,
                $sec_row['name'], $sec_row['email'],
                $current_user_name, $current_user_email_addr
            );

            if ($l2_result['success']) {
                $t2 = mysqli_real_escape_string($con, $l2_result['ticket_number']);
                mysqli_query($con, "UPDATE hr_leaves SET ticket_l2='$t2', secondary_approver_id=$sec_approver_id WHERE id=$leave_id");
                $tickets[] = $l2_result['ticket_number'] . ' (L2)';
            } else {
                $errors[] = 'L2 ticket failed: ' . $l2_result['error'];
            }
        }
    }

    if (!empty($tickets)) {
        $msg = '✅ Ticket(s) created: ' . implode(', ', $tickets);
        if (!empty($errors)) $msg .= ' | ⚠️ ' . implode(', ', $errors);
        echo json_encode(['success' => true, 'message' => $msg, 'tickets' => $tickets]);
    } else {
        echo json_encode(['success' => false, 'message' => '❌ All ticket creation failed: ' . implode(', ', $errors)]);
    }
    exit;
}

// =========================================================================
// AJAX: APPROVE / REJECT LEAVE (Admin direct)
// =========================================================================
if (isset($_POST['ajax_approve_leave']) || isset($_POST['ajax_reject_leave'])) {
    header('Content-Type: application/json');
    if (!$is_admin) {
        echo json_encode(['success' => false, 'message' => 'Not authorized']);
        exit;
    }
    $leave_id = intval($_POST['leave_id'] ?? 0);
    if (!$leave_id) {
        echo json_encode(['success' => false, 'message' => 'Missing leave ID']);
        exit;
    }
    if (isset($_POST['ajax_approve_leave'])) {
        $ok = mysqli_query($con, "UPDATE hr_leaves SET status='approved', approved_by=$current_user_id WHERE id=$leave_id");
        echo json_encode(['success' => (bool)$ok, 'message' => $ok ? '✅ Leave approved!' : mysqli_error($con)]);
    } else {
        $ok = mysqli_query($con, "UPDATE hr_leaves SET status='rejected', rejected_by=$current_user_id WHERE id=$leave_id");
        echo json_encode(['success' => (bool)$ok, 'message' => $ok ? '❌ Leave rejected.' : mysqli_error($con)]);
    }
    exit;
}

// =========================================================================
// POST: UPLOAD DOCUMENT
// =========================================================================
if (isset($_POST['upload_leave_document']) && isset($_FILES['document_file'])) {
    $leave_id  = intval($_POST['leave_id']);
    $location  = mysqli_real_escape_string($con, trim($_POST['document_location'] ?? ''));
    $latitude  = !empty($_POST['latitude'])  ? floatval($_POST['latitude'])  : null;
    $longitude = !empty($_POST['longitude']) ? floatval($_POST['longitude']) : null;
    $address   = !empty($_POST['address'])   ? mysqli_real_escape_string($con, trim($_POST['address'])) : null;

    if ($latitude === null) {
        header("Location: " . $self_url . "?user_email=" . urlencode($currentUserEmail) . "&error=no_gps");
        exit;
    }

    $file = $_FILES['document_file'];
    if ($file['error'] === UPLOAD_ERR_OK) {
        $upload_dir = 'uploads/leave_documents/' . $current_user_employee_id . '/';
        if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);
        $ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        $dest = $upload_dir . 'leave_' . $leave_id . '_' . time() . '.' . $ext;
        if (move_uploaded_file($file['tmp_name'], $dest)) {
            $dn      = mysqli_real_escape_string($con, $file['name']);
            $lat_val = ($latitude  !== null) ? floatval($latitude)  : 'NULL';
            $lng_val = ($longitude !== null) ? floatval($longitude) : 'NULL';
            $adr_val = ($address   !== null) ? "'$address'"         : 'NULL';
            mysqli_query($con, "INSERT INTO hr_leave_documents (leave_id, employee_id, document_name, file_path, location, latitude, longitude, address) VALUES ($leave_id, '$current_user_employee_id', '$dn', '$dest', '$location', $lat_val, $lng_val, $adr_val)");
        }
    }
    header("Location: " . $self_url . "?user_email=" . urlencode($currentUserEmail) . "&success=doc_uploaded");
    exit;
}

// =========================================================================
// POST: SUBMIT NEW LEAVE (AJAX) — WITH TICKET CREATION
// =========================================================================
if (isset($_POST['ajax_create_leave'])) {
    header('Content-Type: application/json');

    $emp_id     = intval($_POST['employee_id']);
    $pri_app_id = intval($_POST['primary_approver_id']);
    $sec_app_id = !empty($_POST['secondary_approver_id']) ? intval($_POST['secondary_approver_id']) : 0;
    $ter_app_id = !empty($_POST['tertiary_approver_id']) ? intval($_POST['tertiary_approver_id']) : 0;
    $start_date = mysqli_real_escape_string($con, $_POST['start_date']);
    $end_date   = mysqli_real_escape_string($con, $_POST['end_date']);
    $leave_days = !empty($_POST['leave_days']) ? intval($_POST['leave_days']) : 0;
    $leave_type = mysqli_real_escape_string($con, $_POST['leave_type']);
    $reason     = mysqli_real_escape_string($con, $_POST['reason']);
    $latitude   = !empty($_POST['latitude'])  ? floatval($_POST['latitude'])  : null;
    $longitude  = !empty($_POST['longitude']) ? floatval($_POST['longitude']) : null;
    $address    = !empty($_POST['address'])   ? mysqli_real_escape_string($con, trim($_POST['address'])) : null;

    // Validate leave days
    if ($leave_days < 1) {
        echo json_encode(['success' => false, 'message' => '❌ Please enter a valid number of leave days (minimum 1).']);
        exit;
    }

    // Eligibility check
    $emp_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$emp_id LIMIT 1"));
    if (!$emp_row) {
        echo json_encode(['success' => false, 'message' => '❌ Employee not found.']);
        exit;
    }
    if (!empty($emp_row['hire_date'])) {
        $hire_dt = new DateTime($emp_row['hire_date']);
        $leave_start_dt = new DateTime($start_date);
        $diff = $leave_start_dt->diff($hire_dt);
        $months_at_leave = ($diff->y * 12) + $diff->m;
        if ($months_at_leave < 6 && $leave_type !== 'unpaid') {
            echo json_encode(['success' => false, 'message' => "❌ Paid Leave Not Available!\n\nYou will have completed only $months_at_leave month(s) by the leave start date ($start_date).\n\nPaid leaves are available after completing 6 months.\n\nYou can only apply for 'Unpaid Leave' at this time."]);
            exit;
        }
    }

    // Duplicate check
    $dup_q = mysqli_query($con, "SELECT id FROM hr_leaves WHERE employee_id=$emp_id AND status!='rejected' AND start_date<='$end_date' AND end_date>='$start_date' LIMIT 1");
    if ($dup_q && mysqli_num_rows($dup_q) > 0) {
        $dup = mysqli_fetch_assoc($dup_q);
        echo json_encode(['success' => false, 'message' => "⚠️ Duplicate Leave!\n\nYou already have an active leave (ID #{$dup['id']}) overlapping these dates.\n\nCheck 'My Leaves' tab."]);
        exit;
    }

    $days   = $leave_days; // use manual count
    $urgent = (date('Y-m-d') == $start_date) ? 1 : 0;

    $lat_val = ($latitude  !== null) ? floatval($latitude)  : 'NULL';
    $lng_val = ($longitude !== null) ? floatval($longitude) : 'NULL';
    $adr_val = ($address   !== null) ? "'$address'"         : 'NULL';

    $ins_sql = "INSERT INTO hr_leaves 
        (employee_id, primary_approver_id, secondary_approver_id, tertiary_approver_id, start_date, end_date, leave_days, leave_type, reason, location_latitude, location_longitude, location_address, status, is_urgent) 
        VALUES ($emp_id, $pri_app_id, " . ($sec_app_id > 0 ? $sec_app_id : 'NULL') . ", " . ($ter_app_id > 0 ? $ter_app_id : 'NULL') . ", '$start_date', '$end_date', $days, '$leave_type', '$reason', $lat_val, $lng_val, $adr_val, 'pending', $urgent)";

    if (!mysqli_query($con, $ins_sql)) {
        echo json_encode(['success' => false, 'message' => '❌ DB Error: ' . mysqli_error($con)]);
        exit;
    }
    $leave_id = mysqli_insert_id($con);
    if (!$leave_id) {
        echo json_encode(['success' => false, 'message' => '❌ Leave not saved.']);
        exit;
    }

    // Upload documents if any
    if (isset($_FILES['leave_documents'])) {
        $up_dir = 'uploads/leave_documents/' . $emp_row['employee_id'] . '/';
        if (!is_dir($up_dir)) mkdir($up_dir, 0755, true);
        for ($i = 0; $i < count($_FILES['leave_documents']['name']); $i++) {
            if ($_FILES['leave_documents']['error'][$i] === 0) {
                $ext  = strtolower(pathinfo($_FILES['leave_documents']['name'][$i], PATHINFO_EXTENSION));
                $dest = $up_dir . 'lv_' . $leave_id . '_' . time() . '_' . $i . '.' . $ext;
                if (move_uploaded_file($_FILES['leave_documents']['tmp_name'][$i], $dest)) {
                    $orig_name = mysqli_real_escape_string($con, $_FILES['leave_documents']['name'][$i]);
                    mysqli_query($con, "INSERT INTO hr_leave_documents (leave_id, employee_id, document_name, file_path, latitude, longitude, address) VALUES ($leave_id, '{$emp_row['employee_id']}', '$orig_name', '$dest', $lat_val, $lng_val, $adr_val)");
                }
            }
        }
    }

    // =========================================================================
    // CREATE TICKETS VIA NODE.JS API
    // =========================================================================
    $loc_info     = $address ? "\n📍 Location: $address" : '';
    $ticket_errors  = [];
    $created_tickets = [];

    // Fetch primary approver details for ticket
    $pri_approver = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, name, email FROM hr_employees WHERE id=$pri_app_id LIMIT 1"));

    if ($pri_approver && !empty($pri_approver['email'])) {
        $l1_subject = "[L1 Leave Request] " . ucfirst($leave_type) . " - $days day(s) ({$emp_row['name']})";
        $l1_message = "🏖️ LEAVE L1 APPROVAL REQUEST\n"
            . "👤 Employee: {$emp_row['name']}\n"
            . "🪪 Position: {$emp_row['position']}\n"
            . "📅 Dates: $start_date to $end_date\n"
            . "🗓️ Duration: $days day(s)\n"
            . "📝 Type: " . ucfirst($leave_type) . "\n"
            . $loc_info . "\n"
            . "💬 Reason: $reason\n\n"
            . "✅ Set ticket to APPROVED to grant this leave.\n"
            . "❌ Set ticket to REJECTED to decline.";

        $l1_result = create_fleet_ticket(
            $l1_subject, $l1_message,
            $pri_approver['name'], $pri_approver['email'],
            $emp_row['name'], $currentUserEmail
        );

        if ($l1_result['success']) {
            $t1 = mysqli_real_escape_string($con, $l1_result['ticket_number']);
            mysqli_query($con, "UPDATE hr_leaves SET ticket_l1='$t1' WHERE id=$leave_id");
            $created_tickets[] = $l1_result['ticket_number'] . ' (L1 → ' . $pri_approver['name'] . ')';
        } else {
            $ticket_errors[] = 'L1: ' . $l1_result['error'];
        }
    } else {
        $ticket_errors[] = 'L1: Primary approver email not found in system';
    }

    // L2 Ticket
    if ($sec_app_id > 0) {
        $sec_approver = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, name, email FROM hr_employees WHERE id=$sec_app_id LIMIT 1"));
        if ($sec_approver && !empty($sec_approver['email'])) {
            $l2_subject = "[L2 Leave Request] " . ucfirst($leave_type) . " - $days day(s) ({$emp_row['name']})";
            $l2_message = "🏖️ LEAVE L2 APPROVAL REQUEST\n"
                . "👤 Employee: {$emp_row['name']}\n"
                . "🪪 Position: {$emp_row['position']}\n"
                . "📅 Dates: $start_date to $end_date\n"
                . "🗓️ Duration: $days day(s)\n"
                . "📝 Type: " . ucfirst($leave_type) . "\n"
                . $loc_info . "\n"
                . "💬 Reason: $reason\n\n"
                . "✅ Set ticket to APPROVED to grant this leave.\n"
                . "❌ Set ticket to REJECTED to decline.";

            $l2_result = create_fleet_ticket(
                $l2_subject, $l2_message,
                $sec_approver['name'], $sec_approver['email'],
                $emp_row['name'], $currentUserEmail
            );

            if ($l2_result['success']) {
                $t2 = mysqli_real_escape_string($con, $l2_result['ticket_number']);
                mysqli_query($con, "UPDATE hr_leaves SET ticket_l2='$t2' WHERE id=$leave_id");
                $created_tickets[] = $l2_result['ticket_number'] . ' (L2 → ' . $sec_approver['name'] . ')';
            } else {
                $ticket_errors[] = 'L2: ' . $l2_result['error'];
            }
        } else {
            $ticket_errors[] = 'L2: Secondary approver email not found in system';
        }
    }

    // ✅ L3 Ticket (tertiary approver)
    if ($ter_app_id > 0) {
        $ter_approver = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, name, email FROM hr_employees WHERE id=$ter_app_id LIMIT 1"));
        if ($ter_approver && !empty($ter_approver['email'])) {
            $l3_subject = "[L3 Leave Request] " . ucfirst($leave_type) . " - $days day(s) ({$emp_row['name']})";
            $l3_message = "🏖️ LEAVE L3 APPROVAL REQUEST\n"
                . "👤 Employee: {$emp_row['name']}\n"
                . "🪪 Position: {$emp_row['position']}\n"
                . "📅 Dates: $start_date to $end_date\n"
                . "🗓️ Duration: $days day(s)\n"
                . "📝 Type: " . ucfirst($leave_type) . "\n"
                . $loc_info . "\n"
                . "💬 Reason: $reason\n\n"
                . "✅ Set ticket to APPROVED to grant this leave.\n"
                . "❌ Set ticket to REJECTED to decline.";

            $l3_result = create_fleet_ticket(
                $l3_subject, $l3_message,
                $ter_approver['name'], $ter_approver['email'],
                $emp_row['name'], $currentUserEmail
            );

            if ($l3_result['success']) {
                $t3 = mysqli_real_escape_string($con, $l3_result['ticket_number']);
                // Store L3 ticket in ticket_error field as a note (no dedicated column needed)
                $existing_err = mysqli_fetch_assoc(mysqli_query($con, "SELECT ticket_error FROM hr_leaves WHERE id=$leave_id LIMIT 1"));
                $l3_note = "L3:" . $t3;
                $combined = !empty($existing_err['ticket_error']) ? $existing_err['ticket_error'] . ' | ' . $l3_note : $l3_note;
                $combined_esc = mysqli_real_escape_string($con, $combined);
                mysqli_query($con, "UPDATE hr_leaves SET tertiary_approver_id=$ter_app_id, ticket_error='$combined_esc' WHERE id=$leave_id");
                $created_tickets[] = $l3_result['ticket_number'] . ' (L3 → ' . $ter_approver['name'] . ')';
            } else {
                $ticket_errors[] = 'L3: ' . $l3_result['error'];
            }
        } else {
            $ticket_errors[] = 'L3: Tertiary approver email not found in system';
        }
    }

    // Store any ticket errors on the leave row for retry visibility
    if (!empty($ticket_errors)) {
        $err_esc = mysqli_real_escape_string($con, implode(' | ', $ticket_errors));
        mysqli_query($con, "UPDATE hr_leaves SET ticket_error='$err_esc' WHERE id=$leave_id");
    }

    // Build success message — leave always saves even if tickets fail
    $success_msg = "✅ Leave submitted successfully! (Leave ID: #$leave_id)\n";
    if (!empty($created_tickets)) {
        $success_msg .= "🎫 Ticket(s) created: " . implode(', ', $created_tickets);
    }
    if (!empty($ticket_errors)) {
        $success_msg .= "\n⚠️ Ticket warning: " . implode(', ', $ticket_errors) . "\n(Leave is saved — HR can raise tickets manually from the admin panel.)";
    }

    echo json_encode(['success' => true, 'message' => $success_msg, 'leave_id' => $leave_id]);
    exit;
}

// =========================================================================
// APPROVERS FROM HIERARCHY
// =========================================================================
$primary_approvers   = [];
$secondary_approvers = [];
$tertiary_approvers  = [];

if ($current_user_pos_id == 0 && !empty($current_user_position)) {
    $fix_q = mysqli_query($con, "SELECT id FROM hr_positions WHERE title='" . mysqli_real_escape_string($con, $current_user_position) . "' LIMIT 1");
    if ($fix_q && mysqli_num_rows($fix_q) > 0) $current_user_pos_id = mysqli_fetch_assoc($fix_q)['id'];
}

if ($current_user_pos_id > 0) {
    $hier = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_leave_hierarchy WHERE position_id=$current_user_pos_id LIMIT 1"));
    if ($hier) {
        if (!empty($hier['approver_1_id'])) {
            $t1 = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id={$hier['approver_1_id']}"));
            $t1_title = $t1 ? $t1['title'] : '';
            $sql1 = "SELECT id, name, position, email FROM hr_employees WHERE status='active' AND (position_id={$hier['approver_1_id']}";
            if ($t1_title) $sql1 .= " OR position LIKE '" . mysqli_real_escape_string($con, $t1_title) . "'";
            $sql1 .= ")";
            $r1 = mysqli_query($con, $sql1);
            while ($row = mysqli_fetch_assoc($r1)) $primary_approvers[] = $row;
        }
        if (!empty($hier['approver_2_id'])) {
            $t2 = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id={$hier['approver_2_id']}"));
            $t2_title = $t2 ? $t2['title'] : '';
            $sql2 = "SELECT id, name, position, email FROM hr_employees WHERE status='active' AND (position_id={$hier['approver_2_id']}";
            if ($t2_title) $sql2 .= " OR position LIKE '" . mysqli_real_escape_string($con, $t2_title) . "'";
            $sql2 .= ")";
            $r2 = mysqli_query($con, $sql2);
            while ($row = mysqli_fetch_assoc($r2)) $secondary_approvers[] = $row;
        }
        // ✅ L3 Tertiary approver
        if (!empty($hier['approver_3_id'])) {
            $t3 = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id={$hier['approver_3_id']}"));
            $t3_title = $t3 ? $t3['title'] : '';
            $sql3 = "SELECT id, name, position, email FROM hr_employees WHERE status='active' AND (position_id={$hier['approver_3_id']}";
            if ($t3_title) $sql3 .= " OR position LIKE '" . mysqli_real_escape_string($con, $t3_title) . "'";
            $sql3 .= ")";
            $r3 = mysqli_query($con, $sql3);
            while ($row = mysqli_fetch_assoc($r3)) $tertiary_approvers[] = $row;
        }
    }
}

// =========================================================================
// LEAVE BALANCE
// =========================================================================
$cur_yr = date('Y');
$bal = mysqli_fetch_assoc(mysqli_query($con, "SELECT 
    SUM(CASE WHEN leave_type='sick'      THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as sick_taken,
    SUM(CASE WHEN leave_type='casual'    THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as casual_taken,
    SUM(CASE WHEN leave_type='earned'    THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as earned_taken,
    SUM(CASE WHEN leave_type='emergency' THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as emergency_taken,
    SUM(CASE WHEN leave_type='unpaid'    THEN DATEDIFF(end_date,start_date)+1 ELSE 0 END) as unpaid_taken
    FROM hr_leaves WHERE employee_id=$current_user_id AND status='approved' AND YEAR(start_date)=$cur_yr"));

$sick_rem     = 7  - ($bal['sick_taken']      ?? 0);
$cas_rem      = 7  - ($bal['casual_taken']    ?? 0);
$ear_rem      = 8  - ($bal['earned_taken']    ?? 0);
$eml_rem      = 4  - ($bal['emergency_taken'] ?? 0);
$unpaid_taken = $bal['unpaid_taken'] ?? 0;

// =========================================================================
// ADMIN: ALL EMPLOYEE LEAVE BALANCES
// =========================================================================
$employee_balances = [];
if ($is_admin) {
    $bal_yr = date('Y');
    $bal_result = mysqli_query($con, "
        SELECT 
            e.id, e.name, e.employee_id, e.department, e.work_location, e.hire_date,
            COALESCE(SUM(CASE WHEN l.leave_type='sick'      AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0) as sick_used,
            COALESCE(SUM(CASE WHEN l.leave_type='casual'    AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0) as casual_used,
            COALESCE(SUM(CASE WHEN l.leave_type='earned'    AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0) as earned_used,
            COALESCE(SUM(CASE WHEN l.leave_type='emergency' AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0) as emergency_used,
            COALESCE(SUM(CASE WHEN l.leave_type='unpaid'    AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0) as unpaid_used,
            (7 - COALESCE(SUM(CASE WHEN l.leave_type='sick'      AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0)) as sick_remaining,
            (7 - COALESCE(SUM(CASE WHEN l.leave_type='casual'    AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0)) as casual_remaining,
            (8 - COALESCE(SUM(CASE WHEN l.leave_type='earned'    AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0)) as earned_remaining,
            (4 - COALESCE(SUM(CASE WHEN l.leave_type='emergency' AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0)) as emergency_remaining,
            (26 - COALESCE(SUM(CASE WHEN l.leave_type IN ('sick','casual','earned','emergency') AND l.status='approved' THEN COALESCE(l.leave_days, DATEDIFF(l.end_date,l.start_date)+1) ELSE 0 END), 0)) as total_remaining
        FROM hr_employees e
        LEFT JOIN hr_leaves l ON l.employee_id = e.id AND YEAR(l.start_date) = $bal_yr
        WHERE e.status = 'active'
        GROUP BY e.id
        ORDER BY e.name ASC
    ");
    if ($bal_result) while ($row = mysqli_fetch_assoc($bal_result)) $employee_balances[] = $row;
}

// =========================================================================
// DROPDOWN DATA
// =========================================================================
$dropdown_employees = [];
$emp_q = mysqli_query($con, "SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name ASC");
while ($row = mysqli_fetch_assoc($emp_q)) $dropdown_employees[] = $row;

// All active employees for manual assignment (admin)
$all_active_employees = [];
$aae_q = mysqli_query($con, "SELECT id, name, position, email FROM hr_employees WHERE status='active' ORDER BY name ASC");
while ($row = mysqli_fetch_assoc($aae_q)) $all_active_employees[] = $row;

// =========================================================================
// MY LEAVES
// =========================================================================
$my_leaves = mysqli_query($con, "SELECT l.*, 
    e1.name as pri_name, e2.name as sec_name, 
    e3.name as app_n, e4.name as rej_n,
    (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count 
    FROM hr_leaves l 
    LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id 
    LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id 
    LEFT JOIN hr_employees e3 ON l.approved_by=e3.id 
    LEFT JOIN hr_employees e4 ON l.rejected_by=e4.id 
    WHERE l.employee_id=$current_user_id 
    ORDER BY l.id DESC");

// =========================================================================
// ALL LEAVES (Admin)
// =========================================================================
$all_leaves_system = null;
if ($is_admin) {
    $all_leaves_system = mysqli_query($con, "SELECT l.*, 
        COALESCE(e.name, CONCAT('[Unknown #', l.employee_id, ']')) as emp_name,
        COALESCE(e.position, 'Unknown') as emp_pos,
        COALESCE(e.work_location, '') as work_location,
        e1.name as pri_n, e2.name as sec_n,
        (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count 
        FROM hr_leaves l 
        LEFT JOIN hr_employees e ON l.employee_id=e.id 
        LEFT JOIN hr_employees e1 ON l.primary_approver_id=e1.id 
        LEFT JOIN hr_employees e2 ON l.secondary_approver_id=e2.id 
        ORDER BY l.id DESC");
}

// =========================================================================
// PENDING APPROVALS (for this user as approver)
// =========================================================================
$approvals_pending = mysqli_query($con, "SELECT l.*, 
    COALESCE(e.name, CONCAT('[Unknown #', l.employee_id, ']')) as emp_name,
    COALESCE(e.position, 'Unknown') as emp_pos,
    COALESCE(e.work_location, '') as work_location,
    (SELECT COUNT(*) FROM hr_leave_documents WHERE leave_id=l.id) as doc_count
    FROM hr_leaves l 
    LEFT JOIN hr_employees e ON l.employee_id=e.id 
    WHERE (l.primary_approver_id=$current_user_id OR l.secondary_approver_id=$current_user_id) 
    AND l.status='pending'
    ORDER BY l.is_urgent DESC, l.created_at ASC");

$pending_count = mysqli_num_rows($approvals_pending);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <title>Leave Management | Abra Travels</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:20px 0; }
        .container-fluid { max-width:1600px; margin:0 auto; padding:0 20px; }
        .page-header { background:linear-gradient(135deg,#1e3a8a,#1e40af); padding:25px 32px; border-radius:12px; box-shadow:0 6px 20px rgba(30,58,138,0.3); margin-bottom:25px; display:flex; justify-content:space-between; align-items:center; color:white; flex-wrap:wrap; gap:15px; }
        .page-header h1 { font-weight:700; margin:0; font-size:1.8rem; }
        .header-info { opacity:0.9; font-size:14px; margin-top:5px; }
        .btn-header { padding:12px 24px; border-radius:10px; font-weight:700; cursor:pointer; border:none; display:inline-flex; align-items:center; gap:8px; transition:0.3s; color:white; text-decoration:none; font-size:14px; }
        .btn-success-custom { background:linear-gradient(135deg,#10b981,#059669); }
        .btn-primary-custom { background:linear-gradient(135deg,#1e3a8a,#1e40af); }
        .btn-header:hover { transform:translateY(-2px); box-shadow:0 8px 25px rgba(0,0,0,0.15); color:white; text-decoration:none; }
        .stats-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:15px; margin-bottom:25px; }
        .stat-card { background:white; border-radius:12px; padding:18px; display:flex; align-items:center; gap:15px; border-left:5px solid; box-shadow:0 3px 12px rgba(0,0,0,0.08); }
        .stat-icon { width:50px; height:50px; border-radius:10px; display:flex; align-items:center; justify-content:center; font-size:20px; color:white; }
        .stat-content h3 { margin:0; font-size:26px; font-weight:800; color:#0f172a; }
        .stat-content p { margin:2px 0 0 0; font-size:11px; font-weight:700; color:#64748b; text-transform:uppercase; }
        .filter-bar { background:white; padding:25px; border-radius:12px; box-shadow:0 3px 12px rgba(0,0,0,0.08); margin-bottom:20px; border:1px solid #e2e8f0; }
        .nav-tabs { border:none; margin-bottom:0; }
        .nav-link { border:none !important; font-weight:700; color:#64748b; padding:15px 25px; border-radius:12px 12px 0 0 !important; }
        .nav-link.active { background:white !important; color:#1e3a8a !important; box-shadow:0 -4px 15px rgba(0,0,0,0.05); }
        .tab-content { background:white; padding:30px; border-radius:0 12px 12px 12px; box-shadow:0 10px 30px rgba(0,0,0,0.05); border:1px solid #e2e8f0; border-top:none; }
        table.table thead th { background:linear-gradient(135deg,#1e3a8a,#1e40af) !important; color:white !important; font-weight:800; padding:16px !important; border:none !important; font-size:13px; text-transform:uppercase; }
        table.table tbody td { padding:14px !important; vertical-align:middle !important; border-bottom:1px solid #f1f5f9 !important; font-size:14px; font-weight:600; color:#0f172a; }
        .badge-status { padding:6px 14px; border-radius:20px; font-weight:800; font-size:12px; text-transform:uppercase; display:inline-block; }
        .badge-pending  { background:#fef3c7; color:#92400e; }
        .badge-approved { background:#d1fae5; color:#065f46; }
        .badge-rejected { background:#fee2e2; color:#991b1b; }

        /* Ticket Badges — same style as CRM */
        .t-badge { display:inline-block; padding:5px 12px; border-radius:8px; font-size:12px; font-weight:800; color:white; margin:2px; letter-spacing:0.5px; cursor:default; white-space:nowrap; }
        .t-green  { background:linear-gradient(135deg,#10b981,#059669); }
        .t-red    { background:linear-gradient(135deg,#ef4444,#dc2626); }
        .t-yellow { background:linear-gradient(135deg,#f59e0b,#d97706); }
        .t-warn   { background:linear-gradient(135deg,#94a3b8,#64748b); font-size:11px; }
        .t-retry  { background:linear-gradient(135deg,#7c3aed,#6d28d9); cursor:pointer; }
        .t-retry:hover { opacity:0.85; }

        .btn-doc-wrapper { position:relative; display:inline-block; }
        .action-btn { width:40px; height:40px; border-radius:10px; border:2px solid #e2e8f0; background:#fff; color:#1e3a8a; display:inline-flex; align-items:center; justify-content:center; cursor:pointer; transition:0.3s; }
        .action-btn:hover { background:#1e3a8a; color:#fff; transform:scale(1.1); }
        .count-badge { position:absolute; top:-8px; right:-8px; background-color:#ef4444; color:white; border-radius:50%; font-size:10px; font-weight:800; width:20px; height:20px; display:flex; align-items:center; justify-content:center; border:2px solid #fff; z-index:10; }
        .form-control-modern { border:2px solid #e2e8f0; border-radius:10px; padding:12px 15px; font-size:14px; height:auto; transition:0.3s; width:100%; font-weight:600; }
        .form-control-modern:focus { border-color:#1e40af; box-shadow:0 0 0 4px rgba(30,64,175,0.1); outline:none; }
        .location-box { background:#f0f9ff; border:2px dashed #3b82f6; border-radius:15px; padding:20px; text-align:center; margin-bottom:20px; }
        .btn-location { background:linear-gradient(135deg,#f59e0b,#d97706); border:none; color:white; padding:10px 25px; border-radius:10px; font-weight:700; cursor:pointer; }
        .btn-submit-modern { background:linear-gradient(135deg,#10b981,#059669); border:none; color:white; width:100%; padding:15px; border-radius:12px; font-weight:800; font-size:16px; margin-top:15px; cursor:pointer; }
        .btn-submit-modern:disabled { opacity:0.6; cursor:not-allowed; }
        .btn-approve { background:linear-gradient(135deg,#10b981,#059669); border:none; color:white; padding:7px 16px; border-radius:8px; font-weight:700; font-size:12px; cursor:pointer; margin:2px; display:inline-flex; align-items:center; gap:5px; }
        .btn-reject  { background:linear-gradient(135deg,#ef4444,#dc2626); border:none; color:white; padding:7px 16px; border-radius:8px; font-weight:700; font-size:12px; cursor:pointer; margin:2px; display:inline-flex; align-items:center; gap:5px; }
        .btn-ticket  { background:linear-gradient(135deg,#f59e0b,#d97706); border:none; color:white; padding:7px 16px; border-radius:8px; font-weight:700; font-size:12px; cursor:pointer; margin:2px; display:inline-flex; align-items:center; gap:5px; }
        .urgent-tag  { background:#fef3c7; color:#92400e; padding:3px 8px; border-radius:6px; font-size:11px; font-weight:700; }
        .alert-banner { border-radius:12px; padding:20px 25px; margin-bottom:20px; display:flex; align-items:flex-start; gap:15px; }
        .alert-warning-custom { background:linear-gradient(135deg,#fef3c7,#fde68a); border:2px solid #f59e0b; }

        /* Manual Assign Panel inside modal */
        .assign-panel { background:#fffbeb; border:2px solid #fcd34d; border-radius:12px; padding:20px; margin-top:18px; }
        .assign-panel h6 { font-weight:800; color:#92400e; margin-bottom:14px; font-size:14px; }
        .assign-select-row { display:flex; gap:10px; align-items:flex-end; flex-wrap:wrap; }
        .assign-select-row select { flex:1; min-width:200px; border:2px solid #e2e8f0; border-radius:10px; padding:10px 12px; font-size:13px; font-family:'Poppins',sans-serif; font-weight:600; }
        .btn-raise-ticket { background:linear-gradient(135deg,#f59e0b,#d97706); border:none; color:white; padding:11px 22px; border-radius:10px; font-weight:700; font-size:13px; cursor:pointer; white-space:nowrap; display:inline-flex; align-items:center; gap:7px; }
        .btn-raise-ticket:disabled { opacity:0.6; cursor:not-allowed; }
    </style>
</head>
<body>
<div class="container-fluid">

    <!-- HEADER -->
    <div class="page-header">
        <div>
            <h1><i class="fas fa-calendar-check mr-2"></i> Leave Management</h1>
            <div class="header-info">Employee: <strong><?php echo htmlspecialchars($current_user_name); ?></strong> (<?php echo htmlspecialchars($current_user_position); ?>)</div>
        </div>
        <div class="d-flex flex-wrap" style="gap:12px;">
            <button class="btn-header btn-success-custom" data-toggle="modal" data-target="#applyLeaveModal">
                <i class="fas fa-plus-circle"></i> Request Leave
            </button>
        </div>
    </div>

    <!-- ALERTS -->
    <?php if ($missing_hire_date): ?>
    <div class="alert-banner alert-warning-custom">
        <i class="fas fa-exclamation-circle" style="color:#f59e0b;font-size:24px;margin-top:3px;flex-shrink:0;"></i>
        <div>
            <strong style="color:#92400e;">Missing Hire Date</strong><br>
            <span style="color:#78350f;font-size:14px;">Your profile does not have a hire date. Please contact HR to update it.</span>
        </div>
    </div>
    <?php elseif (!$is_eligible_for_paid_leaves): ?>
    <div class="alert-banner alert-warning-custom">
        <i class="fas fa-hourglass-half" style="color:#f59e0b;font-size:24px;margin-top:3px;flex-shrink:0;"></i>
        <div>
            <strong style="color:#92400e;">Probation Period — Paid Leaves Locked</strong><br>
            <span style="color:#78350f;font-size:14px;">
                Joined: <strong><?php echo date('d M Y', strtotime($current_user_hire_date)); ?></strong> &nbsp;|&nbsp;
                Completed: <strong><?php echo $months_since_joining; ?> of 6 months</strong> &nbsp;|&nbsp;
                Paid Leaves From: <strong style="color:#059669;"><?php echo $eligibility_date; ?></strong><br>
                Only <strong>Unpaid Leave</strong> is available until <?php echo $eligibility_date; ?>.
            </span>
        </div>
    </div>
    <?php endif; ?>

    <!-- STATS -->
    <div class="stats-row">
        <div class="stat-card" style="border-left-color:#4f46e5;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#4f46e5,#4338ca);"><i class="fas fa-calendar-alt"></i></div>
            <div class="stat-content"><h3>26</h3><p>Total Annual Quota</p></div>
        </div>
        <div class="stat-card" style="border-left-color:#1e40af;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#1e3a8a,#1e40af);"><i class="fas fa-notes-medical"></i></div>
            <div class="stat-content"><h3><?php echo $sick_rem; ?></h3><p>Sick Leave (SL)</p></div>
        </div>
        <div class="stat-card" style="border-left-color:#10b981;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#10b981,#059669);"><i class="fas fa-umbrella-beach"></i></div>
            <div class="stat-content"><h3><?php echo $cas_rem; ?></h3><p>Casual Leave (CL)</p></div>
        </div>
        <div class="stat-card" style="border-left-color:#f59e0b;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#f59e0b,#d97706);"><i class="fas fa-star"></i></div>
            <div class="stat-content"><h3><?php echo $ear_rem; ?></h3><p>Earned Leave (EL)</p></div>
        </div>
        <div class="stat-card" style="border-left-color:#ef4444;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#ef4444,#dc2626);"><i class="fas fa-exclamation-triangle"></i></div>
            <div class="stat-content"><h3><?php echo $eml_rem; ?></h3><p>Emergency (EML)</p></div>
        </div>
        <div class="stat-card" style="border-left-color:#9333ea;">
            <div class="stat-icon" style="background:linear-gradient(135deg,#9333ea,#7e22ce);"><i class="fas fa-hand-holding-usd"></i></div>
            <div class="stat-content"><h3><?php echo $unpaid_taken; ?></h3><p>Unpaid Taken</p></div>
        </div>
    </div>

    <!-- TABS -->
    <ul class="nav nav-tabs" id="leaveTabs">
        <li class="nav-item"><a class="nav-link active" data-toggle="tab" href="#myLeaves">My Leaves</a></li>
        <?php if ($is_admin): ?>
        <li class="nav-item"><a class="nav-link" data-toggle="tab" href="#allLeaves">All Employee Leaves</a></li>
        <li class="nav-item"><a class="nav-link" data-toggle="tab" href="#leaveBalances">Employee Leave Balances</a></li>
        <?php endif; ?>
        <?php if ($pending_count > 0): ?>
        <li class="nav-item">
            <a class="nav-link" data-toggle="tab" href="#approvals">
                Pending Approvals <span class="badge badge-danger ml-1"><?php echo $pending_count; ?></span>
            </a>
        </li>
        <?php endif; ?>
    </ul>

    <div class="tab-content">

        <!-- MY LEAVES TAB -->
        <div id="myLeaves" class="tab-pane fade show active">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-filter mr-2"></i> Filter My Leaves</h6>
                <div class="row">
                    <div class="col-md-3 form-group"><label>From Date</label><input type="date" class="form-control-modern" id="myFilterFrom"></div>
                    <div class="col-md-3 form-group"><label>To Date</label><input type="date" class="form-control-modern" id="myFilterTo"></div>
                    <div class="col-md-2 form-group"><label>Type</label>
                        <select class="form-control-modern" id="myFilterType">
                            <option value="">All</option>
                            <option value="sick">🤒 Sick</option><option value="casual">🏖️ Casual</option>
                            <option value="earned">💰 Earned</option><option value="emergency">🚨 Emergency</option>
                            <option value="unpaid">💸 Unpaid</option>
                        </select>
                    </div>
                    <div class="col-md-2 form-group"><label>Status</label>
                        <select class="form-control-modern" id="myFilterStatus">
                            <option value="">All</option><option value="pending">Pending</option>
                            <option value="approved">Approved</option><option value="rejected">Rejected</option>
                        </select>
                    </div>
                    <div class="col-md-2" style="padding-top:31px;display:flex;gap:8px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyMyFilter()">Apply</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:50px;" onclick="exportToCSV('myLeavesTable','My_Leaves.csv')" title="Export"><i class="fas fa-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="myLeavesTable">
                    <thead><tr><th>Applied</th><th>Type</th><th>Dates</th><th>Days</th><th>Approvers</th><th>Tickets</th><th>Status</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($my_leaves, 0); while ($l = mysqli_fetch_assoc($my_leaves)):
                        $s = new DateTime($l['start_date']); $e = new DateTime($l['end_date']);
                        $days = $e->diff($s)->days + 1;
                        $has_ticket_error = !empty($l['ticket_error']) && empty($l['ticket_l1']) && empty($l['ticket_l2']);
                    ?>
                    <tr data-start="<?php echo $l['start_date']; ?>" data-type="<?php echo strtolower($l['leave_type']); ?>" data-status="<?php echo strtolower($l['status']); ?>">
                        <td><strong><?php echo date('d M Y', strtotime($l['created_at'])); ?></strong></td>
                        <td style="font-size:15px;"><?php echo get_leave_emoji($l['leave_type']); ?>
                            <?php if ($l['is_urgent']): ?><br><span class="urgent-tag">URGENT</span><?php endif; ?>
                        </td>
                        <td style="white-space:nowrap;"><?php echo date('d M', strtotime($l['start_date'])) . ' – ' . date('d M Y', strtotime($l['end_date'])); ?></td>
                        <td><strong><?php echo $days; ?></strong></td>
                        <td style="font-size:12px;">
                            L1: <?php echo htmlspecialchars($l['pri_name'] ?? '—'); ?><br>
                            L2: <?php echo htmlspecialchars($l['sec_name'] ?? '—'); ?>
                        </td>
                        <td style="white-space:nowrap;">
                            <?php if (!empty($l['ticket_l1'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($l['ticket_l1']); ?> L1</span>
                            <?php endif; ?>
                            <?php if (!empty($l['ticket_l2'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($l['ticket_l2']); ?> L2</span>
                            <?php endif; ?>
                            <?php if (empty($l['ticket_l1']) && empty($l['ticket_l2'])): ?>
                                <?php if ($has_ticket_error): ?>
                                    <span class="t-badge t-warn" title="<?php echo htmlspecialchars($l['ticket_error']); ?>">⚠️ Ticket failed</span>
                                <?php else: ?>
                                    <span style="color:#cbd5e1;font-size:12px;">—</span>
                                <?php endif; ?>
                            <?php endif; ?>
                        </td>
                        <td>
                            <span class="badge-status badge-<?php echo $l['status']; ?>"><?php echo $l['status']; ?></span>
                            <?php if ($l['app_n']): ?><br><small class="text-success" style="font-weight:700;">✓ <?php echo htmlspecialchars($l['app_n']); ?></small><?php endif; ?>
                            <?php if ($l['rej_n']): ?><br><small class="text-danger"  style="font-weight:700;">✗ <?php echo htmlspecialchars($l['rej_n']); ?></small><?php endif; ?>
                        </td>
                        <td>
                            <div class="btn-doc-wrapper">
                                <button class="action-btn" onclick="viewDocs(<?php echo $l['id']; ?>)"><i class="fas fa-folder-open"></i></button>
                                <?php if ($l['doc_count'] > 0): ?><span class="count-badge"><?php echo $l['doc_count']; ?></span><?php endif; ?>
                            </div>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- ALL LEAVES TAB (Admin) -->
        <?php if ($is_admin): ?>
        <div id="allLeaves" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-search mr-2"></i> Search All Employee Leaves</h6>
                <div class="row">
                    <div class="col-md-2 form-group"><label>From</label><input type="date" class="form-control-modern" id="adminFilterFrom"></div>
                    <div class="col-md-2 form-group"><label>To</label><input type="date" class="form-control-modern" id="adminFilterTo"></div>
                    <div class="col-md-3 form-group"><label>Employee</label>
                        <select class="form-control-modern" id="adminFilterEmp">
                            <option value="">All Employees</option>
                            <?php foreach ($dropdown_employees as $e): ?>
                            <option value="<?php echo strtolower($e['name']); ?>"><?php echo htmlspecialchars($e['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="col-md-2 form-group"><label>Status</label>
                        <select class="form-control-modern" id="adminFilterStatus">
                            <option value="">All</option><option value="pending">Pending</option>
                            <option value="approved">Approved</option><option value="rejected">Rejected</option>
                        </select>
                    </div>
                    <div class="col-md-3" style="padding-top:31px;display:flex;gap:8px;">
                        <button class="btn btn-primary btn-block" style="font-weight:700;height:48px;" onclick="applyAdminFilter()">Filter</button>
                        <button class="btn btn-success" style="font-weight:700;height:48px;width:50px;" onclick="exportToCSV('allLeavesTable','Company_Leaves.csv')" title="Export"><i class="fas fa-download"></i></button>
                    </div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="allLeavesTable">
                    <thead><tr><th>Employee</th><th>Type</th><th>Duration</th><th>Days</th><th>Tickets</th><th>Status</th><th>Action</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($all_leaves_system, 0); while ($l = mysqli_fetch_assoc($all_leaves_system)): 
                        $has_any_ticket = !empty($l['ticket_l1']) || !empty($l['ticket_l2']);
                        $has_ticket_err = !empty($l['ticket_error']) && !$has_any_ticket;
                    ?>
                    <tr data-start="<?php echo $l['start_date']; ?>" data-applied="<?php echo date('Y-m-d', strtotime($l['created_at'])); ?>" data-name="<?php echo strtolower($l['emp_name']); ?>" data-status="<?php echo strtolower($l['status']); ?>">
                        <td><strong><?php echo htmlspecialchars($l['emp_name']); ?></strong><br><small style="color:#64748b;"><?php echo htmlspecialchars($l['emp_pos']); ?></small></td>
                        <td style="font-size:15px;"><?php echo get_leave_emoji($l['leave_type']); ?></td>
                        <td style="font-size:13px;"><?php echo date('d M', strtotime($l['start_date'])) . ' – ' . date('d M Y', strtotime($l['end_date'])); ?></td>
                        <td><strong><?php echo (new DateTime($l['end_date']))->diff(new DateTime($l['start_date']))->days + 1; ?></strong></td>
                        <td style="white-space:nowrap;">
                            <?php if (!empty($l['ticket_l1'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($l['ticket_l1']); ?> L1</span><br>
                            <?php endif; ?>
                            <?php if (!empty($l['ticket_l2'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($l['ticket_l2']); ?> L2</span>
                            <?php endif; ?>
                            <?php if ($has_ticket_err): ?>
                                <span class="t-badge t-warn" title="<?php echo htmlspecialchars($l['ticket_error']); ?>">⚠️ Failed</span>
                            <?php endif; ?>
                            <?php if (!$has_any_ticket && !$has_ticket_err): ?>
                                <span style="color:#cbd5e1;font-size:12px;">No ticket</span>
                            <?php endif; ?>
                        </td>
                        <td><span class="badge-status badge-<?php echo $l['status']; ?>"><?php echo $l['status']; ?></span></td>
                        <td style="white-space:nowrap;">
                            <?php if ($l['status'] === 'pending'): ?>
                            <button class="btn-approve" onclick="doApprove(<?php echo $l['id']; ?>, this)"><i class="fas fa-check"></i> Approve</button>
                            <button class="btn-reject"  onclick="doReject(<?php echo $l['id']; ?>, this)"><i class="fas fa-times"></i> Reject</button>
                            <?php endif; ?>
                            <!-- Manual Assign & Raise Ticket button always available -->
                            <button class="btn-ticket" onclick="openAssignModal(<?php echo $l['id']; ?>, '<?php echo htmlspecialchars(addslashes($l['emp_name'])); ?>', <?php echo (int)$l['primary_approver_id']; ?>, <?php echo (int)($l['secondary_approver_id'] ?? 0); ?>)">
                                <i class="fas fa-ticket-alt"></i> <?php echo $has_any_ticket ? 'Re-raise' : 'Raise Ticket'; ?>
                            </button>
                        </td>
                        <td>
                            <div class="btn-doc-wrapper">
                                <button class="action-btn" onclick="viewDocs(<?php echo $l['id']; ?>)"><i class="fas fa-folder-open"></i></button>
                                <?php if ($l['doc_count'] > 0): ?><span class="count-badge"><?php echo $l['doc_count']; ?></span><?php endif; ?>
                            </div>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- ✅ EMPLOYEE LEAVE BALANCES TAB (ADMIN ONLY) -->
        <?php if ($is_admin): ?>
        <div id="leaveBalances" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;margin-bottom:15px;"><i class="fas fa-chart-bar mr-2"></i> Employee Leave Balances — <?php echo date('Y'); ?></h6>
                <div class="row">
                    <div class="col-md-3 form-group"><label>Employee</label><input type="text" class="form-control-modern" id="balFilterEmp" placeholder="Search employee..." oninput="applyBalFilter()"></div>
                    <div class="col-md-3 form-group"><label>Department</label><input type="text" class="form-control-modern" id="balFilterDept" placeholder="Filter by department..." oninput="applyBalFilter()"></div>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table" id="balancesTable" style="font-size:13px;">
                    <thead style="background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;">
                        <tr>
                            <th>Employee</th>
                            <th>Department</th>
                            <th style="text-align:center;">Sick (7)</th>
                            <th style="text-align:center;">Casual (7)</th>
                            <th style="text-align:center;">Earned (8)</th>
                            <th style="text-align:center;">Emergency (4)</th>
                            <th style="text-align:center;">Unpaid</th>
                            <th style="text-align:center;">Total Remaining</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php foreach ($employee_balances as $eb): ?>
                    <tr data-name="<?php echo strtolower($eb['name']); ?>" data-dept="<?php echo strtolower($eb['department'] ?? ''); ?>">
                        <td>
                            <strong><?php echo htmlspecialchars($eb['name']); ?></strong><br>
                            <small style="color:#64748b;"><?php echo htmlspecialchars($eb['employee_id']); ?></small>
                        </td>
                        <td><?php echo htmlspecialchars($eb['department'] ?? 'N/A'); ?></td>
                        <td style="text-align:center;">
                            <span style="font-size:16px;font-weight:800;color:<?php echo $eb['sick_remaining'] < 2 ? '#dc2626' : '#059669'; ?>">
                                <?php echo $eb['sick_remaining']; ?>
                            </span><br>
                            <small style="color:#64748b;"><?php echo $eb['sick_used']; ?> used</small>
                        </td>
                        <td style="text-align:center;">
                            <span style="font-size:16px;font-weight:800;color:<?php echo $eb['casual_remaining'] < 2 ? '#dc2626' : '#059669'; ?>">
                                <?php echo $eb['casual_remaining']; ?>
                            </span><br>
                            <small style="color:#64748b;"><?php echo $eb['casual_used']; ?> used</small>
                        </td>
                        <td style="text-align:center;">
                            <span style="font-size:16px;font-weight:800;color:<?php echo $eb['earned_remaining'] < 2 ? '#dc2626' : '#059669'; ?>">
                                <?php echo $eb['earned_remaining']; ?>
                            </span><br>
                            <small style="color:#64748b;"><?php echo $eb['earned_used']; ?> used</small>
                        </td>
                        <td style="text-align:center;">
                            <span style="font-size:16px;font-weight:800;color:<?php echo $eb['emergency_remaining'] < 1 ? '#dc2626' : '#059669'; ?>">
                                <?php echo $eb['emergency_remaining']; ?>
                            </span><br>
                            <small style="color:#64748b;"><?php echo $eb['emergency_used']; ?> used</small>
                        </td>
                        <td style="text-align:center;">
                            <span style="font-size:16px;font-weight:800;color:#64748b;"><?php echo $eb['unpaid_used']; ?></span>
                        </td>
                        <td style="text-align:center;">
                            <span style="font-size:18px;font-weight:800;color:<?php echo $eb['total_remaining'] < 5 ? '#dc2626' : '#1e3a8a'; ?>">
                                <?php echo $eb['total_remaining']; ?>
                            </span>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    <?php if (empty($employee_balances)): ?>
                    <tr><td colspan="8" style="text-align:center;padding:40px;color:#94a3b8;">No employee data found.</td></tr>
                    <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- APPROVALS TAB -->
        <?php if ($pending_count > 0): ?>
        <div id="approvals" class="tab-pane fade">
            <div class="filter-bar">
                <h6 style="color:#1e3a8a;font-weight:700;"><i class="fas fa-bell mr-2"></i> Pending Approvals — <?php echo $pending_count; ?> request(s) waiting</h6>
            </div>
            <div class="table-responsive">
                <table class="table" id="approvalsTable">
                    <thead><tr><th>Employee</th><th>Type</th><th>Dates</th><th>Days</th><th>Reason</th><th>Tickets</th><th>Urgent</th><th>Action</th><th>Docs</th></tr></thead>
                    <tbody>
                    <?php mysqli_data_seek($approvals_pending, 0); while ($a = mysqli_fetch_assoc($approvals_pending)):
                        $days = (new DateTime($a['end_date']))->diff(new DateTime($a['start_date']))->days + 1;
                    ?>
                    <tr>
                        <td><strong><?php echo htmlspecialchars($a['emp_name']); ?></strong><br><small style="color:#64748b;"><?php echo htmlspecialchars($a['emp_pos']); ?></small></td>
                        <td style="font-size:15px;"><?php echo get_leave_emoji($a['leave_type']); ?></td>
                        <td style="font-size:13px;"><?php echo date('d M', strtotime($a['start_date'])) . ' – ' . date('d M Y', strtotime($a['end_date'])); ?></td>
                        <td><strong><?php echo $days; ?></strong></td>
                        <td style="max-width:220px;font-size:13px;"><?php echo htmlspecialchars($a['reason']); ?></td>
                        <td style="white-space:nowrap;">
                            <?php if (!empty($a['ticket_l1'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($a['ticket_l1']); ?> L1</span><br>
                            <?php endif; ?>
                            <?php if (!empty($a['ticket_l2'])): ?>
                                <span class="t-badge t-yellow"><?php echo htmlspecialchars($a['ticket_l2']); ?> L2</span>
                            <?php endif; ?>
                            <?php if (empty($a['ticket_l1']) && empty($a['ticket_l2'])): ?>
                                <span style="color:#94a3b8;font-size:12px;">No ticket</span>
                            <?php endif; ?>
                        </td>
                        <td><?php if ($a['is_urgent']): ?><span class="urgent-tag">🚨 YES</span><?php else: ?>—<?php endif; ?></td>
                        <td>
                            <button class="btn-approve" onclick="doApprove(<?php echo $a['id']; ?>, this)"><i class="fas fa-check"></i> Approve</button>
                            <button class="btn-reject"  onclick="doReject(<?php echo $a['id']; ?>, this)"><i class="fas fa-times"></i> Reject</button>
                        </td>
                        <td>
                            <div class="btn-doc-wrapper">
                                <button class="action-btn" onclick="viewDocs(<?php echo $a['id']; ?>)"><i class="fas fa-folder-open"></i></button>
                                <?php if ($a['doc_count'] > 0): ?><span class="count-badge"><?php echo $a['doc_count']; ?></span><?php endif; ?>
                            </div>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

    </div><!-- /tab-content -->
</div><!-- /container -->

<!-- APPLY LEAVE MODAL -->
<div class="modal fade" id="applyLeaveModal" tabindex="-1">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header" style="background:linear-gradient(135deg,#1e3a8a,#1e40af);color:white;">
                <h4 class="modal-title"><i class="fas fa-paper-plane mr-2"></i> Request New Leave</h4>
                <button type="button" class="close" data-dismiss="modal" style="color:white;opacity:1;">&times;</button>
            </div>
            <div class="modal-body">
                <form id="leaveForm">
                    <input type="hidden" id="leave_emp_id" value="<?php echo $current_user_id; ?>">
                    <div style="background:#e0f2fe;border:2px solid #0284c7;border-radius:12px;padding:15px;margin-bottom:20px;color:#0369a1;font-size:13px;">
                        <strong><i class="fas fa-ticket-alt mr-1"></i> Tickets will be auto-created</strong><br>
                        <small>On submission, tickets are raised in the Fleet system for your L1 and L2 approvers automatically.</small>
                    </div>

                    <!-- GPS Location -->
                    <div class="location-box" id="locBox">
                        <label style="font-weight:800;color:#1e40af;"><i class="fas fa-map-marker-alt"></i> Location Check-in (Required)</label>
                        <input type="hidden" id="lLat"><input type="hidden" id="lLng"><input type="hidden" id="lAddr">
                        <input type="text" id="lDisplay" class="form-control-modern mb-2 text-center" readonly placeholder="Waiting for GPS capture..." style="background:#fff;">
                        <button type="button" class="btn-location" id="btnCapture" onclick="getGPS()">
                            <i class="fas fa-crosshairs"></i> Capture My Location
                        </button>
                    </div>

                    <div class="row">
                        <div class="col-md-6 form-group">
                            <label style="font-weight:700;">Start Date *</label>
                            <input type="date" class="form-control-modern" id="lStart" required min="<?php echo date('Y-m-d'); ?>">
                        </div>
                        <div class="col-md-6 form-group">
                            <label style="font-weight:700;">End Date *</label>
                            <input type="date" class="form-control-modern" id="lEnd" required>
                        </div>
                    </div>

                    <div class="form-group">
                        <label style="font-weight:700;">Leave Type *</label>
                        <?php if (!$is_eligible_for_paid_leaves): ?>
                        <div style="background:#fee2e2;border:2px solid #dc2626;border-radius:10px;padding:12px;margin-bottom:10px;color:#991b1b;font-size:13px;font-weight:700;">
                            <i class="fas fa-lock"></i> Paid leaves locked until <?php echo $eligibility_date; ?>. Only Unpaid Leave available.
                        </div>
                        <?php endif; ?>
                        <select class="form-control-modern" id="lType" required>
                            <option value="">-- Select Type --</option>
                            <?php if ($is_eligible_for_paid_leaves): ?>
                            <option value="sick">🤒 Sick Leave</option>
                            <option value="casual">🏖️ Casual Leave</option>
                            <option value="earned">💰 Earned Leave</option>
                            <option value="emergency">🚨 Emergency Leave</option>
                            <?php endif; ?>
                            <option value="unpaid">💸 Unpaid Leave</option>
                        </select>
                    </div>

                    <div class="row">
                        <div class="col-md-6 form-group">
                            <label style="font-weight:700;">L1 Approver (Primary) *</label>
                            <select class="form-control-modern" id="lPri" required>
                                <?php if (empty($primary_approvers)): ?>
                                <option value="">-- No Approver Configured --</option>
                                <?php else: foreach ($primary_approvers as $p): ?>
                                <option value="<?php echo $p['id']; ?>" selected><?php echo htmlspecialchars($p['name']); ?> (<?php echo htmlspecialchars($p['position']); ?>)</option>
                                <?php endforeach; endif; ?>
                            </select>
                        </div>
                        <div class="col-md-6 form-group">
                            <label style="font-weight:700;">L2 Approver (Secondary)</label>
                            <select class="form-control-modern" id="lSec">
                                <?php if (empty($secondary_approvers)): ?>
                                <option value="">-- No Secondary Approver --</option>
                                <?php else: foreach ($secondary_approvers as $s): ?>
                                <option value="<?php echo $s['id']; ?>" selected><?php echo htmlspecialchars($s['name']); ?> (<?php echo htmlspecialchars($s['position']); ?>)</option>
                                <?php endforeach; ?>
                                <option value="">(Optional) Remove Secondary</option>
                                <?php endif; ?>
                            </select>
                        </div>
                    </div>

                    <!-- ✅ L3 Tertiary Approver -->
                    <?php if (!empty($tertiary_approvers)): ?>
                    <div class="form-group">
                        <label style="font-weight:700;">L3 Approver (Tertiary)</label>
                        <select class="form-control-modern" id="lTer">
                            <option value="">(Optional) No Tertiary Approver</option>
                            <?php foreach ($tertiary_approvers as $t): ?>
                            <option value="<?php echo $t['id']; ?>"><?php echo htmlspecialchars($t['name']); ?> (<?php echo htmlspecialchars($t['position']); ?>)</option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <?php else: ?>
                    <input type="hidden" id="lTer" value="">
                    <?php endif; ?>

                    <!-- ✅ Leave Days Manual Input -->
                    <div class="form-group">
                        <label style="font-weight:700;">Number of Leave Days *</label>
                        <input type="number" class="form-control-modern" id="lDays" min="1" required placeholder="Enter number of days (e.g. 1, 2, 3...)">
                        <small style="color:#64748b;">Enter the actual number of working days you are taking leave for.</small>
                    </div>

                    <div class="form-group">
                        <label style="font-weight:700;">Reason for Leave *</label>
                        <textarea class="form-control-modern" id="lReason" rows="3" required placeholder="Explain why you are requesting leave..."></textarea>
                    </div>

                    <div class="form-group">
                        <label style="font-weight:700;">Attach Supporting Documents (Optional)</label>
                        <input type="file" id="lFiles" multiple class="form-control-modern" style="height:auto;padding:10px;">
                        <div id="fileListDisplay" class="mt-2" style="font-size:12px;color:#1e3a8a;"></div>
                    </div>

                    <button type="button" class="btn-submit-modern" id="lSubmitBtn">
                        SUBMIT &amp; CREATE TICKETS
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- DOCS MODAL -->
<div class="modal fade" id="docsModal" tabindex="-1">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header"><h4><i class="fas fa-folder-open mr-2"></i> Documents Viewer</h4><button type="button" class="close" data-dismiss="modal">&times;</button></div>
            <div class="modal-body" id="docsContent">Loading...</div>
        </div>
    </div>
</div>

<!-- MANUAL ASSIGN & RAISE TICKET MODAL -->
<div class="modal fade" id="assignTicketModal" tabindex="-1">
    <div class="modal-dialog modal-md">
        <div class="modal-content">
            <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);color:white;">
                <h4 class="modal-title"><i class="fas fa-ticket-alt mr-2"></i> Assign &amp; Raise Tickets</h4>
                <button type="button" class="close" data-dismiss="modal" style="color:white;opacity:1;">&times;</button>
            </div>
            <div class="modal-body">
                <input type="hidden" id="atLeaveId">
                <p id="atEmpName" style="font-weight:700;font-size:15px;color:#1e293b;margin-bottom:18px;"></p>

                <div style="background:#f0f9ff;border:2px solid #bae6fd;border-radius:10px;padding:15px;margin-bottom:18px;font-size:13px;color:#0369a1;">
                    <i class="fas fa-info-circle mr-1"></i>
                    Select approvers below. Tickets will be raised in the Fleet system for each selected approver.
                    If tickets already exist, new ones will be created (re-raise).
                </div>

                <div class="form-group">
                    <label style="font-weight:700;font-size:13px;">L1 Primary Approver *</label>
                    <select class="form-control-modern" id="atPriSel">
                        <option value="">-- Select L1 Approver --</option>
                        <?php foreach ($all_active_employees as $e): ?>
                        <option value="<?php echo $e['id']; ?>"><?php echo htmlspecialchars($e['name']); ?> (<?php echo htmlspecialchars($e['position']); ?>)</option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group">
                    <label style="font-weight:700;font-size:13px;">L2 Secondary Approver (Optional)</label>
                    <select class="form-control-modern" id="atSecSel">
                        <option value="">-- None / Skip L2 --</option>
                        <?php foreach ($all_active_employees as $e): ?>
                        <option value="<?php echo $e['id']; ?>"><?php echo htmlspecialchars($e['name']); ?> (<?php echo htmlspecialchars($e['position']); ?>)</option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <button type="button" class="btn-raise-ticket" id="atSubmitBtn" onclick="doManualAssign()" style="width:100%;justify-content:center;margin-top:8px;">
                    <i class="fas fa-ticket-alt"></i> RAISE TICKETS NOW
                </button>
            </div>
        </div>
    </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
var SELF_URL   = '<?php echo $self_url; ?>';
var USER_EMAIL = '<?php echo addslashes($currentUserEmail); ?>';

$(document).ready(function(){
    setDefaults();
    $('a[data-toggle="tab"]').on('shown.bs.tab', function(e){
        var t = $(e.target).attr("href");
        if (t === "#myLeaves")   applyMyFilter();
        if (t === "#allLeaves")  applyAdminFilter();
    });
});

function setDefaults(){
    var now = new Date();
    var fmt = function(d){ return d.toISOString().split('T')[0]; };
    var mStart = new Date(now.getFullYear(), now.getMonth(), 1);
    var mEnd   = new Date(now.getFullYear(), now.getMonth()+1, 0);
    if ($('#myFilterFrom').length){ $('#myFilterFrom').val(fmt(mStart)); $('#myFilterTo').val(fmt(mEnd)); applyMyFilter(); }
    if ($('#adminFilterFrom').length){ $('#adminFilterFrom').val(fmt(mStart)); $('#adminFilterTo').val(fmt(mEnd)); applyAdminFilter(); }
}

// GPS CAPTURE
function getGPS(){
    if (!navigator.geolocation) return alert('GPS not supported');
    $('#btnCapture').html('<i class="fas fa-spinner fa-spin"></i> Locating...').prop('disabled', true);
    navigator.geolocation.getCurrentPosition(function(p){
        var lat = p.coords.latitude, lng = p.coords.longitude;
        $('#lLat').val(lat); $('#lLng').val(lng);
        fetch('https://nominatim.openstreetmap.org/reverse?format=json&lat='+lat+'&lon='+lng)
            .then(function(r){ return r.json(); })
            .then(function(d){
                var a = d.display_name || lat+','+lng;
                $('#lAddr').val(a); $('#lDisplay').val(a);
                $('#locBox').css({'border-color':'#10b981','background':'#f0fdf4'});
                $('#btnCapture').html('<i class="fas fa-check-circle"></i> Captured').prop('disabled', false);
            });
    }, function(e){
        alert('GPS Error: Enable location access');
        $('#btnCapture').html('<i class="fas fa-crosshairs"></i> Retry').prop('disabled', false);
    }, {enableHighAccuracy: true, timeout: 15000});
}

// DOC GPS
function getDocLocation(){
    navigator.geolocation.getCurrentPosition(function(p){
        var lat = p.coords.latitude, lng = p.coords.longitude;
        $('#docLatitude').val(lat); $('#docLongitude').val(lng);
        fetch('https://nominatim.openstreetmap.org/reverse?format=json&lat='+lat+'&lon='+lng)
            .then(function(r){ return r.json(); })
            .then(function(d){ $('#docAddress').val(d.display_name); $('#docLocationDisplay').val(d.display_name); });
    });
}

// FILE LIST
$('#lFiles').on('change', function(){
    var files = $(this)[0].files; var str = '';
    for (var i = 0; i < files.length; i++) str += '<div><i class="fas fa-paperclip mr-1"></i> '+files[i].name+'</div>';
    $('#fileListDisplay').html(str);
});

// SUBMIT LEAVE + CREATE TICKETS
$('#lSubmitBtn').on('click', function(){
    if (!$('#lLat').val()) return alert('❌ GPS Check-in is mandatory!');
    if (!$('#lPri').val()) return alert('❌ Primary Approver is required!');
    if (!$('#lStart').val() || !$('#lEnd').val()) return alert('❌ Start and End dates are required!');
    if ($('#lEnd').val() < $('#lStart').val()) return alert('❌ End date cannot be before start date!');
    if (!$('#lType').val()) return alert('❌ Please select a leave type!');
    if (!$('#lReason').val().trim()) return alert('❌ Reason is required!');
    var leaveDays = parseInt($('#lDays').val());
    if (!leaveDays || leaveDays < 1) return alert('❌ Please enter a valid number of leave days (minimum 1).');

    var btn = $(this);
    btn.prop('disabled', true).text('⏳ SUBMITTING & CREATING TICKETS...');

    var fd = new FormData();
    fd.append('ajax_create_leave', '1');
    fd.append('user_email', USER_EMAIL);
    fd.append('employee_id', $('#leave_emp_id').val());
    fd.append('primary_approver_id', $('#lPri').val());
    fd.append('secondary_approver_id', $('#lSec').val());
    fd.append('tertiary_approver_id', $('#lTer').val() || '');
    fd.append('leave_days', leaveDays);
    fd.append('start_date', $('#lStart').val());
    fd.append('end_date', $('#lEnd').val());
    fd.append('leave_type', $('#lType').val());
    fd.append('reason', $('#lReason').val());
    fd.append('latitude', $('#lLat').val());
    fd.append('longitude', $('#lLng').val());
    fd.append('address', $('#lAddr').val());
    var files = $('#lFiles')[0].files;
    for (var i = 0; i < files.length; i++) fd.append('leave_documents[]', files[i]);

    $.ajax({
        url: SELF_URL + '?user_email=' + encodeURIComponent(USER_EMAIL),
        type: 'POST', data: fd, processData: false, contentType: false,
        success: function(r){
            if (r.success){ alert(r.message); location.reload(); }
            else { alert(r.message || '❌ Something went wrong.'); btn.prop('disabled', false).text('SUBMIT & CREATE TICKETS'); }
        },
        error: function(){ alert('Network Error — please try again.'); btn.prop('disabled', false).text('SUBMIT & CREATE TICKETS'); }
    });
});

// VIEW DOCS
function viewDocs(id){
    $('#docsModal').modal('show');
    $('#docsContent').html('<div class="text-center p-5"><i class="fas fa-spinner fa-spin fa-2x"></i></div>');
    $.get(SELF_URL + '?ajax_get_documents=1&leave_id='+id+'&user_email='+encodeURIComponent(USER_EMAIL), function(r){
        $('#docsContent').html(r);
    });
}

// APPROVE / REJECT
function doApprove(id, btn){
    if (!confirm('Approve this leave request?')) return;
    $(btn).prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i>');
    $.post(SELF_URL + '?user_email='+encodeURIComponent(USER_EMAIL), {ajax_approve_leave:1, leave_id:id}, function(r){
        if (r.success){ alert(r.message); location.reload(); }
        else { alert(r.message); $(btn).prop('disabled', false).html('<i class="fas fa-check"></i> Approve'); }
    }, 'json').fail(function(){ alert('Network error'); $(btn).prop('disabled', false); });
}

function doReject(id, btn){
    if (!confirm('Reject this leave request?')) return;
    $(btn).prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i>');
    $.post(SELF_URL + '?user_email='+encodeURIComponent(USER_EMAIL), {ajax_reject_leave:1, leave_id:id}, function(r){
        if (r.success){ alert(r.message); location.reload(); }
        else { alert(r.message); $(btn).prop('disabled', false).html('<i class="fas fa-times"></i> Reject'); }
    }, 'json').fail(function(){ alert('Network error'); $(btn).prop('disabled', false); });
}

// MANUAL ASSIGN & RAISE TICKET MODAL
function openAssignModal(leaveId, empName, currentPriId, currentSecId){
    $('#atLeaveId').val(leaveId);
    $('#atEmpName').text('Leave request for: ' + empName);
    // Pre-select current approvers if set
    if (currentPriId > 0) $('#atPriSel').val(currentPriId);
    if (currentSecId > 0) $('#atSecSel').val(currentSecId);
    $('#assignTicketModal').modal('show');
}

function doManualAssign(){
    var leaveId  = $('#atLeaveId').val();
    var priId    = $('#atPriSel').val();
    var secId    = $('#atSecSel').val() || 0;
    if (!priId){ alert('❌ Please select a Primary (L1) Approver'); return; }

    var btn = $('#atSubmitBtn');
    btn.prop('disabled', true).html('<i class="fas fa-spinner fa-spin"></i> Creating Tickets...');

    $.post(SELF_URL + '?user_email=' + encodeURIComponent(USER_EMAIL), {
        ajax_manual_assign_ticket: 1,
        leave_id: leaveId,
        primary_approver_id: priId,
        secondary_approver_id: secId
    }, function(r){
        btn.prop('disabled', false).html('<i class="fas fa-ticket-alt"></i> RAISE TICKETS NOW');
        if (r.success){
            alert(r.message);
            $('#assignTicketModal').modal('hide');
            location.reload();
        } else {
            alert('❌ ' + (r.message || 'Failed to create tickets'));
        }
    }, 'json').fail(function(){
        btn.prop('disabled', false).html('<i class="fas fa-ticket-alt"></i> RAISE TICKETS NOW');
        alert('Network error — please try again');
    });
}

// FILTERS
function applyMyFilter(){
    var fDate = $('#myFilterFrom').val(), tDate = $('#myFilterTo').val(),
        lType = $('#myFilterType').val(), lStat = $('#myFilterStatus').val();
    $('#myLeavesTable tbody tr').each(function(){
        var rS = $(this).data('start'), rT = $(this).data('type'), rSt = $(this).data('status');
        var show = true;
        if (fDate && rS < fDate) show = false;
        if (tDate && rS > tDate) show = false;
        if (lType && rT != lType) show = false;
        if (lStat && rSt != lStat) show = false;
        $(this).toggle(show);
    });
}
function applyAdminFilter(){
    var fDate = $('#adminFilterFrom').val(), tDate = $('#adminFilterTo').val(),
        name = $('#adminFilterEmp').val(), status = $('#adminFilterStatus').val();
    $('#allLeavesTable tbody tr').each(function(){
        var rApplied = $(this).data('applied'), rS = $(this).data('start'),
            rN = $(this).data('name'), rSt = $(this).data('status');
        var show = true;
        if (fDate && tDate){
            var inA = rApplied && rApplied >= fDate && rApplied <= tDate;
            var inS = rS && rS >= fDate && rS <= tDate;
            if (!inA && !inS) show = false;
        }
        if (name && rN != name) show = false;
        if (status && rSt != status) show = false;
        $(this).toggle(show);
    });
}
function exportToCSV(tableId, filename){
    var csv = []; var rows = document.querySelectorAll('#'+tableId+' tr:not([style*="display: none"])');
    for (var i = 0; i < rows.length; i++){
        var row = []; var cols = rows[i].querySelectorAll('td,th');
        for (var j = 0; j < cols.length; j++){
            var txt = cols[j].innerText.replace(/"/g,'""').replace(/\n/g,' ').trim();
            row.push('"'+txt+'"');
        }
        csv.push(row.join(','));
    }
    var blob = new Blob(['\ufeff'+csv.join('\n')], {type:'text/csv;charset=utf-8;'});
    var link = document.createElement('a'); link.href = URL.createObjectURL(blob);
    link.download = filename; link.click();
}

function applyBalFilter(){
    var empVal  = ($('#balFilterEmp').val()  || '').toLowerCase().trim();
    var deptVal = ($('#balFilterDept').val() || '').toLowerCase().trim();
    $('#balancesTable tbody tr').each(function(){
        var name = ($(this).data('name') || '').toLowerCase();
        var dept = ($(this).data('dept') || '').toLowerCase();
        var show = (!empVal  || name.includes(empVal))
                && (!deptVal || dept.includes(deptVal));
        $(this).toggle(show);
    });
}
</script>
</body>
</html>
<?php ob_end_flush(); ?>