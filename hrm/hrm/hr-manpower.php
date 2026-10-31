<?php
// ============================================================================
// HR MANPOWER COST ANALYSIS
// ============================================================================
// Present Manpower Cost  -> live from hr_employees + latest hr_payroll record
// Future Manpower Cost   -> planned hires / freelancers not yet real employees
//                           (hr_manpower_future), added manually or via a
//                           2-step Download Template -> Upload CSV import
// Budget Impact          -> Present vs Present+Future comparison
//
// Cost formulas (must match the source Excel exactly):
//   Per Hour  = (Total Salary / 26) / 8
//   Per Day   = Total Salary / 30
//   Per Week  = Total Salary / 4.33
//   Per Month = Total Salary
//   Per Year  = Total Salary * 12
// ============================================================================

if (!ob_get_level()) { ob_start(); }
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
} catch (Exception $e) { die("Error: " . $e->getMessage()); }

date_default_timezone_set('Asia/Kolkata');

if (!isset($_SESSION['user_name'])) { header("Location: login.php"); exit; }
if (!isset($dbConn) || !$dbConn) die("Database connection failed.");
mysqli_report(MYSQLI_REPORT_OFF);

$currentUserName = trim($_SESSION['user_name'] ?? '');

// Same admin check as hr-payroll.php's "Back to Dashboard" button — resolves
// the logged-in session name against hr_employees in case it's a nickname.
$emp_name_db_mp = '';
if (!empty($currentUserName)) {
    $ns_mp  = mysqli_real_escape_string($dbConn, $currentUserName);
    $res_mp = mysqli_query($dbConn, "SELECT name FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$ns_mp%') AND status='active' LIMIT 1");
    if ($res_mp && mysqli_num_rows($res_mp) > 0) {
        $emp_name_db_mp = mysqli_fetch_assoc($res_mp)['name'];
    }
}
$isAdmin = (stripos($emp_name_db_mp, 'abishek') !== false || stripos($currentUserName, 'abishek') !== false);

// ============================================================================
// SCHEMA — future hires / freelancers (not yet real hr_employees rows)
// ============================================================================
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_manpower_future (
    id INT AUTO_INCREMENT PRIMARY KEY,
    entry_type ENUM('hire','freelancer') NOT NULL DEFAULT 'hire',
    name VARCHAR(255) NOT NULL,
    company_name VARCHAR(255) DEFAULT NULL,
    department VARCHAR(150) DEFAULT NULL,
    position VARCHAR(150) DEFAULT NULL,
    expected_joining_date DATE DEFAULT NULL,
    basic_salary DECIMAL(12,2) DEFAULT 0,
    hra DECIMAL(12,2) DEFAULT 0,
    conveyance DECIMAL(12,2) DEFAULT 0,
    special_allowance DECIMAL(12,2) DEFAULT 0,
    gross_pay DECIMAL(12,2) DEFAULT 0,
    incentives DECIMAL(12,2) DEFAULT 0,
    total_ctc DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes TEXT DEFAULT NULL,
    status ENUM('planned','converted','cancelled') NOT NULL DEFAULT 'planned',
    linked_employee_id INT DEFAULT NULL,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_status (status),
    KEY idx_company (company_name),
    KEY idx_department (department)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// ============================================================================
// HELPER: cost breakdown from a monthly total (must match the source Excel)
// ============================================================================
function mp_costs($total) {
    $total = floatval($total);
    $hour = $total > 0 ? ($total / 26) / 8 : 0;
    return [
        'minute' => $hour > 0 ? $hour / 60 : 0,
        'hour'  => $hour,
        'day'   => $total > 0 ? $total / 30 : 0,
        'week'  => $total > 0 ? $total / 4.33 : 0,
        'month' => $total,
        'year'  => $total * 12,
    ];
}
function mp_money($n) { return '₹' . number_format(floatval($n), 2); }

// ============================================================================
// HELPER: company-name normalization — same logic as hr-payroll.php so this
// module groups companies identically to the existing payroll dashboard,
// instead of treating "Abra E Logistic" and "Abra E Logistic Pvt. Ltd." as
// two different companies.
// ============================================================================
function hr_normalize_company_name($s) {
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    $s = preg_replace('/\b(pvt|private|ltd|limited|llp|inc|incorporated|co|company|corp|corporation)\b/', '', $s);
    $s = trim(preg_replace('/\s+/', ' ', $s));
    return $s;
}
$company_norm_to_variants = [];
$mc_res = mysqli_query($dbConn, "SELECT company_name FROM hr_companies WHERE company_name IS NOT NULL AND company_name != ''");
if ($mc_res) {
    while ($mc_row = mysqli_fetch_assoc($mc_res)) {
        $norm = hr_normalize_company_name($mc_row['company_name']);
        if (!isset($company_norm_to_variants[$norm])) $company_norm_to_variants[$norm] = [];
        if (!in_array($mc_row['company_name'], $company_norm_to_variants[$norm])) $company_norm_to_variants[$norm][] = $mc_row['company_name'];
    }
}
$emp_cn_res = mysqli_query($dbConn, "SELECT DISTINCT TRIM(company_name) as company_name FROM hr_employees WHERE company_name IS NOT NULL AND company_name != ''");
if ($emp_cn_res) {
    while ($ecn = mysqli_fetch_assoc($emp_cn_res)) {
        $raw = trim($ecn['company_name']);
        if ($raw === '') continue;
        $norm = hr_normalize_company_name($raw);
        if (!isset($company_norm_to_variants[$norm])) $company_norm_to_variants[$norm] = [];
        if (!in_array($raw, $company_norm_to_variants[$norm])) $company_norm_to_variants[$norm][] = $raw;
    }
}
$company_norm_to_label = [];
foreach ($company_norm_to_variants as $norm => $variants) { $company_norm_to_label[$norm] = $variants[0]; }
function hr_canonical_company_label($raw, $company_norm_to_label) {
    if ($raw === '' || $raw === null) return '(No Company Set)';
    $norm = hr_normalize_company_name($raw);
    return isset($company_norm_to_label[$norm]) ? $company_norm_to_label[$norm] : $raw;
}
$companies_list = [];
foreach ($company_norm_to_variants as $norm => $variants) { $companies_list[] = $variants[0]; }
sort($companies_list);

// ============================================================================
// GET: DOWNLOAD IMPORT TEMPLATE (step 1 of the 2-step import)
// ============================================================================
if (isset($_GET['action']) && $_GET['action'] === 'download_template') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=Manpower_Future_Entries_Template.csv');
    $out = fopen('php://output', 'w');
    fputs($out, "\xEF\xBB\xBF"); // UTF-8 BOM so Excel opens it cleanly
    fputcsv($out, ['entry_type', 'name', 'company_name', 'department', 'position', 'expected_joining_date', 'basic_salary', 'hra', 'conveyance', 'special_allowance', 'gross_pay', 'incentives', 'total_ctc', 'notes']);
    fputcsv($out, ['hire', 'Ravi Kumar', 'Abra E-Logistic PVT LTD', 'Operation Department', 'Logistic Executive', '2026-09-01', '15000', '4000', '3000', '3000', '25000', '0', '25480', 'Planned new hire for warehouse expansion']);
    fputcsv($out, ['freelancer', 'Priya Designs', 'Abra E-Logistic PVT LTD', 'Digital Marketing', 'Freelance Graphic Designer', '2026-08-15', '0', '0', '0', '0', '0', '0', '12000', 'Monthly retainer for social media creatives']);
    fclose($out);
    exit;
}

// ============================================================================
// GET: EXPORT (present / future) — respects whatever filters are active
// ============================================================================
function mp_build_company_filter_sql($alias, $filter_company, $company_norm_to_variants, $dbConn) {
    if (empty($filter_company)) return '';
    $col = ($alias !== '') ? "$alias.company_name" : "company_name";
    if ($filter_company === '(No Company Set)') {
        return " AND COALESCE(NULLIF(TRIM($col),''),'(No Company Set)') = '(No Company Set)' ";
    }
    $norm = hr_normalize_company_name($filter_company);
    $variants = isset($company_norm_to_variants[$norm]) ? $company_norm_to_variants[$norm] : [$filter_company];
    $variant_list = [];
    foreach ($variants as $v) { $variant_list[] = "'" . mysqli_real_escape_string($dbConn, trim($v)) . "'"; }
    return " AND TRIM($col) IN (" . implode(',', $variant_list) . ") ";
}

$f_company    = trim($_GET['f_company'] ?? ($_POST['f_company'] ?? ''));
$f_department = trim($_GET['f_department'] ?? ($_POST['f_department'] ?? ''));
$f_position   = trim($_GET['f_position'] ?? ($_POST['f_position'] ?? ''));
$f_search     = trim($_GET['f_search'] ?? ($_POST['f_search'] ?? ''));
$f_type       = trim($_GET['f_type'] ?? ($_POST['f_type'] ?? ''));

if (isset($_GET['action']) && ($_GET['action'] === 'export_present' || $_GET['action'] === 'export_future')) {
    $isPresent = ($_GET['action'] === 'export_present');
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=' . ($isPresent ? 'Present' : 'Future') . '_Manpower_Cost_Export.csv');
    $out = fopen('php://output', 'w');
    fputs($out, "\xEF\xBB\xBF");

    if ($isPresent) {
        fputcsv($out, ['Name','Company','Department','Designation','Date of Joining','Basic Salary','HRA','Conveyance','Special Allowance','Gross Pay','Incentives','Total CTC','Per Hour','Per Day','Per Week','Per Month','Per Year']);
        $where = " WHERE e.status='active' ";
        $where .= mp_build_company_filter_sql('e', $f_company, $company_norm_to_variants, $dbConn);
        if ($f_department !== '') $where .= " AND e.department = '" . mysqli_real_escape_string($dbConn, $f_department) . "' ";
        if ($f_position !== '') $where .= " AND e.position = '" . mysqli_real_escape_string($dbConn, $f_position) . "' ";
        if ($f_search !== '') $where .= " AND e.name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%' ";
        $sql = "SELECT e.name, e.company_name, e.department, e.position, e.hire_date,
                       p.basic_salary, p.hra, p.conveyance, p.special_allowance, p.gross_pay, p.incentives, p.total_ctc, e.salary
                FROM hr_employees e
                LEFT JOIN hr_payroll p ON p.id = (SELECT p2.id FROM hr_payroll p2 WHERE p2.employee_id = e.id ORDER BY p2.pay_year DESC, p2.pay_month DESC LIMIT 1)
                $where ORDER BY e.company_name, e.department, e.name";
        $res = mysqli_query($dbConn, $sql);
        if ($res) while ($r = mysqli_fetch_assoc($res)) {
            $total = floatval($r['total_ctc'] ?? 0) > 0 ? floatval($r['total_ctc']) : floatval($r['salary'] ?? 0);
            $c = mp_costs($total);
            fputcsv($out, [
                $r['name'], hr_canonical_company_label($r['company_name'], $company_norm_to_label), $r['department'], $r['position'],
                $r['hire_date'], $r['basic_salary'], $r['hra'], $r['conveyance'], $r['special_allowance'], $r['gross_pay'], $r['incentives'], $total,
                round($c['hour'],2), round($c['day'],2), round($c['week'],2), round($c['month'],2), round($c['year'],2)
            ]);
        }
    } else {
        fputcsv($out, ['Type','Name','Company','Department','Designation','Expected Joining','Basic Salary','HRA','Conveyance','Special Allowance','Gross Pay','Incentives','Total CTC','Per Hour','Per Day','Per Week','Per Month','Per Year','Status']);
        $where = " WHERE status != 'cancelled' ";
        $where .= mp_build_company_filter_sql('', $f_company, $company_norm_to_variants, $dbConn);
        if ($f_department !== '') $where .= " AND department = '" . mysqli_real_escape_string($dbConn, $f_department) . "' ";
        if ($f_position !== '') $where .= " AND position = '" . mysqli_real_escape_string($dbConn, $f_position) . "' ";
        if ($f_search !== '') $where .= " AND name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%' ";
        if ($f_type !== '') $where .= " AND entry_type = '" . mysqli_real_escape_string($dbConn, $f_type) . "' ";
        $res = mysqli_query($dbConn, "SELECT * FROM hr_manpower_future $where ORDER BY company_name, department, name");
        if ($res) while ($r = mysqli_fetch_assoc($res)) {
            $c = mp_costs($r['total_ctc']);
            fputcsv($out, [
                ucfirst($r['entry_type']), $r['name'], hr_canonical_company_label($r['company_name'], $company_norm_to_label), $r['department'], $r['position'],
                $r['expected_joining_date'], $r['basic_salary'], $r['hra'], $r['conveyance'], $r['special_allowance'], $r['gross_pay'], $r['incentives'], $r['total_ctc'],
                round($c['hour'],2), round($c['day'],2), round($c['week'],2), round($c['month'],2), round($c['year'],2), ucfirst($r['status'])
            ]);
        }
    }
    fclose($out);
    exit;
}

