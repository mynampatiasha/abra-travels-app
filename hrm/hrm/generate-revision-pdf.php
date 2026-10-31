<?php
// Standalone, isolated PDF generator for revised offer letters already filed
// into hr_employee_documents. Deliberately independent of hr-employee-offer.php —
// it only reads hr_offer_letters/hr_offer_company_settings and writes one file
// to disk plus one column update, so a failure here can't affect anything else
// (sending, approving, creating revisions all stay untouched).
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

$con = null;
if (file_exists('database.php'))          require_once('database.php');
if (file_exists('database-settings.php')) require_once('database-settings.php');
if (file_exists('library.php'))           require_once('library.php');
if (file_exists('funciones.php'))         require_once('funciones.php');
if (function_exists('conexion')) $con = conexion();
elseif (isset($dbConn))          $con = $dbConn;

function backToList($msg, $isError = false) {
    $_SESSION[$isError ? 'error_message' : 'success_message'] = $msg;
    header('Location: hr-employees-list.php');
    exit;
}

if (!$con) backToList('Database not connected.', true);

$doc_id = intval($_GET['doc_id'] ?? 0);
if ($doc_id <= 0) backToList('No document specified.', true);

// Detect hr_employee_documents' real columns (schema varies — same approach
// get-employee-documents.php already uses) so we read/write the right ones.
$doc_cols = [];
$dc_res = mysqli_query($con, "SHOW COLUMNS FROM hr_employee_documents");
if ($dc_res) while ($dcr = mysqli_fetch_assoc($dc_res)) $doc_cols[] = $dcr['Field'];
$path_col = in_array('filepath', $doc_cols) ? 'filepath' : (in_array('file_path', $doc_cols) ? 'file_path' : null);
if (!$path_col) backToList('Document table has no filepath column.', true);

$doc_res = mysqli_query($con, "SELECT id, employee_id, $path_col as doc_path FROM hr_employee_documents WHERE id=$doc_id LIMIT 1");
$doc_row = $doc_res ? mysqli_fetch_assoc($doc_res) : null;
if (!$doc_row) backToList('Document not found.', true);

// Only ever act on entries that are still the print-page link — never touch
// real uploaded files (NDA, tax declaration, etc.) or already-converted PDFs.
if (strpos($doc_row['doc_path'], 'hr-employee-offer.php') === false || strpos($doc_row['doc_path'], 'token=') === false) {
    backToList('This document is not a revised offer letter link — nothing to convert.', true);
}
parse_str(parse_url($doc_row['doc_path'], PHP_URL_QUERY) ?: '', $qs);
$token = mysqli_real_escape_string($con, $qs['token'] ?? '');
if ($token === '') backToList('Could not read the token from this document link.', true);

$offer_res = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE token='$token' LIMIT 1");
$offer = $offer_res ? mysqli_fetch_assoc($offer_res) : null;
if (!$offer) backToList('Original offer letter record not found.', true);

