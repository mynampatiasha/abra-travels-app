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
require_once('library.php');
require_once('funciones.php');
$con = conexion();
if (!$con) die("<div class='alert alert-danger'>Database connection failed.</div>");
isUser();
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');


// =========================================================================
// GOOGLE "HOLIDAYS IN INDIA" CALENDAR — public .ics feed, no API key needed.
// Cached locally for a week so we don't hit Google on every modal open.
// =========================================================================
function getIndianHolidays() {
    $cacheFile = __DIR__ . '/uploads/google_holidays_cache.json';
    $cacheMaxAge = 7 * 24 * 60 * 60;

    if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < $cacheMaxAge) {
        $cached = json_decode(file_get_contents($cacheFile), true);
        if (is_array($cached)) return $cached;
    }

    $icsUrl = 'https://calendar.google.com/calendar/ical/en.indian%23holiday%40group.v.calendar.google.com/public/basic.ics';
    $ics = false;

    if (function_exists('curl_init')) {
        $ch = curl_init($icsUrl);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
        $ics = curl_exec($ch);
        curl_close($ch);
    }
    if ($ics === false || $ics === '') {
        $ctx = stream_context_create(['http' => ['timeout' => 8]]);
        $ics = @file_get_contents($icsUrl, false, $ctx);
    }

    $holidays = [];
    if ($ics) {
        preg_match_all('/BEGIN:VEVENT(.*?)END:VEVENT/s', $ics, $events);
        foreach ($events[1] as $eventBlock) {
            if (preg_match('/DTSTART;VALUE=DATE:(\d{8})/', $eventBlock, $dm)) {
                $formatted = substr($dm[1], 0, 4) . '-' . substr($dm[1], 4, 2) . '-' . substr($dm[1], 6, 2);
                $summary = '';
                if (preg_match('/SUMMARY:(.*)/', $eventBlock, $sm)) $summary = trim($sm[1]);
                $holidays[$formatted] = $summary;
            }
        }
        if (!empty($holidays)) {
            $dir = dirname($cacheFile);
            if (!is_dir($dir)) @mkdir($dir, 0755, true);
            @file_put_contents($cacheFile, json_encode($holidays));
        }
    } elseif (file_exists($cacheFile)) {
        // Fetch failed — fall back to whatever we last cached rather than nothing.
        $stale = json_decode(file_get_contents($cacheFile), true);
        if (is_array($stale)) $holidays = $stale;
    }

    return $holidays;
}

// Counts calendar days from $startDateStr to $endDateStr (inclusive),
// excluding Sundays and any date present in $holidays.
function countWorkingDaysExclHolidays($startDateStr, $endDateStr, $holidays) {
    $start = new DateTime(date('Y-m-d', strtotime($startDateStr)));
    $end   = new DateTime(date('Y-m-d', strtotime($endDateStr)));
    if ($end < $start) return 0;
    $end->modify('+1 day');
    $period = new DatePeriod($start, new DateInterval('P1D'), $end);
    $count = 0;
    foreach ($period as $d) {
        if ($d->format('N') == 7) continue;
        if (isset($holidays[$d->format('Y-m-d')])) continue;
        $count++;
    }
    return $count;
}

$emp_id  = intval($_GET['emp_id']  ?? 0);
$dept_id = intval($_GET['dept_id'] ?? 0);
$pos_id  = intval($_GET['pos_id']  ?? 0);
$context = $_GET['context'] ?? 'cross_training'; // 'cross_training' | 'oje' | 'recert'
$cycle   = intval($_GET['cycle'] ?? 0);

if (!$emp_id || !$dept_id) { echo '<div class="alert alert-warning">Invalid request.</div>'; exit; }

// Employee
$empRow = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$emp_id LIMIT 1"));
if (!$empRow) { echo '<div class="alert alert-warning">Employee not found.</div>'; exit; }

// Company settings
$co_settings = null;
if (!empty($empRow['company_name'])) {
    $cn = mysqli_real_escape_string($con, $empRow['company_name']);
    $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_name='$cn' LIMIT 1"));
}
if (!$co_settings) $co_settings = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_offer_company_settings ORDER BY id ASC LIMIT 1"));

