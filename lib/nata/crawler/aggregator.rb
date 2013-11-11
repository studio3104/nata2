require 'net/ssh'

module Nata
  class Crawler
    class AggregateError < StandardError; end
    class Aggregator
      def initialize(host) # Host.all.each { |host| ... }
        @host = host
        ssh_start

        mysql = host[:mysql_command] || 'mysql'
        mysql = mysql + " -u" + host[:mysql_username] if host[:mysql_username]
        mysql = mysql + " -p" + host[:mysql_password] if host[:mysql_password]
        mysql = mysql + " -P" + host[:mysql_port] if host[:mysql_port]
        @mysql_command = mysql

        @log_file = SlowLogFile.where(host_id: host.id).first
      end


      # 差分とか増分とかローテートされてたときにどうするかみたいなのをここで捌く
      def fetch_slow_log_text
        slow_log_path = fetch_slow_log_file_path

        # 対象ホストへの初回クロールは情報の登録だけ行う
        # スローログファイルがすでに数GB 級のサイズだったらドカンととることになるので、そうならんように
        if !@log_file
          insert_log_file_status(slow_log_path)
          return nil
        end

        current_inode = fetch_file_inode(slow_log_path)
        current_lines = fetch_file_lines(slow_log_path)
        incremental_lines = @log_file.last_checked_line - current_lines

        if @log_file.inode == current_inode
          slow_query = fetch_incremental_text(slow_log_path, incremental_lines)
        else
          slow_query = fetch_full_text(slow_log_path)

          old_file_path = fetch_file_path_by_inode(@log_file.inode, slow_log_path)
          if old_file_path
            slow_query = fetch_incremental_text(old_file_path, incremental_lines) + slow_query
          end

          @log_file.inode = current_inode
        end

        @log_file.last_checked_line = current_lines
        @log_file.save!
        slow_query
      end


      def fetch_slow_log_file_path
        filepath = exec(%Q{#{@mysql_command} -e "SHOW GLOBAL VARIABLES LIKE 'slow_query_log_file';"})

        # "Variable_name\tValue\nslow_query_log_file\t/path/to/slow.log\n"
        filepath.chomp.split("\t").last
      end


      def fetch_file_path_by_inode(inode, file_path = '/')
        exec(%Q{find #{File::dirname(file_path)} -inum #{inode}}).chomp.split("\n").first
      rescue AggregateError
        nil
      end


      def fetch_incremental_text(file_path, target_lines)
        target_lines.zero? ? nil : exec(%Q{tail -#{target_lines} #{file_path}})
      end


      def fetch_full_text(file_path)
        exec(%Q{cat #{file_path}})
      end


      def fetch_file_inode(file_path)
        exec(%Q{ls -li #{file_path} | awk '{print $1}'}).chomp.to_i
      end


      def fetch_file_lines(file_path)
        exec(%Q{wc -l #{file_path} | awk '{print $1}'}).chomp.to_i
      end


      def insert_log_file_status(file_path)
        SlowLogFile.create!(
          host_id: @host.id,
          file_path: file_path,
          inode: fetch_file_inode(file_path),
          last_checked_line: fetch_file_lines(file_path),
        )
      end


      def explain_query(sql_text)
        exec(%Q{#{@mysql_command} -e 'EXPLAIN #{sql_text}'})
      end


      def close
        @ssh.close
      end

      private
      def ssh_start
        @ssh = Net::SSH.start(
          @host[:name],
          @host[:ssh_username] || 'root',
          @host[:ssh_options] || {}
        )
      end

      def exec(command)
        stdout = ''
        ssh_start if @ssh.closed?

        @ssh.exec!(command) do |channel, stream, data|
          stdout << data if stream == :stdout
        end

        raise AggregateError, %Q{command result with no exit status 0 - #{@ssh_username}@#{@ssh_hostname} "#{command}"} if stdout.empty?
        stdout
      end
    end
  end
end
