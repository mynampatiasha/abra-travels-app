<?php
// ============================================================================
// SHARED PAYSLIP HTML GENERATOR
// Used by: hr-payroll.php (browser print) and hr-send-payslips.php (PDF email)
// ============================================================================

function generate_payslip_html($d, $dbConn) {
    // Fetch company logo
    $logo_base64  = '';
    $company_name = $d['company_name'] ?? ($d['company'] ?? 'Abra E Logistics Private Limited');
    if(empty($company_name)) $company_name = 'Abra E Logistics Private Limited';
    $lq = mysqli_query($dbConn, "SELECT logo_path FROM hr_companies WHERE company_name='".mysqli_real_escape_string($dbConn,$company_name)."' LIMIT 1");
    if($lq && mysqli_num_rows($lq) > 0) {
        $lp = mysqli_fetch_assoc($lq)['logo_path'];
        if(!empty($lp) && file_exists($lp))
            $logo_base64 = 'data:image/'.pathinfo($lp,PATHINFO_EXTENSION).';base64,'.base64_encode(file_get_contents($lp));
    }

    $month_name    = date("F", mktime(0,0,0,$d['pay_month'],10));
    $year          = $d['pay_year'];
    $pay_date_fmt  = date("d-M-Y", mktime(0,0,0,$d['pay_month']+1,10,$d['pay_year']));
    $per_day       = floatval($d['per_day_salary']) ?: round(floatval($d['gross_pay'])/26, 2);
    $ot_value      = floatval($d['ot_amount'] ?? $d['ot'] ?? 0);
    $ot_days       = intval($d['weekends_worked'] ?? 0);
    $gross         = floatval($d['gross_pay']);
    $absent_deduct = round($per_day * intval($d['absent_days']), 2);
    $arr_days      = floatval($d['arrears_days'] ?? 0);
    $total_deduct  = floatval($d['esi']) + floatval($d['pt']) + floatval($d['tds'])
                   + $absent_deduct + floatval($d['advance_salary']) + floatval($d['penalty'])
                   + floatval($d['other_deductions'] ?? 0);
    $rs = '₹';

    ob_start(); ?>
<table width="100%" style="max-width:750px;margin:0 auto;border:3px solid #1e3a8a;border-collapse:collapse;background:#fff;font-family:Arial,sans-serif;">

  <!-- LOGO + COMPANY -->
  <tr>
    <td style="padding:16px 24px 10px;text-align:center;border-bottom:3px solid #1e3a8a;">
      <?php if($logo_base64): ?>
      <div style="margin-bottom:8px;"><img src="<?php echo $logo_base64; ?>" style="max-height:100px;max-width:500px;" /></div>
      <?php endif; ?>
      <div style="font-size:16px;font-weight:bold;color:#1e3a8a;"><?php echo strtoupper(htmlspecialchars($company_name)); ?></div>
    </td>
  </tr>

  <!-- SLIP TITLE -->
  <tr>
    <td style="background:#1e3a8a;color:#fff;padding:7px 14px;">
      <span style="font-size:13px;font-weight:bold;letter-spacing:2px;">SALARY SLIP</span>
      <span style="font-size:10px;margin-left:12px;">Month: <?php echo $month_name.' '.$year; ?></span>
    </td>
  </tr>

  <!-- EMPLOYEE INFO -->
  <tr>
    <td style="padding:8px 24px;background:#f8f9fa;border-bottom:2px solid #dee2e6;">
      <table width="100%" style="border-collapse:collapse;">
        <tr>
          <td width="20%" style="padding:3px 6px;font-size:10px;color:#495057;">Employee Name:</td>
          <td width="30%" style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo strtoupper(htmlspecialchars($d['name'])); ?></td>
          <td width="20%" style="padding:3px 6px;font-size:10px;color:#495057;">Employee ID:</td>
          <td width="30%" style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo htmlspecialchars($d['emp_code']); ?></td>
        </tr>
        <tr>
          <td style="padding:3px 6px;font-size:10px;color:#495057;">Designation:</td>
          <td style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo htmlspecialchars($d['designation'] ?? $d['position'] ?? 'N/A'); ?></td>
          <td style="padding:3px 6px;font-size:10px;color:#495057;">Department:</td>
          <td style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo htmlspecialchars($d['dept_name'] ?? $d['department'] ?? 'N/A'); ?></td>
        </tr>
        <tr>
          <td style="padding:3px 6px;font-size:10px;color:#495057;">Pay Date:</td>
          <td style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo $pay_date_fmt; ?></td>
          <td style="padding:3px 6px;font-size:10px;color:#495057;">Pay Period:</td>
          <td style="padding:3px 6px;font-size:10px;font-weight:bold;"><?php echo $month_name.' '.$year; ?></td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- EARNINGS + DEDUCTIONS -->
  <tr>
    <td style="padding:8px 24px;">
      <table width="100%" style="border-collapse:collapse;">
        <tr>
          <!-- Earnings -->
          <td width="49%" style="vertical-align:top;padding-right:6px;">
            <table width="100%" style="border-collapse:collapse;border:1px solid #dee2e6;">
              <tr><td colspan="2" style="background:#1e3a8a;color:#fff;padding:6px 8px;font-size:10px;font-weight:bold;text-transform:uppercase;">Earnings</td></tr>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Basic Salary</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['basic_salary'],2); ?></td></tr>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">HRA</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['hra'],2); ?></td></tr>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Conveyance</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['conveyance'],2); ?></td></tr>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Special Allowance</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['special_allowance'],2); ?></td></tr>
              <tr style="background:#1e3a8a;"><td style="padding:5px 8px;font-size:10px;font-weight:bold;color:#fff;">GROSS SALARY (26 Day Base)</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;color:#fff;"><?php echo $rs.' '.number_format($gross,2); ?></td></tr>
              <?php if($ot_value > 0): ?>
              <tr style="background:#fffbeb;"><td style="padding:5px 8px;font-size:10px;color:#92400e;border-bottom:1px solid #dee2e6;">OT Amount (<?php echo $ot_days; ?> extra days)</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;color:#92400e;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($ot_value,2); ?></td></tr>
              <?php endif; ?>
              <?php if(floatval($d['arrears'] ?? 0) > 0): ?>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Arrears (<?php echo $arr_days; ?> days)</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['arrears'],2); ?></td></tr>
              <?php endif; ?>
              <?php if(floatval($d['overtime'] ?? 0) > 0): ?>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Overtime</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['overtime'],2); ?></td></tr>
              <?php endif; ?>
              <?php if(floatval($d['incentives'] ?? 0) > 0): ?>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Incentives</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['incentives'],2); ?></td></tr>
              <?php endif; ?>
              <?php if(floatval($d['other_earnings'] ?? 0) > 0): ?>
              <tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Other Earnings</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;"><?php echo $rs.' '.number_format($d['other_earnings'],2); ?></td></tr>
              <?php endif; ?>
            </table>
          </td>
          <!-- Deductions -->
          <td width="49%" style="vertical-align:top;padding-left:6px;">
            <table width="100%" style="border-collapse:collapse;border:1px solid #dee2e6;">
              <tr><td colspan="2" style="background:#1e3a8a;color:#fff;padding:6px 8px;font-size:10px;font-weight:bold;text-transform:uppercase;">Deductions</td></tr>
              <?php
              $has_ded = false;
              if(floatval($d['esi'] ?? 0) > 0)           { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">ESI</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['esi'],2).'</td></tr>'; }
              if(floatval($d['pt'] ?? 0) > 0)             { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Professional Tax</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['pt'],2).'</td></tr>'; }
              if(floatval($d['tds'] ?? 0) > 0)            { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">TDS</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['tds'],2).'</td></tr>'; }
              if($absent_deduct > 0)                       { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Absent Deduction ('.$d['absent_days'].' days)</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($absent_deduct,2).'</td></tr>'; }
              if(floatval($d['advance_salary'] ?? 0) > 0) { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Advance Salary</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['advance_salary'],2).'</td></tr>'; }
              if(floatval($d['penalty'] ?? 0) > 0)        { $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Penalty</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['penalty'],2).'</td></tr>'; }
              if(floatval($d['other_deductions'] ?? 0) > 0){ $has_ded=true; echo '<tr><td style="padding:5px 8px;font-size:10px;border-bottom:1px solid #dee2e6;">Other Deductions</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;border-bottom:1px solid #dee2e6;">'.$rs.' '.number_format($d['other_deductions'],2).'</td></tr>'; }
              if($has_ded):
              ?>
              <tr style="background:#1e3a8a;"><td style="padding:5px 8px;font-size:10px;font-weight:bold;color:#fff;">TOTAL DEDUCTIONS</td><td style="padding:5px 8px;font-size:10px;text-align:right;font-weight:bold;color:#fff;"><?php echo $rs.' '.number_format($total_deduct,2); ?></td></tr>
              <?php else: ?>
              <tr><td colspan="2" style="text-align:center;padding:15px;font-style:italic;color:#6c757d;font-size:10px;">No Deductions</td></tr>
              <?php endif; ?>
            </table>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- ATTENDANCE -->
  <tr>
    <td style="padding:0 24px 8px;">
      <table width="100%" style="border-collapse:collapse;border:1px solid #dee2e6;">
        <tr><td colspan="<?php echo ($ot_days > 0 || $ot_value > 0) ? 5 : 3; ?>" style="background:#1e3a8a;color:#fff;padding:6px 8px;font-size:10px;font-weight:bold;text-transform:uppercase;">Attendance Summary (Base: 26 Days)</td></tr>
        <tr style="background:#f8f9fa;">
          <td style="padding:6px;font-size:10px;text-align:center;border-right:1px solid #dee2e6;color:#495057;">Days Present (All Days)</td>
          <td style="padding:6px;font-size:10px;text-align:center;border-right:1px solid #dee2e6;color:#495057;">Normal Days (Max 26)</td>
          <td style="padding:6px;font-size:10px;text-align:center;color:#495057;">Absent Days</td>
          <?php if($ot_days > 0 || $ot_value > 0): ?>
          <td style="padding:6px;font-size:10px;text-align:center;border-left:1px solid #dee2e6;color:#495057;">OT Days (Beyond 26)</td>
          <td style="padding:6px;font-size:10px;text-align:center;border-left:1px solid #dee2e6;color:#495057;">OT Amount</td>
          <?php endif; ?>
        </tr>
        <tr>
          <td style="padding:7px;font-size:11px;text-align:center;font-weight:bold;border-right:1px solid #dee2e6;"><?php echo intval($d['present_days']) + $ot_days; ?></td>
          <td style="padding:7px;font-size:11px;text-align:center;font-weight:bold;border-right:1px solid #dee2e6;"><?php echo $d['present_days']; ?></td>
          <td style="padding:7px;font-size:11px;text-align:center;font-weight:bold;"><?php echo $d['absent_days']; ?></td>
          <?php if($ot_days > 0 || $ot_value > 0): ?>
          <td style="padding:7px;font-size:11px;text-align:center;font-weight:bold;color:#d97706;border-left:1px solid #dee2e6;"><?php echo $ot_days; ?></td>
          <td style="padding:7px;font-size:11px;text-align:center;font-weight:bold;color:#d97706;border-left:1px solid #dee2e6;"><?php echo $rs.' '.number_format($ot_value,2); ?></td>
          <?php endif; ?>
        </tr>
      </table>
    </td>
  </tr>

  <!-- NET SALARY -->
  <tr>
    <td style="background:#1e3a8a;color:#fff;padding:12px 24px;text-align:center;border-top:2px solid #1e40af;">
      <div style="font-size:11px;font-weight:bold;letter-spacing:2px;">NET SALARY PAYABLE</div>
      <div style="font-size:22px;font-weight:bold;margin-top:4px;"><?php echo $rs.' '.number_format($d['net_salary'],2); ?></div>
    </td>
  </tr>

  <!-- SIGNATURES -->
  <tr>
    <td style="padding:12px 24px 8px;border-top:2px solid #dee2e6;">
      <table width="100%" style="border-collapse:collapse;">
        <tr>
          <td width="45%" style="text-align:center;">
            <div style="font-size:14px;color:#1e3a8a;margin-bottom:6px;"><?php echo htmlspecialchars($d['name']); ?></div>
            <div style="border-top:2px solid #212529;margin:0 20px;"></div>
            <div style="font-size:8px;font-weight:bold;text-transform:uppercase;margin-top:3px;">Employee Signature</div>
          </td>
          <td width="10%"></td>
          <td width="45%" style="text-align:center;">
            <div style="font-size:14px;color:#1e3a8a;margin-bottom:6px;">Abishek Veeraswamy</div>
            <div style="border-top:2px solid #212529;margin:0 20px;"></div>
            <div style="font-size:8px;font-weight:bold;text-transform:uppercase;margin-top:3px;">Authorized Signatory</div>
            <div style="font-size:7px;color:#6c757d;">Managing Director</div>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- FOOTER -->
  <tr>
    <td style="padding:6px 24px 10px;text-align:center;font-size:8px;color:#6c757d;font-style:italic;">
      This is a computer-generated payslip and does not require a physical signature. | Confidential — Do not share.
    </td>
  </tr>

</table>
<?php
    return ob_get_clean();
}