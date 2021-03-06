# encoding: utf-8
#
# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

module Selenium
  module WebDriver
    module Firefox

      #
      # @api private
      #
      class Service
        START_TIMEOUT       = 20
        SOCKET_LOCK_TIMEOUT = 45
        STOP_TIMEOUT        = 5
        DEFAULT_PORT        = 4444
        MISSING_TEXT        = "Unable to find Mozilla Wires. Please download the executable from https://github.com/jgraham/wires/releases"

        def self.executable_path
          @executable_path ||= (
            path = Platform.find_binary "wires"
            path or raise Error::WebDriverError, MISSING_TEXT
            Platform.assert_executable path

            path
          )
        end

        def self.executable_path=(path)
          Platform.assert_executable path
          @executable_path = path
        end

        def self.default_service(*extra_args)
          new executable_path, DEFAULT_PORT, *extra_args
        end

        def initialize(executable_path, port, *extra_args)
          @executable_path = executable_path
          @host            = Platform.localhost
          @port            = Integer(port)

          raise Error::WebDriverError, "invalid port: #{@port}" if @port < 1

          @extra_args = extra_args
        end

        def start
          Platform.exit_hook { stop } # make sure we don't leave the server running

          socket_lock.locked do
            find_free_port
            start_process
            connect_until_stable
          end
        end

        def stop
          return if @process.nil? || @process.exited?

          Net::HTTP.start(@host, @port) do |http|
            http.open_timeout = STOP_TIMEOUT / 2
            http.read_timeout = STOP_TIMEOUT / 2

            http.head("/shutdown")
          end

          @process.poll_for_exit STOP_TIMEOUT
        rescue ChildProcess::TimeoutError
        ensure
          @process.stop STOP_TIMEOUT
        end

        def uri
          URI.parse "http://#{@host}:#{@port}"
        end

        def find_free_port
          @port = PortProber.above @port
        end

        def start_process
          server_command = [@executable_path, "--binary=#{Firefox::Binary.path}", "--webdriver-port=#{@port}", *@extra_args]
          @process       = ChildProcess.build(*server_command)

          @process.io.inherit! if $DEBUG || Platform.os == :windows
          @process.start
        end

        def connect_until_stable
          @socket_poller = SocketPoller.new @host, @port, START_TIMEOUT

          unless @socket_poller.connected?
            raise Error::WebDriverError, "unable to connect to Mozilla Wires #{@host}:#{@port}"
          end
        end

        def socket_lock
          @socket_lock ||= SocketLock.new(@port - 1, SOCKET_LOCK_TIMEOUT)
        end

      end # Service
    end # Firefox
  end # WebDriver
end # Service