// Dept/Pos names
$deptName = ''; $posName = 'All Positions';
$dn = mysqli_fetch_assoc(mysqli_query($con, "SELECT name FROM hr_departments WHERE id=$dept_id"));
if ($dn) {
    $deptName = $dn['name'];
} elseif (!empty($empRow['department']) && !is_numeric($empRow['department'])) {
    $deptName = $empRow['department'];
}
if ($pos_id > 0) {
    $pn = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=$pos_id"));
    if ($pn) $posName = $pn['title'];
} elseif (!empty($empRow['position']) && !is_numeric($empRow['position'])) {
    $posName = $empRow['position'];
}

// Progress
$progress = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_employee_progress WHERE employee_id=$emp_id AND department_id=$dept_id AND position_id=$pos_id LIMIT 1"));

// Config
$config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_config WHERE department_id=$dept_id AND position_id=$pos_id LIMIT 1"));
if (!$config) $config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_config WHERE department_id=$dept_id AND position_id=0 LIMIT 1"));
$training_pass_pct = floatval($config['training_pass_percent'] ?? 95);
$oje_pass_pct = floatval($config['oje_pass_percent'] ?? 95);
$max_attempts = intval($config['max_attempts'] ?? 3);

// Test attempts
$trainingAttempts = [];
$ta = mysqli_query($con, "SELECT * FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND department_id=$dept_id AND position_id=$pos_id AND type='training' ORDER BY attempt_number ASC");
if ($ta) while ($r = mysqli_fetch_assoc($ta)) $trainingAttempts[] = $r;

$ojeAttempts = [];
$oa = mysqli_query($con, "SELECT * FROM hr_oje_test_attempts WHERE employee_id=$emp_id AND department_id=$dept_id AND position_id=$pos_id AND type='oje' ORDER BY attempt_number ASC");
if ($oa) while ($r = mysqli_fetch_assoc($oa)) $ojeAttempts[] = $r;

// Date of the attempt that actually passed each test — this is what the
// stepper should show, not the stage-transition timestamp (which only marks
// when the employee became eligible to start that test, not when they took it).
$trainingPassedAt = null;
foreach ($trainingAttempts as $a) { if ($a['passed']) { $trainingPassedAt = $a['attempted_at']; break; } }
$ojePassedAt = null;
foreach ($ojeAttempts as $a) { if ($a['passed']) { $ojePassedAt = $a['attempted_at']; break; } }

$stageOrder = ['training'=>1,'training_test'=>2,'oje_reading'=>3,'oje_test'=>4,'certified'=>5,'failed'=>0];
$currentStage = $progress ? ($stageOrder[$progress['stage']] ?? 1) : 0;

$certNumber = '';
if ($progress && $progress['stage'] === 'certified' && !empty($progress['certified_at'])) {
    $certNumber = 'CERT-' . date('Y', strtotime($progress['certified_at'])) . '-' . str_pad($emp_id, 5, '0', STR_PAD_LEFT);
}

// Recertification attempts (only relevant when context = recert, but harmless to fetch always)
$recertAttempts = [];
$recertWhere = "employee_id=$emp_id AND department_id=$dept_id AND position_id=$pos_id";
$rcq = mysqli_query($con, "SELECT * FROM hr_oje_recert_attempts WHERE $recertWhere ORDER BY cycle_number ASC, attempt_number ASC");
if ($rcq) while ($r = mysqli_fetch_assoc($rcq)) $recertAttempts[] = $r;

$recertPassedRow = null;
foreach (array_reverse($recertAttempts) as $r) { if ($r['passed']) { $recertPassedRow = $r; break; } }
?>

