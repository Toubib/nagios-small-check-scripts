#!/bin/env ruby
# aptitude install libsnmp-ruby libdaemons-ruby
# gem install statsd-ruby syslogger

require 'rubygems'
require 'snmp'
require 'statsd-ruby'
require 'socket'
require 'timeout'
require 'syslogger'

DEBUG = true
STATSD_HOST = { 'dev' => 'xxx',  'rec' => 'xxx', 'app' => 'xxx', 'pre' => 'xxx' }
STATSD_PORT = 8125
ENVIRONMENT = { 'dev' => 'dev', 'rec' => 'recette', 'app' => 'production', 'pre' => 'preproduction'}

SNMP_JVM_TEST= '1.3.6.1.4.1.42.2.145.3.163.1.1.4.4.0'

SNMP_JVM_NUM = {
	'jvm_memory_heap_used' => '1.3.6.1.4.1.42.2.145.3.163.1.1.2.11.0',
	'jvm_memory_noheap_used' => '1.3.6.1.4.1.42.2.145.3.163.1.1.2.21.0',
	'jvmMemGCCount' => '1.3.6.1.4.1.42.2.145.3.163.1.1.2.101.1.2.2',
	'jvmMemGCTimeMs' => '1.3.6.1.4.1.42.2.145.3.163.1.1.2.101.1.3.2',
}
SNMP_JVM_STR = {
	'jvm_memory_heap_used' => 'SNMPv2-SMI::enterprises.42.2.145.3.163.1.1.2.11.0',
	'jvm_memory_noheap_used' => 'SNMPv2-SMI::enterprises.42.2.145.3.163.1.1.2.21.0',
	'jvmMemGCCount' => 'SNMPv2-SMI::enterprises.42.2.145.3.163.1.1.2.101.1.2.2',
	'jvmMemGCTimeMs' => 'SNMPv2-SMI::enterprises.42.2.145.3.163.1.1.2.101.1.3.2',
}

SNMP_JBOSS = {
	'ajp_busy_count' => '1.2.3.4.1.20', 'ajp_max' => '1.2.3.4.1.21',
	'memory_free'  => '1.2.3.4.1.2',  'memory_max'  => '1.2.3.4.1.3',
}
SNMP_JBOSS_BACK = {
	'ds_cat_used'  => '1.2.3.4.1.9',  'ds_cat_max'  => '1.2.3.4.1.10', 'ds_cat_free'  => '1.2.3.4.1.11',
}
SNMP_JBOSS_FRONT = {
	'ds_cat_used'  => '1.2.3.4.1.9',  'ds_cat_max'  => '1.2.3.4.1.10', 'ds_cat_free'  => '1.2.3.4.1.11',
	'ds_fare_used' => '1.2.3.4.1.12', 'ds_fare_max' => '1.2.3.4.1.13', 'ds_fare_free' => '1.2.3.4.1.14',
	'ds_book_used' => '1.2.3.4.1.15', 'ds_book_max' => '1.2.3.4.1.16', 'ds_book_free' => '1.2.3.4.1.17'
}

JBOSS_BLACKLIST = ['xxx', 'yyy']

JBOSS_PATH = 'xxx'
HOSTNAME = Socket.gethostname
SERVER_ENV = ENVIRONMENT[HOSTNAME[0,3].downcase]
SERVER_ID = HOSTNAME.sub(/[A-Za-z]*/,'')

#different behavior between ruby version and os :(((
#have to make a function for this
def get_snmp_label(hash_num, hash_str, name)

	label = hash_num.index(name.to_s)

	if label.nil?
		label = hash_str.index(name.to_s)
	end

	label
end

#Check in the jvm has snmp
def jvm_snmp_enabled?(port)
	SNMP::Manager.open(:Host => 'localhost',:Port => port.to_s, :Timeout => 0.1, :Retries => 0) do |manager|
		response = manager.get( SNMP_JVM_TEST )
		if DEBUG 
			response.each_varbind do |vb|
				printf "#{vb.value.to_s}\n"
			end
		end
	end
    true
rescue Exception => e
    if DEBUG then printf "#{e.message}\n" end
	false
end

def print_time
	time = Time.new
	printf '['+time.hour.to_s+':'+time.min.to_s+' '+time.sec.to_s+'.'+time.usec.to_s + '] '
end

def time_diff_milli(start, finish)
   (finish - start) * 1000.0
end

