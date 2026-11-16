<?php
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
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

// ============================================================
// TABLE SETUP
// ============================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_dv_settings (
    id INT(11) NOT NULL AUTO_INCREMENT,
    category VARCHAR(20) NOT NULL COMMENT 'fresher or experienced',
    document_name VARCHAR(255) NOT NULL,
    is_required TINYINT(1) DEFAULT 1,
    sort_order INT(11) DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_dv_requests (
    id INT(11) NOT NULL AUTO_INCREMENT,
    dv_number VARCHAR(20) NOT NULL,
    candidate_id INT(11) NOT NULL,
    candidate_name VARCHAR(255) NOT NULL,
    candidate_email VARCHAR(255) DEFAULT NULL,
    candidate_phone VARCHAR(50) DEFAULT NULL,
    category VARCHAR(20) NOT NULL COMMENT 'fresher or experienced',
    token VARCHAR(64) NOT NULL,
    expiry_at DATETIME DEFAULT NULL,
    status VARCHAR(30) DEFAULT 'pending' COMMENT 'pending/submitted/verified',
    sent_at DATETIME DEFAULT NULL,
    verified_at DATETIME DEFAULT NULL,
    verified_by VARCHAR(255) DEFAULT NULL,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY unique_dv_number (dv_number),
    UNIQUE KEY unique_token (token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_dv_documents (
    id INT(11) NOT NULL AUTO_INCREMENT,
    request_id INT(11) NOT NULL,
    setting_id INT(11) NOT NULL,
    document_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) DEFAULT NULL,
    file_name VARCHAR(255) DEFAULT NULL,
    file_size VARCHAR(50) DEFAULT NULL,
    uploaded_at DATETIME DEFAULT NULL,
    is_verified TINYINT(1) DEFAULT 0,
    verified_at DATETIME DEFAULT NULL,
    verified_by VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "ALTER TABLE hr_dv_requests ADD COLUMN IF NOT EXISTS candidate_signature LONGTEXT DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_requests ADD COLUMN IF NOT EXISTS tnc_accepted_at DATETIME DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_requests ADD COLUMN IF NOT EXISTS tnc_hr_accepted TINYINT(1) DEFAULT 0");
mysqli_query($con, "ALTER TABLE hr_dv_requests ADD COLUMN IF NOT EXISTS tnc_hr_accepted_by VARCHAR(255) DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_requests ADD COLUMN IF NOT EXISTS tnc_hr_accepted_at DATETIME DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_documents ADD COLUMN IF NOT EXISTS is_rejected TINYINT(1) DEFAULT 0");
mysqli_query($con, "ALTER TABLE hr_dv_documents ADD COLUMN IF NOT EXISTS rejection_category VARCHAR(50) DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_documents ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_documents ADD COLUMN IF NOT EXISTS rejected_by VARCHAR(255) DEFAULT NULL");
mysqli_query($con, "ALTER TABLE hr_dv_documents ADD COLUMN IF NOT EXISTS rejected_at DATETIME DEFAULT NULL");

// ============================================================
// HELPERS
// ============================================================
function generateDVNumber($con) {
    $last = mysqli_fetch_assoc(mysqli_query($con, "SELECT dv_number FROM hr_dv_requests ORDER BY id DESC LIMIT 1"));
    if ($last) {
        preg_match('/DV(\d+)/', $last['dv_number'], $m);
        $next = isset($m[1]) ? intval($m[1]) + 1 : 1;
    } else {
        $next = 1;
    }
    return 'DV' . str_pad($next, 4, '0', STR_PAD_LEFT);
}

function getDVRequest($con, $candidate_id) {
    return mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_dv_requests WHERE candidate_id=" . intval($candidate_id) . " ORDER BY id DESC LIMIT 1"));
}

function getDVSettings($con, $category) {
    $cat = mysqli_real_escape_string($con, $category);
    $res = mysqli_query($con, "SELECT * FROM hr_dv_settings WHERE category='$cat' ORDER BY sort_order ASC, id ASC");
    $rows = [];
    while ($r = mysqli_fetch_assoc($res)) $rows[] = $r;
    return $rows;
}

function getDVDocuments($con, $request_id) {
    $res = mysqli_query($con, "SELECT * FROM hr_dv_documents WHERE request_id=" . intval($request_id) . " ORDER BY id ASC");
    $rows = [];
    while ($r = mysqli_fetch_assoc($res)) $rows[] = $r;
    return $rows;
}

// Human-readable label for a DV category — resolves "position_123" to that position's
// title instead of showing the raw internal key.
function dvCategoryLabel($con, $category) {
    if (preg_match('/^position_(\d+)$/', $category, $m)) {
        $p = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=" . intval($m[1]) . " LIMIT 1"));
        return $p ? htmlspecialchars($p['title']) . ' (Position-Specific)' : 'Position-Specific';
    }
    return ucfirst($category);
}

$current_user_name = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : 'HR';
$upload_dir = 'uploads/hr_dv/';
if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);

$base_url   = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
$script_dir = '/hrm';

