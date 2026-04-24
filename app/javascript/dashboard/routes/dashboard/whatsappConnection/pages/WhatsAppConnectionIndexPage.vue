<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { emitter } from 'shared/helpers/mitt';
import Button from 'dashboard/components-next/button/Button.vue';
import whatsappConnectionsAPI from 'dashboard/api/whatsappConnections';

const POLL_INTERVAL_MS = 5000;

const { t } = useI18n();
const { isAdmin } = useAdmin();

const isLoading = ref(false);
const isPolling = ref(false);
const actionKey = ref('');
const loadErrorMessage = ref('');
const locationName = ref('');
const slots = ref([]);
const selectedSlotId = ref(null);
const selectedSlotDetails = ref(null);
const pollTimer = ref(null);

const selectedSlot = computed(() => {
  return slots.value.find(slot => slot.slotId === selectedSlotId.value) || null;
});

const activeSlot = computed(() => {
  if (
    selectedSlotDetails.value &&
    selectedSlotDetails.value.slotId === selectedSlotId.value
  ) {
    return {
      ...(selectedSlot.value || {}),
      ...selectedSlotDetails.value,
    };
  }

  return selectedSlot.value;
});

const canPollQr = computed(() => {
  return (
    !!activeSlot.value &&
    activeSlot.value.connectionMode !== 'official_api' &&
    !activeSlot.value.connected &&
    (activeSlot.value.connecting || activeSlot.value.qrReady)
  );
});

const qrImage = computed(() => activeSlot.value?.qrCode || null);

const formatTimestamp = value => {
  if (!value) return '-';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '-';
  return parsed.toLocaleString();
};

const unwrapPayload = response => response?.data?.payload || {};
const unwrapQrPayload = response => response?.data?.payload?.payload || null;

const buildErrorMessage = error => {
  return (
    error?.response?.data?.error ||
    error?.response?.data?.payload?.error ||
    error?.response?.data?.message ||
    error?.message ||
    t('WHATSAPP_CONNECTION.ERRORS.GENERIC')
  );
};

const syncSelectedSlot = () => {
  if (!slots.value.length) {
    selectedSlotId.value = null;
    selectedSlotDetails.value = null;
    return;
  }

  if (!selectedSlot.value) {
    selectedSlotId.value = slots.value[0].slotId;
  }

  if (
    selectedSlotDetails.value &&
    selectedSlotDetails.value.slotId !== selectedSlotId.value
  ) {
    selectedSlotDetails.value = null;
  }
};

const loadConnections = async ({ silent = false } = {}) => {
  if (!silent) isLoading.value = true;

  try {
    const response = await whatsappConnectionsAPI.get();
    const payload = unwrapPayload(response);

    loadErrorMessage.value = '';
    locationName.value = payload.locationName || '';
    slots.value = Array.isArray(payload.slots) ? payload.slots : [];
    syncSelectedSlot();

    if (selectedSlotDetails.value && selectedSlot.value) {
      selectedSlotDetails.value = {
        ...selectedSlot.value,
        ...selectedSlotDetails.value,
      };
    }
  } catch (error) {
    loadErrorMessage.value = buildErrorMessage(error);
    if (!silent) {
      useAlert(loadErrorMessage.value);
    }
  } finally {
    if (!silent) isLoading.value = false;
  }
};

const loadQr = async (slotId, { silent = false } = {}) => {
  if (!slotId) return;

  try {
    const response = await whatsappConnectionsAPI.qr(slotId);
    const payload = unwrapQrPayload(response);
    if (!payload) return;

    selectedSlotDetails.value = {
      ...(selectedSlot.value || {}),
      ...payload,
    };
  } catch (error) {
    if (error?.response?.status === 409) {
      selectedSlotDetails.value = {
        ...(selectedSlot.value || {}),
      };
      return;
    }

    if (!silent) {
      useAlert(buildErrorMessage(error));
    }
  }
};

