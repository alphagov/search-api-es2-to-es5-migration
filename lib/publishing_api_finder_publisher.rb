require "gds_api/publishing_api_v2"

class PublishingApiFinderPublisher
  def initialize(schema, timestamp = Time.now.iso8601, logger = Logger.new(STDOUT))
    @schema = schema
    @logger = logger
    @timestamp = timestamp
  end

  def call
    publish(schema)
  end

private

  attr_reader :schema, :logger, :timestamp

  def publishing_api
    @publishing_api ||= GdsApi::PublishingApiV2.new(
      Plek.new.find('publishing-api'),
      bearer_token: ENV['PUBLISHING_API_BEARER_TOKEN'] || 'example',
      timeout: 10,
    )
  end

  def publish(schema)
    finder_presenter = FinderContentItemPresenter.new(schema, timestamp)

    logger.info("Publishing '#{finder_presenter.name}' finder")

    publishing_api.put_content(finder_presenter.content_id, finder_presenter.present)
    publishing_api.patch_links(finder_presenter.content_id, finder_presenter.present_links)
    publishing_api.publish(finder_presenter.content_id)

    if schema.key?("signup_content_id")
      signup_presenter = FinderEmailSignupContentItemPresenter.new(schema, timestamp)

      logger.info("Publishing '#{signup_presenter.name}' finder")

      publishing_api.put_content(signup_presenter.content_id, signup_presenter.present)
      publishing_api.patch_links(signup_presenter.content_id, signup_presenter.present_links)
      publishing_api.publish(signup_presenter.content_id)
    end
  end
end

class FinderContentItemPresenter
  attr_reader :content_id, :schema, :name, :timestamp

  def initialize(schema, timestamp)
    @schema = schema
    @content_id = schema["content_id"]
    @name = schema["name"]
    @timestamp = timestamp
  end

  def present
    {
      base_path: schema["base_path"],
      description: schema["description"],
      details: details,
      document_type: schema["document_type"],
      locale: "en",
      phase: "live",
      public_updated_at: timestamp,
      publishing_app: schema["publishing_app"],
      rendering_app: schema["rendering_app"],
      routes: schema["routes"],
      schema_name: schema["schema_name"],
      title: schema["title"],
      update_type: "minor",
    }
  end

  def present_links
    links = {}
    links["email_alert_signup"] = [schema["signup_content_id"]] if schema.key?("signup_content_id")
    links["parent"] = Array(schema["parent"]) if schema.key?("parent")
    links["ordered_related_items"] = Array(schema["ordered_related_items"]) if schema.key?("ordered_related_items")

    { content_id: content_id, links: links }
  end

  def details
    schema["details"].except("email_filter_facets", "subscription_list_title_prefix")
  end
end

class FinderEmailSignupContentItemPresenter
  attr_reader :content_id, :schema, :name, :timestamp

  def initialize(schema, timestamp)
    @schema = schema
    @content_id = schema["signup_content_id"]
    @name = schema["name"]
    @timestamp = timestamp
  end

  def details
    details = schema.fetch("details", {})
    details.merge(
      "subscription_list_title_prefix" => details.fetch("subscription_list_title_prefix", {}),
      "email_filter_facets" => email_filter_facets,
    ).except("canonical_link", "document_noun",
      "facets", "filter", "generic_description",
      "reject", "summary", "sort")
  end

  def present
    path = schema["base_path"] + "/email-signup"
    {
      base_path: path,
      description: schema["signup_copy"],
      details: details,
      document_type: "finder_email_signup",
      locale: "en",
      phase: "live",
      public_updated_at: timestamp,
      publishing_app: schema["publishing_app"],
      rendering_app: schema["rendering_app"],
      routes: [{ "type" => "exact", "path" => path }],
      schema_name: "finder_email_signup",
      title: schema.fetch("signup_title", schema.fetch("name")),
      update_type: "minor",
    }
  end

  def present_links
    { content_id: content_id, links: {} }
  end

  def email_filter_facets
    schema["details"]["facets"].map do |facet|
      {
        "facet_id" => facet["key"],
        "facet_name" => facet["name"],
        "facet_choices" => facet["allowed_values"].map do |av|
          {
            "key" => av["value"],
            "radio_button_name" => av["label"],
            "topic_name" => av["label"],
            "prechecked" => false
          }
        end
      }
    end
  end
end
