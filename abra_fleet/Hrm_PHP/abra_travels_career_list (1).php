<?php
// ============================================================
// ABRA TRAVELS — CAREER ADMIN PANEL
// File: abra_travels_career_list.php
// Tab 1: Job Postings (Post/Edit/Delete/Toggle jobs)
// Tab 2: Applications (View/Assign/Status/Notes/Resume Download)
// Blue theme matching abra_travels_custom_quote_list.php
// ============================================================
ob_start();
error_reporting(E_ERROR | E_WARNING | E_PARSE);
if (session_status() == PHP_SESSION_NONE) session_start();

require_once('database.php');
require_once('library.php');
if (function_exists('funciones')) require_once('funciones.php');

$con = null;
if (function_exists('conexion'))         $con = conexion();
elseif (isset($dbConn))                  $con = $dbConn;
elseif (function_exists('dbConnection')) $con = dbConnection();

if (!$con) {
    header('Content-Type: application/json');
    echo json_encode(['success'=>false,'message'=>'DB connection failed']);
    exit;
}
mysqli_set_charset($con, 'utf8mb4');

function aq($con,$sql)    { return mysqli_query($con,$sql); }
function ae($con)         { return mysqli_error($con); }
function aesc($con,$v)    { return mysqli_real_escape_string($con,trim((string)($v??''))); }
function ares($con,$sql)  { $r=aq($con,$sql); if($r&&mysqli_num_rows($r)>0) return mysqli_fetch_assoc($r); return null; }
function acnt($con,$sql)  { $r=aq($con,$sql); $row=$r?mysqli_fetch_assoc($r):null; return $row?(int)($row['c']??0):0; }

// ✅ CREATOR LOGIC — Get from URL parameter first, then session fallback
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) : '';
$creator_name  = '';
$creator_email = '';
$created_by    = 1;

if(!empty($currentUserEmail)) {
    $email_safe  = aesc($con, $currentUserEmail);
    $creator_row = ares($con, "SELECT id, name, email FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'active' LIMIT 1");
    if($creator_row) {
        $creator_name  = $creator_row['name'];
        $creator_email = $creator_row['email'];
        $created_by    = (int)$creator_row['id'];
    }
}

