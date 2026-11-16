<?php 
error_reporting(E_ERROR | E_WARNING | E_PARSE);
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}
require_once('database.php');
require_once('library.php');
require_once('funciones.php');
if (@file_exists('requirelanguage.php')) { require 'requirelanguage.php'; }
if (@file_exists('requirelanguage_image.php')) { require 'requirelanguage_image.php'; }

isUser();

// ═══════════════════════════════════════════════════════════════
// NOTIFICATION SYSTEM
// ═══════════════════════════════════════════════════════════════
@mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS notification_reads (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    reader_name  VARCHAR(255) NOT NULL,
    source_type  VARCHAR(30)  NOT NULL,
    source_id    INT NOT NULL,
    read_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_reader_source (reader_name(100), source_type, source_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$ticket_count  = 0;
$ticket_items  = [];
$hdr_reader_esc = mysqli_real_escape_string($dbConn, trim($_SESSION['user_name'] ?? ''));

if (isset($_SESSION['user_name'])) {
    $hdr_pat  = trim($_SESSION['user_name']) . '%';
    $emp_stmt = mysqli_prepare($dbConn,
        "SELECT id, employee_id, hire_date FROM hr_employees WHERE name LIKE ? AND status='active' LIMIT 1");
    if ($emp_stmt) {
        mysqli_stmt_bind_param($emp_stmt, "s", $hdr_pat);
        mysqli_stmt_execute($emp_stmt);
        $emp_row = mysqli_fetch_assoc(mysqli_stmt_get_result($emp_stmt));
        mysqli_stmt_close($emp_stmt);

        if ($emp_row) {
            $hdr_eid       = (int)$emp_row['id'];
            $hdr_emp_code  = $emp_row['employee_id']; // string code used by performance_* tables
            $hdr_emp_hired = (!empty($emp_row['hire_date']) && $emp_row['hire_date'] != '0000-00-00') ? $emp_row['hire_date'] : null;
            // Tickets are counted purely by status -- opening/viewing a
            // ticket does NOT clear it from the count, only actually
            // closing/resolving it does. This is intentional: a glance
            // shouldn't count as handled, only real resolution should.
            $cs = mysqli_prepare($dbConn,
                "SELECT COUNT(*) AS total FROM tickets t
                 WHERE t.assigned_to = ?
                   AND t.status NOT IN ('closed','resolved','Approved','Rejected')");
            if ($cs) {
                mysqli_stmt_bind_param($cs, "i", $hdr_eid);
                mysqli_stmt_execute($cs);
                $cr = mysqli_fetch_assoc(mysqli_stmt_get_result($cs));
                $ticket_count = (int)($cr['total'] ?? 0);
                mysqli_stmt_close($cs);
            }
            $ps = mysqli_prepare($dbConn,
                "SELECT t.id, t.ticket_number, t.subject, t.priority, t.status, t.created_at
                 FROM tickets t
                 WHERE t.assigned_to = ?
                   AND t.status NOT IN ('closed','resolved','Approved','Rejected')
                 ORDER BY t.id DESC LIMIT 5");
            if ($ps) {
                mysqli_stmt_bind_param($ps, "i", $hdr_eid);
                mysqli_stmt_execute($ps);
                $pr = mysqli_stmt_get_result($ps);
                while ($r = mysqli_fetch_assoc($pr)) $ticket_items[] = $r;
                mysqli_stmt_close($ps);
            }
        }
    }
}

// User permissions -- moved above the KYC block so KYC notifications can
// check per-module access (customer_verification / vendor_verification /
// driver_verification), same as everything else in this file.
$user_id = 0; $permissions = [];
$hdr_is_admin_role = isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Administrator';
if ($hdr_is_admin_role) {
    $r = mysqli_query($dbConn, "SELECT cid FROM manager_admin WHERE name='".$_SESSION["user_name"]."' LIMIT 1");
    if ($rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
} elseif (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Employee') {
    $r = mysqli_query($dbConn, "SELECT cid FROM manager_user WHERE name='".$_SESSION["user_name"]."' LIMIT 1");
    if ($rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
}
if ($user_id > 0) {
    $stmt = $dbConn->prepare("SELECT section_name,can_access FROM manager_permissions WHERE user_id=?");
    $stmt->bind_param("i", $user_id); $stmt->execute();
    $result = $stmt->get_result();
    while ($row = $result->fetch_assoc()) $permissions[$row['section_name']] = $row['can_access'];
    $stmt->close();
}

// NOTE: page-level access enforcement now happens centrally in
// database.php (crm_enforce_page_permission_auto), which every page --
// including the ones that never include header.php -- already
// requires before this file even runs. See access-control.php for the
// filename -> permission-key map.

// ── KYC pending review counts ──────────────────────────────────────────
// Notify: admins (bypass everything, as elsewhere in this app), the
// hardcoded KYC-authorized names (matches the actual check inside
// customer-verification.php / vendor-verification.php / manage_driver_kyc.php),
// AND anyone explicitly granted the matching permission key
// (customer_verification / vendor_verification / driver_verification)
// via the Permissions page -- so whoever we've given access to also gets
// notified, not just the hardcoded admin.
$kyc_pending_count = 0;
$kyc_items = [];
$hdr_kyc_authorized = ['Abishek Veeraswamy', 'Abishek', 'abishek'];
$hdr_current_name   = trim($_SESSION['user_name'] ?? '');
$hdr_kyc_name_match = false;
foreach ($hdr_kyc_authorized as $hdr_aname) {
    if (!empty($hdr_current_name) && (stripos($hdr_current_name, $hdr_aname) !== false || stripos($hdr_aname, $hdr_current_name) !== false)) {
        $hdr_kyc_name_match = true;
        break;
    }
}

$kyc_sources = [
    ['table' => 'customer_kyc', 'status_col' => 'kyc_status', 'pending_val' => 'submitted', 'label' => 'Customer KYC', 'link' => 'customer-verification.php', 'perm' => 'customer_verification', 'name_col' => 'name',        'date_col' => 'submitted_at'],
    ['table' => 'vendor_kyc',   'status_col' => 'kyc_status', 'pending_val' => 'submitted', 'label' => 'Vendor KYC',   'link' => 'vendor-verification.php',   'perm' => 'vendor_verification',   'name_col' => 'name',        'date_col' => 'created_at'],
    ['table' => 'driver_kyc',   'status_col' => 'kyc_status', 'pending_val' => 'pending',   'label' => 'Driver KYC',   'link' => 'manage_driver_kyc.php',     'perm' => 'driver_verification',   'name_col' => 'driver_name', 'date_col' => 'created_at'],
];
foreach ($kyc_sources as $src) {
    $has_access = $hdr_is_admin_role || $hdr_kyc_name_match || (!empty($permissions[$src['perm']]) && $permissions[$src['perm']] == 1);
    if (!$has_access) continue;

    $chk = @mysqli_query($dbConn, "SHOW TABLES LIKE '{$src['table']}'");
    if (!$chk || mysqli_num_rows($chk) === 0) continue; // table may not exist in every environment

    // Pulls individual pending records (not just a count) so each one can
    // be marked read separately when clicked, and excludes ones already read.
    $kyc_r = @mysqli_query($dbConn,
        "SELECT t.id, t.`{$src['name_col']}` AS item_name, t.`{$src['date_col']}` AS item_date
         FROM `{$src['table']}` t
         WHERE t.`{$src['status_col']}` = '{$src['pending_val']}'
           AND NOT EXISTS (SELECT 1 FROM notification_reads nr WHERE nr.reader_name='$hdr_reader_esc' AND nr.source_type='{$src['table']}' AND nr.source_id = t.id)
         ORDER BY t.id DESC");
    $kyc_records = [];
    if ($kyc_r) { while ($krow = mysqli_fetch_assoc($kyc_r)) $kyc_records[] = $krow; }
    $c = count($kyc_records);
    $kyc_pending_count += $c;

    if ($c > 0) {
        $kyc_items[] = ['label' => $src['label'], 'count' => $c, 'link' => $src['link'], 'table' => $src['table'], 'records' => $kyc_records];
    }
}

// ── WEEKLY / MONTHLY SELF-REVIEW (mandatory) ────────────────────────────
// Same rule as the Daily KPI checkout gate: a weekly review is overdue
// once Saturday of its week has passed without a submission; a monthly
// review is overdue once the last day of its month has passed without
// one. Never counts a period before the employee's joining date. Scoped
// to the currently logged-in employee, same as the ticket count above.
//
// Each missed period gets its OWN row (not grouped), with two plain-
// English sentences explaining what was missed. Once the employee clicks
// a row, it's stamped in notification_reads (same table/mechanism KYC
// already uses) -- after that it STOPS counting toward the badge number,
// but it stays visible in this list (dimmed), so nothing silently
// disappears -- same "stays listed as a reference, read ones are just
// grayed out" behavior as the rest of the notification system.
$kpi_pending_count = 0;
$kpi_items = [];
if (!empty($hdr_eid) && !empty($hdr_emp_code)) {
    $hdr_emp_code_esc     = mysqli_real_escape_string($dbConn, $hdr_emp_code);
    $hdr_today            = date('Y-m-d');
    $hdr_this_week_monday = date('Y-m-d', strtotime('monday this week'));

    // Which weekly/monthly periods has this reader already clicked into?
    $hdr_kpi_read = [];
    $hdr_read_q = mysqli_query($dbConn, "SELECT source_type, source_id FROM notification_reads
        WHERE reader_name='$hdr_reader_esc' AND source_type IN ('weekly_review','monthly_review')");
    if ($hdr_read_q) {
        while ($hrr = mysqli_fetch_assoc($hdr_read_q)) {
            $hdr_kpi_read[$hrr['source_type'] . '_' . $hrr['source_id']] = true;
        }
    }

    for ($w = 0; $w < 8; $w++) {
        $wk_monday = date('Y-m-d', strtotime($hdr_this_week_monday . ' -' . ($w * 7) . ' days'));
        if ($hdr_emp_hired && strtotime($wk_monday) < strtotime($hdr_emp_hired)) continue;
        $wk_saturday = date('Y-m-d', strtotime($wk_monday . ' +5 days'));
        if ($hdr_today < $wk_saturday) continue; // not due yet
        $wq = mysqli_query($dbConn, "SELECT id FROM performance_weekly_self WHERE employee_id='$hdr_emp_code_esc' AND week_start_date='$wk_monday' LIMIT 1");
        if ($wq && mysqli_num_rows($wq) > 0) continue; // already submitted

        $wk_sid  = (int)str_replace('-', '', $wk_monday); // e.g. 2026-07-20 -> 20260720
        $wk_read = isset($hdr_kpi_read['weekly_review_' . $wk_sid]);
        if (!$wk_read) $kpi_pending_count++;

        $kpi_items[] = [
            'type'    => 'weekly',
            'period'  => $wk_monday,
            'read'    => $wk_read,
            'link'    => 'hr-kpi-evaluation.php',
            'icon'    => 'fa-calendar-week',
            'line1'   => 'You missed a review deadline.',
            'line2'   => 'Your Weekly Self-Review for ' . date('d M', strtotime($wk_monday)) . ' - ' . date('d M Y', strtotime($wk_monday . ' +6 days')) . ' was due by ' . date('d M (D)', strtotime($wk_saturday)) . ' and hasn\'t been submitted yet.',
            'sort'    => $wk_saturday,
        ];
    }

    for ($m = 0; $m < 6; $m++) {
        $mn = date('Y-m', strtotime("-$m months"));
        if ($hdr_emp_hired && strtotime($mn . '-01') < strtotime(date('Y-m-01', strtotime($hdr_emp_hired)))) continue;
        $mn_last_day = date('Y-m-t', strtotime($mn . '-01'));
        if ($hdr_today < $mn_last_day) continue; // not due yet
        $mq = mysqli_query($dbConn, "SELECT id FROM performance_monthly_self WHERE employee_id='$hdr_emp_code_esc' AND review_month='$mn' LIMIT 1");
        if ($mq && mysqli_num_rows($mq) > 0) continue; // already submitted

        $mn_sid  = (int)str_replace('-', '', $mn . '-01'); // e.g. 2026-07 -> 20260701
        $mn_read = isset($hdr_kpi_read['monthly_review_' . $mn_sid]);
        if (!$mn_read) $kpi_pending_count++;

        $kpi_items[] = [
            'type'    => 'monthly',
            'period'  => $mn,
            'read'    => $mn_read,
            'link'    => 'hr-kpi-evaluation.php',
            'icon'    => 'fa-calendar-check',
            'line1'   => 'You missed a review deadline.',
            'line2'   => 'Your Monthly Self-Review for ' . date('F Y', strtotime($mn . '-01')) . ' was due by ' . date('d M (D)', strtotime($mn_last_day)) . ' and hasn\'t been submitted yet.',
            'sort'    => $mn_last_day,
        ];
    }

    // Newest deadline first.
    usort($kpi_items, function($a, $b) { return strcmp($b['sort'], $a['sort']); });
}

// ── HR SCHEDULES -- reminders this user created that are now due ───────
// Same table/marking mechanism as everything else here: once due, it
// shows up in the dropdown with a sound + desktop alert (wired in the JS
// below) and a ticket gets auto-raised (in get_notification_count.php's
// polling handler) for the employee the schedule is about. Clicking it
// stamps notification_reads same as KPI rows do, so it stops counting
// toward the badge but stays visible (dimmed) as a reference.
@mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_schedules (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    schedule_name VARCHAR(255) NOT NULL,
    employee_id   INT NOT NULL,
    schedule_date DATE NOT NULL,
    schedule_time TIME NOT NULL,
    created_by    VARCHAR(150),
    ticket_raised TINYINT(1) DEFAULT 0,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$schedule_pending_count = 0;
$schedule_items = [];
if (!empty($hdr_current_name)) {
    $hdr_sch_q = mysqli_query($dbConn, "
        SELECT s.id, s.schedule_name, s.schedule_date, s.schedule_time, e.name AS employee_name
        FROM hr_schedules s
        LEFT JOIN hr_employees e ON e.id = s.employee_id
        WHERE s.created_by = '$hdr_reader_esc'
          AND TIMESTAMP(s.schedule_date, s.schedule_time) <= NOW()
        ORDER BY s.schedule_date DESC, s.schedule_time DESC
        LIMIT 10
    ");
    if ($hdr_sch_q) {
        while ($hsrow = mysqli_fetch_assoc($hdr_sch_q)) {
            $hs_read_q = mysqli_query($dbConn, "SELECT 1 FROM notification_reads WHERE reader_name='$hdr_reader_esc' AND source_type='hr_schedule' AND source_id=" . (int)$hsrow['id'] . " LIMIT 1");
            $hs_read   = $hs_read_q && mysqli_num_rows($hs_read_q) > 0;
            if (!$hs_read) $schedule_pending_count++;
            $schedule_items[] = [
                'id'       => $hsrow['id'],
                'name'     => $hsrow['schedule_name'],
                'employee' => $hsrow['employee_name'] ?? 'N/A',
                'when'     => date('d M Y, h:i A', strtotime($hsrow['schedule_date'] . ' ' . $hsrow['schedule_time'])),
                'read'     => $hs_read,
            ];
        }
    }
}

$total_notification_count = $ticket_count + $kyc_pending_count + $kpi_pending_count + $schedule_pending_count;

// Greeting
date_default_timezone_set('Asia/Kolkata');
$t = date("H");
if ($t < 12)      $mensaje = $L_['Goodmorning'];
else if ($t < 18) $mensaje = $L_['Goodafternoon'];
else              $mensaje = $L_['Goodnight'];

$is_admin    = isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Administrator';
$is_employee = isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Employee';


// Define the Global "Back to Dashboard" URL Logic — depends on which entity is active.
// index.php        -> E-Logistics-specific admin dashboard
// db-dashboard.php  -> Design & Build's dashboard
// dashboard-pending.php -> Global Trading / Food Industry (no dedicated dashboard built yet)
switch ($_SESSION['active_entity'] ?? null) {
    case 'elogistics': $dashboard_url = 'index.php'; break;
    case 'design':     $dashboard_url = 'db-dashboard.php'; break;
    case 'trading':
    case 'food':       $dashboard_url = 'dashboard-pending.php'; break;
    default:           $dashboard_url = 'db-dashboard.php';
}

// Display info for the currently selected entity (topbar Switch Entity button)
$entity_labels = [
    'elogistics' => ['name' => 'E-Logistics',   'icon' => 'fa-truck'],
    'design'     => ['name' => 'Design & Build','icon' => 'fa-building'],
    'trading'    => ['name' => 'Global Trading','icon' => 'fa-globe'],
    'food'       => ['name' => 'Food Industry', 'icon' => 'fa-cutlery'],
];
$active_entity_info = (!empty($_SESSION['active_entity']) && isset($entity_labels[$_SESSION['active_entity']]))
    ? $entity_labels[$_SESSION['active_entity']]
    : null;
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $is_flowx ? APP_NAME : $_SESSION['ge_cname']; ?> | <?php echo $Paneladministracion; ?></title>
  <meta name="description" content="<?php echo $_SESSION['ge_description']; ?>"/>
  <meta name="keywords" content="<?php echo $_SESSION['ge_keywords']; ?>" />
  <meta name="author" content="Jaomweb">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <link rel="shortcut icon" type="image/png" href="img/<?php echo $is_flowx ? 'favicon.png' : 'favicon.png'; ?>"/>
  <link rel="stylesheet" href="../bower_components/bootstrap/dist/css/bootstrap.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/animate.css/animate.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/font-awesome/css/font-awesome.min.css" type="text/css" />
  <link rel="stylesheet" href="../bower_components/simple-line-icons/css/simple-line-icons.css" type="text/css" />
  <link rel="stylesheet" href="css/font.css" type="text/css" />
  <link rel="stylesheet" href="css/app.css" type="text/css" />
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
  /* ════════════════════════════════════════════════════
     ROOT VARIABLES — Navy Blue Theme
  ════════════════════════════════════════════════════ */
  :root {
    --navy-900: #0a1628;
    --navy-800: #0d1f3c;
    --navy-700: #112347;
    --navy-600: #153060;
    --navy-500: #1a3a72;
    --navy-400: #1e4d9b;
    --navy-300: #2563c4;
    --navy-200: #4a8ae8;
    --navy-100: #93b8f5;
    --navy-50:  #dce9fc;
    --accent:   #f59e0b;
    --accent-2: #10b981;
    --danger:   #ef4444;
    --white:    #ffffff;
    --text-muted: rgba(255,255,255,0.55);
    --border:   rgba(255,255,255,0.08);
    --sidebar-w: 240px;
    --topbar-h:  68px;
    --font: 'Outfit', sans-serif;
  }

  * { box-sizing: border-box; }
  body, html { font-family: var(--font) !important; margin: 0; padding: 0; }

  /* ════════════════════════════════════════════════════
     TOP BAR — full white
  ════════════════════════════════════════════════════ */
  #main-topbar {
    position: fixed;
    top: 0; left: 240px; right: 0;
    height: var(--topbar-h);
    background: #ffffff;
    border-bottom: 2px solid #e2e8f0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 20px 0 16px;
    z-index: 1000;
    box-shadow: 0 2px 12px rgba(0,0,0,0.08);
  }

  /* Topbar title — takes middle space (carousel removed) */
  .topbar-title-wrap {
    flex: 1;
    overflow: hidden;
    background: #ffffff;
    margin: 0 16px;
    height: 100%;
    display: flex;
    align-items: center;
  }
  .topbar-title-wrap .topbar-page-title {
    font-size: 16px;
    font-weight: 700;
    color: var(--navy-800);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Clock on white topbar */
  .topbar-clock {
    font-size: 13px;
    color: var(--navy-700);
    font-weight: 600;
    padding: 5px 12px;
    background: #f1f5f9;
    border-radius: 20px;
    border: 1px solid #e2e8f0;
    margin-right: 6px;
  }

  /* Switch Entity button — topbar */
  .topbar-entity-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 14px 7px 12px;
    background: linear-gradient(135deg, var(--navy-500), var(--navy-400));
    border: none;
    border-radius: 20px;
    cursor: pointer;
    text-decoration: none !important;
    box-shadow: 0 3px 10px rgba(26,58,114,0.28);
    transition: transform .18s, box-shadow .18s;
    margin-right: 6px;
  }
  .topbar-entity-btn:hover {
    transform: translateY(-1px);
    box-shadow: 0 5px 16px rgba(26,58,114,0.4);
  }
  .topbar-entity-btn i.fa-th-large { color: #fff; font-size: 13px; }
  .topbar-entity-btn .te-label { display: flex; flex-direction: column; line-height: 1.15; }
  .topbar-entity-btn .te-cur { font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.6); letter-spacing: .4px; text-transform: uppercase; }
  .topbar-entity-btn .te-name { font-size: 12px; font-weight: 800; color: #fff; }
  .topbar-entity-btn i.fa-exchange { color: rgba(255,255,255,0.75); font-size: 11px; margin-left: 2px; }
  @media (max-width: 640px) {
    .topbar-entity-btn .te-label { display: none; }
    .topbar-entity-btn { padding: 8px; border-radius: 50%; }
  }

  /* Bell on white topbar */
  .notif-bell-wrap {
    position: relative;
    width: 40px; height: 40px;
    border-radius: 10px;
    background: #f1f5f9;
    border: 1px solid #e2e8f0;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer;
    transition: background .2s;
  }
  .notif-bell-wrap:hover { background: #e2e8f0; }
  .notif-bell-wrap .fa-bell { font-size: 17px; color: var(--navy-700); }
  .notif-bell-wrap.has-notif .fa-bell { color: var(--accent); animation: bell-ring .7s ease; }

  /* User button on white topbar */
  .topbar-user-btn {
    display: flex; align-items: center; gap: 9px;
    padding: 5px 12px 5px 6px;
    background: #f1f5f9;
    border: 1px solid #e2e8f0;
    border-radius: 10px;
    cursor: pointer;
    transition: background .2s;
    text-decoration: none !important;
  }
  .topbar-user-btn:hover { background: #e2e8f0; }
  .topbar-user-greet { font-size: 10px; color: #64748b; display: block; }
  .topbar-user-name  { font-size: 13px; font-weight: 700; color: var(--navy-800); display: block; }
  .topbar-user-caret { color: #94a3b8; font-size: 11px; margin-left: 2px; }

  /* Mobile menu button on white topbar */
  .mob-menu-btn {
    display: none;
    width: 38px; height: 38px;
    border-radius: 10px;
    background: #f1f5f9;
    border: 1px solid #e2e8f0;
    align-items: center; justify-content: center;
    cursor: pointer; margin-right: 8px;
    color: var(--navy-800); font-size: 16px;
  }

  /* Right side controls */
  .topbar-right {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
  }

  @keyframes bell-ring {
    0%,100%{transform:rotate(0)} 20%,60%{transform:rotate(-18deg)} 40%,80%{transform:rotate(18deg)}
  }
  .notif-badge {
    position: absolute;
    top: -4px; right: -4px;
    background: var(--danger);
    color: #fff;
    border-radius: 10px;
    min-width: 16px; height: 16px;
    font-size: 9px; font-weight: 800;
    line-height: 16px; text-align: center;
    padding: 0 4px;
    border: 2px solid #fff;
    display: none;
  }

  /* Notification dropdown */
  .notif-drop {
    display: none;
    position: absolute;
    top: calc(100% + 8px); right: 0;
    width: 320px;
    background: #fff;
    border-radius: 12px;
    box-shadow: 0 12px 40px rgba(0,0,0,.22);
    border: 1px solid #e2e8f0;
    overflow: hidden;
    z-index: 9999;
  }
  .notif-drop.open { display: block; animation: drop-in .18s ease; }
  @keyframes drop-in { from{opacity:0;transform:translateY(-8px)} to{opacity:1;transform:translateY(0)} }

  .notif-drop-head {
    background: linear-gradient(135deg, var(--navy-700), var(--navy-500));
    padding: 12px 16px;
    display: flex; align-items: center; justify-content: space-between;
  }
  .notif-drop-head .nd-title { color: #fff; font-weight: 700; font-size: 13px; }
  .notif-drop-head .nd-pill {
    background: rgba(255,255,255,.18);
    color: #fff; font-size: 10px; font-weight: 800;
    border-radius: 20px; padding: 2px 9px;
  }
  .notif-row {
    display: flex; align-items: flex-start; gap: 10px;
    padding: 10px 14px;
    border-bottom: 1px solid #f1f5f9;
    text-decoration: none !important;
    background: #fff;
    transition: background .12s;
  }
  .notif-row:hover { background: #f0f7ff; }
  .notif-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--navy-300); flex-shrink: 0; margin-top: 4px; }
  .notif-info { flex: 1; min-width: 0; }
  .notif-meta { display: flex; justify-content: space-between; margin-bottom: 2px; }
  .notif-num  { font-size: 11px; font-weight: 700; color: var(--navy-400); }
  .notif-age  { font-size: 10px; color: #94a3b8; }
  .notif-subj { font-size: 12px; font-weight: 600; color: #1e293b; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block; margin-bottom: 3px; }
  .notif-prio { display: inline-block; padding: 1px 7px; border-radius: 5px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
  .np-h { background: #fde8e8; color: #c0392b; }
  .np-m { background: #fef3cd; color: #d68910; }
  .np-l { background: #d5f5e3; color: #1e8449; }
  .notif-empty { padding: 30px 20px; text-align: center; }
  .notif-empty i { font-size: 32px; color: #cbd5e1; display: block; margin-bottom: 10px; }
  .notif-empty h6 { color: #475569; font-weight: 700; font-size: 13px; margin: 0 0 4px; }
  .notif-empty p  { color: #94a3b8; font-size: 11px; margin: 0; }
  .notif-footer {
    display: flex; align-items: center; justify-content: center; gap: 6px;
    padding: 10px; background: #f8fafc;
    border-top: 1px solid #e2e8f0;
    color: var(--navy-400); font-weight: 700; font-size: 12px;
    text-decoration: none !important;
    transition: background .12s;
  }
  .notif-footer:hover { background: #eff6ff; }

  /* Notification dropdown -- mobile: fixed-position and full-width so a
     320px dropdown near the right edge of a narrow phone screen can't
     overflow off-screen. */
  @media (max-width: 560px) {
    .notif-drop {
      position: fixed;
      top: 62px;
      left: 10px;
      right: 10px;
      width: auto;
      max-height: 75vh;
      overflow-y: auto;
    }
    .notif-toast {
      left: 10px; right: 10px; top: 66px;
      max-width: none;
    }
  }

  /* Toast */
  .notif-toast {
    position: fixed;
    top: 80px; right: 20px;
    background: var(--navy-500);
    color: #fff;
    padding: 10px 18px;
    border-radius: 10px;
    font-size: 13px; font-weight: 600;
    box-shadow: 0 6px 20px rgba(0,0,0,.2);
    z-index: 99999;
    display: none;
    animation: toast-in .3s ease;
    border-left: 4px solid var(--accent);
  }
  .notif-toast i { margin-right: 8px; color: var(--accent); }
  @keyframes toast-in { from{opacity:0;transform:translateY(-10px)} to{opacity:1;transform:translateY(0)} }

  /* User avatar */
  .topbar-user-avatar {
    width: 32px; height: 32px;
    border-radius: 8px;
    object-fit: cover;
    background: #e2e8f0;
  }
  .topbar-user-info { line-height: 1.2; }

  /* User dropdown menu */
  .topbar-user-drop {
    position: absolute;
    top: calc(100% + 8px); right: 0;
    width: 210px;
    background: #fff;
    border-radius: 12px;
    box-shadow: 0 12px 40px rgba(0,0,0,.18);
    border: 1px solid #e2e8f0;
    overflow: hidden;
    display: none;
    z-index: 9999;
    animation: drop-in .18s ease;
  }
  .topbar-user-drop.open { display: block; }
  .topbar-user-drop-head {
    padding: 14px 16px;
    background: linear-gradient(135deg, var(--navy-800), var(--navy-600));
    border-bottom: 1px solid var(--border);
  }
  .topbar-user-drop-head span { color: #fff; font-size: 13px; font-weight: 600; display: block; }
  .topbar-user-drop-head small { color: var(--navy-100); font-size: 11px; }
  .topbar-user-drop a {
    display: flex; align-items: center; gap: 10px;
    padding: 10px 16px;
    font-size: 13px; font-weight: 500; color: #334155;
    text-decoration: none !important;
    transition: background .12s;
    border-bottom: 1px solid #f1f5f9;
  }
  .topbar-user-drop a:hover { background: #f0f7ff; color: var(--navy-400); }
  .topbar-user-drop a i { width: 16px; text-align: center; color: var(--navy-300); }
  .topbar-user-drop a.logout { color: var(--danger); }
  .topbar-user-drop a.logout i { color: var(--danger); }
  .topbar-user-drop a.logout:hover { background: #fef2f2; }

  /* ════════════════════════════════════════════════════
     SIDEBAR
  ════════════════════════════════════════════════════ */
  #main-sidebar {
    position: fixed;
    top: 0; left: 0;
    width: auto;
    min-width: 240px;
    max-width: 300px;
    height: 100vh;
    background: var(--navy-900);
    border-right: none;
    display: flex;
    flex-direction: column;
    z-index: 1001;
    overflow: visible;
    transition: width .25s ease;
  }

  /* Sidebar brand */
  .sidebar-brand {
    height: var(--topbar-h);
    display: flex; align-items: center;
    padding: 0 16px;
    background: #ffffff;
    border-bottom: 2px solid #e2e8f0;
    gap: 10px;
    flex-shrink: 0;
  }
  .sidebar-brand img { height: 38px; width: auto; border-radius: 6px; flex-shrink: 0; }
  .sidebar-brand-text { font-size: 15px; font-weight: 800; color: var(--navy-800); letter-spacing: 0.3px; white-space: nowrap; }

  /* Sidebar scroll area */
  .sidebar-nav {
    flex: 1;
    overflow-y: auto;
    overflow-x: visible;
    padding: 10px 0 20px;
  }
  .sidebar-nav::-webkit-scrollbar { width: 4px; }
  .sidebar-nav::-webkit-scrollbar-track { background: transparent; }
  .sidebar-nav::-webkit-scrollbar-thumb { background: var(--navy-600); border-radius: 4px; }

  /* Section labels */
  .nav-label {
    font-size: 9px; font-weight: 700;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 1.2px;
    padding: 14px 16px 4px;
  }

  /* Nav items */
  .snav { list-style: none; margin: 0; padding: 0; }
  .snav li { position: relative; }

  .snav > li > a,
  .snav .sub-menu li > a {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 11px 16px;
    font-size: 17px;
    font-weight: 700;
    color: #ffffff;
    text-decoration: none !important;
    border-radius: 0;
    transition: background .15s, color .15s;
    white-space: normal;
    word-break: break-word;
    cursor: pointer;
    border-left: 3px solid transparent;
    letter-spacing: 0.2px;
  }
  .snav > li > a:hover,
  .snav .sub-menu li > a:hover {
    background: rgba(255,255,255,0.06);
    color: #fff;
    border-left-color: var(--navy-300);
  }
  .snav > li.active > a {
    background: rgba(37,99,196,0.22);
    color: #fff;
    border-left-color: var(--navy-200);
  }
  .snav > li > a i.nav-icon {
    width: 20px; text-align: center;
    font-size: 17px;
    flex-shrink: 0;
    transition: color .15s;
  }
  .nav-icon-svg {
    display: inline-flex; align-items: center; justify-content: center;
    width: 20px; height: 18px; flex-shrink: 0;
  }
  .nav-icon-svg svg { width: 18px; height: 18px; color: rgba(255,255,255,0.75); transition: color .15s; }
  .snav > li > a:hover .nav-icon-svg svg, .snav > li.active > a .nav-icon-svg svg { color: #fff; }

  .nav-arrow {
    margin-left: auto;
    font-size: 11px;
    color: rgba(255,255,255,0.3);
    transition: transform .2s;
    flex-shrink: 0;
  }
  .snav li.open > a .nav-arrow { transform: rotate(90deg); color: var(--navy-200); }

  /* Sub menu — hidden by default at ALL levels */
  .sub-menu {
    list-style: none;
    margin: 0; padding: 0;
    background: rgba(0,0,0,0.18);
    display: none;
  }
  /* Open at ANY level — top, second, third */
  .snav li.open > .sub-menu { display: block; animation: sub-in .15s ease; }
  @keyframes sub-in { from{opacity:0;transform:translateY(-4px)} to{opacity:1;transform:translateY(0)} }

  .sub-menu li > a {
    padding: 9px 16px 9px 40px !important;
    font-size: 15px !important;
    font-weight: 600 !important;
    color: rgba(255,255,255,0.90) !important;
    border-left: 3px solid transparent !important;
  }
  .sub-menu li > a:hover {
    color: #fff !important;
    background: rgba(255,255,255,0.07) !important;
    border-left-color: var(--navy-300) !important;
  }
  .sub-menu li > a i { width: 18px; text-align: center; font-size: 15px; flex-shrink: 0; }
  .sub-menu .sub-menu li > a { padding-left: 58px !important; font-size: 14px !important; }
  .sub-menu .sub-menu li > a i { font-size: 14px; width: 16px; }

  /* ── Icon colors — every icon vivid color ── */
  .snav > li > a i.nav-icon { color: rgba(255,255,255,0.75); }
  .snav > li > a:hover i.nav-icon, .snav > li.active > a i.nav-icon { color: #fff; }

  .fa-bar-chart      { color: #60a5fa; }
  .fa-barcode        { color: #94a3b8; }
  .fa-bell           { color: #fbbf24; }
  .fa-bell-slash     { color: #94a3b8; }
  .fa-bicycle        { color: #4ade80; }
  .fa-briefcase      { color: #fbbf24; }
  .fa-building       { color: #60a5fa; }
  .fa-bullhorn       { color: #facc15; }
  .fa-bullseye       { color: #f87171; }
  .fa-calculator     { color: #60a5fa; }
  .fa-calendar       { color: #fb923c; }
  .fa-car            { color: #60a5fa; }
  .fa-check          { color: #4ade80; }
  .fa-check-circle   { color: #4ade80; }
  .fa-check-square   { color: #34d399; }
  .fa-clock-o        { color: #f472b6; }
  .fa-cog            { color: #94a3b8; }
  .fa-cogs           { color: #94a3b8; }
  .fa-commenting     { color: #25D366; }
  .fa-comments       { color: #34d399; }
  .fa-credit-card    { color: #34d399; }
  .fa-cube           { color: #c084fc; }
  .fa-cubes          { color: #fb923c; }
  .fa-cutlery        { color: #f87171; }
  .fa-database       { color: #38bdf8; }
  .fa-download       { color: #60a5fa; }
  .fa-envelope       { color: #60a5fa; }
  .fa-exchange       { color: #34d399; }
  .fa-file-image-o   { color: #c084fc; }
  .fa-file-text      { color: #60a5fa; }
  .fa-filter         { color: #818cf8; }
  .fa-folder-open    { color: #fbbf24; }
  .fa-globe          { color: #4ade80; }
  .fa-headphones     { color: #f472b6; }
  .fa-list           { color: #38bdf8; }
  .fa-list-alt       { color: #38bdf8; }
  .fa-magic          { color: #c084fc; }
  .fa-map-marker     { color: #f87171; }
  .fa-money          { color: #4ade80; }
  .fa-plane          { color: #fb923c; }
  .fa-plus-circle    { color: #4ade80; }
  .fa-question-circle { color: #a78bfa; }
  .fa-refresh        { color: #34d399; }
  .fa-reply          { color: #f87171; }
  .fa-road           { color: #94a3b8; }
  .fa-sign-in        { color: #4ade80; }
  .fa-sign-out       { color: #fb923c; }
  .fa-sitemap        { color: #38bdf8; }
  .fa-star           { color: #fbbf24; }
  .fa-comment        { color: #25D366; }
  .fa-tablet         { color: #60a5fa; }
  .fa-tag            { color: #c084fc; }
  .fa-ticket         { color: #f472b6; }
  .fa-times-circle   { color: #f87171; }
  .fa-truck          { color: #fb923c; }
  .fa-undo           { color: #fb923c; }
  .fa-upload         { color: #38bdf8; }
  .fa-user           { color: #a78bfa; }
  .fa-users          { color: #a78bfa; }
  .fa-wrench         { color: #94a3b8; }
  .fa-archive        { color: #fbbf24; }
  .fa-arrow-right    { color: #60a5fa; }
  .fa-angle-right    { color: rgba(255,255,255,0.30) !important; }

  /* Nested sub-sub menu */
  .sub-menu .sub-menu li > a { padding-left: 58px !important; font-size: 13px !important; }

  /* Logout bottom */
  .sidebar-logout {
    flex-shrink: 0;
    padding: 10px 12px;
    border-top: 1px solid var(--border);
  }
  .sidebar-logout a {
    display: flex; align-items: center; gap: 10px;
    padding: 9px 14px;
    border-radius: 8px;
    font-size: 13px; font-weight: 500;
    color: rgba(255,100,100,0.85);
    text-decoration: none !important;
    transition: background .15s;
  }
  .sidebar-logout a:hover { background: rgba(239,68,68,0.12); color: #ff7070; }
  .sidebar-logout a i { font-size: 14px; }

  /* ════════════════════════════════════════════════════
     CONTENT OFFSET
  ════════════════════════════════════════════════════ */
  .app-content, #content {
    margin-left: 240px !important;
    margin-top: var(--topbar-h) !important;
  }

  /* ════════════════════════════════════════════════════
     RESPONSIVE — MOBILE FRIENDLY
  ════════════════════════════════════════════════════ */
  @media (max-width: 768px) {
    #main-sidebar { transform: translateX(-240px); width: 240px; transition:transform 0.28s ease; }
    #main-sidebar.mobile-open { transform: translateX(0); box-shadow:4px 0 32px rgba(0,0,0,0.45); }
    #main-topbar { left: 0; padding: 0 12px; }
    .app-content, #content { margin-left: 0 !important; }
    .mob-menu-btn { display: flex !important; }
    /* Larger touch targets on mobile */
    .snav li a { padding: 13px 18px !important; font-size: 14px !important; }
    .snav .sub-menu li a { padding: 11px 24px !important; font-size: 13px !important; }
    .sidebar-logout a { padding: 14px 20px !important; font-size: 14px !important; }
    /* Topbar adjustments */
    .topbar-title-wrap { display: none !important; }
    .topbar-clock { display: none !important; }
    .topbar-user-name { display: none !important; }
    /* Overlay to close sidebar on tap outside */
    #sidebar-backdrop { display:none; position:fixed; inset:0; z-index:199; background:rgba(0,0,0,0.4); }
    #main-sidebar.mobile-open ~ #sidebar-backdrop { display:block; }
  }
  @media (max-width: 480px) {
    #main-topbar { min-height: 52px; }
    .topbar-greeting { display: none !important; }
  }

  /* Hide original header/aside */
  #header.app-header, #aside.app-aside { display: none !important; }
  </style>
</head>
<body>
<div class="app">

<!-- ══════════════════════════════════════════
     TOAST
══════════════════════════════════════════ -->
<div class="notif-toast" id="notifToast">
  <i class="fa fa-bell"></i><span id="notifToastText">You have a new notification!</span>
</div>

<!-- ══════════════════════════════════════════
     SIDEBAR
══════════════════════════════════════════ -->
<aside id="main-sidebar">

  <!-- Brand -->
  <a href="<?php echo $dashboard_url; ?>" class="sidebar-brand" style="text-decoration:none;">
    <img src="logo-image/<?php echo $is_flowx ? 'logo1.jpeg' : 'logo1.jpeg'; ?>" alt="<?php echo APP_NAME; ?>">
    <span class="sidebar-brand-text"><?php echo APP_NAME; ?></span>
  </a>

  <!-- Navigation -->
  <nav class="sidebar-nav">
    <ul class="snav">

      <!-- ── Abra E-Logistics ── -->
      <?php
      $show_elogistics = $is_admin
        || (!empty($permissions['abra_e_logistics'])       && $permissions['abra_e_logistics']==1)
        || (!empty($permissions['abra_global_shipping'])   && $permissions['abra_global_shipping']==1)
        || (!empty($permissions['verification'])           && $permissions['verification']==1)
        || (!empty($permissions['customer_verification'])  && $permissions['customer_verification']==1)
        || (!empty($permissions['global_shipping_clients'])&& $permissions['global_shipping_clients']==1)
        || (!empty($permissions['global_shipping_banners'])&& $permissions['global_shipping_banners']==1)
        || (!empty($permissions['global_shipping_coupons'])&& $permissions['global_shipping_coupons']==1)
        || (!empty($permissions['abra_express'])           && $permissions['abra_express']==1)
        || (!empty($permissions['delivery_agent'])         && $permissions['delivery_agent']==1)
        || (!empty($permissions['abra_truck_union'])       && $permissions['abra_truck_union']==1)
        || (!empty($permissions['vendor_verification'])    && $permissions['vendor_verification']==1)
        || (!empty($permissions['driver_verification'])    && $permissions['driver_verification']==1)
        || (!empty($permissions['truck_union_clients'])    && $permissions['truck_union_clients']==1)
        || (!empty($permissions['rate_cards'])             && $permissions['rate_cards']==1)
        || (!empty($permissions['al_rate_cards'])          && $permissions['al_rate_cards']==1)
        || (!empty($permissions['al_rate_calculation'])    && $permissions['al_rate_calculation']==1)
        || (!empty($permissions['al_manual_rate_cards'])   && $permissions['al_manual_rate_cards']==1)
        || (!empty($permissions['al_leads'])               && $permissions['al_leads']==1)
        || (!empty($permissions['al_leads_database'])      && $permissions['al_leads_database']==1)
        || (!empty($permissions['az_orders'])              && $permissions['az_orders']==1)
        || (!empty($permissions['clients'])                && $permissions['clients']==1)
        || (!empty($permissions['vendors'])                && $permissions['vendors']==1)
        || (!empty($permissions['al_vendors'])             && $permissions['al_vendors']==1)
        || (!empty($permissions['operations'])             && $permissions['operations']==1)
        || (!empty($permissions['fleet_management'])       && $permissions['fleet_management']==1)
        || (!empty($permissions['pickup_orders'])          && $permissions['pickup_orders']==1)
        || (!empty($permissions['rto'])                    && $permissions['rto']==1)
        || (!empty($permissions['customer_service'])       && $permissions['customer_service']==1)
        || (!empty($permissions['shipments'])              && $permissions['shipments']==1)
        || (!empty($permissions['shipment_reports'])       && $permissions['shipment_reports']==1)
        || (!empty($permissions['whatsapp_inbox'])         && $permissions['whatsapp_inbox']==1)
        || (!empty($permissions['accounting'])             && $permissions['accounting']==1)
        || (!empty($permissions['al_accounts'])            && $permissions['al_accounts']==1)
        || (!empty($permissions['assets'])                 && $permissions['assets']==1);
      if ($show_elogistics && (empty($_SESSION['active_entity']) || $_SESSION['active_entity'] === 'elogistics')): ?>
      <li>
        <a><i class="fa fa-truck nav-icon"></i> Abra E-Logistics <i class="fa fa-angle-right nav-arrow"></i></a>
        <ul class="sub-menu">
        <?php if ($is_admin): ?>
        <li><a href="index.php"><i class="fa fa-tachometer"></i> Admin Dashboard</a></li>
        <?php endif; ?>
        <!-- ── Abra Global Shipping ── -->
        <?php if ($is_admin || (!empty($permissions['abra_global_shipping']) && $permissions['abra_global_shipping']==1) || (!empty($permissions['verification']) && $permissions['verification']==1) || (!empty($permissions['customer_verification']) && $permissions['customer_verification']==1) || (!empty($permissions['global_shipping_clients']) && $permissions['global_shipping_clients']==1) || (!empty($permissions['global_shipping_banners']) && $permissions['global_shipping_banners']==1) || (!empty($permissions['global_shipping_coupons']) && $permissions['global_shipping_coupons']==1)): ?>
        <li>
          <a><i class="fa fa-globe nav-icon"></i> Abra Global Shipping <i class="fa fa-angle-right nav-arrow"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['verification']) && $permissions['verification']==1)): ?>
            <li><a><i class="fa fa-check-circle"></i> Verification <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['customer_verification']) && $permissions['customer_verification']==1)): ?><li><a href="customer-verification.php"><i class="fa fa-user"></i> Customer</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['global_shipping_clients']) && $permissions['global_shipping_clients']==1)): ?>
            <li><a><i class="fa fa-users"></i> Clients <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <li><a href="global-shipping-clients.php"><i class="fa fa-globe"></i> Abra Global Shipping Clients</a></li>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['global_shipping_banners']) && $permissions['global_shipping_banners']==1)): ?><li><a href="<?php echo BASE_URL; ?>/api1/customer/manage_banners.php" target="_blank"><i class="fa fa-image"></i> Banners</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['global_shipping_coupons']) && $permissions['global_shipping_coupons']==1)): ?><li><a href="<?php echo BASE_URL; ?>/api1/customer/manage_coupons.php" target="_blank"><i class="fa fa-ticket"></i> Coupons</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>

        <!-- ── Abra Express ── -->
        <?php if ($is_admin || (!empty($permissions['abra_express']) && $permissions['abra_express']==1) || (!empty($permissions['delivery_agent']) && $permissions['delivery_agent']==1)): ?>
        <li>
          <a><i class="fa fa-paper-plane nav-icon"></i> Abra Express <i class="fa fa-angle-right nav-arrow"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['delivery_agent']) && $permissions['delivery_agent']==1)): ?><li><a href="delivery-agent.php"><i class="fa fa-bicycle"></i> Delivery Agent</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>

        <!-- ── Abra Truck Union ── -->
        <?php if ($is_admin || (!empty($permissions['abra_truck_union']) && $permissions['abra_truck_union']==1) || (!empty($permissions['vendor_verification']) && $permissions['vendor_verification']==1) || (!empty($permissions['driver_verification']) && $permissions['driver_verification']==1) || (!empty($permissions['truck_union_clients']) && $permissions['truck_union_clients']==1)): ?>
        <li>
          <a><i class="fa fa-truck nav-icon"></i> Abra Truck Union <i class="fa fa-angle-right nav-arrow"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['verification']) && $permissions['verification']==1)): ?>
            <li><a><i class="fa fa-check-circle"></i> Verification <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['vendor_verification']) && $permissions['vendor_verification']==1)): ?><li><a href="vendor-verification.php"><i class="fa fa-truck"></i> Vendor</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['driver_verification']) && $permissions['driver_verification']==1)): ?><li><a href="/api1/vendor/manage_driver_kyc.php"><i class="fa fa-car"></i> Driver</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>


        <!-- ── Global Rate Cards ── -->
        <?php if ($is_admin
            || (!empty($permissions['rate_cards'])         && $permissions['rate_cards']==1)
            || (!empty($permissions['al_rate_cards'])      && $permissions['al_rate_cards']==1)
            || (!empty($permissions['al_rate_calculation'])&& $permissions['al_rate_calculation']==1)
            || (!empty($permissions['al_manual_rate_cards'])&&$permissions['al_manual_rate_cards']==1)
        ): ?>
        <li><a><i class="fa fa-credit-card"></i> Global Rate Cards <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['al_rate_cards']) && $permissions['al_rate_cards']==1) || (!empty($permissions['al_rate_calculation']) && $permissions['al_rate_calculation']==1) || (!empty($permissions['al_manual_rate_cards']) && $permissions['al_manual_rate_cards']==1)): ?>
            <li><a><i class="fa fa-anchor"></i> AL Rate Cards <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['al_rate_cards']) && $permissions['al_rate_cards']==1)): ?><li><a href="al-rate-cards.php"><i class="fa fa-credit-card"></i> AL Rate Cards</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['al_rate_calculation']) && $permissions['al_rate_calculation']==1)): ?><li><a href="al-rate-calculation.php"><i class="fa fa-calculator"></i> Rate Calculation</a></li><?php endif; ?>
                <?php $has_mrc_access = $is_admin || (!empty($permissions['al_manual_rate_cards']) && $permissions['al_manual_rate_cards']==1); ?>
                <?php if ($has_mrc_access): ?><li><a href="manual-rate-cards.php"><i class="fa fa-list-alt"></i> Manual Rate Cards</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>



        <!-- ── Sales & Marketing ── -->
        <?php if ($is_admin || (!empty($permissions['customer_analytics_al']) && $permissions['customer_analytics_al']==1) || (!empty($permissions['meta_ads_analytics_al']) && $permissions['meta_ads_analytics_al']==1) || (!empty($permissions['google_ads_analytics_al']) && $permissions['google_ads_analytics_al']==1) || (!empty($permissions['search_console_al']) && $permissions['search_console_al']==1) || (!empty($permissions['youtube_studio_al']) && $permissions['youtube_studio_al']==1) || (!empty($permissions['social_media_al']) && $permissions['social_media_al']==1)): ?>
        <li>
          <a><i class="fa fa-line-chart nav-icon"></i> Sales & Marketing <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['customer_analytics_al']) && $permissions['customer_analytics_al']==1)): ?>
            <li><a href="customer-analytics.php?entity=elogistics"><i class="fa fa-line-chart"></i> Customer Analytics</a></li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['meta_ads_analytics_al']) && $permissions['meta_ads_analytics_al']==1)): ?>
            <li><a href="meta-ads-dashboard.php?entity=elogistics"><i class="fa fa-bullhorn"></i> Meta Ads Analytics</a></li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['google_ads_analytics_al']) && $permissions['google_ads_analytics_al']==1)): ?>
            <li><a href="google-ads-dashboard.php?entity=elogistics"><i class="fa fa-google"></i> Google Ads Analytics</a></li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['search_console_al']) && $permissions['search_console_al']==1)): ?>
            <li><a href="gsc-dashboard.php?entity=elogistics"><i class="fa fa-search"></i> Search Console</a></li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['youtube_studio_al']) && $permissions['youtube_studio_al']==1)): ?>
            <li>
              <a><i class="fa fa-youtube-play"></i> AI Video Studio <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <li><a href="youtube-dashboard.php?entity=elogistics"><i class="fa fa-magic"></i> Content Studio</a></li>
                <li><a href="youtube-reports.php?entity=elogistics"><i class="fa fa-bar-chart"></i> Video Insights</a></li>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['social_media_al']) && $permissions['social_media_al']==1)): ?>
            <li>
              <a><i class="fa fa-share-alt"></i> Social Media <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <li><a href="social-dashboard.php?entity=elogistics"><i class="fa fa-calendar"></i> Content & Posts</a></li>
                <li><a href="social-reports.php?entity=elogistics"><i class="fa fa-bar-chart"></i> Reports & Insights</a></li>
              </ul>
            </li>
            <?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>

        <!-- ── Sales ── -->
        <?php if ($is_admin || (!empty($permissions['al_leads']) && $permissions['al_leads']==1)): ?>
        <li><a><i class="fa fa-bar-chart"></i> Sales <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || !empty($permissions['al_sales_dashboard'])): ?>
            <li><a href="sales-admin-dashboard.php?b=" style="color:#60a5fa;font-weight:700;"><i class="fa fa-bar-chart" style="color:#60a5fa;"></i> 🏢 AL Sales Dashboard</a></li>
            <?php endif; ?>
            <li><a><i class="fa fa-truck"></i> AL Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <li><a href="tt-sale-leads.php?b=al"><i class="fa fa-bullseye"></i> Sale Leads</a></li>
                <?php if ($is_admin || (!empty($permissions['al_leads_database']) && $permissions['al_leads_database']==1)): ?><li><a href="tt-customer-database.php?b=al"><i class="fa fa-database"></i> Customer Database</a></li><?php endif; ?>
              </ul>
            </li>
          </ul>
        </li>
        <?php endif; ?>


        <!-- ── Clients ── -->
        <?php if ($is_admin || (!empty($permissions['clients']) && $permissions['clients']==1)): ?>
        <li><a><i class="fa fa-users"></i> Clients <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['clients']) && $permissions['clients']==1)): ?><li><a href="management-client.php"><i class="fa fa-user"></i> AL Clients</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>


        <!-- ── Vendors ── -->
        <?php if ($is_admin || (!empty($permissions['vendors']) && $permissions['vendors']==1)): ?>
        <li><a><i class="fa fa-exchange"></i> Vendors <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['al_vendors']) && $permissions['al_vendors']==1)): ?>
            <li><a><i class="fa fa-truck"></i> AL Vendors <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['truck_union_clients']) && $permissions['truck_union_clients']==1)): ?><li><a href="truck-union-clients.php"><i class="fa fa-globe"></i> Online Vendors</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['al_vendors_offline']) && $permissions['al_vendors_offline']==1)): ?><li><a href="vendors.php?b=al"><i class="fa fa-users"></i> Offline Vendors</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['al_vendor_calculation']) && $permissions['al_vendor_calculation']==1)): ?><li><a href="<?php echo BASE_URL; ?>/dashboard/vendor-price-calculator.php" target="_blank"><i class="fa fa-calculator"></i> AL Vendor Calculation</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['vendor_verification']) && $permissions['vendor_verification']==1)): ?><li><a href="vendor-verification.php"><i class="fa fa-check-circle"></i> Vendor Verification</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['vendor_onboarding']) && $permissions['vendor_onboarding']==1)): ?><li><a href="vendor-onboarding.php"><i class="fa fa-plus-circle"></i> Vendor Onboarding</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['vendor_settlement']) && $permissions['vendor_settlement']==1)): ?><li><a href="/api1/vendor/manage_vendor_assignments.php"><i class="fa fa-money"></i> Vendor Settlement</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['abra_service_vendors']) && $permissions['abra_service_vendors']==1)): ?><li><a href="vendors.php?b=asv"><i class="fa fa-wrench"></i> Abra Service Vendors</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>

        <!-- ── Operations ── -->
        <?php if ($is_admin || (!empty($permissions['operations']) && $permissions['operations']==1)): ?>
        <li>
          <a><i class="fa fa-wrench nav-icon"></i> Operations <i class="fa fa-angle-right nav-arrow"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['fleet_management']) && $permissions['fleet_management']==1)): ?>
            <li><a><i class="fa fa-truck"></i> Fleet Management <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['fleet_vehicles']) && $permissions['fleet_vehicles']==1)): ?>
                <li><a><i class="fa fa-car"></i> Vehicles <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                  <ul class="sub-menu">
                    <li><a href="fleet_vehicles_list.php"><i class="fa fa-car"></i> Vehicles</a></li>
                    <?php if ($is_admin || (!empty($permissions['fleet_maintenance']) && $permissions['fleet_maintenance']==1)): ?><li><a href="fleet_maintenance_list.php"><i class="fa fa-wrench"></i> Maintenance</a></li><?php endif; ?>
                    <?php if ($is_admin || (!empty($permissions['customer_fleet'])    && $permissions['customer_fleet']   ==1)): ?><li><a href="customer_fleet_list.php"><i class="fa fa-users"></i> Customer Fleet</a></li><?php endif; ?>
                  </ul>
                </li>
                <?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['fleet_drivers'])      && $permissions['fleet_drivers']     ==1)): ?><li><a href="fleet_drivers_list.php"><i class="fa fa-user"></i> Drivers</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['fleet_gps_tracking']) && $permissions['fleet_gps_tracking']==1)): ?><li><a href="fleet_gps_tracking.php"><i class="fa fa-map-marker"></i> GPS Tracking</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['fleet_trips'])        && $permissions['fleet_trips']       ==1)): ?><li><a href="fleet_trips_list.php"><i class="fa fa-road"></i> Trips & Deliveries</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['storage']) && $permissions['storage']==1) || (!empty($permissions['warehouses']) && $permissions['warehouses']==1) || (!empty($permissions['products']) && $permissions['products']==1) || (!empty($permissions['fulfillment']) && $permissions['fulfillment']==1) || (!empty($permissions['inventory_management']) && $permissions['inventory_management']==1) || (!empty($permissions['stock_reservation']) && $permissions['stock_reservation']==1) || (!empty($permissions['damage_report']) && $permissions['damage_report']==1) || (!empty($permissions['fleet_list']) && $permissions['fleet_list']==1)): ?>
            <li><a><i class="fa fa-building"></i> Warehouse <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['warehouses'])           && $permissions['warehouses']          ==1)): ?><li><a href="warehouses.php"><i class="fa fa-building"></i> Warehouses</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['products'])             && $permissions['products']            ==1)): ?><li><a href="product.php"><i class="fa fa-cube"></i> Products</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['storage'])              && $permissions['storage']             ==1)): ?><li><a href="storage.php"><i class="fa fa-archive"></i> Storage</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['fulfillment'])          && $permissions['fulfillment']         ==1)): ?><li><a href="fulfillment.php"><i class="fa fa-check-circle"></i> Fulfillment</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['inventory_management']) && $permissions['inventory_management']==1)): ?><li><a href="inventory.php"><i class="fa fa-list-alt"></i> Inventory</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['stock_reservation'])    && $permissions['stock_reservation']   ==1)): ?><li><a href="stock-reservation.php"><i class="fa fa-bookmark"></i> Stock Reservation</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['damage_report'])        && $permissions['damage_report']       ==1)): ?><li><a href="damage-report.php"><i class="fa fa-exclamation-triangle"></i> Damage Report</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['fleet_list'])           && $permissions['fleet_list']          ==1)): ?><li><a href="fleet_list.php"><i class="fa fa-truck"></i> Fleet</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['pickup_orders']) && $permissions['pickup_orders']==1)): ?>
            <li><a><i class="fa fa-plus-circle"></i> Pickup <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['pickup_orders'])  && $permissions['pickup_orders'] ==1)): ?><li><a href="pickup-orders.php"><i class="fa fa-plus-circle"></i> Pickup Orders</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['pickup_reports']) && $permissions['pickup_reports']==1)): ?><li><a href="pickup-reports.php"><i class="fa fa-file-text"></i> Pickup Reports</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['process_of_scanning']) && $permissions['process_of_scanning']==1)): ?><li><a href="process-of-scanning.php"><i class="fa fa-barcode"></i> Process of Scanning</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['order_update'])        && $permissions['order_update']       ==1)): ?><li><a href="order-update.php"><i class="fa fa-refresh"></i> Order Update</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['rts'])                 && $permissions['rts']                ==1)): ?><li><a href="rts.php"><i class="fa fa-undo"></i> RTS</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['rto']) && $permissions['rto']==1)): ?>
            <li><a><i class="fa fa-reply"></i> RTO <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['rto'])             && $permissions['rto']            ==1)): ?><li><a href="rto.php"><i class="fa fa-reply"></i> RTO</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['process_for_rto']) && $permissions['process_for_rto']==1)): ?><li><a href="process-for-rto.php"><i class="fa fa-cogs"></i> Process for RTO</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['rto_inscan'])      && $permissions['rto_inscan']     ==1)): ?><li><a href="rto-inscan.php"><i class="fa fa-sign-in"></i> RTO Inscan</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['rto_outscan'])     && $permissions['rto_outscan']    ==1)): ?><li><a href="rto-outscan.php"><i class="fa fa-sign-out"></i> RTO Outscan</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['rto_delivered'])   && $permissions['rto_delivered']  ==1)): ?><li><a href="rto-delivered.php"><i class="fa fa-check"></i> RTO Delivered</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['cancel_shipment']) && $permissions['cancel_shipment']==1)): ?><li><a href="cancel-shipment.php"><i class="fa fa-times-circle"></i> Cancel Shipment</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['pod_pickup']) && $permissions['pod_pickup']==1) || (!empty($permissions['pod_delivery']) && $permissions['pod_delivery']==1)): ?>
            <li><a><i class="fa fa-file-image-o"></i> POD <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
              <ul class="sub-menu">
                <?php if ($is_admin || (!empty($permissions['pod_pickup'])   && $permissions['pod_pickup']  ==1)): ?><li><a href="pickup-pod.php"><i class="fa fa-upload"></i> Pickup POD</a></li><?php endif; ?>
                <?php if ($is_admin || (!empty($permissions['pod_delivery']) && $permissions['pod_delivery']==1)): ?><li><a href="delivery-pod.php"><i class="fa fa-download"></i> Delivery POD</a></li><?php endif; ?>
              </ul>
            </li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['fleet_assign']) && $permissions['fleet_assign']==1)): ?>
            <li><a href="/dashboard/vehicles_dashboard.php"><i class="fa fa-truck"></i> Fleet Assign</a></li>
            <?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['az_orders']) && $permissions['az_orders']==1)): ?><li><a href="abra-zylo-orders.php"><i class="fa fa-tag"></i> AZ Orders</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>


        <!-- ── Customer Service ── -->
        <?php if ($is_admin || (!empty($permissions['customer_service']) && $permissions['customer_service']==1)): ?>
        <li><a><i class="fa fa-headphones"></i> Customer Service <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['shipments']) && $permissions['shipments']==1)): ?><li><a href="active-shipments.php"><i class="fa fa-truck"></i> Shipments</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['shipment_reports']) && $permissions['shipment_reports']==1)): ?><li><a href="shipment-reports.php"><i class="fa fa-file-text"></i> Shipment Reports</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['whatsapp_inbox']) && $permissions['whatsapp_inbox']==1)): ?><li><a href="whatsapp-inbox.php"><i class="fa fa-comment" style="color:#25D366"></i> WhatsApp Inbox</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['styles_status']) && $permissions['styles_status']==1)): ?><li><a href="styles.php"><i class="fa fa-magic"></i> Styles Status</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>


        <!-- ── Accounting ── -->
        <?php if ($is_admin || (!empty($permissions['accounting']) && $permissions['accounting']==1) || (!empty($permissions['al_accounts']) && $permissions['al_accounts']==1) || (!empty($permissions['assets_al']) && $permissions['assets_al']==1) || (!empty($permissions['company_documents_al']) && $permissions['company_documents_al']==1)): ?>
        <li><a><i class="fa fa-calculator"></i> Accounting <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
          <ul class="sub-menu">
            <?php if ($is_admin || (!empty($permissions['al_accounts']) && $permissions['al_accounts']==1)): ?><li><a href="al-accounts.php"><i class="fa fa-folder-open"></i> AL Accounts</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['assets_al']) && $permissions['assets_al']==1)): ?><li><a href="assets.php?entity=elogistics"><i class="fa fa-cubes"></i> Assets</a></li><?php endif; ?>
            <?php if ($is_admin || (!empty($permissions['company_documents_al']) && $permissions['company_documents_al']==1)): ?><li><a href="company-documents.php?entity=elogistics"><i class="fa fa-file-text"></i> Company Documents</a></li><?php endif; ?>
          </ul>
        </li>
        <?php endif; ?>

        </ul>
      </li>
      <?php endif; ?>

      <!-- ── Abra Design and Build ── -->
      <?php
      $show_design = $is_admin
        || (!empty($permissions['abra_design_build'])      && $permissions['abra_design_build']==1)
        || (!empty($permissions['adb_leads'])              && $permissions['adb_leads']==1)
        || (!empty($permissions['adb_projects'])           && $permissions['adb_projects']==1)
        || (!empty($permissions['adb_finance'])            && $permissions['adb_finance']==1)
        || (!empty($permissions['adb_manual_rate_cards'])  && $permissions['adb_manual_rate_cards']==1)
        || (!empty($permissions['adb_customer_db'])        && $permissions['adb_customer_db']==1)
        || (!empty($permissions['db_leads'])               && $permissions['db_leads']==1)
        || (!empty($permissions['db_vendors'])             && $permissions['db_vendors']==1)
        || (!empty($permissions['db_rate_cards'])          && $permissions['db_rate_cards']==1);
      if ($show_design && (empty($_SESSION['active_entity']) || $_SESSION['active_entity'] === 'design')): ?>
      <li>
        <a>
          <span class="nav-icon-svg">
            <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <rect x="3.5" y="4" width="9.5" height="17" rx="0.6" fill="currentColor"/>
              <rect x="13.5" y="8.5" width="7" height="12.5" rx="0.6" fill="currentColor" opacity="0.6"/>
              <rect x="5.5" y="6.8" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="9" y="6.8" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="5.5" y="10.5" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="9" y="10.5" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="5.5" y="14.2" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="9" y="14.2" width="1.9" height="1.9" rx="0.3" fill="var(--navy-800)"/>
              <rect x="15.7" y="11.2" width="1.6" height="1.6" rx="0.3" fill="var(--navy-800)"/>
              <rect x="18" y="11.2" width="1.6" height="1.6" rx="0.3" fill="var(--navy-800)"/>
              <rect x="15.7" y="14.7" width="1.6" height="1.6" rx="0.3" fill="var(--navy-800)"/>
              <rect x="18" y="14.7" width="1.6" height="1.6" rx="0.3" fill="var(--navy-800)"/>
            </svg>
          </span>
          Abra Design & Build <i class="fa fa-angle-right nav-arrow"></i>
        </a>
        <ul class="sub-menu">
          <?php if ($is_admin || (!empty($permissions['adb_leads']) && $permissions['adb_leads']==1)): ?>
          <li><a><i class="fa fa-users"></i> Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['adb_lead_list']) && $permissions['adb_lead_list']==1)): ?>
              <li><a href="db-leads-list.php"><i class="fa fa-list"></i> Lead Management</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['adb_lead_dashboard']) && $permissions['adb_lead_dashboard']==1)): ?>
              <li><a href="lead-dashboard.php"><i class="fa fa-tachometer"></i> Lead Dashboard</a></li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>
          
          <?php if ($is_admin || (!empty($permissions['adb_projects']) && $permissions['adb_projects']==1)): ?>
          <li><a><i class="fa fa-folder-open"></i> Projects <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['adb_projects_list']) && $permissions['adb_projects_list']==1)): ?>
              <li><a href="db-projects-list.php"><i class="fa fa-list"></i> Project Management</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['adb_proj_tasks']) && $permissions['adb_proj_tasks']==1)): ?>
              <li><a href="db-project-tasks.php"><i class="fa fa-check-square"></i> Tasks</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['adb_proj_proof']) && $permissions['adb_proj_proof']==1)): ?>
              <li><a href="db-work-proof.php"><i class="fa fa-file-image-o"></i> Work Proofs</a></li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <?php if ($is_admin || (!empty($permissions['adb_manual_rate_cards']) && $permissions['adb_manual_rate_cards']==1)): ?>
          <li><a href="db-design-quotation-standalone.php"><i class="fa fa-money"></i> Manual Rate Card</a></li>
          <?php endif; ?>
          
          <?php 
          $has_any_finance = $is_admin || (!empty($permissions['adb_finance']) && $permissions['adb_finance']==1) || 
                             (!empty($permissions['adb_proj_finance']) && $permissions['adb_proj_finance']==1) || 
                             (!empty($permissions['adb_proj_fin_dash']) && $permissions['adb_proj_fin_dash']==1) || 
                             (!empty($permissions['adb_proj_fin_budg']) && $permissions['adb_proj_fin_budg']==1) || 
                             (!empty($permissions['adb_proj_fin_exp']) && $permissions['adb_proj_fin_exp']==1) || 
                             (!empty($permissions['adb_proj_fin_pay']) && $permissions['adb_proj_fin_pay']==1);
                             
          $has_finance_projects = $is_admin || (!empty($permissions['adb_finance_projects']) && $permissions['adb_finance_projects']==1) ||
                                  (!empty($permissions['adb_proj_finance']) && $permissions['adb_proj_finance']==1) || 
                                  (!empty($permissions['adb_proj_fin_dash']) && $permissions['adb_proj_fin_dash']==1) || 
                                  (!empty($permissions['adb_proj_fin_budg']) && $permissions['adb_proj_fin_budg']==1) || 
                                  (!empty($permissions['adb_proj_fin_exp']) && $permissions['adb_proj_fin_exp']==1) || 
                                  (!empty($permissions['adb_proj_fin_pay']) && $permissions['adb_proj_fin_pay']==1);
          ?>
          <?php if ($has_any_finance): ?>
          <li><a><i class="fa fa-money"></i> Finance <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($has_finance_projects): ?>
              <li><a href="db-financial-info.php"><i class="fa fa-line-chart"></i> P&L Tracking</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['adb_finance_reports']) && $permissions['adb_finance_reports']==1)): ?>
              <li><a href="db-reports-page.php"><i class="fa fa-file-text"></i> Reports</a></li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>
          
          <?php if ($is_admin || (!empty($permissions['adb_customer_db']) && $permissions['adb_customer_db']==1)): ?>
          <li><a href="db-customer-project-converted.php"><i class="fa fa-users"></i> Clients</a></li>
          <?php endif; ?>

          <!-- ── Sales & Marketing ── -->
          <?php if ($is_admin || (!empty($permissions['customer_analytics_db']) && $permissions['customer_analytics_db']==1) || (!empty($permissions['meta_ads_analytics_db']) && $permissions['meta_ads_analytics_db']==1) || (!empty($permissions['google_ads_analytics_db']) && $permissions['google_ads_analytics_db']==1) || (!empty($permissions['search_console_db']) && $permissions['search_console_db']==1) || (!empty($permissions['youtube_studio_db']) && $permissions['youtube_studio_db']==1) || (!empty($permissions['social_media_db']) && $permissions['social_media_db']==1)): ?>
          <li>
            <a><i class="fa fa-line-chart nav-icon"></i> Sales & Marketing <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['customer_analytics_db']) && $permissions['customer_analytics_db']==1)): ?>
              <li><a href="customer-analytics.php?entity=design"><i class="fa fa-line-chart"></i> Customer Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['meta_ads_analytics_db']) && $permissions['meta_ads_analytics_db']==1)): ?>
              <li><a href="meta-ads-dashboard.php?entity=design"><i class="fa fa-bullhorn"></i> Meta Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['google_ads_analytics_db']) && $permissions['google_ads_analytics_db']==1)): ?>
              <li><a href="google-ads-dashboard.php?entity=design"><i class="fa fa-google"></i> Google Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['search_console_db']) && $permissions['search_console_db']==1)): ?>
              <li><a href="gsc-dashboard.php?entity=design"><i class="fa fa-search"></i> Search Console</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['youtube_studio_db']) && $permissions['youtube_studio_db']==1)): ?>
              <li>
                <a><i class="fa fa-youtube-play"></i> AI Video Studio <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="youtube-dashboard.php?entity=design"><i class="fa fa-magic"></i> Content Studio</a></li>
                  <li><a href="youtube-reports.php?entity=design"><i class="fa fa-bar-chart"></i> Video Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['social_media_db']) && $permissions['social_media_db']==1)): ?>
              <li>
                <a><i class="fa fa-share-alt"></i> Social Media <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="social-dashboard.php?entity=design"><i class="fa fa-calendar"></i> Content & Posts</a></li>
                  <li><a href="social-reports.php?entity=design"><i class="fa fa-bar-chart"></i> Reports & Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Sales ── -->
          <?php if ($is_admin || (!empty($permissions['db_leads']) && $permissions['db_leads']==1)): ?>
          <li><a><i class="fa fa-bar-chart"></i> Sales <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || !empty($permissions['db_sales_dashboard'])): ?>
              <li><a href="sales-admin-dashboard.php?b=db" style="color:#c084fc;font-weight:700;"><i class="fa fa-bar-chart" style="color:#c084fc;"></i> 🏗️ DB Sales Dashboard</a></li>
              <?php endif; ?>
              <li><a><i class="fa fa-database"></i> DB Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="tt-sale-leads.php?b=db"><i class="fa fa-bullseye"></i> Sale Leads</a></li>
                  <?php if ($is_admin || (!empty($permissions['db_leads_database']) && $permissions['db_leads_database']==1)): ?><li><a href="tt-customer-database.php?b=db"><i class="fa fa-database"></i> Customer Database</a></li><?php endif; ?>
                </ul>
              </li>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Vendors ── -->
          <?php if ($is_admin || (!empty($permissions['db_vendors']) && $permissions['db_vendors']==1)): ?>
          <li><a><i class="fa fa-exchange"></i> Vendors <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['db_vendors']) && $permissions['db_vendors']==1)): ?><li><a href="vendors.php?b=db"><i class="fa fa-database"></i> DB Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['abra_service_vendors']) && $permissions['abra_service_vendors']==1)): ?><li><a href="vendors.php?b=asv"><i class="fa fa-wrench"></i> Abra Service Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['vendor_onboarding']) && $permissions['vendor_onboarding']==1)): ?><li><a href="vendor-onboarding.php"><i class="fa fa-plus-circle"></i> Vendor Onboarding</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Accounting ── -->
          <?php if ($is_admin || (!empty($permissions['accounting']) && $permissions['accounting']==1) || (!empty($permissions['assets_db']) && $permissions['assets_db']==1) || (!empty($permissions['company_documents_db']) && $permissions['company_documents_db']==1)): ?>
          <li><a><i class="fa fa-calculator"></i> Accounting <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['assets_db']) && $permissions['assets_db']==1)): ?><li><a href="assets.php?entity=design"><i class="fa fa-cubes"></i> Assets</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['company_documents_db']) && $permissions['company_documents_db']==1)): ?><li><a href="company-documents.php?entity=design"><i class="fa fa-file-text"></i> Company Documents</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

        </ul>
      </li>
      <?php endif; ?>

      <!-- ── Abra Global Trading ── -->
      <?php
      $show_trading = $is_admin
        || (!empty($permissions['abra_global_trading_group']) && $permissions['abra_global_trading_group']==1)
        || (!empty($permissions['abra_global_trading'])     && $permissions['abra_global_trading']==1)
        || (!empty($permissions['agt_leads'])               && $permissions['agt_leads']==1)
        || (!empty($permissions['agt_leads_database'])      && $permissions['agt_leads_database']==1)
        || (!empty($permissions['agt_rate_cards'])          && $permissions['agt_rate_cards']==1)
        || (!empty($permissions['agt_manual_rate_cards'])   && $permissions['agt_manual_rate_cards']==1)
        || (!empty($permissions['az_leads'])                && $permissions['az_leads']==1)
        || (!empty($permissions['az_leads_database'])       && $permissions['az_leads_database']==1)
        || (!empty($permissions['az_vendors'])              && $permissions['az_vendors']==1)
        || (!empty($permissions['az_orders'])               && $permissions['az_orders']==1)
        || (!empty($permissions['agt_clients'])             && $permissions['agt_clients']==1);
      if ($show_trading && (empty($_SESSION['active_entity']) || $_SESSION['active_entity'] === 'trading')): ?>
      <li>
        <a><i class="fa fa-globe nav-icon"></i> Abra Global Trading <i class="fa fa-angle-right nav-arrow"></i></a>
        <ul class="sub-menu">
          <!-- ── Manual Rate Cards ── -->
          <?php if ($is_admin || (!empty($permissions['agt_manual_rate_cards']) && $permissions['agt_manual_rate_cards']==1) || (!empty($permissions['agt_rate_cards']) && $permissions['agt_rate_cards']==1)): ?>
          <li><a href="abra-global-trading-manual_rate_card.php"><i class="fa fa-list-alt"></i> Manual Rate Cards</a></li>
          <?php endif; ?>

          <!-- ── Sales & Marketing ── -->
          <?php if ($is_admin || (!empty($permissions['customer_analytics_az']) && $permissions['customer_analytics_az']==1) || (!empty($permissions['meta_ads_analytics_az']) && $permissions['meta_ads_analytics_az']==1) || (!empty($permissions['google_ads_analytics_az']) && $permissions['google_ads_analytics_az']==1) || (!empty($permissions['search_console_az']) && $permissions['search_console_az']==1) || (!empty($permissions['youtube_studio_az']) && $permissions['youtube_studio_az']==1) || (!empty($permissions['social_media_az']) && $permissions['social_media_az']==1)): ?>
          <li>
            <a><i class="fa fa-line-chart nav-icon"></i> Sales & Marketing <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['customer_analytics_az']) && $permissions['customer_analytics_az']==1)): ?>
              <li><a href="customer-analytics.php?entity=trading"><i class="fa fa-line-chart"></i> Customer Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['meta_ads_analytics_az']) && $permissions['meta_ads_analytics_az']==1)): ?>
              <li><a href="meta-ads-dashboard.php?entity=trading"><i class="fa fa-bullhorn"></i> Meta Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['google_ads_analytics_az']) && $permissions['google_ads_analytics_az']==1)): ?>
              <li><a href="google-ads-dashboard.php?entity=trading"><i class="fa fa-google"></i> Google Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['search_console_az']) && $permissions['search_console_az']==1)): ?>
              <li><a href="gsc-dashboard.php?entity=trading"><i class="fa fa-search"></i> Search Console</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['youtube_studio_az']) && $permissions['youtube_studio_az']==1)): ?>
              <li>
                <a><i class="fa fa-youtube-play"></i> AI Video Studio <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="youtube-dashboard.php?entity=trading"><i class="fa fa-magic"></i> Content Studio</a></li>
                  <li><a href="youtube-reports.php?entity=trading"><i class="fa fa-bar-chart"></i> Video Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['social_media_az']) && $permissions['social_media_az']==1)): ?>
              <li>
                <a><i class="fa fa-share-alt"></i> Social Media <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="social-dashboard.php?entity=trading"><i class="fa fa-calendar"></i> Content & Posts</a></li>
                  <li><a href="social-reports.php?entity=trading"><i class="fa fa-bar-chart"></i> Reports & Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Sales ── -->
          <?php if ($is_admin || (!empty($permissions['agt_leads']) && $permissions['agt_leads']==1) || (!empty($permissions['az_leads']) && $permissions['az_leads']==1) || (!empty($permissions['az_orders']) && $permissions['az_orders']==1)): ?>
          <li><a><i class="fa fa-bar-chart"></i> Sales <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || !empty($permissions['agt_sales_dashboard'])): ?>
              <li><a href="sales-admin-dashboard.php?b=agt" style="color:#4ade80;font-weight:700;"><i class="fa fa-bar-chart" style="color:#4ade80;"></i> 🌏 AGT Sales Dashboard</a></li>
              <?php endif; ?>
              <?php if ($is_admin || !empty($permissions['az_sales_dashboard'])): ?>
              <li><a href="sales-admin-dashboard.php?b=az" style="color:#38bdf8;font-weight:700;"><i class="fa fa-bar-chart" style="color:#38bdf8;"></i> ⚡ AZ Sales Dashboard</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['agt_leads']) && $permissions['agt_leads']==1)): ?>
              <li><a><i class="fa fa-globe"></i> AGT Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="tt-sale-leads.php?b=agt"><i class="fa fa-bullseye"></i> Sale Leads</a></li>
                  <?php if ($is_admin || (!empty($permissions['agt_leads_database']) && $permissions['agt_leads_database']==1)): ?><li><a href="tt-customer-database.php?b=agt"><i class="fa fa-database"></i> Customer Database</a></li><?php endif; ?>
                </ul>
              </li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['az_leads']) && $permissions['az_leads']==1)): ?>
              <li><a><i class="fa fa-tag"></i> AZ Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="tt-sale-leads.php?b=az"><i class="fa fa-bullseye"></i> Sale Leads</a></li>
                  <li><a href="abra_sales_leads.php"><i class="fa fa-globe"></i> Sales Leads - Website</a></li>
                  <li><a href="abra_vendors.php"><i class="fa fa-exchange"></i> Vendor Management</a></li>
                  <?php if ($is_admin || (!empty($permissions['az_leads_database']) && $permissions['az_leads_database']==1)): ?><li><a href="tt-customer-database.php?b=az"><i class="fa fa-database"></i> Customer Database</a></li><?php endif; ?>
                </ul>
              </li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Clients ── -->
          <?php if ($is_admin || (!empty($permissions['agt_clients']) && $permissions['agt_clients']==1)): ?>
          <li><a href="management-client-trading.php"><i class="fa fa-users"></i> Clients</a></li>
          <?php endif; ?>

          <!-- ── Vendors ── -->
          <?php if ($is_admin || (!empty($permissions['az_vendors']) && $permissions['az_vendors']==1) || (!empty($permissions['abra_global_trading']) && $permissions['abra_global_trading']==1)): ?>
          <li><a><i class="fa fa-exchange"></i> Vendors <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['abra_global_trading']) && $permissions['abra_global_trading']==1)): ?><li><a href="vendors.php?b=agt"><i class="fa fa-globe"></i> AGT Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['az_vendors']) && $permissions['az_vendors']==1)): ?><li><a href="vendors.php?b=az"><i class="fa fa-tag"></i> AZ Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['abra_service_vendors']) && $permissions['abra_service_vendors']==1)): ?><li><a href="vendors.php?b=asv"><i class="fa fa-wrench"></i> Abra Service Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['vendor_onboarding']) && $permissions['vendor_onboarding']==1)): ?><li><a href="vendor-onboarding.php"><i class="fa fa-plus-circle"></i> Vendor Onboarding</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Accounting ── -->
          <?php if ($is_admin || (!empty($permissions['accounting']) && $permissions['accounting']==1) || (!empty($permissions['assets_az']) && $permissions['assets_az']==1) || (!empty($permissions['company_documents_az']) && $permissions['company_documents_az']==1)): ?>
          <li><a><i class="fa fa-calculator"></i> Accounting <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['assets_az']) && $permissions['assets_az']==1)): ?><li><a href="assets.php?entity=trading"><i class="fa fa-cubes"></i> Assets</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['company_documents_az']) && $permissions['company_documents_az']==1)): ?><li><a href="company-documents.php?entity=trading"><i class="fa fa-file-text"></i> Company Documents</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

        </ul>
      </li>
      <?php endif; ?>

      <!-- ── Abra Food Industry ── -->
      <?php
      $show_food = $is_admin
        || (!empty($permissions['abra_food_industry'])     && $permissions['abra_food_industry']==1)
        || (!empty($permissions['abra_food_works'])        && $permissions['abra_food_works']==1)
        || (!empty($permissions['afw_leads'])              && $permissions['afw_leads']==1)
        || (!empty($permissions['afw_leads_database'])     && $permissions['afw_leads_database']==1)
        || (!empty($permissions['afw_rate_cards'])         && $permissions['afw_rate_cards']==1)
        || (!empty($permissions['afw_manual_rate_cards'])  && $permissions['afw_manual_rate_cards']==1)
        || (!empty($permissions['afw_clients'])            && $permissions['afw_clients']==1);
      if ($show_food && (empty($_SESSION['active_entity']) || $_SESSION['active_entity'] === 'food')): ?>
      <li>
        <a><i class="fa fa-cutlery nav-icon"></i> Abra Food Industry <i class="fa fa-angle-right nav-arrow"></i></a>
        <ul class="sub-menu">
          <!-- ── Manual Rate Cards ── -->
          <?php if ($is_admin || (!empty($permissions['afw_manual_rate_cards']) && $permissions['afw_manual_rate_cards']==1) || (!empty($permissions['afw_rate_cards']) && $permissions['afw_rate_cards']==1)): ?>
          <li><a href="abra-food-works-quotations.php"><i class="fa fa-list-alt"></i> Manual Rate Cards</a></li>
          <?php endif; ?>

          <!-- ── Sales & Marketing ── -->
          <?php if ($is_admin || (!empty($permissions['customer_analytics_afw']) && $permissions['customer_analytics_afw']==1) || (!empty($permissions['meta_ads_analytics_afw']) && $permissions['meta_ads_analytics_afw']==1) || (!empty($permissions['google_ads_analytics_afw']) && $permissions['google_ads_analytics_afw']==1) || (!empty($permissions['search_console_afw']) && $permissions['search_console_afw']==1) || (!empty($permissions['youtube_studio_afw']) && $permissions['youtube_studio_afw']==1) || (!empty($permissions['social_media_afw']) && $permissions['social_media_afw']==1)): ?>
          <li>
            <a><i class="fa fa-line-chart nav-icon"></i> Sales & Marketing <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['customer_analytics_afw']) && $permissions['customer_analytics_afw']==1)): ?>
              <li><a href="customer-analytics.php?entity=food"><i class="fa fa-line-chart"></i> Customer Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['meta_ads_analytics_afw']) && $permissions['meta_ads_analytics_afw']==1)): ?>
              <li><a href="meta-ads-dashboard.php?entity=food"><i class="fa fa-bullhorn"></i> Meta Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['google_ads_analytics_afw']) && $permissions['google_ads_analytics_afw']==1)): ?>
              <li><a href="google-ads-dashboard.php?entity=food"><i class="fa fa-google"></i> Google Ads Analytics</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['search_console_afw']) && $permissions['search_console_afw']==1)): ?>
              <li><a href="gsc-dashboard.php?entity=food"><i class="fa fa-search"></i> Search Console</a></li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['youtube_studio_afw']) && $permissions['youtube_studio_afw']==1)): ?>
              <li>
                <a><i class="fa fa-youtube-play"></i> AI Video Studio <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="youtube-dashboard.php?entity=food"><i class="fa fa-magic"></i> Content Studio</a></li>
                  <li><a href="youtube-reports.php?entity=food"><i class="fa fa-bar-chart"></i> Video Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['social_media_afw']) && $permissions['social_media_afw']==1)): ?>
              <li>
                <a><i class="fa fa-share-alt"></i> Social Media <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="social-dashboard.php?entity=food"><i class="fa fa-calendar"></i> Content & Posts</a></li>
                  <li><a href="social-reports.php?entity=food"><i class="fa fa-bar-chart"></i> Reports & Insights</a></li>
                </ul>
              </li>
              <?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Sales ── -->
          <?php if ($is_admin || (!empty($permissions['afw_leads']) && $permissions['afw_leads']==1) || (!empty($permissions['afw_leads_database']) && $permissions['afw_leads_database']==1)): ?>
          <li><a><i class="fa fa-bar-chart"></i> Sales <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || !empty($permissions['afw_sales_dashboard'])): ?>
              <li><a href="sales-admin-dashboard.php?b=afw" style="color:#f87171;font-weight:700;"><i class="fa fa-bar-chart" style="color:#f87171;"></i> 🍽️ AFW Sales Dashboard</a></li>
              <?php endif; ?>
              <li><a><i class="fa fa-cutlery"></i> AFW Leads <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <li><a href="tt-sale-leads.php?b=afw"><i class="fa fa-bullseye"></i> Sale Leads</a></li>
                  <?php if ($is_admin || (!empty($permissions['afw_leads_database']) && $permissions['afw_leads_database']==1)): ?><li><a href="tt-customer-database.php?b=afw"><i class="fa fa-database"></i> Customer Database</a></li><?php endif; ?>
                </ul>
              </li>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Clients ── -->
          <?php if ($is_admin || (!empty($permissions['afw_clients']) && $permissions['afw_clients']==1)): ?>
          <li><a href="management-client-food.php"><i class="fa fa-users"></i> Clients</a></li>
          <?php endif; ?>

          <!-- ── Vendors ── -->
          <?php if ($is_admin || (!empty($permissions['abra_food_works']) && $permissions['abra_food_works']==1)): ?>
          <li><a><i class="fa fa-exchange"></i> Vendors <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['abra_food_works']) && $permissions['abra_food_works']==1)): ?><li><a href="vendors.php?b=afw"><i class="fa fa-cutlery"></i> AFW Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['abra_service_vendors']) && $permissions['abra_service_vendors']==1)): ?><li><a href="vendors.php?b=asv"><i class="fa fa-wrench"></i> Abra Service Vendors</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['vendor_onboarding']) && $permissions['vendor_onboarding']==1)): ?><li><a href="vendor-onboarding.php"><i class="fa fa-plus-circle"></i> Vendor Onboarding</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

          <!-- ── Accounting ── -->
          <?php if ($is_admin || (!empty($permissions['accounting']) && $permissions['accounting']==1) || (!empty($permissions['assets_afw']) && $permissions['assets_afw']==1) || (!empty($permissions['company_documents_afw']) && $permissions['company_documents_afw']==1)): ?>
          <li><a><i class="fa fa-calculator"></i> Accounting <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['assets_afw']) && $permissions['assets_afw']==1)): ?><li><a href="assets.php?entity=food"><i class="fa fa-cubes"></i> Assets</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['company_documents_afw']) && $permissions['company_documents_afw']==1)): ?><li><a href="company-documents.php?entity=food"><i class="fa fa-file-text"></i> Company Documents</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>

        </ul>
      </li>
      <?php endif; ?>

      <!-- ── HRM ── -->
      <?php if ($is_admin || (!empty($permissions['hrm']) && $permissions['hrm']==1) || (!empty($permissions['hrm_screening_hub']) && $permissions['hrm_screening_hub']==1) || (!empty($permissions['hrm_career']) && $permissions['hrm_career']==1) || (!empty($permissions['hrm_hiring_process']) && $permissions['hrm_hiring_process']==1) || (!empty($permissions['hrm_screening_kpq']) && $permissions['hrm_screening_kpq']==1) || (!empty($permissions['hrm_onboarding']) && $permissions['hrm_onboarding']==1) || (!empty($permissions['hrm_training_oje']) && $permissions['hrm_training_oje']==1) || (!empty($permissions['hrm_employee_checklist']) && $permissions['hrm_employee_checklist']==1) || (!empty($permissions['hrm_employee_evaluation']) && $permissions['hrm_employee_evaluation']==1) || (!empty($permissions['hrm_exit_process']) && $permissions['hrm_exit_process']==1) || (!empty($permissions['hrm_exit_initiation']) && $permissions['hrm_exit_initiation']==1) || (!empty($permissions['hrm_exit_interview']) && $permissions['hrm_exit_interview']==1) || (!empty($permissions['hrm_exit_settlement']) && $permissions['hrm_exit_settlement']==1) || (!empty($permissions['hrm_employees']) && $permissions['hrm_employees']==1) || (!empty($permissions['hrm_departments']) && $permissions['hrm_departments']==1) || (!empty($permissions['hrm_attendance']) && $permissions['hrm_attendance']==1) || (!empty($permissions['hrm_leave_requests']) && $permissions['hrm_leave_requests']==1) || (!empty($permissions['hrm_payroll']) && $permissions['hrm_payroll']==1) || (!empty($permissions['hrm_notice_board']) && $permissions['hrm_notice_board']==1) || (!empty($permissions['hrm_kpi']) && $permissions['hrm_kpi']==1) || (!empty($permissions['hrm_kpq']) && $permissions['hrm_kpq']==1) || (!empty($permissions['hrm_kpi_evaluation']) && $permissions['hrm_kpi_evaluation']==1) || (!empty($permissions['hrm_feedback']) && $permissions['hrm_feedback']==1) || (!empty($permissions['erp_users']) && $permissions['erp_users']==1)): ?>
      <li>
        <a><i class="fa fa-users nav-icon"></i> HRM <i class="fa fa-angle-right nav-arrow"></i></a>
        <ul class="sub-menu">
          <?php if ($is_admin || (!empty($permissions['hrm_screening_hub']) && $permissions['hrm_screening_hub']==1)): ?>
          <li><a href="hr-employee-overall-data.php"><i class="fa fa-filter"></i> Screening Hub <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['hrm_career']) && $permissions['hrm_career']==1)): ?><li><a href="hr-career.php" style="font-size:14px !important;"><i class="fa fa-briefcase"></i> Career</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_workforce_journey']) && $permissions['hrm_workforce_journey']==1)): ?><li><a href="hr-employee-overall-data.php" style="font-size:14px !important;"><i class="fa fa-road"></i> Workforce Journey</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_hiring_process']) && $permissions['hrm_hiring_process']==1)): ?><li><a href="/dashboard/hr_screening.php" style="font-size:14px !important;"><i class="fa fa-check-square-o"></i> Screening</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_screening_kpq']) && $permissions['hrm_screening_kpq']==1)): ?><li><a href="hr-managing-rounds-kpq.php" style="font-size:14px !important;"><i class="fa fa-question-circle"></i> Screening KPQ</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_onboarding']) && $permissions['hrm_onboarding']==1)): ?><li><a href="hr-employee-onboarding-pending-list.php" style="font-size:14px !important;"><i class="fa fa-sign-in"></i> Onboarding</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_training_oje']) && $permissions['hrm_training_oje']==1)): ?><li><a href="hr-OJE.php" style="font-size:14px !important;"><i class="fa fa-graduation-cap"></i> Training and OJE</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_employee_checklist']) && $permissions['hrm_employee_checklist']==1)): ?><li><a href="hr-employee-preview-checklist.php" style="font-size:14px !important;"><i class="fa fa-list-alt"></i> Employee Checklist</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_employee_evaluation']) && $permissions['hrm_employee_evaluation']==1)): ?><li><a href="hr-employee-OJE.php" style="font-size:14px !important;"><i class="fa fa-star"></i> Employee Evaluation</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_exit_process']) && $permissions['hrm_exit_process']==1)): ?>
              <li>
                <a style="font-size:14px !important;"><i class="fa fa-sign-out"></i> Exit Process <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
                <ul class="sub-menu">
                  <?php if ($is_admin || (!empty($permissions['hrm_exit_initiation']) && $permissions['hrm_exit_initiation']==1)): ?><li><a href="hr-exit-initiation.php" style="font-size:13px !important;"><i class="fa fa-paper-plane"></i> Exit Initiation</a></li><?php endif; ?>
                  <?php if ($is_admin || (!empty($permissions['hrm_exit_handover']) && $permissions['hrm_exit_handover']==1)): ?><li><a href="hr-exit-handover.php" style="font-size:13px !important;"><i class="fa fa-exchange"></i> Exit Handover</a></li><?php endif; ?>
                  <?php if ($is_admin || (!empty($permissions['hrm_exit_interview']) && $permissions['hrm_exit_interview']==1)): ?><li><a href="hr-exit-employee-interview.php" style="font-size:13px !important;"><i class="fa fa-comments"></i> Exit Interview</a></li><?php endif; ?>
                  <?php if ($is_admin || (!empty($permissions['hrm_exit_settlement']) && $permissions['hrm_exit_settlement']==1)): ?><li><a href="hr-exit-settlement.php" style="font-size:13px !important;"><i class="fa fa-file-text"></i> Settlement &amp; Clearance</a></li><?php endif; ?>
                </ul>
              </li>
              <?php endif; ?>
              
            </ul>
          </li>
          <?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_employees'])      && $permissions['hrm_employees']      ==1)): ?><li><a href="hr-employees-list.php"><i class="fa fa-user"></i> Employees</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['erp_users']) && $permissions['erp_users']==1)): ?><li><a href="add-new-users.php"><i class="fa fa-user"></i> ERP Users</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_departments'])    && $permissions['hrm_departments']    ==1)): ?><li><a href="hr-departments-list.php"><i class="fa fa-sitemap"></i> Departments</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_attendance'])     && $permissions['hrm_attendance']     ==1)): ?><li><a href="hr-attendance-list.php"><i class="fa fa-clock-o"></i> Attendance</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_leave_requests']) && $permissions['hrm_leave_requests'] ==1)): ?><li><a href="hr-leave-requests.php"><i class="fa fa-calendar"></i> Leave Requests</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_payroll'])        && $permissions['hrm_payroll']        ==1)): ?><li><a href="hr-payroll.php"><i class="fa fa-money"></i> Payroll</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_notice_board'])   && $permissions['hrm_notice_board']   ==1)): ?><li><a href="hr-notices.php"><i class="fa fa-bullhorn"></i> Notice Board</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_kpi']) && $permissions['hrm_kpi']==1)): ?>
          <li><a><i class="fa fa-bar-chart"></i> KPI <i class="fa fa-angle-right nav-arrow" style="margin-left:auto"></i></a>
            <ul class="sub-menu">
              <?php if ($is_admin || (!empty($permissions['hrm_kpq'])            && $permissions['hrm_kpq']           ==1)): ?><li><a href="hr-kpq.php"><i class="fa fa-question-circle"></i> KPQ</a></li><?php endif; ?>
              <?php if ($is_admin || (!empty($permissions['hrm_kpi_evaluation']) && $permissions['hrm_kpi_evaluation']==1)): ?><li><a href="hr-kpi-evaluation.php"><i class="fa fa-star"></i> KPI Evaluation</a></li><?php endif; ?>
            </ul>
          </li>
          <?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['hrm_feedback']) && $permissions['hrm_feedback']==1)): ?><li><a href="hr-feedback.php"><i class="fa fa-comments"></i> Feedback</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['expense_tracker']) && $permissions['expense_tracker']==1)): ?><li><a href="digital-expenses-finance-suite.php"><i class="fa fa-money"></i> Expense Tracker</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['essential_purchases']) && $permissions['essential_purchases']==1)): ?><li><a href="hr-pantry.php"><i class="fa fa-shopping-cart"></i> Essential Purchases</a></li><?php endif; ?>
        </ul>
      </li>
      <?php endif; ?>





      <!-- ── TMS ── -->
      <?php if ($is_admin || (!empty($permissions['tickets']) && $permissions['tickets']==1)): ?>
      <li>
        <a><i class="fa fa-ticket nav-icon"></i> TMS <i class="fa fa-angle-right nav-arrow"></i></a>
        <ul class="sub-menu">
          <?php if ($is_admin || (!empty($permissions['raise_a_ticket']) && $permissions['raise_a_ticket']==1)): ?><li><a href="raise-a-ticket.php"><i class="fa fa-plus-circle"></i> Raise a Ticket</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['my_tickets'])     && $permissions['my_tickets']    ==1)): ?><li><a href="my-tickets.php"><i class="fa fa-user"></i> My Tickets</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['all_tickets'])    && $permissions['all_tickets']   ==1)): ?><li><a href="reports.php"><i class="fa fa-list"></i> All Tickets</a></li><?php endif; ?>
          <?php if ($is_admin || (!empty($permissions['closed_tickets']) && $permissions['closed_tickets']==1)): ?><li><a href="closed-tickets.php"><i class="fa fa-check-square"></i> Closed Tickets</a></li><?php endif; ?>
        </ul>
      </li>
      <?php endif; ?>

    </ul>
  </nav>

  <!-- Logout -->
  <div class="sidebar-logout">
    <a href="library.php?action=logOut"><i class="fa fa-sign-out"></i> Logout</a>
  </div>
