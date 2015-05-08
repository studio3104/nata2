ENV['RACK_ENV'] = 'test'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'nata2/server'
require 'nata2/data'
require 'nata2/config'
require 'uri'
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

path_to_db = URI.parse(Nata2::Config.get(:dburl)).path
Dir.chdir(File.join(File.dirname(__FILE__), '..')) {
  system(%Q[bundle exec ridgepole -c "{adapter: sqlite3, database: #{path_to_db}}" --apply])
}
data = Nata2::Data.new
data.register_slow_query(TestData::ServiceName, TestData::HostName, TestData::DatabaseName, TestData::ParsedSlowQuery)
