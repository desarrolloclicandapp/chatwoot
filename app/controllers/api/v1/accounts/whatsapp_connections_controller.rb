class Api::V1::Accounts::WhatsappConnectionsController < Api::V1::Accounts::BaseController
  before_action :require_admin!, only: [:start, :reconnect, :pause, :disconnect]

  def index
    render_proxy_result(service.list)
  end

  def qr
    render_proxy_result(service.qr(slot_id: params[:slot_id]))
  end

  def start
    render_proxy_result(service.start(slot_id: params[:slot_id]))
  end

  def reconnect
    render_proxy_result(service.reconnect(slot_id: params[:slot_id]))
  end

  def pause
    render_proxy_result(service.pause(slot_id: params[:slot_id]))
  end

  def disconnect
    render_proxy_result(service.disconnect(slot_id: params[:slot_id]))
  end

  private

  def service
    @service ||= WaflowWhatsappConnections::ProxyService.new(account: Current.account)
  end

  def require_admin!
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
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