</aside>

<!-- ══════════════════════════════════════════
     TOP BAR
══════════════════════════════════════════ -->
<header id="main-topbar">

  <!-- Left: mobile menu + carousel -->
  <div style="display:flex;align-items:center;flex:1;min-width:0;">
    <div class="mob-menu-btn" id="mobMenuBtn" onclick="toggleMobileMenu()">
      <i class="fa fa-bars"></i>
    </div>
    <div class="topbar-title-wrap"></div>
  </div>

  <!-- Right: clock + bell + user -->
  <div class="topbar-right">

    <!-- Switch Entity -->
    <?php if ($active_entity_info): ?>
    <a href="entity-select.php?switch=1" class="topbar-entity-btn" title="Switch Entity">
      <?php if ($_SESSION['active_entity'] === 'design'): ?>
        <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" style="width:15px;height:15px;flex-shrink:0;">
          <rect x="3.5" y="4" width="9.5" height="17" rx="0.6" fill="#fff"/>
          <rect x="13.5" y="8.5" width="7" height="12.5" rx="0.6" fill="#fff" opacity="0.55"/>
          <rect x="5.5" y="6.8" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="9" y="6.8" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="5.5" y="10.5" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="9" y="10.5" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="5.5" y="14.2" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="9" y="14.2" width="1.9" height="1.9" rx="0.3" fill="var(--navy-500)"/>
          <rect x="15.7" y="11.2" width="1.6" height="1.6" rx="0.3" fill="var(--navy-500)"/>
          <rect x="15.7" y="14.7" width="1.6" height="1.6" rx="0.3" fill="var(--navy-500)"/>
        </svg>
      <?php else: ?>
        <i class="fa <?php echo $active_entity_info['icon']; ?>" style="color:#fff;font-size:14px;"></i>
      <?php endif; ?>
      <span class="te-label">
        <span class="te-name">Switch Entity</span>
        <span class="te-cur"><?php echo htmlspecialchars($active_entity_info['name']); ?></span>
      </span>
      <i class="fa fa-exchange"></i>
    </a>
    <?php endif; ?>

    <!-- Clock -->
    <div class="topbar-clock"><span id="tick2"></span></div>

    <!-- Notification Bell -->
    <div style="position:relative;">
      <div class="notif-bell-wrap <?php echo $total_notification_count > 0 ? 'has-notif' : ''; ?>" id="notifBellBtn">
        <i class="fa fa-bell"></i>
        <span class="notif-badge" id="notifBadge"
              style="<?php echo $total_notification_count > 0 ? 'display:inline-block;' : ''; ?>">
          <?php echo $total_notification_count > 99 ? '99+' : $total_notification_count; ?>
        </span>
      </div>

      <div class="notif-drop" id="notifDrop">
        <div class="notif-drop-head">
          <span class="nd-title"><i class="fa fa-bell" style="margin-right:6px;"></i>Notifications</span>
          <span class="nd-pill" id="notifPill" style="<?php echo $total_notification_count > 0 ? '' : 'display:none;'; ?>">
            <?php echo $total_notification_count; ?> pending
          </span>
        </div>
        <div id="notifContent">
          <?php if ($total_notification_count > 0 || !empty($kpi_items) || !empty($schedule_items)): ?>
            <?php foreach ($ticket_items as $t):
              $p  = strtolower($t['priority'] ?? 'low');
              $pc = in_array($p, ['high','urgent','critical']) ? 'np-h' : (in_array($p, ['medium','normal']) ? 'np-m' : 'np-l');
              $diff = time() - strtotime($t['created_at']);
              $ago  = $diff < 3600 ? floor($diff/60).'m ago' : ($diff < 86400 ? floor($diff/3600).'h ago' : floor($diff/86400).'d ago');
            ?>
            <a href="my-tickets.php" class="notif-row">
              <div class="notif-dot"></div>
              <div class="notif-info">
                <div class="notif-meta">
                  <span class="notif-num"><?php echo htmlspecialchars($t['ticket_number'] ?? 'TKT-'.$t['id']); ?></span>
                  <span class="notif-age"><?php echo $ago; ?></span>
                </div>
                <span class="notif-subj"><?php echo htmlspecialchars($t['subject'] ?? 'No Subject'); ?></span>
                <span class="notif-prio <?php echo $pc; ?>"><?php echo ucfirst($p); ?></span>
              </div>
            </a>
            <?php endforeach; ?>
            <?php if ($ticket_count > 5): ?>
            <div style="padding:6px;text-align:center;background:#f8fafc;">
              <span style="color:#2563c4;font-size:11px;">+<?php echo $ticket_count - 5; ?> more</span>
            </div>
            <?php endif; ?>
            <?php foreach ($kyc_items as $k):
              $k_latest = $k['records'][0]['item_date'] ?? null;
              if ($k_latest) {
                  $k_diff = time() - strtotime($k_latest);
                  $k_ago  = $k_diff < 3600 ? floor($k_diff/60).'m ago' : ($k_diff < 86400 ? floor($k_diff/3600).'h ago' : floor($k_diff/86400).'d ago');
              } else { $k_ago = ''; }
            ?>
            <a href="notifications.php" class="notif-row">
              <div class="notif-dot"></div>
              <div class="notif-info">
                <div class="notif-meta">
                  <span class="notif-num"><i class="fa fa-id-card" style="margin-right:4px;"></i><?php echo htmlspecialchars($k['label']); ?></span>
                  <?php if ($k_ago): ?><span class="notif-age">latest <?php echo $k_ago; ?></span><?php endif; ?>
                </div>
                <span class="notif-subj"><?php echo $k['count']; ?> pending review</span>
              </div>
            </a>
            <?php endforeach; ?>
            <?php foreach ($kpi_items as $ki): ?>
            <a href="<?php echo $ki['link']; ?>" class="notif-row"
               style="<?php echo $ki['read'] ? 'opacity:.5;' : ''; ?>"
               onclick="fetch('get_notification_count.php',{method:'POST',credentials:'same-origin',
                 headers:{'Content-Type':'application/x-www-form-urlencoded'},
                 body:'action=mark_kpi_read&review_type=<?php echo $ki['type']; ?>&period=<?php echo $ki['period']; ?>'});">
              <div class="notif-dot" style="<?php echo $ki['read'] ? 'background:#cbd5e1;' : 'background:#dc2626;'; ?>"></div>
              <div class="notif-info">
                <div class="notif-meta">
                  <span class="notif-num"><i class="fa <?php echo $ki['icon']; ?>" style="margin-right:4px;"></i><?php echo $ki['type'] === 'weekly' ? 'Weekly Self-Review' : 'Monthly Self-Review'; ?></span>
                  <?php if ($ki['read']): ?><span class="notif-age">seen</span><?php endif; ?>
                </div>
                <span class="notif-subj" style="white-space:normal;font-weight:700;color:#b91c1c;"><?php echo htmlspecialchars($ki['line1']); ?></span>
                <span class="notif-subj" style="white-space:normal;font-weight:500;color:#475569;"><?php echo htmlspecialchars($ki['line2']); ?></span>
              </div>
            </a>
            <?php endforeach; ?>
            <?php foreach ($schedule_items as $si): ?>
            <a href="my-tickets.php" class="notif-row"
               style="<?php echo $si['read'] ? 'opacity:.5;' : ''; ?>"
               onclick="fetch('get_notification_count.php',{method:'POST',credentials:'same-origin',
                 headers:{'Content-Type':'application/x-www-form-urlencoded'},
                 body:'action=mark_schedule_read&source_id=<?php echo (int)$si['id']; ?>'});">
              <div class="notif-dot" style="<?php echo $si['read'] ? 'background:#cbd5e1;' : 'background:#0ea5e9;'; ?>"></div>
              <div class="notif-info">
                <div class="notif-meta">
                  <span class="notif-num"><i class="fa fa-clock-o" style="margin-right:4px;"></i><?php echo htmlspecialchars($si['name']); ?></span>
                  <?php if ($si['read']): ?><span class="notif-age">seen</span><?php endif; ?>
                </div>
                <span class="notif-subj" style="white-space:normal;font-weight:600;color:#0c4a6e;">For: <?php echo htmlspecialchars($si['employee']); ?> &middot; <?php echo htmlspecialchars($si['when']); ?></span>
                <span class="notif-subj" style="white-space:normal;font-weight:500;color:#475569;">Ticket raised for this reminder.</span>
              </div>
            </a>
            <?php endforeach; ?>
            <a href="notifications.php" class="notif-footer"><i class="fa fa-arrow-right"></i> View All Notifications</a>
          <?php else: ?>
            <div class="notif-empty">
              <i class="fa fa-bell-slash"></i>
              <h6>No Notifications</h6>
              <p>You're all caught up!</p>
            </div>
          <?php endif; ?>
        </div>
      </div>
    </div>

    <!-- User Menu -->
    <div style="position:relative;">
      <?php
      if ($is_admin) {
        $r3 = mysqli_query($dbConn, "SELECT * FROM manager_admin WHERE name='".$_SESSION["user_name"]."' LIMIT 1");
        $pu = mysqli_fetch_array($r3);
        $profile_link = "edit-profile.php?cid=" . codificar($pu['cid'] ?? '');
      } else {
        $r3 = mysqli_query($dbConn, "SELECT * FROM manager_user WHERE name='".$_SESSION["user_name"]."' LIMIT 1");
        $pu = mysqli_fetch_array($r3);
        $profile_link = "edit-profile-user.php?cid=" . codificar($pu['cid'] ?? '');
      }
      ?>
      <div class="topbar-user-btn" id="userMenuBtn">
        <img src="logo-image/user.png" class="topbar-user-avatar" alt="User">
        <div class="topbar-user-info">
          <span class="topbar-user-greet"><?php echo $mensaje; ?></span>
          <span class="topbar-user-name"><?php echo htmlspecialchars($_SESSION['user_name']); ?></span>
        </div>
        <i class="fa fa-angle-down topbar-user-caret"></i>
      </div>

      <div class="topbar-user-drop" id="userMenuDrop">
        <div class="topbar-user-drop-head">
          <span><?php echo htmlspecialchars($_SESSION['user_name']); ?></span>
          <small><?php echo $is_admin ? 'Administrator' : 'Employee'; ?></small>
        </div>
        <a href="<?php echo $profile_link; ?>"><i class="fa fa-user"></i> My Profile</a>
        <a href="library.php?action=logOut" class="logout"><i class="fa fa-sign-out"></i> Logout</a>
      </div>
    </div>

  </div>
