# Notably

[![Gem Version](https://badge.fury.io/rb/notably.png)](http://badge.fury.io/rb/notably)

![a pretty aggressive slogan](notably-slogan.png)

Notably is a redis-backed notification system that _won't_ make you sick and kill you.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'notably'
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install notably
```

## Concepts

Before we dive right in to usage, let me quickly go over a few of the basic concepts of Notably.

### Notification

Most simply, we have a Notification module which you can include in your own classes. It expects a few methods to be overridden, and provides a few helper methods.

Notifications have required attributes, which you set. For instance a CommentNotification might have required attributes of `:comment_id` and `:author_id`. Those attributes become accessor methods that you can use inside your class. Then you must define two methods: `to_html` and `receivers`.

`to_html` should return an html string, which is what you will use in the view to display the notification to the user. (If you're using Rails, you'll have access to all the standard view helpers)

`receivers` should return an array of models to be notified by this notification. All the models returned should be of a class that includes the `Notably::Notifiable` module.  Speaking of...

### Notifiable

The Notifiable module is what you include in the classes that should be notified of things. The only demand placed on the class that includes it is that it responds to and returns a unique value for `id`. So if you're including it in an `ActiveRecord::Base` subclass, you should be good to go.

Notifiable adds these public methods to your class:

* `notifications` Return an array of all notifications
* `notifications_since(time)` Return an array of all notifications that happened after the time parameter
* `unread_notifications` Return an array of all unread notifications
* `unread_notifications!` Return an array of all unread notifications, and update the last_notification_read_at time atomically
* `read_notifications` Return an array of all read notifications
* `read_notifications!` Update the last_notification_read_at time
* `last_notification_read_at` Return an integer representing the time the last notification was read
* `notification_key` The key in redis where the notifications will get stored
* `last_notification_read_at_key` The key in redis where the last_notification_read_at will get stored

For most setups, you should probably only really need access to three or so of those methods.

## Usage

Lets try implementing a comment notification in a sample Rails app with a User model and a Comment model.  We'll start from here:

```ruby
# app/models/user.rb
class User < ActiveRecord::Base
  has_many :comments, foreign_key: :author_id
end

# app/models/comment.rb
class Comment < ActiveRecord::Base
  belongs_to :author, class_name: User
  belongs_to :commentable, polymorphic: true, touch: true
end

# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  before_filter :require_login
  respond_to :json
  def create
    @comment = current_user.comments.create(comment_params)
    respond_with @comment
  end

  private

  def comment_params
    params.require(:comment).permit(:body, :commentable_type, :commentable_id)
  end
end
```

So to begin we know we want our Users to be the one getting the notifications, so lets go ahead and include the necessary module

```ruby
# app/models/user.rb
class User < ActiveRecord::Base
  include Notably::Notifiable
  # ...
end
```

Now we need to create our `CommentNotification` class. I like to do that in an app/notifications directory.  I'll show the finished product here, and then walk through it line by line.

```ruby
# app/notifications/comment_notification.rb
class CommentNotification
  include Notably::Notification
  required_attributes :commentable_type, :commentable_id, :author_id

  def to_html
    "#{author.short_name} commented on #{link_to commentable.name, polymorphic_path(commentable)}"
  end

  def receivers
    commentable.comments.pluck(:author_id).uniq - [author_id]
  end

  def commentable
    @commentable ||= commentable_type.constantize.find(commentable_id)
  end

  def author
    @author ||= User.where(id: author_id)
  end
end
```

So first we include our Notification module, then define the required attributes. The next thing I did was set up the `commentable` and `author` methods for convenience sake, which uses the required attributes to look up the models they point to.  Then I wrote the `to_html` method which would return something that looks like:

> Michael B. commented on [Save Our Bluths](#)

Then I define the `receivers` method which will return a list of users that have also commented on whatever it is I'm commenting on, minus the author of the comment we're currently notifying people about.

Ok, so far so good. Now we just need to hook up the notification creation. I'm sure there's some debate to be had about where the best place to put Notification creation would be, but to me it makes the most sense to have it in the controller. So...

```ruby
# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  # ...
  def create
    @comment = current_user.comments.create(comment_params)
    CommentNotification.create(@comment)
    respond_with @comment
  end
  # ...
end
```

And... we're done. Let me explain a bit about how that create method is working. You can pass it an object, or a hash. The object must respond to all the required attributes. And if it's a hash, it must have a key-value for each required attribute. So I could have just as easily have done

```ruby
CommentNotification.create(
  commentable_type: @comment.commentable_type,
  commentable_id: @comment.commentable_id,
  author_id: current_user.id})
```

But where's the fun in that?

## Grouping

Ok so things are looking pretty good, except the Save Our Bluths post is getting kind of popular, and my notification feed looks like this:

> Michael B. commented on [Save Our Bluths](#)

> Lucille B. commented on [Save Our Bluths](#)

> Buster B. commented on [Save Our Bluths](#)

> Tobius F. commented on [Save Our Bluths](#)

It would be nicer if it looked like

> Buster B., Lucille B., Michael B., and Tobius F. commented on [Save Our Bluths](#)

And what a wonderful time to show you Notably's grouping feature! It works by defining a subset of the required attributes that you group by. So if we wanted to group our `CommentNotification` like I did above, we would write this:

```ruby
# app/notifications/comment_notification.rb
class CommentNotification
  include Notably::Notification
  required_attributes :commentable_type, :commentable_id, :author_id
  group_by :commentable_type, :commentable_id

  # ...
end
```

So let me explain how it's doing this. When a new notification is being saved, it's going to look at the receiver's current notification list, and see if any of them match the `group_by` attributes of the one that is currently saving. If there are any, than it adds the attributes of those that are not being grouped by (in our case, just `:author_id`) to an array that is accessible to you through the `groups` method. As soon as you add the `group_by` line, you have access to all non-grouped-by attributes through the `groups` method. So lets see how that would affect our `CommentNotification` class.

```ruby
# app/notifications/comment_notification.rb
class CommentNotification
  include Notably::Notification
  required_attributes :commentable_type, :commentable_id, :author_id
  group_by :commentable_type, :commentable_id

  def to_html
    "#{authors.collect(&:short_name).to_sentence} commented on #{link_to commentable.name, polymorphic_path([commentable.project, commentable])}"
  end

  def receivers
    commentable.comments.pluck(:author_id).uniq - [author_id]
  end

  def commentable
    @commentable ||= commentable_type.constantize.find(commentable_id)
  end

  def authors
    @authors ||= User.where(id: groups.collect(&:author_id)).order(:first_name)
  end
end
```

And that's really it. `groups` returns an array of OpenStructs that have all the non-grouped-by attributes of all the notifications that are being grouped, including the current notification. But notice that (as I use in the `receivers` method) you can still access `author_id` directly, which will just give you the author_id of the current notification that's being saved.

There's one part of Grouping that I haven't mention yet, and that is `group_within`, which lets you specify the time range that the notification has to fall into in order to be eligable to be grouped. You probably don't want a notification from last week to be grouped with one that just happened. Or maybe you do, and you can set that. By default, it groups within the last_notification_read_at
time. Which I think is a good sensible default, if you're using last_notification_read_at. Otherwise it might be best to set it to a generic `4.hours.ago`. You set it by passing it a lambda or Proc. The lambda or Proc should have one argument, which will be the receiver who's notification list it's grouping from. So this might look like:

```ruby
# app/notifications/comment_notification.rb
class CommentNotification
  include Notably::Notification
  required_attributes :commentable_type, :commentable_id, :author_id
  group_by :commentable_type, :commentable_id
  group_within ->(receiver) { 4.hours.ago }
  # ...
end
```

Or

```ruby
  group_within ->(receiver) { receiver.updated_at }
```

Or

```ruby
  group_within ->(receiver) { receiver.last_notification_read_at } # default
```

(Just a warning, even if you're setting it to something that doesn't need the receiver passed in to calculate it, you need to specify it as an argument if you're going to use lambdas. They don't like it when arguments get ignored.)

## Callbacks

You can use the `before_notify` and `after_notify` class methods to specify callbacks.  They work pretty much as expected taking a lambda, Proc, block, or symbol representing a method.  All of these need to accept an argument for the receiver:

```ruby
class CommentNotification
  include Notably::Notification
  required_attributes :comment_id, :commentable_type, :commentable_id, :author_id
  group_by :commentable_type, :commentable_id
  after_notify ->(receiver) { Rails.logger.info "Sent a comment notification to #{receiver.class} #{receiver.id}" }
  after_notify do |receiver|
    UserMailer.delay.new_comment(receiver.id, comment_id)
  end
  after_notify :foo

  def foo(receiver)
    Rails.logger.info "Foo"
  end
end
```

They're useful for sending email notifications, and probably a lot of other things, but email notifications was what we built this for.  As a side note, if you are using it to send emails, you'll want to have those emails go through some kind of worker queue so you don't massivly slow down notifications.  We recommend [sidekiq](https://github.com/mperham/sidekiq), because it runs on Redis, has a nice dashboard, and has a clean API.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
