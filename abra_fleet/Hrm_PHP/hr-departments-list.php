<?php
session_start();
error_reporting(E_ALL);
ini_set('display_errors', 1);

// =========================================================================
// HR MASTER SETTINGS - COMPLETE WITH COMPANIES TAB + LEAVE HIERARCHY
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

// --- ENSURE HIERARCHY TABLE EXISTS ---
$check_table = mysqli_query($con, "SHOW TABLES LIKE 'hr_leave_hierarchy'");
if(mysqli_num_rows($check_table) == 0) {
    mysqli_query($con, "CREATE TABLE hr_leave_hierarchy (
        position_id INT(11) NOT NULL,
        approver_1_id INT(11) DEFAULT NULL,
        approver_2_id INT(11) DEFAULT NULL,
        PRIMARY KEY (position_id)
    )");
}

date_default_timezone_set(isset($_SESSION['ge_timezone']) ? $_SESSION['ge_timezone'] : 'Asia/Kolkata');


$current_page = basename($_SERVER['PHP_SELF']);

// =========================================================================
// FILE SIZE CONFIGURATION (in MB)
// =========================================================================
define('MAX_LOGO_SIZE_MB', 2);  // 2 MB for company logos
define('MAX_LOGO_SIZE_BYTES', MAX_LOGO_SIZE_MB * 1024 * 1024);

// =========================================================================
// ADMIN CHECK (For Delete Permissions - Abhishek & Keerthi/Keerti)
// =========================================================================
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
// Added Keerthi and Keerti to the authorized list
$authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek', 'Abhishek', 'Keerthi', 'keerthi', 'Keerti', 'keerti');

$isAdmin = false;
foreach($authorized_admin_names as $admin_name) {
    if(stripos($currentUserName, $admin_name) !== false || stripos($admin_name, $currentUserName) !== false) {
        $isAdmin = true;
        break;
    }
}

// Determine dashboard redirect based on user
$dashboard_url = '/dashboard/raise-a-ticket.php'; // Default for non-admins
if(stripos($currentUserName, 'Abishek') !== false || stripos($currentUserName, 'Abhishek') !== false) {
    $dashboard_url = '/dashboard/index.php';
}

// Determine current view (Default to Departments)
$view = isset($_GET['view']) ? $_GET['view'] : 'departments';

// =========================================================================
// EXPORT FUNCTIONALITY
// =========================================================================
if(isset($_GET['action']) && $_GET['action'] == 'export') {
    $export_view = isset($_GET['export_view']) ? $_GET['export_view'] : $view;
    
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=' . $export_view . '_export_' . date('Y-m-d') . '.csv');
    
    $output = fopen('php://output', 'w');
    
    if($export_view == 'departments') {
        fputcsv($output, array('Department ID', 'Department Name'));
        $export_query = mysqli_query($con, "SELECT id, name FROM hr_departments ORDER BY name ASC");
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    } elseif($export_view == 'positions') {
        fputcsv($output, array('Position ID', 'Position Title', 'Department ID', 'Department Name'));
        $export_query = mysqli_query($con, "SELECT p.id, p.title, p.department_id, d.name as department_name FROM hr_positions p LEFT JOIN hr_departments d ON p.department_id = d.id ORDER BY p.title ASC");
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    } elseif($export_view == 'locations') {
        fputcsv($output, array('Location ID', 'Location Name', 'Latitude', 'Longitude'));
        $export_query = mysqli_query($con, "SELECT * FROM hr_work_locations ORDER BY location_name ASC");
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    } elseif($export_view == 'timings') {
        fputcsv($output, array('Timing ID', 'Start Time', 'End Time'));
        $export_query = mysqli_query($con, "SELECT * FROM hr_office_timings ORDER BY id ASC");
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    } elseif($export_view == 'companies') {
        fputcsv($output, array('Company ID', 'Company Name', 'Logo Path'));
        $export_query = mysqli_query($con, "SELECT id, company_name, logo_path FROM hr_companies ORDER BY company_name ASC");
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    } elseif($export_view == 'leave_hierarchy') {
        fputcsv($output, array('Position ID', 'Position Title', 'Department', 'Approver 1 Title', 'Approver 2 Title'));
        $sql = "SELECT p.id, p.title, IFNULL(d.name, 'N/A') as department_name, 
                IFNULL(a1.title, '') as approver_1_title, IFNULL(a2.title, '') as approver_2_title 
                FROM hr_positions p 
                LEFT JOIN hr_departments d ON p.department_id = d.id 
                LEFT JOIN hr_leave_hierarchy h ON p.id = h.position_id 
                LEFT JOIN hr_positions a1 ON h.approver_1_id = a1.id 
                LEFT JOIN hr_positions a2 ON h.approver_2_id = a2.id 
                ORDER BY IFNULL(d.name, 'ZZZ') ASC, p.title ASC";
        $export_query = mysqli_query($con, $sql);
        while($row = mysqli_fetch_assoc($export_query)) {
            fputcsv($output, $row);
        }
    }
    
    fclose($output);
    exit;
}

// =========================================================================
// IMPORT FUNCTIONALITY
// =========================================================================
if(isset($_POST['action']) && $_POST['action'] == 'import' && isset($_FILES['import_file'])) {
    $import_view = isset($_POST['import_view']) ? $_POST['import_view'] : $view;
    
    if($_FILES['import_file']['error'] === UPLOAD_ERR_OK) {
        $file = fopen($_FILES['import_file']['tmp_name'], 'r');
        $header = fgetcsv($file); // Skip header row
        $imported = 0;
        $errors = 0;
        
        while(($data = fgetcsv($file)) !== FALSE) {
            if($import_view == 'departments') {
                // Format: Department Name
                if(isset($data[1]) && !empty($data[1])) {
                    $name = mysqli_real_escape_string($con, $data[1]);
                    if(mysqli_query($con, "INSERT INTO hr_departments (name) VALUES ('$name')")) {
                        $imported++;
                    } else {
                        $errors++;
                    }
                }
            } elseif($import_view == 'positions') {
                // Format: Position Title, Department ID
                if(isset($data[1]) && isset($data[2]) && !empty($data[1]) && !empty($data[2])) {
                    $title = mysqli_real_escape_string($con, $data[1]);
                    $dept_id = intval($data[2]);
                    if(mysqli_query($con, "INSERT INTO hr_positions (title, department_id) VALUES ('$title', $dept_id)")) {
                        $imported++;
                    } else {
                        $errors++;
                    }
                }
            } elseif($import_view == 'locations') {
                // Format: Location Name, Latitude, Longitude
                if(isset($data[1]) && !empty($data[1])) {
                    $loc = mysqli_real_escape_string($con, $data[1]);
                    $lat = isset($data[2]) ? mysqli_real_escape_string($con, $data[2]) : '';
                    $lng = isset($data[3]) ? mysqli_real_escape_string($con, $data[3]) : '';
                    if(mysqli_query($con, "INSERT INTO hr_work_locations (location_name, latitude, longitude) VALUES ('$loc', '$lat', '$lng')")) {
                        $imported++;
                    } else {
                        $errors++;
                    }
                }
            } elseif($import_view == 'timings') {
                // Format: Start Time, End Time
                if(isset($data[1]) && isset($data[2]) && !empty($data[1])) {
                    $start = mysqli_real_escape_string($con, $data[1]);
                    $end = mysqli_real_escape_string($con, $data[2]);
                    if(mysqli_query($con, "INSERT INTO hr_office_timings (start_time, end_time) VALUES ('$start', '$end')")) {
                        $imported++;
                    } else {
                        $errors++;
                    }
                }
            } elseif($import_view == 'companies') {
                // Format: Company Name, Logo Path
                if(isset($data[1]) && !empty($data[1])) {
                    $company_name = mysqli_real_escape_string($con, $data[1]);
                    $logo_path = isset($data[2]) ? mysqli_real_escape_string($con, $data[2]) : '';
                    if(mysqli_query($con, "INSERT INTO hr_companies (company_name, logo_path) VALUES ('$company_name', '$logo_path')")) {
                        $imported++;
                    } else {
                        $errors++;
                    }
                }
            }
        }
        
        fclose($file);
        
        if($imported > 0) {
            $_SESSION['success_message'] = "Successfully imported $imported record(s)." . ($errors > 0 ? " $errors record(s) failed." : "");
        } else {
            $_SESSION['error_message'] = "Import failed. Please check your CSV format.";
        }
    } else {
        $_SESSION['error_message'] = "File upload error. Please try again.";
    }
    
    header("Location: $current_page?view=$import_view");
    exit;
}