<!-- Stepper -->
<?php if ($context !== 'recert'): ?>
<div style="display:flex;align-items:flex-start;background:#f8faff;border-radius:12px;padding:20px 16px;margin-bottom:24px;overflow-x:auto;">
<?php
$steps = [1=>'Training',2=>'Training Test',3=>'OJE Reading',4=>'OJE Test',5=>'Certified'];
$stepIcons = [1=>'fa-book-open',2=>'fa-question-circle',3=>'fa-briefcase',4=>'fa-clipboard-check',5=>'fa-award'];
$stepDateFields = [1=>'training_started_at',2=>'training_completed_at',3=>'oje_started_at',4=>'oje_reading_done_at',5=>'certified_at'];
foreach ($steps as $num => $label):
    if ($progress && $progress['stage'] === 'certified') $state = $num <= 5 ? 'done' : 'locked';
    elseif ($num < $currentStage) $state = 'done';
    elseif ($num == $currentStage) $state = 'current';
    else $state = 'locked';
    $icon = $state === 'done' ? 'fa-check' : ($state === 'locked' ? 'fa-lock' : $stepIcons[$num]);
    $circleStyle = $state === 'done' ? 'background:#10b981;border-color:#10b981;color:#fff;' : ($state === 'current' ? 'background:#1a3fc4;border-color:#1a3fc4;color:#fff;' : 'background:#f8fafc;border-color:#e2e8f0;color:#94a3b8;');
    $labelColor = $state === 'done' ? '#10b981' : ($state === 'current' ? '#1a3fc4' : '#94a3b8');
    $lineColor = $num > 1 ? ($state === 'done' || ($num <= $currentStage) ? '#10b981' : '#e2e8f0') : 'transparent';
    if ($num === 2 && $trainingPassedAt) {
        $stepDate = $trainingPassedAt;
    } elseif ($num === 4 && $ojePassedAt) {
        $stepDate = $ojePassedAt;
    } else {
        $stepDate = $progress[$stepDateFields[$num]] ?? null;
    }
?>
<div style="flex:1;min-width:100px;text-align:center;position:relative;">
  <div style="position:absolute;top:23px;left:-50%;width:100%;height:3px;background:<?php echo $lineColor; ?>;z-index:1;<?php echo $num===1?'display:none':''; ?>"></div>
  <div style="width:46px;height:46px;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 8px;font-size:17px;border:3px solid;position:relative;z-index:2;<?php echo $circleStyle; ?>">
    <i class="fas <?php echo $icon; ?>"></i>
  </div>
  <div style="font-size:11px;font-weight:700;color:<?php echo $labelColor; ?>;"><?php echo $label; ?></div>
  <?php if ($stepDate): ?>
  <div style="font-size:10px;font-weight:600;color:#94a3b8;margin-top:2px;"><?php echo date('d M Y', strtotime($stepDate)); ?></div>
  <?php endif; ?>
</div>
<?php endforeach; ?>
</div>
<?php
if ($progress && $progress['stage'] === 'certified' && !empty($progress['training_started_at']) && !empty($progress['certified_at'])) {
    $googleHolidays = getIndianHolidays();
    $completionDays = countWorkingDaysExclHolidays($progress['training_started_at'], $progress['certified_at'], $googleHolidays);
    ?>
    <div style="background:#ecfdf5;border:1px solid #86efac;border-radius:10px;padding:12px 18px;margin-bottom:24px;text-align:center;">
        <span style="font-weight:800;color:#065f46;font-size:14px;"><i class="fas fa-bolt mr-2"></i>Completed Training &amp; OJE in <?php echo $completionDays; ?> working day<?php echo $completionDays == 1 ? '' : 's'; ?></span>
        <div style="font-size:11px;color:#166534;margin-top:2px;">Sundays and Indian public holidays excluded</div>
    </div>
    <?php
}
?>
<?php endif; ?>

<?php if (!$progress && $context !== 'recert'): ?>
<div class="alert alert-info">This employee has no progress recorded for this department/position yet.</div>
<?php endif; ?>

<?php if ($progress && $context !== 'recert'): ?>
<?php if (!empty($trainingAttempts) || !empty($ojeAttempts)): ?>
<div style="display:flex;justify-content:flex-end;gap:8px;margin-bottom:10px;flex-wrap:wrap;">
  <button type="button" class="btn btn-sm" style="background:#f1f5f9;border:1px solid #cbd5e1;color:#334155;font-weight:700;" onclick="downloadSelectedAttemptsPDF()"><i class="fas fa-file-pdf mr-1"></i> Download Selected</button>
  <button type="button" class="btn btn-sm" style="background:#0f2557;border:none;color:#fff;font-weight:700;" onclick="downloadAllAttemptsPDF()"><i class="fas fa-file-pdf mr-1"></i> Download All</button>
