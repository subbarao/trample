$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'trample'
require 'database_cleaner'
require 'active_record'
require 'pry'
require 'pry-byebug'

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

end

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Base.raise_in_transactional_callbacks = true

ActiveRecord::Schema.define(:version => 1) do
  create_table :people do |t|
    t.string :name
    t.text :tags
    t.integer :age
  end
end

class Person < ActiveRecord::Base
  searchkick

  serialize :tags
end
