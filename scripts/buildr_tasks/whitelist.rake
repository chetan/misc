
# Buildr Whitelist generator
# Chetan Sarva <csarva@pixelcop.net>
#
# USAGE
#
# The only requirement is a buildfile with at least one remote Maven repo
# defined, at least one project definition, and this task file 
# at ./tasks/whitelist.rake relative to buildfile.
#
# Then run:
# 
#   buildr whitelist[org.springframework:spring-core:jar:3.0.1.RELEASE]
#

module BuildrWhitelist

    include Extension

    first_time do
        # Define task not specific to any projet.
        desc 'Generate flattened transitive dependency specs'
        Project.local_task('whitelist', :spec)
    end

    before_define do |project|
        # # Define the loc task for this particular project.
        project.task 'whitelist', :spec do |task, args|
            BuildrWhitelist.exec(args[:spec])
        end
    end

    def whitelist(spec)
        task('whitelist' => spec)
    end

    def self.exec(spec)
        if spec.nil? or spec.empty? then
            puts "ERROR: no spec passed"
            puts "usage: buildr whitelist[<spec>]"
            return
        end
        
        artifacts = Buildr.transitive(spec)
        
        puts
        puts "listing all transitive specs for: #{spec}"
        puts
        
        specs = []
        artifacts.each { |a|
            specs << "#{a.group}:#{a.id}:#{a.type}:#{a.version}"
        }

        # create constant
        orig = Buildr.artifact(spec)
        name = orig.id.gsub('-', '_').upcase
        puts "#{name} = ["

        # print all dependencies
        puts specs.sort.uniq.map { |s| "    \"#{s}\"" }.join(",\n")
        
        # close array
        puts "    ]"
        
        puts
    end

end

class Buildr::Project
    include BuildrWhitelist
end
