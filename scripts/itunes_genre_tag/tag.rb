#! arch -i386 /usr/bin/ruby

require 'rubygems'

if RUBY_PLATFORM =~ /darwin/ then
    # fix for scrapi on Mac OS X
    require "tidy"
    Tidy.path = "/usr/lib/libtidy.dylib" 
end

require 'scrapi'
require 'ostruct'
require 'uri'
require 'net/http'
require 'htmlentities'
require 'json'

require 'appscript'
require 'osax'

include Appscript
include OSAX

module AllMusicGuide
    
    class Scraper
        
        def initialize(debug = false)
            @base = "http://www.allmusic.com"
            @decoder = HTMLEntities.new
            @debug = debug
        end

        def get_url(url)
            uri = URI.parse(URI.escape(url))
            if @debug then
                # check the cache
                cachekey = "/tmp/amg-" + uri.to_s.gsub(%r{[/&:.?~]}, '_')
                if File.exists? cachekey then
                    return File.new(cachekey).read
                end
            end
            http = Net::HTTP.new(uri.host, uri.port)
            html = http.start do |http|
                req = Net::HTTP::Get.new(uri.path + '?' + uri.query, {"User-Agent" => "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.0.10) Gecko/2009042315 Firefox/3.0.10"})
                response = http.request(req)
                response.body
            end
            if @debug then
                # cache response
                File.new(cachekey, "w").write(html)
            end
            return html
        end
        
        def decode(str)
            str.gsub!(/&nbsp;/, ' ')
            str = @decoder.decode(str)
            return str.strip
        end

        def find_artist(name, album = nil, year = nil)
            
            artists = search_for_artists(name)
            return nil if artists.nil? or artists.empty?
            
            if album.nil? or artists.size == 1 then
                # return the first (highest ranking) artist
                artists[0].guess = false
                artists[0].albums, artists[0].styles = get_albums(artists[0])
                return artists[0]
            end
            
            # now that we have a list of artists, look for the best fit
            
            # by album title
            result = search_for_album_match(artists, album, year)
            return result if not result.nil?
            
            # let's look for the correct decade
            result = search_by_decade(artists, year)
            return result if not result.nil?            
            
            # if we got here, let's just use the first result
            puts ">> fallback to first artist (most relavent according to AMG)"
            artists[0].guess = true
            return artists[0]
            
        end
        
        def search_for_album_match(artists, album, year)
            puts ">> looking for artist with album match"
            i = 0
            artists.each { |artist|
                i += 1
                break if i > 3
                puts "   loading albums for #{artist.name}"
                albums, styles = get_albums(artist)
                artist.albums = albums
                artist.styles = styles
                next if albums.nil? or albums.empty?
                albums.each { |al| 
                    if al.title == album or
                        al.title.downcase == album.downcase or
                        al.title.downcase.start_with? album.downcase then
                        
                        puts "> found album: #{al.title}"
                        artist.guess = false                    
                        return artist
                    end
                }
            }
            return nil
        end
        
        def search_by_decade(artists, year)
            puts ">> looking for artist with decade match"
            decade = year - (year % 10)
            return artists.find { |artist|    
                years = normalize_years( parse_years(artist.years) )
                artist.decades = years
                next if years.nil? or years.empty?
                if years.include? decade then
                    artist.guess = true
                    break artist
                end
            }
        end
        
        def parse_years(str)
            str.strip!
            str.gsub!(/\s+/, "")
            return [] if str.nil? or str.empty?
            if str !~ /[,-]/ then
                return [str]
            end
            if str =~ /,/ then
                return str.split(',')
            end
            if str =~ /(\d\d)s-(\d\d)s/ then
                # range of years
                start = $1.to_i + 1900
                fin   = ($2 == '00' ? 2000 : $2.to_i + 1900)
                i = start
                years = [start]
                until i == fin do
                    i += 10
                    years << i
                end
                return years
            end
        end
        
        # normalize to a list of integers only
        def normalize_years(years)
            return years if years.nil? or years.empty?
            return years.map { |y|
                if y !~ /s$/ then 
                    next y
                elsif y == '00s' then 
                    next 2000
                elsif y =~ /(\d\d)s/ then 
                    next ($1.to_i + 1900)
                end
            }
        end
        
        def search_for_artists(name)
           
            # opt1 => 1 = artist
            #         2 = album
            #         3 = song
            #         4 = classical work

            url = "#{@base}/cg/amg.dll?P=amg&samples=1&opt1="
            url += "1"
            url += "&sql=#{name}"
            #puts url
            
            html = get_url(url)
            File.new("/tmp/amg.html", "w").write(html)
            #html = IO.read("/tmp/amg.html")
            #puts html
            
            artists = scrape_artist_results(html)
            
        end
        
        def scrape_artist_results(html)
            
            artist_scraper = ::Scraper.define do
                
                array :artists
                array :links
                array :genres
                array :years
                
                process "table#ExpansionTable1 tr.visible td:nth-child(3) a", :artists   => :text
                process "table#ExpansionTable1 tr.visible td:nth-child(3) a", :links     => "@href"
                process "table#ExpansionTable1 tr.visible td:nth-child(4)",   :genres    => :text
                process "table#ExpansionTable1 tr.visible td:nth-child(5)",   :years     => :text
                
                result :artists, :links, :genres, :years
            end
            
            ret = artist_scraper.scrape(html)
            return scrape_artist_page(html) if ret.artists.nil?
            
            artists = []
            ret.artists.each_index { |i| 
                a = OpenStruct.new
                a.name      = decode(ret.artists[i])
                a.link      = decode(ret.links[i])
                a.genre     = decode(ret.genres[i])
                a.years     = decode(ret.years[i])
                artists << a
            }
            
            return artists
            
        end
        
        def scrape_artist_page(html)
            
            page_scraper = ::Scraper.define do
                array :genres
                array :years
                process "span.title", :artist => :text
                process_first "div#left-sidebar-list ul li", :genres => :text
                process "div.timeline-sub-active", :years => :text
                process_first "div#tabs a", :link => "@href"
                result :artist, :link, :genres, :years
            end
            
            ret = page_scraper.scrape(html)
            return nil if ret.artist.nil?
            
            a = OpenStruct.new
            a.name = decode(ret.artist)
            a.link = decode(ret.link.gsub(/~T0$/, ''))
            a.genre = decode(ret.genres[0])
            a.years = ret.years
            
            return [a]
        end
        
        def get_albums(arg, all = true)
            
            # http://www.allmusic.com/cg/amg.dll?p=amg&sql=11:hpfqxzegldhe
            # http://www.allmusic.com/cg/amg.dll?p=amg&sql=11:hpfqxzegldhe~T2
            
            if arg.kind_of? String then
                url = arg
            elsif arg.kind_of? OpenStruct then
                url = @base + arg.link
            end
            url += "~T2" if url !~ /~T2$/
            #puts url

            # get main albums
            albums, ret = scrape_albums(url)
            return nil if (albums.nil? or albums.empty?) and ret.nil?

            styles = nil
            if ret.styles then
                styles = filter_styles(ret.styles)
            end
            
            # scrape sub-menu pages (Compilations, Singles & EPs, DVDs & Videos, Other)
            ret.links.each { |link|
                next if link =~ /~T20$/
                more_albums, r = scrape_albums(@base + decode(link))
                albums += more_albums
            }

            return [albums, styles]
        end
        
        def filter_styles(list)
            styles = []
            str = list[0]
            i = 0
            list = str.split("\n").find_all { |s|
                next if s.strip.empty?
                true
            }
            list.each { |s|
                if s.include? '<!--Style Listing-->' then
                    i += 1
                    break if i == 2
                elsif i > 0 then
                    styles << s
                end
            }
            return styles
        end
        
        def scrape_albums(url)
            
            html = get_url(url)
            File.new("/tmp/amg2.html", "w").write(html)
            #html = IO.read("/tmp/amg2.html")
            #puts html
            
            album_scraper = ::Scraper.define do
                
                array :years
                array :titles
                array :labels
                array :links
                array :styles

                process "td.styles_moods", :styles => :text
                process "table#ExpansionTable1 tr.visible td:nth-child(3)", :years  => :text
                process "table#ExpansionTable1 tr.visible td:nth-child(5)", :titles => :text
                process "table#ExpansionTable1 tr.visible td:nth-child(7)", :labels => :text
                process "div.sub-menu-layer a", :links => "@href"
                
                result :titles, :years, :labels, :links, :styles
            end
            
            ret = album_scraper.scrape(html)
            return nil if ret.nil? or ret.titles.nil?
            
            albums = []
            ret.titles.each_index { |i| 
                a = OpenStruct.new
                a.title = decode(ret.titles[i])
                a.year = decode(ret.years[i])
                a.labels = decode(ret.labels[i])
                albums << a
            }
            return [albums, ret]
        end
        
    end
    
