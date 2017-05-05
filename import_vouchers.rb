class VoucherCampaign::ImportVouchers
  include Sidekiq::Worker
  sidekiq_options queue: :vouchers_importer
  sidekiq_options :retry => false # job will be discarded immediately if failed
  def expiration
    @expiration ||= 2.hours
  end

  def perform(voucher_campaign_id, filename)
    if voucher_campaign = VoucherCampaign.find_by(id: voucher_campaign_id)
      file = s3_client.download_file_to_tempfile(filename, "vouchers_import")

      if result = DataImporter::VoucherImporter.new(voucher_campaign.id).import_csv(file, allow_update: false)
        result_string = format_result(result)
      else
        result_string = I18n.t('vouchers_importer.errors.invalid_csv_header')
      end

      voucher_campaign.update_attributes(importing_job_result: result_string)
    end
  ensure
    if file
      s3_client.delete_file(filename)
      file.unlink if file
    end
  end

  private

  def s3_client
    @s3_client ||= S3Client.new
  end

  def format_result(result)
    result_string = ""
    result_string << "#{result[:created]} voucher(s) created. " if result[:created].to_i > 0
    result_string << "#{result[:updated]} voucher(s) updated. " if result[:updated].to_i > 0
    result_string << "#{result[:invalid]} voucher(s) invalid." if result[:invalid].to_i > 0

    result_string.strip
  end
end
