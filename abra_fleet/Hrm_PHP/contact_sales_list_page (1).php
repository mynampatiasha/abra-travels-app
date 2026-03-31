<?php
// ============================================================
// contact_sales_list_page.php
// ABRA TRAVELS — MANUAL LEADS (Internal Team CRM)
// Separate table: manual_leads
// Features: Add Lead, Assign, Ticket, Notes, Status, Filter, PDF, Delete
// ============================================================
ob_start();
error_reporting(E_ERROR | E_WARNING | E_PARSE);
if (session_status() == PHP_SESSION_NONE) { session_start(); }

require_once('database.php');
require_once('library.php');
require_once('funciones.php');
// isUser(); // Uncomment in production

// ── DB CONNECTION ─────────────────────────────────────────────────────────────
$con = null;
if (function_exists('conexion'))         $con = conexion();
elseif (isset($dbConn))                  $con = $dbConn;
elseif (function_exists('dbConnection')) $con = dbConnection();
if (!$con) { header('Content-Type: application/json'); echo json_encode(['success'=>false,'message'=>'DB connection failed']); exit; }
mysqli_set_charset($con, 'utf8mb4');

// ── HELPERS ───────────────────────────────────────────────────────────────────
function mq($con,$sql)    { return mysqli_query($con,$sql); }
function me($con)          { return mysqli_error($con); }
function mone($con,$sql)   { $r=mq($con,$sql); return ($r&&mysqli_num_rows($r)>0)?mysqli_fetch_assoc($r):null; }
function ms($con,$v)       { return mysqli_real_escape_string($con,trim((string)($v??''))); }
function mcnt($con,$sql)   { $r=mq($con,$sql); $row=$r?mysqli_fetch_assoc($r):null; return $row?(int)($row['c']??0):0; }

// ✅ CREATOR LOGIC — Get from URL parameter first, then session fallback
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';
$creator_name  = '';
$creator_email = '';
$created_by    = 1;

if(!empty($currentUserEmail)) {
    $email_safe  = ms($con, $currentUserEmail);
    $creator_row = mone($con, "SELECT id, name, email FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'active' LIMIT 1");
    if($creator_row) {
        $creator_name  = $creator_row['name'];
        $creator_email = $creator_row['email'];
        $created_by    = (int)$creator_row['id'];
    }
}

// ── AUTO-CREATE TABLE (manual_leads) ──────────────────────────────────────────
mq($con,"CREATE TABLE IF NOT EXISTS `manual_leads` (
    `id`                   int(11)      NOT NULL AUTO_INCREMENT,
    `ticket_ref`           varchar(30)  DEFAULT NULL COMMENT 'e.g. ML-00001',
    `audience_type`        varchar(30)  DEFAULT 'customer',
    `name`                 varchar(200) DEFAULT NULL,
    `email`                varchar(200) DEFAULT NULL,
    `phone`                varchar(50)  DEFAULT NULL,
    `company_name`         varchar(200) DEFAULT NULL,
    -- Customer fields
    `service_type`         varchar(150) DEFAULT NULL COMMENT 'Pickup & Drop, Airport Transfer etc.',
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
    `source_channel`       varchar(100) DEFAULT 'Manual - Internal',
    -- CRM fields
    `created_by_name`      varchar(200) DEFAULT NULL COMMENT 'Employee who created this lead',
    `created_by_id`        int(11)      DEFAULT NULL,
    `assigned_to`          varchar(200) DEFAULT NULL,
    `assigned_employee_id` int(11)      DEFAULT NULL,
    `status`               varchar(30)  DEFAULT 'new',
    `admin_notes`          text         DEFAULT NULL,
    `follow_up_date`       date         DEFAULT NULL,
    `ticket_number`        varchar(50)  DEFAULT NULL,
    `created_at`           datetime     DEFAULT CURRENT_TIMESTAMP,
    `updated_at`           datetime     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Manually created leads by internal team'");

// ── FETCH EMPLOYEES (same API as tickets) ─────────────────────────────────────
$employees = [];
$api_response = @file_get_contents('https://fleet.abra-travels.com/api/tickets/public-employees');
if ($api_response) {
    $api_data = json_decode($api_response, true);
    if ($api_data && $api_data['success']) {
        foreach ($api_data['data'] as $e) {
            $employees[] = [
                'id'   => (string)($e['_id']['$oid'] ?? $e['_id'] ?? ''),
                'name' => $e['name_parson'] ?? $e['username'] ?? 'Unknown'
            ];
        }
    }
}

// ── SERVICE TYPES LIST ────────────────────────────────────────────────────────
$SERVICE_TYPES = [
    'Pickup & Drop Service',
    'Bus / TT & Shuttle Service',
    'Airport Transfer',
    'Intercity / Outstation',
    'Long Term Rental',
    'Corporate Events',
    'Luxury & Premium Car Rental',
    'Domestic Tour Package',
    'International Tour Package',
    'National / Religious Tour',
    'Adventure Tour',
    'Custom Quote / Other',
];

// ── STATUS CONFIG ─────────────────────────────────────────────────────────────
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
    'customer' => ['icon'=>'👤','label'=>'Customer Booking','color'=>'#1e40af','bg'=>'#eff6ff','border'=>'#bfdbfe'],
    'vendor'   => ['icon'=>'🚛','label'=>'Vendor / Fleet',  'color'=>'#d97706','bg'=>'#fffbeb','border'=>'#fcd34d'],
    'general'  => ['icon'=>'💬','label'=>'General Enquiry', 'color'=>'#7c3aed','bg'=>'#fdf4ff','border'=>'#e9d5ff'],
];

