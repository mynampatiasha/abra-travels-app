<?php
// ✅ FORCE CACHE BYPASS - Version 2026-03-04-v2
if (function_exists('opcache_reset')) {
    opcache_reset();
}
if (function_exists('opcache_invalidate')) {
    opcache_invalidate(__FILE__, true);
}
clearstatcache(true, __FILE__);

// ============================================================
// ABRA TRAVELS — CONTACT & SALES ENQUIRIES (ADMIN PANEL)
// Displays all submissions from contact.php
// Features: View, Assign, Notes, Status, Email, PDF, Delete
// ============================================================
ob_start();
error_reporting(E_ERROR | E_WARNING | E_PARSE);
if (session_status() == PHP_SESSION_NONE) { session_start(); }

require_once('database.php');
require_once('library.php');
require_once('funciones.php');
require_once('abra_email_helper.php');
// isUser(); // Uncomment in production

// ── DB CONNECTION ─────────────────────────────────────────────────────────────
$con = null;
if (function_exists('conexion')) {
    $con = conexion();
} elseif (isset($dbConn)) {
    $con = $dbConn;
} elseif (function_exists('dbConnection')) {
    $con = dbConnection();
}
if (!$con) { header('Content-Type: application/json'); echo json_encode(['success'=>false,'message'=>'DB connection failed']); exit; }
mysqli_set_charset($con, 'utf8mb4');

// ── DB HELPERS ────────────────────────────────────────────────────────────────
function aq($con, $sql)       { return mysqli_query($con, $sql); }
function ae($con)             { return mysqli_error($con); }
function ares($con, $sql)     { $r = aq($con,$sql); if ($r && mysqli_num_rows($r)>0) return mysqli_fetch_assoc($r); return null; }
function aesc($con, $v)       { return mysqli_real_escape_string($con, trim((string)($v??''))); }
function acnt($con, $sql)     { $r = aq($con,$sql); $row = $r?mysqli_fetch_assoc($r):null; return $row?(int)($row['c']??0):0; }

// ✅ Creator = whoever is logged in via Flutter WebView
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';

// ✅ DEBUG LOGGING - Track URL parameter
error_log("=== CONTACT SALES DEBUG ===");
error_log("URL Parameter user_email: " . ($currentUserEmail ?: 'EMPTY'));
error_log("Full GET params: " . print_r($_GET, true));

$creator_name  = '';
$creator_email = '';
$created_by    = 1;

if(!empty($currentUserEmail)) {
    $email_safe  = mysqli_real_escape_string($con, $currentUserEmail);
    $creator_row = ares($con, "SELECT id, name, email FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'active' LIMIT 1");
    if($creator_row) {
        $creator_name  = $creator_row['name'];
        $creator_email = $creator_row['email'];
        $created_by    = (int)$creator_row['id'];
    } else {
        // ✅ If user not found in hr_employees, use the email from URL directly
        $creator_email = $currentUserEmail;
        $creator_name  = 'Admin User'; // Default name if not found in database
    }
}


