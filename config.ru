$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'sinatra'
require 'nata2/server'

run Nata2::Server
