require "sqlite3"

module Nata
  class Model
    application_root = File.join(File.dirname(__FILE__), "..", "..")
    @db = SQLite3::Database.new(application_root + "/db/nata_development.db")
    @db.results_as_hash = true


    def self.fetch_host(hostname)
      @db.execute("SELECT * FROM `hosts` WHERE `name` = ?", hostname).first
    end


    def self.fetch_hostlist
      @db.execute("SELECT * FROM `hosts`")
    end


    def self.summarize_slow_queries(target_host, limit_rows, from_datetime, to_datetime, sort_order = nil)
      result = {}
      fetch_slow_queries(target_host, limit_rows, from_datetime, to_datetime).each do |slow_query|
        # SQL を抽象化する
        # 数値の連続を N に、クォートされた文字列を S に変換
        sql = slow_query["sql_text"]
        next unless sql
        sql = sql.gsub(/\b\d+\b/, "N")
        sql = sql.gsub(/\b0x[0-9A-Fa-f]+\b/, "N")
        sql = sql.gsub(/''/, %q{'S'})
        sql = sql.gsub(/""/, %q{"S"})
        sql = sql.gsub(/(\\')/, "")
        sql = sql.gsub(/(\\")/, "")
        sql = sql.gsub(/'[^']+'/, %q{'S'})
        sql = sql.gsub(/"[^"]+"/, %q{"S"})

        if !result[sql]
          result[sql] = {
            count: 1,
            user: [slow_query["user"]],
            host: [slow_query["exec_from"]],
            query_time: slow_query["query_time"],
            lock_time: slow_query["lock_time"],
            rows_sent: slow_query["rows_sent"],
            rows_examined: slow_query["rows_examined"],
            query_example: slow_query["sql_text"]
          }
          next
        end

        result[sql][:count] += 1
        result[sql][:user] << slow_query["user"]
        result[sql][:host] << slow_query["exec_from"]
        result[sql][:query_time] += slow_query["query_time"]
        result[sql][:lock_time] += slow_query["lock_time"]
        result[sql][:rows_sent] += slow_query["rows_sent"]
        result[sql][:rows_examined] += slow_query["rows_examined"]
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
               when "at"
                 queries.sort_by { |query| query[:average][:query_time] }
               when "al"
                 queries.sort_by { |query| query[:average][:lock_time] }
               when "ar"
                 queries.sort_by { |query| query[:average][:rows_sent] }
               when "c"
                 queries.sort_by { |query| query[:count] }
               when "t"
                 queries.sort_by { |query| query[:sum][:query_time] }
               when "l"
                 queries.sort_by { |query| query[:sum][:lock_time] }
               when "r"
                 queries.sort_by { |query| query[:sum][:rows_sent] }
               else
                 raise
               end

      result.reverse
    end


    def self.fetch_slow_queries(target_host, limit_rows, from_datetime, to_datetime)
      limit_rows = 100 unless limit_rows
      to_datetime = Time.now unless to_datetime

      slow_queries = if from_datetime
                       sql = <<-SQL
                       SELECT * FROM `slow_queries` WHERE `host_id` = (
                         SELECT id FROM `hosts` WHERE `name` = ?
                       ) AND ( `created_at` BETWEEN ? AND ? ) LIMIT ?
                       SQL
                       @db.execute(sql, target_host, from_datetime, to_datetime, limit_rows)
                     else
                       sql = <<-SQL
                       SELECT * FROM `slow_queries` WHERE `host_id` = (
                         SELECT id FROM `hosts` WHERE `name` = ?
                       ) LIMIT ?
                       SQL
                       @db.execute(sql, target_host, limit_rows)
                     end

      slow_queries
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


    def self.delete_host(target_host_name)
      # validation atode kaku

      # deleteの場合はリレーションしてる情報も全部消す
      @db.execute("DELETE FROM `hosts` WHERE `name` = ?", target_host_name)

      # delete しないで表示フラグをオフるとかのほうがいいかな
    end
  end
end
