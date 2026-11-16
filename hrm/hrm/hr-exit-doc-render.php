<?php
// Shared by hr-exit-documents.php (renders the live letter) and hr-exit-settlement.php
// (renders the same body as a starting point when HR opens the Edit Document modal).

// Same company-branding lookup hr-exit-handover.php uses (hr_employees.company_name ->
// hr_companies -> hr_offer_company_settings), kept here so pages that only need the
// exit-document pieces don't have to require the whole handover page (which runs a lot
// of top-level table-setup/session code as a side effect of being included).
function getExitCompanySettingsByEmployeeId($con, $employee_id) {
    $default = ['company_name' => '', 'company_address' => '', 'company_phone' => '', 'company_email' => '', 'company_website' => ''];
    $employee_id = intval($employee_id);
    if ($employee_id <= 0) return $default;

    $res = mysqli_query($con, "SELECT company_name FROM hr_employees WHERE id=$employee_id LIMIT 1");
    $emp = $res ? mysqli_fetch_assoc($res) : null;
    if (!$emp || empty($emp['company_name'])) return $default;

    $cname_e = mysqli_real_escape_string($con, $emp['company_name']);
    $res2 = mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$cname_e')) LIMIT 1");
    $hc_row = $res2 ? mysqli_fetch_assoc($res2) : null;
    if (!$hc_row) return array_merge($default, ['company_name' => $emp['company_name']]);

    $res3 = mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE company_id=" . intval($hc_row['id']) . " LIMIT 1");
    $r = $res3 ? mysqli_fetch_assoc($res3) : null;
    if (!$r) return array_merge($default, ['company_name' => $hc_row['company_name']]);
    $r['company_name'] = $hc_row['company_name'];
    if (empty($r['company_signature']) && !empty($r['signature_path'])) $r['company_signature'] = $r['signature_path'];
    return $r;
}

