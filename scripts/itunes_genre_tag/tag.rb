#! arch -i386 /usr/bin/ruby

require 'amg'

require 'rubygems'
require 'json'

require 'appscript'
require 'osax'

include Appscript
include OSAX

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
