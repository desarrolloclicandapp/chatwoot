class WaflowAgents::AutoReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message
    return unless eligible_message?(message)

    inbox = message.inbox
    attributes = inbox_additional_attributes(inbox)
    agent_id = attributes['waflow_default_agent_id'].to_i
    return if agent_id <= 0

    WaflowAgents::ExecuteService.new(
      account: message.account,
      conversation: message.conversation,
      rule: nil
    ).perform(
      agent_id: agent_id,
      mode: 'reply',
      trigger_message: message
    )
  rescue StandardError => e
    Rails.logger.error("[WaflowAgents::AutoReplyJob] message_id=#{message_id} error=#{e.message}")
  end

  private

  def eligible_message?(message)
    return false unless message.incoming?
    return false if message.private?
    return false if message.activity?
    return false if message.auto_reply_email?

    inbox = message.inbox
    return false unless inbox&.api?

    attributes = inbox_additional_attributes(inbox)
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
