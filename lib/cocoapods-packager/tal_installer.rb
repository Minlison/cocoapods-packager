module Pod
  class TalInstaller < Installer
    def initialize(sandbox, podfile, auto_fix_conflict = true, lockfile = nil)
      @sandbox  = sandbox
      @podfile  = podfile
      @lockfile = lockfile
      @auto_fix_conflict = auto_fix_conflict

      @use_default_plugins = true
      @has_dependencies = true
      super(sandbox, podfile, lockfile)
    end

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
        validator = Xcode::TalTargetValidator.new(aggregate_targets, pod_targets, @auto_fix_conflict)
        validator.validate!
    end
end
end