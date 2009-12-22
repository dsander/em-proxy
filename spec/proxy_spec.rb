require 'spec/helper'

describe Proxy do

  def failed
    EventMachine.stop
    fail
  end

  it "should recieve data on port 8080" do
    EM.run do
      EventMachine.add_timer(2) do
        EventMachine::HttpRequest.new('http://127.0.0.1:8080/test').get({:timeout => 1})
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.on_data do |data|
          data.should =~ /GET \/test/
          EventMachine.stop
        end
      end
    end
  end

  it "should call the on_connect callback" do
    connected = false
    EM.run do
      EventMachine.add_timer(2) do
        EventMachine::HttpRequest.new('http://127.0.0.1:8080/test').get({:timeout => 1})
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.on_connect do 
          connected = true
          EventMachine.stop
        end
      end
    end
    connected.should == true
  end


  it "should transparently redirect TCP traffic to google" do
    EM.run do
      EventMachine.add_timer(2) do
        EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.server :goog, :host => "google.com", :port => 80
        conn.on_data { |data| data }

        conn.on_response do |backend, resp|
          backend.should == :goog
          resp.should =~ /google/
          EventMachine.stop
        end
      end
    end
  end

  it "should duplex TCP traffic to two backends google & yahoo" do
    EM.run do
      EventMachine.add_timer(2) do
        EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.server :goog, :host => "google.com", :port => 80
        conn.server :yhoo, :host => "yahoo.com", :port => 80
        conn.on_data { |data| data }

        seen = []
        conn.on_response do |backend, resp|
          case backend
          when :goog then
            resp.should =~ /google/
            seen.push backend
          when :yhoo
            resp.should =~ /yahoo|yimg/
            seen.push backend
          end
          seen.uniq!

          EventMachine.stop if seen.size == 2
        end
      end
    end
  end

  it "should intercept & alter response from Google" do
    EM.run do
      EventMachine.add_timer(2) do
        http = EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
        http.errback { failed }
        http.callback {
          http.response_header.status.should == 404
          EventMachine.stop
        }
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.server :goog, :host => "google.com", :port => 80
        conn.on_data { |data| data }
        conn.on_response do |backend, data|
          data.gsub(/^HTTP\/1.1 200/, 'HTTP/1.1 404')
        end
      end
    end
  end

  it "should invoke on_finish callback when connection is terminated" do
    EM.run do
      EventMachine.add_timer(2) do
        EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
        conn.server :goog, :host => "google.com", :port => 80
        conn.on_data { |data| data }
        conn.on_response { |backend, resp| resp }
        conn.on_finish do |backend|
          backend.should == :goog
          EventMachine.stop
        end
      end
    end
  end

  it "should invoke on_finish callback when a proxied connection is terminated" do
    finished = false
    EM.run do
      echo = EventMachine::start_server "127.0.0.1", 8000, ConnectionClosingServer
      client = nil
      EventMachine.add_timer(0.5) do
        client = EventMachine::connect "127.0.0.1", 8080, SimpleClient
      end

      Proxy.start(:host => "0.0.0.0", :port => 8080, :debug => false) do |conn|
        conn.server :echo, :host => "127.0.0.1", :port => 8000, :relay_client => true, :relay_server => true
        conn.on_finish do |backend|
          backend.should == :echo
          finished = true
          EventMachine.stop
        end
      end
    end
    finished.should == true
  end

  it "should not invoke on_data when :relay_client is passed as server option" do
    lambda {
      EM.run do
        EventMachine.add_timer(2) do
          http =EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
          http.callback { EventMachine.stop }
        end
  
        Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
          conn.server :goog, :host => "google.com", :port => 80, :relay_client => true
          conn.on_data { |data| raise "Should not be here"; data }
          conn.on_response { |backend, resp| resp }
          
        end
      end
    }.should_not raise_error
  end

  it "should not invoke on_response when :relay_server is passed as server option" do
    lambda {
      EM.run do
        EventMachine.add_timer(2) do
          http =EventMachine::HttpRequest.new('http://127.0.0.1:8080/').get({:timeout => 1})
          http.callback { EventMachine.stop }
        end
  
        Proxy.start(:host => "0.0.0.0", :port => 8080) do |conn|
          conn.server :goog, :host => "google.com", :port => 80, :relay_server => true
          conn.on_data { |data| data }
          conn.on_response { |backend, resp| raise "Should not be here"; }
          
        end
      end
    }.should_not raise_error
  end
end