const pollSelectedSlot = async () => {
  if (isPolling.value) return;

  isPolling.value = true;
  try {
    await loadConnections({ silent: true });

    if (canPollQr.value) {
      await loadQr(selectedSlotId.value, { silent: true });
    }
  } finally {
    isPolling.value = false;
  }
};

const startPolling = () => {
  if (pollTimer.value) clearInterval(pollTimer.value);
  pollTimer.value = setInterval(() => {
    pollSelectedSlot();
  }, POLL_INTERVAL_MS);
};

const stopPolling = () => {
  if (!pollTimer.value) return;
  clearInterval(pollTimer.value);
  pollTimer.value = null;
};

const runAction = async (method, slotId, successKey) => {
  actionKey.value = `${method}:${slotId}`;

  try {
    await whatsappConnectionsAPI[method](slotId);
    useAlert(t(successKey));
    await loadConnections({ silent: true });

    if (selectedSlotId.value === slotId && canPollQr.value) {
      await loadQr(slotId);
    } else if (selectedSlotId.value === slotId) {
      selectedSlotDetails.value = { ...(selectedSlot.value || {}) };
    }
  } catch (error) {
    useAlert(buildErrorMessage(error));
  } finally {
    actionKey.value = '';
  }
};

const handleStart = slotId =>
  runAction('start', slotId, 'WHATSAPP_CONNECTION.SUCCESS.START');

const handleReconnect = slotId =>
  runAction('reconnect', slotId, 'WHATSAPP_CONNECTION.SUCCESS.RECONNECT');

const handlePause = slotId => {
  if (!window.confirm(t('WHATSAPP_CONNECTION.CONFIRM.PAUSE'))) return;
  runAction('pause', slotId, 'WHATSAPP_CONNECTION.SUCCESS.PAUSE');
};

const handleDisconnect = slotId => {
  if (!window.confirm(t('WHATSAPP_CONNECTION.CONFIRM.DISCONNECT'))) return;
  runAction('disconnect', slotId, 'WHATSAPP_CONNECTION.SUCCESS.DISCONNECT');
};

const openGuide = () => {
  emitter.emit('waflow-inbox-guide:open');
};

watch(selectedSlotId, async slotId => {
  selectedSlotDetails.value = null;

  if (!slotId || !selectedSlot.value) return;
  if (selectedSlot.value.connectionMode === 'official_api') return;
  if (selectedSlot.value.qrReady || selectedSlot.value.connecting) {
    await loadQr(slotId, { silent: true });
  }
});

