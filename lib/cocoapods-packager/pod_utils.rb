module Pod
  class Command
    class Package < Command
      private

      def build_static_sandbox(dynamic)
        static_sandbox_root = if dynamic
                                Pathname.new(config.sandbox_root + '/Static')
                              else
                                Pathname.new(config.sandbox_root)
                              end
        Sandbox.new(static_sandbox_root)
      end

      def install_pod(platform_name, sandbox)
        podfile = podfile_from_spec(
          @path,
          @spec.name,
          platform_name,
          @spec.deployment_target(platform_name),
          @subspecs,
          @spec_sources,
          @local_sources
        )

        static_installer = TalInstaller.new(sandbox, podfile, @auto_fix_conflict)
        static_installer.install!

        unless static_installer.nil?
          static_installer.pods_project.targets.each do |target|
            target.build_configurations.each do |config|
              config.build_settings['CLANG_MODULES_AUTOLINK'] = 'NO'
              config.build_settings['GCC_GENERATE_DEBUGGING_SYMBOLS'] = 'NO'
            end
          end
          static_installer.pods_project.save
        end

        static_installer
      end

      def podfile_from_spec(path, spec_name, platform_name, deployment_target, subspecs, sources, local_sources)
        options = {}
        if path
          if @local
            options[:path] = path
          else
            options[:podspec] = path
          end
        end
        options[:subspecs] = subspecs if subspecs
        generator = self
        spec_file = @spec
        source_dir = @source_dir

        Pod::Podfile.new do
          sources.each { |s| source s }
          platform(platform_name, deployment_target)
          # 此处会自动增加非本地依赖项
          pod(spec_name, options)
          # plugin('cocoapods-packager', {})
          # plugin 查看 cocoapods_plugin.rb 文件内定义

          # 增加本地 local  source
          generator.transitive_local_dependencies(spec_file, local_sources).each do |dependency, podspec_file|
            pod_options = {}
            pod_options[:path] = if podspec_file[0] == '/' # absolute path
                                    Pathname.new(podspec_file)
                                 else
                                    expand_path = File.expand_path(podspec_file,source_dir)
                                    Pathname.new(expand_path)
                                 end
            pod dependency.name, **pod_options
          end

          install!('cocoapods',
                   :integrate_targets => false,
                   :deterministic_uuids => false)

          target('packager') do
            inherit! :complete
          end

          post_install do |installer|
            #设置build setting
            installer.pods_project.targets.each do |target|
              target.build_configurations.each do |config|
                config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
                config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -ObjC'
              end
            end
          end
          
        end
      end

      public
      
      def recursive_subspecs_dependencies(spec)

        dependencies = [@spec, *@spec.recursive_subspecs].flat_map do |all_spec|
          all_spec.dependencies.flat_map do |depency|
            depency if ! "#{depency}".include? "#{spec.name}"
          end
        end.compact.uniq
        # puts dependencies

        # dependencies = spec.dependencies || []
        # spec.recursive_subspecs.each do |subspec|
        #   subspec.dependencies.each do |depency|
        #     if ! "#{depency}".include? "#{spec.name}"
        #       dependencies << depency
        #     end
        #   end
        # end
        dependencies
      end

      def transitive_local_dependencies(spec, paths)
        dependencies = recursive_subspecs_dependencies(spec)
        return_list = []
        dependencies.each do |dependency|
          found_podspec_file = nil
          name = dependency.name.split('/')[0]
          paths.each do |path|
            # 展开目录
            if path[0] != '/'
                path = File.expand_path(path, @source_dir)
            end
            podspec_file = path + '/' + name + '.podspec'
            next unless File.file?(podspec_file)
            found_podspec_file = podspec_file
            break
          end
          next unless found_podspec_file
          return_list << [dependency, found_podspec_file]
          dep_spec = Pod::Specification.from_file(found_podspec_file)
          dep_spec.dependencies.each do |d_dep|
            dependencies << d_dep unless dependencies.include? d_dep
          end
        end
        return_list
      end

      private
      def binary_only?(spec)
        deps = spec.dependencies.map { |dep| spec_with_name(dep.name) }
        [spec, *deps].each do |specification|
          %w(vendored_frameworks vendored_libraries).each do |attrib|
            if !specification.nil? && specification.attributes_hash[attrib]
              return true
            end
          end
        end

        false
      end

      def spec_with_name(name)
        return if name.nil?

        set = Pod::Config.instance.sources_manager.search(Dependency.new(name))
        return nil if set.nil?

        set.specification.root
      end

      def spec_with_path(path)
        return if path.nil?
        path = Pathname.new(path)
        path = Pathname.new(Dir.pwd).join(path) unless path.absolute?
        return unless path.exist?

        @path = path.expand_path

        if @path.directory?
          help! @path + ': is a directory.'
          return
        end

        unless ['.podspec', '.json'].include? @path.extname
          help! @path + ': is not a podspec.'
          return
        end

        Specification.from_file(@path)
      end

      #----------------------
      # Dynamic Project Setup
      #----------------------

      def build_dynamic_sandbox(_static_sandbox, _static_installer)
        dynamic_sandbox_root = Pathname.new(config.sandbox_root + '/Dynamic')
        dynamic_sandbox = Sandbox.new(dynamic_sandbox_root)

        dynamic_sandbox
      end

      # @param [Pod::Sandbox] dynamic_sandbox
      #
      # @param [Pod::Sandbox] static_sandbox
      #
      # @param [Pod::Installer] static_installer
      #
      # @param [Pod::Platform] platform
      #
      def install_dynamic_pod(dynamic_sandbox, static_sandbox, static_installer, platform)
        # 1 Create a dynamic target for only the spec pod.
        dynamic_target = build_dynamic_target(dynamic_sandbox, static_installer, platform)

        # 2. Build a new xcodeproj in the dynamic_sandbox with only the spec pod as a target.
        project = prepare_pods_project(dynamic_sandbox, dynamic_target.name, static_installer)

        # 3. Copy the source directory for the dynamic framework from the static sandbox.
        copy_dynamic_target(static_sandbox, dynamic_target, dynamic_sandbox)

        # 4. Create the file references.
        install_file_references(dynamic_sandbox, [dynamic_target], project)

        # 5. Install the target.
        install_library(dynamic_sandbox, dynamic_target, project)

        # 6. Write the actual .xcodeproj to the dynamic sandbox.
        write_pod_project(project, dynamic_sandbox)
      end

      # @param [Pod::Installer] static_installer
      #
      # @return [Pod::PodTarget]
      #
      def build_dynamic_target(dynamic_sandbox, static_installer, platform)
        spec_targets = static_installer.pod_targets.select do |target|
          target.name == @spec.name
        end
        static_target = spec_targets[0]

        file_accessors = create_file_accessors(static_target, dynamic_sandbox)

        archs = []
        dynamic_target = Pod::PodTarget.new(dynamic_sandbox, true, static_target.user_build_configurations, archs, platform, static_target.specs, static_target.target_definitions, file_accessors)
        dynamic_target
      end

      # @param [Pod::Sandbox] dynamic_sandbox
      #
      # @param [String] spec_name
      #
      # @param [Pod::Installer] installer
      #
      def prepare_pods_project(dynamic_sandbox, spec_name, installer)
        # Create a new pods project
        pods_project = Pod::Project.new(dynamic_sandbox.project_path)

        # Update build configurations
        installer.analysis_result.all_user_build_configurations.each do |name, type|
          pods_project.add_build_configuration(name, type)
        end

        # Add the pod group for only the dynamic framework
        local = dynamic_sandbox.local?(spec_name)
        path = dynamic_sandbox.pod_dir(spec_name)
        was_absolute = dynamic_sandbox.local_path_was_absolute?(spec_name)
        pods_project.add_pod_group(spec_name, path, local, was_absolute)
        pods_project
      end

      def copy_dynamic_target(static_sandbox, _dynamic_target, dynamic_sandbox)
        command = "cp -a #{static_sandbox.root}/#{@spec.name} #{dynamic_sandbox.root}"
        `#{command}`
      end

      def create_file_accessors(target, dynamic_sandbox)
        pod_root = dynamic_sandbox.pod_dir(target.root_spec.name)

        path_list = Sandbox::PathList.new(pod_root)
        target.specs.map do |spec|
          Sandbox::FileAccessor.new(path_list, spec.consumer(target.platform))
        end
      end

      def install_file_references(dynamic_sandbox, pod_targets, pods_project)
        installer = Pod::Installer::Xcode::PodsProjectGenerator::FileReferencesInstaller.new(dynamic_sandbox, pod_targets, pods_project)
        installer.install!
      end

      def install_library(dynamic_sandbox, dynamic_target, project)
        return if dynamic_target.target_definitions.flat_map(&:dependencies).empty?
        target_installer = Pod::Installer::Xcode::PodsProjectGenerator::PodTargetInstaller.new(dynamic_sandbox, project, dynamic_target)
        result = target_installer.install!
        native_target = result.native_target

        # Installs System Frameworks
        if dynamic_target.should_build?
          dynamic_target.file_accessors.each do |file_accessor|
            file_accessor.spec_consumer.frameworks.each do |framework|
              native_target.add_system_framework(framework)
            end
            file_accessor.spec_consumer.libraries.each do |library|
              native_target.add_system_library(library)
            end
          end
        end
      end

      def write_pod_project(dynamic_project, dynamic_sandbox)
        UI.message "- Writing Xcode project file to #{UI.path dynamic_sandbox.project_path}" do
          dynamic_project.pods.remove_from_project if dynamic_project.pods.empty?
          dynamic_project.development_pods.remove_from_project if dynamic_project.development_pods.empty?
          dynamic_project.sort(:groups_position => :below)
          dynamic_project.recreate_user_schemes(false)

          # Edit search paths so that we can find our dependency headers
          dynamic_project.targets.first.build_configuration_list.build_configurations.each do |config|
            config.build_settings['HEADER_SEARCH_PATHS'] = "$(inherited) #{Dir.pwd}/Pods/Static/Headers/**"
            config.build_settings['USER_HEADER_SEARCH_PATHS'] = "$(inherited) #{Dir.pwd}/Pods/Static/Headers/**"
            config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -ObjC'
          end
          dynamic_project.save
        end
      end
    end
  end
end
