require 'spec/support/index_helpers'

module IntegrationSpecHelper
  SAMPLE_DOCUMENT_ATTRIBUTES = {
    "title" => "TITLE1",
    "description" => "DESCRIPTION",
    "format" => "local_transaction",
    "link" => "/URL",
    "_type" => "edition",
  }.freeze

  def self.included(base)
    base.after do
      teardown
    end

    @before_suite_setup ||= setup_before_suite
  end

  def self.setup_before_suite
    # we want this process to run before the suite when integration tests are run. :)
    RSpec.configure do |config|
      config.before(:suite) do
        IndexHelpers.setup_test_indexes
      end

      config.after(:suite) do
        IndexHelpers.clean_all
      end
    end
  end

  def teardown
    IndexHelpers.all_index_names.each do |index|
      clean_index_content(index)
    end
  end

  def search_config
    SearchConfig.instance
  end

  def search_server
    search_config.search_server
  end

  def sample_document
    Document.from_hash(SAMPLE_DOCUMENT_ATTRIBUTES, sample_elasticsearch_types)
  end

  def insert_document(index_name, attributes, id: attributes["link"], type: "edition", version: nil)
    version_details =
      if version
        {
          version: version,
          version_type: 'external',
        }
      else
        {}
      end

    id ||= "/test/#{SecureRandom.uuid}"
    attributes['link'] ||= id

    client.create(
      {
        index: index_name,
        type: type,
        id: id,
        body: attributes,
      }.merge(version_details)
    )

    id
  end

  def clean_index_content(index)
    commit_index index

    hits = client.search(index: index, size: 1000)['hits']['hits']
    return if hits.empty?

    client.bulk body: (hits.map { |hit| { delete: { _index: index, _type: hit['_type'], _id: hit['_id'] } } })
    commit_index index
  end

  def commit_document(index_name, attributes, id: attributes["link"], type: "edition")
    return_id = insert_document(index_name, attributes, id: id, type: type)
    commit_index(index_name)
    return_id
  end

  def commit_index(index_name = "mainstream_test")
    client.indices.refresh(index: index_name)
  end

  def app
    Rummager
  end

  def client
    # Set a fairly long timeout to avoid timeouts on index creation on the CI
    # servers
    @client ||= Services::elasticsearch(hosts: SearchConfig.instance.base_uri, timeout: 10)
  end

  def parsed_response
    JSON.parse(last_response.body)
  end

  def expect_document_is_in_rummager(document, type: "edition", index: 'mainstream_test')
    retrieved = fetch_document_from_rummager(id: document['link'], index: index)

    expect(type).to eq(retrieved["_type"])

    retrieved_source = retrieved["_source"]
    document.each do |key, value|
      expect(value).to eq(retrieved_source[key]), "Field #{key} should be '#{value}' but was '#{retrieved_source[key]}'"
    end
  end

  def sample_document_attributes(index_name, section_count)
    short_index_name = index_name.sub("_test", "")
    (1..section_count).map do |i|
      title = "Sample #{short_index_name} document #{i}"
      if i % 2 == 1
        title = title.downcase
      end
      fields = {
        "title" => title,
        "link" => "/#{short_index_name}-#{i}",
        "indexable_content" => "Something something important content id #{i}",
        "mainstream_browse_pages" => "browse/page/#{i}",
        "format" => "answers"
      }
      if i % 2 == 0
        fields["specialist_sectors"] = ["farming"]
      end
      if short_index_name == "government"
        fields["public_timestamp"] = "#{i + 2000}-01-01T00:00:00"
      end
      fields
    end
  end

  def add_sample_documents(index_name, count)
    attributes = sample_document_attributes(index_name, count)
    data = attributes.flat_map do |sample_document|
      [
        { index: { _id: sample_document['link'], _type: 'edition' } },
        sample_document,
      ]
    end

    client.bulk(index: index_name, body: data)
    commit_index(index_name)
  end

  def try_remove_test_index(index_name = nil)
    index_name ||= SearchConfig.instance.default_index_name
    raise "Attempting to delete non-test index: #{index_name}" unless index_name =~ /test/

    if client.indices.exists?(index: index_name)
      client.indices.delete(index: index_name)
    end
  end

  def stub_message_payload(example_document, unpublishing: false)
    routing_key = unpublishing ? 'test.unpublish' : 'test.a_routing_key'
    double(:message, ack: true, payload: example_document, delivery_info: { routing_key: routing_key })
  end

private

  def build_sample_documents_on_content_indices(documents_per_index:)
    SearchConfig.instance.content_index_names.each do |index_name|
      add_sample_documents(index_name, documents_per_index)
    end
  end

  def fetch_document_from_rummager(id:, index: 'mainstream_test', type: '_all')
    client.get(
      index: index,
      type: type,
      id: id
    )
  end
end
