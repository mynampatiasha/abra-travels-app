<?php
// =========================================================================
// HR EMPLOYEE OVERALL DATA DASHBOARD
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
mysqli_report(MYSQLI_REPORT_OFF);

register_shutdown_function(function() {
    $error = error_get_last();
    if ($error && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        echo "<pre style='background:red;color:white;padding:20px;'>FATAL ERROR:\n";
        echo "Type: " . $error['type'] . "\n";
        echo "Message: " . $error['message'] . "\n";
        echo "File: " . $error['file'] . "\n";
        echo "Line: " . $error['line'] . "\n</pre>";
    }
});

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
require_once('library.php');
require_once('funciones.php');

$con = conexion();
if (!$con) { die("DB failed."); }
date_default_timezone_set('Asia/Kolkata');

$currentUserName = $_SESSION['name'] ?? '';
$currentUserRole = $_SESSION['role'] ?? '';

// Fetch Master Pipeline Data
$sql = "
    SELECT 
        s.id AS candidate_id,
        s.candidate_name AS candidate_name,
        s.candidate_email AS candidate_email,
        s.candidate_phone AS candidate_phone,
        s.department,
        s.position_applied,
        s.created_at AS screening_date,
        s.hr_decision AS screening_status,
        
        ol.status AS offer_status,
        ol.sent_at AS offer_sent_at,
        ol.candidate_action_at AS offer_action_at,
        
        dv.status AS dv_status,
        dv.verified_at AS dv_verified_at,
        
        ob.status AS onboarding_status,
        ob.submitted_at AS onboarding_submitted_at,
        
        e.id AS employee_id,
        e.status AS employee_status,
        
        p.stage AS oje_stage,
        p.certified_at AS oje_certified_at,
        
        (SELECT COUNT(*) FROM hr_oje_recert_attempts r WHERE r.employee_id = e.id AND r.passed = 1) AS recert_passed_count,
        (SELECT COUNT(*) FROM hr_oje_cross_training ct WHERE ct.employee_id = e.id AND ct.status = 'completed') AS ct_completed_count,
        (SELECT COUNT(*) FROM hr_oje_cross_training ct WHERE ct.employee_id = e.id AND ct.status = 'active') AS ct_active_count,
        
        (SELECT MAX(round_number) FROM hr_interview_schedules sch WHERE sch.screening_id = s.id) AS max_scheduled_round,
        (SELECT MAX(round_number) FROM hr_screening_evaluations ev WHERE ev.screening_id = s.id) AS max_eval_round
        
    FROM hr_screenings s
    LEFT JOIN hr_offer_letters ol ON ol.candidate_id = s.id
    LEFT JOIN hr_dv_requests dv ON dv.candidate_id = s.id
    LEFT JOIN hr_employee_onboarding_pending ob ON ob.candidate_id = s.id
    LEFT JOIN hr_employees e ON e.personal_email = s.candidate_email OR e.phone = s.candidate_phone
    LEFT JOIN hr_oje_employee_progress p ON p.employee_id = e.id
    ORDER BY s.created_at DESC
";
$result = mysqli_query($con, $sql);
if (!$result) { die("Error in master query: " . mysqli_error($con)); }

$pipeline = [];

$rejected_sids = [];
$rj_res = mysqli_query($con, "SELECT DISTINCT screening_id FROM hr_rejection_log WHERE screening_id IS NOT NULL");
if ($rj_res) {
    while($rj_row = mysqli_fetch_assoc($rj_res)) {
        $rejected_sids[] = $rj_row['screening_id'];
    }
}

while ($row = mysqli_fetch_assoc($result)) {
    $stage = 'Screening';
    $stage_color = '#06b6d4';
    
    $status_lower = strtolower(trim($row['screening_status']));
    $is_rejected = ($status_lower == 'rejected' || $status_lower == 'not interested' || strpos($status_lower, 'rejected') !== false || in_array($row['candidate_id'], $rejected_sids));
    
    if ($is_rejected) {
        $stage = 'Rejected'; $stage_color = '#ef4444';
    } elseif ($row['ct_active_count'] > 0 || $row['ct_completed_count'] > 0) {
        $stage = 'Cross-Training'; $stage_color = '#4ade80';
    } elseif (!empty($row['oje_stage']) && $row['oje_stage'] != 'certified') {
        $stage = 'Training/OJE'; $stage_color = '#3b82f6';
    } elseif ($row['recert_passed_count'] > 0) {
        $stage = 'Recertification Passed'; $stage_color = '#a855f7';
    } elseif ($row['oje_stage'] == 'certified') {
        $stage = 'OJE Certified'; $stage_color = '#10b981';
    } elseif ($row['employee_id'] > 0 && trim(strtolower($row['employee_status'])) == 'active') {
        $stage = 'Active Employee'; $stage_color = '#14b8a6';
    } elseif ($row['onboarding_status'] == 'approved') {
        $stage = 'Onboarding Approved'; $stage_color = '#0ea5e9';
    } elseif ($row['onboarding_status'] == 'pending' || $row['onboarding_status'] == 'submitted') {
        $stage = 'Onboarding Pending'; $stage_color = '#f59e0b';
    } elseif ($row['dv_status'] == 'verified') {
        $stage = 'Docs Verified'; $stage_color = '#8b5cf6';
    } elseif ($row['dv_status'] == 'pending' || $row['dv_status'] == 'submitted') {
        $stage = 'Docs Verification'; $stage_color = '#a855f7';
    } elseif ($row['offer_status'] == 'accepted') {
        $stage = 'Offer Accepted'; $stage_color = '#22c55e';
    } elseif ($row['offer_status'] == 'sent') {
        $stage = 'Offer Sent'; $stage_color = '#eab308';
    } elseif (strtolower($row['screening_status']) == 'selected') {
        $stage = 'Selected'; $stage_color = '#f97316';
    } else {
        $sch_rnd = intval($row['max_scheduled_round']);
        $ev_rnd  = intval($row['max_eval_round']);
        $current_rnd = max(1, max($sch_rnd, $ev_rnd));
        
        $stage = 'Round ' . $current_rnd . ' Screening';
        if ($current_rnd == 1) $stage_color = '#06b6d4';
        elseif ($current_rnd == 2) $stage_color = '#0284c7';
        elseif ($current_rnd == 3) $stage_color = '#4f46e5';
        else $stage_color = '#3730a3';
    }
    
    $row['current_stage'] = $stage;
    $row['stage_color'] = $stage_color;
    $pipeline[] = $row;
}

