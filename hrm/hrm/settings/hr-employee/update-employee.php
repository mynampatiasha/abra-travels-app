<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	
	$name = $_POST['name'];
	$email = $_POST['email'];
	$phone = $_POST['phone'];
	$department = $_POST['department'];
	$hire_date = $_POST['hire_date'];
	$salary = $_POST['salary'];
	$status = $_POST['status'];
	$id = $_POST['id'];
	
		
	
	$resultado = $con->query("UPDATE hr_employees SET name='$name', email='$email', phone='$phone', department='$department', hire_date='$hire_date', salary='$salary', status='$status' WHERE id = '$id'");


	
	echo "<script type=\"text/javascript\">
						alert(\"Info Updated Successfully!.\");
						window.location = \"../../hr-employees-list.php\"
					</script>"; 
 
	
    
    
?>