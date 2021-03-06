module Trample
  class Condition
    include Virtus.model
    attribute :name, Symbol
    attribute :query_name, Symbol, default: :name
    attribute :values, Array
    attribute :search_analyzed, Boolean, default: false
    attribute :and, Boolean
    attribute :not, Boolean
    attribute :prefix, Boolean, default: false
    attribute :any_text, Boolean, default: false
    attribute :autocomplete, Boolean, default: false
    attribute :from_eq
    attribute :to_eq
    attribute :from
    attribute :to
    attribute :single, Boolean, default: false
    attribute :range, Boolean, default: false
    attribute :fields, Array
    attribute :user_query, Hash
    attribute :transform, Proc, default: ->(_,_) { ->(val) { val } }
    attribute :search_klass
    attribute :lookup, Hash

    def initialize(attrs)
      attrs.merge!(single: true) if attrs[:name] == :keywords
      super(attrs)
    end

    def lookup_autocomplete
      if require_autocomplete_lookup?
        options = (lookup || {}).dup
        klass   = options.delete(:klass) || '::Trample::TextLookup'

        options.assert_valid_keys(:key, :label)

        options = options.merge({
          search_klass: search_klass,
          condition_name: name
        })

        lookup_instance = klass.to_s.constantize.new(options)

        self.values = lookup_instance.load(values) 
      end
    end

    def blank?
      values.reject { |v| v == "" || v.nil? }.empty? && !range?
    end

    def as_json(*opts)
      if single?
        values.first
      elsif range?
        {}.tap do |json|
          json[:from_eq] = from_eq if from_eq?
          json[:from]    = from if from?
          json[:to_eq]   = to_eq if to_eq?
          json[:to]      = to if to?
        end
      else
        { values: values, and: and? }
      end
    end

    def runtime_query_name
      name = query_name
      return "#{name}.text_start"   if prefix?
      return "#{name}.text_middle"  if any_text?
      return "#{name}.analyzed"     if search_analyzed?
      return "#{name}.autocomplete" if autocomplete?
      name
    end

    def to_query
      if range?
        to_range_query
      else
        _values      = values.dup.map { |v| v.is_a?(Hash) ? v.dup : v }
        user_queries = _values.select(&is_user_query)
        transformed  = transform_values(_values - user_queries)

        user_query_clause = derive_user_query_clause(user_queries)
        main_clause = derive_main_clause(transformed)

        if user_query_clause.present?
          { or: [ main_clause, user_query_clause ] }
        else
          main_clause
        end
      end
    end

    private

    def transform_values(entries)
      entries = pluck_autocomplete_keys(entries) if has_autocomplete_keys?(entries)
      entries.map(&:downcase!) if search_analyzed?
      entries = entries.first if entries.length == 1
      entries
    end

    def derive_user_query_clause(user_queries)
      if user_queries.length > 0
        user_queries.each { |q| q.delete(:user_query) }
        condition = Condition.new(user_query.merge(values: user_queries))
        condition.to_query
      else
        {}
      end
    end

    def derive_main_clause(transformed)
      if prefix?
        to_prefix_query(transformed)
      elsif has_combinator?
        to_combinator_query(transformed)
      elsif exclusion?
        to_exclusion_query(transformed)
      else
        {runtime_query_name => transformed}
      end
    end

    def pluck_user_query_values!(values)
      user_queries = values.select(&is_user_query)
      values.reject!(&is_user_query)
      [values, user_queries]
    end

    def has_user_queries?(entries)
      entries.any?(&is_user_query)
    end

    def is_user_query
      ->(entry) { entry.is_a?(Hash) and !!entry[:user_query] }
    end

    def pluck_autocomplete_keys(entries)
      entries.map { |v| v[:key] }
    end

    def has_autocomplete_keys?(entries)
      multiple? and entries.any? { |e| e.is_a?(Hash) }
    end

    def has_combinator?
      not attributes[:and].nil?
    end

    def prefix?
      !!prefix
    end

    def exclusion?
      not attributes[:not].nil?
    end

    def anded?
      has_combinator? and !!self.and
    end

    def multiple?
      not single?
    end

    def not?
      !!self.not
    end

    def from?
      !!self.from
    end

    def to?
      !!self.to
    end

    def from_eq?
      !!self.from_eq
    end

    def to_eq?
      !!self.to_eq
    end

    def to_prefix_query(vals)
      if has_combinator?
        to_combinator_query(vals)
      else
        {runtime_query_name => vals}
      end
    end

    def to_exclusion_query(vals)
      if not?
        {runtime_query_name => {not: vals}}
      else
        {runtime_query_name => vals}
      end
    end

    def to_combinator_query(vals, query_name_override = nil)
      if anded?
        {runtime_query_name => {all: vals}}
      else
        {runtime_query_name => vals}
      end
    end

    def to_range_query
      _from_eq = transform.call(self.from_eq) if from_eq?
      _to_eq   = transform.call(self.to_eq) if to_eq?
      _from    = transform.call(self.from) if from?
      _to      = transform.call(self.to) if to?

      hash = {}
      hash.merge!(gte: _from_eq) if _from_eq
      hash.merge!(gt: _from) if _from
      hash.merge!(lte: _to_eq) if _to_eq
      hash.merge!(lt: _to) if _to

      { runtime_query_name => hash }
    end

    def require_autocomplete_lookup?
      (values.present? && values.first.is_a?(Hash)) && 
        values.any? { |v| v[:text].blank? }
    end
  end
end
