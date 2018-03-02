module Searchkick
  class RecordIndexer
    EXCLUDED_ATTRIBUTES = ["_id", "_type"]

    attr_reader :index, :record

    def initialize(index, record)
      @index = index
      @record = record
    end

    def index_data
      data = record_data
      data[:data] = search_data
      {index: data}
    end

    def update_data(method_name)
      data = record_data
      data[:data] = {doc: search_data(method_name)}
      {update: data}
    end

    def delete_data
      {delete: record_data}
    end

    def document_type(ignore_type = false)
      index.klass_document_type(record.class, ignore_type)
    end

    def search_id
      id = record.respond_to?(:search_document_id) ? record.search_document_id : record.id
      id.is_a?(Numeric) ? id : id.to_s
    end

    private

    def record_data
      data = {
        _index: index.name,
        _id: search_id,
        _type: document_type
      }
      data[:_routing] = record.search_routing if record.respond_to?(:search_routing)
      data
    end

    def search_data(method_name = nil)
      partial_reindex = !method_name.nil?
      options = record.class.searchkick_options

      # remove _id since search_id is used instead
      source = record.send(method_name || :search_data).each_with_object({}) { |(k, v), memo| memo[k.to_s] = v; memo }.except(*EXCLUDED_ATTRIBUTES)

      # conversions
      if options[:conversions]
        Array(options[:conversions]).map(&:to_s).each do |conversions_field|
          if source[conversions_field]
            source[conversions_field] = source[conversions_field].map { |k, v| {query: k, count: v} }
          end
        end
      end

      # hack to prevent generator field doesn't exist error
      if options[:suggest]
        options[:suggest].map(&:to_s).each do |field|
          source[field] = nil if !source[field] && !partial_reindex
        end
      end

      # locations
      if options[:locations]
        options[:locations].map(&:to_s).each do |field|
          if source[field]
            if !source[field].is_a?(Hash) && (source[field].first.is_a?(Array) || source[field].first.is_a?(Hash))
              # multiple locations
              source[field] = source[field].map { |a| location_value(a) }
            else
              source[field] = location_value(source[field])
            end
          end
        end
      end

      if !source.key?("type") && record.class.searchkick_klass.searchkick_options[:inheritance]
        source["type"] = document_type(true)
      end

      cast_big_decimal(source)

      source
    end

    def location_value(value)
      if value.is_a?(Array)
        value.map(&:to_f).reverse
      elsif value.is_a?(Hash)
        {lat: value[:lat].to_f, lon: value[:lon].to_f}
      else
        value
      end
    end

    # change all BigDecimal values to floats due to
    # https://github.com/rails/rails/issues/6033
    # possible loss of precision :/
    def cast_big_decimal(obj)
      case obj
      when BigDecimal
        obj.to_f
      when Hash
        obj.each do |k, v|
          obj[k] = cast_big_decimal(v)
        end
      when Enumerable
        obj.map do |v|
          cast_big_decimal(v)
        end
      else
        obj
      end
    end
  end
end