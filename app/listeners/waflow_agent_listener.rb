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

    attributes = inbox.additional_attributes || {}
    attributes['waflow_default_agent_id'].to_i.positive? &&
      attributes['waflow_agent_mode'].to_s == 'reply'
  end
end
