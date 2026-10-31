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

if (!isset($dbConn) || !$dbConn) { die("Database connection failed."); }
mysqli_report(MYSQLI_REPORT_OFF);
date_default_timezone_set('Asia/Kolkata');

$session_id = 0;
if (isset($_SESSION['user_id'])) $session_id = intval($_SESSION['user_id']);
elseif (isset($_SESSION['id'])) $session_id = intval($_SESSION['id']);

$current_user_data = null;
if ($session_id > 0) {
    $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE id=$session_id OR user_id=$session_id LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
} elseif (isset($_SESSION['user_name'])) {
    $n = mysqli_real_escape_string($dbConn, $_SESSION['user_name']);
    $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE name='$n' OR name LIKE '$n%' LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
}
if (!$current_user_data) {
    die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h4>Session Expired.</h4><a href='login.php'>Login</a></div>");
}
$current_user_name = $current_user_data['name'];

// ---- AJAX: UNMARK (undo — just clears the flag, does not delete the candidate) ----
if (isset($_POST['ajax_unmark_employee'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id'] ?? 0);
    if ($sid <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid candidate.']); exit; }
    mysqli_query($dbConn, "UPDATE hr_screenings SET moved_to_employee_at=NULL, moved_to_employee_by=NULL WHERE id=$sid");
    echo json_encode(['success' => true]);
    exit;
}

// ---- FILTERS ----
$f_dept   = trim($_GET['department'] ?? '');
$f_from   = trim($_GET['date_from'] ?? '');
$f_to     = trim($_GET['date_to'] ?? '');
$f_search = trim($_GET['search'] ?? '');

$where = "WHERE moved_to_employee_at IS NOT NULL";
if ($f_dept !== '')   $where .= " AND department = '" . mysqli_real_escape_string($dbConn, $f_dept) . "'";
if ($f_from !== '')   $where .= " AND DATE(moved_to_employee_at) >= '" . mysqli_real_escape_string($dbConn, $f_from) . "'";
if ($f_to !== '')     $where .= " AND DATE(moved_to_employee_at) <= '" . mysqli_real_escape_string($dbConn, $f_to) . "'";
if ($f_search !== '') $where .= " AND candidate_name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%'";

$rows_res = mysqli_query($dbConn, "SELECT * FROM hr_screenings $where ORDER BY moved_to_employee_at DESC");
$rows = [];
if ($rows_res) while ($r = mysqli_fetch_assoc($rows_res)) $rows[] = $r;

$total_count = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT COUNT(*) as c FROM hr_screenings WHERE moved_to_employee_at IS NOT NULL"))['c'] ?? 0;

$depts = [];
$dq = mysqli_query($dbConn, "SELECT DISTINCT department FROM hr_screenings WHERE moved_to_employee_at IS NOT NULL AND department != '' ORDER BY department ASC");
if ($dq) while ($r = mysqli_fetch_assoc($dq)) $depts[] = $r['department'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Marked as Employee | HR</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--accent:#10b981;--danger:#ef4444;--success:#10b981;--warn:#f59e0b;--bg:#f0f4f9;--card:#fff;--border:#e4e9f2;--muted:#64748b;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;color:#0f172a;}
.hdr{background:linear-gradient(135deg,#10b981,#059669);padding:20px 28px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;box-shadow:0 4px 20px rgba(16,185,129,.25);}
.hdr h1{color:#fff;font-size:1.45rem;font-weight:800;margin:0;}
.hdr .sub{color:rgba(255,255,255,.75);font-size:12px;margin-top:3px;}
.btn-h{padding:9px 18px;border-radius:9px;font-weight:700;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:6px;font-size:13px;transition:.2s;text-decoration:none;color:#fff;}
.btn-navy{background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);}
.btn-h:hover{transform:translateY(-1px);box-shadow:0 5px 15px rgba(0,0,0,.15);color:#fff;text-decoration:none;}
.wrap{max-width:1400px;margin:0 auto;padding:24px 20px;}
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-bottom:22px;}
.stat-box{background:var(--card);border-radius:13px;padding:16px;border:1px solid var(--border);display:flex;align-items:center;gap:12px;box-shadow:0 2px 8px rgba(0,0,0,.04);}
.stat-ico{width:42px;height:42px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:16px;flex-shrink:0;background:linear-gradient(135deg,#10b981,#059669);color:#fff;}
.stat-val{font-size:22px;font-weight:800;line-height:1;color:var(--navy);}
.stat-lbl{font-size:10px;font-weight:700;color:var(--muted);text-transform:uppercase;margin-top:3px;}
.card-panel{background:var(--card);border-radius:15px;border:1px solid var(--border);box-shadow:0 2px 10px rgba(0,0,0,.05);overflow:hidden;}
.card-head{padding:18px 22px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;background:linear-gradient(135deg,#f0fdf4,#dcfce7);}
.card-head h5{font-weight:800;color:var(--navy);margin:0;}
.fc{box-sizing:border-box;border:2px solid var(--border);border-radius:9px;padding:9px 12px;font-size:13px;font-family:inherit;font-weight:600;width:100%;transition:.2s;background:#fff;color:#0f172a;}
.fc:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(16,185,129,.08);}
.filter-row{display:flex;gap:9px;flex-wrap:wrap;align-items:center;}
.tbl-wrap{overflow-x:auto;}
table.rtbl{width:100%;border-collapse:collapse;}
table.rtbl thead th{background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-weight:800;padding:12px 15px;font-size:11px;text-transform:uppercase;white-space:nowrap;border:none;}
table.rtbl tbody td{padding:13px 15px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:600;vertical-align:middle;}
table.rtbl tbody tr:hover{background:#f8fafc;}
.badge-emp{background:#dcfce7;color:#065f46;padding:4px 11px;border-radius:20px;font-weight:800;font-size:11px;text-transform:uppercase;white-space:nowrap;}
.cav{display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;background:linear-gradient(135deg,#10b981,#059669);flex-shrink:0;}
.empty-state{text-align:center;padding:60px 20px;color:var(--muted);}
</style>
</head>
<body>

<div class="hdr">
  <div>
    <h1><i class="fas fa-user-check mr-2"></i>Marked as Employee</h1>
    <div class="sub">Candidates manually marked as Employee from Screening &middot; <?php echo htmlspecialchars($current_user_name); ?></div>
  </div>
  <div style="display:flex;gap:9px;">
    <a href="hr_screening.php" class="btn-h btn-navy"><i class="fas fa-arrow-left"></i> Back to Screening</a>
  </div>
</div>

<div class="wrap">

<div class="stats-grid">
  <div class="stat-box">
    <div class="stat-ico"><i class="fas fa-user-check"></i></div>
    <div><div class="stat-val"><?php echo intval($total_count); ?></div><div class="stat-lbl">Total Marked as Employee</div></div>
  </div>
  <div class="stat-box">
    <div class="stat-ico"><i class="fas fa-filter"></i></div>
    <div><div class="stat-val"><?php echo count($rows); ?></div><div class="stat-lbl">Matching Current Filters</div></div>
  </div>
</div>

<div class="card-panel" style="margin-bottom:20px;">
  <div class="card-head">
    <h5><i class="fas fa-filter mr-2"></i>Filters</h5>
  </div>
  <div style="padding:18px 22px;">
    <form method="GET" class="filter-row">
      <input type="text" name="search" class="fc" style="width:220px;" placeholder="Search by name..." value="<?php echo htmlspecialchars($f_search); ?>">
      <select name="department" class="fc" style="width:200px;">
        <option value="">All Departments</option>
        <?php foreach ($depts as $d): ?>
        <option value="<?php echo htmlspecialchars($d); ?>" <?php echo $f_dept===$d?'selected':''; ?>><?php echo htmlspecialchars($d); ?></option>
        <?php endforeach; ?>
      </select>
      <input type="date" name="date_from" class="fc" style="width:160px;" value="<?php echo htmlspecialchars($f_from); ?>">
      <input type="date" name="date_to" class="fc" style="width:160px;" value="<?php echo htmlspecialchars($f_to); ?>">
      <button type="submit" class="btn-h" style="background:var(--accent);"><i class="fas fa-search"></i> Filter</button>
      <a href="hr-employee-log.php" class="btn-h btn-navy" style="color:var(--navy);background:#f1f5f9;"><i class="fas fa-redo"></i> Reset</a>
    </form>
  </div>
</div>

<div class="card-panel">
  <div class="card-head">
    <h5><i class="fas fa-list mr-2"></i>Employee List (<?php echo count($rows); ?>)</h5>
  </div>
  <?php if (empty($rows)): ?>
  <div class="empty-state">
    <i class="fas fa-user-check fa-3x" style="opacity:.3;margin-bottom:14px;display:block;"></i>
    No candidates have been marked as Employee yet<?php echo ($f_dept!==''||$f_search!==''||$f_from!==''||$f_to!=='')?' matching these filters':''; ?>.
  </div>
  <?php else: ?>
  <div class="tbl-wrap">
    <table class="rtbl">
      <thead><tr>
        <th></th><th>Candidate</th><th>Position</th><th>Department</th><th>Phone</th><th>Email</th><th>Marked By</th><th>Marked On</th><th>Action</th>
      </tr></thead>
      <tbody>
        <?php foreach ($rows as $r): ?>
        <tr>
          <td><div class="cav" style="width:38px;height:38px;border-radius:10px;font-size:14px;"><?php echo strtoupper(substr($r['candidate_name'],0,1)); ?></div></td>
          <td><strong style="color:var(--navy);"><?php echo htmlspecialchars($r['candidate_name']); ?></strong><br><span class="badge-emp" style="margin-top:4px;display:inline-block;"><i class="fas fa-check-circle mr-1"></i>Employee</span></td>
          <td><?php echo htmlspecialchars($r['position_applied']); ?></td>
          <td><?php echo htmlspecialchars($r['department']); ?></td>
          <td><?php echo htmlspecialchars($r['candidate_phone'] ?: '-'); ?></td>
          <td><?php echo htmlspecialchars($r['candidate_email'] ?: '-'); ?></td>
          <td><?php echo htmlspecialchars($r['moved_to_employee_by'] ?: '-'); ?></td>
          <td><?php echo date('d M Y, h:i A', strtotime($r['moved_to_employee_at'])); ?></td>
          <td>
            <div style="display:flex;gap:6px;">
              <a href="hr_screening.php?view_candidate=<?php echo intval($r['id']); ?>" class="btn-h" style="background:var(--blue);padding:7px 12px;font-size:11px;" title="Open Candidate"><i class="fas fa-eye"></i></a>
              <button type="button" onclick="unmarkEmployee(<?php echo intval($r['id']); ?>, '<?php echo addslashes(htmlspecialchars($r['candidate_name'])); ?>')" class="btn-h" style="background:#fee2e2;color:#991b1b;padding:7px 12px;font-size:11px;" title="Undo"><i class="fas fa-undo"></i></button>
            </div>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>

</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script>
function unmarkEmployee(id, name) {
    if (!confirm('Remove the Employee mark from "' + name + '"?\n\nThis does not delete the candidate — it just undoes the mark.')) return;
    $.post(window.location.pathname, { ajax_unmark_employee: 1, screening_id: id }, function(resp) {
        if (resp.success) { window.location.reload(); } else { alert(resp.message || 'Could not undo.'); }
    }, 'json').fail(function(){ alert('Server error.'); });
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
