require 'mysql2-cs-bind'
require 'yaml'
require 'active_support/core_ext/hash'

module Nata
  class InvalidPostData < StandardError; end
  class Model
    def self.symbolize_and_suppress_keys(targets, numeric: true, updated_at: true, created_at: true)
      targets.map do |target|
        # results_as_hash が有効な sqlite3-ruby の return がこんな感じ { 'name' => 'aaa', 'sex' => 'male', 0 => 'aaa', 1 => 'male' }
        # なので、数字だけの key を削除して返すようにした
        target.symbolize_keys.delete_if do |k, v|
          k.is_a?(Integer) && numeric ||
          k == :updated_at && updated_at ||
          k == :created_at && created_at
        end
      end
    end

    def self.find_all_groups_details
      all_groups = symbolize_and_suppress_keys(client.xquery('SELECT * FROM `groups`'))
      all_groups.map do |group|
        {
          name: group[:name],
          members: find_group_members(group[:id])
        }
      end
    end

    def self.find_group_members(group_id)
      all_hosts = symbolize_and_suppress_keys(client.xquery('SELECT * FROM `hosts`'))
      group_id = Nata::Validator.validate(groupid: { isa: 'INT', val: group_id }).values.first
      group_members_databases = symbolize_and_suppress_keys(client.xquery(%[
        SELECT `databases`.`host_id` as host_id, `databases`.`name` as name
        FROM `group_members`, `databases`
        WHERE `group_id` = ?
        AND `databases`.`id` = `group_members`.`database_id`
      ], group_id))

      # 最高に効率の悪そうな処理なので直す。。アタマまわってないので後で。
      result = {}
      group_members_databases.each do |db|
        host = all_hosts.select { |h| h[:id] == db[:host_id] }.first
        next unless host
        result[host[:name]] ||= []
        result[host[:name]] << db[:name]
      end
      result
    end

    def self.find_all_hosts_details
      all_hosts = symbolize_and_suppress_keys(client.xquery('SELECT * FROM `hosts`'))
      all_databases = symbolize_and_suppress_keys(client.xquery('SELECT * FROM `databases`'))

      all_hosts.map { |host|
        {
          id: host[:id], name: host[:name],
          databases: all_databases.select { |db| host[:id] == db[:host_id] }.sort_by { |db| db[:name] }
        }
      }.sort_by { |host| host[:name] }
    end

    def self.find_group(groupname)
      groupname = Nata::Validator.validate(groupname: { isa: 'STRING', val: groupname }).values.first
      group = client.xquery('SELECT `id`, `name` FROM `groups` WHERE `name` = ?', groupname)
      symbolize_and_suppress_keys(group).first
    end

    def self.find_or_create_group(groupname)
      groupname = Nata::Validator.validate(groupname: { isa: 'STRING', val: groupname }).values.first
      client.xquery('INSERT IGNORE INTO `groups`(`name`) VALUES(?)', groupname)
      find_group(groupname)
    end

    def self.delete_group(groupname)
      groupname = Nata::Validator.validate(groupname: { isa: 'STRING', val: groupname }).values.first
      group = find_group(groupname)
      client.xquery('BEGIN')
      client.xquery('DELETE FROM `group_members` WHERE `group_id` = ?', group[:id])
      client.xquery('DELETE FROM `groups` WHERE `name` = ?', groupname)
      client.xquery('COMMIT')
    end

    def self.constitute_group(groupname, database_ids)
      groupname = Nata::Validator.validate(groupname: { isa: 'STRING', val: groupname }).values.first
      group = find_group(groupname)
      client.xquery('BEGIN')
      client.xquery('DELETE FROM `group_members` WHERE `group_id` = ?', group[:id])
      database_ids.each do |database_id|
        database_id = Nata::Validator.validate(database_id: { isa: 'INT', val: database_id }).values.first
        client.xquery(
          'INSERT INTO `group_members`(`group_id`, `database_id`) VALUES(?, ?)',
          group[:id], database_id
        )
      end
      client.xquery('COMMIT')
    end

    def self.find_host(hostname)
      hostname = Nata::Validator.validate(hostname: { isa: 'STRING', val: hostname }).values.first
      host = client.xquery('SELECT `id`, `name` FROM `hosts` WHERE `name` = ?', hostname)
      symbolize_and_suppress_keys(host).first
    end

    def self.find_or_create_host(hostname)
      hostname = Nata::Validator.validate(hostname: { isa: 'STRING', val: hostname }).values.first
      client.xquery('INSERT IGNORE INTO `hosts`(`name`) VALUES(?)', hostname)
      find_host(hostname)
    end

    def self.find_database(dbname, host_id)
      host_id = Nata::Validator.validate(host_id: { isa: 'INT', val: host_id }).values.first
      dbname = Nata::Validator.validate(dbname: { isa: 'STRING', val: dbname }).values.first

      database = client.xquery('SELECT `id`, `host_id`, `name` FROM `databases` WHERE `host_id` = ? AND `name` = ?', host_id, dbname)
      symbolize_and_suppress_keys(database).first
    end

    def self.find_or_create_database(dbname, host_id)
      database = find_database(dbname, host_id)
      return database if database

      host_id = Nata::Validator.validate(host_id: { isa: 'INT', val: host_id }).values.first
      dbname = Nata::Validator.validate(dbname: { isa: 'STRING', val: dbname }).values.first

      # グラフや複合ビューでの識別のための色
      rgb = "#{rand(256)},#{rand(256)},#{rand(256)}"
      rgb = Nata::Validator.validate(dbname: { isa: 'STRING', val: rgb }).values.first

      # 外部キー制約により存在しない host を紐付けて挿入すると例外
      client.xquery('INSERT IGNORE INTO `databases`(`host_id`, `name`, `rgb`) VALUES(?, ?, ?)', host_id, dbname, rgb)
      find_database(dbname, host_id)
    end

    def self.register_slow_log(hostname, dbname, slow_log)
      host = find_or_create_host(hostname)
      database = find_or_create_database(dbname, host[:id])

      slow_log = Nata::Validator.validate(
        database_id:     { isa: 'INT',    val: database[:id] },
        user:            { isa: 'STRING', val: slow_log[:user] },
        host:            { isa: 'STRING', val: slow_log[:host] },
        long_query_time: { isa: 'FLOAT',  val: slow_log[:long_query_time] },
        query_time:      { isa: 'FLOAT',  val: slow_log[:query_time] },
        lock_time:       { isa: 'FLOAT',  val: slow_log[:lock_time] },
        rows_sent:       { isa: 'INT',    val: slow_log[:rows_sent] },
        rows_examined:   { isa: 'INT',    val: slow_log[:rows_examined] },
        sql:             { isa: 'STRING', val: slow_log[:sql] },
        date:            { isa: 'TIME',   val: slow_log[:date] },
      )

      sql_insert_slow_queries = <<-SQL
        INSERT INTO `slow_queries`(
          `database_id`,
          `user`, `host`,
          `long_query_time`,
          `query_time`, `lock_time`, `rows_sent`, `rows_examined`,
          `sql`, `date`
        )
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL

      slow_log = slow_log.values
      slow_queries_just_inserted = ''
      begin
        client.query('BEGIN')
        client.xquery(sql_insert_slow_queries, slow_log)
        last_insert_id = client.query('SELECT MAX(id) FROM `slow_queries`').first['MAX(id)']
        slow_queries_just_inserted = symbolize_and_suppress_keys(client.xquery(
          'SELECT * FROM `slow_queries` WHERE `id` = ?', last_insert_id
        )).first
        client.query('COMMIT')
      rescue
        client.query('ROLLBACK')
        raise $!.class, $!.message
      end

      slow_queries_just_inserted
    rescue Nata::DataInvalidError => e
      raise Nata::InvalidPostData, e.message
    end


    def self.summarize_slow_queries(slow_queries, sort_order)
      addition = {}
      slow_queries.each do |slow_query|
        # SQL を抽象化する
        # 数値の連続を N に、クォートされた文字列を S に変換
        sql = slow_query[:sql]
        next unless sql
        sql = sql.gsub(/\b\d+\b/, 'N')
        sql = sql.gsub(/\b0x[0-9A-Fa-f]+\b/, 'N')
        sql = sql.gsub(/''/, %q{'S'})
        sql = sql.gsub(/''/, %q{'S'})
        sql = sql.gsub(/(\\')/, '')
        sql = sql.gsub(/(\\')/, '')
        sql = sql.gsub(/'[^']+'/, %q{'S'})
        sql = sql.gsub(/'[^']+'/, %q{'S'})

        if !addition[sql]
          addition[sql] = {
            count: 1,
            user: [slow_query[:user]],
            host: [slow_query[:host]],
            query_time: slow_query[:query_time],
            lock_time: slow_query[:lock_time],
            rows_sent: slow_query[:rows_sent],
            rows_examined: slow_query[:rows_examined],
            query_example: slow_query[:sql]
          }
          next
        end

        addition[sql][:count] += 1
        addition[sql][:user] << slow_query[:user]
        addition[sql][:host] << slow_query[:host]
        addition[sql][:query_time] += slow_query[:query_time]
        addition[sql][:lock_time] += slow_query[:lock_time]
        addition[sql][:rows_sent] += slow_query[:rows_sent]
        addition[sql][:rows_examined] += slow_query[:rows_examined]
      end

      result = []
      addition.each do |abstracted_sql, summary|
        result << {
          count: summary[:count],
          user: summary[:user].uniq,
          host: summary[:host].uniq,
          average: {
            query_time: summary[:query_time] / summary[:count],
            lock_time: summary[:lock_time] / summary[:count],
            rows_sent: summary[:rows_sent] / summary[:count],
            rows_examined: summary[:rows_examined] / summary[:count],
          },
          sum: {
            query_time: summary[:query_time],
            lock_time: summary[:lock_time],
            rows_sent: summary[:rows_sent],
            rows_examined: summary[:rows_examined],
          },
          query: abstracted_sql,
          query_example: summary[:query_example]
        }
      end

      sort_order ? sort_summarized_queries(result, sort_order) : result
    end


    def self.sort_summarized_queries(queries, sort_order)
      result = case sort_order
               when 'at'
                 queries.sort_by { |query| query[:average][:query_time] }
               when 'al'
                 queries.sort_by { |query| query[:average][:lock_time] }
               when 'ar'
                 queries.sort_by { |query| query[:average][:rows_sent] }
               when 'c'
                 queries.sort_by { |query| query[:count] }
               when 't'
                 queries.sort_by { |query| query[:sum][:query_time] }
               when 'l'
                 queries.sort_by { |query| query[:sum][:lock_time] }
               when 'r'
                 queries.sort_by { |query| query[:sum][:rows_sent] }
               else
                 raise
               end

      result.reverse
    end

    # graph_data_components: {database_id => { hostname: hostname, dbname: dbname, rgb: rgb } }
    def self.generate_recent_chart_datasets(graph_data_components, period = 7)
      today = Date.today
      days = []
      period.times do |i|
        days.unshift(today - i)
      end

      graph_datasets = {}
      graph_data_components.each do |dbid, component|
        graph_datasets[dbid] ||= {}
        graph_datasets[dbid][:rgb] ||= component[:rgb]

        graph_datasets[dbid][:data] = days.map do |day|
          fetch_slow_queries(component[:hostname], component[:dbname], day.to_s, day.to_s + ' 23:59:59').size
        end
      end

      # js のコード生成してる。ホントはこんなやり方したくないけど代替手段がわからんかった。
      js_code = '['
      graph_datasets.each do |dbid, dataset|
        # 一週間以内に出力されていないデータベースはプロットしない
        next if dataset[:data] == [0,0,0,0,0,0,0]

        js_code += %[
          {
            fillColor : "rgba(255,255,255,0)",
            strokeColor : "rgba(#{dataset[:rgb]},1.0)",
            pointColor : "rgba(#{dataset[:rgb]},1.0)",
            pointStrokeColor : "rgba(#{dataset[:rgb]},1.0)",
            data : #{dataset[:data]}
          },
        ].strip
      end
      js_code += ']'
      js_code = js_code.sub(/\}\,\]$/,'}]')

      [days.map { |d| d.strftime('%m/%d') }, js_code]
    end

    def self.fetch_recent_slow_queries(fetch_rows = 100)
      sql = <<-"SQL"
      SELECT `slow_queries`.*, `databases`.rgb rgb, `databases`.`name` database_name, `hosts`.`name` host_name
      FROM ( SELECT * FROM `slow_queries` ORDER BY `date` DESC LIMIT #{fetch_rows} ) slow_queries
      JOIN `databases`
      JOIN `hosts`
      ON `slow_queries`.`database_id` = `databases`.`id`
      AND `databases`.`host_id` = `hosts`.`id`
      ORDER BY `slow_queries`.`date` DESC
      SQL
      result = symbolize_and_suppress_keys(client.xquery(sql))
      result.map { |r| r.merge(date: Time.at(r[:date]).strftime("%Y/%m/%d %H:%M:%S")) }
    end

    def self.fetch_slow_queries(target_hostname, target_dbname, from_datetime = nil, to_datetime = nil)
      host = find_host(target_hostname)
      return [] unless host

      # 余分な keys があると SQLite3::Exception: no such bind parameter ってなるので bind_variables は必要に応じてセット
      bind_variables = Nata::Validator.validate(
        host_id: { isa: 'INT', val: host[:id] },
        target_dbname: { isa: 'STRING', val: target_dbname }
      )

      sql_select_databases_id = 'SELECT `id` FROM `databases` WHERE `host_id` = ? AND `name` = ?'
      basesql_select_slow_queries = %[
        SELECT sq.*, db.rgb FROM `slow_queries` as sq, `databases` as db
        WHERE sq.`database_id` = db.`id` AND `database_id` = ( #{sql_select_databases_id} )
      ].strip

      sql_select_slow_queries = if from_datetime.blank?
                                  if to_datetime.blank?
                                    # to_datetime がないときにフェッチを絞る
                                    basesql_select_slow_queries + " LIMIT 10000"
                                  else
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      to_datetime: { isa: 'TIME', val: to_datetime },
                                    )
                                    basesql_select_slow_queries + " AND sq.`date` <= ?"
                                  end
                                else
                                  if to_datetime.blank?
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      from_datetime: { isa: 'TIME', val: from_datetime },
                                    )

                                    # to_datetime がないときにフェッチを絞る
                                    basesql_select_slow_queries + " AND sq.`date` >= ? LIMIT 10000"
                                  else
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      from_datetime: { isa: 'TIME', val: from_datetime },
                                      to_datetime: { isa: 'TIME', val: to_datetime },
                                    )
                                    basesql_select_slow_queries + " AND ( sq.`date` >= ? AND sq.`date` <= ? )"
                                  end
                                end

      bind_variables = bind_variables.values
      result = symbolize_and_suppress_keys(client.xquery(sql_select_slow_queries, bind_variables))
      result.map do |r|
        r.merge(
          date: Time.at(r[:date]).strftime("%Y/%m/%d %H:%M:%S"),
          dbname: target_dbname,
          hostname: target_hostname,
        )
      end
    end

    def self.client()
      if @client && @client.ping
        @client
      else
        @client = Mysql2::Client.new(
          mysql2_default_settings.merge(
             ENV['NATA_DB_CONFIG'] ? YAML.load_file(ENV['NATA_DB_CONFIG']).symbolize_keys : {}
          )
        )
      end
    end

    def self.mysql2_default_settings
      settings = {
        host: '127.0.0.1',
        username: 'root',
        password: '',
        port: 3306,
        connect_timeout: 2,
        reconnect: true
      }


      case ENV['RACK_ENV']
      when 'test'; then settings.delete(:database)
      when 'production'; then settings = settings.merge(database: 'nata_production')
      else settings = settings.merge(database: 'nata_development')
      end

      settings
    end

    # for test
    def self.create_database_and_tables
      return false unless ENV['RACK_ENV'] == 'test'

      client.query('CREATE DATABASE IF NOT EXISTS `nata_test`')
      client.query('use `nata_test`')
      File.read(File.dirname(__FILE__) + '/../../db/create_table.sql').split(";\n").each do |q|
        client.query(q)
      end
    end

    def self.drop_database_and_all_tables
      client.query('DROP DATABASE IF EXISTS `nata_test`')
    end
  end
end
