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

require_once('database.php');

if (!isset($dbConn) || !$dbConn) { die("Database connection failed."); }
date_default_timezone_set('Asia/Kolkata');

// --- GET TOKEN ---
$token = trim($_GET['token'] ?? '');
if (empty($token)) { die(renderError('Invalid Link', 'This assignment link is invalid or missing.')); }

// --- VALIDATE TOKEN ---
$token_safe = mysqli_real_escape_string($dbConn, $token);
$link = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_assignment_links WHERE token='$token_safe' LIMIT 1"));

if (!$link) { die(renderError('Invalid Link', 'This assignment link does not exist.')); }

// --- CHECK EXPIRY ---
if (!empty($link['expiry_at']) && strtotime($link['expiry_at']) < time()) {
    die(renderError('Link Expired', 'This assignment link has expired. Please contact HR.'));
}

// --- CHECK ALREADY SUBMITTED OR FLAGGED ---
if ($link['status'] === 'submitted') {
    die('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Submitted</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;700;800&display=swap" rel="stylesheet">
    <style>body{font-family:\'Plus Jakarta Sans\',sans-serif;background:#f0f4f9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}
    .box{background:#fff;border-radius:16px;padding:50px 40px;text-align:center;max-width:460px;box-shadow:0 10px 40px rgba(0,0,0,0.1);}
    .icon{font-size:56px;margin-bottom:16px;} h2{color:#0f2557;font-weight:800;} p{color:#64748b;}</style></head>
    <body><div class="box"><div class="icon">✅</div><h2>Already Submitted</h2>
    <p>You have already completed and submitted this assignment.<br>HR will review your answers and get back to you.<br><br>Thank you!</p>
    </div></body></html>');
}
if ($link['status'] === 'flagged' || (!empty($link['is_flagged']) && $link['is_flagged'] == 1)) {
    die(renderError('Session Locked', 'Your assignment session was locked due to security policy violations (e.g., tab switching). Please contact HR.'));
}

// --- FETCH CANDIDATE ---
$candidate = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=" . intval($link['candidate_id']) . " LIMIT 1"));
if (!$candidate) { die(renderError('Not Found', 'Candidate record not found.')); }

// ---- AJAX: LOG TAB SWITCH ----
if (isset($_POST['ajax_log_tab_switch'])) {
    $tok = mysqli_real_escape_string($dbConn, $_POST['token'] ?? '');
    $cnt = intval($_POST['count'] ?? 0);
    $lnk = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_assignment_links WHERE token='$tok' LIMIT 1"));
    if ($lnk) {
        // Add column if missing
        @mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN IF NOT EXISTS tab_switch_count INT DEFAULT 0");
        mysqli_query($dbConn, "UPDATE hr_assignment_links SET tab_switch_count=$cnt WHERE token='$tok'");
    }
    exit;
}

// ---- AJAX: FLAG SESSION ----
if (isset($_POST['ajax_flag_session'])) {
    $tok = mysqli_real_escape_string($dbConn, $_POST['token'] ?? '');
    @mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN IF NOT EXISTS tab_switch_count INT DEFAULT 0");
    @mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN IF NOT EXISTS is_flagged TINYINT(1) DEFAULT 0");
    mysqli_query($dbConn, "UPDATE hr_assignment_links SET is_flagged=1, status='flagged' WHERE token='$tok'");
    exit;
}

// ---- AJAX: SAVE VERIFICATION (LOCATION + SIGNATURE) ----
if (isset($_POST['ajax_save_verification'])) {
    $tok = mysqli_real_escape_string($dbConn, $_POST['token'] ?? '');
    $loc = mysqli_real_escape_string($dbConn, $_POST['location'] ?? '');
    $sig = mysqli_real_escape_string($dbConn, $_POST['signature'] ?? '');
    
    @mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN IF NOT EXISTS candidate_location VARCHAR(255) DEFAULT NULL");
    @mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN IF NOT EXISTS candidate_signature LONGTEXT DEFAULT NULL");
    
    mysqli_query($dbConn, "UPDATE hr_assignment_links SET candidate_location='$loc', candidate_signature='$sig' WHERE token='$tok'");
    
    $_SESSION['assignment_verified_full_' . $tok] = true;
    echo json_encode(['success'=>true]);
    exit;
}

// --- EMAIL VERIFICATION ---
if (!isset($_SESSION['assignment_verified_' . $token_safe])) {
    $verify_error = '';
    if (isset($_POST['verify_email'])) {
        $input_email = trim($_POST['candidate_email'] ?? '');
        $real_email = trim($candidate['candidate_email'] ?? '');
        
        if (empty($real_email)) {
            // Edge case: no email on record
            $_SESSION['assignment_verified_' . $token_safe] = true;
            header("Location: hr_assignment.php?token=" . urlencode($token));
            exit;
        } else if (strtolower($input_email) === strtolower($real_email)) {
            $_SESSION['assignment_verified_' . $token_safe] = true;
            header("Location: hr_assignment.php?token=" . urlencode($token));
            exit;
        } else {
            $verify_error = 'The email address does not match our records for this assignment.';
        }
    }

    if (!isset($_SESSION['assignment_verified_' . $token_safe])) {
        // Show verification form
        echo '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Verify Identity — Assignment</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
body { font-family:"Plus Jakarta Sans",sans-serif; background:#f0f4f9; display:flex; flex-direction:column; align-items:center; justify-content:center; min-height:100vh; margin:0; padding:20px; }
.steps { display:flex; align-items:center; gap:0; margin-bottom:28px; }
.step { display:flex; flex-direction:column; align-items:center; gap:6px; }
.step-circle { width:36px; height:36px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-weight:800; font-size:14px; }
.step.active .step-circle { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; }
.step.inactive .step-circle { background:#e0e7ff; color:#94a3b8; }
.step-label { font-size:11px; font-weight:700; color:#94a3b8; }
.step.active .step-label { color:#1a3fc4; }
.step-line { width:60px; height:3px; background:#e0e7ff; margin-bottom:18px; }
.step-line.done { background:#1a3fc4; }
.box { background:#fff; border-radius:16px; padding:40px 30px; text-align:center; max-width:400px; width:100%; box-shadow:0 10px 40px rgba(0,0,0,0.1); }
.icon { font-size:48px; color:#1a3fc4; margin-bottom:16px; }
h2 { color:#0f2557; font-weight:800; margin-bottom:10px; font-size:22px; }
p { color:#64748b; font-size:14px; margin-bottom:24px; line-height:1.6; }
.fc { border:2px solid #e0e7ff; border-radius:9px; padding:12px 16px; font-size:14px; font-family:inherit; font-weight:600; width:100%; transition:.2s; text-align:center; box-sizing:border-box; margin-bottom:16px; }
.fc:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.08); }
.btn-sub { width:100%; padding:14px; border:none; border-radius:11px; font-family:inherit; font-weight:800; font-size:15px; cursor:pointer; background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; transition:.2s; }
.btn-sub:hover { transform:translateY(-2px); box-shadow:0 7px 20px rgba(26,63,196,.3); }
.err { background:#fee2e2; border:1px solid #fca5a5; color:#991b1b; padding:12px; border-radius:8px; font-size:13px; font-weight:700; margin-bottom:16px; }
</style>
</head>
<body>
    <div class="steps">
        <div class="step active">
            <div class="step-circle">1</div>
            <div class="step-label">Verify Email</div>
        </div>
        <div class="step-line"></div>
        <div class="step inactive">
            <div class="step-circle">2</div>
            <div class="step-label">Identity & Terms</div>
        </div>
        <div class="step-line"></div>
        <div class="step inactive">
            <div class="step-circle">3</div>
            <div class="step-label">Assignment</div>
        </div>
    </div>
    <div class="box">
        <div class="icon"><i class="fas fa-shield-alt"></i></div>
        <h2>Verify Your Identity</h2>
        <p>To access your assignment, please enter the email address you used when applying.</p>';
        if ($verify_error) echo '<div class="err"><i class="fas fa-exclamation-circle mr-1"></i> ' . htmlspecialchars($verify_error) . '</div>';
        echo '<form method="POST">
            <input type="hidden" name="verify_email" value="1">
            <input type="email" name="candidate_email" class="fc" placeholder="Enter your registered email..." required autofocus>
            <button type="submit" class="btn-sub">Access Assignment <i class="fas fa-arrow-right" style="margin-left:6px;"></i></button>
        </form>
    </div>
</body>
</html>';
        exit;
    }

}

if (isset($_SESSION['assignment_verified_' . $token_safe]) && !isset($_SESSION['assignment_verified_full_' . $token_safe])) {
        // Show Location & Signature Verification
        echo '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Verify Identity — Assignment</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
body { font-family:"Plus Jakarta Sans",sans-serif; background:#f0f4f9; display:flex; flex-direction:column; align-items:center; justify-content:center; min-height:100vh; margin:0; padding:20px; }
.steps { display:flex; align-items:center; gap:0; margin-bottom:28px; }
.step { display:flex; flex-direction:column; align-items:center; gap:6px; }
.step-circle { width:36px; height:36px; border-radius:50%; display:flex; align-items:center; justify-content:center; font-weight:800; font-size:14px; }
.step.done .step-circle { background:#22c55e; color:#fff; }
.step.active .step-circle { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; }
.step.inactive .step-circle { background:#e0e7ff; color:#94a3b8; }
.step-label { font-size:11px; font-weight:700; color:#94a3b8; }
.step.active .step-label { color:#1a3fc4; }
.step.done .step-label { color:#22c55e; }
.step-line { width:60px; height:3px; background:#e0e7ff; margin-bottom:18px; }
.step-line.done { background:#22c55e; }
.box { background:#fff; border-radius:16px; padding:40px 30px; text-align:center; max-width:500px; width:100%; box-shadow:0 10px 40px rgba(0,0,0,0.1); }
h2 { color:#0f2557; font-weight:800; margin-bottom:10px; font-size:22px; }
p { color:#64748b; font-size:14px; margin-bottom:24px; line-height:1.6; }
.btn-sub { width:100%; padding:14px; border:none; border-radius:11px; font-family:inherit; font-weight:800; font-size:15px; cursor:pointer; background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; transition:.2s; margin-top:20px; }
.btn-sub:hover { transform:translateY(-2px); box-shadow:0 7px 20px rgba(26,63,196,.3); }
.btn-sub:disabled { opacity:0.6; cursor:not-allowed; transform:none; }
.sig-canvas { border:2px dashed #e0e7ff; border-radius:12px; background:#f8fafc; cursor:crosshair; width:100%; height:150px; touch-action:none; }
.loc-status { font-size:13px; font-weight:700; color:#b45309; background:#fef3c7; padding:8px 12px; border-radius:8px; margin-bottom:16px; display:inline-block; }
.tnc-box { background:#f8faff; border:2px solid #e0e7ff; border-radius:12px; padding:16px; text-align:left; max-height:180px; overflow-y:auto; margin-bottom:16px; font-size:12px; color:#475569; line-height:1.8; }
.tnc-box h4 { color:#0f2557; font-weight:800; font-size:13px; margin-bottom:10px; }
.tnc-box ul { padding-left:16px; }
.tnc-box ul li { margin-bottom:6px; }
.tnc-check { display:flex; align-items:flex-start; gap:10px; text-align:left; margin-bottom:6px; font-size:13px; font-weight:700; color:#0f2557; cursor:pointer; }
.tnc-check input { margin-top:3px; accent-color:#1a3fc4; width:16px; height:16px; cursor:pointer; }
</style>
</head>
<body>
    <div class="steps">
        <div class="step done">
            <div class="step-circle"><i class="fas fa-check"></i></div>
            <div class="step-label">Verify Email</div>
        </div>
        <div class="step-line done"></div>
        <div class="step active">
            <div class="step-circle">2</div>
            <div class="step-label">Identity & Terms</div>
        </div>
        <div class="step-line"></div>
        <div class="step inactive">
            <div class="step-circle">3</div>
            <div class="step-label">Assignment</div>
        </div>
    </div>
    <div class="box">
        <h2>Identity & Terms</h2>
        <p>Please allow location access, draw your signature, and accept the terms before starting.</p>

        <div style="margin-bottom:16px;">
            <button type="button" id="capLocBtn" onclick="captureLocation()" style="background:#f8fafc;border:2px solid #cbd5e1;border-radius:8px;padding:12px;width:100%;font-family:inherit;font-weight:700;font-size:13px;color:#334155;cursor:pointer;transition:.2s;"><i class="fas fa-map-marker-alt mr-2" style="color:#ef4444;"></i> Click to Capture Location</button>
            <div id="locStatus" class="loc-status" style="display:none;margin-top:10px;width:100%;box-sizing:border-box;"></div>
        </div>

        <div style="text-align:left;margin-bottom:8px;font-weight:700;font-size:13px;color:#0f2557;">Draw your signature below:</div>
        <canvas id="sigCanvas" class="sig-canvas"></canvas>
        <div style="text-align:right;margin-top:6px;margin-bottom:20px;">
            <button onclick="clearCanvas()" style="background:none;border:none;color:#ef4444;font-size:12px;font-weight:700;cursor:pointer;"><i class="fas fa-eraser"></i> Clear</button>
        </div>

        <div class="tnc-box">
            <h4><i class="fas fa-file-contract" style="margin-right:6px;color:#1a3fc4;"></i>Terms & Conditions</h4>
            <ul>
                <li>I confirm that I am the intended candidate for this assignment and I am attempting it personally without any assistance from another individual, AI tool, or any external resource.</li>
                <li>I understand that all my answers must be my own original responses and any form of plagiarism, copying, or use of unauthorized aids is strictly prohibited.</li>
                <li>I acknowledge that my location, digital signature, and activity during this session are being recorded for verification purposes.</li>
                <li>I understand that switching browser tabs or windows during this assignment is not permitted and repeated violations will result in my session being locked and flagged to HR.</li>
                <li>I accept that if any discrepancy, malpractice, or dishonesty is discovered at any stage — during or after the evaluation — my candidature will be immediately disqualified and removed from the recruitment process without any further notice.</li>
                <li>I agree that the decision of Abra Logistic regarding any integrity violation shall be final and binding.</li>
            </ul>
        </div>

        <label class="tnc-check">
            <input type="checkbox" id="tncCheck" onchange="checkReady()">
            I have read and I agree to the Terms & Conditions stated above.
        </label>

        <button id="startBtn" class="btn-sub" onclick="submitVerification()" disabled>Start Assignment <i class="fas fa-arrow-right" style="margin-left:6px;"></i></button>
    </div>
    
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
    var locString = "";
    var locReady = false;
    
    function captureLocation() {
        var btn = document.getElementById("capLocBtn");
        var status = document.getElementById("locStatus");
        
        btn.innerHTML = "<i class=\'fas fa-spinner fa-spin mr-2\'></i> Requesting Access...";
        btn.disabled = true;
        status.style.display = "none";
        
        if ("geolocation" in navigator) {
            navigator.geolocation.getCurrentPosition(function(position) {
                var lat = position.coords.latitude;
                var lon = position.coords.longitude;
                var rawCoords = lat + "," + lon;
                
                btn.innerHTML = "<i class=\'fas fa-spinner fa-spin mr-2\'></i> Fetching Address...";
                
                fetch("https://nominatim.openstreetmap.org/reverse?format=json&lat=" + lat + "&lon=" + lon)
                    .then(r => r.json())
                    .then(data => {
                        var addr = data.display_name ? data.display_name : "Address not found";
                        locString = addr + "|" + rawCoords;
                        finalizeLocation(true, "Location captured successfully");
                    })
                    .catch(e => {
                        locString = "Address fetch failed|" + rawCoords;
                        finalizeLocation(true, "Location captured (coordinates only)");
                    });
                
            }, function(error) {
                locString = "Denied/Error|";
                finalizeLocation(false, "Location access denied or unavailable");
            });
        } else {
            locString = "Unsupported|";
            finalizeLocation(false, "Location unsupported by browser");
        }
    }
    
    function finalizeLocation(success, msg) {
        var btn = document.getElementById("capLocBtn");
        var status = document.getElementById("locStatus");
        
        btn.style.display = "none";
        status.style.display = "inline-block";
        
        if (success) {
            status.innerHTML = "<i class=\'fas fa-check-circle\'></i> " + msg;
            status.style.color = "#065f46";
            status.style.background = "#dcfce7";
        } else {
            status.innerHTML = "<i class=\'fas fa-exclamation-triangle\'></i> " + msg;
            status.style.color = "#991b1b";
            status.style.background = "#fee2e2";
        }
        locReady = true;
        checkReady();
    }
    
    // Canvas drawing
    var canvas = document.getElementById("sigCanvas");
    var ctx = canvas.getContext("2d");
    var drawing = false;
    var hasSignature = false;
    
    // Fix DPI
    function resizeCanvas() {
        var rect = canvas.getBoundingClientRect();
        canvas.width = rect.width;
        canvas.height = rect.height;
    }
    window.addEventListener("resize", resizeCanvas);
    resizeCanvas();
    
    function getMousePos(e) {
        var rect = canvas.getBoundingClientRect();
        if(e.touches) {
            return { x: e.touches[0].clientX - rect.left, y: e.touches[0].clientY - rect.top };
        }
        return { x: e.clientX - rect.left, y: e.clientY - rect.top };
    }
    
    function startDraw(e) {
        e.preventDefault(); drawing = true;
        var pos = getMousePos(e);
        ctx.beginPath(); ctx.moveTo(pos.x, pos.y);
    }
    
    function draw(e) {
        e.preventDefault(); if (!drawing) return;
        var pos = getMousePos(e);
        ctx.lineTo(pos.x, pos.y);
        ctx.strokeStyle = "#0f2557"; ctx.lineWidth = 3; ctx.lineCap = "round"; ctx.stroke();
        hasSignature = true; checkReady();
    }
    
    function stopDraw(e) { e.preventDefault(); drawing = false; }
    
    canvas.addEventListener("mousedown", startDraw);
    canvas.addEventListener("mousemove", draw);
    canvas.addEventListener("mouseup", stopDraw);
    canvas.addEventListener("mouseout", stopDraw);
    
    canvas.addEventListener("touchstart", startDraw, {passive:false});
    canvas.addEventListener("touchmove", draw, {passive:false});
    canvas.addEventListener("touchend", stopDraw, {passive:false});
    
    function clearCanvas() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        hasSignature = false; checkReady();
    }
    
    function checkReady() {
        var btn = document.getElementById("startBtn");
        var tncChecked = document.getElementById("tncCheck") ? document.getElementById("tncCheck").checked : true;
        if (locReady && hasSignature && tncChecked) { btn.disabled = false; } else { btn.disabled = true; }
    }
    
    function submitVerification() {
        if (!hasSignature) { alert("Please draw your signature."); return; }
        var btn = document.getElementById("startBtn");
        btn.innerHTML = "<i class=\'fas fa-spinner fa-spin mr-1\'></i> Saving..."; btn.disabled = true;
        
        var sigData = canvas.toDataURL("image/png");
        
        $.post(window.location.href, {
            ajax_save_verification: 1,
            token: "' . $token_safe . '",
            location: locString,
            signature: sigData
        }, function(res) {
            if (res.success) { location.reload(); } else { alert("Failed to save verification."); btn.innerHTML = "Start Assignment <i class=\'fas fa-arrow-right\'></i>"; btn.disabled = false; }
        }, "json");
    }
    </script>
</body>
</html>';
        exit;
    }

// --- FETCH QUESTIONS ---
$dept_id    = intval($link['department_id']);
$pos_id     = intval($link['position_id']);
$round_num  = intval($link['round_number']);
$questions  = [];
$q_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_questions WHERE department_id=$dept_id AND position_id=$pos_id AND round_number=$round_num AND is_active=1 ORDER BY id ASC");
while ($q = mysqli_fetch_assoc($q_res)) $questions[] = $q;

if (empty($questions)) { die(renderError('No Questions', 'No questions have been configured for this assignment round.')); }

// --- HANDLE SUBMISSION ---
$submit_success = false;
$submit_error   = '';

if (isset($_POST['submit_assignment'])) {
    // Re-validate token on submit
    $link_check = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_assignment_links WHERE token='$token_safe' LIMIT 1"));
    if (!$link_check || $link_check['status'] === 'submitted') {
        $submit_error = 'This assignment has already been submitted or the link is invalid.';
    } else {
        $total_obtained = 0;
        $total_possible = 0;
        $answers        = [];

        foreach ($questions as $q) {
            $qid     = $q['id'];
            $ans     = isset($_POST["answer_$qid"]) ? trim($_POST["answer_$qid"]) : '';
            $file_path = null;
            if ($q['input_type'] === 'file_upload' && isset($_FILES["answer_$qid"])) {
                $file_field = $_FILES["answer_$qid"];
                $saved_paths = [];
                $allowed = ['pdf','doc','docx','ppt','pptx','zip','rar','mp4','png','jpg','jpeg','txt','csv'];
                if (!is_dir('uploads/hr_assignment_files')) mkdir('uploads/hr_assignment_files', 0777, true);

                // $file_field['name'] is an array since the input uses answer_ID[]
                $file_count = is_array($file_field['name']) ? count($file_field['name']) : 0;
                for ($i = 0; $i < $file_count; $i++) {
                    if ($file_field['error'][$i] !== UPLOAD_ERR_OK) continue;
                    $orig_name = basename($file_field['name'][$i]);
                    $ext = strtolower(pathinfo($orig_name, PATHINFO_EXTENSION));
                    if (!in_array($ext, $allowed)) continue;
                    $new_name = time() . '_' . rand(1000,9999) . '_' . preg_replace('/[^A-Za-z0-9.\-]/', '', $orig_name);
                    $dest = 'uploads/hr_assignment_files/' . $new_name;
                    if (move_uploaded_file($file_field['tmp_name'][$i], $dest)) {
                        $saved_paths[] = $dest;
                    }
                }
                if (!empty($saved_paths)) {
                    $file_path = json_encode($saved_paths);
                }
            }
            $total_possible += intval($q['marks']);
            // Candidate answers are stored with 0 marks — HR will mark them later
            $answers[] = ['question_id' => $qid, 'answer_text' => $ans, 'file_path' => $file_path, 'marks_obtained' => 0];
        }

        // Insert evaluation record with status 'Pending HR Review'
        $evaluator  = mysqli_real_escape_string($dbConn, $candidate['candidate_name']);
        $hr_notes   = mysqli_real_escape_string($dbConn, 'Assignment submitted by candidate. Pending HR marking.');
        $ins = mysqli_query($dbConn, "INSERT INTO hr_screening_evaluations 
            (screening_id, round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, hr_notes, status) 
            VALUES ({$link['candidate_id']}, $round_num, '$evaluator', 0, $total_possible, 0, 'Pending HR Review', '$hr_notes', 'Pending')");

        if ($ins) {
            $eval_id = mysqli_insert_id($dbConn);
            foreach ($answers as $ans) {
                $safe_ans = mysqli_real_escape_string($dbConn, $ans['answer_text']);
                $safe_file = $ans['file_path'] ? "'" . mysqli_real_escape_string($dbConn, $ans['file_path']) . "'" : "NULL";
                mysqli_query($dbConn, "INSERT INTO hr_screening_evaluation_answers (evaluation_id, question_id, answer_text, file_path, marks_obtained) VALUES ($eval_id, {$ans['question_id']}, '$safe_ans', $safe_file, 0)");
            }
            // Mark link as submitted
            mysqli_query($dbConn, "UPDATE hr_assignment_links SET status='submitted' WHERE token='$token_safe'");

            // ── Auto-raise a ticket to notify the HR person who added this candidate ──
            $screener_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT screened_by FROM hr_screenings WHERE id=" . intval($link['candidate_id']) . " LIMIT 1"));
            $screened_by  = intval($screener_row['screened_by'] ?? 0);

            if ($screened_by > 0) {
                $t_subject = "Assignment Submitted — " . $candidate['candidate_name'] . " (Round $round_num)";
                $t_message = "Candidate " . $candidate['candidate_name'] . " has submitted their Round $round_num assignment for the " .
                             $candidate['position_applied'] . " position (" . $candidate['department'] . " department).\n\n" .
                             "Please review and mark the submission in HR Screening.";
                $t_name     = mysqli_real_escape_string($dbConn, $candidate['candidate_name']);
                $t_subject  = mysqli_real_escape_string($dbConn, $t_subject);
                $t_message  = mysqli_real_escape_string($dbConn, $t_message);
                $t_priority = 'medium';
                $t_timeline = 1440; // 24 hours
                $t_deadline = date('Y-m-d H:i:s', strtotime('+1440 minutes'));

                $tk_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT MAX(id) AS max_id FROM tickets"));
                $tk_next = ($tk_row['max_id'] ?? 0) + 1;
                $ticket_number = 'TICKET' . date('Y') . str_pad($tk_next, 4, '0', STR_PAD_LEFT);

                mysqli_query($dbConn, "INSERT INTO tickets
                    (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
                    VALUES
                    ('$ticket_number', '$t_name', '$t_subject', '$t_message', 'open', '$t_priority', $t_timeline, '$t_deadline', '', NOW(), NOW(), $screened_by, $screened_by)");
            }
            // ── End auto-ticket ──

            // Show success immediately — redirect to prevent resubmit on refresh
            echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Submitted</title>
            <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;700;800&display=swap" rel="stylesheet">
            <style>body{font-family:\'Plus Jakarta Sans\',sans-serif;background:#f0f4f9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}
            .box{background:#fff;border-radius:16px;padding:50px 40px;text-align:center;max-width:480px;box-shadow:0 10px 40px rgba(0,0,0,0.1);}
            .icon{font-size:60px;margin-bottom:16px;} h2{color:#0f2557;font-weight:800;margin-bottom:10px;} p{color:#64748b;line-height:1.8;font-size:14px;}</style></head>
            <body><div class="box">
            <div class="icon">✅</div>
            <h2>Assignment Submitted!</h2>
            <p>Thank you, <strong>' . htmlspecialchars($candidate['candidate_name']) . '</strong>!<br>
            Your assignment has been submitted successfully.<br>HR will review your answers and get back to you.</p>
            </div></body></html>';
            exit;
        } else {
            $submit_error = 'Database error. Please try again.';
        }
    }
}

// --- HELPER: ERROR PAGE ---
function renderError($title, $message) {
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' . htmlspecialchars($title) . '</title>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;700;800&display=swap" rel="stylesheet">
    <style>body{font-family:\'Plus Jakarta Sans\',sans-serif;background:#f0f4f9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}
    .box{background:#fff;border-radius:16px;padding:40px;text-align:center;max-width:420px;box-shadow:0 10px 40px rgba(0,0,0,0.1);}
    .icon{font-size:48px;margin-bottom:16px;} h2{color:#0f2557;font-weight:800;} p{color:#64748b;}</style></head>
    <body><div class="box"><div class="icon">⚠️</div><h2>' . htmlspecialchars($title) . '</h2><p>' . htmlspecialchars($message) . '</p></div></body></html>';
}


?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Assignment — <?php echo htmlspecialchars($candidate['candidate_name']); ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Plus Jakarta Sans',sans-serif; background:#f0f4f9; min-height:100vh; }
.hdr { background:linear-gradient(135deg,#0f2557,#1a3fc4); padding:18px 28px; display:flex; justify-content:space-between; align-items:center; }
.hdr h1 { color:#fff; font-size:1.2rem; font-weight:800; }
.hdr .sub { color:rgba(255,255,255,0.7); font-size:12px; margin-top:2px; }
.wrap { max-width:780px; margin:30px auto; padding:0 20px 60px; }
.candidate-card { background:#fff; border-radius:14px; padding:20px 24px; border:1px solid #e0e7ff; margin-bottom:24px; display:flex; align-items:center; gap:16px; box-shadow:0 2px 10px rgba(0,0,0,0.05); }
.cav { width:52px; height:52px; border-radius:13px; background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; display:flex; align-items:center; justify-content:center; font-weight:800; font-size:20px; flex-shrink:0; }
.candidate-card h4 { font-weight:800; color:#0f2557; margin-bottom:3px; }
.candidate-card p { font-size:13px; color:#64748b; margin:0; }
.security-bar { background:#fff7ed; border:2px solid #fcd34d; border-radius:10px; padding:12px 18px; margin-bottom:20px; display:flex; align-items:center; gap:10px; font-size:13px; font-weight:700; color:#92400e; }
.q-card { background:#fff; border-radius:12px; border:1px solid #e2e8f0; padding:22px; margin-bottom:16px; box-shadow:0 2px 6px rgba(0,0,0,0.04); }
.q-num { font-size:11px; font-weight:800; color:#1a3fc4; text-transform:uppercase; margin-bottom:6px; }
.q-text { font-weight:700; color:#0f2557; font-size:15px; margin-bottom:14px; }
.q-marks { font-size:11px; font-weight:700; color:#64748b; margin-bottom:10px; }
textarea.fc, input.fc, select.fc { border:2px solid #e0e7ff; border-radius:9px; padding:10px 13px; font-size:13px; font-family:inherit; font-weight:600; width:100%; transition:.2s; background:#fff; color:#0f172a; }
textarea.fc { height:100px; resize:vertical; }
textarea.fc:focus, input.fc:focus, select.fc:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.08); }
.btn-sub { width:100%; padding:15px; border:none; border-radius:11px; font-family:inherit; font-weight:800; font-size:15px; cursor:pointer; background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; margin-top:10px; }
.btn-sub:hover { transform:translateY(-2px); box-shadow:0 7px 20px rgba(26,63,196,.3); }
.success-box { background:#fff; border-radius:16px; padding:50px 30px; text-align:center; box-shadow:0 10px 40px rgba(0,0,0,0.08); }
.success-box .icon { font-size:56px; margin-bottom:16px; }
.success-box h2 { color:#0f2557; font-weight:800; margin-bottom:8px; }
.success-box p { color:#64748b; font-size:14px; }
.tab-warn { position:fixed; inset:0; background:rgba(0,0,0,0.85); z-index:9999; display:none; align-items:center; justify-content:center; flex-direction:column; }
.tab-warn h2 { color:#fff; font-weight:800; font-size:24px; margin-bottom:10px; }
.tab-warn p { color:rgba(255,255,255,0.8); font-size:14px; margin-bottom:20px; }
.tab-warn button { padding:12px 28px; border:none; border-radius:10px; background:#1a3fc4; color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer; }
.warn-count { color:#f59e0b; font-weight:800; font-size:18px; margin-bottom:10px; }
</style>
</head>
<body>

<!-- Tab Switch Warning Overlay -->
<div class="tab-warn" id="tabWarnOverlay">
    <div style="text-align:center;padding:30px;">
        <div style="font-size:56px;margin-bottom:16px;">⚠️</div>
        <h2>Tab Switching Detected!</h2>
        <div class="warn-count" id="warnCountText"></div>
        <p>You must not switch tabs or windows during this assignment.<br>This activity is being monitored.</p>
        <button onclick="dismissTabWarning()"><i class="fas fa-arrow-left" style="margin-right:6px;"></i> Return to Assignment</button>
    </div>
</div>

<div class="hdr">
    <div>
        <h1><i class="fas fa-file-alt mr-2"></i>Secure Assignment</h1>
        <div class="sub">Round <?php echo $round_num; ?> &middot; Complete all questions carefully</div>
    </div>
    <div style="color:rgba(255,255,255,0.8);font-size:13px;font-weight:700;">
        <i class="fas fa-shield-alt mr-1"></i> Secure Mode Active
    </div>
</div>

<div class="wrap">

<?php if ($submit_success): ?>
<div class="success-box">
    <div class="icon">✅</div>
    <h2>Assignment Submitted!</h2>
    <p>Thank you, <strong><?php echo htmlspecialchars($candidate['candidate_name']); ?></strong>!<br>
    Your assignment has been submitted successfully.<br>HR will review your answers and get back to you.</p>
</div>

<?php elseif ($submit_error): ?>
<div style="background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:14px 18px;border-radius:11px;font-weight:700;margin-bottom:18px;">
    <i class="fas fa-exclamation-circle mr-2"></i><?php echo htmlspecialchars($submit_error); ?>
</div>

<?php else: ?>

<div class="candidate-card">
    <?php $init = strtoupper(substr($candidate['candidate_name'],0,1)); ?>
    <div class="cav"><?php echo $init; ?></div>
    <div>
        <h4><?php echo htmlspecialchars($candidate['candidate_name']); ?></h4>
        <p><i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($candidate['position_applied']); ?> &nbsp;|&nbsp; <i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($candidate['department']); ?></p>
        <p style="margin-top:4px;"><i class="fas fa-layer-group mr-1"></i> Round <?php echo $round_num; ?> Assignment &nbsp;|&nbsp; <?php echo count($questions); ?> Questions</p>
    </div>
</div>

<div class="security-bar">
    <i class="fas fa-lock fa-lg"></i>
    <div>
        <div>Secure Assignment Mode — Copy, paste and tab switching are disabled.</div>
        <div style="font-size:11px;font-weight:600;color:#b45309;margin-top:2px;">Type your answers manually. Do not switch browser tabs or windows.</div>
    </div>
</div>

<form method="POST" id="assignmentForm" autocomplete="off" enctype="multipart/form-data">
    <input type="hidden" name="submit_assignment" value="1">

    <?php foreach ($questions as $idx => $q): ?>
    <div class="q-card">
        <div class="q-num">Question <?php echo ($idx+1); ?> of <?php echo count($questions); ?></div>
        <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
        <div class="q-marks"><i class="fas fa-star" style="color:#f59e0b;"></i> <?php echo $q['marks']; ?> marks</div>
        <?php if (isset($_GET['debug'])): ?>
        <div style="font-size:10px;color:#ef4444;font-family:monospace;background:#fef2f2;padding:4px 8px;border-radius:4px;margin-bottom:8px;">DEBUG: input_type="<?php echo htmlspecialchars($q['input_type']); ?>" (length: <?php echo strlen($q['input_type']); ?>)</div>
        <?php endif; ?>

        <?php if ($q['input_type'] == 'select' && !empty($q['options_json'])): ?>
            <?php $opts = json_decode($q['options_json'], true) ?: []; ?>
            <select name="answer_<?php echo $q['id']; ?>" class="fc" required>
                <option value="">-- Select your answer --</option>
                <?php foreach ($opts as $opt): ?>
                <option value="<?php echo htmlspecialchars($opt); ?>"><?php echo htmlspecialchars($opt); ?></option>
                <?php endforeach; ?>
            </select>
        <?php elseif ($q['input_type'] == 'textarea'): ?>
            <textarea name="answer_<?php echo $q['id']; ?>" class="fc" required placeholder="Type your answer here..."></textarea>
        <?php elseif ($q['input_type'] == 'number'): ?>
            <input type="number" name="answer_<?php echo $q['id']; ?>" class="fc" required placeholder="Enter a number...">
        <?php elseif ($q['input_type'] == 'file_upload'): ?>
            <input type="file" name="answer_<?php echo $q['id']; ?>[]" class="fc" required multiple accept=".pdf,.doc,.docx,.ppt,.pptx,.zip,.rar,.mp4,.png,.jpg,.jpeg,.txt,.csv" style="padding:7px 10px;">
            <div style="font-size:11px;color:#64748b;margin-top:4px;">Allowed: PDF, DOC/DOCX, PPT/PPTX, ZIP, MP4, Images. You can select multiple files. Max 10MB each.</div>
        <?php else: ?>
            <input type="text" name="answer_<?php echo $q['id']; ?>" class="fc" required placeholder="Type your answer here...">
        <?php endif; ?>
    </div>
    <?php endforeach; ?>

    <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:12px;padding:18px;margin-bottom:16px;">
        <div style="font-weight:800;color:#0f2557;margin-bottom:6px;"><i class="fas fa-info-circle mr-1"></i> Before you submit:</div>
        <ul style="font-size:13px;color:#64748b;padding-left:18px;line-height:1.9;">
            <li>Review all your answers carefully</li>
            <li>You cannot edit or resubmit after submission</li>
            <li>Make sure you have answered all questions</li>
        </ul>
    </div>

    <button type="submit" class="btn-sub" onclick="return confirmSubmit()">
        <i class="fas fa-paper-plane mr-2"></i>Submit Assignment
    </button>
</form>

<?php endif; ?>
</div>

<script>
// ===== ANTI-COPY / ANTI-CHEAT PROTECTION =====
var tabSwitchCount = 0;
var MAX_WARNINGS   = 3;

// Block right-click
document.addEventListener('contextmenu', function(e) { e.preventDefault(); });

// Block keyboard shortcuts
document.addEventListener('keydown', function(e) {
    // Block Ctrl+C, Ctrl+V, Ctrl+A, Ctrl+X, Ctrl+U, F12, Ctrl+Shift+I
    if (e.ctrlKey && ['c','v','a','x','u','s'].includes(e.key.toLowerCase())) {
        e.preventDefault(); return false;
    }
    if (e.key === 'F12' || (e.ctrlKey && e.shiftKey && ['i','j','c'].includes(e.key.toLowerCase()))) {
        e.preventDefault(); return false;
    }
});

// Block copy/paste/cut events on inputs
document.addEventListener('copy',  function(e) { e.preventDefault(); });
document.addEventListener('paste', function(e) { e.preventDefault(); });
document.addEventListener('cut',   function(e) { e.preventDefault(); });

// Allow paste only on form fields (so they can type normally) — block copy/cut only
document.querySelectorAll('textarea, input[type="text"], input[type="number"]').forEach(function(el) {
    el.addEventListener('paste', function(e) { e.preventDefault(); });
    el.addEventListener('copy',  function(e) { e.preventDefault(); });
    el.addEventListener('cut',   function(e) { e.preventDefault(); });
});

// Block drag-drop into inputs
document.addEventListener('drop', function(e) { e.preventDefault(); });
document.addEventListener('dragover', function(e) { e.preventDefault(); });

// Tab switch detection
document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
        tabSwitchCount++;
        showTabWarning();
    }
});



function showTabWarning() {
    var overlay = document.getElementById('tabWarnOverlay');
    var countEl = document.getElementById('warnCountText');
    if (!overlay) return;

    // Save attempt count to server
    var xhr = new XMLHttpRequest();
    xhr.open('POST', window.location.href, true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.send('ajax_log_tab_switch=1&token=<?php echo htmlspecialchars($token); ?>&count=' + tabSwitchCount);

    if (tabSwitchCount >= MAX_WARNINGS) {
        // Auto flag and lock
        countEl.innerHTML = '⛔ Maximum warnings reached! Your assignment has been LOCKED and flagged to HR.';
        overlay.style.display = 'flex';

        // Disable all form inputs
        document.querySelectorAll('textarea, input, select, button[type="submit"]').forEach(function(el) {
            el.disabled = true;
        });

        // Hide return button, show locked message
        var btn = overlay.querySelector('button');
        if (btn) btn.style.display = 'none';

        overlay.innerHTML = '<div style="text-align:center;padding:30px;">' +
            '<div style="font-size:56px;margin-bottom:16px;">🔒</div>' +
            '<h2 style="color:#fff;font-weight:800;font-size:22px;margin-bottom:10px;">Assignment Locked</h2>' +
            '<p style="color:rgba(255,255,255,0.85);font-size:14px;margin-bottom:20px;">You have switched tabs 3 times.<br>Your session has been flagged and sent to HR.<br>You can no longer submit this assignment.</p>' +
            '<div style="background:#ef4444;color:#fff;padding:12px 24px;border-radius:10px;font-weight:800;font-size:14px;display:inline-block;">🚨 Session Flagged — HR Notified</div>' +
            '</div>';

        // Auto-submit flag to server
        var flagXhr = new XMLHttpRequest();
        flagXhr.open('POST', window.location.href, true);
        flagXhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
        flagXhr.send('ajax_flag_session=1&token=<?php echo htmlspecialchars($token); ?>');
        return;
    }

    overlay.style.display = 'flex';
    countEl.innerHTML = '⚠️ Warning ' + tabSwitchCount + ' of ' + MAX_WARNINGS + ' — One more and your session will be locked!';
}

function dismissTabWarning() {
    var overlay = document.getElementById('tabWarnOverlay');
    if (overlay) overlay.style.display = 'none';
}

function confirmSubmit() {
    return confirm('Are you sure you want to submit your assignment? You cannot make changes after submission.');
}

// Disable text selection via CSS
document.body.style.userSelect = 'none';
document.body.style.webkitUserSelect = 'none';

// But allow typing in inputs
document.querySelectorAll('textarea, input, select').forEach(function(el) {
    el.style.userSelect = 'text';
    el.style.webkitUserSelect = 'text';
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