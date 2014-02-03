CREATE TABLE IF NOT EXISTS `hosts` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_hosts_on_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `databases` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `host_id` bigint(20) unsigned NOT NULL,
  `name` varchar(255) NOT NULL,
  `rgb` varchar(255) NOT NULL DEFAULT '255,255,255',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_databases_on_host_id_and_name` (`host_id`,`name`),
  KEY `index_databases_on_host_id` (`host_id`),
  CONSTRAINT `databases_ibfk_1` FOREIGN KEY (`host_id`) REFERENCES `hosts` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `slow_queries` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `database_id` bigint(20) unsigned NOT NULL,
  `date` int(11) unsigned NOT NULL,
  `user` varchar(255) DEFAULT NULL,
  `host` varchar(255) DEFAULT NULL,
  `long_query_time` double DEFAULT NULL,
  `query_time` double NOT NULL DEFAULT '0',
  `lock_time` double NOT NULL DEFAULT '0',
  `rows_sent` bigint(20) unsigned NOT NULL DEFAULT '0',
  `rows_examined` bigint(20) unsigned NOT NULL DEFAULT '0',
  `sql` varchar(8192) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_slow_queries_on_database_id` (`database_id`),
  KEY `index_slow_queries_on_date` (`date`),
  CONSTRAINT `slow_queries_ibfk_1` FOREIGN KEY (`database_id`) REFERENCES `databases` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
