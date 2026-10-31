<?php
// ============================================================================
// PAYROLL SYSTEM - FINAL CLEAN VERSION
// ============================================================================
// LOGIC:
//   Base = 26 days ALWAYS (fixed average for any month)
//   Per day = Gross / 26
//
//   Count ALL attendance (Mon to Sun, any day)
//   present_days = total check-ins this month + HR added days + holidays
//
//   If present_days < 26  → deduct absent days
//   If present_days = 26  → full salary
//   If present_days > 26  → full salary + OT for extra days
//
//   OT days  = MAX(0, present_days - 26)
//   OT amount = OT days × per_day  (auto calculated)
//
// NO week_off_day column needed — works for everyone automatically
// HR can add extra days in form for short months like February
// ============================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
session_start();

try {
    require_once('database.php');
    require_once('library.php');
    require_once('funciones.php');
} catch(Exception $e) { die("Error: " . $e->getMessage()); }

date_default_timezone_set('Asia/Kolkata');
if(!isset($_SESSION['user_name'])) { header("Location: login.php"); exit; }
if(!isset($dbConn) || !$dbConn)    die("Database connection failed.");

// ============================================================================
// AUTHORIZATION
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
$is_keerti  = (stripos($emp_name_db,'keerti') !==false || stripos($currentUserName,'keerti') !==false);
$is_md      = (stripos($emp_position,'managing director')!==false || stripos($emp_position,'ceo')!==false);
$is_hr      = (stripos($emp_dept,'Human Resources')!==false || stripos($emp_dept,'Management')!==false);
$isAdmin    = $is_abishek;

if(!($is_abishek || $is_keerti || $is_md || $is_hr))
    die("<div style='font-family:Arial;text-align:center;margin-top:100px;'><h2>Access Denied</h2><p><a href='raise-a-ticket.php'>Back</a></p></div>");

