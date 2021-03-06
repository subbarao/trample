require 'spec_helper'

RSpec.describe "searching", elasticsearch: true do
  class MyLookup
    include Virtus.model

    def load(values)
      values.map do | value |
        value[:text] = "#{value[:key]} - test"
        value
      end
    end
  end

  let(:klass) do
    Class.new(Trample::Search) do
      condition :id, user_query: {query_name: :name, prefix: true}
      condition :name
      condition :tags
      condition :age, range: true

      condition :tag_ids, user_query: {query_name: :tags, prefix: true}

      condition :_name_prefix, query_name: :name, prefix: true

      condition :simple_name, query_name: 'name', single: true
      condition :company_ids, query_name: 'company_id', 
                              lookup: { 
                                key: :company_id, 
                                label: :company_name 
                              }
      condition :company_custom_ids, query_name: 'company_id', 
                              lookup: { 
                                key: :company_id, 
                                label: :company_name,
                                klass: 'MyLookup'
                               }
    end
  end

  before do
    Searchkick.client.indices.delete index: '_all'
    foo = Company.create!(name: 'Foo Inc')
    bar = Company.create!(name: 'Bar Inc')
    apex = Company.create!(name: 'Apex Inc')
    Person.create!(name: 'Homer', tags: ['funny', 'stupid', 'bald'], age: 38, company: foo)
    Person.create!(name: 'Lisa', tags: ['funny', 'smart', 'kid'], age: 8, company: bar)
    Person.create!(name: 'Marge', tags: ['motherly'], age: 34, company: foo)
    Person.create!(name: 'Bart', tags: ['funny', 'stupid', 'kid'], age: 10, company: apex)
    Person.reindex

    klass.model(Person)
  end

  it "should fetch autocomplete labels by default" do
    search = klass.new
    search.condition(:company_ids).in([{key: Company.first.id.to_s}, { key: Company.last.id.to_s, text: Company.last.name  }])
    search.query!

    expect(search.conditions.as_json['company_ids'][:values]).to eq([{:key=>"1", :text=>"Foo Inc"}, {:key=>"3", :text=>"Apex Inc"}])
  end

  it "should not fetch autocomplete labels when lookup: false" do
    search = klass.new
    values = [{key: Company.first.id.to_s}, { key: Company.last.id.to_s, text: Company.last.name  }]
    search.condition(:company_ids).in(values)
    search.query!(lookup: false)

    expect(search.conditions.as_json['company_ids'][:values]).to eq([{:key=>"1"}, {:key=>"3", :text=>"Apex Inc"}])
  end

  it "should fetch autocomplete labels using custom lookup_class" do
    search = klass.new
    search.condition(:company_custom_ids).in([{key: Company.first.id.to_s}, { key: Company.last.id.to_s, text: Company.last.name  }])
    search.query!

    expect(search.conditions.as_json['company_custom_ids'][:values]).to eq([{:key=>"1", :text=>"#{Company.first.id} - test"}, {:key=>"3", :text=> "#{Company.last.id} - test"}])
  end

  it "records time the search took" do
    search = klass.new
    search.query!
    expect(search.metadata.took).to be_a(Integer)
  end

  it "records total entries" do
    search = klass.new
    search.query!
    expect(search.metadata.pagination.total).to eq(Person.count)
  end

  it "can query correctly when manually assigning" do
    search = klass.new
    search.condition(:name).eq('Homer')
    search.query!

    expect(search.results.length).to eq(1)
  end

  it "supports single-value conditions" do
    search = klass.new
    search.condition(:simple_name).eq('Homer')
    search.query!

    expect(search.results.length).to eq(1)
    expect(search.conditions.as_json['simple_name']).to eq('Homer')
  end

  it "supports single-value conditions via constructor" do
    search = klass.new(conditions: {simple_name: 'Homer'})
    search.query!

    expect(search.results.length).to eq(1)
  end

  it "can query analyzed via direct assignment" do
    search = klass.new
    search.condition(:name).analyzed('homer')
    search.query!

    expect(search.results.length).to eq(1)
  end

  it "can query analyzed via constructor" do
    search = klass.new(conditions: {name: {values: 'homer', search_analyzed: true}})
    search.query!

    expect(search.results.length).to eq(1)
  end

  it "queries basic conditions correctly via constructor" do
    search = klass.new(conditions: {name: "Homer"})
    search.query!

    expect(search.results.length).to eq(1)
  end

  it "should reject blank conditions" do
    search = klass.new(conditions: {name: {values: [""]}})
    search.query!

    expect(search.results.length).to eq(4)
  end

  it "queries arrays OR'd via constructor correctly" do
    search = klass.new(conditions: {tags: {values: ['funny', 'stupid'], and: false}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Lisa', 'Bart'])
  end

  it "queries arrays OR'd via direct assignment correctly" do
    search = klass.new
    search.condition(:tags).or(%w(funny stupid))
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Lisa', 'Bart'])
  end

  it "queries arrays AND'd via constructor correctly" do
    search = klass.new(conditions: {tags: {values: ['funny', 'stupid'], and: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Bart'])
  end

  it "queries arrays AND'd via direct assignment correctly" do
    search = klass.new
    search.condition(:tags).and(%w(funny stupid))
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Bart'])
  end

  it "queries NOT via constructor correctly" do
    search = klass.new(conditions: {name: {values: 'Bart', not: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge', 'Lisa'])
  end

  it "queries NOT via direct assignment correctly" do
    search = klass.new
    search.condition(:name).not('Bart')
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge', 'Lisa'])
  end

  it "queries NOT IN via constructor correctly" do
    search = klass.new(conditions: {name: {values: ['Bart', 'Lisa'], not: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge'])
  end

  it "queries NOT IN via direct assignment correctly" do
    search = klass.new
    search.condition(:name).not(['Bart', 'Lisa'])
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge'])
  end

  it "queries gte via constructor correctly" do
    search = klass.new(conditions: {age: {from_eq: 34}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge'])
  end

  it "queries gte via direct assignment correctly" do
    search = klass.new
    search.condition(:age).gte(34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer', 'Marge'])
  end

  it "queries gt via constructor correctly" do
    search = klass.new(conditions: {age: {from: 34}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer'])
  end

  it "queries gt via direct assignment correctly" do
    search = klass.new
    search.condition(:age).gt(34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Homer'])
  end

  it "queries lte via constructor correctly" do
    search = klass.new(conditions: {age: {to_eq: 34}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Lisa', 'Marge'])
  end

  it "queries lte via direct assignment correctly" do
    search = klass.new
    search.condition(:age).lte(34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Lisa', 'Marge'])
  end

  it "queries lt via constructor correctly" do
    search = klass.new(conditions: {age: {to: 34}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Lisa'])
  end

  it "queries lt via direct assignment correctly" do
    search = klass.new
    search.condition(:age).lt(34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Lisa'])
  end

  it 'can apply a transform to range values' do
    klass.class_eval do
      condition :age, range: true, transform: ->(val) {
        val.to_i + 2
      }
    end
    search = klass.new
    search.condition(:age).lt('11')
    expect(search.conditions[:age].to_query).to eq(age: { lt: 13 })
    search.conditions[:age] = nil
    search.condition(:age).lte('11')
    expect(search.conditions[:age].to_query).to eq(age: { lte: 13 })
    search.conditions[:age] = nil
    search.condition(:age).gte('11')
    expect(search.conditions[:age].to_query).to eq(age: { gte: 13 })
    search.conditions[:age] = nil
    search.condition(:age).gt('11')
    expect(search.conditions[:age].to_query).to eq(age: { gt: 13 })
  end

  it "can query with two separate ranges on the same condition" do
    search = klass.new
    search.condition(:age).gt(8)
    search.condition(:age).lte(34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Marge'])
  end

  it "queries WITHIN and including via constructor correctly" do
    search = klass.new
    search.condition(:age).within_eq(10..34)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Marge'])
  end

  it "queries WITHIN and including via direct assignment correctly" do
    search = klass.new(conditions: {age: {from_eq: 10, to_eq: 34}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Marge'])
  end

  it "queries WITHIN via constructor correctly" do
    search = klass.new
    search.condition(:age).within(10..38)
    search.query!

    expect(search.results.map(&:name)).to match_array(['Marge'])
  end

  it "queries WITHIN via direct assignment correctly" do
    search = klass.new(conditions: {age: {from: 10, to: 38}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Marge'])
  end
  describe "#find_in_batches" do
    let(:search) { klass.new(metadata: {sort: [{att: 'name', dir: 'asc'}]}) }

    context "when batch_size < total_results" do
      it "should return results in array of given batch size" do
        results = []
        search.find_in_batches(batch_size: 2) { |r| results << r.map(&:name) }
        expect(results).to match_array([['Bart', 'Homer'], ['Lisa', 'Marge']])
      end
    end

    context "when batch_size == total_results" do
      it "should return all results" do
        results = []
        search.find_in_batches(batch_size: 4) { |r| results << r.map(&:name) }
        expect(results).to match_array([['Bart', 'Homer', 'Lisa', 'Marge']])
      end
    end

    context "when batch_size > total_results" do
      it "should return all results" do
        results = []
        search.find_in_batches(batch_size: 6) { |r| results << r.map(&:name) }
        expect(results).to match_array([['Bart', 'Homer', 'Lisa', 'Marge']])
      end
    end

    context "when no batch_size given" do
      it "should return results with default batch_size=10_000" do
        results = []
        search.find_in_batches { |r| results << r.map(&:name) }
        expect(results).to match_array([['Bart', 'Homer', 'Lisa', 'Marge']])
      end
    end
  end

  it "should prefix via constructor correctly" do
    search = klass.new(conditions: {name: {values: 'ba', prefix: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart'])
  end

  it "should prefix via direct assignment correctly" do
    search = klass.new
    search.condition(:name).starts_with('ba')
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart'])
  end

  it "should support prefix across multiple values" do
    search = klass.new
    search.condition(:name).starts_with(%w(ba li))
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Lisa'])
  end

  it "should support prefix across multiple values ANDed" do
    search = klass.new(conditions: {tags: {values: ['funny', 'stupid'], prefix: true, and: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Homer'])
  end

  it "should support matching text anywhere in the string" do
    search = klass.new
    search.condition(:name).any_text('ar')
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Marge'])
  end

  it "should support matching text anywhere in the string via constructor" do
    search = klass.new(conditions: {name: {values: 'ar', any_text: true}})
    search.query!

    expect(search.results.map(&:name)).to match_array(['Bart', 'Marge'])
  end

  it "should support sorting asc" do
    search = klass.new(metadata: {sort: [{att: 'name', dir: 'asc'}]})
    search.query!
    expect(search.results.map(&:name)).to eq(%w(Bart Homer Lisa Marge))
  end

  it "should support sorting desc" do
    search = klass.new(metadata: {sort: [{att: 'name', dir: 'desc'}]})
    search.query!
    expect(search.results.map(&:name)).to eq(%w(Marge Lisa Homer Bart))
  end

  it "should support sorting asc via direct assignment" do
    search = klass.new.sort(:age)
    search.query!
    expect(search.results.map(&:age)).to eq([8, 10, 34, 38])
  end

  it "should support sorting desc via direct assignment" do
    search = klass.new.sort('-age')
    search.query!
    expect(search.results.map(&:age)).to eq([38, 34, 10, 8])
  end

  it "should support pagination" do
    search = klass.new(metadata: {pagination: {current_page: 1, per_page: 4}})
    search.query!
    expected_name = search.results[1].name
    search = klass.new(metadata: {pagination: {current_page: 2, per_page: 1}})
    search.query!
    expect(search.results.map(&:name)).to eq([expected_name])
  end

  it "should support query-as-you-type autocompletes via direct assignment" do
    search = klass.new
    search.condition(:name).autocomplete('ba')
    search.query!
    expect(search.results.map(&:name)).to eq(['Bart'])
  end

  context "when loading records" do
    let(:search) do
      search = klass.new
      search.metadata.records[:load] = true
      search
    end

    it "should return ActiveRecords from #query!" do
      search.query!
      expect(search.query!.first).to be_a(ActiveRecord::Base)
    end

    it "should preserve sort order" do
      search.query!
      expect(search.records.map(&:id)).to eq(search.results.map(&:id))
    end

    it "should eager load requested includes" do
      animal = Animal.create!(name: 'spot')
      person = Person.first
      person.animals << animal
      search.metadata.records[:includes] = :animals
      search.query!
      [Person, Animal].each(&:delete_all)
      record = search.records.find { |r| r.id == person.id }
      expect(record.animals.first).to eq(animal)
    end
  end

  context "when an autocomplete condition" do
    it "should be able to query via constructor" do
      search = klass.new(conditions: {name: {values: [{id: 1, key: 'Homer', text: 'Just the Label, does not matter'}]}})
      search.query!
      expect(search.results.map(&:name)).to eq(['Homer'])
    end

    it "should be able to query via direct assignment" do
      search = klass.new
      search.condition(:name).starts_with([{id: 1, key: 'ho', text: 'Label, does not matter'}])
      search.query!

      expect(search.results.map(&:name)).to eq(['Homer'])
    end

    context "when a user query" do
      let(:conditions) do
        bart = Person.find_by(name: 'Bart')

        {
          id: {
            values: [
              {id: 'hom', key: 'hom', text: 'hom', user_query: true},
              {id: bart.id, key: bart.id, text: 'Bart'}
            ]
          }
        }
      end

      it "should query the corresponding condition in addition to the autocomplete" do
        search = klass.new conditions: conditions
        search.query!

        expect(search.results.map(&:name)).to match_array(['Homer', 'Bart'])
      end

      # tests dup logic, these conditions should not mutate
      it "should be able to query twice correctly" do
        search = klass.new conditions: conditions
        search.query!

        expect(search.results.map(&:name)).to match_array(['Homer', 'Bart'])

        search.query!
        expect(search.results.map(&:name)).to match_array(['Homer', 'Bart'])
      end

      it "should not conflict with corresponding condition set manually" do
        conditions.merge!({
          _name_prefix: {
            values: [{id: 'ba', key: 'ba', text: 'ba'}]
          }
        })

        search = klass.new conditions: conditions
        search.query!

        # Just Bart since these are ANDed
        expect(search.results.map(&:name)).to match_array(['Bart'])
      end

      context "and there are multiple user queries" do
        before do
          conditions[:tag_ids] = {
            values: [{ id: 'kid', key: 'kid', text: '"kid"', user_query: true }]
          }
        end

        it "should AND the clauses and query correctly" do
          search = klass.new conditions: conditions
          search.query!
          expect(search.results.map(&:name)).to match_array(['Bart'])
        end
      end
    end
  end

  context "when a keywords condition" do
    it "should support keyword queries" do
      klass.class_eval do
        condition :keywords
      end

      search = klass.new(conditions: {keywords: "homer"})
      search.query!
      expect(search.results.map(&:name)).to eq(['Homer'])
    end

    context "that is limited by fields at runtime" do
      before do
        klass.class_eval do
          condition :keywords
        end
      end

      it "should limit the keyword query to those fields" do
        search = klass.new(conditions: {keywords: {values: "homer", fields: [:tags]}})
        search.query!
        expect(search.results.length).to eq(0)

        search = klass.new(conditions: {keywords: {values: "bald", fields: [:tags]}})
        search.query!
        expect(search.results.map(&:name)).to eq(['Homer'])
      end
    end

    context "that is limited by fields on class definition" do
      before do
        klass.class_eval do
          condition :keywords, fields: [:tags]
        end
      end

      it "should limit the keyword query to those fields" do
        search = klass.new(conditions: {keywords: "homer"})
        search.query!
        expect(search.results.length).to eq(0)

        search = klass.new(conditions: {keywords: "bald"})
        search.query!
        expect(search.results.map(&:name)).to eq(['Homer'])
      end
    end
  end

  context "when searching across multiple models" do
    let(:global_search) do
      Class.new(Trample::Search) do
        condition :name
      end
    end

    before do
      global_search.model Person, Animal

      Animal.create!(name: 'MooCow')
      Animal.create!(name: 'Dog')
      Animal.reindex
    end

    it "yields correct results" do
      search = global_search.new
      search.condition(:name).starts_with('m')
      search.query!
      expect(search.results.map(&:name)).to match_array(%w(Marge MooCow))
    end
  end

  context "when faceting" do
    before do
      klass.aggregation :tags, label: 'Taggings' do |f|
        f.force 'special'
        f.force 'FUNNY', label: 'The Funnies'
      end

      klass.aggregation :name
    end

    let(:agg) do
      search = klass.new
      search.agg(:tags)
      search.query!
      search.aggregations.find { |a| a.name == :tags }
    end

    let(:buckets) do
      agg.buckets.inject({}) { |memo, e| memo.merge(e.key.downcase => e.count) }
    end

    it "should raise an error when the agg is not defined on the class" do
      search = klass.new
      expect { search.agg(:age) }.to raise_error(Trample::AggregationNotDefinedError)
    end

    it "should allow multiple aggs to be assigned at once" do
      search = klass.new
      search.agg(:tags, :name)
      search.query!
      expect(search.aggregations.map(&:name)).to match_array([:tags, :name])
    end

    it "should allow agg assignment via constructor (nil buckets)" do
      search = klass.new(aggregations: [{name: 'tags', buckets: nil}])
      search.query!
      expect(search.aggregations.map(&:name)).to match_array([:tags])
    end

    it "should allow agg assignment via constructor (no buckets key)" do
      search = klass.new(aggregations: [{name: 'tags'}])
      search.query!
      expect(search.aggregations.map(&:name)).to match_array([:tags])
    end

    it "should allow agg assignment via constructor (empty buckets)" do
      search = klass.new(aggregations: [{name: 'tags', buckets: []}])
      search.query!
      expect(search.aggregations.map(&:name)).to match_array([:tags])
    end

    it "should assign agg results specified to the search" do
      expect(buckets['funny']).to eq(3)
      expect(buckets['stupid']).to eq(2)
      expect(buckets['smart']).to eq(1)
      expect(buckets['motherly']).to eq(1)
      expect(buckets['bald']).to eq(1)
    end

    it "should assign labels to aggs" do
      expect(agg.label).to eq('Taggings')
    end

    it "should add forced buckets to the ags" do
      expect(buckets['special']).to eq(0)
    end

    it "should force buckets alphabetically by default" do
      expect(agg.buckets.map(&:key)).to eq(%w(bald FUNNY kid motherly smart special stupid))
    end

    it "should not duplicate forced buckets that are returned as part of the query" do
      funny = agg.buckets.select { |b| b.key.downcase == 'funny' }
      expect(funny.length).to eq(1)
      expect(funny.first.count).to_not be_zero
    end

    it "should allow labels on forced buckets" do
      funny = agg.buckets.find { |b| b.key.downcase == 'funny' }
      expect(funny.label).to eq('The Funnies')
    end

    context "when given a special bucket sort" do
      it "should honor procs" do
        klass.aggregation :tags, label: 'Taggings' do |f|
          f.bucket_sort = proc { |a, b| a.key == 'special' ? -1 : 1 }
          f.force 'special'
          f.force 'FUNNY', label: 'The Funnies'
        end

        expect(agg.buckets.map(&:key)[0]).to eq('special')
      end

      it "should honor :count, sorting secondarily by alpha" do
        klass.aggregation :tags, label: 'Taggings' do |f|
          f.bucket_sort = :count
          f.force 'special'
          f.force 'FUNNY', label: 'The Funnies'
        end

        expect(agg.buckets.map(&:key)).to eq(%w(FUNNY kid stupid bald motherly smart special))
      end
    end

    context "when a bucket is selected" do
      context "via constructor" do
        let(:search) do
          search = klass.new aggregations: [{
            name: 'tags',
            buckets: [
              {key: 'funny'},
              {key: 'stupid', selected: true},
              {key: 'smart'},
              {key: 'motherly', selected: true},
              {key: 'bald'}
            ]
          }]
          search.query!
          search
        end

        it "should filter the search to that selection" do
          expect(search.results.map(&:name)).to match_array(%w(Homer Bart Marge))
        end
      end

      context "via direct assignment" do
        let(:search) do
          search = klass.new
          search.agg(tags: ['stupid', 'motherly']).query!
          search
        end

        it "should filter the search to that selection" do
          expect(search.results.map(&:name)).to match_array(%w(Homer Bart Marge))
        end
      end

      context "both direct assignment and constructor for same agg" do
        let(:search) do
          search = klass.new aggregations: [
            {
              name: 'tags',
              buckets: [
                {key: 'funny'},
                {key: 'stupid', selected: true},
                {key: 'smart'},
                {key: 'motherly', selected: true},
                {key: 'bald'}
              ]
            }
          ]
          search.agg(:tags)
          search.query!
          search
        end

        it "should not wipe selections" do
          expect(search.results.map(&:name)).to match_array(%w(Homer Bart Marge))
        end
      end

      context "and the corresponding condition is also set" do
        let(:search) do
          search = klass.new
          search.agg(tags: ['stupid'])
          search.condition(:tags).in(['motherly'])
          search.query!
          search
        end

        it "should use the condition" do
          expect(search.results.map(&:name)).to match_array(%w(Marge))
        end
      end
    end
  end

end
