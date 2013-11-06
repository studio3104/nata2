require 'time'

module Nata
  class Crawler
    class SlowLogHandler
      class Parser
      class << self
        def slow_queries(plain_slow_queries, last_db = nil, last_datetime = nil)
          result = []

          new.prepare_to_parse_slow_queries(plain_slow_queries).each do |slow_query|
            parsed = new.parse_slow_query(slow_query)

            # use last value if not include in current
            parsed[:db] = last_db unless parsed[:db]
            parsed[:start_time] = last_datetime unless parsed[:start_time]
            last_db = parsed[:db]
            last_datetime = parsed[:start_time]

            result << parsed
          end

          result
        end

        def explain(explain_text)
        end
      end

        def prepare_to_parse_slow_queries(plain_slow_queries, result = [])
          part = []
          messages = plain_slow_queries
          messages = messages.split("\n") unless messages.is_a?(Array)

          # Skip the message that is output when after flush-logs or restart mysqld.
          # e.g.) /usr/sbin/mysqld, Version: 5.5.28-0ubuntu0.12.04.2-log ((Ubuntu)). started with:
          messages.shift while messages.first && !messages.first.start_with?('#')

          while !messages.empty?
            msg = messages.shift
            part << msg
            if msg.end_with?(';') && !msg.upcase.start_with?('USE ', 'SET TIMESTAMP=')
              result << part
              prepare_to_parse_slow_queries(messages, result)
            end
          end

          result
        end

        TIMESTAMP = /^# Time: (\d+)\s+(.+)/
        USER_HOST = /^# User\@Host:\s+(\S+)\s+\@\s+\[?([^\]|\s]+)/
        SQL_COST = /^# Query_time: ([0-9.]+)\s+Lock_time: ([0-9.]+)\s+Rows_sent: ([0-9.]+)\s+Rows_examined: ([0-9.]+).*/
        USE_DB = /^use (\w+);$/
        SET_TIMESTAMP = /^SET timestamp=(\d+);$/
        def parse_slow_query(plain_slow_query)
          plain = plain_slow_query
          record = {}
          message = plain.shift

          if message =~ TIMESTAMP
            record[:start_time] = "20#{$1[0..1]}/#{$1[2..3]}/#{$1[4..5]} #{$2}"
            message = plain.shift
          end

          message =~ USER_HOST
          record[:user] = $1
          record[:host] = $2
          message = plain.shift

          message =~ SQL_COST
          record[:query_time] = $1.to_f
          record[:lock_time] = $2.to_f
          record[:rows_sent] = $3.to_i
          record[:rows_examined] = $4.to_i
          message = plain.shift

          if message =~ USE_DB
            record[:db] = $1
            message = plain.shift
          end

          if message =~ SET_TIMESTAMP
            record[:start_time] = Time.at($1.to_i).strftime("%Y/%m/%d %H:%M:%S")
            message = plain.shift
          end

          record[:sql_text] = message + plain.map { |m| m.strip }.join(' ').sub(' ;', ';')

          record
        end

      end
    end
  end
end
