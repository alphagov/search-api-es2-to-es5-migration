require 'spec_helper'

RSpec.describe GovukIndex::PageTrafficLoader do
  before do
    @new_index = double(:new_index, commit: true, real_name: 'new_index_name')
    @current_index = double(:current_index, close: true, real_name: '')

    allow_any_instance_of(SearchIndices::IndexGroup).to receive(:create_index).and_return(@new_index)
    allow_any_instance_of(SearchIndices::IndexGroup).to receive(:current_real).and_return(@current_index)
    allow_any_instance_of(SearchIndices::IndexGroup).to receive(:switch_to)

    allow(GovukIndex::PageTrafficWorker).to receive(:wait_until_processed)
  end

  it 'processes input data in batches of pairs based on the batch size' do
    input = StringIO.new(('a'..'e').to_a.map { |v| %[{"val": "#{v}"}\n{"data": 1}] }.join("\n"))

    line1 = [{ "val" => "a" }, { "data" => 1 }, { "val" => "b" }, { "data" => 1 }]
    line2 = [{ "val" => "c" }, { "data" => 1 }, { "val" => "d" }, { "data" => 1 }]
    line3 = [{ "val" => "e" }, { "data" => 1 }]

    expect(GovukIndex::PageTrafficWorker).to receive(:perform_async).with(line1, 'new_index_name')
    expect(GovukIndex::PageTrafficWorker).to receive(:perform_async).with(line2, 'new_index_name')
    expect(GovukIndex::PageTrafficWorker).to receive(:perform_async).with(line3, 'new_index_name')

    loader = GovukIndex::PageTrafficLoader.new(iostream_batch_size: 2)

    loader.load_from(input)
  end
end