# setup the jboss instances configurations
def config_setup

	t0 = Time.now
	jboss_instances = []

	begin
		#Scan our jboss server directory
		Dir[JBOSS_PATH+"*"].each do |i|
			
			instance = {}
			instance[:name] = File.basename( i )
			snmp_port = 0
			pid = 0

			#Check if configuration scripts exist
			next if !File.exist? '/etc/init.d/jboss.'+instance[:name]
			next if !File.exist? JBOSS_PATH+instance[:name]+"/pid"

			#Get jboss process PID
			instance[:pid] = File.read(JBOSS_PATH+instance[:name]+"/pid").chomp!

			#Check if running
			next if !File.exist? '/proc/'+instance[:pid]+'/status'

			#Read jboss configuration file
			#This will give us snmp ports
			File.foreach(JBOSS_PATH+instance[:name]+"/conf/ts-config.sh") do |l|
		
				#Td is the client name
				if l =~ /^TD=(.*)/
					instance[:td] = Regexp.last_match(1)

				#Snmp from JBOSS
				elsif l =~ /JBOSS_SNMP_PORT=(.*)/
					instance[:snmp_port] = Regexp.last_match(1) 

				#Snmp from JVM
				elsif l =~ /JBOSS_SNMP_JVM_PORT=(.*)/
					instance[:snmp_jvm_port] = Regexp.last_match(1) 

				end
			end
			instance[:snmp_jvm_port] = (instance[:snmp_port].to_i + 10).to_s

			
			if DEBUG then printf "check jvm snmp for #{instance[:name]} ... " end
			instance[:has_jvm_snmp] = jvm_snmp_enabled? instance[:snmp_jvm_port]
			
			jboss_instances << instance
		end
	rescue Exception => e
		  @logger.error 'config: ' + e.message
	end

	print_time
	printf "Elapsed time (config): %dms\n", (time_diff_milli t0, Time.now)
	jboss_instances
end

#Poll the snmp servers
def run_snmp (jboss_instances)

	t0 = Time.now
	jboss_instances.each do |instance|

		#Prepare our config to call
		if instance[:name] =~ /.*front/ and !JBOSS_BLACKLIST.include? instance[:name]
			snmp_config = SNMP_JBOSS.merge(SNMP_JBOSS_FRONT)
		elsif instance[:name] =~ /.*back/
			snmp_config = SNMP_JBOSS.merge(SNMP_JBOSS_BACK)
		else
			snmp_config = SNMP_JBOSS
		end

		#Setup statsd bucket
		statsd_path = SERVER_ENV+'.'+ instance[:td]+'.jboss.'+instance[:name]+'-'+SERVER_ID+'.'

		#call JBOSS snmp
		begin
		  SNMP::Manager.open(:Host => 'localhost',:Port => instance[:snmp_port], :Timeout => 0.3, :Retries => 1) do |manager|
		    response = manager.get( snmp_config.values )
		    response.each_varbind do |vb|
				#Launch statsd call
				@statsd.gauge statsd_path+snmp_config.index(vb.name.to_s), vb.value
				if DEBUG then printf "#{statsd_path+snmp_config.index(vb.name.to_s)}: #{vb.value}\n" end
		
		    end
		  end
		rescue Exception => e
		  @logger.error instance[:name] + ': ' + e.message
		  if DEBUG then printf "Err #{instance[:name]}: #{e.message}\n" end
		  #exit 2
		end

	    #call JVM snmp
		if instance[:has_jvm_snmp]
		  begin
		    SNMP::Manager.open(:Host => 'localhost',:Port => instance[:snmp_jvm_port], :Timeout => 0.3, :Retries => 1) do |manager|
		      response = manager.get( SNMP_JVM_NUM.values )
		      response.each_varbind do |vb|
				#if DEBUG then printf "vb.name.to_s: #{vb.name.to_s}\n" end
				#Launch statsd call
		  		@statsd.gauge statsd_path+get_snmp_label(SNMP_JVM_NUM, SNMP_JVM_STR, vb.name), vb.value
		  		if DEBUG then printf "#{statsd_path+get_snmp_label(SNMP_JVM_NUM, SNMP_JVM_STR, vb.name)}: #{vb.value}\n" end
		  
		      end
		    end
		  rescue Exception => e
		    @logger.error instance[:name] + ': ' + e.message
		    if DEBUG then printf "Err #{instance[:name]}: #{e.message}\n" end
		    #exit 2
		  end

		end

	end

	print_time
	printf "Elapsed time (snmp + statsd): %dms\n", (time_diff_milli t0, Time.now)
end

#jboss_instances.each do |instance|
#	p instance[:td]+'|'+instance[:name]+': ' + instance[:snmp_port]
#end
 
@logger = Syslogger.new("jboss-snmp-to-statsd", Syslog::LOG_PID, Syslog::LOG_LOCAL0)
@logger.level = Logger::INFO

@statsd = Statsd.new STATSD_HOST[HOSTNAME[0,3].downcase], STATSD_PORT

#Time between config refresh
CONFIG_STEP=600

#Time between polls
RUN_STEP=10

@logger.info "start deamon"

#if DEBUG then printf "Ruby version: #{RUBY_VERSION}\n" end

loop do
	jboss_instances = config_setup

	next_config_time = Time.now + CONFIG_STEP

	#Loop for CONFIG_STEP time with RUN_STEP pauses
	while Time.now < next_config_time
		t0 = Time.now
		run_snmp jboss_instances

		next_run_time_wait = t0 - Time.now + RUN_STEP
		next_run_time_wait = 0 if next_run_time_wait < 0
		#p "wait #{next_run_time_wait}s"

		sleep next_run_time_wait
	end
end

