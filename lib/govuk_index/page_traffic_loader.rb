module GovukIndex
  class PageTrafficLoader
    def initialize(iostream_batch_size: 250)
      @iostream_batch_size = iostream_batch_size
      @logger = Logging.logger[self]
      @logger.level = :info
    end

    # Load data to a new index and switch aliases.  There's strictly
    # speaking a race condition here where a new index exists but the
    # old index is writable, but as this method is only triggered by
    # the 'bin/page_traffic_load' script, that's fine, just don't run
    # two of them at once.
    def load_from(iostream)
      new_index = index_group.create_index
      @logger.info "Created index #{new_index.real_name}"

      old_index = index_group.current_real
      @logger.info "Old index #{old_index.real_name}"

      @logger.info "Indexing to #{new_index.real_name}"

      in_even_sized_batches(iostream) do |lines|
        GovukIndex::PageTrafficWorker.perform_async(lines, new_index.real_name)
      end

      GovukIndex::PageTrafficWorker.wait_until_processed
      new_index.commit

      index_group.switch_to(new_index)
      old_index.close
    end

  private

    # Breaks the given input stream into batches of documents
    # This is due to ES recommendations for index optimisation
    # https://www.elastic.co/guide/en/elasticsearch/reference/2.4/docs-bulk.html
    def in_even_sized_batches(iostream, batch_size = @iostream_batch_size, &_block)
      iostream.each_line.each_slice(batch_size * 2) do |batch|
        yield(batch.map { |b| JSON.parse(b) })
      end
    end

    def index_group
      @index_group ||= SearchConfig.instance.search_server.index_group(
        SearchConfig.instance.page_traffic_index_name
      )
    end
  end
end
