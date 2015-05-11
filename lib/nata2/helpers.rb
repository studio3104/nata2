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
      from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name
    )

    #{"service_name":"service_name","host_name":"host_name2","database_name":"database_name","period":1431082800,"count":4}

    graph_data = graph_data.to_a.group_by { |gd| gd[:period] }
    result = []
    graph_data.each do |period, gdata|
      tgd = { period: Time.at(period).strftime('%Y-%m-%d %H:00') }
      gdata.each do |gd|
        tgd = tgd.merge({ %Q{#{gd[:database_name]}(#{gd[:host_name]})}.to_sym => gd[:count] })
      end
      result << tgd
    end
    return result

    # TODO: plot zero if value is nothing
    plot_per, strftime_format = if time_range == 'y'
                                  [3600 * 24, '%Y-%m-%d']
                                else
                                  [3600, '%Y-%m-%d %H:00']
                                end
  end
end
