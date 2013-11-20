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
        "#{ar_type.to_s}#{fst_sep} #{name.to_s.inspect}.to_sym, #{ar_options}"
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

  module ActiveRecord

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
          ls << "  create_table #{relation.name.to_s.inspect}.to_sym, #{opts.inspect} do |t|"
          relation.fields.each do |field|
            # Active record will add the primary key on its own !?
            ls << "    t.#{field.ar_create_or_change_name_and_options("")}" if (pk.nil? || field.name != pk)
          end

          ls << "  end"
          begin # indexes (duplication)
            # add indexes
            relation.indexes.each do |index|
              ls << "    add_index #{relation.name.to_s.inspect}.to_sym, #{index.inspect}"
            end
            # add unique_indexes
            relation.unique_indexes.each do |index|
              ls << "    add_index #{relation.name.to_s.inspect}.to_sym, #{index.inspect}, unique: true"
            end
          end
        end
        # change tables
        @md.relations.both.each do |rd|
          raise "changing primary key field is not supported yet, relation: #{rd.name}" unless rd.primary_key_fields.nil?

          begin # drop indexes
            # drop indexes
            rd.indexes.left.each do |index|
              ls << "    remove_index #{rd.name.to_s.inspect}.to_sym, column: #{index.inspect}"
            end
            # drop unique_indexes
            rd.unique_indexes.left.each do |index|
              ls << "    remove_index #{rd.name.to_s.inspect}.to_sym, unique: true,  column: #{index.inspect}"
            end
          end

          dropped_fields = []
          # added fields
          rd.fields.right do |field|
            ls << "    create_column #{rd.name.to_s.inspect}.to_sym, #{field.ar_create_or_change_name_and_options(",")}"
          end
          # dropped fields
          rd.fields.left do |field|
            ls << "    drop_column #{rd.name.to_s.inspect}.to_sym, #{rd.name.to_s.inspect}.to_sym"
          end
          # changed fields
          rd.fields.both do |field|
            ls << "    change_column #{rd.name.to_s.inspect}.to_sym, #{field.right.ar_create_or_change_name_and_options(",")}"
          end

          begin # indexes (duplication)
            # add indexes
            rd.indexes.right.each do |index|
              ls << "    add_index #{rd.name.to_s.inspect}.to_sym, #{index.inspect}"
            end
            # add unique_indexes
            rd.unique_indexes.right.each do |index|
              ls << "    add_index #{rd.name.to_s.inspect}.to_sym, #{index.inspect}, unique: true"
            end
          end
        end

        # drop tables
        @md.relations.left.each do |relation|
          ls << "  drop_table #{relation.name.to_s.inspect}.to_sym"
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
