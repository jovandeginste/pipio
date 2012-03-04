# pidgin2adium [![Build Status](https://secure.travis-ci.org/gabebw/pidgin2adium.png)](http://travis-ci.org/gabebw/pidgin2adium)
A fast, easy way to convert Pidgin (formerly gaim) logs to the
Adium format. Note that it assumes a Mac OS X environment with Adium installed.

## FEATURES/PROBLEMS:
* No problems (well, hopefully).

## SYNOPSIS:

There are two ways you can use this gem: as a script or as a library.
Both require you to provide aliases, which may require a bit of explanation.
Adium and Pidgin allow you to set aliases for buddies as well as for yourself,
so that you show up in chats as (for example) "Me" instead of as
"best\_screen\_name\_ever\_018845".

However, Pidgin then uses aliases in the log file instead of the actual screen
name, which complicates things. To parse properly, this gem needs to know which
aliases belong to you so it can map them to the correct screen name.
If it encounters an alias that you did not list,  it assumes that it belongs to
the person to whom you are chatting.
Note that aliases are lower-cased and space is removed, so providing "Gabe B-W,
GBW" is the same as providing "gabeb-w,gbw".

You do not need to provide your screenname in the alias list.

### Example (using script)
Assuming that:

* your Pidgin log files are in the "pidgin-logs" folder
* your various aliases in your chats are "Gabe", "Gabe B-W", and "gbw"

Then run (at the command line)

    $ pidgin2adium -i pidgin-logs -a "Gabe, Gabe B-W, gbw"

Or:

    $ pidgin2adium -i pidgin-logs -a gabe,gabeb-w,gbw

### Example (using library)
The library style allows you to parse a log file and get back a LogFile instance
for easy reading, manipulation, etc. If you don't need to do anything with the
individual messages, use Pidgin2Adium.parse.

    require 'pidgin2adium'
    logfile = Pidgin2Adium.parse("/path/to/log/file.html", "gabe,gbw,gabeb-w")
    if logfile == false
      puts "Oh no! Could not parse!"
    else
      logfile.each do |message|
        # Every Message subclass has sender, time, and buddy_alias
        puts "Sender's screen name: #{message.sender}"
        puts "Time message was sent: #{message.time}"
        puts "Sender's alias: #{message.buddy_alias}"
        if message.respond_to?(:body)
          puts "Message body: #{message.body}"
          if message.respond_to?(:event) # Pidgin2Adium::Event class
            puts "Event type: #{message.event_type}"
          end
        elsif message.respond_to?(:status) # Pidgin2Adium::StatusMessage
          puts "Status: #{message.status}"
        end
        # Prints out the message in Adium log format
        puts message.to_s
      end

      success = logfile.write_out()
      # To overwrite file if it exists:
      # logfile.write_out(overwrite = true)
      # To specify your own output dir (default = Pidgin2Adium::ADIUM_LOG_DIR):
      # logfile.write_out(false, output_dir = my_dir)
      # Or combine them:
      # logfile.write_out(true, my_dir)
      if success == false
        puts "An error occurred!"
      elsif success == Pidgin2Adium::FILE_EXISTS
        # Not returned if overwrite set to true
        puts "File already exists."
      else
        puts "Successfully wrote out log file!"
        puts "Path to output file: #{success}"
      end
      # This deletes search indexes so Adium re-indexes the new chat logs.
      # It is not automatically called after log_file.write_out()
      # Call it after converting all the logs, since it takes up a bit of
      # processing power.
      Pidgin2Adium.delete_search_indexes()
    end

### Example 2 (using library)
If you want to parse the file and write it out instead of just parsing it, use Pidgin2Adium.parse\_and\_generate.

Note: For batch processing, use LogConverter.

    require 'pidgin2adium'
    # Both options are optional; without :output_dir, writes to Adium log dir
    # (which is usually what you want anyway).
    opts = {:overwrite => true, :output_dir => "/my/output/dir"}
    path_to_converted_log = Pidgin2Adium.parse_and_generate("/path/to/log/file.html", "gabe,gbw,gabeb-w", opts)

## REQUIREMENTS:
* None

## INSTALL

    gem install pidgin2adium

## THANKS
With thanks to Li Ma, whose blog post at
http://li-ma.blogspot.com/2008/10/pidgin-log-file-to-adium-log-converter.html
helped tremendously.

## Note on Patches/Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a
  future version unintentionally.
* Commit, do not mess with rakefile, version, or history.
  (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

## Copyright

Copyright (c) 2011 Gabe Berke-Williams. See LICENSE for details.