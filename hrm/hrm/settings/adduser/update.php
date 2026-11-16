<?php
// *************************************************************************
// *                                                                       *
// * DEPRIXA -  logistics Worldwide Software                               *
// * Copyright (c) JAOMWEB. All Rights Reserved                            *
// *                                                                       *
// *************************************************************************
// *                                                                       *
// * Email: osorio2380@yahoo.es                                            *
// * Website: http://www.jaom.info                                         *
// *                                                                       *
// *************************************************************************
// *                                                                       *
// * This software is furnished under a license and may be used and copied *
// * only  in  accordance  with  the  terms  of such  license and with the *
// * inclusion of the above copyright notice.                              *
// * If you Purchased from Codecanyon, Please read the full License from   *
// * here- http://codecanyon.net/licenses/standard                         *
// *                                                                       *
// *************************************************************************
 
error_reporting(E_ERROR | E_WARNING | E_PARSE);
session_start();
require_once('../../database-settings.php');
$con = conexion();	
		
	$cid=$_POST['cid'];
	$name_parson = $_POST['name_parson'];
	$name = $_POST['name'];
	$email = $_POST['email'];
	$phone = $_POST['phone'];
	$estado = $_POST['estado'];	
		
	  $resultado = $con->query("UPDATE manager_user SET name_parson = '$name_parson', name='$name', email='$email', phone='$phone', estado='$estado'
			 WHERE cid = '$cid'");
	
	echo "<script type=\"text/javascript\">
			alert(\"Many thank you for your update.\");
			window.location = \"../../add-new-users.php\"
		 </script>"; 
 
	
    
?>