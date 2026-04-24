class WaflowConversationMigrations::ProxyService < WaflowAgents::BaseService
  DEFAULT_TIMEOUT = 30
  ACCOUNT_NOT_LINKED_ERROR = 'No existe una cuenta Waflow vinculada a este accountId'.freeze
  BRIDGE_NOT_FOUND_ERROR = 'Waflow bridge endpoint not found'.freeze
  BACKEND_CACHE_KEY_PREFIX = 'waflow_conversation_migrations/backend'.freeze
  BACKEND_CACHE_TTL = 10.minutes

  def initialize(account:, conversation:)
    @account = account
    @conversation = conversation
  end

  def options
    request_with_backend_resolution(:get, '/chatwoot/dashboard/migrate-channel/options')
  end

  def migrate(target_slot_id:, resolve_source:)
    safe_target_slot_id = target_slot_id.to_i
    return failure_result('targetSlotId is required', :bad_request) if safe_target_slot_id <= 0

    request_with_backend_resolution(
      :post,
      '/chatwoot/dashboard/migrate-channel/migrate',
      body: {
        targetSlotId: safe_target_slot_id,
        resolveSource: resolve_source == true
      }
    )
  end

  private

  def request_with_backend_resolution(method, path, body: {})
    discovery = resolve_backend_for_account
    return discovery[:error_result] unless discovery[:success]

    response = request_to_backend(method, discovery[:base_url], path, body: body)
    return response unless backend_resolution_retryable?(response)

    reset_backend_resolution!
    clear_cached_backend_base_url

    refreshed_discovery = resolve_backend_for_account(force_refresh: true)
    return refreshed_discovery[:error_result] unless refreshed_discovery[:success]

    request_to_backend(method, refreshed_discovery[:base_url], path, body: body)
  end

  def resolve_backend_for_account(force_refresh: false)
    reset_backend_resolution! if force_refresh
    return @resolved_backend_for_account if defined?(@resolved_backend_for_account)

    unless waflow_configured?
      return @resolved_backend_for_account = {
        success: false,
        error_result: failure_result('Waflow backend is not configured', :service_unavailable)
      }
    end

    cached_base_url = cached_backend_base_url
    if cached_base_url.present?
      cached_probe = probe_backend(cached_base_url)
      case cached_probe[:status]
      when :success
        return @resolved_backend_for_account = { success: true, base_url: cached_base_url }
      when :account_not_found, :bridge_not_found
        clear_cached_backend_base_url
      else
        return @resolved_backend_for_account = {
          success: false,
          error_result: cached_probe[:response]
        }
      end
    end

    account_not_found_responses = []
    bridge_not_found_responses = []
    other_failure_responses = []

    waflow_base_urls.each do |base_url|
      next if base_url == cached_base_url

      probe = probe_backend(base_url)
      case probe[:status]
      when :success
        cache_backend_base_url(base_url)
        return @resolved_backend_for_account = { success: true, base_url: base_url }
      when :account_not_found
        account_not_found_responses << probe[:response]
      when :bridge_not_found
        bridge_not_found_responses << probe[:response]
      else
        other_failure_responses << probe[:response]
      end
    end

    @resolved_backend_for_account = {
      success: false,
      error_result: other_failure_responses.first ||
        bridge_not_found_responses.first ||
        account_not_found_responses.first ||
        failure_result('Waflow backend is not configured', :service_unavailable)
    }
  end

  def probe_backend(base_url)
    response = request_to_backend(:get, base_url, '/chatwoot/account-connections', include_conversation: false)
    status =
      if response[:success]
        :success
      elsif account_not_found_response?(response)
        :account_not_found
      elsif bridge_not_found_response?(response)
        :bridge_not_found
      else
        :failure
      end

    { status: status, response: response }
  end

  def request_to_backend(method, base_url, path, body: {}, include_conversation: true)
    response = HTTParty.public_send(
      method,
      "#{base_url}#{path}",
      **request_options(method, body: body, include_conversation: include_conversation)
    )

    normalize_response(response, base_url)
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowConversationMigrations] #{e.class}: #{e.message} (backend=#{base_url})")
    failure_result(e.message, :internal_server_error).merge(waflow_base_url: base_url)
  end

  def request_options(method, body:, include_conversation:)
    payload = { accountId: @account.id }
    payload[:conversationId] = conversation_identifier if include_conversation

    options = {
      headers: waflow_headers,
      timeout: DEFAULT_TIMEOUT
    }

    if method.to_sym == :get
      options[:query] = payload
    else
      options[:body] = payload.merge(body).to_json
    end

    options
  end

  def conversation_identifier
    @conversation.display_id.presence || @conversation.id
  end

  def normalize_response(response, base_url)
    body = parse_json_response(response).deep_symbolize_keys
    body[:success] = response.success? if body[:success].nil?
    body[:http_status] = response.code.to_i
    body[:waflow_base_url] ||= base_url
    body[:error] ||= fallback_error_message(response, body) unless response.success?
    body
  end

  def fallback_error_message(response, body)
    body[:message].presence ||
      body[:error_message].presence ||
      body[:error].presence ||
      (response.code.to_i == 404 ? BRIDGE_NOT_FOUND_ERROR : "Waflow backend request failed (#{response.code})")
  end

  def account_not_found_response?(response)
    response[:http_status].to_i == 404 && response[:error].to_s.strip == ACCOUNT_NOT_LINKED_ERROR
  end

  def bridge_not_found_response?(response)
    response[:http_status].to_i == 404 && response[:error].to_s.strip == BRIDGE_NOT_FOUND_ERROR
  end

  def backend_resolution_retryable?(response)
    account_not_found_response?(response) || bridge_not_found_response?(response)
  end

  def backend_cache_key
    "#{BACKEND_CACHE_KEY_PREFIX}/#{@account.id}"
  end

  def cached_backend_base_url
    cached = Rails.cache.read(backend_cache_key).to_s.strip
    return nil if cached.blank?
    return cached if waflow_base_urls.include?(cached)

    clear_cached_backend_base_url
    nil
  rescue StandardError => e
    Rails.logger.warn("[WaflowConversationMigrations] failed to read backend cache for account=#{@account.id}: #{e.message}")
    nil
  end

  def cache_backend_base_url(base_url)
    Rails.cache.write(backend_cache_key, base_url, expires_in: BACKEND_CACHE_TTL)
  rescue StandardError => e
    Rails.logger.warn("[WaflowConversationMigrations] failed to write backend cache for account=#{@account.id}: #{e.message}")
  end

  def clear_cached_backend_base_url
    Rails.cache.delete(backend_cache_key)
  rescue StandardError => e
    Rails.logger.warn("[WaflowConversationMigrations] failed to clear backend cache for account=#{@account.id}: #{e.message}")
  end

  def reset_backend_resolution!
    remove_instance_variable(:@resolved_backend_for_account) if defined?(@resolved_backend_for_account)
  end

  def failure_result(message, http_status)
    {
      success: false,
      error: message,
      http_status: Rack::Utils.status_code(http_status)
    }
  end
end