end

amg = AllMusicGuide::Scraper.new(true)
# artist = amg.find_artist("Girls")

# btn = osax.display_dialog("hi?", :buttons => ['Cancel', 'HFS', 'POSIX'], :default_button => 2)
# clicked = btn[:button_returned]
# osax.display_dialog(clicked, :buttons => ['OK'], :with_title => "Clicked")
# exit


# load prefs file
prefs_dir = ENV['HOME'] + "/.amg"
prefs_file = "#{prefs_dir}/cache.json"
if File.exists? prefs_dir then
    if File.exists? prefs_file then
        cache = JSON.parse(File.new(prefs_file).read)
        cache.each { |key,val|
            val = OpenStruct.new(val)
            val.albums.map! { |al|
                OpenStruct.new(al)
            }
            cache[key] = val
        }
    else
        cache = {}
    end
else
    # create an empty file
    Dir.mkdir(prefs_dir) 
    cache = {}
end

itunes = app('iTunes')
tracks = itunes.selection.get

if tracks.empty? then
    puts "no tracks selected!"
    exit
end

class OpenStruct
    def to_json
        table.to_json
    end
end

class Artist
    attr_accessor :name, :albums, :amg, :cached
    def initialize
        @albums = {}
    end
    def [](key)
        @albums[key]
    end
    def []=(key, val)
        @albums[key] = val
    end
    def include?(key)
        @albums.include? key
    end
