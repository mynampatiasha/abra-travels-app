<?php
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

// =========================================================================
// HR SCREENING ROUNDS CONFIGURATION (KPQ)
// =========================================================================

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

$con = conexion();
if (!$con) {
    die("Database connection failed: " . mysqli_connect_error());
}

// Cleans up text pulled from an uploaded CSV cell. Copy-pasting question/round
// text out of Word or Excel commonly leaves "smart quote" characters encoded as
// raw Windows-1252 bytes instead of proper UTF-8 — those bytes are invalid UTF-8,
// and this file doesn't disable mysqli's default error mode, so a query built
// from one bad row throws an uncaught exception and kills the whole import
// (everything after that row, plus a 500 for the request). This repairs the
// common case and, failing that, strips anything unsalvageable instead of
// letting it take the whole import down.
function sanitizeImportText($str) {
    $str = trim((string)$str);
    if ($str === '' || mb_check_encoding($str, 'UTF-8')) return $str;
    $converted = @iconv('Windows-1252', 'UTF-8//IGNORE', $str);
    if ($converted !== false && $converted !== '') return $converted;
    return mb_convert_encoding($str, 'UTF-8', 'UTF-8');
}

if (isset($_GET['update_db'])) {
    $queries = [
        "ALTER TABLE hr_screening_rounds ADD COLUMN position_id INT(11) DEFAULT 0 AFTER department_id",
        "ALTER TABLE hr_screening_questions ADD COLUMN position_id INT(11) DEFAULT 0 AFTER department_id",
        "ALTER TABLE hr_screenings ADD COLUMN position_id INT(11) DEFAULT 0 AFTER department",
        "ALTER TABLE hr_screening_evaluations ADD COLUMN position_id INT(11) DEFAULT 0 AFTER department_id",
        "ALTER TABLE hr_screening_rounds ADD COLUMN round_type VARCHAR(20) DEFAULT 'interview' AFTER round_name",
        "ALTER TABLE hr_screening_rounds ADD COLUMN observation_days INT(11) DEFAULT 0 AFTER round_type"
    ];
    echo "Starting DB Update...<br>";
    foreach ($queries as $q) {
        try {
            if (mysqli_query($con, $q)) {
                echo "SUCCESS: $q <br>";
            } else {
                echo "FAILED: $q - " . mysqli_error($con) . "<br>";
            }
        } catch (Exception $e) {
            echo "EXCEPTION: " . $e->getMessage() . "<br>";
        }
    }
    echo "DB Update Script Finished!";
    exit;
}

// --- ENSURE TABLES EXIST ---
// Table: hr_screening_rounds
$check_rounds = mysqli_query($con, "SHOW TABLES LIKE 'hr_screening_rounds'");
if(mysqli_num_rows($check_rounds) == 0) {
    mysqli_query($con, "CREATE TABLE hr_screening_rounds (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL,
        round_number INT(11) NOT NULL,
        round_name VARCHAR(255) NOT NULL,
        round_type VARCHAR(20) DEFAULT 'interview',
        observation_days INT(11) DEFAULT 0,
        created_by VARCHAR(255) DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )");
}

// --- ENSURE round_type / observation_days EXIST on already-created tables ---
$rc_check = mysqli_query($con, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='hr_screening_rounds'");
$rc_cols = [];
while ($rc = mysqli_fetch_assoc($rc_check)) $rc_cols[] = $rc['COLUMN_NAME'];
if (!in_array('round_type', $rc_cols))       mysqli_query($con, "ALTER TABLE hr_screening_rounds ADD COLUMN round_type VARCHAR(20) DEFAULT 'interview' AFTER round_name");
if (!in_array('observation_days', $rc_cols)) mysqli_query($con, "ALTER TABLE hr_screening_rounds ADD COLUMN observation_days INT(11) DEFAULT 0 AFTER round_type");

// Table: hr_screening_questions
$check_questions = mysqli_query($con, "SHOW TABLES LIKE 'hr_screening_questions'");
if(mysqli_num_rows($check_questions) == 0) {
    mysqli_query($con, "CREATE TABLE hr_screening_questions (
        id INT(11) AUTO_INCREMENT PRIMARY KEY,
        department_id INT(11) NOT NULL,
        round_number INT(11) NOT NULL,
        question_text TEXT NOT NULL,
        input_type VARCHAR(50) DEFAULT 'text',
        options_json TEXT DEFAULT NULL,
        marks INT(11) DEFAULT 10,
        is_active TINYINT(1) DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )");
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
isUser();

$current_page = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// --- AJAX: GET POSITIONS FOR MODAL ---
if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $positions_ajax = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) {
            while($r = mysqli_fetch_assoc($q)) $positions_ajax[] = $r;
        }
    }
    echo json_encode($positions_ajax);
    exit;
}

// Determine current view
$view = isset($_GET['view']) ? $_GET['view'] : 'rounds';
$selected_dept = isset($_GET['dept_id']) ? intval($_GET['dept_id']) : 0;
$selected_pos = isset($_GET['position_id']) ? intval($_GET['position_id']) : 0;

// round_number is now multi-select (array) on the Questions tab
$selected_rounds = isset($_GET['round_number']) ? array_map('intval', (array)$_GET['round_number']) : [];
$selected_rounds = array_values(array_filter($selected_rounds, function($v){ return $v > 0; }));
// $selected_round stays populated ONLY when exactly one round is selected
// (Add Question / Edit Question / Import redirect all need a single round context)
$selected_round = (count($selected_rounds) == 1) ? $selected_rounds[0] : 0;

// Fetch Positions for Selected Department
$positions = [];
if ($selected_dept > 0) {
    $pos_query = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id = $selected_dept ORDER BY title ASC");
    if ($pos_query) {
        while($p = mysqli_fetch_assoc($pos_query)) $positions[] = $p;
    }
}

