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
        Parallel.each(Host.all, in_threads: Parallel.processor_count) do |host|
          begin
            aggregator = Nata::Crawler::Aggregator.new(host)
          rescue # Net::SSH.start のときの例外。あとで明示。
            @logger.err(host.name) { "" }
            next
          end

          # 差分とか増分とか全文とか、
          # どれほどのテキストを持ってくるかは、Aggregator にお任せする
          log_text = aggregator.fetch_slow_log_text(log_path)
          next unless log_text

          Parser.parse_slow_queries(log_text).each do |parsed_slow_query|
            parsed_slow_query[:host_id] = host.id
            begin
              slow_query = SlowQuery.create!(parsed_slow_query)
            rescue # 例外クラスはあとで書く
              @logger.err(host.name) { "" }
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
              rescue # 例外クラスはあとで書く
                @logger.err(host.name) { "" }
              end
            end
          end

          aggregator.close
        end

        sleep @interval
      end
    end
  end
end
