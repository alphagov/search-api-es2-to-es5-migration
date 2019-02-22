module GovukIndex
  class PopularityWorker < Indexer::BaseWorker
    BULK_INDEX_TIMEOUT = 60
    QUEUE_NAME = 'bulk'.freeze
    sidekiq_options queue: QUEUE_NAME

    def perform(records, destination_index)
      actions = Index::ElasticsearchProcessor.new(client: GovukIndex::Client.new(timeout: BULK_INDEX_TIMEOUT, index_name: destination_index))

      popularities = retrieve_popularities_for(destination_index, records)
      records.each do |record|
        actions.save(
          process_record(record, popularities)
        )
      end

      actions.commit
    end

    def process_record(record, popularities)
      base_path = record['identifier']['_id']
      OpenStruct.new(
        identifier: record['identifier'].merge('_version_type' => 'external_gte', '_type' => 'generic-document'),
        document: record['document'].merge('popularity' => popularities[base_path]),
      )
    end

    def retrieve_popularities_for(index_name, records)
      lookup = Indexer::PopularityLookup.new(index_name, SearchConfig.instance)
      lookup.lookup_popularities(records.map { |r| r['identifier']['_id'] })
    end
  end
end
