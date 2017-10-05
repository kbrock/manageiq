describe ManageIQ::Providers::BaseManager::MetricsCapture do
  # created by Metric::Capture.perf_collect_all_metrics (via the queue)

  # ensure default settings.
  before do
    stub_settings(
      :performance => {
        :concurrent_requests => {
          :historical => 1,
          :hourly     => 1,
          :realtime   => 20,
        }
      }
    )
    MiqRegion.seed
    EvmSpecHelper.local_miq_server
  end

  # vmware centric, individual provider tests will override
  let(:ems) { FactoryGirl.create(:ems_vmware) }
  let(:capture) { ManageIQ::Providers::BaseManager::MetricsCapture.new(nil, ems) }
  let(:clusters) { FactoryGirl.create_list(:cluster_target, 2, :ext_management_system => ems) }
  let(:enabled_clusters) { clusters.select(&:perf_capture_enabled?) }
  let(:hosts) { FactoryGirl.create_list(:host_target_vmware, 6, :ext_management_system => ems) }
  let(:enabled_hosts) do
    hosts.select { |h| h.ems_cluster ? h.ems_cluster.perf_capture_enabled? : h.perf_capture_enabled? }
  end
  let(:vms) { hosts.flat_map(&:vms) }
  let(:enabled_vms) do
    vms.select { |vm| (vm.state == 'on') && enabled_hosts.include?(vm.host) && vm.host.perf_capture_enabled? }
  end
  let(:storages) { FactoryGirl.create_list(:storage_target_vmware, 2) }
  let(:enabled_storages) { hosts.flat_map(&:storages).uniq.select(&:perf_capture_enabled?) }

  it "has expected values" do
    wire_ems(storages, clusters, hosts)
    expect(enabled_hosts.size).to eq(3)
    expect(enabled_storages.size).to eq(1)
    expect(enabled_vms.size).to eq(2)
    expect(enabled_clusters.size).to eq(1)
  end

  describe "#detect_gap" do
  end

  describe "#grouped_targets" do
    context "with infra provider" do
      before do
        vms
        wire_ems(storages, clusters, hosts)
      end

      it "includes all objects" do
        targets = capture.send(:grouped_targets, ems)
        expect(targets["Host"]).to match_array(enabled_hosts)
        expect(targets["Storage"]).to match_array(enabled_storages)
        expect(targets["VmOrTemplate"]).to match_array(enabled_vms)
      end

      context "with :exclude_storages" do
        it "excludes storages" do
          targets = capture.send(:grouped_targets, ems, :exclude_storages => true)
          expect(targets["Host"]).to match_array(enabled_hosts)
          expect(targets["Storages"]).to be_nil
          expect(targets["VmOrTemplate"]).to match_array(enabled_vms)
        end
      end
    end

    # context "with cloud provider" do
    #   let(:ems) { FactoryGirl.create(:ems_openstack) }
    #   let(:hosts) { ... }
    #   let(:vms) { hosts.flat_map { |host| FactoryGirl.create(:vm_openstack, :host => host) } }

    #   it "includes storages" do
    #     ems
    #     vms
    #     targets = capture.send(:grouped_targets, ems)
    #     expect(targets["Host"]).to match_array(enabled_hosts)
    #     expect(targets["VmOrTemplate"]).to match_array(enabled_vms)
    #   end
    # end

    # context "with container provider" do
    #   let(:ems) { FactoryGirl.create(:ems_kubernetes) }
    # end

    context "with other provider" do
      let(:ems) { FactoryGirl.create(:automation_manager) }
      it "complains" do
        expect { capture.send(:grouped_targets, ems) }.to raise_error(/unknown/i)
      end
    end
  end

  describe "#perf_collect_storages" do
    before { wire_ems(storages, nil, hosts) }

    it "pushes directly to stack" do
      MiqQueue.delete_all
      expect(enabled_storages.count).to eq(1)
      expect(capture).not_to receive(:perf_capture_one)
      capture.send(:perf_collect_storages, enabled_storages, "realtime", nil, nil)
      expect(MiqQueue.group(:method_name).count).to eq("perf_capture_hourly" => enabled_storages.count)
    end
  end

  describe "#perf_collect_hosts" do
    it "groups hosts" do
      wire_ems(storages, clusters, hosts)
      Timecop.freeze("2011-01-11 17:30 UTC") do
        start_capture = 3.hours.ago.utc
        end_capture = Time.now.utc
        capture_time = 1.hour.ago.utc # actual time coming back from data

        MiqQueue.delete_all
        enabled_hosts.each do |host|
          expect(capture).to receive(:perf_capture_one).with(host, "realtime", start_capture, end_capture)
            .and_return(
              [capture_time, capture_time, {["Host", host.id] => { :counters => {}, :counter_values => {}}}]
            )
        end

        capture.send(:perf_collect_hosts, enabled_hosts, "realtime", start_capture, end_capture)
        expect(MiqQueue.count).to eq(2)

        nonclustered_queue_message = MiqQueue.select { |q| q.miq_callback.blank? }.first
        non_clustered_hosts = enabled_hosts.select { |h| h.ems_cluster_id.blank? }
        non_clustered_data  = non_clustered_hosts.each_with_object({}) do |host, h|
          h[["Host", host.id]] = {:counters => {}, :counter_values => {}}
        end
        expect(nonclustered_queue_message.attributes).to include(
          "queue_name"   => "ems_metrics_processor",
          "role"         => "ems_metrics_processor",
          "class_name"   => "ManageIQ::Providers::Vmware::InfraManager",
          "method_name"  => "perf_process",
          "instance_id"  => ems.id,
          "args"         => ["realtime", capture_time, capture_time],
          "miq_callback" => {},
          "msg_data"     => Marshal.dump(non_clustered_data),
        )

        clustered_queue_message = MiqQueue.select { |q| q.miq_callback.present? }.first
        clustered_hosts = enabled_hosts.select { |h| h.ems_cluster_id.present? }
        clustered_data  = clustered_hosts.each_with_object({}) do |host, h|
          h[["Host", host.id]] = {:counters => {}, :counter_values => {}}
        end
        expect(clustered_queue_message.attributes).to include(
          "queue_name"   => "ems_metrics_processor",
          "role"         => "ems_metrics_processor",
          "class_name"   => "ManageIQ::Providers::Vmware::InfraManager",
          "method_name"  => "perf_process",
          "instance_id"  => ems.id,
          "args"         => ["realtime", capture_time, capture_time],
          "miq_callback" => hash_including(
            :class_name  => "EmsCluster",
            :instance_id => clustered_hosts.first.ems_cluster_id,
            :method_name => "perf_rollup_range_cb",
            :role        => "ems_metrics_processor",
            :queue_name  => "ems_metrics_processor",
            :args        => [capture_time, capture_time, "realtime", nil],
          ),
          "msg_data"     => Marshal.dump(clustered_data),
        )
      end
    end
  end

  # does it group vms correctly (by query_size)
  # using Settings.performance.concurrent_requests.realtime - with minimum value of 20 :(
  describe "#perf_collect_targets" do
    it "groups vms" do
      Timecop.freeze("2011-01-11 17:30 UTC") do
        start_capture = 3.hours.ago.utc
        end_capture = Time.now.utc
        capture_time = 1.hour.ago.utc # actual time coming back from data

        MiqQueue.delete_all
        enabled_vms.each do |vm|
          expect(capture).to receive(:perf_capture_one).with(vm, "realtime", start_capture, end_capture)
            .and_return(
              [capture_time, capture_time, {["VmOrTemplate", vm.id] => {:counters => {}, :counter_values => {}}}]
            )
        end

        capture.send(:perf_collect_targets, enabled_vms, "realtime", start_capture, end_capture)
        vm_data = enabled_vms.each_with_object({}) do |vm, h|
          h[["VmOrTemplate", vm.id]] = {:counters => {}, :counter_values => {}}
        end
        expect(MiqQueue.count).to eq(1)
        expect(MiqQueue.first.attributes).to include(
          "queue_name"  => "ems_metrics_processor",
          "role"        => "ems_metrics_processor",
          "class_name"  => "ManageIQ::Providers::Vmware::InfraManager",
          "instance_id" => ems.id,
          "method_name" => "perf_process",
          "args"        => ["realtime", capture_time, capture_time],
          "msg_data"    => Marshal.dump(vm_data)
        )
      end
    end
  end

  private

  def wire_ems(storages, clusters, hosts)
    hosts.each_with_index do |host, n|
      clusters[n / 2].hosts << host if clusters.present? && n < 4
      host.storages << storages[n / 3] if storages
    end
    clusters.each(&:save!) if clusters.present?
    hosts.each(&:save!)
  end
end
