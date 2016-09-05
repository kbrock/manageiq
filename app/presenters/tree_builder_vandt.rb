class TreeBuilderVandt < TreeBuilder
  include TreeBuilderArchived

  has_kids_for EmsInfra, [:x_get_tree_ems_children, :options]

  def tree_init_options(_tree_name)
    {:leaf => 'VmOrTemplate'}
  end

  def set_locals_for_render
    locals = super
    locals.merge!(:autoload => true)
  end

  def root_options
    [_("All VMs & Templates"), _("All VMs & Templates that I can see")]
  end

  def x_get_tree_roots(count_only, options)
    objects = count_only_or_objects_filtered(count_only, EmsInfra, "name", :match_via_descendants => VmOrTemplate)
    objects.collect! { |o|
      if false
        # not properly determining if open or closed
        x_build_node(o, nil, options.dup)
      else
        TreeBuilderVmsAndTemplates.new(o, options.merge(:show_vms => false)).tree
      end
    } unless count_only
    root_nodes = count_only_or_objects(count_only, x_get_tree_arch_orph_nodes("VMs and Templates"))

    objects + root_nodes
  end

  # Handle custom tree nodes (object is a Hash)
  def x_get_tree_custom_kids(object, count_only, _options)
    klass = ManageIQ::Providers::InfraManager::VmOrTemplate
    objects = case object[:id]
              when "orph" then klass.all_orphaned
              when "arch" then klass.all_archived
              end
    count_only_or_objects_filtered(count_only, objects, "name")
  end

  def x_get_child_nodes(id)
    model, _, prefix = self.class.extract_node_model_and_id(id)
    model == "Hash" ? super : find_child_recursive(x_get_tree_roots(false, {}), id)
  end

  def x_get_tree_ems_children(object, count_only, options)
    # if it got here, then always show the ems children (they only care if count > 0)
    if count_only
      # Rbac.filtered(object.vms).size
      1
    else
      if false
        # want this, but not working
        # it wants nodes not tree returned?
        TreeBuilderVmsAndTemplates.new(object, options).tree.children.first
      else
        Rbac.filtered(object.vms)
      end
    end
  end

  private

  def find_child_recursive(children, id)
    children.each do |t|
      return t[:children] if t[:key] == id

      found = find_child_recursive(t[:children], id) if t[:children]
      return found unless found.nil?
    end
    nil
  end
end
