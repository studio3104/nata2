require 'nata2'
require 'nata2/config'
require 'nata2/mysqldumpslow'
require 'nata2/hrforecast'
require 'time'
require 'sequel'

#DB = Sequel.connect(Nata2::Config.get(:dburl), logger: Nata2.logger)
DB = Sequel.connect(Nata2::Config.get(:dburl))#, logger: Nata2.logger)

class Nata2::Data
  def initialize
    @bundles ||= DB.from(:bundles)
    @slow_queries ||= DB.from(:slow_queries)
    @explains ||= DB.from(:explains)
  end

  def find_bundles(service_name: nil, host_name: nil, database_name: nil, sort: false)
    bundles_where = { service_name: service_name, host_name: host_name, database_name: database_name }
    bundles_where.delete_if { |k,v| v.nil? }
    if sort
      @bundles.where(bundles_where).order(:service_name, :host_name, :database_name).all
    else
      @bundles.where(bundles_where).all
    end
  end

  def get_slow_queries(reverse: false, limit: nil, from_datetime: 0, to_datetime: Time.now.to_i, service_name: nil, host_name: nil, database_name: nil)
    bundles_where = { service_name: service_name, host_name: host_name, database_name: database_name }
    bundles_where.delete_if { |k,v| v.nil? }
    bundle_ids = @bundles.select(:id).where(bundles_where).map { |b| b[:id] }

    result = if reverse
                @slow_queries.where(
                  bundle_id: bundle_ids
                ).where {
                  (datetime >= from_datetime) & (datetime <= to_datetime)
                }.reverse_order(
                  :datetime
                ).limit(limit)
              else
                @slow_queries.where(
                  bundle_id: bundle_ids
                ).where {
                  (datetime >= from_datetime) & (datetime <= to_datetime)
                }.limit(limit)
              end

    result.all
  end

  def get_summarized_slow_queries(sort_order, *args)
    Nata2::Mysqldumpslow.dump(get_slow_queries(*args), sort_order)
  end

  def get_explains(type: nil)
  end

  def register_slow_query(service_name, host_name, database_name, slow_query)
    bundles = find_or_create_bundles(service_name, host_name, database_name)
    result = nil
    current_time = Time.now.to_i
    sql = slow_query[:sql] #!!validation!!

    DB.transaction do
      @slow_queries.insert(
        bundle_id: bundles[:id],
        datetime: slow_query[:datetime], user: slow_query[:user], host: slow_query[:host],
        query_time: slow_query[:query_time], lock_time: slow_query[:lock_time],
        rows_sent: slow_query[:rows_sent], rows_examined: slow_query[:rows_examined],
        sql: sql,
        created_at: current_time, updated_at: current_time
      )

      #!!depending on the transaction isolation. verification required.!!
      result = @slow_queries.select(:id).where(bundle_id: bundles[:id]).reverse_order(:id).limit(1).first
    end

    # Provisional implementation
    at_time = Time.at(slow_query[:datetime])
    count = get_slow_queries(
      from_datetime: Time.parse("#{at_time.year}/#{at_time.month}/#{at_time.day} #{at_time.hour}:00").to_i,
      to_datetime: Time.parse("#{at_time.year}/#{at_time.month}/#{at_time.day} #{at_time.hour}:59:59").to_i,
      service_name: service_name, host_name: host_name, database_name: database_name
    ).size
    hrforecast.update(service_name, host_name, database_name, count, datetime: at_time.to_s, color: bundles[:color])
    # Provisional implementation

    result
  end

  def register_explain(slow_query_id, explain)
    result = nil
    current_time = Time.now.to_i

    DB.transaction do
      @explains.where(slow_query_id: slow_query_id).delete
      explain.each do |e|
        @explains.insert(
          slow_query_id: slow_query_id,
          explain_id: e[:id], select_type: e[:select_type],
          table: e[:table], type: e[:type], possible_keys: e[:possible_keys],
          key: e[:key], key_len: e[:key_len], ref: e[:ref], rows: e[:rows], extra: e[:extra],
          created_at: current_time, updated_at: current_time
        )
      end

      @slow_queries.where(id: slow_query_id).update(explain: 'done')
      result = @explains.select(:id, :slow_query_id).where(slow_query_id: slow_query_id).all
    end

    result
  end

  private

  def config(name)
    Nata2::Config.get(name)
  end

  def hrforecast
    @hrforecast ||= Nata2::HRForecast.new(config(:hffqdn), config(:hfport), https: config(:hfhttps))
  end

  def find_or_create_bundles(service_name, host_name, database_name)
    bundles = find_bundles(service_name: service_name, host_name: host_name, database_name: database_name).first
    return bundles if bundles

    DB.transaction do
      current_time = Time.now.to_i
      color = '#' #create random color code
      3.times { color = color + %w{0 1 2 3 4 5 6 7 8 9 a b c d e f}.shuffle.slice(0,2).join }

      @bundles.insert(
        service_name: service_name,
        host_name: host_name,
        database_name: database_name,
        color: color,
        created_at: current_time,
        updated_at: current_time,
      )

      bundles = @bundles.where(service_name: service_name, host_name: host_name, database_name: database_name).first
    end

    bundles
  end

  public

  def self.create_tables
    DB.transaction do
      DB.create_table :bundles do
        primary_key :id, type: Bignum
        String :service_name, null: false
        String :host_name, null: false
        String :database_name, null: false
        String :color, null: false
        DateTime :created_at, null: false
        DateTime :updated_at, null: false
        unique [:service_name, :host_name, :database_name]
      end

      DB.create_table :slow_queries do
        primary_key :id, type: Bignum
        foreign_key :bundle_id, :bundles
        DateTime :datetime, index: true
        String :user
        String :host
        Float :query_time
        Float :lock_time
        Bignum :rows_sent
        Bignum :rows_examined
        String :sql, text: true
        String :explain, default: 'none', null: false # 'none', 'wait' or 'done'
        DateTime :created_at, null: false
        DateTime :updated_at, null: false
      end

      DB.create_table :explains do
        primary_key :id, type: Bignum
        foreign_key :slow_query_id, :slow_queries
        Integer :explain_id, null: false
        String :select_type, null: false
        String :table, null: false
        String :type, null: false
        String :possible_keys
        String :key
        Integer :key_len
        String :ref
        Bignum :rows, null: false
        String :extra, text: true
        DateTime :created_at, null: false
        DateTime :updated_at, null: false
      end
    end
  end

end