// ── AUTO-CREATE TABLE ─────────────────────────────────────────────────────────
aq($con, "CREATE TABLE IF NOT EXISTS `contact_enquiries` (
    `id`                   int(11)      NOT NULL AUTO_INCREMENT,
    `audience_type`        varchar(30)  DEFAULT 'customer'  COMMENT 'customer | vendor | general',
    `name`                 varchar(200) DEFAULT NULL,
    `email`                varchar(200) DEFAULT NULL,
    `phone`                varchar(50)  DEFAULT NULL,
    `company_name`         varchar(200) DEFAULT NULL,
    -- Customer fields
    `vehicle_type`         varchar(100) DEFAULT NULL,
    `trip_type`            varchar(100) DEFAULT NULL,
    `pickup_date`          date         DEFAULT NULL,
    `pickup_location`      varchar(200) DEFAULT NULL,
    `dropoff_location`     varchar(200) DEFAULT NULL,
    -- Vendor fields
    `fleet_size`           varchar(100) DEFAULT NULL,
    `vendor_vehicle_type`  varchar(100) DEFAULT NULL,
    `vendor_city`          varchar(200) DEFAULT NULL,
    `years_in_business`    varchar(100) DEFAULT NULL,
    -- General fields
    `enquiry_topic`        varchar(200) DEFAULT NULL,
    `contact_pref`         varchar(100) DEFAULT NULL,
    -- Common
    `message`              text         DEFAULT NULL,
    `source_page`          varchar(255) DEFAULT 'contact.php',
    `ip_address`           varchar(45)  DEFAULT NULL,
    `user_agent`           text         DEFAULT NULL,
    -- CRM fields
    `assigned_to`          varchar(200) DEFAULT NULL,
    `assigned_employee_id` int(11)      DEFAULT NULL,
    `status`               varchar(30)  DEFAULT 'new',
    `admin_notes`          text         DEFAULT NULL,
    `follow_up_date`       date         DEFAULT NULL,
    `created_at`           datetime     DEFAULT CURRENT_TIMESTAMP,
    `updated_at`           datetime     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Contact form submissions from contact.php'");

// Safe alter table additions
foreach ([
    "ALTER TABLE `contact_enquiries` ADD COLUMN IF NOT EXISTS `source_page` varchar(255) DEFAULT 'contact.php'",
    "ALTER TABLE `contact_enquiries` ADD COLUMN IF NOT EXISTS `ip_address` varchar(45) DEFAULT NULL",
    "ALTER TABLE `contact_enquiries` ADD COLUMN IF NOT EXISTS `user_agent` text DEFAULT NULL",
    "ALTER TABLE `contact_enquiries` ADD COLUMN IF NOT EXISTS `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
] as $a) { @aq($con, $a); }

// ── FETCH EMPLOYEES ───────────────────────────────────────────────────────────
$employees = [];
$api_response = @file_get_contents('https://fleet.abra-travels.com/api/tickets/public-employees');
if ($api_response) {
    $api_data = json_decode($api_response, true);
    if ($api_data && $api_data['success']) {
        foreach ($api_data['data'] as $e) {
            $employees[] = [
    'id'    => (string)($e['_id']['$oid'] ?? $e['_id'] ?? ''),
    'name'  => $e['name_parson'] ?? $e['username'] ?? 'Unknown',
    'email' => strtolower(trim($e['email'] ?? ''))
];
        }
    }
}

// ── EMAIL HELPER ──────────────────────────────────────────────────────────────
function sendATEmail($to, $subject, $html_body) {
    $headers  = "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
    $headers .= "From: Abra Tours & Travels <noreply@abra-travels.com>\r\n";
    $headers .= "Reply-To: info@abra-travels.com\r\n";
    $headers .= "X-Mailer: PHP/" . phpversion() . "\r\n";
    return mail($to, $subject, $html_body, $headers);
}

// ── AJAX HANDLERS ─────────────────────────────────────────────────────────────
if (isset($_GET['ajax'])) {
    ob_clean();
    header('Content-Type: application/json; charset=utf-8');
    try {
        $id = (int)($_POST['id'] ?? $_GET['id'] ?? 0);

        // UPDATE STATUS
        if ($_GET['ajax'] === 'update_status') {
            if (!$id) throw new Exception('Missing ID');
            $status = aesc($con, $_POST['status'] ?? '');
            $valid  = ['new','contacted','in_progress','quoted','confirmed','cancelled','closed'];
            if (!in_array($status, $valid)) throw new Exception('Invalid status: ' . $status);
            $ok = aq($con, "UPDATE contact_enquiries SET status='$status', updated_at=NOW() WHERE id=$id");
            if (!$ok) throw new Exception('DB update failed: ' . ae($con));
            echo json_encode(['success' => true, 'status' => $status]);
            exit;
        }

        // ASSIGN + RAISE TICKET
        if ($_GET['ajax'] === 'assign_and_ticket') {
            if (!$id) throw new Exception('Missing enquiry ID');
            $emp_name_raw = trim($_POST['employee_name'] ?? '');
            $emp_name     = aesc($con, $emp_name_raw);
            if (!$emp_name) throw new Exception('Please select an agent');

            // API IDs are MongoDB strings — resolve integer ID from hr_employees by name
            $emp_check = ares($con, "SELECT id, name FROM hr_employees WHERE name='$emp_name' LIMIT 1");
            if (!$emp_check) $emp_check = ares($con, "SELECT id, name FROM hr_employees WHERE name LIKE '%$emp_name%' LIMIT 1");
            if (!$emp_check) $emp_check = ares($con, "SELECT id, name FROM hr_employees ORDER BY id ASC LIMIT 1");
            $emp_id = $emp_check ? (int)$emp_check['id'] : 1;

            aq($con, "UPDATE contact_enquiries SET assigned_to='$emp_name', assigned_employee_id=$emp_id, updated_at=NOW() WHERE id=$id");

            $enq = ares($con, "SELECT * FROM contact_enquiries WHERE id=$id LIMIT 1");
            if (!$enq) throw new Exception('Enquiry not found');

            $ref_id    = 'CE-' . str_pad($id, 5, '0', STR_PAD_LEFT);
            $aud_label = ['customer'=>'Customer Booking','vendor'=>'Vendor Partnership','general'=>'General Enquiry'][$enq['audience_type']] ?? 'Enquiry';
            $dest      = trim(($enq['dropoff_location'] ?? $enq['vendor_city'] ?? ''));

            // ✅ creator_name, creator_email, created_by already set from URL email above
// Fallback to session only if URL email was not provided
if (!empty($_POST['creator_email'])) {
    $creator_email = aesc($con, $_POST['creator_email']);
    $creator_name  = aesc($con, $_POST['creator_name'] ?? 'Admin User');
}
if(empty($currentUserEmail)) {
    $session_name = $_SESSION['user_name'] ?? '';
    if($session_name) {
        $sn = aesc($con, $session_name);
        $sr = ares($con, "SELECT id, name, email FROM hr_employees 
            WHERE name='$sn' OR name LIKE '%$sn%' LIMIT 1");
        if($sr) {
            $created_by    = (int)$sr['id'];
            $creator_name  = $sr['name'];
            $creator_email = $sr['email'];
        }
    }
}

// ✅ REMOVED HARDCODED FALLBACK - Let it fail if URL parameter not received
// This will help us debug why the parameter isn't being read
if(empty($creator_email)) {
    error_log("ERROR: creator_email is EMPTY! URL parameter not received!");
    error_log("GET params: " . print_r($_GET, true));
    error_log("REQUEST_URI: " . ($_SERVER['REQUEST_URI'] ?? 'not set'));
    // DO NOT set fallback - let backend reject it so we can see the error
}

            $priority  = 'medium';
            $timeline  = 1440;
            $deadline  = date('Y-m-d H:i:s', strtotime('+1440 minutes'));
            $t_status  = 'open';
            $t_name    = aesc($con, $enq['name'] ?? 'Contact');
            $t_subject = aesc($con, "$aud_label [$ref_id]" . ($dest ? " — $dest" : ''));
            $msg_parts = [
                "Customer: "   . ($enq['name']   ?? ''),
                "Phone: "      . ($enq['phone']  ?? ''),
                "Email: "      . ($enq['email']  ?? ''),
                "Ref: "        . $ref_id,
                "Type: "       . ucfirst($enq['audience_type'] ?? 'customer'),
            ];
            if ($enq['audience_type'] === 'customer') {
                $msg_parts[] = "Vehicle: "  . ($enq['vehicle_type']       ?? '');
                $msg_parts[] = "Trip: "     . ($enq['trip_type']          ?? '');
                $msg_parts[] = "Pickup: "   . ($enq['pickup_location']    ?? '');
                $msg_parts[] = "Dropoff: "  . ($enq['dropoff_location']   ?? '');
                $msg_parts[] = "Date: "     . ($enq['pickup_date']        ?? '');
            } elseif ($enq['audience_type'] === 'vendor') {
                $msg_parts[] = "Company: "  . ($enq['company_name']       ?? '');
                $msg_parts[] = "Fleet: "    . ($enq['fleet_size']         ?? '');
                $msg_parts[] = "Type: "     . ($enq['vendor_vehicle_type'] ?? '');
                $msg_parts[] = "City: "     . ($enq['vendor_city']        ?? '');
            } else {
                $msg_parts[] = "Topic: "    . ($enq['enquiry_topic']      ?? '');
                $msg_parts[] = "Pref: "     . ($enq['contact_pref']       ?? '');
            }
            $msg_parts[] = "Message: " . ($enq['message'] ?? '');
            $t_message  = aesc($con, implode("\n", $msg_parts));

            // ✅ NEW — Send ticket to MongoDB via Node.js internal API
// Find assigned employee email from hr_employees
// ✅ Email comes directly from MongoDB API — no MySQL lookup needed
$assigned_email_for_ticket = strtolower(trim($_POST['employee_email'] ?? ''));

// ✅ DEBUG LOGGING - Track ticket assignment data
error_log("=== TICKET ASSIGNMENT DEBUG ===");
error_log("Assigned Email: " . $assigned_email_for_ticket);
error_log("Assigned Name: " . $emp_name);
error_log("Creator Email: " . $creator_email);
error_log("Creator Name: " . $creator_name);

$ticket_payload = json_encode([
    'subject'        => "$aud_label [$ref_id]" . ($dest ? " — $dest" : ''),
    'message'        => implode("\n", $msg_parts),
    'priority'       => 'medium',
    'timeline'       => 1440,
    'assigned_name'  => $emp_name,
    'assigned_email' => $assigned_email_for_ticket,
    'creator_name'   => $creator_name,
    'creator_email'  => $creator_email,
]);

// ✅ DEBUG LOGGING - Log complete JSON payload
error_log("Ticket Payload JSON: " . $ticket_payload);

$ch = curl_init('http://localhost:3001/api/tickets/internal/create');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $ticket_payload,
    CURLOPT_HTTPHEADER     => [
        'Content-Type: application/json',
        'x-internal-key: abra_internal_2026'
    ],
    CURLOPT_TIMEOUT        => 15,
    CURLOPT_SSL_VERIFYPEER => false,
]);

$api_result = curl_exec($ch);
$http_code  = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curl_error = curl_error($ch);
curl_close($ch);

// ✅ DEBUG LOGGING - Log API response
error_log("HTTP Status Code: " . $http_code);
error_log("API Response: " . $api_result);
if ($curl_error) {
    error_log("CURL Error: " . $curl_error);
}

if ($curl_error) throw new Exception('Ticket API connection failed: ' . $curl_error);

$ticket_response = json_decode($api_result, true);
if (!$ticket_response || !$ticket_response['success']) {
    $error_msg = $ticket_response['error'] ?? 'Unknown error';
    error_log("Ticket Creation Failed: " . $error_msg);
    throw new Exception('Ticket creation failed: ' . $error_msg);
}

$ticket_number = $ticket_response['ticket_number'];
error_log("Ticket Created Successfully: " . $ticket_number);
error_log("=== END TICKET ASSIGNMENT DEBUG ===");

            echo json_encode([
    'success'       => true,
    'ticket_number' => $ticket_number,
    'message'       => "Assigned to $emp_name. Ticket $ticket_number created in Fleet system."
]);
            exit;
        }

        // SAVE NOTES + FOLLOW-UP
        if ($_GET['ajax'] === 'save_notes') {
            if (!$id) throw new Exception('Missing ID');
            $notes = aesc($con, $_POST['notes'] ?? '');
            $fdate = !empty($_POST['follow_up_date']) ? "'" . aesc($con, $_POST['follow_up_date']) . "'" : 'NULL';
            aq($con, "UPDATE contact_enquiries SET admin_notes='$notes', follow_up_date=$fdate, updated_at=NOW() WHERE id=$id");
            echo json_encode(['success' => true, 'message' => 'Notes saved']);
            exit;
        }

        // GET DETAIL
        if ($_GET['ajax'] === 'get_detail') {
            if (!$id) throw new Exception('Missing ID');
            $r   = aq($con, "SELECT * FROM contact_enquiries WHERE id=$id LIMIT 1");
            $row = ($r && mysqli_num_rows($r) > 0) ? mysqli_fetch_assoc($r) : null;
            if (!$row) throw new Exception('Enquiry #' . $id . ' not found');
            echo json_encode(['success' => true, 'data' => $row, 'employees' => $employees]);
            exit;
        }

        // SEND EMAIL
        if ($_GET['ajax'] === 'send_email') {
            if (!$id) throw new Exception('Missing ID');
            $enq = ares($con, "SELECT * FROM contact_enquiries WHERE id=$id LIMIT 1");
            if (!$enq) throw new Exception('Enquiry not found');
            $email = trim($enq['email'] ?? '');
            if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL))
                throw new Exception('Customer does not have a valid email address');

            $ref_id    = 'CE-' . str_pad($id, 5, '0', STR_PAD_LEFT);
            $cname     = htmlspecialchars($enq['name'] ?? 'Valued Customer');
            $c_subject = trim($_POST['subject'] ?? "Your Enquiry - $ref_id | Abra Tours & Travels");
            $c_msg     = trim($_POST['custom_message'] ?? '');
            $aud_label = ['customer'=>'Booking Enquiry','vendor'=>'Vendor Partnership Enquiry','general'=>'General Enquiry'][$enq['audience_type']] ?? 'Enquiry';

            // Build summary rows
            $rows = [];
            $rows[] = ['Reference No.',  '<strong style="color:#1e3a8a;">' . $ref_id . '</strong>'];
            $rows[] = ['Enquiry Type',   ucfirst($enq['audience_type'] ?? 'customer')];
            if ($enq['audience_type'] === 'customer') {
                $rows[] = ['Vehicle Type',   htmlspecialchars($enq['vehicle_type'] ?? '—')];
                $rows[] = ['Trip Type',      htmlspecialchars($enq['trip_type'] ?? '—')];
                $rows[] = ['Pickup From',    htmlspecialchars($enq['pickup_location'] ?? '—')];
                $rows[] = ['Drop-off To',    htmlspecialchars($enq['dropoff_location'] ?? '—')];
                $rows[] = ['Travel Date',    !empty($enq['pickup_date']) ? date('d M Y', strtotime($enq['pickup_date'])) : '—'];
            } elseif ($enq['audience_type'] === 'vendor') {
                if (!empty($enq['company_name'])) $rows[] = ['Company', htmlspecialchars($enq['company_name'])];
                $rows[] = ['Fleet Size',     htmlspecialchars($enq['fleet_size'] ?? '—')];
                $rows[] = ['Vehicle Type',   htmlspecialchars($enq['vendor_vehicle_type'] ?? '—')];
                $rows[] = ['City',           htmlspecialchars($enq['vendor_city'] ?? '—')];
                $rows[] = ['Experience',     htmlspecialchars($enq['years_in_business'] ?? '—')];
            } else {
                $rows[] = ['Topic',          htmlspecialchars($enq['enquiry_topic'] ?? '—')];
                $rows[] = ['Preferred Contact', htmlspecialchars($enq['contact_pref'] ?? '—')];
            }

            $body  = '<!DOCTYPE html><html><head><meta charset="utf-8"/></head>';
            $body .= '<body style="font-family:Arial,sans-serif;background:#f0f4f8;margin:0;padding:20px;">';
            $body .= '<div style="max-width:600px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,.1);">';
            $body .= '<div style="background:linear-gradient(135deg,#1e40af,#1e3a8a);padding:24px 30px;text-align:center;">';
            $body .= '<img src="https://abra-travels.com/images/logo.png" alt="Abra Tours" style="max-height:60px;margin-bottom:10px;" onerror="this.style.display=\'none\'">';
            $body .= '<h1 style="color:#fff;font-size:1.3rem;margin:0;">Abra Tours &amp; Travels</h1>';
            $body .= '<p style="color:rgba(255,255,255,.75);font-size:13px;margin:4px 0 0;">Your Journey, Our Commitment</p></div>';
            $body .= '<div style="padding:28px 30px;">';
            $body .= '<p style="font-size:15px;color:#1e293b;">Dear <strong>' . $cname . '</strong>,</p>';
            $body .= '<p style="font-size:14px;color:#475569;line-height:1.8;">Thank you for reaching out to Abra Tours &amp; Travels. We have received your ' . $aud_label . ' and our team will get in touch with you shortly.</p>';
            if ($c_msg) {
                $body .= '<div style="background:#eff6ff;border-left:4px solid #1e40af;border-radius:0 8px 8px 0;padding:14px 18px;margin:18px 0;font-size:14px;color:#1e293b;line-height:1.7;">' . nl2br(htmlspecialchars($c_msg)) . '</div>';
            }
            $body .= '<div style="background:#f8fafc;border:2px solid #e2e8f0;border-radius:12px;padding:18px 20px;margin:18px 0;">';
            $body .= '<h3 style="font-size:14px;font-weight:700;color:#1e40af;margin:0 0 14px;">📋 Your Enquiry Summary</h3>';
            $body .= '<table style="width:100%;border-collapse:collapse;font-size:13.5px;">';
            foreach ($rows as $r) {
                $body .= '<tr><td style="padding:7px 0;color:#64748b;width:42%;border-bottom:1px solid #f1f5f9;">'.$r[0].'</td><td style="font-weight:700;color:#1e293b;border-bottom:1px solid #f1f5f9;">'.$r[1].'</td></tr>';
            }
            $body .= '</table></div>';
            if (!empty($enq['message'])) {
                $body .= '<div style="background:#f8fafc;border-radius:9px;padding:12px 16px;margin-bottom:16px;font-size:13.5px;color:#334155;line-height:1.7;"><strong>Your Message:</strong><br>'.nl2br(htmlspecialchars($enq['message'])).'</div>';
            }
            $body .= '<p style="font-size:14px;color:#475569;line-height:1.8;">Our team will contact you within <strong>30 minutes</strong> during business hours.</p>';
            $body .= '<div style="text-align:center;margin-top:22px;"><a href="https://wa.me/919686774946" style="background:linear-gradient(135deg,#1e40af,#1e3a8a);color:#fff;padding:12px 28px;border-radius:9px;text-decoration:none;font-size:14px;font-weight:700;display:inline-block;">💬 Chat on WhatsApp</a></div>';
            $body .= '</div>';
            $body .= '<div style="background:#f8fafc;padding:16px;text-align:center;font-size:12px;color:#94a3b8;border-top:2px solid #e2e8f0;">';
            $body .= 'Abra Tours &amp; Travels | <a href="https://abra-travels.com" style="color:#1e40af;text-decoration:none;">abra-travels.com</a> | ';
            $body .= '<a href="tel:+919686774946" style="color:#1e40af;text-decoration:none;">+91 9686 774 946</a><br>';
            $body .= 'Reference: ' . $ref_id . '</div></div></body></html>';

$sent = abraSendAdminEmailToCustomer(
    $email,
    $enq['name'] ?? 'Valued Customer',
    $c_subject,
    $c_msg,
    $ref_id,
    $enq
);
if (!$sent) throw new Exception('Email delivery failed. Check server mail config.');
            echo json_encode(['success' => true, 'message' => "Email sent to $email"]);
            exit;
        }

        // DELETE
        if ($_GET['ajax'] === 'delete') {
            if (!$id) throw new Exception('Missing ID');
            aq($con, "DELETE FROM contact_enquiries WHERE id=$id");
            echo json_encode(['success' => true]);
            exit;
        }

        throw new Exception('Unknown AJAX action: ' . ($_GET['ajax'] ?? 'none'));

    } catch (Throwable $e) {
        echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        exit;
    }
}