// ============================================================================
// POST: IMPORT FUTURE ENTRIES (step 2 — upload the filled template)
// ============================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['import_future'])) {
    $imported = 0; $skipped = 0;
    if (isset($_FILES['csv_file']) && $_FILES['csv_file']['error'] === UPLOAD_ERR_OK) {
        $handle = fopen($_FILES['csv_file']['tmp_name'], 'r');
        if ($handle) {
            fgetcsv($handle); // skip header
            while (($data = fgetcsv($handle)) !== false) {
                if (empty($data) || !array_filter($data)) continue;
                $name = trim($data[1] ?? '');
                if ($name === '') { $skipped++; continue; }
                $entry_type = (trim($data[0] ?? '') === 'freelancer') ? 'freelancer' : 'hire';
                $company_name = mysqli_real_escape_string($dbConn, trim($data[2] ?? ''));
                $department   = mysqli_real_escape_string($dbConn, trim($data[3] ?? ''));
                $position     = mysqli_real_escape_string($dbConn, trim($data[4] ?? ''));
                $exp_join_raw = trim($data[5] ?? '');
                $exp_join     = $exp_join_raw !== '' ? date('Y-m-d', strtotime($exp_join_raw)) : null;
                $basic        = floatval($data[6] ?? 0);
                $hra          = floatval($data[7] ?? 0);
                $conveyance   = floatval($data[8] ?? 0);
                $special      = floatval($data[9] ?? 0);
                $gross        = floatval($data[10] ?? 0);
                $incentives   = floatval($data[11] ?? 0);
                $total_ctc    = floatval($data[12] ?? 0);
                if ($total_ctc <= 0) $total_ctc = $gross > 0 ? $gross : ($basic + $hra + $conveyance + $special);
                $notes        = mysqli_real_escape_string($dbConn, trim($data[13] ?? ''));
                $name_esc     = mysqli_real_escape_string($dbConn, $name);
                $join_sql     = $exp_join ? "'$exp_join'" : "NULL";
                $creator      = mysqli_real_escape_string($dbConn, $currentUserName);

                mysqli_query($dbConn, "INSERT INTO hr_manpower_future
                    (entry_type, name, company_name, department, position, expected_joining_date, basic_salary, hra, conveyance, special_allowance, gross_pay, incentives, total_ctc, notes, created_by)
                    VALUES ('$entry_type','$name_esc','$company_name','$department','$position',$join_sql,$basic,$hra,$conveyance,$special,$gross,$incentives,$total_ctc,'$notes','$creator')");
                $imported++;
            }
            fclose($handle);
        }
        $_SESSION['success_message'] = "$imported entr" . ($imported == 1 ? 'y' : 'ies') . " imported successfully." . ($skipped > 0 ? " $skipped row(s) skipped (missing name)." : "");
    } else {
        $_SESSION['error_message'] = "Please choose a valid CSV file to upload.";
    }
    header("Location: hr-manpower.php?tab=future");
    exit;
}

// ============================================================================
// POST: ADD / EDIT / DELETE / CONVERT future entries
// ============================================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_future_entry'])) {
    $fid          = intval($_POST['future_id'] ?? 0);
    $entry_type   = ($_POST['entry_type'] ?? 'hire') === 'freelancer' ? 'freelancer' : 'hire';
    $name         = trim($_POST['name'] ?? '');
    $company_name = trim($_POST['company_name'] ?? '');
    $department   = trim($_POST['department'] ?? '');
    $position     = trim($_POST['position'] ?? '');
    $exp_join     = trim($_POST['expected_joining_date'] ?? '');
    $basic        = floatval($_POST['basic_salary'] ?? 0);
    $hra          = floatval($_POST['hra'] ?? 0);
    $conveyance   = floatval($_POST['conveyance'] ?? 0);
    $special      = floatval($_POST['special_allowance'] ?? 0);
    $gross        = floatval($_POST['gross_pay'] ?? 0);
    $incentives   = floatval($_POST['incentives'] ?? 0);
    $total_ctc    = floatval($_POST['total_ctc'] ?? 0);
    $notes        = trim($_POST['notes'] ?? '');

    if ($name === '' || $total_ctc <= 0) {
        $_SESSION['error_message'] = "Name and Total CTC are required.";
    } else {
        $name_e = mysqli_real_escape_string($dbConn, $name);
        $co_e   = mysqli_real_escape_string($dbConn, $company_name);
        $dept_e = mysqli_real_escape_string($dbConn, $department);
        $pos_e  = mysqli_real_escape_string($dbConn, $position);
        $notes_e= mysqli_real_escape_string($dbConn, $notes);
        $join_sql = $exp_join !== '' ? "'" . mysqli_real_escape_string($dbConn, $exp_join) . "'" : "NULL";

        if ($fid > 0) {
            mysqli_query($dbConn, "UPDATE hr_manpower_future SET
                entry_type='$entry_type', name='$name_e', company_name='$co_e', department='$dept_e', position='$pos_e',
                expected_joining_date=$join_sql, basic_salary=$basic, hra=$hra, conveyance=$conveyance, special_allowance=$special,
                gross_pay=$gross, incentives=$incentives, total_ctc=$total_ctc, notes='$notes_e'
                WHERE id=$fid");
            $_SESSION['success_message'] = "Entry updated successfully.";
        } else {
            $creator = mysqli_real_escape_string($dbConn, $currentUserName);
            mysqli_query($dbConn, "INSERT INTO hr_manpower_future
                (entry_type, name, company_name, department, position, expected_joining_date, basic_salary, hra, conveyance, special_allowance, gross_pay, incentives, total_ctc, notes, created_by)
                VALUES ('$entry_type','$name_e','$co_e','$dept_e','$pos_e',$join_sql,$basic,$hra,$conveyance,$special,$gross,$incentives,$total_ctc,'$notes_e','$creator')");
            $_SESSION['success_message'] = "Future entry added successfully.";
        }
    }
    header("Location: hr-manpower.php?tab=future");
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_future_entry'])) {
    $fid = intval($_POST['future_id'] ?? 0);
    if ($fid > 0) mysqli_query($dbConn, "DELETE FROM hr_manpower_future WHERE id=$fid");
    $_SESSION['success_message'] = "Entry deleted.";
    header("Location: hr-manpower.php?tab=future");
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['convert_future_entry'])) {
    $fid = intval($_POST['future_id'] ?? 0);
    $linked_emp = intval($_POST['linked_employee_id'] ?? 0);
    if ($fid > 0) {
        if ($linked_emp > 0) {
            mysqli_query($dbConn, "UPDATE hr_manpower_future SET status='converted', linked_employee_id=$linked_emp WHERE id=$fid");
            $_SESSION['success_message'] = "Marked as converted and linked to the employee record. It now drops out of the Future projection and counts under Present instead.";
        } else {
            mysqli_query($dbConn, "UPDATE hr_manpower_future SET status='converted' WHERE id=$fid");
            $_SESSION['success_message'] = "Marked as converted.";
        }
    }
    header("Location: hr-manpower.php?tab=future");
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['cancel_future_entry'])) {
    $fid = intval($_POST['future_id'] ?? 0);
    if ($fid > 0) mysqli_query($dbConn, "UPDATE hr_manpower_future SET status='cancelled' WHERE id=$fid");
    $_SESSION['success_message'] = "Entry cancelled.";
    header("Location: hr-manpower.php?tab=future");
    exit;
}

// ============================================================================
// PRESENT MANPOWER COST — live from hr_employees + latest hr_payroll record
// ============================================================================
$present_where = " WHERE e.status='active' ";
$present_where .= mp_build_company_filter_sql('e', $f_company, $company_norm_to_variants, $dbConn);
if ($f_department !== '') $present_where .= " AND e.department = '" . mysqli_real_escape_string($dbConn, $f_department) . "' ";
if ($f_position !== '')   $present_where .= " AND e.position = '" . mysqli_real_escape_string($dbConn, $f_position) . "' ";
if ($f_search !== '')     $present_where .= " AND e.name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%' ";

$present_sql = "SELECT e.id, e.name, e.company_name, e.department, e.position, e.hire_date,
                       p.basic_salary, p.hra, p.conveyance, p.special_allowance, p.gross_pay, p.incentives,
                       p.pf, p.esi, p.pt, p.tds, p.total_deduction, p.total_ctc, e.salary
                FROM hr_employees e
                LEFT JOIN hr_payroll p ON p.id = (SELECT p2.id FROM hr_payroll p2 WHERE p2.employee_id = e.id ORDER BY p2.pay_year DESC, p2.pay_month DESC LIMIT 1)
                $present_where
                ORDER BY e.company_name, e.department, e.name";
$present_res = mysqli_query($dbConn, $present_sql);
$present_rows = [];
if ($present_res) {
    while ($r = mysqli_fetch_assoc($present_res)) {
        $total = floatval($r['total_ctc'] ?? 0) > 0 ? floatval($r['total_ctc']) : floatval($r['salary'] ?? 0);
        $r['company_label'] = hr_canonical_company_label($r['company_name'], $company_norm_to_label);
        $r['total_used'] = $total;
        $r['costs'] = mp_costs($total);
        $r['has_payroll'] = floatval($r['total_ctc'] ?? 0) > 0;
        $present_rows[] = $r;
    }
}

// Documents filed under each employee (e.g. approved revised offer letters), so
// they show up on the employee's own details card, not just the offer-letter tool.
// hr_employee_documents' real schema varies (see get-employee-documents.php), so
// detect its actual columns rather than assuming fixed names.
$employee_documents_map = [];
$doc_cols_mp = [];
$doc_cols_res = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_employee_documents");
if ($doc_cols_res) while ($dcr = mysqli_fetch_assoc($doc_cols_res)) $doc_cols_mp[] = $dcr['Field'];
$doc_label_col = in_array('document_label', $doc_cols_mp) ? 'document_label' : (in_array('document_type', $doc_cols_mp) ? 'document_type' : null);
$doc_date_col = null;
foreach (['uploaded_at', 'upload_date', 'created_at', 'date_uploaded', 'date'] as $dcand) { if (in_array($dcand, $doc_cols_mp)) { $doc_date_col = $dcand; break; } }
$doc_path_col = in_array('filepath', $doc_cols_mp) ? 'filepath' : (in_array('file_path', $doc_cols_mp) ? 'file_path' : null);