</div>
<?php endif; ?>
<!-- Training Test Scores -->
<div style="background:#fff;border:1.5px solid #e0e7ff;border-radius:12px;padding:20px;margin-bottom:16px;">
  <h6 style="font-weight:800;color:#0f2557;margin-bottom:14px;"><i class="fas fa-question-circle mr-2 text-warning"></i>Training Test   Score History</h6>
  <?php if (empty($trainingAttempts)): ?>
    <p style="color:#94a3b8;font-size:13px;margin:0;">Not attempted yet.</p>
  <?php else: ?>
    <table style="width:100%;border-collapse:collapse;">
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;width:34px;"></th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">#</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Date</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Score</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Result</th>
      </tr></thead>
      <tbody>
        <?php foreach ($trainingAttempts as $a): ?>
        <tr>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;"><input type="checkbox" class="attempt-select" data-id="<?php echo $a['id']; ?>" data-type="training"></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo $a['attempt_number']; ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:700;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($a['percentage'],1); ?>%</td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:800;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;">
            <?php echo $a['passed'] ? '<i class="fas fa-check-circle mr-1"></i>Passed' : '<i class="fas fa-times-circle mr-1"></i>Failed'; ?>
            <button class="btn btn-sm ml-3" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;font-size:11px;padding:2px 8px;" onclick="viewAttemptAnswers(<?php echo $a['id']; ?>, 'training')"><i class="fas fa-eye mr-1"></i> View</button>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  <?php endif; ?>
</div>

<!-- OJE Test Scores -->
<div style="background:#fff;border:1.5px solid #e0e7ff;border-radius:12px;padding:20px;margin-bottom:16px;">
  <h6 style="font-weight:800;color:#0f2557;margin-bottom:14px;"><i class="fas fa-clipboard-check mr-2 text-success"></i>OJE Test   Score History</h6>
  <?php if (empty($ojeAttempts)): ?>
    <p style="color:#94a3b8;font-size:13px;margin:0;">Not attempted yet.</p>
  <?php else: ?>
    <table style="width:100%;border-collapse:collapse;">
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;width:34px;"></th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">#</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Date</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Score</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Result</th>
      </tr></thead>
      <tbody>
        <?php foreach ($ojeAttempts as $a): ?>
        <tr>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;"><input type="checkbox" class="attempt-select" data-id="<?php echo $a['id']; ?>" data-type="oje"></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo $a['attempt_number']; ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:700;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($a['percentage'],1); ?>%</td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:800;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;">
            <?php echo $a['passed'] ? '<i class="fas fa-check-circle mr-1"></i>Passed' : '<i class="fas fa-times-circle mr-1"></i>Failed'; ?>
            <button class="btn btn-sm ml-3" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;font-size:11px;padding:2px 8px;" onclick="viewAttemptAnswers(<?php echo $a['id']; ?>, 'oje')"><i class="fas fa-eye mr-1"></i> View</button>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  <?php endif; ?>
</div>
<?php endif; ?>
<?php
$hasCurrentCycle = false;
foreach ($recertAttempts as $a) {
    if ($a['cycle_number'] == $cycle) $hasCurrentCycle = true;
}
?>
<!-- Recertification Score History (only shown for recert context) -->
<?php if ($context === 'recert'): ?>
<?php if (!empty($recertAttempts)): ?>
<div style="display:flex;justify-content:flex-end;gap:8px;margin-bottom:10px;flex-wrap:wrap;">
  <button type="button" class="btn btn-sm" style="background:#f1f5f9;border:1px solid #cbd5e1;color:#334155;font-weight:700;" onclick="downloadSelectedAttemptsPDF()"><i class="fas fa-file-pdf mr-1"></i> Download Selected</button>
  <button type="button" class="btn btn-sm" style="background:#0f2557;border:none;color:#fff;font-weight:700;" onclick="downloadAllAttemptsPDF()"><i class="fas fa-file-pdf mr-1"></i> Download All</button>
