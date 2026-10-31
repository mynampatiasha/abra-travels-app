<?php
// ============================================================================
// AUTOMATED PAYSLIP EMAIL SENDER — PHPMailer SMTP Version
// Runs on the 10th of every month at 6:00 PM IST
// Sends payslips for the PREVIOUS month to all active employees
// Each company sends from its own email account via SMTP
// ============================================================================
// SECURITY: Call with ?token=AbraPayslip@2026
// CRON:     0 18 10 * * curl "https://crm.abra-logistic.com/dashboard/hr-send-payslips.php?token=AbraPayslip@2026"
// TEST:     Add &month=5&year=2026 to send a specific month manually
// ============================================================================

date_default_timezone_set('Asia/Kolkata');

// ── Security ──────────────────────────────────────────────────────────────────
define('SEND_TOKEN', 'AbraPayslip@2026');
$token = $_GET['token'] ?? $_POST['token'] ?? '';
if($token !== SEND_TOKEN) {
    http_response_code(403);
    die(json_encode(['error' => 'Unauthorized']));
}

// ── Load PHPMailer (manual install — no Composer needed) ─────────────────────
$pm_base = __DIR__ . '/phpmailer/src/';
$pm_files = ['Exception.php', 'PHPMailer.php', 'SMTP.php'];
foreach($pm_files as $f) {
    $full = $pm_base . $f;
    if(!file_exists($full)) {
        die(json_encode(['error' => "PHPMailer file missing: $full — run setup commands in terminal first."]));
    }
    require_once $full;
}

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

// ── DB Connection ─────────────────────────────────────────────────────────────
require_once('database.php');
require_once('library.php');
require_once('funciones.php');
if(!isset($dbConn) || !$dbConn) die(json_encode(['error' => 'DB connection failed']));

// ── Month to send ─────────────────────────────────────────────────────────────
// Default = previous month (on the 10th, send last month's slip)
$send_month = isset($_GET['month']) ? intval($_GET['month']) : intval(date('n')) - 1;
$send_year  = isset($_GET['year'])  ? intval($_GET['year'])  : intval(date('Y'));
if($send_month < 1) { $send_month = 12; $send_year--; }
$month_name = date('F', mktime(0,0,0,$send_month,1,$send_year));

// ── Company SMTP config ───────────────────────────────────────────────────────
// keyword => config (matched against company_name in DB, case-insensitive)
$company_smtp = [
    'logistic' => [
        'from_name'  => 'Abra E-Logistics HR',
        'from_email' => 'hr-admin@abra-logistic.com',
        'smtp_host'  => 'mail.abra-logistic.com',
        'smtp_user'  => 'hr-admin@abra-logistic.com',
        'smtp_pass'  => 'Abragroup@123',
        'smtp_port'  => 465,
        'smtp_enc'   => PHPMailer::ENCRYPTION_SMTPS,
        'color'      => '#1e3a8a',
        'short'      => 'Abra E-Logistics',
    ],
    'zylo' => [
        'from_name'  => 'Abra Zylo HR',
        'from_email' => 'hr-admin@abra-zylo.com',
        'smtp_host'  => 'mail.abra-zylo.com',
        'smtp_user'  => 'hr-admin@abra-zylo.com',
        'smtp_pass'  => 'Abragroup@123',
        'smtp_port'  => 465,
        'smtp_enc'   => PHPMailer::ENCRYPTION_SMTPS,
        'color'      => '#065f46',
        'short'      => 'Abra Zylo',
    ],
    'travel' => [
        'from_name'  => 'Abra Travels HR',
        'from_email' => 'hr-admin@abra-travels.com',
        'smtp_host'  => 'mail.abra-travels.com',
        'smtp_user'  => 'hr-admin@abra-travels.com',
        'smtp_pass'  => 'Abragroup@123',
        'smtp_port'  => 465,
        'smtp_enc'   => PHPMailer::ENCRYPTION_SMTPS,
        'color'      => '#7c3aed',
        'short'      => 'Abra Travels',
    ],
    'design' => [
        'from_name'  => 'Abra Design Build HR',
        'from_email' => 'hr-admin@abra-designbuild.com',
        'smtp_host'  => 'mail.abra-designbuild.com',
        'smtp_user'  => 'hr-admin@abra-designbuild.com',
        'smtp_pass'  => 'Abragroup@123',
        'smtp_port'  => 465,
        'smtp_enc'   => PHPMailer::ENCRYPTION_SMTPS,
        'color'      => '#b45309',
        'short'      => 'Abra Design Build',
    ],
];

