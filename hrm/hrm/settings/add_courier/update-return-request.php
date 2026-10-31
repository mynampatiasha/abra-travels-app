<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	

	$id = $_POST['id'];
	$tracking = $_POST['tracking'];
    $reason = $_POST['reason'];
    $status = $_POST['status'];
    $filed_by = $_POST['filed_by'];
	
	
	$resultado = $con->query("UPDATE return_requests SET tracking = '$tracking', reason = '$reason', status = '$status', filed_by = '$filed_by', updated_at = NOW() WHERE id = $id");


	echo "<script type=\"text/javascript\">
						alert(\"Return request updated successfully.\");
						window.location = \"../../return-requests.php\"
					</script>"; 
	
    
    
?>