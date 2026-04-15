import { createStore } from '../storeFactory';
import WaflowAgentsAPI from '../../api/waflowAgents';

export default createStore({
  name: 'waflow_agent',
  API: WaflowAgentsAPI,
});
