# coding: utf-8
require "sqlite3"
require "parallel"
require "logger"
require "tmpdir"
require "nata/crawler/aggregator"
require "nata/crawler/parser"

module Nata
  class Crawler
    def self.run
      Thread.new(&method(:execute))
    end

    def self.execute
      @logger = Logger.new(Dir.tmpdir + "/nata_crawl.log", 10, 10*1024*1024)
      application_root = File.join(File.dirname(__FILE__), "..", "..")

      loop do
        @db = case ENV["RACK_ENV"]
              when "production"
                SQLite3::Database.new(application_root + "/db/production.db")
              when "test"
                SQLite3::Database.new(application_root + "/db/test.db")
              else
                SQLite3::Database.new(application_root + "/db/development.db")
              end
        @db.results_as_hash = true
        @db.execute("PRAGMA foreign_keys = ON")
        @settings = @db.execute("SELECT * FROM `settings` WHERE ROWID = LAST_INSERT_ROWID()").first

        target_hosts_variables = @db.execute("SELECT * FROM `hosts`")

        Parallel.each(target_hosts_variables, in_threads: Parallel.processor_count) do |host|
          crawl(host)
        end

        @db.close
        sleep @settings["crawl_interval_sec"]
      end
    end

    def self.prepare_host_informations_to_crawl(host)
      ssh = @db.execute("SELECT * FROM `ssh_options` WHERE `host_id` = ?", host["id"]).first
      mysql = @db.execute("SELECT * FROM `mysql_options` WHERE `host_id` = ?", host["id"]).first

      {
        "id" => host["id"],
        "name" => host["name"],
        "explain_flag" => host["explain_flag"],
        "ssh_username" => ssh["username"] ? ssh["username"] : @setting["default_ssh_username"],
        "ssh_password" => ssh["password"] ? ssh["password"] : @setting["default_ssh_password"],
        "mysql_username" => mysql["username"] ? mysql["username"] : @setting["default_mysql_username"],
        "mysql_password" => mysql["password"] ? mysql["password"] : @setting["default_mysql_password"],
        "mysql_command_path" => mysql["command_path"] ? mysql["command_path"] : @setting["default_mysql_command_path"],
        "mysql_bind_port" => mysql["bind_port"] ? mysql["bind_port"] : @setting["default_mysql_bind_port"],
      }
    end

    def self.crawl(host)
      host_informations = prepare_host_informations_to_crawl(host)

      begin
        aggregator = Nata::Aggregator.new(host_informations)
      rescue => e # Net::SSH などの例外。あとで調べて書く。
        @logger.error(host_informations["name"]) { "#{e.message} - #{e.class}" }
        return
      end

      # 現在のスローログファイル情報と、前回チェック時のスローログファイル情報を取得。
      log_file_path = aggregator.fetch_slow_log_file_path
      last_file_status = @db.execute("SELECT * FROM `slow_log_files` WHERE `host_id` = ?", host_informations["id"]).first
      current_file_status = {
        inode: aggregator.fetch_file_inode(log_file_path),
        last_line: aggregator.fetch_file_lines(log_file_path),
      }

      # 初回クロール時はファイルの情報だけ取得保存しておしまい。
      if !last_file_status
        @db.execute(
          "INSERT INTO `slow_log_files` (`host_id`, `inode`, `last_line`) VALUES(?, ?, ?)",
          host_informations["id"],
          current_file_status[:inode],
          current_file_status[:last_line]
        )
        return
      end

      # とってくるファイルサイズ(行数)を制限したほうがいいかも？
      # しばらく稼働してなかったときにどかっと取ってきてしまって帯域圧迫して事故ったりしそう。
      # 行数は config table 作ってそこに入れておき、動的に読みこむようにする
      raw_slow_log = if last_file_status["inode"] == current_file_status[:inode]
                       aggregator.fetch_incremental_text(log_file_path, last_file_status["last_line"], current_file_status[:last_line])
                     else
                       # ログローテーションされちゃってるか、ログファイルが消えてる可能性
                       # ちょっとどうしようか考えつかないのでpending
                       ## 圧縮されてなければ inode 変わってないであろうと仮定して、
                       #### 同一ディレクトリを ls -li -> 同一ディレクトリになかったらどうするか
                       #### inode で find -> これは上から順にファイル舐めるしダメっぽい感じする
                       ## 圧縮されてたら
                       #### 今のファイル名を prefix として find なりしてみる。 -> どろくさい
                       ## 圧縮された上に脈絡ないファイル名になってるかも知れない
                       #### 思いつかん。
                     end

      slow_queries = touroku_toka(host_informations["id"], raw_slow_log, current_file_status)
      explain_suru_toko(aggregator, slow_queries) if host_informations["explain_flag"]
    rescue SQLite3::SQLException, SQLite3::BusyException
    ensure
      aggregator.close if aggregator
    end

    def self.touroku_toka(host_id, raw_slow_log, current_file_status)
      current_datetime = Time.now.to_s

      sql_insert_slow_queries = <<-SQL
        INSERT INTO `slow_queries`(
          `database_id`,
          `user`, `host`,
          `query_time`, `lock_time`, `rows_sent`, `rows_examined`,
          `sql_text`, `db`, `start_time`,
          `created_at`
        )
        VALUES(
          :host_id,
          :user, :host,
          :query_time, :lock_time, :rows_sent, :rows_examined,
          :sql_text, :db, :start_time,
          :created_at
        )
      SQL

      @db.transaction do |trn|
        Nata::Parser.parse_slow_queries(raw_slow_log).each do |parsed_slow_query|
          trn.execute(
            sql_insert_slow_queries,
            parsed_slow_query.merge(host_id: host_id, created_at: current_datetime)
          )
        end

        trn.execute(
          "UPDATE `slow_log_files` SET `last_line` = ?, `inode` = ?, `updated_at` = ? WHERE `host_id` = ?",
          current_file_status[:last_line],
          current_file_status[:inode],
          current_datetime,
          host_id
        )
      end

      @db.execute("SELECT * FROM `slow_queries` WHERE `host_id` = ? AND `created_at` = ?", host_id, current_datetime)
    end

    def self.explain_suru_toko(aggregator, target_slow_queries)
      sql_insert_explains = <<-SQL
        INSERT INTO `explains` (
          `slow_query_id`,
          `explain_id`,
          `select_type`, `table`, `type`, `possible_keys`, `key`, `key_len`, `ref`, `rows`, `extra`
        ) VALUES (
          :slow_query_id,
          :explain_id,
          :select_type, :table, :type, :possible_keys, :key, :key_len, :ref, :rows, :extra
        )
      SQL

      target_slow_queries.each do |just_inserted|
        sql = just_inserted["sql_text"]
        next if !sql || sql.upcase !~ /^SELECT/ #SQLInjection対策のValidationも行う！！！！！！！！！あとでね
        raw_explain = aggregator.explain_query(sql)

        @db.transaction do |trn|
          Nata::Parser.parse_explain(raw_explain).each do |parsed_explain|
            trn.execute(
              sql_insert_explains, 
              parsed_explain.merge(slow_query_id: just_inserted["id"])
            )
          end
        end
      end
    end
  end
end
