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
