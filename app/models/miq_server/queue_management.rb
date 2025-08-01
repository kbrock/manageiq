module MiqServer::QueueManagement
  extend ActiveSupport::Concern

  def clear_miq_queue_for_this_server
    loop do
      msg = MiqQueue.get(:queue_name => 'miq_server', :zone => my_zone)
      break if msg.nil?

      _log.info("Removing message #{MiqQueue.format_full_log_msg(msg)}")
      msg.destroy
    end
  end

  def clean_stop_worker_queue_items
    MiqQueue.where(
      :class_name  => self.class.name,
      :method_name => "stop_worker",
      :queue_name  => 'miq_server',
      :server_guid => guid
    ).destroy_all
  end

  def process_miq_queue
    loop do
      msg = MiqQueue.get(:queue_name => 'miq_server', :zone => my_zone)
      break if msg.nil?

      status, message, result = msg.deliver(self)

      if status == "timeout"
        begin
          _log.info("Reconnecting to DB after timeout error during queue deliver")
          ActiveRecord::Base.postgresql_ssl_friendly_base_reconnect
        rescue => err
          _log.error("Error encountered reconnecting to the database, error:#{err.class.name}: #{err.message}")
        end
      end

      msg.delivered(status, message, result) unless status == 'retry'
    end
  end

  def enqueue_for_server(method_name)
    MiqQueue.put_unless_exists(
      :class_name  => self.class.name,
      :instance_id => id,
      :queue_name  => 'miq_server',
      :zone        => zone.name,
      :method_name => method_name,
      :server_guid => guid
    )
  end

  def shutdown_and_exit_queue
    enqueue_for_server('shutdown_and_exit')
  end

  # Tell the remote or local server to restart
  def restart_queue
    log_message  = "Server restart requested"
    log_message += ", remote server: [#{name}], GUID: [#{guid}], initiated from: [#{MiqServer.my_server.name}], GUID: [#{MiqServer.my_server.guid}]" if is_remote?
    _log.info(log_message)
    enqueue_for_server('restart')
  end
end
