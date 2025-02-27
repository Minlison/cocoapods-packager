module Pod
  class SpecBuilder
    def initialize(spec, source, embedded, dynamic, force_load = false)
      @spec = spec
      #https://git.100tal.com/peiyou_xueersiapp_xesappmoduleiosframework/CloudLearning_English.git
      git_source_name = spec.name.gsub("_HD","")
      @source = source.nil? ? "{ :git => \"https://git.100tal.com/peiyou_xueersiapp_xesappmoduleiosframework/#{git_source_name}.git\", :tag => s.version.to_s }" : source
      @embedded = embedded
      @dynamic = dynamic
      @force_load = force_load
    end

    def framework_path
      if @embedded
        'embedded' + '/' + @spec.name + '.framework'
      else
        @spec.name + '.framework'
      end
    end

    def spec_platform(platform)
      fwk_base = platform.name.to_s + '/' + framework_path
      if @dynamic
      spec = <<RB
  s.#{platform.name}.deployment_target    = '#{platform.deployment_target}'
RB
      else
      spec = <<RB
  s.#{platform.name}.deployment_target    = '#{platform.deployment_target}'
  s.#{platform.name}.source_files   = '#{fwk_base}/Versions/A/Headers/**/*.h'
  s.#{platform.name}.public_header_files   = '#{fwk_base}/Versions/A/Headers/**/*.h'
RB
      end

      # resources
      spec_resources = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_resources = consumer.resources || []
        tmp_resources
      end.compact.uniq

      if spec_resources.count > 0
        spec += "  s.#{platform.name}.resources = '#{fwk_base}/Versions/A/Resources/*.*'\n"
      end
      

       # vendored_frameworks 
      vendored_frameworks = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_vendored_frameworks = consumer.vendored_frameworks || []
        tmp_vendored_frameworks
      end.compact.uniq.flat_map do |framework|
        "ios/#{File.basename(framework)}"
      end
      vendored_frameworks << fwk_base

      spec +=  "  s.#{platform.name}.vendored_frameworks   = #{vendored_frameworks} \n"

      # vendored_libraries 
      vendored_libraries = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_vendored_libraries = consumer.vendored_libraries || []
        tmp_vendored_libraries
      end.compact.uniq
      spec +=  "  s.#{platform.name}.vendored_libraries   = #{vendored_libraries}" if vendored_libraries.count > 0

      # frameworks 
      frameworks = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_frameworks = consumer.frameworks || []
        tmp_frameworks
      end.compact.uniq
      spec += "  s.#{platform.name}.frameworks   = #{frameworks} \n" if frameworks.count > 0

      libraries = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_libraries = consumer.libraries || []
        tmp_libraries
      end.compact.uniq
      spec += "  s.#{platform.name}.libraries   = #{libraries} \n" if libraries.count > 0

      weak_frameworks = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        tmp_libraries = consumer.weak_frameworks || []
        tmp_libraries
      end.compact.uniq
      spec += "  s.#{platform.name}.weak_frameworks   = #{weak_frameworks} \n" if weak_frameworks.count > 0

      [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        spec.all_dependencies(platform)
      end.compact.uniq.each do |d|
        if d.requirement == Pod::Requirement.default
          spec += "  s.dependency '#{d.name}'\n" unless d.root_name == @spec.name
        else
          spec += "  s.dependency '#{d.name}', '#{d.requirement.to_s}'\n" unless d.root_name == @spec.name
        end
      end

      platform_framework_path = platform.name.to_s
      if @embedded
        platform_framework_path += '/embedded'
      end

      if @force_load
  # xcconfig
  xcconfig = <<RB
  path = File.dirname(Pathname.new(__FILE__)).to_s
  relative_path = path
  config = Pod::Config.instance
  if path.include?(config.home_dir.to_s)
    relative_path = "${PODS_ROOT}/#{@spec.name}" 
  end
  s.xcconfig  =  {
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'OTHER_LDFLAGS' => ["$(inherited)","-force_load","\#{relative_path}/#{fwk_base}/#{@spec.name}","'-L \#{relative_path}/#{fwk_base}'"],
    'FRAMEWORK_SEARCH_PATHS' => ["$(inherited)","\#{relative_path}/#{platform_framework_path}"],
    'HEADER_SEARCH_PATHS' => ["$(inherited)","\#{relative_path}/#{fwk_base}/Versions/A/Headers/**"]
  }
RB
      else
  # xcconfig
  xcconfig = <<RB
  path = File.dirname(Pathname.new(__FILE__)).to_s
  relative_path = path
  config = Pod::Config.instance
  if path.include?(config.home_dir.to_s)
    relative_path = "${PODS_ROOT}/#{@spec.name}" 
  end
  s.xcconfig  =  {
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'FRAMEWORK_SEARCH_PATHS' => ["$(inherited)","\#{relative_path}/#{platform_framework_path}"],
    'HEADER_SEARCH_PATHS' => ["$(inherited)","\#{relative_path}/#{fwk_base}/Versions/A/Headers/**"]
  }
RB
      end
      

      spec += xcconfig

      spec
    end

    def spec_metadata
      spec = spec_header
      spec
    end

    def spec_close
      "end\n"
    end

    private

    def spec_header
      spec = "Pod::Spec.new do |s|\n"
        attribute_list = %w(name version summary license authors homepage description social_media_url
        docset_url documentation_url screenshots requires_arc
        deployment_target xcconfig)
      
      attribute_list.each do |attribute|
        value = @spec.attributes_hash[attribute]
        next if value.nil?
        value = value.dump if value.class == String
        spec += "  s.#{attribute} = #{value}\n"
      end
      spec += "  s.source = #{@source}\n"

      spec
    end
  end
end
