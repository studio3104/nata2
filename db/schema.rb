# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 6) do

  create_table "explains", :force => true do |t|
    t.integer  "slow_logs_id"
    t.integer  "explain_id"
    t.string   "select_type"
    t.string   "table"
    t.string   "type"
    t.string   "possible_keys"
    t.string   "key"
    t.integer  "key_len"
    t.string   "ref"
    t.integer  "rows"
    t.string   "extra"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

  create_table "hosts", :force => true do |t|
    t.string   "name",           :null => false
    t.string   "ipadress"
    t.string   "ssh_username"
    t.string   "ssh_options"
    t.string   "mysql_command"
    t.string   "mysql_username"
    t.string   "mysql_password"
    t.string   "mysql_port"
    t.datetime "created_at",     :null => false
    t.datetime "updated_at",     :null => false
  end

  add_index "hosts", ["name"], :name => "index_hosts_on_name", :unique => true

  create_table "slow_log_files", :force => true do |t|
    t.integer  "host_id",           :null => false
    t.string   "fullpath",          :null => false
    t.integer  "inode",             :null => false
    t.integer  "last_checked_line"
    t.string   "last_db"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
  end

  add_index "slow_log_files", ["host_id"], :name => "index_slow_log_files_on_host_id", :unique => true

  create_table "slow_logs", :force => true do |t|
    t.integer  "host_id"
    t.datetime "start_time"
    t.string   "user"
    t.string   "host"
    t.float    "query_time"
    t.float    "lock_time"
    t.integer  "rows_sent"
    t.integer  "rows_examined"
    t.string   "db"
    t.string   "sql_text"
    t.datetime "created_at",    :null => false
    t.datetime "updated_at",    :null => false
  end

end
