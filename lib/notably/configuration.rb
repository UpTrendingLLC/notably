module Notably
  class Configuration
    attr_writer :redis

    def initialize
    end

    def redis
      @redis ||= Redis.current
    end
  end
end