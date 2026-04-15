import ApiClient from './ApiClient';

class WaflowAgentsAPI extends ApiClient {
  constructor() {
    super('waflow_agents', { accountScoped: true });
  }
}

export default new WaflowAgentsAPI();
