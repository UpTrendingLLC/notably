module Notably
  class Configuration
    attr_accessor :redis, :touch_receivers

    def initialize
      @redis = Redis.current
      @touch_receivers = true
    end
  end
end