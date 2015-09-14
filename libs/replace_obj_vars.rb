require_relative 'kb8_utils'

class ReplaceObjVars
  # Class to replace any string references in an object with values from a hash

  REGEXP_VAR = '\${\W*(.*?)\W*}'
  FILE_INCLUDE = 'file://'
  INCLUDE_KEY = 'FileIncludePaths'

  attr_reader :vars
  attr_accessor :updates

  include Methadone::Main
  include Methadone::CLILogging

  def initialize(vars_hash, context_path)
    # TODO: walk top level values and parse out "deep merge actions"
    @context_path = context_path
    @vars = vars_hash
  end

  def replace(obj)
    ReplaceObjVars.replace(obj, self, @context_path)
  end

  def self.load_file(file_name, root)
    if file_name.start_with?('/')
      path = file_name
    else
      path = File.join(root, file_name)
    end
    file_data = Kb8Utils.load_yaml(File.open(path))
    file_data
  end

  # Recursive object to replace items as we go:
  def self.replace(obj, context, context_path)
    case obj.class.to_s
      when 'String'
        # Detect parse requirements
        case obj.strip
          when /^#{REGEXP_VAR}$/
            # If the entire element is to be replaced:
            key = $1.to_s
            if key.start_with?(FILE_INCLUDE)
              file_data = load_file(key, context_path)
              obj = ReplaceObjVars.replace(file_data, context, context_path)
            end
            return context.vars[key] if context.vars.has_key?(key)
          when /#{REGEXP_VAR}/
            # Multiple strings found so replace all matching
            /#{REGEXP_VAR}/.match(obj) do | match |
              match.captures.each do |capture|
                key = capture.to_s

                if context.vars.has_key?(key)
                  debug "obj update (multimatch) - #{context.vars[key]}"
                  obj = obj.gsub(/(#{REGEXP_VAR})/, context.vars[key].to_s)
                end
              end
            end
          else
            # No more parsing:
            return obj
        end
      when 'Hash'
        # Replace all elements by key...
        files = []
        obj.each_key do | key |
          # Detect File replacements here:
          if key == INCLUDE_KEY
            files = obj[key]
          end
        end
        new_data = {}
        files.each do | file |
          file_data = load_file(file, context_path)
          new_data = file_data.merge(new_data)
        end
        obj = obj.merge(new_data)
        obj.each_key do | key |
          obj[key] = ReplaceObjVars.replace(obj[key], context, context_path)
        end
      when 'Array'
        obj.each_index do | index |
          obj[index] = ReplaceObjVars.replace(obj[index], context, context_path)
        end
      else
        return obj
    end
    obj
  end
end
