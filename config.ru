$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "lib"))
require "sinatra"
require "nata/app"

run Nata::Application
#Nata::Crawler.run
