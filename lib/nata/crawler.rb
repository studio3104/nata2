# coding: utf-8
require "sqlite3"
require "parallel"
require "logger"
require "tmpdir"
require "nata/aggregator"
require "nata/parser"

module Nata
  class Crawler
    def self.run
      # とりあえず tmpdir で。あとでちゃんとする。
      Thread.new(&method(:execute))
    end

    def self.execute
      @logger = Logger.new(Dir.tmpdir + "/nata_crawl.log", 10, 10*1024*1024)
      application_root = File.join(File.dirname(__FILE__), "..", "..")

      loop do
        @db = SQLite3::Database.new(application_root + "/db/nata_development.db")
        @db.results_as_hash = true
        target_host_informations = @db.execute("SELECT * FROM `hosts`")

        Parallel.each(target_host_informations, in_threads: Parallel.processor_count) do |host_info|
          crawl(host_info)
        end

        @db.close
        # interval は config table 作ってそこに入れておき、動的に読みこむようにする
        sleep 3
      end
    end

    def self.crawl(host_info)
      # host_info has hostname, 'ssh auth info', 'mysql command path' and 'mysql auth info'.
      begin
        aggregator = Nata::Aggregator.new(host_info)
      rescue => e # Net::SSH などの例外。あとで調べて書く。
        @logger.error(host_info["name"]) { "#{e.message} - #{e.class}" }
        return
      end

      log_file_path = aggregator.fetch_slow_log_file_path
      last_file = @db.execute("SELECT * FROM `slow_log_files` WHERE `host_id` = ?", host_info["id"]).first # return: { id: pk, host_id: int, inode: int, last_line: int }
      current_file = {
        inode: aggregator.fetch_file_inode(log_file_path),
        last_line: aggregator.fetch_file_lines(log_file_path),
      }

      # 初回クロール時はファイルの情報だけ取得保存しておしまい。
      if !last_file
        @db.execute(
          "INSERT INTO `slow_log_files`(`host_id`,`inode`,`last_line`) VALUES(?,?,?)",
          host_info["id"],
          current_file[:inode],
          current_file[:last_line]
        )
        return
      end

      # とってくるファイルサイズ(行数)を制限したほうがいいかも？
      # しばらく稼働してなかったときにどかっと取ってきてしまって帯域圧迫して事故ったりしそう。
      # 行数は config table 作ってそこに入れておき、動的に読みこむようにする
      raw_slow_log = if last_file["inode"] == current_file[:inode]
                       aggregator.fetch_incremental_text(log_file_path, last_file["last_line"], current_file[:last_line])
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

      current_datetime = Time.now.to_s
      @db.transaction do |trn|
        Nata::Parser.parse_slow_queries(raw_slow_log).each do |parsed_slow_query|
          trn.execute(
            "INSERT INTO `slow_queries`(`host_id`,`start_time`,`user`,`exec_from`,`query_time`,`lock_time`,`rows_sent`,`rows_examined`,`db`,`sql_text`,`created_at`,`updated_at`)
            VALUES(:host_id,:start_time,:user,:exec_from,:query_time,:lock_time,:rows_sent,:rows_examined,:db,:sql_text,:created_at,:updated_at)",

            parsed_slow_query.merge(
              host_id: host_info["id"],
              created_at: current_datetime,
              updated_at: current_datetime
            )
          )
        end

        trn.execute(
          "UPDATE `slow_log_files` SET `last_line` = ?, `inode` = ?, `updated_at` = ? WHERE `host_id` = ?",
          current_file[:last_line],
          current_file[:inode],
          current_datetime,
          host_info["id"]
        )
      end

      # ココは別メソッドにしよう
      # EXPLAIN はおまけなので、メインのスロークエリの挿入とはトランザクションを分ける
      sql_select_just_inserted = "SELECT `id`, `sql_text` FROM `slow_queries` WHERE `host_id` = ? AND `updated_at` = ?"
      @db.execute(sql_select_just_inserted, host_info["id"], current_datetime).each do |just_inserted|
        sql = just_inserted["sql_text"]
        next unless sql.upcase =~ /^SELECT/ #SQLInjection対策のValidationも行う！！！！！！！！！あとでね
        raw_explain = aggregator.explain_query(sql)
        p raw_explain

        @db.transaction do |trn|
          Nata::Parser.parse_explain(raw_explain).each do |parsed_explain|
            trn.execute(
              "INSERT INTO `explains`(`slow_query_id`,`explain_id`,`select_type`,`table`,`type`,`possible_keys`,`key`,`key`,`ref`,`rows`,`extra`,`created_at`,`updated_at`)
              VALUES(:slow_query_id,:explain_id,:select_type,:table,:type,:possible_keys,:key,:key_len,:ref,:rows,:extra,:created_at,:updated_at)",
              parsed_explain.merge(
                slow_query_id: just_inserted["id"],
                created_at: current_datetime,
                updated_at: current_datetime
              )
            )
          end
        end
      end
    rescue SQLite3::SQLException => e
    rescue SQLite3::BusyException => e # わけなくてもいいか。ロック競合のときだけ何するでもないか、な。。
    ensure
      aggregator.close if aggregator
    end
  end
end
