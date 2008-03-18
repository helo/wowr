# Wowr - Ruby library for the World of Warcraft Armory
# http://wowr.rubyforge.org/

# written by Ben Humphreys
# http://benhumphreys.co.uk/

begin
	require 'hpricot' # version 0.6
rescue LoadError
	require 'rubygems'
	require 'hpricot' # version 0.6
end
require 'net/http'
require 'cgi'
require 'fileutils' # for making cache directories

require 'wowr/exceptions.rb'
require 'wowr/extensions.rb'
require 'wowr/classes.rb'

module Wowr
	class API

		@@armory_url = 'http://www.wowarmory.com/'
		@@eu_armory_url = 'http://eu.wowarmory.com/'
		
		@@search_url = 'search.xml'
		
		@@character_sheet_url = 'character-sheet.xml'
		@@character_talents_url = 'character-talents.xml'
		@@character_skills_url = 'character-skills.xml'
		@@character_reputation_url = 'character-reputation.xml'
		
		@@guild_info_url = 'guild-info.xml'
		
		@@item_info_url = 'item-info.xml'
		@@item_tooltip_url = 'item-tooltip.xml'

		@@arena_team_url = 'team-info.xml'
		
		@@max_connection_tries = 10
		
		@@cache_directory_path = 'cache/'

		# Tiny forum-used race/class icons
		# @@icon_url = 'http://wowbench.com/images/icons/32x32/'		
		# http://forums.worldofwarcraft.com/images/icon/class/4.gif
		# http://forums.worldofwarcraft.com/images/icon/race/3-0.gif
		# http://forums.worldofwarcraft.com/images/icon/pvpranks/rank_default_0.gif
		
		# Spell stuff
		# http://armory.worldofwarcraft.com/images/icons/21x21/spell_nature_thorns.png
		# http://armory.worldofwarcraft.com/images/icons/21x21/ability_mount_mountainram.png
		
		# Part of the rails plugin stuff?
		# @@profession_icons = {
		# 	:alchemy => "Trade_Alchemy.png",
		# 	:blacksmithing => "Trade_BlackSmithing.png",
		# 	:engineering => "Trade_Engineering.png",
		# 	:enchanting => "Trade_Engraving.png",
		# 	:jewelcrafting => "INV_Hammer_21.png",
		# 	:herbalism => "Trade_Herbalism.png",
		# 	:leatherworking => "Trade_LeatherWorking.png",
		# 	:mining => "Trade_Mining.png",
		# 	:tailoring => "Trade_Tailoring.png",
		# 	:skinning => "INV_Weapon_ShortBlade_01.png"
		# }
		
		@@classes = {
			1 => 'Warrior',
			2 => 'Paladin',
			3 => 'Hunter',
			4 => 'Rogue',
			5 => 'Priest',
			#6 => 'Gold Farmer', # there is no class 6
			7 => 'Shaman',
			8 => 'Mage',
			9 => 'Warlock',
			#10 => 'Purveyor of Baked Goods', # there is no class 10
			11 => 'Druid'
		}
		
		@@genders = {
			0 => 'Male',
			1 => 'Female'
		}
		
		@@races = {
			1 => 'Human',
			1 => 'Orc',
			3 => 'Dwarf',
			4 => 'Night Elf',
			5 => 'Undead',
			6 => 'Tauren',
			7 => 'Gnome',
			8 => 'Troll',
			#9 => 'Pandaren', # there is no race 9
			10 => 'Blood Elf',
			11 => 'Draenei'
		}

		@@search_types = {
			#:all => 'all',	# TODO: All is too complex at the moment, API doesn't return all results in one query
			:item => 'items',
			:character => 'characters',
			:guild => 'guilds',
			:arena_team => 'arenateams'
		}
		
		@@arena_team_sizes = [2, 3, 5]

		attr_accessor :character_name, :guild_name, :realm, :locale, :caching
		
		# You can set up the API with an optional default guild and realm
		# These will be used in all your API requests unless you specify otherwise
		# For item requests, the locale will not matter in results, but may affect the speed of replies
		# Caching is off by default
		# TODO: are these nil declarations pointless?
		def initialize(options = {:character_name => nil,
															:guild_name => nil,
															:realm => nil,
															:locale => :us,
															:caching => false})
			@character_name = options[:character_name]
			@guild_name			= options[:guild_name]
			@realm					= options[:realm]
			@locale					= options[:locale] #|| :us
			@caching				= options[:caching]
		end
		
		
		# General-purpose search
		# All specific searches are wrappers around this method.
		# Caching is disabled for searching
		def search(options = {:search => nil, :type => nil})
			if @@search_types.include? options[:type]
				raise Wowr::Exceptions::InvalidSearchType.new
			end
			
			if options[:search].nil?
				raise Wowr::Exceptions::NoSearchString.new
			end
			
			options.merge!(:caching => false)
			
			xml = get_xml(@@search_url, options)
			
			results = []
			
			if (xml) && (xml%'armorySearch') && (xml%'armorySearch'%'searchResults')
				case options[:type]
				
					# TODO: Filter stuff
					when @@search_types[:item]
						(xml%'armorySearch'%'searchResults'%'items'/:item).each do |item|
							results << Wowr::Classes::SearchItem.new(item)
						end
					
					when @@search_types[:character]
						(xml%'armorySearch'%'searchResults'%'characters'/:character).each do |char|
							results << Wowr::Classes::Character.new(char)
						end
					
					when @@search_types[:guild]
						(xml%'armorySearch'%'searchResults'%'guilds'/:guild).each do |guild|
							results << Wowr::Classes::Guild.new(guild)
						end
					
					when @@search_types[:arena_team]
						(xml%'armorySearch'%'searchResults'%'arenaTeams'/:arenaTeam).each do |team|
							results << Wowr::Classes::ArenaTeam.new(team)
						end
				end
			end
			
			return results
		end
		
		
		
		# Characters
		# Note searches go across all realms by default
		# Caching is disabled for searching
		def search_characters(options = {:name => @character_name})
			options.merge!(:type => @@search_types[:character])
			return search(options)
		end
		
		def get_character_sheet(options = {:character_name => @character_name, :realm => @realm, :caching => @caching})			
			xml = get_xml(@@character_sheet_url, options)
			
			# resist_types = ['arcane', 'fire', 'frost', 'holy', 'nature', 'shadow']
			# @resistances = {}
			# resist_types.each do |res|
			# 	@resistances[res] = Wowr::Classes::Resistance.new(xml%'resistances'%res)
			# end
			# puts @resistances.to_yaml
			# puts xml
			return Wowr::Classes::CharacterSheet.new(xml)
		end
		
		
		
		# Guilds
		# Note searches go across all realms by default
		# Caching is disabled for searching
		def search_guilds(options = {:search => @guild_name, :locale => @locale})
			options.merge!(:type => @@search_types[:guild])
			return search(options)
		end
		
		def get_guild(options = {:guild_name => @guild_name, :realm => @realm, :caching => @caching})
			xml = get_xml(@@guild_info_url, options)
			return Wowr::Classes::Guild.new(xml)
		end
		
		
		
		# Items
		# Items are not realm-specific
		# Caching is disabled for searching
		def search_items(options = {:search => nil})
			options.merge!(:type => @@search_types[:item])
			return search(options)
		end
		
		# TODO: Is not finding the item an exception or just return nil?
		#def get_item(options = {:item_id => nil, :locale => @locale})
			
			#return Wowr::Classes::ItemTooltip.new(xml%'itemTooltip')
		#end
		
		def get_item_info(options = {:item_id => nil, :locale => @locale, :caching => @caching})
			xml = get_xml(@@item_info_url, options)
			if (xml%'itemInfo'%'item')
				return Wowr::Classes::ItemInfo.new(xml%'itemInfo'%'item')
			else
				return nil
			end
		end
		
		def get_item_tooltip(options = {:item_id => nil, :caching => @caching})
			xml = get_xml(@@item_tooltip_url, options)
			
			# tooltip returns empty document when not found
			if xml.nil?
				return nil
				#raise Wowr::Exceptions::ItemNotFound.new("Item not found with id: #{options[:item_id]}")
			end
			return Wowr::Classes::ItemTooltip.new(xml%'itemTooltip')
		end
		
		
		
		# Arena Teams
		# Caching is disabled for searching
		def search_arena_teams(options = {})
			options.merge!(:type => @@search_types[:arena_team])
			return search(options)
		end
		
		def get_arena_team(options = {:team_name => :nil, :team_size => nil, :realm => @realm, :caching => @caching})
			if !@@arena_team_sizes.include?(options[:team_size])
				raise Wowr::Exceptions::InvalidArenaTeamSize.new("Arena teams size must be: #{@@arena_team_sizes.inspect}")
			end
			
			xml = get_xml(@@arena_team_url, options)
			return Wowr::Classes::ArenaTeam.new(xml%'arenaTeam')
		end
		
		# this is more of a rails-plugin thing
		# def icon(icon_url)
		# 	@@icon_url + icon_url
		# end
		
		
		# Clear the cache, optional filename
		def clear_cache(cache_path = @@cache_directory_path)
			begin
				FileUtils.remove_dir(cache_path)
			rescue Exception => e 

			end
		end
		
		
		protected
		
		# TODO: pretty damn hacky
		def get_xml(url, options = {:caching => @caching})
			# better way of doing this?
			# Map custom keys to the HTTP request values 
			reqs = {
				:character_name => 'n',
				:realm => 'r',
				:search => 'searchQuery',
				:type => 'searchType',
				:guild_name => 'n',
				:item_id => 'i',
				:team_size => 'ts',
				:team_name => 't'
			}
			
			params = []
			options.each do |key, value|
				if reqs[key]
					params << "#{reqs[key]}=#{u(value)}"
				end
			end
			
			if params.size > 0
				query = '?' + params.join('&')
			end
			
			locale = options[:locale] || @locale
			
			base = self.base_url(locale)
			full_query = base + url + query
			
			#puts full_query
			
			if options[:caching]
				response = get_cache(full_query)
			else
				response = http_request(full_query)
			end
			
			# puts response
			
			doc = Hpricot.XML(response)
			begin
				errors = doc.search("*[@errCode]")
				#errors.to_yaml
				if errors.size > 0
					errors.each do |error|
						raise Wowr::Exceptions::raise_me(error[:errCode])
					end
				# elsif (doc%'page').nil?
				# 	puts full_query
				# 	puts response
				# 	raise Wowr::Exceptions::EmptyPage
				else
					return (doc%'page')
				end
			rescue Exception => e 
				$stderr.puts "Fatal error ((#{e.to_s})): Couldn't search the XML document."
				$stderr.puts doc
				exit 1
			end
			
		end
		
		# TODO Rename
		def http_request(url)
			req = Net::HTTP::Get.new(url)
			req["user-agent"] = "Mozilla/5.0 Gecko/20070219 Firefox/2.0.0.2"
			
			uri = URI.parse(url)
			
		  http = Net::HTTP.new uri.host, uri.port
		  http.start do
		    res = http.request req
				response = res.body
		  end
			
			# tries = 0
			# 			response = case res
			# 			when Net::HTTPSuccess, Net::HTTPRedirection
			# 				res.body
			# 			else
			# 				tries += 1
			# 				if tries > @@max_connection_tries
			# 					raise Wowr::Exceptions::NetworkTimeout.new('Timed out')
			# 				else
			# 					retry
			# 				end
			# 			end
			
			
			#response = res.body
			
			# while
			# 				tries += 1
			# 				if tries > @@max_connection_tries
			# 					raise Wowr::Exceptions::NetworkTimeout.new('Timed out')
			# 				else
			# 					retry
			# 				end
			# 			end
			# 			
			# 			begin
			# 				res = Net::HTTP.new(uri.host, uri.port).start {|http| http.request(req) }
			# 			rescue Timeout::Error => e
			# 				retry  
			# 				#raise Wowr::Exceptions::NetworkTimeout.new('Timed out')
			# 			end
			# 			
			# 			tries = 0
			# response = case res
			# when Net::HTTPSuccess, Net::HTTPRedirection
			# 	res.body
			# else
			# 	
			# end
		end
		
		
		def get_cache(url)
			path = @@cache_directory_path + url_to_filename(url);
			
			# file doesn't exist, make it
			if !File.exists?(path)
				
				# TODO: Hacky
				FileUtils.mkdir_p(@@cache_directory_path + 'us/') unless File.directory?(@@cache_directory_path + 'us/')
				FileUtils.mkdir_p(@@cache_directory_path + 'eu/') unless File.directory?(@@cache_directory_path + 'eu/')
				
				xml_content = http_request(url)
				
				# write the cache
				file = File.open(path, File::WRONLY|File::TRUNC|File::CREAT)
				#file = File.open(path, 'w')
				file.write(xml_content)
				file.close
			
			# file exists, return the contents
			else
				file = File.open(path, 'r')
				xml_content = file.read
				file.close
			end
			return xml_content
		end
		
		
		
		# :nodoc:
		# remove http://
		def url_to_filename(url)
			if (url.include?(@@armory_url))
				path = 'us/' + url.gsub(@@eu_armory_url, '')
			elsif (url.include?(@@eu_armory_url))
				path = 'eu/' + url.gsub(@@eu_armory_url, '')
			end
			
			return path
		end
		
		
		# :nodoc:
		def base_url(locale = @locale)
			if locale == :eu
				@@eu_armory_url
			else
				@@armory_url
			end
		end
		
		
		# :nodoc:
		def u(str)
			if str.instance_of?(String)
				return CGI.escape(str)
			else
				return str
			end
		end
	end
end