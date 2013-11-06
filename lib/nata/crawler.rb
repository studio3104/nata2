require 'parallel'

module Nata
  class Crawler
    def self.run
      Thread.new {
        begin
          execute
        rescue => e # class ha atode
          # log haku shori wo atode kaku
          p e
        ensure
          # DEPRECATION WARNING: Database connections will not be closed automatically, please close your
          # database connection at the end of the thread by calling `close` on your
          # connection.  For example: ActiveRecord::Base.connection.close
          ActiveRecord::Base.connection.close
        end
      }
    end

    def self.execute
      loop do
        Parallel.each(hostlist, :in_threads => Parallel.processor_count) do |host|
          begin
            runner = SlowLogHandler.new(host)
          rescue => e
            p e.class
            p e.message
            p e.backtrace
          end
          runner.save_informations
          runner.ssh_close
        end
        sleep 300
      end
    end

    def self.hostlist
      Host.all
    end
  end
end
