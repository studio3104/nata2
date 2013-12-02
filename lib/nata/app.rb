require "sinatra"
require "sinatra/reloader"
require "slim"
require "nata/model"

module Nata
  class Application < Sinatra::Base
    configure do
      app_root = File.dirname(__FILE__) + "/../.."
      set :public_folder, app_root + "/public"
      set :views, app_root + "/views"
    end


    get "/" do
      @hostlist = Nata::Model.fetch_hostlist
      slim :index
    end

    get "/summary/:hostname" do
      @hostlist = Nata::Model.fetch_hostlist
      @current_hostname = params[:hostname]
      @sort_order = params[:sort]
      @summarized_queries = Nata::Model.summarize_slow_queries(
        @current_hostname,
        params[:limit],
        params[:from],
        params[:to],
        @sort_order
      )
      slim :summary
    end

    get "/history/:hostname" do
      @hostlist = Nata::Model.fetch_hostlist
      @current_hostname = params[:hostname]
      @queries = Nata::Model.fetch_slow_queries(
        params[:hostname],
        params[:limit],
        params[:from],
        params[:to]
      )
      slim :history
    end
  end
end
