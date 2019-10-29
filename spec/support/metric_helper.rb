module Spec
  module Support
    module MetricHelper
      # for a given set of targets, determine the timings we think we should generate
      #
      def queue_timings_for_targets(targets, days_ago_start = 7, days_ago_end = -1, gap = false)
        targets.each_with_object({}) do |t, messages|
          if t.kind_of?(Storage)
            messages["hourly"] ||= {}
            messages["hourly"][t] = [[4.hours.ago.utc.beginning_of_day]]
          else
            unless gap
              messages["realtime"] ||= {}
              messages["realtime"][t] = [[4.hours.ago.utc.beginning_of_day]]
            end
            messages["historical"] ||= {}
             messages["historical"][t] = [[days_ago_start.days.ago.utc, days_ago_end.days.ago.utc].map { |i| gap ? i : i.beginning_of_day} ]
          end
        end
      end

      # method_name => {target => [timing1, timing2] }
      # for each capture type, what objects are submitted and what are their time frames
      # @return [Hash{String => Hash{Object => Array<Array>}} ]
      def queue_timings(items = MiqQueue.where(:method_name => %w[perf_capture_hourly perf_capture_realtime perf_capture_historical]))
        messages = {}
        items.each do |q|
          obj = q.instance_id ? Object.const_get(q.class_name).find(q.instance_id) : q.class_name.constantize

          interval_name = q.method_name.sub("perf_capture_", "")

          messages[interval_name] ||= {}
          (messages[interval_name][obj] ||= []) << q.args
        end
        messages["historical"]&.transform_values! { |v| combine_consecutive(v) }

        messages
      end

      def combine_consecutive(array)
        x = array.sort!.shift
        array.each_with_object([]) do |i, ac|
          if i.first == x.last
            x[1] = i.last
          else
            ac << x
            x = i
          end
        end << x
      end

      def date_range(days_ago_start = 7.days.ago.utc, days_ago_end = 1.day.from_now.utc, gap = false)
        [[days_ago_start, days_ago_end].map { |i| gap ? i : i.beginning_of_day }]
      end
    end
  end
end

# These contexts expect the following setup:
#
# before do
#   MiqRegion.seed
#   @zone = EvmSpecHelper.local_miq_server.zone
# end
RSpec.shared_context 'with enabled/disabled vmware targets', :with_enabled_disabled_vmware do
  before do
    @ems_vmware = FactoryBot.create(:ems_vmware, :zone => @zone)
    @storages = FactoryBot.create_list(:storage_target_vmware, 2)
    @vmware_clusters = FactoryBot.create_list(:cluster_target, 2)
    @ems_vmware.ems_clusters = @vmware_clusters

    6.times do |n|
      host = FactoryBot.create(:host_target_vmware, :ext_management_system => @ems_vmware)
      @ems_vmware.hosts << host

      @vmware_clusters[n / 2].hosts << host if n < 4
      host.storages << @storages[n / 3]
    end

    MiqQueue.delete_all
    @ems_vmware.reload
  end

  let(:all_targets) { Metric::Targets.capture_ems_targets(@ems_vmware) }
end

RSpec.shared_context "with a small environment and time_profile", :with_small_vmware do
  before do
    @ems_vmware = FactoryBot.create(:ems_vmware, :zone => @zone)
    @vm1 = FactoryBot.create(:vm_vmware)
    @vm2 = FactoryBot.create(:vm_vmware, :hardware => FactoryBot.create(:hardware, :cpu1x2, :memory_mb => 4096))
    @host1 = FactoryBot.create(:host, :hardware => FactoryBot.create(:hardware, :memory_mb => 8124, :cpu_total_cores => 1, :cpu_speed => 9576), :vms => [@vm1])
    @host2 = FactoryBot.create(:host, :hardware => FactoryBot.create(:hardware, :memory_mb => 8124, :cpu_total_cores => 1, :cpu_speed => 9576))

    @ems_cluster = FactoryBot.create(:ems_cluster, :ext_management_system => @ems_vmware)
    @ems_cluster.hosts << @host1
    @ems_cluster.hosts << @host2

    @time_profile = FactoryBot.create(:time_profile_utc)

    MiqQueue.delete_all
  end
end

RSpec.shared_context "with openstack", :with_openstack_and_availability_zones do
  before do
    @ems_openstack = FactoryBot.create(:ems_openstack, :zone => @zone)
    @availability_zone = FactoryBot.create(:availability_zone_target)
    @ems_openstack.availability_zones << @availability_zone
    @vms_in_az = FactoryBot.create_list(:vm_openstack, 2, :ems_id => @ems_openstack.id)
    @availability_zone.vms = @vms_in_az
    @availability_zone.vms.push(FactoryBot.create(:vm_openstack, :ems_id => nil))
    @vms_not_in_az = FactoryBot.create_list(:vm_openstack, 3, :ems_id => @ems_openstack.id)

    MiqQueue.delete_all
  end
end
