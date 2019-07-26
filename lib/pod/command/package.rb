require 'tmpdir'
require 'fileutils'
module Pod
  class Command
    class Package < Command
      self.summary = 'Package a podspec into a static library.'
      self.arguments = [
        CLAide::Argument.new('NAME', true),
        CLAide::Argument.new('SOURCE', false)
      ]

      def self.options
        [
          ['--force',     'Overwrite existing files.'],
          ['--no-mangle', 'Do not mangle symbols of depedendant Pods.'],
          ['--embedded',  'Generate embedded frameworks.'],
          ['--library',   'Generate static libraries.'],
          ['--dynamic',   'Generate dynamic framework.'],
          ['--local',     'Use local state rather than published versions.'],
          ['--bundle-identifier', 'Bundle identifier for dynamic framework'],
          ['--exclude-deps', 'Exclude symbols from dependencies. default true'],
          ['--include-deps', 'Include symbols from dependencies. default false'],
          ['--configuration', 'Build the specified configuration (e.g. Debug). Defaults to Release'],
          ['--subspecs', 'Only include the given subspecs'],
          ['--spec-sources=private,https://github.com/CocoaPods/Specs.git', 'The sources to pull dependent ' \
            'pods from (defaults to https://github.com/CocoaPods/Specs.git)'],
          ['--auto-fix-conflict',   'fix cocoapods conflict .a or .framework , default is true'],
          ['--local-sources=./', '相对 podspec 路径，Paths from which to find local podspecs for transitive dependencies. Multiple local-sources must be comma-delimited.' \
            'pods from local'],
          ['--no-repos', '不自动添加 pod repo list 显示出的 source'],
          ['--repo-update', 'update repo'],
          ['--work-dir', 'the dir when build '],
          ['--git-source', 'framework podspec s.source= '],
          ['--output-dsym', 'generate dSYM file'],
          ['--xcconfig-path', 'xcode build xcconfig path'],
        ]
      end

      def initialize(argv)
        @embedded = argv.flag?('embedded')
        @library = argv.flag?('library')
        @dynamic = argv.flag?('dynamic')
        @local = argv.flag?('local', false)
        @output_dsym = argv.flag?('output-dsym', true)
        @package_type = if @embedded
                          :static_framework
                        elsif @dynamic
                          :dynamic_framework
                        elsif @library
                          :static_library
                        else
                          :static_framework
                        end
        @force = argv.flag?('force')
        @mangle = argv.flag?('mangle', true)
        @bundle_identifier = argv.option('bundle-identifier', nil)
        @include_deps = argv.flag?('include-deps', false)
        @exclude_deps = argv.flag?('exclude-deps', !@include_deps)
        @name = argv.shift_argument
        @source = argv.shift_argument
        @spec_sources = argv.option('spec-sources', 'https://github.com/CocoaPods/Specs.git').split(',')
        @local_sources = argv.option('local-sources', '').split(',')
        @no_repos = argv.flag?('no-repos', false)
        @repo_update = argv.flag?('repo-update', false)
        @work_dir = argv.option('work-dir', Dir.tmpdir)
        @git_source = argv.option('git-source', nil)
        @xcconfig_path = argv.option('xcconfig-path', nil)
        subspecs = argv.option('subspecs')
        @subspecs = subspecs.split(',') unless subspecs.nil?

        @config = argv.option('configuration', 'Release')
        @auto_fix_conflict = argv.flag?('auto-fix-conflict', true)

        @source_dir = Dir.pwd
        @is_spec_from_path = false
        @spec = spec_with_path(@name)
        @is_spec_from_path = true if @spec
        @spec ||= spec_with_name(@name)
        
        @source = "{ :git => \"#{@git_source}\", :tag => s.version.to_s }" unless @git_source.nil?

        super
      end

      def validate!
        super
        help! 'A podspec name or path is required.' unless @spec
        help! 'podspec has binary-only depedencies, mangling not possible.' if @mangle && binary_only?(@spec)
        help! '--bundle-identifier option can only be used for dynamic frameworks' if @bundle_identifier && !@dynamic
        help! '--exclude-deps option can only be used for static libraries' if @exclude_deps && @dynamic
        help! '--local option can only be used when a local `.podspec` path is given.' if @local && !@is_spec_from_path
      end

      def run
        if @spec.nil?
          help! "Unable to find a podspec with path or name `#{@name}`."
          return
        end

        if !@no_repos
          if @spec_sources.nil?
            @spec_sources = []
          end
          config.sources_manager.all.each do |s|
            @spec_sources << s.url
          end
        end
        
        if @repo_update
          update_sources
        end

        target_dir, work_dir = create_working_directory
        return if target_dir.nil?
        build_package

        `mv "#{work_dir}" "#{target_dir}"`
        Dir.chdir(@source_dir)
      end

      def update_sources
        UI.title 'Updating specs repos' do
          @spec_sources.each do |source|
            source = config.sources_manager.source_with_name_or_url(source)
            UI.titled_section "Updating spec repo `#{source.name}`" do
              source.update(config.verbose?)
              source.verify_compatibility!
            end
          end
        end
      end

      private

      def build_in_sandbox(platform)
        config.installation_root  = Pathname.new(Dir.pwd)
        config.sandbox_root       = 'Pods'

        static_sandbox = build_static_sandbox(@dynamic)
        static_installer = install_pod(platform.name, static_sandbox)

        if @dynamic
          dynamic_sandbox = build_dynamic_sandbox(static_sandbox, static_installer)
          install_dynamic_pod(dynamic_sandbox, static_sandbox, static_installer, platform)
        end

        begin
          perform_build(platform, static_sandbox, dynamic_sandbox, static_installer)
        ensure # in case the build fails; see Builder#xcodebuild.
          Pathname.new(config.sandbox_root).rmtree
          FileUtils.rm_f('Podfile.lock')
        end
      end

      def build_package
        builder = SpecBuilder.new(@spec, @source, @embedded, @dynamic, config.cache_root)
        newspec = builder.spec_metadata

        @spec.available_platforms.each do |platform|
          build_in_sandbox(platform)

          newspec += builder.spec_platform(platform)
        end

        newspec += builder.spec_close
        File.open(@spec.name + '.podspec', 'w') { |file| file.write(newspec) }
      end

      def create_target_directory
        target_dir = "#{@source_dir}/#{@spec.name}-#{@spec.version}"
        if File.exist? target_dir
          if @force
            Pathname.new(target_dir).rmtree
          else
            UI.puts "Target directory '#{target_dir}' already exists."
            return nil
          end
        end
        target_dir
      end

      def create_working_directory
        target_dir = create_target_directory
        return if target_dir.nil?
        rootDir = @work_dir
        if rootDir[0] != '/'
          rootDir = File.expand_path(rootDir,@source_dir)
        end
        if rootDir.nil?
          rootDir = Dir.tmpdir
        end
        
        # work_dir = rootDir + '/cocoapods-' + Array.new(8) { rand(36).to_s(36) }.join
        work_dir = rootDir + '/cocoapods-packager-build'
        if File.exist?(work_dir)
          FileUtils.rm_rf(work_dir)
        end
        # Pathname.new(work_dir).mkdir
        FileUtils.mkdir_p(work_dir)
        Dir.chdir(work_dir)

        [target_dir, work_dir]
      end

      def perform_build(platform, static_sandbox, dynamic_sandbox, static_installer)
        static_sandbox_root = config.sandbox_root.to_s

        if @dynamic
          static_sandbox_root = "#{static_sandbox_root}/#{static_sandbox.root.to_s.split('/').last}"
          dynamic_sandbox_root = "#{config.sandbox_root}/#{dynamic_sandbox.root.to_s.split('/').last}"
        end

        builder = Pod::Builder.new(
          platform,
          static_installer,
          @source_dir,
          static_sandbox_root,
          dynamic_sandbox_root,
          static_sandbox.public_headers.root,
          @spec,
          @embedded,
          @mangle,
          @dynamic,
          @config,
          @bundle_identifier,
          @exclude_deps,
          @xcconfig_path
        )

        builder.build(@package_type)

        return unless @embedded
        builder.link_embedded_resources
      end
    end
  end
end