// =========================================================================
// HANDLE FORM SUBMISSIONS
// =========================================================================
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    
    // --- ADD NEW RECORD ---
    if (isset($_POST['action']) && $_POST['action'] == 'add') {
        if ($view == 'departments') {
            // Check if adding a department or position
            if(isset($_POST['name'])) {
                // Adding a department
                $name = mysqli_real_escape_string($con, $_POST['name']);
                if(!empty($name)) mysqli_query($con, "INSERT INTO hr_departments (name) VALUES ('$name')");
            } elseif(isset($_POST['title']) && isset($_POST['department_id'])) {
                // Adding a position to a department
                $title = mysqli_real_escape_string($con, $_POST['title']);
                $dept_id = intval($_POST['department_id']);
                if(!empty($title) && $dept_id > 0) {
                    mysqli_query($con, "INSERT INTO hr_positions (title, department_id) VALUES ('$title', $dept_id)");
                }
            }
        } 
        elseif ($view == 'positions') {
            // Adding position from positions tab
            $title = mysqli_real_escape_string($con, $_POST['title']);
            $dept_id = intval($_POST['department_id']);
            if(!empty($title) && $dept_id > 0) {
                mysqli_query($con, "INSERT INTO hr_positions (title, department_id) VALUES ('$title', $dept_id)");
            }
        }
        elseif ($view == 'locations') {
            $loc = mysqli_real_escape_string($con, $_POST['location_name']);
            $lat = mysqli_real_escape_string($con, $_POST['latitude']);
            $lng = mysqli_real_escape_string($con, $_POST['longitude']);
            if(!empty($loc)) mysqli_query($con, "INSERT INTO hr_work_locations (location_name, latitude, longitude) VALUES ('$loc', '$lat', '$lng')");
        }
        elseif ($view == 'timings') {
            $start = mysqli_real_escape_string($con, $_POST['start_time']);
            $end = mysqli_real_escape_string($con, $_POST['end_time']);
            if(!empty($start)) mysqli_query($con, "INSERT INTO hr_office_timings (start_time, end_time) VALUES ('$start', '$end')");
        }
        elseif ($view == 'companies') {
            $company_name = mysqli_real_escape_string($con, $_POST['company_name']);
            $logo_path = '';
            
            // Handle logo upload
            if(isset($_FILES['company_logo']) && $_FILES['company_logo']['error'] === UPLOAD_ERR_OK) {
                $file = $_FILES['company_logo'];
                $file_size = $file['size'];
                
                // Validate file size
                if($file_size > MAX_LOGO_SIZE_BYTES) {
                    $actual_size_mb = round($file_size / (1024 * 1024), 2);
                    $_SESSION['error_message'] = "Logo file too large! Size: {$actual_size_mb} MB. Maximum: " . MAX_LOGO_SIZE_MB . " MB";
                    header("Location: $current_page?view=$view");
                    exit;
                }
                
                $upload_dir = 'uploads/company_logos/';
                if (!file_exists($upload_dir)) mkdir($upload_dir, 0777, true);
                
                $file_ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
                $allowed_ext = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
                
                if(in_array($file_ext, $allowed_ext)) {
                    $new_filename = 'company_' . time() . '.' . $file_ext;
                    $target_path = $upload_dir . $new_filename;
                    
                    if(move_uploaded_file($file['tmp_name'], $target_path)) {
                        $logo_path = $target_path;
                    }
                }
            }
            
            if(!empty($company_name)) {
                $logo_path_db = mysqli_real_escape_string($con, $logo_path);
                mysqli_query($con, "INSERT INTO hr_companies (company_name, logo_path) VALUES ('$company_name', '$logo_path_db')");
            }
        }
        $_SESSION['success_message'] = "Record added successfully";
        header("Location: $current_page?view=$view");
        exit;
    }

    // --- SAVE HIERARCHY ---
    if (isset($_POST['action']) && $_POST['action'] == 'save_hierarchy') {
        $position_id = intval($_POST['hierarchy_position_id']);
        $approver_1 = intval($_POST['approver_1_id']);
        $approver_2 = intval($_POST['approver_2_id']);
        
        // Validation: Cannot report to self
        if ($position_id == $approver_1 || $position_id == $approver_2) {
            $_SESSION['error_message'] = "Error: A position cannot report to itself.";
        } else {
            // Logic for NULLs if 0 is selected
            $a1_val = ($approver_1 > 0) ? $approver_1 : "NULL";
            $a2_val = ($approver_2 > 0) ? $approver_2 : "NULL";
            
            // ON DUPLICATE KEY UPDATE Logic
            $sql = "INSERT INTO hr_leave_hierarchy (position_id, approver_1_id, approver_2_id) 
                    VALUES ($position_id, $a1_val, $a2_val) 
                    ON DUPLICATE KEY UPDATE approver_1_id = $a1_val, approver_2_id = $a2_val";
            
            if(mysqli_query($con, $sql)) {
                $_SESSION['success_message'] = "Hierarchy updated successfully.";
            } else {
                $_SESSION['error_message'] = "Database Error: " . mysqli_error($con);
            }
        }
        header("Location: $current_page?view=leave_hierarchy");
        exit;
    }

    // --- EDIT RECORD ---
    if (isset($_POST['action']) && $_POST['action'] == 'edit') {
        $id = intval($_POST['edit_id']);
        
        if ($view == 'departments') {
            // Check if editing department or position
            if(isset($_POST['edit_name'])) {
                // Editing department
                $name = mysqli_real_escape_string($con, $_POST['edit_name']);
                mysqli_query($con, "UPDATE hr_departments SET name='$name' WHERE id=$id");
            } elseif(isset($_POST['edit_title']) && isset($_POST['edit_department_id'])) {
                // Editing position
                $title = mysqli_real_escape_string($con, $_POST['edit_title']);
                $dept_id = intval($_POST['edit_department_id']);
                mysqli_query($con, "UPDATE hr_positions SET title='$title', department_id=$dept_id WHERE id=$id");
            }
        }
        elseif ($view == 'positions') {
            // Editing position from positions tab
            $title = mysqli_real_escape_string($con, $_POST['edit_title']);
            $dept_id = intval($_POST['edit_department_id']);
            mysqli_query($con, "UPDATE hr_positions SET title='$title', department_id=$dept_id WHERE id=$id");
        }
        elseif ($view == 'locations') {
            $loc = mysqli_real_escape_string($con, $_POST['edit_location']);
            $lat = mysqli_real_escape_string($con, $_POST['edit_latitude']);
            $lng = mysqli_real_escape_string($con, $_POST['edit_longitude']);
            mysqli_query($con, "UPDATE hr_work_locations SET location_name='$loc', latitude='$lat', longitude='$lng' WHERE id=$id");
        }
        elseif ($view == 'timings') {
            $start = mysqli_real_escape_string($con, $_POST['edit_start']);
            $end = mysqli_real_escape_string($con, $_POST['edit_end']);
            mysqli_query($con, "UPDATE hr_office_timings SET start_time='$start', end_time='$end' WHERE id=$id");
        }
        elseif ($view == 'companies') {
            $company_name = mysqli_real_escape_string($con, $_POST['edit_company_name']);
            
            // Get existing logo path
            $existing = mysqli_query($con, "SELECT logo_path FROM hr_companies WHERE id=$id");
            $existing_row = mysqli_fetch_assoc($existing);
            $logo_path = $existing_row['logo_path'];
            
            // Handle new logo upload
            if(isset($_FILES['edit_company_logo']) && $_FILES['edit_company_logo']['error'] === UPLOAD_ERR_OK) {
                $file = $_FILES['edit_company_logo'];
                $file_size = $file['size'];
                
                // Validate file size
                if($file_size > MAX_LOGO_SIZE_BYTES) {
                    $actual_size_mb = round($file_size / (1024 * 1024), 2);
                    $_SESSION['error_message'] = "Logo file too large! Size: {$actual_size_mb} MB. Maximum: " . MAX_LOGO_SIZE_MB . " MB";
                    header("Location: $current_page?view=$view");
                    exit;
                }
                
                $upload_dir = 'uploads/company_logos/';
                if (!file_exists($upload_dir)) mkdir($upload_dir, 0777, true);
                
                $file_ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
                $allowed_ext = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
                
                if(in_array($file_ext, $allowed_ext)) {
                    // Delete old logo
                    if(!empty($logo_path) && file_exists($logo_path)) {
                        unlink($logo_path);
                    }
                    
                    $new_filename = 'company_' . time() . '.' . $file_ext;
                    $target_path = $upload_dir . $new_filename;
                    
                    if(move_uploaded_file($file['tmp_name'], $target_path)) {
                        $logo_path = $target_path;
                    }
                }
            }
            
            $logo_path_db = mysqli_real_escape_string($con, $logo_path);
            mysqli_query($con, "UPDATE hr_companies SET company_name='$company_name', logo_path='$logo_path_db' WHERE id=$id");
        }
        $_SESSION['success_message'] = "Record updated successfully";
        header("Location: $current_page?view=$view");
        exit;
    }

    // --- DELETE RECORD (Allowed for ABHISHEK & KEERTHI) ---
    if (isset($_POST['action']) && $_POST['action'] == 'delete') {
        if ($isAdmin) {
            $id = intval($_POST['delete_id']);
            $table = '';
            
            // Check if deleting a position (has delete_type parameter)
            if(isset($_POST['delete_type']) && $_POST['delete_type'] == 'position') {
                $table = 'hr_positions';
                // Also clean up hierarchy
                mysqli_query($con, "DELETE FROM hr_leave_hierarchy WHERE position_id=$id");
            }
            // If deleting company, remove logo file
            elseif($view == 'companies') {
                $logo_query = mysqli_query($con, "SELECT logo_path FROM hr_companies WHERE id=$id");
                if($logo_row = mysqli_fetch_assoc($logo_query)) {
                    if(!empty($logo_row['logo_path']) && file_exists($logo_row['logo_path'])) {
                        unlink($logo_row['logo_path']);
                    }
                }
                $table = 'hr_companies';
            }
            elseif($view == 'leave_hierarchy') {
                // For hierarchy view, delete just removes the mapping from hierarchy table
                $table = 'hr_leave_hierarchy';
                mysqli_query($con, "DELETE FROM hr_leave_hierarchy WHERE position_id=$id");
                $_SESSION['success_message'] = "Hierarchy removed successfully";
                header("Location: $current_page?view=$view");
                exit;
            }
            elseif ($view == 'departments') $table = 'hr_departments';
            elseif ($view == 'positions') $table = 'hr_positions';
            elseif ($view == 'locations') $table = 'hr_work_locations';
            elseif ($view == 'timings') $table = 'hr_office_timings';

            if ($table && $view != 'leave_hierarchy') {
                mysqli_query($con, "DELETE FROM $table WHERE id=$id");
                $_SESSION['success_message'] = "Record deleted successfully";
            }
        } else {
            $_SESSION['error_message'] = "Access Denied: You do not have permission to delete records.";
        }
        header("Location: $current_page?view=$view");
        exit;
    }
}

