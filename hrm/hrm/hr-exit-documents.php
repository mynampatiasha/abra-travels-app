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

$chk_cc = mysqli_query($con, "SHOW COLUMNS FROM hr_exit_documents LIKE 'custom_content'");
if ($chk_cc && mysqli_num_rows($chk_cc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_exit_documents ADD COLUMN custom_content LONGTEXT DEFAULT NULL");
}

if (!isset($_GET['token'])) {
    die("Invalid access token.");
}

$token = mysqli_real_escape_string($con, $_GET['token']);
$r = mysqli_query($con, "SELECT d.*, r.employee_id, r.final_last_working_day, r.exit_type FROM hr_exit_documents d JOIN hr_exit_requests r ON r.id = d.exit_id WHERE d.token='$token' LIMIT 1");
$docRow = $r ? mysqli_fetch_assoc($r) : null;

if (!$docRow) {
    die("Document not found or has been removed.");
}

$employee_id = intval($docRow['employee_id']);
$emp_res = mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$employee_id LIMIT 1");
$empRow = $emp_res ? mysqli_fetch_assoc($emp_res) : null;

if (!$empRow) die("Employee record not found.");

// Fetch company settings
$companySettings = ['company_name' => '', 'company_address' => '', 'company_logo' => '', 'company_signature' => '', 'signatory_name' => '', 'signatory_designation' => '', 'company_phone' => '', 'company_email' => '', 'company_website' => ''];
if (!empty($empRow['company_name'])) {
    $cname_e = mysqli_real_escape_string($con, $empRow['company_name']);
    $hc_row = mysqli_fetch_assoc(mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$cname_e')) LIMIT 1"));
    if ($hc_row) {
        $r2 = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_id=" . intval($hc_row['id']) . " LIMIT 1"));
        if ($r2) {
            $companySettings = $r2;
            $companySettings['company_name'] = $hc_row['company_name'];
            if (empty($companySettings['company_signature']) && !empty($companySettings['signature_path'])) {
                $companySettings['company_signature'] = $companySettings['signature_path'];
            }
        }
    }
}

// Format Dates
$joiningDate = isset($empRow['hire_date']) && $empRow['hire_date'] ? date('F j, Y', strtotime($empRow['hire_date'])) : '[Joining Date]';
$lastWorkingDay = $docRow['final_last_working_day'] ? date('F j, Y', strtotime($docRow['final_last_working_day'])) : '[Last Working Day]';
$today = date('d/m/Y');

$docTitle = ucwords(str_replace('_', ' ', $docRow['doc_type']));

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title><?= htmlspecialchars($docTitle) ?> — <?= htmlspecialchars($empRow['name']) ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Calibri',Georgia,serif;background:#f0f4f8;padding:20px;}
    .offer-card{max-width:800px;min-height:1000px;margin:0 auto;background:#fff;box-shadow:0 4px 30px rgba(0,0,0,0.1);position:relative;overflow:hidden;padding-bottom:100px;}
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;position:absolute;bottom:0;left:0;right:0;z-index:1;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:center;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;position:relative;z-index:2;}
    .letter-header-left{font-size:19px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:0;margin-left:30px;}
    .letter-header-left span{display:flex;align-items:center;gap:10px;}
    .letter-header-left i{width:26px;text-align:center;font-size:26px;}
    .letter-header-right{text-align:right;}
    .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
    .letter-company-name-right{font-size:14px;font-weight:900;color:#0f2557;margin-top:4px;text-transform:uppercase;}
    .letter-company-tagline{font-size:11px;color:#0f2557;font-weight:800;text-transform:uppercase;letter-spacing:0.5px;}
    .letter-body{padding:32px 40px 40px 40px;font-family:Arial,sans-serif;font-size:14px;color:#1a202c;line-height:1.6;position:relative;z-index:2;}
    .letter-body p{margin-bottom:10px;}
    .letter-body ul{margin:6px 0 10px 22px;}
    .letter-body ul li{margin-bottom:3px;}
    .letter-from{margin-bottom:16px;}
    .letter-from strong{display:block;font-size:14px;}
    .letter-title{text-align:center;font-weight:700;text-decoration:underline;margin:18px 0 14px 0;font-size:13.5px;}
    .letter-sig-area{display:flex;justify-content:space-between;margin-top:30px;font-size:13px;}
    .letter-sig-box{text-align:center;width:200px;}
    .letter-sig-line{border-top:1px solid #334155;margin-top:50px;padding-top:6px;font-size:12px;font-weight:700;}
    .print-only-spacer{display:none;}
    @media print{
        @page { margin: 0; }
        .print-only-spacer{display:table-header-group !important;}
        .print-only-spacer-foot{display:table-footer-group !important;}
        body{background:#fff;padding:0;}
        .offer-card{box-shadow:none;overflow:visible;padding-bottom:0;}
        .no-print{display:none!important;}
        * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
        .letter-wave-top {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            right: 0 !important;
            z-index: 10 !important;
        }
        .letter-header {
            position: fixed !important;
            top: 70px !important;
            left: 0 !important;
            right: 0 !important;
            z-index: 10 !important;
        }
        .letter-wave-bottom {
            position: fixed !important;
            bottom: 0 !important;
            left: 0 !important;
            right: 0 !important;
        }
        .letter-body {
            margin-top: 30px !important;
        }
    }
    @media(max-width:600px){.letter-header{flex-direction:column;gap:10px;padding:16px;} .letter-body{padding:20px;} .letter-sig-area{flex-direction:column;gap:20px;}}
</style>
</head>
<body>
<div style="max-width: 800px; margin: 0 auto 20px auto; display: flex; justify-content: flex-end;" class="no-print">
    <button type="button" onclick="window.print()" style="padding: 10px 20px; background: #0f2557; color: white; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; display: flex; align-items: center; gap: 8px;">🖨️ Print / Download PDF</button>
</div>

<div class="offer-card">
    <!-- Letterhead Header -->
    <div class="letter-wave-top">
        <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
            <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
        </svg>
    </div>
    <div class="letter-header">
        <div class="letter-header-left">
            <?php if(!empty($companySettings['company_phone'])): ?><span><i class="fas fa-phone-alt"></i> <?= htmlspecialchars($companySettings['company_phone']) ?></span><?php endif; ?>
            <?php if(!empty($companySettings['company_email'])): ?><span><i class="fas fa-envelope"></i> <?= htmlspecialchars($companySettings['company_email']) ?></span><?php endif; ?>
            <?php if(!empty($companySettings['company_website'])): ?><span><i class="fas fa-globe"></i> <?= htmlspecialchars($companySettings['company_website']) ?></span><?php endif; ?>
        </div>
        <div class="letter-header-right">
            <?php if (!empty($companySettings['company_logo'])): ?>
                <img src="<?= htmlspecialchars($companySettings['company_logo']) ?>" alt="Logo"/>
            <?php endif; ?>
        </div>
    </div>

    <table style="width:100%; border-collapse:collapse; border:none;">
    <thead class="print-only-spacer"><tr><td style="height: 245px; border:none;"></td></tr></thead>
    <tbody><tr><td style="padding: 0; border:none;">
    <!-- Letter Body -->
    <div class="letter-body">
        <!-- From -->
        <div style="margin-bottom: 30px; line-height: 1.6;">
            <div style="font-weight:bold; margin-bottom: 6px;">From</div>
            <div style="font-weight:bold; font-size: 16px;"><?= htmlspecialchars($companySettings['company_name'] ?: 'Company Name') ?></div>
            <?php if (!empty($companySettings['company_address'])): ?>
            <div><strong>Registered Office: <?= nl2br(htmlspecialchars(trim($companySettings['company_address']))) ?></strong></div>
            <?php endif; ?>
            <div><strong>Email: <?= htmlspecialchars($companySettings['company_email'] ?: '') ?> | Phone: <?= htmlspecialchars($companySettings['company_phone'] ?: '') ?></strong></div>
            <div><strong>Date: <?= $today ?></strong></div>
        </div>

        <!-- To -->
        <div style="margin-bottom: 25px; line-height: 1.6;">
            <strong>To,</strong><br>
            <strong><?= htmlspecialchars($empRow['name']) ?></strong><br>
            <?php if(!empty($empRow['address'])): ?>
            <strong><?= nl2br(htmlspecialchars(trim($empRow['address']))) ?></strong><br>
            <?php endif; ?>
            <?php if(!empty($empRow['phone'])): ?>
            <strong>Phone: <?= htmlspecialchars($empRow['phone']) ?></strong><br>
            <?php endif; ?>
            <strong>Employee Code: <?= htmlspecialchars($empRow['employee_id'] ?? 'N/A') ?></strong>
        </div>

        <!-- Document Title -->
        <div class="letter-title"><?= htmlspecialchars($docTitle) ?></div>

        <!-- Document Content -->
        <?php if (!empty($docRow['custom_content'])): ?>
            <?= $docRow['custom_content'] ?>
        <?php else: ?>
            <?= renderExitDocumentBody($con, $docRow, $empRow, $companySettings, $joiningDate, $lastWorkingDay) ?>
        <?php endif; ?>

        <!-- Signature -->
        <div class="letter-sig-area">
            <div class="letter-sig-box">
                <div style="height:200px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                    <?php if (!empty($companySettings['company_signature'])): ?>
                    <img src="<?= htmlspecialchars($companySettings['company_signature']) ?>" alt="Company Signature" style="max-height:200px; max-width:230px;">
                    <?php endif; ?>
                </div>
                <div class="letter-sig-line" style="margin-top:0;">
                    For <?= htmlspecialchars($companySettings['company_name'] ?: 'Company Name') ?><br>
                    <small><strong>Name:</strong> <?= htmlspecialchars($companySettings['signatory_name'] ?: 'Authorized Signatory') ?></small><br>
                    <small style="font-weight:400;"><strong>Designation:</strong> <?= htmlspecialchars($companySettings['signatory_designation'] ?: '') ?></small>
                </div>
            </div>
            <?php if (!empty($docRow['requires_signature'])): ?>
            <div class="letter-sig-box">
                <div style="height:200px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                    <?php if (!empty($docRow['employee_signature_data'])): ?>
                    <img src="<?= htmlspecialchars($docRow['employee_signature_data']) ?>" alt="Employee Signature" style="max-height:150px; max-width:230px;">
                    <?php endif; ?>
                </div>
                <div class="letter-sig-line" style="margin-top:0;">
                    Employee Signature<br>
                    <small><strong>Name:</strong> <?= htmlspecialchars($empRow['name'] ?? '') ?></small><br>
                    <?php if (!empty($docRow['employee_signed_at'])): ?>
                    <small style="font-weight:400;"><strong>Signed on:</strong> <?= date('d M Y', strtotime($docRow['employee_signed_at'])) ?></small>
                    <?php endif; ?>
                </div>
            </div>
            <?php endif; ?>
        </div>
    </div>
    </td></tr></tbody>
    <tfoot class="print-only-spacer-foot"><tr><td style="height: 100px; border:none;"></td></tr></tfoot>
    </table>
    <div class="letter-wave-bottom">
        <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
            <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
        </svg>
    </div>
</div>
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