// Same punctuation/suffix-tolerant company-name matching used elsewhere in
// this app (hr-manpower.php / hr-payroll.php / hr-employee-offer.php).
function genpdf_normalize_company_name($s) {
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    $s = preg_replace('/\b(pvt|private|ltd|limited|llp|inc|incorporated|co|company|corp|corporation)\b/', '', $s);
    return trim(preg_replace('/\s+/', ' ', $s));
}
$cs = [];
$emp_res = mysqli_query($con, "SELECT company_name FROM hr_employees WHERE id=" . intval($offer['employee_id']) . " LIMIT 1");
$emp_row = $emp_res ? mysqli_fetch_assoc($emp_res) : null;
if ($emp_row && !empty($emp_row['company_name'])) {
    $emp_norm = genpdf_normalize_company_name($emp_row['company_name']);
    $company_id = 0;
    $mc_res = mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE company_name IS NOT NULL AND company_name != ''");
    if ($mc_res) while ($mc = mysqli_fetch_assoc($mc_res)) {
        if (genpdf_normalize_company_name($mc['company_name']) === $emp_norm) { $company_id = intval($mc['id']); break; }
    }
    if ($company_id > 0) {
        $cs_res = mysqli_query($con, "SELECT cs.*, hc.company_name as live_company_name FROM hr_offer_company_settings cs
                                       LEFT JOIN hr_companies hc ON hc.id = cs.company_id
                                       WHERE cs.company_id = $company_id LIMIT 1");
        $cs_row = $cs_res ? mysqli_fetch_assoc($cs_res) : null;
        if ($cs_row) {
            if (!empty($cs_row['live_company_name'])) $cs_row['company_name'] = $cs_row['live_company_name'];
            if (empty($cs_row['company_signature']) && !empty($cs_row['signature_path'])) $cs_row['company_signature'] = $cs_row['signature_path'];
            $cs = $cs_row;
        }
    }
}

$dompdf_autoload = __DIR__ . '/dompdf/autoload.inc.php';
if (!file_exists($dompdf_autoload)) backToList('Dompdf is not installed on the server (missing /dompdf folder).', true);
require_once $dompdf_autoload;

$logo_html = '';
if (!empty($cs['company_logo']) && file_exists(__DIR__ . '/' . $cs['company_logo'])) {
    $ext = strtolower(pathinfo($cs['company_logo'], PATHINFO_EXTENSION));
    $logo_html = '<img src="data:image/' . $ext . ';base64,' . base64_encode(file_get_contents(__DIR__ . '/' . $cs['company_logo'])) . '" style="max-height:70px;max-width:180px;">';
}
$sig_html = '';
if (!empty($cs['company_signature']) && file_exists(__DIR__ . '/' . $cs['company_signature'])) {
    $ext = strtolower(pathinfo($cs['company_signature'], PATHINFO_EXTENSION));
    $sig_html = '<img src="data:image/' . $ext . ';base64,' . base64_encode(file_get_contents(__DIR__ . '/' . $cs['company_signature'])) . '" style="max-height:60px;max-width:150px;">';
}
$cand_sig_html = '';
if (!empty($offer['candidate_signature']) && strpos($offer['candidate_signature'], 'data:image') === 0) {
    $cand_sig_html = '<img src="' . htmlspecialchars($offer['candidate_signature']) . '" style="max-height:60px;max-width:200px;">';
}

$terms_html = '';
foreach (explode("\n", $offer['terms_conditions'] ?? '') as $line) {
    $line = trim($line);
    if ($line !== '') $terms_html .= '<li style="margin-bottom:6px;">' . htmlspecialchars($line) . '</li>';
}
$roles_html = '';
foreach (explode("\n", $offer['roles_responsibilities'] ?? '') as $line) {
    $line = trim($line);
    if ($line !== '') $roles_html .= '<li style="margin-bottom:6px;">' . htmlspecialchars($line) . '</li>';
}

$bar_top = '<div style="background:#0f2557;height:8px;"></div><div style="background:#42598a;height:4px;"></div>';
$bar_bottom = '<div style="background:#42598a;height:4px;margin-top:20px;"></div><div style="background:#0f2557;height:8px;"></div>';

$html = '<html><head><meta charset="utf-8"><style>
    body { font-family: Arial, sans-serif; font-size: 12px; color:#1a202c; margin:0; }
    .content { padding: 20px 30px; }
    .header { border-bottom: 3px solid #0f2557; padding-bottom: 12px; margin-bottom: 20px; }
    .header table { width:100%; }
    .subject { text-align:center; font-weight:bold; text-decoration:underline; margin:16px 0; }
    .summary-box { border:1px solid #dbeafe; background:#f8faff; padding:10px 14px; margin-bottom:16px; }
    .summary-box table { width:100%; font-size:12px; }
    ul { padding-left:20px; margin:6px 0; }
    .sig-area table { width:100%; margin-top:30px; }
    .sig-line { border-top:1px solid #334155; margin-top:50px; padding-top:6px; font-size:11px; font-weight:bold; }
</style></head><body>
' . $bar_top . '
<div class="content">
<div class="header"><table><tr>
    <td style="font-size:11px;color:#0f2557;">' . htmlspecialchars($cs['company_phone'] ?? '') . '<br>' . htmlspecialchars($cs['company_email'] ?? '') . '<br>' . htmlspecialchars($cs['company_website'] ?? '') . '</td>
    <td style="text-align:right;">' . $logo_html . '</td>
</tr></table></div>
<div style="margin-bottom:20px;">
    <strong>From</strong><br>
    <strong>' . htmlspecialchars($cs['company_name'] ?? '') . '</strong><br>
    ' . (!empty($cs['company_address']) ? 'Registered Office: ' . nl2br(htmlspecialchars($cs['company_address'])) . '<br>' : '') . '
    Email: ' . htmlspecialchars($cs['company_email'] ?? '') . ' | Phone: ' . htmlspecialchars($cs['company_phone'] ?? '') . '<br>
    Date: ' . date('d/m/Y') . '
</div>
<div style="margin-bottom:20px;">
    <strong>To,</strong><br>
    <strong>' . htmlspecialchars($offer['salutation'] ?? 'Mr.') . ' ' . htmlspecialchars($offer['candidate_name']) . '</strong>
</div>
<div class="subject">Subject: Revised Offer of Employment / Revision of Terms &mdash; ' . htmlspecialchars($offer['position']) . '</div>
<p>Dear ' . htmlspecialchars($offer['salutation'] ?? 'Mr.') . ' ' . htmlspecialchars($offer['candidate_name']) . ',</p>
<p>Further to your employment with ' . htmlspecialchars($cs['company_name'] ?? '') . ', we are pleased to inform you that your terms of employment have been revised as set out below, effective from the date mentioned. This letter supersedes the salary/designation terms of your previous offer letter to the extent revised herein; all other terms and conditions remain unchanged.</p>
<div class="summary-box">
    <strong>Summary of Revision:</strong>
    <table>
        <tr><td style="color:#64748b;width:150px;">Designation</td><td>' . htmlspecialchars($offer['previous_position'] ?: '-') . ' -&gt; <strong>' . htmlspecialchars($offer['position']) . '</strong></td></tr>
        <tr><td style="color:#64748b;">CTC / Salary</td><td>' . htmlspecialchars($offer['previous_ctc'] ?: '-') . ' -&gt; <strong>' . htmlspecialchars($offer['offered_ctc']) . '</strong></td></tr>
        <tr><td style="color:#64748b;">Effective From</td><td><strong>' . (!empty($offer['revision_effective_date']) ? date('d M Y', strtotime($offer['revision_effective_date'])) : '-') . '</strong></td></tr>
        ' . (!empty($offer['revision_reason']) ? '<tr><td style="color:#64748b;">Reason</td><td>' . htmlspecialchars($offer['revision_reason']) . '</td></tr>' : '') . '
    </table>
</div>
' . ($roles_html ? '<div style="margin-bottom:16px;"><strong>Roles and Responsibilities:</strong><ul>' . $roles_html . '</ul></div>' : '') . '
<div style="margin-bottom:16px;"><strong>Terms and Conditions:</strong><ul>' . $terms_html . '</ul></div>
<div style="margin-bottom:20px;"><strong>Verification:</strong> This letter is subject to successful verification of records and continued compliance with company policies.</div>
<div class="sig-area"><table><tr>
    <td style="width:50%;">' . $sig_html . '<div class="sig-line">For ' . htmlspecialchars($cs['company_name'] ?? '') . '<br>Name: ' . htmlspecialchars($cs['signatory_name'] ?? '') . '<br>Designation: ' . htmlspecialchars($cs['signatory_designation'] ?? '') . '</div></td>
    <td style="width:50%;">' . $cand_sig_html . '<div class="sig-line">Accepted and Agreed<br>' . htmlspecialchars($offer['candidate_name']) . '</div></td>
</tr></table></div>
</div>
' . $bar_bottom . '
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
</html>';

try {
    $dompdf = new \Dompdf\Dompdf(['isRemoteEnabled' => false]);
    $dompdf->loadHtml($html);
    $dompdf->setPaper('A4', 'portrait');
    $dompdf->render();
} catch (\Throwable $e) {
    backToList('PDF generation failed: ' . $e->getMessage(), true);
}

$dir = __DIR__ . '/uploads/employee_documents/' . intval($offer['employee_id']) . '/';
if (!is_dir($dir)) mkdir($dir, 0755, true);
$fname = 'Revised_Offer_Letter_' . preg_replace('/[^A-Za-z0-9]+/', '_', $offer['candidate_name']) . '_' . date('d-m-Y') . '_' . time() . '.pdf';
if (!file_put_contents($dir . $fname, $dompdf->output())) {
    backToList('Could not save the generated PDF file — check folder permissions on uploads/employee_documents/.', true);
}

$new_path = 'uploads/employee_documents/' . intval($offer['employee_id']) . '/' . $fname;
$new_path_esc = mysqli_real_escape_string($con, $new_path);
mysqli_query($con, "UPDATE hr_employee_documents SET $path_col='$new_path_esc' WHERE id=$doc_id");

// Open the newly generated PDF directly instead of just going back to the
// plain list, so one click on "Generate PDF" ends with the actual file.
header('Location: ' . $new_path);
exit;