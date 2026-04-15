<script setup>
import { computed, onMounted, ref } from 'vue';
import { picoSearch } from '@scmmishra/pico-search';
import { useStoreGetters, useStore } from 'dashboard/composables/store';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const getters = useStoreGetters();

const searchQuery = ref('');

const records = computed(() => getters['waflowAgents/getRecords'].value);
const uiFlags = computed(() => getters['waflowAgents/getUIFlags'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;

  return picoSearch(records.value, query, ['name', 'id']);
});

const loadAgents = () => store.dispatch('waflowAgents/get');

onMounted(() => {
  loadAgents();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    loading-message="Loading Waflow agents..."
    :no-records-found="!records.length"
    no-records-message="No Waflow agents found for this account."
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        title="Waflow Agents"
        description="These agents are managed in Waflow and can be used from Chatwoot automations."
        search-placeholder="Search by name or id"
      >
        <template v-if="records.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ records.length }} linked
          </span>
        </template>
        <template #actions>
          <Button label="Refresh" size="sm" @click="loadAgents" />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <p
        v-if="!filteredRecords.length && searchQuery"
        class="flex items-center justify-center py-20 text-base text-center text-n-slate-11"
      >
        No matching Waflow agents.
      </p>
      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <div
          v-for="agent in filteredRecords"
          :key="agent.id"
          class="flex items-start justify-between gap-4 py-4"
        >
          <div class="flex flex-col gap-1.5">
            <span class="text-heading-3 text-n-slate-12">
              {{ agent.name }}
            </span>
            <div class="flex items-center gap-2 text-body-main text-n-slate-11">
              <span>ID {{ agent.id }}</span>
              <div class="w-px h-3 rounded-lg bg-n-strong" />
              <span>Automation ready</span>
            </div>
          </div>
          <span
            class="px-2.5 py-1 rounded-full text-xs font-medium bg-n-alpha-2 text-n-slate-11"
          >
            Waflow
          </span>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
