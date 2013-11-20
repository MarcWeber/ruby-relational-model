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
    end

    def migrate
      v_next = 1
      while File.exist? file(v_next, "dump")
        v_next += 1
      end
      puts "v_next #{v_next}"

      latest_model = v_next == 1 \
        ? Relational::Model.new \
        : File.open(file(v_next - 1, "dump"), "rb") { |file| Marshal.load(file) }

      if latest_model != @model
        # looks like we need a new migration, something has changed..
        rb_contents = @migrationHelper.migration_file(v_next, latest_model, @model)
        File.open(file(v_next, "dump"), "wb") { |file| Marshal.dump(@model, file) }
        File.open(file(v_next, "rb"), "wb") { |file| file.write(rb_contents) }
      end

      # now try migrating
      db_version = @migrationHelper.version
      puts "db version is #{db_version} latest: #{v_next}"
      while db_version < v_next
        db_version += 1
        @migrationHelper.migrate(db_version.to_i, file(db_version, "rb"))
        SchemaInfo.create(:version => db_version)
      end
    end

    def file(v, ext)
      File.join(@migration_path, "#{v.to_i}.#{ext}")
    end
  end

end
