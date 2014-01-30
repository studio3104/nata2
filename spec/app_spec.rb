require 'spec_helper'

describe Nata::Application do
  include Rack::Test::Methods

  def app
    Nata::Application
  end

  before :each do
    Nata::Model.create_database_and_tables
  end

  after :each do
    Nata::Model.drop_database_and_all_tables
  end


  it '' do
    get '/'
    expect(last_response).to be_ok
  end

  it 'post slow query log' do
    post '/api/1/add/slow_log/test_host1/test_db1', {
      date: '2010/12/31 12:00:00',
      user: 'root[root]', host: 'localhost',
      query_time: 10.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
      sql: 'select sleep(10)'
    }
    expect(last_response).to be_ok
    expect(JSON.parse(last_response.body)).to eq({
      'error' => 0,
      'results' => {
        'id' => 1, 'database_id' => 1,
        'date' => 1293764400,
        'user' => 'root[root]', 'host' => 'localhost',
        'query_time' => 10.00111, 'lock_time' => 0.0, 'rows_sent' => 1, 'rows_examined' => 0,
        'sql' => 'select sleep(10)'
      }
    })
  end
end
