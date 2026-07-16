<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

const props = defineProps({
  // attributeValues do custom attribute `stage`, na ordem atual do board.
  stages: { type: Array, required: true },
  // { [stage]: quantidade } — usado pra impedir remocao que sumiria com lead.
  counts: { type: Object, default: () => ({}) },
  // Etapas estruturais: a de entrada e a de venda ganha. Renomear/remover
  // quebraria a regra do board (pescar sem estagio / pedir valor do contrato).
  lockedStages: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

const draft = ref([...props.stages]);
const novoNome = ref('');

watch(
  () => props.stages,
  valores => {
    draft.value = [...valores];
  }
);

// Mesma normalizacao do backend: o filtro faz downcase e o SQL aplica LOWER().
// Espaco vira _ pra chave nao ter caractere que atrapalhe.
const toKey = texto =>
  texto
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

const humanize = stage =>
  t(`KANBAN.STAGES.${stage.toUpperCase()}`, stage.replace(/_/g, ' '));

const podeRemover = stage => {
  if (props.lockedStages.includes(stage)) return false;
  return !(props.counts[stage] > 0);
};

const motivoBloqueio = stage => {
  if (props.lockedStages.includes(stage)) return t('KANBAN.EDITOR.LOCKED');
  if (props.counts[stage] > 0)
    return t('KANBAN.EDITOR.HAS_LEADS', { count: props.counts[stage] });
  return '';
};

const erro = ref('');

const adicionar = () => {
  const key = toKey(novoNome.value);
  erro.value = '';
  if (!key) return;
  if (draft.value.includes(key)) {
    erro.value = t('KANBAN.EDITOR.DUPLICATE');
    return;
  }
  draft.value.push(key);
  novoNome.value = '';
};

const remover = stage => {
  if (!podeRemover(stage)) return;
  draft.value = draft.value.filter(s => s !== stage);
};

const mudou = computed(
  () => JSON.stringify(draft.value) !== JSON.stringify(props.stages)
);
</script>

<template>
  <woot-modal :show="true" :on-close="() => emit('close')">
    <div class="flex flex-col w-full p-8 overflow-auto">
      <woot-modal-header
        :header-title="t('KANBAN.EDITOR.TITLE')"
        :header-content="t('KANBAN.EDITOR.SUBTITLE')"
      />

      <Draggable
        v-model="draft"
        item-key="_self"
        tag="ul"
        handle=".arrasta"
        class="flex flex-col gap-2 mt-6"
      >
        <template #item="{ element }">
          <li
            class="flex items-center gap-3 px-3 py-2 list-none border rounded-lg border-n-weak bg-n-solid-1"
          >
            <span class="cursor-grab arrasta i-lucide-grip-vertical size-4 text-n-slate-10" />
            <span class="flex-1 text-sm capitalize text-n-slate-12">
              {{ humanize(element) }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ counts[element] || 0 }}
            </span>
            <button
              class="p-1 rounded-md disabled:opacity-30 disabled:cursor-not-allowed text-n-ruby-10 hover:bg-n-alpha-2"
              :disabled="!podeRemover(element)"
              :title="motivoBloqueio(element) || t('KANBAN.EDITOR.REMOVE')"
              @click="remover(element)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </li>
        </template>
      </Draggable>

      <div class="flex gap-2 mt-4">
        <input
          v-model="novoNome"
          type="text"
          class="flex-1"
          :placeholder="t('KANBAN.EDITOR.NEW_PLACEHOLDER')"
          @keyup.enter="adicionar"
        />
        <woot-button variant="smooth" :disabled="!novoNome.trim()" @click="adicionar">
          {{ t('KANBAN.EDITOR.ADD') }}
        </woot-button>
      </div>
      <p v-if="erro" class="mt-1 text-xs text-n-ruby-10">{{ erro }}</p>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('KANBAN.EDITOR.HINT') }}
      </p>

      <div class="flex items-center justify-end gap-2 mt-8">
        <woot-button variant="clear" @click="emit('close')">
          {{ t('KANBAN.EDITOR.CANCEL') }}
        </woot-button>
        <woot-button
          :is-loading="isSaving"
          :disabled="!mudou"
          @click="emit('save', draft)"
        >
          {{ t('KANBAN.EDITOR.SAVE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
