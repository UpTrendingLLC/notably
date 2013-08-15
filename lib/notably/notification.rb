module Notably
  module Notification
    attr_accessor :data, :created_at, :groups

    def self.included(base)
      base.extend(ClassMethods)
      if defined?(Rails) && defined?(ActionView)
        base.send(:include, Rails.application.routes.url_helpers)
        base.send(:include, ActionView::Helpers::UrlHelper)
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
            @data = attributes.slice(*self.class.group_by)
          end
          @groups << self.class.grouper.new(*attributes.except(*self.class.group_by).values)
        else
          raise ArgumentError, "Object #{attributes} does not respond to all required attributes" unless self.class.required_attributes.all? { |k| attributes.respond_to? k }
          if @data.any?
            raise ArgumentError, "Group by fields do not have shared values" unless @data == Hash[self.class.group_by.collect { |k| [k, attributes.send(k)] }]
          else
            @data = Hash[self.class.group_by.collect { |k| [k, attributes.send(k)] }]
          end
          @groups << self.class.grouper.new(*(self.class.required_attributes - self.class.group_by).collect { |k| attributes.send(k) })
        end
      end
    end

    def save
      receivers.each do |receiver|
        # look for groupable messages within group_within
        # group_within = self.class.group_within.arity == 1 ? self.class.group_within.call(user) : self.class.group_within.call
        group_within = self.class.group_within.call(receiver)
        groupable_notifications = receiver.notifications_since(group_within)
        groupable_notifications.select! { |notification| notification[:data] == data }
        groupable_notifications.each do |notification|
          @groups += notification[:groups]
        end
        Notably.config.redis.pipelined do
          receiver.push_notification(marshal, created_at.to_i)
          groupable_notifications.each do |notification|
            receiver.delete_notification(Marshal.dump(notification))
            @groups -= notification[:groups]
          end
        end
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

    module ClassMethods
      def create(attributes={})
        new(attributes).save
      end

      def required_attributes(*args)
        if args.any?
          @required_attributes ||= []
          @required_attributes += args
        else
          @required_attributes ||= []
        end
      end

      def group_by(*args)
        if args.any?
          @group_by ||= []
          @group_by += args
        else
          @group_by ||= []
        end
      end

      def group_within(block=nil)
        if block
          @group_within = block
        else
          @group_within ||= ->(receiver) { receiver.last_notification_read_at.value }
        end
      end

      def grouper
        @grouper ||= Struct.new("#{self.to_s}Grouper", *(required_attributes - group_by)) if @group_by.any?
      end
    end

  end
end