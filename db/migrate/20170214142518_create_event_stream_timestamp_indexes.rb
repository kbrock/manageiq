class CreateEventStreamTimestampIndexes < ActiveRecord::Migration[5.0]
  def change
    say_with_time('updating event streams ems_cluster_id index (1/5)') do
      remove_index :event_streams, :name => "index_event_streams_on_ems_cluster_id"
      add_index :event_streams, [:ems_cluster_id, :timestamp], :name => "index_event_streams_on_ems_cluster_id"
    end

    say_with_time('updating event streams host_id index (2/5)')
      remove_index :event_streams, :name => "index_event_streams_on_host_id"
      add_index :event_streams, [:host_id, :timestamp], :name => "index_event_streams_on_host_id"
    end

    say_with_time('updating event streams dest_host_id index (3/5)')
      remove_index :event_streams, :name => "index_event_streams_on_dest_host_id"
      add_index :event_streams, [:dest_host_id, :timestamp], :name => "index_event_streams_on_dest_host_id"
    end

    say_with_time('updating event streams vm_or_template_id index (4/5)')
      remove_index :event_streams, :name => "index_event_streams_on_vm_or_template_id"
      add_index :event_streams, [:vm_or_template_id, :timestamp], :name => "index_event_streams_on_vm_or_template_id"
    end

    say_with_time('updating event streams dest_vm_or_template_id index (5/5)')
      remove_index :event_streams, :name => "index_event_streams_on_dest_vm_or_template_id"
      add_index :event_streams, [:dest_vm_or_template_id, :timestamp], :name => "index_event_streams_on_dest_vm_or_template_id"
    end
  end
end
