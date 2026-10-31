<?php
ob_start();
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE (Flutter WebView Auth)
// =========================================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$session_name = trim($_SESSION['user_name'] ?? '');
$emp_data = null;
$db_link = isset($dbConn) ? $dbConn : (isset($con) ? $con : null);

if ($db_link && !empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($db_link, $currentUserEmail);
    $eq = mysqli_query($db_link, "
        SELECT id, employee_id, name, department, position 
        FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
        $_SESSION['user_name'] = $emp_data['name'];
        $_SESSION['user_id'] = $emp_data['id'];
        $session_name = $emp_data['name'];
    }
}

if (!$emp_data && $session_name && $db_link) {
    $safe_name = mysqli_real_escape_string($db_link, $session_name);
    $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name = '$safe_name' AND status = 'Active' LIMIT 1");
    if (!$eq || mysqli_num_rows($eq) == 0) {
        $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name LIKE '$safe_name%' AND status = 'Active' LIMIT 1");
    }
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
    }
}

if (!$emp_data) {
    die("
        <div style='font-family:sans-serif; max-width:600px; margin:60px auto; padding:30px; 
                    border:2px solid #ef4444; border-radius:12px; background:#fef2f2; color:#b91c1c;'>
            <h2 style='margin-top:0;'>&#10060; Authentication Failed</h2>
            <p>Could not identify your employee record.</p>
        </div>
    ");
}

$url_email = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';
// =========================================================================


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

// Ensure the rejection log table exists (in case this page loads before hr_screening.php ever ran)
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_rejection_log (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) DEFAULT NULL,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    company_id int(11) DEFAULT NULL,
    round_number int(11) DEFAULT 0,
    round_name varchar(255) DEFAULT 'Overall',
    round_type varchar(30) DEFAULT 'overall',
    reason text NOT NULL,
    rejected_by varchar(255) DEFAULT NULL,
    kept_in_database tinyint(1) DEFAULT 1,
    resume_filename varchar(500) DEFAULT NULL,
    resume_path varchar(500) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// ---- AJAX: DELETE A REJECTION LOG ENTRY (cleanup only — does not touch hr_screenings) ----
if (isset($_POST['ajax_delete_rejection_log'])) {
    header('Content-Type: application/json');
    $lid = intval($_POST['log_id'] ?? 0);
    mysqli_query($dbConn, "DELETE FROM hr_rejection_log WHERE id=$lid");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: GET EVALUATION HISTORY ONLY (for candidates whose hr_screenings row was deleted) ----
if (isset($_GET['ajax_get_eval_history'])) {
    header('Content-Type: application/json');
    $sid = intval($_GET['screening_id'] ?? 0);
    if ($sid <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid candidate reference.']); exit; }

    $rows = [];
    $q = mysqli_query($dbConn, "SELECT round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, status, hr_notes, rejection_reason, created_at FROM hr_screening_evaluations WHERE screening_id=$sid ORDER BY round_number ASC");
    while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;

    if (empty($rows)) {
        echo json_encode(['success'=>false, 'message'=>'No evaluation history found for this candidate.']);
        exit;
    }
    echo json_encode(['success'=>true, 'rounds'=>$rows]);
    exit;
}

// ---- FILTERS ----
$f_dept      = $_GET['department'] ?? '';
$f_round     = $_GET['round_type'] ?? '';
$f_from      = $_GET['date_from'] ?? '';
$f_to        = $_GET['date_to'] ?? '';
$f_search    = $_GET['search'] ?? '';

$where = "WHERE 1=1";
if ($f_dept !== '')   $where .= " AND rl.department = '" . mysqli_real_escape_string($dbConn, $f_dept) . "'";
if ($f_round !== '')  $where .= " AND rl.round_type = '" . mysqli_real_escape_string($dbConn, $f_round) . "'";
if ($f_from !== '')   $where .= " AND DATE(rl.created_at) >= '" . mysqli_real_escape_string($dbConn, $f_from) . "'";
if ($f_to !== '')     $where .= " AND DATE(rl.created_at) <= '" . mysqli_real_escape_string($dbConn, $f_to) . "'";
if ($f_search !== '') $where .= " AND rl.candidate_name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%'";

$rows_res = mysqli_query($dbConn, "SELECT rl.*, hs.id AS still_exists,
    (SELECT COUNT(*) FROM hr_screening_evaluations ev WHERE ev.screening_id = rl.screening_id) AS eval_count
    FROM hr_rejection_log rl
    LEFT JOIN hr_screenings hs ON rl.screening_id = hs.id
    $where
    ORDER BY rl.created_at DESC");

// ---- STATS ----
$stats = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT
    COUNT(*) as total,
    SUM(CASE WHEN round_type='interview' THEN 1 ELSE 0 END) as interview_ct,
    SUM(CASE WHEN round_type='assignment' THEN 1 ELSE 0 END) as assignment_ct,
    SUM(CASE WHEN round_type='work_sample' THEN 1 ELSE 0 END) as worksample_ct,
    SUM(CASE WHEN round_type='overall' THEN 1 ELSE 0 END) as overall_ct,
    SUM(CASE WHEN kept_in_database=1 THEN 1 ELSE 0 END) as kept_ct,
    SUM(CASE WHEN kept_in_database=0 THEN 1 ELSE 0 END) as removed_ct
    FROM hr_rejection_log"));

$depts = [];
$dq = mysqli_query($dbConn, "SELECT name FROM hr_departments ORDER BY name ASC");
while ($r = mysqli_fetch_assoc($dq)) $depts[] = $r['name'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Rejected Candidates | CRM</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#1e293b;--blue:#334155;--accent:#d97706;--danger:#ef4444;--success:#10b981;--warn:#f59e0b;--bg:#f0f4f9;--card:#fff;--border:#e4e9f2;--muted:#64748b;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;color:#0f172a;}
.hdr{background:linear-gradient(135deg,#1e293b,#334155);padding:20px 28px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;box-shadow:0 4px 20px rgba(30,41,59,.25);}
.hdr h1{color:#fff;font-size:1.45rem;font-weight:800;margin:0;}
.hdr .sub{color:rgba(255,255,255,.75);font-size:12px;margin-top:3px;}
.btn-h{padding:9px 18px;border-radius:9px;font-weight:700;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:6px;font-size:13px;transition:.2s;text-decoration:none;color:#fff;}
.btn-navy{background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);}
.btn-success{background:linear-gradient(135deg,#10b981,#059669);}
.btn-h:hover{transform:translateY(-1px);box-shadow:0 5px 15px rgba(0,0,0,.15);color:#fff;text-decoration:none;}
.wrap{max-width:1500px;margin:0 auto;padding:24px 20px;}
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px;margin-bottom:22px;}
.stat-box{background:var(--card);border-radius:13px;padding:16px;border:1px solid var(--border);display:flex;align-items:center;gap:12px;box-shadow:0 2px 8px rgba(0,0,0,.04);}
.stat-ico{width:42px;height:42px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:16px;flex-shrink:0;}
.stat-val{font-size:22px;font-weight:800;line-height:1;}
.stat-lbl{font-size:10px;font-weight:700;color:var(--muted);text-transform:uppercase;margin-top:3px;}
.card-panel{background:var(--card);border-radius:15px;border:1px solid var(--border);box-shadow:0 2px 10px rgba(0,0,0,.05);overflow:hidden;}
.card-head{padding:18px 22px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;background:linear-gradient(135deg,#f8fafc,#eef2f7);}
.card-head h5{font-weight:800;color:var(--navy);margin:0;}
.fc{box-sizing:border-box;border:2px solid var(--border);border-radius:9px;padding:9px 12px;font-size:13px;font-family:inherit;font-weight:600;width:100%;transition:.2s;background:#fff;color:#0f172a;}
.fc:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(217,119,6,.08);}
.filter-row{display:flex;gap:9px;flex-wrap:wrap;align-items:center;}
.tbl-wrap{overflow-x:auto;}
table.rtbl{width:100%;border-collapse:collapse;}
table.rtbl thead th{background:linear-gradient(135deg,#1e293b,#334155);color:#fff;font-weight:800;padding:12px 15px;font-size:11px;text-transform:uppercase;white-space:nowrap;border:none;}
table.rtbl tbody td{padding:13px 15px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:600;vertical-align:middle;}
table.rtbl tbody tr:hover{background:#f8fafc;}
.badge-r{padding:4px 11px;border-radius:20px;font-weight:800;font-size:11px;text-transform:uppercase;white-space:nowrap;}
.b-interview{background:#dbeafe;color:#1e40af;}
.b-assignment{background:#ede9fe;color:#5b21b6;}
.b-work_sample{background:#fce7f3;color:#9d174d;}
.b-overall{background:#fef3c7;color:#92400e;}
.b-kept{background:#dcfce7;color:#065f46;}
.b-removed{background:#f1f5f9;color:#475569;}
.b-src-tracking{background:#ede9fe;color:#5b21b6;}
.b-src-screening{background:#e0f2fe;color:#0369a1;}
.reason-box{max-width:280px;font-size:12px;color:#475569;line-height:1.5;background:#fafafa;border-left:3px solid var(--accent);padding:6px 10px;border-radius:5px;}
.cav{display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;background:linear-gradient(135deg,#1e293b,#334155);flex-shrink:0;}
.empty-state{text-align:center;padding:60px 20px;color:var(--muted);}
</style>
</head>
<body>

<div class="hdr">
  <div>
    <h1><i class="fas fa-user-times mr-2"></i>Rejected Candidates</h1>
    <div class="sub">Permanent rejection history &middot; <?php echo htmlspecialchars($current_user_name); ?></div>
  </div>
  <div style="display:flex;gap:9px;">
    <button onclick="exportCSV()" class="btn-h btn-success"><i class="fas fa-file-download"></i> Export CSV</button>
    <a href="hr_screening.php" class="btn-h btn-navy"><i class="fas fa-arrow-left"></i> Back to Screening</a>
  </div>
</div>

<div class="wrap">

<div class="stats-grid">
<?php
$stat_items = [
    [$stats['total']??0,        'Total Rejected',      'fas fa-user-times',   'linear-gradient(135deg,#1e293b,#475569)'],
    [$stats['interview_ct']??0, 'Interview Rounds',     'fas fa-comments',     'linear-gradient(135deg,#3b82f6,#2563eb)'],
    [$stats['assignment_ct']??0,'Assignment Rounds',    'fas fa-file-alt',     'linear-gradient(135deg,#8b5cf6,#7c3aed)'],
    [$stats['worksample_ct']??0,'Work Sample Rounds',   'fas fa-paperclip',    'linear-gradient(135deg,#ec4899,#db2777)'],
    [$stats['overall_ct']??0,   'Overall Decision',     'fas fa-gavel',        'linear-gradient(135deg,#f59e0b,#d97706)'],
    [$stats['kept_ct']??0,      'Kept in Database',     'fas fa-database',     'linear-gradient(135deg,#10b981,#059669)'],
    [$stats['removed_ct']??0,   'Removed Completely',   'fas fa-trash-alt',    'linear-gradient(135deg,#64748b,#475569)'],
];
foreach ($stat_items as $si):
?>
<div class="stat-box">
  <div class="stat-ico" style="background:<?php echo $si[3]; ?>;color:#fff;"><i class="<?php echo $si[2]; ?>"></i></div>
  <div><div class="stat-val"><?php echo $si[0]; ?></div><div class="stat-lbl"><?php echo $si[1]; ?></div></div>
</div>
<?php endforeach; ?>
</div>

<div class="card-panel">
  <div class="card-head">
    <h5><i class="fas fa-list mr-2"></i>Rejection Records</h5>
    <form method="GET" class="filter-row">
      <select name="department" class="fc" style="width:160px;" onchange="this.form.submit()">
        <option value="">All Departments</option>
        <?php foreach ($depts as $d): ?>
        <option value="<?php echo htmlspecialchars($d); ?>" <?php echo ($f_dept===$d)?'selected':''; ?>><?php echo htmlspecialchars($d); ?></option>
        <?php endforeach; ?>
      </select>
      <select name="round_type" class="fc" style="width:160px;" onchange="this.form.submit()">
        <option value="">All Rounds</option>
        <option value="interview" <?php echo ($f_round==='interview')?'selected':''; ?>>Interview</option>
        <option value="assignment" <?php echo ($f_round==='assignment')?'selected':''; ?>>Assignment</option>
        <option value="work_sample" <?php echo ($f_round==='work_sample')?'selected':''; ?>>Work Sample</option>
        <option value="overall" <?php echo ($f_round==='overall')?'selected':''; ?>>Overall Decision</option>
      </select>
      <input type="date" name="date_from" class="fc" style="width:150px;" value="<?php echo htmlspecialchars($f_from); ?>">
      <input type="date" name="date_to" class="fc" style="width:150px;" value="<?php echo htmlspecialchars($f_to); ?>">
      <input type="text" name="search" class="fc" style="width:160px;" placeholder="Search name..." value="<?php echo htmlspecialchars($f_search); ?>">
      <button type="submit" style="padding:9px 15px;border-radius:9px;border:none;background:var(--navy);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-search mr-1"></i>Filter</button>
      <?php if ($f_dept || $f_round || $f_from || $f_to || $f_search): ?>
      <a href="hr-rejected-candidates.php" style="padding:9px 15px;border-radius:9px;border:1px solid var(--border);background:#fff;color:var(--muted);font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;text-decoration:none;">Clear</a>
      <?php endif; ?>
    </form>
  </div>

  <div class="tbl-wrap">
    <table class="rtbl" id="rejTable">
      <thead>
        <tr>
          <th>#</th><th>Candidate</th><th>Position</th><th>Department</th>
          <th>Source</th><th>Rejected At</th><th>Reason</th><th>Rejected By</th><th>Date</th>
          <th>Database Status</th><th>Actions</th>
        </tr>
      </thead>
      <tbody>
      <?php if (mysqli_num_rows($rows_res) === 0): ?>
        <tr><td colspan="10"><div class="empty-state"><i class="fas fa-check-circle fa-2x mb-2" style="display:block;color:#86efac;"></i>No rejected candidates match these filters.</div></td></tr>
      <?php else: while ($row = mysqli_fetch_assoc($rows_res)):
          $init = strtoupper(substr($row['candidate_name'],0,1).(strpos($row['candidate_name'],' ')!==false?substr($row['candidate_name'],strpos($row['candidate_name'],' ')+1,1):''));
          $round_badge_map = ['interview'=>'b-interview','assignment'=>'b-assignment','work_sample'=>'b-work_sample','overall'=>'b-overall'];
          $round_badge_cls = $round_badge_map[$row['round_type']] ?? 'b-overall';
          $round_display = $row['round_number'] > 0 ? htmlspecialchars($row['round_name']) : 'Overall Decision';
          $src = $row['rejection_source'] ?? 'hr_screening';
          $src_label = ($src === 'candidate_tracking') ? 'Candidate Tracking' : 'HR Screening';
          $src_cls   = ($src === 'candidate_tracking') ? 'b-src-tracking' : 'b-src-screening';
          $has_interview_history = intval($row['eval_count'] ?? 0) > 0;
          // View button is ALWAYS shown as long as we have a screening_id to reference.
          // Destination depends on what data actually survives:
          //  - Profile still exists (hr_screenings row present) -> full profile page
          //  - Profile gone but evaluation history survives -> lightweight round-history modal
          //  - Neither exists -> still show the button; it opens the modal which will report "no history found"
          $show_eye_full  = !empty($row['screening_id']) && $row['still_exists'];
          $show_eye_modal = !empty($row['screening_id']) && !$row['still_exists'];
      ?>
      <tr data-name="<?php echo strtolower(htmlspecialchars($row['candidate_name'])); ?>">
        <td style="font-weight:800;color:var(--muted);font-size:12px;">#<?php echo $row['id']; ?></td>
        <td>
          <div style="display:flex;align-items:center;gap:9px;">
            <div class="cav" style="width:32px;height:32px;border-radius:9px;font-size:12px;"><?php echo $init; ?></div>
            <div>
              <div style="font-weight:700;"><?php echo htmlspecialchars($row['candidate_name']); ?></div>
              <div style="font-size:11px;color:var(--muted);"><?php echo htmlspecialchars($row['candidate_email'] ?: '—'); ?></div>
            </div>
          </div>
        </td>
        <td style="font-weight:700;font-size:12px;"><?php echo htmlspecialchars($row['position_applied']); ?></td>
        <td style="font-size:12px;"><?php echo htmlspecialchars($row['department']); ?></td>
        <td><span class="badge-r <?php echo $src_cls; ?>"><?php echo $src_label; ?></span></td>
        <td><span class="badge-r <?php echo $round_badge_cls; ?>"><?php echo $round_display; ?></span></td>
        <td><div class="reason-box"><?php echo nl2br(htmlspecialchars($row['reason'])); ?></div></td>
        <td style="font-size:12px;"><?php echo htmlspecialchars($row['rejected_by'] ?? '—'); ?></td>
        <td style="font-size:11px;color:var(--muted);"><?php echo date('d M Y, h:i A', strtotime($row['created_at'])); ?></td>
        <td>
          <?php if ($row['kept_in_database']): ?>
            <span class="badge-r b-kept"><i class="fas fa-database mr-1"></i>Kept</span>
          <?php else: ?>
            <span class="badge-r b-removed"><i class="fas fa-trash-alt mr-1"></i>Removed</span>
          <?php endif; ?>
        </td>
        <td>
          <div style="display:flex;gap:4px;">
            <?php if ($show_eye_full): ?>
            <a href="hr_screening.php?view_candidate=<?php echo $row['screening_id']; ?>" title="View Full Profile"
              style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;color:var(--blue);font-size:12px;display:flex;align-items:center;justify-content:center;text-decoration:none;"><i class="fas fa-eye"></i></a>
            <?php elseif ($show_eye_modal): ?>
            <button onclick="openEvalHistoryModal(<?php echo $row['screening_id']; ?>, '<?php echo htmlspecialchars(addslashes($row['candidate_name'])); ?>')" title="View Round History (profile removed)"
              style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;color:var(--blue);font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;"><i class="fas fa-eye"></i></button>
            <?php else: ?>
            <button onclick="alert('No screening reference exists for this candidate — this rejection record has no linked profile or round history.')" title="No profile reference available"
              style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#f8fafc;color:#94a3b8;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;"><i class="fas fa-eye"></i></button>
            <?php endif; ?>
            <?php if ($row['resume_path'] && file_exists($row['resume_path'])): ?>
            <a href="<?php echo htmlspecialchars($row['resume_path']); ?>" target="_blank" title="Resume"
              style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;color:var(--success);font-size:12px;display:flex;align-items:center;justify-content:center;text-decoration:none;"><i class="fas fa-file-alt"></i></a>
            <?php endif; ?>
            <button onclick="deleteLog(<?php echo $row['id']; ?>)" title="Remove this log entry"
              style="width:30px;height:30px;border-radius:7px;border:1px solid #fee2e2;background:#fef2f2;cursor:pointer;color:#ef4444;font-size:12px;"><i class="fas fa-times"></i></button>
          </div>
        </td>
      </tr>
      <?php endwhile; endif; ?>
      </tbody>
    </table>
  </div>
</div>

</div><!-- /wrap -->

<!-- Lightweight Round History Modal (for candidates whose profile was removed) -->
<div class="modal fade" id="evalHistoryModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#1e293b,#334155);color:#fff;border-radius:15px 15px 0 0;">
        <h5 style="font-weight:800;margin:0;"><i class="fas fa-history mr-2"></i>Round History — <span id="ehm_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body" id="ehm_body" style="padding:24px;">
        <div style="text-align:center;padding:30px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--navy);"></i></div>
    </div>
    <div class="modal-footer" style="border-top:2px solid var(--border);">
        <div style="font-size:12px;color:var(--muted);"><i class="fas fa-info-circle mr-1"></i>This candidate's profile, resume, and JD were permanently removed, as HR specifically requested removal from the database at the time of rejection. Only round evaluation records survive.</div>
    </div>
</div></div></div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function exportCSV() {
    var csv = [];
    document.querySelectorAll('#rejTable tr').forEach(function(row) {
        var cells = [];
        var cols = row.querySelectorAll('td, th');
        for (var i = 0; i < cols.length - 1; i++) {
            cells.push('"' + cols[i].innerText.replace(/"/g, '""').replace(/\n/g, ' ').trim() + '"');
        }
        if (cells.length) csv.push(cells.join(','));
    });
    var blob = new Blob(['\ufeff' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'Rejected_Candidates.csv';
    a.click();
}

function deleteLog(id) {
    if (!confirm('Remove this rejection log entry? This only deletes the log record, not any existing candidate profile.')) return;
    $.post(window.location.pathname, { ajax_delete_rejection_log: 1, log_id: id }, function(resp) {
        if (resp.success) location.reload();
    }, 'json');
}

function openEvalHistoryModal(screeningId, name) {
    document.getElementById('ehm_name').textContent = name;
    document.getElementById('ehm_body').innerHTML = '<div style="text-align:center;padding:30px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--navy);"></i></div>';
    $('#evalHistoryModal').modal('show');

    $.getJSON(window.location.pathname, { ajax_get_eval_history: 1, screening_id: screeningId }, function(res) {
        if (!res.success) {
            document.getElementById('ehm_body').innerHTML = '<div style="text-align:center;padding:30px;color:var(--muted);"><i class="fas fa-inbox fa-2x" style="opacity:.3;margin-bottom:10px;display:block;"></i>' + (res.message || 'No history found.') + '</div>';
            return;
        }
        var statusColors = { 'Passed':'#10b981', 'Failed':'#ef4444', 'Pending':'#f59e0b', 'Override':'#f59e0b', 'Rejected':'#ef4444' };
        var html = '';
        res.rounds.forEach(function(r) {
            var sc = statusColors[r.status] || '#64748b';
            var pct = parseFloat(r.percentage || 0);
            html += '<div style="background:#f8fafc;border:1px solid var(--border);border-radius:10px;padding:16px;margin-bottom:12px;">';
            html += '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">';
            html += '<div style="font-weight:800;color:var(--navy);font-size:14px;">Round ' + r.round_number + '</div>';
            html += '<span style="font-weight:800;font-size:12px;padding:3px 12px;border-radius:20px;background:' + sc + '22;color:' + sc + ';">' + (r.status || 'Pending') + '</span>';
            html += '</div>';
            if (r.total_marks_possible > 0) {
                html += '<div style="font-size:13px;color:var(--text);margin-bottom:6px;">Score: <strong>' + r.total_marks_obtained + ' / ' + r.total_marks_possible + '</strong> (' + pct.toFixed(1) + '%) &middot; ' + (r.rating_label || '') + '</div>';
            }
            html += '<div style="font-size:12px;color:var(--muted);margin-bottom:6px;">Evaluator: ' + (r.evaluator_name || '—') + ' &middot; ' + new Date(r.created_at).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) + '</div>';
            if (r.hr_notes) {
                html += '<div style="background:#fff;border-left:3px solid #cbd5e1;padding:8px 12px;border-radius:6px;font-size:12px;color:var(--text);margin-top:8px;"><strong>Notes:</strong> ' + r.hr_notes + '</div>';
            }
            if (r.rejection_reason) {
                html += '<div style="background:#fee2e2;border-left:3px solid #ef4444;padding:8px 12px;border-radius:6px;font-size:12px;color:#991b1b;margin-top:8px;"><strong>Rejection Reason:</strong> ' + r.rejection_reason + '</div>';
            }
            html += '</div>';
        });
        document.getElementById('ehm_body').innerHTML = html;
    }).fail(function() {
        document.getElementById('ehm_body').innerHTML = '<div style="text-align:center;padding:30px;color:red;">Failed to load history.</div>';
    });
}
</script>

<!-- Flutter State Preserver -->
<script>
document.addEventListener("DOMContentLoaded", function() {
    const urlEmail = "<?php echo !empty($currentUserEmail) ? '?user_email=' . urlencode($currentUserEmail) : ''; ?>";
    const urlEmailAmp = "<?php echo !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : ''; ?>";
    if (urlEmail) {
        document.querySelectorAll("a").forEach(a => {
            let href = a.getAttribute("href");
            if (href && href.includes(".php")) {
                if (href.includes("?")) {
                    a.setAttribute("href", href + urlEmailAmp);
                } else {
                    a.setAttribute("href", href + urlEmail);
                }
            }
        });
        document.querySelectorAll("form").forEach(f => {
            if (!f.querySelector('input[name="user_email"]')) {
                let input = document.createElement('input');
                input.type = 'hidden';
                input.name = 'user_email';
                input.value = "<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES); ?>";
                f.appendChild(input);
            }
        });
    }
});
</script>

</body>
</html>
<?php ob_end_flush(); ?>