</header>

<!-- Scripts -->
<script src="../bower_components/jquery/dist/jquery.min.js"></script>
<script src="../bower_components/bootstrap/dist/js/bootstrap.js"></script>

<script>
// ── Clock ────────────────────────────────────────────────────
function show2(){
  var el = document.getElementById("tick2"); if(!el) return;
  var d=new Date(), h=d.getHours(), m=d.getMinutes(), s=d.getSeconds(), dn=h>=12?"PM":"AM";
  if(h>12)h-=12; if(h===0)h=12;
  if(m<=9)m="0"+m; if(s<=9)s="0"+s;
  el.innerHTML = h+":"+m+":"+s+" "+dn;
  setTimeout(show2, 1000);
}
show2();

// ── Sidebar accordion — event delegation (works at ALL nesting levels) ──
document.getElementById('main-sidebar').addEventListener('click', function(e) {
  // Walk up from the clicked element to find the nearest <a>
  var link = e.target.closest('a');
  if (!link) return;

  // Only handle links that have a sibling sub-menu
  var li  = link.parentElement;
  if (!li) return;
  var sub = link.nextElementSibling;

  // If this link has NO sub-menu child, it's a real page link — let it navigate
  if (!sub || !sub.classList.contains('sub-menu')) return;

  // Has sub-menu — toggle open/close
  if (!link.getAttribute('href') || link.getAttribute('href') === '#' || link.getAttribute('href') === '') {
      e.preventDefault();
  }
  e.stopPropagation();

  var isOpen = li.classList.contains('open');

  // Close all sibling <li>s at this same level
  var siblings = li.parentElement ? li.parentElement.children : [];
  for (var i = 0; i < siblings.length; i++) {
    if (siblings[i] !== li) {
      siblings[i].classList.remove('open');
    }
  }

  // Toggle this one
  if (isOpen) {
    li.classList.remove('open');
  } else {
    li.classList.add('open');
  }
});

