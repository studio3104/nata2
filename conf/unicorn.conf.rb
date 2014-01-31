APP_ROOT = File.expand_path('../..', __FILE__)

worker_processes Integer(ENV['WEB_CONCURRENCY'] || 3)
timeout 15
preload_app true
listen APP_ROOT + '/tmp/nata.sock'
listen 9292, tcp_nopush: true
pid APP_ROOT + '/tmp/nata.pid'
stdout_path APP_ROOT + '/log/stdout.log'
stderr_path APP_ROOT + '/log/stderr.log'

before_fork do |server, worker|
  old_pid = "#{server.config[:pid]}.oldbin"
  if old_pid != server.pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      puts "Sending #{sig} signal to old unicorn master..."
      Process.kill(sig, File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end

  sleep 1
end
