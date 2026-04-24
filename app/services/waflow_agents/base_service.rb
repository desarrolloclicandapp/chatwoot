class WaflowAgents::BaseService
  private

  def waflow_base_urls
    @waflow_base_urls ||= begin
      [
        GlobalConfigService.load('WAFLOW_BACKEND_URLS', ''),
        GlobalConfigService.load('WAFLOW_BACKEND_URL', '')
      ]
        .flat_map { |raw| raw.to_s.split(/[\s,;]+/) }
        .map { |value| value.to_s.strip.sub(%r{/+\z}, '') }
        .reject(&:blank?)
        .uniq
    end
  end

  def waflow_base_url
    waflow_base_urls.first
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
    waflow_base_urls.present? && waflow_secret.present?
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