// Highlight active page
(function(){
  var path = window.location.pathname.split('/').pop();
  document.querySelectorAll('#main-sidebar a[href]').forEach(function(a){
    if (a.getAttribute('href') === path || a.href === window.location.href) {
      a.parentElement.classList.add('active');
      
      // If the link itself has a sub-menu child, open it (for parent links like db-dashboard.php)
      if (a.nextElementSibling && a.nextElementSibling.classList.contains('sub-menu')) {
        a.parentElement.classList.add('open');
      }

      // Open parent sub-menus (if this is a child link)
      var parent = a.closest('.sub-menu');
      while (parent) {
        var parentLi = parent.parentElement;
        if (parentLi) parentLi.classList.add('open');
        parent = parentLi ? parentLi.closest('.sub-menu') : null;
      }
    }
  });
})();

// ── Mobile Sidebar Toggle ─────────────────────────────────
function toggleMobileMenu(){
  var sb = document.getElementById('main-sidebar');
  var bd = document.getElementById('sidebar-backdrop');
  sb.classList.toggle('mobile-open');
  if(sb.classList.contains('mobile-open')){
    if(!bd){ bd=document.createElement('div'); bd.id='sidebar-backdrop'; document.body.appendChild(bd); }
    bd.style.display='block';
    bd.onclick=function(){ sb.classList.remove('mobile-open'); bd.style.display='none'; };
  } else {
    if(bd) bd.style.display='none';
  }
}

