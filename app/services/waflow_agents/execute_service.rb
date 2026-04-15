class WaflowAgents::ExecuteService < WaflowAgents::BaseService
  HISTORY_LIMIT = 20

  def initialize(account:, conversation:, rule:)
    @account = account
    @conversation = conversation
    @rule = rule
  end

  def perform(agent_id:)
    safe_agent_id = agent_id.to_i
    return failure_result('agent_id is required') if safe_agent_id <= 0
    return failure_result('Waflow backend is not configured') unless waflow_configured?

    trigger_message = latest_chat_message
    return failure_result('No message available for this conversation', agent_id: safe_agent_id) unless trigger_message
    unless trigger_message.incoming?
      return failure_result(
        'Waflow Agent automations only support incoming messages',
        agent_id: safe_agent_id
      )
    end

    response = HTTParty.post(
      "#{waflow_base_url}/chatwoot/workflow-agents/execute",
      headers: waflow_headers,
      body: build_payload(agent_id: safe_agent_id, trigger_message: trigger_message).to_json,
      timeout: 45
    )

    body = parse_json_response(response)
    result = normalize_result(response, body, safe_agent_id)
    apply_result(result)
    result
  rescue StandardError => e
    capture_exception(e, account: @account)
    Rails.logger.error("[WaflowAgents::ExecuteService] #{e.message}")
    failure_result(e.message, agent_id: safe_agent_id)
  end

  private

  def build_payload(agent_id:, trigger_message:)
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
      memoryKey: "chatwoot:#{@account.id}:conversation:#{@conversation.id}",
      messageHistory: recent_message_history
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

  def apply_result(result)
    send_reply_text(result[:reply_text])
    apply_labels(result[:add_tags], result[:remove_tags])
    @conversation.reload.bot_handoff! if result[:should_handoff]
  end

  def send_reply_text(reply_text)
    return if reply_text.blank?
    return if conversation_a_tweet?

    params = {
      content: reply_text,
      private: false,
      content_attributes: {
        automation_rule_id: @rule.id,
        waflow_agent: true
      }
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

  def latest_chat_message
    @conversation.messages
                 .chat
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
      agent_id: agent_id
    }
  end
end
