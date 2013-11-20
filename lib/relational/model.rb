# encoding: UTF-8

require "set"
require_relative "../../../ruby-assertions/lib/mw/assertions.rb"


module Relational

  # Intentionally using simple hash (opts) for Field/Relation configuration so
  # that users can add their own properties

  module Fields

    # base class for types
    class Field
      attr_reader :opts
      def initialize(name, opts = {})
        @opts = opts.clone
        @opts[:name] = name.assert_sym
        @opts[:comment] ||= nil
        @opts[:nullable] ||= false
        # @opts[:default] ||= nil
      end

      def default
        @opts.fetch(:default)
      end

      def name
        @opts.fetch(:name)
      end

      def nullable
        # null is evil, user must force it
        @opts.fetch(:nullable, false)
      end

      def references
        r = @opts[:references]
        return nil if r.nil?
        r.assert_has_key(:relation).assert_has_key(:field)
        r
      end

      def ==(other)
        return false if self.class != other.class
        @opts == other.opts
      end

    end

    # you can extend and add your own methods the way you like
    # Will be represented as y/n on databases which don't support types
    class Bool < Field
    end

    class Enum < Field
      attr_accessor :values
      def initialize(name, opts)
        opts.assert_has_key(:values)
        super
      end

      def values
        @opts.fetch(:values)
      end

      def check
        @opts.include? :values
      end
    end

    class String < Field
      def initialize(name, opts)
        opts[:default] ||= ''
        super
      end

      def size
        # sane default for most use cases such as name, email, zip, ..
        @opts.fetch(:size, 100)
      end
    end

    class Integer < Field
    end

    # currency like. Should allow 2 digits after ,
    class Price < Field
    end

    class BlobString < Field
    end

    class BlobBinary < Field
    end

  end

  class Relation # a table
    attr_reader :fields
    def initialize(name, opts = {})
      @opts = opts.clone
      @opts[:name] = name.assert_sym
      @name = name
      @opts[:fields] ||= []

      # @primaryKey, items of @indexes, @uniqIndexes must respond_to? to to_a
      # which must return the field names to be indexed
      @opts[:primaryKey] ||= nil # eg [:user_id, :age]
      @opts[:indexes] ||= []     # eg [[:abc, :foo], [:bar, :baz]]
      @opts[:uniqIndexes] ||= [] # eg [[:abc, :foo], [:bar, :baz]]
    end
    def name; @opts.fetch(:name); end
    def primaryKey; @opts.fetch(:primaryKey); end
    def indexes; @opts.fetch(:indexes); end
    def uniqIndexes; @opts.fetch(:uniqIndexes); end
    def fields; @opts.fetch(:fields); end

    def fieldByName(name); @fields.detect {|v| v.name =name }; end

    def fieldsHash; Hash[@fields.map {|v| [v.name, v]}]; end

    def ==(other)
      case other
      when Relation
        @fields == other.fields \
        && @name == other.name \
        && @primaryKey == other.primaryKey \
        && @indexes == other.indexes \
        && @uniqIndexes == other.uniqIndexes
      else false
      end
    end

    # add primary key
    def primary
      key = "#{name}_id".to_sym
      fields << Fields::Integer.new(key)
      @opts[:primaryKey] = [key]
    end

    def method_missing(method_sym, *arguments, &block)
      # TODO improve this implementation
      h = Hash.new
      h[:integer] = Fields::Integer
      h[:price] = Fields::Price
      h[:string] = Fields::String
      h[:enum] = Fields::Enum
      h[:blob_string] = Fields::BlobString
      h[:blob_binary] = Fields::BlobBinary
      if h.include? method_sym
        h[method_sym].new(*arguments, &block)
      else
        super
      end
    end

  end

  class Model # contains relations
    attr_reader :relations

    def initialize(&blk)
      @relations = []
      blk.call(self) if blk
    end

    # may return nil
    def relationByName(name); @relations.detect {|v| v.name == name }; end

    def relation(name)
      r = self.relationByName(name)
      if r.nil?
        r = Relation.new(name)
        @relations << r
      end
      yield r
    end

    def ==(other)
      case other
      when Model
        @relations == other.relations
      else false
      end
    end

    def relationHash
      Hash[@relations.map {|v| [v.name, v]}]
    end

  end

  # check implementation
  module Fields
    class Field
      def check(model)
        r = references
        return if r.nil?
        model.relationByName(r[:relation]).assert_not_nil.fieldByName(r[:field]).assert_not_nil
      end
    end
  end

  class Relation
    def checkIndex(type, indexes)
      indexes.each do |index| index.to_a.each {|v| h.assert_has_key(v) } end
    end
    def check
      h = fieldsHash

      # check that index field names exist:
      @primaryKey.to_a.each {|v| h.assert_has_key(v) }
      @indexes.each      do |index| index.to_a.each {|v| h.assert_has_key(v) } end
      @uniqIndexes.each  do |index| index.to_a.each {|v| h.assert_has_key(v) } end

      # check that field names are unique:
      @fields.map {|v| v.name}.assert_no_duplicates("duplicatie fields: ELEMENTS")
      @fields.each do |v| v.check(self) if v.respond_to? :check end
    end
  end

  class Model
    def check
      @relations.map {|v| v.name}.assert_no_duplicates("duplicatie relations found: ELEMENTS")
      @relations.each do |v| v.check(self) end
    end
  end

end
