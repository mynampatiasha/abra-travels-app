<?php
ob_start();
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
error_reporting(E_ALL);
ini_set('display_errors', 1);
mysqli_report(MYSQLI_REPORT_OFF); // Disable fatal exceptions for mysql queries in PHP 8.1+

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
if (file_exists('mail_helper.php')) { require_once('mail_helper.php'); }

$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
if (!isset($_GET['token'])) {
    isUser();
}

$current_user_name = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : 'HR';

// ============================================================
// TABLE SETUP
// ============================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_offer_company_settings (
    id INT(11) NOT NULL AUTO_INCREMENT,
    company_name VARCHAR(255) DEFAULT NULL,
    company_address TEXT DEFAULT NULL,
    company_phone VARCHAR(50) DEFAULT NULL,
    company_email VARCHAR(255) DEFAULT NULL,
    company_logo VARCHAR(500) DEFAULT NULL,
    signatory_name VARCHAR(255) DEFAULT NULL,
    signatory_designation VARCHAR(255) DEFAULT NULL,
    company_signature VARCHAR(500) DEFAULT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_offer_letters (
    id INT(11) NOT NULL AUTO_INCREMENT,
    offer_number VARCHAR(20) NOT NULL,
    candidate_id INT(11) NOT NULL,
    candidate_name VARCHAR(255) NOT NULL,
    candidate_email VARCHAR(255) DEFAULT NULL,
    candidate_phone VARCHAR(50) DEFAULT NULL,
    position VARCHAR(255) DEFAULT NULL,
    department VARCHAR(255) DEFAULT NULL,
    offered_ctc VARCHAR(100) DEFAULT NULL,
    joining_date DATE DEFAULT NULL,
    probation_period VARCHAR(100) DEFAULT NULL,
    work_location VARCHAR(255) DEFAULT NULL,
    reporting_manager VARCHAR(255) DEFAULT NULL,
    employment_type VARCHAR(100) DEFAULT NULL,
    working_hours VARCHAR(100) DEFAULT NULL,
    notice_period VARCHAR(100) DEFAULT NULL,
    offer_validity DATETIME DEFAULT NULL,
    custom_fields JSON DEFAULT NULL,
    status VARCHAR(30) DEFAULT 'draft',
    token VARCHAR(64) DEFAULT NULL,
    candidate_signature LONGTEXT DEFAULT NULL,
    candidate_action VARCHAR(20) DEFAULT NULL,
    candidate_action_at DATETIME DEFAULT NULL,
    decline_reason TEXT DEFAULT NULL,
    sent_at DATETIME DEFAULT NULL,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY unique_offer_number (offer_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Ensure JSON column compatibility (MySQL 5.7+); fallback to LONGTEXT
$col_cf = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'custom_fields'");
if (!$col_cf || mysqli_num_rows($col_cf) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN custom_fields LONGTEXT DEFAULT NULL");
}

$col_roles = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'roles_responsibilities'");
if (!$col_roles || mysqli_num_rows($col_roles) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN roles_responsibilities LONGTEXT DEFAULT NULL");
}

$col_terms = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'terms_conditions'");
if (!$col_terms || mysqli_num_rows($col_terms) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN terms_conditions LONGTEXT DEFAULT NULL");
}

$col_address = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'candidate_address'");
if (!$col_address || mysqli_num_rows($col_address) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN candidate_address TEXT DEFAULT NULL AFTER candidate_phone");
}

$col_salutation = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'salutation'");
if (!$col_salutation || mysqli_num_rows($col_salutation) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN salutation VARCHAR(10) DEFAULT 'Mr.' AFTER candidate_name");
}

$col_ctc = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'offered_ctc'");
if (!$col_ctc || mysqli_num_rows($col_ctc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN offered_ctc TEXT DEFAULT NULL AFTER department");
} else {
    mysqli_query($con, "ALTER TABLE hr_offer_letters MODIFY COLUMN offered_ctc TEXT DEFAULT NULL");
}

// Ensure hr_offer_company_settings has a proper ID link to hr_companies (fixes cross-company leakage)
$col_cid = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_company_settings LIKE 'company_id'");
if (!$col_cid || mysqli_num_rows($col_cid) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_company_settings ADD COLUMN company_id INT(11) DEFAULT NULL AFTER id");
    // Backfill existing rows by matching name once, so nothing breaks on upgrade
    mysqli_query($con, "UPDATE hr_offer_company_settings c JOIN hr_companies hc ON hc.company_name = c.company_name SET c.company_id = hc.id WHERE c.company_id IS NULL");
}

// ============================================================
// REVISED OFFER LETTER — schema additions (additive only; every
// existing row/query keeps working since these all default to
// values that mean "this is an original offer, not a revision").
// ============================================================
$col_emp = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'employee_id'");
if (!$col_emp || mysqli_num_rows($col_emp) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN employee_id INT(11) DEFAULT NULL AFTER candidate_id");
}
$col_ltype = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'letter_type'");
if (!$col_ltype || mysqli_num_rows($col_ltype) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN letter_type VARCHAR(20) NOT NULL DEFAULT 'original' AFTER status");
}
$col_rnum = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'revision_number'");
if (!$col_rnum || mysqli_num_rows($col_rnum) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN revision_number INT(11) NOT NULL DEFAULT 1 AFTER letter_type");
}
$col_parent = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'parent_offer_id'");
if (!$col_parent || mysqli_num_rows($col_parent) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN parent_offer_id INT(11) DEFAULT NULL AFTER revision_number");
}
$col_effdate = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'revision_effective_date'");
if (!$col_effdate || mysqli_num_rows($col_effdate) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN revision_effective_date DATE DEFAULT NULL AFTER parent_offer_id");
}
$col_prevctc = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'previous_ctc'");
if (!$col_prevctc || mysqli_num_rows($col_prevctc) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN previous_ctc VARCHAR(100) DEFAULT NULL AFTER revision_effective_date");
}
$col_prevpos = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'previous_position'");
if (!$col_prevpos || mysqli_num_rows($col_prevpos) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN previous_position VARCHAR(255) DEFAULT NULL AFTER previous_ctc");
}
$col_revreason = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'revision_reason'");
if (!$col_revreason || mysqli_num_rows($col_revreason) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN revision_reason TEXT DEFAULT NULL AFTER previous_position");
}
// HR approval gate — a revision the employee accepted still needs HR to sign off
// before it's filed into the employee's documents.
$col_hrappr = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'hr_approved_at'");
if (!$col_hrappr || mysqli_num_rows($col_hrappr) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN hr_approved_at DATETIME DEFAULT NULL AFTER revision_reason");
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN hr_approved_by VARCHAR(255) DEFAULT NULL AFTER hr_approved_at");
}

// Salary structure breakup — used by the revised offer letter's editable salary
// table only (original offer letters keep the single free-text offered_ctc field).
foreach (['salary_basic', 'salary_hra', 'salary_special_allowance', 'salary_conveyance', 'salary_other_allowances', 'salary_deductions', 'salary_gross', 'salary_net'] as $rev_sal_col) {
    $col_check = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE '$rev_sal_col'");
    if (!$col_check || mysqli_num_rows($col_check) == 0) {
        mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN $rev_sal_col DECIMAL(12,2) DEFAULT NULL");
    }
}
// HR-added custom salary rows (e.g. "Bonus", "Fuel Allowance") — JSON array of
// {label, amount}, so the table isn't limited to the fixed set of components.
$col_salcustom = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'salary_custom_rows'");
if (!$col_salcustom || mysqli_num_rows($col_salcustom) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN salary_custom_rows TEXT DEFAULT NULL");
}
// Whether the salary table figures are monthly or annual — HR-selectable, defaults
// to 'month' to match the existing behavior.
$col_salperiod = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'salary_period'");
if (!$col_salperiod || mysqli_num_rows($col_salperiod) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN salary_period VARCHAR(20) DEFAULT 'month'");
}
// Candidate/employee-facing details shown on the revision letter itself — a
// separate snapshot from hr_employees so HR can correct a letter without
// touching the underlying employee record.
$col_empcode = mysqli_query($con, "SHOW COLUMNS FROM hr_offer_letters LIKE 'candidate_employee_code'");
if (!$col_empcode || mysqli_num_rows($col_empcode) == 0) {
    mysqli_query($con, "ALTER TABLE hr_offer_letters ADD COLUMN candidate_employee_code VARCHAR(50) DEFAULT NULL");
}

// Note: hr_employee_documents already exists in production (used by
// hr-employees-list.php / get-employee-documents.php) with its own schema —
// see ajax_approve_revision below, which detects its real columns at write
// time instead of assuming a fixed structure here.

// ============================================================
// HELPERS
// ============================================================
function generateOfferNumber($con) {
    $q = mysqli_query($con, "SELECT offer_number FROM hr_offer_letters ORDER BY id DESC LIMIT 1");
    $last = $q ? mysqli_fetch_assoc($q) : null;
    if ($last) {
        preg_match('/AL(\d+)/', $last['offer_number'], $m);
        $next = isset($m[1]) ? intval($m[1]) + 1 : 1;
    } else {
        $next = 1;
    }
    return 'AL' . str_pad($next, 4, '0', STR_PAD_LEFT);
}

function getCompanySettings($con, $candidate_id = 0) {
    if ($candidate_id > 0) {
        // Strict ID-based join: candidate -> hr_screenings.company_id -> hr_offer_company_settings.company_id
        $q = "SELECT cs.*, hc.company_name as live_company_name FROM hr_screenings s
              JOIN hr_offer_company_settings cs ON cs.company_id = s.company_id
              LEFT JOIN hr_companies hc ON hc.id = cs.company_id
              WHERE s.id = " . intval($candidate_id) . " LIMIT 1";
        $res = mysqli_query($con, $q);
        $r = $res ? mysqli_fetch_assoc($res) : null;
        if ($r) {
            if (!empty($r['live_company_name'])) {
                $r['company_name'] = $r['live_company_name'];
            }
            if (empty($r['company_signature']) && !empty($r['signature_path'])) {
                $r['company_signature'] = $r['signature_path'];
            }
            return $r;
        }
    }
    // No silent fallback to another company's data — return empty so the UI can show a clear warning instead
    return [];
}

function getOfferByCandidate($con, $candidate_id) {
    // Only ever return the original offer here — revision rows (letter_type='revision')
    // must stay invisible to the existing screening/onboarding flow so it keeps behaving
    // exactly as it did before revisions existed.
    $q = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE candidate_id=" . intval($candidate_id) . " AND (letter_type='original' OR letter_type IS NULL) ORDER BY id DESC LIMIT 1");
    $offer = $q ? mysqli_fetch_assoc($q) : null;
    if ($offer && isset($offer['terms_conditions'])) {
        $old_terms = "1. Notice Period: 30 days\n2. Termination: Immediate in case of misconduct.\n3. Confidentiality: Must not disclose company secrets.\n(Edit as needed...)";
        if (trim($offer['terms_conditions']) === trim($old_terms)) {
            $offer['terms_conditions'] = "1. Working Hours: As per the company's standard working schedule or as communicated by the management.\n2. Leave Entitlement: You will be entitled to leave as per the company's policy.\n3. Termination\nNotice Period: After confirmation, either party may terminate the employment by giving 60 (sixty) days' written notice or salary in lieu of notice.\nImmediate Termination: The company reserves the right to terminate employment without notice in cases of misconduct, breach of confidentiality, or violation of company policies.\nCompany Liability: If the employee completes the full notice period as instructed by the management, the company will release the pending salary along with the notice period salary (if applicable) as per company policy.\nIf an employee is found absconding by leaving employment without prior notice, approval, or completion of required exit formalities, the employee shall not be eligible for salary payment for the service period under absconding status, subject to company policy and applicable laws.\nConfidentiality: You must maintain the confidentiality of all company information and shall not disclose any data or records to any unauthorized person during or after your employment.\n4. Code of Conduct: You are required to adhere to all company rules, regulations, and policies in force and as amended from time to time.\n5. Verification: This offer is subject to successful verification of your credentials, background, and documents.";
        }
    }
    return $offer;
}

// ============================================================
// REVISED OFFER LETTER — helpers
// ============================================================
function getEmployeeForRevision($con, $employee_id) {
    $employee_id = intval($employee_id);
    if ($employee_id <= 0) return null;
    $q = mysqli_query($con, "SELECT e.*, p.basic_salary, p.hra, p.conveyance, p.special_allowance, p.gross_pay, p.incentives, p.total_ctc as payroll_total_ctc
                              FROM hr_employees e
                              LEFT JOIN hr_payroll p ON p.id = (SELECT p2.id FROM hr_payroll p2 WHERE p2.employee_id = e.id ORDER BY p2.pay_year DESC, p2.pay_month DESC LIMIT 1)
                              WHERE e.id = $employee_id LIMIT 1");
    return $q ? mysqli_fetch_assoc($q) : null;
}

// Every letter (original + all revisions) issued for this employee, oldest first
function getEmployeeOfferHistory($con, $employee_id) {
    $employee_id = intval($employee_id);
    $rows = [];
    if ($employee_id <= 0) return $rows;
    $q = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE employee_id=$employee_id ORDER BY revision_number ASC, id ASC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;
    return $rows;
}

// Most recently issued letter for this employee — used as the "previous" reference
// when drafting a new revision (previous CTC / previous designation).
function getLatestLetterForEmployee($con, $employee_id) {
    $employee_id = intval($employee_id);
    if ($employee_id <= 0) return null;
    $q = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE employee_id=$employee_id ORDER BY revision_number DESC, id DESC LIMIT 1");
    return $q ? mysqli_fetch_assoc($q) : null;
}

// The employee's original hiring offer was created through the candidate/screening
// flow, keyed by candidate_id — it has no employee_id, so getLatestLetterForEmployee()
// can never find it. Before this employee has any revision yet, fall back to matching
// their original offer by name so terms/roles carry forward instead of resetting to
// the generic default text.
function findOriginalOfferForEmployee($con, $employee_name) {
    $name_esc = mysqli_real_escape_string($con, trim((string)$employee_name));
    if ($name_esc === '') return null;
    $q = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE candidate_name = '$name_esc' AND (letter_type='original' OR letter_type IS NULL) ORDER BY id DESC LIMIT 1");
    return $q ? mysqli_fetch_assoc($q) : null;
}

// Company branding for an employee: hr_employees has no company_id FK (free-text
// company_name, same as hr-manpower.php/hr-payroll.php), so resolve by name match.
// Same normalization hr-manpower.php/hr-payroll.php use to reconcile hr_employees'
// free-text company_name against the hr_companies master list (punctuation/suffix-
// tolerant — "Abra E Logistic PVT. LTD." and "Abra E-Logistic Pvt Ltd" both match).
function hr_offer_normalize_company_name($s) {
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[^a-z0-9]+/', ' ', $s);
    $s = preg_replace('/\b(pvt|private|ltd|limited|llp|inc|incorporated|co|company|corp|corporation)\b/', '', $s);
    return trim(preg_replace('/\s+/', ' ', $s));
}
function getCompanySettingsForEmployee($con, $employee_id) {
    $employee_id = intval($employee_id);
    if ($employee_id <= 0) return [];
    $eq = mysqli_query($con, "SELECT company_name FROM hr_employees WHERE id=$employee_id LIMIT 1");
    $erow = $eq ? mysqli_fetch_assoc($eq) : null;
    if (!$erow || empty($erow['company_name'])) return [];
    $emp_norm = hr_offer_normalize_company_name($erow['company_name']);

    $company_id = 0;
    $mc_res = mysqli_query($con, "SELECT id, company_name FROM hr_companies WHERE company_name IS NOT NULL AND company_name != ''");
    if ($mc_res) {
        while ($mc = mysqli_fetch_assoc($mc_res)) {
            if (hr_offer_normalize_company_name($mc['company_name']) === $emp_norm) { $company_id = intval($mc['id']); break; }
        }
    }
    if ($company_id <= 0) return [];

    $q2 = mysqli_query($con, "SELECT cs.*, hc.company_name as live_company_name FROM hr_offer_company_settings cs
                               LEFT JOIN hr_companies hc ON hc.id = cs.company_id
                               WHERE cs.company_id = $company_id LIMIT 1");
    $r = $q2 ? mysqli_fetch_assoc($q2) : null;
    if ($r) {
        if (!empty($r['live_company_name'])) $r['company_name'] = $r['live_company_name'];
        if (empty($r['company_signature']) && !empty($r['signature_path'])) $r['company_signature'] = $r['signature_path'];
        return $r;
    }
    return [];
}


// Salary breakup table for the revised offer letter only. Conveyance and
// Deductions are "if applicable" per the requested format, so those rows are
// omitted entirely when zero/blank instead of showing a redundant ₹0.00 row.
function hr_offer_render_salary_table($offer) {
    $fmt = function($v) { return '&#8377;' . number_format(floatval($v), 2); };
    $row = function($label, $value, $bold = false, $bg = '') {
        $cell = $bold ? "<strong>$value</strong>" : $value;
        $labelCell = $bold ? "<strong>$label</strong>" : $label;
        $style = $bg ? "background:$bg;" : '';
        return "<tr style=\"$style\"><td style=\"padding:8px 20px;border:1px solid #94a3b8;\">$labelCell</td><td style=\"padding:8px 20px;border:1px solid #94a3b8;text-align:center;\">$cell</td></tr>";
    };
    $rows = '';
    foreach ([
        ['Basic Salary', $offer['salary_basic'] ?? 0],
        ['House Rent Allowance (HRA)', $offer['salary_hra'] ?? 0],
        ['Special Allowance', $offer['salary_special_allowance'] ?? 0],
        ['Conveyance Allowance', $offer['salary_conveyance'] ?? 0],
        ['Other Allowances', $offer['salary_other_allowances'] ?? 0],
    ] as $item) {
        if (floatval($item[1]) > 0) $rows .= $row($item[0], $fmt($item[1]));
    }
    $custom_rows = !empty($offer['salary_custom_rows']) ? (json_decode($offer['salary_custom_rows'], true) ?: []) : [];
    foreach ($custom_rows as $cr) {
        $amt = floatval($cr['amount'] ?? 0);
        if ($amt > 0 && trim($cr['label'] ?? '') !== '') {
            $rows .= $row(htmlspecialchars($cr['label']), $fmt($amt));
        }
    }
    $rows .= $row('Gross Salary', $fmt($offer['salary_gross'] ?? 0), true, '#f8fafc');
    if (floatval($offer['salary_deductions'] ?? 0) > 0) {
        $rows .= $row('Deductions', '&minus; ' . $fmt($offer['salary_deductions']));
    }
    $rows .= $row('Net Salary', $fmt($offer['salary_net'] ?? 0), true, '#f0fdf4');
    $period = ($offer['salary_period'] ?? 'month') === 'annum' ? 'annum' : 'month';
    $period_label = $period === 'annum' ? 'Annual' : 'Monthly';
    return '<div style="margin-bottom:25px;"><div class="letter-section-heading">Salary Structure (' . $period_label . '):</div>'
        . '<table style="width:100%;border-collapse:collapse;font-size:13.5px;margin-top:8px;">' . $rows . '</table>'
        . '<div style="font-size:11px;color:#64748b;margin-top:6px;">All figures in INR, per ' . $period . '.</div></div>';
}

// ============================================================
// CANDIDATE PORTAL (via token)
// ============================================================
if (isset($_GET['token']) && !isset($_GET['page'])) {
    $token = mysqli_real_escape_string($con, $_GET['token']);
    $q = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE token='$token' LIMIT 1");
    $offer = $q ? mysqli_fetch_assoc($q) : null;
    if ($offer && isset($offer['terms_conditions'])) {
        $old_terms = "1. Notice Period: 30 days\n2. Termination: Immediate in case of misconduct.\n3. Confidentiality: Must not disclose company secrets.\n(Edit as needed...)";
        if (trim($offer['terms_conditions']) === trim($old_terms)) {
            $offer['terms_conditions'] = "1. Working Hours: As per the company's standard working schedule or as communicated by the management.\n2. Leave Entitlement: You will be entitled to leave as per the company's policy.\n3. Termination\nNotice Period: After confirmation, either party may terminate the employment by giving 60 (sixty) days' written notice or salary in lieu of notice.\nImmediate Termination: The company reserves the right to terminate employment without notice in cases of misconduct, breach of confidentiality, or violation of company policies.\nCompany Liability: If the employee completes the full notice period as instructed by the management, the company will release the pending salary along with the notice period salary (if applicable) as per company policy.\nIf an employee is found absconding by leaving employment without prior notice, approval, or completion of required exit formalities, the employee shall not be eligible for salary payment for the service period under absconding status, subject to company policy and applicable laws.\nConfidentiality: You must maintain the confidentiality of all company information and shall not disclose any data or records to any unauthorized person during or after your employment.\n4. Code of Conduct: You are required to adhere to all company rules, regulations, and policies in force and as amended from time to time.\n5. Verification: This offer is subject to successful verification of your credentials, background, and documents.";
        }
    }
    if (!$offer) die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Invalid or expired link.</h3></div>");

    // Check expiry — only block if the candidate hasn't already acted (accepted/declined).
    // Once signed, the link must stay usable forever so HR/onboarding can view/download the signed PDF.
    if (empty($offer['candidate_action']) && $offer['offer_validity'] && strtotime($offer['offer_validity']) < time()) {
        die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>This offer link has expired.</h3><p>Please contact HR for further assistance.</p></div>");
    }

    // Already acted
    $already_acted_banner = '';
    if (($offer['candidate_action'] == 'accepted' || $offer['candidate_action'] == 'declined') && !isset($_GET['download'])) {
        $action_label = $offer['candidate_action'] == 'accepted' ? 'accepted ✅' : 'declined ❌';
        $bg_color = $offer['candidate_action'] == 'accepted' ? '#f0fdf4' : '#fef2f2';
        $border_color = $offer['candidate_action'] == 'accepted' ? '#86efac' : '#fca5a5';
        $text_color = $offer['candidate_action'] == 'accepted' ? '#166534' : '#991b1b';
        
        $already_acted_banner = "<div class='no-print' style='max-width:210mm;margin:0 auto 20px auto;padding:20px;text-align:center;background:$bg_color;border:2px solid $border_color;border-radius:12px;font-family:sans-serif;'><h3 style='color:$text_color;margin-top:0;'>You have already {$action_label} this offer.</h3>";
        if ($offer['candidate_action'] == 'accepted') {
            $already_acted_banner .= "<div style='margin-top:15px;'><a href='?token={$token}&download=1' target='_blank' style='display:inline-block;padding:12px 24px;background:#1a3fc4;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold;box-shadow:0 4px 12px rgba(26,63,196,0.3);'>Download Signed Offer Letter</a></div>";
        }
        $already_acted_banner .= "</div>";
    }

    $cs = getCompanySettings($con, $offer['candidate_id'] ?? 0);
    // Revision letters are keyed by employee_id, not candidate_id — the lookup above
    // only checks hr_screenings, so fall back to the employee-based company match.
    if (empty($cs) && !empty($offer['employee_id'])) {
        $cs = getCompanySettingsForEmployee($con, $offer['employee_id']);
    }
    if (empty($cs)) {
        die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h3>Company branding not configured.</h3><p>Please ask HR to set up Company Settings for this candidate's company before sending this offer.</p></div>");
    }
    $custom = $offer['custom_fields'] ? json_decode($offer['custom_fields'], true) : [];

    // --- HANDLE PDF DOWNLOAD ---
    if (isset($_GET['download'])) {
        $offerJson = json_encode($offer);
        $csJson = json_encode($cs);
        ?>
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <title>Offer Letter — <?php echo htmlspecialchars($offer['candidate_name']); ?></title>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
        <style>
        body { font-family: Arial, sans-serif; background: #f0f4f8; padding: 20px; color: #000; }
        .pdf-preview { width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.2); border-radius: 0; box-sizing: border-box; display: flex; flex-direction: column; }
        .pdf-content-wrapper { padding: 0 20mm; flex: 1; }
        table { width: 100%; border-collapse: collapse; }
        .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
        .letter-wave-top svg{width:100%;height:70px;display:block;}
        .letter-wave-bottom{width:100%;line-height:0;display:block;margin-top:40px;}
        .letter-wave-bottom svg{width:100%;height:80px;display:block;}
        .letter-header{display:flex;justify-content:space-between;align-items:center;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;}
        .letter-header-left{font-size:19px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:0;margin-left:30px;}
        .letter-header-left span{display:flex;align-items:center;gap:10px;}
        .letter-header-left i{width:26px;text-align:center;font-size:26px;}
        .letter-header-right{text-align:right;}
        .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
        .letter-company-name-right{font-size:15px;font-weight:900;color:#0f2557;margin-top:4px;text-transform:uppercase;}
        .letter-company-tagline{font-size:11px;color:#0f2557;font-weight:800;text-transform:uppercase;letter-spacing:0.5px;}
        .print-only-spacer, .print-only-spacer-foot { display: none; }
        
        @media print{
            @page { margin: 0; }
            .print-only-spacer { display: table-header-group !important; }
            .print-only-spacer-foot { display: table-footer-group !important; }
            body { padding: 0 !important; margin: 0 !important; background: #fff !important; }
            .no-print { display: none !important; }
            * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
            .pdf-preview { padding: 0 !important; margin: 0 !important; width: 100% !important; min-height: 0 !important; border: none !important; box-shadow: none !important; max-width: none !important; border-radius: 0 !important; }

            /* Repeat header + top wave on every printed page */
            .letter-wave-top {
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                right: 0 !important;
                z-index: 10 !important;
            }
            .letter-header {
                position: fixed !important;
                top: 70px !important;
                left: 0 !important;
                right: 0 !important;
                z-index: 10 !important;
            }

            /* Repeat bottom wave on every printed page */
            .letter-wave-bottom {
                position: fixed !important;
                bottom: 0 !important;
                left: 0 !important;
                right: 0 !important;
                margin-top: 0 !important;
                z-index: 10 !important;
            }

            .pdf-content-wrapper {
                margin-top: 0px !important;
            }
        }
        </style>
        </head>
        <body>
        <div class="no-print" style="text-align:center; margin-bottom:20px;">
           <button onclick="window.print()" style="padding:14px 28px; background:#0f2557; color:#fff; border:none; border-radius:10px; font-weight:bold; cursor:pointer; box-shadow:0 4px 12px rgba(15,37,87,0.2);">🖨️ Print / Save as PDF</button>
        </div>
        <div id="pdfPreviewBox" class="pdf-preview" style="max-width:800px; margin:0 auto; background:#fff; padding:40px; box-shadow:0 4px 20px rgba(0,0,0,0.1);"></div>

        <script>
        const o = <?php echo $offerJson; ?>;
        const cs = <?php echo $csJson; ?>;
        const box = document.getElementById('pdfPreviewBox');
        const isSigned = o.status === 'accepted';
        const isRevision = o.letter_type === 'revision';
        
        let custom = [];
        try { custom = JSON.parse(o.custom_fields || '[]'); } catch(e){}

        var fields = [
            ['Position', o.position], ['Department', o.department],
            ['Offered CTC', o.offered_ctc],
            ['Joining Date', o.joining_date ? new Date(o.joining_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : ''],
            ['Probation Period', o.probation_period], ['Work Location', o.work_location],
            ['Reporting Manager', o.reporting_manager],
            ['Working Hours', o.working_hours], ['Notice Period', o.notice_period]
        ];

        var fieldsHTML = '<div class="pdf-grid">';
        fields.forEach(function(f){ if(!f[1]) return; fieldsHTML += '<div class="pdf-field"><div class="pdf-field-label">'+f[0]+'</div><div class="pdf-field-value">'+f[1]+'</div></div>'; });
        custom.forEach(function(cf){ if(!cf.heading && !cf.text) return; fieldsHTML += '<div class="pdf-field"><div class="pdf-field-label">'+cf.heading+'</div><div class="pdf-field-value">'+cf.text+'</div></div>'; });
        fieldsHTML += '</div>';

        var logoHTML = cs.company_logo ? '<img src="'+cs.company_logo+'" style="max-height:100px;max-width:180px;object-fit:contain;">' : '';
        var sigHTML = cs.company_signature ? '<img src="'+cs.company_signature+'" style="max-height:200px;max-width:230px;margin-bottom:4px;margin-top:8px;">' : '<div style="height:65px;"></div>';
        var candidateSigHTML = (isSigned && o.candidate_signature) ? '<img src="'+o.candidate_signature+'" style="max-height:220px;max-width:420px;margin-bottom:4px;margin-top:8px;">' : '<div style="height:65px;"></div>';
        
        var letterDate = o.joining_date ? new Date(o.joining_date).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'}) : new Date().toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'});
        var validityTxt = o.offer_validity ? 'Valid until ' + new Date(o.offer_validity).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'}) : '';

        box.innerHTML = `
        <div class="letter-wave-top">
            <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
                <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
            </svg>
        </div>
        <div class="letter-header">
            <div class="letter-header-left">
                ${cs.company_phone ? '<span><i class="fas fa-phone-alt"></i> '+cs.company_phone+'</span>' : ''}
                ${cs.company_email ? '<span><i class="fas fa-envelope"></i> '+cs.company_email+'</span>' : ''}
                ${cs.company_website ? '<span><i class="fas fa-globe"></i> '+cs.company_website+'</span>' : ''}
            </div>
            <div class="letter-header-right">
                ${cs.company_logo ? '<img src="'+cs.company_logo+'" alt="Logo">' : ''}
            </div>
        </div>
        <div class="pdf-content-wrapper">
        <table style="width:100%; border-collapse:collapse; border:none; font-family: Arial, sans-serif; color: #000; font-size: 14px; line-height: 1.6;">
        <thead class="print-only-spacer"><tr><td style="height: 250px; border:none;"></td></tr></thead>
        <tbody><tr><td style="padding: 0; border:none;">

        <!-- HEADER BLOCK -->
        <div style="margin-bottom: 30px;">
            <div style="font-weight:bold; margin-bottom: 6px;">From</div>
            <div style="font-weight:bold; font-size: 16px;">${cs.company_name || 'ABRA E-LOGISTIC PVT. LTD.'}</div>
            <div><strong>Registered Office: ${(cs.company_address || 'Bangalore').trim().replace(/\n/g, '<br>')}</strong></div>
            <div><strong>Email: ${cs.company_email || 'info@abra-logistic.com'} | Phone: ${cs.company_phone || '8123631041'}</strong></div>
            <div><strong>Date: ${letterDate}</strong></div>
        </div>

        <!-- TO BLOCK -->
        <div style="margin-bottom: 25px;">
            <strong>To,</strong><br>
            <strong>${o.salutation || 'Mr.'} ${o.candidate_name}</strong><br>
            ${o.candidate_employee_code ? '<strong>Employee ID: ' + o.candidate_employee_code + '</strong><br>' : ''}
            ${o.candidate_address ? '<strong>' + o.candidate_address.trim().replace(/\n/g, '<br>') + '</strong><br>' : ''}
            <strong>Phone: ${o.candidate_phone || ''}</strong>${o.candidate_email ? ' &nbsp;|&nbsp; Email: ' + o.candidate_email : ''}
        </div>

        <!-- SUBJECT -->
        <div style="margin-bottom: 25px; text-align: center; text-decoration: underline; font-size: 15px;">
            <strong>Subject: ${isRevision ? 'Revised Offer of Employment / Revision of Terms — ' + o.position : 'Offer of Employment for the Position of ' + o.position}</strong>
        </div>

        <!-- SALUTATION & OPENING -->
        <div style="margin-bottom: 20px;">
            Dear <strong>${o.salutation || 'Mr.'} ${o.candidate_name}</strong>,<br><br>
            ${isRevision
                ? 'Further to your employment with <strong>' + (cs.company_name || 'Abra E-Logistic Pvt. Ltd.') + '</strong>, we are pleased to inform you that your terms of employment have been revised as set out below, effective from the date mentioned. This letter supersedes the salary/designation terms of your previous offer letter to the extent revised herein; all other terms and conditions remain unchanged.'
                : 'We are pleased to offer you the position of <strong>' + o.position + '</strong> at <strong>' + (cs.company_name || 'Abra E-Logistic Pvt. Ltd.') + '</strong>. In this role, you will be responsible for performing various <strong>' + (o.department || 'Procurement') + '</strong> activities and managerial tasks, ensuring the smooth logistic operations of the company.'}
        </div>

        ${isRevision ? `
        <div style="margin-bottom: 20px; border:1px solid #dbeafe; background:#f8faff; border-radius:8px; padding:14px 18px;">
            <strong>Summary of Revision:</strong>
            <table style="width:100%; margin-top:8px; border-collapse:collapse; font-size:13px;">
                <tr><td style="padding:4px 8px; color:#64748b;">Designation</td><td style="padding:4px 8px;">${o.previous_position || '-'} &rarr; <strong>${o.position}</strong></td></tr>
                <tr><td style="padding:4px 8px; color:#64748b;">CTC / Salary</td><td style="padding:4px 8px;">${o.previous_ctc || '-'} &rarr; <strong>${o.offered_ctc}</strong></td></tr>
                <tr><td style="padding:4px 8px; color:#64748b;">Effective From</td><td style="padding:4px 8px;"><strong>${o.revision_effective_date ? new Date(o.revision_effective_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : '-'}</strong></td></tr>
                ${o.revision_reason ? '<tr><td style="padding:4px 8px; color:#64748b;">Reason</td><td style="padding:4px 8px;">' + o.revision_reason + '</td></tr>' : ''}
            </table>
        </div>` : ''}

        <div style="margin-bottom: 20px;">
            Please find below the ${isRevision ? 'revised' : ''} terms and conditions of your employment:
        </div>

        <!-- DETAILS LIST -->
        <table style="width:100%; border:none; margin-bottom:25px; font-size:14px; line-height:1.8; font-family: Arial, sans-serif;">
            <tr><td style="width:25px; vertical-align:top;">1.</td><td style="width: 140px; font-weight:bold; vertical-align:top;">Position:</td><td>${o.position}</td></tr>
            <tr><td style="vertical-align:top;">2.</td><td style="font-weight:bold; vertical-align:top;">Reporting To:</td><td>${o.reporting_manager || 'Manager / Management Representative'}</td></tr>
            <tr><td style="vertical-align:top;">3.</td><td style="font-weight:bold; vertical-align:top;">Place of Posting:</td><td>${o.work_location || 'Bangalore'}</td></tr>
            <tr><td style="vertical-align:top;">4.</td><td style="font-weight:bold; vertical-align:top;">Probation Period:</td><td>${o.probation_period || '3 months from the date of joining.'}</td></tr>
            <tr><td style="vertical-align:top;">5.</td><td style="font-weight:bold; vertical-align:top;">Salary:</td><td>${isRevision ? 'As per the Salary Structure below.' : 'During the probation period, your consolidated salary will be INR ' + o.offered_ctc + ' per month.'}</td></tr>
        </table>

        ${isRevision ? salaryTableHTML(o) : ''}

        <!-- ROLES & RESPONSIBILITIES -->
        ${o.roles_responsibilities ? `
        <div style="margin-bottom: 25px; page-break-inside: avoid;">
            <strong>Roles and Responsibilities:</strong>
            <ul style="margin-top: 8px; padding-left: 20px; font-size: 18px;">${o.roles_responsibilities.split('\n').map(t=>t.trim()?'<li style="margin-bottom:8px; font-size: 14px;">'+t+'</li>':'').join('')}</ul>
        </div>` : ''}

        <!-- TERMS & CONDITIONS -->
        ${o.terms_conditions ? `
        <div style="margin-bottom: 25px;">
            <strong>Terms and Conditions:</strong>
            <ul style="margin-top: 8px; padding-left: 20px; font-size: 18px;">${o.terms_conditions.split('\n').map(t=>{var tt=t.trim(); if(!tt) return ''; var nb=/^\d+\./.test(tt); if(nb) tt = tt.replace(/^(\d+\.\s*[^:]+:?)/, '<strong>$1</strong>'); return '<li style="margin-bottom:8px; font-size: 14px;'+(nb?'list-style:none;margin-left:-20px;':'')+'">'+tt+'</li>';}).join('')}</ul>
        </div>` : ''}
        
        <div style="margin-bottom: 30px;">
            <strong>Verification:</strong> This offer is subject to successful verification of your credentials, background, and documents.
        </div>

        <!-- CLOSING -->
        <div style="margin-bottom: 40px;">
            We are delighted to welcome you to <strong>${cs.company_name || 'Abra E-Logistic Pvt. Ltd.'}</strong> and look forward to your valuable contribution to the company’s growth and success.<br>
            Please sign and return the duplicate copy of this letter as a token of your acceptance of the above terms and conditions.
        </div>

        <!-- SIGNATURE BLOCK -->
        <div style="width: 100%;">
            <div style="width: 100%; margin-bottom: 30px;">
                <strong>For ${cs.company_name || 'Abra E-Logistic Pvt. Ltd.'}</strong><br>
                ${sigHTML}<br>
                <strong>Authorized Signatory</strong><br>
                <strong>Name:</strong> ${cs.signatory_name || 'Abishek Veeraswamy'}<br>
                <strong>Designation:</strong> ${cs.signatory_designation || 'Managing Director'}
            </div>

            <div style="width: 100%;">
                <strong>Accepted and Agreed:</strong><br>
                I, <strong>${o.candidate_name}</strong>, accept the offer of employment and agree to abide by the terms and conditions mentioned above.<br>
                <div style="page-break-inside: avoid;">
                    <div style="margin-top:10px; display:flex; align-items:flex-end; gap:6px;"><span>Signature:</span>${candidateSigHTML}</div>
                    <div style="margin-top:10px;">Date: ${isSigned ? letterDate : '_______________________'}</div>
                </div>
            </div>
        </div>
        
        </td></tr></tbody>
        <tfoot class="print-only-spacer-foot"><tr><td style="height: 100px; border:none;"></td></tr></tfoot>
        </table>
        </div>
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>`;

        // Salary breakup table (revised offer letter only) — any component row,
        // fixed or custom, is omitted when its amount is 0/blank; Gross and Net
        // (the totals) always show.
        function salaryTableHTML(o) {
            function money(v) { var n = parseFloat(v); if (isNaN(n)) n = 0; return '₹' + n.toFixed(2).replace(/\d(?=(\d{3})+\.)/g, '$&,'); }
            function esc(s) { var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
            function cell(label, amt) { return '<tr><td style="padding:8px 20px;border:1px solid #94a3b8;">' + label + '</td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;">' + money(amt) + '</td></tr>'; }
            var rows = '';
            [['Basic Salary', o.salary_basic], ['House Rent Allowance (HRA)', o.salary_hra], ['Special Allowance', o.salary_special_allowance], ['Conveyance Allowance', o.salary_conveyance], ['Other Allowances', o.salary_other_allowances]].forEach(function(item) {
                if (parseFloat(item[1]) > 0) rows += cell(item[0], item[1]);
            });
            var customRows = [];
            try { customRows = JSON.parse(o.salary_custom_rows || '[]'); } catch (e) {}
            customRows.forEach(function(cr) {
                if (parseFloat(cr.amount) > 0 && cr.label && cr.label.trim()) rows += cell(esc(cr.label), cr.amount);
            });
            rows += '<tr style="background:#f8fafc;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Gross Salary</strong></td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;"><strong>' + money(o.salary_gross) + '</strong></td></tr>';
            if (parseFloat(o.salary_deductions) > 0) {
                rows += '<tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Deductions</td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;">&minus; ' + money(o.salary_deductions) + '</td></tr>';
            }
            rows += '<tr style="background:#f0fdf4;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Net Salary</strong></td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;"><strong>' + money(o.salary_net) + '</strong></td></tr>';
            var period = o.salary_period === 'annum' ? 'annum' : 'month';
            var periodLabel = period === 'annum' ? 'Annual' : 'Monthly';
            return '<div style="margin-bottom:25px;"><strong>Salary Structure (' + periodLabel + '):</strong>'
                + '<table style="width:100%;border-collapse:collapse;font-size:13.5px;margin-top:8px;">' + rows + '</table>'
                + '<div style="font-size:11px;color:#64748b;margin-top:6px;">All figures in INR, per ' + period + '.</div></div>';
        }

        function waitForPaint(callback) {
            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    callback();
                });
            });
        }

        var imgs = box.querySelectorAll('img');
        var loaded = 0;
        var totalImgs = imgs.length;
        function allImagesDone() {
            waitForPaint(function() {
                setTimeout(() => { window.print(); }, 500);
            });
        }
        function tryPrint() {
            loaded++;
            if (loaded >= totalImgs) allImagesDone();
        }
        if (totalImgs === 0) {
            allImagesDone();
        } else {
            imgs.forEach(function(img) {
                if (img.complete) {
                    tryPrint();
                } else {
                    img.addEventListener('load', tryPrint);
                    img.addEventListener('error', tryPrint);
                }
            });
        }
        </script>
        </body>
        </html>
        <?php
        exit;
    }

    // Handle accept/decline POST
    if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['candidate_action'])) {
        $action = $_POST['candidate_action'] == 'accept' ? 'accepted' : 'declined';
        $sig = mysqli_real_escape_string($con, $_POST['signature'] ?? '');
        $reason = mysqli_real_escape_string($con, $_POST['decline_reason'] ?? '');
        $now = date('Y-m-d H:i:s');
        $new_status = $action == 'accepted' ? 'accepted' : 'declined';
        mysqli_query($con, "UPDATE hr_offer_letters SET candidate_action='$action', candidate_signature='$sig', candidate_action_at='$now', decline_reason='$reason', status='$new_status' WHERE token='$token'");
        // Note: an accepted revision is NOT auto-filed into the employee's documents here —
        // it waits for HR to review and click Approve on the revise page (ajax_approve_revision).

        // Notify HR via email
        $hr_email = $cs['company_email'] ?? '';
        if ($hr_email) {
            $subj = "Offer {$offer['offer_number']} — Candidate " . ucfirst($action);
            $body = "Candidate {$offer['candidate_name']} has {$action} the offer letter {$offer['offer_number']}.";
            if ($action == 'declined' && $reason) $body .= "\n\nReason: $reason";
            sendCompanyMail($con, $cs['company_id'] ?? 0, $hr_email, $subj, $body);
        }

        echo "<div style='padding:60px;text-align:center;font-family:sans-serif;'>";
        if ($action == 'accepted') {
            echo "<div style='font-size:50px;'>✅</div><h2 style='color:#065f46;margin-top:16px;'>Offer Accepted!</h2><p>Thank you, {$offer['candidate_name']}. Your acceptance has been recorded.</p>";
            echo "<div style='margin-top:30px;'><a href='?token={$token}&download=1' target='_blank' style='display:inline-block;padding:14px 28px;background:#1a3fc4;color:#fff;text-decoration:none;border-radius:10px;font-weight:bold;box-shadow:0 4px 12px rgba(26,63,196,0.3);'>Download Signed Offer Letter</a></div>";
        } else {
            echo "<div style='font-size:50px;'>❌</div><h2 style='color:#991b1b;margin-top:16px;'>Offer Declined</h2><p>Thank you for letting us know. HR will be in touch.</p>";
        }
        echo "</div>";
        if (ob_get_level() > 0) { ob_end_flush(); } exit;
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8"/>
    <title>Offer Letter — <?php echo htmlspecialchars($offer['candidate_name']); ?></title>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap" rel="stylesheet"/>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
    <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Calibri',Georgia,serif;background:#f0f4f8;padding:20px;}
    .offer-card{max-width:800px;min-height:1000px;margin:0 auto;background:#fff;box-shadow:0 4px 30px rgba(0,0,0,0.1);position:relative;overflow:hidden;padding-bottom:100px;}
    .letter-wave-top{width:100%;line-height:0;display:block;margin:0;padding:0;}
    .letter-wave-top svg{width:100%;height:70px;display:block;}
    .letter-wave-bottom{width:100%;line-height:0;display:block;position:absolute;bottom:0;left:0;right:0;z-index:1;}
    .letter-wave-bottom svg{width:100%;height:80px;display:block;}
    .letter-header{display:flex;justify-content:space-between;align-items:flex-start;padding:10px 40px 15px 40px;border-bottom:3px solid #3b5998;background:#fff;position:relative;z-index:2;}
    .letter-header-left{font-size:15px;color:#0f2557;line-height:1.6;font-weight:800;margin-top:5px;margin-left:30px;}
    .letter-header-left span{display:flex;align-items:center;gap:10px;}
    .letter-header-left i{width:26px;text-align:center;font-size:26px;}
    .letter-header-right{text-align:right;}
    .letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
    .letter-company-name-right{font-size:14px;font-weight:900;color:#0f2557;margin-top:4px;text-transform:uppercase;}
    .letter-company-tagline{font-size:11px;color:#0f2557;font-weight:800;text-transform:uppercase;letter-spacing:0.5px;}
    .letter-body{padding:32px 40px 40px 40px;font-family:Arial,sans-serif;font-size:14px;color:#1a202c;line-height:1.6;position:relative;z-index:2;}
    .letter-body p{margin-bottom:10px;}
    .letter-body ul{margin:6px 0 10px 22px;}
    .letter-body ul li{margin-bottom:3px;}
    .letter-from{margin-bottom:16px;}
    .letter-from strong{display:block;font-size:14px;}
    .letter-to{margin-bottom:16px;}
    .letter-subject{text-align:center;font-weight:700;text-decoration:underline;margin:18px 0 14px 0;font-size:13.5px;}
    .letter-section-heading{font-weight:700;margin:14px 0 6px 0;}
    .letter-sig-area{display:flex;justify-content:space-between;margin-top:30px;font-size:13px;}
    .letter-sig-box{text-align:center;width:200px;}
    .letter-sig-line{border-top:1px solid #334155;margin-top:50px;padding-top:6px;font-size:12px;font-weight:700;}
    .sig-pad{border:2px dashed #cbd5e1;border-radius:10px;background:#f8faff;cursor:crosshair;width:100%;height:160px;}
    .btn-accept{padding:14px 32px;border:none;border-radius:10px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-size:15px;font-weight:800;cursor:pointer;width:100%;}
    .btn-decline{padding:14px 32px;border:2px solid #ef4444;border-radius:10px;background:#fff;color:#ef4444;font-size:15px;font-weight:800;cursor:pointer;width:100%;margin-top:10px;}
    .validity-banner{background:#fff7ed;border:1px solid #fcd34d;padding:10px 16px;margin-bottom:16px;font-size:13px;font-weight:700;color:#92400e;}
    .sig-actions{padding:0 40px 28px 40px;}
    .print-only-spacer{display:none;}
    @media print{
        @page { margin: 0; }
        .print-only-spacer{display:table-header-group !important;}
        .print-only-spacer-foot{display:table-footer-group !important;}
        body{background:#fff;padding:0;}
        .offer-card{box-shadow:none;overflow:visible;padding-bottom:0;}
        .sig-actions{display:none;}
        .no-print{display:none!important;}

        /* Repeat header + top wave on every printed page */
        .letter-wave-top {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            right: 0 !important;
            z-index: 10 !important;
        }
        .letter-header {
            position: fixed !important;
            top: 70px !important;
            left: 0 !important;
            right: 0 !important;
            z-index: 10 !important;
        }

        /* Repeat bottom wave on every printed page */
        .letter-wave-bottom {
            position: fixed !important;
            bottom: 0 !important;
            left: 0 !important;
            right: 0 !important;
        }

        .letter-body {
            margin-top: 30px !important;
        }
    }
    @media(max-width:600px){.letter-header{flex-direction:column;gap:10px;padding:16px;} .letter-body,.sig-actions{padding:20px;} .letter-sig-area{flex-direction:column;gap:20px;}}
    </style>
    </head>
    <body>
    <?php if (!empty($already_acted_banner)) echo $already_acted_banner; ?>
    <div style="max-width: 800px; margin: 0 auto 20px auto; display: flex; justify-content: flex-end;" class="no-print">
        <button type="button" onclick="window.print()" style="padding: 10px 20px; background: #0f2557; color: white; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; display: flex; align-items: center; gap: 8px;">🖨️ Print / Download PDF</button>
    </div>

    <div class="offer-card">
        <!-- Letterhead Header -->
        <div class="letter-wave-top">
            <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
                <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
            </svg>
        </div>
        <div class="letter-header">
            <div class="letter-header-left">
                <?php if($cs['company_phone'] ?? ''): ?><span><i class="fas fa-phone-alt"></i> <?php echo htmlspecialchars($cs['company_phone']); ?></span><?php endif; ?>
                <?php if($cs['company_email'] ?? ''): ?><span><i class="fas fa-envelope"></i> <?php echo htmlspecialchars($cs['company_email']); ?></span><?php endif; ?>
                <?php if($cs['company_website'] ?? ''): ?><span><i class="fas fa-globe"></i> <?php echo htmlspecialchars($cs['company_website']); ?></span><?php endif; ?>
            </div>
            <div class="letter-header-right">
                <?php if (!empty($cs['company_logo'])): ?>
                <img src="<?php echo htmlspecialchars($cs['company_logo']); ?>" alt="Logo">
                <?php endif; ?>
            </div>
        </div>

        <table style="width:100%; border-collapse:collapse; border:none;">
        <thead class="print-only-spacer"><tr><td style="height: 245px; border:none;"></td></tr></thead>
        <tbody><tr><td style="padding: 0; border:none;">
        <!-- Letter Body -->
        <div class="letter-body">
            <?php if ($offer['offer_validity']): ?>
            <div class="validity-banner">⏳ This offer is valid until: <strong><?php echo date('d M Y, h:i A', strtotime($offer['offer_validity'])); ?></strong></div>
            <?php endif; ?>

            <!-- From -->
            <div style="margin-bottom: 30px; line-height: 1.6;">
                <div style="font-weight:bold; margin-bottom: 6px;">From</div>
                <div style="font-weight:bold; font-size: 16px;"><?php echo htmlspecialchars($cs['company_name'] ?? ''); ?></div>
                <?php if($cs['company_address'] ?? ''): ?>
                <div><strong>Registered Office: <?php echo nl2br(htmlspecialchars(trim($cs['company_address']))); ?></strong></div>
                <?php endif; ?>
                <div><strong>Email: <?php echo htmlspecialchars($cs['company_email'] ?? ''); ?> | Phone: <?php echo htmlspecialchars($cs['company_phone'] ?? ''); ?></strong></div>
                <div><strong>Date: <?php echo !empty($offer['joining_date']) ? date('d/m/Y', strtotime($offer['joining_date'])) : date('d/m/Y'); ?></strong></div>
            </div>

            <!-- To -->
            <div style="margin-bottom: 25px; line-height: 1.6;">
                <strong>To,</strong><br>
                <strong><?php echo htmlspecialchars($offer['salutation'] ?? 'Mr.'); ?> <?php echo htmlspecialchars($offer['candidate_name']); ?></strong><br>
                <?php if($offer['candidate_employee_code'] ?? ''): ?>
                <strong>Employee ID: <?php echo htmlspecialchars($offer['candidate_employee_code']); ?></strong><br>
                <?php endif; ?>
                <?php if($offer['candidate_address'] ?? ''): ?>
                <strong><?php echo nl2br(htmlspecialchars(trim($offer['candidate_address']))); ?></strong><br>
                <?php endif; ?>
                <strong>Phone: <?php echo htmlspecialchars($offer['candidate_phone'] ?? ''); ?></strong><?php if($offer['candidate_email'] ?? ''): ?> &nbsp;|&nbsp; <strong>Email: <?php echo htmlspecialchars($offer['candidate_email']); ?></strong><?php endif; ?>
            </div>

            <?php $is_revision = (($offer['letter_type'] ?? 'original') === 'revision'); ?>
            <!-- Subject -->
            <div class="letter-subject">Subject: <?php echo $is_revision ? 'Revised Offer of Employment / Revision of Terms — ' . htmlspecialchars($offer['position']) : 'Offer of Employment for the Position of ' . htmlspecialchars($offer['position']); ?></div>

            <p>Dear <strong><?php echo htmlspecialchars($offer['salutation'] ?? 'Mr.'); ?> <?php echo htmlspecialchars($offer['candidate_name']); ?></strong></p>

            <?php if ($is_revision): ?>
            <p>Further to your employment with <strong><?php echo htmlspecialchars($cs['company_name'] ?? 'Abra E-Logistic Pvt. Ltd.'); ?></strong>, we are pleased to inform you that your terms of employment have been revised as set out below, effective from the date mentioned. This letter supersedes the salary/designation terms of your previous offer letter to the extent revised herein; all other terms and conditions remain unchanged.</p>
            <div style="margin-bottom:20px;border:1px solid #dbeafe;background:#f8faff;border-radius:8px;padding:14px 18px;">
                <strong>Summary of Revision:</strong>
                <table style="width:100%;margin-top:8px;border-collapse:collapse;font-size:13px;">
                    <tr><td style="padding:4px 8px;color:#64748b;">Designation</td><td style="padding:4px 8px;"><?php echo htmlspecialchars($offer['previous_position'] ?: '-'); ?> &rarr; <strong><?php echo htmlspecialchars($offer['position']); ?></strong></td></tr>
                    <tr><td style="padding:4px 8px;color:#64748b;">CTC / Salary</td><td style="padding:4px 8px;"><?php echo htmlspecialchars($offer['previous_ctc'] ?: '-'); ?> &rarr; <strong><?php echo htmlspecialchars($offer['offered_ctc']); ?></strong></td></tr>
                    <tr><td style="padding:4px 8px;color:#64748b;">Effective From</td><td style="padding:4px 8px;"><strong><?php echo !empty($offer['revision_effective_date']) ? date('d M Y', strtotime($offer['revision_effective_date'])) : '-'; ?></strong></td></tr>
                    <?php if (!empty($offer['revision_reason'])): ?><tr><td style="padding:4px 8px;color:#64748b;">Reason</td><td style="padding:4px 8px;"><?php echo htmlspecialchars($offer['revision_reason']); ?></td></tr><?php endif; ?>
                </table>
            </div>
            <?php else: ?>
            <p>We are pleased to offer you the position of <strong><?php echo htmlspecialchars($offer['position']); ?></strong> at <strong><?php echo htmlspecialchars($cs['company_name'] ?? 'Abra E-Logistic Pvt. Ltd.'); ?></strong>. In this role, you will be responsible for performing various <strong><?php echo htmlspecialchars($offer['department'] ?? 'Procurement'); ?></strong> activities and managerial tasks, ensuring the smooth logistic operations of the company.</p>
            <?php endif; ?>

            <p>Please find below the <?php echo $is_revision ? 'revised ' : ''; ?>terms and conditions of your employment:</p>

            <ol style="padding-left: 20px;">
                <?php if($offer['position']): ?><li><strong>Position:</strong> <?php echo htmlspecialchars($offer['position']); ?></li><?php endif; ?>
                <?php if($offer['reporting_manager']): ?><li><strong>Reporting To:</strong> <?php echo htmlspecialchars($offer['reporting_manager']); ?></li><?php endif; ?>
                <?php if($offer['work_location']): ?><li><strong>Place of Posting:</strong> <?php echo htmlspecialchars($offer['work_location']); ?></li><?php endif; ?>
                <?php if($offer['joining_date']): ?><li><strong>Date of Joining:</strong> <?php echo date('d/m/Y', strtotime($offer['joining_date'])); ?></li><?php endif; ?>
                <?php if($offer['probation_period']): ?><li><strong>Probation Period:</strong> <?php echo htmlspecialchars($offer['probation_period']); ?></li><?php endif; ?>
                <?php if($offer['offered_ctc'] && !$is_revision): ?><li><strong>Salary:</strong> <?php echo htmlspecialchars($offer['offered_ctc']); ?></li><?php endif; ?>
                <?php if($offer['working_hours']): ?><li><strong>Working Hours:</strong> <?php echo htmlspecialchars($offer['working_hours']); ?></li><?php endif; ?>
                <?php if($offer['notice_period']): ?><li><strong>Notice Period:</strong> <?php echo htmlspecialchars($offer['notice_period']); ?></li><?php endif; ?>
            </ol>

            <?php if ($is_revision): echo hr_offer_render_salary_table($offer); endif; ?>

            <?php if (!empty($offer['roles_responsibilities'])): ?>
            <div class="letter-section-heading">Roles and Responsibilities:</div>
            <ul style="padding-left:20px;"><?php foreach (explode("\n", $offer['roles_responsibilities']) as $rline): $rline = trim($rline); if ($rline === '') continue; ?><li style="margin-bottom:8px;"><?php echo htmlspecialchars($rline); ?></li><?php endforeach; ?></ul>
            <?php endif; ?>

            <?php if (!empty($offer['terms_conditions'])): ?>
            <div class="letter-section-heading">Terms and Conditions:</div>
            <ul style="padding-left:20px;"><?php foreach (explode("\n", $offer['terms_conditions']) as $tline): $tline = trim($tline); if ($tline === '') continue; $nb = preg_match('/^\d+\./', $tline); $safe = htmlspecialchars($tline); if($nb) { $safe = preg_replace('/^(\d+\.\s*[^:]+:?)/', '<strong>$1</strong>', $safe); } ?><li style="margin-bottom:8px;<?php echo $nb ? 'list-style:none;margin-left:-20px;' : ''; ?>"><?php echo $safe; ?></li><?php endforeach; ?></ul>
            <?php endif; ?>

            <?php
            $custom = [];
            if (!empty($offer['custom_fields'])) {
                $custom = json_decode($offer['custom_fields'], true) ?: [];
            }
            ?>
            <?php if (!empty($custom)): ?>
            <?php foreach ($custom as $cf): ?>
            <?php if($cf['heading'] ?? ''): ?>
            <div class="letter-section-heading"><?php echo htmlspecialchars($cf['heading']); ?></div>
            <p><?php echo nl2br(htmlspecialchars($cf['text'] ?? '')); ?></p>
            <?php endif; ?>
            <?php endforeach; ?>
            <?php endif; ?>

            <p>We are delighted to welcome you to <strong><?php echo htmlspecialchars($cs['company_name'] ?? ''); ?></strong> and look forward to your valuable contribution to the company's growth and success.</p>

            <p>Please sign and return the duplicate copy of this letter as a token of your acceptance of the above terms and conditions.</p>

            <!-- Company Signature -->
            <div class="letter-sig-area">
                <div class="letter-sig-box">
                    <div style="height:70px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                        <?php if (!empty($cs['company_signature'])): ?>
                        <img src="<?php echo htmlspecialchars($cs['company_signature']); ?>" alt="Company Signature" style="max-height:80px; max-width:180px;">
                        <?php endif; ?>
                    </div>
                    <div class="letter-sig-line" style="margin-top:0;">
                        For <?php echo htmlspecialchars($cs['company_name'] ?? ''); ?><br>
                        <small><strong>Name:</strong> <?php echo htmlspecialchars($cs['signatory_name'] ?? 'Authorized Signatory'); ?></small><br>
                        <small style="font-weight:400;"><strong>Designation:</strong> <?php echo htmlspecialchars($cs['signatory_designation'] ?? ''); ?></small>
                    </div>
                </div>
                <div class="letter-sig-box">
                    <div style="height:100px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                        <?php if ($offer['candidate_action'] == 'accepted'): ?>
                        <img src="<?php echo htmlspecialchars($offer['candidate_signature']); ?>" alt="Candidate Signature" style="max-height:100px; max-width:260px;">
                        <?php endif; ?>
                    </div>
                    <div class="letter-sig-line" style="margin-top:0;">
                        Accepted and Agreed<br>
                        <small><?php echo htmlspecialchars($offer['candidate_name']); ?></small>
                    </div>
                </div>
            </div>
        </div>
        </td></tr></tbody>
        <tfoot class="print-only-spacer-foot"><tr><td style="height: 100px; border:none;"></td></tr></tfoot>
        </table>
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>
    </div>

        <?php if (empty($offer['candidate_signature']) && !in_array($offer['candidate_action'], ['accepted', 'declined'])): ?>
        <!-- Signature & Actions (hidden on print) -->
        <div class="sig-actions">
            <p style="font-size:12px;color:#64748b;margin-bottom:8px;">Sign below using your mouse or finger to accept this offer.</p>
            <canvas id="sigPad" class="sig-pad"></canvas>
            <div style="margin-top:8px;margin-bottom:16px;">
                <button type="button" onclick="clearSig()" style="padding:8px 18px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;color:#64748b;">Clear</button>
            </div>
            <form method="POST" id="offerForm">
                <input type="hidden" name="candidate_action" id="candidateActionInput" value="">
                <input type="hidden" name="signature" id="signatureInput" value="">
                <input type="hidden" name="decline_reason" id="declineReasonInput" value="">
                <button type="button" class="btn-accept" onclick="submitOffer('accept')">✅ Accept Offer & Sign</button>
                <button type="button" class="btn-decline" onclick="showDecline()">❌ Decline Offer</button>
                <div id="declineBox" style="display:none;margin-top:16px;background:#fff5f5;border:1px solid #fca5a5;border-radius:10px;padding:16px;">
                    <label style="font-weight:700;font-size:13px;color:#991b1b;display:block;margin-bottom:8px;">Reason for Declining (Optional)</label>
                    <textarea id="declineReasonTxt" style="width:100%;padding:10px;border:1px solid #fca5a5;border-radius:8px;font-family:inherit;font-size:13px;height:80px;resize:vertical;" placeholder="Please let us know why you're declining..."></textarea>
                    <button type="button" onclick="submitOffer('decline')" style="margin-top:10px;padding:10px 24px;border:none;border-radius:8px;background:#ef4444;color:#fff;font-family:inherit;font-weight:700;cursor:pointer;">Confirm Decline</button>
                </div>
            </form>
        </div>
        <?php endif; ?>
    </div>   </div>
    </div>

    <script>
    // Signature Pad
    var canvas = document.getElementById('sigPad');
    var ctx = canvas.getContext('2d');
    // Size the drawing buffer to the canvas's FINAL rendered size, not whatever it
    // happens to be while the page (e.g. the company logo above it) is still loading
    // and reflowing — otherwise mouse coordinates (in CSS pixels) end up mismatched
    // against the buffer, so the drawn line appears offset from the actual cursor.
    function sizeSigCanvas() {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.strokeStyle = '#1a3fc4'; ctx.lineWidth = 2; ctx.lineCap = 'round';
    }
    sizeSigCanvas();
    window.addEventListener('load', sizeSigCanvas);
    var drawing = false;
    canvas.addEventListener('mousedown', function(e){ drawing=true; ctx.beginPath(); ctx.moveTo(e.offsetX,e.offsetY); });
    canvas.addEventListener('mousemove', function(e){ if(!drawing) return; ctx.lineTo(e.offsetX,e.offsetY); ctx.stroke(); });
    canvas.addEventListener('mouseup', function(){ drawing=false; });
    canvas.addEventListener('touchstart', function(e){ e.preventDefault(); drawing=true; var t=e.touches[0]; var r=canvas.getBoundingClientRect(); ctx.beginPath(); ctx.moveTo(t.clientX-r.left,t.clientY-r.top); });
    canvas.addEventListener('touchmove', function(e){ e.preventDefault(); if(!drawing) return; var t=e.touches[0]; var r=canvas.getBoundingClientRect(); ctx.lineTo(t.clientX-r.left,t.clientY-r.top); ctx.stroke(); });
    canvas.addEventListener('touchend', function(){ drawing=false; });

    function clearSig() { ctx.clearRect(0,0,canvas.width,canvas.height); }

    function isCanvasBlank() {
        var blank = document.createElement('canvas');
        blank.width = canvas.width; blank.height = canvas.height;
        return canvas.toDataURL() === blank.toDataURL();
    }

    function showDecline() { document.getElementById('declineBox').style.display = 'block'; }

    // The signer can draw anywhere in the box — export only the actual drawn
    // strokes (tightly cropped to their bounding box), not the whole blank
    // canvas, so the signature always sits flush against the "Signature:"
    // label wherever it's shown instead of floating in empty space.
    function getCroppedSignature() {
        var w = canvas.width, h = canvas.height;
        var data = ctx.getImageData(0, 0, w, h).data;
        var minX = w, minY = h, maxX = -1, maxY = -1;
        for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
                if (data[(y * w + x) * 4 + 3] > 0) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (maxX < minX || maxY < minY) return canvas.toDataURL();
        var pad = 4;
        minX = Math.max(0, minX - pad); minY = Math.max(0, minY - pad);
        maxX = Math.min(w - 1, maxX + pad); maxY = Math.min(h - 1, maxY + pad);
        var cw = maxX - minX + 1, ch = maxY - minY + 1;
        var cropped = document.createElement('canvas');
        cropped.width = cw; cropped.height = ch;
        cropped.getContext('2d').drawImage(canvas, minX, minY, cw, ch, 0, 0, cw, ch);
        return cropped.toDataURL();
    }

    function submitOffer(action) {
        if (action === 'accept' && isCanvasBlank()) {
            alert('Please sign in the box before accepting the offer.');
            return;
        }
        document.getElementById('candidateActionInput').value = action;
        document.getElementById('signatureInput').value = action === 'accept' ? getCroppedSignature() : '';
        document.getElementById('declineReasonInput').value = document.getElementById('declineReasonTxt') ? document.getElementById('declineReasonTxt').value : '';
        document.getElementById('offerForm').submit();
    }
    </script>
    </body>
    </html>
    <?php
    if (ob_get_level() > 0) { ob_end_flush(); } exit;
}

// ============================================================
// AJAX: SAVE COMPANY SETTINGS
// ============================================================
if (isset($_POST['ajax_save_company_settings'])) {
    header('Content-Type: application/json');
    $upload_dir = 'uploads/hr_offer/';
    if (!is_dir($upload_dir)) mkdir($upload_dir, 0755, true);

    $company_name    = mysqli_real_escape_string($con, $_POST['company_name'] ?? '');
    $company_address = mysqli_real_escape_string($con, $_POST['company_address'] ?? '');
    $company_phone   = mysqli_real_escape_string($con, $_POST['company_phone'] ?? '');
    $company_email   = mysqli_real_escape_string($con, $_POST['company_email'] ?? '');
    $signatory_name  = mysqli_real_escape_string($con, $_POST['signatory_name'] ?? '');
    $signatory_desig = mysqli_real_escape_string($con, $_POST['signatory_designation'] ?? '');

    $existing = getCompanySettings($con);

    $logo_path = mysqli_real_escape_string($con, $existing['company_logo'] ?? '');
    $sig_path  = mysqli_real_escape_string($con, $existing['company_signature'] ?? '');

    if (isset($_FILES['company_logo']) && $_FILES['company_logo']['error'] === UPLOAD_ERR_OK) {
        $ext = strtolower(pathinfo($_FILES['company_logo']['name'], PATHINFO_EXTENSION));
        if (in_array($ext, ['png','jpg','jpeg','gif','svg','webp'])) {
            $new_logo = $upload_dir . 'logo_' . time() . '.' . $ext;
            if (move_uploaded_file($_FILES['company_logo']['tmp_name'], $new_logo)) $logo_path = mysqli_real_escape_string($con, $new_logo);
        }
    }
    if (isset($_FILES['company_signature']) && $_FILES['company_signature']['error'] === UPLOAD_ERR_OK) {
        $ext = strtolower(pathinfo($_FILES['company_signature']['name'], PATHINFO_EXTENSION));
        if (in_array($ext, ['png','jpg','jpeg','gif','svg','webp'])) {
            $new_sig = $upload_dir . 'sig_' . time() . '.' . $ext;
            if (move_uploaded_file($_FILES['company_signature']['tmp_name'], $new_sig)) $sig_path = mysqli_real_escape_string($con, $new_sig);
        }
    }

    if ($existing) {
        mysqli_query($con, "UPDATE hr_offer_company_settings SET company_name='$company_name', company_address='$company_address', company_phone='$company_phone', company_email='$company_email', company_logo='$logo_path', signatory_name='$signatory_name', signatory_designation='$signatory_desig', company_signature='$sig_path' WHERE id=" . intval($existing['id']));
    } else {
        mysqli_query($con, "INSERT INTO hr_offer_company_settings (company_name, company_address, company_phone, company_email, company_logo, signatory_name, signatory_designation, company_signature) VALUES ('$company_name','$company_address','$company_phone','$company_email','$logo_path','$signatory_name','$signatory_desig','$sig_path')");
    }
    echo json_encode(['success' => true]);
    exit;
}

// ============================================================
// AJAX: SAVE OFFER LETTER
// ============================================================
if (isset($_POST['ajax_save_offer'])) {
    header('Content-Type: application/json');
    $candidate_id    = intval($_POST['candidate_id']);
    $offered_ctc     = mysqli_real_escape_string($con, $_POST['offered_ctc'] ?? '');
    $joining_date    = mysqli_real_escape_string($con, $_POST['joining_date'] ?? '');
    $probation       = mysqli_real_escape_string($con, $_POST['probation_period'] ?? '');
    $work_location   = mysqli_real_escape_string($con, $_POST['work_location'] ?? '');
    $reporting_mgr   = mysqli_real_escape_string($con, $_POST['reporting_manager'] ?? '');
    $salutation      = mysqli_real_escape_string($con, $_POST['salutation'] ?? 'Mr.');
    $working_hours   = mysqli_real_escape_string($con, $_POST['working_hours'] ?? '');
    $notice_period   = mysqli_real_escape_string($con, $_POST['notice_period'] ?? '');
    // datetime-local inputs send "YYYY-MM-DDTHH:MM" — MySQL DATETIME needs a space,
    // not "T", or it silently stores the zero-date instead of erroring.
    $offer_validity  = mysqli_real_escape_string($con, str_replace('T', ' ', $_POST['offer_validity'] ?? ''));
    $custom_fields   = mysqli_real_escape_string($con, $_POST['custom_fields'] ?? '[]');
    $roles_resp      = mysqli_real_escape_string($con, $_POST['roles_responsibilities'] ?? '');
    $terms_cond      = mysqli_real_escape_string($con, $_POST['terms_conditions'] ?? '');
    $is_draft        = intval($_POST['is_draft'] ?? 1);
    $status          = $is_draft ? 'draft' : 'ready';

    // Fetch candidate info
    $q = mysqli_query($con, "SELECT * FROM hr_screenings WHERE id=$candidate_id LIMIT 1");
    $cand = $q ? mysqli_fetch_assoc($q) : null;
    if (!$cand) { echo json_encode(['success'=>false,'message'=>'Candidate not found']); exit; }

    $cname  = mysqli_real_escape_string($con, $_POST['candidate_name'] ?? $cand['candidate_name']);
    $cemail = mysqli_real_escape_string($con, $cand['candidate_email'] ?? '');
    $cphone = mysqli_real_escape_string($con, $cand['candidate_phone'] ?? '');
    $caddr  = mysqli_real_escape_string($con, $_POST['candidate_address'] ?? '');
    $cpos   = mysqli_real_escape_string($con, $_POST['position'] ?? $cand['position_applied']);
    $cdept  = mysqli_real_escape_string($con, $_POST['department'] ?? $cand['department']);

    $existing_offer = getOfferByCandidate($con, $candidate_id);

    if ($existing_offer) {
        $oid = $existing_offer['id'];
        $new_status = mysqli_real_escape_string($con, $status);
        $join_sql = $joining_date ? "'$joining_date'" : "NULL";
        
        $token_update = "";
        $action_update = "";
        if (in_array($existing_offer['candidate_action'], ['accepted', 'declined']) || in_array($existing_offer['status'], ['accepted', 'declined'])) {
            $new_token = bin2hex(random_bytes(32));
            $token_update = ", token='$new_token'";
            $action_update = ", candidate_action=NULL, candidate_signature=NULL, candidate_action_at=NULL, decline_reason=NULL";
        }
        
        $update_res = mysqli_query($con, "UPDATE hr_offer_letters SET candidate_name='$cname', salutation='$salutation', candidate_address='$caddr', position='$cpos', department='$cdept', offered_ctc='$offered_ctc', joining_date=$join_sql, probation_period='$probation', work_location='$work_location', reporting_manager='$reporting_mgr', working_hours='$working_hours', notice_period='$notice_period', offer_validity=" . ($offer_validity ? "'$offer_validity'" : "NULL") . ", custom_fields='$custom_fields', roles_responsibilities='$roles_resp', terms_conditions='$terms_cond', status='$new_status', updated_at=NOW() $token_update $action_update WHERE id=$oid");
        if (!$update_res) {
            echo json_encode(['success'=>false,'message'=>'Database error while saving: ' . mysqli_error($con)]);
            exit;
        }
        $ret_token = isset($new_token) ? $new_token : $existing_offer['token'];
        echo json_encode(['success'=>true,'offer_id'=>$oid,'offer_number'=>$existing_offer['offer_number'],'is_revision'=>true,'new_token'=>$ret_token]);
    } else {
        $offer_number = mysqli_real_escape_string($con, generateOfferNumber($con));
        $token = bin2hex(random_bytes(32));
        $created_by = mysqli_real_escape_string($con, $current_user_name);
        $join_sql = $joining_date ? "'$joining_date'" : "NULL";
        $insert_q = "INSERT INTO hr_offer_letters (offer_number, candidate_id, candidate_name, salutation, candidate_email, candidate_phone, candidate_address, position, department, offered_ctc, joining_date, probation_period, work_location, reporting_manager, working_hours, notice_period, offer_validity, custom_fields, roles_responsibilities, terms_conditions, status, token, created_by) VALUES ('$offer_number', $candidate_id, '$cname', '$salutation', '$cemail', '$cphone', '$caddr', '$cpos', '$cdept', '$offered_ctc', $join_sql, '$probation', '$work_location', '$reporting_mgr', '$working_hours', '$notice_period', " . ($offer_validity ? "'$offer_validity'" : "NULL") . ", '$custom_fields', '$roles_resp', '$terms_cond', '$status', '$token', '$created_by')";
        $res = mysqli_query($con, $insert_q);
        if (!$res) { echo json_encode(['success'=>false,'message'=>'Database error. Please fill all fields.']); exit; }
        $oid = mysqli_insert_id($con);
        echo json_encode(['success'=>true,'offer_id'=>$oid,'offer_number'=>$offer_number,'is_revision'=>false]);
    }
    exit;
}

// ============================================================
// AJAX: SAVE REVISED OFFER LETTER — always INSERTs a new row, so
// full history is preserved (unlike ajax_save_offer above, which
// intentionally UPDATEs in place and is left untouched).
// ============================================================
if (isset($_POST['ajax_save_revision'])) {
    header('Content-Type: application/json');
    $employee_id = intval($_POST['employee_id'] ?? 0);
    $employee = getEmployeeForRevision($con, $employee_id);
    if (!$employee) { echo json_encode(['success'=>false,'message'=>'Employee not found']); exit; }

    // Salary structure (revised offer letter only) — components come from the
    // editable table; Gross/Net are sent as typed by HR (auto-calculated in the
    // browser, but still plain editable inputs, so we trust whatever was submitted
    // rather than recomputing and silently overwriting a manual override).
    $salary_basic    = round(floatval($_POST['salary_basic'] ?? 0), 2);
    $salary_hra      = round(floatval($_POST['salary_hra'] ?? 0), 2);
    $salary_special  = round(floatval($_POST['salary_special_allowance'] ?? 0), 2);
    $salary_conv     = round(floatval($_POST['salary_conveyance'] ?? 0), 2);
    $salary_other    = round(floatval($_POST['salary_other_allowances'] ?? 0), 2);
    $salary_deduct   = round(floatval($_POST['salary_deductions'] ?? 0), 2);
    $salary_gross    = round(floatval($_POST['salary_gross'] ?? ($salary_basic + $salary_hra + $salary_special + $salary_conv + $salary_other)), 2);
    $salary_net      = round(floatval($_POST['salary_net'] ?? ($salary_gross - $salary_deduct)), 2);
    // HR-added custom salary rows (e.g. "Bonus") — rebuild from raw POST JSON into a
    // clean {label, amount} array rather than trusting the input string as-is.
    $custom_rows_raw = json_decode($_POST['salary_custom_rows'] ?? '[]', true);
    $custom_rows_clean = [];
    if (is_array($custom_rows_raw)) {
        foreach ($custom_rows_raw as $cr) {
            $label = trim((string)($cr['label'] ?? ''));
            $amount = round(floatval($cr['amount'] ?? 0), 2);
            if ($label !== '') $custom_rows_clean[] = ['label' => $label, 'amount' => $amount];
        }
    }
    $salary_custom_rows = mysqli_real_escape_string($con, json_encode($custom_rows_clean));
    $salary_period   = ($_POST['salary_period'] ?? 'month') === 'annum' ? 'annum' : 'month';
    // "As shown on letter" is a free-text field HR can rewrite (different wording, per
    // annum instead of per month) — use it if they typed something, otherwise fall back
    // to the auto-formatted figure from Net Salary above.
    $offered_ctc_input = trim($_POST['offered_ctc_text'] ?? '');
    $offered_ctc     = mysqli_real_escape_string($con, $offered_ctc_input !== '' ? $offered_ctc_input : ('₹' . number_format($salary_net, 2) . ' per ' . $salary_period));
    // Previous/current CTC is likewise a free-text field HR can correct when the
    // auto-fetched payroll/original-offer figure is wrong or missing.
    $prev_ctc_input  = trim($_POST['previous_ctc'] ?? '');
    $effective_date  = mysqli_real_escape_string($con, $_POST['revision_effective_date'] ?? '');
    $probation       = mysqli_real_escape_string($con, $_POST['probation_period'] ?? '');
    $work_location   = mysqli_real_escape_string($con, $_POST['work_location'] ?? '');
    $reporting_mgr   = mysqli_real_escape_string($con, $_POST['reporting_manager'] ?? '');
    $salutation      = mysqli_real_escape_string($con, $_POST['salutation'] ?? 'Mr.');
    $working_hours   = mysqli_real_escape_string($con, $_POST['working_hours'] ?? '');
    $notice_period   = mysqli_real_escape_string($con, $_POST['notice_period'] ?? '');
    // datetime-local inputs send "YYYY-MM-DDTHH:MM" — MySQL DATETIME needs a space,
    // not "T", or it silently stores the zero-date instead of erroring.
    $offer_validity  = mysqli_real_escape_string($con, str_replace('T', ' ', $_POST['offer_validity'] ?? ''));
    $custom_fields   = mysqli_real_escape_string($con, $_POST['custom_fields'] ?? '[]');
    $roles_resp      = mysqli_real_escape_string($con, $_POST['roles_responsibilities'] ?? '');
    $terms_cond      = mysqli_real_escape_string($con, $_POST['terms_conditions'] ?? '');
    $revision_reason = mysqli_real_escape_string($con, $_POST['revision_reason'] ?? '');
    $cname  = mysqli_real_escape_string($con, $_POST['candidate_name'] ?? $employee['name']);
    // Contact details are free-text fields HR can correct — prefer what was submitted,
    // fall back to the hr_employees record only when the field was left blank.
    $cemail_input = trim($_POST['candidate_email'] ?? '');
    $cemail = mysqli_real_escape_string($con, $cemail_input !== '' ? $cemail_input : ($employee['email'] ?? $employee['personal_email'] ?? ''));
    $cphone_input = trim($_POST['candidate_phone'] ?? '');
    $cphone = mysqli_real_escape_string($con, $cphone_input !== '' ? $cphone_input : ($employee['phone'] ?? $employee['mobile'] ?? ''));
    $caddr_input = trim($_POST['candidate_address'] ?? '');
    $caddr  = mysqli_real_escape_string($con, $caddr_input !== '' ? $caddr_input : ($employee['address'] ?? ''));
    $cempcode_input = trim($_POST['candidate_employee_code'] ?? '');
    $cempcode = mysqli_real_escape_string($con, $cempcode_input !== '' ? $cempcode_input : ($employee['employee_id'] ?? ''));
    $cpos   = mysqli_real_escape_string($con, $_POST['position'] ?? $employee['position']);
    $cdept  = mysqli_real_escape_string($con, $_POST['department'] ?? $employee['department']);
    $is_draft = intval($_POST['is_draft'] ?? 1);
    $status   = $is_draft ? 'draft' : 'ready';

    if ($salary_basic <= 0 || $effective_date === '') {
        echo json_encode(['success'=>false,'message'=>'Basic Salary and Effective Date are required.']);
        exit;
    }

    $latest = getLatestLetterForEmployee($con, $employee_id);
    // If the most recent letter for this employee is a revision that hasn't been sent
    // yet, keep editing that same draft in place instead of stacking up a fresh
    // "Revision N" row on every Save click — history should only grow when a
    // revision actually goes out, not every time HR tweaks a draft.
    $is_editable_draft = $latest && $latest['letter_type'] === 'revision' && empty($latest['sent_at']) && in_array($latest['status'], ['draft', 'ready']);

    if ($is_editable_draft) {
        $oid = intval($latest['id']);
        $token = $latest['token'];
        $offer_number = $latest['offer_number'];
        $next_revision_number = intval($latest['revision_number']);
        $prev_ctc_update = mysqli_real_escape_string($con, $prev_ctc_input !== '' ? $prev_ctc_input : ($latest['previous_ctc'] ?? ''));
        $update_q = "UPDATE hr_offer_letters SET
            candidate_name='$cname', salutation='$salutation', candidate_email='$cemail', candidate_phone='$cphone', candidate_address='$caddr',
            candidate_employee_code='$cempcode',
            position='$cpos', department='$cdept', offered_ctc='$offered_ctc', probation_period='$probation', work_location='$work_location',
            reporting_manager='$reporting_mgr', working_hours='$working_hours', notice_period='$notice_period', previous_ctc='$prev_ctc_update',
            offer_validity=" . ($offer_validity ? "'$offer_validity'" : "NULL") . ", custom_fields='$custom_fields', roles_responsibilities='$roles_resp',
            terms_conditions='$terms_cond', status='$status', revision_effective_date='$effective_date', revision_reason='$revision_reason',
            salary_basic=$salary_basic, salary_hra=$salary_hra, salary_special_allowance=$salary_special, salary_conveyance=$salary_conv,
            salary_other_allowances=$salary_other, salary_deductions=$salary_deduct, salary_gross=$salary_gross, salary_net=$salary_net,
            salary_custom_rows='$salary_custom_rows', salary_period='$salary_period',
            updated_at=NOW() WHERE id=$oid";
        $res = mysqli_query($con, $update_q);
        if (!$res) { echo json_encode(['success'=>false,'message'=>'Database error: ' . mysqli_error($con)]); exit; }
        echo json_encode(['success'=>true,'offer_id'=>$oid,'offer_number'=>$offer_number,'revision_number'=>$next_revision_number,'token'=>$token,'offered_ctc'=>$offered_ctc]);
        exit;
    }

    $prev_ctc = $prev_ctc_input !== '' ? $prev_ctc_input : ($latest ? $latest['offered_ctc'] : ('₹' . number_format(floatval($employee['payroll_total_ctc'] ?? $employee['salary'] ?? 0), 2) . ' per month'));
    $prev_pos = $latest ? $latest['position'] : $employee['position'];
    $next_revision_number = $latest ? (intval($latest['revision_number']) + 1) : 1;
    $parent_offer_id = $latest ? intval($latest['id']) : null;
    $candidate_id_link = $latest ? intval($latest['candidate_id']) : 0;

    $prev_ctc_esc = mysqli_real_escape_string($con, $prev_ctc);
    $prev_pos_esc = mysqli_real_escape_string($con, $prev_pos);
    $offer_number = mysqli_real_escape_string($con, generateOfferNumber($con));
    $token = bin2hex(random_bytes(32));
    $created_by = mysqli_real_escape_string($con, $current_user_name);

    $insert_q = "INSERT INTO hr_offer_letters
        (offer_number, candidate_id, employee_id, candidate_name, salutation, candidate_email, candidate_phone, candidate_address, candidate_employee_code,
         position, department, offered_ctc, joining_date, probation_period, work_location, reporting_manager, working_hours, notice_period,
         offer_validity, custom_fields, roles_responsibilities, terms_conditions, status, letter_type, revision_number, parent_offer_id,
         revision_effective_date, previous_ctc, previous_position, revision_reason, token, created_by,
         salary_basic, salary_hra, salary_special_allowance, salary_conveyance, salary_other_allowances, salary_deductions, salary_gross, salary_net, salary_custom_rows, salary_period)
        VALUES ('$offer_number', $candidate_id_link, $employee_id, '$cname', '$salutation', '$cemail', '$cphone', '$caddr', '$cempcode',
         '$cpos', '$cdept', '$offered_ctc', '$effective_date', '$probation', '$work_location', '$reporting_mgr', '$working_hours', '$notice_period',
         " . ($offer_validity ? "'$offer_validity'" : "NULL") . ", '$custom_fields', '$roles_resp', '$terms_cond', '$status', 'revision', $next_revision_number, " . ($parent_offer_id ? $parent_offer_id : "NULL") . ",
         '$effective_date', '$prev_ctc_esc', '$prev_pos_esc', '$revision_reason', '$token', '$created_by',
         $salary_basic, $salary_hra, $salary_special, $salary_conv, $salary_other, $salary_deduct, $salary_gross, $salary_net, '$salary_custom_rows', '$salary_period')";
    $res = mysqli_query($con, $insert_q);
    if (!$res) { echo json_encode(['success'=>false,'message'=>'Database error: ' . mysqli_error($con)]); exit; }
    $oid = mysqli_insert_id($con);
    echo json_encode(['success'=>true,'offer_id'=>$oid,'offer_number'=>$offer_number,'revision_number'=>$next_revision_number,'token'=>$token,'offered_ctc'=>$offered_ctc]);
    exit;
}

// ============================================================
// AJAX: HR APPROVES AN ACCEPTED REVISION
// Only after this does the letter get filed into the employee's
// documents — the employee's own acceptance alone is not enough.
// ============================================================
if (isset($_POST['ajax_approve_revision'])) {
    header('Content-Type: application/json');
    $offer_id = intval($_POST['offer_id'] ?? 0);
    $rq = mysqli_query($con, "SELECT * FROM hr_offer_letters WHERE id=$offer_id LIMIT 1");
    $rowOffer = $rq ? mysqli_fetch_assoc($rq) : null;
    if (!$rowOffer || $rowOffer['letter_type'] !== 'revision' || $rowOffer['status'] !== 'accepted') {
        echo json_encode(['success'=>false,'message'=>'This revision is not in an accepted state.']);
        exit;
    }
    if (!empty($rowOffer['hr_approved_at'])) {
        echo json_encode(['success'=>false,'message'=>'Already approved.']);
        exit;
    }
    $now = date('Y-m-d H:i:s');
    $approved_by = mysqli_real_escape_string($con, $current_user_name);
    mysqli_query($con, "UPDATE hr_offer_letters SET hr_approved_at='$now', hr_approved_by='$approved_by' WHERE id=$offer_id");

    // hr_employee_documents already exists in production with its own schema
    // (see get-employee-documents.php) — detect the real columns and write
    // into whichever ones actually exist, instead of assuming our own names.
    $doc_cols = [];
    $dc_res = mysqli_query($con, "SHOW COLUMNS FROM hr_employee_documents");
    if ($dc_res) while ($dcr = mysqli_fetch_assoc($dc_res)) $doc_cols[] = $dcr['Field'];

    $doc_label_val = 'Revised Offer Letter – ' . $rowOffer['candidate_name'] . ' - ' . date('j/n/Y', strtotime($now));
    $doc_fname_val = 'Revised_Offer_Letter_' . preg_replace('/[^A-Za-z0-9]+/', '_', $rowOffer['candidate_name']) . '_' . date('d-m-Y', strtotime($now)) . '.pdf';

    // Reverted to the simple, reliable print-page link (Dompdf's real-file
    // generation caused issues) — View opens this correctly; there's just no
    // literal one-click file save, matching how it worked before.
    $doc_filepath_val = 'hr-employee-offer.php?token=' . $rowOffer['token'] . '&download=1';

    $doc_fields = ['employee_id' => intval($rowOffer['employee_id'])];
    if (in_array('filepath', $doc_cols)) $doc_fields['filepath'] = $doc_filepath_val;
    elseif (in_array('file_path', $doc_cols)) $doc_fields['file_path'] = $doc_filepath_val;

    if (in_array('document_label', $doc_cols)) $doc_fields['document_label'] = $doc_label_val;
    elseif (in_array('document_type', $doc_cols)) $doc_fields['document_type'] = $doc_label_val;

    if (in_array('filename', $doc_cols)) $doc_fields['filename'] = $doc_fname_val;
    elseif (in_array('file_name', $doc_cols)) $doc_fields['file_name'] = $doc_fname_val;
    elseif (in_array('original_name', $doc_cols)) $doc_fields['original_name'] = $doc_fname_val;

    foreach (['uploaded_at', 'upload_date', 'created_at', 'date_uploaded', 'date'] as $dcand) {
        if (in_array($dcand, $doc_cols)) { $doc_fields[$dcand] = $now; break; }
    }

    $doc_col_names = array_keys($doc_fields);
    $doc_col_vals = array_map(function($v) use ($con) { return "'" . mysqli_real_escape_string($con, $v) . "'"; }, array_values($doc_fields));
    mysqli_query($con, "INSERT INTO hr_employee_documents (" . implode(',', $doc_col_names) . ") VALUES (" . implode(',', $doc_col_vals) . ")");

    echo json_encode([
        'success' => true,
        'employee_name' => $rowOffer['candidate_name'],
        'offered_ctc' => $rowOffer['offered_ctc'],
        'approved_at' => $now,
        'approved_by' => $current_user_name,
    ]);
    exit;
}

// ============================================================
// AJAX: SEND OFFER (mark sent_at)
// ============================================================
if (isset($_POST['ajax_mark_sent'])) {
    header('Content-Type: application/json');
    $oid = intval($_POST['offer_id']);
    mysqli_query($con, "UPDATE hr_offer_letters SET status='sent', sent_at=NOW() WHERE id=$oid");
    echo json_encode(['success'=>true]);
    exit;
}

// ============================================================
// AJAX: GET OFFER DATA (for preview/edit)
// ============================================================
if (isset($_GET['ajax_get_offer'])) {
    header('Content-Type: application/json');
    $candidate_id = intval($_GET['candidate_id']);
    $offer = getOfferByCandidate($con, $candidate_id);
    $cs = getCompanySettings($con, $candidate_id);
    echo json_encode(['success'=>true,'offer'=>$offer,'company'=>$cs]);
    exit;
}

// ============================================================
// AJAX: DELETE CANDIDATE
// ============================================================
if (isset($_POST['ajax_delete_candidate'])) {
    header('Content-Type: application/json');
    $cid = intval($_POST['candidate_id']);
    if ($cid > 0) {
        mysqli_query($con, "DELETE FROM hr_screenings WHERE id=$cid");
        mysqli_query($con, "DELETE FROM hr_offer_letters WHERE candidate_id=$cid");
        mysqli_query($con, "DELETE FROM hr_dv_requests WHERE candidate_id=$cid");
    }
    echo json_encode(['success'=>true]);
    exit;
}

// ============================================================
// MAIN PAGE VARIABLES
// ============================================================
$candidate_id = intval($_GET['candidate_id'] ?? 0);
$page = $_GET['page'] ?? 'offer'; // offer | settings

// =========================================================================
// EMPLOYEE → ORIGINAL OFFER LETTER LOOKUP — purely additive, does not touch
// the existing candidate_id path at all. Original offers are keyed by
// hr_screenings.id, not hr_employees.id, so there was previously no way to
// go from an employee straight to their original offer. This resolves an
// hr_employees.id to the matching hr_screenings.id (by phone/email, same
// normalization already proven safe in hr_screening.php's duplicate checks)
// and redirects into the untouched existing ?candidate_id= flow below.
// Only runs when ?employee_id= is passed, ?candidate_id= is not, and this
// ISN'T the existing ?page=revise&employee_id= revision flow (which reads
// employee_id for its own, completely different purpose) — so it can never
// interfere with any existing link or bookmark.
if ($candidate_id <= 0 && $page !== 'revise' && intval($_GET['employee_id'] ?? 0) > 0) {
    $lookup_employee_id = intval($_GET['employee_id']);
    $emp_lookup = mysqli_fetch_assoc(mysqli_query($con, "SELECT phone, email FROM hr_employees WHERE id=$lookup_employee_id LIMIT 1"));
    $resolved_screening_id = 0;
    if ($emp_lookup) {
        $emp_phone_digits = preg_replace('/\D/', '', $emp_lookup['phone'] ?? '');
        $emp_email = mysqli_real_escape_string($con, trim($emp_lookup['email'] ?? ''));
        $lookup_cond = [];
        if ($emp_phone_digits) $lookup_cond[] = "REPLACE(REPLACE(REPLACE(candidate_phone,' ',''),'-',''),'+','') = '" . mysqli_real_escape_string($con, $emp_phone_digits) . "'";
        if ($emp_email !== '') $lookup_cond[] = "candidate_email='$emp_email'";
        if (!empty($lookup_cond)) {
            $lookup_res = mysqli_query($con, "SELECT id FROM hr_screenings WHERE (" . implode(' OR ', $lookup_cond) . ") ORDER BY id DESC LIMIT 1");
            if ($lookup_res && $lookup_row = mysqli_fetch_assoc($lookup_res)) $resolved_screening_id = intval($lookup_row['id']);
        }
    }
    if ($resolved_screening_id > 0) {
        header("Location: hr-employee-offer.php?candidate_id=$resolved_screening_id");
        exit;
    } else {
        $employee_offer_not_found = true;
        $employee_offer_not_found_id = $lookup_employee_id;
    }
}

// =========================================================================
// GENERATE ORIGINAL OFFER LETTER FOR AN EMPLOYEE WITH NO SCREENING HISTORY
// — an original offer normally requires an hr_screenings record plus a
// verified hr_dv_requests entry (see "Eligible Candidates" below). This
// backfills the minimum of both behind the scenes for an employee who has
// neither, then redirects into the completely unmodified existing
// ?candidate_id= flow — so the actual offer-letter creation/sending code is
// 100% untouched and identical to what a real screened candidate gets.
// Own distinct trigger param, so it can never collide with the plain
// employee lookup above or the revision flow.
if ($candidate_id <= 0 && intval($_GET['generate_original_for_employee'] ?? 0) > 0) {
    $go_employee_id = intval($_GET['generate_original_for_employee']);
    $go_emp = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_employees WHERE id=$go_employee_id LIMIT 1"));
    if (!$go_emp) {
        $employee_offer_not_found = true;
    } else {
        // If they already resolve to a real screening record after all, reuse
        // it instead of creating a duplicate — same matching as the lookup above.
        $go_phone_digits = preg_replace('/\D/', '', $go_emp['phone'] ?? '');
        $go_email = mysqli_real_escape_string($con, trim($go_emp['email'] ?? ''));
        $go_cond = [];
        if ($go_phone_digits) $go_cond[] = "REPLACE(REPLACE(REPLACE(candidate_phone,' ',''),'-',''),'+','') = '" . mysqli_real_escape_string($con, $go_phone_digits) . "'";
        if ($go_email !== '') $go_cond[] = "candidate_email='$go_email'";
        $go_existing_id = 0;
        if (!empty($go_cond)) {
            $go_res = mysqli_query($con, "SELECT id FROM hr_screenings WHERE (" . implode(' OR ', $go_cond) . ") ORDER BY id DESC LIMIT 1");
            if ($go_res && $go_row = mysqli_fetch_assoc($go_res)) $go_existing_id = intval($go_row['id']);
        }

        if ($go_existing_id > 0) {
            header("Location: hr-employee-offer.php?candidate_id=$go_existing_id");
            exit;
        }

        // getCompanySettings() strictly requires hr_screenings.company_id to be
        // correct, with no fallback — resolve it from the employee's own company.
        $go_company_id = 0;
        if (!empty($go_emp['company_name'])) {
            $go_cname_e = mysqli_real_escape_string($con, $go_emp['company_name']);
            $go_hc = mysqli_fetch_assoc(mysqli_query($con, "SELECT id FROM hr_companies WHERE TRIM(LOWER(company_name))=TRIM(LOWER('$go_cname_e')) LIMIT 1"));
            if ($go_hc) $go_company_id = intval($go_hc['id']);
        }

        $go_name_e  = mysqli_real_escape_string($con, $go_emp['name']);
        $go_email_e = mysqli_real_escape_string($con, $go_emp['email'] ?? '');
        $go_phone_e = mysqli_real_escape_string($con, $go_emp['phone'] ?? '');
        $go_pos_e   = mysqli_real_escape_string($con, $go_emp['position'] ?? '');
        $go_dept_e  = mysqli_real_escape_string($con, $go_emp['department'] ?? '');
        $go_pos_id  = intval($go_emp['position_id'] ?? 0);
        $go_by_e    = mysqli_real_escape_string($con, $currentUserName ?? 'HR');

        mysqli_query($con, "INSERT INTO hr_screenings
            (candidate_name, candidate_email, candidate_phone, position_applied, department, resume_filename, resume_path, eligibility_status, hr_decision, position_id, company_id, moved_to_employee_at, moved_to_employee_by)
            VALUES ('$go_name_e', '$go_email_e', '$go_phone_e', '$go_pos_e', '$go_dept_e', '', '', 'shortlisted', 'hired', $go_pos_id, " . ($go_company_id > 0 ? $go_company_id : "NULL") . ", NOW(), '$go_by_e')");
        $go_new_screening_id = mysqli_insert_id($con);

        // hr_dv_requests isn't owned by this file, so its full schema is
        // unknown here — detect real columns like the hr_employee_documents
        // insert elsewhere in this file does, and only set what this needs.
        $go_dv_cols = [];
        $go_dv_res = mysqli_query($con, "SHOW COLUMNS FROM hr_dv_requests");
        if ($go_dv_res) while ($go_dv_row = mysqli_fetch_assoc($go_dv_res)) $go_dv_cols[] = $go_dv_row['Field'];
        if (!empty($go_dv_cols)) {
            $go_dv_fields = ['candidate_id' => $go_new_screening_id];
            if (in_array('candidate_name', $go_dv_cols)) $go_dv_fields['candidate_name'] = $go_emp['name'];
            if (in_array('status', $go_dv_cols))         $go_dv_fields['status'] = 'verified';
            if (in_array('verified_at', $go_dv_cols))    $go_dv_fields['verified_at'] = date('Y-m-d H:i:s');
            if (in_array('verified_by', $go_dv_cols))    $go_dv_fields['verified_by'] = $currentUserName ?? 'HR';
            $go_dv_col_names = array_keys($go_dv_fields);
            $go_dv_col_vals  = array_map(function($v) use ($con) { return "'" . mysqli_real_escape_string($con, $v) . "'"; }, array_values($go_dv_fields));
            mysqli_query($con, "INSERT INTO hr_dv_requests (" . implode(',', $go_dv_col_names) . ") VALUES (" . implode(',', $go_dv_col_vals) . ")");
        }

        header("Location: hr-employee-offer.php?candidate_id=$go_new_screening_id");
        exit;
    }
}

$candidate = null;
$offer = null;
if ($candidate_id > 0) {
    $q = mysqli_query($con, "SELECT * FROM hr_screenings WHERE id=$candidate_id LIMIT 1");
    $candidate = $q ? mysqli_fetch_assoc($q) : null;
    $offer = getOfferByCandidate($con, $candidate_id);
}
$cs = getCompanySettings($con, $candidate_id ?? 0);
if (empty($cs) && $candidate_id > 0) {
    echo "<div style='background:#fff3cd;color:#856404;padding:15px;text-align:center;border:1px solid #ffeeba;border-radius:8px;margin:20px;'><strong>Warning:</strong> Company branding is not configured for this candidate's company. Please ask HR to set up Company Settings for this candidate's company before sending this offer.</div>";
}

// Fetch all candidates for the quick-switcher dropdown
$all_candidates = [];
$c_res = mysqli_query($con, "SELECT id, candidate_name, position_applied, department FROM hr_screenings ORDER BY id DESC");
if ($c_res) {
    while ($row = mysqli_fetch_assoc($c_res)) {
        $all_candidates[] = $row;
    }
}

// Fetch all active employees, for the "Generate Revised Offer Letter" picker
$all_employees_for_revision = [];
$e_res = mysqli_query($con, "SELECT id, name, position, department, company_name FROM hr_employees WHERE status='active' ORDER BY name ASC");
if ($e_res) {
    while ($erow = mysqli_fetch_assoc($e_res)) {
        $all_employees_for_revision[] = $erow;
    }
}

// Build offer link
$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']==='on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
$script_dir = '/hrm';
$offer_link = $offer ? $base_url . $script_dir . '/hr-employee-offer.php?token=' . $offer['token'] : '';

// Pre-filled email & whatsapp
$email_subject = $offer ? rawurlencode('Offer Letter — ' . ($offer['position'] ?? '') . ' | ' . ($offer['offer_number'] ?? '')) : '';
$email_body_raw = $offer ? "Dear {$offer['candidate_name']},\n\nWe are delighted to extend an offer for the position of {$offer['position']} at {$cs['company_name']}.\n\nPlease review and accept your offer letter using the secure link below:\n{$offer_link}\n\nThis offer is valid until: " . ($offer['offer_validity'] ? date('d M Y, h:i A', strtotime($offer['offer_validity'])) : 'As discussed') . "\n\nLooking forward to welcoming you to the team.\n\nBest Regards,\n{$cs['signatory_name']}\n{$cs['signatory_designation']}\n{$cs['company_name']}" : '';
$email_body = rawurlencode($email_body_raw);
$wa_body = rawurlencode($offer ? ("Hi {$offer['candidate_name']},\n\nYour offer letter for *{$offer['position']}* at *{$cs['company_name']}* is ready.\n\nPlease click the link below to review and accept:\n{$offer_link}\n\nValid until: " . ($offer['offer_validity'] ? date('d M Y, h:i A', strtotime($offer['offer_validity'])) : 'As discussed')) : '');
$cand_phone_clean = preg_replace('/[^0-9]/', '', $candidate['candidate_phone'] ?? '');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>HR Offer Letter</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--success:#10b981;--warn:#f59e0b;--danger:#ef4444;--bg:#f0f4f9;--card:#fff;--border:#e4e9f2;--muted:#64748b;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;color:#0f172a;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:18px 28px;display:flex;justify-content:space-between;align-items:center;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-size:1.3rem;font-weight:800;margin:0;}
.wrap{max-width:1200px;margin:0 auto;padding:24px 20px;}
.card-s{background:var(--card);border-radius:14px;border:1px solid var(--border);box-shadow:0 2px 10px rgba(0,0,0,.05);padding:24px;margin-bottom:20px;}
.sec-lbl{font-weight:800;font-size:11px;text-transform:uppercase;color:var(--blue);margin-bottom:14px;padding-bottom:8px;border-bottom:2px solid #eef2ff;display:flex;align-items:center;gap:7px;}
.fc{border:2px solid var(--border);border-radius:9px;padding:10px 13px;font-size:13px;font-family:inherit;font-weight:600;width:100%;transition:.2s;background:#fff;color:#0f172a;}
.fc:focus{outline:none;border-color:var(--blue);box-shadow:0 0 0 3px rgba(26,63,196,.08);}
label.fl{font-weight:700;font-size:12px;display:block;margin-bottom:5px;color:var(--navy);}
.fg{margin-bottom:14px;}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;}
.grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px;}
.btn-p{padding:11px 22px;border:none;border-radius:10px;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;display:inline-flex;align-items:center;gap:7px;transition:.2s;text-decoration:none;}
.btn-navy{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;}
.btn-green{background:linear-gradient(135deg,var(--success),#059669);color:#fff;}
.btn-warn{background:linear-gradient(135deg,var(--warn),#d97706);color:#fff;}
.btn-light{background:#f1f5f9;color:var(--navy);border:1px solid var(--border);}
.btn-p:hover{transform:translateY(-1px);box-shadow:0 5px 15px rgba(0,0,0,.12);color:#fff;text-decoration:none;}
.btn-light:hover{color:var(--navy);}
.status-badge{padding:5px 14px;border-radius:20px;font-size:12px;font-weight:800;display:inline-block;}
.s-draft{background:#f1f5f9;color:#475569;}
.s-ready{background:#dbeafe;color:#1e40af;}
.s-sent{background:#fef9c3;color:#713f12;}
.s-accepted{background:#dcfce7;color:#065f46;}
.s-declined{background:#fee2e2;color:#991b1b;}
.tab-bar{display:flex;gap:5px;background:var(--card);padding:7px;border-radius:13px;border:1px solid var(--border);margin-bottom:20px;}
.tab-btn{flex:1;padding:10px;border:none;background:transparent;font-family:inherit;font-weight:700;font-size:13px;color:var(--muted);border-radius:9px;cursor:pointer;transition:.2s;display:flex;align-items:center;justify-content:center;gap:6px;}
.tab-btn.active{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;}
.custom-field-row{display:grid;grid-template-columns:1fr 2fr auto;gap:10px;align-items:center;background:#f8faff;border:1px solid #e0e7ff;border-radius:9px;padding:10px 14px;margin-bottom:8px;}
.alert-ok{background:#dcfce7;border:1px solid #86efac;color:#065f46;padding:12px 16px;border-radius:10px;font-weight:700;margin-bottom:16px;display:flex;align-items:center;gap:8px;}
.alert-err{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:12px 16px;border-radius:10px;font-weight:700;margin-bottom:16px;display:flex;align-items:center;gap:8px;}

/* Navigation Tabs */
.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 20px; }
.nav-btn {
    padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
    font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
    display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

/* PDF Preview Styles */
.pdf-preview{width:210mm;min-height:297mm;margin:0 auto;background:#fff;box-shadow:0 4px 15px rgba(0,0,0,0.2);font-family:Arial,sans-serif;font-size:14px;line-height:1.6;color:#1a202c;transform:none;zoom:1;}
.letter-header{display:flex;justify-content:space-between;align-items:center;padding:20px 40px 16px 40px;border-bottom:3px solid #0f2557;background:#fff;}
.letter-header-left{font-size:15px;color:#1a202c;line-height:2.1;font-weight:600;margin-left:30px;}
.letter-header-left span{display:flex;align-items:center;gap:7px;}
.letter-header-left i{width:26px;text-align:center;font-size:26px;}
.letter-header-right{text-align:right;}
.letter-header-right img{max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;}
.letter-company-name-right{font-size:12px;font-weight:800;color:#0f2557;margin-top:3px;}
.letter-company-tagline{font-size:10px;color:#6b7280;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;margin-top:2px;}
.letter-wave{width:100%;line-height:0;display:block;margin-bottom:0;}
.letter-wave svg{width:100%;height:55px;display:block;}
.letter-body{padding:32px 40px 28px 40px;}
.letter-body p{margin-bottom:10px;}
.letter-body ul{margin:6px 0 10px 22px;}
.letter-body ul li{margin-bottom:3px;}
.letter-from{margin-bottom:16px;}
.letter-from strong{display:block;font-size:14px;}
.letter-to{margin-bottom:16px;}
.letter-subject{text-align:center;font-weight:700;text-decoration:underline;margin:18px 0 14px 0;font-size:13.5px;}
.letter-section-heading{font-weight:700;margin:14px 0 6px 0;}
.letter-sig-area{display:flex;justify-content:space-between;margin-top:30px;}
.letter-sig-box{text-align:center;width:200px;}
.letter-sig-line{border-top:1px solid #334155;margin-top:50px;padding-top:6px;font-size:12px;font-weight:700;}

/* Toast Notification */
.toast-card {
    position: fixed;
    top: 24px;
    right: -350px;
    width: 300px;
    background: #fff;
    border-left: 5px solid var(--success);
    border-radius: 10px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.15);
    padding: 16px 20px;
    z-index: 9999;
    transition: right 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
    display: flex;
    align-items: center;
    gap: 14px;
}
.toast-card.show { right: 24px; }
.toast-card.error { border-left-color: var(--danger); }
.toast-icon { font-size: 22px; color: var(--success); }
.toast-card.error .toast-icon { color: var(--danger); }
.toast-text { font-size: 13px; font-weight: 700; color: var(--navy); line-height: 1.4; }


    .print-only-spacer{display:none;}
@media print{
    @page { margin: 0 !important; size: A4 portrait !important; }
    .print-only-spacer{display:table-header-group !important;}
    .print-only-spacer-foot{display:table-footer-group !important;}
    html, body { background: #fff !important; padding: 0 !important; margin: 0 !important; width: 210mm !important; height: auto !important; }
    .no-print, #main-sidebar, #main-topbar, .hdr, .status-bar, .sec-lbl, .alert-ok, .alert-err, .tab-bar, .nav-tabs-container { display: none !important; }
    * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; transform: none !important; zoom: 1 !important; }

    .app-content, #content, .app, .wrap {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        max-width: none !important;
        background: #fff !important;
    }

    .card-s {
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        background: transparent !important;
    }

    .offer-tab-pane { display: none !important; }
    #pane-preview, #pane-signed { display: block !important; }

    .pdf-preview {
        display: block !important;
        border: none !important;
        padding: 0 !important;
        margin: 0 auto !important;
        box-shadow: none !important;
        width: 210mm !important;
        max-width: 210mm !important;
        min-height: 0 !important;
        font-size: 13px !important;
        transform: none !important;
    }

    .pdf-preview .letter-wave-top {
        position: static !important;
    }
    .pdf-preview .letter-header {
        position: static !important;
    }
    .pdf-preview .print-only-spacer,
    .pdf-preview .print-only-spacer-foot {
        display: none !important;
    }

    .letter-header, .letter-body { padding-left: 20mm !important; padding-right: 20mm !important; }
    .letter-sig-area { page-break-inside: avoid !important; }
}
@media(max-width:768px){.grid2,.grid3{grid-template-columns:1fr;} .hdr{flex-direction:column;gap:10px;}}
</style>
</head>
<body>

<div class="hdr">
  <div>
    <?php if (!$candidate): ?>
    <h1><i class="fas fa-layer-group mr-2"></i>HR Screening Rounds Configuration</h1>
    <?php else: ?>
    <h1><i class="fas fa-file-signature mr-2"></i>HR Offer Letter</h1>
    <div style="color:rgba(255,255,255,.7);font-size:12px;margin-top:3px;display:flex;align-items:center;gap:8px;">
      Candidate:
      <select onchange="if(this.value) window.location.href='hr-employee-offer.php?candidate_id='+this.value;" style="padding:4px 8px;border-radius:6px;border:none;background:rgba(255,255,255,0.2);color:#fff;font-family:inherit;font-size:12px;font-weight:700;outline:none;cursor:pointer;">
        <option value="" style="color:#000;">-- Select Candidate --</option>
        <?php foreach($all_candidates as $c): ?>
          <option value="<?php echo $c['id']; ?>" style="color:#000;" <?php echo ($candidate_id == $c['id']) ? 'selected' : ''; ?>>
            <?php echo htmlspecialchars($c['candidate_name'] . ' (' . $c['position_applied'] . ')'); ?>
          </option>
        <?php endforeach; ?>
      </select>
    </div>
    <?php endif; ?>
    <div style="color:rgba(255,255,255,.7);font-size:12px;margin-top:6px;display:flex;align-items:center;gap:8px;">
      Or find by Employee:
      <select onchange="if(this.value) window.location.href='hr-employee-offer.php?employee_id='+this.value;" style="padding:4px 8px;border-radius:6px;border:none;background:rgba(255,255,255,0.2);color:#fff;font-family:inherit;font-size:12px;font-weight:700;outline:none;cursor:pointer;">
        <option value="" style="color:#000;">-- Select Employee --</option>
        <?php foreach($all_employees_for_revision as $e): ?>
          <option value="<?php echo $e['id']; ?>" style="color:#000;">
            <?php echo htmlspecialchars($e['name'] . ' (' . $e['position'] . ')'); ?>
          </option>
        <?php endforeach; ?>
      </select>
    </div>
  </div>
  <div style="display:flex;gap:9px;">
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    
    <?php if ($page !== 'revise'): ?>
    <button type="button" class="btn-p btn-green no-print" data-toggle="modal" data-target="#revisePickerModal"><i class="fas fa-file-signature"></i> Generate Revised Offer Letter</button>
    <?php endif; ?>
    <?php if ($page !== 'settings'): ?>
    <a href="hr-employee-offer.php?page=settings<?php echo $candidate_id ? '&candidate_id='.$candidate_id : ''; ?>" class="btn-p btn-warn no-print"><i class="fas fa-cog"></i> Company Settings</a>
    <?php endif; ?>
    <a href="hr_screening.php" class="btn-p btn-light no-print"><i class="fas fa-arrow-left"></i> Back to Screening</a>
  </div>
</div>

<!-- REVISE PICKER MODAL -->
<div class="modal fade" id="revisePickerModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:14px;border:none;">
    <div class="modal-header" style="background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;border-radius:14px 14px 0 0;">
      <h5 class="modal-title"><i class="fas fa-file-signature mr-2"></i>Generate Revised Offer Letter</h5>
      <button type="button" class="close" data-dismiss="modal" style="color:#fff;opacity:.9;text-shadow:none;">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px;">
      <label class="fl">Select Employee</label>
      <input type="text" id="revPickerSearch" class="fc" placeholder="Search employee by name..." style="margin-bottom:10px;" onkeyup="filterRevPicker()">
      <select id="revPickerSelect" class="fc" size="8" style="height:auto;">
        <?php foreach ($all_employees_for_revision as $emp): ?>
        <option value="<?php echo intval($emp['id']); ?>" data-search="<?php echo strtolower(htmlspecialchars($emp['name'])); ?>">
          <?php echo htmlspecialchars($emp['name']); ?> — <?php echo htmlspecialchars($emp['position']); ?> (<?php echo htmlspecialchars($emp['department']); ?>)
        </option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="modal-footer">
      <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
      <button type="button" class="btn-p btn-navy" onclick="goToRevisePage()"><i class="fas fa-arrow-right"></i> Continue</button>
    </div>
  </div></div>
</div>
<script>
function filterRevPicker() {
    var filter = document.getElementById('revPickerSearch').value.toLowerCase();
    var options = document.getElementById('revPickerSelect').options;
    for (var i = 0; i < options.length; i++) {
        var match = options[i].getAttribute('data-search').indexOf(filter) > -1;
        options[i].style.display = match ? '' : 'none';
    }
}
function goToRevisePage() {
    var sel = document.getElementById('revPickerSelect');
    if (!sel.value) { alert('Please select an employee.'); return; }
    window.location.href = 'hr-employee-offer.php?page=revise&employee_id=' + sel.value;
}
</script>

<div class="wrap">

  <div class="nav-tabs-container no-print">
    <a href="hr-managing-rounds-kpq.php?view=rounds" class="nav-btn">
      <i class="fas fa-list-ol"></i> Manage Rounds
    </a>
    <a href="hr-managing-rounds-kpq.php?view=questions" class="nav-btn">
      <i class="fas fa-question-circle"></i> Manage Questions (KPQ)
    </a>
    <a href="hr-document-verification.php" class="nav-btn">
      <i class="fas fa-file-alt"></i> Manage Documents
    </a>
    <a href="hr-employee-offer.php" class="nav-btn <?php echo $page !== 'settings' ? 'active' : ''; ?>">
      <i class="fas fa-envelope-open-text"></i> Manage Offer Letters
    </a>
  </div>

<?php if ($page === 'settings'): ?>
<!-- ==================== COMPANY SETTINGS PAGE ==================== -->
<?php
// ---- ENSURE TABLE HAS id AS PRIMARY KEY ----
mysqli_query($con, "ALTER TABLE hr_offer_company_settings ADD COLUMN IF NOT EXISTS id INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST");

// Add columns safely
mysqli_query($con, "ALTER TABLE hr_offer_company_settings
ADD COLUMN IF NOT EXISTS company_phone varchar(30) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS signatory_name varchar(255) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS signatory_designation varchar(255) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS company_address text DEFAULT NULL,
ADD COLUMN IF NOT EXISTS company_website varchar(255) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS signature_path varchar(500) DEFAULT NULL");
ensureCompanySmtpColumns($con);

// ---- AJAX: TEST SMTP (tests the values currently in the form, not necessarily saved yet) ----
if (isset($_POST['ajax_test_smtp'])) { if (ob_get_level() > 0) { ob_clean(); }
    header('Content-Type: application/json');
    $test_smtp = [
        'host'       => trim($_POST['smtp_host'] ?? ''),
        'port'       => intval($_POST['smtp_port'] ?? 587),
        'secure'     => trim($_POST['smtp_secure'] ?? 'tls'),
        'username'   => trim($_POST['smtp_username'] ?? ''),
        'password'   => (string)($_POST['smtp_password'] ?? ''),
        'from_email' => trim($_POST['smtp_username'] ?? ''),
        'from_name'  => trim($_POST['smtp_from_name'] ?? '') ?: trim($_POST['smtp_username'] ?? ''),
    ];
    $test_to = trim($_POST['smtp_test_to'] ?? '');
    // Password may be blank if the user is re-testing a saved config without retyping it.
    if (empty($test_smtp['password']) && intval($_POST['company_row_id'] ?? 0) > 0) {
        $existing_res = mysqli_query($con, "SELECT smtp_password_enc FROM hr_offer_company_settings WHERE id=" . intval($_POST['company_row_id']) . " LIMIT 1");
        $existing_row = $existing_res ? mysqli_fetch_assoc($existing_res) : null;
        if ($existing_row && !empty($existing_row['smtp_password_enc'])) {
            $test_smtp['password'] = smtpDecrypt($existing_row['smtp_password_enc']);
        }
    }
    if (empty($test_smtp['host']) || empty($test_smtp['username']) || empty($test_smtp['password']) || empty($test_to)) {
        echo json_encode(['success' => false, 'message' => 'Fill in SMTP Host, Username, Password and a "Send test to" address first.']);
        exit;
    }
    $result = sendViaSmtpConfig($test_smtp, $test_to, 'SMTP Test Email', "This is a test email confirming your SMTP settings are working correctly.\n\nSent " . date('d M Y, h:i A'));

    // On a successful test, save these values immediately (same as the finance
    // system's test-smtp) so a page refresh doesn't lose what was just verified —
    // only "Save All Companies" persisted before, which is what was wiping the form.
    $company_row_id = intval($_POST['company_row_id'] ?? 0);
    if ($result['success'] && $company_row_id > 0) {
        $h  = mysqli_real_escape_string($con, $test_smtp['host']);
        $p  = intval($test_smtp['port']);
        $s  = mysqli_real_escape_string($con, $test_smtp['secure']);
        $u  = mysqli_real_escape_string($con, $test_smtp['username']);
        $fn = mysqli_real_escape_string($con, $test_smtp['from_name']);
        $pe = mysqli_real_escape_string($con, smtpEncrypt($test_smtp['password']));
        mysqli_query($con, "UPDATE hr_offer_company_settings SET
            smtp_host='$h', smtp_port=$p, smtp_secure='$s', smtp_username='$u',
            smtp_from_name='$fn', smtp_password_enc='$pe' WHERE id=$company_row_id");
    } elseif ($result['success']) {
        $result['message'] .= ' (Save this company first to store these settings permanently.)';
    } if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode($result);
    exit;
}

// ---- HANDLE ADD/UPDATE COMPANY SETTINGS ----
if (isset($_POST['save_company_settings'])) {
    $rows = $_POST['company'] ?? [];
    foreach ($rows as $cid => $c) {
        $cid  = intval($cid);
        $name = mysqli_real_escape_string($con, $c['company_name'] ?? '');
        $comp_id_link = intval($c['company_id'] ?? 0);
        if ($name === '' && $comp_id_link > 0) { $__nr = mysqli_fetch_assoc(mysqli_query($con, "SELECT company_name FROM hr_companies WHERE id=$comp_id_link LIMIT 1")); if ($__nr) $name = mysqli_real_escape_string($con, $__nr['company_name']); }  // resolve the name from hr_companies by id
        $email= mysqli_real_escape_string($con, $c['company_email'] ?? '');
        $phone= mysqli_real_escape_string($con, $c['company_phone'] ?? '');
        $website = mysqli_real_escape_string($con, $c['company_website'] ?? '');
        $sign = mysqli_real_escape_string($con, $c['signatory_name'] ?? '');
        $desig= mysqli_real_escape_string($con, $c['signatory_designation'] ?? '');
        $addr = mysqli_real_escape_string($con, $c['company_address'] ?? '');

        $smtp_host     = mysqli_real_escape_string($con, trim($c['smtp_host'] ?? ''));
        $smtp_port     = intval($c['smtp_port'] ?? 587);
        $smtp_secure   = mysqli_real_escape_string($con, ($c['smtp_secure'] ?? 'tls') === 'ssl' ? 'ssl' : 'tls');
        $smtp_username = mysqli_real_escape_string($con, trim($c['smtp_username'] ?? ''));
        $smtp_from_name= mysqli_real_escape_string($con, trim($c['smtp_from_name'] ?? ''));
        $smtp_password_raw = (string)($c['smtp_password'] ?? '');
        // Blank password on an existing row means "keep the one already saved" —
        // the form never re-displays the decrypted password, so blank isn't "clear it".
        if ($smtp_password_raw !== '') {
            $smtp_pass_sql = ", smtp_password_enc='" . mysqli_real_escape_string($con, smtpEncrypt($smtp_password_raw)) . "'";
        } else {
            $smtp_pass_sql = "";
        }

        // Handle logo upload (single clean pass — no duplicate move_uploaded_file calls)
        $logo_sql = "";
        if (isset($_FILES['company']['name'][$cid]['logo']) && $_FILES['company']['error'][$cid]['logo'] === UPLOAD_ERR_OK) {
            $logo_dir = 'uploads/offer_logos/';
            if (!is_dir($logo_dir)) mkdir($logo_dir, 0755, true);
            $logo_ext = strtolower(pathinfo($_FILES['company']['name'][$cid]['logo'], PATHINFO_EXTENSION));
            $logo_path = $logo_dir . 'logo_' . time() . '_' . $cid . '.' . $logo_ext;
            if (move_uploaded_file($_FILES['company']['tmp_name'][$cid]['logo'], $logo_path)) {
                $logo_sql = ", company_logo='" . mysqli_real_escape_string($con, $logo_path) . "'";
            }
        }

        // Handle signature upload (single clean pass)
        $sig_sql = "";
        if (isset($_FILES['company']['name'][$cid]['signature']) && $_FILES['company']['error'][$cid]['signature'] === UPLOAD_ERR_OK) {
            $sig_dir = 'uploads/offer_signatures/';
            if (!is_dir($sig_dir)) mkdir($sig_dir, 0755, true);
            $sig_ext = strtolower(pathinfo($_FILES['company']['name'][$cid]['signature'], PATHINFO_EXTENSION));
            $sig_path = $sig_dir . 'sig_' . time() . '_' . $cid . '.' . $sig_ext;
            if (move_uploaded_file($_FILES['company']['tmp_name'][$cid]['signature'], $sig_path)) {
                $sig_sql = ", company_signature='" . mysqli_real_escape_string($con, $sig_path) . "'";
            }
        }

        if ($cid > 0) {
            // Update existing
            mysqli_query($con, "UPDATE hr_offer_company_settings SET
                company_id=$comp_id_link, company_name='$name', company_email='$email', company_phone='$phone', company_website='$website',
                signatory_name='$sign', signatory_designation='$desig', company_address='$addr',
                smtp_host='$smtp_host', smtp_port=$smtp_port, smtp_secure='$smtp_secure', smtp_username='$smtp_username', smtp_from_name='$smtp_from_name'
                $smtp_pass_sql $logo_sql $sig_sql WHERE id=$cid");
        } else {
            // New row insert
            if (!empty($name)) {
                mysqli_query($con, "INSERT INTO hr_offer_company_settings
                    (company_id, company_name, company_email, company_phone, company_website, signatory_name, signatory_designation, company_address,
                     smtp_host, smtp_port, smtp_secure, smtp_username, smtp_from_name)
                    VALUES ($comp_id_link, '$name','$email','$phone','$website','$sign','$desig','$addr',
                     '$smtp_host',$smtp_port,'$smtp_secure','$smtp_username','$smtp_from_name')");
                $new_id = mysqli_insert_id($con);
                if ($logo_sql || $sig_sql || $smtp_pass_sql) {
                    mysqli_query($con, "UPDATE hr_offer_company_settings SET 1=1 $logo_sql $sig_sql $smtp_pass_sql WHERE id=$new_id");
                }
            }
        }
    }
    $_SESSION['success_msg'] = "Company settings saved.";
    header("Location: hr-employee-offer.php?page=settings");
    exit;
}

// ---- HANDLE DELETE COMPANY ----
if (isset($_POST['delete_company_id'])) {
    $del_id = intval($_POST['delete_company_id']);
    if ($del_id > 0) {
        mysqli_query($con, "DELETE FROM hr_offer_company_settings WHERE id=$del_id");
    }
    header("Location: hr-employee-offer.php?page=settings");
    exit;
}

// ---- FETCH ALL COMPANIES ----
$companies_res = mysqli_query($con, "SELECT * FROM hr_offer_company_settings ORDER BY id ASC");
$companies = [];
if ($companies_res) {
    while ($crow = mysqli_fetch_assoc($companies_res)) $companies[] = $crow;
}
// If no companies exist yet, add one empty placeholder
if (empty($companies)) $companies[] = ['id'=>0,'company_name'=>'','company_email'=>'','company_phone'=>'','signatory_name'=>'','signatory_designation'=>'','company_address'=>'','company_logo'=>'','signature_path'=>''];

// ---- FETCH MASTER COMPANIES ----
$master_companies = [];
$mc_res = mysqli_query($con, "SELECT id, company_name FROM hr_companies ORDER BY company_name ASC");
if ($mc_res) {
    while ($mc = mysqli_fetch_assoc($mc_res)) $master_companies[] = $mc;
}
?>

<?php if (isset($_SESSION['success_msg'])): ?>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            if (typeof showToast === 'function') {
                showToast("<?php echo addslashes($_SESSION['success_msg']); ?>");
            } else {
                alert("<?php echo addslashes($_SESSION['success_msg']); ?>");
            }
        });
    </script>
    <?php unset($_SESSION['success_msg']); ?>
<?php endif; ?>

<form method="POST" enctype="multipart/form-data" id="companySettingsForm">
<input type="hidden" name="save_company_settings" value="1">

<div id="companiesWrapper">
<?php foreach ($companies as $idx => $co):
    $cid = intval($co['id']);
    $isFirst = ($idx === 0);
?>
<div class="company-settings-row" id="companyRow_<?php echo $cid; ?>" style="background:#fff;border:2px solid #e0e7ff;border-radius:14px;padding:24px;margin-bottom:20px;">
    
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:18px;">
        <div style="font-weight:800;font-size:13px;text-transform:uppercase;color:#0f2557;letter-spacing:.5px;">
            <i class="fas fa-building mr-2" style="color:#1a3fc4;"></i>
            <?php echo $isFirst && $cid > 0 ? 'Company Settings' : 'Company #'.($idx+1); ?>
        </div>
        <?php if ($cid > 0): ?>
        <div style="display:flex;gap:8px;">
            <button type="submit" form="delForm_<?php echo $cid; ?>" style="padding:6px 14px;border:none;border-radius:7px;background:#fee2e2;color:#991b1b;font-weight:700;font-size:12px;cursor:pointer;" onclick="return confirm('Delete this company?');"><i class="fas fa-trash mr-1"></i>Remove</button>
        </div>
        <?php endif; ?>
    </div>

    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Name</label>
            <select name="company[<?php echo $cid; ?>][company_id]" class="fc" onchange="this.form.querySelector('input[name=\'company[<?php echo $cid; ?>][company_name]\']').value = this.options[this.selectedIndex].text;">
                <option value="">Select Company...</option>
                <?php foreach ($master_companies as $mc): ?>
                <option value="<?php echo $mc['id']; ?>" <?php echo (isset($co['company_id']) && intval($co['company_id']) === intval($mc['id'])) ? 'selected' : ''; ?>><?php echo htmlspecialchars($mc['company_name']); ?></option>
                <?php endforeach; ?>
            </select>
            <input type="hidden" name="company[<?php echo $cid; ?>][company_name]" value="<?php echo htmlspecialchars($co['company_name'] ?? ''); ?>">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Email</label>
            <input type="email" name="company[<?php echo $cid; ?>][company_email]" class="fc" value="<?php echo htmlspecialchars($co['company_email'] ?? ''); ?>">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Phone</label>
            <input type="text" name="company[<?php echo $cid; ?>][company_phone]" class="fc" value="<?php echo htmlspecialchars($co['company_phone'] ?? ''); ?>">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Website</label>
            <input type="text" name="company[<?php echo $cid; ?>][company_website]" class="fc" value="<?php echo htmlspecialchars($co['company_website'] ?? ''); ?>" placeholder="e.g. www.example.com">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Authorized Signatory Name</label>
            <input type="text" name="company[<?php echo $cid; ?>][signatory_name]" class="fc" value="<?php echo htmlspecialchars($co['signatory_name'] ?? $co['authorized_signatory'] ?? ''); ?>">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Signatory Designation</label>
            <input type="text" name="company[<?php echo $cid; ?>][signatory_designation]" class="fc" value="<?php echo htmlspecialchars($co['signatory_designation'] ?? ''); ?>">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Address</label>
            <textarea name="company[<?php echo $cid; ?>][company_address]" class="fc" style="height:70px;resize:vertical;"><?php echo htmlspecialchars($co['company_address'] ?? ''); ?></textarea>
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Logo</label>
            <?php if (!empty($co['company_logo']) && file_exists($co['company_logo'])): ?>
                <img src="<?php echo htmlspecialchars($co['company_logo']); ?>" style="height:50px;margin-bottom:6px;display:block;border:1px solid #e0e7ff;border-radius:6px;padding:4px;">
            <?php endif; ?>
            <input type="file" name="company[<?php echo $cid; ?>][logo]" accept="image/*" style="font-size:13px;">
        </div>
        <div>
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Signature Image</label>
            <?php if (!empty($co['signature_path']) && file_exists($co['signature_path'])): ?>
                <img src="<?php echo htmlspecialchars($co['signature_path']); ?>" style="height:50px;margin-bottom:6px;display:block;border:1px solid #e0e7ff;border-radius:6px;padding:4px;">
            <?php elseif (!empty($co['company_signature']) && file_exists($co['company_signature'])): ?>
                <img src="<?php echo htmlspecialchars($co['company_signature']); ?>" style="height:50px;margin-bottom:6px;display:block;border:1px solid #e0e7ff;border-radius:6px;padding:4px;">
            <?php endif; ?>
            <input type="file" name="company[<?php echo $cid; ?>][signature]" accept="image/*" style="font-size:13px;">
        </div>
    </div>

    <div style="margin-top:20px;padding-top:18px;border-top:1px dashed #e0e7ff;">
        <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#0f2557;letter-spacing:.5px;margin-bottom:14px;"><i class="fas fa-paper-plane mr-2" style="color:#1a3fc4;"></i>SMTP Settings (used to send emails as this company)</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Host</label>
                <input type="text" name="company[<?php echo $cid; ?>][smtp_host]" class="fc smtp-host" value="<?php echo htmlspecialchars($co['smtp_host'] ?? ''); ?>" placeholder="mail.example.com">
            </div>
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Port</label>
                <input type="number" name="company[<?php echo $cid; ?>][smtp_port]" class="fc smtp-port" value="<?php echo htmlspecialchars($co['smtp_port'] ?? '465'); ?>" placeholder="465">
            </div>
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Encryption</label>
                <select name="company[<?php echo $cid; ?>][smtp_secure]" class="fc smtp-secure">
                    <option value="ssl" <?php echo (($co['smtp_secure'] ?? '') === 'ssl') ? 'selected' : ''; ?>>SSL</option>
                    <option value="tls" <?php echo (($co['smtp_secure'] ?? 'tls') === 'tls') ? 'selected' : ''; ?>>TLS</option>
                </select>
            </div>
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP From Name</label>
                <input type="text" name="company[<?php echo $cid; ?>][smtp_from_name]" class="fc smtp-from-name" value="<?php echo htmlspecialchars($co['smtp_from_name'] ?? ''); ?>" placeholder="<?php echo htmlspecialchars($co['company_name'] ?? 'Company'); ?> HR">
            </div>
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Username / Email</label>
                <input type="text" name="company[<?php echo $cid; ?>][smtp_username]" class="fc smtp-username" value="<?php echo htmlspecialchars($co['smtp_username'] ?? ''); ?>" placeholder="support@example.com">
            </div>
            <div>
                <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Password</label>
                <div style="position:relative;">
                    <input type="password" name="company[<?php echo $cid; ?>][smtp_password]" class="fc smtp-password" style="padding-right:38px;" placeholder="<?php echo !empty($co['smtp_password_enc'] ?? '') ? '(unchanged — leave blank to keep current)' : 'Enter password'; ?>" autocomplete="new-password">
                    <button type="button" class="smtp-pass-toggle" style="position:absolute;right:8px;top:50%;transform:translateY(-50%);border:none;background:none;color:#94a3b8;cursor:pointer;padding:4px;"><i class="fas fa-eye"></i></button>
                </div>
            </div>
        </div>
        <div style="display:flex;align-items:center;gap:10px;margin-top:14px;flex-wrap:wrap;">
            <input type="text" class="fc smtp-test-to" style="max-width:260px;" placeholder="Send test to (email)" value="<?php echo htmlspecialchars($co['company_email'] ?? ''); ?>">
            <button type="button" class="btn-test-smtp" data-row-id="<?php echo $cid; ?>" style="padding:9px 18px;border:none;border-radius:8px;background:#eef2ff;color:#1a3fc4;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-vial mr-1"></i>Test SMTP</button>
            <span class="smtp-test-result" style="font-size:12px;font-weight:600;"></span>
        </div>
    </div>
</div>
<?php endforeach; ?>
</div>

<!-- New company placeholder (hidden, cloned by JS) -->
<div id="newCompanyTemplate" style="display:none;">
<div class="company-settings-row" style="background:#fff;border:2px dashed #c7d2fe;border-radius:14px;padding:24px;margin-bottom:20px;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:18px;">
        <div style="font-weight:800;font-size:13px;text-transform:uppercase;color:#0f2557;letter-spacing:.5px;"><i class="fas fa-building mr-2" style="color:#6366f1;"></i>New Company</div>
        <button type="button" onclick="this.closest('.company-settings-row').remove()" style="padding:6px 14px;border:none;border-radius:7px;background:#fee2e2;color:#991b1b;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-times mr-1"></i>Cancel</button>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Name</label>
<select name="company[0][company_id]" class="fc" onchange="this.form.querySelector('input[name=\'company[0][company_name]\']').value = this.options[this.selectedIndex].text;">
    <option value="">Select Company...</option>
    <?php foreach ($master_companies as $mc): ?>
    <option value="<?php echo $mc['id']; ?>"><?php echo htmlspecialchars($mc['company_name']); ?></option>
    <?php endforeach; ?>
</select>
<input type="hidden" name="company[0][company_name]" value="">
</div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Email</label><input type="email" name="company[0][company_email]" class="fc"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Phone</label><input type="text" name="company[0][company_phone]" class="fc"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Website</label><input type="text" name="company[0][company_website]" class="fc" placeholder="e.g. www.example.com"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Authorized Signatory Name</label><input type="text" name="company[0][signatory_name]" class="fc"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Signatory Designation</label><input type="text" name="company[0][signatory_designation]" class="fc"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Address</label><textarea name="company[0][company_address]" class="fc" style="height:70px;resize:vertical;"></textarea></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Logo</label><input type="file" name="company[0][logo]" accept="image/*" style="font-size:13px;"></div>
        <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Company Signature Image</label><input type="file" name="company[0][signature]" accept="image/*" style="font-size:13px;"></div>
    </div>

    <div style="margin-top:20px;padding-top:18px;border-top:1px dashed #e0e7ff;">
        <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#0f2557;letter-spacing:.5px;margin-bottom:14px;"><i class="fas fa-paper-plane mr-2" style="color:#1a3fc4;"></i>SMTP Settings (used to send emails as this company)</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Host</label><input type="text" name="company[0][smtp_host]" class="fc smtp-host" placeholder="mail.example.com"></div>
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Port</label><input type="number" name="company[0][smtp_port]" class="fc smtp-port" value="465" placeholder="465"></div>
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">Encryption</label>
                <select name="company[0][smtp_secure]" class="fc smtp-secure">
                    <option value="ssl" selected>SSL</option>
                    <option value="tls">TLS</option>
                </select>
            </div>
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP From Name</label><input type="text" name="company[0][smtp_from_name]" class="fc smtp-from-name" placeholder="Company HR"></div>
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Username / Email</label><input type="text" name="company[0][smtp_username]" class="fc smtp-username" placeholder="support@example.com"></div>
            <div><label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:5px;">SMTP Password</label>
                <div style="position:relative;">
                    <input type="password" name="company[0][smtp_password]" class="fc smtp-password" style="padding-right:38px;" placeholder="Enter password" autocomplete="new-password">
                    <button type="button" class="smtp-pass-toggle" style="position:absolute;right:8px;top:50%;transform:translateY(-50%);border:none;background:none;color:#94a3b8;cursor:pointer;padding:4px;"><i class="fas fa-eye"></i></button>
                </div>
            </div>
        </div>
        <div style="display:flex;align-items:center;gap:10px;margin-top:14px;flex-wrap:wrap;">
            <input type="text" class="fc smtp-test-to" style="max-width:260px;" placeholder="Send test to (email)">
            <button type="button" class="btn-test-smtp" data-row-id="0" style="padding:9px 18px;border:none;border-radius:8px;background:#eef2ff;color:#1a3fc4;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-vial mr-1"></i>Test SMTP</button>
            <span class="smtp-test-result" style="font-size:12px;font-weight:600;"></span>
        </div>
    </div>
</div>
</div>

<div style="display:flex;gap:12px;margin-bottom:20px;">
    <button type="button" onclick="addNewCompany()" style="padding:11px 22px;border:2px dashed #6366f1;border-radius:10px;background:#f5f3ff;color:#4f46e5;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-plus mr-2"></i>Add Company</button>
    <button type="submit" style="padding:11px 28px;border:none;border-radius:10px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-save mr-2"></i>Save All Companies</button>
    <?php if ($candidate_id): ?>
      <a href="hr-employee-offer.php?candidate_id=<?php echo $candidate_id; ?>" class="btn-p btn-light" style="padding:11px 22px;border-radius:10px;text-decoration:none;"><i class="fas fa-arrow-left"></i> Back to Offer</a>
    <?php endif; ?>
</div>
</form>

<?php foreach ($companies as $co): $cid = intval($co['id']); if($cid > 0): ?>
<form method="POST" id="delForm_<?php echo $cid; ?>" style="display:none;"><input type="hidden" name="delete_company_id" value="<?php echo $cid; ?>"></form>
<?php endif; endforeach; ?>

<script>
var newCompanyCounter = 0;
function addNewCompany() {
    newCompanyCounter--; // Use negative IDs for new companies so PHP processes them as new
    var template = document.getElementById('newCompanyTemplate').innerHTML;
    template = template.replace(/\[0\]/g, '[' + newCompanyCounter + ']');
    var wrapper = document.getElementById('companiesWrapper');
    var div = document.createElement('div');
    div.innerHTML = template;
    wrapper.appendChild(div.firstElementChild);
}

document.addEventListener('click', function(e) {
    var toggleBtn = e.target.closest('.smtp-pass-toggle');
    if (toggleBtn) {
        var input = toggleBtn.previousElementSibling;
        var icon = toggleBtn.querySelector('i');
        if (input.type === 'password') {
            input.type = 'text';
            icon.className = 'fas fa-eye-slash';
        } else {
            input.type = 'password';
            icon.className = 'fas fa-eye';
        }
        return;
    }
    var btn = e.target.closest('.btn-test-smtp');
    if (!btn) return;
    var row = btn.closest('.company-settings-row');
    var resultEl = row.querySelector('.smtp-test-result');
    var payload = {
        ajax_test_smtp: 1,
        company_row_id: btn.getAttribute('data-row-id') || 0,
        smtp_host: row.querySelector('.smtp-host').value,
        smtp_port: row.querySelector('.smtp-port').value,
        smtp_secure: row.querySelector('.smtp-secure').value,
        smtp_username: row.querySelector('.smtp-username').value,
        smtp_password: row.querySelector('.smtp-password').value,
        smtp_from_name: row.querySelector('.smtp-from-name').value,
        smtp_test_to: row.querySelector('.smtp-test-to').value
    };
    resultEl.style.color = '#0f2557';
    resultEl.textContent = 'Sending test email…';
    btn.disabled = true;
    fetch(window.location.pathname + window.location.search, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams(payload).toString()
    }).then(function(r) { return r.json(); }).then(function(data) {
        resultEl.style.color = data.success ? '#15803d' : '#b91c1c';
        resultEl.textContent = (data.success ? '✓ ' : '✗ ') + data.message;
    }).catch(function() {
        resultEl.style.color = '#b91c1c';
        resultEl.textContent = '✗ Test request failed — check your connection.';
    }).finally(function() {
        btn.disabled = false;
    });
});
</script>

<?php elseif ($page === 'revise'): ?>
<!-- ==================== REVISED OFFER LETTER PAGE ==================== -->
<?php
$employee_id = intval($_GET['employee_id'] ?? 0);
$rev_employee = getEmployeeForRevision($con, $employee_id);
?>
<?php if (!$rev_employee): ?>
<div class="card-s"><div class="alert-err"><i class="fas fa-exclamation-circle"></i> Employee not found. Go back and pick an employee to generate a revised offer for.</div></div>
<?php else: ?>
<?php
$rev_latest = getLatestLetterForEmployee($con, $employee_id);
// Always look up the original candidate offer (by name match) so its terms/roles are
// available for the "Reset to Original" button — not just as a one-time prefill when
// no draft exists, since an already-saved draft would otherwise never offer this.
$rev_original = findOriginalOfferForEmployee($con, $rev_employee['name']);
// Prefer the verified original candidate offer's terms/roles over whatever a prior
// revision happened to have saved — the original is the trustworthy source of truth,
// so drafts always start from the same wording as the normal offer letter unless HR
// deliberately edits them.
$rev_prefill_terms = ($rev_original['terms_conditions'] ?? null) ?: ($rev_latest['terms_conditions'] ?? null);
$rev_prefill_roles = ($rev_original['roles_responsibilities'] ?? '') ?: ($rev_latest['roles_responsibilities'] ?? '');
$rev_cs = getCompanySettingsForEmployee($con, $employee_id);
$rev_next_number = $rev_latest ? (intval($rev_latest['revision_number']) + 1) : 1;
$rev_prev_ctc = $rev_latest ? $rev_latest['offered_ctc'] : ($rev_original['offered_ctc'] ?? ('₹' . number_format(floatval($rev_employee['payroll_total_ctc'] ?? $rev_employee['salary'] ?? 0), 2) . ' per month'));
$rev_prev_pos = $rev_latest ? $rev_latest['position'] : $rev_employee['position'];
// Salary structure prefill — an existing draft's saved figures win; otherwise start
// from the employee's latest payroll record (hr_payroll, joined in getEmployeeForRevision)
// as a head start, same idea as how CTC/position already prefill from prior data above.
$rev_sal_basic      = $rev_latest['salary_basic'] ?? $rev_employee['basic_salary'] ?? '';
$rev_sal_hra         = $rev_latest['salary_hra'] ?? $rev_employee['hra'] ?? '';
$rev_sal_special     = $rev_latest['salary_special_allowance'] ?? $rev_employee['special_allowance'] ?? '';
$rev_sal_conveyance  = $rev_latest['salary_conveyance'] ?? $rev_employee['conveyance'] ?? '';
$rev_sal_other       = $rev_latest['salary_other_allowances'] ?? '';
$rev_sal_deductions  = $rev_latest['salary_deductions'] ?? '';
$rev_sal_gross       = $rev_latest['salary_gross'] ?? $rev_employee['gross_pay'] ?? '';
$rev_sal_net         = $rev_latest['salary_net'] ?? '';
$rev_sal_custom      = !empty($rev_latest['salary_custom_rows']) ? (json_decode($rev_latest['salary_custom_rows'], true) ?: []) : [];
$rev_sal_period      = ($rev_latest['salary_period'] ?? 'month') === 'annum' ? 'annum' : 'month';
// Employee contact details for the letter — an existing draft's saved values win
// (HR may have corrected them); otherwise pulled from hr_employees as a starting point.
// Uses !empty() rather than ?? — older drafts saved these columns as '' (before this
// field existed on the form), and '' ?? $fallback still returns '' since '' isn't null.
$rev_emp_code = !empty($rev_latest['candidate_employee_code']) ? $rev_latest['candidate_employee_code'] : ($rev_employee['employee_id'] ?? '');
$rev_phone    = !empty($rev_latest['candidate_phone']) ? $rev_latest['candidate_phone'] : ($rev_employee['phone'] ?? $rev_employee['mobile'] ?? '');
$rev_email    = !empty($rev_latest['candidate_email']) ? $rev_latest['candidate_email'] : ($rev_employee['email'] ?? $rev_employee['personal_email'] ?? '');
$rev_address  = !empty($rev_latest['candidate_address']) ? $rev_latest['candidate_address'] : ($rev_employee['address'] ?? '');
$rev_standard_terms = "1. Working Hours: As per the company's standard working schedule or as communicated by the management.\n2. Leave Entitlement: You will be entitled to leave as per the company's policy.\n3. Termination\nNotice Period: After confirmation, either party may terminate the employment by giving 60 (sixty) days' written notice or salary in lieu of notice.\nImmediate Termination: The company reserves the right to terminate employment without notice in cases of misconduct, breach of confidentiality, or violation of company policies.\nCompany Liability: If the employee completes the full notice period as instructed by the management, the company will release the pending salary along with the notice period salary (if applicable) as per company policy.\nIf an employee is found absconding by leaving employment without prior notice, approval, or completion of required exit formalities, the employee shall not be eligible for salary payment for the service period under absconding status, subject to company policy and applicable laws.\nConfidentiality: You must maintain the confidentiality of all company information and shall not disclose any data or records to any unauthorized person during or after your employment.\n4. Code of Conduct: You are required to adhere to all company rules, regulations, and policies in force and as amended from time to time.\n5. Verification: This offer is subject to successful verification of your credentials, background, and documents.";
?>

<?php if (empty($rev_cs)): ?>
<div style="background:#fff3cd;color:#856404;padding:15px;text-align:center;border:1px solid #ffeeba;border-radius:8px;margin-bottom:20px;"><strong>Warning:</strong> Company branding is not configured for this employee's company. Please set up Company Settings before sending this revised offer.</div>
<?php endif; ?>

<div class="no-print" style="display:flex;justify-content:space-between;align-items:center;background:var(--card);border:1px solid var(--border);border-radius:12px;padding:16px 22px;margin-bottom:18px;">
  <div style="display:flex;align-items:center;gap:14px;">
    <div style="width:46px;height:46px;background:linear-gradient(135deg,var(--navy),var(--blue));border-radius:12px;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:18px;"><?php echo strtoupper(substr($rev_employee['name'],0,1)); ?></div>
    <div>
      <div style="font-weight:800;color:var(--navy);font-size:15px;"><?php echo htmlspecialchars($rev_employee['name']); ?></div>
      <div style="font-size:12px;color:var(--muted);"><?php echo htmlspecialchars($rev_employee['position']); ?> &middot; <?php echo htmlspecialchars($rev_employee['department']); ?> &middot; <?php echo htmlspecialchars($rev_employee['company_name']); ?></div>
    </div>
  </div>
  <div style="display:flex;align-items:center;gap:12px;">
    <?php if ($rev_latest): ?>
      <div style="font-size:12px;font-weight:700;color:var(--muted);">Offer: <strong><?php echo htmlspecialchars($rev_latest['offer_number']); ?></strong></div>
      <?php
        $rev_sc_map = ['draft'=>'s-draft','ready'=>'s-ready','sent'=>'s-sent','accepted'=>'s-accepted','declined'=>'s-declined'];
        $rev_sc_cls = $rev_sc_map[$rev_latest['status']] ?? 's-draft';
      ?>
      <span class="status-badge <?php echo $rev_sc_cls; ?>"><?php echo ucfirst($rev_latest['status']); ?></span>
      <?php if (!empty($rev_latest['sent_at'])): ?>
      <span style="font-size:11px;font-weight:700;color:#065f46;background:#dcfce7;border:1px solid #86efac;border-radius:20px;padding:5px 12px;display:inline-flex;align-items:center;gap:5px;" title="Revised offer letter sent on <?php echo date('d M Y, h:i A', strtotime($rev_latest['sent_at'])); ?>"><i class="fas fa-check-circle"></i> Sent <?php echo date('d M Y, h:i A', strtotime($rev_latest['sent_at'])); ?></span>
      <?php endif; ?>
    <?php endif; ?>
    <div style="font-size:12px;font-weight:700;color:var(--muted);">Next: <strong style="color:var(--navy);">Revision <?php echo $rev_next_number; ?></strong></div>
  </div>
</div>

<div class="tab-bar no-print">
  <button class="tab-btn active" id="rtab-form" onclick="switchRevTab('form')"><i class="fas fa-edit"></i> Revision Details</button>
  <button class="tab-btn" id="rtab-preview" onclick="switchRevTab('preview')"><i class="fas fa-eye"></i> Preview PDF</button>
  <button class="tab-btn" id="rtab-send" onclick="switchRevTab('send')"><i class="fas fa-paper-plane"></i> Send</button>
  <?php if ($rev_latest && $rev_latest['status'] === 'accepted'): ?>
  <button class="tab-btn" id="rtab-signed" onclick="switchRevTab('signed')"><i class="fas fa-signature"></i> Signed Copy</button>
  <?php endif; ?>
</div>

<!-- TAB: FORM -->
<div id="rpane-form" class="rev-tab-pane">
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-file-alt"></i> Revision Details</div>
  <div id="revFormAlert"></div>

  <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px 18px;margin-bottom:18px;">
    <div style="font-size:11px;font-weight:800;color:#64748b;text-transform:uppercase;margin-bottom:8px;">Previous / Current (Reference)</div>
    <div class="grid2">
        <div><span style="font-size:12px;color:#64748b;">Designation</span><div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($rev_prev_pos); ?></div></div>
        <div>
            <label class="fl" style="font-size:12px;color:#64748b;margin-bottom:4px;">CTC / Salary <span style="font-weight:400;">(auto-fetched — edit freely if incorrect)</span></label>
            <input type="text" id="rf_prev_ctc" class="fc" placeholder="e.g. ₹50,000 per month" value="<?php echo htmlspecialchars($rev_prev_ctc); ?>">
        </div>
    </div>
  </div>

  <div class="fg">
    <label class="fl">Employee Contact Details <span style="font-weight:400;">(auto-fetched from Employee Management — edit freely if needed)</span></label>
    <div class="grid3">
        <div class="fg"><label class="fl" style="font-size:12px;color:#64748b;">Employee ID</label><input type="text" id="rf_emp_code" class="fc" value="<?php echo htmlspecialchars($rev_emp_code); ?>"></div>
        <div class="fg"><label class="fl" style="font-size:12px;color:#64748b;">Phone</label><input type="text" id="rf_phone" class="fc" value="<?php echo htmlspecialchars($rev_phone); ?>"></div>
        <div class="fg"><label class="fl" style="font-size:12px;color:#64748b;">Email</label><input type="email" id="rf_email" class="fc" value="<?php echo htmlspecialchars($rev_email); ?>"></div>
    </div>
    <div class="fg"><label class="fl" style="font-size:12px;color:#64748b;">Address</label><textarea id="rf_address" class="fc" style="height:60px;"><?php echo htmlspecialchars($rev_address); ?></textarea></div>
  </div>

  <div class="grid3">
    <div class="fg"><label class="fl">Revised Designation *</label><input type="text" id="rf_position" class="fc" value="<?php echo htmlspecialchars($rev_latest['position'] ?? $rev_employee['position']); ?>"></div>
    <div class="fg"><label class="fl">Department</label><input type="text" id="rf_department" class="fc" value="<?php echo htmlspecialchars($rev_latest['department'] ?? $rev_employee['department']); ?>"></div>
    <div class="fg"><label class="fl">Effective Date *</label><input type="date" id="rf_effective" class="fc" value="<?php echo !empty($rev_latest['revision_effective_date']) ? date('Y-m-d', strtotime($rev_latest['revision_effective_date'])) : ''; ?>"></div>
  </div>

  <div class="fg">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">
        <label class="fl" style="margin-bottom:0;">Salary Structure *</label>
        <div style="display:flex;align-items:center;gap:8px;">
            <label class="fl" style="margin-bottom:0;font-weight:400;">Pay Frequency</label>
            <select id="rf_sal_period" class="fc" style="width:auto;padding:6px 10px;" onchange="onRevSalaryPeriodChange()">
                <option value="month" <?php echo $rev_sal_period === 'month' ? 'selected' : ''; ?>>Monthly</option>
                <option value="annum" <?php echo $rev_sal_period === 'annum' ? 'selected' : ''; ?>>Annually</option>
            </select>
        </div>
    </div>
    <table id="rf_salary_table" style="width:100%;border-collapse:collapse;margin-top:6px;">
      <thead>
        <tr style="background:#f8fafc;">
          <th style="text-align:left;padding:8px 20px;font-size:12px;color:#64748b;border:1px solid #94a3b8;">Component</th>
          <th id="rf_sal_amount_header" style="text-align:left;padding:8px 20px;font-size:12px;color:#64748b;border:1px solid #94a3b8;width:220px;">Amount (₹ / <?php echo $rev_sal_period === 'annum' ? 'annum' : 'month'; ?>)</th>
        </tr>
      </thead>
      <tbody>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Basic Salary *</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_basic" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_basic); ?>"></td></tr>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">House Rent Allowance (HRA)</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_hra" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_hra); ?>"></td></tr>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Special Allowance</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_special" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_special); ?>"></td></tr>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Conveyance Allowance (if applicable)</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_conveyance" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_conveyance); ?>"></td></tr>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Other Allowances</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_other" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_other); ?>"></td></tr>
      </tbody>
      <tbody id="rf_sal_custom_rows_body">
        <?php foreach ($rev_sal_custom as $rev_cr): ?>
        <tr class="rf-sal-custom-row">
          <td style="padding:4px;border:1px solid #94a3b8;"><input type="text" class="fc rf-sal-custom-label" placeholder="e.g. Bonus" value="<?php echo htmlspecialchars($rev_cr['label'] ?? ''); ?>"></td>
          <td style="padding:4px;border:1px solid #94a3b8;display:flex;gap:6px;align-items:center;"><input type="number" step="0.01" min="0" class="fc rf-sal-custom-amount" style="flex:1;" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_cr['amount'] ?? ''); ?>"><button type="button" onclick="removeRevSalaryRow(this)" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:28px;height:28px;cursor:pointer;font-weight:800;">&times;</button></td>
        </tr>
        <?php endforeach; ?>
      </tbody>
      <tbody>
        <tr style="background:#f8fafc;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Gross Salary</strong></td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_gross" class="fc" value="<?php echo htmlspecialchars($rev_sal_gross); ?>"></td></tr>
        <tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Deductions (if applicable)</td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_deductions" class="fc" oninput="recalcRevSalary()" value="<?php echo htmlspecialchars($rev_sal_deductions); ?>"></td></tr>
        <tr style="background:#f0fdf4;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Net Salary</strong></td><td style="padding:4px;border:1px solid #94a3b8;"><input type="number" step="0.01" min="0" id="rf_sal_net" class="fc" value="<?php echo htmlspecialchars($rev_sal_net); ?>"></td></tr>
      </tbody>
    </table>
    <div style="margin-top:8px;"><button type="button" onclick="addRevSalaryRow()" class="btn-p btn-light" style="padding:6px 14px;font-size:12px;"><i class="fas fa-plus"></i> Add Row</button></div>
    <div style="font-size:11px;color:#64748b;margin-top:6px;">Gross and Net Salary auto-calculate from the fields above (including any added rows) — you can still edit them directly if needed.</div>
  </div>

  <div class="fg">
    <label class="fl">Revised CTC / Salary (as shown on the letter)</label>
    <input type="text" id="rf_ctc_text" class="fc" placeholder="e.g. ₹25,000 per month" value="<?php echo htmlspecialchars($rev_latest['offered_ctc'] ?? ''); ?>">
    <div style="font-size:11px;color:#64748b;margin-top:4px;">Auto-fills from Net Salary above — edit freely for different wording or a per-annum figure.</div>
  </div>

  <div class="grid3">
    <div class="fg"><label class="fl">Work Location</label><input type="text" id="rf_location" class="fc" value="<?php echo htmlspecialchars($rev_latest['work_location'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Reporting Manager</label><input type="text" id="rf_manager" class="fc" value="<?php echo htmlspecialchars($rev_latest['reporting_manager'] ?? ''); ?>"></div>
    <div class="fg"></div>
  </div>
  <div class="grid3">
    <div class="fg"><label class="fl">Working Hours / Shift</label><input type="text" id="rf_hours" class="fc" value="<?php echo htmlspecialchars($rev_latest['working_hours'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Notice Period</label><input type="text" id="rf_notice" class="fc" value="<?php echo htmlspecialchars($rev_latest['notice_period'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Offer Validity (Date &amp; Time)</label><input type="datetime-local" id="rf_validity" class="fc" value="<?php echo !empty($rev_latest['offer_validity']) ? date('Y-m-d\TH:i', strtotime($rev_latest['offer_validity'])) : ''; ?>"></div>
  </div>
  <div class="fg"><label class="fl">Reason for Revision</label><input type="text" id="rf_reason" class="fc" placeholder="e.g. Annual performance increment / Promotion" value="<?php echo htmlspecialchars($rev_latest['revision_reason'] ?? ''); ?>"></div>
  <div class="fg">
    <div style="display:flex;justify-content:space-between;align-items:center;">
        <label class="fl" style="margin-bottom:0;">Roles &amp; Responsibilities</label>
        <?php if (!empty($rev_original['roles_responsibilities'])): ?><button type="button" onclick="resetRolesToOriginal()" class="btn-p btn-light" style="padding:4px 12px;font-size:11px;"><i class="fas fa-undo"></i> Reset to Original Offer's Roles</button><?php endif; ?>
    </div>
    <textarea id="rf_roles" class="fc" style="height:120px;white-space:pre-wrap;margin-top:6px;" placeholder="e.g.&#10;- Lead the backend engineering team&#10;- Own architecture decisions&#10;(Edit as needed...)"><?php echo htmlspecialchars($rev_prefill_roles); ?></textarea>
  </div>
  <div class="fg">
    <div style="display:flex;justify-content:space-between;align-items:center;">
        <label class="fl" style="margin-bottom:0;">Terms &amp; Conditions</label>
        <div style="display:flex;gap:6px;">
            <?php if (!empty($rev_original['terms_conditions'])): ?><button type="button" onclick="resetTermsToOriginal()" class="btn-p btn-light" style="padding:4px 12px;font-size:11px;"><i class="fas fa-undo"></i> Reset to Original Offer's Terms</button><?php endif; ?>
            <button type="button" onclick="resetTermsToStandard()" class="btn-p btn-light" style="padding:4px 12px;font-size:11px;"><i class="fas fa-file-alt"></i> Reset to Standard Terms</button>
        </div>
    </div>
    <textarea id="rf_terms" class="fc" style="height:220px;white-space:pre-wrap;margin-top:6px;"><?php echo htmlspecialchars($rev_prefill_terms ?? $rev_standard_terms); ?></textarea>
  </div>

  <div style="display:flex;gap:10px;margin-top:20px;flex-wrap:wrap;">
    <button type="button" onclick="saveRevision(1)" class="btn-p btn-light"><i class="fas fa-save"></i> Save Draft</button>
    <button type="button" onclick="saveRevision(0)" class="btn-p btn-navy"><i class="fas fa-check"></i> Save &amp; Mark Ready</button>
    <button type="button" onclick="saveRevision(0, true)" class="btn-p btn-warn"><i class="fas fa-eye"></i> Save &amp; Preview</button>
  </div>
</div>
</div>

<!-- TAB: PREVIEW -->
<div id="rpane-preview" class="rev-tab-pane" style="display:none;">
<div class="card-s">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
    <div class="sec-lbl" style="margin:0;border:none;"><i class="fas fa-eye"></i> Revised Offer Letter Preview</div>
    <div style="display:flex;gap:8px;">
      <button onclick="openRevDownload()" class="btn-p btn-light no-print"><i class="fas fa-print"></i> Print / Save PDF</button>
      <button onclick="switchRevTab('send')" class="btn-p btn-navy no-print"><i class="fas fa-paper-plane"></i> Proceed to Send</button>
    </div>
  </div>
  <div class="pdf-preview" id="revPdfPreviewBox"></div>
</div>
</div>

<!-- TAB: SEND -->
<div id="rpane-send" class="rev-tab-pane" style="display:none;">
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-paper-plane"></i> Send Revised Offer</div>
  <div id="revSendBody">
    <div class="alert-err"><i class="fas fa-exclamation-circle"></i> Please save the revision first before sending.</div>
  </div>
</div>
</div>

<!-- TAB: SIGNED COPY -->
<?php if ($rev_latest && $rev_latest['status'] === 'accepted'): ?>
<div id="rpane-signed" class="rev-tab-pane" style="display:none;">
<div class="card-s">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
    <div class="sec-lbl" style="margin:0;border:none;"><i class="fas fa-signature"></i> Signed Revised Offer Letter</div>
    <button onclick="openRevDownload()" class="btn-p btn-navy no-print"><i class="fas fa-download"></i> Download Signed PDF</button>
  </div>
  <div class="alert-ok"><i class="fas fa-check-circle"></i> Employee accepted on <?php echo !empty($rev_latest['candidate_action_at']) ? date('d M Y, h:i A', strtotime($rev_latest['candidate_action_at'])) : '-'; ?></div>

  <div id="revApprovalBox" style="margin-top:16px;">
  <?php if (!empty($rev_latest['hr_approved_at'])): ?>
    <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:16px;margin-bottom:14px;">
      <div style="font-weight:800;color:#0369a1;margin-bottom:4px;"><i class="fas fa-check-double mr-2"></i>Approved by <?php echo htmlspecialchars($rev_latest['hr_approved_by'] ?? 'HR'); ?> on <?php echo date('d M Y, h:i A', strtotime($rev_latest['hr_approved_at'])); ?></div>
      <div style="font-size:13px;color:#334155;">This revision has been filed into <?php echo htmlspecialchars($rev_employee['name']); ?>'s employee documents.</div>
    </div>
    <div style="background:#fff7ed;border:2px solid #fdba74;border-radius:10px;padding:16px;">
      <div style="font-weight:800;color:#9a3412;margin-bottom:6px;"><i class="fas fa-bell mr-2"></i>Reminder</div>
      <p style="font-size:13.5px;color:#7c2d12;margin:0;">Please go to <strong>Employee Management</strong> and update <?php echo htmlspecialchars($rev_employee['name']); ?>'s salary to <strong><?php echo htmlspecialchars($rev_latest['offered_ctc']); ?></strong> — this system doesn't update payroll automatically.</p>
    </div>
  <?php else: ?>
    <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:10px;padding:16px;">
      <div style="font-weight:800;color:#92400e;margin-bottom:6px;"><i class="fas fa-hourglass-half mr-2"></i>Awaiting HR Approval</div>
      <p style="font-size:13px;color:#78350f;margin-bottom:12px;">The employee has accepted this revision, but it hasn't been filed into their documents yet — review it and approve to finalize.</p>
      <button type="button" onclick="approveRevision(<?php echo intval($rev_latest['id']); ?>)" class="btn-p btn-navy"><i class="fas fa-check"></i> Approve &amp; File</button>
    </div>
  <?php endif; ?>
  </div>
</div>
</div>
<?php endif; ?>

<script>
var REV_EMPLOYEE_ID = <?php echo intval($employee_id); ?>;
// Re-hydrate from the DB on every page load (not just right after a Save in this
// session) — otherwise refreshing the page loses track of an already-saved/sent
// revision and wrongly claims nothing has been saved yet.
var revOfferData = <?php echo $rev_latest ? json_encode($rev_latest) : 'null'; ?>;
var revCompanyData = <?php echo $rev_cs ? json_encode($rev_cs) : '{}'; ?>;
var REV_PREV_POS = <?php echo json_encode($rev_prev_pos); ?>;
var REV_EMP_NAME = <?php echo json_encode($rev_employee['name']); ?>;
var REV_ORIGINAL_TERMS = <?php echo json_encode($rev_original['terms_conditions'] ?? ''); ?>;
var REV_ORIGINAL_ROLES = <?php echo json_encode($rev_original['roles_responsibilities'] ?? ''); ?>;
var REV_STANDARD_TERMS = <?php echo json_encode($rev_standard_terms); ?>;
function resetTermsToOriginal() { document.getElementById('rf_terms').value = REV_ORIGINAL_TERMS; }
function resetRolesToOriginal() { document.getElementById('rf_roles').value = REV_ORIGINAL_ROLES; }
function resetTermsToStandard() { document.getElementById('rf_terms').value = REV_STANDARD_TERMS; }

// Gross/Net auto-calculate from the components, but stay plain editable inputs —
// touching any component recomputes both, so a manual Gross/Net edit only "sticks"
// until the next component change (deliberately simple, no dirty-flag tracking).
// The "as shown on letter" text field is different: HR may deliberately rewrite it
// (different wording, per-annum instead of per-month), so once they've typed into it
// directly we stop overwriting it on every component change.
var revCtcTextDirty = false;
document.getElementById('rf_ctc_text').addEventListener('input', function() { revCtcTextDirty = true; });

function recalcRevSalary() {
    function num(id) { var v = parseFloat(document.getElementById(id).value); return isNaN(v) ? 0 : v; }
    var customTotal = 0;
    document.querySelectorAll('#rf_sal_custom_rows_body .rf-sal-custom-amount').forEach(function(inp) {
        var v = parseFloat(inp.value); if (!isNaN(v)) customTotal += v;
    });
    var gross = num('rf_sal_basic') + num('rf_sal_hra') + num('rf_sal_special') + num('rf_sal_conveyance') + num('rf_sal_other') + customTotal;
    document.getElementById('rf_sal_gross').value = gross.toFixed(2);
    var net = gross - num('rf_sal_deductions');
    document.getElementById('rf_sal_net').value = net.toFixed(2);
    if (!revCtcTextDirty) {
        var period = document.getElementById('rf_sal_period').value === 'annum' ? 'annum' : 'month';
        document.getElementById('rf_ctc_text').value = '₹' + net.toFixed(2).replace(/\d(?=(\d{3})+\.)/g, '$&,') + ' per ' + period;
    }
}

// Pay Frequency just relabels the same figures (Monthly vs Annually) — HR still
// enters whatever numbers apply to the period they picked, nothing is converted.
function onRevSalaryPeriodChange() {
    var period = document.getElementById('rf_sal_period').value === 'annum' ? 'annum' : 'month';
    document.getElementById('rf_sal_amount_header').textContent = 'Amount (₹ / ' + period + ')';
    revCtcTextDirty = false;
    recalcRevSalary();
}

// HR can add arbitrary extra salary components (e.g. "Bonus", "Fuel Allowance")
// beyond the fixed list — each row is a free label + amount, folded into the
// Gross/Net calculation above like any other component.
function addRevSalaryRow() {
    var tbody = document.getElementById('rf_sal_custom_rows_body');
    var tr = document.createElement('tr');
    tr.className = 'rf-sal-custom-row';
    tr.innerHTML = '<td style="padding:4px;border:1px solid #94a3b8;"><input type="text" class="fc rf-sal-custom-label" placeholder="e.g. Bonus"></td>' +
        '<td style="padding:4px;border:1px solid #94a3b8;display:flex;gap:6px;align-items:center;"><input type="number" step="0.01" min="0" class="fc rf-sal-custom-amount" style="flex:1;" oninput="recalcRevSalary()" value="0"><button type="button" onclick="removeRevSalaryRow(this)" style="background:#fee2e2;color:#b91c1c;border:none;border-radius:6px;width:28px;height:28px;cursor:pointer;font-weight:800;">&times;</button></td>';
    tbody.appendChild(tr);
}
function removeRevSalaryRow(btn) {
    btn.closest('tr').remove();
    recalcRevSalary();
}
if (!document.getElementById('rf_sal_gross').value || !document.getElementById('rf_sal_net').value) { recalcRevSalary(); }
if (revOfferData) { renderRevSendPane(); }

function switchRevTab(name) {
    document.querySelectorAll('.rev-tab-pane').forEach(function(p){ p.style.display='none'; });
    document.querySelectorAll('.tab-bar.no-print .tab-btn').forEach(function(b){ b.classList.remove('active'); });
    var pane = document.getElementById('rpane-' + name);
    var btn = document.getElementById('rtab-' + name);
    if (pane) pane.style.display = 'block';
    if (btn) btn.classList.add('active');
    if (name === 'preview') renderRevPreview();
}

function approveRevision(offerId) {
    if (!confirm('Approve this revision? It will be filed into the employee\'s documents.')) return;
    $.post(window.location.pathname, { ajax_approve_revision: 1, offer_id: offerId }, function(resp) {
        if (!resp.success) { alert(resp.message || 'Could not approve.'); return; }
        var box = document.getElementById('revApprovalBox');
        box.innerHTML =
            '<div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:16px;margin-bottom:14px;">' +
            '<div style="font-weight:800;color:#0369a1;margin-bottom:4px;"><i class="fas fa-check-double mr-2"></i>Approved by ' + resp.approved_by + '</div>' +
            '<div style="font-size:13px;color:#334155;">This revision has been filed into ' + resp.employee_name + '\'s employee documents.</div>' +
            '</div>' +
            '<div style="background:#fff7ed;border:2px solid #fdba74;border-radius:10px;padding:16px;">' +
            '<div style="font-weight:800;color:#9a3412;margin-bottom:6px;"><i class="fas fa-bell mr-2"></i>Reminder</div>' +
            '<p style="font-size:13.5px;color:#7c2d12;margin:0;">Please go to <strong>Employee Management</strong> and update ' + resp.employee_name + '\'s salary to <strong>' + resp.offered_ctc + '</strong> — this system doesn\'t update payroll automatically.</p>' +
            '</div>';
        showToast('Revision approved and filed!');
    }, 'json').fail(function(){ alert('Server error while approving.'); });
}

function saveRevision(isDraft, goToPreview) {
    var alertBox = document.getElementById('revFormAlert');
    var salBasic = document.getElementById('rf_sal_basic').value.trim();
    var effective = document.getElementById('rf_effective').value.trim();
    if (!salBasic || parseFloat(salBasic) <= 0 || !effective) {
        alertBox.innerHTML = '<div class="alert-err"><i class="fas fa-exclamation-circle"></i> Please fill Basic Salary and Effective Date.</div>';
        return;
    }
    alertBox.innerHTML = '';
    var customRows = [];
    document.querySelectorAll('#rf_sal_custom_rows_body .rf-sal-custom-row').forEach(function(tr) {
        var label = tr.querySelector('.rf-sal-custom-label').value.trim();
        var amount = tr.querySelector('.rf-sal-custom-amount').value;
        if (label !== '') customRows.push({ label: label, amount: amount });
    });
    var salFields = {
        salary_basic: salBasic,
        salary_hra: document.getElementById('rf_sal_hra').value,
        salary_special_allowance: document.getElementById('rf_sal_special').value,
        salary_conveyance: document.getElementById('rf_sal_conveyance').value,
        salary_other_allowances: document.getElementById('rf_sal_other').value,
        salary_deductions: document.getElementById('rf_sal_deductions').value,
        salary_gross: document.getElementById('rf_sal_gross').value,
        salary_net: document.getElementById('rf_sal_net').value,
        salary_custom_rows: JSON.stringify(customRows),
        salary_period: document.getElementById('rf_sal_period').value
    };
    $.post(window.location.pathname, $.extend({
        ajax_save_revision: 1,
        employee_id: REV_EMPLOYEE_ID,
        position: document.getElementById('rf_position').value.trim(),
        department: document.getElementById('rf_department').value.trim(),
        revision_effective_date: effective,
        previous_ctc: document.getElementById('rf_prev_ctc').value.trim(),
        offered_ctc_text: document.getElementById('rf_ctc_text').value.trim(),
        candidate_employee_code: document.getElementById('rf_emp_code').value.trim(),
        candidate_phone: document.getElementById('rf_phone').value.trim(),
        candidate_email: document.getElementById('rf_email').value.trim(),
        candidate_address: document.getElementById('rf_address').value,
        work_location: document.getElementById('rf_location').value,
        reporting_manager: document.getElementById('rf_manager').value,
        working_hours: document.getElementById('rf_hours').value,
        notice_period: document.getElementById('rf_notice').value,
        offer_validity: document.getElementById('rf_validity').value,
        revision_reason: document.getElementById('rf_reason').value,
        roles_responsibilities: document.getElementById('rf_roles').value,
        terms_conditions: document.getElementById('rf_terms').value,
        is_draft: isDraft ? 1 : 0
    }, salFields), function(resp) {
        if (resp.success) {
            showToast('Revision saved successfully! — ' + resp.offer_number);
            revOfferData = $.extend({
                id: resp.offer_id, offer_number: resp.offer_number, token: resp.token,
                letter_type: 'revision', revision_number: resp.revision_number,
                candidate_name: REV_EMP_NAME,
                position: document.getElementById('rf_position').value.trim(),
                department: document.getElementById('rf_department').value.trim(),
                offered_ctc: resp.offered_ctc,
                previous_ctc: document.getElementById('rf_prev_ctc').value.trim(),
                previous_position: REV_PREV_POS,
                candidate_employee_code: document.getElementById('rf_emp_code').value.trim(),
                candidate_phone: document.getElementById('rf_phone').value.trim(),
                candidate_email: document.getElementById('rf_email').value.trim(),
                candidate_address: document.getElementById('rf_address').value,
                revision_effective_date: effective,
                revision_reason: document.getElementById('rf_reason').value,
                work_location: document.getElementById('rf_location').value,
                reporting_manager: document.getElementById('rf_manager').value,
                working_hours: document.getElementById('rf_hours').value,
                notice_period: document.getElementById('rf_notice').value,
                offer_validity: document.getElementById('rf_validity').value,
                roles_responsibilities: document.getElementById('rf_roles').value,
                terms_conditions: document.getElementById('rf_terms').value,
                status: isDraft ? 'draft' : 'ready'
            }, salFields);
            renderRevSendPane();
            if (goToPreview) switchRevTab('preview');
        } else {
            showToast(resp.message || 'Could not save revision.', true);
        }
    }, 'json');
}

function renderRevSendPane() {
    var box = document.getElementById('revSendBody');
    if (!revOfferData) return;
    var link = window.location.protocol + '//' + window.location.host + window.location.pathname + '?token=' + revOfferData.token;
    var effDateTxt = revOfferData.revision_effective_date ? new Date(revOfferData.revision_effective_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : '-';
    var companyNameTxt = revCompanyData.company_name || 'the company';
    var defaultMsg = 'Dear ' + revOfferData.candidate_name + ',\n\n' +
        'Congratulations! 🎉\n\n' +
        'We are pleased to inform you that your terms of employment at ' + companyNameTxt + ' have been revised in recognition of your contribution and continued performance.\n\n' +
        'Revised Designation: ' + revOfferData.position + '\n' +
        'Revised CTC / Salary: ' + revOfferData.offered_ctc + '\n' +
        'Effective From: ' + effDateTxt + '\n\n' +
        'Please review and accept your revised offer letter using the secure link below:\n' + link + '\n\n' +
        'We truly appreciate your dedication and look forward to your continued success with us.\n\n' +
        'Best Regards,\nHR Team';
    var sentBannerHTML = revOfferData.sent_at
        ? '<div class="alert-ok"><i class="fas fa-check-circle"></i> Revised offer letter sent on ' + new Date(revOfferData.sent_at.replace(' ', 'T')).toLocaleString('en-IN',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}) + ' &middot; Current status: <strong>' + (revOfferData.status.charAt(0).toUpperCase() + revOfferData.status.slice(1)) + '</strong></div>'
        : '';
    var waDefaultMsg = 'Hi ' + revOfferData.candidate_name + ',\n\n' +
        'Your revised offer letter for *' + revOfferData.position + '* at *' + companyNameTxt + '* is ready.\n\n' +
        'Please click the link below to review and accept:\n' + link + '\n\n' +
        'Revised CTC: ' + revOfferData.offered_ctc + ' | Effective From: ' + effDateTxt;
    box.innerHTML = sentBannerHTML +
        '<div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:16px;margin-bottom:20px;">' +
        '<div style="font-weight:800;font-size:12px;color:#0369a1;margin-bottom:8px;text-transform:uppercase;"><i class="fas fa-link mr-1"></i> Offer Link (share with employee)</div>' +
        '<div style="display:flex;gap:8px;align-items:center;"><input type="text" id="revOfferLinkBox" value="' + link + '" readonly class="fc" style="flex:1;font-size:12px;"><button onclick="copyRevLink()" class="btn-p btn-navy" style="white-space:nowrap;"><i class="fas fa-copy"></i> Copy</button></div></div>' +
        '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">' +
        '<div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>' +
        '<div class="fg"><label class="fl">To</label><input type="email" id="revSendEmailTo" class="fc"></div>' +
        '<div class="fg"><label class="fl">Subject</label><input type="text" id="revSendEmailSubject" class="fc" value="Revised Offer Letter — ' + revOfferData.position + ' | ' + revOfferData.offer_number + '"></div>' +
        '<div class="fg"><label class="fl">Message</label><textarea id="revSendEmailBody" class="fc" style="height:220px;resize:vertical;">' + defaultMsg + '</textarea></div>' +
        '<button onclick="sendRevEmail()" class="btn-p btn-navy"><i class="fas fa-paper-plane"></i> Send Email Now</button></div>' +
        '<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;">' +
        '<div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>' +
        '<div class="fg"><label class="fl">Phone Number</label><input type="text" id="revWaPhone" class="fc" value="' + (revOfferData.candidate_phone || '') + '" placeholder="e.g. 91XXXXXXXXXX (with country code)"></div>' +
        '<textarea id="revWaMsgBox" class="fc" style="height:130px;resize:vertical;">' + waDefaultMsg + '</textarea>' +
        '<div style="margin-top:10px;"><button type="button" onclick="openRevWhatsApp()" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp"></i> Open WhatsApp</button></div></div>';
}

function openRevWhatsApp() {
    var phone = document.getElementById('revWaPhone').value.replace(/[^0-9]/g, '');
    if (!phone) { alert('Please enter a phone number (with country code, e.g. 91XXXXXXXXXX).'); return; }
    var msg = document.getElementById('revWaMsgBox').value;
    window.open('https://wa.me/' + phone + '?text=' + encodeURIComponent(msg), '_blank');
    if (revOfferData && revOfferData.id) {
        $.post(window.location.pathname, { ajax_mark_sent: 1, offer_id: revOfferData.id }, function(){}, 'json');
        revOfferData.sent_at = new Date().toISOString().slice(0, 19).replace('T', ' ');
        revOfferData.status = 'sent';
        renderRevSendPane();
    }
}

function copyRevLink() {
    var box = document.getElementById('revOfferLinkBox');
    box.select(); document.execCommand('copy');
    alert('Link copied!');
}

function sendRevEmail() {
    var to = document.getElementById('revSendEmailTo').value.trim();
    var subj = document.getElementById('revSendEmailSubject').value.trim();
    var body = document.getElementById('revSendEmailBody').value.trim();
    if (!to) { alert('Please enter recipient email.'); return; }
    if (!revOfferData) { alert('Please save the revision first.'); return; }
    if (!confirm('Send the revised offer letter email to ' + to + '?')) return;
    $('#emailSendingModal').modal('show');
    $.post(window.location.pathname, { ajax_send_email: 1, offer_id: revOfferData.id, to: to, subject: subj, body: body }, function(resp) {
        $('#emailSendingModal').modal('hide');
        setTimeout(function() {
            if (resp.success) {
                $.post(window.location.pathname, { ajax_mark_sent: 1, offer_id: revOfferData.id }, function(){}, 'json');
                revOfferData.sent_at = new Date().toISOString().slice(0, 19).replace('T', ' ');
                revOfferData.status = 'sent';
                renderRevSendPane();
                showToast('Email sent successfully!');
            } else {
                showToast(resp.message || 'Could not send email.', true);
            }
        }, 400);
    }, 'json').fail(function() {
        $('#emailSendingModal').modal('hide');
        setTimeout(function(){ showToast('Server error while sending email.', true); }, 400);
    });
}

function openRevDownload() {
    if (!revOfferData || !revOfferData.token) { alert('Please save the revision first.'); return; }
    window.open(window.location.pathname + '?token=' + revOfferData.token + '&download=1', '_blank');
}

function renderRevPreview() {
    var box = document.getElementById('revPdfPreviewBox');
    if (!box) return;
    if (!revOfferData) { box.innerHTML = '<p style="color:var(--muted);text-align:center;padding:30px;">Please save the revision details first.</p>'; return; }
    var cs = revCompanyData;
    var o = revOfferData;
    var letterDate = new Date().toLocaleDateString('en-IN',{day:'2-digit',month:'2-digit',year:'numeric'});
    var sigHTML = cs.company_signature ? '<img src="'+cs.company_signature+'" style="max-height:80px;max-width:180px;margin-bottom:4px;margin-top:15px;">' : '<div style="height:65px;"></div>';
    // Same numbered/bold formatting as the original candidate offer letter, so revised
    // offers render with identical alignment and styling in the PDF.
    var termsHTML = (o.terms_conditions || '').split('\n').map(function(t) { var tt = t.trim(); if(!tt) return ''; var nb = /^\d+\./.test(tt); if(nb) tt = tt.replace(/^(\d+\.\s*[^:]+:?)/, '<strong>$1</strong>'); return '<li style="margin-bottom:8px; font-size:14px;' + (nb?'list-style:none;margin-left:-20px;':'') + '">' + tt + '</li>'; }).join('');
    var rolesHTML = (o.roles_responsibilities || '').split('\n').map(function(r) { return r.trim() ? '<li style="margin-bottom:8px; font-size:14px;">' + r.trim() + '</li>' : ''; }).join('');
    var salaryHTML = revSalaryTableHTML(o);
    box.innerHTML = `
    <div class="letter-wave-top"><svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg"><path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/><path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/></svg></div>
    <div class="letter-header">
        <div class="letter-header-left">
            ${cs.company_phone ? '<span><i class="fas fa-phone-alt"></i> ' + cs.company_phone + '</span>' : ''}
            ${cs.company_email ? '<span><i class="fas fa-envelope"></i> ' + cs.company_email + '</span>' : ''}
            ${cs.company_website ? '<span><i class="fas fa-globe"></i> ' + cs.company_website + '</span>' : ''}
        </div>
        <div class="letter-header-right">${cs.company_logo ? '<img src="'+cs.company_logo+'" style="max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;">' : ''}</div>
    </div>
    <div class="letter-body">
        <div style="margin-bottom:30px;line-height:1.6;">
            <div style="font-weight:bold;margin-bottom:6px;">From</div>
            <div style="font-weight:bold;font-size:16px;">${cs.company_name || ''}</div>
            ${cs.company_address ? '<div><strong>Registered Office: ' + cs.company_address.trim().replace(/\n/g, '<br>') + '</strong></div>' : ''}
            <div><strong>Email: ${cs.company_email || ''} | Phone: ${cs.company_phone || ''}</strong></div>
            <div><strong>Date: ${letterDate}</strong></div>
        </div>
        <div style="margin-bottom:25px;line-height:1.6;">
            <strong>To,</strong><br>
            <strong>${o.candidate_name}</strong><br>
            ${o.candidate_employee_code ? '<strong>Employee ID: ' + o.candidate_employee_code + '</strong><br>' : ''}
            ${o.candidate_address ? '<strong>' + o.candidate_address.trim().replace(/\n/g, '<br>') + '</strong><br>' : ''}
            ${o.candidate_phone ? '<strong>Phone: ' + o.candidate_phone + '</strong>' : ''}${o.candidate_email ? ' &nbsp;|&nbsp; <strong>Email: ' + o.candidate_email + '</strong>' : ''}
        </div>
        <div class="letter-subject">Subject: Revised Offer of Employment / Revision of Terms — ${o.position}</div>
        <p>Dear <strong>${o.candidate_name}</strong>,</p>
        <p>Further to your employment with <strong>${cs.company_name || ''}</strong>, we are pleased to inform you that your terms of employment have been revised as set out below, effective from the date mentioned. This letter supersedes the salary/designation terms of your previous offer letter to the extent revised herein; all other terms and conditions remain unchanged.</p>
        <div style="margin-bottom:20px;border:1px solid #dbeafe;background:#f8faff;border-radius:8px;padding:14px 18px;">
            <strong>Summary of Revision:</strong>
            <table style="width:100%;margin-top:8px;border-collapse:collapse;font-size:13px;">
                <tr><td style="padding:4px 8px;color:#64748b;">Designation</td><td style="padding:4px 8px;">${o.previous_position || '-'} &rarr; <strong>${o.position}</strong></td></tr>
                <tr><td style="padding:4px 8px;color:#64748b;">CTC / Salary</td><td style="padding:4px 8px;">${o.previous_ctc || '-'} &rarr; <strong>${o.offered_ctc}</strong></td></tr>
                <tr><td style="padding:4px 8px;color:#64748b;">Effective From</td><td style="padding:4px 8px;"><strong>${o.revision_effective_date ? new Date(o.revision_effective_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : '-'}</strong></td></tr>
                ${o.revision_reason ? '<tr><td style="padding:4px 8px;color:#64748b;">Reason</td><td style="padding:4px 8px;">' + o.revision_reason + '</td></tr>' : ''}
            </table>
        </div>
        ${salaryHTML}
        ${rolesHTML ? '<div style="margin-bottom:25px;"><strong>Roles and Responsibilities:</strong><ul style="margin-top:8px;padding-left:20px;font-size:18px;">' + rolesHTML + '</ul></div>' : ''}
        <div style="margin-bottom:25px;"><strong>Terms and Conditions:</strong><ul style="margin-top:8px;padding-left:20px;font-size:18px;">${termsHTML}</ul></div>
        <div style="margin-bottom:20px;"><strong>Verification:</strong> This letter is subject to successful verification of records and continued compliance with company policies.</div>
        <div class="letter-sig-area">
            <div class="letter-sig-box">
                <div style="height:70px;display:flex;align-items:flex-end;justify-content:center;margin-bottom:5px;">${sigHTML}</div>
                <div class="letter-sig-line" style="margin-top:0;">For ${cs.company_name || ''}<br><small><strong>Name:</strong> ${cs.signatory_name || 'Authorized Signatory'}</small><br><small style="font-weight:400;"><strong>Designation:</strong> ${cs.signatory_designation || ''}</small></div>
            </div>
            <div class="letter-sig-box">
                <div style="height:70px;"></div>
                <div class="letter-sig-line" style="margin-top:0;">Accepted and Agreed<br><small>${o.candidate_name}</small></div>
            </div>
        </div>
    </div>
    <div class="letter-wave-bottom"><svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg"><path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/><path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/></svg></div>
    `;
}

// Salary breakup table markup shared by the HR preview above — any component
// row, fixed or custom, is omitted when its amount is 0/blank; Gross and Net
// (the totals) always show.
function revSalaryTableHTML(o) {
    function money(v) { var n = parseFloat(v); if (isNaN(n)) n = 0; return '₹' + n.toFixed(2).replace(/\d(?=(\d{3})+\.)/g, '$&,'); }
    function esc(s) { var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
    function cell(label, amt) { return '<tr><td style="padding:8px 20px;border:1px solid #94a3b8;">' + label + '</td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;">' + money(amt) + '</td></tr>'; }
    var rows = '';
    [['Basic Salary', o.salary_basic], ['House Rent Allowance (HRA)', o.salary_hra], ['Special Allowance', o.salary_special_allowance], ['Conveyance Allowance', o.salary_conveyance], ['Other Allowances', o.salary_other_allowances]].forEach(function(item) {
        if (parseFloat(item[1]) > 0) rows += cell(item[0], item[1]);
    });
    var customRows = [];
    try { customRows = JSON.parse(o.salary_custom_rows || '[]'); } catch (e) {}
    customRows.forEach(function(cr) {
        if (parseFloat(cr.amount) > 0 && cr.label && cr.label.trim()) rows += cell(esc(cr.label), cr.amount);
    });
    rows += '<tr style="background:#f8fafc;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Gross Salary</strong></td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;"><strong>' + money(o.salary_gross) + '</strong></td></tr>';
    if (parseFloat(o.salary_deductions) > 0) {
        rows += '<tr><td style="padding:8px 20px;border:1px solid #94a3b8;">Deductions</td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;">&minus; ' + money(o.salary_deductions) + '</td></tr>';
    }
    rows += '<tr style="background:#f0fdf4;"><td style="padding:8px 20px;border:1px solid #94a3b8;"><strong>Net Salary</strong></td><td style="padding:8px 20px;border:1px solid #94a3b8;text-align:center;"><strong>' + money(o.salary_net) + '</strong></td></tr>';
    var period = o.salary_period === 'annum' ? 'annum' : 'month';
    var periodLabel = period === 'annum' ? 'Annual' : 'Monthly';
    return '<div style="margin-bottom:25px;"><strong>Salary Structure (' + periodLabel + '):</strong>'
        + '<table style="width:100%;border-collapse:collapse;font-size:13.5px;margin-top:8px;">' + rows + '</table>'
        + '<div style="font-size:11px;color:#64748b;margin-top:6px;">All figures in INR, per ' + period + '.</div></div>';
}
</script>

<?php endif; // end rev_employee check ?>

<?php else: ?>
<!-- ==================== OFFER LETTER PAGE ==================== -->

<?php if (!$candidate): ?>
<?php if (!empty($employee_offer_not_found)): ?>
<div style="background:#fff3cd;color:#856404;padding:15px 20px;text-align:center;border:1px solid #ffeeba;border-radius:8px;margin:0 0 20px;">
    <strong>No original offer letter found for this employee.</strong> Their phone/email didn't match any screening record — they may have been added directly to <code>hr_employees</code> without going through the screening/hiring flow, so no offer was ever generated for them here.
    <?php if (!empty($employee_offer_not_found_id)): ?>
    <div style="margin-top:12px;">
        <a href="hr-employee-offer.php?generate_original_for_employee=<?php echo intval($employee_offer_not_found_id); ?>" class="btn-p btn-navy" style="padding:9px 18px;font-size:12.5px;text-decoration:none;display:inline-block;" onclick="return confirm('Generate a fresh original offer letter for this employee? This creates the screening record they never had, then takes you straight to drafting their offer.');">
            <i class="fas fa-file-signature mr-1"></i> Generate Original Offer Letter for This Employee
        </a>
    </div>
    <?php endif; ?>
</div>
<?php endif; ?>
<?php
$rev_employees_query = mysqli_query($con, "
    SELECT e.id as employee_id, e.name, e.position, e.department, e.company_name,
           ol.status, ol.revision_number, ol.sent_at, ol.candidate_action, ol.candidate_action_at, ol.hr_approved_at
    FROM hr_employees e
    INNER JOIN (
        SELECT employee_id, MAX(id) as max_id FROM hr_offer_letters WHERE letter_type='revision' GROUP BY employee_id
    ) latest ON latest.employee_id = e.id
    INNER JOIN hr_offer_letters ol ON ol.id = latest.max_id
    ORDER BY ol.updated_at DESC
");
$rev_employees_rows = [];
if ($rev_employees_query) while ($rr = mysqli_fetch_assoc($rev_employees_query)) $rev_employees_rows[] = $rr;
?>
<?php if (!empty($rev_employees_rows)): ?>
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-file-signature"></i> Employees with Revised Offer Letters</div>
  <div style="overflow-x:auto;">
    <table style="width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;border:1px solid var(--border);">
      <thead style="background:#f8faff;color:#64748b;font-size:11px;text-transform:uppercase;font-weight:800;">
        <tr>
          <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Employee Name</th>
          <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Position &amp; Dept</th>
          <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Latest Revision</th>
          <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Status</th>
          <th style="padding:14px;border-bottom:1px solid var(--border);text-align:right;">Action</th>
        </tr>
      </thead>
      <tbody style="font-size:13px;font-weight:700;color:var(--navy);">
        <?php foreach ($rev_employees_rows as $re):
          $sc_map = ['draft'=>'s-draft','ready'=>'s-ready','sent'=>'s-sent','accepted'=>'s-accepted','declined'=>'s-declined'];
          $sc_cls = $sc_map[$re['status']] ?? 's-draft';
        ?>
        <tr style="border-bottom:1px solid var(--border);">
          <td style="padding:14px;"><?php echo htmlspecialchars($re['name']); ?></td>
          <td style="padding:14px;">
            <div style="color:var(--navy);"><?php echo htmlspecialchars($re['position']); ?></div>
            <div style="font-size:11px;color:var(--muted);"><?php echo htmlspecialchars($re['department']); ?></div>
          </td>
          <td style="padding:14px;">Revision <?php echo intval($re['revision_number']); ?></td>
          <td style="padding:14px;">
            <span class="status-badge <?php echo $sc_cls; ?>"><i class="fas fa-file-signature mr-1"></i> <?php echo ucfirst($re['status']); ?></span>
            <?php if ($re['status'] === 'accepted' && empty($re['hr_approved_at'])): ?>
            <div style="font-size:10px;font-weight:700;color:#92400e;margin-top:4px;"><i class="fas fa-hourglass-half"></i> Awaiting HR Approval</div>
            <?php elseif (!empty($re['hr_approved_at'])): ?>
            <div style="font-size:10px;font-weight:700;color:#065f46;margin-top:4px;"><i class="fas fa-check-circle"></i> Approved &amp; Filed</div>
            <?php endif; ?>
          </td>
          <td style="padding:14px;text-align:right;">
            <a href="hr-employee-offer.php?page=revise&employee_id=<?php echo intval($re['employee_id']); ?>" class="btn-p btn-navy" style="padding:8px 16px;font-size:12px;"><i class="fas fa-file-signature"></i> Manage Revision</a>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>
<?php endif; ?>
<?php
$dv_verified_query = mysqli_query($con, "SELECT d.candidate_id, d.candidate_name, d.verified_at, s.position_applied, s.department, o.status as offer_status, o.sent_at as offer_sent_at FROM hr_dv_requests d LEFT JOIN hr_screenings s ON d.candidate_id = s.id LEFT JOIN hr_offer_letters o ON d.candidate_id = o.candidate_id WHERE d.status='verified' ORDER BY d.verified_at DESC");
$dv_verified_count = $dv_verified_query ? mysqli_num_rows($dv_verified_query) : 0;
?>
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-user-check"></i> Eligible Candidates (Document Verification Completed)</div>
  
  <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; margin-bottom:20px;">
    <p style="font-size:13px;color:var(--muted);margin:0;">Select a candidate to draft or send their offer letter.</p>
    <div style="position: relative; width: 100%; max-width: 300px;">
      <i class="fas fa-search" style="position: absolute; left: 14px; top: 13px; color: var(--muted);"></i>
      <input type="text" id="candidateSearchInput" onkeyup="filterCandidates()" placeholder="Search candidates..." class="fc" style="padding-left: 36px; width: 100%;">
    </div>
  </div>
  
  <?php if ($dv_verified_count > 0): ?>
    <div style="overflow-x:auto;">
      <table id="candidatesTable" style="width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;border:1px solid var(--border);">
        <thead style="background:#f8faff;color:#64748b;font-size:11px;text-transform:uppercase;font-weight:800;">
          <tr>
            <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Candidate Name</th>
            <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Position & Dept</th>
            <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Verified On</th>
            <th style="padding:14px;border-bottom:1px solid var(--border);text-align:left;">Offer Status</th>
            <th style="padding:14px;border-bottom:1px solid var(--border);text-align:right;">Action</th>
          </tr>
        </thead>
        <tbody style="font-size:13px;font-weight:700;color:var(--navy);">
          <?php while($row = mysqli_fetch_assoc($dv_verified_query)): ?>
          <tr class="candidate-row" style="border-bottom:1px solid var(--border);">
            <td style="padding:14px;"><?php echo htmlspecialchars($row['candidate_name']); ?></td>
            <td style="padding:14px;">
                <div style="color:var(--navy);"><?php echo htmlspecialchars($row['position_applied']); ?></div>
                <div style="font-size:11px;color:var(--muted);"><?php echo htmlspecialchars($row['department']); ?></div>
            </td>
            <td style="padding:14px;"><?php echo date('d M Y', strtotime($row['verified_at'])); ?></td>
            <td style="padding:14px;">
              <?php if (!$row['offer_status']): ?>
                <span class="status-badge s-draft" style="background:#f1f5f9;color:#64748b;">No Offer Created</span>
              <?php else: ?>
                <?php
                  $sc_map = ['draft'=>'s-draft','ready'=>'s-ready','sent'=>'s-sent','accepted'=>'s-accepted','declined'=>'s-declined'];
                  $sc_cls = $sc_map[$row['offer_status']] ?? 's-draft';
                ?>
                <span class="status-badge <?php echo $sc_cls; ?>"><?php echo ucfirst($row['offer_status']); ?></span>
                <?php if (!empty($row['offer_sent_at'])): ?>
                <div style="font-size:10px;font-weight:700;color:#065f46;margin-top:4px;"><i class="fas fa-check-circle"></i> Sent <?php echo date('d M Y, h:i A', strtotime($row['offer_sent_at'])); ?></div>
                <?php endif; ?>
              <?php endif; ?>
            </td>
            <td style="padding:14px;text-align:right;">
              <div style="display:flex;gap:8px;justify-content:flex-end;">
                <a href="hr-employee-offer.php?candidate_id=<?php echo $row['candidate_id']; ?>" class="btn-p btn-navy" style="padding:8px 16px;font-size:12px;"><i class="fas fa-file-signature"></i> Manage Offer</a>
                <button onclick="deleteCandidate(<?php echo $row['candidate_id']; ?>)" class="btn-p" style="background:#fee2e2;color:#991b1b;padding:8px 16px;font-size:12px;border:none;cursor:pointer;"><i class="fas fa-trash"></i> Delete</button>
              </div>
            </td>
          </tr>
          <?php endwhile; ?>
        </tbody>
      </table>
    </div>
  <?php else: ?>
    <div style="text-align:center;padding:40px;border:2px dashed var(--border);border-radius:10px;background:#f8faff;">
      <i class="fas fa-folder-open fa-2x mb-2" style="color:var(--muted);"></i>
      <h4 style="color:var(--navy);margin-top:10px;">No Verified Candidates</h4>
      <p style="color:var(--muted);">No candidates have completed the Document Verification round yet.</p>
    </div>
  <?php endif; ?>
</div>

<script>
function deleteCandidate(cid) {
  if (confirm("Are you sure you want to delete this candidate? This will permanently remove their screening, verification, and offer data.")) {
    var formData = new FormData();
    formData.append('ajax_delete_candidate', '1');
    formData.append('candidate_id', cid);
    fetch('hr-employee-offer.php', {
      method: 'POST',
      body: formData
    })
    .then(r => r.json())
    .then(data => {
      if(data.success) {
        window.location.reload();
      } else {
        alert("Error deleting candidate.");
      }
    }).catch(err => {
      console.error(err);
      alert("Error deleting candidate.");
    });
  }
}

function filterCandidates() {
  var input = document.getElementById("candidateSearchInput");
  var filter = input.value.toUpperCase();
  var table = document.getElementById("candidatesTable");
  if (!table) return;
  var tr = table.getElementsByClassName("candidate-row");

  for (var i = 0; i < tr.length; i++) {
    var tdName = tr[i].getElementsByTagName("td")[0];
    var tdPosDept = tr[i].getElementsByTagName("td")[1];
    if (tdName || tdPosDept) {
      var txtValueName = tdName.textContent || tdName.innerText;
      var txtValuePosDept = tdPosDept.textContent || tdPosDept.innerText;
      if (txtValueName.toUpperCase().indexOf(filter) > -1 || txtValuePosDept.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else {
        tr[i].style.display = "none";
      }
    }       
  }
}
</script>
<?php else: ?>

<!-- Status Bar -->
<div class="no-print" style="display:flex;justify-content:space-between;align-items:center;background:var(--card);border:1px solid var(--border);border-radius:12px;padding:16px 22px;margin-bottom:18px;">
  <div style="display:flex;align-items:center;gap:14px;">
    <div style="width:46px;height:46px;background:linear-gradient(135deg,var(--navy),var(--blue));border-radius:12px;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:18px;">
      <?php echo strtoupper(substr($candidate['candidate_name'],0,1)); ?>
    </div>
    <div>
      <div style="font-weight:800;color:var(--navy);font-size:15px;"><?php echo htmlspecialchars($candidate['candidate_name']); ?></div>
      <div style="font-size:12px;color:var(--muted);"><?php echo htmlspecialchars($candidate['position_applied']); ?> &middot; <?php echo htmlspecialchars($candidate['department']); ?></div>
    </div>
  </div>
  <div style="display:flex;align-items:center;gap:12px;">
    <?php if ($offer): ?>
      <div style="font-size:12px;font-weight:700;color:var(--muted);">Offer: <strong><?php echo htmlspecialchars($offer['offer_number']); ?></strong></div>
      <?php
        $sc_map = ['draft'=>'s-draft','ready'=>'s-ready','sent'=>'s-sent','accepted'=>'s-accepted','declined'=>'s-declined'];
        $sc_cls = $sc_map[$offer['status']] ?? 's-draft';
      ?>
      <span class="status-badge <?php echo $sc_cls; ?>"><?php echo ucfirst($offer['status']); ?></span>
      <?php if (!empty($offer['sent_at'])): ?>
      <span style="font-size:11px;font-weight:700;color:#065f46;background:#dcfce7;border:1px solid #86efac;border-radius:20px;padding:5px 12px;display:inline-flex;align-items:center;gap:5px;" title="Offer letter sent on <?php echo date('d M Y, h:i A', strtotime($offer['sent_at'])); ?>"><i class="fas fa-check-circle"></i> Sent <?php echo date('d M Y, h:i A', strtotime($offer['sent_at'])); ?></span>
      <?php endif; ?>
    <?php endif; ?>
  </div>
</div>

<div class="tab-bar no-print">
  <button class="tab-btn active" id="tab-form" onclick="switchOfferTab('form')"><i class="fas fa-edit"></i> Fill Offer Details</button>
  <button class="tab-btn" id="tab-preview" onclick="switchOfferTab('preview')"><i class="fas fa-eye"></i> Preview PDF</button>
  <button class="tab-btn" id="tab-send" onclick="switchOfferTab('send')"><i class="fas fa-paper-plane"></i> Send Offer</button>
  <?php if ($offer && $offer['status'] == 'accepted'): ?>
  <button class="tab-btn" id="tab-signed" onclick="switchOfferTab('signed')"><i class="fas fa-signature"></i> Signed Copy</button>
  <?php endif; ?>
</div>

<!-- TAB: FORM -->
<div id="pane-form" class="offer-tab-pane">
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-file-alt"></i> Offer Details</div>
  <div id="formAlert"></div>

  <div class="grid4">
    <div class="fg"><label class="fl">Salutation</label>
      <select id="f_salutation" class="fc">
        <?php foreach(['Mr.','Mrs.','Ms.','Miss','Dr.','Mx.'] as $sal): ?>
        <option value="<?php echo $sal; ?>" <?php echo ($offer['salutation'] ?? 'Mr.') == $sal ? 'selected' : ''; ?>><?php echo $sal; ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fg"><label class="fl">Candidate Name</label><input type="text" id="f_cname" class="fc" value="<?php echo htmlspecialchars($offer['candidate_name'] ?? $candidate['candidate_name']); ?>"></div>
    <div class="fg"><label class="fl">Position</label><input type="text" id="f_cpos" class="fc" value="<?php echo htmlspecialchars($offer['position'] ?? $candidate['position_applied']); ?>"></div>
    <div class="fg"><label class="fl">Department</label><input type="text" id="f_cdept" class="fc" value="<?php echo htmlspecialchars($offer['department'] ?? $candidate['department']); ?>"></div>
  </div>
  <div class="fg"><label class="fl">Candidate Full Address (For physical post)</label><textarea id="f_caddr" class="fc" style="height:60px;" placeholder="Enter candidate's address..."><?php echo htmlspecialchars($offer['candidate_address'] ?? ''); ?></textarea></div>

  <div class="grid3">
    <div class="fg"><label class="fl">Offered CTC / Salary *</label><input type="text" id="f_ctc" class="fc" value="<?php echo htmlspecialchars($offer['offered_ctc'] ?? ''); ?>" placeholder="e.g. ₹6,00,000 per annum"></div>
    <div class="fg"><label class="fl">Joining Date *</label><input type="date" id="f_joining" class="fc" value="<?php echo htmlspecialchars($offer['joining_date'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Probation Period</label><input type="text" id="f_probation" class="fc" value="<?php echo htmlspecialchars($offer['probation_period'] ?? ''); ?>" placeholder="e.g. 3 Months"></div>
  </div>
  <div class="grid2">
    <div class="fg"><label class="fl">Work Location</label><input type="text" id="f_location" class="fc" value="<?php echo htmlspecialchars($offer['work_location'] ?? ''); ?>" placeholder="e.g. Mumbai"></div>
    <div class="fg"><label class="fl">Reporting Manager</label><input type="text" id="f_manager" class="fc" value="<?php echo htmlspecialchars($offer['reporting_manager'] ?? ''); ?>"></div>
  </div>
  <div class="grid3">
    <div class="fg"><label class="fl">Working Hours / Shift</label><input type="text" id="f_hours" class="fc" value="<?php echo htmlspecialchars($offer['working_hours'] ?? ''); ?>" placeholder="e.g. 9 AM – 6 PM"></div>
    <div class="fg"><label class="fl">Notice Period</label><input type="text" id="f_notice" class="fc" value="<?php echo htmlspecialchars($offer['notice_period'] ?? ''); ?>" placeholder="e.g. 30 Days"></div>
    <div class="fg"><label class="fl">Offer Validity (Date & Time)</label><input type="datetime-local" id="f_validity" class="fc" value="<?php echo htmlspecialchars($offer['offer_validity'] ? date('Y-m-d\TH:i', strtotime($offer['offer_validity'])) : ''); ?>"></div>
  </div>

  <div class="fg" style="margin-top:14px;">
    <label class="fl">Roles & Responsibilities</label>
    <textarea id="f_roles" class="fc" style="height:150px; white-space: pre-wrap;"><?php echo htmlspecialchars($offer['roles_responsibilities'] ?? "- Vendor Sourcing & Quotations\n- Negotiation & PO Processing\n- Delivery Tracking\n(Edit as needed...)"); ?></textarea>
  </div>
  <div class="fg">
    <label class="fl">Terms & Conditions</label>
    <textarea id="f_terms" class="fc" style="height:200px; white-space: pre-wrap;"><?php echo htmlspecialchars($offer['terms_conditions'] ?? "1. Working Hours: As per the company's standard working schedule or as communicated by the management.\n2. Leave Entitlement: You will be entitled to leave as per the company's policy.\n3. Termination\nNotice Period: After confirmation, either party may terminate the employment by giving 60 (sixty) days' written notice or salary in lieu of notice.\nImmediate Termination: The company reserves the right to terminate employment without notice in cases of misconduct, breach of confidentiality, or violation of company policies.\nCompany Liability: If the employee completes the full notice period as instructed by the management, the company will release the pending salary along with the notice period salary (if applicable) as per company policy.\nIf an employee is found absconding by leaving employment without prior notice, approval, or completion of required exit formalities, the employee shall not be eligible for salary payment for the service period under absconding status, subject to company policy and applicable laws.\nConfidentiality: You must maintain the confidentiality of all company information and shall not disclose any data or records to any unauthorized person during or after your employment.\n4. Code of Conduct: You are required to adhere to all company rules, regulations, and policies in force and as amended from time to time.\n5. Verification: This offer is subject to successful verification of your credentials, background, and documents."); ?></textarea>
  </div>

  <!-- Custom Fields -->
  <div class="sec-lbl" style="margin-top:10px;"><i class="fas fa-plus-circle"></i> Additional Fields</div>
  <div id="customFieldsContainer">
    <?php
    $cf_data = $offer ? json_decode($offer['custom_fields'] ?? '[]', true) : [];
    if (!empty($cf_data)):
      foreach ($cf_data as $idx => $cf):
    ?>
    <div class="custom-field-row" id="cfrow_<?php echo $idx; ?>">
      <input type="text" class="fc cf-heading" placeholder="Heading (e.g. Benefits)" value="<?php echo htmlspecialchars($cf['heading'] ?? ''); ?>">
      <input type="text" class="fc cf-text" placeholder="Value / Description" value="<?php echo htmlspecialchars($cf['text'] ?? ''); ?>">
      <button type="button" onclick="removeCF(this)" style="padding:8px 12px;border:none;border-radius:8px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>
    </div>
    <?php endforeach; endif; ?>
  </div>
  <button type="button" onclick="addCustomField()" class="btn-p btn-light" style="margin-top:6px;"><i class="fas fa-plus"></i> Add Field</button>

  <div style="display:flex;gap:10px;margin-top:20px;flex-wrap:wrap;">
    <button type="button" onclick="saveOffer(1)" class="btn-p btn-light"><i class="fas fa-save"></i> Save Draft</button>
    <button type="button" onclick="saveOffer(0)" class="btn-p btn-navy"><i class="fas fa-check"></i> Save & Mark Ready</button>
    <button type="button" onclick="saveOffer(0, true)" class="btn-p btn-warn"><i class="fas fa-eye"></i> Save & Preview</button>
  </div>
</div>
</div>

<!-- TAB: PREVIEW -->
<div id="pane-preview" class="offer-tab-pane" style="display:none;">
<div class="card-s">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
    <div class="sec-lbl" style="margin:0;border:none;"><i class="fas fa-eye"></i> Offer Letter Preview</div>
    <div style="display:flex;gap:8px;">
      <button onclick="openOfferDownload()" class="btn-p btn-light no-print"><i class="fas fa-print"></i> Print / Save PDF</button>
      <button onclick="switchOfferTab('send')" class="btn-p btn-navy no-print"><i class="fas fa-paper-plane"></i> Proceed to Send</button>
    </div>
  </div>
  <div class="pdf-preview" id="pdfPreviewBox">
    <!-- Rendered dynamically by JS -->
  </div>
</div>
</div>

<!-- TAB: SEND -->
<div id="pane-send" class="offer-tab-pane" style="display:none;">
<div class="card-s">
  <div class="sec-lbl"><i class="fas fa-paper-plane"></i> Send Offer Letter</div>

  <?php if ($offer && !empty($offer['sent_at'])): ?>
  <div class="alert-ok"><i class="fas fa-check-circle"></i> Offer letter sent on <?php echo date('d M Y, h:i A', strtotime($offer['sent_at'])); ?> &middot; Current status: <strong><?php echo ucfirst($offer['status']); ?></strong></div>
  <?php endif; ?>

  <?php if ($offer): ?>
  <!-- Offer Link -->
  <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:16px;margin-bottom:20px;">
    <div style="font-weight:800;font-size:12px;color:#0369a1;margin-bottom:8px;text-transform:uppercase;"><i class="fas fa-link mr-1"></i> Offer Link (share with candidate)</div>
    <div style="display:flex;gap:8px;align-items:center;">
      <input type="text" id="offerLinkBox" value="<?php echo htmlspecialchars($offer_link); ?>" readonly class="fc" style="flex:1;font-size:12px;">
      <button onclick="copyOfferLink()" class="btn-p btn-navy" style="white-space:nowrap;"><i class="fas fa-copy"></i> Copy</button>
    </div>
  </div>

  <!-- Email -->
  <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
    <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
    <div class="fg"><label class="fl">To</label><input type="email" id="sendEmailTo" class="fc" value="<?php echo htmlspecialchars($candidate['candidate_email'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Subject</label><input type="text" id="sendEmailSubject" class="fc" value="Offer Letter — <?php echo htmlspecialchars($offer['position'] ?? ''); ?> | <?php echo htmlspecialchars($offer['offer_number'] ?? ''); ?>"></div>
    <div class="fg"><label class="fl">Message</label><textarea id="sendEmailBody" class="fc" style="height:180px;resize:vertical;"><?php echo htmlspecialchars($email_body_raw); ?></textarea></div>
    <button onclick="sendEmail()" class="btn-p btn-navy"><i class="fas fa-paper-plane"></i> Send Email Now</button>
  </div>

  <!-- WhatsApp -->
  <?php if ($cand_phone_clean): ?>
  <div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;margin-bottom:16px;">
    <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
    <textarea id="waMsgBox" class="fc" style="height:130px;resize:vertical;"><?php echo htmlspecialchars("Hi {$offer['candidate_name']},\n\nYour offer letter for *{$offer['position']}* at *{$cs['company_name']}* is ready.\n\nPlease click the link below to review and accept:\n{$offer_link}\n\nValid until: " . ($offer['offer_validity'] ? date('d M Y, h:i A', strtotime($offer['offer_validity'])) : 'As discussed')); ?></textarea>
    <div style="display:flex;gap:8px;margin-top:10px;">
      <a id="waBtn" href="https://wa.me/<?php echo $cand_phone_clean; ?>?text=<?php echo $wa_body; ?>" target="_blank" class="btn-p" style="background:#25d366;color:#fff;text-decoration:none;" onclick="markSent()"><i class="fab fa-whatsapp"></i> Open WhatsApp</a>
    </div>
  </div>
  <?php endif; ?>

  <!-- Revision -->
  <?php if ($offer && in_array($offer['status'], ['sent','accepted','declined'])): ?>
  <div style="background:#fff7ed;border:1px solid #fcd34d;border-radius:10px;padding:14px;">
    <div style="font-weight:800;font-size:13px;color:#92400e;margin-bottom:6px;"><i class="fas fa-edit mr-1"></i> Revise Offer</div>
    <p style="font-size:12px;color:#78350f;margin-bottom:10px;">Need to change salary or other details? Go back to the form, update, save, and resend.</p>
    <button onclick="switchOfferTab('form')" class="btn-p btn-warn"><i class="fas fa-pen"></i> Edit & Revise</button>
  </div>
  <?php endif; ?>

  <?php else: ?>
  <div class="alert-err"><i class="fas fa-exclamation-circle"></i> Please fill and save the offer details first before sending.</div>
  <?php endif; ?>
</div>
</div>

<!-- TAB: SIGNED COPY -->
<?php if ($offer && $offer['status'] == 'accepted'): ?>
<div id="pane-signed" class="offer-tab-pane" style="display:none;">
<div class="card-s">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
    <div class="sec-lbl" style="margin:0;border:none;"><i class="fas fa-signature"></i> Signed Offer Letter</div>
    <div class="no-print" style="display:flex; gap:10px;">
      <button onclick="var b = document.getElementById('signedPreviewBox'); b.style.display = b.style.display === 'none' ? 'block' : 'none';" class="btn-p btn-light"><i class="fas fa-eye"></i> View Signed PDF</button>
      <button onclick="openOfferDownload()" class="btn-p btn-navy"><i class="fas fa-download"></i> Download Signed PDF</button>
    </div>
  </div>
  <div class="alert-ok"><i class="fas fa-check-circle"></i> Candidate accepted on <?php echo date('d M Y, h:i A', strtotime($offer['candidate_action_at'])); ?></div>
  
  <div class="no-print" style="background:#f0f9ff;border:2px dashed #bae6fd;border-radius:12px;padding:20px;margin-bottom:20px;display:flex;gap:15px;align-items:flex-start;">
    <div style="background:#0284c7;color:#fff;width:40px;height:40px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">
      <i class="fas fa-forward"></i>
    </div>
    <div>
      <h4 style="margin:0 0 5px 0;font-size:15px;font-weight:800;color:#0284c7;">Offer Accepted! Next Step: Onboarding</h4>
      <p style="margin:0;font-size:13px;color:#334155;line-height:1.6;">
        The candidate has successfully signed and accepted the offer. To move them into the onboarding phase, you must manually update their screening status to <strong>"Hired"</strong> in the main dashboard. Once marked as Hired, they will become available in the Onboarding Pending List for link generation.
      </p>
      <div style="margin-top: 12px;">
        <?php if (($candidate['hr_decision'] ?? '') === 'hired'): ?>
        <button class="btn-p" disabled style="background:#059669;border:none;color:#fff;font-size:13px;font-weight:700;padding:10px 20px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;opacity:.9;cursor:default;"><i class="fas fa-check"></i> Successfully Hired!</button>
        <a href="hr-employee-onboarding-pending-list.php" class="btn-p" style="background:#1a3fc4;color:#fff;font-size:13px;font-weight:700;padding:10px 20px;text-decoration:none;border-radius:8px;display:inline-flex;align-items:center;gap:6px;margin-left:10px;">Go to Onboarding List <i class="fas fa-arrow-right"></i></a>
        <?php else: ?>
        <button onclick="markHiredFromOffer(<?php echo $candidate_id; ?>)" class="btn-p" style="background:#10b981;border:none;color:#fff;font-size:13px;font-weight:700;padding:10px 20px;cursor:pointer;border-radius:8px;display:inline-flex;align-items:center;gap:6px;"><i class="fas fa-user-check"></i> Mark as Hired</button>
        <?php endif; ?>
      </div>
    </div>
  </div>

  <div class="pdf-preview" id="signedPreviewBox" style="display:none; margin-top:20px;">
    <!-- Rendered by JS -->
  </div>
</div>
</div>
<script>
function markHiredFromOffer(cid) {
    if(!confirm('Are you sure you want to mark this candidate as Hired? They will be moved to the Onboarding Pending List.')) return;
    var btn = event.currentTarget;
    var oldHtml = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Processing...';
    btn.disabled = true;
    $.post(window.location.href, { ajax_mark_hired: 1, candidate_id: cid }, function(resp) {
        if(resp.success) {
            btn.innerHTML = '<i class="fas fa-check"></i> Successfully Hired!';
            btn.style.background = '#059669';
            alert('Candidate marked as Hired successfully! You can now generate their onboarding link in the Onboarding Pending List.');
            
            // Add a button to navigate to the Onboarding list
            var goBtn = document.createElement('a');
            goBtn.href = 'hr-employee-onboarding-pending-list.php';
            goBtn.className = 'btn-p';
            goBtn.style.cssText = 'background:#1a3fc4;color:#fff;font-size:13px;font-weight:700;padding:10px 20px;text-decoration:none;border-radius:8px;display:inline-flex;align-items:center;gap:6px;margin-left:10px;';
            goBtn.innerHTML = 'Go to Onboarding List <i class="fas fa-arrow-right"></i>';
            btn.parentNode.appendChild(goBtn);
        } else {
            alert('Failed to update status.');
            btn.innerHTML = oldHtml;
            btn.disabled = false;
        }
    }, 'json').fail(function(){
        alert('Server Error.');
        btn.innerHTML = oldHtml;
        btn.disabled = false;
    });
}
</script>
<?php endif; ?>

<?php endif; // end candidate check ?>
<?php endif; // end page check ?>

</div><!-- /wrap -->

<!-- Toast Card -->
<div id="toastCard" class="toast-card">
    <i id="toastIcon" class="fas fa-check-circle toast-icon"></i>
    <div id="toastText" class="toast-text">Message</div>
</div>

<!-- Email Sending Modal -->
<div class="modal fade" id="emailSendingModal" tabindex="-1">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content" style="border-radius:14px;border:none;">
      <div class="modal-body" style="padding:32px;text-align:center;">
        <i class="fas fa-spinner fa-spin fa-3x" style="color:var(--blue);margin-bottom:16px;display:block;"></i>
        <h5 style="font-weight:800;color:var(--navy);">Sending Email...</h5>
        <p style="color:var(--muted);font-size:13px;margin-top:6px;">Please wait while we send the offer letter.</p>
      </div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
var CANDIDATE_ID = <?php echo $candidate_id ?: 0; ?>;
var offerData = <?php echo $offer ? json_encode($offer) : 'null'; ?>;
var companyData = <?php echo $cs ? json_encode($cs) : '{}'; ?>;

// ---- TABS ----
function switchOfferTab(name) {
    document.querySelectorAll('.offer-tab-pane').forEach(function(p){ p.style.display='none'; });
    document.querySelectorAll('.tab-btn').forEach(function(b){ b.classList.remove('active'); });
    var pane = document.getElementById('pane-' + name);
    var btn  = document.getElementById('tab-' + name);
    if (pane) pane.style.display = 'block';
    if (btn)  btn.classList.add('active');
    if (name === 'preview') renderPDFPreview(false);
    if (name === 'signed')  renderPDFPreview(true);
}

function openOfferDownload() {
    if (!offerData || !offerData.token) { alert('Please save the offer first.'); return; }
    window.open(window.location.pathname + '?token=' + offerData.token + '&download=1', '_blank');
}

// ---- TOAST ----
function showToast(msg, isError) {
    var tc = document.getElementById('toastCard');
    var ti = document.getElementById('toastIcon');
    var tt = document.getElementById('toastText');
    tc.className = 'toast-card ' + (isError ? 'error' : '') + ' show';
    ti.className = isError ? 'fas fa-exclamation-circle toast-icon' : 'fas fa-check-circle toast-icon';
    tt.innerHTML = msg;
    setTimeout(function() { tc.classList.remove('show'); }, 3500);
}

// ---- CUSTOM FIELDS ----
var cfIndex = <?php echo count($cf_data ?? []); ?>;
function addCustomField() {
    var container = document.getElementById('customFieldsContainer');
    var row = document.createElement('div');
    row.className = 'custom-field-row';
    row.id = 'cfrow_' + cfIndex;
    row.innerHTML = '<input type="text" class="fc cf-heading" placeholder="Heading (e.g. Benefits)">' +
        '<input type="text" class="fc cf-text" placeholder="Value / Description">' +
        '<button type="button" onclick="removeCF(this)" style="padding:8px 12px;border:none;border-radius:8px;background:#fee2e2;color:#ef4444;cursor:pointer;font-weight:700;"><i class="fas fa-trash"></i></button>';
    container.appendChild(row);
    cfIndex++;
}
function removeCF(btn) { btn.closest('.custom-field-row').remove(); }

function getCustomFields() {
    var fields = [];
    document.querySelectorAll('.custom-field-row').forEach(function(row) {
        var h = row.querySelector('.cf-heading').value.trim();
        var t = row.querySelector('.cf-text').value.trim();
        if (h || t) fields.push({ heading: h, text: t });
    });
    return fields;
}

// ---- SAVE OFFER ----
function saveOffer(isDraft, goToPreview) {
    var alertBox = document.getElementById('formAlert');
    var ctc = document.getElementById('f_ctc').value.trim();
    var joining = document.getElementById('f_joining').value.trim();
    if (!ctc || !joining) {
        alertBox.innerHTML = '<div class="alert-err"><i class="fas fa-exclamation-circle"></i> Please fill Offered CTC and Joining Date.</div>';
        return;
    }
    alertBox.innerHTML = '';

    var customFields = getCustomFields();
    $.post(window.location.pathname, {
        ajax_save_offer: 1,
        candidate_id: CANDIDATE_ID,
        candidate_name: document.getElementById('f_cname').value.trim(),
        salutation: document.getElementById('f_salutation').value,
        candidate_address: document.getElementById('f_caddr').value.trim(),
        position: document.getElementById('f_cpos').value.trim(),
        department: document.getElementById('f_cdept').value.trim(),
        offered_ctc: ctc,
        joining_date: joining,
        probation_period: document.getElementById('f_probation').value,
        work_location: document.getElementById('f_location').value,
        reporting_manager: document.getElementById('f_manager').value,
        working_hours: document.getElementById('f_hours').value,
        notice_period: document.getElementById('f_notice').value,
        offer_validity: document.getElementById('f_validity').value,
        custom_fields: JSON.stringify(customFields),
        roles_responsibilities: document.getElementById('f_roles').value,
        terms_conditions: document.getElementById('f_terms').value,
        is_draft: isDraft ? 1 : 0
    }, function(resp) {
        if (resp.success) {
            alertBox.innerHTML = '';
            showToast('Offer ' + (resp.is_revision ? 'revised' : 'saved') + ' successfully! — ' + resp.offer_number);
            
            if (resp.new_token) {
                var baseUrl = window.location.protocol + "//" + window.location.host + window.location.pathname;
                var newLink = baseUrl + "?token=" + resp.new_token;
                if (document.getElementById('offerLinkInput')) {
                    document.getElementById('offerLinkInput').value = newLink;
                }
            }
            
            offerData = offerData || {};
            offerData.offer_number = resp.offer_number;
            offerData.offered_ctc = document.getElementById('f_ctc').value;
            offerData.joining_date = document.getElementById('f_joining').value;
            offerData.probation_period = document.getElementById('f_probation').value;
            offerData.work_location = document.getElementById('f_location').value;
            offerData.reporting_manager = document.getElementById('f_manager').value;
            offerData.working_hours = document.getElementById('f_hours').value;
            offerData.notice_period = document.getElementById('f_notice').value;
            offerData.offer_validity = document.getElementById('f_validity').value;
            offerData.custom_fields = JSON.stringify(customFields);
            offerData.roles_responsibilities = document.getElementById('f_roles').value;
            offerData.terms_conditions = document.getElementById('f_terms').value;
            offerData.candidate_name = document.getElementById('f_cname').value.trim();
            offerData.salutation = document.getElementById('f_salutation').value;
            offerData.candidate_address = document.getElementById('f_caddr').value.trim();
            offerData.position = document.getElementById('f_cpos').value.trim();
            offerData.department = document.getElementById('f_cdept').value.trim();
            if (goToPreview) switchOfferTab('preview');
        } else {
            alertBox.innerHTML = '';
            showToast(resp.message || 'Could not save offer.', true);
        }
    }, 'json');
}

// ---- PDF PREVIEW ----
function renderPDFPreview(isSigned) {
    var boxId = isSigned ? 'signedPreviewBox' : 'pdfPreviewBox';
    var box = document.getElementById(boxId);
    if (!box) return;
    if (!offerData) { box.innerHTML = '<p style="color:var(--muted);text-align:center;padding:30px;">Please save offer details first.</p>'; return; }

    var cs = companyData;
    var o = offerData;
    var isRevision = o.letter_type === 'revision';
    var custom = [];
    try { custom = JSON.parse(o.custom_fields || '[]'); } catch(e){}

    var fields = [
        ['Position', o.position], ['Department', o.department],
        ['Offered CTC', o.offered_ctc],
        ['Joining Date', o.joining_date ? new Date(o.joining_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : ''],
        ['Probation Period', o.probation_period], ['Work Location', o.work_location],
        ['Reporting Manager', o.reporting_manager],
        ['Working Hours', o.working_hours], ['Notice Period', o.notice_period]
    ];

    var logoHTML = cs.company_logo ? '<img src="'+cs.company_logo+'" style="max-height:80px;max-width:200px;object-fit:contain;">' : '';
    var sigHTML = cs.company_signature ? '<img src="'+cs.company_signature+'" style="max-height:80px;max-width:180px;margin-bottom:4px;margin-top:15px;">' : '<div style="height:65px;"></div>';
    var candidateSigHTML = (isSigned && o.candidate_signature) ? '<img src="'+o.candidate_signature+'" style="max-height:80px;max-width:180px;margin-bottom:4px;margin-top:15px;">' : '<div style="height:65px;"></div>';
    
    var letterDate = o.joining_date ? new Date(o.joining_date).toLocaleDateString('en-IN',{day:'2-digit',month:'2-digit',year:'numeric'}) : new Date().toLocaleDateString('en-IN',{day:'2-digit',month:'2-digit',year:'numeric'});
    var joiningDate = o.joining_date ? new Date(o.joining_date).toLocaleDateString('en-IN',{day:'2-digit',month:'2-digit',year:'numeric'}) : '';

    var termsHTML = (o.terms_conditions || '').split('\n').map(function(t) { var tt = t.trim(); if(!tt) return ''; var nb = /^\d+\./.test(tt); if(nb) tt = tt.replace(/^(\d+\.\s*[^:]+:?)/, '<strong>$1</strong>'); return '<li style="margin-bottom:8px; font-size:14px;' + (nb?'list-style:none;margin-left:-20px;':'') + '">' + tt + '</li>'; }).join('');
    var rolesHTML = (o.roles_responsibilities || '').split('\n').map(function(r) { return r.trim() ? '<li style="margin-bottom:8px; font-size:14px;">' + r + '</li>' : ''; }).join('');

    var customHTML = custom.map(function(c) {
        return (c.heading ? '<div class="letter-section-heading">'+c.heading+'</div>' : '') + 
               (c.text ? '<p>'+c.text.replace(/\n/g,'<br>')+'</p>' : '');
    }).join('');

    box.innerHTML = `
    <!-- Letterhead Header -->
    <div class="letter-wave-top">
        <svg viewBox="0 0 1440 100" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M0,0 L1440,0 L1440,30 C900,30 400,100 0,90 Z" fill="#42598a"/>
            <path d="M0,0 L1440,0 L1440,10 C1000,40 500,80 0,60 Z" fill="#0f2557"/>
        </svg>
    </div>
    <div class="letter-header">
        <div class="letter-header-left">
            ${cs.company_phone ? '<span><i class="fas fa-phone-alt"></i> ' + cs.company_phone + '</span>' : ''}
            ${cs.company_email ? '<span><i class="fas fa-envelope"></i> ' + cs.company_email + '</span>' : ''}
            ${cs.company_website ? '<span><i class="fas fa-globe"></i> ' + cs.company_website + '</span>' : ''}
        </div>
        <div class="letter-header-right">
            ${cs.company_logo ? '<img src="'+cs.company_logo+'" style="max-height:140px;max-width:270px;object-fit:contain;display:block;margin-left:auto;">' : ''}
        </div>
    </div>

    <table style="width:100%; border-collapse:collapse; border:none;">
    <thead class="print-only-spacer"><tr><td style="height: 245px; border:none;"></td></tr></thead>
    <tbody><tr><td style="padding: 0; border:none;">
    <!-- Letter Body -->
    <div class="letter-body">
        <!-- From -->
        <div style="margin-bottom: 30px; line-height: 1.6;">
            <div style="font-weight:bold; margin-bottom: 6px;">From</div>
            <div style="font-weight:bold; font-size: 16px;">${cs.company_name || ''}</div>
            ${cs.company_address ? '<div><strong>Registered Office: ' + cs.company_address.trim().replace(/\n/g, '<br>') + '</strong></div>' : ''}
            <div><strong>Email: ${cs.company_email || ''} | Phone: ${cs.company_phone || ''}</strong></div>
            <div><strong>Date: ${letterDate}</strong></div>
        </div>

        <!-- To -->
        <div style="margin-bottom: 25px; line-height: 1.6;">
            <strong>To,</strong><br>
            <strong>${o.salutation || 'Mr.'} ${o.candidate_name}</strong><br>
            ${o.candidate_address ? '<strong>' + o.candidate_address.trim().replace(/\n/g, '<br>') + '</strong><br>' : ''}
            <strong>Phone: ${o.candidate_phone || ''}</strong>
        </div>

        <div class="letter-subject">Subject: ${isRevision ? 'Revised Offer of Employment / Revision of Terms — ' + o.position : 'Offer of Employment for the Position of ' + o.position}</div>

        <p>Dear <strong>${o.salutation || 'Mr.'} ${o.candidate_name}</strong></p>
        ${isRevision ? `
        <p>Further to your employment with <strong>${cs.company_name || 'Abra E-Logistic Pvt. Ltd.'}</strong>, we are pleased to inform you that your terms of employment have been revised as set out below, effective from the date mentioned. This letter supersedes the salary/designation terms of your previous offer letter to the extent revised herein; all other terms and conditions remain unchanged.</p>
        <div style="margin-bottom:20px;border:1px solid #dbeafe;background:#f8faff;border-radius:8px;padding:14px 18px;">
            <strong>Summary of Revision:</strong>
            <table style="width:100%;margin-top:8px;border-collapse:collapse;font-size:13px;">
                <tr><td style="padding:4px 8px;color:#64748b;">Designation</td><td style="padding:4px 8px;">${o.previous_position || '-'} &rarr; <strong>${o.position}</strong></td></tr>
                <tr><td style="padding:4px 8px;color:#64748b;">CTC / Salary</td><td style="padding:4px 8px;">${o.previous_ctc || '-'} &rarr; <strong>${o.offered_ctc}</strong></td></tr>
                <tr><td style="padding:4px 8px;color:#64748b;">Effective From</td><td style="padding:4px 8px;"><strong>${o.revision_effective_date ? new Date(o.revision_effective_date).toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'}) : '-'}</strong></td></tr>
                ${o.revision_reason ? '<tr><td style="padding:4px 8px;color:#64748b;">Reason</td><td style="padding:4px 8px;">' + o.revision_reason + '</td></tr>' : ''}
            </table>
        </div>` : `
        <p>We are pleased to offer you the position of <strong>${o.position}</strong> at <strong>${cs.company_name || 'Abra E-Logistic Pvt. Ltd.'}</strong>. In this role, you will be responsible for performing various <strong>${o.department || 'Procurement'}</strong> activities and managerial tasks, ensuring the smooth logistic operations of the company.</p>`}
        <p>Please find below the ${isRevision ? 'revised ' : ''}terms and conditions of your employment:</p>

        <ol style="padding-left: 20px;">
            ${o.position ? '<li><strong>Position:</strong> '+o.position+'</li>' : ''}
            ${o.reporting_manager ? '<li><strong>Reporting To:</strong> '+o.reporting_manager+'</li>' : ''}
            ${o.work_location ? '<li><strong>Place of Posting:</strong> '+o.work_location+'</li>' : ''}
            ${joiningDate ? '<li><strong>Date of Joining:</strong> '+joiningDate+'</li>' : ''}
            ${o.probation_period ? '<li><strong>Probation Period:</strong> '+o.probation_period+'</li>' : ''}
            ${o.offered_ctc ? '<li><strong>Salary:</strong> '+o.offered_ctc+'</li>' : ''}
            ${o.working_hours ? '<li><strong>Working Hours:</strong> '+o.working_hours+'</li>' : ''}
            ${o.notice_period ? '<li><strong>Notice Period:</strong> '+o.notice_period+'</li>' : ''}
        </ol>

        ${rolesHTML ? '<div style="margin-bottom:25px;"><strong>Roles and Responsibilities:</strong><ul style="margin-top:8px; font-size:18px;">' + rolesHTML + '</ul></div>' : ''}

        ${termsHTML ? '<div style="margin-bottom:25px;"><strong>Terms and Conditions:</strong><ul style="margin-top:8px;padding-left:20px; font-size:18px;">' + termsHTML + '</ul></div>' : ''}

        <div style="margin-bottom:20px;"><strong>Verification:</strong> This offer is subject to successful verification of your credentials, background, and documents.</div>

        ${customHTML}

        <p>We are delighted to welcome you to <strong>${cs.company_name || ''}</strong> and look forward to your valuable contribution to the company's growth and success.</p>
        <p>Please sign and return the duplicate copy of this letter as a token of your acceptance of the above terms and conditions.</p>

        <div class="letter-sig-area">
            <div class="letter-sig-box">
                <div style="height:70px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                    ${cs.company_signature ? '<img src="'+cs.company_signature+'" style="max-height:80px; max-width:180px;">' : ''}
                </div>
                <div class="letter-sig-line" style="margin-top:0;">
                    For ${cs.company_name || ''}<br>
                    <small><strong>Name:</strong> ${cs.signatory_name || 'Authorized Signatory'}</small><br>
                    <small style="font-weight:400;"><strong>Designation:</strong> ${cs.signatory_designation || ''}</small>
                </div>
            </div>
            <div class="letter-sig-box">
                <div style="height:70px; display:flex; align-items:flex-end; justify-content:center; margin-bottom:5px;">
                    ${(isSigned && o.candidate_signature) ? '<img src="'+o.candidate_signature+'" style="max-height:80px; max-width:180px;">' : ''}
                </div>
                <div class="letter-sig-line" style="margin-top:0;">
                    Accepted and Agreed<br>
                    <small>${o.candidate_name}</small><br>
                    <small style="font-weight:400;">${isSigned ? letterDate : ''}</small>
                </div>
            </div>
        </div>
        </td></tr></tbody>
        <tfoot class="print-only-spacer-foot"><tr><td style="height: 100px; border:none;"></td></tr></tfoot>
        </table>
        <div class="letter-wave-bottom">
            <svg viewBox="0 0 1440 120" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M0,120 L1440,120 L1440,30 C1000,110 500,120 0,80 Z" fill="#42598a"/>
                <path d="M0,120 L1440,120 L1440,60 C900,130 400,90 0,110 Z" fill="#0f2557"/>
            </svg>
        </div>
    </div>
    `;
}

// ---- SEND EMAIL ----
function sendEmail() {
    var to = document.getElementById('sendEmailTo').value.trim();
    var subj = document.getElementById('sendEmailSubject').value.trim();
    var body = document.getElementById('sendEmailBody').value.trim();
    if (!to) { alert('Please enter recipient email.'); return; }
    if (!offerData) { alert('Please save the offer first.'); return; }

    if (!confirm('Are you sure you want to send the offer letter email to ' + to + '?')) return;

    $('#emailSendingModal').modal('show');

    $.post(window.location.pathname, {
        ajax_send_email: 1,
        candidate_id: CANDIDATE_ID,
        offer_id: offerData.id,
        to: to, subject: subj, body: body
    }, function(resp) {
        $('#emailSendingModal').modal('hide');
        setTimeout(function() {
            if (resp.success) {
                markSent();
                showToast('Email sent successfully!');
            } else {
                showToast(resp.message || 'Could not send email.', true);
            }
        }, 400); // wait for modal hide animation
    }, 'json').fail(function() {
        $('#emailSendingModal').modal('hide');
        setTimeout(function() {
            showToast('Server error while sending email.', true);
        }, 400);
    });
}

function markSent() {
    if (!offerData || !offerData.id) return;
    $.post(window.location.pathname, { ajax_mark_sent: 1, offer_id: offerData.id }, function(){}, 'json');
}

function copyOfferLink() {
    var box = document.getElementById('offerLinkBox');
    box.select(); document.execCommand('copy');
    alert('Link copied!');
}

// ---- COMPANY SETTINGS ----
function saveCompanySettings() {
    var form = document.getElementById('companySettingsForm');
    var fd = new FormData(form);
    fd.append('ajax_save_company_settings', '1');
    var alertBox = document.getElementById('settingsAlert');
    alertBox.innerHTML = '<div class="alert-ok"><i class="fas fa-spinner fa-spin"></i> Saving...</div>';
    $.ajax({ url: window.location.href, type: 'POST', data: fd, processData: false, contentType: false,
        success: function(resp) {
            alertBox.innerHTML = '';
            if (resp.success) {
                showToast('Company settings saved successfully!');
                setTimeout(function(){ window.location.reload(); }, 1500);
            } else {
                showToast('Could not save settings.', true);
            }
        }, dataType: 'json'
    });
}
</script>

<?php
// ============================================================
// AJAX: SEND EMAIL (PHP mail)
// ============================================================
if (isset($_POST['ajax_send_email'])) {
    header('Content-Type: application/json');
    $to      = filter_var($_POST['to'] ?? '', FILTER_SANITIZE_EMAIL);
    $subject = strip_tags($_POST['subject'] ?? 'Offer Letter');
    $body_text = strip_tags($_POST['body'] ?? '');
    $offer_id = intval($_POST['offer_id'] ?? 0);

    $offer_data = mysqli_fetch_assoc(mysqli_query($con, "SELECT candidate_name, position, candidate_id, employee_id FROM hr_offer_letters WHERE id=$offer_id"));
    $cname = $offer_data ? htmlspecialchars($offer_data['candidate_name']) : 'View Offer';

    // Resolve company the same way the public offer-view page does: try the
    // candidate_id path first, then fall back to employee_id for revisions,
    // rather than trusting a candidate_id POST field revision sends never include.
    $cs_s = getCompanySettings($con, intval($_POST['candidate_id'] ?? $offer_data['candidate_id'] ?? 0));
    if (empty($cs_s) && !empty($offer_data['employee_id'])) {
        $cs_s = getCompanySettingsForEmployee($con, $offer_data['employee_id']);
    }

    // Send as plain text without UI wrappers
    $final_body = $body_text;

    $result = sendCompanyMail($con, $cs_s['company_id'] ?? 0, $to, $subject, $final_body);
    $sent = $result['success'];

    if ($sent && $offer_id) {
        mysqli_query($con, "UPDATE hr_offer_letters SET status='sent', sent_at=NOW() WHERE id=$offer_id AND status NOT IN ('accepted', 'declined')");
    } if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode(['success' => $sent, 'message' => $result['message']]);
    exit;
}

// ============================================================
// AJAX: MARK AS HIRED
// ============================================================
if (isset($_POST['ajax_mark_hired'])) {
    header('Content-Type: application/json');
    $cid = intval($_POST['candidate_id']);
    mysqli_query($con, "UPDATE hr_screenings SET hr_decision='hired', updated_at=NOW() WHERE id=$cid"); if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode(['success' => true]);
    exit;
}
?>

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
<?php if (ob_get_level() > 0) { ob_end_flush(); } ?>