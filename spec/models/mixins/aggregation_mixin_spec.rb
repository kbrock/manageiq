describe AggregationMixin do
  it "aggregate host attributes" do
    cluster = FactoryGirl.create(:ems_cluster, :hosts => hosts_with_hardware)
    expect(cluster.aggregate_cpu_speed).to eq(47_984) # 2999 cpu_speed * 8 cpu_total_cores * 2 hardwares
    expect(cluster.aggregate_disk_capacity).to eq(80)
  end

  it "aggregates vm attributes"

  it "Supports vm attributes called by region aggregation" do
    MiqRegion.seed
    hosts_with_hardware
    expect($log).to receive(:info).with(/VMs: \[0\], Hosts: \[3\], Sockets: \[5\]/)
    MiqRegion.log_not_under_management("abc")
  end

  def hosts_with_hardware
    2.times.collect do
      FactoryGirl.create(:host,
                         :hardware => FactoryGirl.create(:hardware,
                                                         :cpu_sockets          => 2,
                                                         :cpu_cores_per_socket => 4,
                                                         :cpu_total_cores      => 8,
                                                         :cpu_speed            => 2_999,
                                                         :disk_capacity        => 40
                                                        )
                        )
    end +
    [FactoryGirl.create(:host, :hardware => FactoryGirl.create(:hardware))]
  end
end
