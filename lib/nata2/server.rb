require 'nata2'
require 'nata2/data'
require 'nata2/config'
require 'focuslight-validator'

require 'uri'
require 'sinatra/base'
require 'sinatra/json'
require 'slim'
require 'active_support/core_ext'

module Nata2
  class Server < Sinatra::Base
    configure do
      Slim::Engine.default_options[:pretty] = true
      app_root = File.dirname(__FILE__) + '/../..'
      set :public_folder, app_root + '/public'
      set :views, app_root + '/views'
    end

    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
      set :show_exception, false
      set :show_exception, :after_handler
    end

    helpers do
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
          labels[%Q{#{bundle[:database_name]}(#{bundle[:host_name]})}] = bundle[:color]
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

    get '/slow_query/:query_id' do
      @slow_query = data.get_slow_queries(id: params[:query_id]).first
      slim :slow_query
    end

    get '/view/:service_name/:host_name/:database_name' do
      @service_name = params['service_name']
      @host_name = params[:host_name]
      @database_name = params[:database_name]

      @path = request.path


      @labels = labels(@service_name, @host_name, @database_name)
      @time_range = params['t'] || 'w'
      @graph_data = graph_data(@service_name, @host_name, @database_name, @time_range)
      @params = params.except('service_name', 'host_name', 'database_name', 'amp', 'splat', 'captures')
      @root = @params.has_key?('sort') ? 'dump' : 'list'
      slim :view
    end

    get '/view_complex/:service_name/:database_name' do
      @service_name = params['service_name']
      @database_name = params[:database_name]

      @path = request.path


      @labels = labels(@service_name, @host_name, @database_name)
      @time_range = params['t'] || 'w'
      @graph_data = graph_data(@service_name, @host_name, @database_name, @time_range)
      @labels = labels(@service_name, @host_name, @database_name)
      @params = params.except('service_name', 'host_name', 'database_name', 'amp', 'splat', 'captures')
      @root = @params.has_key?('sort') ? 'dump' : 'list'
      slim :view
    end

    get '/dump/:service_name/:host_name/:database_name' do
      sort = params['sort'] || 'c'
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')
      slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name)
      @slow_queries = data.get_summarized_slow_queries(sort, slow_queries)
      slim :dump
    end

    get '/dump_complex/:service_name/:database_name' do
      sort = params['sort'] || 'c'
      service_name = params[:service_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')
      slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, database_name: database_name)
      @slow_queries = data.get_summarized_slow_queries(sort, slow_queries)
      slim :dump
    end

    get '/list/:service_name/:host_name/:database_name' do
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')
      @page = params[:page] ? params[:page].to_i : 1
      @params = params.except('service_name', 'host_name', 'database_name', 'page', 'amp', 'splat', 'captures')
      limit = 101
      offset = limit * (@page - 1) - 1
      offset = offset < 0 ? 0 : offset

      slow_queries = data.get_slow_queries(reverse: true, from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name, limit: limit, offset: offset)
      if slow_queries.size <= 100
        @disabled_next = true
      else
        slow_queries.pop
      end
      @slow_queries_per_day = {}
      slow_queries.each do |slow_query|
        day = Time.at(slow_query[:datetime]).strftime('%Y/%m/%d')
        @slow_queries_per_day[day] ||= []
        @slow_queries_per_day[day] << slow_query
      end

      slim :list
    end

    get '/list_complex/:service_name/:database_name' do
      service_name = params[:service_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')
      @page = params[:page] ? params[:page].to_i : 1
      @params = params.except('service_name', 'host_name', 'database_name', 'page', 'amp', 'splat', 'captures')
      limit = 101
      offset = limit * (@page - 1) - 1
      offset = offset < 0 ? 0 : offset

      slow_queries = data.get_slow_queries(reverse: true, from_datetime: from, service_name: service_name, database_name: database_name, limit: limit, offset: offset)
      if slow_queries.size <= 100
        @disabled_next = true
      else
        slow_queries.pop
      end
      @slow_queries_per_day = {}
      slow_queries.each do |slow_query|
        day = Time.at(slow_query[:datetime]).strftime('%Y/%m/%d')
        @slow_queries_per_day[day] ||= []
        @slow_queries_per_day[day] << slow_query
      end

      slim :list
    end

    get '/' do
      @bundles = {}
      @complex = {}
      data.find_bundles.each do |bundle|
        @bundles[bundle[:service_name]] ||= []
        @bundles[bundle[:service_name]] << { color: bundle[:color], database: bundle[:database_name], host: bundle[:host_name] }
        @complex[bundle[:service_name]] ||= {}
        @complex[bundle[:service_name]][bundle[:database_name]] ||= 0
        @complex[bundle[:service_name]][bundle[:database_name]] += 1
      end
      slim :index
    end

    post '/api/1/:service_name/:host_name/:database_name' do
      req_params = validate(params, {
        service_name: { rule: rule(:not_blank) }, host_name: { rule: rule(:not_blank) }, database_name: { rule: rule(:not_blank) },
        user: { rule: rule(:regexp, /.*/) }, host: { rule: rule(:regexp, /.*/) },
        query_time: { rule: rule(:float) }, lock_time: { rule: rule(:float) },
        rows_sent: { rule: rule(:uint) }, rows_examined: { rule: rule(:uint) },
        sql: { rule: rule(:not_blank) }, datetime: { rule: rule(:natural) }
      })

      if req_params.has_error?
        halt json({ error: 1, messages: req_params.errors })
      end

      req_params = req_params.hash
      result = data.register_slow_query(
        req_params.delete(:service_name),
        req_params.delete(:host_name),
        req_params.delete(:database_name),
        req_params
      )

      result ? json({ error: 0, data: result }) : json({ error: 1, messages: [] })
    end

    post '/api/1/explain/:slow_query_id' do
      slow_query_id = validate(params, { slow_query_id: { rule: rule(:not_blank) } })
      if slow_query_id.has_error?
        halt json({ error: 1, messages: slow_query_id.errors })
      end
      slow_query_id = slow_query_id[:slow_query_id]

      post_spec = {
        id: { rule: rule(:natural) },
        select_type: { rule: rule(:choice,
                                  'SIMPLE', 'PRIMARY',
                                  'UNION', 'UNION RESULT', 'DEPENDENT UNION', 'UNCACHEABLE UNION', # UNION
                                  'SUBQUERY', 'DEPENDENT SUBQUERY', 'UNCACHEABLE SUBQUERY', 'DERIVED' # SUBQUERY
                                 ) },
        table: { rule: rule(:not_blank) },
        type: { rule: rule(:choice, 'system' ,'const', 'eq_ref', 'ref', 'range', 'index', 'ALL') },
        possible_keys: { default: nil }, key: { default: nil }, key_len: { default: nil }, ref: { default: nil },
        rows: { rule: rule(:uint) }, extra: { default: nil },
      }

      explain = []
      explain_error = false
      params[:explain] = JSON.parse(request.body.read)
      if !params[:explain].is_a?(Array)
        halt json({ error:1, messages: [] })
      end
      params[:explain].each do |p|
        record = p.symbolize_keys
        record = record.delete_if { |k,v| v == 'NULL' }
        exp = validate(record, post_spec)
        explain_error = true if exp.has_error?
        explain << exp
      end

      if explain_error
        halt json({ error: 1, messages: explain.map { |exp| exp.errors } })
      end

      result = data.register_explain(slow_query_id, explain)
      result ? json({ error: 0, data: result }) : json({ error: 1, messages: [] })
    end

    get '/docs/api' do
      slim :'docs/api'
    end
  end
end
