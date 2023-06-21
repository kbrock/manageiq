class PersistentVolumeClaim < ApplicationRecord
  # technically this belongs_to :class_name => "ManageIQ::Providers::ContainerManager"
  belongs_to :ext_management_system, :foreign_key => "ems_id", :inverse_of => :persistent_volume_claims
  belongs_to :container_project
  has_many :container_volumes, :inverse_of => :persistent_volume_claim # rubocop:disable Rails/HasManyOrHasOneDependent
  has_one :persistent_volume, -> { where(:type => 'PersistentVolume') }, :class_name => "ContainerVolume", :inverse_of => :persistent_volume_claim # rubocop:disable Rails/HasManyOrHasOneDependent
  serialize :capacity, Hash
  serialize :requests, Hash
  serialize :limits, Hash

  virtual_column :storage_capacity, :type => :integer

  def storage_capacity
    capacity[:storage]
  end
end
