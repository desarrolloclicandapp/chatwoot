class WaflowWhatsappTemplates::SendTemplateService < WaflowWhatsappTemplates::BaseService
  pattr_initialize [:inbox!, :to!, :template_params!]

  def perform
    return { success: false, error: 'Waflow backend is not configured' } unless waflow_configured?

    response = HTTParty.post(
      "#{waflow_base_url}/chatwoot/official-whatsapp/send-template",
      headers: waflow_headers,
      body: payload.to_json,
      timeout: 25
    )

    body = parse_json_response(response)
    if response.success?
      return {
        success: true,
        message_id: body['message_id'].presence,
        slot_id: body['slot_id'].presence,
        slot_phone: body['slot_phone'].presence
      }
    end

    {
      success: false,
      error: body['error'].presence || 'Official WhatsApp template send failed'
    }
  rescue StandardError => e
    capture_exception(e, account: inbox.account)
    {
      success: false,
      error: e.message
    }
  end

  private

  def payload
    {
      accountId: inbox.account_id,
      inboxId: inbox.id,
      targetPhone: to,
      templateParams: template_params
    }
  end
end
