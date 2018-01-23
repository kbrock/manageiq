require 'sys/proctable'
require 'manageiq'
require 'util/vmdb-logger'

class MemoryLogger
  PSS    = true
  OSPACE = false
  NICK   = false
  def self.log(message)
    if true
      gc_stat    = GC.stat
      heap_alloc = gc_stat[:heap_available_slots] # slot version of :heap_allocated_pages
      heap_live  = gc_stat[:heap_live_slots]      # slots
      heap_free  = gc_stat[:heap_free_slots]      # slots
      live       = gc_stat[:total_allocated_objects] - gc_stat[:total_freed_objects] # objects
      old        = gc_stat[:old_objects]          # objects
      gc         = gc_stat[:major_gc_count]
      if NICK
        gc_str   = "GCstat: [#{gc_stat.inspect}]"
      else
        gc_str   = "All Heap Slots: [#{heap_alloc}], Live Heap Slots: [#{heap_live}], " \
                   "GC: [#{gc}], Live Objects: [#{live}], Old Objects: [#{old}]"
      end
    end
    if PSS
      if defined?(Sys::ProcTable::Smaps)
        mem_info = Sys::ProcTable::Smaps.new(Process.pid, MiqSystem.readfile_async("/proc/#{Process.pid}/smaps"))
        mem_str      = "PSS: [#{mem_info.pss}], RSS: [#{mem_info.rss}], "
      else
        process_info = MiqProcess.processInfo
        mem_str      = "PSS: [#{process_info[:proportional_set_size]}], RSS: [#{process_info[:memory_usage]}], "
      end
    end
    if OSPACE
      # types = Hash.new { |h, k| h[k] = 0 }
      # ObjectSpace.each_object do |obj|
      #   types[obj.class.name] += 1
      # end.sort_by { |_k, v| -v }.take(50)
      #
      ospace_str = "ObjectSpace: [#{ObjectSpace.count_objects.inspect}], "
    end
    # _log.info "{log_prefix} #{msg}, ...""
    "#{message}, #{mem_str}#{ospace_str}#{gc_str}"
  end
end

# require 'miq_worker/runner'
# require 'miq_queue_worker_base/runner.rb'
# MiqWorker::Runner.prepend Module.new {
#   def process_message(message, *args)
#     super
#   ensure
#     meth = "message_#{message}"
#     _log.info MemoryLogger.log("#{log_prefix} LOG MEMORY process_message #{meth}") if self.respond_to?(meth)
#     # ActiveSupport::Notifications.instrument("worker.process_message", message: "message_#{message}") do
#     #   super
#     # end
#   end
#   def do_gc
#     # returning true is not part of do_gc interface. a happy coincidence
#     super.tap do |x|
#       if x
#         _log.info MemoryLogger.log("#{log_prefix} LOG MEMORY do_gc")
#         # ActiveSupport::Notifications.instrument("worker.do_gc") do #? only send if doing actual gc
#       end
#     end
#   end
# }
# MiqQueueWorkerBase::Runner.prepend Module.new {
#   def deliver_queue_message(msg)
#     super
#   ensure
#     _log.info MemoryLogger.log "#{log_prefix} LOG MEMORY deliver_queue_message" \
#                ", Command: [#{msg.class_name}.#{msg.method_name}], Instance id: [#{msg.instance_id}]"
#     # ActiveSupport::Notifications.instrument("worker.deliver_queue_message", message: msg, class_name: self.class.name) do
#     #   super
#     # end
#   end
# }

$perf_log = Vmdb::Loggers::MulticastLogger.new(VMDBLogger.new(ManageIQ.root.join("log").join("performance")))

ActiveSupport::Notifications.subscribe(/\.process_message$/) do |name, start, finish, id, payload|
  $perf_log.info MemoryLogger.log("MIQ(#{name}) LOG MEMORY process_message #{payload[:method]}")
end

ActiveSupport::Notifications.subscribe(/\.do_gc$/) do |name, start, finish, id, payload|
  # gc_time = finish - start
  # gc_meth = gc_time >= 5 ? :warn : :debug
  # $perf_log.send(gc_meth, "MIQ(#{name}) Garbage collection took #{gc_time} seconds")
  $perf_log.info MemoryLogger.log("MIQ(#{name}) LOG MEMORY do_gc")
end

ActiveSupport::Notifications.subscribe(/\.deliver_queue_message$/) do |name, start, finish, id, payload|
  msg = payload[:message]
  $perf_log.info MemoryLogger.log("MIQ(#{name}) LOG MEMORY deliver_queue_message" \
               ", Command: [#{msg.class_name}.#{msg.method_name}], Instance id: [#{msg.instance_id}]")
end
