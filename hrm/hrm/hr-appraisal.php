<?php
// =========================================================================
// HR APPRAISAL & INCREMENT MANAGEMENT
// =========================================================================
// - Manager-performance based salary review (self-review tables excluded)
// - Department -> Position cascading filter (derived live from hr_employees)
// - Company filter (same pattern as hr-payroll.php)
// - AJAX Give Appraisal with live Preview, toast notification on save
// - Full CRUD on appraisal history: View / Edit / Delete
// - Public certificate page (token-based, no login required) for sharing
// - WhatsApp + Email "Notify Employee" panel with warm congratulatory
//   message + certificate link, sent using employee's own contact info
// - Company branding (logo/signatory) resolved from the employee's own
//   hr_employees.company_name, same convention as Payroll
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 0);
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

date_default_timezone_set('Asia/Kolkata');

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require_once('requirelanguage.php');

$con = conexion();
if (!$con) die("Database connection failed");
mysqli_set_charset($con, 'utf8mb4');

// =========================================================================
// SMTP CONFIG (authenticated sending — replaces unreliable raw mail())
// Fill in SMTP_PASS with the real mailbox password for support@abra-logistic.com
// =========================================================================
define('SMTP_HOST', 'mail.abra-logistic.com');
define('SMTP_PORT', 465);
define('SMTP_SECURE', 'ssl'); // ssl = port 465, tls = port 587
define('SMTP_USER', 'support@abra-logistic.com');
define('SMTP_PASS', 'support@12345');
define('SMTP_FROM_NAME_DEFAULT', 'Abra HR');

$PHPMAILER_AVAILABLE = false;
$pm1 = __DIR__ . '/PHPMailer/src/Exception.php';
$pm2 = __DIR__ . '/PHPMailer/src/PHPMailer.php';
$pm3 = __DIR__ . '/PHPMailer/src/SMTP.php';
if (file_exists($pm1) && file_exists($pm2) && file_exists($pm3)) {
    require_once($pm1);
    require_once($pm2);
    require_once($pm3);
    $PHPMAILER_AVAILABLE = true;
}

function sendSmtpMail($to_list, $subject, $body_text, $from_name = null) {
    global $PHPMAILER_AVAILABLE;

    // Fallback: PHPMailer folder not uploaded yet — use plain mail() so the
    // page never crashes, just less reliable delivery until folder is added.
    if (!$PHPMAILER_AVAILABLE) {
        $to = implode(',', array_filter((array)$to_list, function($e){ return filter_var(trim($e), FILTER_VALIDATE_EMAIL); }));
        if (!$to) return ['success' => false, 'message' => 'No valid email address found.'];
        $headers = "From: " . ($from_name ?: SMTP_FROM_NAME_DEFAULT) . " <" . SMTP_USER . ">\r\nReply-To: " . SMTP_USER . "\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n";
        $sent = @mail($to, $subject, $body_text, $headers);
        return ['success' => $sent, 'message' => $sent ? 'Email sent (via fallback mail() — upload the PHPMailer folder for reliable SMTP sending).' : 'mail() returned false.'];
    }

    $mail = new \PHPMailer\PHPMailer\PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host       = SMTP_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = SMTP_USER;
        $mail->Password   = SMTP_PASS;
        $mail->SMTPSecure = SMTP_SECURE === 'ssl' ? \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS : \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = SMTP_PORT;
        $mail->CharSet    = 'UTF-8';

        $mail->setFrom(SMTP_USER, $from_name ?: SMTP_FROM_NAME_DEFAULT);
        foreach ((array)$to_list as $to) {
            $to = trim($to);
            if ($to !== '' && filter_var($to, FILTER_VALIDATE_EMAIL)) $mail->addAddress($to);
        }
        $mail->addReplyTo(SMTP_USER, $from_name ?: SMTP_FROM_NAME_DEFAULT);

        $mail->isHTML(false);
        $mail->Subject = $subject;
        $mail->Body    = $body_text;

        $mail->send();
        return ['success' => true, 'message' => 'Email sent.'];
    } catch (\Exception $e) {
        return ['success' => false, 'message' => 'SMTP Error: ' . $mail->ErrorInfo];
    }
}

// Public certificate links bypass login (cert_token gate, same convention
// as the candidate offer-letter token gate)
if (!isset($_GET['cert_token'])) {
    if (function_exists('isUser')) isUser();
}

