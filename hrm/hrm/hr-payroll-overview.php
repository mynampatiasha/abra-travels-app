<?php
// ============================================================================
// PAYROLL OVERVIEW DASHBOARD — Managing Director only.
// Read-only aggregate view: charts by Company / Department / Position /
// Month, with click-to-drill-down into the underlying employee records.
// Separate file from hr-payroll-fixed.php on purpose — keeps this new
// dashboard from touching the existing, already-tuned payroll list page.
// ============================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
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

try {
    require_once('database.php');
    require_once('library.php');
    require_once('funciones.php');
} catch(Exception $e) { die("Error: " . $e->getMessage()); }

date_default_timezone_set('Asia/Kolkata');

if(!isset($_SESSION['user_name'])) { header("Location: login.php"); exit; }
if(!isset($dbConn) || !$dbConn)    die("Database connection failed.");

// ============================================================================
// AUTHORIZATION — same detection pattern as hr-payroll-fixed.php
// ============================================================================
$currentUserName = trim($_SESSION['user_name'] ?? '');
$emp_name_db     = '';
$emp_dept        = '';
$emp_position    = '';

if(!empty($currentUserName)) {
    $ns  = mysqli_real_escape_string($dbConn, $currentUserName);
    $res = mysqli_query($dbConn, "SELECT name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$ns%') AND status='active' LIMIT 1");
    if($res && mysqli_num_rows($res) > 0) {
        $r            = mysqli_fetch_assoc($res);
        $emp_name_db  = $r['name'];
        $emp_dept     = $r['department'] ?? '';
        $emp_position = $r['position']   ?? '';
    }
}

$is_abishek = (stripos($emp_name_db,'abishek')!==false || stripos($currentUserName,'abishek')!==false);
$is_md      = (stripos($emp_position,'managing director')!==false || stripos($emp_position,'ceo')!==false);

// This dashboard is Managing Director only. Anyone else who lands here
// (old link, direct URL) is sent back to the normal payroll list instead
// of seeing a blank/broken page.
if(!($is_abishek || $is_md)) {
    header("Location: hr-payroll-fixed.php");
    exit;
}

// ============================================================================
// FILTERS — reuse the same session keys as hr-payroll-fixed.php so the
// date range / company stays in sync between the list page and this one.
// ============================================================================
$filter_from = $_POST['filter_from'] ?? $_SESSION['payroll_filter_from'] ?? date('Y-m-01');
$filter_to   = $_POST['filter_to']   ?? $_SESSION['payroll_filter_to']   ?? date('Y-m-t');
$filter_company = $_POST['filter_company'] ?? $_SESSION['payroll_filter_company'] ?? '';
if(isset($_POST['apply_filter'])) {
    $_SESSION['payroll_filter_from']    = $filter_from;
    $_SESSION['payroll_filter_to']      = $filter_to;
    $_SESSION['payroll_filter_company'] = $filter_company;
}
$company_sql = '';
if(!empty($filter_company)) {
    $fc_safe     = mysqli_real_escape_string($dbConn, $filter_company);
    $company_sql = " AND COALESCE(NULLIF(e.company_name,''),'(No Company Set)') = '$fc_safe' ";
}

$companies_list = [];
$cq = mysqli_query($dbConn, "SELECT DISTINCT company_name FROM hr_employees WHERE status='active' AND company_name IS NOT NULL AND company_name != '' ORDER BY company_name");
if($cq) while($c = mysqli_fetch_assoc($cq)) $companies_list[] = $c['company_name'];
$cq2 = mysqli_query($dbConn, "SELECT company_name FROM hr_companies ORDER BY company_name");
if($cq2) while($c = mysqli_fetch_assoc($cq2)) if(!in_array($c['company_name'], $companies_list)) $companies_list[] = $c['company_name'];
sort($companies_list);

