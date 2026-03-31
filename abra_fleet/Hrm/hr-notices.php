<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('database.php');
require_once('database-settings.php');
require_once('library.php');
require_once('funciones.php');
require 'requirelanguage.php';
$con = conexion();

date_default_timezone_set($_SESSION['ge_timezone']);

// 1. SECURITY: Check if user is logged in
if (!isset($_SESSION['user_name'])) {
    header("Location: ../index.php"); 
    exit();
}

// 2. GET CURRENT USER NAME
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';

// 3. DEPARTMENT-BASED ADMIN DETECTION
// Get current user's employee data for department-based permissions
$employee_id = '';
$employee_name = '';
$employee_department = '';
$employee_position = '';
$employee_email = '';

if (!empty($currentUserName)) {
    $name_safe = mysqli_real_escape_string($con, $currentUserName);
    $res = mysqli_query($con, "SELECT employee_id, name, department, position, email FROM hr_employees WHERE LOWER(name) LIKE LOWER('%$name_safe%') AND (status = 'Active' OR status = 'active') LIMIT 1");
    if ($res && mysqli_num_rows($res) > 0) {
        $row = mysqli_fetch_assoc($res);
        $employee_id = $row['employee_id'];
        $employee_name = $row['name'];
        $employee_department = !empty($row['department']) ? $row['department'] : 'General';
        $employee_position = !empty($row['position']) ? $row['position'] : 'General';
        $employee_email = !empty($row['email']) ? $row['email'] : '';
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

// 4. CHECK IF CURRENT USER IS ADMIN
// Department-based OR position-based OR legacy names
$isAdmin = ($is_management_dept || $is_hr_dept || $is_managing_director || $is_abishek || $is_keerti);

// Get current user email for display
$currentUserEmail = $employee_email;
if(empty($currentUserEmail)) {
    // Fallback to legacy email mapping
    if($is_abishek) {
        $currentUserEmail = 'abishekjack1991@gmail.com';
    } elseif($is_keerti) {
        $currentUserEmail = 'hr-admin@abra-logistic.com';
    }
}

// 5. DETERMINE CORRECT BACK BUTTON URL
// Only Abhishek/Abishek and Managing Directors go to main dashboard (./)
// Keerthi and all employees go to raise-a-ticket page
$backUrl = 'https://crm.abra-logistic.com/dashboard/raise-a-ticket.php';  // Default for employees and Keerthi

// Check if user is specifically Abhishek/Abishek OR Managing Director
if($is_abishek || $is_managing_director) {
    $backUrl = './';  // Admin dashboard for Abhishek and Managing Directors
}

// 6. EXPORT FUNCTIONALITY
if(isset($_GET['action']) && $_GET['action'] == 'export') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=notices_export_' . date('Y-m-d') . '.csv');
    
    $output = fopen('php://output', 'w');
    
    // Add UTF-8 BOM for proper Excel encoding
    fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));
    
    // CSV Headers
    fputcsv($output, array('Notice ID', 'Title', 'Description', 'Created Date', 'Created Time'));
    
    // Get all notices for export
    $export_query = "SELECT * FROM hr_notices ORDER BY id DESC";
    $export_result = $con->query($export_query);
    
    while($row = $export_result->fetch_assoc()) {
        fputcsv($output, array(
            $row['id'],
            $row['title'],
            $row['description'],
            date('Y-m-d', strtotime($row['created_at'])),
            date('H:i:s', strtotime($row['created_at']))
        ));
    }
    
    fclose($output);
    exit;
}

// 7. SETTINGS: Pagination & Search
$notices_per_page = 12;
$page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$offset = ($page - 1) * $notices_per_page;
$search_query = isset($_GET['search']) ? trim($_GET['search']) : '';
$view_mode = isset($_GET['view']) ? $_GET['view'] : 'grid';

// 8. DATABASE QUERIES
$where_clause = "";
if (!empty($search_query)) {
    $search_escaped = $con->real_escape_string($search_query);
    $where_clause = "WHERE title LIKE '%$search_escaped%' OR description LIKE '%$search_escaped%'";
}

// Get Total Count
$count_query = "SELECT COUNT(*) as total FROM hr_notices $where_clause";
$count_result = $con->query($count_query);
$total_notices = $count_result->fetch_assoc()['total'];
$total_pages = ceil($total_notices / $notices_per_page);

