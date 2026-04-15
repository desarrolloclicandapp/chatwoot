class WaflowWhatsappTemplates::FetchTemplatesService < WaflowWhatsappTemplates::BaseService
  def initialize(inbox:)
    @inbox = inbox
    @account = inbox.account
  end

  def perform
    unless waflow_configured?
      Rails.logger.error(
        "[WaflowWhatsappTemplates::FetchTemplatesService] bridge_not_configured " \
        "account_id=#{@account.id} inbox_id=#{@inbox.id} has_base_url=#{waflow_base_url.present?} has_secret=#{waflow_secret.present?}"
      )
      return failure_result('WAFLOW_BACKEND_URL o WAFLOW_CHATWOOT_AGENT_SECRET no configurados', 503)
    end

    response = HTTParty.get(
      "#{waflow_base_url}/chatwoot/official-whatsapp/templates",
      headers: waflow_headers,
      query: {
        accountId: @account.id,
        inboxId: @inbox.id
      },
      timeout: 20
    )

    body = parse_json_response(response)

    if response.success?
      templates = Array(body['templates'])
      persist_template_state!(
        templates: templates,
        supported: true,
        metadata: {
          'waflow_official_slot_id' => body['slot_id'],
          'waflow_official_phone_number' => body['slot_phone'],
          'waflow_template_sync_error' => nil
        }
      )
      return {
        success: true,
        templates_count: templates.length
      }
    end

    if [404, 409].include?(response.code.to_i)
      persist_template_state!(
        templates: [],
        supported: false,
        metadata: {
          'waflow_official_slot_id' => nil,
          'waflow_official_phone_number' => nil,
          'waflow_template_sync_error' => body['error'].presence
        }
      )
    end

    Rails.logger.warn(
      "[WaflowWhatsappTemplates::FetchTemplatesService] waflow_sync_failed " \
      "account_id=#{@account.id} inbox_id=#{@inbox.id} status=#{response.code} error=#{body['error'].presence || 'unknown'}"
    )

    failure_result(body['error'].presence || 'No se pudieron sincronizar los templates de Waflow', response.code.to_i)
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowWhatsappTemplates::FetchTemplatesService] #{e.message}")
    failure_result(e.message, 500)
  end

  private

  def failure_result(error, status)
    {
      success: false,
      error: error,
      status: status.presence || 500
    }
  end

  def persist_template_state!(templates:, supported:, metadata: {})
    additional_attributes = (@inbox.channel.additional_attributes || {}).deep_dup
    additional_attributes['message_templates'] = templates
    additional_attributes['waflow_official_template_capable'] = supported
    metadata.each do |key, value|
      additional_attributes[key] = value
    end
    @inbox.channel.update!(additional_attributes: additional_attributes)
  end
end
