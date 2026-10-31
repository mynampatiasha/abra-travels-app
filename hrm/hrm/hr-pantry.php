<?php
// =========================================================================
// OFFICE PANTRY / SUPPLIES TRACKER
// =========================================================================
// - Log office consumables (milk, tea, sugar, etc.) with date, status, amount
// - Item master list — anyone can add a new item on the fly (select2 "tag")
// - Shared data: every logged-in user sees and can log entries
// - Filter by period (month/year/custom range), item, status, search
// - Full CRUD on entries: Add / Edit / Delete
// - Export filtered results to Excel (.xls) and PDF
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 0);
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

date_default_timezone_set('Asia/Kolkata');

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require_once('requirelanguage.php');

$con = conexion();
if (!$con) die("Database connection failed");
mysqli_set_charset($con, 'utf8mb4');

// Requires an active session, same convention as the rest of the HR suite.
if (function_exists('isUser')) isUser();

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : 'Unknown User';

// =========================================================================
// ENSURE TABLES EXIST
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_pantry_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    item_name VARCHAR(150) NOT NULL,
    unit VARCHAR(50) DEFAULT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_by VARCHAR(150),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_item_name (item_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_pantry_entries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    item_id INT DEFAULT NULL,
    item_name VARCHAR(150) NOT NULL,
    entry_date DATE NOT NULL,
    status ENUM('Bought','Pending') NOT NULL DEFAULT 'Bought',
    amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    remarks VARCHAR(255) DEFAULT NULL,
    added_by VARCHAR(150),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_date (entry_date),
    INDEX idx_item (item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Item list starts empty by design — HR adds every item herself via "+ Add New Item".

$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
$script_path = $base_url . $_SERVER['PHP_SELF'];

// =========================================================================
// HELPERS
// =========================================================================
function pantry_status_style($status) {
    if ($status === 'Bought') return ['c' => '#047857', 'bg' => '#ecfdf5', 'border' => '#a7f3d0', 'icon' => '✔️'];
    return ['c' => '#b91c1c', 'bg' => '#fef2f2', 'border' => '#fecaca', 'icon' => '⏳'];
}

function get_or_create_pantry_item($con, $item_id, $item_name_raw, $currentUserName) {
    $item_id = intval($item_id);
    if ($item_id > 0) {
        $q = mysqli_query($con, "SELECT id, item_name FROM hr_pantry_items WHERE id=$item_id LIMIT 1");
        if ($q && mysqli_num_rows($q) > 0) return mysqli_fetch_assoc($q);
    }
    // No valid existing item_id — try to match by name, else create a new item (select2 "tag" flow)
    $name = trim($item_name_raw);
    if ($name === '') return null;
    $name_safe = mysqli_real_escape_string($con, $name);
    $q = mysqli_query($con, "SELECT id, item_name FROM hr_pantry_items WHERE LOWER(item_name)=LOWER('$name_safe') LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) return mysqli_fetch_assoc($q);

    $cb = mysqli_real_escape_string($con, $currentUserName);
    mysqli_query($con, "INSERT IGNORE INTO hr_pantry_items (item_name, created_by) VALUES ('$name_safe', '$cb')");
    $new_id = mysqli_insert_id($con);
    if ($new_id > 0) return ['id' => $new_id, 'item_name' => $name];
    $q2 = mysqli_query($con, "SELECT id, item_name FROM hr_pantry_items WHERE LOWER(item_name)=LOWER('$name_safe') LIMIT 1");
    return $q2 ? mysqli_fetch_assoc($q2) : null;
}

// =========================================================================
// AJAX: ADD ITEM (standalone "manage items" action)
// =========================================================================
if (isset($_POST['ajax_add_item'])) {
    header('Content-Type: application/json');
    $name = trim($_POST['item_name'] ?? '');
    $unit = trim($_POST['unit'] ?? '');
    if ($name === '') { echo json_encode(['success' => false, 'message' => 'Item name is required.']); exit; }
    $item = get_or_create_pantry_item($con, 0, $name, $currentUserName);
    if (!$item) { echo json_encode(['success' => false, 'message' => 'Could not create item.']); exit; }
    if ($unit !== '') {
        $unit_safe = mysqli_real_escape_string($con, $unit);
        mysqli_query($con, "UPDATE hr_pantry_items SET unit='$unit_safe' WHERE id=" . intval($item['id']));
    }
    echo json_encode(['success' => true, 'id' => $item['id'], 'item_name' => $item['item_name']]);
    exit;
}

// =========================================================================
// AJAX: SAVE ENTRY (create or update)
// =========================================================================
if (isset($_POST['ajax_save_entry'])) {
    header('Content-Type: application/json');
    $entry_id   = intval($_POST['entry_id'] ?? 0);
    $item_id    = intval($_POST['item_id'] ?? 0);
    $item_name  = trim($_POST['item_name'] ?? '');
    $entry_date = trim($_POST['entry_date'] ?? '');
    $status     = ($_POST['status'] ?? 'Bought') === 'Pending' ? 'Pending' : 'Bought';
    $amount     = floatval($_POST['amount'] ?? 0);
    $remarks    = trim($_POST['remarks'] ?? '');

    if ($entry_date === '') { echo json_encode(['success' => false, 'message' => 'Date is required.']); exit; }
    if ($item_id <= 0 && $item_name === '') { echo json_encode(['success' => false, 'message' => 'Please select or type an item.']); exit; }
    if ($amount < 0) { echo json_encode(['success' => false, 'message' => 'Amount cannot be negative.']); exit; }

    $item = get_or_create_pantry_item($con, $item_id, $item_name, $currentUserName);
    if (!$item) { echo json_encode(['success' => false, 'message' => 'Could not resolve item.']); exit; }

    $item_id_final   = intval($item['id']);
    $item_name_final = mysqli_real_escape_string($con, $item['item_name']);
    $entry_date_safe = mysqli_real_escape_string($con, $entry_date);
    $remarks_safe    = mysqli_real_escape_string($con, $remarks);
    $added_by_safe   = mysqli_real_escape_string($con, $currentUserName);

    if ($entry_id > 0) {
        mysqli_query($con, "UPDATE hr_pantry_entries SET
            item_id=$item_id_final, item_name='$item_name_final', entry_date='$entry_date_safe',
            status='$status', amount=$amount, remarks='$remarks_safe'
            WHERE id=$entry_id");
        if (mysqli_error($con)) { echo json_encode(['success' => false, 'message' => 'DB Error: ' . mysqli_error($con)]); exit; }
        echo json_encode(['success' => true, 'mode' => 'updated', 'item_name' => $item['item_name']]);
    } else {
        mysqli_query($con, "INSERT INTO hr_pantry_entries
            (item_id, item_name, entry_date, status, amount, remarks, added_by)
            VALUES ($item_id_final, '$item_name_final', '$entry_date_safe', '$status', $amount, '$remarks_safe', '$added_by_safe')");
        if (mysqli_error($con)) { echo json_encode(['success' => false, 'message' => 'DB Error: ' . mysqli_error($con)]); exit; }
        echo json_encode(['success' => true, 'mode' => 'created', 'id' => mysqli_insert_id($con), 'item_name' => $item['item_name']]);
    }
    exit;
}

// =========================================================================
// AJAX: DELETE ENTRY
// =========================================================================
if (isset($_POST['ajax_delete_entry'])) {
    header('Content-Type: application/json');
    $entry_id = intval($_POST['entry_id']);
    mysqli_query($con, "DELETE FROM hr_pantry_entries WHERE id=$entry_id");
    echo json_encode(['success' => true]);
    exit;
}

// =========================================================================
// AJAX: GET SINGLE ENTRY (for edit modal prefill)
// =========================================================================
if (isset($_GET['ajax_get_entry'])) {
    header('Content-Type: application/json');
    $entry_id = intval($_GET['ajax_get_entry']);
    $q = mysqli_query($con, "SELECT * FROM hr_pantry_entries WHERE id=$entry_id LIMIT 1");
    $r = $q ? mysqli_fetch_assoc($q) : null;
    if (!$r) { echo json_encode(['success' => false, 'message' => 'Entry not found.']); exit; }
    echo json_encode(['success' => true, 'entry' => $r]);
    exit;
}

// =========================================================================
// FILTER VALUES (shared by page view + both exports)
// =========================================================================
$filter_period_type = isset($_GET['period_type']) ? $_GET['period_type'] : 'this_month';
$filter_item   = isset($_GET['f_item'])   ? $_GET['f_item']   : '';
$filter_status = isset($_GET['f_status']) ? $_GET['f_status'] : '';
$filter_search = isset($_GET['f_search']) ? trim($_GET['f_search']) : '';

switch ($filter_period_type) {
    case 'this_month': $period_start = date('Y-m-01'); $period_end = date('Y-m-t'); break;
    case 'last_month': $period_start = date('Y-m-01', strtotime('first day of last month')); $period_end = date('Y-m-t', strtotime('last day of last month')); break;
    case 'this_year': $period_start = date('Y-01-01'); $period_end = date('Y-12-31'); break;
    case 'specific_month':
        $sm = isset($_GET['specific_month']) && $_GET['specific_month'] !== '' ? $_GET['specific_month'] : date('Y-m');
        $period_start = $sm . '-01'; $period_end = date('Y-m-t', strtotime($period_start));
        break;
    case 'custom_range':
        $period_start = isset($_GET['range_start']) && $_GET['range_start'] !== '' ? $_GET['range_start'] : date('Y-m-01');
        $period_end   = isset($_GET['range_end'])   && $_GET['range_end']   !== '' ? $_GET['range_end']   : date('Y-m-t');
        break;
    case 'all_time': $period_start = ''; $period_end = ''; break;
    default: $period_start = date('Y-m-01'); $period_end = date('Y-m-t');
}
$period_label = ($filter_period_type === 'all_time') ? 'All Time' : (date('d M Y', strtotime($period_start)) . ' &ndash; ' . date('d M Y', strtotime($period_end)));

function build_pantry_where($con, $period_start, $period_end, $filter_period_type, $filter_item, $filter_status, $filter_search) {
    $where = "1=1";
    if ($filter_period_type !== 'all_time') {
        $where .= " AND entry_date BETWEEN '" . mysqli_real_escape_string($con, $period_start) . "' AND '" . mysqli_real_escape_string($con, $period_end) . "'";
    }
    if (!empty($filter_item))   $where .= " AND item_id=" . intval($filter_item);
    if (!empty($filter_status)) $where .= " AND status='" . mysqli_real_escape_string($con, $filter_status) . "'";
    if (!empty($filter_search)) {
        $s = mysqli_real_escape_string($con, $filter_search);
        $where .= " AND (item_name LIKE '%$s%' OR remarks LIKE '%$s%' OR added_by LIKE '%$s%')";
    }
    return $where;
}
$where_clause = build_pantry_where($con, $period_start, $period_end, $filter_period_type, $filter_item, $filter_status, $filter_search);

// =========================================================================
// EXPORT: EXCEL (.xls via HTML table — no external library required)
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] === 'excel') {
    $include_signature = isset($_GET['include_signature']) && $_GET['include_signature'] === '1';
    $q = mysqli_query($con, "SELECT * FROM hr_pantry_entries WHERE $where_clause ORDER BY entry_date DESC, id DESC");
    header('Content-Type: application/vnd.ms-excel; charset=utf-8');
    header('Content-Disposition: attachment; filename="pantry_export_' . date('Ymd_His') . '.xls"');
    header('Pragma: no-cache');
    header('Expires: 0');
    echo "\xEF\xBB\xBF"; // UTF-8 BOM so ₹ and names render correctly in Excel
    echo '<table border="1"><tr style="background:#0f2557;color:#fff;font-weight:bold;">';
    echo '<th>Date</th><th>Item</th><th>Status</th><th>Amount (INR)</th><th>Remarks</th><th>Added By</th><th>Logged At</th>';
    if ($include_signature) echo '<th>Signature</th>';
    echo '</tr>';
    $grand_total = 0;
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        $grand_total += floatval($r['amount']);
        echo '<tr>';
        echo '<td>' . htmlspecialchars(date('d-M-Y', strtotime($r['entry_date']))) . '</td>';
        echo '<td>' . htmlspecialchars($r['item_name']) . '</td>';
        echo '<td>' . htmlspecialchars($r['status']) . '</td>';
        echo '<td>' . number_format($r['amount'], 2) . '</td>';
        echo '<td>' . htmlspecialchars($r['remarks']) . '</td>';
        echo '<td>' . htmlspecialchars($r['added_by']) . '</td>';
        echo '<td>' . htmlspecialchars(date('d-M-Y h:i A', strtotime($r['created_at']))) . '</td>';
        if ($include_signature) echo '<td>&nbsp;</td>';
        echo '</tr>';
    }
    echo '<tr style="font-weight:bold;background:#f1f5f9;"><td colspan="3">Total</td><td>' . number_format($grand_total, 2) . '</td><td colspan="' . ($include_signature ? '3' : '3') . '"></td>' . ($include_signature ? '<td></td>' : '') . '</tr>';
    echo '</table>';
    exit;
}

// =========================================================================
// EXPORT: PDF
// Uses TCPDF if the library has been uploaded to /tcpdf on the server;
// otherwise falls back to a clean print-ready HTML page (same graceful-
// fallback convention used for SMTP in the Appraisal module) — the user
// hits Ctrl+P / "Save as PDF" from there.
// =========================================================================
if (isset($_GET['export']) && $_GET['export'] === 'pdf') {
    $include_signature = isset($_GET['include_signature']) && $_GET['include_signature'] === '1';
    $q = mysqli_query($con, "SELECT * FROM hr_pantry_entries WHERE $where_clause ORDER BY entry_date DESC, id DESC");
    $rows = [];
    $grand_total = 0;
    if ($q) while ($r = mysqli_fetch_assoc($q)) { $grand_total += floatval($r['amount']); $rows[] = $r; }

    $tcpdf_path = __DIR__ . '/tcpdf/tcpdf.php';
    if (file_exists($tcpdf_path)) {
        require_once($tcpdf_path);
        $pdf = new TCPDF('L', 'mm', 'A4', true, 'UTF-8', false);
        $pdf->SetCreator('Abra HR');
        $pdf->SetTitle('Pantry Export');
        $pdf->setPrintHeader(false);
        $pdf->setPrintFooter(false);
        $pdf->AddPage();
        $pdf->SetFont('helvetica', '', 10);
        $html = '<h2 style="color:#0f2557;">Office Pantry / Supplies Report</h2>';
        $html .= '<p style="color:#64748b;">Period: ' . strip_tags($period_label) . '</p>';
        $html .= '<table border="1" cellpadding="5"><tr style="background-color:#0f2557;color:#ffffff;">
            <th>Date</th><th>Item</th><th>Status</th><th>Amount (INR)</th><th>Remarks</th><th>Added By</th>' . ($include_signature ? '<th>Signature</th>' : '') . '</tr>';
        foreach ($rows as $r) {
            $html .= '<tr><td>' . htmlspecialchars(date('d-M-Y', strtotime($r['entry_date']))) . '</td>'
                   . '<td>' . htmlspecialchars($r['item_name']) . '</td>'
                   . '<td>' . htmlspecialchars($r['status']) . '</td>'
                   . '<td align="right">' . number_format($r['amount'], 2) . '</td>'
                   . '<td>' . htmlspecialchars($r['remarks']) . '</td>'
                   . '<td>' . htmlspecialchars($r['added_by']) . '</td>'
                   . ($include_signature ? '<td>&nbsp;</td>' : '')
                   . '</tr>';
        }
        $colspan_after_total = $include_signature ? 3 : 2;
        $html .= '<tr style="font-weight:bold;background-color:#f1f5f9;"><td colspan="3">Total</td><td align="right">' . number_format($grand_total, 2) . '</td><td colspan="' . $colspan_after_total . '"></td></tr>';
        $html .= '</table>';
        $pdf->writeHTML($html, true, false, true, false, '');
        $pdf->Output('pantry_export_' . date('Ymd_His') . '.pdf', 'D');
        exit;
    }

    // ---- Fallback: print-ready HTML (works with zero extra libraries) ----
    ?>
    <!DOCTYPE html><html><head><meta charset="utf-8"><title>Pantry Export</title>
    <style>
    body{font-family:Arial,Helvetica,sans-serif;padding:30px;color:#1e293b;}
    h2{color:#0f2557;margin-bottom:2px;}
    .sub{color:#64748b;font-size:13px;margin-bottom:18px;}
    table{width:100%;border-collapse:collapse;font-size:13px;}
    th,td{border:1px solid #cbd5e1;padding:8px 10px;text-align:left;}
    th{background:#0f2557;color:#fff;}
    tfoot td{font-weight:bold;background:#f1f5f9;}
    .sig-col{min-width:120px;}
    .no-print{margin-bottom:20px;}
    .no-print button{padding:10px 20px;background:#0f2557;color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;}
    @media print{ .no-print{display:none;} }
    </style></head><body>
    <div class="no-print">
        <button onclick="window.print()">Print / Save as PDF</button>
        <span style="color:#64748b;font-size:12px;margin-left:12px;">
            (Tip: upload the TCPDF library to <code>/tcpdf</code> on the server for one-click, no-print-dialog PDF downloads.)
        </span>
    </div>
    <h2>Office Pantry / Supplies Report</h2>
    <div class="sub">Period: <?php echo $period_label; ?> &middot; Generated <?php echo date('d M Y, h:i A'); ?></div>
    <table>
        <thead><tr><th>Date</th><th>Item</th><th>Status</th><th>Amount (₹)</th><th>Remarks</th><th>Added By</th><?php if ($include_signature): ?><th class="sig-col">Signature</th><?php endif; ?></tr></thead>
        <tbody>
        <?php foreach ($rows as $r): ?>
            <tr>
                <td><?php echo htmlspecialchars(date('d-M-Y', strtotime($r['entry_date']))); ?></td>
                <td><?php echo htmlspecialchars($r['item_name']); ?></td>
                <td><?php echo htmlspecialchars($r['status']); ?></td>
                <td><?php echo number_format($r['amount'], 2); ?></td>
                <td><?php echo htmlspecialchars($r['remarks']); ?></td>
                <td><?php echo htmlspecialchars($r['added_by']); ?></td>
                <?php if ($include_signature): ?><td class="sig-col">&nbsp;</td><?php endif; ?>
            </tr>
        <?php endforeach; ?>
        </tbody>
        <tfoot><tr><td colspan="3">Total</td><td><?php echo number_format($grand_total, 2); ?></td><td colspan="<?php echo $include_signature ? 2 : 1; ?>"></td><?php if ($include_signature): ?><td></td><?php endif; ?></tr></tfoot>
    </table>
    </body></html>
    <?php
    exit;
}

// =========================================================================
// MASTER DATA + MAIN LIST QUERY (page view)
// =========================================================================
$items_master = [];
$iq = mysqli_query($con, "SELECT id, item_name, unit FROM hr_pantry_items WHERE is_active=1 ORDER BY item_name ASC");
if ($iq) while ($i = mysqli_fetch_assoc($iq)) $items_master[] = $i;

$entries_q = mysqli_query($con, "SELECT * FROM hr_pantry_entries WHERE $where_clause ORDER BY entry_date DESC, id DESC");
$entries = [];
$stat_total_entries = 0; $stat_total_amount = 0; $stat_bought = 0; $stat_pending = 0;
if ($entries_q) {
    while ($r = mysqli_fetch_assoc($entries_q)) {
        $entries[] = $r;
        $stat_total_entries++;
        $stat_total_amount += floatval($r['amount']);
        if ($r['status'] === 'Bought') $stat_bought++; else $stat_pending++;
    }
}
$stat_items_count = count($items_master);

$dashboard_url = '/dashboard/index.php';
$status_options = ['Bought', 'Pending'];
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Office Pantry &amp; Supplies Tracker</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
* { margin:0; padding:0; box-sizing:border-box; }
html, body { overflow-x:hidden; max-width:100%; }
body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:30px 0; color:#334155; width:100%; }
.main-wrapper { max-width:1650px; margin:0 auto; padding:0 20px; width:100%; overflow-x:hidden; }

.header-card { background:linear-gradient(135deg,#0f2557 0%,#1a3fc4 100%); border-radius:12px; padding:25px 35px; margin-bottom:25px; box-shadow:0 4px 20px rgba(15,37,87,.35); color:white; }
.header-content { display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:15px; }
.header-title h1 { font-size:26px; font-weight:700; margin-bottom:5px; }
.header-title p { color:rgba(255,255,255,.9); font-size:13px; }
.header-actions { display:flex; gap:10px; flex-wrap:wrap; }
.btn-back, .btn-header-action { background:rgba(255,255,255,.18); color:white; padding:10px 20px; border-radius:10px; font-weight:600; text-decoration:none; border:1px solid rgba(255,255,255,.3); display:inline-flex; align-items:center; gap:8px; transition:.3s; cursor:pointer; font-size:14px; }
.btn-back:hover, .btn-header-action:hover { background:white; color:#0f2557; text-decoration:none; }
.btn-header-action.primary { background:#10b981; border-color:#10b981; }
.btn-header-action.primary:hover { background:#059669; color:#fff; border-color:#059669; }

.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px; margin-bottom:25px; }
.stat-card { background:white; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.06); display:flex; align-items:center; gap:14px; }
.stat-icon { width:46px; height:46px; border-radius:10px; display:flex; align-items:center; justify-content:center; font-size:21px; }
.stat-label { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; }
.stat-value { font-size:22px; font-weight:800; color:#1e293b; }

.filter-panel { background:white; padding:22px; border-radius:12px; margin-bottom:25px; border:2px solid #e2e8f0; box-shadow:0 2px 10px rgba(0,0,0,.06); }
.filter-panel h4 { color:#0f2557; font-weight:700; font-size:16px; margin-bottom:16px; }
.filter-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:16px; align-items:end; }
.filter-group label { font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; display:block; margin-bottom:6px; }
.filter-group select, .filter-group input { width:100%; padding:11px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px; font-weight:500; color:#1e293b; }
.filter-group select:focus, .filter-group input:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }
.period-extra { display:none; }
.btn-apply { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border:none; padding:11px 22px; border-radius:10px; font-weight:700; font-size:14px; cursor:pointer; box-shadow:0 4px 14px rgba(15,37,87,.35); width:100%; }
.btn-apply:hover { transform:translateY(-2px); }

.export-row { display:flex; gap:10px; margin-top:16px; flex-wrap:wrap; }
.btn-export { padding:10px 20px; border-radius:9px; font-weight:700; font-size:13px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; border:2px solid transparent; }
.btn-export-excel { background:#ecfdf5; color:#047857; border-color:#a7f3d0; }
.btn-export-excel:hover { background:#d1fae5; color:#047857; text-decoration:none; }
.btn-export-pdf { background:#fef2f2; color:#b91c1c; border-color:#fecaca; }
.btn-export-pdf:hover { background:#fee2e2; color:#b91c1c; text-decoration:none; }

.period-badge { display:inline-block; background:#e0e7ff; color:#0f2557; padding:6px 16px; border-radius:20px; font-weight:700; font-size:13px; margin-bottom:18px; border:1px solid #c7d2fe; }

.table-responsive { border-radius:12px; border:2px solid #e2e8f0; overflow-x:auto; background:white; box-shadow:0 2px 10px rgba(0,0,0,.06); width:100%; max-width:100%; }
table.pantry-table { width:100%; border-collapse:collapse; min-width:900px; }
table.pantry-table thead th { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; padding:14px 12px; font-weight:700; font-size:12px; text-transform:uppercase; letter-spacing:.4px; text-align:left; white-space:nowrap; }
table.pantry-table td { padding:14px 12px; border-bottom:1px solid #e2e8f0; font-size:13px; vertical-align:middle; }
table.pantry-table tbody tr:hover { background:#f8fafc; }

.badge-status { padding:4px 11px; border-radius:14px; font-size:11px; font-weight:700; white-space:nowrap; display:inline-block; border:1px solid; }
.amount-box { font-weight:700; color:#0f2557; }

.btn-sm-action { padding:7px 12px; border-radius:8px; font-size:12px; font-weight:700; border:none; cursor:pointer; display:inline-flex; align-items:center; gap:6px; margin:2px; }
.btn-edit { background:#fef3c7; color:#92400e; border:1px solid #fcd34d; }
.btn-edit:hover { background:#fde68a; }
.btn-del { background:#fee2e2; color:#991b1b; border:1px solid #fca5a5; }
.btn-del:hover { background:#fecaca; }

.modal-content { border-radius:16px; border:none; }
.modal-dialog { display:flex; align-items:center; min-height:calc(100% - 56px); }
.modal-header { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border-radius:16px 16px 0 0; padding:20px 28px; }
.modal-title { font-weight:700; font-size:18px; }
.modal-body { padding:28px; }
.close { color:white; opacity:.9; }

.form-group label { font-weight:700; color:#0f2557; font-size:12px; text-transform:uppercase; letter-spacing:.4px; display:block; margin-bottom:8px; }
.form-control-custom { width:100%; padding:12px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:15px; font-weight:600; color:#1e293b; }
.form-control-custom:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }

.status-toggle { display:flex; gap:10px; margin-bottom:0; }
.status-toggle label { flex:1; text-align:center; padding:12px; border:2px solid #e2e8f0; border-radius:10px; cursor:pointer; font-weight:700; color:#64748b; transition:.2s; }
.status-toggle input { display:none; }
.status-toggle label.active-bought { border-color:#10b981; background:#ecfdf5; color:#047857; }
.status-toggle label.active-pending { border-color:#ef4444; background:#fef2f2; color:#b91c1c; }

.btn-action-modal { padding:12px 26px; border-radius:10px; font-weight:700; font-size:14px; border:none; cursor:pointer; }
.btn-confirm { background:linear-gradient(135deg,#10b981,#059669); color:white; }

.toast-card { position:fixed; top:24px; right:-400px; width:340px; background:#fff; border-left:5px solid #10b981; border-radius:10px; box-shadow:0 10px 40px rgba(0,0,0,.18); padding:16px 20px; z-index:99999; transition:right .4s cubic-bezier(.175,.885,.32,1.275); display:flex; align-items:center; gap:14px; }
.toast-card.show { right:24px; }
.toast-card.error { border-left-color:#ef4444; }
.toast-icon { font-size:22px; color:#10b981; }
.toast-card.error .toast-icon { color:#ef4444; }
.toast-text { font-size:13px; font-weight:700; color:#0f2557; line-height:1.4; }

select.select2-hidden-accessible { width:100% !important; }
.select2-container .select2-selection--single { height:48px !important; border:2px solid #e2e8f0 !important; border-radius:10px !important; }
.select2-container--default .select2-selection--single .select2-selection__rendered { line-height:44px !important; padding-left:14px !important; font-weight:600 !important; color:#1e293b !important; }
.select2-container--default .select2-selection--single .select2-selection__arrow { height:44px !important; }
</style>
</head>
<body>
<div class="main-wrapper">

<div class="header-card">
  <div class="header-content">
    <div class="header-title">
      <h1><i class="fas fa-mug-hot"></i> Office Pantry &amp; Supplies Tracker</h1>
      <p>Log office consumables and track spend by day, item, and month</p>
    </div>
    <div class="header-actions">
      <button type="button" class="btn-header-action primary" onclick="openEntryModal()"><i class="fas fa-plus"></i> Log Item</button>
      
    </div>
  </div>
</div>

<!-- STATS -->
<div class="stats">
  <div class="stat-card">
    <div class="stat-icon" style="background:#eef2ff;color:#1a3fc4;"><i class="fas fa-list"></i></div>
    <div><div class="stat-label">Entries in Period</div><div class="stat-value"><?php echo $stat_total_entries; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#fffbeb;color:#d97706;"><i class="fas fa-rupee-sign"></i></div>
    <div><div class="stat-label">Total Spend</div><div class="stat-value">₹<?php echo number_format($stat_total_amount, 2); ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#ecfdf5;color:#059669;"><i class="fas fa-check-circle"></i></div>
    <div><div class="stat-label">Bought</div><div class="stat-value"><?php echo $stat_bought; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#fef2f2;color:#dc2626;"><i class="fas fa-hourglass-half"></i></div>
    <div><div class="stat-label">Pending</div><div class="stat-value"><?php echo $stat_pending; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#f1f5f9;color:#475569;"><i class="fas fa-box-open"></i></div>
    <div><div class="stat-label">Items Tracked</div><div class="stat-value"><?php echo $stat_items_count; ?></div></div>
  </div>
</div>

<!-- FILTERS -->
<div class="filter-panel">
  <h4><i class="fas fa-filter"></i> Filter Entries</h4>
  <form method="GET" id="filterForm">
    <div class="filter-row">
      <div class="filter-group">
        <label>Period</label>
        <select name="period_type" id="period_type" onchange="togglePeriodExtra()">
          <option value="this_month" <?php echo $filter_period_type=='this_month'?'selected':''; ?>>This Month</option>
          <option value="last_month" <?php echo $filter_period_type=='last_month'?'selected':''; ?>>Last Month</option>
          <option value="specific_month" <?php echo $filter_period_type=='specific_month'?'selected':''; ?>>Specific Month</option>
          <option value="custom_range" <?php echo $filter_period_type=='custom_range'?'selected':''; ?>>Custom Date Range</option>
          <option value="this_year" <?php echo $filter_period_type=='this_year'?'selected':''; ?>>This Year</option>
          <option value="all_time" <?php echo $filter_period_type=='all_time'?'selected':''; ?>>All Time (compare years too)</option>
        </select>
      </div>

      <div class="filter-group period-extra" id="specificMonthBox">
        <label>Select Month</label>
        <input type="month" name="specific_month" value="<?php echo isset($_GET['specific_month']) ? htmlspecialchars($_GET['specific_month']) : date('Y-m'); ?>">
      </div>
      <div class="filter-group" id="rangeStartBox">
        <label>From Date</label>
        <input type="date" name="range_start" id="range_start" value="<?php echo isset($_GET['range_start']) ? htmlspecialchars($_GET['range_start']) : date('Y-m-01'); ?>" onchange="switchToCustomRange()">
      </div>
      <div class="filter-group" id="rangeEndBox">
        <label>To Date</label>
        <input type="date" name="range_end" id="range_end" value="<?php echo isset($_GET['range_end']) ? htmlspecialchars($_GET['range_end']) : date('Y-m-t'); ?>" onchange="switchToCustomRange()">
      </div>

      <div class="filter-group">
        <label>Item</label>
        <select name="f_item" class="select2">
          <option value="">All Items</option>
          <?php foreach ($items_master as $im): ?>
          <option value="<?php echo intval($im['id']); ?>" <?php echo ($filter_item==$im['id'])?'selected':''; ?>><?php echo htmlspecialchars($im['item_name']); ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Status</label>
        <select name="f_status" class="select2">
          <option value="">All Statuses</option>
          <?php foreach ($status_options as $so): ?>
          <option value="<?php echo $so; ?>" <?php echo ($filter_status==$so)?'selected':''; ?>><?php echo $so; ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Search</label>
        <input type="text" name="f_search" placeholder="Item, remarks, added by..." value="<?php echo htmlspecialchars($filter_search); ?>">
      </div>

      <div class="filter-group">
        <button type="submit" class="btn-apply"><i class="fas fa-search"></i> Apply Filters</button>
      </div>
      <div class="filter-group">
        <button type="button" class="btn-apply" style="background:#fff;color:#64748b;border:2px solid #e2e8f0;box-shadow:none;" onclick="window.location.href=window.location.pathname;"><i class="fas fa-undo"></i> Reset Filters</button>
      </div>
    </div>
  </form>

  <div class="export-row">
    <a href="#" id="exportExcelBtn" class="btn-export btn-export-excel"><i class="fas fa-file-excel"></i> Export Excel</a>
    <a href="#" id="exportPdfBtn" class="btn-export btn-export-pdf" target="_blank"><i class="fas fa-file-pdf"></i> Export PDF</a>
  </div>
</div>

<div class="period-badge"><i class="fas fa-calendar-alt"></i> Showing: <?php echo $period_label; ?></div>

<!-- ENTRIES TABLE -->
<div class="table-responsive">
<table class="pantry-table">
<thead>
<tr>
  <th>Date</th>
  <th>Item</th>
  <th>Status</th>
  <th>Amount</th>
  <th>Remarks</th>
  <th>Added By</th>
  <th style="text-align:right;">Actions</th>
</tr>
</thead>
<tbody>
<?php if (count($entries) > 0): foreach ($entries as $e):
    $st = pantry_status_style($e['status']);
?>
<tr>
  <td><?php echo date('d M Y', strtotime($e['entry_date'])); ?></td>
  <td style="font-weight:700;color:#1e293b;"><?php echo htmlspecialchars($e['item_name']); ?></td>
  <td><span class="badge-status" style="background:<?php echo $st['bg']; ?>;color:<?php echo $st['c']; ?>;border-color:<?php echo $st['border']; ?>;"><?php echo $st['icon'] . ' ' . htmlspecialchars($e['status']); ?></span></td>
  <td class="amount-box">₹<?php echo number_format($e['amount'], 2); ?></td>
  <td style="color:#64748b;"><?php echo htmlspecialchars($e['remarks']); ?></td>
  <td style="color:#64748b;font-size:12px;"><?php echo htmlspecialchars($e['added_by']); ?></td>
  <td style="text-align:right;white-space:nowrap;">
    <button type="button" class="btn-sm-action btn-edit" onclick="openEntryModal(<?php echo intval($e['id']); ?>)"><i class="fas fa-edit"></i> Edit</button>
    <button type="button" class="btn-sm-action btn-del" onclick="deleteEntry(<?php echo intval($e['id']); ?>)"><i class="fas fa-trash"></i> Delete</button>
  </td>
</tr>
<?php endforeach; else: ?>
<tr><td colspan="7" style="text-align:center;padding:40px;color:#94a3b8;">No entries match the selected filters.</td></tr>
<?php endif; ?>
</tbody>
</table>
</div>

</div>

<!-- =========================================================================
     LOG / EDIT ENTRY MODAL
========================================================================== -->
<div class="modal fade" id="entryModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="entryModalTitle"><i class="fas fa-plus"></i> Log Item</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="m_entry_id" value="">

        <div class="form-group">
          <div style="display:flex;justify-content:space-between;align-items:center;">
            <label style="margin-bottom:0;">Item</label>
            <button type="button" id="toggleNewItemBtn" onclick="toggleNewItemRow()" style="background:none;border:none;color:#1a3fc4;font-weight:700;font-size:12px;cursor:pointer;padding:0;">
              <i class="fas fa-plus-circle"></i> Add New Item
            </button>
          </div>
          <select id="m_item" class="form-control-custom select2" style="width:100%;margin-top:8px;"></select>

          <div id="newItemRow" style="display:none;margin-top:10px;gap:8px;">
            <div style="display:flex;gap:8px;">
              <input type="text" id="new_item_name" class="form-control-custom" placeholder="New item name, e.g. Detergent" style="flex:1;">
              <button type="button" class="btn-action-modal btn-confirm" style="padding:0 18px;white-space:nowrap;" onclick="addNewItemInline()"><i class="fas fa-check"></i> Add</button>
            </div>
          </div>
        </div>

        <div class="form-group">
          <label>Date</label>
          <input type="date" id="m_entry_date" class="form-control-custom">
        </div>

        <div class="form-group">
          <label>Status</label>
          <div class="status-toggle">
            <label id="statusLabelBought" class="active-bought" onclick="setEntryStatus('Bought')"><span><i class="fas fa-check"></i> Bought</span></label>
            <label id="statusLabelPending" onclick="setEntryStatus('Pending')"><span><i class="fas fa-hourglass-half"></i> Pending</span></label>
          </div>
          <input type="hidden" id="m_status" value="Bought">
        </div>

        <div class="form-group">
          <label>Amount (₹)</label>
          <input type="number" step="0.01" min="0" id="m_amount" class="form-control-custom" placeholder="e.g. 60">
        </div>

        <div class="form-group">
          <label>Remarks (Optional)</label>
          <input type="text" id="m_remarks" class="form-control-custom" placeholder="e.g. brought 2 packets">
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-action-modal btn-confirm" onclick="saveEntry()"><i class="fas fa-save"></i> Save Entry</button>
      </div>
    </div>
  </div>
</div>

<!-- =========================================================================
     SIGNATURE COLUMN CONFIRMATION MODAL (shown before export)
========================================================================== -->
<div class="modal fade" id="signatureModal" tabindex="-1">
  <div class="modal-dialog" style="max-width:460px;">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-signature"></i> Export Options</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="text-align:center;padding:32px 28px;">
        <div style="width:64px;height:64px;border-radius:50%;background:#eef2ff;display:flex;align-items:center;justify-content:center;margin:0 auto 18px;">
          <i class="fas fa-pen-fancy" style="font-size:26px;color:#1a3fc4;"></i>
        </div>
        <div style="font-size:16px;font-weight:700;color:#0f2557;margin-bottom:8px;">Include a Signature column?</div>
        <div style="font-size:13px;color:#64748b;line-height:1.6;">Adds a blank Signature column to every row in the export, for physical sign-off on a printed copy.</div>
      </div>
      <div class="modal-footer" style="justify-content:center;gap:12px;border-top:1px solid #e2e8f0;padding:18px 28px;">
        <button type="button" class="btn-action-modal" style="background:#f1f5f9;color:#475569;" onclick="proceedExport(false)"><i class="fas fa-times"></i> Without Signature</button>
        <button type="button" class="btn-action-modal btn-confirm" onclick="proceedExport(true)"><i class="fas fa-check"></i> Include Signature</button>
      </div>
    </div>
  </div>
</div>

<!-- Toast Card -->
<div id="toastCard" class="toast-card">
  <i id="toastIcon" class="fas fa-check-circle toast-icon"></i>
  <div id="toastText" class="toast-text">Message</div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/popper.js@1.16.1/dist/umd/popper.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
var ITEMS_MASTER = <?php echo json_encode($items_master); ?>;

$(document).ready(function(){
  $('.filter-panel .select2').select2({ width:'100%', placeholder:'Select...', allowClear:true });
  togglePeriodExtra();
  buildExportLinks();
  $('#filterForm select, #filterForm input').on('change', buildExportLinks);
});

function togglePeriodExtra() {
  var type = $('#period_type').val();
  $('#specificMonthBox').hide();
  if (type === 'specific_month') $('#specificMonthBox').show();
}

// From/To calendar is always visible now — picking a date there means "use this custom range"
function switchToCustomRange() {
  $('#period_type').val('custom_range');
  togglePeriodExtra();
}

// Build the export links from the CURRENT filter form state (so exports always match what's on screen)
function buildExportLinks() {
  var params = $('#filterForm').serialize();
  $('#exportExcelBtn').attr('href', '?' + params + '&export=excel');
  $('#exportPdfBtn').attr('href', '?' + params + '&export=pdf');
}

// Ask whether to include a blank Signature column (for physical sign-off) before exporting — styled modal instead of confirm()
var pendingExportType = null;

function askIncludeSignature(exportType) {
  pendingExportType = exportType;
  buildExportLinks();
  $('#signatureModal').modal('show');
}

function proceedExport(withSignature) {
  $('#signatureModal').modal('hide');
  var btnId = pendingExportType === 'pdf' ? '#exportPdfBtn' : '#exportExcelBtn';
  var url = $(btnId).attr('href') + '&include_signature=' + (withSignature ? '1' : '0');
  if (pendingExportType === 'pdf') {
    window.open(url, '_blank');
  } else {
    window.location.href = url;
  }
  pendingExportType = null;
}

$('#exportExcelBtn').on('click', function(e){
  e.preventDefault();
  askIncludeSignature('excel');
});

$('#exportPdfBtn').on('click', function(e){
  e.preventDefault();
  askIncludeSignature('pdf');
});

// ---- ITEM SELECT2 (with "create new item" tagging) ----
function initItemSelect2(selectedId, selectedName) {
  var $sel = $('#m_item');
  $sel.empty();
  $sel.append(new Option('', '', true, !selectedId)); // blank placeholder option so nothing is auto-picked
  ITEMS_MASTER.forEach(function(it) {
    $sel.append(new Option(it.item_name, it.id, false, false));
  });
  if (selectedId && !ITEMS_MASTER.find(function(it){ return it.id == selectedId; })) {
    $sel.append(new Option(selectedName, selectedId, true, true));
  }
  $sel.select2({
    width: '100%',
    dropdownParent: $('#entryModal'),
    placeholder: 'Select an item...',
    allowClear: true,
    tags: true,
    createTag: function (params) {
      var term = $.trim(params.term);
      if (term === '') return null;
      return { id: 'new:' + term, text: term + ' (new item)', newTag: true };
    }
  });
  if (selectedId) $sel.val(String(selectedId)).trigger('change');

  $('#newItemRow').hide();
  $('#new_item_name').val('');
}

// ---- explicit "Add New Item" control ----
function toggleNewItemRow() {
  var $row = $('#newItemRow');
  if ($row.is(':visible')) { $row.hide(); return; }
  $row.css('display', 'block');
  $('#new_item_name').val('').focus();
}

function addNewItemInline() {
  var name = $.trim($('#new_item_name').val());
  if (name === '') { showToast('Please type an item name.', true); return; }

  $.post(window.location.pathname, { ajax_add_item: 1, item_name: name }, function(resp) {
    if (!resp.success) { showToast(resp.message || 'Could not add item.', true); return; }

    if (!ITEMS_MASTER.find(function(it){ return it.id == resp.id; })) {
      ITEMS_MASTER.push({ id: resp.id, item_name: resp.item_name });
    }
    var $sel = $('#m_item');
    if ($sel.find('option[value="' + resp.id + '"]').length === 0) {
      $sel.append(new Option(resp.item_name, resp.id, false, false));
    }
    $sel.val(String(resp.id)).trigger('change');

    $('#newItemRow').hide();
    $('#new_item_name').val('');
    showToast('"' + resp.item_name + '" added and selected.');
  }, 'json').fail(function(){ showToast('Server error while adding item.', true); });
}

// ---- ENTRY MODAL ----
function setEntryStatus(status) {
  $('#m_status').val(status);
  $('#statusLabelBought').toggleClass('active-bought', status === 'Bought');
  $('#statusLabelPending').toggleClass('active-pending', status === 'Pending');
}

function openEntryModal(entryId) {
  $('#m_entry_id').val('');
  $('#m_entry_date').val(new Date().toISOString().slice(0,10));
  $('#m_amount').val('');
  $('#m_remarks').val('');
  setEntryStatus('Bought');
  initItemSelect2(null, null);
  $('#entryModalTitle').html('<i class="fas fa-plus"></i> Log Item');

  if (entryId) {
    $.getJSON(window.location.pathname, { ajax_get_entry: entryId }, function(resp) {
      if (!resp.success) { showToast(resp.message || 'Could not load entry.', true); return; }
      var e = resp.entry;
      $('#entryModalTitle').html('<i class="fas fa-edit"></i> Edit Entry');
      $('#m_entry_id').val(e.id);
      $('#m_entry_date').val(e.entry_date);
      $('#m_amount').val(e.amount);
      $('#m_remarks').val(e.remarks);
      setEntryStatus(e.status);
      initItemSelect2(e.item_id, e.item_name);
      $('#entryModal').modal('show');
    });
  } else {
    $('#entryModal').modal('show');
  }
}

function saveEntry() {
  var itemVal = $('#m_item').val();
  var itemText = $('#m_item').find(':selected').text();
  var itemId = 0, itemName = '';
  if (itemVal && String(itemVal).indexOf('new:') === 0) {
    itemName = String(itemVal).substring(4);
  } else {
    itemId = parseInt(itemVal) || 0;
    itemName = itemText;
  }

  var date = $('#m_entry_date').val();
  var amount = $('#m_amount').val();
  if (!itemVal) { showToast('Please select or type an item.', true); return; }
  if (!date) { showToast('Please pick a date.', true); return; }
  if (amount === '' || isNaN(parseFloat(amount)) || parseFloat(amount) < 0) { showToast('Please enter a valid amount.', true); return; }

  $.post(window.location.pathname, {
    ajax_save_entry: 1,
    entry_id: $('#m_entry_id').val(),
    item_id: itemId,
    item_name: itemName,
    entry_date: date,
    status: $('#m_status').val(),
    amount: amount,
    remarks: $('#m_remarks').val()
  }, function(resp) {
    if (resp.success) {
      $('#entryModal').modal('hide');
      showToast('Entry saved for ' + resp.item_name + '.');
      setTimeout(function(){ window.location.reload(); }, 700);
    } else {
      showToast(resp.message || 'Could not save entry.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while saving entry.', true); });
}

function deleteEntry(id) {
  if (!confirm('Delete this entry permanently?')) return;
  $.post(window.location.pathname, { ajax_delete_entry: 1, entry_id: id }, function(resp) {
    if (resp.success) {
      showToast('Entry deleted.');
      setTimeout(function(){ window.location.reload(); }, 600);
    } else {
      showToast(resp.message || 'Could not delete entry.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while deleting entry.', true); });
}

// ---- TOAST ----
function showToast(msg, isError) {
  var tc = document.getElementById('toastCard');
  var ti = document.getElementById('toastIcon');
  var tt = document.getElementById('toastText');
  tc.className = 'toast-card ' + (isError ? 'error' : '') + ' show';
  ti.className = isError ? 'fas fa-exclamation-circle toast-icon' : 'fas fa-check-circle toast-icon';
  tt.innerHTML = msg;
  setTimeout(function(){ tc.classList.remove('show'); }, 4500);
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