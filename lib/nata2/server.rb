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

      def hrforecast_ifr_url(service_name, section_name = nil, graph_name = nil, time_range: 'w')
        scheme = config(:hfhttps) ? 'https://' : 'http://'
        base_url = "#{scheme}#{config(:hffqdn)}:#{config(:hfport)}"
        ifr_url = if graph_name
                    "#{base_url}/ifr/nata/#{service_name},#{section_name}/#{graph_name}"
                  else
                    if section_name
                      "#{base_url}/ifr_complex/nata/DATABASES/#{service_name},#{section_name}"
                    else
                      "#{base_url}/ifr_complex/nata/DATABASES/#{service_name}"
                    end
                  end

        if time_range == 'd'
          "#{ifr_url}?t=range&period=86400&graphheader=0&graphlabel=0"
        else
          "#{ifr_url}?t=#{time_range}&graphheader=0&graphlabel=0"
        end
      end

      def graph_data(service_name, host_name, database_name, from)
        slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name)

        from_justified = 0
        now = Time.now.to_i
        (from..now).each do |time|
          if time % 3600 == 0
            from_justified = time
            break
          end
        end

        data = {}
        while now >= from_justified
          period = Time.at(from_justified).strftime('%Y-%m-%d %H:00')
          from_justified += 3600
          data[period] = 0
        end

        slow_queries.each do |slow|
          period = Time.at(slow[:datetime]).strftime('%Y-%m-%d %H:00')
          data[period] ||= 0
          data[period] += 1
        end

        data.map { |period, count| { period: period, %Q{#{database_name}(#{host_name})}.to_sym => count, } }
      end
    end

    get '/slow_query/:query_id' do
      @slow_query = data.get_slow_queries(id: params[:query_id]).first
      slim :slow_query
    end

    get '/dump/:service_name/:host_name/:database_name' do
      sort = params['sort'] || 'c'
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')
      slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name)
      @slow_queries = data.get_summarized_slow_queries(sort, slow_queries)
      @graph_data = graph_data(service_name, host_name, database_name, from)
      @labels = labels(service_name, host_name, database_name)
      slim :dump
      #json @slow_queries.first
    end

    get '/graph/:service_name/:host_name/:database_name' do
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      from = from_datetime(params['t'] || 'w')

      @graph_data = graph_data(service_name, host_name, database_name, from)
      @labels = labels(service_name, host_name, database_name)
      slim :graph
    end

    get '/_list/:service_name/:host_name/:database_name' do
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

      @graph_data = graph_data(service_name, host_name, database_name, from)
      @labels = labels(service_name, host_name, database_name)
      slim :_list
    end

    get '/' do
      @hosts_of = {}
      data.find_bundles.each do |bundle|
        @hosts_of[bundle[:service_name]] ||= {}
        @hosts_of[bundle[:service_name]][bundle[:host_name]] ||= []
        unless @hosts_of[bundle[:service_name]][bundle[:host_name]].include?(bundle[:database_name])
          @hosts_of[bundle[:service_name]][bundle[:host_name]] << bundle[:database_name]
        end
      end
      slim :index
    end

    get '/__view' do
      @slow_queries = data.get_slow_queries(id: params[:id])
      slim :view
    end

    get '/view/:service_name/:host_name/:database_name' do
      @service_name = params['service_name']
      @host_name = params[:host_name]
      @database_name = params[:database_name]
      @labels = labels(@service_name, @host_name, @database_name)
      @time_range = params['t'] || 'w'
      @graph_url = hrforecast_ifr_url(@service_name, @host_name, @database_name, time_range: @time_range)
      from = from_datetime(params['t'] || 'w')
      @graph_data = graph_data(@service_name, @host_name, @database_name, from)
      @labels = labels(@service_name, @host_name, @database_name)
      @params = params.except('service_name', 'host_name', 'database_name', 'amp', 'splat', 'captures')
      @root = @params.has_key?('sort') ? 'dump' : '_list'
      slim :view
    end

    post '/api/1/:service_name/:host_name/:database_name' do
      req_params = validate(params, {
        service_name: { rule: rule(:not_blank) }, host_name: { rule: rule(:not_blank) }, database_name: { rule: rule(:not_blank) },
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
  end
end
