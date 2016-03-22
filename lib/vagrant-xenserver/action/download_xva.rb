require "log4r"
require "xmlrpc/client"
require "vagrant-xenserver/util/uploader"
require "rexml/document"

module VagrantPlugins
  module XenServer
    module Action
      class DownloadXVA
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::download_xva")
        end
        
        def call(env)
          xva_url = env[:machine].provider_config.xva_url

          box_name = env[:machine].box.name.to_s
          box_version = env[:machine].box.version.to_s

          @logger.info("xva_url="+xva_url.to_s)
          # Check whether we've already downloaded a VM from this URL
          # When we do, we set an other_config key 'xva_url', so we
          # can just scan through the VMs looking for it.
          templates = env[:xc].VM.get_all_records_where("field \"is_a_template\"=\"true\"")
          template = templates.detect { |vm,vmr|
            vmr["other_config"]["box_name"] == box_name &&
              vmr["other_config"]["box_version"] == box_version
          }

          @logger.info("template="+template.to_s)

          if template.nil? && (not xva_url.nil?)
            # No template, let's download it.
            pool=env[:xc].pool.get_all
            default_sr=env[:xc].pool.get_default_SR(pool[0])
              
            task = env[:xc].Async.VM.import(xva_url, default_sr, false, false)

            begin
              sleep(2.0)
              task_status = env[:xc].task.get_status(task)
            end while task_status == "pending"
            
            @logger.info("task_status="+task_status)

            if task_status != "success"
              raise Errors::APIError
            end

            task_result = env[:xc].task.get_result(task)

            doc = REXML::Document.new(task_result)

            @logger.debug("task_result=\"#{task_result}\"")
            template_ref = doc.elements['value/array/data/value'].text

            # Make sure it's really a template, and add the xva_url to other_config:
            env[:xc].VM.set_is_a_template(template_ref,true)
            env[:xc].VM.add_to_other_config(template_ref,"xva_url",xva_url)
            env[:xc].VM.add_to_other_config(template_ref,"box_name",box_name)
            env[:xc].VM.add_to_other_config(template_ref,"box_version",box_version)   

            # Hackity hack: HVM booting guests don't need to set the bootable flag
            # on their VBDs, but PV do. Let's set bootable=true on VBD device=0
            # just in case.

            vbds = env[:xc].VM.get_VBDs(template_ref)
            vbds.each { |vbd|
              if env[:xc].VBD.get_userdevice(vbd) == "0"
                env[:xc].VBD.set_bootable(vbd, true)
              end
            }
            env[:template] = template_ref
          else
            (template_ref, template_rec) = template
            env[:template] = template_ref
          end
          
          @app.call(env)
        end
      end
    end
  end
end
