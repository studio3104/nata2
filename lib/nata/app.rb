require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "kaminari/sinatra"
require "nata/model"

module Nata
  class Application < Sinatra::Base
    configure do
      Slim::Engine.default_options[:pretty] = true
      app_root = File.dirname(__FILE__) + "/../.."
      set :public_folder, app_root + "/public"
      set :views, app_root + "/views"
    end

    configure :development do
      register Sinatra::Reloader
    end

    not_found do
      slim :"error/not_found", layout: false
    end

    get "/" do
      @hostlist = Nata::Model.fetch_hostlist
      slim :index
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

    get "/add_host" do
      slim :add_host
    end

    post "/add_host" do
      # INSERT できなかったとかの例外処理あとで
      Nata::Model.add_host(params)

      slim :add_host_success
    end


    get "/modify_host/:hostname" do
      @configured_value = Nata::Model.fetch_host(params[:hostname])
      slim :modify_host
    end

    post "/modify_host" do
      @referer = request.referer

      # INSERT できなかったとかの例外処理あとで
      Nata::Model.modify_host(params)

      slim :modify_host_success
    end


    post "/delete_host" do
      # 例外あとで
      Nata::Model.delete_host(params[:hostname])

      slim :delete_host
    end


    get "/settings" do
      @configured_settings
      slim :settings
    end
  end
end
