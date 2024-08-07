class ContainerRoute < ApplicationRecord
  include CustomAttributeMixin

  belongs_to :ext_management_system, :foreign_key => "ems_id"
  belongs_to :container_project
  belongs_to :container_service
  has_many :container_nodes, -> { distinct }, :through => :container_service
  has_many :container_groups, -> { distinct }, :through => :container_service
  has_many :annotations, -> { where(:section => "annotations") }, # rubocop:disable Rails/HasManyOrHasOneDependent
           :class_name => "CustomAttribute",
           :as         => :resource,
           :inverse_of => :resource
  has_many :labels, -> { where(:section => "labels") }, # rubocop:disable Rails/HasManyOrHasOneDependent
           :class_name => "CustomAttribute",
           :as         => :resource,
           :inverse_of => :resource

  acts_as_miq_taggable
end
