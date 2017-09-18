require 'spec_helper'

RSpec.describe 'Loading page traffic data', tags: ['integration'] do
  it 'adds data to the page traffic index' do
    id = "/test/page/#{SecureRandom.uuid}"
    data = [
      { index: { _id: id, _type: 'page_traffic' } }.to_json,
      { rank_14: 100, vf_14: 0.345, vc_14: 12 }.to_json
    ].join("\n")

    GovukIndex::PageTrafficLoader.new
      .load_from(StringIO.new(data))

    document = fetch_document_from_rummager(id: id, index: 'page-traffic_test')

    expect(document["_type"]).to eq('page_traffic')
    expect(document['_source']['rank_14']).to eq(100)
  end
end
