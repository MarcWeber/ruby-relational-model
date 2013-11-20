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

    class BlobString < Field
      def ar_type; :blob; end
    end

    class BlobBinary < Field
      def ar_type; :blob; end
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
          ls << "  create_table #{relation.name.to_s.inspect}.to_sym, :force => true do |t|"
          relation.fields.each do |field|
            ls << "    t.#{field.ar_create_or_change_name_and_options("")}"
          end
          ls << "  end"
        end
        # change tables
        @md.relations.both.each do |rd|
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
          # TODO indexes
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
            create_table SchemaInfo.table_name do |t|
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
