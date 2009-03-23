#!/usr/bin/ruby

# relink.rb
# usage: ./relink.rb [fix]
# 
# simple script to "re-link" tracks with the file on disk when iTunes forgets
# where it was. if your files are organized using itunes, then this will work 
# without any modifications. if you use some other convention, the code below
# should be a good starting point for you. 
#
# requires: ruby appscript library
#           $ sudo gem install rb-appscript
# 
# chetan sarva <csarva@pixelcop.net>
# 2009-03-22

# set path below for directory to search for music in
@path = '/Volumes/SomeWhere/Music/'

# --- end config

require 'rubygems'
require 'appscript'
include Appscript

require "osax"
include OSAX

# only argument for this script
@fix = false
if ARGV[0] == 'fix' then
    @fix = true
end

# gogogo

def create_path(t, disc = false)
    album_path = sprintf("%s/%s/%s", @path, cln(t.artist.get), cln(t.album.get))
    if not disc then
        return sprintf("%s/%02d %s.mp3", album_path, t.track_number.get, cln(t.name.get, false))
    else
        return sprintf("%s/%s-%02d %s.mp3", 
                       album_path, t.disc_number.get, 
                       t.track_number.get, cln(t.name.get, false))
    end
end

def fix_location(track, path)

    begin
        track.location.set( MacTypes::Alias.path(path) )
        puts "\t\t  updated location"
        @fixed += 1
    rescue => e
        puts "\t\t  !! failed to update location with error " + e
    end

end

def test_location(track, path)

    begin
        if File.exists? path then
            puts "\t\t+ found at: " + path
            fix_location(track, path) if @fix
            return true
        end
    rescue => e
         puts "\t!! failed to test filename #{path} - error: #{e}"
    end
    
    return false
        
end

# replace characters not allowed in filenames
def cln(str, dot = true)
    str.gsub!('/', '_')
    str.gsub!(':', '_')
    str.gsub!('?', '_')
    str.gsub!(/\.$/, '_') if dot
    str    
end

# get selected tracks
itunes = app('iTunes')
tracks = itunes.selection.get

@found = 0
@fixed = 0

# search for tracks with missing location
tracks.each { |t|
    if t.location.get == :missing_value then
    
        @found += 1
        
        song_name = sprintf("\t%s / %s / %02d %s", 
                            t.artist.get, t.album.get, t.track_number.get, t.name.get)
        puts song_name

        if not test_location(create_path(t), track_path) then
            # look for file name is standard location
            if t.disc_count.get != :missing_value then
                # look for multi-disc file naming
                test_location(create_path(t, true), track_path)                     
            end            
        end
        
    end
}

puts
puts "---"
puts "selected #{tracks.size} tracks"
puts "found #{@found} missing"
puts "fixed #{@fixed}"
puts