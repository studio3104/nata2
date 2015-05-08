require 'nata2'
require 'nata2/data'
require 'nata2/helpers'
require 'json'
require 'base64'
require 'uri'
require 'sinatra/base'
require 'sinatra/json'
require 'slim'

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

    SUPPRESS_KEYS_TO_OPTIMIZE = %w[ service_name host_name database_name page amp splat captures ]
    helpers do
      def optimize_params(_params)
        params = _params.dup
        SUPPRESS_KEYS_TO_OPTIMIZE.each { |key| params.delete(key) }
        params
      end

      include Nata2::Helpers
    end

    not_found do
      '<b><font size="7">404</font></b>'
    end

    get '/slow_query/:query_id' do
      @slow_query = data.get_slow_queries(id: params[:query_id]).first
      raise Sinatra::NotFound unless @slow_query
      slim :slow_query
    end

    get '/dumped_query/:dumped_query_base64encoded' do
      begin
        @dumped_query = JSON.parse(Base64.decode64(params[:dumped_query_base64encoded]), symbolize_names: true)
      rescue JSON::ParserError
        raise Sinatra::NotFound
      end
      slim :dumped_query
    end

    get '/view/:service_name/:host_name/:database_name' do
      @service_name = params['service_name']
      @host_name = params[:host_name]
      @database_name = params[:database_name]
      bundles = data.find_bundles(service_name: @service_name, host_name: @host_name, database_name: @database_name)
      raise Sinatra::NotFound if bundles.empty?
      @time_range = params['t'] || 'w'
      @graph_data = graph_data(@service_name, @host_name, @database_name, @time_range)
      @path = request.path
      @labels = labels(@service_name, @host_name, @database_name)
      @params = optimize_params(params)
      @root = @params.has_key?('sort') ? 'dump' : 'list'
      slim :view
    end

    get '/view_complex/:service_name/:database_name' do
      @service_name = params['service_name']
      @database_name = params[:database_name]
      bundles = data.find_bundles(service_name: @service_name, database_name: @database_name)
      raise Sinatra::NotFound if bundles.empty?
      @path = request.path
      @labels = labels(@service_name, @host_name, @database_name)
      @time_range = params['t'] || 'w'
      @graph_data = graph_data(@service_name, @host_name, @database_name, @time_range)
      @params = optimize_params(params)
      @root = @params.has_key?('sort') ? 'dump' : 'list'
      slim :view
    end

    get '/dump/:service_name/:host_name/:database_name' do
      sort = params['sort'] || 'c'
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      bundles = data.find_bundles(service_name: service_name, host_name: host_name, database_name: database_name)
      raise Sinatra::NotFound if bundles.empty?
      from = from_datetime(params['t'] || 'w')
      slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name)
      @slow_queries = data.get_summarized_slow_queries(sort, slow_queries)
      slim :dump
    end

    get '/dump_complex/:service_name/:database_name' do
      sort = params['sort'] || 'c'
      service_name = params[:service_name]
      database_name = params[:database_name]
      bundles = data.find_bundles(service_name: service_name, database_name: database_name)
      raise Sinatra::NotFound if bundles.empty?
      from = from_datetime(params['t'] || 'w')
      slow_queries = data.get_slow_queries(from_datetime: from, service_name: service_name, database_name: database_name)
      @slow_queries = data.get_summarized_slow_queries(sort, slow_queries)
      slim :dump
    end

    get '/list/:service_name/:host_name/:database_name' do
      service_name = params[:service_name]
      host_name = params[:host_name]
      database_name = params[:database_name]
      bundles = data.find_bundles(service_name: service_name, host_name: host_name, database_name: database_name)
      raise Sinatra::NotFound if bundles.empty?
      from = from_datetime(params['t'] || 'w')
      @page = params[:page] ? params[:page].to_i : 1
      @params = optimize_params(params)
      limit = 101
      offset = limit * (@page - 1) - 1
      offset = offset < 0 ? 0 : offset

      slow_queries = data.get_slow_queries(sort_by_date: true, from_datetime: from, service_name: service_name, host_name: host_name, database_name: database_name, limit: limit, offset: offset)
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
      bundles = data.find_bundles(service_name: service_name, database_name: database_name)
      raise Sinatra::NotFound if bundles.empty?
      from = from_datetime(params['t'] || 'w')
      @page = params[:page] ? params[:page].to_i : 1
      @params = optimize_params(params)
      limit = 101
      offset = limit * (@page - 1) - 1
      offset = offset < 0 ? 0 : offset

      slow_queries = data.get_slow_queries(sort_by_date: true, from_datetime: from, service_name: service_name, database_name: database_name, limit: limit, offset: offset)
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
      complex = {}
      data.find_bundles.each do |bundle|
        service, database = [ bundle[:service_name], bundle[:database_name] ]
        @bundles[service] ||= []
        @bundles[service] << { color: bundle[:color], database: database, host: bundle[:host_name] }
        @complex[service] ||= []
        next if @complex[service].include?(database)
        complex[service] ||= {}
        complex[service][database] ||= 0
        complex[service][database] += 1
        @complex[service] << database if complex[service][database] > 1
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
        halt 400, JSON.generate(error: 1, messages: req_params.errors)
      end

      req_params = req_params.hash
      result = data.register_slow_query(
        req_params.delete(:service_name),
        req_params.delete(:host_name),
        req_params.delete(:database_name),
        req_params
      )

      result ? JSON.generate(error: 0, data: result) : JSON.generate(error: 1, messages: [])
    end

    post '/api/1/explain/:slow_query_id' do
      slow_query_id = validate(params, { slow_query_id: { rule: rule(:not_blank) } })
      if slow_query_id.has_error?
        halt 400, json({ error: 1, messages: slow_query_id.errors })
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
        halt 400, json({ error:1, messages: [] })
      end
      params[:explain].each do |p|
        record = p.symbolize_keys
        record = record.delete_if { |k,v| v == 'NULL' }
        exp = validate(record, post_spec)
        explain_error = true if exp.has_error?
        explain << exp
      end

      if explain_error
        halt 400, json({ error: 1, messages: explain.map { |exp| exp.errors } })
      end

      result = data.register_explain(slow_query_id, explain)
      result ? json({ error: 0, data: result }) : json({ error: 1, messages: [] })
    end

    get '/docs/api' do
      slim :'docs/api'
    end
  end
end
