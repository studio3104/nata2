class CreateHosts < ActiveRecord::Migration
  def self.up
    create_table :hosts do |t|
      t.primary_key :id
      t.string      :name, null: false
      t.string      :ipadress
      t.string      :ssh_username
      t.string      :ssh_options
      t.string      :mysql_command
      t.string      :mysql_username
      t.string      :mysql_password
      t.string      :mysql_port
      t.timestamps
    end

    add_index :hosts, :name, unique: true
  end

  def self.down
    drop_table :hosts
  end
end
