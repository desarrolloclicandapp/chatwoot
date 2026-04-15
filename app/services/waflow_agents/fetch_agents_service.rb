class WaflowAgents::FetchAgentsService < WaflowAgents::BaseService
  def initialize(account:)
    @account = account
  end

  def perform
    return [] unless waflow_configured?

    response = HTTParty.get(
      "#{waflow_base_url}/chatwoot/workflow-agents",
      headers: waflow_headers,
      query: { accountId: @account.id },
      timeout: 15
    )

    body = parse_json_response(response)
    return [] unless response.success?

    Array(body['payload']).filter_map do |agent|
      id = agent['id'].to_i
      next if id <= 0

      {
        id: id,
        name: agent['name'].presence || "Waflow Agent ##{id}"
      }
    end
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::FetchAgentsService] #{e.message}")
    []
  end
end
