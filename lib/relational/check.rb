# encoding: UTF-8# encoding: UTF-8
module Relational
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
