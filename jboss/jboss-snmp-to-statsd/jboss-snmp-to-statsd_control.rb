#!/bin/env ruby

require 'rubygems'        # if you use RubyGems
require 'daemons'

options = {
	:dir => '/var/run/jboss-snmp-to-statsd',
	:dir_mode => :normal,
}
Daemons.run('/usr/local/scripts/jboss-snmp-to-statsd/jboss-snmp-to-statsd.rb', options)
