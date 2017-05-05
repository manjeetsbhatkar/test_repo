class DataImporter::VoucherImporter < DataImporter::CsvImporter
  attr_accessor :voucher_campaign_id

  PERMITTED_ATTRIBUTES = [:code]
  IDENTIFIER = [:voucher_campaign_id, :code]

  def initialize(voucher_campaign_id)
    super Voucher, PERMITTED_ATTRIBUTES, IDENTIFIER
    self.voucher_campaign_id = voucher_campaign_id
    self.required_attributes = [:code]
  end

  private

  def add_voucher_campaign_id(row_params)
    row_params[:voucher_campaign_id] = voucher_campaign_id
  end

  def on_importing_row(row_params)
    super && add_voucher_campaign_id(row_params)
  end
end
