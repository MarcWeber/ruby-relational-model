# encoding: UTF-8

module Relational

  LEFT_RIGHT = Struct.new(:left, :right) 

  class Diff
    # left, right: array like lists
    # blk: reduce an item to a key for comparison
    #
    # .both  items contained in both, returned as {:left => , :right => }
    # .left  items contained in left  only
    # .right items contained in right only
    attr_reader :left, :right, :both
    def initialize(left, right, &blk)
      left_h = Hash[left.map {|v| [blk.nil? ? v : blk.call(v), v]}]
      right_h = Hash[right.map {|v| [blk.nil? ? v : blk.call(v), v]}]

      both_keys = left_h.keys & right_h.keys
      left_keys = left_h.keys - both_keys
      right_keys = right_h.keys - both_keys

      @left = left_keys.map {|v| left_h[v]}
      @right = right_keys.map {|v| right_h[v]}
      @both = both_keys.map {|v| LEFT_RIGHT.new(left_h[v], right_h[v]) }
    end
  end

  class RelationDiff
    attr_reader :left, :right, :primary_key_fields, :indexes, :unique_indexes, :fields, :name
    def initialize(left, right)
      @left = left
      @right = right

      @name = left.name

      # primary key
      @primary_key_fields = nil
      @primary_key_fields = LEFT_RIGHT.new(left.primary_key_fields, right.primary_key_fields) if left.primary_key_fields != right.primary_key_fields

      # indexes, unique_indexes
      @indexes = Diff.new(left.indexes, right.indexes) {|v| v.inspect}
      @unique_indexes = Diff.new(left.unique_indexes, right.unique_indexes) {|v| v.inspect}

      # fields
      @fields = Diff.new(left.fields, right.fields) {|v| v.name}
      # only keep fields which differ
      @fields.both.select! do |v|
        v.left != v.right
      end
    end
  end

  class ModelDiff

    attr_reader :left, :right, :relations
    def initialize(left, right)
      @left = left
      @right = right
      @relations = Diff.new(left.relations, right.relations) {|v| v.name }
      @relations.both.map! do |lr|
        RelationDiff.new(lr.left, lr.right)
      end
    end
  end

  class Model
    def diff(other)
      ModelDiff.new(self, other)
    end
  end

end
