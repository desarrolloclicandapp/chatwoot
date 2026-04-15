class WaflowWhatsappTemplates::BaseService
  private

  def waflow_base_url
    @waflow_base_url ||= begin
      raw = GlobalConfigService.load('WAFLOW_BACKEND_URL', '').to_s.strip
      raw.sub(%r{/+\z}, '')
    end
  end

  def waflow_secret
    @waflow_secret ||= GlobalConfigService.load('WAFLOW_CHATWOOT_AGENT_SECRET', '').to_s.strip
  end

  def waflow_configured?
    waflow_base_url.present? && waflow_secret.present?
  end

  def waflow_headers
    {
      'Content-Type' => 'application/json',
      'X-Waflow-Chatwoot-Secret' => waflow_secret
    }
  end

  def parse_json_response(response)
    JSON.parse(response&.body.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def capture_exception(error, account:)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  rescue StandardError
    Rails.logger.error("[WaflowWhatsappTemplates] Failed to capture exception: #{error.message}")
  end
end
