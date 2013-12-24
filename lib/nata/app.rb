require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "kaminari/sinatra"
require "nata/model"
require "nata/validator"

module Nata
  class DataInvalidError < StandardError; end
  class Application < Sinatra::Base
    configure do
      Slim::Engine.default_options[:pretty] = true
      app_root = File.dirname(__FILE__) + "/../.."
      set :public_folder, app_root + "/public"
      set :views, app_root + "/views"
    end

    configure :development do
      register Sinatra::Reloader
      set :show_exceptions, false
      set :show_exceptions, :after_handler
    end

    not_found do
      slim :"error/not_found", layout: false
    end

    get "/" do
      @hostlist = Nata::Model.fetch_hostlist
      slim :index
    end

    get '/test/:unko' do
      d = Nata::Validator.validate_datetime(params[:unko])
      d.first.to_s
    end

    get "/summary/:hostname" do
      @hostlist = Nata::Model.fetch_hostlist
      @current_hostname = params[:hostname]
      @current_sort_order = params[:sort]
      @summarized_queries = Nata::Model.summarize_slow_queries(
        @current_hostname,
        params[:limit],
        params[:from],
        params[:to],
        @current_sort_order
      )

#      @summarized_queries = Kaminari.paginate_array(summarized_queries).page(params[:page]).per(5)
      slim :summary
    end

    get "/history/:hostname" do
      @hostlist = Nata::Model.fetch_hostlist
      @current_hostname = params[:hostname]
      @queries_with_explain = Nata::Model.fetch_slow_queries_with_explain(
        params[:hostname],
        params[:limit],
        params[:from],
        params[:to]
      )

      slim :history
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

    get "/api/1/search/slow_queries" do
    end

    post "/api/1/add/explains" do
    end
  end
end
