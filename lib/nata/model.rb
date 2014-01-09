require 'sqlite3'
require 'active_support/core_ext/hash'

module Nata
  class InvalidPostData < StandardError; end
  class Model
    db_dir = File.join(File.dirname(__FILE__), '..', '..', '/db')
    @db = case ENV['RACK_ENV']
          when 'production'
            SQLite3::Database.new(db_dir + '/production.db')
          when 'test'
            SQLite3::Database.new(db_dir + '/test.db')
          else
            SQLite3::Database.new(db_dir + '/development.db')
          end
    @db.results_as_hash = true
    @db.execute('PRAGMA foreign_keys = ON')

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

    def self.find_all_hosts_details
      all_hosts = symbolize_and_suppress_keys @db.execute('SELECT * FROM `hosts`')
      all_databases = symbolize_and_suppress_keys @db.execute('SELECT * FROM `databases`')

      all_hosts.map { |host|
        {
          id: host[:id], name: host[:name],
          databases: all_databases.select { |db| host[:id] == db[:host_id] }.sort_by { |db| db[:name] }
        }
      }.sort_by { |host| host[:name] }
    end

    def self.find_host(hostname)
      hostname = Nata::Validator.validate(hostname: { isa: 'STRING', val: hostname }).values.first
      host = @db.execute('SELECT `id`, `name` FROM `hosts` WHERE `name` = ?', hostname)
      symbolize_and_suppress_keys(host).first
    end

    def self.find_or_create_host(hostname)
      hostname = Nata::Validator.validate(hostname: { isa: 'STRING', val: hostname }).values.first
      @db.execute('INSERT OR IGNORE INTO `hosts`(`name`) VALUES(?)', hostname)
      find_host(hostname)
    end

    def self.find_database(dbname, host_id)
      host_id = Nata::Validator.validate(host_id: { isa: 'INT', val: host_id }).values.first
      dbname = Nata::Validator.validate(dbname: { isa: 'STRING', val: dbname }).values.first

      database = @db.execute('SELECT `id`, `host_id`, `name` FROM `databases` WHERE `host_id` = ? AND `name` = ?', host_id, dbname)
      symbolize_and_suppress_keys(database).first
    end

    def self.find_or_create_database(dbname, host_id)
      host_id = Nata::Validator.validate(host_id: { isa: 'INT', val: host_id }).values.first
      dbname = Nata::Validator.validate(dbname: { isa: 'STRING', val: dbname }).values.first

      # 外部キー制約により存在しない host を紐付けて挿入すると例外
      @db.execute('INSERT OR IGNORE INTO `databases`(`host_id`, `name`) VALUES(?, ?)', host_id, dbname)
      find_database(dbname, host_id)
    end

    def self.register_slow_log(hostname, dbname, slow_log)
      host = find_or_create_host(hostname)
      database = find_or_create_database(dbname, host[:id])

      slow_log = Nata::Validator.validate(
        user:          { isa: 'STRING', val: slow_log[:user] },
        host:          { isa: 'STRING', val: slow_log[:host] },
        sql:           { isa: 'STRING', val: slow_log[:sql] },
        database_id:   { isa: 'INT',    val: database[:id] },
        rows_sent:     { isa: 'INT',    val: slow_log[:rows_sent] },
        rows_examined: { isa: 'INT',    val: slow_log[:rows_examined] },
        query_time:    { isa: 'FLOAT',  val: slow_log[:query_time] },
        lock_time:     { isa: 'FLOAT',  val: slow_log[:lock_time] },
        date:          { isa: 'TIME',   val: slow_log[:date] },
      )

      sql_insert_slow_queries = <<-SQL
        INSERT INTO `slow_queries`(
          `database_id`,
          `user`, `host`,
          `query_time`, `lock_time`, `rows_sent`, `rows_examined`,
          `sql`, `date`
        )
        VALUES(
          :database_id,
          :user, :host,
          :query_time, :lock_time, :rows_sent, :rows_examined,
          :sql, :date
        )
      SQL

      slow_queries_just_inserted = ''
      @db.transaction do |trx|
        max_id_before_insert = trx.execute('SELECT MAX(id) FROM `slow_queries`').first[0].to_i
        trx.execute(sql_insert_slow_queries, slow_log)
        slow_queries_just_inserted = symbolize_and_suppress_keys(trx.execute(
          'SELECT * FROM `slow_queries` WHERE `id` = ?', max_id_before_insert + 1
        )).first
      end

      slow_queries_just_inserted
    rescue Nata::DataInvalidError => e
      raise Nata::InvalidPostData, e.message
    end


    def self.summarize_slow_queries(slow_queries, sort_order)
      result = {}
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

        if !result[sql]
          result[sql] = {
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

        result[sql][:count] += 1
        result[sql][:user] << slow_query[:user]
        result[sql][:host] << slow_query[:host]
        result[sql][:query_time] += slow_query[:query_time]
        result[sql][:lock_time] += slow_query[:lock_time]
        result[sql][:rows_sent] += slow_query[:rows_sent]
        result[sql][:rows_examined] += slow_query[:rows_examined]
      end

      aheahe = []
      result.each do |abstracted_sql, summary|
        aheahe << {
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

      sort_order ? sort_summarized_queries(aheahe, sort_order) : aheahe
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

    def self.fetch_recent_slow_queries(fetch_rows = 100)
      sql = <<-SQL
      SELECT `slow_queries`.*, `databases`.`name` database_name, `hosts`.`name` host_name
      FROM ( SELECT * FROM `slow_queries` ORDER BY `date` DESC LIMIT ? ) slow_queries
      JOIN `databases`
      JOIN `hosts`
      ON `slow_queries`.`database_id` = `databases`.`id`
      AND `databases`.`id` = `hosts`.`id`
      SQL
      result = symbolize_and_suppress_keys(@db.execute(sql, fetch_rows))
      result.map { |r| r.merge(date: Time.at(r[:date]).strftime("%Y/%m/%d %H:%M:%S")) }
    end

    def self.fetch_slow_queries(target_hostname, target_dbname = nil, from_datetime = nil, to_datetime = nil)
      host = find_host(target_hostname)
      return [] unless host

      # 余分な keys があると SQLite3::Exception: no such bind parameter ってなるので bind_variables は必要に応じてセット
      bind_variables = Nata::Validator.validate(host_id: { isa: 'INT', val: host[:id] })

      sql_select_databases_ids = if target_dbname
                                   bind_variables = bind_variables.merge Nata::Validator.validate(target_dbname: { isa: 'STRING', val: target_dbname })
                                   'SELECT `id` FROM `databases` WHERE `host_id` = :host_id AND `name` = :target_dbname'
                                 else
                                   'SELECT `id` FROM `databases` WHERE `host_id` = :host_id'
                                 end

      basesql_select_slow_queries = "SELECT * FROM `slow_queries` WHERE `database_id` IN ( #{sql_select_databases_ids} )"
      sql_select_slow_queries = if from_datetime.blank?
                                  if to_datetime.blank?
                                    basesql_select_slow_queries
                                  else
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      to_datetime: { isa: 'TIME', val: to_datetime },
                                    )

                                    basesql_select_slow_queries + "AND `date` <= :to_datetime"
                                  end
                                else
                                  if to_datetime.blank?
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      from_datetime: { isa: 'TIME', val: from_datetime },
                                      to_datetime: { isa: 'TIME', val: Time.now.to_s },
                                    )
                                  else
                                    bind_variables = bind_variables.merge Nata::Validator.validate(
                                      from_datetime: { isa: 'TIME', val: from_datetime },
                                      to_datetime: { isa: 'TIME', val: to_datetime },
                                    )
                                  end

                                  basesql_select_slow_queries + " AND ( `date` >= :from_datetime AND `date` <= :to_datetime )"
                                end

      result = symbolize_and_suppress_keys(@db.execute(sql_select_slow_queries, bind_variables))
      result.map do |r|
        r.merge(
          date: Time.at(r[:date]).strftime("%Y/%m/%d %H:%M:%S"),
          dbname: target_dbname,
          hostname: target_hostname,
        )
      end
    end
  end
