<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';

// =========================================================================
// IDENTIFY LOGGED-IN EMPLOYEE (Flutter WebView Auth)
// =========================================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$session_name = trim($_SESSION['user_name'] ?? '');
$emp_data = null;
$db_link = isset($dbConn) ? $dbConn : (isset($con) ? $con : null);

if ($db_link && !empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($db_link, $currentUserEmail);
    $eq = mysqli_query($db_link, "
        SELECT id, employee_id, name, department, position 
        FROM hr_employees 
        WHERE (email = '$email_safe' OR personal_email = '$email_safe') 
        AND status = 'Active' 
        LIMIT 1
    ");
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
        $_SESSION['user_name'] = $emp_data['name'];
        $_SESSION['user_id'] = $emp_data['id'];
        $session_name = $emp_data['name'];
    }
}

if (!$emp_data && $session_name && $db_link) {
    $safe_name = mysqli_real_escape_string($db_link, $session_name);
    $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name = '$safe_name' AND status = 'Active' LIMIT 1");
    if (!$eq || mysqli_num_rows($eq) == 0) {
        $eq = mysqli_query($db_link, "SELECT id, employee_id, name, department, position FROM hr_employees WHERE name LIKE '$safe_name%' AND status = 'Active' LIMIT 1");
    }
    if ($eq && mysqli_num_rows($eq) > 0) {
        $emp_data = mysqli_fetch_assoc($eq);
    }
}

