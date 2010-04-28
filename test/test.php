<?php
/*
Y - Year as 2004 
y - Year as 04 
M - Month as Oct
m - Month as 10
D - Day  as Tue
d - Day  as 29 
z - Day of the year as 301
H - Hours in 24 hour format as 18
h - Hours in 12 hour format as 06
i - Minutes as 15
s - Seconds as 06
*/
date_default_timezone_set('GMT');
$timezoneDiff = -2 * 60 * 60; // CEST sind 2 Stunden weniger als GMT
$dateFormat = "D, d M Y H:i:s";
$now = time();
$currentDate = date($dateFormat, $now);
$maxAge = 5;
$expireDate = date($dateFormat, $now + $maxAge);
$expiresParam = $HTTP_GET_VARS["expires"];
$maxAgeParam = $HTTP_GET_VARS["maxage"];

if ($_SERVER['HTTP_IF_MODIFIED_SINCE']) {
	$notModified = 1;
} else {
	$notModified = 0;
}

header('Last-Modified: Thu, 28 May 2009 06:45:54 GMT');

if ($expiresParam == "true") {
	header('Expires: ' . $expireDate . ' GMT');
}

if ($maxAgeParam != "") {
	header('Cache-Control: max-age=' . $maxAgeParam);
}

//header("Cache-Control: no-cache, must-revalidate");
//header("Expires: Mon, 26 Jul 1997 05:00:00 GMT");

header('Vary: Accept-Encoding');
header('Date: ' . $currentDate + $timezoneDiff);
header('Connection: keep-alive');
//header('Server: Apache');

if ($notModified==1) {
	header("HTTP/1.0 304 Not Modified");
} else {
	echo "Hello cache! This response was created at ".$currentDate;
	echo "\n\n";
	echo "You sent me:\n\n";

	foreach (getallheaders() as $name => $value) {
	    echo "$name: $value\n";
	}

	echo "\n";
	echo "These are my response headers:\n";
	var_dump(headers_list());
}
?>