// =========================================================================
// EXPORT CSV
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'GET' && isset($_GET['action']) && $_GET['action'] == 'export') {
    $export_view = isset($_GET['export_view']) ? $_GET['export_view'] : $view;
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=hr_' . $export_view . '_export_' . date('Y-m-d') . '.csv');
    $output = fopen('php://output', 'w');

    if ($export_view == 'rounds') {
        $where = [];
        if ($selected_dept > 0) $where[] = "r.department_id = $selected_dept";
        if ($selected_pos > 0)  $where[] = "r.position_id = $selected_pos";
        $where_sql = !empty($where) ? "WHERE " . implode(' AND ', $where) : '';

        fputcsv($output, ['Department Name', 'Position', 'Round Number', 'Round Name']);
        $exp_q = mysqli_query($con, "SELECT d.name as dept_name, p.title as pos_title, r.round_number, r.round_name
            FROM hr_screening_rounds r
            LEFT JOIN hr_departments d ON r.department_id = d.id
            LEFT JOIN hr_positions p ON r.position_id = p.id
            $where_sql
            ORDER BY d.name ASC, r.round_number ASC");
        while ($row = mysqli_fetch_assoc($exp_q)) {
            fputcsv($output, [$row['dept_name'], $row['pos_title'] ?: '—', $row['round_number'], $row['round_name']]);
        }
    } elseif ($export_view == 'questions') {
        $where = [];
        if ($selected_dept > 0) $where[] = "q.department_id = $selected_dept";
        if ($selected_pos > 0)  $where[] = "q.position_id = $selected_pos";
        if (!empty($selected_rounds)) {
            $rounds_in = implode(',', array_map('intval', $selected_rounds));
            $where[] = "q.round_number IN ($rounds_in)";
        }
        $where_sql = !empty($where) ? "WHERE " . implode(' AND ', $where) : '';

        fputcsv($output, ['Department Name', 'Position', 'Round Number', 'Question Text', 'Input Type', 'Options (comma separated)', 'Marks']);
        $exp_q = mysqli_query($con, "SELECT d.name as dept_name, p.title as pos_title, q.round_number, q.question_text, q.input_type, q.options_json, q.marks
            FROM hr_screening_questions q
            LEFT JOIN hr_departments d ON q.department_id = d.id
            LEFT JOIN hr_positions p ON q.position_id = p.id
            $where_sql
            ORDER BY d.name ASC, q.round_number ASC, q.id ASC");
        while ($row = mysqli_fetch_assoc($exp_q)) {
            $opts = !empty($row['options_json']) ? implode(', ', json_decode($row['options_json'], true) ?: []) : '';
            fputcsv($output, [$row['dept_name'], $row['pos_title'] ?: '—', $row['round_number'], $row['question_text'], $row['input_type'], $opts, $row['marks']]);
        }
    }
    fclose($output);
    exit;
}

// =========================================================================
// DOWNLOAD TEMPLATE CSV
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'GET' && isset($_GET['action']) && $_GET['action'] == 'download_template') { if (ob_get_level() > 0) { ob_clean(); }
    header('Content-Type: text/csv; charset=utf-8');
    
    $type = isset($_GET['type']) ? $_GET['type'] : 'questions';
    $output = fopen('php://output', 'w');
    
    if ($type == 'rounds') {
        header('Content-Disposition: attachment; filename=hr_rounds_import_template.csv');
        fputcsv($output, ['Round Number', 'Round Name', 'Round Type', 'Observation Days']);
        fputcsv($output, ['1', 'Technical Screening', 'interview', '']);
        fputcsv($output, ['2', 'Practical Task', 'assignment', '']);
        fputcsv($output, ['3', 'Onboarding Trial', 'observation', '30']);
    } else {
        header('Content-Disposition: attachment; filename=hr_questions_import_template.csv');
        fputcsv($output, ['Round Number', 'Question Text', 'Input Type', 'Options (CSV)', 'Marks']);
        fputcsv($output, ['1', 'What is your primary programming language?', 'select', 'PHP, Python, Java, C++', '10']);
        fputcsv($output, ['1', 'Explain your experience with REST APIs.', 'textarea', '', '15']);
        fputcsv($output, ['2', 'Where do you see yourself in 5 years?', 'text', '', '5']);
    }
    
    fclose($output);
    exit;
}

// =========================================================================
// HANDLE FORM SUBMISSIONS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    if (isset($_POST['action'])) {
        
        // --- ADD ROUND ---
        if ($_POST['action'] == 'add_round') {
            $dept_id = intval($_POST['department_id']);
            $pos_id = intval($_POST['position_id']);
            $round_num = intval($_POST['round_number']);
            $round_name = mysqli_real_escape_string($con, $_POST['round_name']);
            $round_type = mysqli_real_escape_string($con, $_POST['round_type'] ?? 'interview');
            $obs_days = intval($_POST['observation_days'] ?? 0);
            
            if ($dept_id > 0 && $round_num > 0 && !empty($round_name)) {
                mysqli_query($con, "INSERT INTO hr_screening_rounds (department_id, position_id, round_number, round_name, round_type, observation_days, created_by) VALUES ($dept_id, $pos_id, $round_num, '$round_name', '$round_type', $obs_days, '$currentUserName')");
                $_SESSION['success_message'] = "Round added successfully.";
            } else {
                $_SESSION['error_message'] = "Please fill all required fields.";
            }
            header("Location: $current_page?view=rounds&dept_id=$dept_id&position_id=$pos_id");
            exit;
        }

        // --- EDIT ROUND ---
        if ($_POST['action'] == 'edit_round') {
            $id = intval($_POST['id']);
            $dept_id = intval($_POST['department_id']);
            $pos_id = intval($_POST['position_id']);
            $round_num = intval($_POST['round_number']);
            $round_name = mysqli_real_escape_string($con, $_POST['round_name']);
            $round_type = mysqli_real_escape_string($con, $_POST['round_type'] ?? 'interview');
            $obs_days = intval($_POST['observation_days'] ?? 0);
            if ($id > 0 && $dept_id > 0 && $round_num > 0 && !empty($round_name)) {
                mysqli_query($con, "UPDATE hr_screening_rounds SET department_id=$dept_id, position_id=$pos_id, round_number=$round_num, round_name='$round_name', round_type='$round_type', observation_days=$obs_days WHERE id=$id");
                $_SESSION['success_message'] = "Round updated successfully.";
            } else {
                $_SESSION['error_message'] = "Please fill all required fields.";
            }
            header("Location: " . $_SERVER['HTTP_REFERER']);
            exit;
        }
        
        // --- ADD QUESTION ---
        if ($_POST['action'] == 'add_question') {
            $dept_id = intval($_POST['department_id']);
            $pos_id = intval($_POST['position_id']);
            $round_num = intval($_POST['round_number']);
            $question_text = mysqli_real_escape_string($con, $_POST['question_text']);
            $input_type = mysqli_real_escape_string($con, $_POST['input_type']);
            $marks = intval($_POST['marks']);
            
            $options_json = '';
            if ($input_type == 'select' || $input_type == 'radio') {
                 $options = explode(',', $_POST['options_csv']);
                 $clean_options = array_map('trim', $options);
                 $options_json = mysqli_real_escape_string($con, json_encode($clean_options));
            }
            
            if ($dept_id > 0 && $round_num > 0 && !empty($question_text)) {
                mysqli_query($con, "INSERT INTO hr_screening_questions (department_id, position_id, round_number, question_text, input_type, options_json, marks) VALUES ($dept_id, $pos_id, $round_num, '$question_text', '$input_type', '$options_json', $marks)");
                $_SESSION['success_message'] = "Question added successfully.";
            } else {
                $_SESSION['error_message'] = "Please fill all required fields.";
            }
            header("Location: $current_page?view=questions&dept_id=$dept_id&position_id=$pos_id&round_number=$round_num");
            exit;
        }

        // --- EDIT QUESTION ---
        if ($_POST['action'] == 'edit_question') {
            $id = intval($_POST['id']);
            $dept_id = intval($_POST['department_id']);
            $pos_id = intval($_POST['position_id']);
            $round_num = intval($_POST['round_number']);
            $question_text = mysqli_real_escape_string($con, $_POST['question_text']);
            $input_type = mysqli_real_escape_string($con, $_POST['input_type']);
            $marks = intval($_POST['marks']);
            
            $options_json = '';
            if ($input_type == 'select' || $input_type == 'radio') {
                 $options = explode(',', $_POST['options_csv']);
                 $clean_options = array_map('trim', $options);
                 $options_json = mysqli_real_escape_string($con, json_encode($clean_options));
            }
            
            if ($id > 0 && $dept_id > 0 && $round_num > 0 && !empty($question_text)) {
                mysqli_query($con, "UPDATE hr_screening_questions SET question_text='$question_text', input_type='$input_type', options_json='$options_json', marks=$marks WHERE id=$id");
                $_SESSION['success_message'] = "Question updated successfully.";
            } else {
                $_SESSION['error_message'] = "Please fill all required fields.";
            }
            $redirect_rounds = isset($_POST['filter_rounds']) ? array_map('intval', (array)$_POST['filter_rounds']) : [$round_num];
            $redirect_url = "$current_page?view=questions&dept_id=$dept_id&position_id=$pos_id";
            foreach ($redirect_rounds as $rr) { if ($rr > 0) $redirect_url .= "&round_number[]=" . $rr; }
            header("Location: $redirect_url");
            exit;
        }
        
        // --- DELETE ROUND ---
        if ($_POST['action'] == 'delete_round') {
            $id = intval($_POST['id']);
            mysqli_query($con, "DELETE FROM hr_screening_rounds WHERE id = $id");
            // Optionally delete associated questions
            // mysqli_query($con, "DELETE FROM hr_screening_questions WHERE department_id = ... AND round_number = ...");
            $_SESSION['success_message'] = "Round deleted successfully.";
            header("Location: " . $_SERVER['HTTP_REFERER']);
            exit;
        }

        // --- DELETE QUESTION ---
        if ($_POST['action'] == 'delete_question') {
            $id = intval($_POST['id']);
            mysqli_query($con, "DELETE FROM hr_screening_questions WHERE id = $id");
            $_SESSION['success_message'] = "Question deleted successfully.";
            header("Location: " . $_SERVER['HTTP_REFERER']);
            exit;
        }

        // --- DELETE MULTIPLE QUESTIONS (Bulk) ---
        if ($_POST['action'] == 'delete_questions_bulk') {
            $ids = isset($_POST['ids']) ? (array)$_POST['ids'] : [];
            $ids = array_filter(array_map('intval', $ids), function($v){ return $v > 0; });
            if (!empty($ids)) {
                $ids_in = implode(',', $ids);
                mysqli_query($con, "DELETE FROM hr_screening_questions WHERE id IN ($ids_in)");
                $_SESSION['success_message'] = count($ids) . " question(s) deleted successfully.";
            } else {
                $_SESSION['error_message'] = "No questions were selected for deletion.";
            }
            header("Location: " . $_SERVER['HTTP_REFERER']);
            exit;
        }

        // --- IMPORT CSV: ROUNDS ---
        if ($_POST['action'] == 'import_rounds' && isset($_FILES['import_file']) && $_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
            $import_dept_id = intval($_POST['dept_id'] ?? 0);
            $import_pos_id  = intval($_POST['position_id'] ?? 0);
            $valid_round_types = ['interview','assignment','work_sample','observation','offer'];

            if ($import_dept_id <= 0 || $import_pos_id <= 0) {
                $_SESSION['error_message'] = "Please select a Department and Position before importing rounds.";
                header("Location: $current_page?view=rounds");
                exit;
            }

            $file = fopen($_FILES['import_file']['tmp_name'], 'r');
            fgetcsv($file); // skip header
            $imported = 0;
            $skipped  = 0;
            while (($data = fgetcsv($file)) !== false) {
                if (count($data) < 2) continue;
                try {
                    $round_num  = intval($data[0]);
                    $round_name_raw = sanitizeImportText($data[1] ?? '');
                    $round_name = mysqli_real_escape_string($con, $round_name_raw);
                    $round_type = isset($data[2]) ? sanitizeImportText(strtolower($data[2])) : 'interview';
                    if (!in_array($round_type, $valid_round_types)) $round_type = 'interview';
                    $round_type = mysqli_real_escape_string($con, $round_type);
                    $obs_days   = isset($data[3]) && $data[3] !== '' ? intval($data[3]) : 0;

                    if ($round_num > 0 && $round_name_raw !== '') {
                        mysqli_query($con, "INSERT INTO hr_screening_rounds (department_id, position_id, round_number, round_name, round_type, observation_days, created_by) VALUES ($import_dept_id, $import_pos_id, $round_num, '$round_name', '$round_type', $obs_days, '$currentUserName')");
                        $imported++;
                    }
                } catch (Throwable $e) {
                    // One malformed row (bad encoding, unexpected data, etc.) no
                    // longer takes the whole import down — skip it and keep going.
                    $skipped++;
                }
            }
            fclose($file);
            $_SESSION['success_message'] = "Imported $imported round(s) successfully." . ($skipped > 0 ? " ($skipped row(s) skipped due to errors — check them manually.)" : "");
            header("Location: $current_page?view=rounds&dept_id=$import_dept_id&position_id=$import_pos_id");
            exit;
        }

        // --- IMPORT CSV: QUESTIONS ---
        if ($_POST['action'] == 'import_questions' && isset($_FILES['import_file']) && $_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
            $import_dept_id = intval($_POST['dept_id'] ?? 0);
            $import_pos_id  = intval($_POST['position_id'] ?? 0);

            if ($import_dept_id <= 0 || $import_pos_id <= 0) {
                $_SESSION['error_message'] = "Please select a Department and Position before importing questions.";
                header("Location: $current_page?view=questions");
                exit;
            }

            $file = fopen($_FILES['import_file']['tmp_name'], 'r');
            fgetcsv($file); // skip header
            $imported = 0;
            $skipped  = 0;
            while (($data = fgetcsv($file)) !== false) {
                if (count($data) < 3) continue;
                try {
                    $round_num = intval($data[0]);
                    $question_text_raw = sanitizeImportText($data[1] ?? '');
                    $question_text = mysqli_real_escape_string($con, $question_text_raw);
                    $input_type    = mysqli_real_escape_string($con, sanitizeImportText($data[2] ?? ''));
                    $opts_csv      = isset($data[3]) ? sanitizeImportText($data[3]) : '';
                    $marks         = isset($data[4]) ? intval($data[4]) : 10;
                    $opts_json     = '';
                    if ($opts_csv !== '') {
                        $opts_arr  = array_map('trim', explode(',', $opts_csv));
                        $opts_json = mysqli_real_escape_string($con, json_encode($opts_arr));
                    }

                    if ($round_num > 0 && $question_text_raw !== '') {
                        mysqli_query($con, "INSERT INTO hr_screening_questions (department_id, position_id, round_number, question_text, input_type, options_json, marks) VALUES ($import_dept_id, $import_pos_id, $round_num, '$question_text', '$input_type', '$opts_json', $marks)");
                        $imported++;
                    }
                } catch (Throwable $e) {
                    // One malformed row (bad encoding, unexpected data, etc.) no
                    // longer takes the whole import down — skip it and keep going.
                    $skipped++;
                }
            }
            fclose($file);
            $_SESSION['success_message'] = "Imported $imported question(s) successfully." . ($skipped > 0 ? " ($skipped row(s) skipped due to errors — check them manually.)" : "");
            header("Location: $current_page?view=questions&dept_id=$import_dept_id&position_id=$import_pos_id");
            exit;
        }
    }
}

