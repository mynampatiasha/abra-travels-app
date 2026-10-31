<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
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
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';
$con = conexion();

date_default_timezone_set(isset($_SESSION['ge_timezone']) && !empty($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');

// ============================================================
// AUTO CREATE hr_notices TABLE IF NOT EXISTS
// ============================================================
$con->query("CREATE TABLE IF NOT EXISTS `hr_notices` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `title` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
    `description` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;");

// ============================================================
// 1. AUTH - Email from URL (Flutter WebView) OR Session
// ============================================================
$currentUserEmail = isset($_GET['user_email']) ? trim($_GET['user_email']) :
                   (isset($_POST['user_email']) ? trim($_POST['user_email']) : '');
$currentUserName  = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$url_email        = !empty($currentUserEmail) ? '&user_email=' . urlencode($currentUserEmail) : '';

$successMsg = '';
$errorMsg   = '';

if (isset($_GET['msg'])) {
    if ($_GET['msg'] === 'deleted') $successMsg = 'Notice deleted successfully!';
    if ($_GET['msg'] === 'added')   $successMsg = 'Notice published successfully!';
    if ($_GET['msg'] === 'error')   $errorMsg   = 'Something went wrong. Please try again.';
}

// ============================================================
// 2. EMPLOYEE DATA LOOKUP
// ============================================================
$employee_id         = '';
$employee_name       = '';
$employee_department = '';
$employee_position   = '';
$employee_email      = '';

// PRIORITY 1: Email from URL (Flutter WebView)
if (!empty($currentUserEmail)) {
    $email_safe = mysqli_real_escape_string($con, $currentUserEmail);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position, email
                                FROM hr_employees
                                WHERE (email = '$email_safe' OR personal_email = '$email_safe')
                                AND status != 'Inactive'
                                LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id         = $row['employee_id'];
        $employee_name       = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position   = !empty($row['position'])   ? $row['position']   : 'General';
        $employee_email      = !empty($row['email'])      ? $row['email']      : $currentUserEmail;
        $_SESSION['user_name'] = $employee_name;
        $currentUserName = $employee_name;
    }
}

// FALLBACK: Session name lookup
if (empty($employee_id) && !empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($con, $currentUserName);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position, email
                                FROM hr_employees
                                WHERE LOWER(name) LIKE LOWER('%$name_safe%')
                                AND status != 'Inactive'
                                LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id         = $row['employee_id'];
        $employee_name       = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position   = !empty($row['position'])   ? $row['position']   : 'General';
        $employee_email      = !empty($row['email'])      ? $row['email']      : '';
    }
}

// ============================================================
// 3. ACCESS CHECK
// ============================================================
if (empty($employee_id)) {
    die("
    <div style='font-family:Poppins,sans-serif;text-align:center;padding:60px 20px;background:#f0f4f8;min-height:100vh;display:flex;align-items:center;justify-content:center;'>
        <div style='max-width:400px;background:#fff;border-radius:16px;padding:40px;box-shadow:0 4px 20px rgba(0,0,0,0.1);'>
            <div style='font-size:56px;margin-bottom:20px;'>&#128274;</div>
            <h2 style='color:#1e293b;margin-bottom:12px;font-weight:700;font-size:20px;'>Authentication Failed</h2>
            <p style='color:#64748b;margin-bottom:8px;font-size:14px;'>Email received: <strong>" . htmlspecialchars($currentUserEmail ?: '(none)') . "</strong></p>
            <p style='color:#94a3b8;font-size:13px;margin-top:16px;'>Please access this page through the Abra Fleet app.</p>
        </div>
    </div>");
}

// ============================================================
// 4. PERMISSION LEVELS
// ============================================================
$is_management_dept   = (stripos($employee_department, 'Management') !== false);
$is_hr_dept           = (stripos($employee_department, 'Human Resources') !== false ||
                          stripos($employee_department, 'Human Resources Department') !== false ||
                          strtolower(trim($employee_department)) === 'hr');
$is_managing_director = (stripos($employee_position, 'managing director') !== false ||
                          stripos($employee_position, 'md') !== false ||
                          stripos($employee_position, 'ceo') !== false);
$is_abishek           = (stripos($employee_name, 'abishek') !== false || stripos($employee_name, 'abhishek') !== false ||
                          stripos($currentUserName, 'abishek') !== false || stripos($currentUserName, 'abhishek') !== false);
$is_keerti            = (stripos($employee_name, 'keerti') !== false || stripos($employee_name, 'keerthi') !== false ||
                          stripos($currentUserName, 'keerti') !== false || stripos($currentUserName, 'keerthi') !== false);

$isAdmin = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_abishek || $is_keerti);

// ============================================================
// 7. BACK BUTTON URL
// ============================================================
$backUrl = 'https://crm.abra-logistic.com/dashboard/raise-a-ticket.php';
if ($is_abishek || $is_managing_director) {
    $backUrl = './';
}

// ============================================================
// 5. INLINE ADD NOTICE (POST — no separate file needed)
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add_notice') {
    $title       = trim($_POST['title'] ?? '');
    $description = trim($_POST['description'] ?? '');
    if (!empty($title) && !empty($description)) {
        $title_safe = $con->real_escape_string($title);
        $desc_safe  = $con->real_escape_string($description);
        $insert = $con->query("INSERT INTO hr_notices (title, description) VALUES ('$title_safe', '$desc_safe')");
        $successMsg = $insert ? 'Notice published successfully!' : 'Failed to publish notice. Please try again.';
        if (!$insert) $errorMsg = 'Failed to publish notice. Please try again.';
    } else {
        $errorMsg = 'Title and description are required.';
    }
}

