#!/usr/bin/ruby -w

# We use old ruby 1.8.7
# rubocop:disable Style/HashSyntax

# Other disables
# rubocop:disable Metrics/LineLength, Metrics/MethodLength, Metrics/AbcSize

module LoadBalance
  PARAMS = {
    :socket => '/var/lib/haproxy/stats'
  }.freeze

  # Generic Class to get and set Haproxy backends weights
  class HaproxyGeneric
    require 'open3'
    require 'socket'

    attr_reader :weight

    def initialize
      @weight = {}
    end

    # Define your own function to fetch load
    def fetch_load
      {}
    end

    # Define your own function to calculate weight based on load
    def calculate_weight(_load)
      {}
    end

    def load_weight
      @weight['old'] = parse_stats(load_stats)
      @weight['new'] = normalize_weight(calculate_weight(fetch_load))
    end

    def apply_weight
      command = ''
      @weight['new'].each do |backend, servers|
        servers.each do |server, weight|
          server_name = backend + '/' + server
          command += 'set server ' + server_name + ' weight ' + weight.to_s + ' ; '
          log('changing weight for ' + server_name + ' from ' + @weight['old'][backend][server].to_s + ' to ' + weight.to_s)
        end
        command.chomp!(' ; ')
      end
      socket = UNIXSocket.new(LoadBalance::PARAMS[:socket])
      socket.write(command + "\n")
      data = socket.read
      socket.close
      data.chomp!.chomp!
      raise 'Haproxy command error : ' + data unless data.empty?
    end

    def load_stats
      socket = UNIXSocket.new(LoadBalance::PARAMS[:socket])
      socket.write("show stat\n")
      stats = socket.read.split("\n")
      socket.close
      stats
    end

    def parse_stats(stats)
      stats.map! { |line| line.split(',') }
      stats.delete_if { |line| line[1] == 'FRONTEND' || line[1] == 'BACKEND' }
      # convert all stats into hash
      info = {}
      first = stats.shift
      first.each_with_index do |val, index|
        info[val] = {}
        stats.each do |x|
          info[val][x[0]] = {} if info[val][x[0]].nil?
          info[val][x[0]][x[1]] = x[index]
        end
      end
      # return weight only
      info['weight']
    end

    def normalize_weight(weight)
      weight.each do |backend, servers|
        max = servers.values.max
        servers.each { |server, load| weight[backend][server] = (load * 256 / max).ceil }
      end
      weight
    end

    def log(message)
      puts Time.now.inspect + ': ' + message
    end

    def backends
      @weight['old'].keys
    end

    def servers(*backend)
      servers = {}
      if backend.empty?
        backends.each do |name|
          servers[backend] = @weight['old'][name].keys
        end
        return servers
      elsif backend.size == 1
        return @weight['old'][backend[0]].keys
      else
        raise 'Wrong number of backends'
      end
    end

    private :fetch_load, :calculate_weight, :load_stats, :parse_stats
    private :log, :backends, :servers
  end

  # Define actual fetch_load and calculate_weight methods in this class
  class Haproxy < LoadBalance::HaproxyGeneric
    # Fetch averge load using ssh. Linux specific version using /proc/loadavg
    def fetch_load
      load = {}
      backends.each do |backend|
        servers(backend).each do |server|
          command = "ssh #{server} cat /proc/loadavg ; echo status=$?"
          data = {}
          # Use Ruby 1.8.7 compatible Open3 which does not support exit status
          Open3.popen3(command) do |stdin, stdout, stderr|
            stdin.close
            data['stdout'] = stdout.read.split("\n")
            data['sterr'] = stderr.read
          end
          data['status'] = data['stdout'].pop.split('=')
          unless data['status'][0] == 'status' || data['status'][0] == '0'
            raise 'Wrong SSH status'
          end
          load[backend] = {} if load[backend].nil?
          load[backend][server] = data['stdout'].pop.split(/\s+/)[1].to_f
        end
      end
      load
    end

    # Calculate weight based on load
    def calculate_weight(load)
      weight = {}
      backends.each do |backend|
        weight[backend] = {}
        full = 1
        load[backend].values.each { |x| full *= x }
        servers(backend).each do |server|
          weight[backend][server] = ((10 * full) / load[backend][server])
        end
      end
      weight
    end
  end
end

haproxy = LoadBalance::Haproxy.new
haproxy.load_weight
haproxy.apply_weight