if ($doc_path_col) {
    $doc_select = "employee_id" . ($doc_label_col ? ", $doc_label_col as doc_label" : "") . ($doc_date_col ? ", $doc_date_col as doc_date" : "") . ", $doc_path_col as doc_path";
    $doc_res = mysqli_query($dbConn, "SELECT $doc_select FROM hr_employee_documents ORDER BY " . ($doc_date_col ?: 'id') . " DESC");
    if ($doc_res) while ($dr = mysqli_fetch_assoc($doc_res)) {
        $eid = intval($dr['employee_id']);
        if (!isset($employee_documents_map[$eid])) $employee_documents_map[$eid] = [];
        $doc_path = $dr['doc_path'] ?? '';
        $is_offer_link = (strpos($doc_path, 'hr-employee-offer.php') !== false);
        $employee_documents_map[$eid][] = [
            'label' => $dr['doc_label'] ?? 'Document',
            'date' => !empty($dr['doc_date']) ? date('d M Y', strtotime($dr['doc_date'])) : '',
            'url' => $is_offer_link ? $doc_path : '',
        ];
    }
}

// Group present rows by company -> department -> position, with subtotals at every level
$present_grouped = [];
$present_total_headcount = 0; $present_total_monthly = 0;
foreach ($present_rows as $r) {
    $co   = $r['company_label'];
    $dept = $r['department'] ?: '(No Department Set)';
    $pos  = $r['position']   ?: '(No Position Set)';
    if (!isset($present_grouped[$co])) $present_grouped[$co] = ['depts' => [], 'headcount' => 0, 'monthly' => 0];
    if (!isset($present_grouped[$co]['depts'][$dept])) $present_grouped[$co]['depts'][$dept] = ['positions' => [], 'headcount' => 0, 'monthly' => 0];
    if (!isset($present_grouped[$co]['depts'][$dept]['positions'][$pos])) $present_grouped[$co]['depts'][$dept]['positions'][$pos] = ['rows' => [], 'headcount' => 0, 'monthly' => 0];
    $present_grouped[$co]['depts'][$dept]['positions'][$pos]['rows'][] = $r;
    $present_grouped[$co]['depts'][$dept]['positions'][$pos]['headcount']++;
    $present_grouped[$co]['depts'][$dept]['positions'][$pos]['monthly'] += $r['total_used'];
    $present_grouped[$co]['depts'][$dept]['headcount']++;
    $present_grouped[$co]['depts'][$dept]['monthly'] += $r['total_used'];
    $present_grouped[$co]['headcount']++;
    $present_grouped[$co]['monthly'] += $r['total_used'];
    $present_total_headcount++;
    $present_total_monthly += $r['total_used'];
}
ksort($present_grouped);

// ============================================================================
// FUTURE MANPOWER COST — planned hires / freelancers
// ============================================================================
$future_where = " WHERE status='planned' ";
$future_where .= mp_build_company_filter_sql('', $f_company, $company_norm_to_variants, $dbConn);
if ($f_department !== '') $future_where .= " AND department = '" . mysqli_real_escape_string($dbConn, $f_department) . "' ";
if ($f_position !== '')   $future_where .= " AND position = '" . mysqli_real_escape_string($dbConn, $f_position) . "' ";
if ($f_search !== '')     $future_where .= " AND name LIKE '%" . mysqli_real_escape_string($dbConn, $f_search) . "%' ";
if ($f_type !== '')       $future_where .= " AND entry_type = '" . mysqli_real_escape_string($dbConn, $f_type) . "' ";

$future_res = mysqli_query($dbConn, "SELECT * FROM hr_manpower_future $future_where ORDER BY company_name, department, name");
$future_rows = [];
$future_total_headcount = 0; $future_total_monthly = 0;
$future_hire_headcount = 0; $future_hire_monthly = 0;
$future_freelance_headcount = 0; $future_freelance_monthly = 0;
if ($future_res) {
    while ($r = mysqli_fetch_assoc($future_res)) {
        $r['company_label'] = hr_canonical_company_label($r['company_name'], $company_norm_to_label);
        $r['costs'] = mp_costs($r['total_ctc']);
        $future_rows[] = $r;
        $future_total_headcount++;
        $future_total_monthly += floatval($r['total_ctc']);
        if ($r['entry_type'] === 'freelancer') {
            $future_freelance_headcount++;
            $future_freelance_monthly += floatval($r['total_ctc']);
        } else {
            $future_hire_headcount++;
            $future_hire_monthly += floatval($r['total_ctc']);
        }
    }
}

// All future entries (any status) — for the manage list on the Future tab
$all_future_res = mysqli_query($dbConn, "SELECT * FROM hr_manpower_future ORDER BY status='planned' DESC, company_name, department, name");
$all_future_rows = [];
if ($all_future_res) while ($r = mysqli_fetch_assoc($all_future_res)) $all_future_rows[] = $r;

