<?php
// =========================================================================
// GET EMPLOYEE DOCUMENTS - AJAX Loader
// =========================================================================

error_reporting(E_ALL);
ini_set('display_errors', 1);
session_start();
require_once('database.php');
require_once('database-settings.php');

$con = conexion();
if (!$con) {
    die("Database connection failed");
}

// Admin Check
$currentUserName = isset($_SESSION['user_name']) ? trim($_SESSION['user_name']) : '';
$authorized_admin_names = array('Abishek Veeraswamy', 'Abishek', 'abishek');

$isAdmin = false;
foreach($authorized_admin_names as $admin_name) {
    if(stripos($currentUserName, $admin_name) !== false || stripos($admin_name, $currentUserName) !== false) {
        $isAdmin = true;
        break;
    }
}

if (!isset($_GET['employee_id'])) {
    echo '<div class="alert alert-danger">Invalid request</div>';
    exit;
}

$employee_id = mysqli_real_escape_string($con, $_GET['employee_id']);

// Fetch all documents for this employee
$docs_query = "SELECT * FROM hr_employee_documents WHERE employee_id = '$employee_id' ORDER BY uploaded_at DESC";
$docs_result = mysqli_query($con, $docs_query);

if (!$docs_result) {
    echo '<div class="alert alert-danger">Error loading documents: ' . mysqli_error($con) . '</div>';
    exit;
}

$doc_count = mysqli_num_rows($docs_result);

if ($doc_count == 0) {
    echo '<div class="no-documents">
            <i class="fas fa-folder-open"></i>
            <h5 style="font-weight: 700; color: #64748b; margin-top: 16px;">No Documents Found</h5>
            <p style="color: #94a3b8; margin-top: 8px;">This employee has no uploaded documents yet.</p>
          </div>';
    exit;
}

echo '<div class="document-list">';

while ($doc = mysqli_fetch_assoc($docs_result)) {
    $doc_id = $doc['id'];
    $doc_type = htmlspecialchars($doc['document_type']);
    $filename = htmlspecialchars($doc['filename']);
    $filepath = htmlspecialchars($doc['filepath']);
    $uploaded_at = date('d-M-Y h:i A', strtotime($doc['uploaded_at']));
    
    // Determine file icon
    $file_ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
    $icon = 'fa-file';
    $icon_color = '#64748b';
    
    if (in_array($file_ext, ['pdf'])) {
        $icon = 'fa-file-pdf';
        $icon_color = '#dc2626';
    } elseif (in_array($file_ext, ['doc', 'docx'])) {
        $icon = 'fa-file-word';
        $icon_color = '#2563eb';
    } elseif (in_array($file_ext, ['jpg', 'jpeg', 'png', 'gif', 'webp'])) {
        $icon = 'fa-file-image';
        $icon_color = '#8b5cf6';
    } elseif (in_array($file_ext, ['xls', 'xlsx'])) {
        $icon = 'fa-file-excel';
        $icon_color = '#059669';
    }
    
    echo '<div class="document-item">
            <div style="display: flex; align-items: center; gap: 15px; flex: 1;">
              <i class="fas ' . $icon . '" style="font-size: 32px; color: ' . $icon_color . ';"></i>
              <div class="doc-info">
                <div class="doc-type">' . $doc_type . '</div>
                <div class="doc-filename"><i class="fas fa-file"></i> ' . $filename . '</div>
                <div class="doc-date"><i class="far fa-clock"></i> Uploaded: ' . $uploaded_at . '</div>
              </div>
            </div>
            <div class="doc-actions">
              <a href="' . $filepath . '" download class="btn-download" title="Download">
                <i class="fas fa-download"></i> Download
              </a>';
    
    if ($isAdmin) {
        echo '<button onclick="deleteDocument(' . $doc_id . ', \'' . $employee_id . '\', \'Employee\'); return false;" 
                      class="btn-delete-doc" title="Delete (Admin Only)">
                <i class="fas fa-trash"></i> Delete
              </button>';
    }
    
    echo '    </div>
          </div>';
}

echo '</div>';

echo '<div style="margin-top: 20px; padding: 15px; background: #f0f9ff; border-radius: 8px; border-left: 4px solid #3b82f6;">
        <strong style="color: #1e40af;"><i class="fas fa-info-circle"></i> Total Documents:</strong> 
        <span style="color: #1e40af; font-weight: 700;">' . $doc_count . '</span>
      </div>';
?>