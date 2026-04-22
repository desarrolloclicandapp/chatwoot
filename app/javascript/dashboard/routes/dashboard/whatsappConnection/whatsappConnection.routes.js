import { frontendURL } from 'dashboard/helper/URLHelper.js';

import WhatsAppConnectionPageRouteView from './pages/WhatsAppConnectionPageRouteView.vue';
import WhatsAppConnectionIndexPage from './pages/WhatsAppConnectionIndexPage.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

const whatsappConnectionRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/whatsapp-connection'),
      component: WhatsAppConnectionPageRouteView,
      children: [
        {
          path: '',
          name: 'whatsapp_connections_index',
          meta,
          component: WhatsAppConnectionIndexPage,
        },
      ],
    },
  ],
};

export default whatsappConnectionRoutes;