// ── Notification Bell ────────────────────────────────────────
(function(){
  var btn       = document.getElementById('notifBellBtn');
  var drop      = document.getElementById('notifDrop');
  var badge     = document.getElementById('notifBadge');
  var pill      = document.getElementById('notifPill');
  var toast     = document.getElementById('notifToast');
  var toastText = document.getElementById('notifToastText');
  var lastCount = <?php echo (int)$total_notification_count; ?>;

  function beepFallback(){
    // Plays a short beep with the Web Audio API -- no sound file needed,
    // so this works even before tms.wav is uploaded, or if the browser
    // blocks/errors on the <audio> element for any reason.
    try {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      var ctx = new Ctx();
      var osc = ctx.createOscillator();
      var gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0.001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.3, ctx.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start(); osc.stop(ctx.currentTime + 0.5);
    } catch(e){}
  }
  function playSound(){
    try {
      var a = document.getElementById('hdrSound');
      if (!a){ a=document.createElement('audio'); a.id='hdrSound'; a.src='tms.wav'; a.preload='auto'; document.body.appendChild(a); }
      a.currentTime=0; a.volume=1;
      var p = a.play();
      if (p && typeof p.catch === 'function') p.catch(function(){ beepFallback(); });
    } catch(e){ beepFallback(); }
  }
  function requestDesktopPermission(){
    if ('Notification' in window && Notification.permission === 'default') { Notification.requestPermission(); }
  }
  function showDesktopNotification(n, diff){
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    try {
      var body = diff===1 ? '1 new notification' : diff+' new notifications';
      var dn = new Notification('Abra E-Logistics', { body: body, icon: 'favicon.ico', tag: 'abra-notif' });
      dn.onclick = function(){ window.focus(); this.close(); };
    } catch(e){}
  }
  function updateBadge(n){
    if(n>0){ badge.textContent=n>99?'99+':n; badge.style.display='inline-block'; pill.textContent=n+' pending'; pill.style.display='inline-block'; btn.classList.add('has-notif'); }
    else  { badge.style.display='none'; pill.style.display='none'; btn.classList.remove('has-notif'); }
  }
  function showToast(n, diff){
    toastText.textContent = diff===1 ? '1 new notification!' : diff+' new notifications!';
    toast.style.display='block';
    clearTimeout(toast._t);
    toast._t = setTimeout(function(){ toast.style.display='none'; }, 4000);
  }
  function poll(){
    fetch('get_notification_count.php',{credentials:'same-origin'})
      .then(function(r){return r.json();})
      .then(function(d){
        var n=parseInt(d.count)||0;
        if(n>lastCount){ playSound(); showToast(n,n-lastCount); showDesktopNotification(n,n-lastCount); }

        if(n!==lastCount){ updateBadge(n); lastCount=n; }
      }).catch(function(){});
  }
  setInterval(poll, 10000);
  window.refreshNotificationCount = poll;

  btn.addEventListener('click',function(e){ e.stopPropagation(); drop.classList.toggle('open'); requestDesktopPermission(); });
  document.addEventListener('click', requestDesktopPermission, { once: true });
  document.addEventListener('click',function(e){
    if(!btn.contains(e.target)&&!drop.contains(e.target)) drop.classList.remove('open');
  });
})();