// ── CSV EXPORT ────────────────────────────────────────────────────────────────
if (isset($_GET['export']) && $_GET['export'] === 'csv') {
    ob_clean();
    $exp = aq($con, "SELECT id, audience_type, name, phone, email, company_name, vehicle_type, trip_type, pickup_date, pickup_location, dropoff_location, fleet_size, vendor_vehicle_type, vendor_city, years_in_business, enquiry_topic, contact_pref, message, assigned_to, status, follow_up_date, created_at FROM contact_enquiries ORDER BY created_at DESC");
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=contact_enquiries_' . date('Ymd_His') . '.csv');
    $out = fopen('php://output', 'w');
    fprintf($out, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($out, ['ID','Type','Name','Phone','Email','Company','Vehicle Type','Trip Type','Pickup Date','From','To','Fleet Size','Vendor Vehicle','Vendor City','Experience','Topic','Pref Contact','Message','Assigned To','Status','Follow-up','Created']);
    if ($exp) while ($row = mysqli_fetch_assoc($exp)) fputcsv($out, array_values($row));
    fclose($out);
    exit;
}

// ── FILTERS ───────────────────────────────────────────────────────────────────
$f_status  = aesc($con, $_GET['status']     ?? '');
$f_aud     = aesc($con, $_GET['audience']   ?? '');
$f_search  = aesc($con, $_GET['search']     ?? '');
$f_agent   = aesc($con, $_GET['agent']      ?? '');
$f_df      = aesc($con, $_GET['date_from']  ?? '');
$f_dt      = aesc($con, $_GET['date_to']    ?? '');

$where = "WHERE 1=1";
if ($f_status) $where .= " AND status='$f_status'";
if ($f_aud)    $where .= " AND audience_type='$f_aud'";
if ($f_search) $where .= " AND (name LIKE '%$f_search%' OR phone LIKE '%$f_search%' OR email LIKE '%$f_search%' OR pickup_location LIKE '%$f_search%' OR dropoff_location LIKE '%$f_search%' OR vendor_city LIKE '%$f_search%')";
if ($f_agent)  $where .= " AND assigned_to='$f_agent'";
if ($f_df)     $where .= " AND DATE(created_at) >= '$f_df'";
if ($f_dt)     $where .= " AND DATE(created_at) <= '$f_dt'";

// ── STATS ─────────────────────────────────────────────────────────────────────
$stats = [
    'total'       => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries"),
    'new'         => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE status='new'"),
    'in_progress' => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE status IN ('contacted','in_progress','quoted')"),
    'confirmed'   => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE status='confirmed'"),
    'today'       => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE DATE(created_at)=CURDATE()"),
    'follow_up'   => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE follow_up_date=CURDATE() AND status NOT IN ('confirmed','cancelled','closed')"),
    'customers'   => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE audience_type='customer'"),
    'vendors'     => acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE audience_type='vendor'"),
];

$result = aq($con, "SELECT * FROM contact_enquiries $where ORDER BY created_at DESC");

$STATUS = [
    'new'         => ['label'=>'New',         'color'=>'#1e40af','bg'=>'#eff6ff','border'=>'#bfdbfe'],
    'contacted'   => ['label'=>'Contacted',   'color'=>'#d97706','bg'=>'#fffbeb','border'=>'#fcd34d'],
    'in_progress' => ['label'=>'In Progress', 'color'=>'#7c3aed','bg'=>'#fdf4ff','border'=>'#e9d5ff'],
    'quoted'      => ['label'=>'Quoted',      'color'=>'#0891b2','bg'=>'#ecfeff','border'=>'#a5f3fc'],
    'confirmed'   => ['label'=>'Confirmed',   'color'=>'#16a34a','bg'=>'#f0fdf4','border'=>'#86efac'],
    'cancelled'   => ['label'=>'Cancelled',   'color'=>'#dc2626','bg'=>'#fef2f2','border'=>'#fecaca'],
    'closed'      => ['label'=>'Closed',      'color'=>'#64748b','bg'=>'#f8fafc','border'=>'#e2e8f0'],
];

$AUD_CFG = [
    'customer' => ['icon'=>'👤','label'=>'Customer Booking', 'color'=>'#1e40af','bg'=>'#eff6ff','border'=>'#bfdbfe'],
    'vendor'   => ['icon'=>'🚛','label'=>'Vendor / Fleet',   'color'=>'#d97706','bg'=>'#fffbeb','border'=>'#fcd34d'],
    'general'  => ['icon'=>'💬','label'=>'General Enquiry',  'color'=>'#7c3aed','bg'=>'#fdf4ff','border'=>'#e9d5ff'],
];
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Contact Enquiries | Abra Travels CRM</title>
<link rel="shortcut icon" type="image/png" href="img/favicon.png"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css" crossorigin="anonymous"/>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800;900&display=swap" rel="stylesheet"/>
<style>
*,*::before,*::after{box-sizing:border-box;}
body,h1,h2,h3,h4,h5,h6,p,span,a,td,th,label,input,select,textarea,button,small,li,div{font-family:'Poppins',sans-serif!important;}
body{background:#f0f4f8;margin:0;padding:0;}
.at-wrap{padding:20px 24px 60px;}

/* HEADER */
.at-header{background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);border-radius:14px;padding:20px 28px;margin-bottom:22px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;box-shadow:0 6px 24px rgba(30,58,138,.3);}
.at-header h1{color:#fff;font-weight:800;font-size:1.35rem;margin:0;display:flex;align-items:center;gap:10px;}
.at-header h1 small{font-size:.75rem;font-weight:600;opacity:.75;display:block;margin-top:3px;}
.hdr-btns{display:flex;gap:10px;flex-wrap:wrap;}
.btn-hdr{background:rgba(255,255,255,.16);color:#fff!important;padding:9px 20px;border-radius:9px;text-decoration:none!important;font-weight:700;font-size:13.5px;display:inline-flex;align-items:center;gap:7px;border:1.5px solid rgba(255,255,255,.28);cursor:pointer;transition:.2s;white-space:nowrap;}
.btn-hdr:hover{background:rgba(255,255,255,.28);}

/* STAT CARDS */
.stat-card{background:#fff;border-radius:14px;padding:16px 20px;box-shadow:0 2px 14px rgba(0,0,0,.07);display:flex;align-items:center;gap:14px;border-left:5px solid transparent;transition:transform .2s;height:100%;}
.stat-card:hover{transform:translateY(-3px);box-shadow:0 6px 24px rgba(0,0,0,.12);}
.s-blue{border-left-color:#1e40af;}.s-amber{border-left-color:#d97706;}.s-green{border-left-color:#16a34a;}.s-cyan{border-left-color:#0891b2;}.s-red{border-left-color:#dc2626;}.s-purple{border-left-color:#7c3aed;}
.stat-icon{width:50px;height:50px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;}
.i-blue{background:#eff6ff;color:#1e40af;}.i-amber{background:#fffbeb;color:#d97706;}.i-green{background:#f0fdf4;color:#16a34a;}.i-cyan{background:#ecfeff;color:#0891b2;}.i-red{background:#fef2f2;color:#dc2626;}.i-purple{background:#fdf4ff;color:#7c3aed;}
.stat-num{font-size:28px;font-weight:900;color:#1e293b;margin:0;line-height:1;}
.stat-lbl{font-size:12px;color:#94a3b8;font-weight:600;margin:2px 0 0;}

/* FILTER BAR */
.filter-bar{background:#fff;border-radius:12px;box-shadow:0 1px 8px rgba(0,0,0,.07);padding:18px 22px;margin-bottom:16px;}
.filter-bar .bar-title{font-size:13.5px;font-weight:700;color:#1e40af;display:flex;align-items:center;gap:7px;margin-bottom:14px;}
.frow{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end;margin-bottom:10px;}
.frow:last-child{margin-bottom:0;}
.fg{display:flex;flex-direction:column;flex:1;min-width:140px;}
.fg label{font-size:11.5px;font-weight:700;color:#374151;margin-bottom:4px;}
.fc{border:1.5px solid #d1d5db;border-radius:8px;padding:0 12px;font-size:13.5px;height:40px;color:#111827;width:100%;background:#fff;transition:border-color .15s;-webkit-appearance:none;}
.fc:focus{border-color:#1e40af;outline:none;box-shadow:0 0 0 3px rgba(30,64,175,.1);}
.fc::placeholder{color:#9ca3af;}
.btn-apply{background:#1e40af;color:#fff;border:none;border-radius:8px;padding:0 22px;height:40px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;white-space:nowrap;transition:.15s;}
.btn-apply:hover{background:#1e3a8a;}
.btn-reset{background:#f3f4f6;color:#6b7280;border:1.5px solid #d1d5db;border-radius:8px;padding:0 16px;height:40px;font-size:13.5px;font-weight:600;text-decoration:none;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;}
.btn-reset:hover{background:#e5e7eb;color:#374151;text-decoration:none;}

/* QUICK TABS */
.tab-pills{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;}
.tab-pill{background:#fff;border:2px solid #e2e8f0;color:#64748b;padding:6px 16px;border-radius:50px;font-size:13px;font-weight:700;text-decoration:none;transition:.15s;}
.tab-pill:hover{border-color:#1e40af;color:#1e40af;text-decoration:none;}
.tab-pill.active{border-color:#1e40af;color:#1e40af;background:#eff6ff;}

/* TABLE */
.tbl-wrap-outer{background:#fff;border-radius:14px;box-shadow:0 2px 14px rgba(0,0,0,.07);overflow:hidden;}
.tbl-scroll{overflow-x:auto;}
.at-tbl{width:100%;border-collapse:collapse;min-width:1350px;}
.at-tbl thead th{background:#1e40af;color:#fff;padding:13px 14px;font-size:13.5px;font-weight:700;white-space:nowrap;}
.at-tbl tbody td{padding:11px 14px;border-bottom:1px solid #f1f5f9;font-size:13.5px;color:#1e293b;vertical-align:middle;}
.at-tbl tbody tr:hover td{background:#eff6ff!important;}
.at-tbl tfoot td{padding:12px 14px;font-size:13.5px;color:#64748b;border-top:2px solid #e2e8f0;}
.row-new{background:#f0f7ff!important;}

/* BADGES */
.ref-badge{font-size:12.5px;font-weight:800;color:#1e40af;background:#eff6ff;padding:3px 9px;border-radius:6px;letter-spacing:.3px;display:inline-block;}
.new-tag{font-size:10.5px;background:#1e40af;color:#fff;padding:2px 7px;border-radius:5px;font-weight:700;display:inline-block;margin-top:3px;}
.aud-badge{padding:4px 10px;border-radius:20px;font-size:12px;font-weight:800;display:inline-block;}
.status-badge{padding:5px 12px;border-radius:20px;font-size:12px;font-weight:700;display:inline-block;white-space:nowrap;}
.fu-tag{background:#fef3c7;border:1.5px solid #fcd34d;border-radius:7px;padding:3px 9px;font-size:12px;font-weight:700;color:#92400e;display:inline-block;}
.fu-tag.urgent{background:#fef2f2;border-color:#fca5a5;color:#dc2626;}
.assign-ok{background:#f0fdf4;border:1.5px solid #86efac;color:#16a34a;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block;}
.assign-no{background:#fef2f2;border:1.5px solid #fecaca;color:#dc2626;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block;}

/* ACTION BUTTONS */
.ab{padding:5px 10px;border-radius:7px;font-size:12px;font-weight:700;text-decoration:none!important;border:1.5px solid transparent;cursor:pointer;display:inline-flex;align-items:center;gap:5px;margin:1px;transition:.15s;white-space:nowrap;line-height:1.3;}
.ab:hover{filter:brightness(.85);}
.ab-view  {background:#eff6ff;color:#1e40af;border-color:#bfdbfe;}
.ab-assign{background:#fffbeb;color:#d97706;border-color:#fcd34d;}
.ab-note  {background:#f0fdf4;color:#16a34a;border-color:#86efac;}
.ab-pdf   {background:#f8fafc;color:#334155;border-color:#e2e8f0;}
.ab-del   {background:#fef2f2;color:#dc2626;border-color:#fecaca;}

/* DETAIL PANEL */
.dp-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.55);z-index:9990;display:none;}
.dp-overlay.show{display:block;}
.dp-panel{position:fixed;top:0;right:-100%;width:100%;max-width:920px;height:100vh;background:#fff;z-index:9999;box-shadow:-8px 0 40px rgba(0,0,0,.18);transition:right .35s cubic-bezier(.4,0,.2,1);overflow-y:auto;display:flex;flex-direction:column;}
.dp-panel.open{right:0;}
.dp-head{background:linear-gradient(135deg,#1e40af,#1e3a8a);padding:20px 28px;color:#fff;display:flex;justify-content:space-between;align-items:flex-start;position:sticky;top:0;z-index:2;flex-shrink:0;}
.dp-head h2{font-size:1.1rem;font-weight:800;margin:0;}
.dp-head p{font-size:13px;margin:4px 0 0;opacity:.78;}
.dp-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:36px;height:36px;border-radius:50%;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:.15s;}
.dp-close:hover{background:rgba(255,255,255,.35);}
.dp-body{padding:22px 28px 50px;flex:1;}
.dp-section{margin-bottom:22px;}
.dp-section h4{font-size:14px;font-weight:800;color:#1e40af;border-bottom:2px solid #e2e8f0;padding-bottom:9px;margin-bottom:14px;display:flex;align-items:center;gap:8px;}
.dp-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;}
.dp-grid.g3{grid-template-columns:repeat(3,1fr);}
.dp-field label{font-size:10.5px;color:#94a3b8;font-weight:700;display:block;margin-bottom:3px;text-transform:uppercase;letter-spacing:.4px;}
.dp-field span{font-size:14px;font-weight:600;color:#1e293b;}
.dp-infobox{background:#f8fafc;border-radius:10px;border:2px solid #e2e8f0;padding:12px 15px;font-size:13.5px;color:#334155;line-height:1.7;white-space:pre-wrap;}
.route-viz{background:linear-gradient(135deg,#eff6ff,#f0fdf4);border:2px solid #bfdbfe;border-radius:12px;padding:14px 18px;display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin-bottom:14px;}
.route-city{font-size:15px;font-weight:900;color:#1e293b;}
.route-sub{font-size:12px;color:#64748b;font-weight:600;}
.route-arrow{font-size:24px;color:#1e40af;flex-shrink:0;}

/* Status quick change */
.sq-btns{display:flex;flex-wrap:wrap;gap:7px;margin-top:10px;}
.sq-btn{border:2px solid;border-radius:8px;padding:6px 14px;font-size:12.5px;font-weight:700;cursor:pointer;background:#fff;transition:.15s;display:inline-flex;align-items:center;gap:5px;}
.sq-btn.active{color:#fff!important;}

/* Assign */
.assign-select{flex:1;border:2px solid #e2e8f0;border-radius:8px;padding:0 12px;font-size:13.5px;height:42px;color:#1e293b;min-width:180px;}
.assign-select:focus{border-color:#1e40af;outline:none;}
.btn-do-assign{background:#d97706;color:#fff;border:none;border-radius:8px;padding:0 18px;height:42px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;transition:.15s;}
.btn-do-assign:hover{background:#b45309;}

/* Notes */
.dp-textarea{border:2px solid #e2e8f0;border-radius:10px;padding:10px 14px;font-size:13.5px;color:#1e293b;width:100%;min-height:80px;resize:vertical;}
.dp-textarea:focus{border-color:#1e40af;outline:none;box-shadow:0 0 0 3px rgba(30,64,175,.1);}
.btn-save-note{background:#16a34a;color:#fff;border:none;border-radius:8px;padding:9px 20px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;margin-top:10px;transition:.15s;}
.btn-save-note:hover{background:#15803d;}

/* Action strip */
.action-strip{display:flex;gap:9px;flex-wrap:wrap;padding-top:18px;border-top:2px solid #e2e8f0;}
.qs-btn{padding:10px 20px;border-radius:9px;font-weight:700;font-size:13.5px;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:7px;text-decoration:none!important;transition:.15s;white-space:nowrap;}
.qs-btn:hover{filter:brightness(.88);}
.qs-call{background:#16a34a;color:#fff!important;}
.qs-wa  {background:#25d366;color:#fff!important;}
.qs-mail{background:#1e40af;color:#fff!important;}
.qs-pdf {background:#0891b2;color:#fff!important;}

/* Email modal */
.modal-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.6);z-index:19990;display:none;align-items:center;justify-content:center;}
.modal-overlay.show{display:flex;}
.mail-box{background:#fff;border-radius:16px;padding:28px 30px;width:560px;max-width:95vw;box-shadow:0 20px 60px rgba(0,0,0,.25);}
.mail-box h4{font-size:16px;font-weight:800;color:#1e40af;margin-bottom:18px;display:flex;align-items:center;gap:9px;}
.mail-input{border:2px solid #e2e8f0;border-radius:9px;padding:9px 13px;font-size:13.5px;width:100%;margin-bottom:12px;}
.mail-input:focus{border-color:#1e40af;outline:none;}
.btn-send{background:#1e40af;color:#fff;border:none;border-radius:9px;padding:10px 26px;font-size:14px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;transition:.15s;}
.btn-send:hover{background:#1e3a8a;}
.btn-cancel{background:#f1f5f9;color:#64748b;border:2px solid #e2e8f0;border-radius:9px;padding:9px 18px;font-size:13.5px;font-weight:700;cursor:pointer;}

/* Toast */
.at-toast{position:fixed;bottom:24px;right:24px;padding:13px 22px;border-radius:12px;font-size:14px;font-weight:700;z-index:99999;display:none;align-items:center;gap:9px;box-shadow:0 8px 32px rgba(0,0,0,.25);min-width:220px;max-width:420px;animation:toastSlide .3s ease;}
.at-toast.show{display:flex;}
.at-toast.ok {background:#16a34a;color:#fff;}
.at-toast.err{background:#dc2626;color:#fff;}
.at-toast.inf{background:#1e40af;color:#fff;}
@keyframes toastSlide{from{transform:translateY(20px);opacity:0;}to{transform:translateY(0);opacity:1;}}

/* Audience type pill colors */
.at-customer{background:#eff6ff;color:#1e40af;border:1.5px solid #bfdbfe;}
.at-vendor  {background:#fffbeb;color:#d97706;border:1.5px solid #fcd34d;}
.at-general {background:#fdf4ff;color:#7c3aed;border:1.5px solid #e9d5ff;}

@media(max-width:768px){.at-wrap{padding:12px 10px 40px;}.dp-panel{max-width:100%;}.dp-grid,.dp-grid.g3{grid-template-columns:1fr;}.route-viz{flex-direction:column;gap:8px;}}
</style>
</head>
<body>
<div class="at-wrap">

<!-- HEADER -->
<div class="at-header">
    <h1>
        <i class="fas fa-headset"></i>
        Contact &amp; Sales Enquiries
        <small>All submissions from the Contact Us page</small>
    </h1>
    <div class="hdr-btns">
        <a href="?export=csv" class="btn-hdr"><i class="fas fa-file-csv"></i> Export CSV</a>
        <a href="abra_travels_custom_quote_list.php" class="btn-hdr"><i class="fas fa-envelope-open-text"></i> Quote Enquiries</a>
        
    </div>
</div>

<!-- STATS -->
<div class="row mb-3">
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-blue">
            <div class="stat-icon i-blue"><i class="fas fa-inbox"></i></div>
            <div><p class="stat-num"><?= $stats['total'] ?></p><p class="stat-lbl">Total</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-blue">
            <div class="stat-icon i-blue"><i class="fas fa-bell"></i></div>
            <div><p class="stat-num"><?= $stats['new'] ?></p><p class="stat-lbl">New / Unread</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-amber">
            <div class="stat-icon i-amber"><i class="fas fa-spinner"></i></div>
            <div><p class="stat-num"><?= $stats['in_progress'] ?></p><p class="stat-lbl">In Progress</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-green">
            <div class="stat-icon i-green"><i class="fas fa-circle-check"></i></div>
            <div><p class="stat-num"><?= $stats['confirmed'] ?></p><p class="stat-lbl">Confirmed</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-cyan">
            <div class="stat-icon i-cyan"><i class="fas fa-calendar-day"></i></div>
            <div><p class="stat-num"><?= $stats['today'] ?></p><p class="stat-lbl">Today</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-red">
            <div class="stat-icon i-red"><i class="fas fa-calendar-exclamation"></i></div>
            <div><p class="stat-num"><?= $stats['follow_up'] ?></p><p class="stat-lbl">Follow-up Today</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-blue">
            <div class="stat-icon i-blue"><i class="fas fa-user"></i></div>
            <div><p class="stat-num"><?= $stats['customers'] ?></p><p class="stat-lbl">Customers</p></div>
        </div>
    </div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3">
        <div class="stat-card s-amber">
            <div class="stat-icon i-amber"><i class="fas fa-truck-moving"></i></div>
            <div><p class="stat-num"><?= $stats['vendors'] ?></p><p class="stat-lbl">Vendors</p></div>
        </div>
    </div>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
    <div class="bar-title"><i class="fas fa-filter"></i> Filter Enquiries</div>
    <form method="GET" autocomplete="off">
        <div class="frow">
            <div class="fg" style="flex:2.2;">
                <label>Search (Name / Phone / Email / Location)</label>
                <input type="text" name="search" class="fc" placeholder="Search name, phone, email, city…" value="<?= htmlspecialchars($f_search) ?>">
            </div>
            <div class="fg">
                <label>Enquiry Type</label>
                <select name="audience" class="fc">
                    <option value="">All Types</option>
                    <option value="customer" <?=$f_aud==='customer'?'selected':''?>>👤 Customer Booking</option>
                    <option value="vendor"   <?=$f_aud==='vendor'  ?'selected':''?>>🚛 Vendor / Fleet</option>
                    <option value="general"  <?=$f_aud==='general' ?'selected':''?>>💬 General Enquiry</option>
                </select>
            </div>
            <div class="fg">
                <label>Status</label>
                <select name="status" class="fc">
                    <option value="">All Status</option>
                    <?php foreach ($STATUS as $k=>$v): ?>
                    <option value="<?=$k?>" <?=$f_status===$k?'selected':''?>><?=$v['label']?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="fg">
                <label>Assigned To</label>
                <select name="agent" class="fc">
                    <option value="">All Agents</option>
                    <option value="Unassigned" <?=$f_agent==='Unassigned'?'selected':''?>>⚠️ Unassigned</option>
                    <?php foreach ($employees as $e): ?>
                    <option value="<?=htmlspecialchars($e['name'])?>" <?=$f_agent===$e['name']?'selected':''?>><?=htmlspecialchars($e['name'])?></option>
                    <?php endforeach; ?>
                </select>
            </div>
        </div>
        <div class="frow">
            <div class="fg" style="max-width:180px;">
                <label>From Date</label>
                <input type="date" name="date_from" class="fc" value="<?=htmlspecialchars($f_df)?>">
            </div>
            <div class="fg" style="max-width:180px;">
                <label>To Date</label>
                <input type="date" name="date_to" class="fc" value="<?=htmlspecialchars($f_dt)?>">
            </div>
            <div class="fg" style="flex:3;"></div>
            <div style="display:flex;gap:8px;align-items:flex-end;">
                <a href="abra_travels_contact_sales.php" class="btn-reset"><i class="fas fa-rotate-left"></i> Reset</a>
                <button type="submit" class="btn-apply"><i class="fas fa-filter"></i> Apply</button>
            </div>
        </div>
    </form>
</div>

<!-- QUICK TABS -->
<div class="tab-pills">
    <?php
    $base_qs = http_build_query(array_filter(['search'=>$f_search,'audience'=>$f_aud,'agent'=>$f_agent,'date_from'=>$f_df,'date_to'=>$f_dt]));
    $total_all = acnt($con, "SELECT COUNT(*) c FROM contact_enquiries");
    ?>
    <a href="?<?=$base_qs?>" class="tab-pill <?=!$f_status?'active':''?>">All (<?=$total_all?>)</a>
    <?php foreach ($STATUS as $k=>$v):
        $tc = acnt($con, "SELECT COUNT(*) c FROM contact_enquiries WHERE status='$k'");
        if (!$tc) continue;
    ?>
    <a href="?status=<?=$k?><?=$base_qs?'&'.$base_qs:''?>"
       class="tab-pill <?=$f_status===$k?'active':''?>"
       style="<?=$f_status===$k?"border-color:{$v['color']};color:{$v['color']};background:{$v['bg']};":''?>">
        <?=$v['label']?> (<?=$tc?>)
    </a>
    <?php endforeach; ?>
</div>

<!-- TABLE -->
<div class="tbl-wrap-outer">
<div class="tbl-scroll">
<table class="at-tbl">
<thead>
<tr>
    <th style="min-width:90px;">Ref #</th>
    <th style="min-width:110px;">Type</th>
    <th style="min-width:210px;">Customer / Contact</th>
    <th style="min-width:190px;">Journey / Details</th>
    <th style="min-width:120px;">Vehicle / Fleet</th>
    <th style="min-width:110px;">Travel Date</th>
    <th style="min-width:170px;">Message</th>
    <th style="min-width:150px;">Assigned To</th>
    <th style="min-width:120px;">Status</th>
    <th style="min-width:100px;">Follow-up</th>
    <th style="min-width:120px;">Received On</th>
    <th style="min-width:240px;">Actions</th>
</tr>
</thead>
<tbody>
<?php
$row_count = 0;
if ($result): while ($row = mysqli_fetch_assoc($result)):
    $row_count++;
    $ref    = 'CE-' . str_pad($row['id'], 5, '0', STR_PAD_LEFT);
    $sc     = $STATUS[$row['status']] ?? $STATUS['new'];
    $ac     = $AUD_CFG[$row['audience_type']] ?? $AUD_CFG['general'];
    $is_new = $row['status'] === 'new';
    $fu     = $row['follow_up_date'] ?? null;
    $fu_today = $fu && $fu === date('Y-m-d');

    // Journey column content
    $journey = '';
    if ($row['audience_type'] === 'customer') {
        if ($row['pickup_location'])  $journey .= '<div><i class="fas fa-location-dot" style="color:#1e40af;width:12px;font-size:10px;"></i> ' . htmlspecialchars($row['pickup_location']) . '</div>';
        if ($row['dropoff_location']) $journey .= '<div style="margin-top:2px;"><i class="fas fa-flag-checkered" style="color:#16a34a;width:12px;font-size:10px;"></i> ' . htmlspecialchars($row['dropoff_location']) . '</div>';
    } elseif ($row['audience_type'] === 'vendor') {
        if ($row['vendor_city'])  $journey .= '<div><i class="fas fa-city" style="color:#d97706;width:12px;font-size:10px;"></i> ' . htmlspecialchars($row['vendor_city']) . '</div>';
        if ($row['fleet_size'])   $journey .= '<div style="margin-top:2px;font-size:12px;color:#64748b;"><i class="fas fa-truck-moving" style="width:12px;font-size:10px;"></i> ' . htmlspecialchars($row['fleet_size']) . '</div>';
    } else {
        if ($row['enquiry_topic']) $journey .= '<div style="font-size:12.5px;font-weight:600;color:#7c3aed;">' . htmlspecialchars($row['enquiry_topic']) . '</div>';
        if ($row['contact_pref'])  $journey .= '<div style="margin-top:2px;font-size:11.5px;color:#64748b;"><i class="fas fa-at" style="font-size:10px;"></i> ' . htmlspecialchars($row['contact_pref']) . '</div>';
    }

    // Vehicle / Fleet column
    $veh = '';
    if ($row['audience_type'] === 'customer') {
        $veh = htmlspecialchars($row['vehicle_type'] ?? '—');
        if ($row['trip_type']) $veh .= '<br><span style="font-size:11.5px;color:#64748b;">' . htmlspecialchars($row['trip_type']) . '</span>';
    } elseif ($row['audience_type'] === 'vendor') {
        $veh = htmlspecialchars($row['vendor_vehicle_type'] ?? '—');
        if ($row['years_in_business']) $veh .= '<br><span style="font-size:11.5px;color:#64748b;">' . htmlspecialchars($row['years_in_business']) . '</span>';
    } else {
        $veh = '<span style="color:#cbd5e1;">—</span>';
    }

    $msg_preview = mb_substr(strip_tags($row['message'] ?? ''), 0, 70);
    if (mb_strlen($row['message'] ?? '') > 70) $msg_preview .= '…';
?>
<tr class="<?=$is_new?'row-new':''?>">
    <td>
        <code class="ref-badge"><?=$ref?></code>
        <?php if ($is_new): ?><br><span class="new-tag">NEW</span><?php endif; ?>
    </td>
    <td>
        <span class="aud-badge at-<?=htmlspecialchars($row['audience_type']??'general')?>">
            <?=$ac['icon']?> <?=$ac['label']?>
        </span>
    </td>
    <td>
        <strong style="font-size:13.5px;"><?=htmlspecialchars($row['name']??'—')?></strong>
        <br><a href="tel:<?=htmlspecialchars($row['phone']??'')?>" style="color:#1e40af;font-size:13px;font-weight:700;text-decoration:none;">
            <i class="fas fa-phone" style="font-size:10px;"></i> <?=htmlspecialchars($row['phone']??'—')?>
        </a>
        <?php if (!empty($row['email'])): ?>
        <br><span style="color:#64748b;font-size:12px;"><i class="fas fa-envelope" style="font-size:10px;"></i> <?=htmlspecialchars($row['email'])?></span>
        <?php endif; ?>
        <?php if (!empty($row['company_name'])): ?>
        <br><span style="font-size:11.5px;color:#d97706;font-weight:700;"><i class="fas fa-building" style="font-size:10px;"></i> <?=htmlspecialchars($row['company_name'])?></span>
        <?php endif; ?>
    </td>
    <td style="font-size:13px;font-weight:600;"><?=$journey?:('—')?></td>
    <td style="font-size:13px;"><?=$veh?></td>
    <td style="font-size:13px;">
        <?=!empty($row['pickup_date'])?'<strong>'.date('d M Y',strtotime($row['pickup_date'])).'</strong>':'<span style="color:#cbd5e1;">—</span>'?>
    </td>
    <td style="font-size:12.5px;color:#475569;max-width:170px;"><?=htmlspecialchars($msg_preview)?:('<span style="color:#cbd5e1;">—</span>')?></td>
    <td>
        <?php if ($row['assigned_to']): ?>
        <span class="assign-ok"><i class="fas fa-user-check" style="font-size:10px;"></i> <?=htmlspecialchars($row['assigned_to'])?></span>
        <?php else: ?>
        <span class="assign-no"><i class="fas fa-user-xmark" style="font-size:10px;"></i> Unassigned</span>
        <?php endif; ?>
    </td>
    <td>
        <span class="status-badge" style="background:<?=$sc['bg']?>;color:<?=$sc['color']?>;border:1.5px solid <?=$sc['border']?>;">
            <?=$sc['label']?>
        </span>
    </td>
    <td>
        <?php if ($fu): ?>
        <span class="fu-tag <?=$fu_today?'urgent':''?>">
            <i class="fas fa-calendar<?=$fu_today?'-exclamation':''?>"></i>
            <?=date('d M',strtotime($fu))?>
        </span>
        <?php else: ?>—<?php endif; ?>
    </td>
    <td style="font-size:12.5px;color:#64748b;">
        <?=date('d M Y',strtotime($row['created_at']))?>
        <br><?=date('h:i A',strtotime($row['created_at']))?>
    </td>
    <td>
        <button class="ab ab-view"   onclick="openDP(<?=$row['id']?>)"><i class="fas fa-eye"></i> View</button>
        <button class="ab ab-assign" onclick="openDP(<?=$row['id']?>,true)"><i class="fas fa-user-tag"></i> Assign</button>
        <button class="ab ab-note"   onclick="openDP(<?=$row['id']?>,false,true)"><i class="fas fa-note-sticky"></i> Note</button>
        <button class="ab ab-pdf"    onclick="genPDF(<?=$row['id']?>)"><i class="fas fa-file-pdf"></i> PDF</button>
        <button class="ab ab-del"    onclick="delEnq(<?=$row['id']?>,'<?=addslashes($ref)?>')"><i class="fas fa-trash-alt"></i></button>
    </td>
</tr>
<?php endwhile; endif; ?>
<?php if ($row_count === 0): ?>
<tr><td colspan="12">
    <div style="text-align:center;padding:70px 20px;color:#94a3b8;">
        <i class="fas fa-inbox" style="font-size:52px;opacity:.25;display:block;margin-bottom:16px;"></i>
        <h4 style="font-size:17px;font-weight:800;color:#64748b;margin-bottom:8px;">No Enquiries Found</h4>
        <p style="font-size:14px;"><?=($f_search||$f_status||$f_aud)?'No results match your filters.':'No contact enquiries yet.'?></p>
        <?php if ($f_search||$f_status||$f_aud): ?>
        <a href="abra_travels_contact_sales.php" style="color:#1e40af;font-size:14px;font-weight:700;text-decoration:none;"><i class="fas fa-xmark-circle"></i> Clear Filters</a>
        <?php endif; ?>
    </div>
</td></tr>
<?php endif; ?>
</tbody>
<tfoot>
<tr>
    <td colspan="12">
        Showing <strong><?=$row_count?></strong> result<?=$row_count!=1?'s':''?>
        <?php if ($f_search||$f_status||$f_aud||$f_df): ?>
        &nbsp;|&nbsp;<a href="abra_travels_contact_sales.php" style="color:#1e40af;font-weight:700;text-decoration:none;"><i class="fas fa-xmark"></i> Clear filters</a>
        <?php endif; ?>
    </td>
</tr>
</tfoot>
</table>
</div>
</div>

</div><!-- /at-wrap -->

<!-- OVERLAY -->
<div class="dp-overlay" id="dpOv" onclick="closeDP()"></div>

<!-- DETAIL PANEL -->
<div class="dp-panel" id="dpPanel">
    <div class="dp-head">
        <div>
            <h2 id="dpTitle">Loading…</h2>
            <p  id="dpSub"></p>
        </div>
        <button class="dp-close" onclick="closeDP()"><i class="fas fa-xmark"></i></button>
    </div>
    <div class="dp-body" id="dpBody">
        <div style="text-align:center;padding:80px;color:#94a3b8;">
            <i class="fas fa-spinner fa-spin fa-3x"></i>
        </div>
    </div>
</div>

<!-- EMAIL MODAL -->
<div class="modal-overlay" id="mailOverlay">
    <div class="mail-box">
        <h4><i class="fas fa-envelope" style="color:#1e40af;"></i> Send Email to Customer</h4>
        <input type="hidden" id="mailId">
        <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">To</label>
        <input type="email" id="mailTo" class="mail-input" readonly style="background:#f8fafc;">
        <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">Subject</label>
        <input type="text" id="mailSubject" class="mail-input">
        <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">Personal Message (optional)</label>
        <textarea id="mailMsg" class="mail-input" rows="4" style="height:auto;min-height:95px;" placeholder="Add a personalized note…"></textarea>
        <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:6px;">
            <button class="btn-cancel" onclick="closeMailModal()">Cancel</button>
            <button class="btn-send" id="mailSendBtn" onclick="doSendMail()">
                <i class="fas fa-paper-plane"></i> Send Email
            </button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div class="at-toast" id="toast">
    <i class="fas fa-circle-check" id="toastIcon"></i>
    <span id="toastMsg"></span>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
var PAGE      = 'abra_travels_contact_sales.php';
var CREATOR_EMAIL = '<?= htmlspecialchars($creator_email) ?>';
var CREATOR_NAME  = '<?= htmlspecialchars($creator_name) ?>';
var STATUS_CFG = <?= json_encode($STATUS)   ?>;
var AUD_CFG    = <?= json_encode($AUD_CFG)  ?>;
var EMPLOYEES  = <?= json_encode($employees) ?>;

// TOAST
var _toastT;
function toast(msg, type) {
    type = type||'ok';
    var t = document.getElementById('toast');
    t.className = 'at-toast show ' + type;
    document.getElementById('toastMsg').textContent = msg;
    document.getElementById('toastIcon').className = type==='err'?'fas fa-circle-xmark':type==='inf'?'fas fa-circle-info':'fas fa-circle-check';
    clearTimeout(_toastT);
    _toastT = setTimeout(function(){ t.className = 'at-toast'; }, 4000);
}
function esc(s){ if(s==null)return''; return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }
function fmtD(d){ if(!d)return'—'; try{return new Date(d).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});}catch(e){return d;} }
function fmtDT(d){ if(!d)return'—'; try{return new Date(d).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'})+' '+new Date(d).toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit',hour12:true});}catch(e){return d;} }

function doPost(action, data) {
    return fetch(PAGE+'?ajax='+action, {
        method:'POST',
        headers:{'Content-Type':'application/x-www-form-urlencoded; charset=utf-8'},
        body: new URLSearchParams(data).toString()
    }).then(function(r){
        if(!r.ok) throw new Error('HTTP '+r.status+' — '+r.statusText);
        return r.text();
    }).then(function(txt){
        try{ return JSON.parse(txt); } catch(e){ throw new Error('Bad server response: '+txt.substring(0,100)); }
    });
}

function delEnq(id, ref) {
    if(!confirm('Delete enquiry '+ref+'?\nThis cannot be undone.')) return;
    doPost('delete',{id:id}).then(function(d){
        if(d.success){ toast('Deleted '+ref,'ok'); setTimeout(function(){location.reload();},1300); }
        else toast('Delete failed: '+(d.message||'error'),'err');
    }).catch(function(e){ toast(e.message,'err'); });
}

var _dpId = null;
function closeDP(){ document.getElementById('dpOv').classList.remove('show'); document.getElementById('dpPanel').classList.remove('open'); _dpId=null; }

function openDP(id, scrollAssign, scrollNote) {
    _dpId = id;
    document.getElementById('dpOv').classList.add('show');
    document.getElementById('dpPanel').classList.add('open');
    document.getElementById('dpBody').innerHTML = '<div style="text-align:center;padding:80px;color:#94a3b8;"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';
    fetch(PAGE+'?ajax=get_detail&id='+id)
        .then(function(r){ if(!r.ok) throw new Error('HTTP '+r.status); return r.text(); })
        .then(function(txt){
            var res; try{ res=JSON.parse(txt); }catch(e){ throw new Error('Bad server response'); }
            if(!res.success){ document.getElementById('dpBody').innerHTML='<div style="padding:40px;text-align:center;color:#dc2626;">'+esc(res.message||'Error loading')+'</div>'; return; }
            renderDP(res.data);
            if(scrollAssign) setTimeout(function(){ var el=document.getElementById('sec-assign'); if(el) el.scrollIntoView({behavior:'smooth',block:'center'}); },380);
            if(scrollNote)   setTimeout(function(){ var el=document.getElementById('sec-notes');  if(el) el.scrollIntoView({behavior:'smooth',block:'center'}); },380);
        })
        .catch(function(e){ document.getElementById('dpBody').innerHTML='<div style="padding:40px;text-align:center;color:#dc2626;">'+esc(e.message)+'</div>'; });
}

function renderDP(d) {
    var ref = 'CE-'+String(d.id).padStart(5,'0');
    var sc  = STATUS_CFG[d.status] || STATUS_CFG['new'];
    var ac  = AUD_CFG[d.audience_type] || AUD_CFG['general'];

    document.getElementById('dpTitle').textContent = d.name || 'Contact';
    document.getElementById('dpSub').textContent   = ref + '  ·  ' + ac.label + '  ·  ' + sc.label;

    var h = '';

    // STATUS QUICK CHANGE
    h += '<div class="dp-section"><h4><i class="fas fa-toggle-on"></i> Quick Status Update</h4>';
    h += '<div style="font-size:13px;color:#64748b;margin-bottom:9px;">Current: <strong style="color:'+sc.color+'">'+esc(sc.label)+'</strong></div>';
    h += '<div class="sq-btns">';
    Object.keys(STATUS_CFG).forEach(function(k){
        var s=STATUS_CFG[k], active=d.status===k;
        h += '<button class="sq-btn'+(active?' active':'')+'" style="border-color:'+s.color+';color:'+(active?'#fff':s.color)+';background:'+(active?s.color:s.bg)+';" onclick="qStatus('+d.id+',\''+k+'\',this)"><i class="fas '+(active?'fa-check-circle':'fa-circle-dot')+'"></i> '+esc(s.label)+'</button>';
    });
    h += '</div></div>';

    // CONTACT INFO
    h += '<div class="dp-section"><h4><i class="fas fa-user"></i> Contact Information</h4>';
    h += '<div class="dp-grid">';
    h += '<div class="dp-field"><label>Full Name</label><span>'+esc(d.name||'—')+'</span></div>';
    h += '<div class="dp-field"><label>Phone / WhatsApp</label><span><a href="tel:'+esc(d.phone||'')+'" style="color:#1e40af;font-weight:700;text-decoration:none;"><i class="fas fa-phone" style="font-size:11px;"></i> '+esc(d.phone||'—')+'</a></span></div>';
    h += '<div class="dp-field"><label>Email</label><span>'+(d.email?'<a href="mailto:'+esc(d.email)+'" style="color:#1e40af;text-decoration:none;">'+esc(d.email)+'</a>':'—')+'</span></div>';
    if (d.company_name) h += '<div class="dp-field"><label>Company</label><span>'+esc(d.company_name)+'</span></div>';
    h += '<div class="dp-field"><label>Enquiry Type</label><span><span class="aud-badge at-'+esc(d.audience_type||'general')+'">'+ac.icon+' '+ac.label+'</span></span></div>';
    h += '<div class="dp-field"><label>Reference</label><span><code class="ref-badge">'+ref+'</code></span></div>';
    h += '<div class="dp-field"><label>Source</label><span>'+esc(d.source_page||'contact.php')+'</span></div>';
    h += '<div class="dp-field"><label>Received</label><span>'+fmtDT(d.created_at)+'</span></div>';
    h += '</div></div>';

    // ENQUIRY DETAILS based on type
    if (d.audience_type === 'customer') {
        h += '<div class="dp-section"><h4><i class="fas fa-route"></i> Booking Details</h4>';
        if (d.pickup_location || d.dropoff_location) {
            h += '<div class="route-viz">';
            h += '<div><div class="route-city"><i class="fas fa-location-dot" style="color:#1e40af;font-size:13px;"></i> '+esc(d.pickup_location||'—')+'</div><div class="route-sub">Pickup</div></div>';
            h += '<div class="route-arrow"><i class="fas fa-arrow-right-long"></i></div>';
            h += '<div><div class="route-city" style="color:#1e40af;"><i class="fas fa-flag-checkered" style="color:#16a34a;font-size:13px;"></i> '+esc(d.dropoff_location||'—')+'</div><div class="route-sub">Drop-off</div></div>';
            h += '</div>';
        }
        h += '<div class="dp-grid">';
        h += '<div class="dp-field"><label>Vehicle Type</label><span>'+esc(d.vehicle_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Trip Type</label><span>'+esc(d.trip_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Pickup Date</label><span>'+fmtD(d.pickup_date)+'</span></div>';
        h += '</div></div>';
    } else if (d.audience_type === 'vendor') {
        h += '<div class="dp-section"><h4><i class="fas fa-truck-moving"></i> Vendor / Fleet Details</h4>';
        h += '<div class="dp-grid">';
        h += '<div class="dp-field"><label>Fleet Size</label><span>'+esc(d.fleet_size||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Vehicle Category</label><span>'+esc(d.vendor_vehicle_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>City / Region</label><span>'+esc(d.vendor_city||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Years in Business</label><span>'+esc(d.years_in_business||'—')+'</span></div>';
        h += '</div></div>';
    } else {
        h += '<div class="dp-section"><h4><i class="fas fa-comment-question"></i> Enquiry Details</h4>';
        h += '<div class="dp-grid">';
        h += '<div class="dp-field"><label>Topic</label><span>'+esc(d.enquiry_topic||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Preferred Contact</label><span>'+esc(d.contact_pref||'—')+'</span></div>';
        h += '</div></div>';
    }

    // MESSAGE
    if (d.message) {
        h += '<div class="dp-section"><h4><i class="fas fa-comment-lines"></i> Message</h4><div class="dp-infobox">'+esc(d.message)+'</div></div>';
    }

    // ASSIGN + TICKET
    h += '<div class="dp-section" id="sec-assign"><h4><i class="fas fa-user-tag"></i> Assign to Agent &amp; Raise Ticket</h4>';
    h += '<div style="font-size:13px;color:#64748b;margin-bottom:10px;">Currently: <strong style="color:#1e293b;">'+(d.assigned_to||'<span style="color:#dc2626;">Unassigned</span>')+'</strong></div>';
    h += '<div style="display:flex;gap:9px;align-items:center;flex-wrap:wrap;">';
    h += '<select id="dpAgentSel" class="assign-select"><option value="">-- Select Agent --</option>';
    EMPLOYEES.forEach(function(e){ h += '<option value="'+e.id+'" data-name="'+esc(e.name)+'" data-email="'+esc(e.email)+'" '+(d.assigned_to===e.name?'selected':'')+'>'+esc(e.name)+'</option>'; });
    h += '</select><button class="btn-do-assign" onclick="doAssign('+d.id+')"><i class="fas fa-user-check"></i> Assign &amp; Raise Ticket</button></div>';
    h += '<p style="font-size:12px;color:#94a3b8;margin-top:8px;"><i class="fas fa-circle-info"></i> Assigns the enquiry AND creates a support ticket automatically.</p></div>';

    // ADMIN NOTES — use data-notes attr to safely pass content; set textarea.value after render
    var fup_val = (d.follow_up_date && d.follow_up_date !== '0000-00-00') ? d.follow_up_date : '';
    h += '<div class="dp-section" id="sec-notes"><h4><i class="fas fa-sticky-note"></i> Admin Notes &amp; Follow-up</h4>';
    h += '<label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:5px;">Internal Notes</label>';
    h += '<textarea class="dp-textarea" id="dpNotes" placeholder="Add internal notes…"></textarea>';
    h += '<label style="font-size:12px;font-weight:700;color:#374151;display:block;margin:10px 0 5px;">Follow-up Date</label>';
    h += '<input type="date" id="dpFollowup" style="border:2px solid #e2e8f0;border-radius:9px;padding:8px 13px;font-size:14px;height:44px;color:#1e293b;width:auto;font-family:Poppins,sans-serif;" value="'+fup_val+'">';
    h += '<br><button class="btn-save-note" onclick="saveNotes('+d.id+')"><i class="fas fa-floppy-disk"></i> Save Notes &amp; Follow-up</button></div>';

    // TIMELINE
    h += '<div class="dp-section"><h4><i class="fas fa-clock-rotate-left"></i> Timeline</h4>';
    h += '<div style="background:#f8fafc;border:2px solid #e2e8f0;border-radius:11px;padding:14px 18px;font-size:13.5px;color:#64748b;">';
    h += '<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-paper-plane" style="color:#1e40af;width:18px;"></i> Enquiry Received</span><strong style="color:#1e293b;">'+fmtDT(d.created_at)+'</strong></div>';
    if (d.updated_at && d.updated_at!==d.created_at) h += '<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-pen-to-square" style="color:#d97706;width:18px;"></i> Last Updated</span><strong style="color:#1e293b;">'+fmtDT(d.updated_at)+'</strong></div>';
    if (d.follow_up_date) h += '<div style="display:flex;justify-content:space-between;padding:7px 0;"><span><i class="fas fa-calendar-check" style="color:#16a34a;width:18px;"></i> Follow-up Date</span><strong style="color:#16a34a;">'+fmtD(d.follow_up_date)+'</strong></div>';
    h += '</div></div>';

    // QUICK ACTIONS
    h += '<div class="action-strip">';
    h += '<a href="tel:'+esc(d.phone||'')+'" class="qs-btn qs-call"><i class="fas fa-phone"></i> Call</a>';
    h += '<a href="https://wa.me/'+esc((d.phone||'').replace(/[^0-9]/g,''))+'" target="_blank" class="qs-btn qs-wa"><i class="fab fa-whatsapp"></i> WhatsApp</a>';
    if (d.email) h += '<button onclick="openMailModal('+d.id+',\''+esc(d.email)+'\',\''+esc(d.name)+'\',\''+String(d.id).padStart(5,'0')+'\')" class="qs-btn qs-mail"><i class="fas fa-envelope"></i> Email</button>';
    h += '<button onclick="genPDF('+d.id+')" class="qs-btn qs-pdf"><i class="fas fa-file-pdf"></i> PDF</button>';
    h += '</div>';

    document.getElementById('dpBody').innerHTML = h;
    // Safely set textarea value AFTER render (avoids HTML entity issues)
    var notesEl = document.getElementById('dpNotes');
    if (notesEl) notesEl.value = d.admin_notes || '';
}

function qStatus(id, status, btn) {
    doPost('update_status',{id:id,status:status}).then(function(d){
        if(d.success){
            toast('Status → '+STATUS_CFG[status].label,'ok');
            document.querySelectorAll('.sq-btn').forEach(function(b){
                Object.keys(STATUS_CFG).forEach(function(k){
                    if(b.textContent.trim().indexOf(STATUS_CFG[k].label)>=0){
                        var isThis = k===status;
                        b.style.background = isThis ? STATUS_CFG[k].color : STATUS_CFG[k].bg;
                        b.style.color      = isThis ? '#fff' : STATUS_CFG[k].color;
                    }
                });
            });
            setTimeout(function(){ location.reload(); },2500);
        } else toast('Error: '+(d.message||'failed'),'err');
    }).catch(function(e){ toast('Error: '+e.message,'err'); });
}

function doAssign(id) {
    var sel=document.getElementById('dpAgentSel');
    var empId=sel.value;
    var empName=sel.options[sel.selectedIndex]?(sel.options[sel.selectedIndex].dataset.name||sel.options[sel.selectedIndex].text):'';
var empEmail=sel.options[sel.selectedIndex]?(sel.options[sel.selectedIndex].dataset.email||''):'';
if(!empId){ toast('Please select an agent first','err'); return; }
    var btn=document.querySelector('.btn-do-assign');
    btn.disabled=true; btn.innerHTML='<i class="fas fa-circle-notch fa-spin"></i> Processing…';
    doPost('assign_and_ticket',{id:id,employee_id:empId,employee_name:empName,employee_email:empEmail,creator_email:CREATOR_EMAIL,creator_name:CREATOR_NAME}).then(function(d){
        btn.disabled=false; btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket';
        if(d.success){ toast(d.message||'Assigned to '+empName+'!','ok'); setTimeout(function(){location.reload();},2200); }
        else toast('Error: '+(d.message||'Assignment failed'),'err');
    }).catch(function(e){ btn.disabled=false; btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket'; toast('Error: '+e.message,'err'); });
}

function saveNotes(id) {
    var notes=document.getElementById('dpNotes').value;
    var fdate=document.getElementById('dpFollowup').value;
    doPost('save_notes',{id:id,notes:notes,follow_up_date:fdate}).then(function(d){ toast(d.success?'Notes saved!':'Save failed','ok'); }).catch(function(e){ toast(e.message,'err'); });
}

function openMailModal(id, email, name, refPad) {
    document.getElementById('mailId').value     = id;
    document.getElementById('mailTo').value      = email;
    document.getElementById('mailSubject').value = 'Your Enquiry - CE-' + refPad + ' | Abra Tours & Travels';
    document.getElementById('mailMsg').value     = '';
    document.getElementById('mailOverlay').classList.add('show');
}
function closeMailModal(){ document.getElementById('mailOverlay').classList.remove('show'); }
function doSendMail() {
    var id=document.getElementById('mailId').value;
    var sub=document.getElementById('mailSubject').value.trim();
    var msg=document.getElementById('mailMsg').value;
    var btn=document.getElementById('mailSendBtn');
    if(!sub){ toast('Please enter a subject','err'); return; }
    btn.disabled=true; btn.innerHTML='<i class="fas fa-circle-notch fa-spin"></i> Sending…';
    doPost('send_email',{id:id,subject:sub,custom_message:msg}).then(function(d){
        btn.disabled=false; btn.innerHTML='<i class="fas fa-paper-plane"></i> Send Email';
        if(d.success){ toast(d.message||'Email sent!','ok'); closeMailModal(); }
        else toast('Email failed: '+(d.message||'Check mail config'),'err');
    }).catch(function(e){ btn.disabled=false; btn.innerHTML='<i class="fas fa-paper-plane"></i> Send Email'; toast('Error: '+e.message,'err'); });
}

// PDF GENERATOR
function genPDF(id) {
    toast('Preparing PDF…','inf');
    fetch(PAGE+'?ajax=get_detail&id='+id).then(function(r){return r.text();}).then(function(txt){
        var res=JSON.parse(txt);
        if(!res.success){ toast('Could not load data: '+res.message,'err'); return; }
        doPrint(res.data);
    }).catch(function(e){ toast('PDF error: '+e.message,'err'); });
}

function doPrint(d) {
    var ref = 'CE-'+String(d.id).padStart(5,'0');
    var sc  = STATUS_CFG[d.status]||STATUS_CFG['new'];
    var ac  = AUD_CFG[d.audience_type]||AUD_CFG['general'];
    var today = new Date().toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});

    var css = '<style>'
        +'body{font-family:Arial,sans-serif;margin:0;padding:0;color:#1e293b;font-size:13px;}'
        +'.page{max-width:800px;margin:0 auto;padding:24px;}'
        +'.logo-hdr{background:linear-gradient(135deg,#1e40af,#1e3a8a);padding:20px 28px;border-radius:12px;display:flex;align-items:center;gap:18px;margin-bottom:22px;}'
        +'.logo-hdr img{max-height:60px;}'
        +'.brand{color:#fff;} .brand h1{font-size:1.4rem;font-weight:900;margin:0;} .brand p{font-size:12px;margin:4px 0 0;opacity:.78;}'
        +'.gen-info{margin-left:auto;text-align:right;color:rgba(255,255,255,.8);font-size:12px;}'
        +'.ref-bar{display:flex;justify-content:space-between;align-items:center;background:#f8fafc;border:2px solid #e2e8f0;border-radius:10px;padding:12px 18px;margin-bottom:20px;}'
        +'.ref{font-size:1.15rem;font-weight:900;color:#1e40af;}'
        +'.s-badge{padding:5px 14px;border-radius:20px;font-size:12.5px;font-weight:700;display:inline-block;}'
        +'.sec{margin-bottom:20px;} .sec h3{font-size:13px;font-weight:800;color:#1e40af;border-bottom:2px solid #bfdbfe;padding-bottom:8px;margin-bottom:12px;}'
        +'.g2{display:grid;grid-template-columns:1fr 1fr;gap:10px;}'
        +'.fld label{font-size:10.5px;color:#94a3b8;font-weight:700;text-transform:uppercase;letter-spacing:.4px;display:block;margin-bottom:3px;}'
        +'.fld span{font-size:13.5px;font-weight:600;}'
        +'.route{background:linear-gradient(135deg,#eff6ff,#f0fdf4);border:2px solid #bfdbfe;border-radius:10px;padding:14px 18px;display:flex;align-items:center;gap:16px;margin-bottom:14px;}'
        +'.rc{font-size:15px;font-weight:900;} .rs{font-size:12px;color:#64748b;} .ra{font-size:20px;color:#1e40af;}'
        +'.note-box{background:#f8fafc;border:2px solid #e2e8f0;border-radius:9px;padding:12px 15px;font-size:13px;line-height:1.7;white-space:pre-wrap;}'
        +'.footer{text-align:center;font-size:11.5px;color:#94a3b8;border-top:2px solid #e2e8f0;padding-top:14px;margin-top:22px;}'
        +'@media print{.page{padding:12px;}}</style>';

    var body = '';
    body += '<div class="logo-hdr">';
    body += '<img src="https://abra-travels.com/images/logo.png" alt="Abra Tours" onerror="this.outerHTML=\'<div style=&quot;width:60px;height:60px;background:rgba(255,255,255,.15);border-radius:8px;&quot;></div>\'"/>';
       
    body += '<div class="gen-info"><div><strong>Contact Enquiry</strong></div><div style="font-size:11px;margin-top:2px;">Generated: '+today+'</div></div>';
    body += '</div>';
    body += '<div class="ref-bar"><div><div class="ref">'+esc(ref)+'</div><small style="font-size:12px;color:#64748b;">'+ac.icon+' '+ac.label+'</small></div>';
    body += '<span class="s-badge" style="background:'+sc.bg+';color:'+sc.color+';border:1.5px solid '+sc.border+';">'+esc(sc.label)+'</span></div>';
    // Contact info
    body += '<div class="sec"><h3>👤 Contact Information</h3><div class="g2">';
    body += '<div class="fld"><label>Full Name</label><span>'+esc(d.name||'—')+'</span></div>';
    body += '<div class="fld"><label>Mobile</label><span>'+esc(d.phone||'—')+'</span></div>';
    body += '<div class="fld"><label>Email</label><span>'+esc(d.email||'—')+'</span></div>';
    if (d.company_name) body += '<div class="fld"><label>Company</label><span>'+esc(d.company_name)+'</span></div>';
    body += '<div class="fld"><label>Received On</label><span>'+fmtDT(d.created_at)+'</span></div>';
    body += '<div class="fld"><label>Assigned To</label><span>'+esc(d.assigned_to||'Unassigned')+'</span></div>';
    body += '</div></div>';
    // Type-specific details
    if (d.audience_type === 'customer') {
        body += '<div class="sec"><h3>🚗 Booking Details</h3>';
        if (d.pickup_location || d.dropoff_location) {
            body += '<div class="route"><div><div class="rc">'+esc(d.pickup_location||'—')+'</div><div class="rs">Pickup</div></div><div class="ra">→</div><div><div class="rc" style="color:#1e40af;">'+esc(d.dropoff_location||'—')+'</div><div class="rs">Drop-off</div></div></div>';
        }
        body += '<div class="g2">';
        body += '<div class="fld"><label>Vehicle Type</label><span>'+esc(d.vehicle_type||'—')+'</span></div>';
        body += '<div class="fld"><label>Trip Type</label><span>'+esc(d.trip_type||'—')+'</span></div>';
        body += '<div class="fld"><label>Travel Date</label><span>'+fmtD(d.pickup_date)+'</span></div>';
        body += '</div></div>';
    } else if (d.audience_type === 'vendor') {
        body += '<div class="sec"><h3>🚛 Vendor Details</h3><div class="g2">';
        body += '<div class="fld"><label>Fleet Size</label><span>'+esc(d.fleet_size||'—')+'</span></div>';
        body += '<div class="fld"><label>Vehicle Type</label><span>'+esc(d.vendor_vehicle_type||'—')+'</span></div>';
        body += '<div class="fld"><label>City / Region</label><span>'+esc(d.vendor_city||'—')+'</span></div>';
        body += '<div class="fld"><label>Experience</label><span>'+esc(d.years_in_business||'—')+'</span></div>';
        body += '</div></div>';
    } else {
        body += '<div class="sec"><h3>💬 Enquiry Details</h3><div class="g2">';
        body += '<div class="fld"><label>Topic</label><span>'+esc(d.enquiry_topic||'—')+'</span></div>';
        body += '<div class="fld"><label>Preferred Contact</label><span>'+esc(d.contact_pref||'—')+'</span></div>';
        body += '</div></div>';
    }
    if (d.message) body += '<div class="sec"><h3>💬 Message</h3><div class="note-box">'+esc(d.message)+'</div></div>';
    if (d.admin_notes) { body += '<div class="sec"><h3>📝 Admin Notes</h3><div class="note-box">'+esc(d.admin_notes)+'</div>'; if(d.follow_up_date) body += '<div style="margin-top:8px;font-size:13px;"><strong>Follow-up:</strong> '+fmtD(d.follow_up_date)+'</div>'; body += '</div>'; }
    body += '<div class="sec"><h3>📊 Status</h3><div style="background:'+sc.bg+';border:2px solid '+sc.border+';border-radius:9px;padding:11px 16px;font-size:14px;color:'+sc.color+';font-weight:700;">'+esc(sc.label)+'</div></div>';
    body += '<div class="footer">Abra Tours &amp; Travels | abra-travels.com | Reference: '+esc(ref)+'</div>';

    // Build self-contained HTML and trigger download via Blob
    var html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Enquiry '+esc(ref)+'</title>'+css+'<style>@page{margin:15mm;size:A4;}</style></head><body><div class="page">'+body+'</div></body></html>';
var blob = new Blob([html], {type:'text/html'});
    var url  = URL.createObjectURL(blob);
    var printWin = window.open(url, '_blank');
    printWin.onload = function() {
        setTimeout(function() {
            printWin.print();
            setTimeout(function(){ URL.revokeObjectURL(url); }, 3000);
        }, 500);
    };
    toast('PDF print dialog opening…','inf');
}

document.addEventListener('keydown', function(e){ if(e.key==='Escape'){ closeDP(); closeMailModal(); } });
</script>
</body>
</html>