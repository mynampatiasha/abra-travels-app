<?php
// ============================================================================
// AUTO-UPDATING PAYROLL SYSTEM - PROFESSIONAL PAYSLIPS
// Real-time Attendance Integration • In-line Payslip Generation
// PF Deduction from Employee Table
// FEATURES: Bulk Holiday Marking (Paid) • Perfect Salary Calculation • Modal Search
// FIXED: Pay Date is ALWAYS 10th of Next Month (Database & Payslip)
// ============================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
session_start();

try {
    if(!file_exists('database.php')) throw new Exception("database.php not found");
    require_once('database.php');
    require_once('library.php');
    require_once('funciones.php');
} catch(Exception $e) {
    die("Error loading files: " . $e->getMessage());
}

date_default_timezone_set('Asia/Kolkata');

if(!isset($_SESSION['user_name'])) { 
    header("Location: login.php"); 
    exit; 
}

if(!isset($dbConn) || !$dbConn) {
    die("Database connection failed.");
}

// ============================================================================
// AUTHORIZATION CHECK - DEPARTMENT-BASED
// ============================================================================
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// Get current user's employee data for department-based permissions
$employee_id = '';
$employee_name = '';
$employee_department = '';
$employee_position = '';

if (!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($dbConn, $currentUserName);
    $res = mysqli_query($dbConn, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$name_safe%') AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    }
}

// Check if user is in admin departments (Management or Human Resources)
$is_management_dept = (stripos($employee_department, 'Management') !== false);
$is_hr_dept = (stripos($employee_department, 'Human Resources') !== false || 
               stripos($employee_department, 'Human Resources Department') !== false);

// Check if user is Managing Director
$is_managing_director = (stripos($employee_position, 'managing director') !== false || 
                         stripos($employee_position, 'md') !== false ||
                         stripos($employee_position, 'ceo') !== false);

// Legacy name-based checks (kept for backward compatibility)
$is_abishek = (stripos($employee_name, 'abishek') !== false || stripos($employee_name, 'abhishek') !== false ||
               stripos($currentUserName, 'abishek') !== false || stripos($currentUserName, 'abhishek') !== false);
$is_keerti = (stripos($employee_name, 'keerti') !== false || stripos($employee_name, 'keerthi') !== false ||
              stripos($currentUserName, 'keerti') !== false || stripos($currentUserName, 'keerthi') !== false);

// Final authorization check: Department-based OR position-based OR legacy names
$is_authorized = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_abishek || $is_keerti);
$isAdmin = $is_abishek; // Abishek has special admin privileges