</div>
<?php endif; ?>
<div style="background:#fff;border:1.5px solid #e0e7ff;border-radius:12px;padding:20px;margin-bottom:16px;">
  <h6 style="font-weight:800;color:#0f2557;margin-bottom:14px;"><i class="fas fa-sync-alt mr-2 text-warning"></i>Recertification   Score History</h6>
  <?php if (empty($recertAttempts) && $cycle == 0): ?>
    <p style="color:#94a3b8;font-size:13px;margin:0;">Not attempted yet.</p>
  <?php else: ?>
    <table style="width:100%;border-collapse:collapse;">
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;width:34px;"></th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Cycle</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">#</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Date</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Score</th>
        <th style="background:#f0f4f8;padding:8px 12px;font-size:11px;text-transform:uppercase;color:#0f2557;font-weight:800;text-align:left;">Result</th>
      </tr></thead>
      <tbody>
        <?php foreach ($recertAttempts as $a): ?>
        <tr>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;"><input type="checkbox" class="attempt-select" data-id="<?php echo $a['id']; ?>" data-type="recert"></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;">Cycle <?php echo $a['cycle_number']; ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo $a['attempt_number']; ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;"><?php echo date('d M Y, h:i A', strtotime($a['attempted_at'])); ?></td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:700;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;"><?php echo number_format($a['percentage'],1); ?>%</td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:800;color:<?php echo $a['passed']?'#065f46':'#991b1b'; ?>;">
            <?php if ($a['passed']): ?>
              <span style="color:#065f46;"><i class="fas fa-check-circle mr-1"></i>Passed</span>
              <div style="margin-top:4px;"><a href="javascript:void(0)" onclick="$('#recert-cert-modal-<?php echo $a['id']; ?>').slideToggle()" style="font-size:11px;text-decoration:underline;font-weight:700;color:#1a3fc4;">View Certificate</a></div>
            <?php else: ?>
              <span style="color:#991b1b;"><i class="fas fa-times-circle mr-1"></i>Failed</span>
            <?php endif; ?>
            <button class="btn btn-sm ml-3" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;font-size:11px;padding:2px 8px;" onclick="viewAttemptAnswers(<?php echo $a['id']; ?>, 'recert')"><i class="fas fa-eye mr-1"></i> View</button>
          </td>
        </tr>
        <?php if ($a['passed']): ?>
        <tr id="recert-cert-modal-<?php echo $a['id']; ?>" style="display:none;background:#f8fafc;">
          <td colspan="5" style="padding:24px;">
            <div style="display:flex;justify-content:center;">
              <div id="ctCertCard_modal-<?php echo $a['id']; ?>" style="width:100%;max-width:700px;background:#fffefb;border:8px solid #0f2557;border-radius:6px;padding:40px 50px;text-align:center;position:relative;">
                <div style="position:absolute;inset:12px;border:2px solid #d4af37;border-radius:4px;pointer-events:none;"></div>
                <?php if (!empty($co_settings['company_logo'])): ?><img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" style="max-height:100px;max-width:240px;object-fit:contain;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto;"><?php endif; ?>
                <div style="font-size:14px;font-weight:800;color:#0f2557;text-transform:uppercase;letter-spacing:1px;"><?php echo htmlspecialchars($co_settings['company_name'] ?? ''); ?></div>
                <div style="font-size:24px;font-weight:800;color:#0f2557;margin:12px 0 4px;">Recertification Certificate</div>
                <div style="font-size:12px;color:#64748b;margin-bottom:10px;">Cycle <?php echo $a['cycle_number']; ?>   <?php echo htmlspecialchars($deptName); ?></div>
                <div style="font-size:12px;color:#64748b;">This certifies that</div>
                <div style="font-size:24px;font-weight:800;color:#1a3fc4;margin:8px 0;"><?php echo htmlspecialchars($empRow['name']); ?></div>
                <div style="font-size:13px;color:#334155;max-width:480px;margin:0 auto 20px;line-height:1.7;">has successfully completed Recertification Cycle <?php echo $a['cycle_number']; ?> for <strong><?php echo htmlspecialchars($posName); ?></strong> in <strong><?php echo htmlspecialchars($deptName); ?></strong> department. Score: <strong><?php echo number_format($a['percentage'],1); ?>%</strong></div>
                <div style="display:flex;justify-content:space-between;margin-top:24px;font-size:12px;color:#64748b;">
                  <div><strong style="display:block;color:#0f2557;"><?php echo date('d M Y', strtotime($a['attempted_at'])); ?></strong>Date Issued</div>
                  <div><strong style="display:block;color:#0f2557;">RECERT-<?php echo date('Y',strtotime($a['attempted_at'])).'-C'.$a['cycle_number'].'-'.str_pad($emp_id,5,'0',STR_PAD_LEFT); ?></strong>Cert No.</div>
                  <div><?php if (!empty($co_settings['company_signature'])): ?><img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" style="max-height:60px;display:block;margin:0 auto 4px;"><?php endif; ?><strong style="display:block;color:#0f2557;">Authorized Signatory</strong></div>
                </div>
              </div>
            </div>
            <div style="text-align:center;margin-top:16px;">
              <button onclick="downloadCTCert('modal-<?php echo $a['id']; ?>')" style="background:#0f2557;color:#fff;border:none;padding:10px 22px;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-download mr-1"></i> Download Certificate</button>
            </div>
          </td>
        </tr>
        <?php endif; ?>
        <?php endforeach; ?>
        
        <?php if ($cycle > 0 && !$hasCurrentCycle): ?>
        <tr>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#94a3b8;"> </td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#64748b;font-weight:700;">Cycle <?php echo $cycle; ?> (Current)</td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#94a3b8;"> </td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#94a3b8;"> </td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#94a3b8;"> </td>
          <td style="padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:700;color:#d97706;">
            <i class="fas fa-clock mr-1"></i> In Progress
          </td>
        </tr>
        <?php endif; ?>
      </tbody>
    </table>
  <?php endif; ?>
