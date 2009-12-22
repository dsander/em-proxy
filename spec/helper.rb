require 'rubygems'
require 'spec'
require 'pp'
require 'em-http'

require 'lib/em-proxy'

module ConnectionClosingServer
 def post_init
   close_connection_after_writing
 end
end

module SimpleClient
 def post_init
   send_data "client: hello"
 end
end