// =============================================
// FETCH MISSING ACTIVE EMPLOYEES (Direct Hires/Imports)
// =============================================
$existing_emp_ids = [];
foreach ($pipeline as $p) {
    if (!empty($p['employee_id']) && $p['employee_id'] > 0) {
        $existing_emp_ids[] = intval($p['employee_id']);
    }
}
$emp_id_list = implode(',', $existing_emp_ids);
$where_not_in = !empty($existing_emp_ids) ? "AND e.id NOT IN ($emp_id_list)" : "";

$sql_missing = "
    SELECT 
        NULL AS candidate_id,
        e.name AS candidate_name,
        e.personal_email AS candidate_email,
        e.phone AS candidate_phone,
        e.department AS department,
        COALESCE(e.position, e.designation, 'N/A') AS position_applied,
        e.hire_date AS screening_date,
        'Hired' AS screening_status,
        
        'accepted' AS offer_status,
        NULL AS offer_sent_at,
        NULL AS offer_action_at,
        
        'verified' AS dv_status,
        NULL AS dv_verified_at,
        
        'approved' AS onboarding_status,
        NULL AS onboarding_submitted_at,
        
        e.id AS employee_id,
        e.status AS employee_status,
        
        p.stage AS oje_stage,
        p.certified_at AS oje_certified_at,
        
        (SELECT COUNT(*) FROM hr_oje_recert_attempts r WHERE r.employee_id = e.id AND r.passed = 1) AS recert_passed_count,
        (SELECT COUNT(*) FROM hr_oje_cross_training ct WHERE ct.employee_id = e.id AND ct.status = 'completed') AS ct_completed_count,
        (SELECT COUNT(*) FROM hr_oje_cross_training ct WHERE ct.employee_id = e.id AND ct.status = 'active') AS ct_active_count,
        
        0 AS max_scheduled_round,
        0 AS max_eval_round
        
    FROM hr_employees e
    LEFT JOIN hr_oje_employee_progress p ON p.employee_id = e.id
    WHERE LOWER(TRIM(e.status)) = 'active' $where_not_in
";
$res_missing = mysqli_query($con, $sql_missing);
if ($res_missing) {
    while ($row = mysqli_fetch_assoc($res_missing)) {
        $stage = 'Active Employee'; 
        $stage_color = '#14b8a6';
        
        if ($row['ct_active_count'] > 0 || $row['ct_completed_count'] > 0) {
            $stage = 'Cross-Training'; $stage_color = '#4ade80';
        } elseif (!empty($row['oje_stage']) && $row['oje_stage'] != 'certified') {
            $stage = 'Training/OJE'; $stage_color = '#3b82f6';
        } elseif ($row['recert_passed_count'] > 0) {
            $stage = 'Recertification Passed'; $stage_color = '#a855f7';
        } elseif ($row['oje_stage'] == 'certified') {
            $stage = 'OJE Certified'; $stage_color = '#10b981';
        }
        
        $row['current_stage'] = $stage;
        $row['stage_color'] = $stage_color;
        $pipeline[] = $row;
    }
}

// =============================================
// FETCH MISSING REJECTED CANDIDATES
// =============================================
$sql_rejected = "
    SELECT 
        rl.screening_id AS candidate_id,
        rl.candidate_name,
        rl.candidate_email,
        rl.candidate_phone,
        rl.department,
        rl.position_applied,
        rl.created_at AS screening_date,
        'Rejected' AS screening_status,
        
        NULL AS offer_status,
        NULL AS offer_sent_at,
        NULL AS offer_action_at,
        
        NULL AS dv_status,
        NULL AS dv_verified_at,
        
        NULL AS onboarding_status,
        NULL AS onboarding_submitted_at,
        
        NULL AS employee_id,
        NULL AS employee_status,
        
        NULL AS oje_stage,
        NULL AS oje_certified_at,
        
        0 AS recert_passed_count,
        0 AS ct_completed_count,
        0 AS ct_active_count,
        
        rl.round_number AS max_scheduled_round,
        rl.round_number AS max_eval_round
        
    FROM hr_rejection_log rl
    LEFT JOIN hr_screenings s ON s.id = rl.screening_id
    WHERE s.id IS NULL
