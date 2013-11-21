# encoding: UTF-8

require "set"
require_relative "../../../ruby-assertions/lib/mw/assertions.rb"


module Relational

  # Intentionally using simple hash (opts) for Field/Relation configuration so
  # that users can add their own properties

  module Fields

    # base class for types
    class Field
      attr_accessor :opts
      def initialize(model, relation, name, opts = {})
        @model = model
        @relation = relation
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

      def check
        raise "use nullable isntead of null" if @opts.include? :null
      end

      def duplicate(relation, name)
        self.class.new(@model, relation, name, @opts.clone)
      end
    end

    # you can extend and add your own methods the way you like
    # Will be represented as y/n on databases which don't support types
    class Boolean < Field
    end

    class Date < Field
    end

    class DateTime < Field
    end

    class Float < Field
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

      alias :super_check :check
      def check
        @opts.include? :values
        super_check
      end
    end

    class String < Field
      def initialize(model, relation, name, opts = {})
        opts[:default] ||= ''
        super
      end

      def size
        # sane default for most use cases such as name, email, zip, ..
        @opts.fetch(:limit, 100)
      end

      alias :super_check :check
      def check
        raise "use size instead of limit" if @opts.include? :limit
        super_check
      end
    end

    class Integer < Field
    end

    # currency like. Should allow 2 digits after ,
    class Price < Field
    end

    # arbitrary length
    class Text < Field
    end
    class Binary < Field
    end

  end

  module Relationships
    class OneToN
      attr_reader :opts
      def initialize(model, opts)
        @model = model
        @opts = opts
        @opts.assert_has_key(:r_one)
        @opts.assert_has_key(:r_n)
      end
      def r_n; @opts.fetch(:r_n); end
      def r_one; @opts.fetch(:r_one); end
      def r_prefix; @opts.fetch(:r_prefix); end

      def fields(relation)
        if relation.name == @r_n
          relation_n = @model.relationByName(r_n)
          # lookup type of primary key fields
          @model.relationByName(r_one).primary_key_fields.map do |field|
            field.duplicate(@model, relation_n, "#{prefix}field.name")
          end
        else
          []
        end
      end

      def relations
        []
      end
    end

    class MToN
      attr_reader :opts

      # block can add additional fields
      def initialize(model, opts, &blk)
        @model = model
        @opts = opts
        @opts[:blk] = blk
        @opts[:relation_name] = "rel_#{opts.fetch(:r_n)}_#{opts.fetch(:r_m)}".to_sym
      end

      def fields(relation)
        if relation.name == @r_n
          relation_n = @model.relationByName(r_n)
          # lookup type of primary key fields
          @model.relationByName(r_one).primary_key_fields.map do |field|
            field.duplicate(@model, relation_n, "#{prefix}field.name")
          end
        else
          []
        end
      end

      def relations
        r = [
        Relation.new(@model, @opts.fetch(:relation_name)) do |r|
           @opts[:blk].call(r) if @opts[:blk]
         end
        ]
      end
    end

    def check
      # relation r_one must exist
      relation_one = @model.relationByName(r_one)
      relation_one.assert_not_nil
      # and have at least one primary key field
      relation_one.primary_key_fields.assert_condition{|v| v.length > 1}

      # relation r_n must exist, too
      @model.relationByName(r_n).assert_not_nil
    end

    # TODO implement more relations
  end

  class Relation # a table
    def initialize(model, name, opts = {})
      @model = model
      @opts = opts.clone
      @opts[:name] = name.assert_sym
      @name = name
      @opts[:fields] ||= []

      # @primary_key_fields, items of @indexes, @unique_indexes must respond_to? to to_a
      # which must return the field names to be indexed
      @opts[:primary_key_fields] ||= [] # eg [:user_id, :age]
      @opts[:indexes] ||= []     # eg [[:abc, :foo], [:bar, :baz]]
      @opts[:unique_indexes] ||= [] # eg [[:abc, :foo], [:bar, :baz]]
    end
    def name; @opts.fetch(:name); end
    def primary_key_fields; @opts.fetch(:primary_key_fields); end
    def indexes; @opts.fetch(:indexes); end
    def unique_indexes; @opts.fetch(:unique_indexes); end
    def unique_indexes=(ui); @opts[:unique_indexes] = ui; end

    # may return fields which are generated on the fly, eg by relations
    def fields; @opts.fetch(:fields); end

    def fieldByName(name); @opts[:fields].detect {|v| v.name == name }; end

    def fieldsHash; Hash[fields.map {|v| [v.name, v]}]; end

    def ==(other)
      case other
      when Relation
        fields == other.fields \
        && name == other.name \
        && primary_key_fields == other.primary_key_fields \
        && indexes == other.indexes \
        && unique_indexes == other.unique_indexes
      else false
      end
    end

    # add primary key
    def primary
      key = "#{name}_id".to_sym
      fields << Fields::Integer.new(@model, self, key)
      @opts[:primary_key_fields] = [key]
    end

    def method_missing(method_sym, *arguments, &block)
      # TODO improve this implementation
      h = Hash.new
      h[:integer] = Fields::Integer
      h[:price] = Fields::Price
      h[:string] = Fields::String
      h[:enum] = Fields::Enum
      h[:binary] = Fields::Binary
      h[:text] = Fields::Text
      h[:date] = Fields::Date
      h[:datetime] = Fields::DateTime
      h[:float] = Fields::Float
      h[:boolean] = Fields::Boolean
      if h.include? method_sym
        @opts[:fields] << h[method_sym].new(@model, @relation, *arguments, &block)
      else
        super
      end
    end

    def parent(*args)
      args.each do |relation_without_s|
        @model.oneToN(:r_one => self.name, :r_n => "#{relation_without_s.to_s}s".to_sym)
      end
    end

  end

  class Model # contains relations
    def initialize(&blk)
      @relations = []
      @relationships = [] # contains OneToN and the like
      blk.call(self) if blk
    end

    def relations
      @relations + (@relationships.map {|v| v.relations}.flatten)
    end

    def oneToN(*arguments)
      @relationships << Relationships::OneToN.new(self, *arguments)
    end

    def mToN(*arguments)
      @relationships << Relationships::MToN.new(self,*arguments)
    end

    # may return nil
    def relationByName(name); @relations.detect {|v| v.name == name }; end

    def relation(name)
      r = self.relationByName(name)
      if r.nil?
        r = Relation.new(self, name)
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
      @primary_key_fields.to_a.each {|v| h.assert_has_key(v) }
      @indexes.each      do |index| index.to_a.each {|v| h.assert_has_key(v) } end
      @unique_indexes.each  do |index| index.to_a.each {|v| h.assert_has_key(v) } end

      # check that field names are uniqueue:
      @fields.map {|v| v.name}.assert_no_duplicates("duplicatie fields: ELEMENTS")
      @fields.each do |v| v.check(self) if v.respond_to? :check end
    end
  end

  class Model
    def check
      # check that relation was not defined twice (best effort)
      rs_opts = @relationships.map {|rs| rs.opts}
      raise "some relation ships have been defined twice" if rs_opts.uniq.length != rs_opts.length

      @relations.map {|v| v.name}.assert_no_duplicates("duplicatie relations found: ELEMENTS")
      @relations.each do |v| v.check(self) end

      @relationships.each do |ship| ship.check end
    end
  end

end