end
__END__


    def self.fetch_slow_queries_with_explain(target_host, limit_rows, from_datetime, to_datetime)
      fetch_slow_queries(target_host, limit_rows, from_datetime, to_datetime).map do |slow_query|
        slow_query['explain'] = @db.execute('SELECT * FROM `explains` WHERE `slow_query_id` = ?', slow_query['id'])
        slow_query
      end
    end

    def self.add_host(target_host_values)
      # validation: atode kaku

      current_datetime = Time.now.to_s
      sql = <<-SQL
      INSERT INTO `hosts`(
        `name`, `ipadress`,
        `ssh_username`, `ssh_options`,
        `mysql_command`, `mysql_username`, `mysql_password`, `mysql_port`,
        `created_at`, `updated_at`
      )
      VALUES(
        :name, :ipaddress,
        :ssh_username, :ssh_options,
        :mysql_command, :mysql_username, :mysql_password, :mysql_port,
        :created_at, :updated_at
      )
      SQL

      @db.execute(
        sql,
        target_host_values.merge(
          created_at: current_datetime,
          updated_at: current_datetime
        )
      )
    end


    def self.modify_host(target_host_values)
      sql = <<-SQL
      UPDATE `hosts` SET
        `ipadress` = :ipaddress,
        `ssh_username` = :ssh_username, `ssh_options` = :ssh_options,
        `mysql_command` = :mysql_command, `mysql_username` = :mysql_username,
        `mysql_password` = :mysql_password, `mysql_port` = :mysql_port,
        `updated_at` = :updated_at
      WHERE `name` = :name
      SQL

      @db.execute(sql, target_host_values.merge(updated_at: Time.now.to_s))
    end


    def self.delete_host(target_host_name)
      # validation atode kaku

      # deleteの場合はリレーションしてる情報も全部消す
      @db.execute('DELETE FROM `hosts` WHERE `name` = ?', target_host_name)

      # delete しないで表示フラグをオフるとかのほうがいいかな
    end
  end
end
