require 'rails_helper'

RSpec.describe WaflowAgentListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(
      :message,
      message_type: 'incoming',
      account: account,
      inbox: inbox,
      conversation: conversation
    )
  end
  let(:event) { Events::Base.new('message_created', Time.zone.now, message: message) }

  before do
    channel.update!(
      additional_attributes: {
        'waflow_default_agent_id' => 42,
        'waflow_agent_mode' => 'reply'
      }
    )
  end

  describe '#message_created' do
    it 'enqueues auto reply for API inboxes configured in reply mode' do
      expect(WaflowAgents::AutoReplyJob).to receive(:perform_later).with(message.id).once

      listener.message_created(event)
    end

    it 'defaults a missing mode to auto reply' do
      channel.update!(additional_attributes: { 'waflow_default_agent_id' => 42 })

      expect(WaflowAgents::AutoReplyJob).to receive(:perform_later).with(message.id).once

      listener.message_created(event)
    end

    it 'uses the channel Waflow configuration when inbox attributes are already present' do
      inbox.update!(additional_attributes: { 'some_existing_key' => 'value' })

      expect(WaflowAgents::AutoReplyJob).to receive(:perform_later).with(message.id).once

      listener.message_created(event)
    end

    it 'keeps channel Waflow configuration authoritative when inbox has stale agent attributes' do
      channel.update!(
        additional_attributes: {
          'waflow_default_agent_id' => 42,
          'waflow_agent_mode' => 'reply'
        }
      )
      inbox.update_columns(
        additional_attributes: {
          'waflow_default_agent_id' => 99,
          'waflow_agent_mode' => 'reply'
        },
        updated_at: 1.minute.from_now
      )

      expect(WaflowAgents::AutoReplyJob).to receive(:perform_later).with(message.id).once

      listener.message_created(event)
    end

    it 'does not enqueue after the first customer message when configured for new conversations only' do
      channel.update!(
        additional_attributes: {
          'waflow_default_agent_id' => 42,
          'waflow_agent_mode' => 'reply',
          'waflow_agent_new_conversations_only' => true
        }
      )
      create(
        :message,
        message_type: 'incoming',
        account: account,
        inbox: inbox,
        conversation: conversation
      )

      expect(WaflowAgents::AutoReplyJob).not_to receive(:perform_later)

      listener.message_created(event)
    end

    it 'does not enqueue when the inbox is explicitly in suggest mode' do
      channel.update!(
        additional_attributes: {
          'waflow_default_agent_id' => 42,
          'waflow_agent_mode' => 'suggest'
        }
      )

      expect(WaflowAgents::AutoReplyJob).not_to receive(:perform_later)

      listener.message_created(event)
    end
  end
end
