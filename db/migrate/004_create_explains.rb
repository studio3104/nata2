class CreateExplains < ActiveRecord::Migration
  def self.up
    create_table :explains do |t|
      t.primary_key :id
      t.integer     :slow_logs_id
      t.integer     :explain_id
      t.string      :select_type
      t.string      :table
      t.string      :type
      t.string      :possible_keys
      t.string      :key
      t.integer     :key_len
      t.string      :ref
      t.integer     :rows
      t.string      :extra
      t.timestamps
    end
  end

  def self.down
    drop_table :explains
  end
end
