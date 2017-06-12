module Metric::Capture
  VALID_CAPTURE_INTERVALS = ['realtime', 'hourly', 'historical'].freeze

  # This is nominally a VMware-specific value, but we currently expect
  # all providers to conform to it.
  REALTIME_METRICS_PER_MINUTE = 3

  REALTIME_PRIORITY = HOURLY_PRIORITY = DAILY_PRIORITY = MiqQueue::NORMAL_PRIORITY
  HISTORICAL_PRIORITY = MiqQueue::LOW_PRIORITY

  def self.capture_cols
    Metric.columns_hash.collect { |c, h| c.to_sym if h.type == :float && c[0, 7] != "derived" }.compact
  end

  def self.historical_days
    Settings.performance.history.initial_capture_days.to_i
  end

  def self.historical_start_time
    historical_days.days.ago.utc.beginning_of_day
  end

  def self.concurrent_requests(interval_name)
    requests = ::Settings.performance.concurrent_requests[interval_name]
    requests = 20 if requests < 20 && interval_name == 'realtime'
    requests
  end

  def self.standard_capture_threshold(target)
    target_key = target.class.base_model.to_s.underscore.to_sym
    minutes_ago(::Settings.performance.capture_threshold[target_key] ||
                ::Settings.performance.capture_threshold.default)
  end

  def self.alert_capture_threshold(target)
    target_key = target.class.base_model.to_s.underscore.to_sym
    minutes_ago(::Settings.performance.capture_threshold_with_alerts[target_key] ||
                ::Settings.performance.capture_threshold_with_alerts.default)
  end

  # COORDINATOR
  # NOTE: put_unless_exists prevents multiple running at same time
  def self.perf_capture_timer(zone = nil)
    _log.info "Queueing performance capture..."

    zone ||= MiqServer.my_server.zone
    targets = Metric::Targets.capture_targets(zone)

    targets_by_rollup_parent = calc_targets_by_rollup_parent(targets)
    target_options = calc_target_options(zone, targets_by_rollup_parent)
    targets = filter_perf_capture_now(targets, target_options)
    queue_captures(targets, target_options)

    # Purge tasks older than 4 hours
    MiqTask.delete_older(4.hours.ago.utc, "name LIKE 'Performance rollup for %'")

    _log.info "Queueing performance capture...Complete"
  end

  def self.perf_capture_gap(start_time, end_time, zone_id = nil)
    _log.info "Queueing performance capture for range: [#{start_time} - #{end_time}]..."

    zone = Zone.find(zone_id) if zone_id
    targets = Metric::Targets.capture_targets(zone, :exclude_storages => true)
    targets.each { |target| target.perf_capture_queue('historical', :start_time => start_time, :end_time => end_time, :zone => zone) }

    _log.info "Queueing performance capture for range: [#{start_time} - #{end_time}]...Complete"
  end

  def self.perf_capture_gap_queue(start_time, end_time, zone = nil)
    item = {
      :class_name  => name,
      :method_name => "perf_capture_gap",
      :role        => "ems_metrics_coordinator",
      :priority    => MiqQueue::HIGH_PRIORITY,
      :args        => [start_time, end_time, zone.try(:id)]
    }
    item[:zone] = zone.name if zone

    MiqQueue.put(item)
  end

  def self.filter_perf_capture_now(targets, target_options)
    targets.select do |target|
      options = target_options[target]
      # [:force] is set if we already determined this target needs perf capture
      if options[:force] || perf_capture_now?(target)
        true
      else
        _log.debug do
          "Skipping capture of #{target.log_target} -" +
            "Performance last captured on [#{target.last_perf_capture_on}] is within threshold"
        end
        false
      end
    end
  end

  # if it has not been run, or it was a very long time ago, just run it
  # if it has been run very recently (even too recently for realtime) then skip it
  # otherwise, it needs to be run if it is realtime, but not if it is standard threshold
  # assumes alert capture threshold <= standard capture threshold
  def self.perf_capture_now?(target)
    return true  if target.last_perf_capture_on.nil?
    return true  if target.last_perf_capture_on < standard_capture_threshold(target)
    return false if target.last_perf_capture_on >= alert_capture_threshold(target)
    MiqAlert.target_needs_realtime_capture?(target)
  end

  #
  # Capture entry points
  #

  # Collect realtime targets and group them by their rollup parent
  #   e.g.: {"EmsCluster:4"=>[Host:4], "EmsCluster:5"=>[Host:1, Host:2]}
  def self.calc_targets_by_rollup_parent(targets)
    # NOTE: only want realtime, but skipped since perf_target_to_interval_name(Host) == "realtime"
    targets.select { |target| target.kind_of?(Host) && perf_capture_now?(target) }.each_with_object({}) do |target, h|
      # Hosts have 1 optional EmsCluster parent
      target.perf_rollup_parents("realtime").to_a.compact.each do |parent|
        pkey = "#{parent.class}:#{parent.id}"
        h[pkey] ||= []
        h[pkey] << "#{target.class}:#{target.id}"
      end
    end
  end
  private_class_method :calc_targets_by_rollup_parent

  # Create task for ems host cluster rollups
  # {"EmsCluster:4" => Task{1}, "EmsCluster:5" => Task{2} }
  def self.calc_target_options(zone, targets_by_rollup_parent)
    task_end_time           = Time.now.utc.iso8601
    default_task_start_time = 1.hour.ago.utc.iso8601

    target_options = Hash.new { |h, k| h[k] = {:zone => zone} }
    # Create a new task for each rollup parent
    targets_by_rollup_parent.keys.each do |pkey|
      name = "Performance rollup for #{pkey}"
      prev_task = MiqTask.where(:identifier => pkey).order("id DESC").first
      task_start_time = prev_task ? prev_task.context_data[:end] : default_task_start_time

      task = MiqTask.create(
        :name         => name,
        :identifier   => pkey,
        :state        => MiqTask::STATE_QUEUED,
        :status       => MiqTask::STATUS_OK,
        :message      => "Task has been queued",
        :context_data => {
          :start    => task_start_time,
          :end      => task_end_time,
          :parent   => pkey,
          :targets  => targets_by_rollup_parent[pkey],
          :complete => [],
          :interval => "realtime"
        }
      )
      _log.info "Created task id: [#{task.id}] for: [#{pkey}] with targets: #{targets_by_rollup_parent[pkey].inspect} for time range: [#{task_start_time} - #{task_end_time}]"
      targets_by_rollup_parent[pkey].each do |target|
        target_options[target] = {
          :task_id => task.id,
          :force   => true, # Force collection since we've already verified that capture should be done now
          :zone    => zone,
        }
      end
    end
    target_options
  end
  private_class_method :calc_target_options

  def self.queue_captures(targets, target_options)
    # Queue the captures for each target
    use_historical = historical_days != 0

    targets.each do |target|
      interval_name = perf_target_to_interval_name(target)

      options = target_options[target]

      begin
        target.perf_capture_queue(interval_name, options)
        if !target.kind_of?(Storage) && use_historical && target.last_perf_capture_on.nil?
          target.perf_capture_queue('historical')
        end
      rescue => err
        _log.warn("Failed to queue perf_capture for target [#{target.class.name}], [#{target.id}], [#{target.name}]: #{err}")
      end
    end
  end
  private_class_method :queue_captures

  def self.perf_target_to_interval_name(target)
    case target
    when Host, VmOrTemplate then                       "realtime"
    when ContainerNode, Container, ContainerGroup then "realtime"
    when Storage then                                  "hourly"
    end
  end
  private_class_method :perf_target_to_interval_name

  def self.minutes_ago(value)
    if value.kind_of?(Integer) # Default unit is minutes
      value.minutes.ago.utc
    elsif value.nil?
      nil
    else
      value.to_i_with_method.seconds.ago.utc
    end
  end
  private_class_method :minutes_ago
end
