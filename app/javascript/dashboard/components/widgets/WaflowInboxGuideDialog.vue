<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import { emitter } from 'shared/helpers/mitt';
import { LocalStorage } from 'shared/helpers/localStorage';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const GUIDE_EVENT = 'waflow-inbox-guide:open';

const stepKeys = [
  'WELCOME',
  'CONNECTION_MENU',
  'CONNECT_PHONE',
  'VERIFY_STATUS',
  'CONVERSATIONS',
  'MIGRATION',
];

const { t } = useI18n();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();

const dialogRef = ref(null);
const currentStepIndex = ref(0);

const totalSteps = computed(() => stepKeys.length);
const currentStepNumber = computed(() => currentStepIndex.value + 1);
const currentStepKey = computed(() => stepKeys[currentStepIndex.value]);
const isFirstStep = computed(() => currentStepIndex.value === 0);
const isLastStep = computed(() => currentStepIndex.value === totalSteps.value - 1);
const storageKey = computed(() => `waflow-inbox-guide:v1:${accountId.value}`);

const markSeen = () => {
  if (!accountId.value) return;
  LocalStorage.set(storageKey.value, true);
};

const open = () => {
  currentStepIndex.value = 0;
  dialogRef.value?.open();
};

const close = ({ remember = true } = {}) => {
  if (remember) markSeen();
  dialogRef.value?.close();
};

const next = () => {
  if (isLastStep.value) {
    close();
    return;
  }
  currentStepIndex.value += 1;
};

const back = () => {
  if (isFirstStep.value) return;
  currentStepIndex.value -= 1;
};

const openConnection = () => {
  markSeen();
  dialogRef.value?.close();
  router.push(accountScopedRoute('whatsapp_connections_index'));
};

onMounted(() => {
  emitter.on(GUIDE_EVENT, open);

  if (accountId.value && !LocalStorage.get(storageKey.value)) {
    window.setTimeout(open, 700);
  }
});

onUnmounted(() => {
  emitter.off(GUIDE_EVENT, open);
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    :title="t('WAFLOW_INBOX_GUIDE.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="markSeen"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('WAFLOW_INBOX_GUIDE.SUBTITLE') }}
      </p>
    </template>

    <div class="flex flex-col gap-5">
      <div class="flex items-center justify-between gap-3">
        <span
          class="rounded-full bg-n-brand/10 px-3 py-1 text-xs font-medium text-n-blue-11"
        >
          {{
            t('WAFLOW_INBOX_GUIDE.STEP_COUNTER', {
              current: currentStepNumber,
              total: totalSteps,
            })
          }}
        </span>
        <button
          type="button"
          class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
          @click="close()"
        >
          {{ t('WAFLOW_INBOX_GUIDE.SKIP') }}
        </button>
      </div>

      <div
        class="rounded-2xl border border-n-weak bg-n-alpha-1 p-6"
      >
        <div
          class="mb-5 flex size-12 items-center justify-center rounded-2xl bg-n-brand/10 text-n-blue-11"
        >
          <i class="i-lucide-compass size-6" />
        </div>
        <h3 class="mb-2 text-xl font-semibold text-n-slate-12">
          {{ t(`WAFLOW_INBOX_GUIDE.STEPS.${currentStepKey}.TITLE`) }}
        </h3>
        <p class="mb-0 text-sm leading-6 text-n-slate-11">
          {{ t(`WAFLOW_INBOX_GUIDE.STEPS.${currentStepKey}.BODY`) }}
        </p>
      </div>

      <div class="grid gap-3 sm:grid-cols-3">
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="mb-1 text-xs font-medium uppercase text-n-slate-10">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.WHATSAPP_LABEL') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.WHATSAPP_VALUE') }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="mb-1 text-xs font-medium uppercase text-n-slate-10">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.INBOX_LABEL') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.INBOX_VALUE') }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="mb-1 text-xs font-medium uppercase text-n-slate-10">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.CHANNEL_LABEL') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t('WAFLOW_INBOX_GUIDE.CARDS.CHANNEL_VALUE') }}
          </p>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex w-full flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Button
          variant="outline"
          color="slate"
          icon="i-lucide-smartphone"
          :label="t('WAFLOW_INBOX_GUIDE.OPEN_CONNECTION')"
          type="button"
          @click="openConnection"
        />
        <div class="flex gap-3">
          <Button
            variant="faded"
            color="slate"
            :label="t('WAFLOW_INBOX_GUIDE.BACK')"
            :disabled="isFirstStep"
            type="button"
            @click="back"
          />
          <Button
            color="blue"
            :label="
              isLastStep
                ? t('WAFLOW_INBOX_GUIDE.FINISH')
                : t('WAFLOW_INBOX_GUIDE.NEXT')
            "
            type="button"
            @click="next"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