";
$res_rejected = mysqli_query($con, $sql_rejected);
if ($res_rejected) {
    while ($row = mysqli_fetch_assoc($res_rejected)) {
        $row['current_stage'] = 'Rejected';
        $row['stage_color']   = '#ef4444';
        $pipeline[] = $row;
    }
}

// Unique departments for filter
$departments = array_unique(array_filter(array_column($pipeline, 'department')));
sort($departments);

// Unique stages for filter
$allStages = array_unique(array_column($pipeline, 'current_stage'));
sort($allStages);
include 'header.php';
?>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
        * { box-sizing: border-box; }
        .custom-app-content { margin-left: 240px; margin-top: 68px; min-height: 100vh; padding-bottom: 50px; }
        @media (max-width: 768px) {
            .custom-app-content { margin-left: 0 !important; }
        }
        .hr-lifecycle-wrap { font-family: 'Plus Jakarta Sans', sans-serif; color: #1e293b; }
        
        .page-header { background: linear-gradient(135deg, #1e1b4b, #312e81); color: #fff; padding: 25px 30px; border-radius: 12px; margin: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); display: flex; justify-content: space-between; align-items: center; }
        .page-header h2 { margin: 0; font-weight: 800; font-size: 24px; }
        .page-header p { margin: 5px 0 0; opacity: 0.8; font-size: 14px; }
        
        .main-container { margin: 0 20px 20px; }
        .nav-pills .nav-link { font-weight: 700; color: #475569; padding: 12px 20px; border-radius: 8px; margin-right: 10px; }
        .nav-pills .nav-link.active { background-color: #312e81; color: #fff; }
        
        .card-box { background: #fff; padding: 20px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.03); border: 1px solid #e2e8f0; margin-bottom: 20px; }
        
        /* Filter Bar */
        .filter-bar { background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; padding: 16px 20px; margin-bottom: 16px; display: flex; flex-wrap: wrap; gap: 10px; align-items: flex-end; }
        .filter-bar label { font-size: 11px; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; display: block; }
        .filter-bar .filter-group { display: flex; flex-direction: column; min-width: 140px; }
        .filter-bar input, .filter-bar select { border: 1px solid #e2e8f0; border-radius: 8px; padding: 7px 10px; font-size: 12px; font-family: 'Plus Jakarta Sans', sans-serif; color: #1e293b; background: #f8fafc; outline: none; }
        .filter-bar input:focus, .filter-bar select:focus { border-color: #312e81; background: #fff; }
        .filter-bar .btn-reset { background: #f1f5f9; border: 1px solid #e2e8f0; color: #64748b; font-weight: 700; font-size: 12px; padding: 7px 14px; border-radius: 8px; cursor: pointer; }
        .filter-bar .btn-reset:hover { background: #e2e8f0; }
        .filter-count { font-size: 12px; font-weight: 700; color: #64748b; align-self: center; margin-left: auto; white-space: nowrap; }

        /* Table */
        .table-responsive { overflow-x: auto; }
        table.master-table { width: 100%; border-collapse: separate; border-spacing: 0; }
        table.master-table th { background: #f8fafc; color: #64748b; font-weight: 700; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; padding: 12px 15px; border-bottom: 2px solid #e2e8f0; }
        table.master-table td { padding: 12px 15px; border-bottom: 1px solid #f1f5f9; font-size: 13px; vertical-align: middle; }
        table.master-table tbody tr:hover { background: #f8fafc; }
        .no-results { text-align: center; padding: 40px; color: #94a3b8; font-weight: 600; font-size: 14px; }
        
        .stage-badge { padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 800; color: #fff; text-align: center; display: inline-block; white-space: nowrap; }
        
        /* Charts - clickable */
        .chart-container { position: relative; height: 300px; width: 100%; }
        canvas { cursor: pointer; }
        .chart-hint { font-size: 11px; color: #94a3b8; font-weight: 600; text-align: center; margin-top: 6px; }

        /* Timeline Modal */
        .timeline { position: relative; max-width: 600px; margin: 0 auto; padding-left: 20px; }
        .timeline::before { content: ''; position: absolute; top: 0; left: 6px; height: 100%; width: 2px; background: #e2e8f0; }
        .timeline-item { position: relative; margin-bottom: 20px; }
        .timeline-item::before { content: ''; position: absolute; left: -20px; top: 4px; width: 14px; height: 14px; border-radius: 50%; background: #312e81; border: 3px solid #fff; box-shadow: 0 0 0 1px #cbd5e1; }
        .timeline-date { font-size: 11px; font-weight: 700; color: #64748b; margin-bottom: 4px; }
        .timeline-content { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px; }
        .timeline-title { font-size: 14px; font-weight: 700; color: #1e293b; margin-bottom: 4px; }
        .timeline-desc { font-size: 12px; color: #475569; margin: 0; }

        /* Drill-down modal table */
        .drill-table { width: 100%; border-collapse: collapse; font-size: 13px; }
        .drill-table th { background: #f8fafc; color: #64748b; font-weight: 700; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; padding: 10px 12px; border-bottom: 2px solid #e2e8f0; }
        .drill-table td { padding: 10px 12px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
        .drill-table tr:last-child td { border-bottom: none; }
        .drill-table tr:hover td { background: #f8fafc; }
        .drill-modal-header { background: linear-gradient(135deg, #1e1b4b, #312e81); color: #fff; }
        .drill-modal-header h5 { font-weight: 800; margin: 0; }
        .drill-modal-header button { color: #fff; opacity: 0.8; }
        .drill-modal-header button:hover { opacity: 1; }
        .drill-count-badge { background: rgba(255,255,255,0.2); color: #fff; font-size: 12px; font-weight: 700; padding: 3px 10px; border-radius: 20px; margin-left: 10px; }

        @media (max-width: 768px) {
            .page-header { flex-direction: column; gap: 12px; }
            .filter-bar { flex-direction: column; }
            .filter-bar .filter-group { min-width: 100%; }
            .filter-count { margin-left: 0; }
        }
</style>
<div class="custom-app-content">
<div class="hr-lifecycle-wrap" style="padding:20px;">

<div class="page-header">
    <div>
        <h2><i class="fas fa-project-diagram mr-2"></i>HR Lifecycle Dashboard</h2>
        <p>Comprehensive overview of candidate and employee pipelines</p>
    </div>
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    
</div>

<div class="main-container">

    <?php if (!$is_admin): ?>
    
    <div style="text-align:center;padding:80px 20px;background:#fff;border-radius:12px;box-shadow:0 4px 15px rgba(0,0,0,0.05);">
        <i class="fas fa-hand-sparkles" style="font-size:64px;color:#6366f1;margin-bottom:20px;opacity:0.9;"></i>
        <h2 style="font-weight:800;color:#1e293b;font-size:28px;margin-bottom:10px;">Welcome to the Screening Module</h2>
        <p style="color:#64748b;font-size:16px;max-width:500px;margin:0 auto;line-height:1.6;">You have successfully accessed the HR Screening Hub. The full analytics dashboard is currently restricted to Administrators, but you can navigate to your active modules using the sidebar.</p>
    </div>
    
    <?php else: ?>

    <!-- ANALYTICS CHARTS -->
    <div class="row" style="display:flex; flex-wrap:wrap;">
        <div class="col-md-4" style="margin-bottom:20px;">
            <div class="card-box" style="height:100%;">
                <h5 style="font-weight:700; font-size:14px; margin-bottom:4px; color:#1e293b;"><i class="fas fa-filter mr-2"></i>Overall Pipeline Funnel</h5>
                <p class="chart-hint"><i class="fas fa-hand-pointer mr-1"></i>Click a bar to see candidates</p>
                <div class="chart-container"><canvas id="funnelChart"></canvas></div>
            </div>
        </div>
        <div class="col-md-4" style="margin-bottom:20px;">
            <div class="card-box" style="height:100%;">
                <h5 style="font-weight:700; font-size:14px; margin-bottom:4px; color:#1e293b;"><i class="fas fa-chart-pie mr-2"></i>Active Workforce Distribution</h5>
                <p class="chart-hint"><i class="fas fa-hand-pointer mr-1"></i>Click a segment to see candidates</p>
                <div class="chart-container"><canvas id="distributionChart"></canvas></div>
            </div>
        </div>
        <div class="col-md-4" style="margin-bottom:20px;">
            <div class="card-box" style="height:100%;">
                <h5 style="font-weight:700; font-size:14px; margin-bottom:4px; color:#1e293b;"><i class="fas fa-graduation-cap mr-2"></i>OJE & Training Status</h5>
                <p class="chart-hint"><i class="fas fa-hand-pointer mr-1"></i>Click a segment to see employees</p>
                <div class="chart-container"><canvas id="trainingChart"></canvas></div>
            </div>
        </div>
    </div>

    <!-- Filter Bar -->
    <div class="filter-bar">
        <div class="filter-group" style="min-width:200px;">
            <label><i class="fas fa-search mr-1"></i>Search</label>
            <input type="text" id="filterSearch" placeholder="Name, email, phone..." oninput="applyFilters()">
        </div>
        <div class="filter-group">
            <label><i class="fas fa-building mr-1"></i>Department</label>
            <select id="filterDept" onchange="applyFilters()">
                <option value="">All Departments</option>
                <?php foreach ($departments as $d): ?>
                <option value="<?php echo htmlspecialchars($d); ?>"><?php echo htmlspecialchars($d); ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="filter-group">
            <label><i class="fas fa-layer-group mr-1"></i>Stage</label>
            <select id="filterStage" onchange="applyFilters()">
                <option value="">All Stages</option>
                <?php foreach ($allStages as $st): ?>
                <option value="<?php echo htmlspecialchars($st); ?>"><?php echo htmlspecialchars($st); ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="filter-group">
            <label><i class="fas fa-calendar mr-1"></i>From Date</label>
            <input type="date" id="filterDateFrom" onchange="applyFilters()">
        </div>
        <div class="filter-group">
            <label><i class="fas fa-calendar mr-1"></i>To Date</label>
            <input type="date" id="filterDateTo" onchange="applyFilters()">
        </div>
        <div>
            <button class="btn-reset" onclick="resetFilters()"><i class="fas fa-times mr-1"></i>Reset</button>
        </div>
        <div>
            <button class="btn-reset" onclick="exportCSV()" style="background:#10b981;color:#fff;border-color:#10b981;"><i class="fas fa-file-download mr-1"></i>Export CSV</button>
        </div>
        <div class="filter-count" id="filterCount"></div>
    </div>

    <div class="card-box">
        <div class="table-responsive">
            <table class="master-table" id="masterTable">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Contact</th>
                        <th>Role & Dept</th>
                        <th>Created</th>
                        <th>Furthest Stage</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody id="masterTableBody">
                    <?php foreach ($pipeline as $p): ?>
                    <tr
                        data-name="<?php echo strtolower(htmlspecialchars($p['candidate_name'])); ?>"
                        data-email="<?php echo strtolower(htmlspecialchars($p['candidate_email'])); ?>"
                        data-phone="<?php echo htmlspecialchars($p['candidate_phone']); ?>"
                        data-dept="<?php echo htmlspecialchars($p['department']); ?>"
                        data-stage="<?php echo htmlspecialchars($p['current_stage']); ?>"
                        data-date="<?php echo date('Y-m-d', strtotime($p['screening_date'])); ?>"
                    >
                        <td><div style="font-weight:700; color:#1e293b;"><?php echo htmlspecialchars($p['candidate_name']); ?></div></td>
                        <td>
                            <div style="font-size:12px; color:#475569;"><i class="fas fa-envelope mr-1 text-muted"></i><?php echo htmlspecialchars($p['candidate_email']); ?></div>
                            <div style="font-size:12px; color:#475569;"><i class="fas fa-phone mr-1 text-muted"></i><?php echo htmlspecialchars($p['candidate_phone']); ?></div>
                        </td>
                        <td>
                            <div style="font-weight:700; font-size:12px; color:#334155;"><?php echo htmlspecialchars($p['position_applied']); ?></div>
                            <div style="font-size:11px; color:#64748b;"><?php echo htmlspecialchars($p['department']); ?></div>
                        </td>
                        <td><?php echo date('d M Y', strtotime($p['screening_date'])); ?></td>
                        <td>
                            <span class="stage-badge" style="background-color: <?php echo $p['stage_color']; ?>">
                                <?php echo htmlspecialchars($p['current_stage']); ?>
                            </span>
                        </td>
                        <td>
                            <button class="btn btn-sm btn-outline-primary" style="font-size:11px; font-weight:700;" onclick="openTimeline(<?php echo $p['candidate_id']; ?>, '<?php echo addslashes(htmlspecialchars($p['candidate_name'])); ?>', <?php echo intval($p['employee_id']); ?>)">
                                <i class="fas fa-history mr-1"></i> View Timeline
                            </button>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
            <div class="no-results" id="noResults" style="display:none;"><i class="fas fa-search fa-2x mb-3 d-block"></i>No records match your filters.</div>
        </div>
    </div>
</div>

<!-- Timeline Modal -->
<div class="modal fade" id="timelineModal" tabindex="-1">
    <div class="modal-dialog modal-dialog-scrollable">
        <div class="modal-content">
            <div class="modal-header" style="background:#f8fafc; border-bottom:1px solid #e2e8f0;">
                <h5 class="modal-title" style="font-weight:800; color:#1e293b;"><i class="fas fa-clock mr-2 text-primary"></i>Lifecycle Timeline</h5>
                <button type="button" class="close" data-dismiss="modal">&times;</button>
            </div>
            <div class="modal-body" id="timelineModalBody">
                <div class="text-center py-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i></div>
            </div>
        </div>
    </div>
</div>

<!-- Drill-Down Modal -->
<div class="modal fade" id="drillModal" tabindex="-1">
    <div class="modal-dialog" style="width:92%; max-width:1150px;">
        <div class="modal-content">
            <div class="modal-header drill-modal-header">
                <div>
                    <h5 class="modal-title">
                        <i class="fas fa-users mr-2"></i>
                        <span id="drillModalTitle">Stage Details</span>
                        <span class="drill-count-badge" id="drillModalCount">0</span>
                    </h5>
                    <div style="font-size:12px; opacity:0.8; margin-top:4px;">Candidates / Employees in this stage</div>
                </div>
                <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
            </div>
            <div class="modal-body p-0" id="drillModalBody" style="max-height:65vh; overflow-y:auto;">
                <div class="text-center py-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i></div>
            </div>
        </div>
    </div>
</div>

<script>
// =============================================
// ALL PIPELINE DATA (for drill-down)
// =============================================
const allPipeline = <?php echo json_encode($pipeline); ?>;

// =============================================
// CHART DATA
// =============================================
<?php
$pipeline_rejections = count(array_filter($pipeline, fn($p) => strpos(strtolower($p['current_stage']), 'rejected') !== false || strtolower($p['screening_status']) === 'rejected' || strtolower($p['screening_status']) === 'not interested'));
$total_rejections = $pipeline_rejections;

$counts = [
    'Total Candidates' => count($pipeline),
    'Offered'          => count(array_filter($pipeline, fn($p) => in_array($p['offer_status'], ['sent','accepted']))),
    'Docs Verified'    => count(array_filter($pipeline, fn($p) => $p['dv_status'] == 'verified')),
    'Onboarded'        => count(array_filter($pipeline, fn($p) => in_array($p['onboarding_status'], ['submitted','approved']))),
    'Active Employees' => count(array_filter($pipeline, fn($p) => trim(strtolower($p['employee_status'])) == 'active')),
    'Total Rejected'   => $total_rejections
];

$dist = [];
foreach ($pipeline as $p) {
    if (!isset($dist[$p['current_stage']])) $dist[$p['current_stage']] = 0;
    $dist[$p['current_stage']]++;
}

$train_ct        = count(array_filter($pipeline, fn($p) => $p['ct_active_count'] > 0 || $p['ct_completed_count'] > 0));
$train_active    = count(array_filter($pipeline, fn($p) => $p['ct_active_count'] == 0 && $p['ct_completed_count'] == 0 && !empty($p['oje_stage']) && $p['oje_stage'] != 'certified'));
$train_recert    = count(array_filter($pipeline, fn($p) => $p['ct_active_count'] == 0 && $p['ct_completed_count'] == 0 && ($p['oje_stage'] == 'certified' || empty($p['oje_stage'])) && $p['recert_passed_count'] > 0));
$train_certified = count(array_filter($pipeline, fn($p) => $p['ct_active_count'] == 0 && $p['ct_completed_count'] == 0 && $p['oje_stage'] == 'certified' && $p['recert_passed_count'] == 0));
$train_none      = count(array_filter($pipeline, fn($p) => trim(strtolower($p['employee_status'])) == 'active' && $p['ct_active_count'] == 0 && $p['ct_completed_count'] == 0 && empty($p['oje_stage']) && $p['recert_passed_count'] == 0));
?>

// =============================================
// DRILL-DOWN LOGIC
// =============================================
function openDrillDown(stageLabel, filterFn) {
    const filtered = allPipeline.filter(filterFn);
    $('#drillModalTitle').text(stageLabel);
    $('#drillModalCount').text(filtered.length + ' record' + (filtered.length !== 1 ? 's' : ''));
    
    if (filtered.length === 0) {
        $('#drillModalBody').html('<div class="text-center py-5 text-muted"><i class="fas fa-inbox fa-2x mb-3 d-block"></i>No records found for this stage.</div>');
    } else {
        let html = '<div class="table-responsive"><table class="drill-table"><thead><tr>';
        html += '<th>#</th><th>Name</th><th>Contact</th><th>Dept & Role</th><th>Applied On</th><th>Stage</th><th>Key Date</th><th>Action</th>';
        html += '</tr></thead><tbody>';
        
        filtered.forEach((p, i) => {
            // Pick most relevant date for this stage
            let keyDate = '—';
            let keyLabel = '';
            if (p.oje_certified_at)           { keyDate = formatDate(p.oje_certified_at);           keyLabel = 'Certified'; }
            else if (p.onboarding_submitted_at){ keyDate = formatDate(p.onboarding_submitted_at);    keyLabel = 'Onboarded'; }
            else if (p.dv_verified_at)         { keyDate = formatDate(p.dv_verified_at);             keyLabel = 'DV Done'; }
            else if (p.offer_action_at)        { keyDate = formatDate(p.offer_action_at);            keyLabel = 'Offer Action'; }
            else if (p.offer_sent_at)          { keyDate = formatDate(p.offer_sent_at);              keyLabel = 'Offer Sent'; }
            else if (p.screening_date)         { keyDate = formatDate(p.screening_date);             keyLabel = 'Screened'; }

            html += `<tr>
                <td style="color:#94a3b8; font-weight:700;">${i+1}</td>
                <td style="font-weight:700; color:#1e293b;">${escHtml(p.candidate_name)}</td>
                <td>
                    <div style="font-size:12px; color:#475569;"><i class="fas fa-envelope mr-1 text-muted"></i>${escHtml(p.candidate_email || '—')}</div>
                    <div style="font-size:12px; color:#475569;"><i class="fas fa-phone mr-1 text-muted"></i>${escHtml(p.candidate_phone || '—')}</div>
                </td>
                <td>
                    <div style="font-weight:700; font-size:12px; color:#334155;">${escHtml(p.position_applied || '—')}</div>
                    <div style="font-size:11px; color:#64748b;">${escHtml(p.department || '—')}</div>
                </td>
                <td style="font-size:12px;">${formatDate(p.screening_date)}</td>
                <td><span class="stage-badge" style="background-color:${p.stage_color}">${escHtml(p.current_stage)}</span></td>
                <td style="font-size:12px;">
                    ${keyDate !== '—' ? `<div style="font-weight:700; color:#334155;">${keyDate}</div><div style="font-size:10px; color:#94a3b8;">${keyLabel}</div>` : '—'}
                </td>
                <td>
                    <button class="btn btn-sm btn-outline-primary" style="font-size:11px; font-weight:700;" onclick="openTimelineFromDrill(${p.candidate_id}, '${escHtml(p.candidate_name)}', ${p.employee_id || 0})">
                        <i class="fas fa-history mr-1"></i>Timeline
                    </button>
                </td>
            </tr>`;
        });

        html += '</tbody></table></div>';
        $('#drillModalBody').html(html);
    }
    
    $('#drillModal').modal('show');
}

function openTimelineFromDrill(candidateId, candidateName, employeeId) {
    $('#drillModal').modal('hide');
    setTimeout(() => openTimeline(candidateId, candidateName, employeeId), 400);
}

function escHtml(str) {
    if (!str) return '—';
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function formatDate(dateStr) {
    if (!dateStr || dateStr === '0000-00-00 00:00:00' || dateStr === '0000-00-00') return '—';
    const d = new Date(dateStr);
    if (isNaN(d)) return '—';
    return d.toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' });
}

// =============================================
// FUNNEL CHART — Bar (horizontal)
// =============================================
const funnelLabels = <?php echo json_encode(array_keys($counts)); ?>;
const funnelData   = <?php echo json_encode(array_values($counts)); ?>;
const funnelColors = ['#06b6d4','#eab308','#a855f7','#0ea5e9','#14b8a6','#ef4444'];

const funnelFilterMap = {
    'Total Candidates': p => true,
    'Offered':          p => ['sent','accepted'].includes(p.offer_status),
    'Docs Verified':    p => p.dv_status === 'verified',
    'Onboarded':        p => ['submitted','approved'].includes(p.onboarding_status),
    'Active Employees': p => (p.employee_status || '').toLowerCase().trim() === 'active',
    'Total Rejected':   p => (p.current_stage || '').toLowerCase().includes('rejected') || (p.screening_status || '').toLowerCase().includes('rejected') || (p.screening_status || '').toLowerCase().includes('not interested')
};

const funnelChart = new Chart(document.getElementById('funnelChart'), {
    type: 'bar',
    data: {
        labels: funnelLabels,
        datasets: [{
            label: 'Headcount',
            data: funnelData,
            backgroundColor: funnelColors,
            borderRadius: 4
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: 'y',
        plugins: { legend: { display: false } },
        onClick: (evt, elements) => {
            if (!elements.length) return;
            const idx = elements[0].index;
            const label = funnelLabels[idx];
            const filterFn = funnelFilterMap[label] || (() => false);
            openDrillDown(label, filterFn);
        }
    }
});

// =============================================
// DISTRIBUTION CHART — Doughnut
// =============================================
const distLabels = <?php echo json_encode(array_keys($dist)); ?>;
const distData   = <?php echo json_encode(array_values($dist)); ?>;
const distColors = [
    '#f43f5e', /* Rose Red */
    '#3b82f6', /* Bright Blue */
    '#eab308', /* Yellow */
    '#22c55e', /* Emerald Green */
    '#a855f7', /* Purple */
    '#f97316', /* Orange */
    '#06b6d4', /* Cyan */
    '#6366f1', /* Indigo */
    '#84cc16', /* Lime */
    '#ec4899', /* Pink */
    '#14b8a6', /* Teal */
    '#10b981', /* Mint */
    '#f59e0b'  /* Amber */
];

const distChart = new Chart(document.getElementById('distributionChart'), {
    type: 'doughnut',
    data: {
        labels: distLabels,
        datasets: [{
            data: distData,
            backgroundColor: distColors
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { position: 'bottom', labels: { boxWidth: 10, font: { size: 10 } } } },
        onClick: (evt, elements) => {
            if (!elements.length) return;
            const idx = elements[0].index;
            const label = distLabels[idx];
            openDrillDown(label, p => p.current_stage === label);
        }
    }
});

// =============================================
// TRAINING CHART — Pie
// =============================================
const trainLabels = ['In Training / OJE', 'Fully Certified', 'Cross-Training', 'Recertification', 'Not Started'];
const trainData   = [<?php echo $train_active; ?>, <?php echo $train_certified; ?>, <?php echo $train_ct; ?>, <?php echo $train_recert; ?>, <?php echo max(0, $train_none); ?>];
const trainColors = ['#3b82f6','#10b981','#4ade80','#a855f7','#e2e8f0'];

const trainFilterMap = {
    'In Training / OJE': p => p.ct_active_count == 0 && p.ct_completed_count == 0 && p.oje_stage && p.oje_stage !== 'certified',
    'Fully Certified':   p => p.ct_active_count == 0 && p.ct_completed_count == 0 && p.oje_stage === 'certified' && p.recert_passed_count == 0,
    'Cross-Training':    p => p.ct_active_count > 0 || p.ct_completed_count > 0,
    'Recertification':   p => p.ct_active_count == 0 && p.ct_completed_count == 0 && (p.oje_stage === 'certified' || !p.oje_stage) && p.recert_passed_count > 0,
    'Not Started':       p => (p.employee_status || '').toLowerCase().trim() === 'active' && p.ct_active_count == 0 && p.ct_completed_count == 0 && !p.oje_stage && p.recert_passed_count == 0
};

const trainingChart = new Chart(document.getElementById('trainingChart'), {
    type: 'pie',
    data: {
        labels: trainLabels,
        datasets: [{
            data: trainData,
            backgroundColor: trainColors
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { position: 'bottom' } },
        onClick: (evt, elements) => {
            if (!elements.length) return;
            const idx = elements[0].index;
            const label = trainLabels[idx];
            const filterFn = trainFilterMap[label] || (() => false);
            openDrillDown(label, filterFn);
        }
    }
});

// =============================================
// MASTER GRID FILTERS
// =============================================
function applyFilters() {
    const search    = document.getElementById('filterSearch').value.toLowerCase().trim();
    const dept      = document.getElementById('filterDept').value.toLowerCase();
    const stage     = document.getElementById('filterStage').value.toLowerCase();
    const dateFrom  = document.getElementById('filterDateFrom').value;
    const dateTo    = document.getElementById('filterDateTo').value;
    
    const rows = document.querySelectorAll('#masterTableBody tr');
    let visible = 0;
    
    rows.forEach(row => {
        const name  = row.dataset.name  || '';
        const email = row.dataset.email || '';
        const phone = row.dataset.phone || '';
        const rDept = (row.dataset.dept  || '').toLowerCase();
        const rStage= (row.dataset.stage || '').toLowerCase();
        const rDate = row.dataset.date  || '';
        
        const matchSearch = !search || name.includes(search) || email.includes(search) || phone.includes(search);
        const matchDept   = !dept  || rDept === dept;
        const matchStage  = !stage || rStage === stage;
        const matchFrom   = !dateFrom || rDate >= dateFrom;
        const matchTo     = !dateTo   || rDate <= dateTo;
        
        const show = matchSearch && matchDept && matchStage && matchFrom && matchTo;
        row.style.display = show ? '' : 'none';
        if (show) visible++;
    });

    document.getElementById('filterCount').textContent = visible + ' record' + (visible !== 1 ? 's' : '') + ' shown';
    document.getElementById('noResults').style.display = visible > 0 ? 'none' : 'block';
}

function resetFilters() {
    document.getElementById('filterSearch').value  = '';
    document.getElementById('filterDept').value    = '';
    document.getElementById('filterStage').value   = '';
    document.getElementById('filterDateFrom').value = '';
    document.getElementById('filterDateTo').value  = '';
    applyFilters();
}

function exportCSV() {
    var rows = Array.from(document.querySelectorAll('#masterTableBody tr')).filter(function(r) { return r.style.display !== 'none'; });
    var csv = [['Name','Email','Phone','Department','Position','Created','Stage']];
    rows.forEach(function(r) {
        csv.push([
            r.dataset.name || '',
            r.dataset.email || '',
            r.dataset.phone || '',
            r.dataset.dept || '',
            r.querySelector('td:nth-child(3) div').textContent.trim(),
            r.dataset.date || '',
            r.dataset.stage || ''
        ]);
    });
    var csvContent = csv.map(function(row) {
        return row.map(function(v) { return '"' + String(v).replace(/"/g, '""') + '"'; }).join(',');
    }).join('\n');
    var blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'HR_Lifecycle_Pipeline.csv';
    a.click();
}

// Init count on load
applyFilters();

// =============================================
// TIMELINE MODAL
// =============================================
function openTimeline(candidateId, candidateName = '', employeeId = 0) {
    if (candidateName) {
        $('#timelineModal .modal-title').html('<i class="fas fa-clock mr-2 text-primary"></i>Lifecycle Timeline - ' + candidateName);
    } else {
        $('#timelineModal .modal-title').html('<i class="fas fa-clock mr-2 text-primary"></i>Lifecycle Timeline');
    }
    
    $('#timelineModal').modal('show');
    $('#timelineModalBody').html('<div class="text-center py-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i><p class="mt-2 text-muted">Loading timeline...</p></div>');
    
    $.ajax({
        url: 'hr-employee-overall-data-ajax.php',
        type: 'POST',
        data: { action: 'get_timeline', candidate_id: candidateId, employee_id: employeeId },
        success: function(res) {
            $('#timelineModalBody').html(res);
        },
        error: function(xhr) {
            $('#timelineModalBody').html(xhr.responseText || '<div class="alert alert-danger">Error loading timeline data.</div>');
        }
    });
}

// Fix Chart.js rendering on tab change
$(document).ready(function() {
    $('a[data-toggle="pill"]').on('shown.bs.tab', function (e) {
        if (e.target.id === 'pills-analytics-tab') {
            if (typeof funnelChart !== 'undefined') funnelChart.resize();
            if (typeof distChart !== 'undefined') distChart.resize();
            if (typeof trainingChart !== 'undefined') trainingChart.resize();
        }
    });
    
    // Initial resize to catch any load-time dimension issues
    setTimeout(function() {
        if ($('#pills-analytics').hasClass('active')) {
            if (typeof funnelChart !== 'undefined') funnelChart.resize();
            if (typeof distChart !== 'undefined') distChart.resize();
            if (typeof trainingChart !== 'undefined') trainingChart.resize();
        }
    }, 250);
});
</script>
<?php endif; ?>

</div><!-- /.hr-lifecycle-wrap -->
</div><!-- /.custom-app-content -->

<?php include 'footer.php'; ?>


