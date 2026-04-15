class WaflowAgents::BaseService
  private

  def waflow_base_url
    @waflow_base_url ||= begin
      raw = GlobalConfigService.load('WAFLOW_BACKEND_URL', '').to_s.strip
      raw.sub(%r{/+\z}, '')
    end
  end

  def waflow_secret
    @waflow_secret ||= begin
      primary = GlobalConfigService.load('WAFLOW_CHATWOOT_AGENT_SECRET', '').to_s.strip
      if primary.present?
        primary
      else
        secondary = GlobalConfigService.load('CHATWOOT_WAFLOW_AGENT_SECRET', '').to_s.strip
        if secondary.present?
          secondary
        else
          GlobalConfigService.load('CHATWOOT_WAFLOW_BRIDGE_SECRET', '').to_s.strip
        end
      end
    end
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
    Rails.logger.error("[WaflowAgents] Failed to capture exception: #{error.message}")
  end
end
