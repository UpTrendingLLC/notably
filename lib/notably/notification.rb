module Notably
  module Notification
    attr_accessor :data, :created_at, :groups

    def self.included(base)
      base.extend(ClassMethods)
      if defined?(Rails) && defined?(ActionView)
        base.send(:include, ActionView::Helpers)
        base.send(:include, Rails.application.routes.url_helpers)
      end
    end

    def to_s
      ActionView::Base.full_sanitizer.sanitize(to_html) if defined?(ActionView)
    end

    def to_html
      ""
    end

    def receivers
      []
    end

    def initialize(*attributes_hashes)
      @data = {}
      @groups = []
      attributes_hashes.each do |attributes|
        case attributes
        when Hash
          raise ArgumentError, "Hash does not have all required attributes" unless self.class.required_attributes.all? { |k| attributes.key? k }
          if @data.any?
            raise ArgumentError, "Group by fields do not have shared values" unless @data == attributes.slice(*self.class.group_by)
          else
            @data = attributes
          end
          @groups << OpenStruct.new(attributes.except(*self.class.group_by))
        else
          raise ArgumentError, "Object #{attributes} does not respond to all required attributes" unless self.class.required_attributes.all? { |k| attributes.respond_to? k }
          if @data.any?
            raise ArgumentError, "Group by fields do not have shared values" unless @data == Hash[self.class.group_by.collect { |k| [k, attributes.send(k)] }]
          else
            @data = Hash[self.class.required_attributes.collect { |k| [k, attributes.send(k)] }]
          end
          @groups << OpenStruct.new(Hash[(self.class.required_attributes - self.class.group_by).collect { |k| [k, attributes.send(k)] }])
        end
      end
    end

    def save
      receivers.each do |receiver|
        # look for groupable messages within group_within
        if self.class.group?
          group_within = self.class.group_within.call(receiver)
          groupable_notifications = receiver.notifications_since(group_within)
          groupable_notifications.select! { |notification| notification[:data].slice(*self.class.group_by) == data.slice(*self.class.group_by) }
          groupable_notifications.each do |notification|
            @groups += notification[:groups]
          end
        end
        run_callbacks(:before_notify, receiver)
        Notably.config.redis.pipelined do
          Notably.config.redis.zadd(receiver.send(:notification_key), created_at.to_i, marshal)
          receiver.touch if Notably.config.touch_receivers
          if self.class.group?
            groupable_notifications.each do |notification|
              Notably.config.redis.zrem(receiver.send(:notification_key), Marshal.dump(notification))
              @groups -= notification[:groups]
            end
          end
        end
        run_callbacks(:after_notify, receiver)
      end
    end

    def to_h
      {
        created_at: created_at,
        data: data,
        groups: groups,
        message: to_s,
        html: to_html
      }
    end

    def marshal
      Marshal.dump(to_h)
    end

    def created_at
      @created_at ||= Time.now
    end

    def method_missing(method, *args, &block)
      if method.to_s =~ /=/
        method = method.to_s.gsub!('=', '')
        if @data.key? method
          @data[method.to_sym] = *args
        end
      else
        if @data.key? method
          @data[method]
        else
          super
        end
      end
    end

    private

    def run_callbacks(type, *args)
      self.class.callbacks[type].each do |callback|
        if callback.is_a? Symbol
          # callback.to_proc.call(self, *args)
          self.send(callback, *args)
        else
          self.instance_exec(*args, &callback)
        end
      end
    end

    module ClassMethods
      attr_reader :callbacks

      def self.extended(base)
        base.class_eval do
          @callbacks = {after_notify: [], before_notify: []}
          @group_by = []
          @group_within = ->(receiver) { receiver.last_notification_read_at }
          @required_attributes = []
        end
      end

      def create(attributes={})
        new(attributes).save
      end

      def required_attributes(*args)
        if args.any?
          @required_attributes += args
        else
          @required_attributes
        end
      end

      def group_by(*args)
        if args.any?
          @group_by += args
        else
          @group_by
        end
      end

      def group?
        @group_by.any?
      end

      def group_within(block=nil)
        if block
          @group_within = block
        else
          @group_within
        end
      end

      def before_notify(method=nil, &block)
        @callbacks[:before_notify] << (block || method)
      end

      def after_notify(method=nil, &block)
        @callbacks[:after_notify] << (block || method)
      end

    end

  end
end