// ── User Menu ────────────────────────────────────────────────
(function(){
  var btn  = document.getElementById('userMenuBtn');
  var drop = document.getElementById('userMenuDrop');
  btn.addEventListener('click',function(e){ e.stopPropagation(); drop.classList.toggle('open'); });
  document.addEventListener('click',function(e){
    if(!btn.contains(e.target)&&!drop.contains(e.target)) drop.classList.remove('open');
  });
})();

// ── LOGOUT OVERLAY ───────────────────────────────────────────
(function(){
  var logoutUrl = 'library.php?action=logOut';

  /* Intercept ALL logout links */
  document.querySelectorAll('a[href*="action=logOut"]').forEach(function(a){
    a.addEventListener('click', function(e){
      e.preventDefault();
      showLogoutOverlay(logoutUrl);
    });
  });

  function showLogoutOverlay(url){
    var overlay = document.getElementById('logout-overlay');
    if(!overlay) return;
    overlay.classList.add('lo-show');

    var s0 = document.getElementById('lo-bye');
    var s1 = document.getElementById('lo-soon');
    var s2 = document.getElementById('lo-going');

    /* Stage 0 — Goodbye wave, fades in immediately */
    setTimeout(function(){ s0.classList.add('lo-in'); }, 60);

    /* Stage 0 → 1 at 1300ms (no blank gap — s1 fades in as s0 fades out) */
    setTimeout(function(){
      s0.classList.remove('lo-in'); s0.classList.add('lo-out');
      setTimeout(function(){
        s0.classList.remove('lo-out');
        s1.classList.add('lo-in');
      }, 320);
    }, 1300);

    /* Stage 1 → 2 at 2700ms */
    setTimeout(function(){
      s1.classList.remove('lo-in'); s1.classList.add('lo-out');
      setTimeout(function(){
        s1.classList.remove('lo-out');
        s2.classList.add('lo-in');
        /* Fill progress bar */
        setTimeout(function(){
          var fill = document.getElementById('lo-fill');
          fill.style.transition = 'width 1.1s linear';
          fill.style.width = '100%';
        }, 80);
      }, 320);
    }, 2700);

    /* Redirect at 4000ms */
    setTimeout(function(){ window.location.href = url; }, 4000);
  }
})();
</script>