function renderExitDocumentBody($con, $docRow, $empRow, $companySettings, $joiningDate, $lastWorkingDay) {
    $doc_type = mysqli_real_escape_string($con, $docRow['doc_type']);
    $res = mysqli_query($con, "SELECT template_html FROM hr_exit_document_templates WHERE doc_code='$doc_type' LIMIT 1");
    $tplRow = $res ? mysqli_fetch_assoc($res) : null;
    
    if ($tplRow && !empty($tplRow['template_html'])) {
        $html = $tplRow['template_html'];
    } else {
        // Fallback if not in DB yet
        $html = "<p>Dear <strong>[EMPLOYEE_NAME]</strong>,</p><p>This is a system generated document regarding your exit request.</p>";
    }

    // Prepare Settlement Table if needed
    $settlementTableHtml = '';
    if (strpos($html, '[SETTLEMENT_TABLE]') !== false) {
        $settlement = null;
        $sres = @mysqli_query($con, "SELECT * FROM hr_exit_settlement WHERE exit_id={$docRow['exit_id']} LIMIT 1");
        if ($sres) $settlement = mysqli_fetch_assoc($sres);

        ob_start();
        ?>
        <div style="margin-top:20px; margin-bottom:20px; page-break-inside:avoid;">
        <table style="width:100%; border-collapse:collapse; font-size:12.5px; font-family:sans-serif;">
            <tr>
                <th style="text-align:left; padding:8px 10px; background:#0f2557; border:1px solid #cbd5e1; color:#fff; font-weight:700; font-size:11px; letter-spacing:0.3px; text-transform:uppercase;">Particulars</th>
                <th style="text-align:right; padding:8px 10px; background:#0f2557; border:1px solid #cbd5e1; color:#fff; font-weight:700; font-size:11px; letter-spacing:0.3px; text-transform:uppercase;">Amount (INR)</th>
            </tr>
            <?php if ($settlement): ?>
            <?php if ((float)$settlement['pending_salary'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Pending Salary</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['pending_salary'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if ((float)$settlement['leave_encashment'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Leave Encashment</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['leave_encashment'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if ((float)$settlement['bonus_incentive'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Bonus / Incentive</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['bonus_incentive'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if (isset($settlement['gratuity_amount']) && $settlement['gratuity_amount'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Gratuity</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['gratuity_amount'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if (isset($settlement['pension_amount']) && $settlement['pension_amount'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Pension</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['pension_amount'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if (isset($settlement['severance_pay']) && $settlement['severance_pay'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">Severance / Notice Pay in Lieu</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹<?= number_format((float)$settlement['severance_pay'], 2) ?></td></tr>
            <?php endif; ?>

            <?php
            // Custom settlement line items from Phase 2 logic (earnings and deductions)
            // They are stored in hr_exit_settlement_items table. Let's fetch them if they exist!
            $custom_items_q = @mysqli_query($con, "SELECT * FROM hr_exit_settlement_items WHERE exit_id={$docRow['exit_id']} ORDER BY id ASC");
            $total_custom_earning = 0;
            $total_custom_deduction = 0;
            if ($custom_items_q) {
                while($citem = mysqli_fetch_assoc($custom_items_q)) {
                    if ($citem['item_type'] === 'earning' && (float)$citem['amount'] > 0) {
                        $total_custom_earning += (float)$citem['amount'];
                        echo '<tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#1e293b;">'.htmlspecialchars($citem['label']).'</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#1e293b; font-weight:bold;">₹'.number_format((float)$citem['amount'], 2).'</td></tr>';
                    } elseif ($citem['item_type'] === 'earning') {
                        $total_custom_earning += (float)$citem['amount'];
                    }
                }
            }
            ?>

            <?php
            // Custom deductions
            if ($custom_items_q) {
                mysqli_data_seek($custom_items_q, 0); // Reset pointer
                while($citem = mysqli_fetch_assoc($custom_items_q)) {
                    if ($citem['item_type'] === 'deduction') {
                        $total_custom_deduction += (float)$citem['amount'];
                        if ((float)$citem['amount'] > 0) {
                            echo '<tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#991b1b;">'.htmlspecialchars($citem['label']).'</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#991b1b; font-weight:bold;">- ₹'.number_format((float)$citem['amount'], 2).'</td></tr>';
                        }
                    }
                }
            }
            ?>

            <?php if (isset($settlement['loan_recovery']) && $settlement['loan_recovery'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#991b1b;">Loan Recovery</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#991b1b; font-weight:bold;">- ₹<?= number_format((float)$settlement['loan_recovery'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if (isset($settlement['notice_shortfall_deduction']) && $settlement['notice_shortfall_deduction'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#991b1b;">Notice Shortfall Deduction</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#991b1b; font-weight:bold;">- ₹<?= number_format((float)$settlement['notice_shortfall_deduction'], 2) ?></td></tr>
            <?php endif; ?>
            <?php if (isset($settlement['other_deductions']) && $settlement['other_deductions'] > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#991b1b;">Other Deductions</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#991b1b; font-weight:bold;">- ₹<?= number_format((float)$settlement['other_deductions'], 2) ?></td></tr>
            <?php endif; ?>

            <?php $totalDeductions = (float)($settlement['loan_recovery']+$settlement['notice_shortfall_deduction']+$settlement['other_deductions']+$total_custom_deduction); ?>
            <?php if ($totalDeductions > 0): ?>
            <tr><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:left; color:#991b1b; font-weight:bold;">Total Deductions</td><td style="padding:8px 10px; border:1px solid #cbd5e1; text-align:right; color:#991b1b; font-weight:bold;">- ₹<?= number_format($totalDeductions, 2) ?></td></tr>
            <?php endif; ?>
            <tr>
                <td style="padding:10px; border:1px solid #cbd5e1; text-align:left; color:#0f2557; font-weight:bold; font-size:13px; background:#f8faff;">Net Payable Amount</td>
                <td style="padding:10px; border:1px solid #cbd5e1; text-align:right; color:#0f2557; font-weight:bold; font-size:14px; background:#f8faff;">₹<?= number_format((float)$settlement['net_amount'], 2) ?></td>
            </tr>
            <?php else: ?>
            <tr><td colspan="2" style="padding:16px; border:1px solid #cbd5e1; text-align:center; color:#666;">Settlement calculation data not found for this exit.</td></tr>
            <?php endif; ?>
        </table>
        </div>
        <?php
        $settlementTableHtml = ob_get_clean();
    }

    // Do replacements
    $html = str_replace('[EMPLOYEE_NAME]', htmlspecialchars($empRow['name'] ?? ''), $html);
    $html = str_replace('[COMPANY_NAME]', htmlspecialchars($companySettings['company_name'] ?: 'our company'), $html);
    $html = str_replace('[JOINING_DATE]', $joiningDate, $html);
    $html = str_replace('[LAST_WORKING_DAY]', $lastWorkingDay, $html);
    $html = str_replace('[DESIGNATION]', htmlspecialchars($empRow['position'] ?? 'Employee'), $html);
    $html = str_replace('[DEPARTMENT]', htmlspecialchars($empRow['department'] ?? 'Department'), $html);
    $html = str_replace('[SETTLEMENT_TABLE]', $settlementTableHtml, $html);

    return $html;
}