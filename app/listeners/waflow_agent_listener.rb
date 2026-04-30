class WaflowAgentListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless should_enqueue_auto_reply?(message)

    Rails.logger.info(
      "[WaflowAgentListener] enqueue auto reply account=#{message.account_id} " \
      "inbox=#{message.inbox_id} conversation=#{message.conversation_id} message=#{message.id}"
    )
    WaflowAgents::AutoReplyJob.perform_later(message.id)
  end

  private

  def should_enqueue_auto_reply?(message)
    return false unless message&.incoming?
    return false if message.private?
    return false if message.activity?
    return false if message.auto_reply_email?

    inbox = message.inbox
    return false unless inbox&.api?

    attributes = waflow_inbox_attributes(inbox)
    return false if new_conversations_only?(attributes['waflow_agent_new_conversations_only']) && previous_customer_message?(message)

    attributes['waflow_default_agent_id'].to_i.positive? &&
      auto_reply_mode?(attributes['waflow_agent_mode'])
  end

  def waflow_inbox_attributes(inbox)
    return {} unless inbox

    inbox_attributes = normalize_attributes(inbox.additional_attributes) if inbox.respond_to?(:additional_attributes)
    channel_attributes = normalize_attributes(inbox.channel&.additional_attributes)

    merged_attributes = channel_attributes.merge((inbox_attributes || {}).except(*waflow_attribute_keys))
    waflow_attribute_keys.each { |key| merged_attributes[key] = waflow_attribute(inbox_attributes, channel_attributes, key) }

    merged_attributes
  end

  def waflow_attribute_keys
    %w[waflow_default_agent_id waflow_agent_mode waflow_agent_new_conversations_only]
  end

  def waflow_attribute(inbox_attributes, channel_attributes, key)
    return channel_attributes[key] if channel_attributes&.key?(key)

    inbox_attributes&.[](key)
  end

  def normalize_attributes(attributes)
    (attributes || {}).to_h.stringify_keys
  end

  def auto_reply_mode?(mode)
    mode.blank? || mode.to_s == 'reply'
  end

  def new_conversations_only?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def previous_customer_message?(message)
    message.conversation.messages
           .where(message_type: :incoming)
           .where(private: false)
           .where.not(id: message.id)
           .exists?
  end
end
