require 'uri'
require 'sinatra/base'
require 'sinatra/reloader'
require 'slim'
require 'rdiscount'
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

    get '/select_host' do
      @all_hosts_details = Nata::Model.find_all_hosts_details
      slim :select_host
    end

    get '/select_group' do
      @all_groups_details = Nata::Model.find_all_groups_details
      slim :select_group
    end

    get '/setting_group' do
      @all_groups_details = Nata::Model.find_all_groups_details
      slim :setting_group
    end

    post '/select_hosts_in_group' do
      choiced_group_name = params['name']
      redirect '/setting_group' if choiced_group_name.blank?
      group = Nata::Model.find_or_create_group(choiced_group_name)
      @group_name = group[:name]
      @group_member = Nata::Model.find_group_members(group[:id])
      @all_hosts_details = Nata::Model.find_all_hosts_details
      slim :select_hosts_in_group
    end

    post '/constitute_group' do
      Nata::Model.constitute_group(params['name'], params['database_ids'])
      redirect '/setting_group?behavior=constitute'
    end

    post '/delete_group' do
      if params['behavior'] == 'confirmed'
        Nata::Model.delete_group(params['name'])
        redirect '/setting_group?behavior=delete'
      end

      group = Nata::Model.find_group(params['name'])
      @group_name = group[:name]
      @group_member = Nata::Model.find_group_members(group[:id])
      slim :delete_group
    end

    post '/setting_group' do
      Nata::Model.setting_group(params['group_id'], params['database_ids'])

      slim :setting_group
    end

    get '/' do
      @recent_slow_queries = Nata::Model.fetch_recent_slow_queries

      db_info = {}
      @recent_slow_queries.each do |rs|
        db_info[rs[:database_id]] = {
          rgb: rs[:rgb],
          hostname: rs[:host_name],
          dbname: rs[:database_name]
        }
      end

      @graph_labels, @graph_datasets = Nata::Model.generate_recent_chart_datasets(db_info)
      slim :index
    end

    def set_page_param(params, referer)
      # from_date, to_date, type のいずれかが変わってたら page を 1 にリセットする
      last_query_strings = URI.parse(referer).query
      return 1 if last_query_strings.blank?

      last_params = Hash[*URI.decode_www_form(last_query_strings).flatten]

      if params['from_date'] == last_params['from_date'] && params['to_date'] == last_params['to_date'] && params['type'] == last_params['type']
        params['page']
      else
        1
      end
    end

    post '/view' do
      params['page'] = set_page_param(params, request.referer)

      unless params['group'].blank?
        if group = Nata::Model.find_group(params['group'])
          params['dbs'] = []
          Nata::Model.find_group_members(group[:id]).each do |hostname, databases|
            databases.each do |database|
              params['dbs'] << hostname + '\t' + database
            end
          end
        end
      end

      query_strings = URI.encode_www_form(params)

      # データベースの選択がされていない場合はトップにリダイレクト
      # js でチェックがない場合ボタンを無効にする、とかにしたほうがいいかも
      redirect '/select_host' unless query_strings.match(/(\&|\?)dbs=/)

      # sinatra は同名のパラメタを扱う場合 name[] のようにしてあげる必要がある
      query_strings = query_strings.gsub(/(\&|\?)dbs=/, '\1dbs[]=')

      if params['type'] == 'history'
        redirect '/history?' + query_strings
      else
        redirect '/summary?' + query_strings
      end
    end

    post '/view_group' do

    end

    get '/history' do
      @type = 'history'

      result = []
      graph_data_components = {}
      params['dbs'].each do |host_db|
        hostname, dbname = host_db.split('\t')
        current_result = Nata::Model.fetch_slow_queries(hostname, dbname, params['from_date'], params['to_date'])
        result << current_result
        if current_result.first
          graph_data_components[current_result.first[:database_id]] = {
            rgb: current_result.first[:rgb],
            hostname: hostname,
            dbname: dbname
          }
        end
      end

      result = result.flatten.sort_by { |r| r[:date] }.reverse
      @queries_with_explain = Kaminari.paginate_array(result).page(params[:page]).per(20)
      @max_page_num = @queries_with_explain.num_pages
      @graph_labels, @graph_datasets = Nata::Model.generate_recent_chart_datasets(graph_data_components, 4)
      slim :history
    end

    get '/summary' do
      @type = params['type']

      queries = []
      graph_data_components = {}
      databases_colorcode = {}
      params['dbs'].each do |host_db|
        hostname, dbname = host_db.split('\t')
        current_result = Nata::Model.fetch_slow_queries(hostname, dbname, params['from_date'], params['to_date'])
        queries << current_result
        if current_result.first
          rgb = current_result.first[:rgb]
          graph_data_components[current_result.first[:database_id]] = {
            rgb: rgb,
            hostname: hostname,
            dbname: dbname
          }
          databases_colorcode["#{dbname} (#{hostname})"] = '#' + rgb.split(',').map { |i| format('%02x', i.to_i) }.join('')
        end
      end

      result = Nata::Model.summarize_slow_queries(queries.flatten, @type)
      @summarized_queries = Kaminari.paginate_array(result).page(params[:page]).per(20)
      @databases_colorcode = databases_colorcode
      @max_page_num = @summarized_queries.num_pages
      @graph_labels, @graph_datasets = Nata::Model.generate_recent_chart_datasets(graph_data_components, 4)
      slim :summary
    end

    error Nata::InvalidPostData do
      status 400
      JSON.generate(error: 1, messages: env['sinatra.error'].message)
    end

    get '/docs/api' do
      @url_add_slow_log = request.scheme + '://' + request.host + '/api/1/add/slow_log/:hostname/:dbname'
      slim :'docs/api'
    end

    # どの HOST/DB への登録があったのか WEB サーバの LOG からも参照出来るように PATH に含む
    post '/api/1/add/slow_log/:hostname/:dbname' do
      registered_rows = Nata::Model.register_slow_log(
        params[:hostname],
        params[:dbname],
        user: params[:user], host: params[:host], long_query_time: params[:long_query_time],
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
