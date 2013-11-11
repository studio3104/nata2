class CreateSlowQueries < ActiveRecord::Migration
  def self.up
    create_table :slow_queries do |t|
      t.primary_key :id
      t.integer     :host_id
      t.datetime    :start_time
      t.string      :user
      t.string      :host
      t.float       :query_time
      t.float       :lock_time
      t.integer     :rows_sent
      t.integer     :rows_examined
      t.string      :db
      t.string      :sql_text
      t.timestamps
    end
  end

  def self.down
    drop_table :slow_queries
  end
end