// Fetch all departments for dropdowns
$departments_dropdown = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
$departments_arr = [];
while($d = mysqli_fetch_assoc($departments_dropdown)) {
    $departments_arr[] = $d;
}

// =========================================================================
// COVERAGE SUMMARY: every configured round vs. how many questions exist
// for it, department + position wise (read-only, no data is modified here)
// =========================================================================
$coverage_not_entered = 0;
// Pivoted: one entry per Department+Position, holding all of its rounds keyed by round_number
$coverage_matrix = [];
$coverage_max_round = 0;

// Seed every Department+Position pair first (even ones with zero rounds configured),
// so completely un-configured positions still show up as a row instead of being silently skipped
$dept_pos_seed = mysqli_query($con, "SELECT d.id as department_id, d.name as dept_name, p.id as position_id, p.title as pos_title
    FROM hr_departments d
    LEFT JOIN hr_positions p ON p.department_id = d.id
    ORDER BY d.name ASC, p.title ASC");
if ($dept_pos_seed) {
    while ($seed = mysqli_fetch_assoc($dept_pos_seed)) {
        $seed_pos_id = $seed['position_id'] !== null ? $seed['position_id'] : 0;
        $combo_key = $seed['department_id'] . '_' . $seed_pos_id;
        $coverage_matrix[$combo_key] = [
            'department_id' => $seed['department_id'],
            'position_id'   => $seed_pos_id,
            'dept_name'     => $seed['dept_name'],
            'pos_title'     => $seed['pos_title'],
            'rounds'        => []
        ];
    }
}

$cov_query = "SELECT r.department_id, r.position_id, r.round_number, r.round_name, r.round_type,
                     d.name as dept_name, p.title as pos_title,
                     (SELECT COUNT(*) FROM hr_screening_questions q
                      WHERE q.department_id = r.department_id
                      AND q.position_id = r.position_id
                      AND q.round_number = r.round_number
                      AND q.is_active = 1) as question_count
              FROM hr_screening_rounds r
              LEFT JOIN hr_departments d ON r.department_id = d.id
              LEFT JOIN hr_positions p ON r.position_id = p.id
              ORDER BY d.name ASC, p.title ASC, r.round_number ASC";
$cov_result = mysqli_query($con, $cov_query);
if ($cov_result) {
    // Round types where candidates upload files or are just observed / no questions are expected
    $no_questions_needed = ['work_sample', 'offer', 'observation'];
    while ($row = mysqli_fetch_assoc($cov_result)) {
        $row['needs_questions'] = !in_array($row['round_type'], $no_questions_needed);
        if ($row['needs_questions'] && $row['question_count'] == 0) {
            $coverage_not_entered++;
        }

        $combo_key = $row['department_id'] . '_' . $row['position_id'];
        if (!isset($coverage_matrix[$combo_key])) {
            $coverage_matrix[$combo_key] = [
                'department_id' => $row['department_id'],
                'position_id'   => $row['position_id'],
                'dept_name'     => $row['dept_name'],
                'pos_title'     => $row['pos_title'],
                'rounds'        => []
            ];
        }
        $coverage_matrix[$combo_key]['rounds'][$row['round_number']] = $row;
        if ($row['round_number'] > $coverage_max_round) $coverage_max_round = $row['round_number'];
    }
}

// Position-level summary for the header badges (how many positions have at least one round configured)
$coverage_positions_configured = 0;
foreach ($coverage_matrix as $combo) {
    if (!empty($combo['rounds'])) $coverage_positions_configured++;
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo isset($_SESSION['ge_cname']) ? $_SESSION['ge_cname'] : 'Abra'; ?> | HR Screening Rounds Management</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <!-- CSS Resources -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    
    .container-fluid { max-width: 1400px; margin: 0 auto; padding: 0 20px; }

    /* Header */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }
    
    /* Navigation Tabs */
    .nav-tabs-container { display: flex; gap: 10px; margin-bottom: 20px; }
    .nav-btn {
        padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
        font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
        display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
    }
    .nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

    /* Action Bar */
    .action-bar {
      background: white; padding: 20px; border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px;
      display: flex; justify-content: space-between; align-items: center;
    }
    .btn-action {
      border: none; padding: 10px 20px; border-radius: 8px; font-weight: 600;
      color: white; background: #10b981; cursor: pointer;
    }
    .card-box { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
    .table th { background: #f8fafc; color: #1e293b; font-weight: 600; border-top: none; }

    /* Coverage Summary */
    .coverage-header {
        background: #f1f5f9; padding: 15px 25px; border-bottom: 1px solid #e2e8f0;
        display: flex; justify-content: space-between; align-items: center; cursor: pointer;
    }
    .coverage-header:hover { background: #e2e8f0; }
    .coverage-header h5 { margin: 0; font-weight: 700; color: #1e3a8a; font-size: 16px; }

    /* Coverage matrix: one row per Department+Position, one column per Round number */
    .coverage-matrix-table { width: 100%; border-collapse: separate; border-spacing: 0; }
    .coverage-matrix-table th {
        text-align: left; padding: 12px 16px; background: #f8fafc; color: #64748b;
        font-weight: 700; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px;
        border-bottom: 2px solid #e2e8f0; white-space: nowrap;
    }
    .coverage-matrix-table th.dept-col, .coverage-matrix-table th.pos-col {
        background: #1e3a8a; color: #fff; position: sticky; z-index: 2;
    }
    .coverage-matrix-table th.dept-col { left: 0; min-width: 170px; }
    .coverage-matrix-table th.pos-col { left: 170px; min-width: 170px; background: #334155; }
    .coverage-matrix-table td {
        padding: 10px 14px; border-bottom: 1px solid #eef2f6; border-right: 1px solid #eef2f6;
        vertical-align: middle; font-size: 13px; color: #334155; min-width: 130px;
    }
    .coverage-matrix-table tbody tr:hover td { background: #f8fafc; }
    .coverage-matrix-table td.dept-cell, .coverage-matrix-table td.pos-cell {
        position: sticky; z-index: 1; font-weight: 700; background: #fff;
    }
    .coverage-matrix-table tbody tr:hover td.dept-cell, .coverage-matrix-table tbody tr:hover td.pos-cell { background: #f8fafc; }
    .coverage-matrix-table td.dept-cell { left: 0; color: #1e3a8a; min-width: 170px; }
    .coverage-matrix-table td.pos-cell { left: 170px; color: #475569; font-weight: 600; min-width: 170px; border-right: 2px solid #e2e8f0; }
    .coverage-matrix-table td.round-cell.empty-cell { background: #fcfcfc; text-align: center; }
    .coverage-matrix-table td.round-cell.empty-cell:hover { background: #fcfcfc; }

    .rc-name { font-weight: 600; color: #1e293b; font-size: 12.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 150px; }
    .rc-type { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: .3px; margin-bottom: 4px; }

    .pill { display: inline-block; padding: 4px 11px; border-radius: 20px; font-size: 11px; font-weight: 700; letter-spacing: .2px; white-space: nowrap; }
    .pill-status-na { background: #f1f5f9; color: #64748b; }

    .rc-count {
        display: inline-block; padding: 4px 11px; border-radius: 20px; font-size: 11.5px;
        font-weight: 700; text-decoration: none; transition: all .2s ease;
    }
    .rc-count.rc-ok { background: #dcfce7; color: #15803d; }
    .rc-count.rc-ok:hover { background: #16a34a; color: #fff; text-decoration: none; }
    .rc-count.rc-missing { background: #fee2e2; color: #b91c1c; }
    .rc-count.rc-missing:hover { background: #dc2626; color: #fff; text-decoration: none; }
  </style>
</head>
<body>

<div class="container-fluid">
    
    <!-- Alerts -->
    <?php if(isset($_SESSION['success_message'])): ?>
        <div class="alert alert-success alert-dismissible fade show">
            <i class="fas fa-check-circle mr-2"></i> <?php echo $_SESSION['success_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['success_message']); ?>
    <?php endif; ?>
    <?php if(isset($_SESSION['error_message'])): ?>
        <div class="alert alert-danger alert-dismissible fade show">
            <i class="fas fa-exclamation-circle mr-2"></i> <?php echo $_SESSION['error_message']; ?>
            <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
        <?php unset($_SESSION['error_message']); ?>
    <?php endif; ?>

    <div class="page-header">
        <h1><i class="fas fa-layer-group mr-2"></i> HR Screening Rounds Configuration</h1>
        <div style="display:flex; gap:10px;">
            <?php
            $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
            $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
            ?>
            
            <a href="hr_screening.php" class="btn btn-light"><i class="fas fa-arrow-left"></i> Back to Screening</a>
        </div>
    </div>

    <div class="nav-tabs-container">
        <a href="?view=rounds" class="nav-btn <?php echo $view == 'rounds' ? 'active' : ''; ?>">
            <i class="fas fa-list-ol"></i> Manage Rounds
        </a>
        <a href="?view=questions" class="nav-btn <?php echo $view == 'questions' ? 'active' : ''; ?>">
            <i class="fas fa-question-circle"></i> Manage Questions (KPQ)
        </a>
        <a href="hr-document-verification.php" class="nav-btn">
            <i class="fas fa-file-alt"></i> Manage Documents
        </a>
        <a href="hr-employee-offer.php" class="nav-btn">
            <i class="fas fa-envelope-open-text"></i> Manage Offer Letters
        </a>
    </div>

    <!-- COVERAGE SUMMARY: Department / Position / Round wise question entry status -->
    <div class="card-box" style="margin-bottom:20px; padding:0; overflow:hidden;">
        <div class="coverage-header" onclick="toggleCoverageMatrix()">
            <h5><i class="fas fa-th-list mr-2"></i> Question Coverage Summary (Click to Expand/Collapse)</h5>
            <div style="display:flex; align-items:center; gap:12px;">
                <span class="badge" style="background:#dcfce7; color:#15803d; font-size:12px; padding:6px 12px;">
                    <?php echo $coverage_positions_configured; ?> of <?php echo count($coverage_matrix); ?> position(s) have rounds configured
                </span>
                <?php if ($coverage_not_entered > 0): ?>
                    <span class="badge" style="background:#ef4444; color:#fff; font-size:12px; padding:6px 12px;">
                        <?php echo $coverage_not_entered; ?> round(s) missing questions
                    </span>
                <?php else: ?>
                    <span class="badge" style="background:#10b981; color:#fff; font-size:12px; padding:6px 12px;">
                        All rounds covered
                    </span>
                <?php endif; ?>
                <i class="fas fa-chevron-down" id="coverageMatrixIcon"></i>
            </div>
        </div>
        <div id="coverageMatrixContent" style="display:none; overflow-x:auto;">
            <table class="coverage-matrix-table">
                <thead>
                    <tr>
                        <th class="dept-col">Department</th>
                        <th class="pos-col">Position</th>
                        <?php for ($i = 1; $i <= $coverage_max_round; $i++): ?>
                            <th>Round <?php echo $i; ?></th>
                        <?php endfor; ?>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($coverage_matrix)): ?>
                    <tr><td colspan="<?php echo 2 + max($coverage_max_round, 1); ?>" class="text-center text-muted p-4">No rounds configured yet. Add a round first to see coverage here.</td></tr>
                    <?php else:
                        // Distinct colors per round type — deliberately avoids green (reserved for the "Entered" status)
                        $rt_labels = ['interview'=>['Interview','#3b82f6'],'assignment'=>['Assignment','#f59e0b'],'work_sample'=>['Work Sample','#8b5cf6'],'observation'=>['Observation','#a78bfa'],'offer'=>['Offer','#0891b2']];
                        foreach ($coverage_matrix as $combo):
                    ?>
                    <tr>
                        <td class="dept-cell"><?php echo htmlspecialchars($combo['dept_name']); ?></td>
                        <td class="pos-cell"><?php echo htmlspecialchars($combo['pos_title'] ?: '—'); ?></td>
                        <?php for ($i = 1; $i <= $coverage_max_round; $i++):
                            $rd = isset($combo['rounds'][$i]) ? $combo['rounds'][$i] : null;
                        ?>
                        <td class="round-cell<?php echo $rd ? '' : ' empty-cell'; ?>">
                            <?php if ($rd):
                                $rt_val = $rd['round_type'] ?: 'interview';
                                $rt_info = $rt_labels[$rt_val] ?? ['Interview','#3b82f6'];
                            ?>
                                <div class="rc-name" title="<?php echo htmlspecialchars($rd['round_name']); ?>"><?php echo htmlspecialchars($rd['round_name']); ?></div>
                                <div class="rc-type" style="color:<?php echo $rt_info[1]; ?>;"><?php echo $rt_info[0]; ?></div>
                                <?php if (!$rd['needs_questions']): ?>
                                    <span class="pill pill-status-na" title="Work sample, offer, or observation round — no questions needed">N/A</span>
                                <?php else: ?>
                                    <a href="?view=questions&dept_id=<?php echo $rd['department_id']; ?>&position_id=<?php echo $rd['position_id']; ?>&round_number[]=<?php echo $rd['round_number']; ?>"
                                       class="rc-count <?php echo $rd['question_count'] > 0 ? 'rc-ok' : 'rc-missing'; ?>"
                                       title="<?php echo $rd['question_count'] > 0 ? 'View' : 'Add'; ?> questions for this round">
                                        <?php echo $rd['question_count']; ?> Q<?php echo $rd['question_count'] == 1 ? '' : 's'; ?>
                                    </a>
                                <?php endif; ?>
                            <?php else: ?>
                                <span class="text-muted">—</span>
                            <?php endif; ?>
                        </td>
                        <?php endfor; ?>
                    </tr>
                    <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
    </div>

    <?php if ($view == 'rounds'): ?>
    
        <div class="action-bar">
            <form method="GET" class="form-inline">
                <input type="hidden" name="view" value="rounds">
                <label class="mr-2 font-weight-bold">Select Department: </label>
                <select name="dept_id" class="form-control mr-3" onchange="this.form.submit()">
                    <option value="0">-- All Departments --</option>
                    <?php foreach($departments_arr as $d): ?>
                        <option value="<?php echo $d['id']; ?>" <?php if($selected_dept == $d['id']) echo 'selected'; ?>>
                            <?php echo htmlspecialchars($d['name']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
                <label class="mr-2 font-weight-bold">Select Position: </label>
                <select name="position_id" class="form-control mr-3" onchange="this.form.submit()">
                    <option value="0">-- All Positions --</option>
                    <?php foreach($positions as $p): ?>
                        <option value="<?php echo $p['id']; ?>" <?php if($selected_pos == $p['id']) echo 'selected'; ?>>
                            <?php echo htmlspecialchars($p['title']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </form>
            <button class="btn-action" data-toggle="modal" data-target="#addRoundModal"><i class="fas fa-plus"></i> Add Round</button>
            <a href="?view=rounds&action=export&export_view=rounds&dept_id=<?php echo $selected_dept; ?>&position_id=<?php echo $selected_pos; ?>" class="btn btn-sm" style="background:#3b82f6;color:#fff;padding:10px 16px;border-radius:8px;font-weight:600;"><i class="fas fa-file-download mr-1"></i> Export CSV</a>
            <button class="btn btn-sm" style="background:#f59e0b;color:#fff;padding:10px 16px;border-radius:8px;font-weight:600;border:none;" data-toggle="modal" data-target="#importRoundsModal"><i class="fas fa-file-upload mr-1"></i> Import CSV</button>
        </div>

        <div class="card-box">
            <table class="table table-hover" id="roundsTable">
                <thead>
                    <tr>
                        <th>Department</th>
                        <th>Position</th>
                        <th>Round Number</th>
                        <th>Round Name</th>
                        <th>Created By</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <?php 
                    $query = "SELECT r.*, d.name as dept_name FROM hr_screening_rounds r LEFT JOIN hr_departments d ON r.department_id = d.id";
                    $query_where = [];
                    if ($selected_dept > 0) $query_where[] = "r.department_id = $selected_dept";
                    if ($selected_pos > 0)  $query_where[] = "r.position_id = $selected_pos";
                    if (!empty($query_where)) $query .= " WHERE " . implode(' AND ', $query_where);
                    $query .= " ORDER BY d.name ASC, r.round_number ASC";
                    $result = mysqli_query($con, $query);
                    while($row = mysqli_fetch_assoc($result)):
                        // Fetch position name
                        $pos_name = '—';
                        if (!empty($row['position_id'])) {
                            $pos_q = mysqli_fetch_assoc(mysqli_query($con, "SELECT title FROM hr_positions WHERE id=" . intval($row['position_id']) . " LIMIT 1"));
                            if ($pos_q) $pos_name = $pos_q['title'];
                        }
                    ?>
                    <tr>
                        <td><?php echo htmlspecialchars($row['dept_name']); ?></td>
                        <td><strong><?php echo htmlspecialchars($pos_name); ?></strong></td>
                        <td><span class="badge badge-primary" style="font-size:14px;">Round <?php echo $row['round_number']; ?></span></td>
                        <?php
                        $rt_labels = ['interview'=>['Interview','#3b82f6'],'assignment'=>['Assignment','#f59e0b'],'work_sample'=>['Work Sample','#8b5cf6'],'observation'=>['Observation','#a78bfa'],'offer'=>['Offer','#10b981']];
                        $rt_val = $row['round_type'] ?: 'interview';
                        $rt_info = $rt_labels[$rt_val] ?? ['Interview','#3b82f6'];
                        ?>
                        <td><strong><?php echo htmlspecialchars($row['round_name']); ?></strong>
                            <div><span class="badge" style="background:<?php echo $rt_info[1]; ?>22;color:<?php echo $rt_info[1]; ?>;font-weight:700;font-size:11px;"><?php echo $rt_info[0]; ?><?php if($rt_val=='observation' && $row['observation_days']>0) echo ' ('.$row['observation_days'].'d)'; ?></span></div>
                        </td>
                        <td><?php echo htmlspecialchars($row['created_by']); ?></td>
                        <td>
                            <a href="?view=questions&dept_id=<?php echo $row['department_id']; ?>&position_id=<?php echo $row['position_id']; ?>&round_number=<?php echo $row['round_number']; ?>" class="btn btn-sm btn-info" title="Manage Questions">
                                <i class="fas fa-list"></i> Questions
                            </a>
                            <button type="button" class="btn btn-sm btn-warning" onclick="editRound(<?php echo htmlspecialchars(json_encode($row)); ?>)" title="Edit Round">
                                <i class="fas fa-edit"></i> Edit
                            </button>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this round?');">
                                <input type="hidden" name="action" value="delete_round">
                                <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
                                <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                            </form>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                </tbody>
            </table>
        </div>

        <!-- Edit Round Modal -->
        <div class="modal fade" id="editRoundModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog" role="document">
                <div class="modal-content">
                    <form method="POST">
                        <input type="hidden" name="action" value="edit_round">
                        <input type="hidden" name="id" id="edit_round_id">
                        <div class="modal-header">
                            <h4 class="modal-title">Edit Round</h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="form-group">
                                <label>Department</label>
                                <select name="department_id" id="edit_round_dept" class="form-control" required onchange="fetchModalPositions(this.value, 'edit_round_pos')">
                                    <option value="">Select Department...</option>
                                    <?php foreach($departments_arr as $d): ?>
                                        <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Position</label>
                                <select name="position_id" id="edit_round_pos" class="form-control" required>
                                    <option value="">Select Position...</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Round Type</label>
                                <select name="round_type" id="edit_round_type" class="form-control" required onchange="toggleRoundTypeFields(this.value, 'edit')">
                                    <option value="interview">Interview / Q&A</option>
                                    <option value="assignment">Assignment (Candidate submits answers via link)</option>
                                    <option value="work_sample">Work Sample / Portfolio / Sales Pitch (Candidate uploads files)</option>
                                    <option value="observation">Observation Period</option>
                                    <option value="offer">Offer / Document Verification</option>
                                </select>
                            </div>
                            <div class="form-group" id="edit_obs_days_wrap" style="display:none;">
                                <label>Observation Period (Days)</label>
                                <input type="number" name="observation_days" id="edit_observation_days" class="form-control" min="1">
                            </div>
                            <div class="alert alert-info p-2" id="edit_worksample_note" style="display:none; font-size:12px;">
                                <i class="fas fa-info-circle"></i> Candidates on this round upload files (portfolio, work samples, pitch deck/recording) via a secure link instead of answering questions.
                            </div>
                            <div class="form-group">
                                <label>Round Number</label>
                                <input type="number" name="round_number" id="edit_round_number" class="form-control" min="1" required>
                            </div>
                            <div class="form-group">
                                <label>Round Name</label>
                                <input type="text" name="round_name" id="edit_round_name" class="form-control" required>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-warning">Update Round</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

        <!-- Add Round Modal -->
        <div class="modal fade" id="addRoundModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog" role="document">
                <div class="modal-content">
                    <form method="POST">
                        <input type="hidden" name="action" value="add_round">
                        <div class="modal-header">
                            <h4 class="modal-title">Add New Round</h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="form-group">
                                <label>Department</label>
                                <select name="department_id" class="form-control" required onchange="fetchModalPositions(this.value, 'modal_position_id')">
                                    <option value="">Select Department...</option>
                                    <?php foreach($departments_arr as $d): ?>
                                        <option value="<?php echo $d['id']; ?>" <?php if($selected_dept == $d['id']) echo 'selected'; ?>><?php echo htmlspecialchars($d['name']); ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Position</label>
                                <select name="position_id" id="modal_position_id" class="form-control" required>
                                    <option value="">Select Position...</option>
                                    <?php foreach($positions as $p): ?>
                                        <option value="<?php echo $p['id']; ?>" <?php if($selected_pos == $p['id']) echo 'selected'; ?>><?php echo htmlspecialchars($p['title']); ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Round Type</label>
                                <select name="round_type" class="form-control" required onchange="toggleRoundTypeFields(this.value, 'add')">
                                    <option value="interview">Interview / Q&A</option>
                                    <option value="assignment">Assignment (Candidate submits answers via link)</option>
                                    <option value="work_sample">Work Sample / Portfolio / Sales Pitch (Candidate uploads files)</option>
                                    <option value="observation">Observation Period</option>
                                    <option value="offer">Offer / Document Verification</option>
                                </select>
                            </div>
                            <div class="form-group" id="add_obs_days_wrap" style="display:none;">
                                <label>Observation Period (Days)</label>
                                <input type="number" name="observation_days" class="form-control" min="1" placeholder="e.g. 30">
                            </div>
                            <div class="alert alert-info p-2" id="add_worksample_note" style="display:none; font-size:12px;">
                                <i class="fas fa-info-circle"></i> Candidates on this round will be sent a secure link where they upload files (portfolio, past work samples, pitch deck/recording, etc.) instead of answering questions. HR reviews and rates the uploaded work.
                            </div>
                            <div class="form-group">
                                <label>Round Number (e.g. 1, 2, 3)</label>
                                <input type="number" name="round_number" class="form-control" min="1" required>
                            </div>
                            <div class="form-group">
                                <label>Round Name (e.g. Technical Interview)</label>
                                <input type="text" name="round_name" class="form-control" required>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-primary">Save Round</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

        <!-- Import Rounds Modal -->
        <div class="modal fade" id="importRoundsModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog" role="document">
                <div class="modal-content">
                    <form method="POST" action="hr-managing-rounds-kpq.php?view=rounds" enctype="multipart/form-data">
                        <input type="hidden" name="action" value="import_rounds">
                        <input type="hidden" name="dept_id" value="<?php echo $selected_dept; ?>">
                        <input type="hidden" name="position_id" value="<?php echo $selected_pos; ?>">
                        <div class="modal-header">
                            <h4 class="modal-title">Import Rounds from CSV</h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <?php if ($selected_dept > 0 && $selected_pos > 0): ?>
                                <div class="alert alert-info p-2" style="font-size:13px;">
                                    <i class="fas fa-info-circle mr-1"></i> Rounds will be imported into
                                    <strong><?php echo htmlspecialchars($departments_arr[array_search($selected_dept, array_column($departments_arr,'id'))]['name'] ?? ''); ?></strong>
                                    — the Department and Position you currently have selected on this page.
                                </div>
                                <p class="text-muted small mb-3">CSV format: <strong>Round Number, Round Name, Round Type (optional), Observation Days (optional)</strong><br>
                                Round Type: interview / assignment / work_sample / observation / offer. Leave blank for interview.</p>
                            <?php else: ?>
                                <div class="alert alert-warning p-2" style="font-size:13px;">
                                    <i class="fas fa-exclamation-triangle mr-1"></i> Please select a Department and Position on the page <strong>before</strong> opening this Import dialog — imported rounds will be assigned to whatever is currently selected.
                                </div>
                            <?php endif; ?>

                            <div class="mb-4 text-center">
                                <a href="?action=download_template&type=rounds" class="btn btn-sm btn-outline-info" style="font-weight:600;"><i class="fas fa-download mr-1"></i> Download Sample CSV Template</a>
                            </div>

                            <div class="form-group">
                                <label>Select CSV File</label>
                                <input type="file" name="import_file" class="form-control-file" accept=".csv" required>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-warning" <?php echo ($selected_dept == 0 || $selected_pos == 0) ? 'disabled' : ''; ?>>Import Rounds</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

    <?php elseif ($view == 'questions'): ?>
        
        <div class="action-bar">
            <form method="GET" class="form-inline" id="questionFilterForm">
                <input type="hidden" name="view" value="questions">
                <label class="mr-2 font-weight-bold">Department: </label>
                <select name="dept_id" id="filter_dept_id" class="form-control mr-3" onchange="clearRoundSelection(); this.form.submit();">
                    <option value="0">-- Select Department --</option>
                    <?php foreach($departments_arr as $d): ?>
                        <option value="<?php echo $d['id']; ?>" <?php if($selected_dept == $d['id']) echo 'selected'; ?>>
                            <?php echo htmlspecialchars($d['name']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
                
                <label class="mr-2 font-weight-bold">Position: </label>
                <select name="position_id" id="filter_position_id" class="form-control mr-3" onchange="clearRoundSelection(); this.form.submit();">
                    <option value="0">-- Select Position --</option>
                    <?php foreach($positions as $p): ?>
                        <option value="<?php echo $p['id']; ?>" <?php if($selected_pos == $p['id']) echo 'selected'; ?>>
                            <?php echo htmlspecialchars($p['title']); ?>
                        </option>
                    <?php endforeach; ?>
                </select>
                
                <label class="mr-2 font-weight-bold">Round(s): </label>
                <select name="round_number[]" id="filter_round_number" class="form-control mr-3" multiple onchange="this.form.submit()">
                    <?php 
                    if ($selected_dept > 0 && $selected_pos > 0) {
                        $rounds_query = mysqli_query($con, "SELECT * FROM hr_screening_rounds WHERE department_id = $selected_dept AND position_id = $selected_pos ORDER BY round_number ASC");
                        if ($rounds_query) {
                            while($r = mysqli_fetch_assoc($rounds_query)):
                    ?>
                        <option value="<?php echo $r['round_number']; ?>" <?php if(in_array($r['round_number'], $selected_rounds)) echo 'selected'; ?>>
                            Round <?php echo $r['round_number']; ?> - <?php echo htmlspecialchars($r['round_name']); ?>
                        </option>
                    <?php 
                            endwhile; 
                        }
                    }
                    ?>
                </select>
                <small class="text-muted mr-3" style="align-self:center;">(Ctrl/Cmd+click to select multiple)</small>
            </form>
            <?php if($selected_dept > 0 && $selected_pos > 0 && $selected_round > 0): ?>
                <button class="btn-action" data-toggle="modal" data-target="#addQuestionModal"><i class="fas fa-plus"></i> Add Question</button>
            <?php endif; ?>
            <a href="?view=questions&action=export&export_view=questions&dept_id=<?php echo $selected_dept; ?>&position_id=<?php echo $selected_pos; ?><?php foreach($selected_rounds as $sr) echo '&round_number[]=' . $sr; ?>" class="btn btn-sm" style="background:#3b82f6;color:#fff;padding:10px 16px;border-radius:8px;font-weight:600;"><i class="fas fa-file-download mr-1"></i> Export CSV</a>
            <button class="btn btn-sm" style="background:#f59e0b;color:#fff;padding:10px 16px;border-radius:8px;font-weight:600;border:none;" data-toggle="modal" data-target="#importQuestionsModal"><i class="fas fa-file-upload mr-1"></i> Import CSV</button>
        </div>
        <script>
        function clearRoundSelection() {
            var sel = document.getElementById('filter_round_number');
            if (sel) { for (var i=0; i<sel.options.length; i++) sel.options[i].selected = false; }
        }
        </script>

        <!-- Import Questions Modal -->
        <div class="modal fade" id="importQuestionsModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog" role="document">
                <div class="modal-content">
                    <form method="POST" action="hr-managing-rounds-kpq.php?view=questions" enctype="multipart/form-data">
                        <input type="hidden" name="action" value="import_questions">
                        <input type="hidden" name="dept_id" value="<?php echo $selected_dept; ?>">
                        <input type="hidden" name="position_id" value="<?php echo $selected_pos; ?>">
                        <div class="modal-header">
                            <h4 class="modal-title">Import Questions from CSV</h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <?php if ($selected_dept > 0 && $selected_pos > 0): ?>
                                <div class="alert alert-info p-2" style="font-size:13px;">
                                    <i class="fas fa-info-circle mr-1"></i> Questions will be imported into
                                    <strong><?php echo htmlspecialchars($departments_arr[array_search($selected_dept, array_column($departments_arr,'id'))]['name'] ?? ''); ?></strong>
                                    — <strong><?php echo htmlspecialchars($positions[array_search($selected_pos, array_column($positions,'id'))]['title'] ?? ''); ?></strong>
                                    — the Department and Position you currently have selected on this page.
                                </div>
                                <p class="text-muted small mb-3">CSV format: <strong>Round Number, Question Text, Input Type, Options (CSV), Marks</strong><br>Input Type: text / textarea / select / radio / rating / number.<br>Options only needed for select/radio.<br>
                                <span class="text-info" style="font-weight:600;"><i class="fas fa-magic mr-1"></i> Smart Scoring:</span> The system automatically calculates scores based on the <strong>order</strong> of your options (First = 100%, Last = 0%). Always order them from best to worst (e.g. <code>Excellent, Good, Poor</code> or <code>Yes, Partially, No</code>).</p>
                            <?php else: ?>
                                <div class="alert alert-warning p-2" style="font-size:13px;">
                                    <i class="fas fa-exclamation-triangle mr-1"></i> Please select a Department and Position on the page <strong>before</strong> opening this Import dialog — imported questions will be assigned to whatever is currently selected.
                                </div>
                            <?php endif; ?>

                            <div class="mb-4 text-center">
                                <a href="?action=download_template&type=questions" class="btn btn-sm btn-outline-info" style="font-weight:600;"><i class="fas fa-download mr-1"></i> Download Sample CSV Template</a>
                            </div>

                            <div class="form-group">
                                <label>Select CSV File</label>
                                <input type="file" name="import_file" class="form-control-file" accept=".csv" required>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-warning" <?php echo ($selected_dept == 0 || $selected_pos == 0) ? 'disabled' : ''; ?>>Import Questions</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>

        <div class="card-box">
            <?php if($selected_dept == 0 || empty($selected_rounds)): ?>
                <div class="text-center p-5 text-muted">
                    <i class="fas fa-info-circle fa-3x mb-3"></i>
                    <h4>Please select a Department and at least one Round to view or add questions.</h4>
                </div>
            <?php else: ?>
                <div style="margin-bottom:12px; display:flex; justify-content:space-between; align-items:center;">
                    <div style="font-size:13px; color:#64748b; font-weight:600;">
                        <span id="selectedCountLabel">0 selected</span>
                    </div>
                    <button type="button" id="bulkDeleteBtn" class="btn btn-sm btn-danger" disabled onclick="submitBulkDeleteQuestions()">
                        <i class="fas fa-trash"></i> Delete Selected
                    </button>
                </div>
                <table class="table table-hover" id="questionsTable">
                    <thead>
                        <tr>
                            <th style="width:36px;"><input type="checkbox" id="selectAllQuestions" onclick="toggleAllQuestions(this)"></th>
                            <th>Round</th>
                            <th>Question</th>
                            <th>Type</th>
                            <th>Marks</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php 
                    $rounds_in = implode(',', array_map('intval', $selected_rounds));
                    $q_query = mysqli_query($con, "SELECT * FROM hr_screening_questions WHERE department_id = $selected_dept AND position_id = $selected_pos AND round_number IN ($rounds_in) ORDER BY round_number ASC, id ASC");
                    while($q = mysqli_fetch_assoc($q_query)): 
                    ?>
                    <tr>
                        <td><input type="checkbox" class="question-checkbox" value="<?php echo $q['id']; ?>" onclick="updateBulkDeleteButton()"></td>
                        <td><span class="badge badge-primary">Round <?php echo $q['round_number']; ?></span></td>
                        <td style="max-width:400px;"><?php echo nl2br(htmlspecialchars($q['question_text'])); ?>
                            <?php if($q['input_type'] == 'select' || $q['input_type'] == 'radio'): ?>
                                <div class="text-muted small mt-1">Options: <?php echo implode(', ', json_decode($q['options_json'], true) ?: []); ?></div>
                            <?php endif; ?>
                        </td>
                        <td><span class="badge badge-secondary"><?php echo strtoupper($q['input_type']); ?></span></td>
                        <td><strong><?php echo $q['marks']; ?></strong></td>
                        <td>
                            <button type="button" class="btn btn-sm btn-info" onclick="editQuestion(<?php echo htmlspecialchars(json_encode($q)); ?>)" title="Edit Question"><i class="fas fa-edit"></i></button>
                            <button type="button" class="btn btn-sm btn-danger" onclick="deleteSingleQuestion(<?php echo $q['id']; ?>)" title="Delete Question"><i class="fas fa-trash"></i></button>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>

                <!-- Kept OUTSIDE the table — never nest a <form> inside another <form> -->
                <form method="POST" id="singleDeleteForm" style="display:none;">
                    <input type="hidden" name="action" value="delete_question">
                    <input type="hidden" name="id" id="singleDeleteId">
                </form>
                <form method="POST" id="bulkDeleteForm" style="display:none;">
                    <input type="hidden" name="action" value="delete_questions_bulk">
                </form>
            <?php endif; ?>
        </div>
        
        <?php if($selected_dept > 0 && $selected_pos > 0 && $selected_round > 0): ?>
        <!-- Add Question Modal -->
        <div class="modal fade" id="addQuestionModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog modal-lg" role="document">
                <div class="modal-content">
                    <form method="POST">
                        <input type="hidden" name="action" value="add_question">
                        <input type="hidden" name="department_id" value="<?php echo $selected_dept; ?>">
                        <input type="hidden" name="position_id" value="<?php echo $selected_pos; ?>">
                        <input type="hidden" name="round_number" value="<?php echo $selected_round; ?>">
                        
                        <div class="modal-header">
                            <h4 class="modal-title">Add Question to Round <?php echo $selected_round; ?></h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="form-group">
                                <label>Question Text</label>
                                <textarea name="question_text" class="form-control" rows="3" required></textarea>
                            </div>
                            <div class="form-group">
                                <label>Input Type</label>
                                <select name="input_type" class="form-control" id="inputTypeSelect" required>
                                    <option value="text">Text (Short Answer)</option>
                                    <option value="textarea">Textarea (Long Answer)</option>
                                    <option value="select">Dropdown (Select)</option>
                                    <option value="radio">Multiple Choice (Radio)</option>
                                    <option value="rating">Rating (1 to 5)</option>
                                    <option value="number">Numeric Score</option>
                                    <option value="file_upload">File Upload</option>
                                </select>
                                <div class="alert alert-info p-2 mt-2" id="fileUploadNote" style="display:none; font-size:12px; margin-bottom:0;">
                                    <i class="fas fa-info-circle"></i> The candidate will upload a file for this question instead of typing an answer. Word the question text as an instruction, e.g. "Upload your portfolio PDF" or "Upload a sample of your prior work." HR gives marks manually after reviewing the file.
                                </div>
                            </div>
                            <div class="form-group">
                                <label>Max Marks for this Question</label>
                                <input type="number" name="marks" class="form-control" value="10" min="1" required>
                            </div>
                            <div class="form-group" id="optionsContainer" style="display:none;">
                                <label>Options (Comma Separated)</label>
                                <input type="text" name="options_csv" class="form-control" placeholder="e.g. Yes, No, Maybe">
                                <small class="text-muted d-block mb-1">Required only for Dropdown or Multiple Choice.</small>
                                <div class="alert alert-info p-2 mt-2" style="font-size:12px; margin-bottom:0;">
                                    <strong><i class="fas fa-magic"></i> Smart Scoring:</strong> The system automatically calculates scores based on the order of options (First = 100%, Last = 0%). Always order them from best to worst (e.g. <code>Excellent, Good, Poor</code>).
                                </div>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-primary">Save Question</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
        <script>
            document.getElementById('inputTypeSelect').addEventListener('change', function() {
                var type = this.value;
                document.getElementById('optionsContainer').style.display = (type === 'select' || type === 'radio') ? 'block' : 'none';
                document.getElementById('fileUploadNote').style.display = (type === 'file_upload') ? 'block' : 'none';
            });
        </script>
        <?php endif; ?>

        <?php if($selected_dept > 0 && $selected_pos > 0 && !empty($selected_rounds)): ?>
        <!-- Edit Question Modal -->
        <div class="modal fade" id="editQuestionModal" tabindex="-1" role="dialog" aria-hidden="true">
            <div class="modal-dialog modal-lg" role="document">
                <div class="modal-content">
                    <form method="POST">
                        <input type="hidden" name="action" value="edit_question">
                        <input type="hidden" name="id" id="edit_q_id">
                        <input type="hidden" name="department_id" value="<?php echo $selected_dept; ?>">
                        <input type="hidden" name="position_id" value="<?php echo $selected_pos; ?>">
                        <input type="hidden" name="round_number" id="edit_q_round_number" value="">
                        <?php foreach ($selected_rounds as $sr): ?>
                        <input type="hidden" name="filter_rounds[]" value="<?php echo $sr; ?>">
                        <?php endforeach; ?>
                        
                        <div class="modal-header">
                            <h4 class="modal-title">Edit Question</h4>
                            <button type="button" class="close" data-dismiss="modal">&times;</button>
                        </div>
                        <div class="modal-body">
                            <div class="form-group">
                                <label>Question Text</label>
                                <textarea name="question_text" id="edit_q_text" class="form-control" rows="3" required></textarea>
                            </div>
                            <div class="form-group">
                                <label>Input Type</label>
                                <select name="input_type" class="form-control" id="edit_q_type" required>
                                    <option value="text">Text (Short Answer)</option>
                                    <option value="textarea">Textarea (Long Answer)</option>
                                    <option value="select">Dropdown (Select)</option>
                                    <option value="radio">Multiple Choice (Radio)</option>
                                    <option value="rating">Rating (1 to 5)</option>
                                    <option value="number">Numeric Score</option>
                                    <option value="file_upload">File Upload</option>
                                </select>
                                <div class="alert alert-info p-2 mt-2" id="editFileUploadNote" style="display:none; font-size:12px; margin-bottom:0;">
                                    <i class="fas fa-info-circle"></i> The candidate will upload a file for this question instead of typing an answer.
                                </div>
                            </div>
                            <div class="form-group">
                                <label>Max Marks for this Question</label>
                                <input type="number" name="marks" id="edit_q_marks" class="form-control" min="1" required>
                            </div>
                            <div class="form-group" id="editOptionsContainer" style="display:none;">
                                <label>Options (Comma Separated)</label>
                                <input type="text" name="options_csv" id="edit_q_options" class="form-control" placeholder="e.g. Yes, No, Maybe">
                                <small class="text-muted d-block mb-1">Required only for Dropdown or Multiple Choice.</small>
                                <div class="alert alert-info p-2 mt-2" style="font-size:12px; margin-bottom:0;">
                                    <strong><i class="fas fa-magic"></i> Smart Scoring:</strong> The system automatically calculates scores based on the order of options (First = 100%, Last = 0%). Always order them from best to worst (e.g. <code>Excellent, Good, Poor</code>).
                                </div>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <button type="submit" class="btn btn-info">Update Question</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
        <script>
            document.getElementById('edit_q_type').addEventListener('change', function() {
                var type = this.value;
                document.getElementById('editOptionsContainer').style.display = (type === 'select' || type === 'radio') ? 'block' : 'none';
                document.getElementById('editFileUploadNote').style.display = (type === 'file_upload') ? 'block' : 'none';
            });

            function editQuestion(q) {
                document.getElementById('edit_q_id').value = q.id;
                document.getElementById('edit_q_text').value = q.question_text;
                document.getElementById('edit_q_type').value = q.input_type;
                document.getElementById('edit_q_marks').value = q.marks;
                document.getElementById('edit_q_round_number').value = q.round_number;
                
                var type = q.input_type;
                if(type === 'select' || type === 'radio') {
                    document.getElementById('editOptionsContainer').style.display = 'block';
                    var options = [];
                    if (q.options_json) {
                        try { options = JSON.parse(q.options_json); } catch(e){}
                    }
                    document.getElementById('edit_q_options').value = options.join(', ');
                } else {
                    document.getElementById('editOptionsContainer').style.display = 'none';
                }
                document.getElementById('editFileUploadNote').style.display = (type === 'file_upload') ? 'block' : 'none';
                
                $('#editQuestionModal').modal('show');
            }
        </script>
        <?php endif; ?>

    <?php endif; ?>

</div>

<!-- Scripts -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script>
$(document).ready(function() {
    var roundsTable = null;
    var questionsTable = null;

    if($('#roundsTable').length) { roundsTable = $('#roundsTable').DataTable(); }
    if($('#questionsTable').length) { questionsTable = $('#questionsTable').DataTable({ pageLength: 100, lengthMenu: [[25, 50, 100, -1], [25, 50, 100, "All"]] }); }

    // Fix: DataTables captures keyboard events and blocks typing in modal inputs.
    // Destroy DataTable when any modal opens, reinitialize when it closes.
    $(document).on('show.bs.modal', '.modal', function() {
        if(roundsTable) { roundsTable.destroy(); roundsTable = null; }
        if(questionsTable) { questionsTable.destroy(); questionsTable = null; }
    });
    $(document).on('hidden.bs.modal', '.modal', function() {
        if($('#roundsTable').length && !roundsTable) { roundsTable = $('#roundsTable').DataTable(); }
        if($('#questionsTable').length && !questionsTable) { questionsTable = $('#questionsTable').DataTable(); }
    });
});
</script>

<script>
function toggleAllQuestions(source) {
    document.querySelectorAll('.question-checkbox').forEach(function(cb) {
        cb.checked = source.checked;
    });
    updateBulkDeleteButton();
}

function updateBulkDeleteButton() {
    var checked = document.querySelectorAll('.question-checkbox:checked').length;
    var btn = document.getElementById('bulkDeleteBtn');
    var label = document.getElementById('selectedCountLabel');
    if (btn) btn.disabled = (checked === 0);
    if (label) label.textContent = checked + ' selected';

    var all = document.querySelectorAll('.question-checkbox');
    var selectAll = document.getElementById('selectAllQuestions');
    if (selectAll && all.length > 0) {
        selectAll.checked = (checked === all.length);
        selectAll.indeterminate = (checked > 0 && checked < all.length);
    }
}

function submitBulkDeleteQuestions() {
    var checkedBoxes = document.querySelectorAll('.question-checkbox:checked');
    if (checkedBoxes.length === 0) return;
    if (!confirm('Delete ' + checkedBoxes.length + ' selected question(s)? This cannot be undone.')) return;

    var form = document.getElementById('bulkDeleteForm');
    form.querySelectorAll('input[name="ids[]"]').forEach(function(el) { el.remove(); });
    checkedBoxes.forEach(function(cb) {
        var input = document.createElement('input');
        input.type = 'hidden';
        input.name = 'ids[]';
        input.value = cb.value;
        form.appendChild(input);
    });
    form.submit();
}

function deleteSingleQuestion(id) {
    if (!confirm('Delete this question?')) return;
    document.getElementById('singleDeleteId').value = id;
    document.getElementById('singleDeleteForm').submit();
}

function fetchModalPositions(deptId, targetSelectId = 'modal_position_id', preselectId = null) {
    var sel = document.getElementById(targetSelectId);
    if (!sel) return;
    
    sel.innerHTML = '<option value="">Loading...</option>';
    if (!deptId) {
        sel.innerHTML = '<option value="">Select Position...</option>';
        return;
    }
    
    fetch('?get_positions=1&dept_id=' + deptId)
        .then(r => r.json())
        .then(data => {
            sel.innerHTML = '<option value="">Select Position...</option>';
            data.forEach(p => {
                var selected = (preselectId && p.id == preselectId) ? 'selected' : '';
                sel.innerHTML += `<option value="${p.id}" ${selected}>${p.title}</option>`;
            });
        });
}

function toggleRoundTypeFields(type, prefix) {
    document.getElementById(prefix + '_obs_days_wrap').style.display = (type === 'observation') ? 'block' : 'none';
    document.getElementById(prefix + '_worksample_note').style.display = (type === 'work_sample') ? 'block' : 'none';
}

function editRound(row) {
    document.getElementById('edit_round_id').value = row.id;
    document.getElementById('edit_round_number').value = row.round_number;
    document.getElementById('edit_round_name').value = row.round_name;
    document.getElementById('edit_round_type').value = row.round_type || 'interview';
    // observation_days comes back from PHP as the string "0" when unset (mysqli
    // returns all columns as strings), which is truthy in JS — so `|| ''` alone
    // doesn't catch it. That "0" then sits in a hidden field with min="1",
    // which is invalid-but-unfocusable and blocks the form from submitting.
    var obsDays = parseInt(row.observation_days, 10);
    document.getElementById('edit_observation_days').value = (obsDays > 0) ? obsDays : '';
    toggleRoundTypeFields(row.round_type || 'interview', 'edit');

    // Set department dropdown
    var deptSelect = document.getElementById('edit_round_dept');
    deptSelect.value = row.department_id;
    
    // Fetch positions for the selected department and pre-select the correct one
    fetchModalPositions(row.department_id, 'edit_round_pos', row.position_id);

    $('#editRoundModal').modal('show');
}

function toggleCoverageMatrix() {
    var content = document.getElementById('coverageMatrixContent');
    var icon = document.getElementById('coverageMatrixIcon');
    var isHidden = content.style.display === 'none';
    content.style.display = isHidden ? 'block' : 'none';
    icon.classList.toggle('fa-chevron-down', !isHidden);
    icon.classList.toggle('fa-chevron-up', isHidden);
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