// ============================================================
// 6. INLINE DELETE — handled by delete_notice.php
// ============================================================

// ============================================================
// 7. EXPORT FUNCTIONALITY
// ============================================================
if (isset($_GET['action']) && $_GET['action'] == 'export') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=notices_export_' . date('Y-m-d') . '.csv');
    $output = fopen('php://output', 'w');
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    fputcsv($output, array('Notice ID', 'Title', 'Description', 'Created Date', 'Created Time'));
    $export_result = $con->query("SELECT * FROM hr_notices ORDER BY id DESC");
    while ($erow = $export_result->fetch_assoc()) {
        fputcsv($output, array(
            $erow['id'],
            $erow['title'],
            $erow['description'],
            date('Y-m-d', strtotime($erow['created_at'])),
            date('H:i:s', strtotime($erow['created_at']))
        ));
    }
    fclose($output);
    exit;
}

// ============================================================
// 9. PAGINATION & SEARCH
// ============================================================
$notices_per_page = 12;
$page             = isset($_GET['page'])   ? max(1, (int)$_GET['page']) : 1;
$offset           = ($page - 1) * $notices_per_page;
$search_query     = isset($_GET['search']) ? trim($_GET['search']) : '';
$view_mode        = isset($_GET['view'])   ? $_GET['view'] : 'grid';

