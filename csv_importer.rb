require 'csv'

class DataImporter::CsvImporter
  attr_accessor :permitted_attributes, :klass, :identifiers, :required_attributes, :verbose, :allow_translations

  CSV_OPTIONS = { headers: true, col_sep: ",", encoding: 'bom|utf-8' }

  REQUIRED_ATTRIBUTES =  []
  PERMITTED_ATTRIBUTES = []
  IDENTIFY_ATTRIBUTES =  []

  def initialize(klass, attributes = PERMITTED_ATTRIBUTES, identifiers = IDENTIFY_ATTRIBUTES)
    self.klass = klass
    self.permitted_attributes = attributes
    self.identifiers = identifiers
    self.required_attributes = identifiers
    self.allow_translations = klass.new.respond_to?(:translation_options)
  end

  def import_csv(file_name, allow_update = true, locale = Language.default.iso_code_2)
    return nil unless valid_headers?(file_name)

    @allow_update = allow_update
    @records = []
    result = read_and_import(file_name, locale)
    klass.import @records
    result
  end

  private

  def read_and_import(file_name, locale = Language.default.iso_code_2)
    result = { created: 0, updated: 0, invalid: 0 }
    CSV.foreach(file_name, CSV_OPTIONS) do |row|
      status = import_row(row, locale)
      result[status] += 1
      if verbose && status == :invalid
        Rails.logger.error "Unable to import row: #{row}"
        Rails.logger.error "#{@messages}\n\n"
      end
    end
    result
  end

  def import_row(row, locale = Language.default.iso_code_2)
    row_params = Hash[row.map { |k, v| [k.is_a?(Symbol) ? k : k.to_s.strip, v.try(:strip)] }].symbolize_keys.slice(*permitted_attributes)
    if on_importing_row(row_params)
      row_params.update(locale: locale) if allow_translations
      if identifiers.present? && record = klass.find_by(row_params.slice(*identifiers))
        update_record(record, row_params)
      else
        create_record(row_params)
      end
    else
      :invalid
    end
  end

  def update_record(record, row_params)
    if @allow_update
      if row_params.except(*identifiers).empty? || record.update_attributes(row_params)
        :updated
      else
        @messages = record.errors.full_messages
        :invalid
      end
    else
      @messages = ['Update is disabled']
      :invalid
    end
  end

  def create_record(row_params)
    record = klass.new(row_params)
    if record.valid?
      @records << record
      :created
    else
      @messages = record.errors.full_messages
      :invalid
    end
  end

  def on_importing_row(row_params)
    true
  end

  def valid_headers?(file_name)
    headers = File.open(file_name, &:readline).strip.split(",").map(&:strip).map(&:to_sym)
    required_attributes.all? { |column_name| headers.include?(column_name) }
  end
end
