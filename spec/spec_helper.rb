# Copyright:: (c) Autotelik Media Ltd 2016
# Author ::   Tom Statter
# Date ::     Aug 2016
# License::   MIT
#
# Details::   Spec Helper for Active Record Loader
#
#
# We are not setup as a Rails project so need to mimic an active record database setup so
# we have some  AR models to test against. Create an in memory database from scratch.
#
#require 'active_record'
#require 'bundler'
#require 'stringio'
#require 'database_cleaner'
#require 'spree'

#$:.unshift '.'  # 1.9.3 quite strict, '.' must be in load path for relative paths to work from here

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[File.join(File.dirname(__FILE__), "support/**/*.rb")].each { |f| require f }

DatashiftSpreeLibraryBase = File.expand_path( File.join(File.dirname(__FILE__), '..') )

require File.join(DatashiftSpreeLibraryBase, 'lib/datashift_spree')

puts "Running tests with ActiveSupport version : #{Gem.loaded_specs['active_support'].inspect}"

puts "Running tests with Rails version : #{Gem.loaded_specs['rails'].version.version.inspect}"

def run_in(dir )
  puts "RSpec .. running test in path [#{dir}]"
  original_dir = Dir.pwd
  begin
    Dir.chdir dir
    yield
  ensure
    Dir.chdir original_dir
  end
end

