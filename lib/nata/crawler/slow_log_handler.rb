module Nata
  class Crawler
    class SlowLogHandler
      def initialize(host) # Host.all.each { |host| ... }
        @host = host

        file = SlowLogFile.where(host_id: @host[:id]).first
        @file = if file
                  @slow_log_info = Information.new(host, file[:fullpath])
                  file
                else
                  @slow_log_info = Information.new(host)
                  register_slow_log_file
                end
      end

      def save_informations
        fetch_slow_queries.each do |parsed|
          parsed[:host_id] = @host[:id]
          p SlowLog.create!(parsed)
          @file.save!
        end
      end

      def ssh_close
        @slow_log_info.close
      end

      def fetch_slow_queries
        last = SlowLog.where(host_id: @host[:id]).last || {}
        last_db = last[:db] || @slow_log_info.last_db
        last_datetime = last[:start_time]

        if @slow_log_info.same_inode?(@file.inode)
          plain_slow_log = @slow_log_info.incremental(@file.last_checked_line)
          @file.last_checked_line = @slow_log_info.lines
        else
          # inode ga kawatte ita toki no shori
          # kangae nakute ha naranai koto ga ooi node atode kaku
#          @file = register_slow_log_file
#          plain_slow_log = @slow_log_info.fulltext
        end

        Parser.slow_queries(plain_slow_log, last_db, last_datetime)
      end

      private
      def register_slow_log_file
        SlowLogFile.create!(
          host_id: @host[:id],
          fullpath: @slow_log_info.path!,
          inode: @slow_log_info.inode,
          last_checked_line: @slow_log_info.lines,
        )
      end
    end
  end
end
