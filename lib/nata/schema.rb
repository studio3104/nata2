#!/usr/bin/env ruby
require "sqlite3"

db_dir = File.join(File.dirname(__FILE__), "..", "..", "db")

db = case ENV["RACK_ENV"]
     when "production"
       SQLite3::Database.new(db_dir + "/production.db")
     when "test"
       SQLite3::Database.new(db_dir + "/test.db")
     else
       SQLite3::Database.new(db_dir + "/development.db")
     end

db.execute("PRAGMA foreign_keys = ON")

db.execute_batch <<-SQL
  DROP TABLE IF EXISTS `hosts`;
  DROP TABLE IF EXISTS `ssh_options`;
  DROP TABLE IF EXISTS `mysql_options`;
  DROP TABLE IF EXISTS `slow_log_files`;
  DROP TABLE IF EXISTS `databases`;
  DROP TABLE IF EXISTS `slow_queries`;
  DROP TABLE IF EXISTS `explains`;
  DROP TABLE IF EXISTS `settings`;
SQL

db.execute_batch <<-SQL
  CREATE TABLE IF NOT EXISTS `hosts` (
    `id`           INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `name`         VARCHAR(255) NOT NULL,
    `ipaddress`    VARCHAR(255),
    `explain_flag` BOOL,
    `created_at`   DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at`   DATETIME NOT NULL DEFAULT (DATETIME('now','localtime'))
  );
  CREATE UNIQUE INDEX IF NOT EXISTS `index_hosts_on_name` ON `hosts` (`name`);

  CREATE TABLE IF NOT EXISTS `ssh_options` (
    `id`         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `host_id`    INTEGER,
    `username`   VARCHAR(255),
    `password`   VARCHAR(255),
    `created_at` DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at` DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
  );
  CREATE UNIQUE INDEX IF NOT EXISTS `index_ssh_options_on_host_id` ON `ssh_options` (`host_id`);

  CREATE TABLE IF NOT EXISTS `mysql_options` (
    `id`           INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `host_id`      INTEGER,
    `command_path` VARCHAR(255),
    `bind_port`    INTEGER,
    `username`     VARCHAR(255),
    `password`     VARCHAR(255),
    `created_at`   DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at`   DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
  );
  CREATE UNIQUE INDEX IF NOT EXISTS `index_mysql_options_on_host_id` ON `mysql_options` (`host_id`);

  CREATE TABLE IF NOT EXISTS `slow_log_files` (
    `id`         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `host_id`    INTEGER,
    `inode`      INTEGER NOT NULL,
    `last_line`  INTEGER,
    `created_at` DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at` DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
  );
  CREATE UNIQUE INDEX IF NOT EXISTS `index_slow_log_files_on_host_id` ON `slow_log_files` (`host_id`);

  CREATE TABLE IF NOT EXISTS `slow_queries` (
    `id`            INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `host_id`       INTEGER,
    `start_time`    DATETIME,
    `user`          VARCHAR(255),
    `host`          VARCHAR(255),
    `query_time`    FLOAT,
    `lock_time`     FLOAT,
    `rows_sent`     INTEGER,
    `rows_examined` INTEGER,
    `db`            VARCHAR(255),
    `sql_text`      VARCHAR(255),
    `created_at`    DATETIME NOT NULL,
    `updated_at`    DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
  );
  CREATE INDEX IF NOT EXISTS `index_slow_queries_on_host_id` ON `slow_queries` (`host_id`);

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
    `created_at`    DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at`    DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    FOREIGN KEY (`slow_query_id`) REFERENCES `slow_queries` (`id`)
  );
  CREATE INDEX IF NOT EXISTS `index_explains_on_explain_id` ON `explains` (`slow_query_id`);

  CREATE TABLE IF NOT EXISTS `settings` (
    `id`                         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    `crawl_interval_sec`         INTEGER,
    `fetch_rows`                 INTEGER,
    `default_ssh_username`       VARCHAR(255),
    `default_ssh_password`       VARCHAR(255),
    `default_mysql_command_path` VARCHAR(255),
    `default_mysql_bind_port`    INTEGER,
    `default_mysql_username`     VARCHAR(255),
    `default_mysql_password`     VARCHAR(255),
    `created_at`                 DATETIME NOT NULL DEFAULT (DATETIME('now','localtime')),
    `updated_at`                 DATETIME NOT NULL DEFAULT (DATETIME('now','localtime'))
  );
SQL
