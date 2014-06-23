require 'nata2'
require 'toml'

config_file = File.expand_path('config.toml', "#{__dir__}/../..")
sample_config_file = File.expand_path('config.sample.toml', "#{__dir__}/../..")
CONFIG = TOML.load_file(File.exist?(config_file) ? config_file : sample_config_file)

class Nata2::Config
  def self.get(keyword)
    case keyword
    when :dburl
      CONFIG['dburl'] || 'sqlite://data/nata2.db'
    else
      raise ArgumentError, "unknown configuration keyword: #{keyword}"
    end
  end
end
