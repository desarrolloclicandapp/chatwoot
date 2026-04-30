require 'rails_helper'

RSpec.describe WaflowAgents::AutoReplyJob do
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
  let(:execute_service) { instance_double(WaflowAgents::ExecuteService) }

  before do
    channel.update!(
      additional_attributes: {
        'waflow_default_agent_id' => 42,
        'waflow_agent_mode' => 'reply'
      }
    )
    allow(WaflowAgents::ExecuteService).to receive(:new).and_return(execute_service)
    allow(execute_service).to receive(:perform)
  end

  it 'uses the high priority queue for customer-facing auto replies' do
    expect(described_class.queue_name).to eq('high')
  end

  it 'executes the configured agent in reply mode' do
    described_class.new.perform(message.id)

    expect(WaflowAgents::ExecuteService).to have_received(:new).with(
      account: message.account,
      conversation: message.conversation,
      rule: nil
    )
    expect(execute_service).to have_received(:perform).with(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )
  end

  it 'defaults a missing mode to auto reply' do
    channel.update!(additional_attributes: { 'waflow_default_agent_id' => 42 })

    described_class.new.perform(message.id)

    expect(execute_service).to have_received(:perform).with(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )
  end

  it 'uses the channel Waflow configuration when inbox attributes are already present' do
    inbox.update!(additional_attributes: { 'some_existing_key' => 'value' })

    described_class.new.perform(message.id)

    expect(execute_service).to have_received(:perform).with(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )
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

    described_class.new.perform(message.id)

    expect(execute_service).to have_received(:perform).with(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )
  end

  it 'skips execution after the first customer message when configured for new conversations only' do
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

    described_class.new.perform(message.id)

    expect(WaflowAgents::ExecuteService).not_to have_received(:new)
  end

  it 'skips execution when the inbox is explicitly in suggest mode' do
    channel.update!(
      additional_attributes: {
        'waflow_default_agent_id' => 42,
        'waflow_agent_mode' => 'suggest'
      }
    )

    described_class.new.perform(message.id)

    expect(WaflowAgents::ExecuteService).not_to have_received(:new)
  end
end