// Get Data
$resultado = $con->query("SELECT * FROM hr_notices $where_clause ORDER BY id DESC LIMIT $notices_per_page OFFSET $offset");
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <title>Notice Board | Abra Logistics</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    
    <!-- CSS Libraries -->
    <link rel="stylesheet" href="../bower_components/bootstrap/dist/css/bootstrap.css" />
    <link rel="stylesheet" href="../bower_components/font-awesome/css/font-awesome.min.css" />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700;800&display=swap" rel="stylesheet">

    <style>
        * {
            box-sizing: border-box;
        }

        body {
            background-color: #f1f5f9;
            font-family: 'Inter', sans-serif;
            color: #334155;
            margin: 0;
            padding: 0;
            overflow-x: hidden;
        }

        /* Top Navigation Bar */
        .navbar-standalone {
            background: linear-gradient(135deg, #6366f1 0%, #4f46e5 100%);
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.25);
            color: white;
            position: sticky;
            top: 0;
            z-index: 1000;
            height: 70px;
        }

        .navbar-brand-custom {
            font-size: 20px;
            font-weight: 800;
            display: flex;
            align-items: center;
            gap: 10px;
            color: white;
        }

        .btn-back {
            background: rgba(255, 255, 255, 0.15);
            color: white !important;
            border: 1px solid rgba(255, 255, 255, 0.2);
            padding: 8px 16px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            transition: all 0.2s;
            font-size: 14px;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }

        .btn-back:hover {
            background: rgba(255, 255, 255, 0.25);
            text-decoration: none;
        }

        /* Main Container */
        .main-container {
            max-width: 1400px;
            margin: 30px auto;
            padding: 0 20px;
        }

        /* Action Bar */
        .action-bar {
            background: white;
            padding: 20px;
            border-radius: 16px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
        }

        .stats-section {
            display: flex;
            align-items: center;
            gap: 15px;
        }

        .stats-icon {
            width: 50px;
            height: 50px;
            background: #e0e7ff;
            color: #4f46e5;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
        }

        .stats-info h4 {
            margin: 0;
            font-weight: 700;
            font-size: 24px;
            color: #1e293b;
        }

        .stats-info span {
            font-size: 13px;
            color: #64748b;
        }

        .search-section {
            display: flex;
            gap: 10px;
            flex-grow: 1;
            max-width: 500px;
        }

        .search-input {
            flex-grow: 1;
            border: 2px solid #e2e8f0;
            border-radius: 10px;
            padding: 11px 15px;
            outline: none;
            font-size: 14px;
        }
        
        .search-input:focus { 
            border-color: #6366f1;
        }

        .btn-primary-custom {
            background: #4f46e5;
            color: white !important;
            border: none;
            padding: 11px 20px;
            border-radius: 10px;
            font-weight: 600;
            transition: all 0.2s;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            text-decoration: none;
        }
        
        .btn-primary-custom:hover { 
            background: #4338ca;
            color: white;
            text-decoration: none;
        }

        .btn-export {
            background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
            color: white !important;
            border: none;
            padding: 11px 20px;
            border-radius: 10px;
            font-weight: 600;
            transition: all 0.2s;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            text-decoration: none;
            box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3);
        }
        
        .btn-export:hover { 
            background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
            color: white;
            text-decoration: none;
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(59, 130, 246, 0.4);
        }

        .actions-right {
            display: flex;
            gap: 10px;
            align-items: center;
        }

        /* View Toggle Buttons */
        .view-toggle {
            display: flex;
            gap: 5px;
            background: #f1f5f9;
            padding: 4px;
            border-radius: 10px;
        }

        .view-btn {
            width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: transparent;
            border: none;
            border-radius: 8px;
            color: #64748b;
            cursor: pointer;
            transition: all 0.2s;
        }

        .view-btn:hover {
            color: #4f46e5;
        }

        .view-btn.active {
            background: white;
            color: #4f46e5;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        /* GRID VIEW */
        .notice-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 24px;
            margin-bottom: 20px;
        }

        @media (min-width: 768px) {
            .notice-grid {
                grid-template-columns: repeat(2, 1fr);
            }
        }

        @media (min-width: 1024px) {
            .notice-grid {
                grid-template-columns: repeat(3, 1fr);
            }
        }

        @media (min-width: 1400px) {
            .notice-grid {
                grid-template-columns: repeat(4, 1fr);
            }
        }

        /* LIST VIEW */
        .notice-list {
            display: flex;
            flex-direction: column;
            gap: 16px;
            margin-bottom: 20px;
        }

        .notice-card {
            background: white;
            border-radius: 16px;
            padding: 24px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            border: 1px solid #e2e8f0;
            display: flex;
            flex-direction: column;
            position: relative;
            overflow: hidden;
            height: 100%;
            min-height: 220px;
        }

        .notice-list .notice-card {
            min-height: auto;
            flex-direction: row;
            align-items: center;
            gap: 20px;
        }

        .notice-card:hover {
            transform: translateY(-8px);
            box-shadow: 0 12px 24px rgba(79, 70, 229, 0.15);
            border-color: #c7d2fe;
        }

        .notice-list .notice-card:hover {
            transform: translateX(5px);
        }

        .notice-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, #6366f1, #a855f7, #ec4899);
        }

        .notice-list .notice-card::before {
            width: 4px;
            height: 100%;
            top: 0;
            left: 0;
        }

        .notice-content {
            flex-grow: 1;
        }

        .notice-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 14px;
            font-size: 12px;
            color: #64748b;
            font-weight: 500;
        }

        .notice-list .notice-header {
            margin-bottom: 8px;
        }

        .notice-id {
            background: #f1f5f9;
            padding: 4px 10px;
            border-radius: 6px;
            color: #475569;
            font-weight: 600;
        }

        .notice-date {
            display: flex;
            align-items: center;
            gap: 5px;
        }

        .notice-title {
            font-size: 18px;
            font-weight: 700;
            color: #1e293b;
            margin-bottom: 12px;
            line-height: 1.4;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }

        .notice-list .notice-title {
            font-size: 20px;
            margin-bottom: 8px;
            -webkit-line-clamp: 1;
        }

        .notice-desc {
            font-size: 14px;
            color: #475569;
            line-height: 1.7;
            margin-bottom: 20px;
            flex-grow: 1;
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }

        .notice-list .notice-desc {
            margin-bottom: 0;
            -webkit-line-clamp: 2;
        }

        .notice-footer {
            margin-top: auto;
            padding-top: 16px;
            border-top: 1px solid #f1f5f9;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .notice-list .notice-footer {
            margin-top: 0;
            padding-top: 0;
            border-top: none;
            flex-direction: column;
            gap: 10px;
            min-width: 120px;
        }

        .btn-read {
            color: #4f46e5;
            background: none;
            border: none;
            font-weight: 600;
            font-size: 13px;
            padding: 0;
            cursor: pointer;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }

        .btn-read:hover {
            color: #4338ca;
            gap: 10px;
        }

        .notice-list .btn-read {
            background: #4f46e5;
            color: white;
            padding: 8px 16px;
            border-radius: 8px;
            width: 100%;
            justify-content: center;
        }

        .notice-list .btn-read:hover {
            background: #4338ca;
            gap: 6px;
        }

        .btn-delete {
            width: 34px;
            height: 34px;
            border-radius: 8px;
            background: #fee2e2;
            color: #ef4444;
            border: none;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .btn-delete:hover { 
            background: #ef4444;
            color: white;
            transform: scale(1.1);
        }

        .notice-list .btn-delete {
            width: 100%;
        }

        /* Pagination */
        .pagination-container {
            display: flex;
            justify-content: center;
            align-items: center;
            margin-top: 40px;
            gap: 8px;
            padding-bottom: 40px;
            flex-wrap: wrap;
        }
        
        .page-link-custom {
            min-width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            color: #64748b;
            text-decoration: none;
            font-weight: 600;
            padding: 0 12px;
            transition: all 0.2s;
        }
        
        .page-link-custom.active {
            background: #4f46e5;
            color: white;
            border-color: #4f46e5;
        }
        
        .page-link-custom:hover:not(.active) {
            border-color: #4f46e5;
            color: #4f46e5;
            text-decoration: none;
        }

        /* Empty State */
        .empty-state {
            text-align: center;
            padding: 80px 20px;
            background: white;
            border-radius: 16px;
            margin-top: 20px;
        }

        .empty-state i {
            font-size: 64px;
            color: #cbd5e1;
            margin-bottom: 20px;
        }

        .empty-state h3 {
            color: #64748b;
            font-weight: 600;
            margin-bottom: 10px;
        }

        .empty-state p {
            color: #94a3b8;
            font-size: 14px;
        }

        /* Modal Customization */
        .modal-header { 
            background: linear-gradient(135deg, #6366f1 0%, #4f46e5 100%);
            color: white;
            border-radius: 6px 6px 0 0;
        }

        .modal-header .close {
            color: white;
            opacity: 1;
            text-shadow: none;
        }

        .modal-header .close:hover {
            opacity: 0.8;
        }

        .modal-title {
            font-weight: 700;
        }

        .full-text-content {
            white-space: pre-wrap;
            color: #334155;
            line-height: 1.8;
            font-size: 15px;
        }

        .form-control {
            border-radius: 8px;
            border: 2px solid #e2e8f0;
            padding: 10px 15px;
        }

        .form-control:focus {
            border-color: #6366f1;
            box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
        }

        label {
            font-weight: 600;
            color: #1e293b;
            margin-bottom: 8px;
        }

        /* Admin Badge */
        .admin-badge {
            background: linear-gradient(135deg, #10b981, #059669);
            color: white;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            display: inline-block;
            margin-left: 10px;
        }

        /* Mobile Responsive */
        @media (max-width: 768px) {
            .navbar-standalone {
                padding: 12px 15px;
                height: auto;
            }

            .navbar-brand-custom {
                font-size: 16px;
            }

            .btn-back {
                padding: 6px 12px;
                font-size: 13px;
            }

            .main-container {
                padding: 0 15px;
                margin: 20px auto;
            }

            .action-bar {
                flex-direction: column;
                align-items: stretch;
            }

            .search-section {
                max-width: 100%;
                order: 3;
            }

            .stats-section {
                order: 1;
            }

            .actions-right {
                order: 2;
                justify-content: space-between;
                width: 100%;
                flex-wrap: wrap;
            }

            .notice-grid {
                grid-template-columns: 1fr;
                gap: 20px;
            }

            .notice-list .notice-card {
                flex-direction: column;
                align-items: stretch;
            }

            .notice-list .notice-footer {
                flex-direction: row;
                width: 100%;
                min-width: auto;
            }

            .pagination-container {
                gap: 5px;
            }

            .page-link-custom {
                min-width: 36px;
                height: 36px;
                font-size: 13px;
            }
        }
    </style>
</head>
<body>

    <!-- 1. STANDALONE TOP HEADER -->
    <nav class="navbar-standalone">
        <div class="navbar-brand-custom">
            <i class="fa fa-bullhorn"></i> Notice Board
            <?php if($isAdmin) { ?>
                <span class="admin-badge">✓ Admin</span>
            <?php } ?>
        </div>
        <div>
            <!-- DYNAMIC BACK BUTTON - Changes based on user type -->
            <a href="<?php echo $backUrl; ?>" class="btn-back">
                <i class="fa fa-arrow-left"></i> Back to Dashboard
            </a>
        </div>
    </nav>

    <!-- 2. MAIN CONTENT CONTAINER -->
    <div class="main-container">

        <!-- Action Bar -->
        <div class="action-bar">
            <!-- Stats -->
            <div class="stats-section">
                <div class="stats-icon">
                    <i class="fa fa-files-o"></i>
                </div>
                <div class="stats-info">
                    <h4><?php echo $total_notices; ?></h4>
                    <span><?php echo $total_notices == 1 ? 'Active Notice' : 'Active Notices'; ?></span>
                </div>
            </div>

            <!-- Search -->
            <form class="search-section" method="GET">
                <input type="hidden" name="view" value="<?php echo $view_mode; ?>">
                <input 
                    type="text" 
                    name="search" 
                    class="search-input" 
                    placeholder="Search by title or description..." 
                    value="<?php echo htmlspecialchars($search_query); ?>"
                >
                <button type="submit" class="btn-primary-custom">
                    <i class="fa fa-search"></i>
                </button>
                <?php if(!empty($search_query)) { ?>
                    <a href="?view=<?php echo $view_mode; ?>" class="btn btn-default" style="border-radius:10px; padding: 11px 16px;">
                        <i class="fa fa-times"></i>
                    </a>
                <?php } ?>
            </form>

            <!-- Actions Right -->
            <div class="actions-right">
                <!-- View Toggle -->
                <div class="view-toggle">
                    <a href="?view=grid<?php echo !empty($search_query) ? '&search='.urlencode($search_query) : ''; ?>" 
                       class="view-btn <?php echo $view_mode == 'grid' ? 'active' : ''; ?>" 
                       title="Grid View">
                        <i class="fa fa-th"></i>
                    </a>
                    <a href="?view=list<?php echo !empty($search_query) ? '&search='.urlencode($search_query) : ''; ?>" 
                       class="view-btn <?php echo $view_mode == 'list' ? 'active' : ''; ?>" 
                       title="List View">
                        <i class="fa fa-list"></i>
                    </a>
                </div>

                <!-- Export Button (Available to Everyone) -->
                <?php if($total_notices > 0) { ?>
                    <a href="?action=export" class="btn-export" title="Export all notices to CSV">
                        <i class="fa fa-download"></i> Export CSV
                    </a>
                <?php } ?>

                <!-- Add Button - ONLY SHOW FOR ADMINS -->
                <?php if($isAdmin) { ?>
                    <button class="btn-primary-custom" data-toggle="modal" data-target="#addNoticeModal">
                        <i class="fa fa-plus"></i> Add Notice
                    </button>
                <?php } ?>
            </div>
        </div>

        <!-- 3. NOTICE DISPLAY (Grid or List) -->
        <?php if($total_notices > 0) { ?>
            <div class="<?php echo $view_mode == 'list' ? 'notice-list' : 'notice-grid'; ?>">
                <?php while($row = $resultado->fetch_assoc()) { 
                    $fullDesc = $row['description'];
                    $shortDesc = strlen($fullDesc) > 120 ? substr($fullDesc, 0, 120) . '...' : $fullDesc;
                    $hasMore = strlen($fullDesc) > 120;

                    // Sanitize for JavaScript
                    $jsTitle = htmlspecialchars(str_replace("'", "\\'", $row['title']), ENT_QUOTES);
                    $jsDesc = htmlspecialchars(str_replace(array("\r\n", "\n", "\r", "'"), array("\\n", "\\n", "\\n", "\\'"), $fullDesc), ENT_QUOTES);
                ?>
                <div class="notice-card">
                    <div class="notice-content">
                        <div class="notice-header">
                            <span class="notice-id">#<?php echo $row['id']; ?></span>
                            <span class="notice-date">
                                <i class="fa fa-clock-o"></i>
                                <?php echo date('d M Y', strtotime($row['created_at'])); ?>
                            </span>
                        </div>
                        
                        <div class="notice-title"><?php echo htmlspecialchars($row['title']); ?></div>
                        
                        <div class="notice-desc">
                            <?php echo nl2br(htmlspecialchars($shortDesc)); ?>
                        </div>
                    </div>
                    
                    <div class="notice-footer">
                        <?php if($hasMore) { ?>
                            <button class="btn-read" onclick="openReadMore(<?php echo $row['id']; ?>, '<?php echo $jsTitle; ?>', '<?php echo $jsDesc; ?>')">
                                Read More <i class="fa fa-arrow-right"></i>
                            </button>
                        <?php } else { ?>
                            <span></span>
                        <?php } ?>

                        <!-- DELETE BUTTON - ALWAYS SHOW IF ADMIN -->
                        <?php if($isAdmin) { ?>
                            <button class="btn-delete" onclick="deleteNotice(<?php echo $row['id']; ?>)" title="Delete Notice">
                                <i class="fa fa-trash"></i>
                            </button>
                        <?php } ?>
                    </div>
                </div>
                <?php } ?>
            </div>

            <!-- Pagination -->
            <?php if($total_pages > 1) { ?>
            <div class="pagination-container">
                <!-- Previous Button -->
                <?php if($page > 1) { 
                    $sParam = !empty($search_query) ? '&search='.urlencode($search_query) : '';
                    $vParam = '&view='.$view_mode;
                ?>
                    <a href="?page=<?php echo ($page - 1); ?><?php echo $sParam.$vParam; ?>" class="page-link-custom">
                        <i class="fa fa-chevron-left"></i>
                    </a>
                <?php } ?>

                <!-- Page Numbers -->
                <?php 
                $start_page = max(1, $page - 2);
                $end_page = min($total_pages, $page + 2);
                
                for($i = $start_page; $i <= $end_page; $i++) { 
                    $active = ($i == $page) ? 'active' : '';
                    $sParam = !empty($search_query) ? '&search='.urlencode($search_query) : '';
                    $vParam = '&view='.$view_mode;
                    echo "<a href='?page=$i$sParam$vParam' class='page-link-custom $active'>$i</a>";
                } 
                ?>

                <!-- Next Button -->
                <?php if($page < $total_pages) { 
                    $sParam = !empty($search_query) ? '&search='.urlencode($search_query) : '';
                    $vParam = '&view='.$view_mode;
                ?>
                    <a href="?page=<?php echo ($page + 1); ?><?php echo $sParam.$vParam; ?>" class="page-link-custom">
                        <i class="fa fa-chevron-right"></i>
                    </a>
                <?php } ?>
            </div>
            <?php } ?>

        <?php } else { ?>
            <!-- Empty State -->
            <div class="empty-state">
                <i class="fa fa-search"></i>
                <h3>No notices found</h3>
                <p><?php echo !empty($search_query) ? 'Try adjusting your search terms' : 'No notices have been posted yet'; ?></p>
                <?php if($isAdmin && empty($search_query)) { ?>
                    <button class="btn-primary-custom" data-toggle="modal" data-target="#addNoticeModal" style="margin-top: 20px;">
                        <i class="fa fa-plus"></i> Create First Notice
                    </button>
                <?php } ?>
            </div>
        <?php } ?>

    </div>

    <!-- 4. MODALS -->

    <!-- Add Notice Modal (Admin Only - Abhishek & Keerthi) -->
    <?php if($isAdmin) { ?>
    <div class="modal fade" id="addNoticeModal" tabindex="-1" role="dialog">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                    <h4 class="modal-title">
                        <i class="fa fa-plus-circle"></i> Create New Notice
                    </h4>
                </div>
                <form action="settings/hr-employee/add-notice.php" method="post" data-parsley-validate>
                    <div class="modal-body" style="padding: 25px;">
                        <div class="form-group">
                            <label>Notice Title <span style="color:#ef4444;">*</span></label>
                            <input 
                                type="text" 
                                name="title" 
                                class="form-control" 
                                required 
                                placeholder="Enter a clear and concise title"
                                style="height:45px;"
                            >
                        </div>
                        <div class="form-group">
                            <label>Description <span style="color:#ef4444;">*</span></label>
                            <textarea 
                                name="description" 
                                class="form-control" 
                                rows="8" 
                                required
                                placeholder="Provide detailed information about this notice..."
                            ></textarea>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-default" data-dismiss="modal">Cancel</button>
                        <button type="submit" class="btn btn-primary">
                            <i class="fa fa-check"></i> Publish Notice
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    <?php } ?>

    <!-- Read More Modal (All Users) -->
    <div class="modal fade" id="readMoreModal" tabindex="-1" role="dialog">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <button type="button" class="close" data-dismiss="modal">&times;</button>
                    <h4 class="modal-title" id="readMoreTitle"></h4>
                </div>
                <div class="modal-body" style="padding: 30px;">
                    <div class="full-text-content" id="readMoreBody"></div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-default" data-dismiss="modal">
                        <i class="fa fa-times"></i> Close
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- SCRIPTS -->
    <script src="../bower_components/jquery/dist/jquery.min.js"></script>
    <script src="../bower_components/bootstrap/dist/js/bootstrap.js"></script>
    <script src="js/parsley.min.js"></script>

    <script>
        // Open Read More Modal
        function openReadMore(id, title, desc) {
            $('#readMoreTitle').html('<i class="fa fa-file-text-o"></i> ' + title);
            // Convert newline characters to HTML breaks
            $('#readMoreBody').html(desc.replace(/\\n/g, '<br>'));
            $('#readMoreModal').modal('show');
        }

        // Delete Logic (Admin Only - Abhishek & Keerthi)
        <?php if($isAdmin) { ?>
        function deleteNotice(id) {
            if(confirm('⚠️ Are you sure you want to delete this notice?\n\nThis action cannot be undone.')) {
                window.location.href = 'deletes/delete_notice.php?id=' + id;
            }
        }
        <?php } ?>

        // Auto-dismiss alerts after 5 seconds
        $(document).ready(function() {
            setTimeout(function() {
                $('.alert').fadeOut('slow');
            }, 5000);
        });
    </script>

</body>
</html>