<!-- ══ LOGOUT OVERLAY ══ -->
<style>
@import url('https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&display=swap');

#logout-overlay{
  display:none;position:fixed;inset:0;z-index:99999;
  background:linear-gradient(135deg,#040d1a 0%,#071428 45%,#0a1e3d 100%);
  overflow:hidden;font-family:'Outfit',sans-serif;
}
#logout-overlay.lo-show{display:block}
#logout-overlay::before{
  content:'';position:absolute;inset:0;
  background-image:radial-gradient(circle,rgba(6,182,212,0.07) 1px,transparent 1px);
  background-size:38px 38px;pointer-events:none;z-index:0;
}
.lo-orb{position:absolute;border-radius:50%;filter:blur(100px);pointer-events:none}
.lo-orb1{width:500px;height:500px;background:rgba(26,68,145,0.3);top:-160px;left:-160px}
.lo-orb2{width:400px;height:400px;background:rgba(6,182,212,0.1);bottom:-100px;right:-100px}
.lo-orb3{width:220px;height:220px;background:rgba(245,158,11,0.07);top:35%;left:38%}

/* All panels stacked in same spot — no display:none, use opacity+pointer-events */
.lo-panel{
  position:absolute;top:0;left:0;right:0;bottom:0;
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  padding:24px 28px;
  opacity:0;pointer-events:none;
  transform:translateY(26px);
  transition:opacity 0.5s ease,transform 0.5s ease;
  z-index:2;text-align:center;
}
.lo-panel.lo-in{opacity:1;pointer-events:auto;transform:translateY(0)}
.lo-panel.lo-out{opacity:0;pointer-events:none;transform:translateY(-20px);transition:opacity 0.3s ease,transform 0.3s ease}