// ── ENSURE TABLES ─────────────────────────────────────────────────────────────
aq($con,"CREATE TABLE IF NOT EXISTS `career_jobs` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `title` varchar(200) NOT NULL,
    `department` varchar(100) DEFAULT NULL,
    `location` varchar(100) DEFAULT NULL,
    `job_type` varchar(50) DEFAULT 'Full Time',
    `experience` varchar(100) DEFAULT NULL,
    `salary_range` varchar(100) DEFAULT NULL,
    `description` text DEFAULT NULL,
    `requirements` text DEFAULT NULL,
    `responsibilities` text DEFAULT NULL,
    `skills_required` text DEFAULT NULL,
    `vacancies` int(11) DEFAULT 1,
    `deadline` date DEFAULT NULL,
    `status` varchar(20) DEFAULT 'active',
    `posted_by` varchar(200) DEFAULT NULL,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

aq($con,"CREATE TABLE IF NOT EXISTS `career_applications` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `job_id` int(11) DEFAULT NULL,
    `full_name` varchar(200) DEFAULT NULL,
    `email` varchar(200) DEFAULT NULL,
    `phone` varchar(30) DEFAULT NULL,
    `position_applied` varchar(200) DEFAULT NULL,
    `department` varchar(100) DEFAULT NULL,
    `experience_years` varchar(50) DEFAULT NULL,
    `qualification` varchar(100) DEFAULT NULL,
    `current_company` varchar(200) DEFAULT NULL,
    `current_ctc` varchar(100) DEFAULT NULL,
    `expected_ctc` varchar(100) DEFAULT NULL,
    `notice_period` varchar(50) DEFAULT NULL,
    `location` varchar(200) DEFAULT NULL,
    `skills` text DEFAULT NULL,
    `cover_letter_text` text DEFAULT NULL,
    `resume_path` varchar(500) DEFAULT NULL,
    `cover_letter_path` varchar(500) DEFAULT NULL,
    `linkedin_url` varchar(500) DEFAULT NULL,
    `portfolio_url` varchar(500) DEFAULT NULL,
    `how_heard` varchar(100) DEFAULT NULL,
    `availability_date` date DEFAULT NULL,
    `status` varchar(50) DEFAULT 'new',
    `assigned_to` varchar(200) DEFAULT NULL,
    `assigned_employee_id` int(11) DEFAULT NULL,
    `admin_notes` text DEFAULT NULL,
    `follow_up_date` date DEFAULT NULL,
    `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
    `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// ── FETCH HR EMPLOYEES ────────────────────────────────────────────────────────
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
// fallback: try hr_employees table
if (empty($employees)) {
    $er = aq($con,"SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name ASC");
    if ($er) while ($row = mysqli_fetch_assoc($er)) $employees[] = ['id'=>$row['id'],'name'=>$row['name']];
}

require_once('abra_email_helper.php'); // ← MASTER EMAIL HELPER

function sendATEmail($to, $subject, $html) {
    // kept for backward compatibility — routes through branded mailer
    $h  = "MIME-Version: 1.0\r\n";
    $h .= "Content-Type: text/html; charset=UTF-8\r\n";
    $h .= "From: ABRA Tours & Travels <hr-admin@abra-travels.com>\r\n";
    $h .= "Reply-To: hr-admin@abra-travels.com\r\n";
    return mail($to, $subject, $html, $h);
}

// ── AJAX ─────────────────────────────────────────────────────────────────────
if (isset($_GET['ajax'])) {
    ob_clean();
    header('Content-Type: application/json; charset=utf-8');
    try {
        $id = (int)($_POST['id'] ?? $_GET['id'] ?? 0);

        // ── SAVE JOB (add/edit) ───────────────────────────────────────────────
        if ($_GET['ajax'] === 'save_job') {
            $jid     = (int)($_POST['jid'] ?? 0);
            $title   = aesc($con,$_POST['title']??'');
            if (!$title) throw new Exception('Job title is required');
            $dept    = aesc($con,$_POST['department']??'');
            $loc     = aesc($con,$_POST['location']??'');
            $jtype   = aesc($con,$_POST['job_type']??'Full Time');
            $exp     = aesc($con,$_POST['experience']??'');
            $sal     = aesc($con,$_POST['salary_range']??'');
            $desc    = aesc($con,$_POST['description']??'');
            $req     = aesc($con,$_POST['requirements']??'');
            $resp    = aesc($con,$_POST['responsibilities']??'');
            $skills  = aesc($con,$_POST['skills_required']??'');
            $vac     = (int)($_POST['vacancies']??1);
            $dl      = !empty($_POST['deadline']) ? "'"  .aesc($con,$_POST['deadline'])."'" : 'NULL';
            $jstatus = aesc($con,$_POST['status']??'active');
            $pby     = aesc($con,$_POST['posted_by']??'');

            if ($jid > 0) {
                $sql = "UPDATE career_jobs SET title='$title',department='$dept',location='$loc',job_type='$jtype',experience='$exp',salary_range='$sal',description='$desc',requirements='$req',responsibilities='$resp',skills_required='$skills',vacancies=$vac,deadline=$dl,status='$jstatus',posted_by='$pby',updated_at=NOW() WHERE id=$jid";
                aq($con,$sql); echo json_encode(['success'=>true,'message'=>'Job updated successfully']);
            } else {
                $sql = "INSERT INTO career_jobs (title,department,location,job_type,experience,salary_range,description,requirements,responsibilities,skills_required,vacancies,deadline,status,posted_by,created_at) VALUES ('$title','$dept','$loc','$jtype','$exp','$sal','$desc','$req','$resp','$skills',$vac,$dl,'$jstatus','$pby',NOW())";
                aq($con,$sql);
                $nid = mysqli_insert_id($con);
                echo json_encode(['success'=>true,'id'=>$nid,'message'=>'Job posted successfully'.($jstatus==='active'?' and is now LIVE on the website!':'')]);
            }
            exit;
        }

        // ── TOGGLE JOB STATUS ─────────────────────────────────────────────────
        if ($_GET['ajax'] === 'toggle_job') {
            if (!$id) throw new Exception('Missing ID');
            $ns = aesc($con,$_POST['status']??'active');
            $valid = ['active','paused','closed'];
            if (!in_array($ns,$valid)) throw new Exception('Invalid status');
            aq($con,"UPDATE career_jobs SET status='$ns',updated_at=NOW() WHERE id=$id");
            echo json_encode(['success'=>true,'status'=>$ns]);
            exit;
        }

        // ── GET JOB ───────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'get_job') {
            if (!$id) throw new Exception('Missing ID');
            $r = ares($con,"SELECT * FROM career_jobs WHERE id=$id LIMIT 1");
            if (!$r) throw new Exception('Job not found');
            echo json_encode(['success'=>true,'data'=>$r]);
            exit;
        }

        // ── DELETE JOB ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'delete_job') {
            if (!$id) throw new Exception('Missing ID');
            aq($con,"DELETE FROM career_jobs WHERE id=$id");
            echo json_encode(['success'=>true]);
            exit;
        }

        // ── GET APPLICATION DETAIL ────────────────────────────────────────────
        if ($_GET['ajax'] === 'get_app') {
            if (!$id) throw new Exception('Missing ID');
            $r = aq($con,"SELECT ca.*, cj.title AS job_title, cj.department AS job_dept FROM career_applications ca LEFT JOIN career_jobs cj ON ca.job_id=cj.id WHERE ca.id=$id LIMIT 1");
            $row = ($r && mysqli_num_rows($r)>0) ? mysqli_fetch_assoc($r) : null;
            if (!$row) throw new Exception('Application #'.$id.' not found');
            echo json_encode(['success'=>true,'data'=>$row,'employees'=>$employees]);
            exit;
        }

        // ── UPDATE APP STATUS ─────────────────────────────────────────────────
        if ($_GET['ajax'] === 'update_status') {
            if (!$id) throw new Exception('Missing ID');
            $status = aesc($con,$_POST['status']??'');
            $valid  = ['new','under_review','shortlisted','interview_scheduled','selected','on_hold','rejected'];
            if (!in_array($status,$valid)) throw new Exception('Invalid status');
            aq($con,"UPDATE career_applications SET status='$status',updated_at=NOW() WHERE id=$id");
            echo json_encode(['success'=>true,'status'=>$status,'message'=>'Status updated']);
            exit;
        }

        // ── ASSIGN + RAISE TICKET ─────────────────────────────────────────────
        if ($_GET['ajax'] === 'assign_and_ticket') {
            if (!$id) throw new Exception('Missing enquiry ID');
            $emp_name_raw = trim($_POST['employee_name'] ?? '');
            $emp_name     = aesc($con, $emp_name_raw);
            if (!$emp_name) throw new Exception('Please select an HR agent');

            // API IDs are MongoDB strings — resolve integer ID from hr_employees by name
            $emp_check = ares($con, "SELECT id, name FROM hr_employees WHERE name='$emp_name' LIMIT 1");
            if (!$emp_check) $emp_check = ares($con, "SELECT id, name FROM hr_employees WHERE name LIKE '%$emp_name%' LIMIT 1");
            if (!$emp_check) $emp_check = ares($con, "SELECT id, name FROM hr_employees ORDER BY id ASC LIMIT 1");
            $emp_id = $emp_check ? (int)$emp_check['id'] : 1;

            aq($con, "UPDATE career_applications SET assigned_to='$emp_name',assigned_employee_id=$emp_id,updated_at=NOW() WHERE id=$id");

            $app = ares($con, "SELECT * FROM career_applications WHERE id=$id LIMIT 1");
            if (!$app) throw new Exception('Application not found');

            $ref_id   = 'APP-' . str_pad($id, 5, '0', STR_PAD_LEFT);
            $t_subject = "Career Application [$ref_id] — " . ($app['position_applied'] ?? '');
            $msg_parts = [
                "Career Application received.",
                "Ref: $ref_id",
                "Applicant: " . ($app['full_name'] ?? ''),
                "Phone: " . ($app['phone'] ?? ''),
                "Email: " . ($app['email'] ?? ''),
                "Position: " . ($app['position_applied'] ?? ''),
                "Department: " . ($app['department'] ?? ''),
                "Experience: " . ($app['experience_years'] ?? ''),
                "Skills: " . ($app['skills'] ?? ''),
                "Notice Period: " . ($app['notice_period'] ?? ''),
                "Please review their resume in the careers admin panel."
            ];

            $priority  = 'medium';
            $timeline  = 1440;
            $t_status  = 'open';

            // ✅ Use global creator variables with session fallback
            // Fallback to session only if URL email was not provided
            if(empty($currentUserEmail)) {
                $sname = $_SESSION['user_name'] ?? '';
                if ($sname) {
                    $sn = aesc($con, $sname);
                    $sr = ares($con, "SELECT id, name, email FROM hr_employees 
                        WHERE name='$sn' OR name LIKE '%$sn%' LIMIT 1");
                    if ($sr) {
                        $created_by    = (int)$sr['id'];
                        $creator_name  = $sr['name'];
                        $creator_email = $sr['email'];
                    }
                }
            }

            // ✅ CRITICAL FIX: Ensure creator_email is NEVER empty (backend requires it)
            if(empty($creator_email)) {
                $creator_email = 'crm@abra-travels.com';  // Default system email
                $creator_name  = $creator_name ?: 'CRM System';
            }

            // Email comes directly from MongoDB API — no MySQL lookup needed
            $assigned_email_for_ticket = strtolower(trim($_POST['employee_email'] ?? ''));

            $ticket_payload = json_encode([
                'subject'        => $t_subject,
                'message'        => implode("\n", $msg_parts),
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

            aq($con, "UPDATE career_applications SET ticket_number='$ticket_number',updated_at=NOW() WHERE id=$id");

            echo json_encode(['success' => true, 'ticket_number' => $ticket_number, 'message' => "Assigned to $emp_name. Ticket $ticket_number created."]);
            exit;
        }

        // ── SAVE NOTES ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'save_notes') {
            if (!$id) throw new Exception('Missing ID');
            $notes = aesc($con,$_POST['notes']??'');
            $fdate = !empty($_POST['follow_up_date']) ? "'".aesc($con,$_POST['follow_up_date'])."'" : 'NULL';
            aq($con,"UPDATE career_applications SET admin_notes='$notes',follow_up_date=$fdate,updated_at=NOW() WHERE id=$id");
            echo json_encode(['success'=>true,'message'=>'Notes saved']);
            exit;
        }

        // ── SEND EMAIL ────────────────────────────────────────────────────────
        if ($_GET['ajax'] === 'send_email') {
            if (!$id) throw new Exception('Missing ID');
            $app = ares($con,"SELECT * FROM career_applications WHERE id=$id LIMIT 1");
            if (!$app) throw new Exception('Application not found');
            $email = trim($app['email'] ?? '');
            if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) throw new Exception('No valid email for this applicant');

            $c_subject = trim($_POST['subject']      ?? 'Your Application Update — ABRA Tours & Travels');
            $c_msg     = trim($_POST['custom_message']?? '');

            // Uses the fully branded helper function (logo, GST, address, footer)
            $sent = abraSendAdminEmailToCandidate($email, $c_subject, $c_msg, $app);
            if (!$sent) throw new Exception('mail() returned false. Check server mail config.');
            echo json_encode(['success' => true, 'message' => "Email sent to $email"]);
            exit;
        }

        // ── DELETE APPLICATION ────────────────────────────────────────────────
        if ($_GET['ajax'] === 'delete_app') {
            if (!$id) throw new Exception('Missing ID');
            // Remove files
            $app = ares($con,"SELECT resume_path,cover_letter_path FROM career_applications WHERE id=$id LIMIT 1");
            if ($app) {
                if ($app['resume_path']       && file_exists(__DIR__.'/'.$app['resume_path']))       @unlink(__DIR__.'/'.$app['resume_path']);
                if ($app['cover_letter_path'] && file_exists(__DIR__.'/'.$app['cover_letter_path'])) @unlink(__DIR__.'/'.$app['cover_letter_path']);
            }
            aq($con,"DELETE FROM career_applications WHERE id=$id");
            echo json_encode(['success'=>true]);
            exit;
        }

        throw new Exception('Unknown AJAX action: '.($_GET['ajax']??'none'));

    } catch (Throwable $e) {
        echo json_encode(['success'=>false,'message'=>$e->getMessage()]);
        exit;
    }
}

// ── RESUME DOWNLOAD ───────────────────────────────────────────────────────────
if (isset($_GET['download'])) {
    $did  = (int)($_GET['download']??0);
    $type = $_GET['type']??'resume';
    if ($did) {
        $app = ares($con,"SELECT resume_path,cover_letter_path,full_name FROM career_applications WHERE id=$did LIMIT 1");
        if ($app) {
            $path = $type === 'cover' ? ($app['cover_letter_path']??'') : ($app['resume_path']??'');
            $fp   = __DIR__.'/'.$path;
            if ($path && file_exists($fp)) {
                $name = ($type==='cover'?'CoverLetter':'Resume').'_'.preg_replace('/[^a-zA-Z0-9]/', '_', $app['full_name']).'.'.pathinfo($fp, PATHINFO_EXTENSION);
                header('Content-Type: application/octet-stream');
                header('Content-Disposition: attachment; filename="'.$name.'"');
                header('Content-Length: '.filesize($fp));
                readfile($fp);
                exit;
            }
        }
    }
    die('File not found.');
}

// ── CSV EXPORT (Applications) ─────────────────────────────────────────────────
if (isset($_GET['export']) && $_GET['export']==='csv') {
    ob_clean();
    $exp = aq($con,"SELECT id,full_name,email,phone,position_applied,department,experience_years,qualification,current_company,notice_period,location,skills,how_heard,status,assigned_to,follow_up_date,created_at FROM career_applications ORDER BY created_at DESC");
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=career_applications_'.date('Ymd_His').'.csv');
    $out = fopen('php://output','w');
    fprintf($out,chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($out,['ID','Name','Email','Phone','Position','Department','Experience','Qualification','Company','Notice','Location','Skills','How Heard','Status','Assigned To','Follow-up','Applied On']);
    if ($exp) while ($row = mysqli_fetch_assoc($exp)) fputcsv($out,array_values($row));
    fclose($out);
    exit;
}

// ── STATS ─────────────────────────────────────────────────────────────────────
$app_stats = [
    'total'      => acnt($con,"SELECT COUNT(*) c FROM career_applications"),
    'new'        => acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE status='new'"),
    'shortlisted'=> acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE status='shortlisted'"),
    'selected'   => acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE status='selected'"),
    'today'      => acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE DATE(created_at)=CURDATE()"),
    'follow_up'  => acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE follow_up_date=CURDATE() AND status NOT IN ('selected','rejected')"),
];

$job_stats = [
    'total'   => acnt($con,"SELECT COUNT(*) c FROM career_jobs"),
    'active'  => acnt($con,"SELECT COUNT(*) c FROM career_jobs WHERE status='active'"),
    'paused'  => acnt($con,"SELECT COUNT(*) c FROM career_jobs WHERE status='paused'"),
    'closed'  => acnt($con,"SELECT COUNT(*) c FROM career_jobs WHERE status='closed'"),
];

// ── APPLICATION FILTERS ───────────────────────────────────────────────────────
$f_status = aesc($con,$_GET['status']??'');
$f_dept   = aesc($con,$_GET['dept']??'');
$f_search = aesc($con,$_GET['search']??'');
$f_agent  = aesc($con,$_GET['agent']??'');
$f_df     = aesc($con,$_GET['date_from']??'');
$f_dt     = aesc($con,$_GET['date_to']??'');
$f_tab    = $_GET['tab']??'applications';

$where = "WHERE 1=1";
if ($f_status) $where .= " AND ca.status='$f_status'";
if ($f_dept)   $where .= " AND ca.department='$f_dept'";
if ($f_search) $where .= " AND (ca.full_name LIKE '%$f_search%' OR ca.phone LIKE '%$f_search%' OR ca.email LIKE '%$f_search%' OR ca.position_applied LIKE '%$f_search%')";
if ($f_agent)  $where .= " AND ca.assigned_to='$f_agent'";
if ($f_df)     $where .= " AND DATE(ca.created_at)>='$f_df'";
if ($f_dt)     $where .= " AND DATE(ca.created_at)<='$f_dt'";

$apps_result = aq($con,"SELECT ca.*, cj.title AS job_title FROM career_applications ca LEFT JOIN career_jobs cj ON ca.job_id=cj.id $where ORDER BY ca.created_at DESC");
$jobs_result = aq($con,"SELECT cj.*, (SELECT COUNT(*) FROM career_applications ca WHERE ca.job_id=cj.id) AS applicant_count FROM career_jobs cj ORDER BY cj.created_at DESC");

$APP_STATUS = [
    'new'                 => ['label'=>'New',              'color'=>'#1e40af','bg'=>'#eff6ff','border'=>'#bfdbfe'],
    'under_review'        => ['label'=>'Under Review',     'color'=>'#d97706','bg'=>'#fffbeb','border'=>'#fcd34d'],
    'shortlisted'         => ['label'=>'Shortlisted',      'color'=>'#7c3aed','bg'=>'#fdf4ff','border'=>'#e9d5ff'],
    'interview_scheduled' => ['label'=>'Interview Sched.', 'color'=>'#0891b2','bg'=>'#ecfeff','border'=>'#a5f3fc'],
    'selected'            => ['label'=>'Selected ✅',       'color'=>'#16a34a','bg'=>'#f0fdf4','border'=>'#86efac'],
    'on_hold'             => ['label'=>'On Hold',           'color'=>'#64748b','bg'=>'#f8fafc','border'=>'#e2e8f0'],
    'rejected'            => ['label'=>'Rejected',          'color'=>'#dc2626','bg'=>'#fef2f2','border'=>'#fecaca'],
];
$JOB_STATUS = [
    'active' => ['label'=>'🟢 Active (Live)','color'=>'#16a34a','bg'=>'#f0fdf4','border'=>'#86efac'],
    'paused' => ['label'=>'🟡 Paused',        'color'=>'#d97706','bg'=>'#fffbeb','border'=>'#fcd34d'],
    'closed' => ['label'=>'🔴 Closed',        'color'=>'#dc2626','bg'=>'#fef2f2','border'=>'#fecaca'],
];
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Career Management | Abra Travels CRM</title>
<link rel="shortcut icon" type="image/png" href="img/favicon.png"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css" crossorigin="anonymous"/>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800;900&display=swap" rel="stylesheet"/>
<style>
*,*::before,*::after{box-sizing:border-box}
body,h1,h2,h3,h4,h5,h6,p,span,a,td,th,label,input,select,textarea,button,small,li,div{font-family:'Poppins',sans-serif!important}
body{background:#f0f4f8;margin:0;padding:0}
.at-wrap{padding:20px 24px 60px}

/* HEADER */
.at-header{background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);border-radius:14px;padding:20px 28px;margin-bottom:22px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;box-shadow:0 6px 24px rgba(30,58,138,.28)}
.at-header h1{color:#fff;font-weight:800;font-size:1.35rem;margin:0;display:flex;align-items:center;gap:10px}
.at-header h1 small{font-size:.75rem;font-weight:600;opacity:.75;display:block;margin-top:3px}
.hdr-btns{display:flex;gap:10px;flex-wrap:wrap}
.btn-hdr{background:rgba(255,255,255,.16);color:#fff!important;padding:9px 20px;border-radius:9px;text-decoration:none!important;font-weight:700;font-size:13.5px;display:inline-flex;align-items:center;gap:7px;border:1.5px solid rgba(255,255,255,.28);cursor:pointer;transition:.2s;white-space:nowrap}
.btn-hdr:hover{background:rgba(255,255,255,.28)}
.btn-hdr-green{background:rgba(22,163,74,.7);border-color:rgba(22,163,74,.9)}
.btn-hdr-green:hover{background:rgba(22,163,74,.9)}

/* TABS */
.main-tabs{display:flex;gap:0;background:#fff;border-radius:14px;padding:6px;box-shadow:0 2px 12px rgba(0,0,0,.07);margin-bottom:20px;overflow:hidden;width:fit-content}
.main-tab{padding:11px 28px;border-radius:10px;font-size:14px;font-weight:700;cursor:pointer;color:#64748b;border:none;background:transparent;transition:.2s;display:inline-flex;align-items:center;gap:8px;white-space:nowrap}
.main-tab:hover{background:#f8fafc;color:#1e3a8a}
.main-tab.active{background:linear-gradient(135deg,#1e3a8a,#1e40af);color:#fff;box-shadow:0 4px 16px rgba(30,58,138,.3)}
.tab-badge{background:rgba(255,255,255,.25);padding:2px 8px;border-radius:20px;font-size:11.5px;font-weight:800}
.main-tab:not(.active) .tab-badge{background:#e2e8f0;color:#64748b}

/* STAT CARDS */
.stat-card{background:#fff;border-radius:14px;padding:16px 20px;box-shadow:0 2px 14px rgba(0,0,0,.07);display:flex;align-items:center;gap:14px;border-left:5px solid transparent;transition:transform .2s;height:100%}
.stat-card:hover{transform:translateY(-3px);box-shadow:0 6px 24px rgba(0,0,0,.12)}
.s-blue{border-left-color:#1e40af}.s-amber{border-left-color:#d97706}.s-green{border-left-color:#16a34a}.s-cyan{border-left-color:#0891b2}.s-red{border-left-color:#dc2626}.s-purple{border-left-color:#7c3aed}
.stat-icon{width:50px;height:50px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0}
.i-blue{background:#eff6ff;color:#1e40af}.i-amber{background:#fffbeb;color:#d97706}.i-green{background:#f0fdf4;color:#16a34a}.i-cyan{background:#ecfeff;color:#0891b2}.i-red{background:#fef2f2;color:#dc2626}.i-purple{background:#fdf4ff;color:#7c3aed}
.stat-num{font-size:30px;font-weight:900;color:#1e293b;margin:0;line-height:1}
.stat-lbl{font-size:12px;color:#94a3b8;font-weight:600;margin:2px 0 0}

/* FILTER BAR */
.filter-bar{background:#fff;border-radius:12px;box-shadow:0 1px 8px rgba(0,0,0,.07);padding:18px 22px;margin-bottom:16px}
.filter-bar .bar-title{font-size:13.5px;font-weight:700;color:#1e3a8a;display:flex;align-items:center;gap:7px;margin-bottom:14px}
.frow{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end;margin-bottom:10px}
.frow:last-child{margin-bottom:0}
.fg{display:flex;flex-direction:column;flex:1;min-width:140px}
.fg label{font-size:11.5px;font-weight:700;color:#374151;margin-bottom:4px}
.fc{border:1.5px solid #d1d5db;border-radius:8px;padding:0 12px;font-size:13.5px;height:40px;color:#111827;width:100%;background:#fff;transition:border-color .15s;-webkit-appearance:none}
.fc:focus{border-color:#1e40af;outline:none;box-shadow:0 0 0 3px rgba(30,64,175,.1)}
.fc::placeholder{color:#9ca3af}
.btn-apply{background:#1e3a8a;color:#fff;border:none;border-radius:8px;padding:0 22px;height:40px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;white-space:nowrap;transition:.15s}
.btn-apply:hover{background:#1e40af}
.btn-reset{background:#f3f4f6;color:#6b7280;border:1.5px solid #d1d5db;border-radius:8px;padding:0 16px;height:40px;font-size:13.5px;font-weight:600;text-decoration:none;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
.btn-reset:hover{background:#e5e7eb;color:#374151;text-decoration:none}

/* QUICK TABS */
.tab-pills{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}
.tab-pill{background:#fff;border:2px solid #e2e8f0;color:#64748b;padding:6px 16px;border-radius:50px;font-size:13px;font-weight:700;text-decoration:none;transition:.15s}
.tab-pill:hover{border-color:#1e40af;color:#1e40af;text-decoration:none}
.tab-pill.active{border-color:#1e3a8a;color:#1e3a8a;background:#eff6ff}

/* TABLE */
.tbl-wrap-outer{background:#fff;border-radius:14px;box-shadow:0 2px 14px rgba(0,0,0,.07);overflow:hidden}
.tbl-scroll{overflow-x:auto}
.at-tbl{width:100%;border-collapse:collapse;min-width:1100px}
.at-tbl thead th{background:#1e3a8a;color:#fff;padding:13px 14px;font-size:13.5px;font-weight:700;white-space:nowrap}
.at-tbl tbody td{padding:12px 14px;border-bottom:1px solid #f1f5f9;font-size:13.5px;color:#1e293b;vertical-align:middle}
.at-tbl tbody tr:hover td{background:#eff6ff!important}
.at-tbl tfoot td{padding:12px 14px;font-size:13.5px;color:#64748b;border-top:2px solid #e2e8f0}
.row-new{background:#f0f7ff!important}

/* BADGES */
.ref-badge{font-size:12.5px;font-weight:800;color:#1e40af;background:#eff6ff;padding:3px 9px;border-radius:6px;letter-spacing:.3px;display:inline-block}
.new-tag{font-size:10.5px;background:#1e40af;color:#fff;padding:2px 7px;border-radius:5px;font-weight:700;display:inline-block;margin-top:3px}
.status-badge{padding:5px 12px;border-radius:20px;font-size:12px;font-weight:700;display:inline-block;white-space:nowrap}
.job-status-badge{padding:4px 12px;border-radius:20px;font-size:12px;font-weight:700;display:inline-block}
.assign-tag-ok{background:#f0fdf4;border:1.5px solid #86efac;color:#16a34a;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block}
.assign-tag-no{background:#fef2f2;border:1.5px solid #fecaca;color:#dc2626;padding:4px 10px;border-radius:7px;font-size:12px;font-weight:700;display:inline-block}
.fu-tag{background:#fef3c7;border:1.5px solid #fcd34d;border-radius:7px;padding:3px 9px;font-size:12px;font-weight:700;color:#92400e;display:inline-block}
.fu-tag.urgent{background:#fef2f2;border-color:#fca5a5;color:#dc2626}

/* ACTION BUTTONS */
.ab{padding:5px 10px;border-radius:7px;font-size:12px;font-weight:700;text-decoration:none!important;border:1.5px solid transparent;cursor:pointer;display:inline-flex;align-items:center;gap:5px;margin:1px;transition:.15s;white-space:nowrap;line-height:1.3}
.ab:hover{filter:brightness(.85)}
.ab-view{background:#eff6ff;color:#1e40af;border-color:#bfdbfe}
.ab-edit{background:#fffbeb;color:#d97706;border-color:#fcd34d}
.ab-del{background:#fef2f2;color:#dc2626;border-color:#fecaca}
.ab-green{background:#f0fdf4;color:#16a34a;border-color:#86efac}
.ab-gray{background:#f8fafc;color:#475569;border-color:#e2e8f0}
.ab-note{background:#fdf4ff;color:#7c3aed;border-color:#e9d5ff}

/* JOB CARDS GRID */
.jobs-admin-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:18px;margin-bottom:20px}
.job-admin-card{background:#fff;border-radius:16px;border:2px solid #e2e8f0;box-shadow:0 2px 12px rgba(0,0,0,.06);overflow:hidden;transition:.2s}
.job-admin-card:hover{border-color:#1e3a8a;box-shadow:0 8px 28px rgba(30,58,138,.14);transform:translateY(-3px)}
.jac-head{background:linear-gradient(135deg,#eff6ff,#dbeafe);padding:16px 20px;border-bottom:2px solid #dbeafe}
.jac-title{font-size:15px;font-weight:900;color:#1e293b;margin-bottom:8px}
.jac-tags{display:flex;flex-wrap:wrap;gap:5px;margin-bottom:10px}
.jac-tag{padding:3px 10px;border-radius:20px;font-size:11.5px;font-weight:700}
.jac-body{padding:16px 20px}
.jac-desc{font-size:13px;color:#64748b;line-height:1.65;margin-bottom:12px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.jac-meta{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:12px}
.jac-meta span{font-size:12.5px;color:#94a3b8;font-weight:600;display:flex;align-items:center;gap:4px}
.jac-actions{display:flex;gap:7px;flex-wrap:wrap}
.applicant-count{background:#1e3a8a;color:#fff;padding:3px 12px;border-radius:20px;font-size:12px;font-weight:800;display:inline-flex;align-items:center;gap:5px}

/* DETAIL PANEL */
.dp-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.55);z-index:9990;display:none}
.dp-overlay.show{display:block}
.dp-panel{position:fixed;top:0;right:-100%;width:100%;max-width:900px;height:100vh;background:#fff;z-index:9999;box-shadow:-8px 0 40px rgba(0,0,0,.18);transition:right .35s cubic-bezier(.4,0,.2,1);overflow-y:auto;display:flex;flex-direction:column}
.dp-panel.open{right:0}
.dp-head{background:linear-gradient(135deg,#1e3a8a,#1e40af);padding:20px 28px;color:#fff;display:flex;justify-content:space-between;align-items:flex-start;position:sticky;top:0;z-index:2;flex-shrink:0}
.dp-head h2{font-size:1.1rem;font-weight:800;margin:0}
.dp-head p{font-size:13px;margin:4px 0 0;opacity:.78}
.dp-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:36px;height:36px;border-radius:50%;cursor:pointer;font-size:16px;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:.15s}
.dp-close:hover{background:rgba(255,255,255,.35)}
.dp-body{padding:22px 28px 50px;flex:1}
.dp-section{margin-bottom:22px}
.dp-section h4{font-size:14px;font-weight:800;color:#1e3a8a;border-bottom:2px solid #e2e8f0;padding-bottom:9px;margin-bottom:14px;display:flex;align-items:center;gap:8px}
.dp-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}
.dp-grid.g3{grid-template-columns:repeat(3,1fr)}
.dp-field label{font-size:10.5px;color:#94a3b8;font-weight:700;display:block;margin-bottom:3px;text-transform:uppercase;letter-spacing:.4px}
.dp-field span{font-size:14px;font-weight:600;color:#1e293b}
.dp-infobox{background:#f8fafc;border-radius:10px;border:2px solid #e2e8f0;padding:12px 15px;font-size:13.5px;color:#334155;line-height:1.7;white-space:pre-wrap}
.sq-btns{display:flex;flex-wrap:wrap;gap:7px;margin-top:10px}
.sq-btn{border:2px solid;border-radius:8px;padding:6px 14px;font-size:12.5px;font-weight:700;cursor:pointer;background:#fff;transition:.15s;display:inline-flex;align-items:center;gap:5px}
.sq-btn.active{color:#fff!important}
.assign-select{flex:1;border:2px solid #e2e8f0;border-radius:8px;padding:0 12px;font-size:13.5px;height:42px;color:#1e293b;min-width:180px}
.assign-select:focus{border-color:#1e40af;outline:none}
.btn-do-assign{background:#d97706;color:#fff;border:none;border-radius:8px;padding:0 18px;height:42px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;transition:.15s}
.btn-do-assign:hover{background:#b45309}
.dp-textarea{border:2px solid #e2e8f0;border-radius:10px;padding:10px 14px;font-size:13.5px;color:#1e293b;width:100%;min-height:80px;resize:vertical}
.dp-textarea:focus{border-color:#1e40af;outline:none;box-shadow:0 0 0 3px rgba(30,64,175,.1)}
.btn-save-note{background:#16a34a;color:#fff;border:none;border-radius:8px;padding:9px 20px;font-size:13.5px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:6px;margin-top:10px;transition:.15s}
.btn-save-note:hover{background:#15803d}
.action-strip{display:flex;gap:9px;flex-wrap:wrap;padding-top:18px;border-top:2px solid #e2e8f0}
.qs-btn{padding:10px 20px;border-radius:9px;font-weight:700;font-size:13.5px;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:7px;text-decoration:none!important;transition:.15s;white-space:nowrap}
.qs-btn:hover{filter:brightness(.88)}
.qs-call{background:#16a34a;color:#fff!important}
.qs-mail{background:#1e3a8a;color:#fff!important}
.qs-dl{background:#0891b2;color:#fff!important}
.qs-dl2{background:#7c3aed;color:#fff!important}
.qs-del{background:#fef2f2;color:#dc2626!important;border:2px solid #fecaca}

/* JOB MODAL */
.modal-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.6);z-index:19990;display:none;align-items:center;justify-content:center;padding:20px}
.modal-overlay.show{display:flex}
.job-modal-box{background:#fff;border-radius:18px;width:800px;max-width:96vw;max-height:92vh;overflow-y:auto;box-shadow:0 20px 60px rgba(0,0,0,.25)}
.jmb-head{background:linear-gradient(135deg,#1e3a8a,#1e40af);padding:22px 28px;display:flex;justify-content:space-between;align-items:center;position:sticky;top:0;z-index:2}
.jmb-head h3{color:#fff;font-size:1.1rem;font-weight:900;margin:0}
.jmb-close{background:rgba(255,255,255,.2);border:none;color:#fff;width:34px;height:34px;border-radius:50%;cursor:pointer;font-size:15px;display:flex;align-items:center;justify-content:center;transition:.15s}
.jmb-close:hover{background:rgba(255,255,255,.35)}
.jmb-body{padding:26px 28px}
.jm-lbl{font-size:13px;font-weight:700;color:#334155;margin-bottom:6px;display:block}
.jm-req{color:#dc2626}
.jm-inp{border:2px solid #e2e8f0;border-radius:10px;padding:10px 14px;font-size:14px;height:48px;color:#1e293b;width:100%;transition:border-color .2s;background:#fff}
.jm-inp:focus{border-color:#1e3a8a;outline:none;box-shadow:0 0 0 3px rgba(30,58,138,.1)}
textarea.jm-inp{height:auto;min-height:90px;resize:vertical}
select.jm-inp{-webkit-appearance:auto}
.btn-save-job{background:linear-gradient(135deg,#16a34a,#15803d);color:#fff;border:none;border-radius:10px;padding:14px 32px;font-size:15px;font-weight:800;cursor:pointer;display:inline-flex;align-items:center;gap:9px;transition:.2s}
.btn-save-job:hover{transform:translateY(-1px);box-shadow:0 8px 24px rgba(22,163,74,.35)}
.jm-hint{font-size:12px;color:#94a3b8;margin-top:5px}

/* MAIL MODAL */
.mail-box{background:#fff;border-radius:16px;padding:28px 30px;width:560px;max-width:95vw;box-shadow:0 20px 60px rgba(0,0,0,.25)}
.mail-box h4{font-size:16px;font-weight:800;color:#1e3a8a;margin-bottom:18px;display:flex;align-items:center;gap:9px}
.mail-input{border:2px solid #e2e8f0;border-radius:9px;padding:9px 13px;font-size:13.5px;width:100%;margin-bottom:12px}
.mail-input:focus{border-color:#1e40af;outline:none}
.btn-send{background:#1e3a8a;color:#fff;border:none;border-radius:9px;padding:10px 26px;font-size:14px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:7px;transition:.15s}
.btn-send:hover{background:#1e40af}
.btn-cancel{background:#f1f5f9;color:#64748b;border:2px solid #e2e8f0;border-radius:9px;padding:9px 18px;font-size:13.5px;font-weight:700;cursor:pointer}

/* TOAST */
.at-toast{position:fixed;bottom:24px;right:24px;padding:13px 22px;border-radius:12px;font-size:14px;font-weight:700;z-index:99999;display:none;align-items:center;gap:9px;box-shadow:0 8px 32px rgba(0,0,0,.25);min-width:220px;max-width:420px;animation:toastSlide .3s ease}
.at-toast.show{display:flex}
.at-toast.ok{background:#16a34a;color:#fff}
.at-toast.err{background:#dc2626;color:#fff}
.at-toast.inf{background:#1e40af;color:#fff}
@keyframes toastSlide{from{transform:translateY(20px);opacity:0}to{transform:translateY(0);opacity:1}}

/* HR GUIDE */
.hr-guide{background:#fff;border-radius:16px;border:2px solid #bfdbfe;padding:18px 20px;margin-bottom:22px}
.hr-guide h4{font-size:.92rem;font-weight:800;color:#1e3a8a;margin-bottom:12px;display:flex;align-items:center;gap:8px}
.guide-steps{display:grid;grid-template-columns:repeat(6,1fr);gap:10px}
.guide-step{background:#eff6ff;border:2px solid #bfdbfe;border-radius:10px;padding:12px 8px;text-align:center}
.gs-num{width:32px;height:32px;background:linear-gradient(135deg,#1e3a8a,#3b82f6);color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:13px;margin:0 auto 8px;flex-shrink:0}
.gs-title{font-size:11.5px;font-weight:800;color:#1e293b;margin-bottom:4px;line-height:1.3}
.gs-desc{font-size:10.5px;color:#64748b;line-height:1.45;margin:0}
@media(max-width:1100px){.guide-steps{grid-template-columns:repeat(3,1fr)}}
@media(max-width:600px){.guide-steps{grid-template-columns:repeat(2,1fr)}}

@media(max-width:768px){
    .at-wrap{padding:12px 10px 40px}
    .dp-panel{max-width:100%}
    .dp-grid,.dp-grid.g3{grid-template-columns:1fr}
    .jobs-admin-grid{grid-template-columns:1fr}
}
</style>
</head>
<body>
<div class="at-wrap">

<!-- HEADER -->
<div class="at-header">
    <h1>
        <i class="fas fa-user-graduate"></i>
        Career Management
        <small>Post jobs, manage applications &amp; track candidates</small>
    </h1>
    <div class="hdr-btns">
        <button class="btn-hdr btn-hdr-green" onclick="openJobModal(0)"><i class="fas fa-plus-circle"></i> Post New Job</button>
        <a href="?tab=applications&export=csv" class="btn-hdr"><i class="fas fa-file-csv"></i> Export CSV</a>
        <a href="careers.php" target="_blank" class="btn-hdr"><i class="fas fa-external-link-alt"></i> View Career Page</a>
        
    </div>
</div>

<!-- MAIN TABS -->
<div class="main-tabs">
    <button class="main-tab <?= $f_tab==='jobs'?'active':'' ?>" onclick="switchTab('jobs')">
        <i class="fas fa-briefcase"></i> Job Postings
        <span class="tab-badge"><?= $job_stats['total'] ?></span>
    </button>
    <button class="main-tab <?= $f_tab!=='jobs'?'active':'' ?>" onclick="switchTab('applications')">
        <i class="fas fa-file-lines"></i> Applications
        <span class="tab-badge"><?= $app_stats['total'] ?></span>
    </button>
</div>

<!-- ═══════════════ JOB POSTINGS TAB ═══════════════ -->
<div id="tab-jobs" style="display:<?= $f_tab==='jobs'?'block':'none' ?>;">

    <!-- JOB STATS -->
    <div class="row mb-3">
        <div class="col-6 col-md-3 mb-3"><div class="stat-card s-blue"><div class="stat-icon i-blue"><i class="fas fa-layer-group"></i></div><div><p class="stat-num"><?= $job_stats['total'] ?></p><p class="stat-lbl">Total Jobs</p></div></div></div>
        <div class="col-6 col-md-3 mb-3"><div class="stat-card s-green"><div class="stat-icon i-green"><i class="fas fa-circle-check"></i></div><div><p class="stat-num"><?= $job_stats['active'] ?></p><p class="stat-lbl">Active / Live</p></div></div></div>
        <div class="col-6 col-md-3 mb-3"><div class="stat-card s-amber"><div class="stat-icon i-amber"><i class="fas fa-pause-circle"></i></div><div><p class="stat-num"><?= $job_stats['paused'] ?></p><p class="stat-lbl">Paused</p></div></div></div>
        <div class="col-6 col-md-3 mb-3"><div class="stat-card s-red"><div class="stat-icon i-red"><i class="fas fa-circle-xmark"></i></div><div><p class="stat-num"><?= $job_stats['closed'] ?></p><p class="stat-lbl">Closed / Filled</p></div></div></div>
    </div>

    <!-- HR GUIDE -->
    <div class="hr-guide">
        <h4><i class="fas fa-lightbulb" style="color:#d97706;"></i> How the Careers System Works — HR Guide</h4>
        <div class="guide-steps">
            <div class="guide-step"><div class="gs-num"><i class="fas fa-briefcase"></i></div><div class="gs-title">Post a Job</div><div class="gs-desc">Click "Post New Job", fill details, set Active — goes LIVE instantly on website.</div></div>
            <div class="guide-step"><div class="gs-num"><i class="fas fa-paper-plane"></i></div><div class="gs-title">Candidates Apply</div><div class="gs-desc">Candidates fill the 4-step form and upload resume. Stored automatically.</div></div>
            <div class="guide-step"><div class="gs-num"><i class="fas fa-list-check"></i></div><div class="gs-title">Review Applications</div><div class="gs-desc">Use filters by status, dept or date. Click View for full candidate details.</div></div>
            <div class="guide-step"><div class="gs-num"><i class="fas fa-arrow-right-arrow-left"></i></div><div class="gs-title">Update Status</div><div class="gs-desc">Move: New &rarr; Review &rarr; Shortlisted &rarr; Interview &rarr; Selected / Rejected.</div></div>
            <div class="guide-step"><div class="gs-num"><i class="fas fa-user-tag"></i></div><div class="gs-title">Assign &amp; Ticket</div><div class="gs-desc">Assign to HR agent — auto-creates a support ticket same as raise-a-ticket.</div></div>
            <div class="guide-step"><div class="gs-num"><i class="fas fa-download"></i></div><div class="gs-title">Download &amp; Email</div><div class="gs-desc">Download resumes directly. Send personalised emails to candidates.</div></div>
        </div>
    </div>

    <!-- JOB CARDS -->
    <?php if ($jobs_result && mysqli_num_rows($jobs_result) > 0): ?>
    <div class="jobs-admin-grid">
    <?php while ($job = mysqli_fetch_assoc($jobs_result)):
        $jsc = $JOB_STATUS[$job['status']] ?? $JOB_STATUS['active'];
        $dl_days = null;
        if (!empty($job['deadline'])) $dl_days = (int)ceil((strtotime($job['deadline'])-time())/86400);
    ?>
    <div class="job-admin-card">
        <div class="jac-head">
            <div class="jac-title"><?= htmlspecialchars($job['title']) ?></div>
            <div class="jac-tags">
                <?php if ($job['department']): ?><span class="jac-tag" style="background:#eff6ff;color:#1e40af;border:1.5px solid #bfdbfe;"><?= htmlspecialchars($job['department']) ?></span><?php endif; ?>
                <?php if ($job['job_type']): ?><span class="jac-tag" style="background:#f0fdf4;color:#16a34a;border:1.5px solid #86efac;"><?= htmlspecialchars($job['job_type']) ?></span><?php endif; ?>
                <?php if ($job['location']): ?><span class="jac-tag" style="background:#f8fafc;color:#475569;border:1.5px solid #e2e8f0;"><i class="fas fa-location-dot" style="font-size:10px;"></i> <?= htmlspecialchars($job['location']) ?></span><?php endif; ?>
            </div>
            <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;">
                <span class="job-status-badge" style="background:<?=$jsc['bg']?>;color:<?=$jsc['color']?>;border:1.5px solid <?=$jsc['border']?>;"><?= $jsc['label'] ?></span>
                <span class="applicant-count"><i class="fas fa-users" style="font-size:11px;"></i> <?= $job['applicant_count'] ?> applied</span>
            </div>
        </div>
        <div class="jac-body">
            <?php if ($job['description']): ?><p class="jac-desc"><?= htmlspecialchars($job['description']) ?></p><?php endif; ?>
            <div class="jac-meta">
                <?php if ($job['experience']): ?><span><i class="fas fa-chart-line"></i><?= htmlspecialchars($job['experience']) ?></span><?php endif; ?>
                <?php if ($job['salary_range']): ?><span><i class="fas fa-indian-rupee-sign"></i><?= htmlspecialchars($job['salary_range']) ?></span><?php endif; ?>
                <?php if ($job['vacancies']): ?><span><i class="fas fa-user-plus"></i><?= $job['vacancies'] ?> vacancy<?= $job['vacancies']>1?'ies':'' ?></span><?php endif; ?>
                <?php if ($dl_days !== null): ?><span style="<?= $dl_days<=3?'color:#dc2626;':'' ?>"><i class="fas fa-calendar-xmark"></i>
                    <?= $dl_days < 0 ? 'Expired' : ($dl_days===0?'Closes today':'Closes in '.$dl_days.'d') ?></span><?php endif; ?>
                <span style="font-size:12px;color:#94a3b8;"><i class="fas fa-clock"></i> <?= date('d M Y',strtotime($job['created_at'])) ?></span>
            </div>
            <div class="jac-actions">
                <button class="ab ab-edit" onclick="openJobModal(<?= $job['id'] ?>)"><i class="fas fa-pen"></i> Edit</button>
                <?php if ($job['status']==='active'): ?>
                <button class="ab ab-gray" onclick="toggleJobStatus(<?=$job['id']?>,'paused')"><i class="fas fa-pause"></i> Pause</button>
                <button class="ab ab-del" onclick="toggleJobStatus(<?=$job['id']?>,'closed')"><i class="fas fa-ban"></i> Close</button>
                <?php elseif ($job['status']==='paused'): ?>
                <button class="ab ab-green" onclick="toggleJobStatus(<?=$job['id']?>,'active')"><i class="fas fa-play"></i> Go Live</button>
                <button class="ab ab-del" onclick="toggleJobStatus(<?=$job['id']?>,'closed')"><i class="fas fa-ban"></i> Close</button>
                <?php else: ?>
                <button class="ab ab-green" onclick="toggleJobStatus(<?=$job['id']?>,'active')"><i class="fas fa-rotate-left"></i> Re-open</button>
                <?php endif; ?>
                <?php if ($job['applicant_count'] > 0): ?>
                <button class="ab ab-view" onclick="switchTab('applications')" title="<?=$job['applicant_count']?> applications"><i class="fas fa-users"></i> <?=$job['applicant_count']?></button>
                <?php endif; ?>
                <button class="ab ab-del" onclick="deleteJob(<?=$job['id']?>,'<?= addslashes($job['title']) ?>')"><i class="fas fa-trash-alt"></i></button>
            </div>
        </div>
    </div>
    <?php endwhile; ?>
    </div>
    <?php else: ?>
    <div style="background:#fff;border-radius:14px;padding:80px 30px;text-align:center;box-shadow:0 2px 14px rgba(0,0,0,.07);">
        <i class="fas fa-briefcase" style="font-size:52px;color:#e2e8f0;display:block;margin-bottom:18px;"></i>
        <h4 style="font-size:18px;font-weight:800;color:#64748b;margin-bottom:10px;">No Jobs Posted Yet</h4>
        <p style="color:#94a3b8;font-size:14px;margin-bottom:22px;">Post your first job opening and it will appear on the careers page immediately.</p>
        <button class="btn-hdr btn-hdr-green" onclick="openJobModal(0)" style="font-size:15px;padding:12px 28px;border-radius:10px;"><i class="fas fa-plus-circle"></i> Post First Job</button>
    </div>
    <?php endif; ?>
</div>

<!-- ═══════════════ APPLICATIONS TAB ═══════════════ -->
<div id="tab-applications" style="display:<?= $f_tab!=='jobs'?'block':'none' ?>;">

    <!-- APP STATS -->
    <div class="row mb-3">
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-blue"><div class="stat-icon i-blue"><i class="fas fa-inbox"></i></div><div><p class="stat-num"><?= $app_stats['total'] ?></p><p class="stat-lbl">Total</p></div></div></div>
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-blue"><div class="stat-icon i-blue"><i class="fas fa-bell"></i></div><div><p class="stat-num"><?= $app_stats['new'] ?></p><p class="stat-lbl">New</p></div></div></div>
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-purple"><div class="stat-icon i-purple"><i class="fas fa-star"></i></div><div><p class="stat-num"><?= $app_stats['shortlisted'] ?></p><p class="stat-lbl">Shortlisted</p></div></div></div>
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-green"><div class="stat-icon i-green"><i class="fas fa-circle-check"></i></div><div><p class="stat-num"><?= $app_stats['selected'] ?></p><p class="stat-lbl">Selected</p></div></div></div>
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-cyan"><div class="stat-icon i-cyan"><i class="fas fa-calendar-day"></i></div><div><p class="stat-num"><?= $app_stats['today'] ?></p><p class="stat-lbl">Today's</p></div></div></div>
        <div class="col-6 col-md-2 mb-3"><div class="stat-card s-red"><div class="stat-icon i-red"><i class="fas fa-calendar-exclamation"></i></div><div><p class="stat-num"><?= $app_stats['follow_up'] ?></p><p class="stat-lbl">Follow-up</p></div></div></div>
    </div>

    <!-- FILTER BAR -->
    <div class="filter-bar">
        <div class="bar-title"><i class="fas fa-filter"></i> Filter Applications</div>
        <form method="GET" autocomplete="off">
            <input type="hidden" name="tab" value="applications">
            <div class="frow">
                <div class="fg" style="flex:2.5;">
                    <label>Search (Name / Phone / Email / Position)</label>
                    <input type="text" name="search" class="fc" placeholder="Search..." value="<?= htmlspecialchars($f_search) ?>">
                </div>
                <div class="fg">
                    <label>Status</label>
                    <select name="status" class="fc">
                        <option value="">All Status</option>
                        <?php foreach ($APP_STATUS as $k=>$v): ?>
                        <option value="<?=$k?>" <?=$f_status===$k?'selected':''?>><?=$v['label']?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="fg">
                    <label>Department</label>
                    <select name="dept" class="fc">
                        <option value="">All Departments</option>
                        <?php foreach (['Sales','Operations','Marketing','Logistics','Support','Finance','HR','IT','General'] as $d): ?>
                        <option value="<?=$d?>" <?=$f_dept===$d?'selected':''?>><?=$d?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="fg">
                    <label>Assigned To</label>
                    <select name="agent" class="fc">
                        <option value="">All Agents</option>
                        <?php foreach ($employees as $e): ?>
                        <option value="<?=htmlspecialchars($e['name'])?>" <?=$f_agent===$e['name']?'selected':''?>><?=htmlspecialchars($e['name'])?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            <div class="frow">
                <div class="fg" style="max-width:180px;"><label>Applied From</label><input type="date" name="date_from" class="fc" value="<?=htmlspecialchars($f_df)?>"></div>
                <div class="fg" style="max-width:180px;"><label>Applied To</label><input type="date" name="date_to" class="fc" value="<?=htmlspecialchars($f_dt)?>"></div>
                <div class="fg" style="flex:3;"></div>
                <div style="display:flex;gap:8px;align-items:flex-end;">
                    <a href="?tab=applications" class="btn-reset"><i class="fas fa-rotate-left"></i> Reset</a>
                    <button type="submit" class="btn-apply"><i class="fas fa-filter"></i> Apply</button>
                </div>
            </div>
        </form>
    </div>

    <!-- STATUS TABS -->
    <div class="tab-pills">
        <?php $total_all = acnt($con,"SELECT COUNT(*) c FROM career_applications"); ?>
        <a href="?tab=applications" class="tab-pill <?= !$f_status?'active':'' ?>">All (<?=$total_all?>)</a>
        <?php foreach ($APP_STATUS as $k=>$v):
            $tc = acnt($con,"SELECT COUNT(*) c FROM career_applications WHERE status='$k'");
            if (!$tc) continue;
        ?>
        <a href="?tab=applications&status=<?=$k?><?= $f_search?'&search='.urlencode($f_search):'' ?>"
           class="tab-pill <?=$f_status===$k?'active':''?>"
           style="<?=$f_status===$k?"border-color:{$v['color']};color:{$v['color']};background:{$v['bg']};":''?>">
            <?=$v['label']?> (<?=$tc?>)
        </a>
        <?php endforeach; ?>
    </div>

    <!-- APPLICATIONS TABLE -->
    <div class="tbl-wrap-outer">
    <div class="tbl-scroll">
    <table class="at-tbl">
    <thead>
    <tr>
        <th style="min-width:90px;">Ref #</th>
        <th style="min-width:190px;">Candidate</th>
        <th style="min-width:180px;">Position Applied</th>
        <th style="min-width:120px;">Experience</th>
        <th style="min-width:130px;">Skills</th>
        <th style="min-width:130px;">Assigned To</th>
        <th style="min-width:120px;">Status</th>
        <th style="min-width:100px;">Follow-up</th>
        <th style="min-width:115px;">Applied On</th>
        <th style="min-width:270px;">Actions</th>
    </tr>
    </thead>
    <tbody>
    <?php
    $row_count = 0;
    if ($apps_result): while ($app = mysqli_fetch_assoc($apps_result)):
        $row_count++;
        $ref  = 'APP-'.str_pad($app['id'],5,'0',STR_PAD_LEFT);
        $sc   = $APP_STATUS[$app['status']] ?? $APP_STATUS['new'];
        $is_new = $app['status']==='new';
        $fu   = $app['follow_up_date']??null;
        $fu_today = $fu && $fu===date('Y-m-d');
    ?>
    <tr class="<?=$is_new?'row-new':''?>">
        <td>
            <code class="ref-badge"><?=$ref?></code>
            <?php if ($is_new): ?><br><span class="new-tag">NEW</span><?php endif; ?>
        </td>
        <td>
            <strong><?=htmlspecialchars($app['full_name']??'—')?></strong>
            <br><a href="tel:<?=htmlspecialchars($app['phone']??'')?>" style="color:#1e40af;font-size:13px;font-weight:700;text-decoration:none;"><i class="fas fa-phone" style="font-size:10px;"></i> <?=htmlspecialchars($app['phone']??'—')?></a>
            <?php if (!empty($app['email'])): ?><br><span style="color:#64748b;font-size:12px;"><?=htmlspecialchars($app['email'])?></span><?php endif; ?>
            <?php if (!empty($app['location'])): ?><br><span style="color:#94a3b8;font-size:11.5px;"><i class="fas fa-location-dot" style="font-size:10px;"></i> <?=htmlspecialchars($app['location'])?></span><?php endif; ?>
        </td>
        <td>
            <strong style="font-size:13.5px;"><?=htmlspecialchars($app['position_applied']??'—')?></strong>
            <?php if ($app['department']): ?><br><span style="font-size:12px;background:#eff6ff;color:#1e40af;padding:2px 8px;border-radius:5px;font-weight:700;"><?=htmlspecialchars($app['department'])?></span><?php endif; ?>
            <?php if (!empty($app['job_title'])): ?><br><span style="font-size:11.5px;color:#94a3b8;">Job: <?=htmlspecialchars($app['job_title'])?></span><?php endif; ?>
        </td>
        <td>
            <span style="font-size:13px;font-weight:700;"><?=htmlspecialchars($app['experience_years']??'—')?></span>
            <?php if ($app['qualification']): ?><br><span style="font-size:12px;color:#64748b;"><?=htmlspecialchars($app['qualification'])?></span><?php endif; ?>
            <?php if ($app['notice_period']): ?><br><span style="font-size:11.5px;color:#94a3b8;">Notice: <?=htmlspecialchars($app['notice_period'])?></span><?php endif; ?>
        </td>
        <td style="font-size:12px;color:#64748b;max-width:140px;">
            <?php
            $sks = array_slice(array_filter(array_map('trim',explode(',', $app['skills']??''))),0,3);
            foreach ($sks as $sk) echo '<span style="background:#f1f5f9;border:1.5px solid #e2e8f0;padding:2px 7px;border-radius:5px;font-size:11px;font-weight:700;color:#475569;display:inline-block;margin:1px;">'.htmlspecialchars($sk).'</span>';
            ?>
        </td>
        <td>
            <?php if ($app['assigned_to']): ?>
            <span class="assign-tag-ok"><i class="fas fa-user-check" style="font-size:10px;"></i> <?=htmlspecialchars($app['assigned_to'])?></span>
            <?php else: ?>
            <span class="assign-tag-no"><i class="fas fa-user-xmark" style="font-size:10px;"></i> Unassigned</span>
            <?php endif; ?>
        </td>
        <td>
            <span class="status-badge" style="background:<?=$sc['bg']?>;color:<?=$sc['color']?>;border:1.5px solid <?=$sc['border']?>;">
                <?=$sc['label']?>
            </span>
        </td>
        <td>
            <?php if ($fu): ?>
            <span class="fu-tag <?=$fu_today?'urgent':''?>"><i class="fas fa-calendar<?=$fu_today?'-exclamation':''?>"></i> <?=date('d M',strtotime($fu))?></span>
            <?php else: ?>—<?php endif; ?>
        </td>
        <td style="font-size:12.5px;color:#64748b;">
            <?=date('d M Y',strtotime($app['created_at']))?>
            <br><?=date('h:i A',strtotime($app['created_at']))?>
        </td>
        <td>
            <button class="ab ab-view" onclick="openDP(<?=$app['id']?>)"><i class="fas fa-eye"></i> View</button>
            <?php if ($app['resume_path']): ?>
            <a class="ab ab-green" href="?download=<?=$app['id']?>&type=resume"><i class="fas fa-download"></i> Resume</a>
            <?php endif; ?>
            <?php if ($app['cover_letter_path']): ?>
            <a class="ab ab-gray" href="?download=<?=$app['id']?>&type=cover"><i class="fas fa-file-alt"></i> Cover</a>
            <?php endif; ?>
            <button class="ab ab-note" onclick="openDP(<?=$app['id']?>,false,true)"><i class="fas fa-note-sticky"></i> Note</button>
            <button class="ab ab-del" onclick="delApp(<?=$app['id']?>,'<?=addslashes($ref)?>')"><i class="fas fa-trash-alt"></i></button>
        </td>
    </tr>
    <?php endwhile; endif; ?>
    <?php if ($row_count===0): ?>
    <tr><td colspan="10">
        <div style="text-align:center;padding:70px 20px;color:#94a3b8;">
            <i class="fas fa-inbox" style="font-size:52px;opacity:.25;display:block;margin-bottom:16px;"></i>
            <h4 style="font-size:17px;font-weight:800;color:#64748b;margin-bottom:8px;">No Applications Found</h4>
            <p style="font-size:14px;"><?=($f_search||$f_status)?'No results match your filters.':'No applications received yet.'?></p>
        </div>
    </td></tr>
    <?php endif; ?>
    </tbody>
    <tfoot>
    <tr><td colspan="10">Showing <strong><?=$row_count?></strong> application<?=$row_count!=1?'s':''?>
        <?php if ($f_search||$f_status||$f_dept): ?>&nbsp;|&nbsp;<a href="?tab=applications" style="color:#1e40af;font-weight:700;text-decoration:none;"><i class="fas fa-xmark"></i> Clear filters</a><?php endif; ?>
    </td></tr>
    </tfoot>
    </table>
    </div></div>
</div><!-- /applications tab -->

</div><!-- /at-wrap -->

<!-- OVERLAY -->
<div class="dp-overlay" id="dpOv" onclick="closeDP()"></div>

<!-- DETAIL PANEL -->
<div class="dp-panel" id="dpPanel">
    <div class="dp-head">
        <div><h2 id="dpTitle">Loading…</h2><p id="dpSub"></p></div>
        <button class="dp-close" onclick="closeDP()"><i class="fas fa-xmark"></i></button>
    </div>
    <div class="dp-body" id="dpBody">
        <div style="text-align:center;padding:80px;color:#94a3b8;"><i class="fas fa-spinner fa-spin fa-3x"></i></div>
    </div>
</div>

<!-- JOB MODAL -->
<div class="modal-overlay" id="jobModalOv">
<div class="job-modal-box">
    <div class="jmb-head">
        <h3 id="jmbTitle">Post New Job</h3>
        <button class="jmb-close" onclick="closeJobModal()"><i class="fas fa-xmark"></i></button>
    </div>
    <div class="jmb-body">
    <input type="hidden" id="jm-id">
    <div class="row">
        <div class="col-md-8"><div class="form-group"><label class="jm-lbl">Job Title <span class="jm-req">*</span></label><input type="text" id="jm-title" class="jm-inp" placeholder="e.g. Travel Sales Executive"></div></div>
        <div class="col-md-4"><div class="form-group"><label class="jm-lbl">Department <span class="jm-req">*</span></label>
            <select id="jm-dept" class="jm-inp">
                <option value="">-- Select --</option>
                <option>Sales</option><option>Operations</option><option>Marketing</option>
                <option>Logistics</option><option>Support</option><option>Finance</option>
                <option>HR</option><option>IT</option><option>General</option>
            </select>
        </div></div>
        <div class="col-md-4"><div class="form-group"><label class="jm-lbl">Location</label><input type="text" id="jm-loc" class="jm-inp" placeholder="e.g. Bangalore"></div></div>
        <div class="col-md-4"><div class="form-group"><label class="jm-lbl">Job Type</label>
            <select id="jm-jtype" class="jm-inp">
                <option>Full Time</option><option>Part Time</option><option>Contract</option><option>Internship</option><option>Remote</option>
            </select>
        </div></div>
        <div class="col-md-4"><div class="form-group"><label class="jm-lbl">Vacancies</label><input type="number" id="jm-vac" class="jm-inp" min="1" value="1"></div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Experience Required</label><input type="text" id="jm-exp" class="jm-inp" placeholder="e.g. 2-4 years"></div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Salary Range (₹ CTC)</label><input type="text" id="jm-sal" class="jm-inp" placeholder="e.g. 3-5 LPA"></div></div>
        <div class="col-md-12"><div class="form-group"><label class="jm-lbl">Job Description <span class="jm-req">*</span></label>
            <textarea id="jm-desc" class="jm-inp" rows="3" placeholder="Brief overview of the role and what the candidate will do..."></textarea>
        </div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Key Responsibilities</label>
            <textarea id="jm-resp" class="jm-inp" rows="4" placeholder="One responsibility per line&#10;- Manage customer bookings&#10;- Handle sales targets&#10;- Coordinate with operations"></textarea>
            <div class="jm-hint">Each line becomes a bullet point on the careers page</div>
        </div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Requirements</label>
            <textarea id="jm-req" class="jm-inp" rows="4" placeholder="One requirement per line&#10;- Bachelor's degree in any field&#10;- Good communication skills&#10;- Minimum 2 years experience"></textarea>
            <div class="jm-hint">Each line becomes a bullet point on the careers page</div>
        </div></div>
        <div class="col-md-12"><div class="form-group"><label class="jm-lbl">Skills Required (comma-separated)</label>
            <input type="text" id="jm-skills" class="jm-inp" placeholder="e.g. MS Office, Customer Service, GDS, Amadeus, Communication">
            <div class="jm-hint">These will appear as skill chips on the job card and auto-fill when a candidate applies</div>
        </div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Application Deadline</label>
            <input type="date" id="jm-deadline" class="jm-inp" min="<?= date('Y-m-d') ?>">
        </div></div>
        <div class="col-md-6"><div class="form-group"><label class="jm-lbl">Status <span class="jm-req">*</span></label>
            <select id="jm-status" class="jm-inp">
                <option value="active">🟢 Active — Goes LIVE on website now</option>
                <option value="paused">🟡 Paused — Hidden from website</option>
                <option value="closed">🔴 Closed — Position filled</option>
            </select>
        </div></div>
        <div class="col-md-12"><div class="form-group mb-0"><label class="jm-lbl">Posted By (HR Name)</label>
            <input type="text" id="jm-posted-by" class="jm-inp" placeholder="e.g. Ananya from HR">
        </div></div>
    </div>
    <div style="margin-top:24px;display:flex;gap:12px;align-items:center;flex-wrap:wrap;">
        <button class="btn-save-job" id="saveJobBtn" onclick="saveJob()"><i class="fas fa-floppy-disk"></i> Save Job</button>
        <button class="btn-cancel" onclick="closeJobModal()">Cancel</button>
        <span id="jobSaveMsg" style="font-size:13px;font-weight:700;"></span>
    </div>
    </div>
</div>
</div>

<!-- EMAIL MODAL -->
<div class="modal-overlay" id="mailOverlay">
<div class="mail-box">
    <h4><i class="fas fa-envelope" style="color:#1e3a8a;"></i> Send Email to Candidate</h4>
    <input type="hidden" id="mailId">
    <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">To</label>
    <input type="email" id="mailTo" class="mail-input" readonly style="background:#f8fafc;">
    <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">Subject</label>
    <input type="text" id="mailSubject" class="mail-input">
    <label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:4px;">Message</label>
    <textarea id="mailMsg" class="mail-input" rows="4" style="height:auto;min-height:95px;" placeholder="Add a personalised message for the candidate…"></textarea>
    <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:6px;">
        <button class="btn-cancel" onclick="closeMailModal()">Cancel</button>
        <button class="btn-send" id="mailSendBtn" onclick="doSendMail()"><i class="fas fa-paper-plane"></i> Send Email</button>
    </div>
</div>
</div>

<!-- TOAST -->
<div class="at-toast" id="toast"><i class="fas fa-circle-check" id="toastIcon"></i><span id="toastMsg"></span></div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
var PAGE       = 'abra_travels_career_list.php';
var APP_STATUS = <?= json_encode($APP_STATUS) ?>;
var JOB_STATUS = <?= json_encode($JOB_STATUS) ?>;
var EMPLOYEES  = <?= json_encode($employees) ?>;

// ── TOAST ──
var _toastT;
function toast(msg,type){
    type=type||'ok';
    var t=document.getElementById('toast');
    t.className='at-toast show '+type;
    document.getElementById('toastMsg').textContent=msg;
    document.getElementById('toastIcon').className=type==='err'?'fas fa-circle-xmark':type==='inf'?'fas fa-circle-info':'fas fa-circle-check';
    clearTimeout(_toastT);
    _toastT=setTimeout(function(){t.className='at-toast';},4000);
}

function esc(s){if(s==null)return'';return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}
function fmtD(d){if(!d)return'—';try{return new Date(d).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});}catch(e){return d;}}
function fmtDT(d){if(!d)return'—';try{return new Date(d).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'})+' '+new Date(d).toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit',hour12:true});}catch(e){return d;}}

function doPost(action,data){
    return fetch(PAGE+'?ajax='+action,{
        method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded; charset=utf-8'},
        body:new URLSearchParams(data).toString()
    }).then(function(r){if(!r.ok)throw new Error('HTTP '+r.status);return r.text();})
    .then(function(txt){try{return JSON.parse(txt);}catch(e){throw new Error('Bad server response: '+txt.substring(0,100));}});
}

// ── TAB SWITCH ──
function switchTab(tab){
    document.getElementById('tab-jobs').style.display        = tab==='jobs'?'block':'none';
    document.getElementById('tab-applications').style.display = tab!=='jobs'?'block':'none';
    document.querySelectorAll('.main-tab').forEach(function(t,i){
        t.classList.toggle('active', i===(tab==='jobs'?0:1));
    });
    history.replaceState(null,'','?tab='+tab);
}

// ── JOB MODAL ──
function openJobModal(id){
    document.getElementById('jm-id').value='';
    document.getElementById('jm-title').value='';
    document.getElementById('jm-dept').value='';
    document.getElementById('jm-loc').value='';
    document.getElementById('jm-jtype').value='Full Time';
    document.getElementById('jm-vac').value='1';
    document.getElementById('jm-exp').value='';
    document.getElementById('jm-sal').value='';
    document.getElementById('jm-desc').value='';
    document.getElementById('jm-resp').value='';
    document.getElementById('jm-req').value='';
    document.getElementById('jm-skills').value='';
    document.getElementById('jm-deadline').value='';
    document.getElementById('jm-status').value='active';
    document.getElementById('jm-posted-by').value='';
    document.getElementById('jmbTitle').textContent = id?'Edit Job':'Post New Job';
    document.getElementById('jobSaveMsg').textContent='';
    document.getElementById('jobModalOv').classList.add('show');
    if (id) {
        fetch(PAGE+'?ajax=get_job&id='+id).then(r=>r.json()).then(function(d){
            if (!d.success) { toast(d.message||'Could not load job','err'); return; }
            var j=d.data;
            document.getElementById('jm-id').value        = j.id;
            document.getElementById('jm-title').value     = j.title||'';
            document.getElementById('jm-dept').value      = j.department||'';
            document.getElementById('jm-loc').value       = j.location||'';
            document.getElementById('jm-jtype').value     = j.job_type||'Full Time';
            document.getElementById('jm-vac').value       = j.vacancies||1;
            document.getElementById('jm-exp').value       = j.experience||'';
            document.getElementById('jm-sal').value       = j.salary_range||'';
            document.getElementById('jm-desc').value      = j.description||'';
            document.getElementById('jm-resp').value      = j.responsibilities||'';
            document.getElementById('jm-req').value       = j.requirements||'';
            document.getElementById('jm-skills').value    = j.skills_required||'';
            document.getElementById('jm-deadline').value  = j.deadline||'';
            document.getElementById('jm-status').value    = j.status||'active';
            document.getElementById('jm-posted-by').value = j.posted_by||'';
        });
    }
}
function closeJobModal(){ document.getElementById('jobModalOv').classList.remove('show'); }

function saveJob(){
    var title = document.getElementById('jm-title').value.trim();
    if (!title) { toast('Job title is required','err'); return; }
    var dept = document.getElementById('jm-dept').value;
    if (!dept) { toast('Please select a department','err'); return; }
    var desc = document.getElementById('jm-desc').value.trim();
    if (!desc) { toast('Job description is required','err'); return; }
    var btn = document.getElementById('saveJobBtn');
    btn.disabled=true; btn.innerHTML='<i class="fas fa-spinner fa-spin"></i> Saving…';
    doPost('save_job',{
        jid:   document.getElementById('jm-id').value,
        title: title,
        department: dept,
        location: document.getElementById('jm-loc').value,
        job_type: document.getElementById('jm-jtype').value,
        vacancies: document.getElementById('jm-vac').value,
        experience: document.getElementById('jm-exp').value,
        salary_range: document.getElementById('jm-sal').value,
        description: desc,
        responsibilities: document.getElementById('jm-resp').value,
        requirements: document.getElementById('jm-req').value,
        skills_required: document.getElementById('jm-skills').value,
        deadline: document.getElementById('jm-deadline').value,
        status: document.getElementById('jm-status').value,
        posted_by: document.getElementById('jm-posted-by').value
    }).then(function(d){
        btn.disabled=false; btn.innerHTML='<i class="fas fa-floppy-disk"></i> Save Job';
        if (d.success) { toast(d.message||'Job saved!','ok'); closeJobModal(); setTimeout(function(){location.reload();},1400); }
        else toast('Error: '+(d.message||'Save failed'),'err');
    }).catch(function(e){ btn.disabled=false; btn.innerHTML='<i class="fas fa-floppy-disk"></i> Save Job'; toast(e.message,'err'); });
}

// ── TOGGLE JOB STATUS ──
function toggleJobStatus(id,status){
    var labels={'active':'Activate','paused':'Pause','closed':'Close'};
    if (!confirm(labels[status]+' this job?')) return;
    doPost('toggle_job',{id:id,status:status})
        .then(function(d){ if(d.success){toast('Job '+status,'ok');setTimeout(function(){location.reload();},1200);}else toast(d.message||'Error','err'); })
        .catch(function(e){toast(e.message,'err');});
}

function deleteJob(id,title){
    if (!confirm('Delete job "'+title+'"?\nThis will NOT delete applications already received.')) return;
    doPost('delete_job',{id:id})
        .then(function(d){ if(d.success){toast('Job deleted','ok');setTimeout(function(){location.reload();},1200);}else toast(d.message||'Error','err'); })
        .catch(function(e){toast(e.message,'err');});
}

// ── APPLICATION DETAIL PANEL ──
var _dpId=null;
function closeDP(){ document.getElementById('dpOv').classList.remove('show'); document.getElementById('dpPanel').classList.remove('open'); _dpId=null; }

function openDP(id,scrollAssign,scrollNote){
    _dpId=id;
    document.getElementById('dpOv').classList.add('show');
    document.getElementById('dpPanel').classList.add('open');
    document.getElementById('dpBody').innerHTML='<div style="text-align:center;padding:80px;color:#94a3b8;"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';

    fetch(PAGE+'?ajax=get_app&id='+id)
        .then(function(r){if(!r.ok)throw new Error('HTTP '+r.status);return r.text();})
        .then(function(txt){
            var res; try{res=JSON.parse(txt);}catch(e){throw new Error('Bad server response');}
            if(!res.success){document.getElementById('dpBody').innerHTML='<div style="padding:40px;text-align:center;color:#dc2626;">'+esc(res.message||'Error')+'</div>';return;}
            renderDP(res.data);
            if(scrollAssign) setTimeout(function(){var el=document.getElementById('sec-assign');if(el)el.scrollIntoView({behavior:'smooth',block:'center'});},380);
            if(scrollNote)   setTimeout(function(){var el=document.getElementById('sec-notes');if(el)el.scrollIntoView({behavior:'smooth',block:'center'});},380);
        })
        .catch(function(e){document.getElementById('dpBody').innerHTML='<div style="padding:40px;text-align:center;color:#dc2626;">'+esc(e.message)+'</div>';});
}

function renderDP(d){
    var ref  = 'APP-'+String(d.id).padStart(5,'0');
    var sc   = APP_STATUS[d.status]||APP_STATUS['new'];
    document.getElementById('dpTitle').textContent = d.full_name||'Applicant';
    document.getElementById('dpSub').textContent   = ref+' · '+esc(d.position_applied||'Open Application')+' · '+sc.label;

    var h='';

    // STATUS CHANGE
    h+='<div class="dp-section"><h4><i class="fas fa-toggle-on"></i> Candidate Status</h4>';
    h+='<div style="font-size:13px;color:#64748b;margin-bottom:9px;">Current: <strong style="color:'+sc.color+'">'+esc(sc.label)+'</strong></div>';
    h+='<div class="sq-btns">';
    Object.keys(APP_STATUS).forEach(function(k){
        var s=APP_STATUS[k], active=d.status===k;
        h+='<button class="sq-btn'+(active?' active':'')+'" style="border-color:'+s.color+';color:'+(active?'#fff':s.color)+';background:'+(active?s.color:s.bg)+';" onclick="qStatus('+d.id+',\''+k+'\')">'+esc(s.label)+'</button>';
    });
    h+='</div></div>';

    // CANDIDATE INFO
    h+='<div class="dp-section"><h4><i class="fas fa-user"></i> Candidate Details</h4><div class="dp-grid">';
    h+='<div class="dp-field"><label>Full Name</label><span>'+esc(d.full_name||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Mobile</label><span><a href="tel:'+esc(d.phone||'')+'" style="color:#1e40af;font-weight:700;text-decoration:none;"><i class="fas fa-phone" style="font-size:11px;"></i> '+esc(d.phone||'—')+'</a></span></div>';
    h+='<div class="dp-field"><label>Email</label><span>'+(d.email?'<a href="mailto:'+esc(d.email)+'" style="color:#1e40af;text-decoration:none;">'+esc(d.email)+'</a>':'—')+'</span></div>';
    h+='<div class="dp-field"><label>Current City</label><span>'+esc(d.location||'—')+'</span></div>';
    h+='<div class="dp-field"><label>LinkedIn</label><span>'+(d.linkedin_url?'<a href="'+esc(d.linkedin_url)+'" target="_blank" style="color:#1e40af;">View Profile</a>':'—')+'</span></div>';
    h+='<div class="dp-field"><label>Portfolio</label><span>'+(d.portfolio_url?'<a href="'+esc(d.portfolio_url)+'" target="_blank" style="color:#1e40af;">View Website</a>':'—')+'</span></div>';
    h+='<div class="dp-field"><label>How Heard</label><span>'+esc(d.how_heard||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Applied On</label><span>'+fmtDT(d.created_at)+'</span></div>';
    h+='</div></div>';

    // POSITION
    h+='<div class="dp-section"><h4><i class="fas fa-briefcase"></i> Position Details</h4><div class="dp-grid">';
    h+='<div class="dp-field"><label>Position Applied</label><span style="font-weight:900;color:#1e3a8a;">'+esc(d.position_applied||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Department</label><span>'+esc(d.department||'—')+'</span></div>';
    if(d.job_title) h+='<div class="dp-field"><label>Specific Job Posting</label><span>'+esc(d.job_title)+'</span></div>';
    h+='<div class="dp-field"><label>Joining Date</label><span>'+fmtD(d.availability_date)+'</span></div>';
    h+='<div class="dp-field"><label>Notice Period</label><span>'+esc(d.notice_period||'—')+'</span></div>';
    h+='</div></div>';

    // PROFESSIONAL
    h+='<div class="dp-section"><h4><i class="fas fa-chart-bar"></i> Professional Background</h4><div class="dp-grid">';
    h+='<div class="dp-field"><label>Total Experience</label><span>'+esc(d.experience_years||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Qualification</label><span>'+esc(d.qualification||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Current Company</label><span>'+esc(d.current_company||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Current CTC</label><span>'+esc(d.current_ctc||'—')+'</span></div>';
    h+='<div class="dp-field"><label>Expected CTC</label><span style="color:#16a34a;font-weight:800;">'+esc(d.expected_ctc||'—')+'</span></div>';
    h+='</div>';
    if(d.skills){
        var sks=d.skills.split(',').map(s=>s.trim()).filter(Boolean);
        if(sks.length){
            h+='<div style="margin-top:12px;"><label style="font-size:11px;color:#94a3b8;font-weight:700;text-transform:uppercase;display:block;margin-bottom:8px;">Skills</label>';
            h+='<div style="display:flex;flex-wrap:wrap;gap:7px;">';
            sks.forEach(function(s){h+='<span style="background:#eff6ff;border:1.5px solid #bfdbfe;color:#1e40af;padding:5px 12px;border-radius:8px;font-size:13px;font-weight:700;">'+esc(s)+'</span>';});
            h+='</div></div>';
        }
    }
    h+='</div>';

    // COVER NOTE
    if(d.cover_letter_text){
        h+='<div class="dp-section"><h4><i class="fas fa-envelope-open-text"></i> Cover Note</h4><div class="dp-infobox">'+esc(d.cover_letter_text)+'</div></div>';
    }

    // DOCUMENTS
    h+='<div class="dp-section"><h4><i class="fas fa-file-arrow-down"></i> Documents</h4><div style="display:flex;gap:10px;flex-wrap:wrap;">';
    if(d.resume_path) h+='<a href="?download='+d.id+'&type=resume" class="qs-btn qs-dl"><i class="fas fa-download"></i> Download Resume</a>';
    else h+='<span style="font-size:13px;color:#dc2626;font-weight:700;"><i class="fas fa-triangle-exclamation"></i> No resume uploaded</span>';
    if(d.cover_letter_path) h+='<a href="?download='+d.id+'&type=cover" class="qs-btn qs-dl2"><i class="fas fa-file-alt"></i> Download Cover Letter</a>';
    h+='</div></div>';

    // ASSIGN + TICKET
    h+='<div class="dp-section" id="sec-assign"><h4><i class="fas fa-user-tag"></i> Assign to HR Agent &amp; Raise Ticket</h4>';
    h+='<div style="font-size:13px;color:#64748b;margin-bottom:10px;">Currently: <strong style="color:#1e293b;">'+(d.assigned_to||'<span style="color:#dc2626;">Unassigned</span>')+'</strong></div>';
    h+='<div style="display:flex;gap:9px;align-items:center;flex-wrap:wrap;">';
    h+='<select id="dpAgentSel" class="assign-select"><option value="">-- Select HR Agent --</option>';
    EMPLOYEES.forEach(function(e){ h+='<option value="'+e.id+'" data-name="'+esc(e.name)+'" data-email="'+esc(e.email)+'" '+(d.assigned_to===e.name?'selected':'')+'>'+esc(e.name)+'</option>'; });
    h+='</select>';
    h+='<button class="btn-do-assign" onclick="doAssign('+d.id+')"><i class="fas fa-user-check"></i> Assign &amp; Raise Ticket</button>';
    h+='</div>';
    h+='<p style="font-size:12px;color:#94a3b8;margin-top:8px;"><i class="fas fa-circle-info"></i> Assigns this application to an HR agent AND auto-creates a support ticket — same as the raise-a-ticket system.</p>';
    h+='</div>';

    // NOTES + FOLLOW-UP
    h+='<div class="dp-section" id="sec-notes"><h4><i class="fas fa-note-sticky"></i> Admin Notes &amp; Follow-up</h4>';
    h+='<label style="font-size:12px;font-weight:700;color:#374151;display:block;margin-bottom:5px;">Internal Notes</label>';
    h+='<textarea class="dp-textarea" id="dpNotes" placeholder="e.g. Called candidate, interview scheduled for Monday at 11am…">'+esc(d.admin_notes||'')+'</textarea>';
    h+='<label style="font-size:12px;font-weight:700;color:#374151;display:block;margin:10px 0 5px;">Follow-up Date</label>';
    h+='<input type="date" id="dpFollowup" style="border:2px solid #e2e8f0;border-radius:9px;padding:8px 13px;font-size:14px;height:44px;color:#1e293b;font-family:Poppins,sans-serif;width:auto;" value="'+(d.follow_up_date||'')+'"/>';
    h+='<br><button class="btn-save-note" onclick="saveNotes('+d.id+')"><i class="fas fa-floppy-disk"></i> Save Notes &amp; Follow-up</button>';
    h+='</div>';

    // TIMELINE
    h+='<div class="dp-section"><h4><i class="fas fa-clock-rotate-left"></i> Timeline</h4>';
    h+='<div style="background:#f8fafc;border:2px solid #e2e8f0;border-radius:11px;padding:14px 18px;font-size:13.5px;color:#64748b;">';
    h+='<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-paper-plane" style="color:#1e40af;width:18px;"></i> Application Received</span><strong style="color:#1e293b;">'+fmtDT(d.created_at)+'</strong></div>';
    if(d.updated_at&&d.updated_at!==d.created_at) h+='<div style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #f1f5f9;"><span><i class="fas fa-pen-to-square" style="color:#d97706;width:18px;"></i> Last Updated</span><strong style="color:#1e293b;">'+fmtDT(d.updated_at)+'</strong></div>';
    if(d.follow_up_date) h+='<div style="display:flex;justify-content:space-between;padding:7px 0;"><span><i class="fas fa-calendar-check" style="color:#16a34a;width:18px;"></i> Follow-up</span><strong style="color:#16a34a;">'+fmtD(d.follow_up_date)+'</strong></div>';
    h+='</div></div>';

    // QUICK ACTIONS
    h+='<div class="action-strip">';
    h+='<a href="tel:'+esc(d.phone||'')+'" class="qs-btn qs-call"><i class="fas fa-phone"></i> Call</a>';
    if(d.email) h+='<button onclick="openMailModal('+d.id+',\''+esc(d.email)+'\',\''+esc(d.full_name)+'\',\''+String(d.id).padStart(5,'0')+'\')" class="qs-btn qs-mail"><i class="fas fa-envelope"></i> Email</button>';
    if(d.resume_path) h+='<a href="?download='+d.id+'&type=resume" class="qs-btn qs-dl"><i class="fas fa-download"></i> Resume</a>';
    h+='<button onclick="genPDF('+d.id+')" class="qs-btn qs-pdf"><i class="fas fa-file-pdf"></i> PDF</button>';
    h+='<button onclick="delApp('+d.id+',\'APP-'+String(d.id).padStart(5,'0')+'\')" class="qs-btn qs-del"><i class="fas fa-trash-alt"></i> Delete</button>';
    h+='</div>';

    document.getElementById('dpBody').innerHTML=h;
}

function qStatus(id,status){
    doPost('update_status',{id:id,status:status})
        .then(function(d){
            if(d.success){toast('Status → '+APP_STATUS[status].label,'ok');setTimeout(function(){openDP(id);location.reload();},1800);}
            else toast('Error: '+(d.message||'Failed'),'err');
        }).catch(function(e){toast(e.message,'err');});
}

function doAssign(id){
    var sel=document.getElementById('dpAgentSel');
    var empId=sel.value;
    var empName=sel.options[sel.selectedIndex]?(sel.options[sel.selectedIndex].dataset.name||sel.options[sel.selectedIndex].text):'';
    var empEmail=sel.options[sel.selectedIndex]?(sel.options[sel.selectedIndex].dataset.email||''):'';
    if(!empId){toast('Please select an HR agent','err');return;}
    var btn=document.querySelector('.btn-do-assign');
    btn.disabled=true; btn.innerHTML='<i class="fas fa-spinner fa-spin"></i> Processing…';
    doPost('assign_and_ticket',{id:id,employee_id:empId,employee_name:empName,employee_email:empEmail})
        .then(function(d){
            btn.disabled=false; btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket';
            if(d.success){toast(d.message||'Assigned!','ok');setTimeout(function(){location.reload();},2000);}
            else toast('Error: '+(d.message||'Failed'),'err');
        }).catch(function(e){btn.disabled=false;btn.innerHTML='<i class="fas fa-user-check"></i> Assign &amp; Raise Ticket';toast(e.message,'err');});
}

function saveNotes(id){
    var notes=document.getElementById('dpNotes').value;
    var fdate=document.getElementById('dpFollowup').value;
    doPost('save_notes',{id:id,notes:notes,follow_up_date:fdate})
        .then(function(d){toast(d.success?'Notes saved!':'Save failed','ok');})
        .catch(function(e){toast(e.message,'err');});
}

function delApp(id,ref){
    if(!confirm('Delete application '+ref+'?\nResume files will also be deleted. This cannot be undone.')) return;
    doPost('delete_app',{id:id})
        .then(function(d){
            if(d.success){toast('Application '+ref+' deleted','ok');closeDP();setTimeout(function(){location.reload();},1300);}
            else toast('Error: '+(d.message||'Delete failed'),'err');
        }).catch(function(e){toast(e.message,'err');});
}

// EMAIL MODAL
function openMailModal(id,email,name,refPad){
    document.getElementById('mailId').value=id;
    document.getElementById('mailTo').value=email;
    document.getElementById('mailSubject').value='Your Application Update — Abra Tours & Travels (APP-'+refPad+')';
    document.getElementById('mailMsg').value='';
    document.getElementById('mailOverlay').classList.add('show');
}
function closeMailModal(){document.getElementById('mailOverlay').classList.remove('show');}
function doSendMail(){
    var id=document.getElementById('mailId').value;
    var sub=document.getElementById('mailSubject').value.trim();
    var msg=document.getElementById('mailMsg').value;
    var btn=document.getElementById('mailSendBtn');
    if(!sub){toast('Please enter a subject','err');return;}
    btn.disabled=true; btn.innerHTML='<i class="fas fa-spinner fa-spin"></i> Sending…';
    doPost('send_email',{id:id,subject:sub,custom_message:msg})
        .then(function(d){
            btn.disabled=false; btn.innerHTML='<i class="fas fa-paper-plane"></i> Send Email';
            if(d.success){toast(d.message||'Email sent!','ok');closeMailModal();}
            else toast('Email failed: '+(d.message||'Check mail config'),'err');
        }).catch(function(e){btn.disabled=false;btn.innerHTML='<i class="fas fa-paper-plane"></i> Send Email';toast(e.message,'err');});
}

// ── GENERATE PDF (opens print window) ────────────────────────────────────────
function genPDF(id) {
    toast('Preparing PDF…', 'inf');
    fetch(PAGE + '?ajax=get_detail&id=' + id)
        .then(function(r) { return r.text(); })
        .then(function(txt) {
            var res = JSON.parse(txt);
            if (!res.success) { toast('Could not load: ' + res.message, 'err'); return; }
            doPrint(res.data);
        })
        .catch(function(e) { toast('PDF error: ' + e.message, 'err'); });
}

function doPrint(d) {
    var ref = d.ticket_ref || 'APP-' + String(d.id).padStart(5, '0');
    var sc = STATUS_CFG[d.status] || STATUS_CFG['new'];
    var today = new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    
    var css = '<style>body{font-family:Arial,sans-serif;margin:0;padding:0;color:#1e293b;font-size:13px;}.page{max-width:800px;margin:0 auto;padding:24px;}.hdr{background:linear-gradient(135deg,#0f766e,#0d5c56);padding:20px 28px;border-radius:12px;display:flex;align-items:center;gap:18px;margin-bottom:22px;}.brand{color:#fff;} .brand h1{font-size:1.4rem;font-weight:900;margin:0;} .brand p{font-size:12px;margin:4px 0 0;opacity:.78;}.gen-info{margin-left:auto;text-align:right;color:rgba(255,255,255,.8);font-size:12px;}.ref-bar{display:flex;justify-content:space-between;align-items:center;background:#f8fafc;border:2px solid #e2e8f0;border-radius:10px;padding:12px 18px;margin-bottom:20px;}.ref{font-size:1.15rem;font-weight:900;color:#0f766e;}.s-badge{padding:5px 14px;border-radius:20px;font-size:12.5px;font-weight:700;display:inline-block;}.sec{margin-bottom:20px;}.sec h3{font-size:13px;font-weight:800;color:#0f766e;border-bottom:2px solid #99f6e4;padding-bottom:8px;margin-bottom:12px;}.g2{display:grid;grid-template-columns:1fr 1fr;gap:10px;}.fld label{font-size:10.5px;color:#94a3b8;font-weight:700;text-transform:uppercase;letter-spacing:.4px;display:block;margin-bottom:3px;}.fld span{font-size:13.5px;font-weight:600;}.note-box{background:#f8fafc;border:2px solid #e2e8f0;border-radius:9px;padding:12px 15px;font-size:13px;line-height:1.7;white-space:pre-wrap;}.footer{text-align:center;font-size:11.5px;color:#94a3b8;border-top:2px solid #e2e8f0;padding-top:14px;margin-top:22px;}@media print{.page{padding:12px;}}</style>';
    
    var body = '';
    body += '<div class="hdr"><div class="brand"><h1>Abra Tours &amp; Travels</h1><p>Career Application Report</p></div><div class="gen-info"><div><strong>Application: ' + esc(ref) + '</strong></div><div style="font-size:11px;margin-top:2px;">Generated: ' + today + '</div></div></div>';
    body += '<div class="ref-bar"><div><div class="ref">' + esc(ref) + '</div><small style="font-size:12px;color:#64748b;">Position: ' + esc(d.position || '—') + '</small></div><span class="s-badge" style="background:' + sc.bg + ';color:' + sc.color + ';border:1.5px solid ' + sc.border + ';">' + esc(sc.label) + '</span></div>';
    body += '<div class="sec"><h3>👤 Candidate Information</h3><div class="g2"><div class="fld"><label>Full Name</label><span>' + esc(d.name || '—') + '</span></div><div class="fld"><label>Mobile</label><span>' + esc(d.phone || '—') + '</span></div><div class="fld"><label>Email</label><span>' + esc(d.email || '—') + '</span></div><div class="fld"><label>Position Applied</label><span>' + esc(d.position || '—') + '</span></div><div class="fld"><label>Experience</label><span>' + esc(d.experience || '—') + '</span></div><div class="fld"><label>Current Location</label><span>' + esc(d.location || '—') + '</span></div><div class="fld"><label>Created By</label><span>' + esc(d.created_by_name || '—') + '</span></div><div class="fld"><label>Assigned To</label><span>' + esc(d.assigned_to || 'Unassigned') + '</span></div></div></div>';
    
    if (d.cover_letter) body += '<div class="sec"><h3>💬 Cover Letter</h3><div class="note-box">' + esc(d.cover_letter) + '</div></div>';
    if (d.admin_notes) {
        body += '<div class="sec"><h3>📝 Admin Notes</h3><div class="note-box">' + esc(d.admin_notes) + '</div>';
        if (d.follow_up_date) body += '<div style="margin-top:8px;font-size:13px;"><strong>Follow-up:</strong> ' + fmtD(d.follow_up_date) + '</div>';
        body += '</div>';
    }
    
    body += '<div class="footer">Abra Tours &amp; Travels | abra-travels.com | Application Ref: ' + esc(ref) + '</div>';
    
    var html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Application ' + esc(ref) + '</title>' + css + '<style>@page{margin:15mm;size:A4;}</style></head><body><div class="page">' + body + '</div></body></html>';
    var blob = new Blob([html], { type: 'text/html' });
    var url = URL.createObjectURL(blob);
    var w = window.open(url, '_blank');
    if (w) {
        w.onload = function() {
            setTimeout(function() { w.print(); }, 500);
        };
    }
    setTimeout(function() { URL.revokeObjectURL(url); }, 5000);
    toast('PDF opened — use Print → Save as PDF', 'ok');
}

document.addEventListener('keydown',function(e){if(e.key==='Escape'){closeDP();closeMailModal();document.getElementById('jobModalOv').classList.remove('show');}});
document.getElementById('jobModalOv').addEventListener('click',function(e){if(e.target===this)closeJobModal();});
document.getElementById('mailOverlay').addEventListener('click',function(e){if(e.target===this)closeMailModal();});
</script>
</body>
</html>