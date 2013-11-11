require 'parallel'
require 'logger'

module Nata
  class Crawler
    def self.run(crawl_interval = 300) #sec
      @logger = Nata::Logger.new
      @interval = crawl_interval
      Thread.new(&method(:execute))
    end

    def self.execute
      loop do
        Parallel.each(Host.all, in_threads: Parallel.processor_count) do |host_info|
          begin
            aggregator = Nata::Crawler::Aggregator.new(host_info)
          rescue => e # Net::SSH.start のときの例外。あとで明示。
            @logger.error(host_info.name) { e.message }
            next
          end

          log_text = fetch_slow_log_text(aggregator)
          next unless log_text

          Parser.parse_slow_queries(log_text).each do |parsed_slow_query|
            parsed_slow_query[:host_id] = host_info.id
            begin
              slow_query = SlowQuery.create!(parsed_slow_query)
            rescue => e # 例外クラスはあとで書く
              @logger.error(host_info.name) { e.message }
            end

            next unless slow_query || slow_query[:sql_text] || slow_query[:sql_text].upcase.start_with?("SELECT ")

            # EXPLAIN
            # 全部の SELECT 句を EXPLAIN するかサマライズとかしてからにするか

            # とりあえず一旦全部の SELECT 句を EXPLAIN しとく
            explain_text = aggregator.explain_query(slow_query[:sql_text])

            Parser.parse_explain(explain_text).each do |parsed_explain|
              parsed_explain[:slow_logs_id] = slow_query.id
              begin
                Explain.create!(parsed_explain)
              rescue => e # 例外クラスはあとで書く
                @logger.error(host_info.name) { e.message }
              end
            end
          end

          aggregator.close
        end

        sleep @interval
      end
    rescue => e
      p e.class
      p e.message
      p e.backtrace
    end


    # 差分とか増分とか全文とか判別
    def self.fetch_slow_log_text(aggregator)
      host_info = aggregator.host_info
      log_file_info = SlowLogFile.where(host_id: host_info.id).first
      slow_log_path = aggregator.fetch_slow_log_file_path

      # 対象ホストへの初回クロールは情報の登録だけ行う
      # スローログファイルがすでに数GB 級のサイズだったらドカンととることになるので、そうならんように
      if log_file_info.nil?
        begin
          SlowLogFile.create!(
            host_id: host_info.id,
            inode: aggregator.fetch_file_inode(slow_log_path),
            last_checked_line: aggregator.fetch_file_lines(slow_log_path),
          )
        rescue => e # 例外クラスはあとで書く
          @logger.error(host_info.name) { e.message }
          return nil
        end
      end

      current_inode = aggregator.fetch_file_inode(slow_log_path)
      current_lines = aggregator.fetch_file_lines(slow_log_path)
      incremental_lines = current_lines - log_file_info.last_checked_line

      if log_file_info.inode == current_inode
        slow_query = aggregator.fetch_incremental_text(slow_log_path, incremental_lines)
      else
        slow_query = aggregator.fetch_full_text(slow_log_path)

        old_file_path = aggregator.fetch_file_path_by_inode(log_file_info.inode, slow_log_path)
        if !old_file_path.nil?
          slow_query = aggregator.fetch_incremental_text(old_file_path, incremental_lines) + slow_query
        else
          @logger.error(host_info.name) { "" }
        end

        log_file_info.inode = current_inode
      end

      log_file_info.last_checked_line = current_lines
      log_file_info.save!
      slow_query
    end
  end
end
