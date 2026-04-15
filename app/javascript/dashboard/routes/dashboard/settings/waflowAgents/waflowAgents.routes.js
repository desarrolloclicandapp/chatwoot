import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import WaflowAgentsHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/waflow-agents'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'waflow_agents_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'waflow_agents_list',
          component: WaflowAgentsHome,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
