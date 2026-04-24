class Api::V1::Accounts::Conversations::WaflowMigrationsController < Api::V1::Accounts::Conversations::BaseController
  def options
    render_proxy_result(service.options)
  end

  def migrate
    render_proxy_result(
      service.migrate(
        target_slot_id: waflow_migration_params[:target_slot_id] || waflow_migration_params[:targetSlotId],
        resolve_source: ActiveModel::Type::Boolean.new.cast(
          waflow_migration_params[:resolve_source] || waflow_migration_params[:resolveSource]
        )
      )
    )
  end

  private

  def service
    @service ||= WaflowConversationMigrations::ProxyService.new(account: Current.account, conversation: @conversation)
  end

  def waflow_migration_params
    params.permit(:target_slot_id, :targetSlotId, :resolve_source, :resolveSource)
  end

  def render_proxy_result(result)
    safe_result = (result || {}).deep_symbolize_keys
    http_status = safe_result.delete(:http_status) || :ok

    if safe_result[:success] == false
      render json: {
        error: safe_result[:error].presence || safe_result[:message].presence || 'Request failed',
        payload: safe_result
      }, status: http_status
    else
      render json: { payload: safe_result }, status: http_status
    end
  end
end
