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

set_error_handler(function($errno, $errstr, $errfile, $errline) {
    echo '<div style="background:#fee2e2;color:#991b1b;padding:15px;border-radius:8px;font-weight:600;font-size:13px;">PHP Error: ' . htmlspecialchars($errstr) . ' (Line ' . $errline . ')</div>'; exit;
});
set_exception_handler(function($e) {
    echo '<div style="background:#fee2e2;color:#991b1b;padding:15px;border-radius:8px;font-weight:600;font-size:13px;">Exception: ' . htmlspecialchars($e->getMessage()) . '</div>'; exit;
});

error_reporting(E_ALL);
ini_set('display_errors', 0);

$con = null;
if (file_exists('database.php'))          require_once('database.php');
if (file_exists('database-settings.php')) require_once('database-settings.php');
if (file_exists('library.php'))           require_once('library.php');
if (file_exists('funciones.php'))         require_once('funciones.php');
if (function_exists('conexion')) $con = conexion();
elseif (isset($dbConn))          $con = $dbConn;

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$isAdmin = stripos($currentUserName, 'Abishek') !== false;

if (!$con) {
    echo '<div style="background:#fee2e2;color:#991b1b;padding:15px;border-radius:8px;font-weight:600;">Database not connected.</div>'; exit;
}

$employee_id_param = isset($_GET['employee_id']) ? trim($_GET['employee_id']) : '';
if (empty($employee_id_param)) {
    echo '<div style="background:#fef3c7;color:#92400e;padding:15px;border-radius:8px;font-weight:600;">No employee ID provided.</div>'; exit;
}

// Detect actual columns
$cols = [];
$r = mysqli_query($con, "SHOW COLUMNS FROM hr_employee_documents");
if ($r) while ($row = mysqli_fetch_assoc($r)) $cols[] = $row['Field'];

// Get integer id for this employee (documents may be stored by either)
$eid_safe = mysqli_real_escape_string($con, $employee_id_param);
$emp_row  = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_employees WHERE employee_id = '$eid_safe' LIMIT 1"));
$emp_int_id = $emp_row ? intval($emp_row['id']) : 0;

// Build SELECT with only existing columns
$sel = ['id', 'employee_id', 'filepath'];
foreach (['document_type','document_label','filename','file_name','original_name','file_path','uploaded_at','upload_date','created_at','date_uploaded','date'] as $c) {
    if (in_array($c, $cols)) $sel[] = $c;
}
$sel_str = implode(', ', array_unique($sel));
$date_cols = ['uploaded_at','upload_date','created_at','date_uploaded','date'];
$order = 'id';
foreach($date_cols as $dc) { if(in_array($dc,$cols)){ $order=$dc; break; } }

// Search by both string employee_id AND integer id
$where = $emp_int_id > 0
    ? "(employee_id = '$eid_safe' OR employee_id = '$emp_int_id')"
    : "employee_id = '$eid_safe'";

$res  = mysqli_query($con, "SELECT $sel_str FROM hr_employee_documents WHERE $where ORDER BY $order DESC");
$docs = [];
if ($res) while ($d = mysqli_fetch_assoc($res)) $docs[] = $d;

// Convert filepath → web URL
function buildUrl($fp) {
    $fp = str_replace('\\', '/', $fp);
    if (preg_match('#https?://[^/]+(/.+)#', $fp, $m)) $fp = $m[1];
    if (strpos($fp, '/hrm/uploads/') === 0) return $fp;
    if (preg_match('#/uploads/employee_documents/(.+)$#', $fp, $m)) return '/hrm/uploads/employee_documents/' . $m[1];
    if (preg_match('#^uploads/employee_documents/(.+)$#', $fp, $m)) return '/hrm/uploads/employee_documents/' . $m[1];
    if (preg_match('#^uploads/(.+)$#', $fp, $m)) return '/hrm/uploads/' . $m[1];
    return '/hrm/' . ltrim($fp, '/');
}

$iconMap = [
    'pdf'  => ['fas fa-file-pdf',   '#ef4444'],
    'doc'  => ['fas fa-file-word',  '#3b82f6'],
    'docx' => ['fas fa-file-word',  '#3b82f6'],
    'jpg'  => ['fas fa-file-image', '#f59e0b'],
    'jpeg' => ['fas fa-file-image', '#f59e0b'],
    'png'  => ['fas fa-file-image', '#f59e0b'],
    'gif'  => ['fas fa-file-image', '#f59e0b'],
];
?>

