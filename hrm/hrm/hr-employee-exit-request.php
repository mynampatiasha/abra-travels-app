<?php
ob_start(); // buffer output so header() redirects always work even if a notice/warning fires early
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

$con = conexion();
if (!$con) die("Database connection failed.");

// Temporary one-time fix for existing records that are stuck in 'handover' stage
mysqli_query($con, "UPDATE hr_exit_requests r JOIN hr_exit_asset_instance a ON a.exit_id=r.id SET r.status='clearance' WHERE r.status='handover' AND a.status='completed'");
@mysqli_query($con, "ALTER TABLE hr_exit_clearance_instance ADD COLUMN employee_remarks TEXT NULL AFTER hr_rejection_reason");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

// Public, no-login access when a resignation token is present — same pattern
// as the Offer Letter candidate portal (hr-employee-offer.php). Without a
// token, this is the employee's own logged-in status tracker.
if (!isset($_GET['token'])) { isUser(); }

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// SCHEMA — all tables/columns are created once by hr-exit-migrate.php.
// Nothing in this file creates or alters tables anymore: running ALTER TABLE
// on every single page load was locking tables under concurrent requests and
// causing intermittent crashes. Run hr-exit-migrate.php once after deploying
// any change here, then this file just assumes the schema already exists.
// =========================================================================

// Defensive wrappers — mysqli_query() can legitimately return false (lock
// timeout, transient error, etc.), and in PHP 8 passing false straight into
// mysqli_fetch_assoc()/mysqli_num_rows() throws a fatal TypeError that kills
// the whole page. Every query result in this file should go through these.
function qFetch($con, $sql) {
    $r = mysqli_query($con, $sql);
    return ($r instanceof mysqli_result) ? mysqli_fetch_assoc($r) : null;
}
function qCount($con, $sql) {
    $r = mysqli_query($con, $sql);
    return ($r instanceof mysqli_result) ? mysqli_num_rows($r) : 0;
}

// Raises one ticket to the HR user who generated this resignation link, so
// they're notified the moment the employee submits — same tickets table and
// ticket_number pattern as raise-a-ticket.php / raiseExitTickets() in
// hr-exit-initiation.php.
function raiseLinkSubmittedTicket($con, $link_generated_by, $employeeName, $exitNumber) {
    $assignee_id = 0;
    $n = mysqli_real_escape_string($con, trim($link_generated_by));
    if ($n !== '') {
        $ur = mysqli_query($con, "SELECT id FROM hr_employees WHERE name='$n' LIMIT 1");
        if ($ur && mysqli_num_rows($ur) > 0) $assignee_id = intval(mysqli_fetch_assoc($ur)['id']);
        else {
            $ur2 = mysqli_query($con, "SELECT id FROM hr_employees WHERE name LIKE '%$n%' LIMIT 1");
            if ($ur2 && mysqli_num_rows($ur2) > 0) $assignee_id = intval(mysqli_fetch_assoc($ur2)['id']);
        }
    }
    if ($assignee_id <= 0) return 0;

    $subject = mysqli_real_escape_string($con, "Resignation Submitted — $employeeName ($exitNumber)");
    $message = mysqli_real_escape_string($con, "$employeeName has submitted their resignation through the link you generated. Please review it in Exit Initiation & Approval ($exitNumber) and begin the HR discussion.");
    $deadline = date('Y-m-d H:i:s', strtotime('+24 hours'));

    $rowmax = qFetch($con, "SELECT MAX(id) AS max_id FROM tickets");
    $nextId = intval($rowmax['max_id'] ?? 0) + 1;
    $ticket_number = 'TICKET' . date('Y') . str_pad($nextId, 4, '0', STR_PAD_LEFT);

    $stmt = mysqli_prepare($con, "INSERT INTO tickets (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by) VALUES (?, 'System', ?, ?, 'open', 'high', 1440, ?, '', NOW(), NOW(), ?, ?)");
    if (!$stmt) return 0;
    mysqli_stmt_bind_param($stmt, "sssssi", $ticket_number, $subject, $message, $deadline, $assignee_id, $assignee_id);
    $ok = mysqli_stmt_execute($stmt);
    mysqli_stmt_close($stmt);
    return $ok ? 1 : 0;
}

// =========================================================================
// HELPERS
// =========================================================================
function resolveDeptPos($con, $empRow) {
    $deptVal = $empRow['department_id'] ?? ($empRow['department'] ?? null);
    $posVal  = $empRow['position_id']   ?? ($empRow['position']   ?? null);
    $dept_id = 0; $pos_id = 0;
    if ($deptVal !== null && $deptVal !== '') {
        if (is_numeric($deptVal)) { $dept_id = intval($deptVal); }
        else {
            $dn = mysqli_real_escape_string($con, trim($deptVal));
            $r = qFetch($con, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1");
            if ($r) $dept_id = intval($r['id']);
        }
    }
    if ($posVal !== null && $posVal !== '') {
        if (is_numeric($posVal)) { $pos_id = intval($posVal); }
        else {
            $pn = mysqli_real_escape_string($con, trim($posVal));
            $where = $dept_id > 0 ? "AND department_id=$dept_id" : "";
            $r = qFetch($con, "SELECT id FROM hr_positions WHERE title='$pn' $where LIMIT 1");
            if ($r) $pos_id = intval($r['id']);
        }
    }
    return [$dept_id, $pos_id];
}

function getNoticeDays($con, $dept_id, $pos_id) {
    $r = qFetch($con, "SELECT notice_days FROM hr_exit_notice_policy WHERE department_id=$dept_id AND position_id=$pos_id LIMIT 1");
    if (!$r) $r = qFetch($con, "SELECT notice_days FROM hr_exit_notice_policy WHERE department_id=$dept_id AND position_id=0 LIMIT 1");
    return $r ? intval($r['notice_days']) : 30;
}

// Ownership checks for the token-scoped Asset Handover write actions below — confirm the row
// being touched actually belongs to THIS token's exit, so one resignation link can never edit
// another employee's checklist.
function assetRunItemForToken($con, $item_row_id, $token_exit_id) {
    return qFetch($con, "SELECT ri.* FROM hr_exit_asset_run_items ri JOIN hr_exit_asset_instance i ON i.id=ri.instance_id WHERE ri.id=" . intval($item_row_id) . " AND i.exit_id=" . intval($token_exit_id) . " LIMIT 1");
}
function assetInstanceForToken($con, $instance_id, $token_exit_id) {
    return qFetch($con, "SELECT * FROM hr_exit_asset_instance WHERE id=" . intval($instance_id) . " AND exit_id=" . intval($token_exit_id) . " LIMIT 1");
}
function clearanceRunItemForToken($con, $item_row_id, $token_exit_id) {
    return qFetch($con, "SELECT ri.* FROM hr_exit_clearance_run_items ri JOIN hr_exit_clearance_instance i ON i.id=ri.instance_id WHERE ri.id=" . intval($item_row_id) . " AND i.exit_id=" . intval($token_exit_id) . " LIMIT 1");
}
function clearanceInstanceForToken($con, $instance_id, $token_exit_id) {
    return qFetch($con, "SELECT * FROM hr_exit_clearance_instance WHERE id=" . intval($instance_id) . " AND exit_id=" . intval($token_exit_id) . " LIMIT 1");
}

// =========================================================================
// TOKEN MODE — the employee-specific resignation link HR generated
// =========================================================================
$tokenRow = null;
if (isset($_GET['token'])) {
    $token = mysqli_real_escape_string($con, $_GET['token']);
    $tokenRow = qFetch($con, "SELECT * FROM hr_exit_requests WHERE token='$token' LIMIT 1");

    $linkExpired = $tokenRow && $tokenRow['link_expires_at'] && strtotime($tokenRow['link_expires_at']) < time();

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'submit_via_link' && $tokenRow && $tokenRow['status'] === 'link_sent' && !$linkExpired) {
        $reason = mysqli_real_escape_string($con, $_POST['reason'] ?? '');
        $requested_last_day = mysqli_real_escape_string($con, $_POST['requested_last_day'] ?? '');
        $is_resignation = ($tokenRow['exit_type'] === 'resignation');
        // For resignation: reason is mandatory. For ack types (termination/contract_end/retirement): reason is optional remarks.
        if (($is_resignation && $reason === '') || $requested_last_day === '') {
            $submit_error = $is_resignation
                ? "Please fill in your reason and requested last working day."
                : "Please select the acknowledged date.";
        } else {
            $empRow = qFetch($con, "SELECT * FROM hr_employees WHERE id={$tokenRow['employee_id']} LIMIT 1");
            list($dept_id, $pos_id) = $empRow ? resolveDeptPos($con, $empRow) : [0, 0];
            $notice_days = getNoticeDays($con, $dept_id, $pos_id);
            mysqli_query($con, "UPDATE hr_exit_requests SET reason='$reason', requested_last_day='$requested_last_day', policy_notice_days=$notice_days, status='initiated', submitted_at=NOW() WHERE id={$tokenRow['id']}");
            raiseLinkSubmittedTicket($con, $tokenRow['link_generated_by'], $empRow['name'] ?? 'The employee', $tokenRow['exit_number']);
            header("Location: hr-employee-exit-request.php?token=$token"); exit;
        }
    }
    // Refresh after any update above
    $tokenRow = qFetch($con, "SELECT * FROM hr_exit_requests WHERE token='$token' LIMIT 1");
}

// =========================================================================
// RESOLVE CURRENT EMPLOYEE (logged-in self-service status view)
// =========================================================================
$empRow = null;
if (!isset($_GET['token']) && $currentUserName) {
    $un = mysqli_real_escape_string($con, $currentUserName);
    $r = mysqli_query($con, "SELECT * FROM hr_employees WHERE name='$un' LIMIT 1");
    if ($r && mysqli_num_rows($r) > 0) {
        $empRow = mysqli_fetch_assoc($r);
    } else {
        $r2 = mysqli_query($con, "SELECT * FROM hr_employees WHERE name LIKE '%$un%' LIMIT 1");
        if ($r2 && mysqli_num_rows($r2) > 0) $empRow = mysqli_fetch_assoc($r2);
    }
}
$employee_id = $empRow ? intval($empRow['id']) : 0;