end

itunes_tracks = {}

tracks.each { |track| 
    
    compilation = track.compilation.get
    next if compilation
    
    artist = track.artist.get
    album = track.album.get
    genre = track.genre.get
    year = track.year.get
    
    if not itunes_tracks.include? artist then
        a = Artist.new
        a.name = artist
        itunes_tracks[artist] = a
    end
    
    if not itunes_tracks[artist].include? album then
        oalbum = OpenStruct.new
        oalbum.title = album
        oalbum.artist = artist
        oalbum.genre = genre
        oalbum.year = year
        oalbum.tracks = []
        itunes_tracks[artist][album] = oalbum
    end
    
    itunes_tracks[artist][album].tracks << track
    
    if itunes_tracks[artist][album].amg.nil? then
        
        # try to find the artist for this album
        
        puts ">>> NEW: #{artist} - #{album} / genre: '#{genre}'"
        
        if cache.include? artist then
            # skip lookup
            puts "    found in cache: #{cache[artist]}"
            itunes_tracks[artist].cached = true
            next
        end
        
        if not itunes_tracks[artist].amg.nil? then
            amg_artist = itunes_tracks[artist].amg
        else
            # search AMG
            amg_artist = amg.find_artist(artist, album, year)
            if amg_artist.nil? then
                puts "!!! couldn't find matching artist"
                itunes_tracks[artist][album].amg = "n/a"
                next
            end
            puts
        end
        
        itunes_tracks[artist][album].amg = amg_artist
        
        puts "#    found: #{amg_artist.name}"
        puts "#    suggested genre: #{amg_artist.genre}"
        puts "#    artist is best guess? " + (amg_artist.guess ? "yes" : "no")
        
        if amg_artist.guess == false and itunes_tracks[artist].amg.nil? then
            # not a guess, associate with artist too
            itunes_tracks[artist].amg = amg_artist
        end
        
    end
}

puts "\n\n\n"
puts "summary: \n\n"

itunes_tracks.each { |name, artist|
    
    amg = nil
    if artist.cached then
        amg = cache[name]
        
    elsif not artist.amg.nil? then
        amg = artist.amg
        
    else
        album = artist.albums.values.find { |a| not a.amg.nil? }
        amg = album.amg
    end
    
    if amg.nil? then
        puts "#{name} = n/a"
        next
    end
    
    # insert into cache
    cache[name] = amg if not cache.include? name    
    
    # print summary
    puts "#{name} = #{amg.genre}, #{amg.styles.join(', ')}"
    artist.albums.each { |album_name, album| 
        puts "   #{album.title} --- '#{album.genre}' => #{amg.genre}"
    }
    
}

#exit

# save the cache
File.new(prefs_file, "w").write(cache.to_json)