// Distinct departments / positions for filter dropdowns (from both present + future)
$dept_list = [];
$dr = mysqli_query($dbConn, "SELECT DISTINCT department FROM hr_employees WHERE department IS NOT NULL AND department != '' AND status='active'
                              UNION SELECT DISTINCT department FROM hr_manpower_future WHERE department IS NOT NULL AND department != ''");
if ($dr) while ($d = mysqli_fetch_assoc($dr)) $dept_list[] = $d['department'];
sort($dept_list);

$pos_list = [];
$pr = mysqli_query($dbConn, "SELECT DISTINCT position FROM hr_employees WHERE position IS NOT NULL AND position != '' AND status='active'
                              UNION SELECT DISTINCT position FROM hr_manpower_future WHERE position IS NOT NULL AND position != ''");
if ($pr) while ($p = mysqli_fetch_assoc($pr)) $pos_list[] = $p['position'];
sort($pos_list);

// Department -> Positions map, so the Designation field can filter down to the
// positions that actually exist under the department picked in the Add Future Entry modal.
$dept_position_map = [];
$dpr = mysqli_query($dbConn, "SELECT DISTINCT department, position FROM hr_employees WHERE department IS NOT NULL AND department != '' AND position IS NOT NULL AND position != '' AND status='active'
                               UNION SELECT DISTINCT department, position FROM hr_manpower_future WHERE department IS NOT NULL AND department != '' AND position IS NOT NULL AND position != ''");
if ($dpr) while ($dp = mysqli_fetch_assoc($dpr)) {
    $dd = $dp['department']; $pp = $dp['position'];
    if (!isset($dept_position_map[$dd])) $dept_position_map[$dd] = [];
    if (!in_array($pp, $dept_position_map[$dd])) $dept_position_map[$dd][] = $pp;
}
foreach ($dept_position_map as $k => $v) { sort($dept_position_map[$k]); }

// Active employees list, for the "Convert to Employee" link-up dropdown
$active_employees_list = [];
$aer = mysqli_query($dbConn, "SELECT id, name FROM hr_employees WHERE status='active' ORDER BY name");
if ($aer) while ($a = mysqli_fetch_assoc($aer)) $active_employees_list[] = $a;

// ============================================================================
// BUDGET IMPACT / COMPARISON TOTALS
// ============================================================================
$combined_total_headcount = $present_total_headcount + $future_total_headcount;
$combined_total_monthly   = $present_total_monthly + $future_total_monthly;
$present_costs  = mp_costs($present_total_monthly);
$future_costs   = mp_costs($future_total_monthly);
$combined_costs = mp_costs($combined_total_monthly);

// Per-company comparison
$company_comparison = [];
foreach ($present_grouped as $co => $data) {
    $company_comparison[$co]['present_headcount'] = $data['headcount'];
    $company_comparison[$co]['present_monthly'] = $data['monthly'];
}
foreach ($future_rows as $r) {
    $co = $r['company_label'];
    if (!isset($company_comparison[$co])) $company_comparison[$co] = ['present_headcount' => 0, 'present_monthly' => 0];
    if (!isset($company_comparison[$co]['future_headcount'])) { $company_comparison[$co]['future_headcount'] = 0; $company_comparison[$co]['future_monthly'] = 0; }
    $company_comparison[$co]['future_headcount']++;
    $company_comparison[$co]['future_monthly'] += floatval($r['total_ctc']);
}
foreach ($company_comparison as $co => $d) {
    if (!isset($company_comparison[$co]['future_headcount'])) { $company_comparison[$co]['future_headcount'] = 0; $company_comparison[$co]['future_monthly'] = 0; }
}
ksort($company_comparison);

// ============================================================================
// GET: PRINT / PDF REPORTS — reuse the already-filtered data computed above,
// so the PDF always matches whatever the on-screen table + filters show.
// ============================================================================
function mp_print_filters_label($f_company, $f_department, $f_position, $f_search, $f_type = '') {
    $parts = [];
    if ($f_company !== '') $parts[] = 'Company: ' . htmlspecialchars($f_company);
    if ($f_department !== '') $parts[] = 'Department: ' . htmlspecialchars($f_department);
    if ($f_position !== '') $parts[] = 'Designation: ' . htmlspecialchars($f_position);
    if ($f_search !== '') $parts[] = 'Search: "' . htmlspecialchars($f_search) . '"';
    if ($f_type !== '') $parts[] = 'Type: ' . htmlspecialchars(ucfirst($f_type));
    return $parts ? implode(' &middot; ', $parts) : 'All Records (no filters applied)';
}
function mp_print_shell($reportTitle, $filtersLabel, $bodyHtml) {
    $generated = date('d M Y, h:i A');
    return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>' . htmlspecialchars($reportTitle) . ' | Abra FlowX.AI</title>
<style>
* { box-sizing:border-box; }
body { font-family: "Segoe UI", Arial, sans-serif; margin:0; padding:26px; color:#1e293b; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
.rp-header { background:linear-gradient(135deg,#0f2557 0%,#15328a 100%); color:#fff; padding:20px 26px; border-radius:12px; margin-bottom:16px; }
.rp-header h1 { margin:0; font-size:21px; }
.rp-header p { margin:6px 0 0; font-size:12px; opacity:.92; }
.rp-meta { font-size:11.5px; color:#475569; margin-bottom:16px; padding:8px 12px; background:#f1f5f9; border-radius:6px; }
table { width:100%; border-collapse:collapse; font-size:11px; margin-bottom:10px; }
th { background:linear-gradient(135deg,#0f2557 0%,#15328a 100%); color:#fff; padding:8px 9px; text-align:left; text-transform:uppercase; font-size:9.5px; letter-spacing:.3px; }
td { padding:6px 9px; border-bottom:1px solid #e2e8f0; }
tr.company-row td { background:#2563eb; color:#fff; font-weight:800; font-size:12px; }
tr.subtotal-row td { background:#f1f5f9; font-weight:800; color:#1e3a8a; }
h3 { color:#1e3a8a; font-size:14px; }
.rp-print-btn { margin-bottom:16px; padding:10px 22px; background:#1e3a8a; color:#fff; border:none; border-radius:8px; font-weight:700; cursor:pointer; font-size:13px; }
@media print { .rp-print-btn { display:none; } body { padding:8px; } }
</style></head><body>
<button class="rp-print-btn" onclick="window.print()"><i class="fas fa-print"></i> Print / Save as PDF</button>
<div class="rp-header"><h1>' . htmlspecialchars($reportTitle) . '</h1><p>Abra FlowX.AI &middot; Manpower Cost Analysis &middot; Generated ' . $generated . '</p></div>
<div class="rp-meta"><strong>Filters applied:</strong> ' . $filtersLabel . '</div>
' . $bodyHtml . '
<script>window.onload = function(){ setTimeout(function(){ window.print(); }, 400); };</script>
</body></html>';
}
if (isset($_GET['action']) && in_array($_GET['action'], ['print_present', 'print_future', 'print_comparison'], true)) {
    $paction = $_GET['action'];
    $filtersLabel = mp_print_filters_label($f_company, $f_department, $f_position, $f_search, $f_type);
    ob_start();
    if ($paction === 'print_present') {
        $title = 'Present Manpower Cost Report';
        echo '<table><thead><tr><th>Name</th><th>Department</th><th>Designation</th><th>Date of Joining</th><th>Basic</th><th>HRA</th><th>Conveyance</th><th>Special Allow.</th><th>Incentives</th><th>Total CTC / Month</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Year</th></tr></thead><tbody>';
        foreach ($present_grouped as $co => $codata) {
            echo '<tr class="company-row"><td colspan="14">' . htmlspecialchars($co) . ' &middot; ' . $codata['headcount'] . ' employee(s) &middot; ' . mp_money($codata['monthly']) . ' / month</td></tr>';
            foreach ($codata['depts'] as $dept => $deptdata) {
                echo '<tr class="subtotal-row"><td colspan="4">' . htmlspecialchars($dept) . ' Subtotal (' . $deptdata['headcount'] . ')</td><td colspan="5"></td><td>' . mp_money($deptdata['monthly']) . '</td><td colspan="4"></td></tr>';
                foreach ($deptdata['rows'] as $r) {
                    echo '<tr><td>' . htmlspecialchars($r['name']) . '</td><td>' . htmlspecialchars($dept) . '</td><td>' . htmlspecialchars($r['position'] ?: '-') . '</td><td>' . ($r['hire_date'] ? date('d M Y', strtotime($r['hire_date'])) : '-') . '</td><td>' . mp_money($r['basic_salary'] ?? 0) . '</td><td>' . mp_money($r['hra'] ?? 0) . '</td><td>' . mp_money($r['conveyance'] ?? 0) . '</td><td>' . mp_money($r['special_allowance'] ?? 0) . '</td><td>' . mp_money($r['incentives'] ?? 0) . '</td><td>' . mp_money($r['total_used']) . '</td><td>' . mp_money($r['costs']['hour']) . '</td><td>' . mp_money($r['costs']['day']) . '</td><td>' . mp_money($r['costs']['week']) . '</td><td>' . mp_money($r['costs']['year']) . '</td></tr>';
                }
            }
        }
        echo '</tbody></table>';
    } elseif ($paction === 'print_future') {
        $title = 'Future Manpower Cost Report (Planned Hires & Freelancers)';
        echo '<table><thead><tr><th>Type</th><th>Name</th><th>Company</th><th>Department</th><th>Designation</th><th>Expected Joining</th><th>Total CTC / Month</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Year</th><th>Status</th></tr></thead><tbody>';
        foreach ($future_rows as $r) {
            $c = $r['costs'];
            echo '<tr><td>' . ($r['entry_type']==='freelancer'?'Freelancer':'Planned Hire') . '</td><td>' . htmlspecialchars($r['name']) . '</td><td>' . htmlspecialchars($r['company_label']) . '</td><td>' . htmlspecialchars($r['department'] ?: '-') . '</td><td>' . htmlspecialchars($r['position'] ?: '-') . '</td><td>' . ($r['expected_joining_date'] ? date('d M Y', strtotime($r['expected_joining_date'])) : '-') . '</td><td>' . mp_money($r['total_ctc']) . '</td><td>' . mp_money($c['hour']) . '</td><td>' . mp_money($c['day']) . '</td><td>' . mp_money($c['week']) . '</td><td>' . mp_money($c['year']) . '</td><td>' . ucfirst($r['status']) . '</td></tr>';
        }
        echo '</tbody></table>';
    } else {
        $title = 'Budget Impact / Comparison Report';
        echo '<h3>Overall Budget Impact</h3><table><thead><tr><th></th><th>Headcount</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Month</th><th>Per Year</th></tr></thead><tbody>';
        echo '<tr><td><strong>Present (Current Employees)</strong></td><td>' . $present_total_headcount . '</td><td>' . mp_money($present_costs['hour']) . '</td><td>' . mp_money($present_costs['day']) . '</td><td>' . mp_money($present_costs['week']) . '</td><td>' . mp_money($present_costs['month']) . '</td><td>' . mp_money($present_costs['year']) . '</td></tr>';
        echo '<tr><td><strong>Future (Planned Hires + Freelancers)</strong></td><td>' . $future_total_headcount . '</td><td>' . mp_money($future_costs['hour']) . '</td><td>' . mp_money($future_costs['day']) . '</td><td>' . mp_money($future_costs['week']) . '</td><td>' . mp_money($future_costs['month']) . '</td><td>' . mp_money($future_costs['year']) . '</td></tr>';
        echo '<tr class="subtotal-row"><td><strong>Projected Total</strong></td><td>' . $combined_total_headcount . '</td><td>' . mp_money($combined_costs['hour']) . '</td><td>' . mp_money($combined_costs['day']) . '</td><td>' . mp_money($combined_costs['week']) . '</td><td>' . mp_money($combined_costs['month']) . '</td><td>' . mp_money($combined_costs['year']) . '</td></tr>';
        echo '</tbody></table>';
        echo '<h3 style="margin-top:20px;">Per-Company Comparison</h3><table><thead><tr><th>Company</th><th>Present Headcount</th><th>Present Monthly</th><th>Future Additions</th><th>Future Monthly</th><th>Projected Total Monthly</th></tr></thead><tbody>';
        foreach ($company_comparison as $co => $d) {
            echo '<tr><td><strong>' . htmlspecialchars($co) . '</strong></td><td>' . $d['present_headcount'] . '</td><td>' . mp_money($d['present_monthly']) . '</td><td>' . $d['future_headcount'] . '</td><td>' . mp_money($d['future_monthly']) . '</td><td><strong>' . mp_money($d['present_monthly'] + $d['future_monthly']) . '</strong></td></tr>';
        }
        echo '</tbody></table>';
    }
    $bodyHtml = ob_get_clean();
    echo mp_print_shell($title, $filtersLabel, $bodyHtml);
    exit;
}

$active_tab = $_GET['tab'] ?? 'present';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Manpower Cost Analysis | HR</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<link href="https://cdn.jsdelivr.net/npm/sweetalert2@11/dist/sweetalert2.min.css" rel="stylesheet"/>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Poppins',sans-serif; background:#f0f4f8; font-weight:400; }
h1,h2,h3,h4,h5,h6 { font-weight:800 !important; }
.container-fluid { max-width:1500px; margin:0 auto; padding:20px; }

.page-header {
    background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);
    padding:20px 30px; border-radius:12px;
    box-shadow:0 4px 15px rgba(30,58,138,0.3); margin-bottom:22px;
    display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:14px;
}
.page-header h1 { color:white; margin:0; font-size:1.7rem; }
.page-header p { color:rgba(255,255,255,0.75); font-size:13px; margin-top:4px; }
.btn-back {
    background:rgba(255,255,255,0.15); color:white; border:2px solid rgba(255,255,255,0.4);
    padding:9px 20px; border-radius:8px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;
    font-weight:700; font-size:13px;
}
.btn-back:hover { background:rgba(255,255,255,0.25); color:white; text-decoration:none; }

.summary-row { display:grid; grid-template-columns:repeat(4,1fr); gap:16px; margin-bottom:22px; }
.stat-card { background:#fff; border-radius:12px; padding:18px 20px; box-shadow:0 2px 10px rgba(0,0,0,0.06); border-left:4px solid #1e3a8a; }
.stat-card .stat-label { font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.5px; color:#64748b; margin-bottom:6px; }
.stat-card .stat-value { font-size:22px; font-weight:800; color:#0f2557; }
.stat-card.present { border-left-color:#10b981; }
.stat-card.future { border-left-color:#f59e0b; }
.stat-card.combined { border-left-color:#7c3aed; }
.stat-breakdown { display:flex; flex-wrap:wrap; gap:6px; margin-top:10px; }
.stat-chip { display:inline-block; font-size:10.5px; font-weight:700; padding:4px 9px; border-radius:20px; white-space:nowrap; }
.stat-chip.hire { background:#fef3c7; color:#92400e; }
.stat-chip.freelance { background:#ede9fe; color:#5b21b6; }
.stat-chip.present-chip { background:#d1fae5; color:#065f46; }
.stat-chip.future-chip { background:#fef3c7; color:#92400e; }

.card-box { background:white; border-radius:12px; padding:24px; box-shadow:0 2px 12px rgba(0,0,0,0.08); margin-bottom:20px; }

.tab-bar { display:flex; gap:10px; margin-bottom:20px; flex-wrap:wrap; }
.tab-btn {
    padding:11px 22px; border-radius:10px; border:2px solid #e2e8f0; background:#fff; color:#64748b;
    font-weight:700; font-size:13.5px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;
}
.tab-btn.active { background:linear-gradient(135deg,#1e3a8a,#1e40af); color:#fff; border-color:#1e3a8a; }
.tab-btn:hover { text-decoration:none; }

.filter-bar .form-group { margin-bottom:16px; }
.filter-bar label { font-size:12px; font-weight:700; color:#374151; margin-bottom:5px; display:block; }
.form-control { border:2px solid #e2e8f0; border-radius:8px; padding:9px 13px; font-size:13px; color:#1e293b; }
.form-control:focus { border-color:#1e3a8a; box-shadow:none; outline:none; }
select.form-control { padding:8px 13px; height:auto; }

.mp-table { width:100%; border-collapse:collapse; font-size:13.5px; }
.mp-table th { background:linear-gradient(135deg,#0f2557 0%,#15328a 100%); color:#fff; font-weight:800; text-transform:uppercase; font-size:12px; letter-spacing:.4px; padding:13px 15px; text-align:left; white-space:nowrap; position:sticky; top:0; z-index:5; box-shadow:0 3px 8px rgba(0,0,0,.35); border-bottom:3px solid #f59e0b; }
.mp-table td { padding:11px 15px; border-bottom:1px solid #f1f5f9; white-space:nowrap; font-size:13.5px; }
.mp-table tr.company-row td { background:linear-gradient(135deg,#2563eb 0%,#3b82f6 100%); color:#fff; font-weight:800; font-size:14.5px; padding:13px 15px; box-shadow:0 2px 5px rgba(0,0,0,.2); }
.mp-table tr.dept-header-row td { background:#eef2ff; font-weight:800; color:#4338ca; font-size:13px; padding:11px 15px 11px 15px; border-top:2px solid #e0e7ff; }
.mp-table tr.dept-header-row td:first-child { border-left:5px solid #6366f1; }
.mp-table tr.position-header-row td { background:#ecfeff; font-weight:700; color:#0e7490; font-size:12.5px; padding:9px 15px 9px 30px; }
.mp-table tr.position-header-row td:first-child { border-left:5px solid #06b6d4; }
.mp-table tr.position-subtotal-row td { background:#fffbeb; font-weight:800; color:#b45309; font-size:12.5px; padding-left:30px; border-top:1px dashed #fde68a; border-bottom:1px dashed #fde68a; }
.mp-table tr.position-subtotal-row td:first-child { border-left:5px solid #f59e0b; }
.mp-table tr.subtotal-row td { background:#f5f3ff; font-weight:800; color:#5b21b6; font-size:13.5px; border-top:2px solid #ede9fe; }
.mp-table tr.subtotal-row td:first-child { border-left:5px solid #7c3aed; }
.mp-table tr.dept-spacer-row td { background:#fff; border-bottom:none; border-left:none; padding:6px; }
.mp-table tr.position-spacer-row td { background:#fff; border-bottom:none; border-left:none; padding:3px; }
.mp-table tbody tr:not(.company-row):not(.subtotal-row):not(.position-subtotal-row):not(.dept-header-row):not(.position-header-row):not(.dept-spacer-row):not(.position-spacer-row) { cursor:pointer; }
.mp-table tbody tr:not(.company-row):not(.subtotal-row):not(.position-subtotal-row):not(.dept-header-row):not(.position-header-row):not(.dept-spacer-row):not(.position-spacer-row):hover td { background:#eff6ff; }

/* Table scroll container: mouse-drag (cursor) scrolling in both directions */
.dc-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; flex-wrap:wrap; gap:8px; }
.dc-name { font-size:19px; font-weight:800; color:#1e293b; }
.dc-type-badge { background:#1e3a8a; color:#fff; padding:5px 14px; border-radius:20px; font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.3px; }
.dc-section-title { font-size:11.5px; font-weight:800; text-transform:uppercase; color:#64748b; letter-spacing:.5px; margin:16px 0 10px; }
.dc-grid { display:grid; grid-template-columns:1fr 1fr; gap:12px 22px; }
.dc-grid-4 { grid-template-columns:repeat(4,1fr); }
.dc-grid-5 { grid-template-columns:repeat(5,1fr); }
.dc-item { display:flex; flex-direction:column; gap:2px; }
.dc-label { font-size:11px; color:#94a3b8; font-weight:700; text-transform:uppercase; letter-spacing:.3px; }
.dc-value { font-size:14.5px; color:#1e293b; font-weight:700; }
.table-scroll-wrap { overflow:auto; max-height:640px; cursor:grab; border-radius:0 0 12px 12px; }
.table-scroll-wrap.dragging { cursor:grabbing; user-select:none; }
.table-scroll-wrap::-webkit-scrollbar { width:10px; height:10px; }
.table-scroll-wrap::-webkit-scrollbar-track { background:#f1f5f9; }
.table-scroll-wrap::-webkit-scrollbar-thumb { background:#94a3b8; border-radius:6px; }
.table-scroll-wrap::-webkit-scrollbar-thumb:hover { background:#64748b; }
.type-badge { padding:3px 10px; border-radius:14px; font-size:10.5px; font-weight:800; }
.type-badge.hire { background:#dbeafe; color:#1e40af; }
.type-badge.freelancer { background:#fef3c7; color:#92400e; }
.status-badge { padding:3px 10px; border-radius:14px; font-size:10.5px; font-weight:800; }
.status-badge.planned { background:#e0e7ff; color:#3730a3; }
.status-badge.converted { background:#dcfce7; color:#065f46; }
.status-badge.cancelled { background:#fee2e2; color:#991b1b; }

.btn-p { padding:9px 18px; border:none; border-radius:8px; font-weight:700; font-size:13px; cursor:pointer; display:inline-flex; align-items:center; gap:7px; text-decoration:none; }
.btn-navy { background:linear-gradient(135deg,#1e3a8a,#1e40af); color:#fff; }
.btn-green { background:linear-gradient(135deg,#10b981,#059669); color:#fff; }
.btn-amber { background:linear-gradient(135deg,#f59e0b,#d97706); color:#fff; }
.btn-light { background:#f1f5f9; color:#334155; border:1px solid #e2e8f0; }
.btn-danger-sm { background:#fee2e2; color:#991b1b; border:none; padding:5px 10px; border-radius:6px; font-size:11px; font-weight:700; cursor:pointer; }
.btn-sm-action { background:#e0e7ff; color:#3730a3; border:none; padding:5px 10px; border-radius:6px; font-size:11px; font-weight:700; cursor:pointer; }

.action-bar { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:18px; }
.empty-hint { text-align:center; padding:40px 20px; color:#94a3b8; }
.empty-hint i { font-size:2rem; margin-bottom:10px; display:block; }
</style>
</head>
<body>
<div class="container-fluid">

    <div class="page-header">
        <div>
            <h1><i class="fas fa-chart-line"></i> Manpower Cost Analysis</h1>
            <p>Present and projected workforce cost — by hour, day, week, month, and year</p>
        </div>
        <div style="display:flex;gap:10px;">
            <a href="<?php echo $isAdmin ? 'index.php' : 'raise-a-ticket.php'; ?>" class="btn-back"><i class="fas fa-home"></i> Home</a>
            <a href="hr-payroll.php" class="btn-back"><i class="fas fa-money-check-alt"></i> Payroll Module</a>
        </div>
    </div>

    <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible"><button type="button" class="close" data-dismiss="alert">&times;</button>
        <?php echo htmlspecialchars($_SESSION['success_message']); unset($_SESSION['success_message']); ?>
    </div>
    <?php endif; ?>
    <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible"><button type="button" class="close" data-dismiss="alert">&times;</button>
        <?php echo htmlspecialchars($_SESSION['error_message']); unset($_SESSION['error_message']); ?>
    </div>
    <?php endif; ?>

    <!-- SUMMARY CARDS -->
    <div class="summary-row">
        <div class="stat-card present">
            <div class="stat-label"><i class="fas fa-users mr-1"></i> Present Headcount</div>
            <div class="stat-value"><?php echo $present_total_headcount; ?></div>
        </div>
        <div class="stat-card present">
            <div class="stat-label">Present Monthly Cost</div>
            <div class="stat-value"><?php echo mp_money($present_total_monthly); ?></div>
        </div>
        <div class="stat-card future">
            <div class="stat-label"><i class="fas fa-user-clock mr-1"></i> Future / Freelance Additions</div>
            <div class="stat-value"><?php echo $future_total_headcount; ?></div>
            <div class="stat-breakdown">
                <span class="stat-chip hire"><i class="fas fa-user-plus mr-1"></i><?php echo $future_hire_headcount; ?> Planned Hire<?php echo $future_hire_headcount!=1?'s':''; ?> &middot; <?php echo mp_money($future_hire_monthly); ?>/mo</span>
                <span class="stat-chip freelance"><i class="fas fa-laptop-code mr-1"></i><?php echo $future_freelance_headcount; ?> Freelancer<?php echo $future_freelance_headcount!=1?'s':''; ?> &middot; <?php echo mp_money($future_freelance_monthly); ?>/mo</span>
            </div>
        </div>
        <div class="stat-card combined">
            <div class="stat-label">Projected Total Monthly Cost</div>
            <div class="stat-value"><?php echo mp_money($combined_total_monthly); ?></div>
            <div class="stat-breakdown">
                <span class="stat-chip present-chip">Present: <?php echo mp_money($present_total_monthly); ?></span>
                <span class="stat-chip future-chip">+ Future: <?php echo mp_money($future_total_monthly); ?></span>
            </div>
        </div>
    </div>

    <!-- TABS -->
    <div class="tab-bar">
        <a href="?tab=present" class="tab-btn <?php echo $active_tab=='present'?'active':''; ?>"><i class="fas fa-user-check"></i> Present Manpower Cost</a>
        <a href="?tab=future" class="tab-btn <?php echo $active_tab=='future'?'active':''; ?>"><i class="fas fa-user-plus"></i> Future Manpower Cost</a>
        <a href="?tab=comparison" class="tab-btn <?php echo $active_tab=='comparison'?'active':''; ?>"><i class="fas fa-balance-scale"></i> Budget Impact / Comparison</a>
    </div>

    <!-- FILTER BAR -->
    <div class="card-box">
        <form method="GET" class="filter-bar">
            <input type="hidden" name="tab" value="<?php echo htmlspecialchars($active_tab); ?>">
            <div class="row">
                <div class="col-md-3 form-group">
                    <label>Search Name</label>
                    <input type="text" name="f_search" class="form-control" value="<?php echo htmlspecialchars($f_search); ?>" placeholder="Search by name...">
                </div>
                <div class="col-md-3 form-group">
                    <label>Company</label>
                    <select name="f_company" class="form-control">
                        <option value="">All Companies</option>
                        <?php foreach ($companies_list as $c): ?>
                        <option value="<?php echo htmlspecialchars($c); ?>" <?php echo $f_company===$c?'selected':''; ?>><?php echo htmlspecialchars($c); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-md-3 form-group">
                    <label>Department</label>
                    <select name="f_department" class="form-control">
                        <option value="">All Departments</option>
                        <?php foreach ($dept_list as $d): ?>
                        <option value="<?php echo htmlspecialchars($d); ?>" <?php echo $f_department===$d?'selected':''; ?>><?php echo htmlspecialchars($d); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="col-md-3 form-group">
                    <label>Designation</label>
                    <select name="f_position" class="form-control">
                        <option value="">All Designations</option>
                        <?php foreach ($pos_list as $p): ?>
                        <option value="<?php echo htmlspecialchars($p); ?>" <?php echo $f_position===$p?'selected':''; ?>><?php echo htmlspecialchars($p); ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
            <div class="row">
                <?php if ($active_tab === 'future'): ?>
                <div class="col-md-3 form-group">
                    <label>Entry Type</label>
                    <select name="f_type" class="form-control">
                        <option value="">All Types</option>
                        <option value="hire" <?php echo $f_type==='hire'?'selected':''; ?>>Planned Hire</option>
                        <option value="freelancer" <?php echo $f_type==='freelancer'?'selected':''; ?>>Freelancer</option>
                    </select>
                </div>
                <?php endif; ?>
                <div class="col-md-2 form-group">
                    <label>&nbsp;</label>
                    <button type="submit" class="btn-p btn-navy" style="width:100%;justify-content:center;"><i class="fas fa-filter"></i> Apply</button>
                </div>
                <div class="col-md-2 form-group">
                    <label>&nbsp;</label>
                    <a href="?tab=<?php echo $active_tab; ?>" class="btn-p btn-light" style="width:100%;justify-content:center;"><i class="fas fa-redo"></i> Reset</a>
                </div>
            </div>
        </form>
    </div>

    <?php if ($active_tab === 'present'): ?>
    <!-- ============================== PRESENT TAB ============================== -->
    <div class="action-bar">
        <a href="?action=export_present&f_company=<?php echo urlencode($f_company); ?>&f_department=<?php echo urlencode($f_department); ?>&f_position=<?php echo urlencode($f_position); ?>&f_search=<?php echo urlencode($f_search); ?>" class="btn-p btn-green"><i class="fas fa-file-excel"></i> Export to Excel</a>
        <a href="?action=print_present&tab=present&f_company=<?php echo urlencode($f_company); ?>&f_department=<?php echo urlencode($f_department); ?>&f_position=<?php echo urlencode($f_position); ?>&f_search=<?php echo urlencode($f_search); ?>" target="_blank" class="btn-p btn-navy"><i class="fas fa-file-pdf"></i> Export to PDF</a>
    </div>
    <div class="card-box" style="padding:0;overflow:hidden;">
        <?php if (empty($present_rows)): ?>
            <div class="empty-hint"><i class="fas fa-users-slash"></i><p>No active employees match this filter.</p></div>
        <?php else: ?>
        <div class="table-scroll-wrap">
        <table class="mp-table">
            <thead>
                <tr>
                    <th>Name</th><th>Department</th><th>Designation</th><th>Date of Joining</th>
                    <th>Basic</th><th>HRA</th><th>Conveyance</th><th>Special Allow.</th><th>Incentives</th>
                    <th>Total CTC / Month</th><th>Per Minute</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Year</th>
                </tr>
            </thead>
            <tbody>
            <?php foreach ($present_grouped as $co => $codata): ?>
                <tr class="company-row"><td colspan="15"><i class="fas fa-building mr-2"></i><?php echo htmlspecialchars($co); ?> &middot; <?php echo $codata['headcount']; ?> employee(s) &middot; <?php echo mp_money($codata['monthly']); ?> / month</td></tr>
                <?php foreach ($codata['depts'] as $dept => $deptdata): $deptCosts = mp_costs($deptdata['monthly']); ?>
                    <tr class="dept-header-row"><td colspan="15"><i class="fas fa-sitemap mr-2"></i><?php echo htmlspecialchars($dept); ?> Department (<?php echo $deptdata['headcount']; ?> employee(s))</td></tr>
                    <?php foreach ($deptdata['positions'] as $pos => $posdata): $posCosts = mp_costs($posdata['monthly']); ?>
                        <tr class="position-header-row"><td colspan="15"><i class="fas fa-user-tie mr-2"></i><?php echo htmlspecialchars($pos); ?> (<?php echo $posdata['headcount']; ?> employee(s))</td></tr>
                        <?php foreach ($posdata['rows'] as $r): ?>
                        <?php $cardData = [
                            'type' => 'Current Employee', 'employee_id' => $r['id'], 'name' => $r['name'], 'company' => $co,
                            'department' => $dept, 'position' => $r['position'] ?: '-',
                            'date_label' => 'Date of Joining', 'date' => $r['hire_date'] ? date('d M Y', strtotime($r['hire_date'])) : '-',
                            'basic' => mp_money($r['basic_salary'] ?? 0), 'hra' => mp_money($r['hra'] ?? 0),
                            'conveyance' => mp_money($r['conveyance'] ?? 0), 'special' => mp_money($r['special_allowance'] ?? 0),
                            'incentives' => mp_money($r['incentives'] ?? 0), 'total' => mp_money($r['total_used']),
                            'minute' => mp_money($r['costs']['minute']), 'hour' => mp_money($r['costs']['hour']), 'day' => mp_money($r['costs']['day']),
                            'week' => mp_money($r['costs']['week']), 'year' => mp_money($r['costs']['year']),
                            'documents' => $employee_documents_map[$r['id']] ?? [],
                        ]; ?>
                        <tr onclick="showDetailsCard(this)" data-card='<?php echo htmlspecialchars(json_encode($cardData), ENT_QUOTES); ?>'>
                            <td><strong><?php echo htmlspecialchars($r['name']); ?></strong><?php if (!$r['has_payroll']): ?><br><span style="font-size:10px;color:#f59e0b;">No payroll record — using base salary</span><?php endif; ?></td>
                            <td><?php echo htmlspecialchars($dept); ?></td>
                            <td><?php echo htmlspecialchars($r['position'] ?: '-'); ?></td>
                            <td><?php echo $r['hire_date'] ? date('d M Y', strtotime($r['hire_date'])) : '-'; ?></td>
                            <td><?php echo mp_money($r['basic_salary'] ?? 0); ?></td>
                            <td><?php echo mp_money($r['hra'] ?? 0); ?></td>
                            <td><?php echo mp_money($r['conveyance'] ?? 0); ?></td>
                            <td><?php echo mp_money($r['special_allowance'] ?? 0); ?></td>
                            <td><?php echo mp_money($r['incentives'] ?? 0); ?></td>
                            <td><strong><?php echo mp_money($r['total_used']); ?></strong></td>
                            <td><?php echo mp_money($r['costs']['minute']); ?></td>
                            <td><?php echo mp_money($r['costs']['hour']); ?></td>
                            <td><?php echo mp_money($r['costs']['day']); ?></td>
                            <td><?php echo mp_money($r['costs']['week']); ?></td>
                            <td><?php echo mp_money($r['costs']['year']); ?></td>
                        </tr>
                        <?php endforeach; ?>
                        <tr class="position-subtotal-row">
                            <td colspan="3"><?php echo htmlspecialchars($pos); ?> Subtotal (<?php echo $posdata['headcount']; ?>)</td>
                            <td colspan="6"></td>
                            <td><?php echo mp_money($posdata['monthly']); ?></td>
                            <td><?php echo mp_money($posCosts['minute']); ?></td>
                            <td><?php echo mp_money($posCosts['hour']); ?></td>
                            <td><?php echo mp_money($posCosts['day']); ?></td>
                            <td><?php echo mp_money($posCosts['week']); ?></td>
                            <td><?php echo mp_money($posCosts['year']); ?></td>
                        </tr>
                        <tr class="position-spacer-row"><td colspan="15">&nbsp;</td></tr>
                    <?php endforeach; ?>
                    <tr class="subtotal-row">
                        <td colspan="4"><?php echo htmlspecialchars($dept); ?> Department Total (<?php echo $deptdata['headcount']; ?>)</td>
                        <td colspan="5"></td>
                        <td><?php echo mp_money($deptdata['monthly']); ?></td>
                        <td><?php echo mp_money($deptCosts['minute']); ?></td>
                        <td><?php echo mp_money($deptCosts['hour']); ?></td>
                        <td><?php echo mp_money($deptCosts['day']); ?></td>
                        <td><?php echo mp_money($deptCosts['week']); ?></td>
                        <td><?php echo mp_money($deptCosts['year']); ?></td>
                    </tr>
                    <tr class="dept-spacer-row"><td colspan="15">&nbsp;</td></tr>
                <?php endforeach; ?>
            <?php endforeach; ?>
            </tbody>
        </table>
        </div>
        <?php endif; ?>
    </div>

    <?php elseif ($active_tab === 'future'): ?>
    <!-- ============================== FUTURE TAB ============================== -->
    <div class="action-bar">
        <button type="button" class="btn-p btn-navy" onclick="openAddFutureModal()"><i class="fas fa-plus"></i> Add Future Entry</button>
        <button type="button" class="btn-p btn-amber" data-toggle="modal" data-target="#importModal"><i class="fas fa-file-import"></i> Import</button>
        <a href="?action=export_future&f_company=<?php echo urlencode($f_company); ?>&f_department=<?php echo urlencode($f_department); ?>&f_position=<?php echo urlencode($f_position); ?>&f_search=<?php echo urlencode($f_search); ?>&f_type=<?php echo urlencode($f_type); ?>" class="btn-p btn-green"><i class="fas fa-file-excel"></i> Export to Excel</a>
        <a href="?action=print_future&tab=future&f_company=<?php echo urlencode($f_company); ?>&f_department=<?php echo urlencode($f_department); ?>&f_position=<?php echo urlencode($f_position); ?>&f_search=<?php echo urlencode($f_search); ?>&f_type=<?php echo urlencode($f_type); ?>" target="_blank" class="btn-p btn-navy"><i class="fas fa-file-pdf"></i> Export to PDF</a>
    </div>

    <div class="card-box" style="padding:0;overflow:hidden;">
        <?php if (empty($all_future_rows)): ?>
            <div class="empty-hint"><i class="fas fa-user-plus"></i><p>No future hires or freelancers added yet. Use "Add Future Entry" or import a template to get started.</p></div>
        <?php else: ?>
        <div class="table-scroll-wrap">
        <table class="mp-table">
            <thead>
                <tr>
                    <th>Type</th><th>Name</th><th>Company</th><th>Department</th><th>Designation</th><th>Expected Joining</th>
                    <th>Total CTC / Month</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Year</th><th>Status</th><th>Actions</th>
                </tr>
            </thead>
            <tbody>
            <?php foreach ($all_future_rows as $r): $c = mp_costs($r['total_ctc']);
                $cardData = [
                    'type' => $r['entry_type']==='freelancer'?'Freelancer':'Planned Hire', 'name' => $r['name'],
                    'company' => hr_canonical_company_label($r['company_name'], $company_norm_to_label),
                    'department' => $r['department'] ?: '-', 'position' => $r['position'] ?: '-',
                    'date_label' => 'Expected Joining', 'date' => $r['expected_joining_date'] ? date('d M Y', strtotime($r['expected_joining_date'])) : '-',
                    'basic' => mp_money($r['basic_salary'] ?? 0), 'hra' => mp_money($r['hra'] ?? 0),
                    'conveyance' => mp_money($r['conveyance'] ?? 0), 'special' => mp_money($r['special_allowance'] ?? 0),
                    'incentives' => mp_money($r['incentives'] ?? 0), 'total' => mp_money($r['total_ctc']),
                    'hour' => mp_money($c['hour']), 'day' => mp_money($c['day']),
                    'week' => mp_money($c['week']), 'year' => mp_money($c['year']),
                    'status' => ucfirst($r['status']),
                ];
            ?>
                <tr onclick="showDetailsCard(this)" data-card='<?php echo htmlspecialchars(json_encode($cardData), ENT_QUOTES); ?>'>
                    <td><span class="type-badge <?php echo $r['entry_type']; ?>"><?php echo $r['entry_type']==='freelancer'?'Freelancer':'Planned Hire'; ?></span></td>
                    <td><strong><?php echo htmlspecialchars($r['name']); ?></strong></td>
                    <td><?php echo htmlspecialchars(hr_canonical_company_label($r['company_name'], $company_norm_to_label)); ?></td>
                    <td><?php echo htmlspecialchars($r['department'] ?: '-'); ?></td>
                    <td><?php echo htmlspecialchars($r['position'] ?: '-'); ?></td>
                    <td><?php echo $r['expected_joining_date'] ? date('d M Y', strtotime($r['expected_joining_date'])) : '-'; ?></td>
                    <td><strong><?php echo mp_money($r['total_ctc']); ?></strong></td>
                    <td><?php echo mp_money($c['hour']); ?></td>
                    <td><?php echo mp_money($c['day']); ?></td>
                    <td><?php echo mp_money($c['week']); ?></td>
                    <td><?php echo mp_money($c['year']); ?></td>
                    <td><span class="status-badge <?php echo $r['status']; ?>"><?php echo ucfirst($r['status']); ?></span></td>
                    <td onclick="event.stopPropagation();">
                        <div style="display:flex;gap:6px;flex-wrap:wrap;">
                        <button type="button" class="btn-sm-action" onclick='openEditFutureModal(<?php echo json_encode($r); ?>)'><i class="fas fa-edit"></i></button>
                        <?php if ($r['status'] === 'planned'): ?>
                        <button type="button" class="btn-sm-action" style="background:#dcfce7;color:#065f46;" onclick="openConvertModal(<?php echo $r['id']; ?>, '<?php echo htmlspecialchars(addslashes($r['name'])); ?>')" title="Mark as Hired / Converted"><i class="fas fa-check"></i></button>
                        <?php endif; ?>
                        <button type="button" class="btn-danger-sm" onclick="deleteFutureEntry(<?php echo $r['id']; ?>, '<?php echo htmlspecialchars(addslashes($r['name'])); ?>')"><i class="fas fa-trash"></i></button>
                        </div>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        </div>
        <?php endif; ?>
    </div>

    <?php else: ?>
    <!-- ============================== COMPARISON TAB ============================== -->
    <div class="action-bar">
        <a href="?action=print_comparison&tab=comparison&f_company=<?php echo urlencode($f_company); ?>&f_department=<?php echo urlencode($f_department); ?>&f_position=<?php echo urlencode($f_position); ?>&f_search=<?php echo urlencode($f_search); ?>" target="_blank" class="btn-p btn-navy"><i class="fas fa-file-pdf"></i> Export to PDF</a>
    </div>
    <div class="card-box">
        <h5 style="margin-bottom:16px;"><i class="fas fa-balance-scale mr-2" style="color:#7c3aed;"></i>Overall Budget Impact</h5>
        <div class="table-scroll-wrap">
        <table class="mp-table">
            <thead><tr><th></th><th>Headcount</th><th>Per Hour</th><th>Per Day</th><th>Per Week</th><th>Per Month</th><th>Per Year</th></tr></thead>
            <tbody>
                <tr><td><strong>Present (Current Employees)</strong></td><td><?php echo $present_total_headcount; ?></td>
                    <td><?php echo mp_money($present_costs['hour']); ?></td><td><?php echo mp_money($present_costs['day']); ?></td>
                    <td><?php echo mp_money($present_costs['week']); ?></td><td><?php echo mp_money($present_costs['month']); ?></td><td><?php echo mp_money($present_costs['year']); ?></td></tr>
                <tr><td><strong>Future (Planned Hires + Freelancers)</strong></td><td><span style="color:#dc2626;font-weight:800;"><?php echo $future_total_headcount; ?></span></td>
                    <td><?php echo mp_money($future_costs['hour']); ?></td><td><?php echo mp_money($future_costs['day']); ?></td>
                    <td><?php echo mp_money($future_costs['week']); ?></td><td><?php echo mp_money($future_costs['month']); ?></td><td><?php echo mp_money($future_costs['year']); ?></td></tr>
                <tr class="subtotal-row"><td><strong>Projected Total</strong></td><td><?php echo $combined_total_headcount; ?></td>
                    <td><?php echo mp_money($combined_costs['hour']); ?></td><td><?php echo mp_money($combined_costs['day']); ?></td>
                    <td><?php echo mp_money($combined_costs['week']); ?></td><td><?php echo mp_money($combined_costs['month']); ?></td><td><?php echo mp_money($combined_costs['year']); ?></td></tr>
            </tbody>
        </table>
        </div>
        <div style="margin-top:16px;padding:14px 18px;background:#f5f3ff;border:1px solid #ddd6fe;border-radius:10px;">
            <strong style="color:#5b21b6;">Budget Impact:</strong> Hiring/onboarding everything currently in the Future list would increase monthly manpower cost by
            <strong style="color:#5b21b6;"><?php echo mp_money($future_total_monthly); ?></strong> (<?php echo mp_money($future_costs['year']); ?> annually),
            a <strong style="color:#5b21b6;"><?php echo $present_total_monthly > 0 ? round(($future_total_monthly/$present_total_monthly)*100, 1) : 0; ?>%</strong> increase over current spend.
        </div>
    </div>

    <div class="card-box">
        <h5 style="margin-bottom:16px;"><i class="fas fa-building mr-2" style="color:#1e3a8a;"></i>Per-Company Comparison</h5>
        <div class="table-scroll-wrap">
        <table class="mp-table">
            <thead><tr><th>Company</th><th>Present Headcount</th><th>Present Monthly</th><th>Future Additions</th><th>Future Monthly</th><th>Projected Total Monthly</th></tr></thead>
            <tbody>
            <?php foreach ($company_comparison as $co => $d): ?>
                <tr>
                    <td><strong><?php echo htmlspecialchars($co); ?></strong></td>
                    <td><?php echo $d['present_headcount']; ?></td>
                    <td><?php echo mp_money($d['present_monthly']); ?></td>
                    <td><?php if ($d['future_headcount'] > 0): ?><span style="color:#dc2626;font-weight:800;"><?php echo $d['future_headcount']; ?></span> <span style="color:#dc2626;font-size:11px;font-weight:600;">(Planned/Freelance)</span><?php else: ?>0<?php endif; ?></td>
                    <td><?php echo mp_money($d['future_monthly']); ?></td>
                    <td><strong><?php echo mp_money($d['present_monthly'] + $d['future_monthly']); ?></strong></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        </div>
    </div>
    <?php endif; ?>

</div>

<!-- ADD / EDIT FUTURE ENTRY MODAL -->
<div class="modal fade" id="futureEntryModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST" id="futureEntryForm">
      <input type="hidden" name="save_future_entry" value="1">
      <input type="hidden" name="future_id" id="fe_id" value="0">
      <div class="modal-header"><h5 class="modal-title" id="fe_title"><i class="fas fa-user-plus mr-2"></i>Add Future Entry</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="row">
            <div class="col-md-4 form-group"><label>Entry Type *</label>
                <select name="entry_type" id="fe_type" class="form-control" required>
                    <option value="hire">Planned Hire</option>
                    <option value="freelancer">Freelancer</option>
                </select>
            </div>
            <div class="col-md-4 form-group"><label>Name *</label><input type="text" name="name" id="fe_name" class="form-control" required></div>
            <div class="col-md-4 form-group"><label>Expected Joining Date</label><input type="date" name="expected_joining_date" id="fe_join" class="form-control"></div>
        </div>
        <div class="row">
            <div class="col-md-4 form-group"><label>Company</label>
                <select name="company_name" id="fe_company" class="form-control">
                    <option value="">Select Company</option>
                    <?php foreach ($companies_list as $c): ?><option value="<?php echo htmlspecialchars($c); ?>"><?php echo htmlspecialchars($c); ?></option><?php endforeach; ?>
                </select>
            </div>
            <div class="col-md-4 form-group"><label>Department</label>
                <select id="fe_department_select" class="form-control" onchange="feDeptChanged()">
                    <option value="">Select Department</option>
                    <?php foreach ($dept_list as $d): ?><option value="<?php echo htmlspecialchars($d); ?>"><?php echo htmlspecialchars($d); ?></option><?php endforeach; ?>
                    <option value="__other__">+ Add New Department...</option>
                </select>
                <input type="text" id="fe_department_new" class="form-control" placeholder="Type new department name" style="display:none;margin-top:6px;" oninput="document.getElementById('fe_department').value=this.value;">
                <input type="hidden" name="department" id="fe_department">
            </div>
            <div class="col-md-4 form-group"><label>Designation</label>
                <select id="fe_position_select" class="form-control" onchange="fePosChanged()">
                    <option value="">Select Designation</option>
                    <option value="__other__">+ Add New Designation...</option>
                </select>
                <input type="text" id="fe_position_new" class="form-control" placeholder="Type new designation" style="display:none;margin-top:6px;" oninput="document.getElementById('fe_position').value=this.value;">
                <input type="hidden" name="position" id="fe_position">
                <small style="color:#64748b;font-size:11px;">Narrows to designations used in the picked department.</small>
            </div>
        </div>
        <hr>
        <p style="font-size:12px;color:#64748b;">Fill in a salary breakdown for planned hires, or just the Total CTC for freelancers (a flat monthly rate is fine).</p>
        <div class="form-group" style="font-weight:800;">Total CTC / Month *
            <div style="display:flex;gap:8px;align-items:center;">
                <input type="number" step="0.01" name="total_ctc" id="fe_total" class="form-control" required style="font-weight:800;">
                <button type="button" class="btn btn-outline-primary" style="white-space:nowrap;font-weight:700;" onclick="feCalculateBreakdown()"><i class="fas fa-calculator mr-1"></i> Auto-Calculate</button>
            </div>
            <small style="color:#64748b;font-weight:400;">Enter the total monthly salary above, then click Auto-Calculate to split it into Basic / HRA / Conveyance / Special Allowance using the same formula as Payroll (Basic = 40% of Total, HRA = 50% of Basic, Conveyance = ₹3,000 flat, Special Allowance = remainder).</small>
        </div>
        <div class="row">
            <div class="col-md-2 form-group"><label>Basic</label><input type="number" step="0.01" name="basic_salary" id="fe_basic" class="form-control" value="0" oninput="feAutoTotal()"></div>
            <div class="col-md-2 form-group"><label>HRA</label><input type="number" step="0.01" name="hra" id="fe_hra" class="form-control" value="0" oninput="feAutoTotal()"></div>
            <div class="col-md-2 form-group"><label>Conveyance</label><input type="number" step="0.01" name="conveyance" id="fe_conveyance" class="form-control" value="0" oninput="feAutoTotal()"></div>
            <div class="col-md-2 form-group"><label>Special Allow.</label><input type="number" step="0.01" name="special_allowance" id="fe_special" class="form-control" value="0" oninput="feAutoTotal()"></div>
            <div class="col-md-2 form-group"><label>Incentives</label><input type="number" step="0.01" name="incentives" id="fe_incentives" class="form-control" value="0"></div>
            <div class="col-md-2 form-group"><label>Gross Pay</label><input type="number" step="0.01" name="gross_pay" id="fe_gross" class="form-control" value="0"></div>
        </div>
        <div class="form-group"><label>Notes</label><textarea name="notes" id="fe_notes" class="form-control" rows="2"></textarea></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn btn-primary"><i class="fas fa-save mr-1"></i> Save</button>
      </div>
    </form>
  </div></div>
</div>

<!-- IMPORT MODAL -->
<div class="modal fade" id="importModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="import_future" value="1">
      <div class="modal-header" style="background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);color:#fff;border-radius:14px 14px 0 0;"><h5 class="modal-title"><i class="fas fa-file-import mr-2"></i>Import Future Entries</h5><button type="button" class="close" data-dismiss="modal" style="color:#fff;opacity:.9;text-shadow:none;">&times;</button></div>
      <div class="modal-body">
        <div style="display:flex;gap:12px;align-items:flex-start;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px 16px;margin-bottom:14px;">
            <div style="background:#1e3a8a;color:#fff;width:26px;height:26px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;flex:0 0 auto;">1</div>
            <div style="flex:1;">
                <strong style="font-size:13.5px;color:#1e293b;">Download the CSV template</strong>
                <p style="font-size:12px;color:#64748b;margin:4px 0 8px;">Get the template with the exact columns needed, plus example rows for a hire and a freelancer.</p>
                <a href="?action=download_template" class="btn-p btn-light" style="font-size:12px;padding:7px 14px;"><i class="fas fa-download"></i> Download Template</a>
            </div>
        </div>
        <div style="display:flex;gap:12px;align-items:flex-start;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px 16px;">
            <div style="background:#1e3a8a;color:#fff;width:26px;height:26px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;flex:0 0 auto;">2</div>
            <div style="flex:1;">
                <strong style="font-size:13.5px;color:#1e293b;">Fill it in, then upload it here</strong>
                <div class="form-group" style="margin-top:8px;margin-bottom:0;"><input type="file" name="csv_file" class="form-control-file" accept=".csv" required></div>
            </div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn btn-primary"><i class="fas fa-upload mr-1"></i> Upload &amp; Import</button>
      </div>
    </form>
  </div></div>
</div>

<!-- CONVERT TO EMPLOYEE MODAL -->
<div class="modal fade" id="convertModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="convert_future_entry" value="1">
      <input type="hidden" name="future_id" id="cv_id" value="0">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-check-circle mr-2"></i>Mark as Hired / Converted</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <p style="font-size:13px;color:#475569;">Marking <strong id="cv_name"></strong> as converted removes them from Future projections. If they now have a real employee record, link it below so the cost carries over correctly into Present.</p>
        <div class="form-group">
            <label>Link to Employee Record (optional)</label>
            <select name="linked_employee_id" class="form-control">
                <option value="0">-- Not linked yet --</option>
                <?php foreach ($active_employees_list as $emp): ?>
                <option value="<?php echo $emp['id']; ?>"><?php echo htmlspecialchars($emp['name']); ?></option>
                <?php endforeach; ?>
            </select>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
        <button type="submit" class="btn btn-success"><i class="fas fa-check mr-1"></i> Confirm</button>
      </div>
    </form>
  </div></div>
</div>

<!-- DETAILS CARD OVERLAY (shown when a table row is clicked) -->
<div class="modal fade" id="detailsCardModal" tabindex="-1">
  <div class="modal-dialog modal-md"><div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#1e3a8a 0%,#1e40af 100%);color:#fff;border-radius:14px 14px 0 0;">
        <h5 class="modal-title"><i class="fas fa-id-card mr-2"></i>Person Details</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;opacity:.9;text-shadow:none;">&times;</button>
    </div>
    <div class="modal-body" id="detailsCardBody"></div>
    <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button></div>
  </div></div>
</div>

<!-- HIDDEN DELETE / CANCEL FORMS -->
<form method="POST" id="deleteFutureForm" style="display:none;">
    <input type="hidden" name="delete_future_entry" value="1">
    <input type="hidden" name="future_id" id="del_fe_id" value="0">
</form>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
<script>
// Cursor-drag scrolling (horizontal + vertical) for every table container —
// click and drag anywhere on a table to scroll it, in addition to the normal
// scrollbars / mouse wheel.
document.addEventListener('DOMContentLoaded', function() {
    document.querySelectorAll('.table-scroll-wrap').forEach(function(wrap) {
        var isDown = false, startX, startY, scrollLeftStart, scrollTopStart;
        wrap.addEventListener('mousedown', function(e) {
            isDown = true;
            wrap.classList.add('dragging');
            startX = e.pageX - wrap.offsetLeft;
            startY = e.pageY - wrap.offsetTop;
            scrollLeftStart = wrap.scrollLeft;
            scrollTopStart = wrap.scrollTop;
        });
        ['mouseleave', 'mouseup'].forEach(function(evt) {
            wrap.addEventListener(evt, function() { isDown = false; wrap.classList.remove('dragging'); });
        });
        wrap.addEventListener('mousemove', function(e) {
            if (!isDown) return;
            e.preventDefault();
            var x = e.pageX - wrap.offsetLeft;
            var y = e.pageY - wrap.offsetTop;
            wrap.scrollLeft = scrollLeftStart - (x - startX);
            wrap.scrollTop = scrollTopStart - (y - startY);
        });
    });
});

function showDetailsCard(tr) {
    var raw = tr.getAttribute('data-card');
    if (!raw) return;
    var d = JSON.parse(raw);
    function grid(pairs, extraClass) {
        var html = '<div class="dc-grid ' + (extraClass || '') + '">';
        pairs.forEach(function(p) {
            html += '<div class="dc-item"><span class="dc-label">' + p[0] + '</span><span class="dc-value">' + p[1] + '</span></div>';
        });
        return html + '</div>';
    }
    var topRows = [['Company', d.company], ['Department', d.department], ['Designation', d.position], [d.date_label, d.date]];
    if (d.status) topRows.push(['Status', d.status]);
    var salaryRows = [['Basic', d.basic], ['HRA', d.hra], ['Conveyance', d.conveyance], ['Special Allowance', d.special], ['Incentives', d.incentives], ['Total CTC / Month', d.total]];
    var costRows = d.minute !== undefined
        ? [['Per Minute', d.minute], ['Per Hour', d.hour], ['Per Day', d.day], ['Per Week', d.week], ['Per Year', d.year]]
        : [['Per Hour', d.hour], ['Per Day', d.day], ['Per Week', d.week], ['Per Year', d.year]];
    var html = '<div class="dc-header"><div class="dc-name">' + d.name + '</div><span class="dc-type-badge">' + d.type + '</span></div>';
    html += grid(topRows);
    html += '<div class="dc-section-title">Salary Breakdown</div>' + grid(salaryRows);
    html += '<div class="dc-section-title">Cost Breakdown</div>' + grid(costRows, d.minute !== undefined ? 'dc-grid-5' : 'dc-grid-4');
    if (d.documents && d.documents.length) {
        html += '<div class="dc-section-title">Documents</div><div style="display:flex;flex-direction:column;gap:8px;">';
        d.documents.forEach(function(doc) {
            html += '<div style="display:flex;justify-content:space-between;align-items:center;background:#f8faff;border:1px solid #e0e7ff;border-radius:8px;padding:9px 12px;">' +
                '<div><i class="fas fa-file-signature mr-2" style="color:#1a3fc4;"></i><strong style="font-size:12.5px;color:#0f2557;">' + doc.label + '</strong><div style="font-size:10.5px;color:#64748b;">Filed ' + doc.date + '</div></div>' +
                (doc.url ? '<a href="' + doc.url + '" target="_blank" class="btn-p btn-navy" style="padding:5px 12px;font-size:11px;text-decoration:none;"><i class="fas fa-download"></i></a>' : '') +
                '</div>';
        });
        html += '</div>';
    }
    if (d.employee_id) {
        html += '<div style="margin-top:18px;border-top:1px solid #f1f5f9;padding-top:16px;"><a href="hr-employee-offer.php?page=revise&employee_id=' + d.employee_id + '" class="btn-p btn-navy" style="text-decoration:none;"><i class="fas fa-file-signature"></i> Generate Revised Offer</a></div>';
    }
    document.getElementById('detailsCardBody').innerHTML = html;
    $('#detailsCardModal').modal('show');
}
var deptPositionMap = <?php echo json_encode($dept_position_map); ?>;
var allPositionsList = <?php echo json_encode($pos_list); ?>;

// Rebuild the Designation <select> options for the given department (or the full list if none/unknown)
function feRebuildPositionOptions(dept, selectedValue) {
    var sel = document.getElementById('fe_position_select');
    var list = (dept && deptPositionMap[dept] && deptPositionMap[dept].length) ? deptPositionMap[dept] : allPositionsList;
    sel.innerHTML = '';
    var opt0 = document.createElement('option'); opt0.value = ''; opt0.textContent = 'Select Designation'; sel.appendChild(opt0);
    list.forEach(function(p) {
        var opt = document.createElement('option');
        opt.value = p; opt.textContent = p;
        sel.appendChild(opt);
    });
    var optOther = document.createElement('option'); optOther.value = '__other__'; optOther.textContent = '+ Add New Designation...'; sel.appendChild(optOther);

    if (selectedValue && list.indexOf(selectedValue) !== -1) {
        sel.value = selectedValue;
        document.getElementById('fe_position_new').style.display = 'none';
        document.getElementById('fe_position').value = selectedValue;
    } else if (selectedValue) {
        sel.value = '__other__';
        document.getElementById('fe_position_new').style.display = 'block';
        document.getElementById('fe_position_new').value = selectedValue;
        document.getElementById('fe_position').value = selectedValue;
    } else {
        sel.value = '';
        document.getElementById('fe_position_new').style.display = 'none';
        document.getElementById('fe_position_new').value = '';
        document.getElementById('fe_position').value = '';
    }
}
// User picked a Department: sync hidden field, show/hide "new" box, and refresh Designation choices
function feDeptChanged() {
    var sel = document.getElementById('fe_department_select');
    var newBox = document.getElementById('fe_department_new');
    if (sel.value === '__other__') {
        newBox.style.display = 'block';
        newBox.focus();
        document.getElementById('fe_department').value = newBox.value;
    } else {
        newBox.style.display = 'none';
        newBox.value = '';
        document.getElementById('fe_department').value = sel.value;
    }
    feRebuildPositionOptions(sel.value === '__other__' ? '' : sel.value, null);
}
function fePosChanged() {
    var sel = document.getElementById('fe_position_select');
    var newBox = document.getElementById('fe_position_new');
    if (sel.value === '__other__') {
        newBox.style.display = 'block';
        newBox.focus();
        document.getElementById('fe_position').value = newBox.value;
    } else {
        newBox.style.display = 'none';
        newBox.value = '';
        document.getElementById('fe_position').value = sel.value;
    }
}
// Set the Department select/new-box to a given value (used when loading an entry for edit)
function feSetDepartment(dept) {
    var sel = document.getElementById('fe_department_select');
    var options = Array.prototype.map.call(sel.options, function(o) { return o.value; });
    if (dept && options.indexOf(dept) !== -1) {
        sel.value = dept;
        document.getElementById('fe_department_new').style.display = 'none';
        document.getElementById('fe_department_new').value = '';
    } else if (dept) {
        sel.value = '__other__';
        document.getElementById('fe_department_new').style.display = 'block';
        document.getElementById('fe_department_new').value = dept;
    } else {
        sel.value = '';
        document.getElementById('fe_department_new').style.display = 'none';
        document.getElementById('fe_department_new').value = '';
    }
    document.getElementById('fe_department').value = dept || '';
}
function feCalculateBreakdown() {
    var gross = parseFloat(document.getElementById('fe_total').value) || 0;
    if (gross <= 0) {
        Swal.fire('Enter Total CTC first', 'Type the monthly salary amount in "Total CTC / Month" before calculating.', 'warning');
        return;
    }
    var basic = Math.round(gross * 0.40 * 100) / 100;
    var hra = Math.round(basic * 0.50 * 100) / 100;
    var conveyance = 3000;
    var special = Math.max(0, Math.round((gross - (basic + hra + conveyance)) * 100) / 100);
    document.getElementById('fe_basic').value = basic.toFixed(2);
    document.getElementById('fe_hra').value = hra.toFixed(2);
    document.getElementById('fe_conveyance').value = conveyance.toFixed(2);
    document.getElementById('fe_special').value = special.toFixed(2);
    document.getElementById('fe_gross').value = (basic + hra + conveyance + special).toFixed(2);
}
function openAddFutureModal() {
    document.getElementById('futureEntryForm').reset();
    document.getElementById('fe_id').value = 0;
    document.getElementById('fe_title').innerHTML = '<i class="fas fa-user-plus mr-2"></i>Add Future Entry';
    feSetDepartment('');
    feRebuildPositionOptions('', null);
    $('#futureEntryModal').modal('show');
}
function openEditFutureModal(row) {
    document.getElementById('fe_id').value = row.id;
    document.getElementById('fe_type').value = row.entry_type;
    document.getElementById('fe_name').value = row.name;
    document.getElementById('fe_join').value = row.expected_joining_date || '';
    document.getElementById('fe_company').value = row.company_name || '';
    feSetDepartment(row.department || '');
    feRebuildPositionOptions(row.department || '', row.position || '');
    document.getElementById('fe_basic').value = row.basic_salary || 0;
    document.getElementById('fe_hra').value = row.hra || 0;
    document.getElementById('fe_conveyance').value = row.conveyance || 0;
    document.getElementById('fe_special').value = row.special_allowance || 0;
    document.getElementById('fe_incentives').value = row.incentives || 0;
    document.getElementById('fe_gross').value = row.gross_pay || 0;
    document.getElementById('fe_total').value = row.total_ctc || 0;
    document.getElementById('fe_notes').value = row.notes || '';
    document.getElementById('fe_title').innerHTML = '<i class="fas fa-edit mr-2"></i>Edit Future Entry';
    $('#futureEntryModal').modal('show');
}
function feAutoTotal() {
    var basic = parseFloat(document.getElementById('fe_basic').value) || 0;
    var hra = parseFloat(document.getElementById('fe_hra').value) || 0;
    var conv = parseFloat(document.getElementById('fe_conveyance').value) || 0;
    var special = parseFloat(document.getElementById('fe_special').value) || 0;
    var totalField = document.getElementById('fe_total');
    if (!totalField.dataset.manuallyEdited) {
        totalField.value = (basic + hra + conv + special).toFixed(2);
    }
}
document.addEventListener('DOMContentLoaded', function() {
    var totalField = document.getElementById('fe_total');
    if (totalField) totalField.addEventListener('input', function() { this.dataset.manuallyEdited = '1'; });
});

function deleteFutureEntry(id, name) {
    Swal.fire({
        title: 'Delete this entry?',
        text: 'This will permanently remove "' + name + '" from the manpower cost list.',
        icon: 'warning', showCancelButton: true, confirmButtonColor: '#ef4444', confirmButtonText: 'Yes, delete'
    }).then((result) => {
        if (result.isConfirmed) {
            document.getElementById('del_fe_id').value = id;
            document.getElementById('deleteFutureForm').submit();
        }
    });
}

function openConvertModal(id, name) {
    document.getElementById('cv_id').value = id;
    document.getElementById('cv_name').innerText = name;
    $('#convertModal').modal('show');
}

<?php if (isset($_SESSION['success_message'])): ?>
Swal.fire({ icon: 'success', title: 'Success', timer: 3500, showConfirmButton: false });
<?php endif; ?>
</script>
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