onMounted(async () => {
  await loadConnections();
  startPolling();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full gap-6 p-6 overflow-auto">
    <section class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-2">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CONNECTION.TITLE') }}
        </h1>
        <p class="max-w-3xl text-sm text-n-slate-11">
          {{ t('WHATSAPP_CONNECTION.DESCRIPTION') }}
        </p>
        <span v-if="locationName" class="text-xs text-n-slate-10">
          {{ t('WHATSAPP_CONNECTION.LOCATION') }}: {{ locationName }}
        </span>
      </div>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          icon="i-lucide-refresh-cw"
          outline
          slate
          :label="t('WHATSAPP_CONNECTION.ACTIONS.REFRESH')"
          :is-loading="isLoading"
          @click="loadConnections()"
        />
        <Button
          icon="i-lucide-compass"
          outline
          slate
          :label="t('WAFLOW_INBOX_GUIDE.REPLAY')"
          @click="openGuide"
        />
      </div>
    </section>

    <div
      v-if="loadErrorMessage && !isLoading"
      class="flex items-center justify-center min-h-[16rem] rounded-2xl border
        border-n-ruby-8/40 bg-n-ruby-9/5 px-6 text-center text-sm text-n-ruby-11"
    >
      {{ loadErrorMessage }}
    </div>

    <div
      v-else-if="!slots.length && !isLoading"
      class="flex items-center justify-center min-h-[16rem] rounded-2xl border border-n-weak bg-n-alpha-1 px-6 text-center text-sm text-n-slate-11"
    >
      {{ t('WHATSAPP_CONNECTION.EMPTY') }}
    </div>

    <div
      v-else
      class="grid flex-1 grid-cols-1 gap-6 xl:grid-cols-[minmax(22rem,28rem)_minmax(0,1fr)]"
    >
      <section class="flex flex-col gap-3">
        <article
          v-for="slot in slots"
          :key="slot.slotId"
          class="rounded-2xl border p-4 transition-all cursor-pointer"
          :class="
            slot.slotId === selectedSlotId
              ? 'border-n-brand bg-n-brand/5 shadow-sm'
              : 'border-n-weak bg-n-surface-2 hover:border-n-strong'
          "
          @click="selectedSlotId = slot.slotId"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-base font-medium truncate text-n-slate-12">
                {{ slot.slotName }}
              </h2>
              <p class="text-sm text-n-slate-11">
                {{ slot.phoneNumber || slot.savedNumber || '-' }}
              </p>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="rounded-full px-2.5 py-1 text-xs font-medium"
                :class="
                  slot.connected
                    ? 'bg-n-teal-9/10 text-n-teal-11'
                    : slot.paused
                      ? 'bg-n-amber-9/10 text-n-slate-12'
                      : slot.connecting
                        ? 'bg-n-blue-9/10 text-n-blue-11'
                        : 'bg-n-ruby-9/10 text-n-ruby-11'
                "
              >
                {{ t(`WHATSAPP_CONNECTION.STATES.${slot.state}`) }}
              </span>
              <span class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-11">
                {{ t(`WHATSAPP_CONNECTION.MODES.${slot.connectionMode}`) }}
              </span>
            </div>
          </div>

          <dl class="grid grid-cols-2 gap-3 mt-4 text-xs text-n-slate-11">
            <div>
              <dt class="mb-1 uppercase text-n-slate-10">
                {{ t('WHATSAPP_CONNECTION.INBOX') }}
              </dt>
              <dd class="text-sm text-n-slate-12">
                #{{ slot.inboxId || '-' }}
              </dd>
            </div>
            <div>
              <dt class="mb-1 uppercase text-n-slate-10">
                {{ t('WHATSAPP_CONNECTION.MODE') }}
              </dt>
              <dd class="text-sm text-n-slate-12">
                {{ t(`WHATSAPP_CONNECTION.MODES.${slot.connectionMode}`) }}
              </dd>
            </div>
          </dl>

          <div class="flex flex-wrap gap-2 mt-4">
            <Button
              v-if="slot.canGenerateQr"
              xs
              :disabled="!isAdmin"
              :is-loading="actionKey === `start:${slot.slotId}`"
              :label="t('WHATSAPP_CONNECTION.ACTIONS.START')"
              @click.stop="handleStart(slot.slotId)"
            />
            <Button
              v-if="slot.canReconnect"
              xs
              outline
              :disabled="!isAdmin"
              :is-loading="actionKey === `reconnect:${slot.slotId}`"
              :label="t('WHATSAPP_CONNECTION.ACTIONS.RECONNECT')"
              @click.stop="handleReconnect(slot.slotId)"
            />
            <Button
              v-if="slot.canPause"
              xs
              amber
              faded
              :disabled="!isAdmin"
              :is-loading="actionKey === `pause:${slot.slotId}`"
              :label="t('WHATSAPP_CONNECTION.ACTIONS.PAUSE')"
              @click.stop="handlePause(slot.slotId)"
            />
            <Button
              v-if="slot.canDisconnect"
              xs
              ruby
              outline
              :disabled="!isAdmin"
              :is-loading="actionKey === `disconnect:${slot.slotId}`"
              :label="t('WHATSAPP_CONNECTION.ACTIONS.DISCONNECT')"
              @click.stop="handleDisconnect(slot.slotId)"
            />
          </div>
        </article>
      </section>

      <section
        class="rounded-2xl border border-n-weak bg-n-surface-2 p-5 min-h-[32rem]"
      >
        <div
          v-if="!activeSlot"
          class="flex items-center justify-center h-full text-sm text-center text-n-slate-11"
        >
          {{ t('WHATSAPP_CONNECTION.NO_SELECTION') }}
        </div>

        <template v-else>
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="text-xl font-semibold text-n-slate-12">
                {{ activeSlot.slotName }}
              </h2>
              <p class="mt-1 text-sm text-n-slate-11">
                {{ activeSlot.phoneNumber || activeSlot.savedNumber || '-' }}
              </p>
            </div>
            <div class="flex gap-2">
              <span
                class="rounded-full px-3 py-1.5 text-xs font-medium"
                :class="
                  activeSlot.connected
                    ? 'bg-n-teal-9/10 text-n-teal-11'
                    : activeSlot.paused
                      ? 'bg-n-amber-9/10 text-n-slate-12'
                      : activeSlot.connecting
                        ? 'bg-n-blue-9/10 text-n-blue-11'
                        : 'bg-n-ruby-9/10 text-n-ruby-11'
                "
              >
                {{ t(`WHATSAPP_CONNECTION.STATES.${activeSlot.state}`) }}
              </span>
              <span class="rounded-full bg-n-alpha-2 px-3 py-1.5 text-xs text-n-slate-11">
                {{ t(`WHATSAPP_CONNECTION.MODES.${activeSlot.connectionMode}`) }}
              </span>
            </div>
          </div>

          <div class="grid gap-4 mt-6 md:grid-cols-3">
            <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
              <p class="text-xs uppercase text-n-slate-10">
                {{ t('WHATSAPP_CONNECTION.INBOX') }}
              </p>
              <p class="mt-2 text-base font-medium text-n-slate-12">
                #{{ activeSlot.inboxId || '-' }}
              </p>
            </div>
            <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
              <p class="text-xs uppercase text-n-slate-10">
                {{ t('WHATSAPP_CONNECTION.MODE') }}
              </p>
              <p class="mt-2 text-base font-medium text-n-slate-12">
                {{ t(`WHATSAPP_CONNECTION.MODES.${activeSlot.connectionMode}`) }}
              </p>
            </div>
            <div class="rounded-xl border border-n-weak bg-n-surface-1 p-4">
              <p class="text-xs uppercase text-n-slate-10">
                {{ t('WHATSAPP_CONNECTION.QR_UPDATED_AT') }}
              </p>
              <p class="mt-2 text-base font-medium text-n-slate-12">
                {{ formatTimestamp(activeSlot.qrUpdatedAt) }}
              </p>
            </div>
          </div>

          <div class="mt-6 rounded-2xl border border-dashed border-n-weak bg-n-surface-1 p-6">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h3 class="text-lg font-medium text-n-slate-12">
                  {{ t('WHATSAPP_CONNECTION.QR_TITLE') }}
                </h3>
                <p class="mt-1 text-sm text-n-slate-11">
                  {{
                    activeSlot.connectionMode === 'official_api'
                      ? t('WHATSAPP_CONNECTION.META_NOTE')
                      : t('WHATSAPP_CONNECTION.QR_DESCRIPTION')
                  }}
                </p>
              </div>
              <Button
                v-if="activeSlot.connectionMode !== 'official_api'"
                xs
                outline
                slate
                :label="t('WHATSAPP_CONNECTION.ACTIONS.REFRESH_QR')"
                @click="loadQr(activeSlot.slotId)"
              />
            </div>

            <div
              v-if="qrImage"
              class="flex items-center justify-center mt-6"
            >
              <img
                :src="qrImage"
                :alt="t('WHATSAPP_CONNECTION.QR_ALT')"
                class="w-full max-w-sm rounded-2xl border border-n-weak bg-white p-4"
              />
            </div>
            <div
              v-else
              class="flex items-center justify-center min-h-[18rem] mt-6 rounded-2xl bg-n-alpha-1 px-6 text-center text-sm text-n-slate-11"
            >
              {{
                activeSlot.connectionMode === 'official_api'
                  ? t('WHATSAPP_CONNECTION.META_NOTE')
                  : t('WHATSAPP_CONNECTION.QR_EMPTY')
              }}
            </div>
          </div>
        </template>
      </section>
    </div>
  </div>
</template>
