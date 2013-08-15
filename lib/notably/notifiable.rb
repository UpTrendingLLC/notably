module Notably
  module Notifiable

    def unread_notifications
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, last_notification_read_at))
    end

    def unread_notifications!
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, Notably.config.redis.getset(last_notification_read_at_key, Time.now.to_i)))
    end

    def notifications
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, 0))
    end

    def notifications_since(time)
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, Time.now.to_i, time.to_i))
    end

    def read_notifications
      parse_notifications(Notably.config.redis.zrevrangebyscore(notification_key, last_notification_read_at, 0))
    end

    def read_notifications!
      parse_notifications(Notably.config.redis.set(last_notification_read_at_key, Time.now.to_i))
    end

    def last_notification_read_at
      Notably.config.redis.get(last_notification_read_at_key).to_i || 0
    end

    def push_notification(notification, time)
      Notably.config.redis.zadd(notification_key, time, notification)
    end

    def delete_notification(notification)
      Notably.config.redis.zrem(notification_key, notification)
    end

    private

    def notification_key
      "notably:notifications:#{self.class}:#{self.id}"
    end

    def last_notification_read_at_key
      "notably:last_read_at:#{self.class}:#{self.id}"
    end

    def parse_notifications(notifications)
      notifications.collect { |n| Marshal.load(n) }
    end
  end
end