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

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

isUser(); // Standard auth check
$template_html = isset($_POST['preview_html']) ? $_POST['preview_html'] : '';
if (empty($template_html)) {
    die("No template HTML provided for preview.");
}

// Replace placeholders with dummy data for preview
$preview_html = str_replace('[EMPLOYEE_NAME]', '<strong>John Doe</strong>', $template_html);
$preview_html = str_replace('[COMPANY_NAME]', '<strong>Acme Corp</strong>', $preview_html);
$preview_html = str_replace('[JOINING_DATE]', '<strong>January 1, 2020</strong>', $preview_html);
$preview_html = str_replace('[LAST_WORKING_DAY]', '<strong>December 31, 2026</strong>', $preview_html);
$preview_html = str_replace('[DESIGNATION]', '<strong>Software Engineer</strong>', $preview_html);
$preview_html = str_replace('[DEPARTMENT]', '<strong>Engineering</strong>', $preview_html);
$preview_html = str_replace('[SETTLEMENT_TABLE]', '<table border="1" cellpadding="8" cellspacing="0" style="width:100%; border-collapse:collapse; margin-top:15px; margin-bottom:15px;"><tr style="background:#f0f4f8;"><th style="text-align:left;">Particulars</th><th style="text-align:right;">Amount (INR)</th></tr><tr><td>[Dynamic Settlement Table Will Appear Here]</td><td style="text-align:right;">0.00</td></tr></table>', $preview_html);

// Dummy company settings
$companySettings = [
    'company_name' => 'Acme Corp',
    'company_address' => '123 Fake Street, Tech City',
    'company_phone' => '1-800-ACME',
    'company_email' => 'hr@acmecorp.com',
    'company_website' => 'www.acmecorp.com',
    'company_logo' => '', // Could put a dummy logo url here if needed
    'company_signature' => '', 
    'signatory_name' => 'Jane Smith',
    'signatory_designation' => 'HR Director'
];

$today = date('d/m/Y');
$docTitle = 'TEMPLATE PREVIEW';

