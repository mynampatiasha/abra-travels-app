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
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) { echo '<div class="alert alert-danger">Database connection failed.</div>'; exit; }
mysqli_set_charset($con, 'utf8mb4');

isUser();

$employee_id = isset($_GET['employee_id']) ? intval($_GET['employee_id']) : 0;

if ($employee_id <= 0) {
    echo '<div class="alert alert-warning">Invalid employee.</div>';
    exit;
}

$q = mysqli_query($con, "SELECT ct.*, 
        fd.name as from_dept_name, fp.title as from_pos_name,
        td.name as to_dept_name, tp.title as to_pos_name
    FROM hr_oje_cross_training ct
    LEFT JOIN hr_departments fd ON fd.id = ct.from_dept_id
    LEFT JOIN hr_positions   fp ON fp.id = ct.from_pos_id
    LEFT JOIN hr_departments td ON td.id = ct.to_dept_id
    LEFT JOIN hr_positions   tp ON tp.id = ct.to_pos_id
    WHERE ct.employee_id = $employee_id
    ORDER BY ct.created_at ASC");

$hops = [];
if ($q) { while ($r = mysqli_fetch_assoc($q)) $hops[] = $r; }

if (empty($hops)) {
    echo '<div class="no-documents"><i class="fas fa-route"></i><p>No cross-training history found for this employee.</p></div>';
    exit;
}
?>
<div style="padding:10px 0;">
  <div style="display:flex;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:20px;">
    <?php foreach ($hops as $i => $hop): ?>
      <?php if ($i === 0): ?>
        <span style="padding:8px 16px;border-radius:20px;font-size:13px;font-weight:700;background:#f1f5f9;color:#475569;">
          <?php echo htmlspecialchars($hop['from_dept_name'] ?? 'N/A'); ?><?php echo !empty($hop['from_pos_name']) ? ' ('.htmlspecialchars($hop['from_pos_name']).')' : ''; ?>
        </span>
        <i class="fas fa-long-arrow-alt-right" style="color:#94a3b8;"></i>
      <?php endif; ?>
      <span style="padding:8px 16px;border-radius:20px;font-size:13px;font-weight:700;
        <?php echo $hop['status']==='completed' ? 'background:#d1fae5;color:#065f46;' : ($hop['status']==='cancelled' ? 'background:#f1f5f9;color:#94a3b8;text-decoration:line-through;' : 'background:#dbeafe;color:#1e40af;'); ?>">
        <?php echo htmlspecialchars($hop['to_dept_name'] ?? 'N/A'); ?><?php echo !empty($hop['to_pos_name']) ? ' ('.htmlspecialchars($hop['to_pos_name']).')' : ''; ?>
        <?php if ($hop['status']==='completed'): ?><i class="fas fa-check-circle ml-1"></i><?php elseif($hop['status']==='active'): ?><i class="fas fa-spinner fa-spin ml-1"></i><?php else: ?><i class="fas fa-times-circle ml-1"></i><?php endif; ?>
      </span>
      <?php if ($i < count($hops) - 1): ?>
        <i class="fas fa-long-arrow-alt-right" style="color:#94a3b8;"></i>
      <?php endif; ?>
    <?php endforeach; ?>
  </div>

  <table class="table" style="font-size:13px;">
    <thead>
      <tr style="background:#f8fafc;">
        <th>#</th><th>From</th><th>To</th><th>Start Date</th><th>Status</th><th>Initiated By</th>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($hops as $i => $hop): ?>
      <tr>
        <td><?php echo $i+1; ?></td>
        <td><?php echo htmlspecialchars($hop['from_dept_name'] ?? 'N/A'); ?><br><span style="color:#94a3b8;font-size:11px;"><?php echo htmlspecialchars($hop['from_pos_name'] ?? 'All'); ?></span></td>
        <td><?php echo htmlspecialchars($hop['to_dept_name'] ?? 'N/A'); ?><br><span style="color:#94a3b8;font-size:11px;"><?php echo htmlspecialchars($hop['to_pos_name'] ?? 'All'); ?></span></td>
        <td><?php echo $hop['start_date'] ? date('d M Y', strtotime($hop['start_date'])) : '-'; ?></td>
        <td>
          <?php if ($hop['status']==='completed'): ?><span class="badge badge-success">Completed</span>
          <?php elseif ($hop['status']==='cancelled'): ?><span class="badge badge-secondary">Cancelled</span>
          <?php else: ?><span class="badge badge-info">Active</span><?php endif; ?>
        </td>
        <td><?php echo htmlspecialchars($hop['initiated_by'] ?? ''); ?></td>
      </tr>
      <?php endforeach; ?>
    </tbody>
  </table>

  <?php $lastHop = end($hops); if ($lastHop['status']==='completed'): ?>
  <div style="margin-top:10px;padding:12px 16px;background:#f0fdf4;border-left:4px solid #10b981;border-radius:8px;font-size:13px;color:#065f46;font-weight:600;">
    <i class="fas fa-info-circle mr-1"></i> This employee's current department/position has been automatically updated to <strong><?php echo htmlspecialchars($lastHop['to_dept_name'] ?? ''); ?></strong> based on their latest completed cross training.
  </div>
  <?php endif; ?>
</div>