// ============================================================
// 10. DATABASE QUERIES
// ============================================================
$where_clause = "";
if (!empty($search_query)) {
    $search_escaped = $con->real_escape_string($search_query);
    $where_clause   = "WHERE title LIKE '%$search_escaped%' OR description LIKE '%$search_escaped%'";
}
$count_result  = $con->query("SELECT COUNT(*) as total FROM hr_notices $where_clause");
$total_notices = $count_result ? $count_result->fetch_assoc()['total'] : 0;
$total_pages   = ceil($total_notices / $notices_per_page);
$resultado     = $con->query("SELECT * FROM hr_notices $where_clause ORDER BY id DESC LIMIT $notices_per_page OFFSET $offset");
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <title>Notice Board | Abra HRM</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <!-- Font Awesome via CDN — fixes missing icons -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css" />
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        html, body {
            height: 100%;
            font-family: 'Poppins', sans-serif;
            background: #f0f4f8;
            color: #334155;
            overflow-x: hidden;
        }

        /* ═══ TOPBAR ═══ */
        .topbar {
            background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
            height: 64px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0 24px;
            box-shadow: 0 2px 12px rgba(30,58,138,0.35);
            position: sticky;
            top: 0;
            z-index: 999;
        }
        .topbar-left { display: flex; align-items: center; gap: 12px; }
        .topbar-icon {
            width: 38px; height: 38px;
            background: rgba(255,255,255,0.15);
            border-radius: 10px;
            display: flex; align-items: center; justify-content: center;
            font-size: 17px; color: white;
        }
        .topbar-title { font-size: 17px; font-weight: 700; color: white; letter-spacing: 0.3px; }
        .badge-admin {
            background: #10b981; color: white;
            font-size: 10px; font-weight: 700;
            padding: 3px 10px; border-radius: 20px;
            text-transform: uppercase; letter-spacing: 0.8px;
        }
        .badge-readonly {
            background: rgba(255,255,255,0.18); color: white;
            font-size: 10px; font-weight: 600;
            padding: 3px 10px; border-radius: 20px;
            border: 1px solid rgba(255,255,255,0.3);
        }
        .btn-back {
            display: inline-flex; align-items: center; gap: 6px;
            background: rgba(255,255,255,0.15); color: white;
            border: 1px solid rgba(255,255,255,0.25);
            padding: 8px 16px; border-radius: 8px;
            font-size: 13px; font-weight: 600; text-decoration: none;
            transition: background 0.2s; font-family: 'Poppins', sans-serif;
        }
        .btn-back:hover { background: rgba(255,255,255,0.28); color: white; text-decoration: none; }

        /* ═══ ALERT ═══ */
        .alert-bar {
            padding: 14px 24px; font-size: 14px; font-weight: 600;
            display: flex; align-items: center; gap: 10px;
        }
        .alert-success { background: #d1fae5; color: #065f46; border-bottom: 2px solid #6ee7b7; }
        .alert-danger  { background: #fee2e2; color: #991b1b; border-bottom: 2px solid #fca5a5; }

        /* ═══ PAGE WRAPPER ═══ */
        .page-wrapper { max-width: 1400px; margin: 0 auto; padding: 28px 20px 60px; }

        /* ═══ CONTROL BAR ═══ */
        .control-bar {
            background: white; border-radius: 14px; padding: 18px 22px;
            margin-bottom: 24px; box-shadow: 0 2px 10px rgba(0,0,0,0.07);
            border: 1.5px solid #e2e8f0;
            display: flex; flex-wrap: wrap; gap: 16px;
            align-items: center; justify-content: space-between;
        }
        .stat-block { display: flex; align-items: center; gap: 14px; }
        .stat-icon {
            width: 50px; height: 50px;
            background: linear-gradient(135deg, #1e3a8a, #1e40af);
            border-radius: 12px; display: flex; align-items: center; justify-content: center;
            color: white; font-size: 20px;
            box-shadow: 0 4px 12px rgba(30,58,138,0.28); flex-shrink: 0;
        }
        .stat-text .num { font-size: 26px; font-weight: 800; color: #1e293b; line-height: 1; }
        .stat-text .lbl { font-size: 12px; color: #64748b; font-weight: 500; margin-top: 2px; }

        /* Search */
        .search-form { display: flex; gap: 8px; flex: 1; max-width: 460px; min-width: 200px; }
        .search-input {
            flex: 1; border: 2px solid #e2e8f0; border-radius: 10px;
            padding: 10px 15px; font-size: 13px; font-family: 'Poppins', sans-serif;
            color: #1e293b; outline: none; transition: border-color 0.2s; background: #f8fafc;
        }
        .search-input:focus { border-color: #1e40af; background: white; }

        /* Buttons */
        .btn-navy {
            background: linear-gradient(135deg, #1e3a8a, #1e40af);
            color: white; border: none; padding: 10px 18px; border-radius: 10px;
            font-size: 13px; font-weight: 600; font-family: 'Poppins', sans-serif;
            cursor: pointer; display: inline-flex; align-items: center; gap: 7px;
            text-decoration: none; box-shadow: 0 3px 10px rgba(30,58,138,0.25);
            transition: all 0.2s; white-space: nowrap;
        }
        .btn-navy:hover { transform: translateY(-2px); box-shadow: 0 6px 18px rgba(30,58,138,0.35); color: white; text-decoration: none; }

        .btn-amber {
            background: linear-gradient(135deg, #f59e0b, #d97706);
            color: white; border: none; padding: 10px 18px; border-radius: 10px;
            font-size: 13px; font-weight: 600; font-family: 'Poppins', sans-serif;
            cursor: pointer; display: inline-flex; align-items: center; gap: 7px;
            text-decoration: none; box-shadow: 0 3px 10px rgba(245,158,11,0.28);
            transition: all 0.2s; white-space: nowrap;
        }
        .btn-amber:hover { transform: translateY(-2px); box-shadow: 0 6px 18px rgba(245,158,11,0.38); color: white; text-decoration: none; }

        .btn-clear {
            background: #f1f5f9; color: #64748b; border: 1.5px solid #e2e8f0;
            padding: 10px 14px; border-radius: 10px; font-size: 13px;
            font-family: 'Poppins', sans-serif; cursor: pointer;
            display: inline-flex; align-items: center; text-decoration: none; transition: all 0.2s;
        }
        .btn-clear:hover { background: #e2e8f0; color: #334155; text-decoration: none; }

        .ctrl-right { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }

        /* View Toggle */
        .view-toggle { display: flex; background: #f1f5f9; border-radius: 10px; padding: 4px; gap: 3px; }
        .view-btn {
            width: 38px; height: 38px; border: none; background: transparent;
            border-radius: 8px; color: #94a3b8; cursor: pointer;
            display: flex; align-items: center; justify-content: center;
            font-size: 15px; text-decoration: none; transition: all 0.2s;
        }
        .view-btn:hover { color: #1e40af; }
        .view-btn.active { background: white; color: #1e3a8a; box-shadow: 0 2px 6px rgba(30,58,138,0.15); }

        /* ═══ GRID ═══ */
        .notice-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 20px;
        }
        @media (min-width: 700px)  { .notice-grid { grid-template-columns: repeat(2, 1fr); } }
        @media (min-width: 1024px) { .notice-grid { grid-template-columns: repeat(3, 1fr); } }
        @media (min-width: 1300px) { .notice-grid { grid-template-columns: repeat(4, 1fr); } }

        /* ═══ LIST ═══ */
        .notice-list { display: flex; flex-direction: column; gap: 14px; }

        /* ═══ NOTICE CARD ═══ */
        .notice-card {
            background: white; border-radius: 14px;
            border: 1.5px solid #e2e8f0; border-left: 5px solid #1e3a8a;
            padding: 22px; display: flex; flex-direction: column;
            min-height: 210px; position: relative; overflow: hidden;
            transition: all 0.25s ease; box-shadow: 0 2px 8px rgba(0,0,0,0.05);
        }
        .notice-card::after {
            content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
            background: linear-gradient(90deg, #1e3a8a, #3b82f6, #10b981);
        }
        .notice-card:hover { transform: translateY(-5px); box-shadow: 0 10px 24px rgba(30,58,138,0.14); border-color: #93c5fd; }

        /* List overrides */
        .notice-list .notice-card {
            min-height: auto; flex-direction: row; align-items: center; gap: 18px; padding: 18px 22px;
        }
        .notice-list .notice-card::after { display: none; }
        .notice-list .notice-card:hover { transform: translateX(4px); }

        .card-body { flex: 1; min-width: 0; }

        .card-meta { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
        .notice-list .card-meta { margin-bottom: 6px; }

        .notice-id {
            background: #eff6ff; color: #1e40af; font-size: 11px; font-weight: 700;
            padding: 3px 10px; border-radius: 6px; border: 1px solid #bfdbfe;
        }
        .notice-date {
            font-size: 11px; color: #94a3b8;
            display: flex; align-items: center; gap: 5px; font-weight: 500;
        }
        .notice-title {
            font-size: 15px; font-weight: 700; color: #1e293b; line-height: 1.5;
            margin-bottom: 10px; display: -webkit-box;
            -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
        }
        .notice-list .notice-title { font-size: 16px; margin-bottom: 5px; -webkit-line-clamp: 1; }
        .notice-desc {
            font-size: 13px; color: #64748b; line-height: 1.7; flex: 1;
            display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical;
            overflow: hidden; margin-bottom: 16px;
        }
        .notice-list .notice-desc { margin-bottom: 0; -webkit-line-clamp: 2; }

        .card-footer-actions {
            display: flex; justify-content: space-between; align-items: center;
            padding-top: 14px; border-top: 1px solid #f1f5f9; margin-top: auto;
        }
        .notice-list .card-footer-actions {
            padding-top: 0; border-top: none; margin-top: 0;
            flex-direction: column; gap: 8px; min-width: 110px;
        }

        .btn-read-more {
            background: none; border: none; color: #1e40af;
            font-size: 13px; font-weight: 700; font-family: 'Poppins', sans-serif;
            cursor: pointer; display: inline-flex; align-items: center; gap: 6px;
            padding: 0; transition: gap 0.2s, color 0.2s;
        }
        .btn-read-more:hover { color: #1e3a8a; gap: 10px; }
        .notice-list .btn-read-more {
            background: linear-gradient(135deg, #1e3a8a, #1e40af);
            color: white; padding: 8px 14px; border-radius: 8px;
            width: 100%; justify-content: center; box-shadow: 0 3px 8px rgba(30,58,138,0.2);
        }
        .notice-list .btn-read-more:hover { color: white; box-shadow: 0 5px 14px rgba(30,58,138,0.3); }

        .btn-del {
            width: 34px; height: 34px; border-radius: 8px;
            background: #fee2e2; color: #ef4444; border: none;
            cursor: pointer; display: inline-flex; align-items: center; justify-content: center;
            font-size: 14px; transition: all 0.2s; flex-shrink: 0;
        }
        .btn-del:hover { background: #ef4444; color: white; transform: scale(1.08); }
        .notice-list .btn-del { width: 100%; border-radius: 8px; height: 36px; }

        /* ═══ EMPTY STATE ═══ */
        .empty-box {
            background: white; border-radius: 16px; border: 1.5px dashed #cbd5e1;
            padding: 80px 30px; text-align: center;
        }
        .empty-box .empty-icon {
            width: 80px; height: 80px; background: #f0f4f8; border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            margin: 0 auto 20px; font-size: 34px; color: #94a3b8;
        }
        .empty-box h3 { font-size: 18px; font-weight: 700; color: #334155; margin-bottom: 8px; }
        .empty-box p  { font-size: 13px; color: #94a3b8; margin-bottom: 24px; }

        /* ═══ PAGINATION ═══ */
        .pagination-wrap { display: flex; justify-content: center; gap: 6px; margin-top: 36px; flex-wrap: wrap; }
        .pg-btn {
            min-width: 40px; height: 40px; background: white; border: 1.5px solid #e2e8f0;
            border-radius: 10px; color: #475569; font-size: 13px; font-weight: 700;
            font-family: 'Poppins', sans-serif; display: flex; align-items: center;
            justify-content: center; padding: 0 12px; text-decoration: none; transition: all 0.2s;
        }
        .pg-btn:hover:not(.pg-active) { border-color: #1e40af; color: #1e40af; text-decoration: none; transform: translateY(-2px); }
        .pg-btn.pg-active { background: linear-gradient(135deg, #1e3a8a, #1e40af); color: white; border-color: #1e3a8a; box-shadow: 0 3px 10px rgba(30,58,138,0.28); }

        /* ═══ MODAL ═══ */
        .modal-overlay {
            display: none; position: fixed; inset: 0;
            background: rgba(15,23,42,0.55); z-index: 9999;
            align-items: center; justify-content: center; padding: 20px;
        }
        .modal-overlay.show { display: flex; }
        .modal-box {
            background: white; border-radius: 16px; width: 100%; max-width: 640px;
            max-height: 90vh; overflow-y: auto;
            box-shadow: 0 20px 60px rgba(0,0,0,0.25);
            animation: modalIn 0.25s ease;
        }
        @keyframes modalIn {
            from { opacity: 0; transform: scale(0.95) translateY(-10px); }
            to   { opacity: 1; transform: scale(1) translateY(0); }
        }
        .modal-head {
            background: linear-gradient(135deg, #1e3a8a, #1e40af);
            color: white; padding: 18px 24px; border-radius: 16px 16px 0 0;
            display: flex; align-items: center; justify-content: space-between;
        }
        .modal-head h5 { font-size: 16px; font-weight: 700; margin: 0; display: flex; align-items: center; gap: 8px; }
        .modal-close {
            background: rgba(255,255,255,0.2); border: none; color: white;
            width: 32px; height: 32px; border-radius: 8px; font-size: 18px; cursor: pointer;
            display: flex; align-items: center; justify-content: center;
            transition: background 0.2s; font-family: 'Poppins', sans-serif;
        }
        .modal-close:hover { background: rgba(255,255,255,0.35); }
        .modal-body { padding: 28px 24px; }
        .modal-footer { padding: 16px 24px; border-top: 1px solid #f1f5f9; display: flex; justify-content: flex-end; gap: 10px; }

        .form-group { margin-bottom: 20px; }
        .form-label { display: block; font-size: 12px; font-weight: 700; color: #475569; text-transform: uppercase; letter-spacing: 0.6px; margin-bottom: 8px; }
        .form-label .req { color: #ef4444; margin-left: 3px; }
        .form-control {
            width: 100%; border: 2px solid #e2e8f0; border-radius: 10px;
            padding: 12px 15px; font-size: 14px; font-family: 'Poppins', sans-serif;
            color: #1e293b; outline: none; transition: border-color 0.2s; background: #f8fafc;
        }
        .form-control:focus { border-color: #1e40af; background: white; box-shadow: 0 0 0 4px rgba(30,64,175,0.08); }
        textarea.form-control { resize: vertical; min-height: 160px; line-height: 1.6; }
        .btn-cancel {
            background: #f1f5f9; color: #475569; border: 1.5px solid #e2e8f0;
            padding: 10px 20px; border-radius: 10px; font-size: 13px; font-weight: 600;
            font-family: 'Poppins', sans-serif; cursor: pointer; transition: all 0.2s;
        }
        .btn-cancel:hover { background: #e2e8f0; }
        .notice-full-text { font-size: 14px; color: #334155; line-height: 1.85; white-space: pre-wrap; }

        /* ═══ RESPONSIVE ═══ */
        @media (max-width: 768px) {
            .topbar { padding: 0 16px; }
            .topbar-title { font-size: 15px; }
            .page-wrapper { padding: 18px 14px 50px; }
            .control-bar { gap: 12px; }
            .search-form { max-width: 100%; }
            .ctrl-right { width: 100%; justify-content: space-between; }
            .notice-list .notice-card { flex-direction: column; }
            .notice-list .card-footer-actions { flex-direction: row; min-width: auto; width: 100%; }
        }
    </style>
</head>
<body>

<!-- TOP BAR -->
<nav class="topbar">
    <div class="topbar-left">
        <div class="topbar-icon"><i class="fa-solid fa-bullhorn"></i></div>
        <span class="topbar-title">Notice Board</span>
        <?php if ($isAdmin): ?>
            <span class="badge-admin">&#10003; Admin</span>
        <?php else: ?>
            <span class="badge-readonly">&#128065; View Only</span>
        <?php endif; ?>
    </div>
    <!--<a href="<?php echo $backUrl; ?>" class="btn-back">-->
    <!--    <i class="fa-solid fa-arrow-left"></i> Back-->
    <!--</a>-->
</nav>

<!-- ALERT -->
<?php if ($successMsg): ?>
    <div class="alert-bar alert-success">
        <i class="fa-solid fa-circle-check"></i> <?php echo htmlspecialchars($successMsg); ?>
    </div>
<?php elseif ($errorMsg): ?>
    <div class="alert-bar alert-danger">
        <i class="fa-solid fa-circle-exclamation"></i> <?php echo htmlspecialchars($errorMsg); ?>
    </div>
<?php endif; ?>

<!-- PAGE CONTENT -->
<div class="page-wrapper">

    <!-- Control Bar -->
    <div class="control-bar">

        <!-- Stats -->
        <div class="stat-block">
            <div class="stat-icon"><i class="fa-regular fa-file-lines"></i></div>
            <div class="stat-text">
                <div class="num"><?php echo $total_notices; ?></div>
                <div class="lbl"><?php echo $total_notices == 1 ? 'Active Notice' : 'Active Notices'; ?></div>
            </div>
        </div>

        <!-- Search -->
        <form class="search-form" method="GET" action="">
            <input type="hidden" name="view" value="<?php echo htmlspecialchars($view_mode); ?>">
            <?php if (!empty($currentUserEmail)): ?>
                <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail); ?>">
            <?php endif; ?>
            <input type="text" name="search" class="search-input"
                   placeholder="Search notices..."
                   value="<?php echo htmlspecialchars($search_query); ?>">
            <button type="submit" class="btn-navy" title="Search">
                <i class="fa-solid fa-magnifying-glass"></i>
            </button>
            <?php if (!empty($search_query)): ?>
                <a href="?view=<?php echo $view_mode; echo $url_email; ?>" class="btn-clear" title="Clear">
                    <i class="fa-solid fa-xmark"></i>
                </a>
            <?php endif; ?>
        </form>

        <!-- Right controls -->
        <div class="ctrl-right">
            <div class="view-toggle">
                <a href="?view=grid<?php echo !empty($search_query) ? '&search='.urlencode($search_query) : ''; echo $url_email; ?>"
                   class="view-btn <?php echo $view_mode == 'grid' ? 'active' : ''; ?>" title="Grid View">
                    <i class="fa-solid fa-table-cells-large"></i>
                </a>
                <a href="?view=list<?php echo !empty($search_query) ? '&search='.urlencode($search_query) : ''; echo $url_email; ?>"
                   class="view-btn <?php echo $view_mode == 'list' ? 'active' : ''; ?>" title="List View">
                    <i class="fa-solid fa-list"></i>
                </a>
            </div>

            <?php if ($total_notices > 0): ?>
                <a href="?action=export<?php echo $url_email; ?>" class="btn-amber">
                    <i class="fa-solid fa-download"></i> Export
                </a>
            <?php endif; ?>

            <?php if ($isAdmin): ?>
                <button class="btn-navy" onclick="openModal('addModal')">
                    <i class="fa-solid fa-plus"></i> Add Notice
                </button>
            <?php endif; ?>
        </div>
    </div>

    <!-- NOTICES -->
    <?php if ($total_notices > 0): ?>
        <div class="<?php echo $view_mode === 'list' ? 'notice-list' : 'notice-grid'; ?>">
            <?php while ($row = $resultado->fetch_assoc()):
                $fullDesc  = $row['description'];
                $shortDesc = strlen($fullDesc) > 130 ? substr($fullDesc, 0, 130) . '…' : $fullDesc;
                $hasMore   = strlen($fullDesc) > 130;
                $jsTitle   = addslashes(htmlspecialchars($row['title']));
                $jsDesc    = addslashes(htmlspecialchars($fullDesc));
            ?>
            <div class="notice-card">
                <div class="card-body">
                    <div class="card-meta">
                        <span class="notice-id">#<?php echo $row['id']; ?></span>
                        <span class="notice-date">
                            <i class="fa-regular fa-calendar"></i>
                            <?php echo date('d M Y', strtotime($row['created_at'])); ?>
                        </span>
                    </div>
                    <div class="notice-title"><?php echo htmlspecialchars($row['title']); ?></div>
                    <div class="notice-desc"><?php echo nl2br(htmlspecialchars($shortDesc)); ?></div>
                </div>
                <div class="card-footer-actions">
                    <?php if ($hasMore): ?>
                        <button class="btn-read-more"
                                onclick="openReadMore('<?php echo $jsTitle; ?>', '<?php echo $jsDesc; ?>')">
                            Read More <i class="fa-solid fa-arrow-right"></i>
                        </button>
                    <?php else: ?>
                        <span></span>
                    <?php endif; ?>

                    <?php if ($isAdmin): ?>
                        <button class="btn-del"
                                onclick="confirmDeleteOpen(<?php echo (int)$row['id']; ?>)"
                                title="Delete Notice">
                            <i class="fa-solid fa-trash"></i>
                        </button>
                    <?php endif; ?>
                </div>
            </div>
            <?php endwhile; ?>
        </div>

        <!-- Pagination -->
        <?php if ($total_pages > 1):
            $sParam = !empty($search_query) ? '&search=' . urlencode($search_query) : '';
            $vParam = '&view=' . $view_mode;
            $eParam = $url_email;
        ?>
        <div class="pagination-wrap">
            <?php if ($page > 1): ?>
                <a href="?page=<?php echo ($page-1).$sParam.$vParam.$eParam; ?>" class="pg-btn">
                    <i class="fa-solid fa-chevron-left"></i>
                </a>
            <?php endif; ?>
            <?php for ($i = max(1, $page-2); $i <= min($total_pages, $page+2); $i++): ?>
                <a href="?page=<?php echo $i.$sParam.$vParam.$eParam; ?>"
                   class="pg-btn <?php echo $i == $page ? 'pg-active' : ''; ?>"><?php echo $i; ?></a>
            <?php endfor; ?>
            <?php if ($page < $total_pages): ?>
                <a href="?page=<?php echo ($page+1).$sParam.$vParam.$eParam; ?>" class="pg-btn">
                    <i class="fa-solid fa-chevron-right"></i>
                </a>
            <?php endif; ?>
        </div>
        <?php endif; ?>

    <?php else: ?>
        <div class="empty-box">
            <div class="empty-icon"><i class="fa-solid fa-bullhorn"></i></div>
            <h3><?php echo !empty($search_query) ? 'No results found' : 'No Notices Yet'; ?></h3>
            <p><?php echo !empty($search_query) ? 'Try different search keywords.' : 'No notices have been posted yet.'; ?></p>
            <?php if ($isAdmin && empty($search_query)): ?>
                <button class="btn-navy" onclick="openModal('addModal')" style="margin:0 auto;">
                    <i class="fa-solid fa-plus"></i> Create First Notice
                </button>
            <?php endif; ?>
        </div>
    <?php endif; ?>

</div>


<!-- MODAL: ADD NOTICE (inline POST — no separate file) -->
<?php if ($isAdmin): ?>
<div class="modal-overlay" id="addModal" onclick="handleOverlayClick(event, 'addModal')">
    <div class="modal-box">
        <div class="modal-head">
            <h5><i class="fa-solid fa-plus-circle"></i> Create New Notice</h5>
            <button class="modal-close" onclick="closeModal('addModal')">&#215;</button>
        </div>
        <form method="POST" action="?<?php echo ltrim($url_email, '&'); ?>">
            <input type="hidden" name="action" value="add_notice">
            <?php if (!empty($currentUserEmail)): ?>
                <input type="hidden" name="user_email" value="<?php echo htmlspecialchars($currentUserEmail); ?>">
            <?php endif; ?>
            <div class="modal-body">
                <div class="form-group">
                    <label class="form-label">Notice Title <span class="req">*</span></label>
                    <input type="text" name="title" class="form-control"
                           placeholder="Enter a clear and concise title" required>
                </div>
                <div class="form-group">
                    <label class="form-label">Description <span class="req">*</span></label>
                    <textarea name="description" class="form-control"
                              placeholder="Write the full notice details here..." required></textarea>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn-cancel" onclick="closeModal('addModal')">Cancel</button>
                <button type="submit" class="btn-navy">
                    <i class="fa-solid fa-check"></i> Publish Notice
                </button>
            </div>
        </form>
    </div>
</div>
<?php endif; ?>


<!-- MODAL: READ MORE -->
<div class="modal-overlay" id="readModal" onclick="handleOverlayClick(event, 'readModal')">
    <div class="modal-box">
        <div class="modal-head">
            <h5 id="readModalTitle"><i class="fa-regular fa-file-lines"></i> Notice</h5>
            <button class="modal-close" onclick="closeModal('readModal')">&#215;</button>
        </div>
        <div class="modal-body">
            <p class="notice-full-text" id="readModalBody"></p>
        </div>
        <div class="modal-footer">
            <button class="btn-cancel" onclick="closeModal('readModal')">
                <i class="fa-solid fa-xmark"></i> Close
            </button>
        </div>
    </div>
</div>


<!-- MODAL: DELETE CONFIRM -->
<?php if ($isAdmin): ?>
<div class="modal-overlay" id="deleteModal" onclick="handleOverlayClick(event, 'deleteModal')">
    <div class="modal-box" style="max-width:420px;">
        <div class="modal-head" style="background:linear-gradient(135deg,#991b1b,#dc2626);">
            <h5><i class="fa-solid fa-triangle-exclamation"></i> Confirm Delete</h5>
            <button class="modal-close" onclick="closeModal('deleteModal')">&#215;</button>
        </div>
        <div class="modal-body" style="text-align:center; padding:32px 24px;">
            <div style="width:64px;height:64px;background:#fee2e2;border-radius:50%;display:flex;align-items:center;justify-content:center;margin:0 auto 16px;font-size:28px;color:#dc2626;">
                <i class="fa-solid fa-trash"></i>
            </div>
            <h4 style="font-size:17px;font-weight:700;color:#1e293b;margin-bottom:10px;">Delete this notice?</h4>
            <p style="font-size:13px;color:#64748b;">This action cannot be undone. The notice will be permanently removed.</p>
        </div>
        <div class="modal-footer">
            <button class="btn-cancel" onclick="closeModal('deleteModal')">Cancel</button>
            <button id="confirmDeleteBtn" onclick=""
               style="background:linear-gradient(135deg,#dc2626,#b91c1c);color:white;border:none;padding:10px 20px;border-radius:10px;font-size:13px;font-weight:600;font-family:'Poppins',sans-serif;display:inline-flex;align-items:center;gap:7px;cursor:pointer;box-shadow:0 3px 10px rgba(220,38,38,0.28);">
                <i class="fa-solid fa-trash"></i> Yes, Delete
            </button>
        </div>
    </div>
</div>
<?php endif; ?>

<script>
    var urlEmail = '<?php echo addslashes($url_email); ?>';

    function openModal(id) {
        document.getElementById(id).classList.add('show');
        document.body.style.overflow = 'hidden';
    }
    function closeModal(id) {
        document.getElementById(id).classList.remove('show');
        document.body.style.overflow = '';
    }
    function handleOverlayClick(e, id) {
        if (e.target === document.getElementById(id)) closeModal(id);
    }
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') ['addModal','readModal','deleteModal'].forEach(closeModal);
    });

    function openReadMore(title, desc) {
        document.getElementById('readModalTitle').innerHTML = '<i class="fa-regular fa-file-lines"></i> ' + title;
        document.getElementById('readModalBody').innerHTML = desc.replace(/\n/g, '<br>');
        openModal('readModal');
    }

    <?php if ($isAdmin): ?>
    function confirmDelete(id) {
        document.getElementById('deleteModal').classList.remove('show');
        document.body.style.overflow = '';

        fetch('delete_notice.php?id=' + id + urlEmail)
            .catch(function() {})
            .finally(function() {
                // Reload with clean URL — no leftover POST data
                var base = window.location.href.split('?')[0];
                var params = 'msg=deleted';
                if (urlEmail) params += urlEmail;
                window.location.href = base + '?' + params;
            });
    }

    function confirmDeleteOpen(id) {
        document.getElementById('confirmDeleteBtn').onclick = function() {
            closeModal('deleteModal');
            confirmDelete(id);
        };
        openModal('deleteModal');
    }
    <?php endif; ?>

    // Auto-dismiss alerts after 5s
    setTimeout(function() {
        var a = document.querySelector('.alert-bar');
        if (a) { a.style.transition = 'opacity 0.5s'; a.style.opacity = '0'; setTimeout(function(){ a.style.display='none'; }, 500); }
    }, 4500);
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