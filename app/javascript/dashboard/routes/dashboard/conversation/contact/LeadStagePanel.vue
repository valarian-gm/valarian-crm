<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStageLabels } from 'dashboard/composables/useStageLabels';

// Qualificar o lead sem sair da conversa. O mesmo dado do board: o custom
// attribute `stage` do contato. Aqui e so um atalho visivel — o accordion de
// atributos nativo nasce fechado e ninguem acha.
const props = defineProps({
  contactId: { type: [Number, String], required: true },
});

const store = useStore();
const { t } = useI18n();

const DEFAULT_STAGES = ['novo', 'qualificado', 'cliente', 'nao_responde', 'excluir'];
const WON_STAGE = 'cliente';

const isSaving = ref(false);

const contact = useMapGetter('contacts/getContact');
const contactAttributes = useMapGetter('attributes/getAttributesByModel');

const lead = computed(() => contact.value(props.contactId) || {});

// Atencao: getAttributesByModel NAO cameliza (ao contrario dos getters vizinhos).
const stages = computed(() => {
  const definition = contactAttributes
    .value('contact_attribute')
    ?.find(attribute => attribute.attribute_key === 'stage');
  const values = definition?.attribute_values;
  return values?.length ? values : DEFAULT_STAGES;
});

// `contacts/getContact` vem do state cru: custom_attributes em snake_case.
const custom = computed(() => lead.value.custom_attributes || {});
const stageAtual = computed(() => custom.value.stage || '');
const arquivado = computed(() => Boolean(custom.value.arquivado));

// Mesma fonte de rotulo do board: o estagio nao pode ter dois nomes.
const { stageLabel } = useStageLabels();

// Merge raso no backend: mandar so o que muda preserva utm_*, valor etc.
const patch = async customAttributes => {
  isSaving.value = true;
  try {
    await store.dispatch('contacts/update', {
      id: props.contactId,
      customAttributes,
    });
  } catch (error) {
    useAlert(t('KANBAN.MOVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const mudarStage = async event => {
  const stage = event.target.value;
  if (!stage || stage === stageAtual.value) return;

  if (stage === WON_STAGE && !Number(custom.value.valor_contrato || 0)) {
    const input = window.prompt(t('KANBAN.CONTRACT_VALUE_PROMPT'));
    if (input === null) return;
    const valor = Number(String(input).replace(',', '.')) || 0;
    await patch({ stage, valor_contrato: valor });
  } else {
    await patch({ stage });
  }
  useAlert(t('KANBAN.MOVED', { name: lead.value.name, stage: stageLabel(stage) }));
};

const alternarArquivado = async () => {
  await patch({ arquivado: !arquivado.value });
};
</script>

<template>
  <div class="flex flex-col gap-2 px-3 py-3">
    <div class="flex items-center gap-2">
      <select
        class="flex-1 !mb-0 !h-8 !text-sm"
        :value="stageAtual"
        :disabled="isSaving"
        @change="mudarStage"
      >
        <option value="" disabled>{{ t('KANBAN.PANEL.PICK_STAGE') }}</option>
        <option v-for="stage in stages" :key="stage" :value="stage">
          {{ stageLabel(stage) }}
        </option>
      </select>
      <button
        class="p-1.5 rounded-md shrink-0"
        :class="
          arquivado
            ? 'text-n-slate-11 bg-n-alpha-2'
            : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-10'
        "
        :title="arquivado ? t('KANBAN.RESTORE') : t('KANBAN.LOST_HINT')"
        :disabled="isSaving"
        @click="alternarArquivado"
      >
        <span
          :class="arquivado ? 'i-lucide-undo-2' : 'i-lucide-circle-x'"
          class="size-4"
        />
      </button>
    </div>
    <p v-if="arquivado" class="text-xs text-n-slate-11">
      {{ t('KANBAN.PANEL.ARCHIVED_NOTE') }}
    </p>
  </div>
</template>
