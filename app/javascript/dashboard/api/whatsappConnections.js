/* global axios */

import ApiClient from './ApiClient';

class WhatsAppConnectionsAPI extends ApiClient {
  constructor() {
    super('whatsapp_connections', { accountScoped: true });
  }

  qr(slotId) {
    return axios.get(`${this.url}/${slotId}/qr`);
  }

  start(slotId) {
    return axios.post(`${this.url}/${slotId}/start`);
  }

  reconnect(slotId) {
    return axios.post(`${this.url}/${slotId}/reconnect`);
  }

  pause(slotId) {
    return axios.post(`${this.url}/${slotId}/pause`);
  }

  disconnect(slotId) {
    return axios.delete(`${this.url}/${slotId}/disconnect`);
  }
}

export default new WhatsAppConnectionsAPI();
