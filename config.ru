$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "lib"))
require "sinatra"
require "nata/app"
require "nata/crawler"

run Nata::Application
#Nata::Crawler.run