if(!$is_authorized) {
    die("<div style='font-family:Arial;text-align:center;margin-top:100px;'>
        <h2>Access Denied</h2>
        <p>Only authorized HR personnel can access this page.</p>
        <p><strong>Access Requirements:</strong></p>
        <ul style='list-style:none;'>
            <li>• Management Department</li>
            <li>• Human Resources Department</li>
            <li>• Managing Director position</li>
        </ul>
        <p><a href='raise-a-ticket.php'>Back to Dashboard</a></p>
        </div>");
}

// ============================================================================
// CREATE ATTENDANCE OVERRIDE TABLE
// ============================================================================
$create_override_table = "CREATE TABLE IF NOT EXISTS `hr_attendance_overrides` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `employee_id` INT(11) NOT NULL,
  `attendance_date` DATE NOT NULL,
  `status` ENUM('present','absent','holiday','leave','half_day') NOT NULL DEFAULT 'present',
  `reason` TEXT NULL,
  `created_by` VARCHAR(100) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_emp_date` (`employee_id`, `attendance_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
mysqli_query($dbConn, $create_override_table);

// Add per_day_salary column if doesn't exist
$check_per_day = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_payroll LIKE 'per_day_salary'");
if(!$check_per_day || mysqli_num_rows($check_per_day) == 0) {
    mysqli_query($dbConn, "ALTER TABLE hr_payroll ADD COLUMN per_day_salary DECIMAL(10,2) DEFAULT 0.00 AFTER net_salary");
}

// ============================================================================
// DOWNLOAD PROFESSIONAL PAYSLIP - INLINE LOGIC
// ============================================================================
if(isset($_GET['download_payslip'])) {
    $payroll_id = intval($_GET['download_payslip']);
    
    // Fetch payroll data with employee details including employee_type
    $query = "SELECT p.*, e.name, e.employee_id as emp_code, e.company_name, e.employee_type,
              COALESCE(e.position, 'N/A') as designation, 
              COALESCE(e.department, 'N/A') as department 
              FROM hr_payroll p 
              INNER JOIN hr_employees e ON p.employee_id = e.id 
              WHERE p.id = $payroll_id LIMIT 1";
    
    $result = mysqli_query($dbConn, $query);
    
    if(!$result || mysqli_num_rows($result) == 0) {
        die("Payroll record not found");
    }
    
    $data = mysqli_fetch_assoc($result);
    
    // Fetch company logo and name from hr_companies table
    $company_name = !empty($data['company_name']) ? $data['company_name'] : 'Abra E Logistics Private Limited';
    $logo_path = '';
    
    if($company_name) {
        $logo_query = mysqli_query($dbConn, "SELECT logo_path FROM hr_companies WHERE company_name = '$company_name' LIMIT 1");
        if($logo_query && mysqli_num_rows($logo_query) > 0) {
            $logo_row = mysqli_fetch_assoc($logo_query);
            $logo_path = $logo_row['logo_path'];
        }
    }
    
    // Convert logo to base64 if it exists
    $logo_base64 = '';
    if(!empty($logo_path) && file_exists($logo_path)) {
        $image_data = file_get_contents($logo_path);
        $image_type = pathinfo($logo_path, PATHINFO_EXTENSION);
        $logo_base64 = 'data:image/' . $image_type . ';base64,' . base64_encode($image_data);
    }
    
    $month_name = date("F", mktime(0, 0, 0, $data['pay_month'], 10));
    $year = $data['pay_year'];
    
    // FORCE PAY DATE CALCULATION: Always 10th of Next Month based on Payroll Month
    // This ignores the database date if it is wrong
    $calculated_pay_date = date("d-M-Y", mktime(0, 0, 0, $data['pay_month'] + 1, 10, $data['pay_year']));
    
    // Per day based on WORKING DAYS only
    $working_days_val = intval($data['working_days']);
    $per_day = ($working_days_val > 0) ? floatval($data['gross_pay']) / $working_days_val : 0;
    $absent_deduction = round($per_day * intval($data['absent_days']), 2);
    
    $ot_value = isset($data['ot_amount']) ? floatval($data['ot_amount']) : floatval($data['ot']);
    
    // GROSS PAY is just: Basic + HRA + Conveyance + Special Allowance
    $gross_pay = floatval($data['gross_pay']);
    
    // TOTAL EARNINGS includes arrears, OT, overtime, incentives ON TOP OF gross pay
    $total_earnings = $gross_pay + floatval($data['arrears']) + $ot_value + floatval($data['overtime']) + floatval($data['incentives']);
    
    // Total deductions - PF is NOT included (it's shown separately but not deducted from net)
    $total_deductions = floatval($data['esi']) + floatval($data['pt']) + floatval($data['tds']) + $absent_deduction + floatval($data['advance_salary']) + floatval($data['penalty']);
    
    // PF Employer Contribution - same as employee PF deduction
    $pf_employer = floatval($data['pf']);
    
    // If PF is 0 but employee is Permanent, calculate it as 12% of basic
    if($pf_employer == 0 && stripos($data['employee_type'], 'Permanent') !== false) {
        $pf_employer = round(floatval($data['basic_salary']) * 0.12, 2);
    }
    
    // Generate Professional Corporate Payslip
    $html = '
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>Payslip - ' . htmlspecialchars($data['name']) . ' - ' . $month_name . ' ' . $year . '</title>
        <style>
            @page {
                margin: 18mm 10mm 10mm 10mm;
                size: A4;
            }
            
            @media print {
                * {
                    -webkit-print-color-adjust: exact !important;
                    print-color-adjust: exact !important;
                    color-adjust: exact !important;
                }
                
                html, body { 
                    margin: 0; 
                    padding: 0;
                    background: white;
                }
                
                .no-print { 
                    display: none !important; 
                }
                
                .payslip-container {
                    box-shadow: none;
                    border: 3px solid #1e3a8a !important;
                    page-break-inside: avoid;
                    margin: 12mm auto 0 auto !important;
                    max-width: 180mm;
                    width: 180mm;
                    padding-top: 3mm;
                }
                
                .header {
                    padding-top: 18px !important;
                    background: white !important;
                }
                
                body {
                    padding: 12mm 0 0 0 !important;
                    margin: 0 !important;
                    background: white !important;
                }
                
                .total-row {
                    background: #1e3a8a !important;
                    color: white !important;
                }
                
                .total-row td {
                    background: #1e3a8a !important;
                    color: white !important;
                }
                
                .ctc-row {
                    background: #059669 !important;
                    color: white !important;
                }
                
                .ctc-row td {
                    background: #059669 !important;
                    color: white !important;
                }
                
                .net-salary {
                    background: #1e3a8a !important;
                    color: white !important;
                }
                
                .payslip-header-bar {
                    background: #1e3a8a !important;
                    color: white !important;
                }
                
                .employee-section {
                    background: #f8f9fa !important;
                }
                
                .attendance-table .label-cell {
                    background: #f8f9fa !important;
                }
                
                .salary-column h3 {
                    background: #1e3a8a !important;
                    color: white !important;
                }
                
                .attendance-section h3 {
                    background: #1e3a8a !important;
                    color: white !important;
                }
            }
            
            * { 
                margin: 0; 
                padding: 0; 
                box-sizing: border-box; 
            }
            
            html, body {
                height: 100%;
            }
            
            body { 
                font-family: Arial, Helvetica, sans-serif;
                background: #f5f5f5;
                padding: 20px 20px 20px 20px;
                margin: 0;
            }
            
            .payslip-container {
                max-width: 750px;
                width: 100%;
                margin: 0 auto;
                background: white;
                box-shadow: 0 0 20px rgba(0,0,0,0.1);
                border: 3px solid #1e3a8a;
                page-break-inside: avoid;
            }
            
            /* HEADER */
            .header {
                background: white;
                padding: 25px 30px 12px 30px;
                border-bottom: 3px solid #1e3a8a;
                text-align: center;
            }
            
            .logo-section {
                margin-bottom: 10px;
                min-height: 180px;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 5px 0;
            }
            
            .logo-section img {
                max-height: 180px;
                max-width: 600px;
                width: auto;
                height: auto;
                object-fit: contain;
                display: block;
            }
            
            .company-name {
                font-size: 20px;
                font-weight: bold;
                color: #1e3a8a;
                margin-bottom: 10px;
                letter-spacing: 0.5px;
                line-height: 1.4;
                text-align: center;
            }
            
            .payslip-header-bar {
                background: #1e3a8a;
                color: white;
                padding: 7px 12px;
                margin: 0 -25px;
            }
            
            .payslip-title {
                font-size: 15px;
                font-weight: bold;
                letter-spacing: 2px;
                margin-bottom: 2px;
            }
            
            .payslip-period {
                font-size: 12px;
                font-weight: normal;
            }
            
            /* EMPLOYEE INFO */
            .employee-section {
                padding: 6px 30px;
                background: #f8f9fa;
                border-bottom: 2px solid #dee2e6;
            }
            
            .info-table {
                width: 100%;
                border-collapse: collapse;
            }
            
            .info-table td {
                padding: 4px 6px;
                font-size: 10px;
                line-height: 1.5;
            }
            
            .info-table td:nth-child(odd) {
                color: #495057;
                font-weight: normal;
                width: 20%;
            }
            
            .info-table td:nth-child(even) {
                color: #212529;
                font-weight: bold;
                width: 30%;
            }
            
            /* SALARY DETAILS */
            .salary-section {
                padding: 6px 30px;
            }
            
            .salary-grid {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 15px;
            }
            
            .salary-column h3 {
                background: #1e3a8a;
                color: white;
                padding: 6px 10px;
                font-size: 10px;
                font-weight: bold;
                margin-bottom: 8px;
                text-transform: uppercase;
                letter-spacing: 1px;
            }
            
            .salary-table {
                width: 100%;
                border-collapse: collapse;
                border: 1px solid #dee2e6;
            }
            
            .salary-table tr {
                border-bottom: 1px solid #dee2e6;
            }
            
            .salary-table tr:last-child {
                border-bottom: none;
            }
            
            .salary-table td {
                padding: 6px 8px;
                font-size: 10px;
                line-height: 1.4;
            }
            
            .salary-table td:first-child {
                color: #495057;
                font-weight: normal;
            }
            
            .salary-table td:last-child {
                text-align: right;
                font-weight: bold;
                color: #212529;
                font-family: "Courier New", monospace;
            }
            
            .total-row {
                background: #1e3a8a !important;
                color: white !important;
                font-weight: bold;
            }
            
            .total-row td {
                padding: 6px 8px !important;
                color: white !important;
                font-weight: bold !important;
                font-size: 11px !important;
                border-bottom: none !important;
            }
            
            .ctc-row {
                background: #059669 !important;
                color: white !important;
                font-weight: bold;
            }
            
            .ctc-row td {
                padding: 6px 8px !important;
                color: white !important;
                font-weight: bold !important;
                font-size: 11px !important;
                border-bottom: none !important;
            }
            
            /* ATTENDANCE */
            .attendance-section {
                padding: 0 30px 6px 30px;
            }
            
            .attendance-section h3 {
                background: #1e3a8a;
                color: white;
                padding: 6px 10px;
                font-size: 10px;
                font-weight: bold;
                margin-bottom: 8px;
                text-transform: uppercase;
                letter-spacing: 1px;
            }
            
            .attendance-table {
                width: 100%;
                border-collapse: collapse;
                border: 1px solid #dee2e6;
            }
            
            .attendance-table td {
                padding: 7px;
                font-size: 10px;
                border-right: 1px solid #dee2e6;
                text-align: center;
                line-height: 1.4;
            }
            
            .attendance-table td:last-child {
                border-right: none;
            }
            
            .attendance-table .label-cell {
                background: #f8f9fa;
                color: #495057;
                font-weight: normal;
            }
            
            .attendance-table .value-cell {
                background: white;
                color: #212529;
                font-weight: bold;
            }
            
            /* NET SALARY */
            .net-salary {
                background: #1e3a8a;
                color: white;
                padding: 7px 30px;
                text-align: center;
                margin: 0;
                border-top: 2px solid #1e40af;
                border-bottom: 2px solid #1e40af;
            }
            
            .net-salary-label {
                font-size: 11px;
                font-weight: bold;
                margin-bottom: 3px;
                letter-spacing: 2px;
            }
            
            .net-salary-amount {
                font-size: 20px;
                font-weight: bold;
                font-family: "Courier New", monospace;
            }
            
            /* SIGNATURE */
            .signature-section {
                padding: 8px 30px 5px 30px;
                display: flex;
                justify-content: space-between;
                align-items: flex-end;
                border-top: 2px solid #dee2e6;
            }
            
            .signature-box {
                width: 45%;
            }
            
            .signature-name {
                font-family: "Brush Script MT", cursive;
                font-size: 18px;
                color: #1e3a8a;
                margin-bottom: 2px;
                font-weight: bold;
                text-align: center;
            }
            
            .signature-line {
                border-top: 2px solid #212529;
                margin: 2px 0;
            }
            
            .signature-label {
                font-size: 8px;
                color: #495057;
                font-weight: bold;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                text-align: center;
            }
            
            .signature-title {
                font-size: 7px;
                color: #6c757d;
                margin-top: 1px;
                font-style: italic;
                text-align: center;
            }
            
            /* FOOTER - REMOVED */
            
            /* PRINT BUTTON */
            .print-button {
                text-align: center;
                padding: 10px;
                background: transparent;
            }
            
            .btn-print {
                background: #1e3a8a;
                color: white;
                padding: 8px 25px;
                border: none;
                border-radius: 5px;
                font-size: 12px;
                font-weight: 600;
                cursor: pointer;
                text-transform: uppercase;
                letter-spacing: 1px;
            }
            
            .btn-print:hover {
                background: #1e40af;
            }
        </style>
    </head>
    <body>
        <div class="payslip-container">
            
            <!-- HEADER -->
            <div class="header">';
    
    // Logo Section - Centered
    if(!empty($logo_base64)) {
        $html .= '
                <div class="logo-section">
                    <img src="' . $logo_base64 . '" alt="Company Logo">
                </div>';
    }
    
    $html .= '
                <div class="company-name">' . strtoupper(htmlspecialchars($company_name)) . '</div>
                
                <div class="payslip-header-bar">
                    <div class="payslip-title">SALARY SLIP</div>
                    <div class="payslip-period">Month: ' . $month_name . ' ' . $year . '</div>
                </div>
            </div>
            
            <!-- EMPLOYEE INFO -->
            <div class="employee-section">
                <table class="info-table">
                    <tr>
                        <td>Employee Name:</td>
                        <td>' . strtoupper(htmlspecialchars($data['name'])) . '</td>
                        <td>Employee ID:</td>
                        <td>' . htmlspecialchars($data['emp_code']) . '</td>
                    </tr>
                    <tr>
                        <td>Designation:</td>
                        <td>' . htmlspecialchars($data['designation']) . '</td>
                        <td>Department:</td>
                        <td>' . htmlspecialchars($data['department']) . '</td>
                    </tr>
                    <tr>
                        <td>Pay Date:</td>
                        <td>' . $calculated_pay_date . '</td>
                        <td>Pay Period:</td>
                        <td>' . $month_name . ' ' . $year . '</td>
                    </tr>
                </table>
            </div>
            
            <!-- SALARY DETAILS -->
            <div class="salary-section">
                <div class="salary-grid">
                    
                    <!-- EARNINGS -->
                    <div class="salary-column">
                        <h3>Earnings</h3>
                        <table class="salary-table">
                            <tr>
                                <td>Basic Salary</td>
                                <td>₹ ' . number_format($data['basic_salary'], 2) . '</td>
                            </tr>
                            <tr>
                                <td>HRA</td>
                                <td>₹ ' . number_format($data['hra'], 2) . '</td>
                            </tr>
                            <tr>
                                <td>Conveyance</td>
                                <td>₹ ' . number_format($data['conveyance'], 2) . '</td>
                            </tr>
                            <tr>
                                <td>Special Allowance</td>
                                <td>₹ ' . number_format($data['special_allowance'], 2) . '</td>
                            </tr>';
    
    $html .= '
                            <tr class="total-row">
                                <td>GROSS EARNINGS</td>
                                <td>₹ ' . number_format($gross_pay, 2) . '</td>
                            </tr>';
    
    // Show additional earnings if any exist
    if(floatval($data['arrears']) > 0 || $ot_value > 0 || floatval($data['overtime']) > 0 || floatval($data['incentives']) > 0) {
        if(floatval($data['arrears']) > 0) {
            $html .= '
                            <tr>
                                <td>Arrears</td>
                                <td>₹ ' . number_format($data['arrears'], 2) . '</td>
                            </tr>';
        }
        if($ot_value > 0) {
            $html .= '
                            <tr>
                                <td>OT Amount</td>
                                <td>₹ ' . number_format($ot_value, 2) . '</td>
                            </tr>';
        }
        if(floatval($data['overtime']) > 0) {
            $html .= '
                            <tr>
                                <td>Overtime</td>
                                <td>₹ ' . number_format($data['overtime'], 2) . '</td>
                            </tr>';
        }
        if(floatval($data['incentives']) > 0) {
            $html .= '
                            <tr>
                                <td>Incentives</td>
                                <td>₹ ' . number_format($data['incentives'], 2) . '</td>
                            </tr>';
        }
    }
    
    // Show PF only if greater than 0
    if($pf_employer > 0) {
        $html .= '
                            <tr>
                                <td>Provident Fund</td>
                                <td>₹ ' . number_format($pf_employer, 2) . '</td>
                            </tr>
                            <tr class="ctc-row">
                                <td>TOTAL CTC</td>
                                <td>₹ ' . number_format($data['total_ctc'], 2) . '</td>
                            </tr>';
    }
    
    $html .= '
                        </table>
                    </div>
                    
                    <!-- DEDUCTIONS -->
                    <div class="salary-column">
                        <h3>Deductions</h3>
                        <table class="salary-table">';
    
    // Show PF only if greater than 0
    if(floatval($data['pf']) > 0) {
        $html .= '
                            <tr>
                                <td>Provident Fund</td>
                                <td>₹ ' . number_format($data['pf'], 2) . '</td>
                            </tr>';
    }
    
    if(floatval($data['esi']) > 0) {
        $html .= '
                            <tr>
                                <td>ESI</td>
                                <td>₹ ' . number_format($data['esi'], 2) . '</td>
                            </tr>';
    }
    
    if(floatval($data['pt']) > 0) {
        $html .= '
                            <tr>
                                <td>Professional Tax</td>
                                <td>₹ ' . number_format($data['pt'], 2) . '</td>
                            </tr>';
    }
    
    if(floatval($data['tds']) > 0) {
        $html .= '
                            <tr>
                                <td>TDS</td>
                                <td>₹ ' . number_format($data['tds'], 2) . '</td>
                            </tr>';
    }
    
    if($absent_deduction > 0) {
        $html .= '
                            <tr>
                                <td>Absent Deduction (' . $data['absent_days'] . ' days)</td>
                                <td>₹ ' . number_format($absent_deduction, 2) . '</td>
                            </tr>';
    }
    
    if(floatval($data['advance_salary']) > 0) {
        $html .= '
                            <tr>
                                <td>Advance Salary</td>
                                <td>₹ ' . number_format($data['advance_salary'], 2) . '</td>
                            </tr>';
    }
    
    if(floatval($data['penalty']) > 0) {
        $html .= '
                            <tr>
                                <td>Penalty</td>
                                <td>₹ ' . number_format($data['penalty'], 2) . '</td>
                            </tr>';
    }
    
    // Show Total Deductions row or No Deductions message
    if($total_deductions > 0) {
        $html .= '
                            <tr class="total-row">
                                <td>TOTAL DEDUCTIONS</td>
                                <td>₹ ' . number_format($total_deductions, 2) . '</td>
                            </tr>';
    } else {
        $html .= '
                            <tr>
                                <td colspan="2" style="text-align:center; font-style:italic; color:#6c757d; padding:15px;">No Deductions</td>
                            </tr>';
    }
    
    $html .= '
                        </table>
                    </div>
                    
                </div>
            </div>
            
            <!-- ATTENDANCE -->
            <div class="attendance-section">
                <h3>Attendance Summary</h3>
                <table class="attendance-table">
                    <tr>
                        <td class="label-cell">Total Working Days</td>
                        <td class="label-cell">Days Present</td>
                        <td class="label-cell">Days Absent</td>
                    </tr>
                    <tr>
                        <td class="value-cell"><strong>' . $data['working_days'] . '</strong></td>
                        <td class="value-cell"><strong>' . $data['present_days'] . '</strong></td>
                        <td class="value-cell"><strong>' . $data['absent_days'] . '</strong></td>
                    </tr>
                </table>
            </div>
            
            <!-- NET SALARY -->
            <div class="net-salary">
                <div class="net-salary-label">NET SALARY PAYABLE</div>
                <div class="net-salary-amount">₹ ' . number_format($data['net_salary'], 2) . '</div>
            </div>
            
            <!-- SIGNATURES -->
            <div class="signature-section">
                <div class="signature-box">
                    <div class="signature-line"></div>
                    <div class="signature-label">Employee Signature</div>
                    <div class="signature-title">Acknowledged By</div>
                </div>
                <div class="signature-box">
                    <div class="signature-name">Abishek Veeraswamy</div>
                    <div class="signature-line"></div>
                    <div class="signature-label">Authorized Signatory</div>
                    <div class="signature-title">Managing Director</div>
                </div>
            </div>
            
            <!-- FOOTER -->
            
        </div>
        
        <!-- PRINT BUTTON -->
        <div class="print-button no-print">
            <button class="btn-print" onclick="window.print()">PRINT / SAVE AS PDF</button>
        </div>
        
    </body>
    </html>';
    
    echo $html;
    exit;
}

// ============================================================================
// BULK MARK HOLIDAY FOR SPECIFIC EMPLOYEES
// ============================================================================
if(isset($_POST['bulk_mark_holiday'])) {
    $employee_ids = isset($_POST['employee_ids']) ? $_POST['employee_ids'] : array();
    $from_date = mysqli_real_escape_string($dbConn, $_POST['from_date']);
    $to_date = mysqli_real_escape_string($dbConn, $_POST['to_date']);
    $status = mysqli_real_escape_string($dbConn, $_POST['mark_status']);
    $reason = mysqli_real_escape_string($dbConn, $_POST['mark_reason']);
    
    if(empty($employee_ids)) {
        $_SESSION['msg'] = "❌ Please select at least one employee";
    } else {
        $marked_count = 0;
        $start = new DateTime($from_date);
        $end = new DateTime($to_date);
        $interval = $end->diff($start)->days + 1;
        
        foreach($employee_ids as $emp_id) {
            $emp_id = intval($emp_id);
            
            for($d = 0; $d < $interval; $d++) {
                $current_date = date('Y-m-d', strtotime($from_date . " +$d days"));
                
                // Skip Sundays
                $day_of_week = date('N', strtotime($current_date));
                if($day_of_week == 7) continue;
                
                $check = mysqli_query($dbConn, "SELECT id FROM hr_attendance_overrides WHERE employee_id = $emp_id AND attendance_date = '$current_date'");
                
                if(mysqli_num_rows($check) > 0) {
                    mysqli_query($dbConn, "UPDATE hr_attendance_overrides SET status = '$status', reason = '$reason', created_by = '$currentUserName' WHERE employee_id = $emp_id AND attendance_date = '$current_date'");
                } else {
                    mysqli_query($dbConn, "INSERT INTO hr_attendance_overrides (employee_id, attendance_date, status, reason, created_by) VALUES ($emp_id, '$current_date', '$status', '$reason', '$currentUserName')");
                }
                $marked_count++;
            }
        }
        
        $_SESSION['msg'] = "✓ Marked $marked_count days for " . count($employee_ids) . " employee(s) as " . ucfirst($status) . ". Click 'Generate Payroll' to update salaries.";
    }
    
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// ============================================================================
// DELETE OVERRIDE
// ============================================================================
if(isset($_POST['delete_override'])) {
    $override_id = intval($_POST['override_id']);
    mysqli_query($dbConn, "DELETE FROM hr_attendance_overrides WHERE id = $override_id");
    $_SESSION['msg'] = "✓ Override removed successfully";
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// ============================================================================
// DELETE PAYROLL RECORD
// ============================================================================
if(isset($_POST['delete_payroll'])) {
    try {
        $payroll_id = intval($_POST['payroll_id']);
        
        $check_query = mysqli_query($dbConn, "SELECT e.name, p.pay_month, p.pay_year FROM hr_payroll p INNER JOIN hr_employees e ON p.employee_id = e.id WHERE p.id = $payroll_id LIMIT 1");
        
        if($check_query && mysqli_num_rows($check_query) > 0) {
            $record = mysqli_fetch_assoc($check_query);
            $emp_name = $record['name'];
            $month = date("F", mktime(0, 0, 0, $record['pay_month'], 10));
            $year = $record['pay_year'];
            
            $delete_sql = "DELETE FROM hr_payroll WHERE id = $payroll_id";
            
            if(mysqli_query($dbConn, $delete_sql)) {
                $_SESSION['msg'] = "✓ Payroll record deleted successfully for <strong>$emp_name</strong> ($month $year)";
            } else {
                throw new Exception(mysqli_error($dbConn));
            }
        } else {
            throw new Exception("Payroll record not found");
        }
        
    } catch(Exception $e) {
        $_SESSION['msg'] = "Error deleting record: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// ============================================================================
// PERFECT SALARY CALCULATION FUNCTION
// UPDATED: Uses FIXED 26 days for ALL months (ignores working days, Sundays, holidays)
// ============================================================================
function calculatePerfectSalary($gross_pay, $working_days, $present_days) {
    // FIXED: Always use 26 days for salary calculation
    // Working days parameter is ignored - only used for attendance tracking
    $standard_days = 26;
    $per_day = round($gross_pay / $standard_days, 2);
    
    // Earned amount based on actual present days
    $earned_amount = $per_day * $present_days;
    
    // Absent days calculation (for display only, not used in salary calc)
    $absent_days = $working_days - $present_days;
    $absent_deduction = $per_day * $absent_days;
    
    // Net salary is simply the earned amount
    $net_salary = round($earned_amount, 2);
    
    // Employee-favorable rounding
    if($net_salary > 0) {
        $decimal = $net_salary - floor($net_salary);
        if($decimal >= 0.50) {
            $net_salary = ceil($net_salary);
        }
    }
    
    return array(
        'per_day' => $per_day,
        'earned' => $earned_amount,
        'absent_deduction' => round($absent_deduction, 2),
        'net_salary' => $net_salary
    );
}

// ============================================================================
// CALCULATE ATTENDANCE WITH OVERRIDES
// ============================================================================
function calculateAttendanceWithOverrides($dbConn, $emp_id, $emp_code, $month, $year, $working_days_base) {
    $total_days = cal_days_in_month(CAL_GREGORIAN, $month, $year);
    $start_date = "$year-" . str_pad($month, 2, '0', STR_PAD_LEFT) . "-01";
    $end_date = "$year-" . str_pad($month, 2, '0', STR_PAD_LEFT) . "-" . str_pad($total_days, 2, '0', STR_PAD_LEFT);
    
    // Count regular attendance
    $att_query = "SELECT COUNT(DISTINCT date) as days_present 
                  FROM hr_attendance 
                  WHERE employee_id = '$emp_code' 
                  AND date BETWEEN '$start_date' AND '$end_date'
                  AND status IN ('present', 'late', 'half_day')";
    
    $att_result = mysqli_query($dbConn, $att_query);
    $att_data = mysqli_fetch_assoc($att_result);
    $base_present = intval($att_data['days_present']);
    
    // Check for overrides
    $override_query = "SELECT COUNT(*) as override_count 
                       FROM hr_attendance_overrides 
                       WHERE employee_id = $emp_id 
                       AND attendance_date BETWEEN '$start_date' AND '$end_date'
                       AND status IN ('holiday', 'leave', 'present')";
    
    $override_result = mysqli_query($dbConn, $override_query);
    $override_data = mysqli_fetch_assoc($override_result);
    $override_days = intval($override_data['override_count']);
    
    $total_present = $base_present + $override_days;
    
    return array(
        'present_days' => $total_present,
        'has_overrides' => ($override_days > 0)
    );
}

// ============================================================================
// EXPORT CSV FUNCTIONALITY
// ============================================================================
if(isset($_POST['export_csv'])) {
    $from_date = $_POST['export_from'];
    $to_date = $_POST['export_to'];
    
    $filename = "Payroll_Report_" . $from_date . "_to_" . $to_date . ".csv";
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=' . $filename);
    
    $output = fopen('php://output', 'w');
    
    fputcsv($output, array(
        'Payroll Month', 'Year', 'Employee ID', 'Name',
        'Basic', 'HRA', 'Conveyance', 'Special Allowance', 'Gross Pay', 
        'Arrears', 'OT Amount', 'Overtime', 'Incentives', 
        'PF (Employee)', 'PF (Employer)', 'Total CTC', 
        'Working Days', 'Present Days', 'Absent Days', 
        'Advance Salary', 'Penalty', 'Net Salary', 'Pay Date'
    ));
    
    $sql = "SELECT p.*, e.name, e.employee_id as emp_code, e.status 
            FROM hr_payroll p 
            INNER JOIN hr_employees e ON p.employee_id = e.id 
            WHERE CONCAT(p.pay_year, '-', LPAD(p.pay_month, 2, '0'), '-01') >= '$from_date' 
            AND CONCAT(p.pay_year, '-', LPAD(p.pay_month, 2, '0'), '-01') <= '$to_date'
            AND e.status = 'active'
            ORDER BY p.pay_year DESC, p.pay_month DESC, e.name ASC";
            
    $result = mysqli_query($dbConn, $sql);
    
    while($row = mysqli_fetch_assoc($result)) {
        $monthName = date("F", mktime(0, 0, 0, $row['pay_month'], 10));
        $ot_value = isset($row['ot_amount']) ? $row['ot_amount'] : $row['ot'];
        
        fputcsv($output, array(
            $monthName, $row['pay_year'], $row['emp_code'], $row['name'],
            $row['basic_salary'], $row['hra'], $row['conveyance'], $row['special_allowance'], $row['gross_pay'],
            $row['arrears'], $ot_value, $row['overtime'], $row['incentives'],
            $row['pf'], $row['pf'], $row['total_ctc'],
            $row['working_days'], $row['present_days'], $row['absent_days'],
            $row['advance_salary'], $row['penalty'], $row['net_salary'], $row['pay_date']
        ));
    }
    
    fclose($output);
    exit();
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================
function getSundaysInMonth($month, $year) {
    $sundays = 0;
    $days_in_month = cal_days_in_month(CAL_GREGORIAN, $month, $year);
    
    for($day = 1; $day <= $days_in_month; $day++) {
        $day_of_week = date('w', mktime(0, 0, 0, $month, $day, $year));
        if($day_of_week == 0) { 
            $sundays++;
        }
    }
    
    return $sundays;
}

// ============================================================================
// AUTO-GENERATE/UPDATE PAYROLL WITH PERFECT CALCULATION & HOLIDAY FIX
// ============================================================================
if(isset($_POST['auto_generate'])) {
    try {
        $current_month = date('n');
        $current_year = date('Y');
        // Use the input value directly
        $holidays = intval($_POST['holidays_count']);
        
        $total_days_in_month = cal_days_in_month(CAL_GREGORIAN, $current_month, $current_year);
        $sundays = getSundaysInMonth($current_month, $current_year);
        $working_days = $total_days_in_month - $sundays - $holidays;
        
        // Ensure database remembers this holiday count
        mysqli_query($dbConn, "UPDATE hr_payroll SET holidays_in_month = $holidays, working_days = $working_days WHERE pay_month = $current_month AND pay_year = $current_year");

        $emp_query = mysqli_query($dbConn, "SELECT id, employee_id, name, salary, employee_type, status, COALESCE(pf, 0) as employee_pf FROM hr_employees WHERE status = 'active' ORDER BY name");
        
        if(!$emp_query) {
            throw new Exception("Failed to fetch employees: " . mysqli_error($dbConn));
        }
        
        $count = 0;
        $updated = 0;
        $errors = array();
        
        // Calculate Pay Date: 10th of the NEXT month
        $pay_date = date('Y-m-d', mktime(0, 0, 0, $current_month + 1, 10, $current_year));
        
        while($emp = mysqli_fetch_assoc($emp_query)) {
            try {
                $emp_db_id = intval($emp['id']);
                $emp_code = mysqli_real_escape_string($dbConn, $emp['employee_id']);
                $emp_name = mysqli_real_escape_string($dbConn, $emp['name']);
                
                // Calculate raw attendance (Biometric + Specific Overrides)
                $att_data = calculateAttendanceWithOverrides($dbConn, $emp_db_id, $emp_code, $current_month, $current_year, $working_days);
                
                $measured_present_days = $att_data['present_days'];
                
                // Add holidays to present days (holidays are PAID days)
                // 26-day average: Employees get paid for holidays
                $calc_present_days = $measured_present_days + $holidays;
                
                // Cap at 26 days maximum (not working days, but 26-day average)
                if($calc_present_days > 26) {
                    $calc_present_days = 26;
                }
                
                // Calculate absent days for display only
                $absent_days = $working_days - $measured_present_days;
                if($absent_days < 0) $absent_days = 0;

                $gross_pay = floatval(str_replace(',', '', $emp['salary']));
                if($gross_pay <= 0) $gross_pay = 0;
                
                $basic_salary = round($gross_pay * 0.40, 2);
                $hra = round($basic_salary * 0.50, 2); 
                $conveyance = 3000;
                $special_allowance = $gross_pay - ($basic_salary + $hra + $conveyance);
                
                if($special_allowance < 0) {
                    $special_allowance = 0;
                    $hra = $gross_pay - $basic_salary - $conveyance;
                    if($hra < 0) $hra = 0;
                }
                $special_allowance = round($special_allowance, 2);
                
                $emp_type = isset($emp['employee_type']) ? $emp['employee_type'] : '';
                $is_permanent = (stripos($emp_type, 'Permanent') !== false);
                $pf = floatval($emp['employee_pf']);
                
                if($pf == 0 && $is_permanent) {
                    $pf = round($basic_salary * 0.12, 2);
                }
                if($pf < 0) $pf = 0;
                
                $esi = 0; $pt = 0; $tds = 0;
                
                // PERFECT SALARY CALCULATION - uses the adjusted present days
                $salary_calc = calculatePerfectSalary($gross_pay, $working_days, $calc_present_days);
                
                $per_day_pay = $salary_calc['per_day'];
                $net_salary = $salary_calc['net_salary'];
                $absent_deduction = $salary_calc['absent_deduction'];
                
                $total_deduction = $pf + $esi + $pt + $tds;
                $total_ctc = $gross_pay + $pf;
                $amount = $net_salary;
                
                $comment = "Auto-generated" . ($att_data['has_overrides'] ? " with overrides" : "") . " for " . date('F Y');
                $comment = mysqli_real_escape_string($dbConn, $comment);
                
                $check = mysqli_query($dbConn, "SELECT id FROM hr_payroll WHERE employee_id = $emp_db_id AND pay_month = $current_month AND pay_year = $current_year LIMIT 1");

                if($check && mysqli_num_rows($check) > 0) {
                    $existing = mysqli_fetch_assoc($check);
                    $existing_id = $existing['id'];
                    
                    $ex_query = mysqli_query($dbConn, "SELECT arrears, COALESCE(ot_amount, ot) as ot_val, overtime, incentives, advance_salary, penalty FROM hr_payroll WHERE id = $existing_id");
                    $ex_data = mysqli_fetch_assoc($ex_query);
                    
                    $arrears = floatval($ex_data['arrears']);
                    $ot_amount = floatval($ex_data['ot_val']);
                    $overtime = floatval($ex_data['overtime']);
                    $incentives = floatval($ex_data['incentives']);
                    $advance = floatval($ex_data['advance_salary']);
                    $penalty = floatval($ex_data['penalty']);
                    
                    // Recalculate based on earned amount (per day × present days)
                    $earned_amount = $salary_calc['earned'];
                    $total_earnings = $earned_amount + $arrears + $ot_amount + $overtime + $incentives;
                    $net_salary = $total_earnings - $advance - $penalty;
                    if($net_salary < 0) $net_salary = 0;
                    
                    $total_ctc = $total_earnings + $pf;
                    $amount = $net_salary;
                    
                    // UPDATED: Added pay_date = '$pay_date'
                    $sql = "UPDATE hr_payroll SET 
                        basic_salary = $basic_salary,
                        hra = $hra,
                        conveyance = $conveyance,
                        special_allowance = $special_allowance,
                        gross_pay = $gross_pay,
                        pf = $pf,
                        total_deduction = $total_deduction,
                        total_ctc = $total_ctc,
                        present_days = $calc_present_days,
                        absent_days = $absent_days,
                        working_days = $working_days,
                        weekends_in_month = $sundays,
                        holidays_in_month = $holidays,
                        net_salary = $net_salary,
                        per_day_salary = $per_day_pay,
                        amount = $amount,
                        pay_date = '$pay_date',
                        comment = '$comment'
                        WHERE id = $existing_id";
                    
                    if(mysqli_query($dbConn, $sql)) {
                        $updated++;
                    }
                    
                } else {
                    $sql = "INSERT INTO hr_payroll (
                        employee_id, 
                        basic_salary, hra, conveyance, special_allowance, gross_pay,
                        arrears, ot, overtime, incentives, ot_amount,
                        pf, esi, pt, tds, total_deduction,
                        total_ctc, 
                        pay_date, pay_month, pay_year, amount,
                        present_days, absent_days, working_days, 
                        weekends_in_month, holidays_in_month, weekends_worked, holidays_worked,
                        advance_salary, net_salary, per_day_salary, penalty, comment
                    ) VALUES (
                        $emp_db_id,
                        $basic_salary, $hra, $conveyance, $special_allowance, $gross_pay,
                        0, 0, 0, 0, 0,
                        $pf, $esi, $pt, $tds, $total_deduction,
                        $total_ctc,
                        '$pay_date', $current_month, $current_year, $amount,
                        $calc_present_days, $absent_days, $working_days,
                        $sundays, $holidays, 0, 0,
                        0, $net_salary, $per_day_pay, 0, '$comment'
                    )";
                    
                    if(mysqli_query($dbConn, $sql)) {
                        $count++;
                    } else {
                        $errors[] = "$emp_name: " . mysqli_error($dbConn);
                    }
                }
                
            } catch(Exception $e) {
                $errors[] = "$emp_name: " . $e->getMessage();
            }
        }
        
        $msg = "✓ Processed payroll based on Holidays: $holidays";
        if($count > 0) $msg .= " | Created: $count";
        if($updated > 0) $msg .= " | Updated: $updated";
        if(count($errors) > 0) {
            $msg .= "<br><small style='color:#dc3545'>Errors: " . implode("; ", array_slice($errors, 0, 3)) . "</small>";
        }
        
        $_SESSION['msg'] = $msg;
        
    } catch(Exception $e) {
        $_SESSION['msg'] = "Error: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// ============================================================================
// UPDATE SINGLE PAYROLL
// ============================================================================
if(isset($_POST['update_payroll'])) {
    try {
        $id = intval($_POST['payroll_id']);
        
        $old_query = mysqli_query($dbConn, "SELECT * FROM hr_payroll WHERE id=$id LIMIT 1");
        if(!$old_query || mysqli_num_rows($old_query) == 0) {
            throw new Exception("Payroll record not found");
        }
        $old = mysqli_fetch_assoc($old_query);
        
        $arrears = floatval($_POST['arrears']);
        $ot_amount = floatval($_POST['ot_amount']);
        $overtime = floatval($_POST['overtime']);
        $incentives = floatval($_POST['incentives']);
        $advance = floatval($_POST['advance']);
        $penalty = floatval($_POST['penalty']);
        
        $base_gross = floatval($old['gross_pay']);
        $pf = floatval($old['pf']);
        
        $total_earnings = $base_gross + $arrears + $ot_amount + $overtime + $incentives;
        
        // Use stored per_day_salary or calculate using fixed 26 days average
        $standard_days = 26;
        $per_day = isset($old['per_day_salary']) && floatval($old['per_day_salary']) > 0 
                   ? floatval($old['per_day_salary']) 
                   : round($base_gross / $standard_days, 2);
        
        // Calculate earned amount based on present days
        $present_days = intval($old['present_days']);
        $earned_amount = $per_day * $present_days;
        $absent_deduction = round($per_day * intval($old['absent_days']), 2);
        
        $display_deduction = $pf + floatval($old['esi']) + floatval($old['pt']) + floatval($old['tds']);
        
        // Net salary = Earned amount + extras - deductions
        $total_earnings = $earned_amount + $arrears + $ot_amount + $overtime + $incentives;
        $net_salary = $total_earnings - $advance - $penalty;
        if($net_salary < 0) $net_salary = 0;
        
        $total_ctc = $base_gross + $pf + $arrears + $ot_amount + $overtime + $incentives;
        $amount = $net_salary;
        
        $sql = "UPDATE hr_payroll SET 
            arrears = $arrears, 
            ot_amount = $ot_amount,
            overtime = $overtime,
            incentives = $incentives,
            advance_salary = $advance, 
            penalty = $penalty,
            total_deduction = $display_deduction, 
            net_salary = $net_salary, 
            total_ctc = $total_ctc,
            amount = $amount
            WHERE id = $id";
        
        if(mysqli_query($dbConn, $sql)) {
            $_SESSION['msg'] = "✓ Payroll updated successfully";
        } else {
            throw new Exception(mysqli_error($dbConn));
        }
        
    } catch(Exception $e) {
        $_SESSION['msg'] = "Error updating: " . $e->getMessage();
    }
    
    header("Location: " . $_SERVER['PHP_SELF']);
    exit;
}

// ============================================================================
// FETCH DATA
// ============================================================================
$current_month = date('n');
$current_year = date('Y');

$filter_from = isset($_POST['filter_from']) ? $_POST['filter_from'] : date('Y-m-01');
$filter_to = isset($_POST['filter_to']) ? $_POST['filter_to'] : date('Y-m-t');

$where_clause = "CONCAT(p.pay_year, '-', LPAD(p.pay_month, 2, '0'), '-01') >= '$filter_from' 
                 AND CONCAT(p.pay_year, '-', LPAD(p.pay_month, 2, '0'), '-01') <= '$filter_to'
                 AND e.status = 'active'";

$data = mysqli_query($dbConn, "
    SELECT p.*, e.name, e.employee_id as emp_code, e.status 
    FROM hr_payroll p 
    INNER JOIN hr_employees e ON p.employee_id = e.id 
    WHERE $where_clause
    ORDER BY p.pay_year DESC, p.pay_month DESC, e.name ASC
");

if(!$data) {
    die("Error fetching payroll data: " . mysqli_error($dbConn));
}

$total_records = mysqli_num_rows($data);

$total_days = cal_days_in_month(CAL_GREGORIAN, $current_month, $current_year);
$sundays = getSundaysInMonth($current_month, $current_year);

$holiday_query = mysqli_query($dbConn, "SELECT holidays_in_month FROM hr_payroll WHERE pay_month = $current_month AND pay_year = $current_year LIMIT 1");
$holidays = 0;
if($holiday_query && mysqli_num_rows($holiday_query) > 0) {
    $h_row = mysqli_fetch_assoc($holiday_query);
    $holidays = intval($h_row['holidays_in_month']);
}

$working_days = $total_days - $sundays - $holidays;

// Get active employees for bulk marking
$active_employees = mysqli_query($dbConn, "SELECT id, name, employee_id, position FROM hr_employees WHERE status='active' ORDER BY name ASC");

// Get overrides for current month
$overrides = mysqli_query($dbConn, "SELECT o.*, e.name, e.employee_id as emp_code 
                                    FROM hr_attendance_overrides o 
                                    INNER JOIN hr_employees e ON o.employee_id = e.id 
                                    WHERE MONTH(o.attendance_date) = $current_month AND YEAR(o.attendance_date) = $current_year
                                    ORDER BY o.attendance_date DESC, e.name ASC");

$total_gross = 0;
$total_net = 0;
$total_ctc = 0;
if($total_records > 0) {
    mysqli_data_seek($data, 0);
    while($row = mysqli_fetch_assoc($data)) {
        $total_gross += floatval($row['gross_pay']);
        $total_net += floatval($row['net_salary']);
        $total_ctc += floatval($row['total_ctc']);
    }
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <!-- Meta refresh removed to prevent losing changes while editing -->
    <title>Payroll System - <?php echo date('F Y'); ?></title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body { 
            font-family: 'Inter', sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #7e8ba3 100%);
            min-height: 100vh;
            padding: 20px;
            color: #1a202c;
        }
        
        .main-container {
            max-width: 1800px;
            margin: 0 auto;
            background: white;
            border-radius: 24px;
            box-shadow: 0 25px 50px -12px rgba(0,0,0,0.25);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 40px 50px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .header-content h1 {
            margin: 0 0 8px 0;
            font-size: 36px;
            font-weight: 900;
        }
        
        .header-content p {
            margin: 0;
            font-size: 16px;
            opacity: 0.95;
            font-weight: 500;
        }

        .btn-header-back {
            background: rgba(255, 255, 255, 0.2);
            color: white;
            padding: 12px 24px;
            border-radius: 12px;
            font-weight: 600;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 10px;
            transition: all 0.3s;
            border: 1px solid rgba(255,255,255,0.3);
        }

        .btn-header-back:hover {
            background: white;
            color: #1e3c72;
            text-decoration: none;
        }
        
        .content {
            padding: 40px 50px;
        }
        
        .alert-modern {
            padding: 18px 24px;
            border-radius: 12px;
            margin-bottom: 30px;
            font-weight: 600;
            font-size: 15px;
            border: none;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
            background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%);
            color: #155724;
            border-left: 5px solid #28a745;
        }
        
        .month-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 35px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
            color: white;
            padding: 24px;
            border-radius: 16px;
            box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1);
            transition: all 0.3s;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 20px 25px -5px rgba(0,0,0,0.2);
        }
        
        .stat-card.green { background: linear-gradient(135deg, #10b981 0%, #059669 100%); }
        .stat-card.purple { background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); }
        .stat-card.orange { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); }
        .stat-card.red { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); }
        .stat-card.teal { background: linear-gradient(135deg, #14b8a6 0%, #0d9488 100%); }
        .stat-card.gray { background: linear-gradient(135deg, #6b7280 0%, #4b5563 100%); }
        
        .stat-label {
            font-size: 13px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 1px;
            opacity: 0.95;
            margin-bottom: 8px;
        }
        
        .stat-value {
            font-size: 32px;
            font-weight: 900;
            line-height: 1;
        }
        
        .control-section {
            background: linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%);
            border: 2px solid #3b82f6;
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 35px;
        }
        
        .control-row {
            display: flex;
            gap: 20px;
            align-items: flex-end;
            justify-content: space-between;
            flex-wrap: wrap;
        }
        
        .form-group label {
            display: block;
            font-weight: 700;
            margin-bottom: 8px;
            color: #1e40af;
            font-size: 14px;
        }
        
        .form-control {
            padding: 10px 15px;
            border: 2px solid #bfdbfe;
            border-radius: 10px;
            font-size: 14px;
            font-weight: 600;
            background: white;
            transition: all 0.3s;
        }
        
        .form-control:focus {
            border-color: #3b82f6;
            outline: none;
            box-shadow: 0 0 0 3px rgba(59,130,246,0.1);
        }
        
        .btn-modern {
            padding: 10px 24px;
            border-radius: 10px;
            font-weight: 700;
            font-size: 14px;
            border: none;
            cursor: pointer;
            transition: all 0.3s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
        }
        
        .btn-modern:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgba(0,0,0,0.2);
        }
        
        .btn-primary { background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); color: white; }
        .btn-success { background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; }
        .btn-warning { background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); color: white; }
        .btn-danger { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; }
        
        .table-wrapper {
            background: white;
            border-radius: 16px;
            border: 2px solid #e5e7eb;
            overflow-x: auto;
            overflow-y: auto;
            max-height: 600px;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        .payroll-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 15px;
            min-width: 2100px;
        }
        
        .payroll-table thead {
            background: linear-gradient(135deg, #1e40af 0%, #1e3a8a 100%);
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }
        
        .payroll-table th {
            padding: 18px 16px;
            text-align: left;
            font-weight: 800;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border-right: 1px solid rgba(255,255,255,0.2);
            white-space: nowrap;
        }
        
        .payroll-table td {
            padding: 16px;
            border-bottom: 1px solid #e5e7eb;
            font-size: 15px;
            font-weight: 500;
            white-space: nowrap;
        }
        
        .payroll-table tbody tr:hover {
            background: #f8fafc;
        }
        
        .payroll-table tbody tr:nth-child(even) {
            background: #fafafa;
        }
        
        .action-btn {
            width: 36px;
            height: 36px;
            border-radius: 8px;
            border: none;
            cursor: pointer;
            transition: all 0.3s;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: white;
            margin-right: 5px;
        }
        
        .action-btn.edit {
            background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
        }
        
        .action-btn.download {
            background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        }

        .action-btn.delete {
            background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
        }
        
        .action-btn:hover {
            transform: scale(1.1);
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.2);
        }
        
        .totals-section {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 24px 30px;
            border-radius: 12px;
            margin-top: 20px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
        }
        
        .totals-section .total-item {
            text-align: center;
        }
        
        .totals-section .total-label {
            font-size: 13px;
            font-weight: 700;
            text-transform: uppercase;
            opacity: 0.9;
            margin-bottom: 8px;
        }
        
        .totals-section .total-value {
            font-size: 28px;
            font-weight: 900;
        }
        
        .empty-state {
            text-align: center;
            padding: 80px 40px;
            color: #64748b;
        }
        
        .empty-state i {
            font-size: 80px;
            color: #cbd5e1;
            margin-bottom: 24px;
        }
        
        .modal-content {
            border-radius: 20px;
            border: none;
            box-shadow: 0 25px 50px -12px rgba(0,0,0,0.25);
        }
        
        .modal-header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            border-radius: 20px 20px 0 0;
            padding: 24px 30px;
            border: none;
        }
        
        .modal-body {
            padding: 30px;
        }
        
        .employee-checkbox { width: 18px; height: 18px; cursor: pointer; margin-right: 8px; }
        
        .override-section {
            background: #fef3c7;
            border: 2px solid #f59e0b;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 25px;
        }
    </style>
</head>
<body>

<div class="main-container">
    <div class="header">
        <div class="header-content">
            <h1><i class="fa fa-calculator"></i> Payroll System - <?php echo date('F Y'); ?></h1>
        </div>
        <div>
            <a href="<?php echo $isAdmin ? '/dashboard/index.php' : '/dashboard/raise-a-ticket.php'; ?>" class="btn-header-back">
                <i class="fa fa-arrow-left"></i> Back to Dashboard
            </a>
        </div>
    </div>

    <div class="content">
        <?php if(isset($_SESSION['msg'])): ?>
        <div class="alert-modern">
            <i class="fa fa-check-circle"></i> <?php echo $_SESSION['msg']; unset($_SESSION['msg']); ?>
        </div>
        <?php endif; ?>

        <!-- MONTH STATISTICS -->
        <div class="month-stats">
            <div class="stat-card">
                <div class="stat-label"><i class="fa fa-calendar"></i> Current Month</div>
                <div class="stat-value"><?php echo date('F Y'); ?></div>
            </div>
            <div class="stat-card orange">
                <div class="stat-label"><i class="fa fa-flag"></i> Holidays</div>
                <div class="stat-value"><?php echo $holidays; ?></div>
            </div>
        </div>

        <!-- CONTROL SECTION -->
        <div class="control-section">
            <div class="control-row">
                
                <!-- LEFT SIDE: Holidays and Generate -->
                <div style="display: flex; gap: 15px; align-items: flex-end; flex-wrap: wrap;">
                    
                    <!-- Combined Form for Holidays and Generation -->
                    <form method="POST" style="display: inline-flex; gap: 10px; align-items: flex-end;">
                        <div>
                            <label style="margin-bottom:5px;font-size:12px; color:#1e40af; font-weight:700;">Holidays</label>
                            <input type="number" name="holidays_count" value="<?php echo $holidays; ?>" min="0" max="31" class="form-control" style="width: 80px;" required>
                        </div>
                        <button type="submit" name="auto_generate" class="btn-modern btn-success">
                            <i class="fa fa-refresh"></i> Generate Payroll
                        </button>
                    </form>
                    
                    <button type="button" class="btn-modern" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); color: white;" data-toggle="modal" data-target="#bulkMarkSpecificModal" title="Mark holiday/leave for specific employees">
                        <i class="fa fa-users"></i> Mark Specific Employees
                    </button>
                </div>

                <!-- RIGHT SIDE: Date Filter and Export -->
                <div style="display: flex; gap: 15px; align-items: flex-end;">
                    <form method="POST" style="display: flex; gap: 10px; align-items: flex-end; background: #dbeafe; padding: 10px 15px; border-radius: 12px; border: 1px solid #93c5fd;">
                        <div>
                            <label style="margin-bottom:2px;font-size:11px;color:#1e40af">From Date</label>
                            <input type="date" name="filter_from" class="form-control" style="height:35px;font-size:13px" value="<?php echo $filter_from; ?>">
                        </div>
                        <div>
                            <label style="margin-bottom:2px;font-size:11px;color:#1e40af">To Date</label>
                            <input type="date" name="filter_to" class="form-control" style="height:35px;font-size:13px" value="<?php echo $filter_to; ?>">
                        </div>
                        <button type="submit" name="apply_filter" class="btn-modern btn-primary" style="height:35px">
                            <i class="fa fa-filter"></i> Apply
                        </button>
                    </form>
                    
                    <form method="POST" style="display: inline-flex;">
                        <input type="hidden" name="export_from" value="<?php echo $filter_from; ?>">
                        <input type="hidden" name="export_to" value="<?php echo $filter_to; ?>">
                        <button type="submit" name="export_csv" class="btn-modern btn-success" style="height:35px">
                            <i class="fa fa-download"></i> Export CSV
                        </button>
                    </form>
                </div>
            </div>
        </div>

        <!-- ATTENDANCE OVERRIDES SECTION -->
        <?php if($overrides && mysqli_num_rows($overrides) > 0): ?>
        <div class="override-section">
            <h4 style="color:#92400e; font-weight:800; margin-bottom:15px;">
                <i class="fa fa-calendar-check-o"></i> Attendance Overrides (<?php echo date('F Y'); ?>)
            </h4>
            <div class="table-responsive" style="max-height:250px; overflow-y:auto;">
                <table class="table table-condensed" style="background:white; border-radius:8px;">
                    <thead style="background:#f59e0b; color:white;">
                        <tr>
                            <th>Employee</th>
                            <th>Date</th>
                            <th>Status</th>
                            <th>Reason</th>
                            <th>By</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php while($ov = mysqli_fetch_assoc($overrides)): ?>
                        <tr>
                            <td><strong><?php echo htmlspecialchars($ov['name']); ?></strong> (<?php echo htmlspecialchars($ov['emp_code']); ?>)</td>
                            <td><?php echo date('d M Y', strtotime($ov['attendance_date'])); ?></td>
                            <td><span class="label label-<?php echo ($ov['status']=='holiday')?'warning':'info'; ?>"><?php echo ucfirst($ov['status']); ?></span></td>
                            <td><?php echo htmlspecialchars($ov['reason']); ?></td>
                            <td><small><?php echo htmlspecialchars($ov['created_by']); ?></small></td>
                            <td>
                                <form method="POST" style="display:inline;">
                                    <input type="hidden" name="override_id" value="<?php echo $ov['id']; ?>">
                                    <button type="submit" name="delete_override" class="btn btn-xs btn-danger">Remove</button>
                                </form>
                            </td>
                        </tr>
                        <?php endwhile; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- PAYROLL TABLE -->
        <?php if($total_records > 0): ?>
        <div class="table-wrapper">
            <table class="payroll-table">
                <thead>
                    <tr>
                        <th>Sl</th>
                        <th>Month/Year</th>
                        <th>Employee</th>
                        <th>Basic</th>
                        <th>HRA</th>
                        <th>Conv</th>
                        <th>Special</th>
                        <th>Gross Pay</th>
                        <th>Working Days</th>
                        <th>Per Day</th>
                        <th>Arrears</th>
                        <th>OT Amt</th>
                        <th>Overtime</th>
                        <th>Incentives</th>
                        <th>PF</th>
                        <th>Total CTC</th>
                        <th>Present</th>
                        <th>Absent</th>
                        <th>Advance</th>
                        <th>Penalty</th>
                        <th>Net Salary</th>
                        <th>Payslip</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <?php 
                    $sl = 1;
                    mysqli_data_seek($data, 0);
                    while($row = mysqli_fetch_assoc($data)): 
                        $ot_display = isset($row['ot_amount']) ? $row['ot_amount'] : $row['ot'];
                        $month_year = date("M Y", mktime(0, 0, 0, $row['pay_month'], 1, $row['pay_year']));
                        
                        // Calculate per day salary using fixed 26 days average
                        $standard_days = 26;
                        $gross = floatval($row['gross_pay']);
                        $per_day_calc = round($gross / $standard_days, 2);
                        
                        // Get stored per_day_salary or use calculated (26 days average)
                        $per_day_display = (isset($row['per_day_salary']) && floatval($row['per_day_salary']) > 0) 
                                          ? floatval($row['per_day_salary']) 
                                          : $per_day_calc;
                    ?>
                    <tr>
                        <td><?php echo $sl++; ?></td>
                        <td style="font-weight: 700; color: #8b5cf6;"><?php echo $month_year; ?></td>
                        <td style="font-weight: 700; color: #1e40af;">
                            <?php echo htmlspecialchars($row['name']); ?>
                            <br><small style="color: #64748b;"><?php echo htmlspecialchars($row['emp_code']); ?></small>
                        </td>
                        <td>₹<?php echo number_format($row['basic_salary']); ?></td>
                        <td>₹<?php echo number_format($row['hra']); ?></td>
                        <td>₹<?php echo number_format($row['conveyance']); ?></td>
                        <td>₹<?php echo number_format($row['special_allowance']); ?></td>
                        <td style="font-weight: 700; color: #3b82f6;">₹<?php echo number_format($row['gross_pay']); ?></td>
                        <td style="font-weight: 700; color: #f59e0b;"><?php echo $working_days_val; ?></td>
                        <td style="font-weight: 700; color: #8b5cf6;">₹<?php echo number_format($per_day_display, 2); ?></td>
                        <td>₹<?php echo number_format($row['arrears']); ?></td>
                        <td>₹<?php echo number_format($ot_display); ?></td>
                        <td>₹<?php echo number_format($row['overtime']); ?></td>
                        <td>₹<?php echo number_format($row['incentives']); ?></td>
                        <td style="color: #ef4444; font-weight: 700;">₹<?php echo number_format($row['pf']); ?></td>
                        <td style="font-weight: 700; color: #8b5cf6;">₹<?php echo number_format($row['total_ctc']); ?></td>
                        <td style="color: #10b981; font-weight: 700;"><?php echo $row['present_days']; ?></td>
                        <td style="color: #ef4444; font-weight: 700;"><?php echo $row['absent_days']; ?></td>
                        <td>₹<?php echo number_format($row['advance_salary']); ?></td>
                        <td>₹<?php echo number_format($row['penalty']); ?></td>
                        <td style="font-weight: 900; color: #10b981; font-size: 17px;">₹<?php echo number_format($row['net_salary']); ?></td>
                        <td>
                            <a href="?download_payslip=<?php echo $row['id']; ?>" target="_blank" class="action-btn download" title="Download Payslip">
                                <i class="fa fa-download"></i>
                            </a>
                        </td>
                        <td>
                            <button class="action-btn edit" onclick='editPayroll(<?php echo json_encode($row, JSON_HEX_APOS | JSON_HEX_QUOT); ?>)' title="Edit">
                                <i class="fa fa-pencil"></i>
                            </button>
                            <button class="action-btn delete" onclick='confirmDelete(<?php echo $row['id']; ?>, "<?php echo addslashes($row['name']); ?>", "<?php echo $month_year; ?>")' title="Delete">
                                <i class="fa fa-trash"></i>
                            </button>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                </tbody>
            </table>
        </div>

        <!-- TOTALS -->
        <div class="totals-section">
            <div class="total-item">
                <div class="total-label">Total Records</div>
                <div class="total-value"><?php echo $total_records; ?></div>
            </div>
            <div class="total-item">
                <div class="total-label">Total Gross Pay</div>
                <div class="total-value">₹<?php echo number_format($total_gross); ?></div>
            </div>
            <div class="total-item">
                <div class="total-label">Total CTC</div>
                <div class="total-value">₹<?php echo number_format($total_ctc); ?></div>
            </div>
            <div class="total-item">
                <div class="total-label">Total Net Salary</div>
                <div class="total-value">₹<?php echo number_format($total_net); ?></div>
            </div>
        </div>
        
        <?php else: ?>
        <div class="empty-state">
            <i class="fa fa-database"></i>
            <h3>No Payroll Data</h3>
            <p style="font-size: 16px;">No records found for the selected date range.</p>
        </div>
        <?php endif; ?>

    </div>
</div>

<!-- MARK SPECIFIC EMPLOYEES MODAL -->
<div class="modal fade" id="bulkMarkSpecificModal" tabindex="-1">
    <div class="modal-dialog modal-lg" style="width: 850px;">
        <div class="modal-content">
            <div class="modal-header" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);">
                <button type="button" class="close" data-dismiss="modal" style="color:white; opacity:1;">&times;</button>
                <h4 class="modal-title" style="font-size: 20px; font-weight: 800;">
                    <i class="fa fa-users"></i> Mark Holiday for Specific Employees
                </h4>
            </div>
            <form method="POST">
                <div class="modal-body" style="padding: 35px;">
                    
                    <!-- INFO BOX -->
                    <div style="background: linear-gradient(135deg, #dbeafe 0%, #bfdbfe 100%); border: 3px solid #3b82f6; border-radius: 15px; padding: 20px; margin-bottom: 30px; text-align: center;">
                        <div style="font-size: 48px; color: #3b82f6; margin-bottom: 10px;">
                            <i class="fa fa-user-plus"></i>
                        </div>
                        <h4 style="color: #1e40af; font-weight: 800; margin: 0 0 10px 0; font-size: 18px;">
                            SELECT SPECIFIC EMPLOYEES
                        </h4>
                        <p style="color: #1e40af; margin: 0; font-size: 14px; font-weight: 600;">
                            Only selected employees will be marked. Others use normal attendance.
                        </p>
                    </div>
                    
                    <!-- EMPLOYEE SELECTION -->
                    <div class="form-group" style="margin-bottom: 30px;">
                        <label style="font-weight: 800; color: #7c3aed; margin-bottom: 15px; font-size: 16px; display: block;">
                            <i class="fa fa-check-square-o"></i> Select Employees <span style="color: #ef4444;">*</span>
                        </label>

                        <!-- SEARCH BAR ADDED HERE -->
                        <div style="margin-bottom: 10px;">
                            <div class="input-group">
                                <span class="input-group-addon" style="background: #f3e8ff; border: 1px solid #d8b4fe; color: #7c3aed;"><i class="fa fa-search"></i></span>
                                <input type="text" id="modalEmpSearch" class="form-control" placeholder="Type employee name or ID to filter list..." style="border: 1px solid #d8b4fe; height: 40px; font-size: 14px;">
                            </div>
                        </div>

                        <div style="max-height: 280px; overflow-y: auto; border: 3px solid #8b5cf6; border-radius: 12px; background: #faf5ff;">
                            
                            <!-- SELECT ALL HEADER -->
                            <label style="font-weight: 800; margin: 0; padding: 15px 20px; background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); color: white; display: block; cursor: pointer; position: sticky; top: 0; z-index: 1;">
                                <input type="checkbox" id="selectAll" style="width: 22px; height: 22px; cursor: pointer; margin-right: 12px; vertical-align: middle;">
                                <span style="font-size: 16px;">Select All Employees</span>
                            </label>
                            
                            <!-- EMPLOYEE LIST -->
                            <div style="padding: 15px;" class="employee-list-container">
                                <?php mysqli_data_seek($active_employees, 0); while($emp = mysqli_fetch_assoc($active_employees)): ?>
                                <label class="emp-item" style="display: block; padding: 15px; margin-bottom: 8px; font-weight: normal; background: white; border-radius: 10px; border: 2px solid #e9d5ff; cursor: pointer; transition: all 0.3s;" onmouseover="this.style.background='#f3e8ff'; this.style.borderColor='#8b5cf6';" onmouseout="this.style.background='white'; this.style.borderColor='#e9d5ff';">
                                    <input type="checkbox" name="employee_ids[]" value="<?php echo $emp['id']; ?>" class="employee-checkbox" style="width: 20px; height: 20px; cursor: pointer; margin-right: 12px; vertical-align: middle;">
                                    <strong style="color: #7c3aed; font-size: 15px;"><?php echo htmlspecialchars($emp['name']); ?></strong>
                                    <span style="color: #64748b; font-size: 14px; margin-left: 8px;">
                                        (<?php echo htmlspecialchars($emp['employee_id']); ?>)
                                    </span>
                                    <span style="color: #8b5cf6; font-size: 13px; margin-left: 8px;">
                                        • <?php echo htmlspecialchars($emp['position']); ?>
                                    </span>
                                </label>
                                <?php endwhile; ?>
                            </div>
                        </div>
                        <small style="color: #7c3aed; margin-top: 10px; display: block; font-weight: 600; font-size: 13px;">
                            <i class="fa fa-lightbulb-o"></i> Tip: Only check employees who were on holiday/leave. Others will use their actual attendance.
                        </small>
                    </div>
                    
                    <!-- DATE FIELDS -->
                    <div style="background: #faf5ff; padding: 25px; border-radius: 12px; margin-bottom: 25px;">
                        <div class="row">
                            <div class="col-md-6">
                                <div class="form-group">
                                    <label style="font-weight: 800; color: #7c3aed; margin-bottom: 10px; font-size: 15px; display: block;">
                                        <i class="fa fa-calendar"></i> From Date <span style="color: #ef4444;">*</span>
                                    </label>
                                    <input type="date" name="from_date" class="form-control" required 
                                           style="height: 50px; padding: 12px 15px; border: 3px solid #8b5cf6; border-radius: 10px; font-weight: 700; font-size: 16px;">
                                </div>
                            </div>
                            <div class="col-md-6">
                                <div class="form-group">
                                    <label style="font-weight: 800; color: #7c3aed; margin-bottom: 10px; font-size: 15px; display: block;">
                                        <i class="fa fa-calendar"></i> To Date <span style="color: #ef4444;">*</span>
                                    </label>
                                    <input type="date" name="to_date" class="form-control" required 
                                           style="height: 50px; padding: 12px 15px; border: 3px solid #8b5cf6; border-radius: 10px; font-weight: 700; font-size: 16px;">
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- MARK AS FIELD -->
                    <div class="form-group" style="margin-bottom: 25px;">
                        <label style="font-weight: 800; color: #7c3aed; margin-bottom: 10px; font-size: 15px; display: block;">
                            <i class="fa fa-tag"></i> Mark As <span style="color: #ef4444;">*</span>
                        </label>
                        <select name="mark_status" class="form-control" required 
                                style="height: 50px; padding: 12px 15px; border: 3px solid #8b5cf6; border-radius: 10px; font-weight: 700; font-size: 16px; background: white;">
                            <option value="">-- Select Status --</option>
                            <option value="holiday">🏖️ Holiday (Paid - Won't count as absent)</option>
                            <option value="leave">📅 Leave (Paid - Won't count as absent)</option>
                            <option value="present">✅ Present (Force mark as present)</option>
                            <option value="absent">❌ Absent (Will deduct from salary)</option>
                        </select>
                    </div>
                    
                    <!-- REASON FIELD -->
                    <div class="form-group">
                        <label style="font-weight: 800; color: #7c3aed; margin-bottom: 10px; font-size: 15px; display: block;">
                            <i class="fa fa-comment"></i> Reason (Optional)
                        </label>
                        <textarea name="mark_reason" class="form-control" rows="3" 
                                  placeholder="E.g., Forgot to mark attendance, Personal leave, Sick leave, Medical emergency, etc." 
                                  style="padding: 15px; border: 3px solid #8b5cf6; border-radius: 10px; font-weight: 600; font-size: 15px; resize: vertical;"></textarea>
                    </div>
                </div>
                
                <div class="modal-footer" style="background: #faf5ff; padding: 20px 35px; border-top: 3px solid #8b5cf6;">
                    <button type="button" class="btn btn-default" data-dismiss="modal" style="padding: 12px 25px; font-weight: 700; font-size: 15px;">
                        <i class="fa fa-times"></i> Cancel
                    </button>
                    <button type="submit" name="bulk_mark_holiday" class="btn-modern" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); color: white; padding: 12px 35px; font-size: 16px; font-weight: 800;">
                        <i class="fa fa-check-circle"></i> Mark Selected Employees
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- EDIT MODAL -->
<div id="editModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal" style="color: white;">&times;</button>
        <h4 class="modal-title"><i class="fa fa-edit"></i> Edit Payroll</h4>
      </div>
      <form method="POST">
          <div class="modal-body">
            <input type="hidden" name="update_payroll" value="1">
            <input type="hidden" name="payroll_id" id="m_id">
            <div style="background: linear-gradient(135deg, #dbeafe 0%, #bfdbfe 100%); padding: 20px; border-radius: 12px; margin-bottom: 25px;">
                <strong id="m_emp_name" style="color: #1e40af; font-size: 18px;"></strong>
                <br><small id="m_emp_code" style="color: #64748b; font-weight: 600;"></small>
            </div>
            <h5 style="color: #10b981; font-weight: 800; border-bottom: 3px solid #10b981; padding-bottom: 10px; margin-bottom: 20px;">
                <i class="fa fa-plus-circle"></i> Additional Earnings
            </h5>
            <div class="row">
                <div class="col-xs-3"><label>Arrears</label><input type="number" step="0.01" name="arrears" id="m_arrears" class="form-control"></div>
                <div class="col-xs-3"><label>OT Amount</label><input type="number" step="0.01" name="ot_amount" id="m_ot_amount" class="form-control"></div>
                <div class="col-xs-3"><label>Overtime</label><input type="number" step="0.01" name="overtime" id="m_overtime" class="form-control"></div>
                <div class="col-xs-3"><label>Incentives</label><input type="number" step="0.01" name="incentives" id="m_incentives" class="form-control"></div>
            </div>
            <h5 style="color: #ef4444; font-weight: 800; border-bottom: 3px solid #ef4444; padding-bottom: 10px; margin: 25px 0 20px 0;">
                <i class="fa fa-minus-circle"></i> Deductions
            </h5>
            <div class="row">
                <div class="col-xs-6"><label>Advance Salary</label><input type="number" step="0.01" name="advance" id="m_advance" class="form-control"></div>
                <div class="col-xs-6"><label>Penalty</label><input type="number" step="0.01" name="penalty" id="m_penalty" class="form-control"></div>
            </div>
          </div>
          <div class="modal-footer">
              <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
              <button type="submit" class="btn-modern btn-primary"><i class="fa fa-save"></i> Save Changes</button>
          </div>
      </form>
    </div>
  </div>
</div>

<!-- DELETE CONFIRMATION MODAL -->
<div id="deleteModal" class="modal fade" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);">
        <button type="button" class="close" data-dismiss="modal" style="color: white;">&times;</button>
        <h4 class="modal-title"><i class="fa fa-trash"></i> Confirm Delete</h4>
      </div>
      <form method="POST">
          <div class="modal-body">
            <input type="hidden" name="delete_payroll" value="1">
            <input type="hidden" name="payroll_id" id="del_id">
            <div style="text-align: center; padding: 20px;">
                <i class="fa fa-exclamation-triangle" style="font-size: 60px; color: #ef4444; margin-bottom: 20px;"></i>
                <h4 style="color: #1a202c; margin-bottom: 15px;">Are you sure you want to delete this payroll record?</h4>
                <p style="font-size: 16px; color: #64748b;">
                    <strong id="del_emp_name" style="color: #1e40af;"></strong><br>
                    <span id="del_month_year" style="color: #8b5cf6;"></span>
                </p>
                <p style="color: #ef4444; font-weight: 600; margin-top: 15px;">
                    <i class="fa fa-warning"></i> This action cannot be undone!
                </p>
            </div>
          </div>
          <div class="modal-footer">
              <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
              <button type="submit" class="btn-modern btn-danger"><i class="fa fa-trash"></i> Yes, Delete</button>
          </div>
      </form>
    </div>
  </div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/js/bootstrap.min.js"></script>
<script>
// Select All checkbox
$('#selectAll').on('change', function() {
    $('.employee-checkbox').not('#selectAll').prop('checked', this.checked);
});

// Search functionality for specific employee modal
$('#modalEmpSearch').on('keyup', function() {
    var value = $(this).val().toLowerCase();
    $('.employee-list-container .emp-item').filter(function() {
        $(this).toggle($(this).text().toLowerCase().indexOf(value) > -1)
    });
});

function editPayroll(data) {
    $('#m_id').val(data.id);
    $('#m_emp_name').text(data.name);
    $('#m_emp_code').text('ID: ' + data.emp_code);
    $('#m_arrears').val(data.arrears);
    var ot_val = data.ot_amount ? data.ot_amount : data.ot;
    $('#m_ot_amount').val(ot_val);
    $('#m_overtime').val(data.overtime);
    $('#m_incentives').val(data.incentives);
    $('#m_advance').val(data.advance_salary);
    $('#m_penalty').val(data.penalty);
    $('#editModal').modal('show');
}

function confirmDelete(id, empName, monthYear) {
    $('#del_id').val(id);
    $('#del_emp_name').text(empName);
    $('#del_month_year').text(monthYear);
    $('#deleteModal').modal('show');
}
</script>
</body>
</html