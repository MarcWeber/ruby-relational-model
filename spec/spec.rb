# encoding: UTF-8
#
# run this test by rspec spec/spec.rb

require_relative "../lib/relational/model.rb"
require_relative "../lib/relational/diff.rb"
require_relative "../lib/relational/ar.rb"
require_relative "../lib/relational/migrate.rb"

require "sqlite3"

include Relational

describe Relational::Diff do
  it "should diff" do
    d = Relational::Diff.new([1,2], [2,3])
    d.both.should eq([LEFT_RIGHT.new(2,2)])
    d.left.should eq([1])
    d.right.should eq([3])
  end
end

describe 'simple use cases should not fail' do

  m = Model.new do |m|

    m.relation(:relation_1) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
      r.enum :enum, :values => [:Yes, :No, :Maybe], :default => :Yes
      r.text :blob_string
      r.binary :blob_string
    end

    m.relation(:relation_2) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
    end

  end

  it "M" do
    m.relations.map {|v| v.name}.should eq([:relation_1, :relation_2])
  end

  m2 = Model.new do |m|
    m.relation(:relation_1) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
      r.text :name1
      r.binary :name2
    end

    m.relation(:relation_3) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
      r.enum :enum, :values => [:Yes, :No, :Maybe], :default => :Yes
      r.text :blob_string
      r.binary :blob_string
    end
  end

  model_diff = m.diff(m2)
  arm = Relational::ActiveRecord::MigrationGenerator.new(model_diff)
  puts arm.changeLines.join("\n")
end

describe "ActiveRecordSqliteMigrations" do

  tmpDir = "tmp"
  begin # prepare
    ActiveRecord::Base.establish_connection(
      :adapter => 'sqlite3',
      :database => "#{tmpDir}/sqlite.db"
    )
    Dir["#{tmpDir}/*"].each do |file|
      File.delete file
    end
  end

  m = Model.new do |m|

    m.relation(:relation_1) do |r|
      r.primary
      r.unique_indexes = [[:enum, :str],[:enum]]
      r.string :str, :nullable => false, :comment => 'foo'
      r.enum :enum, :values => [:Yes, :No, :Maybe], :default => :Yes
      r.text :blob_string
      r.binary :blob_string
    end

    m.relation(:relation_2) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
    end

  end

  m2 = Model.new do |m|
    m.relation(:relation_1) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
      r.text :name1
      r.binary :name2
      r.unique_indexes = [[:str]]
    end

    m.relation(:relation_3) do |r|
      r.primary
      r.string :str, :nullable => false, :comment => 'foo'
      r.enum :enum, :values => [:Yes, :No, :Maybe], :default => :Yes
      r.text :blob_string
      r.binary :blob_string
    end
  end

  Relational::Migrate.new(m, Relational::ActiveRecord::MigrationHelper.new(:force_review => false), tmpDir) \
    .migrate

  Relational::Migrate.new(m2, Relational::ActiveRecord::MigrationHelper.new(:force_review => false), tmpDir) \
    .migrate

  after(:all) do
  end
end