// Helper: match company name to SMTP config
function getCompanyCfg($company_name, $smtp_map) {
    $name_lower = strtolower($company_name ?? '');
    foreach($smtp_map as $keyword => $cfg) {
        if(strpos($name_lower, $keyword) !== false) return $cfg;
    }
    return $smtp_map['logistic']; // default fallback
}

// ── Fetch payroll records ─────────────────────────────────────────────────────
$res = mysqli_query($dbConn, "
    SELECT p.*, e.name, e.employee_id as emp_code, e.personal_email,
           e.position as designation, e.department as dept_name,
           COALESCE(NULLIF(e.company_name,''), 'Abra E Logistics Private Limited') as company
    FROM hr_payroll p
    INNER JOIN hr_employees e ON p.employee_id = e.id
    WHERE p.pay_month = $send_month AND p.pay_year = $send_year
    AND e.status = 'active'
    ORDER BY e.company_name, e.name
");
if(!$res) die(json_encode(['error' => 'Query failed: '.mysqli_error($dbConn)]));

$sent=0; $failed=0; $skipped=0; $log=[];

while($d = mysqli_fetch_assoc($res)) {

    $emp_email = trim($d['personal_email'] ?? '');

    // Skip if no valid email
    if(!$emp_email || !filter_var($emp_email, FILTER_VALIDATE_EMAIL)) {
        $skipped++;
        $log[] = "⚠ SKIP: {$d['name']} — no valid email";
        continue;
    }

    $cfg = getCompanyCfg($d['company'], $company_smtp);

    // ── Payslip calculations ──────────────────────────────────────────────────
    $per_day       = floatval($d['per_day_salary']) ?: round(floatval($d['gross_pay'])/26, 2);
    $ot_value      = floatval($d['ot_amount'] ?? $d['ot'] ?? 0);
    $ot_days       = intval($d['weekends_worked'] ?? 0);
    $gross         = floatval($d['gross_pay']);
    $absent_deduct = round($per_day * floatval($d['absent_days']), 2);
    $total_deduct  = floatval($d['esi']) + floatval($d['pt']) + floatval($d['tds'])
                   + $absent_deduct + floatval($d['advance_salary']) + floatval($d['penalty'])
                   + floatval($d['other_deductions'] ?? 0);
    $arr_days      = floatval($d['arrears_days'] ?? 0);
    $pay_date_fmt  = date('d-M-Y', mktime(0,0,0,$send_month+1,10,$send_year));
    $co_color      = $cfg['color'];
    $co_short      = $cfg['short'];

    // Fetch company logo
    $company_name_esc = mysqli_real_escape_string($dbConn, $d['company']);
    $logo_base64 = '';
    $lq = mysqli_query($dbConn, "SELECT logo_path FROM hr_companies WHERE company_name='$company_name_esc' LIMIT 1");
    if($lq && mysqli_num_rows($lq)>0) {
        $lp = mysqli_fetch_assoc($lq)['logo_path'];
        if(!empty($lp) && file_exists($lp)) {
            $logo_base64 = 'data:image/'.pathinfo($lp,PATHINFO_EXTENSION).';base64,'.base64_encode(file_get_contents($lp));
        }
    }

    // ── Build payslip HTML ────────────────────────────────────────────────────
    ob_start(); ?>
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body{margin:0;padding:0;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;}
  .outer{max-width:640px;margin:0 auto;padding:24px 16px;}
  .greeting{background:#fff;border-radius:14px 14px 0 0;padding:28px 30px 22px;border-bottom:4px solid <?php echo $co_color;?>;}
  .greeting h2{color:<?php echo $co_color;?>;margin:0 0 12px;font-size:20px;}
  .greeting p{color:#374151;font-size:14px;line-height:1.8;margin:0;}
  .ps{background:#fff;border:2px solid <?php echo $co_color;?>;margin-top:20px;border-radius:4px;}
  .hd{background:<?php echo $co_color;?>;color:#fff;padding:16px 22px;text-align:center;}
  .hd .t{font-size:15px;font-weight:bold;letter-spacing:2px;}
  .hd .sub{font-size:11px;margin-top:4px;opacity:.8;}
  .info{padding:10px 22px;background:#f8faff;border-bottom:1px solid #e2e8f0;}
  .info table{width:100%;border-collapse:collapse;}
  .info td{padding:4px 6px;font-size:11px;color:#374151;}
  .info td:nth-child(odd){color:#6b7280;width:22%;}
  .info td:nth-child(even){font-weight:700;width:28%;}
  .two-col{display:table;width:100%;}
  .col{display:table-cell;width:50%;vertical-align:top;padding:12px 22px;}
  .col h3{background:<?php echo $co_color;?>;color:#fff;padding:6px 10px;font-size:10px;font-weight:bold;margin:0 0 8px;text-transform:uppercase;letter-spacing:1px;}
  .tbl{width:100%;border-collapse:collapse;border:1px solid #e2e8f0;}
  .tbl tr{border-bottom:1px solid #e2e8f0;}
  .tbl td{padding:5px 8px;font-size:10px;color:#374151;}
  .tbl td:last-child{text-align:right;font-weight:bold;}
  .tot{background:<?php echo $co_color;?>!important;}
  .tot td{color:#fff!important;font-weight:bold!important;font-size:11px!important;}
  .ot-row td{background:#fffbeb;color:#92400e!important;}
  .att{padding:0 22px 14px;}
  .att-hd{background:<?php echo $co_color;?>;color:#fff;padding:6px 10px;font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;}
  .att-tbl{width:100%;border-collapse:collapse;border:1px solid #e2e8f0;margin-top:0;}
  .att-tbl td{padding:8px;font-size:10px;text-align:center;border-right:1px solid #e2e8f0;}
  .lc{background:#f1f5f9;color:#64748b;font-weight:600;}
  .vc{font-weight:bold;color:#1e293b;}
  .net{background:<?php echo $co_color;?>;color:#fff;padding:16px 22px;text-align:center;}
  .net .nl{font-size:11px;font-weight:bold;letter-spacing:2px;margin-bottom:5px;}
  .net .na{font-size:26px;font-weight:bold;}
  .footer{background:#fff;border-radius:0 0 14px 14px;padding:20px 30px 24px;margin-top:20px;border-top:3px solid <?php echo $co_color;?>;}
  .footer p{font-size:12px;color:#6b7280;line-height:1.7;margin:0 0 6px;}
  .sig{color:<?php echo $co_color;?>;font-weight:700;font-size:13px;}
  .notice{background:#f0fdf4;border:1px solid #86efac;border-radius:8px;padding:10px 14px;font-size:11px;color:#166534;margin-top:14px;}
  .conf{background:#fef3c7;border:1px solid #fcd34d;border-radius:8px;padding:10px 14px;font-size:11px;color:#92400e;margin-top:10px;}
</style>
</head>
<body>
<div class="outer">

  <!-- Greeting -->
  <div class="greeting">
    <h2>Dear <?php echo htmlspecialchars($d['name']); ?>,</h2>
    <p>
      We are pleased to share your <strong>Salary Slip for <?php echo $month_name.' '.$send_year; ?></strong>.<br>
      Your net salary of <strong>₹ <?php echo number_format($d['net_salary'],2); ?></strong> has been processed
      and will be credited to your registered bank account by <strong><?php echo $pay_date_fmt; ?></strong>.<br><br>
      Please review your payslip below. If you notice any discrepancy, kindly reach out to the HR department at the earliest.
    </p>
  </div>

  <!-- Payslip Card -->
  <div class="ps">

    <div class="hd">
      <div class="t">SALARY SLIP — <?php echo strtoupper($month_name.' '.$send_year); ?></div>
      <div class="sub"><?php echo strtoupper($co_short); ?></div>
    </div>

    <div class="info">
      <table>
        <tr>
          <td>Employee Name:</td><td><?php echo strtoupper(htmlspecialchars($d['name'])); ?></td>
          <td>Employee ID:</td><td><?php echo htmlspecialchars($d['emp_code']); ?></td>
        </tr>
        <tr>
          <td>Designation:</td><td><?php echo htmlspecialchars($d['designation'] ?? ''); ?></td>
          <td>Department:</td><td><?php echo htmlspecialchars($d['dept_name'] ?? ''); ?></td>
        </tr>
        <tr>
          <td>Pay Date:</td><td><?php echo $pay_date_fmt; ?></td>
          <td>Pay Period:</td><td><?php echo $month_name.' '.$send_year; ?></td>
        </tr>
      </table>
    </div>

    <div class="two-col">
      <!-- Earnings -->
      <div class="col">
        <h3>Earnings</h3>
        <table class="tbl">
          <tr><td>Basic Salary</td><td>₹ <?php echo number_format($d['basic_salary'],2); ?></td></tr>
          <tr><td>HRA</td><td>₹ <?php echo number_format($d['hra'],2); ?></td></tr>
          <tr><td>Conveyance</td><td>₹ <?php echo number_format($d['conveyance'],2); ?></td></tr>
          <tr><td>Special Allowance</td><td>₹ <?php echo number_format($d['special_allowance'],2); ?></td></tr>
          <tr class="tot"><td>GROSS SALARY</td><td>₹ <?php echo number_format($gross,2); ?></td></tr>
          <?php if($ot_value>0): ?>
          <tr class="ot-row"><td>OT (<?php echo $ot_days; ?> days)</td><td>₹ <?php echo number_format($ot_value,2); ?></td></tr>
          <?php endif; ?>
          <?php if(floatval($d['arrears'])>0): ?>
          <tr><td>Arrears (<?php echo $arr_days; ?> days)</td><td>₹ <?php echo number_format($d['arrears'],2); ?></td></tr>
          <?php endif; ?>
          <?php if(floatval($d['overtime'])>0): ?>
          <tr><td>Overtime</td><td>₹ <?php echo number_format($d['overtime'],2); ?></td></tr>
          <?php endif; ?>
          <?php if(floatval($d['incentives'])>0): ?>
          <tr><td>Incentives</td><td>₹ <?php echo number_format($d['incentives'],2); ?></td></tr>
          <?php endif; ?>
          <?php if(floatval($d['other_earnings']??0)>0): ?>
          <tr><td>Other Earnings</td><td>₹ <?php echo number_format($d['other_earnings'],2); ?></td></tr>
          <?php endif; ?>
        </table>
      </div>

      <!-- Deductions -->
      <div class="col">
        <h3>Deductions</h3>
        <table class="tbl">
          <?php if(floatval($d['esi'])>0): ?><tr><td>ESI</td><td>₹ <?php echo number_format($d['esi'],2); ?></td></tr><?php endif; ?>
          <?php if(floatval($d['pt'])>0): ?><tr><td>Professional Tax</td><td>₹ <?php echo number_format($d['pt'],2); ?></td></tr><?php endif; ?>
          <?php if(floatval($d['tds'])>0): ?><tr><td>TDS</td><td>₹ <?php echo number_format($d['tds'],2); ?></td></tr><?php endif; ?>
          <?php if($absent_deduct>0): ?><tr><td>Absent (<?php echo $d['absent_days']; ?> days)</td><td>₹ <?php echo number_format($absent_deduct,2); ?></td></tr><?php endif; ?>
          <?php if(floatval($d['advance_salary'])>0): ?><tr><td>Advance</td><td>₹ <?php echo number_format($d['advance_salary'],2); ?></td></tr><?php endif; ?>
          <?php if(floatval($d['penalty'])>0): ?><tr><td>Penalty</td><td>₹ <?php echo number_format($d['penalty'],2); ?></td></tr><?php endif; ?>
          <?php if(floatval($d['other_deductions']??0)>0): ?><tr><td>Other Deductions</td><td>₹ <?php echo number_format($d['other_deductions'],2); ?></td></tr><?php endif; ?>
          <?php if($total_deduct>0): ?>
          <tr class="tot"><td>TOTAL DEDUCTIONS</td><td>₹ <?php echo number_format($total_deduct,2); ?></td></tr>
          <?php else: ?>
          <tr><td colspan="2" style="text-align:center;font-style:italic;color:#9ca3af;padding:12px;">No Deductions</td></tr>
          <?php endif; ?>
        </table>
      </div>
    </div>

    <!-- Attendance -->
    <div class="att">
      <div class="att-hd">Attendance Summary (Base: 26 Days)</div>
      <table class="att-tbl">
        <tr>
          <td class="lc">Days Present</td>
          <td class="lc">Normal Days (Max 26)</td>
          <td class="lc">Absent Days</td>
          <?php if($ot_days>0): ?><td class="lc">OT Days</td><td class="lc">OT Amount</td><?php endif; ?>
        </tr>
        <tr>
          <td class="vc"><?php echo intval($d['present_days'])+$ot_days; ?></td>
          <td class="vc"><?php echo $d['present_days']; ?></td>
          <td class="vc"><?php echo $d['absent_days']; ?></td>
          <?php if($ot_days>0): ?>
          <td class="vc" style="color:#d97706;"><?php echo $ot_days; ?></td>
          <td class="vc" style="color:#d97706;">₹ <?php echo number_format($ot_value,2); ?></td>
          <?php endif; ?>
        </tr>
      </table>
    </div>

    <!-- Net Salary -->
    <div class="net">
      <div class="nl">NET SALARY PAYABLE</div>
      <div class="na">₹ <?php echo number_format($d['net_salary'],2); ?></div>
    </div>

  </div><!-- /payslip -->

  <!-- Footer -->
  <div class="footer">
    <div class="notice">
      &#128274; This is a confidential, system-generated payslip. Please do not share it with others.
    </div>
    <div class="conf">
      &#128231; For any queries regarding your salary, please write to <strong><?php echo $cfg['from_email']; ?></strong> or speak to your HR representative.
    </div>
    <p style="margin-top:18px;">
      With Regards,<br>
      <span class="sig"><?php echo $cfg['from_name']; ?></span><br>
      <span style="color:#9ca3af;font-size:11px;"><?php echo $co_short; ?></span>
    </p>
  </div>

</div>
</body>
</html>
    <?php
    $email_html = ob_get_clean();

    // ── Generate PDF Payslip (TCPDF) ─────────────────────────────────────────
    $pdf_path = null;
    $tcpdf_file = __DIR__ . '/tcpdf/tcpdf.php';
    if(file_exists($tcpdf_file)) {
        if(!class_exists('TCPDF')) require_once $tcpdf_file;

        // PDF-friendly HTML (table-based, no CSS display:table)
        $hex = ltrim($co_color, '#');
        list($r,$g,$b) = [hexdec(substr($hex,0,2)), hexdec(substr($hex,2,2)), hexdec(substr($hex,4,2))];

        $absent_deduct2 = round(floatval($d['per_day_salary'])*floatval($d['absent_days']),2);
        $earn_rows = '';
        $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Basic Salary</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['basic_salary'],2).'</td></tr>';
        $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">HRA</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['hra'],2).'</td></tr>';
        $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Conveyance</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['conveyance'],2).'</td></tr>';
        $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Special Allowance</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['special_allowance'],2).'</td></tr>';
        if($ot_value>0) $earn_rows .= '<tr style="background:#fffbeb;"><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;color:#92400e;">OT ('.$ot_days.' days)</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;color:#92400e;">₹ '.number_format($ot_value,2).'</td></tr>';
        if(floatval($d['arrears']??0)>0) $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Arrears ('.$arr_days.' days)</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['arrears'],2).'</td></tr>';
        if(floatval($d['overtime']??0)>0) $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Overtime</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['overtime'],2).'</td></tr>';
        if(floatval($d['incentives']??0)>0) $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Incentives</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['incentives'],2).'</td></tr>';
        if(floatval($d['other_earnings']??0)>0) $earn_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Other Earnings</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['other_earnings'],2).'</td></tr>';

        $ded_rows = '';
        if(floatval($d['esi']??0)>0)            $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">ESI</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['esi'],2).'</td></tr>';
        if(floatval($d['pt']??0)>0)             $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Professional Tax</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['pt'],2).'</td></tr>';
        if(floatval($d['tds']??0)>0)            $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">TDS</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['tds'],2).'</td></tr>';
        if($absent_deduct2>0)                   $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Absent ('.$d['absent_days'].' days)</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($absent_deduct2,2).'</td></tr>';
        if(floatval($d['advance_salary']??0)>0) $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Advance</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['advance_salary'],2).'</td></tr>';
        if(floatval($d['penalty']??0)>0)        $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Penalty</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['penalty'],2).'</td></tr>';
        if(floatval($d['other_deductions']??0)>0) $ded_rows .= '<tr><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;">Other Deductions</td><td style="padding:4px 6px;border-bottom:1px solid #e2e8f0;text-align:right;font-weight:bold;">₹ '.number_format($d['other_deductions'],2).'</td></tr>';
        if(!$ded_rows) $ded_rows = '<tr><td colspan="2" style="text-align:center;font-style:italic;color:#9ca3af;padding:12px;">No Deductions</td></tr>';

        $pdf_html = '
<style>
  body{font-family:Arial,Helvetica,sans-serif;font-size:10pt;color:#1e293b;}
  table{border-collapse:collapse;}
  .hbg{background-color:'.$co_color.';color:#fff;}
</style>
<!-- Header -->
<table width="100%" style="margin-bottom:6px;">
<tr>
  <td style="background-color:'.$co_color.'; color:#fff; padding:15px; text-align:center; vertical-align:middle;">
    '.($logo_base64 ? '<div style="text-align:center;margin-bottom:8px;"><img src="'.$logo_base64.'" height="55" /></div>' : '').'
    <div style="font-size:14pt;font-weight:bold;letter-spacing:2px;">SALARY SLIP — '.strtoupper($month_name.' '.$send_year).'</div>
    <div style="font-size:10pt;margin-top:4px;opacity:.85;">'.strtoupper($co_short).'</div>
  </td>
</tr>
</table>
<!-- Employee Info -->
<table width="100%" style="border:1px solid #e2e8f0;margin-bottom:10px;background:#f8faff;">
<tr>
  <td width="20%" style="padding:5px 8px;color:#6b7280;font-size:9pt;">Employee Name</td>
  <td width="30%" style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.strtoupper(htmlspecialchars($d['name'])).'</td>
  <td width="20%" style="padding:5px 8px;color:#6b7280;font-size:9pt;">Employee ID</td>
  <td width="30%" style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.htmlspecialchars($d['emp_code']).'</td>
</tr>
<tr>
  <td style="padding:5px 8px;color:#6b7280;font-size:9pt;">Designation</td>
  <td style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.htmlspecialchars($d['designation']??'').'</td>
  <td style="padding:5px 8px;color:#6b7280;font-size:9pt;">Department</td>
  <td style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.htmlspecialchars($d['dept_name']??'').'</td>
</tr>
<tr>
  <td style="padding:5px 8px;color:#6b7280;font-size:9pt;">Pay Date</td>
  <td style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.$pay_date_fmt.'</td>
  <td style="padding:5px 8px;color:#6b7280;font-size:9pt;">Pay Period</td>
  <td style="padding:5px 8px;font-weight:bold;font-size:9pt;">'.$month_name.' '.$send_year.'</td>
</tr>
</table>
<!-- Earnings & Deductions side by side -->
<table width="100%" style="margin-bottom:10px;">
<tr>
  <td width="50%" style="vertical-align:top;padding-right:6px;">
    <table width="100%" style="border:1px solid #e2e8f0;">
    <tr class="hbg"><td colspan="2" style="padding:6px 8px;font-size:9pt;font-weight:bold;text-transform:uppercase;letter-spacing:1px;">Earnings</td></tr>
    '.$earn_rows.'
    <tr class="hbg"><td style="padding:5px 8px;font-weight:bold;font-size:9pt;">Gross Salary</td><td style="padding:5px 8px;text-align:right;font-weight:bold;font-size:9pt;">₹ '.number_format($gross,2).'</td></tr>
    </table>
  </td>
  <td width="50%" style="vertical-align:top;padding-left:6px;">
    <table width="100%" style="border:1px solid #e2e8f0;">
    <tr class="hbg"><td colspan="2" style="padding:6px 8px;font-size:9pt;font-weight:bold;text-transform:uppercase;letter-spacing:1px;">Deductions</td></tr>
    '.$ded_rows.'
    '.($total_deduct>0?'<tr class="hbg"><td style="padding:5px 8px;font-weight:bold;font-size:9pt;">Total Deductions</td><td style="padding:5px 8px;text-align:right;font-weight:bold;font-size:9pt;">₹ '.number_format($total_deduct,2).'</td></tr>':'').'
    </table>
  </td>
</tr>
</table>
<!-- Attendance -->
<table width="100%" style="border:1px solid #e2e8f0;margin-bottom:10px;">
<tr class="hbg"><td colspan="'.($ot_days>0?5:3).'" style="padding:6px 8px;font-size:9pt;font-weight:bold;text-transform:uppercase;letter-spacing:1px;">Attendance Summary (Base: 26 Days)</td></tr>
<tr style="background:#f1f5f9;">
  <td style="padding:6px 8px;font-size:9pt;text-align:center;font-weight:600;color:#64748b;border-right:1px solid #e2e8f0;">Days Present</td>
  <td style="padding:6px 8px;font-size:9pt;text-align:center;font-weight:600;color:#64748b;border-right:1px solid #e2e8f0;">Normal Days (Max 26)</td>
  <td style="padding:6px 8px;font-size:9pt;text-align:center;font-weight:600;color:#64748b;">Absent Days</td>
  '.($ot_days>0?'<td style="padding:6px 8px;font-size:9pt;text-align:center;font-weight:600;color:#64748b;border-left:1px solid #e2e8f0;">OT Days</td><td style="padding:6px 8px;font-size:9pt;text-align:center;font-weight:600;color:#64748b;border-left:1px solid #e2e8f0;">OT Amount</td>':'').'
</tr>
<tr>
  <td style="padding:8px;font-size:10pt;text-align:center;font-weight:bold;border-right:1px solid #e2e8f0;">'.(intval($d['present_days'])+$ot_days).'</td>
  <td style="padding:8px;font-size:10pt;text-align:center;font-weight:bold;border-right:1px solid #e2e8f0;">'.$d['present_days'].'</td>
  <td style="padding:8px;font-size:10pt;text-align:center;font-weight:bold;">'.$d['absent_days'].'</td>
  '.($ot_days>0?'<td style="padding:8px;font-size:10pt;text-align:center;font-weight:bold;color:#d97706;border-left:1px solid #e2e8f0;">'.$ot_days.'</td><td style="padding:8px;font-size:10pt;text-align:center;font-weight:bold;color:#d97706;border-left:1px solid #e2e8f0;">₹ '.number_format($ot_value,2).'</td>':'').'
</tr>
</table>
<!-- Net Salary -->
<table width="100%" style="margin-bottom:10px;">
<tr class="hbg">
  <td style="padding:16px;text-align:center;">
    <div style="font-size:10pt;font-weight:bold;letter-spacing:2px;">NET SALARY PAYABLE</div>
    <div style="font-size:22pt;font-weight:bold;margin-top:6px;">₹ '.number_format($d['net_salary'],2).'</div>
  </td>
</tr>
</table>
<!-- Footer note -->
<table width="100%">
<tr>
  <td style="padding:8px;font-size:8pt;color:#6b7280;text-align:center;border:1px solid #e2e8f0;background:#f8faff;">
    This is a computer-generated payslip and does not require a signature. | Confidential — Do not share.<br>
    For queries, contact: <strong>'.$cfg['from_email'].'</strong>
  </td>
</tr>
</table>';

        $pdf = new TCPDF('P', 'mm', 'A4', true, 'UTF-8', false);
        $pdf->SetCreator($co_short);
        $pdf->SetAuthor($co_short . ' HR');
        $pdf->SetTitle("Salary Slip - {$d['name']} - {$month_name} {$send_year}");
        $pdf->SetSubject("Payslip {$month_name} {$send_year}");
        $pdf->SetFont('dejavusans', '', 10);
        $pdf->SetMargins(10, 10, 10);
        $pdf->SetAutoPageBreak(true, 10);
        $pdf->setPrintHeader(false);
        $pdf->setPrintFooter(false);
        $pdf->AddPage();
        $pdf->writeHTML($pdf_html, true, false, true, false, '');

        $safe_name = preg_replace('/[^A-Za-z0-9_]/', '_', $d['name']);
        $pdf_path = sys_get_temp_dir() . "/payslip_{$safe_name}_{$send_month}_{$send_year}.pdf";
        $pdf->Output($pdf_path, 'F');
    }

    // ── Send via PHPMailer SMTP ───────────────────────────────────────────────
    try {
        $mail = new PHPMailer(true);

        $mail->isSMTP();
        $mail->Host        = $cfg['smtp_host'];
        $mail->SMTPAuth    = true;
        $mail->Username    = $cfg['smtp_user'];
        $mail->Password    = $cfg['smtp_pass'];
        $mail->SMTPSecure  = $cfg['smtp_enc'];
        $mail->Port        = $cfg['smtp_port'];
        $mail->SMTPOptions = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]];

        $mail->setFrom($cfg['from_email'], $cfg['from_name']);
        $mail->addAddress($emp_email, $d['name']);
        $mail->addReplyTo($cfg['from_email'], $cfg['from_name']);

        $mail->isHTML(true);
        $mail->CharSet = 'UTF-8';
        $mail->Subject = "Your Salary Slip for {$month_name} {$send_year} — {$co_short}";
        $mail->Body    = $email_html;
        $mail->AltBody = "Dear {$d['name']}, your salary slip for {$month_name} {$send_year} is ready. Net Salary: Rs. " . number_format($d['net_salary'],2) . ". Please contact HR for details.";

        // Attach PDF if generated
        if($pdf_path && file_exists($pdf_path)) {
            $mail->addAttachment($pdf_path, "PaySlip_{$month_name}_{$send_year}_{$d['emp_code']}.pdf");
        }

        $mail->send();
        $sent++;
        $pdf_note = $pdf_path ? ' [+PDF]' : '';
        $log[] = "✓ SENT: {$d['name']} ({$d['emp_code']}) → $emp_email [{$co_short}]{$pdf_note}";

    } catch(Exception $e) {
        $failed++;
        $log[] = "✗ FAIL: {$d['name']} → $emp_email | Error: {$mail->ErrorInfo}";
    }

    // Clean up temp PDF
    if($pdf_path && file_exists($pdf_path)) @unlink($pdf_path);

    usleep(300000); // 0.3s gap between emails
}

// ── Response ──────────────────────────────────────────────────────────────────
header('Content-Type: application/json');
echo json_encode([
    'status'    => 'done',
    'period'    => "{$month_name} {$send_year}",
    'sent'      => $sent,
    'failed'    => $failed,
    'skipped'   => $skipped,
    'log'       => $log,
    'timestamp' => date('d-M-Y H:i:s'),
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
