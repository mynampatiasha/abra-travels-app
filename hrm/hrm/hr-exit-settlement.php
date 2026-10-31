<?php
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
mysqli_report(MYSQLI_REPORT_OFF);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require_once('hr-exit-doc-render.php');

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// Self-healing: ensure the settlement table and the document custom-content
// column exist even if hr-exit-migrate.php was never run on this install.
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_exit_settlement (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL UNIQUE,
    pending_salary DECIMAL(12,2) DEFAULT 0,
    leave_encashment DECIMAL(12,2) DEFAULT 0,
    bonus_incentive DECIMAL(12,2) DEFAULT 0,
    gratuity_amount DECIMAL(12,2) DEFAULT 0,
    pension_amount DECIMAL(12,2) DEFAULT 0,
    severance_pay DECIMAL(12,2) DEFAULT 0,
    loan_recovery DECIMAL(12,2) DEFAULT 0,
    notice_shortfall_deduction DECIMAL(12,2) DEFAULT 0,
    other_deductions DECIMAL(12,2) DEFAULT 0,
    net_amount DECIMAL(12,2) DEFAULT 0,
    notes TEXT DEFAULT NULL,
    status ENUM('pending','approved') DEFAULT 'pending',
    approved_by VARCHAR(255) DEFAULT NULL,
    approved_at DATETIME DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$chk_cc = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'custom_content'");
if ($chk_cc && mysqli_num_rows($chk_cc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_documents ADD COLUMN custom_content LONGTEXT DEFAULT NULL");
}

$chk_status = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
if ($chk_status && mysqli_num_rows($chk_status) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_documents ADD COLUMN status ENUM('draft', 'approved', 'declined') DEFAULT 'draft'");
}

$chk_doctype = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'doc_type'");
if ($chk_doctype) {
    $dt_col = mysqli_fetch_assoc($chk_doctype);
    if ($dt_col && stripos($dt_col['Type'], 'enum') !== false) {
        mysqli_query($con, "ALTER TABLE hr_exit_documents MODIFY COLUMN doc_type VARCHAR(100) NOT NULL");
    }
}

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_exit_document_templates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    doc_code VARCHAR(100) NOT NULL UNIQUE,
    doc_name VARCHAR(255) NOT NULL,
    template_html LONGTEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$c_templates = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_document_templates"));
if ($c_templates['c'] == 0) {
    $defaults = [
        'relieving_letter' => [
            'name' => 'Relieving Letter',
            'html' => '<p>Dear [EMPLOYEE_NAME],</p><p>This has reference to your resignation letter.</p><p>We would like to inform you that your resignation has been accepted and you are relieved from the services of <strong>[COMPANY_NAME]</strong> at the close of working hours on <strong>[LAST_WORKING_DAY]</strong>.</p><p>We confirm that you have returned all company assets and completed the necessary handover procedures.</p><p>We thank you for your contribution to the company and wish you all the best for your future endeavors.</p>'
        ],
        'experience_certificate' => [
            'name' => 'Experience Certificate',
            'html' => '<p><strong>TO WHOMSOEVER IT MAY CONCERN</strong></p><br><p>This is to certify that <strong>[EMPLOYEE_NAME]</strong> was employed with <strong>[COMPANY_NAME]</strong> from <strong>[JOINING_DATE]</strong> to <strong>[LAST_WORKING_DAY]</strong>.</p><p>At the time of leaving, their designation was <strong>[DESIGNATION]</strong> in the <strong>[DEPARTMENT]</strong>.</p><p>During their tenure with us, we found them to be sincere, dedicated, and hardworking. Their conduct was professional and they exhibited good character.</p><p>We wish them success in their future endeavors.</p>'
        ],
        'settlement_statement' => [
            'name' => 'Full & Final Settlement Statement',
            'html' => '<p>Dear [EMPLOYEE_NAME],</p><p>Please find below the details of your Full & Final Settlement calculation as of your last working day (<strong>[LAST_WORKING_DAY]</strong>).</p>[SETTLEMENT_TABLE]<p>If you have any queries regarding this statement, please reach out to the HR department.</p>'
        ],
        'termination_letter' => [
            'name' => 'Termination Letter',
            'html' => '<p>Dear <strong>[EMPLOYEE_NAME]</strong>,</p><p>This letter is to formally notify you that your employment with <strong>[COMPANY_NAME]</strong> is being terminated, effective at the close of business on <strong>[LAST_WORKING_DAY]</strong>.</p><p>This decision has been made after careful consideration and in accordance with company policies. Your final Full & Final (F&F) settlement, including any applicable pending salary, leave encashment, and deductions, will be processed as per company guidelines. Please refer to your Settlement Statement for a detailed breakdown.</p><p>You are required to hand over all company assets—including your ID card, laptop, access keys, and any other company property—to the HR or IT department prior to your departure. You are also reminded of your ongoing obligations under your employment agreement regarding confidentiality and company data.</p><p>We wish you the best in your future endeavors.</p>'
        ],
        'retirement_confirmation_letter' => [
            'name' => 'Retirement Confirmation',
            'html' => '<p>Dear <strong>[EMPLOYEE_NAME]</strong>,</p><p>As you approach your final working day with us on <strong>[LAST_WORKING_DAY]</strong>, we want to formally acknowledge your upcoming retirement from <strong>[COMPANY_NAME]</strong>.</p><p>Over the years, your dedication, hard work, and invaluable contributions have played a significant role in our success. It has been a privilege to work alongside you.</p><p>Your Full & Final Settlement, including your retirement benefits, will be processed in accordance with company policy. Our HR team will be in touch to assist you with the necessary exit formalities and paperwork.</p><p>We wish you a very happy, healthy, and fulfilling retirement. Thank you for your exceptional service.</p>'
        ],
        'non_renewal_notification' => [
            'name' => 'Non Renewal Notification',
            'html' => '<p>Dear <strong>[EMPLOYEE_NAME]</strong>,</p><p>We are writing to formally notify you that your current employment contract with <strong>[COMPANY_NAME]</strong>, which is scheduled to expire on <strong>[LAST_WORKING_DAY]</strong>, will not be renewed.</p><p>We appreciate the contributions you have made during your time with us. Please note that this decision is in alignment with the terms of your employment agreement.</p><p>Your final settlement, including any outstanding salary and applicable benefits, will be processed as per company policy and finalized after your last working day, provided all exit and handover formalities are completed.</p><p>We wish you all the best in your future professional endeavors.</p>'
        ]
    ];
    foreach ($defaults as $code => $data) {
        $c = mysqli_real_escape_string($con, $code);
        $n = mysqli_real_escape_string($con, $data['name']);
        $h = mysqli_real_escape_string($con, $data['html']);
        mysqli_query($con, "INSERT IGNORE INTO hr_exit_document_templates (doc_code, doc_name, template_html) VALUES ('$c', '$n', '$h')");
    }
}

$chk_cc = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'custom_content'");
if ($chk_cc && mysqli_num_rows($chk_cc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_documents ADD COLUMN custom_content LONGTEXT DEFAULT NULL");
}

function qFetch($con, $sql) {
    $r = mysqli_query($con, $sql);
    return ($r instanceof mysqli_result) ? mysqli_fetch_assoc($r) : null;
}

// Files a fully-approved exit document into the employee's document library —
// same employee_id/document_type/filename/filepath pattern hr-exit-handover.php
// uses for the clearance certificate, so it shows up alongside it consistently.
function fileExitDocumentToEmployeeDocuments($con, $exit_id, $doc_type, $token) {
    $empIdRow = qFetch($con, "SELECT e.employee_id FROM hr_exit_requests r JOIN hr_employees e ON e.id=r.employee_id WHERE r.id=$exit_id LIMIT 1");
    if (!$empIdRow || empty($empIdRow['employee_id'])) return;
    $eid_e = mysqli_real_escape_string($con, $empIdRow['employee_id']);
    $dt_label = ucwords(str_replace('_', ' ', $doc_type));
    $dt_e = mysqli_real_escape_string($con, $dt_label);
    $fn_e = mysqli_real_escape_string($con, $dt_label . '.pdf');
    $fp_e = mysqli_real_escape_string($con, 'hr-exit-documents.php?token=' . $token);
    $exists = qFetch($con, "SELECT id FROM hr_employee_documents WHERE employee_id='$eid_e' AND document_type='$dt_e' LIMIT 1");
    if ($exists) {
        mysqli_query($con, "UPDATE hr_employee_documents SET filename='$fn_e', filepath='$fp_e' WHERE id=" . intval($exists['id']));
    } else {
        mysqli_query($con, "INSERT INTO hr_employee_documents (employee_id, document_type, filename, filepath) VALUES ('$eid_e', '$dt_e', '$fn_e', '$fp_e')");
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];
    $exit_id = intval($_POST['exit_id'] ?? 0);
    
    if ($exit_id > 0) {
        if ($action === 'generate_document') {
            $doc_type = mysqli_real_escape_string($con, $_POST['doc_type']);
            $token = bin2hex(random_bytes(32));
            $requires_signature = isset($_POST['requires_signature']) && $_POST['requires_signature'] == '1' ? 1 : 0;

            // Check if status column exists yet (migration script might not have run)
            $status_col_exists = false;
            $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
            if ($chk && mysqli_num_rows($chk) > 0) $status_col_exists = true;

            if ($status_col_exists) {
                $q = "INSERT INTO hr_exit_documents (exit_id, doc_type, token, generated_by, status, requires_signature,
                      employee_signature_data, employee_signed_by, employee_signed_at, hr_released_by, hr_released_at, hr_accepted_by, hr_accepted_at)
                      VALUES ($exit_id, '$doc_type', '$token', '$currentUserName', 'draft', $requires_signature,
                      NULL, NULL, NULL, NULL, NULL, NULL, NULL)
                      ON DUPLICATE KEY UPDATE
                      token='$token', generated_by='$currentUserName', generated_at=NOW(), status='draft', requires_signature=$requires_signature,
                      employee_signature_data=NULL, employee_signed_by=NULL, employee_signed_at=NULL,
                      hr_released_by=NULL, hr_released_at=NULL, hr_accepted_by=NULL, hr_accepted_at=NULL";
            } else {
                $q = "INSERT INTO hr_exit_documents (exit_id, doc_type, token, generated_by)
                      VALUES ($exit_id, '$doc_type', '$token', '$currentUserName')
                      ON DUPLICATE KEY UPDATE
                      token='$token', generated_by='$currentUserName', generated_at=NOW()";
            }

            $res = mysqli_query($con, $q);
            if (!$res) die("MySQL Error in generate_document: " . mysqli_error($con) . " | Query: " . $q);
            mysqli_query($con, "UPDATE hr_exit_requests SET status='documents' WHERE id=$exit_id AND status IN ('handover', 'interview_settlement')");
            
        } elseif ($action === 'approve_document') {
            $doc_id = intval($_POST['doc_id']);
            $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
            if ($chk && mysqli_num_rows($chk) > 0) {
                $doc = qFetch($con, "SELECT doc_type, token, requires_signature FROM hr_exit_documents WHERE id=$doc_id AND exit_id=$exit_id LIMIT 1");
                if (!$doc) {
                    die("DEBUG approve_document: no row found for id=$doc_id AND exit_id=$exit_id. Query: SELECT doc_type, token, requires_signature FROM hr_exit_documents WHERE id=$doc_id AND exit_id=$exit_id LIMIT 1");
                }
                if (!empty($doc['requires_signature'])) {
                    // Signature required — release it to the employee to sign instead of approving outright.
                    $by_e = mysqli_real_escape_string($con, $currentUserName);
                    $r1 = mysqli_query($con, "UPDATE hr_exit_documents SET status='pending_signature', hr_released_by='$by_e', hr_released_at=NOW() WHERE id=$doc_id");
                    if (!$r1) die("MySQL Error in approve_document (release): " . mysqli_error($con));
                } else {
                    $r2 = mysqli_query($con, "UPDATE hr_exit_documents SET status='approved' WHERE id=$doc_id");
                    if (!$r2) die("MySQL Error in approve_document (direct approve): " . mysqli_error($con));
                    fileExitDocumentToEmployeeDocuments($con, $exit_id, $doc['doc_type'], $doc['token']);
                }
            } else {
                die("DEBUG approve_document: 'status' column not found on hr_exit_documents.");
            }
        } elseif ($action === 'accept_document') {
            // Final HR acceptance after the employee has digitally signed — the only
            // path (besides the no-signature branch above) that files into hr_employee_documents.
            $doc_id = intval($_POST['doc_id']);
            $doc = qFetch($con, "SELECT doc_type, token, employee_signature_data FROM hr_exit_documents WHERE id=$doc_id AND exit_id=$exit_id AND status='pending_hr_final' LIMIT 1");
            if (!$doc) {
                die("DEBUG accept_document: no row found for id=$doc_id AND exit_id=$exit_id AND status='pending_hr_final'.");
            }
            if (!empty($doc['employee_signature_data'])) {
                $by_e = mysqli_real_escape_string($con, $currentUserName);
                $r3 = mysqli_query($con, "UPDATE hr_exit_documents SET status='approved', hr_accepted_by='$by_e', hr_accepted_at=NOW() WHERE id=$doc_id");
                if (!$r3) die("MySQL Error in accept_document: " . mysqli_error($con));
                fileExitDocumentToEmployeeDocuments($con, $exit_id, $doc['doc_type'], $doc['token']);
            } else {
                die("DEBUG accept_document: row found but employee_signature_data is empty.");
            }
        } elseif ($action === 'decline_document') {
            $doc_id = intval($_POST['doc_id']);
            $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
            if ($chk && mysqli_num_rows($chk) > 0) {
                mysqli_query($con, "UPDATE hr_exit_documents SET status='declined' WHERE id=$doc_id");
            }
        } elseif ($action === 'revert_document') {
            $doc_id = intval($_POST['doc_id']);
            $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
            if ($chk && mysqli_num_rows($chk) > 0) {
                mysqli_query($con, "UPDATE hr_exit_documents SET status='draft', employee_signature_data=NULL, employee_signed_by=NULL, employee_signed_at=NULL, hr_released_by=NULL, hr_released_at=NULL, hr_accepted_by=NULL, hr_accepted_at=NULL WHERE id=$doc_id");
            }
        } elseif ($action === 'close_exit') {
            mysqli_query($con, "UPDATE hr_exit_requests SET status='closed' WHERE id=$exit_id");
        } elseif ($action === 'delete_doc') {
            $doc_id = intval($_POST['doc_id']);
            mysqli_query($con, "DELETE FROM hr_exit_documents WHERE id=$doc_id AND exit_id=$exit_id");
        } elseif ($action === 'save_settlement') {
            $num = function($key) { return isset($_POST[$key]) && $_POST[$key] !== '' ? (float)$_POST[$key] : 0; };
            $pending_salary = $num('pending_salary');
            $leave_encashment = $num('leave_encashment');
            $bonus_incentive = $num('bonus_incentive');
            $gratuity_amount = $num('gratuity_amount');
            $pension_amount = $num('pension_amount');
            $severance_pay = $num('severance_pay');
            $loan_recovery = $num('loan_recovery');
            $notice_shortfall_deduction = $num('notice_shortfall_deduction');
            $other_deductions = $num('other_deductions');
            $notes = mysqli_real_escape_string($con, $_POST['notes'] ?? '');
            $net_amount = ($pending_salary + $leave_encashment + $bonus_incentive + $gratuity_amount + $pension_amount + $severance_pay)
                        - ($loan_recovery + $notice_shortfall_deduction + $other_deductions);

            mysqli_query($con, "INSERT INTO hr_exit_settlement
                (exit_id, pending_salary, leave_encashment, bonus_incentive, gratuity_amount, pension_amount, severance_pay, loan_recovery, notice_shortfall_deduction, other_deductions, net_amount, notes)
                VALUES ($exit_id, $pending_salary, $leave_encashment, $bonus_incentive, $gratuity_amount, $pension_amount, $severance_pay, $loan_recovery, $notice_shortfall_deduction, $other_deductions, $net_amount, '$notes')
                ON DUPLICATE KEY UPDATE
                pending_salary=$pending_salary, leave_encashment=$leave_encashment, bonus_incentive=$bonus_incentive,
                gratuity_amount=$gratuity_amount, pension_amount=$pension_amount, severance_pay=$severance_pay,
                loan_recovery=$loan_recovery, notice_shortfall_deduction=$notice_shortfall_deduction,
                other_deductions=$other_deductions, net_amount=$net_amount, notes='$notes'");

            if (isset($_POST['final_last_working_day']) && $_POST['final_last_working_day'] !== '') {
                $lwd = mysqli_real_escape_string($con, $_POST['final_last_working_day']);
                mysqli_query($con, "UPDATE hr_exit_requests SET final_last_working_day='$lwd' WHERE id=$exit_id");
            }
        } elseif ($action === 'save_doc_edit') {
            $doc_id = intval($_POST['doc_id'] ?? 0);
            $content = mysqli_real_escape_string($con, $_POST['content'] ?? '');
            if ($doc_id > 0) {
                // Editing content invalidates any prior approval — HR must re-approve before it's employee-visible.
                mysqli_query($con, "UPDATE hr_exit_documents SET custom_content='$content', status='draft' WHERE id=$doc_id AND exit_id=$exit_id");
            }
        }
    }
    
    // Global Template Actions (not tied to specific exit_id)
    if ($action === 'save_global_template') {
        $tid = intval($_POST['template_id'] ?? 0);
        $tcode = mysqli_real_escape_string($con, $_POST['doc_code'] ?? '');
        $tname = mysqli_real_escape_string($con, $_POST['doc_name'] ?? '');
        $thtml = mysqli_real_escape_string($con, $_POST['template_html'] ?? '');
        if ($tid > 0) {
            mysqli_query($con, "UPDATE hr_exit_document_templates SET doc_name='$tname', doc_code='$tcode', template_html='$thtml' WHERE id=$tid");
        } else {
            mysqli_query($con, "INSERT INTO hr_exit_document_templates (doc_code, doc_name, template_html) VALUES ('$tcode', '$tname', '$thtml')");
        }
        header("Location: hr-exit-settlement.php?view=docs");
        exit;
    } elseif ($action === 'delete_global_template') {
        $tid = intval($_POST['template_id'] ?? 0);
        if ($tid > 0) {
            mysqli_query($con, "DELETE FROM hr_exit_document_templates WHERE id=$tid");
        }
        header("Location: hr-exit-settlement.php?view=docs");
        exit;
    }
    header("Location: hr-exit-settlement.php");
    exit;
}

$exits_query = mysqli_query($con, "SELECT r.*, e.name as employee_name FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.status IN ('handover', 'interview_settlement', 'documents', 'closed') ORDER BY r.id DESC");

// Flat, document-centric view for the "Manage Documents" section — every generated
// document across every exit, one row each, with employee info fetched by default
// (same join pattern hr-exit-handover.php uses) instead of re-entering it per document.
$doc_status_exists = false;
$chk_status = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
if ($chk_status && mysqli_num_rows($chk_status) > 0) $doc_status_exists = true;
$doc_status_col = $doc_status_exists ? "d.status" : "'approved' as status";

$all_docs_query = mysqli_query($con, "SELECT d.id as doc_id, d.doc_type, d.token, $doc_status_col, d.custom_content, d.generated_at,
    r.id as exit_id, r.exit_number, r.exit_type, r.final_last_working_day,
    e.id as emp_id, e.name as emp_name, e.employee_id as emp_code, e.department as emp_department,
    e.position as emp_position, e.address as emp_address, e.phone as emp_phone, e.hire_date as emp_hire_date, e.company_name as emp_company_name
    FROM hr_exit_documents d
    JOIN hr_exit_requests r ON r.id = d.exit_id
    LEFT JOIN hr_employees e ON e.id = r.employee_id
    ORDER BY d.generated_at DESC, d.id DESC");
$all_docs_query_error = $all_docs_query ? null : mysqli_error($con);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>F&F Settlement & Exit Certificates</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--red:#ef4444;--amber:#f59e0b;--green:#10b981;--gray-bg:#f0f4f8;}
*{box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--gray-bg);margin:0;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:20px 30px;border-radius:12px;margin:20px;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-weight:800;font-size:1.3rem;margin:0;}
.hdr p{color:rgba(255,255,255,.7);font-size:12px;margin:4px 0 0;}
.wrap{max-width:100%;margin:0 auto;padding:0 24px 30px;}
.card-box{background:#fff;border-radius:12px;padding:22px;box-shadow:0 2px 10px rgba(0,0,0,.06);margin-bottom:18px;}
table{width:100%;border-collapse:collapse;}
th{background:#f0f4f8;color:var(--navy);font-weight:800;font-size:11px;text-transform:uppercase;padding:10px 12px;text-align:left;}
td{padding:10px 12px;border-bottom:1px solid #f1f5f9;font-size:12.5px;vertical-align:top;}
.badge{padding:4px 10px;border-radius:12px;font-size:11px;font-weight:800;}
.b-status{background:#dbeafe;color:#1e40af;}
.b-closed{background:#d1fae5;color:#065f46;}
.btn-p{padding:6px 12px;border:none;border-radius:6px;font-weight:700;font-size:11px;cursor:pointer;color:#fff;display:inline-block;margin-bottom:4px;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));}
.btn-green{background:linear-gradient(135deg,var(--green),#059669);}
.btn-amber{background:linear-gradient(135deg,var(--amber),#b45309);}
.btn-red{background:linear-gradient(135deg,var(--red),#b91c1c);}
.doc-item { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; background:#f8f9fa; padding:4px 8px; border-radius:4px;}
.doc-item .doc-name { font-size:11px; font-weight:700; color:var(--navy); flex:1;}
.doc-item .doc-status { margin-right: 8px;}
.doc-item .doc-actions { display: flex; gap:4px; }
.doc-actions form { margin:0; }
</style>
</head>
<body>
<div class="hdr" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:14px;">
    <div>
        <h1>F&F Settlement & Exit Certificates</h1>
        <p>Generate certificates, approve them for the employee, and close exit requests.</p>
    </div>
    <div>
        
        <button type="button" class="btn-p" id="tabExitsBtn" style="background:#fff;color:var(--navy);font-size:14px;padding:10px 20px;font-weight:700;" onclick="showExitsView()">Exit Requests</button>
        <button type="button" class="btn-p" id="tabDocsBtn" style="background:rgba(255,255,255,.2);color:#fff;font-size:14px;padding:10px 20px;font-weight:700;" onclick="showDocsView()">Manage Documents</button>
    </div>
</div>
<div class="wrap">
    <div class="card-box" id="exitsSection">
        <table>
            <thead>
                <tr>
                    <th>Exit #</th>
                    <th>Employee</th>
                    <th>Type</th>
                    <th>Last Working Day</th>
                    <th>Status</th>
                    <th style="min-width:300px;">Documents (HTML)</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php while($row = mysqli_fetch_assoc($exits_query)): ?>
                <?php
                    // Graceful fallback if status column is missing
                    $status_select = "id, doc_type, token, custom_content";
                    $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
                    if ($chk && mysqli_num_rows($chk) > 0) $status_select .= ", status, requires_signature, employee_signature_data, employee_signed_by, employee_signed_at";

                    $docs_q = mysqli_query($con, "SELECT $status_select FROM hr_exit_documents WHERE exit_id={$row['id']}");
                    $uploaded_docs = [];
                    while($d = mysqli_fetch_assoc($docs_q)) {
                        $uploaded_docs[] = $d;
                    }

                    $rowSettlement = qFetch($con, "SELECT * FROM hr_exit_settlement WHERE exit_id={$row['id']} LIMIT 1") ?: [];

                    // Needed to render a starting-point preview for the Edit Document modal
                    // (same data hr-exit-documents.php itself uses to render the live letter).
                    $rowEmp = intval($row['employee_id']) > 0 ? qFetch($con, "SELECT * FROM hr_employees WHERE id=" . intval($row['employee_id']) . " LIMIT 1") : null;
                    $rowCompanySettings = ['company_name' => '', 'company_address' => '', 'company_phone' => '', 'company_email' => '', 'company_website' => ''];
                    if ($rowEmp && !empty($rowEmp['company_name'])) {
                        $rcn_e = mysqli_real_escape_string($con, $rowEmp['company_name']);
                        $rhc = qFetch($con, "SELECT id, company_name FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$rcn_e')) LIMIT 1");
                        if ($rhc) {
                            $rcs = qFetch($con, "SELECT * FROM hr_offer_company_settings WHERE company_id=" . intval($rhc['id']) . " LIMIT 1");
                            if ($rcs) { $rowCompanySettings = $rcs; $rowCompanySettings['company_name'] = $rhc['company_name']; }
                        }
                    }
                    $rowJoiningDate = ($rowEmp && !empty($rowEmp['hire_date']) && strtotime($rowEmp['hire_date'])) ? date('F j, Y', strtotime($rowEmp['hire_date'])) : '[Joining Date]';
                    $rowLastWorkingDay = (!empty($row['final_last_working_day']) && strtotime($row['final_last_working_day'])) ? date('F j, Y', strtotime($row['final_last_working_day'])) : '[Last Working Day]';
                ?>
                <tr>
                    <td><?= htmlspecialchars($row['exit_number']) ?></td>
                    <td><strong><?= htmlspecialchars($row['employee_name']) ?></strong></td>
                    <td><?= ucfirst($row['exit_type']) ?></td>
                    <td><?= !empty($row['final_last_working_day']) && strtotime($row['final_last_working_day']) ? date('d M Y', strtotime($row['final_last_working_day'])) : 'Pending' ?></td>
                    <td>
                        <span class="badge <?= $row['status']=='closed' ? 'b-closed' : 'b-status' ?>"><?= strtoupper($row['status']) ?></span>
                    </td>
                    <td>
                        <?php if(empty($uploaded_docs)): ?>
                            <span class="text-muted" style="font-size:11px;">No documents generated</span>
                        <?php else: ?>
                            <?php foreach($uploaded_docs as $dt): 
                                $dstat = isset($dt['status']) ? $dt['status'] : 'approved';
                            ?>
                                <?php
                                    $dtPreview = !empty($dt['custom_content']) ? $dt['custom_content'] : renderExitDocumentBody($con, array_merge($dt, ['exit_id' => $row['id'], 'final_last_working_day' => $row['final_last_working_day']]), $rowEmp ?: [], $rowCompanySettings, $rowJoiningDate, $rowLastWorkingDay);
                                ?>
                                <div class="doc-item">
                                    <span class="doc-name"><?= htmlspecialchars(ucwords(str_replace('_', ' ', $dt['doc_type']))) ?></span>
                                    <span class="doc-status">
                                        <?php if($dstat == 'draft'): ?>
                                            <span class="badge" style="background:#fef3c7;color:#92400e;">DRAFT</span>
                                        <?php elseif($dstat == 'pending_signature'): ?>
                                            <span class="badge" style="background:#dbeafe;color:#1e40af;">AWAITING EMPLOYEE SIGNATURE</span>
                                        <?php elseif($dstat == 'pending_hr_final'): ?>
                                            <span class="badge" style="background:#ede9fe;color:#5b21b6;">PENDING HR REVIEW</span>
                                        <?php elseif($dstat == 'declined'): ?>
                                            <span class="badge" style="background:#fee2e2;color:#991b1b;">DECLINED</span>
                                        <?php else: ?>
                                            <span class="badge" style="background:#d1fae5;color:#065f46;">APPROVED</span>
                                        <?php endif; ?>
                                    </span>
                                    <div class="doc-actions">
                                        <a href="hr-exit-documents.php?token=<?= $dt['token'] ?>" target="_blank" class="btn-p btn-navy" title="Preview"><i class="fa fa-eye"></i></a>

                                        <button type="button" class="btn-p btn-amber" title="Edit" onclick="openEditDocModal(<?= $row['id'] ?>, <?= intval($dt['id']) ?>, document.getElementById('editDocSource_<?= intval($dt['id']) ?>').value)"><i class="fa fa-pencil"></i></button>
                                        <textarea id="editDocSource_<?= intval($dt['id']) ?>" style="display:none;"><?= htmlspecialchars($dtPreview) ?></textarea>

                                        <?php if($dstat == 'draft'): ?>
                                            <?php if(!empty($dt['requires_signature'])): ?>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('This document requires the employee\'s signature. Release it to them for signing?');">
                                            <input type="hidden" name="action" value="approve_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-green" title="Release for Signature"><i class="fa fa-signature"></i></button>
                                        </form>
                                            <?php else: ?>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Approve this document? Once approved, the employee will be able to view and download it.');">
                                            <input type="hidden" name="action" value="approve_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-green" title="Approve"><i class="fa fa-check"></i></button>
                                        </form>
                                            <?php endif; ?>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Decline this document?');">
                                            <input type="hidden" name="action" value="decline_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-amber" title="Decline"><i class="fa fa-times"></i></button>
                                        </form>
                                        <?php elseif($dstat == 'pending_signature'): ?>
                                        <span class="text-muted" style="font-size:10.5px;padding:4px 6px;display:inline-block;">Waiting on employee</span>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Revert to Draft? This will pull the document back and clear the release.');">
                                            <input type="hidden" name="action" value="revert_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-navy" title="Revert to Draft"><i class="fa fa-undo"></i></button>
                                        </form>
                                        <?php elseif($dstat == 'pending_hr_final'): ?>
                                        <a href="#" onclick="return openSignaturePreview('<?= htmlspecialchars(addslashes($dt['employee_signature_data'] ?? '')) ?>');" class="btn-p" style="background:#64748b;" title="View Employee Signature"><i class="fa fa-signature"></i></a>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Employee has signed. Accept and finalize this document? It will then be filed to the employee\'s documents.');">
                                            <input type="hidden" name="action" value="accept_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-green" title="Accept"><i class="fa fa-check-double"></i></button>
                                        </form>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Revert to Draft? This clears the employee\'s signature and the document will need to be re-released.');">
                                            <input type="hidden" name="action" value="revert_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-amber" title="Revert to Draft"><i class="fa fa-undo"></i></button>
                                        </form>
                                        <?php else: ?>
                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Revert to Draft? This will hide the document from the employee until approved again.');">
                                            <input type="hidden" name="action" value="revert_document"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-navy" title="Revert to Draft"><i class="fa fa-undo"></i></button>
                                        </form>
                                        <?php endif; ?>

                                        <form method="POST" style="display:inline-block;margin:0;" onsubmit="return confirm('Delete this document?');">
                                            <input type="hidden" name="action" value="delete_doc"/>
                                            <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                            <input type="hidden" name="doc_id" value="<?= $dt['id'] ?>"/>
                                            <button type="submit" class="btn-p btn-red" title="Delete"><i class="fa fa-trash"></i></button>
                                        </form>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </td>
                    <td>
                        <button class="btn-p btn-amber"
                            onclick='openSettlementModal(<?= htmlspecialchars(json_encode([
                                "exit_id" => (int)$row["id"],
                                "final_last_working_day" => $row["final_last_working_day"] ?? "",
                                "pending_salary" => (float)($rowSettlement["pending_salary"] ?? 0),
                                "leave_encashment" => (float)($rowSettlement["leave_encashment"] ?? 0),
                                "bonus_incentive" => (float)($rowSettlement["bonus_incentive"] ?? 0),
                                "gratuity_amount" => (float)($rowSettlement["gratuity_amount"] ?? 0),
                                "pension_amount" => (float)($rowSettlement["pension_amount"] ?? 0),
                                "severance_pay" => (float)($rowSettlement["severance_pay"] ?? 0),
                                "loan_recovery" => (float)($rowSettlement["loan_recovery"] ?? 0),
                                "notice_shortfall_deduction" => (float)($rowSettlement["notice_shortfall_deduction"] ?? 0),
                                "other_deductions" => (float)($rowSettlement["other_deductions"] ?? 0),
                                "notes" => $rowSettlement["notes"] ?? ""
                            ]), ENT_QUOTES, "UTF-8") ?>)'><i class="fa fa-calculator"></i> Settlement</button>
                        <button class="btn-p btn-navy" onclick="openGenModal(<?= $row['id'] ?>)"><i class="fa fa-magic"></i> Generate</button>
                        <?php if($row['status'] != 'closed'): ?>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('Close exit? Only approved documents will be visible to employee.');">
                                <input type="hidden" name="action" value="close_exit"/>
                                <input type="hidden" name="exit_id" value="<?= $row['id'] ?>"/>
                                <button type="submit" class="btn-p btn-amber"><i class="fa fa-lock"></i> Close</button>
                            </form>
                        <?php else: ?>
                            <br><span class="text-success" style="font-size:11px;font-weight:bold;display:inline-block;margin-top:4px;"><i class="fa fa-check-circle"></i> Closed</span>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endwhile; ?>
                <?php if(mysqli_num_rows($exits_query) == 0): ?>
                <tr><td colspan="7" class="text-center py-4 text-muted">No exits ready for settlement.</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>

    <?php
    // Fetch all templates for the grid
    $templates_query = mysqli_query($con, "SELECT * FROM hr_exit_document_templates ORDER BY id ASC");
    ?>
    <div id="manageDocsSection" style="display:none; margin-bottom:24px; background:transparent; box-shadow:none; padding:0; border:none;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; flex-wrap:wrap; gap:10px;">
            <h5 style="margin:0; color:var(--navy); font-weight:800;"><i class="fas fa-layer-group mr-2"></i>All Configured Document Templates</h5>
            <div style="display:flex; align-items:center; gap:10px;">
                <button type="button" class="btn-add" onclick="openTemplateEditor(0, '', '', '')" style="background:#2563eb; color:#fff; border:none; padding:8px 16px; border-radius:6px; font-weight:700; font-size:13px; cursor:pointer;"><i class="fas fa-plus mr-1"></i> New Document</button>
            </div>
        </div>
        <div id="templatesGrid" style="display:grid; grid-template-columns:repeat(auto-fill, minmax(320px, 1fr)); gap:20px;">
            <?php while($templates_query && $tpl = mysqli_fetch_assoc($templates_query)): ?>
            <div class="template-card" style="background:#fff; border:1px solid #e2e8f0; border-radius:12px; box-shadow:0 4px 6px rgba(0,0,0,0.02); display:flex; flex-direction:column; overflow:hidden;">
                <div style="padding:16px; flex:1;">
                    <div style="font-size:10px; font-weight:800; color:#64748b; text-transform:uppercase; letter-spacing:0.5px; margin-bottom:4px;"><i class="fas fa-file-alt mr-1"></i>TEMPLATE</div>
                    <div style="font-size:14px; font-weight:800; color:var(--navy); margin-bottom:12px;"><?= htmlspecialchars($tpl['doc_name']) ?></div>
                    <textarea id="tpl_source_<?= $tpl['id'] ?>" style="display:none;"><?= htmlspecialchars($tpl['template_html']) ?></textarea>
                </div>
                <div style="background:#f8fafc; padding:12px 16px; border-top:1px solid #f1f5f9; display:flex; gap:8px;">
                    <button type="button" class="btn-p btn-navy" style="flex:1; text-align:center;" onclick="openTemplateEditor(<?= $tpl['id'] ?>, '<?= htmlspecialchars(addslashes($tpl['doc_code'])) ?>', '<?= htmlspecialchars(addslashes($tpl['doc_name'])) ?>', document.getElementById('tpl_source_<?= $tpl['id'] ?>').value)"><i class="fas fa-cog mr-1"></i> Manage</button>
                    <button type="button" class="btn-p" style="background:#64748b; color:#fff; flex:1; text-align:center;" onclick="previewGlobalTemplate(document.getElementById('tpl_source_<?= $tpl['id'] ?>').value)"><i class="fas fa-eye mr-1"></i> Preview</button>
                    <button type="button" class="btn-p btn-red" style="width:36px; padding:0; display:flex; justify-content:center; align-items:center;" onclick="deleteTemplateFromGrid(<?= $tpl['id'] ?>)" title="Delete Template"><i class="fas fa-trash"></i></button>
                </div>
            </div>
            <?php endwhile; ?>
        </div>
        </div>
</div>

<!-- Dedicated Template Editor Flow (Like hr-employee-offer.php) -->
<div id="templateEditorSection" style="display:none; margin-bottom:24px;">
    <div style="background:#fff; border-radius:12px; box-shadow:0 4px 10px rgba(0,0,0,0.05); padding:24px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; border-bottom:2px solid #f1f5f9; padding-bottom:16px;">
            <div style="display:flex; align-items:center; gap:12px;">
                <button type="button" class="btn-p" style="background:#e2e8f0; color:#475569;" onclick="closeTemplateEditor()"><i class="fas fa-arrow-left"></i> Back</button>
                <h4 style="margin:0; color:var(--navy); font-weight:800;" id="te_header_title">Edit Template</h4>
            </div>
            <div class="rev-tabs" style="display:flex; gap:8px;">
                <button type="button" class="tab-btn active" id="tabBtn_edit" onclick="switchTeTab('edit')" style="padding:8px 16px; border:none; background:var(--navy); color:#fff; border-radius:6px; font-weight:700;"><i class="fas fa-edit mr-1"></i> Edit Content</button>
                <button type="button" class="tab-btn" id="tabBtn_preview" onclick="switchTeTab('preview')" style="padding:8px 16px; border:none; background:#e2e8f0; color:#475569; border-radius:6px; font-weight:700;"><i class="fas fa-eye mr-1"></i> Preview PDF</button>
            </div>
        </div>

        <form method="POST" id="te_form">
            <input type="hidden" name="action" value="save_global_template"/>
            <input type="hidden" name="template_id" id="te_template_id" value="0"/>
            
            <!-- EDIT PANE -->
            <div id="te_pane_edit">
                <div class="row">
                    <div class="col-md-6 form-group">
                        <label class="font-weight-bold" style="font-size:12px;color:var(--navy);">Document Name</label>
                        <input type="text" name="doc_name" id="te_doc_name" class="form-control" style="font-size:13px;" required placeholder="e.g. Relieving Letter"/>
                    </div>
                    <div class="col-md-6 form-group">
                        <label class="font-weight-bold" style="font-size:12px;color:var(--navy);">Document Code</label>
                        <input type="text" name="doc_code" id="te_doc_code" class="form-control" style="font-size:13px;" required placeholder="e.g. relieving_letter"/>
                    </div>
                </div>
                <div class="form-group">
                    <label class="font-weight-bold" style="font-size:12px;color:var(--navy);">Template HTML</label>
                    <textarea name="template_html" id="te_template_html" class="form-control summernote" rows="12"></textarea>
                    
                    <div style="background:#f1f5f9;padding:10px;border-radius:6px;margin-top:10px;font-size:11px;color:#475569;">
                        <strong>Available Placeholders:</strong><br>
                        <code>[EMPLOYEE_NAME]</code>, <code>[COMPANY_NAME]</code>, <code>[JOINING_DATE]</code>, <code>[LAST_WORKING_DAY]</code>, <code>[DESIGNATION]</code>, <code>[DEPARTMENT]</code><br>
                        <code>[SETTLEMENT_TABLE]</code> (Special placeholder to automatically render the Full & Final Settlement calculation table)
                    </div>
                </div>
                <div style="display:flex; justify-content:space-between; margin-top:20px;">
                    <button type="button" class="btn-p btn-red" id="btnDeleteGlobalTemplate" onclick="deleteGlobalTemplate()" style="display:none;"><i class="fas fa-trash mr-1"></i> Delete Template</button>
                    <button type="button" class="btn-p" style="background:#f59e0b; color:#fff; font-size:14px; padding:10px 24px; font-weight:700; box-shadow:0 4px 10px rgba(245,158,11,0.3);" onclick="teSaveAndPreview()"><i class="fas fa-eye mr-1"></i> Save & Preview</button>
                </div>
            </div>

            <!-- PREVIEW PANE -->
            <div id="te_pane_preview" style="display:none;">
                <div style="margin-bottom:16px; display:flex; justify-content:space-between; align-items:center;">
                    <div class="text-muted" style="font-size:12px; font-weight:600;"><i class="fas fa-info-circle mr-1"></i> Inline live preview showing dummy data formatting.</div>
                    <button type="submit" class="btn-p btn-navy" style="font-size:15px; padding:12px 28px; font-weight:700; box-shadow:0 4px 12px rgba(15,37,87,0.2);"><i class="fas fa-check-circle mr-1"></i> Finalize & Publish</button>
                </div>
                <!-- INLINE PDF CONTAINER -->
                <div class="pdf-preview-container" style="width:100%; max-width:850px; margin:0 auto; background:#e2e8f0; padding:20px; border-radius:10px;">
                    <iframe id="te_previewFrame" style="width:100%; height:1100px; border:none; background:#fff; box-shadow:0 10px 30px rgba(0,0,0,0.1);" src="about:blank"></iframe>
                </div>
            </div>
        </form>
    </div>
</div>

<form id="deleteGlobalTemplateForm" method="POST" style="display:none;">
    <input type="hidden" name="action" value="delete_global_template"/>
    <input type="hidden" name="template_id" id="delete_gt_id" value="0"/>
</form>

<form id="previewGlobalTemplateForm" method="POST" action="hr-exit-template-preview.php" target="_blank" style="display:none;">
    <input type="hidden" name="preview_html" id="preview_html_input" value=""/>
</form>

<link href="https://cdn.jsdelivr.net/npm/summernote@0.8.18/dist/summernote-bs4.min.css" rel="stylesheet">
<script src="https://code.jquery.com/jquery-3.5.1.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/summernote@0.8.18/dist/summernote-bs4.min.js"></script>
<script>
$(document).ready(function() {
    $('.summernote').summernote({
        height: 350,
        toolbar: [
            ['style', ['style']],
            ['font', ['bold', 'italic', 'underline', 'clear']],
            ['para', ['ul', 'ol', 'paragraph']],
            ['insert', ['link', 'picture', 'table', 'hr']],
            ['view', ['fullscreen', 'codeview']]
        ]
    });
});

function openTemplateEditor(id, code, name, html) {
    document.getElementById('manageDocsSection').style.display = 'none';
    document.getElementById('templateEditorSection').style.display = 'block';
    
    document.getElementById('te_template_id').value = id;
    document.getElementById('te_doc_code').value = code;
    document.getElementById('te_doc_name').value = name;
    $('#te_template_html').summernote('code', html);
    
    document.getElementById('te_header_title').innerText = id > 0 ? "Editing: " + name : "New Document Template";
    
    if (id > 0) {
        document.getElementById('btnDeleteGlobalTemplate').style.display = 'inline-block';
        document.getElementById('te_doc_code').readOnly = true;
    } else {
        document.getElementById('btnDeleteGlobalTemplate').style.display = 'none';
        document.getElementById('te_doc_code').readOnly = false;
    }
    switchTeTab('edit');
}

function closeTemplateEditor() {
    document.getElementById('manageDocsSection').style.display = 'block';
    document.getElementById('templateEditorSection').style.display = 'none';
}

function switchTeTab(tab) {
    if (tab === 'edit') {
        document.getElementById('te_pane_edit').style.display = 'block';
        document.getElementById('te_pane_preview').style.display = 'none';
        document.getElementById('tabBtn_edit').style.background = 'var(--navy)';
        document.getElementById('tabBtn_edit').style.color = '#fff';
        document.getElementById('tabBtn_preview').style.background = '#e2e8f0';
        document.getElementById('tabBtn_preview').style.color = '#475569';
    } else {
        document.getElementById('te_pane_edit').style.display = 'none';
        document.getElementById('te_pane_preview').style.display = 'block';
        document.getElementById('tabBtn_preview').style.background = 'var(--navy)';
        document.getElementById('tabBtn_preview').style.color = '#fff';
        document.getElementById('tabBtn_edit').style.background = '#e2e8f0';
        document.getElementById('tabBtn_edit').style.color = '#475569';
    }
}

function teSaveAndPreview() {
    var htmlContent = $('#te_template_html').summernote('code');
    switchTeTab('preview');
    
    var iframe = document.getElementById('te_previewFrame');
    iframe.contentWindow.document.open();
    iframe.contentWindow.document.write('Loading preview...');
    iframe.contentWindow.document.close();

    $.ajax({
        url: 'hr-exit-template-preview.php',
        type: 'POST',
        data: { preview_html: htmlContent },
        success: function(response) {
            iframe.contentWindow.document.open();
            iframe.contentWindow.document.write(response);
            iframe.contentWindow.document.close();
        },
        error: function() {
            iframe.contentWindow.document.open();
            iframe.contentWindow.document.write('<div style="padding:20px;color:red;font-family:sans-serif;">Error loading preview.</div>');
            iframe.contentWindow.document.close();
        }
    });
}

function deleteGlobalTemplate() {
    if (confirm("Are you sure you want to delete this template?")) {
        document.getElementById('delete_gt_id').value = document.getElementById('te_template_id').value;
        document.getElementById('deleteGlobalTemplateForm').submit();
    }
}

function deleteTemplateFromGrid(id) {
    if (confirm('Are you sure you want to delete this template? This action cannot be undone.')) {
        document.getElementById('delete_gt_id').value = id;
        document.getElementById('deleteGlobalTemplateForm').submit();
    }
}

function previewGlobalTemplate(html) {
    document.getElementById('preview_html_input').value = html;
    document.getElementById('previewGlobalTemplateForm').submit();
}

function openGenModal(exitId) {
    document.getElementById('modal_exit_id').value = exitId;
    document.getElementById('gen_requires_signature').checked = false;
    $('#genModal').modal('show');
}

function showExitsView() {
    document.getElementById('exitsSection').style.display = '';
    document.getElementById('manageDocsSection').style.display = 'none';
    document.getElementById('tabExitsBtn').style.background = '#fff';
    document.getElementById('tabExitsBtn').style.color = 'var(--navy)';
    document.getElementById('tabDocsBtn').style.background = 'rgba(255,255,255,.2)';
    document.getElementById('tabDocsBtn').style.color = '#fff';
}
function showDocsView() {
    document.getElementById('exitsSection').style.display = 'none';
    document.getElementById('manageDocsSection').style.display = '';
    document.getElementById('tabDocsBtn').style.background = '#fff';
    document.getElementById('tabDocsBtn').style.color = 'var(--navy)';
    document.getElementById('tabExitsBtn').style.background = 'rgba(255,255,255,.2)';
    document.getElementById('tabExitsBtn').style.color = '#fff';
}

function openSettlementModal(data) {
    document.getElementById('st_exit_id').value = data.exit_id;
    document.getElementById('st_final_last_working_day').value = data.final_last_working_day || '';
    document.getElementById('st_pending_salary').value = data.pending_salary;
    document.getElementById('st_leave_encashment').value = data.leave_encashment;
    document.getElementById('st_bonus_incentive').value = data.bonus_incentive;
    document.getElementById('st_gratuity_amount').value = data.gratuity_amount;
    document.getElementById('st_pension_amount').value = data.pension_amount;
    document.getElementById('st_severance_pay').value = data.severance_pay;
    document.getElementById('st_loan_recovery').value = data.loan_recovery;
    document.getElementById('st_notice_shortfall_deduction').value = data.notice_shortfall_deduction;
    document.getElementById('st_other_deductions').value = data.other_deductions;
    document.getElementById('st_notes').value = data.notes || '';
    recalcSettlementPreview();
    $('#settlementModal').modal('show');
}

function recalcSettlementPreview() {
    var g = function(id) { return parseFloat(document.getElementById(id).value) || 0; };
    var net = (g('st_pending_salary') + g('st_leave_encashment') + g('st_bonus_incentive') + g('st_gratuity_amount') + g('st_pension_amount') + g('st_severance_pay'))
             - (g('st_loan_recovery') + g('st_notice_shortfall_deduction') + g('st_other_deductions'));
    document.getElementById('st_net_amount_preview').value = net.toFixed(2);
}
document.addEventListener('input', function(e) {
    if(e.target && e.target.classList.contains('settlement-amt')) recalcSettlementPreview();
});
</script>

<!-- Generate Modal -->
<div class="modal fade" id="genModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form method="POST">
        <div class="modal-header">
          <h5 class="modal-title" style="font-size:16px;font-weight:800;color:var(--navy);">Generate Exit Document</h5>
          <button type="button" class="close" data-dismiss="modal">&times;</button>
        </div>
        <div class="modal-body">
            <input type="hidden" name="action" value="generate_document"/>
            <input type="hidden" name="exit_id" id="modal_exit_id" value=""/>
            
            <div class="form-group">
                <label class="font-weight-bold" style="font-size:12px;color:var(--navy);">Document Type</label>
                <select name="doc_type" class="form-control" style="font-size:13px;" required>
                    <option value="">Select Document Type</option>
                    <?php
                    $dtq = mysqli_query($con, "SELECT doc_code, doc_name FROM hr_exit_document_templates ORDER BY doc_name ASC");
                    while($dtq && $dt = mysqli_fetch_assoc($dtq)) {
                        echo '<option value="'.htmlspecialchars($dt['doc_code']).'">'.htmlspecialchars($dt['doc_name']).'</option>';
                    }
                    ?>
                </select>
                <small class="text-muted mt-2 d-block">This will instantly generate an HTML certificate. It will be marked as "Draft" and won't be visible to the employee until you preview and Approve it.</small>
            </div>

            <div class="form-group form-check" style="margin-top:10px;">
                <input type="checkbox" class="form-check-input" name="requires_signature" id="gen_requires_signature" value="1">
                <label class="form-check-label" for="gen_requires_signature" style="font-size:12.5px;font-weight:700;color:var(--navy);">Requires the employee's digital signature</label>
                <small class="text-muted mt-1 d-block">If checked, approving this document sends it to the employee to sign first. Once they sign, it comes back to you for final acceptance before it's filed to their documents. If unchecked, approving it files it straight away.</small>
            </div>
        </div>
        <div class="modal-footer">
            <button type="submit" class="btn-p btn-navy">Generate Document</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- Settlement Modal -->
<div class="modal fade" id="settlementModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <form method="POST" id="settlementForm">
        <div class="modal-header">
          <h5 class="modal-title" style="font-size:16px;font-weight:800;color:var(--navy);">Full & Final Settlement</h5>
          <button type="button" class="close" data-dismiss="modal">&times;</button>
        </div>
        <div class="modal-body">
            <input type="hidden" name="action" value="save_settlement"/>
            <input type="hidden" name="exit_id" id="st_exit_id" value=""/>

            <div class="form-group">
                <label class="font-weight-bold" style="font-size:12px;color:var(--navy);">Last Working Day</label>
                <input type="date" name="final_last_working_day" id="st_final_last_working_day" class="form-control" style="font-size:13px;"/>
            </div>

            <div class="row">
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Pending Salary</label>
                    <input type="number" step="0.01" name="pending_salary" id="st_pending_salary" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Leave Encashment</label>
                    <input type="number" step="0.01" name="leave_encashment" id="st_leave_encashment" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Bonus / Incentive</label>
                    <input type="number" step="0.01" name="bonus_incentive" id="st_bonus_incentive" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Gratuity</label>
                    <input type="number" step="0.01" name="gratuity_amount" id="st_gratuity_amount" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Pension</label>
                    <input type="number" step="0.01" name="pension_amount" id="st_pension_amount" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Severance / Notice Pay in Lieu</label>
                    <input type="number" step="0.01" name="severance_pay" id="st_severance_pay" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:#991b1b;font-weight:700;">Loan Recovery (deduction)</label>
                    <input type="number" step="0.01" name="loan_recovery" id="st_loan_recovery" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:#991b1b;font-weight:700;">Notice Shortfall Deduction</label>
                    <input type="number" step="0.01" name="notice_shortfall_deduction" id="st_notice_shortfall_deduction" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:#991b1b;font-weight:700;">Other Deductions</label>
                    <input type="number" step="0.01" name="other_deductions" id="st_other_deductions" class="form-control settlement-amt" style="font-size:13px;"/>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-size:12px;color:var(--navy);font-weight:700;">Net Payable (auto-calculated)</label>
                    <input type="text" id="st_net_amount_preview" class="form-control" style="font-size:13px;font-weight:800;" readonly/>
                </div>
            </div>

            <div class="form-group">
                <label style="font-size:12px;color:var(--navy);font-weight:700;">Notes</label>
                <textarea name="notes" id="st_notes" class="form-control" style="font-size:13px;" rows="2"></textarea>
            </div>
        </div>
        <div class="modal-footer">
            <button type="submit" class="btn-p btn-navy">Save Settlement</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- Edit Document Modal -->
<div class="modal fade" id="editDocModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <form method="POST">
        <div class="modal-header">
          <h5 class="modal-title" style="font-size:16px;font-weight:800;color:var(--navy);">Edit Document Content</h5>
          <button type="button" class="close" data-dismiss="modal">&times;</button>
        </div>
        <div class="modal-body">
            <input type="hidden" name="action" value="save_doc_edit"/>
            <input type="hidden" name="exit_id" id="ed_exit_id" value=""/>
            <input type="hidden" name="doc_id" id="ed_doc_id" value=""/>
            <small class="text-muted d-block mb-2">This is the HTML body of the letter — edit the wording directly. Saving will mark the document as Draft again until you approve it.</small>
            <textarea name="content" id="ed_content" class="form-control" style="font-size:12.5px;font-family:monospace;" rows="18"></textarea>
        </div>
        <div class="modal-footer">
            <button type="submit" class="btn-p btn-navy">Save Document</button>
        </div>
      </form>
    </div>
  </div>
</div>

<link href="https://cdn.jsdelivr.net/npm/summernote@0.8.18/dist/summernote-bs4.min.css" rel="stylesheet">
<script src="https://code.jquery.com/jquery-3.5.1.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/summernote@0.8.18/dist/summernote-bs4.min.js"></script>
<script>
$(document).ready(function() {
    $('.summernote').summernote({
        height: 350,
        toolbar: [
            ['style', ['style']],
            ['font', ['bold', 'italic', 'underline', 'clear']],
            ['para', ['ul', 'ol', 'paragraph']],
            ['insert', ['link', 'picture', 'table', 'hr']],
            ['view', ['fullscreen', 'codeview']]
        ]
    });
});

function openGenModal(exitId) {
    document.getElementById('modal_exit_id').value = exitId;
    document.getElementById('gen_requires_signature').checked = false;
    $('#genModal').modal('show');
}

function showExitsView() {
    document.getElementById('exitsSection').style.display = '';
    document.getElementById('manageDocsSection').style.display = 'none';
    document.getElementById('tabExitsBtn').style.background = '#fff';
    document.getElementById('tabExitsBtn').style.color = 'var(--navy)';
    document.getElementById('tabDocsBtn').style.background = 'rgba(255,255,255,.2)';
    document.getElementById('tabDocsBtn').style.color = '#fff';
}
function showDocsView() {
    document.getElementById('exitsSection').style.display = 'none';
    document.getElementById('manageDocsSection').style.display = '';
    document.getElementById('tabDocsBtn').style.background = '#fff';
    document.getElementById('tabDocsBtn').style.color = 'var(--navy)';
    document.getElementById('tabExitsBtn').style.background = 'rgba(255,255,255,.2)';
    document.getElementById('tabExitsBtn').style.color = '#fff';
}

function openSettlementModal(data) {
    document.getElementById('st_exit_id').value = data.exit_id;
    document.getElementById('st_final_last_working_day').value = data.final_last_working_day || '';
    document.getElementById('st_pending_salary').value = data.pending_salary;
    document.getElementById('st_leave_encashment').value = data.leave_encashment;
    document.getElementById('st_bonus_incentive').value = data.bonus_incentive;
    document.getElementById('st_gratuity_amount').value = data.gratuity_amount;
    document.getElementById('st_pension_amount').value = data.pension_amount;
    document.getElementById('st_severance_pay').value = data.severance_pay;
    document.getElementById('st_loan_recovery').value = data.loan_recovery;
    document.getElementById('st_notice_shortfall_deduction').value = data.notice_shortfall_deduction;
    document.getElementById('st_other_deductions').value = data.other_deductions;
    document.getElementById('st_notes').value = data.notes || '';
    recalcSettlementPreview();
    $('#settlementModal').modal('show');
}

function recalcSettlementPreview() {
    var g = function(id) { return parseFloat(document.getElementById(id).value) || 0; };
    var net = (g('st_pending_salary') + g('st_leave_encashment') + g('st_bonus_incentive') + g('st_gratuity_amount') + g('st_pension_amount') + g('st_severance_pay'))
             - (g('st_loan_recovery') + g('st_notice_shortfall_deduction') + g('st_other_deductions'));
    document.getElementById('st_net_amount_preview').value = net.toFixed(2);
}
document.addEventListener('input', function(e) {
    if (e.target && e.target.classList.contains('settlement-amt')) recalcSettlementPreview();
});

function openEditDocModal(exitId, docId, content) {
    document.getElementById('ed_exit_id').value = exitId;
    document.getElementById('ed_doc_id').value = docId;
    document.getElementById('ed_content').value = content;
    $('#editDocModal').modal('show');
}

function openSignaturePreview(signatureDataUrl) {
    if (!signatureDataUrl) { alert('No signature on file.'); return false; }
    var w = window.open('', '_blank', 'width=520,height=320');
    w.document.write('<title>Employee Signature</title><body style="margin:0;display:flex;align-items:center;justify-content:center;height:100vh;background:#f0f4f8;"><img src="' + signatureDataUrl + '" style="max-width:90%;max-height:90%;border:1px solid #e2e8f0;border-radius:8px;background:#fff;"></body>');
    return false;
}

if (window.location.search.includes('view=docs')) {
    showDocsView();
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
