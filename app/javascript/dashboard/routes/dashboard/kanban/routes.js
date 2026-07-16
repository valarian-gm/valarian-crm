import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import KanbanIndex from './pages/KanbanIndex.vue';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent', 'contact_manage'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'kanban_dashboard_index',
    component: KanbanIndex,
    meta: commonMeta,
  },
];
