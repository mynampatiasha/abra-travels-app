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

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');

// Analysis engine: keyword-matching (no external API required)

if (!isset($dbConn) || !$dbConn) { die("Database connection failed."); }
mysqli_report(MYSQLI_REPORT_OFF);
date_default_timezone_set('Asia/Kolkata');

// =========================================================================
// MAIL — sent per-candidate's company via mail_helper.php (Company Settings
// page), not a single hardcoded account for every company anymore.
// =========================================================================
if (file_exists('mail_helper.php')) { require_once('mail_helper.php'); }

function getScreeningCompanyId($dbConn, $sid) {
    if ($sid <= 0) return 0;
    $cand_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT company_id FROM hr_screenings WHERE id=" . intval($sid) . " LIMIT 1"));
    return $cand_row ? intval($cand_row['company_id'] ?? 0) : 0;
}

$session_id = 0;
if (isset($_SESSION['user_id'])) $session_id = intval($_SESSION['user_id']);
elseif (isset($_SESSION['id'])) $session_id = intval($_SESSION['id']);

$current_user_data = null;
if ($session_id > 0) {
    $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE id=$session_id OR user_id=$session_id LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
} elseif (isset($_SESSION['user_name'])) {
    $n = mysqli_real_escape_string($dbConn, $_SESSION['user_name']);
    $q = mysqli_query($dbConn, "SELECT * FROM hr_employees WHERE name='$n' OR name LIKE '$n%' LIMIT 1");
    if ($q && mysqli_num_rows($q) > 0) $current_user_data = mysqli_fetch_assoc($q);
}
if (!$current_user_data) {
    die("<div style='padding:50px;text-align:center;font-family:sans-serif;'><h4>Session Expired.</h4><a href='login.php'>Login</a></div>");
}

$current_user_id   = $current_user_data['id'];
$current_user_name = $current_user_data['name'];

// FETCH CRM PERMISSIONS
$user_id = 0; 
$permissions = [];
$is_admin = false;
if (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Administrator') {
    $is_admin = true;
    $r = mysqli_query($dbConn, "SELECT cid FROM manager_admin WHERE name='".mysqli_real_escape_string($dbConn, $current_user_name)."' LIMIT 1");
    if ($r && $rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
} elseif (isset($_SESSION['user_type']) && $_SESSION['user_type'] == 'Employee') {
    $r = mysqli_query($dbConn, "SELECT cid FROM manager_user WHERE name='".mysqli_real_escape_string($dbConn, $current_user_name)."' LIMIT 1");
    if ($r && $rw = mysqli_fetch_array($r)) $user_id = $rw['cid'];
}
if ($user_id > 0) {
    $stmt = $dbConn->prepare("SELECT section_name, can_access FROM manager_permissions WHERE user_id=?");
    if ($stmt) {
        $stmt->bind_param("i", $user_id); 
        $stmt->execute();
        $result = $stmt->get_result();
        while ($row = $result->fetch_assoc()) {
            $permissions[$row['section_name']] = $row['can_access'];
        }
        $stmt->close();
    }
}
$authorized_override_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');
$can_override = false;
foreach ($authorized_override_names as $admin_name) {
    if (stripos($current_user_name, $admin_name) !== false || stripos($admin_name, $current_user_name) !== false) {
        $can_override = true;
        break;
    }
}

// ---- TABLE SETUP ----
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_screenings (
    id int(11) NOT NULL AUTO_INCREMENT,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) NOT NULL,
    department varchar(255) NOT NULL,
    resume_filename varchar(500) NOT NULL,
    resume_path varchar(500) NOT NULL,
    resume_text longtext DEFAULT NULL,
    jd_filename varchar(500) DEFAULT NULL,
    jd_path varchar(500) DEFAULT NULL,
    jd_text longtext DEFAULT NULL,
    ai_analysis longtext DEFAULT NULL,
    eligibility_score decimal(5,2) DEFAULT NULL,
    eligibility_status varchar(30) DEFAULT 'pending',
    skills_matched text DEFAULT NULL,
    skills_missing text DEFAULT NULL,
    experience_years varchar(50) DEFAULT NULL,
    education_level varchar(100) DEFAULT NULL,
    screening_notes text DEFAULT NULL,
    hr_decision varchar(30) DEFAULT 'pending',
    screened_by int(11) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add JD columns safely — compatible with MySQL 5.6/5.7/8.0
$db_name = mysqli_query($dbConn, "SELECT DATABASE() as db");
$db_row  = mysqli_fetch_assoc($db_name);
$cur_db  = $db_row['db'] ?? '';
$col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screenings'");
$existing_cols = [];
while ($cr = mysqli_fetch_assoc($col_check)) $existing_cols[] = $cr['COLUMN_NAME'];
if (!in_array('jd_filename', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN jd_filename varchar(500) DEFAULT NULL");
if (!in_array('jd_path',     $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN jd_path varchar(500) DEFAULT NULL");
if (!in_array('jd_text',     $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN jd_text longtext DEFAULT NULL");
if (!in_array('hr_override_score', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN hr_override_score decimal(5,2) DEFAULT NULL");
if (!in_array('position_id', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN position_id int(11) DEFAULT NULL");
if (!in_array('company_id', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN company_id int(11) DEFAULT NULL");
// Manual "Mark as Employee" action (three-dot menu on the candidate list) — a
// deliberate HR click, not tied to onboarding/hr_employees automatically.
if (!in_array('moved_to_employee_at', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN moved_to_employee_at DATETIME DEFAULT NULL");
if (!in_array('moved_to_employee_by', $existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screenings ADD COLUMN moved_to_employee_by VARCHAR(255) DEFAULT NULL");

// Position classification (Professional vs Blue Collar) — read from hr_positions via position_id,
// so a candidate's requirements (Resume/JD/AI scoring) derive from their selected position.
try { mysqli_query($dbConn, "ALTER TABLE hr_positions ADD COLUMN worker_category VARCHAR(20) NOT NULL DEFAULT 'professional'"); } catch (Throwable $e) {}

// Message templates — same table hr_candidate_tracking.php uses, so templates created in
// either screen are shared and show up in both places.
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_message_templates (
    id          INT(11) AUTO_INCREMENT PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    statuses    VARCHAR(500) DEFAULT 'General',
    body        TEXT NOT NULL,
    created_by  VARCHAR(255) DEFAULT '',
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Ensure hr_candidate_tracking has a link back to hr_screenings
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_candidate_tracking (
    id              INT(11) AUTO_INCREMENT PRIMARY KEY,
    screening_id    INT(11) DEFAULT NULL,
    department_id   INT(11) DEFAULT 0,
    position_id     INT(11) DEFAULT 0,
    department_name VARCHAR(255) DEFAULT '',
    position_name   VARCHAR(255) DEFAULT '',
    name            VARCHAR(255) NOT NULL,
    phone           VARCHAR(30)  NOT NULL,
    email           VARCHAR(255) DEFAULT '',
    resume_path     VARCHAR(500) DEFAULT '',
    resume_name     VARCHAR(255) DEFAULT '',
    jd_path         VARCHAR(500) DEFAULT '',
    jd_name         VARCHAR(255) DEFAULT '',
    current_status  VARCHAR(50)  DEFAULT 'New',
    trigger_datetime DATETIME    DEFAULT NULL,
    last_note       TEXT,
    last_updated_by VARCHAR(255) DEFAULT '',
    created_by      VARCHAR(255) DEFAULT '',
    created_at      DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$ct_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_candidate_tracking'");
$ct_existing_cols = [];
while ($cr2 = mysqli_fetch_assoc($ct_col_check)) $ct_existing_cols[] = $cr2['COLUMN_NAME'];
if (!in_array('screening_id', $ct_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_candidate_tracking ADD COLUMN screening_id int(11) DEFAULT NULL");
if (!in_array('rejected_round', $ct_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_candidate_tracking ADD COLUMN rejected_round VARCHAR(255) DEFAULT NULL");

// Auto-fix existing candidates that don't have position_id set yet
mysqli_query($dbConn, "UPDATE hr_screenings s JOIN hr_positions p ON s.position_applied = p.title SET s.position_id = p.id WHERE s.position_id IS NULL OR s.position_id = 0");

mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_screening_evaluations (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) NOT NULL,
    round_number int(11) NOT NULL,
    evaluator_name varchar(255) NOT NULL,
    total_marks_obtained int(11) DEFAULT 0,
    total_marks_possible int(11) DEFAULT 0,
    percentage decimal(5,2) DEFAULT 0,
    rating_label varchar(50) DEFAULT NULL,
    hr_notes text DEFAULT NULL,
    status varchar(30) DEFAULT 'Pending',
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add observation-period columns to hr_screening_evaluations
$col_check_eval = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screening_evaluations'");
$existing_eval_cols = [];
while ($cr = mysqli_fetch_assoc($col_check_eval)) $existing_eval_cols[] = $cr['COLUMN_NAME'];
if (!in_array('obs_status', $existing_eval_cols))     mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN obs_status VARCHAR(20) DEFAULT NULL");
if (!in_array('obs_notes', $existing_eval_cols))      mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN obs_notes TEXT DEFAULT NULL");
if (!in_array('obs_start_date', $existing_eval_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN obs_start_date DATETIME DEFAULT NULL");
if (!in_array('obs_marked_at', $existing_eval_cols))  mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN obs_marked_at DATETIME DEFAULT NULL");
if (!in_array('override_reason', $existing_eval_cols))mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN override_reason TEXT DEFAULT NULL");
if (!in_array('notified_at', $existing_eval_cols))    mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN notified_at DATETIME DEFAULT NULL");
if (!in_array('notify_type', $existing_eval_cols))    mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN notify_type VARCHAR(20) DEFAULT NULL");
if (!in_array('early_end_reason', $existing_eval_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN early_end_reason TEXT DEFAULT NULL");

// Pre-round interview scheduling — kept separate from hr_screening_evaluations so
// scheduling never accidentally creates an eval record (which would switch the
// round view from "form" to "results" and interfere with the 90% lock logic).
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_interview_schedules (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) NOT NULL,
    round_number int(11) NOT NULL,
    scheduled_datetime datetime DEFAULT NULL,
    notified_at datetime DEFAULT NULL,
    scheduled_by varchar(255) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_screening_round (screening_id, round_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
$iv_sched_cols = [];
$iv_sched_cr = mysqli_query($dbConn, "SHOW COLUMNS FROM hr_interview_schedules");
if ($iv_sched_cr) while ($iv_sched_c = mysqli_fetch_assoc($iv_sched_cr)) $iv_sched_cols[] = $iv_sched_c['Field'];
if (!in_array('scheduled_end_datetime', $iv_sched_cols)) mysqli_query($dbConn, "ALTER TABLE hr_interview_schedules ADD COLUMN scheduled_end_datetime DATETIME DEFAULT NULL");
if (!in_array('reminder_ticket_raised_at', $iv_sched_cols)) mysqli_query($dbConn, "ALTER TABLE hr_interview_schedules ADD COLUMN reminder_ticket_raised_at DATETIME DEFAULT NULL");

mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_screening_evaluation_answers (
    id int(11) NOT NULL AUTO_INCREMENT,
    evaluation_id int(11) NOT NULL,
    question_id int(11) NOT NULL,
    answer_text text DEFAULT NULL,
    marks_obtained int(11) DEFAULT 0,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Support file-upload-type questions — answers may carry a file instead of typed text
$ans_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screening_evaluation_answers'");
$ans_existing_cols = [];
while ($cr4 = mysqli_fetch_assoc($ans_col_check)) $ans_existing_cols[] = $cr4['COLUMN_NAME'];
if (!in_array('file_path', $ans_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluation_answers ADD COLUMN file_path VARCHAR(500) DEFAULT NULL");

mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_worksample_files (
    id int(11) NOT NULL AUTO_INCREMENT,
    link_id int(11) NOT NULL,
    screening_id int(11) NOT NULL,
    round_number int(11) NOT NULL,
    file_path varchar(500) NOT NULL,
    file_name varchar(255) NOT NULL,
    file_size int(11) DEFAULT 0,
    uploaded_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Patch hr_assignment_links with submission_type (questions | file_upload)
$al_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_assignment_links'");
$al_existing_cols = [];
while ($cr3 = mysqli_fetch_assoc($al_col_check)) $al_existing_cols[] = $cr3['COLUMN_NAME'];
if (!in_array('submission_type', $al_existing_cols))     mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN submission_type VARCHAR(20) DEFAULT 'questions'");
if (!in_array('tab_switch_count', $al_existing_cols))     mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN tab_switch_count INT DEFAULT 0");
if (!in_array('is_flagged', $al_existing_cols))           mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN is_flagged TINYINT(1) DEFAULT 0");
if (!in_array('candidate_location', $al_existing_cols))   mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN candidate_location VARCHAR(255) DEFAULT NULL");
if (!in_array('candidate_signature', $al_existing_cols))  mysqli_query($dbConn, "ALTER TABLE hr_assignment_links ADD COLUMN candidate_signature LONGTEXT DEFAULT NULL");

// ---- REJECTION LOG (permanent record — survives candidate deletion) ----
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_rejection_log (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) DEFAULT NULL,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    company_id int(11) DEFAULT NULL,
    round_number int(11) DEFAULT 0,
    round_name varchar(255) DEFAULT 'Overall',
    round_type varchar(30) DEFAULT 'overall',
    reason text NOT NULL,
    rejected_by varchar(255) DEFAULT NULL,
    kept_in_database tinyint(1) DEFAULT 1,
    resume_filename varchar(500) DEFAULT NULL,
    resume_path varchar(500) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$rl_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_rejection_log'");
$rl_existing_cols = [];
while ($rlc = mysqli_fetch_assoc($rl_col_check)) $rl_existing_cols[] = $rlc['COLUMN_NAME'];
if (!in_array('rejection_source', $rl_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_rejection_log ADD COLUMN rejection_source VARCHAR(30) DEFAULT 'hr_screening'");

$rej_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screening_evaluations'");
$rej_existing_cols = [];
while ($crj = mysqli_fetch_assoc($rej_col_check)) $rej_existing_cols[] = $crj['COLUMN_NAME'];
if (!in_array('rejection_reason', $rej_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejection_reason TEXT DEFAULT NULL");
if (!in_array('rejected_by', $rej_existing_cols))      mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejected_by VARCHAR(255) DEFAULT NULL");
if (!in_array('rejected_at', $rej_existing_cols))      mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejected_at DATETIME DEFAULT NULL");

// ---- REJECTION LOG (permanent record — survives candidate deletion) ----
mysqli_query($dbConn, "CREATE TABLE IF NOT EXISTS hr_rejection_log (
    id int(11) NOT NULL AUTO_INCREMENT,
    screening_id int(11) DEFAULT NULL,
    candidate_name varchar(255) NOT NULL,
    candidate_email varchar(255) DEFAULT NULL,
    candidate_phone varchar(30) DEFAULT NULL,
    position_applied varchar(255) DEFAULT NULL,
    department varchar(255) DEFAULT NULL,
    company_id int(11) DEFAULT NULL,
    round_number int(11) DEFAULT 0,
    round_name varchar(255) DEFAULT 'Overall',
    round_type varchar(30) DEFAULT 'overall',
    reason text NOT NULL,
    rejected_by varchar(255) DEFAULT NULL,
    kept_in_database tinyint(1) DEFAULT 1,
    resume_filename varchar(500) DEFAULT NULL,
    resume_path varchar(500) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$rej_col_check = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screening_evaluations'");
$rej_existing_cols = [];
while ($crj = mysqli_fetch_assoc($rej_col_check)) $rej_existing_cols[] = $crj['COLUMN_NAME'];
if (!in_array('rejection_reason', $rej_existing_cols)) mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejection_reason TEXT DEFAULT NULL");
if (!in_array('rejected_by', $rej_existing_cols))      mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejected_by VARCHAR(255) DEFAULT NULL");
if (!in_array('rejected_at', $rej_existing_cols))      mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN rejected_at DATETIME DEFAULT NULL");

// ---- HELPER: RENDER FILE ANSWER LINKS (handles legacy single-path and new JSON-array multi-file answers) ----
function renderFileAnswerLinks($file_path_raw) {
    if (empty($file_path_raw)) return '';
    $paths = json_decode($file_path_raw, true);
    if (!is_array($paths)) {
        // Legacy format — single plain path string
        $paths = [$file_path_raw];
    }
    $links = [];
    foreach ($paths as $p) {
        if (empty($p)) continue;
        // Uploaded filenames are stored as: {timestamp}_{rand}_{original-name-sanitized}
        // Strip the "timestamp_rand_" prefix so HR sees the original filename, not the generated one.
        $basename = basename($p);
        $display_name = preg_replace('/^\d+_\d+_/', '', $basename);
        $links[] = '<a href="' . htmlspecialchars($p) . '" target="_blank" style="display:inline-flex;align-items:center;gap:6px;font-weight:700;color:#1a3fc4;text-decoration:none;margin-right:14px;"><i class="fas fa-paperclip"></i>' . htmlspecialchars($display_name) . '</a>';
    }
    return implode('', $links);
}

// ---- HELPER: EXTRACT TEXT ----
// Repairs common PDF-extraction artefacts: merged words (missing spaces) and stray whitespace.
function normalizeExtractedText($text) {
    // Insert a space where a lowercase letter is immediately followed by an uppercase letter
    // (e.g. "ExcelWord" -> "Excel Word") — a common symptom of dropped inter-word spacing.
    $text = preg_replace('/([a-z])([A-Z])/', '$1 $2', $text);
    // Insert a space between a letter and a following digit run, and vice versa (e.g. "PHP5years" -> "PHP 5 years")
    $text = preg_replace('/([a-zA-Z])(\d)/', '$1 $2', $text);
    $text = preg_replace('/(\d)([a-zA-Z])/', '$1 $2', $text);
    // Collapse repeated whitespace
    $text = preg_replace('/[ \t]+/', ' ', $text);
    $text = preg_replace('/\n{2,}/', "\n", $text);
    return trim($text);
}

function extractText($path, $ext) {
    if (!file_exists($path)) return '';
    if ($ext === 'txt') {
        return file_get_contents($path) ?: '';
    }
    if ($ext === 'pdf') {
        // 1) Try pdftotext with -layout — preserves column structure & spacing far better
        //    than plain pdftotext, which is critical for multi-column resumes.
        $out = [];
        @exec("pdftotext -layout " . escapeshellarg($path) . " -", $out, $ret);
        if (isset($ret) && $ret === 0 && !empty($out)) {
            $joined = implode("\n", $out);
            if (strlen(trim($joined)) > 30) return $joined;
        }

        // 2) Fall back to plain pdftotext (no -layout) in case -layout isn't supported
        $out2 = [];
        @exec("pdftotext " . escapeshellarg($path) . " -", $out2, $ret2);
        if (isset($ret2) && $ret2 === 0 && !empty($out2)) {
            $joined2 = implode("\n", $out2);
            if (strlen(trim($joined2)) > 30) return $joined2;
        }

        // 3) Try a bundled PDF parser library if present
        try {
            if (file_exists(__DIR__ . '/Pdf2text.php')) {
                require_once __DIR__ . '/Pdf2text.php';
                $pdf2text = new \Asika\Pdf2text();
                $text = $pdf2text->decode(file_get_contents($path));
                if (strlen(trim($text)) > 30) return normalizeExtractedText($text);
            }
        } catch (\Throwable $t) { }

        // 4) Last resort — manual zlib-stream scraper
        $raw = @file_get_contents($path);
        if (!$raw) return '';

        $text = '';
        preg_match_all("#obj(.*)endobj#ismU", $raw, $objects);
        foreach (($objects[1] ?? []) as $currentObject) {
            if (preg_match("#stream(.*)endstream#ismU", $currentObject, $stream)) {
                $streamData = $stream[1];
                $options = preg_replace("#stream(.*)endstream#ismU", "", $currentObject);
                if (preg_match("#/FlateDecode#ismU", $options)) {
                    $pos = strpos($streamData, "\x78\x9C");
                    if ($pos === false) $pos = strpos($streamData, "\x78\xDA");
                    if ($pos === false) $pos = strpos($streamData, "\x78\x01");

                    if ($pos !== false) {
                        $streamData = substr($streamData, $pos);
                        $decoded = @gzuncompress($streamData);
                        if ($decoded) {
                            preg_match_all("#\((.*?)\)[\s]*Tj#ismU", $decoded, $m);
                            if (!empty($m[1])) $text .= implode(' ', $m[1]) . ' ';

                            preg_match_all("#\[(.*?)\][\s]*TJ#ismU", $decoded, $m);
                            foreach (($m[1] ?? []) as $tj) {
                                $parts = explode('(', $tj);
                                foreach ($parts as $p) {
                                    if (strpos($p, ')') !== false) {
                                        $p_parts = explode(')', $p);
                                        $text .= $p_parts[0];
                                        // Any negative kerning number (even small ones) usually means a space —
                                        // lowered threshold from 2+ digits to 1+ digit so more inter-word gaps are caught.
                                        if (preg_match('/-\d+/', $p_parts[1])) {
                                            $text .= ' ';
                                        }
                                    }
                                }
                                $text .= ' ';
                            }

                            preg_match_all("#\((.*?)\)[\s]*\'#ismU", $decoded, $m);
                            if (!empty($m[1])) $text .= implode(' ', $m[1]) . ' ';
                        }
                    }
                }
            }
        }

        $text = preg_replace_callback('/\\\\([0-7]{3})/', function($m) { return chr(octdec($m[1])); }, $text);
        $text = str_replace(['\\(', '\\)'], ['(', ')'], $text);
        $text = normalizeExtractedText($text);

        if (strlen(trim($text)) > 30) return $text;

        // Extraction genuinely failed — return empty so calling code can show a real error
        // instead of silently substituting fake demo data.
        return '';
    }
    if (in_array($ext, ['doc','docx'])) {
        $out = [];
        @exec("antiword " . escapeshellarg($path), $out, $ret);
        if (isset($ret) && $ret === 0 && !empty($out)) return implode("\n", $out);
        if ($ext === 'docx' && class_exists('ZipArchive')) {
            $zip = new ZipArchive();
            if ($zip->open($path) === true) {
                $xml = $zip->getFromName('word/document.xml');
                $zip->close();
                if ($xml) return strip_tags(str_replace(['</w:p>','</w:r>','<w:br/>'], ["\n"," ","\n"], $xml));
            }
        }
    }
    return '';
}

// ---- AJAX: CHECK DUPLICATE ----
if (isset($_GET['ajax_check_duplicate'])) {
    header('Content-Type: application/json');
    $phone_raw = trim($_GET['phone'] ?? '');
    $email     = mysqli_real_escape_string($dbConn, trim($_GET['email'] ?? ''));
    $phone_digits = preg_replace('/\D/', '', $phone_raw);
    $result = ['duplicate' => false];
    if ($phone_digits || $email) {
        $cond = [];
        if ($phone_digits) $cond[] = "REPLACE(REPLACE(REPLACE(candidate_phone,' ',''),'-',''),'+','') = '" . mysqli_real_escape_string($dbConn, $phone_digits) . "'";
        if ($email) $cond[] = "candidate_email='$email'";
        $q1 = mysqli_query($dbConn, "SELECT id, candidate_name FROM hr_screenings WHERE " . implode(' OR ', $cond) . " LIMIT 1");
        if ($q1 && $r1 = mysqli_fetch_assoc($q1)) {
            $result = ['duplicate' => true, 'source' => 'screening', 'name' => $r1['candidate_name'], 'id' => $r1['id']];
        } else {
            $cond2 = [];
            if ($phone_digits) $cond2[] = "REPLACE(REPLACE(REPLACE(phone,' ',''),'-',''),'+','') = '" . mysqli_real_escape_string($dbConn, $phone_digits) . "'";
            if ($email) $cond2[] = "email='$email'";
            $q2 = mysqli_query($dbConn, "SELECT id, name, current_status FROM hr_candidate_tracking WHERE " . implode(' OR ', $cond2) . " LIMIT 1");
            if ($q2 && $r2 = mysqli_fetch_assoc($q2)) {
                $result = ['duplicate' => true, 'source' => 'tracking', 'name' => $r2['name'], 'id' => $r2['id'], 'status' => $r2['current_status']];
            }
        }
    }
    echo json_encode($result); exit;
}

// ---- AJAX: CHECK CANDIDATE TRACKING DUPLICATE (phone/email + dept/position) ----
if (isset($_GET['ajax_check_tracking_duplicate'])) {
    header('Content-Type: application/json');
    $sid = intval($_GET['screening_id'] ?? 0);
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_phone, candidate_email, department, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['duplicate' => false]); exit; }

    $phone_digits = preg_replace('/\D/', '', $sc['candidate_phone'] ?? '');
    $email = mysqli_real_escape_string($dbConn, trim($sc['candidate_email'] ?? ''));
    $dept  = mysqli_real_escape_string($dbConn, trim($sc['department'] ?? ''));
    $pos   = mysqli_real_escape_string($dbConn, trim($sc['position_applied'] ?? ''));

    $cond = [];
    // Match the same normalization as ajax_check_duplicate above — strip spaces/
    // dashes/plus from the stored tracking phone too, not just the screening side,
    // so a number stored with a space (e.g. "807 3053703") still matches.
    if ($phone_digits) $cond[] = "REPLACE(REPLACE(REPLACE(phone,' ',''),'-',''),'+','') LIKE '%$phone_digits%'";
    if ($email) $cond[] = "email='$email'";

    if (empty($cond)) { echo json_encode(['duplicate' => false]); exit; }

    $cond_str = implode(' OR ', $cond);
    $q = mysqli_query($dbConn, "SELECT id, name, phone, email, current_status, created_at, screening_id FROM hr_candidate_tracking WHERE ($cond_str) AND department_name='$dept' AND position_name='$pos' LIMIT 1");
    
    if ($q && $row = mysqli_fetch_assoc($q)) {
        echo json_encode([
            'duplicate' => true, 
            'name' => $row['name'], 
            'id' => $row['id'], 
            'phone' => $row['phone'],
            'email' => $row['email'],
            'status' => $row['current_status'],
            'created_at' => $row['created_at'],
            'has_other_screening' => !empty($row['screening_id'])
        ]);
    } else {
        echo json_encode(['duplicate' => false]);
    }
    exit;
}

// ---- AJAX: LINK EXISTING TRACKING ROW TO THIS SCREENING ----
if (isset($_POST['ajax_link_tracking'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id'] ?? 0);
    $tracking_id = intval($_POST['tracking_id'] ?? 0);
    if ($sid <= 0 || $tracking_id <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid request.']); exit; }

    $updated_by = mysqli_real_escape_string($dbConn, $current_user_name ?? 'HR');
    mysqli_query($dbConn, "UPDATE hr_candidate_tracking SET screening_id=$sid, last_updated_by='$updated_by' WHERE id=$tracking_id");
    mysqli_query($dbConn, "INSERT INTO hr_candidate_tracking_log (candidate_id, status, notes, updated_by) SELECT id, current_status, 'Linked to screening #$sid after re-screening.', '$updated_by' FROM hr_candidate_tracking WHERE id=$tracking_id");

    echo json_encode(['success' => true, 'tracking_id' => $tracking_id]);
    exit;
}

// ---- AJAX: MARK CANDIDATE AS EMPLOYEE (manual, via the row's ⋮ menu) ----
if (isset($_POST['ajax_mark_as_employee'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id'] ?? 0);
    if ($sid <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid candidate.']); exit; }
    $marked_by = mysqli_real_escape_string($dbConn, $current_user_name ?? 'HR');
    mysqli_query($dbConn, "UPDATE hr_screenings SET moved_to_employee_at=NOW(), moved_to_employee_by='$marked_by' WHERE id=$sid");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: SEND ASSIGNMENT EMAIL ----
if (isset($_POST['ajax_send_assignment_email'])) {
    header('Content-Type: application/json');
    $to        = filter_var($_POST['to'] ?? '', FILTER_SANITIZE_EMAIL);
    $subject   = strip_tags($_POST['subject'] ?? 'Assignment Round');
    $body_text = strip_tags($_POST['body'] ?? '');
    $sid       = intval($_POST['sid'] ?? 0);

    $result = sendCompanyMail($dbConn, getScreeningCompanyId($dbConn, $sid), $to, $subject, $body_text); if (ob_get_level() > 0) { ob_clean(); }
    echo json_encode($result);
    exit;
}

// ---- AJAX: SEND ROUND NOTIFICATION EMAIL ----
if (isset($_POST['ajax_send_round_email'])) {
    header('Content-Type: application/json');
    $to      = filter_var($_POST['to'] ?? '', FILTER_SANITIZE_EMAIL);
    $subject = strip_tags($_POST['subject'] ?? 'Interview Update');
    $body    = strip_tags($_POST['body'] ?? '');
    $sid     = intval($_POST['sid'] ?? 0);
    $round   = intval($_POST['round'] ?? 0);

    $notify_type = ($_POST['notify_type'] ?? '') === 'reject' ? 'reject' : 'congrats';

    $result = sendCompanyMail($dbConn, getScreeningCompanyId($dbConn, $sid), $to, $subject, $body);
    if ($result['success'] && $sid > 0 && $round > 0) {
        mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET notified_at=NOW(), notify_type='$notify_type' WHERE screening_id=$sid AND round_number=$round");
    }
    echo json_encode($result);
    exit;
}

// ---- AJAX: SAVE PRE-ROUND INTERVIEW SCHEDULE ----
if (isset($_POST['ajax_save_interview_schedule'])) {
    header('Content-Type: application/json');
    $sid   = intval($_POST['screening_id'] ?? 0);
    $round = intval($_POST['round_number'] ?? 0);
    $dt    = mysqli_real_escape_string($dbConn, $_POST['scheduled_datetime'] ?? '');
    $end   = mysqli_real_escape_string($dbConn, $_POST['scheduled_end_datetime'] ?? '');
    $by    = mysqli_real_escape_string($dbConn, $current_user_name);

    if ($sid <= 0 || $round <= 0 || empty($dt)) {
        echo json_encode(['success' => false, 'message' => 'Missing required fields.']);
        exit;
    }

    // Block double-booking the same recruiter for a different candidate.
    // With an end time given, this checks for real overlap against the
    // recruiter's other bookings (falling back to a point-in-time check for
    // any older rows that never had an end time saved). Without an end time,
    // it falls back to an exact-start-time match, same as before.
    if (!empty($end)) {
        $conflict = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT his.id, s.candidate_name FROM hr_interview_schedules his
            JOIN hr_screenings s ON s.id = his.screening_id
            WHERE his.scheduled_by = '$by' AND his.screening_id != $sid
              AND (
                    (his.scheduled_end_datetime IS NOT NULL AND '$dt' < his.scheduled_end_datetime AND his.scheduled_datetime < '$end')
                 OR (his.scheduled_end_datetime IS NULL AND his.scheduled_datetime >= '$dt' AND his.scheduled_datetime < '$end')
              )
            LIMIT 1
        "));
    } else {
        $conflict = mysqli_fetch_assoc(mysqli_query($dbConn, "
            SELECT his.id, s.candidate_name FROM hr_interview_schedules his
            JOIN hr_screenings s ON s.id = his.screening_id
            WHERE his.scheduled_datetime = '$dt' AND his.scheduled_by = '$by' AND his.screening_id != $sid
            LIMIT 1
        "));
    }
    if ($conflict) {
        echo json_encode(['success' => false, 'message' => 'This interview slot is already booked for another candidate. Please select a different date or time.']);
        exit;
    }

    $endSql = !empty($end) ? "'$end'" : "NULL";
    mysqli_query($dbConn, "INSERT INTO hr_interview_schedules (screening_id, round_number, scheduled_datetime, scheduled_end_datetime, scheduled_by)
        VALUES ($sid, $round, '$dt', $endSql, '$by')
        ON DUPLICATE KEY UPDATE scheduled_datetime='$dt', scheduled_end_datetime=$endSql, scheduled_by='$by', reminder_ticket_raised_at=NULL");

    echo json_encode(['success' => true]);
    exit;
}

// ---- DOWNLOAD: CALENDAR INVITE (.ics) FOR A SCHEDULED INTERVIEW ----
// Plain-text calendar file — works the same whether opened from an email,
// a WhatsApp message, or the "Add to Calendar" button, on any calendar app.
if (isset($_GET['ajax_download_ics'])) {
    $sid   = intval($_GET['screening_id'] ?? 0);
    $round = intval($_GET['round_number'] ?? 0);

    $sch = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_interview_schedules WHERE screening_id=$sid AND round_number=$round LIMIT 1"));
    if (!$sch || empty($sch['scheduled_datetime'])) {
        header('Content-Type: text/plain');
        echo 'This interview has not been scheduled yet.';
        exit;
    }

    $cand = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));
    $cname = $cand['candidate_name'] ?? 'Candidate';
    $pos   = $cand['position_applied'] ?? '';

    $round_row  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT round_name FROM hr_screening_rounds WHERE round_number=$round LIMIT 1"));
    $round_name = $round_row['round_name'] ?? ('Round ' . $round);

    $start = new DateTime($sch['scheduled_datetime']);
    $end   = !empty($sch['scheduled_end_datetime']) ? new DateTime($sch['scheduled_end_datetime']) : (clone $start)->modify('+30 minutes');

    $dtStart = $start->format('Ymd\THis');
    $dtEnd   = $end->format('Ymd\THis');
    $dtStamp = gmdate('Ymd\THis\Z');
    $uid     = 'interview-' . $sid . '-' . $round . '@' . ($_SERVER['HTTP_HOST'] ?? 'abra-flowxai.abragroup.in');

    $icsEscape = function($s) {
        return str_replace(["\\", ",", ";", "\n"], ["\\\\", "\\,", "\\;", "\\n"], $s);
    };

    $summary = $icsEscape("Interview — {$round_name} — {$cname} — {$pos}");
    $desc    = $icsEscape("Interview for {$cname} ({$pos}), {$round_name}. Please join on time.");

    $ics  = "BEGIN:VCALENDAR\r\n";
    $ics .= "VERSION:2.0\r\n";
    $ics .= "PRODID:-//Abra HR//Interview Scheduler//EN\r\n";
    $ics .= "CALSCALE:GREGORIAN\r\n";
    $ics .= "BEGIN:VEVENT\r\n";
    $ics .= "UID:{$uid}\r\n";
    $ics .= "DTSTAMP:{$dtStamp}\r\n";
    $ics .= "DTSTART;TZID=Asia/Kolkata:{$dtStart}\r\n";
    $ics .= "DTEND;TZID=Asia/Kolkata:{$dtEnd}\r\n";
    $ics .= "SUMMARY:{$summary}\r\n";
    $ics .= "DESCRIPTION:{$desc}\r\n";
    $ics .= "BEGIN:VALARM\r\n";
    $ics .= "ACTION:DISPLAY\r\n";
    $ics .= "DESCRIPTION:Interview Reminder\r\n";
    $ics .= "TRIGGER:-PT5M\r\n";
    $ics .= "END:VALARM\r\n";
    $ics .= "END:VEVENT\r\n";
    $ics .= "END:VCALENDAR\r\n";

    header('Content-Type: text/calendar; charset=utf-8');
    header('Content-Disposition: attachment; filename="interview_' . $sid . '_round' . $round . '.ics"');
    echo $ics;
    exit;
}

// ---- ONE-TIME: RECALCULATE RATING/STATUS FOR EXISTING EVALUATIONS ----
// Run this once (visit the URL in a browser) to retroactively apply the round-half-up
// rounding fix to rounds that were already graded before the fix — e.g. an 89.67% that
// was saved as "Failed" under the old unrounded logic flips to "Passed" here. Rows a
// manager already Manager-Overrode are left untouched since that decision was manual.
if (isset($_GET['fix_existing_evaluation_status'])) {
    header('Content-Type: application/json');

    $rows = mysqli_query($dbConn, "SELECT id, percentage FROM hr_screening_evaluations WHERE status != 'Override'");
    $updated = 0;
    $unchanged = 0;

    while ($r = mysqli_fetch_assoc($rows)) {
        $rounded_pct = round(floatval($r['percentage']));

        $rating_label = 'Poor';
        if ($rounded_pct >= 95) $rating_label = 'Significant';
        elseif ($rounded_pct >= 90) $rating_label = 'Outstanding';
        elseif ($rounded_pct >= 85) $rating_label = 'Excellent';
        elseif ($rounded_pct >= 80) $rating_label = 'Good';
        elseif ($rounded_pct >= 70) $rating_label = 'Average';

        $status = $rounded_pct >= 90 ? 'Passed' : 'Failed';

        $stmt = mysqli_prepare($dbConn, "UPDATE hr_screening_evaluations SET rating_label=?, status=? WHERE id=?");
        mysqli_stmt_bind_param($stmt, "ssi", $rating_label, $status, $r['id']);
        mysqli_stmt_execute($stmt);
        if (mysqli_stmt_affected_rows($stmt) > 0) $updated++; else $unchanged++;
        mysqli_stmt_close($stmt);
    }

    echo json_encode(['success' => true, 'rows_changed' => $updated, 'rows_already_correct' => $unchanged]);
    exit;
}

// ---- DEBUG: SHOW EVERYTHING THE TICKET-REMINDER CRON SEES, NO TIMING NEEDED ----
// Visit this any time — shows the server's current IST time plus every interview
// scheduled in the next 24 hours, whether its reminder ticket has already been raised,
// and whether the scheduler's name resolves to a real hr_employees row. No need to
// time this against a live 5-minute window like the actual cron endpoint.
if (isset($_GET['debug_interview_tickets'])) {
    header('Content-Type: application/json');
    $now_ist = date('Y-m-d H:i:s');

    $rows = mysqli_query($dbConn, "
        SELECT his.id, his.screening_id, his.round_number, his.scheduled_datetime,
               his.scheduled_by, his.reminder_ticket_raised_at,
               s.candidate_name
        FROM hr_interview_schedules his
        JOIN hr_screenings s ON s.id = his.screening_id
        WHERE his.scheduled_datetime IS NOT NULL
          AND his.scheduled_datetime BETWEEN '$now_ist' AND DATE_ADD('$now_ist', INTERVAL 24 HOUR)
        ORDER BY his.scheduled_datetime ASC
    ");

    $out = [];
    while ($r = mysqli_fetch_assoc($rows)) {
        $employee_found = false;
        if (!empty($r['scheduled_by'])) {
            $sb = mysqli_real_escape_string($dbConn, $r['scheduled_by']);
            $emp = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_employees WHERE name='$sb' LIMIT 1"));
            $employee_found = $emp ? true : false;
        }
        $out[] = [
            'candidate_name'            => $r['candidate_name'],
            'round_number'              => $r['round_number'],
            'scheduled_datetime'        => $r['scheduled_datetime'],
            'scheduled_by'              => $r['scheduled_by'],
            'scheduled_by_matches_employee' => $employee_found,
            'reminder_ticket_raised_at' => $r['reminder_ticket_raised_at'],
            'minutes_from_now'          => round((strtotime($r['scheduled_datetime']) - strtotime($now_ist)) / 60, 1),
        ];
    }

    echo json_encode(['server_now_ist' => $now_ist, 'upcoming_interviews_next_24h' => $out], JSON_PRETTY_PRINT);
    exit;
}

// ---- CRON: RAISE A TICKET 5 MINUTES BEFORE EACH SCHEDULED INTERVIEW ----
// Meant to be hit once a minute by a server cron job (e.g. via curl/wget), not by a
// user in the browser. Finds interviews starting in the next 5 minutes that haven't
// had a reminder ticket raised yet, and assigns one to whoever scheduled that round.
if (isset($_GET['cron_raise_interview_tickets'])) {
    header('Content-Type: application/json');

    // Use PHP's own Asia/Kolkata clock (set at the top of this file) for the window
    // boundaries instead of MySQL's NOW() — the DB server's clock/timezone may not
    // match IST, and scheduled_datetime is always stored as an IST value.
    $now_ist    = date('Y-m-d H:i:s');
    $window_end = date('Y-m-d H:i:s', strtotime('+5 minutes'));

    $due = mysqli_query($dbConn, "
        SELECT his.*, s.candidate_name, s.position_applied, s.department
        FROM hr_interview_schedules his
        JOIN hr_screenings s ON s.id = his.screening_id
        WHERE his.scheduled_datetime IS NOT NULL
          AND his.reminder_ticket_raised_at IS NULL
          AND his.scheduled_datetime BETWEEN '$now_ist' AND '$window_end'
    ");

    $raised = 0;
    $skipped = 0;

    while ($row = mysqli_fetch_assoc($due)) {
        $sid   = intval($row['screening_id']);
        $round = intval($row['round_number']);

        // Resolve who scheduled it (a name) to an actual hr_employees id, so the ticket
        // has someone real to be assigned to — same lookup pattern used elsewhere in this app.
        $assigned_to = 0;
        if (!empty($row['scheduled_by'])) {
            $sb = mysqli_real_escape_string($dbConn, $row['scheduled_by']);
            $emp = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_employees WHERE name='$sb' LIMIT 1"));
            if ($emp) $assigned_to = intval($emp['id']);
        }
        if ($assigned_to <= 0) { $skipped++; continue; }

        $round_row  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT round_name FROM hr_screening_rounds WHERE round_number=$round LIMIT 1"));
        $round_name = $round_row['round_name'] ?? ('Round ' . $round);

        $when = date('d M Y, h:i A', strtotime($row['scheduled_datetime']));

        $ticket_name    = mysqli_real_escape_string($dbConn, $row['candidate_name']);
        $ticket_subject = mysqli_real_escape_string($dbConn, "Interview Reminder — {$row['candidate_name']} — {$round_name} — starts in 5 minutes");
        $ticket_message = mysqli_real_escape_string($dbConn,
            "Attention! Your interview is scheduled in 5 minutes.\n\n" .
            "Candidate: {$row['candidate_name']}\n" .
            "Position: {$row['position_applied']}\n" .
            "Department: {$row['department']}\n" .
            "Round: {$round_name}\n" .
            "Scheduled for: {$when}\n\n" .
            "The candidate is waiting. Please join the interview on time."
        );

        $max_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT MAX(id) AS max_id FROM tickets"));
        $next_id = intval($max_row['max_id'] ?? 0) + 1;
        $ticket_number = 'TICKET' . date('Y') . str_pad($next_id, 4, '0', STR_PAD_LEFT);
        $timeline = 5;
        $deadline = date('Y-m-d H:i:s', strtotime($row['scheduled_datetime']));

        $stmt = mysqli_prepare($dbConn, "INSERT INTO tickets
            (ticket_number, name, subject, message, status, priority, timeline, deadline, attachment, created_at, updated_at, assigned_to, created_by)
            VALUES (?, ?, ?, ?, 'open', 'high', ?, ?, '', NOW(), NOW(), ?, ?)");
        if ($stmt) {
            mysqli_stmt_bind_param($stmt, "ssssisii", $ticket_number, $ticket_name, $ticket_subject, $ticket_message, $timeline, $deadline, $assigned_to, $assigned_to);
            mysqli_stmt_execute($stmt);
            mysqli_stmt_close($stmt);
            mysqli_query($dbConn, "UPDATE hr_interview_schedules SET reminder_ticket_raised_at=NOW() WHERE id=" . intval($row['id']));
            $raised++;
        }
    }

    echo json_encode(['success' => true, 'raised' => $raised, 'skipped_no_employee_match' => $skipped]);
    exit;
}

// ---- AJAX: SEND PRE-ROUND INTERVIEW SCHEDULE EMAIL ----
if (isset($_POST['ajax_send_interview_schedule_email'])) {
    header('Content-Type: application/json');
    $to      = filter_var($_POST['to'] ?? '', FILTER_SANITIZE_EMAIL);
    $subject = strip_tags($_POST['subject'] ?? 'Interview Invitation');
    $body    = strip_tags($_POST['body'] ?? '');
    $sid     = intval($_POST['sid'] ?? 0);
    $round   = intval($_POST['round'] ?? 0);

    $result = sendCompanyMail($dbConn, getScreeningCompanyId($dbConn, $sid), $to, $subject, $body);
    if ($result['success'] && $sid > 0 && $round > 0) {
        mysqli_query($dbConn, "UPDATE hr_interview_schedules SET notified_at=NOW() WHERE screening_id=$sid AND round_number=$round");
    }
    echo json_encode($result);
    exit;
}

// ---- AJAX: MARK PRE-ROUND INTERVIEW SCHEDULE AS NOTIFIED (WhatsApp path) ----
if (isset($_POST['ajax_mark_schedule_notified'])) {
    header('Content-Type: application/json');
    $sid   = intval($_POST['screening_id'] ?? 0);
    $round = intval($_POST['round_number'] ?? 0);
    mysqli_query($dbConn, "UPDATE hr_interview_schedules SET notified_at=NOW() WHERE screening_id=$sid AND round_number=$round");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: MARK ROUND CONGRATULATION AS NOTIFIED (WhatsApp path) ----
if (isset($_POST['ajax_mark_round_notified'])) {
    header('Content-Type: application/json');
    $sid   = intval($_POST['sid'] ?? 0);
    $round = intval($_POST['round'] ?? 0);
    if ($sid > 0 && $round > 0) {
        mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET notified_at=NOW(), notify_type='congrats' WHERE screening_id=$sid AND round_number=$round");
    }
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: GET POSITIONS BY DEPT ----
if (isset($_POST['ajax_get_positions_by_dept'])) {
    header('Content-Type: application/json');
    $dept_name = mysqli_real_escape_string($dbConn, $_POST['department']);
    $dept_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dept_name' LIMIT 1"));
    if ($dept_row) {
        $q = mysqli_query($dbConn, "SELECT id, title, worker_category FROM hr_positions WHERE department_id=".$dept_row['id']." ORDER BY title ASC");
        $positions = [];
        while($r = mysqli_fetch_assoc($q)) $positions[] = $r;
        echo json_encode(['success'=>true, 'positions'=>$positions, 'debug'=>"dept_id=".$dept_row['id'].", count=".count($positions)]);
    } else {
        echo json_encode(['success'=>false, 'positions'=>[], 'debug'=>"Department not found: ".$dept_name]);
    }
    exit;
}

// ---- AJAX: SET POSITION CATEGORY (Professional / Blue Collar) — same effect as the
// "Manage Position Categories" panel in hr-OJE.php, exposed here too for convenience. ----
if (isset($_POST['ajax_set_position_category'])) {
    header('Content-Type: application/json');
    $pos_id = intval($_POST['position_id'] ?? 0);
    $cat    = in_array($_POST['worker_category'] ?? '', ['professional', 'blue_collar'], true) ? $_POST['worker_category'] : 'professional';
    if ($pos_id <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid position']); exit; }
    mysqli_query($dbConn, "UPDATE hr_positions SET worker_category='" . mysqli_real_escape_string($dbConn, $cat) . "' WHERE id=$pos_id");
    echo json_encode(['success'=>true]);
    exit;
}

// ---- AJAX: GET MESSAGE TEMPLATES (shared with hr_candidate_tracking.php) ----
if (isset($_GET['get_templates'])) {
    header('Content-Type: application/json');
    $rows = [];
    $q = mysqli_query($dbConn, "SELECT * FROM hr_message_templates ORDER BY title ASC");
    if ($q) while ($r = mysqli_fetch_assoc($q)) {
        $r['statuses'] = array_values(array_filter(array_map('trim', explode(',', $r['statuses']))));
        $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// ---- POST: SAVE MESSAGE TEMPLATE (add or edit) ----
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'save_template') {
    header('Content-Type: application/json');
    $tid       = intval($_POST['id'] ?? 0);
    $title     = trim($_POST['title'] ?? '');
    $body      = trim($_POST['body'] ?? '');
    $statuses  = isset($_POST['statuses']) && is_array($_POST['statuses']) ? $_POST['statuses'] : [];
    if (empty($statuses)) $statuses = ['General'];
    $statuses_str = mysqli_real_escape_string($dbConn, implode(',', $statuses));
    $title_esc = mysqli_real_escape_string($dbConn, $title);
    $body_esc  = mysqli_real_escape_string($dbConn, $body);
    $by_esc    = mysqli_real_escape_string($dbConn, $current_user_name);

    if ($title === '' || $body === '') {
        echo json_encode(['success' => false, 'error' => 'Title and message body are required.']); exit;
    }

    if ($tid > 0) {
        mysqli_query($dbConn, "UPDATE hr_message_templates SET title='$title_esc', statuses='$statuses_str', body='$body_esc' WHERE id=$tid");
    } else {
        mysqli_query($dbConn, "INSERT INTO hr_message_templates (title, statuses, body, created_by) VALUES ('$title_esc','$statuses_str','$body_esc','$by_esc')");
        $tid = mysqli_insert_id($dbConn);
    }
    echo json_encode(['success' => true, 'id' => $tid]); exit;
}

// ---- POST: DELETE MESSAGE TEMPLATE ----
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete_template') {
    header('Content-Type: application/json');
    $tid = intval($_POST['id'] ?? 0);
    mysqli_query($dbConn, "DELETE FROM hr_message_templates WHERE id=$tid");
    echo json_encode(['success' => true]); exit;
}

// ---- AJAX: DEBUG — view raw AI analysis JSON ----
if (isset($_GET['ajax_debug_analysis'])) {
    header('Content-Type: application/json');
    $sid = intval($_GET['id'] ?? 0);
    $sc  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT ai_analysis, eligibility_score, eligibility_status FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['error'=>'Not found']); exit; }
    echo json_encode([
        'eligibility_score'  => $sc['eligibility_score'],
        'eligibility_status' => $sc['eligibility_status'],
        'ai_analysis'        => $sc['ai_analysis'] ? json_decode($sc['ai_analysis'], true) : null
    ], JSON_PRETTY_PRINT);
    exit;
}


if (isset($_GET['ajax_view_candidate'])) {
    $sid = intval($_GET['id'] ?? 0);
    $sc  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) {
        // Candidate's main profile row was permanently removed (e.g. "Remove Completely" at
        // rejection). Fall back to showing surviving evaluation history instead of a dead end,
        // pulling whatever context we can from the permanent rejection log.
        $rej_ctx = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, position_applied, department, reason, round_name, rejected_by, kept_in_database, created_at FROM hr_rejection_log WHERE screening_id=$sid ORDER BY id DESC LIMIT 1"));
        $evals = [];
        $ev_q = mysqli_query($dbConn, "SELECT round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, status, hr_notes, rejection_reason, created_at FROM hr_screening_evaluations WHERE screening_id=$sid ORDER BY round_number ASC");
        while ($ev = mysqli_fetch_assoc($ev_q)) $evals[] = $ev;

        if (empty($evals)) {
            echo '<p style="color:red;padding:20px;">Not found. This candidate\'s profile was permanently removed and no round history remains.</p>';
            exit;
        }

        echo '<div style="background:#fef2f2;border:2px solid #fecaca;border-radius:12px;padding:18px 22px;margin-bottom:20px;">';
        echo '<div style="font-weight:800;color:#991b1b;font-size:15px;margin-bottom:4px;"><i class="fas fa-exclamation-triangle mr-2"></i>Profile Removed';
        if ($rej_ctx) echo ' — ' . htmlspecialchars($rej_ctx['candidate_name']);
        echo '</div>';
        echo '<div style="font-size:13px;color:#7f1d1d;">This candidate\'s full profile, resume, and JD were permanently deleted, as HR specifically requested removal from the database at the time of rejection. Only round evaluation records survive, shown below for reference.</div>';
        if ($rej_ctx) {
            echo '<div style="font-size:12px;color:#991b1b;margin-top:8px;">Position: <strong>' . htmlspecialchars($rej_ctx['position_applied']) . '</strong> &middot; Department: <strong>' . htmlspecialchars($rej_ctx['department']) . '</strong> &middot; Rejected at: <strong>' . htmlspecialchars($rej_ctx['round_name']) . '</strong></div>';
            if (isset($rej_ctx['kept_in_database']) && intval($rej_ctx['kept_in_database']) === 0) {
                echo '<div style="font-size:12px;color:#991b1b;margin-top:4px;"><i class="fas fa-user-slash mr-1"></i>Rejected by <strong>' . htmlspecialchars($rej_ctx['rejected_by']) . '</strong> on ' . date('d M Y, h:i A', strtotime($rej_ctx['created_at'])) . ' — HR chose "Remove Completely" for this candidate at rejection time.</div>';
            }
        }
        echo '</div>';

        echo '<h6 style="font-weight:800;color:var(--navy);margin-bottom:15px;border-bottom:2px solid #e0e7ff;padding-bottom:8px;">Round Evaluation History</h6>';
        $status_colors_fallback = ['Passed'=>'#10b981','Failed'=>'#ef4444','Pending'=>'#f59e0b','Override'=>'#f59e0b','Rejected'=>'#ef4444'];
        foreach ($evals as $ev) {
            $sc_col = $status_colors_fallback[$ev['status']] ?? '#64748b';
            echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:16px;margin-bottom:12px;">';
            echo '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">';
            echo '<div style="font-weight:800;color:#0f2557;font-size:14px;">Round ' . $ev['round_number'] . '</div>';
            echo '<span style="font-weight:800;font-size:12px;padding:3px 12px;border-radius:20px;background:' . $sc_col . '22;color:' . $sc_col . ';">' . htmlspecialchars($ev['status'] ?: 'Pending') . '</span>';
            echo '</div>';
            if ($ev['total_marks_possible'] > 0) {
                echo '<div style="font-size:13px;color:#334155;margin-bottom:6px;">Score: <strong>' . $ev['total_marks_obtained'] . ' / ' . $ev['total_marks_possible'] . '</strong> (' . round(floatval($ev['percentage']), 1) . '%) &middot; ' . htmlspecialchars($ev['rating_label'] ?? '') . '</div>';
            }
            echo '<div style="font-size:12px;color:#64748b;margin-bottom:6px;">Evaluator: ' . htmlspecialchars($ev['evaluator_name'] ?: '—') . ' &middot; ' . date('d M Y, h:i A', strtotime($ev['created_at'])) . '</div>';
            if (!empty($ev['hr_notes'])) {
                echo '<div style="background:#fff;border-left:3px solid #cbd5e1;padding:8px 12px;border-radius:6px;font-size:12px;color:#334155;margin-top:8px;"><strong>Notes:</strong> ' . nl2br(htmlspecialchars($ev['hr_notes'])) . '</div>';
            }
            if (!empty($ev['rejection_reason'])) {
                echo '<div style="background:#fee2e2;border-left:3px solid #ef4444;padding:8px 12px;border-radius:6px;font-size:12px;color:#991b1b;margin-top:8px;"><strong>Rejection Reason:</strong> ' . nl2br(htmlspecialchars($ev['rejection_reason'])) . '</div>';
            }
            echo '</div>';
        }
        exit;
    }

    $data  = $sc['ai_analysis'] ? json_decode($sc['ai_analysis'], true) : null;
    $score = floatval($sc['eligibility_score'] ?? 0);
    $effective_score = (isset($sc['hr_override_score']) && $sc['hr_override_score'] !== null) ? floatval($sc['hr_override_score']) : $score;
    // Blue Collar candidates always score 0 (Resume/JD/AI scoring is intentionally skipped for them) —
    // that isn't a real signal, so they're exempt from the below-90% Shortlist/Hire lock below.
    $is_bc_candidate = false;
    if (!empty($sc['position_id'])) {
        $wc_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=" . intval($sc['position_id']) . " LIMIT 1"));
        $is_bc_candidate = $wc_row && ($wc_row['worker_category'] === 'blue_collar');
    }
    $sc_color = $score >= 75 ? '#10b981' : ($score >= 50 ? '#f59e0b' : '#ef4444');
    $init  = strtoupper(substr($sc['candidate_name'],0,1) . (strpos($sc['candidate_name'],' ')!==false ? substr($sc['candidate_name'],strpos($sc['candidate_name'],' ')+1,1) : ''));
    $circ  = 2 * M_PI * 54;
    $dash  = $circ - ($score/100)*$circ;

    $status_classes = ['pending'=>'b-pending','eligible'=>'b-eligible','highly_eligible'=>'b-highly','partially_eligible'=>'b-partial','not_eligible'=>'b-not'];
    $dec_classes    = ['pending'=>'b-pending','shortlisted'=>'b-shortlisted','rejected'=>'b-rejected','hired'=>'b-hired','on_hold'=>'b-partial'];
    $slabel = str_replace('_',' ', ucfirst($sc['eligibility_status']));
    $sclass = $status_classes[$sc['eligibility_status']] ?? 'b-pending';
    ?>
    <div style="display:grid;grid-template-columns:260px 1fr;gap:24px;">
      <!-- Left -->
      <div style="background:#f8faff;border-radius:14px;padding:24px;border:1px solid #e0e7ff;">
        <div style="width:64px;height:64px;background:linear-gradient(135deg,#0f2557,#1a3fc4);border-radius:16px;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:22px;margin-bottom:16px;"><?php echo $init; ?></div>
        <h5 style="font-weight:800;color:#0f2557;margin-bottom:4px;"><?php echo htmlspecialchars($sc['candidate_name']); ?></h5>
        <div style="font-size:13px;color:#64748b;margin-bottom:14px;"><?php echo htmlspecialchars($sc['candidate_email'] ?: 'No email'); ?></div>
        <div style="font-size:13px;font-weight:700;margin-bottom:6px;"><i class="fas fa-briefcase mr-2" style="color:#1a3fc4;"></i><?php echo htmlspecialchars($sc['position_applied']); ?></div>
        <div style="font-size:13px;font-weight:700;margin-bottom:6px;"><i class="fas fa-building mr-2" style="color:#1a3fc4;"></i><?php echo htmlspecialchars($sc['department']); ?></div>
        <?php if ($sc['candidate_phone']): ?><div style="font-size:13px;font-weight:700;margin-bottom:6px;"><i class="fas fa-phone mr-2" style="color:#1a3fc4;"></i><?php echo htmlspecialchars($sc['candidate_phone']); ?></div><?php endif; ?>
        <div style="font-size:12px;color:#64748b;margin-bottom:16px;"><i class="fas fa-calendar mr-1"></i> <?php echo date('d M Y', strtotime($sc['created_at'])); ?></div>
        <a href="<?php echo htmlspecialchars($sc['resume_path']); ?>" target="_blank" style="display:block;text-align:center;padding:10px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;border-radius:10px;font-weight:700;font-size:13px;text-decoration:none;margin-bottom:8px;"><i class="fas fa-file-alt mr-1"></i> Download Resume</a>
        <?php if (!empty($sc['jd_path'])): ?>
        <a href="<?php echo htmlspecialchars($sc['jd_path']); ?>" target="_blank" style="display:block;text-align:center;padding:10px;background:linear-gradient(135deg,#6366f1,#4f46e5);color:#fff;border-radius:10px;font-weight:700;font-size:13px;text-decoration:none;margin-bottom:16px;"><i class="fas fa-file-contract mr-1"></i> Download JD</a>
        <?php endif; ?>
        <div style="border-top:1px solid #e0e7ff;padding-top:16px;">
          <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#0f2557;margin-bottom:10px;">HR Decision</div>
          <?php if ($can_override): ?>
          <div style="margin-bottom:10px;">
            <label style="font-size:11px;font-weight:700;color:var(--muted);display:block;margin-bottom:3px;">Override AI Score (0-100)</label>
            <input type="number" id="hrOverrideTxt" value="<?php echo htmlspecialchars($sc['hr_override_score'] ?? ''); ?>" min="0" max="100" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;" placeholder="Leave blank to use AI score">
          </div>
          <?php endif; ?>
          <?php $needs_override_lock = ($effective_score < 90 && !$can_override && !$is_bc_candidate); ?>
          <select id="hrDecisionSel" style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-weight:700;font-size:13px;margin-bottom:8px;">
            <?php foreach (['pending'=>'Pending','shortlisted'=>'Shortlisted','on_hold'=>'On Hold','rejected'=>'Rejected','hired'=>'Hired'] as $v=>$l): ?>
            <?php $is_locked_option = $needs_override_lock && in_array($v, ['shortlisted','hired']); ?>
            <option value="<?php echo $v; ?>" <?php echo ($sc['hr_decision']==$v)?'selected':''; ?> <?php echo $is_locked_option ? 'disabled' : ''; ?>><?php echo $l . ($is_locked_option ? ' (Locked — below 90%)' : ''); ?></option>
            <?php endforeach; ?>
          </select>
          <?php if ($needs_override_lock): ?>
          <div style="font-size:11px;color:#92400e;background:#fff7ed;border:1px solid #fcd34d;border-radius:6px;padding:6px 10px;margin-bottom:8px;">
            <i class="fas fa-lock mr-1"></i> Score is below 90% — only authorized HR can Shortlist or Hire this candidate.
          </div>
          <?php endif; ?>
          <textarea id="hrNotesTxt" style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;resize:vertical;height:70px;" placeholder="Internal notes..."><?php echo htmlspecialchars($sc['screening_notes'] ?? ''); ?></textarea>
          <button onclick="saveDecision(<?php echo $sid; ?>)" style="width:100%;margin-top:8px;padding:10px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-save mr-1"></i> Save Decision</button>
        </div>
        
        <?php if ($sc['hr_decision'] == 'shortlisted'): ?>
        <div style="border-top:1px solid #e0e7ff;padding-top:16px;margin-top:16px;" id="callingSection_<?php echo $sid; ?>">
          <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#0f2557;margin-bottom:10px;"><i class="fas fa-phone-alt mr-1" style="color:#1a3fc4;"></i> Candidate Calling</div>
          <?php
          $track_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id, current_status FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
          if ($track_row) {
              $tc = $status_colors_inline = [
                  'New'=>'#6366f1','Called'=>'#3b82f6','Interested'=>'#10b981','Not Interested'=>'#ef4444',
                  'Call Later'=>'#f59e0b','Callback'=>'#f97316','Scheduled'=>'#8b5cf6','Follow Up'=>'#06b6d4',
                  'No Response'=>'#94a3b8','Rejected'=>'#dc2626','Hired'=>'#059669'
              ][$track_row['current_status']] ?? '#6b7280';
              echo '<div style="font-size:12px;font-weight:700;text-align:center;padding:8px;border-radius:6px;background:'.$tc.'22;color:'.$tc.';margin-bottom:8px;">Status: '.htmlspecialchars($track_row['current_status']).'</div>';
              echo '<a href="hr_candidate_tracking.php" target="_blank" style="display:block;text-align:center;padding:9px;border:1px solid #e0e7ff;border-radius:8px;color:#1a3fc4;font-weight:700;font-size:12px;text-decoration:none;">Manage Calling Status &rarr;</a>';
          } else {
              // This should rarely show now since shortlisting auto-creates the row, but kept as a manual fallback
              echo '<button onclick="startCalling('.$sid.', this)" style="display:none;width:100%;padding:10px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-phone mr-1"></i> Start Calling</button>';
          }
          ?>
        </div>
        <?php endif; ?>

        <?php if ($sc['hr_decision'] == 'hired'): ?>
        <div style="border-top:1px solid #e0e7ff;padding-top:16px;margin-top:16px;">
          <div style="font-weight:800;font-size:12px;text-transform:uppercase;color:#0f2557;margin-bottom:10px;"><i class="fas fa-user-plus mr-1" style="color:#1a3fc4;"></i> Employee Onboarding</div>
          <?php
          $o_link_res = mysqli_query($dbConn, "SELECT * FROM hr_onboarding_links WHERE candidate_id=$sid LIMIT 1");
          $o_link = $o_link_res ? mysqli_fetch_assoc($o_link_res) : null;
          if ($o_link) {
              $base_url = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http") . "://$_SERVER[HTTP_HOST]";
              $path_parts = explode('/', parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
              array_pop($path_parts);
              $dir_path = implode('/', $path_parts);
              $onboard_url = $base_url . $dir_path . '/hr-employee-onboarding.php?token=' . $o_link['token'];
              
              echo '<div style="margin-bottom:10px;">
                    <input type="text" id="onboardLinkBox_'.$sid.'" value="'.htmlspecialchars($onboard_url).'" readonly style="width:100%;padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:12px;font-family:inherit;background:#f8faff;margin-bottom:8px;">
                    <button onclick="copyText(\'onboardLinkBox_'.$sid.'\')" style="width:100%;padding:9px 16px;border:none;border-radius:8px;background:#1a3fc4;color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-copy mr-1"></i>Copy Link</button>
                </div>';
              
              $status_bg = $o_link['status'] == 'approved' ? '#dcfce7' : ($o_link['status'] == 'submitted' ? '#fef08a' : ($o_link['status'] == 'declined' ? '#fee2e2' : '#f1f5f9'));
              $status_col = $o_link['status'] == 'approved' ? '#065f46' : ($o_link['status'] == 'submitted' ? '#854d0e' : ($o_link['status'] == 'declined' ? '#991b1b' : '#475569'));
              echo '<div style="font-size:12px;font-weight:700;text-align:center;padding:5px;border-radius:6px;background:'.$status_bg.';color:'.$status_col.';">Status: '.ucfirst($o_link['status']).'</div>';
              
              if ($o_link['status'] != 'approved') {
                  echo '<button onclick="generateOnboardingLink('.$sid.')" style="width:100%;margin-top:8px;padding:8px;border:1px solid #1a3fc4;border-radius:8px;background:#fff;color:#1a3fc4;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-sync-alt mr-1"></i> Regenerate Link</button>';
              }
          } else {
              echo '<button onclick="generateOnboardingLink('.$sid.')" style="width:100%;padding:10px;border:none;border-radius:8px;background:linear-gradient(135deg,#6366f1,#4f46e5);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-link mr-1"></i> Generate Onboarding Link</button>';
          }
          ?>
        </div>
        <?php endif; ?>
      </div>
      <!-- Right -->
      <div style="overflow:hidden; display:flex; flex-direction:column;">
        <!-- Tabs Nav -->
        <ul class="nav nav-tabs" style="border-bottom: 2px solid #e0e7ff; margin-bottom: 15px;">
            <li class="nav-item">
                <a class="nav-link active" data-toggle="tab" href="#tab-ai-analysis" style="font-weight:700; color:var(--navy); padding:10px 20px; border:none; border-bottom:3px solid transparent;" onclick="$(this).css('border-bottom', '3px solid var(--blue)').css('color', 'var(--navy)'); $('#tab-rounds-link').css('border-bottom', '3px solid transparent').css('color', 'var(--muted)'); localStorage.setItem('hrLastCandidateView_<?php echo $sid; ?>', JSON.stringify({tab:'ai'}));">AI Analysis</a>
            </li>
            <li class="nav-item">
                <a class="nav-link" id="tab-rounds-link" data-toggle="tab" href="#tab-interview-rounds" style="font-weight:700; color:var(--muted); padding:10px 20px; border:none; border-bottom:3px solid transparent;" onclick="$(this).css('border-bottom', '3px solid var(--blue)').css('color', 'var(--navy)'); $(this).parent().siblings().find('a').css('border-bottom', '3px solid transparent').css('color', 'var(--muted)'); loadInterviewRounds(<?php echo $sid; ?>, 0);">Interview Rounds</a>
            </li>
        </ul>
        <script>
            // Init tab styling
            $('#tab-ai-analysis').parent().parent().find('.nav-link.active').css('border-bottom', '3px solid var(--blue)');
        </script>

        <!-- Tabs Content -->
        <div class="tab-content" style="flex:1; overflow-y:auto; padding-right:5px;">
            <!-- Tab 1: AI Analysis -->
            <div class="tab-pane fade show active" id="tab-ai-analysis">
        <?php if ($data):
            $sm_html = '';
            foreach (($data['skills_matched'] ?? []) as $s) $sm_html .= '<span class="skill-tag skill-ok">'.htmlspecialchars($s).'</span>';
            if (!$sm_html) $sm_html = '<span style="color:#64748b;font-size:13px;">None detected</span>';

            $miss_html = '';
            foreach (($data['skills_missing'] ?? []) as $s) $miss_html .= '<span class="skill-tag skill-miss">'.htmlspecialchars($s).'</span>';
            if (!$miss_html) $miss_html = '<span style="color:#10b981;font-size:13px;">Full match!</span>';

            $jd_req_html = '';
            foreach (($data['jd_key_requirements'] ?? []) as $r) $jd_req_html .= '<span class="skill-tag" style="background:#ede9fe;color:#5b21b6;">'.htmlspecialchars($r).'</span>';

            $str_html = '';
            foreach (($data['strengths'] ?? []) as $s) $str_html .= '<div class="strength-item"><i class="fas fa-check mr-2"></i>'.htmlspecialchars($s).'</div>';

            $con_html = '';
            foreach (($data['concerns'] ?? []) as $s) $con_html .= '<div class="concern-item"><i class="fas fa-exclamation-triangle mr-2"></i>'.htmlspecialchars($s).'</div>';
            if (!$con_html) $con_html = '<div class="strength-item">No major concerns</div>';

            $q_html = '';
            foreach (($data['interview_questions'] ?? []) as $q) $q_html .= '<div class="q-item">'.htmlspecialchars($q).'</div>';

            $score_badge_class = $score >= 75 ? 'b-eligible' : ($score >= 50 ? 'b-partial' : 'b-not');
        ?>
        <div class="ai-panel">
          <div class="score-ring-wrap">
            <div class="score-ring">
              <svg width="130" height="130" viewBox="0 0 130 130">
                <circle cx="65" cy="65" r="54" fill="none" stroke="#e2e8f0" stroke-width="10"/>
                <circle cx="65" cy="65" r="54" fill="none" stroke="<?php echo $sc_color; ?>" stroke-width="10"
                  stroke-dasharray="<?php echo round($circ,2); ?>" stroke-dashoffset="<?php echo round($dash,2); ?>"
                  stroke-linecap="round"/>
              </svg>
              <div class="score-num"><span style="color:<?php echo $sc_color; ?>;"><?php echo round($score); ?></span><small>/100</small></div>
            </div>
            <div style="margin-top:10px;"><span class="badge-s <?php echo $score_badge_class; ?>" style="font-size:13px;padding:7px 18px;"><?php echo $slabel; ?></span></div>
            <p style="margin-top:10px;color:#64748b;font-size:13px;font-weight:600;max-width:460px;margin-left:auto;margin-right:auto;"><?php echo htmlspecialchars($data['candidate_summary'] ?? ''); ?></p>
          </div>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:8px;">
            <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:14px;">
              <div style="font-size:11px;font-weight:800;color:#1a3fc4;text-transform:uppercase;margin-bottom:4px;">Experience</div>
              <div style="font-size:15px;font-weight:800;color:#0f2557;"><?php echo htmlspecialchars($data['experience_years'] ?? 'Unknown'); ?></div>
            </div>
            <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:14px;">
              <div style="font-size:11px;font-weight:800;color:#1a3fc4;text-transform:uppercase;margin-bottom:4px;">Education</div>
              <div style="font-size:15px;font-weight:800;color:#0f2557;"><?php echo htmlspecialchars($data['education_level'] ?? 'Unknown'); ?></div>
            </div>
          </div>
          <div style="font-size:11px;color:#94a3b8;display:flex;align-items:center;gap:5px;margin-bottom:14px;">
            <i class="fas fa-info-circle"></i> Auto-detected by keyword scan — please verify against the resume before deciding.
          </div>

          <?php if (!empty($data['scoring_breakdown'])): ?>
          <div class="ai-section">
            <h6><i class="fas fa-chart-bar" style="color:#1a3fc4;"></i> Score Breakdown <span style="font-weight:600;font-size:10px;color:#94a3b8;text-transform:none;">(click a row for details)</span></h6>
            <?php foreach ($data['scoring_breakdown'] as $sb_idx => $sb): ?>
            <div style="margin-bottom:10px;cursor:pointer;" onclick="var d=document.getElementById('sbDetail_<?php echo $sid; ?>_<?php echo $sb_idx; ?>'); if(d) d.style.display = d.style.display==='none' ? 'block' : 'none';">
              <div style="display:flex;justify-content:space-between;font-size:12px;font-weight:700;color:#0f2557;margin-bottom:3px;">
                <span><i class="fas fa-chevron-right" style="font-size:9px;color:#94a3b8;margin-right:5px;"></i><?php echo htmlspecialchars($sb['label']); ?></span>
                <span><?php echo $sb['points']; ?> / <?php echo $sb['max']; ?> pts (<?php echo $sb['pct']; ?>%)</span>
              </div>
              <div class="pbar-wrap">
                <div class="pbar-fill" style="width:<?php echo min(100, $sb['pct']); ?>%;background:<?php echo $sb['pct'] >= 75 ? '#10b981' : ($sb['pct'] >= 40 ? '#f59e0b' : '#ef4444'); ?>;"></div>
              </div>
              <?php if (!empty($sb['detail'])): ?>
              <div id="sbDetail_<?php echo $sid; ?>_<?php echo $sb_idx; ?>" style="display:none;margin-top:6px;background:#f8fafc;border-left:3px solid #cbd5e1;border-radius:6px;padding:8px 10px;font-size:11px;font-weight:600;color:#475569;line-height:1.5;">
                <?php echo $sb['detail']; ?>
              </div>
              <?php endif; ?>
            </div>
            <?php endforeach; ?>
          </div>
          <?php endif; ?>
          <?php if ($jd_req_html): ?>
          <div class="ai-section">
            <h6><i class="fas fa-file-contract" style="color:#6366f1;"></i> Key JD Requirements</h6>
            <?php echo $jd_req_html; ?>
          </div>
          <?php endif; ?>
          <div class="ai-section"><h6><i class="fas fa-check-circle" style="color:#10b981;"></i> Skills / Requirements Matched</h6><?php echo $sm_html; ?></div>
          <div class="ai-section"><h6><i class="fas fa-times-circle" style="color:#ef4444;"></i> Skills / Requirements Missing</h6><?php echo $miss_html; ?></div>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:18px;">
            <div class="ai-section"><h6><i class="fas fa-star" style="color:#f59e0b;"></i> Strengths</h6><?php echo $str_html; ?></div>
            <div class="ai-section"><h6><i class="fas fa-exclamation-triangle" style="color:#f59e0b;"></i> Concerns</h6><?php echo $con_html; ?></div>
          </div>
          <?php if (!empty($data['jd_vs_resume_gap'])): ?>
          <div class="ai-section">
            <h6><i class="fas fa-balance-scale" style="color:#6366f1;"></i> JD vs Resume Gap</h6>
            <div style="background:#f5f3ff;border:1px solid #ede9fe;border-radius:10px;padding:16px;font-size:14px;font-weight:600;color:#4c1d95;line-height:1.7;"><?php echo htmlspecialchars($data['jd_vs_resume_gap']); ?></div>
          </div>
          <?php endif; ?>
          <?php if (!empty($data['recommendation'])): ?>
          <div class="ai-section">
            <h6><i class="fas fa-comment-dots" style="color:#1a3fc4;"></i> Recommendation</h6>
            <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:16px;font-size:14px;font-weight:600;color:#0369a1;line-height:1.7;"><?php echo htmlspecialchars($data['recommendation']); ?></div>
          </div>
          <?php endif; ?>
          <?php if ($q_html): ?>
          <div class="ai-section">
            <h6><i class="fas fa-question-circle" style="color:#1a3fc4;"></i> Interview Questions</h6>
            <?php echo $q_html; ?>
          </div>
          <?php endif; ?>
        </div>
        <?php else: ?>
        <div style="text-align:center;padding:50px;background:#f8faff;border-radius:14px;border:2px dashed #e0e7ff;">
          <i class="fas fa-robot" style="font-size:40px;color:#1a3fc4;margin-bottom:16px;display:block;"></i>
          <h5 style="color:#0f2557;font-weight:800;margin-bottom:8px;">Analysis Not Run Yet</h5>
          <p style="color:#64748b;margin-bottom:20px;">Click to compare the JD with the resume.</p>
          <button onclick="runAnalysis(<?php echo $sid; ?>, this)" style="padding:12px 28px;border:none;border-radius:10px;background:linear-gradient(135deg,#0f2557,#1a3fc4);color:#fff;font-family:inherit;font-weight:700;font-size:14px;cursor:pointer;">
            <i class="fas fa-search mr-2"></i>Run Keyword Analysis
          </button>
          <div id="aiResultBox_<?php echo $sid; ?>" style="margin-top:16px;"></div>
        </div>
        <?php endif; ?>
            </div>
            
            <!-- Tab 2: Interview Rounds -->
            <div class="tab-pane fade" id="tab-interview-rounds">
                <div id="interviewRoundsContainer">
                    <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--blue);"></i> Loading Rounds...</div>
                </div>
            </div>
        </div>
      </div>
    </div>
    <?php
    exit;
}

// ---- AJAX: LOAD INTERVIEW ROUNDS ----
if (isset($_GET['ajax_load_interview_round'])) {
    $sid = intval($_GET['screening_id'] ?? 0);
    $round_req = intval($_GET['round_number'] ?? 0);
    
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT department, position_id, hr_decision FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo '<p style="color:red;">Candidate not found.</p>'; exit; }
    
    $dept_name = mysqli_real_escape_string($dbConn, $sc['department']);
    $dept_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dept_name' LIMIT 1"));
    $dept_id = $dept_row ? $dept_row['id'] : 0;
    
    $pos_id = isset($sc['position_id']) ? intval($sc['position_id']) : 0;

    // Blue Collar candidates are exempt from the below-90% interview-round lock — the
    // Observation Period substitutes for strict interview scoring for that category.
    $is_bc_candidate = false;
    if ($pos_id > 0) {
        $wc_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=$pos_id LIMIT 1"));
        $is_bc_candidate = $wc_row && ($wc_row['worker_category'] === 'blue_collar');
    }

    $rounds = [];
    $rounds_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_rounds WHERE department_id=$dept_id AND position_id=$pos_id ORDER BY round_number ASC");
    while ($r = mysqli_fetch_assoc($rounds_res)) {
        $rounds[] = $r;
    }
    
    if (empty($rounds)) {
        echo '<div style="text-align:center;padding:40px;background:#f8faff;border-radius:14px;border:2px dashed #e0e7ff;"><i class="fas fa-layer-group" style="font-size:40px;color:var(--muted);margin-bottom:16px;display:block;"></i><h5 style="color:var(--navy);font-weight:800;margin-bottom:8px;">No Rounds Configured</h5><p style="color:var(--muted);">No interview rounds have been set up for the <strong>' . htmlspecialchars($dept_name) . '</strong> department.</p></div>';
        exit;
    }
    
    if ($round_req == 0) $round_req = $rounds[0]['round_number'];

    // ---- GATE: Round 1 requires tracking status to be 'Interested', 'Scheduled', 'Selected', or 'Hired' ----
    // EXCEPTION: If the candidate already has evaluation history (they went through rounds
    // before being rejected, hired, etc.), skip this gate entirely so their actual round history 
    // is visible instead of a false "never called" lock.
    $has_eval_history = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM hr_screening_evaluations WHERE screening_id=$sid LIMIT 1")) > 0;
    
    if ($round_req == $rounds[0]['round_number'] && !$has_eval_history) {
        $track_check = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id, current_status FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
        $allowed_statuses = ['Interested', 'Scheduled', 'Selected', 'Hired'];
        if (!$track_check || !in_array($track_check['current_status'], $allowed_statuses)) {
            if (!$track_check) {
                // No tracking row at all — candidate hasn't even been shortlisted/started calling yet
                echo '<div style="text-align:center;padding:40px;background:#fff7ed;border-radius:14px;border:2px dashed #fcd34d;">
                    <i class="fas fa-phone-slash" style="font-size:40px;color:#d97706;margin-bottom:16px;display:block;"></i>
                    <h5 style="color:#92400e;font-weight:800;margin-bottom:8px;">Round 1 Locked</h5>
                    <p style="color:#78350f;margin-bottom:6px;">This candidate hasn\'t been shortlisted and called yet.</p>
                    <p style="color:#78350f;margin-bottom:20px;font-size:13px;">Set HR Decision to <strong>Shortlisted</strong> first, then use <strong>Start Calling</strong> from the AI Analysis tab.</p>
                </div>';
            } else {
                $cur_status_label = htmlspecialchars($track_check['current_status']);
                echo '<div style="text-align:center;padding:40px;background:#fff7ed;border-radius:14px;border:2px dashed #fcd34d;">
                    <i class="fas fa-phone-slash" style="font-size:40px;color:#d97706;margin-bottom:16px;display:block;"></i>
                    <h5 style="color:#92400e;font-weight:800;margin-bottom:8px;">Round 1 Locked</h5>
                    <p style="color:#78350f;margin-bottom:6px;">Round 1 unlocks only after the candidate is marked as Interested, Scheduled, or Selected via the calling process.</p>
                    <p style="color:#78350f;margin-bottom:20px;font-size:13px;">Currently: <strong>'.$cur_status_label.'</strong></p>
                    <button onclick="openQuickCallingUpdate('.$sid.')" style="padding:10px 24px;border:none;border-radius:10px;background:linear-gradient(135deg,#f59e0b,#d97706);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">
                        <i class="fas fa-phone mr-2"></i>Update Calling Status
                    </button>
                </div>';
            }
            exit;
        }
    }

    // Informational banner: candidate is rejected — this history is read-only reference
    if (($sc['hr_decision'] ?? '') === 'rejected') {
        $rej_log_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT reason, round_name, rejected_by, created_at FROM hr_rejection_log WHERE screening_id=$sid ORDER BY id DESC LIMIT 1"));
        echo '<div style="background:#fee2e2;border:2px solid #fca5a5;border-radius:12px;padding:16px 20px;margin-bottom:18px;">';
        echo '<div style="font-weight:800;color:#991b1b;font-size:14px;margin-bottom:4px;"><i class="fas fa-times-circle mr-2"></i>This candidate was rejected';
        if ($rej_log_row) echo ' at: ' . htmlspecialchars($rej_log_row['round_name']);
        echo '</div>';
        if ($rej_log_row) {
            echo '<div style="font-size:12px;color:#b91c1c;">Reason: ' . htmlspecialchars($rej_log_row['reason']) . ' &middot; By: ' . htmlspecialchars($rej_log_row['rejected_by']) . ' &middot; ' . date('d M Y, h:i A', strtotime($rej_log_row['created_at'])) . '</div>';
        }
        echo '<div style="font-size:12px;color:#7f1d1d;margin-top:6px;">The round history below is shown for reference only.</div>';
        echo '</div>';
    }

    // ---- OVERALL SUMMARY PANEL ----
    $total_rounds = count($rounds);
    $rounds_passed = 0;
    $rounds_pending = 0;
    $rounds_failed = 0;
    $rounds_not_started = 0;
    $overall_avg_pct = 0;
    $pct_count = 0;

    $is_hired = ($sc['hr_decision'] ?? '') === 'hired';
    foreach ($rounds as $r) {
        // Offer-type rounds have no evaluation record — mark as Passed when candidate is hired
        if (($r['round_type'] ?? '') === 'offer' && $is_hired) {
            $rounds_passed++;
            continue;
        }
        $ev_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=" . $r['round_number'] . " LIMIT 1");
        $ev = $ev_res ? mysqli_fetch_assoc($ev_res) : null;
        if (!$ev) { $rounds_not_started++; }
        elseif (($ev['status'] ?? '') == 'Passed' || ($ev['status'] ?? '') == 'Override') { $rounds_passed++; $overall_avg_pct += floatval($ev['percentage'] ?? 0); $pct_count++; }
        elseif (($ev['status'] ?? '') == 'Failed') { $rounds_failed++; $overall_avg_pct += floatval($ev['percentage'] ?? 0); $pct_count++; }
        else { $rounds_pending++; }
    }
    $avg_pct = $pct_count > 0 ? round($overall_avg_pct / $pct_count) : 0;
    $progress_pct = $total_rounds > 0 ? round(($rounds_passed / $total_rounds) * 100) : 0;

    echo '<div style="background:linear-gradient(135deg,#0f2557,#1a3fc4);border-radius:14px;padding:20px;margin-bottom:20px;color:#fff;">';
    echo '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">';
    echo '<div><div style="font-weight:800;font-size:15px;margin-bottom:3px;"><i class="fas fa-layer-group mr-2"></i>Interview Progress Summary</div>';
    echo '<div style="font-size:12px;opacity:.75;">' . $total_rounds . ' Round' . ($total_rounds!=1?'s':'') . ' Configured</div></div>';
    echo '<div style="text-align:right;"><div style="font-size:28px;font-weight:800;">' . $progress_pct . '%</div><div style="font-size:11px;opacity:.75;">Overall Progress</div></div>';
    echo '</div>';

    // Progress bar
    echo '<div style="background:rgba(255,255,255,0.2);border-radius:99px;height:8px;margin-bottom:14px;">';
    echo '<div style="height:8px;border-radius:99px;background:linear-gradient(90deg,#10b981,#34d399);width:' . $progress_pct . '%;transition:.5s;"></div>';
    echo '</div>';

    // Stats row
    echo '<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:10px;">';
    $summary_items = [
        ['✅', 'Passed', $rounds_passed, '#dcfce7', '#065f46'],
        ['❌', 'Failed', $rounds_failed, '#fee2e2', '#991b1b'],
        ['⏳', 'Pending', $rounds_pending, '#fff7ed', '#92400e'],
        ['⬜', 'Not Started', $rounds_not_started, '#f1f5f9', '#475569'],
    ];
    foreach ($summary_items as $si) {
        echo '<div style="background:rgba(255,255,255,0.12);border-radius:10px;padding:10px;text-align:center;">';
        echo '<div style="font-size:18px;margin-bottom:3px;">' . $si[0] . '</div>';
        echo '<div style="font-size:20px;font-weight:800;">' . $si[2] . '</div>';
        echo '<div style="font-size:10px;opacity:.8;font-weight:700;">' . $si[1] . '</div>';
        echo '</div>';
    }
    echo '</div>';

    // Per-round mini status
    echo '<div style="margin-top:14px;display:flex;flex-wrap:wrap;gap:8px;">';
    foreach ($rounds as $r) {
        $rt = ($r['round_type'] ?? 'interview') == 'assignment' ? '📝' : (($r['round_type'] ?? '') == 'observation' ? '⏳' : (($r['round_type'] ?? '') == 'offer' ? '🤝' : (($r['round_type'] ?? '') == 'work_sample' ? '📎' : '🎤')));
        // Special case: offer round shows as Passed (Hired) when candidate is hired
        if (($r['round_type'] ?? '') === 'offer' && $is_hired) {
            $pill_bg = '#dcfce7'; $pill_txt = 'Hired ✅'; $pill_col = '#065f46';
        } else {
            $ev2_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=" . $r['round_number'] . " LIMIT 1");
            $ev2 = $ev2_res ? mysqli_fetch_assoc($ev2_res) : null;
            if (!$ev2) {
                $pill_bg = 'rgba(255,255,255,0.12)'; $pill_txt = 'Not Started'; $pill_col = 'rgba(255,255,255,0.7)';
            } elseif (($ev2['status'] ?? '') == 'Passed' || ($ev2['status'] ?? '') == 'Override') {
                $pill_bg = '#dcfce7'; $pill_txt = number_format(floatval($ev2['percentage'] ?? 0), 2) . '% ✅'; $pill_col = '#065f46';
            } elseif (($ev2['status'] ?? '') == 'Failed') {
                $pill_bg = '#fee2e2'; $pill_txt = number_format(floatval($ev2['percentage'] ?? 0), 2) . '% ❌'; $pill_col = '#991b1b';
            } else {
                $pill_bg = '#fff7ed'; $pill_txt = 'Pending ⏳'; $pill_col = '#92400e';
            }
        }
        echo '<div style="background:' . $pill_bg . ';color:' . $pill_col . ';border-radius:20px;padding:5px 12px;font-size:12px;font-weight:800;">';
        echo $rt . ' Round ' . $r['round_number'] . ': ' . htmlspecialchars($r['round_name']) . ' — ' . $pill_txt;
        echo '</div>';
    }
    echo '</div>';
    echo '</div>';
    // ---- END OVERALL SUMMARY ----
    
    // Render Round Tabs
    echo '<div style="display:flex;gap:10px;margin-bottom:20px;border-bottom:1px solid #e0e7ff;padding-bottom:10px;overflow-x:auto;">';
    foreach ($rounds as $r) {
        $isActive = ($r['round_number'] == $round_req);
        $bg = $isActive ? 'var(--blue)' : '#f8faff';
        $col = $isActive ? '#fff' : 'var(--muted)';
        $border = $isActive ? 'var(--blue)' : '#e0e7ff';
        
        // Check if evaluated — offer rounds use hr_decision instead of evaluations table
        $icon = '';
        if (($r['round_type'] ?? '') === 'offer' && $is_hired) {
            $icon = '<i class="fas fa-check-circle" style="color:'.($isActive?'#fff':'var(--success)').';margin-left:6px;"></i>';
        } else {
            $eval_check = mysqli_query($dbConn, "SELECT status FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=" . $r['round_number']);
            if (mysqli_num_rows($eval_check) > 0) {
                $eval_row = mysqli_fetch_assoc($eval_check);
                if ($eval_row['status'] == 'Passed') $icon = '<i class="fas fa-check-circle" style="color:'.($isActive?'#fff':'var(--success)').';margin-left:6px;"></i>';
                else if ($eval_row['status'] == 'Failed') $icon = '<i class="fas fa-times-circle" style="color:'.($isActive?'#fff':'var(--danger)').';margin-left:6px;"></i>';
                else $icon = '<i class="fas fa-clock" style="color:'.($isActive?'#fff':'var(--warn)').';margin-left:6px;"></i>';
            }
        }
        
        // Check if previous round is completed and passed
        $is_locked = false;
        $round_index = array_search($r, $rounds);
        if ($round_index > 0) {
            $prev_round_num = $rounds[$round_index - 1]['round_number'];
            $prev_eval_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$prev_round_num LIMIT 1");
            $prev_eval = $prev_eval_res ? mysqli_fetch_assoc($prev_eval_res) : null;
            
            if (!$prev_eval) {
                // Previous round not even submitted
                $is_locked = true;
            } elseif (!$is_bc_candidate && round(floatval($prev_eval['percentage'] ?? 0)) < 90 && ($prev_eval['status'] ?? '') != 'Override') {
                // Previous round below 90% and no Manager Override (Blue Collar candidates are exempt)
                $is_locked = true;
            }
        }

        if ($is_locked) {
            echo '<button disabled style="padding:8px 16px; border-radius:20px; border:1px solid #e2e8f0; background:#f1f5f9; color:#94a3b8; font-weight:700; font-size:12px; cursor:not-allowed; white-space:nowrap;">🔒 Round '.$r['round_number'].': '.htmlspecialchars($r['round_name']).'</button>';
        } else {
            echo '<button onclick="loadInterviewRounds('.$sid.', '.$r['round_number'].')" style="padding:8px 16px; border-radius:20px; border:1px solid '.$border.'; background:'.$bg.'; color:'.$col.'; font-weight:700; font-size:12px; cursor:pointer; white-space:nowrap;">Round '.$r['round_number'].': '.htmlspecialchars($r['round_name']).$icon.'</button>';
        }
    }
    echo '</div>';
    
    // Check if this round is assignment type
    $active_round_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_rounds WHERE department_id=$dept_id AND position_id=$pos_id AND round_number=$round_req LIMIT 1");
    $active_round_data = $active_round_res ? mysqli_fetch_assoc($active_round_res) : null;
    $is_assignment_round  = ($active_round_data && ($active_round_data['round_type'] ?? 'interview') == 'assignment');
    $is_offer_round       = ($active_round_data && ($active_round_data['round_type'] ?? '') == 'offer');
    $is_observation_round = ($active_round_data && ($active_round_data['round_type'] ?? '') == 'observation');
    $is_worksample_round  = ($active_round_data && ($active_round_data['round_type'] ?? '') == 'work_sample');
    $is_interview_round   = (!$is_assignment_round && !$is_offer_round && !$is_observation_round && !$is_worksample_round);

    // ---- PRE-ROUND SCHEDULING — show for ALL rounds per user request ----
    if (true) {
        $sched_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_interview_schedules WHERE screening_id=$sid AND round_number=$round_req LIMIT 1"));
        $cand_for_sched = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, candidate_email, candidate_phone, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));

        echo '<div style="background:#eff6ff;border:2px solid #bfdbfe;border-radius:12px;padding:18px;margin-bottom:20px;">';
        echo '<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">';
        echo '<div>';
        echo '<div style="font-weight:800;color:#1e3a8a;font-size:14px;"><i class="fas fa-calendar-alt mr-2"></i>Round ' . $round_req . ' Schedule</div>';
        if ($sched_row && !empty($sched_row['scheduled_datetime'])) {
            echo '<div style="font-size:13px;color:#1e40af;margin-top:5px;">Scheduled for: <strong>' . date('d M Y, h:i A', strtotime($sched_row['scheduled_datetime'])) . '</strong></div>';
            if (!empty($sched_row['notified_at'])) {
                echo '<div style="font-size:12px;color:#065f46;margin-top:3px;"><i class="fas fa-check-circle mr-1"></i>Candidate Notified: ' . date('d M Y, h:i A', strtotime($sched_row['notified_at'])) . '</div>';
            } else {
                echo '<div style="font-size:12px;color:#92400e;margin-top:3px;"><i class="fas fa-exclamation-circle mr-1"></i>Not yet notified</div>';
            }
        } else {
            echo '<div style="font-size:13px;color:#64748b;margin-top:5px;">No schedule set yet.</div>';
        }
        echo '</div>';
        echo '<button type="button" onclick=\'openScheduleInterviewModal(' . $sid . ', ' . $round_req . ', ' . json_encode($cand_for_sched['candidate_name'] ?? '') . ', ' . json_encode($cand_for_sched['candidate_email'] ?? '') . ', ' . json_encode($cand_for_sched['candidate_phone'] ?? '') . ', ' . json_encode($cand_for_sched['position_applied'] ?? '') . ', ' . json_encode($sched_row['scheduled_datetime'] ?? '') . ')\' style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#1e3a8a,#2563eb);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;white-space:nowrap;"><i class="fas fa-calendar-plus mr-1"></i>' . (($sched_row && !empty($sched_row['scheduled_datetime'])) ? 'Reschedule / Notify Again' : 'Schedule &amp; Notify Candidate') . '</button>';
        echo '</div>';
        echo '</div>';
    }

    if ($is_offer_round) {
        // Output a container for the Document Verification Panel and fetch it via AJAX
        echo '<div id="dvPanelContainer_' . $sid . '"><div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:#1a3fc4;"></i></div></div>';
        echo '<script>
        $(document).ready(function(){
            $.get("hr-document-verification.php?ajax_dv_panel=1&candidate_id=' . $sid . '", function(html) {
                $("#dvPanelContainer_' . $sid . '").html(html);
            });
        });
        </script>';

        exit;
    }

    if ($is_observation_round) {
        $obs_days = intval($active_round_data['observation_days'] ?? 0);
        $obs_cand = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, candidate_email, candidate_phone, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));
        $oc_name  = $obs_cand['candidate_name'] ?? '';
        $oc_email = $obs_cand['candidate_email'] ?? '';
        $oc_phone = $obs_cand['candidate_phone'] ?? '';
        $oc_pos   = $obs_cand['position_applied'] ?? '';

        // Fetch or create evaluation row for this round
        $obs_eval_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1");
        $obs_eval = $obs_eval_res ? mysqli_fetch_assoc($obs_eval_res) : null;

        if (!$obs_eval) {
            $evaluator_esc = mysqli_real_escape_string($dbConn, $current_user_name);
            mysqli_query($dbConn, "INSERT INTO hr_screening_evaluations (screening_id, round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, status, obs_start_date) VALUES ($sid, $round_req, '$evaluator_esc', 0, 0, 0, 'Observation', 'Pending', NOW())");
            $obs_eval_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1");
            $obs_eval = mysqli_fetch_assoc($obs_eval_res);
        }

        $start_ts = strtotime($obs_eval['obs_start_date'] ?? 'now');
        $end_ts   = $start_ts + ($obs_days * 86400);
        $now_ts   = time();
        $days_elapsed   = max(0, floor(($now_ts - $start_ts) / 86400));
        $days_remaining = max(0, ceil(($end_ts - $now_ts) / 86400));
        $progress_pct_obs = $obs_days > 0 ? min(100, round(($days_elapsed / $obs_days) * 100)) : 0;

        echo '<div style="background:#f8faff;border:2px solid #e0e7ff;border-radius:14px;padding:24px;">';
        echo '<div style="display:flex;align-items:center;gap:12px;margin-bottom:18px;">';
        echo '<div style="width:48px;height:48px;border-radius:12px;background:linear-gradient(135deg,#a78bfa,#7c3aed);color:#fff;display:flex;align-items:center;justify-content:center;font-size:20px;"><i class="fas fa-hourglass-half"></i></div>';
        echo '<div><div style="font-weight:800;color:var(--navy);font-size:16px;">Observation Period — ' . $obs_days . ' Days</div>';
        echo '<div style="font-size:12px;color:var(--muted);">Started: ' . date('d M Y', $start_ts) . ' &nbsp;|&nbsp; Expected End: ' . date('d M Y', $end_ts) . '</div></div>';
        echo '</div>';

        if (empty($obs_eval['obs_status'])) {
            // Progress bar
            echo '<div style="background:#e2e8f0;border-radius:99px;height:10px;margin-bottom:8px;">';
            echo '<div style="height:10px;border-radius:99px;background:linear-gradient(90deg,#a78bfa,#7c3aed);width:' . $progress_pct_obs . '%;"></div>';
            echo '</div>';
            echo '<div style="font-size:12px;color:var(--muted);font-weight:700;margin-bottom:20px;">' . $days_elapsed . ' / ' . $obs_days . ' days elapsed &middot; ' . $days_remaining . ' days remaining</div>';

            echo '<div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:18px;">';
            echo '<label style="font-weight:700;font-size:13px;color:var(--navy);display:block;margin-bottom:8px;">' . htmlspecialchars($active_round_data['round_name'] ?? 'Round') . ' Remarks / Notes</label>';
            echo '<textarea id="obsNotes_' . $obs_eval['id'] . '" class="fc" style="width:100%;height:80px;resize:vertical;margin-bottom:14px;" placeholder="Observation feedback..."></textarea>';
            echo '<div style="display:flex;gap:10px;">';
            echo '<button onclick="saveObservationStatus(' . $obs_eval['id'] . ',' . $sid . ',' . $round_req . ',\'completed\')" style="flex:1;padding:12px;border:none;border-radius:9px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-check-circle mr-1"></i> Mark as Completed</button>';
            echo '<button onclick="saveObservationStatus(' . $obs_eval['id'] . ',' . $sid . ',' . $round_req . ',\'not_completed\')" style="flex:1;padding:12px;border:none;border-radius:9px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-times-circle mr-1"></i> Not Completed</button>';
            echo '</div></div>';
        } elseif ($obs_eval['obs_status'] == 'completed') {
            echo '<div style="background:#f0fdf4;border:2px solid #86efac;border-radius:10px;padding:16px;">';
            echo '<div style="font-weight:800;color:#065f46;font-size:14px;margin-bottom:6px;"><i class="fas fa-check-circle mr-2"></i>Observation Period Completed</div>';
            echo '<div style="font-size:12px;color:#166534;">Marked on ' . date('d M Y, h:i A', strtotime($obs_eval['obs_marked_at'])) . '</div>';
            if (!empty($obs_eval['obs_notes'])) echo '<div style="margin-top:10px;background:#fff;border-radius:8px;padding:10px;font-size:13px;color:#065f46;">' . nl2br(htmlspecialchars($obs_eval['obs_notes'])) . '</div>';
            echo '</div>';
            echo '<div style="margin-top:12px;text-align:center;font-size:12px;font-weight:700;color:#065f46;">✅ Candidate is unlocked for the next round.</div>';
            echo '<div style="text-align:center;margin-top:14px;">';
            echo '<button onclick="openRoundNotifyModal('.$sid.','.$round_req.',\''.addslashes($oc_name).'\',\''.addslashes($oc_email).'\',\''.addslashes($oc_phone).'\',\''.addslashes($oc_pos).'\',true)" style="padding:9px 16px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;margin-right:6px;"><i class="fas fa-check-circle mr-1"></i>Congratulate Candidate</button>';
            echo '<button onclick="openRejectModal('.$sid.','.$round_req.',\''.addslashes(htmlspecialchars($active_round_data['round_name'] ?? 'Observation')).'\',\'observation\')" style="padding:9px 16px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;margin-right:6px;"><i class="fas fa-times-circle mr-1"></i>Reject Candidate</button>';
            echo '<button onclick="openRejectionNotifyModal('.$sid.','.$round_req.',\''.addslashes($oc_name).'\',\''.addslashes($oc_email).'\',\''.addslashes($oc_phone).'\',\''.addslashes($oc_pos).'\')" style="padding:9px 16px;border:none;border-radius:8px;background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-paper-plane mr-1"></i>Rejection Notify</button>';
            if (!empty($obs_eval['notified_at'])) {
                $obs_notify_label = ($obs_eval['notify_type'] ?? '') === 'reject' ? 'Rejection Notified' : 'Congratulated';
                echo '<div style="margin-top:12px; font-size:12px; font-weight:700; color:#065f46;"><i class="fas fa-check-circle" style="color:#10b981; margin-right:4px;"></i> '.$obs_notify_label.': '.date('d M Y, h:i A', strtotime($obs_eval['notified_at'])).'</div>';
            }
            echo '</div>';
            echo '<div style="text-align:center;margin-top:10px;"><button onclick="revertObservationStatus(' . $obs_eval['id'] . ',' . $sid . ',' . $round_req . ')" style="padding:6px 12px;border:none;border-radius:6px;background:#e5e7eb;color:#4b5563;font-size:11px;font-weight:700;cursor:pointer;"><i class="fas fa-undo mr-1"></i> Revert Status</button></div>';
        } else {
            echo '<div style="background:#fee2e2;border:2px solid #fca5a5;border-radius:10px;padding:16px;">';
            echo '<div style="font-weight:800;color:#991b1b;font-size:14px;margin-bottom:6px;"><i class="fas fa-times-circle mr-2"></i>Observation Period Not Completed</div>';
            echo '<div style="font-size:12px;color:#b91c1c;">Marked on ' . date('d M Y, h:i A', strtotime($obs_eval['obs_marked_at'])) . '</div>';
            if (!empty($obs_eval['obs_notes'])) echo '<div style="margin-top:10px;background:#fff;border-radius:8px;padding:10px;font-size:13px;color:#991b1b;">' . nl2br(htmlspecialchars($obs_eval['obs_notes'])) . '</div>';
            echo '</div>';
            echo '<div style="margin-top:12px;text-align:center;font-size:12px;font-weight:700;color:#991b1b;">🔒 Candidate is blocked from progressing to the next round.</div>';
            echo '<div style="text-align:center;margin-top:14px;">';
            echo '<button onclick="openRejectModal('.$sid.','.$round_req.',\''.addslashes(htmlspecialchars($active_round_data['round_name'] ?? 'Observation')).'\',\'observation\')" style="padding:9px 16px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;margin-right:6px;"><i class="fas fa-times-circle mr-1"></i>Reject Candidate</button>';
            echo '<button onclick="openRejectionNotifyModal('.$sid.','.$round_req.',\''.addslashes($oc_name).'\',\''.addslashes($oc_email).'\',\''.addslashes($oc_phone).'\',\''.addslashes($oc_pos).'\')" style="padding:9px 16px;border:none;border-radius:8px;background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-paper-plane mr-1"></i>Rejection Notify</button>';
            echo '</div>';
            echo '<div style="text-align:center;margin-top:10px;"><button onclick="revertObservationStatus(' . $obs_eval['id'] . ',' . $sid . ',' . $round_req . ')" style="padding:6px 12px;border:none;border-radius:6px;background:#e5e7eb;color:#4b5563;font-size:11px;font-weight:700;cursor:pointer;"><i class="fas fa-undo mr-1"></i> Revert Status</button></div>';
        }

        echo '</div>';
        exit;
    }

    if ($is_worksample_round) {
        $cand_res = mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1");
        $cand_data = $cand_res ? mysqli_fetch_assoc($cand_res) : null;
        $cand_name = $cand_data['candidate_name'] ?? '';
        $cand_pos  = $cand_data['position_applied'] ?? '';
        $cand_email = $cand_data['candidate_email'] ?? '';
        $cand_phone = $cand_data['candidate_phone'] ?? '';

        $existing_link_res = mysqli_query($dbConn, "SELECT * FROM hr_assignment_links WHERE candidate_id=$sid AND round_number=$round_req ORDER BY id DESC LIMIT 1");
        $existing_link_row = $existing_link_res ? mysqli_fetch_assoc($existing_link_res) : null;
        $base_url = (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
        $existing_link_url = $existing_link_row ? $base_url . '/hr_worksample.php?token=' . $existing_link_row['token'] : '';
        $link_status = $existing_link_row ? $existing_link_row['status'] : 'not_generated';
        $link_expiry = ($existing_link_row && $existing_link_row['expiry_at']) ? date('d M Y, h:i A', strtotime($existing_link_row['expiry_at'])) : 'No Expiry';
        $prefilled_msg = "Dear {$cand_name},\n\nAs part of your selection process for the *{$cand_pos}* role, please share a sample of your previous work / portfolio / pitch using the secure link below:\n{$existing_link_url}\n\nLink Expiry: {$link_expiry}\n\nBest Regards,\nHR Team";

        echo '<div style="background:#f8faff;border:2px solid #e0e7ff;border-radius:14px;padding:22px;">';

        if ($link_status == 'submitted') {
            echo '<div style="background:#dcfce7;border:1px solid #86efac;border-radius:10px;padding:14px;margin-bottom:18px;"><span style="font-size:22px;">✅</span> <strong style="color:#065f46;">Work Sample Submitted</strong> — review the files below and give a rating.</div>';
        } elseif ($link_status == 'pending') {
            echo '<div style="background:#fff7ed;border:1px solid #fcd34d;border-radius:10px;padding:14px;margin-bottom:18px;"><span style="font-size:22px;">⏳</span> <strong style="color:#92400e;">Link Sent — Awaiting Upload</strong> (Expires: '.$link_expiry.')</div>';
        } else {
            echo '<div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:14px;margin-bottom:18px;"><span style="font-size:22px;">🔗</span> <strong style="color:#0369a1;">Upload Link Not Generated Yet</strong></div>';
        }

        if ($existing_link_row) {
            $tab_count = intval($existing_link_row['tab_switch_count'] ?? 0);
            $is_flagged = intval($existing_link_row['is_flagged'] ?? 0);
            if ($is_flagged) {
                echo '<div style="background:#fee2e2;border:2px solid #fca5a5;border-radius:10px;padding:14px;margin-bottom:16px;display:flex;align-items:center;gap:10px;">
                    <span style="font-size:22px;">🚨</span>
                    <div>
                        <div style="font-weight:800;color:#991b1b;font-size:14px;">Session Flagged — Tab Switching Detected</div>
                        <div style="font-size:12px;color:#b91c1c;margin-top:3px;">Candidate switched tabs <strong>' . $tab_count . ' times</strong> and was locked out. Work sample was not submitted normally.</div>
                    </div>
                </div>';
            } elseif ($tab_count > 0) {
                echo '<div style="background:#fff7ed;border:2px solid #fcd34d;border-radius:10px;padding:14px;margin-bottom:16px;display:flex;align-items:center;gap:10px;">
                    <span style="font-size:22px;">⚠️</span>
                    <div>
                        <div style="font-weight:800;color:#92400e;font-size:14px;">Tab Switch Attempts: ' . $tab_count . ' / 3</div>
                        <div style="font-size:12px;color:#78350f;margin-top:3px;">Candidate switched tabs during the upload. Monitor carefully.</div>
                    </div>
                </div>';
            } elseif ($existing_link_row['status'] != 'not_generated') {
                echo '<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:12px;margin-bottom:16px;display:flex;align-items:center;gap:8px;">
                    <span style="font-size:18px;">✅</span>
                    <div style="font-weight:700;color:#065f46;font-size:13px;">No tab switching detected — Clean session</div>
                </div>';
            }

            // Identity verification display
            if (!empty($existing_link_row['candidate_signature']) || !empty($existing_link_row['candidate_location'])) {
                $sig_img = $existing_link_row['candidate_signature'] ?? '';
                $loc_str = $existing_link_row['candidate_location'] ?? 'Unknown';
                echo '<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px;margin-bottom:16px;">
                    <div style="font-weight:800;color:#0f2557;font-size:13px;margin-bottom:10px;"><i class="fas fa-shield-alt mr-2" style="color:#1a3fc4;"></i>Identity Verification</div>
                    <div style="display:flex;gap:20px;">
                        <div style="flex:1;">
                            <div style="font-size:11px;color:#64748b;font-weight:700;margin-bottom:4px;text-transform:uppercase;">Digital Signature</div>
                            <div style="border:1px dashed #cbd5e1;border-radius:6px;background:#fff;padding:4px;text-align:center;">';
                if ($sig_img) echo '<img src="' . $sig_img . '" style="max-width:100%;max-height:80px;">';
                else echo '<div style="color:#94a3b8;font-size:12px;padding:20px;">No signature captured</div>';
                echo '      </div>
                        </div>
                        <div style="flex:1;">
                            <div style="font-size:11px;color:#64748b;font-weight:700;margin-bottom:4px;text-transform:uppercase;">Location Captured</div>
                            <div style="background:#fff;border:1px solid #e2e8f0;border-radius:6px;padding:12px;font-size:12px;color:#334155;font-weight:600;">
                                ' . (function() use ($loc_str) {
                                    $parts = explode("|", $loc_str);
                                    $addr = $parts[0];
                                    $coords_str = count($parts) > 1 ? $parts[1] : $loc_str;
                                    $out = '<i class="fas fa-map-marker-alt mr-2" style="color:#ef4444;"></i> ' . htmlspecialchars($addr);
                                    $coords = explode(",", $coords_str);
                                    if (count($coords) == 2 && is_numeric(trim($coords[0])) && is_numeric(trim($coords[1]))) {
                                        $out .= '<br><a href="https://www.google.com/maps?q=' . trim($coords[0]) . ',' . trim($coords[1]) . '" target="_blank" style="font-size:11px;color:#1a3fc4;font-weight:700;text-decoration:none;margin-top:4px;display:inline-block;"><i class="fas fa-external-link-alt mr-1"></i>View on Google Maps</a>';
                                    }
                                    return $out;
                                })() . '
                            </div>
                        </div>
                    </div>
                </div>';
            }
        }

        if ($link_status !== 'submitted') {
            echo '<div style="background:#fff;border:1px solid #e0e7ff;border-radius:10px;padding:16px;margin-bottom:16px;">';
            if ($existing_link_url) {
                echo '<div style="display:flex;gap:8px;align-items:center;margin-bottom:10px;">
                    <input type="text" id="wsLinkBox_'.$sid.'" value="'.htmlspecialchars($existing_link_url).'" readonly style="flex:1;padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:12px;">
                    <button onclick="copyText(\'wsLinkBox_'.$sid.'\')" style="padding:9px 16px;border:none;border-radius:8px;background:#1a3fc4;color:#fff;font-weight:700;font-size:12px;cursor:pointer;">Copy</button>
                </div>';
            }
            echo '<div style="display:flex;gap:8px;align-items:center;">
                <select id="wsExpirySelect_'.$sid.'" style="padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
                    <option value="48">48 Hours</option><option value="168">7 Days</option><option value="0">No Expiry</option>
                </select>
                <button onclick="generateWorksampleLink('.$sid.', '.$round_req.', '.$dept_id.', '.$pos_id.')" style="padding:9px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-weight:700;font-size:13px;cursor:pointer;">'.($existing_link_url ? 'Regenerate Link' : 'Generate Upload Link').'</button>
            </div></div>';

            if ($existing_link_url) {
                echo '<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;margin-bottom:16px;">
                    <div class="fg"><label class="fl">Phone</label><input type="text" id="wsWaPhone_'.$sid.'" class="fc" value="'.htmlspecialchars($cand_phone).'"></div>
                    <div class="fg"><label class="fl">Message</label><textarea id="wsWaMsg_'.$sid.'" class="fc" style="height:110px;">'.htmlspecialchars($prefilled_msg).'</textarea></div>
                    <button type="button" onclick="sendWorksampleWa('.$sid.')" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp"></i> Open WhatsApp</button>
                </div>';
                echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;">
                    <div class="fg"><label class="fl">To</label><input type="email" id="wsEmailTo_'.$sid.'" class="fc" value="'.htmlspecialchars($cand_email).'"></div>
                    <div class="fg"><label class="fl">Subject</label><input type="text" id="wsEmailSubj_'.$sid.'" class="fc" value="Work Sample Request — '.htmlspecialchars($cand_pos).'"></div>
                    <div class="fg"><label class="fl">Message</label><textarea id="wsEmailBody_'.$sid.'" class="fc" style="height:150px;">'.htmlspecialchars($prefilled_msg).'</textarea></div>
                    <div id="wsEmailAlert_'.$sid.'"></div>
                    <button type="button" onclick="sendWorksampleEmail(this, '.$sid.')" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Send Email</button>
                </div>';
            }
        }

        if ($link_status == 'submitted') {
            $files_res = mysqli_query($dbConn, "SELECT * FROM hr_worksample_files WHERE link_id=" . $existing_link_row['id'] . " ORDER BY id ASC");
            echo '<h6 style="font-weight:800;color:#0f2557;margin:18px 0 12px;border-bottom:2px solid #e0e7ff;padding-bottom:8px;">Uploaded Files</h6>';
            while ($f = mysqli_fetch_assoc($files_res)) {
                echo '<div style="display:flex;justify-content:space-between;align-items:center;background:#fff;border:1px solid #e2e8f0;border-radius:8px;padding:10px 14px;margin-bottom:8px;">
                    <span><i class="fas fa-paperclip mr-2" style="color:#1a3fc4;"></i>'.htmlspecialchars($f['file_name']).'</span>
                    <a href="'.htmlspecialchars($f['file_path']).'" target="_blank" style="font-weight:700;color:#1a3fc4;">Download</a>
                </div>';
            }

            $eval_res3 = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1");
            $eval_row3 = $eval_res3 ? mysqli_fetch_assoc($eval_res3) : null;
            if (!$eval_row3) {
                $evaluator_esc = mysqli_real_escape_string($dbConn, $current_user_name);
                mysqli_query($dbConn, "INSERT INTO hr_screening_evaluations (screening_id, round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, status) VALUES ($sid, $round_req, '$evaluator_esc', 0, 100, 0, 'Work Sample', 'Pending')");
                $eval_row3 = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1"));
            }

            if ($eval_row3['status'] == 'Pending') {
                echo '<div style="background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:18px;margin-top:14px;">
                    <label class="fl">HR Rating</label>
                    <select id="wsRating_'.$eval_row3['id'].'" class="fc" style="max-width:320px;">
                        <option value="">-- Select Rating --</option>
                        <option value="100">💎 Significant → 100%</option>
                        <option value="90">🏆 Outstanding → 90%</option>
                        <option value="80">⭐ Excellent → 80%</option>
                        <option value="70">✨ Good → 70%</option>
                        <option value="60">👍 Average → 60%</option>
                        <option value="40">🚫 Poor → 40%</option>
                        <option value="0">❌ Failed → 0%</option>
                    </select>
                    <label class="fl" style="margin-top:12px;">' . htmlspecialchars($active_round_data['round_name'] ?? 'Round') . ' Remarks</label>
                    <textarea id="wsNotes_'.$eval_row3['id'].'" class="fc" style="height:70px;"></textarea>
                    <div style="margin-top:12px;">
                    <button onclick="saveWorksampleRating('.$eval_row3['id'].','.$sid.','.$round_req.')" style="padding:10px 22px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-weight:700;cursor:pointer;"><i class="fas fa-check-circle mr-1"></i>Success &amp; Submit</button>
                    <button type="button" onclick="openRejectModal('.$sid.', '.$round_req.', \''.addslashes(htmlspecialchars($active_round_data['round_name'] ?? ('Round ' . $round_req))).'\', \'work_sample\')" style="padding:10px 22px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-weight:700;cursor:pointer;margin-left:8px;"><i class="fas fa-times-circle mr-1"></i>Reject</button>
                    </div>
                </div>';
                echo '</div>'; exit;
            }
        }
        echo '</div>';
        // Only let execution fall through to the shared results-display block
        // when the work sample has been submitted AND already rated by HR.
        // Otherwise, stop here — there's nothing else to render for this round.
        $ws_already_rated = false;
        if ($link_status == 'submitted') {
            $ws_eval_check = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT status FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1"));
            if ($ws_eval_check && $ws_eval_check['status'] != 'Pending') $ws_already_rated = true;
        }
        if (!$ws_already_rated) exit;
    }

    if ($is_assignment_round) {
        // Fetch candidate details for pre-filled message
        $cand_res = mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1");
        $cand_data = $cand_res ? mysqli_fetch_assoc($cand_res) : null;
        $cand_name = $cand_data['candidate_name'] ?? '';
        $cand_pos  = $cand_data['position_applied'] ?? '';
        $cand_email = $cand_data['candidate_email'] ?? '';
        $cand_phone = $cand_data['candidate_phone'] ?? '';
        $prev_round = $round_req - 1;

        // Fetch existing link if already generated
        $existing_link_res = mysqli_query($dbConn, "SELECT * FROM hr_assignment_links WHERE candidate_id=$sid AND round_number=$round_req ORDER BY id DESC LIMIT 1");
        $existing_link_row = $existing_link_res ? mysqli_fetch_assoc($existing_link_res) : null;
        $base_url = (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . '/hrm';
        $existing_link_url = $existing_link_row ? $base_url . '/hr_assignment.php?token=' . $existing_link_row['token'] : '';
        $link_status = $existing_link_row ? $existing_link_row['status'] : 'not_generated';
        $link_expiry = ($existing_link_row && $existing_link_row['expiry_at']) ? date('d M Y, h:i A', strtotime($existing_link_row['expiry_at'])) : 'No Expiry';

        // Validity statement — expressed as a duration, not just a bare timestamp
        $link_validity_line = 'This link does not have an expiry.';
        if ($existing_link_row && $existing_link_row['expiry_at']) {
            $hours_left = ceil((strtotime($existing_link_row['expiry_at']) - time()) / 3600);
            $link_validity_line = $hours_left > 0
                ? "This link is valid for the next {$hours_left} hour(s) and will expire on {$link_expiry}."
                : "This link has expired.";
        }

        // Pre-filled message
        $prefilled_msg = "Dear {$cand_name},\n\nCongratulations on successfully clearing Round {$prev_round} of your selection process for the *{$cand_pos}* role!\n\nYou have been shortlisted for the next stage — *Assignment Round*.\n\nPlease complete your assignment using the secure link below:\n{$existing_link_url}\n\n{$link_validity_line}\n\nImportant Rules:\n- Please complete the assignment in one sitting — switching tabs or windows is not allowed.\n- Copying and pasting is disabled during the assignment.\n- Do not share this link with anyone.\n\nPlease complete it at your earliest convenience.\n\nBest Regards,\nHR Team";
        $wa_msg = urlencode($prefilled_msg);
        $email_subject = urlencode("Assignment Round — {$cand_pos} Application");
        $email_body    = urlencode($prefilled_msg);

        echo '<div style="background:#f8faff;border:2px solid #e0e7ff;border-radius:14px;padding:22px;">';
        
        // Status banner
        if ($link_status == 'submitted') {
            echo '<div style="background:#dcfce7;border:1px solid #86efac;border-radius:10px;padding:14px;margin-bottom:18px;display:flex;align-items:center;gap:10px;">
                <span style="font-size:22px;">✅</span>
                <div><div style="font-weight:800;color:#065f46;font-size:14px;">Assignment Submitted by Candidate</div>
                <div style="font-size:12px;color:#166534;margin-top:2px;">The candidate has completed the assignment. You can now review and give marks below.</div></div>
            </div>';
        } elseif ($link_status == 'pending') {
            echo '<div style="background:#fff7ed;border:1px solid #fcd34d;border-radius:10px;padding:14px;margin-bottom:18px;display:flex;align-items:center;gap:10px;">
                <span style="font-size:22px;">⏳</span>
                <div><div style="font-weight:800;color:#92400e;font-size:14px;">Link Sent — Awaiting Candidate Submission</div>
                <div style="font-size:12px;color:#78350f;margin-top:2px;">Expires: '.$link_expiry.'</div></div>
            </div>';
        } else {
            echo '<div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:10px;padding:14px;margin-bottom:18px;display:flex;align-items:center;gap:10px;">
                <span style="font-size:22px;">🔗</span>
                <div><div style="font-weight:800;color:#0369a1;font-size:14px;">Assignment Link Not Generated Yet</div>
                <div style="font-size:12px;color:#0284c7;margin-top:2px;">Generate a secure link to share with '.$cand_name.'</div></div>
            </div>';
        }

        // Tab switch warning display
        $link_data_res = mysqli_query($dbConn, "SELECT * FROM hr_assignment_links WHERE candidate_id=$sid AND round_number=$round_req ORDER BY id DESC LIMIT 1");
        $link_data = $link_data_res ? mysqli_fetch_assoc($link_data_res) : null;
        if ($link_data) {
            $tab_count = intval($link_data['tab_switch_count'] ?? 0);
            $is_flagged = intval($link_data['is_flagged'] ?? 0);
            if ($is_flagged) {
                echo '<div style="background:#fee2e2;border:2px solid #fca5a5;border-radius:10px;padding:14px;margin-bottom:16px;display:flex;align-items:center;gap:10px;">
                    <span style="font-size:22px;">🚨</span>
                    <div>
                        <div style="font-weight:800;color:#991b1b;font-size:14px;">Session Flagged — Tab Switching Detected</div>
                        <div style="font-size:12px;color:#b91c1c;margin-top:3px;">Candidate switched tabs <strong>' . $tab_count . ' times</strong> and was locked out. Assignment was not submitted normally.</div>
                    </div>
                </div>';
            } elseif ($tab_count > 0) {
                echo '<div style="background:#fff7ed;border:2px solid #fcd34d;border-radius:10px;padding:14px;margin-bottom:16px;display:flex;align-items:center;gap:10px;">
                    <span style="font-size:22px;">⚠️</span>
                    <div>
                        <div style="font-weight:800;color:#92400e;font-size:14px;">Tab Switch Attempts: ' . $tab_count . ' / 3</div>
                        <div style="font-size:12px;color:#78350f;margin-top:3px;">Candidate switched tabs during the assignment. Monitor carefully.</div>
                    </div>
                </div>';
            } else {
                echo '<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:12px;margin-bottom:16px;display:flex;align-items:center;gap:8px;">
                    <span style="font-size:18px;">✅</span>
                    <div style="font-weight:700;color:#065f46;font-size:13px;">No tab switching detected — Clean session</div>
                </div>';
            }
        }
        
        // Verification display
        if ($link_data && (!empty($link_data['candidate_signature']) || !empty($link_data['candidate_location']))) {
            $sig_img = $link_data['candidate_signature'] ?? '';
            $loc_str = $link_data['candidate_location'] ?? 'Unknown';
            echo '<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px;margin-bottom:16px;">
                <div style="font-weight:800;color:#0f2557;font-size:13px;margin-bottom:10px;"><i class="fas fa-shield-alt mr-2" style="color:#1a3fc4;"></i>Identity Verification</div>
                <div style="display:flex;gap:20px;">
                    <div style="flex:1;">
                        <div style="font-size:11px;color:#64748b;font-weight:700;margin-bottom:4px;text-transform:uppercase;">Digital Signature</div>
                        <div style="border:1px dashed #cbd5e1;border-radius:6px;background:#fff;padding:4px;text-align:center;">';
            if ($sig_img) echo '<img src="' . $sig_img . '" style="max-width:100%;max-height:80px;">';
            else echo '<div style="color:#94a3b8;font-size:12px;padding:20px;">No signature captured</div>';
            echo '      </div>
                    </div>
                    <div style="flex:1;">
                        <div style="font-size:11px;color:#64748b;font-weight:700;margin-bottom:4px;text-transform:uppercase;">Location Captured</div>
                        <div style="background:#fff;border:1px solid #e2e8f0;border-radius:6px;padding:12px;font-size:12px;color:#334155;font-weight:600;">
                            ' . (function() use ($loc_str) {
                                $parts = explode("|", $loc_str);
                                $addr = $parts[0];
                                $coords_str = count($parts) > 1 ? $parts[1] : $loc_str;
                                
                                $out = '<i class="fas fa-map-marker-alt mr-2" style="color:#ef4444;"></i> ' . htmlspecialchars($addr);
                                
                                $coords = explode(",", $coords_str);
                                if (count($coords) == 2 && is_numeric(trim($coords[0])) && is_numeric(trim($coords[1]))) {
                                    $out .= '<br><a href="https://www.google.com/maps?q=' . trim($coords[0]) . ',' . trim($coords[1]) . '" target="_blank" style="font-size:11px;color:#1a3fc4;font-weight:700;text-decoration:none;margin-top:4px;display:inline-block;"><i class="fas fa-external-link-alt mr-1"></i>View on Google Maps</a>';
                                }
                                return $out;
                            })() . '
                        </div>
                    </div>
                </div>
            </div>';
        }

        // Candidate info
        echo '<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:18px;">
            <div style="background:#fff;border:1px solid #e0e7ff;border-radius:9px;padding:12px;">
                <div style="font-size:10px;font-weight:800;color:#1a3fc4;text-transform:uppercase;margin-bottom:3px;">Candidate</div>
                <div style="font-weight:800;color:#0f2557;font-size:14px;">'.htmlspecialchars($cand_name).'</div>
            </div>
            <div style="background:#fff;border:1px solid #e0e7ff;border-radius:9px;padding:12px;">
                <div style="font-size:10px;font-weight:800;color:#1a3fc4;text-transform:uppercase;margin-bottom:3px;">Position</div>
                <div style="font-weight:800;color:#0f2557;font-size:14px;">'.htmlspecialchars($cand_pos).'</div>
            </div>
        </div>';

        // Generate Link Section (only if not yet submitted)
        if ($link_status !== 'submitted') {
            echo '<div style="background:#fff;border:1px solid #e0e7ff;border-radius:10px;padding:16px;margin-bottom:16px;">
                <div style="font-weight:800;color:#0f2557;margin-bottom:12px;font-size:13px;"><i class="fas fa-link mr-2" style="color:#1a3fc4;"></i>Assignment Link</div>';
            
            if ($existing_link_url) {
                echo '<div style="display:flex;gap:8px;align-items:center;margin-bottom:10px;">
                    <input type="text" id="assignLinkBox_'.$sid.'" value="'.htmlspecialchars($existing_link_url).'" readonly style="flex:1;padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:12px;font-family:inherit;background:#f8faff;">
                    <button onclick="copyText(\'assignLinkBox_'.$sid.'\')" style="padding:9px 16px;border:none;border-radius:8px;background:#1a3fc4;color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;white-space:nowrap;"><i class="fas fa-copy mr-1"></i>Copy Link</button>
                </div>';
            }
            
            echo '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
                <select id="expirySelect_'.$sid.'" onchange="if(this.value==\'custom\'){document.getElementById(\'expiryCustom_'.$sid.'\').style.display=\'inline-block\';}else{document.getElementById(\'expiryCustom_'.$sid.'\').style.display=\'none\';}" style="padding:9px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;font-weight:600;">
                    <option value="24">24 Hours</option>
                    <option value="48">48 Hours</option>
                    <option value="168">7 Days</option>
                    <option value="0">No Expiry</option>
                    <option value="custom">Custom Date & Time</option>
                </select>
                <input type="datetime-local" id="expiryCustom_'.$sid.'" style="display:none;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;font-weight:600;">
                <button onclick="generateLinkFromRound('.$sid.', '.$round_req.', '.$dept_id.', '.$pos_id.')" style="padding:9px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;white-space:nowrap;">
                    <i class="fas fa-link mr-1"></i>'.($existing_link_url ? 'Regenerate Link' : 'Generate Link').'
                </button>
            </div>
            </div>';

            // Share Message Section (only if link exists)
            if ($existing_link_url) {
                echo '<div style="margin-top:20px; border-top:1px solid #e2e8f0; padding-top:20px;">';
                echo '<h5 style="font-weight:800;color:var(--navy);margin-bottom:15px;font-size:14px;"><i class="fas fa-share-alt mr-2"></i> Share Assignment Link</h5>';

                // WhatsApp Section
                echo '<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;margin-bottom:16px;">
                        <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
                        <div class="fg"><label class="fl" style="color:#065f46;">Phone Number</label><input type="text" id="waPhone_'.$sid.'" class="fc" value="'.htmlspecialchars($cand_phone).'"></div>
                        <div class="fg"><label class="fl" style="color:#065f46;">Message</label><textarea id="waMsg_'.$sid.'" class="fc" style="height:130px;resize:vertical;">'.htmlspecialchars($prefilled_msg).'</textarea></div>
                        <button type="button" onclick="sendAssignWaInline('.$sid.')" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp"></i> Open WhatsApp</button>
                      </div>';

                // Email Section
                echo '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
                        <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
                        <div class="fg"><label class="fl">To</label><input type="email" id="emailTo_'.$sid.'" class="fc" value="'.htmlspecialchars($cand_email).'"></div>
                        <div class="fg"><label class="fl">Subject</label><input type="text" id="emailSubj_'.$sid.'" class="fc" value="Assignment Round — '.htmlspecialchars($cand_pos).' Application"></div>
                        <div class="fg"><label class="fl">Message</label><textarea id="emailBody_'.$sid.'" class="fc" style="height:180px;resize:vertical;">'.htmlspecialchars($prefilled_msg).'</textarea></div>
                        <div id="emailAlert_'.$sid.'" style="margin-bottom:10px;"></div>
                        <button type="button" onclick="sendAssignEmailInline(this, '.$sid.')" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Send Email Now</button>
                      </div>';

                echo '</div>';
            }
        }

        echo '</div>';

        // If submitted AND needs HR review — show the answers for HR to mark
        if ($link_status == 'submitted') {
            $eval_res2 = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1");
            if ($eval_row2 = mysqli_fetch_assoc($eval_res2)) {
                // Only show marking interface if it's still pending
                if ($eval_row2['status'] == 'Pending' || $eval_row2['status'] == 'Pending HR Review') {
                    echo '<div style="margin-top:20px;">';
                    // Show answers for HR marking
                    $ans_res2 = mysqli_query($dbConn, "SELECT a.*, q.question_text, q.marks FROM hr_screening_evaluation_answers a LEFT JOIN hr_screening_questions q ON a.question_id = q.id WHERE a.evaluation_id = " . $eval_row2['id']);
                    echo '<h6 style="font-weight:800;color:#0f2557;margin-bottom:15px;border-bottom:2px solid #e0e7ff;padding-bottom:8px;"><i class="fas fa-pen mr-2"></i>Candidate Answers — Give Marks</h6>';
                    $q_num2 = 1;
                    $total_possible2 = 0;
                    while ($ans2 = mysqli_fetch_assoc($ans_res2)) {
                        $max_m = intval($ans2['marks']);
                        $total_possible2 += $max_m;
                        $v_sig = round($max_m * 1.0);
                        $v_out = round($max_m * 0.9);
                        $v_exc = round($max_m * 0.8);
                        $v_goo = round($max_m * 0.7);
                        $v_avg = round($max_m * 0.6);
                        $v_poo = round($max_m * 0.4);

                        $ans2_answer_html = renderFileAnswerLinks($ans2['file_path']) ?: nl2br(htmlspecialchars($ans2['answer_text'] ?: 'No answer provided'));
                        echo '<div style="background:#fff;border:1px solid #e2e8f0;border-radius:8px;padding:15px;margin-bottom:12px;">
                            <div style="font-weight:700;color:#0f2557;font-size:14px;margin-bottom:8px;">Q'.$q_num2.'. '.htmlspecialchars($ans2['question_text'] ?? 'Question deleted').'</div>
                            <div style="background:#f8fafc;padding:10px;border-radius:6px;border-left:3px solid #cbd5e1;font-size:13px;color:#475569;margin-bottom:10px;"><strong>Answer:</strong> '.$ans2_answer_html.'</div>
                            <div style="display:flex;align-items:center;gap:10px;">
                                <label style="font-size:12px;font-weight:700;color:#64748b;margin:0;">Rating:</label>
                                <select name="hr_marks_'.$ans2['question_id'].'" id="hrmark_'.$eval_row2['id'].'_'.$ans2['question_id'].'" style="padding:7px 12px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;" onchange="recalcAssignmentMarks('.$eval_row2['id'].', '.$total_possible2.')">
                                    <option value="">-- Select Rating --</option>
                                    <option value="'.$v_sig.'">💎 Significant → '.$v_sig.'/'.$max_m.'</option>
                                    <option value="'.$v_out.'">🏆 Outstanding → '.$v_out.'/'.$max_m.'</option>
                                    <option value="'.$v_exc.'">⭐ Excellent → '.$v_exc.'/'.$max_m.'</option>
                                    <option value="'.$v_goo.'">✨ Good → '.$v_goo.'/'.$max_m.'</option>
                                    <option value="'.$v_avg.'">👍 Average → '.$v_avg.'/'.$max_m.'</option>
                                    <option value="'.$v_poo.'">🚫 Poor → '.$v_poo.'/'.$max_m.'</option>
                                    <option value="0">❌ Failed → 0/'.$max_m.'</option>
                                </select>
                            </div>
                        </div>';
                        $q_num2++;
                    }
                    echo '<div style="width:100%; margin-bottom:15px;">
                            <label style="font-size:12px;font-weight:700;color:#64748b;margin-bottom:6px;display:block;">HR Remarks / Feedback:</label>
                            <textarea id="assignRemarks_'.$eval_row2['id'].'" style="width:100%;padding:10px;border:2px solid #e0e7ff;border-radius:8px;font-family:inherit;font-size:13px;resize:vertical;height:80px;" placeholder="Enter your remarks for the candidate\'s assignment here..."></textarea>
                        </div>
                    <div style="display:flex;justify-content:space-between;align-items:center;margin-top:16px;flex-wrap:wrap;gap:10px;width:100%;">
                        <div style="font-size:13px;font-weight:700;color:#64748b;">Total: <span id="assignTotalMarks_'.$eval_row2['id'].'" style="color:#1a3fc4;font-size:15px;">0</span> / '.$total_possible2.' &nbsp;|&nbsp; <span id="assignPct_'.$eval_row2['id'].'" style="color:#1a3fc4;">0%</span></div>
                        <div>
                        <button onclick="saveAssignmentMarks('.$eval_row2['id'].', '.$sid.', '.$round_req.', '.$total_possible2.')" style="padding:10px 22px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-check-circle mr-1"></i>Success &amp; Submit</button>
                        <button type="button" onclick="openRejectModal('.$sid.', '.$round_req.', \''.addslashes(htmlspecialchars($active_round_data['round_name'] ?? ('Round ' . $round_req))).'\', \'assignment\')" style="padding:10px 22px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;margin-left:8px;"><i class="fas fa-times-circle mr-1"></i>Reject</button>
                        </div>
                    </div>';
                    echo '</div>';
                    exit;
                }
            } else {
                exit; // Still exit if no eval record exists yet for a submitted link (though unlikely)
            }
        }
    }

    // Fetch Evaluation for active round
    $eval_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_req LIMIT 1");
    if ($eval_row = mysqli_fetch_assoc($eval_res)) {
        // Render Results
        $score = round(floatval($eval_row['percentage']));
        $sc_color = '#64748b'; $icon = 'fas fa-info-circle';
        if ($score >= 95) { $sc_color = '#0f766e'; $icon = 'fas fa-gem'; }
        else if ($score >= 90) { $sc_color = '#059669'; $icon = 'fas fa-trophy'; }
        else if ($score >= 85) { $sc_color = '#10b981'; $icon = 'fas fa-star'; }
        else if ($score >= 80) { $sc_color = '#2563eb'; $icon = 'fas fa-sparkles'; }
        else if ($score >= 70) { $sc_color = '#d97706'; $icon = 'fas fa-thumbs-up'; }
        else { $sc_color = '#dc2626'; $icon = 'fas fa-ban'; }
        
        echo '<div style="background:#f8faff; border:1px solid #e0e7ff; border-radius:12px; padding:20px; margin-bottom:20px;">';
        echo '<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px;">';
        echo '<div><h5 style="margin:0; font-weight:800; color:var(--navy);">Round ' . $round_req . ' Results</h5><div style="font-size:12px; color:var(--muted); margin-top:4px;">Evaluated by: ' . htmlspecialchars($eval_row['evaluator_name']) . ' on ' . date('d M Y, h:i A', strtotime($eval_row['created_at'])) . '</div></div>';
        echo '<div style="text-align:right;"><div style="font-size:24px; font-weight:800; color:'.$sc_color.';">' . round($score) . '%</div><div style="font-size:12px; font-weight:700; background:'.$sc_color.'22; color:'.$sc_color.'; padding:3px 10px; border-radius:10px; display:inline-block;"><i class="'.$icon.' mr-1"></i> ' . htmlspecialchars($eval_row['rating_label']) . ' (' . $eval_row['status'] . ')</div></div>';
        echo '</div>';
        // Explain the rounding whenever the raw score isn't already a whole number — this is
        // the reason a score like 89.67% (or 89.50%) shows as Passed even though it's under 90.
        $raw_pct_val = floatval($eval_row['percentage']);
        if (abs($raw_pct_val - round($raw_pct_val)) > 0.001) {
            echo '<div style="background:#f8faff; border:1px solid #e0e7ff; border-radius:8px; padding:10px 14px; font-size:12px; color:#475569; margin-bottom:14px;"><i class="fas fa-calculator" style="color:#6366f1;"></i> Raw score: <strong>' . number_format($raw_pct_val, 2) . '%</strong> — rounded to <strong>' . round($raw_pct_val) . '%</strong> for Pass/Fail (89.50% and above rounds up to 90%).</div>';
        }
        if (!empty($eval_row['hr_notes'])) {
            echo '<div style="background:#fff; border:1px solid #e2e8f0; border-radius:8px; padding:12px; font-size:13px; color:var(--navy);"><strong><i class="fas fa-sticky-note" style="color:var(--muted);"></i> ' . htmlspecialchars($active_round_data['round_name'] ?? 'Round') . ' Remarks:</strong><br>' . nl2br(htmlspecialchars($eval_row['hr_notes'])) . '</div>';
        }
        if (!empty($eval_row['early_end_reason'])) {
            echo '<div style="background:#fff7ed; border:1px solid #fcd34d; border-radius:8px; padding:12px; font-size:13px; color:#92400e; margin-top:10px;"><strong><i class="fas fa-stop-circle" style="color:#f59e0b;"></i> Interview Ended Early:</strong><br>' . nl2br(htmlspecialchars($eval_row['early_end_reason'])) . '</div>';
        }

        // Show override button if below 90% (Blue Collar candidates are exempt from this lock)
        if (!$is_bc_candidate && round(floatval($eval_row['percentage'])) < 90 && $eval_row['status'] != 'Override') {
            echo '<div style="margin-top:15px; padding:15px; background:#fff7ed; border:2px solid #fcd34d; border-radius:10px; text-align:center;">';
            echo '<div style="font-weight:800; color:#92400e; margin-bottom:8px; font-size:13px;">⚠️ Score below 90% — Next round is locked</div>';
            if ($can_override) {
                echo '<button onclick="hrOverrideUnlock('.$sid.', '.$round_req.')" style="padding:10px 24px; border:none; border-radius:8px; background:linear-gradient(135deg,#f59e0b,#d97706); color:#fff; font-family:inherit; font-weight:700; font-size:13px; cursor:pointer;"><i class="fas fa-unlock mr-2"></i>Manager Override — Unlock Next Round</button>';
            } else {
                echo '<div style="font-size:12px; color:#92400e; background:#fff; padding:8px; border-radius:6px; display:inline-block;"><strong>Note:</strong> You do not have permission to override. Please contact Management.</div>';
            }
            echo '</div>';
        } elseif ($eval_row['status'] == 'Override') {
            echo '<div style="margin-top:15px; padding:15px; background:#fff7ed; border:2px solid #fcd34d; border-radius:10px;">';
            echo '<div style="font-weight:800; color:#92400e; font-size:13px; margin-bottom:8px;">🔓 Manager Override Applied — Next Round Unlocked</div>';
            echo '<div style="font-size:12px; color:#78350f; background:#fff; padding:10px; border-radius:8px; border-left:3px solid #f59e0b;">';
            echo '<strong>Override Reason:</strong> ' . htmlspecialchars($eval_row['override_reason'] ?? 'No reason provided');
            echo '</div></div>';
        } elseif ($is_bc_candidate && round(floatval($eval_row['percentage'])) < 90) {
            echo '<div style="margin-top:15px; padding:15px; background:#eef2ff; border:2px solid #c7d2fe; border-radius:10px; text-align:center;">';
            echo '<div style="font-weight:800; color:#3730a3; font-size:13px;">✅ Blue Collar role — Next Round Unlocked (interview score threshold not required)</div>';
            echo '</div>';
        } elseif (round(floatval($eval_row['percentage'])) >= 90) {
            echo '<div style="margin-top:15px; padding:15px; background:#f0fdf4; border:2px solid #86efac; border-radius:10px; text-align:center;">';
            echo '<div style="font-weight:800; color:#065f46; font-size:13px;">✅ Score ≥ 90% — Next Round Automatically Unlocked</div>';
            echo '</div>';
        }
        echo '</div>';
        
        // Show Answers
        echo '<h6 style="font-weight:800; color:var(--navy); margin-bottom:15px; border-bottom:2px solid #e0e7ff; padding-bottom:8px;">Questions & Answers</h6>';
        $ans_res = mysqli_query($dbConn, "SELECT a.*, q.question_text, q.marks FROM hr_screening_evaluation_answers a LEFT JOIN hr_screening_questions q ON a.question_id = q.id WHERE a.evaluation_id = " . $eval_row['id']);
        if (mysqli_num_rows($ans_res) > 0) {
            $q_num = 1;
            while ($ans = mysqli_fetch_assoc($ans_res)) {
            $q_marks_obtained = intval($ans['marks_obtained']);
            $q_marks_max      = intval($ans['marks']);
            $q_pct            = $q_marks_max > 0 ? round(($q_marks_obtained / $q_marks_max) * 100) : 0;
            $q_color          = $q_pct >= 90 ? '#10b981' : ($q_pct >= 70 ? '#3b82f6' : ($q_pct >= 50 ? '#f59e0b' : '#ef4444'));

            // Determine rating label from marks
            $pct_val = $q_marks_max > 0 ? ($q_marks_obtained / $q_marks_max) * 100 : 0;
            if ($pct_val >= 100)     $rating_icon = '💎 Significant';
            elseif ($pct_val >= 90)  $rating_icon = '🏆 Outstanding';
            elseif ($pct_val >= 80)  $rating_icon = '⭐ Excellent';
            elseif ($pct_val >= 70)  $rating_icon = '✨ Good';
            elseif ($pct_val >= 60)  $rating_icon = '👍 Average';
            elseif ($pct_val >= 40)  $rating_icon = '🚫 Poor';
            else                     $rating_icon = '❌ Failed';

            echo '<div style="background:#fff; border:1px solid #e2e8f0; border-radius:8px; padding:15px; margin-bottom:10px; box-shadow:0 1px 3px rgba(0,0,0,0.02);">';
            
            // Question header
            echo '<div style="display:flex; justify-content:space-between; align-items:start; margin-bottom:10px;">';
            echo '<div style="font-weight:700; color:var(--navy); font-size:14px; flex:1;">Q'.$q_num.'. ' . htmlspecialchars($ans['question_text'] ?? 'Question deleted') . '</div>';
            echo '<div style="display:flex; align-items:center; gap:8px; margin-left:15px;">';
            echo '<span style="font-weight:800; color:'.$q_color.'; font-size:13px; background:#f0f4f8; padding:4px 10px; border-radius:6px;">'.$q_marks_obtained.' / '.$q_marks_max.' marks</span>';
            echo '</div>';
            echo '</div>';

            // Answer
            $ans_answer_html = renderFileAnswerLinks($ans['file_path']) ?: nl2br(htmlspecialchars($ans['answer_text'] ?: 'No answer provided'));
            echo '<div style="font-size:13px; color:#475569; background:#f8fafc; padding:10px; border-radius:6px; border-left:3px solid #cbd5e1; margin-bottom:8px;"><strong>Answer:</strong> ' . $ans_answer_html . '</div>';

            // Rating
            echo '<div style="font-size:12px; font-weight:700; color:'.$q_color.';">'.$rating_icon.'</div>';

            echo '</div>';
            $q_num++;
        }
        }

        // Overall Result Box (Blue Collar candidates are exempt from the below-90% gate)
        $overall_pct   = round(floatval($eval_row['percentage']));
        $overall_color = $overall_pct >= 90 ? '#10b981' : ($overall_pct >= 70 ? '#3b82f6' : ($overall_pct >= 50 ? '#f59e0b' : '#ef4444'));
        $auto_next     = $overall_pct >= 90 || $is_bc_candidate;

        echo '<div style="background:'.($auto_next ? '#f0fdf4' : '#fff7ed').'; border:2px solid '.($auto_next ? '#86efac' : '#fcd34d').'; border-radius:12px; padding:20px; margin-top:20px; text-align:center;">';
        echo '<div style="font-size:28px; font-weight:800; color:'.$overall_color.';">' . $eval_row['total_marks_obtained'] . ' / ' . $eval_row['total_marks_possible'] . ' marks</div>';
        echo '<div style="font-size:22px; font-weight:800; color:'.$overall_color.';">'.round($overall_pct).'%</div>';

        if ($overall_pct >= 90) {
            echo '<div style="margin-top:10px; display:inline-block; background:#dcfce7; color:#065f46; padding:8px 20px; border-radius:20px; font-weight:800; font-size:13px;">✅ Auto Shortlisted to Next Round</div>';
        } elseif ($is_bc_candidate) {
            echo '<div style="margin-top:10px; display:inline-block; background:#e0e7ff; color:#3730a3; padding:8px 20px; border-radius:20px; font-weight:800; font-size:13px;">✅ Blue Collar role — Shortlisted to Next Round</div>';
        } else {
            if ($can_override) {
                echo '<div style="margin-top:10px; display:inline-block; background:#fee2e2; color:#991b1b; padding:8px 20px; border-radius:20px; font-weight:800; font-size:13px;">⚠️ Below 90% — Manager Override Required</div>';
            } else {
                echo '<div style="margin-top:10px; display:inline-block; background:#fee2e2; color:#991b1b; padding:8px 20px; border-radius:20px; font-weight:800; font-size:13px;">⚠️ Below 90% — Contact Management to Override</div>';
            }
        }
        echo '</div>';

        $cand_data = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, candidate_email, candidate_phone, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));
        $c_name = htmlspecialchars($cand_data['candidate_name'] ?? '');
        $c_pos = htmlspecialchars($cand_data['position_applied'] ?? '');
        $c_email = htmlspecialchars($cand_data['candidate_email'] ?? '');
        $c_phone = htmlspecialchars($cand_data['candidate_phone'] ?? '');
        $status_pass = $auto_next || $eval_row['status'] == 'Override';
        
        echo '<div style="margin-top:15px; text-align:center;">';
        echo '<button onclick="openRoundNotifyModal('.$sid.', '.$round_req.', \''.addslashes($c_name).'\', \''.addslashes($c_email).'\', \''.addslashes($c_phone).'\', \''.addslashes($c_pos).'\', true)" style="padding:10px 20px; border:none; border-radius:8px; background:linear-gradient(135deg,#10b981,#059669); color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer; margin-right:8px;"><i class="fas fa-check-circle mr-2"></i>Congratulate Candidate</button>';
        echo '<button onclick="openRejectModal('.$sid.', '.$round_req.', \''.addslashes(htmlspecialchars($active_round_data['round_name'] ?? ('Round '.$round_req))).'\', \''.($is_assignment_round?'assignment':($is_worksample_round?'work_sample':'interview')).'\')" style="padding:10px 20px; border:none; border-radius:8px; background:linear-gradient(135deg,#ef4444,#dc2626); color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer; margin-right:8px;"><i class="fas fa-times-circle mr-2"></i>Reject Candidate</button>';
        echo '<button onclick="openRejectionNotifyModal('.$sid.', '.$round_req.', \''.addslashes($c_name).'\', \''.addslashes($c_email).'\', \''.addslashes($c_phone).'\', \''.addslashes($c_pos).'\')" style="padding:10px 20px; border:none; border-radius:8px; background:linear-gradient(135deg,#6b7280,#4b5563); color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer;"><i class="fas fa-paper-plane mr-2"></i>Rejection Notify</button>';
        if (!empty($eval_row['notified_at'])) {
            $notify_label = ($eval_row['notify_type'] ?? '') === 'reject' ? 'Rejection Notified' : 'Congratulated';
            echo '<div style="margin-top:12px; font-size:12px; font-weight:700; color:#065f46;"><i class="fas fa-check-circle" style="color:#10b981; margin-right:4px;"></i> '.$notify_label.': '.date('d M Y, h:i A', strtotime($eval_row['notified_at'])).'</div>';
        }
        echo '</div>';
    } else {
        // Render Evaluation Form
        $questions = [];
        $q_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_questions WHERE department_id=$dept_id AND position_id=$pos_id AND round_number=$round_req AND is_active=1 ORDER BY id ASC");
        while ($q = mysqli_fetch_assoc($q_res)) { $questions[] = $q; }
        
        if (empty($questions)) {
            echo '<p style="color:var(--muted); text-align:center; padding:20px;">No questions configured for this round.</p>';
            exit;
        }
        
        echo '<form id="evalForm_'.$round_req.'" onsubmit="submitInterviewEvaluation(event, '.$sid.', '.$round_req.')">';
        echo '<div style="background:#f0fdf4; border:1px solid #bbf7d0; border-radius:8px; padding:12px; margin-bottom:20px; font-size:13px; color:#166534;"><i class="fas fa-info-circle"></i> Evaluate the candidate based on the questions below. Marks will be calculated to form an overall rating.</div>';
        
        $total_possible = 0;
        foreach ($questions as $idx => $q) {
            $total_possible += intval($q['marks']);
            echo '<div style="background:#fff; border:1px solid #e2e8f0; border-radius:8px; padding:20px; margin-bottom:15px; box-shadow:0 1px 3px rgba(0,0,0,0.02);">';
            echo '<div style="font-weight:700; color:var(--navy); font-size:14px; margin-bottom:12px;">Q'.($idx+1).'. ' . htmlspecialchars($q['question_text']) . '</div>';
            
            // Answer Input
            echo '<div style="margin-bottom:15px;">';
            if ($q['input_type'] == 'select' && !empty($q['options_json'])) {
                $options = json_decode($q['options_json'], true);
                echo '<select name="answer_'.$q['id'].'" class="fc" style="width:100%;" onchange="autoScoreQuestion(this, '.$q['id'].')">';
                echo '<option value="">Select an answer... (optional)</option>';
                foreach ($options as $opt) {
                    echo '<option value="'.htmlspecialchars($opt).'">'.htmlspecialchars($opt).'</option>';
                }
                echo '</select>';
            } elseif ($q['input_type'] == 'file_upload') {
                echo '<div style="background:#fff7ed;border:1px solid #fcd34d;border-radius:8px;padding:12px;font-size:12px;color:#92400e;"><i class="fas fa-info-circle mr-1"></i> This is a File Upload question — it is meant for Assignment/Work Sample rounds where the candidate submits a file. For a live Interview round, just rate it directly below based on your discussion.</div>';
            } else {
                echo '<textarea name="answer_'.$q['id'].'" class="fc" style="width:100%; height:80px; resize:vertical;" placeholder="Candidate\'s response... (optional)"></textarea>';
            }
            echo '</div>';
            
            // Marks Input
            echo '<div style="display:flex; align-items:center; gap:10px; background:#f8fafc; padding:10px; border-radius:6px;">';
            echo '<label style="font-size:12px; font-weight:700; color:var(--muted); margin:0;">Evaluation Rating:</label>';
            
            $max_m = floatval($q['marks']);
            $v_sig = round($max_m * 1.0, 0);
            $v_out = round($max_m * 0.9, 0);
            $v_exc = round($max_m * 0.8, 0);
            $v_goo = round($max_m * 0.7, 0);
            $v_avg = round($max_m * 0.6, 0);
            $v_poo = round($max_m * 0.4, 0);
            $v_fai = 0;

            echo '<select name="marks_'.$q['id'].'" id="marks_'.$q['id'].'" class="fc" style="width:300px; font-size:13px;" onchange="updateMarkDisplay(this, '.$q['id'].', '.$max_m.')">';
            echo '<option value="">-- Select Rating --</option>';
            echo '<option value="'.$v_sig.'">💎 Significant → '.$v_sig.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_out.'">🏆 Outstanding → '.$v_out.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_exc.'">⭐ Excellent → '.$v_exc.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_goo.'">✨ Good → '.$v_goo.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_avg.'">👍 Average → '.$v_avg.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_poo.'">🚫 Poor → '.$v_poo.'/'.$max_m.' marks</option>';
            echo '<option value="'.$v_fai.'">❌ Failed → 0/'.$max_m.' marks</option>';
            echo '</select>';
            echo '<span id="mark_display_'.$q['id'].'" style="font-size:13px; font-weight:800; color:var(--navy); margin-left:10px;"></span>';
            echo '</div>';
            echo '</div>';
        }
        
        echo '<div style="background:#fff; border:1px solid #e2e8f0; border-radius:8px; padding:20px; margin-bottom:20px;">';
        echo '<label style="font-size:13px; font-weight:700; color:var(--navy); display:block; margin-bottom:8px;">' . htmlspecialchars($active_round_data['round_name'] ?? 'Round') . ' Remarks / Feedback</label>';
        echo '<textarea name="hr_notes" class="fc" style="width:100%; height:80px; resize:vertical; margin-bottom:15px;" placeholder="Overall impression for this round..."></textarea>';
        
        echo '<input type="hidden" name="round_status" id="auto_round_status" value="Pending">';
        echo '</div>';
        
        echo '<div style="display:flex; justify-content:space-between; align-items:center;">';
        echo '<div style="font-size:13px; font-weight:700; color:var(--muted);">
            Total Possible Marks: <span style="color:var(--navy);">'.$total_possible.'</span> &nbsp;|&nbsp; 
            Selected Marks: <span id="live_marks_display" style="color:var(--blue); font-size:15px;">0</span> / '.$total_possible.'
            &nbsp;|&nbsp; 
            Percentage: <span id="live_pct_display" style="color:var(--blue); font-size:15px;">0%</span>
        </div>';
        echo '<button type="submit" style="padding:12px 22px; border:none; border-radius:8px; background:linear-gradient(135deg,#10b981,#059669); color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer; box-shadow:0 4px 10px rgba(16,185,129,0.2);"><i class="fas fa-check-circle mr-2"></i>Success &amp; Submit</button>';
        echo '<button type="button" onclick="openRejectModal(' . $sid . ', ' . $round_req . ', \'' . addslashes(htmlspecialchars($active_round_data['round_name'] ?? ('Round ' . $round_req))) . '\', \'interview\')" style="padding:12px 22px; border:none; border-radius:8px; background:linear-gradient(135deg,#ef4444,#dc2626); color:#fff; font-family:inherit; font-weight:700; font-size:14px; cursor:pointer; margin-left:10px;"><i class="fas fa-times-circle mr-2"></i>Reject</button>';
        echo '</div>';
        
        echo '</form>';
        
        // --- AUTO-SCORING JAVASCRIPT ---
        echo '<script>
        function recalcLiveMarks() {
            var totalSelected = 0;
            var totalPossible = '.$total_possible.';
            document.querySelectorAll(\'[name^="marks_"]\').forEach(function(sel) {
                var val = parseFloat(sel.value);
                if (!isNaN(val)) totalSelected += val;
            });
            var pct = totalPossible > 0 ? Math.round((totalSelected / totalPossible) * 100) : 0;
            var liveMarks = document.getElementById("live_marks_display");
            var livePct = document.getElementById("live_pct_display");
            if (liveMarks) liveMarks.textContent = totalSelected;
            if (livePct) {
                livePct.textContent = pct + "%";
                livePct.style.color = pct >= 90 ? "#10b981" : (pct >= 70 ? "#3b82f6" : "#ef4444");
            }
            // Auto set hidden status
            var autoStatus = document.getElementById("auto_round_status");
            if (autoStatus) autoStatus.value = pct >= 90 ? "Passed" : "Failed";
        }
        
        function updateMarkDisplay(selectEl, qId, maxMarks) {
            var display = document.getElementById("mark_display_" + qId);
            if (!display) return;
            var val = parseFloat(selectEl.value);
            if (isNaN(val)) {
                display.innerHTML = "";
                return;
            }
            display.innerHTML = "<span style=\"background:#f0f9ff;border:1px solid #bae6fd;padding:4px 10px;border-radius:6px;\">" + val + " / " + maxMarks + " marks</span>";
            recalcLiveMarks();
        }
        
        function autoScoreQuestion(selectEl, qId) {
            var totalOptions = selectEl.options.length - 1; // Exclude the first placeholder option
            var selectedIndex = selectEl.selectedIndex;
            var marksDropdown = document.getElementById("marks_" + qId);
            
            if (!marksDropdown) return;
            
            if (selectedIndex === 0 || totalOptions < 1) {
                // User reset to the placeholder
                marksDropdown.selectedIndex = 0;
                return;
            }
            
            // Calculate percentage based on position
            var percentage = 100;
            if (totalOptions > 1) {
                percentage = 100 - ((selectedIndex - 1) / (totalOptions - 1)) * 100;
            }
            
            // Map percentage to Evaluation Rating
            if (percentage >= 95) marksDropdown.selectedIndex = 1; // Significant
            else if (percentage >= 90) marksDropdown.selectedIndex = 2; // Outstanding
            else if (percentage >= 80) marksDropdown.selectedIndex = 3; // Excellent
            else if (percentage >= 70) marksDropdown.selectedIndex = 4; // Good
            else if (percentage >= 60) marksDropdown.selectedIndex = 5; // Average
            else if (percentage >= 40) marksDropdown.selectedIndex = 6; // Poor
            else marksDropdown.selectedIndex = 7; // Failed
            
            // Highlight the dropdown to show it was automatically changed
            marksDropdown.style.transition = "background 0.3s";
            marksDropdown.style.background = "#f0fdf4";
            setTimeout(() => { marksDropdown.style.background = "#fff"; }, 1000);
        }

        // ---- AUTOSAVE / DRAFT RECOVERY (2 hour window) ----
        (function() {
            var draftKey = "hrEvalDraft_' . $sid . '_' . $round_req . '";
            var maxAgeMs = 2 * 60 * 60 * 1000; // 2 hours
            var form = document.getElementById("evalForm_' . $round_req . '");
            if (!form) return;

            function collectDraft() {
                var data = {};
                form.querySelectorAll("textarea, select").forEach(function(el) {
                    if (el.name) data[el.name] = el.value;
                });
                return data;
            }

            function saveDraft() {
                try {
                    localStorage.setItem(draftKey, JSON.stringify({ t: Date.now(), data: collectDraft() }));
                } catch (e) {}
            }

            form.addEventListener("input", saveDraft);
            form.addEventListener("change", saveDraft);

            try {
                var raw = localStorage.getItem(draftKey);
                if (raw) {
                    var parsed = JSON.parse(raw);
                    if (parsed && parsed.t && (Date.now() - parsed.t) <= maxAgeMs) {
                        if (confirm("We found unsaved answers from your last session. Restore them?")) {
                            Object.keys(parsed.data).forEach(function(name) {
                                var el = form.querySelector("[name=\"" + name + "\"]");
                                if (el) {
                                    el.value = parsed.data[name];
                                    if (el.tagName === "SELECT") el.dispatchEvent(new Event("change"));
                                }
                            });
                            recalcLiveMarks();
                        } else {
                            localStorage.removeItem(draftKey);
                        }
                    } else {
                        localStorage.removeItem(draftKey);
                    }
                }
            } catch (e) {}
        })();
        </script>';
    }
    exit;
}

// ---- AJAX: SUBMIT INTERVIEW EVALUATION ----
if (isset($_POST['ajax_submit_evaluation'])) { if (ob_get_level() > 0) { ob_clean(); }
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);
    $round_req = intval($_POST['round_number']);
    $hr_notes = mysqli_real_escape_string($dbConn, $_POST['hr_notes']);
    // Auto decide status based on percentage
    $status = 'Pending'; // will be set after calculation
    $evaluator = mysqli_real_escape_string($dbConn, $current_user_name);
    
    // Validate submission
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT department, position_id FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['success'=>false, 'message'=>'Candidate not found.']); exit; }
    
    $dept_name = mysqli_real_escape_string($dbConn, $sc['department']);
    $dept_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dept_name' LIMIT 1"));
    $dept_id = $dept_row ? $dept_row['id'] : 0;
    $pos_id = isset($sc['position_id']) ? intval($sc['position_id']) : 0;
    
    $q_res = mysqli_query($dbConn, "SELECT * FROM hr_screening_questions WHERE department_id=$dept_id AND position_id=$pos_id AND round_number=$round_req AND is_active=1");
    
    $total_obtained = 0;
    $total_possible = 0;
    $answers = [];
    
    while ($q = mysqli_fetch_assoc($q_res)) {
        $qid = $q['id'];
        $ans = isset($_POST["answer_$qid"]) ? trim($_POST["answer_$qid"]) : '';
        $marks_raw = isset($_POST["marks_$qid"]) ? trim($_POST["marks_$qid"]) : '';

        if ($marks_raw === '') {
            // Question not asked — skip entirely, does not count toward score
            continue;
        }

        $marks = intval($marks_raw);
        if ($marks > $q['marks']) $marks = $q['marks']; // Prevent over-scoring
        if ($marks < 0) $marks = 0;
        
        $total_obtained += $marks;
        $total_possible += intval($q['marks']);
        
        $answers[] = [
            'question_id' => $qid,
            'answer_text' => $ans,
            'marks_obtained' => $marks
        ];
    }
    
    $percentage = ($total_possible > 0) ? ($total_obtained / $total_possible) * 100 : 0;

    // Rating/status thresholds compare against the ROUNDED percentage (e.g. 89.67% rounds
    // to 90% and passes; 89.49% rounds to 89% and fails) — standard round-half-up, so the
    // stored rating and Pass/Fail status always agree with each other. The exact raw
    // percentage is still stored separately in the `percentage` column for the record.
    $rounded_pct = round($percentage);

    // Rating logic mapping from KPI
    $rating_label = "Poor";
    if ($rounded_pct >= 95) $rating_label = "Significant";
    else if ($rounded_pct >= 90) $rating_label = "Outstanding";
    else if ($rounded_pct >= 85) $rating_label = "Excellent";
    else if ($rounded_pct >= 80) $rating_label = "Good";
    else if ($rounded_pct >= 70) $rating_label = "Average";

    // Auto decide round status based on the rounded percentage
    $status = $rounded_pct >= 90 ? 'Passed' : 'Failed';
    $status = mysqli_real_escape_string($dbConn, $status);
    
    // Insert Evaluation
    $early_end_reason = isset($_POST['early_end_reason']) ? mysqli_real_escape_string($dbConn, trim($_POST['early_end_reason'])) : '';
    $early_end_reason_sql = $early_end_reason !== '' ? "'$early_end_reason'" : "NULL";

    $ins_eval = "INSERT INTO hr_screening_evaluations (screening_id, round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, hr_notes, status, early_end_reason) VALUES ($sid, $round_req, '$evaluator', $total_obtained, $total_possible, $percentage, '$rating_label', '$hr_notes', '$status', $early_end_reason_sql)";
    
    if (mysqli_query($dbConn, $ins_eval)) {
        $eval_id = mysqli_insert_id($dbConn);
        
        // Insert Answers
        foreach ($answers as $ans) {
            $safe_ans = mysqli_real_escape_string($dbConn, $ans['answer_text']);
            mysqli_query($dbConn, "INSERT INTO hr_screening_evaluation_answers (evaluation_id, question_id, answer_text, marks_obtained) VALUES ($eval_id, {$ans['question_id']}, '$safe_ans', {$ans['marks_obtained']})");
        } if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success'=>true]);
    } else { if (ob_get_level() > 0) { ob_clean(); }
        echo json_encode(['success'=>false, 'message'=>'Database error: ' . mysqli_error($dbConn)]);
    }
    exit;
}

// ====================================================================
// KEYWORD-MATCHING ANALYSIS ENGINE (No external API — works offline)
// ====================================================================
// How it works:
//   1. Tokenise both resume and JD into lowercase words/phrases
//   2. Extract JD requirements as keywords (nouns, tech terms, skills)
//   3. Check which of those keywords appear in the resume → matched / missing
//   4. Detect experience years and education level via regex patterns
//   5. Score using the same 5-band system as before:
//        JD keyword match   = up to 45 pts
//        Experience match   = up to 25 pts
//        Education match    = up to 15 pts
//        Resume completeness = up to 10 pts
//        Domain signals      = up to  5 pts
// ====================================================================

function kwm_tokenise($text) {
    // Lowercase, keep alphanumeric + hyphens (for terms like "full-stack")
    $text = mb_strtolower($text);
    $text = preg_replace('/[^\w\s\-\+\#\.\/]/', ' ', $text);
    return $text;
}

function kwm_extract_phrases($text) {
    // Returns array of all 1-gram, 2-gram and 3-gram tokens
    $text   = kwm_tokenise($text);
    $words  = preg_split('/\s+/', $text, -1, PREG_SPLIT_NO_EMPTY);
    $result = [];
    $n      = count($words);
    for ($i = 0; $i < $n; $i++) {
        if (strlen($words[$i]) > 1) $result[] = $words[$i];
        if ($i + 1 < $n) $result[] = $words[$i] . ' ' . $words[$i+1];
        if ($i + 2 < $n) $result[] = $words[$i] . ' ' . $words[$i+1] . ' ' . $words[$i+2];
    }
    return array_unique($result);
}

// Stop-words to skip when extracting JD keywords
function kwm_stopwords() {
    return ['a','an','the','and','or','but','in','on','at','to','for','of','with','by',
            'from','up','about','into','through','during','including','until','against',
            'among','throughout','despite','towards','upon','concerning','is','are','was',
            'were','be','been','being','have','has','had','do','does','did','will','would',
            'shall','should','may','might','must','can','could','not','no','nor',
            'so','yet','both','either','neither','each','few','more','most','other',
            'some','such','than','too','very','just','our','your','we','you','they',
            'he','she','it','its','this','that','these','those','who','which','what',
            'when','where','why','how','all','any','both','each','every','much','own',
            'same','than','then','there','well','also','as','if','per','etc','ie','eg',
            'good','strong','excellent','ability','skills','experience','knowledge',
            'responsibilities','requirements','qualification','role','position','team',
            'company','work','working','job','looking','candidate','applicant','will',
            'must','preferred','desired','required','plus','bonus','ideally','minimum',
            'years','year','month','months','day','days','able','ability','need','needs'];
}

// Extract meaningful keyword candidates from JD text (Strict Mode to prevent PDF bytecode)
function kwm_extract_jd_keywords($jd_text, $position, $department) {
    // We strictly use a master list to prevent PDF extraction garbage (like ObjEndobj) from becoming keywords
    $tech_boost = ['php','mysql','javascript','python','java','react','angular','vue',
                   'node','nodejs','laravel','django','spring','sql','nosql','mongodb',
                   'postgresql','html','css','bootstrap','jquery','rest','api','apis',
                   'json','xml','git','github','gitlab','docker','kubernetes','aws','azure',
                   'gcp','linux','windows','excel','word','powerpoint','sap','erp','crm',
                   'tally','logistics','supply chain','freight','shipping','customs','import',
                   'export','warehouse','inventory','procurement','accounts','finance',
                   'taxation','gst','tds','payroll','hr','recruitment','training','sales',
                   'marketing','digital marketing','seo','sem','social media','content',
                   'design','photoshop','illustrator','autocad','solidworks','civil',
                   'mechanical','electrical','construction','project management','agile',
                   'scrum','communication','leadership','teamwork','problem solving',
                   'analytical','ms office','data analysis','reporting','customer service',
                   'tender','bilty','lr','lorry receipt','road transport','air freight',
                   'sea freight','fcl','lcl','customs clearance','freight forwarding',
                   'developer','engineer','manager','executive','assistant','full stack',
                   'front end','back end','database','ui','ux'];

    $jd_lower = mb_strtolower($jd_text . ' ' . $position . ' ' . $department);
    $found = [];
    
    foreach ($tech_boost as $tb) {
        if (preg_match('/\b' . preg_quote($tb, '/') . '\b/', $jd_lower)) {
            $found[] = $tb;
        }
    }
    
    // If no master skills found, fallback to parsing position name (cleanly)
    if (empty($found)) {
        $pos_words = explode(' ', mb_strtolower($position));
        $stops = kwm_stopwords();
        foreach($pos_words as $pw) {
            $pw = trim($pw, '-.,;:()[]{}');
            if (strlen($pw) > 2 && !in_array($pw, $stops)) {
                $found[] = $pw;
            }
        }
    }
    
    return array_values(array_unique($found));
}

// Check if a keyword appears in the resume text
function kwm_keyword_in_resume($keyword, $resume_lower) {
    // Normalize hyphens/underscores/multiple spaces to single spaces
    $resume_norm  = preg_replace('/[\s\-_]+/', ' ', $resume_lower);
    $keyword_norm = preg_replace('/[\s\-_]+/', ' ', $keyword);

    // Phrase match (multi-word keyword): substring match is safe here since
    // multi-word phrases are far less likely to appear accidentally inside
    // unrelated text.
    if (strpos($keyword_norm, ' ') !== false) {
        return strpos($resume_norm, $keyword_norm) !== false;
    }

    // Single-word keyword: strict word-boundary match ONLY. No substring
    // fallback — short keywords like "aws", "ba", "ui", "hr" can accidentally
    // match inside unrelated words (e.g. "aws" inside "laws"), producing false
    // positives. Merged-word PDF extraction issues are now handled upstream by
    // normalizeExtractedText(), so this fallback is no longer needed.
    return (bool) preg_match('/\b' . preg_quote($keyword_norm, '/') . '[0-9]*\b/', $resume_norm);
}

// Detect years of experience from resume text
function kwm_detect_experience($resume_text) {
    $text = mb_strtolower($resume_text);

    // 1) Prefer an EXPLICIT statement like "5 years of experience" or "3+ years"
    $patterns = [
        '/(\d{1,2})\s*\+?\s*years?\s*(?:of\s+)?(?:experience|exp|work)/i',
        '/experience[:\s]+(\d{1,2})\s*\+?\s*years?/i',
        '/(\d{1,2})\s*\+?\s*yrs?\s*(?:of\s+)?(?:exp|experience)/i',
    ];
    foreach ($patterns as $p) {
        if (preg_match($p, $text, $m)) {
            $yrs = intval($m[1]);
            if ($yrs > 0 && $yrs < 50) return $yrs . ' year' . ($yrs != 1 ? 's' : '');
        }
    }

    // 2) Fallback: no explicit phrase found — scan for date ranges that include
    //    a MONTH NAME (e.g. "Feb 2025 - Present", "Oct 2025-Present"). Pure
    //    year-only ranges like "2022-2025" are deliberately EXCLUDED, since
    //    those almost always represent education/degree durations, not jobs.
    //    This avoids the fragility of trying to isolate a "Work Experience"
    //    section by heading text, which breaks easily on multi-column resumes
    //    where pdftotext's reading order can interleave sidebar content.
    $months = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';

    // Both start AND end must be tied to a month name somewhere in the match —
    // this pattern requires at least one month token to appear in the range.
    $range_pattern = '/\b(' . $months . ')[\s.]*(\d{4})?\s*[-–—]+\s*(?:(' . $months . ')[\s.]*)?(\d{4}|present|current|now)\b/i';

    $earliest_start = null;
    $latest_end     = null;
    $now_year       = intval(date('Y'));

    if (preg_match_all($range_pattern, $text, $matches, PREG_SET_ORDER)) {
        foreach ($matches as $m) {
            // $m[2] may be empty if the range was like "Feb-Mar 2025" (year only stated once, at the end)
            $end_raw  = strtolower(trim($m[4]));
            $end_year = in_array($end_raw, ['present', 'current', 'now']) ? $now_year : intval($m[4]);

            $start_year = !empty($m[2]) ? intval($m[2]) : $end_year; // e.g. "Feb-Mar 2025" -> both = 2025

            if ($start_year < 1990 || $start_year > $now_year + 1) continue;
            if ($end_year   < 1990 || $end_year   > $now_year + 1) continue;

            if ($earliest_start === null || $start_year < $earliest_start) $earliest_start = $start_year;
            if ($latest_end === null || $end_year > $latest_end) $latest_end = $end_year;
        }
    }

    if ($earliest_start !== null && $latest_end !== null && $latest_end >= $earliest_start) {
        $yrs = $latest_end - $earliest_start;
        if ($yrs == 0) return 'Less than 1 year';
        return $yrs . ' year' . ($yrs != 1 ? 's' : '') . ' (estimated)';
    }

    // 3) Second fallback: no month-anchored range found either — scan for pure
    //    year-only ranges (e.g. "2019 - 2020", "2022-Present"). A SINGLE such
    //    range is still ignored (too likely to be one degree's duration, e.g.
    //    "B.Tech 2017-2021"), but TWO OR MORE distinct ranges is a strong signal
    //    of a listed job history — people essentially never list 2+ separate
    //    qualifications each with their own "YYYY-YYYY" range, but frequently
    //    list several jobs that way when they don't have month-level dates.
    //    Extra safeguard: any range sitting right next to an education keyword
    //    (diploma, degree, b.tech, university, school, sslc, etc.) is dropped
    //    outright, so an education table with 2+ rows of its own can't get
    //    counted as work experience even though it would otherwise qualify.
    $yearonly_pattern = '/\b(\d{4})\s*[-–—]+\s*(\d{4}|present|current|now)\b/i';
    $edu_keywords = '/\b(diploma|degree|b\.?\s*tech|b\.?\s*e\b|bachelor|m\.?\s*tech|master|\bmba\b|\bmca\b|\bbca\b|\bbsc\b|\bmsc\b|university|college|polytechnic|school|academy|institute|sslc|hsc|matriculation|puc|12th|10th|qualification)\b/i';
    $yo_earliest = null;
    $yo_latest   = null;
    $yo_count    = 0;

    if (preg_match_all($yearonly_pattern, $text, $yoMatches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE)) {
        foreach ($yoMatches as $m) {
            $matchOffset = $m[0][1];
            $windowStart = max(0, $matchOffset - 80);
            $context = substr($text, $windowStart, ($matchOffset - $windowStart) + strlen($m[0][0]) + 20);
            if (preg_match($edu_keywords, $context)) continue; // looks like an education date, not a job

            $end_raw  = strtolower(trim($m[2][0]));
            $end_year = in_array($end_raw, ['present', 'current', 'now']) ? $now_year : intval($m[2][0]);
            $start_year = intval($m[1][0]);

            if ($start_year < 1990 || $start_year > $now_year + 1) continue;
            if ($end_year   < 1990 || $end_year   > $now_year + 1) continue;
            if ($end_year < $start_year) continue;

            $yo_count++;
            if ($yo_earliest === null || $start_year < $yo_earliest) $yo_earliest = $start_year;
            if ($yo_latest === null || $end_year > $yo_latest) $yo_latest = $end_year;
        }
    }

    if ($yo_count >= 2 && $yo_earliest !== null && $yo_latest !== null && $yo_latest >= $yo_earliest) {
        $yrs = $yo_latest - $yo_earliest;
        if ($yrs == 0) return 'Less than 1 year';
        return $yrs . ' year' . ($yrs != 1 ? 's' : '') . ' (estimated)';
    }

    // 4) Third fallback: no absolute dates anywhere — some resumes state each
    //    role's length in relative terms instead of calendar dates, e.g.
    //    'Worked in "FLIPKART" as a "TEAM LEADER" for a period of 1 year'.
    //    Every such phrase found is summed (each one is normally per-role, so
    //    they add up to total career length) rather than just taking the first,
    //    unlike Tier 1's single summary-statement match. Same education-keyword
    //    safeguard as Tier 3, so "completed the course for a period of 2 years"
    //    can't get counted as work experience.
    $duration_pattern = '/for\s+(?:a\s+)?(?:period|duration)\s+of\s+(\d{1,2})\s*\+?\s*(years?|months?)\b|\bfor\s+(\d{1,2})\s*\+?\s*(years?|months?)\b/i';
    $total_months  = 0;
    $duration_hits = 0;

    if (preg_match_all($duration_pattern, $text, $durMatches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE)) {
        foreach ($durMatches as $m) {
            $matchOffset = $m[0][1];
            $windowStart = max(0, $matchOffset - 80);
            $context = substr($text, $windowStart, ($matchOffset - $windowStart) + strlen($m[0][0]) + 20);
            if (preg_match($edu_keywords, $context)) continue;

            $num  = !empty($m[1][0]) ? intval($m[1][0]) : intval($m[3][0] ?? 0);
            $unit = !empty($m[2][0]) ? strtolower($m[2][0]) : strtolower($m[4][0] ?? '');
            if ($num <= 0 || $unit === '') continue;

            $months = (strpos($unit, 'month') === 0) ? $num : $num * 12;
            $total_months += $months;
            $duration_hits++;
        }
    }

    if ($duration_hits > 0 && $total_months > 0) {
        $yrs = intval(round($total_months / 12));
        if ($yrs == 0) return 'Less than 1 year';
        return $yrs . ' year' . ($yrs != 1 ? 's' : '') . ' (estimated)';
    }

    return '';
}

// Detect education level from resume text
function kwm_detect_education($resume_text) {
    $text = mb_strtolower($resume_text);

    // [pattern, label, rank] — higher rank = more advanced qualification
    $levels = [
        ['phd|ph\.d|doctorate|doctor of philosophy',                                    'Ph.D / Doctorate',              100],
        ['\bmba\b|master of business administration',                                   'MBA',                            90],
        ['m\.\s*tech|m\.\s*e\b|master of tech(nology)?|master of engineering',          'M.Tech',                         90],
        ['\bmsc\b|m\.\s*sc\b|master of science',                                        'M.Sc',                           90],
        ['\bma\b|m\.\s*a\b|master of arts',                                             'M.A',                            90],
        ['\bmcom\b|m\.\s*com\b|master of commerce',                                     'M.Com',                          90],
        ['\bmca\b|master of computer applications',                                     'MCA',                            90],
        ['\bpgdm\b|post\s*graduate diploma in management',                              'PGDM',                           88],
        ['b\.\s*tech|\bbtech\b|b\.\s*e\b|\bbe\b|bachelor of (engineering|tech(nology)?)','B.Tech / B.E',                   80],
        ['\bbba\b|bachelor of business administration',                                 'BBA',                            80],
        ['\bbbm\b|bachelor of business management',                                     'BBM',                            80],
        ['\bbsc\b|b\.\s*sc\b|bachelor of science',                                      'B.Sc',                           80],
        ['\bbca\b|bachelor of computer applications',                                    'BCA',                            80],
        ['\bbcom\b|b\.\s*com\b|bachelor of commerce',                                   'B.Com',                          80],
        ['\bb\.\s*voc\b|bachelor of vocation',                                          'B.Voc',                          80],
        ['\bba\b|b\.\s*a\b|bachelor of arts',                                           'B.A',                            80],
        ['diploma',                                                                     'Diploma',                        50],
        ['hsc|12th|higher secondary|plus two|\bpuc\b',                                  'HSC / 12th',                     20],
        ['sslc|10th|matriculation',                                                     'SSLC / 10th',                    10],
    ];

    $best_label = 'Not detected';
    $best_rank  = -1;
    foreach ($levels as [$pattern, $label, $rank]) {
        if (preg_match('/' . $pattern . '/i', $text) && $rank > $best_rank) {
            $best_label = $label;
            $best_rank  = $rank;
        }
    }
    return $best_label;
}

// Extract experience requirement from JD
function kwm_jd_experience_requirement($jd_text) {
    if (empty(trim($jd_text))) return 0;
    // Separator covers a plain hyphen plus every en/em/figure dash variant and the
    // minus sign, or the word "to" — PDF text extraction frequently substitutes a
    // different dash glyph than a plain "-" depending on the source font/PDF
    // generator, which silently broke ranges like "1–3 years" (en dash) before.
    // Unit covers both "years/year" and the "yrs/yr" abbreviation.
    $sep  = '(?:[\x{002D}\x{2010}\x{2011}\x{2012}\x{2013}\x{2014}\x{2015}\x{2212}]|\s+to\s+)';
    $unit = '(?:years?|yrs?)';
    $patterns = [
        '/(\d{1,2})\s*' . $sep . '\s*\d{1,2}\s*\+?\s*' . $unit . '/iu',
        '/minimum\s+(\d{1,2})\s*' . $unit . '/iu',
        '/at\s+least\s+(\d{1,2})\s*' . $unit . '/iu',
        '/(\d{1,2})\+\s*' . $unit . '/iu',
        '/(\d{1,2})\s*' . $unit . '\s+(?:of\s+)?(?:experience|exp)/iu',
    ];
    foreach ($patterns as $p) {
        if (preg_match($p, $jd_text, $m)) return intval($m[1]);
    }
    return 0;
}

// Parse detected experience string back to a number
function kwm_parse_exp_years($exp_str) {
    if (preg_match('/(\d+)/', $exp_str, $m)) return intval($m[1]);
    return 0;
}

// --- MASTER SKILLS LIST FOR JSON PARSING ---
$master_skills = [
    'php','mysql','javascript','python','java','react','angular','vue',
    'node.js','nodejs','laravel','django','spring','sql','nosql','mongodb',
    'postgresql','html','css','bootstrap','jquery','rest api','apis',
    'json','xml','git','github','gitlab','docker','kubernetes','aws','azure',
    'gcp','linux','windows','excel','word','powerpoint','sap','erp','crm',
    'tally','logistics','supply chain','freight','shipping','customs','import',
    'export','warehouse','inventory','procurement','accounts','finance',
    'taxation','gst','tds','payroll','hr','recruitment','training','sales',
    'marketing','digital marketing','seo','sem','social media','content',
    'photoshop','illustrator','autocad','project management','agile',
    'scrum','communication','leadership','data analysis','reporting',
    'customer service','tender','bilty','lorry receipt','fcl','lcl',
    'developer','engineer','manager','executive','assistant','full stack',
    'front end','back end','database','ui','ux'
];

function kwm_analyze($resume_text, $jd_text, $position, $department) {
    global $master_skills;
    
    // Check if pdftotext failed and we are reading raw PDF bytecode (e.g. Scanned PDF or unsupported encryption)
    $is_garbage_resume = strpos($resume_text, 'Obj') !== false && strpos($resume_text, 'endobj') !== false && strlen($resume_text) > 1000 && stripos($resume_text, 'developer') === false;
    if ($is_garbage_resume) {
        return [
            'eligibility_score'    => 0,
            'eligibility_status'   => 'not_eligible',
            'candidate_summary'    => 'CRITICAL ERROR: Your Windows server is missing the pdftotext program! PHP cannot read compressed PDF files directly. Please either install xpdf-tools or upload the Resume/JD as .txt or .docx files to see the AI work perfectly!',
            'experience_years'     => 'Error',
            'education_level'      => 'Error',
            'jd_key_requirements'  => [],
            'skills_matched'       => [],
            'skills_missing'       => [],
            'strengths'            => ['None'],
            'concerns'             => ['PDF text extraction failed completely because pdftotext is not installed on this server.'],
            'jd_vs_resume_gap'     => 'Please upload a .TXT or .DOCX file to test the AI, or install pdftotext.',
            'recommendation'       => 'Fix server dependencies (pdftotext) or use .txt/.docx files.',
            'interview_questions'  => ['Why did the PDF extraction fail? Because PDFs are compressed binary files!']
        ];
    }

    // JSON CONVERSION: Resume
    $res_lower = mb_strtolower($resume_text);
    $res_skills = [];
    foreach ($master_skills as $skill) {
        if (kwm_keyword_in_resume($skill, $res_lower)) {
            $res_skills[] = $skill;
        }
    }
    $res_exp = kwm_parse_exp_years(kwm_detect_experience($resume_text));
    $res_edu = kwm_detect_education($resume_text);

    // JSON CONVERSION: JD
    $jd_lower = mb_strtolower($jd_text);
    $req_skills = [];
    foreach ($master_skills as $skill) {
        if (kwm_keyword_in_resume($skill, $jd_lower)) {
            $req_skills[] = $skill;
        }
    }
    if (empty($req_skills)) {
        // We do not invent skills from the position anymore, as per user request.
        // The matching will only happen to the JD and resume.
    }

    $req_exp = kwm_jd_experience_requirement($jd_text);

    // JSON COMPARISON & SCORING
    $score = 0;
    $matched_skills = [];
    $missing_skills = [];

    // 1. Skills (Max 45)
    $skills_points = 0;
    if (empty($req_skills) && !empty($res_skills)) {
        $skills_points = 45;
        $skills_detail = 'JD had no specific skills detected, so full 45 pts awarded by default since the resume lists skills (' . implode(', ', array_map('ucwords', $res_skills)) . ').';
    } elseif (!empty($req_skills)) {
        foreach ($req_skills as $rs) {
            if (in_array($rs, $res_skills)) {
                $matched_skills[] = $rs;
            } else {
                $missing_skills[] = $rs;
            }
        }
        $match_ratio = count($matched_skills) / count($req_skills);
        $skills_points = $match_ratio * 45;
        $skills_detail = 'Matched ' . count($matched_skills) . ' of ' . count($req_skills) . ' JD-required skills (' . round($match_ratio * 100) . '%) → ' . round($match_ratio * 100) . '% x 45 = ' . round($skills_points, 1) . ' pts.'
            . '<br><br><strong style="color:#065f46;">✅ Found in resume:</strong> ' . (!empty($matched_skills) ? implode(', ', array_map('ucwords', $matched_skills)) : 'None')
            . '<br><strong style="color:#991b1b;">❌ Missing from resume:</strong> ' . (!empty($missing_skills) ? implode(', ', array_map('ucwords', $missing_skills)) : 'None');
    } else {
        $skills_detail = 'No skills detected in either the JD or the resume — 0 pts.';
    }
    $score += $skills_points;

    // 2. Experience (Max 25)
    $experience_points = 0;
    if ($req_exp == 0 && $res_exp > 0) {
        $experience_points = 25;
        $experience_detail = "JD did not state a required experience level. Resume shows {$res_exp} year(s) detected → full 25 pts awarded by default.";
    } elseif ($req_exp == 0 && $res_exp == 0) {
        $experience_points = 25;
        $experience_detail = 'Neither the JD nor the resume state experience explicitly → full 25 pts awarded by default.';
    } else {
        if ($res_exp >= $req_exp) {
            $experience_points = 25;
            $experience_detail = "Resume shows {$res_exp} year(s) vs JD requirement of {$req_exp} year(s) — meets/exceeds requirement → full 25 pts.";
        } else {
            $experience_points = ($res_exp / $req_exp) * 25;
            $experience_detail = "Resume shows {$res_exp} year(s) vs JD requirement of {$req_exp} year(s) → ({$res_exp}/{$req_exp}) x 25 = " . round($experience_points, 1) . ' pts.';
        }
    }
    $score += $experience_points;

    // 3. Education (Max 15)
    $education_points = ($res_edu != 'Not detected') ? 15 : 5;
    $education_detail = ($res_edu != 'Not detected')
        ? "Detected education level: \"{$res_edu}\" (matched via keyword pattern) → full 15 pts."
        : 'No recognizable education keyword/pattern found in resume → fallback 5 pts.';
    $score += $education_points;

    // 4. Completeness (Max 10)
    $has_email = (bool) preg_match('/\b[\w.\-]+@[\w.\-]+\.\w{2,6}\b/', $resume_text);
    $has_phone = (bool) preg_match('/\b[6-9]\d{9}\b|\b\+\d[\d\s\-]{8,14}\b/', $resume_text);
    $has_skills_listed = !empty($res_skills);
    $completeness = ($has_email ? 3 : 0) + ($has_phone ? 3 : 0) + ($has_skills_listed ? 4 : 0);
    $completeness_detail = ($has_email ? '✅' : '❌') . ' Email found (3 pts) &middot; '
        . ($has_phone ? '✅' : '❌') . ' Phone found (3 pts) &middot; '
        . ($has_skills_listed ? '✅' : '❌') . ' Skills listed (4 pts).';
    $score += $completeness;

    // 5. Domain (Max 5)
    $domain_points = 0;
    $res_skill_count = count($res_skills);
    if ($res_skill_count > 5) $domain_points = 5;
    elseif ($res_skill_count > 2) $domain_points = 2;
    $domain_detail = "{$res_skill_count} matched skill(s) found in resume. Needs 6+ for full 5 pts, 3-5 for partial 2 pts, 0-2 for 0 pts → " . $domain_points . ' pts awarded.';
    $score += $domain_points;

    $total_score = max(0, min(100, round($score)));

    // Build the scoring breakdown for transparency in the UI
    $scoring_breakdown = [
        ['label' => 'Skills Match',      'points' => round($skills_points, 1),     'max' => 45, 'pct' => round(($skills_points / 45) * 100),     'detail' => $skills_detail],
        ['label' => 'Experience',        'points' => round($experience_points, 1), 'max' => 25, 'pct' => round(($experience_points / 25) * 100), 'detail' => $experience_detail],
        ['label' => 'Education',         'points' => round($education_points, 1),  'max' => 15, 'pct' => round(($education_points / 15) * 100),  'detail' => $education_detail],
        ['label' => 'Resume Completeness', 'points' => round($completeness, 1),    'max' => 10, 'pct' => round(($completeness / 10) * 100),      'detail' => $completeness_detail],
        ['label' => 'Domain Signals',     'points' => round($domain_points, 1),    'max' => 5,  'pct' => round(($domain_points / 5) * 100),      'detail' => $domain_detail],
    ];

    // Generate output
    if ($total_score >= 75) $status = 'highly_eligible';
    elseif ($total_score >= 50) $status = 'eligible';
    elseif ($total_score >= 25) $status = 'partially_eligible';
    else $status = 'not_eligible';

    $match_pct = !empty($req_skills) ? round((count($matched_skills) / count($req_skills)) * 100) : 100;
    $summary = "JSON Comparison: Candidate has {$match_pct}% match on required skills. Found " . count($res_skills) . " total skills in resume.";

    return [
        'eligibility_score'    => $total_score,
        'eligibility_status'   => $status,
        'candidate_summary'    => $summary,
        'experience_years'     => $res_exp > 0 ? $res_exp . ' years' : 'Not specified',
        'education_level'      => $res_edu,
        'jd_key_requirements'  => array_map('ucwords', $req_skills),
        'skills_matched'       => array_map('ucwords', $matched_skills),
        'skills_missing'       => array_map('ucwords', $missing_skills),
        'strengths'            => ['Matched ' . count($matched_skills) . ' specific skills from JD JSON.'],
        'concerns'             => count($missing_skills) > 0 ? ['Missing ' . count($missing_skills) . ' critical skills.'] : ['No major concerns.'],
        'jd_vs_resume_gap'     => 'The resume covers ' . $match_pct . '% of JD requirements.',
        'recommendation'       => $total_score >= 50 ? 'Proceed to interview round.' : 'Candidate lacks required matching skills.',
        'interview_questions'  => count($missing_skills) > 0 ? ['Can you explain your experience with ' . ucwords($missing_skills[0]) . '?'] : ['What excites you about this ' . (trim($position) !== '' ? $position : 'role') . '?'],
        'scoring_breakdown'    => $scoring_breakdown
    ];
}

// ---- AJAX: ANALYZE (Keyword-Matching Engine) ----
if (isset($_POST['ajax_analyze_resume'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);
    $sc  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['success'=>false,'message'=>'Record not found']); exit; }

    $resume_text = $sc['resume_text'] ?? '';
    $jd_text     = $sc['jd_text'] ?? '';
    
    // Re-extract if old data looks garbled or empty
    if (strlen($resume_text) < 50 || strpos($resume_text, 'Obj') !== false) {
        $resume_text = extractText($sc['resume_path'], pathinfo($sc['resume_path'], PATHINFO_EXTENSION));
        $jd_text = extractText($sc['jd_path'], pathinfo($sc['jd_path'], PATHINFO_EXTENSION));
    }
    
    $position    = $sc['position_applied'];
    $department  = $sc['department'];

    if (strlen(trim($resume_text)) < 30) {
        echo json_encode([
            'success' => false,
            'message' => 'Could not extract readable text from this resume file. It may be a scanned image PDF. Please re-upload as .docx or .txt.'
        ]);
        exit;
    }

    // Run the keyword-matching analysis — no API call, pure PHP
    $parsed = kwm_analyze($resume_text, $jd_text, $position, $department);

    $score    = floatval($parsed['eligibility_score']);
    $status   = mysqli_real_escape_string($dbConn, $parsed['eligibility_status']);
    $exp      = mysqli_real_escape_string($dbConn, $parsed['experience_years']);
    $edu      = mysqli_real_escape_string($dbConn, $parsed['education_level']);
    $sm       = mysqli_real_escape_string($dbConn, implode(', ', $parsed['skills_matched']));
    $miss     = mysqli_real_escape_string($dbConn, implode(', ', $parsed['skills_missing']));
    $analysis = mysqli_real_escape_string($dbConn, json_encode($parsed));

    mysqli_query($dbConn, "UPDATE hr_screenings SET ai_analysis='$analysis',eligibility_score=$score,eligibility_status='$status',experience_years='$exp',education_level='$edu',skills_matched='$sm',skills_missing='$miss',screened_by=$current_user_id,updated_at=NOW() WHERE id=$sid");

    echo json_encode(['success'=>true,'data'=>$parsed,'score'=>$score]);
    exit;
}

// ---- AJAX: REVERT OBSERVATION PERIOD STATUS ----
if (isset($_POST['ajax_revert_observation_status'])) {
    header('Content-Type: application/json');
    $eval_id = intval($_POST['eval_id']);
    $sid     = intval($_POST['screening_id']);
    $round   = intval($_POST['round_number']);

    mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET obs_status=NULL, obs_notes=NULL, obs_marked_at=NULL, percentage=0, status='Pending', rating_label='Observation' WHERE id=$eval_id AND screening_id=$sid AND round_number=$round");

    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: SAVE OBSERVATION PERIOD STATUS ----
if (isset($_POST['ajax_save_observation_status'])) {
    header('Content-Type: application/json');
    $eval_id = intval($_POST['eval_id']);
    $sid     = intval($_POST['screening_id']);
    $round   = intval($_POST['round_number']);
    $status  = $_POST['obs_status'] === 'completed' ? 'completed' : 'not_completed';
    $notes   = mysqli_real_escape_string($dbConn, $_POST['obs_notes'] ?? '');

    // Reuse percentage/status fields so existing lock logic (>=90%) works unmodified
    $pct        = ($status == 'completed') ? 100 : 0;
    $main_status = ($status == 'completed') ? 'Passed' : 'Failed';
    $rating     = ($status == 'completed') ? 'Completed' : 'Not Completed';

    mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET obs_status='$status', obs_notes='$notes', obs_marked_at=NOW(), percentage=$pct, status='$main_status', rating_label='$rating' WHERE id=$eval_id AND screening_id=$sid AND round_number=$round");

    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: PROCESS REJECTION (round-level or overall) ----
if (isset($_POST['ajax_process_rejection'])) {
    header('Content-Type: application/json');
    $sid         = intval($_POST['screening_id'] ?? 0);
    $round_num   = intval($_POST['round_number'] ?? 0);
    $round_name  = mysqli_real_escape_string($dbConn, trim($_POST['round_name'] ?? 'Overall'));
    $round_type  = mysqli_real_escape_string($dbConn, trim($_POST['round_type'] ?? 'overall'));
    $reason      = trim($_POST['reason'] ?? '');
    $keep_in_db  = intval($_POST['keep_in_db'] ?? 1);

    if ($sid <= 0) { echo json_encode(['success'=>false,'message'=>'Invalid candidate.']); exit; }
    if ($reason === '') { echo json_encode(['success'=>false,'message'=>'A rejection reason is required.']); exit; }

    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['success'=>false,'message'=>'Candidate not found.']); exit; }

    $reason_esc       = mysqli_real_escape_string($dbConn, $reason);
    $rejected_by_esc  = mysqli_real_escape_string($dbConn, $current_user_name);
    $cname_esc        = mysqli_real_escape_string($dbConn, $sc['candidate_name']);
    $cemail_esc       = mysqli_real_escape_string($dbConn, $sc['candidate_email']);
    $cphone_esc       = mysqli_real_escape_string($dbConn, $sc['candidate_phone']);
    $pos_esc          = mysqli_real_escape_string($dbConn, $sc['position_applied']);
    $dept_esc         = mysqli_real_escape_string($dbConn, $sc['department']);
    $company_id_sql   = !empty($sc['company_id']) ? intval($sc['company_id']) : 'NULL';
    $resume_fname_esc = mysqli_real_escape_string($dbConn, $sc['resume_filename'] ?? '');
    $resume_path_esc  = mysqli_real_escape_string($dbConn, $sc['resume_path'] ?? '');

    // 1) Always write the permanent rejection log entry FIRST
    mysqli_query($dbConn, "INSERT INTO hr_rejection_log
        (screening_id, candidate_name, candidate_email, candidate_phone, position_applied, department, company_id,
         round_number, round_name, round_type, reason, rejected_by, kept_in_database, resume_filename, resume_path, rejection_source)
        VALUES
        ($sid, '$cname_esc', '$cemail_esc', '$cphone_esc', '$pos_esc', '$dept_esc', $company_id_sql,
         $round_num, '$round_name', '$round_type', '$reason_esc', '$rejected_by_esc', $keep_in_db, '$resume_fname_esc', '$resume_path_esc', 'hr_screening')");

    // 2) If round-level rejection, mark that round's evaluation as Rejected
    if ($round_num > 0) {
        $existing_eval = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_screening_evaluations WHERE screening_id=$sid AND round_number=$round_num LIMIT 1"));
        if ($existing_eval) {
            mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET status='Rejected', rejection_reason='$reason_esc', rejected_by='$rejected_by_esc', rejected_at=NOW() WHERE id=" . $existing_eval['id']);
        } else {
            mysqli_query($dbConn, "INSERT INTO hr_screening_evaluations (screening_id, round_number, evaluator_name, total_marks_obtained, total_marks_possible, percentage, rating_label, status, rejection_reason, rejected_by, rejected_at)
                VALUES ($sid, $round_num, '$rejected_by_esc', 0, 0, 0, 'Rejected', 'Rejected', '$reason_esc', '$rejected_by_esc', NOW())");
        }
    }

    // 3) Update overall candidate decision
    mysqli_query($dbConn, "UPDATE hr_screenings SET hr_decision='rejected', screening_notes='$reason_esc', updated_at=NOW() WHERE id=$sid");

    // 3.5) If this candidate also has a row in Candidate Tracking, remove it now that the
    // rejection is permanently recorded in hr_rejection_log above — mirrors the same
    // "log first, then remove from tracking" behavior used in hr_candidate_tracking.php,
    // so a candidate rejected from either page never leaves a stale row behind.
    $track_row_sync = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id, resume_path, jd_path FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
    if ($track_row_sync) {
        $tid_sync = intval($track_row_sync['id']);
        if (!empty($track_row_sync['resume_path']) && file_exists($track_row_sync['resume_path'])) @unlink($track_row_sync['resume_path']);
        if (!empty($track_row_sync['jd_path'])     && file_exists($track_row_sync['jd_path']))     @unlink($track_row_sync['jd_path']);
        mysqli_query($dbConn, "DELETE FROM hr_candidate_tracking_log WHERE candidate_id=$tid_sync");
        mysqli_query($dbConn, "DELETE FROM hr_candidate_tracking WHERE id=$tid_sync");
    }

    // 4) If HR chose NOT to keep in database, delete working record + files
    if ($keep_in_db == 0) {
        if (!empty($sc['resume_path']) && file_exists($sc['resume_path'])) @unlink($sc['resume_path']);
        if (!empty($sc['jd_path']) && file_exists($sc['jd_path'])) @unlink($sc['jd_path']);
        mysqli_query($dbConn, "DELETE FROM hr_screenings WHERE id=$sid");
    }

    echo json_encode(['success'=>true, 'deleted'=> ($keep_in_db == 0)]);
    exit;
}



// ---- AJAX: Manager Override UNLOCK NEXT ROUND ----
if (isset($_POST['ajax_hr_override_unlock'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);
    $round = intval($_POST['round_number']);
    $reason = mysqli_real_escape_string($dbConn, $_POST['override_reason'] ?? '');
    
    // Add override_reason column if not exists
    $col_check2 = mysqli_query($dbConn, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$cur_db' AND TABLE_NAME='hr_screening_evaluations' AND COLUMN_NAME='override_reason'");
    if (mysqli_num_rows($col_check2) == 0) {
        mysqli_query($dbConn, "ALTER TABLE hr_screening_evaluations ADD COLUMN override_reason text DEFAULT NULL");
    }
    
    mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET status='Override', override_reason='$reason' WHERE screening_id=$sid AND round_number=$round");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: GENERATE LINK FROM SCREENING PAGE ----
if (isset($_POST['ajax_generate_link_screening'])) {
    header('Content-Type: application/json');
    $candidate_id = intval($_POST['candidate_id']);
    $round_number = intval($_POST['round_number']);
    $dept_id      = intval($_POST['department_id']);
    $pos_id       = intval($_POST['position_id']);
    $expiry_hours = $_POST['expiry_hours'] ?? '';
    $expiry_custom = $_POST['expiry_custom'] ?? '';
    $submission_type = mysqli_real_escape_string($dbConn, $_POST['submission_type'] ?? 'questions');

    $existing = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_assignment_links WHERE candidate_id=$candidate_id AND round_number=$round_number LIMIT 1"));
    if ($existing) mysqli_query($dbConn, "DELETE FROM hr_assignment_links WHERE id=" . $existing['id']);

    $token      = bin2hex(random_bytes(32));
    if ($expiry_hours === 'custom' && !empty($expiry_custom)) {
        $expiry_sql = "'" . date('Y-m-d H:i:s', strtotime($expiry_custom)) . "'";
    } else {
        $hrs = intval($expiry_hours);
        $expiry_sql = $hrs > 0 ? "'" . date('Y-m-d H:i:s', strtotime("+{$hrs} hours")) . "'" : "NULL";
    }
    $created_by = mysqli_real_escape_string($dbConn, $current_user_name);

    mysqli_query($dbConn, "INSERT INTO hr_assignment_links (candidate_id, round_number, department_id, position_id, token, expiry_at, status, created_by, submission_type) VALUES ($candidate_id, $round_number, $dept_id, $pos_id, '$token', $expiry_sql, 'pending', '$created_by', '$submission_type')");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: START CALLING (create hr_candidate_tracking row linked to this screening) ----
if (isset($_POST['ajax_start_calling'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);

    $existing = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
    if ($existing) {
        echo json_encode(['success' => true, 'already_exists' => true, 'tracking_id' => $existing['id']]);
        exit;
    }

    if (!empty($_POST['skip_tracking_creation'])) {
        echo json_encode(['success' => true, 'message' => 'Skipped tracking creation.']);
        exit;
    }

    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if (!$sc) { echo json_encode(['success'=>false, 'message'=>'Candidate not found.']); exit; }

    $dept_name = mysqli_real_escape_string($dbConn, $sc['department']);
    $dept_row  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dept_name' LIMIT 1"));
    $dept_id   = $dept_row ? intval($dept_row['id']) : 0;
    $pos_id    = intval($sc['position_id'] ?? 0);
    $pos_name  = mysqli_real_escape_string($dbConn, $sc['position_applied']);
    $cname     = mysqli_real_escape_string($dbConn, $sc['candidate_name']);
    $cphone    = mysqli_real_escape_string($dbConn, $sc['candidate_phone']);
    $cemail    = mysqli_real_escape_string($dbConn, $sc['candidate_email']);
    $created_by= mysqli_real_escape_string($dbConn, $current_user_name);

    mysqli_query($dbConn, "INSERT INTO hr_candidate_tracking
        (screening_id, department_id, position_id, department_name, position_name, name, phone, email, resume_path, resume_name, jd_path, jd_name, current_status, created_by, last_updated_by)
        VALUES
        ($sid, $dept_id, $pos_id, '$dept_name', '$pos_name', '$cname', '$cphone', '$cemail',
         '" . mysqli_real_escape_string($dbConn, $sc['resume_path']) . "', '" . mysqli_real_escape_string($dbConn, $sc['resume_filename']) . "',
         '" . mysqli_real_escape_string($dbConn, $sc['jd_path'] ?? '') . "', '" . mysqli_real_escape_string($dbConn, $sc['jd_filename'] ?? '') . "',
         'New', '$created_by', '$created_by')");

    $new_tid = mysqli_insert_id($dbConn);
    mysqli_query($dbConn, "INSERT INTO hr_candidate_tracking_log (candidate_id, status, notes, updated_by) VALUES ($new_tid, 'New', 'Started calling process after shortlisting.', '$created_by')");

    echo json_encode(['success' => true, 'already_exists' => false, 'tracking_id' => $new_tid]);
    exit;
}

// ---- AJAX: GET CALLING STATUS for a screening_id (used to gate Round 1) ----
// ---- AJAX: GET CANDIDATE CONTACT (used before sending rejection notification) ----
if (isset($_GET['ajax_get_candidate_contact'])) {
    header('Content-Type: application/json');
    $sid = intval($_GET['screening_id'] ?? 0);
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT candidate_name, candidate_email, candidate_phone, position_applied FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if ($sc) {
        echo json_encode(['success'=>true, 'name'=>$sc['candidate_name'], 'email'=>$sc['candidate_email'], 'phone'=>$sc['candidate_phone'], 'position'=>$sc['position_applied']]);
    } else {
        echo json_encode(['success'=>false]);
    }
    exit;
}

// ---- AJAX: GET CALLING STATUS for a screening_id (used to gate Round 1) ----
if (isset($_GET['ajax_get_calling_status'])) {
    header('Content-Type: application/json');
    $sid = intval($_GET['screening_id'] ?? 0);
    $row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id, current_status, last_note, trigger_datetime FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
    echo json_encode(['exists' => (bool)$row, 'data' => $row ?: null]);
    exit;
}

// ---- AJAX: GENERATE ONBOARDING LINK ----
if (isset($_POST['ajax_generate_onboarding_link'])) {
    header('Content-Type: application/json');
    $candidate_id = intval($_POST['candidate_id']);

    // Check if candidate exists and is hired
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$candidate_id LIMIT 1"));
    if (!$sc || $sc['hr_decision'] !== 'hired') {
        echo json_encode(['success'=>false, 'message'=>'Candidate not found or not marked as hired.']);
        exit;
    }

    $existing = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_onboarding_links WHERE candidate_id=$candidate_id LIMIT 1"));
    if ($existing) mysqli_query($dbConn, "DELETE FROM hr_onboarding_links WHERE id=" . $existing['id']);

    $token = bin2hex(random_bytes(32));
    $cand_name = mysqli_real_escape_string($dbConn, $sc['candidate_name']);
    $cand_email = mysqli_real_escape_string($dbConn, $sc['candidate_email']);
    $created_by = mysqli_real_escape_string($dbConn, $current_user_name);

    mysqli_query($dbConn, "INSERT INTO hr_onboarding_links (candidate_id, token, candidate_name, candidate_email, status, created_by) VALUES ($candidate_id, '$token', '$cand_name', '$cand_email', 'pending', '$created_by')");

    echo json_encode(['success'=>true]);
    exit;
}

// ---- AJAX: SAVE WORK SAMPLE RATING ----
if (isset($_POST['ajax_save_worksample_rating'])) {
    header('Content-Type: application/json');
    $eval_id = intval($_POST['eval_id']);
    $sid     = intval($_POST['screening_id']);
    $round   = intval($_POST['round_number']);
    $pct     = intval($_POST['rating'] ?? 0);
    $notes   = mysqli_real_escape_string($dbConn, $_POST['notes'] ?? '');

    $rating_label = 'Poor';
    if ($pct >= 100) $rating_label = 'Significant';
    elseif ($pct >= 90) $rating_label = 'Outstanding';
    elseif ($pct >= 85) $rating_label = 'Excellent';
    elseif ($pct >= 80) $rating_label = 'Good';
    elseif ($pct >= 70) $rating_label = 'Average';
    $status = $pct >= 90 ? 'Passed' : 'Failed';

    mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET total_marks_obtained=$pct, total_marks_possible=100, percentage=$pct, rating_label='$rating_label', status='$status', hr_notes='$notes' WHERE id=$eval_id AND screening_id=$sid AND round_number=$round");
    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: SAVE ASSIGNMENT MARKS BY HR ----
if (isset($_POST['ajax_save_assignment_marks'])) {
    header('Content-Type: application/json');
    $eval_id       = intval($_POST['eval_id']);
    $sid           = intval($_POST['screening_id']);
    $round_number  = intval($_POST['round_number']);
    $total_possible = intval($_POST['total_possible']);
    $marks_json    = $_POST['marks_json'] ?? '{}';
    $marks_arr     = json_decode($marks_json, true) ?: [];

    $total_obtained = 0;
    foreach ($marks_arr as $qid => $marks) {
        $qid   = intval($qid);
        $marks = intval($marks);
        $total_obtained += $marks;
        mysqli_query($dbConn, "UPDATE hr_screening_evaluation_answers SET marks_obtained=$marks WHERE evaluation_id=$eval_id AND question_id=$qid");
    }

    $percentage = $total_possible > 0 ? ($total_obtained / $total_possible) * 100 : 0;
    // Round-half-up before comparing to thresholds — see note on the main round-evaluation
    // handler above for why (keeps rating label and Pass/Fail status consistent with each other).
    $rounded_pct = round($percentage);
    $rating_label = 'Poor';
    if ($rounded_pct >= 95) $rating_label = 'Significant';
    elseif ($rounded_pct >= 90) $rating_label = 'Outstanding';
    elseif ($rounded_pct >= 85) $rating_label = 'Excellent';
    elseif ($rounded_pct >= 80) $rating_label = 'Good';
    elseif ($rounded_pct >= 70) $rating_label = 'Average';

    $status = $rounded_pct >= 90 ? 'Passed' : 'Failed';
    $rating_label = mysqli_real_escape_string($dbConn, $rating_label);
    $status = mysqli_real_escape_string($dbConn, $status);
    $hr_notes_sql = "";
    if (isset($_POST['hr_notes'])) {
        $notes = mysqli_real_escape_string($dbConn, $_POST['hr_notes']);
        $hr_notes_sql = ", hr_notes='$notes'";
    }

    mysqli_query($dbConn, "UPDATE hr_screening_evaluations SET total_marks_obtained=$total_obtained, total_marks_possible=$total_possible, percentage=$percentage, rating_label='$rating_label', status='$status' $hr_notes_sql WHERE id=$eval_id");

    echo json_encode(['success' => true]);
    exit;
}

// ---- AJAX: SAVE DECISION ----
if (isset($_POST['ajax_update_decision'])) {
    header('Content-Type: application/json');
    $sid      = intval($_POST['screening_id']);
    $decision = mysqli_real_escape_string($dbConn, $_POST['decision'] ?? 'pending');
    $notes    = mysqli_real_escape_string($dbConn, $_POST['notes'] ?? '');

    // Only authorized HR can actually apply an override score, no matter what's posted
    $override_sql = ", hr_override_score=NULL";
    if ($can_override && isset($_POST['override_score']) && $_POST['override_score'] !== '') {
        $override = floatval($_POST['override_score']);
        $override_sql = ", hr_override_score=$override";
    }

    // Setting a candidate to Shortlisted/Hired below 90% counts as an override —
    // only authorized HR can do this, regardless of what the dropdown allowed.
    // Blue Collar candidates are exempt: their score is always 0 because Resume/JD/AI
    // scoring is intentionally skipped for that category, so it isn't a real signal to gate on.
    if (in_array($decision, ['shortlisted', 'hired']) && !$can_override) {
        $score_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT eligibility_score, hr_override_score, position_id FROM hr_screenings WHERE id=$sid LIMIT 1"));
        $is_bc_candidate = false;
        if (!empty($score_row['position_id'])) {
            $wc_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=" . intval($score_row['position_id']) . " LIMIT 1"));
            $is_bc_candidate = $wc_row && ($wc_row['worker_category'] === 'blue_collar');
        }

        if (!$is_bc_candidate) {
            $base_score = floatval($score_row['eligibility_score'] ?? 0);
            $existing_override = (isset($score_row['hr_override_score']) && $score_row['hr_override_score'] !== null) ? floatval($score_row['hr_override_score']) : null;
            $effective_score_chk = $existing_override !== null ? $existing_override : $base_score;

            if ($effective_score_chk < 90) {
                echo json_encode(['success' => false, 'message' => 'This candidate scored below 90%. Only authorized HR can Shortlist or Hire this candidate.']);
                exit;
            }
        }
    }

    mysqli_query($dbConn, "UPDATE hr_screenings SET hr_decision='$decision',screening_notes='$notes'$override_sql,updated_at=NOW() WHERE id=$sid");

    // Auto-create the candidate tracking row the moment HR shortlists this candidate
    if ($decision == 'shortlisted' && empty($_POST['skip_tracking_creation'])) {
        $already_tracked = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_candidate_tracking WHERE screening_id=$sid LIMIT 1"));
        if (!$already_tracked) {
            $sc_for_track = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$sid LIMIT 1"));
            if ($sc_for_track) {
                $dept_name_t = mysqli_real_escape_string($dbConn, $sc_for_track['department']);
                $dept_row_t  = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dept_name_t' LIMIT 1"));
                $dept_id_t   = $dept_row_t ? intval($dept_row_t['id']) : 0;
                $pos_id_t    = intval($sc_for_track['position_id'] ?? 0);
                $pos_name_t  = mysqli_real_escape_string($dbConn, $sc_for_track['position_applied']);
                $cname_t     = mysqli_real_escape_string($dbConn, $sc_for_track['candidate_name']);
                $cphone_t    = mysqli_real_escape_string($dbConn, $sc_for_track['candidate_phone']);
                $cemail_t    = mysqli_real_escape_string($dbConn, $sc_for_track['candidate_email']);
                $created_by_t= mysqli_real_escape_string($dbConn, $current_user_name);

                mysqli_query($dbConn, "INSERT INTO hr_candidate_tracking
                    (screening_id, department_id, position_id, department_name, position_name, name, phone, email, resume_path, resume_name, jd_path, jd_name, current_status, created_by, last_updated_by)
                    VALUES
                    ($sid, $dept_id_t, $pos_id_t, '$dept_name_t', '$pos_name_t', '$cname_t', '$cphone_t', '$cemail_t',
                     '" . mysqli_real_escape_string($dbConn, $sc_for_track['resume_path']) . "', '" . mysqli_real_escape_string($dbConn, $sc_for_track['resume_filename']) . "',
                     '" . mysqli_real_escape_string($dbConn, $sc_for_track['jd_path'] ?? '') . "', '" . mysqli_real_escape_string($dbConn, $sc_for_track['jd_filename'] ?? '') . "',
                     'New', '$created_by_t', '$created_by_t')");

                $new_tid_auto = mysqli_insert_id($dbConn);
                mysqli_query($dbConn, "INSERT INTO hr_candidate_tracking_log (candidate_id, status, notes, updated_by) VALUES ($new_tid_auto, 'New', 'Auto-created on shortlisting.', '$created_by_t')");
            }
        }
    }

    echo json_encode(['success'=>true]);
    exit;
}

// ---- AJAX: EDIT CANDIDATE ----
if (isset($_POST['ajax_edit_candidate'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);
    $cname = mysqli_real_escape_string($dbConn, $_POST['candidate_name'] ?? '');
    $cemail = mysqli_real_escape_string($dbConn, $_POST['candidate_email'] ?? '');
    $cphone = mysqli_real_escape_string($dbConn, $_POST['candidate_phone'] ?? '');
    $dept = mysqli_real_escape_string($dbConn, $_POST['department'] ?? '');
    $pos_applied = mysqli_real_escape_string($dbConn, $_POST['position_applied'] ?? '');
    
    // Attempt to lookup position_id based on the newly selected position title
    $pos_id = 0;
    if ($pos_applied) {
        $pos_query = mysqli_query($dbConn, "SELECT id FROM hr_positions WHERE title='$pos_applied' LIMIT 1");
        if ($pos_query && mysqli_num_rows($pos_query) > 0) {
            $pos_row = mysqli_fetch_assoc($pos_query);
            $pos_id = $pos_row['id'];
        }
    }

    $company_id = intval($_POST['company_id'] ?? 0);
$q = "UPDATE hr_screenings SET candidate_name='$cname', candidate_email='$cemail', candidate_phone='$cphone', company_id=$company_id, department='$dept', position_applied='$pos_applied', position_id=$pos_id, updated_at=NOW() WHERE id=$sid";
    if (mysqli_query($dbConn, $q)) {
        echo json_encode(['success'=>true]);
    } else {
        echo json_encode(['success'=>false, 'message'=>mysqli_error($dbConn)]);
    }
    exit;
}

// ---- AJAX: DELETE CANDIDATE ----
if (isset($_POST['ajax_delete_candidate'])) {
    header('Content-Type: application/json');
    $sid = intval($_POST['screening_id']);
    // Optional: Fetch file paths to unlink them from server if needed
    $sc = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT resume_path, jd_path FROM hr_screenings WHERE id=$sid LIMIT 1"));
    if ($sc) {
        if (file_exists($sc['resume_path'])) @unlink($sc['resume_path']);
        if (file_exists($sc['jd_path'])) @unlink($sc['jd_path']);
        mysqli_query($dbConn, "DELETE FROM hr_screenings WHERE id=$sid");
        echo json_encode(['success'=>true]);
    } else {
        echo json_encode(['success'=>false, 'message'=>'Record not found']);
    }
    exit;
}

// ---- AJAX/POST: SAVE CANDIDATE FROM REVIEW ----
if (isset($_POST['ajax_save_candidate']) && isset($_SESSION['review_candidate'])) {
    try {
        $sess = $_SESSION['review_candidate'];
        $ai   = $sess['ai_results'] ?? [];

        // Safe truncate helper — clamps any field to its column's max length so MySQL never rejects it
        $clamp = function($val, $max) {
            $val = (string)($val ?? '');
            $val = preg_replace('/[^\x{0009}\x{000A}\x{000D}\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}]+/u', ' ', $val);
            if ($val === null) $val = ''; // preg_replace can return null on bad UTF-8
            return mb_substr($val, 0, $max);
        };

        $cname     = mysqli_real_escape_string($dbConn, $clamp($sess['candidate_name'] ?? '', 255));
        $cemail    = mysqli_real_escape_string($dbConn, $clamp($sess['candidate_email'] ?? '', 255));
        $cphone    = mysqli_real_escape_string($dbConn, $clamp($sess['candidate_phone'] ?? '', 30));
        $pos       = mysqli_real_escape_string($dbConn, $clamp($sess['position_applied'] ?? '', 255));
        $pos_id    = intval($sess['position_id'] ?? 0);
        $company_id= intval($sess['company_id'] ?? 0);
        $dept      = mysqli_real_escape_string($dbConn, $clamp($sess['department'] ?? '', 255));
        $rfname_e  = mysqli_real_escape_string($dbConn, $clamp($sess['resume_filename'] ?? '', 500));
        $rpath_e   = mysqli_real_escape_string($dbConn, $clamp($sess['resume_path'] ?? '', 500));
        $rtext_e   = mysqli_real_escape_string($dbConn, $clamp($sess['resume_text'] ?? '', 50000));
        $jdfname_e = mysqli_real_escape_string($dbConn, $clamp($sess['jd_filename'] ?? '', 500));
        $jdpath_e  = mysqli_real_escape_string($dbConn, $clamp($sess['jd_path'] ?? '', 500));
        $jdtext_e  = mysqli_real_escape_string($dbConn, $clamp($sess['jd_text'] ?? '', 30000));

        $analysis_json = mysqli_real_escape_string($dbConn, $clamp(json_encode($ai), 60000));
        $score         = intval($ai['eligibility_score'] ?? 0);
        $status        = mysqli_real_escape_string($dbConn, $clamp($ai['eligibility_status'] ?? 'pending', 30));
        $exp           = mysqli_real_escape_string($dbConn, $clamp($ai['experience_years'] ?? '', 50));
        $edu           = mysqli_real_escape_string($dbConn, $clamp($ai['education_level'] ?? '', 100));
        $sm            = mysqli_real_escape_string($dbConn, $clamp(json_encode($ai['skills_matched'] ?? []), 20000));
        $miss          = mysqli_real_escape_string($dbConn, $clamp(json_encode($ai['skills_missing'] ?? []), 20000));

        $override_sql = "NULL";
        if (isset($_POST['hr_override_score']) && $_POST['hr_override_score'] !== '') {
            $override_sql = floatval($_POST['hr_override_score']);
        }

        $ins = @mysqli_query($dbConn, "INSERT INTO hr_screenings
            (candidate_name, candidate_email, candidate_phone, position_applied, position_id, company_id, department,
             resume_filename, resume_path, resume_text,
             jd_filename, jd_path, jd_text,
             ai_analysis, eligibility_score, eligibility_status, experience_years, education_level, skills_matched, skills_missing,
             hr_decision, hr_override_score, screened_by)
            VALUES
            ('$cname','$cemail','$cphone','$pos',$pos_id,$company_id,'$dept',
             '$rfname_e','$rpath_e','$rtext_e',
             '$jdfname_e','$jdpath_e','$jdtext_e',
             '$analysis_json', $score, '$status', '$exp', '$edu', '$sm', '$miss',
             'pending', $override_sql, $current_user_id)");

        if ($ins) {
            $new_sid = mysqli_insert_id($dbConn);
            unset($_SESSION['review_candidate']); // Clear session
            header('Location: ' . $_SERVER['PHP_SELF'] . '?uploaded=' . $new_sid);
            exit;
        } else {
            $upload_error = 'Database error saving candidate: ' . mysqli_error($dbConn);
        }
    } catch (\Throwable $e) {
        $upload_error = 'Could not save candidate: ' . $e->getMessage() . ' — please re-check the entered details and try again.';
    }
}

// ---- UPLOAD HANDLER ----
$upload_success = false;
$upload_error   = '';
$new_sid        = 0;
$cand_info      = [];

if (isset($_GET['uploaded']) && intval($_GET['uploaded']) > 0) {
    $new_sid        = intval($_GET['uploaded']);
    $upload_success = true;
    $cand_res = mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE id=$new_sid LIMIT 1");
    if ($cand_res) $cand_info = mysqli_fetch_assoc($cand_res);
} elseif (isset($_GET['review']) && isset($_SESSION['review_candidate'])) {
    $cand_info = $_SESSION['review_candidate'];
    $upload_success = true; // Pretend upload success to show files
}

if (isset($_POST['submit_resume'])) {
    try {
        $cname  = mysqli_real_escape_string($dbConn, trim($_POST['candidate_name'] ?? ''));
        $cemail = mysqli_real_escape_string($dbConn, trim($_POST['candidate_email'] ?? ''));
        $cphone = mysqli_real_escape_string($dbConn, trim($_POST['candidate_phone'] ?? ''));
        $pos    = mysqli_real_escape_string($dbConn, trim($_POST['position_applied'] ?? ''));
        $pos_id = intval($_POST['position_id'] ?? 0);
        $company_id = intval($_POST['company_id'] ?? 0);
        $dept   = mysqli_real_escape_string($dbConn, trim($_POST['department'] ?? ''));

        // Robust fallback logic for position ID and title
        if (empty($pos) && $pos_id > 0) {
            $pq = mysqli_query($dbConn, "SELECT title FROM hr_positions WHERE id=$pos_id LIMIT 1");
            if ($prow = mysqli_fetch_assoc($pq)) {
                $pos = mysqli_real_escape_string($dbConn, $prow['title']);
            }
        } elseif ($pos_id == 0 && !empty($pos)) {
            $pq = mysqli_query($dbConn, "SELECT id FROM hr_positions WHERE title='$pos' LIMIT 1");
            if ($prow = mysqli_fetch_assoc($pq)) {
                $pos_id = intval($prow['id']);
            }
        }

        // Blue Collar positions: Resume/JD upload and AI scoring become optional — the
        // candidate can still be added and moved straight into interview rounds.
        $is_blue_collar = false;
        if ($pos_id > 0) {
            $wcRow = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=$pos_id"));
            $is_blue_collar = $wcRow && ($wcRow['worker_category'] === 'blue_collar');
        }

        $has_resume_file = isset($_FILES['resume_file']) && $_FILES['resume_file']['error'] === UPLOAD_ERR_OK;
        $has_jd_file     = isset($_FILES['jd_file'])     && $_FILES['jd_file']['error']     === UPLOAD_ERR_OK;

        if (!$cname) {
            $upload_error = 'Candidate Name is required.';
        } elseif (!$is_blue_collar && !$has_resume_file) {
            $fe = isset($_FILES['resume_file']['error']) ? $_FILES['resume_file']['error'] : -1;
            $upload_error = 'Resume upload failed (PHP error code: ' . $fe . '). Check file size limit in php.ini (upload_max_filesize / post_max_size).';
        } elseif (!$is_blue_collar && !$has_jd_file) {
            $fe = isset($_FILES['jd_file']['error']) ? $_FILES['jd_file']['error'] : -1;
            $upload_error = 'Job Description (JD) upload is required (PHP error code: ' . $fe . ').';
        } else {
            $allowed = array('pdf','doc','docx','txt');
            $rpath = ''; $rname = ''; $rtext = ''; $resume_extraction_failed = true;

            if ($has_resume_file) {
                $rf   = $_FILES['resume_file'];
                $rext = strtolower(pathinfo($rf['name'], PATHINFO_EXTENSION));

                if (!in_array($rext, $allowed)) {
                    $upload_error = 'Resume: only PDF, DOC, DOCX, TXT allowed. Got: ' . htmlspecialchars($rext);
                } else {
                    $dir = 'uploads/hr_screening/';
                    if (!is_dir($dir)) {
                        if (!mkdir($dir, 0755, true)) {
                            throw new Exception('Cannot create upload directory: ' . $dir . '. Check server folder permissions.');
                        }
                    }
                    if (!is_writable($dir)) {
                        throw new Exception('Upload directory not writable: ' . $dir . '. Run: chmod 755 ' . $dir);
                    }

                    $rpath = $dir . 'resume_' . time() . '_' . rand(1000,9999) . '.' . $rext;
                    if (!move_uploaded_file($rf['tmp_name'], $rpath)) {
                        throw new Exception('Could not save resume to: ' . $rpath . '. Check permissions.');
                    }

                    $rname = $rf['name'];
                    $rtext = extractText($rpath, $rext);
                    $resume_extraction_failed = (strlen(trim($rtext)) < 30);
                    if ($resume_extraction_failed) {
                        $rtext = ''; // Do not fabricate content — leave genuinely empty
                    }
                }
            }

            if (!$upload_error) {
                $jd_path = ''; $jd_fname = ''; $jd_text = '';
                if ($has_jd_file) {
                    $jf   = $_FILES['jd_file'];
                    $jext = strtolower(pathinfo($jf['name'], PATHINFO_EXTENSION));
                    if (in_array($jext, $allowed)) {
                        $dir = 'uploads/hr_screening/';
                        if (!is_dir($dir)) @mkdir($dir, 0755, true);
                        $jd_path = $dir . 'jd_' . time() . '_' . rand(1000,9999) . '.' . $jext;
                        if (move_uploaded_file($jf['tmp_name'], $jd_path)) {
                            $jd_text  = extractText($jd_path, $jext);
                            $jd_fname = $jf['name'];
                        }
                    }
                }

                // Run AI Analysis immediately in-memory — but only if we actually got readable resume text
                if ($resume_extraction_failed) {
                    if ($is_blue_collar && !$has_resume_file) {
                        $analysis_results = [
                            'eligibility_score'    => 0,
                            'eligibility_status'   => 'not_applicable',
                            'candidate_summary'    => 'Resume/JD/AI scoring skipped for this Blue Collar role. Candidate proceeds directly to HR/Manager interview rounds.',
                            'experience_years'     => 'N/A',
                            'education_level'      => 'N/A',
                            'jd_key_requirements'  => [],
                            'skills_matched'       => [],
                            'skills_missing'       => [],
                            'strengths'            => [],
                            'concerns'             => [],
                            'jd_vs_resume_gap'     => 'Not applicable — Blue Collar role.',
                            'recommendation'       => 'Proceed with HR Interview / Observation Period as per the Blue Collar hiring process.',
                            'interview_questions'  => []
                        ];
                    } else {
                        $analysis_results = [
                            'eligibility_score'    => 0,
                            'eligibility_status'   => 'pending',
                            'candidate_summary'    => 'Could not extract readable text from this resume file. The PDF may be a scanned image or use an unsupported encoding. Please re-upload as a .docx or .txt file, or a text-based (not scanned) PDF, then re-run analysis.',
                            'experience_years'     => 'Unknown',
                            'education_level'      => 'Unknown',
                            'jd_key_requirements'  => [],
                            'skills_matched'       => [],
                            'skills_missing'       => [],
                            'strengths'            => [],
                            'concerns'             => ['Resume text could not be extracted — analysis was not run.'],
                            'jd_vs_resume_gap'     => 'Not available — resume text extraction failed.',
                            'recommendation'       => 'Please re-upload the resume in a readable format (.docx or .txt) and re-run analysis.',
                            'interview_questions'  => []
                        ];
                    }
                } else {
                    $analysis_results = kwm_analyze($rtext, $jd_text, $pos, $dept);
                }

                $_SESSION['review_candidate'] = [
                    'candidate_name' => $cname,
                    'candidate_email' => $cemail,
                    'candidate_phone' => $cphone,
                    'position_applied' => $pos,
                    'position_id' => $pos_id,
                    'company_id' => $company_id,
                    'department' => $dept,
                    'resume_path' => $rpath,
                    'jd_path' => $jd_path,
                    'resume_filename' => $rname,
                    'jd_filename' => $jd_fname,
                    'resume_text' => $rtext,
                    'jd_text' => $jd_text,
                    'ai_results' => $analysis_results
                ];

                header('Location: ' . $_SERVER['PHP_SELF'] . '?review=1');
                exit;
            }
        }
    } catch (Exception $e) {
        $upload_error = 'Server error: ' . $e->getMessage();
    }
}

// ---- FETCH DATA ----
// Rejected candidates are deliberately excluded from this page's stats and table —
// they live permanently on hr-rejected-candidates.php instead, so this page only
// shows the active pipeline.
$stats = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT COUNT(*) as total, SUM(CASE WHEN eligibility_status IN ('eligible','highly_eligible') THEN 1 ELSE 0 END) as eligible, SUM(CASE WHEN eligibility_status='partially_eligible' THEN 1 ELSE 0 END) as partial, SUM(CASE WHEN eligibility_status='not_eligible' THEN 1 ELSE 0 END) as not_eligible, SUM(CASE WHEN hr_decision='shortlisted' THEN 1 ELSE 0 END) as shortlisted, SUM(CASE WHEN eligibility_status='pending' THEN 1 ELSE 0 END) as pending_ai FROM hr_screenings WHERE hr_decision <> 'rejected'"));
$all_rows = mysqli_query($dbConn, "SELECT * FROM hr_screenings WHERE hr_decision <> 'rejected' ORDER BY created_at DESC");
$depts = []; $dq = mysqli_query($dbConn, "SELECT name FROM hr_departments ORDER BY name ASC"); while($r=mysqli_fetch_assoc($dq)) $depts[]=$r['name'];
$companies_list = [];
$companies_map = [];
$_offer_con = function_exists('conexion') ? conexion() : $dbConn;
$cq = mysqli_query($_offer_con, "SELECT id, company_name FROM hr_companies ORDER BY company_name ASC");
while ($cr = mysqli_fetch_assoc($cq)) {
    $companies_list[] = $cr;
    $companies_map[$cr['id']] = $cr['company_name'];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>HR Screening | CRM</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0f2557;--blue:#1a3fc4;--success:#10b981;--warn:#f59e0b;--danger:#ef4444;--bg:#f0f4f9;--card:#fff;--border:#e4e9f2;--muted:#64748b;}

/* Toast Card */
.toast-card {
    position: fixed; top: 24px; right: -350px; width: 300px;
    background: #fff; border-left: 5px solid var(--success);
    border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,0.15);
    padding: 16px 20px; z-index: 9999;
    transition: right 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
    display: flex; align-items: center; gap: 14px;
}
.toast-card.show { right: 24px; }
.toast-card.error { border-left-color: var(--danger); }
.toast-icon { font-size: 22px; color: var(--success); }
.toast-card.error .toast-icon { color: var(--danger); }
.toast-text { font-size: 13px; font-weight: 700; color: var(--navy); line-height: 1.4; }
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Plus Jakarta Sans',sans-serif;background:var(--bg);min-height:100vh;color:#0f172a;}
.hdr{background:linear-gradient(135deg,var(--navy),var(--blue));padding:20px 28px;display:flex;justify-content:space-between;align-items:center;box-shadow:0 4px 20px rgba(15,37,87,.25);}
.hdr h1{color:#fff;font-size:1.45rem;font-weight:800;margin:0;}
.hdr .sub{color:rgba(255,255,255,.7);font-size:12px;margin-top:3px;}
.btn-h{padding:9px 18px;border-radius:9px;font-weight:700;cursor:pointer;border:none;display:inline-flex;align-items:center;gap:6px;font-size:13px;transition:.2s;text-decoration:none;color:#fff;}
.btn-teal{background:linear-gradient(135deg,#00c6ad,#00a28e);}
.btn-navy{background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.3);}
.btn-h:hover{transform:translateY(-1px);box-shadow:0 5px 15px rgba(0,0,0,.15);color:#fff;text-decoration:none;}
.wrap{max-width:1500px;margin:0 auto;padding:24px 20px;}
.alert-banner{background:linear-gradient(135deg,#f97316,#ea580c);border-radius:12px;padding:14px 22px;display:flex;align-items:center;gap:14px;color:#fff;font-weight:600;margin-bottom:22px;cursor:pointer;box-shadow:0 4px 14px rgba(249,115,22,.35);animation:gentlePulse 2.5s infinite;}
@keyframes gentlePulse{0%,100%{opacity:1}50%{opacity:.85}}
.alert-banner i{font-size:1.3rem;}
.alert-banner .count-pill{background:rgba(255,255,255,.25);border-radius:20px;padding:3px 12px;font-size:.85rem;}
.alert-card-item{background:#f8fafc;border-radius:12px;padding:16px;margin-bottom:14px;}
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:14px;margin-bottom:24px;}
.stat-box{background:var(--card);border-radius:13px;padding:18px;border:1px solid var(--border);display:flex;align-items:center;gap:12px;box-shadow:0 2px 8px rgba(0,0,0,.04);}
.stat-ico{width:46px;height:46px;border-radius:11px;display:flex;align-items:center;justify-content:center;font-size:17px;flex-shrink:0;}
.stat-val{font-size:24px;font-weight:800;line-height:1;}
.stat-lbl{font-size:10px;font-weight:700;color:var(--muted);text-transform:uppercase;margin-top:3px;}
.tab-bar{display:flex;gap:5px;background:var(--card);padding:7px;border-radius:13px;border:1px solid var(--border);margin-bottom:18px;}
.tab-btn{flex:1;padding:10px;border:none;background:transparent;font-family:inherit;font-weight:700;font-size:13px;color:var(--muted);border-radius:9px;cursor:pointer;transition:.2s;display:flex;align-items:center;justify-content:center;gap:6px;}
.tab-btn.active{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;box-shadow:0 3px 12px rgba(26,63,196,.25);}
.tab-pane{display:none;}.tab-pane.active{display:block;}
.card-panel{background:var(--card);border-radius:15px;border:1px solid var(--border);box-shadow:0 2px 10px rgba(0,0,0,.05);overflow:hidden;}
.card-head{padding:18px 22px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;background:linear-gradient(135deg,#f8faff,#eef2ff);}
.card-head h5{font-weight:800;color:var(--navy);margin:0;}
.form-sec{background:var(--card);border-radius:15px;border:1px solid var(--border);padding:26px;box-shadow:0 2px 10px rgba(0,0,0,.05);}
.sec-lbl{font-weight:800;font-size:11px;text-transform:uppercase;color:var(--blue);margin-bottom:12px;padding-bottom:7px;border-bottom:2px solid #eef2ff;display:flex;align-items:center;gap:7px;letter-spacing:.5px;}
.fc{box-sizing:border-box;border:2px solid var(--border);border-radius:9px;padding:10px 13px;font-size:13px;font-family:inherit;font-weight:600;width:100%;transition:.2s;background:#fff;color:#0f172a;}
.fc:focus{outline:none;border-color:var(--blue);box-shadow:0 0 0 3px rgba(26,63,196,.08);}
label.fl{font-weight:700;font-size:12px;display:block;margin-bottom:5px;}
.fg{margin-bottom:16px;}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:16px;}
.upzone{border:2px dashed var(--blue);border-radius:13px;padding:26px 18px;text-align:center;background:#f8faff;cursor:pointer;transition:.3s;position:relative;}
.upzone.jdz{border-color:#6366f1;background:#f5f3ff;}
.upzone:hover{border-style:solid;}
.upzone input[type=file]{position:absolute;inset:0;opacity:0;cursor:pointer;width:100%;height:100%;}
.upzone .uico{font-size:26px;margin-bottom:7px;}
.upzone .utxt{font-weight:700;font-size:13px;}
.upzone .usub{font-size:11px;color:var(--muted);margin-top:3px;}
.file-ok{display:none;align-items:center;gap:7px;background:#f0fdf4;border:1px solid #86efac;border-radius:7px;padding:8px 12px;margin-top:7px;font-size:12px;font-weight:700;color:#065f46;}
.btn-sub{width:100%;padding:14px;border:none;border-radius:11px;font-family:inherit;font-weight:800;font-size:14px;cursor:pointer;background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;transition:.2s;display:flex;align-items:center;justify-content:center;gap:7px;margin-top:10px;}
.btn-sub:hover:not(:disabled){transform:translateY(-2px);box-shadow:0 7px 20px rgba(26,63,196,.3);}
.btn-sub:disabled{opacity:.5;cursor:not-allowed;}
.tbl-wrap{overflow-x:auto;}
table.stbl{width:100%;border-collapse:collapse;}
table.stbl thead th{background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;font-weight:800;padding:12px 15px;font-size:11px;text-transform:uppercase;white-space:nowrap;border:none;}
table.stbl tbody td{padding:13px 15px;border-bottom:1px solid #f1f5f9;font-size:13px;font-weight:600;vertical-align:middle;}
table.stbl tbody tr:hover{background:#f8faff;}
.badge-s{padding:4px 11px;border-radius:20px;font-weight:800;font-size:11px;text-transform:uppercase;white-space:nowrap;}
.b-pending{background:#f1f5f9;color:#475569;}
.b-eligible{background:#dcfce7;color:#065f46;}
.b-highly{background:#a7f3d0;color:#064e3b;}
.b-partial{background:#fef9c3;color:#713f12;}
.b-not{background:#fee2e2;color:#991b1b;}
.b-shortlisted{background:#dbeafe;color:#1e40af;}
.b-rejected{background:#fee2e2;color:#991b1b;}
.b-hired{background:#a7f3d0;color:#064e3b;}
.pbar-wrap{background:#e2e8f0;border-radius:99px;height:7px;overflow:hidden;flex:1;}
.pbar-fill{height:100%;border-radius:99px;}
.alert-ok{background:#dcfce7;border:1px solid #86efac;color:#065f46;padding:14px 18px;border-radius:11px;font-weight:700;margin-bottom:18px;display:flex;align-items:center;gap:9px;}
.alert-err{background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:14px 18px;border-radius:11px;font-weight:700;margin-bottom:18px;display:flex;align-items:center;gap:9px;}
.filter-row{display:flex;gap:9px;flex-wrap:wrap;align-items:center;}
.ai-panel{background:#f8faff;border:2px solid #e0e7ff;border-radius:15px;padding:22px;}
.score-ring-wrap{text-align:center;margin-bottom:18px;}
.score-ring{position:relative;display:inline-block;}
.score-ring svg{transform:rotate(-90deg);}
.score-ring .score-num{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;font-weight:800;font-size:26px;color:var(--navy);line-height:1;}
.score-ring .score-num small{font-size:11px;font-weight:600;color:var(--muted);}
.ai-section{margin-bottom:16px;}
.ai-section h6{font-weight:800;font-size:11px;text-transform:uppercase;color:var(--navy);margin-bottom:8px;display:flex;align-items:center;gap:5px;}
.skill-tag{display:inline-block;padding:4px 11px;border-radius:20px;font-size:12px;font-weight:700;margin:2px;}
.skill-ok{background:#dcfce7;color:#065f46;}
.skill-miss{background:#fee2e2;color:#991b1b;}
.strength-item{padding:7px 11px;background:#f0fdf4;border-left:3px solid var(--success);border-radius:5px;font-size:12px;font-weight:600;margin-bottom:5px;color:#065f46;}
.concern-item{padding:7px 11px;background:#fff7ed;border-left:3px solid var(--warn);border-radius:5px;font-size:12px;font-weight:600;margin-bottom:5px;color:#92400e;}
.q-item{padding:9px 13px;background:#f8faff;border:1px solid #e0e7ff;border-radius:7px;font-size:12px;font-weight:600;margin-bottom:5px;color:var(--navy);}
.q-item::before{content:"Q: ";font-weight:800;color:var(--blue);}
.modal-content{border-radius:15px;border:none;box-shadow:0 20px 60px rgba(0,0,0,.2);}
.modal-header{background:linear-gradient(135deg,var(--navy),var(--blue));border-radius:15px 15px 0 0;}
.modal-header h4{color:#fff;font-weight:800;margin:0;}
.modal-header .close{color:#fff;opacity:.8;}
.cav{display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;background:linear-gradient(135deg,var(--navy),var(--blue));flex-shrink:0;}
@media(max-width:768px){.row2{grid-template-columns:1fr;}.hdr{flex-direction:column;gap:12px;}.stats-grid{grid-template-columns:repeat(2,1fr);}}

/* Custom alert overlay — replaces native browser alert() with a styled card */
.hrs-alert-overlay{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(15,37,87,0.5);backdrop-filter:blur(4px);z-index:100000;align-items:center;justify-content:center;padding:20px;}
.hrs-alert-overlay.show{display:flex;}
.hrs-alert-card{background:#fff;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,.25);max-width:400px;width:100%;padding:32px;text-align:center;animation:hrsAlertPop .25s cubic-bezier(.175,.885,.32,1.275) forwards;}
@keyframes hrsAlertPop{0%{opacity:0;transform:scale(.85);}100%{opacity:1;transform:scale(1);}}
.hrs-alert-icon{font-size:44px;margin-bottom:14px;}
.hrs-alert-icon.err{color:#ef4444;}
.hrs-alert-icon.warn{color:#f59e0b;}
.hrs-alert-title{font-size:17px;font-weight:800;color:#0f2557;margin-bottom:10px;}
.hrs-alert-text{font-size:13.5px;color:#64748b;line-height:1.6;margin-bottom:22px;}
.hrs-alert-btn{padding:11px 34px;border:none;border-radius:10px;background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;}
</style>
</head>
<body>

<?php
$is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
$dashboard_url = $is_admin ? '/dashboard/index.php' : '/dashboard/raise-a-ticket.php';

// ============================================================
// INTERVIEW DASHBOARD — today's interviews (grouped by round) and
// missed/overdue interviews, derived entirely from hr_interview_schedules
// vs hr_screening_evaluations: a schedule with no matching evaluation and
// a past time means missed; a matching evaluation means completed. No
// separate status field needed for this.
// ============================================================
$iv_round     = trim($_GET['iv_round'] ?? '');
$iv_position  = trim($_GET['iv_position'] ?? '');
$iv_recruiter = trim($_GET['iv_recruiter'] ?? '');

$iv_where_extra = "";
if ($iv_round !== '') $iv_where_extra .= " AND his.round_number = " . intval($iv_round);
if ($iv_position !== '') $iv_where_extra .= " AND s.position_applied = '" . mysqli_real_escape_string($dbConn, $iv_position) . "'";
if ($iv_recruiter !== '') $iv_where_extra .= " AND his.scheduled_by = '" . mysqli_real_escape_string($dbConn, $iv_recruiter) . "'";

// "Offer"-type rounds (e.g. "HR Discussion and Offer") never get a row in
// hr_screening_evaluations — completion is tracked only via hr_screenings.
// hr_decision='hired'. Without accounting for this, a hired candidate's offer
// round would show as permanently missed/overdue, which it isn't.
$iv_join_extra = "
    LEFT JOIN hr_departments hd ON hd.name = s.department
    LEFT JOIN hr_screening_rounds hsr ON hsr.department_id = hd.id AND hsr.position_id = s.position_id AND hsr.round_number = his.round_number
";
$iv_offer_done_extra = " AND NOT (hsr.round_type = 'offer' AND s.hr_decision = 'hired')";

$iv_today_res = mysqli_query($dbConn, "
    SELECT his.id, his.screening_id, his.round_number, his.scheduled_datetime, his.scheduled_by,
           s.candidate_name, s.position_applied, s.department, s.hr_decision,
           s.candidate_phone, s.candidate_email,
           ev.id as eval_id, hsr.round_type
    FROM hr_interview_schedules his
    JOIN hr_screenings s ON s.id = his.screening_id
    LEFT JOIN hr_screening_evaluations ev ON ev.screening_id = his.screening_id AND ev.round_number = his.round_number
    $iv_join_extra
    WHERE DATE(his.scheduled_datetime) = CURDATE() $iv_where_extra
    ORDER BY his.round_number ASC, his.scheduled_datetime ASC
");
$iv_today_rows = [];
if ($iv_today_res) while ($ivr = mysqli_fetch_assoc($iv_today_res)) $iv_today_rows[] = $ivr;

$iv_missed_res = mysqli_query($dbConn, "
    SELECT his.id, his.screening_id, his.round_number, his.scheduled_datetime, his.scheduled_by,
           s.candidate_name, s.position_applied, s.department,
           s.candidate_phone, s.candidate_email
    FROM hr_interview_schedules his
    JOIN hr_screenings s ON s.id = his.screening_id
    LEFT JOIN hr_screening_evaluations ev ON ev.screening_id = his.screening_id AND ev.round_number = his.round_number
    $iv_join_extra
    WHERE his.scheduled_datetime < NOW() AND ev.id IS NULL $iv_offer_done_extra $iv_where_extra
    ORDER BY his.scheduled_datetime DESC
");
$iv_missed_rows = [];
if ($iv_missed_res) while ($ivr = mysqli_fetch_assoc($iv_missed_res)) $iv_missed_rows[] = $ivr;

// Filter dropdown option lists
$iv_rounds_list = [];
$iv_rr = mysqli_query($dbConn, "SELECT DISTINCT round_number FROM hr_interview_schedules ORDER BY round_number ASC");
if ($iv_rr) while ($ivx = mysqli_fetch_assoc($iv_rr)) $iv_rounds_list[] = intval($ivx['round_number']);

$iv_positions_list = [];
$iv_pr = mysqli_query($dbConn, "SELECT DISTINCT s.position_applied FROM hr_interview_schedules his JOIN hr_screenings s ON s.id = his.screening_id WHERE s.position_applied IS NOT NULL AND s.position_applied != '' ORDER BY s.position_applied ASC");
if ($iv_pr) while ($ivx = mysqli_fetch_assoc($iv_pr)) $iv_positions_list[] = $ivx['position_applied'];

$iv_recruiters_list = [];
$iv_cr = mysqli_query($dbConn, "SELECT DISTINCT scheduled_by FROM hr_interview_schedules WHERE scheduled_by IS NOT NULL AND scheduled_by != '' ORDER BY scheduled_by ASC");
if ($iv_cr) while ($ivx = mysqli_fetch_assoc($iv_cr)) $iv_recruiters_list[] = $ivx['scheduled_by'];

// Cards for the "Follow-ups"-style overlay — same underlying data as the
// Interview Dashboard tables, just re-shown as cards on demand.
$iv_alert_cards = [];
foreach ($iv_today_rows as $ivr) {
    $sched_ts = strtotime($ivr['scheduled_datetime']);
    $is_offer_done = (($ivr['round_type'] ?? '') === 'offer' && ($ivr['hr_decision'] ?? '') === 'hired');
    if ($ivr['eval_id'] || $is_offer_done) continue; // completed — not something to follow up on
    $iv_alert_cards[] = ['row' => $ivr, 'kind' => ($sched_ts > time() ? 'today_upcoming' : 'today_missed')];
}
foreach ($iv_missed_rows as $ivr) {
    $iv_alert_cards[] = ['row' => $ivr, 'kind' => 'overdue'];
}
$iv_alert_count = count($iv_alert_cards);
?>
<div class="hdr">
  <div>
    <h1><i class="fas fa-user-check mr-2"></i>HR Candidate Screening</h1>
    <div class="sub">JD + Resume AI analysis &middot; <?php echo htmlspecialchars($current_user_name); ?></div>
  </div>
  <div style="display:flex;gap:9px;">
    <a href="hr_screening.php" class="btn-h btn-teal"><i class="fas fa-plus-circle"></i> Screen New Candidate</a>
    <a href="hr_candidate_tracking.php" class="btn-h" style="background:linear-gradient(135deg,#8b5cf6,#7c3aed);"><i class="fas fa-phone-alt"></i> Candidate Tracking</a>
    <a href="hr-employee-log.php" class="btn-h" style="background:linear-gradient(135deg,#10b981,#059669);"><i class="fas fa-user-check"></i> Marked as Employee</a>
    <a href="hr-rejected-candidates.php" class="btn-h" style="background:linear-gradient(135deg,#ef4444,#dc2626);"><i class="fas fa-user-times"></i> Rejection Log</a>

    
  </div>
</div>

<div class="wrap">

<?php if ($upload_success): ?>
<div class="alert-ok"><i class="fas fa-check-circle fa-lg"></i> Uploaded successfully! Candidate #<?php echo $new_sid; ?> created — run AI analysis below.</div>
<?php endif; ?>
<?php if ($upload_error): ?>
<div class="alert-err"><i class="fas fa-exclamation-circle fa-lg"></i> <?php echo htmlspecialchars($upload_error); ?></div>
<?php endif; ?>

<!-- Stats -->
<div class="stats-grid">
<?php
$stat_items = [
    [$stats['total']??0,       'Total Screened',     'fas fa-users',         'linear-gradient(135deg,#667eea,#764ba2)', ''],
    [$stats['eligible']??0,    'Eligible',           'fas fa-check-circle',  'linear-gradient(135deg,#10b981,#059669)', 'color:var(--success)'],
    [$stats['partial']??0,     'Partially Eligible', 'fas fa-adjust',        'linear-gradient(135deg,#f59e0b,#d97706)', 'color:var(--warn)'],
    [$stats['not_eligible']??0,'Not Eligible',       'fas fa-times-circle',  'linear-gradient(135deg,#ef4444,#dc2626)', 'color:var(--danger)'],
    [$stats['shortlisted']??0, 'Shortlisted',        'fas fa-star',          'linear-gradient(135deg,#3b82f6,#2563eb)', 'color:#2563eb'],
    [$stats['pending_ai']??0,  'Pending AI',         'fas fa-hourglass-half','linear-gradient(135deg,#6366f1,#4f46e5)', 'color:#4f46e5'],
];
foreach ($stat_items as $si):
?>
<div class="stat-box">
  <div class="stat-ico" style="background:<?php echo $si[3]; ?>;color:#fff;"><i class="<?php echo $si[2]; ?>"></i></div>
  <div><div class="stat-val" style="<?php echo $si[4]; ?>"><?php echo $si[0]; ?></div><div class="stat-lbl"><?php echo $si[1]; ?></div></div>
</div>
<?php endforeach; ?>
</div>

<?php if ($iv_alert_count > 0): ?>
<div class="alert-banner" onclick="$('#interviewAlertModal').modal('show')">
    <i class="fas fa-bell"></i>
    <span><?php echo $iv_alert_count; ?> interview<?php echo $iv_alert_count > 1 ? 's' : ''; ?> need attention (today + overdue)</span>
    <span class="count-pill"><?php echo $iv_alert_count; ?> pending</span>
    <span style="margin-left:auto;font-size:13px;opacity:.85;"><i class="fas fa-eye mr-1"></i>Click to view</span>
</div>
<?php endif; ?>

<!-- Interview Detail Overlay (kept for potential future re-use; no longer triggered
     now that the dashboard tables were removed in favor of the banner+card overlay) -->
<div class="modal fade" id="interviewDetailModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <div class="modal-header">
      <h4><i class="fas fa-calendar-check mr-2"></i>Interview Detail</h4>
      <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" id="interviewDetailBody" style="padding:24px;"></div>
    <div class="modal-footer" id="interviewDetailFooter" style="padding:16px 24px;border-top:1px solid var(--border);"></div>
  </div></div>
</div>
<script>
function showInterviewDetail(tr) {
    var raw = tr.getAttribute('data-detail');
    if (!raw) return;
    var d = JSON.parse(raw);
    function row(label, value) {
        return '<div style="display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #f1f5f9;">' +
            '<span style="font-size:12px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.3px;">' + label + '</span>' +
            '<span style="font-size:13px;font-weight:700;color:var(--navy);text-align:right;">' + value + '</span></div>';
    }
    var html = '<div style="text-align:center;margin-bottom:18px;">' +
        '<div style="width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:22px;margin:0 auto 10px;">' + d.candidate_name.charAt(0).toUpperCase() + '</div>' +
        '<div style="font-weight:800;color:var(--navy);font-size:16px;">' + d.candidate_name + '</div>' +
        '<span style="background:' + d.status_bg + ';color:' + d.status_col + ';padding:4px 14px;border-radius:20px;font-weight:800;font-size:11px;display:inline-block;margin-top:6px;">' + d.status + '</span>' +
        '</div>' +
        row('Round', 'Round ' + d.round) +
        row('Position Applied', d.position) +
        row('Department', d.department || '-') +
        row('Scheduled For', d.when) +
        row('Recruiter', d.recruiter);
    document.getElementById('interviewDetailBody').innerHTML = html;
    document.getElementById('interviewDetailFooter').innerHTML =
        '<button type="button" class="btn-h" style="background:#f1f5f9;color:var(--navy);" data-dismiss="modal">Close</button>' +
        '<a href="hr_screening.php?view_candidate=' + d.screening_id + '" class="btn-h btn-teal"><i class="fas fa-user mr-1"></i> Open Candidate</a>';
    $('#interviewDetailModal').modal('show');
}
</script>

<!-- =====================================================================
     MODAL: Interview Follow-ups (cards) — same data as the Interview
     Dashboard tables above, shown as cards, matching hr_candidate_tracking.php's
     "Upcoming Follow-ups" pattern.
===================================================================== -->
<div class="modal fade" id="interviewAlertModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f97316,#ea580c);">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-bell mr-2"></i>Interview Follow-ups — Today &amp; Overdue</h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <?php if (empty($iv_alert_cards)): ?>
        <div style="text-align:center;padding:40px;color:var(--muted);">
            <i class="fas fa-check-circle fa-3x" style="margin-bottom:14px;opacity:.3;"></i>
            <p>No interviews need attention right now.</p>
        </div>
        <?php else: ?>
        <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px;background:#f8fafc;border-radius:10px;padding:12px 16px;">
            <input type="date" id="ivAlertDateFrom" class="fc" style="width:150px;" title="From date">
            <input type="date" id="ivAlertDateTo" class="fc" style="width:150px;" title="To date">
            <select id="ivAlertRoundFilter" class="fc" style="width:140px;">
                <option value="">All Rounds</option>
                <?php foreach ($iv_rounds_list as $rn): ?>
                <option value="<?php echo $rn; ?>">Round <?php echo $rn; ?></option>
                <?php endforeach; ?>
            </select>
            <select id="ivAlertPositionFilter" class="fc" style="width:190px;">
                <option value="">All Positions</option>
                <?php foreach ($iv_positions_list as $pos): ?>
                <option value="<?php echo htmlspecialchars($pos); ?>"><?php echo htmlspecialchars($pos); ?></option>
                <?php endforeach; ?>
            </select>
            <select id="ivAlertStatusFilter" class="fc" style="width:160px;">
                <option value="">All Statuses</option>
                <option value="today_upcoming">Scheduled (Today)</option>
                <option value="today_missed">Missed Today</option>
                <option value="overdue">Overdue</option>
            </select>
            <button type="button" onclick="ivApplyAlertFilter()" style="padding:9px 16px;border:none;border-radius:8px;background:#f97316;color:#fff;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-filter mr-1"></i>Filter</button>
            <button type="button" onclick="ivResetAlertFilter()" style="padding:9px 16px;border:1px solid #e2e8f0;border-radius:8px;background:#fff;color:#475569;font-weight:700;font-size:12px;cursor:pointer;">Reset</button>
        </div>
        <div id="ivAlertCardsContainer">
        <?php foreach ($iv_alert_cards as $card):
            $ivr = $card['row'];
            $kind = $card['kind'];
            if ($kind === 'today_upcoming') { $sc = '#1e40af'; $badge_txt = 'Scheduled'; $time_txt = date('h:i A', strtotime($ivr['scheduled_datetime'])) . ' — <strong>TODAY</strong>'; $time_col = '#10b981'; }
            elseif ($kind === 'today_missed') { $sc = '#991b1b'; $badge_txt = 'Missed Today'; $time_txt = date('h:i A', strtotime($ivr['scheduled_datetime'])) . ' — <strong>MISSED</strong>'; $time_col = '#ef4444'; }
            else { $sc = '#991b1b'; $days_od = floor((time() - strtotime($ivr['scheduled_datetime'])) / 86400); $badge_txt = $days_od <= 0 ? 'Missed Today' : ($days_od . 'd Overdue'); $time_txt = date('d M Y, h:i A', strtotime($ivr['scheduled_datetime'])) . ' — <strong>OVERDUE</strong>'; $time_col = '#ef4444'; }
            $round_num = intval($ivr['round_number']);
            $round_colors = ['#7c3aed','#2563eb','#0891b2','#d97706','#059669','#db2777'];
            $round_col = $round_colors[($round_num - 1 + count($round_colors)) % count($round_colors)];
        ?>
        <?php
            $ivr_phone_clean = preg_replace('/[^0-9]/', '', $ivr['candidate_phone'] ?? '');
            if (strlen($ivr_phone_clean) === 10) $ivr_phone_clean = '91' . $ivr_phone_clean;
            $ivr_ctx = json_encode([
                'id'          => $ivr['screening_id'],
                'name'        => $ivr['candidate_name'],
                'phone'       => $ivr['candidate_phone'] ?? '',
                'phone_clean' => $ivr_phone_clean,
                'email'       => $ivr['candidate_email'] ?? '',
                'status'      => $badge_txt,
                'tdt'         => date('d M Y, h:i A', strtotime($ivr['scheduled_datetime'])),
                'department'  => $ivr['department'] ?? '',
                'position'    => $ivr['position_applied'] ?? '',
            ]);
        ?>
        <div class="alert-card-item"
            data-round="<?php echo $round_num; ?>"
            data-position="<?php echo htmlspecialchars($ivr['position_applied']); ?>"
            data-status="<?php echo $kind; ?>"
            data-tdate="<?php echo date('Y-m-d', strtotime($ivr['scheduled_datetime'])); ?>"
            style="border-left:4px solid <?php echo $sc; ?>;">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:14px;flex-wrap:wrap;">
                <div>
                    <div style="font-weight:700;font-size:15px;color:var(--navy);"><?php echo htmlspecialchars($ivr['candidate_name']); ?></div>
                    <div style="font-size:12px;color:var(--muted);margin-top:3px;">
                        <i class="fas fa-layer-group mr-1" style="color:<?php echo $round_col; ?>;"></i><span style="color:<?php echo $round_col; ?>;font-weight:800;">Round <?php echo $round_num; ?></span>
                        &nbsp;|&nbsp;<i class="fas fa-briefcase mr-1"></i><?php echo htmlspecialchars($ivr['position_applied']); ?>
                        &nbsp;|&nbsp;<i class="fas fa-building mr-1"></i><?php echo htmlspecialchars($ivr['department']); ?>
                        <?php if (!empty($ivr['scheduled_by'])): ?>&nbsp;|&nbsp;<i class="fas fa-user-tie mr-1"></i><?php echo htmlspecialchars($ivr['scheduled_by']); ?><?php endif; ?>
                    </div>
                </div>
                <div style="text-align:right;flex-shrink:0;">
                    <span class="status-badge" style="background:<?php echo $sc; ?>;color:#fff;padding:4px 12px;border-radius:20px;font-weight:800;font-size:11px;margin-bottom:7px;display:inline-block;"><?php echo htmlspecialchars($badge_txt); ?></span><br>
                    <span style="font-size:12px;font-weight:700;color:<?php echo $time_col; ?>;"><i class="fas fa-clock mr-1"></i><?php echo $time_txt; ?></span>
                </div>
            </div>
            <div style="display:flex;gap:8px;margin-top:12px;padding-top:10px;border-top:1px dashed #e2e8f0;">
                <a href="hr_screening.php?view_candidate=<?php echo intval($ivr['screening_id']); ?>" style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;text-decoration:none;">
                    <i class="fas fa-user"></i> Open Candidate
                </a>
                <button type="button"
                    data-ctx='<?php echo htmlspecialchars($ivr_ctx, ENT_QUOTES); ?>'
                    onclick="openTemplatePicker(JSON.parse(this.dataset.ctx))"
                    style="flex:1;padding:8px 12px;border:none;border-radius:8px;background:linear-gradient(135deg,#16a34a,#22c55e);color:#fff;font-weight:700;font-size:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:6px;">
                    <i class="fas fa-paper-plane"></i> Notify Candidate
                </button>
            </div>
        </div>
        <?php endforeach; ?>
        </div>
        <?php endif; ?>
    </div>
</div>
</div>
</div>

<!-- =====================================================================
     MODAL: TEMPLATE PICKER (shared templates with hr_candidate_tracking.php)
===================================================================== -->
<div class="modal fade" id="templatePickerModal" tabindex="-1">
<div class="modal-dialog modal-lg">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#f59e0b,#d97706);">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-comment-dots mr-2"></i>Choose a Message Template — <span id="tpl_pick_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <div style="position:relative;margin-bottom:16px;">
            <i class="fas fa-search" style="position:absolute;left:14px;top:50%;transform:translateY(-50%);color:var(--muted);"></i>
            <input type="text" id="tplSearchInput" class="fc" style="padding-left:38px;" placeholder="Search templates by name, status, or keyword…">
        </div>
        <div id="tplPickerList" style="max-height:420px;overflow-y:auto;"></div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
    </div>
</div></div></div>

<!-- =====================================================================
     MODAL: NOTIFY CANDIDATE (Email + WhatsApp)
===================================================================== -->
<div class="modal fade" id="notifyModal" tabindex="-1">
<div class="modal-dialog modal-lg modal-dialog-scrollable">
<div class="modal-content">
    <div class="modal-header" style="background:linear-gradient(135deg,#16a34a,#22c55e);">
        <h5 class="modal-title" style="color:#fff;"><i class="fas fa-paper-plane mr-2"></i>Notify Candidate — <span id="notify_cname"></span></h5>
        <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
    </div>
    <div class="modal-body">
        <p style="font-size:13px;color:var(--muted);margin-bottom:14px;">
            <i class="fas fa-info-circle mr-1"></i>
            Review and edit the messages below before sending via Email or WhatsApp.
        </p>
        <input type="hidden" id="notify_name_hidden">
        <input type="hidden" id="notify_tdt_hidden">
        <div class="fg" style="margin-bottom:18px;max-width:280px;">
            <label class="fl">Sender Name <span style="font-weight:400;color:var(--muted);">(shown in "Regards," — auto-filled, editable)</span></label>
            <input type="text" id="notify_sender_name" class="fc" oninput="regenerateNotifyMessages()">
        </div>

        <div id="saveAsTemplateBox" style="display:none;background:#fffbeb;border:1px solid #fde68a;border-radius:10px;padding:14px 16px;margin-bottom:18px;">
            <label style="font-weight:700;font-size:13px;color:#92400e;cursor:pointer;display:flex;align-items:center;gap:8px;">
                <input type="checkbox" id="saveAsTemplateCheck" onchange="document.getElementById('saveAsTemplateFields').style.display=this.checked?'block':'none';">
                Save this message as a reusable template for next time
            </label>
            <div id="saveAsTemplateFields" style="display:none;margin-top:10px;">
                <label class="fl">Template Title</label>
                <input type="text" id="saveAsTemplateTitle" class="fc" placeholder="e.g. Custom Reminder">
                <small style="color:var(--muted);font-size:11.5px;display:block;margin-top:6px;">Saved with whatever text you actually send below — swap in specific names/dates for placeholders like <code>{name}</code> first if you want it reusable. It will be tagged with this candidate's current status (<span id="saveAsTemplateStatusLabel"></span>).</small>
            </div>
        </div>

        <!-- Email Section -->
        <div style="background:#eff6ff;border-radius:12px;padding:20px;margin-bottom:18px;border:1px solid #bfdbfe;">
            <div style="font-weight:700;font-size:14px;color:#1d4ed8;margin-bottom:14px;">
                <i class="fas fa-envelope mr-2"></i>Send via Email
            </div>
            <div class="fg"><label class="fl">To (Email Address)</label><input type="email" id="notify_email_to" class="fc" placeholder="candidate@email.com"></div>
            <div class="fg"><label class="fl">Subject</label><input type="text" id="notify_email_subject" class="fc"></div>
            <div class="fg"><label class="fl">Email Body (Plain Text)</label><textarea id="notify_email_body" class="fc" rows="6" style="resize:vertical;height:140px;"></textarea></div>
            <button type="button" onclick="sendNotifyEmail()" style="padding:10px 22px;border:none;border-radius:9px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;font-weight:700;font-size:13px;cursor:pointer;">
                <i class="fas fa-paper-plane mr-2"></i>Send Email
            </button>
            <span id="notify_email_status" style="font-size:12px;margin-left:12px;"></span>
        </div>

        <!-- WhatsApp Section -->
        <div style="background:#f0fdf4;border-radius:12px;padding:20px;border:1px solid #bbf7d0;">
            <div style="font-weight:700;font-size:14px;color:#15803d;margin-bottom:14px;">
                <i class="fab fa-whatsapp mr-2"></i>Send via WhatsApp
            </div>
            <div class="fg"><label class="fl">WhatsApp Message</label><textarea id="notify_wa_body" class="fc" rows="6" style="resize:vertical;height:140px;"></textarea></div>
            <div style="font-size:13px;color:var(--muted);margin-bottom:12px;">
                <i class="fas fa-phone mr-1"></i> Sending to: <strong id="notify_wa_phone_display"></strong>
            </div>
            <a id="notify_wa_link" href="#" target="_blank"
                onclick="updateWALink()"
                style="display:inline-block;padding:10px 22px;border-radius:9px;background:linear-gradient(135deg,#16a34a,#22c55e);color:#fff;font-weight:700;font-size:13px;text-decoration:none;">
                <i class="fab fa-whatsapp mr-2"></i>Open WhatsApp
            </a>
        </div>
    </div>
    <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
    </div>
</div></div></div>

<script>
// ── Template-driven Notify system (shared hr_message_templates table with hr_candidate_tracking.php) ──
var COMPANY_NAME = <?php echo json_encode(isset($_SESSION['ge_cname']) ? trim($_SESSION['ge_cname']) : 'Company'); ?>;
var HR_NAME      = <?php echo json_encode($current_user_name); ?>;
var _notifyWAPhone         = '';
var _notifyCtx              = null;
var _currentRawTemplateBody = '';
var _isCustomFlow           = false;
var _templatesCache         = null;

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function capitalizeFirst(str) {
    if (!str) return str;
    str = str.trim();
    return str.charAt(0).toUpperCase() + str.slice(1);
}
function splitDateTime(tdt) {
    if (!tdt) return { date: 'Not yet scheduled', time: '' };
    var parts = tdt.split(',');
    if (parts.length >= 2) return { date: parts[0].trim(), time: parts.slice(1).join(',').trim() };
    return { date: tdt, time: '' };
}
function buildReminderMsg(name, status, tdt, senderName) {
    var dt = splitDateTime(tdt);
    var sender = capitalizeFirst(senderName || HR_NAME);
    return 'Hi ' + name + ',\n\n' +
        'Greetings from ' + COMPANY_NAME + '.\n' +
        'This is a friendly reminder regarding your interview.\n\n' +
        'Scheduled for:\n' +
        'Date: ' + dt.date + '\n' +
        'Time: ' + dt.time + '\n\n' +
        'Kindly ensure that you are available at the scheduled time. If you are unavailable, please let us know in advance.\n\n' +
        'We look forward to speaking with you.\n\n' +
        'Regards,\n' + sender + '\n' +
        'HR Team\n' +
        COMPANY_NAME;
}
function fillPlaceholders(text, ctx, senderOverride) {
    var dt = splitDateTime(ctx.tdt);
    var sender = capitalizeFirst(senderOverride || HR_NAME);
    return String(text || '')
        .replace(/\{name\}/gi, ctx.name || '')
        .replace(/\{position\}/gi, ctx.position || '—')
        .replace(/\{department\}/gi, ctx.department || '—')
        .replace(/\{company\}/gi, COMPANY_NAME || '')
        .replace(/\{date\}/gi, dt.date || '')
        .replace(/\{time\}/gi, dt.time || '')
        .replace(/\{phone\}/gi, ctx.phone || '')
        .replace(/\{sender\}/gi, sender);
}
function loadTemplatesCache(callback) {
    if (_templatesCache) { callback(_templatesCache); return; }
    fetch('hr_screening.php?get_templates=1')
        .then(function(r) { return r.json(); })
        .then(function(data) { _templatesCache = data; callback(data); });
}
function openTemplatePicker(ctx) {
    _notifyCtx = ctx;
    document.getElementById('tpl_pick_cname').textContent = ctx.name;
    document.getElementById('tplSearchInput').value = '';
    $('#interviewAlertModal').modal('hide');
    setTimeout(function() {
        $('#templatePickerModal').modal('show');
        _templatesCache = null;
        loadTemplatesCache(function() { renderTemplatePickerList(''); });
    }, 250);
}
function renderTemplatePickerList(filterText) {
    var listEl = document.getElementById('tplPickerList');
    var q = (filterText || '').toLowerCase().trim();
    var templates = (_templatesCache || []).filter(function(t) {
        if (!q) return true;
        var hay = (t.title + ' ' + t.statuses.join(' ') + ' ' + t.body).toLowerCase();
        return hay.indexOf(q) !== -1;
    });
    var html = '';
    html += '<div onclick="pickCustomTemplate()" style="cursor:pointer;background:#fffbeb;border:2px dashed #fbbf24;border-radius:10px;padding:14px 16px;margin-bottom:12px;">' +
        '<div style="font-weight:700;color:#92400e;"><i class="fas fa-pen mr-2"></i>Other — Type your own message</div>' +
        '<div style="font-size:12px;color:#92400e;opacity:.8;margin-top:3px;">Skip templates and write a custom message for this candidate.</div>' +
        '</div>';
    if (!templates.length) {
        if (q) html += '<div style="text-align:center;padding:24px;color:var(--muted);">No templates match "' + escHtml(filterText) + '".</div>';
        else html += '<div style="text-align:center;padding:24px;color:var(--muted);">No templates yet — pick "Other" above to write one, or manage templates from Candidate Tracking.</div>';
    } else {
        templates.forEach(function(t) {
            var preview = t.body.length > 110 ? t.body.substring(0,110) + '…' : t.body;
            var badges = t.statuses.map(function(s) {
                return '<span style="background:#6366f1;color:#fff;font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;margin-right:4px;">' + escHtml(s) + '</span>';
            }).join('');
            html += '<div onclick=\'pickTemplate(' + t.id + ')\' style="cursor:pointer;background:#f8fafc;border:2px solid var(--border);border-radius:10px;padding:14px 16px;margin-bottom:10px;">' +
                '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;">' +
                '<div style="font-weight:700;color:var(--navy);">' + escHtml(t.title) + '</div>' +
                '<div>' + badges + '</div>' +
                '</div>' +
                '<div style="font-size:12.5px;color:var(--muted);margin-top:6px;white-space:pre-wrap;">' + escHtml(preview) + '</div>' +
                '</div>';
        });
    }
    listEl.innerHTML = html;
}
document.getElementById('tplSearchInput') && document.getElementById('tplSearchInput').addEventListener('input', function() {
    renderTemplatePickerList(this.value);
});
function pickTemplate(id) {
    var tpl = (_templatesCache || []).find(function(t) { return t.id == id; });
    if (!tpl) return;
    _isCustomFlow = false;
    $('#templatePickerModal').modal('hide');
    setTimeout(function() { showNotifyModal(tpl.body, false); }, 300);
}
function pickCustomTemplate() {
    _isCustomFlow = true;
    var defaultBody = buildReminderMsg(_notifyCtx.name, _notifyCtx.status, _notifyCtx.tdt, HR_NAME);
    $('#templatePickerModal').modal('hide');
    setTimeout(function() { showNotifyModal(defaultBody, true); }, 300);
}
function showNotifyModal(rawBody, isCustom) {
    var ctx = _notifyCtx;
    _notifyWAPhone = ctx.phone_clean || ctx.phone;
    _currentRawTemplateBody = rawBody;

    document.getElementById('notify_cname').textContent = ctx.name;
    document.getElementById('notify_email_to').value    = ctx.email || '';
    document.getElementById('notify_email_subject').value = 'Message from ' + COMPANY_NAME + ' HR';
    document.getElementById('notify_sender_name').value = capitalizeFirst(HR_NAME);
    document.getElementById('notify_name_hidden').value = ctx.name;
    document.getElementById('notify_tdt_hidden').value  = ctx.tdt;

    var msg = fillPlaceholders(rawBody, ctx, HR_NAME);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    document.getElementById('notify_wa_phone_display').textContent = ctx.phone;
    document.getElementById('notify_email_status').textContent = '';

    var saveBox = document.getElementById('saveAsTemplateBox');
    if (isCustom) {
        saveBox.style.display = 'block';
        document.getElementById('saveAsTemplateCheck').checked = false;
        document.getElementById('saveAsTemplateFields').style.display = 'none';
        document.getElementById('saveAsTemplateTitle').value = '';
        document.getElementById('saveAsTemplateStatusLabel').textContent = ctx.status;
    } else {
        saveBox.style.display = 'none';
    }

    updateWALink();
    $('#notifyModal').modal('show');
}
function regenerateNotifyMessages() {
    var sender = document.getElementById('notify_sender_name').value;
    var msg = fillPlaceholders(_currentRawTemplateBody, _notifyCtx, sender);
    document.getElementById('notify_email_body').value = msg;
    document.getElementById('notify_wa_body').value    = msg;
    updateWALink();
}
function updateWALink() {
    var msg = document.getElementById('notify_wa_body').value;
    var waUrl = 'https://wa.me/' + _notifyWAPhone + '?text=' + encodeURIComponent(msg);
    document.getElementById('notify_wa_link').href = waUrl;
}
document.getElementById('notify_wa_body') && document.getElementById('notify_wa_body').addEventListener('input', updateWALink);
function maybeSaveAsTemplate(sentBody) {
    if (!_isCustomFlow) return;
    var check = document.getElementById('saveAsTemplateCheck');
    if (!check || !check.checked) return;
    var title = document.getElementById('saveAsTemplateTitle').value.trim();
    if (!title) { showHrAlert('Please enter a template title to save it.', 'warn'); return; }

    var fd = new FormData();
    fd.append('action', 'save_template');
    fd.append('title', title);
    fd.append('body', sentBody);
    fd.append('statuses[]', _notifyCtx.status);

    fetch('hr_screening.php', { method: 'POST', body: fd })
        .then(function(r) { return r.json(); })
        .then(function(res) {
            if (res.success) {
                _templatesCache = null;
                check.checked = false;
            }
        });
}
function sendNotifyEmail() {
    var to      = document.getElementById('notify_email_to').value.trim();
    var subject = document.getElementById('notify_email_subject').value.trim();
    var body    = document.getElementById('notify_email_body').value.trim();
    var statusEl = document.getElementById('notify_email_status');
    if (!to) { showHrAlert('Please enter the candidate email address.', 'warn'); return; }
    var mailtoUrl = 'mailto:' + encodeURIComponent(to)
        + '?subject=' + encodeURIComponent(subject)
        + '&body=' + encodeURIComponent(body);
    window.open(mailtoUrl, '_blank');
    statusEl.textContent = 'Email client opened!';
    statusEl.style.color = 'var(--success)';
    maybeSaveAsTemplate(body);
}
</script>
<script>
function ivApplyAlertFilter() {
    var from = document.getElementById('ivAlertDateFrom').value;
    var to   = document.getElementById('ivAlertDateTo').value;
    var round = document.getElementById('ivAlertRoundFilter').value;
    var position = document.getElementById('ivAlertPositionFilter').value;
    var status = document.getElementById('ivAlertStatusFilter').value;
    document.querySelectorAll('#ivAlertCardsContainer .alert-card-item').forEach(function(card) {
        var show = true;
        if (from && card.dataset.tdate < from) show = false;
        if (to   && card.dataset.tdate > to)   show = false;
        if (round && card.dataset.round !== round) show = false;
        if (position && card.dataset.position !== position) show = false;
        if (status && card.dataset.status !== status) show = false;
        card.style.display = show ? '' : 'none';
    });
}
function ivResetAlertFilter() {
    document.getElementById('ivAlertDateFrom').value = '';
    document.getElementById('ivAlertDateTo').value = '';
    document.getElementById('ivAlertRoundFilter').value = '';
    document.getElementById('ivAlertPositionFilter').value = '';
    document.getElementById('ivAlertStatusFilter').value = '';
    ivApplyAlertFilter();
}
</script>

<!-- Tabs -->
<div class="tab-bar">
  <button class="tab-btn active" id="tab-upload" onclick="switchTab('upload')"><i class="fas fa-cloud-upload-alt"></i> Upload JD &amp; Resume</button>
  <button class="tab-btn" id="tab-screening" onclick="switchTab('screening')"><i class="fas fa-list-check"></i> All Screenings
    <?php if(($stats['total']??0)>0): ?>
    <span style="background:#ef4444;color:#fff;border-radius:99px;padding:1px 7px;font-size:11px;font-weight:800;"><?php echo $stats['total']; ?></span>
    <?php endif; ?>
  </button>
</div>

<style>
@media (max-width: 900px) {
  .upload-grid { grid-template-columns: 1fr !important; }
}
</style>
<div class="tab-pane active" id="pane-upload">
<div class="upload-grid" style="display:grid;grid-template-columns:1fr 1fr;gap:22px;">

    <!-- Left: Single unified form card -->
    <div class="form-sec">
      <form method="POST" enctype="multipart/form-data" id="screenForm">
        <input type="hidden" name="submit_resume" value="1">

        <div class="sec-lbl"><i class="fas fa-user"></i> Candidate Details</div>
        <div class="fg"><label class="fl">Full Name *</label><input type="text" name="candidate_name" class="fc" required value="<?php echo htmlspecialchars($cand_info['candidate_name'] ?? ''); ?>" placeholder="e.g. Ravi Kumar"></div>
        <div class="row2">
          <div class="fg"><label class="fl">Phone</label><input type="text" name="candidate_phone" class="fc" value="<?php echo htmlspecialchars($cand_info['candidate_phone'] ?? ''); ?>" placeholder="Mobile number"></div>
          <div class="fg"><label class="fl">Email</label><input type="email" name="candidate_email" class="fc" value="<?php echo htmlspecialchars($cand_info['candidate_email'] ?? ''); ?>" placeholder="email@example.com"></div>
        </div>
        <div class="fg">
  <label class="fl">Company *</label>
  <select name="company_id" class="fc" id="companySelect" required>
    <option value="">Select Company...</option>
    <?php foreach ($companies_list as $co): ?>
    <option value="<?php echo $co['id']; ?>" 
      <?php echo (isset($cand_info['company_id']) && $cand_info['company_id'] == $co['id']) ? 'selected' : ''; ?>>
      <?php echo htmlspecialchars($co['company_name']); ?>
    </option>
    <?php endforeach; ?>
  </select>
</div>
        <div class="fg">
          <label class="fl">Department *</label>
          <select name="department" class="fc" id="deptSelect" onchange="loadPositionsForDept(this.value)" required>
            <option value="">Select Department...</option>
            <?php foreach($depts as $d): ?>
              <option value="<?php echo htmlspecialchars($d); ?>" <?php echo (isset($cand_info['department']) && $cand_info['department'] === $d) ? 'selected' : ''; ?>><?php echo htmlspecialchars($d); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="fg">
          <label class="fl">Position Applied For *</label>
          <select name="position_id" class="fc" id="posSelect" onchange="updatePosName()" required>
            <option value="">Select Position...</option>
            <?php if(!empty($cand_info['position_id'])):
              $cand_pos_row = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=" . intval($cand_info['position_id']) . " LIMIT 1"));
              $cand_pos_category = $cand_pos_row['worker_category'] ?? 'professional';
            ?>
              <option value="<?php echo intval($cand_info['position_id']); ?>" data-category="<?php echo htmlspecialchars($cand_pos_category); ?>" selected><?php echo htmlspecialchars($cand_info['position_applied']); ?></option>
            <?php endif; ?>
          </select>
          <input type="hidden" name="position_applied" id="posNameInput" value="<?php echo htmlspecialchars($cand_info['position_applied'] ?? ''); ?>">
        </div>

        <div class="fg" id="posCategoryWrap">
          <label class="fl">Category</label>
          <select class="fc" id="posCategorySelect" onchange="savePositionCategoryFromScreening()" disabled>
            <option value="professional">Professional</option>
            <option value="blue_collar">Blue Collar</option>
          </select>
          <p style="font-size:11px;color:var(--muted);margin-top:4px;">This sets the classification for the <strong>position</strong> — it applies to every candidate applying to it, not just this one.</p>
        </div>

        <div id="blueCollarNotice" style="display:none;margin-top:14px;padding:9px 12px;background:#eef2ff;border:1px solid #c7d2fe;border-radius:7px;font-size:11px;color:#3730a3;">
          <i class="fas fa-info-circle"></i> Blue Collar role selected — Resume, JD, and AI scoring are optional. You can add this candidate straight into interview rounds.
        </div>

        <div style="border-top:1px solid var(--border);margin-top:18px;padding-top:18px;">
          <div class="sec-lbl" id="jdSecLbl"><i class="fas fa-file-contract"></i> Job Description (JD) *</div>
          <?php if ($upload_success && $new_sid): ?>
            <div class="file-ok" style="display:flex;margin-bottom:16px;"><i class="fas fa-check-circle"></i> Uploaded: <?php echo htmlspecialchars($cand_info['jd_filename'] ?: 'No JD uploaded'); ?></div>
          <?php else: ?>
            <div class="upzone jdz" id="jdZone">
              <input type="file" name="jd_file" id="jdFile" accept=".pdf,.doc,.docx,.txt" required onchange="showFile(this,'jdLbl','jdOk','jdOkName')">
              <div class="uico" style="color:#6366f1;"><i class="fas fa-file-contract"></i></div>
              <div class="utxt" id="jdLbl">Upload Job Description</div>
              <div class="usub" id="jdReqLbl">PDF, DOC, DOCX, TXT &middot; Required</div>
            </div>
            <div class="file-ok" id="jdOk"><i class="fas fa-check-circle"></i><span id="jdOkName"></span></div>
            <p id="jdReqNote" style="font-size:11px;color:var(--muted);margin:7px 0 16px;padding:9px 12px;background:#f5f3ff;border-radius:7px;border:1px solid #ede9fe;">
              <i class="fas fa-info-circle" style="color:#6366f1;"></i> Uploading the JD is required so the AI has the exact requirements to score against.
            </p>
          <?php endif; ?>
        </div>

        <div style="border-top:1px solid var(--border);margin-top:4px;padding-top:18px;">
          <div class="sec-lbl" id="resumeSecLbl"><i class="fas fa-file-alt"></i> Candidate Resume *</div>
          <?php if ($upload_success && $new_sid): ?>
            <div class="file-ok" style="display:flex;margin-bottom:16px;"><i class="fas fa-check-circle"></i> Uploaded: <?php echo htmlspecialchars($cand_info['resume_filename'] ?? ''); ?></div>
          <?php else: ?>
            <div class="upzone" id="resumeZone">
              <input type="file" name="resume_file" id="resumeFile" accept=".pdf,.doc,.docx,.txt" required onchange="showFile(this,'resumeLbl','resumeOk','resumeOkName')">
              <div class="uico" style="color:var(--blue);"><i class="fas fa-file-upload"></i></div>
              <div class="utxt" id="resumeLbl">Upload Candidate Resume</div>
              <div class="usub" id="resumeReqLbl">PDF, DOC, DOCX, TXT &middot; Required</div>
            </div>
            <div class="file-ok" id="resumeOk"><i class="fas fa-check-circle"></i><span id="resumeOkName"></span></div>
            <button type="submit" class="btn-sub mt-3" id="submitBtn"><i class="fas fa-brain"></i> Upload &amp; Analyze Candidate</button>
          <?php endif; ?>
        </div>

      </form>
    </div>

    <!-- Right panel -->
    <div>
      <?php if (isset($_GET['review']) && isset($_SESSION['review_candidate'])): ?>
      <div class="form-sec" id="analyzeBox">
        <div class="sec-lbl" style="display:flex;justify-content:space-between;">
            <span><i class="fas fa-robot"></i> AI Analysis Ready</span>
            <span class="badge-s b-highly" style="font-size:11px;">Preview Mode</span>
        </div>
        
        <div id="aiResultBox_preview" style="margin-top:14px;"></div>
        
        <form method="POST" action="hr_screening.php" id="saveCandidateForm" style="margin-top:20px;padding-top:20px;border-top:1px solid var(--border);">
            <?php if ($can_override): ?>
            <div class="fg">
                <label class="fl">Manager Override Score (Optional)</label>
                <input type="number" name="hr_override_score" class="fc" placeholder="e.g. 90" min="0" max="100">
                <p style="font-size:11px;color:var(--muted);margin-top:4px;">If you disagree with the AI score, enter your manual score here.</p>
            </div>
            <?php endif; ?>
            <input type="hidden" name="ajax_save_candidate" value="1">
            <div style="display:flex;gap:10px;">
                <button type="submit" class="btn-sub" style="flex:1;background:linear-gradient(135deg,var(--success),#059669);"><i class="fas fa-check-circle"></i> Add Candidate to Database</button>
                <a href="hr_screening.php" class="btn-sub" style="flex:1;background:#fff;border:1px solid #fee2e2;color:#ef4444;text-decoration:none;display:flex;align-items:center;justify-content:center;"><i class="fas fa-times-circle mr-1"></i> Discard</a>
            </div>
        </form>

        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var container = document.getElementById('aiResultBox_preview');
            var data = <?php echo json_encode($_SESSION['review_candidate']['ai_results']); ?>;
            renderAIResult(data, data.eligibility_score, container);
        });
        </script>
      </div>
      <?php elseif ($upload_success && $new_sid): ?>
      <div class="form-sec" id="analyzeBox">
        <div class="sec-lbl"><i class="fas fa-check-circle"></i> Candidate Saved Successfully</div>
        <div style="text-align:center;padding:22px 0;">
          <div style="width:68px;height:68px;background:linear-gradient(135deg,var(--success),#059669);border-radius:16px;display:inline-flex;align-items:center;justify-content:center;font-size:30px;color:#fff;margin-bottom:12px;"><i class="fas fa-user-check"></i></div>
          <h5 style="color:var(--navy);font-weight:800;margin-bottom:6px;">Candidate #<?php echo $new_sid; ?> Added!</h5>
          <p style="color:var(--muted);font-size:13px;margin-bottom:18px;">The candidate has been formally entered into the database.</p>
        </div>
        
        <?php if (!empty($cand_info['ai_analysis'])): ?>
            <div id="aiResultBox_<?php echo $new_sid; ?>" style="margin-top:14px;"></div>
            <script>
            document.addEventListener('DOMContentLoaded', function() {
                var container = document.getElementById('aiResultBox_<?php echo $new_sid; ?>');
                var data = <?php echo $cand_info['ai_analysis']; ?>;
                renderAIResult(data, <?php echo $cand_info['eligibility_score']; ?>, container);
            });
            </script>
        <?php endif; ?>
      </div>
      <?php else: ?>
      <div class="form-sec">
        <div class="sec-lbl"><i class="fas fa-info-circle"></i> How It Works</div>
        <?php
        $steps = [
            ['fas fa-user',          'Step 1 — Candidate Details',  'Enter name, position, and department.'],
            ['fas fa-file-contract', 'Step 2 — Upload JD',          'Upload the Job Description. The AI compares the resume directly against it.'],
            ['fas fa-file-upload',   'Step 3 — Upload Resume',       'Upload the candidate resume in any readable format.'],
            ['fas fa-brain',         'Step 4 — Run Keyword Analysis',     'Keyword engine compares JD terms to resume and scores the match out of 100.'],
            ['fas fa-chart-pie',     'Step 5 — Review Report',       'See score, matched/missing skills, strengths, concerns, and interview questions.'],
            ['fas fa-gavel',         'Step 6 — HR Decision',         'Mark as Shortlisted, On Hold, Rejected, or Hired.'],
        ];
        foreach ($steps as $st):
        ?>
        <div style="display:flex;gap:12px;padding:12px;background:#f8faff;border-radius:11px;border:1px solid #e0e7ff;margin-bottom:9px;">
          <div style="width:36px;height:36px;border-radius:9px;background:linear-gradient(135deg,var(--navy),var(--blue));color:#fff;display:flex;align-items:center;justify-content:center;flex-shrink:0;"><i class="<?php echo $st[0]; ?>" style="font-size:14px;"></i></div>
          <div>
            <div style="font-weight:800;font-size:13px;color:var(--navy);"><?php echo $st[1]; ?></div>
            <div style="font-size:12px;color:var(--muted);margin-top:2px;"><?php echo $st[2]; ?></div>
          </div>
        </div>
        <?php endforeach; ?>

        <div style="margin-top:18px;background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:1px solid #86efac;border-radius:11px;padding:14px;">
          <div style="font-weight:800;font-size:11px;color:#065f46;margin-bottom:9px;text-transform:uppercase;letter-spacing:.5px;"><i class="fas fa-chart-bar mr-1"></i> AI Scoring Weights</div>
          <?php
          $scoring = [
              ['JD Requirements Match','45%','#10b981',45],
              ['Relevant Experience',  '25%','#3b82f6',25],
              ['Education Fit',        '15%','#8b5cf6',15],
              ['Resume Quality',       '10%','#f59e0b',10],
              ['Domain Signals',       '5%', '#06b6d4', 5],
          ];
          foreach ($scoring as $sc2):
          ?>
          <div style="display:flex;align-items:center;gap:9px;margin-bottom:6px;">
            <div style="font-size:12px;font-weight:700;color:#065f46;width:155px;"><?php echo $sc2[0]; ?></div>
            <div class="pbar-wrap"><div class="pbar-fill" style="width:<?php echo $sc2[3]; ?>%;background:<?php echo $sc2[2]; ?>;"></div></div>
            <div style="font-size:12px;font-weight:800;color:<?php echo $sc2[2]; ?>;width:32px;"><?php echo $sc2[1]; ?></div>
          </div>
          <?php endforeach; ?>
        </div>
      </div>
      <?php endif; ?>
    </div>

  </div>
</div>

<!-- TAB 2: ALL SCREENINGS -->
<div class="tab-pane" id="pane-screening">
  <div class="card-panel">
    <div class="card-head">
      <h5><i class="fas fa-list mr-2"></i>All Candidates</h5>
      <div class="filter-row">
        <select class="fc" id="filterStatus" style="width:155px;" onchange="applyFilter()">
          <option value="">All Status</option>
          <option value="pending">Pending AI</option>
          <option value="highly_eligible">Highly Eligible</option>
          <option value="eligible">Eligible</option>
          <option value="partially_eligible">Partially Eligible</option>
          <option value="not_eligible">Not Eligible</option>
        </select>
        <select class="fc" id="filterDept" style="width:160px;" onchange="applyFilter()">
          <option value="">All Departments</option>
          <?php foreach ($depts as $d): ?>
          <option value="<?php echo strtolower(htmlspecialchars($d)); ?>"><?php echo htmlspecialchars($d); ?></option>
          <?php endforeach; ?>
        </select>
        <input type="text" class="fc" id="filterName" style="width:155px;" placeholder="Search name..." onkeyup="applyFilter()">
        <button onclick="applyFilter()" style="padding:9px 15px;border-radius:9px;border:none;background:var(--blue);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-search mr-1"></i>Filter</button>
        <button onclick="exportCSV()" style="padding:9px 15px;border-radius:9px;border:none;background:var(--success);color:#fff;font-family:inherit;font-weight:700;font-size:12px;cursor:pointer;"><i class="fas fa-file-download mr-1"></i>Export</button>
      </div>
    </div>
    <div class="tbl-wrap">
      <table class="stbl" id="screeningTable">
        <thead>
          <tr>
            <th>#</th><th>Candidate</th><th>Company</th><th>Position</th><th>Department</th>
            <th>JD</th><th>AI Score</th><th>Eligibility & Stage</th><th>HR Decision</th>
            <th>Date</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
        <?php mysqli_data_seek($all_rows, 0); $sl_num = 1; while ($row = mysqli_fetch_assoc($all_rows)):
            $score  = $row['eligibility_score'] ?? null;
            $sc_col = ($score!==null) ? ($score>=75?'var(--success)':($score>=50?'var(--warn)':'var(--danger)')) : 'var(--muted)';
            $sm     = ['pending'=>'b-pending','eligible'=>'b-eligible','highly_eligible'=>'b-highly','partially_eligible'=>'b-partial','not_eligible'=>'b-not'];
            $dm     = ['pending'=>'b-pending','shortlisted'=>'b-shortlisted','rejected'=>'b-rejected','hired'=>'b-hired','on_hold'=>'b-partial'];
            $sc_cls = $sm[$row['eligibility_status']] ?? 'b-pending';
            $dc_cls = $dm[$row['hr_decision']] ?? 'b-pending';
            $init   = strtoupper(substr($row['candidate_name'],0,1).(strpos($row['candidate_name'],' ')!==false?substr($row['candidate_name'],strpos($row['candidate_name'],' ')+1,1):''));
            $hasJD  = !empty($row['jd_path']);
        ?>
        <tr id="row_<?php echo $row['id']; ?>" data-status="<?php echo $row['eligibility_status']; ?>" data-dept="<?php echo strtolower($row['department']); ?>" data-name="<?php echo strtolower(htmlspecialchars($row['candidate_name'])); ?>">
          <td style="font-weight:800;color:var(--muted);font-size:12px;"><?php echo $sl_num++; ?></td>
          <td>
            <div style="display:flex;align-items:center;gap:9px;">
              <div class="cav" style="width:34px;height:34px;border-radius:9px;font-size:13px;"><?php echo $init; ?></div>
              <div>
                <div style="font-weight:700;"><?php echo htmlspecialchars($row['candidate_name']); ?></div>
                <div style="font-size:11px;color:var(--muted);"><?php echo htmlspecialchars($row['candidate_email'] ?? '—'); ?></div>
              </div>
            </div>
          </td>
          <td style="font-size:12px;color:var(--navy);font-weight:600;"><i class="fas fa-building mr-1" style="color:var(--muted);font-size:10px;"></i><?php echo htmlspecialchars($companies_map[$row['company_id']] ?? '—'); ?></td>
<td style="font-weight:700;font-size:12px;"><?php echo htmlspecialchars($row['position_applied']); ?></td>
          <td style="font-size:12px;"><?php echo htmlspecialchars($row['department']); ?></td>
          <td>
            <?php if ($hasJD): ?>
            <span class="badge-s" style="background:#ede9fe;color:#5b21b6;"><i class="fas fa-check mr-1"></i>Yes</span>
            <?php else: ?>
            <span class="badge-s b-pending">No JD</span>
            <?php endif; ?>
          </td>
          <td>
            <?php 
            $final_score = $score;
            $is_overridden = isset($row['hr_override_score']) && $row['hr_override_score'] !== null;
            if ($is_overridden) $final_score = floatval($row['hr_override_score']);
            
            if ($final_score !== null): 
                $sc_col = $final_score >= 75 ? 'var(--success)' : ($final_score >= 50 ? '#f59e0b' : 'var(--danger)');
            ?>
            <div style="display:flex;align-items:center;gap:7px;">
              <div class="pbar-wrap" style="width:50px;"><div class="pbar-fill" style="width:<?php echo $final_score; ?>%;background:<?php echo $sc_col; ?>;"></div></div>
              <span style="font-weight:800;font-size:13px;color:<?php echo $sc_col; ?>;"><?php echo round($final_score); ?>%</span>
              <?php if ($is_overridden): ?>
                <span style="font-size:9px;font-weight:800;background:#ede9fe;color:#5b21b6;padding:2px 4px;border-radius:4px;" title="Manually Adjusted by HR">HR</span>
              <?php endif; ?>
            </div>
            <?php else: ?><span style="color:var(--muted);font-size:11px;font-weight:600;">Not run</span><?php endif; ?>
          </td>
          <td>
            <span class="badge-s <?php echo $sc_cls; ?>"><?php echo str_replace('_',' ',ucfirst($row['eligibility_status'])); ?></span>
            <?php
            // Calling/Tracking status (only relevant once shortlisted)
            $calling_label = '';
            $calling_color = '#94a3b8';
            $calling_bg = '#f1f5f9';
            if ($row['hr_decision'] == 'shortlisted' || $row['hr_decision'] == 'hired') {
                $track_row_main = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT current_status FROM hr_candidate_tracking WHERE screening_id={$row['id']} LIMIT 1"));
                if ($track_row_main) {
                    $tc_map_main = [
                        'New'=>'#6366f1','Called'=>'#3b82f6','Interested'=>'#10b981','Not Interested'=>'#ef4444',
                        'Call Later'=>'#f59e0b','Callback'=>'#f97316','Scheduled'=>'#8b5cf6','Follow Up'=>'#06b6d4',
                        'No Response'=>'#94a3b8','Rejected'=>'#dc2626','Hired'=>'#059669'
                    ];
                    $calling_label = '📞 ' . htmlspecialchars($track_row_main['current_status']);
                    $calling_color = $tc_map_main[$track_row_main['current_status']] ?? '#6b7280';
                    $calling_bg = $calling_color . '22';
                } else {
                    $calling_label = '📞 Not Called Yet';
                    $calling_color = '#94a3b8';
                    $calling_bg = '#f1f5f9';
                }
            }

            // Find current round stage for this candidate
            $stage_label = 'Not Started';
            $stage_color = '#94a3b8';
            $stage_bg = '#f1f5f9';

            $latest_eval = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT round_number, status, percentage FROM hr_screening_evaluations WHERE screening_id={$row['id']} ORDER BY round_number DESC LIMIT 1"));
            if ($latest_eval) {
                $rn = intval($latest_eval['round_number']);
                $rs = $latest_eval['status'];
                $rp = floatval($latest_eval['percentage']);

                // Check if next round exists
                $dept_r = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT department, position_id FROM hr_screenings WHERE id={$row['id']} LIMIT 1"));
                $dept_id_r = 0;
                $pos_id_r = 0;
                if ($dept_r) {
                    $dn = mysqli_real_escape_string($dbConn, $dept_r['department']);
                    $dr = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT id FROM hr_departments WHERE name='$dn' LIMIT 1"));
                    if ($dr) $dept_id_r = $dr['id'];
                    $pos_id_r = intval($dept_r['position_id']);
                }
                $next_round_exists = mysqli_num_rows(mysqli_query($dbConn, "SELECT id FROM hr_screening_rounds WHERE department_id=$dept_id_r AND position_id=$pos_id_r AND round_number=".($rn+1)." LIMIT 1")) > 0;

                $is_bc_row = false;
                if ($pos_id_r > 0) {
                    $wc_row_r = mysqli_fetch_assoc(mysqli_query($dbConn, "SELECT worker_category FROM hr_positions WHERE id=$pos_id_r LIMIT 1"));
                    $is_bc_row = $wc_row_r && ($wc_row_r['worker_category'] === 'blue_collar');
                }

                if ($rs == 'Override' || $rp >= 90 || $is_bc_row) {
                    if ($next_round_exists) {
                        $stage_label = 'Round ' . $rn . ' ✅ → Round ' . ($rn + 1);
                        $stage_color = '#065f46'; $stage_bg = '#dcfce7';
                    } else {
                        $stage_label = 'Round ' . $rn . ' ✅ Completed';
                        $stage_color = '#065f46'; $stage_bg = '#dcfce7';
                    }
                } elseif ($rs == 'Pending' || $rs == 'Pending HR Review') {
                    $stage_label = 'Round ' . $rn . ' ⏳ Pending';
                    $stage_color = '#1d4ed8'; $stage_bg = '#dbeafe';
                } else {
                    $stage_label = 'Round ' . $rn . ' ⚠️ ' . round($rp) . '%';
                    $stage_color = '#92400e'; $stage_bg = '#fef9c3';
                }
            }
            ?>
            <?php if ($calling_label): ?>
            <div style="margin-top:4px;display:inline-block;background:<?php echo $calling_bg; ?>;color:<?php echo $calling_color; ?>;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:800;"><?php echo $calling_label; ?></div>
            <?php endif; ?>
            <div style="margin-top:4px;display:inline-block;background:<?php echo $stage_bg; ?>;color:<?php echo $stage_color; ?>;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:800;"><?php echo $stage_label; ?></div>
          </td>
          <td><span class="badge-s <?php echo $dc_cls; ?>"><?php echo str_replace('_',' ',ucfirst($row['hr_decision'])); ?></span>
            <?php if (!empty($row['moved_to_employee_at'])): ?>
            <div style="margin-top:4px;display:inline-block;background:#dcfce7;color:#065f46;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:800;" title="Marked as Employee by <?php echo htmlspecialchars($row['moved_to_employee_by'] ?? ''); ?> on <?php echo date('d M Y', strtotime($row['moved_to_employee_at'])); ?>"><i class="fas fa-user-check"></i> Employee</div>
            <?php endif; ?>
          </td>
          <td style="font-size:11px;color:var(--muted);"><?php echo date('d M Y', strtotime($row['created_at'])); ?></td>
          <td>
            <div style="display:flex;gap:4px;">
              <button onclick="openEditCandidate(<?php echo $row['id']; ?>, '<?php echo addslashes(htmlspecialchars($row['candidate_name'])); ?>', '<?php echo addslashes(htmlspecialchars($row['candidate_email'])); ?>', '<?php echo addslashes(htmlspecialchars($row['candidate_phone'])); ?>', '<?php echo addslashes(htmlspecialchars($row['department'])); ?>', '<?php echo addslashes(htmlspecialchars($row['position_applied'])); ?>', <?php echo intval($row['company_id'] ?? 0); ?>)" title="Edit Candidate"
                style="width:30px;height:30px;border-radius:7px;border:1px solid #e2e8f0;background:#f8fafc;cursor:pointer;color:#475569;font-size:12px;"
                onmouseover="this.style.background='#475569';this.style.color='#fff'"
                onmouseout="this.style.background='#f8fafc';this.style.color='#475569'"><i class="fas fa-pencil-alt"></i></button>
              <button onclick="viewCandidate(<?php echo $row['id']; ?>)" title="View Report"
                style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;cursor:pointer;color:var(--blue);font-size:12px;"
                onmouseover="this.style.background='var(--blue)';this.style.color='#fff'"
                onmouseout="this.style.background='#fff';this.style.color='var(--blue)'"><i class="fas fa-eye"></i></button>
              <button onclick="runAnalysis(<?php echo $row['id']; ?>, this)" title="<?php echo $row['ai_analysis']?'Re-analyse':'Run Analysis'; ?>"
                style="width:30px;height:30px;border-radius:7px;border:none;background:<?php echo $row['ai_analysis']?'#f1f5f9':'linear-gradient(135deg,var(--navy),var(--blue))'; ?>;cursor:pointer;color:<?php echo $row['ai_analysis']?'var(--muted)':'#fff'; ?>;font-size:12px;">
                <i class="fas <?php echo $row['ai_analysis']?'fa-sync-alt':'fa-robot'; ?>"></i></button>
              <a href="<?php echo htmlspecialchars($row['resume_path']); ?>" target="_blank" title="Resume"
                style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;color:var(--success);font-size:12px;display:flex;align-items:center;justify-content:center;text-decoration:none;"
                onmouseover="this.style.background='var(--success)';this.style.color='#fff'"
                onmouseout="this.style.background='#fff';this.style.color='var(--success)'"><i class="fas fa-file-alt"></i></a>
              <?php if ($hasJD): ?>
              <a href="<?php echo htmlspecialchars($row['jd_path']); ?>" target="_blank" title="Job Description"
                style="width:30px;height:30px;border-radius:7px;border:1px solid #ede9fe;background:#f5f3ff;color:#6366f1;font-size:12px;display:flex;align-items:center;justify-content:center;text-decoration:none;"
                onmouseover="this.style.background='#6366f1';this.style.color='#fff'"
                onmouseout="this.style.background='#f5f3ff';this.style.color='#6366f1'"><i class="fas fa-file-contract"></i></a>
              <?php endif; ?>
              <button onclick="deleteCandidate(<?php echo $row['id']; ?>)" title="Delete Candidate"
                style="width:30px;height:30px;border-radius:7px;border:1px solid #fee2e2;background:#fef2f2;cursor:pointer;color:#ef4444;font-size:12px;"
                onmouseover="this.style.background='#ef4444';this.style.color='#fff'"
                onmouseout="this.style.background='#fef2f2';this.style.color='#ef4444'"><i class="fas fa-trash-alt"></i></button>
              <div style="position:relative;display:inline-block;">
                <button onclick="toggleRowMenu(event, <?php echo $row['id']; ?>)" title="More Actions"
                  style="width:30px;height:30px;border-radius:7px;border:1px solid var(--border);background:#fff;cursor:pointer;color:var(--muted);font-size:14px;"
                  onmouseover="this.style.background='#f1f5f9'" onmouseout="this.style.background='#fff'"><i class="fas fa-ellipsis-v"></i></button>
                <div id="rowMenu_<?php echo $row['id']; ?>" class="row-menu" style="display:none;position:absolute;right:0;top:34px;background:#fff;border:1px solid var(--border);border-radius:8px;box-shadow:0 8px 24px rgba(0,0,0,.15);z-index:50;min-width:190px;overflow:hidden;">
                  <?php if (empty($row['moved_to_employee_at'])): ?>
                  <button onclick="markAsEmployee(<?php echo $row['id']; ?>, '<?php echo addslashes(htmlspecialchars($row['candidate_name'])); ?>')" style="display:block;width:100%;text-align:left;padding:10px 14px;border:none;background:none;cursor:pointer;font-size:12px;font-weight:700;color:var(--navy);"
                    onmouseover="this.style.background='#f8faff'" onmouseout="this.style.background='none'">
                    <i class="fas fa-user-check mr-2" style="color:#10b981;"></i> Mark as Employee
                  </button>
                  <?php else: ?>
                  <div style="padding:10px 14px;font-size:11px;color:var(--muted);"><i class="fas fa-check-circle mr-1" style="color:#10b981;"></i> Already marked as Employee</div>
                  <?php endif; ?>
                </div>
              </div>
            </div>
          </td>
        </tr>
        <?php endwhile; ?>
        </tbody>
      </table>
    </div>
  </div>
</div>

</div><!-- /wrap -->

<!-- Modal -->
<div class="modal fade" id="candidateModal" tabindex="-1" style="padding:0 !important;">
  <div class="modal-dialog" style="max-width:100%; margin:0; height:100vh;">
    <div class="modal-content" style="min-height:100vh; border-radius:0;">
      <div class="modal-header" style="align-items:center;background:#fff;border-bottom:1px solid #e0e7ff;padding:15px 24px;">
        <div style="display:flex;align-items:center;gap:15px;">
          <button type="button" data-dismiss="modal" style="background:#f1f5f9;border:1px solid #e2e8f0;border-radius:8px;padding:8px 16px;font-weight:700;color:#475569;cursor:pointer;"><i class="fas fa-arrow-left mr-2"></i>Back to Candidates</button>
          <h4 style="margin:0;font-weight:800;color:#0f2557;"><i class="fas fa-user-check mr-2"></i>Candidate Screening Report</h4>
        </div>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="candidateModalBody" style="padding:26px;">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--blue);"></i></div>
      </div>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script>
function switchTab(name) {
    document.querySelectorAll('.tab-pane').forEach(function(p){ p.classList.remove('active'); });
    document.querySelectorAll('.tab-btn').forEach(function(b){ b.classList.remove('active'); });
    document.getElementById('pane-' + name).classList.add('active');
    document.getElementById('tab-' + name).classList.add('active');
    localStorage.setItem('hrScreeningActiveTab', name);
}

window.addEventListener('DOMContentLoaded', function() {
    var savedTab = localStorage.getItem('hrScreeningActiveTab');
    if (savedTab && document.getElementById('tab-' + savedTab)) {
        switchTab(savedTab);
    }
    
    // Check URL for candidate view state
    var urlParams = new URLSearchParams(window.location.search);
    var viewId = urlParams.get('view_candidate');
    if (viewId) {
        viewCandidate(viewId);
    }
    
    // Clear URL when candidate modal is closed
    $('#candidateModal').on('hidden.bs.modal', function () {
        var url = new URL(window.location);
        url.searchParams.delete('view_candidate');
        window.history.pushState({}, '', url);
    });
});

function showFile(input, lblId, okId, nameId) {
    if (!input.files || !input.files.length) return;
    var fname = input.files[0].name;
    document.getElementById(lblId).textContent = fname;
    var box = document.getElementById(okId);
    box.style.display = 'flex';
    document.getElementById(nameId).textContent = fname;
}

document.getElementById('screenForm').addEventListener('submit', function() {
    var btn = document.getElementById('submitBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Uploading...';
});

function runAnalysis(id, btn) {
    var origHTML = btn ? btn.innerHTML : '';
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'; }

    var resultBox = document.getElementById('aiResultBox_' + id);
    if (!resultBox) {
        resultBox = document.createElement('div');
        resultBox.id = 'aiResultBox_' + id;
        if (btn && btn.closest && btn.closest('td')) {
            btn.closest('td').appendChild(resultBox);
        } else {
            document.body.appendChild(resultBox);
        }
    }

    resultBox.innerHTML = '<div style="text-align:center;padding:28px;color:var(--blue);">' +
        '<i class="fas fa-robot fa-2x" style="display:block;margin-bottom:10px;"></i>' +
        '<strong>AI is comparing JD vs Resume...</strong><br>' +
        '<small style="color:var(--muted);">This may take 15-30 seconds</small></div>';

    $.post(window.location.pathname, { ajax_analyze_resume: 1, screening_id: id }, function(resp) {
        if (btn) { btn.disabled = false; btn.innerHTML = origHTML; }
        if (resp.success) {
            renderAIResult(resp.data, resp.score, resultBox);
            // If resultBox was created dynamically (meaning this was clicked from the table), reload to show new score
            if (!document.getElementById('aiResultBox_' + id)) {
                location.reload();
            }
        } else if (resp.rate_limit) {
            showRateLimitCountdown(id, btn, origHTML, resultBox);
        } else {
            resultBox.innerHTML = '<div style="background:#fee2e2;padding:14px;border-radius:9px;color:#991b1b;font-weight:700;margin-top:10px;">' +
                '<i class="fas fa-exclamation-circle mr-2"></i>' + (resp.message || 'Analysis failed') + '</div>';
        }
    }, 'json').fail(function() {
        if (btn) { btn.disabled = false; btn.innerHTML = origHTML; }
        resultBox.innerHTML = '<div style="background:#fee2e2;padding:14px;border-radius:9px;color:#991b1b;font-weight:700;margin-top:10px;">Network error — please retry.</div>';
    });
}

function showRateLimitCountdown(id, btn, origHTML, resultBox) {
    if (btn) { btn.disabled = false; btn.innerHTML = origHTML; }
    resultBox.innerHTML =
        '<div style="background:#fffbeb;border:2px solid #f59e0b;border-radius:12px;padding:22px;text-align:center;margin-top:10px;">' +
            '<i class="fas fa-clock fa-2x" style="color:#f59e0b;display:block;margin-bottom:10px;"></i>' +
            '<div style="font-weight:800;color:#92400e;font-size:14px;margin-bottom:6px;">API Rate Limit — Please wait then retry</div>' +
            '<div style="font-size:12px;color:#78350f;margin-bottom:14px;">OpenRouter rate limit reached. Wait a moment then click retry.</div>' +
            '<button onclick="runAnalysis(' + id + ', this)" style="padding:10px 24px;border:none;border-radius:8px;background:linear-gradient(135deg,#f59e0b,#d97706);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">' +
                '<i class="fas fa-redo mr-1"></i> Retry Now' +
            '</button>' +
        '</div>';
}

function renderAIResult(data, score, container) {
    var sc = parseFloat(score);
    var color = sc >= 75 ? '#10b981' : (sc >= 50 ? '#f59e0b' : '#ef4444');
    var statusLabel = (data.eligibility_status || 'pending').replace(/_/g,' ').replace(/\b\w/g, function(c){ return c.toUpperCase(); });
    var circ = 2 * Math.PI * 54;
    var offset = circ - (sc / 100) * circ;
    var scoreClass = sc >= 75 ? 'b-eligible' : (sc >= 50 ? 'b-partial' : 'b-not');

    function tagsHTML(arr, cls) {
        if (!arr || !arr.length) return '<span style="color:var(--muted);font-size:12px;">None</span>';
        return arr.map(function(s){ return '<span class="skill-tag ' + cls + '">' + s + '</span>'; }).join('');
    }
    function listHTML(arr, cls) {
        if (!arr || !arr.length) return '';
        var icon = cls === 'strength-item' ? 'fa-check' : 'fa-exclamation-triangle';
        return arr.map(function(s){ return '<div class="' + cls + '"><i class="fas ' + icon + ' mr-2"></i>' + s + '</div>'; }).join('');
    }

    var jdTagsHTML = '';
    if (data.jd_key_requirements && data.jd_key_requirements.length) {
        jdTagsHTML = data.jd_key_requirements.map(function(r){ return '<span class="skill-tag" style="background:#ede9fe;color:#5b21b6;">' + r + '</span>'; }).join('');
    }

    var html = '<div class="ai-panel" style="margin-top:14px;">';
    html += '<div class="score-ring-wrap">';
    html += '<div class="score-ring">';
    html += '<svg width="120" height="120" viewBox="0 0 130 130">';
    html += '<circle cx="65" cy="65" r="54" fill="none" stroke="#e2e8f0" stroke-width="10"/>';
    html += '<circle cx="65" cy="65" r="54" fill="none" stroke="' + color + '" stroke-width="10" stroke-dasharray="' + circ.toFixed(2) + '" stroke-dashoffset="' + offset.toFixed(2) + '" stroke-linecap="round"/>';
    html += '</svg>';
    html += '<div class="score-num"><span style="color:' + color + ';">' + Math.round(sc) + '</span><small>/100</small></div>';
    html += '</div>';
    html += '<div style="margin-top:8px;"><span class="badge-s ' + scoreClass + '" style="font-size:13px;padding:6px 16px;">' + statusLabel + '</span></div>';
    if (data.candidate_summary) html += '<p style="margin-top:9px;color:var(--muted);font-size:13px;font-weight:600;">' + data.candidate_summary + '</p>';
    html += '</div>';

    html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:8px;">';
    html += '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:9px;padding:12px;"><div style="font-size:10px;font-weight:800;color:var(--blue);text-transform:uppercase;margin-bottom:3px;">Experience</div><div style="font-weight:800;color:var(--navy);">' + (data.experience_years || 'Unknown') + '</div></div>';
    html += '<div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:9px;padding:12px;"><div style="font-size:10px;font-weight:800;color:var(--blue);text-transform:uppercase;margin-bottom:3px;">Education</div><div style="font-weight:800;color:var(--navy);">' + (data.education_level || 'Unknown') + '</div></div>';
    html += '</div>';
    html += '<div style="font-size:11px;color:#94a3b8;display:flex;align-items:center;gap:5px;margin-bottom:14px;"><i class="fas fa-info-circle"></i> Auto-detected by keyword scan — please verify against the resume before deciding.</div>';

    if (data.scoring_breakdown && data.scoring_breakdown.length) {
        html += '<div class="ai-section"><h6><i class="fas fa-chart-bar" style="color:var(--blue);"></i> Score Breakdown <span style="font-weight:600;font-size:10px;color:#94a3b8;text-transform:none;">(click a row for details)</span></h6>';
        data.scoring_breakdown.forEach(function(sb) {
            var barColor = sb.pct >= 75 ? '#10b981' : (sb.pct >= 40 ? '#f59e0b' : '#ef4444');
            window._sbDetailCounter = (window._sbDetailCounter || 0) + 1;
            var detailId = 'sbDetailJS_' + window._sbDetailCounter;
            html += '<div style="margin-bottom:10px;cursor:pointer;" onclick="var d=document.getElementById(\'' + detailId + '\'); if(d) d.style.display = d.style.display===\'none\' ? \'block\' : \'none\';">';
            html += '<div style="display:flex;justify-content:space-between;font-size:12px;font-weight:700;color:var(--navy);margin-bottom:3px;">';
            html += '<span><i class="fas fa-chevron-right" style="font-size:9px;color:#94a3b8;margin-right:5px;"></i>' + sb.label + '</span><span>' + sb.points + ' / ' + sb.max + ' pts (' + sb.pct + '%)</span>';
            html += '</div>';
            html += '<div class="pbar-wrap"><div class="pbar-fill" style="width:' + Math.min(100, sb.pct) + '%;background:' + barColor + ';"></div></div>';
            if (sb.detail) {
                html += '<div id="' + detailId + '" style="display:none;margin-top:6px;background:#f8fafc;border-left:3px solid #cbd5e1;border-radius:6px;padding:8px 10px;font-size:11px;font-weight:600;color:#475569;line-height:1.5;">' + sb.detail + '</div>';
            }
            html += '</div>';
        });
        html += '</div>';
    }

    if (jdTagsHTML) html += '<div class="ai-section"><h6><i class="fas fa-file-contract" style="color:#6366f1;"></i> Key JD Requirements</h6>' + jdTagsHTML + '</div>';
    html += '<div class="ai-section"><h6><i class="fas fa-check-circle" style="color:#10b981;"></i> Matched</h6>' + tagsHTML(data.skills_matched, 'skill-ok') + '</div>';
    html += '<div class="ai-section"><h6><i class="fas fa-times-circle" style="color:#ef4444;"></i> Missing</h6>' + tagsHTML(data.skills_missing, 'skill-miss') + '</div>';
    html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px;">';
    html += '<div class="ai-section"><h6><i class="fas fa-star" style="color:#f59e0b;"></i> Strengths</h6>' + (listHTML(data.strengths, 'strength-item') || '<div class="strength-item">—</div>') + '</div>';
    html += '<div class="ai-section"><h6><i class="fas fa-exclamation-triangle" style="color:#f59e0b;"></i> Concerns</h6>' + (listHTML(data.concerns, 'concern-item') || '<div class="strength-item">No major concerns</div>') + '</div>';
    html += '</div>';
    if (data.jd_vs_resume_gap) html += '<div class="ai-section"><h6><i class="fas fa-balance-scale" style="color:#6366f1;"></i> JD vs Resume Gap</h6><div style="background:#f5f3ff;border:1px solid #ede9fe;border-radius:9px;padding:13px;font-size:13px;font-weight:600;color:#4c1d95;line-height:1.7;">' + data.jd_vs_resume_gap + '</div></div>';
    if (data.recommendation) html += '<div class="ai-section"><h6><i class="fas fa-comment-dots" style="color:var(--blue);"></i> Recommendation</h6><div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:9px;padding:13px;font-size:13px;font-weight:600;color:#0369a1;line-height:1.7;">' + data.recommendation + '</div></div>';
    if (data.interview_questions && data.interview_questions.length) {
        html += '<div class="ai-section"><h6><i class="fas fa-question-circle" style="color:var(--blue);"></i> Interview Questions</h6>';
        data.interview_questions.forEach(function(q){ html += '<div class="q-item">' + q + '</div>'; });
        html += '</div>';
    }
    html += '</div>';
    container.innerHTML = html;
}

function viewCandidate(id) {
    // Add to URL for state persistence on refresh
    var url = new URL(window.location);
    url.searchParams.set('view_candidate', id);
    window.history.pushState({view_candidate: id}, '', url);

    $('#candidateModal').modal('show');
    $('#candidateModalBody').html('<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--blue);"></i></div>');
    $.get(window.location.pathname + '?ajax_view_candidate=1&id=' + id, function(html) {
        $('#candidateModalBody').html(html);

        // Restore last viewed tab/round for this candidate, if any
        var saved = localStorage.getItem('hrLastCandidateView_' + id);
        if (saved) {
            try {
                var state = JSON.parse(saved);
                if (state.tab === 'rounds') {
                    var roundsTabLink = document.getElementById('tab-rounds-link');
                    if (roundsTabLink) {
                        $(roundsTabLink).tab('show');
                        roundsTabLink.style.borderBottom = '3px solid var(--blue)';
                        roundsTabLink.style.color = 'var(--navy)';
                        var aiTabLink = document.getElementById('tab-ai-analysis');
                        if (aiTabLink && aiTabLink.parentElement && aiTabLink.parentElement.parentElement) {
                            $(aiTabLink.parentElement.parentElement).find('a.nav-link').not(roundsTabLink).css('border-bottom', '3px solid transparent').css('color', 'var(--muted)');
                        }
                        loadInterviewRounds(id, state.round || 0);
                    }
                }
            } catch (e) {}
        }
    }).fail(function() {
        $('#candidateModalBody').html('<p style="text-align:center;padding:30px;color:red;">Failed to load.</p>');
    });
}

var pendingDuplicateAction = null;

function showDuplicateWarningModal(sid, res, actionType, btn = null, extraData = {}) {
    var createdDate = res.created_at ? new Date(res.created_at).toLocaleDateString('en-IN', {day:'2-digit',month:'short',year:'numeric'}) : '—';
    $('#dupCandName').text(res.name);
    $('#dupCandId').text('#' + res.id);
    $('#dupCandStatus').text(res.status);
    $('#dupCandDate').text(createdDate);
    
    pendingDuplicateAction = { type: actionType, id: sid, btn: btn, data: extraData, trackId: res.id };
    $('#duplicateWarningModal').modal('show');
}

$(document).on('click', '#btnSkipTracking', function() {
    if (!pendingDuplicateAction) return;
    if (pendingDuplicateAction.type === 'saveDecision') {
        doSaveDecision(pendingDuplicateAction.id, pendingDuplicateAction.data.decision, pendingDuplicateAction.data.notes, pendingDuplicateAction.data.override, 1, pendingDuplicateAction.btn);
    } else if (pendingDuplicateAction.type === 'startCalling') {
        doStartCalling(pendingDuplicateAction.id, pendingDuplicateAction.btn, 1);
    }
});

$(document).on('click', '#btnLinkTracking', function() {
    if (!pendingDuplicateAction) return;
    var btn = pendingDuplicateAction.btn;
    var sid = pendingDuplicateAction.id;
    var trackId = pendingDuplicateAction.trackId;
    
    if (btn) btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Linking...';
    
    $.post(window.location.pathname, { ajax_link_tracking: 1, screening_id: sid, tracking_id: trackId }, function() {
        if (pendingDuplicateAction.type === 'saveDecision') {
            doSaveDecision(sid, pendingDuplicateAction.data.decision, pendingDuplicateAction.data.notes, pendingDuplicateAction.data.override, 1, btn); // skip auto-create, already linked
        } else if (pendingDuplicateAction.type === 'startCalling') {
            doStartCalling(sid, btn, 1); // skip auto-create, already linked
        }
    }, 'json').fail(function() {
        alert('Failed to link candidate.');
        if (btn) btn.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Error';
    });
});

function saveDecision(id) {
    var decision = document.getElementById('hrDecisionSel').value;
    var notes    = document.getElementById('hrNotesTxt').value;
    var overrideEl = document.getElementById('hrOverrideTxt');
    var override = overrideEl ? overrideEl.value : '';

    if (decision === 'rejected') {
        openRejectModal(id, 0, 'Overall', 'overall');
        return;
    }

    var btn = event.currentTarget;
    if (decision === 'shortlisted' || decision === 'hired') {
        var oldHtml = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Checking...';
        $.getJSON(window.location.pathname, { ajax_check_tracking_duplicate: 1, screening_id: id }, function(res) {
            if (res.duplicate) {
                btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Decision';
                showDuplicateWarningModal(id, res, 'saveDecision', btn, {decision: decision, notes: notes, override: override});
            } else {
                doSaveDecision(id, decision, notes, override, 0, btn);
            }
        });
        return;
    }
    doSaveDecision(id, decision, notes, override, 0, btn);
}

function doSaveDecision(id, decision, notes, override, skipTracking, btn) {
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Saving...';
    $.post(window.location.href, { ajax_update_decision: 1, screening_id: id, decision: decision, notes: notes, override_score: override, skip_tracking_creation: skipTracking }, function(resp) {
        if (resp.success) {
            btn.innerHTML = '<i class="fas fa-check mr-1"></i> Saved!';
            $('#duplicateWarningModal').modal('hide');
            setTimeout(function(){ 
                btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Decision';
            }, 2000);
            viewCandidate(id); // refresh panel so Interview Rounds tab reflects the linked tracking row
        } else {
            btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Decision';
            alert(resp.message || 'Could not save decision.');
        }
    }, 'json').fail(function() {
        btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Decision';
    });
}

function applyFilter() {
    var status = document.getElementById('filterStatus').value;
    var dept   = document.getElementById('filterDept').value;
    var name   = document.getElementById('filterName').value.toLowerCase().trim();
    document.querySelectorAll('#screeningTable tbody tr').forEach(function(row) {
        var show = true;
        if (status && row.dataset.status !== status) show = false;
        if (dept   && row.dataset.dept   !== dept)   show = false;
        if (name   && row.dataset.name.indexOf(name) === -1) show = false;
        row.style.display = show ? '' : 'none';
    });
}

function exportCSV() {
    var csv = [];
    document.querySelectorAll('#screeningTable tr').forEach(function(row) {
        if (row.style.display === 'none') return;
        var cells = [];
        var cols = row.querySelectorAll('td, th');
        for (var i = 0; i < cols.length - 1; i++) {
            cells.push('"' + cols[i].innerText.replace(/"/g, '""').replace(/\n/g, ' ').trim() + '"');
        }
        csv.push(cells.join(','));
    });
    var blob = new Blob(['\ufeff' + csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'HR_Screenings.csv';
    a.click();
}

function deleteCandidate(id) {
    if (confirm('Are you sure you want to delete this candidate? This cannot be undone.')) {
        $.post(window.location.pathname, { ajax_delete_candidate: 1, screening_id: id }, function(resp) {
            if (resp.success) {
                var urlParams = new URLSearchParams(window.location.search);
                if (urlParams.get('uploaded') == id) {
                    window.location.href = window.location.pathname;
                } else {
                    var row = document.getElementById('row_' + id);
                    if (row) {
                        row.style.transition = 'opacity 0.3s';
                        row.style.opacity = '0';
                        setTimeout(function() { row.remove(); }, 300);
                    }
                }
            } else {
                alert('Error: ' + (resp.message || 'Could not delete candidate.'));
            }
        }, 'json').fail(function() {
            alert('Failed to delete. Server error.');
        });
    }
}

function toggleRowMenu(e, id) {
    e.stopPropagation();
    document.querySelectorAll('.row-menu').forEach(function(m) { if (m.id !== 'rowMenu_' + id) m.style.display = 'none'; });
    var menu = document.getElementById('rowMenu_' + id);
    if (menu) menu.style.display = (menu.style.display === 'block') ? 'none' : 'block';
}
document.addEventListener('click', function() {
    document.querySelectorAll('.row-menu').forEach(function(m) { m.style.display = 'none'; });
});

function markAsEmployee(id, name) {
    if (!confirm('Mark "' + name + '" as Employee?\n\nThis just tags their record here for reference — it does not create or sync anything with any other system.')) return;
    $.post(window.location.pathname, { ajax_mark_as_employee: 1, screening_id: id }, function(resp) {
        if (resp.success) {
            window.location.reload();
        } else {
            alert(resp.message || 'Could not mark as employee.');
        }
    }, 'json').fail(function() { alert('Server error.'); });
}

function hrOverrideUnlock(screening_id, round_number) {
    // Store values for submit
    document.getElementById('overrideScreeningId').value = screening_id;
    document.getElementById('overrideRoundNumber').value = round_number;
    document.getElementById('overrideReason').value = '';
    // Show the Bootstrap modal
    $('#hrOverrideModal').modal('show');
}

function submitOverride(screening_id, round_number) {
    var reason = document.getElementById('overrideReason').value.trim();
    if (!reason) {
        alert('Please enter a reason for the override.');
        return;
    }
    $.post(window.location.pathname, {
        ajax_hr_override_unlock: 1,
        screening_id: screening_id,
        round_number: round_number,
        override_reason: reason
    }, function(resp) {
        if (resp.success) {
            $('#hrOverrideModal').modal('hide');
            loadInterviewRounds(screening_id, round_number);
        }
    }, 'json');
}

var _roundLoadToken = 0;

function loadInterviewRounds(screening_id, round_number) {
    var container = document.getElementById('interviewRoundsContainer');
    if (!container) return;

    // Remember last viewed tab + round for this candidate so a page reload can restore it
    localStorage.setItem('hrLastCandidateView_' + screening_id, JSON.stringify({ tab: 'rounds', round: round_number }));

    // Guard against race conditions: if the user clicks multiple round tabs quickly,
    // only the response matching the MOST RECENT click is allowed to render.
    var myToken = ++_roundLoadToken;

    container.innerHTML = '<div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--blue);"></i><div style="margin-top:10px;color:var(--muted);font-weight:600;">Loading...</div></div>';

    $.get(window.location.pathname + '?ajax_load_interview_round=1&screening_id=' + screening_id + '&round_number=' + round_number, function(html) {
        if (myToken !== _roundLoadToken) return; // a newer request has since been made — discard this stale response
        $(container).html(html);
    }).fail(function() {
        if (myToken !== _roundLoadToken) return;
        $(container).html('<p style="color:red;text-align:center;padding:20px;">Failed to load interview rounds.</p>');
    });
}

function submitInterviewEvaluation(e, screening_id, round_number) {
    e.preventDefault();
    var form = document.getElementById('evalForm_' + round_number);
    var btn = form.querySelector('button[type="submit"]');
    var originalText = btn.innerHTML;

    var unratedCount = 0, totalCount = 0;
    form.querySelectorAll('select[id^="marks_"]').forEach(function(sel) {
        totalCount++;
        if (sel.value === '') unratedCount++;
    });

    var earlyEndReason = '';
    if (unratedCount > 0) {
        if (!confirm(unratedCount + ' of ' + totalCount + ' question(s) were not rated. Submit anyway as an early-ended interview?')) return;
        earlyEndReason = prompt('Optional: Why was the interview ended early? (Leave blank to skip)') || '';
    }

    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Submitting...';
    btn.disabled = true;
    
    var formData = $(form).serialize() + '&ajax_submit_evaluation=1&screening_id=' + screening_id + '&round_number=' + round_number + '&early_end_reason=' + encodeURIComponent(earlyEndReason);
    
    $.post(window.location.pathname, formData, function(resp) {
        if (resp.success) {
            btn.innerHTML = '<i class="fas fa-check mr-2"></i>Success!';
            btn.style.background = 'linear-gradient(135deg, #10b981, #059669)';
            try { localStorage.removeItem('hrEvalDraft_' + screening_id + '_' + round_number); } catch (e) {}
            
            // Reload the interview rounds tab to show the results
            setTimeout(function() {
                loadInterviewRounds(screening_id, round_number);
            }, 1000);
        } else {
            alert('Error: ' + (resp.message || 'Could not submit evaluation.'));
            btn.innerHTML = originalText;
            btn.disabled = false;
        }
    }, 'json').fail(function() {
        alert('Server error occurred while submitting evaluation.');
        btn.innerHTML = originalText;
        btn.disabled = false;
    });
}

function loadPositionsForDept(deptName) {
    var posSelect = document.getElementById('posSelect');
    var posNameInput = document.getElementById('posNameInput');
    
    if (!posSelect) return;
    posSelect.innerHTML = '<option value="">Loading...</option>';
    if (posNameInput) posNameInput.value = '';
    
    if (!deptName) {
        posSelect.innerHTML = '<option value="">Select Position...</option>';
        return;
    }
    
    $.post(window.location.href, { ajax_get_positions_by_dept: 1, department: deptName }, function(res) {
        posSelect.innerHTML = '<option value="">Select Position...</option>';
        if (res.success && res.positions.length > 0) {
            res.positions.forEach(function(p) {
                var opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.title;
                opt.setAttribute('data-category', p.worker_category || 'professional');
                posSelect.appendChild(opt);
            });
        }
    }, 'json');
}

function updatePosName() {
    var posSelect = document.getElementById('posSelect');
    var posNameInput = document.getElementById('posNameInput');
    if (posSelect && posNameInput) {
        if (posSelect.selectedIndex > 0) {
            posNameInput.value = posSelect.options[posSelect.selectedIndex].text;
        } else {
            posNameInput.value = '';
        }
    }
    applyBlueCollarRequirements();
}

// Blue Collar positions: Resume/JD upload become optional, and the requirement hints/labels update to match.
function applyBlueCollarRequirements() {
    var posSelect = document.getElementById('posSelect');
    var notice = document.getElementById('blueCollarNotice');
    var categorySelect = document.getElementById('posCategorySelect');
    if (!posSelect) return;
    var selectedOpt = posSelect.options[posSelect.selectedIndex];
    var hasPosition = !!(selectedOpt && selectedOpt.value);
    var isBlueCollar = !!(selectedOpt && selectedOpt.getAttribute('data-category') === 'blue_collar');

    if (categorySelect) {
        categorySelect.disabled = !hasPosition;
        categorySelect.value = isBlueCollar ? 'blue_collar' : 'professional';
    }

    var jdFile = document.getElementById('jdFile');
    var resumeFile = document.getElementById('resumeFile');
    var jdReqLbl = document.getElementById('jdReqLbl');
    var resumeReqLbl = document.getElementById('resumeReqLbl');
    var jdSecLbl = document.getElementById('jdSecLbl');
    var resumeSecLbl = document.getElementById('resumeSecLbl');
    var jdReqNote = document.getElementById('jdReqNote');

    if (notice) notice.style.display = isBlueCollar ? 'block' : 'none';

    if (jdFile) { if (isBlueCollar) jdFile.removeAttribute('required'); else jdFile.setAttribute('required', 'required'); }
    if (resumeFile) { if (isBlueCollar) resumeFile.removeAttribute('required'); else resumeFile.setAttribute('required', 'required'); }
    if (jdReqLbl) jdReqLbl.innerHTML = isBlueCollar ? 'PDF, DOC, DOCX, TXT &middot; Optional' : 'PDF, DOC, DOCX, TXT &middot; Required';
    if (resumeReqLbl) resumeReqLbl.innerHTML = isBlueCollar ? 'PDF, DOC, DOCX, TXT &middot; Optional' : 'PDF, DOC, DOCX, TXT &middot; Required';
    if (jdSecLbl) jdSecLbl.innerHTML = isBlueCollar ? '<i class="fas fa-file-contract"></i> Job Description (JD)' : '<i class="fas fa-file-contract"></i> Job Description (JD) *';
    if (resumeSecLbl) resumeSecLbl.innerHTML = isBlueCollar ? '<i class="fas fa-file-alt"></i> Candidate Resume' : '<i class="fas fa-file-alt"></i> Candidate Resume *';
    if (jdReqNote) jdReqNote.style.display = isBlueCollar ? 'none' : 'block';
}
document.addEventListener('DOMContentLoaded', applyBlueCollarRequirements);

// HR changes the Category dropdown right here on the screening form — this updates the
// POSITION's classification (hr_positions.worker_category), so it applies to every future
// candidate for that position too, same as the "Manage Position Categories" panel in hr-OJE.php.
function savePositionCategoryFromScreening() {
    var posSelect = document.getElementById('posSelect');
    var categorySelect = document.getElementById('posCategorySelect');
    if (!posSelect || !categorySelect) return;
    var posId = posSelect.value;
    if (!posId) return;
    var newCategory = categorySelect.value;

    $.post(window.location.href, { ajax_set_position_category: 1, position_id: posId, worker_category: newCategory }, function(resp) {
        var data = typeof resp === 'string' ? JSON.parse(resp) : resp;
        if (data.success) {
            var selectedOpt = posSelect.options[posSelect.selectedIndex];
            if (selectedOpt) selectedOpt.setAttribute('data-category', newCategory);
            applyBlueCollarRequirements();
        } else {
            alert('Could not update position category. Please try again.');
        }
    }, 'json');
}
</script>
<!-- Edit Candidate Modal -->
<div class="modal fade" id="editCandidateModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content" style="border-radius:14px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.3);">
      <div class="modal-body" style="padding:28px;">
        <h5 style="font-weight:800;color:#0f2557;margin-bottom:18px;">
          <i class="fas fa-user-edit mr-2"></i>Edit Candidate
        </h5>
        <input type="hidden" id="editCandidateId">
        
        <div style="margin-bottom:12px;">
          <label class="frm-lbl">Candidate Name</label>
          <input type="text" class="fc" id="editCandidateName" style="width:100%;">
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px;">
          <div>
            <label class="frm-lbl">Email</label>
            <input type="email" class="fc" id="editCandidateEmail" style="width:100%;">
          </div>
          <div>
            <label class="frm-lbl">Phone</label>
            <input type="text" class="fc" id="editCandidatePhone" style="width:100%;">
          </div>
        </div>
        <div style="margin-bottom:12px;">
          <label class="frm-lbl">Company</label>
          <select class="fc" id="editCandidateCompany" style="width:100%;">
            <option value="">Select Company...</option>
            <?php foreach ($companies_list as $co): ?>
            <option value="<?php echo $co['id']; ?>"><?php echo htmlspecialchars($co['company_name']); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div style="margin-bottom:12px;">
          <label class="frm-lbl">Department</label>
          <select class="fc" id="editCandidateDept" style="width:100%;" onchange="loadPositionsForEdit(this.value)">
            <option value="">Select Department...</option>
            <?php foreach ($depts as $d): ?>
            <option value="<?php echo htmlspecialchars($d); ?>"><?php echo htmlspecialchars($d); ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div style="margin-bottom:24px;">
          <label class="frm-lbl">Position</label>
          <select class="fc" id="editCandidatePos" style="width:100%;" onchange="updateEditPosName()">
            <option value="">Select Position...</option>
          </select>
          <input type="hidden" id="editPosNameInput">
        </div>
        
        <div style="display:flex;gap:10px;justify-content:flex-end;">
          <button onclick="$('#editCandidateModal').modal('hide')" style="padding:10px 20px;border:2px solid #e0e7ff;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;">Cancel</button>
          <button id="saveCandidateBtn" onclick="submitEditCandidate()" style="padding:10px 24px;border:none;border-radius:8px;background:var(--blue);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">
            <i class="fas fa-save mr-1"></i> Save Changes
          </button>
        </div>
      </div>
    </div>
  </div>
</div>
<script>
function openEditCandidate(id, name, email, phone, dept, posApplied, companyId) {
    document.getElementById('editCandidateId').value = id;
    document.getElementById('editCandidateCompany').value = companyId || '';
    document.getElementById('editCandidateName').value = name;
    document.getElementById('editCandidateEmail').value = email;
    document.getElementById('editCandidatePhone').value = phone;
    document.getElementById('editCandidateDept').value = dept;
    document.getElementById('editPosNameInput').value = posApplied;
    
    // Load positions for this department and select the correct one
    var posSelect = document.getElementById('editCandidatePos');
    posSelect.innerHTML = '<option value="">Loading...</option>';
    
    $.post(window.location.href, { ajax_get_positions_by_dept: 1, department: dept }, function(res) {
        posSelect.innerHTML = '<option value="">Select Position...</option>';
        if (res.success && res.positions.length > 0) {
            res.positions.forEach(function(p) {
                var opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.title;
                if (p.title === posApplied) opt.selected = true;
                posSelect.appendChild(opt);
            });
        }
    }, 'json');
    
    $('#editCandidateModal').modal('show');
}

function loadPositionsForEdit(deptName) {
    var posSelect = document.getElementById('editCandidatePos');
    document.getElementById('editPosNameInput').value = '';
    posSelect.innerHTML = '<option value="">Loading...</option>';
    if (!deptName) { posSelect.innerHTML = '<option value="">Select Position...</option>'; return; }
    
    $.post(window.location.href, { ajax_get_positions_by_dept: 1, department: deptName }, function(res) {
        posSelect.innerHTML = '<option value="">Select Position...</option>';
        if (res.success && res.positions.length > 0) {
            res.positions.forEach(function(p) {
                var opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.title;
                posSelect.appendChild(opt);
            });
        }
    }, 'json');
}

function updateEditPosName() {
    var posSelect = document.getElementById('editCandidatePos');
    var posNameInput = document.getElementById('editPosNameInput');
    if (posSelect.selectedIndex > 0) {
        posNameInput.value = posSelect.options[posSelect.selectedIndex].text;
    } else {
        posNameInput.value = '';
    }
}

function submitEditCandidate() {
    var id = document.getElementById('editCandidateId').value;
    var name = document.getElementById('editCandidateName').value.trim();
    var email = document.getElementById('editCandidateEmail').value.trim();
    var phone = document.getElementById('editCandidatePhone').value.trim();
    var dept = document.getElementById('editCandidateDept').value;
    var pos_id = document.getElementById('editCandidatePos').value;
    var pos_applied = document.getElementById('editPosNameInput').value;
    
    if (!name || !dept || !pos_applied) {
        alert("Name, Department, and Position are required.");
        return;
    }
    
    var btn = document.getElementById('saveCandidateBtn');
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Saving...';
    btn.disabled = true;
    
    var company_id = document.getElementById('editCandidateCompany').value;
    $.post(window.location.pathname, {
        ajax_edit_candidate: 1,
        screening_id: id,
        company_id: company_id,
        candidate_name: name,
        candidate_email: email,
        candidate_phone: phone,
        department: dept,
        position_id: pos_id,
        position_applied: pos_applied
    }, function(resp) {
        if (resp.success) {
            location.reload();
        } else {
            alert('Error: ' + (resp.message || 'Could not update candidate.'));
            btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Changes';
            btn.disabled = false;
        }
    }, 'json').fail(function() {
        alert('Failed to save. Server error.');
        btn.innerHTML = '<i class="fas fa-save mr-1"></i> Save Changes';
        btn.disabled = false;
    });
}
</script>
<!-- Manager Override Modal (proper Bootstrap modal to fix focus issue) -->
<div class="modal fade" id="hrOverrideModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content" style="border-radius:14px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.3);">
      <div class="modal-body" style="padding:28px;">
        <h5 style="font-weight:800;color:#0f2557;margin-bottom:6px;">
          <i class="fas fa-unlock" style="color:#f59e0b;margin-right:8px;"></i>Manager Override — Unlock Next Round
        </h5>
        <p style="font-size:13px;color:#64748b;margin-bottom:18px;">
          Score is below 90%. Please provide a reason for overriding and unlocking the next round.
        </p>
        <input type="hidden" id="overrideScreeningId">
        <input type="hidden" id="overrideRoundNumber">
        <div style="margin-bottom:16px;">
          <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Override Reason *</label>
          <textarea id="overrideReason" style="width:100%;padding:10px 13px;border:2px solid #e0e7ff;border-radius:9px;font-family:inherit;font-size:13px;resize:vertical;height:90px;" placeholder="e.g. Candidate showed strong practical skills during in-person discussion..."></textarea>
        </div>
        <div style="display:flex;gap:10px;justify-content:flex-end;">
          <button onclick="$('#hrOverrideModal').modal('hide')" style="padding:10px 20px;border:2px solid #e0e7ff;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;">Cancel</button>
          <button onclick="submitOverride(document.getElementById('overrideScreeningId').value, document.getElementById('overrideRoundNumber').value)" style="padding:10px 24px;border:none;border-radius:8px;background:linear-gradient(135deg,#f59e0b,#d97706);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">
            <i class="fas fa-unlock mr-1"></i> Confirm Override
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="modal fade" id="candidateModal" tabindex="-1" style="padding:0 !important;">
  <div class="modal-dialog" style="max-width:100%; margin:0; height:100vh;">
    <div class="modal-content" style="min-height:100vh; border-radius:0;">
      <div class="modal-header" style="align-items:center;background:#fff;border-bottom:1px solid #e0e7ff;padding:15px 24px;">
        <div style="display:flex;align-items:center;gap:15px;">
          <button type="button" data-dismiss="modal" style="background:#f1f5f9;border:1px solid #e2e8f0;border-radius:8px;padding:8px 16px;font-weight:700;color:#475569;cursor:pointer;"><i class="fas fa-arrow-left mr-2"></i>Back to Candidates</button>
          <h4 style="margin:0;font-weight:800;color:#0f2557;"><i class="fas fa-user-check mr-2"></i>Candidate Screening Report</h4>
        </div>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" id="candidateModalBody" style="padding:26px;">
        <div style="text-align:center;padding:40px;"><i class="fas fa-spinner fa-spin fa-2x" style="color:var(--blue);"></i></div>
      </div>
    </div>
  </div>
</div>
<!-- Round Notification Modal -->
<div class="modal fade" id="roundNotifyModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <div class="modal-header" style="background:#f8faff;border-bottom:1px solid #e0e7ff;">
      <h5 class="modal-title" style="font-weight:800;color:var(--navy);"><i class="fas fa-paper-plane mr-2 text-primary"></i>Notify Candidate: Round Update</h5>
      <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px;">
      <input type="hidden" id="rn_sid">
      <input type="hidden" id="rn_round">
      <input type="hidden" id="rn_phone">
      <input type="hidden" id="rn_context">

      <!-- Email Section -->
      <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
        <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
        <div class="fg"><label class="fl">To</label><input type="email" id="rn_email_to" class="fc"></div>
        <div class="fg"><label class="fl">Subject</label><input type="text" id="rn_email_subj" class="fc"></div>
        <div class="fg"><label class="fl">Message</label><textarea id="rn_email_body" class="fc" style="height:140px;resize:vertical;"></textarea></div>
        <button type="button" onclick="sendRoundEmail()" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Send Email Now</button>
      </div>

      <!-- WhatsApp Section -->
      <div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;margin-bottom:16px;" id="rn_wa_container">
        <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
        <div style="margin-bottom:10px;">
          <label style="font-size:12px;font-weight:700;color:#065f46;display:block;margin-bottom:4px;">Phone Number</label>
          <input type="text" id="rn_phone_display" class="fc" style="width:100%;" placeholder="+91XXXXXXXXXX">
        </div>
        <textarea id="rn_wa_msg" class="fc" style="height:100px;resize:vertical;"></textarea>
        <div style="margin-top:10px;">
          <button type="button" onclick="openRoundWhatsApp()" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp mr-1"></i> Open WhatsApp</button>
        </div>
      </div>
      
    </div>
  </div></div>
</div>

<!-- Interview Schedule & Notify Modal -->
<div class="modal fade" id="scheduleInterviewModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <div class="modal-header" style="background:#eff6ff;border-bottom:1px solid #bfdbfe;">
      <h5 class="modal-title" style="font-weight:800;color:var(--navy);"><i class="fas fa-calendar-alt mr-2 text-primary"></i>Schedule Interview &amp; Notify Candidate</h5>
      <button type="button" class="close" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px;">
      <input type="hidden" id="si_sid">
      <input type="hidden" id="si_round">

      <div style="display:flex;gap:14px;margin-bottom:18px;flex-wrap:wrap;">
        <div class="fg" style="flex:1;min-width:200px;">
          <label class="fl">Interview Date &amp; Time *</label>
          <input type="datetime-local" id="si_datetime" class="fc">
        </div>
        <div class="fg" style="flex:1;min-width:200px;">
          <label class="fl">Interview End Time <span style="font-weight:400;color:var(--muted);">(optional)</span></label>
          <input type="datetime-local" id="si_end_datetime" class="fc">
        </div>
      </div>

      <div class="fg" style="margin-bottom:18px;background:#fffbeb;border:1px solid #fde68a;border-radius:10px;padding:16px;">
        <label class="fl">Interview Mode *</label>
        <div style="display:flex;gap:14px;margin-bottom:12px;flex-wrap:wrap;">
          <label style="display:flex;align-items:center;gap:6px;font-weight:700;font-size:13px;cursor:pointer;">
            <input type="radio" name="si_mode" value="virtual" onchange="toggleInterviewModeFields()" checked style="accent-color:#1a3fc4;"> <i class="fas fa-video mr-1"></i> Virtual Interview
          </label>
          <label style="display:flex;align-items:center;gap:6px;font-weight:700;font-size:13px;cursor:pointer;">
            <input type="radio" name="si_mode" value="face_to_face" onchange="toggleInterviewModeFields()" style="accent-color:#1a3fc4;"> <i class="fas fa-building mr-1"></i> Face to Face Interview
          </label>
          <label style="display:flex;align-items:center;gap:6px;font-weight:700;font-size:13px;cursor:pointer;">
            <input type="radio" name="si_mode" value="assignment" onchange="toggleInterviewModeFields()" style="accent-color:#1a3fc4;"> <i class="fas fa-file-alt mr-1"></i> Assignment
          </label>
          <label style="display:flex;align-items:center;gap:6px;font-weight:700;font-size:13px;cursor:pointer;">
            <input type="radio" name="si_mode" value="observation" onchange="toggleInterviewModeFields()" style="accent-color:#1a3fc4;"> <i class="fas fa-hourglass-half mr-1"></i> Observation
          </label>
          <label style="display:flex;align-items:center;gap:6px;font-weight:700;font-size:13px;cursor:pointer;">
            <input type="radio" name="si_mode" value="document_verification" onchange="toggleInterviewModeFields()" style="accent-color:#1a3fc4;"> <i class="fas fa-id-card mr-1"></i> Document Verification
          </label>
        </div>
        <div id="si_virtual_wrap">
          <label class="fl">Meeting Link *</label>
          <input type="text" id="si_meeting_link" class="fc" placeholder="e.g. https://meet.google.com/xxx-xxxx-xxx" oninput="updateScheduleMessages(window._si_name, window._si_pos)">
        </div>
        <div id="si_address_wrap" style="display:none;">
          <label class="fl">Interview Address</label>
          <textarea id="si_address" class="fc" style="height:60px;resize:vertical;" oninput="updateScheduleMessages(window._si_name, window._si_pos)">Abra Group, 209, 2nd Main Rd, East of NGEF Layout, Kasturi Nagar, Bengaluru, Karnataka 560043</textarea>
        </div>
      </div>

      <div style="background:#f8faff;border:1px solid #e0e7ff;border-radius:10px;padding:18px;margin-bottom:16px;">
        <div style="font-weight:800;font-size:13px;color:var(--navy);margin-bottom:12px;"><i class="fas fa-envelope mr-2" style="color:#6366f1;"></i> Send via Email</div>
        <div class="fg"><label class="fl">To</label><input type="email" id="si_email_to" class="fc"></div>
        <div class="fg"><label class="fl">Subject</label><input type="text" id="si_email_subj" class="fc"></div>
        <div class="fg"><label class="fl">Message</label><textarea id="si_email_body" class="fc" style="height:140px;resize:vertical;"></textarea></div>
        <div id="si_email_alert" style="margin-bottom:8px;"></div>
        <button type="button" onclick="sendScheduleEmail()" class="btn-p btn-navy"><i class="fas fa-paper-plane mr-1"></i> Save Schedule &amp; Send Email</button>
      </div>

      <div style="background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:18px;">
        <div style="font-weight:800;font-size:13px;color:#065f46;margin-bottom:12px;"><i class="fab fa-whatsapp mr-2" style="color:#25d366;"></i> Send via WhatsApp</div>
        <div class="fg"><label class="fl" style="color:#065f46;">Phone Number</label><input type="text" id="si_wa_phone" class="fc"></div>
        <div class="fg"><label class="fl" style="color:#065f46;">Message</label><textarea id="si_wa_msg" class="fc" style="height:120px;resize:vertical;"></textarea></div>
        <button type="button" onclick="sendScheduleWhatsApp()" class="btn-p" style="background:#25d366;color:#fff;"><i class="fab fa-whatsapp mr-1"></i> Save Schedule &amp; Open WhatsApp</button>
      </div>

      <div style="margin-top:16px;text-align:center;">
        <button type="button" onclick="saveAndDownloadIcs()" class="btn-p" style="background:#eef2ff;color:#3730a3;border:1px solid #c7d2fe;"><i class="fas fa-calendar-plus mr-1"></i> Save Schedule &amp; Add to Calendar</button>
        <div style="font-size:11px;color:var(--muted);margin-top:6px;">Downloads a calendar invite (.ics) with a 5-minute reminder — works with Google Calendar, Outlook, and phone calendars.</div>
      </div>
    </div>
  </div></div>
</div>

<script>
function startCalling(sid, btn) {
    var oldHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Checking...';
    
    $.getJSON(window.location.pathname, { ajax_check_tracking_duplicate: 1, screening_id: sid }, function(res) {
        if (res.duplicate) {
            btn.disabled = false;
            btn.innerHTML = oldHtml;
            showDuplicateWarningModal(sid, res, 'startCalling', btn, {});
        } else {
            doStartCalling(sid, btn, 0);
        }
    });
}

function doStartCalling(sid, btn, skipTracking) {
    var oldHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Starting...';
    $.post(window.location.pathname, { ajax_start_calling: 1, screening_id: sid, skip_tracking_creation: skipTracking }, function(resp) {
        if (resp.success) {
            $('#duplicateWarningModal').modal('hide');
            viewCandidate(sid); // reload the panel to show the new status block
        } else {
            alert('Error: ' + (resp.message || 'Could not start calling.'));
            btn.disabled = false;
            btn.innerHTML = oldHtml;
        }
    }, 'json').fail(function() {
        alert('Server error.');
        btn.disabled = false;
        btn.innerHTML = oldHtml;
    });
}

function openQuickCallingUpdate(sid) {
    window.location.href = '<?php echo BASE_URL; ?>/hrm/hr_candidate_tracking.php';
}

function copyText(elementId) {
    var el = document.getElementById(elementId);
    el.select();
    document.execCommand('copy');
    alert('Copied to clipboard!');
}

function generateLinkFromRound(sid, round_number, dept_id, pos_id) {
    var expiry = document.getElementById('expirySelect_' + sid).value;
    var custom = document.getElementById('expiryCustom_' + sid) ? document.getElementById('expiryCustom_' + sid).value : '';
    $.post(window.location.pathname, {
        ajax_generate_link_screening: 1,
        candidate_id: sid,
        round_number: round_number,
        department_id: dept_id,
        position_id: pos_id,
        expiry_hours: expiry,
        expiry_custom: custom
    }, function(resp) {
        if (resp.success) {
            loadInterviewRounds(sid, round_number);
        } else {
            alert('Error: ' + (resp.message || 'Could not generate link.'));
        }
    }, 'json');
}

function recalcAssignmentMarks(evalId, totalPossible) {
    var total = 0;
    document.querySelectorAll('[id^="hrmark_' + evalId + '_"]').forEach(function(sel) {
        var v = parseFloat(sel.value);
        if (!isNaN(v)) total += v;
    });
    var pct = totalPossible > 0 ? Math.round((total / totalPossible) * 100) : 0;
    var tm = document.getElementById('assignTotalMarks_' + evalId);
    var tp = document.getElementById('assignPct_' + evalId);
    if (tm) tm.textContent = total;
    if (tp) { tp.textContent = pct + '%'; tp.style.color = pct >= 90 ? '#10b981' : (pct >= 70 ? '#3b82f6' : '#ef4444'); }
}

function saveObservationStatus(evalId, sid, round_number, status) {
    var notesEl = document.getElementById('obsNotes_' + evalId);
    var notes = notesEl ? notesEl.value.trim() : '';

    if (status === 'not_completed' && !notes) {
        if (!confirm('No remarks entered. Are you sure you want to mark this as Not Completed?')) return;
    } else {
        var actionText = status === 'completed' ? 'Completed' : 'Not Completed';
        if (!confirm('Are you sure you want to mark this Observation Period as ' + actionText + '?')) return;
    }

    $.post(window.location.pathname, {
        ajax_save_observation_status: 1,
        eval_id: evalId,
        screening_id: sid,
        round_number: round_number,
        obs_status: status,
        obs_notes: notes
    }, function(resp) {
        if (resp.success) {
            loadInterviewRounds(sid, round_number);
        } else {
            alert('Error saving observation status.');
        }
    }, 'json');
}

function revertObservationStatus(evalId, sid, round_number) {
    if (!confirm('Are you sure you want to revert the Observation Period status? This will set it back to Pending.')) return;

    $.post(window.location.pathname, {
        ajax_revert_observation_status: 1,
        eval_id: evalId,
        screening_id: sid,
        round_number: round_number
    }, function(resp) {
        if (resp.success) {
            loadInterviewRounds(sid, round_number);
        } else {
            alert('Error reverting observation status.');
        }
    }, 'json');
}

function saveAssignmentMarks(evalId, sid, round_number, totalPossible) {
    var marks = {};
    document.querySelectorAll('[id^="hrmark_' + evalId + '_"]').forEach(function(sel) {
        var qid = sel.id.split('_')[2];
        marks[qid] = sel.value || 0;
    });
    var remarks = document.getElementById('assignRemarks_' + evalId);
    var notesVal = remarks ? remarks.value : '';

    $.post(window.location.pathname, {
        ajax_save_assignment_marks: 1,
        eval_id: evalId,
        screening_id: sid,
        round_number: round_number,
        total_possible: totalPossible,
        marks_json: JSON.stringify(marks),
        hr_notes: notesVal
    }, function(resp) {
        if (resp.success) {
            loadInterviewRounds(sid, round_number);
        } else {
            alert('Error saving marks.');
        }
    }, 'json');
}

function generateOnboardingLink(sid) {
    if(!confirm("Generate a new onboarding link for this candidate?")) return;
    var btn = event.currentTarget;
    var oldHtml = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Generating...';
    btn.disabled = true;
    $.post(window.location.pathname, {
        ajax_generate_onboarding_link: 1,
        candidate_id: sid
    }, function(resp) {
        if (resp.success) {
            location.reload();
        } else {
            alert('Error: ' + (resp.message || 'Could not generate link.'));
            btn.innerHTML = oldHtml;
            btn.disabled = false;
        }
    }, 'json').fail(function() {
        alert("Server error.");
        btn.innerHTML = oldHtml;
        btn.disabled = false;
    });
}

// ---- ASSIGNMENT INLINE ACTIONS ----
function generateWorksampleLink(sid, round, dept_id, pos_id) {
    var expiry = document.getElementById('wsExpirySelect_' + sid).value;
    $.post(window.location.pathname, {
        ajax_generate_link_screening: 1, candidate_id: sid, round_number: round,
        department_id: dept_id, position_id: pos_id, expiry_hours: expiry, submission_type: 'file_upload'
    }, function(resp) {
        if (resp.success) loadInterviewRounds(sid, round);
        else alert('Error generating link.');
    }, 'json');
}

function sendWorksampleWa(sid) {
    var phone = document.getElementById('wsWaPhone_' + sid).value.replace(/[^0-9]/g, '');
    var msg = encodeURIComponent(document.getElementById('wsWaMsg_' + sid).value);
    if (!phone) { alert('Please enter a phone number.'); return; }
    window.open('https://wa.me/' + phone + '?text=' + msg, '_blank');
}

function sendWorksampleEmail(btn, sid) {
    var to = document.getElementById('wsEmailTo_' + sid).value.trim();
    var subj = document.getElementById('wsEmailSubj_' + sid).value.trim();
    var body = document.getElementById('wsEmailBody_' + sid).value.trim();
    var alertBox = document.getElementById('wsEmailAlert_' + sid);
    if (!to) { alertBox.innerHTML = 'Recipient required.'; return; }
    var oldHtml = btn.innerHTML;
    btn.innerHTML = 'Sending...'; btn.disabled = true;
    $.post(window.location.pathname, { ajax_send_assignment_email: 1, to: to, subject: subj, body: body, sid: sid }, function(resp) {
        btn.innerHTML = oldHtml; btn.disabled = false;
        alertBox.innerHTML = resp.success ? '<span style="color:#065f46;">Sent!</span>' : '<span style="color:#991b1b;">' + (resp.message||'Failed') + '</span>';
    }, 'json');
}

function saveWorksampleRating(evalId, sid, round) {
    var rating = document.getElementById('wsRating_' + evalId).value;
    var notes = document.getElementById('wsNotes_' + evalId).value;
    if (!rating) { alert('Please select a rating.'); return; }
    $.post(window.location.pathname, {
        ajax_save_worksample_rating: 1, eval_id: evalId, screening_id: sid, round_number: round, rating: rating, notes: notes
    }, function(resp) {
        if (resp.success) loadInterviewRounds(sid, round);
        else alert('Error saving rating.');
    }, 'json');
}

// ---- ASSIGNMENT INLINE ACTIONS ----
function sendAssignWaInline(sid) {
    var phone = document.getElementById('waPhone_' + sid).value.replace(/[^0-9]/g, '');
    var msg = encodeURIComponent(document.getElementById('waMsg_' + sid).value);
    if (!phone) {
        alert('Please provide a valid phone number.');
        return;
    }
    window.open('https://wa.me/' + phone + '?text=' + msg, '_blank');
}

function sendAssignEmailInline(btn, sid) {
    var to       = document.getElementById('emailTo_' + sid).value.trim();
    var subject  = document.getElementById('emailSubj_' + sid).value.trim();
    var body     = document.getElementById('emailBody_' + sid).value.trim();
    var alertBox = document.getElementById('emailAlert_' + sid);

    if (!to) {
        alertBox.innerHTML = '<div style="background:#fee2e2;padding:10px;border-radius:8px;color:#991b1b;font-weight:700;font-size:13px;">Please enter a recipient email address.</div>';
        return;
    }

    var oldHtml = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Sending...';
    btn.disabled = true;
    alertBox.innerHTML = '';

    $.post(window.location.pathname, {
        ajax_send_assignment_email: 1,
        to: to,
        subject: subject,
        body: body,
        sid: sid
    }, function(resp) {
        btn.innerHTML = oldHtml;
        btn.disabled = false;
        if (resp.success) {
            alertBox.innerHTML = '<div style="background:#dcfce7;padding:10px;border-radius:8px;color:#065f46;font-weight:700;font-size:13px;"><i class="fas fa-check-circle mr-1"></i>Email sent successfully!</div>';
        } else {
            alertBox.innerHTML = '<div style="background:#fee2e2;padding:10px;border-radius:8px;color:#991b1b;font-weight:700;font-size:13px;"><i class="fas fa-exclamation-circle mr-1"></i>' + (resp.message || 'Failed to send.') + '</div>';
            console.error("Mail Debug:", resp.debug);
        }
    }, 'json').fail(function() {
        btn.innerHTML = oldHtml;
        btn.disabled = false;
        alertBox.innerHTML = '<div style="background:#fee2e2;padding:10px;border-radius:8px;color:#991b1b;font-weight:700;font-size:13px;">Server error. Please retry.</div>';
    });
}

/* ============================================================
   REPLACE the existing openRoundNotifyModal function with this
   (adds rn_phone_display field population)
   ============================================================ */
function openRoundNotifyModal(sid, round_req, cand_name, cand_email, cand_phone, cand_pos, is_pass) {
    document.getElementById('rn_sid').value = sid;
    document.getElementById('rn_round').value = round_req;
    document.getElementById('rn_phone').value = cand_phone;
    document.getElementById('rn_context').value = 'congrats';
    var phoneDisplay = document.getElementById('rn_phone_display');
    if (phoneDisplay) phoneDisplay.value = cand_phone || '';

    var subj, msg;

    // round_req is only ever 0 when this is called from the Document
    // Verification / Offer panel — every interview round always passes its
    // real round number (1, 2, 3...). So this branch is scoped exclusively
    // to the document verification stage.
    if (round_req == 0) {
        subj = "Document Verification Complete — " + cand_pos;
        msg = "Hi " + cand_name + ",\n\n" +
            "Congratulations! Your document verification for the " + cand_pos + " position has been completed successfully.\n\n" +
            "Our HR team will share your offer letter with you shortly. Please keep an eye on your email/WhatsApp for further updates.\n\n" +
            "Warm Regards,\nHR Team";
    } else if (is_pass) {
        subj = "Interview Update — " + cand_pos;
        msg = "Hi " + cand_name + ",\n\n" +
            "Congratulations on successfully completing Round " + round_req + " of the interview process for the " + cand_pos + " position!\n\n" +
            "You have been shortlisted for the next stage. Please be prepared for the upcoming round.\n\n" +
            "We will be reaching out to you shortly with more details.\n\nWarm Regards,\nHR Team";
    } else {
        subj = "Interview Update — " + cand_pos;
        msg = "Hi " + cand_name + ",\n\n" +
            "Thank you for participating in Round " + round_req + " of the interview process for the " + cand_pos + " position.\n\n" +
            "We will be in touch with you soon regarding the outcome and next steps.\n\nWarm Regards,\nHR Team";
    }

    document.getElementById('rn_email_to').value = cand_email;
    document.getElementById('rn_email_subj').value = subj;
    document.getElementById('rn_email_body').value = msg;
    document.getElementById('rn_wa_msg').value = msg;
    document.getElementById('rn_wa_container').style.display = 'block';

    $('#roundNotifyModal').modal('show');
}

function openRejectionNotifyModal(sid, round_req, cand_name, cand_email, cand_phone, cand_pos) {
    document.getElementById('rn_sid').value = sid;
    document.getElementById('rn_round').value = round_req || 0;
    document.getElementById('rn_phone').value = cand_phone;
    document.getElementById('rn_context').value = 'reject';
    var phoneDisplay = document.getElementById('rn_phone_display');
    if (phoneDisplay) phoneDisplay.value = cand_phone || '';

    var subj = "Application Update — " + cand_pos;
    var msg = "Dear " + cand_name + ",\n\n" +
        "Thank you for taking the time to participate in our selection process for the " + cand_pos + " role and for sharing your skills and experience with us.\n\n" +
        "After careful consideration, we have decided not to move forward with your application at this stage. This decision does not reflect a lack of merit on your part — we simply had to make a difficult choice among several strong candidates.\n\n" +
        "We truly appreciate the effort you put into the process and encourage you to apply for future opportunities with us that match your profile.\n\n" +
        "Wishing you all the best in your career ahead.\n\n" +
        "Warm Regards,\nHR Team";

    document.getElementById('rn_email_to').value = cand_email;
    document.getElementById('rn_email_subj').value = subj;
    document.getElementById('rn_email_body').value = msg;
    document.getElementById('rn_wa_msg').value = msg;
    document.getElementById('rn_wa_container').style.display = 'block';

    $('#roundNotifyModal').modal('show');
}

function sendRoundEmail() {
    var sid = document.getElementById('rn_sid').value;
    var round = document.getElementById('rn_round').value;
    var to = document.getElementById('rn_email_to').value.trim();
    var subj = document.getElementById('rn_email_subj').value.trim();
    var body = document.getElementById('rn_email_body').value.trim();
    var context = document.getElementById('rn_context').value;

    if (!to) { alert('Recipient email is required.'); return; }
    if (!confirm('Are you sure you want to send this email to ' + to + '?')) return;

    var btn = event.currentTarget;
    var oldHtml = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Sending...';
    btn.disabled = true;

    $.post(window.location.pathname, {
        ajax_send_round_email: 1,
        to: to,
        subject: subj,
        body: body,
        sid: sid,
        round: round,
        notify_type: context
    }, function(resp) {
        if (resp.success) {
            showToast('Email sent successfully!');
            closeRoundNotifyModalSafely();
            setTimeout(function(){ location.reload(); }, 500);
        } else {
            showToast(resp.message || 'Could not send email.', true);
        }
    }, 'json').fail(function() {
        showToast('Server error while sending email.', true);
    }).always(function() {
        btn.innerHTML = oldHtml;
        btn.disabled = false;
    });
}

/* ============================================================
   REPLACE the existing openRoundWhatsApp function with this
   (reads from editable phone field instead of hidden input)
   ============================================================ */
function openRoundWhatsApp() {
    var phoneEl = document.getElementById('rn_phone_display');
    var phone = phoneEl ? phoneEl.value.replace(/[^0-9]/g, '') : document.getElementById('rn_phone').value.replace(/[^0-9]/g, '');
    var msg = document.getElementById('rn_wa_msg').value;
    var sid = document.getElementById('rn_sid').value;
    var round = document.getElementById('rn_round').value;
    var context = document.getElementById('rn_context').value;
    if (!phone) { alert('Invalid phone number.'); return; }
    window.open('https://wa.me/' + phone + '?text=' + encodeURIComponent(msg), '_blank');
    closeRoundNotifyModalSafely();
    if (context === 'congrats' && sid && round) {
        $.post(window.location.pathname, { ajax_mark_round_notified: 1, sid: sid, round: round }, function() {
            loadInterviewRounds(sid, round);
        }, 'json');
    }
}

/* ===================== PRE-ROUND INTERVIEW SCHEDULING ===================== */
function openScheduleInterviewModal(sid, round, name, email, phone, pos, existingDatetime) {
    document.getElementById('si_sid').value = sid;
    document.getElementById('si_round').value = round;

    var dtInput = document.getElementById('si_datetime');
    dtInput.value = existingDatetime ? existingDatetime.replace(' ', 'T').substring(0, 16) : '';
    document.getElementById('si_end_datetime').value = '';

    document.getElementById('si_email_to').value = email || '';
    document.getElementById('si_wa_phone').value = phone || '';
    document.getElementById('si_email_alert').innerHTML = '';

    // Reset interview mode fields to default (Virtual) each time the modal opens
    document.querySelector('input[name="si_mode"][value="virtual"]').checked = true;
    document.getElementById('si_meeting_link').value = '';
    document.getElementById('si_address').value = 'Abra Group, 209, 2nd Main Rd, East of NGEF Layout, Kasturi Nagar, Bengaluru, Karnataka 560043';
    toggleInterviewModeFields();

    // Store name/pos globally so the meeting-link/address input listeners can regenerate the message
    window._si_name = name;
    window._si_pos = pos;

    dtInput.onchange = function() { updateScheduleMessages(name, pos); };
    updateScheduleMessages(name, pos);

    $('#scheduleInterviewModal').modal('show');
}

function toggleInterviewModeFields() {
    var mode = document.querySelector('input[name="si_mode"]:checked').value;
    document.getElementById('si_virtual_wrap').style.display = (mode === 'virtual') ? 'block' : 'none';
    document.getElementById('si_address_wrap').style.display = (mode === 'face_to_face') ? 'block' : 'none';
    updateScheduleMessages(window._si_name, window._si_pos);
}

function formatScheduleDateTime() {
    var dtVal = document.getElementById('si_datetime').value;
    if (!dtVal) return '[Date & Time to be confirmed]';
    var d = new Date(dtVal);
    var options = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' };
    return d.toLocaleString('en-IN', options);
}

function updateScheduleMessages(name, pos) {
    var round = document.getElementById('si_round').value;
    var dtDisplay = formatScheduleDateTime();
    var modeEl = document.querySelector('input[name="si_mode"]:checked');
    var mode = modeEl ? modeEl.value : 'virtual';

    var subj, msg;

    if (mode === 'assignment') {
        subj = "Assignment Round Invitation — Round " + round + " — " + pos;
        msg = "Hi " + name + ",\n\nCongratulations! You have been shortlisted for Round " + round + " — Assignment Round — for the " + pos + " position.\n\nDeadline: " + dtDisplay + "\n\nPlease complete your assignment before the deadline. We look forward to reviewing your submission." + "\n\nWarm Regards,\nHR Team";
    } else if (mode === 'observation') {
        subj = "Observation Round Invitation — Round " + round + " — " + pos;
        msg = "Hi " + name + ",\n\nCongratulations! You have been shortlisted for Round " + round + " — Observation Round — for the " + pos + " position.\n\nObservation Period Starts: " + dtDisplay + "\n\nOur team will be observing your performance during this period. We look forward to working with you." + "\n\nWarm Regards,\nHR Team";
    } else if (mode === 'document_verification') {
        subj = "Document Verification — Round " + round + " — " + pos;
        msg = "Hi " + name + ",\n\nCongratulations! You have been shortlisted for Round " + round + " — Document Verification — for the " + pos + " position.\n\nScheduled for: " + dtDisplay + "\n\nPlease keep your original documents ready for verification. We look forward to seeing you." + "\n\nWarm Regards,\nHR Team";
    } else {
        subj = "Interview Invitation — Round " + round + " — " + pos;
        var modeLine = '';
        if (mode === 'virtual') {
            var link = document.getElementById('si_meeting_link').value.trim();
            modeLine = "Mode: Virtual Interview\nMeeting Link: " + (link || '[Meeting link to be shared]');
        } else {
            var addr = document.getElementById('si_address').value.trim();
            modeLine = "Mode: Face to Face Interview\nVenue: " + (addr || '[Address to be confirmed]');
        }
        msg = "Hi " + name + ",\n\nWe are pleased to invite you for Round " + round + " of the interview process for the " + pos + " position.\n\nDate & Time: " + dtDisplay + "\n" + modeLine + "\n\nPlease be available at the scheduled time. We look forward to speaking with you." + "\n\nWarm Regards,\nHR Team";
    }

    document.getElementById('si_email_subj').value = subj;
    document.getElementById('si_email_body').value = msg;
    document.getElementById('si_wa_msg').value = msg;
}

function saveInterviewSchedule(callback) {
    var sid = document.getElementById('si_sid').value;
    var round = document.getElementById('si_round').value;
    var dtVal = document.getElementById('si_datetime').value;
    var endVal = document.getElementById('si_end_datetime').value;

    if (!dtVal) { showHrAlert('Please select an interview date & time.', 'warn'); return; }
    if (endVal && endVal <= dtVal) { showHrAlert('End time must be after the start time.', 'warn'); return; }

    $.post(window.location.pathname, {
        ajax_save_interview_schedule: 1,
        screening_id: sid,
        round_number: round,
        scheduled_datetime: dtVal.replace('T', ' ') + ':00',
        scheduled_end_datetime: endVal ? (endVal.replace('T', ' ') + ':00') : ''
    }, function(resp) {
        if (resp.success && typeof callback === 'function') callback();
        else if (!resp.success) showHrAlert(resp.message || 'Could not save schedule.', 'err', 'Scheduling Conflict');
    }, 'json');
}

function saveAndDownloadIcs() {
    var sid = document.getElementById('si_sid').value;
    var round = document.getElementById('si_round').value;
    saveInterviewSchedule(function() {
        window.open(window.location.pathname + '?ajax_download_ics=1&screening_id=' + sid + '&round_number=' + round, '_blank');
    });
}

// Fixes the Bootstrap nested-modal issue globally: closing ANY modal while another
// modal is still open behind it strips body.modal-open / removes the backdrop,
// leaving the page stuck. This tracks how many modals are actually open and
// repairs body/backdrop state accordingly — works for any modal, any nesting depth.
(function() {
    var openModalStack = [];

    $(document).on('show.bs.modal', '.modal', function() {
        if (openModalStack.indexOf(this.id) === -1) {
            openModalStack.push(this.id);
        }
    });

    $(document).on('shown.bs.modal', '.modal', function() {
        var depth = openModalStack.length;
        var zBase = 1040 + (depth * 20);
        $(this).css('z-index', zBase + 10);
        $('.modal-backdrop').last().css('z-index', zBase);
    });

    $(document).on('hidden.bs.modal', '.modal', function() {
        var idx = openModalStack.indexOf(this.id);
        if (idx > -1) openModalStack.splice(idx, 1);

        if (openModalStack.length > 0) {
            $('body').addClass('modal-open');

            while ($('.modal-backdrop').length < openModalStack.length) {
                $('body').append('<div class="modal-backdrop fade show"></div>');
            }
            while ($('.modal-backdrop').length > openModalStack.length) {
                $('.modal-backdrop').first().remove();
            }

            var topId = openModalStack[openModalStack.length - 1];
            var depth = openModalStack.length;
            var zBase = 1040 + (depth * 20);
            $('#' + topId).css('z-index', zBase + 10);
            $('.modal-backdrop').last().css('z-index', zBase);
        }
    });
})();

function closeScheduleModalSafely() {
    if (document.activeElement) document.activeElement.blur();
    $('#scheduleInterviewModal').modal('hide');
}

function closeRoundNotifyModalSafely() {
    if (document.activeElement) document.activeElement.blur();
    $('#roundNotifyModal').modal('hide');
}

function sendScheduleEmail() {
    var to = document.getElementById('si_email_to').value.trim();
    var subj = document.getElementById('si_email_subj').value.trim();
    var body = document.getElementById('si_email_body').value.trim();
    var sid = document.getElementById('si_sid').value;
    var round = document.getElementById('si_round').value;
    var alertBox = document.getElementById('si_email_alert');

    if (!to) { alertBox.innerHTML = '<div style="background:#fee2e2;padding:8px;border-radius:6px;color:#991b1b;font-size:12px;">Recipient email required.</div>'; return; }

    saveInterviewSchedule(function() {
        $.post(window.location.pathname, {
            ajax_send_interview_schedule_email: 1,
            to: to, subject: subj, body: body, sid: sid, round: round
        }, function(resp) {
            if (resp.success) {
                alertBox.innerHTML = '<div style="background:#dcfce7;padding:8px;border-radius:6px;color:#065f46;font-size:12px;">Email sent and schedule saved!</div>';
                setTimeout(function(){ closeScheduleModalSafely(); loadInterviewRounds(sid, round); }, 900);
            } else {
                alertBox.innerHTML = '<div style="background:#fee2e2;padding:8px;border-radius:6px;color:#991b1b;font-size:12px;">' + (resp.message || 'Failed to send.') + '</div>';
            }
        }, 'json');
    });
}

function sendScheduleWhatsApp() {
    var phone = document.getElementById('si_wa_phone').value.replace(/[^0-9]/g, '');
    var msg = document.getElementById('si_wa_msg').value;
    var sid = document.getElementById('si_sid').value;
    var round = document.getElementById('si_round').value;

    if (!phone) { alert('Please enter a valid phone number.'); return; }

    saveInterviewSchedule(function() {
        $.post(window.location.pathname, { ajax_mark_schedule_notified: 1, screening_id: sid, round_number: round }, function() {
            closeScheduleModalSafely();
            loadInterviewRounds(sid, round);
        }, 'json');
        window.open('https://wa.me/' + phone + '?text=' + encodeURIComponent(msg), '_blank');
    });
}
/* =================== END PRE-ROUND INTERVIEW SCHEDULING =================== */

function showToast(msg, isError) {
    var tc = document.getElementById('toastCard');
    if(!tc) return alert(msg);
    var ti = document.getElementById('toastIcon');
    var tt = document.getElementById('toastText');
    tc.className = 'toast-card ' + (isError ? 'error' : '') + ' show';
    ti.className = isError ? 'fas fa-exclamation-circle toast-icon' : 'fas fa-check-circle toast-icon';
    tt.innerHTML = msg;
    setTimeout(function() { tc.classList.remove('show'); }, 3500);
}
</script>

<!-- Toast Card -->
<div id="toastCard" class="toast-card">
    <i id="toastIcon" class="fas fa-check-circle toast-icon"></i>
    <div id="toastText" class="toast-text">Message</div>
</div>

<!-- Reject Candidate Modal (round-level or overall) -->
<div class="modal fade" id="rejectCandidateModal" tabindex="-1" style="z-index:99999;">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content" style="border-radius:14px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.3);">
      <div class="modal-body" style="padding:28px;">
        <input type="hidden" id="rej_sid">
        <input type="hidden" id="rej_round_number">
        <input type="hidden" id="rej_round_name">
        <input type="hidden" id="rej_round_type">
        <input type="hidden" id="rej_cand_name">
        <input type="hidden" id="rej_cand_email">
        <input type="hidden" id="rej_cand_phone">
        <input type="hidden" id="rej_cand_pos">

        <div id="rejStep1">
          <h5 style="font-weight:800;color:#991b1b;margin-bottom:6px;">
            <i class="fas fa-times-circle mr-2"></i>Reject Candidate
          </h5>
          <p style="font-size:13px;color:#64748b;margin-bottom:16px;" id="rejStepSubtitle">Please provide a reason for rejection.</p>
          <div style="margin-bottom:18px;">
            <label style="font-size:12px;font-weight:700;color:#0f2557;display:block;margin-bottom:6px;">Rejection Reason *</label>
            <textarea id="rejReasonTxt" style="width:100%;padding:10px 13px;border:2px solid #fecaca;border-radius:9px;font-family:inherit;font-size:13px;resize:vertical;height:100px;" placeholder="e.g. Did not meet the required technical skills for this role..."></textarea>
          </div>
          <div style="display:flex;gap:10px;justify-content:flex-end;">
            <button onclick="$('#rejectCandidateModal').modal('hide')" style="padding:10px 20px;border:2px solid #e0e7ff;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;">Cancel</button>
            <button onclick="goToRejectStep2()" style="padding:10px 24px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">
              <i class="fas fa-arrow-right mr-1"></i> Continue
            </button>
          </div>
        </div>

        <div id="rejStep2" style="display:none;">
          <h5 style="font-weight:800;color:#0f2557;margin-bottom:6px;">
            <i class="fas fa-database mr-2" style="color:#1a3fc4;"></i>Keep Candidate in Database?
          </h5>
          <p style="font-size:13px;color:#64748b;margin-bottom:20px;">Do you want to keep this candidate's profile in the database, or remove it completely? This cannot be undone.</p>
          <div style="display:flex;gap:10px;justify-content:flex-end;flex-wrap:wrap;">
            <button onclick="goToRejectStep1()" style="padding:10px 18px;border:2px solid #e0e7ff;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;"><i class="fas fa-arrow-left mr-1"></i> Back</button>
            <button onclick="finalizeRejection(0)" id="rejDeleteBtn" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-trash-alt mr-1"></i> No, Remove Completely</button>
            <button onclick="finalizeRejection(1)" id="rejKeepBtn" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#1a3fc4,#1d4ed8);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;"><i class="fas fa-check mr-1"></i> Yes, Keep in Database</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
function openRejectModal(sid, round_number, round_name, round_type) {
    document.getElementById('rej_sid').value = sid;
    document.getElementById('rej_round_number').value = round_number || 0;
    document.getElementById('rej_round_name').value = round_name || 'Overall';
    document.getElementById('rej_round_type').value = round_type || 'overall';
    document.getElementById('rejReasonTxt').value = '';
    document.getElementById('rejStepSubtitle').textContent = round_number > 0
        ? ('Rejecting candidate at: ' + round_name)
        : 'Rejecting this candidate overall.';

    $.getJSON(window.location.pathname, { ajax_get_candidate_contact: 1, screening_id: sid }, function(res) {
        if (res.success) {
            document.getElementById('rej_cand_name').value  = res.name || '';
            document.getElementById('rej_cand_email').value = res.email || '';
            document.getElementById('rej_cand_phone').value = res.phone || '';
            document.getElementById('rej_cand_pos').value   = res.position || '';
        }
    });

    goToRejectStep1();
    $('#rejectCandidateModal').modal('show');
}

function goToRejectStep1() {
    document.getElementById('rejStep1').style.display = 'block';
    document.getElementById('rejStep2').style.display = 'none';
}

function goToRejectStep2() {
    var reason = document.getElementById('rejReasonTxt').value.trim();
    if (!reason) { alert('Please enter a reason for rejection.'); return; }
    document.getElementById('rejStep1').style.display = 'none';
    document.getElementById('rejStep2').style.display = 'block';
}

function finalizeRejection(keepInDb) {
    var sid          = document.getElementById('rej_sid').value;
    var round_number = document.getElementById('rej_round_number').value;
    var round_name   = document.getElementById('rej_round_name').value;
    var round_type   = document.getElementById('rej_round_type').value;
    var reason       = document.getElementById('rejReasonTxt').value.trim();

    var keepBtn = document.getElementById('rejKeepBtn');
    var delBtn  = document.getElementById('rejDeleteBtn');
    keepBtn.disabled = true; delBtn.disabled = true;
    var activeBtn = keepInDb ? keepBtn : delBtn;
    var oldHtml = activeBtn.innerHTML;
    activeBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';

    $.post(window.location.pathname, {
        ajax_process_rejection: 1,
        screening_id: sid,
        round_number: round_number,
        round_name: round_name,
        round_type: round_type,
        reason: reason,
        keep_in_db: keepInDb
    }, function(resp) {
        keepBtn.disabled = false; delBtn.disabled = false;
        activeBtn.innerHTML = oldHtml;
        if (resp.success) {
            $('#rejectCandidateModal').modal('hide');
            if (resp.deleted) {
                $('#candidateModal').modal('hide');
                var row = document.getElementById('row_' + sid);
                if (row) row.remove();
                showToast('Candidate rejected and removed from the database.');
            } else {
                showToast('Candidate rejected.');
                if (round_number > 0) {
                    loadInterviewRounds(sid, round_number);
                } else {
                    viewCandidate(sid);
                }
            }
        } else {
            alert('Error: ' + (resp.message || 'Could not process rejection.'));
        }
    }, 'json').fail(function() {
        keepBtn.disabled = false; delBtn.disabled = false;
        activeBtn.innerHTML = oldHtml;
        alert('Server error while processing rejection.');
    });
}
</script>

<!-- Duplicate Warning Modal -->
<div class="modal fade" id="duplicateWarningModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header" style="background:var(--danger);color:#fff;">
                <h5 class="modal-title"><i class="fas fa-exclamation-triangle mr-2"></i>Possible Duplicate Candidate</h5>
                <button type="button" class="close" data-dismiss="modal" style="color:#fff;">&times;</button>
            </div>
            <div class="modal-body">
                <p>A candidate with this phone/email already exists in the tracking system for this department and position:</p>
                <div style="background:#fff7ed;border:1px solid #fcd34d;padding:12px;border-radius:8px;margin-bottom:15px;color:#92400e;">
                    <strong>Name:</strong> <span id="dupCandName"></span><br>
                    <strong>ID:</strong> <span id="dupCandId"></span><br>
                    <strong>Status:</strong> <span id="dupCandStatus"></span><br>
                    <strong>Added on:</strong> <span id="dupCandDate"></span>
                </div>
                <p>Do you want to link this screening to that existing entry, or skip tracking for now?</p>
            </div>
            <div class="modal-footer" style="display:flex;gap:10px;justify-content:flex-end;">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
                <button type="button" id="btnSkipTracking" style="padding:10px 20px;border:2px solid #e0e7ff;border-radius:8px;background:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;color:#64748b;">
                    <i class="fas fa-forward mr-1"></i> Skip — Don't Track
                </button>
                <button type="button" id="btnLinkTracking" style="padding:10px 20px;border:none;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;">
                    <i class="fas fa-link mr-1"></i> Link to Existing Entry
                </button>
            </div>
        </div>
    </div>
</div>

<!-- Custom Alert Overlay — replaces native browser alert() with a styled card -->
<div id="hrsAlertOverlay" class="hrs-alert-overlay">
    <div class="hrs-alert-card">
        <div id="hrsAlertIcon" class="hrs-alert-icon err"><i class="fas fa-exclamation-circle"></i></div>
        <div id="hrsAlertTitle" class="hrs-alert-title">Notice</div>
        <div id="hrsAlertText" class="hrs-alert-text"></div>
        <button type="button" class="hrs-alert-btn" onclick="document.getElementById('hrsAlertOverlay').classList.remove('show')">OK</button>
    </div>
</div>
<script>
function showHrAlert(message, type, title) {
    var overlay = document.getElementById('hrsAlertOverlay');
    var icon = document.getElementById('hrsAlertIcon');
    var titleEl = document.getElementById('hrsAlertTitle');
    var textEl = document.getElementById('hrsAlertText');
    type = type || 'err';
    icon.className = 'hrs-alert-icon ' + type;
    icon.innerHTML = type === 'warn' ? '<i class="fas fa-exclamation-triangle"></i>' : '<i class="fas fa-exclamation-circle"></i>';
    titleEl.textContent = title || (type === 'warn' ? 'Heads Up' : 'Notice');
    textEl.textContent = message;
    overlay.classList.add('show');
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
<?php if (ob_get_level() > 0) { ob_end_flush(); } ?>