$filter_from_dt = new DateTime($filter_from);
$filter_to_dt   = new DateTime($filter_to);
$period_label = ($filter_from_dt->format('Y-m') === $filter_to_dt->format('Y-m'))
    ? $filter_from_dt->format('F Y')
    : $filter_from_dt->format('d M Y').' - '.$filter_to_dt->format('d M Y');

// ============================================================================
// DATA — one row per employee-payroll-record in range. Everything else
// (department / position / company / monthly charts, leaderboard,
// drill-down) is aggregated client-side in JS from this single dataset,
// same approach used for the Attendance Overview tab. Keeps the SQL here
// simple and low-risk.
// ============================================================================
$data = mysqli_query($dbConn, "SELECT p.*, e.name, e.employee_id as emp_code,
        COALESCE(NULLIF(e.company_name,''),'(No Company Set)') as company_name,
        COALESCE(NULLIF(e.department,''),'Unassigned') as pv_department,
        COALESCE(NULLIF(e.position,''),'Unassigned') as pv_position
    FROM hr_payroll p
    INNER JOIN hr_employees e ON p.employee_id = e.id
    WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$filter_from' AND '$filter_to'
    AND e.status='active' $company_sql
    ORDER BY p.pay_year ASC, p.pay_month ASC, e.name ASC");
if(!$data) die("Error: ".mysqli_error($dbConn));

$payroll_overview_records = [];
$total_net = $total_gross = $total_ot = $total_deductions = 0;
$emp_codes_seen = [];
while($row = mysqli_fetch_assoc($data)) {
    $net  = floatval($row['net_salary']);
    $gross = floatval($row['gross_pay']);
    $ot   = floatval($row['ot_amount'] ?? $row['ot'] ?? 0);
    $ded  = floatval($row['penalty'] ?? 0) + floatval($row['other_deductions'] ?? 0);

    $total_net  += $net;
    $total_gross += $gross;
    $total_ot   += $ot;
    $total_deductions += $ded;
    $emp_codes_seen[$row['emp_code']] = true;

    $payroll_overview_records[] = [
        'employee'   => $row['name'],
        'emp_code'   => $row['emp_code'],
        'company'    => $row['company_name'],
        'department' => $row['pv_department'],
        'position'   => $row['pv_position'],
        'month'      => intval($row['pay_month']),
        'year'       => intval($row['pay_year']),
        'month_label'=> date('M Y', mktime(0,0,0,intval($row['pay_month']),1,intval($row['pay_year']))),
        'gross'      => $gross,
        'net'        => $net,
        'ctc'        => floatval($row['total_ctc'] ?? 0),
        'ot'         => $ot,
        'present_days'    => floatval($row['present_days'] ?? 0),
        'paid_leave_days' => floatval($row['paid_leave_days'] ?? 0),
        'absent_days'     => floatval($row['absent_days'] ?? 0),
        'deductions'      => $ded,
    ];
}
$total_records = count($payroll_overview_records);
$total_employees = count($emp_codes_seen);
$avg_net = $total_employees > 0 ? ($total_net / $total_records ?: 0) : 0;
$records_json = json_encode($payroll_overview_records);
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Payroll Overview — Managing Director</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Inter',sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;padding:20px;color:#1a202c;}
    .wrap{max-width:1900px;margin:0 auto;background:white;border-radius:24px;box-shadow:0 25px 50px -12px rgba(0,0,0,.25);overflow:hidden;}
    .hdr{background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);color:white;padding:35px 50px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:15px;}
    .hdr h1{margin:0 0 5px;font-size:30px;font-weight:900;}
    .hdr p{margin:0;font-size:13px;opacity:.9;}
    .btn-back{background:rgba(255,255,255,.2);color:white;padding:10px 20px;border-radius:10px;font-weight:600;text-decoration:none;display:inline-flex;align-items:center;gap:8px;border:1px solid rgba(255,255,255,.3);transition:all .3s;}
    .btn-back:hover{background:white;color:#1e3c72;text-decoration:none;}
    .content{padding:35px 50px;}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:16px;margin-bottom:30px;}
    .sc{color:white;padding:20px;border-radius:14px;box-shadow:0 8px 15px -3px rgba(0,0,0,.1);}
    .sc.blue{background:linear-gradient(135deg,#3b82f6,#2563eb);}
    .sc.green{background:linear-gradient(135deg,#10b981,#059669);}
    .sc.orange{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .sc.purple{background:linear-gradient(135deg,#8b5cf6,#7c3aed);}
    .sc.teal{background:linear-gradient(135deg,#14b8a6,#0d9488);}
    .sc.red{background:linear-gradient(135deg,#ef4444,#dc2626);}
    .sc .lbl{font-size:11px;font-weight:700;text-transform:uppercase;opacity:.9;margin-bottom:6px;}
    .sc .val{font-size:24px;font-weight:900;}
    .ctrl{background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:2px solid #3b82f6;border-radius:14px;padding:20px 25px;margin-bottom:30px;display:flex;gap:15px;align-items:flex-end;flex-wrap:wrap;justify-content:space-between;}
    label{display:block;font-weight:700;margin-bottom:6px;color:#1e40af;font-size:13px;}
    .fc{padding:9px 13px;border:2px solid #bfdbfe;border-radius:8px;font-size:13px;font-weight:600;background:white;}
    .btn{padding:9px 20px;border-radius:9px;font-weight:700;font-size:13px;border:none;cursor:pointer;transition:all .3s;display:inline-flex;align-items:center;gap:7px;box-shadow:0 3px 6px rgba(0,0,0,.1);}
    .btn:hover{transform:translateY(-2px);}
    .btn-p{background:linear-gradient(135deg,#3b82f6,#2563eb);color:white;}
    .btn-d{background:linear-gradient(135deg,#64748b,#475569);color:white;}
    .charts-grid{display:grid;grid-template-columns:1fr 1fr;gap:22px;margin-bottom:30px;}
    @media (max-width:1100px){.charts-grid{grid-template-columns:1fr;}}
    .chart-card{background:white;border:2px solid #e5e7eb;border-radius:14px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.05);}
    .chart-card h4{color:#1e3a8a;font-weight:800;margin-bottom:14px;font-size:15px;}
    .chart-card .ch-wrap{position:relative;height:280px;}
    .chart-card.wide{grid-column:1/-1;}
    .filter-badge{display:none;background:#4338ca;color:white;padding:8px 16px;border-radius:20px;font-size:13px;font-weight:700;margin-bottom:16px;align-items:center;gap:10px;}
    .filter-badge button{background:rgba(255,255,255,.25);border:none;color:white;border-radius:14px;padding:3px 10px;font-weight:700;cursor:pointer;font-size:12px;}
    .drill-row{background:#eef2ff;border:2px solid #6366f1;border-radius:14px;padding:16px 20px;margin-bottom:20px;display:flex;gap:15px;align-items:flex-end;flex-wrap:wrap;justify-content:space-between;}
    .chips{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px;}
    .chip{display:inline-flex;align-items:center;gap:8px;background:#4338ca;color:white;padding:6px 12px;border-radius:20px;font-size:12px;font-weight:700;}
    .chip button{background:rgba(255,255,255,.25);border:none;color:white;border-radius:12px;padding:2px 8px;font-weight:700;cursor:pointer;font-size:11px;}
    .chip.clear-all{background:#64748b;cursor:pointer;}
    .lb-wrap{background:white;border-radius:14px;border:2px solid #e5e7eb;overflow-x:auto;max-height:520px;overflow-y:auto;box-shadow:0 4px 6px rgba(0,0,0,.05);}
    table.lb{width:100%;border-collapse:collapse;font-size:13px;min-width:900px;}
    table.lb thead{background:linear-gradient(135deg,#1e40af,#1e3a8a);color:white;position:sticky;top:0;}
    table.lb th{padding:13px;text-align:left;font-weight:800;font-size:11px;text-transform:uppercase;white-space:nowrap;}
    table.lb td{padding:11px 13px;border-bottom:1px solid #e5e7eb;font-size:13px;font-weight:500;white-space:nowrap;}
    table.lb tbody tr:hover{background:#f8fafc;cursor:pointer;}
    table.lb tbody tr:nth-child(even){background:#fafafa;}
    .no-data{text-align:center;padding:60px 20px;color:#64748b;font-size:15px;}
  </style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <div>
      <h1><i class="fa fa-line-chart"></i> Payroll Overview</h1>
      <p>Managing Director Dashboard &nbsp;|&nbsp; All payroll data at a glance &nbsp;|&nbsp; Click any chart segment to drill down</p>
    </div>
    <a href="hr-payroll-fixed.php" class="btn-back"><i class="fa fa-arrow-left"></i> Payroll List</a>
  </div>

  <div class="content">
    <!-- STATS -->
    <div class="stats">
      <div class="sc blue"><div class="lbl">Period</div><div class="val" style="font-size:15px;"><?php echo htmlspecialchars($period_label); ?></div></div>
      <div class="sc purple"><div class="lbl"><i class="fa fa-users"></i> Employees Paid</div><div class="val"><?php echo $total_employees; ?></div></div>
      <div class="sc green"><div class="lbl"><i class="fa fa-money"></i> Total Net Paid</div><div class="val">₹<?php echo number_format($total_net); ?></div></div>
      <div class="sc blue"><div class="lbl"><i class="fa fa-briefcase"></i> Total Gross</div><div class="val">₹<?php echo number_format($total_gross); ?></div></div>
      <div class="sc teal"><div class="lbl"><i class="fa fa-star"></i> Total OT</div><div class="val">₹<?php echo number_format($total_ot); ?></div></div>
      <div class="sc red"><div class="lbl"><i class="fa fa-minus-circle"></i> Total Deductions</div><div class="val">₹<?php echo number_format($total_deductions); ?></div></div>
      <div class="sc orange"><div class="lbl"><i class="fa fa-calculator"></i> Avg Net / Record</div><div class="val">₹<?php echo number_format($avg_net); ?></div></div>
    </div>

    <!-- FILTERS -->
    <div class="ctrl">
      <form method="POST" style="display:flex;gap:15px;align-items:flex-end;flex-wrap:wrap;">
        <div><label>From</label><input type="date" name="filter_from" class="fc" value="<?php echo htmlspecialchars($filter_from); ?>"></div>
        <div><label>To</label><input type="date" name="filter_to" class="fc" value="<?php echo htmlspecialchars($filter_to); ?>"></div>
        <div>
          <label><i class="fa fa-building"></i> Company / Entity</label>
          <select name="filter_company" class="fc" style="min-width:240px;">
            <option value="">— All Companies —</option>
            <?php foreach($companies_list as $cn): ?>
            <option value="<?php echo htmlspecialchars($cn); ?>" <?php echo ($filter_company === $cn) ? 'selected' : ''; ?>><?php echo htmlspecialchars($cn); ?></option>
            <?php endforeach; ?>
            <option value="(No Company Set)" <?php echo ($filter_company === '(No Company Set)') ? 'selected' : ''; ?>>(No Company Set)</option>
          </select>
        </div>
        <button type="submit" name="apply_filter" class="btn btn-p"><i class="fa fa-filter"></i> Apply</button>
      </form>
    </div>

    <?php if($total_records === 0): ?>
      <div class="no-data"><i class="fa fa-inbox" style="font-size:40px;display:block;margin-bottom:12px;"></i> No payroll records found for this period.</div>
    <?php else: ?>

    <!-- DRILL FILTERS (client-side, apply instantly to charts + leaderboard below) -->
    <div class="drill-row">
      <div><label>Employee</label>
        <select id="pvFilterEmployee" class="fc" style="min-width:210px;" onchange="pvApplyFilter('employee', this.value)">
          <option value="">— All Employees —</option>
        </select>
      </div>
      <div><label>Department</label>
        <select id="pvFilterDept" class="fc" style="min-width:180px;" onchange="pvApplyFilter('department', this.value)">
          <option value="">— All Departments —</option>
        </select>
      </div>
      <div><label>Position</label>
        <select id="pvFilterPosition" class="fc" style="min-width:180px;" onchange="pvApplyFilter('position', this.value)">
          <option value="">— All Positions —</option>
        </select>
      </div>
      <button type="button" class="btn btn-d" onclick="pvClearAllFilters()"><i class="fa fa-times"></i> Clear Filters</button>
    </div>

    <div id="pvChips" class="chips"></div>

    <!-- CHARTS -->
    <div class="charts-grid">
      <div class="chart-card">
        <h4><i class="fa fa-building"></i> Net Salary by Company</h4>
        <div class="ch-wrap"><canvas id="pvChartCompany"></canvas></div>
      </div>
      <div class="chart-card">
        <h4><i class="fa fa-sitemap"></i> Net Salary by Department</h4>
        <div class="ch-wrap"><canvas id="pvChartDept"></canvas></div>
      </div>
      <div class="chart-card">
        <h4><i class="fa fa-id-badge"></i> Net Salary by Position</h4>
        <div class="ch-wrap"><canvas id="pvChartPosition"></canvas></div>
      </div>
      <div class="chart-card">
        <h4><i class="fa fa-line-chart"></i> Monthly Trend (Net / Gross / OT)</h4>
        <div class="ch-wrap"><canvas id="pvChartTrend"></canvas></div>
      </div>
    </div>

    <!-- EMPLOYEE LEADERBOARD -->
    <div class="chart-card wide" style="margin-bottom:30px;">
      <h4><i class="fa fa-trophy"></i> Employee Leaderboard <span id="pvLbCount" style="font-weight:600;font-size:12px;color:#64748b;"></span></h4>
      <div class="lb-wrap">
        <table class="lb">
          <thead>
            <tr>
              <th>Employee</th><th>Company</th><th>Department</th><th>Position</th>
              <th>Records</th><th>Present Days</th><th>Total Gross</th><th>Total OT</th><th>Total Deductions</th><th>Total Net</th>
            </tr>
          </thead>
          <tbody id="pvLbBody"></tbody>
        </table>
      </div>
    </div>

    <?php endif; ?>
  </div>
</div>

<?php if($total_records > 0): ?>
<script>
const pvRecords = <?php echo $records_json; ?>;

// Unified filter state — populated either from the Employee/Department/Position
// dropdowns above, or from clicking a chart bar/point (both write here, so
// everything — charts + leaderboard — stays in sync from one source of truth).
let pvFilters = { department: '', position: '', employee: '', month: '', company: '' };
let pvCompanyChart, pvDeptChart, pvPositionChart, pvTrendChart;

function pvFmtMoney(n){ return '₹' + Math.round(n).toLocaleString('en-IN'); }

function pvGroupSum(records, keyFn){
    const map = {};
    records.forEach(r => {
        const k = keyFn(r);
        if(!map[k]) map[k] = { net:0, gross:0, ot:0, emp:new Set() };
        map[k].net += r.net; map[k].gross += r.gross; map[k].ot += r.ot;
        map[k].emp.add(r.emp_code);
    });
    return map;
}

function pvFilteredRecords(){
    return pvRecords.filter(r =>
        (!pvFilters.department || r.department === pvFilters.department) &&
        (!pvFilters.position   || r.position   === pvFilters.position) &&
        (!pvFilters.employee   || r.employee   === pvFilters.employee) &&
        (!pvFilters.month      || r.month_label === pvFilters.month) &&
        (!pvFilters.company    || r.company    === pvFilters.company)
    );
}

function pvApplyFilter(type, value){
    pvFilters[type] = value;
    // keep the dropdowns in sync when a chart click set the filter
    if(type === 'department') document.getElementById('pvFilterDept').value = value;
    if(type === 'position')   document.getElementById('pvFilterPosition').value = value;
    if(type === 'employee')   document.getElementById('pvFilterEmployee').value = value;
    pvRenderAll();
}

function pvClearOneFilter(type){
    pvApplyFilter(type, '');
}

function pvClearAllFilters(){
    pvFilters = { department: '', position: '', employee: '', month: '', company: '' };
    document.getElementById('pvFilterDept').value = '';
    document.getElementById('pvFilterPosition').value = '';
    document.getElementById('pvFilterEmployee').value = '';
    pvRenderAll();
}

function pvRenderAll(){
    pvRefreshCharts();
    pvRenderLeaderboard();
    pvRenderChips();
}

function pvRenderChips(){
    const labels = { department: 'Department', position: 'Position', employee: 'Employee', month: 'Month', company: 'Company' };
    const active = Object.keys(pvFilters).filter(k => pvFilters[k]);
    const box = document.getElementById('pvChips');
    if(active.length === 0){ box.innerHTML = ''; return; }
    box.innerHTML = active.map(k =>
        `<span class="chip">${labels[k]}: ${pvFilters[k]} <button onclick="pvClearOneFilter('${k}')">✕</button></span>`
    ).join('') + (active.length > 1 ? `<span class="chip clear-all" onclick="pvClearAllFilters()">Clear All ✕</span>` : '');
}

function pvPopulateDropdowns(){
    const fill = (id, values) => {
        const sel = document.getElementById(id);
        values.forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
    };
    fill('pvFilterEmployee', [...new Set(pvRecords.map(r => r.employee))].sort());
    fill('pvFilterDept',     [...new Set(pvRecords.map(r => r.department))].sort());
    fill('pvFilterPosition', [...new Set(pvRecords.map(r => r.position))].sort());
}

function pvRenderLeaderboard(){
    const recs = pvFilteredRecords();
    const byEmp = {};
    recs.forEach(r => {
        if(!byEmp[r.emp_code]) byEmp[r.emp_code] = {
            employee:r.employee, company:r.company, department:r.department, position:r.position,
            records:0, present_days:0, gross:0, ot:0, deductions:0, net:0
        };
        const e = byEmp[r.emp_code];
        e.records++; e.present_days += r.present_days; e.gross += r.gross;
        e.ot += r.ot; e.deductions += r.deductions; e.net += r.net;
    });
    const list = Object.values(byEmp).sort((a,b) => b.net - a.net);
    document.getElementById('pvLbCount').textContent = '(' + list.length + ' employee' + (list.length===1?'':'s') + ')';
    const body = document.getElementById('pvLbBody');
    body.innerHTML = list.map(e => `
        <tr>
          <td style="font-weight:700;color:#1e40af;">${e.employee}</td>
          <td>${e.company}</td>
          <td>${e.department}</td>
          <td>${e.position}</td>
          <td style="text-align:center;">${e.records}</td>
          <td style="text-align:center;">${e.present_days}</td>
          <td>${pvFmtMoney(e.gross)}</td>
          <td style="color:#d97706;">${pvFmtMoney(e.ot)}</td>
          <td style="color:#dc2626;">${pvFmtMoney(e.deductions)}</td>
          <td style="font-weight:900;color:#059669;">${pvFmtMoney(e.net)}</td>
        </tr>`).join('');
}

function pvBarData(groupKeyFn){
    const grouped = pvGroupSum(pvFilteredRecords(), groupKeyFn);
    const labels = Object.keys(grouped).sort((a,b) => grouped[b].net - grouped[a].net);
    return { labels: labels, data: labels.map(l => grouped[l].net) };
}

function pvMakeBarChart(canvasId, groupKeyFn, drillType, colorBase){
    const d = pvBarData(groupKeyFn);
    const ctx = document.getElementById(canvasId).getContext('2d');
    const chart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: d.labels,
            datasets: [{
                label: 'Net Salary',
                data: d.data,
                backgroundColor: colorBase,
                borderRadius: 6
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            plugins: {
                legend: { display: false },
                tooltip: { callbacks: { label: (c) => pvFmtMoney(c.parsed.y) } }
            },
            scales: {
                x: { grid: { display: false } },
                y: { beginAtZero: true, ticks: { callback: (v) => '₹' + (v/1000) + 'k' } }
            },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    pvApplyFilter(drillType, chart.data.labels[idx]);
                }
            }
        }
    });
    chart.pvGroupKeyFn = groupKeyFn;
    return chart;
}

function pvTrendData(){
    const grouped = pvGroupSum(pvFilteredRecords(), r => r.month_label + '|' + r.year + '|' + String(r.month).padStart(2,'0'));
    const keys = Object.keys(grouped).sort((a,b) => a.split('|')[1]+a.split('|')[2] > b.split('|')[1]+b.split('|')[2] ? 1 : -1);
    return {
        labels: keys.map(k => k.split('|')[0]),
        net: keys.map(k => grouped[k].net),
        gross: keys.map(k => grouped[k].gross),
        ot: keys.map(k => grouped[k].ot)
    };
}

function pvMakeTrendChart(){
    const t = pvTrendData();
    const ctx = document.getElementById('pvChartTrend').getContext('2d');
    const chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: t.labels,
            datasets: [
                { label: 'Net Salary', data: t.net, borderColor: '#059669', backgroundColor: 'rgba(5,150,105,.1)', tension: .3, fill: true },
                { label: 'Gross Pay', data: t.gross, borderColor: '#2563eb', backgroundColor: 'rgba(37,99,235,.05)', tension: .3, fill: true },
                { label: 'OT Amount', data: t.ot, borderColor: '#d97706', backgroundColor: 'rgba(217,119,6,.05)', tension: .3, fill: true }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'nearest', intersect: true },
            plugins: { tooltip: { callbacks: { label: (c) => c.dataset.label + ': ' + pvFmtMoney(c.parsed.y) } } },
            scales: { y: { beginAtZero: true, ticks: { callback: (v) => '₹' + (v/1000) + 'k' } } },
            onClick: (evt) => {
                const points = chart.getElementsAtEventForMode(evt, 'nearest', {intersect:true}, true);
                if(points.length){
                    const idx = points[0].index;
                    pvApplyFilter('month', chart.data.labels[idx]);
                }
            }
        }
    });
    return chart;
}

function pvRefreshCharts(){
    const c = pvBarData(pvCompanyChart.pvGroupKeyFn);
    pvCompanyChart.data.labels = c.labels; pvCompanyChart.data.datasets[0].data = c.data; pvCompanyChart.update();

    const dpt = pvBarData(pvDeptChart.pvGroupKeyFn);
    pvDeptChart.data.labels = dpt.labels; pvDeptChart.data.datasets[0].data = dpt.data; pvDeptChart.update();

    const pos = pvBarData(pvPositionChart.pvGroupKeyFn);
    pvPositionChart.data.labels = pos.labels; pvPositionChart.data.datasets[0].data = pos.data; pvPositionChart.update();

    const t = pvTrendData();
    pvTrendChart.data.labels = t.labels;
    pvTrendChart.data.datasets[0].data = t.net;
    pvTrendChart.data.datasets[1].data = t.gross;
    pvTrendChart.data.datasets[2].data = t.ot;
    pvTrendChart.update();
}

document.addEventListener('DOMContentLoaded', function(){
    pvPopulateDropdowns();
    pvCompanyChart  = pvMakeBarChart('pvChartCompany', r => r.company, 'company', '#6366f1');
    pvDeptChart     = pvMakeBarChart('pvChartDept', r => r.department, 'department', '#3b82f6');
    pvPositionChart = pvMakeBarChart('pvChartPosition', r => r.position, 'position', '#8b5cf6');
    pvTrendChart    = pvMakeTrendChart();
    pvRenderLeaderboard();
});
</script>
<?php endif; ?>
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