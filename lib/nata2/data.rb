require 'nata2'
require 'nata2/config'
require 'nata2/mysqldumpslow'
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

  def find_bundles(service_name: nil, host_name: nil, database_name: nil)
    bundles_where = { service_name: service_name, host_name: host_name, database_name: database_name }
    bundles_where.delete_if { |k,v| v.nil? }
    @bundles.where(bundles_where).order(:service_name, :database_name, :host_name).all
  end

  def get_slow_queries(
    id: nil, sort_by_date: false, limit: nil, offset: nil, 
    from_datetime: 0, to_datetime: Time.now.to_i,
    service_name: nil, host_name: nil, database_name: nil
  )
    bundles_where = { service_name: service_name, host_name: host_name, database_name: database_name }
    bundles_where.delete_if { |k,v| v.nil? }
    slow_queries_where = id ? { slow_queries__id: id } : {}

    result = if sort_by_date
                @bundles.where(bundles_where).left_outer_join(
                  :slow_queries, bundle_id: :id
                ).where(
                  slow_queries_where
                ).where {
                  (datetime >= from_datetime) & (datetime <= to_datetime)
                }.reverse_order(
                  :datetime
                ).limit(limit).offset(offset)
              else
                @bundles.where(bundles_where).left_outer_join(
                  :slow_queries, bundle_id: :id
                ).where(
                  slow_queries_where
                ).where {
                  (datetime >= from_datetime) & (datetime <= to_datetime)
                }.limit(limit).offset(offset)
              end
    result.all
  end

  def get_summarized_slow_queries(sort_order, slow_queries)
    Nata2::Mysqldumpslow.dump(slow_queries, sort_order)
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

  def find_or_create_bundles(service_name, host_name, database_name)
    bundles = find_bundles(service_name: service_name, host_name: host_name, database_name: database_name).first
    return bundles if bundles

    DB.transaction do
      current_time = Time.now.to_i
      color = '#' #create random color code
      6.times { color = color + %w{0 1 2 3 4 5 6 7 8 9 a b c d e f}.shuffle.first }

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
end
