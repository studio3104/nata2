$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'time'
require 'rspec'
require 'rack/test'
require 'nata/app'
require 'nata/model'
require 'nata/validator'
require 'nata/schema'