if (!$emp_data) {
    die("
        <div style='font-family:sans-serif; max-width:600px; margin:60px auto; padding:30px; 
                    border:2px solid #ef4444; border-radius:12px; background:#fef2f2; color:#b91c1c;'>
            <h2 style='margin-top:0;'>&#10060; Authentication Failed</h2>
            <p>Could not identify your employee record.</p>
        </div>
    ");
}

$url_email = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';
// =========================================================================


$con = conexion();
if (!$con) die("Database connection failed.");

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');
// isUser();

$current_page    = basename($_SERVER['PHP_SELF']);
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// =========================================================================
// CREATE TABLES IF NOT EXIST
// =========================================================================
$tables = [
"CREATE TABLE IF NOT EXISTS hr_oje_training_materials (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_material_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    heading_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    item_title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT NULL,
    document_path VARCHAR(500) DEFAULT NULL,
    document_filename VARCHAR(255) DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    training_days INT DEFAULT 7,
    oje_days INT DEFAULT 7,
    training_pass_percent DECIMAL(5,2) DEFAULT 95.00,
    oje_pass_percent DECIMAL(5,2) DEFAULT 95.00,
    max_attempts INT DEFAULT 3,
    created_by VARCHAR(255) DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_dept_pos (department_id, position_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_oje_content (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    content TEXT DEFAULT NULL,
    document_path VARCHAR(500) DEFAULT NULL,
    document_filename VARCHAR(255) DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_oje_headings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    heading_name VARCHAR(255) NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_oje_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    heading_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    item_title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT NULL,
    document_path VARCHAR(500) DEFAULT NULL,
    document_filename VARCHAR(255) DEFAULT NULL,
    sort_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    type ENUM('training','oje') NOT NULL DEFAULT 'training',
    question_text TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_by VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_question_options (
    id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    option_label VARCHAR(255) NOT NULL,
    points INT NOT NULL DEFAULT 0,
    is_correct TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_employee_progress (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    stage ENUM('training','training_test','oje_reading','oje_test','certified','failed') DEFAULT 'training',
    training_started_at DATETIME DEFAULT NULL,
    training_completed_at DATETIME DEFAULT NULL,
    oje_started_at DATETIME DEFAULT NULL,
    oje_reading_done_at DATETIME DEFAULT NULL,
    certified_at DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_emp_dept_pos (employee_id, department_id, position_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_material_completions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    item_id INT NOT NULL,
    completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_emp_item (employee_id, item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

"CREATE TABLE IF NOT EXISTS hr_oje_test_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    department_id INT NOT NULL,
    position_id INT NOT NULL DEFAULT 0,
    type ENUM('training','oje') NOT NULL,
    attempt_number INT DEFAULT 1,
    total_marks INT DEFAULT 0,
    obtained_marks INT DEFAULT 0,
    percentage DECIMAL(5,2) DEFAULT 0,
    passed TINYINT(1) DEFAULT 0,
    answers_json LONGTEXT DEFAULT NULL,
    attempted_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
];

foreach ($tables as $sql) mysqli_query($con, $sql);

// Safe column additions   ignore errors if columns already exist
try { mysqli_query($con, "ALTER TABLE hr_oje_training_materials ADD COLUMN trainer_name VARCHAR(255) DEFAULT NULL"); } catch (Throwable $e) {}
try { mysqli_query($con, "ALTER TABLE hr_oje_training_materials ADD COLUMN trainer_designation VARCHAR(255) DEFAULT NULL"); } catch (Throwable $e) {}
try { mysqli_query($con, "ALTER TABLE hr_oje_oje_headings ADD COLUMN trainer_name VARCHAR(255) DEFAULT NULL"); } catch (Throwable $e) {}
try { mysqli_query($con, "ALTER TABLE hr_oje_oje_headings ADD COLUMN trainer_designation VARCHAR(255) DEFAULT NULL"); } catch (Throwable $e) {}

// Upload dir
$upload_dir = 'uploads/hr_oje/';
if (!is_dir($upload_dir)) @mkdir($upload_dir, 0755, true);

// =========================================================================
// CSV IMPORT/EXPORT HANDLERS (GET)
// =========================================================================
if (isset($_GET['action'])) {
    if ($_GET['action'] == 'download_template') {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=OJE_Questions_Template.csv');
        $output = fopen('php://output', 'w');
        fputcsv($output, ['question_text','option1','points1','correct1','option2','points2','correct2','option3','points3','correct3','option4','points4','correct4','option5','points5','correct5','option6','points6','correct6']);
        fputcsv($output, ['Sample Question: Is this true?','Yes','10','Y','Partially','5','N','No','0','N','','','','','','','','','']);
        fclose($output);
        exit;
    }
    if ($_GET['action'] == 'export_questions') {
        $type = $_GET['type'] ?? 'training';
        $dept_id = intval($_GET['dept_id'] ?? 0);
        $pos_id = intval($_GET['pos_id'] ?? 0);
        
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=OJE_Questions_Export_'.ucfirst($type).'.csv');
        $output = fopen('php://output', 'w');
        fputcsv($output, ['question_text','option1','points1','correct1','option2','points2','correct2','option3','points3','correct3','option4','points4','correct4','option5','points5','correct5','option6','points6','correct6']);
        
        $qres = mysqli_query($con, "SELECT * FROM hr_oje_questions WHERE department_id=$dept_id AND position_id=$pos_id AND type='$type' ORDER BY sort_order ASC, id ASC");
        while ($q = mysqli_fetch_assoc($qres)) {
            $row = [$q['question_text']];
            $ores = mysqli_query($con, "SELECT * FROM hr_oje_question_options WHERE question_id={$q['id']} ORDER BY sort_order ASC, id ASC");
            $opts = [];
            while ($o = mysqli_fetch_assoc($ores)) $opts[] = $o;
            
            for ($i=0; $i<6; $i++) {
                if (isset($opts[$i])) {
                    $row[] = $opts[$i]['option_label'];
                    $row[] = $opts[$i]['points'];
                    $row[] = $opts[$i]['is_correct'] ? 'Y' : 'N';
                } else {
                    $row[] = ''; $row[] = ''; $row[] = '';
                }
            }
            fputcsv($output, $row);
        }
        fclose($output);
        exit;
    }
}

// =========================================================================
// AJAX: GET POSITIONS
// =========================================================================
if (isset($_GET['get_positions'])) {
    header('Content-Type: application/json');
    $dept_id = intval($_GET['dept_id']);
    $rows = [];
    if ($dept_id > 0) {
        $q = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$dept_id ORDER BY title ASC");
        if ($q) while ($r = mysqli_fetch_assoc($q)) $rows[] = $r;
    }
    echo json_encode($rows); exit;
}

// =========================================================================
// AJAX: DELETE EMPLOYEE DATA
// =========================================================================
if (isset($_POST['ajax_delete_employee_oje'])) {
    header('Content-Type: application/json');
    $emp_id = intval($_POST['employee_id']);
    if ($emp_id > 0) {

        mysqli_query($con, "DELETE FROM hr_oje_employee_progress WHERE employee_id=$emp_id");
        mysqli_query($con, "DELETE FROM hr_oje_test_attempts WHERE employee_id=$emp_id");
    }
    echo json_encode(['success'=>true]);
    exit;
}

// =========================================================================
// POST HANDLERS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];

    // ---- SAVE CONFIG ----
    if ($action == 'save_config') {
        $dept_id   = intval($_POST['department_id']);
        $pos_id    = intval($_POST['position_id']);
        $t_days    = intval($_POST['training_days']);
        $o_days    = intval($_POST['oje_days']);
        $t_pass    = floatval($_POST['training_pass_percent']);
        $o_pass    = floatval($_POST['oje_pass_percent']);
        $max_att   = intval($_POST['max_attempts']);
        $cb        = mysqli_real_escape_string($con, $currentUserName);
        mysqli_query($con, "INSERT INTO hr_oje_config (department_id,position_id,training_days,oje_days,training_pass_percent,oje_pass_percent,max_attempts,created_by)
            VALUES ($dept_id,$pos_id,$t_days,$o_days,$t_pass,$o_pass,$max_att,'$cb')
            ON DUPLICATE KEY UPDATE training_days=$t_days,oje_days=$o_days,training_pass_percent=$t_pass,oje_pass_percent=$o_pass,max_attempts=$max_att");
        $_SESSION['success_message'] = "Configuration saved.";
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=config"); exit;
    }

    // ---- ADD TRAINING HEADING ----
    if ($action == 'add_training_heading') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $name     = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $trainer  = mysqli_real_escape_string($con, trim($_POST['trainer_name'] ?? ''));
        $tdesig   = mysqli_real_escape_string($con, trim($_POST['trainer_designation'] ?? ''));
        $cb       = mysqli_real_escape_string($con, $currentUserName);
        if ($name) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_training_materials WHERE department_id=$dept_id AND position_id=$pos_id"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            mysqli_query($con, "INSERT INTO hr_oje_training_materials (department_id,position_id,heading_name,trainer_name,trainer_designation,sort_order,created_by) VALUES ($dept_id,$pos_id,'$name','$trainer','$tdesig',$ns,'$cb')");
            $_SESSION['success_message'] = "Training heading added.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=training"); exit;
    }

    // ---- DELETE TRAINING HEADING ----
    if ($action == 'delete_training_heading') {
        $id = intval($_POST['id']);
        $items = mysqli_query($con, "SELECT document_path FROM hr_oje_material_items WHERE heading_id=$id");
        while ($it = mysqli_fetch_assoc($items)) if (!empty($it['document_path']) && file_exists($it['document_path'])) @unlink($it['document_path']);
        mysqli_query($con, "DELETE FROM hr_oje_material_items WHERE heading_id=$id");
        mysqli_query($con, "DELETE FROM hr_oje_training_materials WHERE id=$id");
        $_SESSION['success_message'] = "Heading deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- EDIT TRAINING HEADING ----
    if ($action == 'edit_training_heading') {
        $id      = intval($_POST['id']);
        $name    = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $trainer = mysqli_real_escape_string($con, trim($_POST['trainer_name'] ?? ''));
        $tdesig  = mysqli_real_escape_string($con, trim($_POST['trainer_designation'] ?? ''));
        if ($name && $id > 0) {
            mysqli_query($con, "UPDATE hr_oje_training_materials SET heading_name='$name', trainer_name='$trainer', trainer_designation='$tdesig' WHERE id=$id");
            $_SESSION['success_message'] = "Heading updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- ADD TRAINING ITEM ----
    if ($action == 'add_training_item') {
        $hid     = intval($_POST['heading_id']);
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $title   = mysqli_real_escape_string($con, trim($_POST['item_title']));
        $desc    = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));
        $doc_path = ''; $doc_fname = '';
        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] === UPLOAD_ERR_OK) {
            $df = $_FILES['document_file'];
            $ext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
            if (in_array($ext, ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt','mp4','mov','avi','wmv','webm'])) {
                $p = $upload_dir . 'mat_' . time() . '_' . rand(1000,9999) . '.' . $ext;
                if (move_uploaded_file($df['tmp_name'], $p)) { $doc_path = $p; $doc_fname = $df['name']; }
            }
        }
        if ($title) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_material_items WHERE heading_id=$hid"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            $dp = $doc_path ? "'".mysqli_real_escape_string($con,$doc_path)."'" : "NULL";
            $df2 = $doc_fname ? "'".mysqli_real_escape_string($con,$doc_fname)."'" : "NULL";
            mysqli_query($con, "INSERT INTO hr_oje_material_items (heading_id,department_id,position_id,item_title,description,document_path,document_filename,sort_order) VALUES ($hid,$dept_id,$pos_id,'$title','$desc',$dp,$df2,$ns)");
            $_SESSION['success_message'] = "Training item added.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=training"); exit;
    }

    // ---- DELETE TRAINING ITEM ----
    if ($action == 'delete_training_item') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path FROM hr_oje_material_items WHERE id=$id"));
        if ($row && !empty($row['document_path']) && file_exists($row['document_path'])) @unlink($row['document_path']);
        mysqli_query($con, "DELETE FROM hr_oje_material_items WHERE id=$id");
        $_SESSION['success_message'] = "Item deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- EDIT MATERIAL ITEM ----
    if ($action == 'edit_material_item') {
        $id      = intval($_POST['item_id']);
        $type    = $_POST['item_type'] == 'oje' ? 'oje' : 'training';
        $title   = mysqli_real_escape_string($con, trim($_POST['item_title']));
        $desc    = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));
        $table   = ($type == 'oje') ? 'hr_oje_oje_items' : 'hr_oje_material_items';
        
        $docUpdateSql = "";
        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] === UPLOAD_ERR_OK) {
            $df = $_FILES['document_file'];
            $ext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
            if (in_array($ext, ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt','mp4','mov','avi','wmv','webm'])) {
                $p = $upload_dir . $type . '_' . time() . '_' . rand(1000,9999) . '.' . $ext;
                if (move_uploaded_file($df['tmp_name'], $p)) {
                    // Remove old file
                    $old = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path FROM $table WHERE id=$id"));
                    if ($old && !empty($old['document_path']) && file_exists($old['document_path'])) @unlink($old['document_path']);
                    
                    $dp = mysqli_real_escape_string($con, $p);
                    $df2 = mysqli_real_escape_string($con, $df['name']);
                    $docUpdateSql = ", document_path='$dp', document_filename='$df2'";
                }
            }
        }
        
        if ($title && $id > 0) {
            mysqli_query($con, "UPDATE $table SET item_title='$title', description='$desc' $docUpdateSql WHERE id=$id");
            $_SESSION['success_message'] = "Item updated successfully.";
        }
        $tab = ($type == 'oje') ? 'oje_content' : 'training';
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- ADD OJE HEADING ----
    if ($action == 'add_oje_heading') {
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $name    = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $trainer = mysqli_real_escape_string($con, trim($_POST['trainer_name'] ?? ''));
        $tdesig  = mysqli_real_escape_string($con, trim($_POST['trainer_designation'] ?? ''));
        $cb      = mysqli_real_escape_string($con, $currentUserName);
        if ($name) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_oje_headings WHERE department_id=$dept_id AND position_id=$pos_id"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            mysqli_query($con, "INSERT INTO hr_oje_oje_headings (department_id,position_id,heading_name,trainer_name,trainer_designation,sort_order,created_by) VALUES ($dept_id,$pos_id,'$name','$trainer','$tdesig',$ns,'$cb')");
            $_SESSION['success_message'] = "OJE heading added.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=oje_content"); exit;
    }

    // ---- DELETE OJE HEADING ----
    if ($action == 'delete_oje_heading') {
        $id = intval($_POST['id']);
        $items = mysqli_query($con, "SELECT document_path FROM hr_oje_oje_items WHERE heading_id=$id");
        while ($it = mysqli_fetch_assoc($items)) if (!empty($it['document_path']) && file_exists($it['document_path'])) @unlink($it['document_path']);
        mysqli_query($con, "DELETE FROM hr_oje_oje_items WHERE heading_id=$id");
        mysqli_query($con, "DELETE FROM hr_oje_oje_headings WHERE id=$id");
        $_SESSION['success_message'] = "Heading deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- EDIT OJE HEADING ----
    if ($action == 'edit_oje_heading') {
        $id      = intval($_POST['id']);
        $name    = mysqli_real_escape_string($con, trim($_POST['heading_name']));
        $trainer = mysqli_real_escape_string($con, trim($_POST['trainer_name'] ?? ''));
        $tdesig  = mysqli_real_escape_string($con, trim($_POST['trainer_designation'] ?? ''));
        if ($name && $id > 0) {
            mysqli_query($con, "UPDATE hr_oje_oje_headings SET heading_name='$name', trainer_name='$trainer', trainer_designation='$tdesig' WHERE id=$id");
            $_SESSION['success_message'] = "OJE Heading updated.";
        }
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- ADD OJE ITEM ----
    if ($action == 'add_oje_item') {
        $hid     = intval($_POST['heading_id']);
        $dept_id = intval($_POST['department_id']);
        $pos_id  = intval($_POST['position_id']);
        $title   = mysqli_real_escape_string($con, trim($_POST['item_title']));
        $desc    = mysqli_real_escape_string($con, trim($_POST['description'] ?? ''));
        $doc_path = ''; $doc_fname = '';
        if (isset($_FILES['document_file']) && $_FILES['document_file']['error'] === UPLOAD_ERR_OK) {
            $df = $_FILES['document_file'];
            $ext = strtolower(pathinfo($df['name'], PATHINFO_EXTENSION));
            if (in_array($ext, ['pdf','doc','docx','ppt','pptx','xls','xlsx','txt','mp4','mov','avi','wmv','webm'])) {
                $p = $upload_dir . 'oje_item_' . time() . '_' . rand(1000,9999) . '.' . $ext;
                if (move_uploaded_file($df['tmp_name'], $p)) { $doc_path = $p; $doc_fname = $df['name']; }
            }
        }
        if ($title) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_oje_items WHERE heading_id=$hid"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            $dp = $doc_path ? "'".mysqli_real_escape_string($con,$doc_path)."'" : "NULL";
            $df2 = $doc_fname ? "'".mysqli_real_escape_string($con,$doc_fname)."'" : "NULL";
            mysqli_query($con, "INSERT INTO hr_oje_oje_items (heading_id,department_id,position_id,item_title,description,document_path,document_filename,sort_order) VALUES ($hid,$dept_id,$pos_id,'$title','$desc',$dp,$df2,$ns)");
            $_SESSION['success_message'] = "OJE item added.";
        }
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=oje_content"); exit;
    }

    // ---- DELETE OJE ITEM ----
    if ($action == 'delete_oje_item') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT document_path FROM hr_oje_oje_items WHERE id=$id"));
        if ($row && !empty($row['document_path']) && file_exists($row['document_path'])) @unlink($row['document_path']);
        mysqli_query($con, "DELETE FROM hr_oje_oje_items WHERE id=$id");
        $_SESSION['success_message'] = "OJE item deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }

    // ---- ADD QUESTION ----
    if ($action == 'add_question') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $type     = $_POST['q_type'] == 'oje' ? 'oje' : 'training';
        $qtext    = mysqli_real_escape_string($con, trim($_POST['question_text']));
        $cb       = mysqli_real_escape_string($con, $currentUserName);
        $options  = $_POST['options'] ?? [];
        $points   = $_POST['points'] ?? [];
        $correct  = intval($_POST['correct_option'] ?? 0);
        if ($qtext && !empty($options)) {
            $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_questions WHERE department_id=$dept_id AND position_id=$pos_id AND type='$type'"));
            $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
            mysqli_query($con, "INSERT INTO hr_oje_questions (department_id,position_id,type,question_text,sort_order,created_by) VALUES ($dept_id,$pos_id,'$type','$qtext',$ns,'$cb')");
            $qid = mysqli_insert_id($con);
            foreach ($options as $i => $opt) {
                $ol = mysqli_real_escape_string($con, trim($opt));
                $pts = intval($points[$i] ?? 0);
                $isc = ($i == $correct) ? 1 : 0;
                if ($ol) mysqli_query($con, "INSERT INTO hr_oje_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$i)");
            }
            $_SESSION['success_message'] = "Question added.";
        }
        $tab = ($type == 'oje') ? 'oje_test' : 'training_test';
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=$tab"); exit;
    }

    // ---- EDIT QUESTION ----
    if ($action == 'edit_question') {
        $qid      = intval($_POST['question_id']);
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $type     = $_POST['q_type'] == 'oje' ? 'oje' : 'training';
        $qtext    = mysqli_real_escape_string($con, trim($_POST['question_text']));
        $options  = $_POST['options'] ?? [];
        $points   = $_POST['points'] ?? [];
        $correct  = intval($_POST['correct_option'] ?? 0);
        
        if ($qid > 0 && $qtext && !empty($options)) {
            mysqli_query($con, "UPDATE hr_oje_questions SET question_text='$qtext' WHERE id=$qid");
            mysqli_query($con, "DELETE FROM hr_oje_question_options WHERE question_id=$qid");
            foreach ($options as $i => $opt) {
                $ol = mysqli_real_escape_string($con, trim($opt));
                $pts = intval($points[$i] ?? 0);
                $isc = ($i == $correct) ? 1 : 0;
                if ($ol) mysqli_query($con, "INSERT INTO hr_oje_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$i)");
            }
            $_SESSION['success_message'] = "Question updated successfully.";
        }
        $tab = ($type == 'oje') ? 'oje_test' : 'training_test';
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=$tab"); exit;
    }

    // ---- IMPORT QUESTIONS ----
    if ($action == 'import_questions') {
        $dept_id  = intval($_POST['department_id']);
        $pos_id   = intval($_POST['position_id']);
        $type     = $_POST['q_type'] == 'oje' ? 'oje' : 'training';
        $cb       = mysqli_real_escape_string($con, $currentUserName);
        
        if (isset($_FILES['csv_file']) && $_FILES['csv_file']['error'] === UPLOAD_ERR_OK) {
            $file = $_FILES['csv_file']['tmp_name'];
            if (($handle = fopen($file, "r")) !== FALSE) {
                // skip header
                $header = fgetcsv($handle, 1000, ",");
                $imported = 0;
                while (($data = fgetcsv($handle, 1000, ",")) !== FALSE) {
                    $qtext = mysqli_real_escape_string($con, trim($data[0] ?? ''));
                    if (!$qtext) continue;
                    
                    $ms = mysqli_fetch_assoc(mysqli_query($con, "SELECT MAX(sort_order) as m FROM hr_oje_questions WHERE department_id=$dept_id AND position_id=$pos_id AND type='$type'"));
                    $ns = ($ms['m'] !== null) ? intval($ms['m'])+1 : 0;
                    mysqli_query($con, "INSERT INTO hr_oje_questions (department_id,position_id,type,question_text,sort_order,created_by) VALUES ($dept_id,$pos_id,'$type','$qtext',$ns,'$cb')");
                    $qid = mysqli_insert_id($con);
                    
                    $col = 1;
                    $optIndex = 0;
                    while ($col < count($data) && $col < 19) {
                        $ol = mysqli_real_escape_string($con, trim($data[$col]));
                        $pts = intval($data[$col+1] ?? 0);
                        $is_corr_str = strtoupper(trim($data[$col+2] ?? 'N'));
                        $isc = ($is_corr_str == 'Y' || $is_corr_str == '1') ? 1 : 0;
                        if ($ol) {
                            mysqli_query($con, "INSERT INTO hr_oje_question_options (question_id,option_label,points,is_correct,sort_order) VALUES ($qid,'$ol',$pts,$isc,$optIndex)");
                            $optIndex++;
                        }
                        $col += 3;
                    }
                    $imported++;
                }
                fclose($handle);
                $_SESSION['success_message'] = "$imported questions imported successfully.";
            } else {
                $_SESSION['error_message'] = "Could not open CSV file.";
            }
        } else {
            $_SESSION['error_message'] = "Please upload a valid CSV file.";
        }
        $tab = ($type == 'oje') ? 'oje_test' : 'training_test';
        header("Location: $current_page?dept_id=$dept_id&pos_id=$pos_id&tab=$tab"); exit;
    }

    // ---- DELETE QUESTION ----
    if ($action == 'delete_question') {
        $id = intval($_POST['id']);
        $row = mysqli_fetch_assoc(mysqli_query($con, "SELECT type,department_id,position_id FROM hr_oje_questions WHERE id=$id"));
        mysqli_query($con, "DELETE FROM hr_oje_question_options WHERE question_id=$id");
        mysqli_query($con, "DELETE FROM hr_oje_questions WHERE id=$id");
        $_SESSION['success_message'] = "Question deleted.";
        header("Location: " . $_SERVER['HTTP_REFERER']); exit;
    }
}

// =========================================================================
// PAGE DATA
// =========================================================================
$sel_dept = isset($_GET['dept_id']) ? intval($_GET['dept_id']) : 0;
$sel_pos  = isset($_GET['pos_id'])  ? intval($_GET['pos_id'])  : 0;
$active_tab = $_GET['tab'] ?? 'training';

$departments = [];
$dq = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");
while ($d = mysqli_fetch_assoc($dq)) $departments[] = $d;

$positions = [];
if ($sel_dept > 0) {
    $pq = mysqli_query($con, "SELECT id, title FROM hr_positions WHERE department_id=$sel_dept ORDER BY title ASC");
    if ($pq) while ($p = mysqli_fetch_assoc($pq)) $positions[] = $p;
}

// Config
$config = null;
if ($sel_dept > 0) {
    $config = mysqli_fetch_assoc(mysqli_query($con, "SELECT * FROM hr_oje_config WHERE department_id=$sel_dept AND position_id=$sel_pos LIMIT 1"));
}

// Training materials
$training_headings = [];
if ($sel_dept > 0) {
    $hq = mysqli_query($con, "SELECT * FROM hr_oje_training_materials WHERE department_id=$sel_dept AND position_id=$sel_pos ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($hq)) {
        $h['items'] = [];
        $iq = mysqli_query($con, "SELECT * FROM hr_oje_material_items WHERE heading_id={$h['id']} ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($iq)) $h['items'][] = $i;
        $training_headings[] = $h;
    }
}

// OJE Content
$oje_headings = [];
if ($sel_dept > 0) {
    $oq = mysqli_query($con, "SELECT * FROM hr_oje_oje_headings WHERE department_id=$sel_dept AND position_id=$sel_pos ORDER BY sort_order ASC, id ASC");
    while ($h = mysqli_fetch_assoc($oq)) {
        $h['items'] = [];
        $iq = mysqli_query($con, "SELECT * FROM hr_oje_oje_items WHERE heading_id={$h['id']} ORDER BY sort_order ASC, id ASC");
        while ($i = mysqli_fetch_assoc($iq)) $h['items'][] = $i;
        $oje_headings[] = $h;
    }
}

// Questions
$training_questions = [];
$oje_questions = [];
if ($sel_dept > 0) {
    $qq = mysqli_query($con, "SELECT q.*, GROUP_CONCAT(o.id,'::',o.option_label,'::',o.points,'::',o.is_correct ORDER BY o.sort_order SEPARATOR '||') as options_raw FROM hr_oje_questions q LEFT JOIN hr_oje_question_options o ON o.question_id=q.id WHERE q.department_id=$sel_dept AND q.position_id=$sel_pos GROUP BY q.id ORDER BY q.type, q.sort_order ASC");
    while ($q = mysqli_fetch_assoc($qq)) {
        $q['options'] = [];
        if (!empty($q['options_raw'])) {
            foreach (explode('||', $q['options_raw']) as $opt) {
                $parts = explode('::', $opt);
                if (count($parts) == 4) $q['options'][] = ['id'=>$parts[0],'label'=>$parts[1],'points'=>$parts[2],'is_correct'=>$parts[3]];
            }
        }
        if ($q['type'] == 'training') $training_questions[] = $q;
        else $oje_questions[] = $q;
    }
}

// Employee performance data
$employee_performance = [];
if ($sel_dept > 0) {
    $epq = mysqli_query($con, "SELECT p.*, e.name as emp_name, e.hire_date, e.position, e.department,
        (SELECT COUNT(*) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='training') as training_attempts,
        (SELECT MAX(percentage) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='training') as training_best_pct,
        (SELECT COUNT(*) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='oje') as oje_attempts,
        (SELECT MAX(percentage) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='oje') as oje_best_pct,
        (SELECT training_days FROM hr_oje_config WHERE department_id=p.department_id AND (position_id=p.position_id OR position_id=0) ORDER BY position_id DESC LIMIT 1) as config_training_days,
        (SELECT oje_days FROM hr_oje_config WHERE department_id=p.department_id AND (position_id=p.position_id OR position_id=0) ORDER BY position_id DESC LIMIT 1) as config_oje_days
        FROM hr_oje_employee_progress p
        INNER JOIN hr_employees e ON e.id=p.employee_id
        WHERE p.department_id=$sel_dept" . ($sel_pos > 0 ? " AND p.position_id=$sel_pos" : "") . "
        ORDER BY e.name ASC");
    while ($ep = mysqli_fetch_assoc($epq)) $employee_performance[] = $ep;
}

// Helper: get dept name / pos title
function getDeptName($depts, $id) { foreach($depts as $d) if($d['id']==$id) return $d['name']; return ''; }
function getPosTitle($positions, $id) { foreach($positions as $p) if($p['id']==$id) return $p['title']; return 'All Positions'; }

$sel_dept_name = getDeptName($departments, $sel_dept);
$sel_pos_title = getPosTitle($positions, $sel_pos);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>OJE Management - <?php echo htmlspecialchars($_SESSION['ge_cname'] ?? 'CRM'); ?></title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css"/>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"/>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap" rel="stylesheet"/>
<link rel="stylesheet" href="css/app.css" type="text/css"/>
<style>
:root {
  --navy: #0f2557;
  --blue: #1a3fc4;
  --light-blue: #e0e7ff;
  --green: #10b981;
  --amber: #f59e0b;
  --red: #ef4444;
  --gray-bg: #f0f4f8;
}
* { box-sizing: border-box; }
body { font-family: 'Plus Jakarta Sans', sans-serif; background: var(--gray-bg); }

/* Navigation Tabs */
.nav-tabs-container { display: flex; gap: 10px; margin-bottom: 24px; }
.nav-btn {
    padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
    font-weight: 600; text-decoration: none; box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
    display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
}
.nav-btn:hover { text-decoration: none; color: #1e3a8a; }
.nav-btn.active { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; }

.oje-header {
  background: linear-gradient(135deg, #0f2557 0%, #1a3fc4 100%);
  padding: 22px 32px; display: flex; justify-content: space-between; align-items: center;
  border-radius: 12px; margin-bottom: 24px; box-shadow: 0 4px 20px rgba(15,37,87,0.3);
}
.oje-header h1 { color: #fff; font-weight: 800; margin: 0; font-size: 1.5rem; }
.oje-header p { color: rgba(255,255,255,0.65); font-size: 12px; margin: 4px 0 0; }

.filter-bar {
  background: #fff; padding: 18px 24px; border-radius: 10px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.06); margin-bottom: 20px;
  display: flex; align-items: center; flex-wrap: wrap; gap: 14px;
}
.filter-bar label { font-weight: 700; font-size: 13px; color: var(--navy); margin: 0; }
.filter-bar select { border: 2px solid #e0e7ff; border-radius: 8px; padding: 8px 14px; font-size: 13px; font-weight: 600; color: var(--navy); min-width: 200px; }

/* DataTables controls alignment fix */
.dataTables_wrapper .dt-buttons { display: flex; gap: 8px; flex-wrap: wrap; }
.dataTables_wrapper .dataTables_filter input { border: 2px solid #e0e7ff; border-radius: 8px; padding: 6px 12px; font-size: 13px; margin-left: 6px; }
.dataTables_wrapper .dataTables_length select { border: 2px solid #e0e7ff; border-radius: 8px; padding: 6px 10px; font-size: 13px; }

.main-tabs { display: flex; gap: 0; border-bottom: 2px solid #e0e7ff; margin-bottom: 24px; flex-wrap: wrap; }
.main-tab {
  padding: 12px 22px; font-weight: 700; font-size: 13px; color: #64748b;
  cursor: pointer; border-bottom: 3px solid transparent; margin-bottom: -2px;
  transition: all .2s; white-space: nowrap;
}
.main-tab:hover { color: var(--blue); }
.main-tab.active { color: var(--blue); border-bottom-color: var(--blue); }

.card-box { background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 2px 10px rgba(0,0,0,0.06); margin-bottom: 20px; }
.card-box h5 { font-weight: 800; color: var(--navy); margin-bottom: 16px; font-size: 14px; }

.heading-block { border: 1.5px solid #e0e7ff; border-radius: 10px; margin-bottom: 16px; overflow: hidden; }
.heading-block-head {
  background: #f8faff; padding: 12px 18px; display: flex; justify-content: space-between; align-items: center;
  border-bottom: 1.5px solid #e0e7ff;
}
.heading-block-head h6 { margin: 0; font-weight: 800; color: var(--navy); font-size: 13px; }
.heading-block-body { padding: 14px 18px; }

.material-item {
  display: flex; justify-content: space-between; align-items: flex-start; gap: 12px;
  padding: 12px 14px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px;
}
.material-item .item-title { font-weight: 700; color: var(--navy); font-size: 13px; margin-bottom: 3px; }
.material-item .item-desc { font-size: 11px; color: #64748b; }
.doc-pill {
  display: inline-flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 700;
  padding: 3px 9px; border-radius: 12px; background: #ede9fe; color: #5b21b6; text-decoration: none;
}
.doc-pill.none { background: #f1f5f9; color: #94a3b8; }

.q-card { border: 1.5px solid #e0e7ff; border-radius: 10px; padding: 16px; margin-bottom: 12px; }
.q-card .q-num { font-size: 11px; font-weight: 800; color: var(--blue); text-transform: uppercase; margin-bottom: 6px; }
.q-card .q-text { font-weight: 700; color: var(--navy); font-size: 14px; margin-bottom: 10px; }
.option-row { display: flex; align-items: center; gap: 8px; padding: 6px 10px; border-radius: 6px; margin-bottom: 4px; background: #f8fafc; }
.option-row.correct { background: #d1fae5; }
.option-badge { font-size: 11px; font-weight: 800; padding: 2px 8px; border-radius: 10px; }
.option-badge.correct { background: #10b981; color: #fff; }
.option-badge.pts { background: #e0e7ff; color: var(--blue); }

.btn-add { background: var(--blue); color: #fff; border: none; padding: 8px 18px; border-radius: 8px; font-weight: 700; font-size: 13px; cursor: pointer; }
.btn-add:hover { background: var(--navy); }
.btn-sm-del { background: #fee2e2; color: var(--red); border: 1px solid #fca5a5; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; }

/* Performance table */
.perf-table { width: 100%; border-collapse: collapse; }
.perf-table th { background: #f0f4f8; color: var(--navy); font-weight: 800; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; padding: 10px 14px; border-bottom: 2px solid #e0e7ff; }
.perf-table td { padding: 12px 14px; border-bottom: 1px solid #f1f5f9; font-size: 13px; vertical-align: middle; }
.perf-table tr:hover td { background: #f8faff; }
.stage-badge {
  display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 12px;
  font-size: 11px; font-weight: 800;
}
.stage-badge.training { background: #e0e7ff; color: var(--blue); }
.stage-badge.training_test { background: #fef3c7; color: #92400e; }
.stage-badge.oje_reading { background: #dbeafe; color: #1e40af; }
.stage-badge.oje_test { background: #ede9fe; color: #5b21b6; }
.stage-badge.certified { background: #d1fae5; color: #065f46; }
.stage-badge.failed { background: #fee2e2; color: #991b1b; }

.pct-bar { height: 6px; border-radius: 3px; background: #e0e7ff; margin-top: 4px; }
.pct-bar-fill { height: 100%; border-radius: 3px; transition: width .5s; }

.empty-hint { text-align: center; padding: 40px; color: #94a3b8; }
.config-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
@media(max-width:600px){ .config-grid { grid-template-columns: 1fr; } }

.form-field { margin-bottom: 16px; }
.form-field label { display: block; font-weight: 700; font-size: 12px; color: var(--navy); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.5px; }
.form-field input, .form-field select, .form-field textarea {
  width: 100%; padding: 10px 14px; border: 2px solid #e0e7ff; border-radius: 8px;
  font-size: 13px; font-weight: 600; color: var(--navy); font-family: inherit; transition: .2s;
}
.form-field input:focus, .form-field select:focus, .form-field textarea:focus {
  border-color: var(--blue); box-shadow: 0 0 0 3px rgba(26,63,196,.08); outline: none;
}
.option-builder { border: 1.5px solid #e0e7ff; border-radius: 8px; overflow: hidden; }
.option-builder-row { display: grid; grid-template-columns: 1fr auto auto auto; gap: 8px; align-items: center; padding: 8px 12px; border-bottom: 1px solid #f1f5f9; }
.option-builder-row:last-child { border-bottom: none; }
.option-builder-header { background: #f8faff; font-weight: 700; font-size: 11px; text-transform: uppercase; color: #94a3b8; }
</style>
</head>
<body>
<div class="container-fluid" style="padding: 30px; max-width: 1400px; margin: 0 auto;">
<?php if(isset($_SESSION['success_message'])): ?>
<div class="alert alert-success alert-dismissible fade show"><i class="fas fa-check-circle mr-2"></i><?php echo $_SESSION['success_message']; unset($_SESSION['success_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>
<?php if(isset($_SESSION['error_message'])): ?>
<div class="alert alert-danger alert-dismissible fade show"><i class="fas fa-exclamation-circle mr-2"></i><?php echo $_SESSION['error_message']; unset($_SESSION['error_message']); ?><button type="button" class="close" data-dismiss="alert">&times;</button></div>
<?php endif; ?>

<!-- HEADER -->
<div class="oje-header">
  <div>
    <h1><i class="fas fa-graduation-cap mr-2"></i> Training & OJE Management</h1>
    <p>Configure training materials, tests, and track employee progress</p>
  </div>
  <div>
    <?php if ($sel_dept > 0): ?>
      <a href="hr-OJE.php" class="btn btn-light btn-sm mr-2"><i class="fas fa-layer-group mr-1"></i> All Configurations</a>
    <?php endif; ?>
    
    <?php
    $is_admin = isset($_SESSION['user_name']) && in_array(trim($_SESSION['user_name']), ['Abishek Veeraswamy', 'Abishek', 'abishek']);
    $dashboard_url = $is_admin ? 'index.php' : 'raise-a-ticket.php';
    ?>
    <a href="<?php echo $dashboard_url; ?>" class="btn-action btn-dashboard" style="background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%); box-shadow: 0 4px 15px rgba(139, 92, 246, 0.3); color: white; text-decoration: none; padding: 10px 20px; border-radius: 8px; font-weight: 600; display: inline-flex; align-items: center; gap: 8px; transition: all 0.3s; margin-right: 15px;">
      <i class="fas fa-arrow-left"></i> Back to Dashboard
    </a>

  </div>
</div>

<!-- NAVIGATION TABS -->
<div class="nav-tabs-container">
    <a href="hr-OJE.php" class="nav-btn active">
        <i class="fas fa-graduation-cap"></i> Training & OJE
    </a>
    <a href="hr-recert-crosstraining.php" class="nav-btn">
        <i class="fas fa-sync-alt"></i> Recertification & Cross Training
    </a>
    <a href="hr-recert-crosstraining.php?tab=history" class="nav-btn">
        <i class="fas fa-history"></i> History & Analytics
    </a>
</div>

<!-- FILTER BAR -->
<div class="filter-bar">
  <form method="GET" class="d-flex align-items-center flex-wrap" style="gap:14px;" id="filterForm">
    <input type="hidden" name="tab" value="<?php echo htmlspecialchars($active_tab); ?>">
    <div class="d-flex align-items-center" style="gap:8px;">
      <label>Department:</label>
      <select name="dept_id" onchange="document.getElementById('filterForm').submit()">
        <option value="0">All Departments</option>
        <?php foreach($departments as $d): ?>
        <option value="<?php echo $d['id']; ?>" <?php if($sel_dept==$d['id']) echo 'selected'; ?>><?php echo htmlspecialchars($d['name']); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="d-flex align-items-center" style="gap:8px;">
      <label>Position:</label>
      <select name="pos_id" onchange="document.getElementById('filterForm').submit()">
        <option value="0">All Positions</option>
        <?php foreach($positions as $p): ?>
        <option value="<?php echo $p['id']; ?>" <?php if($sel_pos==$p['id']) echo 'selected'; ?>><?php echo htmlspecialchars($p['title']); ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <?php if($sel_dept > 0): ?>
    <span style="font-size:12px;color:#64748b;"><i class="fas fa-filter mr-1"></i><?php echo htmlspecialchars($sel_dept_name); ?> <?php echo $sel_pos > 0 ? 'â†’ '.htmlspecialchars($sel_pos_title) : '(All Positions)'; ?></span>
    <?php endif; ?>
  </form>
</div>

<?php if ($sel_dept == 0): ?>

<div class="d-flex justify-content-between align-items-center mb-4 mt-2">
    <h4 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-layer-group mr-2 text-primary"></i>All Training & OJE Configurations</h4>
    <div>
      <button type="button" class="btn btn-outline-primary mr-2" style="font-weight:700;border-radius:8px;border-color:var(--blue);color:var(--blue);" onclick="$('#allEmpOjeSection').slideToggle();"><i class="fas fa-users mr-1"></i> View All Employees</button>
      <button class="btn-add" data-toggle="modal" data-target="#newConfigModal"><i class="fas fa-plus mr-1"></i> New Configuration</button>
    </div>
</div>

<?php
// Get all unique configs
$overviewQuery = "
    SELECT 
        d.id as dept_id, d.name as dept_name,
        p.id as pos_id, p.title as pos_title,
        (SELECT COUNT(*) FROM hr_oje_training_materials WHERE department_id = d.id AND position_id = COALESCE(p.id, 0)) as training_count,
        (SELECT COUNT(*) FROM hr_oje_oje_headings WHERE department_id = d.id AND position_id = COALESCE(p.id, 0)) as oje_count
    FROM (
        SELECT department_id, position_id FROM hr_oje_training_materials
        UNION
        SELECT department_id, position_id FROM hr_oje_oje_headings
    ) as configs
    JOIN hr_departments d ON d.id = configs.department_id
    LEFT JOIN hr_positions p ON p.id = configs.position_id
    ORDER BY d.name ASC, p.title ASC
";
$overviewRes = mysqli_query($con, $overviewQuery);
?>

<div class="row">
<?php 
if ($overviewRes && mysqli_num_rows($overviewRes) > 0) {
    while ($row = mysqli_fetch_assoc($overviewRes)) {
        $dept_name = $row['dept_name'];
        $pos_title = empty($row['pos_id']) ? 'All Positions' : $row['pos_title'];
        $link = "hr-OJE.php?dept_id={$row['dept_id']}&pos_id=" . intval($row['pos_id']);
        
        echo '<div class="col-md-4 mb-4">';
        echo '<div class="card-box" style="height:100%; display:flex; flex-direction:column; padding:20px;">';
        echo '<div style="flex:1;">';
        echo '<div style="font-size:12px; font-weight:800; color:#64748b; text-transform:uppercase; margin-bottom:4px;"><i class="fas fa-building mr-1"></i>' . htmlspecialchars($dept_name) . '</div>';
        echo '<h5 style="font-weight:800; color:#0f2557; margin-bottom:12px;"><i class="fas fa-briefcase mr-1" style="color:#1e40af;"></i>' . htmlspecialchars($pos_title) . '</h5>';
        
        echo '<div style="display:flex; gap:10px; margin-bottom:15px; flex-wrap:wrap;">';
        echo '<span style="font-size:12px; font-weight:700; background:#f0fdf4; color:#16a34a; padding:4px 10px; border-radius:20px;"><i class="fas fa-book-open mr-1"></i>' . $row['training_count'] . ' Training Headings</span>';
        echo '<span style="font-size:12px; font-weight:700; background:#eff6ff; color:#2563eb; padding:4px 10px; border-radius:20px;"><i class="fas fa-clipboard-check mr-1"></i>' . $row['oje_count'] . ' OJE Headings</span>';
        echo '</div>';
        echo '</div>';
        
        echo '<a href="'.$link.'" class="btn btn-primary btn-sm text-center" style="display:block; text-decoration:none; border-radius:8px; font-weight:700;"><i class="fas fa-cog mr-1"></i> Manage Configuration</a>';
        echo '</div>';
        echo '</div>';
    }
} else {
    echo '<div class="col-12"><div class="card-box"><div class="empty-hint"><i class="fas fa-clipboard-list fa-2x mb-3"></i><p style="margin:0;">No Training or OJE configurations found. Create one to get started.</p></div></div></div>';
}
?>
</div>

<?php
// ---- ALL EMPLOYEES (combined across departments/positions, respects filters) ----
$allEmpWhere = ["e.name != 'Unknown'"];
if ($sel_dept > 0) { $allEmpWhere[] = "p.department_id=$sel_dept"; if ($sel_pos > 0) $allEmpWhere[] = "p.position_id=$sel_pos"; }
$allEmpWhereSql = $allEmpWhere ? "WHERE " . implode(" AND ", $allEmpWhere) : "";
$allEmpQ = mysqli_query($con, "SELECT p.*, e.name as emp_name, e.department as emp_dept, e.position as emp_pos, e.hire_date, d.name as dept_name, pos.title as pos_title,
    (SELECT COUNT(*) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='training') as training_attempts,
    (SELECT MAX(percentage) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='training') as training_best_pct,
    (SELECT COUNT(*) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='oje') as oje_attempts,
    (SELECT MAX(percentage) FROM hr_oje_test_attempts WHERE employee_id=p.employee_id AND department_id=p.department_id AND position_id=p.position_id AND type='oje') as oje_best_pct
    FROM hr_oje_employee_progress p
    INNER JOIN hr_employees e ON e.id=p.employee_id
    LEFT JOIN hr_departments d ON d.id=p.department_id
    LEFT JOIN hr_positions pos ON pos.id=p.position_id
    $allEmpWhereSql
    ORDER BY e.name ASC");
$allEmpRows = [];
if ($allEmpQ) while ($r = mysqli_fetch_assoc($allEmpQ)) $allEmpRows[] = $r;
?>

<div id="allEmpOjeSection" style="display:none;">
<div class="d-flex justify-content-between align-items-center mb-3 mt-4">
  <h4 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-users mr-2 text-primary"></i>Employee Training & OJE - All Employees</h4>
  <span style="font-size:12px;color:#64748b;" id="allEmpLiveCount"><?php echo count($allEmpRows); ?> employees found</span>
</div>
<?php if (!empty($allEmpRows)): ?>
<div class="card-box" id="allEmpFilterBar" style="margin-bottom:14px;">
  <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Employees</h5>
  <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
    <div style="flex:1;min-width:180px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
      <input type="text" id="ae-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
    </div>
    <div style="flex:1;min-width:180px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Department</label>
      <select id="ae-dept" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
        <option value="">All Departments</option>
        <?php foreach ($departments as $d): ?><option value="<?php echo htmlspecialchars($d['name']); ?>"><?php echo htmlspecialchars($d['name']); ?></option><?php endforeach; ?>
      </select>
    </div>
    <div style="flex:1;min-width:180px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Position</label>
      <select id="ae-pos" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
        <option value="">All Positions</option>
        <?php
        $all_pos_ae = mysqli_query($con, "SELECT DISTINCT title FROM hr_positions ORDER BY title ASC");
        if ($all_pos_ae) while ($pr = mysqli_fetch_assoc($all_pos_ae)): ?>
          <option value="<?php echo htmlspecialchars($pr['title']); ?>"><?php echo htmlspecialchars($pr['title']); ?></option>
        <?php endwhile; ?>
      </select>
    </div>
    <div style="flex:1;min-width:160px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Stage</label>
      <select id="ae-stage" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
        <option value="">All Stages</option>
        <option value="training">Training</option>
        <option value="training_test">Training Test</option>
        <option value="oje_reading">OJE Reading</option>
        <option value="oje_test">OJE Test</option>
        <option value="certified">Certified</option>
        <option value="failed">Failed</option>
      </select>
    </div>
    <div style="min-width:150px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date From</label>
      <input type="date" id="ae-from" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
    </div>
    <div style="min-width:150px;">
      <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date To</label>
      <input type="date" id="ae-to" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
    </div>
    <div>
      <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetAEFilters()"><i class="fas fa-redo mr-1"></i> Reset</button>
    </div>
    <div style="display:flex;gap:8px;">
      <button type="button" class="btn btn-success btn-sm" onclick="window.tAE && window.tAE.button(0).trigger();"><i class="fas fa-file-excel mr-1"></i> Excel</button>
      <button type="button" class="btn btn-info btn-sm" onclick="window.tAE && window.tAE.button(1).trigger();"><i class="fas fa-file-csv mr-1"></i> CSV</button>
    </div>
  </div>
</div>
<?php endif; ?>
<div class="card-box" style="padding:0;overflow:hidden;">
  <?php if (empty($allEmpRows)): ?>
    <div class="empty-hint"><i class="fas fa-users fa-2x mb-2"></i><p>No employee progress data found<?php echo $sel_dept>0 ? ' for this filter.' : '.'; ?></p></div>
  <?php else: ?>
  <div style="overflow-x:auto;">
    <table class="perf-table" id="allEmpOjeTable">
      <thead>
        <tr>
          <th>Employee</th>
          <th>Department / Position</th>
          <th>Stage</th>
          <th>Training Test</th>
          <th>OJE Test</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach ($allEmpRows as $ep): 
          $isCross = (strtolower(trim($ep['emp_dept'] ?? '')) !== strtolower(trim($ep['dept_name'] ?? ''))) || (strtolower(trim($ep['emp_pos'] ?? '')) !== strtolower(trim($ep['pos_title'] ?? 'All Positions')));
        ?>
        <tr data-empname="<?php echo htmlspecialchars(strtolower($ep['emp_name'] ?? '')); ?>" data-dept="<?php echo htmlspecialchars($ep['dept_name'] ?? ''); ?>" data-pos="<?php echo htmlspecialchars($ep['pos_title'] ?? ''); ?>" data-stage="<?php echo htmlspecialchars($ep['stage'] ?? ''); ?>" data-startdate="<?php echo !empty($ep['training_started_at']) ? date('Y-m-d', strtotime($ep['training_started_at'])) : ''; ?>">
          <td>
            <div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($ep['emp_name']); ?></div>
            <?php if ($isCross): ?>
              <div style="margin-top:2px;"><span style="font-size:10px;font-weight:800;background:#ede9fe;color:#5b21b6;padding:2px 6px;border-radius:4px;text-transform:uppercase;"><i class="fas fa-random mr-1"></i>Cross Training</span></div>
            <?php else: ?>
              <div style="margin-top:2px;"><span style="font-size:10px;font-weight:800;background:#e0e7ff;color:#1e40af;padding:2px 6px;border-radius:4px;text-transform:uppercase;"><i class="fas fa-user-graduate mr-1"></i>OJE</span></div>
            <?php endif; ?>
          </td>
          <td>
            <div style="font-size:12px;font-weight:700;color:#334155;"><?php echo htmlspecialchars($ep['dept_name'] ?? ' '); ?></div>
            <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($ep['pos_title'] ?? 'All Positions'); ?></div>
          </td>
          <td>
            <?php $stage_labels = ['training'=>'Training','training_test'=>'Training Test','oje_reading'=>'OJE Reading','oje_test'=>'OJE Test','certified'=>'Certified','failed'=>'Failed']; ?>
            <span class="stage-badge <?php echo $ep['stage']; ?>"><?php echo $stage_labels[$ep['stage']] ?? $ep['stage']; ?></span>
          </td>
          <td>
            <?php if ($ep['training_attempts'] > 0): ?>
              <span style="font-weight:700;font-size:13px;color:<?php echo $ep['training_best_pct']>=95?'#065f46':'#991b1b'; ?>;"><?php echo number_format($ep['training_best_pct'],1); ?>%</span>
            <?php else: ?><span style="color:#94a3b8;font-size:12px;">Not taken</span><?php endif; ?>
          </td>
          <td>
            <?php if ($ep['oje_attempts'] > 0): ?>
              <span style="font-weight:700;font-size:13px;color:<?php echo $ep['oje_best_pct']>=95?'#065f46':'#991b1b'; ?>;"><?php echo number_format($ep['oje_best_pct'],1); ?>%</span>
            <?php else: ?><span style="color:#94a3b8;font-size:12px;">Not taken</span><?php endif; ?>
          </td>
          <td>
            <?php if ($ep['stage'] == 'certified'): ?>
              <span style="color:#065f46;font-weight:800;font-size:12px;"><i class="fas fa-certificate mr-1"></i> Certified</span>
            <?php elseif ($ep['stage'] == 'failed'): ?>
              <span style="color:#991b1b;font-weight:800;font-size:12px;"><i class="fas fa-times-circle mr-1"></i> Failed</span>
            <?php else: ?>
              <span style="color:#92400e;font-weight:700;font-size:12px;"><i class="fas fa-clock mr-1"></i> In Progress</span>
            <?php endif; ?>
          </td>
          <td>
            <div style="display:flex;gap:8px;">
              <button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;"
                onclick="openUnifiedViewModal(<?php echo $ep['employee_id']; ?>, <?php echo $ep['department_id']; ?>, <?php echo $ep['position_id']; ?>, 'oje', 0, '<?php echo htmlspecialchars(addslashes($ep['emp_name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($ep['dept_name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($ep['pos_title'] ?? '')); ?>')">
                <i class="fas fa-eye mr-1"></i> View
              </button>
              <button onclick="deleteEmployeeOJE(<?php echo $ep['employee_id']; ?>)" class="btn btn-sm" style="background:#fee2e2;color:#991b1b;font-size:11px;font-weight:700;border:none;cursor:pointer;"><i class="fas fa-trash"></i> Delete</button>
            </div>
          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <?php endif; ?>
</div>
</div>

<?php else: ?>

<!-- MAIN TABS -->
<div class="main-tabs">
  <?php
  $tabs = [
    'training'      => ['icon'=>'fas fa-book-open',       'label'=>'Training Materials'],
    'training_test' => ['icon'=>'fas fa-question-circle', 'label'=>'Training Test'],
    'oje_content'   => ['icon'=>'fas fa-briefcase',       'label'=>'OJE Content'],
    'oje_test'      => ['icon'=>'fas fa-clipboard-check', 'label'=>'OJE Test'],
    'config'        => ['icon'=>'fas fa-cog',             'label'=>'Configuration'],
    'performance'   => ['icon'=>'fas fa-chart-bar',       'label'=>'Employee Performance'],
  ];
  foreach ($tabs as $key => $info): ?>
  <div class="main-tab <?php echo $active_tab==$key?'active':''; ?>" onclick="switchTab('<?php echo $key; ?>')">
    <i class="<?php echo $info['icon']; ?> mr-1"></i><?php echo $info['label']; ?>
  </div>
  <?php endforeach; ?>
</div>

<!-- ======================= TAB: TRAINING MATERIALS ======================= -->
<div id="tab-training" class="tab-content-panel" style="display:<?php echo $active_tab=='training'?'block':'none'; ?>">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h5 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-book-open mr-2 text-primary"></i>Training Materials</h5>
    <button class="btn-add" data-toggle="modal" data-target="#addTrainingHeadingModal"><i class="fas fa-plus mr-1"></i> Add Heading</button>
  </div>

  <?php if (empty($training_headings)): ?>
    <div class="card-box"><div class="empty-hint"><i class="fas fa-book fa-2x mb-2"></i><p>No training materials yet. Add a heading to start.</p></div></div>
  <?php else: foreach ($training_headings as $h): ?>
    <div class="heading-block">
      <div class="heading-block-head">
        <div>
          <h6><i class="fas fa-layer-group mr-2" style="color:var(--blue);"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6>
          <?php if (!empty($h['trainer_name'])): ?>
          <span style="font-size:11px;font-weight:700;color:#64748b;"><i class="fas fa-chalkboard-teacher mr-1" style="color:var(--blue);"></i><?php echo htmlspecialchars($h['trainer_name']); ?><?php if (!empty($h['trainer_designation'])): ?> &mdash; <?php echo htmlspecialchars($h['trainer_designation']); ?><?php endif; ?></span>
          <?php endif; ?>
        </div>
        <div class="d-flex gap-2" style="gap:6px;">
          <button class="btn btn-sm btn-info" onclick="openAddItemModal(<?php echo $h['id']; ?>, '<?php echo htmlspecialchars(addslashes($h['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
          <button class="btn btn-sm btn-secondary" onclick='openEditHeadingModal(<?php echo $h["id"]; ?>, <?php echo htmlspecialchars(json_encode($h["heading_name"]), ENT_QUOTES); ?>, <?php echo htmlspecialchars(json_encode($h["trainer_name"] ?? ""), ENT_QUOTES); ?>, <?php echo htmlspecialchars(json_encode($h["trainer_designation"] ?? ""), ENT_QUOTES); ?>, "training")'><i class="fas fa-edit"></i></button>
          <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this heading and all its items?')">
            <input type="hidden" name="action" value="delete_training_heading">
            <input type="hidden" name="id" value="<?php echo $h['id']; ?>">
            <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
            <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
            <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
          </form>
        </div>
      </div>
      <div class="heading-block-body">
        <?php if (empty($h['items'])): ?>
          <p class="text-muted small mb-0">No items yet. Click "+ Item" to add.</p>
        <?php else: foreach ($h['items'] as $item): ?>
          <div class="material-item">
            <div>
              <div class="item-title"><?php echo htmlspecialchars($item['item_title']); ?></div>
              <?php if (!empty($item['description'])): ?><div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div><?php endif; ?>
              <div style="margin-top:5px;">
                <?php if (!empty($item['document_path'])): ?>
                  <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="doc-pill"><i class="fas fa-file-alt"></i><?php echo htmlspecialchars($item['document_filename']); ?></a>
                <?php else: ?>
                  <span class="doc-pill none"><i class="fas fa-ban"></i> No attachment</span>
                <?php endif; ?>
              </div>
            </div>
            <div class="d-flex gap-2" style="gap:8px;">
              <button type="button" class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick='openEditItemModal(<?php echo htmlspecialchars(json_encode($item), ENT_QUOTES, "UTF-8"); ?>, "training")'><i class="fas fa-edit"></i> Edit</button>
              <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?')">
                <input type="hidden" name="action" value="delete_training_item">
                <input type="hidden" name="id" value="<?php echo $item['id']; ?>">
                <button type="submit" class="btn-sm-del"><i class="fas fa-trash"></i></button>
              </form>
            </div>
          </div>
        <?php endforeach; endif; ?>
      </div>
    </div>
  <?php endforeach; endif; ?>
</div>

<!-- ======================= TAB: TRAINING TEST ======================= -->
<div id="tab-training_test" class="tab-content-panel" style="display:<?php echo $active_tab=='training_test'?'block':'none'; ?>">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h5 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-question-circle mr-2 text-warning"></i>Training Test Questions</h5>
    <div class="d-flex gap-2" style="gap:8px;">
      <a href="?action=export_questions&type=training&dept_id=<?php echo $sel_dept; ?>&pos_id=<?php echo $sel_pos; ?>" class="btn btn-sm" style="background:#f1f5f9;border:1px solid #cbd5e1;color:#475569;font-weight:700;"><i class="fas fa-file-export mr-1"></i> Export</a>
      <button class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick="openImportModal('training')"><i class="fas fa-file-import mr-1"></i> Import</button>
      <button class="btn-add" onclick="openAddQuestionModal('training')"><i class="fas fa-plus mr-1"></i> Add Question</button>
    </div>
  </div>
  <?php if (empty($training_questions)): ?>
    <div class="card-box"><div class="empty-hint"><i class="fas fa-question fa-2x mb-2"></i><p>No training test questions yet.</p></div></div>
  <?php else: foreach ($training_questions as $idx => $q): ?>
    <div class="q-card">
      <div class="q-num">Question <?php echo $idx+1; ?></div>
      <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
      <div style="margin-bottom:8px;">
        <?php foreach ($q['options'] as $opt): ?>
          <div class="option-row <?php echo $opt['is_correct']?'correct':''; ?>">
            <span style="flex:1;font-size:12px;font-weight:600;color:#334155;"><?php echo htmlspecialchars($opt['label']); ?></span>
            <span class="option-badge pts"><i class="fas fa-star" style="color:#f59e0b;"></i> <?php echo $opt['points']; ?> pts</span>
            <?php if ($opt['is_correct']): ?><span class="option-badge correct"><i class="fas fa-check"></i> Correct</span><?php endif; ?>
          </div>
        <?php endforeach; ?>
      </div>
      <div class="d-flex gap-2" style="gap:8px;">
        <button type="button" class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick='openEditQuestionModal(<?php echo htmlspecialchars(json_encode($q), ENT_QUOTES, "UTF-8"); ?>, "training")'><i class="fas fa-edit mr-1"></i> Edit</button>
        <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this question?')">
          <input type="hidden" name="action" value="delete_question">
          <input type="hidden" name="id" value="<?php echo $q['id']; ?>">
          <button type="submit" class="btn-sm-del"><i class="fas fa-trash mr-1"></i> Delete</button>
        </form>
      </div>
    </div>
  <?php endforeach; endif; ?>
</div>

<!-- ======================= TAB: OJE CONTENT ======================= -->
<div id="tab-oje_content" class="tab-content-panel" style="display:<?php echo $active_tab=='oje_content'?'block':'none'; ?>">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h5 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-briefcase mr-2 text-info"></i>OJE Content Materials</h5>
    <button class="btn-add" data-toggle="modal" data-target="#addOjeHeadingModal"><i class="fas fa-plus mr-1"></i> Add Heading</button>
  </div>
  <?php if (empty($oje_headings)): ?>
    <div class="card-box"><div class="empty-hint"><i class="fas fa-briefcase fa-2x mb-2"></i><p>No OJE content yet. Add a heading to start.</p></div></div>
  <?php else: foreach ($oje_headings as $h): ?>
    <div class="heading-block">
      <div class="heading-block-head">
        <div>
          <h6><i class="fas fa-briefcase mr-2" style="color:#1e40af;"></i><?php echo htmlspecialchars($h['heading_name']); ?></h6>
          <?php if (!empty($h['trainer_name'])): ?>
          <span style="font-size:11px;font-weight:700;color:#64748b;"><i class="fas fa-chalkboard-teacher mr-1" style="color:#1e40af;"></i><?php echo htmlspecialchars($h['trainer_name']); ?><?php if (!empty($h['trainer_designation'])): ?> &mdash; <?php echo htmlspecialchars($h['trainer_designation']); ?><?php endif; ?></span>
          <?php endif; ?>
        </div>
        <div class="d-flex gap-2" style="gap:6px;">
          <button class="btn btn-sm btn-info" onclick="openAddOjeItemModal(<?php echo $h['id']; ?>, '<?php echo htmlspecialchars(addslashes($h['heading_name'])); ?>')"><i class="fas fa-plus"></i> Item</button>
          <button class="btn btn-sm btn-secondary" onclick='openEditHeadingModal(<?php echo $h["id"]; ?>, <?php echo htmlspecialchars(json_encode($h["heading_name"]), ENT_QUOTES); ?>, <?php echo htmlspecialchars(json_encode($h["trainer_name"] ?? ""), ENT_QUOTES); ?>, <?php echo htmlspecialchars(json_encode($h["trainer_designation"] ?? ""), ENT_QUOTES); ?>, "oje")'><i class="fas fa-edit"></i></button>
          <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this heading and all its items?')">
            <input type="hidden" name="action" value="delete_oje_heading">
            <input type="hidden" name="id" value="<?php echo $h['id']; ?>">
            <button type="submit" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
          </form>
        </div>
      </div>
      <div class="heading-block-body">
        <?php if (empty($h['items'])): ?>
          <p class="text-muted small mb-0">No items yet. Click "+ Item" to add.</p>
        <?php else: foreach ($h['items'] as $item): ?>
          <div class="material-item">
            <div>
              <div class="item-title"><?php echo htmlspecialchars($item['item_title']); ?></div>
              <?php if (!empty($item['description'])): ?><div class="item-desc"><?php echo htmlspecialchars($item['description']); ?></div><?php endif; ?>
              <div style="margin-top:5px;">
                <?php if (!empty($item['document_path'])): ?>
                  <a href="<?php echo htmlspecialchars($item['document_path']); ?>" target="_blank" class="doc-pill"><i class="fas fa-file-alt"></i><?php echo htmlspecialchars($item['document_filename']); ?></a>
                <?php else: ?>
                  <span class="doc-pill none"><i class="fas fa-ban"></i> No attachment</span>
                <?php endif; ?>
              </div>
            </div>
            <div class="d-flex gap-2" style="gap:8px;">
              <button type="button" class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick='openEditItemModal(<?php echo htmlspecialchars(json_encode($item), ENT_QUOTES, "UTF-8"); ?>, "oje")'><i class="fas fa-edit"></i> Edit</button>
              <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this item?')">
                <input type="hidden" name="action" value="delete_oje_item">
                <input type="hidden" name="id" value="<?php echo $item['id']; ?>">
                <button type="submit" class="btn-sm-del"><i class="fas fa-trash"></i></button>
              </form>
            </div>
          </div>
        <?php endforeach; endif; ?>
      </div>
    </div>
  <?php endforeach; endif; ?>
</div>

<!-- ======================= TAB: OJE TEST ======================= -->
<div id="tab-oje_test" class="tab-content-panel" style="display:<?php echo $active_tab=='oje_test'?'block':'none'; ?>">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h5 style="font-weight:800;color:var(--navy);margin:0;"><i class="fas fa-clipboard-check mr-2 text-success"></i>OJE Test Questions</h5>
    <div class="d-flex gap-2" style="gap:8px;">
      <a href="?action=export_questions&type=oje&dept_id=<?php echo $sel_dept; ?>&pos_id=<?php echo $sel_pos; ?>" class="btn btn-sm" style="background:#f1f5f9;border:1px solid #cbd5e1;color:#475569;font-weight:700;"><i class="fas fa-file-export mr-1"></i> Export</a>
      <button class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick="openImportModal('oje')"><i class="fas fa-file-import mr-1"></i> Import</button>
      <button class="btn-add" onclick="openAddQuestionModal('oje')"><i class="fas fa-plus mr-1"></i> Add Question</button>
    </div>
  </div>
  <?php if (empty($oje_questions)): ?>
    <div class="card-box"><div class="empty-hint"><i class="fas fa-clipboard fa-2x mb-2"></i><p>No OJE test questions yet.</p></div></div>
  <?php else: foreach ($oje_questions as $idx => $q): ?>
    <div class="q-card">
      <div class="q-num">Question <?php echo $idx+1; ?></div>
      <div class="q-text"><?php echo htmlspecialchars($q['question_text']); ?></div>
      <div style="margin-bottom:8px;">
        <?php foreach ($q['options'] as $opt): ?>
          <div class="option-row <?php echo $opt['is_correct']?'correct':''; ?>">
            <span style="flex:1;font-size:12px;font-weight:600;color:#334155;"><?php echo htmlspecialchars($opt['label']); ?></span>
            <span class="option-badge pts"><i class="fas fa-star" style="color:#f59e0b;"></i> <?php echo $opt['points']; ?> pts</span>
            <?php if ($opt['is_correct']): ?><span class="option-badge correct"><i class="fas fa-check"></i> Correct</span><?php endif; ?>
          </div>
        <?php endforeach; ?>
      </div>
      <div class="d-flex gap-2" style="gap:8px;">
        <button type="button" class="btn btn-sm" style="background:#e0e7ff;border:1px solid #c7d2fe;color:#3730a3;font-weight:700;" onclick='openEditQuestionModal(<?php echo htmlspecialchars(json_encode($q), ENT_QUOTES, "UTF-8"); ?>, "oje")'><i class="fas fa-edit mr-1"></i> Edit</button>
        <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this question?')">
          <input type="hidden" name="action" value="delete_question">
          <input type="hidden" name="id" value="<?php echo $q['id']; ?>">
          <button type="submit" class="btn-sm-del"><i class="fas fa-trash mr-1"></i> Delete</button>
        </form>
      </div>
    </div>
  <?php endforeach; endif; ?>
</div>

<!-- ======================= TAB: CONFIG ======================= -->
<div id="tab-config" class="tab-content-panel" style="display:<?php echo $active_tab=='config'?'block':'none'; ?>">
  <div class="card-box">
    <h5><i class="fas fa-cog mr-2"></i>Configuration for <?php echo htmlspecialchars($sel_dept_name); ?><?php echo $sel_pos > 0 ? ' â†’ '.htmlspecialchars($sel_pos_title) : ''; ?></h5>
    <form method="POST">
      <input type="hidden" name="action" value="save_config">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <div class="config-grid">
        <div class="form-field">
          <label><i class="fas fa-calendar-day mr-1"></i> Training Duration (Days)</label>
          <input type="number" name="training_days" min="1" value="<?php echo $config['training_days'] ?? 7; ?>" required>
        </div>
        <div class="form-field">
          <label><i class="fas fa-calendar-day mr-1"></i> OJE Duration (Days)</label>
          <input type="number" name="oje_days" min="1" value="<?php echo $config['oje_days'] ?? 7; ?>" required>
        </div>
        <div class="form-field">
          <label><i class="fas fa-percent mr-1"></i> Training Test Pass % (e.g. 95)</label>
          <input type="number" name="training_pass_percent" min="1" max="100" step="0.01" value="<?php echo $config['training_pass_percent'] ?? 95; ?>" required>
        </div>
        <div class="form-field">
          <label><i class="fas fa-percent mr-1"></i> OJE Test Pass % (e.g. 95)</label>
          <input type="number" name="oje_pass_percent" min="1" max="100" step="0.01" value="<?php echo $config['oje_pass_percent'] ?? 95; ?>" required>
        </div>
        <div class="form-field">
          <label><i class="fas fa-redo mr-1"></i> Max Test Attempts</label>
          <input type="number" name="max_attempts" min="1" max="10" value="<?php echo $config['max_attempts'] ?? 3; ?>" required>
        </div>
      </div>
      <button type="submit" class="btn-add"><i class="fas fa-save mr-1"></i> Save Configuration</button>
    </form>
  </div>
</div>

<!-- ======================= TAB: PERFORMANCE ======================= -->
<div id="tab-performance" class="tab-content-panel" style="display:<?php echo $active_tab=='performance'?'block':'none'; ?>">
  <?php if (!empty($employee_performance)): ?>
  <div class="card-box" id="perfFilterBar" style="margin-bottom:14px;">
    <h5 style="margin-bottom:14px;"><i class="fas fa-filter mr-2"></i>Filter Employees</h5>
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;">
      <div style="flex:1;min-width:180px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Employee Name</label>
        <input type="text" id="pf-name" placeholder="Search employee..." style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="flex:1;min-width:160px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Stage</label>
        <select id="pf-stage" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
          <option value="">All Stages</option>
          <option value="training">Training</option>
          <option value="training_test">Training Test</option>
          <option value="oje_reading">OJE Reading</option>
          <option value="oje_test">OJE Test</option>
          <option value="certified">Certified</option>
          <option value="failed">Failed</option>
        </select>
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date From</label>
        <input type="date" id="pf-from" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div style="min-width:150px;">
        <label style="font-weight:700;font-size:12px;color:var(--navy);display:block;margin-bottom:5px;">Start Date To</label>
        <input type="date" id="pf-to" style="width:100%;padding:8px 12px;border:2px solid #e0e7ff;border-radius:8px;font-size:13px;">
      </div>
      <div>
        <button type="button" class="btn-reset-filter" style="margin-top:0;" onclick="resetPFFilters()"><i class="fas fa-redo mr-1"></i> Reset</button>
      </div>
      <div style="display:flex;gap:8px;">
        <button type="button" class="btn btn-success btn-sm" onclick="window.tPF && window.tPF.button(0).trigger();"><i class="fas fa-file-excel mr-1"></i> Excel</button>
        <button type="button" class="btn btn-info btn-sm" onclick="window.tPF && window.tPF.button(1).trigger();"><i class="fas fa-file-csv mr-1"></i> CSV</button>
      </div>
    </div>
  </div>
  <?php endif; ?>
  <div class="card-box" style="padding:0;overflow:hidden;">
    <div style="padding:18px 24px;border-bottom:2px solid #f1f5f9;display:flex;justify-content:space-between;align-items:center;">
      <h5 style="margin:0;font-weight:800;color:var(--navy);"><i class="fas fa-chart-bar mr-2"></i>Employee Performance</h5>
      <span style="font-size:12px;color:#64748b;" id="perfLiveCount"><?php echo count($employee_performance); ?> employees found</span>
    </div>
    <?php if (empty($employee_performance)): ?>
      <div class="empty-hint"><i class="fas fa-users fa-2x mb-2"></i><p>No employee progress data found for this filter.</p></div>
    <?php else: ?>
    <div style="overflow-x:auto;">
      <table class="perf-table" id="mainPerfTable">
        <thead>
          <tr>
            <th>Employee</th>
            <th>Stage</th>
            <th>Training Started</th>
            <th>Training Test</th>
            <th>OJE Reading</th>
            <th>OJE Test</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($employee_performance as $ep): ?>
          <tr data-empname="<?php echo htmlspecialchars(strtolower($ep['emp_name'] ?? '')); ?>" data-stage="<?php echo htmlspecialchars($ep['stage'] ?? ''); ?>" data-startdate="<?php echo !empty($ep['training_started_at']) ? date('Y-m-d', strtotime($ep['training_started_at'])) : ''; ?>">
            <td>
              <div style="font-weight:700;color:var(--navy);"><?php echo htmlspecialchars($ep['emp_name'] ?? 'Unknown'); ?></div>
              <div style="font-size:11px;color:#64748b;"><?php echo htmlspecialchars($ep['department'] ?? ''); ?></div>
            </td>
            <td>
              <?php
              $isOverdue = false;
              if ($ep['stage'] == 'training' || $ep['stage'] == 'training_test') {
                  $c_days = $ep['config_training_days'] ?? 7;
                  $startDateStr = (!empty($ep['hire_date']) && $ep['hire_date'] !== '0000-00-00') ? $ep['hire_date'] : ($ep['training_started_at'] ?? '');
                  if ($startDateStr) {
                      $deadlineTs = strtotime($startDateStr) + ($c_days * 86400);
                      if (time() >= $deadlineTs) $isOverdue = true;
                  }
              } elseif ($ep['stage'] == 'oje_reading' || $ep['stage'] == 'oje_test') {
                  $o_days = $ep['config_oje_days'] ?? 7;
                  $ojeStartDateStr = (!empty($ep['oje_started_at']) && $ep['oje_started_at'] !== '0000-00-00') ? $ep['oje_started_at'] : '';
                  if ($ojeStartDateStr) {
                      $deadlineTs = strtotime($ojeStartDateStr) + ($o_days * 86400);
                      if (time() >= $deadlineTs) $isOverdue = true;
                  }
              }
              ?>
              <span class="stage-badge <?php echo $isOverdue ? 'failed' : $ep['stage']; ?>">
                <?php
                $stage_labels = ['training'=>'Training','training_test'=>'Training Test','oje_reading'=>'OJE Reading','oje_test'=>'OJE Test','certified'=>'Certified','failed'=>'Failed'];
                echo $isOverdue ? 'Overdue' : ($stage_labels[$ep['stage']] ?? $ep['stage']);
                ?>
              </span>
            </td>
            <td><?php echo $ep['training_started_at'] ? date('d M Y', strtotime($ep['training_started_at'])) : ' '; ?></td>
            <td>
              <?php if ($ep['training_attempts'] > 0): ?>
                <div style="font-weight:700;font-size:13px;color:<?php echo $ep['training_best_pct'] >= 95 ? '#065f46':'#991b1b'; ?>">
                  <?php echo number_format($ep['training_best_pct'], 1); ?>%
                </div>
                <div class="pct-bar"><div class="pct-bar-fill" style="width:<?php echo min(100,$ep['training_best_pct']); ?>%;background:<?php echo $ep['training_best_pct']>=95?'#10b981':'#ef4444'; ?>;"></div></div>
                <div style="font-size:11px;color:#64748b;"><?php echo $ep['training_attempts']; ?> attempt(s)</div>
              <?php else: echo '<span style="color:#94a3b8;font-size:12px;">Not taken</span>'; endif; ?>
            </td>
            <td><?php echo $ep['oje_started_at'] ? date('d M Y', strtotime($ep['oje_started_at'])) : ' '; ?></td>
            <td>
              <?php if ($ep['oje_attempts'] > 0): ?>
                <div style="font-weight:700;font-size:13px;color:<?php echo $ep['oje_best_pct'] >= 95 ? '#065f46':'#991b1b'; ?>">
                  <?php echo number_format($ep['oje_best_pct'], 1); ?>%
                </div>
                <div class="pct-bar"><div class="pct-bar-fill" style="width:<?php echo min(100,$ep['oje_best_pct']); ?>%;background:<?php echo $ep['oje_best_pct']>=95?'#10b981':'#ef4444'; ?>;"></div></div>
                <div style="font-size:11px;color:#64748b;"><?php echo $ep['oje_attempts']; ?> attempt(s)</div>
              <?php else: echo '<span style="color:#94a3b8;font-size:12px;">Not taken</span>'; endif; ?>
            </td>
            <td>
              <?php if ($ep['stage'] == 'certified'): ?>
                <span style="color:#065f46;font-weight:800;font-size:12px;"><i class="fas fa-certificate mr-1"></i> Certified</span>
              <?php elseif ($ep['stage'] == 'failed'): ?>
                <span style="color:#991b1b;font-weight:800;font-size:12px;"><i class="fas fa-times-circle mr-1"></i> Failed</span>
              <?php else: ?>
                <span style="color:#92400e;font-weight:700;font-size:12px;"><i class="fas fa-clock mr-1"></i> In Progress</span>
              <?php endif; ?>
            </td>
            <td>
              <div style="display:flex;gap:8px;">
                <button type="button" class="btn btn-sm btn-outline-primary" style="font-size:11px;font-weight:700;"
                  onclick="openUnifiedViewModal(<?php echo $ep['employee_id']; ?>, <?php echo $ep['department_id']; ?>, <?php echo $ep['position_id']; ?>, 'oje', 0, '<?php echo htmlspecialchars(addslashes($ep['emp_name'] ?? '')); ?>', '<?php echo htmlspecialchars(addslashes($sel_dept_name)); ?>', '<?php echo htmlspecialchars(addslashes($sel_pos_title)); ?>')">
                  <i class="fas fa-eye mr-1"></i> View
                </button>
                <button onclick="deleteEmployeeOJE(<?php echo $ep['employee_id']; ?>)" class="btn btn-sm" style="background:#fee2e2;color:#991b1b;font-size:11px;font-weight:700;border:none;cursor:pointer;"><i class="fas fa-trash"></i> Delete</button>
              </div>
            </td>
          </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <?php endif; ?>
  </div>
</div>

<?php endif; ?>
</div>
</div>
</div>

<!-- ======================= MODALS ======================= -->

<!-- Add Training Heading Modal -->
<div class="modal fade" id="addTrainingHeadingModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="add_training_heading">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-plus mr-2"></i>Add Training Heading</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Heading Name</label><input type="text" name="heading_name" required placeholder="e.g. Company Policies, Safety Training"></div>
        <div class="form-field"><label>Trainer Name</label><input type="text" name="trainer_name" placeholder="e.g. Ravi Kumar"></div>
        <div class="form-field"><label>Trainer Designation</label><input type="text" name="trainer_designation" placeholder="e.g. Senior HR Executive"></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save</button></div>
    </form>
  </div></div>
</div>

<!-- Add Training Item Modal -->
<div class="modal fade" id="addItemModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="add_training_item">
      <input type="hidden" name="heading_id" id="ai_heading_id">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <div class="modal-header"><h5 class="modal-title">Add Item to "<span id="ai_heading_label"></span>"</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Item Title</label><input type="text" name="item_title" required placeholder="e.g. About the Company"></div>
        <div class="form-field"><label>Description (optional)</label><textarea name="description" rows="2" placeholder="Short description..."></textarea></div>
        <div class="form-field"><label>Upload Document / Video (PDF, DOC, PPT, MP4, etc.)</label><input type="file" name="document_file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt,.mp4,.mov,.avi,.wmv,.webm"></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Item</button></div>
    </form>
  </div></div>
</div>

<!-- Edit Material Item Modal (For Training and OJE) -->
<div class="modal fade" id="editItemModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="edit_material_item">
      <input type="hidden" name="item_id" id="ei_item_id">
      <input type="hidden" name="item_type" id="ei_item_type">
      <div class="modal-header"><h5 class="modal-title">Edit Item</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Item Title</label><input type="text" name="item_title" id="ei_item_title" required></div>
        <div class="form-field"><label>Description (optional)</label><textarea name="description" id="ei_description" rows="2"></textarea></div>
        <div class="form-field">
            <label>Upload Replacement Document (optional)</label>
            <div id="ei_current_file" style="margin-bottom:10px; font-size:13px; font-weight:600; color:#0f2557;"></div>
            <input type="file" name="document_file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt,.mp4,.mov,.avi,.wmv,.webm">
            <small class="text-muted">Uploading a new file will overwrite the existing one.</small>
        </div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Update Item</button></div>
    </form>
  </div></div>
</div>

<!-- Add OJE Heading Modal -->
<div class="modal fade" id="addOjeHeadingModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="add_oje_heading">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-briefcase mr-2"></i>Add OJE Heading</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Heading Title</label><input type="text" name="heading_name" required placeholder="e.g. Roles & Responsibilities"></div>
        <div class="form-field"><label>Trainer Name</label><input type="text" name="trainer_name" placeholder="e.g. Ravi Kumar"></div>
        <div class="form-field"><label>Trainer Designation</label><input type="text" name="trainer_designation" placeholder="e.g. Senior HR Executive"></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Heading</button></div>
    </form>
  </div></div>
</div>

<!-- Add OJE Item Modal -->
<div class="modal fade" id="addOjeItemModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="add_oje_item">
      <input type="hidden" name="heading_id" id="aoi_heading_id">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <div class="modal-header"><h5 class="modal-title">Add Item to "<span id="aoi_heading_label"></span>"</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Item Title</label><input type="text" name="item_title" required placeholder="e.g. Daily Checklist"></div>
        <div class="form-field"><label>Description (optional)</label><textarea name="description" rows="2" placeholder="Short description..."></textarea></div>
        <div class="form-field"><label>Upload Document / Video (optional)</label><input type="file" name="document_file" accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt,.mp4,.mov,.avi,.wmv,.webm"></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Item</button></div>
    </form>
  </div></div>
</div>

<!-- Add Question Modal -->
<div class="modal fade" id="addQuestionModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="add_question">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="q_type" id="q_type_input">
      <div class="modal-header">
        <h5 class="modal-title" id="qModalTitle"><i class="fas fa-question-circle mr-2"></i>Add Question</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div class="form-field"><label>Question Text</label><textarea name="question_text" rows="3" required placeholder="Enter your question here..."></textarea></div>
        <label style="font-weight:700;font-size:12px;color:var(--navy);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;display:block;">Answer Options & Points</label>
        <div class="option-builder">
          <div class="option-builder-row option-builder-header">
            <span>Option Label</span><span>Points</span><span>Correct?</span><span></span>
          </div>
          <div id="optionsContainer">
            <?php
            $default_opts = [['Yes',10],['Partially',5],['No',0]];
            foreach ($default_opts as $i => $o): ?>
            <div class="option-builder-row" id="opt_row_<?php echo $i; ?>">
              <input type="text" name="options[]" value="<?php echo $o[0]; ?>" placeholder="Option label" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>
              <input type="number" name="points[]" value="<?php echo $o[1]; ?>" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">
              <input type="radio" name="correct_option" value="<?php echo $i; ?>" <?php echo $i==0?'checked':''; ?> style="width:18px;height:18px;">
              <button type="button" onclick="removeOption(<?php echo $i; ?>)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>
            </div>
            <?php endforeach; ?>
          </div>
        </div>
        <button type="button" onclick="addOption()" style="margin-top:10px;background:#f0f4f8;border:1.5px dashed #cbd5e1;border-radius:8px;padding:8px 16px;font-size:13px;font-weight:700;cursor:pointer;width:100%;color:#64748b;">+ Add Option</button>
        <div style="margin-top:12px;padding:10px 14px;background:#fef3c7;border:1px solid #fcd34d;border-radius:8px;font-size:12px;font-weight:600;color:#92400e;">
          <i class="fas fa-info-circle mr-1"></i> Default: Yes=10pts, Partially=5pts, No=0pts. Mark the correct answer using the radio button.
        </div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Question</button></div>
    </form>
  </div></div>
</div>

<!-- Edit Question Modal -->
<div class="modal fade" id="editQuestionModal" tabindex="-1">
  <div class="modal-dialog modal-lg"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" value="edit_question">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="q_type" id="edit_q_type_input">
      <input type="hidden" name="question_id" id="edit_question_id">
      <div class="modal-header">
        <h5 class="modal-title" id="editQModalTitle"><i class="fas fa-edit mr-2"></i>Edit Question</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <div class="form-field"><label>Question Text</label><textarea name="question_text" id="edit_question_text" rows="3" required placeholder="Enter your question here..."></textarea></div>
        <label style="font-weight:700;font-size:12px;color:var(--navy);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;display:block;">Answer Options & Points</label>
        <div class="option-builder">
          <div class="option-builder-row option-builder-header">
            <span>Option Label</span><span>Points</span><span>Correct?</span><span></span>
          </div>
          <div id="editOptionsContainer"></div>
        </div>
        <button type="button" onclick="addEditOption()" style="margin-top:10px;background:#f0f4f8;border:1.5px dashed #cbd5e1;border-radius:8px;padding:8px 16px;font-size:13px;font-weight:700;cursor:pointer;width:100%;color:#64748b;">+ Add Option</button>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Save Changes</button></div>
    </form>
  </div></div>
</div>

<!-- Import Questions Modal -->
<div class="modal fade" id="importQuestionsModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST" enctype="multipart/form-data">
      <input type="hidden" name="action" value="import_questions">
      <input type="hidden" name="department_id" value="<?php echo $sel_dept; ?>">
      <input type="hidden" name="position_id" value="<?php echo $sel_pos; ?>">
      <input type="hidden" name="q_type" id="import_q_type_input">
      <div class="modal-header">
        <h5 class="modal-title" id="importModalTitle"><i class="fas fa-file-import mr-2"></i>Import Questions</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body">
        <p class="text-muted" style="font-size:13px;">Upload a CSV file containing your test questions. <a href="?action=download_template" class="text-primary" style="font-weight:700;"><i class="fas fa-download mr-1"></i>Download Template</a></p>
        <div class="form-field">
          <label>Select CSV File</label>
          <input type="file" name="csv_file" accept=".csv" required style="border:1.5px dashed #cbd5e1;padding:12px;cursor:pointer;">
        </div>
        <div style="margin-top:12px;padding:10px 14px;background:#fef3c7;border:1px solid #fcd34d;border-radius:8px;font-size:12px;font-weight:600;color:#92400e;">
          <i class="fas fa-info-circle mr-1"></i> Note: The CSV must follow the exact format of the template. Maximum 6 options per question.
        </div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Import File</button></div>
    </form>
  </div></div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="js/ui-load.js"></script><script src="js/ui-jp.config.js"></script>
<script src="js/ui-jp.js"></script><script src="js/ui-nav.js"></script><script src="js/ui-toggle.js"></script>
<script>
function deleteEmployeeOJE(empId) {
  if (confirm("Are you sure you want to delete this employee? This will permanently remove their employee record, OJE progress, and test attempts.")) {
    var formData = new FormData();
    formData.append('ajax_delete_employee_oje', '1');
    formData.append('employee_id', empId);
    fetch('hr-OJE.php', {
      method: 'POST',
      body: formData
    })
    .then(r => r.json())
    .then(data => {
      if(data.success) {
        window.location.reload();
      } else {
        alert("Error deleting employee.");
      }
    }).catch(err => {
      console.error(err);
      alert("Error deleting employee.");
    });
  }
}

function switchTab(tab) {
  document.querySelectorAll('.tab-content-panel').forEach(function(p){ p.style.display='none'; });
  document.querySelectorAll('.main-tab').forEach(function(t){ t.classList.remove('active'); });
  document.getElementById('tab-'+tab).style.display = 'block';
  event.currentTarget.classList.add('active');
  // Update URL without reload
  var url = new URL(window.location.href);
  url.searchParams.set('tab', tab);
  window.history.replaceState({}, '', url);
  document.querySelector('input[name="tab"]').value = tab;
}

function openAddItemModal(headingId, headingName) {
  document.getElementById('ai_heading_id').value = headingId;
  document.getElementById('ai_heading_label').textContent = headingName;
  $('#addItemModal').modal('show');
}

var optCount = 3;
function addOption() {
  var i = optCount++;
  var html = '<div class="option-builder-row" id="opt_row_'+i+'">' +
    '<input type="text" name="options[]" placeholder="Option label" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>' +
    '<input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">' +
    '<input type="radio" name="correct_option" value="'+i+'" style="width:18px;height:18px;">' +
    '<button type="button" onclick="removeOption('+i+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>' +
    '</div>';
  document.getElementById('optionsContainer').insertAdjacentHTML('beforeend', html);
}

function openImportModal(type) {
  document.getElementById('import_q_type_input').value = type;
  document.getElementById('importModalTitle').innerHTML = '<i class="fas fa-file-import mr-2"></i>Import ' + (type=='oje'?'OJE':'Training') + ' Questions';
  $('#importQuestionsModal').modal('show');
}

function removeOption(i) {
  var row = document.getElementById('opt_row_'+i);
  if (row) row.remove();
}

function openAddQuestionModal(type) {
  document.getElementById('q_type_input').value = type;
  document.getElementById('qModalTitle').innerHTML = '<i class="fas fa-question-circle mr-2"></i>Add ' + (type=='oje'?'OJE':'Training') + ' Question';
  // Reset options to default
  document.getElementById('optionsContainer').innerHTML = `
    <div class="option-builder-row" id="opt_row_0">
      <input type="text" name="options[]" value="Yes" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>
      <input type="number" name="points[]" value="10" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">
      <input type="radio" name="correct_option" value="0" checked style="width:18px;height:18px;">
      <button type="button" onclick="removeOption(0)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>
    </div>
    <div class="option-builder-row" id="opt_row_1">
      <input type="text" name="options[]" value="Partially" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>
      <input type="number" name="points[]" value="5" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">
      <input type="radio" name="correct_option" value="1" style="width:18px;height:18px;">
      <button type="button" onclick="removeOption(1)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>
    </div>
    <div class="option-builder-row" id="opt_row_2">
      <input type="text" name="options[]" value="No" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>
      <input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">
      <input type="radio" name="correct_option" value="2" style="width:18px;height:18px;">
      <button type="button" onclick="removeOption(2)" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>
    </div>`;
  optCount = 3;
  $('#addQuestionModal').modal('show');
}

var editOptCount = 0;
function openEditQuestionModal(q, type) {
  document.getElementById('edit_q_type_input').value = type;
  document.getElementById('edit_question_id').value = q.id;
  document.getElementById('edit_question_text').value = q.question_text;
  document.getElementById('editQModalTitle').innerHTML = '<i class="fas fa-edit mr-2"></i>Edit ' + (type=='oje'?'OJE':'Training') + ' Question';
  
  var html = '';
  editOptCount = 0;
  if(q.options && q.options.length > 0) {
    q.options.forEach(function(opt, index) {
      var isChecked = opt.is_correct == 1 || opt.is_correct == '1' || opt.is_correct === true ? 'checked' : '';
      html += '<div class="option-builder-row" id="edit_opt_row_'+index+'">' +
        '<input type="text" name="options[]" value="'+opt.label.replace(/"/g, '&quot;')+'" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>' +
        '<input type="number" name="points[]" value="'+opt.points+'" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">' +
        '<input type="radio" name="correct_option" value="'+index+'" '+isChecked+' style="width:18px;height:18px;">' +
        '<button type="button" onclick="removeEditOption('+index+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>' +
        '</div>';
      editOptCount++;
    });
  }
  document.getElementById('editOptionsContainer').innerHTML = html;
  $('#editQuestionModal').modal('show');
}

function addEditOption() {
  var i = editOptCount++;
  var html = '<div class="option-builder-row" id="edit_opt_row_'+i+'">' +
    '<input type="text" name="options[]" placeholder="Option label" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;" required>' +
    '<input type="number" name="points[]" value="0" min="0" max="100" style="border:1.5px solid #e0e7ff;border-radius:6px;padding:6px 10px;font-size:13px;font-weight:600;width:70px;">' +
    '<input type="radio" name="correct_option" value="'+i+'" style="width:18px;height:18px;">' +
    '<button type="button" onclick="removeEditOption('+i+')" style="background:none;border:none;color:#ef4444;font-size:16px;cursor:pointer;padding:0;">Ã—</button>' +
    '</div>';
  document.getElementById('editOptionsContainer').insertAdjacentHTML('beforeend', html);
}

function removeEditOption(i) {
  var row = document.getElementById('edit_opt_row_'+i);
  if(row) row.parentNode.removeChild(row);
}

function openEditItemModal(item, type) {
  document.getElementById('ei_item_id').value = item.id;
  document.getElementById('ei_item_type').value = type;
  document.getElementById('ei_item_title').value = item.item_title;
  document.getElementById('ei_description').value = item.description || '';
  
  var fdiv = document.getElementById('ei_current_file');
  if (item.document_filename) {
      fdiv.innerHTML = '<i class="fas fa-file-alt mr-1 text-primary"></i> Current File: ' + item.document_filename;
  } else {
      fdiv.innerHTML = '<i class="fas fa-ban mr-1 text-muted"></i> No file currently attached.';
  }
  
  $('#editItemModal').modal('show');
}

function openEditHeadingModal(id, name, trainerName, trainerDesig, type) {
  document.getElementById('eh_id').value = id;
  document.getElementById('eh_name').value = name;
  document.getElementById('eh_trainer_name').value = trainerName;
  document.getElementById('eh_trainer_designation').value = trainerDesig;
  document.getElementById('eh_action').value = (type === 'oje') ? 'edit_oje_heading' : 'edit_training_heading';
  $('#editHeadingModal').modal('show');
}

function openAddOjeItemModal(headingId, headingLabel) {
  document.getElementById('aoi_heading_id').value = headingId;
  document.getElementById('aoi_heading_label').textContent = headingLabel;
  $('#addOjeItemModal').modal('show');
}
</script>
<!-- Edit Heading Modal (Training + OJE shared) -->
<div class="modal fade" id="editHeadingModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content">
    <form method="POST">
      <input type="hidden" name="action" id="eh_action" value="edit_training_heading">
      <input type="hidden" name="id" id="eh_id">
      <div class="modal-header"><h5 class="modal-title"><i class="fas fa-edit mr-2"></i>Edit Heading</h5><button type="button" class="close" data-dismiss="modal">&times;</button></div>
      <div class="modal-body">
        <div class="form-field"><label>Heading Name</label><input type="text" name="heading_name" id="eh_name" required></div>
        <div class="form-field"><label>Trainer Name</label><input type="text" name="trainer_name" id="eh_trainer_name" placeholder="e.g. Ravi Kumar"></div>
        <div class="form-field"><label>Trainer Designation</label><input type="text" name="trainer_designation" id="eh_trainer_designation" placeholder="e.g. Senior HR Executive"></div>
      </div>
      <div class="modal-footer"><button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button><button type="submit" class="btn btn-primary">Update Heading</button></div>
    </form>
  </div></div>
</div>
<!-- NEW CONFIG MODAL -->
<div class="modal fade" id="newConfigModal" tabindex="-1">
  <div class="modal-dialog"><div class="modal-content" style="border-radius:12px; border:none; box-shadow:0 10px 30px rgba(0,0,0,0.1);">
    <div class="modal-header" style="background:var(--navy); color:white; border-radius:12px 12px 0 0;">
      <h5 class="modal-title" style="font-weight:800;"><i class="fas fa-plus mr-2"></i>New Configuration</h5>
      <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
    </div>
    <div class="modal-body" style="padding:24px; min-height:350px;">
      <p style="font-size:14px; color:#64748b; margin-bottom:20px;">Select a department and position to start building their Training and OJE materials.</p>
      <div class="form-field">
        <label>Department</label>
        <select id="newConfigDept" onchange="fetchPositionsForNewConfig(this.value)">
          <option value="">-- Select Department --</option>
          <?php foreach($departments as $d): ?>
            <option value="<?php echo $d['id']; ?>"><?php echo htmlspecialchars($d['name']); ?></option>
          <?php endforeach; ?>
        </select>
      </div>
      <div class="form-field">
        <label>Position</label>
        <select id="newConfigPos">
          <option value="0">All Positions</option>
        </select>
      </div>
    </div>
    <div class="modal-footer" style="border-top:1px solid #e2e8f0;">
      <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
      <button type="button" class="btn btn-primary" onclick="createNewConfig()">Proceed <i class="fas fa-arrow-right ml-1"></i></button>
    </div>
  </div></div>
</div>

<script>
function fetchPositionsForNewConfig(dept_id) {
    var posSelect = document.getElementById('newConfigPos');
    posSelect.innerHTML = '<option value="0">All Positions</option>';
    if(!dept_id) return;
    $.get('hr-OJE.php', { get_positions: 1, dept_id: dept_id }, function(res) {
        try {
            var data = typeof res === 'string' ? JSON.parse(res) : res;
            data.forEach(function(p) {
                posSelect.innerHTML += '<option value="'+p.id+'">'+p.title+'</option>';
            });
        } catch(e) {}
    });
}
function createNewConfig() {
    var deptId = document.getElementById('newConfigDept').value;
    var posId = document.getElementById('newConfigPos').value;
    if(!deptId) { alert("Please select a department."); return; }
    window.location.href = 'hr-OJE.php?dept_id=' + deptId + '&pos_id=' + posId;
}
</script>

<!-- Unified Employee View Modal (Training/OJE/Cross Training/Recert all use this) -->
<div class="modal fade" id="unifiedViewModal" tabindex="-1" role="dialog" style="z-index:99999;">
  <div class="modal-dialog modal-xl" style="max-width:900px;">
    <div class="modal-content" style="border-radius:16px;border:none;box-shadow:0 20px 60px rgba(0,0,0,0.2);">
      <div class="modal-header" style="background:linear-gradient(135deg,#0f2557,#1a3fc4);border-radius:16px 16px 0 0;padding:20px 28px;">
        <div>
          <h5 class="modal-title" style="color:#fff;font-weight:800;margin:0;" id="unifiedModalTitle">Employee Progress</h5>
          <p id="unifiedModalSubtitle" style="color:rgba(255,255,255,0.65);font-size:12px;margin:4px 0 0;"></p>
        </div>
        <button type="button" class="close text-white" data-dismiss="modal">&times;</button>
      </div>
      <div class="modal-body" style="padding:28px;max-height:80vh;overflow-y:auto;" id="unifiedModalBody">
        <div class="text-center p-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i><p class="mt-2 text-muted">Loading...</p></div>
      </div>
    </div>
  </div>
</div>

<script>
function openUnifiedViewModal(empId, deptId, posId, context, cycle, empName, deptName, posName) {
  document.getElementById('unifiedModalTitle').innerText = empName + '   Progress';
  document.getElementById('unifiedModalSubtitle').innerText = deptName + (posName ? ' (' + posName + ')' : '');
  document.getElementById('unifiedModalBody').innerHTML = '<div class="text-center p-4"><i class="fas fa-spinner fa-spin fa-2x text-primary"></i><p class="mt-2 text-muted">Loading...</p></div>';
  $('#unifiedViewModal').modal('show');

  $.get('hr-ct-view-ajax.php', {
    emp_id: empId, dept_id: deptId, pos_id: posId, context: context, cycle: cycle || 0
  }, function(html) {
    document.getElementById('unifiedModalBody').innerHTML = html;
  }).fail(function() {
    document.getElementById('unifiedModalBody').innerHTML = '<div class="alert alert-danger">Failed load data.</div>';
  });
}
</script>

<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script>
function downloadCTCert(empId) {
  var el = document.getElementById('ctCertCard_' + empId);
  if (!el) {
      alert("Certificate element not found.");
      return;
  }
  var originalStyle = el.style.cssText;
  el.style.maxHeight = 'none';
  el.style.overflow = 'visible';
  html2canvas(el, { scale: 2, useCORS: true, logging: false }).then(function(canvas) {
    el.style.cssText = originalStyle;
    var link = document.createElement('a');
    link.download = 'Certificate_of_Completion.png';
    link.href = canvas.toDataURL('image/png');
    link.click();
  }).catch(function(err) {
      alert("Error generating certificate image.");
      el.style.cssText = originalStyle;
  });
}
</script>

<!-- DataTables Scripts -->
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap4.min.css"/>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/buttons/2.3.6/css/buttons.bootstrap4.min.css"/>
<script type="text/javascript" src="https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap4.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/dataTables.buttons.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/buttons.bootstrap4.min.js"></script>
<script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.1.3/jszip.min.js"></script>
<script type="text/javascript" src="https://cdn.datatables.net/buttons/2.3.6/js/buttons.html5.min.js"></script>
<script>
$(document).ready(function() {
    var dtConfig = {
        "pageLength": 25,
        "dom": "<'row'<'col-sm-12'tr>>" +
               "<'row mt-3'<'col-sm-12 col-md-5'i><'col-sm-12 col-md-7'p>>",
        "buttons": [
            { extend: 'excelHtml5', className: 'btn btn-success btn-sm', text: '<i class="fas fa-file-excel mr-1"></i> Excel', exportOptions: { modifier: { search: 'applied' } } },
            { extend: 'csvHtml5', className: 'btn btn-info btn-sm', text: '<i class="fas fa-file-csv mr-1"></i> CSV', exportOptions: { modifier: { search: 'applied' } } }
        ]
    };
    if ($('#allEmpOjeTable').length) {
        var conf1 = Object.assign({}, dtConfig, { "order": [[ 5, "asc" ]] });
        window.tAE = $('#allEmpOjeTable').DataTable(conf1);
    } else { window.tAE = null; }
    if ($('#mainPerfTable').length) {
        var conf2 = Object.assign({}, dtConfig, { "order": [[ 6, "asc" ]] });
        window.tPF = $('#mainPerfTable').DataTable(conf2);
    } else { window.tPF = null; }
    var tAE = window.tAE, tPF = window.tPF;

    function inRange(dateStr, from, to) {
        if (!dateStr) return !(from || to);
        var d = new Date(dateStr);
        if (from && d < new Date(from)) return false;
        if (to && d > new Date(to)) return false;
        return true;
    }

    // ---- All Employees (Training & OJE) table ----
    if (tAE) {
        $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
            if (settings.nTable.id !== 'allEmpOjeTable') return true;
            var $row = $(tAE.row(dataIndex).node());
            var name = $('#ae-name').val().toLowerCase();
            var dept = $('#ae-dept').val();
            var pos = $('#ae-pos').val();
            var stage = $('#ae-stage').val();
            var from = $('#ae-from').val();
            var to = $('#ae-to').val();
            if (name && ($row.data('empname') || '').indexOf(name) === -1) return false;
            if (dept && $row.data('dept') !== dept) return false;
            if (pos && $row.data('pos') !== pos) return false;
            if (stage && $row.data('stage') !== stage) return false;
            if (!inRange($row.data('startdate'), from, to)) return false;
            return true;
        });
        $('#ae-name, #ae-dept, #ae-pos, #ae-stage, #ae-from, #ae-to').on('keyup change', function() { tAE.draw(); });
        tAE.on('draw', function() {
            $('#allEmpLiveCount').text(tAE.rows({search:'applied'}).count() + ' employees found');
        });
    }
    window.resetAEFilters = function() {
        $('#ae-name').val(''); $('#ae-dept').val(''); $('#ae-pos').val(''); $('#ae-stage').val('');
        $('#ae-from').val(''); $('#ae-to').val('');
        if (tAE) tAE.draw();
    };

    // ---- Employee Performance table ----
    if (tPF) {
        $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
            if (settings.nTable.id !== 'mainPerfTable') return true;
            var $row = $(tPF.row(dataIndex).node());
            var name = $('#pf-name').val().toLowerCase();
            var stage = $('#pf-stage').val();
            var from = $('#pf-from').val();
            var to = $('#pf-to').val();
            if (name && ($row.data('empname') || '').indexOf(name) === -1) return false;
            if (stage && $row.data('stage') !== stage) return false;
            if (!inRange($row.data('startdate'), from, to)) return false;
            return true;
        });
        $('#pf-name, #pf-stage, #pf-from, #pf-to').on('keyup change', function() { tPF.draw(); });
        tPF.on('draw', function() {
            $('#perfLiveCount').text(tPF.rows({search:'applied'}).count() + ' employees found');
        });
    }
    window.resetPFFilters = function() {
        $('#pf-name').val(''); $('#pf-stage').val(''); $('#pf-from').val(''); $('#pf-to').val('');
        if (tPF) tPF.draw();
    };
});
</script>


<!-- Flutter State Preserver -->
<script>
document.addEventListener("DOMContentLoaded", function() {
    const urlEmail = "<?php echo !empty($currentUserEmail) ? '?user_email=' . urlencode($currentUserEmail) : ''; ?>";
    const urlEmailAmp = "<?php echo !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : ''; ?>";
    if (urlEmail) {
        document.querySelectorAll("a").forEach(a => {
            let href = a.getAttribute("href");
            if (href && href.includes(".php")) {
                if (href.includes("?")) {
                    a.setAttribute("href", href + urlEmailAmp);
                } else {
                    a.setAttribute("href", href + urlEmail);
                }
            }
        });
        document.querySelectorAll("form").forEach(f => {
            if (!f.querySelector('input[name="user_email"]')) {
                let input = document.createElement('input');
                input.type = 'hidden';
                input.name = 'user_email';
                input.value = "<?php echo htmlspecialchars($currentUserEmail, ENT_QUOTES); ?>";
                f.appendChild(input);
            }
        });
    }
});
</script>

</body>
</html>

