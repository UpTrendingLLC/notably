require "notably/configuration"
require "notably/notification"
require "notably/notifiable"
require "notably/version"

module Notably
  module_function

  def config
    @config ||= Configuration.new
    yield @config if block_given?
    @config
  end
end
