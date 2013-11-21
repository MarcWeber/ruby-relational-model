# encoding: UTF-8

module Relational

  class SchemaInfo < ::ActiveRecord::Base
  end

  class Migrate
    # migrationHelper must reply_to
    #  migration_file(version, last_model, new_model) returning ruby file contents as string
    #  migrate(version, file) attempting to run migration
    #  version must return current version (thus query the version table)
    def initialize(model, migrationHelper, migration_path)
      @model = model
      @migration_path = migration_path
      @migrationHelper = migrationHelper

      @opts = {}
      case :dump
      when :yaml
        require "yaml"
        @opts[:dump_from_file] = proc {|file| YAML::parse_file(file) }
        @opts[:dump_to_file] = proc {|file, thing| File.open(file, "wb") { |file| Marshal.dump(thing.to_yaml, file) } }
      when :dump
        @opts[:dump_from_file] = proc {|file| File.open(file, "rb") { |f| Marshal.load(f) }}
        @opts[:dump_to_file] = proc {|file, thing| File.open(file, "wb") { |f| Marshal.dump(thing, f) }}
      end
    end

    def migrate
      v_next = 1
      while File.exist? file(v_next, "dump")
        v_next += 1
      end
      puts "v_next #{v_next}"

      latest_model = v_next == 1 \
        ? Relational::Model.new \
        : @opts[:dump_from_file].call(file(v_next - 1, "dump"))

      puts latest_model.inspect

      puts @model.inspect

      if not (latest_model == @model)
        # looks like we need a new migration, something has changed..
        rb_contents = @migrationHelper.migration_file(v_next, latest_model, @model)
        @opts[:dump_to_file].call(file(v_next, "dump"), @model)
        File.open(file(v_next, "rb"), "wb") { |file| file.write(rb_contents) }
      end

      # now try migrating
      db_version = @migrationHelper.version
      puts "db version is #{db_version} latest: #{v_next}"
      db_version += 1
      while db_version < v_next and File.exist? file(db_version, "rb")
        puts ">>>> migrating to #{db_version}"
        @migrationHelper.migrate(db_version.to_i, file(db_version, "rb"))
        SchemaInfo.create(:version => db_version)
        db_version += 1
      end
    end

    def file(v, ext)
      File.join(@migration_path, "#{v.to_i}.#{ext}")
    end
  end

end
