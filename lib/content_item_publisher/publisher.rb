require "gds_api/publishing_api_v2"

# ContentItemPublisher is responsible for publishing content items related
# to search, such as finders and finder email signup pages.
module ContentItemPublisher
  class Publisher
    def initialize(content_item, timestamp = Time.now.iso8601, logger = Logger.new(STDOUT))
      @content_item = content_item
      @logger = logger
      @timestamp = timestamp
    end

    def call
      publish(content_item)
    end

  private

    attr_reader :content_item, :logger, :timestamp

    def content_item_presenter
      raise NotImplementedError
    end

    def publish(content_item)
      presenter = content_item_presenter.new(content_item, timestamp)

      logger.info("Publishing #{presenter.description}")

      Services.publishing_api.put_content(presenter.content_id, presenter.present)
      Services.publishing_api.patch_links(presenter.content_id, presenter.present_links)
      Services.publishing_api.publish(presenter.content_id)
    end
  end
end