<?php if (empty($docs)): ?>
<div style="text-align:center;padding:40px 20px;">
    <i class="fas fa-folder-open" style="font-size:56px;color:#cbd5e1;display:block;margin-bottom:14px;"></i>
    <h5 style="color:#64748b;font-weight:700;margin-bottom:6px;">No Documents Found</h5>
    <p style="color:#94a3b8;font-size:13px;margin:0;">No documents have been uploaded for this employee yet.</p>
    <p style="color:#94a3b8;font-size:12px;margin-top:6px;">Documents can be uploaded from the <strong>Add / Edit Employee</strong> page.</p>
</div>
<?php else: ?>
<div style="margin-bottom:14px;display:flex;align-items:center;justify-content:space-between;">
    <span style="font-weight:700;color:#1e3a8a;font-size:15px;">
        <i class="fas fa-folder" style="color:#8b5cf6;"></i>
        &nbsp;<?php echo count($docs); ?> Document<?php echo count($docs) != 1 ? 's' : ''; ?>
    </span>
    <span style="font-size:12px;color:#94a3b8;">
        To add more, use the Edit Employee page
    </span>
</div>
<div style="max-height:420px;overflow-y:auto;padding-right:4px;">
<?php foreach ($docs as $doc):
    $fp    = $doc['filepath'] ?? $doc['file_path'] ?? '';
    $ext   = strtolower(pathinfo($fp, PATHINFO_EXTENSION));
    $ic    = $iconMap[$ext] ?? ['fas fa-file-alt', '#64748b'];
    $label = $doc['document_label'] ?? $doc['document_type'] ?? 'Document';
    $fname = $doc['filename'] ?? $doc['file_name'] ?? $doc['original_name'] ?? basename($fp);
    $date = $doc['uploaded_at'] ?? $doc['upload_date'] ?? $doc['created_at'] ?? $doc['date_uploaded'] ?? $doc['date'] ?? '';
    $url   = buildUrl($fp);
?>
<div style="background:#f8fafc;padding:14px 16px;border-radius:10px;margin-bottom:10px;border:2px solid #e2e8f0;display:flex;align-items:center;gap:14px;transition:all 0.2s;"
     onmouseover="this.style.borderColor='#8b5cf6';this.style.background='#f5f3ff'"
     onmouseout="this.style.borderColor='#e2e8f0';this.style.background='#f8fafc'">

    <!-- Icon -->
    <div style="width:46px;height:46px;border-radius:10px;background:<?php echo $ic[1]; ?>1a;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        <i class="<?php echo $ic[0]; ?>" style="font-size:22px;color:<?php echo $ic[1]; ?>;"></i>
    </div>

    <!-- Info -->
    <div style="flex:1;min-width:0;">
        <div style="font-weight:700;color:#1e3a8a;font-size:14px;margin-bottom:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
            <?php echo htmlspecialchars($label); ?>
        </div>
        <div style="font-size:12px;color:#64748b;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
            <i class="fas fa-file" style="font-size:10px;"></i> <?php echo htmlspecialchars($fname); ?>
        </div>
        <?php if ($date): ?>
        <div style="font-size:11px;color:#94a3b8;margin-top:2px;">
            <i class="fas fa-clock" style="font-size:10px;"></i> <?php echo date('d M Y, h:i A', strtotime($date)); ?>
        </div>
        <?php endif; ?>
    </div>

    <!-- Actions -->
    <div style="display:flex;gap:6px;flex-shrink:0;">
        <a href="<?php echo htmlspecialchars($url); ?>" target="_blank"
           style="background:#3b82f6;color:white;padding:8px 14px;border-radius:7px;text-decoration:none;font-weight:600;font-size:12px;display:inline-flex;align-items:center;gap:5px;">
            <i class="fas fa-eye"></i> View
        </a>
        <a href="<?php echo htmlspecialchars($url); ?>" target="_blank"
           style="background:#10b981;color:white;padding:8px 12px;border-radius:7px;text-decoration:none;font-weight:600;font-size:12px;display:inline-flex;align-items:center;gap:5px;">
            <i class="fas fa-download"></i>
        </a>
        <?php if ($isAdmin): ?>
        <a href="hr-employees-list.php?delete_doc=<?php echo intval($doc['id']); ?>"
           onclick="return confirm('Delete this document?\nThis cannot be undone.')"
           style="background:#ef4444;color:white;padding:8px 12px;border-radius:7px;text-decoration:none;font-weight:600;font-size:12px;display:inline-flex;align-items:center;gap:5px;">
            <i class="fas fa-trash"></i>
        </a>
        <?php endif; ?>
    </div>
</div>
<?php endforeach; ?>
</div>
<?php endif; ?>