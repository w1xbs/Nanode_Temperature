<?php

  include 'db.php';

  $db = $_GET["db"];
  $table = $_GET["table"];
  $tempC = $_GET["tempC"];
  $tempF = $_GET["tempF"];
  $millis = $_GET["millis"];
  $vtime = time() * 1000;

  $con = mysql_connect($host, $user, $password);
  if (!con)
  {
    die('Could Not Connect: ' . mysql_error());
  }

  if (mysql_query("CREATE DATABASE IF NOT EXISTS ". $db, $con))
  {
  }
  else
  {
    echo "Error creating database: " . mysql_error();
  }

  mysql_select_db ($db, $con);

  if (mysql_query("CREATE TABLE IF NOT EXISTS " . $table . "(time bigint(22), tempC float, tempF float, millis int(11))"))
  {
  }
  else
  {
    echo "Error creating table: " . mysql_error();
  }

  mysql_query("INSERT INTO " . $table . " (time, tempC, tempF, millis) VALUES ($vtime, $tempC, $tempF, $millis)");

  mysql_close($con);

  echo $vtime;
  echo ", ";
  echo $tempC;
  echo ", ";
  echo $tempF;
  echo ", ";
  echo $millis;

?>
