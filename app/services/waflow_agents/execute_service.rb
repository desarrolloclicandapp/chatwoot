class WaflowAgents::ExecuteService < WaflowAgents::BaseService
  HISTORY_LIMIT = 20
  SUPPORTED_MODES = %w[suggest reply].freeze

  def initialize(account:, conversation:, rule:)
    @account = account
    @conversation = conversation
    @rule = rule
  end

  def perform(agent_id:, mode: 'reply', extra_context: '', trigger_message: nil)
    safe_agent_id = agent_id.to_i
    return failure_result('agent_id is required') if safe_agent_id <= 0
    return failure_result('Waflow backend is not configured') unless waflow_configured?

    normalized_mode = normalize_mode(mode)
    trigger_message = resolve_trigger_message(trigger_message)
    return failure_result('No message available for this conversation', agent_id: safe_agent_id) unless trigger_message
    if @rule.present? && !trigger_message.incoming?
      return failure_result(
        'Waflow Agent automations only support incoming messages',
        agent_id: safe_agent_id
      )
    end

    result = nil
    waflow_base_urls.each do |base_url|
      result = execute_on_backend(
        base_url,
        agent_id: safe_agent_id,
        trigger_message: trigger_message,
        extra_context: extra_context,
        mode: normalized_mode
      )
      break unless result.nil?
    end

    result ||= failure_result('Waflow request failed', agent_id: safe_agent_id).merge(mode: normalized_mode)
    apply_result(result, mode: normalized_mode)
    result
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::ExecuteService] #{e.message}")
    failure_result(e.message, agent_id: safe_agent_id)
  end

  def reset_memory(agent_id:)
    safe_agent_id = agent_id.to_i
    return failure_result('agent_id is required') if safe_agent_id <= 0
    return failure_result('Waflow backend is not configured') unless waflow_configured?

    waflow_base_urls.each do |base_url|
      result = reset_memory_on_backend(base_url, agent_id: safe_agent_id)
      return result unless result.nil?
    end

    failure_result('Waflow reset memory failed', agent_id: safe_agent_id)
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::ExecuteService] #{e.message}")
    failure_result(e.message, agent_id: safe_agent_id)
  end

  private

  def execute_on_backend(base_url, agent_id:, trigger_message:, extra_context:, mode:)
    response = HTTParty.post(
      "#{base_url}/chatwoot/workflow-agents/execute",
      headers: waflow_headers,
      body: build_payload(
        agent_id: agent_id,
        trigger_message: trigger_message,
        extra_context: extra_context
      ).to_json,
      timeout: 45
    )

    body = parse_json_response(response)
    error = body['error_message'].presence || body['error'].presence || 'Waflow request failed'
    if retryable_backend_miss?(response, error)
      Rails.logger.warn(
        "[WaflowAgents::ExecuteService] retrying backend account=#{@account.id} " \
        "conversation=#{@conversation.id} backend=#{base_url} status=#{response.code} error=#{error}"
      )
      return nil
    end

    Rails.logger.info(
      "[WaflowAgents::ExecuteService] backend=#{base_url} account=#{@account.id} " \
      "conversation=#{@conversation.id} status=#{response.code}"
    )
    normalize_result(response, body, agent_id).merge(mode: mode)
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error(
      "[WaflowAgents::ExecuteService] backend=#{base_url} account=#{@account.id} " \
      "conversation=#{@conversation.id} error=#{e.message}"
    )
    nil
  end

  def reset_memory_on_backend(base_url, agent_id:)
    response = HTTParty.post(
      "#{base_url}/chatwoot/workflow-agents/reset-memory",
      headers: waflow_headers,
      body: build_reset_memory_payload(agent_id: agent_id).to_json,
      timeout: 30
    )

    body = parse_json_response(response)
    error = body['error'].presence || body['error_message'].presence || 'Waflow reset memory failed'
    if retryable_backend_miss?(response, error)
      Rails.logger.warn(
        "[WaflowAgents::ExecuteService] retrying reset backend account=#{@account.id} " \
        "conversation=#{@conversation.id} backend=#{base_url} status=#{response.code} error=#{error}"
      )
      return nil
    end

    unless response.success? && body['success'] == true
      return failure_result(error, agent_id: agent_id)
    end

    {
      success: true,
      status: 'completed',
      agent_id: agent_id,
      deleted_count: body['deleted_count'].to_i,
      memory_key: body['memory_key'].presence || default_memory_key,
      error_message: nil
    }
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error(
      "[WaflowAgents::ExecuteService] reset backend=#{base_url} account=#{@account.id} " \
      "conversation=#{@conversation.id} error=#{e.message}"
    )
    nil
  end

  def build_payload(agent_id:, trigger_message:, extra_context:)
    {
      accountId: @account.id,
      agentId: agent_id,
      conversationId: @conversation.id,
      contactId: @conversation.contact_id,
      contactName: @conversation.contact&.name,
      phone: @conversation.contact&.phone_number,
      email: @conversation.contact&.email,
      inboxId: @conversation.inbox_id,
      incomingMessage: trigger_message.content_for_llm.to_s,
      channel: normalized_channel,
      memoryKey: default_memory_key,
      extraContext: extra_context.to_s,
      messageHistory: recent_message_history
    }
  end

  def build_reset_memory_payload(agent_id:)
    {
      accountId: @account.id,
      agentId: agent_id,
      conversationId: @conversation.id,
      contactId: @conversation.contact_id,
      phone: @conversation.contact&.phone_number,
      memoryKey: default_memory_key
    }
  end

  def normalize_result(response, body, agent_id)
    if !response.success?
      return failure_result(
        body['error_message'].presence || body['error'].presence || 'Waflow request failed',
        agent_id: agent_id
      )
    end

    {
      success: body['success'] == true,
      run_id: body['run_id'],
      status: body['status'].presence || (body['success'] == true ? 'completed' : 'error'),
      reply_text: body['reply_text'].to_s,
      summary: body['summary'].to_s,
      intent: body['intent'].to_s,
      should_handoff: body['should_handoff'] == true,
      confidence: body['confidence'],
      add_tags: normalize_tags(body['add_tags']),
      remove_tags: normalize_tags(body['remove_tags']),
      tags_added: normalize_tags(body['tags_added']),
      tags_removed: normalize_tags(body['tags_removed']),
      crm_actions_error: body['crm_actions_error'],
      error_message: body['error_message'],
      agent_id: agent_id
    }
  end

  def apply_result(result, mode:)
    return unless result[:success]
    return unless mode == 'reply'

    send_reply_text(result[:reply_text])
    apply_labels(result[:add_tags], result[:remove_tags])
    @conversation.reload.bot_handoff! if result[:should_handoff]
  end

  def send_reply_text(reply_text)
    return if reply_text.blank?
    return if conversation_a_tweet?

    content_attributes = { waflow_agent: true }
    content_attributes[:automation_rule_id] = @rule.id if @rule&.id.present?

    params = {
      content: reply_text,
      private: false,
      content_attributes: content_attributes
    }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def apply_labels(add_tags, remove_tags)
    safe_add_tags = normalize_tags(add_tags)
    safe_remove_tags = normalize_tags(remove_tags)

    @conversation.reload.add_labels(safe_add_tags) if safe_add_tags.any?
    return if safe_remove_tags.empty?

    next_labels = @conversation.label_list - safe_remove_tags
    @conversation.update!(label_list: next_labels)
  end

  def normalize_tags(tags)
    Array(tags).filter_map do |tag|
      value = tag.to_s.strip
      value.presence
    end.uniq.first(20)
  end

  def recent_message_history
    @conversation.messages
                 .chat
                 .reorder(created_at: :desc)
                 .limit(HISTORY_LIMIT)
                 .to_a
                 .reverse
                 .filter_map do |message|
      text = message.content_for_llm.to_s.strip
      next if text.blank?

      {
        role: message.incoming? ? 'user' : 'assistant',
        channel: normalized_channel,
        text: text,
        created_at: message.created_at&.iso8601
      }
    end
  end

  def resolve_trigger_message(explicit_message = nil)
    return explicit_message if explicit_message.present?
    return latest_chat_message if @rule.present?

    latest_incoming_chat_message
  end

  def latest_chat_message
    @conversation.messages
                 .chat
                 .reorder(created_at: :desc)
                 .first
  end

  def latest_incoming_chat_message
    @conversation.messages
                 .chat
                 .where(message_type: :incoming)
                 .reorder(created_at: :desc)
                 .first
  end

  def normalized_channel
    inbox = @conversation.inbox
    return 'unknown' unless inbox
    return 'instagram' if inbox.instagram? || inbox.instagram_direct?
    return 'facebook' if inbox.facebook?
    return 'email' if inbox.email?
    return 'whatsapp' if inbox.whatsapp? || inbox.twilio_whatsapp?
    return 'sms' if inbox.sms? || inbox.twilio?
    return 'telegram' if inbox.telegram?
    return 'tiktok' if inbox.tiktok?
    return 'webchat' if inbox.web_widget?
    return 'api' if inbox.api?

    inbox.channel_type.to_s.demodulize.underscore.presence || 'unknown'
  end

  def default_memory_key
    "chatwoot:#{@account.id}:conversation:#{@conversation.id}"
  end

  def normalize_mode(mode)
    safe_mode = mode.to_s.strip
    return safe_mode if SUPPORTED_MODES.include?(safe_mode)

    'reply'
  end

  def conversation_a_tweet?
    @conversation.additional_attributes.present? &&
      @conversation.additional_attributes['type'] == 'tweet'
  end

  def failure_result(message, agent_id: nil)
    {
      success: false,
      run_id: nil,
      status: 'error',
      reply_text: '',
      summary: '',
      intent: 'error',
      should_handoff: false,
      confidence: 0,
      add_tags: [],
      remove_tags: [],
      tags_added: [],
      tags_removed: [],
      crm_actions_error: nil,
      error_message: message,
      agent_id: agent_id,
      deleted_count: 0,
      memory_key: default_memory_key
    }
  end
end
