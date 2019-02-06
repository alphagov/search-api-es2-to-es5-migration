module Search
  # Presents a combined set of results for a GOV.UK site search
  class ResultSetPresenter
    attr_reader :es_response, :search_params

    # `registries` should be a map from registry names to registries,
    # which gets passed to the ResultSetPresenter class. For example:
    #
    #     { organisations: OrganisationRegistry.new(...) }
    #
    # `aggregate_examples` is {field_name => {aggregate_value => {total: count, examples: [{field: value}, ...]}}}
    # ie: a hash keyed by field name, containing hashes keyed by aggregates value with
    # values containing example information for the value.
    def initialize(search_params:,
                   es_response:,
                   registries: {},
                   aggregate_examples: {},
                   schema: nil,
                   query_payload: {})

      @es_response = es_response
      @aggregates = es_response["aggregations"]
      @search_params = search_params
      @registries = registries
      @aggregate_examples = aggregate_examples
      @schema = schema
      @query_payload = query_payload
    end

    def present
      response = {
        results: presented_results,
        total: es_response.dig("hits", "total") || 0,
        start: search_params.start,
        search_params.aggregate_name => presented_aggregates,
        suggested_queries: suggested_queries
      }

      if search_params.show_query?
        response['elasticsearch_query'] = @query_payload
      end

      response
    end

  private

    def suggested_queries
      SpellCheckPresenter.new(es_response).present
    end

    def presented_results
      es_response.dig("hits", "hits").to_a.map do |raw_result|
        ResultPresenter.new(raw_result.to_hash, @registries, @schema, search_params).present
      end
    end

    def presented_aggregates
      AggregateResultPresenter.new(@aggregates, @aggregate_examples, @search_params, @registries).presented_aggregates
    end
  end
end