// Create override table if missing
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_attendance_overrides (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    attendance_date DATE NOT NULL,
    status ENUM('present','absent','holiday','leave','half_day') DEFAULT 'present',
    reason TEXT, created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_emp_date (employee_id, attendance_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add per_day_salary column if missing
$c = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'per_day_salary'");
if(!$c || mysqli_num_rows($c)==0)
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN per_day_salary DECIMAL(10,2) DEFAULT 0.00 AFTER net_salary");

// ============================================================================
// CORE SALARY CALCULATION
// ============================================================================
// RULES:
//   per_day       = gross / 26
//   normal_days   = MIN(total_present, 26)   → salary
//   ot_days       = MAX(0, total_present - 26) → OT bonus
//   absent_days   = MAX(0, 26 - total_present)
//   net           = (normal_days × per_day) + (ot_days × per_day) - deductions
//
// total_present = ALL attendance days (Mon-Sun) + holidays + HR added days
// ============================================================================
function calcSalary($gross, $total_present) {
    if($gross <= 0) return ['per_day'=>0,'normal_days'=>0,'ot_days'=>0,'absent_days'=>26,'earned'=>0,'ot_amount'=>0,'net'=>0];

    $per_day     = round($gross / 26, 4);
    $normal_days = min($total_present, 26);
    $ot_days     = max(0, $total_present - 26);
    $absent_days = max(0, 26 - $normal_days);

    $earned    = round($per_day * $normal_days, 2);
    $ot_amount = round($per_day * $ot_days, 2);

    // Employee-favorable rounding
    $net     = $earned + $ot_amount;
    $decimal = $net - floor($net);
    $net     = ($decimal >= 0.50) ? ceil($net) : floor($net);

    return [
        'per_day'     => round($per_day, 2),
        'normal_days' => $normal_days,
        'ot_days'     => $ot_days,
        'absent_days' => $absent_days,
        'earned'      => $earned,
        'ot_amount'   => $ot_amount,
        'net'         => $net
    ];
}

// ============================================================================
// GET TOTAL ATTENDANCE DAYS FOR AN EMPLOYEE IN A MONTH
// Counts ALL days (Mon-Sun) — no day is excluded
// ============================================================================
function getTotalAttendanceDays($dbConn, $emp_db_id, $emp_code, $month, $year) {
    $start = "$year-" . str_pad($month,2,'0',STR_PAD_LEFT) . "-01";
    $end   = "$year-" . str_pad($month,2,'0',STR_PAD_LEFT) . "-" . str_pad(cal_days_in_month(CAL_GREGORIAN,$month,$year),2,'0',STR_PAD_LEFT);

    // Biometric check-ins (any day including Sunday)
    $q = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
        WHERE employee_id='$emp_code' AND date BETWEEN '$start' AND '$end'
        AND status IN ('present','late','half_day')");
    $bio_days = intval(mysqli_fetch_assoc($q)['cnt']);

    // Manual overrides — present/holiday/leave = add days, absent = subtract
    $oq = mysqli_query($dbConn, "SELECT attendance_date, status FROM hr_attendance_overrides
        WHERE employee_id=$emp_db_id AND attendance_date BETWEEN '$start' AND '$end'");

    $ov_present = 0;
    $ov_absent  = 0;
    $ov_dates   = [];

    while($ov = mysqli_fetch_assoc($oq)) {
        $ov_dates[] = $ov['attendance_date'];
        if(in_array($ov['status'], ['present','holiday','leave'])) $ov_present++;
        elseif($ov['status'] == 'absent')                          $ov_absent++;
    }

    // Remove biometric days that have overrides (to avoid double counting)
    if(!empty($ov_dates)) {
        $ds = "'" . implode("','", $ov_dates) . "'";
        $q  = mysqli_query($dbConn, "SELECT COUNT(DISTINCT date) as cnt FROM hr_attendance
            WHERE employee_id='$emp_code' AND date IN ($ds) AND status IN ('present','late','half_day')");
        $bio_days -= intval(mysqli_fetch_assoc($q)['cnt']);
    }

    $total = max(0, $bio_days + $ov_present - $ov_absent);

    return [
        'total'       => $total,
        'bio_days'    => max(0, $bio_days),
        'ov_present'  => $ov_present,
        'ov_absent'   => $ov_absent,
        'has_overrides' => count($ov_dates) > 0
    ];
}

// ============================================================================
// DOWNLOAD PAYSLIP
// ============================================================================
if(isset($_GET['download_payslip'])) {
    $pid    = intval($_GET['download_payslip']);
    $result = mysqli_query($dbConn, "SELECT p.*, e.name, e.employee_id as emp_code,
        e.company_name, e.employee_type,
        COALESCE(e.position,'N/A') as designation,
        COALESCE(e.department,'N/A') as department
        FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id
        WHERE p.id=$pid LIMIT 1");
    if(!$result || mysqli_num_rows($result)==0) die("Not found");
    $d = mysqli_fetch_assoc($result);

    $company_name = $d['company_name'] ?: 'Abra E Logistics Private Limited';
    $logo_base64  = '';
    $lq = mysqli_query($dbConn,"SELECT logo_path FROM hr_companies WHERE company_name='$company_name' LIMIT 1");
    if($lq && mysqli_num_rows($lq)>0) {
        $lp = mysqli_fetch_assoc($lq)['logo_path'];
        if(!empty($lp) && file_exists($lp))
            $logo_base64 = 'data:image/'.pathinfo($lp,PATHINFO_EXTENSION).';base64,'.base64_encode(file_get_contents($lp));
    }

    $month_name   = date("F", mktime(0,0,0,$d['pay_month'],10));
    $year         = $d['pay_year'];
    $pay_date_fmt = date("d-M-Y", mktime(0,0,0,$d['pay_month']+1,10,$d['pay_year']));
    $per_day      = floatval($d['per_day_salary']) ?: round(floatval($d['gross_pay'])/26, 2);
    $ot_value     = floatval($d['ot_amount'] ?? $d['ot']);
    $ot_days      = intval($d['weekends_worked'] ?? 0); // stored as ot_days
    $gross        = floatval($d['gross_pay']);
    $absent_deduct = round($per_day * intval($d['absent_days']), 2);
    $total_deduct  = floatval($d['esi']) + floatval($d['pt']) + floatval($d['tds']) + $absent_deduct + floatval($d['advance_salary']) + floatval($d['penalty']);
    $pf_emp       = floatval($d['pf']);
    if($pf_emp==0 && stripos($d['employee_type'],'Permanent')!==false) $pf_emp=round(floatval($d['basic_salary'])*0.12,2);

    ob_end_clean();
    echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Payslip - '.htmlspecialchars($d['name']).'</title>
    <style>
    @page{margin:15mm 10mm;size:A4;}
    @media print{*{-webkit-print-color-adjust:exact!important;}html,body{margin:0;padding:0;background:white;}.no-print{display:none!important;}}
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:Arial,sans-serif;background:#f5f5f5;padding:20px;}
    .ps{max-width:750px;margin:0 auto;background:white;border:3px solid #1e3a8a;box-shadow:0 0 20px rgba(0,0,0,.1);}
    .hd{padding:20px 30px 12px;border-bottom:3px solid #1e3a8a;text-align:center;}
    .logo{min-height:120px;display:flex;align-items:center;justify-content:center;margin-bottom:10px;}
    .logo img{max-height:120px;max-width:600px;object-fit:contain;}
    .cn{font-size:18px;font-weight:bold;color:#1e3a8a;margin-bottom:8px;}
    .hb{background:#1e3a8a;color:white;padding:7px 12px;}
    .hb .t{font-size:14px;font-weight:bold;letter-spacing:2px;}
    .hb .p{font-size:11px;}
    .es{padding:8px 30px;background:#f8f9fa;border-bottom:2px solid #dee2e6;}
    .it{width:100%;border-collapse:collapse;}
    .it td{padding:4px 6px;font-size:10px;}
    .it td:nth-child(odd){color:#495057;width:20%;}
    .it td:nth-child(even){color:#212529;font-weight:bold;width:30%;}
    .ss{padding:8px 30px;}
    .sg{display:grid;grid-template-columns:1fr 1fr;gap:15px;}
    .sc h3{background:#1e3a8a;color:white;padding:6px 10px;font-size:10px;font-weight:bold;margin-bottom:8px;text-transform:uppercase;}
    .st{width:100%;border-collapse:collapse;border:1px solid #dee2e6;}
    .st tr{border-bottom:1px solid #dee2e6;}
    .st td{padding:5px 8px;font-size:10px;}
    .st td:last-child{text-align:right;font-weight:bold;font-family:"Courier New",monospace;}
    .tr{background:#1e3a8a!important;}.tr td{color:white!important;font-weight:bold!important;font-size:11px!important;}
    .cr{background:#059669!important;}.cr td{color:white!important;font-weight:bold!important;font-size:11px!important;}
    .or{background:#fffbeb!important;}.or td{color:#92400e!important;font-weight:bold!important;}
    .at{padding:0 30px 8px;}
    .at h3{background:#1e3a8a;color:white;padding:6px 10px;font-size:10px;font-weight:bold;margin-bottom:8px;text-transform:uppercase;}
    .att{width:100%;border-collapse:collapse;border:1px solid #dee2e6;}
    .att td{padding:7px;font-size:10px;border-right:1px solid #dee2e6;text-align:center;}
    .lc{background:#f8f9fa;color:#495057;}
    .vc{background:white;color:#212529;font-weight:bold;}
    .vc.ot{color:#d97706!important;background:#fffbeb!important;}
    .ns{background:#1e3a8a;color:white;padding:10px 30px;text-align:center;border-top:2px solid #1e40af;}
    .nl{font-size:11px;font-weight:bold;letter-spacing:2px;margin-bottom:3px;}
    .na{font-size:22px;font-weight:bold;font-family:"Courier New",monospace;}
    .sg2{padding:10px 30px 8px;display:flex;justify-content:space-between;border-top:2px solid #dee2e6;}
    .sb{width:45%;}
    .sn{font-family:"Brush Script MT",cursive;font-size:18px;color:#1e3a8a;text-align:center;}
    .sl{border-top:2px solid #212529;margin:3px 0;}
    .slb{font-size:8px;color:#495057;font-weight:bold;text-transform:uppercase;text-align:center;}
    .st2{font-size:7px;color:#6c757d;font-style:italic;text-align:center;}
    .pb{text-align:center;padding:12px;}
    .pb button{background:#1e3a8a;color:white;padding:10px 30px;border:none;border-radius:5px;font-size:13px;font-weight:600;cursor:pointer;}
    </style></head><body>
    <div class="ps">
    <div class="hd">';
    if($logo_base64) echo '<div class="logo"><img src="'.$logo_base64.'" alt="Logo"></div>';
    echo '<div class="cn">'.strtoupper(htmlspecialchars($company_name)).'</div>
    <div class="hb"><div class="t">SALARY SLIP</div><div class="p">Month: '.$month_name.' '.$year.'</div></div></div>
    <div class="es"><table class="it">
    <tr><td>Employee Name:</td><td>'.strtoupper(htmlspecialchars($d['name'])).'</td><td>Employee ID:</td><td>'.htmlspecialchars($d['emp_code']).'</td></tr>
    <tr><td>Designation:</td><td>'.htmlspecialchars($d['designation']).'</td><td>Department:</td><td>'.htmlspecialchars($d['department']).'</td></tr>
    <tr><td>Pay Date:</td><td>'.$pay_date_fmt.'</td><td>Pay Period:</td><td>'.$month_name.' '.$year.'</td></tr>
    </table></div>
    <div class="ss"><div class="sg">
    <div class="sc"><h3>Earnings</h3><table class="st">
    <tr><td>Basic Salary</td><td>&#8377; '.number_format($d['basic_salary'],2).'</td></tr>
    <tr><td>HRA</td><td>&#8377; '.number_format($d['hra'],2).'</td></tr>
    <tr><td>Conveyance</td><td>&#8377; '.number_format($d['conveyance'],2).'</td></tr>
    <tr><td>Special Allowance</td><td>&#8377; '.number_format($d['special_allowance'],2).'</td></tr>
    <tr class="tr"><td>GROSS SALARY (26 Day Base)</td><td>&#8377; '.number_format($gross,2).'</td></tr>';
    if($ot_value>0) echo '<tr class="or"><td>OT Amount ('.$ot_days.' extra days × &#8377;'.number_format($per_day,2).')</td><td>&#8377; '.number_format($ot_value,2).'</td></tr>';
    if(floatval($d['arrears'])>0) echo '<tr><td>Arrears</td><td>&#8377; '.number_format($d['arrears'],2).'</td></tr>';
    if(floatval($d['overtime'])>0) echo '<tr><td>Overtime</td><td>&#8377; '.number_format($d['overtime'],2).'</td></tr>';
    if(floatval($d['incentives'])>0) echo '<tr><td>Incentives</td><td>&#8377; '.number_format($d['incentives'],2).'</td></tr>';
    if($pf_emp>0) {
        echo '<tr><td>PF Employer</td><td>&#8377; '.number_format($pf_emp,2).'</td></tr>';
        echo '<tr class="cr"><td>TOTAL CTC</td><td>&#8377; '.number_format($d['total_ctc'],2).'</td></tr>';
    }
    echo '</table></div>
    <div class="sc"><h3>Deductions</h3><table class="st">';
    if(floatval($d['pf'])>0)             echo '<tr><td>Provident Fund</td><td>&#8377; '.number_format($d['pf'],2).'</td></tr>';
    if(floatval($d['esi'])>0)            echo '<tr><td>ESI</td><td>&#8377; '.number_format($d['esi'],2).'</td></tr>';
    if(floatval($d['pt'])>0)             echo '<tr><td>Professional Tax</td><td>&#8377; '.number_format($d['pt'],2).'</td></tr>';
    if(floatval($d['tds'])>0)            echo '<tr><td>TDS</td><td>&#8377; '.number_format($d['tds'],2).'</td></tr>';
    if($absent_deduct>0)                 echo '<tr><td>Absent Deduction ('.$d['absent_days'].' days)</td><td>&#8377; '.number_format($absent_deduct,2).'</td></tr>';
    if(floatval($d['advance_salary'])>0) echo '<tr><td>Advance Salary</td><td>&#8377; '.number_format($d['advance_salary'],2).'</td></tr>';
    if(floatval($d['penalty'])>0)        echo '<tr><td>Penalty</td><td>&#8377; '.number_format($d['penalty'],2).'</td></tr>';
    if($total_deduct>0) echo '<tr class="tr"><td>TOTAL DEDUCTIONS</td><td>&#8377; '.number_format($total_deduct,2).'</td></tr>';
    else                echo '<tr><td colspan="2" style="text-align:center;padding:15px;font-style:italic;color:#6c757d">No Deductions</td></tr>';
    echo '</table></div></div></div>
    <div class="at"><h3>Attendance Summary (Base: 26 Days)</h3>
    <table class="att">
    <tr>
      <td class="lc">Days Present (All Days)</td>
      <td class="lc">Normal Days (Max 26)</td>
      <td class="lc">Absent Days</td>
      <td class="lc">OT Days (Beyond 26)</td>
      <td class="lc">OT Amount</td>
    </tr>
    <tr>
      <td class="vc"><strong>'.($d['present_days'] + $ot_days).'</strong></td>
      <td class="vc"><strong>'.$d['present_days'].'</strong></td>
      <td class="vc"><strong>'.$d['absent_days'].'</strong></td>
      <td class="vc ot"><strong>'.$ot_days.'</strong></td>
      <td class="vc ot">&#8377; '.number_format($ot_value,2).'</td>
    </tr>
    </table></div>
    <div class="ns"><div class="nl">NET SALARY PAYABLE</div><div class="na">&#8377; '.number_format($d['net_salary'],2).'</div></div>
    <div class="sg2">
    <div class="sb"><div class="sn">'.htmlspecialchars($d['name']).'</div><div class="sl"></div><div class="slb">Employee Signature</div></div>
    <div class="sb"><div class="sn">Abishek Veeraswamy</div><div class="sl"></div><div class="slb">Authorized Signatory</div><div class="st2">Managing Director</div></div>
    </div></div>
    <div class="pb no-print"><button onclick="window.print()">PRINT / SAVE AS PDF</button></div>
    </body></html>';
    exit;
}

// ============================================================================
// BULK MARK HOLIDAY
// ============================================================================
if(isset($_POST['bulk_mark_holiday'])) {
    $emp_ids   = $_POST['employee_ids'] ?? [];
    $from_date = mysqli_real_escape_string($dbConn, $_POST['from_date']);
    $to_date   = mysqli_real_escape_string($dbConn, $_POST['to_date']);
    $status    = mysqli_real_escape_string($dbConn, $_POST['mark_status']);
    $reason    = mysqli_real_escape_string($dbConn, $_POST['mark_reason']);
    if(empty($emp_ids)) { $_SESSION['msg'] = "❌ Select at least one employee"; }
    else {
        $cnt      = 0;
        $interval = (new DateTime($to_date))->diff(new DateTime($from_date))->days + 1;
        foreach($emp_ids as $eid) {
            $eid = intval($eid);
            for($i=0; $i<$interval; $i++) {
                $dt  = date('Y-m-d', strtotime("$from_date +$i days"));
                $chk = mysqli_query($dbConn,"SELECT id FROM hr_attendance_overrides WHERE employee_id=$eid AND attendance_date='$dt'");
                if(mysqli_num_rows($chk)>0)
                    mysqli_query($dbConn,"UPDATE hr_attendance_overrides SET status='$status',reason='$reason',created_by='$currentUserName' WHERE employee_id=$eid AND attendance_date='$dt'");
                else
                    mysqli_query($dbConn,"INSERT INTO hr_attendance_overrides (employee_id,attendance_date,status,reason,created_by) VALUES ($eid,'$dt','$status','$reason','$currentUserName')");
                $cnt++;
            }
        }
        $_SESSION['msg'] = "✓ Marked $cnt days for ".count($emp_ids)." employee(s) as ".ucfirst($status).". Regenerate payroll to update.";
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// DELETE OVERRIDE
// ============================================================================
if(isset($_POST['delete_override'])) {
    mysqli_query($dbConn,"DELETE FROM hr_attendance_overrides WHERE id=".intval($_POST['override_id']));
    $_SESSION['msg'] = "✓ Override removed";
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// DELETE PAYROLL
// ============================================================================
if(isset($_POST['delete_payroll'])) {
    $pid = intval($_POST['payroll_id']);
    $r   = mysqli_query($dbConn,"SELECT e.name,p.pay_month,p.pay_year FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE p.id=$pid LIMIT 1");
    if($r && mysqli_num_rows($r)>0) {
        $rec = mysqli_fetch_assoc($r);
        if(mysqli_query($dbConn,"DELETE FROM hr_payroll WHERE id=$pid"))
            $_SESSION['msg'] = "✓ Deleted for <strong>{$rec['name']}</strong> (".date("F",mktime(0,0,0,$rec['pay_month'],10))." {$rec['pay_year']})";
        else $_SESSION['msg'] = "Error: ".mysqli_error($dbConn);
    }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// EXPORT CSV
// ============================================================================
if(isset($_POST['export_csv'])) {
    $from = $_POST['export_from'];
    $to   = $_POST['export_to'];
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=Payroll_'.$from.'_to_'.$to.'.csv');
    $out = fopen('php://output','w');
    fputcsv($out,['Month','Year','Emp ID','Name','Basic','HRA','Conv','Special','Gross','Per Day','Present Days','Absent Days','OT Days','OT Amount','Arrears','Overtime','Incentives','PF','Total CTC','Advance','Penalty','Net Salary','Pay Date']);
    $res = mysqli_query($dbConn,"SELECT p.*,e.name,e.employee_id as ec FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$from' AND '$to' AND e.status='active' ORDER BY p.pay_year DESC,p.pay_month DESC,e.name");
    while($r=mysqli_fetch_assoc($res)) {
        $ot_val  = $r['ot_amount']??$r['ot'];
        $ot_days = $r['weekends_worked']??0;
        fputcsv($out,[date("F",mktime(0,0,0,$r['pay_month'],10)),$r['pay_year'],$r['ec'],$r['name'],
            $r['basic_salary'],$r['hra'],$r['conveyance'],$r['special_allowance'],$r['gross_pay'],
            isset($r['per_day_salary'])?$r['per_day_salary']:round($r['gross_pay']/26,2),
            $r['present_days'],$r['absent_days'],$ot_days,$ot_val,
            $r['arrears'],$r['overtime'],$r['incentives'],$r['pf'],$r['total_ctc'],
            $r['advance_salary'],$r['penalty'],$r['net_salary'],$r['pay_date']]);
    }
    fclose($out); exit;
}

// ============================================================================
// AUTO GENERATE PAYROLL
// ============================================================================
if(isset($_POST['auto_generate'])) {
    try {
        if(!empty($_POST['filter_from'])) {
            $dp = explode('-',$_POST['filter_from']);
            $yr = intval($dp[0]);
            $mo = intval($dp[1]);
        } else { $mo=date('n'); $yr=date('Y'); }

        $holidays         = intval($_POST['holidays_count']);
        $add_working_days = intval($_POST['add_working_days']);
        $total_days       = cal_days_in_month(CAL_GREGORIAN,$mo,$yr);
        $pay_date         = date('Y-m-d', mktime(0,0,0,$mo+1,10,$yr));

        $emps = mysqli_query($dbConn,"SELECT id,employee_id,name,salary,employee_type,COALESCE(pf,0) as employee_pf,hire_date FROM hr_employees WHERE status='active' ORDER BY name");
        $created=$updated=0; $errors=[];

        while($emp=mysqli_fetch_assoc($emps)) {
            try {
                $eid       = intval($emp['id']);
                $ecd       = mysqli_real_escape_string($dbConn,$emp['employee_id']);
                $enm       = mysqli_real_escape_string($dbConn,$emp['name']);
                $hire_date = $emp['hire_date'];

                // Skip if not joined yet
                $month_end = "$yr-".str_pad($mo,2,'0',STR_PAD_LEFT)."-".str_pad($total_days,2,'0',STR_PAD_LEFT);
                if(!empty($hire_date) && strtotime($hire_date) > strtotime($month_end)) continue;

                // Get TOTAL attendance days (ALL days including Sundays)
                $att = getTotalAttendanceDays($dbConn,$eid,$ecd,$mo,$yr);
                $total_present_bio = $att['total'];

                // Add holidays and HR extra days (only if employee was there full month)
                $month_start = "$yr-".str_pad($mo,2,'0',STR_PAD_LEFT)."-01";
                $eligible    = (empty($hire_date) || strtotime($hire_date) <= strtotime($month_end));
                $extra       = $eligible ? ($holidays + $add_working_days) : 0;

                // TOTAL PRESENT = biometric + overrides + holidays + HR added days
                $total_present = $total_present_bio + $extra;

                // CORE CALCULATION — simple and clean
                $gross  = floatval(str_replace(',','',$emp['salary']));
                $calc   = calcSalary($gross, $total_present);

                $per_day     = $calc['per_day'];
                $normal_days = $calc['normal_days'];  // capped at 26
                $ot_days     = $calc['ot_days'];       // beyond 26
                $absent_days = $calc['absent_days'];
                $auto_ot     = $calc['ot_amount'];     // auto calculated
                $earned      = $calc['earned'];

                // Salary structure breakdown
                $basic   = round($gross*0.40,2);
                $hra     = round($basic*0.50,2);
                $conv    = 3000;
                $special = max(0,round($gross-($basic+$hra+$conv),2));

                $pf = floatval($emp['employee_pf']);
                if($pf==0 && stripos($emp['employee_type'],'Permanent')!==false) $pf=round($basic*0.12,2);
                if($pf<0) $pf=0;

                $total_ctc = $gross + $pf + $auto_ot;
                $comment   = mysqli_real_escape_string($dbConn,"Auto | Total present: $total_present (bio: $total_present_bio + extra: $extra) | OT days: $ot_days | OT: ₹$auto_ot");

                // Check existing record
                $ex = mysqli_query($dbConn,"SELECT id,arrears,COALESCE(ot_amount,ot) as ot_val,overtime,incentives,advance_salary,penalty FROM hr_payroll WHERE employee_id=$eid AND pay_month=$mo AND pay_year=$yr LIMIT 1");

                if($ex && mysqli_num_rows($ex)>0) {
                    $exr   = mysqli_fetch_assoc($ex);
                    $exid  = $exr['id'];
                    $arr   = floatval($exr['arrears']);
                    $ovt   = floatval($exr['overtime']);
                    $inc   = floatval($exr['incentives']);
                    $adv   = floatval($exr['advance_salary']);
                    $pen   = floatval($exr['penalty']);

                    // Net = earned from normal days + auto OT + manual extras - deductions
                    $net       = max(0, $earned + $auto_ot + $arr + $ovt + $inc - $adv - $pen);
                    $total_ctc = $gross + $pf + $auto_ot + $arr + $ovt + $inc;

                    mysqli_query($dbConn,"UPDATE hr_payroll SET
                        basic_salary=$basic,hra=$hra,conveyance=$conv,special_allowance=$special,gross_pay=$gross,
                        pf=$pf,total_deduction=$pf,total_ctc=$total_ctc,
                        present_days=$normal_days,absent_days=$absent_days,working_days=26,
                        holidays_in_month=$holidays,
                        ot_amount=$auto_ot,weekends_worked=$ot_days,
                        net_salary=$net,per_day_salary=$per_day,amount=$net,
                        pay_date='$pay_date',comment='$comment'
                        WHERE id=$exid");
                    if(!mysqli_error($dbConn)) $updated++;
                    else $errors[] = "$enm: ".mysqli_error($dbConn);

                } else {
                    $net       = max(0, $earned + $auto_ot);
                    $total_ctc = $gross + $pf + $auto_ot;

                    mysqli_query($dbConn,"INSERT INTO hr_payroll (
                        employee_id,basic_salary,hra,conveyance,special_allowance,gross_pay,
                        arrears,ot,overtime,incentives,ot_amount,
                        pf,esi,pt,tds,total_deduction,total_ctc,
                        pay_date,pay_month,pay_year,amount,
                        present_days,absent_days,working_days,
                        weekends_in_month,holidays_in_month,weekends_worked,holidays_worked,
                        advance_salary,net_salary,per_day_salary,penalty,comment
                    ) VALUES (
                        $eid,$basic,$hra,$conv,$special,$gross,
                        0,0,0,0,$auto_ot,
                        $pf,0,0,0,$pf,$total_ctc,
                        '$pay_date',$mo,$yr,$net,
                        $normal_days,$absent_days,26,
                        0,$holidays,$ot_days,0,
                        0,$net,$per_day,0,'$comment'
                    )");
                    if(!mysqli_error($dbConn)) $created++;
                    else $errors[] = "$enm: ".mysqli_error($dbConn);
                }

            } catch(Exception $e) { $errors[]=$emp['name'].": ".$e->getMessage(); }
        }

        $mn  = date('F Y',mktime(0,0,0,$mo,1,$yr));
        $msg = "✓ Payroll generated for <strong>$mn</strong> | Holidays: $holidays | Add Days: $add_working_days | Created: $created | Updated: $updated";
        if(count($errors)) $msg .= "<br><small style='color:red'>".implode("; ",array_slice($errors,0,3))."</small>";
        $msg .= "<br><small style='color:#059669'>💡 All days counted (including Sundays). Days beyond 26 = auto OT.</small>";
        $_SESSION['msg'] = $msg;
        $_SESSION['payroll_filter_from']      = $_POST['filter_from'] ?? '';
        $_SESSION['payroll_filter_to']        = $_POST['filter_to']   ?? '';
        $_SESSION['payroll_add_working_days'] = $add_working_days;

    } catch(Exception $e) { $_SESSION['msg']="Error: ".$e->getMessage(); }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// UPDATE SINGLE PAYROLL
// ============================================================================
if(isset($_POST['update_payroll'])) {
    try {
        $id  = intval($_POST['payroll_id']);
        $old = mysqli_fetch_assoc(mysqli_query($dbConn,"SELECT * FROM hr_payroll WHERE id=$id LIMIT 1"));
        if(!$old) throw new Exception("Not found");

        $arr = floatval($_POST['arrears']);
        $ota = floatval($_POST['ot_amount']);
        $ovt = floatval($_POST['overtime']);
        $inc = floatval($_POST['incentives']);
        $adv = floatval($_POST['advance']);
        $pen = floatval($_POST['penalty']);

        $gross    = floatval($old['gross_pay']);
        $pf       = floatval($old['pf']);
        $per_day  = floatval($old['per_day_salary']) ?: round($gross/26,2);

        // Present days (normal, capped at 26) + OT days
        $normal_days = intval($old['present_days']);
        $ot_days     = intval($old['weekends_worked'] ?? 0);
        $auto_ot     = round($per_day * $ot_days, 2);

        // If HR manually entered OT, use that instead
        $final_ot = ($ota > 0) ? $ota : $auto_ot;

        $earned = $per_day * $normal_days;
        $net    = max(0, $earned + $final_ot + $arr + $ovt + $inc - $adv - $pen);
        $ctc    = $gross + $pf + $final_ot + $arr + $ovt + $inc;

        mysqli_query($dbConn,"UPDATE hr_payroll SET arrears=$arr,ot_amount=$final_ot,overtime=$ovt,incentives=$inc,advance_salary=$adv,penalty=$pen,net_salary=$net,total_ctc=$ctc,amount=$net WHERE id=$id");
        $_SESSION['msg'] = mysqli_error($dbConn) ? "Error: ".mysqli_error($dbConn) : "✓ Payroll updated";

    } catch(Exception $e) { $_SESSION['msg']="Error: ".$e->getMessage(); }
    header("Location: ".$_SERVER['PHP_SELF']); exit;
}

// ============================================================================
// FETCH DATA
// ============================================================================
$current_month = date('n');
$current_year  = date('Y');

$filter_from = $_POST['filter_from'] ?? $_SESSION['payroll_filter_from'] ?? date('Y-m-01');
$filter_to   = $_POST['filter_to']   ?? $_SESSION['payroll_filter_to']   ?? date('Y-m-t');
if(isset($_POST['apply_filter'])) { $_SESSION['payroll_filter_from']=$filter_from; $_SESSION['payroll_filter_to']=$filter_to; }
$saved_add = intval($_SESSION['payroll_add_working_days'] ?? 0);

$data = mysqli_query($dbConn,"SELECT p.*,e.name,e.employee_id as emp_code FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id=e.id WHERE CONCAT(p.pay_year,'-',LPAD(p.pay_month,2,'0'),'-01') BETWEEN '$filter_from' AND '$filter_to' AND e.status='active' ORDER BY p.pay_year DESC,p.pay_month DESC,e.name");
if(!$data) die("Error: ".mysqli_error($dbConn));

$total_records = mysqli_num_rows($data);
$hq = mysqli_query($dbConn,"SELECT holidays_in_month FROM hr_payroll WHERE pay_month=$current_month AND pay_year=$current_year LIMIT 1");
$holidays = ($hq && mysqli_num_rows($hq)>0) ? intval(mysqli_fetch_assoc($hq)['holidays_in_month']) : 0;

$active_emps = mysqli_query($dbConn,"SELECT id,name,employee_id,position FROM hr_employees WHERE status='active' ORDER BY name");
$overrides   = mysqli_query($dbConn,"SELECT o.*,e.name,e.employee_id as ec FROM hr_attendance_overrides o INNER JOIN hr_employees e ON o.employee_id=e.id WHERE MONTH(o.attendance_date)=$current_month AND YEAR(o.attendance_date)=$current_year ORDER BY o.attendance_date DESC,e.name");

$total_gross=$total_net=$total_ctc_sum=$total_ot=0;
if($total_records>0) {
    mysqli_data_seek($data,0);
    while($r=mysqli_fetch_assoc($data)) {
        $total_gross   += floatval($r['gross_pay']);
        $total_net     += floatval($r['net_salary']);
        $total_ctc_sum += floatval($r['total_ctc']);
        $total_ot      += floatval($r['ot_amount']??$r['ot']);
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Payroll System</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Inter',sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;padding:20px;color:#1a202c;}
    .wrap{max-width:1900px;margin:0 auto;background:white;border-radius:24px;box-shadow:0 25px 50px -12px rgba(0,0,0,.25);overflow:hidden;}
    .hdr{background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);color:white;padding:35px 50px;display:flex;justify-content:space-between;align-items:center;}
    .hdr h1{margin:0 0 5px;font-size:32px;font-weight:900;}
    .hdr p{margin:0;font-size:14px;opacity:.9;}
    .btn-back{background:rgba(255,255,255,.2);color:white;padding:10px 20px;border-radius:10px;font-weight:600;text-decoration:none;display:inline-flex;align-items:center;gap:8px;border:1px solid rgba(255,255,255,.3);transition:all .3s;}
    .btn-back:hover{background:white;color:#1e3c72;text-decoration:none;}
    .content{padding:35px 50px;}
    .alert-m{padding:15px 20px;border-radius:10px;margin-bottom:25px;font-weight:600;background:linear-gradient(135deg,#d4edda,#c3e6cb);color:#155724;border-left:4px solid #28a745;}
    .info-box{background:#f0fdf4;border:2px solid #10b981;border-radius:12px;padding:15px 20px;margin-bottom:25px;font-size:13px;color:#065f46;line-height:1.6;}
    .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:16px;margin-bottom:30px;}
    .sc{color:white;padding:20px;border-radius:14px;box-shadow:0 8px 15px -3px rgba(0,0,0,.1);transition:all .3s;}
    .sc:hover{transform:translateY(-4px);}
    .sc.blue{background:linear-gradient(135deg,#3b82f6,#2563eb);}
    .sc.green{background:linear-gradient(135deg,#10b981,#059669);}
    .sc.orange{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .sc.purple{background:linear-gradient(135deg,#8b5cf6,#7c3aed);}
    .sc.teal{background:linear-gradient(135deg,#14b8a6,#0d9488);}
    .sc .lbl{font-size:11px;font-weight:700;text-transform:uppercase;opacity:.9;margin-bottom:6px;}
    .sc .val{font-size:26px;font-weight:900;}
    .ctrl{background:linear-gradient(135deg,#f0f9ff,#e0f2fe);border:2px solid #3b82f6;border-radius:14px;padding:25px;margin-bottom:30px;}
    .ctrl-row{display:flex;gap:15px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;}
    label{display:block;font-weight:700;margin-bottom:6px;color:#1e40af;font-size:13px;}
    .fc{padding:9px 13px;border:2px solid #bfdbfe;border-radius:8px;font-size:13px;font-weight:600;background:white;}
    .btn{padding:9px 20px;border-radius:9px;font-weight:700;font-size:13px;border:none;cursor:pointer;transition:all .3s;display:inline-flex;align-items:center;gap:7px;box-shadow:0 3px 6px rgba(0,0,0,.1);}
    .btn:hover{transform:translateY(-2px);}
    .btn-p{background:linear-gradient(135deg,#3b82f6,#2563eb);color:white;}
    .btn-s{background:linear-gradient(135deg,#10b981,#059669);color:white;}
    .btn-d{background:linear-gradient(135deg,#ef4444,#dc2626);color:white;}
    .btn-v{background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:white;}
    .tw{background:white;border-radius:14px;border:2px solid #e5e7eb;overflow-x:auto;overflow-y:auto;max-height:620px;box-shadow:0 4px 6px rgba(0,0,0,.08);margin-bottom:25px;}
    .pt{width:100%;border-collapse:collapse;font-size:13px;min-width:2300px;}
    .pt thead{background:linear-gradient(135deg,#1e40af,#1e3a8a);color:white;position:sticky;top:0;z-index:10;}
    .pt th{padding:16px 13px;text-align:left;font-weight:800;font-size:12px;text-transform:uppercase;border-right:1px solid rgba(255,255,255,.2);white-space:nowrap;}
    .pt td{padding:13px;border-bottom:1px solid #e5e7eb;font-size:13px;font-weight:500;white-space:nowrap;}
    .pt tbody tr:hover{background:#f8fafc;}
    .pt tbody tr:nth-child(even){background:#fafafa;}
    .pt tbody tr.ot-row{background:#fffbeb!important;}
    .ab{width:33px;height:33px;border-radius:7px;border:none;cursor:pointer;transition:all .3s;display:inline-flex;align-items:center;justify-content:center;color:white;margin-right:4px;}
    .ab.edit{background:linear-gradient(135deg,#f59e0b,#d97706);}
    .ab.dl{background:linear-gradient(135deg,#10b981,#059669);}
    .ab.del{background:linear-gradient(135deg,#ef4444,#dc2626);}
    .ab:hover{transform:scale(1.1);}
    .totals{background:linear-gradient(135deg,#1e3c72,#2a5298);color:white;padding:20px 25px;border-radius:12px;margin-top:15px;display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:15px;}
    .ti{text-align:center;}
    .ti .tl{font-size:11px;font-weight:700;text-transform:uppercase;opacity:.85;margin-bottom:5px;}
    .ti .tv{font-size:24px;font-weight:900;}
    .mc{border-radius:18px!important;border:none!important;box-shadow:0 20px 50px rgba(0,0,0,.2)!important;}
    .mh{border-radius:18px 18px 0 0!important;padding:22px 28px!important;border:none!important;}
    .mb{padding:28px!important;}
  </style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <div>
      <h1><i class="fa fa-calculator"></i> Payroll System</h1>
      <p>Fixed 26-Day Base &nbsp;|&nbsp; ALL Days Counted (Mon–Sun) &nbsp;|&nbsp; Beyond 26 = Auto OT &nbsp;|&nbsp; Simple & Fair for Everyone</p>
    </div>
    <a href="<?php echo $isAdmin ? '/dashboard/index.php' : '/dashboard/raise-a-ticket.php'; ?>" class="btn-back">
      <i class="fa fa-arrow-left"></i> Dashboard
    </a>
  </div>

  <div class="content">
    <?php if(isset($_SESSION['msg'])): ?>
    <div class="alert-m"><i class="fa fa-check-circle"></i> <?php echo $_SESSION['msg']; unset($_SESSION['msg']); ?></div>
    <?php endif; ?>

    <!-- INFO BOX -->
    <div class="info-box">
      <strong><i class="fa fa-info-circle"></i> How Salary is Calculated:</strong><br>
      &nbsp;&nbsp; ✅ <strong>Base = 26 days always</strong> (fixed for every month)<br>
      &nbsp;&nbsp; ✅ <strong>All attendance counted</strong> — Monday to Sunday, any day employee comes in<br>
      &nbsp;&nbsp; ✅ <strong>Present &lt; 26</strong> → Absent deduction &nbsp;|&nbsp; <strong>Present = 26</strong> → Full salary &nbsp;|&nbsp; <strong>Present &gt; 26</strong> → Full salary + OT<br>
      &nbsp;&nbsp; ✅ <strong>February short month?</strong> HR adds extra days in "Add Working Days" → counts towards 26<br>
      &nbsp;&nbsp; ✅ <strong>No week-off configuration needed</strong> — works automatically for everyone
    </div>

    <!-- STATS -->
    <div class="stats">
      <div class="sc blue"><div class="lbl">Filter Period</div><div class="val" style="font-size:16px"><?php echo date('M Y',strtotime($filter_from)).' – '.date('M Y',strtotime($filter_to)); ?></div></div>
      <div class="sc purple"><div class="lbl"><i class="fa fa-users"></i> Records</div><div class="val"><?php echo $total_records; ?></div></div>
      <div class="sc orange"><div class="lbl"><i class="fa fa-flag"></i> Holidays This Month</div><div class="val"><?php echo $holidays; ?></div></div>
      <div class="sc teal"><div class="lbl"><i class="fa fa-star"></i> Total Auto OT</div><div class="val">₹<?php echo number_format($total_ot); ?></div></div>
      <div class="sc green"><div class="lbl"><i class="fa fa-money"></i> Total Net Salary</div><div class="val">₹<?php echo number_format($total_net); ?></div></div>
    </div>

    <!-- CONTROLS -->
    <div class="ctrl">
      <div class="ctrl-row">
        <div style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;">
          <form method="POST" style="display:inline-flex;gap:10px;align-items:flex-end;">
            <div>
              <label>Holidays</label>
              <input type="number" name="holidays_count" value="0" min="0" max="31" class="fc" style="width:75px" required>
            </div>
            <div>
              <label title="For short months like Feb - adds to present days">Add Working Days
                <small style="color:#059669;font-size:10px;display:block;">For Feb/short months</small>
              </label>
              <input type="number" name="add_working_days" value="<?php echo $saved_add; ?>" min="0" max="10" class="fc" style="width:75px">
            </div>
            <input type="hidden" name="filter_from" value="<?php echo $filter_from; ?>">
            <input type="hidden" name="filter_to"   value="<?php echo $filter_to; ?>">
            <button type="submit" name="auto_generate" class="btn btn-s"><i class="fa fa-refresh"></i> Generate Payroll</button>
          </form>
          <button type="button" class="btn btn-v" data-toggle="modal" data-target="#markModal"><i class="fa fa-users"></i> Mark Specific Employees</button>
        </div>
        <div style="display:flex;gap:10px;align-items:flex-end;">
          <form method="POST" style="display:flex;gap:8px;align-items:flex-end;background:#dbeafe;padding:8px 12px;border-radius:10px;">
            <div><label style="font-size:11px">From</label><input type="date" name="filter_from" class="fc" style="height:33px;font-size:12px" value="<?php echo $filter_from; ?>"></div>
            <div><label style="font-size:11px">To</label><input type="date" name="filter_to" class="fc" style="height:33px;font-size:12px" value="<?php echo $filter_to; ?>"></div>
            <button type="submit" name="apply_filter" class="btn btn-p" style="height:33px"><i class="fa fa-filter"></i> Apply</button>
          </form>
          <form method="POST">
            <input type="hidden" name="export_from" value="<?php echo $filter_from; ?>">
            <input type="hidden" name="export_to"   value="<?php echo $filter_to; ?>">
            <button type="submit" name="export_csv" class="btn btn-s" style="height:33px"><i class="fa fa-download"></i> Export CSV</button>
          </form>
        </div>
      </div>
    </div>

    <!-- OVERRIDES -->
    <?php if($overrides && mysqli_num_rows($overrides)>0): ?>
    <div style="background:#fef3c7;border:2px solid #f59e0b;border-radius:12px;padding:18px;margin-bottom:25px;">
      <h4 style="color:#92400e;font-weight:800;margin-bottom:12px;"><i class="fa fa-calendar-check-o"></i> Attendance Overrides (<?php echo date('F Y'); ?>)</h4>
      <div style="max-height:200px;overflow-y:auto;">
        <table class="table table-condensed" style="background:white;border-radius:8px;font-size:13px;margin:0;">
          <thead style="background:#f59e0b;color:white;"><tr><th>Employee</th><th>Date</th><th>Status</th><th>Reason</th><th>By</th><th></th></tr></thead>
          <tbody>
            <?php while($ov=mysqli_fetch_assoc($overrides)): ?>
            <tr>
              <td><strong><?php echo htmlspecialchars($ov['name']); ?></strong></td>
              <td><?php echo date('d M Y',strtotime($ov['attendance_date'])); ?> (<?php echo date('D',strtotime($ov['attendance_date'])); ?>)</td>
              <td><span class="label label-<?php echo $ov['status']=='holiday'?'warning':'info'; ?>"><?php echo ucfirst($ov['status']); ?></span></td>
              <td><?php echo htmlspecialchars($ov['reason']); ?></td>
              <td><small><?php echo htmlspecialchars($ov['created_by']); ?></small></td>
              <td><form method="POST" style="display:inline"><input type="hidden" name="override_id" value="<?php echo $ov['id']; ?>"><button type="submit" name="delete_override" class="btn btn-xs btn-danger">Remove</button></form></td>
            </tr>
            <?php endwhile; ?>
          </tbody>
        </table>
      </div>
    </div>
    <?php endif; ?>

    <!-- PAYROLL TABLE -->
    <?php if($total_records>0): ?>
    <div class="tw">
      <table class="pt">
        <thead>
          <tr>
            <th>Sl</th><th>Month</th><th>Employee</th>
            <th>Basic</th><th>HRA</th><th>Conv</th><th>Special</th><th>Gross</th><th>Per Day</th>
            <th>Present Days</th><th>Absent Days</th><th>⭐ OT Days</th><th>⭐ OT Amount</th>
            <th>Arrears</th><th>Overtime</th><th>Incentives</th>
            <th>PF</th><th>Total CTC</th>
            <th>Advance</th><th>Penalty</th><th>Net Salary</th>
            <th>Payslip</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php
          $sl=1; mysqli_data_seek($data,0);
          while($row=mysqli_fetch_assoc($data)):
              $ot_val   = floatval($row['ot_amount']??$row['ot']);
              $ot_days  = intval($row['weekends_worked']??0);
              $per_day  = floatval($row['per_day_salary']??0) ?: round(floatval($row['gross_pay'])/26,2);
              $my       = date("M Y", mktime(0,0,0,$row['pay_month'],1,$row['pay_year']));
              $is_ot    = $ot_val > 0;
              $total_present = intval($row['present_days']) + $ot_days; // normal + OT
          ?>
          <tr class="<?php echo $is_ot ? 'ot-row' : ''; ?>">
            <td><?php echo $sl++; ?></td>
            <td style="font-weight:700;color:#8b5cf6"><?php echo $my; ?></td>
            <td style="font-weight:700;color:#1e40af">
              <?php echo htmlspecialchars($row['name']); ?>
              <br><small style="color:#64748b"><?php echo htmlspecialchars($row['emp_code']); ?></small>
            </td>
            <td>₹<?php echo number_format($row['basic_salary']); ?></td>
            <td>₹<?php echo number_format($row['hra']); ?></td>
            <td>₹<?php echo number_format($row['conveyance']); ?></td>
            <td>₹<?php echo number_format($row['special_allowance']); ?></td>
            <td style="font-weight:700;color:#3b82f6">₹<?php echo number_format($row['gross_pay']); ?></td>
            <td style="color:#8b5cf6;font-weight:700">₹<?php echo number_format($per_day,2); ?></td>
            <td>
              <div style="font-weight:700;color:#10b981"><?php echo $row['present_days']; ?></div>
              <small style="color:#64748b">/ 26 base</small>
              <?php if($total_present != $row['present_days']): ?>
                <br><small style="color:#64748b">Total: <?php echo $total_present; ?></small>
              <?php endif; ?>
            </td>
            <td style="color:#ef4444;font-weight:700"><?php echo $row['absent_days']; ?></td>
            <td style="<?php echo $ot_days>0?'color:#d97706;font-weight:800;background:#fffbeb;':'color:#64748b;'; ?>">
              <?php if($ot_days>0): ?>⭐ <?php endif; ?><?php echo $ot_days; ?>
              <?php if($ot_days>0): ?><br><small>extra days</small><?php endif; ?>
            </td>
            <td style="<?php echo $ot_val>0?'color:#d97706;font-weight:800;background:#fffbeb;':'color:#64748b;'; ?>">
              ₹<?php echo number_format($ot_val); ?>
            </td>
            <td>₹<?php echo number_format($row['arrears']); ?></td>
            <td>₹<?php echo number_format($row['overtime']); ?></td>
            <td>₹<?php echo number_format($row['incentives']); ?></td>
            <td style="color:#ef4444;font-weight:700">₹<?php echo number_format($row['pf']); ?></td>
            <td style="font-weight:700;color:#8b5cf6">₹<?php echo number_format($row['total_ctc']); ?></td>
            <td>₹<?php echo number_format($row['advance_salary']); ?></td>
            <td>₹<?php echo number_format($row['penalty']); ?></td>
            <td style="font-weight:900;color:#10b981;font-size:15px">₹<?php echo number_format($row['net_salary']); ?></td>
            <td><a href="?download_payslip=<?php echo $row['id']; ?>" target="_blank" class="ab dl" title="Payslip"><i class="fa fa-download"></i></a></td>
            <td>
              <button class="ab edit" onclick='editPayroll(<?php echo json_encode($row,JSON_HEX_APOS|JSON_HEX_QUOT); ?>)' title="Edit"><i class="fa fa-pencil"></i></button>
              <button class="ab del" onclick='confirmDelete(<?php echo $row["id"]; ?>,"<?php echo addslashes($row['name']); ?>","<?php echo $my; ?>")' title="Delete"><i class="fa fa-trash"></i></button>
            </td>
          </tr>
          <?php endwhile; ?>
        </tbody>
      </table>
    </div>
    <div class="totals">
      <div class="ti"><div class="tl">Records</div><div class="tv"><?php echo $total_records; ?></div></div>
      <div class="ti"><div class="tl">Total Gross</div><div class="tv">₹<?php echo number_format($total_gross); ?></div></div>
      <div class="ti"><div class="tl">⭐ Total OT</div><div class="tv" style="color:#fcd34d">₹<?php echo number_format($total_ot); ?></div></div>
      <div class="ti"><div class="tl">Total CTC</div><div class="tv">₹<?php echo number_format($total_ctc_sum); ?></div></div>
      <div class="ti"><div class="tl">Total Net Salary</div><div class="tv">₹<?php echo number_format($total_net); ?></div></div>
    </div>
    <?php else: ?>
    <div style="text-align:center;padding:80px;color:#64748b;">
      <i class="fa fa-database" style="font-size:80px;color:#cbd5e1;display:block;margin-bottom:20px;"></i>
      <h3>No Payroll Data</h3>
      <p>Click "Generate Payroll" to create records for the selected period.</p>
    </div>
    <?php endif; ?>
  </div>
</div>

<!-- MARK EMPLOYEES MODAL -->
<div class="modal fade" id="markModal" tabindex="-1">
  <div class="modal-dialog modal-lg" style="width:800px;">
    <div class="modal-content mc">
      <div class="modal-header mh" style="background:linear-gradient(135deg,#8b5cf6,#7c3aed);">
        <button type="button" class="close" data-dismiss="modal" style="color:white;opacity:1;">&times;</button>
        <h4 class="modal-title" style="font-weight:800;font-size:18px;"><i class="fa fa-users"></i> Mark Holiday / Leave / Absent for Employees</h4>
      </div>
      <form method="POST">
        <div class="modal-body mb">
          <div style="background:#f0fdf4;border:2px solid #10b981;border-radius:10px;padding:12px;margin-bottom:20px;font-size:13px;color:#065f46;">
            <strong><i class="fa fa-info-circle"></i> How this affects payroll:</strong><br>
            • <strong>Holiday / Leave (Paid)</strong> → Adds to present days count (counts towards 26)<br>
            • <strong>Present (Force)</strong> → Marks as present even without biometric<br>
            • <strong>Absent</strong> → Subtracts from present days (salary deduction)
          </div>
          <div style="margin-bottom:10px;">
            <input type="text" id="empSearch" class="form-control" placeholder="Search employee..." style="border:2px solid #8b5cf6;border-radius:8px;height:38px;font-size:13px;">
          </div>
          <div style="max-height:250px;overflow-y:auto;border:2px solid #8b5cf6;border-radius:10px;">
            <label style="display:block;padding:10px 14px;background:linear-gradient(135deg,#8b5cf6,#7c3aed);color:white;font-weight:800;cursor:pointer;margin:0;position:sticky;top:0;z-index:1;">
              <input type="checkbox" id="selAll" style="width:17px;height:17px;margin-right:10px;vertical-align:middle;"> Select All
            </label>
            <div style="padding:10px;" class="emp-list">
              <?php while($e=mysqli_fetch_assoc($active_emps)): ?>
              <label class="emp-item" style="display:block;padding:9px;margin-bottom:5px;background:white;border-radius:7px;border:2px solid #e9d5ff;cursor:pointer;font-weight:normal;transition:all .2s;" onmouseover="this.style.background='#f3e8ff'" onmouseout="this.style.background='white'">
                <input type="checkbox" name="employee_ids[]" value="<?php echo $e['id']; ?>" style="width:16px;height:16px;margin-right:8px;vertical-align:middle;">
                <strong style="color:#7c3aed"><?php echo htmlspecialchars($e['name']); ?></strong>
                <span style="color:#64748b;font-size:12px;margin-left:6px;">(<?php echo htmlspecialchars($e['employee_id']); ?>)</span>
              </label>
              <?php endwhile; ?>
            </div>
          </div>
          <div class="row" style="margin-top:18px;">
            <div class="col-md-6"><label>From Date *</label><input type="date" name="from_date" class="form-control fc" required></div>
            <div class="col-md-6"><label>To Date *</label><input type="date" name="to_date" class="form-control fc" required></div>
          </div>
          <div style="margin-top:15px;">
            <label>Mark As *</label>
            <select name="mark_status" class="form-control fc" required>
              <option value="">-- Select Status --</option>
              <option value="holiday">🏖️ Holiday (Paid — adds to present count)</option>
              <option value="leave">📅 Leave (Paid — adds to present count)</option>
              <option value="present">✅ Present (Force mark)</option>
              <option value="absent">❌ Absent (Deduction)</option>
            </select>
          </div>
          <div style="margin-top:15px;">
            <label>Reason (Optional)</label>
            <textarea name="mark_reason" class="form-control" rows="2" style="border:2px solid #8b5cf6;border-radius:8px;font-size:13px;" placeholder="e.g. Public holiday, Medical leave..."></textarea>
          </div>
        </div>
        <div class="modal-footer" style="background:#faf5ff;border-top:2px solid #8b5cf6;">
          <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
          <button type="submit" name="bulk_mark_holiday" class="btn btn-v"><i class="fa fa-check"></i> Mark Selected Employees</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL -->
<div id="editModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content mc">
      <div class="modal-header mh" style="background:linear-gradient(135deg,#1e3c72,#2a5298);">
        <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
        <h4 class="modal-title"><i class="fa fa-edit"></i> Edit Payroll</h4>
      </div>
      <form method="POST">
        <div class="modal-body mb">
          <input type="hidden" name="update_payroll" value="1">
          <input type="hidden" name="payroll_id" id="m_id">
          <div style="background:linear-gradient(135deg,#dbeafe,#bfdbfe);padding:15px;border-radius:10px;margin-bottom:18px;">
            <strong id="m_name" style="color:#1e40af;font-size:17px;"></strong>
            <br><small id="m_code" style="color:#64748b;font-weight:600;"></small>
          </div>
          <div id="ot_info" style="background:#fffbeb;border:2px solid #f59e0b;border-radius:9px;padding:12px;margin-bottom:18px;display:none;">
            <strong style="color:#92400e;"><i class="fa fa-star"></i> Auto OT (days beyond 26):</strong>
            <span id="ot_display" style="color:#d97706;font-weight:700;margin-left:8px;"></span>
            <br><small style="color:#92400e;">Auto-calculated from attendance. Override only if correction needed.</small>
          </div>
          <h5 style="color:#10b981;font-weight:800;border-bottom:2px solid #10b981;padding-bottom:8px;margin-bottom:15px;"><i class="fa fa-plus-circle"></i> Additional Earnings</h5>
          <div class="row">
            <div class="col-xs-3"><label>Arrears</label><input type="number" step="0.01" name="arrears" id="m_arr" class="form-control fc"></div>
            <div class="col-xs-3"><label>OT Amount</label><input type="number" step="0.01" name="ot_amount" id="m_ot" class="form-control fc"></div>
            <div class="col-xs-3"><label>Overtime</label><input type="number" step="0.01" name="overtime" id="m_ovt" class="form-control fc"></div>
            <div class="col-xs-3"><label>Incentives</label><input type="number" step="0.01" name="incentives" id="m_inc" class="form-control fc"></div>
          </div>
          <h5 style="color:#ef4444;font-weight:800;border-bottom:2px solid #ef4444;padding-bottom:8px;margin:20px 0 15px;"><i class="fa fa-minus-circle"></i> Deductions</h5>
          <div class="row">
            <div class="col-xs-6"><label>Advance Salary</label><input type="number" step="0.01" name="advance" id="m_adv" class="form-control fc"></div>
            <div class="col-xs-6"><label>Penalty</label><input type="number" step="0.01" name="penalty" id="m_pen" class="form-control fc"></div>
          </div>
        </div>
        <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-p"><i class="fa fa-save"></i> Save</button></div>
      </form>
    </div>
  </div>
</div>

<!-- DELETE MODAL -->
<div id="delModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content mc">
    <div class="modal-header mh" style="background:linear-gradient(135deg,#ef4444,#dc2626);">
      <button type="button" class="close" data-dismiss="modal" style="color:white;">&times;</button>
      <h4 class="modal-title"><i class="fa fa-trash"></i> Confirm Delete</h4>
    </div>
    <form method="POST"><div class="modal-body mb" style="text-align:center;">
      <input type="hidden" name="delete_payroll" value="1">
      <input type="hidden" name="payroll_id" id="del_id">
      <i class="fa fa-exclamation-triangle" style="font-size:50px;color:#ef4444;margin-bottom:15px;display:block;"></i>
      <h4>Delete this payroll record?</h4>
      <p style="margin-top:10px;"><strong id="del_name" style="color:#1e40af;"></strong><br><span id="del_my" style="color:#8b5cf6;"></span></p>
    </div>
    <div class="modal-footer"><button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-d"><i class="fa fa-trash"></i> Delete</button></div>
    </form></div>
  </div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/js/bootstrap.min.js"></script>
<script>
$('#selAll').on('change', function() { $('input[name="employee_ids[]"]').prop('checked', this.checked); });
$('#empSearch').on('keyup', function() {
    var v = $(this).val().toLowerCase();
    $('.emp-list .emp-item').filter(function() { $(this).toggle($(this).text().toLowerCase().includes(v)); });
});

function editPayroll(d) {
    $('#m_id').val(d.id);
    $('#m_name').text(d.name);
    $('#m_code').text('ID: ' + d.emp_code);
    var ot = d.ot_amount ? parseFloat(d.ot_amount) : parseFloat(d.ot||0);
    var ot_days = parseInt(d.weekends_worked||0);
    $('#m_arr').val(d.arrears); $('#m_ot').val(ot);
    $('#m_ovt').val(d.overtime); $('#m_inc').val(d.incentives);
    $('#m_adv').val(d.advance_salary); $('#m_pen').val(d.penalty);
    if(ot_days > 0 && ot > 0) {
        $('#ot_display').text('₹' + ot.toLocaleString('en-IN') + ' (' + ot_days + ' extra days beyond 26)');
        $('#ot_info').show();
    } else { $('#ot_info').hide(); }
    $('#editModal').modal('show');
}

function confirmDelete(id, name, my) {
    $('#del_id').val(id); $('#del_name').text(name); $('#del_my').text(my);
    $('#delModal').modal('show');
}
</script>
</body>
</html>