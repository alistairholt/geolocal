require 'spec_helper'
require 'geolocal/provider/db_ip'

describe Geolocal::Provider::DB_IP do
  let(:it) { described_class }
  let(:provider) { it.new }


  describe 'network operation' do
    let(:country_page) {
      <<-eol
        <div class="container">
          <h3>Free database download</h3>
          <a href='http://download.db-ip.com/free/dbip-country-2015-02.csv.gz' class='btn btn-primary'>Download free IP-country database</a> (CSV, February 2015)
        </div>
      eol
    }

    # todo: would be nice to test returning lots of little chunks
    let(:country_csv) {
      <<-eol.gsub(/^\s*/, '')
        "0.0.0.0","0.255.255.255","US"
        "1.0.0.0","1.0.0.255","AU"
        "1.0.1.0","1.0.3.255","CN"
      eol
    }

    before do
      stub_request(:get, 'https://db-ip.com/db/download/country').
        with(headers: {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
        to_return(status: 200, body: country_page, headers: {})

      stub_request(:get, "http://download.db-ip.com/free/dbip-country-2015-02.csv.gz").
        with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
        to_return(:status => 200, :body => country_csv, :headers => {'Content-Length' => country_csv.length})
    end

    it 'can download the csv' do
      Geolocal.configure do |config|
        config.tmpdir = 'tmp/geolocal-test'
      end

      # wow!!  can't do this in an around hook because it gets the ordering completely wrong.
      # since around hooks wrap ALL before hooks, they end up using the previous test's config.
      if File.exist?(provider.csv_file)
        File.delete(provider.csv_file)
      end

      provider.download
      expect(File.read provider.csv_file).to eq country_csv

      File.delete(provider.csv_file)
    end
  end


  describe 'generating' do
    let(:example_header) {
      <<EOL
# This file is autogenerated by the Geolocal gem

module Geolocal

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
    true if mod.bsearch { |range| num > range.max ? 1 : num < range.min ? -1 : 0 }
  end

EOL
    }

    def run_test example_body
      outfile = 'tmp/geolocal.rb'
      if File.exist?(outfile)
        File.delete(outfile)
      end

      Geolocal.configure do |config|
        config.tmpdir = 'spec/data'
        config.file = outfile
        config.countries = { us: 'US', au: 'AU' }
        yield config
      end

      provider.update
      expect(File.read outfile).to eq example_header + example_body
      File.delete(outfile)
    end


    it 'can generate countries from a csv' do
      example_output = <<EOL
  def self.in_au? address, family=nil
    search address, family, AUv4, AUv6
  end

  def self.in_us? address, family=nil
    search address, family, USv4, USv6
  end

end

Geolocal::AUv4 = [
16777216..16777471
]

Geolocal::AUv6 = [
55832834671488781931518904937387917312..55832834671488781949965649011097468927
]

Geolocal::USv4 = [
0..16777215
]

Geolocal::USv6 = [
55854460156896106951106838613354086400..55854460790721407065221539361705689087
]

EOL

      run_test example_output do |config|
        # no need to change config
      end
    end

    it 'can generate countries from a csv when ipv6 is turned off' do
      example_output = <<EOL
  def self.in_au? address, family=nil
    search address, family, AUv4, nil
  end

  def self.in_us? address, family=nil
    search address, family, USv4, nil
  end

end

Geolocal::AUv4 = [
16777216..16777471
]

Geolocal::USv4 = [
0..16777215
]

EOL

      run_test example_output do |config|
        config.ipv6 = false
      end
    end


    it 'can generate countries from a csv when ipv4 is turned off' do
      example_output = <<EOL
  def self.in_au? address, family=nil
    search address, family, nil, AUv6
  end

  def self.in_us? address, family=nil
    search address, family, nil, USv6
  end

end

Geolocal::AUv6 = [
55832834671488781931518904937387917312..55832834671488781949965649011097468927
]

Geolocal::USv6 = [
55854460156896106951106838613354086400..55854460790721407065221539361705689087
]

EOL

      run_test example_output do |config|
        config.ipv4 = false
      end
    end
  end
end
