<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');
require_once('../../database-settings.php');


// Get form data
$client_id = isset($_POST['client_id']) ? $_POST['client_id'] : '';
$provisions = isset($_POST['provisions']) ? $_POST['provisions'] : [];

if (empty($client_id)) {
    die("Client ID is required.");
}

// Define provision fields
$provisionFields = [
    'display_products',
    'storage_fulfillment',
    'last_mile',
    'road_freight',
    'air_freight',
    'sea_freight',
    'rail_freight',
    'domestic',
    'international',
    'import',
    'export',
];

// Check if the client ID exists
$checkQuery = "SELECT * FROM tbl_clients_provisions WHERE client_id = '$client_id'";
$checkResult = mysqli_query($dbConn, $checkQuery);

if (mysqli_num_rows($checkResult) > 0) {
    // Build the update query if the record exists
    $updateQuery = "UPDATE tbl_clients_provisions SET ";
    $updates = [];
    foreach ($provisionFields as $field) {
        $value = isset($provisions[$field]) ? 1 : 0;
        $updates[] = "$field = $value";
    }
    $updateQuery .= implode(', ', $updates);
    $updateQuery .= " WHERE client_id = '$client_id'";

    if (mysqli_query($dbConn, $updateQuery)) {
        echo "<script type=\"text/javascript\">
			alert(\"Updatd Successfully!\");
			window.location = \"../../management-client-az.php\"
		</script>";
    } else {
        echo "Error updating provisions: " . mysqli_error($dbConn);
    }
} else {
    // Insert a new record if the client ID does not exist
    $fields = implode(', ', array_merge(['client_id'], $provisionFields));
    $values = ["'$client_id'"];
    foreach ($provisionFields as $field) {
        $values[] = isset($provisions[$field]) ? 1 : 0;
    }
    $values = implode(', ', $values);

    $insertQuery = "INSERT INTO tbl_clients_provisions ($fields) VALUES ($values)";
    if (mysqli_query($dbConn, $insertQuery)) {
        echo "<script type=\"text/javascript\">
			alert(\"Updatd Successfully!\");
			window.location = \"../../management-client-az.php\"
		</script>";
    } else {
        echo "Error inserting provisions: " . mysqli_error($dbConn);
    }
}
?>
