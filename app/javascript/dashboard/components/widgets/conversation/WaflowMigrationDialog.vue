<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const isMigrating = ref(false);
const errorMessage = ref('');
const slots = ref([]);
const selectedSlotId = ref('');
const resolveSource = ref(false);
const result = ref(null);

const currentSlot = computed(() => slots.value.find(slot => slot.isCurrent));
const availableSlots = computed(() =>
  slots.value.filter(slot => !slot.isCurrent && slot.inboxId)
);
const selectedSlot = computed(() =>
  availableSlots.value.find(slot => String(slot.slotId) === selectedSlotId.value)
);
const canMigrate = computed(
  () => Boolean(selectedSlot.value) && !isLoading.value && !isMigrating.value
);
const hasTargetConversationUrl = computed(() =>
  Boolean(result.value?.targetConversationUrl)
);

const unwrapPayload = response => response?.data?.payload || {};

const buildErrorMessage = error => {
  return (
    error?.response?.data?.error ||
    error?.response?.data?.payload?.error ||
    error?.response?.data?.message ||
    error?.message ||
    t('WAFLOW_MIGRATION.ERRORS.GENERIC')
  );
};

const resetState = () => {
  errorMessage.value = '';
  slots.value = [];
  selectedSlotId.value = '';
  resolveSource.value = false;
  result.value = null;
};

const loadOptions = async () => {
  if (!props.conversationId) return;

  isLoading.value = true;
  errorMessage.value = '';
  result.value = null;

  try {
    const response = await ConversationApi.fetchWaflowMigrationOptions(
      props.conversationId
    );
    const payload = unwrapPayload(response);
    slots.value = Array.isArray(payload.slots) ? payload.slots : [];
    selectedSlotId.value = availableSlots.value.length
      ? String(availableSlots.value[0].slotId)
      : '';
  } catch (error) {
    errorMessage.value = buildErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const open = () => {
  resetState();
  dialogRef.value?.open();
  loadOptions();
};

const close = () => {
  dialogRef.value?.close();
};

const migrate = async () => {
  if (!canMigrate.value) return;

  isMigrating.value = true;
  errorMessage.value = '';

  try {
    const response = await ConversationApi.migrateWaflowConversation({
      conversationId: props.conversationId,
      targetSlotId: selectedSlot.value.slotId,
      resolveSource: resolveSource.value,
    });
    result.value = unwrapPayload(response);
    useAlert(t('WAFLOW_MIGRATION.SUCCESS_TOAST'));
  } catch (error) {
    errorMessage.value = buildErrorMessage(error);
  } finally {
    isMigrating.value = false;
  }
};

const openTargetConversation = () => {
  if (!result.value?.targetConversationUrl) return;
  window.location.href = result.value.targetConversationUrl;
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t('WAFLOW_MIGRATION.TITLE')"
    :description="t('WAFLOW_MIGRATION.DESCRIPTION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="resetState"
  >
    <div class="flex flex-col gap-4">
      <div
        v-if="isLoading"
        class="flex min-h-40 items-center justify-center rounded-xl border border-n-weak bg-n-alpha-1 text-sm text-n-slate-11"
      >
        {{ t('WAFLOW_MIGRATION.LOADING') }}
      </div>

      <div
        v-else-if="errorMessage"
        class="rounded-xl border border-n-ruby-8/40 bg-n-ruby-9/10 p-4 text-sm text-n-ruby-11"
      >
        {{ errorMessage }}
      </div>

      <template v-else>
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="mb-1 text-xs font-medium uppercase text-n-slate-10">
            {{ t('WAFLOW_MIGRATION.CURRENT_CHANNEL') }}
          </p>
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{
              currentSlot?.slotName ||
              t('WAFLOW_MIGRATION.CURRENT_CHANNEL_UNKNOWN')
            }}
          </p>
          <p v-if="currentSlot?.phoneNumber" class="mb-0 mt-1 text-xs text-n-slate-11">
            {{ currentSlot.phoneNumber }}
          </p>
        </div>

        <div class="flex flex-col gap-2">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('WAFLOW_MIGRATION.SELECT_TARGET') }}
          </p>

          <button
            v-for="slot in availableSlots"
            :key="slot.slotId"
            type="button"
            class="flex w-full items-center justify-between gap-3 rounded-xl border p-4 text-left transition"
            :class="
              String(slot.slotId) === selectedSlotId
                ? 'border-n-brand bg-n-brand/10'
                : 'border-n-weak bg-n-alpha-1 hover:border-n-strong'
            "
            @click="selectedSlotId = String(slot.slotId)"
          >
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ slot.slotName }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ slot.phoneNumber || t('WAFLOW_MIGRATION.NO_PHONE') }}
              </span>
            </span>
            <span class="text-xs text-n-slate-10">#{{ slot.inboxId }}</span>
          </button>

          <div
            v-if="!availableSlots.length"
            class="rounded-xl border border-dashed border-n-weak p-5 text-center text-sm text-n-slate-11"
          >
            {{ t('WAFLOW_MIGRATION.NO_CHANNELS') }}
          </div>
        </div>

        <label
          class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-sm text-n-slate-12"
        >
          <input
            v-model="resolveSource"
            type="checkbox"
            class="size-4"
          />
          <span>{{ t('WAFLOW_MIGRATION.RESOLVE_SOURCE') }}</span>
        </label>

        <div
          v-if="result"
          class="rounded-xl border border-n-teal-8/40 bg-n-teal-9/10 p-4 text-sm text-n-teal-11"
        >
          <p class="mb-1 font-medium">
            {{ t('WAFLOW_MIGRATION.RESULT_TITLE') }}
          </p>
          <p class="mb-0">
            {{
              result.createdNewConversation
                ? t('WAFLOW_MIGRATION.CREATED_DESTINATION')
                : t('WAFLOW_MIGRATION.REUSED_DESTINATION')
            }}
          </p>
        </div>
      </template>
    </div>

    <template #footer>
      <div class="flex w-full flex-col gap-3 sm:flex-row sm:justify-end">
        <Button
          variant="faded"
          color="slate"
          :label="t('WAFLOW_MIGRATION.CLOSE')"
          type="button"
          @click="close"
        />
        <Button
          v-if="hasTargetConversationUrl"
          variant="outline"
          color="teal"
          icon="i-lucide-external-link"
          trailing-icon
          :label="t('WAFLOW_MIGRATION.OPEN_TARGET')"
          type="button"
          @click="openTargetConversation"
        />
        <Button
          color="blue"
          icon="i-lucide-route"
          :label="t('WAFLOW_MIGRATION.CONFIRM')"
          :is-loading="isMigrating"
          :disabled="!canMigrate"
          type="button"
          @click="migrate"
        />
      </div>
    </template>
  </Dialog>
</template>
