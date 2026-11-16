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

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// TABLE SETUP
// =========================================================================
$tables = [
// Master list of clearance departments (HR can add more, e.g. Legal, Facilities)
"CREATE TABLE IF NOT EXISTS hr_exit_clearance_departments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    sort_order INT DEFAULT 0,
    is_active TINYINT(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

// Per-exit clearance items, one row per clearance department
"CREATE TABLE IF NOT EXISTS hr_exit_clearance_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    exit_id INT NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    status ENUM('pending','cleared') DEFAULT 'pending',
    remarks TEXT DEFAULT NULL,
    cleared_by VARCHAR(255) DEFAULT NULL,
    cleared_at DATETIME DEFAULT NULL,
    UNIQUE KEY uniq_exit_dept (exit_id, department_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];
foreach ($tables as $sql) mysqli_query($con, $sql);

// Seed default clearance departments if empty
$cnt = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_clearance_departments"));
if (intval($cnt['c']) == 0) {
    foreach (['IT' => 1, 'Finance' => 2, 'Admin' => 3, 'HR' => 4] as $name => $order) {
        $n = mysqli_real_escape_string($con, $name);
        mysqli_query($con, "INSERT INTO hr_exit_clearance_departments (department_name, sort_order) VALUES ('$n', $order)");
    }
} else {
    // Covers installs seeded before HR was added to the default department list
    $hasHr = mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_clearance_departments WHERE department_name='HR'")) > 0;
    if (!$hasHr) mysqli_query($con, "INSERT INTO hr_exit_clearance_departments (department_name, sort_order) VALUES ('HR', 4)");
}

// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    if (isset($_POST['action']) && $_POST['action'] === 'add_clearance_dept') {
        $name = mysqli_real_escape_string($con, trim($_POST['department_name']));
        if ($name) mysqli_query($con, "INSERT INTO hr_exit_clearance_departments (department_name, sort_order) VALUES ('$name', 99)");
        header("Location: hr-exit-clearance.php?tab=settings"); exit;
    }

    if (isset($_POST['action']) && $_POST['action'] === 'mark_cleared') {
        $item_id = intval($_POST['item_id']);
        $remarks = mysqli_real_escape_string($con, $_POST['remarks'] ?? '');
        $by = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "UPDATE hr_exit_clearance_items SET status='cleared', remarks='$remarks', cleared_by='$by', cleared_at=NOW() WHERE id=$item_id");
        header("Location: hr-exit-clearance.php?exit_id=" . intval($_POST['exit_id'])); exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================
$activeTab = $_GET['tab'] ?? 'clearance';
$exit_id = intval($_GET['exit_id'] ?? 0);

$clearanceDepts = [];
$cdq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_departments WHERE is_active=1 ORDER BY sort_order ASC");
while ($row = mysqli_fetch_assoc($cdq)) $clearanceDepts[] = $row;

$exitRow = null; $empRow = null; $handoverComplete = false; $items = [];
if ($exit_id > 0) {
    $exitRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_exit_requests WHERE id=$exit_id LIMIT 1"));
    if ($exitRow) {
        $empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id={$exitRow['employee_id']} LIMIT 1"));

        // Check handover completion — locking rule
        $htotal = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_handover_items WHERE exit_id=$exit_id"));
        $hack = mysqli_fetch_assoc(mysqli_query($con, "SELECT COUNT(*) as c FROM hr_exit_handover_items WHERE exit_id=$exit_id AND status='acknowledged'"));
        $handoverComplete = (intval($htotal['c']) > 0 && intval($htotal['c']) == intval($hack['c']));

        if ($handoverComplete) {
            // Auto-create clearance rows for this exit if not already present
            foreach ($clearanceDepts as $cd) {
                $dn = mysqli_real_escape_string($con, $cd['department_name']);
                mysqli_query($con, "INSERT IGNORE INTO hr_exit_clearance_items (exit_id, department_name) VALUES ($exit_id, '$dn')");
            }
            $iq = mysqli_query($con, "SELECT * FROM hr_exit_clearance_items WHERE exit_id=$exit_id ORDER BY id ASC");
            while ($row = mysqli_fetch_assoc($iq)) $items[] = $row;

            if (mysqli_num_rows(mysqli_query($con, "SELECT id FROM hr_exit_requests WHERE id=$exit_id AND status='handover'")) > 0) {
                mysqli_query($con, "UPDATE hr_exit_requests SET status='clearance' WHERE id=$exit_id");
            }
        }
    }
}
$total_items = count($items);
$cleared_items = count(array_filter($items, fn($i) => $i['status'] === 'cleared'));
$pct = $total_items > 0 ? round(($cleared_items / $total_items) * 100) : 0;

$exitsAwaitingClearance = [];
$eq = mysqli_query($con, "SELECT r.*, e.name as employee_name FROM hr_exit_requests r LEFT JOIN hr_employees e ON e.id=r.employee_id WHERE r.status IN ('handover','clearance') ORDER BY r.id DESC");
while ($row = mysqli_fetch_assoc($eq)) $exitsAwaitingClearance[] = $row;
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Department Clearance — Exit Module</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--amber:#b45309;--green:#10b981;--gray-bg:#f0f4f8;}
*{box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--gray-bg);margin:0;}
.hdr{background:linear-gradient(135deg,var(--navy),#b45309);padding:20px 30px;border-radius:12px;margin:20px;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-weight:800;font-size:1.3rem;margin:0;}
.hdr p{color:rgba(255,255,255,.7);font-size:12px;margin:4px 0 0;}
.wrap{max-width:1000px;margin:0 auto;padding:0 20px 30px;}
.tab-bar{display:flex;gap:6px;background:#fff;padding:6px;border-radius:12px;border:1px solid #e2e8f0;margin-bottom:18px;}
.tab-bar a{flex:1;text-align:center;padding:10px;border-radius:8px;font-weight:700;font-size:13px;color:#64748b;text-decoration:none;}
.tab-bar a.active{background:linear-gradient(135deg,var(--navy),#b45309);color:#fff;}
.card-box{background:#fff;border-radius:12px;padding:22px;box-shadow:0 2px 10px rgba(0,0,0,.06);margin-bottom:18px;}
.card-box h5{font-weight:800;color:var(--navy);margin-bottom:14px;font-size:15px;}
.fc{border:2px solid #e2e8f0;border-radius:8px;padding:9px 12px;font-size:13px;font-weight:600;width:100%;}
.btn-p{padding:9px 18px;border:none;border-radius:8px;font-weight:700;font-size:12px;cursor:pointer;color:#fff;}
.btn-navy{background:linear-gradient(135deg,var(--navy),#b45309);}
.btn-green{background:linear-gradient(135deg,var(--green),#059669);}
.progress-track{height:10px;border-radius:5px;background:#fde68a;overflow:hidden;}
.progress-fill{height:100%;background:linear-gradient(90deg,#f59e0b,var(--green));}
.dept-card{border:1.5px solid #e2e8f0;border-radius:10px;padding:16px;margin-bottom:10px;display:flex;justify-content:space-between;align-items:center;gap:14px;flex-wrap:wrap;}
.dept-card.cleared{border-color:#bbf7d0;background:#f0fdf4;}
.badge{padding:4px 10px;border-radius:12px;font-size:11px;font-weight:800;}
.b-pending{background:#fef3c7;color:#92400e;}
.b-cleared{background:#d1fae5;color:#065f46;}
table{width:100%;border-collapse:collapse;}
th{background:#f0f4f8;color:var(--navy);font-weight:800;font-size:11px;text-transform:uppercase;padding:10px 12px;text-align:left;}
td{padding:10px 12px;border-bottom:1px solid #f1f5f9;font-size:12.5px;}
</style>
</head>
<body>
<div class="hdr"><h1><i class="fas fa-clipboard-check mr-2"></i>Department Clearance</h1><p>Step 3 of 5 — IT, Finance, Admin sign off before settlement</p></div>
<div class="wrap">

<div class="tab-bar">
  <a href="?tab=clearance<?php echo $exit_id ? '&exit_id='.$exit_id : ''; ?>" class="<?php echo $activeTab=='clearance'?'active':''; ?>"><i class="fas fa-check-double mr-1"></i>Clearance</a>
  <a href="?tab=settings" class="<?php echo $activeTab=='settings'?'active':''; ?>"><i class="fas fa-cog mr-1"></i>Departments Setup (HR)</a>
</div>

<?php if ($activeTab === 'settings'): ?>
<div class="card-box">
  <h5><i class="fas fa-building mr-2"></i>Clearance Departments</h5>
  <form method="POST" class="form-inline mb-3">
    <input type="hidden" name="action" value="add_clearance_dept">
    <input type="text" name="department_name" class="fc mr-2" style="max-width:220px;" placeholder="e.g. Legal, Facilities" required>
    <button type="submit" class="btn-p btn-navy">Add Department</button>
  </form>
  <table><thead><tr><th>Department</th></tr></thead><tbody>
  <?php foreach ($clearanceDepts as $cd): ?>
  <tr><td><?php echo htmlspecialchars($cd['department_name']); ?></td></tr>
  <?php endforeach; ?>
  </tbody></table>
</div>

<?php else: ?>

<?php if (!$exit_id): ?>
<div class="card-box">
  <h5><i class="fas fa-user-clock mr-2"></i>Exits In Handover / Clearance</h5>
  <table><thead><tr><th>Exit #</th><th>Employee</th><th>Status</th><th>Action</th></tr></thead><tbody>
  <?php foreach ($exitsAwaitingClearance as $e): ?>
  <tr>
    <td><?php echo htmlspecialchars($e['exit_number']); ?></td>
    <td><?php echo htmlspecialchars($e['employee_name']); ?></td>
    <td><span class="badge b-pending"><?php echo ucfirst($e['status']); ?></span></td>
    <td><a href="?exit_id=<?php echo $e['id']; ?>" class="btn-p btn-navy" style="text-decoration:none;">Open</a></td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($exitsAwaitingClearance)): ?><tr><td colspan="4" style="text-align:center;color:#94a3b8;padding:30px;">No exits currently in this stage.</td></tr><?php endif; ?>
  </tbody></table>
</div>

<?php elseif (!$handoverComplete): ?>
<div class="card-box text-center" style="padding:50px 20px;">
  <i class="fas fa-lock" style="font-size:44px;color:#94a3b8;margin-bottom:14px;"></i>
  <h5 style="color:#334155;">Clearance is locked</h5>
  <p style="color:#64748b;font-size:14px;">Handover must be 100% acknowledged by the receiving supervisor before clearance can begin.</p>
  <a href="hr-exit-handover.php?exit_id=<?php echo $exit_id; ?>" class="btn-p btn-navy" style="text-decoration:none;">Go to Handover</a>
</div>

<?php else: ?>
<div class="card-box">
  <h5><i class="fas fa-clipboard-list mr-2"></i><?php echo htmlspecialchars($exitRow['exit_number']); ?> — <?php echo htmlspecialchars($empRow['name'] ?? ''); ?></h5>
  <div style="margin-bottom:14px;">
    <div style="display:flex;justify-content:space-between;font-size:12px;font-weight:700;color:var(--navy);margin-bottom:5px;"><span><?php echo $cleared_items; ?> of <?php echo $total_items; ?> departments cleared</span><span><?php echo $pct; ?>%</span></div>
    <div class="progress-track"><div class="progress-fill" style="width:<?php echo $pct; ?>%;"></div></div>
  </div>

  <?php foreach ($items as $it): ?>
  <div class="dept-card <?php echo $it['status']; ?>">
    <div>
      <strong><?php echo htmlspecialchars($it['department_name']); ?></strong>
      <?php if ($it['status']=='cleared'): ?>
      <div style="font-size:12px;color:#065f46;">Cleared by <?php echo htmlspecialchars($it['cleared_by']); ?> on <?php echo date('d M Y', strtotime($it['cleared_at'])); ?></div>
      <?php if ($it['remarks']): ?><div style="font-size:12px;color:#64748b;">Remarks: <?php echo htmlspecialchars($it['remarks']); ?></div><?php endif; ?>
      <?php endif; ?>
    </div>
    <?php if ($it['status']=='pending'): ?>
    <form method="POST" style="display:flex;gap:8px;align-items:center;">
      <input type="hidden" name="action" value="mark_cleared"><input type="hidden" name="item_id" value="<?php echo $it['id']; ?>"><input type="hidden" name="exit_id" value="<?php echo $exit_id; ?>">
      <input type="text" name="remarks" class="fc" placeholder="Remarks (optional)" style="width:220px;">
      <button type="submit" class="btn-p btn-green"><i class="fas fa-check mr-1"></i> Mark Cleared</button>
    </form>
    <?php else: ?>
    <span class="badge b-cleared">Cleared</span>
    <?php endif; ?>
  </div>
  <?php endforeach; ?>

  <?php if ($pct == 100 && $total_items > 0): ?>
  <div class="alert alert-success mt-3"><i class="fas fa-check-circle mr-1"></i> All departments cleared. <a href="hr-exit-interview-settlement.php?exit_id=<?php echo $exit_id; ?>">Proceed to Exit Interview & Settlement →</a></div>
  <?php endif; ?>
</div>
<?php endif; ?>
<?php endif; ?>

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
