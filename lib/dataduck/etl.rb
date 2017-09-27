require_relative 'redshift_destination'

module DataDuck
  class ETL
    class << self
      attr_accessor :destinations
    end

    def self.destination(destination_name)
      self.destinations ||= []
      self.destinations << DataDuck::Destination.destination(destination_name)
    end

    attr_accessor :destinations
    attr_accessor :tables

    def initialize(options = {})
      self.class.destinations ||= []
      @tables = options[:tables] || []
      @destinations = options[:destinations] || []

      @autoload_tables = options[:autoload_tables].nil? ? true : options[:autoload_tables]
      if @autoload_tables
        Dir[DataDuck.project_root + "/src/tables/*.rb"].each do |file|
          table_name_underscores = file.split("/").last.gsub(".rb", "")
          table_name_camelized = DataDuck::Util.underscore_to_camelcase(table_name_underscores)
          require file
          table_class = Object.const_get(table_name_camelized)
          if table_class <= DataDuck::Table && table_class.new.include_with_all?
            @tables << table_class
          end
        end
      end
    end

    def process!
      Logs.info("Processing ETL on pid #{ Process.pid }...")

      destinations_to_use = []
      destinations_to_use = destinations_to_use.concat(self.class.destinations)
      destinations_to_use = destinations_to_use.concat(self.destinations)
      destinations_to_use.uniq!
      if destinations_to_use.length == 0
        destinations_to_use << DataDuck::Destination.only_destination
      end

      errored_tables = []
      redshift = destinations_to_use[0]

      @tables.each do |table_or_class|
        table = table_or_class.kind_of?(DataDuck::Table) ? table_or_class : table_or_class.new
        Logs.info("Processing table '#{ table.name }'...")
        begin
          last_row = redshift.query("INSERT INTO etl_event_log (name, event, timestamp_start) VALUES ('#{ table.name }', 'load_table', CURRENT_TIMESTAMP); SELECT id, timestamp_start FROM etl_event_log WHERE name = '#{ table.name }' ORDER BY id DESC LIMIT 1")[0] # Added to gem per BI-560
	        table.etl!(destinations_to_use)
	        redshift.query("UPDATE etl_event_log SET timestamp_end = CURRENT_TIMESTAMP, runtime_in_s = EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - '#{ last_row[:timestamp_start] }')) WHERE id = #{ last_row[:id] }") # Added to gem per BI-560
        rescue Exception => err
          Logs.error("Error while processing table '#{ table.name }': #{ err.to_s }\n#{ err.backtrace.join("\n") }")
          errored_tables << table
        end
      end

      Logs.info("Finished ETL processing for pid #{ Process.pid }, #{ @tables.length - errored_tables.length } succeeded, #{ errored_tables.length } failed")
      if errored_tables.length > 0
        Logs.info("The following tables encountered errors: '#{ errored_tables.map(&:name).join("', '") }'")
      end
    end
  end
end