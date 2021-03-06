require 'methadone'
require_relative 'file_secrets'
require_relative 'multi_template'

class Kb8DeployUnit

  attr_accessor :context,
                :only_deploy,
                :resources,
                :changed_resources

  include Methadone::Main
  include Methadone::CLILogging

  def initialize(data, context, deploy_file, only_deploy=nil, no_diff=false)
    @no_diff = no_diff
    @only_deploy = only_deploy
    debug 'Loading new context'
    data = context.resolve_vars(data.dup)
    @context = context.new(data)
    @context.update_vars(data)
    debug 'Got new context'
    unless @context.settings.path
      puts "Invalid deployment unit (Missing path) in deployment file '#{deploy_file}'."
      exit 1
    end
    path = @context.resolve_vars([@context.settings.path])
    dir = File.join(@context.deployment_home, path.pop)
    @resources = {}
    actual_dir = File.expand_path(dir)
    @changed_resources = []

    if @context.settings.file_secrets
      add_resource(FileSecrets.create_from_context(@context))
    end

    # Load all kb8 files...
    Dir["#{actual_dir}/*.yaml"].each do | file |
      debug "Loading kb8 file:'#{file}'..."
      Kb8Utils.load_multi_yaml(file).each do |data|
        new_items = nil

        kb8_data = @context.resolve_vars(data)
        debug "kb8 data:#{kb8_data}"

        if @context.settings.multi_template
          multi_template = MultiTemplate.new(kb8_data, @context, file, dir)
          new_items = multi_template.items if multi_template.valid_data?
        end
        unless new_items
          new_items = []
          new_items << Kb8Resource.get_resource_from_data(kb8_data, file, @context)
        end
        new_items.each do | kb8_resource |
          add_resource(kb8_resource)
        end
      end
    end
    debug "NoControllerOk:#{@context.settings.no_controller_ok}"
    unless @resources.has_key?('ReplicationController')
      unless @context.settings.no_controller_ok
        puts "Invalid deployment unit (Missing controller) in dir:#{dir}/*.yaml"
        exit 1
      end
    end
  end

  def add_resource(kb8_resource)
    unless @resources[kb8_resource.kind]
      @resources[kb8_resource.kind] = []
    end
    @resources[kb8_resource.kind] << kb8_resource
  end

  def create_or_update(resource)
    if resource.exist?
      if resource.is_dirty?
        puts "Previously failed resource, deleting #{resource.kinds}/#{resource.name}..."
        resource.delete
        create(resource)
      else
        # Check health and decide if we need to regard the diff...
        unless @no_diff
          if resource.up_to_date?
            if resource_uses_changed_secret?(resource)
              puts "Resource #{resource.kinds}/#{resource.name} uses changed secret, redeploying"
            else
              puts "No Change for #{resource.kinds}/#{resource.name}, Skipping."
              return true
            end
          end
        end
        puts "Updating #{resource.kinds}/#{resource.name}..."
        resource.update
        @changed_resources << resource
        puts '...done.'
      end
    else
      create(resource)
    end
  end

  def create(resource)
    puts "Creating #{resource.kinds}/#{resource.name}..."
    resource.create
    @changed_resources << resource
    puts '...done.'
  end

  def deploy
    if @context.settings.delete_items
      @context.settings.delete_items.each do |resource_name|
        resource = Kb8Resource.create_from_name(resource_name)
        if resource.exist?
          puts "Deleting #{resource.kinds}/#{resource.name}..."
          resource.delete
        end
      end
    end

    # Order resources before deploying them...
    deploy_items = []
    @resources.each do |key, resource_category|
      next if key == 'Pod'
      next if key == 'ReplicationController'
      resource_category.each do |resource|
        deploy_items << resource
      end
    end
    if @resources.has_key?('Pod')
      deploy_items == deploy_items.concat(@resources['Pod'])
    end
    if @resources.has_key?('ReplicationController')
      possible_items = @resources['ReplicationController']
      possible_items.each do | item |
        if item.exist? && item.context.settings.no_automatic_upgrade && (!@context.always_deploy)
          puts "No automatic upgrade specified for #{item.kinds}/#{item.name} skipping..."
        else
          deploy_items << item
        end
      end
    end
    deploy_items.each do | item |
      # test if we have a deployment filter
      deploy = (@only_deploy.nil? || @only_deploy.to_a.include?(item.original_full_name))
      if deploy
        create_or_update(item)
      else
        puts "Skipping resource (-d):#{item.original_full_name}"
      end
    end
  end

  def resource_uses_changed_secret?(resource)
    changed_secrets = []
    @changed_resources.each do |resource|
      if resource.kind == 'Secret'
        changed_secrets << resource.name
      end
    end
    resource.uses_any_secret?(changed_secrets)
  end
end