?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Template Preview</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Calibri',Georgia,serif;background:#f0f4f8;padding:20px;}
    .offer-card{max-width:800px;min-height:1100px;margin:0 auto;background:#fff;box-shadow:0 4px 30px rgba(0,0,0,0.1);position:relative;overflow:hidden;padding-bottom:100px;}
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;position:absolute;bottom:0;left:0;right:0;z-index:1;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:flex-start;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;position:relative;z-index:2;}
    .letter-header-left{font-size:18px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:5px;margin-left:30px;}
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
    .letter-sig-area{display:flex;justify-content:space-between;margin-top:30px;font-size:14px;page-break-inside:avoid;}
    .letter-sig-box{text-align:center;width:220px;}
    .letter-sig-line{border-top:1px solid #334155;margin-top:50px;padding-top:6px;font-size:14px;font-weight:700;}
    .print-only-spacer{display:none;}
    .print-only-spacer-foot{display:none;}
    .letter-title { text-align:center; font-size:18px; font-weight:bold; text-transform:uppercase; text-decoration:underline; margin-bottom: 24px; color:#0f2557; }
    .letter-from{margin-bottom:16px; font-weight:bold;}
    
    @media print{
        @page { margin: 0 !important; size: A4 portrait !important; }
        html, body { background: #fff !important; padding: 0 !important; margin: 0 !important; width: 210mm !important; height: auto !important; }
        .print-btn{display:none !important;}
        .print-only-spacer { display: table-header-group !important; }
        .print-only-spacer-foot { display: table-footer-group !important; }
        * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; transform: none !important; zoom: 1 !important; }
        .offer-card{box-shadow:none;margin:0;width:100%;max-width:none;min-height:auto;padding-bottom:0;overflow:visible !important;position:static !important;}
        .letter-wave-top { position: fixed !important; top: 0 !important; left: 0 !important; right: 0 !important; z-index: 10 !important; }
        .letter-header { position: fixed !important; top: 70px !important; left: 0 !important; right: 0 !important; z-index: 10 !important; }
        .letter-wave-bottom { position: fixed !important; bottom: 0 !important; left: 0 !important; right: 0 !important; z-index: 10 !important; }
        .letter-body { margin-top: 30px !important; }
        .letter-sig-area { page-break-inside: avoid !important; }
    }
</style>
</head>
<body>

<div class="print-btn" style="max-width: 800px; margin: 0 auto 20px auto; display: flex; justify-content: flex-end;">
    <button onclick="window.print()" style="padding: 12px 24px; font-size: 16px; background: #0f2557; color: white; border: none; border-radius: 8px; font-weight: bold; cursor: pointer; display: flex; align-items: center; gap: 8px;"><i class="fas fa-print"></i> Print / Save PDF</button>
</div>
<script>
if (window.self !== window.top) {
    document.querySelector('.print-btn').style.display = 'none';
}
</script>

<div class="offer-card">
    <div class="letter-wave-top">
        <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
            <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
        </svg>
    </div>
    <div class="letter-header">
        <div class="letter-header-left">
            <span><i class="fas fa-phone-alt"></i> <?= htmlspecialchars($companySettings['company_phone']) ?></span>
            <span><i class="fas fa-envelope"></i> <?= htmlspecialchars($companySettings['company_email']) ?></span>
            <span><i class="fas fa-globe"></i> <?= htmlspecialchars($companySettings['company_website']) ?></span>
        </div>
        <div class="letter-header-right">
             <div class="letter-company-name-right"><?= htmlspecialchars($companySettings['company_name']) ?></div>
        </div>
    </div>

    <table style="width:100%; border-collapse:collapse; border:none;">
        <thead class="print-only-spacer">
            <tr><td style="height: 245px; border:none;"></td></tr>
        </thead>
        <tbody>
            <tr>
                <td>
                    <div class="letter-body">
        
        <div style="background:#fef3c7;padding:10px;text-align:center;margin-bottom:20px;font-weight:bold;color:#92400e;border:1px solid #f59e0b;">
            TEMPLATE PREVIEW MODE (DUMMY DATA)
        </div>

        <div style="margin-bottom: 30px; line-height: 1.6;">
            <div style="font-weight:bold; margin-bottom: 6px;">From</div>
            <div style="font-weight:bold; font-size: 16px;"><?= htmlspecialchars($companySettings['company_name']) ?></div>
            <div><strong>Registered Office: <?= htmlspecialchars($companySettings['company_address']) ?></strong></div>
            <div><strong>Email: <?= htmlspecialchars($companySettings['company_email']) ?> | Phone: <?= htmlspecialchars($companySettings['company_phone']) ?></strong></div>
            <div><strong>Date: <?= $today ?></strong></div>
        </div>
        
        <div class="letter-title"><?= htmlspecialchars($docTitle) ?></div>
        
        <div class="letter-from">
            To,<br>
            <strong>John Doe</strong><br>
            456 Main St, Example City<br>
            Phone: 555-0123<br>
            Employee Code: EMP-1234
        </div>
        
        <!-- RENDER THE HTML HERE -->
        <?= $preview_html ?>
        
        <div class="letter-sig-area">
            <div class="letter-sig-box">
                <div style="height:70px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                    <!-- signature space -->
                </div>
                <div class="letter-sig-line" style="margin-top:0;">
                    For <?= htmlspecialchars($companySettings['company_name']) ?><br>
                    <strong>Name:</strong> <?= htmlspecialchars($companySettings['signatory_name']) ?><br>
                    <span style="font-weight:400;"><strong>Designation:</strong> <?= htmlspecialchars($companySettings['signatory_designation']) ?></span>
                </div>
            </div>
        </div>
        
                    </div>
                </td>
            </tr>
        </tbody>
        <tfoot class="print-only-spacer-foot">
            <tr><td style="height: 100px; border:none;"></td></tr>
        </tfoot>
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
