<?php
/*
 * Export nagios config to a xml file
 */

$nagiosConfFile='/var/cache/nagios3/objects.cache';
$outdir='/var/www/nagios';

class nagiosService {
  var $host_name=null;
  var $service_description=null;
  var $check_command=null;
  var $normal_check_interval=null;

  function __construct($configArray){
    foreach($configArray as $key => $configLine){
      //echo $configLine."\n";
      if(strstr($configLine,'host_name') == true ){
        $this->host_name=trim(str_replace('host_name','',$configLine));
      }
      if(strstr($configLine,'service_description') == true ){
	$this->service_description=htmlspecialchars(trim(str_replace('service_description','',$configLine)));
      }
      if(strstr($configLine,'check_command') == true ){
	$this->check_command=trim(str_replace('check_command','',$configLine));
	//$this->check_command=$configLine;
      }
    }
  }

  /**
    Return the xml service node
  */
  function getXmlNode(){
    $node="<service>\n";
    $node=$node."  <host_name>".$this->host_name."</host_name>\n";
    $node=$node."  <service_description>".$this->service_description."</service_description>\n";
    $node=$node."  <check_command><![CDATA[".$this->check_command."]]></check_command>\n";
    $node=$node."</service>\n";
    return $node;
  }
}

class nagiosCommand {
  var $command_name=null;
  var $command_line=null;

  function __construct($configArray){
    foreach($configArray as $key => $configLine){
      if(strstr($configLine,'command_name') == true ){
        $this->command_name=trim(str_replace('command_name','',$configLine));
      }
      if(strstr($configLine,'command_line') == true ){
        $this->command_line=trim(str_replace('command_line','',$configLine));
      }
    }
  }

  function getXmlNode(){
    $node="<command>\n";
    $node=$node."  <command_name>".$this->command_name."</command_name>\n";
    $node=$node."  <command_line><![CDATA[".$this->command_line."]]></command_line>\n";
    $node=$node."</command>\n";
    return $node;
  }
}

$nagiosConfString=file_get_contents($nagiosConfFile);
//echo '<pre>';
//var_dump($nagiosConfString);
//echo '</pre><hr /><hr /><hr />';

$nagiosConfArray=explode('define',$nagiosConfString);

//CLASS SERVICE
echo "<nagios_config>\n";
foreach($nagiosConfArray as $config){
  $configArray=explode("\n",$config);
  //var_dump($configArray);
  if ( strstr($configArray[0],'service') == true && strstr($configArray[0],'serviceextinfo') == false){
    $nservice=new nagiosService($configArray);
    echo $nservice->getXmlNode();
  }
  if ( strstr($configArray[0],'command') == true ){
    $ncommand=new nagiosCommand($configArray);
    echo $ncommand->getXmlNode();
  }
}
echo "</nagios_config>\n";
?>
