<?php
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	
	$name = $_POST['name'];
	$id = $_POST['id'];
	
		
	
	$resultado = $con->query("UPDATE hr_departments SET name='$name' WHERE id = '$id'");


	
	echo "<script type=\"text/javascript\">
						alert(\"Info Updated Successfully!.\");
						window.location = \"../../hr-departments-list.php\"
					</script>"; 
 
	
    
    
?>