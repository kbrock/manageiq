module Metric::Targets
  cache_with_timeout(:perf_capture_always, 1.minute) do
    MiqRegion.my_region.perf_capture_always
  end

  def self.perf_capture_always=(options)
    perf_capture_always_clear_cache
    MiqRegion.my_region.perf_capture_always = options
  end

  def self.capture_infra_targets(zone, options)
    # Preload all of the objects we are going to be inspecting.
    includes = {:ext_management_systems => {:hosts => {:ems_cluster => :tags, :tags => {}}}}
    MiqPreloader.preload(zone, includes)

    emses = zone.ext_management_systems

    # If it can and does have a cluster, then ask that, otherwise, ask host itself.
    hosts = emses.flat_map(&:host).select do |t|
      t.ems_cluster ? t.ems_cluster.perf_capture_enabled? : t.perf_capture_enabled?
    end
    storages = capture_storage_targets(hosts, options)
    vms = capture_vm_targets(hosts, options)

    hosts + storages + vms
  end

  # @return vms under all availability zones
  #         and vms under no availability zone
  # NOTE: some stacks (e.g. nova) default to no availability zone
  def self.capture_cloud_targets(zone, options = {})
    return [] if options[:exclude_vms]

    MiqPreloader.preload(zone.ems_clouds, :vms => [{:availability_zone => :tags}, :ext_management_system])

    zone.ems_clouds.flat_map(&:vms).select do |vm|
      vm.state == 'on' && (vm.availability_zone.nil? || vm.availability_zone.perf_capture_enabled?)
    end
  end

  def self.capture_container_targets(zone, _options)
    includes = {
      :container_nodes  => :tags,
      :container_groups => [:tags, :containers => :tags],
    }

    MiqPreloader.preload(zone.ems_containers, includes)

    targets = []
    zone.ems_containers.each do |ems|
      targets += ems.container_nodes
      targets += ems.container_groups
      targets += ems.container_groups.flat_map(&:containers)
    end

    targets
  end

  # @param [Host] hosts hosts that are a) enabled and b) have an ems
  def self.capture_vm_targets(hosts, options)
    return Vm.none if options[:exclude_vms]
    MiqPreloader.preload(hosts, :vms => :ext_management_system)
    hosts.flat_map { |t| t.vms.select { |v| v.state == 'on' } }
  end

  # @param [Host] hosts hosts that are a) enabled and b) have an ems
  # hosts preloaded storages and tags
  def self.capture_storage_targets(hosts, options)
    return Storage.none if options[:exclude_storages]
    MiqPreloader.preload(hosts, :storages => :tags)
    hosts.flat_map { |h| h.storages.select { |s| Storage.supports?(s.store_type) && s.perf_capture_enabled? } }
  end

  # If a Cluster, standalone Host, or Storage is not enabled, skip it.
  # If a Cluster is enabled, capture all of its Hosts.
  # If a Host is enabled, capture all of its Vms.
  def self.capture_targets(zone = nil, options = {})
    zone = MiqServer.my_server.zone if zone.nil?
    zone = Zone.find(zone) if zone.kind_of?(Integer)
    capture_infra_targets(zone, options) + \
      capture_cloud_targets(zone, options) + \
      capture_container_targets(zone, options)
  end
end
