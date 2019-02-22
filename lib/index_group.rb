module SearchIndices
  # A group of related indexes.
  #
  # An index group, say "govuk", consists of a number of indexes of the
  # form "govuk-<timestamp>-<uuid>". For example:
  #
  #   govuk-2013-02-28t15:51:12z-50e3251b-869b-4894-b83c-de4675cefff6
  #
  # One of these indexes is aliased to the group name itself.
  class IndexGroup
    def initialize(base_uri, name, schema, search_config)
      @base_uri = base_uri
      @client = Services::elasticsearch(hosts: base_uri)
      # Index creation can take longer than other requests, so create a separate
      # client with a longer timeout
      @index_creation_client = Services::elasticsearch(hosts: base_uri, timeout: 10)
      @name = name
      @schema = schema
      @search_config = search_config
    end

    def index_for_name(real_name)
      SearchIndices::Index.new(
        @base_uri, real_name, @name, mappings, @search_config
      )
    end

    def create_index
      index_name = generate_name
      index_payload = {
        "settings" => settings,
        "mappings" => mappings,
      }
      @index_creation_client.indices.create(
        index: index_name,
        body: index_payload
      )

      logger.info "Created index #{index_name}"

      Index.new(@base_uri, index_name, @name, mappings, @search_config)
    end

    def switch_to(index)
      # Loading this manually rather than using `index_map` because we may have
      # unaliased indices, which won't match the new naming convention.
      indices = @client.indices.get_alias

      # Bail if there is an existing index with this name.
      # elasticsearch won't allow us to add an alias with the same name as an
      # existing index. If such an index exists, it hasn't yet been migrated to
      # the new alias-y way of doing things.
      if indices.include? @name
        raise RuntimeError, "There is an index called #{@name}"
      end

      # Response of the form:
      #   { "index_name" => { "aliases" => { "a1" => {}, "a2" => {} } }
      aliased_indices = indices.select { |_name, details|
        details.fetch("aliases", {}).include? @name
      }

      # For any existing indices with this alias, remove the alias
      # We would normally expect 0 or 1 such index, but several is valid too
      actions = aliased_indices.keys.map { |index_name|
        { "remove" => { "index" => index_name, "alias" => @name } }
      }

      logger.info do
        old_names = aliased_indices.keys.inspect
        new_name = index.index_name.inspect
        "Switching #{@name} alias from #{old_names} to #{new_name}"
      end

      actions << { "add" => { "index" => index.index_name, "alias" => @name } }

      payload = { "actions" => actions }

      @client.indices.update_aliases(body: payload)
    end

    def current
      Index.new(@base_uri, @name, @name, mappings, @search_config)
    end

    # The unaliased version of the current index
    #
    # When we're migrating, we need access to this so we can still manipulate
    # the index even after we have switched the alias
    def current_real
      current_index = current
      if current_index.exists?
        Index.new(@base_uri, current.real_name, @name, mappings, @search_config)
      end
    end

    def index_names
      alias_map.keys
    end

    def clean
      alias_map(include_closed: true).each do |name, details|
        delete(name) if details.fetch("aliases", {}).empty?
      end
    end

  private

    def logger
      Logging.logger[self]
    end

    def settings
      @settings ||= @schema.elasticsearch_settings(@name)
    end

    def mappings
      @mappings ||= @schema.elasticsearch_mappings(@name)
    end

    def generate_name
      # elasticsearch requires that all index names be lower case
      # (Thankfully, lower case ISO8601 timestamps are still valid)
      "#{@name}-#{Time.now.utc.iso8601}-#{SecureRandom.uuid}".downcase
    end

    def alias_map(include_closed: false)
      expand_wildcards = ['open']
      expand_wildcards << 'closed' if include_closed
      # Return a map of all aliases in this group, of the form:
      # { concrete_name => { "aliases" => { alias_name => {}, ... } }, ... }
      indices = @client.indices.get(index: "#{@name}*", expand_wildcards: expand_wildcards)
      indices.select { |name| name_pattern.match name }
    end

    def name_pattern
      %r{
        \A
        #{Regexp.escape(@name)}
        -
        \d{4}-\d{2}-\d{2}  # Date
        t
        \d{2}:\d{2}:\d{2}  # Time
        z
        -
        \h[-\h]*  # UUID
        \Z
      }x
    end

    def delete(index_name)
      logger.info "Deleting index #{index_name}"
      @client.indices.delete(index: index_name)
    end
  end
end