// =========================================================================
// FETCH THE ACTIVE EXIT REQUEST — either the token row, or this employee's latest
// =========================================================================
$exitRow = null;
if (isset($_GET['token'])) {
    $exitRow = $tokenRow;
} elseif ($employee_id > 0) {
    $exitRow = qFetch($con, "SELECT * FROM hr_exit_requests WHERE employee_id=$employee_id AND status != 'link_sent' ORDER BY id DESC LIMIT 1");
}
if ($exitRow) { 
    $empRow = qFetch($con, "SELECT * FROM hr_employees WHERE id={$exitRow['employee_id']} LIMIT 1");
}

$handoverInstance = null; $handoverItems = []; $handoverPct = 0;
$clearanceItems = []; $clearancePct = 0;
$interviewMeta = null; $settlement = null;
$documents = [];
$assetInstance = null; $assetGrouped = [];
$clrInstance = null; $clrGrouped = []; $clrHeadName2 = ''; $clrDeclaration = '';

if ($exitRow && $exitRow['status'] !== 'link_sent') {
    $exit_id = intval($exitRow['id']);

    $handoverInstance = qFetch($con, "SELECT hi.*, e.name as nominated_name FROM hr_exit_handover_instance hi LEFT JOIN hr_employees e ON e.id=hi.nominated_to_id WHERE hi.exit_id=$exit_id LIMIT 1");
    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_handover_items'") > 0) {
        $hq = mysqli_query($con, "SELECT * FROM hr_exit_handover_items WHERE exit_id=$exit_id ORDER BY sort_order ASC, id ASC");
        if ($hq) while ($row = mysqli_fetch_assoc($hq)) $handoverItems[] = $row;
    }
    $htotal = count($handoverItems);
    $hack = count(array_filter($handoverItems, fn($i) => $i['status'] === 'acknowledged'));
    $handoverPct = $htotal > 0 ? round(($hack / $htotal) * 100) : 0;

    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_clearance_items'") > 0) {
        $cq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_items WHERE exit_id=$exit_id ORDER BY id ASC");
        if ($cq) while ($row = mysqli_fetch_assoc($cq)) $clearanceItems[] = $row;
    }
    $ctotal = count($clearanceItems);
    $ccleared = count(array_filter($clearanceItems, fn($i) => $i['status'] === 'cleared'));
    $clearancePct = $ctotal > 0 ? round(($ccleared / $ctotal) * 100) : 0;

    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_interview_meta'") > 0) {
        $interviewMeta = qFetch($con, "SELECT * FROM hr_exit_interview_meta WHERE exit_id=$exit_id LIMIT 1");
    }
    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_settlement'") > 0) {
        $settlement = qFetch($con, "SELECT * FROM hr_exit_settlement WHERE exit_id=$exit_id LIMIT 1");
        $settlementItems = [];
        if ($settlement && qCount($con, "SHOW TABLES LIKE 'hr_exit_settlement_items'") > 0) {
            $siq = mysqli_query($con, "SELECT * FROM hr_exit_settlement_items WHERE exit_id=$exit_id ORDER BY sort_order ASC, id ASC");
            if ($siq) while ($sir = mysqli_fetch_assoc($siq)) $settlementItems[] = $sir;
        }
    }
    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_documents'") > 0) {
        $doc_where = "exit_id=$exit_id";
        $chk = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'status'");
        if ($chk && mysqli_num_rows($chk) > 0) {
            // Approved docs show as download-ready; pending_signature/pending_hr_final
            // need to surface here too so the employee can sign or see review status.
            $doc_where .= " AND status IN ('approved','pending_signature','pending_hr_final')";
        }
        $dq = mysqli_query($con, "SELECT * FROM hr_exit_documents WHERE $doc_where");
        if ($dq) while ($row = mysqli_fetch_assoc($dq)) $documents[$row['doc_type']] = $row;
    }

    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_asset_instance'") > 0) {
        $assetInstance = qFetch($con, "SELECT * FROM hr_exit_asset_instance WHERE exit_id=$exit_id LIMIT 1");
        if ($assetInstance) {
            $air = mysqli_query($con, "SELECT * FROM hr_exit_asset_run_items WHERE instance_id=" . intval($assetInstance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
            if ($air) while ($ai_row = mysqli_fetch_assoc($air)) {
                $gk = $ai_row['heading_name'];
                if (!isset($assetGrouped[$gk])) $assetGrouped[$gk] = ['heading_id' => $ai_row['heading_id'], 'show_condition_field' => $ai_row['show_condition_field'], 'items' => []];
                $assetGrouped[$gk]['items'][] = $ai_row;
            }
        }
    }

    if (qCount($con, "SHOW TABLES LIKE 'hr_exit_clearance_instance'") > 0) {
        $clrInstance = qFetch($con, "SELECT * FROM hr_exit_clearance_instance WHERE exit_id=$exit_id LIMIT 1");
        if ($clrInstance) {
            if (!empty($clrInstance['position_head_employee_id'])) {
                $chr2 = qFetch($con, "SELECT name FROM hr_employees WHERE id=" . intval($clrInstance['position_head_employee_id']) . " LIMIT 1");
                $clrHeadName2 = $chr2['name'] ?? '';
            }
            if (!empty($clrInstance['template_id'])) {
                $ctpl2 = qFetch($con, "SELECT declaration_text FROM hr_exit_clearance_templates WHERE id=" . intval($clrInstance['template_id']) . " LIMIT 1");
                if ($ctpl2 && !empty($ctpl2['declaration_text'])) {
                    $clrDeclaration = str_replace('{{name}}', $empRow['name'] ?? '', $ctpl2['declaration_text']);
                }
            }
            $cir2 = mysqli_query($con, "SELECT * FROM hr_exit_clearance_run_items WHERE instance_id=" . intval($clrInstance['id']) . " ORDER BY heading_sort ASC, item_sort ASC, id ASC");
            if ($cir2) while ($ci_row2 = mysqli_fetch_assoc($cir2)) {
                $cgk2 = $ci_row2['heading_name'];
                if (!isset($clrGrouped[$cgk2])) $clrGrouped[$cgk2] = ['items' => []];
                $clrGrouped[$cgk2]['items'][] = $ci_row2;
            }
        }
    }
}

