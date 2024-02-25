require 'ceedling/constants'

class ConfiguratorPlugins

  constructor :file_wrapper, :system_wrapper

  attr_reader :rake_plugins, :programmatic_plugins

  def setup
    @rake_plugins   = []
    @programmatic_plugins = []
  end


  # Override to prevent exception handling from walking & stringifying the object variables.
  # Object variables are gigantic and produce a flood of output.
  def inspect
    # TODO: When identifying information is added to constructor, insert it into `inspect()` string
    return this.class.name
  end


  def process_aux_load_paths(config)
    plugin_paths = {}

    # Add any base load path to Ruby's load path collection
    config[:plugins][:load_paths].each do |path|
      @system_wrapper.add_load_path( path )
    end

    # If a load path contains an actual Ceedling plugin, load its subdirectories by convention
    config[:plugins][:enabled].each do |plugin|
      config[:plugins][:load_paths].each do |root|
        path = File.join(root, plugin)

        # Ceedling Ruby-based hash defaults plugin (or config for Ceedling programmatic plugin)
        is_config_plugin       = ( not @file_wrapper.directory_listing( File.join( path, 'config', '*.rb' ) ).empty? )

        # Ceedling programmatic plugin
        is_programmatic_plugin = ( not @file_wrapper.directory_listing( File.join( path, 'lib', '*.rb' ) ).empty? )

        # Ceedling Rake plugin
        is_rake_plugin         = ( not @file_wrapper.directory_listing( File.join( path, '*.rake' ) ).empty? )

        if (is_config_plugin or is_programmatic_plugin or is_rake_plugin)
          plugin_paths[(plugin + '_path').to_sym] = path

          # Add paths to Ruby load paths that contain *.rb files
          @system_wrapper.add_load_path( File.join( path, 'config') ) if is_config_plugin   
          @system_wrapper.add_load_path( File.join( path, 'lib') )    if is_programmatic_plugin

          # We found load_path/ + <plugin>/ path that exists, skip ahead
          break
        end
      end
    end

    return plugin_paths
  end


  # Gather up and return .rake filepaths that exist in plugin paths
  def find_rake_plugins(config, plugin_paths)
    @rake_plugins = []
    plugins_with_path = []

    config[:plugins][:enabled].each do |plugin|
      if path = plugin_paths[(plugin + '_path').to_sym]
        rake_plugin_path = File.join(path, "#{plugin}.rake")
        if (@file_wrapper.exist?(rake_plugin_path))
          plugins_with_path << rake_plugin_path
          @rake_plugins << plugin
        end
      end
    end

    return plugins_with_path
  end


  # Gather up just names of .rb `Plugin` subclasses that exist in plugin paths + lib/
  def find_programmatic_plugins(config, plugin_paths)
    @programmatic_plugins = []

    config[:plugins][:enabled].each do |plugin|
      if path = plugin_paths[(plugin + '_path').to_sym]
        script_plugin_path = File.join(path, "lib", "#{plugin}.rb")

        if @file_wrapper.exist?(script_plugin_path)
          @programmatic_plugins << plugin
        end
      end
    end

    return @programmatic_plugins
  end


  # Gather up and return config .yml filepaths that exist in plugin paths + config/
  def find_config_plugins(config, plugin_paths)
    plugins_with_path = []

    config[:plugins][:enabled].each do |plugin|
      if path = plugin_paths[(plugin + '_path').to_sym]
        config_plugin_path = File.join(path, "config", "#{plugin}.yml")

        if @file_wrapper.exist?(config_plugin_path)
          plugins_with_path << config_plugin_path
        end
      end
    end

    return plugins_with_path
  end


  # Gather up and return default .yml filepaths that exist on-disk
  def find_plugin_yml_defaults(config, plugin_paths)
    defaults_with_path = []

    config[:plugins][:enabled].each do |plugin|
      if path = plugin_paths[(plugin + '_path').to_sym]
        default_path = File.join(path, 'config', 'defaults.yml')

        if @file_wrapper.exist?(default_path)
          defaults_with_path << default_path
        end
      end
    end

    return defaults_with_path
  end

  # Gather up and return defaults generated by Ruby code in plugin paths + config/
  def find_plugin_hash_defaults(config, plugin_paths)
    defaults_hash= []

    config[:plugins][:enabled].each do |plugin|
      if path = plugin_paths[(plugin + '_path').to_sym]
        default_path = File.join(path, "config", "defaults_#{plugin}.rb")
        if @file_wrapper.exist?(default_path)
          @system_wrapper.require_file( "defaults_#{plugin}.rb" )

          object = eval("get_default_config()")
          defaults_hash << object
        end
      end
    end

    return defaults_hash
  end

end
