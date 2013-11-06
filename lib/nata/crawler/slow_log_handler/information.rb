require 'net/ssh'

module Nata
  class Crawler::SlowLogHandler
    class InformationFetchError < StandardError; end
    class Information
      def initialize(host, filename = nil) # Host.all.each { |host| ... }
        @filename = filename

        @ssh_hostname = host[:name]
        @ssh_username = host[:ssh_username] || 'root'
        @ssh_options = host[:ssh_options] || {}
        ssh_start

        mysql = host[:mysql_command] || 'mysql'
        mysql = mysql + " -u" + host[:mysql_username] if host[:mysql_username]
        mysql = mysql + " -p" + host[:mysql_password] if host[:mysql_password]
        mysql = mysql + " -P" + host[:mysql_port] if host[:mysql_port]
        @mysql_command = mysql
      end

      LASTDB = /use (\w+);$/
      def last_db
        exec(%Q{grep '^use ' #{path}}).split("\n").last =~ LASTDB
        $1
      end

      def inode
        exec(%Q{ls -li #{path} | awk '{print $1}'}).chomp.to_i
      end

      def path
        return @filename if @filename
        path!
      end

      def path!
        filepath = exec(%Q{#{@mysql_command} -e "SHOW GLOBAL VARIABLES LIKE 'slow_query_log_file';"})

        # "Variable_name\tValue\nslow_query_log_file\t/path/to/slow.log\n"
        @filename = filepath.chomp.split("\t").last
      end

      def lines
        exec(%Q{wc -l #{path} | awk '{print $1}'}).chomp.to_i
      end

      def fulltext
        exec(%Q{cat #{path}})
      end

      def incremental(last_checked_line)
        target_lines = lines - last_checked_line
        return '' if target_lines.zero?
        exec(%Q{tail -#{target_lines} #{path}})
      end

      def same_inode?(old_inode)
        old_inode == inode
      end

      def close
        @ssh.close
      end

      private
      def ssh_start
        @ssh = Net::SSH.start(@ssh_hostname, @ssh_username, @ssh_options)
      end

      def exec(command)
        stdout = ''
        ssh_start if @ssh.closed?

        @ssh.exec!(command) do |channel, stream, data|
          stdout << data if stream == :stdout
        end

        raise InformationFetchError, %Q{command result with no exit status 0 - #{@ssh_username}@#{@ssh_hostname} "#{command}"} if stdout.empty?
        stdout
      end
    end
  end
end
