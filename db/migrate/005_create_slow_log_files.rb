class CreateSlowLogFiles < ActiveRecord::Migration
  def self.up
    create_table :slow_log_files do |t|
      t.primary_key :id
      t.integer     :host_id, null: false
      t.integer     :inode, null: false
      t.integer     :last_checked_line
      t.timestamps
    end

    add_index :slow_log_files, :host_id, unique: true
  end

  def self.down
    drop_table :slow_log_files
  end
end
