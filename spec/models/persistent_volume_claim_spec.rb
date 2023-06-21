RSpec.describe PersistentVolumeClaim do
  describe "#storage_capacity" do
    let(:storage_size) { 123_456_789 }

    it "returns value for :storage key in Hash column :capacity" do
      persistent_volume = FactoryBot.create(
        :persistent_volume_claim,
        :capacity => {:storage => storage_size, :foo => "something"}
      )
      expect(persistent_volume.storage_capacity).to eq storage_size
    end

    it "returns nil if there is no :storage key in Hash column :capacity" do
      persistent_volume = FactoryBot.create(
        :persistent_volume_claim,
        :capacity => {:foo => "something"}
      )
      expect(persistent_volume.storage_capacity).to be nil
    end
  end

  describe "#persistent_volume" do
    it "finds none" do
      pvc = FactoryBot.create(:persistent_volume_claim)
      FactoryBot.create(:container_volume, :persistent_volume_claim => pvc)
      expect(pvc.persistent_volume).to be_nil
    end

    it "finds one" do
      pvc = FactoryBot.create(:persistent_volume_claim)
      FactoryBot.create(:container_volume, :persistent_volume_claim => pvc)
      pv = FactoryBot.create(:persistent_volume, :persistent_volume_claim => pvc)
      expect(pvc.persistent_volume).to eq(pv)
    end
  end
end
