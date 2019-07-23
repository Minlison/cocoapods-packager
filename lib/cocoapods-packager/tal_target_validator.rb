module Pod
    class Installer
      class Xcode
        class TalTargetValidator < TargetValidator
            def verify_no_duplicate_framework_and_library_names
                aggregate_targets.each do |aggregate_target|
                  aggregate_target.user_build_configurations.keys.each do |config|
                    pod_targets = aggregate_target.pod_targets_for_build_configuration(config)
                    file_accessors = pod_targets.flat_map(&:file_accessors)
      
                    frameworks = file_accessors.flat_map(&:vendored_frameworks).uniq.map(&:basename)
                    frameworks += pod_targets.select { |pt| pt.should_build? && pt.requires_frameworks? }.map(&:product_module_name).uniq
                    verify_no_duplicate_names(frameworks, aggregate_target, 'frameworks')
      
                    libraries = file_accessors.flat_map(&:vendored_libraries).uniq.map(&:basename)
                    libraries += pod_targets.select { |pt| pt.should_build? && !pt.requires_frameworks? }.map(&:product_name)
                    verify_no_duplicate_names(libraries, aggregate_target, 'libraries')
                  end
                end
            end

            def verify_no_duplicate_names(names, aggregate_target, type)
                duplicates = names.map { |n| n.to_s.downcase }.group_by { |f| f }.select { |_, v| v.size > 1 }.keys
      
                unless duplicates.empty?
                    puts aggregate_target.client_root
                #   raise Informative, "The '#{aggregate_target.label}' target has " \
                #     "#{type} with conflicting names: #{duplicates.to_sentence}."
                end
            end
        end
    end
end