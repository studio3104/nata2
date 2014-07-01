ENV['RACK_ENV'] = 'test'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'nata2/server'
require 'rspec'
require 'rack/test'

module RSpecMixin
  include Rack::Test::Methods
  include Nata2::Helpers
  def app() Nata2::Server end
end

RSpec.configure do |c|
  c.include RSpecMixin
end

class TestData
  ServiceName = 'nataapplication'
  HostName = 'nata.db01'
  DatabaseName = 'nata_db'
  ParsedSlowQuery = {
    datetime: 1390883951, user: 'user', host: 'localhost',
    query_time: 2.001227, lock_time: 0.0, rows_sent: 1, rows_examined:0,
    sql: 'select sleep(2)'
  }
end

begin
  Nata2::Data.create_tables
  data = Nata2::Data.new
  data.register_slow_query(TestData::ServiceName, TestData::HostName, TestData::DatabaseName, TestData::ParsedSlowQuery)
rescue
end
