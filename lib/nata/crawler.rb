# coding: utf-8
require "sqlite3"
require "parallel"
require "logger"
require "tmpdir"
require "nata/crawler/aggregator"
require "nata/crawler/parser"

# EXPLAIN は別で処理するか処理を追加する。
## スロークエリの登録をクローラ以外のAPIなどからでも登録出来るようにしたい。
### クロール対象になっているホストへのAPIからの登録は出来ないようにする。
## ので、入り口ごとに処理を分岐させて複雑化しないで、いったんストアしておいて、あとで取り出して EXPLAIN する、みたいにしたい。
# ひとまずはあつめてきてパースしてDBに入れるだけ。

module Nata
  class Crawler
    def self.run
      # とりあえずココで
      @logger = Logger.new(Dir.tmpdir + "/nata_crawl.log", 10, 10*1024*1024)

      Thread.new(&method(:crawl))
    end

    def self.crawl
      loop do
        @db = db_client()

        # 設定テーブルは追記型なので最新の1行を取得する
        @settings = @db.execute("SELECT * FROM `settings` WHERE ROWID = LAST_INSERT_ROWID()").first

        target_hosts = @db.execute("SELECT * FROM `hosts` WHERE `crawl_flag` = 1")
        in_threads = @settings["crawl_concurrency"] || Parallel.processor_count

        Parallel.each(target_hosts, in_threads: in_threads) do |host|
          host_informations = prepare_host_informations_to_crawl(host)

          begin
            aggregator = Nata::Aggregator.new(host_informations)
          rescue => e # Net::SSH などの例外。あとで調べて書く。
            @logger.error(host_informations["name"]) { "#{e.message} - #{e.class}" }
            next
          end

          log_file_path, last_file_status, current_file_status = fetch_file_status(aggregator, host_informations["id"])

          if !last_file_status # 初回クロール時はファイルの情報だけ取得保存しておしまい
            register_file_status(host_informations["id"], current_file_status)
            next
          end

          raw_slow_log = fetch_raw_slow_log(aggregator, log_file_path, last_file_status, current_file_status)
          parsed_slow_queries = Nata::Parser.parse_slow_queries(raw_slow_log)
          save_queries(host_informations["id"], current_file_status, parsed_slow_queries)
          aggregator.close
        end

        @db.close
        sleep @settings["crawl_interval_sec"]
      end
    end

    def self.save_queries(host_id, current_file_status, parsed_slow_queries)
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
        parsed_slow_queries.each do |parsed_slow_query|
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


    def self.fetch_file_status(aggregator, host_id)
      # 現在のスローログファイル情報と、前回チェック時のスローログファイル情報を取得。
      log_file_path = aggregator.fetch_slow_log_file_path
      last_file_status = @db.execute("SELECT * FROM `slow_log_files` WHERE `host_id` = ?", host_id).first
      current_file_status = {
        inode: aggregator.fetch_file_inode(log_file_path),
        last_line: aggregator.fetch_file_lines(log_file_path),
      }

      [log_file_path, last_file_status, current_file_status]
    end

    def self.register_file_status(host_id, current_file_status)
      @db.execute(
        "INSERT INTO `slow_log_files` (`host_id`, `inode`, `last_line`) VALUES(?, ?, ?)",
        host_id,
        current_file_status[:inode],
        current_file_status[:last_line]
      )
    end

    def self.fetch_raw_slow_log(aggregator, last_file_status, current_file_status)
      # とってくるファイルサイズ(行数)を制限したほうがいいかも？
      # しばらく稼働してなかったときにどかっと取ってきてしまって帯域圧迫して事故ったりしそう。
      # 行数は config table 作ってそこに入れておき、動的に読みこむようにする
      raw_slow_log = if last_file_status["inode"] == current_file_status[:inode]
                       aggregator.fetch_incremental_text(
                         log_file_path,
                         last_file_status["last_line"],
                         current_file_status[:last_line]
                       )
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
      raw_slow_log
    end
    def self.db_client
      db_dir = File.join(File.dirname(__FILE__), "..", "..", "/db")
      client = case ENV["RACK_ENV"]
               when "production"
                 SQLite3::Database.new(db_dir + "/production.db")
               when "test"
                 SQLite3::Database.new(db_dir + "/test.db")
               else
                 SQLite3::Database.new(db_dir + "/development.db")
               end
      clinet.results_as_hash = true
      client.execute("PRAGMA foreign_keys = ON")
      client
    end

    def self.prepare_host_informations_to_crawl(host)
      {
        "id" => host["id"],
        "name" => host["name"],
        "explain_flag" => host["explain_flag"],
        "ssh_username" => host["ssh_username"] ? host["ssh_username"] : @settings["default_ssh_username"],
        "ssh_password" => host["ssh_password"] ? host["ssh_password"] : @settings["default_ssh_password"],
        "mysql_username" => host["mysql_username"] ? host["mysql_username"] : @settings["default_mysql_username"],
        "mysql_password" => host["mysql_password"] ? host["mysql_password"] : @settings["default_mysql_password"],
        "mysql_command_path" => host["mysql_command_path"] ? host["mysql_command_path"] : @settings["default_mysql_command_path"],
        "mysql_bind_port" => host["mysql_bind_port"] ? host["mysql_bind_port"] : @settings["default_mysql_bind_port"],
      }
    end

  end
end