// ── AJAX HANDLERS ─────────────────────────────────────────────────────────────
if (isset($_GET['ajax'])) {
    ob_clean();
    header('Content-Type: application/json; charset=utf-8');
    try {
        $id = (int)($_POST['id'] ?? $_GET['id'] ?? 0);

        // ── ADD LEAD ──────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'add_lead') {
            $aud       = ms($con,$_POST['audience_type']     ?? 'customer');
            $name      = ms($con,$_POST['name']              ?? '');
            $email     = ms($con,$_POST['email']             ?? '');
            $phone     = ms($con,$_POST['phone']             ?? '');
            $company   = ms($con,$_POST['company_name']      ?? '');
            $svc       = ms($con,$_POST['service_type']      ?? '');
            $veh       = ms($con,$_POST['vehicle_type']      ?? '');
            $trip      = ms($con,$_POST['trip_type']         ?? '');
            $pickup    = ms($con,$_POST['pickup_location']   ?? '');
            $dropoff   = ms($con,$_POST['dropoff_location']  ?? '');
            $pd_raw    = trim($_POST['pickup_date']          ?? '');
            $pd_sql    = (!empty($pd_raw)&&strtotime($pd_raw))?"'".ms($con,date('Y-m-d',strtotime($pd_raw)))."'":'NULL';
            $fsize     = ms($con,$_POST['fleet_size']        ?? '');
            $vveh      = ms($con,$_POST['vendor_vehicle_type']?? '');
            $vcity     = ms($con,$_POST['vendor_city']       ?? '');
            $yib       = ms($con,$_POST['years_in_business'] ?? '');
            $etopic    = ms($con,$_POST['enquiry_topic']     ?? '');
            $cpref     = ms($con,$_POST['contact_pref']      ?? '');
            $message   = ms($con,$_POST['message']           ?? '');
            $channel   = ms($con,$_POST['source_channel']    ?? 'Manual - Internal');
            $cb_name   = ms($con,$_POST['created_by_name']   ?? '');
            $cb_id_raw = (int)($_POST['created_by_id']       ?? 0);

            if (!$name) throw new Exception('Customer name is required');
            if (!$phone && !$email) throw new Exception('Phone or Email is required');

            // Resolve created_by_id from hr_employees if needed
            if (!$cb_id_raw && $cb_name) {
                $cbr = mone($con,"SELECT id FROM hr_employees WHERE name='$cb_name' LIMIT 1");
                if (!$cbr) $cbr = mone($con,"SELECT id FROM hr_employees WHERE name LIKE '%$cb_name%' LIMIT 1");
                $cb_id_raw = $cbr ? (int)$cbr['id'] : 1;
            }

            $sql = "INSERT INTO manual_leads (
                audience_type,name,email,phone,company_name,
                service_type,vehicle_type,trip_type,pickup_date,pickup_location,dropoff_location,
                fleet_size,vendor_vehicle_type,vendor_city,years_in_business,
                enquiry_topic,contact_pref,message,source_channel,
                created_by_name,created_by_id,status,created_at
            ) VALUES (
                '$aud','$name','$email','$phone','$company',
                '$svc','$veh','$trip',$pd_sql,'$pickup','$dropoff',
                '$fsize','$vveh','$vcity','$yib',
                '$etopic','$cpref','$message','$channel',
                '$cb_name',$cb_id_raw,'new',NOW()
            )";
            $ok = mq($con,$sql);
            if (!$ok) throw new Exception('DB insert failed: '.me($con));
            $new_id = (int)mysqli_insert_id($con);
            $ref = 'ML-'.str_pad($new_id,5,'0',STR_PAD_LEFT);
            mq($con,"UPDATE manual_leads SET ticket_ref='$ref' WHERE id=$new_id");
            echo json_encode(['success'=>true,'message'=>"Lead $ref created successfully",'id'=>$new_id,'ref'=>$ref]);
            exit;
        }

        // ── UPDATE STATUS ─────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'update_status') {
            if (!$id) throw new Exception('Missing ID');
            $status = ms($con,$_POST['status']??'');
            if (!array_key_exists($status,$GLOBALS['STATUS'])) throw new Exception('Invalid status');
            $ok = mq($con,"UPDATE manual_leads SET status='$status',updated_at=NOW() WHERE id=$id");
            if (!$ok) throw new Exception('DB update failed: '.me($con));
            echo json_encode(['success'=>true,'status'=>$status]);
            exit;
        }

        // ── ASSIGN + TICKET ───────────────────────────────────────────────────
        if ($_GET['ajax'] === 'assign_and_ticket') {
            if (!$id) throw new Exception('Missing lead ID');
            $emp_name_raw = trim($_POST['employee_name'] ?? '');
            $emp_name     = ms($con, $emp_name_raw);
            if (!$emp_name) throw new Exception('Please select an agent');

            // API IDs are MongoDB strings — resolve integer ID from hr_employees by name
            $emp_check = mone($con, "SELECT id,name FROM hr_employees WHERE name='$emp_name' LIMIT 1");
            if (!$emp_check) $emp_check = mone($con, "SELECT id,name FROM hr_employees WHERE name LIKE '%$emp_name%' LIMIT 1");
            if (!$emp_check) $emp_check = mone($con, "SELECT id,name FROM hr_employees ORDER BY id ASC LIMIT 1");
            $emp_id = $emp_check ? (int)$emp_check['id'] : 1;

            mq($con, "UPDATE manual_leads SET assigned_to='$emp_name',assigned_employee_id=$emp_id,updated_at=NOW() WHERE id=$id");

            $lead = mone($con, "SELECT * FROM manual_leads WHERE id=$id LIMIT 1");
            if (!$lead) throw new Exception('Lead not found');

            $ref = $lead['ticket_ref'] ?: 'ML-' . str_pad($id, 5, '0', STR_PAD_LEFT);

            // ✅ Use global creator variables with fallback to lead's created_by_id
            // First check if we have creator from URL parameter (already set at top)
            // If not, try to get from the lead's created_by_id field
            if(empty($currentUserEmail)) {
                $cb_id = (int)($lead['created_by_id'] ?? 0);
                if ($cb_id) {
                    $created_by = $cb_id;
                    $cb_check = mone($con, "SELECT name, email FROM hr_employees WHERE id=$cb_id LIMIT 1");
                    if ($cb_check) {
                        $creator_name  = $cb_check['name'];
                        $creator_email = $cb_check['email'];
                    }
                }
            }

            // ✅ CRITICAL FIX: Ensure creator_email is NEVER empty (backend requires it)
            if(empty($creator_email)) {
                $creator_email = 'crm@abra-travels.com';  // Default system email
                $creator_name  = $creator_name ?: 'CRM System';
            }

            $priority = 'medium';
            $timeline = 1440;
            $t_subject = "Manual Lead [$ref]" . ($lead['service_type'] ? " — {$lead['service_type']}" : '');

            $msg_parts = [
                "Lead Ref: $ref",
                "Source: " . ($lead['source_channel'] ?? 'Manual'),
                "Created By: " . ($lead['created_by_name'] ?? 'Internal'),
                "Customer: " . ($lead['name'] ?? ''),
                "Phone: " . ($lead['phone'] ?? ''),
                "Email: " . ($lead['email'] ?? ''),
                "Service: " . ($lead['service_type'] ?? ''),
                "Vehicle: " . ($lead['vehicle_type'] ?? ''),
                "Trip Type: " . ($lead['trip_type'] ?? ''),
                "Pickup: " . ($lead['pickup_location'] ?? ''),
                "Dropoff: " . ($lead['dropoff_location'] ?? ''),
                "Message: " . ($lead['message'] ?? ''),
            ];

            // Email comes directly from MongoDB API — no MySQL lookup needed
            $assigned_email_for_ticket = strtolower(trim($_POST['employee_email'] ?? ''));

            $ticket_payload = json_encode([
                'subject'        => $t_subject,
                'message'        => implode("\n", array_filter($msg_parts)),
                'priority'       => $priority,
                'timeline'       => $timeline,
                'assigned_name'  => $emp_name,
                'assigned_email' => $assigned_email_for_ticket,
                'creator_name'   => $creator_name,
                'creator_email'  => $creator_email,
            ]);

            $ch = curl_init('http://localhost:3001/api/tickets/internal/create');
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST           => true,
                CURLOPT_POSTFIELDS     => $ticket_payload,
                CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
                CURLOPT_TIMEOUT        => 10,
            ]);
            $response = curl_exec($ch);
            $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($http_code !== 200 && $http_code !== 201) {
                throw new Exception('Ticket creation failed. HTTP ' . $http_code . ': ' . $response);
            }

            $ticket_data = json_decode($response, true);
            $ticket_number = $ticket_data['ticket']['ticketNumber'] ?? 'UNKNOWN';

            mq($con, "UPDATE manual_leads SET ticket_number='$ticket_number',updated_at=NOW() WHERE id=$id");

            echo json_encode(['success' => true, 'ticket_number' => $ticket_number, 'message' => "Assigned to $emp_name. Ticket $ticket_number created."]);
            exit;
        }

        // ── SAVE NOTES ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'save_notes') {
            if (!$id) throw new Exception('Missing ID');
            $notes = ms($con,$_POST['notes']??'');
            $fdate = !empty($_POST['follow_up_date'])?"'".ms($con,$_POST['follow_up_date'])."'":'NULL';
            mq($con,"UPDATE manual_leads SET admin_notes='$notes',follow_up_date=$fdate,updated_at=NOW() WHERE id=$id");
            echo json_encode(['success'=>true,'message'=>'Notes saved']);
            exit;
        }

        // ── GET DETAIL ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'get_detail') {
            if (!$id) throw new Exception('Missing ID');
            $r   = mq($con,"SELECT * FROM manual_leads WHERE id=$id LIMIT 1");
            $row = ($r&&mysqli_num_rows($r)>0)?mysqli_fetch_assoc($r):null;
            if (!$row) throw new Exception('Lead #'.$id.' not found');
            echo json_encode(['success'=>true,'data'=>$row,'employees'=>$employees]);
            exit;
        }

        // ── SEND EMAIL ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'send_email') {
            if (!$id) throw new Exception('Missing ID');
            $c_subject = ms($con, $_POST['subject'] ?? '');
            $c_msg     = ms($con, $_POST['custom_message'] ?? '');
            if (empty($c_subject)) throw new Exception('Subject is required');

            $r = mq($con, "SELECT * FROM manual_leads WHERE id=$id LIMIT 1");
            $lead = ($r && mysqli_num_rows($r) > 0) ? mysqli_fetch_assoc($r) : null;
            if (!$lead) throw new Exception('Lead not found');

            $email = trim($lead['email'] ?? '');
            if (empty($email)) throw new Exception('No email address for this lead');

            $ref_id = $lead['ticket_ref'] ?: 'ML-' . str_pad($id, 5, '0', STR_PAD_LEFT);

            // Build branded HTML email
            $body = '<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:Arial,sans-serif;margin:0;padding:0;background:#f1f5f9;}.container{max-width:600px;margin:20px auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 12px rgba(0,0,0,.08);}.header{background:linear-gradient(135deg,#0f766e,#0d5c56);padding:24px 28px;text-align:center;}.header h1{color:#fff;font-size:1.5rem;font-weight:900;margin:0;}.content{padding:28px 32px;}.msg-box{background:#f8fafc;border-left:4px solid #0f766e;padding:14px 18px;margin:16px 0;font-size:14px;color:#334155;line-height:1.7;}.footer{background:#f8fafc;padding:16px;text-align:center;font-size:12px;color:#94a3b8;border-top:2px solid #e2e8f0;}</style></head><body><div class="container"><div class="header"><h1>Abra Tours &amp; Travels</h1></div><div class="content">';
            $body .= '<p style="font-size:15px;color:#1e293b;line-height:1.7;">Dear <strong>' . htmlspecialchars($lead['name'] ?? 'Valued Customer') . '</strong>,</p>';
            $body .= '<p style="font-size:14px;color:#475569;line-height:1.8;">Thank you for your interest in Abra Tours &amp; Travels.</p>';
            
            if (!empty($c_msg)) {
                $body .= '<div class="msg-box">' . nl2br(htmlspecialchars($c_msg)) . '</div>';
            }
            
            $body .= '<p style="font-size:14px;color:#475569;line-height:1.8;">Our team will contact you within <strong>30 minutes</strong> during business hours.</p>';
            $body .= '<div style="text-align:center;margin-top:22px;"><a href="https://wa.me/919686774946" style="background:linear-gradient(135deg,#1e40af,#1e3a8a);color:#fff;padding:12px 28px;border-radius:9px;text-decoration:none;font-size:14px;font-weight:700;display:inline-block;">💬 Chat on WhatsApp</a></div>';
            $body .= '</div>';
            $body .= '<div class="footer">Abra Tours &amp; Travels | <a href="https://abra-travels.com" style="color:#1e40af;text-decoration:none;">abra-travels.com</a> | <a href="tel:+919686774946" style="color:#1e40af;text-decoration:none;">+91 9686 774 946</a><br>Reference: ' . $ref_id . '</div></div></body></html>';

            // Send email using PHP mail()
            $headers  = "MIME-Version: 1.0\r\n";
            $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
            $headers .= "From: Abra Tours & Travels <info@abra-travels.com>\r\n";
            $headers .= "Reply-To: info@abra-travels.com\r\n";
            $headers .= "X-Mailer: PHP/" . phpversion() . "\r\n";
            
            $sent = mail($email, $c_subject, $body, $headers);
            if (!$sent) throw new Exception('Email delivery failed. Check server mail config.');
            
            echo json_encode(['success' => true, 'message' => "Email sent to $email"]);
            exit;
        }

        // ── DELETE ────────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'delete') {
            if (!$id) throw new Exception('Missing ID');
            mq($con,"DELETE FROM manual_leads WHERE id=$id");
            echo json_encode(['success'=>true]);
            exit;
        }

        throw new Exception('Unknown action: '.($_GET['ajax']??'none'));
    } catch (Throwable $e) {
        echo json_encode(['success'=>false,'message'=>$e->getMessage()]);
        exit;
    }
}

