# coding: utf-8
require "net/ssh"
require "json"

module Nata
  class AggregateError < StandardError; end
  class Aggregator
    def initialize(host_info) # Host.all.each { |host_info| ... }
      @host_info = host_info
      ssh_start

      mysql = host_info["mysql_command"] || "mysql"
      mysql = mysql + " -u" + host_info["mysql_username"] if host_info["mysql_username"]
      mysql = mysql + " -p" + host_info["mysql_password"] if host_info["mysql_password"]
      mysql = mysql + " -P" + host_info["mysql_port"] if host_info["mysql_port"]
      @mysql_command = mysql
    end


    def fetch_slow_log_file_path
      filepath = exec(%Q{#{@mysql_command} -e "SHOW GLOBAL VARIABLES LIKE 'slow_query_log_file';"})

      # "Variable_name\tValue\nslow_query_log_file\t/path/to/slow.log\n"
      filepath.chomp.split("\t").last
    end


    def fetch_file_path_by_inode(inode, file_path = '/')
      exec(%Q{find #{File::dirname(file_path)} -inum #{inode}}).chomp.split("\n").first
    end


    def fetch_incremental_text(file_path, start_line, end_line)
      if [start_line, end_line].include?(0) || start_line > end_line
      else
        exec(%Q{sed -n '#{start_line},#{end_line}p' #{file_path}})
      end
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


    def explain_query(sql_text)
      # SQLInjection 対策の Validation をあとでちゃんと書く
      ## それとも Validation は呼び出し元でやるべきかな
      exec(%Q{#{@mysql_command} -e 'EXPLAIN #{sql_text}'})
    end


    def close
      @ssh.close
    end

    private
    def ssh_start
      @ssh = Net::SSH.start(
        @host_info["name"],
        @host_info["ssh_username"],
        JSON.parse(@host_info["ssh_options"])
      )
    end

    def exec(command)
      stdout = ''
      ssh_start if @ssh.closed?

      @ssh.exec!(command) do |channel, stream, data|
        stdout << data if stream == :stdout
      end

      # raise のメッセージには stderr を含めたほうがよさげかも
      raise AggregateError, %Q{command result with no exit status 0 - #{@host_info[:ssh_username]}@#{@host_info[:name]} "#{command}"} if stdout.empty?
      stdout
    end
  end
end