RSpec.configure do |config|

  config.before do
    ARGV.replace []
  end

  config.before(:suite) do
    puts "Booting spree rails app - version #{DataShift::SpreeEcom::version}"

    # We are not a Spree project, so we implement a spree application of our own
    if(DataShift::SpreeEcom::is_namespace_version )
      spree_boot
    else
      boot('test_spree_standalone')             # key to YAML db e.g  test_memory, test_mysql
    end

    puts "Testing Spree standalone - version #{DataShift::SpreeEcom::version}"
  end

  config.before(:each) do

    set_spree_class_helpers

    DatabaseCleaner.strategy = :transaction

    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  shared_context 'Populate dictionary ready for Product loading' do

    set_spree_class_helpers

    let(:product_klass) { DataShift::SpreeEcom::get_product_class }

    let(:product_loader) { DataShift::SpreeEcom::ProductLoader.new }

    # %w{Image OptionType OptionValue Property ProductProperty Variant Taxon Taxonomy Zone}

    let(:image_klass) {  DataShift::SpreeEcom::get_spree_class 'Image' }

    @Product_klass = DataShift::SpreeEcom::get_product_class

    #spree_klass_list.each do |k|
    #  instance_variable_set("@#{k}_klass", DataShift::SpreeEcom::get_spree_class(k))
    #end

    config.before(:each) do
      DataShift::Configuration.reset
      DataShift::Exporters::Configuration.reset
      DataShift::Loaders::Configuration.reset
    end

    before do
      begin

        DataShift::ModelMethods::Catalogue.clear
        DataShift::ModelMethods::Manager.clear

      rescue => e
        puts e.inspect
        puts e.backtrace
        raise e
      end
    end
  end


  def capture(stream)
    begin
      stream = stream.to_s
      eval "$#{stream} = StringIO.new"
      yield
      result = eval("$#{stream}").string
    ensure
      eval("$#{stream} = #{stream.upcase}")
    end

    result
  end

  alias :silence :capture

  def rspec_spree_thor_path
    @spec_thor_path ||= File.join( File.dirname(__FILE__), '..', 'lib', 'thor', 'spree')
  end

  def fixtures_path()
    File.expand_path(File.dirname(__FILE__) + '/fixtures')
  end

  def ifixture_file( name )
    File.join(fixtures_path(), name)
  end

  def results_path
    File.join(fixtures_path(), 'results')
  end

  def negative_fixture_path
    File.join(fixtures_path, 'negative')
  end

  def negative_fixture_file( source )
    File.join(negative_fixture_path, source)
  end

  # Return location of an expected results file and ensure tree clean before test
  def result_file( name )
    expect = File.join(results_path, name)

    begin FileUtils.rm(expect); rescue; end

    expect
  end

  def results_clear
    begin FileUtils.rm_rf(results_path); rescue; end

    FileUtils.mkdir(results_path) unless File.exists?(results_path);
  end


  def spree_fixture( source)
    ifixture_file(source)
  end

  def bundler_setup(gemfile)
    ENV['BUNDLE_GEMFILE'] = gemfile

    begin
      Bundler.setup(:default, :development)
    rescue Bundler::BundlerError => e
      $stderr.puts e.message
      $stderr.puts "Run `bundle install` to install missing gems"
      exit e.status_code
    end
  end

  def before_each_spree
    # replaced by proper database cleaner
  end


  def set_logger( name = 'datashift_spree_spec.log')

    require 'logger'
    logdir = File.join(File.dirname(__FILE__), 'log')
    FileUtils.mkdir_p(logdir) unless File.exists?(logdir)
    ActiveRecord::Base.logger = Logger.new( File.join(logdir, name) )
  end


  def db_connect( env = 'development' )
    # Some active record stuff seems to rely on the RAILS_ENV being set ?

    ENV['RAILS_ENV'] = env

    configuration = {}

    database_yml_path = File.join(DataShift::SpreeEcom::spree_sandbox_path, 'config', 'database.yml')

    configuration[:database_configuration] = YAML::load( ERB.new( IO.read(database_yml_path) ).result )
    db = configuration[:database_configuration][ env ]

    set_logger

    puts "Connecting to DB"

    ActiveRecord::Base.establish_connection( db )

    puts "Connected to DB"
  end

  # Datashift is NOT a Rails engine. It can be used in any Ruby project,
  # pulled in by a parent/host application via standard Gemfile
  # 
  # Here we have to hack our way around the fact that datashift is not a Rails/Spree app/engine
  # so that we can ** run our specs ** directly in datashift library
  # i.e without ever having to install datashift in a host application
  #
  # NOTES:
  # => Will chdir into the sandbox to load environment as need to mimic being at root of a rails project
  #    chdir back after environment loaded

  def spree_boot()

    spree_sandbox_app_path = DataShift::SpreeEcom::spree_sandbox_path

    unless(File.exists?(spree_sandbox_app_path))
      puts "Creating new Rails sandbox for Spree : #{spree_sandbox_app_path}"

      DataShift::SpreeEcom::build_sandbox

      original_dir = Dir.pwd

      # TOFIX - this don't work ... but works if run straight after the task
      # maybe the env not right using system ?
      begin
        Dir.chdir DataShift::SpreeEcom::spree_sandbox_path
        puts "Running bundle install"
        system('bundle install')

       # puts "Running rake db:migrate"
        #system('bundle exec rake db:migrate')
      ensure
        Dir.chdir original_dir
      end
    end

    puts "Using Rails sandbox for Spree : #{spree_sandbox_app_path}"

    run_in(spree_sandbox_app_path) {

      puts "Running db_connect from #{Dir.pwd}"

      db_connect

      require 'spree'

      begin
        puts "Booting Spree #{DataShift::SpreeEcom::version} in sandbox"
        load 'config/environment.rb'
        puts "Booted Spree using version #{DataShift::SpreeEcom::version}"
      rescue => e
        #somethign in deface seems to blow up suddenly on 1.1
        puts "Warning - Potential issue initializing Spree sandbox:"
        puts e.backtrace
        puts "#{e.inspect}"
      end
    }

    puts "Booted Spree using version #{DataShift::SpreeEcom::version}"
  end

  def set_spree_class_helpers
    @spree_klass_list  =  %w{Image OptionType OptionValue Property ProductProperty Variant Taxon Taxonomy Zone}

    @Product_klass = DataShift::SpreeEcom::get_product_class

    @spree_klass_list.each do |k|
      instance_variable_set("@#{k}_klass", DataShift::SpreeEcom::get_spree_class(k))
    end
  end

  def self.boot( database_env)

    ActiveRecord::Base.clear_active_connections!()

    unless(DataShift::SpreeEcom::is_namespace_version)

      DataShift::SpreeEcom::load()

      db_connect( database_env )
      @dslog.info "Booting Spree using pre 1.0.0 version"
      boot_pre_1
      @dslog.info "Booted Spree using pre 1.0.0 version"

      migrate_up      # create an sqlite Spree database on the fly
    end
  end

  def self.boot_pre_1

    require 'rake'
    require 'rubygems/package_task'
    require 'thor/group'

    require 'spree_core/preferences/model_hooks'
    #
    # Initialize preference system
    ActiveRecord::Base.class_eval do
      include Spree::Preferences
      include Spree::Preferences::ModelHooks
    end

    gem 'paperclip'
    gem 'nested_set'

    require 'nested_set'
    require 'paperclip'
    require 'acts_as_list'

    CollectiveIdea::Acts::NestedSet::Railtie.extend_active_record
    ActiveRecord::Base.send(:include, Paperclip::Glue)

    gem 'activemerchant'
    require 'active_merchant'
    require 'active_merchant/billing/gateway'

    ActiveRecord::Base.send(:include, ActiveMerchant::Billing)

    require 'scopes'

    # Not sure how Rails manages this seems lots of circular dependencies so
    # keep trying stuff till no more errors

    Dir[lib_root + '/*.rb'].each do |r|
      begin
        require r if File.file?(r)
      rescue => e
      end
    end

    Dir[lib_root + '/**/*.rb'].each do |r|
      begin
        require r if File.file?(r) && ! r.include?('testing')  && ! r.include?('generators')
      rescue => e
      end
    end

    load_models( true )

    Dir[lib_root + '/*.rb'].each do |r|
      begin
        require r if File.file?(r)
      rescue => e
      end
    end

    Dir[lib_root + '/**/*.rb'].each do |r|
      begin
        require r if File.file?(r) && ! r.include?('testing')  && ! r.include?('generators')
      rescue => e
      end
    end

    #  require 'lib/product_filters'

    load_models( true )

  end

  def self.load_models( report_errors = nil )
    puts 'Loading Spree models from', DataShift::SpreeEcom::root
    Dir[DataShift::SpreeEcom::root + '/app/models/**/*.rb'].each {|r|
      begin
        require r if File.file?(r)
      rescue => e
        puts("WARNING failed to load #{r}", e.inspect) if(report_errors == true)
      end
    }
  end

  def self.migrate_up
    ActiveRecord::Migrator.up( File.join(DataShift::SpreeEcom::root, 'db/migrate') )
  end

end
