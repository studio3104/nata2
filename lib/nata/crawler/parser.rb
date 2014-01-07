require "time"

module Nata
  class Parser
    def self.parse_slow_queries(plain_slow_queries, last_db = nil, last_datetime = nil)
      result = []

      split_slow_queries(plain_slow_queries).each do |slow_query|
        parsed = parse_slow_query(slow_query)

        # use last value if not include in current
        parsed[:db] = last_db unless parsed[:db]
        parsed[:date] = last_datetime unless parsed[:date]
        last_db = parsed[:db]
        last_datetime = parsed[:date]

        result << parsed
      end

      result
    end

    def self.parse_explain(explain_text)
      # id    select_type    table    type    possible_keys    key    key_len    ref    rows    Extra
      # 1     SIMPLE         user     ALL     NULL             NULL   NULL       NULL   5

      result = []
      plain_explain_text = explain_text.chomp.split("\n")
      keys = plain_explain_text.shift.chomp.split(/\s+/)
      keys[0] = "explain_id"

      plain_explain_text.each do |explain_values|
        record = {}
        values = explain_values.chomp.split(/\s+/)

        keys.each do |key|
          value = values.shift
          value = nil if value == "NULL"
          value = value.to_i if !value.nil? && [ "explain_id", "key_len", "rows" ].include?(key)
          record[key.downcase.to_sym] = value
        end

        result << record
      end

      result
    end

    def self.split_slow_queries(plain_slow_queries, result = [])
      part = []
      messages = plain_slow_queries
      messages = messages.split("\n") unless messages.is_a?(Array)

      # Skip the message that is output when after flush-logs or restart mysqld.
      # e.g.) /usr/sbin/mysqld, Version: 5.5.28-0ubuntu0.12.04.2-log ((Ubuntu)). started with:
      messages.shift while messages.first && !messages.first.start_with?("#")

      while !messages.empty?
        msg = messages.shift.strip
        part << msg
        if msg.end_with?(";") && !msg.upcase.start_with?("USE ", "SET TIMESTAMP=")
          result << part
          split_slow_queries(messages, result)
        end
      end

      result
    end


    # ここ、マッチしなかった時のこととかまったく考えてない感じで雑なので
    # あとでちゃんとした感じに直す
    TIMESTAMP = /^# Time: (\d+)\s+(.+)/
    USER_HOST = /^# User\@Host:\s+(\S+)\s+\@\s+\[?([^\]|\s]+)/
    SQL_COST = /^# Query_time: ([0-9.]+)\s+Lock_time: ([0-9.]+)\s+Rows_sent: ([0-9.]+)\s+Rows_examined: ([0-9.]+).*/
    USE_DB = /^use (\w+);$/
    SET_TIMESTAMP = /^SET timestamp=(\d+);$/
    def self.parse_slow_query(plain_slow_query)
      plain = plain_slow_query
      record = {}
      message = plain.shift

      if message =~ TIMESTAMP
        record[:date] = "20#{$1[0..1]}/#{$1[2..3]}/#{$1[4..5]} #{$2}"
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
        record[:date] = Time.at($1.to_i).strftime("%Y/%m/%d %H:%M:%S")
        message = plain.shift
      end

      record[:sql] = message + plain.map { |m| m.strip }.join(" ").sub(" ;", ";") if message
      record[:sql] = record[:sql].sub(/;$/,'')

      record
    end

  end
end

__END__
require 'json'
require 'net/http'
require 'uri'
require 'awesome_print'
Nata::Parser.parse_slow_queries(File.read('/Users/JP11546/m_slow.log'), 'line_manga').each do |slow|
#  slow.delete(:sql)
#  ap slow
  url = 'http://localhost:9292/api/1/add/slow_log/dbm201.manga.line/line_manga'
  response = Net::HTTP.post_form(URI.parse(url), slow)

  raise "#{response.body}" unless  response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body, symbolize_names: true)
end
