#!/usr/bin/env ruby
# Services: xxxx rm appxx
# messages:
# - Critical: timeout 10.0s on [/]
# - (Service Check Timed Out)
# - Critical - 19ko, 1 files, 10.31s

require 'net/http'
require 'nagiosharder'

HOST=ARGV[0]
SERVICE=ARGV[1]
MESSAGE=ARGV[2]
STATE_ID=ARGV[3]
STATE_TYPE=ARGV[4]
SERVERS_PREFIX='appxxx'
LOGFILE='/var/log/nagios3/restart-jboss.log'
MAX_SAFE_CRITICAL_COUNT=10
NAGIOS_INTERNET_CHECK = {
	"xxx" => [
		"Google_xxx",
		"Google_yyy",
	],
	"www.google.fr" => [
		"Web",
	]
}

URL='http://xxx/restart/prod/'

TIMEOUT_STATUS=[
	/Critical: timeout [0-9\.]*s on/,
	/Service Check Timed Out/,
	/Critical - [0-9a-zA-Z]*, [0-9]* files, [0-9\.]*[a-z]*/,
]

def _log message
	t = Time.new.strftime("%Y-%m-%d %H:%M:%S")
	printf "[#{t}] #{message}\n"
	File.open(LOGFILE, 'a') { |file|
		file.write("[#{t}] #{message}\n")
	}
end

def _exit message
	_log "EXIT: "+message+"\n"
	exit
end

#parse application server informations and trigger the restart
def parse_app
	/([-\.\w]*) [-\.\w]* app([0-9]*)/.match SERVICE
	instance = $1
	serveur_id = $2

	_log "i=#{instance} sid=#{serveur_id}"
	call_url instance, SERVERS_PREFIX+serveur_id
end

#trigger an application server restart
def call_url instance, server
	url=URL+server+'/'+instance
	r = Net::HTTP.get_response(URI.parse(url))
	_log "HTTP code=#{r.code}, msg=#{r.body}"
end

#check if the alert is a service timeout
def is_timeout?
	is_timeout = false
	TIMEOUT_STATUS.each do |r|
		is_timeout = true if MESSAGE =~ r
	end
	
	is_timeout
end

#Check the monitoring system status
def nagios_internet_status_is_ok?
	ret = true
	site = NagiosHarder::Site.new('http://xxx/cgi-bin/nagios3', nil, nil)
	services = site.service_status(:critical)

	#p "Critical: #{services.inspect}"

	count_real_critical_services=0
	services.each do |s|
		next if s.attempts[0] != s.attempts[2] #test if HARD
		next if s.notifications_disabled
		next if s.acknowledged
		count_real_critical_services += 1
	end
	
	if count_real_critical_services > MAX_SAFE_CRITICAL_COUNT
		_log "#{count_real_critical_services} current nagios alerts is more than the max allowed (#{MAX_SAFE_CRITICAL_COUNT})"
		return false
	end

	#check for internet check access alert
	services.each do |s|

		next if s.attempts[0] != s.attempts[2] #test if HARD
		#p "#{s.host}/#{s.service}"

		NAGIOS_INTERNET_CHECK.each do |nagios_host, nagios_services|
			next if s.host != nagios_host

			nagios_services.each do |nagios_service|
				ret = false if s.service == nagios_service
			end
		end

	end

	ret
end

#we want only hard errors alert types.
exit if STATE_TYPE != 'HARD'
exit if STATE_ID != '2'

_log "Request for HOST='#{HOST}', SERVICE='#{SERVICE}', MESSAGE='#{MESSAGE}'"
_exit "not a timeout" if is_timeout? == false

# Recherche des pattern d'instance
if SERVICE =~ /[-a-z0-9\.]* [-a-z0-9\.]* app[0-9]*/
	sleep 60 #wait 1 min to check nagios_internet_status
	_exit "Nagios status seems in a bad way !" if nagios_internet_status_is_ok? == false
	parse_app
else
	_exit "pattern not found"
end
