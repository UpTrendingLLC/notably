module Notably
  module Notifiable

    def notifications
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, 0))
    end

    def notifications_since(time)
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, time.to_i))
    end

    def unread_notifications
      notifications_since(last_notification_read_at)
    end

    def unread_notifications!
      notifications_since(Notably.config.redis.getset(last_notification_read_at_key, Time.now.to_i))
    end

    def read_notifications
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, last_notification_read_at, 0))
    end

    def read_notifications!
      parse_notifications(Notably.config.redis.set(last_notification_read_at_key, Time.now.to_i))
    end

    def last_notification_read_at
      Notably.config.redis.get(last_notification_read_at_key).to_i
    end

    def notification_key
      "notably:notifications:#{self.class}:#{self.id}"
    end

    def last_notification_read_at_key
      "notably:last_read_at:#{self.class}:#{self.id}"
    end

    private

    def parse_notifications(notifications)
      notifications.collect { |n| Marshal.load(n) }
    end
  end
end