</div>
<?php endif; ?>

<!-- Certificate (Generic Cross Training / OJE) -->
<?php if ($progress && $progress['stage'] === 'certified' && $context !== 'recert'): ?>
<div style="background:#fff;border:1.5px solid #bbf7d0;border-radius:12px;padding:20px;margin-bottom:16px;">
  <h6 style="font-weight:800;color:#065f46;margin-bottom:16px;"><i class="fas fa-certificate mr-2"></i>Certificate of Completion</h6>
  <div style="display:flex;justify-content:center;">
    <div id="ctCertCard_<?php echo $emp_id; ?>" style="width:100%;max-width:700px;background:#fffefb;border:8px solid #0f2557;border-radius:6px;padding:40px 50px;text-align:center;position:relative;">
      <div style="position:absolute;inset:12px;border:2px solid #d4af37;border-radius:4px;pointer-events:none;"></div>
      <?php if (!empty($co_settings['company_logo'])): ?>
        <img src="<?php echo htmlspecialchars($co_settings['company_logo']); ?>" style="max-height:100px;max-width:260px;object-fit:contain;margin-bottom:10px;display:block;margin-left:auto;margin-right:auto;">
      <?php endif; ?>
      <div style="font-size:13px;font-weight:800;letter-spacing:2px;text-transform:uppercase;color:#0f2557;"><?php echo htmlspecialchars($co_settings['company_name'] ?? ''); ?></div>
      <div style="font-size:24px;font-weight:800;color:#0f2557;margin:12px 0 4px;">Certificate of Completion</div>
      <div style="font-size:12px;color:#64748b;margin-bottom:20px;"><?php echo $context === 'oje' ? 'Training & OJE Program' : 'Cross Training Program'; ?></div>
      <div style="font-size:13px;color:#64748b;">This certifies that</div>
      <div style="font-size:24px;font-weight:800;color:#1a3fc4;margin:8px 0;"><?php echo htmlspecialchars($empRow['name']); ?></div>
      <div style="font-size:13px;color:#334155;max-width:480px;margin:0 auto 20px;line-height:1.7;">has successfully completed the <?php echo $context === 'oje' ? 'Training & OJE' : 'Cross Training'; ?> program for the position of <strong><?php echo htmlspecialchars($posName); ?></strong> in the <strong><?php echo htmlspecialchars($deptName); ?></strong> department.</div>
      <div style="display:flex;justify-content:space-between;margin-top:24px;font-size:12px;color:#64748b;">
        <div><strong style="display:block;color:#0f2557;"><?php echo date('d M Y', strtotime($progress['certified_at'])); ?></strong>Date Issued</div>
        <div><strong style="display:block;color:#0f2557;"><?php echo $certNumber; ?></strong>Certificate No.</div>
        <div>
          <?php if (!empty($co_settings['company_signature'])): ?>
            <img src="<?php echo htmlspecialchars($co_settings['company_signature']); ?>" style="max-height:80px;max-width:200px;display:block;margin:0 auto 4px;">
          <?php endif; ?>
          <strong style="display:block;color:#0f2557;">Authorized Signatory</strong>
        </div>
      </div>
    </div>
  </div>
  <div style="text-align:center;margin-top:16px;">
    <button type="button" onclick="downloadCTCert(<?php echo $emp_id; ?>)" style="background:#0f2557;color:#fff;border:none;padding:10px 22px;border-radius:8px;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-download mr-1"></i> Download Certificate</button>
  </div>
</div>
<?php endif; ?>