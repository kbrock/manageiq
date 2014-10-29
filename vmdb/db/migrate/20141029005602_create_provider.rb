class CreateProvider < ActiveRecord::Migration
  def up
    create_table "providers", :force => true do |t|
      t.string   "name"
      t.string   "port"
      t.string   "hostname"
      t.string   "ipaddress"
      t.datetime "created_on"
      t.datetime "updated_on"
      t.string   "guid",                        :limit => 36
      t.integer  "zone_id",                     :limit => 8
      t.string   "type"
      t.string   "api_version"
      t.string   "uid_ems"
      t.string   "provider_region"
    end
  end

  def down
    drop_table "providers"
  end
end