// =========================================================================
// FETCH DATA
// =========================================================================
if ($view == 'departments') {
    // Fetch departments with position counts
    $data_query = "SELECT d.*, 
                   (SELECT COUNT(*) FROM hr_positions p WHERE p.department_id = d.id) as position_count 
                   FROM hr_departments d 
                   ORDER BY d.name ASC";
    $result = mysqli_query($con, $data_query);
} elseif ($view == 'positions') {
    // Fetch all positions with their department info
    $data_query = "SELECT p.*, d.name as department_name 
                   FROM hr_positions p 
                   LEFT JOIN hr_departments d ON p.department_id = d.id 
                   ORDER BY p.title ASC";
    $result = mysqli_query($con, $data_query);
} elseif ($view == 'locations') {
    $data_query = "SELECT * FROM hr_work_locations ORDER BY location_name ASC";
    $result = mysqli_query($con, $data_query);
} elseif ($view == 'companies') {
    $data_query = "SELECT * FROM hr_companies ORDER BY company_name ASC";
    $result = mysqli_query($con, $data_query);
} elseif ($view == 'leave_hierarchy') {
    // FIXED QUERY - Using IFNULL and proper ordering
    $data_query = "SELECT p.id, p.title, IFNULL(d.name, 'N/A') as department_name, 
                   h.approver_1_id, h.approver_2_id,
                   IFNULL(a1.title, '') as approver_1_title, 
                   IFNULL(a2.title, '') as approver_2_title 
                   FROM hr_positions p 
                   LEFT JOIN hr_departments d ON p.department_id = d.id 
                   LEFT JOIN hr_leave_hierarchy h ON p.id = h.position_id 
                   LEFT JOIN hr_positions a1 ON h.approver_1_id = a1.id 
                   LEFT JOIN hr_positions a2 ON h.approver_2_id = a2.id 
                   ORDER BY IFNULL(d.name, 'ZZZ') ASC, p.title ASC";
    $result = mysqli_query($con, $data_query);
    
    // Check if query failed
    if(!$result) {
        die("Query Error: " . mysqli_error($con));
    }
} else {
    $data_query = "SELECT * FROM hr_office_timings ORDER BY id ASC";
    $result = mysqli_query($con, $data_query);
}

$total_rows = mysqli_num_rows($result);

// Fetch all departments for dropdown
$departments_dropdown = mysqli_query($con, "SELECT * FROM hr_departments ORDER BY name ASC");

// Fetch all positions for Hierarchy dropdowns (Need for JSON pass-through)
if ($view == 'leave_hierarchy') {
    $pos_dd_query = mysqli_query($con, "SELECT p.id, p.title, IFNULL(d.name, 'No Department') as dept_name FROM hr_positions p LEFT JOIN hr_departments d ON p.department_id = d.id ORDER BY p.title ASC");
    $all_positions = array();
    while($row = mysqli_fetch_assoc($pos_dd_query)) {
        $all_positions[] = $row;
    }
}

// Page Configuration (Dynamic Button Titles)
$view_config = [
    'departments' => [
        'title' => 'Departments', 
        'icon' => 'fa-sitemap', 
        'btn_text' => 'Add Department'
    ],
    'positions' => [
        'title' => 'Positions', 
        'icon' => 'fa-id-badge', 
        'btn_text' => 'Add Position'
    ],
    'locations' => [
        'title' => 'Work Locations', 
        'icon' => 'fa-map-marker-alt', 
        'btn_text' => 'Add Location'
    ],
    'timings' => [
        'title' => 'Office Timings', 
        'icon' => 'fa-clock', 
        'btn_text' => 'Add Timing'
    ],
    'companies' => [
        'title' => 'Companies', 
        'icon' => 'fa-building', 
        'btn_text' => 'Add Company'
    ],
    'leave_hierarchy' => [
        'title' => 'Leave Hierarchy', 
        'icon' => 'fa-users-cog', 
        'btn_text' => '' // No add button, just edit existing positions
    ]
];

