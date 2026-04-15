class Api::V1::Accounts::WaflowAgentsController < Api::V1::Accounts::BaseController
  def index
    payload = WaflowAgents::FetchAgentsService.new(account: Current.account).perform
    render json: { payload: payload }
  end
end
