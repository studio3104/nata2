require 'mysql2-cs-bind'
require 'yaml'

class Hash
  def symbolize_keys!
    keys.each do |key|
      self[(key.to_sym rescue key) || key] = delete(key)
    end
    self
  end
end

module Nata
  class Schema
    def self.client
      @client ||= Mysql2::Client.new(
        default_settings.merge(
          {}
#          YAML.load_file(ENV['NATA_DB_CONFIG']).symbolize_keys!
        )
      )
    end

    def self.default_settings
      {
        host: '127.0.0.1',
        username: 'root',
        password: '',
        database: ENV['RACK_ENV'] ? "nata_#{ENV['RACK_ENV']}" : 'nata_development',
        port: 3306,
        connect_timeout: 2
      }
    end
  end
end



cl = Nata::Schema.client
p cl.query('show databases')
