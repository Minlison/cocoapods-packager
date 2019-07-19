module Pod
  class SpecBuilder
    def initialize(spec, source, embedded, dynamic)
      @spec = spec
      @source = source.nil? ? '{ :path => \'.\' }' : source
      @embedded = embedded
      @dynamic = dynamic
    end

    def framework_path
      if @embedded
        @spec.name + '.embeddedframework' + '/' + @spec.name + '.framework'
      else
        @spec.name + '.framework'
      end
    end

    def spec_platform(platform)
      fwk_base = platform.name.to_s + '/' + framework_path
      if @dynamic
      spec = <<RB
  s.#{platform.name}.deployment_target    = '#{platform.deployment_target}'
  s.#{platform.name}.vendored_frameworks   = '#{platform.name.to_s}/*.framework'
RB
      else
      spec = <<RB
  s.#{platform.name}.deployment_target    = '#{platform.deployment_target}'
  s.#{platform.name}.vendored_frameworks   = '#{platform.name.to_s}/*.framework'
  s.#{platform.name}.vendored_libraries   = '#{platform.name.to_s}/*.a'
  s.#{platform.name}.source_files   = '#{fwk_base}/Versions/A/Headers/**/*.h'
  s.#{platform.name}.public_header_files   = '#{fwk_base}/Versions/A/Headers/**/*.h'
  s.#{platform.name}.resources   = '#{fwk_base}/Versions/A/Resources/**/*.*'
  s.xcconfig  =  {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/#{@spec.name}/#{platform.name.to_s}"',
    'HEADER_SEARCH_PATHS' => '"${PODS_ROOT}/#{@spec.name}/**/*"',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
RB
      end

      [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        spec.all_dependencies(platform)
      end.compact.uniq.each do |d|
        if d.requirement == Pod::Requirement.default
          spec += "  s.dependency '#{d.name}'\n" unless d.root_name == @spec.name
        else
          spec += "  s.dependency '#{d.name}', '#{d.requirement.to_s}'\n" unless d.root_name == @spec.name
        end
      end
      
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
        docset_url documentation_url screenshots frameworks weak_frameworks libraries requires_arc
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
