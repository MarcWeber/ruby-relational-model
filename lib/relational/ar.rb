# encoding: UTF-8

# generate ActiverRecord migrations based on diff

require 'active_record'

module Relational
  module Fields

    class Field
      def ar_type
        raise "override"
      end

      def ar_options
        opts = @opts.clone
        opts.delete(:name)
        opts
      end

      def ar_create_or_change_name_and_options(fst_sep)
        "#{ar_type.to_s}#{fst_sep} #{@opts[:name].to_s.inspect}.to_sym, #{ar_options}"
      end

      def ar_model_fields
        opts = {}
        opts[:null] = nullable
      end
    end

    # you can extend and add your own methods the way you like
    # Will be represented as y/n on databases which don't support types
    class Bool < Field
      def ar_type; :boolean; end
    end

    class Enum < Field
      def ar_type; :boolean; end
    end

    class String < Field
      def ar_type; :string; end
      alias :super_ar_model_fields :ar_model_fields
      def ar_model_fields
        opts = super_ar_model_fields
        opts[:limit] = size
      end
    end

    class Integer < Field
      def ar_type; :integer; end
    end

    # currency like. Should allow 2 digits after ,
    class Price < Field
      def ar_type; :price; end
    end

    class Text < Field
      def ar_type; :text; end
    end

    class Binary < Field
      def ar_type; :binary; end
    end
  end

  class Relation
    def ar_name
      "#{name}s"
    end
  end

  class RelationDiff
    def ar_name
      "#{name}s"
    end
  end

  module ActiveRecord

    class ModelGenerator

      def initialize(model)
        @model = model
      end

      def createmodels(container)
        @model.relations.each do |relation|
          c = Class.new(::ActiveRecord::Base)
          container.const_set(relation.name.capitalize, c)
        end
      end
    end

    class MigrationGenerator
      def initialize(md)
        @md = md.assert_instance_of(ModelDiff)
      end

      def changeLines
        ls = []
        ls << "def change"

        # add tables
        @md.relations.right.each do |relation|
          opts = {}
          # opts[:force] = true

          pk = nil
          case relation.primary_key_fields.length
          when 0
          when 1
            pk = relation.primary_key_fields.first
            # auto_increment
            relation.fieldByName(pk).assert_instance_of(Relational::Fields::Integer)
          else; raise "For ActiveRecord there is only one primary key field supported yet, relation: #{relation.name}" 
          end

          opts[:primary_key] = pk unless pk.nil?
          ls << "  create_table #{relation.ar_name.to_s.inspect}.to_sym, #{opts.inspect} do |t|"
          relation.fields.each do |field|
            # Active record will add the primary key on its own !?
            ls << "    t.#{field.ar_create_or_change_name_and_options("")}" if (pk.nil? || field.name != pk)
          end

          ls << "  end"
          begin # indexes (duplication)
            # add indexes
            relation.indexes.each do |index|
              ls << "    add_index #{relation.ar_name.to_s.inspect}.to_sym, #{index.inspect}"
            end
            # add unique_indexes
            relation.unique_indexes.each do |index|
              ls << "    add_index #{relation.ar_name.to_s.inspect}.to_sym, #{index.inspect}, unique: true"
            end
          end
        end
        # change tables
        @md.relations.both.each do |rd|
          raise "changing primary key field is not supported yet, relation: #{rd.ar_name}" unless rd.primary_key_fields.nil?

          begin # drop indexes
            # drop indexes
            rd.indexes.left.each do |index|
              ls << "    remove_index #{rd.ar_name.to_s.inspect}.to_sym, column: #{index.inspect}"
            end
            # drop unique_indexes
            rd.unique_indexes.left.each do |index|
              ls << "    remove_index #{rd.ar_name.to_s.inspect}.to_sym, unique: true,  column: #{index.inspect}"
            end
          end

          # added fields
          rd.fields.right.each do |field|
            ls << "    add_column #{rd.ar_name.to_s.inspect}.to_sym, :#{field.ar_create_or_change_name_and_options(",")}"
          end
          # dropped fields
          rd.fields.left.each do |field|
            ls << "    remove_column #{rd.ar_name.to_s.inspect}.to_sym, #{field.name.to_s.inspect}.to_sym"
          end
          # changed fields
          rd.fields.both.each do |field|
            ls << "    change_column #{rd.ar_name.to_s.inspect}.to_sym, #{field.right.ar_create_or_change_name_and_options(",")}"
          end

          begin # indexes (duplication)
            # add indexes
            rd.indexes.right.each do |index|
              ls << "    add_index #{rd.ar_name.to_s.inspect}.to_sym, #{index.inspect}"
            end
            # add unique_indexes
            rd.unique_indexes.right.each do |index|
              ls << "    add_index #{rd.ar_name.to_s.inspect}.to_sym, #{index.inspect}, unique: true"
            end
          end
        end

        # drop tables
        @md.relations.left.each do |relation|
          ls << "  drop_table #{relation.ar_name.to_s.inspect}.to_sym"
        end
        ls << "end"
        ls
      end
    end

    # ActiveRecord migrationHelper implementation for migrate.rb
    class MigrationHelper
      def initialize(opts)
        @opts = opts
      end
      def migration_file(version, last_model, new_model)
        change = MigrationGenerator.new(last_model.diff(new_model)).changeLines.map {|v| "  #{v}"}.join("\n")
          forceReviewLine = @opts.fetch(:force_review, true) ? "raise 'Review this file, then remove this line'" : ""
"
#{forceReviewLine}
class Migration#{version} < ActiveRecord::Migration
  #{change}
end
"
      end

      def migrate(version, file)
        load file
        migration = "Migration#{version}".constantize.new
        migration.change
      end

      def version
        $SCHEMA_INFO_DONE ||= false
        # unless SchemaInfo.table_exists?
        unless $SCHEMA_INFO_DONE
          $SCHEMA_INFO_DONE = true
          ::ActiveRecord::Schema.define do
            create_table(SchemaInfo.table_name) do |t|
              t.column :version, :float
            end
          end
          return 0
        end
        SchemaInfo.maximum(:version) || 0
      end
    end

  end
end
