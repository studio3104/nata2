require 'mysql2-cs-bind'

module Nata
  class Schema
    db_dir = File.join(File.dirname(__FILE__), '..', '..', 'db')
    @db = case ENV['RACK_ENV']
         when 'production'
           SQLite3::Database.new(db_dir + '/production.db')
         when 'test'
           SQLite3::Database.new(db_dir + '/test.db')
         else
           SQLite3::Database.new(db_dir + '/development.db')
         end
    @db.execute('PRAGMA foreign_keys = ON')

    def self.create_tables
      @db.execute_batch <<-SQL
        CREATE TABLE IF NOT EXISTS `hosts` (
          `id`                 INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          `name`               VARCHAR(255) NOT NULL,
          `created_at`         INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          `updated_at`         INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS `index_hosts_on_name` ON `hosts` (`name`);

        CREATE TABLE IF NOT EXISTS `databases` (
          `id`         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          `host_id`    INTEGER NOT NULL,
          `name`       VARCHAR(255) NOT NULL,
          `rgb`        VARCHAR(255) NOT NULL DEFAULT '255,255,255',
          `created_at` INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          `updated_at` INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
        );
        CREATE INDEX IF NOT EXISTS `index_databases_on_host_id` ON `databases` (`host_id`);
        CREATE UNIQUE INDEX IF NOT EXISTS `index_databases_on_host_id_and_name` ON `databases` (`host_id`, `name`);

        CREATE TABLE IF NOT EXISTS `slow_queries` (
          `id`            INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          `database_id`   INTEGER NOT NULL,
          `date`          INTEGER NOT NULL, --unixtime
          `user`          VARCHAR(255),
          `host`          VARCHAR(255),
          `query_time`    FLOAT NOT NULL DEFAULT 0.0,
          `lock_time`     FLOAT NOT NULL DEFAULT 0.0,
          `rows_sent`     INTEGER NOT NULL DEFAULT 0,
          `rows_examined` INTEGER NOT NULL DEFAULT 0,
          `sql`           VARCHAR(255) NOT NULL,
          `created_at`    INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          `updated_at`    INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          FOREIGN KEY (`database_id`) REFERENCES `databases` (`id`)
        );
        CREATE INDEX IF NOT EXISTS `index_slow_queries_on_database_id` ON `slow_queries` (`database_id`);
        CREATE INDEX IF NOT EXISTS `index_slow_queries_on_date` ON `slow_queries` (`date`);

        CREATE TABLE IF NOT EXISTS `explains` (
          `id`            INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          `slow_query_id` INTEGER,
          `explain_id`    INTEGER,
          `select_type`   VARCHAR(255),
          `table`         VARCHAR(255),
          `type`          VARCHAR(255),
          `possible_keys` VARCHAR(255),
          `key`           VARCHAR(255),
          `key_len`       INTEGER,
          `ref`           VARCHAR(255),
          `rows`          INTEGER,
          `extra`         VARCHAR(255),
          `created_at`    INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          `updated_at`    INTEGER NOT NULL DEFAULT (STRFTIME('%s', 'now', 'localtime')),
          FOREIGN KEY (`slow_query_id`) REFERENCES `slow_queries` (`id`)
        );
        CREATE INDEX IF NOT EXISTS `index_explains_on_explain_id` ON `explains` (`slow_query_id`);
      SQL
    end

    def self.drop_all_tables
      @db.execute_batch <<-SQL
        DROP TABLE IF EXISTS `settings`;
        DROP TABLE IF EXISTS `explains`;
        DROP TABLE IF EXISTS `slow_queries`;
        DROP TABLE IF EXISTS `databases`;
        DROP TABLE IF EXISTS `hosts`;
      SQL
    end
  end
end
Nata::Schema.drop_all_tables
Nata::Schema.create_tables
