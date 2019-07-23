module Pod
  class Installer
    class Xcode
      class TalTargetValidator < TargetValidator
        
        def initialize(aggregate_targets, pod_targets, auto_fix_conflict = true)
          @aggregate_targets = aggregate_targets
          @pod_targets = pod_targets
          @auto_fix_conflict = auto_fix_conflict
        end

        def verify_no_duplicate_framework_and_library_names
            aggregate_targets.each do |aggregate_target|
              aggregate_target.user_build_configurations.keys.each do |config|
                pod_targets = aggregate_target.pod_targets_for_build_configuration(config)
                file_accessors = pod_targets.flat_map(&:file_accessors)
  
                frameworks = file_accessors.flat_map(&:vendored_frameworks).uniq.map(&:basename)
                frameworks += pod_targets.select { |pt| pt.should_build? && pt.requires_frameworks? }.map(&:product_module_name).uniq
                verify_no_duplicate_names(frameworks, aggregate_target, 'frameworks', file_accessors)
  
                libraries = file_accessors.flat_map(&:vendored_libraries).uniq.map(&:basename)
                libraries += pod_targets.select { |pt| pt.should_build? && !pt.requires_frameworks? }.map(&:product_name)
                verify_no_duplicate_names(libraries, aggregate_target, 'libraries', file_accessors)
              end
            end
        end

        def verify_no_duplicate_names(names, aggregate_target, type, file_accessors)
          duplicates = names.map { |n| n.to_s.downcase }.group_by { |f| f }.select { |_, v| v.size > 1 }.keys

          if !duplicates.empty? && @auto_fix_conflict
            # 移除冲突文件
            duplicate_files = Array.new
            duplicates.each do |d|
              tmp_duplicate = file_accessors.flat_map(&:vendored_libraries).uniq.find_all { |p|
                d == p.basename.to_s && File.exist?(p)
              }.sort || []
              duplicate_files << tmp_duplicate
            end

            duplicate_files.each do |dfs|
              if dfs.count > 1
                dfs.pop
                dfs.each do |file|
                  puts "remove confliting file #{file}"
                  FileUtils.rm(file) if File.exist?(file)
                end
              end
            end
          end

          if duplicates.empty? && !@auto_fix_conflict
            raise Informative, "The '#{aggregate_target.label}' target has " \
              "#{type} with conflicting names: #{duplicates.to_sentence}."
          end
        end
      end
    end
  end
end