<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import inboxMixin from 'shared/mixins/inboxMixin';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';

export default {
  components: {
    LoadingState,
    SettingsFieldSection,
    NextButton,
    SelectInput,
  },
  mixins: [inboxMixin],
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      selectedWaflowAgentId: '',
      selectedWaflowAgentMode: 'suggest',
      isUpdatingWaflowAgentConfig: false,
    };
  },
  computed: {
    ...mapGetters({
      waflowAgents: 'waflowAgents/getRecords',
      waflowAgentUiFlags: 'waflowAgents/getUIFlags',
    }),
    isSpanish() {
      return this.$i18n?.locale === 'es';
    },
    channelLabel() {
      return this.inbox?.name || `Inbox ${this.inbox?.id || ''}`.trim();
    },
    waflowAgentOptions() {
      const options = Array.isArray(this.waflowAgents) ? this.waflowAgents : [];
      return [
        {
          label: this.isSpanish ? 'Sin agente' : 'No agent',
          value: '',
        },
        ...options.map(agent => ({
          label: agent.name || `Agent ${agent.id}`,
          value: String(agent.id),
        })),
      ];
    },
    waflowAgentModeOptions() {
      return [
        {
          label: this.isSpanish
            ? 'Sugerir respuesta'
            : 'Suggest reply',
          value: 'suggest',
        },
        {
          label: this.isSpanish
            ? 'Responder automaticamente'
            : 'Reply automatically',
          value: 'reply',
        },
      ];
    },
    sectionLabel() {
      return this.isSpanish ? 'Agente Waflow' : 'Waflow agent';
    },
    sectionHelpText() {
      return this.isSpanish
        ? 'Elige que agente trabaja en este canal.'
        : 'Choose which agent works in this channel.';
    },
    agentPlaceholder() {
      return this.isSpanish
        ? 'Selecciona un agente'
        : 'Select an agent';
    },
    modePlaceholder() {
      return this.isSpanish
        ? 'Selecciona como responder'
        : 'Select response mode';
    },
    statusText() {
      if (!this.selectedWaflowAgentId) {
        return this.isSpanish
          ? 'Selecciona un agente para activar este canal.'
          : 'Select an agent to activate this channel.';
      }

      if (this.selectedWaflowAgentMode === 'reply') {
        return this.isSpanish
          ? 'Respondera automaticamente a cada mensaje entrante.'
          : 'It will automatically reply to every incoming message.';
      }

      return this.isSpanish
        ? 'Mostrara sugerencias en el compositor.'
        : 'It will show suggestions in the composer.';
    },
    saveLabel() {
      return this.isSpanish ? 'Guardar configuracion' : 'Save settings';
    },
    unsupportedChannelMessage() {
      return this.isSpanish
        ? 'El agente Waflow esta disponible para canales de Waflow Inbox.'
        : 'The Waflow agent is available for Waflow Inbox channels.';
    },
    isFetchingAgents() {
      return !!this.waflowAgentUiFlags?.fetchingList;
    },
    canSave() {
      return this.isAPIInbox && !this.isUpdatingWaflowAgentConfig;
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
  },
  mounted() {
    this.setDefaults();
    this.$store.dispatch('waflowAgents/get');
  },
  methods: {
    setDefaults() {
      this.selectedWaflowAgentId =
        this.inbox.additional_attributes?.waflow_default_agent_id?.toString() ||
        '';
      this.selectedWaflowAgentMode =
        this.inbox.additional_attributes?.waflow_agent_mode || 'suggest';
    },
    async updateWaflowAgentConfig() {
      if (!this.canSave) return;

      this.isUpdatingWaflowAgentConfig = true;
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            additional_attributes: {
              ...(this.inbox.additional_attributes || {}),
              waflow_default_agent_id: this.selectedWaflowAgentId
                ? Number(this.selectedWaflowAgentId)
                : null,
              waflow_agent_mode: this.selectedWaflowAgentMode || 'suggest',
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingWaflowAgentConfig = false;
      }
    },
  },
};
</script>

<template>
  <div class="mx-6 max-w-4xl">
    <LoadingState v-if="isFetchingAgents" />
    <div v-else>
      <div
        v-if="!isAPIInbox"
        class="rounded-xl border border-n-weak bg-n-alpha-2 p-5 text-sm text-n-slate-11"
      >
        {{ unsupportedChannelMessage }}
      </div>
      <form v-else @submit.prevent="updateWaflowAgentConfig">
        <SettingsFieldSection
          :label="sectionLabel"
          :help-text="sectionHelpText"
          class="[&>div]:!items-start"
        >
          <div class="flex flex-col gap-3">
            <div class="rounded-lg border border-n-weak bg-n-alpha-2 px-4 py-3">
              <p class="mb-1 text-xs font-medium uppercase tracking-wide text-n-slate-11">
                {{ isSpanish ? 'Canal activo' : 'Active channel' }}
              </p>
              <p class="mb-0 text-sm font-medium text-n-slate-12">
                {{ channelLabel }}
              </p>
            </div>
            <SelectInput
              v-model="selectedWaflowAgentId"
              :options="waflowAgentOptions"
              :placeholder="agentPlaceholder"
            />
            <SelectInput
              v-model="selectedWaflowAgentMode"
              :options="waflowAgentModeOptions"
              :placeholder="modePlaceholder"
            />
            <p class="mb-0 text-xs text-n-slate-11">
              {{ statusText }}
            </p>
          </div>
          <template #extra>
            <div class="grid grid-cols-1 lg:grid-cols-8 mt-3">
              <div class="col-span-1 lg:col-span-2 invisible" />
              <div class="col-span-1 lg:col-span-6 flex justify-end mx-1">
                <NextButton
                  type="submit"
                  :label="saveLabel"
                  :disabled="!canSave"
                  :is-loading="isUpdatingWaflowAgentConfig"
                />
              </div>
            </div>
          </template>
        </SettingsFieldSection>
      </form>
    </div>
  </div>
</template>