$current_title = $view_config[$view]['title'];
$current_icon = $view_config[$view]['icon'];
$current_btn_text = $view_config[$view]['btn_text'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title><?php echo $_SESSION['ge_cname']; ?> | Master Settings</title>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />

  <!-- CSS Resources -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/css/bootstrap.min.css" />
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Poppins', sans-serif; background: #f0f4f8; min-height: 100vh; padding: 20px 0; }
    
    .container-fluid { 
      max-width: 1600px; 
      margin: 0 auto; 
      padding: 0 20px;
    }

    /* Header */
    .page-header {
      background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
      padding: 20px 30px;
      border-radius: 10px;
      box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3);
      margin-bottom: 20px;
      display: flex; 
      justify-content: space-between; 
      align-items: center;
    }
    .page-header h1 { color: white; font-weight: 600; margin: 0; font-size: 1.8rem; }
    
    .stat-box { text-align: center; padding: 8px 20px; background: rgba(255, 255, 255, 0.15); border-radius: 8px; }
    .stat-box .stat-number { font-size: 1.8rem; font-weight: 700; color: white; }
    .stat-box .stat-label { font-size: 0.85rem; color: rgba(255, 255, 255, 0.9); margin-top: 4px; }

    /* Navigation Tabs */
    .nav-tabs-container {
        display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap;
    }
    .nav-btn {
        padding: 12px 25px; background: white; border-radius: 12px; color: #64748b;
        font-weight: 600; text-decoration: none; transition: all 0.3s;
        box-shadow: 0 2px 5px rgba(0,0,0,0.05); display: flex; align-items: center; gap: 8px; border: 2px solid transparent;
    }
    .nav-btn:hover { text-decoration: none; transform: translateY(-2px); color: #1e3a8a; border-color: #e2e8f0; }
    .nav-btn.active { 
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); 
        color: white; 
        box-shadow: 0 4px 15px rgba(30, 58, 138, 0.3); 
    }

    /* Action Bar */
    .action-bar {
      background: white; 
      padding: 20px; 
      border-radius: 10px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.08); 
      margin-bottom: 20px;
      display: flex; 
      justify-content: space-between; 
      align-items: center;
      flex-wrap: wrap;
      gap: 15px;
    }
    
    .action-bar-left {
        display: flex;
        align-items: center;
        gap: 15px;
        flex-wrap: wrap;
    }
    
    .action-bar-right {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
    }
    
    .btn-action {
      border: none; padding: 12px 28px; border-radius: 10px; font-weight: 700;
      transition: all 0.3s; display: inline-flex; align-items: center; gap: 10px;
      font-size: 15px; color: white; text-decoration: none; cursor: pointer;
      background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      box-shadow: 0 4px 15px rgba(16, 185, 129, 0.3);
    }
    .btn-action:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(16, 185, 129, 0.4); color: white; text-decoration: none; }

    .btn-export {
      background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
      box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3);
    }
    .btn-export:hover { box-shadow: 0 8px 25px rgba(59, 130, 246, 0.4); }

    .btn-import {
      background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);
      box-shadow: 0 4px 15px rgba(245, 158, 11, 0.3);
    }
    .btn-import:hover { box-shadow: 0 8px 25px rgba(245, 158, 11, 0.4); }

    /* Back to Dashboard Button */
    .btn-back-dashboard {
      background: rgba(30, 58, 138, 0.1);
      color: #1e3a8a;
      padding: 10px 20px;
      border-radius: 10px;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-weight: 600;
      transition: all 0.3s;
      border: 2px solid #e2e8f0;
      font-size: 14px;
    }
    
    .btn-back-dashboard:hover {
      background: #1e3a8a;
      color: white;
      text-decoration: none;
      transform: translateX(-3px);
      border-color: #1e3a8a;
    }

    /* Department Card Style */
    .department-card {
        background: white;
        border-radius: 12px;
        margin-bottom: 25px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.08);
        border: 3px solid #e2e8f0;
        overflow: hidden;
        transition: all 0.3s;
    }
    
    .department-card:hover {
        box-shadow: 0 4px 20px rgba(0,0,0,0.12);
        transform: translateY(-2px);
    }

    .department-header {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
        color: white;
        padding: 20px 25px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        cursor: pointer;
        user-select: none;
    }

    .department-header:hover {
        background: linear-gradient(135deg, #1e40af 0%, #2563eb 100%);
    }

    .department-name {
        font-size: 1.4rem;
        font-weight: 700;
        display: flex;
        align-items: center;
        gap: 12px;
    }

    .position-count-badge {
        background: rgba(255, 255, 255, 0.2);
        padding: 6px 16px;
        border-radius: 20px;
        font-size: 0.9rem;
        font-weight: 600;
    }

    .department-actions {
        display: flex;
        gap: 10px;
        align-items: center;
    }

    .expand-icon {
        transition: transform 0.3s;
        font-size: 1.2rem;
    }

    .expand-icon.expanded {
        transform: rotate(180deg);
    }

    .positions-container {
        padding: 20px 25px;
        display: none;
        background: #f8fafc;
    }

    .positions-container.show {
        display: block;
    }

    .position-item {
        background: white;
        padding: 15px 20px;
        margin-bottom: 12px;
        border-radius: 10px;
        border-left: 4px solid #10b981;
        display: flex;
        justify-content: space-between;
        align-items: center;
        box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        transition: all 0.3s;
    }

    .position-item:hover {
        transform: translateX(5px);
        box-shadow: 0 4px 10px rgba(0,0,0,0.1);
    }

    .position-title {
        font-weight: 600;
        color: #1e3a8a;
        font-size: 1.1rem;
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .no-positions {
        text-align: center;
        padding: 40px;
        color: #94a3b8;
        font-style: italic;
    }

    /* Table Container - HIDDEN UNTIL LOADED */
    .table-container { 
      background: white; 
      padding: 20px; 
      border-radius: 10px; 
      box-shadow: 0 2px 10px rgba(0,0,0,0.08);
      display: none; /* HIDDEN BY DEFAULT */
    }
    
    .table-container.loaded {
      display: block; /* SHOW WHEN LOADED */
    }
    
    table.dataTable thead th {
        background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%) !important; 
        color: white !important; font-weight: 700 !important; 
        border: 1px solid #1e3a8a !important; padding: 15px 10px !important; 
    }

    table.dataTable tbody td {
        border: 1px solid #e2e8f0 !important; padding: 12px 10px !important;
        font-weight: 600 !important; color: #1e293b !important; vertical-align: middle;
    }

    /* Company Logo Display */
    .company-logo-display {
        width: 80px;
        height: 80px;
        object-fit: contain;
        border-radius: 8px;
        border: 2px solid #e2e8f0;
        padding: 5px;
        background: white;
    }
    
    .company-card {
        background: white;
        border-radius: 12px;
        padding: 20px;
        margin-bottom: 20px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.08);
        border: 2px solid #e2e8f0;
        display: flex;
        align-items: center;
        gap: 20px;
        transition: all 0.3s;
    }
    
    .company-card:hover {
        box-shadow: 0 4px 20px rgba(0,0,0,0.12);
        transform: translateY(-2px);
    }
    
    .company-logo-container {
        flex-shrink: 0;
    }
    
    .company-info {
        flex: 1;
    }
    
    .company-name {
        font-size: 1.3rem;
        font-weight: 700;
        color: #1e3a8a;
        margin-bottom: 5px;
    }

    /* Action Icons */
    .action-btn {
      display: inline-block; width: 32px; height: 32px; line-height: 32px; text-align: center;
      border-radius: 8px; margin: 0 5px; transition: all 0.3s ease; text-decoration: none; font-size: 14px; cursor: pointer;
    }
    .btn-icon-edit { background: #1e40af; color: white; border: none; }
    .btn-icon-delete { background: #dc2626; color: white; border: none; }
    
    .btn-icon-edit:hover { background: #1e3a8a; color: white; transform: scale(1.15); }
    .btn-icon-delete:hover { background: #b91c1c; color: white; transform: scale(1.15); }

    /* Modals */
    .modal-content { border-radius: 15px; border: none; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
    .modal-header { background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); color: white; border-radius: 15px 15px 0 0; padding: 20px 30px; }
    .close { color: white; opacity: 0.9; text-shadow: none; font-size: 28px; }
    .form-control { border-radius: 8px; padding: 10px 15px; height: auto; border: 2px solid #e2e8f0; }
    .form-control:focus { border-color: #1e40af; box-shadow: none; }

    /* Alert */
    .alert-container { position: fixed; top: 20px; right: 20px; z-index: 9999; min-width: 300px; max-width: 500px; }
    .alert { border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); }
    
    /* Lat/Long display style */
    code { background: #f1f5f9; padding: 2px 6px; border-radius: 4px; color: #e11d48; font-weight: 700; }

    /* Leave Hierarchy Badges */
    .badge-approver-1 { background: #d1fae5; color: #065f46; border: 1px solid #10b981; padding: 4px 8px; border-radius: 4px; font-size: 0.85rem; font-weight: 600; display: inline-flex; align-items: center; gap: 5px; }
    .badge-approver-2 { background: #fef3c7; color: #92400e; border: 1px solid #f59e0b; padding: 4px 8px; border-radius: 4px; font-size: 0.85rem; font-weight: 600; display: inline-flex; align-items: center; gap: 5px; }
    .badge-none { background: #f1f5f9; color: #94a3b8; border: 1px solid #cbd5e1; padding: 4px 8px; border-radius: 4px; font-size: 0.85rem; font-style: italic; }

    /* Loading Spinner */
    .table-loader {
        text-align: center;
        padding: 40px;
        background: white;
        border-radius: 10px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.08);
    }
    
    .spinner {
        border: 4px solid #f3f3f3;
        border-top: 4px solid #1e3a8a;
        border-radius: 50%;
        width: 50px;
        height: 50px;
        animation: spin 1s linear infinite;
        margin: 0 auto 15px;
    }
    
    @keyframes spin {
        0% { transform: rotate(0deg); }
        100% { transform: rotate(360deg); }
    }
    
    /* Responsive adjustments */
    @media (max-width: 768px) {
        .action-bar {
            flex-direction: column;
            align-items: stretch;
        }
        .action-bar-left, .action-bar-right {
            width: 100%;
            justify-content: center;
        }
    }
  </style>
</head>
<body>

<!-- Alert Messages -->
<div class="alert-container">
  <?php if (isset($_SESSION['success_message'])): ?>
    <div class="alert alert-success alert-dismissible fade show">
      <strong><i class="fa fa-check-circle"></i> Success!</strong> <?php echo htmlspecialchars($_SESSION['success_message']); ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['success_message']); ?>
  <?php endif; ?>
  
  <?php if (isset($_SESSION['error_message'])): ?>
    <div class="alert alert-danger alert-dismissible fade show">
      <strong><i class="fa fa-exclamation-triangle"></i> Error!</strong> <?php echo $_SESSION['error_message']; ?>
      <button type="button" class="close" data-dismiss="alert">&times;</button>
    </div>
    <?php unset($_SESSION['error_message']); ?>
  <?php endif; ?>
</div>

<div class="container-fluid">
  
  <div class="page-header">
    <div><h1><i class="fas fa-sliders-h"></i> Master Settings</h1></div>
    <div class="header-stats">
      <div class="stat-box">
        <div class="stat-number"><?php echo $total_rows; ?></div>
        <div class="stat-label">Total Records</div>
      </div>
    </div>
  </div>

  <div class="nav-tabs-container">
      <a href="?view=departments" class="nav-btn <?php echo $view=='departments'?'active':''; ?>">
          <i class="fas fa-sitemap"></i> Departments & Positions
      </a>
      <a href="?view=positions" class="nav-btn <?php echo $view=='positions'?'active':''; ?>">
          <i class="fas fa-list"></i> All Positions
      </a>
      <a href="?view=locations" class="nav-btn <?php echo $view=='locations'?'active':''; ?>">
          <i class="fas fa-map-marker-alt"></i> Locations
      </a>
      <a href="?view=timings" class="nav-btn <?php echo $view=='timings'?'active':''; ?>">
          <i class="fas fa-clock"></i> Timings
      </a>
      <a href="?view=companies" class="nav-btn <?php echo $view=='companies'?'active':''; ?>">
          <i class="fas fa-building"></i> Companies
      </a>
      <a href="?view=leave_hierarchy" class="nav-btn <?php echo $view=='leave_hierarchy'?'active':''; ?>">
          <i class="fas fa-users-cog"></i> Leave Hierarchy
      </a>
  </div>

  <div class="action-bar">
    <div class="action-bar-left">
      <h4 style="margin:0; color: #1e3a8a; font-weight: 700; font-size: 1.5rem;">
          <i class="fas <?php echo $current_icon; ?>"></i> <?php echo $current_title; ?> List
      </h4>
      
      <!-- Back to Dashboard Button -->
      <a href="<?php echo $dashboard_url; ?>" class="btn-back-dashboard">
        <i class="fas fa-arrow-left"></i> Back to Dashboard
      </a>
    </div>
    
    <div class="action-bar-right">
      <!-- Export Button -->
      <a href="?action=export&export_view=<?php echo $view; ?>" class="btn-action btn-export">
        <i class="fas fa-download"></i> Export CSV
      </a>
      
      <?php if($view != 'leave_hierarchy'): ?>
      <!-- Import Button -->
      <button type="button" class="btn-action btn-import" data-toggle="modal" data-target="#importModal">
        <i class="fas fa-upload"></i> Import CSV
      </button>
      
      <!-- Add Button -->
      <button type="button" class="btn-action" data-toggle="modal" data-target="#addModal">
        <i class="fas fa-plus"></i> <?php echo $current_btn_text; ?>
      </button>
      <?php endif; ?>
    </div>
  </div>

  <?php if($view == 'departments'): ?>
    <!-- HIERARCHICAL DEPARTMENT VIEW -->
    <?php 
    mysqli_data_seek($result, 0);
    while($dept = mysqli_fetch_assoc($result)) { 
        // Fetch positions for this department
        $dept_id = $dept['id'];
        $positions_query = mysqli_query($con, "SELECT * FROM hr_positions WHERE department_id = $dept_id ORDER BY title ASC");
        $has_positions = mysqli_num_rows($positions_query) > 0;
    ?>
    <div class="department-card">
        <div class="department-header" onclick="toggleDepartment(<?php echo $dept['id']; ?>)">
            <div class="department-name">
                <i class="fas fa-sitemap"></i>
                <?php echo htmlspecialchars($dept['name']); ?>
                <span class="position-count-badge">
                    <?php echo $dept['position_count']; ?> Position<?php echo $dept['position_count'] != 1 ? 's' : ''; ?>
                </span>
            </div>
            <div class="department-actions">
                <button class="action-btn btn-icon-edit" 
                    data-id="<?php echo $dept['id']; ?>"
                    data-name="<?php echo htmlspecialchars($dept['name']); ?>"
                    onclick="event.stopPropagation(); openEditDeptModal(this);" title="Edit Department">
                    <i class="fas fa-edit"></i>
                </button>

                <?php if($isAdmin): ?>
                  <form method="POST" style="display:inline;" onsubmit="event.stopPropagation(); return confirm('⚠️ Are you sure? This will also affect all positions under this department!');">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="delete_id" value="<?php echo $dept['id']; ?>">
                    <button type="submit" class="action-btn btn-icon-delete" title="Delete Department">
                        <i class="fas fa-trash"></i>
                    </button>
                  </form>
                <?php endif; ?>

                <i class="fas fa-chevron-down expand-icon" id="icon_<?php echo $dept['id']; ?>"></i>
            </div>
        </div>

        <div class="positions-container" id="positions_<?php echo $dept['id']; ?>">
            <?php if($has_positions): ?>
                <?php while($pos = mysqli_fetch_assoc($positions_query)): ?>
                <div class="position-item">
                    <div class="position-title">
                        <i class="fas fa-user-tie"></i>
                        <?php echo htmlspecialchars($pos['title']); ?>
                    </div>
                    <div>
                        <button class="action-btn btn-icon-edit" 
                            data-id="<?php echo $pos['id']; ?>"
                            data-title="<?php echo htmlspecialchars($pos['title']); ?>"
                            data-dept="<?php echo $pos['department_id']; ?>"
                            onclick="openEditPosModal(this)" title="Edit Position">
                            <i class="fas fa-edit"></i>
                        </button>

                        <?php if($isAdmin): ?>
                          <form method="POST" style="display:inline;" onsubmit="return confirm('⚠️ Are you sure you want to delete this position?');">
                            <input type="hidden" name="action" value="delete">
                            <input type="hidden" name="delete_type" value="position">
                            <input type="hidden" name="delete_id" value="<?php echo $pos['id']; ?>">
                            <button type="submit" class="action-btn btn-icon-delete" title="Delete Position">
                                <i class="fas fa-trash"></i>
                            </button>
                          </form>
                        <?php endif; ?>
                    </div>
                </div>
                <?php endwhile; ?>
            <?php else: ?>
                <div class="no-positions">
                    <i class="fas fa-inbox" style="font-size: 48px; margin-bottom: 10px; opacity: 0.3;"></i><br>
                    No positions added yet. Click "Add Designation" above to add positions to this department.
                </div>
            <?php endif; ?>
        </div>
    </div>
    <?php } ?>

  <?php elseif($view == 'companies'): ?>
    <!-- COMPANIES VIEW WITH LOGOS -->
    <?php 
    mysqli_data_seek($result, 0);
    if(mysqli_num_rows($result) > 0):
        while($company = mysqli_fetch_assoc($result)): 
    ?>
    <div class="company-card">
        <div class="company-logo-container">
            <?php if(!empty($company['logo_path']) && file_exists($company['logo_path'])): ?>
                <img src="<?php echo htmlspecialchars($company['logo_path']); ?>" 
                     alt="<?php echo htmlspecialchars($company['company_name']); ?>" 
                     class="company-logo-display">
            <?php else: ?>
                <div class="company-logo-display" style="display: flex; align-items: center; justify-content: center; background: #f1f5f9;">
                    <i class="fas fa-building" style="font-size: 2rem; color: #94a3b8;"></i>
                </div>
            <?php endif; ?>
        </div>
        <div class="company-info">
            <div class="company-name"><?php echo htmlspecialchars($company['company_name']); ?></div>
            <div style="color: #64748b; font-size: 0.9rem;">
                <?php echo !empty($company['logo_path']) ? 'Logo Available' : 'No Logo'; ?>
            </div>
        </div>
        <div>
            <button class="action-btn btn-icon-edit" 
                data-id="<?php echo $company['id']; ?>"
                data-name="<?php echo htmlspecialchars($company['company_name']); ?>"
                data-logo="<?php echo htmlspecialchars($company['logo_path']); ?>"
                onclick="openEditCompanyModal(this)" title="Edit Company">
                <i class="fas fa-edit"></i>
            </button>

            <?php if($isAdmin): ?>
              <form method="POST" style="display:inline;" onsubmit="return confirm('⚠️ Are you sure you want to delete this company?');">
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="delete_id" value="<?php echo $company['id']; ?>">
                <button type="submit" class="action-btn btn-icon-delete" title="Delete Company">
                    <i class="fas fa-trash"></i>
                </button>
              </form>
            <?php endif; ?>
        </div>
    </div>
    <?php 
        endwhile;
    else:
    ?>
    <div class="no-positions">
        <i class="fas fa-building" style="font-size: 64px; margin-bottom: 10px; opacity: 0.3;"></i><br>
        No companies added yet. Click "Add Company" above to add your first company.
    </div>
    <?php endif; ?>

  <?php else: ?>
    <!-- REGULAR TABLE VIEW FOR OTHER SECTIONS WITH LOADER -->
    <div class="table-loader" id="tableLoader">
        <div class="spinner"></div>
        <p style="color: #64748b; font-weight: 600;">Loading data...</p>
    </div>
    
    <div class="table-container" id="tableContainer">
      <table id="masterTable" class="display nowrap" style="width:100%">
        <thead>
          <tr>
            <th width="50">#</th>
            <?php if($view == 'timings'): ?>
              <th>Start Time</th>
              <th>End Time</th>
            <?php elseif($view == 'positions'): ?>
              <th>Position Title</th>
              <th>Department</th>
            <?php elseif($view == 'leave_hierarchy'): ?>
              <th>Position</th>
              <th>Department</th>
              <th>Approver 1 (Level 1)</th>
              <th>Approver 2 (Level 2)</th>
            <?php else: ?>
              <th>Location Name</th>
              <th>Latitude</th>
              <th>Longitude</th>
            <?php endif; ?>
            <th width="100">Actions</th>
          </tr>
        </thead>
        <tbody>
          <?php 
          mysqli_data_seek($result, 0);
          $count = 1;
          while($row = mysqli_fetch_assoc($result)) { 
          ?>
          <tr>
            <td><?php echo $count++; ?></td>
            
            <?php if($view == 'timings'): ?>
              <td><?php echo htmlspecialchars($row['start_time']); ?></td>
              <td><?php echo htmlspecialchars($row['end_time']); ?></td>
            <?php elseif($view == 'positions'): ?>
              <td><?php echo htmlspecialchars($row['title']); ?></td>
              <td><?php echo htmlspecialchars($row['department_name']); ?></td>
            <?php elseif($view == 'leave_hierarchy'): ?>
              <td><strong><?php echo htmlspecialchars($row['title']); ?></strong></td>
              <td><?php echo htmlspecialchars($row['department_name']); ?></td>
              <td>
                  <?php if(!empty($row['approver_1_title'])): ?>
                      <span class="badge-approver-1"><i class="fas fa-check-circle"></i> <?php echo htmlspecialchars($row['approver_1_title']); ?></span>
                  <?php else: ?>
                      <span class="badge-none">Not Set</span>
                  <?php endif; ?>
              </td>
              <td>
                  <?php if(!empty($row['approver_2_title'])): ?>
                      <span class="badge-approver-2"><i class="fas fa-check-double"></i> <?php echo htmlspecialchars($row['approver_2_title']); ?></span>
                  <?php else: ?>
                      <span class="badge-none">Not Set</span>
                  <?php endif; ?>
              </td>
            <?php else: ?>
              <td><?php echo htmlspecialchars($row['location_name']); ?></td>
              <td><code><?php echo htmlspecialchars($row['latitude']); ?></code></td>
              <td><code><?php echo htmlspecialchars($row['longitude']); ?></code></td>
            <?php endif; ?>

            <td>
              <?php if($view == 'leave_hierarchy'): ?>
                <button class="action-btn btn-icon-edit" 
                      data-id="<?php echo $row['id']; ?>"
                      data-title="<?php echo htmlspecialchars($row['title']); ?>"
                      data-app1="<?php echo $row['approver_1_id'] ?? 0; ?>"
                      data-app2="<?php echo $row['approver_2_id'] ?? 0; ?>"
                      onclick="openHierarchyModal(this)" title="Set Hierarchy">
                      <i class="fas fa-sitemap"></i>
                </button>

                <?php if($isAdmin): ?>
                  <form method="POST" style="display:inline;" onsubmit="return confirm('⚠️ Are you sure you want to clear the hierarchy for this position?');">
                    <input type="hidden" name="action" value="delete">
                    <input type="hidden" name="delete_id" value="<?php echo $row['id']; ?>">
                    <button type="submit" class="action-btn btn-icon-delete" title="Clear Hierarchy">
                        <i class="fas fa-eraser"></i>
                    </button>
                  </form>
                <?php endif; ?>

              <?php else: ?>
                  <!-- EDIT Button (Everyone) -->
                  <button class="action-btn btn-icon-edit" 
                      data-id="<?php echo $row['id']; ?>"
                      <?php if($view == 'positions'): ?>
                          data-title="<?php echo htmlspecialchars($row['title']); ?>"
                          data-dept="<?php echo $row['department_id'] ?? 0; ?>"
                      <?php elseif($view == 'locations'): ?>
                          data-loc="<?php echo htmlspecialchars($row['location_name']); ?>"
                          data-lat="<?php echo htmlspecialchars($row['latitude']); ?>"
                          data-lng="<?php echo htmlspecialchars($row['longitude']); ?>"
                      <?php elseif($view == 'timings'): ?>
                          data-start="<?php echo $row['start_time']; ?>"
                          data-end="<?php echo $row['end_time']; ?>"
                      <?php endif; ?>
                      onclick="openEditModal(this)" title="Edit">
                      <i class="fas fa-edit"></i>
                  </button>

                  <!-- DELETE Button (Abhishek & Keerthi Only) -->
                  <?php if($isAdmin): ?>
                    <form method="POST" style="display:inline;" onsubmit="return confirm('⚠️ Are you sure you want to delete this record?');">
                      <input type="hidden" name="action" value="delete">
                      <input type="hidden" name="delete_id" value="<?php echo $row['id']; ?>">
                      <button type="submit" class="action-btn btn-icon-delete" title="Delete">
                          <i class="fas fa-trash"></i>
                      </button>
                    </form>
                  <?php endif; ?>
              <?php endif; ?>
            </td>
          </tr>
          <?php } ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<!-- IMPORT MODAL -->
<div class="modal fade" id="importModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-upload"></i> Import <?php echo $current_title; ?> from CSV</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST" enctype="multipart/form-data">
        <div class="modal-body">
          <input type="hidden" name="action" value="import">
          <input type="hidden" name="import_view" value="<?php echo $view; ?>">
          
          <div class="alert alert-info">
            <strong><i class="fas fa-info-circle"></i> CSV Format Required:</strong><br>
            <?php if($view == 'departments'): ?>
              <code>Department ID, Department Name</code><br>
              <small>Example: 1, Finance Department</small>
            <?php elseif($view == 'positions'): ?>
              <code>Position ID, Position Title, Department ID, Department Name</code><br>
              <small>Example: 1, Senior Manager, 5, Finance Department</small>
            <?php elseif($view == 'locations'): ?>
              <code>Location ID, Location Name, Latitude, Longitude</code><br>
              <small>Example: 1, Main Office, 12.9716, 77.5946</small>
            <?php elseif($view == 'timings'): ?>
              <code>Timing ID, Start Time, End Time</code><br>
              <small>Example: 1, 09:00 AM, 06:00 PM</small>
            <?php elseif($view == 'companies'): ?>
              <code>Company ID, Company Name, Logo Path</code><br>
              <small>Example: 1, Abra Logistics, uploads/company_logos/logo.png</small>
            <?php endif; ?>
          </div>
          
          <div class="form-group">
            <label style="font-weight: 600;">Select CSV File <span style="color: red;">*</span></label>
            <input type="file" name="import_file" class="form-control-file" accept=".csv" required
                   style="padding: 10px; border: 2px solid #e2e8f0; border-radius: 8px;">
            <small style="color: #64748b; display: block; margin-top: 5px;">
              <i class="fas fa-info-circle"></i> The first row should contain headers and will be skipped
            </small>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-warning" style="background: #f59e0b; border: none; font-weight: 600;">
            <i class="fas fa-upload"></i> Import Data
          </button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- HIERARCHY MODAL -->
<div class="modal fade" id="hierarchyModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-users-cog"></i> Set Leave Approval Hierarchy</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST">
        <div class="modal-body">
          <input type="hidden" name="action" value="save_hierarchy">
          <input type="hidden" name="hierarchy_position_id" id="hierarchy_position_id">
          
          <div class="form-group">
              <label style="font-weight: 600;">Target Position</label>
              <input type="text" id="hierarchy_position_title" class="form-control" readonly style="background: #f1f5f9; color: #64748b;">
          </div>
          
          <div class="form-group">
              <label style="font-weight: 600; color: #065f46;"><i class="fas fa-user-check"></i> 1st Level Approver (Line Manager)</label>
              <select name="approver_1_id" id="approver_1_id" class="form-control">
                  <option value="0">-- Select Approver 1 (None) --</option>
                  <!-- Populated via JS -->
              </select>
          </div>
          
          <div class="form-group">
              <label style="font-weight: 600; color: #92400e;"><i class="fas fa-user-check"></i> 2nd Level Approver (Optional)</label>
              <select name="approver_2_id" id="approver_2_id" class="form-control">
                  <option value="0">-- Select Approver 2 (None) --</option>
                  <!-- Populated via JS -->
              </select>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-success" style="background: #10b981; border: none; font-weight: 600;">Save Hierarchy</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- ADD MODAL -->
<div class="modal fade" id="addModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-plus-circle"></i> <?php echo $current_btn_text; ?></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST" enctype="multipart/form-data" id="addForm">
        <div class="modal-body">
          <input type="hidden" name="action" value="add">
          
          <?php if($view == 'departments'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">What would you like to add?</label>
                <select class="form-control" id="addType" onchange="toggleAddForm()">
                    <option value="department">New Department</option>
                    <option value="position">New Position to Department</option>
                </select>
            </div>
            
            <div id="departmentForm">
                <div class="form-group">
                    <label style="font-weight: 600;">Department Name</label>
                    <input type="text" name="name" id="dept_name" class="form-control" placeholder="e.g. Finance Department">
                </div>
            </div>
            
            <div id="positionForm" style="display: none;">
                <div class="form-group">
                    <label style="font-weight: 600;">Select Department <span style="color: red;">*</span></label>
                    <select name="department_id" id="pos_dept_id" class="form-control">
                        <option value="">-- Select Department --</option>
                        <?php 
                        mysqli_data_seek($departments_dropdown, 0);
                        while($dept = mysqli_fetch_assoc($departments_dropdown)) {
                            echo '<option value="'.$dept['id'].'">'.htmlspecialchars($dept['name']).'</option>';
                        }
                        ?>
                    </select>
                </div>
                <div class="form-group">
                    <label style="font-weight: 600;">Position Title</label>
                    <input type="text" name="title" id="pos_title" class="form-control" placeholder="e.g. Senior Manager">
                </div>
            </div>
          <?php elseif($view == 'positions'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">Select Department <span style="color: red;">*</span></label>
                <select name="department_id" class="form-control" required>
                    <option value="">-- Select Department --</option>
                    <?php 
                    mysqli_data_seek($departments_dropdown, 0);
                    while($dept = mysqli_fetch_assoc($departments_dropdown)) {
                        echo '<option value="'.$dept['id'].'">'.htmlspecialchars($dept['name']).'</option>';
                    }
                    ?>
                </select>
            </div>
            <div class="form-group">
                <label style="font-weight: 600;">Position Title</label>
                <input type="text" name="title" class="form-control" required placeholder="e.g. Senior Manager">
            </div>
          <?php elseif($view == 'locations'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">Work Location Name</label>
                <input type="text" name="location_name" class="form-control" required placeholder="e.g. Warehouse A">
            </div>
            <div class="row">
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Latitude</label>
                    <input type="text" name="latitude" class="form-control" placeholder="e.g. 12.9716">
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Longitude</label>
                    <input type="text" name="longitude" class="form-control" placeholder="e.g. 77.5946">
                </div>
            </div>
          <?php elseif($view == 'timings'): ?>
            <div class="row">
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Start Time</label>
                    <input type="text" name="start_time" class="form-control" required placeholder="e.g. 09:00 AM">
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">End Time</label>
                    <input type="text" name="end_time" class="form-control" required placeholder="e.g. 06:00 PM">
                </div>
            </div>
          <?php elseif($view == 'companies'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">Company Name <span style="color: red;">*</span></label>
                <input type="text" name="company_name" class="form-control" required placeholder="e.g. Abra Logistics">
            </div>
            <div class="form-group">
                <label style="font-weight: 600;">Company Logo (Optional)</label>
                <input type="file" name="company_logo" id="company_logo" class="form-control-file" 
                       accept="image/jpeg,image/jpg,image/png,image/gif,image/webp" 
                       onchange="validateLogoSize(this)"
                       style="padding: 10px; border: 2px solid #e2e8f0; border-radius: 8px;">
                <small style="color: #64748b; display: block; margin-top: 5px;">
                    <i class="fas fa-info-circle"></i> Maximum file size: <?php echo MAX_LOGO_SIZE_MB; ?> MB | Formats: JPG, PNG, GIF, WEBP
                </small>
            </div>
          <?php endif; ?>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-success" style="background: #10b981; border: none; font-weight: 600;">Save</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL FOR DEPARTMENTS -->
<div class="modal fade" id="editDeptModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit"></i> Edit Department</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST">
        <div class="modal-body">
          <input type="hidden" name="action" value="edit">
          <input type="hidden" name="edit_id" id="edit_dept_id">
          <div class="form-group">
              <label style="font-weight: 600;">Department Name</label>
              <input type="text" name="edit_name" id="edit_dept_name" class="form-control" required>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-primary" style="background: #1e3a8a; border: none; font-weight: 600;">Update</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL FOR POSITIONS -->
<div class="modal fade" id="editPosModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit"></i> Edit Position</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST">
        <div class="modal-body">
          <input type="hidden" name="action" value="edit">
          <input type="hidden" name="edit_id" id="edit_pos_id">
          <div class="form-group">
              <label style="font-weight: 600;">Select Department <span style="color: red;">*</span></label>
              <select name="edit_department_id" id="edit_pos_dept" class="form-control" required>
                  <option value="">-- Select Department --</option>
                  <?php 
                  mysqli_data_seek($departments_dropdown, 0);
                  while($dept = mysqli_fetch_assoc($departments_dropdown)) {
                      echo '<option value="'.$dept['id'].'">'.htmlspecialchars($dept['name']).'</option>';
                  }
                  ?>
              </select>
          </div>
          <div class="form-group">
              <label style="font-weight: 600;">Position Title</label>
              <input type="text" name="edit_title" id="edit_pos_title" class="form-control" required>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-primary" style="background: #1e3a8a; border: none; font-weight: 600;">Update</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL FOR COMPANIES -->
<div class="modal fade" id="editCompanyModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit"></i> Edit Company</h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST" enctype="multipart/form-data" id="editCompanyForm">
        <div class="modal-body">
          <input type="hidden" name="action" value="edit">
          <input type="hidden" name="edit_id" id="edit_company_id">
          <div class="form-group">
              <label style="font-weight: 600;">Company Name <span style="color: red;">*</span></label>
              <input type="text" name="edit_company_name" id="edit_company_name" class="form-control" required>
          </div>
          <div class="form-group">
              <label style="font-weight: 600;">Current Logo</label>
              <div id="current_logo_preview" style="margin-bottom: 10px;"></div>
          </div>
          <div class="form-group">
              <label style="font-weight: 600;">Replace Logo (Optional)</label>
              <input type="file" name="edit_company_logo" id="edit_company_logo" class="form-control-file" 
                     accept="image/jpeg,image/jpg,image/png,image/gif,image/webp"
                     onchange="validateLogoSize(this)"
                     style="padding: 10px; border: 2px solid #e2e8f0; border-radius: 8px;">
              <small style="color: #64748b; display: block; margin-top: 5px;">
                  <i class="fas fa-info-circle"></i> Leave empty to keep current logo | Max: <?php echo MAX_LOGO_SIZE_MB; ?> MB
              </small>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-primary" style="background: #1e3a8a; border: none; font-weight: 600;">Update</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- EDIT MODAL FOR OTHER VIEWS -->
<div class="modal fade" id="editModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title"><i class="fas fa-edit"></i> Edit <?php echo substr($current_title, 0, -1); ?></h5>
        <button type="button" class="close" data-dismiss="modal">&times;</button>
      </div>
      <form method="POST">
        <div class="modal-body">
          <input type="hidden" name="action" value="edit">
          <input type="hidden" name="edit_id" id="edit_id">
          
          <?php if($view == 'locations'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">Work Location Name</label>
                <input type="text" name="edit_location" id="edit_location" class="form-control" required>
            </div>
            <div class="row">
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Latitude</label>
                    <input type="text" name="edit_latitude" id="edit_latitude" class="form-control">
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Longitude</label>
                    <input type="text" name="edit_longitude" id="edit_longitude" class="form-control">
                </div>
            </div>
          <?php elseif($view == 'timings'): ?>
            <div class="row">
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">Start Time</label>
                    <input type="text" name="edit_start" id="edit_start" class="form-control" required>
                </div>
                <div class="col-md-6 form-group">
                    <label style="font-weight: 600;">End Time</label>
                    <input type="text" name="edit_end" id="edit_end" class="form-control" required>
                </div>
            </div>
          <?php elseif($view == 'positions'): ?>
            <div class="form-group">
                <label style="font-weight: 600;">Select Department <span style="color: red;">*</span></label>
                <select name="edit_department_id" id="edit_department_id" class="form-control" required>
                    <option value="">-- Select Department --</option>
                    <?php 
                    mysqli_data_seek($departments_dropdown, 0);
                    while($dept = mysqli_fetch_assoc($departments_dropdown)) {
                        echo '<option value="'.$dept['id'].'">'.htmlspecialchars($dept['name']).'</option>';
                    }
                    ?>
                </select>
            </div>
            <div class="form-group">
                <label style="font-weight: 600;">Position Title</label>
                <input type="text" name="edit_title" id="edit_title" class="form-control" required>
            </div>
          <?php endif; ?>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
          <button type="submit" class="btn btn-primary" style="background: #1e3a8a; border: none; font-weight: 600;">Update</button>
        </div>
      </form>
    </div>
  </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>

<script>
var MAX_LOGO_SIZE = <?php echo MAX_LOGO_SIZE_BYTES; ?>;
var MAX_LOGO_SIZE_MB = <?php echo MAX_LOGO_SIZE_MB; ?>;

// Store All Positions for Hierarchy Dropdowns
<?php if($view == 'leave_hierarchy'): ?>
var allPositions = <?php echo json_encode($all_positions); ?>;
<?php endif; ?>

$(document).ready(function() {
    <?php if($view != 'departments' && $view != 'companies'): ?>
    var table = $('#masterTable').DataTable({
        pageLength: 25,
        lengthMenu: [[25, 50, 100, -1], [25, 50, 100, "All"]],
        language: {
            search: "Search:",
            paginate: { next: 'Next', previous: 'Prev' }
        },
        initComplete: function() {
            $('#tableLoader').fadeOut(200, function() {
                $('#tableContainer').addClass('loaded').hide().fadeIn(300);
            });
        }
    });
    <?php endif; ?>

    setTimeout(function() { $('.alert').fadeOut('slow'); }, 5000);
});

function toggleAddForm() {
    var addType = $('#addType').val();
    if(addType == 'department') {
        $('#departmentForm').show();
        $('#positionForm').hide();
        $('#pos_dept_id').removeAttr('required');
        $('#pos_title').removeAttr('required');
        $('#dept_name').attr('required', 'required');
    } else {
        $('#departmentForm').hide();
        $('#positionForm').show();
        $('#dept_name').removeAttr('required');
        $('#pos_dept_id').attr('required', 'required');
        $('#pos_title').attr('required', 'required');
    }
}

function validateLogoSize(input) {
    if (input.files && input.files[0]) {
        var fileSize = input.files[0].size;
        var fileName = input.files[0].name;
        
        if (fileSize > MAX_LOGO_SIZE) {
            var actualSizeMB = (fileSize / (1024 * 1024)).toFixed(2);
            alert('⚠️ LOGO FILE TOO LARGE!\n\n' +
                  'File: ' + fileName + '\n' +
                  'Size: ' + actualSizeMB + ' MB\n' +
                  'Maximum allowed: ' + MAX_LOGO_SIZE_MB + ' MB\n\n' +
                  'Please compress the image and try again.');
            input.value = '';
            return false;
        }
    }
    return true;
}

function toggleDepartment(deptId) {
    var container = $('#positions_' + deptId);
    var icon = $('#icon_' + deptId);
    container.toggleClass('show');
    icon.toggleClass('expanded');
}

function openEditDeptModal(btn) {
    var id = $(btn).data('id');
    var name = $(btn).data('name');
    $('#edit_dept_id').val(id);
    $('#edit_dept_name').val(name);
    $('#editDeptModal').modal('show');
}

function openEditPosModal(btn) {
    var id = $(btn).data('id');
    var title = $(btn).data('title');
    var dept = $(btn).data('dept');
    $('#edit_pos_id').val(id);
    $('#edit_pos_title').val(title);
    $('#edit_pos_dept').val(dept);
    $('#editPosModal').modal('show');
}

function openEditCompanyModal(btn) {
    var id = $(btn).data('id');
    var name = $(btn).data('name');
    var logo = $(btn).data('logo');
    $('#edit_company_id').val(id);
    $('#edit_company_name').val(name);
    var logoPreview = $('#current_logo_preview');
    if(logo && logo != '') {
        logoPreview.html('<img src="' + logo + '" style="width: 100px; height: 100px; object-fit: contain; border: 2px solid #e2e8f0; border-radius: 8px; padding: 5px;">');
    } else {
        logoPreview.html('<p style="color: #94a3b8; font-style: italic;">No logo uploaded</p>');
    }
    $('#editCompanyModal').modal('show');
}

function openEditModal(btn) {
    var id = $(btn).data('id');
    $('#edit_id').val(id);
    <?php if($view == 'positions'): ?>
        $('#edit_title').val($(btn).data('title'));
        $('#edit_department_id').val($(btn).data('dept'));
    <?php elseif($view == 'locations'): ?>
        $('#edit_location').val($(btn).data('loc'));
        $('#edit_latitude').val($(btn).data('lat'));
        $('#edit_longitude').val($(btn).data('lng'));
    <?php elseif($view == 'timings'): ?>
        $('#edit_start').val($(btn).data('start'));
        $('#edit_end').val($(btn).data('end'));
    <?php endif; ?>
    $('#editModal').modal('show');
}

function openHierarchyModal(btn) {
    var posId = $(btn).data('id');
    var posTitle = $(btn).data('title');
    var app1 = $(btn).data('app1');
    var app2 = $(btn).data('app2');

    $('#hierarchy_position_id').val(posId);
    $('#hierarchy_position_title').val(posTitle);

    var optionsHtml = '<option value="0">-- No Approver --</option>';
    
    // Populate dropdown, excluding the current position to prevent self-approval loop
    allPositions.forEach(function(pos) {
        if(pos.id != posId) {
            optionsHtml += `<option value="${pos.id}">${pos.title} (${pos.dept_name})</option>`;
        }
    });

    $('#approver_1_id').html(optionsHtml);
    $('#approver_2_id').html(optionsHtml);

    // Set selected values
    $('#approver_1_id').val(app1 ? app1 : 0);
    $('#approver_2_id').val(app2 ? app2 : 0);

    $('#hierarchyModal').modal('show');
}
</script>
</body>
</html>