/* ── Stage 0: Goodbye wave ── */
.lo-wave{font-size:60px;line-height:1;margin-bottom:16px;display:inline-block;animation:lowave 1.4s ease-in-out infinite}
@keyframes lowave{0%,100%{transform:rotate(0deg)}20%{transform:rotate(-18deg)}40%{transform:rotate(14deg)}60%{transform:rotate(-10deg)}80%{transform:rotate(8deg)}}
.lo-bye-title{font-size:36px;font-weight:900;color:#fff;letter-spacing:-0.8px;margin-bottom:8px;line-height:1.1}
@media(max-width:480px){.lo-bye-title{font-size:26px}}
.lo-bye-title span{background:linear-gradient(90deg,#06b6d4,#90b8f0);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.lo-bye-sub{font-size:14px;font-weight:500;color:rgba(255,255,255,0.35);letter-spacing:0.2px}

/* ── Stage 1: Quote ── */
.lo-quote-card{
  background:rgba(255,255,255,0.035);
  border:1px solid rgba(255,255,255,0.08);
  border-radius:20px;
  padding:28px 32px;
  max-width:520px;width:100%;
  position:relative;
}
@media(max-width:480px){.lo-quote-card{padding:20px 18px;border-radius:14px}}
.lo-quote-open{
  position:absolute;top:-18px;left:24px;
  font-size:52px;line-height:1;font-family:Georgia,serif;
  color:var(--accent2,#06b6d4);opacity:0.55;
}
.lo-quote-text{
  font-size:17px;font-weight:600;color:rgba(255,255,255,0.88);
  font-style:italic;line-height:1.65;margin-bottom:16px;margin-top:8px;
}
@media(max-width:480px){.lo-quote-text{font-size:14px}}
.lo-quote-divider{width:40px;height:2px;background:linear-gradient(90deg,transparent,#06b6d4,transparent);margin:0 auto 10px}
.lo-quote-author{font-size:11px;font-weight:700;color:#06b6d4;letter-spacing:2px;text-transform:uppercase}

/* ── Stage 2: Come back soon ── */
.lo-door-icon{font-size:52px;margin-bottom:14px;display:inline-block;animation:lodoor 1.5s ease-in-out infinite}
@keyframes lodoor{0%,100%{transform:scale(1)}50%{transform:scale(1.08)}}
.lo-going-title{font-size:28px;font-weight:900;color:#fff;margin-bottom:6px;letter-spacing:-0.5px}
@media(max-width:480px){.lo-going-title{font-size:22px}}
.lo-going-sub{font-size:13px;font-weight:500;color:rgba(255,255,255,0.3);margin-bottom:28px}
.lo-progress{width:min(260px,80vw);height:4px;background:rgba(255,255,255,0.08);border-radius:99px;overflow:hidden;margin:0 auto 10px}
#lo-fill{height:100%;width:0%;background:linear-gradient(90deg,#1a4491,#06b6d4);border-radius:99px}
.lo-progress-text{font-size:11px;color:rgba(255,255,255,0.2);letter-spacing:0.5px}
</style>

<div id="logout-overlay">
  <div class="lo-orb lo-orb1"></div>
  <div class="lo-orb lo-orb2"></div>
  <div class="lo-orb lo-orb3"></div>

  <!-- Stage 0: Goodbye wave -->
  <div class="lo-panel" id="lo-bye">
    <div class="lo-wave">👋</div>
    <div class="lo-bye-title">Goodbye, <span><?php echo htmlspecialchars($_SESSION['user_name'] ?? 'Friend'); ?></span>!</div>
    <div class="lo-bye-sub">You've been signed out of Abra FlowX.AI</div>
  </div>

  <!-- Stage 1: Clean single quote -->
  <div class="lo-panel" id="lo-soon">
    <div class="lo-quote-card">
      <span class="lo-quote-open">"</span>
      <div class="lo-quote-text">
        Success is not final, rest is not permanent —<br>what matters is the courage to come back tomorrow.
      </div>
      <div class="lo-quote-divider"></div>
      <div class="lo-quote-author">— Abra FlowX.AI</div>
    </div>
  </div>

  <!-- Stage 2: Come back soon -->
  <div class="lo-panel" id="lo-going">
    <div class="lo-door-icon">🚪</div>
    <div class="lo-going-title">See you soon!</div>
    <div class="lo-going-sub">Your workspace will be ready when you return</div>
    <div class="lo-progress"><div id="lo-fill"></div></div>
    <div class="lo-progress-text">Signing out securely...</div>
  </div>

</div>