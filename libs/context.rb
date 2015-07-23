require 'yaml'
require 'methadone'
require_relative 'replace_obj_vars'

class Context

  attr_accessor :always_deploy,
                :container_version_finder,
                :deployment_home,
                :env_name,
                :settings,
                :vars

  include Methadone::Main
  include Methadone::CLILogging

  def initialize(settings,
                 container_version_finder,
                 deployment_home,
                 always_deploy=false,
                 env_name=nil,
                 vars=nil)

    debug "Creating initial context..."
    @container_version_finder = container_version_finder
    @settings = settings
    @deployment_home = deployment_home
    @always_deploy = always_deploy
    @env_name = env_name || settings.default_env_name
    @vars = vars
  end

  def environment
    return @vars unless @vars.nil?

    # If not set, Try to find them...
    glob_path = File.join(@deployment_home, @settings.env_file_glob_path)
    regexp_find = glob_path.gsub(/\*/, '(.*)')
    Dir[glob_path].each do | file_name |
      # Get the environment name from the file part of the glob path:
      # e.g. given ./environments/ci_mgt/kb8or.yaml
      #      get ci_mgt from ./environments/*/kb8or.yaml
      /#{regexp_find}/.match(file_name)
      env_name = $1
      if env_name == @env_name
        debug "env=#{env_name}"
        @vars = Context.resolve_env_file(file_name)
        break
      end
    end
    debug "vars=#{vars}"
    @vars
  end

  def resolve_vars_in_file(file_path)
    data = YAML.load(File.read(file_path))
    resolve_vars(data)
  end

  def resolve_vars(data)
    ReplaceObjVars.new(environment).replace(data)
  end

  def self.resolve_env_file(file_path)
    data = YAML.load(File.read(file_path))

    # Resolve any vars within the env file:
    vars_resolver = ReplaceObjVars.new(data)
    vars_resolver.replace(data)
  end

  def new(data)
    debug "Cloning new context..."
    context = Context.new(@settings.new(data),
                          @container_version_finder,
                          @deployment_home,
                          @always_deploy,
                          @env_name,
                          @vars)
    context
  end
end