// =========================================================================
// TOKEN-SCOPED ASSET HANDOVER WRITE ACTIONS — the employee fills this in
// through their own resignation link, no login required. Every handler
// verifies the row being touched belongs to THIS token's exit first.
// =========================================================================
if (isset($_GET['token']) && $tokenRow && $_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['ajax_action'])) {
    header('Content-Type: application/json');
    $token_exit_id = intval($tokenRow['id']);

    if ($_POST['ajax_action'] === 'token_toggle_asset_item') {
        $item = assetRunItemForToken($con, $_POST['run_item_id'] ?? 0, $token_exit_id);
        if (!$item) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $checked = intval($_POST['checked'] ?? 0) == 1 ? 1 : 0;
        if ($checked) {
            mysqli_query($con, "UPDATE hr_exit_asset_run_items SET is_checked=1, checked_by='Employee', checked_at=NOW() WHERE id=" . intval($item['id']));
        } else {
            mysqli_query($con, "UPDATE hr_exit_asset_run_items SET is_checked=0, checked_by=NULL, checked_at=NULL WHERE id=" . intval($item['id']));
        }
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_save_asset_detail') {
        $item = assetRunItemForToken($con, $_POST['run_item_id'] ?? 0, $token_exit_id);
        if (!$item) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $cond = mysqli_real_escape_string($con, trim($_POST['condition_text'] ?? ''));
        $rem  = mysqli_real_escape_string($con, trim($_POST['remarks'] ?? ''));
        mysqli_query($con, "UPDATE hr_exit_asset_run_items SET condition_text='$cond', remarks='$rem' WHERE id=" . intval($item['id']));
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_save_asset_signature') {
        $inst = assetInstanceForToken($con, $_POST['instance_id'] ?? 0, $token_exit_id);
        if (!$inst) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $sig = trim($_POST['signature_data'] ?? '');
        if (empty($sig)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $sig_e = mysqli_real_escape_string($con, $sig);
        $empName_e = mysqli_real_escape_string($con, $empRow['name'] ?? 'Employee');
        mysqli_query($con, "UPDATE hr_exit_asset_instance SET signature_data='$sig_e', signed_by='$empName_e', signed_at=NOW(), status='pending_approval', rejection_reason=NULL WHERE id=" . intval($inst['id']));
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_set_clearance_response') {
        $item = clearanceRunItemForToken($con, $_POST['run_item_id'] ?? 0, $token_exit_id);
        if (!$item) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $resp = $_POST['response'] ?? '';
        if (!in_array($resp, ['yes','no','na','unanswered'], true)) { echo json_encode(['success' => false, 'message' => 'Invalid response']); exit; }
        $empName_e2 = mysqli_real_escape_string($con, $empRow['name'] ?? 'Employee');
        mysqli_query($con, "UPDATE hr_exit_clearance_run_items SET response='$resp', checked_by='$empName_e2', checked_at=NOW() WHERE id=" . intval($item['id']));
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_save_clearance_remarks') {
        $item = clearanceRunItemForToken($con, $_POST['run_item_id'] ?? 0, $token_exit_id);
        if (!$item) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $rem2 = mysqli_real_escape_string($con, trim($_POST['remarks'] ?? ''));
        mysqli_query($con, "UPDATE hr_exit_clearance_run_items SET remarks='$rem2' WHERE id=" . intval($item['id']));
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_save_clearance_signature') {
        $inst2 = clearanceInstanceForToken($con, $_POST['instance_id'] ?? 0, $token_exit_id);
        if (!$inst2) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $sig2 = trim($_POST['signature_data'] ?? '');
        if (empty($sig2)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $emp_rem = trim($_POST['employee_remarks'] ?? '');
        $emp_rem_e = mysqli_real_escape_string($con, $emp_rem);
        $sig2_e = mysqli_real_escape_string($con, $sig2);
        $empName2_e = mysqli_real_escape_string($con, $empRow['name'] ?? 'Employee');
        mysqli_query($con, "UPDATE hr_exit_clearance_instance SET employee_remarks='$emp_rem_e', employee_signature_data='$sig2_e', employee_signed_by='$empName2_e', employee_signed_at=NOW(), status='pending_hr_approval', position_head_rejection_reason=NULL, hr_rejection_reason=NULL WHERE id=" . intval($inst2['id']));
        $exit_id_e = intval($inst2['exit_id']);
        mysqli_query($con, "INSERT INTO hr_exit_clearance_history (exit_id, action_name, action_by) VALUES ($exit_id_e, 'Employee digitally signed the clearance document', '$empName2_e')");
        echo json_encode(['success' => true]); exit;
    }

    if ($_POST['ajax_action'] === 'token_save_document_signature') {
        $doc_id3 = intval($_POST['doc_id'] ?? 0);
        $sig3 = trim($_POST['signature_data'] ?? '');
        if (empty($sig3)) { echo json_encode(['success' => false, 'message' => 'Signature is required.']); exit; }
        $doc3 = qFetch($con, "SELECT id FROM hr_exit_documents WHERE id=$doc_id3 AND exit_id=$token_exit_id AND status='pending_signature' LIMIT 1");
        if (!$doc3) { echo json_encode(['success' => false, 'message' => 'Not found']); exit; }
        $sig3_e = mysqli_real_escape_string($con, $sig3);
        $empName3_e = mysqli_real_escape_string($con, $empRow['name'] ?? 'Employee');
        mysqli_query($con, "UPDATE hr_exit_documents SET employee_signature_data='$sig3_e', employee_signed_by='$empName3_e', employee_signed_at=NOW(), status='pending_hr_final' WHERE id=$doc_id3");
        echo json_encode(['success' => true]); exit;
    }

    echo json_encode(['success' => false, 'message' => 'Unknown action']); exit;
}

// =========================================================================
// STAGE MAPPING FOR THE STEPPER
// =========================================================================
$stageOrder = ['initiated'=>1,'retained'=>7,'approved'=>2,'handover'=>3,'clearance'=>4,'interview_settlement'=>5,'documents'=>6,'closed'=>7,'rejected'=>0];
$currentStageIdx = $exitRow ? ($stageOrder[$exitRow['status']] ?? 1) : 0;

// Auto-advance: if clearance instance is completed but hr_exit_requests status is still 'clearance', fix it
if ($exitRow && $exitRow['status'] === 'clearance' && !empty($clrInstance) && $clrInstance['status'] === 'completed') {
    $adv_id = intval($exitRow['id']);
    mysqli_query($con, "UPDATE hr_exit_requests SET status='interview_settlement' WHERE id=$adv_id AND status='clearance'");
    $exitRow['status'] = 'interview_settlement';
    $currentStageIdx = 5;
}

$docLabels = ['relieving_letter' => 'Relieving Letter', 'experience_certificate' => 'Experience Certificate', 'settlement_statement' => 'Settlement Statement', 'termination_letter' => 'Termination Letter', 'retirement_confirmation_letter' => 'Retirement Confirmation', 'non_renewal_notification' => 'Non Renewal Notification'];
$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']==='on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>My Exit Journey</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--teal:#0f766e;--amber:#b45309;--purple:#6d28d9;--coral:#c2410c;--green:#10b981;--red:#ef4444;--gray-bg:#f0f4f8;}
*{box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--gray-bg);margin:0;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:22px 32px;border-radius:12px;margin:20px;box-shadow:0 4px 20px rgba(15,37,87,.3);}
.hdr h1{color:#fff;font-weight:800;font-size:1.4rem;margin:0;}
.hdr p{color:rgba(255,255,255,.65);font-size:12px;margin:4px 0 0;}
.wrap{max-width:900px;margin:0 auto;padding:0 20px 40px;}
.card-box{background:#fff;border-radius:12px;padding:24px;box-shadow:0 2px 10px rgba(0,0,0,.06);margin-bottom:20px;}
.card-box h5{font-weight:800;color:var(--navy);margin-bottom:14px;font-size:15px;}
.fc{border:2px solid #e2e8f0;border-radius:8px;padding:10px 13px;font-size:13px;font-weight:600;width:100%;}
label.fl{font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;}
.fg{margin-bottom:14px;}
.btn-p{padding:10px 22px;border:none;border-radius:9px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;text-decoration:none;display:inline-block;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));}
.btn-green{background:linear-gradient(135deg,var(--green),#059669);}

.stepper{display:flex;align-items:flex-start;margin-bottom:20px;background:#fff;border-radius:12px;padding:22px 12px;box-shadow:0 2px 10px rgba(0,0,0,.06);overflow-x:auto;gap:5px;}
.step{flex:1;min-width:120px;text-align:center;position:relative;}
.step .step-circle{width:40px;height:40px;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 6px;font-size:14px;font-weight:800;border:3px solid #e2e8f0;background:#f8fafc;color:#94a3b8;position:relative;z-index:2;}
.step .step-line{position:absolute;top:20px;left:-50%;width:100%;height:3px;background:#e2e8f0;z-index:1;}
.step:first-child .step-line{display:none;}
.step .step-label{font-size:10.5px;font-weight:700;color:#94a3b8;word-wrap:break-word;line-height:1.2;margin-top:4px;}
.step.done .step-circle{background:var(--green);border-color:var(--green);color:#fff;}
.step.done .step-line{background:var(--green);}
.step.done .step-label{color:var(--green);}
.step.current .step-circle{background:var(--blue);border-color:var(--blue);color:#fff;box-shadow:0 0 0 5px rgba(26,63,196,.15);}
.step.current .step-label{color:var(--blue);}
.step.rejected .step-circle{background:var(--red);border-color:var(--red);color:#fff;}
.step.rejected .step-label{color:var(--red);}

.phase-bar{display:flex;justify-content:space-between;align-items:center;padding:12px 18px;border-radius:10px 10px 0 0;color:#fff;font-weight:800;font-size:13px;}
.phase-1{background:var(--navy);}
.phase-2{background:var(--teal);}
.phase-3{background:var(--amber);}
.phase-4{background:var(--purple);}
.phase-5{background:var(--coral);}
.phase-body{border:1.5px solid #e2e8f0;border-top:none;border-radius:0 0 10px 10px;padding:18px;margin-bottom:18px;}
.phase-body.locked{background:#f8fafc;color:#94a3b8;text-align:center;padding:30px 18px;}

.item-row{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border:1px solid #e2e8f0;border-radius:8px;margin-bottom:8px;flex-wrap:wrap;gap:8px;}
.badge{padding:4px 10px;border-radius:12px;font-size:11px;font-weight:800;}
.b-pending{background:#f1f5f9;color:#475569;}
.b-filled{background:#fef3c7;color:#92400e;}
.b-acknowledged, .b-cleared, .b-approved{background:#d1fae5;color:#065f46;}
.b-rejected{background:#fee2e2;color:#991b1b;}

.progress-track{height:9px;border-radius:5px;background:#e2e8f0;overflow:hidden;margin-bottom:10px;}
.progress-fill{height:100%;background:linear-gradient(90deg,var(--blue),var(--green));}

.settle-total{background:#f5f3ff;border:2px solid #c4b5fd;border-radius:10px;padding:14px;text-align:center;margin-top:10px;}
.settle-total .amt{font-size:22px;font-weight:800;color:var(--purple);}
.doc-row{display:flex;justify-content:space-between;align-items:center;padding:12px 14px;border:1px solid #e2e8f0;border-radius:8px;margin-bottom:8px;flex-wrap:wrap;gap:8px;}

.asset-row-card{border:1.5px solid #e2e8f0;border-radius:10px;padding:12px 14px;margin-bottom:10px;}
.asset-row-card.is-checked{border-color:#bbf7d0;background:#f0fdf4;}
.sig-pad-box{border:2px dashed #a78bfa;border-radius:10px;background:#faf5ff;padding:12px;max-width:500px;}
canvas.emp-sig-canvas{width:100%;height:140px;border:1px solid #ddd6fe;border-radius:8px;background:#fff;cursor:crosshair;touch-action:none;display:block;}
</style>
</head>
<body>
<div class="hdr"><h1><i class="fas fa-route mr-2"></i>My Exit Journey</h1><p>Submit your resignation via your secure link and track every step through to closure</p></div>
<div class="wrap">

<?php if (!empty($submit_error)): ?>
<div class="alert alert-danger"><?php echo htmlspecialchars($submit_error); ?></div>
<?php endif; ?>

<?php if (isset($_GET['token']) && !$tokenRow): ?>
<div class="card-box text-center"><i class="fas fa-link-slash fa-2x mb-2" style="color:#94a3b8;"></i><h5>Invalid or expired link</h5><p style="color:#64748b;">This resignation link is not valid. Please contact HR for a new one.</p></div>

<?php elseif (isset($_GET['token']) && $tokenRow && $tokenRow['status'] === 'link_sent' && $linkExpired): ?>
<div class="card-box text-center"><i class="fas fa-hourglass-end fa-2x mb-2" style="color:#94a3b8;"></i><h5>This link has expired</h5><p style="color:#64748b;">This link expired on <?php echo date('d M Y', strtotime($tokenRow['link_expires_at'])); ?>. Please contact HR for a new one.</p></div>

<?php elseif (isset($_GET['token']) && $tokenRow && $tokenRow['status'] === 'link_sent'): ?>
<?php if ($tokenRow['exit_type'] === 'resignation'): ?>
<!-- Employee submits their resignation via the unique link HR sent them — UNTOUCHED -->
<div class="card-box">
  <h5><i class="fas fa-file-signature mr-2"></i>Submit Your Resignation — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
  <p style="color:#64748b;font-size:12.5px;">This link was generated specifically for you by HR. Once submitted, your request goes to HR for discussion. This link is valid until <strong><?php echo $tokenRow['link_expires_at'] ? date('d M Y', strtotime($tokenRow['link_expires_at'])) : '—'; ?></strong>.</p>
  <form method="POST" id="submitResignationForm">
    <input type="hidden" name="action" value="submit_via_link">
    <div class="fg"><label class="fl">Reason for Leaving</label><textarea name="reason" class="fc" style="height:90px;" placeholder="Let us know why you're leaving..." required></textarea></div>
    <div class="fg"><label class="fl">Requested Last Working Day</label><input type="date" name="requested_last_day" class="fc" required></div>
    <button type="button" class="btn-p btn-navy" onclick="showCustomConfirm('Are you sure you want to submit this resignation?', function(){ document.getElementById('submitResignationForm').submit(); });"><i class="fas fa-paper-plane mr-1"></i> Submit Resignation</button>
  </form>
</div>

<?php else: ?>
<!-- Acknowledgment form for Termination / Contract End / Retirement — NEW branch, separate from resignation -->
<?php
  $ackTypeLabels = ['termination'=>'Termination Notice','contract_end'=>'Contract Non-Renewal','retirement'=>'Retirement Confirmation'];
  $ackTypeIcons  = ['termination'=>'fa-gavel','contract_end'=>'fa-file-contract','retirement'=>'fa-user-clock'];
  $ackLabel = $ackTypeLabels[$tokenRow['exit_type']] ?? ucfirst(str_replace('_',' ',$tokenRow['exit_type']));
  $ackIcon  = $ackTypeIcons[$tokenRow['exit_type']] ?? 'fa-bell';
?>
<div class="card-box">
  <h5><i class="fas <?php echo $ackIcon; ?> mr-2"></i>Acknowledge: <?php echo htmlspecialchars($ackLabel); ?> — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
  <p style="color:#64748b;font-size:12.5px;">HR has initiated a <?php echo strtolower($ackLabel); ?> for you. Please read the details below and formally acknowledge receipt. This link is valid until <strong><?php echo $tokenRow['link_expires_at'] ? date('d M Y', strtotime($tokenRow['link_expires_at'])) : '—'; ?></strong>.</p>
  <?php if ($tokenRow['link_reason']): ?>
  <div style="background:#f0f4ff;border-left:4px solid #1a3fc4;border-radius:8px;padding:14px 16px;margin-bottom:16px;">
    <div style="font-weight:800;font-size:12px;color:#1a3fc4;margin-bottom:6px;"><i class="fas fa-info-circle mr-1"></i> HR Note</div>
    <p style="margin:0;font-size:13px;color:#334155;"><?php echo nl2br(htmlspecialchars($tokenRow['link_reason'])); ?></p>
  </div>
  <?php endif; ?>
  <form method="POST" id="submitAckForm">
    <input type="hidden" name="action" value="submit_via_link">
    <div class="fg"><label class="fl">Your Comments / Remarks (optional)</label><textarea name="reason" class="fc" style="height:80px;" placeholder="Any comments you'd like HR to record..."></textarea></div>
    <div class="fg"><label class="fl">Acknowledged Date</label><input type="date" name="requested_last_day" class="fc" value="<?php echo date('Y-m-d'); ?>" required></div>
    <div class="fg" style="display:flex;align-items:flex-start;gap:10px;background:#fef9ec;border:1px solid #f59e0b;border-radius:8px;padding:12px;">
      <input type="checkbox" id="ackConfirm" style="margin-top:3px;width:18px;height:18px;flex-shrink:0;" required>
      <label for="ackConfirm" style="font-size:13px;font-weight:600;color:#92400e;cursor:pointer;margin:0;">I, <strong><?php echo htmlspecialchars($empRow['name'] ?? 'the undersigned'); ?></strong>, confirm that I have read and understood the <?php echo strtolower($ackLabel); ?> communicated to me by HR, and I formally acknowledge receipt of this notice.</label>
    </div>
    <button type="button" class="btn-p btn-navy" style="margin-top:14px;" onclick="
      if (!document.getElementById('ackConfirm').checked) { alert('Please tick the acknowledgment checkbox before submitting.'); return; }
      showAckConfirm();
    "><i class="fas fa-check-circle mr-1"></i> Submit Acknowledgment</button>
  </form>
</div>

<!-- Styled confirm modal — self-contained for this page section -->
<div id="ackConfirmOverlay" style="display:none;position:fixed;inset:0;background:rgba(15,37,87,.45);z-index:99999;align-items:center;justify-content:center;">
  <div style="background:#fff;border-radius:16px;padding:36px 32px;max-width:400px;width:90%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.25);">
    <div style="width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,#1a3fc4,#0f2557);display:flex;align-items:center;justify-content:center;margin:0 auto 16px;">
      <i class="fas fa-question" style="color:#fff;font-size:22px;"></i>
    </div>
    <h5 style="font-weight:800;color:#0f2557;margin-bottom:8px;">Please Confirm</h5>
    <p style="color:#64748b;font-size:13px;margin-bottom:24px;">Confirm acknowledgment of this notice? This action cannot be undone.</p>
    <div style="display:flex;gap:10px;justify-content:center;">
      <button type="button" onclick="document.getElementById('ackConfirmOverlay').style.display='none';" style="padding:10px 24px;border:2px solid #e2e8f0;background:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;">Cancel</button>
      <button type="button" onclick="document.getElementById('ackConfirmOverlay').style.display='none'; document.getElementById('submitAckForm').submit();" style="padding:10px 24px;border:none;background:linear-gradient(135deg,#0f2557,#1a3fc4);border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;color:#fff;">Confirm</button>
    </div>
  </div>
</div>
<script>
function showAckConfirm() {
  document.getElementById('ackConfirmOverlay').style.display = 'flex';
}
</script>
<?php endif; ?>



<?php elseif (!isset($_GET['token']) && !$empRow): ?>
<div class="card-box text-center"><i class="fas fa-user-slash fa-2x mb-2" style="color:#94a3b8;"></i><h5>Employee record not found</h5><p style="color:#64748b;">We couldn't match your account to an employee record. Please contact HR.</p></div>

<?php elseif (!$exitRow): ?>
<div class="card-box text-center"><i class="fas fa-info-circle fa-2x mb-2" style="color:#94a3b8;"></i><h5>No active exit request</h5><p style="color:#64748b;">You don't have an exit in progress. If you wish to resign, please speak to HR — they will send you a secure, one-time link to submit your resignation.</p></div>

<?php /* 
  The "Acknowledgment Received" screen has been removed so that employees 
  can immediately see their full Exit Journey (Progress Tracker) after acknowledging,
  just like resignations.
*/ ?><?php else: ?>
<!-- Active exit journey -->
<?php
// 7 stepper nodes collapse into 5 content phases: Submitted+Approved share Phase 1,
// Documents+Closed share Phase 5.
$stageToPhase = [1=>1, 2=>1, 3=>2, 4=>3, 5=>4, 6=>5, 7=>5];
$defaultPhase = $stageToPhase[$currentStageIdx] ?? 1;
?>
<div class="stepper">
  <?php
  $steps = [1=>'Submitted',2=>'Approved',3=>'Asset Handover',4=>'Department-Position Clearance',5=>'Interview & Settlement',6=>'Documents',7=>'Closed'];
  foreach ($steps as $num => $label):
    if ($exitRow['status'] === 'retained') { $state = ($num == 1) ? 'done' : ''; }
    elseif ($num < $currentStageIdx) $state = 'done';
    elseif ($num == $currentStageIdx) $state = 'current';
    else $state = '';
  ?>
  <div class="step <?php echo $state; ?>" style="cursor:pointer;" onclick="switchPhaseTab(<?php echo $stageToPhase[$num]; ?>)">
    <div class="step-line"></div>
    <div class="step-circle"><i class="fas <?php echo $state=='done'?'fa-check':'fa-circle'; ?>" style="font-size:<?php echo $state=='done'?'14px':'8px'; ?>;"></i></div>
    <div class="step-label"><?php echo $label; ?></div>
  </div>
  <?php endforeach; ?>
</div>

<?php if ($exitRow['status'] === 'retained'): ?>
<div class="alert alert-success"><i class="fas fa-heart mr-1"></i> Great news — you were retained during discussion and your exit request (<?php echo htmlspecialchars($exitRow['exit_number']); ?>) has been closed as a retention, not a rejection.</div>
<?php elseif ($exitRow['status'] === 'rejected'): ?>
<div class="alert alert-danger">Your exit request (<?php echo htmlspecialchars($exitRow['exit_number']); ?>) was not approved. Remarks: <?php echo htmlspecialchars($exitRow['hr_remarks'] ?: '—'); ?>.</div>
<?php endif; ?>

<div id="phaseTab-1" class="phase-tab-panel" style="display:<?php echo $defaultPhase==1?'block':'none'; ?>;">
<!-- PHASE 1: Initiation & Approval -->
<div class="phase-bar phase-1"><span><i class="fas fa-door-open mr-2"></i>1. Exit Request — <?php echo htmlspecialchars($exitRow['exit_number']); ?></span><span><?php echo ucfirst(str_replace('_',' ',$exitRow['exit_type'])); ?></span></div>
<div class="phase-body">
  <div style="font-weight:800; color:var(--navy); font-size:16px; margin-bottom:14px; border-bottom:1px solid #e2e8f0; padding-bottom:8px;">
    <?php echo htmlspecialchars($empRow['name'] ?? ''); ?> 
    <span style="color:#64748b; font-size:13px; font-weight:600; margin-left:6px;">(<?php echo htmlspecialchars($empRow['position'] ?? 'N/A'); ?>)</span>
  </div>
  <div class="fg"><label class="fl">Reason</label><div><?php echo nl2br(htmlspecialchars($exitRow['reason'] ?: '—')); ?></div></div>
  <div class="row">
    <div class="col-md-4"><label class="fl">Requested Last Day</label><div><?php echo $exitRow['requested_last_day'] ? date('d M Y', strtotime($exitRow['requested_last_day'])) : '—'; ?></div></div>
    <div class="col-md-4"><label class="fl">HR</label><span class="badge b-<?php echo $exitRow['hr_approval']; ?>"><?php echo ucfirst($exitRow['hr_approval']); ?></span></div>
    <div class="col-md-4"><label class="fl">Manager</label><span class="badge b-<?php echo $exitRow['manager_approval']; ?>"><?php echo ucfirst($exitRow['manager_approval']); ?></span></div>
  </div>
  <?php if ($exitRow['final_last_working_day']): ?>
  <div class="fg mt-2"><label class="fl">Confirmed Last Working Day</label><strong style="color:var(--navy);"><?php echo date('d M Y', strtotime($exitRow['final_last_working_day'])); ?></strong></div>
  <?php endif; ?>
  <?php if ($exitRow['hr_remarks']): ?><div class="fg"><label class="fl">HR Remarks</label><?php echo htmlspecialchars($exitRow['hr_remarks']); ?></div><?php endif; ?>
  <?php if ($exitRow['manager_remarks']): ?><div class="fg"><label class="fl">Manager Remarks</label><?php echo htmlspecialchars($exitRow['manager_remarks']); ?></div><?php endif; ?>
</div>
</div>

<?php if (!in_array($exitRow['status'], ['retained','rejected'])): ?>
<div id="phaseTab-2" class="phase-tab-panel" style="display:<?php echo $defaultPhase==2?'block':'none'; ?>;">
<!-- PHASE 2: Handover -->
<div class="phase-bar phase-2"><span><i class="fas fa-boxes-stacked mr-2"></i>2. Asset Handover</span><span><?php echo $handoverPct; ?>%</span></div>
<?php if ($currentStageIdx < 3): ?>
<div class="phase-body locked"><i class="fas fa-lock mb-2"></i><br>Not started yet — this begins once your exit is approved.</div>
<?php else: ?>
<div class="phase-body">

  <?php if ($assetInstance && $assetInstance['status'] !== 'not_applicable'): ?>
  <h6 style="font-weight:800;color:var(--navy);margin-bottom:10px;"><i class="fas fa-boxes-stacked mr-2"></i>HR Handover — Asset Return Checklist</h6>

  <?php
  $ah_badge_map = [
      'completed'        => ['b-acknowledged', 'Approved'],
      'pending_approval' => ['b-filled', 'Pending HR Approval'],
      'rejected'         => ['b-rejected', 'Rejected — Please Resubmit'],
  ];
  $ah_badge = $ah_badge_map[$assetInstance['status']] ?? ['b-pending', 'In Progress'];
  // Fill controls only ever work via the resignation link's own write actions (see token-scoped
  // handlers above) — force read-only if this page is ever viewed without a token.
  $ah_readonly = in_array($assetInstance['status'], ['pending_approval', 'completed']) || !isset($_GET['token']);
  ?>
  <div style="margin-bottom:12px;">
    <span class="badge <?php echo $ah_badge[0]; ?>"><?php echo $ah_badge[1]; ?></span>
    <?php if (isset($_GET['token'])): ?>
    <a href="hr-exit-handover.php?view_asset_doc=<?php echo intval($assetInstance['exit_id']); ?>&token=<?php echo urlencode($_GET['token']); ?>" target="_blank" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;margin-left:8px;"><i class="fas fa-print mr-1"></i> Preview / Print</a>
    <?php endif; ?>
  </div>

  <?php if ($assetInstance['status'] === 'rejected'): ?>
  <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#991b1b;margin-bottom:14px;">
    <strong>Rejected by HR</strong> on <?php echo date('d M Y, h:i A', strtotime($assetInstance['reviewed_at'])); ?><br>
    Reason: <?php echo htmlspecialchars($assetInstance['rejection_reason']); ?><br>
    Please review, update if needed, and re-sign below.
  </div>
  <?php endif; ?>

  <div style="display:flex;flex-wrap:wrap;gap:12px;margin-bottom:14px;padding:12px 14px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;font-size:12px;">
    <div><strong>Employee ID:</strong> <?php echo htmlspecialchars($empRow['employee_id'] ?? '—'); ?></div>
    <div><strong>Department:</strong> <?php echo htmlspecialchars($empRow['department'] ?? '—'); ?></div>
    <div><strong>Designation:</strong> <?php echo htmlspecialchars($empRow['position'] ?? '—'); ?></div>
    <div><strong>Last Working Day:</strong> <?php echo $exitRow['final_last_working_day'] ? date('d M Y', strtotime($exitRow['final_last_working_day'])) : '—'; ?></div>
  </div>

  <?php foreach ($assetGrouped as $g_name => $g_data): ?>
  <div style="font-weight:800;color:var(--navy);font-size:14px;margin:20px 0 10px;padding-bottom:6px;border-bottom:2px solid #eef2ff;"><?php echo htmlspecialchars($g_name); ?></div>
  <?php if ($g_data['show_condition_field']): ?>
  <div style="overflow-x:auto;">
    <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
      <thead><tr><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Sl. No.</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Asset</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%;">Returned</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:16%;">Condition</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:24%;">Remarks</th></tr></thead>
      <tbody>
      <?php foreach ($g_data['items'] as $vidx => $it): ?>
      <tr style="background:<?php echo $vidx%2==1?'#f8faff':'#fff'; ?>;">
        <td style="border:1px solid #cbd5e1; padding:8px 10px;"><?php echo $vidx+1; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;"><?php echo htmlspecialchars($it['item_text']); ?><?php if ($it['is_custom']): ?><span class="badge" style="background:#ede9fe;color:#5b21b6;margin-left:6px;font-size:10px;">Custom</span><?php endif; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
          <?php if (!$ah_readonly): ?>
          <input type="checkbox" <?php echo $it['is_checked']?'checked':''; ?> onchange="empToggleAssetItem(<?php echo $it['id']; ?>, this.checked)" style="width:18px;height:18px;cursor:pointer;margin-top:2px;">
          <?php else: ?>
          <span style="font-weight:bold; color:<?php echo $it['is_checked']?'#059669':'#94a3b8'; ?>;"><?php echo $it['is_checked'] ? '&#10003;' : ''; ?></span>
          <?php endif; ?>
        </td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;">
          <?php if (!$ah_readonly && $g_data['show_condition_field']): ?>
          <input type="text" class="fc" id="empCond_<?php echo $it['id']; ?>" value="<?php echo htmlspecialchars($it['condition_text'] ?? ''); ?>" onblur="empSaveAssetDetail(<?php echo $it['id']; ?>)" style="padding:4px 8px;font-size:12px;width:100%;" placeholder="Condition">
          <?php else: ?>
          <?php echo htmlspecialchars($it['condition_text'] ?? ''); ?>
          <?php endif; ?>
        </td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;">
          <?php if (!$ah_readonly): ?>
          <input type="text" class="fc" id="empRem_<?php echo $it['id']; ?>" value="<?php echo htmlspecialchars($it['remarks'] ?? ''); ?>" onblur="empSaveAssetDetail(<?php echo $it['id']; ?>)" style="padding:4px 8px;font-size:12px;width:100%;" placeholder="Remarks (optional)">
          <?php else: ?>
          <?php echo htmlspecialchars($it['remarks'] ?? ''); ?>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php else: ?>
  <div style="overflow-x:auto;">
    <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
      <thead><tr><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%;">Sl. No.</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px;">Asset</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%;">Returned</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:24%;">Remarks</th></tr></thead>
      <tbody>
      <?php foreach ($g_data['items'] as $vidx => $it): ?>
      <tr style="background:<?php echo $vidx%2==1?'#f8faff':'#fff'; ?>;">
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;"><?php echo $vidx+1; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;"><strong><?php echo htmlspecialchars($it['item_text']); ?></strong><?php if ($it['is_custom']): ?><span class="badge" style="background:#ede9fe;color:#5b21b6;margin-left:6px;font-size:10px;">Custom</span><?php endif; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center;">
          <?php if (!$ah_readonly): ?>
          <input type="checkbox" <?php echo $it['is_checked']?'checked':''; ?> onchange="empToggleAssetItem(<?php echo $it['id']; ?>, this.checked)" style="width:18px;height:18px;cursor:pointer;margin-top:2px;">
          <?php else: ?>
          <span style="font-weight:bold; color:<?php echo $it['is_checked']?'#059669':'#94a3b8'; ?>;"><?php echo $it['is_checked'] ? '&#10003;' : ''; ?></span>
          <?php endif; ?>
        </td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word;">
          <?php if (!$ah_readonly): ?>
          <input type="text" class="fc" id="empRem_<?php echo $it['id']; ?>" value="<?php echo htmlspecialchars($it['remarks'] ?? ''); ?>" onblur="empSaveAssetDetail(<?php echo $it['id']; ?>)" style="padding:4px 8px;font-size:12px;width:100%;" placeholder="Remarks (optional)">
          <?php else: ?>
          <?php echo htmlspecialchars($it['remarks'] ?? ''); ?>
          <?php endif; ?>
        </td>
      </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
  <?php endforeach; ?>

  <?php if (empty($assetGrouped)): ?>
  <p style="color:#94a3b8;font-size:13px;">No checklist items yet.</p>
  <?php endif; ?>

  <?php if ($assetInstance['status'] === 'completed'): ?>
  <div class="alert alert-success mt-2" style="font-size:12.5px;"><i class="fas fa-check-circle mr-1"></i> Approved. Thank you.</div>
  <?php if (!empty($assetInstance['signature_data'])): ?><img src="<?php echo htmlspecialchars($assetInstance['signature_data']); ?>" style="max-height:80px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
  <?php elseif ($assetInstance['status'] === 'pending_approval'): ?>
  <div class="alert alert-warning mt-2" style="font-size:12.5px;"><i class="fas fa-hourglass-half mr-1"></i> Submitted — awaiting HR approval.</div>
  <?php if (!empty($assetInstance['signature_data'])): ?><img src="<?php echo htmlspecialchars($assetInstance['signature_data']); ?>" style="max-height:80px;border:1px solid #e2e8f0;border-radius:8px;"><?php endif; ?>
  <?php elseif (!$ah_readonly): ?>
  <div style="font-weight:800;color:var(--navy);font-size:13px;margin-top:14px;">Your Signature</div>
  <p style="font-size:11.5px;color:#64748b;margin-bottom:8px;">Draw your signature below, then submit for HR approval.</p>
  <div class="sig-pad-box">
    <canvas id="empAssetSigCanvas" width="460" height="140" class="emp-sig-canvas"></canvas>
    <div style="margin-top:8px;display:flex;gap:8px;">
      <button type="button" class="btn-p" style="background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;" onclick="empClearAssetSig()">Clear</button>
      <button type="button" class="btn-p btn-navy" onclick="empFinalizeAssetSignature(<?php echo $assetInstance['id']; ?>)">Submit for Approval</button>
    </div>
  </div>
  <?php endif; ?>
  <?php endif; ?>
</div>
</div>
<?php endif; ?>

<div id="phaseTab-3" class="phase-tab-panel" style="display:<?php echo $defaultPhase==3?'block':'none'; ?>;">
<!-- PHASE 3: Clearance -->
<div class="phase-bar phase-3"><span><i class="fas fa-clipboard-check mr-2"></i>3. Department-Position Clearance</span><span><?php echo $clearancePct; ?>%</span></div>
<?php if ($currentStageIdx < 4): ?>
<div class="phase-body locked"><i class="fas fa-lock mb-2"></i><br>Locked until Asset Handover is fully acknowledged.</div>
<?php else: ?>
<div class="phase-body">

  <?php if ($clrInstance && $clrInstance['status'] !== 'not_applicable'): ?>
  <h6 style="font-weight:800;color:var(--navy);margin-bottom:10px;"><i class="fas fa-user-shield mr-2"></i>Department-Position Clearance</h6>

  <?php
  $clr_badge_map2 = [
      'completed'                    => ['b-acknowledged', 'Approved'],
      'pending_position_head_review' => ['b-filled', 'Pending Review'],
      'rejected_by_position_head'    => ['b-rejected', 'Rejected — Please Resubmit'],
      'pending_hr_approval'          => ['b-filled', 'Pending HR Approval'],
  ];
  $clr_badge2 = $clr_badge_map2[$clrInstance['status']] ?? ['b-pending', 'In Progress'];
  $clr_readonly2 = in_array($clrInstance['status'], ['pending_position_head_review','pending_hr_approval','completed']) || !isset($_GET['token']);
  ?>
  <div style="margin-bottom:12px;">
    <span class="badge <?php echo $clr_badge2[0]; ?>"><?php echo $clr_badge2[1]; ?></span>
    <?php if (isset($_GET['token'])): ?>
    <a href="hr-exit-handover.php?view_clearance_doc=<?php echo intval($clrInstance['exit_id']); ?>&token=<?php echo urlencode($_GET['token']); ?>" target="_blank" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;margin-left:8px;"><i class="fas fa-print mr-1"></i> Preview / Print</a>
    <?php endif; ?>
  </div>

  <?php if (!$clr_readonly2 && !empty($clrInstance['position_head_signature_data']) && $clrInstance['status'] !== 'rejected_by_position_head' && empty($clrInstance['hr_rejection_reason'])): ?>
  <div class="alert alert-info" style="font-size:12.5px;background:#eff6ff;border:1px solid #bfdbfe;color:#1e3a8a;margin-bottom:14px;">
    <i class="fas fa-info-circle mr-1"></i> <strong>Action Required:</strong> The Position Head has signed the document. Please add any remarks you might have, draw your signature at the bottom, then submit for final HR approval.
  </div>
  <?php endif; ?>

  <?php if ($clrInstance['status'] === 'rejected_by_position_head'): ?>
  <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#991b1b;margin-bottom:14px;">
    <strong>Rejected by <?php echo htmlspecialchars($clrHeadName2 ?: 'the Position Head'); ?></strong><br>
    Reason: <?php echo htmlspecialchars($clrInstance['position_head_rejection_reason']); ?><br>
    Please review, update if needed, and re-sign below.
  </div>
  <?php endif; ?>
  <?php if ($clrInstance['status'] === 'in_progress' && !empty($clrInstance['hr_rejection_reason'])): ?>
  <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;font-size:12.5px;color:#991b1b;margin-bottom:14px;">
    <strong>Sent back by HR</strong><br>
    Reason: <?php echo htmlspecialchars($clrInstance['hr_rejection_reason']); ?><br>
    Please review, update if needed, and re-sign below.
  </div>
  <?php endif; ?>

  <?php foreach ($clrGrouped as $cg_name => $cg_data): ?>
  <div style="font-weight:800;color:var(--navy);font-size:14px;margin:20px 0 10px;padding-bottom:6px;border-bottom:2px solid #eef2ff;"><?php echo htmlspecialchars($cg_name); ?></div>
  <div style="overflow-x:auto;">
    <table style="width:100%; border-collapse:collapse; font-size:12.5px; margin-bottom:10px; table-layout:fixed;">
      <thead><tr><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:8%; vertical-align:middle; text-align:left;">Sl. No.</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; vertical-align:middle; text-align:left;">Clearance Item</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%; vertical-align:middle; text-align:center;">Yes</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%; vertical-align:middle; text-align:center;">No</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:12%; vertical-align:middle; text-align:center;">N/A</th><th style="border:1px solid #cbd5e1; padding:8px 10px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:24%; vertical-align:middle; text-align:left;">Remarks</th></tr></thead>
      <tbody>
      <?php foreach ($cg_data['items'] as $cidx => $it2): ?>
      <tr style="background:<?php echo $cidx%2==1?'#f8faff':'#fff'; ?>;">
        <td style="border:1px solid #cbd5e1; padding:8px 10px; vertical-align:middle; text-align:left;"><?php echo $cidx+1; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word; vertical-align:middle; text-align:left;"><?php echo htmlspecialchars($it2['item_text']); ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669; vertical-align:middle;"><?php echo $it2['response']==='yes' ? '&#10003;' : ''; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669; vertical-align:middle;"><?php echo $it2['response']==='no' ? '&#10003;' : ''; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; text-align:center; font-weight:bold; color:#059669; vertical-align:middle;"><?php echo $it2['response']==='na' ? '&#10003;' : ''; ?></td>
        <td style="border:1px solid #cbd5e1; padding:8px 10px; word-wrap:break-word; vertical-align:middle; text-align:left;"><?php echo htmlspecialchars($it2['remarks'] ?? ''); ?></td>
      </tr>
      <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endforeach; ?>

  <?php if (empty($clrGrouped)): ?>
  <p style="color:#94a3b8;font-size:13px;">No checklist items yet.</p>
  <?php endif; ?>

  <?php if (!empty($clrDeclaration)): ?>
  <div style="font-size:12px;line-height:1.7;color:#1a202c;margin:16px 0;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px 14px;"><?php echo nl2br(htmlspecialchars($clrDeclaration)); ?></div>
  <?php endif; ?>

  <?php if ($clrInstance['status'] === 'completed'): ?>
  <div class="alert alert-success mt-2" style="font-size:12.5px;"><i class="fas fa-check-circle mr-1"></i> Fully approved. Thank you.</div>
  <?php elseif ($clrInstance['status'] === 'pending_hr_approval'): ?>
  <div class="alert alert-success mt-2" style="font-size:12.5px;"><i class="fas fa-check-circle mr-1"></i> You have signed this document. Awaiting final HR approval.</div>
  <?php elseif (empty($clrInstance['position_head_signature_data'])): ?>
  <div class="alert alert-warning mt-2" style="font-size:12.5px;"><i class="fas fa-hourglass-half mr-1"></i> Awaiting Position Head signature. You can sign this document once they have completed their review.</div>
  <?php elseif (!$clr_readonly2): ?>
  <div style="font-weight:800;color:var(--navy);font-size:13px;margin-top:14px;margin-bottom:8px;">Your Signature</div>
  <div style="margin-bottom:12px;">
    <label class="fl">Your Remarks (Optional)</label>
    <textarea id="clrEmpRemarks2" class="fc" style="height:70px;max-width:500px;" placeholder="Add any comments regarding the clearance..."></textarea>
  </div>
  <div class="sig-pad-box">
    <canvas id="clrEmpSigCanvas2" width="460" height="140" class="emp-sig-canvas"></canvas>
    <div style="margin-top:8px;display:flex;gap:8px;">
      <button type="button" class="btn-p" style="background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;" onclick="empClearClrSig()">Clear</button>
      <button type="button" class="btn-p btn-navy" onclick="empSaveClearanceSignature(<?php echo $clrInstance['id']; ?>)">Submit for Final Approval</button>
    </div>
  </div>
  <?php endif; ?>
  <?php endif; ?>
</div>
<?php endif; ?>
</div>

<div id="phaseTab-4" class="phase-tab-panel" style="display:<?php echo $defaultPhase==4?'block':'none'; ?>;">
<!-- PHASE 4: Interview & Settlement -->
<div class="phase-bar phase-4"><span><i class="fas fa-comments-dollar mr-2"></i>4. Exit Interview & Settlement</span><span><?php echo $settlement && $settlement['status']=='approved' ? 'Approved' : 'Pending'; ?></span></div>
<?php if ($currentStageIdx <= 4): ?>
<div class="phase-body locked"><i class="fas fa-lock mb-2"></i><br>Locked until the Department-Position Clearance is approved by HR.</div>
<?php else: ?>
<div class="phase-body">
  <div class="fg" style="margin-bottom: 20px;"><label class="fl" style="font-weight:800;color:var(--navy);font-size:14px;">Exit Interview Status</label>
    <?php 
    $interviewCompletedDate = null;
    if ((isset($exitRow['current_exit_round']) && intval($exitRow['current_exit_round']) == 99) || in_array($exitRow['status'], ['documents', 'closed'])) {
        $ansQ = mysqli_query($con, "SELECT MAX(submitted_at) as cdate FROM hr_exit_interview_answers WHERE exit_id=" . intval($exitRow['id']));
        if ($ansQ && $ar = mysqli_fetch_assoc($ansQ)) {
            if (!empty($ar['cdate'])) $interviewCompletedDate = $ar['cdate'];
        }
        if (!$interviewCompletedDate && $settlement) $interviewCompletedDate = $settlement['created_at'] ?? null;
    }
    ?>
    <?php if ($interviewCompletedDate || (isset($exitRow['current_exit_round']) && intval($exitRow['current_exit_round']) == 99)): ?>
    <span class="badge" style="background:#d1fae5;color:#065f46;font-size:12px;padding:6px 12px;"><i class="fas fa-check-circle mr-1"></i> Completed <?php echo $interviewCompletedDate ? 'on ' . date('d M Y', strtotime($interviewCompletedDate)) : ''; ?></span>
    <?php else: ?>
    <span class="badge" style="background:#fee2e2;color:#991b1b;font-size:12px;padding:6px 12px;"><i class="fas fa-hourglass-half mr-1"></i> Not yet completed</span>
    <?php endif; ?>
  </div>

  <div style="font-weight:800;color:var(--navy);font-size:14px;margin:20px 0 10px;padding-bottom:6px;border-bottom:2px solid #eef2ff;">Full & Final Settlement</div>
  <?php if ($settlement): ?>
  <div style="background:#fff; border-radius:12px; box-shadow:0 8px 24px rgba(15,37,87,.04); border:1px solid #e2e8f0; overflow:hidden; margin-bottom:20px;">
    <table style="width:100%; border-collapse:collapse; font-size:14px; table-layout:fixed;">
      <thead>
        <tr style="background:linear-gradient(135deg, #f8fafc, #f1f5f9);">
          <th style="padding:14px 20px; color:#64748b; text-transform:uppercase; font-size:11px; font-weight:800; letter-spacing:0.8px; width:65%; border-bottom:2px solid #e2e8f0;">Particulars</th>
          <th style="padding:14px 20px; color:#64748b; text-transform:uppercase; font-size:11px; font-weight:800; letter-spacing:0.8px; text-align:right; border-bottom:2px solid #e2e8f0;">Amount (₹)</th>
        </tr>
      </thead>
      <tbody>
        <?php $alt = 0; ?>
        <?php if ((float)$settlement['pending_salary'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-wallet mr-2 text-muted" style="opacity:0.6;"></i>Pending Salary</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['pending_salary'],2); ?></td>
        </tr>
        <?php endif; ?>
        <?php if ((float)$settlement['leave_encashment'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-umbrella-beach mr-2 text-muted" style="opacity:0.6;"></i>Leave Encashment</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['leave_encashment'],2); ?></td>
        </tr>
        <?php endif; ?>
        <?php if ((float)$settlement['bonus_incentive'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-award mr-2 text-muted" style="opacity:0.6;"></i>Bonus / Incentive</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['bonus_incentive'],2); ?></td>
        </tr>
        <?php endif; ?>
        <?php if (isset($settlement['gratuity_amount']) && (float)$settlement['gratuity_amount'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-hand-holding-usd mr-2 text-muted" style="opacity:0.6;"></i>Gratuity</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['gratuity_amount'],2); ?></td>
        </tr>
        <?php endif; ?>
        <?php if (isset($settlement['pension_amount']) && (float)$settlement['pension_amount'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-piggy-bank mr-2 text-muted" style="opacity:0.6;"></i>Pension Settlement</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['pension_amount'],2); ?></td>
        </tr>
        <?php endif; ?>
        <?php if (isset($settlement['severance_pay']) && (float)$settlement['severance_pay'] > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#f8fafc' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-handshake mr-2 text-muted" style="opacity:0.6;"></i>Severance / Notice Pay in Lieu</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ <?php echo number_format($settlement['severance_pay'],2); ?></td>
        </tr>
        <?php endif; ?>
        
        <?php 
        // Render custom EARNINGS
        $total_custom_earning = 0;
        if (!empty($settlementItems)) {
            foreach ($settlementItems as $si) {
                if ($si['item_type'] === 'earning') {
                    $total_custom_earning += (float)$si['amount'];
                    if ((float)$si['amount'] > 0) {
                        echo '<tr style="background:'.($alt++ % 2 == 0 ? '#f8fafc' : '#fff').';">';
                        echo '<td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#334155; font-weight:600;"><i class="fas fa-plus-circle mr-2 text-muted" style="opacity:0.6;"></i>'.htmlspecialchars($si['label']).'</td>';
                        echo '<td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; font-weight:800; color:var(--navy);">₹ '.number_format((float)$si['amount'],2).'</td>';
                        echo '</tr>';
                    }
                }
            }
        }
        ?>

        <?php $stdDeds = (float)$settlement['loan_recovery']+(float)$settlement['notice_shortfall_deduction']+(float)$settlement['other_deductions']; ?>
        <?php if ($stdDeds > 0): ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#fef2f2' : '#fff'; ?>;">
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#991b1b; font-weight:700;"><i class="fas fa-minus-circle mr-2" style="opacity:0.7;"></i>Standard Deductions (Loan / Notice / Other)</td>
          <td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; color:#991b1b; font-weight:700;">– ₹ <?php echo number_format($stdDeds,2); ?></td>
        </tr>
        <?php endif; ?>

        <?php 
        // Render custom DEDUCTIONS
        if (!empty($settlementItems)) {
            foreach ($settlementItems as $si) {
                if ($si['item_type'] === 'deduction' && (float)$si['amount'] > 0) {
                    echo '<tr style="background:'.($alt++ % 2 == 0 ? '#fef2f2' : '#fff').';">';
                    echo '<td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; color:#991b1b; font-weight:700;"><i class="fas fa-minus-circle mr-2" style="opacity:0.7;"></i>'.htmlspecialchars($si['label']).'</td>';
                    echo '<td style="border-bottom:1px solid #f1f5f9; padding:14px 20px; text-align:right; color:#991b1b; font-weight:700;">– ₹ '.number_format((float)$si['amount'],2).'</td>';
                    echo '</tr>';
                }
            }
        }
        ?>
      </tbody>
      <tfoot>
        <tr style="background:linear-gradient(135deg,var(--navy),var(--blue)); color:#fff;">
          <td style="padding:16px 20px; font-weight:800; font-size:14px; text-transform:uppercase; letter-spacing:0.5px;">Net Payable <?php echo $settlement['status']=='approved' ? '' : '<span style="font-size:10px; opacity:0.8; margin-left:6px; background:rgba(255,255,255,0.2); padding:2px 6px; border-radius:4px;">PROVISIONAL</span>'; ?></td>
          <td style="padding:16px 20px; text-align:right; font-weight:800; font-size:18px;">₹ <?php echo number_format($settlement['net_amount'],2); ?></td>
        </tr>
      </tfoot>
    </table>
  </div>
  <?php else: ?>
  <div class="alert alert-warning" style="font-size:13px;"><i class="fas fa-info-circle mr-1"></i> Settlement not yet calculated or released by HR.</div>
  <?php endif; ?>
</div>
<?php endif; ?>
</div>

<div id="phaseTab-5" class="phase-tab-panel" style="display:<?php echo $defaultPhase==5?'block':'none'; ?>;">
<!-- PHASE 5: Documents & Closure -->
<div class="phase-bar phase-5"><span><i class="fas fa-file-signature mr-2"></i>5. Documents & Closure</span><span><?php echo $exitRow['status']=='closed' ? 'Closed' : 'In Progress'; ?></span></div>
<?php if ($currentStageIdx < 6): ?>
<div class="phase-body locked"><i class="fas fa-lock mb-2"></i><br>Locked until your Full & Final Settlement is approved.</div>
<?php else: ?>
<div class="phase-body">
  <div style="font-weight:800;color:var(--navy);font-size:14px;margin-bottom:15px;padding-bottom:6px;border-bottom:2px solid #eef2ff;">Exit Certificates & Documents</div>
  
  <div style="overflow-x:auto;">
    <table style="width:100%; border-collapse:collapse; font-size:13px; margin-bottom:10px; table-layout:fixed;">
      <thead>
        <tr>
          <th style="border:1px solid #cbd5e1; padding:10px 14px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; width:65%;">Document</th>
          <th style="border:1px solid #cbd5e1; padding:10px 14px; background:#0f2557; color:#fff; text-transform:uppercase; font-size:11px; text-align:center;">Action</th>
        </tr>
      </thead>
      <tbody>
        <?php $alt = 0; foreach ($docLabels as $type => $label): $d = $documents[$type] ?? null; ?>
        <tr style="background:<?php echo $alt++ % 2 == 0 ? '#fff' : '#f8faff'; ?>;">
          <td style="border:1px solid #cbd5e1; padding:10px 14px; font-weight:600; color:var(--navy);"><i class="far fa-file-alt mr-2" style="color:#64748b;"></i> <?php echo $label; ?></td>
          <td style="border:1px solid #cbd5e1; padding:10px 14px; text-align:center;">
            <?php if (!$d): ?>
            <span class="badge" style="background:#f1f5f9;color:#64748b;font-size:10.5px;padding:5px 12px;border:1px solid #e2e8f0;">Not issued</span>
            <?php elseif ($d['status'] === 'approved'): ?>
            <a href="hr-exit-documents.php?token=<?php echo $d['token']; ?>" target="_blank" class="btn-p btn-green" style="padding:6px 14px;font-size:11.5px;border-radius:6px;box-shadow:0 1px 3px rgba(16,185,129,0.3);"><i class="fas fa-file-download mr-1"></i> View / Download</a>
            <?php elseif ($d['status'] === 'pending_hr_final'): ?>
            <span class="badge" style="background:#ede9fe;color:#5b21b6;font-size:10.5px;padding:5px 12px;">Signed — Awaiting HR</span>
            <?php elseif ($d['status'] === 'pending_signature' && isset($_GET['token'])): ?>
            <div style="text-align:left;">
              <p style="font-size:11.5px;color:#64748b;margin:0 0 8px;"><i class="fas fa-info-circle mr-1"></i> This document requires your signature. Review it, then sign below.</p>
              <a href="hr-exit-documents.php?token=<?php echo $d['token']; ?>" target="_blank" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;margin-bottom:10px;"><i class="fas fa-eye mr-1"></i> Preview Document</a>
              <div class="sig-pad-box">
                <canvas id="docSigCanvas_<?php echo $d['id']; ?>" class="emp-sig-canvas doc-sig-canvas"></canvas>
                <div style="margin-top:8px;display:flex;gap:8px;">
                  <button type="button" class="btn-p" style="background:#fff;border:1.5px solid #a78bfa;color:#6d28d9;" onclick="empClearDocSig(<?php echo $d['id']; ?>)">Clear</button>
                  <button type="button" class="btn-p btn-navy" onclick="empSubmitDocSignature(<?php echo $d['id']; ?>)">Sign & Submit</button>
                </div>
              </div>
            </div>
            <?php elseif ($d['status'] === 'pending_signature'): ?>
            <span class="badge" style="background:#dbeafe;color:#1e40af;font-size:10.5px;padding:5px 12px;">Awaiting your signature</span>
            <?php endif; ?>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>

  <?php if ($exitRow['status'] === 'closed'): ?>
  <div class="alert alert-success mt-4" style="font-size:13px;border-radius:8px;font-weight:600;"><i class="fas fa-check-circle mr-1"></i> Your exit process is complete. Thank you for your time with us — we wish you the very best.</div>
  <?php else: ?>
  <p style="color:#94a3b8;font-size:12px;margin-top:15px;"><i class="fas fa-info-circle mr-1"></i> Your record will be closed and archived by HR once all required documents are issued.</p>
  <?php endif; ?>
</div>
<?php endif; ?>
</div>
<?php endif; ?>

<?php endif; ?>
</div>
<script>
function switchPhaseTab(n) {
    document.querySelectorAll('.phase-tab-panel').forEach(function(p){ p.style.display = 'none'; });
    var target = document.getElementById('phaseTab-' + n);
    if (target) target.style.display = 'block';
}
function empPost(action, params, cb) {
    var data = Object.assign({ ajax_action: action }, params);
    var body = Object.keys(data).map(function(k) { return encodeURIComponent(k) + '=' + encodeURIComponent(data[k]); }).join('&');
    fetch(window.location.href, { method: 'POST', headers: {'Content-Type':'application/x-www-form-urlencoded'}, body: body })
        .then(function(r){ return r.json(); })
        .then(cb)
        .catch(function(){ alert('Network error. Please try again.'); });
}
function empToggleAssetItem(id, checked) {
    empPost('token_toggle_asset_item', { run_item_id: id, checked: checked ? 1 : 0 }, function(){});
}
function empSaveAssetDetail(id) {
    var condEl = document.getElementById('empCond_' + id);
    var remEl = document.getElementById('empRem_' + id);
    empPost('token_save_asset_detail', { run_item_id: id, condition_text: condEl ? condEl.value : '', remarks: remEl ? remEl.value : '' }, function(){});
}
var empAssetSigCanvas = document.getElementById('empAssetSigCanvas');
var empAssetSigCtx = null;
var empAssetSigDrawing = false;
if (empAssetSigCanvas) {
    empAssetSigCanvas.width = empAssetSigCanvas.offsetWidth;
    empAssetSigCanvas.height = empAssetSigCanvas.offsetHeight;
    empAssetSigCtx = empAssetSigCanvas.getContext('2d');
    empAssetSigCtx.strokeStyle = '#1a3fc4'; empAssetSigCtx.lineWidth = 2; empAssetSigCtx.lineCap = 'round';
    var empSigPos = function(e) {
        var r = empAssetSigCanvas.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    empAssetSigCanvas.addEventListener('mousedown', function(e){ empAssetSigDrawing = true; var p = empSigPos(e); empAssetSigCtx.beginPath(); empAssetSigCtx.moveTo(p.x, p.y); });
    empAssetSigCanvas.addEventListener('mousemove', function(e){ if (!empAssetSigDrawing) return; var p = empSigPos(e); empAssetSigCtx.lineTo(p.x, p.y); empAssetSigCtx.stroke(); });
    empAssetSigCanvas.addEventListener('mouseup', function(){ empAssetSigDrawing = false; });
    empAssetSigCanvas.addEventListener('mouseleave', function(){ empAssetSigDrawing = false; });
    empAssetSigCanvas.addEventListener('touchstart', function(e){ e.preventDefault(); empAssetSigDrawing = true; var p = empSigPos(e); empAssetSigCtx.beginPath(); empAssetSigCtx.moveTo(p.x, p.y); }, {passive:false});
    empAssetSigCanvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!empAssetSigDrawing) return; var p = empSigPos(e); empAssetSigCtx.lineTo(p.x, p.y); empAssetSigCtx.stroke(); }, {passive:false});
    empAssetSigCanvas.addEventListener('touchend', function(e){ e.preventDefault(); empAssetSigDrawing = false; }, {passive:false});
}
function empClearAssetSig() {
    if (!empAssetSigCanvas || !empAssetSigCtx) return;
    empAssetSigCtx.clearRect(0, 0, empAssetSigCanvas.width, empAssetSigCanvas.height);
}
function empFinalizeAssetSignature(instanceId) {
    if (!empAssetSigCanvas) return;
    var blank = document.createElement('canvas');
    blank.width = empAssetSigCanvas.width; blank.height = empAssetSigCanvas.height;
    if (empAssetSigCanvas.toDataURL() === blank.toDataURL()) { alert('Please draw your signature first.'); return; }
    
    showCustomConfirm('Submit your Asset Handover checklist for HR approval? You will not be able to edit it until HR reviews it.', function() {
        var dataUrl = empAssetSigCanvas.toDataURL('image/png');
        empPost('token_save_asset_signature', { instance_id: instanceId, signature_data: dataUrl }, function(resp) {
            if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to submit signature.'); }
        });
    });
}

/* ===== Department-Position Clearance ===== */

function empSetClearanceResponse(id, response) {
    empPost('token_set_clearance_response', { run_item_id: id, response: response }, function(){});
}
function empSaveClearanceRemarks(id, remarks) {
    empPost('token_save_clearance_remarks', { run_item_id: id, remarks: remarks }, function(){});
}

var clrEmpSigCanvas2 = document.getElementById('clrEmpSigCanvas2');
var clrEmpSigCtx2 = null;
var clrEmpSigDrawing2 = false;
if (clrEmpSigCanvas2) {
    clrEmpSigCanvas2.width = clrEmpSigCanvas2.offsetWidth;
    clrEmpSigCanvas2.height = clrEmpSigCanvas2.offsetHeight;
    clrEmpSigCtx2 = clrEmpSigCanvas2.getContext('2d');
    clrEmpSigCtx2.strokeStyle = '#1a3fc4'; clrEmpSigCtx2.lineWidth = 2; clrEmpSigCtx2.lineCap = 'round';
    var clrEmpSigPos2 = function(e) {
        var r = clrEmpSigCanvas2.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    clrEmpSigCanvas2.addEventListener('mousedown', function(e){ clrEmpSigDrawing2 = true; var p = clrEmpSigPos2(e); clrEmpSigCtx2.beginPath(); clrEmpSigCtx2.moveTo(p.x, p.y); });
    clrEmpSigCanvas2.addEventListener('mousemove', function(e){ if (!clrEmpSigDrawing2) return; var p = clrEmpSigPos2(e); clrEmpSigCtx2.lineTo(p.x, p.y); clrEmpSigCtx2.stroke(); });
    clrEmpSigCanvas2.addEventListener('mouseup', function(){ clrEmpSigDrawing2 = false; });
    clrEmpSigCanvas2.addEventListener('mouseleave', function(){ clrEmpSigDrawing2 = false; });
    clrEmpSigCanvas2.addEventListener('touchstart', function(e){ e.preventDefault(); clrEmpSigDrawing2 = true; var p = clrEmpSigPos2(e); clrEmpSigCtx2.beginPath(); clrEmpSigCtx2.moveTo(p.x, p.y); }, {passive:false});
    clrEmpSigCanvas2.addEventListener('touchmove', function(e){ e.preventDefault(); if (!clrEmpSigDrawing2) return; var p = clrEmpSigPos2(e); clrEmpSigCtx2.lineTo(p.x, p.y); clrEmpSigCtx2.stroke(); }, {passive:false});
    clrEmpSigCanvas2.addEventListener('touchend', function(e){ e.preventDefault(); clrEmpSigDrawing2 = false; }, {passive:false});
}
function empClearClrSig() {
    if (!clrEmpSigCanvas2 || !clrEmpSigCtx2) return;
    clrEmpSigCtx2.clearRect(0, 0, clrEmpSigCanvas2.width, clrEmpSigCanvas2.height);
}
function empSaveClearanceSignature(instanceId) {
    if (!clrEmpSigCanvas2) return;
    var blank2 = document.createElement('canvas');
    blank2.width = clrEmpSigCanvas2.width; blank2.height = clrEmpSigCanvas2.height;
    if (clrEmpSigCanvas2.toDataURL() === blank2.toDataURL()) { alert('Please draw your signature first.'); return; }
    
    showCustomConfirm('Submit your Department-Position Clearance for review? You will not be able to edit it until reviewed.', function() {
        var dataUrl2 = clrEmpSigCanvas2.toDataURL('image/png');
        var empRem = document.getElementById('clrEmpRemarks2') ? document.getElementById('clrEmpRemarks2').value : '';
        empPost('token_save_clearance_signature', { instance_id: instanceId, signature_data: dataUrl2, employee_remarks: empRem }, function(resp) {
            if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to submit signature.'); }
        });
    });
}

/* ===== Exit Documents requiring signature (Phase 5) — one canvas per document ===== */
function initDocSigCanvas(canvas) {
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    var ctx = canvas.getContext('2d');
    ctx.strokeStyle = '#1a3fc4'; ctx.lineWidth = 2; ctx.lineCap = 'round';
    var drawing = false;
    var pos = function(e) {
        var r = canvas.getBoundingClientRect();
        if (e.touches) return { x: e.touches[0].clientX - r.left, y: e.touches[0].clientY - r.top };
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    canvas.addEventListener('mousedown', function(e){ drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); });
    canvas.addEventListener('mousemove', function(e){ if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); });
    canvas.addEventListener('mouseup', function(){ drawing = false; });
    canvas.addEventListener('mouseleave', function(){ drawing = false; });
    canvas.addEventListener('touchstart', function(e){ e.preventDefault(); drawing = true; var p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); }, {passive:false});
    canvas.addEventListener('touchmove', function(e){ e.preventDefault(); if (!drawing) return; var p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); }, {passive:false});
    canvas.addEventListener('touchend', function(e){ e.preventDefault(); drawing = false; }, {passive:false});
}
document.querySelectorAll('.doc-sig-canvas').forEach(initDocSigCanvas);

function empClearDocSig(docId) {
    var c = document.getElementById('docSigCanvas_' + docId);
    if (!c) return;
    c.getContext('2d').clearRect(0, 0, c.width, c.height);
}
function empSubmitDocSignature(docId) {
    var c = document.getElementById('docSigCanvas_' + docId);
    if (!c) return;
    var blank3 = document.createElement('canvas');
    blank3.width = c.width; blank3.height = c.height;
    if (c.toDataURL() === blank3.toDataURL()) { alert('Please draw your signature first.'); return; }

    showCustomConfirm('Submit your signature for this document? It will be sent to HR for final acceptance.', function() {
        var dataUrl3 = c.toDataURL('image/png');
        empPost('token_save_document_signature', { doc_id: docId, signature_data: dataUrl3 }, function(resp) {
            if (resp.success) { location.reload(); } else { alert(resp.message || 'Failed to submit signature.'); }
        });
    });
}
</script>

<!-- Custom Confirm Overlay -->
<div id="customConfirmOverlay" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(15,37,87,0.7);z-index:9999;align-items:center;justify-content:center;">
    <div style="background:#fff;border-radius:14px;padding:30px;max-width:400px;width:90%;box-shadow:0 10px 25px rgba(0,0,0,0.2);text-align:center;">
        <i class="fas fa-question-circle" style="font-size:40px;color:var(--blue);margin-bottom:15px;"></i>
        <h5 style="font-weight:800;color:var(--navy);margin-bottom:10px;">Please Confirm</h5>
        <p id="customConfirmText" style="color:#64748b;font-size:13.5px;margin-bottom:20px;"></p>
        <div style="display:flex;gap:10px;justify-content:center;">
            <button type="button" class="btn-p" style="background:#f1f5f9;color:#475569;border:1px solid #cbd5e1;flex:1;" onclick="closeCustomConfirm()">Cancel</button>
            <button type="button" class="btn-p btn-navy" style="flex:1;" id="customConfirmBtn">Confirm</button>
        </div>
    </div>
</div>

<script>
var _customConfirmCallback = null;
function showCustomConfirm(msg, callback) {
    document.getElementById('customConfirmText').innerText = msg;
    _customConfirmCallback = callback;
    document.getElementById('customConfirmOverlay').style.display = 'flex';
}
function closeCustomConfirm() {
    document.getElementById('customConfirmOverlay').style.display = 'none';
    _customConfirmCallback = null;
}
document.getElementById('customConfirmBtn').addEventListener('click', function() {
    var cb = _customConfirmCallback;
    closeCustomConfirm();
    if (typeof cb === 'function') {
        cb();
    }
});
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
