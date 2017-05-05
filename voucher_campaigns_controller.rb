module Admin
  class VoucherCampaignsController < BaseController
    before_action :set_voucher_campaign, only: [:show, :update, :destroy, :toggle_archive, :import_vouchers, :imported_vouchers]
    before_action :set_countries, :set_segments, :set_languages, only: [:create, :update]
    before_action :set_filters, only: [:index, :ids]

    def index

      if @filters && @filters['by_status_in']
        begin
          status = @filters['by_status_in']
          status_filter = status[0].to_sym
          where_status = "(case when (available_at is null or available_at > now()) then 'unavailable'
 when (expired_at is not null and expired_at < now()) then 'expired' else 'available' end )  = ? "
          relation = VoucherCampaign.ransack(@filters).result.where(where_status, status_filter).includes(:countries, :languages, :segments).order(@order + ' ' + @sort)
        rescue
        end
      else
        begin
          relation = VoucherCampaign.ransack(@filters).result.includes(:countries, :languages, :segments).order(@order + ' ' + @sort)
        rescue
          return render json: { errors: INVALID_SEARCH_ERROR }, status: :unprocessable_entity
        end
      end
      begin
        @total_entries = relation.count
        @voucher_campaigns = relation.paginate(page: @page, per_page: @page_limit)
      rescue
        return render json: { errors: INVALID_SEARCH_ERROR }, status: :unprocessable_entity
      end
    end

    def show
    end

    def ids
      order = 'name'
      sort = 'ASC'

      if @filters && @filters['by_status_in']
        begin
          status = @filters['by_status_in']
          status_filter = status[0].to_sym
          where_status = "(case when (available_at is null or available_at > now()) then 'unavailable'
 when (expired_at is not null and expired_at < now()) then 'expired' else 'available' end )  = ? "
          @voucher_campaigns_ids = VoucherCampaign.ransack(@filters).result.where(where_status, status_filter).order(@order + ' ' + @sort)
        rescue
        end
      else
        begin
          @voucher_campaigns_ids = VoucherCampaign.ransack(@filters).result.order(@order + ' ' + @sort)
        rescue
          return render json: { errors: INVALID_SEARCH_ERROR }, status: :unprocessable_entity
        end
      end
    end

    def create
      begin
        @voucher_campaign = VoucherCampaign.new(voucher_campaign_params)
        if @voucher_campaign.save
          if set_slug
            render json: @voucher_campaign, status: 200
          else
            render json: {errors: @voucher_campaign.errors.full_messages}, status: :unprocessable_entity
          end
        else
          render json: { errors: @voucher_campaign.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        render json: {errors: "#{e.message.split(": UPDATE").first}"}, status: :unprocessable_entity
      end
    end

    def toggle_archive
      @voucher_campaign.toggle_archive!
      render :show
    end

    def update
      begin
        if @voucher_campaign.update(voucher_campaign_params)
          if set_slug
            render :show, status: 200
          else
            render json: {errors: @voucher_campaign.errors.full_messages}, status: :unprocessable_entity
          end
        else
          render json: { errors: @voucher_campaign.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        render json: {errors: "#{e.message.split(": UPDATE").first}"}, status: :unprocessable_entity
      end
    end

    def destroy
      if @voucher_campaign.destroy
        render json: { success: true, ts: Time.now.utc }
      else
        render json: { error: @voucher_campaign.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def import_vouchers
      return render json: { errors: "Unable to import vouchers. Allowed .csv only" }, status: :unprocessable_entity unless File.extname(params[:file].tempfile).try(:casecmp,".csv") == 0
      return render json: { errors: "Unable to import vouchers. Please save change in CTA first." }, status: :unprocessable_entity unless "CodeVoucherCampaign" == @voucher_campaign.type

      filename = "voucher_campaign_#{@voucher_campaign.id}/vouchers_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.csv"
      s3_client.upload_file(filename, params[:file].tempfile)
      job_id = VoucherCampaign::ImportVouchers.perform_async(@voucher_campaign.id, filename)
      @voucher_campaign.update_attributes(importing_job_id: job_id, importing_job_result: nil)

      render json: {
        success: true,
        result: I18n.t('vouchers_importer.job_queued'),
        importing_job_status: @voucher_campaign.importing_job_status,
        importing_job_result: @voucher_campaign.importing_job_result,
        importing_job_id: @voucher_campaign.importing_job_id,
        ts: Time.now.utc
      }, status: :ok
    end

    def imported_vouchers
      render json: {
        importing_job_status: @voucher_campaign.importing_job_status,
        importing_job_result: @voucher_campaign.importing_job_result,
        importing_job_id: @voucher_campaign.importing_job_id,
        count: @voucher_campaign.vouchers.count
      }, status: :ok
    end


    def constants
      render json: {
        state_types: VoucherCampaign::STATES_MAP,
        cta_types: VoucherCampaign::TYPE_MAP,
        url_voucher_campaigns: {
          user_info_options: UrlVoucherCampaign::USER_INFO_OPTIONS,
          device_info_options: UrlVoucherCampaign::DEVICE_INFO_OPTIONS
        },
        acceptable_columns: Importer::VoucherCampaignTranslation::ACCEPTABLE_COLUMNS,
        translatable_columns: VoucherCampaign.translated_attribute_names
      }
    end

    def export
      filename = "voucher_campaigns_#{params[:language]}_#{Time.now.to_i}.csv"
      csv_file = Importer::VoucherCampaignTranslation.export_to_csv(params[:language])
      send_data(csv_file, type: 'application/csv', filename: filename, disposition: 'attachment')
    end

    def import
      count = Importer::VoucherCampaignTranslation.import_from_csv(params[:file].tempfile, params[:language])
      render json: { success: true, count: count }
    end

    private

    def set_slug
      slug_not_changed = true
      if @voucher_campaign
        country = country_to_iso_code_3
        country = country.blank? ? "all" : country.downcase
        if @voucher_campaign.slug.blank?
          @voucher_campaign.slug = "#{country}-vouchers-#{@voucher_campaign.id}"
          slug_not_changed = false
        end

        if  @voucher_campaign.detail_slug.blank?
          @voucher_campaign.detail_slug = "#{country}-vouchers-detail-#{@voucher_campaign.id}"
          slug_not_changed = false
        end
      end

      slug_not_changed ||  @voucher_campaign.save

    end

    def country_to_iso_code_3
      begin
        current_country = Country.find_by(id: current_country_id)
        current_country.iso_code_3
      rescue
        nil
      end
    end

    def set_filters
      begin
        @order = get_correct_model_attribute('VoucherCampaign', params[:order_by], 'created_at')
        @sort = get_correct_sort_param(params[:sort_by])
        @page = params[:page].to_i || 1
        @page = 1 if @page == 0
        @filters = params[:q]? JSON.parse(params[:q]) : {}

        if current_country_id
          country_id = Country.find_by(id: current_country_id).id
          @filters.update(country_id_eq: country_id)
        end

        @page_limit = WillPaginate.per_page


        @order = '"' + @order + '"'
        @sort = "DESC NULLS LAST" if @sort.upcase == "DESC"
        @sort = "ASC NULLS FIRST" if @sort.upcase == "ASC"
      rescue
        return render json: { errors: INVALID_SEARCH_ERROR }, status: :unprocessable_entity
      end
    end

    def set_voucher_campaign
      @voucher_campaign = VoucherCampaign.find_by(id: params[:id])
      if !@voucher_campaign.present?
        render json: { errors: INVALID_ID_ERROR }, status: :unprocessable_entity
      end
    end

    def set_segments
      @segments = Segment.where(id: (params[:segment_ids] || []))
    end

    def set_languages
      @languages = Language.where(id: (params[:language_ids] || []))
    end

    def set_countries
      @countries = Country.where(id: (params[:country_ids] || []))
    end

    def voucher_campaign_params
      permitted = params.permit(:tablet_enabled, :action_text_for_package_2, :action_text_2, :action_url_2, :action_package_2, :privilege_card_category_id, :type, :mobile_enabled, :web_enabled, :tv_enabled, :slug, :detail_slug,
                                :order, :action_text, :action_url, :action_package, :action_text_for_package,
                                :image, :detail_image, :expired_at, :available_at, :name, :state, :title,
                                :header, :message, :seo_title_tag, :seo_meta_keywords, :seo_meta_description, :footnote_action_title,
                                :footnote_action_url, seo_meta_keywords: [],
                                translations_attributes: [:id, :locale, :_destroy, :action_text, :title, :header, :message, :action_text_for_package, :seo_title_tag, :seo_meta_keywords, :seo_meta_description, :action_text_2, :action_package_2, :action_text_for_package_2, :footnote_action_title, :image, :detail_image])
      .merge({ countries: @countries, languages: @languages, segments: @segments }.compact)


      permitted.tap do |whitelisted|

        if params[:type]

          attrs = params[:type].constantize::ACCESSOR_ATTRS
          whitelisted[:cta_data] = attrs.inject({}) { |result, attr| result.update(attr => params[attr]) } unless params[:cta_data]

          if params[:type] == 'CodeVoucherCampaign'
            whitelisted[:vouchers_attributes] = params.permit(vouchers_attributes: [:code])[:vouchers_attributes] || {}
          end

        end
      end
    end

    def s3_client
      @s3_client ||= S3Client.new
    end
  end
end
