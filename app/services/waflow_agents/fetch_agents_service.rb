class WaflowAgents::FetchAgentsService < WaflowAgents::BaseService
  ACCOUNT_NOT_LINKED_ERROR = 'No existe una subcuenta Waflow vinculada a este accountId'.freeze
  BRIDGE_NOT_FOUND_ERROR = 'Waflow bridge endpoint not found'.freeze

  def initialize(account:)
    @account = account
  end

  def perform
    return [] unless waflow_configured?

    waflow_base_urls.each do |base_url|
      agents = fetch_from_backend(base_url)
      return agents unless agents.nil?
    end

    []
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::FetchAgentsService] #{e.class}: #{e.message}")
    []
  end

  private

  def fetch_from_backend(base_url)
    response = HTTParty.get(
      "#{base_url}/chatwoot/workflow-agents",
      headers: waflow_headers,
      query: { accountId: @account.id },
      timeout: 15
    )

    body = parse_json_response(response)
    unless response.success?
      error = body['error'].presence || body['error_message'].presence || body['message'].presence || "HTTP #{response.code}"
      Rails.logger.warn(
        "[WaflowAgents::FetchAgentsService] account=#{@account.id} backend=#{base_url} " \
        "status=#{response.code} error=#{error}"
      )
      return nil if retryable_backend_miss?(response, error)

      return []
    end

    payload = Array(body['payload'])
    Rails.logger.info(
      "[WaflowAgents::FetchAgentsService] account=#{@account.id} backend=#{base_url} " \
      "status=#{response.code} agents=#{payload.length}"
    )

    payload.filter_map do |agent|
      id = agent['id'].to_i
      next if id <= 0

      {
        id: id,
        name: agent['name'].presence || "Waflow Agent ##{id}"
      }
    end
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::FetchAgentsService] #{e.class}: #{e.message} (backend=#{base_url})")
    nil
  end

  def retryable_backend_miss?(response, error)
    response.code.to_i == 404 && [ACCOUNT_NOT_LINKED_ERROR, BRIDGE_NOT_FOUND_ERROR].include?(error.to_s.strip)
  end
end
