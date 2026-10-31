<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	
	
 
	if ($_SERVER["REQUEST_METHOD"] == "POST") {
		// Sanitize and retrieve form data
		$id = $_POST['id'];
		$employee_id = $_POST['employee_id'];
		$amount = $_POST['amount'];
		$pay_date = $_POST['pay_date'];
		$comment = $_POST['comment'];
		
		// Update query
		$resultado = $con->query("UPDATE hr_payroll 
				SET employee_id = '$employee_id', amount = '$amount', pay_date = '$pay_date', comment = '$comment' 
				WHERE id = '$id'");


			echo "<script type=\"text/javascript\">
						alert(\"Payroll updated successfully.\");
						window.location = \"../../hr-payroll.php\"
					</script>"; 
		
	}
    
    
?>