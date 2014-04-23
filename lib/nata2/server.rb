require 'nata2'
require 'nata2/data'
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
    end

## TEST START ##

    get '/test/register' do
      begin
        Nata2::Data.create_tables
      rescue
      end
      params = {
        service_name: 'service3', host_name: 'host2', database_name: 'database2',
        datetime: Time.now.to_i.to_s,
        user: 'user', host: 'localhost',
        query_time: '2.001227', lock_time: '0.0', rows_sent: '1', rows_examined: '0',
        sql: 'select sleep(2); drop table bundles; drop table slow_queries; drop table explains;'
      }

      req_params = validate(params, {
        service_name: { rule: rule(:not_blank) },
        host_name: { rule: rule(:not_blank) },
        database_name: { rule: rule(:not_blank) },
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

    get '/' do
      json data.get_slow_queries
    end

    get '/ho' do
      json data.get_summarized_slow_queries('c', service_name: 'service3')
    end

## TEST END ##

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
