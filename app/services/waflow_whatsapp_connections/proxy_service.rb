class WaflowWhatsappConnections::ProxyService < WaflowWhatsappConnections::BaseService
  DEFAULT_TIMEOUT = 30

  def initialize(account:)
    @account = account
  end

  def list
    request(:get, '/chatwoot/account-connections')
  end

  def qr(slot_id:)
    request(:get, "/chatwoot/account-connections/#{slot_id}/qr")
  end

  def start(slot_id:)
    request(:post, "/chatwoot/account-connections/#{slot_id}/start")
  end

  def reconnect(slot_id:)
    request(:post, "/chatwoot/account-connections/#{slot_id}/reconnect")
  end

  def pause(slot_id:)
    request(:post, "/chatwoot/account-connections/#{slot_id}/pause")
  end

  def disconnect(slot_id:)
    request(:delete, "/chatwoot/account-connections/#{slot_id}/disconnect")
  end

  private

  def request(method, path)
    return failure_result('Waflow backend is not configured', :service_unavailable) unless waflow_configured?

    response = HTTParty.public_send(
      method,
      "#{waflow_base_url}#{path}",
      **request_options(method)
    )

    normalize_response(response)
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowWhatsappConnections] #{e.message}")
    failure_result(e.message, :internal_server_error)
  end

  def request_options(method)
    options = {
      headers: waflow_headers,
      timeout: DEFAULT_TIMEOUT
    }

    if method.to_sym == :get
      options[:query] = { accountId: @account.id }
    else
      options[:body] = { accountId: @account.id }.to_json
    end

    options
  end

  def normalize_response(response)
    body = parse_json_response(response).deep_symbolize_keys
    body[:success] = response.success? if body[:success].nil?
    body[:http_status] = response.code.to_i
    body[:error] ||= fallback_error_message(response, body) unless response.success?
    body
  end

  def fallback_error_message(response, body)
    body[:message].presence ||
      body[:error_message].presence ||
      body[:error].presence ||
      (response.code.to_i == 404 ? 'Waflow bridge endpoint not found' : "Waflow backend request failed (#{response.code})")
  end

  def failure_result(message, http_status)
    {
      success: false,
      error: message,
      http_status: Rack::Utils.status_code(http_status)
    }
  end
end
