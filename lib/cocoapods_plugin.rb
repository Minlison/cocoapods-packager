require 'pod/command/package'
require 'cocoapods-packager/user_interface/build_failed_report'
require 'cocoapods-packager/builder'
require 'cocoapods-packager/framework'
require 'cocoapods-packager/mangle'
require 'cocoapods-packager/pod_utils'
require 'cocoapods-packager/spec_builder'
require 'cocoapods-packager/symbols'

# module CocoapodsPackager
#     Pod::HooksManager.register('cocoapods-packager', :pre_install) do |context|
#         # do some thing
#     end
# end