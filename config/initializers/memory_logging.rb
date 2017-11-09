require 'sys/proctable'

class MemoryLogger
  PSS    = true
  OSPACE = true
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
