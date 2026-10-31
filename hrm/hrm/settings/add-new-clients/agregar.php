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

require_once('../../database.php');
require_once('../../funciones.php');

	$locker = $_POST['locker'];
	$name = $_POST['name'];
	$cc = $_POST['cc'];
	$company = $_POST['company'];
	$email = $_POST['email'];
	$code_phone = $_POST['code_phone'];
	$phone = $_POST['phone'];
	$code_phone1 = $_POST['code_phone1'];
	$telefono = $_POST['telefono'];
	$address=$_POST['address'];
	$country = countries($_POST['country']);
	$department = department($_POST['department']);
	$state = city($_POST['state']);
	$iso = $_POST['iso'];
	$zipcode = $_POST['zipcode'];
	$lang = $_POST['lang'];
	$pass = $_POST['password'];
	$pwdmd5 = md5(PASS_SALT.$pass);
	$imagen = $_POST['imagen'];
	$tipo_imagen = $_POST['tipo_imagen'];
	$client_id = $_POST['client_id'];

	
	// verificamos si esta marcado el check box activo
	if(isset($_POST['estado']))
	$estado = $_POST['estado'];
	else
	$estado = 0;

	#
	## Cargo la imagen por defecto
	$tipo_imagen = "image/png";
	$url = APP_URL."/img/user_image.png";

	$imagen = imagecreatefromstring(file_get_contents($url));
	imagealphablending($imagen, true);
	imagesavealpha($imagen, true);

	ob_start();
	imagepng($imagen);
	$string = ob_get_contents();
	ob_end_clean();
	
	$pa=mysqli_query($dbConn, "SELECT MAX(locker)as maximo FROM tbl_clients");				
	if($row=mysqli_fetch_array($pa)){
		if($row['maximo']==NULL){
			$locker='100001';
		}else{
			$locker=$row['maximo']+1;
		}
	}

	$sql1 =mysqli_query($dbConn, "SELECT email FROM tbl_clients WHERE email='$email' AND name='$name'");
			if($row=mysqli_fetch_array($sql1)){							
				 echo "<script type=\"text/javascript\">
						alert(\"Email $email are already registered in the database, please enter different data, thank you.\");
						window.location = \"../../management-client.php\"
					</script>"; 							
			}else{
				
				$sql1="INSERT INTO tbl_clients (client_id,locker,name,cc,address,email, phone, telefono, password, company, country, department, state, iso, zipcode,lang, estado,date,imagen,tipo_imagen) VALUES 	
				('$client_id','$locker','$name','$cc','$address', '$email', '$code_phone$phone', '$code_phone1$telefono', '$pwdmd5', '$company', '$country', '$department', '$state', '$iso', '$zipcode', '$lang', '$estado',curdate(), '".mysqli_real_escape_string($dbConn, $string)."', '$tipo_imagen')";
			}
	dbQuery($sql1);
	
	echo "<script type=\"text/javascript\">
						alert(\"Thank you very much for registering.\");
						window.location = \"../../management-client.php\"
					</script>"; 


?>