require 'uri'
require 'sinatra/base'
require 'sinatra/reloader'
require 'slim'
require 'kaminari/sinatra'
require 'nata/model'
require 'nata/validator'

module Nata
  class DataInvalidError < StandardError; end
  class Application < Sinatra::Base
    configure do
      Slim::Engine.default_options[:pretty] = true
      app_root = File.dirname(__FILE__) + '/../..'
      set :public_folder, app_root + '/public'
      set :views, app_root + '/views'
    end

    configure :development do
      register Sinatra::Reloader
      set :show_exceptions, false
      set :show_exceptions, :after_handler
    end

    not_found do
      slim :'error/not_found', layout: false
    end

    get '/' do
      @all_hosts_details = Nata::Model.find_all_hosts_details
      slim :index
    end

    def set_page_param(params, referer)
      last_query_strings = URI.parse(referer).query
      return 1 if last_query_strings.blank?
      last_params = Hash[*URI.decode_www_form(last_query_strings).flatten]
      return 1 unless params['type'] == last_params['type']
      params['page']
    end

    post '/view' do
      params['page'] = set_page_param(params, request.referer)
      query_strings = URI.encode_www_form(params)

      if query_strings.match(/(\&|\?)dbs=/)
        query_strings = query_strings.gsub(/(\&|\?)dbs=/, '\1dbs[]=')
      else
        redirect '/?' + query_strings
      end

      if params['type'] == 'history'
        redirect '/history?' + query_strings
      else
        redirect '/summary?' + query_strings
      end
    end

    get '/history' do
      @type = 'history'

      result = []
      params['dbs'].each do |host_db|
        hostname, dbname = host_db.split('\t')
        result << Nata::Model.fetch_slow_queries(hostname, dbname, params['from_date'], params['to_date'])
      end

      result = result.flatten.sort_by { |r| r[:date] }
      @queries_with_explain = Kaminari.paginate_array(result).page(params[:page]).per(20)
      @max_page_num = @queries_with_explain.num_pages
      slim :history
    end

    get '/summary' do
      @type = params['type']

      queries = params['dbs'].map do |host_db|
        hostname, dbname = host_db.split('\t')
        Nata::Model.fetch_slow_queries(hostname, dbname, params['from_date'], params['to_date']) 
      end

      result = Nata::Model.summarize_slow_queries(queries.flatten, @type)
      @summarized_queries = Kaminari.paginate_array(result).page(params[:page]).per(20)
      @max_page_num = @summarized_queries.num_pages
      slim :summary
    end

    error Nata::InvalidPostData do
      status 400
      JSON.generate(error: 1, messages: env['sinatra.error'].message)
    end

    # どの HOST/DB への登録があったのか WEB サーバの LOG からも参照出来るように PATH に含む
    post '/api/1/add/slow_log/:hostname/:dbname' do
      registered_rows = Nata::Model.register_slow_log(
        params[:hostname],
        params[:dbname],
        user: params[:user], host: params[:host],
        query_time: params[:query_time], lock_time: params[:lock_time],
        rows_sent: params[:rows_sent], rows_examined: params[:rows_examined],
        sql: params[:sql],
        date: params[:date]
      )

      JSON.generate({
        error: 0,
        results: registered_rows
      })
    end

    get '/api/1/search/slow_queries' do
    end

    post '/api/1/add/explains' do
    end
  end
end
