require 'log4r'

module VagrantPlugins
  module XenServer
    module Action
      class IsSuspended
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_xenserver::action::is_suspended')
        end

        def call(env)
          @logger.info("env[:machine].state.id="+env[:machine].state.id.to_s)
          env[:result] = env[:machine].state.id == 'Suspended'
          @app.call(env)
        end
      end
    end
  end
end
