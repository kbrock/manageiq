class Provider < ActiveRecord::Base
  acts_as_miq_taggable
  include AuthenticationMixin
  
end
