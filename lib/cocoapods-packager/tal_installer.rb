module Pod
    class TalInstaller < Installer
        def install!
            prepare
            resolve_dependencies
            download_dependencies
            validate_targets_remove_confilict
            generate_pods_project
            if installation_options.integrate_targets?
              integrate_user_project
            else
              UI.section 'Skipping User Project Integration'
            end
            perform_post_install_actions
        end
        def validate_targets_remove_confilict
            validator = Xcode::TalTargetValidator.new(aggregate_targets, pod_targets)
            validator.validate!
        end
    end
end