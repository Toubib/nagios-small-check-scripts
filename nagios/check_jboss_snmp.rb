#!/usr/bin/env ruby
# This nagios check script check a jboss status with snmp

require 'rubygems'
require 'snmp'
require 'optiflag'
require 'yaml'

SNMP_JBOSS = {
	:ajp_busy => '1.2.3.4.1.20', :ajp_max => '1.2.3.4.1.21',
	:mem_used => '1.2.3.4.1.2', :mem_max => '1.2.3.4.1.3',
	:ds_cat_used => '1.2.3.4.1.9', :ds_cat_max_used => '1.2.3.4.1.10', :ds_cat_free => '1.2.3.4.1.11', # database datasources
	:ds_fare_used => '1.2.3.4.1.12', :ds_fare_max_used => '1.2.3.4.1.13', :ds_fare_free => '1.2.3.4.1.14', # database datasources
	:ds_book_used => '1.2.3.4.1.15', :ds_book_max_used => '1.2.3.4.1.16', :ds_book_free => '1.2.3.4.1.17', # database datasources
	}

# File with jboss instances's snmp port
# jboss_instance_name01: snmp_port
# jboss_instance_name02: snmp_port
JBOSS_PORTS_CONFIG_FILE='/usr/local/etc/jboss-instances-snmp.yaml'

JBOSS_PORTS = YAML.load_file(JBOSS_PORTS_CONFIG_FILE)

# OPT PARSING
module CheckJbossSnmp extend OptiFlagSet
  usage_flag "h","help"

  optional_switch_flag "v" do
    description "verbose"
  end

  flag "i" do
    long_form "instance"
    description "jboss instance"
  end

  flag "s" do
    long_form "server"
    description "server's instance"
  end

  optional_switch_flag "dsc" do
    long_form "datasource-cat"
    description "--datasource-cat, check cat ds is not full"
  end

  optional_switch_flag "dsb" do
    long_form "datasource-book"
    description "--datasource-book, check book ds is not full"
  end

  optional_switch_flag "dsf" do
    long_form "datasource-fare"
    description "--datasource-fare, check fare ds is not full"
  end

  and_process!
end

if ARGV.flags.v?
  VERBOSE=1
else
  VERBOSE=0
end

result = {}
check_list = {}
nagios_return_str="OK"
nagios_return_code=0
nagios_return_summary_ok=""
nagios_return_summary_err=""

check_list[:ds_cat_free]  = SNMP_JBOSS[:ds_cat_free]  if ARGV.flags.dsc?
check_list[:ds_book_free] = SNMP_JBOSS[:ds_book_free] if ARGV.flags.dsb?
check_list[:ds_fare_free] = SNMP_JBOSS[:ds_fare_free] if ARGV.flags.dsf?

instance = ARGV.flags.i
server = ARGV.flags.s

if VERBOSE > 0 then p "instance=[#{instance}], server=[#{server}], port=[#{JBOSS_PORTS[instance]}]" end

#check instance config
if ! JBOSS_PORTS.has_key? instance
  printf "Err: instance #{instance} not found in JBOSS_PORTS hash\n"
  exit 3
end

#snmp check
begin
  SNMP::Manager.open(:Host => server,:Port => JBOSS_PORTS[instance]) do |manager|
    response = manager.get( check_list.values )
    response.each_varbind do |vb|
      result[vb.name.to_s] = vb.value.to_s
    end
  end
rescue Exception => e
  printf "Err #{e.message}\n"
  exit 2
end

if VERBOSE > 0 then p result.inspect end

# Process results
check_list.each do |k,v|

  nagios_return_summary_ok += " #{k}:#{result[v]}"

  case k
    when :ds_cat_free
      nagios_return_summary_err += " #{k}:#{result[v]}" if result[v].to_i == 0

    when :ds_book_free
      nagios_return_summary_err += " #{k}:#{result[v]}" if result[v].to_i == 0

    when :ds_fare_free
      nagios_return_summary_err += " #{k}:#{result[v]}" if result[v].to_i == 0
  end
end

#print nagios status
if ! nagios_return_summary_err.empty?
  printf "Err -#{nagios_return_summary_err}\n"
  exit 2
end

printf "Ok -#{nagios_return_summary_ok}\n"
exit 0
