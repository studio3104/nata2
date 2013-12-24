require 'spec_helper'

describe Nata::Model do
  before :each do
    Nata::Schema.drop_all_databases
    Nata::Schema.create_databases
  end

  context 'find_host' do
    it 'search host' do
      hostname = 'test_host1'
      Nata::Model.find_or_create_host(hostname)
      expect(
        Nata::Model.find_host(hostname)
      ).to eq(id:1, name: hostname)
    end

    it 'search for missing host' do
      expect(
        Nata::Model.find_host('test_host1')
      ).to eq(nil)
    end
  end


  context 'find_database' do
    hostname, dbname = 'test_host1', 'test_db1'
    it 'search database' do
      Nata::Model.find_or_create_database(hostname, dbname)
      expect(
        Nata::Model.find_database(hostname, dbname)
      ).to eq(id: 1, host_id: 1, name: dbname)
    end

    it 'search for missing hostname' do
      expect(
        Nata::Model.find_database(hostname, dbname)
      ).to eq(nil)
    end

    it 'search for exist hostname and missing dbname' do
      Nata::Model.find_or_create_host(hostname)
      expect(
        Nata::Model.find_database(hostname, dbname)
      ).to eq(nil)
    end
  end


  context 'find_or_create_host' do
    it 'call twice with same arguments' do
      hostname = 'test_host1'
      2.times do
        expect(
          Nata::Model.find_or_create_host(hostname)
        ).to eq(
          { id: 1, name: hostname }
        )
      end
    end

    it 'call more than once with argument is difference hostname' do
      expect(
        Nata::Model.find_or_create_host('test_host1')
      ).to eq(
        { id: 1, name: 'test_host1' }
      )
      expect(
        Nata::Model.find_or_create_host('test_host2')
      ).to eq(
        { id: 2, name: 'test_host2' }
      )
      expect(
        Nata::Model.find_or_create_host('test_host3')
      ).to eq(
        { id: 3, name: 'test_host3' }
      )
    end
  end


  context 'find_or_create_database' do
    it 'call twice with same arguments' do
      hostname = 'test_host01'
      dbname = 'test_db01'
      2.times do
        expect(
          Nata::Model.find_or_create_database(hostname, dbname)
        ).to eq(
          { id: 1, host_id: 1, name: dbname }
        )
      end
    end

    it 'call more than once with arguments are same hostname and difference dbname' do
      hostname = 'test_host02'
      expect(
        Nata::Model.find_or_create_database(hostname, 'test_db01')
      ).to eq(
        { id: 1, host_id: 1, name: 'test_db01' }
      )
      expect(
        Nata::Model.find_or_create_database(hostname, 'test_db02')
      ).to eq(
        { id: 2, host_id: 1, name: 'test_db02' }
      )
      expect(
        Nata::Model.find_or_create_database(hostname, 'test_db03')
      ).to eq(
        { id: 3, host_id: 1, name: 'test_db03' }
      )
    end
  end


  context 'register_slow_log' do
    slow_log = { 
      date: '2013/10/31 12:38:58',
      user: 'root[root]',
      host: 'localhost',
      query_time: 10.00111,
      lock_time: 0.0,
      rows_sent: 1,
      rows_examined: 0,
      sql: 'select sleep(10)'
    }

    it 'call once' do
      expect(
        Nata::Model.register_slow_log(
          'test_host01', 'test_db01', slow_log
        )
      ).to eq(
        database_id: 1,
        date: Time.parse('2013-10-31 12:38:58 +0900').to_i,
        host: 'localhost',
        id: 1,
        lock_time: 0.0,
        query_time: 10.00111,
        rows_examined: 0,
        rows_sent: 1,
        sql: 'select sleep(10)',
        user: 'root[root]'
      )
    end
  end

  context 'fetch_slow_queries' do
    hostname = 'test_host1'
    prepare_dummy_data  = Proc.new {
      Nata::Model.register_slow_log(hostname, 'test_db1', {
        date: '2010/12/31 12:00:00',
        user: 'root[root]', host: 'localhost',
        query_time: 10.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
        sql: 'select sleep(10)'
      })
      Nata::Model.register_slow_log(hostname, 'test_db2', {
        date: '2011/12/31 12:00:00',
        user: 'root[root]', host: 'localhost',
        query_time: 20.001142, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
        sql: 'select sleep(20)'
      })
      Nata::Model.register_slow_log(hostname, 'test_db3', {
        date: '2012/12/31 12:00:00',
        user: 'root[root]', host: 'localhost',
        query_time: 30.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
        sql: 'select sleep(30)'
      })
    }

    it 'exist host' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries(hostname)
      ).to eq(
        [
          {
            id: 1, database_id: 1,
            date: Time.parse('2010-12-31 12:00:00 +0900').to_i,
            user: 'root[root]', host: 'localhost',
            query_time: 10.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
            sql: 'select sleep(10)'
          },
          {
            id: 2, database_id: 2,
            date: Time.parse('2011-12-31 12:00:00 +0900').to_i,
            user: 'root[root]', host: 'localhost',
            query_time: 20.001142, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
            sql: 'select sleep(20)'
          },
          {
            id: 3, database_id: 3,
            date: Time.parse('2012-12-31 12:00:00 +0900').to_i,
            user: 'root[root]', host: 'localhost',
            query_time: 30.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
            sql: 'select sleep(30)'
          }
        ]
      )
    end

    it 'missing host' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries('missing_host')
      ).to eq([])
    end

    it 'exist host and exist database' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries(hostname, 'test_db1')
      ).to eq([{
        id: 1, database_id: 1,
        date: Time.parse('2010-12-31 12:00:00 +0900').to_i,
        user: 'root[root]', host: 'localhost',
        query_time: 10.00111, lock_time: 0.0, rows_sent: 1, rows_examined: 0,
        sql: 'select sleep(10)'
      }])
    end

    it 'exist host and missing database' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries(hostname, 'missing_db')
      ).to eq([])
    end

    it 'exist host with from datatime' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries(hostname, from_datetime: '2011-12-31 11:39:00 JST')
      ).to eq([
        {
          id: 2,database_id: 2,
          date: Time.parse('2011-12-31 12:00:00').to_i,
          user: 'root[root]',host: 'localhost',
          query_time: 20.001142,lock_time: 0.0,rows_sent: 1,rows_examined: 0,
          sql: 'select sleep(20)'
        },
        {
          id: 3,database_id: 3,
          date: Time.parse('2012-12-31 12:00:00').to_i,
          user: 'root[root]',host: 'localhost',
          query_time: 30.00111,lock_time: 0.0,rows_sent: 1,rows_examined: 0,
          sql: 'select sleep(30)'
        }
      ])
    end

    it 'exist host with from datatime and to datetime' do
      prepare_dummy_data.call
      expect(
        Nata::Model.fetch_slow_queries(hostname, from_datetime: '2011-12-31 11:39:00 JST', to_datetime: '2012-01-01')
      ).to eq([
        {
          id: 2,database_id: 2,
          date: Time.parse('2011-12-31 12:00:00').to_i,
          user: 'root[root]',host: 'localhost',
          query_time: 20.001142,lock_time: 0.0,rows_sent: 1,rows_examined: 0,
          sql: 'select sleep(20)'
        },
      ])
    end
  end
end
