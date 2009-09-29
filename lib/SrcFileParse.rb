# =SrcFileParse
# The class +SrcFileParse+ has 2 subclasses, +SrcTxtFileParse+ and +SrcHtmlFileParse+
# It parses the file passed into it and extracts the following
# from each line in the chat: time, alias, and message and/or status.

require 'parsedate'

module Pidgin2Adium
    # The two subclasses of +SrcFileParse+,
    # +SrcTxtFileParse+ and +SrcHtmlFileParse+, only differ
    # in that they have their own @line_regex, @line_regex_status,
    # and most importantly, create_msg and create_status_or_event_msg, which take
    # the +MatchData+ objects from matching against @line_regex or
    # @line_regex_status, respectively and return object instances.
    # +create_msg+ returns a +Message+ instance (or one of its subclasses).
    # +create_status_or_event_msg+ returns a +Status+ or +Event+ instance.
    class SrcFileParse
	def initialize(src_path, dest_dir_base, user_aliases, user_tz, user_tz_offset)
	    @src_path = src_path
	    # these two are to pass to generator in pare_file
	    @dest_dir_base = dest_dir_base
	    @user_aliases = user_aliases
	    @user_tz = user_tz
	    @user_tz_offset = user_tz_offset
	    @tz_offset = get_time_zone_offset()

	    # Used in @line_regex{,_status}. Only one group: the entire timestamp.
	    @timestamp_regex_str = '\(((?:\d{4}-\d{2}-\d{2} )?\d{1,2}:\d{1,2}:\d{1,2}(?: .{1,2})?)\)'
	    # the first line is special: it tells us
	    # 1) who we're talking to 
	    # 2) what time/date
	    # 3) what SN we used
	    # 4) what protocol (AIM, icq, jabber...)
	    @first_line_regex = /Conversation with (.+?) at (.+?) on (.+?) \((.+?)\)/

	    # Possible formats for timestamps:
	    # "2007-04-17 12:33:13" => %w{2007, 04, 17, 12, 33, 13}
	    @time_regex_one = /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
	    # "4/18/2007 11:02:00 AM" => %w{4, 18, 2007, 11, 02, 00, AM}
	    @time_regex_two = %r{(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ([AP]M)}
	    # sometimes a line in a chat doesn't have a full timestamp
	    # "04:22:05 AM" => %w{04 22 05 AM}
	    @minimal_time_regex = /(\d{1,2}):(\d{2}):(\d{2}) ?([AP]M)?/
	    
	    # {user,partner}SN set in parse_file() after reading the first line
	    @user_SN = nil
	    @partner_SN = nil
	    
	    # @basic_time_info is for files that only have the full timestamp at
	    # the top; we can use it to fill in the minimal per-line timestamps.
	    # It has only 3 elements (year, month, dayofmonth) because
	    # you should be able to fill everything else in.
	    # If you can't, something's wrong.
	    @basic_time_info = []

	    # @user_alias is set each time get_sender_by_alias is called. Set an
	    # initial value just in case the first message doesn't give us an
	    # alias.
	    @user_alias = @user_aliases[0]
	    
	    # @status_map, @lib_purple_events, and @events are used in
	    # create_status_or_event_message.
	    @status_map = {
		/(.+) logged in\.$/ => 'online',
		/(.+) logged out\.$/ => 'offline',
		/(.+) has signed on\.$/ => 'online',
		/(.+) has signed off\.$/ => 'offline',
		/(.+) has gone away\.$/ => 'away',
		/(.+) is no longer away\.$/ => 'available',
		/(.+) has become idle\.$/ => 'idle',
		/(.+) is no longer idle\.$/ => 'available'
	    }

	    # lib_purple_events are all of event_type libPurple
	    @lib_purple_events = [
		# file transfer
		/Starting transfer of .+ from (.+)/,
		/^Offering to send .+ to (.+)$/,
		/(.+) is offering to send file/,
		/^Transfer of file .+ complete$/,
		/Error reading|writing|accessing .+: .+/,
		/You cancelled the transfer of/,
		/File transfer cancelled/,
		/(.+) cancelled the transfer of/,
		/(.+) cancelled the file transfer/,
		# Direct IM - actual (dis)connect events are their own types
		/^Attempting to connect to (.+) at .+ for Direct IM\./,
		/^Asking (.+) to connect to us at .+ for Direct IM\./,
		/^Attempting to connect via proxy server\.$/,
		/^Direct IM with (.+) failed/,
		# encryption
		/Received message encrypted with wrong key/,
		/^Requesting key\.\.\.$/,
		/^Outgoing message lost\.$/,
		/^Conflicting Key Received!$/,
		/^Error in decryption- asking for resend\.\.\.$/,
		/^Making new key pair\.\.\.$/,
		# file transfer - these are in this (non-used) list because you can't get the alias out of matchData[1]
		/^You canceled the transfer of .+$/,
		# sending errors
		/^Last outgoing message not received properly- resetting$/,
		/'Resending\.\.\./,
		# connection errors
		/Lost connection with the remote user:.+/,
		# chats
		/^.+ entered the room\.$/,
		/^.+ left the room\.$/
	    ]

	    # non-libpurple events
	    # Each key maps to an event_type string. The keys will be matched against a line of chat
	    # and the partner's alias will be in regex group 1, IF the alias is matched.
	    @event_map = {
		# .+ is not an alias, it's a proxy server so no grouping
		/^Attempting to connect to .+\.$/ => 'direct-im-connect',
		# NB: pidgin doesn't track when Direct IM is disconnected, AFAIK
		/^Direct IM established$/ => 'directIMConnected',
		/Unable to send message. The message is too large./ => 'chat-error',
		/You missed .+ messages from (.+) because they were too large./ => 'chat-error'
	    }
	end

	def get_time_zone_offset()
	    tz_match = /([-\+]\d+)[A-Z]{3}\.txt|html?/.match(@src_path)
	    tz_offset = tz_match[1] rescue @user_tz_offset
	    return tz_offset
	end

	# Adium time format: YYYY-MM-DD\THH.MM.SS[+-]TZ_HRS like:
	# 2008-10-05T22.26.20-0800
	def create_adium_time(time)
	    # parsed_date = [year, month, day, hour, min, sec]
	    parsed_date = case time
			 when @time_regex_one
			     [$~[1].to_i, # year
			     $~[2].to_i,  # month
			     $~[3].to_i,  # day
			     $~[4].to_i,  # hour
			     $~[5].to_i,  # minute
			     $~[6].to_i]  # seconds
			 when @time_regex_two
			     hours = $~[4].to_i
			     if $~[7] == 'PM' and hours != 12
				 hours += 12
			     end
			     [$~[3].to_i, # year
			      $~[1].to_i, # month
			      $~[2].to_i, # day
			      hours,
			      $~[5].to_i, # minutes
			      $~[6].to_i] # seconds
			 when @minimal_time_regex
			     # "04:22:05" => %w{04 22 05}
			     hours = $~[1].to_i
			     if $~[4] == 'PM' and hours != 12
				 hours += 12
			     end
			     @basic_time_info + # [year, month, day]
			     [hours,
			      $~[2].to_i, # minutes
			      $~[3].to_i] # seconds
			 else
			     Pidgin2Adium.log_msg("You have found an odd timestamp.", true)
			     Pidgin2Adium.log_msg("Please report it to the developer.")
			     Pidgin2Adium.log_msg("The timestamp: #{time}")
			     Pidgin2Adium.log_msg("Continuing...")

			     ParseDate.parsedate(time)
			 end
	    return Time.local(*parsed_date).strftime("%Y-%m-%dT%H.%M.%S#{@tz_offset}")
	end

	# parse_file slurps up @src_path into one big string and runs
	# SrcHtmlFileParse.cleanup if it's an HTML file.
	# It then uses regexes to break up the string, uses create(Status)Msg
	# to turn the regex MatchData into data hashes, and feeds it to
	# ChatFileGenerator, which creates the XML data string.
	# This method returns a ChatFileGenerator object.
	def parse_file()
	    file = File.new(@src_path, 'r')
	    # Deal with first line.
	    first_line = file.readline()
	    first_line_match = @first_line_regex.match(first_line)
	    if first_line_match.nil?
		file.close()
		Pidgin2Adium.log_msg("Parsing of #{@src_path} failed (could not find valid first line).", true)
		return false
	    else
		# one big string, without the first line
		if self.class == SrcHtmlFileParse
		    file_content = self.cleanup(file.read())
		else
		    file_content = file.read()
		end
		file.close()
	    end
	    
	    service = first_line_match[4]
	    # user_SN is standardized to avoid "AIM.name" and "AIM.na me" folders
	    @user_SN = first_line_match[3].downcase.gsub(' ', '')
	    @partner_SN = first_line_match[1]
	    pidgin_chat_time_start = first_line_match[2]
	    @basic_time_info = case first_line
			     when @time_regex_one: [$1.to_i, $2.to_i, $3.to_i]
			     when @time_regex_two: [$3.to_i, $1.to_i, $2.to_i]
			     end
	    adium_chat_time_start = create_adium_time(pidgin_chat_time_start)

	    generator = ChatFileGenerator.new(service,
					   @user_SN,
					   @partner_SN,
					   adium_chat_time_start,
					   @dest_dir_base)
	    file_content.each_line do |line|
		case line
		when @line_regex
		    generator.append_line( create_msg($~.captures) )
		when @line_regex_status
		    generator.append_line( create_status_or_event_msg($~.captures) )
		end
	    end
	    return generator
	end

	def get_sender_by_alias(alias_name)
	    if @user_aliases.include? alias_name.downcase.sub(/^\*{3}/,'').gsub(/\s+/, '')
		# Set the current alias being used of the ones in @user_aliases
		@user_alias = alias_name.sub(/^\*{3}/, '')
		return @user_SN
	    else
		return @partner_SN
	    end
	end

	# create_msg takes an array of captures from matching against @line_regex
	# and returns a Message object or one of its subclasses.
	# It can be used for SrcTxtFileParse and SrcHtmlFileParse because
	# both of them return data in the same indexes in the matches array.
	def create_msg(matches)
	    msg = nil
	    # Either a regular message line or an auto-reply/away message.
	    time = create_adium_time(matches[0])
	    alias_str = matches[1]
	    sender = get_sender_by_alias(alias_str)
	    body = matches[3]
	    if matches[2] # auto-reply
		msg = AutoReplyMessage.new(sender, time, alias_str, body)
	    else
		# normal message
		msg = XMLMessage.new(sender, time, alias_str, body)
	    end
	    return msg
	end

	# create_status_or_event_msg takes an array of +MatchData+ captures from
	# matching against @line_regex_status and returns an Event or Status.
	def create_status_or_event_msg(matches)
	    # ["22:58:00", "BuddyName logged in."]
	    # 0: time
	    # 1: status message or event
	    msg = nil
	    time = create_adium_time(matches[0])
	    str = matches[1]
	    regex, status = @status_map.detect{|regex, status| str =~ regex}
	    if regex and status
		# Status message
		alias_str = regex.match(str)[1]
		sender = get_sender_by_alias(alias_str)
		msg = StatusMessage.new(sender, time, alias_str, status)
	    else
		# Test for event
		regex = @lib_purple_events.detect{|regex| str =~ regex }
		event_type = 'libpurpleEvent' if regex
		unless regex and event_type
		    # not a libpurple event, try others
		    regex_and_event_type = @event_map.detect{|regex,event_type| str =~ regex}
		    regex = regex_and_event_type[0]
		    event_type = regex_and_event_type[1]
		end
		if regex and event_type
		    regex_matches = regex.match(str)
		    # Event message
		    if regex_matches.size == 1
			# No alias - this means it's the user
			alias_str = @user_alias
			sender = @user_SN
		    else
			alias_str = regex.match(str)[1]
			sender = get_sender_by_alias(alias_str)
		    end
		    msg = Event.new(sender, time, alias_str, str, event_type)
		end
	    end
	    return msg
	end
    end

    class SrcTxtFileParse < SrcFileParse
	def initialize(src_path, dest_dir_base, user_aliases, user_tz, user_tz_offset)
	    super(src_path, dest_dir_base, user_aliases, user_tz, user_tz_offset)
	    # @line_regex matches a line in a TXT log file other than the first
	    # @line_regex matchdata:
	    # 0: timestamp
	    # 1: screen name or alias, if alias set
	    # 2: "<AUTO-REPLY>" or nil
	    # 3: message body
	    @line_regex = /#{@timestamp_regex_str} (.*?) ?(<AUTO-REPLY>)?: (.*)$/o
	    # @line_regex_status matches a status line
	    # @line_regex_status matchdata:
	    # 0: timestamp
	    # 1: status message
	    @line_regex_status = /#{@timestamp_regex_str} ([^:]+?)[\r\n]{1,2}/o
	end

    end

    class SrcHtmlFileParse < SrcFileParse
	def initialize(src_path, dest_dir_base, user_aliases, user_tz, user_tz_offset)
	    super(src_path, dest_dir_base, user_aliases, user_tz, user_tz_offset)
	    # @line_regex matches a line in an HTML log file other than the first
	    # time matches on either "2008-11-17 14:12" or "14:12"
	    # @line_regex match obj:
	    # 0: timestamp, extended or not
	    # 1: screen name or alias, if alias set
	    # 2: "&lt;AUTO-REPLY&gt;" or nil
	    # 3: message body
	    #  <span style='color: #000000;'>test sms</span>
	    @line_regex = /#{@timestamp_regex_str} ?<b>(.*?) ?(&lt;AUTO-REPLY&gt;)?:?<\/b> ?(.*)<br ?\/>/o
	    # @line_regex_status matches a status line
	    # @line_regex_status match obj:
	    # 0: timestamp
	    # 1: status message
	    @line_regex_status = /#{@timestamp_regex_str} ?<b> (.*?)<\/b><br ?\/>/o
	end

	# Removes <font> tags, empty <a>s, and spans with either no color
	# information or color information that just turns the text black.
	# Returns a string.
	def cleanup(text)
	    # Pidgin and Adium both show bold using
	    # <span style="font-weight: bold;"> except Pidgin uses single quotes
	    # and Adium uses double quotes
	    text.gsub!(/<\/?(html|body|font).*?>/, '')
	    # These empty links are sometimes appended to every line in a chat,
	    # for some weird reason. Remove them.
	    text.gsub!(%r{<a href='.+?'>\s*?</a>}, '')
	    text.gsub!(%r{(.*?)<span.+style='(.+?)'>(.*?)</span>(.*)}) do |s|
		# before = text before match
		# style = style declaration
		# innertext = text inside <span>
		# after = text after match
		before, style, innertext, after = *($~[1..4])
		# TODO: remove after from string then see what balanceTags does
		# Remove empty spans.
		nil if innertext == ''
		# Only allow some style declarations
		# We keep:
		# font-weight: bold
		# color (except #000000)
		# text-decoration: underline
		styleparts = style.split(/; ?/)
		styleparts.map! do |p|
		    # Short-circuit for common declaration
		    # Yes, sometimes there's a ">" before the ";".
		    if p == 'color: #000000;' or
			p == 'color: #000000>;'
			nil
		    else
			case p
			when /font-family/: nil
			when /font-size/: nil
			when /background/: nil
			end
		    end
		end
		styleparts.compact!
		if styleparts.empty?
		    style = ''
		elsif styleparts.size == 1
		    p styleparts
		    exit 1
		    style = styleparts[0] << ';'
		else
		    style = styleparts.join('; ') << ';'
		end
		if style != ''
		    innertext = "<span style=\"#{style}\">#{innertext}</span>"
		end
		before + innertext + after
	    end
	    # Pidgin uses <em>, Adium uses <span>
	    if text.gsub!('<em>', '<span style="italic">')
		text.gsub!('</em>', '</span>')
	    end
	    return text
	end
    end

    # A holding object for each line of the chat.
    # It is subclassed as appropriate (eg AutoReplyMessage).
    # All Messages have senders, times, and aliases.
    class Message
	def initialize(sender, time, alias_str)
	    @sender = sender
	    @time = time
	    @alias_str = alias_str
	end
    end
   
    # Basic message with body text (as opposed to pure status messages, which
    # have no body).
    class XMLMessage < Message
	def initialize(sender, time, alias_str, body)
	    super(sender, time, alias_str)
	    @body = body
	    normalize_body!()
	end

	def get_output
	    return sprintf('<message sender="%s" time="%s" alias="%s">%s</message>' << "\n",
			   @sender, @time, @alias_str, @body)
	end

	def normalize_body!
	    normalize_body_entities!()
	    # Fix mismatched tags. Yes, it's faster to do it per-message
	    # than all at once.
	    @body = Pidgin2Adium.balance_tags(@body)
	    if @alias_str[0,3] == '***'
		# "***<alias>" is what pidgin sets as the alias for a /me action
		@alias_str.slice!(0,3)
		@body = '*' << @body << '*'
	    end
	    @body = '<div><span style="font-family: Helvetica; font-size: 12pt;">' <<
	    @body << 
	    '</span></div>'
	end

	def normalize_body_entities!
	    # Convert '&' to '&amp;' only if it's not followed by an entity.
	    @body.gsub!(/&(?!lt|gt|amp|quot|apos)/, '&amp;')
	    # replace single quotes with '&apos;' but only outside <span>s.
	    @body.gsub!(/(.*?)(<span.*?>.*?<\/span>)(.*?)/) do
		before, span, after = $1, ($2||''), $3||''
		before.gsub("'", '&aquot;') <<
		    span <<
		    after.gsub("'", '&aquot;')
	    end
	end
    end

    # An auto reply message, meaning it has a body.
    class AutoReplyMessage < XMLMessage
	def get_output
	    return sprintf('<message sender="%s" time="%s" auto="true" alias="%s">%s</message>' << "\n", @sender, @time, @alias_str, @body)
	end
    end

    # A message saying e.g. "Blahblah has gone away."
    class StatusMessage < Message
	def initialize(sender, time, alias_str, status)
	    super(sender, time, alias_str) 
	    @status = status
	end
	def get_output
	    return sprintf('<status type="%s" sender="%s" time="%s" alias="%s"/>' << "\n", @status, @sender, @time, @alias_str)
	end
    end
  
    # An <event> line of the chat
    class Event < XMLMessage
	def initialize(sender, time, alias_str, body, type="libpurpleMessage")
	    super(sender, time, alias_str, body)
	    @type = type
	end

	def get_output
	    return sprintf('<event type="%s" sender="%s" time="%s" alias="%s">%s</event>', @type, @sender, @time, @alias_str, @body)
	end
    end
end # end module