// ============================================================
// CANDIDATE PORTAL (via token)
// ============================================================
if (isset($_GET['token'])) {
    $token = mysqli_real_escape_string($con, $_GET['token']);
    $req   = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_dv_requests WHERE token='$token' LIMIT 1"));
    if (!$req) die("<div style='padding:60px;text-align:center;font-family:sans-serif;'><h3>Invalid or expired link.</h3></div>");

    if ($req['expiry_at'] && strtotime($req['expiry_at']) < time()) {
        die("<div style='padding:60px;text-align:center;font-family:sans-serif;'><h3>This link has expired.</h3><p>Please contact HR.</p></div>");
    }

    $dv_has_rejected_doc = false;
    if ($req['status'] === 'submitted' || $req['status'] === 'verified') {
        $dv_rej_check = mysqli_query($con, "SELECT id FROM hr_dv_documents WHERE request_id=" . $req['id'] . " AND is_rejected=1 LIMIT 1");
        $dv_has_rejected_doc = $dv_rej_check && mysqli_num_rows($dv_rej_check) > 0;

        if (!$dv_has_rejected_doc) {
            echo "<div style='padding:60px;text-align:center;font-family:sans-serif;'><h2>✅ Documents Already Submitted</h2><p>HR will review and verify your documents shortly.</p></div>";
            if (ob_get_level() > 0) { ob_end_flush(); } exit;
        }
    }

    $settings = getDVSettings($con, $req['category']);
    $existing_docs = getDVDocuments($con, $req['id']);
    $existing_map  = [];
    foreach ($existing_docs as $ed) $existing_map[$ed['setting_id']] = $ed;

    // Handle document upload POST
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submit_docs'])) {
        $all_uploaded = true;
        foreach ($settings as $s) {
            $sid = $s['id'];
            if (isset($_FILES['doc_' . $sid]) && $_FILES['doc_' . $sid]['error'] === UPLOAD_ERR_OK) {
                $file   = $_FILES['doc_' . $sid];
                $ext    = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
                $allowed = ['pdf','jpg','jpeg','png','doc','docx'];
                if (!in_array($ext, $allowed)) continue;
                $fname  = 'dv_' . $req['id'] . '_' . $sid . '_' . time() . '.' . $ext;
                $fpath  = $upload_dir . $fname;
                $fsize  = round($file['size'] / 1024) . ' KB';
                if (move_uploaded_file($file['tmp_name'], $fpath)) {
                    $fname_e  = mysqli_real_escape_string($con, $file['name']);
                    $fpath_e  = mysqli_real_escape_string($con, $fpath);
                    $fsize_e  = mysqli_real_escape_string($con, $fsize);
                    $dname_e  = mysqli_real_escape_string($con, $s['document_name']);
                    $now      = date('Y-m-d H:i:s');
                    if (isset($existing_map[$sid])) {
                        mysqli_query($con, "UPDATE hr_dv_documents SET file_path='$fpath_e', file_name='$fname_e', file_size='$fsize_e', uploaded_at='$now', is_verified=0, is_rejected=0, rejection_category=NULL, rejection_reason=NULL, rejected_by=NULL, rejected_at=NULL WHERE id=" . $existing_map[$sid]['id']);
                    } else {
                        mysqli_query($con, "INSERT INTO hr_dv_documents (request_id, setting_id, document_name, file_path, file_name, file_size, uploaded_at) VALUES (" . $req['id'] . ", $sid, '$dname_e', '$fpath_e', '$fname_e', '$fsize_e', '$now')");
                    }
                }
            } elseif ($s['is_required'] && !isset($existing_map[$sid])) {
                $all_uploaded = false;
            }
        }
        // Check all required docs uploaded
        $uploaded_ids = [];
        $docs_check = mysqli_query($con, "SELECT setting_id FROM hr_dv_documents WHERE request_id=" . $req['id']);
        while ($dc = mysqli_fetch_assoc($docs_check)) $uploaded_ids[] = $dc['setting_id'];
        $missing_required = false;
        foreach ($settings as $s) {
            if ($s['is_required'] && !in_array($s['id'], $uploaded_ids)) { $missing_required = true; break; }
        }
        // Block submission while any document HR rejected is still awaiting a replacement upload
        $still_rejected_check = mysqli_query($con, "SELECT id FROM hr_dv_documents WHERE request_id=" . $req['id'] . " AND is_rejected=1 LIMIT 1");
        $still_has_rejected = $still_rejected_check && mysqli_num_rows($still_rejected_check) > 0;
        if (!$missing_required && !$still_has_rejected) {
            // Save signature & TNC acceptance
            if (!empty($_POST['candidate_signature'])) {
                $sig_data = mysqli_real_escape_string($con, $_POST['candidate_signature']);
                $tnc_time = date('Y-m-d H:i:s');
                mysqli_query($con, "UPDATE hr_dv_requests SET candidate_signature='$sig_data', tnc_accepted_at='$tnc_time' WHERE id=" . $req['id']);
            }
            mysqli_query($con, "UPDATE hr_dv_requests SET status='submitted', updated_at=NOW() WHERE id=" . $req['id']);

            // ── Auto-raise a ticket to notify the HR person who added this candidate ──
            $screener_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT screened_by, candidate_name, position_applied, department FROM hr_screenings WHERE id=" . intval($req['candidate_id']) . " LIMIT 1"));
            $screened_by  = intval($screener_row['screened_by'] ?? 0);

            if ($screened_by > 0) {
                $t_subject = "Documents Submitted — " . $req['candidate_name'] . " (Ref: " . $req['dv_number'] . ")";
                $t_message = "Candidate " . $req['candidate_name'] . " has submitted their documents for verification.\n\n" .
                             "Position: " . ($screener_row['position_applied'] ?? '-') . "\n" .
                             "Department: " . ($screener_row['department'] ?? '-') . "\n" .
                             "Category: " . dvCategoryLabel($con, $req['category']) . "\n\n" .
                             "Please review and verify the documents in HR Screening.";
                $t_name     = mysqli_real_escape_string($con, $req['candidate_name']);
                $t_subject  = mysqli_real_escape_string($con, $t_subject);
                $t_message  = mysqli_real_escape_string($con, $t_message);
                $t_priority = 'medium';
                $t_timeline = 1440; // 24 hours
                $t_deadline = date('Y-m-d H:i:s', strtotime('+1440 minutes'));

                $tk_row  = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(id) AS max_id FROM tickets"));
                $tk_next = ($tk_row['max_id'] ?? 0) + 1;
                $ticket_number = 'TICKET' . date('Y') . str_pad($tk_next, 4, '0', STR_PAD_LEFT);

                mysqli_query($con, "INSERT INTO tickets
                    (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
                    VALUES
                    ('$ticket_number', '$t_name', '$t_subject', '$t_message', 'open', '$t_priority', $t_timeline, '$t_deadline', '', NOW(), NOW(), $screened_by, $screened_by)");
            }
            // ── End auto-ticket ──
        }
        header('Location: ' . $_SERVER['REQUEST_URI']);
        exit;
    }

    // Refresh existing docs after any upload
    $existing_docs = getDVDocuments($con, $req['id']);
    $existing_map  = [];
    foreach ($existing_docs as $ed) $existing_map[$ed['setting_id']] = $ed;
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>Document Verification — <?php echo htmlspecialchars($req['candidate_name']); ?></title>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
    <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Plus Jakarta Sans',sans-serif;background:#f0f4f8;padding:20px;}
    .card{max-width:720px;margin:0 auto;background:#fff;border-radius:16px;box-shadow:0 4px 30px rgba(0,0,0,0.1);overflow:hidden;}
    .card-hdr{background:linear-gradient(135deg,#0f2557,#1a3fc4);padding:28px 36px;}
    .card-hdr h1{color:#fff;font-size:1.3rem;font-weight:800;}
    .card-hdr p{color:rgba(255,255,255,.7);font-size:13px;margin-top:4px;}
    .card-body{padding:32px 36px;}
    .doc-row{background:#f8faff;border:1px solid #e0e7ff;border-radius:12px;padding:18px 20px;margin-bottom:14px;}
    .doc-name{font-weight:800;color:#0f2557;font-size:14px;margin-bottom:4px;}
    .doc-req{font-size:11px;font-weight:700;color:#ef4444;margin-bottom:10px;}
    .doc-opt{font-size:11px;font-weight:700;color:#64748b;margin-bottom:10px;}
    .upload-btn{display:inline-block;padding:9px 20px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;}
    .uploaded-ok{background:#dcfce7;border:1px solid #86efac;border-radius:8px;padding:10px 14px;font-size:12px;font-weight:700;color:#065f46;display:flex;align-items:center;gap:8px;margin-top:8px;}
    .btn-sub{width:100%;padding:14px;border:none;border-radius:11px;font-family:inherit;font-weight:800;font-size:14px;cursor:pointer;background:linear-gradient(135deg,#10b981,#059669);color:#fff;margin-top:20px;}
    .tnc-box{background:#f8faff;border:2px solid #e0e7ff;border-radius:12px;padding:16px;text-align:left;max-height:200px;overflow-y:auto;margin-bottom:14px;font-size:12px;color:#475569;line-height:1.8;}
    .tnc-box h4{color:#0f2557;font-weight:800;font-size:13px;margin-bottom:10px;}
    .tnc-box ul{padding-left:16px;}
    .tnc-box ul li{margin-bottom:6px;}
    .sig-canvas{border:2px dashed #e0e7ff;border-radius:12px;background:#f8fafc;cursor:crosshair;width:100%;height:150px;touch-action:none;}
    .tnc-check{display:flex;align-items:flex-start;gap:10px;text-align:left;margin-bottom:16px;font-size:13px;font-weight:700;color:#0f2557;cursor:pointer;}
    .tnc-check input{margin-top:3px;accent-color:#1a3fc4;width:16px;height:16px;cursor:pointer;}
    .validity{background:#fff7ed;border:1px solid #fcd34d;border-radius:10px;padding:12px 16px;font-size:13px;font-weight:700;color:#92400e;margin-bottom:20px;}
    input[type=file]{display:none;}
    
    /* Custom Modal CSS */
    .modal-overlay {
        display: none;
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
        background: rgba(15, 37, 87, 0.5);
        backdrop-filter: blur(4px);
        z-index: 1000;
        align-items: center;
        justify-content: center;
        padding: 20px;
    }
    .modal-card {
        background: #fff;
        border-radius: 16px;
        box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        max-width: 400px;
        width: 100%;
        padding: 32px;
        text-align: center;
        animation: modalPop 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards;
    }
    @keyframes modalPop {
        0% { opacity: 0; transform: scale(0.8); }
        100% { opacity: 1; transform: scale(1); }
    }
    .modal-icon {
        font-size: 48px;
        margin-bottom: 16px;
    }
    .modal-title {
        font-size: 18px;
        font-weight: 800;
        color: #0f2557;
        margin-bottom: 12px;
    }
    .modal-text {
        font-size: 14px;
        color: #64748b;
        margin-bottom: 24px;
        line-height: 1.6;
    }
    .modal-actions {
        display: flex;
        gap: 12px;
    }
    .btn-modal {
        flex: 1;
        padding: 12px;
        border-radius: 10px;
        font-weight: 700;
        font-size: 14px;
        cursor: pointer;
        border: none;
        font-family: inherit;
    }
    .btn-cancel {
        background: #f1f5f9;
        color: #475569;
    }
    .btn-confirm {
        background: linear-gradient(135deg,#10b981,#059669);
        color: #fff;
    }
    </style>
    </head>
    <body>
    <div class="card">
      <div class="card-hdr">
        <h1>📄 Document Verification</h1>
        <p>Ref: <?php echo htmlspecialchars($req['dv_number']); ?> &middot; <?php echo dvCategoryLabel($con, $req['category']); ?></p>
      </div>
      <div class="card-body">
        <?php if ($req['expiry_at']): ?>
        <div class="validity">⏳ Link valid until: <strong><?php echo date('d M Y, h:i A', strtotime($req['expiry_at'])); ?></strong></div>
        <?php endif; ?>

        <div style="background:linear-gradient(135deg, #f0fdf4, #dcfce7);border:1px solid #86efac;border-radius:12px;padding:16px 20px;margin-bottom:24px;display:flex;gap:12px;align-items:flex-start;">
          <div style="font-size:24px;">🎉</div>
          <div>
            <div style="font-weight:800;color:#065f46;font-size:15px;margin-bottom:4px;">Congratulations, <?php echo htmlspecialchars($req['candidate_name']); ?>!</div>
            <div style="font-size:13px;color:#166534;line-height:1.6;">You have successfully cleared your interview rounds. As the next step towards your offer letter, please complete your document verification.</div>
          </div>
        </div>

        <p style="font-size:14px;line-height:1.8;color:#334155;margin-bottom:24px;">
          Please upload the following documents below. Ensure each file is clear and legible.<br>
          <span style="font-size:12px;color:#64748b;font-weight:600;">Accepted formats: PDF, JPG, PNG, DOC, DOCX.</span>
        </p>

        <form method="POST" enctype="multipart/form-data" id="docForm">
          <?php foreach ($settings as $s): ?>
          <?php
            $doc_record = $existing_map[$s['id']] ?? null;
            $uploaded = ($doc_record && !empty($doc_record['file_path'])) ? $doc_record : null;
            $is_rejected_doc = $uploaded && intval($doc_record['is_rejected'] ?? 0) === 1;
          ?>
          <div class="doc-row" <?php if ($is_rejected_doc) echo 'style="border-color:#fca5a5;background:#fff1f2;"'; ?>>
            <div class="doc-name"><?php echo htmlspecialchars($s['document_name']); ?></div>
            <div class="<?php echo $s['is_required'] ? 'doc-req' : 'doc-opt'; ?>">
              <?php echo $s['is_required'] ? '* Required' : 'Optional'; ?>
            </div>
            <?php if ($is_rejected_doc): ?>
            <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:10px 14px;font-size:12px;color:#991b1b;margin-top:8px;">
              <div style="font-weight:800;display:flex;align-items:center;gap:6px;">❌ Rejected — please re-upload</div>
              <div style="margin-top:4px;"><strong>Reason:</strong> <?php echo htmlspecialchars($doc_record['rejection_reason'] ?? ''); ?></div>
              <div style="margin-top:4px;font-size:11px;opacity:.8;">Previously uploaded: <?php echo htmlspecialchars($uploaded['file_name']); ?></div>
            </div>
            <?php elseif ($uploaded): ?>
            <div class="uploaded-ok">
              <span>✅</span>
              <span><?php echo htmlspecialchars($uploaded['file_name']); ?> (<?php echo htmlspecialchars($uploaded['file_size']); ?>)</span>
              <span style="margin-left:auto;font-size:11px;color:#16a34a;">Uploaded — you can replace below</span>
            </div>
            <?php endif; ?>
            <input type="file" name="doc_<?php echo $s['id']; ?>" id="file_<?php echo $s['id']; ?>"
              accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
              onchange="showFileName(this, <?php echo $s['id']; ?>)">
            <div style="margin-top:10px;display:flex;align-items:center;gap:12px;">
              <label for="file_<?php echo $s['id']; ?>" class="upload-btn">
                <span>📎 <?php echo $uploaded ? 'Replace File' : 'Choose File'; ?></span>
              </label>
              <span id="fname_<?php echo $s['id']; ?>" style="font-size:12px;font-weight:600;color:#64748b;"></span>
            </div>
          </div>
          <?php endforeach; ?>

          <input type="hidden" name="submit_docs" value="1">
          <input type="hidden" name="candidate_signature" id="sigDataInput" value="">

          <div style="margin-top:28px;border-top:2px solid #e0e7ff;padding-top:24px;">

            <!-- T&C Box -->
            <div class="tnc-box">
              <h4>📋 Terms & Conditions / Non-Disclosure Agreement</h4>
              <ul>
                <li>I confirm that all documents submitted by me are genuine, authentic, and belong to me. I understand that submission of forged or tampered documents will lead to immediate disqualification and may result in legal action.</li>
                <li>I agree to maintain strict confidentiality of all proprietary information, business processes, trade secrets, and internal data I may access during my employment. I shall not disclose any such information to any third party during or after my employment.</li>
                <li>I consent to the company conducting a thorough background verification check including but not limited to education, previous employment, criminal records, and references.</li>
                <li>I understand that my offer of employment is contingent upon successful verification of all submitted documents and a satisfactory background check.</li>
                <li>I agree to abide by the company's Code of Conduct, HR policies, and all applicable rules and regulations from the date of joining.</li>
                <li>I acknowledge that any misrepresentation of information at any stage of the recruitment process will result in termination of employment without notice, regardless of when such misrepresentation is discovered.</li>
                <li>My digital signature below serves as my binding acceptance of all the above terms and conditions.</li>
              </ul>
            </div>

            <!-- Checkbox -->
            <label class="tnc-check">
              <input type="checkbox" id="tncCheckDV" onchange="checkDVReady()">
              I have read and I agree to the Terms & Conditions and Non-Disclosure Agreement stated above.
            </label>

            <!-- Signature Pad -->
            <div style="font-weight:700;font-size:13px;color:#0f2557;margin-bottom:8px;">✍️ Draw Your Signature Below:</div>
            <canvas id="dvSigCanvas" class="sig-canvas"></canvas>
            <div style="text-align:right;margin-top:6px;margin-bottom:20px;">
              <button type="button" onclick="clearDVCanvas()" style="background:none;border:none;color:#ef4444;font-size:12px;font-weight:700;cursor:pointer;"><i class="fas fa-eraser"></i> Clear Signature</button>
            </div>

          </div>

          <button type="button" id="dvSubmitBtn" class="btn-sub" onclick="showConfirmModal()" disabled style="opacity:0.5;">
            📤 Submit Documents
          </button>
        </form>
      </div>
    </div>

    <!-- Custom Confirm Modal -->
    <div id="confirmModal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-icon">📤</div>
            <div class="modal-title">Submit Documents?</div>
            <div class="modal-text">Are you sure you want to submit all documents? Please ensure all files are correct before submitting.</div>
            <div class="modal-actions">
                <button type="button" class="btn-modal btn-cancel" onclick="closeConfirmModal()">Cancel</button>
                <button type="button" class="btn-modal btn-confirm" onclick="executeSubmit()">Yes, Submit</button>
            </div>
        </div>
    </div>
    <script>
// --- Signature Pad ---
var dvCanvas = document.getElementById('dvSigCanvas');
var dvCtx = dvCanvas.getContext('2d');
var dvDrawing = false;
var dvHasSig = false;

function resizeDVCanvas() {
    var rect = dvCanvas.getBoundingClientRect();
    dvCanvas.width = rect.width;
    dvCanvas.height = rect.height;
}
window.addEventListener('resize', resizeDVCanvas);
resizeDVCanvas();

function getDVPos(e) {
    var rect = dvCanvas.getBoundingClientRect();
    if (e.touches) return { x: e.touches[0].clientX - rect.left, y: e.touches[0].clientY - rect.top };
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
}
dvCanvas.addEventListener('mousedown',  function(e){ dvDrawing=true; var p=getDVPos(e); dvCtx.beginPath(); dvCtx.moveTo(p.x,p.y); });
dvCanvas.addEventListener('mousemove',  function(e){ if(!dvDrawing) return; var p=getDVPos(e); dvCtx.lineTo(p.x,p.y); dvCtx.strokeStyle='#0f2557'; dvCtx.lineWidth=3; dvCtx.lineCap='round'; dvCtx.stroke(); dvHasSig=true; checkDVReady(); });
dvCanvas.addEventListener('mouseup',    function(){ dvDrawing=false; });
dvCanvas.addEventListener('mouseout',   function(){ dvDrawing=false; });
dvCanvas.addEventListener('touchstart', function(e){ e.preventDefault(); dvDrawing=true; var p=getDVPos(e); dvCtx.beginPath(); dvCtx.moveTo(p.x,p.y); }, {passive:false});
dvCanvas.addEventListener('touchmove',  function(e){ e.preventDefault(); if(!dvDrawing) return; var p=getDVPos(e); dvCtx.lineTo(p.x,p.y); dvCtx.strokeStyle='#0f2557'; dvCtx.lineWidth=3; dvCtx.lineCap='round'; dvCtx.stroke(); dvHasSig=true; checkDVReady(); }, {passive:false});
dvCanvas.addEventListener('touchend',   function(e){ e.preventDefault(); dvDrawing=false; }, {passive:false});

function clearDVCanvas() {
    dvCtx.clearRect(0, 0, dvCanvas.width, dvCanvas.height);
    dvHasSig = false;
    checkDVReady();
}

function checkDVReady() {
    var tnc = document.getElementById('tncCheckDV');
    var btn = document.getElementById('dvSubmitBtn');
    if (tnc.checked && dvHasSig) {
        btn.disabled = false;
        btn.style.opacity = '1';
    } else {
        btn.disabled = true;
        btn.style.opacity = '0.5';
    }
}

// --- File name display ---
function showFileName(input, id) {
    var el = document.getElementById('fname_' + id);
    if (input.files && input.files[0]) {
        el.textContent = input.files[0].name;
    }
}

// --- Confirm Modal ---
function showConfirmModal() {
    // Inject signature into hidden input
    document.getElementById('sigDataInput').value = dvCanvas.toDataURL('image/png');
    document.getElementById('confirmModal').style.display = 'flex';
}
function closeConfirmModal() {
    document.getElementById('confirmModal').style.display = 'none';
}
function executeSubmit() {
    document.getElementById('docForm').submit();
}
    </script>
    </body>
    </html>
    <?php
    if (ob_get_level() > 0) { ob_end_flush(); } exit;
}

// ============================================================
// FROM HERE — HR SIDE (requires login)
// ============================================================
isUser();

// ============================================================
// AJAX: SAVE DV SETTINGS (Fresher / Experienced docs list)
// ============================================================
if (isset($_POST['ajax_save_dv_settings'])) {
    header('Content-Type: application/json');
    $category = (in_array($_POST['category'], ['fresher','experienced','blue_collar']) || preg_match('/^position_\d+$/', $_POST['category'] ?? ''))
        ? $_POST['category'] : 'fresher';
    $docs = json_decode($_POST['documents'] ?? '[]', true);
    if (!is_array($docs)) { echo json_encode(['success'=>false,'message'=>'Invalid data']); exit; }

    mysqli_query($con, "DELETE FROM hr_dv_settings WHERE category='$category'");
    foreach ($docs as $idx => $doc) {
        $dname = mysqli_real_escape_string($con, trim($doc['name'] ?? ''));
        $req   = intval($doc['required'] ?? 1);
        if (!$dname) continue;
        mysqli_query($con, "INSERT INTO hr_dv_settings (category, document_name, is_required, sort_order) VALUES ('$category', '$dname', $req, $idx)");
    }
    echo json_encode(['success' => true]);
    exit;
}

// ============================================================
// AJAX: GET DV SETTINGS
// ============================================================
if (isset($_GET['ajax_get_dv_settings'])) {
    header('Content-Type: application/json');
    $fresher    = getDVSettings($con, 'fresher');
    $experienced = getDVSettings($con, 'experienced');
    $blue_collar = getDVSettings($con, 'blue_collar');
    echo json_encode(['success'=>true,'fresher'=>$fresher,'experienced'=>$experienced,'blue_collar'=>$blue_collar]);
    exit;
}

// ============================================================
// AJAX: LIST POSITIONS (for the position-specific document set picker)
// ============================================================
if (isset($_GET['ajax_list_positions_dv'])) {
    header('Content-Type: application/json');
    $rows = [];
    $r = mysqli_query($con, "SELECT p.id, p.title, d.name as dept_name FROM hr_positions p JOIN hr_departments d ON d.id=p.department_id ORDER BY d.name ASC, p.title ASC");
    if ($r) while ($row = mysqli_fetch_assoc($r)) $rows[] = $row;
    echo json_encode(['success'=>true,'positions'=>$rows]);
    exit;
}

// ============================================================
// AJAX: GET POSITION-SPECIFIC DOCUMENT SET
// ============================================================
if (isset($_GET['ajax_get_position_dv_docs'])) {
    header('Content-Type: application/json');
    $pos_id = intval($_GET['position_id'] ?? 0);
    if ($pos_id <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid position']); exit; }
    $docs = getDVSettings($con, 'position_' . $pos_id);
    echo json_encode(['success'=>true,'documents'=>$docs]);
    exit;
}

// ============================================================
// AJAX: CREATE / SEND DV REQUEST
// ============================================================
if (isset($_POST['ajax_create_dv_request'])) {
    header('Content-Type: application/json');
    $candidate_id = intval($_POST['candidate_id']);
    $category     = in_array($_POST['category'], ['fresher','experienced','blue_collar']) ? $_POST['category'] : 'fresher';
    $expiry_hours = $_POST['expiry_hours'] ?? '48';
    $expiry_custom = $_POST['expiry_custom'] ?? '';

    $cand = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_screenings WHERE id=$candidate_id LIMIT 1"));
    if (!$cand) { echo json_encode(['success'=>false,'message'=>'Candidate not found']); exit; }

    // Delete old request if exists and not yet verified
    $old = getDVRequest($con, $candidate_id);
    if ($old && $old['status'] !== 'verified') {
        mysqli_query($con, "DELETE FROM hr_dv_documents WHERE request_id=" . $old['id']);
        mysqli_query($con, "DELETE FROM hr_dv_requests WHERE id=" . $old['id']);
    }

    // A position-specific document set (if HR has configured one for this candidate's
    // position) takes precedence over the generic Fresher/Experienced/Blue Collar category.
    if (!empty($cand['position_id'])) {
        $pos_cat = 'position_' . intval($cand['position_id']);
        $pos_doc_check = mysqli_query($con, "SELECT id FROM hr_dv_settings WHERE category='$pos_cat' LIMIT 1");
        if ($pos_doc_check && mysqli_num_rows($pos_doc_check) > 0) {
            $category = $pos_cat;
        }
    }

    $dv_number  = generateDVNumber($con);
    $token      = bin2hex(random_bytes(32));
    $cname      = mysqli_real_escape_string($con, $cand['candidate_name']);
    $cemail     = mysqli_real_escape_string($con, $cand['candidate_email'] ?? '');
    $cphone     = mysqli_real_escape_string($con, $cand['candidate_phone'] ?? '');
    $created_by = mysqli_real_escape_string($con, $current_user_name);
    $cat_e      = mysqli_real_escape_string($con, $category);
    $dvn_e      = mysqli_real_escape_string($con, $dv_number);

    if ($expiry_hours === 'custom' && !empty($expiry_custom)) {
        $expiry_sql = "'" . date('Y-m-d H:i:s', strtotime($expiry_custom)) . "'";
    } else {
        $hrs = intval($expiry_hours);
        $expiry_sql = $hrs > 0 ? "'" . date('Y-m-d H:i:s', strtotime("+{$hrs} hours")) . "'" : "NULL";
    }

    mysqli_query($con, "INSERT INTO hr_dv_requests (dv_number, candidate_id, candidate_name, candidate_email, candidate_phone, category, token, expiry_at, status, created_by) VALUES ('$dvn_e', $candidate_id, '$cname', '$cemail', '$cphone', '$cat_e', '$token', $expiry_sql, 'pending', '$created_by')");
    $rid = mysqli_insert_id($con);

    // Pre-create document rows for tracking
    $settings = getDVSettings($con, $category);
    foreach ($settings as $s) {
        $dname_e = mysqli_real_escape_string($con, $s['document_name']);
        mysqli_query($con, "INSERT INTO hr_dv_documents (request_id, setting_id, document_name) VALUES ($rid, {$s['id']}, '$dname_e')");
    }

    $link = $base_url . $script_dir . '/hr-document-verification.php?token=' . $token;
    echo json_encode(['success'=>true,'dv_number'=>$dv_number,'link'=>$link,'candidate'=>$cand,'expiry_sql'=>$expiry_sql]);
    exit;
}

// ============================================================
// AJAX: GET DV STATUS FOR CANDIDATE (used in hr-screening)
// ============================================================
if (isset($_GET['ajax_dv_status'])) {
    header('Content-Type: application/json');
    $candidate_id = intval($_GET['candidate_id']);
    $req  = getDVRequest($con, $candidate_id);
    $docs = $req ? getDVDocuments($con, $req['id']) : [];
    echo json_encode(['success'=>true,'request'=>$req,'documents'=>$docs]);
    exit;
}

// ============================================================
// AJAX: VERIFY SINGLE DOCUMENT
// ============================================================
if (isset($_POST['ajax_verify_document'])) {
    header('Content-Type: application/json');
    $doc_id = intval($_POST['doc_id']);
    $by     = mysqli_real_escape_string($con, $current_user_name);
    $now    = date('Y-m-d H:i:s');
    mysqli_query($con, "UPDATE hr_dv_documents SET is_verified=1, verified_at='$now', verified_by='$by', is_rejected=0, rejection_category=NULL, rejection_reason=NULL, rejected_by=NULL, rejected_at=NULL WHERE id=$doc_id");
    echo json_encode(['success'=>true]);
    exit;
}

// ============================================================
// AJAX: REJECT SINGLE DOCUMENT
// ============================================================
if (isset($_POST['ajax_reject_document'])) {
    header('Content-Type: application/json');
    $doc_id   = intval($_POST['doc_id']);
    $category = trim($_POST['rejection_category'] ?? '');
    $reason   = trim($_POST['rejection_reason'] ?? '');

    $allowed_categories = ['wrong_document','unclear_image','incomplete_document','poor_quality','expired_document','other'];
    if (!in_array($category, $allowed_categories, true)) {
        echo json_encode(['success'=>false,'message'=>'Please select a valid rejection reason.']);
        exit;
    }
    if ($reason === '') {
        echo json_encode(['success'=>false,'message'=>'A rejection reason is required.']);
        exit;
    }

    $doc = mysqli_fetch_assoc(mysqli_query($con, "SELECT dd.*, dr.candidate_id FROM hr_dv_documents dd JOIN hr_dv_requests dr ON dr.id = dd.request_id WHERE dd.id=$doc_id LIMIT 1"));
    if (!$doc) { echo json_encode(['success'=>false,'message'=>'Document not found.']); exit; }

    $by_e       = mysqli_real_escape_string($con, $current_user_name);
    $now        = date('Y-m-d H:i:s');
    $cat_e      = mysqli_real_escape_string($con, $category);
    $reason_e   = mysqli_real_escape_string($con, $reason);

    mysqli_query($con, "UPDATE hr_dv_documents SET is_verified=0, is_rejected=1, rejection_category='$cat_e', rejection_reason='$reason_e', rejected_by='$by_e', rejected_at='$now' WHERE id=$doc_id");

    // A rejected document means verification is no longer complete for this request —
    // drop it back to 'submitted' so the candidate portal reopens for re-upload.
    mysqli_query($con, "UPDATE hr_dv_requests SET status='submitted', updated_at='$now' WHERE id=" . intval($doc['request_id']) . " AND status='verified'");

    echo json_encode(['success'=>true, 'candidate_id'=>intval($doc['candidate_id']), 'document_name'=>$doc['document_name']]);
    exit;
}

// ============================================================
// AJAX: VERIFY ALL DOCUMENTS
// ============================================================
if (isset($_POST['ajax_verify_all'])) {
    header('Content-Type: application/json');
    $request_id = intval($_POST['request_id']);
    $by  = mysqli_real_escape_string($con, $current_user_name);
    $now = date('Y-m-d H:i:s');
    mysqli_query($con, "UPDATE hr_dv_documents SET is_verified=1, verified_at='$now', verified_by='$by' WHERE request_id=$request_id AND is_rejected=0");

    $still_rejected = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_dv_documents WHERE request_id=$request_id AND is_rejected=1 LIMIT 1"));
    if (!$still_rejected) {
        mysqli_query($con, "UPDATE hr_dv_requests SET status='verified', verified_at='$now', verified_by='$by' WHERE id=$request_id");
    }
    echo json_encode(['success'=>true]);
    exit;
}

// ============================================================
// AJAX: LOAD DV PANEL FOR HR-SCREENING (inline embed)
// ============================================================
if (isset($_GET['ajax_dv_panel'])) {
    $candidate_id = intval($_GET['candidate_id']);
    $cand = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_screenings WHERE id=$candidate_id LIMIT 1"));
    if (!$cand) { echo '<p style="color:red;">Candidate not found.</p>'; exit; }

    $req  = getDVRequest($con, $candidate_id);
    $docs = $req ? getDVDocuments($con, $req['id']) : [];
    $fresher_settings    = getDVSettings($con, 'fresher');
    $experienced_settings = getDVSettings($con, 'experienced');

    $dv_link = $req ? $base_url . $script_dir . '/hr-document-verification.php?token=' . $req['token'] : '';
    $cand_phone_clean = preg_replace('/[^0-9]/', '', $cand['candidate_phone'] ?? '');

    // Status colors
    $status_styles = [
        'pending'   => ['bg'=>'#fff7ed','color'=>'#92400e','icon'=>'⏳','label'=>'Pending — Awaiting Candidate Upload'],
        'submitted' => ['bg'=>'#dbeafe','color'=>'#1e40af','icon'=>'📥','label'=>'Submitted — Awaiting HR Verification'],
        'verified'  => ['bg'=>'#dcfce7','color'=>'#065f46','icon'=>'✅','label'=>'Verified — All Documents Cleared'],
    ];
    $cur_status = $req ? ($req['status'] ?? 'pending') : null;
    $ss = $cur_status ? ($status_styles[$cur_status] ?? $status_styles['pending']) : null;

    // ---- TOP STATUS BANNER ----
    if ($req && $ss) {
        echo '<div style="background:'.$ss['bg'].';border-radius:12px;padding:16px 20px;margin-bottom:18px;display:flex;align-items:center;gap:12px;">
            <span style="font-size:24px;">'.$ss['icon'].'</span>
            <div>
                <div style="font-weight:800;color:'.$ss['color'].';font-size:14px;">'.$ss['label'].'</div>
                <div style="font-size:12px;color:'.$ss['color'].';opacity:.8;margin-top:2px;">Ref: '.$req['dv_number'].' &middot; '.dvCategoryLabel($con, $req['category']).' &middot; Created: '.date('d M Y, h:i A', strtotime($req['created_at'])).'</div>
            </div>
        </div>';
    }

    // ---- CONGRATULATE / REJECT / REJECTION NOTIFY — Offer Round decision ----
    // Always visible, regardless of hr_decision state (hired/rejected/pending), so HR can
    // still send a congratulations/welcome message or a rejection notice at any point,
    // even after the candidate has already been marked Hired.
    $dv_c_name  = $cand['candidate_name'] ?? '';
    $dv_c_email = $cand['candidate_email'] ?? '';
    $dv_c_phone = $cand['candidate_phone'] ?? '';
    $dv_c_pos   = $cand['position_applied'] ?? '';

    echo '<div style="background:#fff;border:1px solid #e0e7ff;border-radius:12px;padding:16px 20px;margin-bottom:18px;text-align:center;">';
    echo '<div style="font-weight:800;font-size:12px;color:#64748b;margin-bottom:12px;text-transform:uppercase;">Offer Round Decision</div>';
    echo '<button onclick="openRoundNotifyModal('.$candidate_id.', 0, \''.addslashes(htmlspecialchars($dv_c_name)).'\', \''.addslashes(htmlspecialchars($dv_c_email)).'\', \''.addslashes(htmlspecialchars($dv_c_phone)).'\', \''.addslashes(htmlspecialchars($dv_c_pos)).'\', true)" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;margin-right:8px;"><i class="fas fa-check-circle mr-2"></i>Congratulate Candidate</button>';
    echo '<button onclick="openRejectModal('.$candidate_id.', 0, \'Offer Round\', \'offer\')" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;margin-right:8px;"><i class="fas fa-times-circle mr-2"></i>Reject Candidate</button>';
    echo '<button onclick="openRejectionNotifyModal('.$candidate_id.', 0, \''.addslashes(htmlspecialchars($dv_c_name)).'\', \''.addslashes(htmlspecialchars($dv_c_email)).'\', \''.addslashes(htmlspecialchars($dv_c_phone)).'\', \''.addslashes(htmlspecialchars($dv_c_pos)).'\')" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-paper-plane mr-2"></i>Rejection Notify</button>';
    echo '</div>';

    // ---- CREATE / RESEND SECTION ----
    if (!$req || $req['status'] === 'pending') {
        echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:12px;padding:20px;margin-bottom:18px;">';
        echo '<div style="font-weight:800;font-size:13px;color:#0f2557;margin-bottom:14px;"><i class="fas fa-paper-plane mr-2" style="color:#1a3fc4;"></i>'.($req ? 'Resend Document Verification Link' : 'Send Document Verification Link').'</div>';

        // Category select
        echo '<div style="margin-bottom:12px;">
            <label style="font-size:12px;font-weight:700;color:#64748b;display:block;margin-bottom:6px;">Candidate Type</label>
            <select id="dvCategorySelect_'.$candidate_id.'" style="padding:9px 13px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-weight:700;font-size:13px;width:100%;">
                <option value="fresher" '.($req && $req['category']==='fresher' ? 'selected' : '').'>Fresher</option>
                <option value="experienced" '.($req && $req['category']==='experienced' ? 'selected' : '').'>Experienced</option>
                <option value="blue_collar" '.($req && $req['category']==='blue_collar' ? 'selected' : '').'>Blue Collar</option>
            </select>
        </div>';

        // Expiry
        echo '<div style="margin-bottom:12px;">
            <label style="font-size:12px;font-weight:700;color:#64748b;display:block;margin-bottom:6px;">Link Expiry</label>
            <select id="dvExpirySelect_'.$candidate_id.'" style="padding:9px 13px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-weight:700;font-size:13px;" onchange="if(this.value==\'custom\'){document.getElementById(\'dvExpiryCustom_'.$candidate_id.'\').style.display=\'block\';}else{document.getElementById(\'dvExpiryCustom_'.$candidate_id.'\').style.display=\'none\';}">
                <option value="24">24 Hours</option>
                <option value="48" selected>48 Hours</option>
                <option value="168">7 Days</option>
                <option value="0">No Expiry</option>
                <option value="custom">Custom Date & Time</option>
            </select>
            <input type="datetime-local" id="dvExpiryCustom_'.$candidate_id.'" style="display:none;margin-top:8px;padding:8px 13px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;width:100%;">
        </div>';

        echo '<button onclick="createDVRequest('.$candidate_id.')" style="padding:10px 22px;border:none;border-radius:9px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-link mr-1"></i>Generate & Share Link</button>';
        echo '</div>';
    }

    // ---- LINK & SHARE (if request exists) ----
    if ($req && $dv_link) {
        $wa_msg = rawurlencode("Hi {$req['candidate_name']},\n\nPlease upload your documents for verification using the link below:\n{$dv_link}\n\nRef: {$req['dv_number']}\nExpiry: " . ($req['expiry_at'] ? date('d M Y, h:i A', strtotime($req['expiry_at'])) : 'No expiry'));
        $email_body_raw = "Dear {$req['candidate_name']},\n\nAs part of your selection process, we require you to upload your documents for verification.\n\nPlease use the secure link below:\n{$dv_link}\n\nRef: {$req['dv_number']}\nValid Until: " . ($req['expiry_at'] ? date('d M Y, h:i A', strtotime($req['expiry_at'])) : 'No expiry') . "\n\nPlease upload all required documents at your earliest.\n\nHR Team";

        $dv_is_expired = $req['expiry_at'] && strtotime($req['expiry_at']) < time();

        echo '<div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:12px;padding:16px 20px;margin-bottom:18px;">';
        echo '<div style="font-weight:800;font-size:12px;color:#0369a1;margin-bottom:10px;text-transform:uppercase;"><i class="fas fa-link mr-1"></i> Document Upload Link</div>';

        if ($req['expiry_at']) {
            if ($dv_is_expired) {
                echo '<div style="font-size:12px;font-weight:700;color:#991b1b;background:#fee2e2;border-radius:8px;padding:8px 12px;margin-bottom:12px;"><i class="fas fa-exclamation-triangle mr-1"></i> This link expired on '.date('d M Y, h:i A', strtotime($req['expiry_at'])).' — candidate cannot use it until you extend validity below.</div>';
            } else {
                echo '<div style="font-size:12px;font-weight:700;color:#0369a1;margin-bottom:12px;"><i class="fas fa-clock mr-1"></i> Valid until '.date('d M Y, h:i A', strtotime($req['expiry_at'])).'</div>';
            }
        }

        echo '<div style="display:flex;gap:8px;align-items:center;margin-bottom:12px;">
            <input type="text" id="dvLinkBox_'.$candidate_id.'" value="'.htmlspecialchars($dv_link).'" readonly style="flex:1;padding:9px 12px;border:2px solid #bae6fd;border-radius:8px;font-size:12px;font-family:inherit;background:#fff;">
            <button onclick="copyDVLink('.$candidate_id.')" style="padding:9px 16px;border:none;border-radius:8px;background:#0369a1;color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;white-space:nowrap;"><i class="fas fa-copy mr-1"></i>Copy</button>
        </div>';

        // Share buttons
        echo '<div style="display:flex;gap:8px;flex-wrap:wrap;">';
        if ($cand_phone_clean) {
            echo '<a href="https://wa.me/'.$cand_phone_clean.'?text='.$wa_msg.'" target="_blank" style="padding:9px 16px;border:none;border-radius:8px;background:#25d366;color:#fff;font-family:inherit;font-weight:700;font-size:12px;text-decoration:none;display:inline-flex;align-items:center;gap:5px;"><i class="fab fa-whatsapp"></i> WhatsApp</a>';
        }
        if ($cand['candidate_email']) {
            $email_subj = rawurlencode('Document Verification — ' . $req['dv_number']);
            $email_body_enc = rawurlencode($email_body_raw);
            echo '<a href="mailto:'.htmlspecialchars($cand['candidate_email']).'?subject='.$email_subj.'&body='.$email_body_enc.'" style="padding:9px 16px;border:none;border-radius:8px;background:#6366f1;color:#fff;font-family:inherit;font-weight:700;font-size:12px;text-decoration:none;display:inline-flex;align-items:center;gap:5px;"><i class="fas fa-envelope mr-1"></i> Email</a>';
        }
        if ($req['status'] === 'pending') {
            echo '<button onclick="createDVRequest('.$candidate_id.')" style="padding:9px 16px;border:1px solid #e0e7ff;border-radius:8px;background:#fff;color:#64748b;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-sync-alt mr-1"></i>Regenerate</button>';
        } else {
            echo '<button onclick="extendDVExpiry('.$req['id'].','.$candidate_id.')" style="padding:9px 16px;border:1px solid '.($dv_is_expired?'#ef4444':'#e0e7ff').';border-radius:8px;background:'.($dv_is_expired?'#fef2f2':'#fff').';color:'.($dv_is_expired?'#dc2626':'#64748b').';font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-clock mr-1"></i>Extend Link Validity (48h)</button>';
        }
        echo '</div></div>';
    }

    // ---- SIGNATURE & TNC ----
    if ($req && !empty($req['candidate_signature'])) {
        echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:12px;padding:16px 20px;margin-bottom:18px;">';
        echo '<div style="font-weight:800;font-size:12px;color:#0369a1;margin-bottom:10px;text-transform:uppercase;"><i class="fas fa-file-signature mr-1"></i> Candidate Signature & T&C Acceptance</div>';
        echo '<div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap;">';
        echo '<img src="' . htmlspecialchars($req['candidate_signature']) . '" style="border:2px solid #e0e7ff;border-radius:10px;background:#fff;max-width:220px;height:80px;object-fit:contain;padding:6px;">';
        echo '<div>';
        echo '<div style="font-size:12px;font-weight:700;color:#065f46;"><i class="fas fa-check-circle mr-1"></i> T&C Accepted</div>';
        if ($req['tnc_accepted_at']) {
            echo '<div style="font-size:11px;color:#64748b;margin-top:4px;">Accepted on: ' . date('d M Y, h:i A', strtotime($req['tnc_accepted_at'])) . '</div>';
        }
        echo '</div>';
        echo '</div></div>';
    }

    // ---- DOCUMENTS TABLE ----
    if ($req && !empty($docs)) {
        $all_uploaded  = true;
        $all_verified  = true;
        $upload_count  = 0;
        $verified_count = 0;
        $rejected_docs  = [];

        foreach ($docs as $d) {
            if (!$d['file_path']) $all_uploaded = false;
            else $upload_count++;
            if (!$d['is_verified']) $all_verified = false;
            else $verified_count++;
            if (intval($d['is_rejected'] ?? 0) === 1) $rejected_docs[] = $d;
        }

        echo '<div style="background:#fff;border:1px solid #e0e7ff;border-radius:12px;overflow:hidden;margin-bottom:18px;">';
        echo '<div style="background:linear-gradient(135deg,#f8faff,#eef2ff);padding:14px 20px;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #e0e7ff;flex-wrap:wrap;gap:10px;">';
        echo '<div style="font-weight:800;color:#0f2557;font-size:13px;"><i class="fas fa-folder-open mr-2" style="color:#1a3fc4;"></i>Uploaded Documents ('.$upload_count.' / '.count($docs).')</div>';

        echo '<div style="display:flex;gap:8px;flex-wrap:wrap;">';
        if ($upload_count > 0 && !$all_verified && $req['status'] === 'submitted') {
            echo '<button onclick="verifyAll('.$req['id'].','.$candidate_id.')" style="padding:8px 18px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-check-double mr-1"></i>Verify All</button>';
        }
        if (!empty($rejected_docs) && $dv_link) {
            echo '<button onclick="openDvRejectNotifyModal('.$candidate_id.')" style="padding:8px 18px;border:none;border-radius:8px;background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-paper-plane mr-1"></i>Notify Candidate ('.count($rejected_docs).' Rejected)</button>';
        }
        echo '</div>';
        echo '</div>';

        foreach ($docs as $d) {
            $has_file = !empty($d['file_path']) && file_exists($d['file_path']);
            $is_ver   = intval($d['is_verified']);
            $is_rej   = intval($d['is_rejected'] ?? 0);
            $bg       = $is_rej ? '#fff1f2' : ($is_ver ? '#f0fdf4' : ($has_file ? '#fff' : '#fafafa'));
            $border   = $is_rej ? '#fca5a5' : ($is_ver ? '#86efac' : ($has_file ? '#e0e7ff' : '#f1f5f9'));

            echo '<div style="padding:14px 20px;border-bottom:1px solid #f1f5f9;background:'.$bg.';border-left:4px solid '.$border.';">';
            echo '<div style="display:flex;align-items:center;gap:12px;">';

            // Status icon
            if ($is_rej) echo '<span style="font-size:20px;">❌</span>';
            elseif ($is_ver) echo '<span style="font-size:20px;">✅</span>';
            elseif ($has_file) echo '<span style="font-size:20px;">📄</span>';
            else echo '<span style="font-size:20px;">⬜</span>';

            echo '<div style="flex:1;">';
            echo '<div style="font-weight:700;color:#0f2557;font-size:13px;">'.htmlspecialchars($d['document_name']).'</div>';
            if ($has_file) {
                echo '<div style="font-size:11px;color:#64748b;margin-top:2px;">'.htmlspecialchars($d['file_name']).' &middot; '.htmlspecialchars($d['file_size']).' &middot; Uploaded: '.date('d M Y, h:i A', strtotime($d['uploaded_at'])).'</div>';
                if ($is_rej) {
                    $rej_reason_label = htmlspecialchars($d['rejection_reason'] ?? '');
                    $rej_by = htmlspecialchars($d['rejected_by'] ?? '');
                    $rej_when = !empty($d['rejected_at']) ? date('d M Y, h:i A', strtotime($d['rejected_at'])) : '';
                    echo '<div style="font-size:11px;color:#991b1b;font-weight:700;margin-top:4px;background:#fee2e2;border-radius:6px;padding:6px 10px;">Rejected by '.$rej_by.' on '.$rej_when.' &middot; Reason: '.$rej_reason_label.' &middot; <span style="font-weight:800;">Awaiting candidate re-upload</span></div>';
                } elseif ($is_ver) {
                    echo '<div style="font-size:11px;color:#065f46;font-weight:700;margin-top:2px;">Verified by '.$d['verified_by'].' on '.date('d M Y', strtotime($d['verified_at'])).'</div>';
                }
            } else {
                echo '<div style="font-size:11px;color:#94a3b8;margin-top:2px;">Not yet uploaded</div>';
            }
            echo '</div>';

            // Action buttons
            if ($has_file) {
                echo '<div style="display:flex;gap:6px;flex-wrap:wrap;">';
                echo '<a href="'.htmlspecialchars($d['file_path']).'" target="_blank" style="padding:7px 13px;border:1px solid #e0e7ff;border-radius:7px;background:#fff;color:#1a3fc4;font-size:12px;font-weight:700;text-decoration:none;display:inline-flex;align-items:center;gap:4px;"><i class="fas fa-eye"></i> View</a>';
                echo '<a href="'.htmlspecialchars($d['file_path']).'" download style="padding:7px 13px;border:1px solid #e0e7ff;border-radius:7px;background:#fff;color:#10b981;font-size:12px;font-weight:700;text-decoration:none;display:inline-flex;align-items:center;gap:4px;"><i class="fas fa-download"></i> Download</a>';
                if (!$is_ver && !$is_rej) {
                    echo '<button onclick="verifyDoc('.$d['id'].','.$candidate_id.')" style="padding:7px 13px;border:none;border-radius:7px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-size:12px;font-weight:700;cursor:pointer;"><i class="fas fa-check"></i> Verify</button>';
                }
                if (!$is_rej) {
                    echo '<button onclick="openRejectDocModal('.$d['id'].', '.$candidate_id.', \''.addslashes(htmlspecialchars($d['document_name'])).'\')" style="padding:7px 13px;border:none;border-radius:7px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-size:12px;font-weight:700;cursor:pointer;"><i class="fas fa-times"></i> Reject</button>';
                }
                echo '</div>';
            }

            echo '</div>';

            // HR Upload Section (always visible — upload if missing, replace if exists)
            $upload_label = $has_file ? '🔄 Replace File' : '📤 Upload on Behalf';
            $upload_color = $has_file ? '#6366f1' : '#0f2557';
            echo '<div style="margin-top:10px;padding-top:10px;border-top:1px dashed #e0e7ff;display:flex;align-items:center;gap:10px;flex-wrap:wrap;">';
            echo '<span style="font-size:11px;font-weight:700;color:#64748b;">HR Upload:</span>';
            echo '<label style="padding:7px 14px;border:1px solid '.$upload_color.';border-radius:7px;background:#fff;color:'.$upload_color.';font-size:12px;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:5px;">
                <i class="fas fa-upload"></i> '.$upload_label.'
                <input type="file" style="display:none;" accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
                    onchange="hrUploadDoc(this, '.$req['id'].', '.$d['setting_id'].', \''.addslashes($d['document_name']).'\', '.$candidate_id.')">
            </label>';
            echo '<span id="hrUploadStatus_'.$d['setting_id'].'" style="font-size:11px;font-weight:700;color:#64748b;"></span>';
            echo '</div>';

            echo '</div>';
        }
        echo '</div>';

        // ---- HR TNC ACCEPTANCE ----
        echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:12px;padding:16px 20px;margin-bottom:18px;">';
        echo '<div style="font-weight:800;font-size:12px;color:#0369a1;margin-bottom:10px;text-transform:uppercase;"><i class="fas fa-file-contract mr-1"></i> Terms & Conditions Acceptance</div>';

        if (!empty($req['tnc_hr_accepted']) && $req['tnc_hr_accepted'] == 1) {
            echo '<div style="background:#dcfce7;border:1px solid #86efac;border-radius:8px;padding:12px 14px;display:flex;align-items:center;gap:10px;">';
            echo '<span style="font-size:20px;">✅</span>';
            echo '<div>';
            echo '<div style="font-weight:800;color:#065f46;font-size:13px;">T&C Accepted by HR on behalf of candidate</div>';
            echo '<div style="font-size:11px;color:#166534;margin-top:2px;">Confirmed by: <strong>'.htmlspecialchars($req['tnc_hr_accepted_by']).'</strong> on '.date('d M Y, h:i A', strtotime($req['tnc_hr_accepted_at'])).'</div>';
            echo '</div></div>';
        } elseif (!empty($req['tnc_accepted_at'])) {
            echo '<div style="background:#dcfce7;border:1px solid #86efac;border-radius:8px;padding:12px 14px;display:flex;align-items:center;gap:10px;">';
            echo '<span style="font-size:20px;">✅</span>';
            echo '<div>';
            echo '<div style="font-weight:800;color:#065f46;font-size:13px;">T&C Accepted by Candidate digitally</div>';
            echo '<div style="font-size:11px;color:#166534;margin-top:2px;">Accepted on: '.date('d M Y, h:i A', strtotime($req['tnc_accepted_at'])).'</div>';
            echo '</div></div>';
        } else {
            echo '<div style="background:#fff7ed;border:1px solid #fcd34d;border-radius:8px;padding:12px 14px;margin-bottom:12px;font-size:12px;color:#92400e;font-weight:600;">
                ⚠️ Candidate has not yet accepted T&C digitally. If candidate has physically agreed, HR can confirm below.
            </div>';
            echo '<label style="display:flex;align-items:flex-start;gap:10px;cursor:pointer;font-size:13px;font-weight:700;color:#0f2557;">
                <input type="checkbox" id="hrTncCheck_'.$req['id'].'" style="margin-top:3px;accent-color:#1a3fc4;width:16px;height:16px;">
                I confirm that the candidate has physically read, agreed and signed the Terms & Conditions and Non-Disclosure Agreement.
            </label>';
            echo '<button onclick="submitHrTnc('.$req['id'].', '.$candidate_id.')" style="margin-top:12px;padding:9px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-check-circle mr-1"></i> Confirm T&C Acceptance</button>';
        }
        echo '</div>';

        // ---- OFFER LETTER UNLOCK / HIRED STATUS ----
        $off_q = mysqli_query($con, "SELECT status FROM hr_offer_letters WHERE candidate_id=$candidate_id ORDER BY id DESC LIMIT 1");
        $off_data = mysqli_fetch_assoc($off_q);

        if ($cand['hr_decision'] === 'hired') {
            echo '<div style="background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;border-radius:12px;padding:20px;text-align:center;">';
            echo '<div style="font-size:28px;margin-bottom:8px;">🎉</div>';
            echo '<div style="font-weight:800;color:#065f46;font-size:15px;margin-bottom:6px;">Candidate Successfully Hired!</div>';
            echo '<p style="font-size:13px;color:#166534;margin-bottom:16px;">The candidate is now in the Onboarding Pending List.</p>';
            echo '<a href="hr-employee-onboarding-pending-list.php" style="padding:12px 28px;border:none;border-radius:10px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-weight:700;font-size:14px;text-decoration:none;display:inline-flex;align-items:center;gap:8px;"><i class="fas fa-arrow-right"></i> Go to Onboarding List</a>';
            echo '</div>';
        }
        elseif ($off_data && $off_data['status'] === 'accepted') {
            echo '<div style="background:linear-gradient(135deg,#eff6ff,#dbeafe);border:2px solid #93c5fd;border-radius:12px;padding:20px;text-align:center;">';
            echo '<div style="font-size:28px;margin-bottom:8px;">✅</div>';
            echo '<div style="font-weight:800;color:#1e3a8a;font-size:15px;margin-bottom:6px;">Offer Letter Accepted!</div>';
            echo '<p style="font-size:13px;color:#1e40af;margin-bottom:16px;">The candidate has digitally signed the offer letter. Mark as Hired to begin onboarding.</p>';
            echo '<button onclick="quickMarkHired('.$candidate_id.')" style="padding:12px 28px;border:none;border-radius:10px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-weight:700;font-size:14px;cursor:pointer;display:inline-flex;align-items:center;gap:8px;"><i class="fas fa-user-check"></i> Mark as Hired</button>';
            echo '</div>';
        }
        elseif ($req['status'] === 'verified' || $all_verified) {
            echo '<div style="background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;border-radius:12px;padding:20px;text-align:center;">';
            echo '<div style="font-size:28px;margin-bottom:8px;">🎉</div>';
            echo '<div style="font-weight:800;color:#065f46;font-size:15px;margin-bottom:6px;">All Documents Verified!</div>';
            echo '<p style="font-size:13px;color:#166534;margin-bottom:16px;">You can now proceed to create and send the Offer Letter.</p>';
            echo '<a href="hr-employee-offer.php?candidate_id='.$candidate_id.'" style="padding:12px 28px;border:none;border-radius:10px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-weight:700;font-size:14px;text-decoration:none;display:inline-flex;align-items:center;gap:8px;"><i class="fas fa-file-signature"></i> Open Offer Letter</a>';
            echo '</div>';
        } else {
            echo '<div style="background:#f8faff;border:2px dashed #cbd5e1;border-radius:12px;padding:20px;text-align:center;opacity:.7;">';
            echo '<div style="font-size:28px;margin-bottom:8px;">🔒</div>';
            echo '<div style="font-weight:800;color:#475569;font-size:14px;">Offer Letter Locked</div>';
            echo '<p style="font-size:12px;color:#94a3b8;margin-top:6px;">Offer letter will be unlocked once all documents are verified.</p>';
            echo '</div>';
        }
    } elseif ($req && empty($docs)) {
        echo '<div style="text-align:center;padding:30px;color:#94a3b8;"><i class="fas fa-folder-open fa-2x" style="margin-bottom:10px;display:block;"></i>No documents uploaded yet.</div>';
    }

    // Custom Confirmation Modal HTML
    echo '<div id="hrDvConfirmModal_' . $candidate_id . '" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(15,37,87,0.5);backdrop-filter:blur(4px);z-index:9999;align-items:center;justify-content:center;padding:20px;">
        <div style="background:#fff;border-radius:16px;box-shadow:0 10px 40px rgba(0,0,0,0.2);max-width:400px;width:100%;padding:32px;text-align:center;">
            <div style="font-size:48px;margin-bottom:16px;">✅</div>
            <div id="hrDvConfirmTitle_' . $candidate_id . '" style="font-size:18px;font-weight:800;color:#0f2557;margin-bottom:12px;">Confirm Action</div>
            <div id="hrDvConfirmText_' . $candidate_id . '" style="font-size:14px;color:#64748b;margin-bottom:24px;line-height:1.6;">Are you sure?</div>
            <div style="display:flex;gap:12px;">
                <button type="button" onclick="document.getElementById(\'hrDvConfirmModal_' . $candidate_id . '\').style.display=\'none\'" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:#f1f5f9;color:#475569;font-family:inherit;">Cancel</button>
                <button type="button" id="hrDvConfirmBtn_' . $candidate_id . '" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;">Yes, Confirm</button>
            </div>
        </div>
    </div>';

    // Reject Document Modal HTML
    echo '<div id="hrDvRejectModal_' . $candidate_id . '" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(15,37,87,0.5);backdrop-filter:blur(4px);z-index:9999;align-items:center;justify-content:center;padding:20px;">
        <div style="background:#fff;border-radius:16px;box-shadow:0 10px 40px rgba(0,0,0,0.2);max-width:440px;width:100%;padding:32px;text-align:left;">
            <div style="font-size:40px;margin-bottom:12px;text-align:center;">❌</div>
            <div style="font-size:18px;font-weight:800;color:#0f2557;margin-bottom:4px;text-align:center;">Reject Document</div>
            <div style="font-size:13px;color:#64748b;margin-bottom:20px;text-align:center;">Rejecting: <strong id="hrDvRejectDocNameLabel_' . $candidate_id . '"></strong></div>

            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Rejection Reason *</label>
            <select id="hrDvRejectCategory_' . $candidate_id . '" style="width:100%;padding:10px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-weight:600;font-size:13px;margin-bottom:14px;">
                <option value="">Select a reason...</option>
                <option value="wrong_document">Wrong Document</option>
                <option value="unclear_image">Unclear / Blurry Image</option>
                <option value="incomplete_document">Incomplete Document</option>
                <option value="poor_quality">Poor Image / Background Quality</option>
                <option value="expired_document">Expired Document</option>
                <option value="other">Other</option>
            </select>

            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Details for Candidate *</label>
            <textarea id="hrDvRejectNotes_' . $candidate_id . '" rows="3" placeholder="Explain what is wrong so the candidate knows what to fix..." style="width:100%;padding:10px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;resize:vertical;margin-bottom:20px;"></textarea>

            <div style="display:flex;gap:12px;">
                <button type="button" onclick="closeRejectDocModal(' . $candidate_id . ')" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:#f1f5f9;color:#475569;font-family:inherit;">Cancel</button>
                <button type="button" onclick="submitRejectDoc(' . $candidate_id . ')" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;">Reject Document</button>
            </div>
        </div>
    </div>';

    // Notify Candidate of Rejections Modal HTML (message preview/edit, same UX as Rejection Notify elsewhere)
    $rejected_docs_for_modal = $rejected_docs ?? [];
    if (!empty($rejected_docs_for_modal) && $dv_link) {
        $rej_lines = [];
        foreach ($rejected_docs_for_modal as $rd) {
            $rej_lines[] = '- ' . $rd['document_name'] . ': ' . $rd['rejection_reason'];
        }
        $rej_all_msg = "Hi {$req['candidate_name']},\n\n" . count($rejected_docs_for_modal) . " document(s) could not be verified and need to be re-uploaded:\n\n"
            . implode("\n", $rej_lines)
            . "\n\nPlease re-upload the correct document(s) using your original link:\n{$dv_link}\n\nRef: {$req['dv_number']}";
        $rej_all_subj = 'Documents Need Re-upload — ' . $req['dv_number'];

        echo '<div id="hrDvNotifyModal_' . $candidate_id . '" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(15,37,87,0.5);backdrop-filter:blur(4px);z-index:9999;align-items:center;justify-content:center;padding:20px;">
            <div style="background:#fff;border-radius:16px;box-shadow:0 10px 40px rgba(0,0,0,0.2);max-width:520px;width:100%;padding:32px;text-align:left;max-height:90vh;overflow-y:auto;">
                <div style="font-size:18px;font-weight:800;color:#0f2557;margin-bottom:4px;"><i class="fas fa-paper-plane mr-2" style="color:#6b7280;"></i>Notify Candidate — Rejected Documents</div>
                <div style="font-size:12px;color:#64748b;margin-bottom:18px;">Review or edit the message before sending.</div>

                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">WhatsApp Number</label>
                <input type="text" id="hrDvNotifyPhone_' . $candidate_id . '" value="' . htmlspecialchars($cand_phone_clean ?: '') . '" style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;margin-bottom:6px;">
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">WhatsApp Message</label>
                <textarea id="hrDvNotifyWaMsg_' . $candidate_id . '" rows="6" style="width:100%;padding:10px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:12px;resize:vertical;margin-bottom:8px;">' . htmlspecialchars($rej_all_msg) . '</textarea>
                <button type="button" onclick="sendDvNotifyWhatsApp(' . $candidate_id . ')" style="width:100%;padding:10px;border:none;border-radius:9px;background:#25d366;color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;margin-bottom:20px;"><i class="fab fa-whatsapp mr-1"></i> Open WhatsApp</button>

                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Email To</label>
                <input type="text" id="hrDvNotifyEmailTo_' . $candidate_id . '" value="' . htmlspecialchars($cand['candidate_email'] ?? '') . '" style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;margin-bottom:6px;">
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Email Subject</label>
                <input type="text" id="hrDvNotifyEmailSubj_' . $candidate_id . '" value="' . htmlspecialchars($rej_all_subj) . '" style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;margin-bottom:6px;">
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Email Body</label>
                <textarea id="hrDvNotifyEmailBody_' . $candidate_id . '" rows="6" style="width:100%;padding:10px 12px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:12px;resize:vertical;margin-bottom:20px;">' . htmlspecialchars($rej_all_msg) . '</textarea>

                <div style="display:flex;gap:12px;">
                    <button type="button" onclick="document.getElementById(\'hrDvNotifyModal_' . $candidate_id . '\').style.display=\'none\'" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:#f1f5f9;color:#475569;font-family:inherit;">Cancel</button>
                    <button type="button" id="hrDvNotifyEmailBtn_' . $candidate_id . '" onclick="sendDvNotifyEmail(' . $candidate_id . ')" style="flex:1;padding:12px;border-radius:10px;font-weight:700;font-size:14px;cursor:pointer;border:none;background:linear-gradient(135deg,#6366f1,#4338ca);color:#fff;font-family:inherit;"><i class="fas fa-envelope mr-1"></i> Send Email</button>
                </div>
            </div>
        </div>';
    }

    // Inline JS for panel actions
    echo '<script>
    function quickMarkHired(cid) {
        if(!confirm("Mark this candidate as Hired? They will be ready for onboarding.")) return;
        var btn = event.currentTarget;
        var old = btn.innerHTML;
        btn.innerHTML = "<i class=\"fas fa-spinner fa-spin\"></i> Marking...";
        $.post("hr_screening.php", { ajax_update_decision: 1, screening_id: cid, decision: "hired", notes: "Automatically marked as Hired after offer acceptance." }, function(resp) {
            if(resp.success) {
                alert("Candidate marked as Hired! They are now in the Onboarding Pending List.");
                location.reload();
            } else {
                alert("Failed to mark as Hired.");
                btn.innerHTML = old;
            }
        }, "json").fail(function() {
            alert("Server Error.");
            btn.innerHTML = old;
        });
    }

    function copyDVLink(cid) {
        var box = document.getElementById("dvLinkBox_" + cid);
        box.select(); document.execCommand("copy");
        alert("Link copied!");
    }

    function extendDVExpiry(requestId, cid) {
        if (!confirm("Extend this link\'s validity by 48 hours? The candidate\'s already uploaded documents will NOT be affected.")) return;
        $.post("hr-document-verification.php", { ajax_extend_dv_expiry: 1, request_id: requestId, expiry_hours: 48 }, function(resp) {
            if (resp.success) {
                var container = document.getElementById("dvPanelContainer_" + cid);
                if (container) {
                    container.innerHTML = "<div style=\"text-align:center;padding:20px;\"><i class=\"fas fa-spinner fa-spin fa-2x\" style=\"color:#1a3fc4;\"></i></div>";
                    $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=" + cid, function(html) {
                        container.innerHTML = html;
                    });
                }
            } else {
                alert("Could not extend link validity.");
            }
        }, "json").fail(function() { alert("Server error."); });
    }

    function openDvRejectNotifyModal(cid) {
        document.getElementById("hrDvNotifyModal_" + cid).style.display = "flex";
    }

    function sendDvNotifyWhatsApp(cid) {
        var phone = document.getElementById("hrDvNotifyPhone_" + cid).value.replace(/[^0-9]/g, "");
        var msg = document.getElementById("hrDvNotifyWaMsg_" + cid).value;
        if (!phone) { alert("Please enter a valid WhatsApp number."); return; }
        window.open("https://wa.me/" + phone + "?text=" + encodeURIComponent(msg), "_blank");
        document.getElementById("hrDvNotifyModal_" + cid).style.display = "none";
    }

    function sendDvNotifyEmail(cid) {
        var to = document.getElementById("hrDvNotifyEmailTo_" + cid).value.trim();
        var subj = document.getElementById("hrDvNotifyEmailSubj_" + cid).value.trim();
        var body = document.getElementById("hrDvNotifyEmailBody_" + cid).value.trim();
        if (!to) { alert("Recipient email is required."); return; }
        if (!confirm("Send this email to " + to + "?")) return;

        var btn = document.getElementById("hrDvNotifyEmailBtn_" + cid);
        var oldHtml = btn.innerHTML;
        btn.innerHTML = "<i class=\"fas fa-spinner fa-spin\"></i> Sending...";
        btn.disabled = true;

        $.post("hr_screening.php", {
            ajax_send_round_email: 1,
            to: to,
            subject: subj,
            body: body,
            sid: cid,
            round: 0
        }, function(resp) {
            if (resp.success) {
                alert("Email sent successfully!");
                document.getElementById("hrDvNotifyModal_" + cid).style.display = "none";
            } else {
                alert(resp.message || "Could not send email.");
            }
        }, "json").fail(function() {
            alert("Server error while sending email.");
        }).always(function() {
            btn.innerHTML = oldHtml;
            btn.disabled = false;
        });
    }

    function createDVRequest(cid) {
        var category = document.getElementById("dvCategorySelect_" + cid).value;
        var expiry   = document.getElementById("dvExpirySelect_" + cid).value;
        var custom   = document.getElementById("dvExpiryCustom_" + cid) ? document.getElementById("dvExpiryCustom_" + cid).value : "";
        if (!category) { alert("Please select candidate type."); return; }

        $.post("hr-document-verification.php", {
            ajax_create_dv_request: 1,
            candidate_id: cid,
            category: category,
            expiry_hours: expiry,
            expiry_custom: custom
        }, function(resp) {
            if (resp.success) {
                // Reload DV panel
                var container = document.getElementById("dvPanelContainer_" + cid);
                if (container) {
                    container.innerHTML = "<div style=\"text-align:center;padding:20px;\"><i class=\"fas fa-spinner fa-spin fa-2x\" style=\"color:#1a3fc4;\"></i></div>";
                    $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=" + cid, function(html) {
                        container.innerHTML = html;
                    });
                }
            } else {
                alert("Error: " + (resp.message || "Could not create request."));
            }
        }, "json").fail(function() { alert("Server error."); });
    }

    function verifyDoc(docId, cid) {
        document.getElementById("hrDvConfirmTitle_" + cid).innerText = "Verify Document?";
        document.getElementById("hrDvConfirmText_" + cid).innerText = "Mark this document as verified?";
        var btn = document.getElementById("hrDvConfirmBtn_" + cid);
        btn.onclick = function() {
            document.getElementById("hrDvConfirmModal_" + cid).style.display = "none";
            $.post("hr-document-verification.php", { ajax_verify_document: 1, doc_id: docId }, function(resp) {
                if (resp.success) {
                    var container = document.getElementById("dvPanelContainer_" + cid);
                    if (container) {
                        container.innerHTML = "<div style=\"text-align:center;padding:20px;\"><i class=\"fas fa-spinner fa-spin fa-2x\" style=\"color:#1a3fc4;\"></i></div>";
                        $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=" + cid, function(html) {
                            container.innerHTML = html;
                        });
                    }
                }
            }, "json");
        };
        document.getElementById("hrDvConfirmModal_" + cid).style.display = "flex";
    }

    function openRejectDocModal(docId, cid, docName) {
        var modal = document.getElementById("hrDvRejectModal_" + cid);
        modal.setAttribute("data-doc-id", docId);
        document.getElementById("hrDvRejectDocNameLabel_" + cid).innerText = docName;
        document.getElementById("hrDvRejectCategory_" + cid).value = "";
        document.getElementById("hrDvRejectNotes_" + cid).value = "";
        modal.style.display = "flex";
    }

    function closeRejectDocModal(cid) {
        document.getElementById("hrDvRejectModal_" + cid).style.display = "none";
    }

    function submitRejectDoc(cid) {
        var modal = document.getElementById("hrDvRejectModal_" + cid);
        var docId = modal.getAttribute("data-doc-id");
        var category = document.getElementById("hrDvRejectCategory_" + cid).value;
        var notes = document.getElementById("hrDvRejectNotes_" + cid).value.trim();
        if (!category) { alert("Please select a rejection reason."); return; }
        if (!notes) { alert("Please enter details for the candidate before rejecting."); return; }

        $.post("hr-document-verification.php", {
            ajax_reject_document: 1,
            doc_id: docId,
            rejection_category: category,
            rejection_reason: notes
        }, function(resp) {
            if (resp.success) {
                closeRejectDocModal(cid);
                var container = document.getElementById("dvPanelContainer_" + cid);
                if (container) {
                    container.innerHTML = "<div style=\"text-align:center;padding:20px;\"><i class=\"fas fa-spinner fa-spin fa-2x\" style=\"color:#1a3fc4;\"></i></div>";
                    $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=" + cid, function(html) {
                        container.innerHTML = html;
                    });
                }
            } else {
                alert("Error: " + (resp.message || "Could not reject document."));
            }
        }, "json").fail(function() {
            alert("Server error while rejecting document.");
        });
    }

    function verifyAll(requestId, cid) {
        document.getElementById("hrDvConfirmTitle_" + cid).innerText = "Verify All Documents?";
        document.getElementById("hrDvConfirmText_" + cid).innerText = "Mark ALL uploaded documents as verified?";
        var btn = document.getElementById("hrDvConfirmBtn_" + cid);
        btn.onclick = function() {
            document.getElementById("hrDvConfirmModal_" + cid).style.display = "none";
            $.post("hr-document-verification.php", { ajax_verify_all: 1, request_id: requestId }, function(resp) {
                if (resp.success) {
                    var container = document.getElementById("dvPanelContainer_" + cid);
                    if (container) {
                        container.innerHTML = "<div style=\"text-align:center;padding:20px;\"><i class=\"fas fa-spinner fa-spin fa-2x\" style=\"color:#1a3fc4;\"></i></div>";
                        $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=" + cid, function(html) {
                            container.innerHTML = html;
                        });
                    }
                }
            }, "json");
        };
        document.getElementById("hrDvConfirmModal_" + cid).style.display = "flex";
    }

    function hrUploadDoc(input, requestId, settingId, docName, candidateId) {
        if (!input.files || !input.files[0]) return;
        var statusEl = document.getElementById(\'hrUploadStatus_\' + settingId);
        if (statusEl) statusEl.innerHTML = \'<i class="fas fa-spinner fa-spin"></i> Uploading...\';

        var formData = new FormData();
        formData.append(\'ajax_hr_upload_doc\', \'1\');
        formData.append(\'request_id\', requestId);
        formData.append(\'setting_id\', settingId);
        formData.append(\'doc_name\', docName);
        formData.append(\'hr_doc_file\', input.files[0]);

        $.ajax({
            url: \'hr-document-verification.php\',
            type: \'POST\',
            data: formData,
            processData: false,
            contentType: false,
            success: function(resp) {
                if (resp.success) {
                    var container = document.getElementById(\'dvPanelContainer_\' + candidateId);
                    if (container) {
                        container.innerHTML = \'<div style="text-align:center;padding:20px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:#1a3fc4;"></i></div>\';
                        $.get(\'hr-document-verification.php?ajax_dv_panel=1&candidate_id=\' + candidateId, function(html) {
                            container.innerHTML = html;
                        });
                    }
                } else {
                    if (statusEl) statusEl.innerHTML = \'<span style="color:#ef4444;">❌ \' + (resp.message || \'Failed\') + \'</span>\';
                }
            },
            dataType: \'json\'
        });
    }

    function submitHrTnc(requestId, candidateId) {
        var checkbox = document.getElementById(\'hrTncCheck_\' + requestId);
        if (!checkbox || !checkbox.checked) {
            alert(\'Please check the confirmation checkbox first.\');
            return;
        }
        $.post(\'hr-document-verification.php\', {
            ajax_hr_tnc_accept: 1,
            request_id: requestId
        }, function(resp) {
            if (resp.success) {
                var container = document.getElementById(\'dvPanelContainer_\' + candidateId);
                if (container) {
                    container.innerHTML = \'<div style="text-align:center;padding:20px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:#1a3fc4;"></i></div>\';
                    $.get(\'hr-document-verification.php?ajax_dv_panel=1&candidate_id=\' + candidateId, function(html) {
                        container.innerHTML = html;
                    });
                }
            } else {
                alert(\'Failed to save T&C acceptance.\');
            }
        }, \'json\');
    }
    </script>';
    exit;
}

// ============================================================
// AJAX: HR MANUAL UPLOAD DOCUMENT
// ============================================================
if (isset($_POST['ajax_hr_upload_doc'])) {
    header('Content-Type: application/json');
    $request_id = intval($_POST['request_id']);
    $setting_id = intval($_POST['setting_id']);
    $doc_name   = mysqli_real_escape_string($con, $_POST['doc_name'] ?? '');

    if (!isset($_FILES['hr_doc_file']) || $_FILES['hr_doc_file']['error'] !== UPLOAD_ERR_OK) {
        echo json_encode(['success' => false, 'message' => 'File upload failed.']);
        exit;
    }

    $file    = $_FILES['hr_doc_file'];
    $ext     = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    $allowed = ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'];
    if (!in_array($ext, $allowed)) {
        echo json_encode(['success' => false, 'message' => 'Invalid file type.']);
        exit;
    }

    $upload_dir = 'uploads/hr_dv/';
    if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);

    $fname  = 'dv_hr_' . $request_id . '_' . $setting_id . '_' . time() . '.' . $ext;
    $fpath  = $upload_dir . $fname;
    $fsize  = round($file['size'] / 1024) . ' KB';
    $now    = date('Y-m-d H:i:s');

    if (!move_uploaded_file($file['tmp_name'], $fpath)) {
        echo json_encode(['success' => false, 'message' => 'Could not save file.']);
        exit;
    }

    $fname_e  = mysqli_real_escape_string($con, $file['name']);
    $fpath_e  = mysqli_real_escape_string($con, $fpath);
    $fsize_e  = mysqli_real_escape_string($con, $fsize);
    $by_e     = mysqli_real_escape_string($con, $current_user_name);

    // Check if doc row exists
    $existing = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_dv_documents WHERE request_id=$request_id AND setting_id=$setting_id LIMIT 1"));
    if ($existing) {
        mysqli_query($con, "UPDATE hr_dv_documents SET file_path='$fpath_e', file_name='$fname_e', file_size='$fsize_e', uploaded_at='$now', is_verified=1, verified_at='$now', verified_by='$by_e', is_rejected=0, rejection_category=NULL, rejection_reason=NULL, rejected_by=NULL, rejected_at=NULL WHERE id=" . $existing['id']);
    } else {
        mysqli_query($con, "INSERT INTO hr_dv_documents (request_id, setting_id, document_name, file_path, file_name, file_size, uploaded_at, is_verified, verified_at, verified_by) VALUES ($request_id, $setting_id, '$doc_name', '$fpath_e', '$fname_e', '$fsize_e', '$now', 1, '$now', '$by_e')");
    }

    // Check overall verification status
    $req_check = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_dv_requests WHERE id=$request_id LIMIT 1"));
    if ($req_check) {
        $settings_check = getDVSettings($con, $req_check['category']);
        $uploaded_docs = mysqli_query($con, "SELECT setting_id, is_verified FROM hr_dv_documents WHERE request_id=$request_id AND file_path IS NOT NULL AND file_path != ''");
        
        $uploaded_map = [];
        while ($dc = mysqli_fetch_assoc($uploaded_docs)) {
            $uploaded_map[$dc['setting_id']] = intval($dc['is_verified']);
        }
        
        $missing = false;
        $unverified = false;
        foreach ($settings_check as $sc) {
            if ($sc['is_required']) {
                if (!isset($uploaded_map[$sc['id']])) {
                    $missing = true;
                } elseif ($uploaded_map[$sc['id']] == 0) {
                    $unverified = true;
                }
            }
        }
        
        if (!$missing) {
            if (!$unverified) {
                mysqli_query($con, "UPDATE hr_dv_requests SET status='verified', verified_at='$now', verified_by='$by_e' WHERE id=$request_id");
            } else {
                mysqli_query($con, "UPDATE hr_dv_requests SET status='submitted', updated_at='$now' WHERE id=$request_id AND status='pending'");
            }
        }
    }

    echo json_encode(['success' => true]);
    exit;
}

// ============================================================
// AJAX: HR TNC ACCEPTANCE
// ============================================================
if (isset($_POST['ajax_hr_tnc_accept'])) {
    header('Content-Type: application/json');
    $request_id = intval($_POST['request_id']);
    $by  = mysqli_real_escape_string($con, $current_user_name);
    $now = date('Y-m-d H:i:s');
    mysqli_query($con, "UPDATE hr_dv_requests SET tnc_hr_accepted=1, tnc_hr_accepted_by='$by', tnc_hr_accepted_at='$now' WHERE id=$request_id");
    echo json_encode(['success' => true]);
    exit;
}

// ============================================================
// AJAX: EXTEND DV LINK EXPIRY (non-destructive — keeps same token & all uploaded/verified documents)
// ============================================================
if (isset($_POST['ajax_extend_dv_expiry'])) {
    header('Content-Type: application/json');
    $request_id   = intval($_POST['request_id']);
    $expiry_hours = $_POST['expiry_hours'] ?? '48';

    $hrs = intval($expiry_hours);
    $expiry_sql = $hrs > 0 ? "'" . date('Y-m-d H:i:s', strtotime("+{$hrs} hours")) . "'" : "NULL";

    mysqli_query($con, "UPDATE hr_dv_requests SET expiry_at=$expiry_sql, updated_at=NOW() WHERE id=$request_id");
    echo json_encode(['success' => true]);
    exit;
}

// ============================================================
// SETTINGS PAGE (standalone, linked from offer page settings)
// ============================================================
$fresher_docs     = getDVSettings($con, 'fresher');
$experienced_docs = getDVSettings($con, 'experienced');
$blue_collar_docs = getDVSettings($con, 'blue_collar');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Document Verification Settings</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--success:#10b981;--border:#e4e9f2;--bg:#f0f4f9;--muted:#64748b;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:20px 30px;display:flex;justify-content:space-between;align-items:center;border-radius:10px;box-shadow:0 4px 15px rgba(30, 58, 138, 0.3);margin-bottom:20px;}
.hdr h1{color:#fff;font-size:1.8rem;font-weight:600;margin:0;}
.wrap{max-width:1400px;margin:0 auto;padding:20px;}
.card-s{background:#fff;border-radius:14px;border:1px solid var(--border);padding:24px;margin-bottom:20px;box-shadow:0 2px 10px rgba(0,0,0,.05);}
.sec-lbl{font-weight:800;font-size:11px;text-transform:uppercase;color:var(--blue);margin-bottom:14px;padding-bottom:8px;border-bottom:2px solid #eef2ff;}
.doc-setting-row{display:grid;grid-template-columns:1fr auto auto;gap:10px;align-items:center;background:#f8faff;border:1px solid #e0e7ff;border-radius:9px;padding:10px 14px;margin-bottom:8px;}
.fc{border:2px solid var(--border);border-radius:9px;padding:9px 13px;font-size:13px;font-family:inherit;font-weight:600;width:100%;background:#fff;}
.btn-p{padding:10px 20px;border:none;border-radius:9px;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:7px;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;}
.btn-green{background:linear-gradient(135deg,var(--success),#059669);color:#fff;}
.btn-light{background:#f1f5f9;color:var(--navy);border:1px solid var(--border);}
.alert-ok{background:#dcfce7;border:1px solid #86efac;color:#065f46;padding:12px 16px;border-radius:10px;font-weight:700;margin-bottom:16px;}

/* Save confirmation toast — stays visible regardless of scroll position */
.dv-toast{position:fixed;bottom:32px;right:32px;min-width:340px;max-width:460px;padding:20px 26px;border-radius:14px;font-weight:800;font-size:17px;line-height:1.4;box-shadow:0 12px 36px rgba(0,0,0,.2);z-index:9999;opacity:0;transform:translateY(16px);pointer-events:none;transition:opacity .25s ease,transform .25s ease;}
.dv-toast i{font-size:19px;}
.dv-toast-show{opacity:1;transform:translateY(0);}
.dv-toast-success{background:#dcfce7;border:1px solid #86efac;color:#065f46;}
.dv-toast-error{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;}

/* Navigation Tabs */
.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 20px; }
.nav-btn {
    padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
    font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
    display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }
</style>
</head>
<body>

<div class="wrap">
  <div class="hdr">
    <h1><i class="fas fa-layer-group mr-2"></i>HR Screening Rounds Configuration</h1>
    <div style="display:flex;gap:9px;">
      <?php
      $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
      $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
      ?>
      
      <a href="hr-employee-offer.php?page=settings" style="padding:9px 18px;border-radius:9px;background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);color:#fff;font-weight:700;font-size:13px;text-decoration:none;display:inline-flex;align-items:center;gap:6px;"><i class="fas fa-cog"></i> Company Settings</a>
      <a href="hr_screening.php" style="padding:9px 18px;border-radius:9px;background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);color:#fff;font-weight:700;font-size:13px;text-decoration:none;display:inline-flex;align-items:center;gap:6px;"><i class="fas fa-arrow-left"></i> Back to Screening</a>
    </div>
  </div>

  <div class="nav-tabs-container">
    <a href="hr-managing-rounds-kpq.php?view=rounds" class="nav-btn">
      <i class="fas fa-list-ol"></i> Manage Rounds
    </a>
    <a href="hr-managing-rounds-kpq.php?view=questions" class="nav-btn">
      <i class="fas fa-question-circle"></i> Manage Questions (KPQ)
    </a>
    <a href="hr-document-verification.php" class="nav-btn active">
      <i class="fas fa-file-alt"></i> Manage Documents
    </a>
    <a href="hr-employee-offer.php" class="nav-btn">
      <i class="fas fa-envelope-open-text"></i> Manage Offer Letters
    </a>
  </div>

  <div id="settingsAlert"></div>

  <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;">

    <!-- FRESHER -->
    <div class="card-s">
      <div class="sec-lbl"><i class="fas fa-graduation-cap mr-1"></i> Fresher Documents</div>
      <div id="fresherList">
        <?php foreach ($fresher_docs as $idx => $fd): ?>
        <div class="doc-setting-row">
          <input type="text" class="fc fresher-doc-name" value="<?php echo htmlspecialchars($fd['document_name']); ?>" placeholder="Document name">
          <select class="fc fresher-doc-req" style="width:110px;">
            <option value="1" <?php echo $fd['is_required'] ? 'selected' : ''; ?>>Required</option>
            <option value="0" <?php echo !$fd['is_required'] ? 'selected' : ''; ?>>Optional</option>
          </select>
          <button onclick="this.closest('.doc-setting-row').remove()" style="padding:8px 11px;border:none;border-radius:7px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>
        </div>
        <?php endforeach; ?>
      </div>
      <button onclick="addDocRow('fresherList','fresher-doc-name','fresher-doc-req')" class="btn-p btn-light" style="margin-top:8px;"><i class="fas fa-plus"></i> Add Document</button>
    </div>

    <!-- EXPERIENCED -->
    <div class="card-s">
      <div class="sec-lbl"><i class="fas fa-briefcase mr-1"></i> Experienced Documents</div>
      <div id="experiencedList">
        <?php foreach ($experienced_docs as $idx => $ed): ?>
        <div class="doc-setting-row">
          <input type="text" class="fc experienced-doc-name" value="<?php echo htmlspecialchars($ed['document_name']); ?>" placeholder="Document name">
          <select class="fc experienced-doc-req" style="width:110px;">
            <option value="1" <?php echo $ed['is_required'] ? 'selected' : ''; ?>>Required</option>
            <option value="0" <?php echo !$ed['is_required'] ? 'selected' : ''; ?>>Optional</option>
          </select>
          <button onclick="this.closest('.doc-setting-row').remove()" style="padding:8px 11px;border:none;border-radius:7px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>
        </div>
        <?php endforeach; ?>
      </div>
      <button onclick="addDocRow('experiencedList','experienced-doc-name','experienced-doc-req')" class="btn-p btn-light" style="margin-top:8px;"><i class="fas fa-plus"></i> Add Document</button>
    </div>

    <!-- BLUE COLLAR -->
    <div class="card-s">
      <div class="sec-lbl"><i class="fas fa-hard-hat mr-1"></i> Blue Collar Documents</div>
      <div id="blueCollarList">
        <?php foreach ($blue_collar_docs as $idx => $bd): ?>
        <div class="doc-setting-row">
          <input type="text" class="fc blue-collar-doc-name" value="<?php echo htmlspecialchars($bd['document_name']); ?>" placeholder="Document name">
          <select class="fc blue-collar-doc-req" style="width:110px;">
            <option value="1" <?php echo $bd['is_required'] ? 'selected' : ''; ?>>Required</option>
            <option value="0" <?php echo !$bd['is_required'] ? 'selected' : ''; ?>>Optional</option>
          </select>
          <button onclick="this.closest('.doc-setting-row').remove()" style="padding:8px 11px;border:none;border-radius:7px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>
        </div>
        <?php endforeach; ?>
      </div>
      <button onclick="addDocRow('blueCollarList','blue-collar-doc-name','blue-collar-doc-req')" class="btn-p btn-light" style="margin-top:8px;"><i class="fas fa-plus"></i> Add Document</button>
    </div>

  </div>

  <div style="text-align:center;margin-top:10px;">
    <button onclick="saveAllSettings()" class="btn-p btn-navy" style="padding:13px 36px;font-size:14px;"><i class="fas fa-save"></i> Save All Document Settings</button>
  </div>

  <!-- POSITION-SPECIFIC DOCUMENT SETS -->
  <div class="card-s" style="margin-top:24px;">
    <div class="sec-lbl"><i class="fas fa-user-tag mr-1"></i> Position-Specific Document Sets</div>
    <p style="font-size:12px;color:#64748b;margin:-6px 0 14px;">Optional — define a custom document list for one particular position. When set, it overrides the Fresher/Experienced/Blue Collar list for candidates applying to that position.</p>
    <div style="margin-bottom:14px;">
      <select id="posDvSelect" class="fc" style="max-width:360px;" onchange="loadPositionDvDocs(this.value)">
        <option value="">-- Select a Position --</option>
      </select>
    </div>
    <div id="posDvEditor" style="display:none;">
      <div id="positionDocList"></div>
      <button onclick="addDocRow('positionDocList','position-doc-name','position-doc-req')" class="btn-p btn-light" style="margin-top:8px;"><i class="fas fa-plus"></i> Add Document</button>
      <div style="margin-top:14px;">
        <button onclick="savePositionDvDocs()" class="btn-p btn-navy"><i class="fas fa-save"></i> Save Position Documents</button>
      </div>
    </div>
    <div id="posDvAlert" style="margin-top:10px;"></div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script>
function addDocRow(listId, nameClass, reqClass, prefillName, prefillRequired) {
    var list = document.getElementById(listId);
    var row = document.createElement('div');
    row.className = 'doc-setting-row';
    var nameVal = prefillName ? prefillName.replace(/"/g, '&quot;') : '';
    var reqVal  = (prefillRequired === undefined || prefillRequired === null) ? '1' : String(prefillRequired);
    row.innerHTML = '<input type="text" class="fc ' + nameClass + '" value="' + nameVal + '" placeholder="Document name">' +
        '<select class="fc ' + reqClass + '" style="width:110px;"><option value="1"' + (reqVal === '1' ? ' selected' : '') + '>Required</option><option value="0"' + (reqVal === '0' ? ' selected' : '') + '>Optional</option></select>' +
        '<button onclick="this.closest(\'.doc-setting-row\').remove()" style="padding:8px 11px;border:none;border-radius:7px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>';
    list.appendChild(row);
}

function collectDocs(nameClass, reqClass) {
    var docs = [];
    var names = document.querySelectorAll('.' + nameClass);
    var reqs  = document.querySelectorAll('.' + reqClass);
    for (var i = 0; i < names.length; i++) {
        var n = names[i].value.trim();
        if (n) docs.push({ name: n, required: reqs[i] ? reqs[i].value : '1' });
    }
    return docs;
}

function saveAllSettings() {
    var alertBox = document.getElementById('settingsAlert');
    alertBox.innerHTML = '<div class="alert-ok"><i class="fas fa-spinner fa-spin mr-2"></i>Saving...</div>';

    var fresherDocs     = collectDocs('fresher-doc-name', 'fresher-doc-req');
    var experiencedDocs = collectDocs('experienced-doc-name', 'experienced-doc-req');
    var blueCollarDocs  = collectDocs('blue-collar-doc-name', 'blue-collar-doc-req');

    var p1 = $.post('hr-document-verification.php', { ajax_save_dv_settings: 1, category: 'fresher', documents: JSON.stringify(fresherDocs) }, null, 'json');
    var p2 = $.post('hr-document-verification.php', { ajax_save_dv_settings: 1, category: 'experienced', documents: JSON.stringify(experiencedDocs) }, null, 'json');
    var p3 = $.post('hr-document-verification.php', { ajax_save_dv_settings: 1, category: 'blue_collar', documents: JSON.stringify(blueCollarDocs) }, null, 'json');

    $.when(p1, p2, p3).done(function(r1, r2, r3) {
        if (r1[0].success && r2[0].success && r3[0].success) {
            alertBox.innerHTML = '<div class="alert-ok"><i class="fas fa-check-circle mr-2"></i>All document settings saved successfully!</div>';
            showToast('<i class="fas fa-check-circle mr-2"></i>All document settings saved successfully!', false);
        } else {
            alertBox.innerHTML = '<div style="background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:12px;border-radius:10px;font-weight:700;">Could not save settings. Please try again.</div>';
            showToast('<i class="fas fa-exclamation-circle mr-2"></i>Could not save settings. Please try again.', true);
        }
    });
}

// ---- Position-Specific Document Sets ----
document.addEventListener('DOMContentLoaded', function() {
    $.get('hr-document-verification.php', { ajax_list_positions_dv: 1 }, function(res) {
        if (!res.success) return;
        var sel = document.getElementById('posDvSelect');
        res.positions.forEach(function(p) {
            var opt = document.createElement('option');
            opt.value = p.id;
            opt.textContent = p.dept_name + ' — ' + p.title;
            sel.appendChild(opt);
        });
    }, 'json');
});

function loadPositionDvDocs(posId) {
    var editor = document.getElementById('posDvEditor');
    var list = document.getElementById('positionDocList');
    var alertBox = document.getElementById('posDvAlert');
    alertBox.innerHTML = '';
    list.innerHTML = '';
    if (!posId) { editor.style.display = 'none'; return; }
    editor.style.display = 'block';
    $.get('hr-document-verification.php', { ajax_get_position_dv_docs: 1, position_id: posId }, function(res) {
        if (res.success && res.documents.length > 0) {
            res.documents.forEach(function(d) {
                addDocRow('positionDocList', 'position-doc-name', 'position-doc-req', d.document_name, d.is_required);
            });
        }
    }, 'json');
}

function savePositionDvDocs() {
    var posId = document.getElementById('posDvSelect').value;
    var alertBox = document.getElementById('posDvAlert');
    if (!posId) return;
    var docs = collectDocs('position-doc-name', 'position-doc-req');
    alertBox.innerHTML = '<div class="alert-ok"><i class="fas fa-spinner fa-spin mr-2"></i>Saving...</div>';
    $.post('hr-document-verification.php', { ajax_save_dv_settings: 1, category: 'position_' + posId, documents: JSON.stringify(docs) }, function(res) {
        if (res.success) {
            alertBox.innerHTML = '<div class="alert-ok"><i class="fas fa-check-circle mr-2"></i>Position document set saved!</div>';
            showToast('<i class="fas fa-check-circle mr-2"></i>Position document set saved!', false);
        } else {
            alertBox.innerHTML = '<div style="background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:12px;border-radius:10px;font-weight:700;">Could not save. Please try again.</div>';
        }
    }, 'json');
}

function showToast(message, isError) {
    var toast = document.getElementById('dvToast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'dvToast';
        document.body.appendChild(toast);
    }
    toast.className = 'dv-toast ' + (isError ? 'dv-toast-error' : 'dv-toast-success');
    toast.innerHTML = message;
    void toast.offsetWidth; // restart CSS transition if toast is shown again quickly
    toast.classList.add('dv-toast-show');
    clearTimeout(toast._hideTimer);
    toast._hideTimer = setTimeout(function() {
        toast.classList.remove('dv-toast-show');
    }, 3500);
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