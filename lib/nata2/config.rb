require 'nata2'
require 'toml'

CONFIG = TOML.load_file(File.expand_path('config.toml', "#{__dir__}/../.."))

class Nata2::Config
  def self.get(keyword)
    case keyword
    when :hrforecast_url
      CONFIG[:hrforecast_url]
    when :dburl
      CONFIG[:dburl] || 'sqlite://data/nata2.db'
    else
      raise ArgumentError, "unknown configuration keyword: #{keyword}"
    end
  end
end
