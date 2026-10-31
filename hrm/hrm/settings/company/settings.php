<?php
	error_reporting(E_ERROR | E_WARNING | E_PARSE);
	session_start();
	require_once('../../database-settings.php');
	require_once('../../database.php');
	require '../../requirelanguage.php';
	require '../../css/GUMP/gump.class.php';
	
		$cname = mysqli_real_escape_string($dbConn, $_POST['cname']);
        $nit = mysqli_real_escape_string($dbConn, $_POST['nit']);
        $cemail = mysqli_real_escape_string($dbConn, $_POST['cemail']);
        $cphone = mysqli_real_escape_string($dbConn, $_POST['cphone']);
        $caddress = mysqli_real_escape_string($dbConn, $_POST['caddress']);
        $country = mysqli_real_escape_string($dbConn, $_POST['country']);
        $city = mysqli_real_escape_string($dbConn, $_POST['city']);
        $website = mysqli_real_escape_string($dbConn, $_POST['website']);
        $footer_website = mysqli_real_escape_string($dbConn, $_POST['footer_website']);
        $currency = mysqli_real_escape_string($dbConn, $_POST['currency']);
        $measure = mysqli_real_escape_string($dbConn, $_POST['measure']);
        $prefijo = mysqli_real_escape_string($dbConn, $_POST['prefijo']);
        $cons_no = mysqli_real_escape_string($dbConn, $_POST['cons_no']);
        $lang = mysqli_real_escape_string($dbConn, $_POST['lang']);
        $bemail = mysqli_real_escape_string($dbConn, $_POST['bemail']);
        $date = mysqli_real_escape_string($dbConn, $_POST['date']);
        $timezone = mysqli_real_escape_string($dbConn, $_POST['timezone']);
        $description = mysqli_real_escape_string($dbConn, $_POST['description']);
        $keywords = mysqli_real_escape_string($dbConn, $_POST['keywords']);
        $nom_banco = mysqli_real_escape_string($dbConn, $_POST['nom_banco']);
        $nom_cuenta = mysqli_real_escape_string($dbConn, $_POST['nom_cuenta']);
        $nro_cuenta = mysqli_real_escape_string($dbConn, $_POST['nro_cuenta']);
        $locker = mysqli_real_escape_string($dbConn, $_POST['locker']);
        $dirlocker = mysqli_real_escape_string($dbConn, $_POST['dirlocker']);

		$sql = "UPDATE company 
                SET cname='$cname', 
                    nit='$nit', 
                    cemail='$cemail', 
                    cphone='$cphone', 
                    caddress='$caddress', 
                    country='$country', 
                    measure='$measure', 
                    prefijo='$prefijo', 
                    cons_no='$cons_no', 
                    city='$city', 
                    website='$website', 
                    footer_website='$footer_website', 
                    currency='$currency', 
                    lang='$lang', 
                    bemail='$bemail', 
                    date='$date', 
                    timezone='$timezone', 
                    description='$description', 
                    keywords='$keywords', 
                    nom_banco='$nom_banco', 
                    nom_cuenta='$nom_cuenta', 
                    nro_cuenta='$nro_cuenta', 
                    locker='$locker', 
                    dirlocker='$dirlocker'";

        // Execute the query
        if (mysqli_query($dbConn, $sql)) {
            echo "<script type=\"text/javascript\">
                    alert(\"$changeexits\");
                    window.location = \"../../preferences.php\";
                  </script>";
        } else {
            echo "Error updating record: " . mysqli_error($dbConn);
        }

        // Close the database connection
        //mysqli_close($dbConn);
    
    
?>