$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// ENSURE TABLES / COLUMNS EXIST
// =========================================================================
mysqli_query($con, "CREATE TABLE IF NOT EXISTS hr_appraisals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id VARCHAR(50) NOT NULL,
    employee_name VARCHAR(200) NOT NULL,
    department VARCHAR(150),
    position VARCHAR(150),
    company_name VARCHAR(255) DEFAULT NULL,
    review_period_start DATE NULL,
    review_period_end DATE NULL,
    avg_performance_score DECIMAL(6,2) DEFAULT NULL,
    performance_review_count INT DEFAULT 0,
    old_salary DECIMAL(12,2) NOT NULL DEFAULT 0,
    new_salary DECIMAL(12,2) NOT NULL DEFAULT 0,
    increment_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    increment_percentage DECIMAL(7,2) NOT NULL DEFAULT 0,
    increment_mode ENUM('percentage','amount') DEFAULT 'percentage',
    input_value DECIMAL(12,2) DEFAULT 0,
    appraisal_type VARCHAR(100) DEFAULT 'Annual Increment',
    remarks TEXT,
    cert_token VARCHAR(64) DEFAULT NULL,
    created_by VARCHAR(150),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_employee (employee_id),
    INDEX idx_created (created_at),
    INDEX idx_token (cert_token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Safe-add columns in case table already existed from an earlier version
function ensureColumn($con, $table, $col, $definition) {
    $c = mysqli_query($con, "SHOW COLUMNS FROM `$table` LIKE '$col'");
    if (!$c || mysqli_num_rows($c) == 0) {
        mysqli_query($con, "ALTER TABLE `$table` ADD COLUMN $col $definition");
    }
}
ensureColumn($con, 'hr_appraisals', 'company_name', "VARCHAR(255) DEFAULT NULL AFTER position");
ensureColumn($con, 'hr_appraisals', 'cert_token', "VARCHAR(64) DEFAULT NULL");
ensureColumn($con, 'hr_appraisals', 'input_value', "DECIMAL(12,2) DEFAULT 0");

// =========================================================================
// HELPERS
// =========================================================================
function getPerfStyle($s) {
    if ($s === null) return ['r' => 'No Data', 'c' => '#94a3b8', 'bg' => '#f1f5f9', 'icon' => '➖'];
    if ($s == -1) return ['r' => 'On Leave', 'c' => '#64748b', 'bg' => '#f1f5f9', 'icon' => '🏖️'];
    if ($s >= 95) return ['r' => 'Significant', 'c' => '#0f766e', 'bg' => '#ccfbf1', 'icon' => '💎'];
    if ($s >= 90) return ['r' => 'Outstanding', 'c' => '#059669', 'bg' => '#ecfdf5', 'icon' => '🏆'];
    if ($s >= 85) return ['r' => 'Excellent',   'c' => '#10b981', 'bg' => '#d1fae5', 'icon' => '⭐'];
    if ($s >= 80) return ['r' => 'Good',        'c' => '#2563eb', 'bg' => '#eff6ff', 'icon' => '✨'];
    if ($s >= 70) return ['r' => 'Average',     'c' => '#d97706', 'bg' => '#fffbeb', 'icon' => '👍'];
    return ['r' => 'Poor', 'c' => '#dc2626', 'bg' => '#fef2f2', 'icon' => '🚫'];
}

function getManagerPerformance($con, $employee_id, $f_start, $f_end) {
    $eid = mysqli_real_escape_string($con, $employee_id);
    $tables = [
        ['tbl' => 'performance_weekly_manager',     'date' => 'week_start_date'],
        ['tbl' => 'performance_monthly_manager',    'date' => 'review_month'],
        ['tbl' => 'performance_quarterly_manager',  'date' => 'review_quarter'],
        ['tbl' => 'performance_halfyearly_manager', 'date' => 'review_halfyear'],
        ['tbl' => 'performance_yearly_manager',     'date' => 'review_year'],
    ];
    $total_score = 0; $count = 0;
    foreach ($tables as $t) {
        $sql = "SELECT total_score FROM `{$t['tbl']}` WHERE employee_id='$eid'";
        if (!empty($f_start)) {
            if ($t['date'] == 'review_month') $sql .= " AND {$t['date']} >= '" . date('Y-m', strtotime($f_start)) . "'";
            elseif (in_array($t['date'], ['review_quarter','review_halfyear','review_year'])) $sql .= " AND {$t['date']} >= '" . date('Y', strtotime($f_start)) . "'";
            else $sql .= " AND {$t['date']} >= '$f_start'";
        }
        if (!empty($f_end)) {
            if ($t['date'] == 'review_month') $sql .= " AND {$t['date']} <= '" . date('Y-m', strtotime($f_end)) . "'";
            elseif (in_array($t['date'], ['review_quarter','review_halfyear','review_year'])) $sql .= " AND {$t['date']} <= '" . date('Y', strtotime($f_end)) . "'";
            else $sql .= " AND {$t['date']} <= '$f_end'";
        }
        $q = mysqli_query($con, $sql);
        if ($q) while ($row = mysqli_fetch_assoc($q)) {
            $score = floatval($row['total_score']);
            if ($score < 0) continue;
            $total_score += $score; $count++;
        }
    }
    return ['avg' => $count > 0 ? round($total_score / $count, 2) : null, 'count' => $count];
}

function calcBasic($gross) { return round(floatval($gross) * 0.40, 2); }

function getCompanyBranding($con, $company_name) {
    $cn = mysqli_real_escape_string($con, trim($company_name ?: ''));

    // Primary source: hr_offer_company_settings — this table has a REAL,
    // working company_email already configured (proven by offer-letter
    // emails sending successfully), unlike hr_companies which typically
    // only stores logo_path and has no verified sending email.
    if ($cn !== '') {
        $q = mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE TRIM(company_name)='$cn' LIMIT 1");
        $r = $q ? mysqli_fetch_assoc($q) : null;
        if (!$r) {
            $q2 = mysqli_query($con, "SELECT * FROM hr_offer_company_settings WHERE LOWER(TRIM(company_name))=LOWER('$cn') LIMIT 1");
            $r = $q2 ? mysqli_fetch_assoc($q2) : null;
        }
        if ($r && !empty($r['company_email'])) {
            // Fill in a logo if this settings row doesn't have one but hr_companies does
            if (empty($r['company_logo'])) {
                $lq = mysqli_query($con, "SELECT logo_path FROM hr_companies WHERE TRIM(company_name)='$cn' LIMIT 1");
                if ($lq && mysqli_num_rows($lq) > 0) {
                    $lp = mysqli_fetch_assoc($lq)['logo_path'];
                    if (!empty($lp)) $r['company_logo'] = $lp;
                }
            }
            $r['logo_path'] = $r['company_logo'] ?? null; // normalize key name used by certificate renderer
            return $r;
        }
    }

    // Fallback: hr_companies (logo only — no verified email here)
    if ($cn !== '') {
        $q = mysqli_query($con, "SELECT * FROM hr_companies WHERE TRIM(company_name)='$cn' LIMIT 1");
        $r = $q ? mysqli_fetch_assoc($q) : null;
        if ($r) return $r;
    }
    return ['company_name' => $company_name ?: 'Abra E Logistics Private Limited', 'logo_path' => null, 'company_email' => null];
}

function buildNotifyMessages($emp_name, $old_salary, $new_salary, $incr_pct, $incr_amt, $appraisal_type, $cert_link, $company_name) {
    $old_f = number_format($old_salary, 2);
    $new_f = number_format($new_salary, 2);
    $pct_f = ($incr_pct >= 0 ? '+' : '') . number_format($incr_pct, 2);
    $amt_f = ($incr_amt >= 0 ? '+' : '') . number_format($incr_amt, 2);

    $whatsapp_text = "Hi {$emp_name}! 🎉\n\nWe're thrilled to share some great news — your hard work and dedication have been recognized!\n\nYour salary has been revised as part of a *{$appraisal_type}*:\n₹{$old_f} → *₹{$new_f}* ({$pct_f}%)\n\nCongratulations, and thank you for all your contributions to *{$company_name}*. Keep up the excellent work!\n\nYou can view your increment certificate here:\n{$cert_link}";

    $email_subject = "Congratulations! Your Salary Has Been Revised — {$company_name}";

    $email_body = "Dear {$emp_name},\n\nWe are delighted to inform you that, in recognition of your performance and contribution, your salary has been revised.\n\nAppraisal Type: {$appraisal_type}\nPrevious Salary: ₹{$old_f}\nRevised Salary: ₹{$new_f}\nIncrement: ₹{$amt_f} ({$pct_f}%)\n\nThis reflects the value you bring to {$company_name}, and we look forward to your continued growth with us.\n\nYou can view and download your increment certificate using the link below:\n{$cert_link}\n\nCongratulations once again, and thank you for your continued dedication!\n\nWarm regards,\nHuman Resources\n{$company_name}";

    return ['whatsapp' => $whatsapp_text, 'subject' => $email_subject, 'body' => $email_body];
}

// =========================================================================
// PUBLIC CERTIFICATE VIEW (via cert_token — no login required)
// =========================================================================
if (isset($_GET['view']) && $_GET['view'] === 'certificate' && isset($_GET['cert_token'])) {
    $token = mysqli_real_escape_string($con, $_GET['cert_token']);
    $q = mysqli_query($con, "SELECT * FROM hr_appraisals WHERE cert_token='$token' LIMIT 1");
    $appraisal = $q ? mysqli_fetch_assoc($q) : null;
    if (!$appraisal) die("<div style='padding:60px;text-align:center;font-family:Arial,sans-serif;'><h3>Invalid or expired certificate link.</h3></div>");
    render_appraisal_certificate($con, $appraisal);
    exit;
}

function render_appraisal_certificate($con, $a) {
    $cs = getCompanyBranding($con, $a['company_name']);
    $logo_html = '';
    if (!empty($cs['logo_path']) && file_exists($cs['logo_path'])) {
        $logo_html = '<img src="' . htmlspecialchars($cs['logo_path']) . '" style="max-height:140px;max-width:380px;object-fit:contain;margin:0 auto 14px;display:block;">';
    }
    $style = getPerfStyle($a['avg_performance_score'] !== null ? floatval($a['avg_performance_score']) : null);
    $pct_display = ($a['increment_percentage'] >= 0 ? '+' : '') . number_format($a['increment_percentage'], 2) . '%';
    $date_display = date('d F Y', strtotime($a['created_at']));
    ?>
    <!DOCTYPE html>
    <html><head><meta charset="utf-8">
    <title>Appraisal Certificate — <?php echo htmlspecialchars($a['employee_name']); ?></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@400;700&family=Poppins:wght@400;500;600;700;800&family=Dancing+Script:wght@700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:'Poppins',sans-serif;background:linear-gradient(135deg,#1e3a8a,#0f2557);padding:50px 20px;}
    .cert-page{max-width:950px;margin:0 auto;background:#fdfbf6;padding:0;box-shadow:0 30px 80px rgba(0,0,0,.4);position:relative;border-radius:6px;overflow:hidden;}
    .cert-outer-border{border:10px solid #0f2557;margin:14px;position:relative;background:
        repeating-linear-gradient(135deg, rgba(212,175,55,0.04) 0px, rgba(212,175,55,0.04) 2px, transparent 2px, transparent 40px),
        #fdfbf6;
    }
    .cert-gold-line{border:2px solid #d4af37;margin:6px;padding:46px 50px;position:relative;}

    /* Corner ornaments */
    .corner{position:absolute;width:70px;height:70px;border:3px solid #d4af37;}
    .corner.tl{top:-2px;left:-2px;border-right:none;border-bottom:none;}
    .corner.tr{top:-2px;right:-2px;border-left:none;border-bottom:none;}
    .corner.bl{bottom:-2px;left:-2px;border-right:none;border-top:none;}
    .corner.br{bottom:-2px;right:-2px;border-left:none;border-top:none;}

    .cert-ribbon{display:inline-block;background:linear-gradient(135deg,#d4af37,#b8860b);color:#fff;font-size:11px;font-weight:800;letter-spacing:3px;text-transform:uppercase;padding:7px 26px;border-radius:20px;box-shadow:0 4px 10px rgba(184,134,11,.4);margin-bottom:18px;}

    .cert-co{font-family:'Cinzel',serif;font-size:21px;font-weight:700;color:#0f2557;letter-spacing:2px;text-align:center;}
    .cert-title{font-family:'Cinzel',serif;font-size:38px;font-weight:700;color:#0f2557;margin:14px 0 4px;text-transform:uppercase;letter-spacing:3px;text-align:center;text-shadow:1px 1px 0 #d4af37;}
    .cert-title-underline{width:160px;height:3px;background:linear-gradient(90deg,transparent,#d4af37,transparent);margin:0 auto 20px;}
    .cert-sub{font-size:13px;color:#92400e;background:#fef3c7;display:inline-block;padding:4px 18px;border-radius:14px;text-transform:uppercase;letter-spacing:2px;font-weight:700;margin-bottom:28px;}
    .cert-sub-wrap{text-align:center;}

    .cert-name{font-family:'Cinzel',serif;font-size:42px;font-weight:700;color:#0f172a;display:inline-block;padding:0 10px 12px;margin-bottom:22px;position:relative;}
    .cert-name::after{content:'';position:absolute;bottom:0;left:50%;transform:translateX(-50%);width:80%;height:3px;background:linear-gradient(90deg,transparent,#d4af37,transparent);}
    .cert-name-wrap{text-align:center;}

    .cert-msg{font-size:15px;color:#334155;line-height:1.85;max-width:680px;margin:0 auto 24px;text-align:center;}

    .seal-wrap{display:flex;justify-content:center;margin:14px 0 8px;}
    .seal{width:120px;height:120px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#f4d35e,#d4af37 55%,#b8860b 100%);display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:0 8px 20px rgba(184,134,11,.45),inset 0 0 0 4px rgba(255,255,255,.35),inset 0 0 0 8px rgba(184,134,11,.5);position:relative;}
    .seal i{font-size:34px;color:#fff;text-shadow:0 2px 4px rgba(0,0,0,.2);}
    .seal-pct{font-size:13px;font-weight:800;color:#5a3e00;margin-top:2px;}

    .salary-flow{display:flex;align-items:center;justify-content:center;gap:24px;margin:24px 0 18px;flex-wrap:wrap;}
    .sf-box{background:#fff;border:2px solid #e2e8f0;border-radius:14px;padding:18px 30px;min-width:170px;box-shadow:0 4px 10px rgba(0,0,0,.04);}
    .sf-box.new{background:linear-gradient(135deg,#ecfdf5,#d1fae5);border-color:#10b981;}
    .sf-label{font-size:11px;font-weight:700;text-transform:uppercase;color:#64748b;letter-spacing:1px;}
    .sf-value{font-size:23px;font-weight:800;color:#1e293b;margin-top:5px;}
    .sf-box.new .sf-value{color:#059669;}
    .sf-arrow{font-size:26px;color:#d4af37;}

    .pct-badge-wrap{text-align:center;margin-bottom:8px;}
    .pct-badge{display:inline-block;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;padding:9px 30px;border-radius:30px;font-weight:800;font-size:19px;box-shadow:0 6px 16px rgba(15,37,87,.35);letter-spacing:.5px;}

    .cert-meta-wrap{text-align:center;margin:24px 0 8px;}
    .cert-meta{font-size:12.5px;color:#64748b;display:inline-block;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:10px 22px;}

    .cert-sig-area{display:flex;justify-content:center;margin-top:42px;text-align:center;}
    .sig-block{width:300px;text-align:center;border-top:1px dashed #d4af37;padding-top:14px;}
    .sig-script{font-family:'Dancing Script',cursive;font-size:32px;color:#0f2557;}
    .sig-line{border-top:2px solid #0f2557;margin-top:8px;padding-top:7px;font-size:12px;font-weight:700;color:#0f2557;}

    .no-print{text-align:center;margin-bottom:20px;}
    .no-print button{padding:13px 28px;background:#0f2557;color:#fff;border:none;border-radius:10px;font-weight:700;cursor:pointer;font-family:inherit;font-size:14px;box-shadow:0 4px 14px rgba(15,37,87,.3);}
    @media print{ body{background:#fff;padding:0;} .no-print{display:none!important;} .cert-page{box-shadow:none;margin:0;} }
    </style>
    </head><body>
    <div class="no-print">
        <button onclick="downloadCert()"><i class="fas fa-download"></i> Download as Image</button>
        <button onclick="window.print()" style="margin-left:10px;background:#475569;"> Print / Save as PDF</button>
    </div>
    <div class="cert-page" id="certBox">
        <div class="cert-outer-border">
            <div class="cert-gold-line">
                <div class="corner tl"></div><div class="corner tr"></div><div class="corner bl"></div><div class="corner br"></div>

                <?php echo $logo_html; ?>
                <div class="cert-co"><?php echo strtoupper(htmlspecialchars($cs['company_name'] ?? '')); ?></div>
                <div class="cert-title">Certificate of Appraisal</div>
                <div class="cert-title-underline"></div>
                <div class="cert-sub-wrap"><span class="cert-sub"><?php echo htmlspecialchars($a['appraisal_type']); ?></span></div>

                <div class="cert-msg">This is to certify that</div>
                <div class="cert-name-wrap"><div class="cert-name"><?php echo strtoupper(htmlspecialchars($a['employee_name'])); ?></div></div>
                <div class="cert-msg">has been awarded a salary increment in recognition of outstanding performance and valuable contribution towards the organization's continued growth and success.</div>

                <div class="seal-wrap">
                    <div class="seal">
                        <i class="fas fa-award"></i>
                        <div class="seal-pct"><?php echo $pct_display; ?></div>
                    </div>
                </div>

                <div class="salary-flow">
                    <div class="sf-box"><div class="sf-label">Previous Salary</div><div class="sf-value">₹<?php echo number_format($a['old_salary'],2); ?></div></div>
                    <div class="sf-arrow">&#10142;</div>
                    <div class="sf-box new"><div class="sf-label">Revised Salary</div><div class="sf-value">₹<?php echo number_format($a['new_salary'],2); ?></div></div>
                </div>
                <div class="pct-badge-wrap"><span class="pct-badge"><?php echo $pct_display; ?> Increment &nbsp;(₹<?php echo number_format($a['increment_amount'],2); ?>)</span></div>

                <div class="cert-meta-wrap">
                    <div class="cert-meta">
                        <i class="fas fa-building"></i> <?php echo htmlspecialchars($a['department']); ?> &nbsp;&middot;&nbsp;
                        <i class="fas fa-id-badge"></i> <?php echo htmlspecialchars($a['position']); ?> &nbsp;&middot;&nbsp;
                        <i class="far fa-calendar-alt"></i> <?php echo $date_display; ?>
                        <?php if ($a['avg_performance_score'] !== null): ?>
                        <br><i class="fas fa-star" style="color:#d4af37;"></i> Performance Rating: <?php echo $style['icon'].' '.$style['r']; ?> (<?php echo $a['avg_performance_score']; ?>%)
                        <?php endif; ?>
                    </div>
                </div>

                <div class="cert-sig-area">
                    <div class="sig-block">
                        <div class="sig-script"><?php echo htmlspecialchars($cs['signatory_name'] ?? 'Abishek Veeraswamy'); ?></div>
                        <div class="sig-line"><?php echo htmlspecialchars($cs['signatory_name'] ?? 'Authorized Signatory'); ?><br>
                        <small style="font-weight:400;"><?php echo htmlspecialchars($cs['signatory_designation'] ?? 'Managing Director'); ?></small></div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <script>
    function downloadCert(){
        html2canvas(document.getElementById('certBox'), {scale:2, useCORS:true, backgroundColor:'#ffffff'}).then(function(canvas){
            var link = document.createElement('a');
            link.download = 'Appraisal_Certificate_<?php echo preg_replace('/[^A-Za-z0-9]/','_',$a['employee_name']); ?>.jpg';
            link.href = canvas.toDataURL('image/jpeg', 0.92);
            link.click();
        });
    }
    </script>
    </body></html>
    <?php
}

// =========================================================================
// AUTHORIZATION — Admin / HR / Management / MD only
// =========================================================================
$employee_id = ''; $employee_name_db = ''; $employee_department = ''; $employee_position = '';
if (!empty($currentUserName)) {
    $ns  = mysqli_real_escape_string($con, $currentUserName);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$ns%') AND LOWER(status)='active' LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name_db = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
    }
}
$is_management_dept = (stripos($employee_department, 'Management') !== false);
$is_hr_dept = (stripos($employee_department, 'Human Resources') !== false);
$is_managing_director = (stripos($employee_position, 'managing director') !== false || stripos($employee_position, 'md') !== false || stripos($employee_position, 'ceo') !== false);
$is_abishek = (stripos($employee_name_db, 'abishek') !== false || stripos($currentUserName, 'abishek') !== false);
$is_keerthi = (stripos($employee_name_db, 'keerti') !== false || stripos($employee_name_db, 'keerthi') !== false || stripos($currentUserName, 'keerti') !== false || stripos($currentUserName, 'keerthi') !== false);
$isAdmin = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_abishek || $is_keerthi);
$dashboard_url = $is_abishek ? '/dashboard/index.php' : '/dashboard/raise-a-ticket.php';

if (!$isAdmin) {
    die("<div style='font-family:Poppins,Arial;text-align:center;margin-top:100px;'>
        <h2 style='color:#dc2626;'>Access Denied</h2>
        <p>You do not have permission to access the Appraisal &amp; Increment module.</p>
        <p><a href='".$dashboard_url."'>&larr; Back to Dashboard</a></p></div>");
}

$base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS']==='on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
$script_path = $base_url . $_SERVER['PHP_SELF'];

// =========================================================================
// ADMIN VIEW OF CERTIFICATE (by id, requires login — for History modal link)
// =========================================================================
if (isset($_GET['view']) && $_GET['view'] === 'certificate' && isset($_GET['id'])) {
    $aid = intval($_GET['id']);
    $q = mysqli_query($con, "SELECT * FROM hr_appraisals WHERE id=$aid LIMIT 1");
    $appraisal = $q ? mysqli_fetch_assoc($q) : null;
    if (!$appraisal) die("Appraisal record not found.");
    render_appraisal_certificate($con, $appraisal);
    exit;
}

// =========================================================================
// APPRAISAL TYPE OPTIONS
// =========================================================================
$appraisal_types = [
    'Annual Increment', 'Performance-Based Increment', 'Promotion', 'Grade / Band Change',
    'Probation Confirmation Increment', 'Retention Bonus / Counter Offer',
    'Special / Ad-hoc Increment', 'Salary Correction / Adjustment', 'Other'
];

// =========================================================================
// AJAX: GIVE APPRAISAL (save)
// =========================================================================
if (isset($_POST['ajax_give_appraisal'])) {
    header('Content-Type: application/json');
    $target_id   = mysqli_real_escape_string($con, $_POST['target_employee_id']);
    $mode        = ($_POST['increment_mode'] === 'amount') ? 'amount' : 'percentage';
    $input_value = floatval($_POST['increment_value']);
    $appraisal_type = mysqli_real_escape_string($con, $_POST['appraisal_type']);
    $remarks     = mysqli_real_escape_string($con, trim($_POST['remarks']));
    $period_start = !empty($_POST['period_start']) ? mysqli_real_escape_string($con, $_POST['period_start']) : null;
    $period_end   = !empty($_POST['period_end'])   ? mysqli_real_escape_string($con, $_POST['period_end'])   : null;

    $emp_q = mysqli_query($con, "SELECT id, name, department, position, salary, company_name, phone, alt_phone, email, personal_email FROM hr_employees WHERE employee_id='$target_id' AND LOWER(status)='active' LIMIT 1");
    if (!$emp_q || mysqli_num_rows($emp_q) == 0) { echo json_encode(['success'=>false,'message'=>'Employee not found or inactive.']); exit; }
    $emp = mysqli_fetch_assoc($emp_q);
    $old_salary = floatval($emp['salary']);
    $dept = $emp['department'] ?: 'General';
    $posn = $emp['position'] ?: 'General';
    $company_name = $emp['company_name'] ?: '';

    if ($old_salary <= 0) { echo json_encode(['success'=>false,'message'=>"Employee's current salary is ₹0. Please set a base salary first."]); exit; }

    if ($mode === 'percentage') {
        $increment_percentage = $input_value;
        $increment_amount     = round($old_salary * ($input_value / 100), 2);
    } else {
        $increment_amount     = $input_value;
        $increment_percentage = round(($input_value / $old_salary) * 100, 2);
    }
    $new_salary = round($old_salary + $increment_amount, 2);
    if ($new_salary <= 0) { echo json_encode(['success'=>false,'message'=>'Resulting new salary must be greater than ₹0.']); exit; }

    $perf = getManagerPerformance($con, $target_id, $period_start, $period_end);
    $avg_score_sql = ($perf['avg'] !== null) ? floatval($perf['avg']) : 'NULL';
    $perf_count = intval($perf['count']);
    $period_start_sql = $period_start ? "'$period_start'" : 'NULL';
    $period_end_sql   = $period_end   ? "'$period_end'"   : 'NULL';
    $created_by = mysqli_real_escape_string($con, $currentUserName);
    $cert_token = bin2hex(random_bytes(24));
    $cname_sql = mysqli_real_escape_string($con, $company_name);
    $emp_name_sql = mysqli_real_escape_string($con, $emp['name']);

    $ins_sql = "INSERT INTO hr_appraisals
        (employee_id, employee_name, department, position, company_name, review_period_start, review_period_end,
         avg_performance_score, performance_review_count, old_salary, new_salary,
         increment_amount, increment_percentage, increment_mode, input_value, appraisal_type, remarks, cert_token, created_by)
        VALUES
        ('$target_id', '$emp_name_sql', '$dept', '$posn', '$cname_sql', $period_start_sql, $period_end_sql,
         $avg_score_sql, $perf_count, $old_salary, $new_salary,
         $increment_amount, $increment_percentage, '$mode', $input_value, '$appraisal_type', '$remarks', '$cert_token', '$created_by')";

    if (!mysqli_query($con, $ins_sql)) { echo json_encode(['success'=>false,'message'=>'DB Error: '.mysqli_error($con)]); exit; }
    $new_id = mysqli_insert_id($con);
    mysqli_query($con, "UPDATE hr_employees SET salary=$new_salary WHERE employee_id='$target_id'");

    $cert_link = $script_path . '?view=certificate&cert_token=' . $cert_token;
    $cs = getCompanyBranding($con, $company_name);
    $msgs = buildNotifyMessages($emp['name'], $old_salary, $new_salary, $increment_percentage, $increment_amount, $appraisal_type, $cert_link, $cs['company_name'] ?? $company_name);

    $phone = !empty($emp['phone']) ? $emp['phone'] : ($emp['alt_phone'] ?? '');
    $phone_clean = preg_replace('/[^0-9]/', '', $phone);
    $emails = array_filter([$emp['email'] ?? '', $emp['personal_email'] ?? '']);

    echo json_encode([
        'success' => true,
        'appraisal_id' => $new_id,
        'old_salary' => number_format($old_salary,2),
        'new_salary' => number_format($new_salary,2),
        'increment_amount' => number_format($increment_amount,2),
        'increment_percentage' => number_format($increment_percentage,2),
        'employee_name' => $emp['name'],
        'cert_link' => $cert_link,
        'whatsapp_text' => $msgs['whatsapp'],
        'email_subject' => $msgs['subject'],
        'email_body' => $msgs['body'],
        'phone_clean' => $phone_clean,
        'emails' => array_values($emails)
    ]);
    exit;
}

// =========================================================================
// AJAX: EDIT APPRAISAL (CRUD - Update)
// =========================================================================
if (isset($_POST['ajax_edit_appraisal'])) {
    header('Content-Type: application/json');
    $aid = intval($_POST['appraisal_id']);
    $mode = ($_POST['increment_mode'] === 'amount') ? 'amount' : 'percentage';
    $input_value = floatval($_POST['increment_value']);
    $appraisal_type = mysqli_real_escape_string($con, $_POST['appraisal_type']);
    $remarks = mysqli_real_escape_string($con, trim($_POST['remarks']));

    $q = mysqli_query($con, "SELECT * FROM hr_appraisals WHERE id=$aid LIMIT 1");
    $rec = $q ? mysqli_fetch_assoc($q) : null;
    if (!$rec) { echo json_encode(['success'=>false,'message'=>'Appraisal record not found.']); exit; }

    $old_salary = floatval($rec['old_salary']); // recalc based on this row's original baseline
    if ($mode === 'percentage') {
        $increment_percentage = $input_value;
        $increment_amount = round($old_salary * ($input_value/100), 2);
    } else {
        $increment_amount = $input_value;
        $increment_percentage = round(($input_value/$old_salary)*100, 2);
    }
    $new_salary = round($old_salary + $increment_amount, 2);
    if ($new_salary <= 0) { echo json_encode(['success'=>false,'message'=>'Resulting new salary must be greater than ₹0.']); exit; }

    mysqli_query($con, "UPDATE hr_appraisals SET
        increment_mode='$mode', input_value=$input_value,
        increment_amount=$increment_amount, increment_percentage=$increment_percentage,
        new_salary=$new_salary, appraisal_type='$appraisal_type', remarks='$remarks'
        WHERE id=$aid");

    // If this is the LATEST appraisal for the employee, sync live salary
    $latest_q = mysqli_query($con, "SELECT id FROM hr_appraisals WHERE employee_id='".mysqli_real_escape_string($con,$rec['employee_id'])."' ORDER BY created_at DESC, id DESC LIMIT 1");
    $latest = $latest_q ? mysqli_fetch_assoc($latest_q) : null;
    $synced_live = false;
    if ($latest && intval($latest['id']) === $aid) {
        mysqli_query($con, "UPDATE hr_employees SET salary=$new_salary WHERE employee_id='".mysqli_real_escape_string($con,$rec['employee_id'])."'");
        $synced_live = true;
    }

    echo json_encode(['success'=>true, 'synced_live'=>$synced_live, 'new_salary'=>number_format($new_salary,2)]);
    exit;
}

// =========================================================================
// AJAX: DELETE APPRAISAL (CRUD - Delete, with salary rollback)
// =========================================================================
if (isset($_POST['ajax_delete_appraisal'])) {
    header('Content-Type: application/json');
    $aid = intval($_POST['appraisal_id']);
    $q = mysqli_query($con, "SELECT * FROM hr_appraisals WHERE id=$aid LIMIT 1");
    $rec = $q ? mysqli_fetch_assoc($q) : null;
    if (!$rec) { echo json_encode(['success'=>false,'message'=>'Appraisal record not found.']); exit; }
    $emp_id_safe = mysqli_real_escape_string($con, $rec['employee_id']);

    $latest_q = mysqli_query($con, "SELECT id FROM hr_appraisals WHERE employee_id='$emp_id_safe' ORDER BY created_at DESC, id DESC LIMIT 1");
    $latest = $latest_q ? mysqli_fetch_assoc($latest_q) : null;
    $was_latest = ($latest && intval($latest['id']) === $aid);

    mysqli_query($con, "DELETE FROM hr_appraisals WHERE id=$aid");

    $reverted_salary = null;
    if ($was_latest) {
        $next_q = mysqli_query($con, "SELECT new_salary FROM hr_appraisals WHERE employee_id='$emp_id_safe' ORDER BY created_at DESC, id DESC LIMIT 1");
        if ($next_q && mysqli_num_rows($next_q) > 0) {
            $reverted_salary = floatval(mysqli_fetch_assoc($next_q)['new_salary']);
        } else {
            $reverted_salary = floatval($rec['old_salary']);
        }
        mysqli_query($con, "UPDATE hr_employees SET salary=$reverted_salary WHERE employee_id='$emp_id_safe'");
    }

    echo json_encode(['success'=>true, 'reverted_salary' => $reverted_salary !== null ? number_format($reverted_salary,2) : null]);
    exit;
}

// =========================================================================
// AJAX: SEND EMAIL NOTIFICATION
// =========================================================================
if (isset($_POST['ajax_send_notify_email'])) {
    header('Content-Type: application/json');
    $to_raw = $_POST['to'] ?? '';
    $emails = array_filter(array_map('trim', explode(',', $to_raw)));
    $emails = array_filter($emails, function($e){ return filter_var($e, FILTER_VALIDATE_EMAIL); });
    if (empty($emails)) { echo json_encode(['success'=>false,'message'=>'No valid email address found.']); exit; }

    $subject = strip_tags($_POST['subject'] ?? 'Salary Revision');
    $body = strip_tags($_POST['body'] ?? '');
    $company_name = mysqli_real_escape_string($con, $_POST['company_name'] ?? '');
    $cs = getCompanyBranding($con, $company_name);
    $from_name  = $cs['company_name'] ?? 'HR Team';

    $result = sendSmtpMail($emails, $subject, $body, $from_name);
    echo json_encode($result);
    exit;
}

// =========================================================================
// AJAX: HISTORY (list)
// =========================================================================
if (isset($_GET['ajax_history'])) {
    header('Content-Type: application/json');
    $eid = mysqli_real_escape_string($con, $_GET['ajax_history']);
    $q = mysqli_query($con, "SELECT * FROM hr_appraisals WHERE employee_id='$eid' ORDER BY created_at DESC, id DESC");

    // Employee contact + branding fetched once (same for every record of this employee)
    $emp_lookup = mysqli_query($con, "SELECT phone, alt_phone, email, personal_email, company_name FROM hr_employees WHERE employee_id='$eid' LIMIT 1");
    $emp_contact = $emp_lookup ? mysqli_fetch_assoc($emp_lookup) : [];
    $phone = !empty($emp_contact['phone']) ? $emp_contact['phone'] : ($emp_contact['alt_phone'] ?? '');
    $phone_clean = preg_replace('/[^0-9]/', '', $phone);
    $emails = array_values(array_filter([$emp_contact['email'] ?? '', $emp_contact['personal_email'] ?? '']));

    $list = [];
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        // Lazy-backfill: older records (saved before cert_token existed) get
        // a token generated on first view, so their certificate link works.
        if (empty($r['cert_token'])) {
            $new_token = bin2hex(random_bytes(24));
            mysqli_query($con, "UPDATE hr_appraisals SET cert_token='$new_token' WHERE id=" . intval($r['id']));
            $r['cert_token'] = $new_token;
        }
        $cert_link = $script_path . '?view=certificate&cert_token=' . $r['cert_token'];
        $company_for_notify = !empty($r['company_name']) ? $r['company_name'] : ($emp_contact['company_name'] ?? '');
        $cs_n = getCompanyBranding($con, $company_for_notify);
        $msgs = buildNotifyMessages($r['employee_name'], floatval($r['old_salary']), floatval($r['new_salary']), floatval($r['increment_percentage']), floatval($r['increment_amount']), $r['appraisal_type'], $cert_link, $cs_n['company_name'] ?? $company_for_notify);

        $list[] = [
            'id' => $r['id'],
            'date' => date('d M Y, h:i A', strtotime($r['created_at'])),
            'type' => $r['appraisal_type'],
            'old_salary' => number_format($r['old_salary'], 2),
            'new_salary' => number_format($r['new_salary'], 2),
            'increment_amount' => number_format($r['increment_amount'], 2),
            'increment_percentage' => number_format($r['increment_percentage'], 2),
            'mode' => $r['increment_mode'],
            'input_value' => $r['input_value'],
            'avg_score' => $r['avg_performance_score'] !== null ? $r['avg_performance_score'] : 'N/A',
            'review_window' => (!empty($r['review_period_start']) && !empty($r['review_period_end'])) ? date('d M Y', strtotime($r['review_period_start'])) . ' - ' . date('d M Y', strtotime($r['review_period_end'])) : 'N/A',
            'remarks' => $r['remarks'],
            'created_by' => $r['created_by'],
            'cert_link' => $cert_link,
            'employee_name' => $r['employee_name'],
            'company_name' => $company_for_notify,
            'whatsapp_text' => $msgs['whatsapp'],
            'email_subject' => $msgs['subject'],
            'email_body' => $msgs['body'],
            'phone_clean' => $phone_clean,
            'emails' => $emails
        ];
    }
    echo json_encode(['success' => true, 'history' => $list]);
    exit;
}

// =========================================================================
// MASTER DATA
// =========================================================================
$depts_master = [];
$rd = mysqli_query($con, "SELECT name FROM hr_departments ORDER BY name ASC");
if ($rd) while ($d = mysqli_fetch_assoc($rd)) $depts_master[] = $d['name'];

$pos_master = [];
$rp = mysqli_query($con, "SELECT title FROM hr_positions ORDER BY title ASC");
if ($rp) while ($p = mysqli_fetch_assoc($rp)) $pos_master[] = $p['title'];

// Cascading Dept -> Position map, derived LIVE from active employees (Option A)
$dept_position_map = [];
$dpq = mysqli_query($con, "SELECT DISTINCT department, position FROM hr_employees WHERE LOWER(status)='active' AND department IS NOT NULL AND department!='' AND position IS NOT NULL AND position!='' ORDER BY department, position");
if ($dpq) while ($r = mysqli_fetch_assoc($dpq)) {
    if (!isset($dept_position_map[$r['department']])) $dept_position_map[$r['department']] = [];
    if (!in_array($r['position'], $dept_position_map[$r['department']])) $dept_position_map[$r['department']][] = $r['position'];
}

// Companies list (same pattern as hr-payroll.php)
$companies_list = [];
$cq = mysqli_query($con, "SELECT DISTINCT company_name FROM hr_employees WHERE LOWER(status)='active' AND company_name IS NOT NULL AND company_name != '' ORDER BY company_name");
if ($cq) while ($c = mysqli_fetch_assoc($cq)) $companies_list[] = $c['company_name'];
$cq2 = mysqli_query($con, "SELECT company_name FROM hr_companies ORDER BY company_name");
if ($cq2) while ($c = mysqli_fetch_assoc($cq2)) if (!in_array($c['company_name'], $companies_list)) $companies_list[] = $c['company_name'];
sort($companies_list);

// =========================================================================
// FILTER VALUES
// =========================================================================
$filter_period_type = isset($_GET['period_type']) ? $_GET['period_type'] : 'this_month';
$filter_dept    = isset($_GET['f_dept']) ? $_GET['f_dept'] : '';
$filter_pos     = isset($_GET['f_pos'])  ? $_GET['f_pos']  : '';
$filter_company = isset($_GET['f_company']) ? $_GET['f_company'] : '';
$filter_emp     = isset($_GET['f_emp'])  ? $_GET['f_emp']  : '';
$filter_search  = isset($_GET['f_search']) ? trim($_GET['f_search']) : '';

switch ($filter_period_type) {
    case 'this_month': $period_start = date('Y-m-01'); $period_end = date('Y-m-t'); break;
    case 'last_month': $period_start = date('Y-m-01', strtotime('first day of last month')); $period_end = date('Y-m-t', strtotime('last day of last month')); break;
    case 'this_year': $period_start = date('Y-01-01'); $period_end = date('Y-12-31'); break;
    case 'specific_month':
        $sm = isset($_GET['specific_month']) && $_GET['specific_month'] !== '' ? $_GET['specific_month'] : date('Y-m');
        $period_start = $sm . '-01'; $period_end = date('Y-m-t', strtotime($period_start));
        break;
    case 'custom_range':
        $period_start = isset($_GET['range_start']) && $_GET['range_start'] !== '' ? $_GET['range_start'] : date('Y-m-01');
        $period_end   = isset($_GET['range_end'])   && $_GET['range_end']   !== '' ? $_GET['range_end']   : date('Y-m-t');
        break;
    case 'all_time': $period_start = ''; $period_end = ''; break;
    default: $period_start = date('Y-m-01'); $period_end = date('Y-m-t');
}
$period_label = ($filter_period_type === 'all_time') ? 'All Time' : (date('d M Y', strtotime($period_start)) . ' &ndash; ' . date('d M Y', strtotime($period_end)));

// =========================================================================
// EMPLOYEE LIST QUERY
// =========================================================================
$where = "LOWER(TRIM(status)) = 'active'";
if (!empty($filter_dept))    $where .= " AND department='" . mysqli_real_escape_string($con, $filter_dept) . "'";
if (!empty($filter_pos))     $where .= " AND position='"   . mysqli_real_escape_string($con, $filter_pos)  . "'";
if (!empty($filter_company)) $where .= " AND COALESCE(NULLIF(company_name,''),'(No Company Set)')='" . mysqli_real_escape_string($con, $filter_company) . "'";
if (!empty($filter_emp))     $where .= " AND employee_id='" . mysqli_real_escape_string($con, $filter_emp) . "'";
if (!empty($filter_search)) {
    $s = mysqli_real_escape_string($con, $filter_search);
    $where .= " AND (name LIKE '%$s%' OR employee_id LIKE '%$s%')";
}

$emp_query = mysqli_query($con, "SELECT id, employee_id, name, department, position, salary, COALESCE(NULLIF(company_name,''),'(No Company Set)') as company_name FROM hr_employees WHERE $where ORDER BY name ASC");

$latest_appraisals = [];
$la_q = mysqli_query($con, "SELECT a1.* FROM hr_appraisals a1 INNER JOIN (SELECT employee_id, MAX(created_at) as max_dt FROM hr_appraisals GROUP BY employee_id) a2 ON a1.employee_id=a2.employee_id AND a1.created_at=a2.max_dt");
if ($la_q) while ($r = mysqli_fetch_assoc($la_q)) $latest_appraisals[$r['employee_id']] = $r;

$stat_total = 0; $stat_with_appraisal_in_period = 0; $stat_never_appraised = 0; $stat_score_sum = 0; $stat_score_count = 0;
$employee_rows = [];
if ($emp_query) {
    while ($row = mysqli_fetch_assoc($emp_query)) {
        $perf = getManagerPerformance($con, $row['employee_id'], $period_start, $period_end);
        $row['perf'] = $perf;
        $row['basic'] = calcBasic($row['salary']);
        $row['last_appraisal'] = isset($latest_appraisals[$row['employee_id']]) ? $latest_appraisals[$row['employee_id']] : null;

        $stat_total++;
        if ($row['last_appraisal'] === null) {
            $stat_never_appraised++;
        } else {
            $la_date = $row['last_appraisal']['created_at'];
            if ($filter_period_type === 'all_time' || (strtotime($la_date) >= strtotime($period_start) && strtotime($la_date) <= strtotime($period_end . ' 23:59:59'))) {
                $stat_with_appraisal_in_period++;
            }
        }
        if ($perf['avg'] !== null) { $stat_score_sum += $perf['avg']; $stat_score_count++; }
        $employee_rows[] = $row;
    }
}
$stat_avg_score = $stat_score_count > 0 ? round($stat_score_sum / $stat_score_count, 2) : null;
?>
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Appraisal &amp; Increment Management</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
<link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
* { margin:0; padding:0; box-sizing:border-box; }
html, body { overflow-x:hidden; max-width:100%; }
body { font-family:'Poppins',sans-serif; background:#f0f4f8; min-height:100vh; padding:30px 0; color:#334155; width:100%; }
.main-wrapper { max-width:1750px; margin:0 auto; padding:0 20px; width:100%; overflow-x:hidden; }

.header-card { background:linear-gradient(135deg,#0f2557 0%,#1a3fc4 100%); border-radius:12px; padding:25px 35px; margin-bottom:25px; box-shadow:0 4px 20px rgba(15,37,87,.35); color:white; }
.header-content { display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:15px; }
.header-title h1 { font-size:26px; font-weight:700; margin-bottom:5px; }
.header-title p { color:rgba(255,255,255,.9); font-size:13px; }
.btn-back { background:rgba(255,255,255,.18); color:white; padding:10px 20px; border-radius:10px; font-weight:600; text-decoration:none; border:1px solid rgba(255,255,255,.3); display:inline-flex; align-items:center; gap:8px; transition:.3s; }
.btn-back:hover { background:white; color:#0f2557; text-decoration:none; }

.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:16px; margin-bottom:25px; }
.stat-card { background:white; border-radius:12px; padding:18px 22px; border:2px solid #e2e8f0; box-shadow:0 2px 8px rgba(0,0,0,.06); display:flex; align-items:center; gap:14px; }
.stat-icon { width:46px; height:46px; border-radius:10px; display:flex; align-items:center; justify-content:center; font-size:21px; }
.stat-label { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; }
.stat-value { font-size:22px; font-weight:800; color:#1e293b; }

.filter-panel { background:white; padding:22px; border-radius:12px; margin-bottom:25px; border:2px solid #e2e8f0; box-shadow:0 2px 10px rgba(0,0,0,.06); }
.filter-panel h4 { color:#0f2557; font-weight:700; font-size:16px; margin-bottom:16px; }
.filter-row { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:16px; align-items:end; }
.filter-group label { font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:.5px; display:block; margin-bottom:6px; }
.filter-group select, .filter-group input { width:100%; padding:11px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px; font-weight:500; color:#1e293b; }
.filter-group select:focus, .filter-group input:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }
.period-extra { display:none; }
.btn-apply { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border:none; padding:11px 22px; border-radius:10px; font-weight:700; font-size:14px; cursor:pointer; box-shadow:0 4px 14px rgba(15,37,87,.35); }
.btn-apply:hover { transform:translateY(-2px); }

.period-badge { display:inline-block; background:#e0e7ff; color:#0f2557; padding:6px 16px; border-radius:20px; font-weight:700; font-size:13px; margin-bottom:18px; border:1px solid #c7d2fe; }

.table-responsive { border-radius:12px; border:2px solid #e2e8f0; overflow-x:auto; overflow-y:visible; background:white; box-shadow:0 2px 10px rgba(0,0,0,.06); width:100%; max-width:100%; cursor:grab; user-select:none; }
.table-responsive.dragging { cursor:grabbing; }
.table-responsive.dragging * { cursor:grabbing !important; }
table.appraisal-table { width:100%; border-collapse:collapse; min-width:1400px; }
table.appraisal-table thead th { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; padding:14px 12px; font-weight:700; font-size:12px; text-transform:uppercase; letter-spacing:.4px; text-align:left; white-space:nowrap; }
table.appraisal-table td { padding:14px 12px; border-bottom:1px solid #e2e8f0; font-size:13px; vertical-align:middle; }
table.appraisal-table tbody tr:hover { background:#f8fafc; }

.badge-no-appraisal { background:#fef2f2; color:#b91c1c; padding:4px 11px; border-radius:14px; font-size:11px; font-weight:700; border:1px solid #fecaca; white-space:nowrap; }
.badge-has-appraisal { background:#ecfdf5; color:#047857; padding:4px 11px; border-radius:14px; font-size:11px; font-weight:700; border:1px solid #a7f3d0; white-space:nowrap; display:inline-block; }
.badge-rating { padding:4px 11px; border-radius:14px; font-size:11px; font-weight:700; white-space:nowrap; display:inline-block; }
.company-chip { font-size:11px; color:#4338ca; font-weight:700; background:#eef2ff; padding:2px 8px; border-radius:8px; display:inline-block; margin-top:4px; }

.salary-box { font-weight:700; color:#0f2557; }
.salary-sub { font-size:11px; color:#64748b; }

.btn-sm-action { padding:8px 14px; border-radius:8px; font-size:12px; font-weight:700; border:none; cursor:pointer; display:inline-flex; align-items:center; gap:6px; margin:2px; }
.btn-give { background:linear-gradient(135deg,#10b981,#059669); color:white; }
.btn-give:hover { transform:translateY(-2px); color:white; }
.btn-hist { background:#eef2ff; color:#1a3fc4; border:1px solid #c7d2fe; }
.btn-hist:hover { background:#e0e7ff; }

.modal-content { border-radius:16px; border:none; }
.modal-dialog { display:flex; align-items:center; min-height:calc(100% - 56px); }
.modal-content { max-height:90vh; display:flex; flex-direction:column; }
.modal-header { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:white; border-radius:16px 16px 0 0; padding:20px 28px; flex-shrink:0; }
.modal-title { font-weight:700; font-size:18px; }
.modal-body { padding:28px; overflow-y:auto; flex:1 1 auto; }
.modal-footer { flex-shrink:0; }
.close { color:white; opacity:.9; }

.salary-summary-box { background:#f8fafc; border:2px solid #e2e8f0; border-radius:12px; padding:18px; margin-bottom:20px; display:grid; grid-template-columns:1fr 1fr; gap:14px; }
.salary-summary-box .label { font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; }
.salary-summary-box .value { font-size:18px; font-weight:800; color:#1e293b; margin-top:3px; }

.perf-summary-box { background:#eff6ff; border:2px solid #bfdbfe; border-radius:12px; padding:16px; margin-bottom:20px; font-size:13px; color:#1e40af; }

.mode-toggle { display:flex; gap:10px; margin-bottom:16px; }
.mode-toggle label { flex:1; text-align:center; padding:12px; border:2px solid #e2e8f0; border-radius:10px; cursor:pointer; font-weight:700; color:#64748b; transition:.2s; }
.mode-toggle input { display:none; }
.mode-toggle label.active { border-color:#1a3fc4; background:#eff6ff; color:#0f2557; }

.form-group label { font-weight:700; color:#0f2557; font-size:12px; text-transform:uppercase; letter-spacing:.4px; display:block; margin-bottom:8px; }
.form-control-custom { width:100%; padding:12px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:15px; font-weight:600; color:#1e293b; }
.form-control-custom:focus { outline:none; border-color:#1a3fc4; box-shadow:0 0 0 3px rgba(26,63,196,.1); }

.preview-box { display:none; background:linear-gradient(135deg,#f0fdf4,#ecfdf5); border:2px solid #10b981; border-radius:12px; padding:20px; margin-top:18px; }
.preview-box h5 { color:#047857; font-weight:800; margin-bottom:14px; font-size:15px; }
.preview-grid { display:grid; grid-template-columns:1fr auto 1fr; gap:10px; align-items:center; margin-bottom:10px; }
.preview-old, .preview-new { text-align:center; padding:10px; border-radius:10px; }
.preview-old { background:#fee2e2; color:#991b1b; }
.preview-new { background:#d1fae5; color:#065f46; }
.preview-old .pv-label, .preview-new .pv-label { font-size:10px; font-weight:700; text-transform:uppercase; }
.preview-old .pv-value, .preview-new .pv-value { font-size:17px; font-weight:800; margin-top:3px; }
.preview-arrow { font-size:20px; color:#10b981; }
.preview-delta { text-align:center; margin-top:8px; font-weight:800; color:#047857; font-size:15px; }

.btn-action-modal { padding:12px 26px; border-radius:10px; font-weight:700; font-size:14px; border:none; cursor:pointer; }
.btn-preview { background:#0f2557; color:white; }
.btn-confirm { background:linear-gradient(135deg,#10b981,#059669); color:white; }
.btn-confirm:disabled { background:#cbd5e1; cursor:not-allowed; }

.history-item { background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; padding:14px 18px; margin-bottom:10px; }
.history-item .ht-row { display:flex; justify-content:space-between; flex-wrap:wrap; gap:10px; }
.history-empty { text-align:center; padding:40px; color:#94a3b8; }
.history-actions { display:flex; gap:8px; margin-top:10px; }
.btn-hist-edit { background:#fef3c7; color:#92400e; border:1px solid #fcd34d; padding:6px 12px; border-radius:7px; font-size:11px; font-weight:700; cursor:pointer; display:inline-flex; align-items:center; gap:5px; }
.btn-hist-del { background:#fee2e2; color:#991b1b; border:1px solid #fca5a5; padding:6px 12px; border-radius:7px; font-size:11px; font-weight:700; cursor:pointer; display:inline-flex; align-items:center; gap:5px; }
.btn-hist-cert { background:#e0e7ff; color:#1a3fc4; border:1px solid #c7d2fe; padding:6px 12px; border-radius:7px; font-size:11px; font-weight:700; cursor:pointer; display:inline-flex; align-items:center; gap:5px; text-decoration:none; }
.btn-hist-cert:hover { color:#1a3fc4; text-decoration:none; }
.btn-hist-notify { background:#dcfce7; color:#15803d; border:1px solid #86efac; padding:6px 12px; border-radius:7px; font-size:11px; font-weight:700; cursor:pointer; display:inline-flex; align-items:center; gap:5px; }
.btn-hist-notify:hover { background:#bbf7d0; }

.notify-section { background:#f0fdf4; border:2px solid #10b981; border-radius:12px; padding:18px; margin-top:6px; }
.notify-section h6 { color:#047857; font-weight:800; margin-bottom:10px; font-size:13px; text-transform:uppercase; }
.notify-box { background:#fff; border:1px solid #d1fae5; border-radius:10px; padding:14px; margin-bottom:12px; }
.btn-wa { background:#25d366; color:#fff; padding:11px 20px; border-radius:9px; font-weight:700; font-size:13px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; }
.btn-wa:hover { color:#fff; text-decoration:none; opacity:.9; }
.btn-cert-link { background:linear-gradient(135deg,#0f2557,#1a3fc4); color:#fff; padding:11px 20px; border-radius:9px; font-weight:700; font-size:13px; text-decoration:none; display:inline-flex; align-items:center; gap:8px; }
.btn-cert-link:hover { color:#fff; text-decoration:none; }

/* Toast */
.toast-card { position:fixed; top:24px; right:-400px; width:340px; background:#fff; border-left:5px solid #10b981; border-radius:10px; box-shadow:0 10px 40px rgba(0,0,0,.18); padding:16px 20px; z-index:99999; transition:right .4s cubic-bezier(.175,.885,.32,1.275); display:flex; align-items:center; gap:14px; }
.toast-card.show { right:24px; }
.toast-card.error { border-left-color:#ef4444; }
.toast-icon { font-size:22px; color:#10b981; }
.toast-card.error .toast-icon { color:#ef4444; }
.toast-text { font-size:13px; font-weight:700; color:#0f2557; line-height:1.4; }

select.select2-hidden-accessible { width:100% !important; }
.select2-container .select2-selection--single { height:48px !important; border:2px solid #e2e8f0 !important; border-radius:10px !important; }
.select2-container--default .select2-selection--single .select2-selection__rendered { line-height:44px !important; padding-left:14px !important; font-weight:600 !important; color:#1e293b !important; }
.select2-container--default .select2-selection--single .select2-selection__arrow { height:44px !important; }
@keyframes confettiFallAppraisal { 0%{transform:translateY(0) rotate(0deg);opacity:1;} 100%{transform:translateY(100vh) rotate(720deg);opacity:0;} }
</style>
</head>
<body>
<div class="main-wrapper">

<div class="header-card">
  <div class="header-content">
    <div class="header-title">
      <h1><i class="fas fa-chart-line"></i> Appraisal &amp; Increment Management</h1>
      <p>Manager-performance based salary review &mdash; not self review data</p>
    </div>
    
  </div>
</div>

<!-- STATS -->
<div class="stats">
  <div class="stat-card">
    <div class="stat-icon" style="background:#eef2ff;color:#1a3fc4;"><i class="fas fa-users"></i></div>
    <div><div class="stat-label">Employees Shown</div><div class="stat-value"><?php echo $stat_total; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#ecfdf5;color:#059669;"><i class="fas fa-check-circle"></i></div>
    <div><div class="stat-label">Appraised in Period</div><div class="stat-value"><?php echo $stat_with_appraisal_in_period; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#fef2f2;color:#dc2626;"><i class="fas fa-exclamation-circle"></i></div>
    <div><div class="stat-label">Never Appraised</div><div class="stat-value"><?php echo $stat_never_appraised; ?></div></div>
  </div>
  <div class="stat-card">
    <div class="stat-icon" style="background:#fffbeb;color:#d97706;"><i class="fas fa-star"></i></div>
    <div><div class="stat-label">Avg Manager Score (Period)</div><div class="stat-value"><?php echo $stat_avg_score !== null ? $stat_avg_score . '%' : 'N/A'; ?></div></div>
  </div>
</div>

<!-- FILTERS -->
<div class="filter-panel">
  <h4><i class="fas fa-filter"></i> Filter Employees &amp; Performance Period</h4>
  <form method="GET" id="filterForm">
    <div class="filter-row">
      <div class="filter-group">
        <label>Performance Period</label>
        <select name="period_type" id="period_type" onchange="togglePeriodExtra()">
          <option value="this_month" <?php echo $filter_period_type=='this_month'?'selected':''; ?>>This Month</option>
          <option value="last_month" <?php echo $filter_period_type=='last_month'?'selected':''; ?>>Last Month</option>
          <option value="specific_month" <?php echo $filter_period_type=='specific_month'?'selected':''; ?>>Specific Month</option>
          <option value="custom_range" <?php echo $filter_period_type=='custom_range'?'selected':''; ?>>Custom Date Range</option>
          <option value="this_year" <?php echo $filter_period_type=='this_year'?'selected':''; ?>>This Year</option>
          <option value="all_time" <?php echo $filter_period_type=='all_time'?'selected':''; ?>>All Time</option>
        </select>
      </div>

      <div class="filter-group period-extra" id="specificMonthBox">
        <label>Select Month</label>
        <input type="month" name="specific_month" value="<?php echo isset($_GET['specific_month']) ? htmlspecialchars($_GET['specific_month']) : date('Y-m'); ?>">
      </div>
      <div class="filter-group period-extra" id="rangeStartBox">
        <label>From Date</label>
        <input type="date" name="range_start" value="<?php echo isset($_GET['range_start']) ? htmlspecialchars($_GET['range_start']) : date('Y-m-01'); ?>">
      </div>
      <div class="filter-group period-extra" id="rangeEndBox">
        <label>To Date</label>
        <input type="date" name="range_end" value="<?php echo isset($_GET['range_end']) ? htmlspecialchars($_GET['range_end']) : date('Y-m-t'); ?>">
      </div>

      <div class="filter-group">
        <label>Company</label>
        <select name="f_company" class="select2">
          <option value="">All Companies</option>
          <?php foreach ($companies_list as $cn): ?>
          <option value="<?php echo htmlspecialchars($cn); ?>" <?php echo ($filter_company==$cn)?'selected':''; ?>><?php echo htmlspecialchars($cn); ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Department</label>
        <select name="f_dept" id="f_dept_select" class="select2" onchange="filterPositionsByDept()">
          <option value="">All Departments</option>
          <?php foreach ($depts_master as $dm): ?>
          <option value="<?php echo htmlspecialchars($dm); ?>" <?php echo ($filter_dept==$dm)?'selected':''; ?>><?php echo htmlspecialchars($dm); ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Position</label>
        <select name="f_pos" id="f_pos_select" class="select2">
          <option value="">All Positions</option>
          <?php foreach ($pos_master as $pm): ?>
          <option value="<?php echo htmlspecialchars($pm); ?>" <?php echo ($filter_pos==$pm)?'selected':''; ?>><?php echo htmlspecialchars($pm); ?></option>
          <?php endforeach; ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Employee</label>
        <select name="f_emp" class="select2">
          <option value="">All Employees</option>
          <?php
          $all_emp_q = mysqli_query($con, "SELECT employee_id, name FROM hr_employees WHERE LOWER(status)='active' ORDER BY name ASC");
          while ($ae = mysqli_fetch_assoc($all_emp_q)) {
              $sel = ($filter_emp == $ae['employee_id']) ? 'selected' : '';
              echo "<option value='".htmlspecialchars($ae['employee_id'])."' $sel>".htmlspecialchars($ae['name'])." (".htmlspecialchars($ae['employee_id']).")</option>";
          }
          ?>
        </select>
      </div>

      <div class="filter-group">
        <label>Search</label>
        <input type="text" name="f_search" placeholder="Name or ID..." value="<?php echo htmlspecialchars($filter_search); ?>">
      </div>

      <div class="filter-group">
        <button type="submit" class="btn-apply" style="width:100%;"><i class="fas fa-search"></i> Apply Filters</button>
      </div>
    </div>
  </form>
</div>

<div class="period-badge"><i class="fas fa-calendar-alt"></i> Showing Manager Performance For: <?php echo $period_label; ?></div>

<!-- EMPLOYEE TABLE -->
<div class="table-responsive">
<table class="appraisal-table">
<thead>
<tr>
  <th>Employee</th>
  <th>Dept / Position / Company</th>
  <th>Current Salary</th>
  <th>Manager Performance (Period)</th>
  <th>Last Appraisal</th>
  <th style="text-align:right;">Actions</th>
</tr>
</thead>
<tbody>
<?php if (count($employee_rows) > 0): foreach ($employee_rows as $row):
    $perf = $row['perf'];
    $style = getPerfStyle($perf['avg']);
    $la = $row['last_appraisal'];
?>
<tr>
  <td>
    <div style="font-weight:700;color:#1e293b;"><?php echo htmlspecialchars($row['name']); ?></div>
    <div style="font-size:11px;color:#64748b;">ID: <?php echo htmlspecialchars($row['employee_id']); ?></div>
  </td>
  <td>
    <div style="font-size:12px;color:#475569;"><?php echo htmlspecialchars($row['department'] ?: 'General'); ?></div>
    <div style="font-size:12px;color:#94a3b8;"><?php echo htmlspecialchars($row['position'] ?: 'General'); ?></div>
    <div class="company-chip"><i class="fas fa-building"></i> <?php echo htmlspecialchars($row['company_name']); ?></div>
  </td>
  <td>
    <div class="salary-box">₹<?php echo number_format($row['salary'], 2); ?></div>
    <div class="salary-sub">Basic (40%): ₹<?php echo number_format($row['basic'], 2); ?></div>
  </td>
  <td>
    <?php if ($perf['avg'] !== null): ?>
      <span class="badge-rating" style="background:<?php echo $style['bg']; ?>;color:<?php echo $style['c']; ?>;"><?php echo $style['icon'].' '.$style['r']; ?> &mdash; <?php echo $perf['avg']; ?>%</span>
      <div style="font-size:11px;color:#94a3b8;margin-top:5px;"><?php echo $perf['count']; ?> manager review(s) in period</div>
    <?php else: ?>
      <span class="badge-rating" style="background:#f1f5f9;color:#94a3b8;">➖ No manager reviews in this period</span>
    <?php endif; ?>
  </td>
  <td>
    <?php if ($la === null): ?>
      <span class="badge-no-appraisal"><i class="fas fa-exclamation-triangle"></i> No Appraisal Given Yet</span>
    <?php else: ?>
      <span class="badge-has-appraisal"><i class="fas fa-check"></i> <?php echo date('d M Y', strtotime($la['created_at'])); ?></span>
      <div style="font-size:11px;color:#64748b;margin-top:5px;">
        <?php echo htmlspecialchars($la['appraisal_type']); ?> &middot;
        <?php echo ($la['increment_percentage'] >= 0 ? '+' : '') . number_format($la['increment_percentage'],2); ?>%
        (₹<?php echo number_format($la['increment_amount'],2); ?>)
      </div>
    <?php endif; ?>
  </td>
  <td style="text-align:right;white-space:nowrap;">
    <button type="button" class="btn-sm-action btn-give"
      onclick='openAppraisalModal(<?php echo json_encode([
        "id" => $row["employee_id"], "name" => $row["name"], "dept" => $row["department"] ?: "General",
        "pos" => $row["position"] ?: "General", "company" => $row["company_name"],
        "salary" => floatval($row["salary"]), "basic" => floatval($row["basic"]),
        "avg" => $perf["avg"], "count" => $perf["count"],
        "period_start" => $period_start, "period_end" => $period_end, "period_label" => strip_tags($period_label)
      ], JSON_HEX_APOS|JSON_HEX_QUOT); ?>)'>
      <i class="fas fa-coins"></i> Give Appraisal
    </button>
    <button type="button" class="btn-sm-action btn-hist" onclick="openHistoryModal('<?php echo htmlspecialchars($row['employee_id']); ?>','<?php echo htmlspecialchars(addslashes($row['name'])); ?>')">
      <i class="fas fa-history"></i> History
    </button>
  </td>
</tr>
<?php endforeach; else: ?>
<tr><td colspan="6" style="text-align:center;padding:40px;color:#94a3b8;">No employees match the selected filters.</td></tr>
<?php endif; ?>
</tbody>
</table>
</div>

</div>

<!-- =========================================================================
     GIVE APPRAISAL MODAL
========================================================================== -->
<div class="modal fade" id="appraisalModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-coins"></i> Give Appraisal / Increment</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="m_emp_id">
        <input type="hidden" id="m_emp_name_hidden">
        <input type="hidden" id="m_emp_company">
        <input type="hidden" id="m_period_start">
        <input type="hidden" id="m_period_end">

        <div style="margin-bottom:18px;">
          <div style="font-weight:800;font-size:18px;color:#0f2557;" id="m_emp_name_display"></div>
          <div style="font-size:12px;color:#64748b;" id="m_emp_meta"></div>
        </div>

        <div class="salary-summary-box">
          <div><div class="label">Current Gross Salary</div><div class="value" id="m_current_gross">₹0.00</div></div>
          <div><div class="label">Current Basic Salary (40%)</div><div class="value" id="m_current_basic">₹0.00</div></div>
        </div>

        <div class="perf-summary-box" id="m_perf_box">
          <i class="fas fa-chart-bar"></i> <strong>Manager Performance:</strong> <span id="m_perf_text"></span>
        </div>

        <div class="form-group">
          <label>Appraisal Type / Reason</label>
          <select id="m_appraisal_type" class="form-control-custom">
            <?php foreach ($appraisal_types as $atype): ?>
            <option value="<?php echo htmlspecialchars($atype); ?>"><?php echo htmlspecialchars($atype); ?></option>
            <?php endforeach; ?>
          </select>
        </div>

        <div class="form-group">
          <label>Increment Input Mode</label>
          <div class="mode-toggle">
            <label id="modeLabelPct" class="active" onclick="setMode('percentage')"><span><i class="fas fa-percent"></i> Percentage Increase</span></label>
            <label id="modeLabelAmt" onclick="setMode('amount')"><span><i class="fas fa-rupee-sign"></i> Fixed Amount Increase</span></label>
          </div>
        </div>

        <div class="form-group">
          <label id="m_value_label">Increment Percentage (%)</label>
          <input type="number" step="0.01" id="m_increment_value" class="form-control-custom" placeholder="e.g. 18" oninput="liveCalc()">
        </div>

        <div class="form-group">
          <label>Remarks (Optional)</label>
          <textarea id="m_remarks" class="form-control-custom" rows="3" placeholder="Reason / context for this appraisal..."></textarea>
        </div>

        <div style="text-align:center;">
          <button type="button" class="btn-action-modal btn-preview" onclick="showPreview()"><i class="fas fa-eye"></i> Preview Change</button>
        </div>

        <div class="preview-box" id="previewBox">
          <h5><i class="fas fa-check-double"></i> Preview &mdash; Confirm before saving</h5>
          <div class="preview-grid">
            <div class="preview-old"><div class="pv-label">Old Gross</div><div class="pv-value" id="pv_old_gross">₹0</div></div>
            <div class="preview-arrow"><i class="fas fa-long-arrow-alt-right"></i></div>
            <div class="preview-new"><div class="pv-label">New Gross</div><div class="pv-value" id="pv_new_gross">₹0</div></div>
          </div>
          <div class="preview-grid">
            <div class="preview-old"><div class="pv-label">Old Basic (40%)</div><div class="pv-value" id="pv_old_basic">₹0</div></div>
            <div class="preview-arrow"><i class="fas fa-long-arrow-alt-right"></i></div>
            <div class="preview-new"><div class="pv-label">New Basic (40%)</div><div class="pv-value" id="pv_new_basic">₹0</div></div>
          </div>
          <div class="preview-delta" id="pv_delta"></div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-action-modal btn-confirm" id="confirmBtn" disabled onclick="confirmSaveAppraisal()"><i class="fas fa-save"></i> Confirm &amp; Save</button>
      </div>
    </div>
  </div>
</div>

<!-- =========================================================================
     NOTIFY EMPLOYEE MODAL (appears automatically right after save)
========================================================================== -->
<div class="modal fade" id="notifyModal" tabindex="-1" data-backdrop="static">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#059669,#10b981);">
        <h5 class="modal-title"><i class="fas fa-paper-plane"></i> <span id="n_modal_title">Notify Candidate</span> &mdash; <span id="n_emp_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div style="text-align:center;margin-bottom:18px;">
          <div style="font-size:14px;color:#475569;">Salary updated successfully:</div>
          <div style="font-size:22px;font-weight:800;color:#059669;margin-top:6px;">₹<span id="n_old_salary"></span> &rarr; ₹<span id="n_new_salary"></span> (<span id="n_pct"></span>)</div>
        </div>

        <div style="text-align:center;margin-bottom:20px;">
          <a id="n_cert_link" href="#" target="_blank" class="btn-cert-link"><i class="fas fa-certificate"></i> View / Download Increment Certificate</a>
        </div>

        <div class="notify-section">
          <h6><i class="fab fa-whatsapp"></i> Send via WhatsApp</h6>
          <div class="notify-box">
            <textarea id="n_wa_text" class="form-control-custom" rows="6" style="font-size:13px;"></textarea>
          </div>
          <a id="n_wa_btn" href="#" target="_blank" class="btn-wa"><i class="fab fa-whatsapp"></i> Open WhatsApp</a>
        </div>

        <div class="notify-section" style="background:#eff6ff;border-color:#bfdbfe;margin-top:16px;">
          <h6 style="color:#1e40af;"><i class="fas fa-envelope"></i> Send via Email</h6>
          <div class="notify-box">
            <label class="fl" style="font-size:11px;font-weight:700;color:#1e40af;display:block;margin-bottom:6px;">To</label>
            <input type="text" id="n_email_to" class="form-control-custom" style="margin-bottom:10px;">
            <label class="fl" style="font-size:11px;font-weight:700;color:#1e40af;display:block;margin-bottom:6px;">Subject</label>
            <input type="text" id="n_email_subject" class="form-control-custom" style="margin-bottom:10px;">
            <label class="fl" style="font-size:11px;font-weight:700;color:#1e40af;display:block;margin-bottom:6px;">Message</label>
            <textarea id="n_email_body" class="form-control-custom" rows="8" style="font-size:13px;"></textarea>
          </div>
          <button type="button" class="btn-action-modal btn-preview" onclick="sendNotifyEmail()"><i class="fas fa-paper-plane"></i> Send Email Now</button>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal" onclick="window.location.reload();">Done</button>
      </div>
    </div>
  </div>
</div>

<!-- =========================================================================
     HISTORY MODAL (with full CRUD: View / Edit / Delete)
========================================================================== -->
<div class="modal fade" id="historyModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-history"></i> Appraisal History &mdash; <span id="h_emp_name"></span></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="historyContent">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<!-- =========================================================================
     EDIT APPRAISAL MODAL (CRUD - Update)
========================================================================== -->
<div class="modal fade" id="editApprModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header" style="background:linear-gradient(135deg,#d97706,#f59e0b);">
        <h5 class="modal-title"><i class="fas fa-edit"></i> Edit Appraisal Record</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <input type="hidden" id="e_appraisal_id">
        <div class="form-group">
          <label>Appraisal Type / Reason</label>
          <select id="e_appraisal_type" class="form-control-custom">
            <?php foreach ($appraisal_types as $atype): ?>
            <option value="<?php echo htmlspecialchars($atype); ?>"><?php echo htmlspecialchars($atype); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="form-group">
          <label>Increment Input Mode</label>
          <div class="mode-toggle">
            <label id="eModeLabelPct" class="active" onclick="setEditMode('percentage')"><span><i class="fas fa-percent"></i> Percentage</span></label>
            <label id="eModeLabelAmt" onclick="setEditMode('amount')"><span><i class="fas fa-rupee-sign"></i> Fixed Amount</span></label>
          </div>
        </div>
        <div class="form-group">
          <label id="e_value_label">Increment Percentage (%)</label>
          <input type="number" step="0.01" id="e_increment_value" class="form-control-custom">
        </div>
        <div class="form-group">
          <label>Remarks</label>
          <textarea id="e_remarks" class="form-control-custom" rows="3"></textarea>
        </div>
        <div style="font-size:12px;color:#92400e;background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;padding:10px 14px;">
          <i class="fas fa-info-circle"></i> Recalculated from this record's original baseline salary. If this is the employee's latest appraisal, their live salary will also be updated to match.
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-outline-secondary" data-dismiss="modal">Cancel</button>
        <button type="button" class="btn-action-modal" style="background:linear-gradient(135deg,#d97706,#f59e0b);color:#fff;" onclick="saveEditAppraisal()"><i class="fas fa-save"></i> Save Changes</button>
      </div>
    </div>
  </div>
</div>

<!-- Toast Card -->
<div id="toastCard" class="toast-card">
  <i id="toastIcon" class="fas fa-check-circle toast-icon"></i>
  <div id="toastText" class="toast-text">Message</div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/popper.js@1.16.1/dist/umd/popper.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
var DEPT_POSITION_MAP = <?php echo json_encode($dept_position_map); ?>;
var ALL_POSITIONS = <?php echo json_encode($pos_master); ?>;
var PRESELECTED_POS = "<?php echo htmlspecialchars($filter_pos); ?>";

$(document).ready(function(){
  $('.select2').select2({ width:'100%', placeholder:'Select...', allowClear:true });
  togglePeriodExtra();
  filterPositionsByDept(true);
  initDragScroll();
});

// ---- CLICK-AND-DRAG HORIZONTAL SCROLLING for the table ----
function initDragScroll() {
  var el = document.querySelector('.table-responsive');
  if (!el) return;
  var isDown = false, startX, scrollLeft;

  el.addEventListener('mousedown', function(e){
    isDown = true;
    el.classList.add('dragging');
    startX = e.pageX - el.offsetLeft;
    scrollLeft = el.scrollLeft;
  });
  el.addEventListener('mouseleave', function(){ isDown = false; el.classList.remove('dragging'); });
  el.addEventListener('mouseup', function(){ isDown = false; el.classList.remove('dragging'); });
  el.addEventListener('mousemove', function(e){
    if (!isDown) return;
    e.preventDefault();
    var x = e.pageX - el.offsetLeft;
    var walk = (x - startX) * 1.4;
    el.scrollLeft = scrollLeft - walk;
  });
}

function togglePeriodExtra() {
  var type = $('#period_type').val();
  $('.period-extra').hide();
  if (type === 'specific_month') $('#specificMonthBox').show();
  if (type === 'custom_range') { $('#rangeStartBox').show(); $('#rangeEndBox').show(); }
}

// ---- CASCADING DEPARTMENT -> POSITION (Option A: derived live from employees) ----
function filterPositionsByDept(isInit) {
  var dept = $('#f_dept_select').val();
  var posSelect = $('#f_pos_select');
  var currentVal = isInit ? PRESELECTED_POS : posSelect.val();
  var options = '<option value="">All Positions</option>';

  var list = dept && DEPT_POSITION_MAP[dept] ? DEPT_POSITION_MAP[dept] : ALL_POSITIONS;
  list.forEach(function(p) {
    var sel = (p === currentVal) ? 'selected' : '';
    options += '<option value="' + p.replace(/"/g,'&quot;') + '" ' + sel + '>' + p + '</option>';
  });
  posSelect.html(options);
  posSelect.trigger('change'); // refresh select2 display
}

// ---- GIVE APPRAISAL MODAL ----
var currentGross = 0, currentBasic = 0, currentMode = 'percentage';

function setMode(mode) {
  currentMode = mode;
  $('#modeLabelPct').toggleClass('active', mode === 'percentage');
  $('#modeLabelAmt').toggleClass('active', mode === 'amount');
  $('#m_value_label').text(mode === 'percentage' ? 'Increment Percentage (%)' : 'Increment Amount (₹)');
  $('#m_increment_value').attr('placeholder', mode === 'percentage' ? 'e.g. 18' : 'e.g. 20000');
  $('#previewBox').hide();
  $('#confirmBtn').attr('disabled', true);
}

function openAppraisalModal(data) {
  $('#m_emp_id').val(data.id);
  $('#m_emp_name_hidden').val(data.name);
  $('#m_emp_company').val(data.company);
  $('#m_emp_name_display').text(data.name + ' (' + data.id + ')');
  $('#m_emp_meta').text(data.dept + ' — ' + data.pos + ' — ' + data.company);
  $('#m_period_start').val(data.period_start);
  $('#m_period_end').val(data.period_end);

  currentGross = parseFloat(data.salary) || 0;
  currentBasic = parseFloat(data.basic) || 0;
  $('#m_current_gross').text('₹' + currentGross.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));
  $('#m_current_basic').text('₹' + currentBasic.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));

  if (data.avg !== null && data.avg !== undefined) {
    $('#m_perf_text').html('Average score <strong>' + data.avg + '%</strong> across <strong>' + data.count + '</strong> manager review(s) for period: ' + data.period_label);
  } else {
    $('#m_perf_text').html('No manager performance reviews found for period: ' + data.period_label);
  }

  $('#m_increment_value').val('');
  $('#m_remarks').val('');
  setMode('percentage');
  $('#previewBox').hide();
  $('#confirmBtn').attr('disabled', true);
  $('#appraisalModal').modal('show');
}

function liveCalc() { $('#previewBox').hide(); $('#confirmBtn').attr('disabled', true); }

function showPreview() {
  var val = parseFloat($('#m_increment_value').val());
  if (isNaN(val)) { alert('Please enter a valid increment value.'); return; }
  if (currentGross <= 0) { alert('Current salary is ₹0 — cannot calculate increment.'); return; }

  var incrementAmount, incrementPct, newGross;
  if (currentMode === 'percentage') {
    incrementPct = val;
    incrementAmount = Math.round((currentGross * (val/100)) * 100) / 100;
  } else {
    incrementAmount = val;
    incrementPct = Math.round(((val/currentGross)*100) * 100) / 100;
  }
  newGross = Math.round((currentGross + incrementAmount) * 100) / 100;
  var newBasic = Math.round((newGross * 0.40) * 100) / 100;
  if (newGross <= 0) { alert('Resulting new salary must be greater than ₹0.'); return; }

  $('#pv_old_gross').text('₹' + currentGross.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));
  $('#pv_new_gross').text('₹' + newGross.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));
  $('#pv_old_basic').text('₹' + currentBasic.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));
  $('#pv_new_basic').text('₹' + newBasic.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}));
  var sign = incrementAmount >= 0 ? '+' : '';
  $('#pv_delta').html(sign + '₹' + incrementAmount.toLocaleString('en-IN', {minimumFractionDigits:2, maximumFractionDigits:2}) + ' &nbsp; (' + sign + incrementPct.toFixed(2) + '%)');
  $('#previewBox').slideDown();
  $('#confirmBtn').attr('disabled', false);
}

function confirmSaveAppraisal() {
  if (!confirm('Confirm and save this appraisal? This will immediately update the employee salary.')) return;
  $.post(window.location.pathname, {
    ajax_give_appraisal: 1,
    target_employee_id: $('#m_emp_id').val(),
    target_employee_name: $('#m_emp_name_hidden').val(),
    increment_mode: currentMode,
    increment_value: $('#m_increment_value').val(),
    appraisal_type: $('#m_appraisal_type').val(),
    remarks: $('#m_remarks').val(),
    period_start: $('#m_period_start').val(),
    period_end: $('#m_period_end').val()
  }, function(resp) {
    if (resp.success) {
      $('#appraisalModal').modal('hide');
      showToast('✅ Appraisal saved for ' + resp.employee_name + '! Salary updated: ₹' + resp.old_salary + ' → ₹' + resp.new_salary + ' (' + (parseFloat(resp.increment_percentage) >= 0 ? '+' : '') + resp.increment_percentage + '%).');
      launchConfetti();
      setTimeout(function(){ openNotifyModal(resp); }, 450);
    } else {
      showToast(resp.message || 'Could not save appraisal.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while saving appraisal.', true); });
}

function launchConfetti() {
  var colors = ['#0f2557','#1a3fc4','#10b981','#f59e0b','#ef4444','#8b5cf6','#d4af37'];
  for (var i = 0; i < 80; i++) {
    var el = document.createElement('div');
    var size = Math.random() * 10 + 5;
    el.style.cssText = 'position:fixed;top:-20px;left:' + (Math.random()*100) + 'vw;width:' + size + 'px;height:' + size + 'px;' +
      'background:' + colors[Math.floor(Math.random()*colors.length)] + ';border-radius:' + (Math.random()>0.5?'50%':'2px') + ';' +
      'z-index:99999;pointer-events:none;opacity:1;' +
      'animation:confettiFallAppraisal ' + (1.5+Math.random()*2) + 's ease-in forwards;';
    document.body.appendChild(el);
    setTimeout(function(node){ return function(){ node.remove(); }; }(el), 4000);
  }
}

// ---- NOTIFY MODAL ----
function openNotifyModal(resp, isFromHistory) {
  $('#n_modal_title').text(isFromHistory ? 'Notify Candidate' : 'Appraisal Saved! Notify Candidate');
  $('#n_emp_name').text(resp.employee_name);
  $('#n_old_salary').text(resp.old_salary);
  $('#n_new_salary').text(resp.new_salary);
  $('#n_pct').text((parseFloat(resp.increment_percentage) >= 0 ? '+' : '') + resp.increment_percentage + '%');
  $('#n_cert_link').attr('href', resp.cert_link);
  $('#n_wa_text').val(resp.whatsapp_text);
  $('#n_wa_btn').attr('href', 'https://wa.me/' + resp.phone_clean + '?text=' + encodeURIComponent(resp.whatsapp_text));
  $('#n_email_to').val((resp.emails || []).join(', '));
  $('#n_email_subject').val(resp.email_subject);
  $('#n_email_body').val(resp.email_body);
  window._notify_company = resp.company_name || $('#m_emp_company').val();
  $('#notifyModal').modal('show');
}

// Re-notify candidate about a PAST appraisal record, from History
function notifyFromHistory(id) {
  var h = currentHistoryData[id];
  if (!h) { showToast('Could not load this record.', true); return; }
  $('#historyModal').modal('hide');
  setTimeout(function(){ openNotifyModal(h, true); }, 350);
}

// Keep WA link synced if HR edits the message text
$(document).on('input', '#n_wa_text', function(){
  var phone = $('#n_wa_btn').attr('href').split('https://wa.me/')[1].split('?')[0];
  $('#n_wa_btn').attr('href', 'https://wa.me/' + phone + '?text=' + encodeURIComponent($(this).val()));
});

function sendNotifyEmail() {
  var to = $('#n_email_to').val().trim();
  if (!to) { showToast('Please enter at least one recipient email.', true); return; }
  $.post(window.location.pathname, {
    ajax_send_notify_email: 1,
    to: to,
    subject: $('#n_email_subject').val(),
    body: $('#n_email_body').val(),
    company_name: window._notify_company || ''
  }, function(resp) {
    showToast(resp.success ? 'Email sent successfully!' : (resp.message || 'Could not send email.'), !resp.success);
  }, 'json').fail(function(){ showToast('Server error while sending email.', true); });
}

// ---- TOAST ----
function showToast(msg, isError) {
  var tc = document.getElementById('toastCard');
  var ti = document.getElementById('toastIcon');
  var tt = document.getElementById('toastText');
  tc.className = 'toast-card ' + (isError ? 'error' : '') + ' show';
  ti.className = isError ? 'fas fa-exclamation-circle toast-icon' : 'fas fa-check-circle toast-icon';
  tt.innerHTML = msg;
  setTimeout(function(){ tc.classList.remove('show'); }, 4500);
}

// ---- HISTORY MODAL (with CRUD) ----
var currentHistoryEmpId = '';
var currentHistoryData = {}; // keyed by appraisal id -> full record, avoids embedding raw JSON in HTML attributes

function openHistoryModal(empId, empName) {
  currentHistoryEmpId = empId;
  $('#h_emp_name').text(empName);
  loadHistory(empId);
  $('#historyModal').modal('show');
}

function loadHistory(empId) {
  $('#historyContent').html('<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin" style="font-size:24px;color:#0f2557;"></i></div>');
  $.ajax({
    url: window.location.pathname, type: 'GET', dataType: 'json',
    data: { ajax_history: empId },
    success: function(resp) {
      currentHistoryData = {};
      if (resp.success && resp.history.length > 0) {
        var html = '';
        resp.history.forEach(function(h) {
          currentHistoryData[h.id] = h; // safe storage, no HTML-attribute encoding needed
          var sign = (parseFloat(h.increment_percentage) >= 0) ? '+' : '';
          html += '<div class="history-item" id="hist_' + h.id + '">' +
            '<div class="ht-row"><div><strong style="color:#0f2557;">' + escapeHtml(h.type) + '</strong></div>' +
            '<div style="color:#64748b;font-size:12px;"><i class="fas fa-clock"></i> ' + h.date + '</div></div>' +
            '<div class="ht-row" style="margin-top:8px;">' +
              '<div>₹' + h.old_salary + ' &rarr; <strong style="color:#059669;">₹' + h.new_salary + '</strong></div>' +
              '<div style="font-weight:700;color:#047857;">' + sign + h.increment_percentage + '% (₹' + h.increment_amount + ')</div>' +
            '</div>' +
            '<div style="font-size:12px;color:#64748b;margin-top:6px;">Mode: ' + h.mode + ' &middot; Avg Score at decision: ' + h.avg_score + (h.avg_score !== 'N/A' ? '%' : '') + ' &middot; Period: ' + h.review_window + '</div>' +
            (h.remarks ? '<div style="margin-top:8px;background:#fffbeb;border-left:3px solid #f59e0b;padding:8px 12px;border-radius:6px;font-size:12px;color:#78350f;">' + escapeHtml(h.remarks) + '</div>' : '') +
            '<div style="font-size:11px;color:#94a3b8;margin-top:8px;">Given by: ' + escapeHtml(h.created_by) + '</div>' +
            '<div class="history-actions">' +
              '<a href="' + h.cert_link + '" target="_blank" class="btn-hist-cert"><i class="fas fa-certificate"></i> Certificate</a>' +
              '<button type="button" class="btn-hist-notify" onclick="notifyFromHistory(' + h.id + ')"><i class="fas fa-paper-plane"></i> Notify Candidate</button>' +
              '<button type="button" class="btn-hist-edit" onclick="openEditAppraisal(' + h.id + ')"><i class="fas fa-edit"></i> Edit</button>' +
              '<button type="button" class="btn-hist-del" onclick="deleteAppraisal(' + h.id + ')"><i class="fas fa-trash"></i> Delete</button>' +
            '</div>' +
          '</div>';
        });
        $('#historyContent').html(html);
      } else {
        $('#historyContent').html('<div class="history-empty"><i class="fas fa-folder-open" style="font-size:40px;display:block;margin-bottom:10px;"></i>No appraisal history yet for this employee.</div>');
      }
    },
    error: function() { $('#historyContent').html('<div class="history-empty" style="color:#dc2626;">Failed to load history.</div>'); }
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ---- EDIT APPRAISAL (CRUD - Update) ----
var currentEditMode = 'percentage';
function setEditMode(mode) {
  currentEditMode = mode;
  $('#eModeLabelPct').toggleClass('active', mode === 'percentage');
  $('#eModeLabelAmt').toggleClass('active', mode === 'amount');
  $('#e_value_label').text(mode === 'percentage' ? 'Increment Percentage (%)' : 'Increment Amount (₹)');
}

function openEditAppraisal(id) {
  var h = currentHistoryData[id];
  if (!h) { showToast('Could not load this record.', true); return; }
  $('#e_appraisal_id').val(h.id);
  $('#e_appraisal_type').val(h.type);
  $('#e_remarks').val(h.remarks || '');
  var mode = (h.mode === 'amount') ? 'amount' : 'percentage';
  var prefillVal = parseFloat(h.input_value);
  if (!prefillVal) { // older records saved before input_value existed
    prefillVal = (mode === 'amount') ? parseFloat(h.increment_amount.replace(/,/g,'')) : parseFloat(h.increment_percentage);
  }
  $('#e_increment_value').val(prefillVal);
  setEditMode(mode);
  $('#historyModal').modal('hide');
  $('#editApprModal').modal('show');
}

function saveEditAppraisal() {
  var val = $('#e_increment_value').val();
  if (val === '' || isNaN(parseFloat(val))) { showToast('Please enter a valid increment value.', true); return; }
  $.post(window.location.pathname, {
    ajax_edit_appraisal: 1,
    appraisal_id: $('#e_appraisal_id').val(),
    increment_mode: currentEditMode,
    increment_value: val,
    appraisal_type: $('#e_appraisal_type').val(),
    remarks: $('#e_remarks').val()
  }, function(resp) {
    if (resp.success) {
      $('#editApprModal').modal('hide');
      showToast('Appraisal record updated.' + (resp.synced_live ? ' Live salary synced to ₹' + resp.new_salary + '.' : ''));
      setTimeout(function(){ window.location.reload(); }, 1200);
    } else {
      showToast(resp.message || 'Could not update appraisal.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while updating appraisal.', true); });
}

// ---- DELETE APPRAISAL (CRUD - Delete) ----
function deleteAppraisal(id) {
  if (!confirm('Permanently delete this appraisal record? If this was the employee\'s latest appraisal, their live salary will be reverted to the previous value.')) return;
  $.post(window.location.pathname, { ajax_delete_appraisal: 1, appraisal_id: id }, function(resp) {
    if (resp.success) {
      showToast('Appraisal deleted.' + (resp.reverted_salary ? ' Salary reverted to ₹' + resp.reverted_salary + '.' : ''));
      loadHistory(currentHistoryEmpId);
      setTimeout(function(){ window.location.reload(); }, 1200);
    } else {
      showToast(resp.message || 'Could not delete appraisal.', true);
    }
  }, 'json').fail(function(){ showToast('Server error while deleting appraisal.', true); });
}
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