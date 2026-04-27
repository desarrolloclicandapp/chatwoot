class WaflowAgentListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless should_enqueue_auto_reply?(message)

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

    attributes = inbox_additional_attributes(inbox)
    attributes['waflow_default_agent_id'].to_i.positive? &&
      auto_reply_mode?(attributes['waflow_agent_mode'])
  end

  def inbox_additional_attributes(inbox)
    return {} unless inbox

    attributes = inbox.additional_attributes if inbox.respond_to?(:additional_attributes)
    return attributes if attributes.present?

    inbox.channel&.additional_attributes || {}
  end

  def auto_reply_mode?(mode)
    mode.blank? || mode.to_s == 'reply'
  end
end
