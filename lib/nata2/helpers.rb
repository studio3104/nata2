require 'nata2/config'
require 'focuslight-validator'

module Nata2::Helpers
  def validate(*args)
    Focuslight::Validator.validate(*args)
  end

  def rule(*args)
    Focuslight::Validator.rule(*args)
  end

  def data
    @data ||= Nata2::Data.new
  end

  def config(name)
    Nata2::Config.get(name)
  end

  def labels(service_name, host_name, database_name)
    bundles = data.find_bundles(service_name: service_name, host_name: host_name, database_name: database_name)
    labels = {}
    bundles.each do |bundle|
      name = %Q{#{bundle[:database_name]}(#{bundle[:host_name]})}
      labels[name] = { color: bundle[:color], path: %Q{/view/#{bundle[:service_name]}/#{bundle[:host_name]}/#{bundle[:database_name]}} }
    end
    labels
  end

  def from_datetime(time_range)
    now = Time.now.to_i
    case time_range
    when 'd' then now - 86400
    when 'w' then now - 86400 * 7
    when 'm' then now - 86400 * 30
    when 'y' then now - 86400 * 365
    else
      halt
    end
  end

  def get_graph_data(service_name, host_name, database_name, time_range)
    from = from_datetime(time_range)
    graph_data = data.get_slow_queries_count_by_period(
      per_day: time_range == 'y', from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name
    )
    return [] if graph_data.empty?

    #{"service_name":"service_name","host_name":"host_name2","database_name":"database_name","period":1431082800,"count":4}

    period_column_name, fmt_strftime, plot_per = if time_range == 'y'
      [ :period_per_day, '%Y-%m-%d', 3600 * 24 ]
    else
      [ :period_per_hour, '%Y-%m-%d %H:00', 3600 ]
    end

    graph_data = graph_data.to_a.group_by { |gd| gd[period_column_name] }
    temp = graph_data.max_by { |_, gd| gd.size }
    template = {}
    temp.last.each { |tmp|
      template.merge!({
        %Q{#{tmp[:database_name]}(#{tmp[:host_name]})}.to_sym => 0
      })
    }
    result = []
    period = graph_data.min_by { |prd, _| prd }.first
    max_period = graph_data.max_by { |prd, _| prd }.first
    while period <= max_period do
      tgd = template.merge(period: Time.at(period).strftime(fmt_strftime))
      graph_data[period].each do |gd|
        tgd = tgd.merge({ %Q{#{gd[:database_name]}(#{gd[:host_name]})}.to_sym => gd[:count] })
      end
      period += plot_per
      result << tgd
    end
    return result
  end
end
