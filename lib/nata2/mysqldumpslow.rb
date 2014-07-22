require 'nata2'

module Nata2::Mysqldumpslow
  def self.dump(slow_queries, sort_order = 'c')
    summation = {}
    slow_queries.each do |slow_query|
      sql = slow_query[:sql]
      next unless sql
      normarized_sql = normalize(sql)
      summation = sum(summation, normarized_sql, slow_query)
    end

    summarized = summarize(summation)
    sort_summarized(summarized, sort_order)
  end

  private

  def self.normalize(sql)
    sql = sql.gsub(/\b\d+\b/, 'N')
    sql = sql.gsub(/\b0x[0-9A-Fa-f]+\b/, 'N')
    sql = sql.gsub(/''/, %q{'S'})
    sql = sql.gsub(/''/, %q{'S'})
    sql = sql.gsub(/(\\')/, '')
    sql = sql.gsub(/(\\')/, '')
    sql = sql.gsub(/'[^']+'/, %q{'S'})
    sql = sql.gsub(/'[^']+'/, %q{'S'})
    # abbreviate massive "in (...)" statements and similar
    # s!(([NS],){100,})!sprintf("$2,{repeated %d times}",length($1)/2)!eg;
    sql
  end

  def self.sum(summation, normarized_sql, slow_query)
    summation[normarized_sql] ||= {
      count: 0, user: [slow_query[:user]], host: [slow_query[:host]],
      query_time: 0.0, lock_time: 0.0,
      rows_sent: 0, rows_examined: 0,
      raw_sql: slow_query[:sql]
    }

    summation[normarized_sql][:count] += 1
    summation[normarized_sql][:user] << slow_query[:user]
    summation[normarized_sql][:host] << slow_query[:host]
    summation[normarized_sql][:query_time] += slow_query[:query_time]
    summation[normarized_sql][:lock_time] += slow_query[:lock_time]
    summation[normarized_sql][:rows_sent] += slow_query[:rows_sent]
    summation[normarized_sql][:rows_examined] += slow_query[:rows_examined]

    summation
  end

  def self.summarize(summation)
    summation.map do |normarized_sql, c|
      count = c[:count].to_f
      {
        count: count.to_i, user: c[:user].uniq, host: c[:host].uniq,
        average: {
          query_time: c[:query_time]/count, lock_time: c[:lock_time]/count,
          rows_sent: c[:rows_sent]/count, rows_examined: c[:rows_examined]/count
        },
        summation: {
          query_time: c[:query_time], lock_time: c[:lock_time],
          rows_sent: c[:rows_sent], rows_examined: c[:rows_examined]
        },
        normarized_sql: normarized_sql,
        raw_sql: c[:row_sql]
      }
    end
  end

  def self.sort_summarized(summarized, order)
    result = case order
             when 'at'
               summarized.sort_by { |query| query[:average][:query_time] }
             when 'al'
               summarized.sort_by { |query| query[:average][:lock_time] }
             when 'ar'
               summarized.sort_by { |query| query[:average][:rows_sent] }
             when 'c'
               summarized.sort_by { |query| query[:count] }
             when 't'
               summarized.sort_by { |query| query[:summation][:query_time] }
             when 'l'
               summarized.sort_by { |query| query[:summation][:lock_time] }
             when 'r'
               summarized.sort_by { |query| query[:summation][:rows_sent] }
             else
               raise ArgumentError, %q{sort order is either of 'at', 'al', 'ar', 't', 'l', 'r' or 'c'.}
             end

    result.reverse
  end
end
