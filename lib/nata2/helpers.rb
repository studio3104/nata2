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

  def graph_data(service_name, host_name, database_name, time_range)
    from = from_datetime(time_range)
    slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name)
    plot_per, strftime_format = if time_range == 'y'
                                  [3600 * 24, '%Y-%m-%d']
                                else
                                  [3600, '%Y-%m-%d %H:00']
                                end

    from_justified = 0
    now = Time.now.to_i
    (from..now).each do |time|
      if time % plot_per == 0
        from_justified = time
        break
      end
    end

    bundles = data.find_bundles(service_name: service_name, host_name: host_name, database_name: database_name)
    db_names = bundles.map { |s| %Q{#{s[:database_name]}(#{s[:host_name]})} }
    data = {}
    db_names.each do |db_name|
      __from = from_justified
      while now >= __from
        period = Time.at(__from).strftime(strftime_format)
        __from += plot_per
        data[period] ||= {}
        data[period][db_name] = 0
      end
    end

    slow_queries.each do |slow|
      period = Time.at(slow[:datetime]).strftime(strftime_format)
      db_name = %Q{#{slow[:database_name]}(#{slow[:host_name]})}
      data[period] ||= {}
      data[period][db_name] ||= 0
      data[period][db_name] += 1
    end

    data.map { |period, count_of| { period: period }.merge(count_of) }
  end
end
