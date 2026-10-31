<?php
    error_reporting(E_ALL);
    ini_set('display_errors', 1);

    session_start();
    require_once('../../database.php');
    require_once('../../database-settings.php');

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['tracking_no'])) {
    $tracking_no = mysqli_real_escape_string($dbConn, $_POST['tracking_no']);

    // Fetch from inscan table
    $inscan_query = "SELECT inscan_datetime, status AS inscan_status FROM inscan WHERE tracking_no = '$tracking_no'";
    $inscan_result = mysqli_query($dbConn, $inscan_query);
    $inscan_data = mysqli_fetch_assoc($inscan_result);

    // Fetch from outscan table
    $outscan_query = "SELECT outscan_datetime, status AS outscan_status FROM outscan WHERE tracking_no = '$tracking_no'";
    $outscan_result = mysqli_query($dbConn, $outscan_query);
    $outscan_data = mysqli_fetch_assoc($outscan_result);

    if ($inscan_data || $outscan_data) {
        echo json_encode([
            'success' => true,
            'inscan_datetime' => $inscan_data['inscan_datetime'] ?? null,
            'inscan_status' => $inscan_data['inscan_status'] ?? null,
            'outscan_datetime' => $outscan_data['outscan_datetime'] ?? null,
            'outscan_status' => $outscan_data['outscan_status'] ?? null,
        ]);
    } else {
        echo json_encode(['success' => false, 'message' => 'No data found for this tracking number.']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Invalid request.']);
}
?>
