require 'rails_helper'

RSpec.describe WaflowAgents::ExecuteService do
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
      conversation: conversation,
      content: 'Me pasas la lista de precios'
    )
  end

  before do
    allow(GlobalConfigService).to receive(:load) do |key, default|
      case key
      when 'WAFLOW_BACKEND_URLS'
        'https://old-waflow.test https://active-waflow.test'
      when 'WAFLOW_BACKEND_URL'
        ''
      when 'WAFLOW_CHATWOOT_AGENT_SECRET'
        'secret'
      else
        default
      end
    end
  end

  it 'retries the next Waflow backend when the first one is not linked to the Chatwoot account' do
    missing_backend_response = instance_double(
      HTTParty::Response,
      success?: false,
      code: 404,
      body: { error: 'No existe una subcuenta Waflow vinculada a este accountId' }.to_json
    )
    success_response = instance_double(
      HTTParty::Response,
      success?: true,
      code: 200,
      body: {
        success: true,
        status: 'completed',
        reply_text: '',
        run_id: 'run_123'
      }.to_json
    )
    expect(HTTParty).to receive(:post).with(
      'https://old-waflow.test/chatwoot/workflow-agents/execute',
      any_args
    ).ordered.and_return(missing_backend_response)
    expect(HTTParty).to receive(:post).with(
      'https://active-waflow.test/chatwoot/workflow-agents/execute',
      any_args
    ).ordered.and_return(success_response)

    result = described_class.new(account: account, conversation: conversation, rule: nil).perform(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )

    expect(result[:success]).to be true
  end

  it 'normalizes backend tags to visible Chatwoot labels and ignores legacy encoded labels' do
    success_response = instance_double(
      HTTParty::Response,
      success?: true,
      code: 200,
      body: {
        success: true,
        status: 'completed',
        reply_text: '',
        run_id: 'run_123',
        add_tags: ['Cliente Activo', 'nuevo cliente', 'waflow_enc_yw5vdghlcibkz']
      }.to_json
    )
    allow(HTTParty).to receive(:post).and_return(success_response)

    result = described_class.new(account: account, conversation: conversation, rule: nil).perform(
      agent_id: 42,
      mode: 'reply',
      trigger_message: message
    )

    expect(result[:add_tags]).to contain_exactly('cliente_activo', 'nuevo_cliente')
    expect(conversation.reload.label_list).to contain_exactly('cliente_activo', 'nuevo_cliente')
  end

  it 'suppresses repeated closing replies without resolving the conversation' do
    success_response = instance_double(
      HTTParty::Response,
      success?: true,
      code: 200,
      body: {
        success: true,
        status: 'completed',
        reply_text: 'De nada, quedo atento.',
        run_id: 'run_123',
        suppress_agent_reply: true,
        suppress_reason: 'closing_thanks'
      }.to_json
    )
    allow(HTTParty).to receive(:post).and_return(success_response)

    expect do
      described_class.new(account: account, conversation: conversation, rule: nil).perform(
        agent_id: 42,
        mode: 'reply',
        trigger_message: message
      )
    end.not_to change { conversation.messages.outgoing.count }

    expect(conversation.reload.status).to eq('open')
  end
end
