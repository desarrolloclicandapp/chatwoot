class Api::V1::Accounts::Conversations::WaflowAgentsController < Api::V1::Accounts::Conversations::BaseController
  def create
    result = WaflowAgents::ExecuteService.new(
      account: Current.account,
      conversation: @conversation,
      rule: nil
    ).perform(
      agent_id: waflow_agent_params[:agent_id],
      mode: waflow_agent_params[:mode],
      extra_context: waflow_agent_params[:extra_context]
    )

    if result[:success]
      render json: { payload: result }, status: :ok
    else
      render json: { error: result[:error_message], payload: result }, status: :unprocessable_entity
    end
  end

  def reset_memory
    result = WaflowAgents::ExecuteService.new(
      account: Current.account,
      conversation: @conversation,
      rule: nil
    ).reset_memory(
      agent_id: waflow_agent_params[:agent_id]
    )

    if result[:success]
      render json: { payload: result }, status: :ok
    else
      render json: { error: result[:error_message], payload: result }, status: :unprocessable_entity
    end
  end

  private

  def waflow_agent_params
    params.permit(:agent_id, :mode, :extra_context)
  end
end
