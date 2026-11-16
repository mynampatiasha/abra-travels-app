<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

session_start();
require_once('../../database.php');
require_once('../../database-settings.php');

header('Content-Type: application/json'); // Set response to JSON

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);

    if (isset($input['action']) && $input['action'] === 'submit' && isset($input['data']) && is_array($input['data'])) {
        $data = $input['data'];
        $inscan_values = [];
        $courier_track_values = [];

        mysqli_begin_transaction($dbConn); 
        
        try {
            foreach ($data as $row) {
                $tracking_no = mysqli_real_escape_string($dbConn, $row['tracking_no']);
                $origin = mysqli_real_escape_string($dbConn, $row['origin']);
                $destination = mysqli_real_escape_string($dbConn, $row['destination']);
                $scanned_by = mysqli_real_escape_string($dbConn, $row['scanned_by']);
                $inscan_datetime = mysqli_real_escape_string($dbConn, $row['inscan_datetime']);
                $scan_location = mysqli_real_escape_string($dbConn, $row['scan_location']);
                $status = mysqli_real_escape_string($dbConn, $row['status']);
                $delivery_date = mysqli_real_escape_string($dbConn, $row['delivery_date']);

                // Fetch reference_no and delivery_aggregator from courier table
                $courierDetailsQuery = "SELECT cid, cons_no, letra, reference_no, delivery_aggregator, ship_name, phone, correo, user FROM courier WHERE tracking = '$tracking_no' LIMIT 1";
                $result = mysqli_query($dbConn, $courierDetailsQuery);

                if ($result && mysqli_num_rows($result) > 0) {
                    $courierData = mysqli_fetch_assoc($result);
                    
                    $reference_no = mysqli_real_escape_string($dbConn, $courierData['reference_no']);
                    $delivery_aggregator = mysqli_real_escape_string($dbConn, $courierData['delivery_aggregator']);
                    $cid = $courierData['cid'];
                    $cons_no = $courierData['cons_no'];
                    $letra = $courierData['letra'];
                    $ship_name = mysqli_real_escape_string($dbConn, $courierData['ship_name']);
                    $phone = mysqli_real_escape_string($dbConn, $courierData['phone']);
                    $correo = mysqli_real_escape_string($dbConn, $courierData['correo']);
                    $user = mysqli_real_escape_string($dbConn, $courierData['user']);
                    
                    // Insert into inscan with reference_no and delivery_aggregator
                    $inscan_values[] = "('$tracking_no', '$reference_no', '$delivery_aggregator', '$origin', '$destination', '$scanned_by', '$inscan_datetime', '$scan_location', '$status', '$delivery_date')";

                    // Insert into courier_track
                    $comments = 'Package has been scanned at facility: ' . $scan_location;
                    $new_status = 'Inscan';
                    $bk_time = date("Y-m-d H:i:s");

                    $courier_track_values[] = "('$cid', '$cons_no', '$letra', '$scan_location', '$new_status', '$comments', '$bk_time', '$ship_name', '$phone', '$correo', '$user')";
                    // ✅ Correct: Update courier inside the loop
$updateCourier = "UPDATE courier 
    SET status = 'Inscan', ciudad = '$origin', city1 = '$destination' 
    WHERE tracking = '$tracking_no'";
if (!mysqli_query($dbConn, $updateCourier)) {
    throw new Exception("Error updating courier for $tracking_no: " . mysqli_error($dbConn));
}

                } else {
                    throw new Exception("Tracking number $tracking_no not found in the courier table.");
                }
            }

            // Insert into inscan
            if (!empty($inscan_values)) {
                $query = "INSERT INTO inscan (tracking_no, reference_no, delivery_aggregator, origin, destination, scanned_by, inscan_datetime, scan_location, status, delivery_date) VALUES " . implode(", ", $inscan_values);
                if (!mysqli_query($dbConn, $query)) {
                    throw new Exception("Error inserting into inscan: " . mysqli_error($dbConn));
                }
            }

            // Insert into courier_track
            if (!empty($courier_track_values)) {
                $courierTrackQuery = "INSERT INTO courier_track (cid, cons_no, letra, pick_time, status, comments, bk_time, ship_name, phone, correo, user) VALUES " . implode(", ", $courier_track_values);
                if (!mysqli_query($dbConn, $courierTrackQuery)) {
                    throw new Exception("Error inserting into courier_track: " . mysqli_error($dbConn));
                }
            }

            mysqli_commit($dbConn);
            echo json_encode(['success' => true, 'message' => 'Records inserted and all statuses updated successfully.']);
        } catch (Exception $e) {
            mysqli_rollback($dbConn);
            http_response_code(500);
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
    } else {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Invalid data format.']);
    }
} else {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Invalid request method.']);
}
?>
