require 'ipaddr'


module Geolocal
  module Provider
    class Base
      def initialize params={}
        @config = params.merge(Geolocal.configuration.to_hash)
      end

      def config
        @config
      end

      def download
        # TODO: skip download if local files are new enough
        # TODO: provide a FORCE argument to force download anyway
        download_files
      end

      def update
        countries = config[:countries].reduce({}) { |a, (k, v)|
          a.merge! k.to_s.upcase => Array(v).map(&:upcase).to_set
        }

        ipv4 = Socket::AF_INET  if config[:ipv4]
        ipv6 = Socket::AF_INET6 if config[:ipv6]

        results = countries.keys.reduce({}) { |a, k|
          a.merge! k.upcase+'v4' => '' if ipv4
          a.merge! k.upcase+'v6' => '' if ipv4
          a
        }

        read_ranges(countries) do |name,lostr,histr|
          loaddr = IPAddr.new(lostr)
          hiaddr = IPAddr.new(histr)
          lofam = loaddr.family
          hifam = hiaddr.family
          raise "#{lostr} is family #{lofam} but #{histr} is #{hifam}" if lofam != hifam

          if lofam == ipv4
            namefam = name+'v4'
          elsif lofam == ipv6
            namefam = name+'v6'
          else
            raise "unknown family #{lofam} for #{lostr}"
          end

          results[namefam] << "#{loaddr.to_i}..#{hiaddr.to_i},\n"
        end

        File.open(config[:file], 'w') do |file|
          output(file, results)
        end

        status "done, result in #{config[:file]}\n"
      end

      def output file, results
        modname = config[:module]

        write_header file, modname

        config[:countries].keys.each do |name|
          v4mod = config[:ipv4] ? name.to_s.upcase + 'v4' : 'nil'
          v6mod = config[:ipv6] ? name.to_s.upcase + 'v6' : 'nil'
          write_method file, name, v4mod, v6mod
        end
        file.write "end\n\n"

        status "  writing "
        results.each do |name, body|
          status "#{name} "
          write_ranges file, modname, name, body
        end
        status "\n"
      end


      def write_header file, modname
        file.write <<EOL
# This file is autogenerated by the Geolocal gem

module #{modname}

  def self.search address, family=nil, v4module, v6module
    address = IPAddr.new(address) if address.is_a?(String)
    family = address.family unless family
    num = address.to_i
    case family
      when Socket::AF_INET  then mod = v4module
      when Socket::AF_INET6 then mod = v6module
      else raise "Unknown family \#{family} for address \#{address}"
    end
    raise "ipv\#{family == 2 ? 4 : 6} was not compiled in" unless mod
    mod.bsearch { |range| num > range.max ? 1 : num < range.min ? -1 : 0 }
  end

EOL
      end

      def write_method file, name, v4mod, v6mod
        file.write <<EOL
  def self.in_#{name}? address, family=nil
    search address, family, #{v4mod}, #{v6mod}
  end

EOL
      end

      def write_ranges file, modname, name, body
        file.write <<EOL
#{modname}::#{name} = [
#{body}]

EOL
      end
    end
  end
end


# random utilities
module Geolocal
  module Provider
    class Base
      # returns elapsed time of block in seconds
      def time_block
        start = Time.now
        yield
        stop = Time.now
        stop - start + 0.0000001 # fudge to prevent division by zero
      end

      def status *args
        unless config[:quiet]
          Kernel.print(*args)
          $stdout.flush unless args.last.end_with?("\n")
        end
      end
    end
  end
end

