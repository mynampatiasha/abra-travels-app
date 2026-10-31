<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

header('Content-Type: application/json'); // Set response to JSON

if ($_POST['action'] === 'update') {
    $storage_id = $_POST['storage_id']; // Make sure you're using 'storage_id' for updates

    // Define only the editable fields
    $editable_fields = ['inventory_count', 'variation', 'selling_price', 'special_notes', 'remarks'];

    $updates = [];
    foreach ($editable_fields as $field) {
        if (isset($_POST[$field])) {
            $value = mysqli_real_escape_string($dbConn, $_POST[$field]);
            $updates[] = "$field = '$value'";
        }
    }

    if (!empty($updates)) {
        $update_query = "UPDATE storage SET " . implode(', ', $updates) . " WHERE item_code = '$storage_id'";

        if (mysqli_query($dbConn, $update_query)) {
            echo json_encode(['success' => true, 'message' => 'Record updated successfully.']);
        } else {
            echo json_encode(['success' => false, 'message' => 'Database error: ' . mysqli_error($dbConn)]);
        }
    } else {
        echo json_encode(['success' => false, 'message' => 'No fields to update.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid action.']);
}
?>