// ── CSV EXPORT ────────────────────────────────────────────────────────────────
if (isset($_GET['export']) && $_GET['export'] === 'csv') {
    ob_clean();
    $exp = mq($con,"SELECT id,ticket_ref,audience_type,name,phone,email,company_name,service_type,vehicle_type,trip_type,pickup_date,pickup_location,dropoff_location,fleet_size,vendor_vehicle_type,vendor_city,enquiry_topic,contact_pref,message,source_channel,created_by_name,assigned_to,status,ticket_number,follow_up_date,created_at FROM manual_leads ORDER BY created_at DESC");
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=manual_leads_'.date('Ymd_His').'.csv');
    $out = fopen('php://output','w');
    fprintf($out,chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($out,['Ref','ID','Type','Name','Phone','Email','Company','Service','Vehicle','Trip','Pickup Date','From','To','Fleet','V.Type','City','Topic','Pref','Message','Source','Created By','Assigned To','Status','Ticket #','Follow-up','Created']);
    if ($exp) while ($row=mysqli_fetch_assoc($exp)) fputcsv($out,array_values($row));
    fclose($out);
    exit;
}

// ── FILTERS ───────────────────────────────────────────────────────────────────
$f_status  = ms($con,$_GET['status']      ?? '');
$f_aud     = ms($con,$_GET['audience']    ?? '');
$f_search  = ms($con,$_GET['search']      ?? '');
$f_agent   = ms($con,$_GET['agent']       ?? '');
$f_svc     = ms($con,$_GET['service']     ?? '');
$f_creator = ms($con,$_GET['creator']     ?? '');
$f_channel = ms($con,$_GET['channel']     ?? '');
$f_df      = ms($con,$_GET['date_from']   ?? '');
$f_dt      = ms($con,$_GET['date_to']     ?? '');

$where = "WHERE 1=1";
if ($f_status)  $where .= " AND status='$f_status'";
if ($f_aud)     $where .= " AND audience_type='$f_aud'";
if ($f_search)  $where .= " AND (name LIKE '%$f_search%' OR phone LIKE '%$f_search%' OR email LIKE '%$f_search%' OR pickup_location LIKE '%$f_search%' OR dropoff_location LIKE '%$f_search%' OR vendor_city LIKE '%$f_search%' OR ticket_ref LIKE '%$f_search%')";
if ($f_agent)   $where .= " AND assigned_to='$f_agent'";
if ($f_svc)     $where .= " AND service_type='$f_svc'";
if ($f_creator) $where .= " AND created_by_name='$f_creator'";
if ($f_channel) $where .= " AND source_channel='$f_channel'";
if ($f_df)      $where .= " AND DATE(created_at)>='$f_df'";
if ($f_dt)      $where .= " AND DATE(created_at)<='$f_dt'";

// ── STATS ─────────────────────────────────────────────────────────────────────
$stats = [
    'total'       => mcnt($con,"SELECT COUNT(*) c FROM manual_leads"),
    'new'         => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE status='new'"),
    'in_progress' => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE status IN ('contacted','in_progress','quoted')"),
    'confirmed'   => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE status='confirmed'"),
    'today'       => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE DATE(created_at)=CURDATE()"),
    'follow_up'   => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE follow_up_date=CURDATE() AND status NOT IN ('confirmed','cancelled','closed')"),
    'unassigned'  => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE (assigned_to IS NULL OR assigned_to='') AND status NOT IN ('confirmed','cancelled','closed')"),
    'with_ticket' => mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE ticket_number IS NOT NULL AND ticket_number!=''"),
];

// Unique creators for filter dropdown
$creators_r = mq($con,"SELECT DISTINCT created_by_name FROM manual_leads WHERE created_by_name IS NOT NULL AND created_by_name!='' ORDER BY created_by_name ASC");
$creators = [];
if ($creators_r) while ($cr = mysqli_fetch_assoc($creators_r)) $creators[] = $cr['created_by_name'];

// Unique channels
$channels_r = mq($con,"SELECT DISTINCT source_channel FROM manual_leads WHERE source_channel IS NOT NULL AND source_channel!='' ORDER BY source_channel ASC");
$channels = [];
if ($channels_r) while ($ch = mysqli_fetch_assoc($channels_r)) $channels[] = $ch['source_channel'];

$result = mq($con,"SELECT * FROM manual_leads $where ORDER BY created_at DESC");
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Manual Leads | Abra Travels CRM</title>
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
.at-header{background:linear-gradient(135deg,#0f766e 0%,#0d9488 100%);border-radius:14px;padding:20px 28px;margin-bottom:22px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;box-shadow:0 6px 24px rgba(15,118,110,.3);}
.at-header h1{color:#fff;font-weight:800;font-size:1.35rem;margin:0;display:flex;align-items:center;gap:10px;}
.at-header h1 small{font-size:.75rem;font-weight:600;opacity:.75;display:block;margin-top:3px;}
.hdr-btns{display:flex;gap:10px;flex-wrap:wrap;}
.btn-hdr{background:rgba(255,255,255,.16);color:#fff!important;padding:9px 20px;border-radius:9px;text-decoration:none!important;font-weight:700;font-size:13.5px;display:inline-flex;align-items:center;gap:7px;border:1.5px solid rgba(255,255,255,.28);cursor:pointer;transition:.2s;white-space:nowrap;}
.btn-hdr:hover{background:rgba(255,255,255,.28);}
.btn-hdr-gold{background:#f59e0b;border-color:#f59e0b;color:#fff!important;}
.btn-hdr-gold:hover{background:#d97706;}

/* STAT CARDS */
.stat-card{background:#fff;border-radius:14px;padding:16px 20px;box-shadow:0 2px 14px rgba(0,0,0,.07);display:flex;align-items:center;gap:14px;border-left:5px solid transparent;transition:transform .2s;height:100%;}
.stat-card:hover{transform:translateY(-3px);box-shadow:0 6px 24px rgba(0,0,0,.12);}
.s-teal{border-left-color:#0f766e;}.s-blue{border-left-color:#1e40af;}.s-amber{border-left-color:#d97706;}.s-green{border-left-color:#16a34a;}.s-cyan{border-left-color:#0891b2;}.s-red{border-left-color:#dc2626;}.s-purple{border-left-color:#7c3aed;}
.stat-icon{width:50px;height:50px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;}
.i-teal{background:#f0fdfa;color:#0f766e;}.i-blue{background:#eff6ff;color:#1e40af;}.i-amber{background:#fffbeb;color:#d97706;}.i-green{background:#f0fdf4;color:#16a34a;}.i-cyan{background:#ecfeff;color:#0891b2;}.i-red{background:#fef2f2;color:#dc2626;}.i-purple{background:#fdf4ff;color:#7c3aed;}
.stat-num{font-size:28px;font-weight:900;color:#1e293b;margin:0;line-height:1;}
.stat-lbl{font-size:12px;color:#94a3b8;font-weight:600;margin:2px 0 0;}

/* FILTER BAR */
.filter-bar{background:#fff;border-radius:12px;box-shadow:0 1px 8px rgba(0,0,0,.07);padding:18px 22px;margin-bottom:16px;}
.filter-bar .bar-title{font-size:13.5px;font-weight:700;color:#0f766e;display:flex;align-items:center;gap:7px;margin-bottom:14px;}
.frow{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end;margin-bottom:10px;}
.frow:last-child{margin-bottom:0;}
.fg{display:flex;flex-direction:column;flex:1;min-width:140px;}
.fg label{font-size:11.5px;font-weight:700;color:#374151;margin-bottom:4px;}
.fc{border:1.5px solid #d1d5db;border-radius:8px;padding:0 12px;font-size:13.5px;height:40px;color:#111827;width:100%;background:#fff;transition:border-color .15s;-webkit-appearance:none;}
.fc:focus{border-color:#0f766e;outline:none;box-shadow:0 0 0 3px rgba(15,118,110,.1);}
.fc::placeholder{color:#9ca3af;}
.btn-apply{background:#0f766e;color:#fff;border:none;border-radius:8px;padding:0 22px;height:40px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;white-space:nowrap;transition:.15s;}
.btn-apply:hover{background:#0d5c56;}
.btn-reset{background:#f3f4f6;color:#6b7280;border:1.5px solid #d1d5db;border-radius:8px;padding:0 16px;height:40px;font-size:13.5px;font-weight:700;text-decoration:none;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;}
.btn-reset:hover{background:#e5e7eb;color:#374151;text-decoration:none;}

/* QUICK TABS */
.tab-pills{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;}
.tab-pill{background:#fff;border:2px solid #e2e8f0;color:#64748b;padding:6px 16px;border-radius:50px;font-size:13px;font-weight:700;text-decoration:none;transition:.15s;}
.tab-pill:hover{border-color:#0f766e;color:#0f766e;text-decoration:none;}
.tab-pill.active{border-color:#0f766e;color:#0f766e;background:#f0fdfa;}

/* TABLE */
.tbl-wrap-outer{background:#fff;border-radius:14px;box-shadow:0 2px 14px rgba(0,0,0,.07);overflow:hidden;}
.tbl-scroll{overflow-x:auto;}
.at-tbl{width:100%;border-collapse:collapse;min-width:1450px;}
.at-tbl thead th{background:#0f766e;color:#fff;padding:13px 14px;font-size:13.5px;font-weight:700;white-space:nowrap;}
.at-tbl tbody td{padding:11px 14px;border-bottom:1px solid #f1f5f9;font-size:13.5px;color:#1e293b;vertical-align:middle;}
.at-tbl tbody tr:hover td{background:#f0fdfa!important;}
.at-tbl tfoot td{padding:12px 14px;font-size:13.5px;color:#64748b;border-top:2px solid #e2e8f0;}
.row-new{background:#f0fdf4!important;}

/* BADGES */
.ref-badge{font-size:12.5px;font-weight:800;color:#0f766e;background:#f0fdfa;padding:3px 9px;border-radius:6px;letter-spacing:.3px;display:inline-block;border:1px solid #99f6e4;}
.new-tag{font-size:10.5px;background:#0f766e;color:#fff;padding:2px 7px;border-radius:5px;font-weight:700;display:inline-block;margin-top:3px;}
.aud-badge{padding:4px 10px;border-radius:20px;font-size:12px;font-weight:800;display:inline-block;}
.status-badge{padding:5px 12px;border-radius:20px;font-size:12px;font-weight:700;display:inline-block;white-space:nowrap;}
.creator-tag{background:#f0fdfa;border:1.5px solid #99f6e4;color:#0f766e;padding:3px 9px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block;}
.ticket-tag{background:#fdf4ff;border:1.5px solid #e9d5ff;color:#7c3aed;padding:3px 9px;border-radius:7px;font-size:11.5px;font-weight:700;display:inline-block;}
.fu-tag{background:#fef3c7;border:1.5px solid #fcd34d;border-radius:7px;padding:3px 9px;font-size:12px;font-weight:700;color:#92400e;display:inline-block;}
.fu-tag.urgent{background:#fef2f2;border-color:#fca5a5;color:#dc2626;}
.assign-ok{background:#f0fdf4;border:1.5px solid #86efac;color:#16a34a;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block;}
.assign-no{background:#fef2f2;border:1.5px solid #fecaca;color:#dc2626;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block;}

/* ACTION BUTTONS */
.ab{padding:5px 10px;border-radius:7px;font-size:12px;font-weight:700;text-decoration:none!important;border:1.5px solid transparent;cursor:pointer;display:inline-flex;align-items:center;gap:5px;margin:1px;transition:.15s;white-space:nowrap;line-height:1.3;}
.ab:hover{filter:brightness(.85);}
.ab-view  {background:#f0fdfa;color:#0f766e;border-color:#99f6e4;}
.ab-assign{background:#fffbeb;color:#d97706;border-color:#fcd34d;}
.ab-note  {background:#f0fdf4;color:#16a34a;border-color:#86efac;}
.ab-pdf   {background:#f8fafc;color:#334155;border-color:#e2e8f0;}
.ab-del   {background:#fef2f2;color:#dc2626;border-color:#fecaca;}

/* DETAIL PANEL */
.dp-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.55);z-index:9990;display:none;}
.dp-overlay.show{display:block;}
.dp-panel{position:fixed;top:0;right:-100%;width:100%;max-width:920px;height:100vh;background:#fff;z-index:9999;box-shadow:-8px 0 40px rgba(0,0,0,.18);transition:right .35s cubic-bezier(.4,0,.2,1);overflow-y:auto;display:flex;flex-direction:column;}
.dp-panel.open{right:0;}
.dp-head{background:linear-gradient(135deg,#0f766e,#0d5c56);padding:20px 28px;color:#fff;display:flex;justify-content:space-between;align-items:flex-start;position:sticky;top:0;z-index:2;flex-shrink:0;}
.dp-head h2{font-size:1.1rem;font-weight:800;margin:0;}
.dp-head p{font-size:13px;margin:4px 0 0;opacity:.78;}
.dp-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:36px;height:36px;border-radius:50%;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:.15s;}
.dp-close:hover{background:rgba(255,255,255,.35);}
.dp-body{padding:22px 28px 50px;flex:1;}
.dp-section{margin-bottom:22px;}
.dp-section h4{font-size:14px;font-weight:800;color:#0f766e;border-bottom:2px solid #e2e8f0;padding-bottom:9px;margin-bottom:14px;display:flex;align-items:center;gap:8px;}
.dp-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;}
.dp-grid.g3{grid-template-columns:repeat(3,1fr);}
.dp-field label{font-size:10.5px;color:#94a3b8;font-weight:700;display:block;margin-bottom:3px;text-transform:uppercase;letter-spacing:.4px;}
.dp-field span{font-size:14px;font-weight:600;color:#1e293b;}
.dp-infobox{background:#f8fafc;border-radius:10px;border:2px solid #e2e8f0;padding:12px 15px;font-size:13.5px;color:#334155;line-height:1.7;white-space:pre-wrap;}
.route-viz{background:linear-gradient(135deg,#f0fdfa,#f0fdf4);border:2px solid #99f6e4;border-radius:12px;padding:14px 18px;display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin-bottom:14px;}
.route-city{font-size:15px;font-weight:900;color:#1e293b;}
.route-sub{font-size:12px;color:#64748b;font-weight:600;}
.route-arrow{font-size:24px;color:#0f766e;flex-shrink:0;}
.sq-btns{display:flex;flex-wrap:wrap;gap:7px;margin-top:10px;}
.sq-btn{border:2px solid;border-radius:8px;padding:6px 14px;font-size:12.5px;font-weight:700;cursor:pointer;background:#fff;transition:.15s;display:inline-flex;align-items:center;gap:5px;}
.sq-btn.active{color:#fff!important;}
.assign-select{flex:1;border:2px solid #e2e8f0;border-radius:8px;padding:0 12px;font-size:13.5px;height:42px;color:#1e293b;min-width:180px;}
.assign-select:focus{border-color:#0f766e;outline:none;}
.btn-do-assign{background:#d97706;color:#fff;border:none;border-radius:8px;padding:0 18px;height:42px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;transition:.15s;}
.btn-do-assign:hover{background:#b45309;}
.dp-textarea{border:2px solid #e2e8f0;border-radius:10px;padding:10px 14px;font-size:13.5px;color:#1e293b;width:100%;min-height:80px;resize:vertical;}
.dp-textarea:focus{border-color:#0f766e;outline:none;box-shadow:0 0 0 3px rgba(15,118,110,.1);}
.btn-save-note{background:#16a34a;color:#fff;border:none;border-radius:8px;padding:9px 20px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;margin-top:10px;transition:.15s;}
.btn-save-note:hover{background:#15803d;}
.action-strip{display:flex;gap:9px;flex-wrap:wrap;padding-top:18px;border-top:2px solid #e2e8f0;}
.qs-btn{padding:10px 20px;border-radius:9px;font-weight:700;font-size:13.5px;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:7px;text-decoration:none!important;transition:.15s;white-space:nowrap;}
.qs-btn:hover{filter:brightness(.88);}
.qs-call{background:#16a34a;color:#fff!important;}
.qs-wa  {background:#25d366;color:#fff!important;}
.qs-pdf {background:#0891b2;color:#fff!important;}

/* ADD LEAD MODAL */
.modal-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.6);z-index:19990;display:none;align-items:flex-start;justify-content:center;overflow-y:auto;padding:30px 15px;}
.modal-overlay.show{display:flex;}
.lead-box{background:#fff;border-radius:16px;padding:0;width:720px;max-width:96vw;box-shadow:0 20px 60px rgba(0,0,0,.25);margin:auto;}
.lead-box-head{background:linear-gradient(135deg,#0f766e,#0d5c56);padding:22px 28px;border-radius:16px 16px 0 0;display:flex;justify-content:space-between;align-items:center;}
.lead-box-head h4{color:#fff;font-size:1.1rem;font-weight:800;margin:0;display:flex;align-items:center;gap:9px;}
.lead-box-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:34px;height:34px;border-radius:50%;cursor:pointer;font-size:15px;display:flex;align-items:center;justify-content:center;}
.lead-box-close:hover{background:rgba(255,255,255,.35);}
.lead-box-body{padding:24px 28px;}
.lead-box-foot{padding:16px 28px 22px;border-top:2px solid #f1f5f9;display:flex;gap:10px;justify-content:flex-end;}
.lf-row{display:grid;gap:14px;margin-bottom:14px;}
.lf-row.g2{grid-template-columns:1fr 1fr;}
.lf-row.g3{grid-template-columns:1fr 1fr 1fr;}
.lf-field label{font-size:11.5px;font-weight:700;color:#374151;display:block;margin-bottom:5px;text-transform:uppercase;letter-spacing:.04em;}
.lf-field input,.lf-field select,.lf-field textarea{width:100%;border:1.5px solid #d1d5db;border-radius:9px;padding:10px 13px;font-size:13.5px;color:#111827;outline:none;transition:border-color .15s;-webkit-appearance:none;appearance:none;font-family:'Poppins',sans-serif!important;}
.lf-field input:focus,.lf-field select:focus,.lf-field textarea:focus{border-color:#0f766e;box-shadow:0 0 0 3px rgba(15,118,110,.1);}
.lf-field textarea{min-height:90px;resize:vertical;}
.lf-field select{background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2394a3b8' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");background-repeat:no-repeat;background-position:right 12px center;padding-right:34px;}
.lf-section-title{font-size:12px;font-weight:800;color:#0f766e;text-transform:uppercase;letter-spacing:.07em;padding:10px 0 6px;border-bottom:2px solid #f0fdfa;margin-bottom:14px;display:flex;align-items:center;gap:7px;}
.lf-audience-tabs{display:flex;gap:8px;margin-bottom:18px;}
.lf-aud-btn{flex:1;padding:10px;border:2px solid #e2e8f0;border-radius:10px;background:#f8fafc;color:#64748b;font-size:13px;font-weight:700;cursor:pointer;text-align:center;transition:.15s;}
.lf-aud-btn:hover{border-color:#0f766e;color:#0f766e;}
.lf-aud-btn.on{border-color:#0f766e;background:#f0fdfa;color:#0f766e;}
.lf-panel{display:none;}
.lf-panel.on{display:block;}
.btn-submit-lead{background:#0f766e;color:#fff;border:none;border-radius:9px;padding:11px 28px;font-size:14px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;transition:.15s;}
.btn-submit-lead:hover{background:#0d5c56;}
.btn-cancel-lead{background:#f1f5f9;color:#64748b;border:2px solid #e2e8f0;border-radius:9px;padding:10px 20px;font-size:13.5px;font-weight:700;cursor:pointer;}

/* Toast */
.at-toast{position:fixed;bottom:24px;right:24px;padding:13px 22px;border-radius:12px;font-size:14px;font-weight:700;z-index:99999;display:none;align-items:center;gap:9px;box-shadow:0 8px 32px rgba(0,0,0,.25);min-width:220px;max-width:420px;animation:toastSlide .3s ease;}
.at-toast.show{display:flex;}
.at-toast.ok{background:#16a34a;color:#fff;}
.at-toast.err{background:#dc2626;color:#fff;}
.at-toast.inf{background:#0f766e;color:#fff;}
@keyframes toastSlide{from{transform:translateY(20px);opacity:0;}to{transform:translateY(0);opacity:1;}}

/* Audience badges */
.at-customer{background:#eff6ff;color:#1e40af;border:1.5px solid #bfdbfe;}
.at-vendor  {background:#fffbeb;color:#d97706;border:1.5px solid #fcd34d;}
.at-general {background:#fdf4ff;color:#7c3aed;border:1.5px solid #e9d5ff;}

@media(max-width:768px){.at-wrap{padding:12px 10px 40px;}.dp-panel{max-width:100%;}.dp-grid,.dp-grid.g3{grid-template-columns:1fr;}.lf-row.g2,.lf-row.g3{grid-template-columns:1fr;}}
</style>
</head>
<body>
<div class="at-wrap">

<!-- HEADER -->
<div class="at-header">
    <h1>
        <i class="fas fa-user-plus"></i>
        Manual Leads — Internal Team
        <small>Leads created by your internal team (separate from website enquiries)</small>
    </h1>
    <div class="hdr-btns">
        <button class="btn-hdr btn-hdr-gold" onclick="openAddLead()"><i class="fas fa-plus-circle"></i> Add New Lead</button>
        <a href="?export=csv" class="btn-hdr"><i class="fas fa-file-csv"></i> Export CSV</a>
        <a href="abra_travels_contact_sales.php" class="btn-hdr"><i class="fas fa-headset"></i> Website Enquiries</a>
        <!--<a href="index.php" class="btn-hdr"><i class="fas fa-arrow-left"></i> Dashboard</a>-->
    </div>
</div>

<!-- STATS -->
<div class="row mb-3">
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-teal"><div class="stat-icon i-teal"><i class="fas fa-layer-group"></i></div><div><p class="stat-num"><?=$stats['total']?></p><p class="stat-lbl">Total Leads</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-blue"><div class="stat-icon i-blue"><i class="fas fa-bell"></i></div><div><p class="stat-num"><?=$stats['new']?></p><p class="stat-lbl">New</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-amber"><div class="stat-icon i-amber"><i class="fas fa-spinner"></i></div><div><p class="stat-num"><?=$stats['in_progress']?></p><p class="stat-lbl">In Progress</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-green"><div class="stat-icon i-green"><i class="fas fa-circle-check"></i></div><div><p class="stat-num"><?=$stats['confirmed']?></p><p class="stat-lbl">Confirmed</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-cyan"><div class="stat-icon i-cyan"><i class="fas fa-calendar-day"></i></div><div><p class="stat-num"><?=$stats['today']?></p><p class="stat-lbl">Added Today</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-red"><div class="stat-icon i-red"><i class="fas fa-calendar-exclamation"></i></div><div><p class="stat-num"><?=$stats['follow_up']?></p><p class="stat-lbl">Follow-up Today</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-red"><div class="stat-icon i-red"><i class="fas fa-user-xmark"></i></div><div><p class="stat-num"><?=$stats['unassigned']?></p><p class="stat-lbl">Unassigned</p></div></div></div>
    <div class="col-6 col-sm-4 col-md-3 col-lg-2 mb-3"><div class="stat-card s-purple"><div class="stat-icon i-purple"><i class="fas fa-ticket"></i></div><div><p class="stat-num"><?=$stats['with_ticket']?></p><p class="stat-lbl">Tickets Raised</p></div></div></div>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
    <div class="bar-title"><i class="fas fa-filter"></i> Filter Leads</div>
    <form method="GET" autocomplete="off">
        <div class="frow">
            <div class="fg" style="flex:2.2;">
                <label>Search (Name / Phone / Email / Location / Ref)</label>
                <input type="text" name="search" class="fc" placeholder="Search name, phone, ref no…" value="<?=htmlspecialchars($f_search)?>">
            </div>
            <div class="fg">
                <label>Enquiry Type</label>
                <select name="audience" class="fc">
                    <option value="">All Types</option>
                    <option value="customer" <?=$f_aud==='customer'?'selected':''?>>👤 Customer</option>
                    <option value="vendor"   <?=$f_aud==='vendor'  ?'selected':''?>>🚛 Vendor</option>
                    <option value="general"  <?=$f_aud==='general' ?'selected':''?>>💬 General</option>
                </select>
            </div>
            <div class="fg">
                <label>Service Type</label>
                <select name="service" class="fc">
                    <option value="">All Services</option>
                    <?php foreach($SERVICE_TYPES as $st): ?>
                    <option value="<?=htmlspecialchars($st)?>" <?=$f_svc===$st?'selected':''?>><?=htmlspecialchars($st)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="fg">
                <label>Status</label>
                <select name="status" class="fc">
                    <option value="">All Status</option>
                    <?php foreach($STATUS as $k=>$v): ?>
                    <option value="<?=$k?>" <?=$f_status===$k?'selected':''?>><?=$v['label']?></option>
                    <?php endforeach; ?>
                </select>
            </div>
        </div>
        <div class="frow">
            <div class="fg">
                <label>Created By (Employee)</label>
                <select name="creator" class="fc">
                    <option value="">All Employees</option>
                    <?php foreach($creators as $cr): ?>
                    <option value="<?=htmlspecialchars($cr)?>" <?=$f_creator===$cr?'selected':''?>><?=htmlspecialchars($cr)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="fg">
                <label>Assigned To</label>
                <select name="agent" class="fc">
                    <option value="">All Agents</option>
                    <?php foreach($employees as $e): ?>
                    <option value="<?=htmlspecialchars($e['name'])?>" <?=$f_agent===$e['name']?'selected':''?>><?=htmlspecialchars($e['name'])?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="fg">
                <label>Source Channel</label>
                <select name="channel" class="fc">
                    <option value="">All Channels</option>
                    <?php foreach($channels as $ch): ?>
                    <option value="<?=htmlspecialchars($ch)?>" <?=$f_channel===$ch?'selected':''?>><?=htmlspecialchars($ch)?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="fg" style="max-width:170px;"><label>From Date</label><input type="date" name="date_from" class="fc" value="<?=htmlspecialchars($f_df)?>"></div>
            <div class="fg" style="max-width:170px;"><label>To Date</label><input type="date" name="date_to" class="fc" value="<?=htmlspecialchars($f_dt)?>"></div>
            <div style="display:flex;gap:8px;align-items:flex-end;">
                <a href="contact_sales_list_page.php" class="btn-reset"><i class="fas fa-rotate-left"></i> Reset</a>
                <button type="submit" class="btn-apply"><i class="fas fa-filter"></i> Apply</button>
            </div>
        </div>
    </form>
</div>

<!-- QUICK STATUS TABS -->
<div class="tab-pills">
    <?php
    $base_qs = http_build_query(array_filter(['search'=>$f_search,'audience'=>$f_aud,'agent'=>$f_agent,'service'=>$f_svc,'creator'=>$f_creator,'channel'=>$f_channel,'date_from'=>$f_df,'date_to'=>$f_dt]));
    $total_all = mcnt($con,"SELECT COUNT(*) c FROM manual_leads");
    ?>
    <a href="?<?=$base_qs?>" class="tab-pill <?=!$f_status?'active':''?>">All (<?=$total_all?>)</a>
    <?php foreach($STATUS as $k=>$v):
        $tc = mcnt($con,"SELECT COUNT(*) c FROM manual_leads WHERE status='$k'");
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
    <th style="min-width:160px;">Service</th>
    <th style="min-width:190px;">Journey / Details</th>
    <th style="min-width:120px;">Vehicle</th>
    <th style="min-width:110px;">Travel Date</th>
    <th style="min-width:150px;">Created By</th>
    <th style="min-width:150px;">Assigned To</th>
    <th style="min-width:130px;">Ticket #</th>
    <th style="min-width:120px;">Status</th>
    <th style="min-width:100px;">Follow-up</th>
    <th style="min-width:120px;">Added On</th>
    <th style="min-width:240px;">Actions</th>
</tr>
</thead>
<tbody>
<?php
$row_count = 0;
if ($result): while ($row = mysqli_fetch_assoc($result)):
    $row_count++;
    $ref = $row['ticket_ref'] ?: 'ML-'.str_pad($row['id'],5,'0',STR_PAD_LEFT);
    $sc  = $STATUS[$row['status']] ?? $STATUS['new'];
    $ac  = $AUD_CFG[$row['audience_type']] ?? $AUD_CFG['general'];
    $is_new = $row['status'] === 'new';
    $fu  = $row['follow_up_date'] ?? null;
    $fu_today = $fu && $fu === date('Y-m-d');

    $journey = '';
    if ($row['audience_type'] === 'customer') {
        if ($row['pickup_location'])  $journey .= '<div><i class="fas fa-location-dot" style="color:#0f766e;width:12px;font-size:10px;"></i> '.htmlspecialchars($row['pickup_location']).'</div>';
        if ($row['dropoff_location']) $journey .= '<div style="margin-top:2px;"><i class="fas fa-flag-checkered" style="color:#16a34a;width:12px;font-size:10px;"></i> '.htmlspecialchars($row['dropoff_location']).'</div>';
    } elseif ($row['audience_type'] === 'vendor') {
        if ($row['vendor_city'])  $journey .= '<div><i class="fas fa-city" style="color:#d97706;width:12px;font-size:10px;"></i> '.htmlspecialchars($row['vendor_city']).'</div>';
        if ($row['fleet_size'])   $journey .= '<div style="margin-top:2px;font-size:12px;color:#64748b;"><i class="fas fa-truck-moving" style="width:12px;font-size:10px;"></i> '.htmlspecialchars($row['fleet_size']).'</div>';
    } else {
        if ($row['enquiry_topic']) $journey .= '<div style="font-size:12.5px;font-weight:600;color:#7c3aed;">'.htmlspecialchars($row['enquiry_topic']).'</div>';
    }
?>
<tr class="<?=$is_new?'row-new':''?>">
    <td>
        <code class="ref-badge"><?=$ref?></code>
        <?php if ($is_new): ?><br><span class="new-tag">NEW</span><?php endif; ?>
    </td>
    <td><span class="aud-badge at-<?=htmlspecialchars($row['audience_type']??'general')?>"><?=$ac['icon']?> <?=$ac['label']?></span></td>
    <td>
        <strong style="font-size:13.5px;"><?=htmlspecialchars($row['name']??'—')?></strong>
        <br><a href="tel:<?=htmlspecialchars($row['phone']??'')?>" style="color:#0f766e;font-size:13px;font-weight:700;text-decoration:none;"><i class="fas fa-phone" style="font-size:10px;"></i> <?=htmlspecialchars($row['phone']??'—')?></a>
        <?php if (!empty($row['email'])): ?><br><span style="color:#64748b;font-size:12px;"><i class="fas fa-envelope" style="font-size:10px;"></i> <?=htmlspecialchars($row['email'])?></span><?php endif; ?>
        <?php if (!empty($row['company_name'])): ?><br><span style="font-size:11.5px;color:#d97706;font-weight:700;"><i class="fas fa-building" style="font-size:10px;"></i> <?=htmlspecialchars($row['company_name'])?></span><?php endif; ?>
    </td>
    <td style="font-size:12.5px;font-weight:600;color:#0f766e;"><?=htmlspecialchars($row['service_type']??'—')?><br><span style="font-size:11px;color:#94a3b8;"><?=htmlspecialchars($row['source_channel']??'')?></span></td>
    <td style="font-size:13px;font-weight:600;"><?=$journey?:'—'?></td>
    <td style="font-size:13px;"><?=htmlspecialchars($row['vehicle_type']??'—')?><?php if (!empty($row['trip_type'])): ?><br><span style="font-size:11.5px;color:#64748b;"><?=htmlspecialchars($row['trip_type'])?></span><?php endif; ?></td>
    <td style="font-size:13px;"><?=!empty($row['pickup_date'])?'<strong>'.date('d M Y',strtotime($row['pickup_date'])).'</strong>':'<span style="color:#cbd5e1;">—</span>'?></td>
    <td><?php if ($row['created_by_name']): ?><span class="creator-tag"><i class="fas fa-user-pen" style="font-size:10px;"></i> <?=htmlspecialchars($row['created_by_name'])?></span><?php else: ?><span style="color:#cbd5e1;font-size:12px;">—</span><?php endif; ?></td>
    <td><?php if ($row['assigned_to']): ?><span class="assign-ok"><i class="fas fa-user-check" style="font-size:10px;"></i> <?=htmlspecialchars($row['assigned_to'])?></span><?php else: ?><span class="assign-no"><i class="fas fa-user-xmark" style="font-size:10px;"></i> Unassigned</span><?php endif; ?></td>
    <td><?php if (!empty($row['ticket_number'])): ?><span class="ticket-tag"><i class="fas fa-ticket" style="font-size:10px;"></i> <?=htmlspecialchars($row['ticket_number'])?></span><?php else: ?><span style="color:#cbd5e1;font-size:12px;">No ticket</span><?php endif; ?></td>
    <td><span class="status-badge" style="background:<?=$sc['bg']?>;color:<?=$sc['color']?>;border:1.5px solid <?=$sc['border']?>;"><?=$sc['label']?></span></td>
    <td><?php if ($fu): ?><span class="fu-tag <?=$fu_today?'urgent':''?>"><i class="fas fa-calendar<?=$fu_today?'-exclamation':''?>"></i> <?=date('d M',strtotime($fu))?></span><?php else: ?>—<?php endif; ?></td>
    <td style="font-size:12.5px;color:#64748b;"><?=date('d M Y',strtotime($row['created_at']))?><br><?=date('h:i A',strtotime($row['created_at']))?></td>
    <td>
        <button class="ab ab-view"   onclick="openDP(<?=$row['id']?>)"><i class="fas fa-eye"></i> View</button>
        <button class="ab ab-assign" onclick="openDP(<?=$row['id']?>,true)"><i class="fas fa-user-tag"></i> Assign</button>
        <button class="ab ab-note"   onclick="openDP(<?=$row['id']?>,false,true)"><i class="fas fa-note-sticky"></i> Note</button>
        <button class="ab ab-pdf"    onclick="genPDF(<?=$row['id']?>)"><i class="fas fa-file-pdf"></i> PDF</button>
        <button class="ab ab-del"    onclick="delLead(<?=$row['id']?>,'<?=addslashes($ref)?>')"><i class="fas fa-trash-alt"></i></button>
    </td>
</tr>
<?php endwhile; endif; ?>
<?php if ($row_count===0): ?>
<tr><td colspan="14">
    <div style="text-align:center;padding:70px 20px;color:#94a3b8;">
        <i class="fas fa-layer-group" style="font-size:52px;opacity:.25;display:block;margin-bottom:16px;"></i>
        <h4 style="font-size:17px;font-weight:800;color:#64748b;margin-bottom:8px;">No Leads Found</h4>
        <p style="font-size:14px;"><?=($f_search||$f_status||$f_aud)?'No results match your filters. Try resetting.':'No manual leads yet. Click <strong>Add New Lead</strong> to create one.'?></p>
        <?php if ($f_search||$f_status||$f_aud): ?>
        <a href="contact_sales_list_page.php" style="color:#0f766e;font-size:14px;font-weight:700;text-decoration:none;"><i class="fas fa-xmark-circle"></i> Clear Filters</a>
        <?php else: ?>
        <button onclick="openAddLead()" style="background:#0f766e;color:#fff;border:none;border-radius:9px;padding:11px 24px;font-size:14px;font-weight:700;cursor:pointer;margin-top:12px;display:inline-flex;align-items:center;gap:8px;"><i class="fas fa-plus-circle"></i> Add New Lead</button>
        <?php endif; ?>
    </div>
</td></tr>
<?php endif; ?>
</tbody>
<tfoot>
<tr><td colspan="14">Showing <strong><?=$row_count?></strong> lead<?=$row_count!=1?'s':''?><?php if ($f_search||$f_status||$f_aud||$f_df): ?>&nbsp;|&nbsp;<a href="contact_sales_list_page.php" style="color:#0f766e;font-weight:700;text-decoration:none;"><i class="fas fa-xmark"></i> Clear filters</a><?php endif; ?></td></tr>
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
        <div><h2 id="dpTitle">Loading…</h2><p id="dpSub"></p></div>
        <button class="dp-close" onclick="closeDP()"><i class="fas fa-xmark"></i></button>
    </div>
    <div class="dp-body" id="dpBody"><div style="text-align:center;padding:80px;color:#94a3b8;"><i class="fas fa-spinner fa-spin fa-3x"></i></div></div>
</div>

<!-- ADD LEAD MODAL -->
<div class="modal-overlay" id="addLeadModal">
    <div class="lead-box">
        <div class="lead-box-head">
            <h4><i class="fas fa-user-plus"></i> Add New Lead</h4>
            <button class="lead-box-close" onclick="closeAddLead()"><i class="fas fa-xmark"></i></button>
        </div>
        <div class="lead-box-body">
            <!-- AUDIENCE TYPE TABS -->
            <div class="lf-section-title"><i class="fas fa-tag"></i> Lead Type</div>
            <div class="lf-audience-tabs">
                <button type="button" class="lf-aud-btn on" id="lf-tab-c" onclick="setLfAud('customer')">👤 Customer Booking</button>
                <button type="button" class="lf-aud-btn" id="lf-tab-v" onclick="setLfAud('vendor')">🚛 Vendor / Fleet</button>
                <button type="button" class="lf-aud-btn" id="lf-tab-g" onclick="setLfAud('general')">💬 General Enquiry</button>
            </div>
            <input type="hidden" id="lf_aud" value="customer">

            <!-- CREATED BY + SOURCE -->
            <div class="lf-section-title"><i class="fas fa-user-pen"></i> Created By</div>
            <div class="lf-row g2">
                <div class="lf-field">
                    <label>Employee (Who is creating this lead?) *</label>
                    <select id="lf_created_by_name">
                        <option value="" disabled selected>-- Select Employee --</option>
                        <?php foreach($employees as $e): ?>
                        <option value="<?=htmlspecialchars($e['name'])?>" data-id="<?=htmlspecialchars($e['id'])?>">
                            <?=htmlspecialchars($e['name'])?>
                        </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="lf-field">
                    <label>Source / Channel</label>
                    <select id="lf_source_channel">
                        <option value="Manual - Internal">Manual - Internal</option>
                        <option value="Manual - Phone Call">Manual - Phone Call</option>
                        <option value="Manual - WhatsApp">Manual - WhatsApp</option>
                        <option value="Manual - Walk-in">Manual - Walk-in</option>
                        <option value="Manual - Referral">Manual - Referral</option>
                        <option value="Manual - Social Media">Manual - Social Media</option>
                        <option value="Manual - Email">Manual - Email</option>
                    </select>
                </div>
            </div>

            <!-- CUSTOMER INFO -->
            <div class="lf-section-title"><i class="fas fa-user"></i> Customer Information</div>
            <div class="lf-row g3">
                <div class="lf-field"><label>Full Name *</label><input type="text" id="lf_name" placeholder="Customer name"></div>
                <div class="lf-field"><label>Phone / WhatsApp *</label><input type="text" id="lf_phone" placeholder="+91 XXXXX XXXXX"></div>
                <div class="lf-field"><label>Email</label><input type="email" id="lf_email" placeholder="customer@email.com"></div>
            </div>
            <div class="lf-row">
                <div class="lf-field"><label>Company / Business Name</label><input type="text" id="lf_company" placeholder="Optional — company or org name"></div>
            </div>

            <!-- CUSTOMER PANEL -->
            <div class="lf-panel on" id="lf-panel-c">
                <div class="lf-section-title"><i class="fas fa-car"></i> Booking Details</div>
                <div class="lf-row g2">
                    <div class="lf-field">
                        <label>Service Type</label>
                        <select id="lf_service_type">
                            <option value="" disabled selected>Choose service</option>
                            <?php foreach($SERVICE_TYPES as $st): ?>
                            <option value="<?=htmlspecialchars($st)?>"><?=htmlspecialchars($st)?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <div class="lf-field">
                        <label>Vehicle Type</label>
                        <select id="lf_vehicle_type">
                            <option value="" disabled selected>Choose</option>
                            <option>Hatchback</option><option>Sedan</option><option>SUV</option>
                            <option>Tempo Traveller</option><option>Mini Bus</option><option>Large Bus</option><option>Luxury Car</option>
                        </select>
                    </div>
                </div>
                <div class="lf-row g3">
                    <div class="lf-field">
                        <label>Trip Type</label>
                        <select id="lf_trip_type">
                            <option value="" disabled selected>Choose</option>
                            <option>Single Trip</option><option>Return Trip</option><option>Airport Transfer</option><option>Multi-Day</option>
                        </select>
                    </div>
                    <div class="lf-field"><label>Pickup Date</label><input type="date" id="lf_pickup_date"></div>
                    <div class="lf-field"></div>
                </div>
                <div class="lf-row g2">
                    <div class="lf-field"><label>Pickup Location</label><input type="text" id="lf_pickup" placeholder="City, area, landmark…"></div>
                    <div class="lf-field"><label>Drop-off Location</label><input type="text" id="lf_dropoff" placeholder="Destination…"></div>
                </div>
            </div>

            <!-- VENDOR PANEL -->
            <div class="lf-panel" id="lf-panel-v">
                <div class="lf-section-title"><i class="fas fa-truck-moving"></i> Vendor / Fleet Details</div>
                <div class="lf-row g2">
                    <div class="lf-field"><label>Fleet Size</label><select id="lf_fleet_size"><option value="" disabled selected>Choose</option><option>1 Vehicle</option><option>2–5 Vehicles</option><option>6–15 Vehicles</option><option>16+ Vehicles</option></select></div>
                    <div class="lf-field"><label>Vehicle Category</label><select id="lf_vveh"><option value="" disabled selected>Choose</option><option>Hatchback</option><option>Sedan</option><option>SUV / MUV</option><option>Tempo Traveller</option><option>Mini Bus</option><option>Large Bus</option><option>Mixed Fleet</option></select></div>
                </div>
                <div class="lf-row g2">
                    <div class="lf-field"><label>City / Region</label><input type="text" id="lf_vcity" placeholder="e.g. Bangalore, Mysore…"></div>
                    <div class="lf-field"><label>Years in Business</label><select id="lf_yib"><option value="" disabled selected>Choose</option><option>Just Starting</option><option>1–3 years</option><option>3–7 years</option><option>7+ years</option></select></div>
                </div>
            </div>

            <!-- GENERAL PANEL -->
            <div class="lf-panel" id="lf-panel-g">
                <div class="lf-section-title"><i class="fas fa-comment"></i> Enquiry Details</div>
                <div class="lf-row g2">
                    <div class="lf-field"><label>Enquiry Topic</label><select id="lf_etopic"><option value="" disabled selected>Choose a topic</option><option>Pricing &amp; Rates</option><option>Route Information</option><option>Booking Modification</option><option>Refund / Cancellation</option><option>Corporate Account</option><option>Complaint / Feedback</option><option>Other</option></select></div>
                    <div class="lf-field"><label>Preferred Contact</label><select id="lf_cpref"><option value="" disabled selected>Choose</option><option>Phone Call</option><option>WhatsApp</option><option>Email</option></select></div>
                </div>
            </div>

            <!-- MESSAGE -->
            <div class="lf-section-title" style="margin-top:4px;"><i class="fas fa-comment-lines"></i> Additional Notes / Message</div>
            <div class="lf-row">
                <div class="lf-field"><textarea id="lf_message" placeholder="Any special requirements, notes, or details about this lead…"></textarea></div>
            </div>
        </div>
        <div class="lead-box-foot">
            <button class="btn-cancel-lead" onclick="closeAddLead()">Cancel</button>
            <button class="btn-submit-lead" id="btnSubmitLead" onclick="submitLead()"><i class="fas fa-plus-circle"></i> Create Lead</button>
        </div>
    </div>
</div>

<!-- TOAST -->
<div class="at-toast" id="toast"><i class="fas fa-circle-check" id="toastIcon"></i><span id="toastMsg"></span></div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
var PAGE       = 'contact_sales_list_page.php';
var STATUS_CFG = <?=json_encode($STATUS)?>;
var AUD_CFG    = <?=json_encode($AUD_CFG)?>;
var EMPLOYEES  = <?=json_encode($employees)?>;

// TOAST
var _toastT;
function toast(msg, type) {
    type = type||'ok';
    var t = document.getElementById('toast');
    t.className = 'at-toast show '+type;
    document.getElementById('toastMsg').textContent = msg;
    document.getElementById('toastIcon').className = type==='err'?'fas fa-circle-xmark':type==='inf'?'fas fa-circle-info':'fas fa-circle-check';
    clearTimeout(_toastT);
    _toastT = setTimeout(function(){ t.className='at-toast'; }, 4500);
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
        try{ return JSON.parse(txt); } catch(e){ throw new Error('Bad server response: '+txt.substring(0,120)); }
    });
}

// ── ADD LEAD MODAL ──────────────────────────────────────────────────────────
function openAddLead(){ document.getElementById('addLeadModal').classList.add('show'); }
function closeAddLead(){ document.getElementById('addLeadModal').classList.remove('show'); }

var _lfAud = 'customer';
function setLfAud(t){
    _lfAud = t;
    document.getElementById('lf_aud').value = t;
    ['c','v','g'].forEach(function(x){ document.getElementById('lf-tab-'+x).classList.remove('on'); document.getElementById('lf-panel-'+x).classList.remove('on'); });
    document.getElementById('lf-tab-'+t[0]).classList.add('on');
    document.getElementById('lf-panel-'+t[0]).classList.add('on');
}

function gv(id){ return (document.getElementById(id)||{value:''}).value||''; }

function submitLead(){
    var name  = gv('lf_name').trim();
    var phone = gv('lf_phone').trim();
    var email = gv('lf_email').trim();
    var cb    = gv('lf_created_by_name').trim();
    if(!name){ toast('Please enter customer name','err'); return; }
    if(!phone && !email){ toast('Please enter phone or email','err'); return; }
    if(!cb){ toast('Please select the employee creating this lead','err'); return; }

    var cbSel = document.getElementById('lf_created_by_name');
    var cbId  = cbSel.options[cbSel.selectedIndex]?cbSel.options[cbSel.selectedIndex].dataset.id||'':'';

    var data = {
        audience_type:    _lfAud,
        name:             name,
        phone:            phone,
        email:            email,
        company_name:     gv('lf_company'),
        source_channel:   gv('lf_source_channel'),
        created_by_name:  cb,
        created_by_id:    cbId,
        message:          gv('lf_message'),
    };
    // Customer fields
    if (_lfAud === 'customer') {
        data.service_type     = gv('lf_service_type');
        data.vehicle_type     = gv('lf_vehicle_type');
        data.trip_type        = gv('lf_trip_type');
        data.pickup_date      = gv('lf_pickup_date');
        data.pickup_location  = gv('lf_pickup');
        data.dropoff_location = gv('lf_dropoff');
    } else if (_lfAud === 'vendor') {
        data.fleet_size           = gv('lf_fleet_size');
        data.vendor_vehicle_type  = gv('lf_vveh');
        data.vendor_city          = gv('lf_vcity');
        data.years_in_business    = gv('lf_yib');
    } else {
        data.enquiry_topic = gv('lf_etopic');
        data.contact_pref  = gv('lf_cpref');
    }

    var btn = document.getElementById('btnSubmitLead');
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-circle-notch fa-spin"></i> Creating…';

    doPost('add_lead', data).then(function(d){
        btn.disabled = false; btn.innerHTML = '<i class="fas fa-plus-circle"></i> Create Lead';
        if (d.success) {
            toast(d.message || 'Lead created!', 'ok');
            closeAddLead();
            setTimeout(function(){ location.reload(); }, 1800);
        } else {
            toast('Error: '+(d.message||'Failed to create lead'), 'err');
        }
    }).catch(function(e){
        btn.disabled = false; btn.innerHTML = '<i class="fas fa-plus-circle"></i> Create Lead';
        toast('Error: '+e.message, 'err');
    });
}

// ── DETAIL PANEL ────────────────────────────────────────────────────────────
var _dpId = null;
function closeDP(){ document.getElementById('dpOv').classList.remove('show'); document.getElementById('dpPanel').classList.remove('open'); _dpId=null; }

function openDP(id, scrollAssign, scrollNote){
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
    var ref = d.ticket_ref || 'ML-'+String(d.id).padStart(5,'0');
    var sc  = STATUS_CFG[d.status] || STATUS_CFG['new'];
    var ac  = AUD_CFG[d.audience_type] || AUD_CFG['general'];
    document.getElementById('dpTitle').textContent = d.name || 'Lead';
    document.getElementById('dpSub').textContent   = ref + '  ·  ' + ac.label + '  ·  ' + sc.label;
    var h = '';

    // STATUS QUICK CHANGE
    h += '<div class="dp-section"><h4><i class="fas fa-toggle-on"></i> Quick Status Update</h4>';
    h += '<div style="font-size:13px;color:#64748b;margin-bottom:9px;">Current: <strong style="color:'+sc.color+'">'+esc(sc.label)+'</strong></div>';
    h += '<div class="sq-btns">';
    Object.keys(STATUS_CFG).forEach(function(k){
        var s=STATUS_CFG[k], active=d.status===k;
        h+='<button class="sq-btn'+(active?' active':'')+'" style="border-color:'+s.color+';color:'+(active?'#fff':s.color)+';background:'+(active?s.color:s.bg)+';" onclick="qStatus('+d.id+',\''+k+'\',this)"><i class="fas '+(active?'fa-check-circle':'fa-circle-dot')+'"></i> '+esc(s.label)+'</button>';
    });
    h += '</div></div>';

    // LEAD INFO
    h += '<div class="dp-section"><h4><i class="fas fa-layer-group"></i> Lead Information</h4><div class="dp-grid">';
    h += '<div class="dp-field"><label>Reference</label><span><code class="ref-badge">'+ref+'</code></span></div>';
    h += '<div class="dp-field"><label>Lead Type</label><span><span class="aud-badge at-'+esc(d.audience_type||'general')+'">'+ac.icon+' '+ac.label+'</span></span></div>';
    h += '<div class="dp-field"><label>Service Type</label><span style="color:#0f766e;font-weight:700;">'+esc(d.service_type||'—')+'</span></div>';
    h += '<div class="dp-field"><label>Source Channel</label><span>'+esc(d.source_channel||'—')+'</span></div>';
    h += '<div class="dp-field"><label>Created By</label><span><span class="creator-tag"><i class="fas fa-user-pen" style="font-size:10px;"></i> '+esc(d.created_by_name||'—')+'</span></span></div>';
    h += '<div class="dp-field"><label>Created On</label><span>'+fmtDT(d.created_at)+'</span></div>';
    if (d.ticket_number) h += '<div class="dp-field"><label>Ticket #</label><span><span class="ticket-tag"><i class="fas fa-ticket" style="font-size:10px;"></i> '+esc(d.ticket_number)+'</span></span></div>';
    h += '</div></div>';

    // CONTACT INFO
    h += '<div class="dp-section"><h4><i class="fas fa-user"></i> Contact Information</h4><div class="dp-grid">';
    h += '<div class="dp-field"><label>Full Name</label><span>'+esc(d.name||'—')+'</span></div>';
    h += '<div class="dp-field"><label>Phone / WhatsApp</label><span><a href="tel:'+esc(d.phone||'')+'" style="color:#0f766e;font-weight:700;text-decoration:none;"><i class="fas fa-phone" style="font-size:11px;"></i> '+esc(d.phone||'—')+'</a></span></div>';
    h += '<div class="dp-field"><label>Email</label><span>'+(d.email?'<a href="mailto:'+esc(d.email)+'" style="color:#0f766e;text-decoration:none;">'+esc(d.email)+'</a>':'—')+'</span></div>';
    if (d.company_name) h += '<div class="dp-field"><label>Company</label><span>'+esc(d.company_name)+'</span></div>';
    h += '</div></div>';

    // TYPE-SPECIFIC DETAILS
    if (d.audience_type==='customer') {
        h += '<div class="dp-section"><h4><i class="fas fa-route"></i> Booking Details</h4>';
        if (d.pickup_location||d.dropoff_location) {
            h += '<div class="route-viz"><div><div class="route-city"><i class="fas fa-location-dot" style="color:#0f766e;font-size:13px;"></i> '+esc(d.pickup_location||'—')+'</div><div class="route-sub">Pickup</div></div>';
            h += '<div class="route-arrow"><i class="fas fa-arrow-right-long"></i></div>';
            h += '<div><div class="route-city" style="color:#0f766e;"><i class="fas fa-flag-checkered" style="color:#16a34a;font-size:13px;"></i> '+esc(d.dropoff_location||'—')+'</div><div class="route-sub">Drop-off</div></div></div>';
        }
        h += '<div class="dp-grid"><div class="dp-field"><label>Vehicle Type</label><span>'+esc(d.vehicle_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Trip Type</label><span>'+esc(d.trip_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Pickup Date</label><span>'+fmtD(d.pickup_date)+'</span></div></div></div>';
    } else if (d.audience_type==='vendor') {
        h += '<div class="dp-section"><h4><i class="fas fa-truck-moving"></i> Vendor / Fleet Details</h4><div class="dp-grid">';
        h += '<div class="dp-field"><label>Fleet Size</label><span>'+esc(d.fleet_size||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Vehicle Category</label><span>'+esc(d.vendor_vehicle_type||'—')+'</span></div>';
        h += '<div class="dp-field"><label>City / Region</label><span>'+esc(d.vendor_city||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Experience</label><span>'+esc(d.years_in_business||'—')+'</span></div>';
        h += '</div></div>';
    } else {
        h += '<div class="dp-section"><h4><i class="fas fa-comment-question"></i> Enquiry Details</h4><div class="dp-grid">';
        h += '<div class="dp-field"><label>Topic</label><span>'+esc(d.enquiry_topic||'—')+'</span></div>';
        h += '<div class="dp-field"><label>Preferred Contact</label><span>'+esc(d.contact_pref||'—')+'</span></div>';
        h += '</div></div>';
    }

    if (d.message) h += '<div class="dp-section"><h4><i class="fas fa-comment-lines"></i> Notes / Message</h4><div class="dp-infobox">'+esc(d.message)+'</div></div>';

    // ASSIGN + TICKET
    h += '<div class="dp-section" id="sec-assign"><h4><i class="fas fa-user-tag"></i> Assign to Agent &amp; Raise Ticket</h4>';
    h += '<div style="font-size:13px;color:#64748b;margin-bottom:10px;">Currently: <strong style="color:#1e293b;">'+(d.assigned_to||'<span style="color:#dc2626;">Unassigned</span>')+'</strong>';
    if (d.ticket_number) h += ' &nbsp;|&nbsp; Ticket: <span class="ticket-tag" style="font-size:11.5px;">'+esc(d.ticket_number)+'</span>';
    h += '</div><div style="display:flex;gap:9px;align-items:center;flex-wrap:wrap;">';
    h += '<select id="dpAgentSel" class="assign-select"><option value="">-- Select Agent --</option>';
    EMPLOYEES.forEach(function(e){ h += '<option value="'+e.id+'" data-name="'+esc(e.name)+'" data-email="'+esc(e.email)+'" '+(d.assigned_to===e.name?'selected':'')+'>'+esc(e.name)+'</option>'; });
    h += '</select><button class="btn-do-assign" onclick="doAssign('+d.id+')"><i class="fas fa-user-check"></i> Assign &amp; Raise Ticket</button></div>';
    h += '<p style="font-size:12px;color:#94a3b8;margin-top:8px;"><i class="fas fa-circle-info"></i> Assigns the lead AND creates a support ticket automatically.</p></div>';

    // NOTES + FOLLOW-UP
    var fup_val = (d.follow_up_date && d.follow_up_date!=='0000-00-00')?d.follow_up_date:'';
    h += '<div class="dp-section" id="sec-notes"><h4><i class="fas fa-sticky-note"></i> Admin Notes &amp; Follow-up</h4>';
    h += '<textarea class="dp-textarea" id="dpNotes" placeholder="Add internal notes…"></textarea>';
    h += '<label style="font-size:12px;font-weight:700;color:#374151;display:block;margin:10px 0 5px;">Follow-up Date</label>';
    h += '<input type="date" id="dpFollowup" style="border:2px solid #e2e8f0;border-radius:9px;padding:8px 13px;font-size:14px;height:44px;color:#1e293b;width:auto;font-family:Poppins,sans-serif;" value="'+fup_val+'">';
    h += '<br><button class="btn-save-note" onclick="saveNotes('+d.id+')"><i class="fas fa-floppy-disk"></i> Save Notes &amp; Follow-up</button></div>';

    // TIMELINE
    h += '<div class="dp-section"><h4><i class="fas fa-clock-rotate-left"></i> Timeline</h4>';
    h += '<div style="background:#f8fafc;border:2px solid #e2e8f0;border-radius:11px;padding:14px 18px;font-size:13.5px;color:#64748b;">';
    h += '<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-plus-circle" style="color:#0f766e;width:18px;"></i> Lead Created</span><strong style="color:#1e293b;">'+fmtDT(d.created_at)+'</strong></div>';
    if (d.updated_at&&d.updated_at!==d.created_at) h += '<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-pen-to-square" style="color:#d97706;width:18px;"></i> Last Updated</span><strong style="color:#1e293b;">'+fmtDT(d.updated_at)+'</strong></div>';
    if (d.follow_up_date) h += '<div style="display:flex;justify-content:space-between;padding:7px 0;"><span><i class="fas fa-calendar-check" style="color:#16a34a;width:18px;"></i> Follow-up Date</span><strong style="color:#16a34a;">'+fmtD(d.follow_up_date)+'</strong></div>';
    h += '</div></div>';

    // QUICK ACTIONS
    h += '<div class="action-strip">';
    h += '<a href="tel:'+esc(d.phone||'')+'" class="qs-btn qs-call"><i class="fas fa-phone"></i> Call</a>';
    h += '<a href="https://wa.me/'+esc((d.phone||'').replace(/[^0-9]/g,''))+'" target="_blank" class="qs-btn qs-wa"><i class="fab fa-whatsapp"></i> WhatsApp</a>';
    if (d.email) h += '<button onclick="openMailModal('+d.id+',\''+esc(d.email)+'\',\''+esc(d.name)+'\',\''+ref+'\')" class="qs-btn qs-mail"><i class="fas fa-envelope"></i> Email</button>';
    h += '<button onclick="genPDF('+d.id+')" class="qs-btn qs-pdf"><i class="fas fa-file-pdf"></i> PDF</button>';
    h += '</div>';

    document.getElementById('dpBody').innerHTML = h;
    var notesEl = document.getElementById('dpNotes');
    if (notesEl) notesEl.value = d.admin_notes||'';
}

function qStatus(id, status, btn) {
    doPost('update_status',{id:id,status:status}).then(function(d){
        if(d.success){ toast('Status → '+STATUS_CFG[status].label,'ok'); setTimeout(function(){ location.reload(); },2000); }
        else toast('Error: '+(d.message||'failed'),'err');
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
    doPost('assign_and_ticket',{id:id,employee_id:empId,employee_name:empName,employee_email:empEmail}).then(function(d){
        btn.disabled=false; btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket';
        if(d.success){ toast(d.message||'Assigned!','ok'); setTimeout(function(){location.reload();},2200); }
        else toast('Error: '+(d.message||'failed'),'err');
    }).catch(function(e){ btn.disabled=false; btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket'; toast('Error: '+e.message,'err'); });
}

function saveNotes(id) {
    var notes=document.getElementById('dpNotes').value;
    var fdate=document.getElementById('dpFollowup').value;
    doPost('save_notes',{id:id,notes:notes,follow_up_date:fdate}).then(function(d){ toast(d.success?'Notes saved!':'Save failed','ok'); }).catch(function(e){ toast(e.message,'err'); });
}

function delLead(id, ref) {
    if(!confirm('Delete lead '+ref+'?\nThis cannot be undone.')) return;
    doPost('delete',{id:id}).then(function(d){
        if(d.success){ toast('Deleted '+ref,'ok'); setTimeout(function(){ location.reload(); },1300); }
        else toast('Delete failed: '+(d.message||'error'),'err');
    }).catch(function(e){ toast(e.message,'err'); });
}

// PDF GENERATOR
function genPDF(id) {
    toast('Preparing PDF…','inf');
    fetch(PAGE+'?ajax=get_detail&id='+id).then(function(r){return r.text();}).then(function(txt){
        var res=JSON.parse(txt);
        if(!res.success){ toast('Could not load: '+res.message,'err'); return; }
        doPrint(res.data);
    }).catch(function(e){ toast('PDF error: '+e.message,'err'); });
}
function doPrint(d) {
    var ref = d.ticket_ref||'ML-'+String(d.id).padStart(5,'0');
    var sc  = STATUS_CFG[d.status]||STATUS_CFG['new'];
    var ac  = AUD_CFG[d.audience_type]||AUD_CFG['general'];
    var today = new Date().toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});
    var css='<style>body{font-family:Arial,sans-serif;margin:0;padding:0;color:#1e293b;font-size:13px;}.page{max-width:800px;margin:0 auto;padding:24px;}.hdr{background:linear-gradient(135deg,#0f766e,#0d5c56);padding:20px 28px;border-radius:12px;display:flex;align-items:center;gap:18px;margin-bottom:22px;}.brand{color:#fff;} .brand h1{font-size:1.4rem;font-weight:900;margin:0;} .brand p{font-size:12px;margin:4px 0 0;opacity:.78;}.gen-info{margin-left:auto;text-align:right;color:rgba(255,255,255,.8);font-size:12px;}.ref-bar{display:flex;justify-content:space-between;align-items:center;background:#f8fafc;border:2px solid #e2e8f0;border-radius:10px;padding:12px 18px;margin-bottom:20px;}.ref{font-size:1.15rem;font-weight:900;color:#0f766e;}.s-badge{padding:5px 14px;border-radius:20px;font-size:12.5px;font-weight:700;display:inline-block;}.sec{margin-bottom:20px;}.sec h3{font-size:13px;font-weight:800;color:#0f766e;border-bottom:2px solid #99f6e4;padding-bottom:8px;margin-bottom:12px;}.g2{display:grid;grid-template-columns:1fr 1fr;gap:10px;}.fld label{font-size:10.5px;color:#94a3b8;font-weight:700;text-transform:uppercase;letter-spacing:.4px;display:block;margin-bottom:3px;}.fld span{font-size:13.5px;font-weight:600;}.route{background:linear-gradient(135deg,#f0fdfa,#f0fdf4);border:2px solid #99f6e4;border-radius:10px;padding:14px 18px;display:flex;align-items:center;gap:16px;margin-bottom:14px;}.rc{font-size:15px;font-weight:900;}.rs{font-size:12px;color:#64748b;}.ra{font-size:20px;color:#0f766e;}.note-box{background:#f8fafc;border:2px solid #e2e8f0;border-radius:9px;padding:12px 15px;font-size:13px;line-height:1.7;white-space:pre-wrap;}.footer{text-align:center;font-size:11.5px;color:#94a3b8;border-top:2px solid #e2e8f0;padding-top:14px;margin-top:22px;}@media print{.page{padding:12px;}}</style>';
    var body='';
    body+='<div class="hdr"><div class="brand"><h1>Abra Tours &amp; Travels</h1><p>Manual Lead Report</p></div><div class="gen-info"><div><strong>Lead: '+esc(ref)+'</strong></div><div style="font-size:11px;margin-top:2px;">Generated: '+today+'</div></div></div>';
    body+='<div class="ref-bar"><div><div class="ref">'+esc(ref)+'</div><small style="font-size:12px;color:#64748b;">'+ac.icon+' '+ac.label+' · '+esc(d.service_type||'—')+'</small></div><span class="s-badge" style="background:'+sc.bg+';color:'+sc.color+';border:1.5px solid '+sc.border+';">'+esc(sc.label)+'</span></div>';
    body+='<div class="sec"><h3>👤 Contact Information</h3><div class="g2"><div class="fld"><label>Full Name</label><span>'+esc(d.name||'—')+'</span></div><div class="fld"><label>Mobile</label><span>'+esc(d.phone||'—')+'</span></div><div class="fld"><label>Email</label><span>'+esc(d.email||'—')+'</span></div><div class="fld"><label>Source Channel</label><span>'+esc(d.source_channel||'—')+'</span></div><div class="fld"><label>Created By</label><span>'+esc(d.created_by_name||'—')+'</span></div><div class="fld"><label>Assigned To</label><span>'+esc(d.assigned_to||'Unassigned')+'</span></div></div></div>';
    if (d.audience_type==='customer'){body+='<div class="sec"><h3>🚗 Booking Details</h3>';if(d.pickup_location||d.dropoff_location){body+='<div class="route"><div><div class="rc">'+esc(d.pickup_location||'—')+'</div><div class="rs">Pickup</div></div><div class="ra">→</div><div><div class="rc" style="color:#0f766e;">'+esc(d.dropoff_location||'—')+'</div><div class="rs">Drop-off</div></div></div>';}body+='<div class="g2"><div class="fld"><label>Vehicle</label><span>'+esc(d.vehicle_type||'—')+'</span></div><div class="fld"><label>Trip Type</label><span>'+esc(d.trip_type||'—')+'</span></div><div class="fld"><label>Travel Date</label><span>'+fmtD(d.pickup_date)+'</span></div></div></div>';}else if(d.audience_type==='vendor'){body+='<div class="sec"><h3>🚛 Vendor Details</h3><div class="g2"><div class="fld"><label>Fleet Size</label><span>'+esc(d.fleet_size||'—')+'</span></div><div class="fld"><label>Vehicle Type</label><span>'+esc(d.vendor_vehicle_type||'—')+'</span></div><div class="fld"><label>City</label><span>'+esc(d.vendor_city||'—')+'</span></div><div class="fld"><label>Experience</label><span>'+esc(d.years_in_business||'—')+'</span></div></div></div>';}
    if(d.message) body+='<div class="sec"><h3>💬 Notes / Message</h3><div class="note-box">'+esc(d.message)+'</div></div>';
    if(d.admin_notes){body+='<div class="sec"><h3>📝 Admin Notes</h3><div class="note-box">'+esc(d.admin_notes)+'</div>';if(d.follow_up_date) body+='<div style="margin-top:8px;font-size:13px;"><strong>Follow-up:</strong> '+fmtD(d.follow_up_date)+'</div>';body+='</div>';}
    body+='<div class="footer">Abra Tours &amp; Travels | abra-travels.com | Lead Ref: '+esc(ref)+'</div>';
    var html='<!DOCTYPE html><html><head><meta charset="utf-8"><title>Lead '+esc(ref)+'</title>'+css+'<style>@page{margin:15mm;size:A4;}</style></head><body><div class="page">'+body+'</div></body></html>';
    var blob=new Blob([html],{type:'text/html'});
    var url=URL.createObjectURL(blob);
    var a=document.createElement('a');
    a.href=url; a.download='Lead-'+ref+'-Abra-Travels.html';
    document.body.appendChild(a); a.click();
    setTimeout(function(){ URL.revokeObjectURL(url); document.body.removeChild(a); },1000);
    toast('PDF downloaded — open and Print → Save as PDF','ok');
}

// EMAIL MODAL
function openMailModal(id, email, name, ref) {
    document.getElementById('mailId').value = id;
    document.getElementById('mailTo').value = email;
    document.getElementById('mailSubject').value = 'Your Enquiry Update — Abra Tours & Travels (' + ref + ')';
    document.getElementById('mailMsg').value = '';
    document.getElementById('mailOverlay').classList.add('show');
}
function closeMailModal() { document.getElementById('mailOverlay').classList.remove('show'); }
function doSendMail() {
    var id = document.getElementById('mailId').value;
    var sub = document.getElementById('mailSubject').value.trim();
    var msg = document.getElementById('mailMsg').value;
    var btn = document.getElementById('mailSendBtn');
    if (!sub) { toast('Please enter a subject', 'err'); return; }
    btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending…';
    doPost('send_email', { id: id, subject: sub, custom_message: msg })
        .then(function(d) {
            btn.disabled = false; btn.innerHTML = '<i class="fas fa-paper-plane"></i> Send Email';
            if (d.success) { toast(d.message || 'Email sent!', 'ok'); closeMailModal(); }
            else toast('Email failed: ' + (d.message || 'Check mail config'), 'err');
        })
        .catch(function(e) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-paper-plane"></i> Send Email'; toast(e.message, 'err'); });
}

document.addEventListener('keydown',function(e){ if(e.key==='Escape'){ closeDP(); closeAddLead(); closeMailModal(); } });
document.getElementById('mailOverlay').addEventListener('click', function(e) { if (e.target === this) closeMailModal(); });
</script>

<!-- EMAIL MODAL -->
<div id="mailOverlay" class="modal-overlay">
    <div class="modal-box" style="max-width:560px;">
        <div class="modal-header">
            <h3><i class="fas fa-envelope"></i> Send Email to Customer</h3>
            <button class="modal-close" onclick="closeMailModal()"><i class="fas fa-times"></i></button>
        </div>
        <div class="modal-body">
            <input type="hidden" id="mailId">
            <div style="margin-bottom:14px;">
                <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:5px;">To</label>
                <input type="email" id="mailTo" readonly style="background:#f1f5f9;border:2px solid #e2e8f0;border-radius:9px;padding:10px 14px;font-size:14px;width:100%;color:#64748b;font-family:Poppins,sans-serif;">
            </div>
            <div style="margin-bottom:14px;">
                <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:5px;">Subject</label>
                <input type="text" id="mailSubject" style="border:2px solid #e2e8f0;border-radius:9px;padding:10px 14px;font-size:14px;width:100%;color:#1e293b;font-family:Poppins,sans-serif;">
            </div>
            <div style="margin-bottom:14px;">
                <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:5px;">Custom Message (optional)</label>
                <textarea id="mailMsg" rows="5" placeholder="Add a personalized message…" style="border:2px solid #e2e8f0;border-radius:9px;padding:10px 14px;font-size:14px;width:100%;color:#1e293b;font-family:Poppins,sans-serif;resize:vertical;"></textarea>
            </div>
            <p style="font-size:12px;color:#94a3b8;margin-top:8px;"><i class="fas fa-circle-info"></i> A branded email with company details will be sent automatically.</p>
        </div>
        <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:6px;">
            <button class="btn-cancel" onclick="closeMailModal()">Cancel</button>
            <button class="btn-send" id="mailSendBtn" onclick="doSendMail()">
                <i class="fas fa-paper-plane"></i> Send Email
            </button>
        </div>
    </div>
</div>

</body>
</html>
