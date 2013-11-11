require 'logger'

module Nata
  class Logger < Logger
    def initialize
      # あとでちゃんとする
      super('/tmp/nata.log', 10, 100 * 1024 * 1024)
    end
  end
end
