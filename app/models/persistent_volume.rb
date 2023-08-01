class PersistentVolume < ContainerVolume
  acts_as_miq_taggable
  include NewWithTypeStiMixin
  serialize :capacity, Hash

  # NOTE: overriding parent polymorphic. Ensuring the type gets set
  belongs_to :parent, :class_name => 'ExtManagementSystem'
  default_value_for :parent_type, 'ExtManagementSystem'

  has_many :container_volumes, -> { where(:type => 'ContainerVolume') }, :through => :persistent_volume_claim
  has_many :parents, -> { distinct }, :through => :container_volumes, :source_type => 'ContainerGroup'
  alias_attribute :container_groups, :parents

  virtual_delegate :name, :to => :parent, :prefix => true, :allow_nil => true, :type => :string
  virtual_attribute :storage_capacity, :string

  def storage_capacity
    capacity[:storage]
  end
end
