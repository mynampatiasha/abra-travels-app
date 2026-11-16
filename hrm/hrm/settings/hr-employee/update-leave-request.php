<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	
	$id = $_POST['id'];
	$employee_id = $_POST['employee_id'];
		$start_date = $_POST['start_date'];
		$end_date = $_POST['end_date'];
		$reason = $_POST['reason'];
		$status = $_POST['status'];
	
		
	
	$resultado = $con->query("UPDATE hr_leaves SET employee_id='$employee_id', start_date='$start_date', end_date='$end_date', reason='$reason', status='$status' WHERE id = '$id'");


	
	echo "<script type=\"text/javascript\">
						alert(\"Leave Request Updated Successfully!.\");
						window.location = \"../../hr-leave-requests.php\"
					</script>"; 
 
	
    
    
?>