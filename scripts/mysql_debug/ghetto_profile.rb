#!/usr/bin/ruby

# == Synopsis 
#   Ghetto Profile
#   - A quick and dirty way to profile your stored procedures
#
# == Examples
#     ghetto_profile.rb --attach crappy_code.sql
#     mysql < crappy_code.sql
#     ghetto_profile.rb --stats -uroot -pmysql
#
# == Usage 
#   ghetto_profile.rb [options] [files]
#
#   For help use: ghetto_profile.rb --help
#
# == Options
#       --help          Displays help message
#   -V, --version       Display the version, then exit
#   -v, --verbose       Verbose output
#   
#   Commands
#   -s, --stats         Collect and display stats from debug database
#   -a, --attach        Attach profiling code (modifies source file)
#   -r, --detach        Detach profiling code
#
#   For use with --stats command
#   -h, --host [host]
#   -d, --database [name]
#   -u, --username [user]
#   -p, --password [pass]
#
# == Author
#   Chetan Sarva <csarva@operative.com>
#
# == Copyright
#   Copyright (c) 2008 Operative Media, Inc. Licensed under the BSD License:
#   http://www.opensource.org/licenses/bsd-license.php

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'dbi'
require 'yaml'

module Operative

class GhettoProfile

    VERSION = '0.7'
    
    attr_reader :options
    
    def initialize(arguments, stdin)
        @arguments = arguments
        @stdin = stdin
        
        # Set defaults
        @options = OpenStruct.new
        @options.verbose = false
        @options.database = 'debug'
        @options.host = 'localhost'
        @options.user = 'root'
        @options.pass = ''
        
    end

    # Parse options, check arguments, then process the command
    def run
    
        return output_usage if not (parsed_options? && arguments_valid?) 
        
        return do_stats if @options.stats
        return do_attach if @options.attach
        return do_detach if @options.detach
        
    end
  
    protected
  
        def parsed_options?
            # Specify options
            opts = OptionParser.new 
            opts.on('-V', '--version')    { output_version ; exit 0 }
            opts.on('--help')             { output_help }
            opts.on('-v', '--verbose')    { @options.verbose = true }  
            
            # mysql options
            opts.on('-u', '--username [user]')     { |u| @options.user = u || 'root' }
            opts.on('-p', '--password [pass]')     { |p| @options.pass = p || '' }
            opts.on('-h', '--host [host]')         { |h| @options.host = h || 'localhost' }
            opts.on('-d', '--database [database]') { |d| @options.database = d || 'debug' }
            
            # commands
            opts.on('-s', '--stats')    { @options.stats = true }
            opts.on('-a', '--attach')   { @options.attach = true }
            opts.on('-r', '--detach')   { @options.detach = true }
                
            opts.parse!(@arguments) rescue return false
          
            process_options
            true      
        end

        # Performs post-parse processing on options
        def process_options
            
            if @options.attach or @options.detach
                @options.files = @arguments
            end
            
        end

        # True if required arguments were provided
        def arguments_valid?
            num = 0
            num += 1 if @options.stats
            num += 1 if @options.attach
            num += 1 if @options.detach
            return false if num > 1
            return true
        end
    
        def output_help
            output_version
            RDoc::usage() #exits app
        end
    
        def output_usage
            RDoc::usage('usage') # gets usage from comments above
        end
    
        def output_version
            puts "#{File.basename(__FILE__)} version #{VERSION}"
        end
    
        def get_dbh()
            return connect(@options.host, @options.database, @options.user, @options.pass)
        end

        # connect to the database and return the handle
        # Mysql::CLIENT_MULTI_RESULTS = 131072
        def connect(host, name, user, pass)
            str = sprintf('DBI:Mysql:database=%s;host=%s;flag=%s', 
                        name, host, 131072)
            begin
                dbh = DBI.connect(str, user, pass)
            rescue => ex
            
                puts sprintf("[%s] Failed to connect to '%s' with username '%s'", Time.new, str, user) + 
                    "\n\t" + ex.inspect + 
                    "\n\t" + ex.backtrace.join("\n\t") 
                exit
                
            end
        end
        
        # add debug code to files
        def do_attach
            
            @options.files.each { |file|
                
                next if not File.exists? file
                
                @open = false
                @open_proc = ''
                @lines = ''
                
                File.new(file).each { |line|
                
                    if line =~ /^\s*call\s+([a-z0-9_.]+)\s*\(/i then
                        if not $1.include? 'debug'
                            @open = true
                            @open_proc = $1
                            @lines += sprintf("CALL debug.on('%s');", $1) + " -- added by ghetto_profile\n"
                            @lines += line
                            end_debug(line)

                        else
                            @lines += line
                            end_debug(line)
                            
                        end
                    else
                        @lines += line
                        end_debug(line)

                    end
                    
                }
                
                File.new(file, 'w').write(@lines)
                
            }
            
        end
        
        def end_debug(line)

            if line =~ /\)\s*;\s*$/ and @open then
                @lines += sprintf("CALL debug.off('%s');", @open_proc) + " -- added by ghetto_profile\n"
                @open = false
                @open_proc = ''
            end        
        end
        
        # remove debug code from files
        def do_detach
        
            @options.files.each { |file|
                
                next if not File.exists? file
                
                @open = false
                @open_proc = ''
                @lines = ''
                
                File.new(file).each { |line|
                
                    if line !~ /added by ghetto_profile/ then
                        @lines += line
                    end
                
                }
                
                File.new(file, 'w').write(@lines)
                
            }
        
        end
    
        def do_stats
        
            dbh = get_dbh()
            
            query = dbh.prepare('SELECT * FROM debug.debug')
            query.execute()
            
            procs = {}
            stacks = {}
            i = 0
            
            query.fetch_hash { |row|
            
                i += 1
                
                proc = row['proc_id']
                state = row['debug_output']
                
                if state == 'start' then
                    if not stacks.has_key? proc then
                        stacks[proc] = []
                    end
                    stacks[proc] << [ proc, Time.parse(row['ts']) ]
                    
                elsif state == 'end' then
                    # find the last proc and compute the time
                    close = stacks[proc].pop
                    
                    # add the timing to the list
                    if procs.has_key? proc then
                        stat = procs[proc]
                    else
                        stat = OpenStruct.new
                        stat.proc = proc
                        stat.times = []
                    end
                    
                    time_end = Time.parse(row['ts'])
                    
                    stat.times << time_end - close[1]
                    procs[proc] = stat
                    
                    #if i > 100 then
                        #puts procs.to_yaml
                        #break
                    #end
                    
                end
                
            }
            
            total = 0
            total_count = 0
            
            procs.each_pair { |proc, stat|
                stat.num = stat.times.length
                stat.min = stat.times.min
                stat.max = stat.times.max
                
                # calc average and total
                sum = 0
                stat.times.each { |i| sum += i }
                
                stat.total = sum
                stat.total_min = sum / 60
                stat.avg = stat.total / stat.num
                
                total += sum
                total_count += stat.num
                
            }
            
            # calculate % of total
            procs.each_pair { |proc, stat|
                stat.pct = stat.total / total * 100
            }
            
            puts sprintf("total time: %.4f\n\n", total)
            
            procs.sort { |a,b|
                # sort in descending order by percentage
                b[1].pct <=> a[1].pct
                
            }.each { |item|
                
                stat = item[1]
            
                puts stat.proc
                puts sprintf("\t pct:   %.4f", stat.pct)
                puts sprintf("\t total: %.4f (%.2f)", stat.total, stat.total_min)
                puts sprintf("\t avg:   %.4f", stat.avg)
                puts sprintf("\t count: %s", stat.num)
                puts sprintf("\t min:   %s", stat.min)
                puts sprintf("\t max:   %s", stat.max)
                puts ""
            
            }
            
        end

end

end

zydeco = Operative::GhettoProfile.new(ARGV, STDIN)
zydeco.run
