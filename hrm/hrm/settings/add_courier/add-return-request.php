<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database.php');

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $tracking = $_POST['tracking'];
    $reason = $_POST['reason'];
    $status = $_POST['status'];
    $filed_by = $_POST['filed_by'];
    
    $query = "INSERT INTO return_requests (tracking, reason, status, filed_by) VALUES ('$tracking', '$reason', '$status', '$filed_by')";
    
    if (mysqli_query($dbConn, $query)) {
        echo "<script type=\"text/javascript\">
						alert(\"New return request added successfully.\");
						window.location = \"../../return-requests.php\"
					</script>";
    } else {
        echo "Error: " . $query . "<br>" . mysqli_error($dbConn);
    }
}
	
    
?>
