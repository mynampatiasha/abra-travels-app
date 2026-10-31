<?php
	
	require_once '/path/to/vendor/autoload.php'; // Loads the library
	use Twilio\Rest\Client;
	
	$sid = "ACf7fc0a3b324231720e12d57f7e7679e5";
	$token = "489846d303ec3aeb42fa2405b9221f03";
	$from = "+15595127910";
	$client = new Client($sid, $token);
	$telefono = "+573116173306";
	$mensaje = $client->account->messages->create(array(
		"From" => $from,
		"To" => $telefono,
		"Body" => "Numero tracking 100001"
			));
	echo "Resultado=" . $mensaje->sid;
	
?>