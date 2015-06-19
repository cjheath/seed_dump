class SeedDump
  module Environment

    def dump_using_environment(env = {})
      Rails.application.eager_load!

      models_env = env['MODEL'] || env['MODELS']
      models = if models_env
                 models_env.split(',')
                           .collect {|x| x.strip.underscore.singularize.camelize.constantize }
               else
                 ActiveRecord::Base.descendants
               end

      models = models.select do |model|
                 (model.to_s != 'ActiveRecord::SchemaMigration') && \
                  model.table_exists? && \
                  model.exists?
               end

      append = env['APPEND'] == 'true'
      batch_size = env['BATCH_SIZE'] ? env['BATCH_SIZE'].to_i : nil
      exclude = env['EXCLUDE'] ? env['EXCLUDE'].split(',').map {|e| e.strip.to_sym} : nil
      file =  env['FILE'] || 'db/seeds.rb'
      import = env['IMPORT'] == 'true'
      limit = env['LIMIT'].to_i if env['LIMIT']

      dumper = SeedDump.new(
	  models,
	  append: append,
	  batch_size: batch_size,
	  exclude: exclude,
	  file: file,
	  import: import,
	  limit: limit
	)
      dumper.dump_all
    end
  end

  def initialize(models, options)
    @models = models
    @options = options
  end

  def dump_all
    @keys = Hash.new{{}}
    @foreign_keys = {}	# Array of foreign key reflections of dependencies per model
    @depends_on = Hash.new([])	# Array of models that are dependencies of each model
    @models.each do |model|
      model.reflections.select do |n,r|
	next unless r.is_a? ActiveRecord::Reflection::BelongsToReflection
	target = ActiveSupport::Inflector.constantize(r.class_name)
	next unless target.exists?
	(@depends_on[model] ||= []) << target
	(@foreign_keys[model] ||= []) << (f = r.foreign_key)
	# puts "#{model.name} depends on #{target} via #{f} (association #{r.name})"
      end
    end

    @dumped = {}
    @to_dump = @models.dup
    until @to_dump.empty? do
      next_model = @to_dump.detect do |model|
	# Choose a model that has not been dumped, but whose dependencies all have:
	!@dumped[model] and
	  !@depends_on[model].detect do |dependency|
	    !(dependency == model) and !@dumped[dependency]
	  end
      end

      # Just choose the next one if there's a dependency cycle.
      next_model = @to_dump.shift unless next_model

      dump_model(next_model, @options)

      @options[:append] = true
      @dumped[next_model] = true
      @to_dump.delete(next_model)
    end
  end

  def dump_model(model, options)
    model = model.limit(options[:limit]) if options[:limit]

    SeedDump.dump(model,
		  append: options[:append],
		  batch_size: options[:batch_size],
		  exclude: options[:exclude],
		  file: options[:file],
		  import: options[:import])
  end
end

